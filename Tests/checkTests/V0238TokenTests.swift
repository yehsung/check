import AppKit
import Foundation
import Testing
@testable import check

// MARK: - v0.2.38 트랙 γ: 토큰 사용량 캐시 가벼워지기 (Q5 저장 스로틀 · Q6 48h 보관 경계 · M4 해시 키/핫·콜드 분리)
//
// 계측으로 확정된 출발점(이 맥, v0.2.37): dedupe 캐시 ≈16MB 상주(엔트리 70,766 개 중 73% 가 지난달), 팝오버 열림 중
// 30초마다 1,595 파일 순회 + 변경 시 7.6MB JSON 전체 재기록(21분에 64MB 디스크 쓰기), 첫 스캔 peak footprint 405MB.
//
// 여기 테스트는 전부 임시 홈의 픽스처만 읽는다(~/.claude/projects 실데이터 금지). defaults 스위트 이름은 고정이다.

/// 스캔 기준 시각(고정): 2026-07-14 12:33:20 KST → 현재 KST 월 "2026-07".
/// 월 시작 = KST 07-01 00:00 = UTC 06-30 15:00. 보관 경계(Q6) = 월 시작 − 48h = KST 06-29 00:00 = UTC 06-28 15:00.
private let v0238Now = Date(timeIntervalSince1970: 1_784_000_000)
private let v0238MonthStart = v0238UTC("2026-06-30T15:00:00Z")

private func v0238UTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

private func v0238ISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

/// 스캐너와 같은 산식의 ts14(UTC YYYYMMDDHHMMSS).
private func v0238TS14(_ date: Date) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return ((((c.year! * 100 + c.month!) * 100 + c.day!) * 100 + c.hour!) * 100 + c.minute!) * 100 + c.second!
}

private func v0238TempDir(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0238-\(tag)-\(UUID().uuidString)", isDirectory: true)
}

/// 격리 캐시 베이스 URL(스토어가 여기서 .state.json / .entries.json 을 파생한다).
private func v0238CacheURL(in dir: URL) -> URL {
    dir.appendingPathComponent("cache.json", isDirectory: false)
}

private func v0238Write(_ contents: String, to url: URL, modified: Date = v0238Now) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func v0238Append(_ contents: String, to url: URL, modified: Date) {
    if let h = try? FileHandle(forWritingTo: url) {
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(contents.utf8))
        try? h.close()
    }
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func v0238ClaudeURL(_ home: URL, _ project: String, _ file: String) -> URL {
    home.appendingPathComponent(".claude/projects/\(project)/\(file)", isDirectory: false)
}

