import Foundation
import Observation
import os

// MARK: - Codex 계정 사용량 (로컬 `codex app-server` 의 account/usage/read)

/// Codex **계정** 의 일별 토큰 사용량 스냅샷. 로컬 `codex app-server` 에 JSON-RPC `account/usage/read` 를 보내 받는다.
///
/// 왜 필요한가(issue #6): 로컬 rollout 스캔은 보관(`archived_sessions` 로 rename)·압축(7일 지난 rollout 을 `.zst` 로
/// 바꾸고 원본 삭제)에서 이번 달 기여를 잃어 계정 집계보다 46% 적게 나온 사례가 있다. 스캐너의 유실은 v0.2.41 에서
/// 수리했지만(CheckTokenUsage.scanCodex), **이미 `.zst` 만 남은 파일은 어떤 스캐너도 못 읽는다**(macOS SDK 에 zstd 디코더가
/// 없다). 그 구멍을 계정 집계가 메운다 — 서버 보드는 로컬 합과 계정 월합 중 큰 쪽을 쓴다(20260903120000 마이그레이션).
///
/// 값의 성질(실측, codex-cli 0.144.1):
/// - `buckets` 의 날짜는 **UTC 일자**다(로컬 이벤트 델타를 UTC/KST 로 각각 일별 합산해 대조 — UTC 가 3~10% 오차로 일치).
/// - 단위는 input(캐시 포함)+output = 로컬 스캐너의 `codexInput+codexOutput` 과 같은 단위.
/// - 계정 집계는 **다른 기기·Codex 클라우드/IDE 사용까지 포함**한다. 맥 2대가 같은 계정값을 올리므로 서버는 합이 아니라 max 를 쓴다.
/// - 반영 지연이 수십 분 이상이라 실시간은 로컬 집계가 맡고, 이 값은 30분마다 한 번 갱신한다.
///
/// 프라이버시: 여기 담기는 것은 숫자(일별 토큰·누적)와 시각뿐이다. `~/.codex/auth.json` 은 **존재 여부만** 본다(토큰이 들어
/// 있어 내용은 읽지 않는다).
struct CodexAccountUsage: Codable, Equatable, Sendable {
    /// 이 스냅샷을 받은 시각(앱 시계).
    var fetchedAt: Date
    /// 계정 누적 토큰(`summary.lifetimeTokens`). 프로토콜상 null 일 수 있다.
    var lifetimeTokens: Int?
    /// UTC 'YYYY-MM-DD' → 그 날 토큰. 최근 `retentionDays` 일만 보관한다(스냅샷이 UserDefaults 에 영속되므로 무한히 자라지 않게).
    var buckets: [String: Int]

    /// 버킷 보관 일수. 월 롤오버 직후에도 지난달 전체가 남아 있게 두 달을 넉넉히 덮는 70일.
    static let retentionDays = 70

    init(fetchedAt: Date, lifetimeTokens: Int?, buckets: [String: Int]) {
        self.fetchedAt = fetchedAt
        self.lifetimeTokens = lifetimeTokens
        self.buckets = buckets
    }

    /// 'YYYY-MM' 월의 버킷 합(접두어 매칭). 버킷이 UTC 일자라 이 합은 **UTC 월**이고 로컬 집계는 KST 월이다(경계 9시간 차) —
    /// 월간 순위 용도에선 허용한다(스펙 미결 항목으로 문서화).
    func monthTotal(_ month: String) -> Int {
        let prefix = month + "-"
        var sum = 0
        for (day, tokens) in buckets where day.hasPrefix(prefix) { sum += tokens }
        return sum
    }

    /// 가장 최근 버킷 날짜(고정폭 'YYYY-MM-DD' 라 사전식 최대 = 최신). 버킷이 없으면 nil.
    var latestBucketDate: String? { buckets.keys.max() }

