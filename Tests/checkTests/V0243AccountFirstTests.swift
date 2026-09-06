import Foundation
import Testing
@testable import check

// v0.2.43 — Codex 계정 우선 산식(issue #6 후속).
//
// 배경: Codex CLI 는 포크(서브에이전트·thread/fork·review)마다 부모 rollout 의 token_count 를 새 파일에 통째로 복사한다.
// 파일별 차분 스캐너는 그 복사본을 새 소비로 세어 제보자 계정에서 로컬이 계정의 4.64배(225억 vs 48.5억)로 부풀었고,
// `greatest(로컬, 계정)` 은 정확히 그 부풀린 쪽을 골라 순위판 1·2위에 올렸다(2026-09-06 프로덕션 실측).
// 그래서 산식을 "계정 우선 + 미반영 꼬리만 로컬" 로 바꾼다. 여기서 고정하는 것:
//   (A) 순수 규칙(CodexEffectiveRule) — 서버 마이그레이션 20260906120000 의 프로브 ⓐ~ⓓ 와 **같은 숫자**.
//   (B) 잔디 병합(TokenDailyMerge) — 하루 단위로 같은 규칙.
//   (C) 순위판 행(TokenBoardRow/TokenBoardEntry) — 서버 codex_effective 디코드·폴백·캡션·툴팁.
//   (D) 내 박스(TokenUsageDisplay·TokenUsageMonthly.detailTooltip) — 같은 규칙·같은 어휘.
//   (E) SQL 계약 — 마이그레이션 파일 문자열(주석 제거 후).

private let afNow = Date(timeIntervalSince1970: 1_757_100_000)   // 2025-09-05 20:00:00 UTC — 버킷 보관 창 계산에만 쓴다
/// Codex 숫자가 있는 툴팁은 끝에 하루의 뜻(9시 경계)을 밝힌다(v0.2.43 UTC 축 — V0243UTCAxisTests 가 리터럴·배선을 고정).
private func afAccount(_ buckets: [String: Int]) -> CodexAccountUsage {
    CodexAccountUsage(fetchedAt: afNow, lifetimeTokens: nil, buckets: buckets)
}
private func afRow(_ day: String, _ device: String, claude: Int = 0, codex: Int, account: Int?) -> TokenUsageDailyRow {
    TokenUsageDailyRow(day: day, deviceId: device, claudeTotal: claude, codexTotal: codex, codexAccount: account)
}
private func afUsage(month: String = "2026-09", codexInput: Int = 0, claudeDaily: [String: Int] = [:], codexDaily: [String: Int] = [:]) -> TokenUsageMonthly {
    var usage = TokenUsageMonthly(month: month)
    usage.codexInput = codexInput
    usage.claudeDaily = claudeDaily
    usage.codexDaily = codexDaily
    return usage
}
/// 보드 엔트리 픽스처(전부 0 이 기본). `serverEffective` 가 nil 이면 옛 RPC(codex_effective 없음)를 흉내낸다.
private func afEntry(
    claudeInput: Int = 0, codexInput: Int = 0, codexOutput: Int = 0, codexCacheRead: Int = 0,
    codexAccountMonth: Int? = nil, serverEffective: Int? = nil, total: Int? = nil
) -> TokenBoardEntry {
    let codex = serverEffective ?? max(codexInput + codexOutput, codexAccountMonth ?? 0)
    return TokenBoardEntry(
        userID: "u1", name: "영식", avatarURL: nil, total: total ?? (claudeInput + codex),
        claudeInput: claudeInput, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: codexInput, codexOutput: codexOutput,
        codexCacheRead: codexCacheRead, codexAccountMonth: codexAccountMonth, codexEffectiveFromServer: serverEffective
    )
}

// MARK: - (B) 잔디 병합 — 하루 단위 계정 우선

