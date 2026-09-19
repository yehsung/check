import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.34 — **신고 관리 마이그레이션의 소스 계약**(20260920100000_report_admin.sql).
//
// 행동은 로컬 Postgres 하네스(replay-harness-v2 사본 · 체인 101개 재생 → 새 파일 3회 연속 적용 → 파일 안 프로브 23건,
// 합성 계정 갈래와 빌린 프로필 갈래 둘 다)가 증명했다. 여기서 보는 것은 **그 행동을 만드는 문장이 사라지거나 넓어지는 것**이고,
// 특히 위험한 다섯 가지다:
//   ① 운영자 판정을 is_app_admin() 말고 다른 것(클라 깃발 · 인라인 술어)으로 하는 것.
//   ② 실행권이 anon 에게 새는 것.
//   ③ 처리 메모가 신고자에게 새는 것 — 표 단위 select 가 새 칸까지 따라간다(마이그레이션 머리말 ★).
//   ④ FK 를 더해 계정 삭제 경로(20260918120000 §0)를 깨는 것.
//   ⑤ 서버가 돌려주는 칸 이름과 클라 디코더(`ContentReportAdminRow`)가 갈리는 것 — 그러면 목록이 조용히 비거나 칸이 nil 이다.
//
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).

private struct ReportAdminContractError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private let reportAdminMigrationName = "20260920100000_report_admin.sql"

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫 디렉토리를 잡는다.
/// `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다(V0333 계약 테스트들과 같은 방식).
private func reportAdminMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReportAdminContractError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw ReportAdminContractError(
        "supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", ")). "
            + "워크트리라면 'cp -R /Users/yesung/check/supabase ./supabase' 로 들여오거나 CHECK_MIGRATIONS_DIR 로 알려 줘라."
    )
}

/// `--` 줄 주석을 걷어낸다.
private func raStripLineComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func raSquash(_ sql: String) -> String {
    sql.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// (주석 걷은 원문, 공백 접고 소문자로 만든 한 줄).
private func reportAdminSQL() throws -> (code: String, flat: String) {
    let file = try reportAdminMigrationsDirectory().appendingPathComponent(reportAdminMigrationName)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw ReportAdminContractError("\(reportAdminMigrationName) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    let code = raStripLineComments(try String(contentsOf: file, encoding: .utf8))
    return (code, raSquash(code).lowercased())
}

/// `create or replace function public.<name>(` 부터 그 정의의 본문 끝(달러 인용 닫힘)까지. 없으면 nil.
private func raFunctionDefinition(_ name: String, in flat: String) -> String? {
    guard let start = flat.range(of: "create or replace function public.\(name)(") else { return nil }
    let rest = flat[start.lowerBound...]
    // 머리의 `as $tag$` 를 찾아 같은 태그가 다시 나오는 곳까지 자른다.
    guard let asRange = rest.range(of: " as $") else { return nil }
    let afterAs = rest[asRange.upperBound...]
    guard let tagEnd = afterAs.firstIndex(of: "$") else { return nil }
    let tag = "$" + afterAs[afterAs.startIndex..<tagEnd] + "$"
    let bodyStart = afterAs.index(after: tagEnd)
    guard let close = afterAs[bodyStart...].range(of: tag) else { return nil }
    return String(rest[rest.startIndex..<close.upperBound])
}

private let reportAdminFunctions: [(name: String, signature: String)] = [
    ("report_admin_list", "public.report_admin_list(text, int)"),
    ("report_admin_update", "public.report_admin_update(uuid, text, text)"),
    ("report_open_count", "public.report_open_count()"),
]

// MARK: - ① 운영자 판정 · definer

@Test
func 신고관리_RPC_셋은_definer_이고_search_path_가_고정이며_판정은_is_app_admin_하나다() throws {
    let (_, flat) = try reportAdminSQL()
    for function in reportAdminFunctions {
        let definition = try #require(raFunctionDefinition(function.name, in: flat), "\(function.name) 정의가 없다")
        #expect(definition.contains("security definer"), "\(function.name) 이 security definer 가 아니다")
        #expect(definition.contains("set search_path = public"), "\(function.name) 의 search_path 가 고정되지 않았다(definer 함수의 필수 자물쇠)")
        #expect(definition.contains("public.is_app_admin()"),
                "\(function.name) 에 운영자 게이트(is_app_admin)가 없다 — 비운영자가 신고를 읽거나 닫는다")
        // 관리자 술어를 인라인으로 다시 적으면 '관리자 정의가 두 곳'이라는 20260910120000 의 경고에 셋째가 생긴다.
        #expect(!definition.contains("role = 'admin'"), "\(function.name) 이 관리자 술어를 인라인으로 다시 적었다")
        // 클라 표시 깃발로 판정하면 안 된다(ultra 무제한 마이그레이션이 그 규약을 못 박았다).
        #expect(!definition.contains("unlimited"), "\(function.name) 이 표시 전용 깃발을 판정에 쓴다")
    }
    // 처리의 게이트는 **맨 앞 거절**이다(definer 라 RLS 를 지나치므로 이 한 줄이 전부다).
    let update = try #require(raFunctionDefinition("report_admin_update", in: flat))
    let gate = try #require(update.range(of: "if not public.is_app_admin() then raise exception 'report_forbidden'"),
                            "report_admin_update 의 운영자 거절이 없다")
    let write = try #require(update.range(of: "update public.content_reports"))
    #expect(gate.upperBound <= write.lowerBound, "운영자 게이트가 쓰기보다 뒤에 있다")
    // 목록은 예외가 아니라 0행(제보함 목록 규약) — where 에 판정이 붙어 있다.
    let list = try #require(raFunctionDefinition("report_admin_list", in: flat))
    #expect(list.contains("where (select public.is_app_admin())"), "report_admin_list 가 비운영자에게 0행을 주지 않는다")
    let count = try #require(raFunctionDefinition("report_open_count", in: flat))
    #expect(count.contains("case when public.is_app_admin()") && count.contains("else 0 end"),
            "report_open_count 가 비운영자에게 0 을 주지 않는다 — 숫자로 '신고가 몇 건 밀렸는지'가 샌다")
}

