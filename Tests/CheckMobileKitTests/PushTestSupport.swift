import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 푸시(D9) 테스트 도우미. 기반 도우미(BaseTestSupport)를 고치지 않고 이 파일에 더한다.

/// 시스템 알림 어댑터 가짜 — 권한 상태를 테스트가 정하고, 시킨 일을 기록한다.
@MainActor
final class PushFakeSystem: PushNotificationSystem {
    var status: PushAuthorizationStatus = .notDetermined
    /// 권한 창에서 사용자가 고를 답.
    var grantsOnRequest = true
    /// 권한 읽기를 이 문이 열릴 때까지 붙잡는다(세대 경합 재현 — 벽시계 지연 대신 테스트가 연다). 부를 때의 문을 쓴다.
    var statusGate: BaseGate?

    private(set) var statusReads = 0
    private(set) var authorizationRequests = 0
    private(set) var remoteRegistrations = 0
    private(set) var badgeCounts: [Int] = []
    private(set) var settingsOpened = 0
    private(set) var primerPresentations = 0
    private(set) var primerDismissals = 0

    /// 시작할 때의 값을 늦게 돌려준다. 실제 시스템 콜백처럼 **작업 취소를 모른다**(취소돼도 문이 열리기 전엔 끝나지 않는다).
    func authorizationStatus() async -> PushAuthorizationStatus {
        statusReads += 1
        let result = status
        if let gate = statusGate {
            await gate.wait()
        }
        return result
    }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        if status == .notDetermined {
            status = grantsOnRequest ? .authorized : .denied
        }
        return status.allowsDelivery
    }

    func registerForRemoteNotifications() {
        remoteRegistrations += 1
    }

    private(set) var remoteUnregistrations = 0
    private(set) var deliveredRemovals = 0

    func unregisterForRemoteNotifications() {
        remoteUnregistrations += 1
    }

    func removeAllDeliveredNotifications() {
        deliveredRemovals += 1
    }

    func setBadgeCount(_ count: Int) {
        badgeCounts.append(count)
    }

    func openSystemSettings() {
        settingsOpened += 1
    }

    func presentPermissionPrimer(_ coordinator: PushCoordinator) {
        primerPresentations += 1
    }

    func dismissPermissionPrimer() {
        primerDismissals += 1
    }

    // 시스템 화면(암호 저장 창) — 테스트가 `setSystemOverlay` 로 띄우고 내린다. 어댑터처럼 **관찰을 켠 동안에만** 알린다.
    private(set) var systemOverlay = false
    private(set) var overlayObservationStarts = 0
    private(set) var overlayObservationStops = 0
    private var overlayHandler: (@MainActor (Bool) -> Void)?
    var isObservingOverlay: Bool { overlayHandler != nil }

    var isSystemOverlayPresented: Bool { systemOverlay }

    func startObservingSystemOverlay(_ onChange: @escaping @MainActor (Bool) -> Void) {
        overlayObservationStarts += 1
        overlayHandler = onChange
    }

    func stopObservingSystemOverlay() {
        overlayObservationStops += 1
        overlayHandler = nil
    }

    func setSystemOverlay(_ presented: Bool) {
        guard systemOverlay != presented else { return }
        systemOverlay = presented
        overlayHandler?(presented)
    }
}

/// 관찰 가능한 배지 값(탭 스토어 배지 대신).
@MainActor
@Observable
final class PushFakeBadges {
    var messages = 0
    var games = 0
}

/// 푸시 시나리오 한 벌: 스텁 서버(RPC 이름 → 응답) · 앱 모델 · 가짜 시스템.
@MainActor
final class PushHarness {
    nonisolated static let userID = "a1111111-2222-4333-8444-000000000001"
    nonisolated static let peerID = "b2222222-3333-4444-8555-000000000002"
    nonisolated static let messageID = "c3333333-4444-4555-8666-000000000003"
    nonisolated static let matchID = "e4444444-5555-4666-8777-000000000004"
    nonisolated static let reportID = "f5555555-6666-4777-8888-000000000005"
    nonisolated static let deviceToken = Data((0..<32).map { UInt8($0 * 7 % 256) })

    let host: String
    let storage: AingSharedStorage
    let clock: BaseTestClock
    let model: MobileAppModel
    let system = PushFakeSystem()
    /// RPC 이름 → 응답(없으면 404 PGRST202). 스텁 스레드에서 읽으므로 잠금 상자.
    let rpc = BaseLockedBox<[String: MobileStubResponse]>([:])
    /// 이 이름의 RPC 가 몇 번째 부름부터 이 응답을 쓸지(401 한 번 → 성공 재현).
    let firstCallOverride = BaseLockedBox<[String: MobileStubResponse]>([:])
    private let callCounts = BaseLockedBox<[String: Int]>([:])
    let access: String
    let refreshed: String

