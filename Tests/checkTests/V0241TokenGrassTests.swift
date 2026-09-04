import Foundation
import Testing
@testable import check

// MARK: - v0.2.41: 토큰 잔디(일별 토큰 기록 + 내 기록 잔디, issue #3 의 토큰 절반) 회귀 그물
//
// 이 파일이 지키는 것 넷:
//  (A) 순수 병합 규칙 — 서버 기기 행(claude+codex 는 sum, codex_account 는 max) · 로컬(claude + max(codex, 계정)) ·
//      둘의 날짜별 max. 이 셋 중 하나만 어긋나도 잔디가 조용히 반쯤 밝거나 두 배로 진해진다(픽셀로는 못 잡는다).
//  (B) 격자 — 근무 잔디와 **같은 창·같은 미래 칸 규약**. 하루만 어긋나도 나란히 선 두 잔디가 서로를 반증한다.
//  (C) 업로드/조회 계약 — 경로·본문 모양(배열·스네이크·codex_account 생략)·변경된 날만·월간 뒤 순서·수집 거부 침묵.
//  (D) SQL 계약 — 표/정책/트리거/프로브 문자열(마이그레이션 20260903170000).
// 렌더(픽셀·패널 순서·높이 예산)는 CheckMenuRenderTests.swift 쪽에 산다(그쪽 private 헬퍼를 쓰기 때문).

// MARK: - 픽스처 헬퍼

/// KST 2026-09-03(목) 12:00 — 마이그레이션 프로브·CHANGELOG 와 같은 달. 월 문자열은 "2026-09".
private let tgNow = tgUTC("2026-09-03T03:00:00Z")

private func tgUTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

private func tgDefaults() -> UserDefaults {
    UserDefaults(suiteName: "check-v0241-grass-\(UUID().uuidString)")!
}

private let tgUserID = "00000000-0000-0000-0000-000000000009"
private let tgDailyPath = "/rest/v1/token_usage_device_daily"
private let tgMonthlyPath = "/rest/v1/token_usage_device_monthly"

private func tgUsage(
    month: String = "2026-09",
    claudeDaily: [String: Int] = [:],
    codexDaily: [String: Int] = [:]
) -> TokenUsageMonthly {
    var usage = TokenUsageMonthly(month: month)
    usage.claudeDaily = claudeDaily
    usage.codexDaily = codexDaily
    // 월간 업로드 게이트(총합 > 0)를 통과시키기 위한 최소값 — 일별 경로와는 무관하다.
    usage.claudeInput = claudeDaily.values.reduce(0, +) + codexDaily.values.reduce(0, +)
    return usage
}

private func tgAccount(_ buckets: [String: Int]) -> CodexAccountUsage {
    CodexAccountUsage(fetchedAt: tgNow, lifetimeTokens: nil, buckets: buckets)
}

private func tgRow(_ day: String, _ device: String, claude: Int, codex: Int, account: Int?) -> TokenUsageDailyRow {
    TokenUsageDailyRow(day: day, deviceId: device, claudeTotal: claude, codexTotal: codex, codexAccount: account)
}

/// 이 맥의 로컬 일별 맵을 담은 격리 토큰 스토어. 홈은 빈 임시 디렉터리다 — 기본 생성자를 쓰면 **테스트 러너가
/// 진짜 홈의 Claude/Codex 로그를 읽어** 잔디 값이 이 맥의 실제 사용량이 되고, 단언이 그날그날 달라진다(실측 11억).
@MainActor
private func tgTokenStore(snapshot: TokenUsageMonthly?) -> TokenUsageStore {
    let defaults = tgDefaults()
    if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
        defaults.set(data, forKey: TokenUsageStore.snapshotKey)
    }
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0241-grass-home-\(UUID().uuidString)", isDirectory: true)
    return TokenUsageStore(
        defaults: defaults, homeDirectory: home,
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false),
        notificationCenter: NotificationCenter(), codexHomeResolver: { nil })
}

@MainActor
private func tgStore(host: String, localSnapshot: TokenUsageMonthly? = nil) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: URLSession(configuration: .stubbed))
    let store = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"], defaults: tgDefaults(),
        workspaceNotifications: nil, tokenUsage: tgTokenStore(snapshot: localSnapshot))
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: tgUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    store.isMenuPresented = false
    store.deviceID = "MAC-A"
    store.tokenUsagePublicLoaded = true
    store.tokenUsageCollectLoaded = true
    return store
}

@MainActor
private func tgCancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel(); store.refreshTask?.cancel(); store.syncTask?.cancel(); store.pokePollTask?.cancel()
}

/// 일별 표로 나간 POST 요청들의 본문(배열 그대로).
private func tgDailyBodies(host: String) -> [[[String: Any]]] {
    zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == tgDailyPath && $0.0.httpMethod == "POST" }
        .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.1.utf8))) as? [[String: Any]] }
}

private func tgDailyRequests(host: String) -> [URLRequest] {
    URLProtocolStub.requests(forHost: host).filter { $0.url?.path == tgDailyPath }
}

// MARK: - (A) 병합 순수 규칙

