import Foundation
import Testing

// 서버 안정화(2026-10-30 · l4-cron) — 매분 cron 7개를 job 하나(minutely)로 묶는 마이그레이션
// (`20261102210000_cron_minutely.sql`)의 **소스 계약**.
//
// 행동(단계 7개가 다 돈다 · 한 단계 실패는 그 단계만 · 앞 단계는 커밋돼 남는다 · 예산 초과면 뒤 단계 SKIP · lock_timeout 단계별 실효 ·
// 클라 역할 call/select 거절 · rummy-settle 이전 · 운영 job 이 바뀌었으면 배포 중단)은 로컬 하네스(replay-harness-v2, CRON_SHIM 1·0)의
// `call public.cron_minutely()` 와 파일 안 §6 사후 단언이 증명한다. 여기서는 그 행동을 만드는 **문장**이 사라지는 것을 잡는다.
// V0351PhoneWork 등 옛 파일의 `cron.schedule('phone-work', …)` 계약은 그 파일의 글자로 남는다 — "정산·틱이 매분 돈다"는 뜻은
// 이제 이 파일이 잇는다(아래 첫 시험: 체인 끝에서 일곱 다 minutely 의 단계이고, 뒤 파일이 단독 job 으로 되살리지 않는다).
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).

private struct CronMinutelyError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private let cmMigrationName = "20261102210000_cron_minutely.sql"

/// 묶인 매분 job 이름 → 운영 command(2026-10-30 운영 cron.job 읽기와 글자까지 같다).
private let cmMovedJobs: [(name: String, command: String, position: Int)] = [
    ("gomoku-settle", "select public.gomoku_settle_expired();", 10),
    ("chess-settle", "select public.chess_settle_expired();", 20),
    ("tetris-settle", "select public.tetris_settle_expired();", 30),
    ("push-retry", "select public.push_outbox_retry();", 40),
    ("phone-work", "select public.phone_work_tick();", 50),
    ("weekly-work-reward", "select public.weekly_work_settle_all();", 80),
    ("achievements", "select public.achievements_settle_all();", 90),
]

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 `supabase/migrations` 를 찾는다(`CHECK_MIGRATIONS_DIR` 로 덮어쓴다).
private func cmMigrationsDirectory() throws -> URL {
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
    throw CronMinutelyError(message: "supabase/migrations 를 못 찾았다(워크트리라면 CHECK_MIGRATIONS_DIR 로 알려 줘라)")
}

