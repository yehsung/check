import Foundation
import Testing
@testable import check

// MARK: - v0.2.43 — Codex 포크 복사 구간 · 캐시 스키마 v2 · Claude 12주 창
//
// 배경(2026-09-06 확정): Codex 는 스레드를 포크할 때(서브에이전트 스폰·thread/fork·review/start) 부모 rollout 의 token_count 를
// 자식의 새 파일에 그대로 다시 쓴다(CodexForkRule 주석의 소스·재현 근거). 파일별 누적치 차분 스캐너는 그 복사본을 새 소비로 세어
// 포크 한 번마다 부모 이력을 한 번 더 그날에 더했다(프로덕션 두 사용자가 계정 집계의 4.6배·3.4배, 포크 많이 쓴 날은 7~8배).
//
// 여기 픽스처는 실물 자식 파일의 배치를 그대로 본뜬다(내 맥 0.144.1 에서 thread/fork 로 재현한 두 표본):
//   0번 줄 자기 session_meta(forked_from_id = 부모, 라인 timestamp = 포크 시각 T0)
//   1번 줄 복사된 부모 session_meta(id = 부모, forked_from_id 없음)
//   복사 token_count(T0 + 0.1s, 값 그대로 · 누적 단조 증가)
//   자식 자신의 token_count(T0 + 8s 이후, 부모 마지막 누적에서 이어짐)
//
// 기존 스위트와 같은 기준 시각(2026-07-14 12:33:20 KST → 현재 월 2026-07)을 쓴다. 12주 창 = [2026-04-20 월요일 0시, ∞).

private let forkNow = Date(timeIntervalSince1970: 1_784_000_000)

/// UTC ISO 문자열 → Date(소수초 허용).
private func forkUTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = iso.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

/// Codex 라인 timestamp 포맷(UTC, 밀리초, Z) — 실물과 같은 모양.
private func forkISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

private func forkTempHome() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0243-\(UUID().uuidString)", isDirectory: true)
}