private func v0238CodexURL(_ home: URL, _ path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

private func v0238ClaudeLine(id: String, req: String, at date: Date, usage: String, filler: Int = 0) -> String {
    let content = filler > 0 ? ",\"content\":[{\"type\":\"text\",\"text\":\"\(String(repeating: "x", count: filler))\"}]" : ""
    return "{\"type\":\"assistant\",\"timestamp\":\"\(v0238ISO(date))\",\"requestId\":\"\(req)\","
        + "\"message\":{\"id\":\"\(id)\",\"usage\":\(usage)\(content)}}"
}

private func v0238UserLine(at date: Date) -> String {
    "{\"type\":\"user\",\"timestamp\":\"\(v0238ISO(date))\",\"message\":{\"role\":\"user\",\"content\":\"hi\"}}"
}

private func v0238CodexLine(input: Int, output: Int, at date: Date) -> String {
    "{\"timestamp\":\"\(v0238ISO(date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
        + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":0,"
        + "\"output_tokens\":\(output),\"total_tokens\":0}}}}"
}

private func v0238Defaults(_ name: String) -> UserDefaults {
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

// MARK: - 오라클 픽스처 (구현 전 코드로 채취한 값과 동일해야 한다)

/// 결정적 픽스처. Claude 두 프로젝트(포크 복제·스트리밍 스냅샷·지난달 48h 안/밖·오늘·부분 라인) + Codex rollout 하나.
/// 반환: (a.jsonl 완결 바이트, b.jsonl 바이트, rollout 바이트).
private func v0238WriteOracleFixture(into home: URL) -> (aConsumed: Int, bSize: Int, codexSize: Int) {
    let inMonth = v0238Now.addingTimeInterval(-5 * 86_400)              // 07-09 KST
    let today = v0238UTC("2026-07-14T02:00:00Z")                         // KST 07-14 11:00 (오늘)
    let prevWithin48h = v0238MonthStart.addingTimeInterval(-3_600)      // KST 06-30 23:00 (지난달, 보관 창 안)
    let prevOutside48h = v0238MonthStart.addingTimeInterval(-10 * 86_400) // KST 06-21 (지난달, 월 시작 − 48h 밖 — v0.2.43 부터는 12주 창 안이라 보관, 합계 밖)

    let k1 = v0238ClaudeLine(id: "msg_k1", req: "req_k1", at: inMonth,
        usage: "{\"input_tokens\":100,\"output_tokens\":50,\"cache_read_input_tokens\":10,\"cache_creation_input_tokens\":5}")
    let k2a = v0238ClaudeLine(id: "msg_k2", req: "req_k2", at: inMonth, usage: "{\"input_tokens\":10,\"output_tokens\":2}")
    let k2b = v0238ClaudeLine(id: "msg_k2", req: "req_k2", at: inMonth, usage: "{\"input_tokens\":11,\"output_tokens\":688}")
    let k3 = v0238ClaudeLine(id: "msg_k3", req: "req_k3", at: prevWithin48h, usage: "{\"input_tokens\":1000}")
    let k4 = v0238ClaudeLine(id: "msg_k4", req: "req_k4", at: prevOutside48h, usage: "{\"input_tokens\":5000}")
    let k5 = v0238ClaudeLine(id: "msg_k5", req: "req_k5", at: today, usage: "{\"input_tokens\":7,\"output_tokens\":3}")
    let partial = "{\"type\":\"assistant\",\"timestamp\":\"" // 개행 없는 꼬리(아직 쓰는 중)

    let aComplete = [k1, v0238UserLine(at: inMonth), k2a, k1, k2b, k3, k4].joined(separator: "\n") + "\n"
    v0238Write(aComplete + partial, to: v0238ClaudeURL(home, "proj-a", "a.jsonl"))
    let b = [k1, k5].joined(separator: "\n") + "\n"
    v0238Write(b, to: v0238ClaudeURL(home, "proj-b", "b.jsonl"))

    let codex = [
        v0238CodexLine(input: 900, output: 100, at: v0238UTC("2026-07-05T00:00:00Z")),   // cum 1000 → 첫 관측(기준선)
        v0238CodexLine(input: 1400, output: 100, at: v0238UTC("2026-07-05T01:00:00Z")),  // cum 1500 → +500 (7월)
        "{\"payload\":{\"type\":\"token_count\",\"info\":{\"rate_limits\":{}}}}",          // 무효(건너뜀)
        v0238CodexLine(input: 1600, output: 100, at: today)                              // cum 1700 → +200 (오늘)
    ].joined(separator: "\n") + "\n"
    v0238Write(codex, to: v0238CodexURL(home, "2026/07/05/rollout-2026-07-05T00-00-00-aaaa.jsonl"))
    return (aComplete.utf8.count, b.utf8.count, codex.utf8.count)
}

/// 구현 전(v0.2.37) 스캐너로 위 픽스처를 돌려 채취한 오라클. 합계·오늘분·파일 진행 상태가 구현 후에도 그대로여야 한다.
/// (엔트리 보관 수는 Q6 로 5 → 4 가 되는 것이 의도된 변화라 여기 오라클에 넣지 않는다.)
@Test
func fixtureScanTotalsAndFileProgressMatchPreChangeOracle() {
    let home = v0238TempDir("oracle")
    defer { try? FileManager.default.removeItem(at: home) }
    let sizes = v0238WriteOracleFixture(into: home)

    let r = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)

    // Claude: k1(100/50/10/5, 세 번 등장해도 1회) + k2(max-output 688 레코드의 11) + k5(7/3). k3·k4 는 지난달이라 합계 밖.
    #expect(r.usage.claudeInput == 118)
    #expect(r.usage.claudeOutput == 741)
    #expect(r.usage.claudeCacheRead == 10)
    #expect(r.usage.claudeCacheCreation == 5)
    // Codex: 첫 관측 기준선 → +500 +200. 무효 라인은 기준선을 건드리지 않는다.
    #expect(r.usage.codexInput == 700)
    #expect(r.usage.codexOutput == 0)
    #expect(r.usage.total == 1_574)
    // 오늘: k5(10) + Codex 오늘 델타(200).
    #expect(r.usage.todayDate == "2026-07-14")
    #expect(r.usage.todayTotal == 210)
    #expect(r.usage.month == "2026-07")

    // 파일 진행 상태: a 는 부분 라인 앞까지, b 와 rollout 은 끝까지.
    let claudeStates = Dictionary(uniqueKeysWithValues: r.cache.claudeFileStates.map { (($0.key as NSString).lastPathComponent, $0.value) })
    #expect(claudeStates["a.jsonl"]?.consumedOffset == sizes.aConsumed)
    #expect(claudeStates["a.jsonl"]?.size == sizes.aConsumed + "{\"type\":\"assistant\",\"timestamp\":\"".utf8.count)
    #expect(claudeStates["b.jsonl"]?.consumedOffset == sizes.bSize)
    #expect(r.cache.codexFileStates.values.first?.consumedOffset == sizes.codexSize)
    #expect(r.cache.codexFileStates.values.first?.prevCumulative == 1_700)
    #expect(r.cache.codexFileStates.values.first?.monthContribTotal == 700)
    #expect(r.cache.codexFileStates.values.first?.dayContrib == ["2026-07-14": 200, "2026-07-05": 500])   // v0.2.41: 일별 맵(과제 E 선행)
    #expect(r.stats.claudeFilesRead == 2)
    #expect(r.stats.codexFilesRead == 1)
    #expect(r.stats.cacheChanged == true)

    // 무변경 재갱신: 재읽기 0, 캐시 무변경, 합계 동일.
    let r2 = TokenUsageIncrementalScanner.update(r.cache, homeDirectory: home, now: v0238Now)
    #expect(r2.stats.claudeBytesRead == 0)
    #expect(r2.stats.codexBytesRead == 0)
    #expect(r2.stats.cacheChanged == false)
    #expect(r2.usage == r.usage)
}

// MARK: - 첫 스캔 footprint 실험 (autoreleasepool)

/// 이 프로세스의 phys_footprint(바이트). mach task_info(TASK_VM_INFO) — Activity Monitor 의 "메모리" 열과 같은 지표.
private func v0238PhysFootprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(task_self_trap(), task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Int(info.phys_footprint)
}

/// 10MB JSONL 픽스처(실제 assistant 라인처럼 수 KB 의 content 를 단 라인 2,000 개)를 빈 캐시로 첫 스캔했을 때
/// footprint 가 얼마나 남는가. JSONSerialization 이 라인마다 만드는 autoreleased 객체가 풀 없이 쌓이면 이 델타가
/// 픽스처 크기의 수 배로 뛴다(프로덕션 peak 405MB 의 유력 원천). 단언은 넓게(픽스처의 8배), 수치는 보고서로.
@Test
func firstScanFootprintDeltaOnTenMegabyteFixtureStaysBounded() {
    let home = v0238TempDir("footprint")
    defer { try? FileManager.default.removeItem(at: home) }
    let inMonth = v0238Now.addingTimeInterval(-2 * 86_400)
    var lines: [String] = []
    lines.reserveCapacity(2_000)
    for i in 0..<2_000 {
        lines.append(v0238ClaudeLine(
            id: "msg_\(i)", req: "req_\(i)", at: inMonth,
            usage: "{\"input_tokens\":\(i),\"output_tokens\":1,\"cache_read_input_tokens\":2,\"cache_creation_input_tokens\":3}",
            filler: 5_000))
    }
    // 두 파일로 나눠 파일 경계도 지나게 한다.
    let half = lines.count / 2
    let fileA = lines[..<half].joined(separator: "\n") + "\n"
    let fileB = lines[half...].joined(separator: "\n") + "\n"
    v0238Write(fileA, to: v0238ClaudeURL(home, "big", "a.jsonl"))
    v0238Write(fileB, to: v0238ClaudeURL(home, "big", "b.jsonl"))
    let fixtureBytes = fileA.utf8.count + fileB.utf8.count
    lines.removeAll()

    let before = v0238PhysFootprint()
    let r = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)
    let after = v0238PhysFootprint()
    let delta = after - before

    print("=== V0238 FOOTPRINT: fixture=\(fixtureBytes / 1_048_576)MB entries=\(r.cache.claudeEntries.count) "
        + "before=\(before / 1_048_576)MB after=\(after / 1_048_576)MB delta=\(delta / 1_048_576)MB ===")
    #expect(r.cache.claudeEntries.count == 2_000)
    #expect(r.usage.claudeInput == (0..<2_000).reduce(0, +))
    #expect(before > 0 && after > 0)
    // 넓은 상한: 픽스처(10MB)의 8배. 풀이 없으면(구현 전) 이 값이 어디쯤인지 위 print 로 보고한다.
    #expect(delta < fixtureBytes * 8, "첫 스캔 footprint 델타 \(delta / 1_048_576)MB 가 픽스처 8배를 넘음")
}

