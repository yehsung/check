import Foundation
import Testing
@testable import check

// MARK: - 픽스처 헬퍼 (임시 홈에 jsonl 을 써서 실제 파일 순회·mtime·파싱·이어읽기 경로를 검증한다)
//
// 픽스처는 Package.swift 리소스 등록 대신, 테스트가 런타임에 임시 디렉터리로 쓰는 방식이라 번들 등록이 불필요하다.
//
// 라인 종결 규약: 실제 Claude/Codex 로그는 레코드마다 개행("\n")으로 종결된다(append-only). 증분 스캐너는
// "개행 없는 꼬리"를 아직 쓰는 중인 부분 라인으로 보고 소비하지 않으므로, 픽스처도 완결 레코드는 항상 "\n" 으로 끝낸다.

/// 스캔 기준 시각(고정). 월/타임스탬프/mtime 을 모두 이 값에서 파생해 결정적으로 만든다.
/// 실제 KST 값: 2026-07-14 12:33:20 KST → 현재 KST 월 = "2026-07".
/// 현재 월 경계: [KST 2026-07-01 00:00, KST 2026-08-01 00:00) = [UTC 2026-06-30 15:00, UTC 2026-07-31 15:00).
/// 직전 월 시작(보관 하한): KST 2026-06-01 00:00 = UTC 2026-05-31 15:00.
private let fixedNow = Date(timeIntervalSince1970: 1_784_000_000)

/// Claude timestamp 포맷(UTC, 소수초, Z). 스캐너의 앞 19자 사전식/정수 월 비교와 맞물린다.
private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
}

/// UTC ISO 문자열("2026-06-30T15:00:00Z")을 Date 로. 월 경계(KST 00:00 = UTC 15:00 전날) 테스트에 쓴다.
private func utcDate(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

/// 테스트에서 특정 시각의 ts14(YYYYMMDDHHMMSS) 를 직접 만든다 — 스캐너 내부 산식과 동일(UTC 초 정밀도).
private func ts14(_ date: Date) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let y = c.year ?? 0, mo = c.month ?? 0, d = c.day ?? 0
    let h = c.hour ?? 0, mi = c.minute ?? 0, s = c.second ?? 0
    return ((((y * 100 + mo) * 100 + d) * 100 + h) * 100 + mi) * 100 + s
}

/// 고유한 임시 홈 디렉터리 URL(아직 만들지 않음 — 파일 쓸 때 상위 폴더가 생성된다).
private func makeTempHome() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-token-\(UUID().uuidString)", isDirectory: true)
}

/// 고유한 임시 캐시 파일 URL(스토어 테스트가 실제 Application Support 를 건드리지 않게 주입).
private func makeTempCacheURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-token-cache-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("cache.json", isDirectory: false)
}

/// 파일을 쓰고(덮어씀) mtime 을 지정한다(기본 fixedNow — mtime 프리필터를 통과시킨다).
private func writeFile(_ contents: String, to url: URL, modified: Date = fixedNow) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

/// 기존 파일 끝에 이어 쓰고(append) mtime 을 지정한다 — 이어읽기(tail) 경로를 검증하기 위한 성장 모사.
private func appendFile(_ contents: String, to url: URL, modified: Date = fixedNow) {
    if let handle = try? FileHandle(forWritingTo: url) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(contents.utf8))
        try? handle.close()
    }
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func claudeURL(_ home: URL, project: String, file: String) -> URL {
    home.appendingPathComponent(".claude/projects/\(project)/\(file)", isDirectory: false)
}