@Test
func serverTotalsUseTheAccountBucketForReflectedDaysAndLocalOnlyForTheTail() {
    // 마지막 버킷 날짜(9/2) 앞은 계정값, 그 날은 큰 쪽, 그 뒤는 로컬. 9/1 의 로컬 900 은 **버려진다**(옛 max 면 900 이 살아남았다 —
    // 포크 복사본으로 부푼 값이 잔디를 물들이던 자리).
    let totals = TokenDailyMerge.serverTotals([
        afRow("2026-09-01", "MAC-A", codex: 900, account: 100),
        afRow("2026-09-02", "MAC-A", codex: 50, account: 300),
        afRow("2026-09-03", "MAC-A", codex: 20, account: nil)
    ])
    #expect(totals["2026-09-01"] == 100)
    #expect(totals["2026-09-02"] == 300)
    #expect(totals["2026-09-03"] == 20)
    // 계정 버킷은 기기 간 max, 로컬은 기기 합(꼬리 날). claude 는 언제나 기기 합으로 더한다.
    let two = TokenDailyMerge.serverTotals([
        afRow("2026-09-01", "MAC-A", claude: 1_000, codex: 200, account: 1_000),
        afRow("2026-09-01", "MAC-B", claude: 500, codex: 100, account: 1_000),
        afRow("2026-09-02", "MAC-A", claude: 7, codex: 20, account: nil),
        afRow("2026-09-02", "MAC-B", claude: 0, codex: 30, account: nil)
    ])
    #expect(two["2026-09-01"] == 1_500 + 1_000)   // 마지막 버킷 날(9/1) = max(1,000, 300) = 1,000 (뻥튀기 없음)
    #expect(two["2026-09-02"] == 7 + 50)          // 꼬리 = 기기 합
    // 계정을 보고한 기기가 하나도 없으면 로컬 그대로(옛 동작).
    #expect(TokenDailyMerge.serverTotals([afRow("2026-09-04", "MAC-A", codex: 77, account: nil)])["2026-09-04"] == 77)
    // 반영된 날인데 그 날 버킷이 없는 기기만 있으면 0 — 로컬 값으로 채우지 않는다(계정에 사용이 없는 날).
    let reflectedGap = TokenDailyMerge.serverTotals([
        afRow("2026-09-01", "MAC-A", codex: 500, account: nil),
        afRow("2026-09-02", "MAC-A", codex: 0, account: 40)
    ])
    #expect(reflectedGap["2026-09-01"] == nil || reflectedGap["2026-09-01"] == 0)
    #expect(reflectedGap["2026-09-02"] == 40)
    // 음수 방어.
    #expect(TokenDailyMerge.serverTotals([afRow("2026-09-05", "MAC-A", claude: -5, codex: -7, account: nil)])["2026-09-05"] == 0)
    #expect(TokenDailyMerge.serverTotals([]).isEmpty)
}

@Test
func localTotalsUseTheAccountBucketForReflectedDaysAndLocalOnlyForTheTail() {
    let usage = afUsage(
        claudeDaily: ["2026-09-01": 1_000, "2026-09-02": 30],
        codexDaily: ["2026-09-01": 900, "2026-09-02": 50, "2026-09-03": 20]
    )
    let local = TokenDailyMerge.localTotals(usage: usage, account: afAccount(["2026-09-01": 100, "2026-09-02": 300, "2026-08-20": 7]))
    #expect(local["2026-09-01"] == 1_000 + 100)   // 반영된 날: 계정(로컬 900 은 버린다)
    #expect(local["2026-09-02"] == 30 + 300)      // 마지막 버킷 날: max(300, 50)
    #expect(local["2026-09-03"] == 20)            // 꼬리: 로컬
    #expect(local["2026-08-20"] == 7)             // 로컬 맵 밖(지난 달)은 계정 버킷이 채운다
    #expect(local["2026-09-09"] == nil)
    // 계정이 없으면 로컬 그대로.
    let noAccount = TokenDailyMerge.localTotals(usage: usage, account: nil)
    #expect(noAccount["2026-09-01"] == 1_900)
    #expect(TokenDailyMerge.localTotals(usage: nil, account: nil).isEmpty)
}

