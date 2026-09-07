import Foundation
import Testing
@testable import check

// v0.2.46 — 서버 마이그레이션 계약(20260907140000_codex_fork_safe_tail.sql): 계정 스냅샷이 있는 사용자의 로컬 Codex 증거는
// 포크 억제 빌드(codex_diag_build ≥ 52 = v0.2.43 CodexForkTracker) 기기에서만 센다. 2026-09-07 abto.app 사고(메인 맥 build 51 이
// 하루 로컬 119.2억을 올려 순위판 146억)의 서버 쪽 방어다.
//
// 클라 `CodexEffectiveRule.month/day` 는 **자기 기기**(항상 현재 빌드 = 포크 안전) 의 로컬만 계정과 합치므로 이 게이트가 필요 없다 —
// 변경하지 않는다. 게이트는 여러 기기의 로컬이 섞이는 서버 산식에만 있다.

private func fsRepoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(relative)
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다). 문자열 리터럴 안의 `--` 는
/// 이 파일에 없다(있으면 아래 검색이 헛돈다 — 그때 이 헬퍼를 고쳐라).
private func fsStrippingSQLComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 보드 함수의 `returns table(...)` 블록(출력 컬럼 목록·순서)을 잘라 낸다 — 두 파일에서 글자 단위로 같아야 한다.
private func fsBoardReturnsBlock(_ sql: String) throws -> String {
    let start = try #require(sql.range(of: "create function public.token_usage_board(p_month text)\nreturns table(")?.upperBound)
    let end = try #require(sql.range(of: "\n)\nlanguage sql", range: start..<sql.endIndex)?.lowerBound)
    return String(sql[start..<end])
}

