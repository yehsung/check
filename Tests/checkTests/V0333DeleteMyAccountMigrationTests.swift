import Foundation
import Testing
@testable import check
@testable import CheckCore

// 앱스토어 정식 출시 준비(2026-09-18) — **계정 삭제 RPC 의 소스 계약**.
//
// `20260918120000_delete_my_account.sql` 이 만드는 `public.delete_my_account()` 는 폰(나 탭 → 설정 → 계정 삭제 시트)이
// 비밀번호 재인증 뒤 한 번 부르는 함수다. 서버 계약(SPEC "서버 계약"):
//   · 호출자 본인(auth.uid())의 auth.users 행을 지운다 — 나머지는 FK on delete cascade 로 따라 지워진다.
//   · feedback_reports.user_id 만 on delete set null(본문은 남고 익명이 된다 — 20260910120000 의 결정).
//   · 지우기 전에 내 팀 id 를 모아 두고, 지운 뒤 **남은 멤버가 0명인 그 팀들만** 지운다. 다른 팀은 안 건드린다.
//   · 로그인 안 한 호출은 예외. anon 은 실행권이 없고 authenticated 만 있다.
//
// 이 파일은 마이그레이션 **텍스트**를 읽어 그 계약이 글자로 남아 있는지 본다(V0313MigrationArgDefaultTests 와 같은 방식).
// 행동은 로컬 Postgres 하네스(replay-harness-v2 · 체인 99개 재생 뒤 파일 안 프로브 + 사용자 흉내 테스트)가 증명했고,
// 여기서는 그 행동을 만드는 문장이 사라지거나 넓어지는 것을 잡는다 — 특히 **다른 사람 행을 지우는 delete 가 끼어드는 것**.
//
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).

// MARK: - 마이그레이션 찾기

private struct DeleteAccountContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private let deleteAccountMigrationName = "20260918120000_delete_my_account.sql"
private let deleteAccountFunction = "delete_my_account"

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫 디렉토리를
/// 잡는다(워크트리면 `.claude/worktrees/<이름>` 을 지나 저장소 루트에서). `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다.
private func deleteAccountMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DeleteAccountContractError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw DeleteAccountContractError(
        "supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", ")). "
            + "워크트리라면 'cp -R /Users/yesung/check/supabase ./supabase' 로 들여오거나 CHECK_MIGRATIONS_DIR 로 알려 줘라."
    )
}

