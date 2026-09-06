import Foundation
import Testing
@testable import check

// v0.2.43 — Codex 로컬 일별을 **UTC 축**으로도 묶는다(계정 우선 산식 검토 P1, 2026-09-06).
//
// 배경: 계정 버킷(`account/usage/read` dailyUsageBuckets)은 UTC 날짜 키다. 로컬 일별 맵은 KST 날짜 키였고, 산식의 꼬리
// (`day > lastDay`)와 마지막 날 차분을 **같은 문자열 키**로 견주면 KST 0~9시 몫이 전날 UTC 버킷과 겹쳐 항상 더해진다
// (운영자 5월: UTC 정렬 오차 0.1M vs KST 키 28.6M(37%); 조영서 +41% 실례). 그래서 스캐너가 이벤트 timestamp 의 UTC 날짜로도
// 델타를 쌓고(`CodexFileProgress.dayContribUTC` → `TokenUsageMonthly.codexDailyUTC`), 일별 표에 `codex_utc_total` 로 올리며,
// 규칙 호출측(내 박스·잔디 병합)은 UTC 맵을 쓴다. KST 맵(`codexDaily`)과 `todayTotal` 은 그대로다.
//
// 표시(사용자 결정): "9시 경계 하루" — 반영된 날은 계정 버킷 그대로, 날짜 라벨은 UTC 날짜 문자열을 KST 날짜로 그대로 읽는다
// (UTC 하루 = KST 오전 9시 ~ 다음날 오전 9시). 툴팁 한 줄(`TokenUsageMonthly.tokenDayAxisNote`)이 세 화면에서 같은 리터럴로 이를 밝힌다.
//
// 기준 시각은 포크 스위트와 같다(2026-07-14 12:33:20 KST → 현재 월 2026-07, UTC 보존 하한 2026-06-30).

private let uaNow = Date(timeIntervalSince1970: 1_784_000_000)

private func uaUTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = iso.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

private func uaISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

private func uaTempHome() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("check-v0243-utc-\(UUID().uuidString)", isDirectory: true)
}

private func uaWrite(_ lines: [String], to url: URL, modified: Date) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func uaCodexURL(_ home: URL, _ path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

private func uaMeta(id: String, at date: Date) -> String {
    "{\"timestamp\":\"\(uaISO(date))\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"timestamp\":\"\(uaISO(date))\","
        + "\"cwd\":\"/tmp\",\"originator\":\"test\",\"cli_version\":\"0.144.6\"}}"
}

private func uaEvent(input: Int, cached: Int = 0, output: Int = 0, at date: Date) -> String {
    "{\"timestamp\":\"\(uaISO(date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),"
    + "\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(input + output)},"
    + "\"last_token_usage\":{\"input_tokens\":0,\"cached_input_tokens\":0,\"output_tokens\":0,\"reasoning_output_tokens\":0,\"total_tokens\":0},"
    + "\"model_context_window\":258400},\"rate_limits\":null}}"
}

private func uaMicros(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1_000_000).rounded()) }

private func uaScan(_ home: URL, cache: TokenUsageCache = TokenUsageCache(), now: Date = uaNow) -> TokenUsageIncrementalScanner.Result {
    TokenUsageIncrementalScanner.update(cache, homeDirectory: home, now: now)
}

private func uaAccount(_ buckets: [String: Int]) -> CodexAccountUsage {
    CodexAccountUsage(fetchedAt: uaNow, lifetimeTokens: nil, buckets: buckets)
}

private func uaRepoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(relative)
}

/// `//`·`--` 줄 주석을 걷어낸다(하우스 규칙 — 소스 계약은 설명을 지워야 초록이 되면 안 된다).
private func uaStrippingComments(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        let trimmed = line.drop(while: { $0 == " " })
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("--") { return "" }
        return line
    }.joined(separator: "\n")
}

// MARK: - 1. 이중 누적: 같은 이벤트가 KST 맵과 UTC 맵에서 다른 날짜 키로 간다