private func codexURL(_ home: URL, path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

/// Claude assistant 라인 한 줄(JSON, 개행 미포함). usage 는 JSON 오브젝트 문자열로 주입해 누락/널 필드도 만들 수 있다.
private func claudeLine(id: String, requestId: String, timestamp: Date, usage: String) -> String {
    "{\"type\":\"assistant\",\"timestamp\":\"\(iso8601(timestamp))\","
    + "\"requestId\":\"\(requestId)\",\"message\":{\"id\":\"\(id)\",\"usage\":\(usage)}}"
}

/// Codex token_count 라인 한 줄(JSON, total_token_usage 포함, 개행 미포함). 이벤트-귀속 재설계 후 월/일 귀속은 파일 mtime 이
/// 아니라 이 라인의 timestamp(UTC → KST)가 정한다. 기본 timestamp 는 현재 월(하지만 오늘 아님)의 임의 시각.
private func codexTokenCountLine(
    input: Int, cached: Int, output: Int,
    timestamp: Date = fixedNow.addingTimeInterval(-3 * 86_400)
) -> String {
    "{\"timestamp\":\"\(iso8601(timestamp))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),"
    + "\"output_tokens\":\(output),\"total_tokens\":0}}}}"
}

/// "token_count" 문자열은 있으나 total_token_usage 가 없는 무효 라인(프리체크는 통과하되 채택되지 않아야 한다).
private let codexInvalidTokenCountLine =
    "{\"payload\":{\"type\":\"token_count\",\"info\":{\"rate_limits\":{}}}}"

// MARK: - Claude 파서 (전체 스캔 진입점 = 빈 캐시 증분)

@Test
func claudeDeduplicatesForkedHistoryAcrossFiles() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-5 * 86_400)   // 2026-07-09 → 현재 월
    // L1 은 두 파일(포크/이어가기)에 동일 (id, requestId) 로 복제된다 → 한 번만 집계돼야 한다.
    let l1 = claudeLine(
        id: "msg_1", requestId: "req_1", timestamp: inMonth,
        usage: "{\"input_tokens\":100,\"output_tokens\":50,\"cache_read_input_tokens\":10,\"cache_creation_input_tokens\":5}"
    )
    // L2 는 별도 (id, requestId) → 따로 집계된다.
    let l2 = claudeLine(
        id: "msg_2", requestId: "req_2", timestamp: inMonth,
        usage: "{\"input_tokens\":200,\"output_tokens\":100,\"cache_read_input_tokens\":20,\"cache_creation_input_tokens\":10}"
    )
    writeFile("\(l1)\n", to: claudeURL(home, project: "a", file: "sessionA.jsonl"))
    writeFile("\(l1)\n\(l2)\n", to: claudeURL(home, project: "b", file: "sessionB.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    // 중복 제거가 없으면 input 은 400(=100+100+200). dedupe 로 300 이어야 한다.
    #expect(usage.claudeInput == 300)
    #expect(usage.claudeOutput == 150)
    #expect(usage.claudeCacheRead == 30)
    #expect(usage.claudeCacheCreation == 15)
    #expect(usage.claudeTotal == 495)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeSameMessageIDDifferentRequestIDCountsSeparately() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-1 * 86_400)   // 2026-07-13 → 현재 월
    // 같은 message.id 라도 requestId 가 다르면 다른 요청이므로 각각 집계한다((id, requestId) 쌍 키).
    let a = claudeLine(id: "msg_x", requestId: "req_a", timestamp: inMonth, usage: "{\"input_tokens\":100}")
    let b = claudeLine(id: "msg_x", requestId: "req_b", timestamp: inMonth, usage: "{\"input_tokens\":100}")
    writeFile("\(a)\n\(b)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.claudeInput == 200)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeAdoptsMaxOutputAmongStreamingSnapshotsInSameFile() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)   // 현재 월
    // 같은 (id, requestId)의 스트리밍 진행 스냅샷 3줄 — output_tokens 가 점증([2,2,688]).
    // "첫값 채택"이면 2, 올바른 max-output 채택이면 688. 교체 레코드(최종 스냅샷)의 input/cache 도 함께 채택된다.
    let s1 = claudeLine(id: "msg_s", requestId: "req_s", timestamp: inMonth,
        usage: "{\"input_tokens\":10,\"output_tokens\":2,\"cache_read_input_tokens\":1,\"cache_creation_input_tokens\":3}")
    let s2 = claudeLine(id: "msg_s", requestId: "req_s", timestamp: inMonth,
        usage: "{\"input_tokens\":10,\"output_tokens\":2,\"cache_read_input_tokens\":1,\"cache_creation_input_tokens\":3}")
    let s3 = claudeLine(id: "msg_s", requestId: "req_s", timestamp: inMonth,
        usage: "{\"input_tokens\":11,\"output_tokens\":688,\"cache_read_input_tokens\":4,\"cache_creation_input_tokens\":9}")
    writeFile("\(s1)\n\(s2)\n\(s3)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.claudeOutput == 688)        // 최대 output 채택(첫값 2 아님)
    #expect(usage.claudeInput == 11)          // 교체 레코드(최종 스냅샷)의 input
    #expect(usage.claudeCacheRead == 4)       // 함께 교체
    #expect(usage.claudeCacheCreation == 9)   // 함께 교체
    try? FileManager.default.removeItem(at: home)
}

// FIX: reverse-straddle(월 경계 버전) — 같은 (id, requestId) 키에 '지난달의 옛 큰-output' 라인과 '이번달의 작은 output'
// 라인이 섞여 있을 때. max-output 이 이긴 레코드의 ts(지난달)로 월을 판정하면 키가 통째로 탈락(과소집계)한다. 월 판정 ts 를
// '관측 최대 ts'로 유지하면, 이번달 라인이 하나라도 있으면 그 키(최대 output)가 현재 월 합계에 남는다. 입력 순서와 무관하게 결정적.
@Test
func claudeReverseStraddleCountsKeyByMaxObservedTimestamp() {
    let prevMonth = fixedNow.addingTimeInterval(-20 * 86_400)  // 2026-06-24 → 지난달(보관 안, 합계 밖)
    let inMonth = fixedNow.addingTimeInterval(-5 * 86_400)     // 2026-07-09 → 현재 월
    let big = claudeLine(id: "msg_r", requestId: "req_r", timestamp: prevMonth,
        usage: "{\"input_tokens\":7,\"output_tokens\":100}")   // 지난달·큰 output.
    let small = claudeLine(id: "msg_r", requestId: "req_r", timestamp: inMonth,
        usage: "{\"input_tokens\":3,\"output_tokens\":50}")    // 이번달·작은 output.

    // 두 입력 순서 모두 같은 결과여야 한다(max(output)·max(ts) 라 결정적).
    for (order, lines) in [("big-first", "\(big)\n\(small)\n"), ("small-first", "\(small)\n\(big)\n")] {
        let home = makeTempHome()
        writeFile(lines, to: claudeURL(home, project: "p", file: "s.jsonl"))
        let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)
        // 관측 최대 ts(이번달)로 월 판정 → 키 유지. 값은 max-output 레코드(output=100/input=7).
        #expect(usage.claudeOutput == 100, "\(order): 지난달 큰-output 이 이번달 키를 탈락시키면 안 됨")
        #expect(usage.claudeInput == 7, "\(order): max-output 레코드의 input 채택")
        try? FileManager.default.removeItem(at: home)
    }
}

@Test
func claudeForkReplicationOfFinalSnapshotCountsOnce() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)   // 현재 월
    // 포크 복제: 두 파일에 같은 (id, requestId) 최종 스냅샷(output=688)이 그대로 복사된다 → 1회만 집계(불변).
    let line = claudeLine(id: "msg_f", requestId: "req_f", timestamp: inMonth,
        usage: "{\"input_tokens\":11,\"output_tokens\":688,\"cache_read_input_tokens\":4,\"cache_creation_input_tokens\":9}")
    writeFile("\(line)\n", to: claudeURL(home, project: "a", file: "s.jsonl"))
    writeFile("\(line)\n", to: claudeURL(home, project: "b", file: "s.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.claudeOutput == 688)        // 1376 아님 — 같은 값이라 max 채택도 1회 집계 불변
    #expect(usage.claudeInput == 11)
    #expect(usage.claudeCacheRead == 4)
    #expect(usage.claudeCacheCreation == 9)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeExcludesLinesOutsideCurrentMonth() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-5 * 86_400)     // 2026-07-09 → 현재 월
    let prevMonth = fixedNow.addingTimeInterval(-40 * 86_400)  // 2026-06-04 → 지난달(합계 제외)
    let keep = claudeLine(id: "in", requestId: "in", timestamp: inMonth, usage: "{\"input_tokens\":1000}")
    let drop = claudeLine(id: "out", requestId: "out", timestamp: prevMonth, usage: "{\"input_tokens\":999999}")
    // 파일 mtime 은 fixedNow 라 프리필터는 통과 — 지난달 라인은 timestamp(월 귀속)로만 걸러진다.
    writeFile("\(keep)\n\(drop)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.claudeInput == 1000)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeAttributesKSTMonthByBoundaryAtUTC1500() {
    let home = makeTempHome()
    // KST 월 경계: KST 2026-07-01 00:00 == UTC 2026-06-30 15:00. 이 순간(이상)은 7월, 1초 전은 6월이어야 한다.
    let boundaryIn = utcDate("2026-06-30T15:00:00Z")   // = KST 07-01 00:00:00 → 현재 월(포함)
    let boundaryOut = utcDate("2026-06-30T14:59:59Z")  // = KST 06-30 23:59:59 → 지난달(제외)
    let keep = claudeLine(id: "bin", requestId: "bin", timestamp: boundaryIn, usage: "{\"input_tokens\":500}")
    let drop = claudeLine(id: "bout", requestId: "bout", timestamp: boundaryOut, usage: "{\"input_tokens\":700}")
    writeFile("\(keep)\n\(drop)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    // 경계 정각(하한 포함)만 7월로 계상되고, 1초 전은 6월이라 제외된다.
    #expect(usage.claudeInput == 500)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeTreatsMissingAndNullUsageFieldsAsZero() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-2 * 86_400)   // 현재 월
    // output_tokens 누락, cache_read 는 null, cache_creation 누락 → 전부 0 으로 처리되어야 한다.
    let line = claudeLine(
        id: "m", requestId: "r", timestamp: inMonth,
        usage: "{\"input_tokens\":100,\"cache_read_input_tokens\":null}"
    )
    writeFile("\(line)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.claudeInput == 100)
    #expect(usage.claudeOutput == 0)
    #expect(usage.claudeCacheRead == 0)
    #expect(usage.claudeCacheCreation == 0)
    try? FileManager.default.removeItem(at: home)
}

@Test
func mtimePrefilterSkipsFilesUntouchedSinceMonthStart() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-5 * 86_400)
    // 라인 timestamp 는 현재 월이지만 파일 mtime 이 현재 월 시작 이전(지난달, 40일 전)이라 파일 통째로 스킵되어야 한다.
    let line = claudeLine(id: "m", requestId: "r", timestamp: inMonth, usage: "{\"input_tokens\":777}")
    writeFile("\(line)\n", to: claudeURL(home, project: "p", file: "old.jsonl"),
              modified: fixedNow.addingTimeInterval(-40 * 86_400))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.total == 0)
    try? FileManager.default.removeItem(at: home)
}

// MARK: - Codex 파서 (token_count 이벤트 timestamp 의 KST 월/일로 delta 귀속)

@Test
func codexSumsEventDeltasAcrossFilesAndAbsorbsInvalidLine() {
    let home = makeTempHome()
    // 파일1: token_count 여러 줄. cum=input+output. delta = max(0, cum − 직전누적). 마지막 줄은 total_token_usage 없는
    // 무효 라인이라 건너뛰고 직전 유효 누적(prevCumulative)을 갱신하지 않는다 → 다음 유효 이벤트가 있으면 흡수(여기선 없음).
    // 이벤트1 cum=520 delta 520, 이벤트2 cum=1050 delta 530 → 파일1 = 1050(=최종 누적, 단조라 델타합=최종).
    let file1 = [
        codexTokenCountLine(input: 500, cached: 400, output: 20),
        codexTokenCountLine(input: 1000, cached: 800, output: 50),
        codexInvalidTokenCountLine
    ].joined(separator: "\n")
    // 파일2: 다른 세션. cum=205 delta 205. 둘 다 현재 월(기본 timestamp)이라 합산된다.
    let file2 = codexTokenCountLine(input: 200, cached: 100, output: 5)
    writeFile("\(file1)\n", to: codexURL(home, path: "2026/07/01/rollout-2026-07-01T00-00-00-aaaa.jsonl"))
    writeFile("\(file2)\n", to: codexURL(home, path: "2026/07/02/rollout-2026-07-02T00-00-00-bbbb.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.codexInput == 1255)   // 1050 + 205 (이벤트 delta 합, 입력+출력 합산)
    #expect(usage.codexOutput == 0)     // 이벤트-귀속 델타는 입출력을 합쳐 codexInput 에 담는다
    #expect(usage.codexTotal == 1255)   // 조합 총합은 옛 mtime 방식과 동일
    try? FileManager.default.removeItem(at: home)
}

@Test
func codexSkipsFilesUntouchedSinceMonthStart() {
    let home = makeTempHome()
    // mtime 이 지난달 이전(45일 전 = 2026-05-30)이라 현재 월 프리필터에서 스킵된다.
    let line = codexTokenCountLine(input: 9999, cached: 0, output: 1)
    writeFile("\(line)\n", to: codexURL(home, path: "2026/05/01/rollout-2026-05-01T00-00-00-cccc.jsonl"),
              modified: fixedNow.addingTimeInterval(-45 * 86_400))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.total == 0)
    try? FileManager.default.removeItem(at: home)
}

@Test
func codexFileInPreviousMonthIsNotCountedInCurrentMonth() {
    let home = makeTempHome()
    // mtime 이 지난달(현재 월 시작 이전)인 codex 파일은 프리필터에서 아예 열리지 않는다.
    // -20일(2026-06-24)은 지난달이라 프리필터(현재 월 시작=UTC 06-30 15:00)에서 스킵된다. 이벤트도 6월이라 이중 안전.
    let line = codexTokenCountLine(input: 5000, cached: 0, output: 100, timestamp: utcDate("2026-06-20T00:00:00Z"))
    writeFile("\(line)\n", to: codexURL(home, path: "2026/06/24/rollout-2026-06-24T00-00-00-dddd.jsonl"),
              modified: fixedNow.addingTimeInterval(-20 * 86_400))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.codexTotal == 0)
    try? FileManager.default.removeItem(at: home)
}

// MARK: - 오늘(KST 자정 이후) 증가량 (todayTotal / todayDate)

@Test
func todayFilterCountsOnlyKSTTodayEntriesForClaude() {
    let home = makeTempHome()
    // fixedNow = 2026-07-14 12:33:20 KST. 오늘 = [UTC 07-13 15:00, UTC 07-14 15:00). 어제(07-13) 엔트리는 월 합계엔 들되 오늘엔 제외.
    let todayLine = claudeLine(id: "t", requestId: "t", timestamp: fixedNow,
        usage: "{\"input_tokens\":100,\"output_tokens\":50,\"cache_read_input_tokens\":10,\"cache_creation_input_tokens\":5}")
    let yesterday = fixedNow.addingTimeInterval(-86_400)   // 2026-07-13 → 어제(같은 달)
    let yesterdayLine = claudeLine(id: "y", requestId: "y", timestamp: yesterday, usage: "{\"input_tokens\":999}")
    writeFile("\(todayLine)\n\(yesterdayLine)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.todayDate == "2026-07-14")
    #expect(usage.todayTotal == 165)     // 오늘 엔트리 4필드 합(100+50+10+5), 어제 999 제외
    #expect(usage.claudeInput == 1099)   // 월 합계엔 어제도 포함(100+999)
    try? FileManager.default.removeItem(at: home)
}

@Test
func todayFilterBoundaryAtKSTMidnightUTC1500() {
    let home = makeTempHome()
    // 오늘 경계: KST 07-14 00:00 == UTC 07-13 15:00. 이 순간(이상)은 오늘, 1초 전은 어제여야 한다.
    let boundaryIn = utcDate("2026-07-13T15:00:00Z")    // = KST 07-14 00:00 → 오늘(포함)
    let boundaryOut = utcDate("2026-07-13T14:59:59Z")   // = KST 07-13 23:59:59 → 어제(제외)
    let keep = claudeLine(id: "in", requestId: "in", timestamp: boundaryIn, usage: "{\"input_tokens\":500}")
    let drop = claudeLine(id: "out", requestId: "out", timestamp: boundaryOut, usage: "{\"input_tokens\":700}")
    writeFile("\(keep)\n\(drop)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.todayTotal == 500)   // 경계 정각만 오늘, 1초 전은 어제라 제외
    try? FileManager.default.removeItem(at: home)
}

// (a·핵심 결함 근절) resume 세션: 어제까지 누적 5000, 오늘 8000 으로 성장. 두 이벤트가 한 파일에 섞여 있어도
// 오늘분은 오늘 이벤트 delta(3000)만 — 어제 누적 5000 은 오늘로 새지 않는다(옛 mtime 통째 귀속의 +수십억 이상치 근절).
@Test
func codexAttributesTodayByEventTimestampNotSessionCumulative() {
    let home = makeTempHome()
    let yesterdayEvt = utcDate("2026-07-13T06:00:00Z")   // KST 2026-07-13 15:00 → 어제(현재 월)
    let todayEvt = utcDate("2026-07-14T02:00:00Z")       // KST 2026-07-14 11:00 → 오늘
    let lines = [
        codexTokenCountLine(input: 5000, cached: 0, output: 0, timestamp: yesterdayEvt),  // cum 5000, delta 5000 (어제)
        codexTokenCountLine(input: 8000, cached: 0, output: 0, timestamp: todayEvt)        // cum 8000, delta 3000 (오늘)
    ].joined(separator: "\n")
    // mtime=fixedNow(프리필터 통과). 파일에 어제·오늘 이벤트가 섞여 있다.
    writeFile("\(lines)\n", to: codexURL(home, path: "2026/07/13/rollout-2026-07-13T00-00-00-aaaa.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.todayDate == "2026-07-14")
    #expect(usage.todayTotal == 3000)   // 오늘 이벤트 delta(8000-5000)만 — 어제 누적 5000 은 오늘에 안 샌다
    #expect(usage.codexInput == 8000)   // 월 집계 = 어제(5000)+오늘(3000) delta 합
    #expect(usage.codexOutput == 0)
    #expect(usage.codexTotal == 8000)
    try? FileManager.default.removeItem(at: home)
}

// (b) 오늘 일 경계: KST 07-14 00:00 == UTC 07-13 15:00. 경계 정각(이상) 이벤트는 오늘, 1초 전은 어제.
@Test
func codexTodayBoundaryAtKSTMidnightUTC1500() {
    let home = makeTempHome()
    let boundaryIn = utcDate("2026-07-13T15:00:00Z")    // = KST 07-14 00:00 → 오늘(포함)
    let boundaryOut = utcDate("2026-07-13T14:59:59Z")   // = KST 07-13 23:59:59 → 어제(제외)
    // 어제 이벤트 cum 700 → delta 700(월엔 들되 오늘 아님). 경계 정각 이벤트 cum 1200 → delta 500(오늘).
    let lines = [
        codexTokenCountLine(input: 700, cached: 0, output: 0, timestamp: boundaryOut),
        codexTokenCountLine(input: 1200, cached: 0, output: 0, timestamp: boundaryIn)
    ].joined(separator: "\n")
    writeFile("\(lines)\n", to: codexURL(home, path: "2026/07/13/rollout-2026-07-13T00-00-00-bbbb.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.todayTotal == 500)    // 경계 정각 delta 만 오늘, 1초 전(700)은 어제라 제외
    #expect(usage.codexInput == 1200)   // 월 집계엔 둘 다(700+500)
    try? FileManager.default.removeItem(at: home)
}

// (a) 월 경계: 한 파일에 6월 말 이벤트 + 7월 이벤트가 섞여 있어도 현재 월(7월) delta 만 집계된다.
// (6월 이벤트도 prevCumulative 는 갱신하므로 7월 delta 가 6월분만큼 부풀지 않는다.)
@Test
func codexMonthBoundaryCountsOnlyCurrentMonthEventDeltas() {
    let home = makeTempHome()
    let juneEvt = utcDate("2026-06-30T14:00:00Z")       // KST 06-30 23:00 → 6월(현재 월 밖)
    let julyBoundary = utcDate("2026-06-30T15:00:00Z")  // KST 07-01 00:00 → 7월(경계 포함)
    let julyEvt = utcDate("2026-07-05T00:00:00Z")       // KST 07-05 09:00 → 7월
    let lines = [
        codexTokenCountLine(input: 1000, cached: 0, output: 0, timestamp: juneEvt),      // cum 1000, delta 1000 (6월 → 제외)
        codexTokenCountLine(input: 3000, cached: 0, output: 0, timestamp: julyBoundary), // cum 3000, delta 2000 (7월)
        codexTokenCountLine(input: 5000, cached: 0, output: 0, timestamp: julyEvt)       // cum 5000, delta 2000 (7월)
    ].joined(separator: "\n")
    // mtime=fixedNow(7월)이라 프리필터 통과.
    writeFile("\(lines)\n", to: codexURL(home, path: "2026/06/30/rollout-2026-06-30T00-00-00-ffff.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.codexInput == 4000)   // 7월 delta 합(2000+2000), 6월 1000 제외
    #expect(usage.codexTotal == 4000)
    try? FileManager.default.removeItem(at: home)
}

// (c) info null / timestamp 결손 이벤트는 건너뛰되 prevCumulative 를 갱신하지 않아, 다음 유효 이벤트의 delta 에 흡수된다(유실 없음).
@Test
func codexAbsorbsSkippedEventsIntoNextValidDelta() {
    let home = makeTempHome()
    let evt = utcDate("2026-07-05T00:00:00Z")   // 7월(현재 월), 오늘 아님
    // 이벤트1 cum 1000 delta 1000. 중간에 total_token_usage 없는 무효 라인(건너뜀, prevCumulative 유지 1000).
    // 이벤트2 cum 3000 → delta 2000(건너뛴 중간분까지 흡수). timestamp 없는 라인도 하나 끼워 건너뜀을 검증.
    let noTimestamp = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
        + "\"info\":{\"total_token_usage\":{\"input_tokens\":9999,\"cached_input_tokens\":0,\"output_tokens\":0,\"total_tokens\":0}}}}"
    let lines = [
        codexTokenCountLine(input: 1000, cached: 0, output: 0, timestamp: evt),
        codexInvalidTokenCountLine,   // info 에 total_token_usage 없음 → 건너뜀
        noTimestamp,                  // total 은 있으나 timestamp 결손 → 건너뜀(prevCumulative 불변)
        codexTokenCountLine(input: 3000, cached: 0, output: 0, timestamp: evt)
    ].joined(separator: "\n")
    writeFile("\(lines)\n", to: codexURL(home, path: "2026/07/05/rollout-2026-07-05T00-00-00-cccc.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.codexInput == 3000)   // 1000 + 2000(흡수) — 건너뛴 이벤트로 토큰 유실 없음
    #expect(usage.codexTotal == 3000)
    try? FileManager.default.removeItem(at: home)
}

// (d) 누적이 줄어드는 리셋 이벤트는 delta 를 max(0,…) 로 클램프한다(음수 델타 없음).
@Test
func codexClampsCumulativeResetToZeroDelta() {
    let home = makeTempHome()
    let evt = utcDate("2026-07-05T00:00:00Z")   // 7월
    let lines = [
        codexTokenCountLine(input: 5000, cached: 0, output: 0, timestamp: evt),  // cum 5000, delta 5000
        codexTokenCountLine(input: 3000, cached: 0, output: 0, timestamp: evt),  // cum 3000(리셋), delta max(0,-2000)=0
        codexTokenCountLine(input: 4000, cached: 0, output: 0, timestamp: evt)   // cum 4000, delta 1000
    ].joined(separator: "\n")
    writeFile("\(lines)\n", to: codexURL(home, path: "2026/07/05/rollout-2026-07-05T00-00-00-dddd.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.codexInput == 6000)   // 5000 + 0(클램프) + 1000 — 리셋이 음수로 깎지 않음
    try? FileManager.default.removeItem(at: home)
}

// (b·자정 넘김) 무변경 파일에서 날이 바뀌면 재읽기 없이 dayContribTotal 을 0 리셋하고 dayKey 를 오늘로 갱신한다.
// 월(monthKey)은 그대로라 월 집계는 유지된다. 어제 누적이 오늘로 새지 않는다.
@Test
func codexDayRolloverResetsDayContribOnUnchangedFile() {
    let home = makeTempHome()
    let yesterdayEvt = utcDate("2026-07-13T06:00:00Z")   // KST 07-13 15:00
    let yScanNow = utcDate("2026-07-13T12:00:00Z")       // 어제 스캔 시각(KST 07-13 21:00) → 그날이 "오늘"
    let url = codexURL(home, path: "2026/07/13/rollout-2026-07-13T00-00-00-dddd.jsonl")

    // 어제 스캔: 이벤트 일키(07-13)==그날 오늘 → dayContrib=5000, dayKey=07-13.
    writeFile("\(codexTokenCountLine(input: 5000, cached: 0, output: 0, timestamp: yesterdayEvt))\n",
              to: url, modified: yScanNow)
    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: yScanNow)
    #expect(r1.usage.todayDate == "2026-07-13")
    #expect(r1.usage.todayTotal == 5000)
    #expect(r1.cache.codexFileStates.values.first?.dayKey == "2026-07-13")

    // 자정 넘김: 파일 무변경(크기·mtime 불변). now=오늘(fixedNow) 재스캔 → 재읽기 0, dayContrib 0 리셋, dayKey=오늘.
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)

    #expect(r2.stats.codexBytesRead == 0)   // 무변경 파일 — 재읽기 0
    #expect(r2.stats.cacheChanged == true)  // 일 롤오버 리셋은 캐시 변경(저장 유도)
    #expect(r2.cache.codexFileStates.values.first?.dayKey == "2026-07-14")
    #expect(r2.cache.codexFileStates.values.first?.dayContribTotal == 0)
    #expect(r2.usage.todayTotal == 0)       // 어제 누적 5000 이 오늘로 새지 않음
    #expect(r2.usage.codexInput == 5000)    // 월(7월) 집계는 유지(monthKey 그대로 7월)
    try? FileManager.default.removeItem(at: home)
}

@Test
func todayTotalCombinesClaudeAndCodexForToday() {
    let home = makeTempHome()
    // 오늘 Claude 엔트리 + 오늘 Codex 이벤트가 함께 todayTotal 에 합산된다(month 부분집합). 둘 다 이벤트 timestamp 로 오늘 귀속.
    let today = utcDate("2026-07-14T02:00:00Z")   // KST 07-14 11:00
    let claudeToday = claudeLine(id: "c", requestId: "c", timestamp: today,
        usage: "{\"input_tokens\":10,\"output_tokens\":20,\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0}")
    writeFile("\(claudeToday)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))
    writeFile("\(codexTokenCountLine(input: 3, cached: 1, output: 4, timestamp: today))\n",
              to: codexURL(home, path: "2026/07/14/rollout-today.jsonl"))

    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(usage.todayTotal == 37)   // Claude(10+20) + Codex delta(3+4)
    try? FileManager.default.removeItem(at: home)
}

// MARK: - 소스 결합/부재

@Test
func scanReturnsZeroWhenNoLogDirectoriesExist() {
    // 홈에 .claude/.codex 가 아예 없으면(로그 부재) 전부 0 — 뷰는 이 경우 아무것도 그리지 않는다.
    let home = makeTempHome()
    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)
    #expect(usage.total == 0)
    #expect(usage.claudeTotal == 0)
    #expect(usage.codexTotal == 0)
    // 월은 로그 유무와 무관하게 현재 KST 월로 태깅된다.
    #expect(usage.month == "2026-07")
}

// MARK: - 증분 스캔 (이어읽기 · 무변경 스킵 · 축소 폴백 · 퇴거 · 부분라인 · dedupe 유지)

@Test
func tailReadsOnlyNewlyAppendedBytesAndAdvancesOffset() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)
    let l1 = claudeLine(id: "a", requestId: "a", timestamp: inMonth, usage: "{\"input_tokens\":100}") + "\n"
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(l1, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.usage.claudeInput == 100)
    // 파일이 하나뿐이라 .values.first 로 그 상태를 본다(경로 키는 FS 심볼릭 정규화로 테스트 url.path 와 다를 수 있음).
    #expect(r1.cache.claudeFileStates.values.first?.consumedOffset == l1.utf8.count)

    // 라인 하나 append(파일 성장) → 재갱신은 consumedOffset 이후 "새 바이트"만 읽는다.
    let l2 = claudeLine(id: "b", requestId: "b", timestamp: inMonth, usage: "{\"input_tokens\":200}") + "\n"
    appendFile(l2, to: url, modified: fixedNow.addingTimeInterval(1))

    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.claudeBytesRead == l2.utf8.count)          // 새로 붙은 바이트만
    #expect(r2.usage.claudeInput == 300)                        // 100 + 200
    #expect(r2.cache.claudeFileStates.values.first?.consumedOffset == l1.utf8.count + l2.utf8.count)
    try? FileManager.default.removeItem(at: home)
}

@Test
func unchangedFileIsNotReReadOnSecondUpdate() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)
    let line = claudeLine(id: "m", requestId: "r", timestamp: inMonth, usage: "{\"input_tokens\":100}") + "\n"
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(line, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.usage.claudeInput == 100)
    #expect(r1.stats.claudeBytesRead > 0)
    #expect(r1.stats.cacheChanged == true)

    // 파일을 건드리지 않고 재갱신 → 크기·mtime 동일이라 재읽기 0, 캐시 무변경(저장 스킵).
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.claudeBytesRead == 0)
    #expect(r2.stats.claudeFilesRead == 0)
    #expect(r2.stats.cacheChanged == false)
    #expect(r2.usage == r1.usage)
    try? FileManager.default.removeItem(at: home)
}

@Test
func partialLineIsNotConsumedUntilNewlineArrives() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)
    let l1 = claudeLine(id: "a", requestId: "a", timestamp: inMonth, usage: "{\"input_tokens\":100}") + "\n"
    let l2 = claudeLine(id: "b", requestId: "b", timestamp: inMonth, usage: "{\"input_tokens\":200}") // 개행 없음
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(l1 + l2, to: url)  // l2 는 아직 쓰는 중인 부분 라인(개행 미도착)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.usage.claudeInput == 100)                                           // l2(부분)는 미소비
    #expect(r1.cache.claudeFileStates.values.first?.consumedOffset == l1.utf8.count) // l1 끝에서 멈춤

    // 개행이 붙어 l2 완성 → 다음 갱신에서 완성분만 반영(이어읽기는 consumedOffset 부터 = l2 + 개행).
    appendFile("\n", to: url, modified: fixedNow.addingTimeInterval(1))
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.usage.claudeInput == 300)                                         // 이제 l2 계상
    #expect(r2.stats.claudeBytesRead == (l2 + "\n").utf8.count)                  // 부분+새 개행만 재읽기
    #expect(r2.cache.claudeFileStates.values.first?.consumedOffset == (l1 + l2 + "\n").utf8.count)
    try? FileManager.default.removeItem(at: home)
}

@Test
func shrunkFileTriggersFullReparseFallback() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)
    let l1 = claudeLine(id: "m1", requestId: "r1", timestamp: inMonth, usage: "{\"input_tokens\":100}") + "\n"
    let l2 = claudeLine(id: "m2", requestId: "r2", timestamp: inMonth, usage: "{\"input_tokens\":200}") + "\n"
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(l1 + l2, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.usage.claudeInput == 300)

    // 파일을 더 작은 내용으로 덮어쓴다(로테이션/절단 모사) — size 축소 → 전체 재파싱 폴백.
    let l3 = claudeLine(id: "m3", requestId: "r3", timestamp: inMonth, usage: "{\"input_tokens\":50}") + "\n"
    writeFile(l3, to: url)

    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    // 처음부터 다시 읽어 l3 를 계상하고 오프셋을 새 끝으로 리셋(테일이 아니라 전체 재읽기).
    #expect(r2.cache.claudeEntries["m3\u{0}r3"]?.input == 50)
    #expect(r2.stats.claudeBytesRead == l3.utf8.count)
    #expect(r2.cache.claudeFileStates.values.first?.consumedOffset == l3.utf8.count)
    // 설계상 허용: 사라진 라인(l1, l2)의 엔트리는 맵에 잔류할 수 있다(주석 명시). 재파싱 자체는 정상 수행됨을 위에서 확인.
    #expect(r2.cache.claudeEntries["m1\u{0}r1"] != nil)
    try? FileManager.default.removeItem(at: home)
}

@Test
func evictsEntriesBeforePreviousMonth() {
    // 현재 월 합계와 보관(직전 월까지)/퇴거(직전 월 이전)를 분리 검증한다:
    // 지난달(6월) 엔트리는 보관되나 합계 제외, 전전월(5월) 엔트리는 퇴거.
    var cache = TokenUsageCache()
    cache.claudeEntries["fresh\u{0}fresh"] = ClaudeEntry(
        ts14: ts14(fixedNow.addingTimeInterval(-5 * 86_400)), input: 111, output: 0, cacheRead: 0, cacheCreation: 0)   // 7월
    cache.claudeEntries["mid\u{0}mid"] = ClaudeEntry(
        ts14: ts14(fixedNow.addingTimeInterval(-20 * 86_400)), input: 222, output: 0, cacheRead: 0, cacheCreation: 0)  // 6월
    cache.claudeEntries["old\u{0}old"] = ClaudeEntry(
        ts14: ts14(fixedNow.addingTimeInterval(-60 * 86_400)), input: 999, output: 0, cacheRead: 0, cacheCreation: 0)  // 5월

    let home = makeTempHome() // 로그 디렉터리 없음 — 워크는 아무 파일도 안 잡고 퇴거/합계만 수행.
    let result = TokenUsageIncrementalScanner.update(cache, homeDirectory: home, now: fixedNow)

    #expect(result.cache.claudeEntries["old\u{0}old"] == nil)   // 5월(직전 월 이전) → 퇴거
    #expect(result.cache.claudeEntries["mid\u{0}mid"] != nil)   // 6월(직전 월) → 보관
    #expect(result.cache.claudeEntries["fresh\u{0}fresh"] != nil)
    #expect(result.usage.claudeInput == 111)                    // 합계는 현재 월(7월)의 fresh 만(mid/old 제외)
    #expect(result.stats.cacheChanged == true)                  // 퇴거가 있었으니 저장 유도
}

@Test
func dedupePersistsAcrossUpdatesAndFiles() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)
    let line = claudeLine(id: "msg_k", requestId: "req_k", timestamp: inMonth, usage: "{\"input_tokens\":100}") + "\n"
    writeFile(line, to: claudeURL(home, project: "a", file: "s.jsonl"))

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.usage.claudeInput == 100)

    // 다른 파일(포크/이어가기)에 같은 (id, requestId) 라인이 복제됨 — 두 번째 갱신에서도 한 번만 계상.
    writeFile(line, to: claudeURL(home, project: "b", file: "s.jsonl"))
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.usage.claudeInput == 100)     // 200 아님 — 갱신 간 dedupe 유지
    #expect(r2.cache.claudeEntries.count == 1)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeReplacesCachedEntryWhenLargerOutputArrivesOnLaterUpdate() {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)
    // 1차 스캔: 진행 스냅샷 [output=2] 를 캐시에 넣는다. 이후 같은 키의 최종 스냅샷 [output=688] 이 append 되고,
    // 2차 스캔의 이어읽기(tail)가 그 라인을 만나면 캐시 엔트리가 교체되어야 한다(증분 경로 max-output 성립).
    let early = claudeLine(id: "msg_i", requestId: "req_i", timestamp: inMonth,
        usage: "{\"input_tokens\":10,\"output_tokens\":2}") + "\n"
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(early, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.usage.claudeOutput == 2)
    #expect(r1.usage.claudeInput == 10)

    let final = claudeLine(id: "msg_i", requestId: "req_i", timestamp: inMonth,
        usage: "{\"input_tokens\":11,\"output_tokens\":688}") + "\n"
    appendFile(final, to: url, modified: fixedNow.addingTimeInterval(1))

    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.claudeBytesRead == final.utf8.count)  // 새로 붙은 바이트만 재읽기
    #expect(r2.usage.claudeOutput == 688)                  // 캐시 엔트리가 교체됨(첫값 2 유지 아님)
    #expect(r2.usage.claudeInput == 11)                    // 교체 레코드의 input 으로 갱신
    #expect(r2.cache.claudeEntries.count == 1)             // 교체이지 추가가 아님(엔트리 1개 유지)
    try? FileManager.default.removeItem(at: home)
}