// MARK: - (C) 순위판 툴팁 — 캡션의 두 값만

@Test
func boardTooltipShowsOnlyTheTwoCaptionValuesInFullPrecision() {
    // v0.2.45: 툴팁은 캡션에 보이는 두 값의 정확한 숫자뿐이다 — 로컬/계정 구분·캐시·포크 의심·축 설명은 운영자 진단이라
    // UI 에서 걷어냈다(사용자 지적 "유저들한테 너무 과하게 다 표시한다"). Codex 는 codexEffective(굵은 총합·캡션과 같은 값).
    let accountDriven = afEntry(claudeInput: 10, codexInput: 120, codexCacheRead: 60, codexAccountMonth: 1_000, serverEffective: 1_000)
    #expect(accountDriven.detailTooltip == "Claude 10 · Codex 1,000")
    // 로컬이 계정보다 커도(포크 복사본) 서버가 준 유효값만 적는다 — 진단 문구는 없다(서버 token_scan_health 가 낸다).
    let overcount = afEntry(codexInput: 150, codexAccountMonth: 100, serverEffective: 120)
    #expect(overcount.detailTooltip == "Codex 120")
    let withinLag = afEntry(codexInput: 120, codexAccountMonth: 100, serverEffective: 110)
    #expect(withinLag.detailTooltip == "Codex 110")
    // 계정을 모르면(옛 RPC·미보고) 종전 max 폴백 값 그대로.
    #expect(afEntry(codexInput: 120, codexCacheRead: 60).detailTooltip == "Codex 120")
    // 로컬 0·계정만 있는 사람.
    #expect(afEntry(codexAccountMonth: 300, serverEffective: 300).detailTooltip == "Codex 300")
    #expect(afEntry().detailTooltip == "")
    // 진단 어휘 부정 단언 — 어느 툴팁에도 없다.
    for tip in [accountDriven, overcount, withinLag].map(\.detailTooltip) {
        for word in ["로컬", "계정 집계", "캐시", "포크", "축", "총합", "기준"] {
            #expect(!tip.contains(word), "툴팁에 진단 어휘 '\(word)': \(tip)")
        }
    }
}

// MARK: - (D) 내 박스 툴팁 — 같은 모양

@Test
func myBoxTooltipShowsClaudeAndEffectiveCodexOnly() {
    var usage = TokenUsageMonthly(month: "2026-09")
    usage.codexInput = 1_000; usage.codexOutput = 200; usage.codexCacheRead = 700
    #expect(usage.detailTooltip == "Codex 1,200")
    // 계정이 있으면 계정 우선 규칙의 유효값(TokenUsageDisplay.codexEffective) 하나만 — 로컬·계정 두 숫자를 나란히 놓지 않는다.
    let big = afAccount(["2026-09-01": 3_000, "2026-09-07": 2_000, "2026-08-31": 999])
    #expect(usage.detailTooltip(account: big) == "Codex 5,000")
    let equal = afAccount(["2026-09-02": 1_200])
    #expect(usage.detailTooltip(account: equal) == "Codex 1,200")
    let small = afAccount(["2026-09-02": 900])
    #expect(usage.detailTooltip(account: small) == "Codex 900")
    // 이 달 버킷이 없으면(월합 0·마지막 날 없음) 로컬 그대로 — 지난달 버킷을 이번 달로 오인하지 않는다.
    #expect(usage.detailTooltip(account: afAccount(["2026-08-31": 999])) == "Codex 1,200")
    usage.claudeInput = 10
    #expect(usage.detailTooltip(account: big) == "Claude 10 · Codex 5,000")
    for word in ["로컬", "계정 집계", "캐시", "포크", "축", "총합", "반영", "입력", "출력"] {
        #expect(!usage.detailTooltip(account: small).contains(word), "툴팁에 진단 어휘 '\(word)'")
    }
}

