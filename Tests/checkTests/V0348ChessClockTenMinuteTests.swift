import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.48 — 체스 시계 5분 → 10분의 **계약**: Swift 에 박힌 값 ↔ 마이그레이션의 **가장 나중 정의**.
//
// 시계 초기값은 두 군데에 있다: 서버의 `public.chess_initial_ms()` 와 앱의 `ChessClock.initialSeconds`. 앱은 로비
// 응답으로 서버 값을 받아 쓰지만(그 쪽은 `V0348ChessClockServerDrivenTests`), 로비를 읽기 전의 캡션·시계 자리표시와
// 로봇 판의 기본값은 앱에 박힌 값이다. 둘이 갈리면 창을 연 첫 순간과 로봇 판이 서버와 다른 시계를 말한다.
//
// ★ SQL 쪽은 **파일 하나를 골라 읽지 않는다.** 그 함수를 정의하는 마이그레이션은 둘이고(20261005160000 = 300000 ·
//   20261012120000 = 600000) 서버에 남는 것은 **파일명 순으로 마지막** 정의다. 옛 파일을 읽으면 300000 에 걸려 빨개지고,
//   아무 파일이나 읽어 한 군데라도 맞으면 초록이 되는 검사는 한쪽만 고친 배포를 통과시킨다. 그래서 체인 전체에서
//   정의를 **순서대로 전부** 모으고 마지막을 정본으로 삼으며, 첫 정의가 **다른 값**이라는 것도 같이 잰다(기준선 갈림 —
//   둘이 같으면 "가장 나중을 골랐다" 는 것이 아무 뜻도 없다).
//
// 뮤테이션 실측(2026-10-12 · 스크래치의 APFS 사본): Swift 만 300 으로 되돌린 사본과 SQL 만 300000 으로 되돌린 사본이
// **둘 다** 이 파일에서 빨개진다 — 수치는 보고서에 있다.
//
// `supabase/` 는 .gitignore 라 git worktree 에는 없을 수 있다 — 조상을 훑어 올라가며 찾고, `CHECK_MIGRATIONS_DIR` 로
// 덮어쓸 수 있다(뮤테이션 사본용 — V0313 · V0341 과 같은 문).

// MARK: - 마이그레이션 읽기

private let tmNewMigration = "20261012120000_chess_clock_10min.sql"
private let tmDuelMigration = "20261005160000_chess_duel.sql"

