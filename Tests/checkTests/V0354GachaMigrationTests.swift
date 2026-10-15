import CryptoKit
import Foundation
import Testing

// v0.3.54 — 캐릭터 뽑기 · 황금 아잉이 · 조각 교환(`20261015121000_gacha.sql`)의 **소스 계약**.
//
// 행동은 마이그레이션 자신의 §9 프로브(실호출 24건 — 옛/새 상점 · needs_update · 부족 · 뽑기 · 재시도 멱등 · 중복 → 조각 ·
// 교환 갈래 전부 · 황금 not_for_sale · 착용 게이트 · 추첨 경계 · 2만 번 분포 · RPC 200번 셈 · 계정 삭제 cascade)와 재생 하네스
// (3회 연속 적용 + 사용자 흉내 테스트 · 뮤턴트 11개 전부 빨강)가 증명했다. 여기서 재는 것은 db push 전에 알 수 있는 것이다:
//   ① 확률표가 사용자 확정표이고 합 100 이며, **누적 추첨을 0…99 전부에 돌리면** 칸마다 정확히 그 확률만큼 떨어진다
//      (프로브의 경계표 ⑳ · 사후 단언 §8(5) · 프로브 ② 의 확률 JSON 이 같은 표를 말한다).
//   ② 황금의 가격표 행(min_protocol 2 · gacha_only)이 CHECK 교체보다 **먼저** 들어간다 — 거꾸로면 그 사이 옛 클라 전원에게
//      price 0 카드가 뜨고 누구나 공짜로 입는다(20261005120000 머리말의 함정).
//   ③ shop_state · buy_character 의 새 본문 = 직전 마지막 정의(정본) + 치환표(바이트) · §1 의 정본 md5 가 정말 그 본문의 md5.
//   ④ 두 RPC 의 전선 계약(인자 전부 DEFAULT · 실행권 · 잠금 순서 · 장부 reason · 응답 어휘)과 새 표의 cascade · RPC 전용 권한.
// 하우스 규칙: `--` 주석은 걷어내고 본다(바이트 비교는 원문으로).

private let gcMigration = "20261015121000_gacha.sql"
private let gcRobot = "20261005120000_character_roster_v3_robot.sql"
private let gcShop = "20260913170100_shop.sql"
private let gcRubyV2 = "20261014120000_ruby_economy_v2.sql"

/// 사용자 확정표(2026-10-15): (id, 확률, 조각 교환가 — nil = 교환 불가).
private let gcOwnerTable: [(id: String, percent: Int, shardCost: Int?)] = [
    ("aing_gold", 5, nil), ("fox", 24, 3), ("squirrel", 24, 3), ("shiba", 14, 5),
    ("ghost", 14, 5), ("jellyfish", 11, 7), ("robot", 8, 10),
]