// (e) 증분 이어읽기: append 후 재스캔은 새 바이트만 읽고, prevCumulative 를 이어받아 그 사이 delta 만 정확히 가산한다.
@Test
func codexTailAddsDeltaOfAppendedCumulativeOnReRead() {
    let home = makeTempHome()
    let evt = utcDate("2026-07-05T00:00:00Z")   // 7월(현재 월), 오늘 아님
    let l1 = codexTokenCountLine(input: 100, cached: 50, output: 10, timestamp: evt) + "\n"   // cum 110
    let url = codexURL(home, path: "2026/07/01/rollout-2026-07-01T00-00-00-aaaa.jsonl")
    writeFile(l1, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.usage.codexInput == 110)   // delta 110 (input+output 합)
    #expect(r1.usage.codexOutput == 0)

    // 세션이 이어져 더 큰 누적치가 append 됨 — tail 로 새 바이트만 읽어 delta(340-110=230)만 가산.
    let l2 = codexTokenCountLine(input: 300, cached: 150, output: 40, timestamp: evt) + "\n"   // cum 340
    appendFile(l2, to: url, modified: fixedNow.addingTimeInterval(1))
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.codexBytesRead == l2.utf8.count)   // 새 바이트만
    #expect(r2.usage.codexInput == 340)                 // 110 + 230(이어읽기 delta) = 최종 누적
    #expect(r2.cache.codexFileStates.values.first?.prevCumulative == 340)
    try? FileManager.default.removeItem(at: home)
}