private func forkWrite(_ contents: String, to url: URL, modified: Date = forkNow) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func forkAppend(_ contents: String, to url: URL, modified: Date) {
    if let h = try? FileHandle(forWritingTo: url) {
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(contents.utf8))
        try? h.close()
    }
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func forkCodexURL(_ home: URL, _ path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

private func forkClaudeURL(_ home: URL, _ file: String) -> URL {
    home.appendingPathComponent(".claude/projects/p/\(file)", isDirectory: false)
}

/// session_meta 라인. forkedFrom 이 있으면 자기 메타(포크 표식), 없으면 표식 없는 메타(원본 세션 또는 복사된 부모 메타).
/// payload 의 timestamp 는 세션 생성 시각이고 판정에는 **라인** timestamp 만 쓴다 — 복사된 부모 메타는 payload 시각이 옛날이다.
private func forkMeta(id: String, forkedFrom: String? = nil, at date: Date, payloadTimestamp: Date? = nil) -> String {
    let marker = forkedFrom.map { ",\"forked_from_id\":\"\($0)\"" } ?? ""
    return "{\"timestamp\":\"\(forkISO(date))\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"\(marker),"
        + "\"timestamp\":\"\(forkISO(payloadTimestamp ?? date))\",\"cwd\":\"/tmp\",\"originator\":\"test\",\"cli_version\":\"0.144.6\"}}"
}

private func forkEvent(input: Int, cached: Int = 0, output: Int = 0, at date: Date) -> String {
    "{\"timestamp\":\"\(forkISO(date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),"
    + "\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(input + output)},"
    + "\"last_token_usage\":{\"input_tokens\":0,\"cached_input_tokens\":0,\"output_tokens\":0,\"reasoning_output_tokens\":0,\"total_tokens\":0},"
    + "\"model_context_window\":258400},\"rate_limits\":null}}"
}

/// 본문에 "session_meta"/"token_count" 낱말이 든 메시지 라인 — 바이트 프리체크는 통과하지만 type 이 달라 무시돼야 한다.
private func forkChatter(at date: Date) -> String {
    "{\"timestamp\":\"\(forkISO(date))\",\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\","
    + "\"content\":[{\"type\":\"input_text\",\"text\":\"session_meta token_count 를 설명해줘\"}]}}"
}

private let forkT0 = forkUTC("2026-07-10T03:00:00.000Z")   // KST 07-10 12:00 (현재 월, 오늘 아님)
private let forkParentCreated = forkUTC("2026-04-26T08:23:14.493Z")

private func micros(_ date: Date) -> Int { Int((date.timeIntervalSince1970 * 1_000_000).rounded()) }

/// 표본 자식 파일: 복사 3개(1000·5000·9000) + 자기 이벤트 2개(9300·10000 → 델타 300 + 700 = 1000).
private func forkChildLines(marker: Bool = true, copiedMeta: Bool = true) -> [String] {
    var lines = [forkMeta(id: "child", forkedFrom: marker ? "parent" : nil, at: forkT0)]
    if copiedMeta {
        lines.append(forkMeta(id: "parent", at: forkT0.addingTimeInterval(0.1), payloadTimestamp: forkParentCreated))
    }
    let burst = forkT0.addingTimeInterval(0.12)
    lines += [
        forkChatter(at: burst),
        forkEvent(input: 1000, at: burst),
        forkEvent(input: 5000, cached: 3000, at: burst),
        forkEvent(input: 9000, cached: 7000, at: burst),
        forkEvent(input: 9300, cached: 7100, at: forkT0.addingTimeInterval(8)),
        forkEvent(input: 10000, cached: 7900, at: forkT0.addingTimeInterval(20))
    ]
    return lines
}

private func forkScan(_ home: URL, cache: TokenUsageCache = TokenUsageCache(), now: Date = forkNow) -> TokenUsageIncrementalScanner.Result {
    TokenUsageIncrementalScanner.update(cache, homeDirectory: home, now: now)
}

// MARK: - 1. 복사 구간은 기준선만, 자기 턴만 센다 (포크 표식 없는 대조군은 옛 값 그대로)

@Test
func forkCopiesSetBaselineOnlyAndOwnTurnsCount() {
    let home = forkTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    forkWrite(forkChildLines().joined(separator: "\n") + "\n",
              to: forkCodexURL(home, "2026/07/10/rollout-2026-07-10T12-00-00-child.jsonl"))

    let r = forkScan(home)

    // 복사 3개(1000→5000→9000 = 8000)는 델타 0, 자기 이벤트 두 개(9000→9300→10000)만 1000.
    #expect(r.usage.codexInput == 1000)
    #expect(r.usage.codexCacheRead == 900)             // 캐시도 같은 규칙(7000→7100→7900)
    #expect(r.usage.codexDaily == ["2026-07-10": 1000])
    #expect(r.stats.codexForkCopyEvents == 3)
    let state = r.cache.codexFileStates.values.first
    #expect(state?.forkCopyDeadlineMicros == micros(forkT0) + CodexForkRule.copyWindowMicros)
    #expect(state?.prevInput == 10000)                  // 기준선은 마지막 유효 누적으로 이어진다

    // 대조군: 같은 이벤트 값·같은 시각이지만 포크 표식도 복사된 메타도 없으면 옛 규칙 그대로(첫 이벤트만 기준선) 9000.
    let control = forkTempHome()
    defer { try? FileManager.default.removeItem(at: control) }
    forkWrite(forkChildLines(marker: false, copiedMeta: false).joined(separator: "\n") + "\n",
              to: forkCodexURL(control, "2026/07/10/rollout-2026-07-10T12-00-00-plain.jsonl"))
    let c = forkScan(control)
    #expect(c.usage.codexInput == 9000)
    #expect(c.stats.codexForkCopyEvents == 0)
    #expect(c.cache.codexFileStates.values.first?.forkCopyDeadlineMicros == 0)
}

// MARK: - 2. 첫 읽기가 복사 버스트 도중에 끊겨도 다음 읽기가 마감을 물려받는다

@Test
func forkCopiesAreStillSkippedWhenTheFirstReadEndsMidBurst() {
    let home = forkTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = forkCodexURL(home, "2026/07/10/rollout-2026-07-10T12-00-00-child.jsonl")
    let lines = forkChildLines()
    let firstWrite = forkT0.addingTimeInterval(0.2)
    // 자기 메타 · 복사 메타 · 잡담 · 복사 1개까지만 써진 순간을 본다(실제로는 밀리초지만 스캐너는 그 사이에도 돌 수 있다).
    forkWrite(lines[0...3].joined(separator: "\n") + "\n", to: url, modified: firstWrite)
    let r1 = forkScan(home)
    #expect(r1.usage.codexInput == 0)
    #expect(r1.stats.codexForkCopyEvents == 1)
    let s1 = r1.cache.codexFileStates.values.first
    #expect(s1?.forkCopyDeadlineMicros == micros(forkT0) + CodexForkRule.copyWindowMicros)
    #expect((s1?.consumedOffset ?? 0) > 0)              // 복사 1개가 기준선을 세워 오프셋이 전진했다(이어읽기 경로로 간다)

    // 나머지 복사 2개 + 자기 이벤트 2개가 이어 붙는다 → 이어읽기가 마감을 물려받아 복사만 거르고 자기 몫 1000 만 센다.
    forkAppend(lines[4...].joined(separator: "\n") + "\n", to: url, modified: forkT0.addingTimeInterval(30))
    let r2 = forkScan(home, cache: r1.cache)
    #expect(r2.stats.codexBytesRead == (lines[4...].joined(separator: "\n") + "\n").utf8.count)   // 새 바이트만
    #expect(r2.stats.codexForkCopyEvents == 2)
    #expect(r2.usage.codexInput == 1000)
    #expect(r2.usage.codexDaily == ["2026-07-10": 1000])
}

// MARK: - 3. 포크의 포크: 복사된 세대가 몇이든 자기 이벤트만

@Test
func forkOfForkSkipsEveryCopiedGeneration() {
    let home = forkTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let burst = forkT0.addingTimeInterval(0.05)
    let lines = [
        forkMeta(id: "grandchild", forkedFrom: "child", at: forkT0),
        forkMeta(id: "child", forkedFrom: "parent", at: burst, payloadTimestamp: forkT0.addingTimeInterval(-3_600)),
        forkMeta(id: "parent", at: burst, payloadTimestamp: forkParentCreated),
        forkEvent(input: 1000, at: burst),     // 조부모 이력
        forkEvent(input: 2000, at: burst),
        forkEvent(input: 2500, at: burst),     // 부모 이력(조부모 누적에서 이어짐)
        forkEvent(input: 4000, at: burst),
        forkEvent(input: 4100, at: forkT0.addingTimeInterval(9))   // 자기 첫 턴 → 100
    ]
    forkWrite(lines.joined(separator: "\n") + "\n", to: forkCodexURL(home, "2026/07/10/rollout-2026-07-10T12-00-00-gc.jsonl"))
    let r = forkScan(home)
    #expect(r.usage.codexInput == 100)
    #expect(r.stats.codexForkCopyEvents == 4)
}

// MARK: - 4. 표식이 없어도 두 번째 session_meta 가 포크의 증거다

@Test
func secondSessionMetaAloneMarksAFork() {
    let home = forkTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    forkWrite(forkChildLines(marker: false, copiedMeta: true).joined(separator: "\n") + "\n",
              to: forkCodexURL(home, "2026/07/10/rollout-2026-07-10T12-00-00-nomarker.jsonl"))
    let r = forkScan(home)
    #expect(r.usage.codexInput == 1000)
    #expect(r.stats.codexForkCopyEvents == 3)
    #expect(r.cache.codexFileStates.values.first?.forkCopyDeadlineMicros == micros(forkT0) + CodexForkRule.copyWindowMicros)
}

// MARK: - 5. 5초 창의 트레이드오프 — 창 밖의 자기 이벤트는 센다, 창 안의 것은 놓친다(문서화된 손실)

@Test
func copyWindowBoundaryIsFiveSecondsAfterTheOwnMeta() {
    let home = forkTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let lines = [
        forkMeta(id: "child", forkedFrom: "parent", at: forkT0),
        forkMeta(id: "parent", at: forkT0.addingTimeInterval(0.1), payloadTimestamp: forkParentCreated),
        forkEvent(input: 1000, at: forkT0.addingTimeInterval(0.1)),
        forkEvent(input: 5000, at: forkT0.addingTimeInterval(5.0)),      // 마감 정각 → 아직 복사 구간(놓친다)
        forkEvent(input: 5010, at: forkT0.addingTimeInterval(5.001)),    // 1ms 뒤(라인 timestamp 정밀도) → 자기 이벤트 → 델타 10
        forkEvent(input: 5100, at: forkT0.addingTimeInterval(60))        // → 90
    ]
    forkWrite(lines.joined(separator: "\n") + "\n", to: forkCodexURL(home, "2026/07/10/rollout-2026-07-10T12-00-00-edge.jsonl"))
    let r = forkScan(home)
    #expect(r.usage.codexInput == 100)
    #expect(r.stats.codexForkCopyEvents == 2)
}

// MARK: - 6. 시계·표식 파싱 순수 함수

@Test
func forkRuleParsesTimestampsAndMarkers() {
    // 실물 타임스탬프: 밀리초 3자리. 소수부가 없거나 6자리를 넘어도 마이크로초로 정규화한다.
    #expect(CodexForkRule.timestampMicros(fromTimestamp: "2026-09-06T05:35:27.749Z") == 1_788_672_927_749_000)
    #expect(CodexForkRule.timestampMicros(fromTimestamp: "2026-09-06T05:35:27Z") == 1_788_672_927_000_000)
    #expect(CodexForkRule.timestampMicros(fromTimestamp: "2026-09-06T05:35:27.1234567Z") == 1_788_672_927_123_456)
    #expect(CodexForkRule.timestampMicros(fromTimestamp: "1970-01-01T00:00:00.000Z") == 0)
    #expect(CodexForkRule.timestampMicros(fromTimestamp: "2026-13-06T05:35:27Z") == nil)
    #expect(CodexForkRule.timestampMicros(fromTimestamp: "garbage") == nil)
    // 윤년: 2028-02-29 는 유효하고 하루(86,400s) 뒤가 3월 1일이다.
    let feb29 = CodexForkRule.timestampMicros(fromTimestamp: "2028-02-29T00:00:00Z")!
    #expect(CodexForkRule.timestampMicros(fromTimestamp: "2028-03-01T00:00:00Z") == feb29 + 86_400_000_000)

    let own: [String: Any] = ["type": "session_meta", "payload": ["id": "c", "forked_from_id": "p"]]
    let viaParent: [String: Any] = ["type": "session_meta", "payload": ["id": "c", "parent_thread_id": "p"]]
    let plain: [String: Any] = ["type": "session_meta", "payload": ["id": "c"]]
    let nullMarker: [String: Any] = ["type": "session_meta", "payload": ["id": "c", "forked_from_id": NSNull()]]
    let notMeta: [String: Any] = ["type": "response_item", "payload": ["forked_from_id": "p"]]
    #expect(CodexForkRule.hasForkMarker(own))
    #expect(CodexForkRule.hasForkMarker(viaParent))
    #expect(!CodexForkRule.hasForkMarker(plain))
    #expect(!CodexForkRule.hasForkMarker(nullMarker))
    #expect(CodexForkRule.isSessionMeta(own) && !CodexForkRule.isSessionMeta(notMeta))

    // 추적기: 첫 줄의 자기 메타에 표식이 있으면 마감 = 그 줄 시각 + 5s. 표식이 없으면 두 번째 메타가 자기 메타 시각으로 마감을 세운다.
    var t = CodexForkTracker(startedAtZero: true, deadlineMicros: 0)
    t.observeSessionMeta(["type": "session_meta", "timestamp": "2026-09-06T05:35:27.622Z", "payload": ["id": "c", "forked_from_id": "p"]])
    #expect(t.deadlineMicros == 1_788_672_927_622_000 + 5_000_000)
    var u = CodexForkTracker(startedAtZero: true, deadlineMicros: 0)
    u.observeSessionMeta(["type": "session_meta", "timestamp": "2026-09-06T05:35:27.622Z", "payload": ["id": "c"]])
    #expect(u.deadlineMicros == 0)
    u.linesSeen = 1
    u.observeSessionMeta(["type": "session_meta", "timestamp": "2026-09-06T05:35:27.749Z", "payload": ["id": "p"]])
    #expect(u.deadlineMicros == 1_788_672_927_622_000 + 5_000_000)   // 자기 메타 시각 기준(복사 메타 시각이 아니라)
    #expect(u.isCopy(eventTimestamp: "2026-09-06T05:35:32.622Z"))
    #expect(!u.isCopy(eventTimestamp: "2026-09-06T05:35:32.622001Z"))
    // 이어읽기(첫 줄이 아님)에서 만난 메타는 무조건 복사된 부모 메타 — 그 줄 시각으로 마감.
    var v = CodexForkTracker(startedAtZero: false, deadlineMicros: 0)
    v.observeSessionMeta(["type": "session_meta", "timestamp": "2026-09-06T05:35:27.749Z", "payload": ["id": "p"]])
    #expect(v.deadlineMicros == 1_788_672_927_749_000 + 5_000_000)
    // 시계를 못 읽으면 마감을 세우지 않는다(포크 아님으로 흘러간다 — 크래시·유실 없음).
    var w = CodexForkTracker(startedAtZero: true, deadlineMicros: 0)
    w.observeSessionMeta(["type": "session_meta", "payload": ["id": "c", "forked_from_id": "p"]])
    #expect(w.deadlineMicros == 0)
    #expect(!w.isCopy(eventTimestamp: "2026-09-06T05:35:27.749Z"))
}

// MARK: - 7. 영속: 12원소 튜플 왕복 + 11원소(v4 형식) 관용 + 세대 게이트

@Test
func codexFileProgressRoundTripsForkDeadlineAndToleratesElevenElementTuples() throws {
    var cache = TokenUsageCache()
    cache.codexFileStates["/c/rollout.jsonl"] = CodexFileProgress(
        size: 20, mtimeMicros: 111, consumedOffset: 15, prevInput: 300, prevOutput: 40, prevCached: 120,
        monthKey: "2026-07", monthInput: 250, monthOutput: 50, monthCached: 90, dayContrib: ["2026-07-14": 42],
        forkCopyDeadlineMicros: 1_788_672_932_622_000)
    let data = try JSONEncoder().encode(cache)
    #expect(String(decoding: data, as: UTF8.self).contains("[20,111,15,300,40,120,\"2026-07\",250,50,90,{\"2026-07-14\":42},1788672932622000]"))
    #expect(try JSONDecoder().decode(TokenUsageCache.self, from: data) == cache)

    // 같은 세대 안에서 11원소로 잘린 튜플은 마감 0(포크 아님)으로 읽힌다 — 새 형식의 잘린 튜플 방어(옛 세대는 아래 게이트가 막는다).
    let eleven = """
    {"codexFileStates":{"/c/rollout.jsonl":[20,111,15,300,40,120,"2026-07",250,50,90,{"2026-07-14":42}]},\
    "codexSchemaVersion":\(TokenUsageCache.currentCodexSchemaVersion)}
    """
    let decoded = try JSONDecoder().decode(TokenUsageCache.self, from: Data(eleven.utf8))
    #expect(decoded.codexFileStates["/c/rollout.jsonl"]?.forkCopyDeadlineMicros == 0)
    #expect(decoded.codexFileStates["/c/rollout.jsonl"]?.dayContrib == ["2026-07-14": 42])
}

/// 세대 게이트 둘 다 올랐다. 되돌리면 (a) 복사 구간을 새 소비로 센 v4 codex 상태가 오프셋과 함께 살아남아 산식만 고쳐도 숫자가 안 고쳐지고,
/// (b) Claude 엔트리가 현재 월치뿐인 옛 캐시가 살아남아 12주 잔디의 지난 기록이 되살아나지 않는다.
@Test
func cacheGenerationsAreBumpedSoStaleForkCountsAreReparsed() throws {
    #expect(TokenUsageCacheStore.currentSchemaVersion == 2)
    #expect(TokenUsageCache.currentCodexSchemaVersion == 5)

    // v0.2.41/42 가 쓴 v4 모놀리식: 11원소 튜플이 그대로 디코드는 되지만 세대가 달라 codex 상태만 폐기(Claude 상태 보존).
    let v4 = """
    {"claudeFileStates":{"/a/b.jsonl":[10,999,8]},"claudeEntries":{"msg\\u0000req":[20260722103000,1,2,3,4]},\
    "codexFileStates":{"/p/rollout.jsonl":[10,20,30,300,40,120,"2026-09",22508601512,0,0,{"2026-09-02":14010966015}]},\
    "codexSchemaVersion":4}
    """
    let decoded = try JSONDecoder().decode(TokenUsageCache.self, from: Data(v4.utf8))
    #expect(decoded.codexFileStates.isEmpty)
    #expect(decoded.claudeFileStates["/a/b.jsonl"] != nil)
    #expect(decoded.codexSchemaVersion == 5)

    // 스토어 레이아웃 게이트: 핫 파일의 schemaVersion 이 1(v0.2.38~42)이면 두 파일을 통째로 버린다(→ 전체 재스캔).
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("check-v0243-gate-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let base = dir.appendingPathComponent("cache.json", isDirectory: false)
    var cache = TokenUsageCache()
    cache.claudeEntries["m\u{0}r"] = ClaudeEntry(ts14: 20_260_710_000_000, input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
    #expect(TokenUsageCacheStore.save(cache, parts: .all, to: base))
    #expect(TokenUsageCacheStore.load(from: base) == cache)
    let stateURL = TokenUsageCacheStore.stateURL(for: base)
    var hot = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
    hot["schemaVersion"] = 1
    try JSONSerialization.data(withJSONObject: hot).write(to: stateURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
}

// MARK: - 8. 진단: 포크 파일 수·복사 토큰, 앱 산식 항등식, 업로드 키

@Test
func diagnosticsCountForkFilesAndCopyTokensAndKeepTheAppIdentity() throws {
    let home = forkTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    forkWrite(forkChildLines().joined(separator: "\n") + "\n",
              to: forkCodexURL(home, "2026/07/10/rollout-2026-07-10T12-00-00-child.jsonl"))
    // 포크 아닌 보통 파일 하나(첫 이벤트 기준선, 두 번째가 델타 50).
    forkWrite([
        forkMeta(id: "solo", at: forkT0.addingTimeInterval(-86_400)),
        forkEvent(input: 700, at: forkT0.addingTimeInterval(-86_400 + 5)),
        forkEvent(input: 750, at: forkT0.addingTimeInterval(-86_400 + 60))
    ].joined(separator: "\n") + "\n", to: forkCodexURL(home, "2026/07/09/rollout-2026-07-09T12-00-00-solo.jsonl"))

    let d = CodexUsageDiagnosticsScanner.compute(homeDirectory: home, month: "2026-07", appBuild: 52)
    #expect(d.filesTotal == 2)
    #expect(d.filesMonth == 2)
    #expect(d.forkFiles == 1)
    // 복사 3개가 옛 산식이라면 더했을 몫: 첫 복사는 기준선(0), 1000→5000, 5000→9000 = 8000.
    #expect(d.forkCopyTokens == 8000)
    #expect(d.dedupTotal == 1000 + 50)
    #expect(d.dupEvents == 0)
    // 이월 수정 전 산식(legacy)은 포크 규칙도 없던 세대 — 첫 이벤트 전액과 복사 구간까지 다 더한다: 1000+4000+4000+300+700 + 700+50.
    #expect(d.legacyTotal == 10_000 + 750)
    // 앱 산식 항등식: 진단의 dedupTotal + dupTokens == 프로덕션 스캐너의 Codex 합(같은 홈·같은 월).
    let scanned = TokenUsageScanner.scan(homeDirectory: home, now: forkNow)
    #expect(d.dedupTotal + d.dupTokens == scanned.codexTotal)
    #expect(scanned.codexTotal == 1050)

    // 업로드 본문: 진단이 실리면 두 키가 snake_case 로 나가고, 진단이 nil 이면 키 자체가 없다(서버 값 보존 규약).
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let with = TokenUsageUpsertRequest(
        userId: "U", month: "2026-07", deviceId: "D", claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 1050, codexOutput: 0, total: 1050, todayTotal: 0, todayDate: "2026-07-14", diagnostics: d)
    let object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(with)) as? [String: Any])
    #expect(object["codex_diag_fork_files"] as? Int == 1)
    #expect(object["codex_diag_fork_tokens"] as? Int == 8000)
    let without = TokenUsageUpsertRequest(
        userId: "U", month: "2026-07", deviceId: "D", claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 1050, codexOutput: 0, total: 1050, todayTotal: 0, todayDate: "2026-07-14", diagnostics: nil)
    let bare = try #require(try JSONSerialization.jsonObject(with: encoder.encode(without)) as? [String: Any])
    #expect(bare["codex_diag_fork_files"] == nil && bare["codex_diag_fork_tokens"] == nil)

    // 진단 스냅샷 Codable 하위호환: 두 키가 없는 옛 페이로드도 0 으로 읽힌다.
    let old = try JSONDecoder().decode(CodexUsageDiagnostics.self, from: Data("{\"filesTotal\":3}".utf8))
    #expect(old.forkFiles == 0 && old.forkCopyTokens == 0 && old.filesTotal == 3)
}

// MARK: - 9. Claude 12주 창 — 스캔 창은 잔디 창과 같고, 월 합계는 그대로 현재 월

private func forkClaudeLine(id: String, at date: Date, input: Int) -> String {
    "{\"type\":\"assistant\",\"timestamp\":\"\(forkISO(date))\",\"requestId\":\"\(id)\","
    + "\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":0}}}"
}

