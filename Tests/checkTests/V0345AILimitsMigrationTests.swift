import Foundation
import Testing

// v0.3.45 — 서버 마이그레이션 계약(20261007120000_ai_limits.sql): AI 구독 **리밋** 원장.
//
// 이 파일이 지키는 것은 "표가 만들어진다" 가 아니라 **"본인만 보이는 성질이 조용히 풀리지 않는다"** 와
// **"기존 토큰 축이 안 다쳤다"** 이다. 행동은 마이그레이션 자신이 증명한다 — 파일 안의 §5 카탈로그 단언 10종과
// §6 행동 프로브 10종이 적용 시점에 역할을 **실제로 바꿔** 되묻고, 어긋나면 raise exception 으로 통째로 롤백한다
// (로컬 Postgres 에서 결함 11종을 심어 전부 빨개지는 것을 확인했다). 여기서 보는 것은 **그 문장들이 사라지거나
// 넓어지는 것**이다.
//
// 특히 위험한 여섯 가지(전부 아래에 단언이 하나씩 있다):
//   ① 회수가 부여보다 뒤로 가는 것 — Supabase 기본 특권 때문에 **delete 가 남는다**(2026-09-04 에 배포를 멈춘 결함).
//   ② select 정책이 빠지는 것 — PostgREST merge-duplicates upsert 가 충돌 행을 읽어야 해서 **두 번째 업로드부터 403**.
//   ③ 외래키가 둘 이상이 되는 것 — PostgREST 임베드가 모호해져 **기존 팀 현황 조회가 400** 으로 죽는다.
//   ④ 읽기 RPC 가 생기는 것 — security definer 한 줄로 남의 구독 상태가 전원에게 나간다.
//   ⑤ notify pgrst 가 사라지는 것 — 적용 직후 클라가 404(PGRST205)를 받는다.
//   ⑥ 자격증명·토큰 문자열이 서버 파일로 새는 것.

private let t45Migration = "20261007120000_ai_limits.sql"

