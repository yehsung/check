import Foundation
import Testing
@testable import check

// MARK: - 픽스처 헬퍼 (임시 홈에 jsonl 을 써서 실제 파일 순회·mtime·파싱·이어읽기 경로를 검증한다)
//
// 픽스처는 Package.swift 리소스 등록 대신, 테스트가 런타임에 임시 디렉터리로 쓰는 방식이라 번들 등록이 불필요하다.
//
// 라인 종결 규약: 실제 Claude/Codex 로그는 레코드마다 개행("\n")으로 종결된다(append-only). 증분 스캐너는
// "개행 없는 꼬리"를 아직 쓰는 중인 부분 라인으로 보고 소비하지 않으므로, 픽스처도 완결 레코드는 항상 "\n" 으로 끝낸다.

/// 스캔 기준 시각(고정). 창/타임스탬프/mtime 을 모두 이 값에서 파생해 결정적으로 만든다.
private let fixedNow = Date(timeIntervalSince1970: 1_784_000_000)

/// Claude timestamp 포맷(UTC, 소수초, Z). 스캐너의 앞 19자 사전식/정수 창 비교와 맞물린다.
private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
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

/// Codex token_count 라인 한 줄(JSON, total_token_usage 포함, 개행 미포함).
private func codexTokenCountLine(input: Int, cached: Int, output: Int) -> String {
    "{\"timestamp\":\"2026-07-01T00:00:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
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
    let inWindow = fixedNow.addingTimeInterval(-5 * 86_400)
    // L1 은 두 파일(포크/이어가기)에 동일 (id, requestId) 로 복제된다 → 한 번만 집계돼야 한다.
    let l1 = claudeLine(
        id: "msg_1", requestId: "req_1", timestamp: inWindow,
        usage: "{\"input_tokens\":100,\"output_tokens\":50,\"cache_read_input_tokens\":10,\"cache_creation_input_tokens\":5}"
    )
    // L2 는 별도 (id, requestId) → 따로 집계된다.
    let l2 = claudeLine(
        id: "msg_2", requestId: "req_2", timestamp: inWindow,
        usage: "{\"input_tokens\":200,\"output_tokens\":100,\"cache_read_input_tokens\":20,\"cache_creation_input_tokens\":10}"
    )
    writeFile("\(l1)\n", to: claudeURL(home, project: "a", file: "sessionA.jsonl"))
    writeFile("\(l1)\n\(l2)\n", to: claudeURL(home, project: "b", file: "sessionB.jsonl"))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    // 중복 제거가 없으면 input 은 400(=100+100+200). dedupe 로 300 이어야 한다.
    #expect(snapshot.claude.input == 300)
    #expect(snapshot.claude.output == 150)
    #expect(snapshot.claude.cacheRead == 30)
    #expect(snapshot.claude.cacheCreation == 15)
    #expect(snapshot.claude.total == 495)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeSameMessageIDDifferentRequestIDCountsSeparately() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-1 * 86_400)
    // 같은 message.id 라도 requestId 가 다르면 다른 요청이므로 각각 집계한다((id, requestId) 쌍 키).
    let a = claudeLine(id: "msg_x", requestId: "req_a", timestamp: inWindow, usage: "{\"input_tokens\":100}")
    let b = claudeLine(id: "msg_x", requestId: "req_b", timestamp: inWindow, usage: "{\"input_tokens\":100}")
    writeFile("\(a)\n\(b)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.claude.input == 200)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeAdoptsMaxOutputAmongStreamingSnapshotsInSameFile() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    // 같은 (id, requestId)의 스트리밍 진행 스냅샷 3줄 — output_tokens 가 점증([2,2,688]).
    // "첫값 채택"이면 2, 올바른 max-output 채택이면 688. 교체 레코드(최종 스냅샷)의 input/cache 도 함께 채택된다.
    let s1 = claudeLine(id: "msg_s", requestId: "req_s", timestamp: inWindow,
        usage: "{\"input_tokens\":10,\"output_tokens\":2,\"cache_read_input_tokens\":1,\"cache_creation_input_tokens\":3}")
    let s2 = claudeLine(id: "msg_s", requestId: "req_s", timestamp: inWindow,
        usage: "{\"input_tokens\":10,\"output_tokens\":2,\"cache_read_input_tokens\":1,\"cache_creation_input_tokens\":3}")
    let s3 = claudeLine(id: "msg_s", requestId: "req_s", timestamp: inWindow,
        usage: "{\"input_tokens\":11,\"output_tokens\":688,\"cache_read_input_tokens\":4,\"cache_creation_input_tokens\":9}")
    writeFile("\(s1)\n\(s2)\n\(s3)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.claude.output == 688)        // 최대 output 채택(첫값 2 아님)
    #expect(snapshot.claude.input == 11)          // 교체 레코드(최종 스냅샷)의 input
    #expect(snapshot.claude.cacheRead == 4)       // 함께 교체
    #expect(snapshot.claude.cacheCreation == 9)   // 함께 교체
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeForkReplicationOfFinalSnapshotCountsOnce() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    // 포크 복제: 두 파일에 같은 (id, requestId) 최종 스냅샷(output=688)이 그대로 복사된다 → 1회만 집계(불변).
    let line = claudeLine(id: "msg_f", requestId: "req_f", timestamp: inWindow,
        usage: "{\"input_tokens\":11,\"output_tokens\":688,\"cache_read_input_tokens\":4,\"cache_creation_input_tokens\":9}")
    writeFile("\(line)\n", to: claudeURL(home, project: "a", file: "s.jsonl"))
    writeFile("\(line)\n", to: claudeURL(home, project: "b", file: "s.jsonl"))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.claude.output == 688)        // 1376 아님 — 같은 값이라 max 채택도 1회 집계 불변
    #expect(snapshot.claude.input == 11)
    #expect(snapshot.claude.cacheRead == 4)
    #expect(snapshot.claude.cacheCreation == 9)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeExcludesLinesOutsideThirtyDayWindow() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-5 * 86_400)     // 창 안
    let outOfWindow = fixedNow.addingTimeInterval(-40 * 86_400) // 창 밖(30일 이전)
    let keep = claudeLine(id: "in", requestId: "in", timestamp: inWindow, usage: "{\"input_tokens\":1000}")
    let drop = claudeLine(id: "out", requestId: "out", timestamp: outOfWindow, usage: "{\"input_tokens\":999999}")
    // 파일 mtime 은 fixedNow 라 프리필터는 통과 — 창 밖 라인은 timestamp 로만 걸러진다.
    writeFile("\(keep)\n\(drop)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.claude.input == 1000)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeTreatsMissingAndNullUsageFieldsAsZero() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-2 * 86_400)
    // output_tokens 누락, cache_read 는 null, cache_creation 누락 → 전부 0 으로 처리되어야 한다.
    let line = claudeLine(
        id: "m", requestId: "r", timestamp: inWindow,
        usage: "{\"input_tokens\":100,\"cache_read_input_tokens\":null}"
    )
    writeFile("\(line)\n", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.claude.input == 100)
    #expect(snapshot.claude.output == 0)
    #expect(snapshot.claude.cacheRead == 0)
    #expect(snapshot.claude.cacheCreation == 0)
    try? FileManager.default.removeItem(at: home)
}

@Test
func mtimePrefilterSkipsFilesUntouchedSinceCutoff() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-5 * 86_400)
    // 라인 timestamp 는 창 안이지만 파일 mtime 이 컷오프 이전(40일 전)이라 파일 통째로 스킵되어야 한다.
    let line = claudeLine(id: "m", requestId: "r", timestamp: inWindow, usage: "{\"input_tokens\":777}")
    writeFile("\(line)\n", to: claudeURL(home, project: "p", file: "old.jsonl"),
              modified: fixedNow.addingTimeInterval(-40 * 86_400))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.claude.total == 0)
    try? FileManager.default.removeItem(at: home)
}