@Test
func claudeScanWindowEqualsTheGrassWindow() {
    let w = TokenUsageIncrementalScanner.windowBounds(now: forkNow)
    #expect(w.start == WorkDailyGrid.windowStart(now: forkNow))
    #expect(w.startKey == "2026-04-20")                                  // 2026-07-14(화) 의 주 월요일 07-13 − 12주
    #expect(w.start == forkUTC("2026-04-19T15:00:00Z"))                  // KST 04-20 00:00
    #expect(w.retentionStart == w.start.addingTimeInterval(-48 * 3_600))
    // 창은 언제나 월 시작보다 앞이다(84일 > 한 달) — totals 의 "월 안 엔트리는 창 안" 전제.
    for offset in stride(from: 0, through: 400, by: 7) {
        let now = forkNow.addingTimeInterval(TimeInterval(offset) * 86_400)
        #expect(TokenUsageIncrementalScanner.windowBounds(now: now).start < TokenUsageIncrementalScanner.monthBounds(now: now).start)
    }
}

@Test
func claudeDailyCoversTwelveWeeksWhileMonthTotalsStayMonthly() {
    let home = forkTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let inMonth = forkUTC("2026-07-09T03:00:00Z")      // KST 07-09 12:00 (현재 월)
    let inWindow = forkUTC("2026-06-04T03:00:00Z")     // KST 06-04 (지난달, 창 안) — v0.2.42 까지는 저장조차 안 됐다
    let outWindow = forkUTC("2026-04-05T03:00:00Z")    // KST 04-05 (창 앞, 보관 하한 04-18 밖)
    forkWrite([
        forkClaudeLine(id: "m", at: inMonth, input: 1000),
        forkClaudeLine(id: "w", at: inWindow, input: 200),
        forkClaudeLine(id: "o", at: outWindow, input: 30)
    ].joined(separator: "\n") + "\n", to: forkClaudeURL(home, "s.jsonl"))
    // 창 안이지만 월 시작 이전에 마지막으로 손댄 파일(mtime −40일): v0.2.42 까지는 프리필터가 통째로 건너뛰었다.
    forkWrite(forkClaudeLine(id: "old-file", at: inWindow.addingTimeInterval(3_600), input: 7) + "\n",
              to: forkClaudeURL(home, "old.jsonl"), modified: forkNow.addingTimeInterval(-40 * 86_400))
    // 창 앞에 마지막으로 손댄 파일(mtime −100일)은 여전히 열지 않는다.
    forkWrite(forkClaudeLine(id: "stale", at: inMonth, input: 999_999) + "\n",
              to: forkClaudeURL(home, "stale.jsonl"), modified: forkNow.addingTimeInterval(-100 * 86_400))

    let r = forkScan(home)

    #expect(r.usage.month == "2026-07")
    #expect(r.usage.windowStart == "2026-04-20")
    // 로그 완전성 하한: 창 안에서 본 가장 오래된 파일(old.jsonl, mtime −40일 = KST 06-04) 의 **다음 날**.
    #expect(r.usage.claudeCompleteFrom == "2026-06-05")
    #expect(r.usage.claudeInput == 1000)                                  // 월 합계는 현재 월만(6월분 제외)
    #expect(r.usage.claudeDaily == ["2026-07-09": 1000, "2026-06-04": 207])   // 일별은 창 안 전부(6/4 = 200 + old.jsonl 의 7)
    #expect(r.cache.claudeEntries.count == 3)                             // m · w · old-file. o(창 앞)는 저장조차 안 된다
    #expect(r.stats.claudeFilesRead == 2)                                 // s.jsonl · old.jsonl (stale.jsonl 은 프리필터 스킵)
    #expect(r.usage.todayTotal == 0)

    // 재스캔은 재읽기 0 · 퇴거 0(창 안은 전부 보관).
    let r2 = forkScan(home, cache: r.cache)
    #expect(r2.stats.claudeBytesRead == 0 && r2.stats.cacheChanged == false)
    #expect(r2.usage == r.usage)
}