private struct T45Error: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `supabase/` 는 .gitignore 라 git worktree 에는 없다 — 조상을 훑어 올라가며 `supabase/migrations` 가 있는 첫
/// 디렉토리를 잡는다(V0313·V0333·V0338 과 같은 방식). `CHECK_MIGRATIONS_DIR` 로 덮어쓸 수 있다 — 뮤테이션 하네스가
/// 공유 체크아웃의 실물을 안 건드리고 사본에 결함을 심어 이 단언들이 실제로 빨개지는지 보는 문이다.
private func t45MigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw T45Error("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
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
    throw T45Error("supabase/migrations 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
/// 이 파일에는 문자열 리터럴 안의 `--` 가 없다(있으면 그 줄이 잘려 단언이 헛돈다 — 더하지 마라).
private func t45Strip(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func t45Raw() throws -> String {
    let file = try t45MigrationsDirectory().appendingPathComponent(t45Migration)
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw T45Error("\(t45Migration) 이 \(file.deletingLastPathComponent().path) 에 없다")
    }
    return try String(contentsOf: file, encoding: .utf8)
}

private func t45SQL() throws -> String { t45Strip(try t45Raw()) }

private func t45Occurrences(_ haystack: String, _ needle: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var index = haystack.startIndex
    while let range = haystack.range(of: needle, range: index..<haystack.endIndex) {
        count += 1
        index = range.upperBound
    }
    return count
}

// MARK: - ① 체인에서의 자리

@Test
func 리밋_마이그레이션은_체인의_마지막이고_토큰_원장_뒤에_온다() throws {
    let names = try FileManager.default
        .contentsOfDirectory(at: try t45MigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
    #expect(names.count > 30, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
    let index = try #require(names.firstIndex(of: t45Migration), "\(t45Migration) 이 체인에 없다")
    // ★ 여기 있던 `index == names.count - 1`("내가 체인의 마지막이다")은 **지웠다**(2026-10-08) — V0341 이 같은 이유로
    //   먼저 지운 대리 지표다. 뒤에 파일이 생기는 것 자체는 결함이 아니다(20261008120000 이 이 표에 device_label 을
    //   더한다). 지키려던 뜻은 "이 표가 만들어진 뒤에 고친다" 이고 그건 뒤 파일 쪽 §0(to_regclass 전제)과
    //   V0347 의 순서 단언이 직접 잰다. 반대로 뒤에 아무 파일이 없어도 이 대리는 넓어진 권한을 못 봤다.
    #expect(index >= 1, "\(t45Migration) 앞에 아무 파일도 없다 — 체인을 잘못 읽었다")
    // 같은 타임스탬프가 둘이면 적용 순서가 파일시스템 순서에 맡겨진다.
    let stamps = names.map { String($0.prefix(14)) }
    #expect(Set(stamps).count == stamps.count, "같은 타임스탬프를 쓰는 마이그레이션이 있다")
}

// MARK: - ② 회수가 부여보다 **먼저** 다

@Test
func 표_권한은_전부_회수한_뒤에_필요한_것만_부여한다() throws {
    let sql = try t45SQL()
    let revoke = "revoke all on table public.ai_limits from public, anon, authenticated;"
    let grant = "grant select, insert, update on table public.ai_limits to authenticated;"

    let revokeRange = try #require(sql.range(of: revoke),
                                  "전부 회수하는 줄이 없다 — Supabase 기본 특권 때문에 delete 가 남는다")
    let grantRange = try #require(sql.range(of: grant), "authenticated 부여 줄이 없다")
    #expect(revokeRange.lowerBound < grantRange.lowerBound,
            "회수가 부여보다 뒤에 온다 — 회수가 부여를 지워 authenticated 가 통째로 막히거나, 순서를 바꾸면 delete 가 남는다")

    // 세 수신자 전부에게서 거둔다. 하나라도 빠지면 그 역할엔 기본 특권의 ALL 이 남는다.
    for grantee in ["public", "anon", "authenticated"] {
        #expect(revoke.contains(grantee), "회수 대상에 \(grantee) 가 없다")
    }
    // ★ authenticated 에 delete 를 주는 길이 없다. 행을 지우는 길은 계정 삭제(cascade)와 service_role 뿐이다.
    #expect(!sql.contains("delete on table public.ai_limits to authenticated"),
            "authenticated 에 delete 를 준다 — 본인 리밋 행을 지우는 길이 열린다")
    #expect(sql.contains("grant select, insert, update, delete on table public.ai_limits to service_role;"),
            "service_role 부여가 없다 — e2e 픽스처·운영자 정리 경로가 사라진다")
    #expect(sql.contains("alter table public.ai_limits enable row level security;"), "RLS 를 켜지 않는다")
}

// MARK: - ③ 본인 행 정책 3종 — select 가 빠지면 두 번째 업로드부터 403

