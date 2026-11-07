import CheckTokenScan
import Foundation
import Testing
@testable import aing_scan

// 시험 규칙: 운영 서버·실제 홈·실제 예약(crontab·launchctl)을 건드리지 않는다. 홈은 임시 폴더, 서버와 명령 실행기는 가짜다.
// 임시 폴더는 지우지 않는다(저장소 규칙) — 시스템 임시 폴더 아래에 남는다.

private let fixedNow = Date(timeIntervalSince1970: 1_784_000_000)   // 2026-07-14 03:33:20 UTC = 12:33 KST

private func tempDir(_ tag: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("aing-scan-tests-\(tag)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func iso(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}

private func write(_ text: String, to url: URL, modified: Date = fixedNow) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func claudeLine(id: String, request: String, at: Date, input: Int, output: Int, cacheRead: Int, cacheCreation: Int) -> String {
    "{\"type\":\"assistant\",\"timestamp\":\"\(iso(at))\",\"requestId\":\"\(request)\",\"message\":{\"id\":\"\(id)\","
        + "\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),\"cache_read_input_tokens\":\(cacheRead),"
        + "\"cache_creation_input_tokens\":\(cacheCreation)}}}"
}

private func codexLine(input: Int, cached: Int, output: Int, at: Date) -> String {
    "{\"timestamp\":\"\(iso(at))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
        + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),"
        + "\"output_tokens\":\(output),\"total_tokens\":0}}}}"
}

/// Claude 126(100+20+5+1) · Codex 530(첫 관측 520 은 기준선, 다음 1050 → 델타 530) 이 나오는 홈.
private func makeFixtureHome() -> URL {
    let home = tempDir("home")
    let at = fixedNow.addingTimeInterval(-3600)
    write(claudeLine(id: "m1", request: "r1", at: at, input: 100, output: 20, cacheRead: 5, cacheCreation: 1) + "\n",
          to: home.appendingPathComponent(".claude/projects/p1/a.jsonl"))
    let codex = [
        codexLine(input: 500, cached: 400, output: 20, at: at.addingTimeInterval(-60)),
        codexLine(input: 1000, cached: 800, output: 50, at: at),
    ].joined(separator: "\n") + "\n"
    write(codex, to: home.appendingPathComponent(".codex/sessions/2026/07/14/rollout-2026-07-14T00-00-00-aaaa.jsonl"))
    return home
}

/// 가짜 서버: 경로별 응답을 정해 두고, 받은 본문을 기록한다.
private final class FakeTransport: ScanTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(path: String, body: [String: Any])] = []
    var responses: [String: (Int, String)] = [:]

    var calls: [(path: String, body: [String: Any])] { lock.lock(); defer { lock.unlock() }; return _calls }

    func post(path: String, body: Data) async throws -> (status: Int, body: Data) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let r: (Int, String) = lock.withLock {
            _calls.append((path, json))
            return responses[path] ?? (200, "{\"ok\":true}")
        }
        return (r.0, Data(r.1.utf8))
    }
}

/// 가짜 명령 실행기: crontab 내용을 메모리에 들고 있는다.
private final class FakeRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    var crontab: String?
    var commands: [String] = []

    func run(_ executable: String, _ arguments: [String], stdin: Data?) -> (status: Int32, stdout: Data) {
        lock.lock(); defer { lock.unlock() }
        commands.append(([executable] + arguments).joined(separator: " "))
        if executable.hasSuffix("crontab") {
            if arguments == ["-l"] {
                guard let crontab else { return (1, Data()) }
                return (0, Data(crontab.utf8))
            }
            if arguments == ["-"] {
                crontab = stdin.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                return (0, Data())
            }
        }
        return (0, Data())
    }
}

private final class Output: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
    func append(_ s: String) { lock.lock(); _lines.append(s); lock.unlock() }
}

private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

private func makeEnv(
    home: URL, transport: FakeTransport, runner: FakeRunner, output: Output, clock: Clock,
    platform: Scheduler.Platform = .linux, macApp: Bool = false
) -> ScanEnvironment {
    ScanEnvironment(
        home: home,
        environment: ["AING_SCAN_HOME": home.appendingPathComponent(".aing-scan").path],
        transport: transport,
        runner: runner,
        platform: platform,
        uid: 501,
        now: { clock.now },
        macAppPresent: { macApp },
        executablePath: "/opt/test/aing-scan",
        hostName: "devbox",
        output: { output.append($0) }
    )
}

private let linkOK = (200, "{\"ok\":true,\"device_id\":\"11111111-2222-3333-4444-555555555555\",\"device_key\":\"SECRET-KEY-DO-NOT-PRINT\"}")