@Test
func dailyUploadSendsWindowDaysAndFallsBackToMonthForOldSnapshots() throws {
    var usage = TokenUsageMonthly(month: "2026-07")
    usage.windowStart = "2026-04-20"
    usage.claudeDaily = ["2026-04-19": 1, "2026-04-20": 2, "2026-06-04": 3, "2026-07-01": 4]
    usage.codexDaily = ["2026-07-02": 5]
    let account = CodexAccountUsage(
        fetchedAt: forkNow, lifetimeTokens: 1, buckets: ["2026-03-01": 9, "2026-05-05": 6, "2026-07-03": 7])
    let values = TokenUsageDailyUpload.values(usage: usage, account: account)
    #expect(Set(values.keys) == ["2026-04-20", "2026-06-04", "2026-07-01", "2026-07-02", "2026-05-05", "2026-07-03"])
    #expect(values["2026-04-19"] == nil)                                  // 창 앞(straddle 부분값)은 보내지 않는다
    #expect(values["2026-05-05"] == TokenUsageDailyValue(claude: 0, codex: 0, codexAccount: 6))
    #expect(values["2026-06-04"] == TokenUsageDailyValue(claude: 3, codex: 0, codexAccount: nil))

    // 옛 스냅샷(windowStart 없음)은 월 1일이 창 시작 → 옛 월 접두어 규칙과 같은 집합.
    usage.windowStart = ""
    #expect(usage.windowStartDay == "2026-07-01")
    #expect(Set(TokenUsageDailyUpload.values(usage: usage, account: account).keys) == ["2026-07-01", "2026-07-02", "2026-07-03"])

    // 로그 완전성 하한(claudeCompleteFrom): 그 앞의 날은 Claude 값을 **nil**(키 생략)로 보내고, Claude 값뿐인 날은 아예 보내지 않는다.
    // Codex 일별·계정 버킷은 transcript 보관과 무관하므로 그대로 싣는다.
    usage.windowStart = "2026-04-20"
    usage.claudeCompleteFrom = "2026-06-01"
    let guarded = TokenUsageDailyUpload.values(usage: usage, account: account)
    #expect(Set(guarded.keys) == ["2026-05-05", "2026-06-04", "2026-07-01", "2026-07-02", "2026-07-03"])   // 04-20(Claude 뿐·하한 앞)은 빠진다
    #expect(guarded["2026-05-05"] == TokenUsageDailyValue(claude: nil, codex: 0, codexAccount: 6))
    #expect(guarded["2026-06-04"] == TokenUsageDailyValue(claude: 3, codex: 0, codexAccount: nil))
    let guardedRows = TokenUsageDailyUpload.rows(userID: "u", deviceID: "MAC-A", days: ["2026-05-05", "2026-06-04"], values: guarded)
    #expect(guardedRows.map(\.claudeTotal) == [nil, 3])

    // 스냅샷 Codable: windowStart·claudeCompleteFrom 이 왕복하고, 키가 없는 옛 스냅샷은 빈 문자열로 복원된다.
    let data = try JSONEncoder().encode(usage)
    #expect(try JSONDecoder().decode(TokenUsageMonthly.self, from: data) == usage)
    let legacy = try JSONDecoder().decode(TokenUsageMonthly.self, from: Data("{\"month\":\"2026-07\"}".utf8))
    #expect(legacy.windowStart == "" && legacy.windowStartDay == "2026-07-01" && legacy.claudeCompleteFrom == "")
    #expect(TokenUsageIncrementalScanner.claudeCompleteFromKey(oldestMtimeMicros: nil) == "")
    #expect(TokenUsageIncrementalScanner.claudeCompleteFromKey(oldestMtimeMicros: micros(forkUTC("2026-06-04T14:59:59Z"))) == "2026-06-05")   // KST 06-04 23:59:59
    #expect(TokenUsageIncrementalScanner.claudeCompleteFromKey(oldestMtimeMicros: micros(forkUTC("2026-06-04T15:00:00Z"))) == "2026-06-06")   // KST 06-05 00:00
}