@Test
func codexEventsAccumulateOnBothTheKSTAndUTCDayAxes() {
    let home = uaTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // KST 07-10 00:30(=UTC 07-09 15:30) 에 시작한 세션. 첫 이벤트는 기준선(델타 0).
    let t0 = uaUTC("2026-07-09T15:30:00.000Z")
    let t1 = uaUTC("2026-07-09T16:00:00.000Z")   // KST 07-10 01:00 · UTC 07-09
    let t2 = uaUTC("2026-07-10T03:00:00.000Z")   // KST 07-10 12:00 · UTC 07-10
    uaWrite(
        [uaMeta(id: "s", at: t0), uaEvent(input: 1_000, at: t0), uaEvent(input: 1_500, at: t1), uaEvent(input: 2_200, at: t2)],
        to: uaCodexURL(home, "2026/07/10/rollout-2026-07-10T00-30-00-s.jsonl"), modified: t2
    )
    let r = uaScan(home)
    #expect(r.usage.codexInput == 1_200)
    #expect(r.usage.codexDaily == ["2026-07-10": 1_200])                              // KST: 둘 다 7/10
    #expect(r.usage.codexDailyUTC == ["2026-07-09": 500, "2026-07-10": 700])          // UTC: 자정(=KST 09시) 전후로 갈린다
    // 오늘분·월 합계·KST 맵은 예전 그대로(이 변경은 맵을 하나 **더** 만들 뿐이다).
    #expect(r.usage.codexDaily.values.reduce(0, +) == r.usage.codexDailyUTC.values.reduce(0, +))
    #expect(r.usage.codexDailyUTC.values.reduce(0, +) == r.usage.codexInput)
    // 이어읽기에서도 두 맵이 같이 자란다.
    let t3 = uaUTC("2026-07-10T16:00:00.000Z")   // KST 07-11 01:00 · UTC 07-10
    let url = uaCodexURL(home, "2026/07/10/rollout-2026-07-10T00-30-00-s.jsonl")
    if let h = try? FileHandle(forWritingTo: url) {
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data((uaEvent(input: 2_300, at: t3) + "\n").utf8))
        try? h.close()
    }
    try? FileManager.default.setAttributes([.modificationDate: t3], ofItemAtPath: url.path)
    let r2 = uaScan(home, cache: r.cache)
    #expect(r2.stats.codexBytesRead < 600)   // 새 바이트만 읽었다(전체 재파싱이 아니다)
    #expect(r2.usage.codexDaily == ["2026-07-10": 1_200, "2026-07-11": 100])
    #expect(r2.usage.codexDailyUTC == ["2026-07-09": 500, "2026-07-10": 800])
}

// MARK: - 2. 영속: 13원소 튜플 왕복 + 12원소(UTC 맵 없는 같은 세대) 관용

@Test
func codexFileProgressRoundTripsTheUTCMapAsTheThirteenthElement() throws {
    var cache = TokenUsageCache()
    cache.codexFileStates["/c/rollout.jsonl"] = CodexFileProgress(
        size: 20, mtimeMicros: 111, consumedOffset: 15, prevInput: 300, prevOutput: 40, prevCached: 120,
        monthKey: "2026-07", monthInput: 250, monthOutput: 50, monthCached: 90, dayContrib: ["2026-07-14": 42],
        forkCopyDeadlineMicros: 7, dayContribUTC: ["2026-07-13": 5, "2026-06-30": 37])
    let data = try JSONEncoder().encode(cache)
    let decoded = try JSONDecoder().decode(TokenUsageCache.self, from: data)
    #expect(decoded == cache)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("[20,111,15,300,40,120,\"2026-07\",250,50,90,{\"2026-07-14\":42},7,{"))
    #expect(json.contains("\"2026-06-30\":37") && json.contains("\"2026-07-13\":5"))
    // 같은 세대(v5)의 12원소 튜플(UTC 맵 없음)은 빈 맵으로 읽힌다 — 새 형식의 잘린 튜플 방어.
    let twelve = """
    {"claudeFileStates":{},"claudeEntries":{},"codexFileStates":{"/c/rollout.jsonl":[20,111,15,300,40,120,"2026-07",250,50,90,{"2026-07-14":42},7]},\
    "codexSchemaVersion":\(TokenUsageCache.currentCodexSchemaVersion)}
    """
    let short = try JSONDecoder().decode(TokenUsageCache.self, from: Data(twelve.utf8))
    #expect(short.codexFileStates["/c/rollout.jsonl"]?.dayContribUTC == [:])
    #expect(short.codexFileStates["/c/rollout.jsonl"]?.forkCopyDeadlineMicros == 7)
}

// MARK: - 3. 월 롤오버: UTC 맵은 "UTC 일 ≥ KST 월 시작 − 1일" 키만 남기고, KST 맵처럼 통째로 비우지 않는다