    init(label: String = "push", apnsEnvironment: String? = "sandbox") {
        host = BaseStub.makeHost(label)
        storage = BaseStub.makeStorage()
        clock = BaseTestClock()
        access = BaseStub.jwt(exp: clock.now.addingTimeInterval(3600), subject: Self.userID, salt: "a")
        refreshed = BaseStub.jwt(exp: clock.now.addingTimeInterval(7200), subject: Self.userID, salt: "b")
        rpc.mutate {
            $0["client_release"] = BaseStub.releaseOK
            $0["register_device"] = BaseStub.registerOK
            $0["unregister_device"] = .json(#"{"status":"ok","removed":true}"#)
        }
        let rpcBox = rpc
        let overrideBox = firstCallOverride
        let counts = callCounts
        let access = access
        let refreshed = refreshed
        MobileStubURLProtocol.register(host: host) { request in
            if let name = request.rpcName {
                var index = 0
                counts.mutate { index = $0[name, default: 0]; $0[name] = index + 1 }
                if index == 0, let first = overrideBox.get()[name] { return first }
                return rpcBox.get()[name] ?? .missingFunction(name)
            }
            switch request.path {
            case "/auth/v1/token":
                if request.queryValue("grant_type") == "refresh_token" {
                    return BaseStub.authResponse(access: refreshed, refresh: "r2", userID: PushHarness.userID)
                }
                return BaseStub.authResponse(access: access, refresh: "r1", userID: PushHarness.userID)
            case "/auth/v1/logout": return .json("{}")
            case "/rest/v1/memberships": return BaseStub.membershipOK
            default: return .missingFunction(request.path)
            }
        }
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: MobileAppInfo(build: 1, version: "0.1.0", osVersion: "iOS 18.0", apnsEnvironment: apnsEnvironment),
            clock: clock.clock,
            installationID: "11111111-2222-4333-8444-555555555555",
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        model = MobileAppModel(environment: environment)
        // 제품의 벽시계 상한은 테스트가 재는 대상이 아니면 끈다(포화에서 상한이 먼저 지나 다른 갈래로 새지 않게).
        model.push.sessionSettleTimeoutSeconds = BaseStub.patientSeconds
        model.push.gomokuBusyTimeoutSeconds = BaseStub.patientSeconds
        model.session.clientReleaseTimeoutSeconds = 0
        // 폼 로그인 뒤 암호 저장 창 유예: 벽시계 대신 곧바로 끝난다(창이 안 뜬 경우). 유예 중 사건을 재는 테스트는 문으로 바꾼다.
        model.push.credentialPromptGraceSleep = { _ in }
    }

    var push: PushCoordinator { model.push }

    /// 가짜 시스템을 붙이고(앱 델리게이트 didFinishLaunching 과 같은 자리) 실행 → 로그인 → active.
    func launchSignedIn(active: Bool = true) async {
        push.attach(system: system)
        model.start()
        _ = await baseWaitUntil { self.model.session.phase == .signedOut }
        await model.session.signIn(email: "push@aing-check.invalid", password: "pw")
        if active { model.sceneDidBecomeActive() }
        await settle()
    }

    /// 진행 중인 권한 확인 · 등록 · 배지 확인이 끝날 때까지.
    func settle() async {
        for _ in 0..<5 {
            await push.pendingStatusCheck?.value
            await push.pendingCredentialPromptGrace?.value
            await model.session.pendingDeviceRegistration?.value
            await push.pendingBadgeConfirmation?.value
            await Task.yield()
        }
    }

    /// 앱이 꺼져 있다가 **키체인에 세션이 있는 채** 새로 켜지는 실행(알림을 눌러 켜짐 · 옛 카테고리 액션으로 뒤에서 켜짐 등). 같은 스텁 호스트 · 저장소를 쓴다.
    /// 반환한 모델은 시작만 해 둔다(장면 active 없음) — 어댑터 `handle()` 가 부르는 것과 같다.
    func makeRestoredModel(start: Bool = true) -> MobileAppModel {
        let vault = InMemoryTokenVault()
        vault.write(access, key: AingKeychain.accessTokenKey)
        vault.write("r1", key: AingKeychain.refreshTokenKey)
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: host),
            vault: vault,
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: clock.clock,
            installationID: "11111111-2222-4333-8444-555555555555",
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        storage.defaults.set(Self.userID, forKey: AingSharedKeys.userID)
        let restored = MobileAppModel(environment: environment)
        restored.push.sessionSettleTimeoutSeconds = BaseStub.patientSeconds
        restored.push.gomokuBusyTimeoutSeconds = BaseStub.patientSeconds
        restored.session.clientReleaseTimeoutSeconds = 0
        restored.push.credentialPromptGraceSleep = { _ in }
        restored.push.attach(system: system)
        if start { restored.start() }
        return restored
    }

