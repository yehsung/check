@testable import CheckCore
import CheckMobileShared
import Foundation
import ImageIO
import Testing
@testable import CheckMobileKit

// 폰 **아잉 큐브 배선**(1.0.17)의 못. 재는 것은 **결과 숫자**다(함수를 불렀는지가 아니라 요청이 몇 건 나갔는지 · 값이 어떻게 바뀌었는지).
// 뷰는 전부 `#if os(iOS)` 안이라 맥 스위트가 못 본다 — 그 화면을 죽이는 원인은 배선 몇 줄이다.

@MainActor
final class RummyWireHarness {
    nonisolated static let userID = "a0000000-0000-4000-8000-000000000001"
    nonisolated static let rival = "a0000000-0000-4000-8000-000000000002"
    nonisolated static let matchID = "a0000000-0000-4000-8000-0000000000f1"
    nonisolated static var matchUUID: UUID { UUID(uuidString: matchID)! }

    let server: GamesStubServer
    let storage: AingSharedStorage
    let clock: BaseTestClock
    let transport: BaseFakeTransport
    let model: MobileAppModel

    init(label: String, authResponse: (@Sendable (MobileStubRequest) -> MobileStubResponse)? = nil) {
        server = GamesStubServer(label: label)
        storage = BaseStub.makeStorage(label)
        clock = BaseTestClock()
        transport = BaseFakeTransport()
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: Self.userID)
        server.setDefault("/auth/v1/token") { request in
            authResponse?(request) ?? BaseStub.authResponse(access: fresh, refresh: "r-rummy", userID: RummyWireHarness.userID)
        }
        let environment = MobileEnvironment(
            service: BaseStub.makeService(host: server.host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            clock: clock.clock,
            installationID: "11111111-2222-4333-8444-66666666cccc",
            realtimeTransport: transport,
            runsTimers: false,
            reloadWidgetTimelines: {}
        )
        model = MobileAppModel(environment: environment)
        model.session.clientReleaseTimeoutSeconds = 0
        model.realtime.coalesceSeconds = 3_600
        // 하트비트·마감 깨우기·폴링은 시험이 직접 밟는다(시계가 멈춰 있다).
        model.rummy.heartbeatEnabled = false
        model.rummy.deadlineWakeEnabled = false
        model.rummy.pollStepSeconds = 3_600
    }

    var games: GamesStore { model.games }
    var rummy: RummyStore { model.rummy }
    var nowMs: Int { Int(clock.now.timeIntervalSince1970 * 1000) }

    func count(_ rpc: String) -> Int { server.requests(rpc).count }

    func barrier() async {
        await baseBarrier(model.context.service)
        await baseYield(turns: 8)
        await baseBarrier(model.context.service)
    }