@Test
func utcRetainFromKeyIsTheDayBeforeTheKSTMonthStart() {
    #expect(TokenUsageIncrementalScanner.utcRetainFromKey(monthString: "2026-07") == "2026-06-30")
    #expect(TokenUsageIncrementalScanner.utcRetainFromKey(monthString: "2026-03") == "2026-02-28")
    #expect(TokenUsageIncrementalScanner.utcRetainFromKey(monthString: "2024-03") == "2024-02-29")
    #expect(TokenUsageIncrementalScanner.utcRetainFromKey(monthString: "2026-01") == "2025-12-31")
    #expect(TokenUsageIncrementalScanner.utcRetainFromKey(monthString: "garbage") == "")
}

@Test
func rolloverKeepsThePreviousMonthsLastUTCDayInTheUTCMapOnly() {
    // (a) 무변경 파일의 월 롤오버(재키): KST 맵은 비고, UTC 맵은 보존 하한(6/30) 이상 키만 남는다.
    var cache = TokenUsageCache()
    let path = "/tmp/ua-roll/rollout.jsonl"
    cache.codexFileStates[path] = CodexFileProgress(
        size: 10, mtimeMicros: 5, consumedOffset: 10, prevInput: 900, prevOutput: 0, prevCached: 0,
        monthKey: "2026-06", monthInput: 900, monthOutput: 0, monthCached: 0, dayContrib: ["2026-06-30": 12],
        forkCopyDeadlineMicros: 0, dayContribUTC: ["2026-06-15": 5, "2026-06-30": 7])
    var stats = TokenUsageIncrementalScanner.Stats()
    TokenUsageIncrementalScanner.scanCodexFiles(
        &cache, files: [(url: URL(fileURLWithPath: path), size: 10, mtimeMicros: 5)], roots: [], monthString: "2026-07", stats: &stats
    )
    let state = cache.codexFileStates[path]
    #expect(state?.monthKey == "2026-07")
    #expect(state?.dayContrib == [:])
    #expect(state?.dayContribUTC == ["2026-06-30": 7])
    #expect(state?.prevInput == 900)   // 기준선은 파일 안에서 계속 이어진다

    // (b) 지난달에 마지막으로 쓰인 파일(이번 달 프리필터 밖)의 6/30 UTC 몫도 이번 달 UTC 맵에 **합쳐진다** — 상태 키가 지난달이어도.
    //     KST 맵·월 합계는 예전처럼 이번 달 것만이다.
    let home = uaTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let j0 = uaUTC("2026-06-15T10:00:00.000Z")   // 기준선
    let j1 = uaUTC("2026-06-15T11:00:00.000Z")   // 델타 300 → KST·UTC 6/15
    let j2 = uaUTC("2026-06-30T12:00:00.000Z")   // 델타 600 → KST 6/30 21:00 · UTC 6/30
    uaWrite(
        [uaMeta(id: "j", at: j0), uaEvent(input: 1_000, at: j0), uaEvent(input: 1_300, at: j1), uaEvent(input: 1_900, at: j2)],
        to: uaCodexURL(home, "2026/06/15/rollout-2026-06-15T19-00-00-j.jsonl"), modified: j2
    )
    let june = uaScan(home, now: uaUTC("2026-06-30T13:00:00.000Z"))
    #expect(june.usage.codexDaily == ["2026-06-15": 300, "2026-06-30": 600])
    #expect(june.usage.codexDailyUTC == ["2026-06-15": 300, "2026-06-30": 600])
    let july = uaScan(home, cache: june.cache)   // 7/14: 파일 mtime(6/30) 은 이번 달 프리필터 밖, 퇴거 경계(6/29 0시 KST) 안
    #expect(july.usage.codexInput == 0)
    #expect(july.usage.codexDaily == [:])
    #expect(july.usage.codexDailyUTC == ["2026-06-30": 600])

    // (c) 이번 달에 처음부터 파싱한 파일의 6/30 UTC 이벤트(KST 7/1 08:00)도 UTC 맵에 든다 — KST 맵은 7/1 로.
    let k0 = uaUTC("2026-06-30T22:00:00.000Z")   // 기준선 (KST 7/1 07:00)
    let k1 = uaUTC("2026-06-30T23:00:00.000Z")   // 델타 400 → KST 7/1 · UTC 6/30
    let k2 = uaUTC("2026-07-01T02:00:00.000Z")   // 델타 100 → KST 7/1 · UTC 7/1
    uaWrite(
        [uaMeta(id: "k", at: k0), uaEvent(input: 1_000, at: k0), uaEvent(input: 1_400, at: k1), uaEvent(input: 1_500, at: k2)],
        to: uaCodexURL(home, "2026/07/01/rollout-2026-07-01T07-00-00-k.jsonl"), modified: k2
    )
    let july2 = uaScan(home, cache: july.cache)
    #expect(july2.usage.codexInput == 500)
    #expect(july2.usage.codexDaily == ["2026-07-01": 500])
    #expect(july2.usage.codexDailyUTC == ["2026-06-30": 1_000, "2026-07-01": 100])
}