// (g) 파일 축소(로테이션/절단): size 감소 → offset 0 전체 재파싱 + contrib/prevCumulative 리셋 후 재누적.
@Test
func codexShrunkFileResetsAndFullyReparses() {
    let home = makeTempHome()
    let evt = utcDate("2026-07-05T00:00:00Z")   // 7월
    let url = codexURL(home, path: "2026/07/05/rollout-2026-07-05T00-00-00-eeee.jsonl")
    // 초기: 누적 2000 까지.
    let big = [
        codexTokenCountLine(input: 1000, cached: 0, output: 0, timestamp: evt),
        codexTokenCountLine(input: 2000, cached: 0, output: 0, timestamp: evt)
    ].joined(separator: "\n") + "\n"
    writeFile(big, to: url)
    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.usage.codexInput == 2000)

    // 더 작은 내용으로 덮어씀(축소) — 새 세션이 누적 500 에서 시작. 전체 재파싱으로 delta/prevCumulative 리셋.
    let small = codexTokenCountLine(input: 500, cached: 0, output: 0, timestamp: evt) + "\n"
    writeFile(small, to: url)
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.codexBytesRead == small.utf8.count)   // 처음부터 재읽기(테일 아님)
    #expect(r2.usage.codexInput == 500)                    // 이전 2000 잔류 없이 새 누적 500 만
    #expect(r2.cache.codexFileStates.values.first?.prevCumulative == 500)
    #expect(r2.cache.codexFileStates.values.first?.consumedOffset == small.utf8.count)
    try? FileManager.default.removeItem(at: home)
}

