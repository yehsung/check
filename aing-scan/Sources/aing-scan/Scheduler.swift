import Foundation

/// 외부 명령 하나 실행(launchctl · crontab). 시험은 가짜를 넣어 실제 예약을 건드리지 않는다.
protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], stdin: Data?) -> (status: Int32, stdout: Data)
}

struct ProcessRunner: CommandRunner {
    func run(_ executable: String, _ arguments: [String], stdin: Data?) -> (status: Int32, stdout: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        let input = Pipe()
        if stdin != nil { process.standardInput = input } else { process.standardInput = FileHandle.nullDevice }
        do { try process.run() } catch { return (127, Data()) }
        if let stdin {
            input.fileHandleForWriting.write(stdin)
            try? input.fileHandleForWriting.close()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}

/// 10분마다 `aing-scan run` 을 돌리는 예약. 맥은 사용자 LaunchAgent, 리눅스는 사용자 crontab(관리자 권한 불필요,
/// 로그인해 있지 않아도 돈다). 둘 다 **지우지 않고** 끈다 — 맥은 plist 를 Disabled 로 다시 쓰고, 리눅스는 우리 줄만 뺀 crontab 을 다시 넣는다.
struct Scheduler {
    enum Platform: Equatable { case macOS, linux }

    static let label = "io.aingcheck.scan"
    static let cronMarker = "# aing-scan"
    static let intervalSeconds = 600

    let platform: Platform
    let home: URL
    let runner: CommandRunner
    let uid: UInt32

    var launchAgentURL: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    static func cronLine(binary: String) -> String {
        // 경로는 작은따옴표로 감싼다(공백 대비). 출력은 버린다 — 기록은 ~/.aing-scan/scan.log 에 스캐너가 직접 남긴다.
        "*/10 * * * * '\(binary)' run --quiet >/dev/null 2>&1 \(cronMarker)"
    }

    static func launchAgentPlist(binary: String, disabled: Bool) -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary, "run", "--quiet"],
            "StartInterval": intervalSeconds,
            "RunAtLoad": true,
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "Nice": 10,
            "Disabled": disabled,
        ]
        return (try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)) ?? Data()
    }

    /// 예약을 건다. 이미 있으면 새 경로로 바꿔 건다(같은 줄을 두 번 만들지 않는다).
    func install(binary: String) throws {
        switch platform {
        case .macOS:
            try ScanStorage.writePrivate(Self.launchAgentPlist(binary: binary, disabled: false), to: launchAgentURL, permissions: 0o644)
            _ = runner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Self.label)"], stdin: nil)
            let r = runner.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", launchAgentURL.path], stdin: nil)
            if r.status != 0 { throw SchedulerError.commandFailed("launchctl bootstrap", r.status) }
        case .linux:
            let current = currentCrontab()
            var lines = current.filter { !$0.contains(Self.cronMarker) }
            lines.append(Self.cronLine(binary: binary))
            try writeCrontab(lines)
        }
    }

    /// 예약을 끈다(지우지 않는다).
    func remove(binary: String) throws {
        switch platform {
        case .macOS:
            _ = runner.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Self.label)"], stdin: nil)
            if FileManager.default.fileExists(atPath: launchAgentURL.path) {
                try ScanStorage.writePrivate(Self.launchAgentPlist(binary: binary, disabled: true), to: launchAgentURL, permissions: 0o644)
            }
        case .linux:
            let current = currentCrontab()
            let kept = current.filter { !$0.contains(Self.cronMarker) }
            if kept.count != current.count { try writeCrontab(kept) }
        }
    }

    func isInstalled() -> Bool {
        switch platform {
        case .macOS:
            guard let data = try? Data(contentsOf: launchAgentURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return false }
            return (plist["Disabled"] as? Bool) != true
        case .linux:
            return currentCrontab().contains { $0.contains(Self.cronMarker) }
        }
    }

    private func currentCrontab() -> [String] {
        let r = runner.run(Self.crontabPath, ["-l"], stdin: nil)
        // crontab 이 아직 없으면 1 을 돌려준다 — 빈 목록으로 본다.
        guard r.status == 0, let text = String(data: r.stdout, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { !$0.isEmpty }
    }

    private func writeCrontab(_ lines: [String]) throws {
        let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        let r = runner.run(Self.crontabPath, ["-"], stdin: Data(text.utf8))
        if r.status != 0 { throw SchedulerError.commandFailed("crontab", r.status) }
    }

    static var crontabPath: String {
        for path in ["/usr/bin/crontab", "/bin/crontab", "/usr/local/bin/crontab"] where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/crontab"
    }
}

enum SchedulerError: Error, Equatable {
    case commandFailed(String, Int32)
}