    /// 그 월 안에서 가장 최근 버킷 날짜. 툴팁의 "D일까지 반영" 이 쓴다 — 지난달 버킷을 이번 달 반영일로 오인하지 않게 월을 가른다.
    func latestBucketDate(in month: String) -> String? {
        let prefix = month + "-"
        return buckets.keys.filter { $0.hasPrefix(prefix) }.max()
    }

    /// `fetchedAt` 기준 `retentionDays` 일 이전 버킷을 버린 사본. 날짜 문자열이 고정폭이라 컷오프 문자열과의 사전식 비교로 충분하다.
    func pruned() -> CodexAccountUsage {
        let cutoffDate = fetchedAt.addingTimeInterval(-TimeInterval(Self.retentionDays) * 86_400)
        let cutoff = Self.utcDayString(cutoffDate)
        var copy = self
        copy.buckets = buckets.filter { $0.key >= cutoff }
        return copy
    }

    /// Date → UTC 'YYYY-MM-DD'. 버킷 키와 같은 축(UTC)이다.
    static func utcDayString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 프로브 결과 상태. 원시값이 서버 컬럼 `token_usage_device_monthly.codex_account_status`(smallint) 에 그대로 올라간다 —
/// 값을 바꾸거나 재배열하지 마라(서버 진단 `token_scan_health()` 가 이 숫자를 읽는다).
enum CodexAccountProbeStatus: Int, Codable, Equatable, Sendable {
    /// 계정 사용량을 받았다.
    case ok = 1
    /// 로그인 셸·폴백 후보 어디에도 `codex` 실행 파일이 없다.
    case codexNotInstalled = 2
    /// `~/.codex/auth.json` 부재(프로세스를 띄우지 않고 판정) 또는 서버가 인증 오류를 돌려줌(API 키 로그인 포함).
    case notLoggedIn = 3
    /// 15초 데드라인 안에 응답이 없어 프로세스를 죽였다.
    case timeout = 4
    /// 그 밖의 실패(응답 없이 종료·파싱 불가·error 응답).
    case failed = 5
}

/// `codex app-server` 를 띄워 `account/usage/read` 를 한 번 묻는 순수+Process 프로브. 상태는 실행 파일 위치 캐시뿐이다.
///
/// 절대 규칙: 테스트는 `parse(lines:)`·`requestLines(appVersion:)`·`fallbackCandidates(homeDirectory:)` 같은 순수 함수만 부른다.
/// `fetch`/`run`/`locateCodex` 는 실제 프로세스를 띄우므로 프로덕션 러너(`CodexAccountUsageStore.live()`)에서만 쓴다.
enum CodexAccountUsageProbe {
    /// 프로브 실패. status 가 서버에 올라가고 reason 은 로컬 진단용(서버에 보내지 않는다 — 문자열은 어디에도 싣지 않는다).
    struct Failure: Error, Equatable, Sendable {
        var status: CodexAccountProbeStatus
        var reason: String
    }

    /// 찾아낸 실행 파일과, 그것을 띄울 때 넘길 환경. npm 전역 `codex` 는 `#!/usr/bin/env node` 셸 스크립트라 실행 시 PATH 에
    /// node 가 있어야 한다 — 그래서 로그인 셸의 PATH 를 그대로 자식 env 에 넘긴다(GUI 앱의 PATH 는 `/usr/bin:/bin:/usr/sbin:/sbin` 뿐).
    struct Toolchain: Equatable, Sendable {
        var executable: URL
        var environment: [String: String]
    }