// MARK: - 캐시 (컴팩트 Codable 왕복)

@Test
func cacheSurvivesCompactCodableRoundTripIncludingNulKeys() {
    var cache = TokenUsageCache()
    cache.claudeEntries["msg_1\u{0}req_1"] = ClaudeEntry(ts14: 20_260_722_103_000, input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
    cache.claudeFileStates["/a/b.jsonl"] = FileProgress(size: 10, mtimeMicros: 999, consumedOffset: 8)
    cache.codexFileStates["/c/rollout.jsonl"] = CodexFileProgress(
        size: 20, mtimeMicros: 111, consumedOffset: 15, prevCumulative: 340,
        monthKey: "2026-07", monthContribTotal: 300, dayKey: "2026-07-14", dayContribTotal: 42)

    let data = try! JSONEncoder().encode(cache)
    let decoded = try! JSONDecoder().decode(TokenUsageCache.self, from: data)
    #expect(decoded == cache)   // NUL 구분자 키 + codex 8필드(문자열 섞임) 배열튜플이 정확히 왕복.
}

// (f) 하위호환: 구버전 캐시(codexSchemaVersion 부재 + 옛 codex 튜플)를 로드하면 codexFileStates 만 폐기하고 Claude 상태는
// 보존한다 — 스키마 게이트가 옛 숫자열 튜플을 새 형식으로 억지 디코드하다 던지는 실패(→ 전체 캐시 폐기)를 막는다.
// codexFileStates 가 비면 다음 스캔이 codex 를 offset 0 전체 재파싱해 과거 귀속을 소급 교정한다.
@Test
func legacyCacheDropsCodexStatesButKeepsClaudeAndTriggersReparse() {
    // 옛 codex 튜플 [10,20,30,40,50,60] 은 새 형식으로 디코드하면 monthKey(문자열) 위치에 숫자 50 이 와 실패하지만,
    // codexSchemaVersion 부재(→ 버전 0, 현재≠0) 게이트가 애초에 codexFileStates 디코드를 건너뛴다.
    let legacyJSON = """
    {"claudeFileStates":{"/a/b.jsonl":[10,999,8]},"claudeEntries":{"msg\\u0000req":[20260722103000,1,2,3,4]},"codexFileStates":{"/p/rollout.jsonl":[10,20,30,40,50,60]}}
    """
    let decoded = try! JSONDecoder().decode(TokenUsageCache.self, from: Data(legacyJSON.utf8))
    #expect(decoded.codexFileStates.isEmpty)                       // 옛 codex 상태 폐기(재파싱 유발)
    #expect(decoded.claudeFileStates["/a/b.jsonl"] != nil)         // Claude 파일상태 보존
    #expect(decoded.claudeEntries["msg\u{0}req"]?.input == 1)      // Claude 엔트리 보존
    #expect(decoded.codexSchemaVersion == TokenUsageCache.currentCodexSchemaVersion)  // 인메모리 버전은 현재로 승격
}

// 새 8필드(이벤트-귀속) codex 배열튜플이 정확히 왕복한다(prevCumulative·month/day 귀속 보존).
@Test
func codexFileProgressRoundTripsEventAttributionFields() {
    var cache = TokenUsageCache()
    cache.codexFileStates["/c/rollout.jsonl"] = CodexFileProgress(
        size: 20, mtimeMicros: 111, consumedOffset: 15, prevCumulative: 340,
        monthKey: "2026-07", monthContribTotal: 300, dayKey: "2026-07-14", dayContribTotal: 42)
    let data = try! JSONEncoder().encode(cache)
    let decoded = try! JSONDecoder().decode(TokenUsageCache.self, from: data)
    #expect(decoded == cache)
    let s = decoded.codexFileStates["/c/rollout.jsonl"]!
    #expect(s.prevCumulative == 340)
    #expect(s.monthKey == "2026-07")
    #expect(s.monthContribTotal == 300)
    #expect(s.dayKey == "2026-07-14")
    #expect(s.dayContribTotal == 42)
}

// MARK: - 숫자 포맷 (콤마 전체 숫자)

@Test
func tokenNumberFormatterGroupsFullDigits() {
    #expect(TokenNumberFormatter.grouped(0) == "0")
    #expect(TokenNumberFormatter.grouped(999) == "999")
    #expect(TokenNumberFormatter.grouped(1_000) == "1,000")
    #expect(TokenNumberFormatter.grouped(1_234) == "1,234")
    #expect(TokenNumberFormatter.grouped(145_691_467) == "145,691,467")
    #expect(TokenNumberFormatter.grouped(4_280_667_571) == "4,280,667,571")
    #expect(TokenNumberFormatter.grouped(4_564_338_243) == "4,564,338,243")
    // 음수 방어(0 으로 클램프).
    #expect(TokenNumberFormatter.grouped(-5) == "0")
}

// MARK: - 계약 타입 (TokenUsageMonthly)

@Test
func monthlyTotalSumsAllSixFieldsAndDerivesLabel() {
    let m = TokenUsageMonthly(
        month: "2026-07",
        claudeInput: 1, claudeOutput: 2, claudeCacheRead: 3, claudeCacheCreation: 4,
        codexInput: 5, codexOutput: 6
    )
    #expect(m.total == 21)          // 여섯 필드 합
    #expect(m.claudeTotal == 10)    // 1+2+3+4
    #expect(m.codexTotal == 11)     // 5+6
    #expect(m.monthNumber == 7)     // 'YYYY-MM' → 라벨 숫자(선행 0 제거)
}

@Test
func monthlyTooltipUsesGroupedFullNumbers() {
    let usage = TokenUsageMonthly(
        month: "2026-07",
        claudeInput: 8_458_939, claudeOutput: 9_796_198,
        claudeCacheRead: 4_063_320_273, claudeCacheCreation: 199_092_161,
        codexInput: 145_068_307, codexOutput: 623_160
    )
    #expect(usage.claudeTotal == 4_280_667_571)
    #expect(usage.codexTotal == 145_691_467)
    #expect(usage.total == 4_426_359_038)
    #expect(usage.detailTooltip ==
        "Claude 4,280,667,571 (입력 8,458,939 · 출력 9,796,198 · 캐시읽기 4,063,320,273 · 캐시생성 199,092,161) · Codex 145,691,467")
}

