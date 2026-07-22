import Foundation
import Testing
@testable import check

// MARK: - 픽스처 헬퍼 (임시 홈에 jsonl 을 써서 실제 파일 순회·mtime·파싱 경로를 검증한다)
//
// 픽스처는 Package.swift 리소스 등록 대신, 테스트가 런타임에 임시 디렉터리로 쓰는 방식이라 번들 등록이 불필요하다.

/// 스캔 기준 시각(고정). 창/타임스탬프/mtime 을 모두 이 값에서 파생해 결정적으로 만든다.
private let fixedNow = Date(timeIntervalSince1970: 1_784_000_000)

/// Claude timestamp 포맷(UTC, 소수초, Z). 스캐너의 앞 19자 사전식 창 비교와 맞물린다.
private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
}

/// 고유한 임시 홈 디렉터리 URL(아직 만들지 않음 — 파일 쓸 때 상위 폴더가 생성된다).
private func makeTempHome() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-token-\(UUID().uuidString)", isDirectory: true)
}

/// 파일을 쓰고 mtime 을 지정한다(기본 fixedNow — mtime 프리필터를 통과시킨다).
private func writeFile(_ contents: String, to url: URL, modified: Date = fixedNow) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func claudeURL(_ home: URL, project: String, file: String) -> URL {
    home.appendingPathComponent(".claude/projects/\(project)/\(file)", isDirectory: false)
}

private func codexURL(_ home: URL, path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

/// Claude assistant 라인 한 줄(JSON). usage 는 JSON 오브젝트 문자열로 주입해 누락/널 필드도 만들 수 있다.
private func claudeLine(id: String, requestId: String, timestamp: Date, usage: String) -> String {
    "{\"type\":\"assistant\",\"timestamp\":\"\(iso8601(timestamp))\","
    + "\"requestId\":\"\(requestId)\",\"message\":{\"id\":\"\(id)\",\"usage\":\(usage)}}"
}

/// Codex token_count 라인 한 줄(JSON, total_token_usage 포함).
private func codexTokenCountLine(input: Int, cached: Int, output: Int) -> String {
    "{\"timestamp\":\"2026-07-01T00:00:00.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),"
    + "\"output_tokens\":\(output),\"total_tokens\":0}}}}"
}

/// "token_count" 문자열은 있으나 total_token_usage 가 없는 무효 라인(프리체크는 통과하되 채택되지 않아야 한다).
private let codexInvalidTokenCountLine =
    "{\"payload\":{\"type\":\"token_count\",\"info\":{\"rate_limits\":{}}}}"

// MARK: - Claude 파서

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
    writeFile(l1, to: claudeURL(home, project: "a", file: "sessionA.jsonl"))
    writeFile("\(l1)\n\(l2)", to: claudeURL(home, project: "b", file: "sessionB.jsonl"))

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
    writeFile("\(a)\n\(b)", to: claudeURL(home, project: "p", file: "s.jsonl"))

    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)

    #expect(snapshot.claude.input == 200)
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
    writeFile("\(keep)\n\(drop)", to: claudeURL(home, project: "p", file: "s.jsonl"))

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
    writeFile(line, to: claudeURL(home, project: "p", file: "s.jsonl"))

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
    writeFile(line, to: claudeURL(home, project: "p", file: "old.jsonl"),
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
    writeFile(file1, to: codexURL(home, path: "2026/07/01/rollout-2026-07-01T00-00-00-aaaa.jsonl"))
    writeFile(file2, to: codexURL(home, path: "2026/07/02/rollout-2026-07-02T00-00-00-bbbb.jsonl"))

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
    writeFile(line, to: codexURL(home, path: "2026/05/01/rollout-2026-05-01T00-00-00-cccc.jsonl"),
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

// MARK: - 스토어 (스로틀/영속/부트스트랩)

@Test
func shouldRescanRespectsThirtyMinuteThrottle() {
    let now = fixedNow
    // 최초(마지막 스캔 없음)엔 항상 스캔한다.
    #expect(TokenUsageStore.shouldRescan(lastScannedAt: nil, now: now) == true)
    // 10분 전 스캔 → 아직 신선(재스캔 안 함).
    #expect(TokenUsageStore.shouldRescan(lastScannedAt: now.addingTimeInterval(-10 * 60), now: now) == false)
    // 정확히 30분 경과 → 재스캔(>=).
    #expect(TokenUsageStore.shouldRescan(lastScannedAt: now.addingTimeInterval(-30 * 60), now: now) == true)
    // 31분 경과 → 재스캔.
    #expect(TokenUsageStore.shouldRescan(lastScannedAt: now.addingTimeInterval(-31 * 60), now: now) == true)
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
        clock: { fixedNow }
    )
    #expect(store.snapshot == seeded)
    #expect(store.isScanning == false)
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
    )
    writeFile(line, to: claudeURL(home, project: "p", file: "s.jsonl"))
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    // 영속 스냅샷이 없으므로 init 이 1회 부트스트랩 스캔을 킥한다.
    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, clock: { fixedNow })

    // 백그라운드 스캔 완료를 결정적으로 기다린다(고정 시간 폴링은 전체 스위트 병렬 부하에서 플레이크).
    await store.awaitScanCompletion()
    #expect(store.snapshot?.claude.input == 123)
    #expect(store.snapshot?.total == 130)
    #expect(store.isScanning == false)
    // 값이 있으므로 영속된다(재시작 후 즉시 표시).
    #expect(defaults.data(forKey: TokenUsageStore.snapshotKey) != nil)
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: home)
}