@Test
func serverTotalsSumsDeviceLogsButReadsTheAccountBucketAsMax() {
    // 기기 두 대가 같은 날을 올렸다. claude/codex 로컬 로그는 **각 맥의 자기 몫**이라 더하고(sum), codex_account 는
    // 두 맥이 **같은 계정값**을 올리므로 더하면 기기 수만큼 뻥튀기된다 — max 로 읽는다(월 표 20260903160000 과 같은 성질).
    let totals = TokenDailyMerge.serverTotals([
        tgRow("2026-09-01", "MAC-A", claude: 1_000, codex: 200, account: 1_000),
        tgRow("2026-09-01", "MAC-B", claude: 500, codex: 100, account: 1_000)
    ])
    // claude 합 1,500 + max(codex 로컬 합 300, 계정 1,000) = 2,500. (sum 이면 3,500 — 정확히 계정값 한 번만큼 더 크다.)
    #expect(totals["2026-09-01"] == 2_500)
    #expect(totals.count == 1)

    // 계정이 로컬보다 작으면 로컬이 이긴다(계정 반영이 수십 분 늦는 창 — 오늘 칸이 뒷걸음질하지 않게).
    #expect(TokenDailyMerge.serverTotals([tgRow("2026-09-02", "MAC-A", claude: 0, codex: 900, account: 100)])["2026-09-02"] == 900)
    // null 계정(그 기기가 버킷을 보고하지 않음)은 max 에서 아예 빠진다 — 0 으로 읽어 다른 기기 값을 깎으면 안 된다.
    #expect(TokenDailyMerge.serverTotals([
        tgRow("2026-09-03", "MAC-A", claude: 0, codex: 0, account: 800),
        tgRow("2026-09-03", "MAC-B", claude: 0, codex: 0, account: nil)
    ])["2026-09-03"] == 800)
    // 음수 방어(서버 값이 상하더라도 잔디가 음수 칸으로 새지 않게).
    #expect(TokenDailyMerge.serverTotals([tgRow("2026-09-04", "MAC-A", claude: -5, codex: -7, account: nil)])["2026-09-04"] == 0)
    #expect(TokenDailyMerge.serverTotals([]).isEmpty)
}

@Test
func localTotalsAddClaudeToTheGreaterOfCodexLogAndAccountBucket() {
    // 이 맥의 일별 유효 토큰 = claude + max(codex 로컬, 계정 버킷). 서버 보드 RPC 의 greatest 산식을 하루 단위로 옮긴 것.
    let usage = tgUsage(
        claudeDaily: ["2026-09-01": 1_000, "2026-09-02": 30],
        codexDaily: ["2026-09-01": 200, "2026-09-03": 50]
    )
    let local = TokenDailyMerge.localTotals(usage: usage, account: tgAccount(["2026-09-01": 900, "2026-08-20": 7]))

    #expect(local["2026-09-01"] == 1_900)   // 1,000 + max(200, 900)
    #expect(local["2026-09-02"] == 30)      // claude 만
    #expect(local["2026-09-03"] == 50)      // codex 만
    // 계정 버킷은 ~70일이라 **로컬 맵 밖(지난 달)의 Codex 날**도 채운다 — 로컬 맵은 현재 월뿐이라 여기가 유일한 원천이다.
    #expect(local["2026-08-20"] == 7)
    // 0 인 날은 키를 만들지 않는다(빈 칸과 "0을 보고한 날"을 굳이 가르지 않는다 — 잔디에선 둘 다 옅은 바탕이다).
    #expect(local["2026-09-09"] == nil)
    #expect(TokenDailyMerge.localTotals(usage: nil, account: nil).isEmpty)
    #expect(TokenDailyMerge.localTotals(usage: tgUsage(claudeDaily: ["2026-09-01": 0]), account: nil).isEmpty)
}

@Test
func mergedTakesTheLargerOfServerAndLocalPerDay() {
    // 어느 쪽이 진실에 가까운지는 날마다 다르다 — 오늘·최근은 로컬이 더 최신(업로드는 60초 게이트)이고,
    // 지난 달과 다른 기기 몫은 서버만 안다. 그래서 **큰 쪽**을 쓴다(더하면 이 맥의 몫이 두 번 계상된다).
    let merged = TokenDailyMerge.merged(
        server: ["2026-09-01": 2_500, "2026-09-02": 10, "2026-08-31": 77],
        local: ["2026-09-02": 900, "2026-09-03": 5]
    )
    #expect(merged["2026-09-01"] == 2_500)   // 서버만
    #expect(merged["2026-09-02"] == 900)     // 로컬이 더 최신
    #expect(merged["2026-08-31"] == 77)      // 로컬에 없는 지난 달
    #expect(merged["2026-09-03"] == 5)       // 서버에 아직 없는 오늘
    #expect(merged.count == 4)
    // 합산이 아니다 — 같은 날 둘 다 있으면 합(3,400)이 아니라 큰 쪽(2,500)이다.
    #expect(TokenDailyMerge.merged(server: ["d": 2_500], local: ["d": 900])["d"] == 2_500)
}

// MARK: - (B) 격자(TokenDailyGrid)

