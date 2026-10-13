import Foundation
import Testing
@testable import check
@testable import CheckCore

// 0.3.51 — 폰 근무 마이그레이션(`20261014130000_phone_work.sql`)의 **소스 계약**.
//
// 행동(시작 · 중복 시작 · touch · mismatch · 종료 · 매분 처리 · 1회 알림 · 유예 · 맥 입력 생존 · 소급 마감 · 토큰 없는 마감 ·
// 맥 종료 뒤 장부 정리 · 0행 꼬리 치유 · 랩 지급 · anon/무소속 거절)은 로컬 Postgres 하네스(replay-harness-v2 — 체인 재생 뒤
// 파일 3회 + 사용자 흉내 테스트)와 파일 안 §9 프로브가 증명한다. 여기서는 그 행동을 만드는 **문장**이 사라지거나 넓어지는 것을 잡는다.
// 하우스 규칙: `--` 줄 주석을 걷어내고 본다(안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).

private struct PhoneWorkMigrationError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private let phoneWorkMigrationName = "20261014130000_phone_work.sql"

/// `supabase/` 는 .gitignore 라 워크트리에 없을 수 있다 — 조상을 훑어 `supabase/migrations` 를 찾는다(`CHECK_MIGRATIONS_DIR` 로 덮어쓴다).
private func phoneWorkMigrationsDirectory() throws -> URL {
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
    throw PhoneWorkMigrationError(message: "supabase/migrations 를 못 찾았다(워크트리라면 CHECK_MIGRATIONS_DIR 로 알려 줘라)")
}