/// ★ PostgREST 는 배열 본문의 키 집합이 행마다 다르면 400 PGRST102 로 본문 전체를 거절한다(v0.2.41 리뷰 P0). claude_total 도 빠질 수 있게 된
/// v0.2.43 부터는 묶음이 (claude 유무 × 계정 유무) 넷이다 — 스텁이 혼합 키를 물어뜯으므로 묶음을 갈라야만 네 행이 전부 올라간다.
@MainActor
@Test
func dailyUpsertSplitsRowsByBothOptionalKeysSoEveryBodyIsUniform() async throws {
    let host = "v0243-daily-shapes"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: URLSession(configuration: .stubbed))
    let rows = [
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-07-01", deviceId: "MAC-A", claudeTotal: 100, codexTotal: 0, codexAccount: 900),
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-07-02", deviceId: "MAC-A", claudeTotal: 0, codexTotal: 7, codexAccount: nil),
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-06-01", deviceId: "MAC-A", claudeTotal: nil, codexTotal: 0, codexAccount: 5),   // 하한 앞·계정만
        TokenUsageDailyUpsertRow(userId: "U", day: "2026-06-02", deviceId: "MAC-A", claudeTotal: nil, codexTotal: 3, codexAccount: nil) // 하한 앞·codex 만
    ]
    try await service.upsertTokenUsageDaily(accessToken: "access-token", rows: rows)

    let bodies = URLProtocolStub.bodies(forHost: host)
        .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [[String: Any]] }
    #expect(bodies.count == 4, "키 모양이 넷이면 요청도 넷이어야 한다: \(bodies.count)")
    for body in bodies {
        #expect(Set(body.map { Set($0.keys) }).count == 1, "한 본문 안의 키 집합이 행마다 다르다 — 서버가 400 으로 통째 거절한다")
    }
    let all = bodies.flatMap { $0 }
    #expect(all.count == 4)
    let june1 = try #require(all.first { $0["day"] as? String == "2026-06-01" })
    #expect(june1["claude_total"] == nil)                       // 키 자체가 없다 — 서버의 옛 완전값 보존
    #expect(june1["codex_account"] as? Int == 5)
    #expect(Set(june1.keys) == ["user_id", "day", "device_id", "codex_total", "codex_account"])
    let june2 = try #require(all.first { $0["day"] as? String == "2026-06-02" })
    #expect(Set(june2.keys) == ["user_id", "day", "device_id", "codex_total"])
    let july1 = try #require(all.first { $0["day"] as? String == "2026-07-01" })
    #expect(july1["claude_total"] as? Int == 100)
    // 묶음 순서는 결정적(claude·계정 → claude → 계정 → 없음).
    #expect(bodies.map { $0.first?["day"] as? String } == ["2026-07-01", "2026-07-02", "2026-06-01", "2026-06-02"])
}