@Test
func tokenGridUsesTheSameThirteenWeekWindowAsTheWorkGrass() {
    // 같은 패널에 두 잔디가 나란히 서므로 창이 하루라도 어긋나면 그 자체가 결함으로 보인다.
    let grid = TokenDailyGrid.build(daily: [:], now: tgNow)
    let work = WorkDailyGrid.build(parsed: [], now: tgNow)

    #expect(grid.weeks == work.weeks)
    #expect(grid.weeks == WorkDailyGrid.defaultWeeks)
    #expect(grid.weekStart == work.weekStart)
    #expect(grid.days == work.days)
    for week in 0..<grid.weeks {
        for weekday in 0..<WorkRhythmHeatmap.dayCount {
            #expect(grid.isFuture(week: week, weekday: weekday) == work.isFuture(week: week, weekday: weekday))
        }
    }
    // 분모는 하루 5천만 고정(자기 최대값 기준이면 사람마다·주마다 기준이 흔들린다 — 근무 8시간과 같은 철학).
    #expect(TokenDailyGrid.fullDayTokens == 50_000_000)
    #expect(TokenDailyGrid.empty.weeks == 0)
    #expect(TokenDailyGrid.empty.totalTokens == 0)
}

@Test
func tokenGridPlacesDaysInTheRightCellAndKeepsFutureCellsZero() {
    // tgNow = 2026-09-03(목). 이번 주 월요일 = 08-31, 창 시작 = 그 12주 전 = 2026-06-08(월).
    let grid = TokenDailyGrid.build(daily: [
        "2026-09-03": 12_000,      // 오늘 = 마지막 열 목요일
        "2026-08-31": 5_000,       // 마지막 열 월요일
        "2026-06-08": 700,         // 첫 열 월요일(창의 정확한 하한)
        "2026-06-07": 999,         // 창 하루 전 → 버린다
        "2026-09-06": 999,         // 이번 주 일요일 = 미래 → 버린다(시계가 앞선 기기의 행 방어)
        "2026-09-04": 999,         // 내일 → 버린다
        "20260903": 999,           // 형 어긋남 → 버린다(잔디 전체를 못 그리는 것보다 낫다)
        "": 999
    ], now: tgNow)

    #expect(grid.weekStart == TokenDailyGrid.date(fromDay: "2026-06-08"))
    let last = grid.weeks - 1
    #expect(grid.tokens[last][3] == 12_000)
    #expect(grid.tokens[last][0] == 5_000)
    #expect(grid.tokens[0][0] == 700)
    #expect(grid.totalTokens == 17_700, "창 밖·미래·형 어긋난 키가 섞여 들어왔다")
    // 미래 칸은 언제나 0 이다(불변식).
    for week in 0..<grid.weeks {
        for weekday in 0..<WorkRhythmHeatmap.dayCount where grid.isFuture(week: week, weekday: weekday) {
            #expect(grid.tokens[week][weekday] == 0)
        }
    }
    // 0/음수 값은 칸을 만들지 않는다.
    #expect(TokenDailyGrid.build(daily: ["2026-09-03": 0, "2026-09-02": -5], now: tgNow).totalTokens == 0)
}

@Test
func tokenGridDayStringAndTooltipTextSpeakTheSameAxisAsTheServerColumn() {
    // day 문자열은 claudeDaily/codexDaily 의 키이자 서버 day 컬럼이자 조회의 since 다 — 넷이 한 축이어야 한다.
    #expect(TokenDailyGrid.dayString(tgNow) == "2026-09-03")
    // KST 자정 직후/직전(UTC 로는 전날 15시대)도 KST 날짜로 떨어진다 — UTC 로 새면 잔디가 하루씩 밀린다.
    #expect(TokenDailyGrid.dayString(tgUTC("2026-09-02T15:00:00Z")) == "2026-09-03")
    #expect(TokenDailyGrid.dayString(tgUTC("2026-09-02T14:59:59Z")) == "2026-09-02")
    #expect(TokenDailyGrid.dayString(TokenDailyGrid.date(fromDay: "2026-01-05")!) == "2026-01-05")
    #expect(TokenDailyGrid.date(fromDay: "2026-9-3") == TokenDailyGrid.date(fromDay: "2026-09-03"))
    #expect(TokenDailyGrid.date(fromDay: "2026-09") == nil)
    #expect(TokenDailyGrid.date(fromDay: "not-a-day") == nil)

    // 툴팁 값 문구: 0 은 "사용 없음", 그 외는 순위판·내 행과 같은 콤마 전체 숫자(축약 금지 — 단위가 어긋나 보인다).
    #expect(TokenDailyGrid.tooltipValueText(0) == "사용 없음")
    #expect(TokenDailyGrid.tooltipValueText(-1) == "사용 없음")
    #expect(TokenDailyGrid.tooltipValueText(12_345_678) == "12,345,678 토큰")
    // 그리드가 날짜를 앞에 붙이면 스펙의 그 문장이 된다.
    let weekStart = TokenDailyGrid.date(fromDay: "2026-08-31")!
    #expect(ContributionGridView.tooltipText(weekStart: weekStart, week: 0, weekday: 3,
                                             valueText: TokenDailyGrid.tooltipValueText(12_345_678))
        == "9월 3일 · 12,345,678 토큰")
}

// MARK: - (C) 업로드가 고를 값(순수)

