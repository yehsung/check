import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.51 — 루비 경제 v2(`20261014120000_ruby_economy_v2.sql`)의 **계약**: 마이그레이션의 가장 나중 정의 ↔ 앱에 박힌 짝 상수.
//
// 서버만 아는 값(캐릭터 가격 · 울트라 가격 · 가입 지급)은 shop_state 로 내려가서 클라가 따라온다. 반대로 **상금은 클라에
// 박혀 있다**(맥 `CheckMiniGameWindowView.rubyPrizes` · 폰 `GamesMiniGameText.rubyPrizes` · `RankingsText.rubyPrizes`) —
// 서버는 금액을 내려 주지 않는다(`minigame_yesterday_winner` 는 awarded 참/거짓뿐). 넷이 갈리면 화면이 받지 않을 상금을 말한다.
//
// ★ SQL 쪽은 **파일 하나를 골라 읽지 않는다.** 상수마다 정의가 둘 이상이고(옛 파일 = 옛 값) 서버에 남는 것은
//   **파일명 순으로 마지막** 정의다. 체인 전체에서 정의를 순서대로 모으고 마지막을 정본으로 삼으며, 첫 정의가 **다른 값**이라는
//   것도 같이 잰다(기준선 갈림 — 둘이 같으면 "가장 나중을 골랐다" 가 아무 뜻도 없다). V0348 과 같은 문.
// ★ 주석은 걷어내고 읽는다(하우스 규칙 — 안 그러면 설명을 지워야만 초록이 된다).
// ★ 행동(새 가입자 60 · 구매가 새 가격으로 차감 · 로봇 needs_update · 자정 상 10·5·3)은 마이그레이션 자신의 프로브(§5)와
//   재생 하네스가 잰다 — 여기는 그 파일이 **무엇을 쓰는지**와 **앱이 같은 숫자를 말하는지**를 묶는다.
//
// `supabase/` 는 .gitignore 라 git worktree 에는 없을 수 있다 — 조상을 훑어 올라가며 찾고, `CHECK_MIGRATIONS_DIR` 로
// 덮어쓸 수 있다(뮤테이션 사본용 — V0313 · V0341 · V0348 과 같은 문).

// MARK: - 마이그레이션 읽기

private let reNewMigration = "20261014120000_ruby_economy_v2.sql"
private let reShopMigration = "20260913170100_shop.sql"
private let reRobotMigration = "20261005120000_character_roster_v3_robot.sql"