// MARK: - 4. 일별 업로드: 각 값은 그 맵이 **덮는 날에만** 실린다(부분값으로 서버의 완전값을 덮지 않는다)

@Test
func dailyUploadSendsEachFieldOnlyWhereItsMapIsComplete() throws {
    var usage = TokenUsageMonthly(month: "2026-07")
    usage.windowStart = "2026-04-20"
    usage.claudeDaily = ["2026-06-30": 2, "2026-07-01": 4, "2026-05-10": 6]
    usage.codexDaily = ["2026-07-01": 5]
    usage.codexDailyUTC = ["2026-06-30": 9, "2026-07-01": 3]
    let values = TokenUsageDailyUpload.values(usage: usage, account: uaAccount(["2026-07-01": 40, "2026-06-30": 8]))
    // 전월 마지막 UTC 일(6/30): Codex KST 맵은 이번 달만 덮으므로 **키 생략**, UTC 값·계정 버킷은 싣고, Claude 는 창이 덮어 완전값이면 싣는다.
    #expect(values["2026-06-30"] == TokenUsageDailyValue(claude: 2, codex: nil, codexUTC: 9, codexAccount: 8))
    #expect(values["2026-07-01"] == TokenUsageDailyValue(claude: 4, codex: 5, codexUTC: 3, codexAccount: 40))
    // 창 안이지만 이번 달 밖·UTC 하한 앞(5/10): Claude 만. Codex 두 값은 모른다(nil) — 0 으로 보내면 5월 행의 Codex 가 지워진다.
    #expect(values["2026-05-10"] == TokenUsageDailyValue(claude: 6, codex: nil, codexUTC: nil, codexAccount: nil))
    // 로그 완전성 하한이 6/30 뒤면 그 날 Claude 도 빠진다(A 의 규칙 그대로).
    usage.claudeCompleteFrom = "2026-07-01"
    let guarded = TokenUsageDailyUpload.values(usage: usage, account: nil)
    #expect(guarded["2026-06-30"] == TokenUsageDailyValue(claude: nil, codex: nil, codexUTC: 9, codexAccount: nil))
    // 셋 다 없는 날은 빠진다.
    #expect(guarded["2026-05-10"] == nil)

    // 요청 본문: 6/30 행에는 codex_total 키가 없고 codex_utc_total 은 있다. 7/1 행은 셋 다.
    let rows = TokenUsageDailyUpload.rows(userID: "u", deviceID: "MAC-A", days: ["2026-06-30", "2026-07-01", "2026-05-10"], values: values)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let bodies = try rows.map { try JSONSerialization.jsonObject(with: encoder.encode($0)) as? [String: Any] ?? [:] }
    #expect(Set(bodies[0].keys) == ["user_id", "day", "device_id", "claude_total", "codex_utc_total", "codex_account"])
    #expect(bodies[0]["codex_utc_total"] as? Int == 9)
    #expect(Set(bodies[1].keys) == ["user_id", "day", "device_id", "claude_total", "codex_total", "codex_utc_total", "codex_account"])
    #expect(Set(bodies[2].keys) == ["user_id", "day", "device_id", "claude_total"])
    // 스냅샷 Codable: UTC 맵이 왕복하고, 없는 옛 스냅샷은 빈 맵.
    let data = try JSONEncoder().encode(usage)
    #expect(try JSONDecoder().decode(TokenUsageMonthly.self, from: data) == usage)
    let legacy = try JSONDecoder().decode(TokenUsageMonthly.self, from: Data("{\"month\":\"2026-07\",\"codexDaily\":{\"2026-07-02\":1}}".utf8))
    #expect(legacy.codexDailyUTC.isEmpty)
    #expect(legacy.codexDailyOnAccountAxis == ["2026-07-02": 1])   // 첫 스캔 전 옛 스냅샷은 KST 맵으로 대신한다
}

// MARK: - 5. 규칙 호출측은 UTC 맵을 쓴다 — 검토 픽스처(ⓐ120 ⓑ150 ⓒ150 ⓓ125)와 같은 숫자