// MARK: - Codex 파서

@Test
func codexAdoptsLastValidTokenCountPerFileAndSumsAcrossFiles() {
    let home = makeTempHome()
    // 파일1: token_count 여러 줄 — 마지막 "유효" 누적치(1000/800/50)를 채택해야 한다(합산 아님, 첫 줄 아님).
    // 마지막 줄은 total_token_usage 없는 무효 라인이라 무시되고, 직전 유효 라인이 채택된다.
    let file1 = [
        codexTokenCountLine(input: 500, cached: 400, output: 20),
        codexTokenCountLine(input: 1000, cached: 800, output: 50),
        codexInvalidTokenCountLine
    ].joined(separator: "\n")
    // 파일2: 다른 세션 누적치(200/100/5).
    let file2 = codexTokenCountLine(input: 200, cached: 100, output: 5)
    writeFile("\(file1)\n", to: codexURL(home, path: "2026/07/01/rollout-2026-07-01T00-00-00-aaaa.jsonl"))
    writeFile("\(file2)\n", to: codexURL(home, path: "2026/07/02/rollout-2026-07-02T00-00-00-bbbb.jsonl"))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.codex.input == 1200)   // 1000 + 200 (파일 단위 최종 누적치 합)
    #expect(snapshot.codex.output == 55)    // 50 + 5
    #expect(snapshot.codex.cached == 900)   // 800 + 100
    #expect(snapshot.codex.total == 1255)   // input(캐시 포함) + output
    try? FileManager.default.removeItem(at: home)
}