@Test
func uploadValuesKeepOnlyCurrentMonthDaysAndSkipEmptyOnes() {
    // 로컬 맵에는 보관 하한(월 시작 − 48시간) 때문에 지난 달 꼬리 이틀이 남아 있다. 그 날들은 이미 그 달에 올렸고
    // 지금은 **부분값**이라 보내지 않는다 — 보내면 서버의 온전한 값을 부분값으로 덮는다.
    let values = TokenUsageDailyUpload.values(
        usage: tgUsage(claudeDaily: ["2026-09-01": 100, "2026-08-31": 50], codexDaily: ["2026-09-02": 7, "2026-08-30": 9]),
        account: tgAccount(["2026-09-01": 900, "2026-09-05": 4, "2026-08-31": 3])
    )
    #expect(Set(values.keys) == ["2026-09-01", "2026-09-02", "2026-09-05"])
    #expect(values["2026-09-01"] == TokenUsageDailyValue(claude: 100, codex: 0, codexAccount: 900))
    // 계정 버킷이 없는 날은 nil 이다(0 이 아니다) — 0 을 실으면 다른 기기가 올린 계정값을 덮는다.
    #expect(values["2026-09-02"] == TokenUsageDailyValue(claude: 0, codex: 7, codexAccount: nil))
    // 계정 버킷만 있는 날도 남긴다(`.zst` 만 남은 채 설치한 사람의 Codex 사용은 로컬 맵에 없다).
    #expect(values["2026-09-05"] == TokenUsageDailyValue(claude: 0, codex: 0, codexAccount: 4))
    // 셋 다 0/nil 인 날은 말할 것이 없어 뺀다.
    #expect(TokenUsageDailyUpload.values(usage: tgUsage(claudeDaily: ["2026-09-01": 0]), account: nil).isEmpty)
    #expect(TokenUsageDailyUpload.values(usage: tgUsage(), account: nil).isEmpty)
}

@Test
func changedDaysReturnsEverythingFirstThenOnlyWhatMoved() {
    let current = [
        "2026-09-01": TokenUsageDailyValue(claude: 100, codex: 0, codexAccount: 900),
        "2026-09-02": TokenUsageDailyValue(claude: 0, codex: 7, codexAccount: nil),
        "2026-09-03": TokenUsageDailyValue(claude: 5, codex: 5, codexAccount: nil)
    ]
    // 장부가 비어 있으면 전부(처음 업로드), 날짜 오름차순 — 본문이 결정적이라 테스트·로그가 읽기 쉽다.
    #expect(TokenUsageDailyUpload.changedDays(current: current, lastUploaded: [:]) == ["2026-09-01", "2026-09-02", "2026-09-03"])
    // 전부 같으면 하나도 없다(요청 자체가 안 나간다).
    #expect(TokenUsageDailyUpload.changedDays(current: current, lastUploaded: current).isEmpty)
    // 계정값만 달라져도 '바뀐 날'이다 — 계정 버킷은 로컬 로그와 무관하게 자란다(nil → 값 포함).
    var ledger = current
    ledger["2026-09-02"] = TokenUsageDailyValue(claude: 0, codex: 7, codexAccount: 1)
    #expect(TokenUsageDailyUpload.changedDays(current: current, lastUploaded: ledger) == ["2026-09-02"])
    // 장부에만 있는 날(달이 바뀌어 현재 범위에서 빠진 날)은 다시 보내지 않는다.
    ledger = current
    ledger["2026-08-30"] = TokenUsageDailyValue(claude: 1, codex: 1, codexAccount: nil)
    #expect(TokenUsageDailyUpload.changedDays(current: current, lastUploaded: ledger).isEmpty)

    // rows 는 넘겨받은 순서를 지키고, values 에 없는 날은 조용히 건너뛴다(크래시 없음).
    let rows = TokenUsageDailyUpload.rows(
        userID: "u", deviceID: "MAC-A", days: ["2026-09-02", "없는날", "2026-09-01"], values: current)
    #expect(rows.map(\.day) == ["2026-09-02", "2026-09-01"])
    #expect(rows.allSatisfy { $0.userId == "u" && $0.deviceId == "MAC-A" })
    #expect(rows.first?.codexAccount == nil)
    #expect(rows.last?.codexAccount == 900)
}

// MARK: - (C) 업로드/조회 HTTP 계약 (URLProtocolStub)

