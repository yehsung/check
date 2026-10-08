import Foundation
import Testing

// v0.3.47 — 서버 마이그레이션 계약(20261008120000_ai_limits_devices.sql): 기기 이름 + 메인 맥 선택.
//
// 무엇을 지키는가. 서버는 **이미 기기별로** 저장한다(ai_limits 의 기본키가 (user_id, device_id, provider)).
// 이 마이그레이션이 더하는 것은 그 기기를 **부를 이름**(ai_limits.device_label)과 위젯 한 줄에 보여줄
// **메인 맥 한 대**(ai_limits_prefs) 뿐이다. 행동은 마이그레이션 자신이 증명한다 — 파일 안의 §6 카탈로그
// 단언 11종과 §7 행동 프로브 11종이 적용 시점에 역할을 **실제로 바꿔** 되묻고, 어긋나면 통째로 롤백한다
// (로컬 Postgres 15 에서 결함 21종을 심어 전부 빨개지는 것을 확인했다 — 그 중 둘은 카탈로그가 못 보고
//  프로브만 잡는다). 여기서 보는 것은 **그 문장들이 사라지거나 넓어지는 것**이다.
//
// 특히 위험한 일곱 가지(전부 아래에 단언이 하나씩 있다):
//   ① 회수가 부여보다 뒤로 가는 것 — Supabase 기본 특권 때문에 **delete 가 남는다**(2026-09-04 에 배포를 멈춘 결함).
//   ② select 정책이 빠지는 것 — merge-duplicates upsert 가 충돌 행을 읽어야 해서 **두 번째 upsert 부터 403**.
//   ③ 외래키가 둘 이상이 되는 것 — PostgREST 임베드가 모호해져 **기존 조회가 400** 으로 죽는다.
//      main_device_id 에 ai_limits 로 FK 를 거는 유혹이 바로 그 자리에 있고, 걸면 20261007120000 §5⑥ 도 같이 깨진다.
//   ④ 이 설정이 **profiles** 로 옮겨 가는 것 — 그 표는 표 단위 UPDATE 가 회수돼 있어(20260912161754) 칸 단위
//      grant 를 빼먹으면 "토글은 켜지는데 서버 값이 안 바뀐다" 가 된다. 그래서 전용 표로 간다.
//   ⑤ device_label 이 authenticated 의 쓰기 범위에서 빠지는 것 — "기기 이름만 조용히 안 올라간다".
//   ⑥ 읽기 RPC 가 생기는 것 — security definer 한 줄로 남이 어떤 맥을 쓰는지가 나간다.
//   ⑦ notify pgrst 가 사라지는 것 — 적용 직후 새 표는 404(PGRST205), 새 칸을 실은 upsert 는 400(PGRST204).

private let t47dMigration = "20261008120000_ai_limits_devices.sql"
private let t47dLimitsMigration = "20261007120000_ai_limits.sql"