private func phoneWorkSQL() throws -> String {
    let url = try phoneWorkMigrationsDirectory().appendingPathComponent(phoneWorkMigrationName)
    let raw = try String(contentsOf: url, encoding: .utf8)
    return raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func squash(_ sql: String) -> String {
    sql.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// `create or replace function public.<name>(` 부터 그 함수 본문의 닫는 `$fn$` 까지.
private func functionBody(_ sql: String, _ name: String) throws -> String {
    let lowered = sql.lowercased()
    guard let start = lowered.range(of: "create or replace function public.\(name)(") else {
        throw PhoneWorkMigrationError(message: "\(name) 의 정의가 없다")
    }
    let rest = lowered[start.upperBound...]
    guard let open = rest.range(of: "$fn$"), let close = rest[open.upperBound...].range(of: "$fn$") else {
        throw PhoneWorkMigrationError(message: "\(name) 의 본문 경계를 못 찾았다")
    }
    return String(lowered[start.lowerBound..<close.upperBound])
}

@Suite struct V0351PhoneWorkMigrationTests {
    @Test func tableHasOnlyTheAuthUsersForeignKeyWithCascadeOnTheSameLineAndNoClientGrants() throws {
        let sql = try phoneWorkSQL()
        let flat = squash(sql)
        #expect(flat.contains("create table if not exists public.phone_work_sessions ("))
        // FK 는 auth.users 하나(public 표 사이 FK 는 PostgREST 임베드 모호성 — 20260802120000). 계정 삭제 계약 테스트가 줄 단위로 cascade 를 본다.
        let referenceLines = sql.split(separator: "\n").filter { $0.lowercased().contains("references ") }
        #expect(referenceLines.count == 1, "참조가 \(referenceLines.count)줄이다: \(referenceLines)")
        #expect(referenceLines.first.map { $0.lowercased().contains("references auth.users(id) on delete cascade") } == true)
        #expect(flat.contains("alter table public.phone_work_sessions enable row level security"))
        #expect(flat.contains("revoke all on table public.phone_work_sessions from public, anon, authenticated"))
        #expect(!flat.contains("create policy"), "생존 장부에 클라 정책이 생겼다 — 클라가 장부를 위조한다")
        #expect(!flat.contains("grant select on public.phone_work_sessions to authenticated"))
        #expect(flat.contains("create unique index if not exists phone_work_sessions_one_open_per_user"))
    }

    @Test func rpcsAreDefinerWithDefaultArgumentsAndAuthenticatedOnly() throws {
        let flat = squash(try phoneWorkSQL())
        for name in ["work_phone_start", "work_phone_stop", "work_phone_touch"] {
            let body = try functionBody(try phoneWorkSQL(), name)
            #expect(body.contains("security definer"), "\(name) 가 definer 가 아니다")
            #expect(body.contains("set search_path = public"))
            #expect(body.contains("auth.uid()"))
            #expect(body.contains("pg_advisory_xact_lock(hashtext('phone_work:' || v_uid::text))"), "\(name) 가 사람 단위로 직렬화되지 않는다")
            // 시각은 서버 now() 하나뿐 — 클라가 보낸 시각 인자가 없다.
            #expect(!body.contains("p_started_at") && !body.contains("p_ended_at") && !body.contains("p_seen_at"))
        }
        #expect(flat.contains("create or replace function public.work_phone_start() returns jsonb"))
        #expect(flat.contains("create or replace function public.work_phone_stop(p_session_id uuid default null) returns jsonb"))
        #expect(flat.contains("create or replace function public.work_phone_touch() returns jsonb"))
        for signature in ["work_phone_start()", "work_phone_stop(uuid)", "work_phone_touch()"] {
            #expect(flat.contains("revoke all on function public.\(signature) from public, anon;"))
            #expect(flat.contains("grant execute on function public.\(signature) to authenticated;"))
        }
    }

    @Test func startInsertsSessionBeforeStatusAndFoldsTheUniqueViolationIntoAlreadyWorking() throws {
        let body = try functionBody(try phoneWorkSQL(), "work_phone_start")
        let insert = try #require(body.range(of: "insert into public.work_sessions"))
        let status = try #require(body.range(of: "insert into public.work_statuses"))
        let ledger = try #require(body.range(of: "insert into public.phone_work_sessions"))
        #expect(insert.upperBound <= status.lowerBound, "상태 upsert 가 세션 INSERT 보다 앞이다 — 트리거가 off_work 로 강등한다")
        #expect(status.upperBound <= ledger.lowerBound)
        #expect(body.contains("exception when unique_violation"), "맥과 동시에 열 때의 23505 를 접지 않는다")
        #expect(body.contains("'already_working'") && body.contains("'no_team'"))
        #expect(body.contains("order by m.joined_at, m.team_id"), "주 팀 규칙이 클라(fetchOwnMembership)와 다르다")
        #expect(body.contains("public.phone_work__wallet()"), "시작이 지갑(3시간 랩)을 정산하지 않는다")
    }

    @Test func stopClosesMyOpenSessionWhoeverOpenedItAndStampsLastSeen() throws {
        let body = try functionBody(try phoneWorkSQL(), "work_phone_stop")
        #expect(body.contains("where s.user_id = v_uid and s.ended_at is null"), "종료가 '내 열린 세션' 을 고르지 않는다")
        #expect(body.contains("'mismatch'"))
        #expect(body.contains("last_seen_at = v_now"), "종료가 last_seen_at 을 안 찍는다 — 소유하던 맥이 끊긴 강하로 읽어 되살린다")
        #expect(body.contains("closed_reason = 'manual'"))
        #expect(!body.contains("auto_closed_reason"), "사용자 종료에 자동 마감 사유를 적었다")
        #expect(body.contains("public.phone_work__wallet()"))
    }

    @Test func touchOnlyWritesForPhoneSessionsAndClearsThePendingCheck() throws {
        let body = try functionBody(try phoneWorkSQL(), "work_phone_touch")
        #expect(body.contains("check_sent_at = null"), "touch 가 확인 대기를 풀지 않는다 — 유예 안에 열어도 마감된다")
        #expect(body.contains("last_touch_at = v_now"))
        // 맥이 연 세션이면 폰 장부 UPDATE 가 0행 → 쓰기 없이 반환(맥 하트비트가 그 세션의 생존이다).
        let ledgerUpdate = try #require(body.range(of: "update public.phone_work_sessions pw"))
        let notFound = try #require(body.range(of: "if not found then"))
        let statusUpdate = try #require(body.range(of: "update public.work_statuses st"))
        #expect(ledgerUpdate.upperBound <= notFound.lowerBound && notFound.upperBound <= statusUpdate.lowerBound,
                "맥 세션에서도 상태 행을 민다 — 맥이 죽어도 스캐빈저가 못 닫는다")
        #expect(body.contains("last_input_at = v_now"), "결정 ①(리그 라이브 상한)이 사라졌다")
        #expect(body.contains("'not_working'") && body.contains("closed_reason"))
    }

    @Test func processUsesServerConstantsMacInputAndRetroactiveAwayClose() throws {
        let body = try functionBody(try phoneWorkSQL(), "phone_work__process")
        #expect(body.contains("public.phone_work_check_seconds()") && body.contains("public.phone_work_grace_seconds()"))
        #expect(!body.contains("9000") && !body.contains("interval '2 hours"), "임계가 리터럴로 박혔다")
        #expect(body.contains("public.away_last_input_at(v_team, v_user)"), "맥 입력을 생존으로 안 본다")
        #expect(body.contains("v_end := greatest(v_start, least(v_alive, v_now))"), "마감이 마지막 신호 소급이 아니다")
        #expect(body.contains("auto_closed_reason = 'away'"))
        #expect(body.contains("and s.ended_at is null"), "다른 경로가 닫은 ended_at 을 덮어쓴다")
        // 정확히 1회: 조건부 UPDATE … RETURNING 이 확인 시각을 세운 쪽만 알림을 적재한다.
        let mark = try #require(body.range(of: "set check_sent_at = v_now"))
        let returning = try #require(body.range(of: "returning check_sent_at into v_sent"))
        let enqueue = try #require(body.range(of: "public.push__enqueue("))
        #expect(mark.upperBound <= returning.lowerBound && returning.upperBound <= enqueue.lowerBound)
        // 본문은 소문자로 접어 본다 — 'WORK_CHECK' 카테고리도 여기선 'work_check' 다.
        #expect(body.contains("'type', 'work_check'"), "페이로드 type 이 폰 PushKind(work_check)와 다르다")
        #expect(body.contains("'category', 'work_check'"), "aps.category 가 폰 카테고리(WORK_CHECK)와 다르다")
        #expect(body.contains("'collapse_id', 'work-check'"))
        // 대리 하트비트는 last_seen_at 을 민다(그래야 구버전 맥·폰과 스캐빈저가 폰 근무를 살아 있는 근무로 본다).
        #expect(body.contains("last_seen_at = v_now"))
        #expect(body.contains("p_dispatch"), "프로브용 발송 끄기 문이 사라졌다 — 롤백 안 되는 발송을 프로브가 부른다")
    }

    @Test func tickIsServiceRoleOnlyAndScheduledEveryMinute() throws {
        let flat = squash(try phoneWorkSQL())
        #expect(flat.contains("revoke all on function public.phone_work_tick() from public, anon, authenticated;"))
        #expect(flat.contains("grant execute on function public.phone_work_tick() to service_role;"))
        #expect(!flat.contains("grant execute on function public.phone_work_tick() to authenticated"))
        #expect(flat.contains("perform cron.schedule('phone-work', '* * * * *', 'select public.phone_work_tick();');"))
        #expect(flat.contains("perform cron.unschedule('phone-work');"))
        #expect(flat.contains("pg_try_advisory_xact_lock(hashtext('phone_work_tick'))"))
        #expect(flat.contains("pg_try_advisory_xact_lock(hashtext('phone_work:' || r.user_id::text))"))
        for helper in ["phone_work__process(uuid, boolean)", "phone_work__sweep(uuid)", "phone_work__wallet()", "phone_work__session_json(uuid)"] {
            #expect(flat.contains("revoke all on function public.\(helper) from public, anon, authenticated, service_role;"), "\(helper)")
        }
    }

    @Test func pushKindIsWidenedByReadingTheLiveConstraintAndPrefsAreNotWidened() throws {
        let sql = try phoneWorkSQL()
        let flat = squash(sql)
        #expect(flat.contains("regexp_matches(v_def,"), "kind 어휘를 손으로 다시 적었다 — 같은 릴리스의 다른 kind 를 지운다")
        #expect(flat.contains("v_values || array['work_check']"))
        #expect(!flat.contains("create or replace function public.set_push_prefs"), "work_check 를 끌 수 있게 됐다(조용한 마감)")
        #expect(!flat.contains("create or replace function public.push__enqueue"))
        #expect(!flat.contains("create or replace function public.push_outbox_claim"))
    }

    @Test func existingClosersAndLeaderboardAreNotRedefined() throws {
        let flat = squash(try phoneWorkSQL())
        for name in ["close_abandoned_work_sessions", "close_away_work_sessions", "team_weekly_leaderboard",
                     "ultra_wallet_sync", "enforce_open_session_for_working", "poke_user", "ultra_poke_user", "work_tick"] {
            #expect(!flat.contains("create or replace function public.\(name)("), "\(name) 를 재정의했다 — 이 파일의 범위가 아니다")
            #expect(!flat.contains("drop function if exists public.\(name)("))
        }
        #expect(flat.contains("least(greatest(public.away_close_threshold_seconds(), 1800), 43200)"),
                "확인 임계가 자리비움 임계를 [30분, 12시간] 으로 조여 쓰지 않는다")
    }

    @Test func notifyPgrstIsTheLastStatement() throws {
        let statements = try phoneWorkSQL().split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(statements.last == "notify pgrst, 'reload schema';")
    }
}
