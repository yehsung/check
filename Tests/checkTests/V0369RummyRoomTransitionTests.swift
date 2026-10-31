import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.69 아잉 큐브 — 방 만들기 뒤 방 화면이 20~30초 안 뜬 운영 결함(10-30, 판 5f24f990…)의 회귀 시험.
//
// 실측: 14:31:08 방 생성 → 14:31:10~11 봇 셋 참가(방장에게 'rummy' 초인종) → 14:31:29 스크린숏에 아직 로비 →
// 30초 로비 폴링 무렵 방 화면. 서버 RPC 는 0.1~1.1초.
//
// 근본 원인: **방 카드가 로비 `me.room` 만 봤다.** 만들기·참가 응답과 초인종·5초 폴링은 `match` 를 갈아 phase 를 .room 으로
// 바꾸지만 로비 `me.room` 은 30초 로비 폴링만 간다 — phase 는 방인데 화면은 '방 만들기' 카드, 들어온 사람·[시작] 단추도
// 30초씩 늦었다(클라 게이트는 짝으로 있다: 스토어는 옳았고 뷰가 막았다).
// 고침: 방 카드의 원천을 `RummyStore.shownRoom(match:lobby:)` 한 곳으로 — forming 판 state 먼저, 없을 때만 로비 me.room.
//
// 시험은 폴링을 재운다(pollStepSeconds = 3,600) — 30초 로비 폴링 없이 만들기 응답·초인종만으로 화면이 서야 한다.
// 서버 응답은 `Fixtures/rummy/server/*.json` 을 쓰고, 픽스처에 없는 장면은 서버가 바꾸는 칸만 바꿔 만든다.

private let rtMe = "d0000000-0000-4000-8000-000000000001"
private let rtFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/rummy/server", isDirectory: true)

