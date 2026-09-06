import Foundation
import Testing
@testable import check

// v0.2.43 코드 리뷰(wf_cf10d462-66e)가 확정한 결함의 회귀 테스트 — 클라 쪽(E-1 · E-3 · E-4).
//
//  E-1 [P1] Claude 완전성 하한(claudeCompleteFrom)이 "가장 오래된 파일이 오늘"이면 오늘을 영구 누락했다.
//           하한은 Claude Code 정리(기본 30일)가 그 날의 더 이른 파일을 **지웠을 수 있을 때만** 세운다 — oldest 가 29일 안이면 제한 없음.
//  E-3 [P2] 첫 스캔 전 복원된 옛 스냅샷(windowStart "")이 codex_utc_total=0 을 이번 달 모든 날에 실었다 — UTC 맵은 이 빌드 산출물에서만 안다.
//  E-4 [P2] 전월 마지막 UTC 일(utcRetainFrom 당일)의 UTC 합은 재파싱 직후 구조적으로 부분값 — 그 날의 codex_utc_total 은 싣지 않는다.

private let rfNow = Date(timeIntervalSince1970: 1_784_000_000)   // 2026-07-14 01:33:20Z = KST 07-14 10:33

private func rfUTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)!
}

private func rfMicros(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1_000_000).rounded()) }

private func rfTempHome() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rf-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func rfClaudeURL(_ home: URL, _ file: String) -> URL {
    home.appendingPathComponent(".claude/projects/p/\(file)", isDirectory: false)
}

private func rfWrite(_ contents: String, to url: URL, modified: Date) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func rfClaudeLine(id: String, at date: Date, input: Int) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return "{\"type\":\"assistant\",\"timestamp\":\"\(f.string(from: date))\",\"requestId\":\"r-\(id)\","
        + "\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":1,\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0}}}"
}

private func rfScan(_ home: URL, now: Date = rfNow) -> TokenUsageIncrementalScanner.Result {
    TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now)
}

// MARK: - E-1 하한 규칙(순수 함수)

@Test
func claudeCompletenessFloorOnlyWhenCleanupCouldHaveDeletedEarlierFiles() {
    let s = TokenUsageIncrementalScanner.self
    // 파일이 없으면 제한 없음(그대로).
    #expect(s.claudeCompleteFromKey(oldestMtimeMicros: nil, now: rfNow) == "")
    // (a) 가장 오래된 파일이 오늘 → 정리가 닿을 수 없다 → 제한 없음. 종전엔 "내일"을 돌려 오늘을 영구 누락했다(리뷰 P1).
    #expect(s.claudeCompleteFromKey(oldestMtimeMicros: rfMicros(rfNow.addingTimeInterval(-3_600)), now: rfNow) == "")
    // 10일 전·28일 전도 제한 없음.
    #expect(s.claudeCompleteFromKey(oldestMtimeMicros: rfMicros(rfNow.addingTimeInterval(-10 * 86_400)), now: rfNow) == "")
    #expect(s.claudeCompleteFromKey(oldestMtimeMicros: rfMicros(rfNow.addingTimeInterval(-28 * 86_400)), now: rfNow) == "")
    // (b) 40일 전 파일이 가장 오래됨 → 그 KST 일자의 다음 날부터 온전(종전 규칙 그대로). rfNow − 40일 = 2026-06-04 01:33Z = KST 06-04 10:33.
    #expect(s.claudeCompleteFromKey(oldestMtimeMicros: rfMicros(rfNow.addingTimeInterval(-40 * 86_400)), now: rfNow) == "2026-06-05")
    // (c) 경계: 정확히 29일 전은 하한을 세우고(정리 창 안), 29일 − 1초 는 세우지 않는다.
    let edge = rfNow.addingTimeInterval(-TokenUsageIncrementalScanner.claudeCleanupFloorSeconds)
    #expect(s.claudeCompleteFromKey(oldestMtimeMicros: rfMicros(edge), now: rfNow) != "")
    #expect(s.claudeCompleteFromKey(oldestMtimeMicros: rfMicros(edge.addingTimeInterval(1)), now: rfNow) == "")
    // 하한 상수 = 29일(Claude Code 기본 정리 30일 − 1일).
    #expect(TokenUsageIncrementalScanner.claudeCleanupFloorSeconds == 29 * 86_400)
}