// MARK: - ② 실행권

@Test
func 신고관리_RPC_실행권은_authenticated_에게만_있다() throws {
    let (_, flat) = try reportAdminSQL()
    for function in reportAdminFunctions {
        #expect(flat.contains("revoke all on function \(function.signature) from public;"),
                "\(function.signature): public 회수 줄이 없다")
        #expect(flat.contains("revoke execute on function \(function.signature) from public, anon;"),
                "\(function.signature): anon 회수 줄이 없다 — Supabase 는 새 함수에 anon 실행권을 딸려 보낸다")
        #expect(flat.contains("grant execute on function \(function.signature) to authenticated;"),
                "\(function.signature): authenticated 에게 주는 줄이 없다 — 관리자 화면이 통째로 403 이다")
        #expect(!flat.contains("grant execute on function \(function.signature) to anon"), "\(function.signature): anon 에게 준다")
        #expect(!flat.contains("grant execute on function \(function.signature) to public"), "\(function.signature): public 에게 준다")
    }
    // 적용 시점에 카탈로그로 되묻는다(글자가 아니라 has_function_privilege).
    #expect(flat.contains("has_function_privilege('anon', r.fn::regprocedure, 'execute')"), "anon 차단을 카탈로그로 되묻지 않는다")
    #expect(flat.contains("has_function_privilege('authenticated', r.fn::regprocedure, 'execute')"))
}

// MARK: - ③ 처리 메모는 신고자에게 안 보인다

@Test
func 새_두_칸은_nullable_이고_authenticated_의_select_는_원래_아홉_칸뿐이다() throws {
    let (_, flat) = try reportAdminSQL()
    #expect(flat.contains("alter table public.content_reports add column if not exists admin_note text;"),
            "admin_note 가 nullable·기본값 없음으로 더해지지 않았다(기존 행을 다시 쓰면 안 된다)")
    #expect(flat.contains("alter table public.content_reports add column if not exists handled_at timestamptz;"))
    #expect(flat.contains("check (admin_note is null or char_length(admin_note) <= 500)"),
            "처리 메모 상한이 제보함 답장 메모(500)와 다르다")
    #expect(flat.contains("revoke select on public.content_reports from authenticated;"),
            "표 단위 select 를 거두지 않는다 — 표 단위 grant 는 새 칸까지 따라가 처리 메모가 신고자에게 샌다")
    let grantStart = try #require(flat.range(of: "grant select ("), "칸 단위 select grant 가 없다")
    let grantEnd = try #require(flat.range(of: ") on public.content_reports to authenticated;", range: grantStart.upperBound..<flat.endIndex))
    let columns = flat[grantStart.upperBound..<grantEnd.lowerBound]
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    #expect(columns == ["id", "reporter", "target_user", "message_id", "message_body", "reason", "detail", "status", "created_at"],
            "authenticated 가 읽는 칸이 원래 아홉 칸과 다르다: \(columns)")
    #expect(!columns.contains("admin_note") && !columns.contains("handled_at"), "운영자 기록 칸을 신고자에게 열었다")
    // 표 단위로 다시 주는 줄이 생기면 위 자물쇠가 통째로 무의미하다.
    #expect(!flat.contains("grant select on public.content_reports to authenticated"), "표 단위 select 를 다시 준다")
    #expect(!flat.contains("create policy"), "이 파일은 정책을 만들지 않는다 — 신고 표의 정책은 20260918180000 의 SELECT 하나다")
}

