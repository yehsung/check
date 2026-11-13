import Foundation

/// 스캐너가 쓰는 파일 자리. 맥·리눅스 모두 `~/.aing-scan/` 한 폴더(0700)다 — 찾기 쉽고, 끊을 때 무엇이 남는지 분명하다.
/// 시험은 `AING_SCAN_HOME` 으로 통째로 옮긴다.
struct ScanPaths: Sendable {
    let root: URL

    var config: URL { root.appendingPathComponent("config.json") }
    /// 기기 키(비밀). 0600. 출력·로그에 절대 싣지 않는다.
    var key: URL { root.appendingPathComponent("device.key") }
    var state: URL { root.appendingPathComponent("state.json") }
    /// 증분 스캔 캐시(맥 앱과 같은 TokenUsageCacheStore 형식 — state/entries 두 파일로 갈린다).
    var cacheBase: URL { root.appendingPathComponent("cache/token-usage-cache.json") }
    var lock: URL { root.appendingPathComponent("run.lock") }
    var log: URL { root.appendingPathComponent("scan.log") }
    var binDirectory: URL { root.appendingPathComponent("bin", isDirectory: true) }

    static func standard(home: URL, environment: [String: String]) -> ScanPaths {
        if let custom = environment["AING_SCAN_HOME"], !custom.isEmpty {
            return ScanPaths(root: URL(fileURLWithPath: custom, isDirectory: true))
        }
        return ScanPaths(root: home.appendingPathComponent(".aing-scan", isDirectory: true))
    }

    func ensureRoot() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
}

/// 연결 정보(비밀 아님). 키는 따로 device.key 에 둔다.
struct ScanConfig: Codable, Equatable, Sendable {
    /// 서버가 정해 준 이 기계의 번호. 토큰 표의 device_id 로 쓰인다.
    var deviceId: String
    var name: String
    var linkedAt: Date
    /// 연결할 때(대화형 셸) 본 CODEX_HOME · CLAUDE_CONFIG_DIR. 예약 실행(cron·launchd)은 셸 환경이 없어 여기서 읽는다.
    var codexHome: String?
    var claudeConfigDir: String?
    /// false = 끊음(키는 비워졌다). 파일을 지우지 않고 표시만 바꾼다.
    var linked: Bool = true
}

/// 실행 사이에 남기는 상태. 업로드 판단(바뀐 것만)과 `status` 표시에 쓴다.
struct ScanState: Codable, Equatable, Sendable {
    var lastRunAt: Date?
    var lastUploadAt: Date?
    /// 마지막 업로드 결과(ok · too_soon · revoked · network · server 등). 상태 표시용.
    var lastResult: String?
    var lastUploadedUsage: TokenUsageMonthlySnapshot?
    /// 일별 행 장부의 기준일(KST). 날이 바뀌면 장부를 비워 하루 한 번 전부 다시 보낸다(맥 앱과 같은 규칙).
    var dailyBaselineDay: String?
    /// 날짜 → 마지막으로 보낸 그 날 값의 정규 문자열.
    var uploadedDaily: [String: String] = [:]
    /// "<빌드>:<KST 날짜>" — 진단은 이 도장당 한 번(맥 앱 codexDiagnosticsStamp 와 같은 모양).
    var diagnosticsStamp: String?
    /// 상태 표시용 이번 달 숫자(정수만).
    var lastMonth: String?
    var lastClaudeTotal: Int?
    var lastCodexTotal: Int?
    var lastAntigravityTotal: Int?
    var lastFiles: Int?
}

/// TokenUsageMonthly 는 Codable 이지만 모듈 밖에서 비교만 하면 되므로 JSON 문자열로 들고 있는다.
struct TokenUsageMonthlySnapshot: Codable, Equatable, Sendable {
    var json: String
}

enum ScanStorage {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL, permissions: Int = 0o600) throws {
        let data = try encoder().encode(value)
        try writePrivate(data, to: url, permissions: permissions)
    }

    /// 0600 으로 원자적으로 쓴다(임시 파일 → 이름 바꾸기). 키·설정·상태 모두 이 길로만 쓴다.
    static func writePrivate(_ data: Data, to url: URL, permissions: Int = 0o600) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    static func readKey(_ paths: ScanPaths) -> String? {
        guard let data = try? Data(contentsOf: paths.key),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// 키를 비운다(파일은 남기고 내용만 0바이트) — 지우지 않고 무효로 만든다.
    static func clearKey(_ paths: ScanPaths) {
        try? writePrivate(Data(), to: paths.key)
    }

    /// 로그 한 줄(숫자·결과만). 256KB 를 넘으면 비우고 다시 쓴다.
    static func appendLog(_ line: String, paths: ScanPaths, now: Date) {
        let stamp = ISO8601DateFormatter().string(from: now)
        let data = Data("\(stamp) \(line)\n".utf8)
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: paths.log.path))?[.size] as? Int, size > 256 * 1024 {
            try? writePrivate(Data(), to: paths.log)
        }
        if !fm.fileExists(atPath: paths.log.path) {
            try? writePrivate(data, to: paths.log)
            return
        }
        if let handle = try? FileHandle(forWritingTo: paths.log) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }
}