private struct REError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private let reRepoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func reMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw REError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw REError("supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

/// `--` 줄 주석을 걷어낸다. 문자열 안의 `--` 도 같이 잘린다(이 파일의 단언은 그런 줄에 걸리지 않는다).
private func reStripSQL(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// Swift 소스의 `//` 주석을 걷어낸다(줄 단위 — 문자열 안의 `//` 는 이 파일이 찾는 줄에 없다).
private func reStripSwift(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "//") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func reMigrationNames() throws -> [String] {
    try FileManager.default
        .contentsOfDirectory(at: try reMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
}

private func reRaw(_ name: String) throws -> String {
    let file = try reMigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw REError("\(name) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

private func reMatches(_ pattern: String, in text: String) throws -> [[String]] {
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).map { match in
        (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

private func reInts(_ text: String) -> [Int] {
    text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
}

/// 체인 전체에서 상수 함수 `public.<name>()` 의 정의를 **적용 순서대로** 전부 모은다(파일 · 값 목록).
///
/// 값은 `returns int|int[] language sql immutable as $tag$ select <값> $tag$` 모양에서 읽는다(`<값>` = 정수 또는
/// `array[…]`). 정의 머리는 있는데 그 모양이 아니어서 값을 못 읽으면 **조용히 건너뛰지 않고 던진다** — 건너뛰면
/// "가장 나중" 이 옛 파일로 내려앉아 엉뚱하게 초록·빨강이 된다.
private func reConstantDefinitions(_ name: String) throws -> [(file: String, value: [Int])] {
    var found: [(file: String, value: [Int])] = []
    let header = #"create\s+(?:or\s+replace\s+)?function\s+public\."# + name + #"\s*\("#
    let full = header + #"\s*\)\s*returns\s+int(?:eger)?(?:\[\])?\s+language\s+sql\s+immutable\s+as\s+\$([a-z_]*)\$\s*select\s+([^$]+?)\s*\$\1\$"#
    for file in try reMigrationNames() {
        let sql = reStripSQL(try reRaw(file))
        let headers = try reMatches(header, in: sql).count
        guard headers > 0 else { continue }
        let values = try reMatches(full, in: sql).map { reInts($0[2]) }
        guard values.count == headers, values.allSatisfy({ !$0.isEmpty }) else {
            throw REError("\(file): public.\(name) 정의 머리는 \(headers)개인데 값을 읽은 것은 \(values.count)개다 — "
                + "상수 헬퍼의 모양이 바뀌었다(이 파서를 고쳐라)")
        }
        found.append(contentsOf: values.map { (file, $0) })
    }
    return found
}

/// 새 파일의 가격표 `update public.character_prices … ;` 문장(주석 걷은 것).
private func rePriceUpdateStatement() throws -> String {
    let sql = reStripSQL(try reRaw(reNewMigration))
    let statements = try reMatches(#"^\s*update\s+public\.character_prices\b[^;]*;"#, in: sql).map { $0[0] }
    guard statements.count == 1, let only = statements.first else {
        throw REError("\(reNewMigration) 의 가격표 update 문이 \(statements.count)개다(기대 1)")
    }
    return only
}

/// `('id', 가격)` 쌍 → 사전. 같은 id 가 두 번 나오면 던진다(마지막 값이 조용히 이기면 안 된다).
private func rePricePairs(_ text: String) throws -> [String: Int] {
    var out: [String: Int] = [:]
    for match in try reMatches(#"\(\s*'([a-z_]+)'\s*,\s*([0-9]+)\s*(?:,\s*[0-9]+\s*)?\)"#, in: text) {
        guard let price = Int(match[2]) else { continue }
        if out[match[1]] != nil { throw REError("가격 쌍에 \(match[1]) 이 두 번 있다") }
        out[match[1]] = price
    }
    return out
}

/// `do $tag$ … $tag$` 블록들의 본문(원문). 꼬리표는 파일에 실제로 쓰인 것을 다 훑는다.
private func reDoBlocks(_ raw: String) throws -> [(tag: String, body: String)] {
    try reMatches(#"^do\s+(\$[a-z_0-9]+\$)"#, in: raw).compactMap { match in
        let tag = match[1]
        guard let open = raw.range(of: "do \(tag)"),
              let close = raw.range(of: tag, range: open.upperBound..<raw.endIndex) else { return nil }
        return (tag, String(raw[open.upperBound..<close.lowerBound]))
    }
}

private func reSource(_ relative: String) throws -> String {
    try String(contentsOf: reRepoRoot.appendingPathComponent(relative), encoding: .utf8)
}

/// Swift 소스(주석 걷음)에서 `rubyPrizes = [a, b, c]` 를 읽는다. 정확히 한 번 있어야 한다.
private func reSwiftPrizes(_ relative: String) throws -> [Int] {
    let code = reStripSwift(try reSource(relative))
    let found = try reMatches(#"static\s+let\s+rubyPrizes\s*=\s*\[([0-9,\s]+)\]"#, in: code)
    guard found.count == 1 else { throw REError("\(relative) 에 rubyPrizes 상수가 \(found.count)개다(기대 1)") }
    return reInts(found[0][1])
}

@Suite("루비 경제 v2 — 마이그레이션의 가장 나중 정의와 앱의 짝 상수")
struct V0351RubyEconomyMigrationTests {

    // MARK: ① 상수 셋 — 가장 나중 정의가 새 값이고, 그 정의가 이 파일이다

    @Test("상금 · 울트라 가격 · 가입 지급의 가장 나중 정의 = 이 파일의 새 값(첫 정의는 옛 값 — 기준선이 갈린다)")
    func latestConstantsAreTheNewEconomy() throws {
        let expectations: [(name: String, first: [Int], latest: [Int])] = [
            ("ruby_prize_amounts", [20, 10, 5], [10, 5, 3]),
            ("ultra_ruby_price", [3], [5]),
            ("ruby_welcome_grant", [30], [60]),
        ]
        for expectation in expectations {
            let definitions = try reConstantDefinitions(expectation.name)
            let first = try #require(definitions.first, "\(expectation.name) 정의가 체인에 없다")
            let latest = try #require(definitions.last)
            #expect(first.value == expectation.first,
                    "\(expectation.name) 첫 정의(\(first.file))가 \(first.value) 다 — 옛 값 \(expectation.first) 이어야 기준선이 갈린다")
            #expect(latest.value == expectation.latest,
                    "\(expectation.name) 가장 나중 정의(\(latest.file))가 \(latest.value) 다(기대 \(expectation.latest))")
            #expect(latest.file == reNewMigration,
                    "\(expectation.name) 의 가장 나중 정의가 \(latest.file) 다 — 이 파일 뒤에 누가 다시 정의했다")
        }
    }

    @Test("근무 3시간 랩 루비 3 은 그대로다(사용자 결정) — 이 파일은 그 상수를 다시 정의하지 않고, 맥 칩 \"💎 +3\" 과 짝이 맞는다")
    func lapGrantIsUntouched() throws {
        let definitions = try reConstantDefinitions("ruby_mission_grant")
        let latest = try #require(definitions.last, "ruby_mission_grant 정의가 체인에 없다")
        #expect(latest.value == [3])
        #expect(!definitions.contains { $0.file == reNewMigration }, "이 파일이 랩 지급을 다시 정의했다 — 사용자 결정은 '그대로'다")
        #expect(MissionCopy.reward(.todayThreeHours) == "💎 +\(latest.value[0])",
                "맥 미션 칩이 서버 랩 지급(\(latest.value[0]))과 다른 숫자를 말한다")
    }

    // MARK: ② 상금 — 서버 · 맥 · 폰 두 벌이 같은 숫자를 말한다

    @Test("상금 짝 상수 넷(서버 · 맥 · 폰 게임 탭 · 폰 순위 탭)이 같고 화면 문구가 그 숫자를 말한다")
    func prizePairsAgreeEverywhere() throws {
        let server = try #require(try reConstantDefinitions("ruby_prize_amounts").last).value
        #expect(server == [10, 5, 3])
        #expect(CheckMiniGameWindowView.rubyPrizes == server, "맥 상수 \(CheckMiniGameWindowView.rubyPrizes) ≠ 서버 \(server)")
        // 폰 두 벌은 이 타깃이 링크하지 않으므로 **소스**를 읽는다(주석 걷음).
        #expect(try reSwiftPrizes("Sources/CheckMobileKit/Games/GamesText.swift") == server, "폰 게임 탭 상수가 서버와 다르다")
        #expect(try reSwiftPrizes("Sources/CheckMobileKit/Rankings/RankingsText.swift") == server, "폰 순위 탭 상수가 서버와 다르다")
        // 문구는 상수에서 **유도**된다 — 숫자를 다시 적은 문장이 생기면 여기서 갈린다.
        #expect(CheckMiniGameWindowView.prizeCaption == "자정에 1·2·3등에게 루비 10·5·3")
        #expect(CheckMiniGameWindowView.awardedChip == "루비 +10 받음")
        #expect(CheckMiniGameWindowView.prizeQuorum == 5)
    }

    @Test("상금 칩(`ChampionRow(… awarded:)`)에 숫자를 직접 적은 자리가 소스 어디에도 없다 — DEBUG 견본까지 상수에서 읽는다")
    func championRowAwardIsNeverALiteral() throws {
        // 2026-10-14 리뷰: 짝 상수 셋을 10·5·3 으로 옮긴 뒤에도 DEBUG 견본(MobileComponentsGallery)이 `awarded: 20` 을
        // 박고 있었다 — 맥 스위트는 `#if DEBUG && os(iOS)` 파일을 컴파일하지 않으니 **원문**을 훑는다(주석 걷음).
        let sources = reRepoRoot.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let literalAward = #"\bawarded:\s*-?[0-9]"#
        // 기준선: 이 정규식이 옛 견본 줄은 잡고 상수에서 읽는 줄은 놓아준다(둘이 같게 나오면 이 검사는 영원히 초록이다).
        #expect(try reMatches(literalAward, in: #"ChampionRow(caption: "어제 1등", score: "972점", awarded: 20)"#).count == 1)
        #expect(try reMatches(literalAward, in: #"ChampionRow(caption: "어제 1등", awarded: RankingsText.rubyPrizes[0])"#).isEmpty)
        var scanned = 0
        var offenders: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            scanned += 1
            let code = reStripSwift(try String(contentsOf: file, encoding: .utf8))
            for match in try reMatches(literalAward, in: code) {
                offenders.append("\(file.path.replacingOccurrences(of: reRepoRoot.path + "/", with: "")): \(match[0])")
            }
        }
        #expect(scanned > 100, "Swift 소스를 \(scanned)개밖에 못 읽었다 — 이 검사가 헛돈다")
        #expect(offenders.isEmpty, "상금 칩에 숫자를 직접 적은 자리: \(offenders) — `rubyPrizes[0]` 에서 읽어라")
        let gallery = reStripSwift(try reSource("Sources/CheckMobileKit/Components/MobileComponentsGallery.swift"))
        #expect(try reMatches(#"ChampionRow\([^)]*awarded:\s*RankingsText\.rubyPrizes\[0\]"#, in: gallery).count == 1,
                "견본의 ChampionRow 가 RankingsText.rubyPrizes[0] 을 안 읽는다")
    }

    // MARK: ③ 가격표 — price 칸만, 여섯 캐릭터 전부, 2배

    @Test("가격표 갱신은 price 칸 한 칸만 쓴다 — min_protocol 을 덮는 upsert 가 없다(로봇 누출 함정)")
    func priceUpdateTouchesOnlyThePriceColumn() throws {
        let statement = try rePriceUpdateStatement()
        let set = try #require(try reMatches(#"\bset\s+(.+?)\s+from\b"#, in: statement.replacingOccurrences(of: "\n", with: " ")).first?[1])
        #expect(set.trimmingCharacters(in: .whitespaces) == "price = v.price",
                "가격표 update 의 set 절이 '\(set)' 다 — price 말고 다른 칸(min_protocol)을 쓰면 로봇이 구버전에 팔린다")
        #expect(statement.contains("is distinct from v.price"), "재적용이 0행이 되는 조건(is distinct from)이 빠졌다 — 멱등 단언(§4(7))과 어긋난다")
        let sql = reStripSQL(try reRaw(reNewMigration)).lowercased()
        #expect(!sql.contains("insert into public.character_prices"), "가격표에 insert/upsert 를 쓴다 — 칸을 통째로 덮는 모양이다")
        #expect(try reMatches(#"\bmin_protocol\s*=(?!=)"#, in: sql).isEmpty, "이 파일 어딘가가 min_protocol 에 값을 대입한다")
    }

    @Test("가격표의 새 값 = 사용자 확정표 · 옛 값의 정확히 2배 · 이 앱이 파는 캐릭터 전부(아잉 제외)")
    func newPricesAreTheConfirmedTable() throws {
        let newPrices = try rePricePairs(try rePriceUpdateStatement())
        #expect(newPrices == ["fox": 60, "squirrel": 60, "shiba": 100, "ghost": 100, "jellyfish": 140, "robot": 200])

        // 기준선: 옛 가격은 두 파일의 시드에서 읽는다(상점 다섯 · 로봇 하나). 새 값이 옛 값과 같으면 이 파일은 아무것도 안 한 것이다.
        let shopSeed = reStripSQL(try reRaw(reShopMigration))
        let robotSeed = reStripSQL(try reRaw(reRobotMigration))
        let oldShop = try rePricePairs(try #require(try reMatches(#"insert\s+into\s+public\.character_prices\s*\([^)]*\)\s*values([^;]*);"#, in: shopSeed).first?[1]))
        let oldRobot = try rePricePairs(try #require(try reMatches(#"insert\s+into\s+public\.character_prices\s*\([^)]*\)\s*values([^;]*);"#, in: robotSeed).first?[1]))
        let old = oldShop.merging(oldRobot) { _, robot in robot }
        #expect(old == ["fox": 30, "squirrel": 30, "shiba": 50, "ghost": 50, "jellyfish": 70, "robot": 100], "옛 가격 시드를 못 읽었다: \(old)")
        for (id, price) in newPrices {
            #expect(old[id].map { $0 * 2 } == price, "\(id): 옛 \(old[id].map(String.init) ?? "없음") → 새 \(price) — 2배가 아니다")
        }

        // 이 앱 번들이 세우는 유료 캐릭터 전부가 새 가격을 받는다(빠진 캐릭터는 옛 값 그대로 남아 "2배" 가 거짓이 된다).
        // v0.3.54: 황금 아잉이는 카탈로그에 늘 있지만 **팔지 않는다**(뽑기 전용) — 유료 캐릭터가 아니다.
        let paid = Set(CheckMascotAssets.catalog.allIDs.filter { $0 != CharacterCatalog.builtInAingID && !CharacterCatalog.isGoldAing($0) })
        #expect(Set(newPrices.keys) == paid, "가격을 고친 캐릭터 \(newPrices.keys.sorted()) ≠ 번들의 유료 캐릭터 \(paid.sorted())")
    }

    @Test("가입 지급 ≥ 제일 싼 캐릭터(2026-09-13 사용자 규칙) — 그리고 이 파일 뒤에 가격표를 다시 쓰는 파일이 없다")
    func welcomeStillBuysTheCheapestCharacter() throws {
        let welcome = try #require(try reConstantDefinitions("ruby_welcome_grant").last).value[0]
        let cheapest = try #require(try rePricePairs(try rePriceUpdateStatement()).values.min())
        #expect(welcome >= cheapest, "가입 지급 \(welcome) < 제일 싼 캐릭터 \(cheapest) — 가입하고 아무것도 못 산다")

        let names = try reMigrationNames()
        let mine = try #require(names.firstIndex(of: reNewMigration), "\(reNewMigration) 이 체인에 없다")
        for later in names[(mine + 1)...] {
            let sql = reStripSQL(try reRaw(later)).lowercased()
            #expect(!sql.contains("update public.character_prices") && !sql.contains("insert into public.character_prices"),
                    "\(later) 가 이 파일 뒤에서 가격표를 다시 쓴다 — 이 계약(가입 ≥ 최저가 · 2배)을 그 파일로 옮겨라")
        }
        // 이 파일 자신이 그 부등식을 적용 시점에 되묻는다(옛 파일의 단언은 다시 안 돈다).
        let post = try #require(try reDoBlocks(try reRaw(reNewMigration)).first { $0.tag == "$post$" }, "사후 단언 블록이 없다")
        #expect(post.body.contains("public.ruby_welcome_grant() < v_min"), "사후 단언이 가입 지급 ≥ 최저가를 안 잰다")
    }

    // MARK: ④ 실행권 · 본문 — create or replace 만, 회수 없음, RPC 는 손대지 않는다

    @Test("상수 셋은 create or replace 로만 바뀌고 drop · revoke · grant 가 한 줄도 없다(PUBLIC 회수 = 가입이 조용히 0 루비)")
    func constantsKeepTheirACL() throws {
        let sql = reStripSQL(try reRaw(reNewMigration))
        for name in ["ruby_prize_amounts", "ultra_ruby_price", "ruby_welcome_grant"] {
            #expect(try reMatches(#"create\s+or\s+replace\s+function\s+public\."# + name + #"\s*\(\s*\)"#, in: sql).count == 1,
                    "\(name) 가 create or replace 로 정확히 한 번 정의되지 않는다")
        }
        // pg_temp 헬퍼 정리(drop function if exists pg_temp.…)는 된다 — 막는 것은 **public** 함수를 버리는 줄이다.
        #expect(try reMatches(#"^\s*drop\s+function\s+(?:if\s+exists\s+)?public\."#, in: sql).isEmpty,
                "public 함수를 drop 한다 — ACL 과 주석을 버린다")
        #expect(try reMatches(#"^\s*(revoke|grant)\b"#, in: sql).isEmpty, "실행권을 다시 적는 줄이 있다 — 이 파일은 실행권을 안 건드린다")
        // 사후 단언이 PUBLIC 실행권과 oid 를 실제로 되묻는다(drop + create 는 Supabase 기본 권한이 같은 ACL 을 붙여 원문만으론 안 갈린다).
        let post = try #require(try reDoBlocks(try reRaw(reNewMigration)).first { $0.tag == "$post$" })
        #expect(post.body.contains("has_function_privilege('public', 'public.ultra_ruby_price()', 'EXECUTE')"))
        #expect(post.body.contains("has_function_privilege('public', 'public.ruby_welcome_grant()', 'EXECUTE')"))
        #expect(reStripSQL(try reRaw(reNewMigration)).contains("jsonb_build_object('oid', p.oid"), "속성 스냅숏에 oid 가 없다 — drop + create 를 못 잡는다")
    }

    @Test("RPC 본문 · 판돈 · 정족수 · 울트라 상한을 이 파일이 다시 정의하지 않는다")
    func noRPCOrUntouchedConstantIsRedefined() throws {
        let sql = reStripSQL(try reRaw(reNewMigration))
        for name in ["buy_character", "buy_ultra", "shop_state", "minigame_award_daily_prizes", "handle_check_auth_user",
                     "ruby_welcome_backfill", "minigame_yesterday_winner", "ruby_mission_grant", "minigame_prize_quorum",
                     "ultra_buy_max", "gomoku_stakes", "chess_stakes", "free_character_id"] {
            #expect(try reMatches(#"create\s+(?:or\s+replace\s+)?function\s+public\."# + name + #"\s*\("#, in: sql).isEmpty,
                    "이 파일이 public.\(name) 을 다시 정의한다 — 상수·가격표만 바꾸는 파일이다")
        }
        // 판돈은 그대로 3/5/10 이다(가장 나중 정의 기준).
        #expect(try reConstantDefinitions("gomoku_stakes").last?.value == [3, 5, 10])
        #expect(try reConstantDefinitions("chess_stakes").last?.value == [3, 5, 10])
    }

    // MARK: ⑤ 파일 위생 — 순서 · 프로브 센티널 · 달러 태그 함정

    @Test("이 파일은 상점 · 환영 지급 · 로봇 · 테트리스 파일 뒤에 오고, 프로브는 센티널로 통째 롤백한다")
    func orderingAndProbeHygiene() throws {
        let names = try reMigrationNames()
        #expect(names.count > 100, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
        let mine = try #require(names.firstIndex(of: reNewMigration), "\(reNewMigration) 이 체인에 없다")
        for source in ["20260913170000_ruby_currency.sql", reShopMigration, "20260913180000_ruby_welcome_grant.sql",
                       "20260923140000_minigame_tetris.sql", reRobotMigration] {
            let at = try #require(names.firstIndex(of: source), "\(source) 이 체인에 없다")
            #expect(at < mine, "\(source) 가 이 파일보다 뒤에 있다")
        }
        let raw = try reRaw(reNewMigration)
        let blocks = try reDoBlocks(raw)
        #expect(blocks.map(\.tag) == ["$pre$", "$post$", "$probe$"], "do 블록 구성이 \(blocks.map(\.tag)) 다")
        let probe = try #require(blocks.first { $0.tag == "$probe$" })
        #expect(probe.body.contains("raise exception 'RUBY_V2_PROBE_ROLLBACK'") && probe.body.contains("if sqlerrm <> 'RUBY_V2_PROBE_ROLLBACK' then raise; end if;"),
                "프로브가 센티널 예외로 롤백하지 않는다 — 프로브 픽스처(가입자 다섯)가 운영에 남는다")
        #expect(!reStripSQL(raw).lowercased().contains("reset role"), "RESET ROLE 이 있다 — CLI 링크드 연결은 세션 사용자로 떨어져 42501")
        // 달러 태그 함정: do 블록 안 주석에 '$' 가 있으면 그 자리에서 본문이 끝날 수 있다(2026-09-14 app_release).
        for block in blocks {
            let commentLines = block.body.split(separator: "\n").filter { $0.contains("--") }
            for line in commentLines {
                let comment = line[line.range(of: "--")!.lowerBound...]
                #expect(!comment.contains("$"), "\(block.tag) 블록 주석에 '$' 가 있다: \(comment)")
            }
        }
    }
}