private struct T47DError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `supabase/` 는 .gitignore 라 git worktree 에는 없다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫
/// 디렉토리를 잡는다(V0313·V0333·V0338·V0345 와 같은 방식). `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다 —
/// 뮤테이션 하네스가 공유 체크아웃의 실물을 안 건드리고 사본에 결함을 심어 이 단언들이 실제로 빨개지는지 보는 문이다.
private func t47dMigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw T47DError("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw T47DError("supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
/// 이 파일에는 문자열 리터럴 안의 `--` 가 없다(있으면 그 줄이 잘려 단언이 헛돈다 — 더하지 마라).
private func t47dStrip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func t47dRaw(_ name: String = t47dMigration) throws -> String {
    let file = try t47dMigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw T47DError("\(name) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

private func t47dSQL(_ name: String = t47dMigration) throws -> String { t47dStrip(try t47dRaw(name)) }

private func t47dOccurrences(_ haystack: String, _ needle: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var index = haystack.startIndex
    while let range = haystack.range(of: needle, range: index..<haystack.endIndex) {
        count += 1
        index = range.upperBound
    }
    return count
}

/// `verb` 뒤의 표 이름들을 모은다(V0345 와 같은 방식). `update public.` 은 접두어를 되붙인다.
private func t47dTargets(_ sql: String, verbs: [String]) -> Set<String> {
    var targets: Set<String> = []
    for verb in verbs {
        var cursor = sql.startIndex
        while let range = sql.range(of: verb, range: cursor..<sql.endIndex) {
            let token = sql[range.upperBound...].prefix { !" \n(;".contains($0) }
            targets.insert(verb.hasSuffix("public.") ? "public." + token : String(token))
            cursor = range.upperBound
        }
    }
    return targets
}

// MARK: - ① 체인에서의 자리

@Test
func 기기별리밋_마이그레이션은_리밋_원장_뒤에_오고_타임스탬프가_겹치지_않는다() throws {
    // ★ `index == names.count - 1`("내가 체인의 마지막이다")은 **두지 않는다** — 그건 뜻이 아니라 대리 지표였다
    //   (V0341 이 같은 이유로 지웠다). 뒤에 파일이 생기는 것 자체는 결함이 아니고, 반대로 뒤에 아무것도 없어도
    //   잘못된 순서는 잡지 못한다. 지켜야 하는 뜻은 "고칠 표가 먼저 만들어져 있다" 이고, 그건 아래 두 줄과
    //   파일 안 §0(to_regclass 로 실제로 되묻는다)이 잰다.
    let names = try FileManager.default
        .contentsOfDirectory(at: try t47dMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
    #expect(names.count > 30, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
    let index = try #require(names.firstIndex(of: t47dMigration), "\(t47dMigration) 이 체인에 없다")
    let limits = try #require(names.firstIndex(of: t47dLimitsMigration), "\(t47dLimitsMigration) 이 체인에 없다")
    #expect(limits < index, "리밋 원장(\(t47dLimitsMigration))보다 앞에 있다 — 고칠 표가 아직 없다")
    // 같은 타임스탬프가 둘이면 적용 순서가 파일시스템 순서에 맡겨진다.
    let stamps = names.map { String($0.prefix(14)) }
    #expect(Set(stamps).count == stamps.count, "같은 타임스탬프를 쓰는 마이그레이션이 있다")

    // 파일 안의 전제 단언도 그 자리에 있어야 한다(순서가 뒤집히면 42P01 로 죽는데 왜 죽었는지가 안 남는다).
    let sql = try t47dSQL()
    #expect(sql.contains("if to_regclass('public.ai_limits') is null then"), "§0 전제 검사가 없다")
    #expect(sql.contains("raise exception '§0 ai_limits 의 기본키가 (%) 다"),
            "기기별 저장이라는 전제(기본키에 device_id 가 있다)를 되묻지 않는다")
}

// MARK: - ② 회수가 부여보다 **먼저** 다

@Test
func 기기별리밋_표_권한은_전부_회수한_뒤에_필요한_것만_부여한다() throws {
    let sql = try t47dSQL()
    let revoke = "revoke all on table public.ai_limits_prefs from public, anon, authenticated;"
    let grant = "grant select, insert, update on table public.ai_limits_prefs to authenticated;"

    let revokeRange = try #require(sql.range(of: revoke),
                                  "전부 회수하는 줄이 없다 — Supabase 기본 특권 때문에 delete 가 남는다")
    let grantRange = try #require(sql.range(of: grant), "authenticated 부여 줄이 없다")
    #expect(revokeRange.lowerBound < grantRange.lowerBound,
            "회수가 부여보다 뒤에 온다 — 회수가 부여를 지워 authenticated 가 통째로 막히거나, 순서를 바꾸면 delete 가 남는다")

    for grantee in ["public", "anon", "authenticated"] {
        #expect(revoke.contains(grantee), "회수 대상에 \(grantee) 가 없다")
    }
    // ★ authenticated 에 delete 를 주는 길이 없다. 고른 맥을 되돌리는 길은 main_device_id 를 null 로 update 하는 것이다.
    #expect(!sql.contains("delete on table public.ai_limits_prefs to authenticated"),
            "authenticated 에 delete 를 준다 — 설정 행을 지우는 길이 열린다")
    #expect(sql.contains("grant select, insert, update, delete on table public.ai_limits_prefs to service_role;"),
            "service_role 부여가 없다 — e2e 픽스처·운영자 정리 경로가 사라진다")
    #expect(sql.contains("alter table public.ai_limits_prefs enable row level security;"), "RLS 를 켜지 않는다")
    // ai_limits 쪽 권한은 **건드리지 않는다** — 칸을 더하는 것은 표 ACL 을 바꾸지 않아야 한다.
    #expect(!sql.contains("grant select, insert, update on table public.ai_limits to"),
            "ai_limits 의 표 권한을 다시 준다 — 그 표의 권한은 20261007120000 의 것이다")
    #expect(!sql.contains("revoke all on table public.ai_limits from"),
            "ai_limits 의 권한을 거둔다 — 거두고 다시 주는 사이에 칸 단위 grant 로 좁아질 수 있다")
    #expect(sql.contains("raise exception '§6① anon 이 ai_limits_prefs 에 % 권한을 갖고 있다"))
    #expect(sql.contains("raise exception '§6② authenticated 가 ai_limits_prefs 를 지울 수 있다"))
    #expect(sql.contains("raise exception '§6⑪ anon 이 ai_limits 에 % 권한을 갖게 됐다"),
            "칸을 더하면서 ai_limits 의 권한이 흔들렸는지 되묻지 않는다")
}