// MARK: - E-1 스캔 → values 를 잇는 회귀: 오늘 파일뿐인 홈에서 오늘 Claude 가 실린다

@Test
func todayOnlyClaudeHomeUploadsTodaysClaudeValue() {
    let home = rfTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // 첫 설치일(또는 30일 공백 뒤 첫 날): transcript 가 오늘 만든 파일 하나뿐이다.
    let todayEvent = rfUTC("2026-07-14T00:30:00Z")   // KST 07-14 09:30
    rfWrite(rfClaudeLine(id: "t1", at: todayEvent, input: 3_000_000) + "\n",
            to: rfClaudeURL(home, "today.jsonl"), modified: rfNow.addingTimeInterval(-600))

    let r = rfScan(home)
    #expect(r.usage.month == "2026-07")
    #expect(r.usage.claudeDaily["2026-07-14"] == 3_000_001)
    // 하한 없음 — 이 파일보다 이른 파일을 정리가 지웠을 수 없다(10분 전 파일이 가장 오래된 파일).
    #expect(r.usage.claudeCompleteFrom == "")

    // 일별 업로드에 오늘 Claude 가 실린다(종전엔 claude nil·codex 0·utc 0·버킷 nil 이라 행이 통째로 빠졌다).
    let values = TokenUsageDailyUpload.values(usage: r.usage, account: nil)
    #expect(values["2026-07-14"]?.claude == 3_000_001)
    let rows = TokenUsageDailyUpload.rows(userID: "u", deviceID: "MAC-A", days: ["2026-07-14"], values: values)
    #expect(rows.first?.claudeTotal == 3_000_001)
}

@Test
func oldTranscriptStillRaisesTheFloorButNotOntoTheObservedDay() {
    let home = rfTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // 40일 전에 마지막으로 손댄 파일(창 안) + 오늘 파일. 하한은 40일 전 파일의 KST 일자 **다음 날**(06-05)이지 오늘이 아니다.
    let old = rfNow.addingTimeInterval(-40 * 86_400)                       // 2026-06-04 01:33Z = KST 06-04
    rfWrite(rfClaudeLine(id: "o", at: old, input: 7) + "\n", to: rfClaudeURL(home, "old.jsonl"), modified: old)
    rfWrite(rfClaudeLine(id: "t", at: rfUTC("2026-07-14T00:30:00Z"), input: 5) + "\n",
            to: rfClaudeURL(home, "today.jsonl"), modified: rfNow.addingTimeInterval(-600))
    let r = rfScan(home)
    #expect(r.usage.claudeCompleteFrom == "2026-06-05")
    let values = TokenUsageDailyUpload.values(usage: r.usage, account: nil)
    #expect(values["2026-06-04"] == nil)                 // 하한 앞(부분값일 수 있음) + Claude 뿐 → 행 자체가 빠진다
    #expect(values["2026-07-14"]?.claude == 6)           // 오늘은 실린다
}

// MARK: - E-3 첫 스캔 전 옛 스냅샷은 codex_utc_total 을 싣지 않는다

