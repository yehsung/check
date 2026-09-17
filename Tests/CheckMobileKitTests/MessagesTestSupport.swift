import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 메시지 탭 테스트 도우미(D4). 기반 도우미(`BaseTestSupport.swift`)는 고치지 않고 여기에 더한다.
//
// 스텁 서버는 서버 계약(SPEC-wave1 §1.1) 모양의 JSON 을 돌려준다: `message_history_with_reads` 행 · `message_unread_summary` ·
// `mark_messages_read` · `send_message` · `app_user_directory`. 테스트가 상태를 바꾸면 다음 요청부터 반영된다.

/// 조작 가능한 메시지 스텁 서버(잠금 — 스텁 스레드에서 읽는다).
final class MessagesStubServer: @unchecked Sendable {
    struct Row {
        var id: String
        var peer: String
        var name: String
        var body: String
        var epoch: Int
        var mine: Bool
        var readByPeer: Bool?
        var unread: Bool?

        var json: String {
            func text(_ value: String) -> String {
                let data = try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
                return String(decoding: data, as: UTF8.self)
            }
            func flag(_ value: Bool?) -> String { value.map { $0 ? "true" : "false" } ?? "null" }
            return """
            {"id":\(text(id)),"from_user":\(text(mine ? MessagesHarness.me : peer)),"to_user":\(text(mine ? peer : MessagesHarness.me)),\
            "body":\(text(body)),"created_at":null,"is_mine":\(mine),"peer_user_id":\(text(peer)),"peer_display_name":\(text(name)),\
            "peer_avatar_url":null,"created_epoch":\(epoch),"read_by_peer":\(flag(mine ? readByPeer : nil)),"unread":\(flag(mine ? nil : unread))}
            """
        }
    }