@MainActor
@Test
func dailyUpsertPostsAnArrayWithSnakeKeysAndOmitsCodexAccountWhenAbsent() async throws {
    let host = "v0241-daily-body"
    let store = tgStore(host: host)
    defer { tgCancelTasks(store) }

    await store.uploadTokenUsageDailyIfNeeded(
        usage: tgUsage(claudeDaily: ["2026-09-01": 100], codexDaily: ["2026-09-02": 7]),
        account: tgAccount(["2026-09-01": 900]),
        generation: store.sessionGeneration
    )

    let request = try #require(tgDailyRequests(host: host).first)
    #expect(request.httpMethod == "POST")
    // 충돌키는 PK 그대로 — 다르면 서버가 42P10 으로 거절한다(마이그레이션 단언 (2)와 짝).
    #expect(request.url?.query?.contains("on_conflict=user_id,day,device_id") == true)
    // upsert 관용구: 기존 행을 병합하고 본문은 돌려받지 않는다(수집 거부자의 0행도 성공으로 읽히도록).
    let prefer = try #require(request.value(forHTTPHeaderField: "Prefer"))
    #expect(prefer.contains("resolution=merge-duplicates"))
    #expect(prefer.contains("return=minimal"))

    let body = try #require(tgDailyBodies(host: host).first)
    #expect(body.count == 2, "본문은 배열이어야 한다(행 하나씩 보내면 왕복이 날짜 수만큼 는다)")
    let first = try #require(body.first { $0["day"] as? String == "2026-09-01" })
    #expect(first["user_id"] as? String == tgUserID)
    #expect(first["device_id"] as? String == "MAC-A")
    #expect(first["claude_total"] as? Int == 100)
    #expect(first["codex_total"] as? Int == 0)
    #expect(first["codex_account"] as? Int == 900)
    #expect(Set(first.keys) == ["user_id", "day", "device_id", "claude_total", "codex_total", "codex_account"])

    // ★ 계정 버킷이 없는 날은 **키 자체가 빠진다**. 0 을 실으면 PostgREST 가 그 컬럼을 SET 해 다른 기기가 앞서
    //   올린 계정값을 0 으로 밀어 버린다(월 표 codex_account_* 와 같은 규약).
    let second = try #require(body.first { $0["day"] as? String == "2026-09-02" })
    #expect(second["codex_account"] == nil, "codex_account 가 실렸다: \(second.keys.sorted())")
    #expect(second["codex_total"] as? Int == 7)
}

@MainActor
@Test
func dailyUpsertSendsOnlyChangedDaysAndGoesSilentWhenNothingMoved() async throws {
    let host = "v0241-daily-changed"
    let store = tgStore(host: host)
    defer { tgCancelTasks(store) }
    let first = tgUsage(claudeDaily: ["2026-09-01": 100, "2026-09-02": 200])

    await store.uploadTokenUsageDailyIfNeeded(usage: first, account: nil, generation: store.sessionGeneration)
    #expect(tgDailyBodies(host: host).count == 1)
    #expect(tgDailyBodies(host: host)[0].count == 2, "처음엔 전부 보낸다")

    // 값이 그대로면 요청 자체가 없다(빈 배열 upsert 도 30초마다 헛왕복이 될 뿐이다).
    await store.uploadTokenUsageDailyIfNeeded(usage: first, account: nil, generation: store.sessionGeneration)
    #expect(tgDailyBodies(host: host).count == 1, "안 바뀐 날을 다시 올렸다")

    // 하루만 자라면 그 하루만 나간다.
    await store.uploadTokenUsageDailyIfNeeded(
        usage: tgUsage(claudeDaily: ["2026-09-01": 100, "2026-09-02": 250]), account: nil, generation: store.sessionGeneration)
    let second = try #require(tgDailyBodies(host: host).last)
    #expect(tgDailyBodies(host: host).count == 2)
    #expect(second.count == 1)
    #expect(second.first?["day"] as? String == "2026-09-02")
    #expect(second.first?["claude_total"] as? Int == 250)

    // 서비스에 빈 배열을 직접 넘겨도 요청은 나가지 않는다(게이트는 짝으로 있다 — 스토어가 걸러도 서비스가 다시 건다).
    // PostgREST 는 빈 배열 upsert 에도 200 을 돌려주므로 이 가드가 없으면 30초마다 헛왕복이 그대로 돈다.
    let before = tgDailyRequests(host: host).count
    try await store.service.upsertTokenUsageDaily(accessToken: "access-token", rows: [])
    #expect(tgDailyRequests(host: host).count == before, "빈 배열로 요청이 나갔다")

    // 로그아웃은 장부를 비운다 — 남기면 다음 계정의 첫 업로드가 "이미 올린 날"로 읽혀 그 날들이 통째로 빠진다.
    #expect(!store.lastUploadedDaily.isEmpty)
    store.signOut()
    #expect(store.lastUploadedDaily.isEmpty)
    #expect(store.tokenDailyGrid == .empty)
}

@MainActor
@Test
func dailyUpsertIsSilentWithoutSessionOrWhenCollectionIsOptedOut() async {
    let host = "v0241-daily-gates"
    let store = tgStore(host: host)
    defer { tgCancelTasks(store) }
    let usage = tgUsage(claudeDaily: ["2026-09-01": 100])

    // 수집 거부: 서버 트리거가 어차피 버리지만, 그 사람 맥이 헛왕복을 도는 것 자체를 없앤다.
    // (게이트는 짝으로 있어야 한다 — 이 함수만 따로 불려도 새지 않게 여기서도 한 번 더 건다.)
    store.tokenUsageCollect = false
    await store.uploadTokenUsageDailyIfNeeded(usage: usage, account: nil, generation: store.sessionGeneration)
    #expect(tgDailyRequests(host: host).isEmpty)
    #expect(store.lastUploadedDaily.isEmpty, "거부 상태에서 장부가 갱신되면 수집을 켠 뒤 그 날들이 영영 안 올라간다")

    // 비로그인.
    store.tokenUsageCollect = true
    store.session = nil
    await store.uploadTokenUsageDailyIfNeeded(usage: usage, account: nil, generation: store.sessionGeneration)
    #expect(tgDailyRequests(host: host).isEmpty)

    // 올릴 날이 하나도 없어도(전부 0) 요청은 없다.
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: tgUserID)
    await store.uploadTokenUsageDailyIfNeeded(usage: tgUsage(), account: nil, generation: store.sessionGeneration)
    #expect(tgDailyRequests(host: host).isEmpty)
}

