@testable import CheckCore
import CheckMobileShared
import Foundation
import SwiftUI
import Testing
@testable import CheckMobileKit

// 사용자 답(운영판 '폰 아잉 큐브: 방에서 탭으로 나가도 자리를 남길까요?'): "맥처럼 방을 나가기".
// 재는 것은 요청 건수와 탭·경로·단계 값이다. `selectTab`·`open`·경로 바인딩은 탭 막대·푸시·딥링크·재선택이 실제로 부르는 문이고, 탭이 옮겨 가면 SwiftUI 가 부르는 `onDisappear` 는 시험이 대신 부른다.
@MainActor
@Suite(.serialized) struct V1016RummyTabExitTests {
    private let waits = GamesWaitBudget()

    private enum Seat { case host, guest }

    /// 게임 탭 큐브 화면에 앉은 방까지 간다. 서버 `rummy_state` 도 그 방을 말한다.
    private func seated(_ label: String, as seat: Seat, engaged: Bool = true) async -> RummyWireHarness {
        let harness = RummyWireHarness(label: label)
        harness.serveLobby()
        await harness.signIn()
        harness.games.rummyLeaveRetrySeconds = []
        harness.model.router.pathRestoreSeconds = 0
        serveState(harness, status: "forming", mySeatState: "joined", seat: seat)
        harness.model.router.selectedTab = .games
        harness.model.router.push(GamesDestination.rummy, on: .games)
        harness.games.rummyScreenDidAppear()
        await harness.barrier()
        let text = stateJSON(harness, status: "forming", mySeatState: "joined", seat: seat)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let state = try? decoder.decode(RummyMatchState.self, from: Data(text.utf8)) else {
            Issue.record("방 픽스처가 와이어와 어긋난다")
            return harness
        }
        if engaged { harness.rummy.markEngaged(RummyWireHarness.matchUUID) }
        harness.rummy.applyState(state)
        #expect(harness.rummy.phase == .room)
        return harness
    }

    private func stateJSON(_ harness: RummyWireHarness, status: String, mySeatState: String, seat: Seat) -> String {
        RummyWireJSON.state(nowMs: harness.nowMs, status: status, mySeatState: mySeatState, turnSeat: 1,
                            hostID: seat == .host ? RummyWireHarness.userID : RummyWireHarness.rival)
    }

    private func serveState(_ harness: RummyWireHarness, status: String, mySeatState: String, seat: Seat) {
        harness.server.setDefault("rummy_state", json: #"{"status":"ok","state":\#(stateJSON(harness, status: status, mySeatState: mySeatState, seat: seat))}"#)
    }

    /// 사람이 탭 막대를 눌렀다 — 옮겨 갔으면 SwiftUI 처럼 화면을 내린다.
    private func tap(_ tab: AingTab, _ harness: RummyWireHarness) {
        harness.model.router.tabBarSelection = tab
        if harness.model.router.selectedTab != .games { harness.games.rummyScreenDidDisappear() }
    }

    private func settled(_ harness: RummyWireHarness) async {
        await harness.games.rummyDepartureTask?.value
        await harness.barrier()
    }

    // MARK: - 손님

    @Test("손님 탭 이탈: 탭이 바로 옮겨 가고 rummy_leave 1건 · 돌아오면 로비 + 안내 한 줄 · 다음에 떠나면 줄이 지워진다")
    func guestLeaves() async {
        let harness = await seated("tab-guest", as: .guest)
        let router = harness.model.router
        tap(.messages, harness)
        #expect(router.selectedTab == .messages, "응답을 기다리느라 탭이 안 옮겨 갔다")
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        #expect(harness.rummy.phase == .lobby)
        #expect(harness.games.isInRummyRoom == false)
        #expect(GamesRummyCard.line(harness.games) != .room)
        #expect(harness.rummy.isEngagedInCurrentMatch == false)
        tap(.games, harness)
        harness.games.rummyScreenDidAppear()
        #expect(router.path(for: .games).count == 1, "돌아오면 큐브 화면(로비)이어야 한다")
        #expect(harness.games.rummyLeftByTabNotice == GamesRummyText.tabLeftNotice)
        #expect(harness.rummy.notice == nil, "코어 안내줄에 들어가면 방·판 화면까지 따라간다")
        tap(.me, harness)
        #expect(harness.games.rummyLeftByTabNotice == nil, "안내 줄이 다음 방문까지 남는다")
        #expect(harness.count("rummy_leave") == 1)
        await harness.tearDown()
    }

    @Test("이중 전송: 나가는 중에 탭을 또 옮기고 푸시가 와도 rummy_leave 는 1건")
    func guestSendsOnce() async {
        let harness = await seated("tab-once", as: .guest)
        let router = harness.model.router
        router.selectTab(.messages)
        router.selectTab(.me)
        router.open(.rankings(.league))
        #expect(router.selectedTab == .rankings)
        harness.games.rummyScreenDidDisappear()
        await settled(harness)
        router.selectTab(.now)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        await harness.tearDown()
    }

    // MARK: - 방장

    @Test("방장 탭 이탈: 0건 · 확인이 뜨고 탭은 그대로 · 막대를 다시 그리라는 값이 오른다")
    func hostAsks() async {
        let harness = await seated("tab-host", as: .host)
        let router = harness.model.router
        let serial = router.tabRefusalSerial
        tap(.now, harness)
        await harness.barrier()
        #expect(harness.count("rummy_leave") == 0)
        #expect(router.selectedTab == .games)
        #expect(router.tabBarSelection == .games)
        #expect(harness.games.rummyDeparturePrompt == .confirmCloseRoom)
        #expect(GamesRummyExit.prompt(.confirmCloseRoom)?.confirm == GamesRummyText.closeRoomConfirm)
        #expect(router.tabRefusalSerial == serial + 1, "막대만 눌린 탭으로 옮겨 간 채 남을 수 있다")
        #expect(harness.rummy.phase == .room)
        await harness.tearDown()
    }

    @Test("방장 수락: rummy_leave 1건 + 원래 가려던 탭으로 간다 · 두 번 눌러도 1건")
    func hostConfirms() async {
        let harness = await seated("tab-host-yes", as: .host)
        let router = harness.model.router
        tap(.me, harness)
        harness.games.confirmRummyDeparture()
        harness.games.confirmRummyDeparture()
        #expect(harness.games.rummyDeparturePrompt == nil)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        #expect(router.selectedTab == .me, "수락했는데 가려던 탭으로 안 갔다")
        #expect(harness.rummy.phase == .lobby)
        await harness.tearDown()
    }

    @Test("방장 취소: 0건 · 탭 유지 · 방에 남고 · 뒤늦은 수락은 아무 일도 안 한다")
    func hostCancels() async {
        let harness = await seated("tab-host-no", as: .host)
        let router = harness.model.router
        tap(.me, harness)
        harness.games.cancelRummyDeparture()
        harness.games.confirmRummyDeparture()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 0)
        #expect(router.selectedTab == .games)
        #expect(harness.rummy.phase == .room)
        #expect(harness.games.rummyDeparturePrompt == nil)
        await harness.tearDown()
    }