@Test
func myBoxEffectiveUsesTheUTCMapAndMatchesTheProbeFixtures() {
    var local = TokenUsageMonthly(month: "2025-01")
    local.codexInput = 150
    local.codexDaily = ["2025-01-05": 900]                                   // KST 맵은 일부러 다르게 — 쓰이면 답이 어긋난다
    local.codexDailyUTC = ["2025-01-05": 100, "2025-01-06": 30, "2025-01-07": 20]
    // ⓐ 계정 100(1/5 40 · 1/6 60, 마지막 1/6) → 100 + 꼬리 20 + max(0, 30 − 60) = 120.
    #expect(TokenUsageDisplay.codexEffective(local: local, account: uaAccount(["2025-01-05": 40, "2025-01-06": 60])) == 120)
    // ⓑ 계정 없음 → 로컬 150.
    #expect(TokenUsageDisplay.codexEffective(local: local, account: nil) == 150)
    // ⓒ 기기 합이 1/7 에 50 → 150.
    local.codexDailyUTC["2025-01-07"] = 50
    #expect(TokenUsageDisplay.codexEffective(local: local, account: uaAccount(["2025-01-05": 40, "2025-01-06": 60])) == 150)
    // ⓓ 마지막 버킷이 1/7 이고 부분값 5, 로컬 20 → 110 + max(0, 20 − 5) = 125.
    local.codexDailyUTC["2025-01-07"] = 20
    #expect(TokenUsageDisplay.codexEffective(local: local, account: uaAccount(["2025-01-05": 40, "2025-01-06": 65, "2025-01-07": 5])) == 125)
    // UTC 맵이 비어 있는 옛 스냅샷은 KST 맵으로 후퇴한다(첫 스캔이 끝나면 UTC 맵이 채워진다).
    local.codexDailyUTC = [:]
    #expect(TokenUsageDisplay.codexEffective(local: local, account: uaAccount(["2025-01-05": 40, "2025-01-06": 60])) == 100 + 0 + max(0, 0 - 60))
    #expect(local.codexDailyOnAccountAxis == ["2025-01-05": 900])
}

// MARK: - 6. 잔디 병합: 서버 행은 codex_utc_total 우선(없으면 codex_total), 로컬은 UTC 맵