@Test
func codexSkipsFilesUntouchedSinceCutoff() {
    let home = makeTempHome()
    let line = codexTokenCountLine(input: 9999, cached: 0, output: 1)
    writeFile("\(line)\n", to: codexURL(home, path: "2026/05/01/rollout-2026-05-01T00-00-00-cccc.jsonl"),
              modified: fixedNow.addingTimeInterval(-45 * 86_400))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.codex.total == 0)
    try? FileManager.default.removeItem(at: home)
}

// MARK: - 소스 결합/부재

@Test
func scanReturnsZeroWhenNoLogDirectoriesExist() {
    // 홈에 .claude/.codex 가 아예 없으면(로그 부재) 전부 0 — 뷰는 이 경우 아무것도 그리지 않는다.
    let home = makeTempHome()
    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)
    #expect(snapshot.total == 0)
    #expect(snapshot.claude.total == 0)
    #expect(snapshot.codex.total == 0)
}

// MARK: - 증분 스캔 (이어읽기 · 무변경 스킵 · 축소 폴백 · 퇴거 · 부분라인 · dedupe 유지)

@Test
func tailReadsOnlyNewlyAppendedBytesAndAdvancesOffset() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    let l1 = claudeLine(id: "a", requestId: "a", timestamp: inWindow, usage: "{\"input_tokens\":100}") + "\n"
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(l1, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.snapshot.claude.input == 100)
    // 파일이 하나뿐이라 .values.first 로 그 상태를 본다(경로 키는 FS 심볼릭 정규화로 테스트 url.path 와 다를 수 있음).
    #expect(r1.cache.claudeFileStates.values.first?.consumedOffset == l1.utf8.count)

    // 라인 하나 append(파일 성장) → 재갱신은 consumedOffset 이후 "새 바이트"만 읽는다.
    let l2 = claudeLine(id: "b", requestId: "b", timestamp: inWindow, usage: "{\"input_tokens\":200}") + "\n"
    appendFile(l2, to: url, modified: fixedNow.addingTimeInterval(1))

    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.claudeBytesRead == l2.utf8.count)          // 새로 붙은 바이트만
    #expect(r2.snapshot.claude.input == 300)                    // 100 + 200
    #expect(r2.cache.claudeFileStates.values.first?.consumedOffset == l1.utf8.count + l2.utf8.count)
    try? FileManager.default.removeItem(at: home)
}

@Test
func unchangedFileIsNotReReadOnSecondUpdate() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    let line = claudeLine(id: "m", requestId: "r", timestamp: inWindow, usage: "{\"input_tokens\":100}") + "\n"
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(line, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.snapshot.claude.input == 100)
    #expect(r1.stats.claudeBytesRead > 0)
    #expect(r1.stats.cacheChanged == true)

    // 파일을 건드리지 않고 재갱신 → 크기·mtime 동일이라 재읽기 0, 캐시 무변경(저장 스킵).
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.claudeBytesRead == 0)
    #expect(r2.stats.claudeFilesRead == 0)
    #expect(r2.stats.cacheChanged == false)
    #expect(r2.snapshot == r1.snapshot)
    try? FileManager.default.removeItem(at: home)
}