    @Test("방장 수락 실패: 탭을 안 옮기고 방이 남는다 · 안내 줄 · 다시 누르면 다시 보낸다")
    func hostConfirmFails() async {
        let harness = await seated("tab-host-fail", as: .host)
        harness.server.setDefault("rummy_leave", json: #"{"message":"down"}"#, status: 500)
        tap(.me, harness)
        harness.games.confirmRummyDeparture()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        #expect(harness.model.router.selectedTab == .games, "방이 안 닫혔는데 탭을 옮겼다 — 남들이 빈 방에서 기다린다")
        #expect(harness.rummy.phase == .room)
        #expect(harness.games.isRummyLeaveUnconfirmed)
        harness.server.setDefault("rummy_leave", json: #"{"status":"ok"}"#)
        tap(.me, harness)
        harness.games.confirmRummyDeparture()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 2)
        #expect(harness.model.router.selectedTab == .me)
        #expect(harness.rummy.phase == .lobby)
        await harness.tearDown()
    }

    // MARK: - 이탈이 아닌 것

    @Test("놀던 기기: 손님이든 방장이든 쓰기도 읽기도 0건 · 확인 없이 탭이 옮겨 간다")
    func idleDeviceSendsNothing() async {
        for seat in [Seat.guest, .host] {
            let harness = await seated("tab-idle-\(seat)", as: seat, engaged: false)
            let reads = harness.count("rummy_state")
            tap(.now, harness)
            await settled(harness)
            #expect(harness.model.router.selectedTab == .now)
            #expect(harness.games.rummyDeparturePrompt == nil)
            #expect(harness.count("rummy_leave") == 0)
            #expect(harness.count("rummy_state") == reads, "놀던 기기가 방을 읽었다")
            #expect(harness.rummy.phase == .room)
            await harness.tearDown()
        }
    }

    @Test("앱을 내림: 손님·방장 모두 0건 · 확인 없음 · 방 그대로(서버가 시작 때 끊긴 자리를 뺀다)")
    func backgroundSendsNothing() async {
        for seat in [Seat.guest, .host] {
            let harness = await seated("tab-bg-\(seat)", as: seat)
            harness.games.appDidEnterBackground()
            await settled(harness)
            #expect(harness.count("rummy_leave") == 0)
            #expect(harness.games.rummyDeparturePrompt == nil)
            #expect(harness.rummy.phase == .room)
            #expect(harness.games.isRummyScreenVisible)
            await harness.tearDown()
        }
    }

    @Test("판 중: 탭·푸시 모두 0건 · 확인 없음 · 판 그대로(90초 규칙)")
    func playingIsUntouched() async {
        let harness = await seated("tab-playing", as: .host)
        // 서버도 판이라고 말한다(돌아와 화면이 설 때 로비·판을 다시 읽는다).
        harness.serveLobby(activeMatchID: RummyWireHarness.matchID)
        serveState(harness, status: "active", mySeatState: "playing", seat: .host)
        harness.apply()
        #expect(harness.rummy.phase == .playing)
        #expect(GamesRummyExit.decision(harness.rummy) == .confirmForfeit)
        tap(.now, harness)
        await settled(harness)
        #expect(harness.model.router.selectedTab == .now)
        harness.games.rummyScreenDidAppear()
        harness.model.router.open(.messages)
        harness.games.rummyScreenDidDisappear()
        await settled(harness)
        #expect(harness.model.router.selectedTab == .messages)
        #expect(harness.games.rummyDeparturePrompt == nil)
        #expect(harness.count("rummy_leave") == 0, "판 중 탭 이동이 기권이 됐다")
        #expect(harness.rummy.phase == .playing)
        await harness.tearDown()
    }

    @Test("규칙 시트: 띄우고 닫아도 0건 · 확인 없음 · 방 그대로")
    func sheetIsNotDeparture() async {
        let harness = await seated("tab-sheet", as: .guest)
        harness.rummy.rulesShown = true
        await harness.barrier()
        harness.rummy.rulesShown = false
        await settled(harness)
        #expect(harness.count("rummy_leave") == 0)
        #expect(harness.rummy.phase == .room)
        await harness.tearDown()
    }

    @Test("방장 확인이 시트를 거둔다 — 시트 위에는 확인이 안 뜬다")
    func promptClosesSheet() async {
        let harness = await seated("tab-sheet-host", as: .host)
        harness.rummy.rulesShown = true
        harness.model.router.open(.messages)
        #expect(harness.games.rummyDeparturePrompt == .confirmCloseRoom)
        #expect(harness.rummy.rulesShown == false)
        await harness.tearDown()
    }

    @Test("로비·결과 화면: 그냥 간다 — 0건 · 확인 없음")
    func lobbyIsUntouched() async {
        let harness = RummyWireHarness(label: "tab-lobby")
        harness.serveLobby()
        await harness.signIn()
        harness.model.router.selectedTab = .games
        harness.games.rummyScreenDidAppear()
        await harness.barrier()
        #expect(harness.rummy.phase == .lobby)
        tap(.now, harness)
        await settled(harness)
        #expect(harness.model.router.selectedTab == .now)
        #expect(harness.count("rummy_leave") == 0)
        await harness.tearDown()
    }

    @Test("화면 밖: 나가기 실패 뒤 다른 탭끼리 옮겨 다녀도 그 탭 이동은 이탈이 아니다")
    func offScreenIsNotDeparture() async {
        let harness = await seated("tab-off", as: .host)
        harness.games.rummyScreenDidDisappear()
        harness.model.router.selectedTab = .now
        harness.model.router.selectTab(.me)
        await settled(harness)
        #expect(harness.model.router.selectedTab == .me)
        #expect(harness.games.rummyDeparturePrompt == nil)
        #expect(harness.count("rummy_leave") == 0)
        await harness.tearDown()
    }

    // MARK: - 시작 직후 경합

    @Test("경합(손님): 서버 state 가 active 면 안 나간다 — rummy_leave 0건 · 판을 들고 큐브 화면으로 돌아온다")
    func guestRace() async {
        let harness = await seated("tab-race", as: .guest)
        serveState(harness, status: "active", mySeatState: "playing", seat: .guest)
        tap(.messages, harness)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 0, "시작된 판에 나가기를 보내 기권됐다")
        #expect(harness.rummy.phase == .playing)
        #expect(harness.model.router.selectedTab == .games, "시작된 판 앞으로 안 돌아왔다")
        #expect(harness.model.router.path(for: .games).count == 1)
        await harness.tearDown()
    }