// MARK: - 달력 받침(앱 산식과 같은 값)

@Test
func windowStartShimMatchesAppFormula() {
    // 2026-07-14(화) 12:33 KST → 이번 주 월요일 2026-07-13 00:00 KST → 12주 전 2026-04-20 00:00 KST = 04-19 15:00 UTC.
    let start = WorkDailyGrid.windowStart(now: fixedNow)
    #expect(start == ISO8601DateFormatter().date(from: "2026-04-19T15:00:00Z"))
    // 일요일 밤(KST)은 아직 그 주다: 2026-07-19 23:30 KST = 14:30 UTC → 월요일 07-13.
    let sunday = ISO8601DateFormatter().date(from: "2026-07-19T14:30:00Z")!
    #expect(WorkDailyGrid.windowStart(now: sunday, weeks: 1) == ISO8601DateFormatter().date(from: "2026-07-12T15:00:00Z"))
}

// MARK: - 계획(바뀐 것만 · 하트비트)

@Test
func plannerSkipsMonthlyWhenZeroButSendsHeartbeat() {
    let config = ScanConfig(deviceId: "dev", name: "n", linkedAt: fixedNow)
    let empty = TokenUsageScanner.scan(homeDirectory: tempDir("empty"), now: fixedNow)
    let plan = ScanPlanner.plan(usage: empty, filesStatted: 0, diagnostics: nil, config: config, state: ScanState(), now: fixedNow)
    #expect(plan.payload.monthly == nil)
    #expect(plan.payload.daily.isEmpty)
    #expect(plan.payload.heartbeat.scanFiles == 0)
    #expect(plan.shouldSend)   // 첫 실행은 하트비트라도 보낸다
}

@Test
func plannerSendsOnlyWhatChanged() {
    let home = makeFixtureHome()
    let config = ScanConfig(deviceId: "dev", name: "n", linkedAt: fixedNow)
    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)
    #expect(usage.claudeTotal == 126)
    #expect(usage.codexTotal == 530)

    let first = ScanPlanner.plan(usage: usage, filesStatted: 2, diagnostics: nil, config: config, state: ScanState(), now: fixedNow)
    #expect(first.shouldSend)
    #expect(first.payload.monthly?.total == 656)
    #expect(!first.payload.daily.isEmpty)

    // 같은 숫자로 5분 뒤 → 보낼 것 없음.
    let later = fixedNow.addingTimeInterval(300)
    let second = ScanPlanner.plan(usage: usage, filesStatted: 2, diagnostics: nil, config: config, state: first.stateOnSuccess, now: later)
    #expect(!second.shouldSend)
    #expect(second.payload.daily.isEmpty)

    // 한 시간 뒤 → 하트비트 때문에 보낸다(일별 행은 여전히 없음).
    let hour = fixedNow.addingTimeInterval(3700)
    let third = ScanPlanner.plan(usage: usage, filesStatted: 2, diagnostics: nil, config: config, state: first.stateOnSuccess, now: hour)
    #expect(third.shouldSend)
    #expect(third.payload.daily.isEmpty)

    // 너무 잦은 실행(1분 뒤)은 바뀐 것이 있어도 보내지 않는다(서버 하한 2분).
    let soon = ScanPlanner.plan(usage: usage, filesStatted: 2, diagnostics: nil, config: config,
                                state: ScanState(lastUploadAt: fixedNow), now: fixedNow.addingTimeInterval(60))
    #expect(!soon.shouldSend)
}

@Test
func plannerMonthlyBodyIsTheAppsBody() throws {
    let home = makeFixtureHome()
    let usage = TokenUsageScanner.scan(homeDirectory: home, now: fixedNow)
    let config = ScanConfig(deviceId: "dev-9", name: "n", linkedAt: fixedNow)
    let plan = ScanPlanner.plan(usage: usage, filesStatted: 2, diagnostics: nil, config: config, state: ScanState(), now: fixedNow)
    let app = TokenUsageUpsertRequest.monthly(
        userID: "", usage: usage, deviceID: "dev-9", account: nil, accountStatus: nil, diagnostics: nil,
        formatDate: { ISO8601DateFormatter().string(from: $0) }
    )
    let enc = ScanStorage.encoder()
    #expect(try enc.encode(plan.payload.monthly) == enc.encode(app))
    // 계정 프로브는 원격 기계에서 돌리지 않는다 → codex_account_* 키가 아예 없다(서버의 맥북 계정값을 지우지 않는다).
    let body = try #require(try JSONSerialization.jsonObject(with: enc.encode(plan.payload.monthly)) as? [String: Any])
    #expect(body.keys.filter { $0.hasPrefix("codex_account") }.isEmpty)
    #expect(body["claude_input"] as? Int == 100)
    #expect(body["codex_input"] as? Int == 500)
}