    /// 로그인 셸 조회 제한(초). `/bin/zsh -lc 'command -v codex'` 는 실측 42ms 지만 느린 dotfile(nvm 초기화 등)을 감안한다.
    nonisolated static let shellLookupTimeout: TimeInterval = 5
    /// 프로세스 총 데드라인(초). 실측 initialize 0.09s + usage 0.77s. 서버 내부 타임아웃 10초보다 길게 둔다.
    nonisolated static let fetchDeadline: TimeInterval = 15
    /// terminate() 뒤 SIGKILL 까지의 유예(초).
    nonisolated static let killGrace: TimeInterval = 2
    /// 실행 파일 탐색 실패의 캐시 수명(초). 성공은 프로세스 수명 동안 캐시한다.
    nonisolated static let locateFailureTTL: TimeInterval = 1800
    /// `account/usage/read` 요청 id. 응답 줄은 이 id 로만 고른다(초기화 응답·알림 줄이 앞뒤로 섞여 온다).
    nonisolated static let usageRequestID = 2

    // MARK: 실행 파일 탐색 (프로세스 수명 캐시)

    private struct LocateState {
        var toolchain: Toolchain?
        var codexHome: URL?
        var failedAt: Date?
    }

    private static let locateState = OSAllocatedUnfairLock(initialState: LocateState())

    /// 로그인 셸에서 `CODEX_HOME` 이 설정돼 있으면 그 경로. **탐색을 새로 하지 않는다** — 이미 캐시된 결과만 돌려주므로
    /// 토큰 스캐너가 이것을 읽어도 셸이 뜨지 않는다(테스트에서 프로세스가 새는 통로를 막는다). 첫 프로브 전엔 nil.
    static func cachedCodexHome() -> URL? {
        locateState.withLock { $0.codexHome }
    }

