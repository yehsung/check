import Foundation
import Testing
@testable import check

// v0.3.13 — **RPC 인자의 default 를 지키는 소스 계약** (2026-09-12 PGRST202 장애의 재발 방지선 두 번째).
//
// 장애 요약: `20260912143000_profile_center.sql` 이 `minigame_board` 를 drop+create 하면서
// 원래 있던 `p_day date default null` 의 **default 를 떨어뜨렸다.** 앱은 '오늘' 순위를 볼 때
// `p_day` 키를 안 보내므로(encodeIfPresent) PostgREST 가 함수를 못 찾아 404 PGRST202 를 냈다.
// 핫픽스는 `20260912151142_minigame_board_default_restore.sql`.
//
// 이 파일이 지키는 불변식은 **한 문장**이다:
//   "앱이 본문에서 생략하는 인자는, 마이그레이션 **최종 정의**에서 반드시 default 를 갖는다."
//
// 그래서 기대값을 손으로 적지 않는다 — 왼쪽(앱이 보내는 키)은 진짜 요청 구조체를 진짜 인코더로 인코딩해서,
// 오른쪽(함수가 선언한 인자)은 SQL 헤더를 파싱해서 얻고, **그 차집합**에 default 를 요구한다.
// 새 RPC 가 늘어도, 인자가 늘어도, 이 규칙은 그대로 적용된다.
//
// ⚠️ `pg_get_function_identity_arguments` 는 default 를 **안 보여 준다.** 카탈로그로 확인할 때는
//    `pg_get_function_arguments` 를 써라(핫픽스 파일의 do$$ 단언이 그렇게 한다).

// MARK: - 마이그레이션 디렉토리 찾기

private struct MigrationContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `supabase/` 는 .gitignore 로 공개 저장소에서 빠져 있어 **git worktree 에는 존재하지 않는다.**
/// `#filePath` 에서 세 단계만 올라가는 기존 관용구는 워크트리에서 무조건 실패한다(기존 8개
/// 마이그레이션 계약 테스트가 그 상태다). 그래서 여기선 **조상을 훑어 올라가며** 실제로
/// `supabase/migrations` 가 있는 첫 디렉토리를 찾는다 — 메인 체크아웃이면 3단째에, 워크트리면
/// `.claude/worktrees/<이름>` 을 지나 저장소 루트에서 잡힌다.
///
/// `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다(뮤테이션 하네스 전용 — 공유 체크아웃의 실물을
/// 건드리지 않고 사본으로 검증하기 위한 문이다). 덮어써도 아래 단언들은 그대로 돈다.
private func migrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MigrationContractError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw MigrationContractError(
        "supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", ")). "
            + "워크트리라면 저장소 루트까지 올라가야 하고, 그래도 없으면 CHECK_MIGRATIONS_DIR 로 알려 줘라."
    )
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
private func stripSQLLineComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 그 함수를 정의하는 마이그레이션 중 **파일명이 가장 늦은 것**(= 실제로 적용 순서상 마지막).
/// 중간 파일이 default 를 잃었더라도(실제로 20260912143000 이 그랬다) 최종 정의가 옳으면 서버는 옳다.
private func finalDefinition(of function: String) throws -> (file: URL, sql: String) {
    let directory = try migrationsDirectory()
    let files = try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !files.isEmpty else {
        throw MigrationContractError("\(directory.path) 에 .sql 이 하나도 없다")
    }
    var found: (URL, String)?
    for file in files {
        let sql = stripSQLLineComments(try String(contentsOf: file, encoding: .utf8))
        // ★ `create` 로 앵커한다. `drop function public.X(text, date)` · `revoke … on function public.X(…)` ·
        //   본문 안의 호출 `from public.X(g.game, v_d1)` 이 전부 "function public.X(" 를 포함하므로,
        //   앵커를 느슨하게 두면 인자 목록으로 `(text, date)` 를 읽어 버린다(실제로 그렇게 틀렸었다).
        if createHeaderParenIndex(sql, function: function) != nil {
            found = (file, sql)
        }
    }
    guard let found else {
        throw MigrationContractError("\(function) 을 정의하는 마이그레이션이 \(directory.path) 에 없다")
    }
    return found
}

/// `create [or replace] function public.<name>(` 의 **여는 괄호** 위치.
private func createHeaderParenIndex(_ sql: String, function: String) -> String.Index? {
    for header in ["create or replace function public.\(function)(", "create function public.\(function)("] {
        if let range = sql.range(of: header, options: .caseInsensitive) {
            return sql.index(before: range.upperBound)      // 여는 괄호
        }
    }
    return nil
}