@Test
func 본인_행_정책이_세_종류_다_있고_셋_다_본인_조건이다() throws {
    let sql = try t45SQL()

    #expect(sql.contains("""
        create policy "users read own ai limits"
          on public.ai_limits for select
          using (user_id = auth.uid());
        """), "select 정책이 없다 — merge-duplicates upsert 가 충돌 행을 못 읽어 두 번째 업로드부터 403 이다")
    #expect(sql.contains("""
        create policy "users insert own ai limits"
          on public.ai_limits for insert
          with check (user_id = auth.uid());
        """), "insert 정책이 없다")
    #expect(sql.contains("""
        create policy "users update own ai limits"
          on public.ai_limits for update
          using (user_id = auth.uid())
          with check (user_id = auth.uid());
        """), "update 정책이 없다(using 과 with check 둘 다 필요하다)")

    // 정책은 **정확히 3개** 다. 허용형 정책은 OR 로 합쳐지므로 넷째가 끼면 위 제한이 통째로 무력해진다.
    #expect(t45Occurrences(sql, "create policy") == 3,
            "정책이 3개가 아니다(\(t45Occurrences(sql, "create policy"))개) — 넓은 정책이 끼면 본인 조건이 OR 로 풀린다")
    #expect(!sql.contains("using (true)"), "using (true) 정책이 있다 — 전원에게 열린다")
    #expect(!sql.contains("for delete"), "delete 정책이 있다 — 지우는 길이 열린다")
    #expect(!sql.contains("for all"), "for all 정책이 있다 — 네 가지가 한 번에 열린다")
    // 적용 시점 단언도 그 자리에 있어야 한다(파일을 고치는 사람이 테스트만 보고 넘어가지 않게).
    #expect(sql.contains("raise exception '§5④ ai_limits 정책이 %개다(기대 3)"))
    #expect(sql.contains("raise exception '§5④ 본인 select 정책이 %개다(기대 1)"))
}

// MARK: - ④ 외래키는 auth.users 하나뿐

@Test
func 외래키는_auth_users_하나뿐이고_cascade_다() throws {
    let sql = try t45SQL()

    #expect(sql.contains("user_id uuid not null references auth.users(id) on delete cascade"),
            "auth.users 로의 cascade 외래키가 없다 — 계정 삭제가 23503 으로 죽는다")
    // ★ 둘 이상이면 PostgREST 임베드가 모호해져 기존 팀 현황 조회가 400 으로 죽는다(이 저장소 전례).
    #expect(t45Occurrences(sql, "references ") == 1,
            "참조가 \(t45Occurrences(sql, "references "))개다(기대 1) — 임베드가 모호해져 기존 조회가 400 이다")
    #expect(!sql.contains("references public.profiles"), "profiles 로도 참조한다 — 임베드가 모호해진다")
    #expect(sql.contains("primary key (user_id, device_id, provider)"),
            "기본키가 (user_id, device_id, provider) 가 아니다")
    #expect(sql.contains("raise exception '§5⑤ ai_limits 의 외래키가 %개다(기대 1)"))
    #expect(sql.contains("raise exception '§5⑥ 다른 표가 ai_limits 를 참조한다(%건)"),
            "반대 방향 참조를 막는 단언이 없다")
}

// MARK: - ⑤ 읽기 RPC 를 만들지 않는다 · 순위판에 섞지 않는다

@Test
func 읽기_RPC_를_만들지_않고_순위판_RPC_를_건드리지_않는다() throws {
    let sql = try t45SQL()

    // 이 파일이 만드는 함수는 **터치 트리거 하나** 뿐이다. 그 밖의 함수는 전부 읽기 경로가 된다.
    #expect(t45Occurrences(sql, "create or replace function public.") == 1,
            "public 함수를 \(t45Occurrences(sql, "create or replace function public."))개 만든다(기대 1 = 터치 트리거)")
    #expect(sql.contains("create or replace function public.touch_ai_limits_updated_at()"))
    #expect(!sql.contains("security definer"),
            "security definer 함수가 있다 — RLS 를 지나쳐 남의 행이 나간다")
    #expect(!sql.contains("token_usage_board"), "순위판 RPC 를 건드린다 — 전원에게 남의 구독 상태가 나간다")
    #expect(!sql.contains("token_usage"), "기존 토큰 축 표·함수를 건드린다 — 리밋은 별개의 새 축이다")
    #expect(sql.contains("create table if not exists public.ai_limits ("))
    #expect(t45Occurrences(sql, "create table") == 1, "표를 하나만 만들어야 한다 — 기존 표에 칸을 더하지도 않는다")
    // 적용 시점에도 되묻는다.
    #expect(sql.contains("raise exception '§5⑦ ai_limits 를 본문에서 읽는 함수가 %개다(기대 0)"))
    #expect(sql.contains("raise exception '§5⑦ ai_limits 를 읽는 뷰가 %개다(기대 0)"))
}

// MARK: - ⑥ notify pgrst 가 파일의 **마지막** 문장이다

@Test
func notify_pgrst_가_파일의_마지막_문장이다() throws {
    let sql = try t45SQL()
    let tail = sql.trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(tail.hasSuffix("notify pgrst, 'reload schema';"),
            "notify pgrst 가 끝에 없다 — 적용 직후 클라가 404(PGRST205)를 받는다. 끝은: \(String(tail.suffix(80)))")
    #expect(t45Occurrences(sql, "notify pgrst") == 1, "notify pgrst 가 여러 번 있다")
}

// MARK: - ⑦ 자격증명·토큰이 서버 파일에 없다

@Test
func 자격증명_문자열이_마이그레이션에_없다() throws {
    let raw = try t45Raw()   // 주석까지 포함해 **원문**을 본다 — 설명에 토큰을 적는 것도 막는다.
    for secret in ["access_token", "refresh_token", "Bearer ", "sk-ant", "eyJ", "ChatGPT-Account-Id",
                   "oauth_creds", "find-generic-password", "claudeAiOauth"] {
        #expect(!raw.contains(secret), Comment(rawValue: "자격증명 관련 문자열 \"\(secret)\" 이 서버 파일에 있다"))
    }
    // 올라오는 칸에 원문 신원이 없다. 지문은 해시만 받고 CHECK 가 그걸 강제한다.
    let sql = t45Strip(raw)
    #expect(!sql.contains("email text"), "이메일 칸을 만든다 — 서버에는 숫자만 올린다")
    #expect(sql.contains("account_fingerprint not like '%@%'"),
            "지문 칸에 이메일 모양이 들어오는 것을 막는 CHECK 가 없다")
    #expect(sql.contains("constraint ai_limits_no_raw_identity check"))
}

// MARK: - ⑧ 칸 구성과 단위 가드

@Test
func 칸_구성과_퍼센트_가드가_그대로다() throws {
    let sql = try t45SQL()
    for column in ["user_id uuid not null", "device_id text not null", "provider text not null",
                   "five_hour_percent double precision", "five_hour_resets_at timestamptz",
                   "weekly_percent double precision", "weekly_resets_at timestamptz",
                   "plan_label text", "account_fingerprint text",
                   "observed_at timestamptz not null", "updated_at timestamptz not null default now()"] {
        #expect(sql.contains(column), Comment(rawValue: "칸 \"\(column)\" 이 없다"))
    }
    // observed_at 에 기본값을 두면 낡은 값이 영원히 신선해 보인다(신선도·하한 규칙이 거짓이 된다).
    #expect(!sql.contains("observed_at timestamptz not null default"),
            "observed_at 에 기본값을 뒀다 — 안 보낸 행이 조용히 '지금' 으로 기록돼 신선도 규칙이 거짓이 된다")
    // 퍼센트는 0…100 이고 NaN·무한은 거부된다(NaN 이 들어가면 폰의 JSON 파싱이 통째로 깨진다).
    #expect(sql.contains("constraint ai_limits_percent_range check"))
    #expect(sql.contains("five_hour_percent >= 0 and five_hour_percent <= 100"))
    #expect(sql.contains("weekly_percent >= 0 and weekly_percent <= 100"))
    // 제공자 어휘 CHECK 는 **일부러 없다** — 넷째 제공자가 붙는 날 구버전 맥이 23514 로 막히지 않게.
    #expect(!sql.contains("provider in ('claude'"),
            "제공자 어휘를 CHECK 로 박았다 — 넷째 제공자가 붙는 날 구버전 맥의 업로드가 23514 로 통째로 막힌다")
    // 터치 트리거(PostgREST 는 본문에 온 칸만 SET 한다 — 없으면 updated_at 이 영영 insert 시각이다).
    #expect(sql.contains("""
        create trigger touch_ai_limits_updated_at
          before insert or update on public.ai_limits
          for each row execute function public.touch_ai_limits_updated_at();
        """))
}

// MARK: - ⑨ 적용 시점 단언·프로브가 사라지지 않았다

@Test
func 적용_시점_단언과_행동_프로브가_제자리에_있다() throws {
    let sql = try t45SQL()

    // §5 카탈로그 단언: anon 4종 · authenticated delete · PUBLIC grant · RLS · PK 순서 · 터치 트리거 · 칸 누수.
    #expect(sql.contains("foreach v_t in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop"),
            "anon 의 네 권한을 전부 되묻지 않는다")
    #expect(sql.contains("raise exception '§5① anon 이 ai_limits 에 % 권한을 갖고 있다"))
    #expect(sql.contains("raise exception '§5② authenticated 가 ai_limits 를 지울 수 있다"))
    #expect(sql.contains("a.grantee = 0"), "PUBLIC 앞으로 난 grant 를 보는 단언이 없다")
    #expect(sql.contains("raise exception '§5④ ai_limits 의 RLS 가 꺼져 있다"))
    #expect(sql.contains("raise exception '§5⑧ ai_limits 의 기본키가 (%) 다"))
    #expect(sql.contains("raise exception '§5⑩ 리밋 칸이 다른 표(%건)에도 있다"),
            "리밋 칸이 기존 토큰 표로 새는 것을 보는 단언이 없다")

    // §6 행동 프로브: 역할을 실제로 바꿔 잰다. 복귀는 reset role 이 아니라 **캡처한 실행 역할**이다
    //   (reset role 은 CLI 링크드 연결에서 세션 사용자로 떨어져 다음 SELECT 를 42501 로 죽인다 — 2026-08-31 전례).
    #expect(sql.contains("v_exec_role text := current_user;"), "실행 역할을 캡처하지 않는다")
    #expect(sql.contains("execute format('set local role %I', v_exec_role);"), "캡처한 역할로 복귀하지 않는다")
    #expect(!sql.contains("reset role"), "reset role 로 복귀한다 — 운영 연결에서 42501 이 난다")
    #expect(sql.contains("set local role %I', p_role"), "역할 전환 헬퍼가 없다")
    #expect(sql.contains("raise exception 'AI_LIMITS_PROBE_ROLLBACK_SENTINEL';"),
            "센티널 롤백이 없다 — 프로브 행이 운영 표에 남는다")
    #expect(sql.contains("if probes <> v_expected then"), "프로브 수를 되묻지 않는다 — 검사가 조용히 빠진다")
    #expect(sql.contains("raise exception '① 남의 행이 %건 보인다(기대 0)"), "남의 행 격리 프로브가 없다")
    #expect(sql.contains("raise exception '② 남의 user_id 로 행을 넣는 데 성공했다"))
    #expect(sql.contains("on conflict (user_id, device_id, provider) do update"),
            "merge-duplicates upsert 를 실제로 돌리지 않는다 — select 정책 누락이 안 잡힌다")
    #expect(sql.contains("raise exception '⑤ authenticated 가 본인 행을 지웠다"))
    #expect(sql.contains("raise exception '⑥ anon 이 ai_limits 를 %행 읽었다"))

    // 프로브가 손대는 표는 ai_limits 와 auth.users 뿐이다(운영 표를 더럽히는 프로브는 두지 않는다).
    var cursor = sql.startIndex
    var targets: Set<String> = []
    for verb in ["insert into ", "delete from ", "update public."] {
        cursor = sql.startIndex
        while let range = sql.range(of: verb, range: cursor..<sql.endIndex) {
            let rest = sql[range.upperBound...]
            let token = rest.prefix { !" \n(".contains($0) }
            targets.insert(verb == "update public." ? "public." + token : String(token))
            cursor = range.upperBound
        }
    }
    #expect(targets.isSubset(of: ["public.ai_limits", "auth.users"]),
            "프로브가 다른 표를 쓴다: \(targets.sorted().joined(separator: ", "))")
}

// MARK: - ⑩ 달러 인용 함정

@Test
func 달러_인용_태그가_본문_주석에_글자로_적혀_있지_않다() throws {
    let raw = try t45Raw()
    // 2026-09-14 app_release 사고: 달러 인용 본문 안의 `--` 는 주석이 아니라 글자라, 설명에 태그 이름을 적으면
    // 그 자리에서 본문이 끝나 나머지가 SQL 로 해석된다. 태그가 **짝수 번**(열고 닫기)만 나오는지 센다.
    for tag in ["$assert$", "$probe$", "$tmp$", "$tail$", "$$"] {
        let count = t45Occurrences(raw, tag)
        #expect(count % 2 == 0,
                Comment(rawValue: "달러 태그 \(tag) 가 \(count)번 나온다(홀수) — 주석에 태그 글자를 적으면 본문이 거기서 끝난다"))
    }
}
