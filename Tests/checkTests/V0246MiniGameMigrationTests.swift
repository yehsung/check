import Foundation
import Testing
@testable import check

// v0.2.46 — 서버 마이그레이션 계약(20260908090000_minigame_scores.sql): 미니게임 일별 최고기록 원장 · 오늘 순위 RPC ·
// 순위 공개 토글 · 자정 상품(전날 게임별 1등에게 울트라 찌르기 +10, pg_cron 매시 멱등).
//
// 클라(hub 포크)가 이 이름들을 그대로 쓴다: 표 `minigame_daily_scores`(본문 user_id·game·best_score, on_conflict=user_id,game,day),
// RPC `minigame_board(p_game, p_day)` 6컬럼, `minigame_yesterday_winner(p_game)` 6컬럼, `profiles.minigame_public`.
// 행 디코드(JSON → convertFromSnakeCase)는 hub 의 V0246MiniGameHubTests 몫 — 여기선 SQL 만 고정한다.

private func mgRepoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(relative)
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다). 문자열 리터럴 안의 `--` 는
/// 이 파일에 없다(있으면 아래 검색이 헛돈다 — 그때 이 헬퍼를 고쳐라).
private func mgStrippingSQLComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func mgMigrationSQL() throws -> String {
    let raw = try String(contentsOf: mgRepoURL("supabase/migrations/20260908090000_minigame_scores.sql"), encoding: .utf8)
    return mgStrippingSQLComments(raw)
}

/// `create function public.<name>(…)` 부터 그 함수 본문의 `$$;` 까지.
private func mgFunctionBody(_ sql: String, header: String) throws -> String {
    let start = try #require(sql.range(of: header)?.lowerBound, "함수 헤더가 없다: \(header)")
    let end = try #require(sql.range(of: "\n$$;", range: start..<sql.endIndex)?.upperBound)
    return String(sql[start..<end])
}

@Test
func migrationContractMiniGameDailyScoresTable() throws {
    let sql = try mgMigrationSQL()

    // (i) 일별 원장 표: PK 3컬럼(user_id, game, day) · game/best_score check · day 는 서버 기본값(KST) · FK 는 auth.users 만.
    #expect(sql.contains("create table if not exists public.minigame_daily_scores ("))
    #expect(sql.contains("user_id uuid not null references auth.users(id) on delete cascade"))
    #expect(sql.contains("game text not null check (game in ('timing_bar','flappy'))"))
    #expect(sql.contains("day date not null default ((now() at time zone 'Asia/Seoul')::date)"))
    #expect(sql.contains("best_score integer not null default 0 check (best_score >= 0 and best_score <= 1000)"))
    #expect(sql.contains("primary key (user_id, game, day)"))
    #expect(!sql.contains("references public.profiles"), "새 표가 profiles 를 FK 로 가리키면 PostgREST 임베드가 모호해진다(docs/release.md)")
    #expect(sql.contains("on public.minigame_daily_scores (game, day, best_score desc, best_at)"), "순위 인덱스")

    // (ii) 권한 순서: RLS → 기본 특권 회수 → authenticated S/I/U(D 없음) → service_role 전부.
    let enableRLS = try #require(sql.range(of: "alter table public.minigame_daily_scores enable row level security;"))
    let revokeAll = try #require(sql.range(of: "revoke all on table public.minigame_daily_scores from public, anon, authenticated;"))
    let grantAuth = try #require(sql.range(of: "grant select, insert, update on public.minigame_daily_scores to authenticated;"))
    let grantSvc = try #require(sql.range(of: "grant select, insert, update, delete on public.minigame_daily_scores to service_role;"))
    #expect(enableRLS.lowerBound < revokeAll.lowerBound && revokeAll.lowerBound < grantAuth.lowerBound && grantAuth.lowerBound < grantSvc.lowerBound)
    #expect(!sql.contains("grant select, insert, update, delete on public.minigame_daily_scores to authenticated"))

    // (iii) 정책 3종(자기 행) — select 정책은 merge-duplicates 충돌 읽기에 필수.
    #expect(sql.contains("create policy \"users insert own minigame scores\"\n  on public.minigame_daily_scores for insert\n  with check (user_id = auth.uid());"))
    #expect(sql.contains("create policy \"users update own minigame scores\"\n  on public.minigame_daily_scores for update\n  using (user_id = auth.uid())\n  with check (user_id = auth.uid());"))
    #expect(sql.contains("create policy \"users read own minigame scores\"\n  on public.minigame_daily_scores for select\n  using (user_id = auth.uid());"))
}