@MainActor
@Test
func dailyUpsertFollowsTheMonthlyUpsertInTheSameCycleAndUnderTheSameGates() async throws {
    // 월간 → 일별 순서가 요건이다: 일별 표가 아직 없는 서버(404)에서도 월간 업로드와 그 변경 게이트는 정상 완결돼
    // 순위판 사용량이 멈추지 않는다(일별 실패는 독립이다).
    let host = "v0241-daily-order"
    let store = tgStore(host: host)
    defer { tgCancelTasks(store) }

    await store.uploadTokenUsageIfNeeded(
        usage: tgUsage(claudeDaily: ["2026-09-01": 100]), account: tgAccount(["2026-09-01": 900]), accountStatus: .ok, now: tgNow)

    let paths = URLProtocolStub.requests(forHost: host)
        .filter { $0.httpMethod == "POST" && ($0.url?.path == tgMonthlyPath || $0.url?.path == tgDailyPath) }
        .compactMap(\.url?.path)
    let monthly = try #require(paths.firstIndex(of: tgMonthlyPath))
    let daily = try #require(paths.firstIndex(of: tgDailyPath))
    #expect(monthly < daily, "일별 upsert 가 월간보다 먼저 나갔다: \(paths)")

    // 60초 스로틀도 그대로 물려받는다 — 값이 자라도 60초 안에는 둘 다 안 나간다.
    await store.uploadTokenUsageIfNeeded(
        usage: tgUsage(claudeDaily: ["2026-09-01": 500]), account: nil, accountStatus: .ok, now: tgNow.addingTimeInterval(30))
    #expect(tgDailyBodies(host: host).count == 1)
    // 수집 거부면 월간도 일별도 나가지 않는다.
    store.tokenUsageCollect = false
    await store.uploadTokenUsageIfNeeded(
        usage: tgUsage(claudeDaily: ["2026-09-01": 900]), account: nil, accountStatus: .ok, now: tgNow.addingTimeInterval(600))
    #expect(tgDailyBodies(host: host).count == 1)
}

@MainActor
@Test
func dailyFetchAsksForMyRowsSinceTheWindowStartOrderedAndCapped() async throws {
    let host = "token-daily-two-devices"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: URLSession(configuration: .stubbed))
    let rows = try await service.fetchMyTokenDaily(accessToken: "access-token", userID: tgUserID, since: "2026-06-08")

    let request = try #require(URLProtocolStub.requests(forHost: host).first { $0.url?.path == tgDailyPath })
    #expect(request.httpMethod == "GET")
    let url = try #require(request.url)
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    #expect(value("select") == "day,device_id,claude_total,codex_total,codex_account")
    #expect(value("user_id") == "eq.\(tgUserID)")
    #expect(value("day") == "gte.2026-06-08")
    // day.desc 라 상한에 걸려 잘려도 **오래된 쪽**이 빠진다(최근 잔디가 먼저 산다). 1000 은 호스티드 max_rows 와 같다.
    #expect(value("order") == "day.desc")
    #expect(value("limit") == "1000")
    // 응답은 기기별 행 그대로 온다(합산은 클라 몫). null 계정은 nil 로 디코드된다.
    #expect(rows.count == 3)
    #expect(rows.contains { $0.deviceId == "MAC-B" && $0.codexAccount == nil })
    #expect(rows.filter { $0.codexAccount == 1_000 }.count == 2)
}

// MARK: - (C) 내 기록 로드 배선

@MainActor
@Test
func insightsLoadMergesServerAndLocalIntoTheTokenGridWithoutTouchingTheWorkGrass() async {
    // 서버 두 기기 행 + 이 맥의 로컬 맵을 날짜별 max 로 합쳐 잔디를 만든다. 근무 쪽(잔디·회고·히트맵)은 같은 로드에서
    // 그대로 계산된다 — 토큰은 **독립 실패**라 서로를 막지 않는다.
    let host = "token-daily-two-devices"
    // 이 맥의 로컬 몫: 오늘 Claude 4,242(서버엔 아직 안 올라간 값 — 업로드는 60초 게이트라 오늘 칸은 로컬이 최신이다).
    let today = TokenDailyGrid.dayString(Date())
    var local = TokenUsageMonthly(month: TokenUsageIncrementalScanner.kstMonthString(Date()))
    local.claudeDaily = [today: 4_242]
    let store = tgStore(host: host, localSnapshot: local)
    defer { tgCancelTasks(store) }

    await store.performLoadInsights()

    #expect(store.insightsLoaded)
    #expect(store.dailyGrid.weeks == WorkDailyGrid.defaultWeeks)
    #expect(store.tokenDailyGrid.weeks == WorkDailyGrid.defaultWeeks)
    #expect(store.tokenDailyGrid.weekStart == store.dailyGrid.weekStart)
    // 픽스처 MAC-A/MAC-B 의 같은 날: claude 1,500 + max(codex 합 300, 계정 1,000) = 2,500. 다른 날은 codex 300.
    // 거기에 서버가 아직 모르는 오늘의 로컬 4,242 가 max 로 얹힌다.
    #expect(store.tokenDailyGrid.totalTokens == 2_800 + 4_242, "기기 합산(claude sum · 계정 max) 또는 서버/로컬 max 가 어긋났다")
    let last = store.tokenDailyGrid.weeks - 1
    let todayIndex = store.tokenDailyGrid.days - 1 - last * WorkRhythmHeatmap.dayCount
    #expect(store.tokenDailyGrid.tokens[last][todayIndex] == 4_242, "오늘 칸에 로컬 값이 안 얹혔다")
    // 근무 잔디는 스텁 work_sessions(2시간)로 그대로 선다 — 토큰 로드가 이 값을 건드리지 않는다.
    #expect(store.dailyGrid.totalSeconds > 0)
}