@Test
func monthlyTooltipOmitsSourcesWithNoUsage() {
    // Codex 만 있는 경우 툴팁에 Codex 만 나온다(빈 Claude 파트 미표시).
    let codexOnly = TokenUsageMonthly(month: "2026-07", codexInput: 1_500_000, codexOutput: 500_000)
    #expect(codexOnly.detailTooltip == "Codex 2,000,000")
}

@Test
func monthlySurvivesCodableRoundTrip() {
    let original = TokenUsageMonthly(
        month: "2026-07",
        claudeInput: 1, claudeOutput: 2, claudeCacheRead: 3, claudeCacheCreation: 4,
        codexInput: 5, codexOutput: 6
    )
    let data = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(TokenUsageMonthly.self, from: data)
    #expect(decoded == original)
}

@Test
func monthlyRoundTripPreservesTodayFields() {
    // 새 필드(todayTotal/todayDate)도 인코드→디코드 왕복에서 보존된다(커스텀 Codable 정확성).
    let original = TokenUsageMonthly(month: "2026-07", claudeInput: 1, todayTotal: 12_345, todayDate: "2026-07-14")
    let data = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(TokenUsageMonthly.self, from: data)
    #expect(decoded == original)
    #expect(decoded.todayTotal == 12_345)
    #expect(decoded.todayDate == "2026-07-14")
}