// MARK: - 10. 실물 표본(opt-in) — 내 맥에서 thread/fork 로 만든 자식 파일 두 개는 이번 달 기여가 0 이어야 한다

/// `CHECK_FORK_SAMPLE_HOME=<CODEX_HOME>` 일 때만 돈다(기본은 즉시 통과). 그 디렉터리의 `sessions/**` 에 실물 포크 자식 표본을
/// 이번 달 경로로, 부모는 원래 날짜 경로로 둔 뒤 스캐너를 돌린다. 출력은 숫자뿐이다(대화 본문은 읽지도 찍지도 않는다).
@Test
func forkSamplesFromRealCodexHomeContributeZero() {
    guard let sample = ProcessInfo.processInfo.environment["CHECK_FORK_SAMPLE_HOME"], !sample.isEmpty else { return }
    let codexHome = URL(fileURLWithPath: sample, isDirectory: true)
    let now = Date()
    let r = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: codexHome, codexHome: codexHome, now: now)
    let states = r.cache.codexFileStates.values.filter { $0.monthKey == r.usage.month }
    print("FORK_SAMPLE month=\(r.usage.month) filesStatted=\(r.stats.codexFilesStatted) filesRead=\(r.stats.codexFilesRead) "
          + "copyEvents=\(r.stats.codexForkCopyEvents) codexInput=\(r.usage.codexInput) codexOutput=\(r.usage.codexOutput) "
          + "forkFiles=\(states.filter { $0.forkCopyDeadlineMicros > 0 }.count) "
          + "contribs=\(states.map(\.monthContribTotal).sorted())")
    #expect(r.stats.codexFilesRead >= 2)
    #expect(r.stats.codexForkCopyEvents > 0)
    #expect(r.usage.codexInput == 0)
    #expect(r.usage.codexOutput == 0)
    #expect(states.allSatisfy { $0.monthContribTotal == 0 })
    let d = CodexUsageDiagnosticsScanner.compute(homeDirectory: codexHome, codexHome: codexHome, month: r.usage.month, appBuild: 52)
    print("FORK_SAMPLE diag forkFiles=\(d.forkFiles) forkCopyTokens=\(d.forkCopyTokens) dedupTotal=\(d.dedupTotal) legacyTotal=\(d.legacyTotal)")
    #expect(d.forkFiles == states.filter { $0.forkCopyDeadlineMicros > 0 }.count)
    #expect(d.dedupTotal + d.dupTokens == r.usage.codexTotal)
}
