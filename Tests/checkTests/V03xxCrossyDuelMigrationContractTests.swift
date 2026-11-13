import Foundation
import Testing
@testable import CheckCore

// 1:1 길건너(crossy_duel) — **서버 초안 ↔ 앱 글자 대조**(CD/SPEC.md §10.2 T `V03xxCrossyDuelMigrationContractTests` · §9.5 #27).
//
// 스텁 서버 시험은 서버가 **무엇을 부르고 무엇을 내는지**를 앱이 적은 대로 가정한다 — 이름 한 글자가 갈려도 전부 초록이다
// (메모리 stub-tests-hide-roundtrip-bugs). 그래서 초안 **원문**과 앱 상수를 맞댄다(C 의 FixtureContract 가 이미 재는 요청 본문 키 ·
// DEFAULT · status 어휘 · 봉투 키는 여기서 되풀이하지 않는다):
//   ① 클라 RPC 집합 = 초안 §10 실행권 계약 표의 `rpc` 줄 = `CrossyDuelWire.RPC.all` · 초안이 정의한 crossy_duel 함수 전부가 그 표에 있다 ·
//      두 밑줄 내부 함수는 클라 실행권 0(`internal`) · 함수마다 정의 하나(오버로드 0 — PGRST203)
//   ② `realtime.send(…, '<이벤트>', …)` 글자 = `RealtimeLinkConstants.crossyDuelBroadcastEvent`(링 라우팅의 짝 — Wiring 시험)
//   ③ `crossy_duel_protocol()` = `CrossyDuelWire.protocolVersion` · `crossy_duel_stakes()` = `CrossyDuelStake.allCases` · 머리 함수 하나(V0351)
//   ④ 남의 머리 정의 0 — `gomoku`(V0341) · `tetris_`(TetrisOneWriter) · `minigame_`(V0367) · `duel_fee`(V0354)
//   ⑤ 매분 일은 `cron_minutely_steps` 한 줄(자리 39 · 5000ms) · 하루 청소 cron 하나(18:55 UTC)
//   ⑥ `daily_crossy_duel` 정의 줄 = `DailyMissionStatus.key(game: "crossy_duel")` · 제목에 게임 이름(`CrossyDuelNoticeText.gameName`)
//   ⑦ 조각 치환 앵커가 체인(초안 앞 파일)에 실제로 있는 글자이고, 표지는 체인에 없는 새 글자다(멱등 가드가 일하는 전제).
//      ★ 앵커 일부는 앞선 게임(아잉 마작 D22)이 **조각 치환으로** 넣은 글자라 체인의 마지막 `create or replace` 본문에는 없다 —
//      그 조각들까지 재생해 "적용 결과"를 Swift 로 재는 일은 하지 않는다(그 결과는 하네스 e_canon · h_tamper 가 실제 Postgres 에서 잰다).
//
// 초안 위치: `CROSSY_DUEL_MIGRATION_SQL=<파일>` → 없으면 조상의 `supabase/migrations/20261109150000_crossy_duel.sql`.
// `CROSSY_DUEL_REQUIRE_MIGRATION=1` 이면 없을 때 건너뛰지 않고 빨갛다. 체인은 다른 마이그레이션 시험과 같은 길
// (`CHECK_MIGRATIONS_DIR` → 조상의 `supabase/migrations`) — 이 초안 **앞** 이름의 파일만 본다.

private let cmcMigrationName = "20261109150000_crossy_duel.sql"

private struct CMCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func cmcMigrationURL() -> URL? {
    let fileManager = FileManager.default
    if let path = ProcessInfo.processInfo.environment["CROSSY_DUEL_MIGRATION_SQL"], !path.isEmpty {
        return fileManager.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations/\(cmcMigrationName)")
        if fileManager.fileExists(atPath: candidate.path) { return candidate }
        directory.deleteLastPathComponent()
    }
    return nil
}