    /// `codex` 실행 파일을 찾는다: 로그인 셸(`/bin/zsh -lc`) 조회 → 실패하면 폴백 후보 순회. 결과는 프로세스 수명 동안 캐시하고
    /// 실패도 `locateFailureTTL` 동안 캐시한다(30분마다 도는 프로브가 매번 셸을 띄우지 않게).
    static func locateCodex(homeDirectory: URL, now: Date = Date()) -> Toolchain? {
        let cached: Toolchain?? = locateState.withLock { state in
            if let t = state.toolchain { return .some(t) }
            if let failedAt = state.failedAt, now.timeIntervalSince(failedAt) < locateFailureTTL { return .some(nil) }
            return nil
        }
        if let cached { return cached }

        var environment = ProcessInfo.processInfo.environment
        var executable: URL?
        var codexHome: URL?
        if let shell = shellLookup(timeout: shellLookupTimeout) {
            if let path = shell.path, !path.isEmpty { environment["PATH"] = path }
            if let home = shell.codexHome, !home.isEmpty { codexHome = URL(fileURLWithPath: home, isDirectory: true) }
            if let codex = shell.codex, !codex.isEmpty, FileManager.default.isExecutableFile(atPath: codex) {
                executable = URL(fileURLWithPath: codex)
            }
        }
        if executable == nil {
            executable = fallbackCandidates(homeDirectory: homeDirectory).first {
                FileManager.default.isExecutableFile(atPath: $0.path)
            }
            // 폴백으로 찾은 npm 셸 스크립트가 node 를 찾을 수 있게 흔한 node 위치를 PATH 앞에 덧붙인다.
            let extra = ["/opt/homebrew/bin", "/usr/local/bin", homeDirectory.appendingPathComponent(".volta/bin").path]
            environment["PATH"] = (extra + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        }
        if let codexHome { environment["CODEX_HOME"] = codexHome.path }

        let toolchain = executable.map { Toolchain(executable: $0, environment: environment) }
        let resolvedCodexHome = codexHome
        locateState.withLock { state in
            state.codexHome = resolvedCodexHome
            state.toolchain = toolchain
            state.failedAt = toolchain == nil ? now : nil
        }
        return toolchain
    }

    /// 폴백 후보(순서대로). npm/homebrew/volta/bun/nvm 전역과 IDE 확장이 번들한 네이티브 바이너리(이 맥에 실재).
    /// 순수 함수: 존재 여부는 호출측이 본다(테스트는 목록 규칙만 고정한다).
    static func fallbackCandidates(homeDirectory: URL) -> [URL] {
        let home = homeDirectory
        var out: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".volta/bin/codex"),
            home.appendingPathComponent(".bun/bin/codex"),
            home.appendingPathComponent(".local/bin/codex")
        ]
        // ~/.nvm/versions/node/*/bin/codex — 최신 node 부터.
        let nvm = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) {
            for v in versions.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
                out.append(nvm.appendingPathComponent("\(v)/bin/codex"))
            }
        }
        // IDE 확장 번들: ~/.cursor|.vscode/extensions/openai.chatgpt-*/bin/macos-*/codex
        for ide in [".cursor", ".vscode"] {
            let ext = home.appendingPathComponent("\(ide)/extensions", isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: ext.path) else { continue }
            for name in names.filter({ $0.hasPrefix("openai.chatgpt-") }).sorted(by: >) {
                let bin = ext.appendingPathComponent("\(name)/bin", isDirectory: true)
                guard let archs = try? FileManager.default.contentsOfDirectory(atPath: bin.path) else { continue }
                for arch in archs.filter({ $0.hasPrefix("macos-") }).sorted() {
                    out.append(bin.appendingPathComponent("\(arch)/codex"))
                }
            }
        }
        return out
    }

    /// 로그인 셸에서 PATH·CODEX_HOME·codex 경로를 NUL 구분으로 뽑는다. 제한 시간 안에 안 끝나면 죽이고 nil.
    private static func shellLookup(timeout: TimeInterval) -> (path: String?, codexHome: String?, codex: String?)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "printf '%s\\0%s\\0%s\\0' \"$PATH\" \"${CODEX_HOME-}\" \"$(command -v codex 2>/dev/null)\""]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let reader = stdout.fileHandleForReading
        let collected = OSAllocatedUnfairLock(initialState: Data())
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            let data = reader.readDataToEndOfFile()
            collected.withLock { $0 = data }
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 1)
            return nil
        }
        process.waitUntilExit()
        let data = collected.withLock { $0 }
        let parts = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        guard parts.count >= 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    // MARK: 요청/응답 (순수)

    /// stdio JSONL 요청 3줄(한 줄 = 한 메시지). initialize(id 1) → initialized 알림 → account/usage/read(id 2).
    static func requestLines(appVersion: String) -> [String] {
        let version = appVersion.replacingOccurrences(of: "\"", with: "")
        return [
            "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"aing-check\",\"title\":\"aing-check\",\"version\":\"\(version)\"}}}",
            "{\"method\":\"initialized\",\"params\":{}}",
            "{\"method\":\"account/usage/read\",\"id\":\(usageRequestID)}"
        ]
    }

    /// 응답 줄들을 파싱한다. **`id == requestID` 인 줄만** 쓴다 — 초기화 응답(id 1)·알림(`remoteControl/status/changed` 등)·
    /// 잘린 JSON 이 섞여 와도 무시한다. 그 줄에 `error` 가 있으면 실패(인증 문구면 `.notLoggedIn`), `result` 가 있으면
    /// `summary.lifetimeTokens`(null 허용)와 `dailyUsageBuckets`(null 허용 → 빈 맵)을 읽는다. 해당 줄이 없으면 `.failed`.
    static func parse(lines: [String], requestID: Int = usageRequestID, fetchedAt: Date) -> Result<CodexAccountUsage, Failure> {
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, id.intValue == requestID
            else { continue }
            if let error = object["error"] {
                let message = (error as? [String: Any])?["message"] as? String ?? String(describing: error)
                let status: CodexAccountProbeStatus =
                    message.range(of: "auth", options: .caseInsensitive) != nil ? .notLoggedIn : .failed
                return .failure(Failure(status: status, reason: message))
            }
            guard let result = object["result"] as? [String: Any] else {
                return .failure(Failure(status: .failed, reason: "result 없음"))
            }
            let summary = result["summary"] as? [String: Any]
            let lifetime = (summary?["lifetimeTokens"] as? NSNumber).map { Int($0.int64Value) }
            var buckets: [String: Int] = [:]
            if let daily = result["dailyUsageBuckets"] as? [[String: Any]] {
                for bucket in daily {
                    guard let day = bucket["startDate"] as? String, day.count >= 10,
                          let tokens = bucket["tokens"] as? NSNumber else { continue }
                    // 고정폭 'YYYY-MM-DD' 접두어만 키로 쓴다(서버가 시각을 붙여 보내더라도 일 단위로 접는다).
                    buckets[String(day.prefix(10)), default: 0] += Int(tokens.int64Value)
                }
            }
            return .success(CodexAccountUsage(fetchedAt: fetchedAt, lifetimeTokens: lifetime, buckets: buckets).pruned())
        }
        return .failure(Failure(status: .failed, reason: "id \(requestID) 응답 줄 없음"))
    }

    // MARK: 실행 (Process)

    /// 실행 파일을 찾아 프로브를 한 번 돈다. 못 찾으면 `.codexNotInstalled`. 프로덕션 러너 전용.
    static func fetch(homeDirectory: URL, appVersion: String, now: Date = Date()) async -> Result<CodexAccountUsage, Failure> {
        guard let toolchain = locateCodex(homeDirectory: homeDirectory, now: now) else {
            return .failure(Failure(status: .codexNotInstalled, reason: "codex 실행 파일 없음"))
        }
        return await run(toolchain: toolchain, homeDirectory: homeDirectory, appVersion: appVersion, now: now)
    }

    /// `codex app-server` 를 띄워 요청 3줄을 쓰고, stdout 을 **비동기로 계속 읽으며**(파이프 버퍼 교착 방지) id 2 응답 줄이
    /// 오면 끝낸다. 총 `fetchDeadline` 뒤 terminate() → `killGrace` 뒤 SIGKILL. stderr 는 /dev/null.
    static func run(
        toolchain: Toolchain, homeDirectory: URL, appVersion: String,
        deadline: TimeInterval = fetchDeadline, killGrace: TimeInterval = killGrace, now: Date = Date()
    ) async -> Result<CodexAccountUsage, Failure> {
        let session = ProcessSession(
            toolchain: toolchain, homeDirectory: homeDirectory,
            request: requestLines(appVersion: appVersion).joined(separator: "\n") + "\n",
            deadline: deadline, killGrace: killGrace
        )
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<ProcessSession.Outcome, Never>) in
            session.start { continuation.resume(returning: $0) }
        }
        switch outcome {
        case .responded(let lines):
            return parse(lines: lines, fetchedAt: now)
        case .timeout:
            return .failure(Failure(status: .timeout, reason: "\(Int(deadline))초 안에 응답 없음"))
        case .exited(let lines):
            // 응답 없이 끝났어도 그때까지 받은 줄에 답이 있을 수 있다(종료 직전에 흘려보낸 경우).
            let parsed = parse(lines: lines, fetchedAt: now)
            if case .success = parsed { return parsed }
            if case .failure(let f) = parsed, f.status == .notLoggedIn { return parsed }
            return .failure(Failure(status: .failed, reason: "응답 없이 종료"))
        case .launchFailed(let reason):
            return .failure(Failure(status: .failed, reason: reason))
        }
    }

    /// Process/Pipe 를 한 곳에 가두고 잠금으로 상태를 지킨다(Swift 6: Process 는 Sendable 이 아니다).
    /// 완료 콜백은 정확히 한 번 불린다(readability·termination·deadline 어느 쪽이 먼저 오든).
    private final class ProcessSession: @unchecked Sendable {
        enum Outcome: Sendable {
            case responded([String])
            case exited([String])
            case timeout
            case launchFailed(String)
        }

        private struct State {
            var buffer = Data()
            var lines: [String] = []
            var finished = false
        }

        private let toolchain: Toolchain
        private let homeDirectory: URL
        private let request: String
        private let deadline: TimeInterval
        private let killGrace: TimeInterval
        private let process = Process()
        private let stdin = Pipe()
        private let stdout = Pipe()
        private let state = OSAllocatedUnfairLock(initialState: State())
        private var completion: (@Sendable (Outcome) -> Void)?

        init(toolchain: Toolchain, homeDirectory: URL, request: String, deadline: TimeInterval, killGrace: TimeInterval) {
            self.toolchain = toolchain
            self.homeDirectory = homeDirectory
            self.request = request
            self.deadline = deadline
            self.killGrace = killGrace
        }

        func start(_ completion: @escaping @Sendable (Outcome) -> Void) {
            self.completion = completion
            process.executableURL = toolchain.executable
            process.arguments = ["app-server"]
            process.environment = toolchain.environment
            process.currentDirectoryURL = homeDirectory
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            let reader = stdout.fileHandleForReading
            reader.readabilityHandler = { [weak self] handle in
                self?.consume(handle.availableData)
            }
            process.terminationHandler = { [weak self] _ in
                self?.finish(exitedNormally: true)
            }
            do {
                try process.run()
            } catch {
                reader.readabilityHandler = nil
                finish(with: .launchFailed(error.localizedDescription))
                return
            }
            // 요청 3줄. 파이프의 읽는 쪽이 먼저 닫히면 write 가 SIGPIPE 로 **우리 프로세스를** 죽인다 — fd 단위로 끈다.
            let writer = stdin.fileHandleForWriting
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? writer.write(contentsOf: Data(request.utf8))
            // 총 데드라인. 응답이 먼저 오면 finish 가 이미 끝내 둔 상태라 no-op.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deadline) { [weak self] in
                self?.finish(with: .timeout)
            }
        }

        /// stdout 조각을 모아 완결 줄로 자른다. id 2 응답 줄을 보면 즉시 끝낸다.
        private func consume(_ data: Data) {
            if data.isEmpty {
                // EOF — 프로세스가 stdout 을 닫았다(종료 직전). terminationHandler 가 마무리한다.
                return
            }
            let done: [String]? = state.withLock { s -> [String]? in
                guard !s.finished else { return nil }
                s.buffer.append(data)
                while let nl = s.buffer.firstIndex(of: 0x0A) {
                    let lineData = s.buffer[s.buffer.startIndex..<nl]
                    s.buffer.removeSubrange(s.buffer.startIndex...nl)
                    s.lines.append(String(decoding: lineData, as: UTF8.self))
                }
                let hasAnswer = s.lines.contains { CodexAccountUsageProbe.lineHasUsageResponseID($0) }
                return hasAnswer ? s.lines : nil
            }
            if let done { finish(with: .responded(done)) }
        }

        /// 종료 이벤트: 남은 stdout 을 마저 읽고(쓰는 쪽이 닫혔으니 즉시 돌아온다) 끝낸다.
        private func finish(exitedNormally: Bool) {
            let reader = stdout.fileHandleForReading
            reader.readabilityHandler = nil
            if let rest = try? reader.readToEnd(), !rest.isEmpty {
                state.withLock { s in
                    guard !s.finished else { return }
                    s.buffer.append(rest)
                }
            }
            let lines: [String] = state.withLock { s in
                if !s.buffer.isEmpty {
                    s.lines.append(String(decoding: s.buffer, as: UTF8.self))
                    s.buffer.removeAll()
                }
                return s.lines
            }
            let answered = lines.contains { CodexAccountUsageProbe.lineHasUsageResponseID($0) }
            finish(with: answered ? .responded(lines) : .exited(lines))
        }

        /// 정확히 한 번만 완료한다. 아직 살아 있으면 terminate → killGrace 뒤 SIGKILL. stdin 은 여기서 닫는다.
        private func finish(with outcome: Outcome) {
            let first: Bool = state.withLock { s in
                guard !s.finished else { return false }
                s.finished = true
                return true
            }
            guard first else { return }
            stdout.fileHandleForReading.readabilityHandler = nil
            try? stdin.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                let pid = process.processIdentifier
                // 유예 뒤 SIGKILL. **강한 캡처**다 — 완료 직후 세션이 해제되면 약참조는 nil 이 되어 SIGTERM 을 무시한 프로세스가
                // 영영 남는다. 세션을 2초 더 붙들어 두는 비용뿐이다.
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killGrace) {
                    if self.process.isRunning { kill(pid, SIGKILL) }
                }
            }
            let completion = self.completion
            self.completion = nil
            completion?(outcome)
        }
    }

    /// 줄이 `"id":2` 응답인지의 값싼 판별(전체 JSON 파싱 전 프리체크). 최종 판정은 parse 가 한다.
    static func lineHasUsageResponseID(_ line: String) -> Bool {
        guard line.contains("\"id\"") else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let id = object["id"] as? NSNumber else { return false }
        return id.intValue == usageRequestID
    }
}