// MARK: - M4 해시 키 (정의 고정 · 16진 왕복 · 문자열 조회 호환)

/// 키의 정의는 "옛 dedupe 문자열 id\0requestId 의 SHA-256 앞 16바이트"다. 앱 재시작·업그레이드 뒤에도 디스크의 키가
/// 같은 엔트리를 가리켜야 하므로 벡터로 못 박는다(프로세스 시드가 섞이는 Swift Hasher 를 쓰면 매 실행 다른 키가 된다).
@Test
func entryKeyIsSHA256PrefixOfLegacyDedupeString() {
    let k = ClaudeEntryKey(messageID: "a", requestID: "b")
    #expect(k.hex == "59b271ae1bbcb1d31d41929817f4b16f")                   // python: sha256(b"a\x00b").hexdigest()[:32]
    #expect(k == ClaudeEntryKey(dedupeString: "a\u{0}b"))                  // 두 이니셜라이저는 같은 정의
    #expect(ClaudeEntryKey(messageID: "msg_k1", requestID: "req_k1").hex == "684fd34e08540c6376199d3587d6252f")
    // NUL 구분자: ("ab","") 와 ("a","b") 와 ("","ab") 는 서로 다른 키다.
    #expect(ClaudeEntryKey(messageID: "ab", requestID: "").hex == "969caaeb3626c0d5695eefa6aea53305")
    #expect(ClaudeEntryKey(messageID: "ab", requestID: "") != k)
    #expect(ClaudeEntryKey(messageID: "", requestID: "ab") != k)
    #expect(ClaudeEntryKey(messageID: "", requestID: "ab") != ClaudeEntryKey(messageID: "ab", requestID: ""))
}

@Test
func entryKeyRoundTripsThroughHexAndCodable() throws {
    let k = ClaudeEntryKey(messageID: "msg_01ABCDEFGHIJKLMNOPQRSTUV", requestID: "req_011CSXYZ0123456789abcdef")
    #expect(k.hex.count == 32)
    #expect(ClaudeEntryKey(hex: k.hex) == k)
    #expect(ClaudeEntryKey(hex: k.hex.uppercased()) == k)              // 대문자도 받는다
    #expect(ClaudeEntryKey(hex: String(k.hex.dropLast())) == nil)      // 31자
    #expect(ClaudeEntryKey(hex: k.hex + "0") == nil)                    // 33자
    #expect(ClaudeEntryKey(hex: "zz" + String(k.hex.dropFirst(2))) == nil) // 16진 아님
    #expect(ClaudeEntryKey(hex: "msg\u{0}req") == nil)                  // 옛 문자열 키는 절대 16진으로 안 읽힌다
    // Codable 은 단일값 16진 문자열.
    let data = try JSONEncoder().encode(k)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(k.hex)\"")
    #expect(try JSONDecoder().decode(ClaudeEntryKey.self, from: data) == k)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(ClaudeEntryKey.self, from: Data("\"nope\"".utf8)) }
}

/// 문자열 조회(옛 dedupe 문자열)는 프로덕션 ingest 가 (id, requestId) 로 넣은 엔트리에 닿고, 저장→로드 뒤에도 같다.
@Test
func entryKeyLookupByLegacyStringMatchesIngestAndSurvivesDiskRoundTrip() {
    let home = v0238TempDir("keylookup")
    let dir = v0238TempDir("keylookup-cache")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: dir) }
    _ = v0238WriteOracleFixture(into: home)
    let r = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)

    #expect(r.cache.claudeEntries["msg_k1\u{0}req_k1"]?.input == 100)
    #expect(r.cache.claudeEntries["msg_k2\u{0}req_k2"]?.output == 688)
    #expect(r.cache.claudeEntries[ClaudeEntryKey(messageID: "msg_k5", requestID: "req_k5")]?.input == 7)
    #expect(r.cache.claudeEntries["msg_k4\u{0}req_k4"]?.input == 5000)   // 6/21 은 12주 창 안(v0.2.43) — 보관되나 합계 밖
    #expect(r.cache.claudeEntries.count == 5)                            // k1 k2 k3 k4 k5

    let base = v0238CacheURL(in: dir)
    #expect(TokenUsageCacheStore.save(r.cache, parts: .all, to: base))
    let loaded = TokenUsageCacheStore.load(from: base)
    #expect(loaded == r.cache)
    #expect(loaded.claudeEntries["msg_k3\u{0}req_k3"]?.input == 1000)
    // 콜드 파일은 16진 키 오브젝트다(옛 NUL 문자열 키 없음).
    let cold = try! JSONSerialization.jsonObject(with: Data(contentsOf: TokenUsageCacheStore.entriesURL(for: base))) as! [String: Any]
    #expect(cold.count == 5)
    #expect(cold.keys.allSatisfy { ClaudeEntryKey(hex: $0) != nil })
}

// MARK: - Q6 보관 경계 (월 시작 − 48h)

