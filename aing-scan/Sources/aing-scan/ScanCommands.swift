import CheckTokenScan
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// 명령이 바깥 세상과 닿는 자리 전부. 시험은 홈·환경·서버·명령 실행기·시계를 통째로 바꿔 넣는다
/// (운영 서버·실제 홈·실제 예약을 건드리지 않는다).
struct ScanEnvironment: Sendable {
    var home: URL
    var environment: [String: String]
    var transport: ScanTransport?
    var runner: CommandRunner
    var platform: Scheduler.Platform
    var uid: UInt32
    var now: @Sendable () -> Date
    /// 이 맥에 아잉체크 앱이 있어 이미 집계하는가(맥만). 있으면 연결을 멈춘다 — 같은 맥을 두 번 세지 않게.
    var macAppPresent: @Sendable () -> Bool
    var executablePath: String
    var hostName: String
    var output: @Sendable (String) -> Void

    var paths: ScanPaths { ScanPaths.standard(home: home, environment: environment) }
    var scheduler: Scheduler { Scheduler(platform: platform, home: home, runner: runner, uid: uid) }

    static func live() -> ScanEnvironment {
        let env = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory(), isDirectory: true)
        #if os(macOS)
        let platform = Scheduler.Platform.macOS
        #else
        let platform = Scheduler.Platform.linux
        #endif
        let server = env["AING_SCAN_SERVER"].flatMap { URL(string: $0) } ?? AingScanBuild.defaultServer
        let anon = AingScanBuild.embeddedAnonKey ?? env["AING_SCAN_ANON_KEY"]
        return ScanEnvironment(
            home: home,
            environment: env,
            transport: anon.map { URLSessionTransport(server: server, anonKey: $0) },
            runner: ProcessRunner(),
            platform: platform,
            uid: UInt32(getuid()),
            now: { Date() },
            macAppPresent: { ScanEnvironment.liveMacAppPresent() },
            executablePath: ScanEnvironment.liveExecutablePath(),
            hostName: ScanEnvironment.liveHostName(),
            output: { print($0) }
        )
    }

    /// 맥 앱(번들 kingcheck)이 이 사용자 계정에서 한 번이라도 기기 번호를 만들었는가. 앱 설정 도메인만 읽는다.
    static func liveMacAppPresent() -> Bool {
        #if os(macOS)
        return UserDefaults(suiteName: "kingcheck")?.string(forKey: "check.deviceID")?.isEmpty == false
        #else
        return false
        #endif
    }

    static func liveExecutablePath() -> String {
        #if os(Linux)
        if let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe") { return resolved }
        #endif
        let arg = CommandLine.arguments.first ?? "aing-scan"
        let url = arg.hasPrefix("/") ? URL(fileURLWithPath: arg)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(arg)
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func liveHostName() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return "remote" }
        let name = String(cString: buffer).split(separator: ".").first.map(String.init) ?? ""
        return name.isEmpty ? "remote" : name
    }
}

enum ScanExit: Int32 {
    case ok = 0
    case failure = 1
    case refused = 2
    case usage = 64
}

/// 명령 네 개. 출력은 사람이 읽는 한국어 한두 줄이고, 키·경로 같은 비밀은 싣지 않는다.
struct ScanCommands {
    let env: ScanEnvironment

    // MARK: link

    func link(code rawCode: String, name: String?, force: Bool, schedule: Bool) async -> ScanExit {
        let code = Self.normalizeCode(rawCode)
        guard code.count >= 6 else {
            env.output("연결 코드가 비었거나 짧습니다. 맥 아잉체크 → 설정 → [다른 기기 또는 서버 연결]에서 명령을 다시 복사해 주세요.")
            return .usage
        }
        if env.platform == .macOS, env.macAppPresent(), !force {
            env.output("이 맥에는 아잉체크 앱이 있어 앱이 이미 토큰을 집계합니다. 스캐너는 필요 없습니다.")
            return .refused
        }
        guard let transport = env.transport else {
            env.output("서버 연결 설정이 빠진 스캐너입니다(개발판). 배포판을 받아 주세요.")
            return .failure
        }
        let paths = env.paths
        do { try paths.ensureRoot() } catch {
            env.output("~/.aing-scan 폴더를 만들 수 없습니다.")
            return .failure
        }
        let previous = ScanStorage.load(ScanConfig.self, from: paths.config)
        let machineName = (name?.isEmpty == false ? name! : env.hostName)
        let server = ScanServer(transport: transport)
        let result: ScanServer.LinkResult
        do {
            result = try await server.link(
                code: code, name: String(machineName.prefix(40)), os: Self.osLabel(env.platform),
                previousDeviceId: previous?.deviceId
            )
        } catch ScanServerError.codeRejected(let reason) {
            env.output(Self.linkRejectionMessage(reason))
            return .refused
        } catch {
            env.output("서버에 연결하지 못했습니다. 인터넷 연결을 확인하고 다시 붙여넣어 주세요.")
            return .failure
        }
        let config = ScanConfig(
            deviceId: result.deviceId,
            name: String(machineName.prefix(40)),
            linkedAt: env.now(),
            codexHome: Self.nonEmpty(env.environment["CODEX_HOME"]),
            claudeConfigDir: Self.nonEmpty(env.environment["CLAUDE_CONFIG_DIR"]),
            linked: true
        )
        do {
            try ScanStorage.writePrivate(Data(result.deviceKey.utf8), to: paths.key)
            try ScanStorage.save(config, to: paths.config)
        } catch {
            env.output("연결 정보를 저장하지 못했습니다(~/.aing-scan 권한을 확인해 주세요).")
            return .failure
        }
        env.output("연결됐습니다: \(config.name)")
        if schedule {
            do {
                try env.scheduler.install(binary: env.executablePath)
                env.output("10분마다 자동으로 집계합니다.")
            } catch {
                env.output("자동 실행 예약을 걸지 못했습니다. `aing-scan run` 을 직접 돌리거나 예약을 확인해 주세요.")
            }
        }
        _ = await run(quiet: false)
        return .ok
    }

