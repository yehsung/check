import CryptoKit
import Foundation
import Testing

// v0.3.54 — 판돈 수수료 10%(`20261015120000_duel_fee.sql`)의 **소스 계약**.
//
// 행동(오목·체스 기권 승자 +5/+9/+18 · 패자 그대로 · 무승부 환불 · 재정산 멱등 · 탈퇴 승리 +18 · 장부 = 잔량 · 수수료 소각)은
// 마이그레이션 자신의 §4 프로브(실호출 13건)와 재생 하네스(3회 연속 적용 + 사용자 흉내 테스트 · 뮤턴트 4개 전부 빨강)가 증명했다.
// 여기서 재는 것은 db push 전에 알 수 있는 것이다:
//   ① 수수료 식이 사용자 확정표(3/5/10 → 1/1/2)를 **계산으로** 내는가(정수식을 읽어 직접 계산한다 — 모양이 아니라 값).
//   ② 두 정산 함수의 새 본문이 **정본 + 치환표**와 바이트까지 같은가(Swift 가 치환을 다시 적용한다) — 그리고 그 정본이
//      정말 이 파일 직전의 마지막 정의인가(옛 본문을 베끼면 자리비움·FIDE 무승부 같은 뒤 판의 행동이 조용히 사라진다).
//   ③ §1 이 못 박은 md5 가 정본 본문의 md5 와 같은가(운영 본문 대조의 기준이 틀리면 배포가 엉뚱하게 멈추거나 통과한다).
//   ④ 무승부 환불 · 멱등 가드 · 지갑 키 순서가 치환 밖에 그대로 있는가 · 수수료가 장부에 따로 안 적히는가.
// 하우스 규칙: `--` 주석은 걷어내고 본다(바이트 비교는 원문으로 — 본문 안 주석도 prosrc 의 일부다).

private let dfMigration = "20261015120000_duel_fee.sql"
/// v0.3.64(2026-10-22 사용자 결정 "멀티 미니게임 수수료 다시 제거해줘") — `duel_fee` 를 0 으로 다시 정의한 뒤 파일. 이 파일 뒤에
/// `duel_fee` 를 정의하는 것은 이것 하나뿐이어야 하고, 정산 함수는 다시 정의하지 않는다(그대로 `2*판돈 − duel_fee` 를 준다).
private let dfFeeOffMigration = "20261022142000_duel_fee_off.sql"
private let dfGomokuCanon = "20260916210000_gomoku_timeout_autoplace.sql"
private let dfChessCanon = "20261005160000_chess_duel.sql"

private struct DFError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func dfMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DFError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var visited: [String] = []
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        visited.append(directory.path)
        directory = directory.deletingLastPathComponent()
    }
    throw DFError("supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

private func dfNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(at: try dfMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }.map(\.lastPathComponent).sorted()
}

private func dfRaw(_ name: String) throws -> String {
    let file = try dfMigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else { throw DFError("\(name) 이 없다: \(file.path)") }
    return try String(contentsOf: file, encoding: .utf8)
}