@Test
func restoredLegacySnapshotOmitsUTCTotalsInsteadOfSendingZeros() throws {
    // v0.2.42 가 저장한 스냅샷: windowStart "" · codexDailyUTC 비어 있음. 스키마 5 재파싱 전 팝오버를 열면 이 값으로 업로드가 나간다.
    var legacy = TokenUsageMonthly(month: "2026-07")
    legacy.codexDaily = ["2026-07-01": 500, "2026-07-02": 700]
    legacy.claudeDaily = ["2026-07-02": 9]
    let values = TokenUsageDailyUpload.values(usage: legacy, account: nil)
    // UTC 값은 **모른다**(nil) — 0 을 실으면 서버 coalesce(codex_utc_total, codex_total) 가 0 이 되어 꼬리가 다음 업로드까지 0 이다.
    #expect(values["2026-07-01"] == TokenUsageDailyValue(claude: 0, codex: 500, codexUTC: nil, codexAccount: nil))
    #expect(values["2026-07-02"] == TokenUsageDailyValue(claude: 9, codex: 700, codexUTC: nil, codexAccount: nil))
    let rows = TokenUsageDailyUpload.rows(userID: "u", deviceID: "MAC-A", days: ["2026-07-01"], values: values)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let body = try JSONSerialization.jsonObject(with: encoder.encode(rows[0])) as? [String: Any] ?? [:]
    #expect(body["codex_utc_total"] == nil)
    #expect(Set(body.keys) == ["user_id", "day", "device_id", "claude_total", "codex_total"])

    // 이 빌드의 스캔 산출물(windowStart 채워짐)이면 UTC 값을 싣는다 — 맵에 키가 없는 이번 달 날은 0(관측된 0).
    var fresh = legacy
    fresh.windowStart = "2026-04-20"
    fresh.codexDailyUTC = ["2026-07-01": 400]
    let freshValues = TokenUsageDailyUpload.values(usage: fresh, account: nil)
    #expect(freshValues["2026-07-01"]?.codexUTC == 400)
    #expect(freshValues["2026-07-02"]?.codexUTC == 0)
}

// MARK: - E-4 전월 마지막 UTC 일의 UTC 합은 싣지 않는다

@Test
func previousMonthsLastUTCDayNeverCarriesAUTCTotal() throws {
    var usage = TokenUsageMonthly(month: "2026-07")
    usage.windowStart = "2026-04-20"
    usage.claudeDaily = ["2026-06-30": 2]
    // 재파싱 직후 6/30 키의 UTC 합은 7/1 00:00~09:00 KST 몫만 담긴 **부분값**(6월 mtime 파일은 프리필터 밖). 있어도 싣지 않는다.
    usage.codexDailyUTC = ["2026-06-30": 9, "2026-07-01": 3]
    let values = TokenUsageDailyUpload.values(usage: usage, account: uaAccountForReviewFix(["2026-06-30": 8]))
    #expect(values["2026-06-30"] == TokenUsageDailyValue(claude: 2, codex: nil, codexUTC: nil, codexAccount: 8))
    #expect(values["2026-07-01"] == TokenUsageDailyValue(claude: 0, codex: 0, codexUTC: 3, codexAccount: nil))
    // 요청 본문: 6/30 행에는 codex_utc_total 도 codex_total 도 없다(둘 다 모른다). 서버 산식은 그 날을 반영일로 보고 계정 버킷을 쓴다.
    let rows = TokenUsageDailyUpload.rows(userID: "u", deviceID: "MAC-A", days: ["2026-06-30"], values: values)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let body = try JSONSerialization.jsonObject(with: encoder.encode(rows[0])) as? [String: Any] ?? [:]
    #expect(Set(body.keys) == ["user_id", "day", "device_id", "claude_total", "codex_account"])
    // 롤오버 보존 규칙(utcRetainFromKey)은 그대로다 — 업로드 규칙과 별개(스캐너의 UTC 맵은 그 키를 계속 담는다).
    #expect(TokenUsageIncrementalScanner.utcRetainFromKey(monthString: "2026-07") == "2026-06-30")
}

private func uaAccountForReviewFix(_ buckets: [String: Int]) -> CodexAccountUsage {
    CodexAccountUsage(fetchedAt: rfNow, lifetimeTokens: 1, buckets: buckets)
}