    // MARK: run

    /// 한 번 스캔하고 바뀐 것이 있으면 올린다. 예약 실행(quiet)은 연결 전·잠금 중이면 조용히 끝난다.
    @discardableResult
    func run(quiet: Bool) async -> ScanExit {
        let paths = env.paths
        guard let config = ScanStorage.load(ScanConfig.self, from: paths.config), config.linked,
              let key = ScanStorage.readKey(paths) else {
            if !quiet { env.output("아직 연결되지 않았습니다. 맥 아잉체크 → 설정 → [다른 기기 또는 서버 연결]의 명령을 붙여넣어 주세요.") }
            return quiet ? .ok : .refused
        }
        guard let transport = env.transport else {
            if !quiet { env.output("서버 연결 설정이 빠진 스캐너입니다(개발판).") }
            return .failure
        }
        guard let lock = RunLock(url: paths.lock) else {
            if !quiet { env.output("다른 집계가 돌고 있습니다. 잠시 뒤 다시 해 주세요.") }
            return .ok
        }
        defer { lock.release() }

        let now = env.now()
        var state = ScanStorage.load(ScanState.self, from: paths.state) ?? ScanState()
        let codexHome = Self.url(Self.nonEmpty(env.environment["CODEX_HOME"]) ?? config.codexHome)
        let claudeConfigDir = Self.url(Self.nonEmpty(env.environment["CLAUDE_CONFIG_DIR"]) ?? config.claudeConfigDir)

        // 맥 앱과 같은 증분 스캐너 · 같은 캐시 형식.
        let cache = TokenUsageCacheStore.load(from: paths.cacheBase)
        let result = TokenUsageIncrementalScanner.update(
            cache, homeDirectory: env.home, codexHome: codexHome, claudeConfigDir: claudeConfigDir, now: now
        )
        if !result.stats.changedParts.isEmpty {
            TokenUsageCacheStore.save(result.cache, parts: result.stats.changedParts, to: paths.cacheBase)
        }
        let files = result.stats.claudeFilesStatted + result.stats.codexFilesStatted + result.stats.antigravityFilesStatted
        let diagnostics: CodexUsageDiagnostics? = ScanPlanner.diagnosticsDue(state: state, now: now)
            ? CodexUsageDiagnosticsScanner.compute(
                homeDirectory: env.home, codexHome: codexHome, month: result.usage.month,
                appBuild: AingScanBuild.sharedCodeAppBuild
            )
            : nil

        let plan = ScanPlanner.plan(
            usage: result.usage, filesStatted: files, diagnostics: diagnostics,
            config: config, state: state, now: now
        )
        state.lastRunAt = now
        guard plan.shouldSend else {
            state.lastMonth = result.usage.month
            state.lastClaudeTotal = result.usage.claudeTotal
            state.lastCodexTotal = result.usage.codexTotal
            state.lastAntigravityTotal = result.usage.antigravityTotal
            state.lastFiles = files
            try? ScanStorage.save(state, to: paths.state)
            if !quiet { env.output(Self.summary(state, sent: false)) }
            return .ok
        }

        let server = ScanServer(transport: transport)
        do {
            let response = try await server.upload(key: key, payload: plan.payload)
            if response.ok {
                var next = plan.stateOnSuccess
                next.lastRunAt = now
                try? ScanStorage.save(next, to: paths.state)
                ScanStorage.appendLog(Self.logLine("ok", next), paths: paths, now: now)
                if !quiet { env.output(Self.summary(next, sent: true)) }
                return .ok
            }
            state.lastResult = response.reason ?? "rejected"
            try? ScanStorage.save(state, to: paths.state)
            ScanStorage.appendLog("upload \(state.lastResult ?? "rejected")", paths: paths, now: now)
            if !quiet { env.output("서버가 이번 집계를 받지 않았습니다(\(state.lastResult ?? "rejected")). 다음 예약 때 다시 보냅니다.") }
            return .failure
        } catch ScanServerError.revoked {
            // 맥 앱에서 [끊기]를 눌렀다 — 키를 비우고 예약을 끈다. 다시 쓰려면 새 연결 명령을 붙여넣는다.
            state.lastResult = "revoked"
            try? ScanStorage.save(state, to: paths.state)
            disconnectLocally(config: config)
            ScanStorage.appendLog("revoked", paths: paths, now: now)
            if !quiet { env.output("맥 아잉체크에서 이 기기의 연결을 끊었습니다. 다시 쓰려면 새 연결 명령을 붙여넣어 주세요.") }
            return .refused
        } catch {
            state.lastResult = "network"
            try? ScanStorage.save(state, to: paths.state)
            ScanStorage.appendLog("upload network", paths: paths, now: now)
            if !quiet { env.output("서버에 보내지 못했습니다. 다음 예약 때 다시 보냅니다.") }
            return .failure
        }
    }