private let cmcMigrationRequired = ProcessInfo.processInfo.environment["CROSSY_DUEL_REQUIRE_MIGRATION"] == "1"
/// 돌아야 하는가 — 파일이 있거나, 없으면 빨개져야 할 때(REQUIRE).
private let cmcMigrationGate = cmcMigrationURL() != nil || cmcMigrationRequired

private func cmcRaw() throws -> String {
    guard let url = cmcMigrationURL() else {
        throw CMCError("""
            길건너 1:1 초안이 없다(CROSSY_DUEL_MIGRATION_SQL=\(ProcessInfo.processInfo.environment["CROSSY_DUEL_MIGRATION_SQL"] ?? "(없음)")) \
            — CROSSY_DUEL_REQUIRE_MIGRATION=1 이라 건너뛰지 않는다
            """)
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// `--` 줄 주석을 걷는다(하우스 규칙). 조각·앵커는 함수 본문 글자 그대로라 ⑦ 은 원문으로 본다.
private func cmcStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func cmcChainDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CMCError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        directory.deleteLastPathComponent()
    }
    throw CMCError("체인(supabase/migrations)을 못 찾았다 — 워크트리라면 supabase 심링크나 CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

/// 체인에서 이 초안 **앞** 파일들의 원문(이름 순).
private func cmcChainText() throws -> String {
    let directory = try cmcChainDirectory()
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".sql") && $0 < cmcMigrationName }
        .sorted()
    guard !names.isEmpty else { throw CMCError("체인(\(directory.path))이 비었다") }
    return try names.map { try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8) }.joined(separator: "\n")
}

private func cmcMatches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) throws -> [[String]] {
    let regex = try NSRegularExpression(pattern: pattern, options: options)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}

private func cmcCount(_ needle: String, in text: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    return text.components(separatedBy: needle).count - 1
}