/// Claude 는 12주 잔디 창 시작 − 48h(KST 04-18 00:00) 부터 남고 그 이전은 지워진다(엔트리·파일상태). Codex 파일상태는 월 시작 − 48h
/// (KST 06-29) 그대로다(v0.2.43 — Codex 는 월 창 유지). v0.2.38~42 는 Claude 도 월 시작 − 48h 였고, v0.2.37 은 직전 월 1일부터였다.
/// 뮤테이션: Claude 경계를 월 시작 − 48h 로 되돌리면 창 안 엔트리(−20d)가 사라져 빨강, Codex 경계를 창으로 옮기면 drop-rollout 이 살아남아 빨강.
@Test
func retentionKeepsTheTwelveWeekWindowAndEvictsOlder() {
    let window = TokenUsageIncrementalScanner.windowBounds(now: v0238Now)
    #expect(window.startKey == "2026-04-20")                               // 07-14(화) 의 주 월요일 07-13 − 12주
    let boundary = window.retentionStart                                  // KST 04-18 00:00
    let codexBoundary = v0238MonthStart.addingTimeInterval(-48 * 3_600)   // KST 06-29 00:00
    var cache = TokenUsageCache()
    cache.claudeEntries["in\u{0}m"] = ClaudeEntry(ts14: v0238TS14(v0238Now.addingTimeInterval(-5 * 86_400)), input: 111, output: 0, cacheRead: 0, cacheCreation: 0)
    cache.claudeEntries["edge-in\u{0}m"] = ClaudeEntry(ts14: v0238TS14(boundary), input: 222, output: 0, cacheRead: 0, cacheCreation: 0)                       // 경계 정각 → 보관
    cache.claudeEntries["edge-out\u{0}m"] = ClaudeEntry(ts14: v0238TS14(boundary.addingTimeInterval(-1)), input: 333, output: 0, cacheRead: 0, cacheCreation: 0) // 1초 전 → 퇴거
    cache.claudeEntries["prev\u{0}m"] = ClaudeEntry(ts14: v0238TS14(v0238MonthStart.addingTimeInterval(-20 * 86_400)), input: 444, output: 0, cacheRead: 0, cacheCreation: 0) // 지난달 본체(6/11, 창 안) → 보관
    let micros = { (d: Date) in Int((d.timeIntervalSince1970 * 1_000_000).rounded()) }
    cache.claudeFileStates["/keep.jsonl"] = FileProgress(size: 1, mtimeMicros: micros(boundary.addingTimeInterval(3_600)), consumedOffset: 1)
    cache.claudeFileStates["/drop.jsonl"] = FileProgress(size: 1, mtimeMicros: micros(boundary.addingTimeInterval(-3_600)), consumedOffset: 1)
    cache.codexFileStates["/keep-rollout.jsonl"] = CodexFileProgress(size: 1, mtimeMicros: micros(codexBoundary), consumedOffset: 1, prevInput: 1, prevOutput: 0, prevCached: 0, monthKey: "2026-06", monthInput: 0, monthOutput: 0, monthCached: 0, dayContrib: [:])
    cache.codexFileStates["/drop-rollout.jsonl"] = CodexFileProgress(size: 1, mtimeMicros: micros(codexBoundary.addingTimeInterval(-1)), consumedOffset: 1, prevInput: 1, prevOutput: 0, prevCached: 0, monthKey: "2026-06", monthInput: 0, monthOutput: 0, monthCached: 0, dayContrib: [:])

    let home = v0238TempDir("retention")   // 로그 없음 — 퇴거/합계만
    let r = TokenUsageIncrementalScanner.update(cache, homeDirectory: home, now: v0238Now)

    #expect(r.cache.claudeEntries["in\u{0}m"] != nil)
    #expect(r.cache.claudeEntries["edge-in\u{0}m"] != nil)
    #expect(r.cache.claudeEntries["edge-out\u{0}m"] == nil)
    #expect(r.cache.claudeEntries["prev\u{0}m"] != nil)
    #expect(r.cache.claudeEntries.count == 3)
    #expect(r.cache.claudeFileStates.keys.sorted() == ["/keep.jsonl"])
    #expect(r.cache.codexFileStates.keys.sorted() == ["/keep-rollout.jsonl"])
    #expect(r.usage.claudeInput == 111)                 // 합계는 여전히 현재 월만(보관된 4/18·6/11 엔트리는 합계 밖)
    #expect(r.usage.claudeDaily["2026-06-11"] == 444)   // 창 안의 지난 날은 일별 맵(잔디)에 남는다
    #expect(r.usage.claudeDaily["2026-04-18"] == nil)   // 창 앞 48h straddle 분은 부분값이라 일별 맵에 넣지 않는다
    #expect(r.stats.entriesChanged == true)             // 콜드 변경
    #expect(r.stats.statesChanged == true)              // 핫 변경
    #expect(r.stats.changedParts == .all)
}

/// ingest 가드도 같은 경계다(v0.2.43: 12주 창 시작 − 48h): 파일이 열리더라도 창 시작 −49h 라인은 저장조차 안 되고 −47h 라인은 저장된다(합계 밖).
@Test
func ingestGuardUsesSameRetentionBoundaryAsEviction() {
    let home = v0238TempDir("ingestguard")
    defer { try? FileManager.default.removeItem(at: home) }
    let windowStart = TokenUsageIncrementalScanner.windowBounds(now: v0238Now).start   // KST 04-20 00:00
    let inside = v0238ClaudeLine(id: "i", req: "i", at: windowStart.addingTimeInterval(-47 * 3_600), usage: "{\"input_tokens\":10}")
    let outside = v0238ClaudeLine(id: "o", req: "o", at: windowStart.addingTimeInterval(-49 * 3_600), usage: "{\"input_tokens\":20}")
    let current = v0238ClaudeLine(id: "c", req: "c", at: v0238Now, usage: "{\"input_tokens\":30}")
    v0238Write([inside, outside, current].joined(separator: "\n") + "\n", to: v0238ClaudeURL(home, "p", "s.jsonl"))

    let r = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)

    #expect(r.cache.claudeEntries["i\u{0}i"] != nil)
    #expect(r.cache.claudeEntries["o\u{0}o"] == nil)
    #expect(r.cache.claudeEntries.count == 2)
    #expect(r.usage.claudeInput == 30)
}