// MARK: - ③ 본인 행 정책 3종 — select 가 빠지면 두 번째 upsert 부터 403

@Test
func 기기별리밋_본인_행_정책이_세_종류_다_있고_셋_다_본인_조건이다() throws {
    let sql = try t47dSQL()

    #expect(sql.contains("""
        create policy "users read own ai limit prefs"
          on public.ai_limits_prefs for select
          using (user_id = auth.uid());
        """), "select 정책이 없다 — merge-duplicates upsert 가 충돌 행을 못 읽어 두 번째 upsert 부터 403 이다")
    #expect(sql.contains("""
        create policy "users insert own ai limit prefs"
          on public.ai_limits_prefs for insert
          with check (user_id = auth.uid());
        """), "insert 정책이 없다")
    #expect(sql.contains("""
        create policy "users update own ai limit prefs"
          on public.ai_limits_prefs for update
          using (user_id = auth.uid())
          with check (user_id = auth.uid());
        """), "update 정책이 없다(using 과 with check 둘 다 필요하다)")

    // 정책은 **정확히 3개** 다. 허용형 정책은 OR 로 합쳐지므로 넷째가 끼면 위 제한이 통째로 무력해진다.
    #expect(t47dOccurrences(sql, "create policy") == 3,
            "정책이 3개가 아니다(\(t47dOccurrences(sql, "create policy"))개) — 넓은 정책이 끼면 본인 조건이 OR 로 풀린다")
    #expect(!sql.contains("using (true)"), "using (true) 정책이 있다 — 전원에게 열린다")
    #expect(!sql.contains("with check (true)"), "with check (true) 정책이 있다 — 남의 user_id 로 쓰는 길이 열린다")
    #expect(!sql.contains("for delete"), "delete 정책이 있다 — 지우는 길이 열린다")
    #expect(!sql.contains("for all"), "for all 정책이 있다 — 네 가지가 한 번에 열린다")
    // 이 파일은 ai_limits 의 정책을 건드리지 않는다(그 표의 3정책은 20261007120000 의 것이다).
    #expect(!sql.contains("on public.ai_limits for"), "ai_limits 에 정책을 더한다 — 그 표의 정책 수 단언(기대 3)이 깨진다")
    #expect(sql.contains("raise exception '§6④ ai_limits_prefs 정책이 %개다(기대 3)"))
    #expect(sql.contains("raise exception '§6④ 본인 select 정책이 %개다(기대 1)"))
}

// MARK: - ④ 외래키는 auth.users 하나뿐 · main_device_id 에 FK 를 걸지 않는다

@Test
func 기기별리밋_외래키는_auth_users_하나뿐이고_main_device_id_에_참조를_걸지_않는다() throws {
    let sql = try t47dSQL()

    // ★ 한 줄에 `references auth.users(id)` 와 `on delete cascade` 가 같이 있어야 한다 —
    //   V0333 의 전수 스캔이 줄 단위로 읽고, 떨어져 있으면 "cascade 아닌 FK" 로 집힌다.
    #expect(sql.contains("user_id uuid primary key references auth.users(id) on delete cascade,"),
            "auth.users 로의 cascade 외래키가 한 줄에 없다 — 계정 삭제가 23503 으로 죽고 V0333 전수 스캔도 빨개진다")
    #expect(t47dOccurrences(sql, "references ") == 1,
            "참조가 \(t47dOccurrences(sql, "references "))개다(기대 1) — 임베드가 모호해져 기존 조회가 400 이다")
    // ★ 여러 줄로 이은 설명은 `Comment(rawValue:)` 로 싼다 — Comment 는 **문자열 리터럴**만 받아
    //   `"…" + "…"` 를 그대로 넘기면 컴파일이 안 된다(이 파일이 그 실수로 한 번 빨갰다).
    #expect(!sql.contains("references public.ai_limits"),
            Comment(rawValue: "main_device_id 에 ai_limits 로 FK 를 걸었다 — 걸 유일키가 없고(기본키에 provider 가 있다), "
                              + "걸면 임베드가 모호해지고, 고른 맥의 행이 사라지는 일(설정 off · 3일 유령 게이트)이 23503 으로 막힌다"))
    #expect(!sql.contains("references public.profiles"), "profiles 로도 참조한다 — 임베드가 모호해진다")
    #expect(sql.contains("user_id uuid primary key"),
            "기본키가 user_id 하나가 아니다 — 맥마다 다른 메인을 주장하는 상태가 생긴다")
    #expect(sql.contains("raise exception '§6⑤ ai_limits_prefs 의 외래키가 %개다(기대 1)"))
    #expect(sql.contains("raise exception '§6⑥ 다른 표가 ai_limits_prefs 를 참조한다(%건)"),
            "반대 방향 참조를 막는 단언이 없다")
    #expect(sql.contains("raise exception '§6⑥ 다른 표가 ai_limits 를 참조한다(%건)"),
            "ai_limits 쪽 역방향 참조(20261007120000 §5⑥)를 여기서 다시 지키지 않는다")
    #expect(sql.contains("raise exception '§6⑧ ai_limits_prefs 의 기본키가 (%) 다(기대 user_id)"))
}

// MARK: - ⑤ profiles 로 가지 않는다 · 읽기 RPC 를 만들지 않는다

@Test
func 기기별리밋_설정은_profiles_가_아니라_전용_표에_두고_읽기_RPC_를_만들지_않는다() throws {
    let sql = try t47dSQL()

    // ★ profiles 는 표 단위 UPDATE 가 회수돼 있어(20260912161754) 칸을 더하면 칸 단위 grant 를 같이 주지 않는 한
    //   쓰기가 조용히 0행으로 끝난다 — "토글은 켜지는데 서버 값이 안 바뀐다".
    #expect(t47dTargets(sql, verbs: ["alter table public."]).isSubset(of: ["public.ai_limits", "public.ai_limits_prefs"]),
            Comment(rawValue: "이 파일이 고치는 표: \(t47dTargets(sql, verbs: ["alter table public."]).sorted().joined(separator: ", ")) "
                              + "— profiles 를 포함해 다른 표를 alter 하면 안 된다"))
    #expect(!sql.contains("grant update ("), "칸 단위 update grant 가 있다 — 이 축은 표 단위 grant 인 전용 표로 간다")

    // 이 파일이 만드는 함수는 **터치 트리거 하나** 뿐이다. 그 밖의 함수는 전부 읽기 경로가 된다.
    #expect(t47dOccurrences(sql, "create or replace function public.") == 1,
            "public 함수를 \(t47dOccurrences(sql, "create or replace function public."))개 만든다(기대 1 = 터치 트리거)")
    #expect(sql.contains("create or replace function public.touch_ai_limits_prefs_updated_at()"))
    #expect(!sql.contains("security definer"),
            "security definer 함수가 있다 — RLS 를 지나쳐 남이 어떤 맥을 쓰는지가 나간다")
    #expect(!sql.contains("token_usage"), "기존 토큰 축 표·함수를 건드린다 — 리밋은 별개의 축이다")
    #expect(sql.contains("create table if not exists public.ai_limits_prefs ("))
    #expect(t47dOccurrences(sql, "create table") == 1, "표를 하나만 만들어야 한다")
    // ★ 터치 트리거 본문에 표 이름을 글자로 적지 않는다 — 20261007120000 §5⑦ 이 "이름이 든 함수 본문" 을 세므로
    //   그 파일을 다시 적용하는 날(db reset · --include-all) 이 함수가 그 단언에 걸려 배포가 멈춘다.
    let body = try #require(sql.range(of: "returns trigger language plpgsql as $$"))
    let bodyEnd = try #require(sql.range(of: "$$;", range: body.upperBound..<sql.endIndex))
    #expect(!sql[body.upperBound..<bodyEnd.lowerBound].contains("ai_limits"),
            "터치 트리거 본문에 표 이름이 들어 있다 — 20261007120000 §5⑦(본문에 ai_limits 가 든 함수 0개)이 깨진다")
    #expect(sql.contains("raise exception '§6⑦ ai_limits_prefs 를 본문에서 읽는 함수가 %개다(기대 0)"))
    #expect(sql.contains("raise exception '§6⑦ ai_limits_prefs 를 읽는 뷰가 %개다(기대 0)"))
}

// MARK: - ⑥ notify pgrst 가 파일의 **마지막** 문장이다

@Test
func 기기별리밋_notify_pgrst_가_파일의_마지막_문장이다() throws {
    let sql = try t47dSQL()
    let tail = sql.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(tail.hasSuffix("notify pgrst, 'reload schema';"),
            "notify pgrst 가 끝에 없다 — 새 표는 404(PGRST205), 새 칸을 실은 upsert 는 400(PGRST204)이다. 끝은: \(String(tail.suffix(80)))")
    #expect(t47dOccurrences(sql, "notify pgrst") == 1, "notify pgrst 가 여러 번 있다")
    // 최상위 트랜잭션 제어는 운영 CLI 의 래퍼 트랜잭션을 깨 반쪽만 적용된 채 남긴다.
    for line in sql.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
        #expect(!["begin;", "commit;", "rollback;", "start transaction;"].contains(line),
                Comment(rawValue: "최상위 트랜잭션 제어 '\(line)' 가 있다 — CLI 래퍼 트랜잭션을 깬다"))
    }
}

// MARK: - ⑦ 자격증명·원문 신원이 늘지 않았다

@Test
func 기기별리밋_자격증명_문자열이_마이그레이션에_없다() throws {
    let raw = try t47dRaw()   // 주석까지 포함해 **원문**을 본다 — 설명에 토큰을 적는 것도 막는다.
    for secret in ["access_token", "refresh_token", "Bearer ", "sk-ant", "eyJ", "ChatGPT-Account-Id",
                   "oauth_creds", "find-generic-password", "claudeAiOauth"] {
        #expect(!raw.contains(secret), Comment(rawValue: "자격증명 관련 문자열 \"\(secret)\" 이 서버 파일에 있다"))
    }
    let sql = t47dStrip(raw)
    #expect(!sql.contains("email text"), "이메일 칸을 만든다 — 올라가는 것은 숫자와 기기 이름뿐이다")
    #expect(!sql.contains("account_id text"), "계정 식별자 칸을 만든다")
    // 새 표의 칸은 셋뿐임을 적용 시점에도 되묻는다(칸이 늘면 처리방침의 "…뿐입니다" 가 거짓이 된다).
    #expect(sql.contains("raise exception '§6⑧ ai_limits_prefs 의 칸이 (%) 다(기대 user_id,main_device_id,updated_at)"),
            "새 표의 칸 구성을 되묻는 단언이 없다 — 칸이 조용히 늘면 처리방침이 거짓이 된다")
}

// MARK: - ⑧ 칸 구성과 길이 가드 — 두 파일의 상한이 어긋나면 고를 수 있는 맥을 못 고른다

@Test
func 기기별리밋_칸과_길이_가드가_리밋_원장과_같은_상한을_쓴다() throws {
    let sql = try t47dSQL()

    // device_label: nullable text(구버전 맥은 안 보낸다) · 빈 문자열 금지 · 64자 상한.
    #expect(sql.contains("alter table public.ai_limits add column if not exists device_label text;"),
            "device_label 칸을 더하지 않거나 not null·default 를 붙였다 — not null 이면 구버전 맥의 업로드가 23502 로 통째로 막힌다")
    #expect(sql.contains("""
        alter table public.ai_limits add constraint ai_limits_device_label_sane
          check (device_label is null or char_length(device_label) between 1 and 64);
        """), "device_label 길이 CHECK 가 없거나 모양이 바뀌었다(1…64 가 빈 문자열 금지와 상한을 한 줄로 한다)")
    #expect(sql.contains("alter table public.ai_limits drop constraint if exists ai_limits_device_label_sane;"),
            "이름 붙인 CHECK 를 drop → add 로 넣지 않는다 — 재적용 때 같은 제약이 겹쳐 쌓인다")
    #expect(sql.contains("raise exception '§6⑩ authenticated 가 ai_limits.device_label 을 못 쓴다"),
            "새 칸이 authenticated 의 쓰기 범위 안인지 되묻지 않는다 — 기기 이름만 조용히 안 올라간다")
    #expect(sql.contains("has_column_privilege('anon', 'public.ai_limits', 'device_label', 'SELECT')"),
            "anon 이 기기 이름을 읽을 수 있는지 되묻지 않는다")

    // main_device_id: nullable(= 아직 안 골랐다) · 빈 문자열 금지 · 상한은 ai_limits.device_id 와 **같아야** 한다.
    #expect(sql.contains("  main_device_id text,"), "main_device_id 가 nullable text 가 아니다 — null 이 '아직 안 골랐다' 다")
    #expect(sql.contains("""
        alter table public.ai_limits_prefs add constraint ai_limits_prefs_main_device_sane
          check (main_device_id is null or char_length(main_device_id) between 1 and 128);
        """), "main_device_id 길이 CHECK 가 없거나 모양이 바뀌었다")
    #expect(sql.contains("  updated_at timestamptz not null default now()"), "updated_at 칸이 없다")

    // ★ 두 파일이 어긋나면: 저쪽이 받아 적은 device_id 를 이쪽이 못 담아, 고를 수 있는 맥을 고르는 순간 23514 다.
    let limits = try t47dSQL(t47dLimitsMigration)
    let deviceIdBound = try #require(
        limits.range(of: "length(device_id) between 1 and ").map { range -> String in
            String(limits[range.upperBound...].prefix { $0.isNumber })
        }, "\(t47dLimitsMigration) 에서 device_id 상한을 못 읽었다 — 이 비교가 헛돈다")
    let mainBound = try #require(
        sql.range(of: "char_length(main_device_id) between 1 and ").map { range -> String in
            String(sql[range.upperBound...].prefix { $0.isNumber })
        }, "main_device_id 상한을 못 읽었다")
    #expect(deviceIdBound == mainBound,
            "device_id 상한(\(deviceIdBound))과 main_device_id 상한(\(mainBound))이 다르다 — 긴 device_id 를 가진 맥은 메인으로 고를 수 없다")

    // 터치 트리거(PostgREST 는 본문에 온 칸만 SET 한다 — 없으면 updated_at 이 영영 insert 시각이다).
    #expect(sql.contains("""
        create trigger touch_ai_limits_prefs_updated_at
          before insert or update on public.ai_limits_prefs
          for each row execute function public.touch_ai_limits_prefs_updated_at();
        """))
    #expect(sql.contains("raise exception '§6⑨ ai_limits 의 터치 트리거가 사라졌다"),
            "칸을 더하면서 ai_limits 의 터치 트리거를 떨어뜨렸는지 되묻지 않는다")
}

// MARK: - ⑨ 적용 시점 단언·프로브가 사라지지 않았다

@Test
func 기기별리밋_적용_시점_단언과_행동_프로브가_제자리에_있다() throws {
    let sql = try t47dSQL()

    // §6 카탈로그 단언: anon 4종 · authenticated delete · PUBLIC grant · RLS · PK · 칸 구성 · 트리거 · 칸 권한.
    #expect(t47dOccurrences(sql, "foreach v_t in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop") == 2,
            "anon 의 네 권한을 두 표(새 표 + ai_limits)에서 전부 되묻지 않는다")
    #expect(sql.contains("a.grantee = 0"), "PUBLIC 앞으로 난 grant 를 보는 단언이 없다")
    #expect(sql.contains("raise exception '§6④ ai_limits_prefs 의 RLS 가 꺼져 있다"))
    #expect(sql.contains("raise notice '§6 카탈로그 단언 11종 통과"), "카탈로그 단언 요약이 없다")

    // §7 행동 프로브: 역할을 실제로 바꿔 잰다. 복귀는 reset role 이 아니라 **캡처한 실행 역할**이다
    //   (reset role 은 CLI 링크드 연결에서 세션 사용자로 떨어져 다음 SELECT 를 42501 로 죽인다 — 2026-08-31 전례).
    #expect(sql.contains("v_exec_role text := current_user;"), "실행 역할을 캡처하지 않는다")
    #expect(sql.contains("execute format('set local role %I', v_exec_role);"), "캡처한 역할로 복귀하지 않는다")
    #expect(!sql.contains("reset role"), "reset role 로 복귀한다 — 운영 연결에서 42501 이 난다")
    #expect(sql.contains("set local role %I', p_role"), "역할 전환 헬퍼가 없다")
    #expect(sql.contains("raise exception 'AI_LIMITS_DEVICES_PROBE_ROLLBACK_SENTINEL';"),
            "센티널 롤백이 없다 — 프로브 행이 운영 표에 남는다")
    #expect(sql.contains("if probes <> v_expected then"), "프로브 수를 되묻지 않는다 — 검사가 조용히 빠진다")
    #expect(sql.contains("raise exception '① 남의 행이 %건 보인다(기대 0)"), "남의 행 격리 프로브가 없다")
    #expect(sql.contains("raise exception '② 남의 user_id 로 행을 넣는 데 성공했다"))
    #expect(sql.contains("on conflict (user_id) do update"),
            "merge-duplicates upsert 를 실제로 돌리지 않는다 — select 정책 누락이 안 잡힌다")
    #expect(sql.contains("raise exception '⑤ authenticated 가 본인 행을 지웠다"))
    #expect(sql.contains("raise exception '⑥ anon 이 ai_limits_prefs 를 %행 읽었다"))
    #expect(sql.contains("raise exception '⑩ 한 계정에 둘째 행이 들어갔다"),
            "계정당 한 값(둘째 insert 가 23505)을 실제로 재지 않는다")
    #expect(sql.contains("raise exception '⑨ authenticated 가 올린 device_label 이 (%) 다"),
            "authenticated 가 **실제로** 기기 이름을 올려 보는 프로브가 없다 — 칸 권한 결함이 카탈로그만으로는 안 잡힌다")
    #expect(sql.contains("when unique_violation then"), "unique_violation 을 잡는 프로브가 없다")
    #expect(t47dOccurrences(sql, "when check_violation then null;") == 4,
            Comment(rawValue: "길이 가드 프로브가 4개가 아니다(\(t47dOccurrences(sql, "when check_violation then null;"))개) — "
                              + "빈 문자열·상한 초과 × (main_device_id · device_label)"))

    // 프로브가 손대는 표는 두 리밋 표와 auth.users 뿐이다(운영 표를 더럽히는 프로브는 두지 않는다).
    let targets = t47dTargets(sql, verbs: ["insert into ", "delete from ", "update public."])
    #expect(targets.isSubset(of: ["public.ai_limits", "public.ai_limits_prefs", "auth.users"]),
            "프로브가 다른 표를 쓴다: \(targets.sorted().joined(separator: ", "))")
}

// MARK: - ⑩ 달러 인용 함정

@Test
func 기기별리밋_달러_인용_태그가_본문_주석에_글자로_적혀_있지_않다() throws {
    let raw = try t47dRaw()
    // 2026-09-14 app_release 사고: 달러 인용 본문 안의 `--` 는 주석이 아니라 글자라, 설명에 태그 이름을 적으면
    // 그 자리에서 본문이 끝나 나머지가 SQL 로 해석된다. 태그가 **정확히 두 번**(열고 닫기)만 나오는지 센다.
    for tag in ["$pre$", "$assert$", "$probe$", "$tmp$", "$tail$", "$$"] {
        #expect(t47dOccurrences(raw, tag) == 2,
                Comment(rawValue: "달러 태그 \(tag) 가 \(t47dOccurrences(raw, tag))번 나온다(기대 2) — "
                                  + "주석에 태그 글자를 적으면 본문이 거기서 끝난다"))
    }
    // 줄 주석 뒤에 태그 글자가 하나도 없다(위의 짝수 검사만으로는 "주석에 두 번 적기" 를 못 잡는다).
    for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
        guard let dash = line.range(of: "--") else { continue }
        let comment = line[dash.upperBound...]
        for tag in ["$pre$", "$assert$", "$probe$", "$tmp$", "$tail$"] {
            #expect(!comment.contains(tag),
                    Comment(rawValue: "주석에 달러 태그 \(tag) 가 글자로 적혀 있다: \(line.trimmingCharacters(in: .whitespaces))"))
        }
    }
}