private func rtObject(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: rtFolder.appendingPathComponent("\(name).json"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func rtJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private let rtMatchID: UUID = {
    let state = (try! rtObject("state_forming"))["state"] as! [String: Any]
    return UUID(uuidString: state["id"] as! String)!
}()

private struct RTError: Error {}

@MainActor
private final class RTHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: rtMe)
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw RTError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum RTRetention {
    static var hosts: [RTHost] = []
}

private final class RTScript: @unchecked Sendable {
    private let lock = NSLock()
    private var standing: [String: GomokuStubProtocol.Reply] = [:]

    func stand(_ rpc: String, _ body: String, delay: TimeInterval = 0) {
        lock.lock()
        standing[rpc] = GomokuStubProtocol.Reply(status: 200, body: body, delay: delay)
        lock.unlock()
    }

    var handler: GomokuStubProtocol.Handler {
        { [self] rpc, _, _ in
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.standing[rpc]
        }
    }
}

@MainActor
private func rtMake(_ label: String, script: RTScript) -> (RummyStore, String) {
    let host = "v0369-rt-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: script.handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = RTHost(service: service)
    RTRetention.hosts.append(owner)
    let store = RummyStore()
    store.attach(host: owner)
    store.pollStepSeconds = 3_600
    store.draftDebounceSeconds = 0.05
    store.deadlineWakeEnabled = false
    return (store, host)
}

@MainActor
private func rtWait(_ resumes: Int = 600, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 앱 창이 그리는 장면(`RummyPanel.scene` 의 스토어 갈래와 같은 값) — 방 카드는 `scene.myRoom` 이 있으면 선다.
@MainActor
private func rtScene(_ store: RummyStore) -> RummyScene {
    RummyScene(
        phase: store.phase, availability: store.availability, lobby: store.lobby, match: store.match,
        editor: store.editor, isMyTurn: store.isMyTurn, otherDraft: store.otherDraft, notice: store.notice,
        isWorking: store.isWorking, ranking: store.ranking, myUserID: UUID(uuidString: rtMe), fixedNow: nil,
        isPreview: false)
}

private func rtJoined(_ room: RummyRoom?) -> Int { room?.seats?.filter { $0.state == .joined }.count ?? 0 }

/// 내 방(me.room)이 `rtMatchID` 인 로비 — 실제 로비 픽스처에서 me.room 의 id·방장·자리만 나로 바꿨다
/// (서버 `rummy_lobby` 의 me.room = 내가 joined 인 forming 방).
private func rtLobbyWithMyRoom() throws -> String {
    var lobby = try rtObject("lobby_with_room_invites_public")
    var me = try #require(lobby["me"] as? [String: Any])
    var room = try #require(me["room"] as? [String: Any])
    room["id"] = rtMatchID.uuidString.lowercased()
    room["host"] = ["id": rtMe, "display_name": "디시험01", "avatar_url": NSNull(), "character": NSNull()]
    room["seats"] = [["user_id": rtMe, "display_name": "디시험01", "avatar_url": NSNull(), "character": NSNull(),
                      "seat_no": 0, "state": "joined"]]
    me["room"] = room
    lobby["me"] = me
    return rtJSON(lobby)
}

@Suite("V0369 아잉 큐브 — 방 만들기 뒤 방 화면 전환")
@MainActor
struct V0369RummyRoomTransitionTests {
    /// 운영 순서 그대로: 로비 조회가 도는 중(창 열기)에 [방 만들기] → 만들기 응답 → 봇 참가 초인종. 30초 폴링 없이 방 화면이
    /// 만들기 응답 순간 서고, 초인종 한 번에 참가자 4명·[시작] 이 켜져야 한다. 늦게 온 로비(방 없음)도 화면을 되돌리지 않는다.
    @Test("만들기 응답 즉시 방 카드 · 초인종 한 번에 참가자 반영 · 30초 로비 폴링 불필요")
    func createShowsRoomImmediatelyAndDoorbellFillsSeats() async throws {
        let script = RTScript()
        // 창을 열 때 나간 로비 조회는 **방이 없을 때** 읽혔고 늦게(0.3초) 온다.
        script.stand("rummy_lobby", rtJSON(try rtObject("lobby_empty")), delay: 0.3)
        script.stand("rummy_create", rtJSON(try rtObject("create_ok")), delay: 0.05)
        let (store, host) = rtMake("create", script: script)

        let lobbyTask = Task { await store.refreshLobby() }
        await rtWait { GomokuStubProtocol.calls(host: host, rpc: "rummy_lobby").count == 1 }
        store.createRoom()
        await store.actionTask?.value

        // 만들기 응답 순간 — 로비는 아직 비행 중이고 me.room 은 없다. 옛 뷰(로비 me.room 만 봄)는 여기서 '방 만들기' 카드였다.
        #expect(store.phase == .room)
        #expect(store.lobby?.me?.room == nil)
        #expect(store.myRoom?.id == rtMatchID)
        #expect(rtScene(store).myRoom?.id == rtMatchID, "방 카드가 만들기 응답 즉시 서야 한다(30초 로비 폴링을 기다리지 않는다)")
        #expect(rtScene(store).amHost)
        #expect(rtJoined(rtScene(store).myRoom) == 1)

        // 봇 셋 참가 → 방장에게 초인종 → state(참가 4명).
        script.stand("rummy_state", rtJSON(try rtObject("state_forming")), delay: 0.05)
        store.handleSignal()
        await rtWait { rtJoined(rtScene(store).myRoom) == 4 }
        #expect(rtJoined(rtScene(store).myRoom) == 4, "초인종 한 번에 들어온 사람이 방 카드에 보여야 한다([시작] 은 참가 2명↑)")
        #expect(GomokuStubProtocol.calls(host: host, rpc: "rummy_state").count >= 1)

        // 늦게 온 로비(방 없음)가 와도 방 화면은 그대로다.
        await lobbyTask.value
        #expect(store.lobby?.me?.room == nil)
        #expect(store.phase == .room)
        #expect(rtScene(store).myRoom?.id == rtMatchID)
        // 로비는 처음 한 번만 — 폴링이 아니라 만들기 응답·초인종이 화면을 세웠다.
        #expect(GomokuStubProtocol.calls(host: host, rpc: "rummy_lobby").count == 1)
    }

    /// 만들기 응답에 state 가 안 실린 모양(match_id 만)도 이어진 state 조회 한 번으로 방 카드가 선다.
    @Test("만들기 응답에 state 가 없으면 state 조회 한 번으로 방 카드")
    func createWithoutStateFetchesStateAndShowsRoom() async throws {
        let script = RTScript()
        script.stand("rummy_lobby", rtJSON(try rtObject("lobby_empty")))
        var create = try rtObject("create_ok")
        create["state"] = NSNull()
        script.stand("rummy_create", rtJSON(create))
        script.stand("rummy_state", rtJSON(try rtObject("state_forming")))
        let (store, host) = rtMake("create-nostate", script: script)

        await store.refreshLobby()
        store.createRoom()
        await store.actionTask?.value

        #expect(store.phase == .room)
        #expect(rtScene(store).myRoom?.id == rtMatchID)
        #expect(rtJoined(rtScene(store).myRoom) == 4)
        #expect(GomokuStubProtocol.calls(host: host, rpc: "rummy_lobby").count == 1)
    }

    /// 참가(초대 수락·공개 방)도 같은 길이다 — 참가 응답 즉시 방 카드.
    @Test("참가 응답 즉시 방 카드")
    func joinShowsRoomImmediately() async throws {
        let script = RTScript()
        script.stand("rummy_lobby", rtJSON(try rtObject("lobby_empty")))
        script.stand("rummy_join", rtJSON(try rtObject("create_ok")))
        let (store, _) = rtMake("join", script: script)

        await store.refreshLobby()
        store.join(rtMatchID)
        await store.actionTask?.value

        #expect(store.phase == .room)
        #expect(store.lobby?.me?.room == nil)
        #expect(rtScene(store).myRoom?.id == rtMatchID)
    }

    /// 짝 결함: 방이 닫힌 것을 초인종으로 안 순간 방 카드가 내려가야 한다. 옛 뷰는 로비 me.room 이 남아 닫힌 방의
    /// [시작]·[나가기] 를 다음 30초 로비 폴링까지 그렸다.
    @Test("닫힌 방을 안 순간 방 카드가 내려간다")
    func closedRoomDropsCardImmediately() async throws {
        let script = RTScript()
        script.stand("rummy_create", rtJSON(try rtObject("create_ok")))
        script.stand("rummy_lobby", try rtLobbyWithMyRoom())
        let (store, _) = rtMake("closed", script: script)

        store.createRoom()
        await store.actionTask?.value
        await store.refreshLobby()
        #expect(store.lobby?.me?.room?.id == rtMatchID)
        #expect(rtScene(store).myRoom?.id == rtMatchID)

        // 방장이 아닌 쪽이 닫았다고 치고(서버 rummy_leave 방장 취소 → status cancelled) 초인종.
        var closed = try rtObject("state_forming")
        var state = try #require(closed["state"] as? [String: Any])
        state["status"] = "cancelled"
        closed["state"] = state
        script.stand("rummy_state", rtJSON(closed))
        store.handleSignal()
        await rtWait { store.match == nil }

        #expect(store.match == nil)
        #expect(store.phase == .lobby)
        #expect(store.lobby?.me?.room == nil)
        #expect(rtScene(store).myRoom == nil, "닫힌 방의 카드가 남으면 안 된다")
        #expect(store.notice == RummyNoticeText.roomClosed)
    }

    /// 나가기 뒤 늦게 온 로비(나가기 전에 읽힌 me.room)가 방 카드를 되살리지 않는다.
    @Test("나가기 뒤 옛 로비가 방 카드를 되살리지 않는다")
    func staleLobbyAfterLeaveDoesNotResurrectRoom() async throws {
        let script = RTScript()
        script.stand("rummy_create", rtJSON(try rtObject("create_ok")))
        script.stand("rummy_lobby", try rtLobbyWithMyRoom())
        script.stand("rummy_leave", rtJSON(try rtObject("leave_host_cancel")))
        let (store, _) = rtMake("leave", script: script)

        store.createRoom()
        await store.actionTask?.value
        await store.refreshLobby()
        #expect(rtScene(store).myRoom?.id == rtMatchID)

        // 서버가 아직 me.room 을 말하는 로비(나가기 직전에 읽힌 것과 같은 모양)를 계속 준다.
        store.leave()
        await store.actionTask?.value
        #expect(store.match == nil)
        #expect(store.lobby?.me?.room == nil)
        #expect(rtScene(store).myRoom == nil)
    }

    /// 뷰 쪽 짝: 렌더 주입(로비만)은 예전처럼 로비 me.room 을, forming 판이 있으면 판을 그린다 — 한 함수가 정한다.
    @Test("방 카드 원천은 한 곳 — forming 판 먼저, 없으면 로비 me.room")
    func sceneRoomSourceIsSingleFunction() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let lobby = try decoder.decode(RummyLobby.self, from: Data(try rtLobbyWithMyRoom().utf8))
        let forming = try decoder.decode(RummyActionResponse.self, from: Data(rtJSON(try rtObject("state_forming")).utf8)).state
        let formingState = try #require(forming)

        // 로비만 → 로비 me.room.
        #expect(RummyStore.shownRoom(match: nil, lobby: lobby)?.id == rtMatchID)
        #expect(rtJoined(RummyStore.shownRoom(match: nil, lobby: lobby)) == 1)
        // forming 판 → 판의 자리(참가 4 + 초대 1)·방장 얼굴.
        let fromMatch = try #require(RummyStore.shownRoom(match: formingState, lobby: lobby))
        #expect(rtJoined(fromMatch) == 4)
        #expect(fromMatch.seats?.contains { $0.state == .invited && $0.seatNo == nil } == true)
        #expect(fromMatch.host?.id.uuidString.lowercased() == rtMe)
        #expect(fromMatch.host?.displayName == "디시험01")
        #expect(fromMatch.stake == formingState.stake)
        #expect(fromMatch.maxSeats == 4)
        // 판이 시작됐으면(active) 방 카드는 판에서 서지 않는다.
        var active = formingState
        active.status = .active
        #expect(RummyStore.shownRoom(match: active, lobby: nil) == nil)
        // 뷰 장면이 같은 함수를 쓴다.
        let scene = RummyScene(
            phase: .room, availability: .available, lobby: nil, match: formingState, editor: nil, isMyTurn: false,
            otherDraft: nil, notice: nil, isWorking: false, ranking: nil, myUserID: UUID(uuidString: rtMe),
            fixedNow: nil, isPreview: false)
        #expect(scene.myRoom?.id == rtMatchID)
    }
}