// MARK: - ④ 계정 삭제 경로

@Test
func 신고관리_마이그레이션은_FK_를_더하지_않고_삭제_폐쇄를_다시_묻는다() throws {
    let (_, flat) = try reportAdminSQL()
    #expect(!flat.contains(" references "), "FK 를 더했다 — 계정 삭제 경로(20260918120000 §0)의 cascade 단언을 다시 따져야 한다")
    // 적용 시점 카탈로그 단언: FK 는 20260918180000 의 둘 그대로 · 삭제 폐쇄에 set null 예외 둘뿐.
    #expect(flat.contains("'reporter:n,target_user:c'"), "content_reports 의 FK 구성을 되묻지 않는다")
    #expect(flat.contains("confdeltype"), "삭제 경로의 FK 삭제 규칙을 카탈로그로 되묻는 단언이 없다")
    #expect(flat.contains("not (c.conrelid = 'public.feedback_reports'::regclass and c.confdeltype = 'n')")
            && flat.contains("not (c.conrelid = 'public.content_reports'::regclass and c.confdeltype = 'n')"),
            "set null 예외가 제보함·신고함 둘이 아니다")
}

// MARK: - ⑤ 서버 반환 칸 ↔ 클라 디코더

@Test
func 목록_반환_칸은_클라_디코더가_읽는_이름과_같다() throws {
    let (_, flat) = try reportAdminSQL()
    let definition = try #require(raFunctionDefinition("report_admin_list", in: flat))
    let tableStart = try #require(definition.range(of: "returns table("))
    let tableEnd = try #require(definition.range(of: ") language sql", range: tableStart.upperBound..<definition.endIndex))
    let serverColumns = definition[tableStart.upperBound..<tableEnd.lowerBound]
        .split(separator: ",")
        .compactMap { $0.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) }
    // 디코더는 `.convertFromSnakeCase` 뒤의 카멜 이름으로 매칭한다 — 스네이크로 되돌려 대조한다.
    let clientColumns = ContentReportAdminRow.CodingKeys.allCases.map { key in
        key.rawValue.reduce(into: "") { result, character in
            if character.isUppercase { result += "_" + character.lowercased() } else { result.append(character) }
        }
    }
    #expect(serverColumns == clientColumns,
            "서버 반환 칸과 클라 디코더가 갈렸다 — 서버 \(serverColumns) · 클라 \(clientColumns)")
    // 적용 시점에도 같은 계약을 카탈로그로 되묻는다(pg_get_function_result).
    #expect(flat.contains("pg_get_function_result('public.report_admin_list(text,int)'::regprocedure)"))
}

@Test
func 앱이_생략하는_신고_RPC_인자는_default_를_갖는다() throws {
    // 앱은 목록을 **전체**로 받는다 — p_status 키가 빠진다. 그 인자가 default 를 잃으면 PGRST202(2026-09-12 미니게임 사고).
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    func keys<Body: Encodable>(_ body: Body) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: try encoder.encode(body)) as? [String: Any]
        return Set((object ?? [:]).keys)
    }
    #expect(try keys(ReportAdminListRequest(pStatus: nil, pLimit: 200)) == ["p_limit"])
    #expect(try keys(ReportAdminUpdateRequest(pId: "r", pStatus: "done", pNote: nil)) == ["p_id", "p_status"])
    #expect(try keys(ReportAdminUpdateRequest(pId: "r", pStatus: "done", pNote: "")) == ["p_id", "p_status", "p_note"],
            "빈 메모(= 지운다)가 키째 빠지면 서버는 '그대로 둔다'로 읽는다")

    let (_, flat) = try reportAdminSQL()
    #expect(flat.contains("create or replace function public.report_admin_list(p_status text default null, p_limit int default 200)"),
            "report_admin_list 의 인자 기본값이 계약(p_status null · p_limit 200)과 다르다")
    #expect(flat.contains("create or replace function public.report_admin_update(p_id uuid, p_status text, p_note text default null)"),
            "report_admin_update 의 p_note 에 default 가 없다 — 앱이 메모 없이 부르면 PGRST202 다")
    #expect(flat.contains("'p_status text default null::text, p_limit integer default 200'"), "사후 단언이 기본값을 되묻지 않는다")
}