/// 초안 §10 실행권 계약 표(`do $cd_acl$`)의 줄: 함수 이름 → 종류(rpc · const · internal · policy).
private func cmcACL(_ sql: String) throws -> [(name: String, kind: String)] {
    guard let open = sql.range(of: "do $cd_acl$"),
          let close = sql.range(of: "$cd_acl$", range: open.upperBound..<sql.endIndex) else {
        throw CMCError("do $cd_acl$ 블록이 없다 — §10 실행권 계약 표가 사라졌거나 이름이 바뀌었다")
    }
    let block = String(sql[open.upperBound..<close.lowerBound])
    return try cmcMatches(#"array\['public\.([a-z0-9_]+)\([^']*\)',\s*'(rpc|const|internal|policy)'\]"#, in: block)
        .map { ($0[1], $0[2]) }
}

private struct CMCSplice {
    let function: String
    let anchor: String
    let fragment: String
    let after: Bool
    let marker: String
}

/// `do $<tag>$ … $<tag>$` 블록 안 `v_spec` 의 조각 행(원문).
private func cmcSplices(_ raw: String, block tag: String) throws -> [CMCSplice] {
    guard let open = raw.range(of: "do $\(tag)$"),
          let close = raw.range(of: "$\(tag)$", range: open.upperBound..<raw.endIndex) else {
        throw CMCError("do $\(tag)$ 블록이 없다 — 조각 치환 절이 사라졌거나 이름이 바뀌었다")
    }
    let block = String(raw[open.upperBound..<close.lowerBound])
    let pattern = #"array\[\s*'([^']+)'\s*,\s*\$frag\$(.*?)\$frag\$\s*,\s*\$frag\$(.*?)\$frag\$\s*,\s*'(after|before)'\s*,\s*\$frag\$(.*?)\$frag\$\s*\]"#
    return try cmcMatches(pattern, in: block, options: [.dotMatchesLineSeparators]).map {
        CMCSplice(function: $0[1], anchor: $0[2], fragment: $0[3], after: $0[4] == "after", marker: $0[5])
    }
}

@Suite("1:1 길건너 마이그레이션 계약 — 서버 초안 글자 = 앱 글자")
struct V03xxCrossyDuelMigrationContractTests {

    /// 없으면: 초안을 못 찾을 때 아래 시험이 전부 조용히 건너뛰어 "초록"으로 보인다 — REQUIRE 가 켜져 있으면 여기서 빨갛다.
    @Test("초안 관문: CROSSY_DUEL_REQUIRE_MIGRATION=1 이면 초안이 있어야 한다(건너뜀 0)", .enabled(if: cmcMigrationRequired))
    func theDraftIsPresentWhenRequired() throws {
        #expect(cmcMigrationURL() != nil, "CROSSY_DUEL_MIGRATION_SQL 이 가리키는 초안이 없다")
        #expect(try cmcRaw().contains("crossy_duel_report"))
    }

    /// ① 없으면: 앱이 부르는 이름이 서버에 없거나(오타 — 모든 버튼이 404), 서버가 클라 함수를 하나 더 열어 두거나, 내부 함수(정산 ·
    /// 무효 · 준비)에 authenticated 실행권이 남아 클라가 남의 판을 정산해도 스텁 시험은 초록이다.
    @Test(.enabled(if: cmcMigrationGate))
    func theClientRPCSetMatchesTheWireAndInternalsStayClosed() throws {
        let sql = cmcStrip(try cmcRaw())
        let acl = try cmcACL(sql)
        #expect(acl.count == 47, "§10 계약 표가 \(acl.count)줄이다(초안 머리 단언 47 과 같아야 한다)")
        let rpc = Set(acl.filter { $0.kind == "rpc" }.map(\.name))
        #expect(rpc == Set(CrossyDuelWire.RPC.all), "클라 RPC: 초안 \(rpc.sorted()) ≠ 앱 \(CrossyDuelWire.RPC.all.sorted())")
        #expect(CrossyDuelWire.RPC.all.count == 8 && Set(CrossyDuelWire.RPC.all).count == 8)
        // 두 밑줄 내부 함수는 전부 internal(클라 실행권 0) — 하나라도 rpc/const 면 클라가 직접 부른다.
        let defined = try cmcMatches(#"create\s+or\s+replace\s+function\s+public\.(crossy_duel[a-z0-9_]*)\s*\("#, in: sql,
                                     options: [.caseInsensitive]).map { $0[1].lowercased() }
        let kinds = Dictionary(acl.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
        for name in defined where name.hasPrefix("crossy_duel__") {
            #expect(kinds[name] == "internal", "\(name) 이 internal 이 아니다(\(kinds[name] ?? "표에 없음"))")
        }
        // 초안이 정의한 crossy_duel 함수 전부가 표에 있다(표에 없으면 기본 PUBLIC 실행권이 그대로 남는다) · 정의는 하나씩.
        #expect(Set(defined) == Set(acl.map(\.name)), "정의 \(Set(defined).symmetricDifference(Set(acl.map(\.name))).sorted()) 가 표와 갈린다")
        let overloads = Dictionary(grouping: defined, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        #expect(overloads.isEmpty, "같은 이름 정의가 둘 이상이다(PGRST203): \(overloads)")
        // ★ 기준선: 판 정산 함수는 표에 internal 로 있다(위 반복이 실제로 무언가를 잰다).
        #expect(kinds["crossy_duel__settle"] == "internal" && kinds["crossy_duel_settle_expired"] == "internal")
    }

    /// ② 없으면: 서버가 다른 글자로 초인종을 울려도(예: 'crossy-duel') 앱 링은 그것을 drain 으로 접고 스텁 시험은 초록이다.
    @Test(.enabled(if: cmcMigrationGate))
    func theDoorbellEventIsTheAppConstant() throws {
        let sql = cmcStrip(try cmcRaw())
        let events = try cmcMatches(#"perform\s+realtime\.send\((?:[^;]*?)\)\s*,\s*'([a-z_:-]+)'"#, in: sql,
                                    options: [.dotMatchesLineSeparators]).map { $0[1] }
        #expect(!events.isEmpty, "초안에 realtime.send 초인종이 없다")
        #expect(Set(events) == [RealtimeLinkConstants.crossyDuelBroadcastEvent], "초인종 글자: \(events)")
        // ★ 기준선: 혼자 하기 이름 · 대문자는 앱 상수가 아니다.
        #expect(!events.contains("crossy") && !events.contains("CROSSY_DUEL"))
    }

    /// ③ 없으면: 서버 프로토콜이 올라가 앱이 모든 RPC 에서 unsupported_client 를 받거나, 판돈 칩이 서버가 받지 않는 값을 보낸다.
    @Test(.enabled(if: cmcMigrationGate))
    func theProtocolAndStakesMatchTheApp() throws {
        let sql = cmcStrip(try cmcRaw())
        let proto = try cmcMatches(#"function\s+public\.crossy_duel_protocol\(\)\s*returns\s+int\s+language\s+sql\s+immutable\s+as\s+\$fn\$\s*select\s+([0-9]+)\s*\$fn\$"#,
                                   in: sql, options: [.caseInsensitive])
        #expect(proto.count == 1 && Int(proto.first?[1] ?? "") == CrossyDuelWire.protocolVersion, "프로토콜: \(proto.map { $0[1] })")
        let stakes = try cmcMatches(#"function\s+public\.crossy_duel_stakes\(\)\s*returns\s+int\[\]\s+language\s+sql\s+immutable\s+as\s+\$fn\$\s*select\s+array\[([0-9,\s]+)\]\s*\$fn\$"#,
                                    in: sql, options: [.caseInsensitive])
        #expect(stakes.count == 1, "crossy_duel_stakes 머리 함수가 하나가 아니다(V0351 파서)")
        let values = (stakes.first?[1] ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        #expect(values == CrossyDuelStake.allCases.map(\.rawValue), "판돈: 서버 \(values) ≠ 앱 \(CrossyDuelStake.allCases.map(\.rawValue))")
    }

    /// ④ 없으면: 이 초안이 남의 머리 함수(오목 · 테트리스 · 혼자 하기 미니게임 · 수수료)를 다시 정의해 그 게임의 계약을 조용히 바꾼다.
    @Test(.enabled(if: cmcMigrationGate))
    func theDraftDefinesNoForeignHeads() throws {
        let sql = cmcStrip(try cmcRaw())
        let defined = try cmcMatches(#"create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)\s*\("#, in: sql,
                                     options: [.caseInsensitive]).map { $0[1].lowercased() }
        let foreign = defined.filter { $0.hasPrefix("gomoku") || $0.hasPrefix("tetris_") || $0.hasPrefix("minigame_") || $0 == "duel_fee" }
        #expect(foreign.isEmpty, "남의 머리 함수를 정의한다: \(foreign)")
        // ★ 기준선: 같은 읽기가 이 초안의 함수는 본다.
        #expect(defined.contains("crossy_duel_report") && defined.contains("crossy_duel__settle"))
    }

    /// ⑤ 없으면: 판 정산 백스톱이 단독 매분 job 으로 돌아 매분 단계 예산 밖에 서거나(CronMinutely 계약 밖), 자리가 남과 겹친다.
    @Test(.enabled(if: cmcMigrationGate))
    func theMinutelyWorkIsOneStepRowAndPurgeIsOneJob() throws {
        let sql = cmcStrip(try cmcRaw())
        let squashed = sql.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(cmcCount("values ('crossy-duel-settle', 'select public.crossy_duel_settle_expired()', 39, 5000)", in: squashed) == 1,
                "매분 단계 행이 (crossy-duel-settle · 39 · 5000) 하나가 아니다")
        #expect(cmcCount("cron.schedule('crossy-duel-purge', '55 18 * * *', 'select public.crossy_duel_purge()')", in: squashed) == 1)
        // 단독 매분 job(* * * * *) 은 없다.
        #expect(!squashed.contains("'* * * * *'"), "단독 매분 cron job 이 있다")
    }

    /// ⑥ 없으면: 서버 일일 줄 키가 앱이 묻는 키(`daily_crossy_duel`)와 갈려 판 끝 꼬리가 영영 "이미 채움"을 못 알아보거나, game 이
    /// 혼자 하기 `crossy` 로 접혀 아이콘·문구가 혼자 하기 것으로 나온다.
    @Test(.enabled(if: cmcMigrationGate))
    func theDailyMissionRowMatchesTheAppKey() throws {
        let raw = try cmcRaw()
        let rows = try cmcMatches(#"\(\s*'(daily_crossy_duel)'\s*,\s*'([a-z_]+)'\s*,\s*'([^']+)'\s*,\s*'([^']*)'\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*\)"#,
                                  in: raw)
        let row = try #require(rows.first, "초안에 daily_crossy_duel 정의 줄이 없다")
        #expect(Set(rows.map { $0.dropFirst().joined(separator: "|") }).count == 1, "daily_crossy_duel 줄이 서로 다르게 두 벌이다")
        #expect(row[1] == DailyMissionStatus.key(game: row[2]), "키 \(row[1]) ≠ 앱 키 \(DailyMissionStatus.key(game: row[2]))")
        #expect(row[2] == "crossy_duel", "game 이 \(row[2]) 다 — 혼자 하기 crossy 갈래로 접힌다")
        #expect(row[3].contains(CrossyDuelNoticeText.gameName), "제목 '\(row[3])' 에 게임 이름이 없다")
        #expect(row[4] == "맥에서 할 수 있어요")
        #expect(row[5] == "5" && row[6] == "1" && row[7] == "100", "보상 · 목표 · 순서: \(row[5...7])")
    }

    /// ⑦ 없으면: 앵커가 체인에 없는 글자라 운영 적용이 "앵커 0회"로 멈추거나, 표지가 이미 체인에 있는 글자라 멱등 가드가 "이미 있다"로
    /// 건너뛰어 조각이 영영 안 들어간다(하네스는 그 하네스의 체인으로만 잰다 — 이 시험은 지금 저장소 체인으로 잰다).
    @Test(.enabled(if: cmcMigrationGate))
    func theSpliceAnchorsExistInTheChainAndTheMarkersAreNew() throws {
        let raw = try cmcRaw()
        let splices = try cmcSplices(raw, block: "cd_splice") + cmcSplices(raw, block: "cd_daily")
        #expect(splices.count >= 7, "조각 행이 \(splices.count)개다")
        let functions = Set(splices.map(\.function))
        #expect(functions.isSuperset(of: ["public.game__busy_users()", "public.delete_my_account()", "public.daily_mission_defs()"]),
                "\(functions.sorted())")
        let chain = try cmcChainText()
        for splice in splices {
            #expect(cmcCount(splice.anchor, in: chain) >= 1, "\(splice.function) 앵커가 체인에 없다: \(splice.anchor.prefix(80))")
            #expect(cmcCount(splice.marker, in: chain) == 0, "\(splice.function) 표지가 이미 체인에 있다: \(splice.marker.prefix(80))")
            #expect(cmcCount(splice.marker, in: splice.fragment) == 1, "\(splice.function) 표지가 제 조각 안에 한 번이 아니다")
            #expect(!splice.fragment.contains(splice.anchor) || splice.anchor.isEmpty, "\(splice.function) 조각이 앵커를 또 담는다(앵커 1회 단언이 깨진다)")
        }
        // ★ 기준선: 체인에 없는 글자는 0 으로 센다(같은 감지기가 있다/없다를 가른다).
        #expect(cmcCount("crossy_duel_matches", in: chain) == 0, "체인에 이미 1:1 길건너 표가 있다 — 초안 앞 이름 거르기가 틀렸다")
    }
}