@MainActor
@Test
func insightsLoadKeepsTheWorkGrassWhenTheTokenFetchFailsAndSkipsItWhenOptedOut() async {
    // (1) 서버 일별 조회가 실패해도(표 미배포·네트워크) 근무 쪽은 그대로 그려지고, 잔디는 로컬 몫만으로라도 선다.
    let host = "insights-token-fetch-fails"   // 이 호스트엔 일별 픽스처가 없어 빈 배열이 온다
    let store = tgStore(host: host)
    defer { tgCancelTasks(store) }

    await store.performLoadInsights()
    #expect(store.insightsLoaded)
    #expect(!store.insightsFailed)
    #expect(store.dailyGrid.totalSeconds > 0, "토큰 경로가 근무 잔디를 막았다")
    #expect(store.tokenDailyGrid.weeks == WorkDailyGrid.defaultWeeks)

    // (2) 수집 거부면 조회 자체를 건너뛰고 잔디는 empty 다(패널도 섹션을 숨긴다 — 서버에 행이 없고 앞으로도 안 쌓인다).
    let optedOut = tgStore(host: host)
    defer { tgCancelTasks(optedOut) }
    optedOut.tokenUsageCollect = false
    await optedOut.performLoadInsights()
    #expect(optedOut.tokenDailyGrid == .empty)
    #expect(optedOut.dailyGrid.totalSeconds > 0)
    #expect(URLProtocolStub.requests(forHost: host).filter { $0.url?.path == tgDailyPath }.count == 1,
            "수집 거부자가 일별 표를 조회했다")

    // (3) 주가 바뀌면 토큰 잔디도 근무 잔디와 함께 버린다 — 마지막 열이 '그때의 이번 주'로 굳으면 새 주 첫 화면이 거짓이 된다.
    store.insightsWeekKey = "2020-W01"
    store.discardInsightsIfWeekRolledOver()
    #expect(store.tokenDailyGrid == .empty)
    #expect(store.dailyGrid == .empty)
}

// MARK: - (D) SQL 계약 (20260903170000_token_usage_daily.sql)

private func tgRepoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(relative)
}

