import Foundation
import Testing
@testable import check

// v0.2.46 — 서버 마이그레이션 계약(20260908180000_minigame_prize_quorum.sql): 자정 상품에 최소 참가자 수(정족수 5) 조건.
//
// 사용자 결정(2026-09-08): "10개 보상은 해당 날에 참여자가 5명 이상일 때만 지급." 조건이 없으면 혼자 한 판만 해도
// 1등이라 매일 10 발이 나간다.
//
// 이 파일은 **새 파일만** 고정한다. 앞 파일(20260908090000)은 이미 프로덕션에 적용됐으므로 손대지 않으며,
// 그 계약은 V0246MiniGameMigrationTests 가 그대로 지킨다(두 파일이 서로를 덮지 않는지도 여기서 한 줄 확인한다).

private func qmRepoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(relative)
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
private func qmStrippingSQLComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

private func qmMigrationSQL() throws -> String {
    let raw = try String(contentsOf: qmRepoURL("supabase/migrations/20260908180000_minigame_prize_quorum.sql"), encoding: .utf8)
    return qmStrippingSQLComments(raw)
}

/// 함수 헤더부터 그 본문의 `$$;` 까지.
private func qmFunctionBody(_ sql: String, header: String) throws -> String {
    let start = try #require(sql.range(of: header)?.lowerBound, "함수 헤더가 없다: \(header)")
    let end = try #require(sql.range(of: "\n$$;", range: start..<sql.endIndex)?.upperBound)
    return String(sql[start..<end])
}

@Test
func migrationContractMiniGameQuorumConstant() throws {
    let sql = try qmMigrationSQL()

    // 정족수는 한 곳에서만 바꾼다(ultra_balance_cap() 관용구). immutable · anon 실행권 없음.
    #expect(sql.contains("create or replace function public.minigame_prize_quorum()\nreturns int language sql immutable as $$ select 5 $$;"))
    #expect(sql.contains("revoke execute on function public.minigame_prize_quorum() from public, anon;"))
    #expect(sql.contains("grant  execute on function public.minigame_prize_quorum() to authenticated, service_role;"))
}

@Test
func migrationContractMiniGameQuorumGate() throws {
    let sql = try qmMigrationSQL()
    let body = try qmFunctionBody(sql, header: "create or replace function public.minigame_award_daily_prizes(p_day date default null)")

    // (i) 참가자 = 그날 그 게임에 점수를 낸 **공개 사용자 수**. 모집단이 1등 선정 쿼리와 같아야 "N명 중 1등"이 말이 된다.
    #expect(body.contains("select count(distinct s.user_id) into v_players"))
    #expect(body.contains("where s.game = v_game and s.day = v_day and s.best_score > 0\n         and coalesce(p.minigame_public, true);"))
    #expect(body.contains("v_quorum  int  := public.minigame_prize_quorum();"))

    // (ii) 미달이면 건너뛴다 — 아무도 안 한 날('no_scores')과 어휘를 구별한다.
    #expect(body.contains("elsif v_players < v_quorum then"))
    #expect(body.contains("'reason', 'quorum', 'players', v_players, 'need', v_quorum"))
    #expect(body.contains("if v_players = 0 then"))
    #expect(body.contains("'reason', 'no_scores'"))

    // (iii) 검사는 상품 장부 insert **앞**이다. 뒤에 있으면 미달인데 (day, game) 행이 남아 나중에 5명이 돼도 지급이 막힌다.
    let gate = try #require(body.range(of: "elsif v_players < v_quorum then"))
    let insert = try #require(body.range(of: "on conflict (day, game) do nothing;"))
    #expect(gate.lowerBound < insert.lowerBound, "정족수 검사가 지급 장부 insert 뒤에 있으면 미달인 날이 영구히 잠긴다")
    #expect(!body.contains("insert into public.minigame_prizes(day, game, user_id, score)\n        select"),
            "미달일 때 상품 장부에 행을 남기면 '이미 줬다'와 구별되지 않는다")

    // (iv) 지급된 건에는 players 를 함께 싣는다(감사용).
    #expect(body.contains("'balance_after', v_after, 'players', v_players)"))

    // (v) 종전 계약은 한 글자도 바뀌지 않았다 — 함수를 통째로 다시 정의했으므로 여기서 되묻는다.
    #expect(body.contains("update public.profiles set ultra_balance = ultra_balance + 10"))
    #expect(body.contains("on conflict (day) do nothing;"), "자정 초기화 멱등 키")
    #expect(body.contains("set ultra_balance = v_cap"))
    #expect(body.contains("'prize:expire', v_cap - v_before, v_cap,"))
    #expect(body.contains("pg_advisory_xact_lock(hashtext('ultra_wallet:' || v_uid::text))"))
    #expect(body.contains("v_days := array[v_today - 3, v_today - 2, v_today - 1];"), "3일 따라잡기")
    #expect(!body.contains("least("), "least(cap, …) 는 장부와 잔량을 어긋나게 한다(20260903190000:297-299)")

    // (vi) 실행권은 여전히 service_role 만(create or replace 는 권한을 보존하지만 재부여로 못 박는다).
    #expect(sql.contains("revoke execute on function public.minigame_award_daily_prizes(date) from public, anon, authenticated;\ngrant  execute on function public.minigame_award_daily_prizes(date) to service_role;"))
}