@Test
func partialLineIsNotConsumedUntilNewlineArrives() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    let l1 = claudeLine(id: "a", requestId: "a", timestamp: inWindow, usage: "{\"input_tokens\":100}") + "\n"
    let l2 = claudeLine(id: "b", requestId: "b", timestamp: inWindow, usage: "{\"input_tokens\":200}") // 개행 없음
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(l1 + l2, to: url)  // l2 는 아직 쓰는 중인 부분 라인(개행 미도착)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.snapshot.claude.input == 100)                                       // l2(부분)는 미소비
    #expect(r1.cache.claudeFileStates.values.first?.consumedOffset == l1.utf8.count) // l1 끝에서 멈춤

    // 개행이 붙어 l2 완성 → 다음 갱신에서 완성분만 반영(이어읽기는 consumedOffset 부터 = l2 + 개행).
    appendFile("\n", to: url, modified: fixedNow.addingTimeInterval(1))
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.snapshot.claude.input == 300)                                     // 이제 l2 계상
    #expect(r2.stats.claudeBytesRead == (l2 + "\n").utf8.count)                  // 부분+새 개행만 재읽기
    #expect(r2.cache.claudeFileStates.values.first?.consumedOffset == (l1 + l2 + "\n").utf8.count)
    try? FileManager.default.removeItem(at: home)
}

@Test
func shrunkFileTriggersFullReparseFallback() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    let l1 = claudeLine(id: "m1", requestId: "r1", timestamp: inWindow, usage: "{\"input_tokens\":100}") + "\n"
    let l2 = claudeLine(id: "m2", requestId: "r2", timestamp: inWindow, usage: "{\"input_tokens\":200}") + "\n"
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(l1 + l2, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.snapshot.claude.input == 300)

    // 파일을 더 작은 내용으로 덮어쓴다(로테이션/절단 모사) — size 축소 → 전체 재파싱 폴백.
    let l3 = claudeLine(id: "m3", requestId: "r3", timestamp: inWindow, usage: "{\"input_tokens\":50}") + "\n"
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
func evictsEntriesOutsideThirtyOneDayMargin() {
    // 창(30일) 합계와 퇴거(31일 보존)를 분리 검증한다: 30.5일 엔트리는 보존되나 합계 제외, 32일 엔트리는 퇴거.
    var cache = TokenUsageCache()
    cache.claudeEntries["fresh\u{0}fresh"] = ClaudeEntry(
        ts14: ts14(fixedNow.addingTimeInterval(-5 * 86_400)), input: 111, output: 0, cacheRead: 0, cacheCreation: 0)
    cache.claudeEntries["mid\u{0}mid"] = ClaudeEntry(
        ts14: ts14(fixedNow.addingTimeInterval(-30.5 * 86_400)), input: 222, output: 0, cacheRead: 0, cacheCreation: 0)
    cache.claudeEntries["old\u{0}old"] = ClaudeEntry(
        ts14: ts14(fixedNow.addingTimeInterval(-32 * 86_400)), input: 999, output: 0, cacheRead: 0, cacheCreation: 0)

    let home = makeTempHome() // 로그 디렉터리 없음 — 워크는 아무 파일도 안 잡고 퇴거/합계만 수행.
    let result = TokenUsageIncrementalScanner.update(cache, homeDirectory: home, now: fixedNow)

    #expect(result.cache.claudeEntries["old\u{0}old"] == nil)   // 32일(>31일) → 퇴거
    #expect(result.cache.claudeEntries["mid\u{0}mid"] != nil)   // 30.5일(≤31일) → 보존
    #expect(result.cache.claudeEntries["fresh\u{0}fresh"] != nil)
    #expect(result.snapshot.claude.input == 111)                // 합계는 30일 창 안의 fresh 만(mid/old 제외)
    #expect(result.stats.cacheChanged == true)                  // 퇴거가 있었으니 저장 유도
}

@Test
func dedupePersistsAcrossUpdatesAndFiles() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    let line = claudeLine(id: "msg_k", requestId: "req_k", timestamp: inWindow, usage: "{\"input_tokens\":100}") + "\n"
    writeFile(line, to: claudeURL(home, project: "a", file: "s.jsonl"))

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.snapshot.claude.input == 100)

    // 다른 파일(포크/이어가기)에 같은 (id, requestId) 라인이 복제됨 — 두 번째 갱신에서도 한 번만 계상.
    writeFile(line, to: claudeURL(home, project: "b", file: "s.jsonl"))
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.snapshot.claude.input == 100)     // 200 아님 — 갱신 간 dedupe 유지
    #expect(r2.cache.claudeEntries.count == 1)
    try? FileManager.default.removeItem(at: home)
}