// MARK: - 연결 → 첫 집계 → 다시 실행

@Test
func linkSavesPrivateKeyInstallsCronAndUploadsOnce() async throws {
    let home = makeFixtureHome()
    let transport = FakeTransport()
    transport.responses["rest/v1/rpc/scanner_link"] = linkOK
    let runner = FakeRunner()
    runner.crontab = "0 3 * * * /usr/bin/backup\n"
    let output = Output()
    let clock = Clock(fixedNow)
    let env = makeEnv(home: home, transport: transport, runner: runner, output: output, clock: clock)

    let exit = await ScanCommands(env: env).link(code: "abcd-efgh", name: nil, force: false, schedule: true)
    #expect(exit == .ok)

    // 서버에 보낸 연결 본문: 코드 정규화 · 이름 · OS.
    let linkCall = try #require(transport.calls.first)
    #expect(linkCall.path == "rest/v1/rpc/scanner_link")
    #expect(linkCall.body["p_code"] as? String == "ABCDEFGH")
    #expect(linkCall.body["p_name"] as? String == "devbox")
    #expect((linkCall.body["p_os"] as? String)?.hasPrefix("linux-") == true)

    // 키는 0600 파일에만 있고, 화면 출력에는 없다.
    let paths = env.paths
    #expect(ScanStorage.readKey(paths) == "SECRET-KEY-DO-NOT-PRINT")
    let perms = try FileManager.default.attributesOfItem(atPath: paths.key.path)[.posixPermissions] as? Int
    #expect(perms == 0o600)
    #expect(!output.lines.joined().contains("SECRET-KEY"))

    // 남의 crontab 줄은 그대로, 우리 줄 하나가 더해졌다.
    let cron = try #require(runner.crontab)
    #expect(cron.contains("/usr/bin/backup"))
    #expect(cron.components(separatedBy: Scheduler.cronMarker).count - 1 == 1)
    #expect(cron.contains("'/opt/test/aing-scan' run"))

    // 연결 직후 첫 집계가 올라갔다: 월 행 + 일별 + 하트비트 + 진단(첫 실행이라 실린다 — 빌드 게이트 52 이상).
    let upload = try #require(transport.calls.last)
    #expect(upload.path == "rest/v1/rpc/scanner_upload")
    #expect(upload.body["p_key"] as? String == "SECRET-KEY-DO-NOT-PRINT")
    let payload = try #require(upload.body["p_payload"] as? [String: Any])
    let monthly = try #require(payload["monthly"] as? [String: Any])
    #expect(monthly["device_id"] as? String == "11111111-2222-3333-4444-555555555555")
    #expect(monthly["total"] as? Int == 656)
    #expect((monthly["codex_diag_build"] as? Int ?? 0) >= 52)
    #expect((payload["daily"] as? [Any])?.isEmpty == false)
    #expect((payload["heartbeat"] as? [String: Any])?["scan_files"] as? Int == 2)
    #expect(payload["build"] as? Int == AingScanBuild.sharedCodeAppBuild)

    // 5분 뒤 다시 실행 → 바뀐 것이 없어 서버에 가지 않는다.
    clock.now = fixedNow.addingTimeInterval(300)
    let before = transport.calls.count
    #expect(await ScanCommands(env: env).run(quiet: true) == .ok)
    #expect(transport.calls.count == before)

    // 기록이 늘면(Claude 한 줄 추가) 다음 실행이 올린다.
    clock.now = fixedNow.addingTimeInterval(600)
    let more = claudeLine(id: "m2", request: "r2", at: fixedNow.addingTimeInterval(500), input: 10, output: 0, cacheRead: 0, cacheCreation: 0)
    write(more + "\n", to: home.appendingPathComponent(".claude/projects/p1/b.jsonl"), modified: clock.now)
    #expect(await ScanCommands(env: env).run(quiet: true) == .ok)
    let again = try #require(transport.calls.last?.body["p_payload"] as? [String: Any])
    #expect((again["monthly"] as? [String: Any])?["total"] as? Int == 666)
    // 진단은 하루 한 번 — 두 번째 올림에는 없다.
    #expect((again["monthly"] as? [String: Any])?["codex_diag_build"] == nil)
}