    // MARK: status

    func status() -> ScanExit {
        let paths = env.paths
        guard let config = ScanStorage.load(ScanConfig.self, from: paths.config) else {
            env.output("연결되지 않음")
            return .ok
        }
        let state = ScanStorage.load(ScanState.self, from: paths.state) ?? ScanState()
        let keyPresent = ScanStorage.readKey(paths) != nil
        env.output("기기 이름: \(config.name)")
        env.output("연결: \(config.linked && keyPresent ? "됨" : "끊김")")
        env.output("자동 실행: \(env.scheduler.isInstalled() ? "켜짐(10분마다)" : "꺼짐")")
        env.output("마지막 집계: \(state.lastRunAt.map(Self.local) ?? "없음")")
        env.output("마지막 올림: \(state.lastUploadAt.map(Self.local) ?? "없음") · 결과 \(state.lastResult ?? "-")")
        env.output(Self.summary(state, sent: nil))
        env.output("스캐너 \(AingScanBuild.version)")
        return .ok
    }

    // MARK: unlink

    func unlink() async -> ScanExit {
        let paths = env.paths
        guard let config = ScanStorage.load(ScanConfig.self, from: paths.config) else {
            env.output("연결되지 않음")
            return .ok
        }
        if let key = ScanStorage.readKey(paths), let transport = env.transport {
            // 서버 쪽 끊기는 최선 노력 — 실패해도 이 기계에서는 끊는다(맥 앱 목록에서도 [끊기]로 지울 수 있다).
            try? await ScanServer(transport: transport).unlink(key: key)
        }
        disconnectLocally(config: config)
        env.output("연결을 끊었습니다. 이 기기에서는 더 이상 집계하지 않습니다.")
        return .ok
    }

    private func disconnectLocally(config: ScanConfig) {
        let paths = env.paths
        try? env.scheduler.remove(binary: env.executablePath)
        ScanStorage.clearKey(paths)
        var off = config
        off.linked = false
        try? ScanStorage.save(off, to: paths.config)
    }

    // MARK: 도움 함수

    /// 붙여넣으며 섞인 공백·하이픈을 빼고 대문자로.
    static func normalizeCode(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(32))
    }

    static func osLabel(_ platform: Scheduler.Platform) -> String {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        return (platform == .macOS ? "macos" : "linux") + "-" + arch
    }

    static func linkRejectionMessage(_ reason: String) -> String {
        switch reason {
        case "expired": return "연결 코드가 만료됐습니다(10분). 맥 아잉체크에서 명령을 다시 복사해 주세요."
        case "used": return "이미 쓴 연결 코드입니다. 맥 아잉체크에서 명령을 다시 복사해 주세요."
        case "limit": return "연결할 수 있는 기기 수(5대)를 넘었습니다. 맥 아잉체크 설정에서 안 쓰는 기기를 끊어 주세요."
        default: return "연결 코드를 확인하지 못했습니다. 맥 아잉체크에서 명령을 다시 복사해 주세요."
        }
    }

    static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func url(_ path: String?) -> URL? {
        path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }

    static func summary(_ state: ScanState, sent: Bool?) -> String {
        let month = state.lastMonth ?? "-"
        let claude = TokenNumberFormatter.compactKorean(state.lastClaudeTotal ?? 0)
        let codex = TokenNumberFormatter.compactKorean(state.lastCodexTotal ?? 0)
        var line = "\(month) 이 기기: Claude \(claude) · Codex \(codex)"
        if let ag = state.lastAntigravityTotal, ag > 0 { line += " · 안티그래비티 \(TokenNumberFormatter.compactKorean(ag))" }
        switch sent {
        case true?: line += " — 올렸습니다"
        case false?: line += " — 바뀐 것 없음"
        case nil: break
        }
        return line
    }

    static func logLine(_ result: String, _ state: ScanState) -> String {
        "upload \(result) files=\(state.lastFiles ?? 0) claude=\(state.lastClaudeTotal ?? 0) codex=\(state.lastCodexTotal ?? 0) ag=\(state.lastAntigravityTotal ?? 0)"
    }

    static func local(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 HH:mm"
        return f.string(from: date)
    }
}

/// 같은 기계에서 두 실행이 겹치지 않게(예약 실행 + 손으로 친 run). flock 은 프로세스가 죽으면 저절로 풀린다.
final class RunLock {
    private let fd: Int32

    init?(url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        self.fd = fd
    }

    func release() {
        _ = flock(fd, LOCK_UN)
        close(fd)
    }
}