@Test
func claudeReplacesCachedEntryWhenLargerOutputArrivesOnLaterUpdate() {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    // 1차 스캔: 진행 스냅샷 [output=2] 를 캐시에 넣는다. 이후 같은 키의 최종 스냅샷 [output=688] 이 append 되고,
    // 2차 스캔의 이어읽기(tail)가 그 라인을 만나면 캐시 엔트리가 교체되어야 한다(증분 경로 max-output 성립).
    let early = claudeLine(id: "msg_i", requestId: "req_i", timestamp: inWindow,
        usage: "{\"input_tokens\":10,\"output_tokens\":2}") + "\n"
    let url = claudeURL(home, project: "p", file: "s.jsonl")
    writeFile(early, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.snapshot.claude.output == 2)
    #expect(r1.snapshot.claude.input == 10)

    let final = claudeLine(id: "msg_i", requestId: "req_i", timestamp: inWindow,
        usage: "{\"input_tokens\":11,\"output_tokens\":688}") + "\n"
    appendFile(final, to: url, modified: fixedNow.addingTimeInterval(1))

    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.claudeBytesRead == final.utf8.count)  // 새로 붙은 바이트만 재읽기
    #expect(r2.snapshot.claude.output == 688)              // 캐시 엔트리가 교체됨(첫값 2 유지 아님)
    #expect(r2.snapshot.claude.input == 11)                // 교체 레코드의 input 으로 갱신
    #expect(r2.cache.claudeEntries.count == 1)             // 교체이지 추가가 아님(엔트리 1개 유지)
    try? FileManager.default.removeItem(at: home)
}

@Test
func codexTailAdoptsNewerCumulativeTokenCountOnAppend() {
    let home = makeTempHome()
    let l1 = codexTokenCountLine(input: 100, cached: 50, output: 10) + "\n"
    let url = codexURL(home, path: "2026/07/01/rollout-2026-07-01T00-00-00-aaaa.jsonl")
    writeFile(l1, to: url)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: fixedNow)
    #expect(r1.snapshot.codex.input == 100)
    #expect(r1.snapshot.codex.output == 10)

    // 세션이 이어져 더 큰 누적치가 append 됨 — tail 로 새 바이트만 읽어 최신 token_count 를 채택(합산 아님).
    let l2 = codexTokenCountLine(input: 300, cached: 150, output: 40) + "\n"
    appendFile(l2, to: url, modified: fixedNow.addingTimeInterval(1))
    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: fixedNow)
    #expect(r2.stats.codexBytesRead == l2.utf8.count)   // 새 바이트만
    #expect(r2.snapshot.codex.input == 300)             // 최신 누적치로 갱신
    #expect(r2.snapshot.codex.output == 40)
    try? FileManager.default.removeItem(at: home)
}

// MARK: - 캐시 (컴팩트 Codable 왕복)