@Test
func migrationContractMiniGameGuardTrigger() throws {
    let sql = try mgMigrationSQL()
    let body = try mgFunctionBody(sql, header: "create or replace function public.guard_minigame_score()")

    // invoker(자기 행만 본다 — security definer 아님) · 게임별 상한 예외 · INSERT 는 day 를 KST 오늘로 덮어쓰고 plays 1 ·
    // UPDATE 는 day 불변 · plays+1 · 하향 방지(greatest 규칙) · best_at 은 갱신됐을 때만.
    #expect(!body.contains("security definer"), "트리거는 다른 표를 읽지 않으므로 invoker 여야 한다(definer 는 우회 표면)")
    #expect(body.contains("case new.game when 'timing_bar' then 1000 when 'flappy' then 999 else 0 end"))
    #expect(body.contains("raise exception 'MINIGAME_SCORE_OUT_OF_RANGE'"))
    #expect(body.contains("new.day     := (now() at time zone 'Asia/Seoul')::date;"))
    #expect(body.contains("new.plays   := 1;"))
    #expect(body.contains("new.day     := old.day;"))
    #expect(body.contains("new.plays   := old.plays + 1;"))
    #expect(body.contains("if new.best_score <= old.best_score then\n      new.best_score := old.best_score;\n      new.best_at    := old.best_at;"))
    #expect(sql.contains("create trigger guard_minigame_score\n  before insert or update on public.minigame_daily_scores\n  for each row execute function public.guard_minigame_score();"))
}

@Test
func migrationContractMiniGameBoardRPC() throws {
    let sql = try mgMigrationSQL()

    // 시그니처: (p_game text, p_day date default null) → 6컬럼 고정 순서(클라 MiniGameBoardRow 가 디코드).
    #expect(sql.contains("drop function if exists public.minigame_board(text);"))
    #expect(sql.contains("drop function if exists public.minigame_board(text, date);"))
    #expect(sql.contains("create function public.minigame_board(p_game text, p_day date default null)\nreturns table(\n  user_id uuid,\n  display_name text,\n  avatar_url text,\n  best_score integer,\n  best_at timestamptz,\n  plays integer\n)"))
    let body = try mgFunctionBody(sql, header: "create function public.minigame_board(p_game text, p_day date default null)")
    #expect(body.contains("security definer"))
    #expect(body.contains("set search_path = public"))
    #expect(body.contains("s.day = coalesce(p_day, (now() at time zone 'Asia/Seoul')::date)"), "기본은 KST 오늘")
    #expect(body.contains("(coalesce(p.minigame_public, true) or s.user_id = auth.uid())"), "비공개는 본인에게만")
    #expect(body.contains("order by s.best_score desc, s.best_at asc, s.user_id"))
    #expect(body.contains("limit 50"))
    // 권한 3줄 순서.
    #expect(sql.contains("revoke all     on function public.minigame_board(text, date) from public;\nrevoke execute on function public.minigame_board(text, date) from public, anon;\ngrant  execute on function public.minigame_board(text, date) to authenticated, service_role;"))

    // 어제 1등 RPC: 6컬럼 · 지급 행 우선 · 없으면 공개 1위(awarded false).
    #expect(sql.contains("create function public.minigame_yesterday_winner(p_game text)\nreturns table(\n  day date,\n  user_id uuid,\n  display_name text,\n  avatar_url text,\n  score integer,\n  awarded boolean\n)"))
    let winner = try mgFunctionBody(sql, header: "create function public.minigame_yesterday_winner(p_game text)")
    #expect(winner.contains("true as awarded"))
    #expect(winner.contains("false as awarded"))
    #expect(winner.contains("where not exists (select 1 from prized)"))
    #expect(winner.contains("coalesce(p.minigame_public, true)"))
    #expect(sql.contains("revoke execute on function public.minigame_yesterday_winner(text) from public, anon;"))
    #expect(sql.contains("grant  execute on function public.minigame_yesterday_winner(text) to authenticated, service_role;"))
}

@Test
func migrationContractMiniGamePublicToggle() throws {
    let sql = try mgMigrationSQL()
    // 컬럼 + 컬럼 단위 grant(누적 — 기존 목록 회수 없음).
    #expect(sql.contains("alter table public.profiles add column if not exists minigame_public boolean not null default true;"))
    #expect(sql.contains("grant update (minigame_public) on public.profiles to authenticated;"))
    #expect(sql.contains("grant select (minigame_public) on public.profiles to anon, authenticated;"))
    #expect(!sql.contains("revoke select on public.profiles"), "기존 select 목록을 회수하면 앱의 프로필 GET 이 통째로 403")
    #expect(!sql.contains("revoke update on public.profiles"))
}