    @Test("경합(방장): 수락한 순간 state 가 active 면 안 나가고 탭도 안 옮긴다")
    func hostRace() async {
        let harness = await seated("tab-race-host", as: .host)
        tap(.messages, harness)
        serveState(harness, status: "active", mySeatState: "playing", seat: .host)
        harness.games.confirmRummyDeparture()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 0)
        #expect(harness.rummy.phase == .playing)
        #expect(harness.model.router.selectedTab == .games)
        await harness.tearDown()
    }

    @Test("확인이 떠 있는 동안 판이 시작됐다: 뒤늦은 수락은 0건 · 옮기지 않는다")
    func hostStaleConfirm() async {
        let harness = await seated("tab-stale", as: .host)
        tap(.messages, harness)
        harness.apply()
        harness.games.confirmRummyDeparture()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 0)
        #expect(harness.model.router.selectedTab == .games)
        await harness.tearDown()
    }

    @Test("확인이 떠 있는 동안 방이 사라졌다: 보낼 것 없이 가려던 탭으로 간다")
    func hostConfirmAfterRoomGone() async {
        let harness = await seated("tab-gone", as: .host)
        tap(.messages, harness)
        harness.rummy.clearMatch()
        #expect(GamesRummyExit.decision(harness.rummy) == .close)
        harness.games.confirmRummyDeparture()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 0)
        #expect(harness.model.router.selectedTab == .messages)
        await harness.tearDown()
    }

    // MARK: - 다른 길

    @Test("푸시·위젯 라우트: 손님은 나가고 그 화면이 열린다 — 1건")
    func guestRoutes() async {
        let harness = await seated("tab-route", as: .guest)
        harness.model.router.open(.message(peerID: "peer-1"))
        harness.games.rummyScreenDidDisappear()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        #expect(harness.model.router.selectedTab == .messages)
        #expect(harness.model.router.lastOpenedRoute == .message(peerID: "peer-1"))

        let widget = await seated("tab-widget", as: .guest)
        #expect(widget.model.handleOpenURL(URL(string: "aingcheck://now")!))
        widget.games.rummyScreenDidDisappear()
        await settled(widget)
        #expect(widget.count("rummy_leave") == 1)
        #expect(widget.model.router.selectedTab == .now)
        await harness.tearDown()
        await widget.tearDown()
    }

    @Test("푸시·위젯 라우트: 방장은 멈춰 묻는다 — 0건 · 수락하면 나간 뒤 그 라우트가 열린다 · 취소면 안 열린다")
    func hostRoutes() async {
        let harness = await seated("tab-route-host", as: .host)
        let router = harness.model.router
        router.open(.message(peerID: "peer-1"))
        await harness.barrier()
        #expect(harness.count("rummy_leave") == 0)
        #expect(router.selectedTab == .games)
        #expect(router.lastOpenedRoute != .message(peerID: "peer-1"))
        #expect(router.path(for: .games).count == 1, "확인 전에 경로를 비웠다")
        #expect(harness.games.rummyDeparturePrompt == .confirmCloseRoom)
        harness.games.confirmRummyDeparture()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        #expect(router.selectedTab == .messages)
        #expect(router.lastOpenedRoute == .message(peerID: "peer-1"))
        #expect(router.path(for: .games).isEmpty == false, "게임 탭 경로는 그 라우트가 건드리지 않는다")

        let cancelled = await seated("tab-route-no", as: .host)
        #expect(cancelled.model.handleOpenURL(URL(string: "aingcheck://now")!))
        cancelled.games.cancelRummyDeparture()
        await settled(cancelled)
        #expect(cancelled.model.router.selectedTab == .games)
        #expect(cancelled.count("rummy_leave") == 0)
        await harness.tearDown()
        await cancelled.tearDown()
    }

    @Test("게임 탭 재선택(뒤로): 같은 탭 고르기는 이탈이 아니다 · 경로가 줄면 손님은 나가고 방장은 화면을 되세워 묻는다")
    func popToRootByReselect() async {
        let guest = await seated("tab-pop", as: .guest)
        guest.model.router.tabBarSelection = .games
        await settled(guest)
        #expect(guest.count("rummy_leave") == 0, "같은 탭 고르기를 이탈로 읽었다")
        guest.model.router.pathBinding(for: .games).wrappedValue = NavigationPath()
        guest.games.rummyScreenDidDisappear()
        await settled(guest)
        #expect(guest.count("rummy_leave") == 1)
        #expect(guest.model.router.path(for: .games).isEmpty)

        let host = await seated("tab-pop-host", as: .host)
        let router = host.model.router
        router.pathBinding(for: .games).wrappedValue = NavigationPath()
        #expect(router.path(for: .games).isEmpty, "화면은 이미 내려갔다 — 경로가 사실과 갈린다")
        host.games.rummyScreenDidDisappear()
        #expect(await waits.wait { router.path(for: .games).count == 1 }, "방장 화면이 안 되돌아왔다")
        host.games.rummyScreenDidAppear()
        #expect(host.count("rummy_leave") == 0)
        #expect(host.games.rummyDeparturePrompt == .confirmCloseRoom)
        host.games.confirmRummyDeparture()
        await settled(host)
        #expect(host.count("rummy_leave") == 1)
        #expect(router.path(for: .games).isEmpty, "수락했는데 게임 첫 화면으로 안 갔다")
        await guest.tearDown()
        await host.tearDown()
    }

    @Test("경로가 늘어나는 쪽은 묻지 않는다 · 방을 떠나는 길이 아니다")
    func pushIsNotDeparture() async {
        let harness = await seated("tab-push", as: .host)
        let router = harness.model.router
        var path = router.path(for: .games)
        path.append(GamesDestination.rummy)
        router.pathBinding(for: .games).wrappedValue = path
        #expect(router.path(for: .games).count == 2)
        #expect(harness.games.rummyDeparturePrompt == nil)
        await harness.tearDown()
    }

    // MARK: - 실패

    @Test("실패(손님): 자리를 숨기지 않는다 — 카드 칩·보조 줄·안내 줄 · 손댄 판 장부 유지 · 다시 나갈 수 있다")
    func guestFailureKeepsSeat() async {
        let harness = await seated("tab-fail", as: .guest)
        harness.server.setDefault("rummy_leave", json: #"{"message":"down"}"#, status: 500)
        tap(.messages, harness)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        #expect(harness.model.router.selectedTab == .messages, "탭은 이미 옮겨 갔다")
        #expect(harness.rummy.phase == .room, "서버엔 자리가 남았는데 화면은 나왔다고 말한다")
        #expect(harness.rummy.isEngagedInCurrentMatch, "되돌린 방이 놀던 기기로 읽혀 다시 나갈 수 없다")
        #expect(GamesRummyCard.line(harness.games) == .room)
        #expect(GamesRummyCard.chip(harness.games) == GamesRummyText.roomChip)
        #expect(GamesRummyCard.detail(harness.games) == GamesRummyText.leaveUnconfirmedDetail)
        #expect(harness.games.isRummyLeaveUnconfirmed)
        await harness.rummy.refreshLobby()
        await harness.barrier()
        #expect(harness.rummy.phase == .room, "늦게 온 로비가 되돌린 방을 다시 접었다")
        // 돌아와서 다시 떠나면 다시 보낸다 — 이번엔 닿는다.
        harness.server.setDefault("rummy_leave", json: #"{"status":"ok"}"#)
        tap(.games, harness)
        harness.games.rummyScreenDidAppear()
        tap(.now, harness)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 2)
        #expect(harness.rummy.phase == .lobby)
        #expect(!harness.games.isRummyLeaveUnconfirmed)
        #expect(harness.games.rummyLeftByTabNotice == GamesRummyText.tabLeftNotice)
        await harness.tearDown()
    }

    @Test("되보내기: 한 번 실패해도 다른 탭에 있으면 혼자 다시 보내 닿으면 나온다")
    func guestRetryReaches() async {
        let harness = await seated("tab-retry", as: .guest)
        harness.games.rummyLeaveRetrySeconds = [0.01, 0.01, 0.01]
        harness.server.setDefault("rummy_leave", json: #"{"status":"ok"}"#)
        harness.server.enqueue("rummy_leave") { _ in .json(#"{"message":"down"}"#, status: 500) }
        tap(.messages, harness)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 2, "되보내지 않았거나 닿은 뒤에도 또 보냈다")
        #expect(harness.rummy.phase == .lobby)
        #expect(harness.games.rummyLeftByTabNotice == GamesRummyText.tabLeftNotice)
        #expect(GamesRummyCard.line(harness.games) != .room)
        await harness.tearDown()
    }

    @Test("되보내기: 상한이 있고 · 돌아와 방을 보고 있으면 보내지 않는다 · 로그아웃이면 끊는다")
    func guestRetryBounds() async {
        let bounded = await seated("tab-retry-max", as: .guest)
        bounded.games.rummyLeaveRetrySeconds = [0.01, 0.01]
        bounded.server.setDefault("rummy_leave", json: #"{"message":"down"}"#, status: 500)
        tap(.messages, bounded)
        await settled(bounded)
        #expect(bounded.count("rummy_leave") == 3)
        #expect(bounded.games.isRummyLeaveUnconfirmed)
        #expect(bounded.rummy.phase == .room)

        let back = await seated("tab-retry-back", as: .guest)
        back.games.rummyLeaveRetrySeconds = [0.05]
        back.server.setDefault("rummy_leave", json: #"{"message":"down"}"#, status: 500)
        tap(.messages, back)
        #expect(await waits.wait { back.games.isRummyLeaveUnconfirmed })
        tap(.games, back)
        back.games.rummyScreenDidAppear()
        await settled(back)
        #expect(back.count("rummy_leave") == 1, "방을 다시 보고 있는 사람을 내보냈다")
        #expect(back.rummy.phase == .room)

        let signedOut = await seated("tab-retry-out", as: .guest)
        signedOut.games.rummyLeaveRetrySeconds = [0.05]
        signedOut.server.setDefault("rummy_leave", json: #"{"message":"down"}"#, status: 500)
        tap(.messages, signedOut)
        #expect(await waits.wait { signedOut.games.isRummyLeaveUnconfirmed })
        let sent = signedOut.count("rummy_leave")
        await signedOut.model.session.signOut()
        try? await Task.sleep(for: .milliseconds(100))
        await signedOut.barrier()
        #expect(signedOut.count("rummy_leave") == sent, "로그아웃했는데 나가기가 또 나갔다")
        #expect(signedOut.games.rummyLeftByTabNotice == nil)
        #expect(!signedOut.games.isRummyLeaveUnconfirmed)
        #expect(signedOut.games.rummyDeparturePrompt == nil)

        await bounded.tearDown()
        await back.tearDown()
        await signedOut.tearDown()
    }

    @Test("로그아웃은 기존 길: 방장 확인이 떠 있어도 사라지고 탭 문을 지나지 않는다")
    func signOutTakesOwnRoad() async {
        let harness = await seated("tab-signout", as: .host)
        harness.model.router.selectTab(.me)
        #expect(harness.games.rummyDeparturePrompt != nil)
        await harness.model.session.signOut()
        await harness.barrier()
        #expect(harness.games.rummyDeparturePrompt == nil)
        #expect(harness.model.router.selectedTab == .now)
        await harness.tearDown()
    }

    // MARK: - 검토 지적: 시작된 판을 기권시키는 길

    private let downJSON = #"{"message":"down"}"#

    /// 응답이 늦는 실패 — 그 사이 다른 일이 끼어드는 경합을 값으로 재현한다.
    private func slowFailure(seconds: Double = 0.3) -> GamesStubServer.Responder {
        { _ in
            Thread.sleep(forTimeInterval: seconds)
            return .json(#"{"message":"down"}"#, status: 500)
        }
    }

    @Test("못 읽으면 안 보낸다: state 가 안 닿으면 rummy_leave 0건 · 방 그대로 · 자리 있음을 말한다(그 사이 시작됐으면 묻지 않은 기권이다)")
    func unreadRoomSendsNothing() async {
        let harness = await seated("tab-unread", as: .guest)
        harness.server.setDefault("rummy_state", json: downJSON, status: 500)
        tap(.messages, harness)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 0, "방인지 판인지 모른 채 나가기를 보냈다")
        #expect(harness.model.router.selectedTab == .messages)
        #expect(harness.rummy.phase == .room)
        #expect(harness.games.isRummyLeaveUnconfirmed)
        #expect(GamesRummyCard.detail(harness.games) == GamesRummyText.leaveUnconfirmedDetail)
        await harness.tearDown()
    }

    @Test("못 읽어 미룬 나가기: 망이 돌아오면 되보내기가 읽고 나서 나간다 — 1건")
    func unreadThenRetryLeaves() async {
        let harness = await seated("tab-unread-retry", as: .guest)
        harness.games.rummyLeaveRetrySeconds = [0.01]
        harness.server.enqueue("rummy_state") { _ in .json(#"{"message":"down"}"#, status: 500) }
        tap(.messages, harness)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        #expect(harness.rummy.phase == .lobby)
        #expect(!harness.games.isRummyLeaveUnconfirmed)
        await harness.tearDown()
    }

    @Test("되보내는 사이 판이 시작됐다: 읽어서 알면 나가지 않고 판을 든다 — 0건")
    func retryFindsStartedMatch() async {
        let harness = await seated("tab-retry-started", as: .guest)
        harness.games.rummyLeaveRetrySeconds = [0.01]
        harness.server.enqueue("rummy_state") { _ in .json(#"{"message":"down"}"#, status: 500) }
        serveState(harness, status: "active", mySeatState: "playing", seat: .guest)
        tap(.messages, harness)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 0, "되보내기가 시작된 판을 기권시켰다")
        #expect(harness.rummy.phase == .playing)
        #expect(!harness.games.isRummyLeaveUnconfirmed)
        await harness.tearDown()
    }

    @Test("문을 지나 코어에 닿는 사이 판이 됐다: departRoom 은 rummy_leave 를 안 보낸다")
    func heldMatchIsNotLeft() async {
        let harness = await seated("tab-held-active", as: .guest)
        harness.apply()
        #expect(await harness.rummy.departRoom(reason: .windowClosed) == .startedMatch)
        #expect(harness.count("rummy_leave") == 0)
        #expect(harness.rummy.phase == .playing)
        await harness.tearDown()
    }

    @Test("읽는 사이 폴링이 판을 들고 왔고 읽기는 실패했다: 폰·맥 길 모두 rummy_leave 0건")
    func matchArrivesWhileReading() async {
        let phone = await seated("tab-read-race", as: .guest)
        let before = phone.count("rummy_state")
        phone.server.enqueue("rummy_state", slowFailure())
        let departing = Task { await phone.rummy.departRoom(reason: .windowClosed) }
        #expect(await waits.wait { phone.count("rummy_state") == before + 1 })
        phone.apply()
        #expect(await departing.value == .startedMatch)
        #expect(phone.count("rummy_leave") == 0, "읽기 실패 뒤 쥔 판에 나가기를 보내 기권됐다")

        let mac = await seated("tab-read-race-mac", as: .guest)
        let macBefore = mac.count("rummy_state")
        mac.server.enqueue("rummy_state", slowFailure())
        let closing = Task { await mac.rummy.leaveRoomForExit(reason: .windowClosed) }
        #expect(await waits.wait { mac.count("rummy_state") == macBefore + 1 })
        mac.apply()
        #expect(await closing.value == false)
        #expect(mac.count("rummy_leave") == 0)
        await phone.tearDown()
        await mac.tearDown()
    }

    @Test("맥 길은 그대로: 창이 닫히면 못 읽어도 나간다(다시 시도할 사람이 없다)")
    func macPathStillLeavesWhenUnread() async {
        let harness = await seated("tab-mac-unread", as: .guest)
        harness.server.setDefault("rummy_state", json: downJSON, status: 500)
        #expect(await harness.rummy.leaveRoomForExit(reason: .windowClosed))
        #expect(harness.count("rummy_leave") == 1)
        await harness.tearDown()
    }

    // MARK: - 검토 지적: 화면 밖 자리가 살아 있는 길

    private func beatingHarness(_ label: String, as seat: Seat) async -> RummyWireHarness {
        let harness = await seated(label, as: seat)
        harness.rummy.heartbeatSeconds = 3_600
        harness.rummy.heartbeatEnabled = true
        harness.rummy.updateHeartbeat()
        return harness
    }

    @Test("방 하트비트는 방 화면이 설 때만: 내려가면 멈추고(서버가 시작 때 뺀다) · 돌아오면 곧바로 한 번 · 앱을 내린 것으로는 안 멈춘다")
    func roomHeartbeatFollowsScreen() async {
        let harness = await beatingHarness("tab-beat", as: .guest)
        let id = RummyWireHarness.matchUUID
        #expect(harness.rummy.heartbeatMatchID == id)
        harness.games.appDidEnterBackground()
        #expect(harness.rummy.heartbeatMatchID == id, "앱 내림은 이탈이 아니다 — 깨어난 뒤 자리를 잃는다")
        harness.games.rummyScreenDidDisappear()
        #expect(harness.rummy.heartbeatMatchID == nil, "화면 밖 자리가 살아 있어 모르는 사이 판돈이 걷힌다")
        let beats = harness.count("rummy_heartbeat")
        harness.games.rummyScreenDidAppear()
        #expect(harness.rummy.heartbeatMatchID == id)
        #expect(await waits.wait { harness.count("rummy_heartbeat") == beats + 1 }, "돌아온 뒤 10초 사이 시작되면 빠진다")
        await harness.tearDown()
    }

    @Test("판 하트비트는 화면과 무관하다: 화면 밖에서 판이 되면 돌고 · 판 중 탭을 옮겨도 돈다(90초 규칙)")
    func matchHeartbeatIgnoresScreen() async {
        let harness = await beatingHarness("tab-beat-match", as: .guest)
        let id = RummyWireHarness.matchUUID
        harness.games.rummyScreenDidDisappear()
        #expect(harness.rummy.heartbeatMatchID == nil)
        harness.apply()
        #expect(harness.rummy.phase == .playing)
        #expect(harness.rummy.heartbeatMatchID == id, "시작된 판의 하트비트가 안 돌아 끊김 기권된다")
        await harness.tearDown()
    }

    @Test("어느 문도 안 지나고 화면 밖에 앉았다(앱을 다시 켬): 하트비트 없음 — 기본값이 쉼이다")
    func relaunchedSeatHasNoHeartbeat() async {
        let harness = RummyWireHarness(label: "tab-beat-relaunch")
        harness.serveLobby()
        await harness.signIn()
        harness.rummy.heartbeatSeconds = 3_600
        harness.rummy.heartbeatEnabled = true
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        harness.apply(status: "forming", mySeatState: "joined")
        #expect(harness.rummy.phase == .room)
        #expect(harness.rummy.heartbeatMatchID == nil)
        await harness.tearDown()
    }

    @Test("나가기 실패로 되돌린 방도 화면 밖이면 하트비트가 안 돈다 · 되보내기 합은 끊김 기준 90초를 넘는다")
    func restoredRoomStaysSilent() async {
        let fresh = RummyWireHarness(label: "tab-beat-budget")
        #expect(fresh.games.rummyLeaveRetrySeconds.reduce(0, +) > 90, "되보내기가 끝난 뒤 서버가 빼 주기 전까지 빈틈이 남는다")
        await fresh.tearDown()

        let harness = await beatingHarness("tab-beat-fail", as: .guest)
        harness.server.setDefault("rummy_leave", json: downJSON, status: 500)
        tap(.messages, harness)
        await settled(harness)
        #expect(harness.rummy.phase == .room)
        #expect(harness.rummy.heartbeatMatchID == nil)
        await harness.tearDown()
    }

    // MARK: - 검토 지적: 낡은 말

    @Test("나오지 못했다는 말은 그 방에서만: 판이 시작되거나 방이 사라지면 저절로 없다 — 판 화면이 [나가기](기권)를 권하지 않는다")
    func unconfirmedLineDoesNotOutliveRoom() async {
        let started = await seated("tab-line-started", as: .guest)
        started.server.setDefault("rummy_leave", json: downJSON, status: 500)
        tap(.messages, started)
        await settled(started)
        #expect(started.games.isRummyLeaveUnconfirmed)
        tap(.games, started)
        started.games.rummyScreenDidAppear()
        started.apply()
        #expect(started.rummy.phase == .playing)
        #expect(!started.games.isRummyLeaveUnconfirmed)
        #expect(started.rummy.notice == nil, "판 화면 상태 줄이 차례 안내 대신 이 말을 띄운다")

        let closed = await seated("tab-line-closed", as: .guest)
        closed.server.setDefault("rummy_leave", json: downJSON, status: 500)
        tap(.messages, closed)
        await settled(closed)
        closed.rummy.clearMatch()
        #expect(!closed.games.isRummyLeaveUnconfirmed)
        #expect(GamesRummyCard.line(closed.games) != .room)
        await started.tearDown()
        await closed.tearDown()
    }

    // MARK: - 검토 지적: 화면의 [나가기]도 자리를 숨기지 않는다

    @Test("화면 [나가기](손님): 못 닿으면 방에 남아 말한다 · 닿으면 로비 · 탭 안내는 안 뜬다 · 두 번 눌러도 1건")
    func screenButtonDoesNotHideSeat() async {
        let harness = await seated("tab-button", as: .guest)
        harness.server.setDefault("rummy_leave", json: downJSON, status: 500)
        harness.games.leaveRummyRoomFromScreen()
        harness.games.leaveRummyRoomFromScreen()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 1)
        #expect(harness.rummy.phase == .room, "서버엔 자리가 남았는데 로비를 보였다")
        #expect(harness.games.isRummyLeaveUnconfirmed)
        harness.server.setDefault("rummy_leave", json: #"{"status":"ok"}"#)
        harness.games.leaveRummyRoomFromScreen()
        await settled(harness)
        #expect(harness.count("rummy_leave") == 2)
        #expect(harness.rummy.phase == .lobby)
        #expect(harness.games.rummyLeftByTabNotice == nil, "스스로 누른 나가기에 탭 얘기를 했다")
        await harness.tearDown()
    }

    @Test("화면 [방 닫고 나가기](방장): 못 닿으면 방에 남는다 · 그새 판이면 0건")
    func screenHostConfirm() async {
        let failed = await seated("tab-button-host", as: .host)
        failed.server.setDefault("rummy_leave", json: downJSON, status: 500)
        failed.games.leaveRummyRoomFromScreen()
        await settled(failed)
        #expect(failed.rummy.phase == .room)
        #expect(failed.games.isRummyLeaveUnconfirmed)

        let started = await seated("tab-button-started", as: .host)
        serveState(started, status: "active", mySeatState: "playing", seat: .host)
        started.apply()
        started.games.leaveRummyRoomFromScreen()
        await settled(started)
        #expect(started.count("rummy_leave") == 0, "지난 확인으로 시작된 판을 기권시켰다")
        #expect(started.rummy.phase == .playing)
        await failed.tearDown()
        await started.tearDown()
    }

    // MARK: - 검토 지적: 수락 뒤

    @Test("방장 수락 후 응답을 기다리는 사이 다른 탭으로 갔다: 끌고 가지 않는다 · 1건")
    func hostMovesWhileLeaving() async {
        let harness = await seated("tab-host-moved", as: .host)
        let router = harness.model.router
        harness.server.enqueue("rummy_leave") { _ in
            Thread.sleep(forTimeInterval: 0.2)
            return .json(#"{"status":"ok"}"#)
        }
        tap(.me, harness)
        harness.games.confirmRummyDeparture()
        #expect(await waits.wait { harness.count("rummy_leave") == 1 })
        tap(.messages, harness)
        #expect(router.selectedTab == .messages)
        await settled(harness)
        #expect(router.selectedTab == .messages, "사람이 고른 탭에서 수락 때 탭으로 끌고 갔다")
        #expect(harness.count("rummy_leave") == 1)
        #expect(harness.rummy.phase == .lobby)
        await harness.tearDown()
    }

    @Test("방장 수락 후 다른 탭으로 갔고 나가기가 실패했다: 혼자 다시 보낸다(화면 밖에 방이 열린 채 남지 않는다)")
    func hostMovedThenRetries() async {
        let harness = await seated("tab-host-moved-fail", as: .host)
        harness.games.rummyLeaveRetrySeconds = [0.01]
        harness.server.enqueue("rummy_leave", slowFailure(seconds: 0.2))
        tap(.me, harness)
        harness.games.confirmRummyDeparture()
        #expect(await waits.wait { harness.count("rummy_leave") == 1 })
        tap(.messages, harness)
        await settled(harness)
        #expect(harness.count("rummy_leave") == 2)
        #expect(harness.rummy.phase == .lobby)
        #expect(harness.model.router.selectedTab == .messages)
        await harness.tearDown()
    }

    @Test("방장 수락: 나간 뒤 로비 조회를 기다리지 않고 간다 — 늦은 조회에 빈 로비로 묶이지 않는다")
    func hostResumeDoesNotWaitForLobby() async {
        let harness = await seated("tab-host-lobby", as: .host)
        let router = harness.model.router
        let lobby = RummyWireJSON.lobby(nowMs: harness.nowMs)
        harness.server.setDefault("rummy_lobby") { _ in
            Thread.sleep(forTimeInterval: 0.2)
            return .json(lobby)
        }
        let before = harness.count("rummy_lobby")
        tap(.me, harness)
        harness.games.confirmRummyDeparture()
        #expect(await waits.wait { harness.count("rummy_lobby") > before })
        #expect(router.selectedTab == .me, "로비 응답을 기다리느라 탭이 안 옮겨 갔다")
        await settled(harness)
        await harness.tearDown()
    }

    // MARK: - 검토 지적: 탭이 굳는 길

    @Test("안 뜬 확인에 탭을 또 눌렀다: 값을 내렸다 올려 다시 띄운다(같은 값이면 SwiftUI 가 모른 채 탭만 막힌다) · 0건 · 그 틈에 취소하면 안 되살아난다")
    func repeatedAskRefires() async {
        let harness = await seated("tab-refire", as: .host)
        let router = harness.model.router
        let serial = router.tabRefusalSerial
        tap(.now, harness)
        tap(.me, harness)
        #expect(harness.games.rummyDeparturePrompt == nil)
        #expect(await waits.wait { harness.games.rummyDeparturePrompt == .confirmCloseRoom }, "확인이 다시 안 떠 탭이 굳는다")
        #expect(router.tabRefusalSerial == serial + 2)
        #expect(harness.count("rummy_leave") == 0)
        // 가려던 곳은 마지막에 누른 탭이다.
        harness.games.confirmRummyDeparture()
        await settled(harness)
        #expect(router.selectedTab == .me)

        let cancelled = await seated("tab-refire-no", as: .host)
        tap(.now, cancelled)
        tap(.me, cancelled)
        cancelled.games.cancelRummyDeparture()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(cancelled.games.rummyDeparturePrompt == nil, "취소한 확인이 되살아났다")
        await harness.tearDown()
        await cancelled.tearDown()
    }

    @Test("방장 탭 재선택으로 화면이 내려간 사이 판이 시작됐다: 되세운 화면에 '방이 닫혀요'가 안 뜬다 · 0건")
    func stalePromptDropsOnReappear() async {
        let harness = await seated("tab-reappear", as: .host)
        let router = harness.model.router
        router.pathBinding(for: .games).wrappedValue = NavigationPath()
        harness.games.rummyScreenDidDisappear()
        #expect(harness.games.rummyDeparturePrompt == .confirmCloseRoom)
        #expect(await waits.wait { router.path(for: .games).count == 1 })
        harness.apply()
        harness.games.rummyScreenDidAppear()
        #expect(harness.games.rummyDeparturePrompt == nil)
        #expect(harness.count("rummy_leave") == 0)
        await harness.tearDown()
    }

    // MARK: - 방 안내 줄

    @Test("방 안내 줄: 손님 · 방장은 말이 다르고 놀던 기기 · 판 · 로비는 말하지 않는다")
    func hintTable() async {
        typealias Plan = GamesRummyRoomPlan
        #expect(Plan.tabExitHint(.leaveRoom) == GamesRummyText.tabExitHintGuest)
        #expect(Plan.tabExitHint(.confirmCloseRoom) == GamesRummyText.tabExitHintHost)
        #expect(Plan.tabExitHint(.close) == nil)
        #expect(Plan.tabExitHint(.confirmForfeit) == nil)
        #expect(GamesRummyText.tabExitHintGuest != GamesRummyText.tabExitHintHost)
        let guest = await seated("tab-hint", as: .guest)
        #expect(Plan.tabExitHint(GamesRummyExit.decision(guest.rummy)) == GamesRummyText.tabExitHintGuest)
        let idle = await seated("tab-hint-idle", as: .guest, engaged: false)
        #expect(Plan.tabExitHint(GamesRummyExit.decision(idle.rummy)) == nil)
        await guest.tearDown()
        await idle.tearDown()
    }

    @Test("장면: 탭 이탈 데모 둘이 방장·손님 방에 선다")
    func demoScenes() {
        typealias R = MobileDemoRummyRoute
        #expect(R(demoRoute: "games/rummy/room/tab-exit")?.scene == .roomTabExit)
        #expect(R(demoRoute: "games/rummy/room/guest/tab-exit")?.scene == .roomGuestTabExit)
        #expect(R.Scene.roomTabExit.focusMatchID == R.Scene.roomID && R.Scene.roomTabExit.engages)
        #expect(R.Scene.roomGuestTabExit.focusMatchID == R.Scene.guestRoomID && R.Scene.roomGuestTabExit.engages)
    }
}