/// `--` 줄 주석을 걷어낸다.
private func stripLineComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 공백을 한 칸으로 접어 문장 모양 비교를 줄바꿈·들여쓰기와 무관하게 한다.
private func squashWhitespace(_ sql: String) -> String {
    sql.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func deleteAccountMigrationSQL() throws -> (raw: String, sql: String) {
    let file = try deleteAccountMigrationsDirectory().appendingPathComponent(deleteAccountMigrationName)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw DeleteAccountContractError("\(deleteAccountMigrationName) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    let raw = try String(contentsOf: file, encoding: .utf8)
    return (raw, stripLineComments(raw))
}

/// 함수 본문: `create or replace function public.delete_my_account()` 뒤의 `$fn$ … $fn$` 사이.
private func deleteAccountFunctionBody(_ sql: String) throws -> String {
    guard let header = sql.range(of: "create or replace function public.\(deleteAccountFunction)()", options: .caseInsensitive) else {
        throw DeleteAccountContractError("create or replace function public.\(deleteAccountFunction)() 헤더가 없다")
    }
    let afterHeader = sql[header.upperBound...]
    guard let open = afterHeader.range(of: "$fn$") else {
        throw DeleteAccountContractError("함수 본문의 달러 인용($fn$)이 없다")
    }
    let afterOpen = afterHeader[open.upperBound...]
    guard let close = afterOpen.range(of: "$fn$") else {
        throw DeleteAccountContractError("함수 본문의 닫는 달러 인용($fn$)이 없다")
    }
    return String(afterOpen[afterOpen.startIndex..<close.lowerBound])
}

/// 함수 헤더(create … as $fn$ 직전까지) — 속성 줄(security definer · set search_path)이 여기 있다.
private func deleteAccountFunctionHeader(_ sql: String) throws -> String {
    guard let header = sql.range(of: "create or replace function public.\(deleteAccountFunction)()", options: .caseInsensitive) else {
        throw DeleteAccountContractError("create or replace function public.\(deleteAccountFunction)() 헤더가 없다")
    }
    let afterHeader = sql[header.lowerBound...]
    guard let open = afterHeader.range(of: "$fn$") else {
        throw DeleteAccountContractError("함수 본문의 달러 인용($fn$)이 없다")
    }
    return squashWhitespace(String(afterHeader[afterHeader.startIndex..<open.lowerBound])).lowercased()
}

/// 본문 안의 `delete from …;` 문장들(세미콜론까지, 공백 접음, 소문자).
private func deleteStatements(in body: String) -> [String] {
    let squashed = squashWhitespace(body).lowercased()
    var statements: [String] = []
    var searchRange = squashed.startIndex..<squashed.endIndex
    while let start = squashed.range(of: "delete from", range: searchRange) {
        guard let end = squashed.range(of: ";", range: start.upperBound..<squashed.endIndex) else { break }
        statements.append(String(squashed[start.lowerBound..<end.upperBound]))
        searchRange = end.upperBound..<squashed.endIndex
    }
    return statements
}

// MARK: - ① 정의 · 속성

@Test
func 계정삭제_함수는_definer_이고_search_path_가_고정이다() throws {
    let (_, sql) = try deleteAccountMigrationSQL()
    let header = try deleteAccountFunctionHeader(sql)
    #expect(header.contains("returns void"), "반환형이 void 가 아니다(폰은 본문 없이 200/204 만 본다): \(header)")
    #expect(header.contains("language plpgsql"), "plpgsql 이 아니다: \(header)")
    #expect(header.contains("security definer"), "security definer 가 빠졌다 — authenticated 는 auth.users 를 못 지운다: \(header)")
    #expect(header.contains("set search_path = public"), "search_path 고정이 빠졌다(definer 함수의 필수 자물쇠): \(header)")
    #expect(!header.contains("security invoker"), "invoker 로 바뀌었다: \(header)")
}

@Test
func 계정삭제_함수의_최종_정의는_이_파일_하나뿐이다() throws {
    // 다른 파일이 create or replace 로 다시 정의하면 검사가 조용히 사라지는 전례(20260917140000 머리말)를 막는다.
    let directory = try deleteAccountMigrationsDirectory()
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var defining: [String] = []
    for file in files {
        let sql = stripLineComments(try String(contentsOf: file, encoding: .utf8)).lowercased()
        if sql.contains("function public.\(deleteAccountFunction)()")
            && (sql.contains("create or replace function public.\(deleteAccountFunction)()")
                || sql.contains("create function public.\(deleteAccountFunction)()")) {
            defining.append(file.lastPathComponent)
        }
    }
    #expect(defining == [deleteAccountMigrationName],
            "delete_my_account 를 정의하는 파일이 바뀌었다: \(defining). 다시 정의한 파일이 있으면 이 테스트의 단언을 그 파일에도 걸어라.")
}

// MARK: - ② 신원 게이트 · 실행권

@Test
func 계정삭제는_auth_uid_로만_대상을_정하고_비로그인은_예외다() throws {
    let (_, sql) = try deleteAccountMigrationSQL()
    let body = squashWhitespace(try deleteAccountFunctionBody(sql)).lowercased()
    #expect(body.contains("v_uid uuid := auth.uid()"), "대상이 auth.uid() 가 아니다 — 인자로 남의 id 를 받으면 안 된다: \(body.prefix(200))")
    #expect(body.contains("if v_uid is null then raise exception"), "비로그인(uid null) 게이트가 없다")
    #expect(body.contains("errcode = '28000'"), "비로그인 예외의 SQLSTATE 가 28000(invalid_authorization_specification)이 아니다 — PostgREST 가 403 으로 옮기는 코드다")
    // 인자를 받지 않는다 — 헤더가 `()` 인 것을 ① 이 잡고, 본문에 p_ 인자 참조가 없는지 여기서 본다.
    #expect(!body.contains(" p_"), "본문이 p_ 인자를 읽는다 — 이 함수는 인자가 없어야 한다(누구를 지울지는 토큰이 정한다)")
}

@Test
func 계정삭제_실행권은_authenticated_에게만_있다() throws {
    let (_, sql) = try deleteAccountMigrationSQL()
    let flat = squashWhitespace(sql).lowercased()
    #expect(flat.contains("revoke all on function public.delete_my_account() from public, anon"),
            "public·anon 회수 줄이 없다 — Supabase 는 새 함수에 anon 실행권을 딸려 보낸다")
    #expect(flat.contains("grant execute on function public.delete_my_account() to authenticated"),
            "authenticated 에게 주는 줄이 없다")
    #expect(!flat.contains("to anon, authenticated") && !flat.contains("delete_my_account() to anon"),
            "anon 에게 실행권을 준다")
    #expect(!flat.contains("grant execute on function public.delete_my_account() to public"), "public 에게 실행권을 준다")
    // 사후 단언이 카탈로그로 되묻는다(글자가 아니라 has_function_privilege).
    #expect(flat.contains("has_function_privilege('anon'"), "anon 차단을 카탈로그로 되묻는 사후 단언이 없다")
    #expect(flat.contains("has_function_privilege('authenticated'"), "authenticated 허용을 카탈로그로 되묻는 사후 단언이 없다")
}