@Test
func migrationContractMiniGamePrize() throws {
    let sql = try mgMigrationSQL()

    // 장부 표: (day, game) PK = 멱등 키. authenticated 는 select 만.
    #expect(sql.contains("create table if not exists public.minigame_prizes ("))
    #expect(sql.contains("primary key (day, game)"))
    #expect(sql.contains("revoke all on table public.minigame_prizes from public, anon, authenticated;\ngrant select on public.minigame_prizes to authenticated;"))
    #expect(sql.contains("on public.minigame_prizes for select\n  using (true);"))

    // 울트라 장부 어휘: 옛 세 항 + prize:%.
    #expect(sql.contains("alter table public.ultra_ledger drop constraint if exists ultra_ledger_reason_check;"))
    #expect(sql.contains("check (reason = 'floor' or reason = 'spend:ultra' or reason like 'mission:%' or reason like 'prize:%');"))

    // 지급 함수: service_role 전용 · 전날 기본 · 공개 사용자만 · 지갑 잠금 · on conflict do nothing 이 실제 삽입일 때만 +10 · 장부 +10 · least 금지.
    let body = try mgFunctionBody(sql, header: "create or replace function public.minigame_award_daily_prizes(p_day date default null)")
    #expect(body.contains("security definer"))
    #expect(body.contains("if p_day is null then"), "p_day 없이 부르면 [오늘−3, 오늘−1] 따라잡기")
    #expect(body.contains("v_days := array[p_day];"))
    #expect(body.contains("foreach v_game in array array['timing_bar', 'flappy'] loop"))
    #expect(body.contains("and coalesce(p.minigame_public, true)"), "숨긴 사람은 순위표에 없으니 상품 대상도 아니다")
    #expect(body.contains("order by s.best_score desc, s.best_at asc, s.user_id"))
    #expect(body.contains("pg_advisory_xact_lock(hashtext('ultra_wallet:' || v_uid::text))"))
    #expect(body.contains("on conflict (day, game) do nothing;"))
    #expect(body.contains("get diagnostics v_rows = row_count;\n      if v_rows = 0 then"), "실제로 삽입됐을 때만 +10")
    #expect(body.contains("update public.profiles set ultra_balance = ultra_balance + 10"))
    #expect(body.contains("'prize:minigame:' || v_game, 10, v_after,"))
    #expect(!body.contains("least("), "least(cap, …) 는 장부와 잔량을 어긋나게 한다(20260903190000:297-299)")
    #expect(sql.contains("revoke execute on function public.minigame_award_daily_prizes(date) from public, anon, authenticated;\ngrant  execute on function public.minigame_award_daily_prizes(date) to service_role;"))

    // 자정 초기화(사용자 결정 2026-09-08: 상품으로 3 을 넘긴 잔량은 매일 KST 자정에 3 으로 — 매일 1등이어도 13 → 13):
    // 오늘 키 표 minigame_prize_days(service_role 만) · 지급보다 먼저 · 상한 초과 전원 → cap, 장부 'prize:expire'(음수) · p_day null 이면 [오늘−3, 오늘−1].
    #expect(sql.contains("create table if not exists public.minigame_prize_days (\n  day date primary key,"))
    #expect(sql.contains("revoke all on table public.minigame_prize_days from public, anon, authenticated;\ngrant select, insert, update, delete on public.minigame_prize_days to service_role;"))
    #expect(!sql.contains("on public.minigame_prize_days to authenticated"))
    let resetRange = try #require(body.range(of: "on conflict (day) do nothing;"))
    let awardRange = try #require(body.range(of: "on conflict (day, game) do nothing;"))
    #expect(resetRange.lowerBound < awardRange.lowerBound, "초기화가 지급보다 먼저여야 우승자가 정확히 3 + 10 이 된다")
    #expect(body.contains("v_cap     int  := public.ultra_balance_cap();"))
    #expect(body.contains("where p.ultra_balance > v_cap order by p.id loop"))
    #expect(body.contains("update public.profiles set ultra_balance = v_cap where id = r.id;"))
    #expect(body.contains("'prize:expire', v_cap - v_before, v_cap,"))
    #expect(body.contains("v_days := array[v_today - 3, v_today - 2, v_today - 1];"))
    #expect(body.contains("'reset', jsonb_build_object('day', to_char(v_today, 'YYYY-MM-DD'), 'performed', v_reset_performed, 'users', v_reset_users),"))

    // 스케줄: 매시 5분(멱등이라 자정 실행이 빠져도 다음 시간에 준다) · 실패는 notice.
    #expect(sql.contains("create extension if not exists pg_cron;"))
    #expect(sql.contains("cron.schedule(\n    'minigame-daily-prize',\n    '5 * * * *',\n    $cron$select public.minigame_award_daily_prizes();$cron$\n  );"))
    #expect(sql.contains("raise notice 'pg_cron 스케줄 등록 건너뜀(환경 미지원 가능): %', sqlerrm;"))
}