@Test
func migrationContractMiniGameWinnerRPCGainsPlayersAndQuorum() throws {
    let sql = try qmMigrationSQL()

    // 반환 타입이 바뀌므로 drop 선행 — 그리고 drop 은 실행권을 버리므로 revoke/grant 3줄을 다시 부여해야 한다.
    #expect(sql.contains("drop function if exists public.minigame_yesterday_winner(text);"))
    #expect(sql.contains("create function public.minigame_yesterday_winner(p_game text)\nreturns table(\n  day date,\n  user_id uuid,\n  display_name text,\n  avatar_url text,\n  score integer,\n  awarded boolean,\n  players integer,\n  quorum integer\n)"))
    #expect(sql.contains("revoke execute on function public.minigame_yesterday_winner(text) from public, anon;"))
    #expect(sql.contains("grant  execute on function public.minigame_yesterday_winner(text) to authenticated, service_role;"))

    let body = try qmFunctionBody(sql, header: "create function public.minigame_yesterday_winner(p_game text)")
    // players 는 지급 함수의 정족수 산식과 같은 쿼리, quorum 은 같은 상수 — 화면이 "N명 참여 · 5명부터 상품"을 같은 출처에서 받는다.
    #expect(body.contains("select count(distinct s.user_id)::int"))
    #expect(body.contains("public.minigame_prize_quorum() as quorum"))
    #expect(body.contains("coalesce(p.minigame_public, true)"))
    #expect(body.contains("true as awarded"))
    #expect(body.contains("false as awarded"))
    #expect(body.contains("where not exists (select 1 from prized)"))
    #expect(body.contains("cross join counted c"))
}