// MARK: - ③ 무엇을 지우는가 — 본인 행과 빈 팀뿐

@Test
func 계정삭제의_delete_문은_전부_본인_또는_내_팀으로만_묶인다() throws {
    let (_, sql) = try deleteAccountMigrationSQL()
    let body = try deleteAccountFunctionBody(sql)
    let statements = deleteStatements(in: body)
    #expect(!statements.isEmpty, "본문에 delete 문이 없다")

    // 정확히 하나: 본인의 auth.users 행. 다른 조건으로 auth.users 를 지우는 문장은 있을 수 없다.
    let authDeletes = statements.filter { $0.contains("delete from auth.users") }
    #expect(authDeletes == ["delete from auth.users where id = v_uid;"],
            "auth.users 삭제 문장이 계약과 다르다: \(authDeletes)")

    // 나머지 delete 는 모두 v_uid(본인) 또는 v_teams(내가 있던 팀)로 묶인다 — 남의 행에 닿는 문장이 끼어들면 여기서 잡힌다.
    for statement in statements {
        #expect(statement.contains("v_uid") || statement.contains("v_teams"),
                "본인·내 팀으로 묶이지 않은 delete 가 있다: \(statement)")
        #expect(statement.contains(" where "), "where 없는 delete 가 있다: \(statement)")
    }

    // cascade 가 지우는 표를 손으로 지우지 않는다(손으로 지우기 시작하면 FK 규칙과 두 벌이 된다).
    for table in ["public.profiles", "public.memberships", "public.work_sessions", "public.work_statuses", "public.messages",
                  "public.todo_items", "public.client_devices", "public.ruby_ledger", "public.pokes"] {
        #expect(!statements.contains { $0.contains("delete from \(table)") }, "\(table) 을 손으로 지운다 — cascade 에 맡겨라")
    }
    let flatBody = squashWhitespace(body).lowercased()
    #expect(!flatBody.contains("truncate"), "truncate 가 있다")
    #expect(!flatBody.contains("delete from public.feedback_reports"), "제보를 지운다 — 제보는 set null 로 익명화되고 남아야 한다")
}

@Test
func 계정삭제는_내_팀을_먼저_적어_두고_남은_멤버가_0명인_팀만_지운다() throws {
    let (_, sql) = try deleteAccountMigrationSQL()
    let body = squashWhitespace(try deleteAccountFunctionBody(sql)).lowercased()

    // 순서: 팀 id 수집 → 팀 행 잠금 → auth.users 삭제 → 빈 팀 삭제. memberships 가 cascade 로 사라진 뒤에는 되물을 수 없다.
    let collect = try #require(body.range(of: "from public.memberships m where m.user_id = v_uid"), "내 팀 id 를 모으는 select 가 없다")
    #expect(body[..<collect.lowerBound].contains("array_agg(m.team_id)"), "팀 id 를 배열로 모으지 않는다")
    let lock = try #require(body.range(of: "for update"), "팀 행 잠금(for update)이 없다 — join_team 과 경합하면 방금 들어온 사람의 팀이 사라진다")
    let authDelete = try #require(body.range(of: "delete from auth.users where id = v_uid"), "auth.users 삭제가 없다")
    let teamDelete = try #require(body.range(of: "delete from public.teams t where t.id = any(v_teams)"), "빈 팀 정리 문장이 없다")
    #expect(collect.upperBound <= lock.lowerBound, "팀 id 수집이 잠금보다 뒤다")
    #expect(lock.upperBound <= authDelete.lowerBound, "잠금이 auth.users 삭제보다 뒤다")
    #expect(authDelete.upperBound <= teamDelete.lowerBound, "빈 팀 정리가 auth.users 삭제보다 앞이다(그때는 내 멤버십이 아직 있어 0명이 아니다)")

    // '남은 멤버 0명' 조건이 그 delete 문에 붙어 있다.
    let teamStatement = try #require(deleteStatements(in: body).first { $0.contains("delete from public.teams") })
    #expect(teamStatement.contains("not exists (select 1 from public.memberships m where m.team_id = t.id)"),
            "빈 팀 조건이 다르다: \(teamStatement)")
}

// MARK: - ④ cascade 전제 — 삭제 경로의 FK 는 전부 on delete cascade(제보함만 set null)