    /// message_unread_summary 응답(다른 상대에게서 온 안 읽은 메시지 `total` 건).
    static func unreadSummary(total: Int) -> MobileStubResponse {
        let peers = total > 0
            ? #"[{"peer_user_id":"b9999999-3333-4444-8555-000000000009","count":\#(total),"last_epoch_ms":1789621110000}]"#
            : "[]"
        return .json(#"{"status":"ok","total":\#(total),"peers":\#(peers)}"#)
    }

    func requests() -> [MobileStubRequest] {
        baseRequests(host: host)
    }

    /// 사건 장벽(이 하네스 모델의 서비스 한 바퀴).
    func barrier() async {
        await baseBarrier(model.context.service)
    }

    func calls(_ rpcName: String) -> [MobileStubRequest] {
        requests().filter { $0.rpcName == rpcName }
    }

    func clearRequests() {
        MobileStubURLProtocol.clearRequests(host: host)
        callCounts.mutate { $0 = [:] }
    }

    func setRPC(_ name: String, _ response: MobileStubResponse) {
        rpc.mutate { $0[name] = response }
    }

    var forbiddenViolations: [String] {
        MobileForbiddenCalls.violations(in: requests())
    }

    func tearDown() {
        BaseStub.tearDown(host: host, storage: storage)
    }

    /// 서버 트리거가 만드는 모양 그대로의 본문(SPEC-wave1 §1.5 — `_apns` 칸까지). `message_id` 는 서버가 싣지만 앱은 읽지 않는다.
    static func messageUserInfo(peer: String = peerID, message: String? = messageID) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "하늘", "body": "점심 뭐 먹을래요?"], "sound": "default", "category": "MESSAGE", "thread-id": "message-\(peer)"],
            "type": "message",
            "peer_id": peer,
            "_apns": ["expiration": 1_789_700_000, "collapse_id": NSNull()],
        ]
        if let message { info["message_id"] = message }
        return info
    }

    static func gomokuUserInfo(match: String = matchID) -> [AnyHashable: Any] {
        [
            "aps": ["alert": ["title": "오목 신청", "body": "하늘님이 오목 대결을 신청했어요 · 루비 5"], "sound": "default", "category": "GOMOKU_INVITE", "thread-id": "gomoku"],
            "type": "gomoku_invite",
            "match_id": match,
            "_apns": ["expiration": 1_789_700_000, "collapse_id": match],
        ]
    }

    static func feedbackUserInfo(report: Any? = reportID) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "제보에 답장이 왔어요", "body": "고칠게요"], "sound": "default", "category": "FEEDBACK_REPLY"],
            "type": "feedback_reply",
        ]
        if let report { info["report_id"] = report }
        return info
    }

    /// gomoku_respond(accept) 성공 — 판 상태 묶음 포함(지어낸 이름).
    static func respondAcceptOK(match: String = matchID) -> MobileStubResponse {
        let matchRow = #"{"id":"\#(match)","turn":"black","black":"\#(userID)","board":"\#(String(repeating: ".", count: 225))","stake":5,"white":"\#(peerID)","result":null,"status":"active","winner":null,"opponent":"\#(userID)","challenger":"\#(peerID)","end_reason":null,"move_count":0,"deadline_ms":1789621530000,"finished_ms":null,"turn_started_ms":1789621500000,"invite_expires_ms":1789621560000}"#
        let opponent = #"{"user_id":"\#(peerID)","character":"aing","avatar_url":null,"display_name":"하늘"}"#
        let state = #"{"match":\#(matchRow),"moves":[],"my_color":"black","opponent":\#(opponent),"ruby_balance":95,"server_now_ms":1789621500000,"my_auto_streak":0,"opponent_auto_streak":0}"#
        return .json(#"{"status":"ok","accepted":true,"state":\#(state),"ruby_balance":95,"server_now_ms":1789621500000}"#)
    }
}

/// JSON 본문의 한 키 값(문자열·불·null).
func pushBodyValue(_ request: MobileStubRequest, _ key: String) -> Any? {
    guard let data = request.bodyText.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object[key]
}