/// 월 경계를 걸치는 세션(월말 밤 시작 → 월초 새벽까지). 증분(6월 마지막 스캔의 캐시 이어받기)과 전량(빈 캐시) 결과가
/// 월초·월중·다음 달까지 매 시점 같아야 한다 — 48h 보관이 straddle dedupe(같은 키의 지난달/이번달 라인)를 정확히 덮는 증명.
@Test
func monthBoundaryStraddleTotalsAreInvariantBetweenIncrementalAndFullScan() {
    let home = v0238TempDir("straddle")
    defer { try? FileManager.default.removeItem(at: home) }
    let url = v0238ClaudeURL(home, "p", "session.jsonl")
    let kst = { (utc: String) in v0238UTC(utc) }
    let now1 = kst("2026-06-30T14:50:00Z")   // KST 06-30 23:50 (6월)
    let now2 = kst("2026-06-30T16:00:00Z")   // KST 07-01 01:00 (7월 초)
    let now3 = kst("2026-07-20T03:00:00Z")   // KST 07-20 12:00 (7월 중)
    let now4 = kst("2026-08-02T15:00:00Z")   // KST 08-03 00:00 (8월)

    // 6월 밤: a(6월만), b 의 첫 스냅샷.
    let a = v0238ClaudeLine(id: "a", req: "a", at: kst("2026-06-30T13:00:00Z"), usage: "{\"input_tokens\":10,\"output_tokens\":1}")
    let b1 = v0238ClaudeLine(id: "b", req: "b", at: kst("2026-06-30T14:40:00Z"), usage: "{\"input_tokens\":1,\"output_tokens\":5}")
    v0238Write([a, b1].joined(separator: "\n") + "\n", to: url, modified: now1)
    let june = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now1)
    #expect(june.usage.month == "2026-06")
    #expect(june.usage.claudeInput == 11)

    // 자정 넘김: b 의 최종 스냅샷(7월, 더 큰 output), c(7월), d 는 reverse-straddle(6월 라인이 더 큰 output, 7월 라인이 더 최신).
    let b2 = v0238ClaudeLine(id: "b", req: "b", at: kst("2026-06-30T15:00:20Z"), usage: "{\"input_tokens\":2,\"output_tokens\":700}")
    let c = v0238ClaudeLine(id: "c", req: "c", at: kst("2026-06-30T15:30:00Z"), usage: "{\"input_tokens\":100}")
    let d1 = v0238ClaudeLine(id: "d", req: "d", at: kst("2026-06-30T14:59:50Z"), usage: "{\"input_tokens\":9,\"output_tokens\":300}")
    let d2 = v0238ClaudeLine(id: "d", req: "d", at: kst("2026-06-30T15:00:05Z"), usage: "{\"input_tokens\":3,\"output_tokens\":100}")
    v0238Append([b2, c, d1, d2].joined(separator: "\n") + "\n", to: url, modified: now2)

    let inc2 = TokenUsageIncrementalScanner.update(june.cache, homeDirectory: home, now: now2)
    let full2 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now2)
    #expect(inc2.usage.month == "2026-07")
    // 7월: b(2/700) + c(100) + d(max-output 300 레코드의 9, 관측 최대 ts 가 7월이라 7월로). a 는 6월이라 밖.
    #expect(inc2.usage.claudeInput == 111)
    #expect(inc2.usage.claudeOutput == 1_000)
    #expect(inc2.usage == full2.usage)
    #expect(inc2.cache.claudeEntries == full2.cache.claudeEntries)
    #expect(inc2.cache.claudeEntries["a\u{0}a"] != nil)      // 6/30 라인은 48h 창 안이라 보관(합계 밖)
    #expect(inc2.stats.claudeBytesRead == [b2, c, d1, d2].joined(separator: "\n").utf8.count + 1)   // 이어읽기(새 바이트만)

    // 7월 중: 파일 무변경. 증분은 재읽기 0 이고, 전량과 같다. 6월 straddle 엔트리는 아직 보관(경계는 7월 내내 6/29).
    let inc3 = TokenUsageIncrementalScanner.update(inc2.cache, homeDirectory: home, now: now3)
    let full3 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now3)
    #expect(inc3.stats.claudeBytesRead == 0)
    #expect(inc3.stats.cacheChanged == false)
    #expect(inc3.usage == full3.usage)
    #expect(inc3.usage.claudeOutput == 1_000)
    #expect(inc3.cache.claudeEntries.count == 4)

    // 8월(v0.2.43): 12주 창(05-11~)이라 6/30·7/1 엔트리는 아직 보관되고 파일(mtime 7/1)도 창 안이라 열린다 — 8월 합계는 0 이고
    // 증분·전량이 같으며, 일별 맵에는 지난 두 달의 날이 남는다(잔디가 보는 값). 재읽기·퇴거는 없다.
    let inc4 = TokenUsageIncrementalScanner.update(inc3.cache, homeDirectory: home, now: now4)
    let full4 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now4)
    #expect(inc4.usage.month == "2026-08")
    #expect(inc4.usage.total == 0)
    #expect(inc4.usage == full4.usage)
    #expect(inc4.cache.claudeEntries.count == 4)
    #expect(inc4.cache.claudeFileStates.count == 1)
    #expect(inc4.usage.claudeDaily["2026-07-01"] == 1_111)   // KST 7/1: b(2+700) + c(100) + d(max-output 레코드 9+300)
    #expect(inc4.usage.claudeDaily["2026-06-30"] == 11)      // a(10+1)
    #expect(inc4.stats.claudeBytesRead == 0 && inc4.stats.cacheChanged == false)

    // 10월(KST 10-05 월요일 0시): 창이 7/13 로 옮겨(보관 하한 7/11) 6·7월 초 엔트리가 전부 퇴거되고 파일(mtime 7/1)도 창 밖이라 닫힌다. 전량도 0.
    let now5 = kst("2026-10-04T15:00:00Z")   // KST 10-05 00:00 (10월)
    let inc5 = TokenUsageIncrementalScanner.update(inc4.cache, homeDirectory: home, now: now5)
    let full5 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now5)
    #expect(inc5.usage.month == "2026-10")
    #expect(inc5.usage.total == 0)
    #expect(inc5.usage == full5.usage)
    #expect(inc5.cache.claudeEntries.isEmpty)
    #expect(inc5.cache.claudeFileStates.isEmpty)
    #expect(inc5.stats.entriesChanged == true && inc5.stats.statesChanged == true)
}

// MARK: - 핫/콜드 분리 (파일 레이아웃 · 부분 저장 · 세대 게이트)