@Test
func grassMergePrefersTheUTCLocalValueAndFallsBackForOldClients() {
    let rows = [
        TokenUsageDailyRow(day: "2026-09-01", deviceId: "MAC-A", claudeTotal: 0, codexTotal: 900, codexAccount: 100, codexUtcTotal: 120),
        TokenUsageDailyRow(day: "2026-09-02", deviceId: "MAC-A", claudeTotal: 0, codexTotal: 50, codexAccount: 300, codexUtcTotal: 350),
        TokenUsageDailyRow(day: "2026-09-03", deviceId: "MAC-A", claudeTotal: 0, codexTotal: 20, codexAccount: nil, codexUtcTotal: 35),
        TokenUsageDailyRow(day: "2026-09-03", deviceId: "MAC-B", claudeTotal: 0, codexTotal: 7, codexAccount: nil)   // 구클라: UTC 없음 → KST 값
    ]
    let totals = TokenDailyMerge.serverTotals(rows)
    #expect(totals["2026-09-01"] == 100)        // 반영된 날: 계정
    #expect(totals["2026-09-02"] == 350)        // 마지막 버킷 날: max(300, UTC 350) — KST 50 은 안 본다
    #expect(totals["2026-09-03"] == 35 + 7)     // 꼬리: 기기 합(UTC 우선, 없으면 KST)
    var usage = TokenUsageMonthly(month: "2026-09")
    usage.codexDaily = ["2026-09-03": 999]
    usage.codexDailyUTC = ["2026-09-02": 400, "2026-09-03": 20]
    let local = TokenDailyMerge.localTotals(usage: usage, account: uaAccount(["2026-09-01": 100, "2026-09-02": 300]))
    #expect(local["2026-09-01"] == 100)
    #expect(local["2026-09-02"] == 400)
    #expect(local["2026-09-03"] == 20)
    // 조회 select 는 새 컬럼을 읽는다(디코드는 없으면 nil).
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let old = try? decoder.decode([TokenUsageDailyRow].self, from: Data(#"[{"day":"2026-09-01","device_id":"A","claude_total":1,"codex_total":2,"codex_account":null}]"#.utf8))
    #expect(old?.first?.codexUtcTotal == nil)
}

// MARK: - 7. 툴팁: 세 화면이 같은 리터럴로 하루의 뜻을 밝힌다

@Test
func dayAxisNoteIsOneLiteralSharedByMyBoxBoardAndGrass() throws {
    #expect(TokenUsageMonthly.tokenDayAxisNote == "Codex 하루는 오전 9시 기준(계정 집계와 같은 축) · Claude 는 자정 기준")
    var usage = TokenUsageMonthly(month: "2026-09")
    usage.codexInput = 1_000
    #expect(usage.detailTooltip.hasSuffix(" · " + TokenUsageMonthly.tokenDayAxisNote))
    usage.codexInput = 0
    usage.claudeInput = 5
    #expect(!usage.detailTooltip.contains(TokenUsageMonthly.tokenDayAxisNote))   // Codex 가 없으면 말할 것이 없다
    let entry = TokenBoardEntry(
        userID: "u", name: "n", avatarURL: nil, total: 120, claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 150, codexOutput: 0, codexCacheRead: 0, codexAccountMonth: 100, codexEffectiveFromServer: 120)
    #expect(entry.detailTooltip.hasSuffix(" · " + TokenUsageMonthly.tokenDayAxisNote))
    // 소스 계약: 리터럴은 한 곳(TokenUsageMonthly)에만 있고, 순위판 툴팁·잔디 헤더가 그 상수를 부른다.
    let usageSource = uaStrippingComments(try String(contentsOf: uaRepoURL("Sources/check/CheckTokenUsage.swift"), encoding: .utf8))
    let models = uaStrippingComments(try String(contentsOf: uaRepoURL("Sources/check/SupabaseWorkModels.swift"), encoding: .utf8))
    let menu = uaStrippingComments(try String(contentsOf: uaRepoURL("Sources/check/CheckMenuView.swift"), encoding: .utf8))
    #expect(usageSource.components(separatedBy: "\"Codex 하루는 오전 9시 기준").count - 1 == 1)
    #expect(!models.contains("\"Codex 하루는 오전 9시 기준") && !menu.contains("\"Codex 하루는 오전 9시 기준"))
    #expect(models.contains("TokenUsageMonthly.tokenDayAxisNote"))
    #expect(menu.contains(".help(TokenUsageMonthly.tokenDayAxisNote)"))
}

// MARK: - 8. upsert 묶음: 키 집합이 같은 행끼리만(옵셔널이 셋이 됐다) · 순서 결정적

@MainActor
@Test
func dailyUpsertGroupsRowsByExactKeySetSoEveryBodyIsUniform() async throws {
    let host = "v0243-utc-shapes"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: URLSession(configuration: .stubbed))
    let rows = [
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-07-01", deviceId: "MAC-A", claudeTotal: 100, codexTotal: 0, codexUtcTotal: 1, codexAccount: 900),
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-07-02", deviceId: "MAC-A", claudeTotal: 0, codexTotal: 7, codexUtcTotal: 2, codexAccount: nil),
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-06-30", deviceId: "MAC-A", claudeTotal: 3, codexTotal: nil, codexUtcTotal: 9, codexAccount: 8),   // 전월 마지막 UTC 일
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-05-10", deviceId: "MAC-A", claudeTotal: 6, codexTotal: nil, codexUtcTotal: nil, codexAccount: nil),  // Claude 만
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-05-11", deviceId: "MAC-A", claudeTotal: nil, codexTotal: nil, codexUtcTotal: nil, codexAccount: 4) // 계정만
    ]
    try await service.upsertTokenUsageDaily(accessToken: "access-token", rows: rows)
    let bodies = URLProtocolStub.bodies(forHost: host)
        .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [[String: Any]] }
    #expect(bodies.count == 5, "키 모양이 다섯이면 요청도 다섯: \(bodies.count)")
    for body in bodies {
        #expect(Set(body.map { Set($0.keys) }).count == 1, "한 본문 안의 키 집합이 행마다 다르다 — 서버가 400 으로 통째 거절한다")
    }
    let all = bodies.flatMap { $0 }
    #expect(all.count == 5)
    let june30 = try #require(all.first { $0["day"] as? String == "2026-06-30" })
    #expect(Set(june30.keys) == ["user_id", "day", "device_id", "claude_total", "codex_utc_total", "codex_account"])
    // 묶음 순서는 키가 많은 쪽부터(claude·codex·utc·account 순 내림차순) — 결정적.
    #expect(bodies.map { $0.first?["day"] as? String } == ["2026-07-01", "2026-07-02", "2026-06-30", "2026-05-10", "2026-05-11"])
}