@Test
func cacheSurvivesCompactCodableRoundTripIncludingNulKeys() {
    var cache = TokenUsageCache()
    cache.claudeEntries["msg_1\u{0}req_1"] = ClaudeEntry(ts14: 20_260_722_103_000, input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
    cache.claudeFileStates["/a/b.jsonl"] = FileProgress(size: 10, mtimeMicros: 999, consumedOffset: 8)
    cache.codexFileStates["/c/rollout.jsonl"] = CodexFileProgress(size: 20, mtimeMicros: 111, consumedOffset: 15, input: 5, output: 6, cached: 7)

    let data = try! JSONEncoder().encode(cache)
    let decoded = try! JSONDecoder().decode(TokenUsageCache.self, from: data)
    #expect(decoded == cache)   // NUL 구분자 키 포함 배열튜플 인코딩이 정확히 왕복.
}

// MARK: - 축약 포맷

@Test
func tokenAbbreviationMatchesOracleDigits() {
    #expect(TokenAbbreviation.short(0) == "0")
    #expect(TokenAbbreviation.short(999) == "999")
    #expect(TokenAbbreviation.short(1_000) == "1.0K")
    #expect(TokenAbbreviation.short(1_234) == "1.2K")
    #expect(TokenAbbreviation.short(3_400_000) == "3.4M")
    #expect(TokenAbbreviation.short(145_691_467) == "145.7M")
    #expect(TokenAbbreviation.short(199_092_161) == "199.1M")
    #expect(TokenAbbreviation.short(4_063_320_273) == "4.06B")
    #expect(TokenAbbreviation.short(4_280_667_571) == "4.28B")
    // 음수 방어(0 으로 클램프).
    #expect(TokenAbbreviation.short(-5) == "0")
}

// MARK: - 스냅샷 (툴팁/Codable)

@Test
func snapshotTooltipMatchesSpecFormat() {
    let snapshot = TokenUsageSnapshot(
        claude: ClaudeTokenUsage(input: 8_458_939, output: 9_796_198,
                                 cacheRead: 4_063_320_273, cacheCreation: 199_092_161),
        codex: CodexTokenUsage(input: 145_068_307, output: 623_160, cached: 137_277_056),
        scannedAt: fixedNow
    )
    #expect(snapshot.claude.total == 4_280_667_571)
    #expect(snapshot.codex.total == 145_691_467)
    #expect(snapshot.total == 4_426_359_038)
    #expect(snapshot.detailTooltip ==
        "Claude 4.28B (입력 8.5M · 출력 9.8M · 캐시읽기 4.06B · 캐시생성 199.1M) · Codex 145.7M")
}

@Test
func snapshotTooltipOmitsSourcesWithNoUsage() {
    // Codex 로그만 있는 경우 툴팁에 Codex 만 나온다(빈 Claude 파트 미표시).
    let codexOnly = TokenUsageSnapshot(
        claude: ClaudeTokenUsage(),
        codex: CodexTokenUsage(input: 1_500_000, output: 500_000, cached: 0),
        scannedAt: fixedNow
    )
    #expect(codexOnly.detailTooltip == "Codex 2.0M")
}

@Test
func snapshotSurvivesCodableRoundTrip() {
    let original = TokenUsageSnapshot(
        claude: ClaudeTokenUsage(input: 1, output: 2, cacheRead: 3, cacheCreation: 4),
        codex: CodexTokenUsage(input: 5, output: 6, cached: 7),
        scannedAt: fixedNow
    )
    let data = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(TokenUsageSnapshot.self, from: data)
    #expect(decoded == original)
}

// MARK: - 스토어 (churn 가드/영속/부트스트랩)

@MainActor
@Test
func refreshNowSkipsWithinMinIntervalThenScansAfter() async {
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
    // init 부트스트랩(snapshot nil)이 1회 스캔을 킥한다(lastRefreshAt = fixedNow).
    await store.awaitScanCompletion()
    #expect(store.scanCount == 1)

    // 같은 시각 refreshNow → 0초 경과(<3초) → 스킵.
    await store.refreshNow()
    #expect(store.scanCount == 1)

    // 2초 경과(<3초) → 여전히 스킵.
    clockBox.now = fixedNow.addingTimeInterval(2)
    await store.refreshNow()
    #expect(store.scanCount == 1)

    // 4초 경과(≥3초) → 갱신 실행.
    clockBox.now = fixedNow.addingTimeInterval(4)
    await store.refreshNow()
    #expect(store.scanCount == 2)

    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: home)
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
}

@MainActor
@Test
func storeRestoresPersistedSnapshotOnInit() {
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let seeded = TokenUsageSnapshot(
        claude: ClaudeTokenUsage(input: 10, output: 20, cacheRead: 30, cacheCreation: 40),
        codex: CodexTokenUsage(input: 50, output: 60, cached: 0),
        scannedAt: fixedNow
    )
    defaults.set(try! JSONEncoder().encode(seeded), forKey: TokenUsageStore.snapshotKey)

    // 영속 스냅샷이 있으면 init 이 즉시 복원하고(첫 프레임부터 값 표시) 부트스트랩 스캔을 하지 않는다.
    let store = TokenUsageStore(
        defaults: defaults,
        homeDirectory: makeTempHome(),
        cacheURL: makeTempCacheURL(),
        clock: { fixedNow }
    )
    #expect(store.snapshot == seeded)
    #expect(store.isScanning == false)
    #expect(store.scanCount == 0)
    defaults.removePersistentDomain(forName: suiteName)
}

