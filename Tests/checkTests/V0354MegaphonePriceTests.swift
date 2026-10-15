import Foundation
import Testing

// v0.3.54 — 확성기 루비 50 → 30 의 **계약**: 마이그레이션 체인의 가장 나중 정의가 30 이고, 그 파일은 상수 하나만 바꾼다.
//
// 앱은 가격을 베끼지 않는다(맥 · 폰 모두 megaphone_info 의 price 를 그대로 보여 준다 — V0351MegaphoneTests ·
// MessagesMegaphoneTests). 그래서 이 값의 정본은 서버의 `public.megaphone_ruby_price()` 하나다.
//
// ★ 파일 하나를 골라 읽지 않는다 — 그 함수를 정의하는 파일은 둘이고(20261014122000 = 50 · 20261015110000 = 30) 서버에 남는
//   것은 **파일명 순으로 마지막** 정의다. 첫 정의가 **다른 값**이라는 것도 같이 잰다(기준선이 같으면 "가장 나중을 골랐다" 가
//   아무 뜻도 없다). V0348ChessClockTenMinuteTests 와 같은 문.
//
// `supabase/` 는 .gitignore 라 git worktree 에는 없을 수 있다 — 조상을 훑어 올라가며 찾고, `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다.

private let mpNewMigration = "20261015110000_megaphone_price_30.sql"
private let mpMegaphoneMigration = "20261014122000_megaphone.sql"
/// 이 파일을 쓸 때 운영에 적용된 마지막 파일 — 새 파일은 이보다 뒤여야 CLI 가 올린다.
private let mpLastAppliedInProduction = "20261014130000_phone_work.sql"
/// 같은 날 함께 나가는 0.3.54 파일 — 새 파일이 이보다 앞이어야 이 파일만 먼저 올려도 그 둘이 "마지막 적용보다 앞" 이 되지 않는다.
private let mpDuelFeeMigration = "20261015120000_duel_fee.sql"

private struct MPError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func mpMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    throw MPError("supabase/migrations 를 못 찾았다 — CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

/// `--` 줄 주석을 걷어낸다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
private func mpStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func mpMigrationNames() throws -> [String] {
    try FileManager.default
        .contentsOfDirectory(at: try mpMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
}

private func mpRaw(_ name: String) throws -> String {
    let file = try mpMigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw MPError("\(name) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

private func mpMatches(_ pattern: String, in text: String) throws -> [[String]] {
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

private func mpCount(_ needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

/// 체인 전체에서 `public.megaphone_ruby_price()` 의 정의를 적용 순서대로 전부 모은다. 머리는 있는데 값을 못 읽으면 던진다
/// (조용히 건너뛰면 "가장 나중" 이 옛 파일로 내려앉는다).
private func mpPriceDefinitions() throws -> [(file: String, value: Int)] {
    let header = #"create\s+(?:or\s+replace\s+)?function\s+public\.megaphone_ruby_price\s*\("#
    let full = header + #"\s*\)\s*returns\s+int(?:eger)?\s+language\s+sql\s+immutable\s+as\s+\$fn\$\s*select\s+([0-9]+)\s*\$fn\$"#
    var found: [(file: String, value: Int)] = []
    for file in try mpMigrationNames() {
        let sql = mpStrip(try mpRaw(file))
        let headers = try mpMatches(header, in: sql).count
        guard headers > 0 else { continue }
        let values = try mpMatches(full, in: sql).compactMap { Int($0[1]) }
        guard values.count == headers else {
            throw MPError("\(file): 정의 머리 \(headers)개 · 값 \(values.count)개 — 상수 헬퍼 모양이 바뀌었다(이 파서를 고쳐라)")
        }
        found.append(contentsOf: values.map { (file, $0) })
    }
    return found
}

@Suite("확성기 30루비 — 마이그레이션의 가장 나중 정의")
struct V0354MegaphonePriceTests {

    @Test
    func latestDefinitionIsThirtyAndTheFirstWasFifty() throws {
        let definitions = try mpPriceDefinitions()
        #expect(definitions.map(\.file) == [mpMegaphoneMigration, mpNewMigration], "정의하는 파일: \(definitions.map(\.file))")
        #expect(definitions.first?.value == 50, "기준선(첫 정의)이 50 이 아니다 — 가장 나중을 고르는 검사가 헛돈다")
        #expect(definitions.last?.value == 30, "서버에 남는 가격: \(definitions.last.map { String($0.value) } ?? "없음")")
    }

    @Test
    func fileSitsBetweenProductionTipAndTheOtherV0354Files() throws {
        let names = try mpMigrationNames()
        let mine = try #require(names.firstIndex(of: mpNewMigration), "\(mpNewMigration) 이 체인에 없다")
        let tip = try #require(names.firstIndex(of: mpLastAppliedInProduction))
        #expect(tip < mine, "운영의 마지막 적용 파일보다 앞이면 CLI 가 이 파일을 '순서 밖' 으로 거절한다")
        if let duelFee = names.firstIndex(of: mpDuelFeeMigration) {
            #expect(mine < duelFee, "0.3.54 파일보다 뒤면 이 파일만 먼저 올렸을 때 그 파일들이 순서 밖이 된다")
        }
    }

    @Test
    func priceMigrationTouchesOneConstantAndNothingElse() throws {
        let raw = try mpRaw(mpNewMigration)
        let sql = mpStrip(raw)
        let lower = sql.lowercased()

        let created = try mpMatches(#"create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)"#, in: lower).map { $0[1] }
        #expect(created == ["megaphone_ruby_price"], "이 파일이 만드는 public 함수: \(created)")
        #expect(mpCount("$fn$ select 30 $fn$", in: sql) == 1)
        // 상수 함수의 PUBLIC 실행권은 유지해야 한다(42501 함정) — 실행권을 적지 않고, 지우지 않는다.
        #expect(try mpMatches(#"^\s*(grant|revoke)\s"#, in: lower).isEmpty, "grant/revoke 문장이 있다")
        #expect(try mpMatches(#"drop\s+function"#, in: lower).isEmpty, "함수를 지운다 — ACL · COMMENT 가 사라진다")
        #expect(try mpMatches(#"(update|delete\s+from|insert\s+into|alter\s+table)\s+(only\s+)?public\."#, in: lower).isEmpty,
                "표에 쓰는 문장이 있다")
        for line in sql.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            #expect(!["begin;", "commit;", "rollback;", "start transaction;"].contains(line),
                    "최상위 트랜잭션 제어 '\(line)' — 운영 CLI 의 래퍼 트랜잭션을 깬다")
        }
        // 달러 태그 규율: 각 태그 정확히 2회, 이름 없는 달러 인용 없음.
        #expect(mpCount("$fn$", in: raw) == 2)
        #expect(mpCount("$post$", in: raw) == 2, "주석에 태그 글자를 적으면 그 자리에서 본문이 끝난다")
        #expect(!raw.contains("$$"))
        #expect(sql.contains("if public.megaphone_ruby_price() <> 30 then"), "사후 단언이 30 을 되묻지 않는다")
    }
}