@Test
func 사용자_프로필_팀을_가리키는_FK_는_전부_cascade_이고_예외는_제보함_set_null_뿐이다() throws {
    // 마이그레이션 텍스트 전수. 새 표가 `references auth.users(id)` 를 cascade 없이 만들면 계정 삭제가 23503 으로 죽는다 —
    // 파일 안 §0 이 적용 시점에 카탈로그로 같은 것을 되묻지만, 여기서 먼저 잡아 db push 전에 안다.
    let directory = try deleteAccountMigrationsDirectory()
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    let targets = ["references auth.users(id)", "references public.profiles(id)", "references public.teams(id)"]
    var seen = 0
    var offenders: [String] = []
    for file in files {
        let sql = stripLineComments(try String(contentsOf: file, encoding: .utf8))
        for (index, line) in sql.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lowered = line.lowercased()
            guard targets.contains(where: { lowered.contains($0) }) else { continue }
            seen += 1
            if lowered.contains("on delete cascade") { continue }
            if file.lastPathComponent == "20260910120000_feedback_reports.sql", lowered.contains("on delete set null") { continue }
            offenders.append("\(file.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
        }
    }
    #expect(seen >= 30, "FK 선언을 \(seen)개밖에 못 찾았다 — 훑는 패턴이 실제 파일과 어긋났다(2026-09-18 기준 33개)")
    #expect(offenders.isEmpty, Comment(rawValue: "cascade 가 아닌 FK 가 있다 — 계정 삭제가 막힌다:\n" + offenders.joined(separator: "\n")))
}

@Test
func 마이그레이션은_적용_시점에_cascade_전제와_소유자_권한을_카탈로그로_되묻는다() throws {
    let (_, sql) = try deleteAccountMigrationSQL()
    let flat = squashWhitespace(sql).lowercased()
    // §0: 삭제 경로(auth.users → profiles → … 전이 폐쇄)의 FK 삭제 규칙을 pg_constraint 로 훑는다.
    #expect(flat.contains("confdeltype"), "FK 삭제 규칙을 카탈로그(pg_constraint.confdeltype)로 되묻는 §0 이 없다")
    // §3: 소유자 함정 — 함수 소유자에게 auth.users DELETE 권한이 없으면 배포를 멈춘다(운영에서 첫 사용자 앞에서 42501 로 죽지 않게).
    #expect(flat.contains("has_table_privilege(v_owner, 'auth.users', 'delete')"),
            "함수 소유자의 auth.users DELETE 권한을 되묻는 단언이 없다")
    #expect(flat.contains("edge function"), "권한이 없을 때의 대안(Edge Function + service_role)이 예외 문구에 없다")
    // 흐름 프로브: 합성 계정으로 본인 삭제·빈 팀 정리·남의 행 보존·제보 익명화·비로그인 거절을 실제로 돌린다.
    #expect(flat.contains("perform public.delete_my_account()"), "흐름 프로브가 함수를 실제로 부르지 않는다")
    #expect(flat.contains("set local role authenticated"), "흐름 프로브가 authenticated 로 내려가지 않는다(definer 경로를 안 탄다)")
    #expect(flat.contains("dma_probe_rollback"), "흐름 프로브의 센티널 롤백이 없다 — 같은 파일 3회 적용이 깨진다")
    #expect(flat.contains("notify pgrst"), "스키마 캐시 리로드 신호가 없다 — PostgREST 가 새 RPC 를 404 로 낸다")
}

// MARK: - ⑤ 아바타 — 최선 노력, 실패해도 계정 삭제는 진행

@Test
func 아바타_행_삭제는_최선_노력이고_실패가_계정_삭제를_막지_않는다() throws {
    let (_, sql) = try deleteAccountMigrationSQL()
    let body = squashWhitespace(try deleteAccountFunctionBody(sql)).lowercased()
    let avatar = try #require(deleteStatements(in: body).first { $0.contains("delete from storage.objects") },
                              "아바타 행(storage.objects) 삭제가 없다 — 공개 URL 이 떠난 사람의 얼굴을 계속 내준다")
    #expect(avatar.contains("bucket_id = 'avatars'") && avatar.contains("v_uid::text || '.jpg'"),
            "아바타 경로가 앱 업로드 경로(avatars/<uid>.jpg)와 다르다: \(avatar)")
    // 그 delete 는 예외 블록 안에 있고, 그 블록은 warning 만 낸다.
    let avatarRange = try #require(body.range(of: "delete from storage.objects"))
    let after = body[avatarRange.upperBound...]
    let exceptionRange = try #require(after.range(of: "exception when others then"), "아바타 삭제 뒤에 예외 블록이 없다")
    #expect(after[exceptionRange.upperBound...].hasPrefix(" raise warning"), "아바타 실패를 warning 이 아니라 예외로 올린다")
    // 아바타 삭제가 auth.users 삭제보다 앞이다(뒤면 uid 를 알아도 순서상 의미가 없진 않지만, 실패 시 계정이 이미 없어진 채 warning 이 남는다).
    let authRange = try #require(body.range(of: "delete from auth.users"))
    #expect(avatarRange.lowerBound < authRange.lowerBound, "아바타 삭제가 auth.users 삭제보다 뒤다")
}