@Test
func migrationContractMiniGameProbes() throws {
    let sql = try mgMigrationSQL()
    // 프로브가 앱과 같은 역할로 돌고(authenticated + JWT 클레임), 센티널로 통째 롤백하며, RESET ROLE 을 쓰지 않는다.
    #expect(sql.contains("v_exec_role text := current_user;"))
    #expect(sql.contains("execute 'set local role authenticated';"))
    #expect(sql.contains("perform set_config('request.jwt.claims', v_claims, true);"))
    #expect(sql.contains("perform set_config('request.jwt.claim.sub', v_uid::text, true);"))
    #expect(sql.contains("execute format('set local role %I', v_exec_role);"))
    #expect(!sql.lowercased().contains("reset role"), "RESET ROLE 은 CLI 링크드 연결에서 세션 사용자로 떨어져 42501")
    #expect(sql.contains("raise exception 'MINIGAME_PROBE_ROLLBACK';"))
    #expect(sql.contains("if sqlerrm <> 'MINIGAME_PROBE_ROLLBACK' then raise; end if;"))
    // 핵심 프로브 기대값: 하향 방지(120 유지) · 상한 예외 · 타인 RLS · 비공개 필터 · 상품 +10 멱등 · 잔량 13 보존 · 2→≤3.
    #expect(sql.contains("if v_score <> 120 or v_plays <> 2 or v_at3 <> v_at1 then"))
    #expect(sql.contains("if sqlerrm <> 'MINIGAME_SCORE_OUT_OF_RANGE' then raise; end if;"))
    #expect(sql.contains("if sqlstate <> '42501' then raise; end if;"))
    #expect(sql.contains("if v_bal <> 13 then\n      raise exception '⑩ 1등 A 의 잔량이 초기화(3) + 상품(10) = 13 이 아니다"), "자정 초기화 뒤 +10 = 13")
    #expect(sql.contains("where user_id = v_uid and kst_day = v_today and reason = 'prize:expire' and delta = -10 and balance_after = 3;"))
    #expect(sql.contains("if v_bal <> 13 or jsonb_array_length(v_res->'awarded') <> 0 or (v_res->'reset'->>'performed') is distinct from 'false' then"), "두 번째 호출은 초기화·지급 모두 건너뛴다")
    #expect(sql.contains("raise exception '⑰ A 의 잔량·장부 드리프트가 변했다"), "장부 없이 잔량만 바꾸면 ultra_wallet_audit 드리프트")
    #expect(sql.contains("if jsonb_array_length(v_res->'days') <> 3 or (v_res->'reset'->>'performed') is distinct from 'false' then"), "p_day null → 3일 따라잡기")
    #expect(sql.contains("if v_n <> v_pd0 then"), "초기화 키 롤백 확인")
    // 적용 당일의 초기화 키를 프로브 블록 **뒤**(센티널 롤백 밖)에서 미리 채운다 — 첫 cron 이 한낮에 옛 경제 잔량(5·4)을 깎지 않게.
    // 프로브는 시작에서 그 키를 지우고(롤백으로 원복) ⑯ 을 돌리므로 재적용에도 통과한다.
    let seed = try #require(sql.range(of: "insert into public.minigame_prize_days(day, reset_users)\nvalues ((now() at time zone 'Asia/Seoul')::date, 0)\non conflict (day) do nothing;"))
    let sentinel = try #require(sql.range(of: "raise exception 'MINIGAME_PROBE_ROLLBACK';"))
    let probeDelete = try #require(sql.range(of: "delete from public.minigame_prize_days where day = v_today;"))
    #expect(sentinel.upperBound < seed.lowerBound, "오늘 키 insert 는 프로브 블록 뒤여야 실제로 남는다")
    #expect(probeDelete.lowerBound < sentinel.lowerBound, "프로브가 오늘 키를 먼저 지워야 재적용에서도 ⑯ 이 초기화를 관측한다")
    #expect(sql.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("on conflict (day) do nothing;"), "파일 맨 끝")
    #expect(sql.contains("if v_bal <> 13 then"))
    #expect(sql.contains("if v_bal > 3 or v_bal < 2 then"))
    #expect(sql.contains("perform public.minigame_award_daily_prizes(v_yday);"), "authenticated 가 상품 함수를 부르면 42501 이어야 한다")
}