private struct GCError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func gcMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GCError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw GCError("supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

private func gcNames() throws -> [String] {
    try FileManager.default.contentsOfDirectory(at: try gcMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }.map(\.lastPathComponent).sorted()
}

private func gcRaw(_ name: String) throws -> String {
    let file = try gcMigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else { throw GCError("\(name) 이 없다: \(file.path)") }
    return try String(contentsOf: file, encoding: .utf8)
}

private func gcStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func gcSquash(_ text: String) -> String {
    text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

private func gcMatches(_ pattern: String, in text: String, dotAll: Bool = false) throws -> [[String]] {
    var options: NSRegularExpression.Options = [.caseInsensitive, .anchorsMatchLines]
    if dotAll { options.insert(.dotMatchesLineSeparators) }
    let regex = try NSRegularExpression(pattern: pattern, options: options)
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}

private func gcCount(_ needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

/// `create` 줄에서 정의하는 `public.<name>(` 의 **마지막** 본문(`as $fn$ … $fn$`, 원문 바이트).
private func gcBody(_ name: String, in raw: String) -> String? {
    var last: Range<String.Index>?
    var searchStart = raw.startIndex
    while let found = raw.range(of: "function public.\(name)(", range: searchStart..<raw.endIndex) {
        let lineStart = raw[raw.startIndex..<found.lowerBound].lastIndex(of: "\n").map { raw.index(after: $0) } ?? raw.startIndex
        if gcStrip(String(raw[lineStart..<found.lowerBound])).lowercased().contains("create") { last = found }
        searchStart = found.upperBound
    }
    guard let header = last, let open = raw.range(of: "as $fn$", range: header.upperBound..<raw.endIndex),
          let close = raw.range(of: "$fn$", range: open.upperBound..<raw.endIndex) else { return nil }
    return String(raw[open.upperBound..<close.lowerBound])
}

/// 정의 머리(`create … function public.<name>(` 부터 `as $fn$` 앞까지)를 공백 접은 소문자로.
private func gcHeader(_ name: String, in raw: String) throws -> String {
    let sql = gcStrip(raw)
    let found = try gcMatches(#"create\s+or\s+replace\s+function\s+public\."# + name + #"\s*\((.*?)as\s+\$fn\$"#, in: sql, dotAll: true)
    guard found.count == 1, let only = found.first else { throw GCError("\(name) 정의 머리가 \(found.count)개다(기대 1)") }
    var header = gcSquash(only[0])
    if header.hasSuffix(" as $fn$") { header.removeLast(" as $fn$".count) }
    return header
}

private func gcDefiningFiles(_ name: String) throws -> [String] {
    try gcNames().filter { file in
        let sql = gcStrip(try gcRaw(file)).lowercased()
        return try !gcMatches(#"create\s+(?:or\s+replace\s+)?function\s+public\."# + name + #"\s*\("#, in: sql).isEmpty
    }
}

private func gcPatches(_ raw: String) throws -> [(fn: String, seq: Int, old: String, new: String)] {
    try gcMatches(#"\('([a-z_]+)',\s*([0-9]+),\s*\$patch\$(.*?)\$patch\$,\s*\$patch\$(.*?)\$patch\$\)"#, in: raw, dotAll: true)
        .map { ($0[1], Int($0[2]) ?? -1, $0[3], $0[4]) }
}

private func gcMD5(_ text: String) -> String {
    Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

private func gcBlock(_ raw: String, tag: String) throws -> String {
    guard let open = raw.range(of: "do \(tag)") else { throw GCError("\(tag) 블록이 없다") }
    guard let close = raw.range(of: tag, range: open.upperBound..<raw.endIndex) else { throw GCError("\(tag) 가 안 닫힌다") }
    return String(raw[open.upperBound..<close.lowerBound])
}

/// 이 파일의 확률표 insert 를 행으로 읽는다: (id, percent, shard_cost, sort).
private func gcPoolRows() throws -> [(id: String, percent: Int, shardCost: Int?, sort: Int)] {
    let sql = gcStrip(try gcRaw(gcMigration))
    let statements = try gcMatches(#"insert\s+into\s+public\.gacha_pool\s*\(\s*character_id\s*,\s*percent\s*,\s*shard_cost\s*,\s*sort\s*\)\s*values([^;]*);"#, in: sql)
    guard statements.count == 1 else { throw GCError("확률표 insert 가 \(statements.count)개다(기대 1)") }
    return try gcMatches(#"\(\s*'([a-z_]+)'\s*,\s*([0-9]+)\s*,\s*(null|[0-9]+)\s*,\s*([0-9]+)\s*\)"#, in: statements[0][1]).map {
        ($0[1], Int($0[2]) ?? -1, Int($0[3]), Int($0[4]) ?? -1)
    }
}

/// gacha__pick 과 같은 뜻의 누적 추첨: sort 순 누적합이 처음으로 r 보다 큰 행.
private func gcPick(_ roll: Int, _ table: [(id: String, percent: Int)]) -> String? {
    guard roll >= 0 else { return nil }
    var upTo = 0
    for row in table {
        upTo += row.percent
        if upTo > roll { return row.id }
    }
    return nil
}

/// 체인에서 `add constraint profiles_character_valid check (character is null or character in (…))` 의 마지막 정의 (파일, 명단).
private func gcLatestRoster() throws -> (file: String, ids: [String]) {
    var latest: (String, [String])?
    for file in try gcNames() {
        let flat = gcSquash(gcStrip(try gcRaw(file)))
        for match in try gcMatches(#"add constraint profiles_character_valid check \(character is null or character in \(([^)]*)\)"#, in: flat) {
            latest = (file, match[1].split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "' ")) })
        }
    }
    guard let found = latest else { throw GCError("profiles_character_valid 명단을 못 찾았다") }
    return found
}

@Suite("캐릭터 뽑기 · 황금 아잉이 · 조각 교환 — 마이그레이션 소스 계약(20261015121000)")
struct V0354GachaMigrationTests {

    // MARK: ① 확률표

    @Test("확률표 = 사용자 확정표(합 100) · 누적 추첨을 0…99 에 돌리면 칸마다 정확히 그 확률 · 교환 대상 = 상점에서 파는 여섯")
    func oddsTableIsTheOwnerTableAndTheWalkMatches() throws {
        let rows = try gcPoolRows()
        #expect(rows.map(\.id) == gcOwnerTable.map(\.id), "확률표 순서·명단이 \(rows.map(\.id)) 다")
        #expect(rows.map(\.percent) == gcOwnerTable.map(\.percent), "확률이 \(rows.map(\.percent)) 다")
        #expect(rows.map(\.shardCost) == gcOwnerTable.map(\.shardCost), "교환가가 \(rows.map(\.shardCost)) 다")
        #expect(rows.map(\.percent).reduce(0, +) == 100, "확률 합이 \(rows.map(\.percent).reduce(0, +)) 다")
        #expect(zip(rows, rows.dropFirst()).allSatisfy { $0.sort < $1.sort }, "sort 가 표 순서대로 오르지 않는다 — 확률표 표시 순서가 갈린다")

        // 결과로 잰다: 추첨값 100개(0…99)를 누적 추첨에 넣으면 칸마다 정확히 확률만큼 떨어진다(기준선: 순서를 뒤집어도 개수는 같고 경계는 갈린다).
        let table = rows.map { (id: $0.id, percent: $0.percent) }
        var hits: [String: Int] = [:]
        for roll in 0..<100 { hits[gcPick(roll, table) ?? "∅", default: 0] += 1 }
        #expect(hits == Dictionary(uniqueKeysWithValues: gcOwnerTable.map { ($0.id, $0.percent) }), "추첨 0…99 의 칸별 개수가 \(hits) 다")
        #expect(gcPick(100, table) == nil && gcPick(-1, table) == nil, "범위 밖 추첨이 무언가를 고른다")
        #expect(gcPick(5, table) == "fox" && gcPick(5, Array(table.reversed())) != "fox", "기준선: 순서를 뒤집어도 경계가 그대로다 — 이 검사가 헛돈다")

        // 프로브 ⑳ 의 경계표가 이 표의 누적 경계와 같다(프로브가 다른 표를 재면 초록이 거짓이다).
        let probe = gcStrip(try gcBlock(try gcRaw(gcMigration), tag: "$probe$"))
        let boundaries = try gcMatches(#"\(\s*([0-9]+)\s*,\s*'([a-z_]+)'\s*\)"#, in: probe)
        #expect(boundaries.count == 14, "프로브 경계표가 \(boundaries.count)칸이다(기대 14)")
        for pair in boundaries {
            #expect(gcPick(Int(pair[1]) ?? -1, table) == pair[2], "프로브 경계 \(pair[1]) → \(pair[2]) 가 확률표와 어긋난다")
        }

        // 사후 단언 §8(5)와 프로브 ② 가 같은 표를 말한다.
        let post = try gcBlock(try gcRaw(gcMigration), tag: "$post$")
        let literal = try #require(try gcMatches(#"'(\[\["aing_gold".*?\]\])'::jsonb"#, in: post, dotAll: true).first?[1], "사후 단언의 확률표 문자열이 없다")
        let decoded = try #require(try JSONSerialization.jsonObject(with: Data(literal.utf8)) as? [[Any]])
        #expect(decoded.map { $0[0] as? String } == gcOwnerTable.map(\.id)
                && decoded.map { $0[1] as? Int } == gcOwnerTable.map(\.percent)
                && decoded.map { $0[2] as? Int } == gcOwnerTable.map(\.shardCost), "사후 단언의 확률표가 확정표와 다르다: \(literal)")
        let odds = gcSquash(probe)
        #expect(odds.contains(gcSquash(gcOwnerTable.map { #"{"character_id": "\#($0.id)", "percent": \#($0.percent)}"# }.joined(separator: ", "))),
                "프로브 ② 의 확률 JSON 이 확정표와 다르다")

        // 교환 대상(교환가 있는 칸) = 상점에서 파는 여섯(루비 v2 의 가격표 갱신 대상) — 파는 캐릭터만 조각으로 바꿀 수 있다.
        let priceUpdate = gcStrip(try gcRaw(gcRubyV2))
        let sold = Set(try gcMatches(#"\(\s*'([a-z_]+)'\s*,\s*[0-9]+\s*\)"#,
                                     in: try #require(try gcMatches(#"^\s*update\s+public\.character_prices\b[^;]*;"#, in: priceUpdate).first?[0])).map { $0[1] })
        #expect(Set(rows.filter { $0.shardCost != nil }.map(\.id)) == sold, "교환 대상 \(rows.filter { $0.shardCost != nil }.map(\.id)) ≠ 파는 캐릭터 \(sold.sorted())")
    }

    @Test("추첨은 코어 CSPRNG(gen_random_uuid 앞 32비트 mod 100)이고 random()·setseed 를 안 쓴다")
    func rollUsesCoreCSPRNG() throws {
        let roll = gcSquash(try #require(gcBody("gacha__roll", in: try gcRaw(gcMigration))))
        #expect(roll == "select (('x' || substr(pg_catalog.gen_random_uuid()::text, 1, 8))::bit(32)::bigint % 100)::int", "추첨식이 \(roll) 다")
        // 함수 본문에서 random()·setseed() 를 찾는다(gen_random_uuid 는 `\b` 경계에 안 걸린다 — 아래 기준선).
        let forbidden = #"\b(random|setseed)\s*\("#
        #expect(try gcMatches(forbidden, in: "select random() * 100").count == 1, "기준선: random() 을 못 잡는다")
        #expect(try gcMatches(forbidden, in: "select pg_catalog.gen_random_uuid()").isEmpty, "기준선: gen_random_uuid 를 random() 으로 잡는다")
        for fn in ["gacha__roll", "gacha__pick", "gacha_pull", "gacha_exchange", "gacha_min_protocol"] {
            let body = gcStrip(try #require(gcBody(fn, in: try gcRaw(gcMigration)), "\(fn) 본문이 없다"))
            #expect(try gcMatches(forbidden, in: body).isEmpty, "\(fn) 가 random()/setseed 를 쓴다 — 세션 PRNG 는 돈이 걸린 추첨에 안 쓴다")
        }
        let pull = gcSquash(gcStrip(try #require(gcBody("gacha_pull", in: try gcRaw(gcMigration)))))
        #expect(pull.contains("v_char := public.gacha__pick(public.gacha__roll());"), "gacha_pull 이 같은 추첨 두 함수를 안 부른다(분포 프로브가 다른 길을 잰다)")
        #expect(pull.contains("if v_char is null then raise exception"), "추첨이 비면 롤백하지 않는다(루비만 깎인다)")
    }

    // MARK: ② 황금의 문 — 가격표 행이 CHECK 보다 먼저

    @Test("aing_gold 가격표 행(1000 · min_protocol 2 · gacha_only)이 CHECK 교체보다 먼저 · 덮어쓰지 않는다 · 명단 − 아잉 = 가격표 키")
    func goldRowComesBeforeTheCheck() throws {
        let sql = gcSquash(gcStrip(try gcRaw(gcMigration)))
        let insert = "insert into public.character_prices (character_id, price, min_protocol, gacha_only) values ('aing_gold', 1000, 2, true) on conflict (character_id) do nothing;"
        let row = try #require(sql.range(of: insert), "aing_gold 가격표 행이 (1000, 2, true) · on conflict do nothing 이 아니다")
        let check = try #require(sql.range(of: "add constraint profiles_character_valid check"))
        let comment = try #require(sql.range(of: "comment on constraint profiles_character_valid on public.profiles is"))
        let column = try #require(sql.range(of: "alter table public.character_prices add column if not exists gacha_only boolean not null default false;"))
        #expect(column.upperBound <= row.lowerBound && row.upperBound <= check.lowerBound && check.upperBound <= comment.lowerBound,
                "순서가 칸 → 황금 행 → CHECK → 주석이 아니다 — CHECK 가 먼저면 그 사이 옛 클라에 price 0 카드 · 공짜 착용")
        #expect(gcCount("update public.character_prices", in: sql) == 0, "다른 가격표 행을 고친다")

        let roster = try gcLatestRoster()
        #expect(roster.file == gcMigration, "허용 명단의 마지막 정의가 \(roster.file) 다")
        #expect(roster.ids.sorted() == ["aing", "aing_gold", "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel"], "명단이 \(roster.ids) 다")
        // 결과로 잰다: 체인 전체의 가격표 id(시드 · 로봇 · 황금) = 명단 − 무료(아잉). 빠지면 그 id 가 price 0 으로 공짜가 된다.
        var priced = Set<String>()
        for file in try gcNames() {
            let text = gcStrip(try gcRaw(file)).lowercased()
            for statement in try gcMatches(#"insert\s+into\s+public\.character_prices\s*\([^)]*\)\s*values([^;]*);"#, in: text) {
                for match in try gcMatches(#"\(\s*'([a-z_]+)'"#, in: statement[1]) { priced.insert(match[1]) }
            }
        }
        #expect(priced == Set(roster.ids).subtracting(["aing"]), "가격표 id \(priced.sorted()) ≠ 명단 − 아잉")
        #expect(!priced.contains("aing"), "기준선: 아잉이 가격표에 있다 — 무료 규약이 깨진다")
    }

    // MARK: ③ 정본 + 치환

    @Test("shop_state · buy_character 새 본문 = 직전 마지막 정의 + 치환표(바이트) · §1 md5 = 정본 · set_character 는 그대로이고 게이트가 황금을 덮는다")
    func shopBodiesAreCanonicalPlusPatches() throws {
        let raw = try gcRaw(gcMigration)
        let patches = try gcPatches(raw)
        #expect(patches.count == 5, "치환표가 \(patches.count)줄이다(기대 5 = shop_state 셋 · buy_character 둘)")
        let names = try gcNames()
        let mine = try #require(names.firstIndex(of: gcMigration))
        let pre = try gcBlock(raw, tag: "$pre$")
        let post = try gcBlock(raw, tag: "$post$")
        for fn in ["shop_state", "buy_character"] {
            let before = try gcDefiningFiles(fn).filter { (names.firstIndex(of: $0) ?? .max) < mine }
            #expect(before.last == gcRobot, "\(fn) 의 직전 마지막 정의가 \(String(describing: before.last)) 다(기대 \(gcRobot))")
            let canon = try #require(gcBody(fn, in: try gcRaw(gcRobot)))
            let mineBody = try #require(gcBody(fn, in: raw))
            var expected = canon
            for patch in patches where patch.fn == fn {
                #expect(gcCount(patch.old, in: canon) == 1 && !patch.new.contains(patch.old), "\(fn)#\(patch.seq) 치환 자리가 1회가 아니거나 new 가 old 를 품는다")
                expected = expected.replacingOccurrences(of: patch.old, with: patch.new)
            }
            #expect(mineBody == expected, "\(fn) 의 새 본문이 정본 + 치환과 다르다")
            #expect(mineBody != canon, "기준선: 새 본문이 정본과 같다")
            #expect(try gcDefiningFiles(fn).last == gcMigration, "\(fn) 의 가장 나중 정의가 이 파일이 아니다")
            #expect(pre.contains(gcMD5(canon)), "\(fn): §1 의 정본 md5 가 정본 본문의 md5(\(gcMD5(canon)))가 아니다")
            #expect(post.contains(gcMD5(mineBody)), "\(fn): §8 의 새 본문 md5 가 실제 새 본문의 것이 아니다")
        }
        // 서명 그대로(create or replace) — drop 은 DEFAULT·ACL·주석을 버리고 PGRST203 를 부른다.
        #expect(try gcHeader("shop_state", in: raw).hasPrefix("create or replace function public.shop_state(p_protocol int default 0) returns jsonb"))
        #expect(try gcHeader("buy_character", in: raw).hasPrefix(
            "create or replace function public.buy_character(p_id text default null::text, p_protocol int default 0) returns jsonb"))
        #expect(try gcMatches(#"^\s*drop\s+function\s+(?:if\s+exists\s+)?public\."#, in: gcStrip(raw)).isEmpty, "public 함수를 drop 한다")

        // buy_character: not_for_sale 이 보유 확인 · 프로토콜 게이트 · 잔량 잠금보다 **먼저**다(차감·소유 기입이 원리적으로 없다).
        let buy = gcSquash(gcStrip(try #require(gcBody("buy_character", in: raw))))
        let notForSale = try #require(buy.range(of: "if coalesce(v_gacha_only, false) then return jsonb_build_object('status', 'not_for_sale'"))
        for later in ["select 1 from public.character_ownership o", "'needs_update'", "for update", "insert into public.character_ownership"] {
            let at = try #require(buy.range(of: later), "buy_character 에 '\(later)' 가 없다")
            #expect(notForSale.upperBound <= at.lowerBound, "not_for_sale 이 '\(later)' 보다 뒤다")
        }
        // shop_state: gacha 키는 프로토콜 게이트 안 · 행마다 gacha_only.
        let shop = gcSquash(gcStrip(try #require(gcBody("shop_state", in: raw))))
        #expect(shop.contains("if greatest(coalesce(p_protocol, 0), 0) >= public.gacha_min_protocol() then v_gacha := jsonb_build_object("))
        #expect(shop.contains("'gacha_only', coalesce(c.gacha_only, false)"))
        #expect(shop.contains("case when v_gacha is null then '{}'::jsonb else jsonb_build_object('gacha', v_gacha) end"),
                "옛 클라에 gacha 키(null 값 포함)가 새어 나간다")

        // set_character 는 이 파일이 안 건드리고, 마지막 정의의 소유 게이트가 "가격표 행 ⇒ 소유권" 이다(황금 행이 있으므로 덮인다).
        #expect(!(try gcDefiningFiles("set_character")).contains(gcMigration), "이 파일이 set_character 를 다시 정의한다")
        let lastSet = try #require(try gcDefiningFiles("set_character").last)
        let setBody = gcSquash(gcStrip(try #require(gcBody("set_character", in: try gcRaw(lastSet)))))
        #expect(setBody.contains("and exists (select 1 from public.character_prices c where c.character_id = cleaned) and not exists (select 1 from public.character_ownership o where o.user_id = uid and o.character_id = cleaned) then return jsonb_build_object('status', 'not_owned'"),
                "set_character(\(lastSet))의 소유 게이트가 '가격표 행 ⇒ 소유권' 이 아니다 — 황금을 누구나 입는다")
        #expect(pre.contains(gcMD5(try #require(gcBody("set_character", in: try gcRaw(lastSet))))),
                "§1 이 set_character 정본 md5 를 못 박지 않는다")
    }

    // MARK: ④ 전선 계약

    @Test("gacha_pull · gacha_exchange: 인자 전부 DEFAULT · definer · authenticated 만 · 잠금 → 멱등키 → for update · 응답 어휘가 전선 계약 그대로")
    func rpcWireContract() throws {
        let raw = try gcRaw(gcMigration)
        let sql = gcSquash(gcStrip(raw))
        #expect(try gcHeader("gacha_pull", in: raw) ==
                "create or replace function public.gacha_pull(p_protocol int default 0, p_request_id uuid default null) returns jsonb language plpgsql volatile security definer set search_path = public")
        #expect(try gcHeader("gacha_exchange", in: raw) ==
                "create or replace function public.gacha_exchange(p_character_id text default null, p_protocol int default 0, p_request_id uuid default null) returns jsonb language plpgsql volatile security definer set search_path = public")
        for signature in ["public.gacha_pull(integer, uuid)", "public.gacha_exchange(text, integer, uuid)"] {
            #expect(sql.contains("revoke all on function \(signature) from public, anon;"), "\(signature) anon 회수 줄이 없다")
            #expect(sql.contains("grant execute on function \(signature) to authenticated;"), "\(signature) authenticated 허용 줄이 없다")
            #expect(!sql.contains("grant execute on function \(signature) to anon"), "\(signature) 를 anon 에게 준다")
        }
        for (fn, statuses, keys) in [
            ("gacha_pull", ["not_signed_in", "needs_update", "insufficient", "invalid", "ok"],
             ["character_id", "duplicate", "shards_gained", "shards", "ruby_balance", "price", "request_id", "replayed", "need", "have", "min_protocol"]),
            ("gacha_exchange", ["not_signed_in", "needs_update", "not_exchangeable", "already_owned", "insufficient_shards", "invalid", "ok"],
             ["character_id", "shards", "cost", "request_id", "replayed", "need", "have"]),
        ] {
            let body = gcSquash(gcStrip(try #require(gcBody(fn, in: raw))))
            for status in statuses { #expect(body.contains("'status', '\(status)'"), "\(fn): 상태 '\(status)' 가 없다(전선 계약)") }
            for key in keys { #expect(body.contains("'\(key)',"), "\(fn): 응답 키 '\(key)' 가 없다(전선 계약)") }
            // 잠금 순서: 지갑 키 → 멱등키 조회 → 행 잠금(for update). 지갑 키는 사용자당 하나(ultra_wallet:).
            let lock = try #require(body.range(of: "perform pg_advisory_xact_lock(hashtext('ultra_wallet:' || uid::text));"), "\(fn): 지갑 키가 없다")
            let replay = try #require(body.range(of: "from public.gacha_log l where l.user_id = uid and l.request_id = v_req"), "\(fn): 멱등키 조회가 없다")
            let rowLock = try #require(body.range(of: "for update"), "\(fn): 행 잠금이 없다")
            #expect(lock.upperBound <= replay.lowerBound && replay.upperBound <= rowLock.lowerBound, "\(fn): 잠금 → 멱등키 → for update 순서가 아니다")
            #expect(body.contains("v_proto int := greatest(coalesce(p_protocol, 0), 0);") && body.contains("if v_proto < v_need then"),
                    "\(fn): 프로토콜을 바닥(0)으로 읽어 gacha_min_protocol 과 비교하지 않는다")
            let need = try #require(body.range(of: "v_need := public.gacha_min_protocol();"))
            #expect(need.upperBound <= lock.lowerBound, "\(fn): 프로토콜 게이트가 지갑 잠금보다 뒤다(옛 클라가 잠금까지 탄다)")
        }
        let pull = gcSquash(gcStrip(try #require(gcBody("gacha_pull", in: raw))))
        #expect(pull.contains("v_price constant int := public.gacha_price();") && !pull.contains("50"), "뽑기 값을 리터럴로 적는다 — gacha_price() 만 본다")
        #expect(pull.contains("'spend:gacha:' || v_id::text, -v_price, v_bal"), "뽑기 차감 장부가 spend:gacha:<원장 id> −가격이 아니다")
        #expect(pull.contains("values (uid, v_char, 'gacha') on conflict (user_id, character_id) do nothing"), "처음 나온 캐릭터를 gacha 로 소유하지 않는다")
        let exchange = gcSquash(gcStrip(try #require(gcBody("gacha_exchange", in: raw))))
        #expect(!exchange.contains("insert into public.ruby_ledger") && !exchange.contains("ruby_balance -"), "교환이 루비를 건드린다")
        #expect(exchange.contains("set shards = shards - v_cost"), "교환이 조각을 깎지 않는다")
        // 상수: gacha_price() = 50 · gacha_min_protocol() = max(2, 확률표 캐릭터 min_protocol) · 둘 다 PUBLIC(회수 줄 없음).
        #expect(gcSquash(try #require(gcBody("gacha_price", in: raw))) == "select 50")
        #expect(gcSquash(try #require(gcBody("gacha_min_protocol", in: raw))).hasPrefix("select greatest(2, coalesce(max(c.min_protocol), 0))::int"))
        for constant in ["gacha_price", "gacha_min_protocol"] {
            #expect(try gcMatches(#"^\s*(revoke|grant)\b[^;\n]*public\."# + constant + #"\s*\("#, in: gcStrip(raw)).isEmpty, "\(constant) 의 실행권을 다시 적는다")
        }
        for helper in ["public.gacha__roll()", "public.gacha__pick(int)"] {
            #expect(sql.contains("revoke all on function \(helper) from public, anon, authenticated;"), "\(helper) 가 내부 전용이 아니다")
        }
    }

    // MARK: ⑤ 새 표

    @Test("새 표 셋: FK 는 같은 줄 cascade(조각·원장 → profiles) · 확률표 → 가격표 · 멱등키 유니크 · RLS 켜고 전권 회수 · 정책 없음")
    func newTablesAreRpcOnlyAndCascade() throws {
        let code = gcStrip(try gcRaw(gcMigration)).lowercased()
        let lines = code.split(separator: "\n").map { gcSquash(String($0)) }
        #expect(lines.contains("user_id uuid primary key references public.profiles(id) on delete cascade,"), "character_shards.user_id 의 cascade 가 같은 줄에 없다")
        #expect(lines.contains("user_id uuid not null references public.profiles(id) on delete cascade,"), "gacha_log.user_id 의 cascade 가 같은 줄에 없다")
        #expect(lines.contains("character_id text primary key references public.character_prices(character_id),"), "gacha_pool → 가격표 FK 가 없다")
        #expect(lines.contains("constraint gacha_log_user_request_key unique (user_id, request_id)"), "멱등키 유니크가 없다 — 이중 과금")
        #expect(lines.contains("shards int not null default 0 check (shards >= 0),"), "조각이 음수가 될 수 있다")
        for table in ["gacha_pool", "character_shards", "gacha_log"] {
            #expect(lines.contains("alter table public.\(table) enable row level security;"), "\(table) RLS 가 꺼져 있다")
            #expect(lines.contains("revoke all on public.\(table) from public, anon, authenticated;"), "\(table) 기본 권한을 회수하지 않는다")
            #expect(!lines.contains { $0.hasPrefix("grant") && $0.contains("public.\(table)") && ($0.contains("anon") || $0.contains("authenticated")) },
                    "\(table) 을 클라에게 연다")
        }
        #expect(!code.contains("create policy"), "새 표에 정책을 만든다 — RPC 전용이다")
        // 한 표가 두 표를 가리키면 PostgREST 가 junction 으로 읽어 기존 임베드가 400 이 된다 — 표마다 FK 하나.
        for table in ["gacha_pool", "character_shards", "gacha_log"] {
            let body = try #require(try gcMatches(#"create\s+table\s+if\s+not\s+exists\s+public\."# + table + #"\s*\((.*?)\n\);"#, in: code, dotAll: true).first?[1])
            #expect(gcCount("references ", in: body) == 1, "\(table) 의 FK 가 \(gcCount("references ", in: body))개다(기대 1)")
        }
    }

    // MARK: ⑥ 위생 · 불변식 · 프로브

    @Test("순서 · do 블록 · 달러 태그 · RESET ROLE · notify · 가입 지급 ≥ 살 수 있는 최저가를 다시 잰다 · 프로브 24건과 분포 ±1.2%p")
    func hygieneInvariantAndProbe() throws {
        let names = try gcNames()
        let mine = try #require(names.firstIndex(of: gcMigration))
        for source in [gcShop, gcRobot, gcRubyV2, "20261015120000_duel_fee.sql"] {
            #expect(try #require(names.firstIndex(of: source), "\(source) 이 체인에 없다") < mine, "\(source) 가 이 파일보다 뒤다")
        }
        let raw = try gcRaw(gcMigration)
        let sql = gcStrip(raw)
        let tags = try gcMatches(#"^do\s+(\$[a-z_0-9]+\$)"#, in: raw).map { $0[1] }
        #expect(tags == ["$pre$", "$post$", "$probe$"], "do 블록 구성이 \(tags) 다")
        for tag in tags {
            #expect(gcCount(tag, in: raw) == 2, "\(tag) 가 원문에 \(gcCount(tag, in: raw))회")
            for line in try gcBlock(raw, tag: tag).split(separator: "\n") {
                if let dash = line.range(of: "--") { #expect(!line[dash.upperBound...].contains("$"), "\(tag) 블록 주석에 '$': \(line)") }
            }
        }
        #expect(!sql.lowercased().contains("reset role"))
        for line in sql.split(separator: "\n") where ["begin;", "commit;", "rollback;"].contains(line.trimmingCharacters(in: .whitespaces).lowercased()) {
            Issue.record("최상위 트랜잭션 제어: \(line)")
        }
        let lastLine = sql.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
        #expect(lastLine == "notify pgrst, 'reload schema';", "파일 끝이 notify pgrst 가 아니다(새 표·새 RPC)")

        let post = gcSquash(gcStrip(try gcBlock(raw, tag: "$post$")))
        #expect(post.contains("select min(c.price) into v_min from public.character_prices c where not c.gacha_only;")
                && post.contains("public.ruby_welcome_grant() < v_min"), "사후 단언이 가입 지급 ≥ (뽑기 전용을 뺀) 최저가를 안 잰다")
        let probe = gcSquash(gcStrip(try gcBlock(raw, tag: "$probe$")))
        for token in ["v_expected constant int := 24", "v_draws constant int := 20000", "abs(v_share - r.percent) > 1.2",
                      "v_res := public.gacha_pull(2, v_r1);", "v_res := public.buy_character('aing_gold', 2);",
                      "v_res := public.set_character('aing_gold');", "perform public.delete_my_account();",
                      "raise exception 'gacha_probe_rollback';", "if sqlerrm <> 'gacha_probe_rollback' then raise; end if;",
                      "execute format('set local role %i', v_exec_role);"] {
            #expect(probe.contains(token), "프로브에 '\(token)' 이 없다")
        }
    }
}