private func v0238FileBytes(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// 저장은 더러워진 쪽만 다시 쓴다: codex 만 바뀐 저장은 콜드 파일을 한 바이트도 안 건드리고, 로드는 두 파일의 합이다.
@Test
func partialSaveRewritesOnlyDirtyFileAndLoadMergesBoth() {
    let dir = v0238TempDir("partial")
    defer { try? FileManager.default.removeItem(at: dir) }
    let base = v0238CacheURL(in: dir)
    let stateURL = TokenUsageCacheStore.stateURL(for: base)
    let entriesURL = TokenUsageCacheStore.entriesURL(for: base)
    #expect(stateURL.lastPathComponent == "cache.state.json")
    #expect(entriesURL.lastPathComponent == "cache.entries.json")

    var cache = TokenUsageCache()
    cache.claudeEntries["m1\u{0}r1"] = ClaudeEntry(ts14: 20_260_710_000_000, input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
    cache.claudeFileStates["/a.jsonl"] = FileProgress(size: 10, mtimeMicros: 999, consumedOffset: 8)
    cache.codexFileStates["/r.jsonl"] = CodexFileProgress(size: 5, mtimeMicros: 1, consumedOffset: 5, prevInput: 100, prevOutput: 0, prevCached: 0, monthKey: "2026-07", monthInput: 7, monthOutput: 0, monthCached: 0, dayContrib: ["2026-07-14": 7])

    // 처음엔 어느 부분만 요청해도 둘 다 만들어진다(없는 파일은 항상 채운다 — 핫만 있는 쌍은 로드에서 폐기되므로).
    #expect(TokenUsageCacheStore.save(cache, parts: [.state], to: base))
    #expect(FileManager.default.fileExists(atPath: entriesURL.path))
    #expect(TokenUsageCacheStore.load(from: base) == cache)
    let coldBytes1 = v0238FileBytes(entriesURL)
    let hotBytes1 = v0238FileBytes(stateURL)

    // codex 상태만 바뀐 저장(핫만): 콜드 파일 불변.
    cache.codexFileStates["/r.jsonl"]?.monthInput = 70
    #expect(TokenUsageCacheStore.save(cache, parts: [.state], to: base))
    #expect(v0238FileBytes(entriesURL) == coldBytes1)
    #expect(v0238FileBytes(stateURL) != hotBytes1)
    #expect(TokenUsageCacheStore.load(from: base) == cache)
    let hotBytes2 = v0238FileBytes(stateURL)

    // 엔트리만 바뀐 저장(콜드만): 핫 파일 불변.
    cache.claudeEntries["m2\u{0}r2"] = ClaudeEntry(ts14: 20_260_711_000_000, input: 5, output: 6, cacheRead: 7, cacheCreation: 8)
    #expect(TokenUsageCacheStore.save(cache, parts: [.entries], to: base))
    #expect(v0238FileBytes(stateURL) == hotBytes2)
    #expect(v0238FileBytes(entriesURL) != coldBytes1)
    #expect(TokenUsageCacheStore.load(from: base) == cache)

    // 핫 파일 본문엔 엔트리가 비어 있다(엔트리는 콜드에만).
    let hot = try! JSONSerialization.jsonObject(with: v0238FileBytes(stateURL)!) as! [String: Any]
    #expect(hot["schemaVersion"] as? Int == TokenUsageCacheStore.currentSchemaVersion)
    #expect(((hot["state"] as? [String: Any])?["claudeEntries"] as? [String: Any])?.isEmpty == true)
}

/// 스캐너의 changedParts 가 핫/콜드를 가른다: codex 만 자라면 핫만, Claude usage 라인이 붙으면 둘 다, 무변경이면 없음.
@Test
func scannerReportsWhichCachePartChanged() {
    let home = v0238TempDir("parts")
    defer { try? FileManager.default.removeItem(at: home) }
    let evt = v0238UTC("2026-07-05T00:00:00Z")
    let rollout = v0238CodexURL(home, "2026/07/05/rollout-2026-07-05T00-00-00-aaaa.jsonl")
    v0238Write(v0238CodexLine(input: 100, output: 0, at: evt) + "\n", to: rollout)
    let claude = v0238ClaudeURL(home, "p", "s.jsonl")
    v0238Write(v0238ClaudeLine(id: "a", req: "a", at: evt, usage: "{\"input_tokens\":1}") + "\n", to: claude)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)
    #expect(r1.stats.changedParts == .all)

    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: v0238Now)
    #expect(r2.stats.changedParts.isEmpty)

    v0238Append(v0238CodexLine(input: 200, output: 0, at: evt) + "\n", to: rollout, modified: v0238Now.addingTimeInterval(1))
    let r3 = TokenUsageIncrementalScanner.update(r2.cache, homeDirectory: home, now: v0238Now)
    #expect(r3.stats.changedParts == [.state])
    #expect(r3.usage.codexInput == 100)

    // Claude 파일이 자랐지만 usage 라인이 아니면(사용자 메시지) 핫만.
    v0238Append(v0238UserLine(at: evt) + "\n", to: claude, modified: v0238Now.addingTimeInterval(2))
    let r4 = TokenUsageIncrementalScanner.update(r3.cache, homeDirectory: home, now: v0238Now)
    #expect(r4.stats.changedParts == [.state])

    v0238Append(v0238ClaudeLine(id: "b", req: "b", at: evt, usage: "{\"input_tokens\":2}") + "\n", to: claude, modified: v0238Now.addingTimeInterval(3))
    let r5 = TokenUsageIncrementalScanner.update(r4.cache, homeDirectory: home, now: v0238Now)
    #expect(r5.stats.changedParts == .all)
    #expect(r5.usage.claudeInput == 3)
}