    private let lock = NSLock()
    private var rows: [Row] = []
    private var summaryText = #"{"status":"ok","total":0,"peers":[]}"#
    private var directoryText = "[]"
    private var sendResponse: MobileStubResponse = .json(#"{"status":"ok","body":"x","ring":"sent"}"#)
    private var markResponse: MobileStubResponse = .json(#"{"status":"ok","advanced":true,"unread":0}"#)
    private var withReadsMissing = false
    /// 이력 요청마다 하나씩 꺼내 쓰는 그때의 행 — 비면 지금 행. (늦게 오는 응답은 벽시계 지연이 아니라 `BaseHold` 로 만든다.)
    private var historyScript: [[Row]] = []
    /// RPC 이름별 덮어쓰기 응답기(nil 을 돌려주면 기본 응답). 계정 전환 · 겹친 늦은 응답 시나리오가 쓴다.
    private var overrides: [String: @Sendable (MobileStubRequest) -> MobileStubResponse?] = [:]

    /// `rpc` 요청에 먼저 물어볼 응답기. **잠금 밖에서** 부른다 — 응답기 안에서 이 서버의 다른 메서드를 불러도 된다.
    func override(_ rpc: String, _ responder: @escaping @Sendable (MobileStubRequest) -> MobileStubResponse?) {
        lock.lock(); overrides[rpc] = responder; lock.unlock()
    }

    func setRows(_ value: [Row]) { lock.lock(); rows = value; lock.unlock() }
    func appendRow(_ value: Row) { lock.lock(); rows.append(value); lock.unlock() }
    /// 빈 문자열이면 "함수 없음"(옛 서버).
    func setSummary(_ text: String) { lock.lock(); summaryText = text; lock.unlock() }
    func setDirectory(_ text: String) { lock.lock(); directoryText = text; lock.unlock() }
    func setSend(_ response: MobileStubResponse) { lock.lock(); sendResponse = response; lock.unlock() }
    func setMark(_ response: MobileStubResponse) { lock.lock(); markResponse = response; lock.unlock() }
    func setWithReadsMissing(_ value: Bool) { lock.lock(); withReadsMissing = value; lock.unlock() }
    func scriptHistory(_ steps: [[Row]]) { lock.lock(); historyScript = steps; lock.unlock() }
    func setRead(peer: String) {
        lock.lock()
        rows = rows.map { row in
            var copy = row
            if row.peer == peer, row.mine { copy.readByPeer = true }
            return copy
        }
        lock.unlock()
    }

    static func summary(_ peers: [(String, Int)]) -> String {
        let items = peers.map { #"{"peer_user_id":"\#($0.0)","count":\#($0.1),"last_epoch_ms":1789621400000}"# }
        return #"{"status":"ok","total":\#(peers.reduce(0) { $0 + $1.1 }),"peers":[\#(items.joined(separator: ","))]}"#
    }

    func respond(_ request: MobileStubRequest) -> MobileStubResponse {
        let overrideResponder: (@Sendable (MobileStubRequest) -> MobileStubResponse?)? = {
            lock.lock(); defer { lock.unlock() }
            return request.rpcName.flatMap { overrides[$0] }
        }()
        if let overrideResponder, let response = overrideResponder(request) { return response }
        lock.lock(); defer { lock.unlock() }
        switch request.rpcName {
        case "client_release": return BaseStub.releaseOK
        case "register_device": return BaseStub.registerOK
        case "unregister_device": return .json(#"{"status":"ok","removed":true}"#)
        case "message_history_with_reads", "message_history":
            if request.rpcName == "message_history_with_reads", withReadsMissing {
                return .missingFunction("message_history_with_reads")
            }
            var current = rows
            if !historyScript.isEmpty {
                current = historyScript.removeFirst()
            }
            let body = "[" + current.map { row -> String in
                if request.rpcName == "message_history" {
                    var plain = row
                    plain.readByPeer = nil
                    plain.unread = nil
                    return plain.json
                }
                return row.json
            }.joined(separator: ",") + "]"
            return .json(body)
        case "message_unread_summary":
            return summaryText.isEmpty ? .missingFunction("message_unread_summary") : .json(summaryText)
        case "mark_messages_read":
            return markResponse
        case "send_message":
            return sendResponse
        case "app_user_directory": return .json(directoryText)
        default: break
        }
        if request.path == "/rest/v1/memberships" { return BaseStub.membershipOK }
        if request.path == "/auth/v1/token" {
            // 계정 전환: 비밀번호 로그인은 두 번째 사용자로 답한다.
            return BaseStub.authResponse(
                access: BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(7200), subject: MessagesHarness.secondUser),
                refresh: "refresh-two",
                userID: MessagesHarness.secondUser
            )
        }
        if request.path == "/auth/v1/logout" { return .json("{}") }
        return .missingFunction(request.path)
    }
}

/// 앱 모델 전체(세션 · 라우터 · 실시간 러너 · 메시지 스토어)를 스텁 서버 위에 세운다.
@MainActor
struct MessagesHarness {
    nonisolated static let me = "user-me"
    /// 계정 전환 시나리오의 다음 계정.
    nonisolated static let secondUser = "user-two"
    nonisolated static let base = 1_789_621_000   // 2026-09-17 13:56:40 KST 무렵(데모 시계 14:05 보다 조금 앞)
    /// 첫 계정의 access token(키체인 복원). 계정 전환 시나리오의 스텁이 "앞 계정이 띄운 요청"을 이 값으로 알아본다.
    nonisolated static let firstAccessToken = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(7200), subject: me)

    let host: String
    let storage: AingSharedStorage
    let server: MessagesStubServer
    let clock: BaseTestClock
    let transport: BaseFakeTransport
    let model: MobileAppModel
    var store: MessagesStore { model.messages }
    var requests: [MobileStubRequest] { baseRequests(host: host) }

    func count(_ rpc: String) -> Int { requests.filter { $0.rpcName == rpc }.count }
    func bodies(_ rpc: String) -> [String] { requests.filter { $0.rpcName == rpc }.map(\.bodyText) }

    func tearDown() {
        BaseStub.tearDown(host: host, storage: storage)
    }

    /// 앞 계정(키체인 복원 계정)이 보낸 요청인가.
    nonisolated static func isFirstAccount(_ request: MobileStubRequest) -> Bool {
        BaseStub.bearer(request) == "Bearer \(firstAccessToken)"
    }

    /// 사건 장벽(같은 서비스·세션 한 바퀴) — 늦게 넘긴 응답의 이어짐이 메인 액터에서 돈 뒤.
    func barrier() async {
        await baseBarrier(model.context.service)
    }

    /// 로그인된 채로 시작해 scene active 까지(첫 활성화 새로고침이 끝날 때까지 기다린다).
    static func make(active: Bool = true, configure: (MessagesStubServer) -> Void = { _ in }) async -> MessagesHarness {
        let host = BaseStub.makeHost("messages")
        let server = MessagesStubServer()
        configure(server)
        MobileStubURLProtocol.register(host: host) { server.respond($0) }
        let storage = BaseStub.makeStorage()
        let vault = InMemoryTokenVault()
        vault.write(firstAccessToken, key: AingKeychain.accessTokenKey)
        vault.write("refresh-me", key: AingKeychain.refreshTokenKey)
        storage.defaults.set(me, forKey: AingSharedKeys.userID)
        let clock = BaseTestClock()
        let transport = BaseFakeTransport()
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: host),
            vault: vault,
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: clock.clock,
            installationID: "11111111-2222-4333-8444-555555555555",
            realtimeTransport: transport,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        let model = MobileAppModel(environment: environment)
        model.realtime.coalesceSeconds = 3600   // 창은 테스트가 flushCoalescedSignals 로 닫는다
        model.messages.postMarkRefreshSeconds = 3600
        model.session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음(포화에서 client_release 가 3초를 넘어도 같은 경로)
        model.start()
        _ = await baseWaitUntil { model.session.phase == .signedIn }
        let harness = MessagesHarness(host: host, storage: storage, server: server, clock: clock, transport: transport, model: model)
        if active {
            model.sceneDidBecomeActive()
            await harness.settle()
        }
        return harness
    }

    /// 떠 있는 새로고침·읽음 왕복이 끝날 때까지.
    /// 병합 뒤: 같은 앱 모델의 지금 탭도 활성화 때 `app_user_directory`·`work_*` GET 을 부른다 — 그 새로고침까지 끝나야 테스트의
    /// 요청 수 기준선(`count` 전후 차)이 메시지 스토어 몫만 잰다.
    /// 스토어는 다음 걸음을 앞 걸음이 끝나는 같은 메인 액터 차례에 깃발로 세운다 — 깃발이 모두 내려간 채 몇 차례 양보해도 그대로면 멎었다.
    func settle() async {
        for _ in 0..<3 {
            _ = await baseWaitUntil {
                store.pendingActivityTask == nil && !store.isMarkingRead && !store.isSending && !store.directoryLoading
                    && model.now.refreshTask == nil
            }
            await baseYield()
        }
    }

    /// 로그아웃 → 다른 사용자로 로그인(같은 앱 모델 · scene 은 active 그대로). 끝나면 새 계정의 활성화 새로고침까지 기다린다.
    func switchAccount(sourceLocation: SourceLocation = #_sourceLocation) async {
        let before = model.session.generation
        await model.session.signOut()
        await model.session.signIn(email: "two@example.invalid", password: "pw-two")
        #expect(model.session.isSignedIn, "두 번째 계정 로그인 실패: \(String(describing: model.session.notice))", sourceLocation: sourceLocation)
        #expect(model.session.session?.userID == Self.secondUser, sourceLocation: sourceLocation)
        #expect(model.session.generation > before, sourceLocation: sourceLocation)
        await settle()
    }

    /// 금지 경로 0건(데모·실 모드 공통 단언).
    func expectNoForbiddenCalls(sourceLocation: SourceLocation = #_sourceLocation) {
        let violations = MobileForbiddenCalls.violations(in: requests)
        #expect(violations.isEmpty, "금지 호출: \(violations)", sourceLocation: sourceLocation)
        #expect(!requests.contains { $0.path.contains("take_pokes") }, sourceLocation: sourceLocation)
    }
}

extension MessagesStubServer.Row {
    static func received(_ id: String, from peer: String, name: String = "상대", body: String? = nil, at offset: Int, unread: Bool? = true) -> Self {
        .init(id: id, peer: peer, name: name, body: body ?? "받은 말 \(id)", epoch: MessagesHarness.base + offset, mine: false, readByPeer: nil, unread: unread)
    }

    static func sent(_ id: String, to peer: String, name: String = "상대", body: String? = nil, at offset: Int, read: Bool? = false) -> Self {
        .init(id: id, peer: peer, name: name, body: body ?? "보낸 말 \(id)", epoch: MessagesHarness.base + offset, mine: true, readByPeer: read, unread: nil)
    }
}