@Test
func linkRefusesOnMacWithTheAppUnlessForced() async {
    let home = tempDir("mac")
    let transport = FakeTransport()
    transport.responses["rest/v1/rpc/scanner_link"] = linkOK
    let output = Output()
    let env = makeEnv(home: home, transport: transport, runner: FakeRunner(), output: output, clock: Clock(fixedNow),
                      platform: .macOS, macApp: true)
    #expect(await ScanCommands(env: env).link(code: "ABCDEFGH", name: nil, force: false, schedule: false) == .refused)
    #expect(transport.calls.isEmpty)   // 서버에 아예 가지 않는다
    #expect(output.lines.joined().contains("앱이 이미"))
}

@Test
func linkRejectedCodeExplainsAndSavesNothing() async {
    let home = tempDir("reject")
    let transport = FakeTransport()
    transport.responses["rest/v1/rpc/scanner_link"] = (200, "{\"ok\":false,\"reason\":\"expired\"}")
    let output = Output()
    let env = makeEnv(home: home, transport: transport, runner: FakeRunner(), output: output, clock: Clock(fixedNow))
    #expect(await ScanCommands(env: env).link(code: "ABCDEFGH", name: nil, force: false, schedule: true) == .refused)
    #expect(output.lines.joined().contains("만료"))
    #expect(ScanStorage.readKey(env.paths) == nil)
}

// MARK: - 끊기(앱에서 끊음 · 직접 끊음)

@Test
func revokedKeyStopsScheduleAndClearsKey() async throws {
    let home = makeFixtureHome()
    let transport = FakeTransport()
    transport.responses["rest/v1/rpc/scanner_link"] = linkOK
    let runner = FakeRunner()
    let output = Output()
    let clock = Clock(fixedNow)
    let env = makeEnv(home: home, transport: transport, runner: runner, output: output, clock: clock)
    _ = await ScanCommands(env: env).link(code: "ABCDEFGH", name: "srv", force: false, schedule: true)
    #expect(runner.crontab?.contains(Scheduler.cronMarker) == true)

    transport.responses["rest/v1/rpc/scanner_upload"] = (200, "{\"ok\":false,\"reason\":\"revoked\"}")
    clock.now = fixedNow.addingTimeInterval(4000)
    #expect(await ScanCommands(env: env).run(quiet: true) == .refused)
    #expect(ScanStorage.readKey(env.paths) == nil)
    #expect(runner.crontab?.contains(Scheduler.cronMarker) == false)
    #expect(ScanStorage.load(ScanConfig.self, from: env.paths.config)?.linked == false)

    // 끊긴 뒤의 예약 실행은 서버에 가지 않는다.
    let before = transport.calls.count
    #expect(await ScanCommands(env: env).run(quiet: true) == .ok)
    #expect(transport.calls.count == before)
}

@Test
func unlinkCallsServerAndTurnsOffLaunchAgentWithoutDeleting() async throws {
    let home = tempDir("unlink")
    let transport = FakeTransport()
    transport.responses["rest/v1/rpc/scanner_link"] = linkOK
    let runner = FakeRunner()
    let output = Output()
    let env = makeEnv(home: home, transport: transport, runner: runner, output: output, clock: Clock(fixedNow), platform: .macOS)
    _ = await ScanCommands(env: env).link(code: "ABCDEFGH", name: nil, force: false, schedule: true)
    #expect(env.scheduler.isInstalled())
    #expect(runner.commands.contains { $0.hasPrefix("/bin/launchctl bootstrap gui/501 ") })

    #expect(await ScanCommands(env: env).unlink() == .ok)
    #expect(transport.calls.contains { $0.path == "rest/v1/rpc/scanner_unlink" })
    #expect(!env.scheduler.isInstalled())
    // plist 는 남아 있되 꺼져 있다(Disabled).
    #expect(FileManager.default.fileExists(atPath: env.scheduler.launchAgentURL.path))
    #expect(ScanStorage.readKey(env.paths) == nil)
}

// MARK: - 예약 줄

@Test
func cronInstallIsIdempotent() throws {
    let runner = FakeRunner()
    let s = Scheduler(platform: .linux, home: tempDir("cron"), runner: runner, uid: 1000)
    try s.install(binary: "/home/u/.aing-scan/bin/aing-scan")
    try s.install(binary: "/home/u/.aing-scan/bin/aing-scan")
    #expect(runner.crontab?.components(separatedBy: Scheduler.cronMarker).count == 2)   // 한 줄
    try s.remove(binary: "/home/u/.aing-scan/bin/aing-scan")
    #expect(runner.crontab == "")
}

@Test
func codeNormalizationStripsSeparators() {
    #expect(ScanCommands.normalizeCode(" ab12-cd34 ") == "AB12CD34")
    #expect(ScanCommands.normalizeCode("x").count == 1)
}
