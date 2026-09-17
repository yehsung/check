import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 순위·나 탭 테스트 도우미(rankme). 기반 도우미(`BaseStub` 등)를 조합한다 — 기반 파일은 고치지 않는다.
//
// 앱 모델을 그대로 조립하되 **scene 을 active 로 만들지 않는다**: 로그인 복원이 끝나도 다른 탭 스토어는 깨어나지 않아
// 스텁 기록에는 세션(client_release · register_device · memberships)과 이 테스트가 부른 스토어의 요청만 남는다.

enum RankMeFixture {
    static let userID = "u-rankme-0001"
    static let teamID = "team-rankme-1"
    /// 2026-09-17 14:05 KST(목).
    static let now = MobileClock.demoInstant

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static let membership = MobileStubResponse.json(#"[{"team_id":"\#(teamID)","role":"member","teams":{"name":"테스트팀","weekly_goal_hours":40}}]"#)
}

@MainActor
final class RankMeHarness {
    let host: String
    let storage: AingSharedStorage
    let clock: BaseTestClock
    let model: MobileAppModel
    private let responses: BaseLockedBox<[String: [MobileStubResponse]]>

    var rankings: RankingsStore { model.rankings }
    var me: MeStore { model.me }

    /// - responder: 요청마다 먼저 묻는다(nil 이면 기본 응답 → 없으면 404 PGRST202).
    init(
        label: String,
        clockStart: Date = RankMeFixture.now,
        waitsForProfile: Bool = true,
        responder: @escaping @Sendable (MobileStubRequest) -> MobileStubResponse?
    ) async {
        host = BaseStub.makeHost(label)
        storage = BaseStub.makeStorage()
        clock = BaseTestClock(clockStart)
        responses = BaseLockedBox([:])
        let queued = responses
        MobileStubURLProtocol.register(host: host) { request in
            if let custom = responder(request) { return custom }
            if let name = request.rpcName {
                var next: MobileStubResponse?
                queued.mutate { table in
                    if var list = table[name], !list.isEmpty {
                        next = list.removeFirst()
                        table[name] = list
                    }
                }
                if let next { return next }
                switch name {
                case "client_release": return BaseStub.releaseOK
                case "register_device": return BaseStub.registerOK
                default: break
                }
            }
            if request.path == "/rest/v1/memberships" { return RankMeFixture.membership }
            return .missingFunction(request.path)
        }
        let vault = InMemoryTokenVault()
        vault.write(BaseStub.jwt(exp: clockStart.addingTimeInterval(86_400 * 30), subject: RankMeFixture.userID), key: AingKeychain.accessTokenKey)
        vault.write("refresh-rankme", key: AingKeychain.refreshTokenKey)
        storage.defaults.set(RankMeFixture.userID, forKey: AingSharedKeys.userID)
        storage.defaults.set("rankme@example.invalid", forKey: AingSharedKeys.email)
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
        model = MobileAppModel(environment: environment)
        model.start()
        _ = await baseWaitUntil {
            self.model.session.isSignedIn && (!waitsForProfile || self.model.session.profile?.teamID == RankMeFixture.teamID)
        }
    }

    /// 이름이 같은 RPC 에 차례로 줄 응답(응답기 뒤, 기본값 앞).
    func enqueue(_ rpc: String, _ response: MobileStubResponse) {
        responses.mutate { $0[rpc, default: []].append(response) }
    }

    var requests: [MobileStubRequest] { MobileStubURLProtocol.requests(host: host) }

    func requests(rpc: String) -> [MobileStubRequest] {
        requests.filter { $0.rpcName == rpc }
    }

    func requests(path: String, method: String) -> [MobileStubRequest] {
        requests.filter { $0.path == path && $0.method.uppercased() == method.uppercased() }
    }

    /// 금지 호출 0건 + 세션·이 테스트가 허용한 경로 밖의 쓰기 0건.
    func expectNoForbiddenCalls(sourceLocation: SourceLocation = #_sourceLocation) {
        let violations = MobileForbiddenCalls.violations(in: requests)
        #expect(violations.isEmpty, "금지 호출: \(violations)", sourceLocation: sourceLocation)
        let ultra = requests.filter { ["buy_ultra", "ultra_wallet_sync", "take_pokes", "work_tick"].contains($0.rpcName ?? "") }
        #expect(ultra.isEmpty, "울트라·지갑·찌르기 경로가 나갔다: \(ultra.map(\.path))", sourceLocation: sourceLocation)
    }

    func tearDown() {
        BaseStub.tearDown(host: host, storage: storage)
    }
}

extension MobileStubRequest {
    /// 본문 JSON 객체(없으면 빈 사전).
    var jsonBody: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(bodyText.utf8))) as? [String: Any] ?? [:]
    }
}