@Test
func migrationContractMiniGameQuorumProbes() throws {
    let sql = try qmMigrationSQL()

    // 앱과 같은 역할(authenticated + JWT 클레임) · 센티널 롤백 · RESET ROLE 금지.
    #expect(sql.contains("v_exec_role text := current_user;"))
    #expect(sql.contains("execute 'set local role authenticated';"))
    #expect(sql.contains("perform set_config('request.jwt.claims', v_claims, true);"))
    #expect(sql.contains("execute format('set local role %I', v_exec_role);"))
    #expect(!sql.lowercased().contains("reset role"), "RESET ROLE 은 CLI 링크드 연결에서 세션 사용자로 떨어져 42501")
    #expect(sql.contains("raise exception 'MINIGAME_QUORUM_PROBE_ROLLBACK';"))
    #expect(sql.contains("if sqlerrm <> 'MINIGAME_QUORUM_PROBE_ROLLBACK' then raise; end if;"))

    // 프로브 날짜는 앱이 없던 과거 — 프로덕션의 진짜 기록이 분모에 섞이면 4명/5명 단언이 흔들린다.
    #expect(sql.contains("v_pd1       date := date '2025-01-06';"))
    #expect(sql.contains("v_pd2       date := date '2025-01-07';"))
    #expect(sql.contains("v_pd3       date := date '2025-01-08';"))

    // ⑲ 4명 → 두 게임 모두 건너뜀(상품 장부 0행 · 잔량 불변) · ⑳ 5명 → 같은 날 정상 지급(players 5)
    #expect(sql.contains("raise exception '⑲ 참가자 4명인데 상품이 나갔다: %', v_res;"))
    #expect(sql.contains("and (s->>'players')::int = 4 and (s->>'need')::int = 5) then"))
    #expect(sql.contains("raise exception '⑲ 정족수 미달인데 상품 장부에 %행이 남았다 — 나중에 5명이 돼도 지급이 막힌다', v_n;"))
    #expect(sql.contains("or (v_res->'awarded'->0->>'players')::int <> 5 then"))
    #expect(sql.contains("if v_bal <> v_bal0[1] + 10 then"))

    // ㉑ 비공개 1명은 분모에서 빠진다 · ㉒ winner RPC 의 players 는 독립 산식과 같고 quorum 은 5.
    #expect(sql.contains("update public.profiles set minigame_public = false where id = v_uids[5];"))
    #expect(sql.contains("raise exception '㉑ 비공개 참가자를 분모에서 빼지 않았다(5명으로 세어 지급했다): %', v_res;"))
    #expect(sql.contains("select w.players, w.quorum into v_players, v_quorum from public.minigame_yesterday_winner('timing_bar') w;"))
    #expect(sql.contains("if v_players is distinct from v_m or v_players < 5 then"))
    #expect(sql.contains("if v_quorum <> 5 then"))

    // 회귀 3종: ⑯ 자정 초기화(13 → 3 · 멱등) · ⑱ 3일 따라잡기 · ⑪ 잔량 13 보존/2 → ≤3.
    #expect(sql.contains("raise exception '⑯ 초기화가 13 → 3 을 하지 않았다: %', v_bal;"))
    #expect(sql.contains("where user_id = v_uids[1] and kst_day = v_today and reason = 'prize:expire' and delta = -10 and balance_after = 3;"))
    #expect(sql.contains("if (v_res->'reset'->>'performed') is distinct from 'false' or v_bal <> 3 then"))
    #expect(sql.contains("if jsonb_array_length(v_res->'days') <> 3 or (v_res->'reset'->>'performed') is distinct from 'false' then"))
    #expect(sql.contains("raise exception '⑪ 상한을 넘긴 잔량 13 이 sync 뒤 % 로 바뀌었다 — 배포 중단', v_bal;"))
    #expect(sql.contains("if v_bal > 3 or v_bal < 2 then"))

    // 롤백 확인(잔량·장부·오늘 초기화 키·과거 픽스처 행)과 역할 복귀.
    #expect(sql.contains("raise exception '프로브 롤백 실패(오늘 초기화 키 % → %)', v_pd0, v_n;"))
    #expect(sql.contains("raise exception '프로브 롤백 실패(과거 픽스처 점수 %행 잔존)', v_n;"))
    #expect(sql.contains("raise exception '프로브 종료 뒤 실행 역할이 어긋났다: %', current_user;"))
}

@Test
func quorumMigrationDoesNotTouchTheAlreadyAppliedFile() throws {
    // 앞 파일은 이미 프로덕션에 적용됐다 — 고치면 원격과 로컬이 갈린다. 새 파일이 그 파일의 표/트리거를 다시 만들지 않는지 본다.
    let sql = try qmMigrationSQL()
    #expect(!sql.contains("create table if not exists public.minigame_daily_scores"))
    #expect(!sql.contains("create table if not exists public.minigame_prizes"))
    #expect(!sql.contains("create table if not exists public.minigame_prize_days"))
    #expect(!sql.contains("create or replace function public.guard_minigame_score()"))
    #expect(!sql.contains("create function public.minigame_board("))
    #expect(!sql.contains("cron.schedule("), "스케줄은 앞 파일이 이미 등록했다(잡 이름이 같아 재등록은 무해하지만 출처를 하나로 둔다)")
    // 그리고 앞 파일 자체가 그대로 있다(계약 테스트가 읽는 대상).
    let prior = try String(contentsOf: qmRepoURL("supabase/migrations/20260908090000_minigame_scores.sql"), encoding: .utf8)
    #expect(prior.contains("create or replace function public.minigame_award_daily_prizes(p_day date default null)"))
}