// MARK: - 스토어 (@MainActor · 30분 간격 · 영속)

/// 계정 사용량 스냅샷의 갱신 간격·영속·상태를 담당한다. 프로브 실행은 주입된 `runner` 에 위임하므로 테스트는 실제 `codex` 를
/// 절대 띄우지 않는다(`inert()`/러너 주입).
///
/// 게이트 순서(refreshIfDue): 재진입 금지 → 간격(1800초, force 면 무시) → `~/.codex/auth.json` 부재면 프로세스 없이
/// `.notLoggedIn` → 러너. 스탬프(lastProbeAt)는 러너를 부르기 **전에** 찍어 실패도 30분 동안 재시도하지 않는다(난사 방지 —
/// uploadTokenUsageIfNeeded 의 lastTokenUploadAt 과 같은 관용구).
///
/// 영속(UserDefaults `check.codexAccount.snapshot`): 버킷이 날짜별이라 월 롤오버에 안전하다 — 복원 시 월을 따지지 않는다
/// (TokenUsageStore 의 월 일치 게이트와 다른 이유: 저쪽은 '한 달 합' 하나라 달이 바뀌면 의미가 없지만, 이쪽은 `monthTotal(month)` 가
/// 조회 시점에 달을 가른다).
@Observable
@MainActor
final class CodexAccountUsageStore {
    typealias Runner = @Sendable (_ homeDirectory: URL, _ now: Date) async -> Result<CodexAccountUsage, CodexAccountUsageProbe.Failure>