@MainActor
@Test
func storeDoesNotPersistZeroResultSoNextLaunchRescans() async {
    // 로그가 없는 홈: 부트스트랩 스캔이 0 을 낸다. 인메모리엔 스로틀 기준(scannedAt)용으로 0 스냅샷이 남지만
    // total==0 이라 뷰는 EmptyView 를 그린다. 영속은 하지 않아, 재실행(새 스토어)은 nil→다시 부트스트랩한다.
    let home = makeTempHome()
    let suiteName = "check-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, clock: { fixedNow })

    // 스캔 완료를 결정적으로 기다린다(고정 시간 폴링은 전체 스위트 병렬 부하에서 플레이크).
    await store.awaitScanCompletion()
    #expect(store.isScanning == false)
    #expect(store.snapshot?.total == 0)  // 인메모리 0 스냅샷(뷰는 total>0 이 아니라 EmptyView)
    #expect(defaults.data(forKey: TokenUsageStore.snapshotKey) == nil)  // 영속 안 함 → 재실행 시 재부트스트랩

    // 같은 defaults 로 새 스토어를 만들면(재실행 모사) 영속본이 없어 snapshot 은 nil 로 시작한다.
    let relaunched = TokenUsageStore(defaults: defaults, homeDirectory: home, clock: { fixedNow })
    #expect(relaunched.snapshot == nil)

    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: home)
}

// MARK: - 실증(옵트인): 이 맥의 실제 로그를 스캔해 오라클과 비교한다.
// CHECK_TOKEN_LIVE=1 일 때만 실행된다(평소 swift test 에서는 스킵 — 결정적/헤드리스 유지).

@Test(.enabled(if: ProcessInfo.processInfo.environment["CHECK_TOKEN_LIVE"] == "1"))
func liveScanReportsRealUsage() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let start = Date()
    let snapshot = TokenUsageScanner.scan(homeDirectory: home, now: Date())
    let elapsed = Date().timeIntervalSince(start)

    print("=== LIVE TOKEN SCAN (\(String(format: "%.1f", elapsed))s) ===")
    print("Claude input=\(snapshot.claude.input) output=\(snapshot.claude.output) "
        + "cacheRead=\(snapshot.claude.cacheRead) cacheCreation=\(snapshot.claude.cacheCreation) "
        + "total=\(snapshot.claude.total)")
    print("Codex input=\(snapshot.codex.input) output=\(snapshot.codex.output) "
        + "cached=\(snapshot.codex.cached) total=\(snapshot.codex.total)")
    print("GRAND TOTAL=\(snapshot.total)")
    print("tooltip=\(snapshot.detailTooltip)")

    #expect(snapshot.total > 0)
    // 성능 목표는 배포(release) 기준 < 10초(실측 ~2.5초). 이 테스트는 디버그로도 돌 수 있어(최적화 없음 ~4배 느림)
    // 느슨한 상한만 둔다 — 정밀 수치는 위 print 로 확인한다.
    #expect(elapsed < 30)
}