private func dfStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func dfSquash(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

private func dfMatches(_ pattern: String, in text: String, dotAll: Bool = false) throws -> [[String]] {
    var options: NSRegularExpression.Options = [.caseInsensitive, .anchorsMatchLines]
    if dotAll { options.insert(.dotMatchesLineSeparators) }
    let regex = try NSRegularExpression(pattern: pattern, options: options)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}

private func dfCount(_ needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

/// 원문에서 `function public.<name>(` 을 `create` 가 있는 줄에서 정의하는 **마지막** 자리의 `as $fn$ … $fn$` 본문(원문 바이트).
private func dfBody(_ name: String, in raw: String) -> String? {
    var last: Range<String.Index>?
    var searchStart = raw.startIndex
    while let found = raw.range(of: "function public.\(name)(", range: searchStart..<raw.endIndex) {
        let lineStart = raw[raw.startIndex..<found.lowerBound].lastIndex(of: "\n").map { raw.index(after: $0) } ?? raw.startIndex
        let prefix = dfStrip(String(raw[lineStart..<found.lowerBound]))
        if prefix.lowercased().contains("create") { last = found }
        searchStart = found.upperBound
    }
    guard let header = last, let open = raw.range(of: "as $fn$", range: header.upperBound..<raw.endIndex),
          let close = raw.range(of: "$fn$", range: open.upperBound..<raw.endIndex) else { return nil }
    return String(raw[open.upperBound..<close.lowerBound])
}

/// 체인에서 `public.<name>(` 을 정의하는 파일들(적용 순).
private func dfDefiningFiles(_ name: String) throws -> [String] {
    try dfNames().filter { file in
        let sql = dfStrip(try dfRaw(file)).lowercased()
        return try !dfMatches(#"create\s+(?:or\s+replace\s+)?function\s+public\."# + name + #"\s*\("#, in: sql).isEmpty
    }
}

/// §1 치환표 `('<fn>', <seq>, $patch$OLD$patch$, $patch$NEW$patch$)` — 원문 그대로(줄 끝까지 바이트).
private func dfPatches(_ raw: String) throws -> [(fn: String, seq: Int, old: String, new: String)] {
    try dfMatches(#"\('([a-z_]+)',\s*([0-9]+),\s*\$patch\$(.*?)\$patch\$,\s*\$patch\$(.*?)\$patch\$\)"#, in: raw, dotAll: true)
        .map { ($0[1], Int($0[2]) ?? -1, $0[3], $0[4]) }
}

private func dfMD5(_ text: String) -> String {
    Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// `do $tag$ … $tag$` 블록(원문).
private func dfBlock(_ raw: String, tag: String) throws -> String {
    guard let open = raw.range(of: "do \(tag)") else { throw DFError("\(tag) 블록이 없다") }
    guard let close = raw.range(of: tag, range: open.upperBound..<raw.endIndex) else { throw DFError("\(tag) 가 안 닫힌다") }
    return String(raw[open.upperBound..<close.lowerBound])
}

@Suite("판돈 수수료 10% — 마이그레이션 소스 계약(20261015120000)")
struct V0354DuelFeeMigrationTests {

    // MARK: ① 수수료 식 — 읽어서 계산한다

    @Test("duel_fee 정수식을 읽어 계산하면 판돈 3/5/10 → 수수료 1/1/2 · 승자 수령 5/9/18 · 순이익 +2/+4/+8 (옛 식 6/10/20 과 갈린다)")
    func feeFormulaComputesTheConfirmedTable() throws {
        let sql = dfStrip(try dfRaw(dfMigration))
        let found = try dfMatches(
            #"create\s+or\s+replace\s+function\s+public\.duel_fee\s*\(\s*p_stake\s+int\s*\)\s*returns\s+int\s+language\s+sql\s+immutable\s+as\s+\$fn\$\s*select\s+\(\s*2\s*\*\s*p_stake\s*\*\s*([0-9]+)\s*\+\s*([0-9]+)\s*\)\s*/\s*([0-9]+)\s*\$fn\$"#,
            in: sql)
        #expect(found.count == 1, "duel_fee 정의를 \(found.count)개 읽었다(기대 1 — 모양이 바뀌었으면 이 파서를 고쳐라)")
        let row = try #require(found.first)
        let (percent, half, scale) = (try #require(Int(row[1])), try #require(Int(row[2])), try #require(Int(row[3])))
        let fee: (Int) -> Int = { stake in (2 * stake * percent + half) / scale }

        // 판돈은 서버 상수의 가장 나중 정의에서 읽는다(손으로 적은 3/5/10 이 서버와 갈리면 이 표가 거짓이 된다).
        for name in ["gomoku_stakes", "chess_stakes"] {
            var latest: [Int]?
            for file in try dfNames() {
                let text = dfStrip(try dfRaw(file))
                for match in try dfMatches(#"function\s+public\."# + name + #"\s*\(\s*\)\s*returns\s+int\[\]\s+language\s+sql\s+immutable\s+as\s+\$[a-z_]*\$\s*select\s+array\[([0-9,\s]+)\]"#, in: text) {
                    latest = match[1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                }
            }
            #expect(latest == [3, 5, 10], "\(name) 의 가장 나중 정의가 \(String(describing: latest)) 다 — 수수료 표(사용자 확정)는 3/5/10 에 대한 것이다")
        }
        let stakes = [3, 5, 10]
        #expect(stakes.map(fee) == [1, 1, 2], "수수료가 \(stakes.map(fee)) 다(사용자 확정 1/1/2)")
        #expect(stakes.map { 2 * $0 - fee($0) } == [5, 9, 18], "승자 수령이 5/9/18 이 아니다")
        #expect(stakes.map { $0 - fee($0) } == [2, 4, 8], "순이익이 +2/+4/+8 이 아니다")
        #expect(stakes.map { 2 * $0 } != stakes.map { 2 * $0 - fee($0) }, "기준선: 옛 지급(2×판돈)과 같다 — 수수료가 0 이다")
        // 식의 뜻 = 판(2×판돈)의 반올림 10%. 판돈 1…100 전부에서 다른 정수식과 같은 값을 낸다(어느 판돈이 더 생겨도 뜻이 같다).
        for stake in 1...100 {
            #expect(fee(stake) == (2 * stake + 5) / 10, "판돈 \(stake): \(fee(stake)) ≠ 반올림 10% \((2 * stake + 5) / 10)")
        }
    }

    @Test("duel_fee 는 이 파일에서 한 번만 create or replace 되고 실행권 줄이 없다(PUBLIC 회수 = 소유자가 다른 definer 의 42501) · 뒤에는 수수료 0 파일 하나뿐")
    func feeFunctionKeepsPublicExecute() throws {
        let sql = dfStrip(try dfRaw(dfMigration))
        let defining = try dfDefiningFiles("duel_fee")
        // v0.3.64: 체인의 마지막 정의는 수수료 0 파일이다(그 파일이 값 0 · ACL 그대로를 스스로 단언한다). 이 파일은 그 앞의 역사다.
        #expect(defining == [dfMigration, dfFeeOffMigration], "duel_fee 를 정의하는 파일이 \(defining) 다")
        let off = dfStrip(try dfRaw(dfFeeOffMigration))
        #expect(try dfMatches(#"create\s+or\s+replace\s+function\s+public\.duel_fee\s*\(\s*p_stake\s+int\s*\)\s*returns\s+int\s+language\s+sql\s+immutable\s+as\s+\$fn\$\s*select\s+0\s*\$fn\$"#,
                                in: off).count == 1, "\(dfFeeOffMigration) 의 duel_fee 가 '언제나 0' 이 아니다")
        #expect(try dfMatches(#"^\s*(revoke|grant)\b[^;]*duel_fee"#, in: off).isEmpty, "수수료 0 파일이 duel_fee 실행권을 다시 적는다")
        for fn in ["gomoku__settle", "chess__settle", "tetris__settle"] {
            #expect(try dfDefiningFiles(fn).last != dfFeeOffMigration, "수수료 0 파일이 \(fn) 을 다시 정의했다(명세: 정산은 그대로)")
        }
        #expect(try dfMatches(#"^\s*(revoke|grant)\b[^;]*duel_fee"#, in: sql).isEmpty, "duel_fee 의 실행권을 다시 적는다")
        #expect(try dfMatches(#"^\s*drop\s+function\s+(?:if\s+exists\s+)?public\."#, in: sql).isEmpty, "public 함수를 drop 한다 — ACL·주석을 버린다")
        #expect(!dfSquash(sql).contains("function public.gomoku_stakes") && !dfSquash(sql).contains("function public.chess_stakes"),
                "판돈 상수를 다시 정의한다(V0351 상수 파서 · 사용자 결정 '판돈 그대로')")
        // 사후 단언이 PUBLIC 실행권을 뜻으로 되묻는다.
        let post = try dfBlock(try dfRaw(dfMigration), tag: "$post$")
        #expect(post.contains("has_function_privilege('public', 'public.duel_fee(integer)', 'EXECUTE')"))
    }

    // MARK: ② 정본 + 치환 = 새 본문(바이트)

    @Test("두 정산 함수의 새 본문 = 직전 마지막 정의(정본) + 치환표 — Swift 가 치환을 다시 적용해 바이트로 대조한다")
    func settleBodiesAreCanonicalPlusPatches() throws {
        let raw = try dfRaw(dfMigration)
        let patches = try dfPatches(raw)
        #expect(patches.count == 6, "치환표가 \(patches.count)줄이다(기대 6 = 함수 둘 × 선언·지급·장부)")
        let names = try dfNames()
        let mine = try #require(names.firstIndex(of: dfMigration), "\(dfMigration) 이 체인에 없다")
        for (fn, canonFile) in [("gomoku__settle", dfGomokuCanon), ("chess__settle", dfChessCanon)] {
            // 정본 = 이 파일 **앞**에서 그 함수를 마지막으로 정의한 파일(옛 본문을 베끼면 뒤 판의 행동이 사라진다).
            let before = try dfDefiningFiles(fn).filter { (names.firstIndex(of: $0) ?? .max) < mine }
            #expect(before.last == canonFile, "\(fn) 의 직전 마지막 정의가 \(String(describing: before.last)) 다(기대 \(canonFile))")
            let canon = try #require(dfBody(fn, in: try dfRaw(canonFile)), "\(canonFile) 에서 \(fn) 본문을 못 떴다")
            let mineBody = try #require(dfBody(fn, in: raw), "\(dfMigration) 에서 \(fn) 본문을 못 떴다")
            var expected = canon
            for patch in patches where patch.fn == fn {
                #expect(dfCount(patch.old, in: canon) == 1, "\(fn)#\(patch.seq): 정본에 old 가 \(dfCount(patch.old, in: canon))회")
                #expect(!patch.new.contains(patch.old), "\(fn)#\(patch.seq): new 가 old 를 품는다 — 재적용 갈래 판정이 무의미해진다")
                #expect(!patch.old.contains("refund"), "\(fn)#\(patch.seq): 치환이 무승부 환불 갈래를 건드린다")
                expected = expected.replacingOccurrences(of: patch.old, with: patch.new)
            }
            #expect(patches.filter { $0.fn == fn }.map(\.seq) == [1, 2, 3], "\(fn) 의 치환 번호가 1·2·3 이 아니다")
            #expect(mineBody == expected, "\(fn) 의 새 본문이 정본 + 치환과 다르다 — 치환 밖을 건드렸다")
            #expect(mineBody != canon, "기준선: 새 본문이 정본과 같다 — 이 파일은 아무것도 안 바꿨다")
            // 이 파일이 그 함수의 체인 마지막 정의다(뒤에서 누가 옛 식으로 되돌리면 여기가 빨갛다).
            #expect(try dfDefiningFiles(fn).last == dfMigration, "\(fn) 의 가장 나중 정의가 이 파일이 아니다 — 뒤 파일이 다시 정의했다")

            // ③ §1 의 정본 md5 · §3 의 새 본문 md5 가 실제 본문의 md5 다(운영 대조 기준이 맞다).
            let pre = try dfBlock(raw, tag: "$pre$")
            #expect(pre.contains("'\(fn)'") && pre.contains(dfMD5(canon)), "\(fn): §1 이 못 박은 정본 md5 가 정본 본문의 md5(\(dfMD5(canon)))가 아니다")
            #expect(try dfBlock(raw, tag: "$post$").contains(dfMD5(mineBody)), "\(fn): §3 이 못 박은 새 본문 md5 가 실제 새 본문의 것이 아니다")
        }
    }

    // MARK: ④ 지급식 · 장부 한 행 · 환불 · 멱등 · 잠금

    @Test("승리 갈래만 2×판돈 − duel_fee 를 주고 장부는 prize 한 행(gross·fee) — 환불·멱등 가드·지갑 키 순서는 그대로")
    func payoutLedgerRefundAndGuards() throws {
        let raw = try dfRaw(dfMigration)
        for (fn, game, a, b) in [("gomoku__settle", "gomoku", "v_black", "v_white"), ("chess__settle", "chess", "v_white", "v_black")] {
            let body = dfSquash(dfStrip(try #require(dfBody(fn, in: raw))))
            #expect(dfCount("v_fee := public.duel_fee(v_stake);", in: body) == 1, "\(fn): 수수료 계산이 한 번이 아니다")
            let fee = try #require(body.range(of: "v_fee := public.duel_fee(v_stake);"))
            let pay = try #require(body.range(of: "set ruby_balance = ruby_balance + 2 * v_stake - v_fee where id = v_winner"),
                                   "\(fn): 승자 지급이 2×판돈 − 수수료가 아니다")
            #expect(fee.upperBound <= pay.lowerBound, "\(fn): 수수료를 지급 뒤에 계산한다")
            #expect(body.contains("'prize:\(game):' || p_match_id::text, 2 * v_stake - v_fee, v_bal"), "\(fn): 승리 장부 delta 가 지급과 다르다")
            #expect(body.contains("'gross', 2 * v_stake, 'fee', v_fee"), "\(fn): 승리 장부 detail 에 gross·fee 가 없다")
            #expect(!body.contains("2 * v_stake, v_bal"), "\(fn): 옛 지급(2×판돈) 장부가 남았다")
            // 수수료를 따로 적는 차감 행을 만들지 않는다(장부 한 행 — reason CHECK·grant_once·클라 무변화).
            #expect(!body.contains("spend:\(game):fee"), "\(fn): 수수료를 따로 적는 장부 행이 생겼다")
            // 무승부 환불 = 판돈 그대로(수수료 없음) · 멱등 가드 · 지갑 키 least → greatest.
            #expect(dfCount("set ruby_balance = ruby_balance + v_stake where id = v_u", in: body) == 1, "\(fn): 무승부 환불이 판돈 그대로가 아니다")
            #expect(body.contains("'grant:\(game):refund:' || p_match_id::text, v_stake, v_bal"), "\(fn): 환불 장부가 바뀌었다")
            #expect(body.contains("where g.id = p_match_id and g.status = 'active'") && body.contains("if not found then return false; end if;"),
                    "\(fn): 멱등 가드가 사라졌다 — 상금이 두 번 나간다")
            let least = try #require(body.range(of: "pg_advisory_xact_lock(hashtext('ultra_wallet:' || least(\(a), \(b))::text))"))
            let greatest = try #require(body.range(of: "pg_advisory_xact_lock(hashtext('ultra_wallet:' || greatest(\(a), \(b))::text))"))
            let update = try #require(body.range(of: "update public.\(game)_matches g"))
            #expect(least.upperBound <= greatest.lowerBound && greatest.upperBound <= update.lowerBound,
                    "\(fn): 지갑 키를 least → greatest → 행 갱신 순서로 잡지 않는다")
        }
    }

    // MARK: ⑤ 손대지 않는 것

    @Test("이 파일은 duel_fee 와 두 정산 함수만 정의하고 표·실행권·탈퇴 함수는 안 건드린다")
    func touchesNothingElse() throws {
        let sql = dfStrip(try dfRaw(dfMigration))
        let defined = Set(try dfMatches(#"^\s*create\s+(?:or\s+replace\s+)?function\s+public\.([a-z_0-9]+)\s*\("#, in: sql).map { $0[1] })
        #expect(defined == ["duel_fee", "gomoku__settle", "chess__settle"], "이 파일이 정의하는 public 함수가 \(defined.sorted()) 다")
        let flat = dfSquash(sql)
        for forbidden in ["alter table public.", "create table public.", "create table if not exists public.", "drop table public.",
                          "drop table if exists public.", "create policy", "revoke all on function public.gomoku__settle", "revoke all on function public.chess__settle",
                          "grant execute on function public.gomoku__settle", "grant execute on function public.chess__settle"] {
            #expect(!flat.contains(forbidden), "이 파일이 '\(forbidden)' 을 한다")
        }
        // 탈퇴 정산은 정의를 안 바꾸고도 수수료를 낸다 — 마지막 delete_my_account 가 두 settle 을 부른다.
        let lastDelete = try #require(try dfDefiningFiles("delete_my_account").last)
        #expect(lastDelete != dfMigration)
        let deleteBody = dfSquash(dfStrip(try #require(dfBody("delete_my_account", in: try dfRaw(lastDelete)))))
        #expect(deleteBody.contains("perform public.gomoku__settle(") && deleteBody.contains("perform public.chess__settle("),
                "delete_my_account(\(lastDelete))가 정산 함수를 안 부른다 — '탈퇴 승리도 수수료' 가 거짓이 된다")
    }

    // MARK: ⑥ 파일 위생 · 프로브

    @Test("순서 · do 블록 · 달러 태그 · RESET ROLE · 최상위 트랜잭션 · notify · 프로브가 사용자 경로를 실호출하고 센티널로 롤백")
    func hygieneAndProbe() throws {
        let names = try dfNames()
        #expect(names.count > 100, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
        let mine = try #require(names.firstIndex(of: dfMigration))
        for source in [dfGomokuCanon, dfChessCanon, "20261014120000_ruby_economy_v2.sql", "20261014130000_phone_work.sql"] {
            #expect(try #require(names.firstIndex(of: source), "\(source) 이 체인에 없다") < mine, "\(source) 가 이 파일보다 뒤다")
        }
        let raw = try dfRaw(dfMigration)
        let sql = dfStrip(raw)
        let tags = try dfMatches(#"^do\s+(\$[a-z_0-9]+\$)"#, in: raw).map { $0[1] }
        #expect(tags == ["$pre$", "$post$", "$probe$"], "do 블록 구성이 \(tags) 다")
        for tag in tags {
            #expect(dfCount(tag, in: raw) == 2, "\(tag) 가 원문에 \(dfCount(tag, in: raw))회 — 주석에 태그 글자를 적으면 본문이 거기서 끝난다")
            for line in try dfBlock(raw, tag: tag).split(separator: "\n") {
                if let dash = line.range(of: "--") { #expect(!line[dash.upperBound...].contains("$"), "\(tag) 블록 주석에 '$': \(line)") }
            }
        }
        #expect(!sql.lowercased().contains("reset role"), "RESET ROLE — CLI 링크드 연결은 세션 사용자로 떨어져 42501")
        for line in sql.split(separator: "\n") where ["begin;", "commit;", "rollback;"].contains(line.trimmingCharacters(in: .whitespaces).lowercased()) {
            Issue.record("최상위 트랜잭션 제어: \(line)")
        }
        let lastLine = sql.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
        #expect(lastLine == "notify pgrst, 'reload schema';", "파일 끝이 notify pgrst 가 아니다(새 함수 duel_fee)")

        let probe = dfSquash(dfStrip(try dfBlock(raw, tag: "$probe$")))
        for token in ["v_expected constant int := 13", "v_exec_role text := current_user",
                      "v_res := public.gomoku_resign(1, v_g);", "v_res := public.chess_resign(1, v_g);",
                      "perform public.delete_my_account();", "public.gomoku__settle(v_g, 'draw', 'board_full')",
                      "public.chess__settle(v_g, 'draw', 'agreement')", "v_stakes int[] := array[3, 5, 10];",
                      "v_fees int[] := array[1, 1, 2];", "execute format('set local role %i', v_exec_role);",
                      "raise exception 'duel_fee_probe_rollback';", "if sqlerrm <> 'duel_fee_probe_rollback' then raise; end if;"] {
            #expect(probe.contains(token), "프로브에 '\(token)' 이 없다")
        }
    }
}