    nonisolated static let snapshotKey = "check.codexAccount.snapshot"
    /// 프로브 간격(초). 계정 버킷의 반영 지연이 수십 분이라 더 자주 물어도 새 값이 없다.
    nonisolated static let refreshInterval: TimeInterval = 1800
    /// force 여도 지키는 하한(초). 월 롤오버 판정은 KST 월 경계 창에서 여러 틱 연속 참일 수 있는데(WorkTimerStoreSync 의
    /// refreshTokenUsageInBackgroundIfDue ★ 주석과 같은 경로), 하한이 없으면 30초 틱마다 `codex app-server` 를 띄운다.
    nonisolated static let forcedRefreshFloor: TimeInterval = 60

    /// 마지막으로 받은 계정 스냅샷(실패해도 직전 값을 유지 — 버킷은 날짜별이라 낡아도 틀리지 않는다).
    private(set) var snapshot: CodexAccountUsage?
    /// 마지막 프로브의 상태. 서버 `codex_account_status` 로 올라간다.
    private(set) var lastStatus: CodexAccountProbeStatus?
    /// 마지막 프로브 **시도** 시각(주입 시계). 간격 판정의 기준.
    private(set) var lastProbeAt: Date?
    /// 러너가 불린 횟수(테스트 계측 — auth.json 부재·간격·재진입 가드가 프로세스를 실제로 막는지).
    @ObservationIgnored private(set) var runnerCallCount = 0
    @ObservationIgnored private var inFlight = false