// MARK: - (E) SQL 계약 (20260906120000_codex_account_first.sql)

private func afRepoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(relative)
}

/// `--` 줄 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다). 문자열 리터럴 안의 `--` 는
/// 이 파일에 없다(있으면 아래 검색이 헛돈다 — 그때 이 헬퍼를 고쳐라).
private func afStrippingSQLComments(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// 서버 마이그레이션 계약(20260906120000): 진단 컬럼 2개 · 보드는 codex_effective 를 맨 끝에 더한 15컬럼 · 계정 우선 산식(greatest 로
/// 로컬·계정을 고르지 않는다) · 꼬리는 일별 표 · health 는 두 컬럼 추가에 판정 순서 유지 · 실행권 · 프로브 ⓐ~ⓓ 와 센티널 롤백.
/// 파일이 없으면(supabase/ 없는 체크아웃) 다른 SQL 계약 테스트와 같이 **빨강**이다.
@Test
func migrationContractCodexAccountFirst() throws {
    let raw = try String(contentsOf: afRepoURL("supabase/migrations/20260906120000_codex_account_first.sql"), encoding: .utf8)
    let sql = afStrippingSQLComments(raw)
    // (i) 진단 컬럼 2개.
    #expect(sql.contains("add column if not exists codex_diag_fork_files int"))
    #expect(sql.contains("add column if not exists codex_diag_fork_tokens bigint"))
    // (ii) 보드: 반환 타입이 바뀌므로 drop 선행, 옛 14컬럼 뒤에 codex_effective.
    #expect(sql.contains("drop function if exists public.token_usage_board(text);"))
    #expect(sql.contains("  codex_cache_read bigint,\n  codex_account_month bigint,\n  codex_effective bigint\n)"))
    #expect(sql.contains("m.codex_account_month,\n    m.codex_effective\n  from merged m"))
    // (iii) 계정 우선: 보드 함수 본문에 greatest 로 로컬·계정을 고르는 산식이 없다(주석 제거 후; 사후 단언의 문자열 리터럴은 본문 밖이라
    //       함수 본문만 잘라 본다). 꼬리는 일별 표에서, 마지막 버킷 날은 차이만.
    let boardStart = try #require(sql.range(of: "create function public.token_usage_board(p_month text)")?.lowerBound)
    let boardEnd = try #require(sql.range(of: "\n$$;", range: boardStart..<sql.endIndex)?.upperBound)
    let boardBody = String(sql[boardStart..<boardEnd])
    #expect(!boardBody.contains("greatest(sum(d.codex_input + d.codex_output)"))
    #expect(!boardBody.contains("greatest(coalesce(d.codex_input"))
    #expect(boardBody.contains("(e.claude_total + e.codex_effective)::bigint as total"))
    #expect(sql.contains("max(d.codex_account_last_day) as account_last_day"))
    // D1(UTC 축 보강)이 꼬리·마지막 날 서브쿼리를 daily_by_day(별칭 x) 위로 옮기고, "계정 없음"과 "이달 버킷 없음" 분기를
    // 한 줄로 합쳤다 — 뜻은 같다(둘 다 로컬 전액). 문자열은 마이그레이션 본문과 글자 단위로 같아야 한다.
    #expect(sql.contains("x.day > t.account_last_day"), "미반영 꼬리(last_day 뒤 날짜)를 로컬로 더하는 서브쿼리가 없다")
    #expect(sql.contains("x.day = t.account_last_day"), "마지막 버킷 날의 로컬·버킷 차분 서브쿼리가 없다")
    #expect(sql.contains("when t.codex_account is null or t.account_last_day is null then t.codex_local"),
            "계정 없음/이달 버킷 없음 → 로컬 전액 분기가 없다")
    #expect(sql.contains("(l.codex_input + l.codex_output)::bigint as codex_effective"))
    // (iii-1) v0.2.43 UTC 축(검토 P1·P0·P2, spec-d §1): 일별 표에 codex_utc_total 을 더하고, 꼬리·마지막 날 차분은 UTC 값을 우선 쓴다.
    //         옛 표(token_usage_monthly) 행 선택은 계정 기준 effective 를 옛 로컬과 견주지 않는다 — 계정이 있으면 기기 행이 이긴다(P0:
    //         이 조건이 없으면 로컬을 부풀린 사용자는 옛 행이 반드시 이겨 순위판 값이 한 자리도 안 바뀐다). 문자열은 D1 과 글자 단위로 같아야 한다.
    #expect(sql.contains("add column if not exists codex_utc_total bigint"))
    #expect(sql.contains("coalesce(dd.codex_utc_total, dd.codex_total)"))
    #expect(!boardBody.contains("sum(dd.codex_total)"), "꼬리·차분이 아직 KST 값(codex_total)만 본다 — UTC 값 우선이어야 한다")
    #expect(sql.contains("(d.codex_account is not null or d.claude_total + d.codex_local >= coalesce(g.total, 0))"))
    #expect(!sql.contains("coalesce(d.total, 0) >= coalesce(g.total, 0)) as prefer_device"), "옛 표 선택이 여전히 effective 를 옛 로컬과 견준다(P0)")
    // (iv) health: 두 컬럼을 맨 끝에, 판정 순서(과다계상 의심 < 정상) 유지. v0.2.43: 스냅샷 노후·옛 행 덮어쓰기 판정도 '정상' 앞에.
    #expect(sql.contains("drop function if exists public.token_scan_health(text);"))
    #expect(sql.contains("codex_account_status smallint, codex_account_month bigint,\n  codex_diag_fork_files int, codex_diag_fork_tokens bigint\n)"))
    #expect(sql.contains("max(d.codex_diag_fork_files)::int"))
    #expect(sql.contains("max(d.codex_diag_fork_tokens)::bigint"))
    let overcount = try #require(sql.range(of: "'Codex 로컬이 계정보다 큼(과다계상 의심)'")?.lowerBound)
    let normal = try #require(sql.range(of: "else '정상'")?.lowerBound)
    #expect(overcount < normal)
    let stale = try #require(sql.range(of: "'계정 스냅샷 노후(48h+)'")?.lowerBound, "스냅샷 노후 판정이 없다")
    let legacyWins = try #require(sql.range(of: "'옛 행이 보드를 덮음'")?.lowerBound, "옛 행 덮어쓰기 판정이 없다")
    #expect(stale < normal && legacyWins < normal, "새 판정이 '정상' 뒤에 있으면 영원히 안 뜬다")
    // (v) 실행권: 보드는 anon 불가·authenticated/service_role 가능, health 는 service_role 전용.
    #expect(sql.contains("revoke execute on function public.token_usage_board(text) from public, anon;"))
    #expect(sql.contains("grant execute on function public.token_usage_board(text) to authenticated, service_role;"))
    #expect(sql.contains("revoke execute on function public.token_scan_health(text) from public, anon, authenticated;"))
    #expect(sql.contains("grant  execute on function public.token_scan_health(text) to service_role;"))
    // (vi) 프로브 ⓐ~ⓓ 와 센티널 롤백 — Swift 규칙 테스트와 같은 숫자(120 · 150 · 150 · 125).
    for expected in ["<> 120 then", "<> 150 then", "<> 125 then"] {
        #expect(sql.contains(expected), "프로브 기대값 누락: \(expected)")
    }
    #expect(sql.contains("raise exception 'ACCOUNT_FIRST_PROBE_ROLLBACK';"))
    #expect(sql.contains("if sqlerrm <> 'ACCOUNT_FIRST_PROBE_ROLLBACK' then raise; end if;"))
    #expect(sql.contains("ACCOUNT_FIRST_PROBE_"))
    #expect(!sql.contains("create table"))     // 표를 만들지 않는다(PGRST201 회피)
}