/// create 헤더의 인자 목록 원문을 쪼갠다. 괄호 중첩을 세어 닫는다(`numeric(10,2)` 같은 타입이 와도 안 깨지게).
private func declaredArguments(_ sql: String, function: String) throws -> [(name: String, declaration: String)] {
    guard let parenIndex = createHeaderParenIndex(sql, function: function) else {
        throw MigrationContractError("\(function) 의 create 헤더를 못 찾았다")
    }
    var depth = 0
    var body = ""
    var index = parenIndex
    while index < sql.endIndex {
        let character = sql[index]
        if character == "(" {
            depth += 1
            if depth == 1 { index = sql.index(after: index); continue }
        } else if character == ")" {
            depth -= 1
            if depth == 0 { break }
        }
        body.append(character)
        index = sql.index(after: index)
    }
    guard depth == 0 else { throw MigrationContractError("\(function) 인자 목록의 괄호가 안 닫힌다") }

    // 최상위 콤마로만 쪼갠다.
    var parts: [String] = []
    var current = ""
    var nested = 0
    for character in body {
        if character == "(" { nested += 1 }
        if character == ")" { nested -= 1 }
        if character == ",", nested == 0 {
            parts.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    parts.append(current)

    return parts
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { (name: String($0.split(separator: " ").first ?? ""), declaration: $0) }
}

// MARK: - 앱이 **생략하는** 인자 = default 가 반드시 있어야 하는 인자

/// 앱이 실제로 보내는 본문의 키 집합. 진짜 요청 구조체를 서비스와 **같은 설정**의 인코더로 인코딩한다
/// (여기서 손으로 `["p_game"]` 이라고 적으면 이 테스트는 앱이 아니라 나를 검사하게 된다).
private func sentKeys<Body: Encodable>(_ body: Body) throws -> Set<String> {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase   // SupabaseWorkService.init 과 같은 설정
    let data = try encoder.encode(body)
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw MigrationContractError("본문이 JSON 객체가 아니다")
    }
    return Set(object.keys)
}

// MARK: - ① 핵심: 생략되는 인자에는 default 가 있어야 한다

@Test
func 앱이_생략하는_RPC_인자는_최종_마이그레이션에서_default_를_갖는다() throws {
    // 왼쪽: 앱이 '오늘' 순위를 볼 때 실제로 보내는 키(= p_game 하나).
    let sent = try sentKeys(MiniGameBoardRequest(pGame: MiniGameKind.flappy.rawValue))
    #expect(sent == ["p_game"], "앱이 보내는 키가 바뀌었다: \(sent)")

    // 오른쪽: 마이그레이션 최종 정의가 선언한 인자.
    let (file, sql) = try finalDefinition(of: "minigame_board")
    let declared = try declaredArguments(sql, function: "minigame_board")
    #expect(declared.map(\.name) == ["p_game", "p_day"], "\(file.lastPathComponent): 인자 목록이 바뀌었다: \(declared.map(\.declaration))")

    // 차집합: 앱이 안 보내는 인자. 이것들이 default 를 잃는 순간 PostgREST 는 함수를 못 찾는다.
    let omitted = declared.filter { !sent.contains($0.name) }
    #expect(!omitted.isEmpty, "생략되는 인자가 하나도 없다면 이 테스트는 아무것도 안 지킨다 — 전제가 바뀌었다")
    for argument in omitted {
        let why = "\(file.lastPathComponent): 앱이 안 보내는 인자 '\(argument.name)' 에 default 가 없다 "
            + "→ 오늘(2026-09-12) 미니게임 창을 빈 화면으로 만든 그 PGRST202 다. 선언=\(argument.declaration)"
        #expect(argument.declaration.lowercased().contains("default"), Comment(rawValue: why))
    }

    // 값까지 못박는다: default 가 null 이 아니면(예: 오늘 날짜 리터럴) 서버가 KST 로 정한다는 규약이 깨진다.
    let pDay = try #require(declared.first { $0.name == "p_day" })
    #expect(
        pDay.declaration.lowercased().replacingOccurrences(of: " ", with: "").contains("defaultnull"),
        "\(file.lastPathComponent): p_day 의 default 가 null 이 아니다: \(pDay.declaration)"
    )
}

// MARK: - ② 최종 정의가 실제로 핫픽스 파일인지 (순서가 곧 진실이다)

@Test
func minigame_board_의_최종_정의는_default_를_되돌린_파일이다() throws {
    let (file, _) = try finalDefinition(of: "minigame_board")
    let why = "최종 정의가 바뀌었다: \(file.lastPathComponent). 새 파일이 minigame_board 를 다시 정의했다면 "
        + "그 파일도 p_day 의 default 를 갖고 있는지 위 테스트로 확인된다 — 이 줄만 새 이름으로 고쳐라."
    #expect(file.lastPathComponent == "20260912151142_minigame_board_default_restore.sql", Comment(rawValue: why))

    // 사고를 낸 파일은 그대로 남아 있다(이미 적용된 마이그레이션이라 본문을 고치지 않는다).
    // 그 파일이 default 를 **안** 갖고 있다는 사실 자체가 '최종 정의로만 판정한다'는 이 파일의 전제다.
    let directory = try migrationsDirectory()
    let culprit = directory.appendingPathComponent("20260912143000_profile_center.sql")
    if let sql = try? String(contentsOf: culprit, encoding: .utf8) {
        let declared = try declaredArguments(stripSQLLineComments(sql), function: "minigame_board")
        let pDay = declared.first { $0.name == "p_day" }
        #expect(
            pDay?.declaration.lowercased().contains("default") == false,
            "20260912143000 이 고쳐졌다면 위 '최종 정의로만 판정' 전제를 다시 생각하라: \(pDay?.declaration ?? "nil")"
        )
    }
}

// MARK: - ③ 핫픽스는 문자열이 아니라 카탈로그로 되묻는다

/// 핫픽스 파일은 적용 직후 `pg_get_function_arguments` 로 자기 결과를 되묻는다.
/// 이 do$$ 블록이 사라지면 "적용했는데 default 가 안 붙은" 상태가 다시 무음이 된다.
@Test
func 핫픽스는_적용_직후_카탈로그로_자기_결과를_확인한다() throws {
    let (file, sql) = try finalDefinition(of: "minigame_board")
    #expect(sql.contains("pg_get_function_arguments"), "\(file.lastPathComponent): 사후 단언이 사라졌다")
    #expect(
        sql.contains("'p_game text, p_day date DEFAULT NULL::date'"),
        "\(file.lastPathComponent): 사후 단언이 비교하는 시그니처 문자열이 바뀌었다"
    )
    #expect(sql.contains("notify pgrst"), "\(file.lastPathComponent): 스키마 캐시 리로드 신호가 없다")
}
