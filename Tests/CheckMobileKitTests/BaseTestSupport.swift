import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 기반 테스트 도우미(D-base). 탭 작업자의 테스트도 이 도우미를 쓴다 — 고치지 말고 더할 것이 있으면 자기 파일에 둔다.
//
// 규칙: 테스트마다 **고유 호스트**(`BaseStub.makeHost`)와 **고유 공용 저장소**(`BaseStub.makeStorage`)를 쓴다 — 스텁 기록·
// UserDefaults suite 가 병렬 테스트끼리 섞이지 않게. 끝나면 `BaseStub.tearDown(host:storage:)`.

/// 조작 가능한 시계(잠금으로 보호 — 스텁 스레드에서도 읽는다).
final class BaseTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = MobileClock.demoInstant) {
        current = start
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }

    var clock: MobileClock { MobileClock { [self] in self.now } }
}

/// 스레드 안전 카운터·상자.
final class BaseLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&value)
    }
}

enum BaseStub {
    static func makeHost(_ label: String = "base") -> String {
        "\(label)-\(UUID().uuidString.lowercased().prefix(12)).stub.invalid"
    }

    /// 응답 붙잡기(`BaseHold`)가 스텁 앞에 서는 세션. 붙잡기를 걸지 않은 호스트는 곧바로 스텁으로 간다.
    static func makeService(host: String) -> SupabaseWorkService {
        SupabaseWorkService(
            projectURL: URL(string: "https://\(host)")!,
            anonKey: "stub-anon-key",
            session: BaseHoldURLProtocol.makeSession()
        )
    }

    static func makeStorage() -> AingSharedStorage {
        let storage = AingSharedStorage.temporary(name: "test-\(UUID().uuidString.lowercased().prefix(12))")
        storage.ensureDirectory()
        return storage
    }

    static func tearDown(host: String, storage: AingSharedStorage) {
        BaseHoldURLProtocol.uninstall(host: host)
        MobileStubURLProtocol.unregister(host: host)
        try? FileManager.default.removeItem(at: storage.directory)
        if let suite = storage.defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    /// exp 가 주어진 시각인 가짜 JWT.
    static func jwt(exp: Date, subject: String = "user-1", salt: String = "") -> String {
        func b64(_ text: String) -> String {
            Data(text.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let payload = #"{"sub":"\#(subject)","exp":\#(Int(exp.timeIntervalSince1970)),"n":"\#(salt)"}"#
        return b64(#"{"alg":"none"}"#) + "." + b64(payload) + ".sig"
    }

    static func authResponse(access: String, refresh: String, userID: String) -> MobileStubResponse {
        .json(#"{"access_token":"\#(access)","refresh_token":"\#(refresh)","user":{"id":"\#(userID)"}}"#)
    }

    static let releaseOK = MobileStubResponse.json(#"{"status":"ok","platform":"ios","min_build":1,"latest_build":3,"notes":null}"#)
    static let registerOK = MobileStubResponse.json(#"{"status":"ok","device_id":"dev-1","push_prefs":{"message":true,"gomoku_invite":false,"feedback_reply":true}}"#)
    static let membershipOK = MobileStubResponse.json(#"[{"team_id":"team-1","role":"member","teams":{"name":"테스트팀","weekly_goal_hours":40}}]"#)
    static let jwtExpired = MobileStubResponse.json(#"{"code":"PGRST301","message":"JWT expired"}"#, status: 401)
    static let invalidGrant = MobileStubResponse.json(#"{"error":"invalid_grant","error_description":"Invalid Refresh Token: Already Used"}"#, status: 400)

    static let appInfo = MobileAppInfo(build: 1, version: "0.1.0", osVersion: "iOS 18.0", apnsEnvironment: "sandbox")

    /// 제품의 벽시계 상한(푸시의 실행 복원 대기 등)을 테스트가 재지 않을 때 넣는 값 — 포화에서도 먼저 지나지 않는다.
    static let patientSeconds: TimeInterval = 600

    static func bearer(_ request: MobileStubRequest) -> String {
        request.headers["Authorization"] ?? request.headers["authorization"] ?? ""
    }
}

// `baseWaitUntil` · `baseYield` · `BaseHold` · `baseBarrier` · `BaseGate` 는 BaseLoadSupport.swift(부하 내성 — 벽시계 대기 없음).

/// 테스트용 소켓: 명령을 기록하고, 테스트가 `emit` 으로 사건을 넣는다.
@MainActor
final class BaseFakeTransport: RealtimeTransport {
    var onEvent: ((RealtimeTransportEvent) -> Void)?
    private(set) var connects: [(accessToken: String, channel: String, isPrivate: Bool)] = []
    private(set) var disconnectCount = 0
    private(set) var pushedTokens: [String] = []
    private(set) var heartbeatCount = 0

    func connect(url: URL, apiKey: String, accessToken: String, channel: String, isPrivate: Bool) {
        connects.append((accessToken, channel, isPrivate))
    }

    func pushAccessToken(_ token: String) {
        pushedTokens.append(token)
    }

    func sendHeartbeat() {
        heartbeatCount += 1
    }

    func disconnect() {
        disconnectCount += 1
    }

    func emit(_ event: RealtimeTransportEvent) {
        onEvent?(event)
    }
}