private struct TMError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func tmMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TMError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw TMError("supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
/// 문자열 안의 `--` 도 같이 잘린다(이 파일의 단언은 그런 줄에 걸리지 않는다).
private func tmStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 체인의 파일 이름(파일명 순 = 운영 CLI 의 적용 순).
private func tmMigrationNames() throws -> [String] {
    try FileManager.default
        .contentsOfDirectory(at: try tmMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
}

private func tmRaw(_ name: String) throws -> String {
    let file = try tmMigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw TMError("\(name) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

private func tmMatches(_ pattern: String, in text: String) throws -> [[String]] {
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).map { match in
        (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

/// 체인 전체에서 상수 함수 `public.<name>()` 의 정의를 **적용 순서대로** 전부 모은다(파일 · 값).
///
/// 값은 `returns int language sql immutable as $fn$ select <숫자> $fn$` 모양에서 읽는다. 정의 머리는 있는데 그 모양이
/// 아니어서 값을 못 읽으면 **조용히 건너뛰지 않고 던진다** — 건너뛰면 "가장 나중" 이 옛 파일로 내려앉아, 새 파일의
/// 모양만 바꾼 변경이 옛 값과 대조돼 엉뚱하게 초록·빨강이 된다.
private func tmConstantDefinitions(_ name: String) throws -> [(file: String, value: Int)] {
    var found: [(file: String, value: Int)] = []
    let header = #"create\s+(?:or\s+replace\s+)?function\s+public\."# + name + #"\s*\("#
    let full = header + #"\s*\)\s*returns\s+int(?:eger)?\s+language\s+sql\s+immutable\s+as\s+\$fn\$\s*select\s+([0-9]+)\s*\$fn\$"#
    for file in try tmMigrationNames() {
        let sql = tmStrip(try tmRaw(file))
        let headers = try tmMatches(header, in: sql).count
        guard headers > 0 else { continue }
        let values = try tmMatches(full, in: sql).compactMap { Int($0[1]) }
        guard values.count == headers else {
            throw TMError("\(file): public.\(name) 정의 머리는 \(headers)개인데 값을 읽은 것은 \(values.count)개다 — "
                + "상수 헬퍼의 모양이 바뀌었다(이 파서를 고쳐라)")
        }
        found.append(contentsOf: values.map { (file, $0) })
    }
    return found
}

private func tmCount(_ needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

/// `do $tag$ … $tag$` 블록의 본문(원문).
private func tmBlock(_ raw: String, tag: String) throws -> Substring {
    guard let open = raw.range(of: "do \(tag)"),
          let close = raw.range(of: tag, range: open.upperBound..<raw.endIndex) else {
        throw TMError("\(tag) 블록을 못 찾았다")
    }
    return raw[open.upperBound..<close.lowerBound]
}

private let tmFixtureRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures", isDirectory: true)

private func tmFixture(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: tmFixtureRoot.appendingPathComponent(path))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TMError("\(path) 는 JSON 객체가 아니다")
    }
    return object
}

@Suite("체스 시계 10분 — Swift 에 박힌 값과 마이그레이션의 가장 나중 정의")
struct V0348ChessClockTenMinuteTests {

    // MARK: - ① Swift ↔ SQL(가장 나중 정의)

    @Test
    @MainActor
    func swiftClockMatchesTheLatestMigrationDefinition() throws {
        // 없으면: 서버만 600000 으로 올리고 앱의 300 을 그대로 두거나(로비를 읽기 전 캡션·로봇 판이 5분),
        // 앱만 600 으로 고치고 마이그레이션을 빼먹어도(화면은 10분이라는데 판은 5분으로 열린다) 초록이다.
        let initial = try tmConstantDefinitions("chess_initial_ms")
        // '가장 나중' 을 고르는 일이 **실제로 일어나야** 한다 — 정의가 하나뿐이면 무엇을 읽어도 같은 값이다.
        #expect(initial.count == 2, "chess_initial_ms 를 정의하는 자리가 \(initial.map(\.file)) 이다 — 정의가 늘었으면 이 계약을 다시 읽어라")
        let first = try #require(initial.first)
        let last = try #require(initial.last)
        #expect(first.file == tmDuelMigration)
        #expect(first.value == 300_000, "옛 정의(5분)가 바뀌었다 — 이미 적용된 파일은 고치지 않는다")
        #expect(last.file == tmNewMigration, "서버에 남는 정의가 \(last.file) 것이다")
        #expect(last.value == 600_000)
        #expect(first.value != last.value, "두 정의가 같으면 '가장 나중을 읽는다' 가 아무것도 재지 않는다")

        // ★ 계약: 서버에 남는 값 = 앱에 박힌 값(초 × 1000).
        #expect(Double(last.value) == ChessClock.initialSeconds * 1000,
                "서버 \(last.value)ms ≠ 앱 \(ChessClock.initialSeconds)초 — 한쪽만 고쳤다")
        #expect(last.value == ChessClock.initialMs)

        // 가산·유예는 이 배포가 건드리지 않는다: 정의는 여전히 옛 파일 하나뿐이고 값도 그대로다.
        let increment = try tmConstantDefinitions("chess_increment_ms")
        #expect(increment.map(\.file) == [tmDuelMigration])
        #expect(increment.last?.value == 3_000)
        #expect(Double(increment.last?.value ?? -1) == ChessClock.incrementSeconds * 1000)
        let grace = try tmConstantDefinitions("chess_grace_ms")
        #expect(grace.map(\.file) == [tmDuelMigration])
        #expect(grace.last?.value == 2_000)
        let store = ChessStore()
        #expect(grace.last?.value == store.graceMs)
        #expect(increment.last?.value == store.incrementMs)
        #expect(Double(grace.last?.value ?? -1) == ChessStore.flagGraceSeconds * 1000)
    }

    // MARK: - ② 박힌 값은 한 곳에서 나온다

    @Test
    @MainActor
    func everyBakedInStartingClockComesFromTheOneConstant() {
        // 없으면: 네 자리(자리표시 시계 · 스토어 기본값 · reset · 로봇 판 기본 인자) 가운데 하나만 300_000 으로 남아도
        // 초록이다 — 예컨대 reset 만 남으면 로그아웃했다 들어온 사람의 로봇 판만 5분이다.
        #expect(ChessClock.initialSeconds == 600)
        #expect(ChessClock.incrementSeconds == 3)
        #expect(ChessClock.initialMs == 600_000)
        #expect(ChessClock().remaining(.white) == 600)
        #expect(ChessClock().remaining(.black) == 600)

        // 자리표시 시계(관전 첫 응답 전 · 테스트 판)
        #expect(ChessServerClock.initial.whiteMsLeft == 600_000)
        #expect(ChessServerClock.initial.blackMsLeft == 600_000)
        #expect(ChessServerClock.initial.incrementMs == 3_000)
        #expect(ChessServerClock.initial.running == nil)
        #expect(ChessSpectateState(id: "x").clock.whiteMsLeft == 600_000)

        // 스토어 기본값 — 로비를 읽기 전의 캡션이 이 값으로 그려진다.
        let store = ChessStore()
        #expect(store.initialMs == 600_000)
        #expect(ChessText.subtitle(initialMs: store.initialMs, incrementMs: store.incrementMs)
                == "FIDE 규칙 · 백 선공 · 10분 + 한 수 3초")

        // reset — 서버가 **다른 값**을 말한 뒤 로그아웃하면 박힌 값으로 돌아온다(대조군: 그 사이 값은 실제로 달랐다).
        store.initialMs = 900_000
        #expect(ChessText.subtitle(initialMs: store.initialMs, incrementMs: store.incrementMs)
                == "FIDE 규칙 · 백 선공 · 15분 + 한 수 3초")
        store.reset()
        #expect(store.initialMs == 600_000)
        #expect(store.initialMs == ChessStore().initialMs, "reset 뒤의 기본값이 새 스토어와 다르다")

        // 로봇 판의 기본 인자
        let game = ChessAIGame(humanColor: .white, now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(game.msLeft(.white) == 600_000)
        #expect(game.msLeft(.black) == 600_000)
        #expect(game.incrementMs == 3_000)
    }

    // MARK: - ③ 10분 픽스처는 이 서버에서 뜬 것이다

    @Test
    func clockTenFixturesWereCapturedFromTheServerTheLatestDefinitionDescribes() throws {
        // 없으면: `V0348ChessClockServerDrivenTests` 가 먹이는 "10분 서버의 응답" 이 마이그레이션과 따로 놀아도 초록이다 —
        // 누가 상수를 또 바꾸면 그 테스트들은 더는 존재하지 않는 서버를 재고 있게 된다.
        let latest = try #require(try tmConstantDefinitions("chess_initial_ms").last).value
        let manifest = try tmFixture("chess-rpc-clock10/_manifest.json")
        #expect((manifest["chess_initial_ms"] as? NSNumber)?.intValue == latest)
        #expect((manifest["chess_increment_ms"] as? NSNumber)?.intValue == 3_000)
        #expect((manifest["chess_grace_ms"] as? NSNumber)?.intValue == 2_000)
        let lobby = try tmFixture("chess-rpc-clock10/chess_lobby__ok_empty.json")
        #expect((lobby["initial_ms"] as? NSNumber)?.intValue == latest)
        for name in ["chess_respond__accept_ok", "chess_state__ok_initial_my_turn",
                     "chess_state__ok_initial_their_turn", "chess_watch__ok_active"] {
            let row = try #require(try tmFixture("chess-rpc-clock10/\(name).json")["match"] as? [String: Any], "\(name)")
            #expect((row["white_ms_left"] as? NSNumber)?.intValue == latest, "\(name): 새 판의 백 시계")
            #expect((row["black_ms_left"] as? NSNumber)?.intValue == latest, "\(name): 새 판의 흑 시계")
        }
        // 매니페스트에 적힌 픽스처와 디스크의 json 이 같은 집합이다(손으로 끼워 넣은 본문이 없다).
        let listed = Set((manifest["fixtures"] as? [String: Any] ?? [:]).keys)
        let onDisk = Set(try FileManager.default
            .contentsOfDirectory(atPath: tmFixtureRoot.appendingPathComponent("chess-rpc-clock10").path)
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix("_") }
            .map { String($0.dropLast(5)) })
        #expect(listed == onDisk)
        #expect(listed.count == 8)

        // ★ 대조군: 옛 픽스처 집합은 **옛 정의**의 서버에서 뜬 것이다(그래서 그 로비는 300000 을 말한다).
        let oldest = try #require(try tmConstantDefinitions("chess_initial_ms").first).value
        let legacyLobby = try tmFixture("chess-rpc/chess_lobby__ok_empty.json")
        #expect((legacyLobby["initial_ms"] as? NSNumber)?.intValue == oldest)
        #expect(oldest != latest)
    }

    // MARK: - ④ 파일 규율

    @Test
    func tenMinuteMigrationTouchesOneConstantAndNothingElse() throws {
        // 없으면: 이 파일에 `update public.chess_matches …`(진행 중인 판의 시계를 10분으로 "맞춰 주는" 한 줄) 이나 revoke 한 줄,
        // 다른 함수의 재정의가 끼어도 PR 단계에서는 아무도 모른다(적용 때는 파일의 §3 이 잡지만 그건 운영 앞에서다).
        let names = try tmMigrationNames()
        #expect(names.count > 100, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
        let mine = try #require(names.firstIndex(of: tmNewMigration), "\(tmNewMigration) 이 체인에 없다")
        let duel = try #require(names.firstIndex(of: tmDuelMigration))
        #expect(duel < mine, "체스 대국 파일보다 뒤여야 한다 — 앞이면 그 파일이 300000 으로 다시 덮는다")

        let raw = try tmRaw(tmNewMigration)
        let sql = tmStrip(raw)
        let lower = sql.lowercased()

        // 만드는 public 함수는 하나뿐이고, 값은 한 번만 적힌다.
        let created = try tmMatches(#"create\s+(?:or\s+replace\s+)?function\s+public\.([a-z0-9_]+)"#, in: lower).map { $0[1] }
        #expect(created == ["chess_initial_ms"], "이 파일이 만드는 public 함수: \(created)")
        #expect(tmCount("$fn$ select 600000 $fn$", in: sql) == 1)
        #expect(try tmMatches(#"^\s*comment\s+on\s+function\s+public\."#, in: lower).count == 3)

        // 판 표에 쓰는 문장이 없다 — 5분으로 시작한 판은 5분 시계로 끝난다.
        let writes = try tmMatches(
            #"(update|delete\s+from|insert\s+into|truncate(\s+table)?|alter\s+table|lock\s+table)\s+(only\s+)?public\.chess_(matches|moves)\b"#,
            in: lower)
        #expect(writes.isEmpty, "판 표를 건드리는 문장: \(writes.map { $0[0] })")
        // 실행권을 적지 않는다(create or replace 가 보존한다) · 함수를 지우지 않는다 · 역할을 되돌리지 않는다.
        #expect(try tmMatches(#"^\s*(grant|revoke)\s"#, in: lower).isEmpty, "grant/revoke 문장이 있다")
        #expect(try tmMatches(#"drop\s+function\s+(if\s+exists\s+)?public\."#, in: lower).isEmpty, "public 함수를 지운다")
        #expect(!lower.contains("reset role"), "RESET ROLE — CLI 링크드 연결은 세션 사용자로 떨어져 42501")
        for line in sql.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            #expect(!["begin;", "commit;", "rollback;", "start transaction;"].contains(line),
                    "최상위 트랜잭션 제어 '\(line)' — 운영 CLI 의 래퍼 트랜잭션을 깬다")
        }

        // 달러 태그 규율: 블록 태그가 원문에 각 정확히 2회, 블록 안 `--` 주석에 자기 태그 글자가 없다.
        for tag in ["$pre$", "$assert$", "$tail$"] {
            #expect(tmCount(tag, in: raw) == 2, "\(tag) 가 \(tmCount(tag, in: raw))회 — 주석에 태그 글자를 적으면 그 자리에서 본문이 끝난다")
            for line in try tmBlock(raw, tag: tag).split(separator: "\n") {
                if let dash = line.range(of: "--") {
                    #expect(!line[dash.upperBound...].contains("$"), "\(tag) 블록 주석에 달러 글자가 있다: \(line)")
                }
            }
        }
        #expect(tmCount("$fn$", in: raw) == 2)
        #expect(tmCount("$tmp$", in: raw) == 4)
        #expect(!raw.contains("$$"), "이름 없는 달러 인용은 쓰지 않는다")

        // 사후 단언이 재는 것 여섯 묶음이 본문에 있다(묶음 수 가드와 같은 숫자).
        #expect(sql.contains("v_expected constant int := 6;"))
        #expect(tmCount("v_probes := v_probes + 1;", in: sql) == 6)

        // 체스 두 파일의 관례 그대로: 끝은 적용 완료 알림 블록이다.
        let lastLine = sql.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
        #expect(lastLine == "end $tail$;", "파일 끝이 꼬리 블록이 아니다: \(lastLine ?? "")")
    }
}