    private let defaults: UserDefaults
    private let homeDirectory: URL
    private let clock: () -> Date
    private let runner: Runner

    init(
        defaults: UserDefaults,
        homeDirectory: URL,
        clock: @escaping () -> Date = { Date() },
        runner: @escaping Runner
    ) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        self.clock = clock
        self.runner = runner
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(CodexAccountUsage.self, from: data) {
            snapshot = restored
        }
    }

    /// 프로덕션 조립: 실홈 + 실제 프로브. **CheckApp 한 곳에서만** 만든다(소스 계약 테스트가 되묻는다).
    static func live(defaults: UserDefaults = .standard) -> CodexAccountUsageStore {
        let version = UpdateCheckStore.bundleShortVersion()
        return CodexAccountUsageStore(
            defaults: defaults,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            runner: { home, now in
                await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: version, now: now)
            }
        )
    }

    /// 무해 인스턴스: 존재하지 않는 홈(auth.json 부재 → 러너 미호출)·격리 defaults·호출되면 실패를 돌려주는 러너.
    /// WorkTimerStore 의 기본값이라, 주입을 잊은 테스트가 실제 `codex` 를 띄우는 일이 구조적으로 없다(fail-closed).
    static func inert() -> CodexAccountUsageStore {
        let name = "check.codexAccount.inert.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return CodexAccountUsageStore(
            defaults: defaults,
            homeDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("check-codex-account-inert-\(UUID().uuidString)", isDirectory: true),
            runner: { _, _ in .failure(.init(status: .codexNotInstalled, reason: "inert")) }
        )
    }

    /// 간격이 찼는지. 진행 중이면 거짓. force 는 1800초 간격을 무시하되 60초 하한은 지킨다.
    func isDue(now: Date, force: Bool = false) -> Bool {
        if inFlight { return false }
        guard let last = lastProbeAt else { return true }
        let elapsed = now.timeIntervalSince(last)
        return force ? elapsed >= Self.forcedRefreshFloor : elapsed >= Self.refreshInterval
    }

    /// 간격(1800초)이 찼을 때만 프로브를 돈다. `force` 는 월 롤오버처럼 '지금 값이 없다'가 이유일 때 쓴다(60초 하한은 유지).
    func refreshIfDue(now: Date, force: Bool = false) async {
        guard isDue(now: now, force: force) else { return }
        lastProbeAt = now
        // auth.json 이 없으면 로그인 안 된 것 — 프로세스를 띄우지 않는다(파일 내용은 읽지 않는다, 존재 여부만).
        let authPath = homeDirectory.appendingPathComponent(".codex/auth.json").path
        guard FileManager.default.fileExists(atPath: authPath) else {
            lastStatus = .notLoggedIn
            return
        }
        inFlight = true
        runnerCallCount += 1
        let result = await runner(homeDirectory, now)
        inFlight = false
        switch result {
        case .success(let usage):
            snapshot = usage
            lastStatus = .ok
            if let data = try? JSONEncoder().encode(usage) {
                defaults.set(data, forKey: Self.snapshotKey)
            }
        case .failure(let failure):
            lastStatus = failure.status
        }
    }
}

// MARK: - 표시 산식 (순수)

/// 내 팝오버 행의 표시 총합. 로컬 6필드 합(`TokenUsageMonthly.total`, 업로드값)은 건드리지 않고, **표시**만
/// `claudeTotal + max(codexTotal, 계정 월합)` 으로 한다 — 서버 보드가 `greatest(codex_local, codex_account)` 로 하는 것과 같은 규칙이라
/// 내 행과 순위판의 내 숫자가 어긋나지 않는다.
enum TokenUsageDisplay {
    static func effectiveTotal(local: TokenUsageMonthly, accountMonth: Int?) -> Int {
        local.claudeTotal + max(local.codexTotal, max(0, accountMonth ?? 0))
    }
}