private func cmStrip(_ raw: String) -> String {
    raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 소문자 · 공백 한 칸 · 여는 괄호 뒤 공백 제거(`cron.schedule(\n 'x'` 와 `cron.schedule('x'` 를 같게 본다).
private func cmSquash(_ sql: String) -> String {
    sql.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        .replacingOccurrences(of: "( ", with: "(")
}

private func cmFiles() throws -> [String] {
    try FileManager.default.contentsOfDirectory(at: try cmMigrationsDirectory(), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }
        .map(\.lastPathComponent)
        .sorted()
}

private func cmSQL(_ name: String = cmMigrationName) throws -> String {
    let url = try cmMigrationsDirectory().appendingPathComponent(name)
    return cmStrip(try String(contentsOf: url, encoding: .utf8))
}

/// `create or replace procedure public.cron_minutely()` 부터 닫는 `$proc$` 까지(소문자).
private func cmProcedure() throws -> String {
    let lowered = try cmSQL().lowercased()
    guard let start = lowered.range(of: "create or replace procedure public.cron_minutely()") else {
        throw CronMinutelyError(message: "cron_minutely 프로시저 정의가 없다")
    }
    let rest = lowered[start.upperBound...]
    guard let open = rest.range(of: "$proc$"), let close = rest[open.upperBound...].range(of: "$proc$") else {
        throw CronMinutelyError(message: "cron_minutely 본문 경계($proc$)를 못 찾았다")
    }
    return String(lowered[start.lowerBound..<close.upperBound])
}

@Suite("서버 안정화 l4-cron — 매분 cron 7개 → minutely 한 job(cron_minutely 프로시저)")
struct CronMinutelyMigrationTests {
    @Test("체인 끝에서 일곱이 다 minutely 의 단계다 — 단독 job 을 만든 파일은 전부 앞에 있고, 뒤 파일은 단독 매분 job 으로 되살리지 않는다")
    func 일곱이_매분_한_갈래로_돈다() throws {
        // 없으면: 7개를 지우기만 하고 단계 행 하나를 빠뜨려(예: phone-work) 그 일이 영영 멈추거나, 뒤 파일이 옛 단독 job 을 다시
        //         등록해 같은 정산이 매분 두 번(백엔드도 둘) 도는 것이 초록이다.
        let names = try cmFiles()
        #expect(names.count > 100, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
        let mine = try #require(names.firstIndex(of: cmMigrationName), "\(cmMigrationName) 이 체인에 없다")
        let flat = cmSquash(try cmSQL())
        // cron.schedule 을 품은 파일만 한 번씩 접는다(140여 개를 일곱 번 접으면 수십 초 — 빠른 게이트에서 빠진다).
        var scheduling: [(index: Int, flat: String)] = []
        let directory = try cmMigrationsDirectory()
        for (i, file) in names.enumerated() where i != mine {
            let raw = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            guard raw.contains("cron.schedule") else { continue }
            let sql = cmStrip(raw)
            if sql.contains("cron.schedule") { scheduling.append((i, cmSquash(sql))) }
        }
        for job in cmMovedJobs {
            #expect(flat.contains("('\(job.name)', '\(job.command)', \(job.position))"),
                    "\(job.name) 단계 씨앗이 운영 command 그대로가 아니다(또는 빠졌다)")
            let scheduledAt = scheduling.filter { $0.flat.contains("cron.schedule('\(job.name)', '* * * * *'") }.map(\.index)
            #expect(!scheduledAt.isEmpty, "\(job.name) 을 처음 등록한 파일을 못 찾았다 — 이름이 틀렸거나 검사가 헛돈다")
            for i in scheduledAt {
                #expect(i < mine, "\(names[i]) 가 \(job.name) 을 단독 매분 job 으로 다시 등록한다 — minutely 와 같이 두 번 돈다")
            }
        }
        #expect(flat.contains("v_names text[] := array['gomoku-settle', 'push-retry', 'chess-settle', 'phone-work', 'weekly-work-reward', 'achievements', 'tetris-settle', 'rummy-settle'];"),
                "지울 job 이름 목록이 일곱 + rummy-settle 이 아니다")
        #expect(flat.contains("perform cron.unschedule(r.jobid);"))
        #expect(flat.contains("perform cron.schedule('minutely', '* * * * *', 'call public.cron_minutely()');"),
                "minutely 는 매분 · 한 문장 call 이어야 한다(여러 문장이면 암묵 트랜잭션 블록이라 COMMIT 이 죽는다)")
        // rummy-settle 단독 job 이 있으면 그 command 그대로 position 35 행으로 옮긴다(게임 추가 세션과의 합의).
        #expect(flat.contains("values ('rummy-settle', r.command, 35)"))
        // 지우기 전 대조(운영 job 이 바뀌었으면 조용히 옛 command 로 되돌리지 않고 멈춘다) · 사후 단언(옛 이름 0 · minutely 1).
        #expect(flat.contains("가 단계 command(%)와 다르다"))
        #expect(flat.contains("의 주기가 매분이 아니다(%)"))
        #expect(flat.contains("단독 매분 job 이 남았다(%)"))
        #expect(flat.contains("minutely job 이 %개다(기대 1)"))
    }

    @Test("프로시저 모양 — PROCEDURE · invoker · SET 절 없음 · COMMIT 은 예외 블록 밖 · 57014 따로 잡기 · lock_timeout 단계별")
    func 프로시저가_단계마다_커밋한다() throws {
        // 없으면: security definer 나 `set search_path` 를 붙여 COMMIT 이 invalid transaction termination 으로 매분 죽거나,
        //         when others 만 두어 시간 초과(57014) 한 번에 job 전체가 죽고 뒤 단계가 그 분에 안 도는 것이 초록이다.
        let body = try cmProcedure()
        let head = String(body[..<(try #require(body.range(of: "as $proc$"))).lowerBound])
        #expect(cmSquash(head) == "create or replace procedure public.cron_minutely() language plpgsql",
                "머리에 language plpgsql 말고 다른 절이 있다(security definer · set … 이면 COMMIT 을 못 한다): \(head)")
        let flat = cmSquash(body)
        #expect(!flat.contains("security definer"))
        // 등록표를 먼저 배열로 읽는다(루프 중 COMMIT 과 커서가 엉키지 않게).
        #expect(flat.contains("array_agg(s.command order by s.position, s.step)"))
        #expect(flat.contains("from public.cron_minutely_steps s where s.enabled;"))
        // 단계: 시간 제한 → 실행(예외 블록) → 기록 → COMMIT(블록 밖).
        let exec = try #require(flat.range(of: "begin execute v_cmds[v_i]; exception when query_canceled then"),
                                "단계 실행이 query_canceled 를 따로 잡는 예외 블록이 아니다(when others 는 57014 를 안 잡는다)")
        let blockEnd = try #require(flat[exec.upperBound...].range(of: " end; "))
        #expect(!flat[exec.lowerBound..<blockEnd.lowerBound].contains("commit"), "예외 블록 안에 COMMIT 이 있다 — 서브트랜잭션 안이라 죽는다")
        let loopEnd = try #require(flat[blockEnd.upperBound...].range(of: "end loop;"))
        #expect(flat[blockEnd.upperBound..<loopEnd.lowerBound].contains("commit;"), "단계 기록 뒤 COMMIT 이 없다 — 뒤 단계가 터지면 앞 정산도 되돌아간다")
        #expect(flat.contains("perform set_config('statement_timeout', v_timeout::text, true);"))
        #expect(flat.contains("perform set_config('lock_timeout', v_timeout::text, true);"),
                "단계별 lock_timeout 이 없다 — CALL 안에서 실효가 있는 시간 제한은 이것뿐이다(하네스 ④-a/b)")
        // 예산 40초 · 시작 전 확인 · SKIP 기록 · 끝에서 예외(앞 단계는 커밋됨) · 7일 청소.
        #expect(flat.contains("v_budget_ms int := 40000;"))
        #expect(flat.contains("if extract(epoch from clock_timestamp() - v_job_t0) * 1000 >= v_budget_ms then"))
        #expect(flat.contains("'skip'"), "예산 초과 건너뜀을 sqlstate 'SKIP' 으로 남기지 않는다")
        #expect(flat.contains("delete from public.cron_step_failures f where f.failed_at < now() - interval '7 days';"))
        let raise = try #require(flat.range(of: "if v_failed > 0 or v_skipped > 0 then raise exception"))
        #expect(raise.lowerBound > loopEnd.upperBound, "실패 예외가 루프 안에 있다 — 뒤 단계가 안 돈다")
        // 본문의 표 이름은 전부 public. 으로 한정(SET search_path 를 못 붙이는 대신).
        for table in ["cron_minutely_steps", "cron_minutely_runs", "cron_step_failures"] {
            let total = flat.components(separatedBy: table).count - 1
            let qualified = flat.components(separatedBy: "public.\(table)").count - 1
            #expect(total > 0 && total == qualified, "\(table) 이 public. 없이 \(total - qualified)번 나온다")
        }
    }

    @Test("권한 — 세 표 RLS · 프로시저/표/시퀀스 권한을 public·anon·authenticated·service_role 에서 회수 · grant 0 · 함수 재정의 0")
    func 클라와_service_role_은_못_건드린다() throws {
        // 없으면: Supabase 기본 권한으로 authenticated 가 매분 job 을 부르거나, service_role 이 cron_minutely_steps.command 를 써서
        //         postgres 로 임의 SQL 을 돌리는 통로가 생기거나, 이 파일이 정산·푸시 함수 본문을 재정의해 체인 계약을 깨도 초록이다.
        let flat = cmSquash(try cmSQL())
        for table in ["cron_minutely_steps", "cron_minutely_runs", "cron_step_failures"] {
            #expect(flat.contains("alter table public.\(table) enable row level security;"), "\(table) RLS")
            #expect(flat.contains("revoke all on table public.\(table) from public, anon, authenticated, service_role;"), "\(table) 회수")
        }
        #expect(flat.contains("revoke all on sequence public.cron_step_failures_id_seq from public, anon, authenticated, service_role;"))
        #expect(flat.contains("revoke all on procedure public.cron_minutely() from public, anon, authenticated, service_role;"))
        #expect(!flat.contains("grant "), "이 파일에 grant 가 있다 — 누구에게도 주지 않는다")
        #expect(!flat.contains("create policy"))
        #expect(!flat.contains("create or replace function") && !flat.contains("create function"),
                "이 파일이 함수를 정의한다 — 정산·푸시 본문 재정의 금지(XplatServerMigrationTests 마지막 정의 계약)")
        #expect(!flat.contains("security definer"))
        // 사후 단언이 실행권·표 권한·본문 무변경을 적용 순간에 되묻는다.
        #expect(flat.contains("has_function_privilege(v_role, 'public.cron_minutely()', 'execute')"))
        #expect(flat.contains("의 본문·속성이 이 파일에서 바뀌었다"))
        // 최상위 트랜잭션 제어 0(프로시저 본문의 commit 은 들여쓰기 안 — 줄 머리 commit 은 래퍼 트랜잭션을 깬다).
        for line in try cmSQL().split(separator: "\n") {
            #expect(!["begin;", "commit;", "rollback;", "start transaction;"].contains(String(line).lowercased()),
                    "최상위 트랜잭션 제어 '\(line)' — 운영 CLI 래퍼 트랜잭션을 깬다")
        }
    }
}