@Test
func monthlyDecodesLegacySnapshotWithoutTodayFieldsAsDefaults() {
    // 하위호환: 옛 영속 스냅샷엔 todayTotal/todayDate 키가 없다 — decodeIfPresent 로 0/"" 폴백해 디코드 실패(재스캔) 없이 복원.
    let legacyJSON = """
    {"month":"2026-07","claudeInput":10,"claudeOutput":20,"claudeCacheRead":30,"claudeCacheCreation":40,"codexInput":50,"codexOutput":60}
    """
    let decoded = try! JSONDecoder().decode(TokenUsageMonthly.self, from: Data(legacyJSON.utf8))
    #expect(decoded.month == "2026-07")
    #expect(decoded.claudeInput == 10)
    #expect(decoded.codexOutput == 60)
    #expect(decoded.total == 210)
    #expect(decoded.todayTotal == 0)    // 하위호환 폴백
    #expect(decoded.todayDate == "")    // 하위호환 폴백
}

@Test
func monthlyTooltipAppendsTodayWhenPresent() {
    // 내 박스 툴팁 끝에 "오늘 +N" 한 줄이 붙는다(값이 있을 때만 — 없으면 기존 문구 그대로).
    let usage = TokenUsageMonthly(month: "2026-07", claudeInput: 100, todayTotal: 1_234_567, todayDate: "2026-07-14")
    #expect(usage.detailTooltip == "Claude 100 (입력 100 · 출력 0 · 캐시읽기 0 · 캐시생성 0) · 오늘 +1,234,567")
    // 오늘분 0 이면 기존 문구 불변(하위호환).
    let noToday = TokenUsageMonthly(month: "2026-07", codexInput: 1_500_000, codexOutput: 500_000)
    #expect(noToday.detailTooltip == "Codex 2,000,000")
}

// MARK: - 뷰 시그니처 (onOpenBoard 유무)

@MainActor
@Test
func rowAcceptsOptionalOnOpenBoardCallback() {
    // 계약 시그니처 고정: 인자 없이도(기존처럼) 생성되어 콜백이 nil, 콜백을 주면 non-nil 로 보관된다.
    let plain = CheckTokenUsageRow()
    let withBoard = CheckTokenUsageRow(onOpenBoard: {})
    #expect(plain.onOpenBoard == nil)
    #expect(withBoard.onOpenBoard != nil)
}

// MARK: - 스토어 (churn 가드/영속/첫 스캔 트리거/월 리셋)

@MainActor
@Test
func refreshIfStaleSkipsWithinMinIntervalThenScansAfter() async {
    // 30분 스로틀 대체 정책: 마지막 갱신 후 minRefreshInterval(3초) 미만이면 스캔을 건너뛴다(여닫이 churn 방지).
    // clock 을 고정/전진시키며 scanCount 로 실제 스캔 여부를 관찰한다.
    let home = makeTempHome()               // 로그 부재 — 스캔은 즉시(0) 끝난다
    let cacheURL = makeTempCacheURL()
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let clockBox = ClockBox(fixedNow)

    let store = TokenUsageStore(
        defaults: defaults, homeDirectory: home, cacheURL: cacheURL, clock: { clockBox.now }
    )
    // init 은 더 이상 스캔을 킥하지 않는다 — 뷰(.task)의 첫 트리거를 모사해 refreshIfStale 로 첫 스캔을 돌린다(lastRefreshAt = fixedNow).
    await store.refreshIfStale()
    #expect(store.scanCount == 1)

    // 같은 시각 refreshIfStale → 0초 경과(<3초) → 스킵.
    await store.refreshIfStale()
    #expect(store.scanCount == 1)

    // 2초 경과(<3초) → 여전히 스킵.
    clockBox.now = fixedNow.addingTimeInterval(2)
    await store.refreshIfStale()
    #expect(store.scanCount == 1)

    // 4초 경과(≥3초) → 갱신 실행.
    clockBox.now = fixedNow.addingTimeInterval(4)
    await store.refreshIfStale()
    #expect(store.scanCount == 2)

    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: home)
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
}

@MainActor
@Test
func storeRestoresPersistedUsageWhenMonthMatches() {
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    // 귀속 월이 현재 KST 월(fixedNow → "2026-07")과 일치하는 스냅샷.
    let seeded = TokenUsageMonthly(
        month: "2026-07",
        claudeInput: 10, claudeOutput: 20, claudeCacheRead: 30, claudeCacheCreation: 40,
        codexInput: 50, codexOutput: 60
    )
    defaults.set(try! JSONEncoder().encode(seeded), forKey: TokenUsageStore.snapshotKey)

    // 월 일치 → init 이 즉시 복원하고(첫 프레임부터 값 표시) 부트스트랩 스캔을 하지 않는다.
    let store = TokenUsageStore(
        defaults: defaults,
        homeDirectory: makeTempHome(),
        cacheURL: makeTempCacheURL(),
        clock: { fixedNow }
    )
    #expect(store.currentMonthUsage == seeded)
    #expect(store.isScanning == false)
    #expect(store.scanCount == 0)
    defaults.removePersistentDomain(forName: suiteName)
}

