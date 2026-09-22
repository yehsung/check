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

    /// 호출 자리마다 붙는 **유계** 일련번호. 같은 자리를 여러 번 부를 때(하네스 `init` 이 그렇다)
    /// 이름이 겹치지 않게 한다. UUID 와 다른 점은 가짓수다 — 한 번 실행에서 그 자리를 부른 횟수만큼만
    /// 늘고, 다음 실행은 **같은 이름들을 다시 쓴다**. 그래서 파일이 실행마다 쌓이지 않는다.
    private static let storageSequence = BaseLockedBox([String: Int]())

    private static func nextStorageIndex(_ site: String) -> Int {
        var index = 0
        storageSequence.mutate { table in
            index = table[site, default: 0]
            table[site] = index + 1
        }
        return index
    }

    /// 테스트마다 고유한 임시 공용 저장소.
    ///
    /// **왜 UUID 를 걷어냈는가** — 이 이름은 `$TMPDIR/aing-shared-<이름>` 폴더와
    /// `com.yehsung.aingcheck.scratch.<이름>` UserDefaults 스위트가 **둘 다** 여기서 나온다. UUID 면
    /// 실행마다 새 이름이라 ~/Library/Preferences 에 plist 가 영구히 쌓인다 —
    /// 2026-09-22 에 그 폴더의 check-* 45만 개가 cfprefsd 를 죽여 앱이 자기 UserDefaults 를 못 읽었고,
    /// 기기 ID 를 잃어 유령 기기로 순위표 토큰이 2배가 됐다. `removePersistentDomain` 도 파일 직접 삭제도
    /// cfprefsd 를 못 이긴다(실측) — 그러니 고칠 것은 정리 시점이 아니라 **이름의 개수**다.
    /// 2026-09-22 갱신: 이름을 유계로 만드는 것만으로는 **모자랐다**. 유계여도 상한이 0 이 아니라
    /// ~/Library/Preferences 에 새 항목이 생기고, 그러면 "그 폴더 항목 수가 안 는다"는 회귀 게이트
    /// (`PreferencesLeakGateTests`)를 걸 수 없다. 그래서 `MobileTestScratch` 가 스위트를 $TMPDIR
    /// 절대 경로로 옮겼다 — 이 함수가 주는 이름은 이제 그 경로의 꼬리다.
    ///
    /// **왜 호출자를 안 고쳐도 되는가** — `#function`·`#line` 은 **호출 지점**에서 평가되는 컴파일러
    /// 기본 인자다. 20개 파일이 `BaseStub.makeStorage()` 라고만 써도 각자 자기 신원이 들어온다.
    ///
    /// **왜 일련번호까지 붙는가** — 호출 자리가 테스트 하나를 가리키지 않는 곳이 있다. 하네스 `init`
    /// (`GamesHarness`·`NowHarness`·`MeHarness` …)은 **모든 테스트가 같은 줄**을 지난다. 거기서 이름이
    /// 같으면 이 함수가 만들 때 지우는 폴더·도메인이 **병렬로 도는 옆 테스트의 것**이 되어, 재현 안 되는
    /// 빨강이 된다. 그리고 `BaseSessionHardeningTests.installationIDSurvivesBrokenKeychain` 은 한
    /// 테스트에서 저장소를 **둘** 만들고 그 둘이 서로 다름을 단언한다 — 이름이 같으면 그 단언이 조용히
    /// 무의미해진다. 일련번호가 두 경우를 한꺼번에 막으면서도 이름 수를 유계로 남긴다.
    static func makeStorage(_ label: String = "",
                            function: String = #function,
                            line: Int = #line) -> AingSharedStorage {
        let site = label.isEmpty ? "L\(line)" : "\(label)-L\(line)"
        let tag = "\(site)-\(nextStorageIndex(function + "#" + site))"
        return MobileTestScratch.storage(tag, function: function)
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