/// 세대 게이트: v0.2.37 이하의 단일 파일은 읽지 않고 지운다. 핫의 schemaVersion 이 다르거나, 두 파일 중 하나가 없거나,
/// 콜드가 손상(16진 아닌 키)이면 전부 빈 캐시(→ 재스캔). 손상 처리 경로 하나로 모인다.
@Test
func cacheLoadDiscardsLegacyAndMismatchedGenerations() throws {
    let dir = v0238TempDir("gate")
    defer { try? FileManager.default.removeItem(at: dir) }
    let base = v0238CacheURL(in: dir)
    let stateURL = TokenUsageCacheStore.stateURL(for: base)
    let entriesURL = TokenUsageCacheStore.entriesURL(for: base)

    // 1) 옛 단일 파일(모놀리식, 문자열 키)만 있는 맥: 빈 캐시 + 파일 삭제.
    let legacy = """
    {"claudeFileStates":{"/a/b.jsonl":[10,999,8]},"claudeEntries":{"msg\\u0000req":[20260722103000,1,2,3,4]},\
    "codexFileStates":{"/p/rollout.jsonl":[10,20,30,40,"2026-07",50,"2026-07-14",60]},"codexSchemaVersion":3}
    """
    v0238Write(legacy, to: base)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
    #expect(FileManager.default.fileExists(atPath: base.path) == false)

    // 2) 정상 쌍은 그대로 왕복한다.
    var cache = TokenUsageCache()
    cache.claudeEntries["m\u{0}r"] = ClaudeEntry(ts14: 20_260_710_000_000, input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
    cache.claudeFileStates["/a.jsonl"] = FileProgress(size: 10, mtimeMicros: 999, consumedOffset: 8)
    #expect(TokenUsageCacheStore.save(cache, parts: .all, to: base))
    #expect(TokenUsageCacheStore.load(from: base) == cache)

    // 3) 핫의 세대가 다르면(옛 세대) 전부 폐기.
    var hot = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
    hot["schemaVersion"] = TokenUsageCacheStore.currentSchemaVersion - 1
    try JSONSerialization.data(withJSONObject: hot).write(to: stateURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
    hot["schemaVersion"] = TokenUsageCacheStore.currentSchemaVersion
    try JSONSerialization.data(withJSONObject: hot).write(to: stateURL)
    #expect(TokenUsageCacheStore.load(from: base) == cache)

    // 4) 콜드가 없으면(핫만 살아남은 쌍) 폐기 — 핫이 앞서면 "소비한 오프셋인데 엔트리 없음" = 과소집계라서.
    let coldBytes = try Data(contentsOf: entriesURL)
    try FileManager.default.removeItem(at: entriesURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
    try coldBytes.write(to: entriesURL)
    #expect(TokenUsageCacheStore.load(from: base) == cache)

    // 5) 콜드 손상(16진 아닌 키): 폐기.
    try Data("{\"msg\\u0000req\":[20260722103000,1,2,3,4]}".utf8).write(to: entriesURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())

    // 6) 핫만 없어도 폐기(콜드만으론 이어읽기 기준이 없다 — 재스캔이 dedupe 로 같은 값을 만든다).
    try coldBytes.write(to: entriesURL)
    try FileManager.default.removeItem(at: stateURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
}

/// 스토어 경로로 본 세대 업: 옛 단일 파일이 "이 픽스처는 이미 끝까지 소비했다"고 주장해도(엔트리는 없음) 믿지 않고
/// 재스캔해 값이 나온다. 믿었다면 0 이었을 것이다(과소집계). 옛 파일은 지워지고 새 쌍이 그 자리에 생긴다.
@MainActor
@Test
func storeRescansWhenOnDiskCacheIsFromOlderGeneration() async throws {
    let home = v0238TempDir("gen-home")
    let dir = v0238TempDir("gen-cache")
    let suite = "check-v0238-token-generation"
    let defaults = v0238Defaults(suite)
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: dir)
    }
    _ = v0238WriteOracleFixture(into: home)
    let base = v0238CacheURL(in: dir)

    // 실제 스캔으로 경로 키(심볼릭 정규화된 실경로)를 얻어, 엔트리만 비운 옛 모놀리식 JSON 을 베이스 자리에 놓는다.
    var stale = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now).cache
    stale.claudeEntries = [:]
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try JSONEncoder().encode(stale).write(to: base)

    let center = NotificationCenter()
    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: base, clock: { v0238Now }, notificationCenter: center)
    await store.refreshIfStale()

    #expect(store.currentMonthUsage?.claudeInput == 118)   // 옛 파일을 믿었다면 0
    #expect(store.currentMonthUsage?.total == 1_574)
    #expect(FileManager.default.fileExists(atPath: base.path) == false)

    // 종료 훅으로 저장을 강제하면 새 쌍이 생기고, 새 스토어는 그 쌍으로 재읽기 0 에 같은 값을 낸다.
    center.post(name: NSApplication.willTerminateNotification, object: nil)
    let reloaded = TokenUsageCacheStore.load(from: base)
    #expect(reloaded.claudeEntries.count == 5)   // k1 k2 k3 k4 k5 — 12주 창(v0.2.43)이라 6/21 의 k4 도 남는다
    let again = TokenUsageIncrementalScanner.update(reloaded, homeDirectory: home, now: v0238Now)
    #expect(again.stats.claudeBytesRead == 0)
    #expect(again.usage.total == 1_574)
}

// MARK: - Q5 저장 스로틀 · 루프 종료 저장 · 종료 훅

/// clock 주입용 참조 박스.
@MainActor
private final class V0238Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// 스로틀 시나리오용 스토어 + 성장하는 픽스처. 매 단계 새 usage 라인을 붙여 스캔이 항상 캐시를 더럽히게 한다.
@MainActor
private struct V0238ThrottleRig {
    let home: URL
    let dir: URL
    let base: URL
    let url: URL
    let clock: V0238Clock
    let center = NotificationCenter()
    let store: TokenUsageStore
    var lines = 0

    init(suite: String, defaults: UserDefaults) {
        home = v0238TempDir("throttle-home")
        dir = v0238TempDir("throttle-cache")
        base = v0238CacheURL(in: dir)
        url = v0238ClaudeURL(home, "p", "s.jsonl")
        clock = V0238Clock(v0238Now)
        v0238Write("", to: url, modified: v0238Now)
        let box = clock
        store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: base, clock: { box.now }, notificationCenter: center)
    }

    /// 시각을 t0+seconds 로 옮기고 usage 라인 하나를 붙인 뒤(mtime 도 그 시각) 갱신한다.
    mutating func advanceAppendAndRefresh(to seconds: TimeInterval) async {
        clock.now = v0238Now.addingTimeInterval(seconds)
        lines += 1
        v0238Append(v0238ClaudeLine(id: "m\(lines)", req: "r\(lines)", at: clock.now, usage: "{\"input_tokens\":1}") + "\n",
                    to: url, modified: clock.now)
        await store.refreshIfStale()
    }

    func entriesOnDisk() -> Int? {
        guard let data = try? Data(contentsOf: TokenUsageCacheStore.entriesURL(for: base)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj.count
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: home)
        try? FileManager.default.removeItem(at: dir)
    }
}