/// 서버 마이그레이션 계약(20260903170000): 표·PK·인덱스 · 정책 3종 · 트리거 2개(스킵 < 터치) · purge 확장 ·
/// anon 차단 · 사후 단언 · 센티널 롤백 프로브. 파일이 없으면(supabase/ 없는 체크아웃) 다른 SQL 계약 테스트와 같이 **빨강**이다 —
/// 조용히 통과하면 계약이 검사되지 않은 채 초록으로 보인다.
@Test
func migrationContractTokenUsageDaily() throws {
    let sql = try String(contentsOf: tgRepoURL("supabase/migrations/20260903170000_token_usage_daily.sql"), encoding: .utf8)

    // 표 · 컬럼 · PK · 인덱스.
    #expect(sql.contains("create table if not exists public.token_usage_device_daily ("))
    for column in ["day text not null", "device_id text not null",
                   "claude_total bigint not null default 0", "codex_total bigint not null default 0",
                   "codex_account bigint,", "updated_at timestamptz not null default now()",
                   "created_at timestamptz not null default now()"] {
        #expect(sql.contains(column), "컬럼 정의 누락: \(column)")
    }
    // codex_account 만 nullable 이다 — "미보고"와 "0을 보고함"을 구별해야 기기 간 max 가 성립한다.
    #expect(!sql.contains("codex_account bigint not null"))
    #expect(sql.contains("primary key (user_id, day, device_id)"))
    #expect(sql.contains("references auth.users(id) on delete cascade"))
    #expect(sql.contains("create index if not exists token_usage_device_daily_user_day"))
    #expect(sql.contains("(user_id, day desc)"))

    // 권한: anon 은 명시 회수(Supabase 기본 권한이 새 표를 anon 에게도 연다), authenticated 는 delete 없음.
    #expect(sql.contains("revoke all on table public.token_usage_device_daily from public, anon;"))
    #expect(sql.contains("grant select, insert, update on public.token_usage_device_daily to authenticated;"))
    #expect(!sql.contains("grant select, insert, update, delete on public.token_usage_device_daily to authenticated"))
    #expect(sql.contains("enable row level security"))

    // 정책 3종(select 가 없으면 merge-duplicates upsert 가 두 번째부터 403 이다).
    for policy in ["users insert own daily token usage", "users update own daily token usage", "users read own daily token usage"] {
        #expect(sql.contains("drop policy if exists \"\(policy)\""), "정책 멱등 drop 누락: \(policy)")
        #expect(sql.contains("create policy \"\(policy)\""), "정책 생성 누락: \(policy)")
    }
    #expect(sql.contains("using (user_id = auth.uid())"))
    #expect(sql.contains("with check (user_id = auth.uid())"))

    // 트리거 2개: 수집 거부 스킵(20260803010000 함수 재사용) + updated_at 터치. 이름 순으로 도므로 skip < touch 여야 한다.
    #expect(sql.contains("create trigger skip_token_usage_daily_when_opted_out"))
    #expect(sql.contains("execute function public.skip_token_usage_when_opted_out()"))
    #expect(sql.contains("create trigger touch_token_usage_daily_updated_at"))
    #expect("skip_token_usage_daily_when_opted_out" < "touch_token_usage_daily_updated_at")
    #expect(sql.contains("new.updated_at := now();"))

    // purge 확장: 플래그 하나로 상태가 완결돼야 한다(월 표·옛 표와 함께 일별 표도 지운다).
    #expect(sql.contains("create or replace function public.purge_token_usage_on_opt_out()"))
    #expect(sql.contains("delete from public.token_usage_device_daily where user_id = new.id;"))
    #expect(sql.contains("delete from public.token_usage_device_monthly where user_id = new.id;"))

    // 사후 단언 + 센티널 롤백 프로브.
    #expect(sql.contains("if n <> 8 then"))            // 컬럼 8개(타입 포함)
    #expect(sql.contains("if n <> 3 then"))            // 정책 3종
    #expect(sql.contains("if n <> 2 then"))            // 트리거 2개
    #expect(sql.contains("has_table_privilege('anon'"))
    #expect(sql.contains("raise exception 'TOKEN_USAGE_DAILY_PROBE_ROLLBACK';"))
    #expect(sql.contains("if sqlerrm <> 'TOKEN_USAGE_DAILY_PROBE_ROLLBACK' then raise; end if;"))
    // 읽기 RPC 는 만들지 않는다 — 남의 일별 기록이 어떤 경로로도 나가면 안 된다(자기 행은 PostgREST select 로 충분).
    #expect(!sql.contains("create or replace function public.token_usage_daily("))
    #expect(!sql.contains("to anon;"))
}

// MARK: - (D) 소스 계약

private func tgStrippingComments(_ source: String) -> String {
    var result = ""
    var inString = false, inLineComment = false, inBlockComment = false
    var previous: Character = " "
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; i += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; i += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; i += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        i += 1
    }
    return result
}

/// 배선 계약(주석 제거 후): 일별 업로드는 월간 성공 **뒤**에서 딱 한 번 불리고, 실패해도 장부를 갱신하지 않으며,
/// 조회는 잔디 창 시작(insightsWindowStart)을 since 로 쓴다. 이 셋은 값 단언만으로는 초록인 채 어긋날 수 있다.
@Test
func sourceContractDailyUploadSitsAfterTheMonthlyUpsert() throws {
    let sync = tgStrippingComments(try String(contentsOf: tgRepoURL("Sources/check/WorkTimerStoreSync.swift"), encoding: .utf8))
    #expect(sync.components(separatedBy: "await uploadTokenUsageDailyIfNeeded(").count - 1 == 1)
    // 호출은 lastUploadedUsage 갱신(= 월간 성공 확정) 뒤다.
    let ledger = try #require(sync.range(of: "lastUploadedAccountKey = accountKey"))
    let call = try #require(sync.range(of: "await uploadTokenUsageDailyIfNeeded("))
    #expect(ledger.upperBound < call.lowerBound, "일별 업로드가 월간 성공 확정보다 앞에 있다")
    // 성공에만 장부를 갈아 끼운다(실패 경로에 대입이 없다).
    let body = try #require(sync.range(of: "func uploadTokenUsageDailyIfNeeded("))
    let tail = String(sync[body.lowerBound...])
    let assign = try #require(tail.range(of: "lastUploadedDaily = current"))
    let catchStart = try #require(tail.range(of: "} catch {"))
    #expect(assign.upperBound < catchStart.lowerBound, "실패 경로에서 장부를 갱신하면 그 날들이 영영 재시도되지 않는다")

    let insights = tgStrippingComments(try String(contentsOf: tgRepoURL("Sources/check/WorkTimerStoreInsights.swift"), encoding: .utf8))
    #expect(insights.contains("since: TokenDailyGrid.dayString(since)"))
    #expect(insights.contains("service.fetchMyTokenDaily("))
    // 병합은 순수 함수로 — 스토어 안에 산식을 다시 쓰면 테스트가 보는 함수와 앱이 쓰는 산식이 갈라진다.
    #expect(insights.contains("TokenDailyMerge.merged(server: TokenDailyMerge.serverTotals(tokenRows), local: local)"))
}