// MARK: - 상태 어휘 · 메모 보존 · 프로브

@Test
func 처리는_새_어휘를_만들지_않고_메모_보존_규약을_지킨다() throws {
    let (_, flat) = try reportAdminSQL()
    let update = try #require(raFunctionDefinition("report_admin_update", in: flat))
    // 상태 어휘의 정본은 표의 CHECK — RPC 는 CHECK 위반을 이름 있는 예외로 옮길 뿐 목록을 한 벌 더 적지 않는다.
    #expect(update.contains("exception when check_violation then raise exception 'report_bad_status'"),
            "상태 거절이 표 CHECK 를 정본으로 쓰지 않는다")
    #expect(!update.contains("'doing'") && !update.contains("'wontfix'"), "RPC 가 상태 어휘를 한 벌 더 적었다 — 정본은 표 CHECK 다")
    #expect(update.contains("when p_note is null then admin_note"), "p_note null 이 메모를 보존하지 않는다")
    #expect(update.contains("handled_at = clock_timestamp()"), "처리 시각이 clock_timestamp() 가 아니다")
    for column in ["reason", "detail", "message_body", "message_id", "reporter", "target_user", "created_at"] {
        #expect(!update.contains("set \(column) =") && !update.contains(", \(column) ="), "처리가 신고 본문 칸(\(column))을 고친다")
    }
    // 클라 라벨이 붙은 넷이 서버 어휘와 같다(FeedbackStatus 를 그대로 쓰는 근거).
    #expect(ContentReportStatus.reportTransitions.map(\.rawValue) == ["open", "doing", "done", "wontfix"])
}

@Test
func 흐름_프로브는_기대_건수와_실제_단언_수가_같고_센티널로_롤백한다() throws {
    let (code, flat) = try reportAdminSQL()
    let expected = try #require(flat.range(of: "v_expected constant int := "))
    let digits = flat[expected.upperBound...].prefix { $0.isNumber }
    let declared = try #require(Int(digits))
    let increments = code.components(separatedBy: "probes := probes + 1;").count - 1
    #expect(declared == increments, "v_expected(\(declared))와 실제 단언 수(\(increments))가 다르다 — 카운터 단언이 거짓이 된다")
    #expect(declared >= 20, "프로브가 너무 적다(\(declared))")
    #expect(flat.contains("raise exception 'report_admin_probe_rollback'"), "센티널 롤백이 없다 — 같은 파일 3회 적용이 행을 남긴다")
    #expect(flat.contains("execute format('set local role %i', v_exec_role)"), "실행 역할 복귀가 set local role 이 아니다(RESET ROLE 함정)")
    #expect(!flat.contains("reset role"), "RESET ROLE 을 쓴다 — 운영 CLI 에서 세션 사용자(권한 0)로 떨어진다")
    #expect(flat.contains("notify pgrst"), "스키마 캐시 리로드 신호가 없다 — PostgREST 가 새 RPC 를 404 로 낸다")
    // 최상위 트랜잭션 제어가 없다(운영 CLI 가 파일을 한 트랜잭션으로 감싼다).
    for line in code.split(separator: "\n") where line.trimmingCharacters(in: .whitespaces).lowercased() == "begin;" {
        Issue.record("최상위 begin; 이 있다: \(line)")
    }
}

@Test
func 신고관리_마이그레이션_뒤_파일은_표_단위_select_를_되살리지_않는다() throws {
    // 이 파일이 20260918180000(신고 표) 뒤에 와야 칸을 더할 수 있다. 뒤에 다른 파일이 content_reports 의 select 를
    // 표 단위로 다시 주면 처리 메모가 신고자에게 새므로, 그런 파일이 생기면 이 테스트가 먼저 알린다.
    let files = try FileManager.default.contentsOfDirectory(at: try reportAdminMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
    let index = try #require(files.firstIndex(of: reportAdminMigrationName), "\(reportAdminMigrationName) 이 체인에 없다")
    #expect(files.firstIndex(of: "20260918180000_blocks_and_reports.sql").map { $0 < index } == true, "신고 표 파일보다 앞에 있다")
    for later in files[(index + 1)...] {
        let sql = raSquash(raStripLineComments(try String(
            contentsOf: try reportAdminMigrationsDirectory().appendingPathComponent(later), encoding: .utf8
        ))).lowercased()
        #expect(!sql.contains("grant select on public.content_reports to authenticated"),
                "\(later) 가 content_reports 의 표 단위 select 를 다시 준다 — 처리 메모가 신고자에게 샌다")
    }
}