@MainActor
@Test
func storeBootstrapsScanAndPersistsNonZeroResult() async {
    let home = makeTempHome()
    let inWindow = fixedNow.addingTimeInterval(-3 * 86_400)
    let line = claudeLine(
        id: "m", requestId: "r", timestamp: inWindow,
        usage: "{\"input_tokens\":123,\"output_tokens\":7}"
    ) + "\n"
    writeFile(line, to: claudeURL(home, project: "p", file: "s.jsonl"))
    let cacheURL = makeTempCacheURL()
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    // 영속 스냅샷이 없으므로 init 이 1회 부트스트랩 스캔을 킥한다.
    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: cacheURL, clock: { fixedNow })

    // 백그라운드 스캔 완료를 결정적으로 기다린다(고정 시간 폴링은 전체 스위트 병렬 부하에서 플레이크).
    await store.awaitScanCompletion()
    #expect(store.snapshot?.claude.input == 123)
    #expect(store.snapshot?.total == 130)
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
    // 로그가 없는 홈: 부트스트랩 스캔이 0 을 낸다. 인메모리엔 스냅샷(0)이 남지만 total==0 이라 뷰는 EmptyView 를 그린다.
    // 영속은 하지 않아, 재실행(새 스토어)은 nil→다시 부트스트랩한다.
    let home = makeTempHome()
    let cacheURL = makeTempCacheURL()
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: cacheURL, clock: { fixedNow })

    await store.awaitScanCompletion()
    #expect(store.isScanning == false)
    #expect(store.snapshot?.total == 0)  // 인메모리 0 스냅샷(뷰는 total>0 이 아니라 EmptyView)
    #expect(defaults.data(forKey: TokenUsageStore.snapshotKey) == nil)  // 영속 안 함 → 재실행 시 재부트스트랩

    // 같은 defaults 로 새 스토어를 만들면(재실행 모사) 영속본이 없어 snapshot 은 nil 로 시작한다.
    let relaunched = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: makeTempCacheURL(), clock: { fixedNow })
    #expect(relaunched.snapshot == nil)

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

    print("=== LIVE INCREMENTAL TOKEN SCAN ===")
    print(String(format: "first(full)  %.3fs  claudeBytes=%d codexBytes=%d filesRead=%d+%d",
                 firstElapsed, r1.stats.claudeBytesRead, r1.stats.codexBytesRead,
                 r1.stats.claudeFilesRead, r1.stats.codexFilesRead))
    print(String(format: "no-change    %.3fs  claudeBytes=%d codexBytes=%d statted=%d+%d changed=%@",
                 noChangeElapsed, r2.stats.claudeBytesRead, r2.stats.codexBytesRead,
                 r2.stats.claudeFilesStatted, r2.stats.codexFilesStatted, r2.stats.cacheChanged ? "true" : "false"))
    print(String(format: "one-file     %.3fs  reReadBytes=%d file=%@ (size=%d, 상한: 전체 재파싱)",
                 oneFileElapsed, r3.stats.claudeBytesRead, pokedPath, pokedBytes))
    print("Claude input=\(r1.snapshot.claude.input) output=\(r1.snapshot.claude.output) "
        + "cacheRead=\(r1.snapshot.claude.cacheRead) cacheCreation=\(r1.snapshot.claude.cacheCreation) "
        + "total=\(r1.snapshot.claude.total)")
    print("Codex input=\(r1.snapshot.codex.input) output=\(r1.snapshot.codex.output) "
        + "cached=\(r1.snapshot.codex.cached) total=\(r1.snapshot.codex.total)")
    print("GRAND TOTAL=\(r1.snapshot.total)")
    print("tooltip=\(r1.snapshot.detailTooltip)")

    // 무변경 갱신은 재읽기 0(핵심 성질)이며 합계 불변.
    #expect(r2.stats.claudeBytesRead == 0)
    #expect(r2.stats.codexBytesRead == 0)
    #expect(r2.stats.cacheChanged == false)
    #expect(r2.snapshot.total == r1.snapshot.total)
    #expect(r1.snapshot.total > 0)
    // 단일 파일 재파싱해도 dedupe 로 합계 불변.
    #expect(r3.snapshot.total == r1.snapshot.total)
}