/// (a) 저장은 마지막 저장(스토어 생성 시점이 첫 기준) 후 300초 이상 지난 스캔 완료 시점에만. 그 사이 변경은 모였다가 한 번에.
/// 뮤테이션: persistIfDirty 의 간격 조건을 지우면 더러운 스캔마다 저장돼 t0+120 에서 이미 saveCount 1 → 빨강.
@MainActor
@Test
func cacheSaveIsThrottledToFiveMinutesByInjectedClock() async {
    #expect(TokenUsageStore.refreshPeriod == 120)
    #expect(TokenUsageStore.refreshTolerance == 20)
    #expect(TokenUsageStore.saveInterval == 300)
    let suite = "check-v0238-token-throttle"
    let defaults = v0238Defaults(suite)
    var rig = V0238ThrottleRig(suite: suite, defaults: defaults)
    defer { defaults.removePersistentDomain(forName: suite); rig.tearDown() }

    await rig.advanceAppendAndRefresh(to: 0)          // 첫 스캔: 더러움 1줄, 저장 0 (생성 후 0초)
    #expect(rig.store.scanCount == 1)
    #expect(rig.store.saveCount == 0)
    await rig.advanceAppendAndRefresh(to: 120)        // 120 < 300
    #expect(rig.store.scanCount == 2)
    #expect(rig.store.saveCount == 0)
    await rig.advanceAppendAndRefresh(to: 240)        // 240 < 300
    #expect(rig.store.saveCount == 0)
    #expect(rig.entriesOnDisk() == nil)               // 아직 디스크에 아무것도 없다
    await rig.advanceAppendAndRefresh(to: 300)        // 300 ≥ 300 → 저장 #1 (모인 4줄이 한 번에)
    #expect(rig.store.saveCount == 1)
    await rig.store.awaitPendingSaves()
    #expect(rig.entriesOnDisk() == 4)
    await rig.advanceAppendAndRefresh(to: 420)        // 마지막 저장(300) 후 120 → 저장 안 함
    #expect(rig.store.saveCount == 1)
    await rig.store.awaitPendingSaves()
    #expect(rig.entriesOnDisk() == 4)
    await rig.advanceAppendAndRefresh(to: 600)        // 300 → 저장 #2
    #expect(rig.store.saveCount == 2)
    await rig.store.awaitPendingSaves()
    #expect(rig.entriesOnDisk() == 6)
    // 무변경 스캔은 간격이 차도 저장하지 않는다(더러움 없음).
    rig.clock.now = v0238Now.addingTimeInterval(1_200)
    await rig.store.refreshIfStale()
    #expect(rig.store.scanCount == 7)
    #expect(rig.store.saveCount == 2)
    #expect(rig.store.currentMonthUsage?.claudeInput == 6)
}

/// (b) 팝오버가 닫혀 갱신 루프가 취소되면 더러운 캐시를 1회 저장한다(간격과 무관). 깨끗하면 저장하지 않는다.
@MainActor
@Test
func refreshLoopCancellationPersistsDirtyCacheOnce() async {
    let suite = "check-v0238-token-loop-cancel"
    let defaults = v0238Defaults(suite)
    var rig = V0238ThrottleRig(suite: suite, defaults: defaults)
    defer { defaults.removePersistentDomain(forName: suite); rig.tearDown() }
    rig.lines += 1
    v0238Append(v0238ClaudeLine(id: "m1", req: "r1", at: v0238Now, usage: "{\"input_tokens\":5}") + "\n", to: rig.url, modified: v0238Now)

    // 팝오버 열림(.task): 즉시 1회 스캔 → 120초 sleep. 스캔 완료까지 기다린 뒤 닫힘(취소)을 모사한다.
    let store = rig.store
    let loop = Task { await store.runRefreshLoop() }
    var spins = 0
    while store.scanCount == 0, spins < 2_000 {
        spins += 1
        try? await Task.sleep(for: .milliseconds(2))
    }
    await store.awaitScanCompletion()
    #expect(store.scanCount == 1)
    #expect(store.currentMonthUsage?.claudeInput == 5)
    #expect(store.saveCount == 0)                        // 300초 전 — 스로틀에 막혀 아직 안 씀

    loop.cancel()
    await loop.value                                     // 루프 종료 지점에서 1회 저장
    #expect(store.saveCount == 1)
    await store.awaitPendingSaves()
    #expect(rig.entriesOnDisk() == 1)
    #expect(TokenUsageCacheStore.load(from: rig.base).claudeEntries["m1\u{0}r1"]?.input == 5)

    // 다시 열었다 닫음(무변경): 스캔은 돌지만 깨끗하니 저장 없음 — "1회"가 "매 닫힘마다"가 아님을 못 박는다.
    rig.clock.now = v0238Now.addingTimeInterval(10)
    let loop2 = Task { await store.runRefreshLoop() }
    spins = 0
    while store.scanCount < 2, spins < 2_000 {
        spins += 1
        try? await Task.sleep(for: .milliseconds(2))
    }
    await store.awaitScanCompletion()
    loop2.cancel()
    await loop2.value
    #expect(store.scanCount == 2)
    #expect(store.saveCount == 1)
}

/// (c) 앱 종료 알림(NSApplication.willTerminateNotification)에서 더러운 캐시를 **동기로** 쓴다 — 알림이 돌아오면 프로세스가
/// 끝나므로 비동기 예약으로는 늦다. 장벽(awaitPendingSaves) 없이 곧바로 디스크에서 읽혀야 한다. 두 번째 알림은 무동작.
@MainActor
@Test
func terminationNotificationPersistsDirtyCacheSynchronously() async {
    let suite = "check-v0238-token-terminate"
    let defaults = v0238Defaults(suite)
    var rig = V0238ThrottleRig(suite: suite, defaults: defaults)
    defer { defaults.removePersistentDomain(forName: suite); rig.tearDown() }

    await rig.advanceAppendAndRefresh(to: 0)
    #expect(rig.store.saveCount == 0)
    #expect(rig.entriesOnDisk() == nil)

    rig.center.post(name: NSApplication.willTerminateNotification, object: nil)
    #expect(rig.store.saveCount == 1)
    #expect(rig.entriesOnDisk() == 1)                    // 장벽 없이 즉시 — 동기 저장
    #expect(FileManager.default.fileExists(atPath: TokenUsageCacheStore.stateURL(for: rig.base).path))

    rig.center.post(name: NSApplication.willTerminateNotification, object: nil)
    #expect(rig.store.saveCount == 1)                    // 깨끗하면 무동작

    // 종료 뒤 더러워진 변경도(예: 종료 직전 스캔) 다음 알림에 나간다.
    await rig.advanceAppendAndRefresh(to: 10)
    rig.center.post(name: NSApplication.willTerminateNotification, object: nil)
    #expect(rig.store.saveCount == 2)
    #expect(rig.entriesOnDisk() == 2)
}