    func serveLobby(activeMatchID: String? = nil, inviteRoomID: String? = nil) {
        server.setDefault("rummy_lobby", json: RummyWireJSON.lobby(nowMs: nowMs, activeMatchID: activeMatchID, inviteRoomID: inviteRoomID))
        server.setDefault("rummy_ranking", json: #"{"status":"ok","server_now_ms":\#(nowMs),"me":{"games":1,"wins":1,"rank":1},"rows":[]}"#)
        server.setDefault("rummy_leave", json: #"{"status":"ok"}"#)
        server.setDefault("rummy_heartbeat", json: #"{"status":"ok","server_now_ms":\#(nowMs)}"#)
        server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
    }

    func signIn() async {
        model.start()
        _ = await baseWaitUntil { model.session.phase == .signedOut }
        model.sceneDidBecomeActive()
        await model.session.signIn(email: "rummy@aing.invalid", password: "pw")
        await barrier()
    }

    func decodedState(status: String = "active", mySeatState: String = "playing", turnSeat: Int = 1, seq: Int = 3, draft: String = "null") -> RummyMatchState? {
        let text = RummyWireJSON.state(nowMs: nowMs, status: status, mySeatState: mySeatState, turnSeat: turnSeat, seq: seq, draft: draft)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(RummyMatchState.self, from: Data(text.utf8))
    }

    /// 판 state 를 스토어에 직접 꽂는다.
    @discardableResult
    func apply(status: String = "active", mySeatState: String = "playing", turnSeat: Int = 1) -> Bool {
        guard let state = decodedState(status: status, mySeatState: mySeatState, turnSeat: turnSeat) else {
            Issue.record("state 픽스처가 와이어와 어긋난다")
            return false
        }
        return rummy.applyState(state) == .applied
    }

    func tearDown() async {
        if model.session.isSignedIn { await model.session.signOut() }
        model.rummy.reset()
        BaseStub.tearDown(host: server.host, storage: storage)
    }
}

enum RummyWireJSON {
    static func lobby(nowMs: Int, activeMatchID: String? = nil, inviteRoomID: String? = nil, games: Int? = 3) -> String {
        let active = activeMatchID.map { "\"\($0)\"" } ?? "null"
        let invite = inviteRoomID.map { room(id: $0, nowMs: nowMs) } ?? ""
        return #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"turn_seconds":60,"room_ttl_seconds":600,"me":{"ruby_balance":100,"games":\#(games.map(String.init) ?? "null"),"wins":1,"room":null,"active_match_id":\#(active)},"invites":[\#(invite)],"public_rooms":[],"users":[]}"#
    }

    static func room(id: String, nowMs: Int) -> String {
        #"{"id":"\#(id)","host":{"id":"\#(RummyWireHarness.rival)","display_name":"큐브라이벌"},"stake":5,"is_public":false,"max_seats":4,"expires_at_ms":\#(nowMs + 600_000),"seats":[]}"#
    }

    static func state(nowMs: Int, id: String = RummyWireHarness.matchID, status: String, mySeatState: String, turnSeat: Int, seq: Int = 3, draft: String = "null", hostID: String = RummyWireHarness.userID) -> String {
        let me = RummyWireHarness.userID, rival = RummyWireHarness.rival
        let rack = status == "active" && mySeatState == "playing" ? #"["A10","A11","A12","B1"]"# : "null"
        return #"{"id":"\#(id)","status":"\#(status)","host_id":"\#(hostID)","stake":5,"is_public":false,"max_seats":4,"seat_count":2,"seq":\#(seq),"server_now_ms":\#(nowMs),"turn_seat_no":\#(turnSeat),"turn_started_ms":\#(nowMs - 1000),"turn_deadline_ms":\#(nowMs + 59_000),"pool_count":40,"table":[],"table_layout":[],"draft":\#(draft),"my_seat_no":0,"my_rack":\#(rack),"my_initial_done":false,"seats":[{"user_id":"\#(me)","display_name":"나","seat_no":0,"state":"\#(mySeatState)","rack_count":4},{"user_id":"\#(rival)","display_name":"큐브라이벌","seat_no":1,"state":"playing","rack_count":6}],"reactions":[]}"#
    }
}

@MainActor
@Suite(.serialized) struct GamesRummyWiringTests {
    private let waits = GamesWaitBudget()

    // MARK: - 초인종 · 조인

    @Test("초인종: 'rummy' 한 번에 로비 조회 **한 번** · 메시지 조회로 안 샌다 · 러너 칸을 떼면 0건(기준선)")
    func theSignalReachesTheStore() async {
        let harness = RummyWireHarness(label: "rummy-signal")
        harness.serveLobby()
        await harness.signIn()
        harness.transport.emit(.joined)
        await harness.barrier()
        let before = harness.count("rummy_lobby")
        harness.transport.emit(.broadcast(event: "rummy"))
        #expect(harness.model.realtime.effectLog.contains(.rummySignal), "링이 큐브 가지를 안 냈다")
        #expect(!harness.model.realtime.effectLog.suffix(1).contains(.drain), "큐브 초인종이 drain 으로 샜다")
        #expect(await waits.wait { harness.count("rummy_lobby") == before + 1 }, "초인종이 로비 조회가 안 됐다")
        await harness.barrier()
        #expect(harness.count("rummy_lobby") == before + 1, "초인종 한 번에 조회가 여러 건이다")
        harness.model.realtime.rummy = nil
        harness.transport.emit(.broadcast(event: "rummy"))
        await harness.barrier()
        #expect(harness.count("rummy_lobby") == before + 1, "칸을 뗐는데 조회가 나갔다 — 이 시험이 아무것도 안 잰다")
        await harness.tearDown()
    }

    @Test("조인 따라잡기: `.catchUp` 이 큐브 로비를 한 번 읽는다")
    func joinCatchesUp() async {
        let harness = RummyWireHarness(label: "rummy-join")
        harness.serveLobby()
        await harness.signIn()
        let before = harness.count("rummy_lobby")
        harness.transport.emit(.joined)
        harness.model.realtime.flushCoalescedSignals()
        #expect(harness.model.realtime.effectLog.contains(.catchUp), "조인이 따라잡기 effect 를 안 냈다")
        #expect(await waits.wait { harness.count("rummy_lobby") == before + 1 }, "조인 직후 로비를 안 읽었다")
        await harness.tearDown()
    }

    // MARK: - 앱 모델 배선 값

    @Test("주 스위치: 화면이 뜨면 순위가 나간다(요청 건수) · 스위치를 끈 기준선은 0건")
    func rankingSwitch() async {
        let harness = RummyWireHarness(label: "rummy-ranking")
        harness.serveLobby()
        await harness.signIn()
        #expect(harness.rummy.rankingEnabled)
        harness.games.rummyScreenDidAppear()
        #expect(await waits.wait { harness.count("rummy_ranking") == 1 }, "순위 탭이 영영 로딩 문구다 — rankingEnabled 배선이 빠졌다")
        harness.games.rummyScreenDidDisappear()

        let off = RummyWireHarness(label: "rummy-ranking-off")
        off.serveLobby()
        await off.signIn()
        off.rummy.rankingEnabled = false
        off.games.rummyScreenDidAppear()
        await off.barrier()
        #expect(off.count("rummy_ranking") == 0)
        off.games.rummyScreenDidDisappear()

        await harness.tearDown()
        await off.tearDown()
    }

    @Test("저장소: 받침대 · 손댄 판 장부가 앱 기본값에 남는다(다시 켠 폰이 자기 판을 놀던 기기로 읽지 않는다)")
    func ledgersPersist() async {
        let harness = RummyWireHarness(label: "rummy-ledger")
        harness.serveLobby()
        await harness.signIn()
        // 인스턴스가 아니라 **남는 값**으로 잰다(`storage.defaults` 는 부를 때마다 같은 suite 의 새 인스턴스다).
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        #expect(harness.storage.defaults.stringArray(forKey: RummyStore.engagedDefaultsKey)?
            .contains(RummyWireHarness.matchID) == true, "손댄 판 장부가 앱 저장소에 안 남는다")
        harness.apply()
        #expect(harness.storage.defaults.data(forKey: RummyStore.rackDefaultsKey(matchID: RummyWireHarness.matchUUID)) != nil,
                "받침대 자리가 앱 저장소에 안 남는다")
        await harness.tearDown()
    }

    // MARK: - 화면 수명

    @Test("수명: 뜨면 창이 서고 사라져도 요청은 쓰기 0건 · 진행 판은 남고 · 끝난 판은 접힌다")
    func screenLifecycle() async {
        let harness = RummyWireHarness(label: "rummy-life")
        harness.serveLobby()
        await harness.signIn()
        harness.games.rummyScreenDidAppear()
        #expect(harness.games.isRummyScreenVisible)
        #expect(harness.rummy.isWindowVisible, "폴링 문이 안 열렸다")
        await harness.barrier()
        harness.apply()
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        harness.games.rummyScreenDidDisappear()
        await harness.barrier()
        #expect(!harness.rummy.isWindowVisible)
        #expect(harness.count("rummy_leave") == 0, "화면을 떠났을 뿐인데 기권이 나갔다")
        #expect(harness.rummy.phase == .playing, "진행 판을 접었다")
        // 끝난 판은 접는다 — 다시 들어올 때 결과가 다시 서지 않게.
        harness.games.rummyScreenDidAppear()
        harness.apply(status: "finished", mySeatState: "done")
        #expect(harness.rummy.phase == .finished)
        harness.games.rummyScreenDidDisappear()
        #expect(harness.rummy.phase == .lobby, "끝난 판이 남았다")
        await harness.tearDown()
    }

    @Test("앱 전환: background 는 창만 내리고(기권 아님) active 는 되세워 따라잡는다 · 안 보이면 로비 한 번")
    func scenePhases() async {
        let harness = RummyWireHarness(label: "rummy-scene")
        harness.serveLobby()
        await harness.signIn()
        harness.games.rummyScreenDidAppear()
        await harness.barrier()
        harness.apply()
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        harness.games.appDidEnterBackground()
        #expect(!harness.rummy.isWindowVisible)
        #expect(harness.games.isRummyScreenVisible, "화면은 그대로 있다")
        #expect(harness.count("rummy_leave") == 0, "앱을 내렸다고 기권이 나갔다(서버 90초 규칙에 맡긴다)")
        harness.server.setDefault("rummy_state", json: #"{"status":"ok","state":\#(RummyWireJSON.state(nowMs: harness.nowMs, status: "active", mySeatState: "playing", turnSeat: 1))}"#)
        // 서버도 이 판을 내 판이라고 말한다(아니면 로비가 "판 없음" 사정을 확인하려 state 를 또 읽어 수가 흐려진다).
        harness.serveLobby(activeMatchID: RummyWireHarness.matchID)
        await harness.barrier()  // 판 시작을 처음 본 뒤의 잔액 조회(코어 머리말 ⑯)까지 끝낸 뒤 센다.
        let stateBefore = harness.count("rummy_state"), visibleLobbyBefore = harness.count("rummy_lobby")
        harness.clock.advance(10)
        harness.games.appDidBecomeActive()
        #expect(harness.rummy.isWindowVisible)
        #expect(await waits.wait { harness.count("rummy_state") > stateBefore }, "돌아와서 판을 안 읽었다")
        await harness.barrier()
        #expect(harness.count("rummy_state") == stateBefore + 1, "복귀 한 번에 판 조회가 \(harness.count("rummy_state") - stateBefore)건이다")
        #expect(harness.count("rummy_lobby") == visibleLobbyBefore + 1, "복귀 한 번에 로비 조회가 \(harness.count("rummy_lobby") - visibleLobbyBefore)건이다")
        harness.games.rummyScreenDidDisappear()
        let lobbyBefore = harness.count("rummy_lobby")
        harness.rummy.lastLobbyRequestAt = .distantPast
        harness.games.appDidEnterBackground()
        harness.games.appDidBecomeActive()
        #expect(await waits.wait { harness.count("rummy_lobby") > lobbyBefore }, "화면 밖에서 돌아왔는데 받은 초대를 못 읽었다")
        await harness.tearDown()
    }

    @Test("허브: 첫 화면이 로비를 읽어(30초 스로틀) 초대가 칩·탭 배지에 선다 · 오목 카드 재료에는 안 섞인다")
    func hubAndBadge() async {
        let harness = RummyWireHarness(label: "rummy-hub")
        harness.serveLobby(inviteRoomID: "a0000000-0000-4000-8000-0000000000e1")
        await harness.signIn()
        harness.rummy.lastMenuLobbyAt = .distantPast
        let before = harness.count("rummy_lobby")
        harness.games.hubDidAppear()
        #expect(await waits.wait { harness.count("rummy_lobby") == before + 1 }, "허브가 큐브 로비를 안 읽었다")
        harness.games.hubDidAppear()
        await harness.barrier()
        #expect(harness.count("rummy_lobby") == before + 1, "스로틀이 안 걸렸다")
        #expect(harness.games.badgeCount == 1, "받은 초대가 탭 배지에 없다")
        #expect(harness.games.gomokuIncomingCount == 0, "오목 카드 재료에 큐브 초대가 섞였다")
        #expect(GamesRummyCard.line(harness.games) == .incoming)
        #expect(GamesRummyCard.chip(harness.games) == "받은 초대 1")
        await harness.tearDown()
    }

    // MARK: - 이탈

    @Test("로그아웃: 손댄 판이면 `rummy_leave` 가 세션을 지우기 **전에** 나간다 · 놀던 기기는 0건")
    func signOutLeavesOnlyWhenEngaged() async {
        let harness = RummyWireHarness(label: "rummy-signout")
        harness.serveLobby()
        await harness.signIn()
        harness.apply()
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        await harness.model.me.signOut()
        await harness.barrier()
        let paths = harness.server.requests.map { $0.rpcName ?? $0.path }
        let leave = paths.firstIndex(of: "rummy_leave")
        let logout = paths.firstIndex { $0.contains("/auth/v1/logout") }
        #expect(leave != nil, "기권이 안 나갔다 — 판이 '플레이 중'으로 남는다")
        if let leave, let logout { #expect(leave < logout, "세션부터 지웠다") }
        #expect(!harness.model.session.isSignedIn)

        // 놀던 기기: 같은 판을 읽기만 했다.
        let idle = RummyWireHarness(label: "rummy-signout-idle")
        idle.serveLobby()
        await idle.signIn()
        idle.apply()
        await idle.model.me.signOut()
        await idle.barrier()
        #expect(idle.count("rummy_leave") == 0, "놀던 기기가 다른 기기의 판을 기권시켰다")
        await harness.tearDown()
        await idle.tearDown()
    }

    @Test("계정 삭제: 앞에 `rummy_leave` 를 안 보낸다(서버 삭제가 같은 트랜잭션에서 기권한다) · 삭제가 실패하면 판이 그대로다")
    func accountDeletionLeavesTheForfeitToTheServer() async {
        let fresh = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: RummyWireHarness.userID)
        let harness = RummyWireHarness(label: "rummy-delete") { request in
            if request.bodyText.contains("wrong") {
                return .json(#"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#, status: 400)
            }
            return BaseStub.authResponse(access: fresh, refresh: "r-rummy", userID: RummyWireHarness.userID)
        }
        harness.serveLobby()
        nonisolated(unsafe) var deleteFails = true
        harness.server.setDefault("delete_my_account") { _ in
            deleteFails ? MobileStubResponse(status: 500, body: Data()) : MobileStubResponse(status: 204, body: Data())
        }
        await harness.signIn()
        harness.apply()
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        let wrong = await harness.model.session.deleteAccount(password: "wrong")
        #expect(wrong == .failed(.wrongPassword))
        #expect(harness.count("rummy_leave") == 0, "비밀번호를 틀렸는데 판이 기권됐다")
        #expect(harness.rummy.phase == .playing)
        // 재인증은 통과했는데 서버 삭제가 실패했다 — 계정이 남으니 판도 남아야 한다.
        let failed = await harness.model.session.deleteAccount(password: "right")
        #expect(failed != .deleted)
        #expect(harness.count("delete_my_account") >= 1, "기준선: 삭제를 안 불렀으면 이 시험은 아무것도 안 잰다")
        #expect(harness.count("rummy_leave") == 0, "삭제가 실패했는데 판은 기권됐다 — 판돈을 돌려받을 길이 없다")
        #expect(harness.rummy.phase == .playing)
        deleteFails = false
        let right = await harness.model.session.deleteAccount(password: "right")
        #expect(right == .deleted)
        #expect(harness.count("rummy_leave") == 0, "서버가 원자적으로 하는 일을 먼저 저질렀다")
        await harness.tearDown()
    }

    @Test("화면 [나가기]: 판 중 손댄 판 = 기권 확인 · 놀던 기기 = 그냥 닫기 · 확인이 뜬 뒤 판이 끝났으면 기권 안 보낸다")
    func exitDecisions() async {
        let harness = RummyWireHarness(label: "rummy-exit")
        harness.serveLobby()
        await harness.signIn()
        harness.apply()
        #expect(GamesRummyExit.decision(harness.rummy) == .close, "놀던 기기인데 기권을 묻는다")
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        #expect(GamesRummyExit.decision(harness.rummy) == .confirmForfeit)
        #expect(GamesRummyExit.prompt(.confirmForfeit)?.detail == "나가면 기권돼 꼴찌가 되고 판돈을 잃어요.")
        #expect(GamesRummyExit.prompt(.close) == nil)
        // 확인이 떠 있는 동안 판이 끝났다.
        harness.apply(status: "finished", mySeatState: "done")
        #expect(await GamesRummyExit.confirm(asked: .confirmForfeit, rummy: harness.rummy) == false)
        #expect(harness.count("rummy_leave") == 0, "끝난 판에 기권을 보냈다")
        await harness.tearDown()
    }

    @Test("나간 뒤: 안내줄을 지우고 로비를 한 번 다시 읽는다(같은 화면이 로비로 남는다) · 시작된 판을 들고 남았으면 안 나간다")
    func leavingSettlesTheLobby() async throws {
        let forfeit = RummyWireHarness(label: "rummy-settle")
        forfeit.serveLobby()
        await forfeit.signIn()
        forfeit.apply()
        forfeit.rummy.markEngaged(RummyWireHarness.matchUUID)
        forfeit.rummy.setNotice("판이 바뀌었어요")
        await forfeit.barrier()
        var before = forfeit.count("rummy_lobby")
        #expect(await GamesRummyExit.confirm(asked: .confirmForfeit, rummy: forfeit.rummy))
        #expect(forfeit.count("rummy_leave") == 1)
        #expect(forfeit.rummy.match == nil && forfeit.rummy.notice == nil, "낡은 안내줄이 로비에 남았다")
        #expect(forfeit.count("rummy_lobby") == before + 1, "낡은 activeMatchId 로 '판 진행 중' 칩이 남는다")
        await forfeit.tearDown()

        let guest = RummyWireHarness(label: "rummy-settle-room")
        guest.serveLobby()
        let forming = RummyWireJSON.state(nowMs: guest.nowMs, status: "forming", mySeatState: "joined", turnSeat: 0)
        guest.server.setDefault("rummy_state", json: #"{"status":"ok","state":\#(forming)}"#)
        await guest.signIn()
        guest.apply(status: "forming", mySeatState: "joined")
        guest.rummy.markEngaged(RummyWireHarness.matchUUID)
        await guest.barrier()
        before = guest.count("rummy_lobby")
        guest.games.leaveRummyRoomFromScreen()
        await guest.games.rummyDepartureTask?.value
        #expect(guest.count("rummy_leave") == 1)
        #expect(guest.rummy.match == nil)
        #expect(guest.count("rummy_lobby") == before + 1, "닫힌 방이 공개 목록에 남는다")
        await guest.tearDown()

        let started = RummyWireHarness(label: "rummy-settle-started")
        started.serveLobby()
        let active = RummyWireJSON.state(nowMs: started.nowMs, status: "active", mySeatState: "playing", turnSeat: 1)
        started.server.setDefault("rummy_state", json: #"{"status":"ok","state":\#(active)}"#)
        await started.signIn()
        started.apply(status: "forming", mySeatState: "joined")
        started.rummy.markEngaged(RummyWireHarness.matchUUID)
        await started.barrier()
        started.games.leaveRummyRoomFromScreen()
        await started.games.rummyDepartureTask?.value
        #expect(started.count("rummy_leave") == 0, "묻지도 않고 시작된 판을 기권시켰다")
        #expect(started.rummy.match != nil)
        await started.tearDown()
    }

    @Test("놀던 기기: 받침대 안 정리는 서버로 안 나가고 engaged 도 안 선다 · 판에 놓으면 이어 받는다 · 손댄 기기는 디바운스가 그대로 걸린다(맥 동작 불변)")
    func idleRackMoveStaysLocal() async throws {
        let harness = RummyWireHarness(label: "rummy-idle-rack")
        harness.serveLobby()
        harness.server.setDefault("rummy_draft", json: #"{"status":"ok","draft_seq":3}"#)
        await harness.signIn()
        // 다른 기기가 만들던 작업 판 — 이 기기의 시작 판(빈 판)과 달라서, 보내면 덮인다.
        let draft = #"{"table":[["B1","B2","B3"]],"layout":[[100,100]],"draft_seq":2,"at_ms":\#(harness.nowMs)}"#
        let state = try #require(harness.decodedState(turnSeat: 0, draft: draft))
        #expect(harness.rummy.applyState(state) == .applied)
        #expect(harness.rummy.isMyTurn && !harness.rummy.isEngagedInCurrentMatch)
        harness.rummy.draftDebounceSeconds = 0.02
        let rack = try #require(harness.rummy.editor?.rack.map(\.id))

        harness.rummy.moveTiles([rack[0]], to: .rackSlot(RummyRackSlot(row: 1, halfCol: 4)))
        #expect(harness.rummy.editor?.rackLayout.slot(of: rack[0]) == RummyRackSlot(row: 1, halfCol: 4), "받침대가 안 옮겨졌다")
        #expect(harness.rummy.draftDebounceTask == nil, "놀던 기기의 받침대 정리가 전송을 걸었다")
        try await Task.sleep(for: .milliseconds(100))
        await harness.barrier()
        #expect(harness.count("rummy_draft") == 0, "다른 기기의 작업 판을 시작 판으로 덮었다")
        #expect(!harness.rummy.isEngagedInCurrentMatch, "받침대만 정리했는데 이 기기가 판을 쥐었다")

        // 판에 놓으면 이어 받는다. 그 디바운스 안의 받침대 정리가 걸린 전송을 지우면 안 된다.
        harness.rummy.moveTiles([rack[0]], to: .newMeld)
        harness.rummy.moveTiles([rack[1]], to: .rackSlot(RummyRackSlot(row: 1, halfCol: 8)))
        #expect(await waits.wait { harness.count("rummy_draft") == 1 }, "판에 놓았는데 안 나갔다")
        #expect(harness.rummy.isEngagedInCurrentMatch)

        // 손댄 기기의 받침대 정리는 예전 그대로 디바운스를 건다.
        await harness.barrier()
        harness.rummy.draftDebounceSeconds = 3_600
        harness.rummy.moveTiles([rack[1]], to: .rackSlot(RummyRackSlot(row: 1, halfCol: 12)))
        #expect(harness.rummy.draftDebounceTask != nil, "손댄 기기의 동작이 바뀌었다")
        await harness.tearDown()
    }

    // MARK: - 다른 기기 판

    @Test("다른 기기 판: 로비로 판을 읽어도 화면을 끌어 올리지 않고 쓰기가 0건이며 화면을 안 켜 둔다 · 손댄 판은 연다")
    func playingElsewhereStaysQuiet() async {
        let harness = RummyWireHarness(label: "rummy-elsewhere")
        harness.serveLobby()
        await harness.signIn()
        let before = harness.model.router.path(for: .games).count
        #expect(harness.apply(turnSeat: 0))
        #expect(harness.rummy.phase == .playing)
        #expect(harness.model.router.path(for: .games).count == before, "남의 기기 판이 화면을 끌어 올렸다")
        await harness.rummy.heartbeatTick(matchID: RummyWireHarness.matchUUID)
        #expect(harness.count("rummy_heartbeat") == 0, "놀던 기기가 하트비트를 보냈다(그 판이 이 기기 탓에 살아 있게 된다)")
        #expect(!harness.games.holdsRummyMatch)
        #expect(!harness.games.wantsIdleTimerDisabled, "놀던 기기가 화면을 켜 둔다")
        #expect(!harness.games.isAnyMatchScreenVisible, "놀던 기기가 확성기를 미룬다")

        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        await harness.rummy.heartbeatTick(matchID: RummyWireHarness.matchUUID)
        #expect(harness.count("rummy_heartbeat") == 1)
        #expect(harness.games.holdsRummyMatch)
        #expect(harness.games.wantsIdleTimerDisabled, "판 중에 화면이 꺼진다")
        #expect(harness.games.isAnyMatchScreenVisible, "판 중에 확성기가 뜬다")
        #expect(harness.model.isMegaphoneBannerDeferred)
        // 이제 손댄 판이니 코어의 문(`presentWindow`)이 화면을 연다.
        harness.rummy.presentWindow?()
        #expect(harness.model.router.path(for: .games).count == before + 1, "손댄 판의 화면이 안 열린다")
        await harness.tearDown()
    }

    @Test("확성기: 로비·방·결과 화면은 다른 대결 화면과 같이 미루고, 기권 뒤 구경은 안 미룬다")
    func megaphoneTable() async {
        let harness = RummyWireHarness(label: "rummy-megaphone")
        harness.serveLobby()
        await harness.signIn()
        #expect(!harness.games.isAnyMatchScreenVisible)
        harness.games.rummyScreenDidAppear()
        #expect(harness.games.isAnyMatchScreenVisible, "로비 화면인데 안 미룬다")
        harness.apply(mySeatState: "forfeit")
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        #expect(!harness.games.isAnyMatchScreenVisible, "기권 뒤 구경인데 미룬다")
        await harness.tearDown()
    }

    // MARK: - 네 방향 막기

    @Test("한 사람 한 판: 큐브 판·방이 있으면 세 입구가 막히고, 끝난 판·기권·없음은 안 막는다 · 서버 id 만 알아도 막는다")
    func rummyBlocksTheOtherThree() async {
        let harness = RummyWireHarness(label: "rummy-block")
        harness.serveLobby()
        await harness.signIn()
        let games = harness.games
        func allClear() { #expect(games.gomokuEntryBlock == nil && games.chessEntryBlock == nil && games.tetrisEntryBlock == nil) }
        allClear()
        harness.apply()
        #expect(games.gomokuEntryBlock == .rummy && games.chessEntryBlock == .rummy && games.tetrisEntryBlock == .rummy)
        #expect(games.hasActiveRummyMatch)
        harness.apply(status: "finished", mySeatState: "done")
        #expect(!games.hasLiveRummyMatch, "끝난 판이 입구를 막는다")
        allClear()
        harness.rummy.clearMatch()
        // 방: 서버 `chess__busy` 가 joined 도 본다.
        harness.apply(status: "forming", mySeatState: "joined")
        #expect(games.hasLiveRummyMatch && !games.hasActiveRummyMatch, "방인데 '판 진행' 이거나 안 막는다")
        #expect(games.gomokuEntryBlock == .rummy, "방에 앉은 채 오목을 수락한다")
        #expect(games.isInRummyRoom)
        harness.rummy.clearMatch()
        // 기권 뒤 구경.
        harness.apply(mySeatState: "forfeit")
        #expect(!games.hasLiveRummyMatch, "기권했는데 다른 게임을 못 한다")
        harness.rummy.clearMatch()
        allClear()
        // 서버가 말한 id 만 안다(판을 못 읽었다).
        harness.server.setDefault("rummy_state") { _ in .networkFailure() }
        harness.serveLobby(activeMatchID: RummyWireHarness.matchID)
        await harness.rummy.refreshLobby()
        #expect(harness.rummy.match == nil)
        #expect(games.gomokuEntryBlock == .rummy, "그 틈에 오목 입구가 열려 있다")
        #expect(GamesBusyGame.rummy.text == .rummy)
        await harness.tearDown()
    }

    @Test("한 사람 한 판: 다른 게임 판이 흐르면 큐브 입구가 막히고 카드가 그 이름을 말한다")
    func theOtherThreeBlockRummy() async {
        let harness = RummyWireHarness(label: "rummy-blocked")
        harness.serveLobby()
        await harness.signIn()
        let games = harness.games
        #expect(games.rummyEntryBlock == nil)
        harness.server.setDefault("tetris_state") { _ in .networkFailure() }
        harness.server.setDefault("tetris_lobby", json: TetrisWireJSON.lobby(nowMs: harness.nowMs, activeMatchID: "m-t"))
        await games.tetris.refreshLobby()
        #expect(games.rummyEntryBlock == .tetris, "테트리스 중인데 큐브 입구가 열려 있다")
        #expect(GamesRummyCard.line(games) == .blocked)
        #expect(GamesRummyCard.chip(games) == "1:1 테트리스 대결 중이에요")
        #expect(GamesRummyCard.detail(games) == "테트리스 대결이 끝나면 아잉 큐브를 신청할 수 있어요")
        await harness.tearDown()
    }

    @Test("카드 서열: 판 > 방 > 초대 > 전적 > 기본 — 서열이 뒤집히면 값이 바뀐다")
    func cardOrder() async {
        let harness = RummyWireHarness(label: "rummy-card")
        harness.server.setDefault("rummy_lobby", json: RummyWireJSON.lobby(nowMs: harness.nowMs, games: nil))
        await harness.signIn()
        let games = harness.games
        await harness.rummy.refreshLobby()
        #expect(GamesRummyCard.line(games) == .idle)
        #expect(GamesRummyCard.detail(games) == GamesRummyText.idleLine)
        harness.server.setDefault("rummy_lobby", json: RummyWireJSON.lobby(nowMs: harness.nowMs, games: 3))
        await harness.rummy.refreshLobby()
        #expect(GamesRummyCard.line(games) == .record)
        #expect(GamesRummyCard.detail(games) == "내 전적 판 수 3 · 1등 1")
        harness.server.setDefault("rummy_lobby", json: RummyWireJSON.lobby(nowMs: harness.nowMs, inviteRoomID: "a0000000-0000-4000-8000-0000000000e1"))
        await harness.rummy.refreshLobby()
        #expect(GamesRummyCard.line(games) == .incoming)
        harness.apply(status: "forming", mySeatState: "joined")
        #expect(GamesRummyCard.line(games) == .room)
        harness.rummy.clearMatch()
        harness.apply()
        #expect(GamesRummyCard.line(games) == .activeMatch)
        await harness.tearDown()
    }

    // MARK: - 끝 · 로그아웃

    @Test("로그아웃 사슬: 다음 계정에 방·판·받침대·초대가 남지 않는다 · 배선 값은 그대로다")
    func signOutResets() async {
        let harness = RummyWireHarness(label: "rummy-reset")
        harness.serveLobby(inviteRoomID: "a0000000-0000-4000-8000-0000000000e1")
        await harness.signIn()
        await harness.rummy.refreshLobby()
        harness.apply(mySeatState: "forfeit")
        await harness.model.session.signOut()
        await harness.barrier()
        #expect(harness.rummy.match == nil && harness.rummy.lobby == nil && harness.rummy.editor == nil)
        #expect(harness.games.badgeCount == 0)
        #expect(harness.rummy.rankingEnabled, "reset 이 배선 값을 건드렸다")
        await harness.tearDown()
    }

    /// 일일 줄이 큐브 하나뿐인 `achievements_status`(서버 `daily_mission_defs` 의 key·game 글자 그대로).
    private static func missionStatus(rummyDone: Bool) -> String {
        typealias Daily = MeDailyMissionStoreTests
        let row = Daily.dailyRow(.init(key: "daily_rummy", game: "rummy", title: "아잉 큐브 한 판 하기", sort: 70), done: rummyDone, claimed: false)
        let daily = #"{"kst_day":"2026-09-17","reset_at_ms":\#(Daily.resetMs),"missions":[\#(row)],"claimable_count":\#(rummyDone ? 1 : 0),"claimable_ruby":\#(rummyDone ? 5 : 0)}"#
        return Daily.status(dailyJSON: daily)
    }

    @Test("판 끝: 코어가 끝을 처음 본 순간 미션을 묻는다(같은 판을 또 봐도 한 번) · 오늘 큐브 줄을 채웠으면 0건 — 게임 이름이 서버 값과 다르면 값이 바뀐다")
    func finishAsksMissions() async {
        let harness = RummyWireHarness(label: "rummy-mission")
        harness.serveLobby()
        harness.server.setDefault("achievements_status", json: Self.missionStatus(rummyDone: false))
        await harness.signIn()
        await harness.model.me.loadAchievements()
        let before = harness.count("achievements_status")
        #expect(before >= 1)
        harness.apply()
        await harness.barrier()
        #expect(harness.count("achievements_status") == before, "판 중에 미션을 물었다")
        harness.apply(status: "finished", mySeatState: "done")
        #expect(await waits.wait { harness.count("achievements_status") == before + 1 }, "판이 끝났는데 미션을 안 물었다 — [받기]가 안 뜬다")
        await harness.barrier()
        _ = harness.rummy.applyState(harness.decodedState(status: "finished", mySeatState: "done", seq: 4)!)
        await harness.barrier()
        #expect(harness.count("achievements_status") == before + 1, "같은 판의 끝을 또 세었다")

        // 오늘 이미 채운 줄 — 이름이 `rummy` 라야 그 줄을 찾아 0건이다(모르는 이름이면 묻는다).
        let done = RummyWireHarness(label: "rummy-mission-done")
        done.serveLobby()
        done.server.setDefault("achievements_status", json: Self.missionStatus(rummyDone: true))
        await done.signIn()
        await done.model.me.loadAchievements()
        let doneBefore = done.count("achievements_status")
        done.apply(status: "finished", mySeatState: "done")
        await done.barrier()
        #expect(done.count("achievements_status") == doneBefore, "오늘 채운 줄인데 또 물었다 — 게임 이름이 서버 값이 아니다")
        await harness.tearDown()
        await done.tearDown()
    }

    @Test("루비: 로비 잔액이 호스트 거울(게임 탭·상점)까지 가고 로그아웃이면 비는다")
    func rubyMirror() async {
        let harness = RummyWireHarness(label: "rummy-ruby")
        harness.serveLobby()
        await harness.signIn()
        await harness.rummy.refreshLobby()
        #expect(harness.rummy.rubyBalance == 100)
        #expect(harness.model.context.gomokuHost.rubyBalance == 100, "큐브 로비 잔액이 공유 거울에 안 간다")
        await harness.model.session.signOut()
        await harness.barrier()
        #expect(harness.rummy.rubyBalance == nil)
        #expect(harness.model.context.gomokuHost.rubyBalance == nil, "앞 사람 잔액이 남았다")
        await harness.tearDown()
    }

    // MARK: - 하트비트 · 계정 교체

    @Test("하트비트: 타이머는 손댄 판에서만 돈다 — 놀던 기기 0건 · 화면을 떠나도 계속 · 로그아웃이면 멈춘다")
    func heartbeatFollowsTheLedger() async {
        let harness = RummyWireHarness(label: "rummy-heartbeat")
        harness.serveLobby()
        await harness.signIn()
        harness.rummy.heartbeatSeconds = 0.01
        harness.rummy.heartbeatEnabled = true
        harness.apply()
        try? await Task.sleep(for: .milliseconds(80))
        await harness.barrier()
        #expect(harness.rummy.heartbeatMatchID == nil)
        #expect(harness.count("rummy_heartbeat") == 0, "놀던 기기가 하트비트를 보냈다")
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        #expect(await waits.wait { harness.count("rummy_heartbeat") >= 1 }, "손댄 판인데 하트비트가 안 나간다 — 90초 뒤 끊김 기권이다")
        harness.games.rummyScreenDidAppear()
        harness.games.rummyScreenDidDisappear()
        let seen = harness.count("rummy_heartbeat")
        #expect(await waits.wait { harness.count("rummy_heartbeat") > seen }, "화면을 떠났더니 하트비트가 멎었다")
        await harness.model.session.signOut()
        await harness.barrier()
        let stopped = harness.count("rummy_heartbeat")
        try? await Task.sleep(for: .milliseconds(80))
        await harness.barrier()
        #expect(harness.count("rummy_heartbeat") == stopped, "로그아웃했는데 하트비트가 나간다")
        await harness.tearDown()
    }

    @Test("계정 교체: 앞 계정의 손댄 판 장부는 다음 계정에 안 넘어간다(같은 판의 상대여도 쓰기 0건) · 같은 사람이 돌아오면 이어진다")
    func ledgerIsBoundToAccount() async {
        let me = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: RummyWireHarness.userID)
        let rival = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(24 * 3600), subject: RummyWireHarness.rival)
        let harness = RummyWireHarness(label: "rummy-swap") { request in
            request.bodyText.contains("rival@")
                ? BaseStub.authResponse(access: rival, refresh: "r-rival", userID: RummyWireHarness.rival)
                : BaseStub.authResponse(access: me, refresh: "r-rummy", userID: RummyWireHarness.userID)
        }
        harness.serveLobby()
        await harness.signIn()
        harness.apply()
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        #expect(harness.games.holdsRummyMatch)
        // 토큰 만료 같은 강제 로그아웃 — 이탈 없이 세션만 내려간다.
        await harness.model.session.signOut()
        await harness.barrier()
        #expect(harness.rummy.match == nil)

        await harness.model.session.signIn(email: "rival@aing.invalid", password: "pw")
        await harness.barrier()
        harness.apply()
        #expect(!harness.rummy.isEngagedInCurrentMatch, "앞 계정의 장부가 다음 계정의 판을 쥐었다")
        #expect(!harness.games.holdsRummyMatch)
        #expect(GamesRummyExit.decision(harness.rummy) == .close, "다음 계정이 손대지 않은 판을 기권시킨다")
        await harness.rummy.heartbeatTick(matchID: RummyWireHarness.matchUUID)
        #expect(harness.count("rummy_heartbeat") == 0, "다음 계정 토큰으로 하트비트가 나갔다")
        await GamesRummyExit.leaveBeforeSessionEnds(harness.rummy)
        #expect(harness.count("rummy_leave") == 0, "다음 계정이 앞 계정의 판을 기권시켰다")
        await harness.model.session.signOut()
        await harness.barrier()

        // 같은 사람이 돌아왔다 — 쥐던 판의 하트비트·이탈이 이어져야 한다(안 이어지면 그 판이 90초 뒤 끊김 기권이다).
        await harness.model.session.signIn(email: "rummy@aing.invalid", password: "pw")
        await harness.barrier()
        harness.apply()
        #expect(harness.rummy.isEngagedInCurrentMatch, "같은 사람의 장부가 사라졌다")
        await harness.tearDown()
    }

    // MARK: - 그림 · 문구

    @Test("그림: 번들 사본 둘은 맥과 같은 blob 이고 받은 그림 문턱을 지난다")
    func artIsBundled() throws {
        for kind in RummyArtKind.allCases {
            let url = try #require(MobileArtNames.url(kind.bundleName), "\(kind) 이 앱 번들에 없다")
            let phone = try Data(contentsOf: url)
            let mac = try Data(contentsOf: IntegrationContractTests.root.appendingPathComponent("Sources/check/Resources/\(kind.bundleName).png"))
            #expect(phone == mac, "\(kind) 이 맥 사본과 다르다")
            let source = try #require(CGImageSourceCreateWithData(phone as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(GamesRummyArtRules.isAcceptable(kind: kind, pixelWidth: image.width, pixelHeight: image.height))
        }
    }

    @Test("그림: 받은 응답 판정 — 200 정상 · 못 쓰는 그림 · 304 · 404 · 500")
    func artOutcome() {
        typealias R = GamesRummyArtRules
        #expect(R.outcome(status: 200, byteCount: 1000, pixels: (2400, 478), kind: .rack) == .replace)
        #expect(R.outcome(status: 200, byteCount: 1000, pixels: (512, 512), kind: .rack) == .keep, "정사각 받침대를 받았다")
        #expect(R.outcome(status: 200, byteCount: 9 * 1024 * 1024, pixels: (2400, 478), kind: .rack) == .keep, "너무 큰 그림")
        #expect(R.outcome(status: 200, byteCount: 1000, pixels: nil, kind: .table) == .keep)
        #expect(R.outcome(status: 304, byteCount: 0, pixels: nil, kind: .table) == .keep)
        #expect(R.outcome(status: 404, byteCount: 0, pixels: nil, kind: .table) == .revert)
        #expect(R.outcome(status: 500, byteCount: 0, pixels: nil, kind: .table) == .keep)
        #expect(R.remoteURL(.rack, projectURL: URL(string: "https://x.invalid")!).absoluteString
                == "https://x.invalid/storage/v1/object/public/game-art/rummy/rack.png")
    }

    @Test("문구: 터치 낱말만 쓴다(⌥·마우스·창·클릭·호버·상표 이름 금지) · 시간 초과는 1장 · 등수 분배는 순수익")
    func textIsForTouch() throws {
        let source = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesRummyText.swift")
        let literals = source.components(separatedBy: "\"").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        #expect(literals.count > 80, "문구 표를 못 읽었다")
        for word in ["⌥", "마우스", "클릭", "호버", "드래그", "창을", "창이", "창 ", "루미"] {
            for line in literals { #expect(!line.contains(word), "'\(word)' 이 문구에 있다: \(line)") }
        }
        let time = try #require(GamesRummyText.rules.first { $0.title == "시간 60초" })
        #expect(time.detail.contains("되돌리고 1장"))
        #expect(!time.detail.contains("3장"), "낡은 벌칙: \(time.detail)")
        let split = try #require(GamesRummyText.rules.first { $0.title == "등수 분배" })
        #expect(split.detail.contains("2명 +N·−N") && split.detail.contains("3명 +N·0·−N") && split.detail.contains("4명 +2N·0·−N·−N"))
        for rule in GamesRummyText.rules {
            for text in rule.example { #expect(RummyFace(text: text) != nil, "\(rule.title) 예시 \(text)") }
        }
        #expect(GamesRummyText.net(5) == "+5" && GamesRummyText.net(-5) == "−5" && GamesRummyText.net(0) == "0")
    }

    @Test("의자: 나 = 아래 · 방이 없으면 나만 · 초대 중은 흐리게 · 글자는 폰 표")
    func seating() throws {
        let me = UUID(uuidString: RummyWireHarness.userID)!, rival = UUID(uuidString: RummyWireHarness.rival)!
        let solo = GamesRummySeating.chairs(room: nil, myUserID: me, myName: "나나", myAvatarURL: nil, myCharacter: "fox")
        #expect(solo.count == 4 && solo[0].isMe && solo[0].name == "나나" && solo[1...].allSatisfy { $0.kind == .empty })
        let third = UUID(uuidString: "a0000000-0000-4000-8000-000000000003")!
        let room = RummyRoom(id: third, host: RummyPeer(id: me, displayName: "나나", avatarUrl: nil, character: nil), stake: 3,
                             isPublic: false, expiresAtMs: nil, maxSeats: 4, seats: [
                                RummyRoomSeat(userId: rival, displayName: "둘째", avatarUrl: nil, character: nil, state: .joined, seatNo: 1),
                                RummyRoomSeat(userId: me, displayName: "나나", avatarUrl: nil, character: nil, state: .joined, seatNo: 0),
                                RummyRoomSeat(userId: third, displayName: "셋째", avatarUrl: nil, character: nil, state: .invited, seatNo: nil),
                             ])
        let chairs = GamesRummySeating.chairs(room: room, myUserID: me, myName: "나나", myAvatarURL: nil, myCharacter: nil)
        #expect(chairs.map(\.name) == ["나나", "둘째", "셋째", ""])
        #expect(chairs[0].tag == "나 · 방장" && chairs[1].tag == "참가함" && chairs[2].tag == "초대함")
        #expect(chairs[2].dimmed && chairs[2].seatNo == nil && chairs[1].userID == rival)
    }
}