@MainActor
@Test
func storeIgnoresPersistedUsageFromDifferentMonthAndRescans() async {
    // 월 전환 모사: 지난달(2026-06) 스냅샷이 영속돼 있어도 현재 월(fixedNow → 2026-07)과 다르므로 표시하지 않고 재스캔한다.
    let home = makeTempHome()   // 로그 부재 → 재스캔은 현재 월 0 집계
    let cacheURL = makeTempCacheURL()
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let stale = TokenUsageMonthly(month: "2026-06", claudeInput: 999_999, claudeOutput: 888_888)
    defaults.set(try! JSONEncoder().encode(stale), forKey: TokenUsageStore.snapshotKey)

    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: cacheURL, clock: { fixedNow })
    // 월 불일치라 init 복원은 없다(currentMonthUsage nil). 첫 스캔을 뷰 트리거(refreshIfStale)로 돌려 현재 월로 리셋한다.
    await store.refreshIfStale()

    // 지난달 숫자가 새 달 프레임에 새지 않는다: 재스캔이 현재 월로 리셋(0), month 는 2026-07.
    #expect(store.currentMonthUsage?.month == "2026-07")
    #expect(store.currentMonthUsage?.total == 0)
    #expect(store.scanCount == 1)   // 월 불일치 → 재스캔이 돌았다

    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: home)
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
}

@MainActor
@Test
func storeBootstrapsScanAndPersistsNonZeroResult() async {
    let home = makeTempHome()
    let inMonth = fixedNow.addingTimeInterval(-3 * 86_400)   // 현재 월
    let line = claudeLine(
        id: "m", requestId: "r", timestamp: inMonth,
        usage: "{\"input_tokens\":123,\"output_tokens\":7}"
    ) + "\n"
    writeFile(line, to: claudeURL(home, project: "p", file: "s.jsonl"))
    let cacheURL = makeTempCacheURL()
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    // 영속 스냅샷이 없어 init 복원은 없다. 첫 스캔을 뷰 트리거(refreshIfStale)로 돌린다(백그라운드 완료까지 await).
    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: cacheURL, clock: { fixedNow })

    await store.refreshIfStale()
    #expect(store.currentMonthUsage?.claudeInput == 123)
    #expect(store.currentMonthUsage?.total == 130)
    #expect(store.currentMonthUsage?.month == "2026-07")
    #expect(store.isScanning == false)
    // 값이 있으므로 영속된다(재시작 후 즉시 표시).
    #expect(defaults.data(forKey: TokenUsageStore.snapshotKey) != nil)
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: home)
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
}

@MainActor
@Test
func storeDoesNotPersistZeroResultSoNextLaunchRescans() async {
    // 로그가 없는 홈: 부트스트랩 스캔이 0 을 낸다. 인메모리엔 집계(0)가 남지만 total==0 이라 뷰는 EmptyView 를 그린다.
    // 영속은 하지 않아, 재실행(새 스토어)은 nil→다시 부트스트랩한다.
    let home = makeTempHome()
    let cacheURL = makeTempCacheURL()
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: cacheURL, clock: { fixedNow })

    // 첫 스캔을 뷰 트리거(refreshIfStale)로 돌린다 — 로그 부재라 0 집계.
    await store.refreshIfStale()
    #expect(store.isScanning == false)
    #expect(store.currentMonthUsage?.total == 0)  // 인메모리 0 집계(뷰는 total>0 이 아니라 EmptyView)
    #expect(defaults.data(forKey: TokenUsageStore.snapshotKey) == nil)  // 영속 안 함 → 재실행 시 첫 스캔에서 다시 채운다

    // 같은 defaults 로 새 스토어를 만들면(재실행 모사) 영속본이 없고 init 이 스캔하지 않아 currentMonthUsage 는 nil 로 시작한다.
    let relaunched = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: makeTempCacheURL(), clock: { fixedNow })
    #expect(relaunched.currentMonthUsage == nil)

    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: home)
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
}

/// clock 주입용 참조 박스(테스트에서 현재 시각을 전진시켜 churn 가드를 결정적으로 검증).
@MainActor
private final class ClockBox {
    var now: Date
    init(_ now: Date) { self.now = now }
}

// MARK: - 실증(옵트인): 이 맥의 실제 로그로 첫 스캔·무변경 갱신·단일파일 재테일 시간을 측정한다.
// CHECK_TOKEN_LIVE=1 일 때만 실행된다(평소 swift test 에서는 스킵 — 결정적/헤드리스 유지). 실홈은 읽기 전용으로만.

@Test(.enabled(if: ProcessInfo.processInfo.environment["CHECK_TOKEN_LIVE"] == "1"))
func liveIncrementalScanReportsRealUsageAndTimings() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let now = Date()

    // 1) 첫 스캔(빈 캐시 = 전체 스캔).
    let t0 = Date()
    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now)
    let firstElapsed = Date().timeIntervalSince(t0)

    // 2) 무변경 갱신(같은 캐시 재사용) — 워크+stat 만, 재읽기 0 목표.
    let t1 = Date()
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: now)
    let noChangeElapsed = Date().timeIntervalSince(t1)

    // 3) "변경 1파일" 모사(실홈은 읽기 전용이라 파일을 안 건드린다): 캐시에서 가장 큰 claude 파일 하나의
    //    mtime 을 1μs 낮춰(=역행) 그 파일만 처음부터 재파싱하게 만든다 → 단일 파일 전체 재읽기 비용(상한) 측정.
    var poked = r2.cache
    var pokedPath = "-"
    var pokedBytes = 0
    if let (path, state) = poked.claudeFileStates.max(by: { $0.value.size < $1.value.size }) {
        pokedPath = (path as NSString).lastPathComponent
        pokedBytes = state.size
        poked.claudeFileStates[path] = FileProgress(size: state.size, mtimeMicros: state.mtimeMicros - 1, consumedOffset: 0)
    }
    let t2 = Date()
    let r3 = TokenUsageIncrementalScanner.update(poked, homeDirectory: home, now: now)
    let oneFileElapsed = Date().timeIntervalSince(t2)

    print("=== LIVE INCREMENTAL TOKEN SCAN (KST 월: \(r1.usage.month)) ===")
    print(String(format: "first(full)  %.3fs  claudeBytes=%d codexBytes=%d filesRead=%d+%d",
                 firstElapsed, r1.stats.claudeBytesRead, r1.stats.codexBytesRead,
                 r1.stats.claudeFilesRead, r1.stats.codexFilesRead))
    print(String(format: "no-change    %.3fs  claudeBytes=%d codexBytes=%d statted=%d+%d changed=%@",
                 noChangeElapsed, r2.stats.claudeBytesRead, r2.stats.codexBytesRead,
                 r2.stats.claudeFilesStatted, r2.stats.codexFilesStatted, r2.stats.cacheChanged ? "true" : "false"))
    print(String(format: "one-file     %.3fs  reReadBytes=%d file=%@ (size=%d, 상한: 전체 재파싱)",
                 oneFileElapsed, r3.stats.claudeBytesRead, pokedPath, pokedBytes))
    print("Claude input=\(r1.usage.claudeInput) output=\(r1.usage.claudeOutput) "
        + "cacheRead=\(r1.usage.claudeCacheRead) cacheCreation=\(r1.usage.claudeCacheCreation) "
        + "total=\(r1.usage.claudeTotal)")
    print("Codex input=\(r1.usage.codexInput) output=\(r1.usage.codexOutput) total=\(r1.usage.codexTotal)")
    print("GRAND TOTAL=\(r1.usage.total)  grouped=\(TokenNumberFormatter.grouped(r1.usage.total))")
    print("tooltip=\(r1.usage.detailTooltip)")

    // 이 테스트는 실홈(읽기)에서 돈다 — 실행 중 이 세션이 Claude 로그에 계속 쓰므로(자기참조) '무변경=0바이트'
    // 하드 단언은 동시쓰기에 플레이크다. 재읽기 바이트/변경 여부는 정보성으로만 출력하고, 견고한 핵심 성질만
    // 단언한다: 합계>0 이고, 파일은 자라기만 하므로(같은 now 로 월/퇴거 고정) 스캔을 거듭해도 합계는 단조 비감소.
    print(String(format: "no-change reread claudeBytes=%d codexBytes=%d changed=%@ (동시쓰기면 >0 가능 — 정보성)",
                 r2.stats.claudeBytesRead, r2.stats.codexBytesRead, r2.stats.cacheChanged ? "true" : "false"))
    #expect(r1.usage.total > 0)
    #expect(r2.usage.total >= r1.usage.total)  // 무변경/동시쓰기 모두 비감소(파일은 자라기만).
    #expect(r3.usage.total >= r1.usage.total)  // 단일 파일 재파싱 후에도(dedupe) 비감소.
}