@Test
func migrationContractCodexForkSafeTail() throws {
    let raw = try String(contentsOf: fsRepoURL("supabase/migrations/20260907140000_codex_fork_safe_tail.sql"), encoding: .utf8)
    let sql = fsStrippingSQLComments(raw)
    let prevRaw = try String(contentsOf: fsRepoURL("supabase/migrations/20260906120000_codex_account_first.sql"), encoding: .utf8)
    let prev = fsStrippingSQLComments(prevRaw)

    // (i) 게이트: fork_safe 는 기기 행의 codex_diag_build ≥ 52 로 세우고, 꼬리·미로그인·비율은 *_safe 합만, today 는 비안전 기기의 Claude 몫만.
    let boardStart = try #require(sql.range(of: "create function public.token_usage_board(p_month text)")?.lowerBound)
    let boardEnd = try #require(sql.range(of: "\n$$;", range: boardStart..<sql.endIndex)?.upperBound)
    let boardBody = String(sql[boardStart..<boardEnd])
    #expect(boardBody.contains("(coalesce(md.codex_diag_build, 0) >= 52) as fork_safe"))
    #expect(boardBody.contains(">= 52"))
    #expect(boardBody.contains("local_all_safe"))
    #expect(boardBody.contains("local_online_safe"))
    #expect(boardBody.contains("local_offline_safe"))
    #expect(boardBody.contains("today_unsafe_claude"))
    #expect(boardBody.contains("today_safe"))
    #expect(boardBody.contains("claude_today_safe"))
    #expect(boardBody.contains("sum(x.local_all_safe) from daily_by_day x where x.uid = t.uid and x.day > t.account_last_day"),
            "꼬리가 fork_safe 기기 합을 쓰지 않는다")
    #expect(boardBody.contains("(select sum(x.local_online_safe)::numeric / nullif(sum(x.bucket), 0)"),
            "축소율 r 의 모집단이 꼬리(fork_safe)와 다르다")
    #expect(boardBody.contains("then least(d.today_total, coalesce(tc.claude_total, 0))"),
            "비안전 기기의 today 가 Claude 몫으로 잘리지 않는다")
    #expect(!boardBody.contains("p.app_build"), "게이트는 프로필의 빌드(마지막 기기가 쓴 값)가 아니라 기기 행의 빌드여야 한다 — abto.app 은 프로필 54 · 메인 기기 51")

    // (ii) 꼬리·차분·미로그인이 전 기기 합(local_all/local_online/local_offline)을 쓰지 않는다.
    #expect(!boardBody.contains("x.local_all)"), "꼬리가 아직 전 기기 합을 쓴다 — 구빌드 로컬이 증거로 남는다")
    #expect(!boardBody.contains("x.local_online)"))
    #expect(!boardBody.contains("x.local_offline)"))
    #expect(!boardBody.contains("as local_all,"))

    // (iii) 출력 컬럼 15개·순서 불변: 종전 파일의 returns table 블록과 글자 단위로 같고, 마지막 select 도 같다(클라 TokenBoardRow 디코드).
    #expect(try fsBoardReturnsBlock(sql) == fsBoardReturnsBlock(prev))
    #expect(sql.contains("  codex_cache_read bigint,\n  codex_account_month bigint,\n  codex_effective bigint\n)"))
    #expect(sql.contains("m.codex_account_month,\n    m.codex_effective\n  from merged m"))
    #expect(sql.contains("drop function if exists public.token_usage_board(text);"))
    // health 는 시그니처 그대로(create or replace) — 반환 끝이 포크 두 컬럼.
    #expect(sql.contains("create or replace function public.token_scan_health(p_month text default null)"))
    #expect(sql.contains("codex_account_status smallint, codex_account_month bigint,\n  codex_diag_fork_files int, codex_diag_fork_tokens bigint\n)"))

    // (iii-1) 종전 계약이 그대로다(회귀 방지): UTC coalesce · P0 prefer_device · greatest 부재 · 오늘 서브쿼리 달 가둠 · 계정 없음 분기.
    #expect(boardBody.contains("coalesce(dd.codex_utc_total, dd.codex_total)"))
    #expect(!boardBody.contains("greatest(sum(d.codex_input + d.codex_output)"))
    #expect(boardBody.contains("(d.codex_account is not null or d.claude_total + d.codex_local >= coalesce(g.total, 0))"))
    #expect(boardBody.contains("when t.codex_account is null or t.account_last_day is null then t.codex_local"))
    #expect(boardBody.contains("when t.codex_account is null or t.account_last_day is null then t.today_total"))
    #expect(boardBody.contains("where dd.day like p_month || '-%'\n      and dd.day = to_char((now() at time zone 'Asia/Seoul')::date, 'YYYY-MM-DD')"),
            "오늘 Claude 서브쿼리가 조회 달로 가둬져 있지 않다(20260906120000 ⓘ 경계)")
    #expect(boardBody.contains("(e.claude_total + e.codex_effective)::bigint as total"))

    // (iv) health 판정: '구버전 스캐너' 는 '스캐너 멈춤' 뒤·'과다계상 의심' 앞, 나머지 순서 유지.
    let stalled = try #require(sql.range(of: "'스캐너 멈춤(24시간 이상)'")?.lowerBound)
    let oldBuild = try #require(sql.range(of: "'Codex 구버전 스캐너(build '")?.lowerBound, "구버전 스캐너 판정이 없다")
    let overcount = try #require(sql.range(of: "'Codex 로컬이 계정보다 큼(과다계상 의심)'")?.lowerBound)
    let stale = try #require(sql.range(of: "'계정 스냅샷 노후(48h+)'")?.lowerBound)
    let legacyWins = try #require(sql.range(of: "'옛 행이 보드를 덮음'")?.lowerBound)
    let normal = try #require(sql.range(of: "else '정상'")?.lowerBound)
    #expect(stalled < oldBuild && oldBuild < overcount && overcount < stale && stale < legacyWins && legacyWins < normal)
    #expect(sql.contains("bool_or(coalesce(d.codex_diag_build, 0) < 52 and d.codex_input + d.codex_output > 0)"))

    // (v) 실행권: 보드는 anon 불가·authenticated/service_role 가능, health 는 service_role 전용.
    #expect(sql.contains("revoke execute on function public.token_usage_board(text) from public, anon;"))
    #expect(sql.contains("grant execute on function public.token_usage_board(text) to authenticated, service_role;"))
    #expect(sql.contains("revoke execute on function public.token_scan_health(text) from public, anon, authenticated;"))
    #expect(sql.contains("grant  execute on function public.token_scan_health(text) to service_role;"))

    // (vi) 프로브: 종전 ⓐ~ⓚ 재생(build 54 픽스처) + 새 ⓛ 계열 기대값 · 센티널 롤백 · 실행 역할 캡처.
    for expected in ["<> 120 then", "<> 150 then", "<> 125 then", "<> 155 then", "<> 104 or v_today_total <> 10 then",
                     "<> 118 then", "<> 160 or v_local <> 190 then",
                     "<> 100 or v_total <> 100 then", "<> 105 then", "<> 30 then", "<> 150 or v_today_total <> 50 then"] {
        #expect(sql.contains(expected), "프로브 기대값 누락: \(expected)")
    }
    #expect(sql.contains("codex_diag_build = 51"), "구빌드 픽스처가 없다")
    #expect(sql.contains("'Codex 구버전 스캐너(build 51)%'"))
    #expect(sql.contains("v_exec_role text := current_user;"))
    #expect(sql.contains("if current_user <> v_exec_role then"))
    #expect(sql.contains("raise exception 'FORK_SAFE_PROBE_ROLLBACK';"))
    #expect(sql.contains("if sqlerrm <> 'FORK_SAFE_PROBE_ROLLBACK' then raise; end if;"))
    #expect(sql.contains("FORK_SAFE_PROBE_"))
    #expect(!sql.contains("ACCOUNT_FIRST_PROBE_"), "종전 프로브 기기 id 를 그대로 쓰면 두 파일의 정리 predicate 가 겹친다")
    #expect(!sql.contains("create table"))     // 표를 만들지 않는다(PGRST201 회피)
    #expect(!sql.contains("add column"))       // 컬럼도 더하지 않는다(클라 업로드 계약 불변)
}

/// 클라 규칙은 손대지 않는다: 자기 기기 산식(`CodexEffectiveRule.month`)은 서버 게이트와 무관하게 종전 픽스처 그대로다.
/// (V0243AccountFirstTests 가 숫자를 고정한다 — 여기서는 규칙 타입이 서버 게이트 어휘를 갖지 않음만 못 박는다.)
@Test
func clientRuleIsUntouchedByTheServerGate() throws {
    let source = try String(contentsOf: fsRepoURL("Sources/check/CodexEffectiveRule.swift"), encoding: .utf8)
    #expect(!source.contains("fork_safe"))
    #expect(!source.contains("codexDiagBuild"))
}
