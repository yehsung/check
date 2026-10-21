import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.60 1:1 테트리스 **맥 창**과 그 둘레 — 창 수명 · 키 · 입구 · 받은 신청이 닿는 세 표면 · 앱 배선 · 버전.
//
// 창은 체스 창(v0.3.44)의 수명 규약을 그대로 쓴다. 여기서 못 박는 것은 **테트리스에서만 틀릴 수 있는 것**들이다:
//   · 창이 키를 잃거나 닫혀도 판이 끝나지 않는다(판은 단조 시계로 흐른다 — 설계 D10). 키 상실 처리기 자체가 없다.
//   · ★ 미니게임 창의 전역 모니터가 이 창의 스페이스(하드드롭)를 양보한다(`standaloneWindowIDs` 등록).
//   · 이 창 전용 키 모니터: 뗌은 언제나 · 누름은 이 창으로 간 키만 · 판 밖(로비)에서는 아무것도 삼키지 않는다 ·
//     키 반복은 삼키기만 · 8초 굳은 키 그물.
//   · 받은 신청 세 표면(말풍선 큐 · 팝오버 배너 · 메뉴바 점)과 "대결이 시작됐어요" 말풍선.
//   · CheckApp 배선 여섯 문(전부 옵셔널이라 빠져도 컴파일·스토어 테스트는 초록이다 — 그래서 글자로 되묻는다).
//
// 창을 실제로 띄우는 검증은 알파 0(`CheckPanelVisibility`) · 직렬이고, 띄운 창은 곧바로 화면 밖으로 옮긴다.
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

// MARK: - 헬퍼

private let twMe = "00000000-0000-0000-0000-0000000000a1"
private let twRival = TetrisDuelUser(id: "00000000-0000-0000-0000-0000000000b2", displayName: "민수",
                                     avatarURL: nil, characterID: "fox", isWorking: true, isCapable: true,
                                     inMatch: true)

@MainActor
private func twController(_ store: TetrisDuelStore) -> CheckTetrisDuelWindowController {
    let controller = CheckTetrisDuelWindowController()
    controller.configure(store: store, content: { _ in AnyView(Color.clear) })
    return controller
}

/// 네트워크 없는 스토어(host nil). 폴링·판 루프는 재운다.
@MainActor
private func twStore() -> TetrisDuelStore {
    let store = TetrisDuelStore()
    store.pollStepSeconds = 3_600
    store.gameLoopStepSeconds = 3_600
    return store
}

private func twMatch(finished: Bool = false, outcome: TetrisDuelOutcome? = nil) -> TetrisDuelMatchState {
    TetrisDuelMatchState(
        id: "7e7e0000-0000-4000-8000-000000000060", stake: 5, seed: 7, opponent: twRival,
        acceptedAt: nil, readyDeadline: nil, startAt: nil, maxEnd: nil, meReady: true,
        opponentBoard: .empty, isFinished: finished, outcome: outcome,
        endReason: finished ? .topout : nil, rubyDelta: finished ? 4 : nil, finishedAt: nil)
}

/// 판이 도는 스토어 — 시작한 판 구동기(시드 7)를 단조 시각 100 에 세운다. 입력은 이 판에 곧바로 들어간다.
@MainActor
private func twLiveStore() -> TetrisDuelStore {
    let store = twStore()
    store.uptime = { 100 }
    var game = TetrisGame(seed: 7)
    game.action()
    store.duel = TetrisDuelSession(seed: 7, startedGame: game, startAt: 100)
    store.duelMatchID = twMatch().id
    store.match = twMatch()
    store.phase = .playing
    return store
}

/// 화면에 올리되 보이지 않게(알파 0 · 화면 밖) — `strokeBelongsToGame`·`yieldsToOtherWindow` 가 `isVisible` 을 요구한다.
@MainActor
private func twWindow(identifier: String? = nil) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    if let identifier { window.identifier = NSUserInterfaceItemIdentifier(identifier) }
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    window.orderFrontRegardless()
    return window
}

/// 띄운 대결 창을 곧바로 화면 밖으로(알파 0 이어도 사용자 화면 한가운데 두지 않는다).
@MainActor
private func twMoveOffscreen(_ controller: CheckTetrisDuelWindowController) {
    controller.currentWindow?.setFrameOrigin(NSPoint(x: -6000, y: -6000))
}

// MARK: - 레이아웃 산식(순수)

@Test("창 크기 항등식 — 내 판은 솔로 캔버스 344×356 그대로 · 세 열과 본문 높이가 창 크기를 정한다")
func theDuelWindowLayoutAddsUp() {
    #expect(TetrisDuelWindowLayout.canvasSize == MiniGameWindowLayout.canvasSize,
            "내 판 캔버스가 솔로와 다르다 — 같은 손이 다른 배율의 판을 친다")
    #expect(TetrisDuelWindowLayout.canvasSize == CGSize(width: 344, height: 356))
    let inner = TetrisDuelWindowLayout.canvasSize.width + TetrisDuelWindowLayout.opponentColumnWidth
        + TetrisDuelWindowLayout.sideColumnWidth + TetrisDuelWindowLayout.columnSpacing * 2
    #expect(inner == TetrisDuelWindowLayout.innerWidth)
    #expect(TetrisDuelWindowLayout.lobbyListWidth + TetrisDuelWindowLayout.columnSpacing
            + TetrisDuelWindowLayout.lobbySideWidth == TetrisDuelWindowLayout.innerWidth, "로비 두 열이 안쪽 폭과 안 맞는다")
    let expectedBody: CGFloat = 462        // 위 띠 34 + 간격 12 + 이름 카드 52 + 간격 8 + 캔버스 356
    #expect(TetrisDuelWindowLayout.bodyHeight == expectedBody)
    #expect(TetrisDuelWindowLayout.contentSize == CGSize(width: 900, height: 554))
    #expect(TetrisDuelWindowLayout.lobbyLiveHeight >= 80, "지금 대결 중 칸이 \(TetrisDuelWindowLayout.lobbyLiveHeight)pt 로 눌렸다")
    // 13" 맥 작업 영역(1440×900 − 메뉴바·독)에 든다.
    #expect(TetrisDuelWindowLayout.contentSize.width <= 1240 && TetrisDuelWindowLayout.contentSize.height <= 700)
    // 상대 미니 판 — 셀 9pt(설계서 "8~9pt"), 상대 열 안에 여백과 함께 든다.
    #expect(TetrisMiniBoardLayout.cell >= 8 && TetrisMiniBoardLayout.cell <= 9)
    #expect(TetrisMiniBoardLayout.boardSize.width + 24 <= TetrisDuelWindowLayout.opponentColumnWidth)
}

// MARK: - 키 래치(순수)

@Suite("1:1 테트리스 창 — 키 래치(순수)")
struct TetrisDuelKeyLatchTests {
    @Test("누름은 이 창으로 간 키만 · 판 밖(로비)에서는 아무것도 안 삼킨다 · 뗌은 언제나 스토어로 간다")
    func pressesNeedTheDuelWindowButReleasesAlwaysPass() {
        // 없으면: 다른 창(팝오버 목록 · 할 일 보드)에서 누른 화살표를 대결 창이 삼켜 커서가 죽거나(게이트 없음),
        //        다른 창에서 뗀 ← 가 판에 안 닿아 조각이 벽까지 미끄러진다(뗌을 게이트 뒤에 둠).
        var latch = TetrisDuelKeyLatch()
        let foreign = latch.handle(keyCode: 123, isUp: false, isRepeat: false, hasModifier: false,
                                   belongs: false, live: true, now: 0)
        #expect(foreign.consumed == false && foreign.commands.isEmpty, "다른 창으로 간 ← 를 삼켰다")
        let lobby = latch.handle(keyCode: 49, isUp: false, isRepeat: false, hasModifier: false,
                                 belongs: true, live: false, now: 0)
        #expect(lobby.consumed == false && lobby.commands.isEmpty, "로비에서 스페이스를 삼킨다 — 초점 단추가 안 눌린다")

        let press = latch.handle(keyCode: 123, isUp: false, isRepeat: false, hasModifier: false,
                                 belongs: true, live: true, now: 0)
        #expect(press.consumed && press.commands == [.left(true)])
        #expect(latch.input.moveLeftHeld)
        // ★ 기준선 갈림: 같은 키의 뗌이 **다른 창**에서 와도 스토어로 간다(삼키지는 않는다).
        let release = latch.handle(keyCode: 123, isUp: true, isRepeat: false, hasModifier: false,
                                   belongs: false, live: true, now: 0.2)
        #expect(release.consumed == false, "남의 창으로 간 뗌을 삼켰다")
        #expect(release.commands == [.left(false)], "다른 창에서 뗀 ← 가 판에 안 닿는다 — 조각이 벽까지 미끄러진다")
        #expect(!latch.input.moveLeftHeld)
    }

    @Test("키 표는 솔로와 같다 — ← → ↓ · ↑/X 시계 · Z 반시계 · C 홀드 · 스페이스 하드드롭 · ESC 는 없다")
    func theKeyTableMatchesSolo() {
        var latch = TetrisDuelKeyLatch()
        func down(_ code: UInt16) -> [TetrisDuelKeyLatch.Command] {
            latch.handle(keyCode: code, isUp: false, isRepeat: false, hasModifier: false,
                         belongs: true, live: true, now: 0).commands
        }
        #expect(down(124) == [.right(true)])
        #expect(down(125) == [.softDrop(true)])
        #expect(down(126) == [.rotate(clockwise: true)])
        #expect(down(7) == [.rotate(clockwise: true)])
        #expect(down(6) == [.rotate(clockwise: false)])
        #expect(down(8) == [.hold])
        #expect(down(49) == [.hardDrop])
        // ESC 정지는 없다(대결은 멈출 수 없다) — 삼키지도 않는다(다른 화면의 취소 키를 훔치지 않게).
        let escape = latch.handle(keyCode: 53, isUp: false, isRepeat: false, hasModifier: false,
                                  belongs: true, live: true, now: 0)
        #expect(escape.consumed == false && escape.commands.isEmpty)
        // 회전·홀드의 뗌은 아무 일도 안 한다(멱등).
        let rotateUp = latch.handle(keyCode: 126, isUp: true, isRepeat: false, hasModifier: false,
                                    belongs: true, live: true, now: 0)
        #expect(rotateUp.commands.isEmpty)
    }

    @Test("키 반복은 삼키기만 한다 · ⌘ 조합은 흘린다 · 8초 굳은 키는 스스로 뗀다 · 전부 떼기")
    func repeatsModifiersAndTheStuckKeyNet() {
        // 없으면: OS 키 반복이 하드드롭을 연타하거나(반복 = 새 누름), ⌘← 가 판을 움직이거나,
        //        ⌘ 로 사라진 keyUp 때문에 ← 가 판 끝까지 굳는다.
        var latch = TetrisDuelKeyLatch()
        _ = latch.handle(keyCode: 123, isUp: false, isRepeat: false, hasModifier: false, belongs: true, live: true, now: 10)
        let repeated = latch.handle(keyCode: 49, isUp: false, isRepeat: true, hasModifier: false,
                                    belongs: true, live: true, now: 10.1)
        #expect(repeated.consumed && repeated.commands.isEmpty, "키 반복이 하드드롭을 다시 냈다")
        let command = latch.handle(keyCode: 124, isUp: false, isRepeat: false, hasModifier: true,
                                   belongs: true, live: true, now: 10.1)
        #expect(command.consumed == false && command.commands.isEmpty, "⌘→ 가 판을 움직였다")

        #expect(latch.releaseStuck(now: 17.9).isEmpty, "8초가 안 됐는데 뗐다 — 정직하게 누르고 있는 손을 끊는다")
        #expect(latch.releaseStuck(now: 18.0) == [.left(false)], "8초 넘게 굳은 ← 를 안 뗀다")
        #expect(!latch.input.moveLeftHeld)
        #expect(latch.releaseStuck(now: 30).isEmpty, "이미 뗀 키를 또 뗐다")

        _ = latch.handle(keyCode: 125, isUp: false, isRepeat: false, hasModifier: false, belongs: true, live: true, now: 40)
        #expect(latch.input.softDropHeld)
        latch.releaseAll()
        #expect(!latch.input.softDropHeld && latch.softSince == nil)
    }
}

// MARK: - 창 수명 · 키 모니터 (직렬 — AppKit 창을 동시에 만들면 SIGSEGV 실측)

@MainActor
@Suite(.serialized)
struct TetrisDuelWindowLifecycleTests {
    @Test
    func theWindowIdentityMatchesTheContract() {
        // 없으면: 자동저장 이름이 다른 창과 겹쳐 자리 저장이 조용히 죽거나, 식별자가 달라 전역 모니터가 이 창을 못 알아본다.
        #expect(CheckTetrisDuelWindowController.windowTitle == "1:1 테트리스")
        #expect(CheckTetrisDuelWindowController.frameAutosaveName == "check.tetris-duel.window")
        #expect(CheckTetrisDuelWindowController.fixedContentSize == NSSize(width: 900, height: 554))
        let window = CheckTetrisDuelWindowController.makeWindow()
        defer { window.close() }
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(!window.styleMask.contains(.resizable), "크기가 바뀌면 판 배율이 창에 딸려 흔들린다")
        #expect(!window.isReleasedWhenClosed)
        #expect(!window.hidesOnDeactivate, "다른 앱을 누르면 창이 사라진다 — 판은 계속 흐르는데 안 보인다")
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        #expect(window.identifier?.rawValue == CheckTetrisDuelWindowController.frameAutosaveName)
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 스위트가 사용자 화면에 창을 띄운다")
    }

    @Test
    func losingKeyMinimizingOrClosingNeverEndsTheMatch() throws {
        // 없으면: 다른 앱을 잠깐 본 것 · 창을 내린 것이 판 중단이 된다 — 루비가 걸린 판을 사용자 실수 한 번에 잃는다.
        #expect(!CheckTetrisDuelWindowController().responds(to: #selector(NSWindowDelegate.windowDidResignKey(_:))),
                "테트리스 창이 키 상실에 반응한다")
        let store = twLiveStore()
        let match = try #require(store.match)
        let controller = twController(store)
        defer { controller.discardWindowForTesting(); store.stopPolling() }
        controller.show()
        twMoveOffscreen(controller)
        #expect(store.isWindowVisible, "창을 열었는데 스토어가 '보임'을 안 받았다 — 준비 보고의 문이 안 열린다")
        #expect(controller.frameAutosaveActive, "자동저장 이름이 다른 창과 겹친다")
        #expect(TetrisDuelKeys.isInstalled(for: controller), "창을 열었는데 이 창의 키 모니터가 안 걸렸다 — 판을 조작할 수 없다")
        let window = try #require(controller.currentWindow)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(store.match == match && store.phase == .playing, "키를 잃었더니 판이 바뀌었다")
        #expect(store.duel != nil, "키를 잃었더니 판 구동기가 사라졌다")

        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        #expect(!store.isWindowVisible, "최소화가 '안 보임'을 안 알렸다")
        #expect(store.match == match && store.duel != nil, "최소화했더니 판이 끝났다 — 판은 단조 시계로 계속 흘러야 한다(D10)")

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(!controller.isOpen)
        #expect(store.match == match && store.phase == .playing && store.duel != nil,
                "창을 닫았더니 진행 중인 판이 바뀌었다 — 닫기는 기권이 아니다")
    }

    @Test
    func closingFoldsAFinishedMatchButMinimizingDoesNot() throws {
        // 없으면: 끝난 판의 결과 화면이 닫은 뒤 한 시간이 지나도 다시 열면 그대로 선다(닫기 통지가 빠짐), 또는
        //        최소화만 했는데 결과 화면이 사라진다(닫기와 최소화를 한 통지로 합침).
        let store = twStore()
        store.match = twMatch(finished: true, outcome: .won)
        store.phase = .finished
        let controller = twController(store)
        defer { controller.discardWindowForTesting(); store.stopPolling() }
        controller.show()
        twMoveOffscreen(controller)
        let window = try #require(controller.currentWindow)
        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        #expect(store.match?.isFinished == true, "최소화만 했는데 결과 화면이 접혔다")
        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(store.match == nil && store.phase == .lobby, "닫았는데 끝난 판이 남았다 — 다음에 열면 낡은 결과가 선다")
    }

    @Test
    func occlusionReleasesKeysButKeepsVisibility() throws {
        // 없으면: 가려진 창(keyUp 을 못 받는다)에서 ← 가 굳어 조각이 벽까지 미끄러지거나, 가림이 '안 보임'으로 번져 준비 보고가 멎는다.
        let store = twLiveStore()
        let controller = twController(store)
        defer { controller.discardWindowForTesting(); store.stopPolling() }
        controller.show()
        twMoveOffscreen(controller)
        let window = try #require(controller.currentWindow)
        let before = try #require(store.duel?.game.active?.column)
        #expect(TetrisDuelKeys.handleForTesting(keyCode: 123, isUp: false, eventWindow: window, duelWindow: window,
                                                store: store, now: 100))
        #expect(store.duel?.game.active?.column == before - 1, "← 가 판에 안 닿았다")
        controller.applyOcclusion(visible: false)
        #expect(store.isWindowVisible, "가려졌다고 '안 보임'까지 됐다")
        #expect(controller.lastOcclusionNotice == false)
        // 판은 단조 시계로 흐른다 — 0.5초를 흘려도 조각이 더 왼쪽으로 가지 않으면 ← 가 풀린 것이다(DAS 0.167초).
        store.uptime = { 100.5 }
        store.tick()
        #expect(store.duel?.game.active?.column == before - 1, "가렸는데 ← 가 굳은 채 조각이 계속 미끄러진다")
        // 래치도 놓였다 — 안 놓이면 가렸던 창으로 돌아와 다시 누른 ← 가 **처음 누른 시각**의 도장을 이어받아
        // 굳은 키 그물(8초)이 정직하게 누르고 있는 손을 일찍 끊는다.
        #expect(!TetrisDuelKeys.latchForTesting.input.moveLeftHeld, "가렸는데 래치가 ← 를 쥐고 있다")
        controller.applyOcclusion(visible: true)
        #expect(TetrisDuelKeys.handleForTesting(keyCode: 123, isUp: false, eventWindow: window, duelWindow: window,
                                                store: store, now: 107))
        #expect(TetrisDuelKeys.latchForTesting.leftSince == 107, "다시 누른 ← 가 옛 도장(100초)을 이어받았다")
    }

    @Test
    func theKeyMonitorDrivesTheBoardOnlyFromTheDuelWindow() throws {
        // 없으면: 미니게임 창·팝오버에서 누른 키가 루비가 걸린 판을 움직이거나, 대결 창의 스페이스가 하드드롭을 안 한다.
        TetrisDuelKeys.remove()
        defer { TetrisDuelKeys.remove() }
        let store = twLiveStore()
        let duel = twWindow(identifier: CheckTetrisDuelWindowController.frameAutosaveName)
        let other = twWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
        defer { [duel, other].forEach { $0.orderOut(nil) } }
        let start = try #require(store.duel?.game.active)

        #expect(TetrisDuelKeys.handleForTesting(keyCode: 124, isUp: false, eventWindow: other, duelWindow: duel,
                                                store: store, now: 100) == false)
        #expect(store.duel?.game.active?.column == start.column, "다른 창에서 누른 → 가 판을 움직였다")
        #expect(TetrisDuelKeys.handleForTesting(keyCode: 124, isUp: false, eventWindow: duel, duelWindow: duel,
                                                store: store, now: 100))
        #expect(store.duel?.game.active?.column == start.column + 1)
        _ = TetrisDuelKeys.handleForTesting(keyCode: 124, isUp: true, eventWindow: duel, duelWindow: duel,
                                            store: store, now: 100)

        let filled = store.duel?.game.board.joined().compactMap { $0 }.count ?? 0
        #expect(TetrisDuelKeys.handleForTesting(keyCode: 49, isUp: false, eventWindow: duel, duelWindow: duel,
                                                store: store, now: 100))
        let after = store.duel?.game.board.joined().compactMap { $0 }.count ?? 0
        #expect(after == filled + 4, "스페이스가 하드드롭을 안 했다(굳은 칸 \(filled) → \(after))")

        // ★ 기준선 갈림: 같은 스페이스가 **로비**에서는 삼켜지지 않는다(초점 단추를 눌러야 한다).
        let lobby = twStore()
        #expect(TetrisDuelKeys.handleForTesting(keyCode: 49, isUp: false, eventWindow: duel, duelWindow: duel,
                                                store: lobby, now: 100) == false)
    }

    /// ★ 미니게임 창을 띄워 둔 채 **테트리스 창**에서 누른 스페이스는 테트리스 몫이다(하드드롭).
    @Test
    func spacePressedInTheDuelWindowIsNeverTakenByTheMiniGame() {
        // 없으면: `standaloneWindowIDs` 에서 이 창을 빼도 초록이다 — 그러면 미니게임 창을 열어 둔 사람의 하드드롭이 삼켜진다.
        let game = twWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
        let duel = twWindow(identifier: CheckTetrisDuelWindowController.frameAutosaveName)
        let unknown = twWindow()
        defer { [game, duel, unknown].forEach { $0.orderOut(nil) } }
        #expect(MiniGameSpaceKey.yieldsToOtherWindow(duel, gameWindow: game),
                "테트리스 창으로 간 스페이스를 미니게임이 삼킨다 — standaloneWindowIDs 에 이 창이 빠졌다")
        #expect(!MiniGameSpaceKey.yieldsToOtherWindow(unknown, gameWindow: game),
                "전제: 모르는 창에는 양보하지 않는다 — 이 답이 참이면 위 단언이 아무것도 안 잰다")
        // 화살표는 미니게임 쪽 엄격 게이트가 이미 양보한다(이 창은 미니게임 창이 아니다).
        #expect(!MiniGameSpaceKey.strokeBelongsToGame(duel, gameWindow: game))
    }
}

// MARK: - 미니게임 입구

@MainActor
@Suite(.serialized)
struct TetrisDuelEntryTests {
    @Test
    func theEntryOpensTheDuelWindowThenClosesTheMiniGameWindow() {
        // 없으면: 입구가 테트리스 창만 열고 미니게임 창을 남기거나(창 둘), 먼저 내리고 나중에 열거나, 엉뚱한 창을 연다.
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
                                   defaults: twDefaults("v0360-tetris-entry"), workspaceNotifications: nil)
        var tetrisOpens: [Bool] = []
        var others = 0
        store.tetris.presentWindow = { tetrisOpens.append(store.isMiniGamePanelVisible) }
        store.chess.presentWindow = { others += 1 }
        store.gomoku.presentWindow = { others += 1 }
        store.isMiniGamePanelVisible = true
        let token = store.miniGameInterruptToken

        store.openTetrisDuelFromMiniGame()

        #expect(tetrisOpens == [true], "테트리스 창이 뜨는 순간 미니게임 창이 이미 내려가 있었다 — 여는 것이 먼저다")
        #expect(others == 0, "테트리스 입구가 다른 대결 창을 띄웠다")
        #expect(store.isMiniGamePanelVisible == false, "창 둘이 떠 있다")
        #expect(store.miniGameInterruptToken == token + 1)
    }

    @Test
    func theHeaderCarriesTheTetrisDoorThroughTheStoreDoor() throws {
        // 없으면: 버튼은 있는데 아무 데도 안 이어지거나(머리글 클로저 기본값 {}), 스토어 문을 건너뛰어 미니게임 창이 남는다.
        let panel = twStripped(try twSource("MiniGamePanel.swift"))
        #expect(panel.contains("MiniGameTetrisDuelEntryButton { onTetrisDuel() }"), "머리글에 테트리스 입구가 없다")
        #expect(panel.contains("onTetrisDuel: { store.openTetrisDuelFromMiniGame() }"),
                "테트리스 입구가 스토어의 문을 안 지난다 — 미니게임 창이 안 닫힌다")
        // 세 문이 **한 묶음** 안에 있다(묶음 밖에 캡슐로 두면 344pt 를 넘는다 — V0338 헤더 시험).
        let group = try #require(twBlock(panel, after: "MiniGameDuelEntryGroup {"))
        #expect(group.contains("MiniGameGomokuEntryButton { onGomoku() }")
                && group.contains("MiniGameChessEntryButton { onChess() }")
                && group.contains("MiniGameTetrisDuelEntryButton { onTetrisDuel("),
                "1:1 입구 셋이 한 묶음 안에 없다: \(group)")
        #expect(panel.contains("CheckTetrisDuelWindowController.frameAutosaveName"),
                "전역 스페이스 모니터의 독립 창 목록에 테트리스 창이 없다")
        let miniGameStore = twStripped(try twSource("WorkTimerStoreMiniGame.swift"))
        let door = try #require(twFunctionBody(miniGameStore, name: "openTetrisDuelFromMiniGame"))
        let opened = try #require(door.range(of: "tetris.openWindow(focusMatchID: nil)"))
        let closed = try #require(door.range(of: "closeMiniGamePanel()"))
        #expect(opened.lowerBound < closed.lowerBound, "미니게임 창을 먼저 내린다 — 여는 것이 먼저다")
    }

    @MainActor
    @Test
    func theGroupedDoorsAreThreeButtonsWithNamesAndTooltips() throws {
        // 없으면: 묶음이 이름 대신 아이콘만 그리거나(문 셋이 서로 구별 안 됨), 보이스오버가 "1:1 테트리스" 를 못 읽는다.
        #expect(MiniGameTetrisDuelEntryButton.title == "1:1 테트리스")
        #expect([MiniGameGomokuEntryButton.segmentTitle, MiniGameChessEntryButton.segmentTitle,
                  MiniGameTetrisDuelEntryButton.segmentTitle] == ["오목", "체스", "테트리스"])
        let panel = twStripped(try twSource("MiniGamePanel.swift"))
        let capsule = try #require(twBetween(panel, "private struct MiniGameEntryCapsule: View {", "private var capsule: some View {"))
        #expect(capsule.contains("Text(segmentTitle)"), "묶음 조각이 짧은 이름을 안 그린다")
        #expect(capsule.contains(".accessibilityLabel(title)"), "묶음 조각이 보이스오버에게 게임 이름을 안 말한다")
        #expect(capsule.contains(".checkTooltip(help)"), "묶음 조각에 말풍선이 없다")
        #expect(NSImage(systemSymbolName: TetrisDuelEntryIcon.resolved, accessibilityDescription: nil) != nil,
                "테트리스 대결 아이콘(\(TetrisDuelEntryIcon.resolved))이 이 맥에서 안 풀린다")
        #expect(TetrisDuelEntryIcon.symbol != MiniGameKind.tetris.icon, "대결 아이콘이 솔로 테트리스 칩과 같다")
    }
}

// MARK: - 받은 신청 세 표면 · 시작 알림

@MainActor
@Suite(.serialized)
struct TetrisDuelReachTests {
    @Test
    func theInviteAndStartBubblesReachTheCharacterQueue() throws {
        // 없으면: 스토어가 부르는 문이 아무 데도 안 물려 캐릭터가 신청을 말하지 않거나, 처리된 신청이 뒤늦게 뜬다.
        let (engine, controller, store) = twOverlay()
        defer {
            controller.clearTetrisInvites()
            controller.updateWorking(false)
        }
        let invite = twInvite(id: "invite-1", expiresIn: 50)
        store.tetris.incoming = [invite]
        controller.enqueueTetrisInvite(invite)
        controller.enqueueTetrisInvite(invite)
        #expect(controller.tetrisInviteQueue.count == 1, "같은 신청이 두 번 들어갔다")
        #expect(controller.showNextTetrisInviteBubble())
        let text = CheckOverlayController.tetrisInviteBubbleText(name: "민수", stake: 5)
        #expect(engine.greetingText == text)
        #expect(text.contains("테트리스"), "말풍선이 어느 게임인지 말하지 않는다")
        #expect(text != CheckOverlayController.chessInviteBubbleText(name: "민수", stake: 5))
        #expect(controller.tetrisInviteBubbleScreenRect() == nil, "배선 전인데 클릭 자리가 생겼다")
        controller.onOpenTetrisDuel = { _ in }
        #expect(controller.tetrisBubbleMatchID() == "invite-1", "말풍선을 눌러도 그 신청의 창을 열 수 없다")
        engine.greetingText = nil

        // 처리된(스토어에서 사라진) 신청 · 만료된 신청은 뒤늦게 뜨지 않는다.
        let handled = twInvite(id: "handled", expiresIn: 50)
        store.tetris.incoming = []
        controller.enqueueTetrisInvite(handled)
        #expect(controller.showNextTetrisInviteBubble() == false)
        #expect(controller.tetrisInviteQueue.isEmpty, "이미 처리된 신청이 뒤늦게 말풍선으로 뜬다")
        // 떠 있는 말풍선 뒤에서는 기다린다(소비하지 않는다).
        engine.showBubble("다른 안내", seconds: 60)
        let waiting = twInvite(id: "waiting", expiresIn: 50)
        store.tetris.incoming = [waiting]
        controller.enqueueTetrisInvite(waiting)
        #expect(controller.showNextTetrisInviteBubble() == false)
        #expect(controller.tetrisInviteQueue.map(\.id) == ["waiting"], "못 띄운 신청을 큐에서 뺐다")
    }

    @Test
    func theStartBubbleOnlyShowsWhileTheWindowIsHidden() throws {
        // 없으면: 창을 못 띄운 사람(다른 앱 · 잠든 맥에서 막 깬)이 판이 시작된 줄 모르고, 준비하지 못한 채 30초 뒤 판이 무산된다.
        let (engine, controller, store) = twOverlay()
        defer {
            controller.clearTetrisInvites()
            controller.updateWorking(false)
        }
        // "대결이 시작됐어요" — 창이 안 보일 때만, 끝난 판이면 버린다.
        let tetris = store.tetris
        tetris.match = twMatch()
        tetris.isWindowVisible = false
        let attention = TetrisDuelAttention(kind: .matchStarted, matchID: twMatch().id, opponentName: "민수")
        #expect(CheckOverlayController.tetrisAttentionIsCurrent(attention, in: tetris))
        tetris.isWindowVisible = true
        #expect(!CheckOverlayController.tetrisAttentionIsCurrent(attention, in: tetris), "창이 보이는데 말풍선을 띄운다")
        tetris.isWindowVisible = false
        tetris.match = twMatch(finished: true, outcome: .lost)
        #expect(!CheckOverlayController.tetrisAttentionIsCurrent(attention, in: tetris), "끝난 판인데 시작했다고 한다")
        tetris.match = twMatch()
        controller.enqueueTetrisAttention(attention)
        #expect(controller.showPendingTetrisAttentionBubble())
        #expect(engine.greetingText == CheckOverlayController.tetrisAttentionBubbleText(attention))
        #expect(engine.greetingText?.contains("테트리스") == true, "시작 말풍선이 어느 게임인지 말하지 않는다")
        #expect(controller.pendingTetrisAttention == nil)
        controller.onOpenTetrisDuel = { _ in }
        #expect(controller.tetrisBubbleMatchID() == twMatch().id, "시작 말풍선을 눌러도 그 판을 열 수 없다")
        // 사실이 아니면 **버린다**(기다리지 않는다).
        engine.greetingText = nil
        tetris.isWindowVisible = true
        controller.enqueueTetrisAttention(attention)
        #expect(controller.showPendingTetrisAttentionBubble() == false)
        #expect(controller.pendingTetrisAttention == nil, "사실이 아닌 시작 알림이 큐에 남았다")
    }

    @Test
    func theMenuBarDotAndThePopoverBannerKnowAboutTetrisInvites() throws {
        // 없으면: 테트리스 신청이 메뉴바 점에도 팝오버에도 안 뜬다 — 캐릭터를 꺼 둔 사람에게는 알 길이 0 이다.
        #expect(MenuBarDotReasons().isEmpty)
        #expect(!MenuBarDotReasons(tetrisInvite: true).isEmpty, "테트리스 신청이 점을 안 켠다")
        #expect(MenuBarDotReasons(tetrisInvite: true).accessibilityDescription == "테트리스 신청")
        #expect(MenuBarDotReasons(chessInvite: true, tetrisInvite: true).accessibilityDescription == "체스 신청 · 테트리스 신청")
        let off = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        #expect(MenuBarStatusLabel(snapshot: off, title: "오프", hasTetrisInvite: true).dotReasons.tetrisInvite)
        #expect(MenuBarStatusLabel(snapshot: off, title: "오프").dotReasons.isEmpty)

        let store = twMenuStore()
        let invite = twInvite(id: "invite-1", expiresIn: 48)
        let with = try twBitmap(CheckMenuView(store: store, previewTetrisInvite: invite))
        let without = try twBitmap(CheckMenuView(store: store))
        let grew = Double(with.pixelsHigh - without.pixelsHigh) / 2
        print("[배너] 테트리스 배너 높이 \(grew)pt (예산 \(CheckMenuView.tetrisInviteBannerHeight)pt)")
        #expect(with.pixelsHigh > without.pixelsHigh, "테트리스 신청 배너를 띄웠는데 팝오버가 안 자랐다 — 배너가 안 그려진다")
        #expect(abs(grew - Double(CheckMenuView.tetrisInviteBannerHeight)) < 24,
                "배너 높이 예산(\(CheckMenuView.tetrisInviteBannerHeight)pt)과 실제(\(grew)pt)가 크게 다르다")
        // 체스와 함께 오면 체스가 이긴다(배너는 한 번에 하나 — 창 높이 예산).
        let both = try twBitmap(CheckMenuView(store: store, previewChessInvite: ChessInvite(
            id: "c-1", peer: ChessUser(id: twRival.id, displayName: "민수", avatarURL: nil, characterID: "fox",
                                       isWorking: true, isCapable: true, inMatch: false),
            stake: 5, expiresAt: invite.expiresAt), previewTetrisInvite: invite))
        #expect(both.pixelsHigh == with.pixelsHigh, "체스·테트리스 배너가 함께 그려졌다 — 창이 700pt 상한을 넘는다")
        MiniGameSnapshots.save(with, name: "popover-tetris-invite-banner.png", sub: "stills")
        #expect(TetrisDuelText.inviteBannerTitle(name: "민수").contains("테트리스"))
    }
}

// MARK: - 소스 계약 (문들이 **물려 있는가**)

@Test
func theAppWiresTheTetrisDuelWindowAndAllItsDoors() throws {
    // 없으면: 스토어 쪽 문이 전부 옵셔널이라 전부 빠져도 컴파일·스토어 테스트는 초록이다 — 창이 안 뜨고(판 시작에도),
    //        순위는 영영 로딩이고, 신청 말풍선은 아무 데도 안 닿는다.
    let app = twStripped(try twSource("CheckApp.swift"))
    #expect(app.contains("CheckTetrisDuelWindowController.shared.configure(store: store.tetris"))
    #expect(app.contains("hasTetrisInvite: appDelegate.store.tetris.visibleIncoming != nil"), "메뉴바 점이 테트리스 신청을 모른다")
    let wire = try #require(twFunctionBody(app, name: "wireTetrisDuel"))
    for line in ["tetris.rankingEnabled = true",
                 "tetris.presentWindow = { CheckTetrisDuelWindowController.shared.show() }",
                 "tetris.dismissWindow = { CheckTetrisDuelWindowController.shared.close() }",
                 "self?.overlayController?.enqueueTetrisInvite(invite)",
                 "self?.overlayController?.enqueueTetrisAttention(attention)",
                 "self?.store.tetris.openWindow(focusMatchID: matchID)",
                 "CheckTetrisDuelWindowController.shared.close() self?.overlayController?.clearTetrisInvites()"] {
        #expect(wire.contains(line), "wireTetrisDuel 에 '\(line)' 이 없다")
    }
    #expect(wire.contains("tetris.requestAttention = {"))
    // 순서: 오버레이 컨트롤러를 만든 **뒤**에 잇는다(먼저 이으면 첫 신청이 받을 곳 없이 사라진다).
    let overlay = try #require(app.range(of: "overlayController = CheckOverlayController("))
    let call = try #require(app.range(of: "wireTetrisDuel()"))
    #expect(overlay.lowerBound < call.lowerBound, "wireTetrisDuel() 이 오버레이 컨트롤러보다 먼저다")

    let window = twStripped(try twSource("CheckTetrisDuelWindow.swift"))
    #expect(!window.contains("func windowDidResignKey("), "키 상실 처리기가 생겼다")
    #expect(!window.contains("InterruptToken") && !window.contains("resign("), "창 수명이 판을 끝낸다")
    #expect(window.contains("frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)"))
    #expect(window.contains("TetrisDuelPanel(store: tetris, me: me, safety: safety)"))
    let closed = try #require(twFunctionBody(window, name: "notifyClosed"))
    #expect(closed.contains("store.windowDidClose()"))
    let visibility = try #require(twFunctionBody(window, name: "notifyVisibility"))
    #expect(!visibility.contains("windowDidClose"), "'안 보임' 통지에 닫기가 섞였다 — 최소화가 결과 화면을 접는다")

    let panel = twStripped(try twSource("TetrisDuelPanel.swift"))
    #expect(panel.contains("height: TetrisDuelWindowLayout.contentSize.height, alignment: .topLeading) "
                           + ".background(CheckTheme.background) .foregroundStyle(CheckTheme.primaryText) "
                           + ".checkTooltipLayer() .appUserAvatarCharacters(from: safety)"),
            "창 루트의 툴팁 레이어·캐릭터 표 두 줄이 그 자리에 없다")
    #expect(twCount(".checkTooltip(", in: panel) >= 3, "말풍선 툴팁 자리가 모자라다 — 레이어가 장식이다")
    #expect(!panel.contains("Picker(") && !panel.contains("Menu(") && !panel.contains("TextField("),
            "ImageRenderer 가 못 그리는 컨트롤이 들어왔다")
    // ★ 판(`store.duel`)은 관찰 대상이 아니다 — 잎의 TimelineView 안에서만 읽는다.
    let board = try #require(twBetween(panel, "struct TetrisDuelBoardView: View {", "private var accessibility: String {"))
    #expect(board.contains("TimelineView(") && board.contains("store.duel?.game"))
    #expect(board.contains("store.tick()"), "보이는 창의 프레임이 판을 지금까지 밀지 않는다")
    let elapsedLeaf = try #require(twBetween(panel, "struct TetrisDuelElapsedLeaf: View {", "private struct TetrisDuelMyCard: View {"))
    #expect(elapsedLeaf.contains("TimelineView(") && elapsedLeaf.contains("store.duel?.simulated"))
    #expect(twCount("store.duel", in: panel) == 2,
            "판 구동기를 두 잎(판 그림 · 경과 시간) 밖에서도 읽는다 — 매 걸음 창 전체가 다시 그려질 수 있다")

    let overlaySource = twStripped(try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayWindow.swift"))
    #expect(overlaySource.contains("if let rect = tetrisInviteBubbleScreenRect(), rect.contains(screenPoint) { return true }"),
            "테트리스 말풍선이 몸체로 안 쳐진다 — 클릭이 통과한다")
    #expect(overlaySource.contains("let matchID = tetrisBubbleMatchID() { onOpenTetrisDuel?(matchID) return }"),
            "테트리스 말풍선을 눌러도 창이 안 열린다")

    let menu = twStripped(try twSource("CheckMenuView.swift"))
    #expect(twCount("tetrisInviteBanner", in: menu) >= 3, "테트리스 배너를 그리는 자리가 모자란다(무소속·메인 화면)")
    #expect(menu.contains("if store.isSignedIn, tetrisBannerInvite != nil { return .tetrisInvite }"))
    #expect(menu.contains("case .tetrisInvite: return Self.tetrisInviteBannerHeight"), "배너 높이가 행수 예산에 안 들어간다")
}

@Test
func everyWindowAutosaveNameIsStillUniqueAfterAddingTetris() throws {
    // 없으면: 자동저장 이름이 겹쳐도 초록이다 — 겹치면 자리 저장이 **조용히** 죽는다.
    let directory = CheckCoreSourceLayout.macDirectory
    let enumerator = try #require(FileManager.default.checkSourcesEnumerator(at: directory, includingPropertiesForKeys: nil))
    var names: [String] = []
    for case let file as URL in enumerator where file.pathExtension == "swift" {
        let text = twStripped(try String(contentsOf: file, encoding: .utf8))
        var rest = Substring(text)
        while let found = rest.range(of: "frameAutosaveName = \"") {
            let after = rest[found.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { break }
            names.append(String(after[..<end]))
            rest = after[end...]
        }
    }
    #expect(names.contains("check.tetris-duel.window"))
    #expect(names.count >= 5, "창 이름을 못 찾았다(\(names))")
    #expect(Set(names).count == names.count, "자동저장 이름이 겹친다: \(names)")
}

// v0.3.61: 빌드 번호 고정(0.3.60 / 113)과 "맨 위 섹션" 단언은 다음 버전이 올라가며 거짓이 됐다 — 그 두 사실은 이제
// `V0361UpdatePrefetchTests.versionAndChangelog` 가 0.3.61 / 114 로 잰다. 여기는 0.3.60 섹션의 **내용**과, 테트리스가
// 기대는 하한(빌드가 113 아래로 내려가면 `tetris_min_build() = 113` 서버가 이 맥을 구버전으로 보고 신청을 막는다)만 남긴다.
@Test("CHANGELOG 0.3.60 은 세 줄(사용자 말투) · 빌드는 113 이상")
func versionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    let afterKey = squashed.components(separatedBy: "<key>CFBundleVersion</key><string>").dropFirst().first ?? ""
    let buildNumber = Int(afterKey.prefix { $0.isNumber })
    #expect((buildNumber ?? 0) >= 113, "빌드 번호가 테트리스 하한(113) 아래다: \(String(describing: buildNumber))")
    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.60\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 3, "항목 \(items)")
    #expect(items.contains { $0.contains("1:1 테트리스") })
    #expect(items.allSatisfy { $0.count <= 40 }, "배너 폭에서 잘릴 만큼 긴 줄이 있다: \(items)")
    for banned in ["RPC", "서버", "스토어", "테스트", "tetris_"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(changelog.range(of: "## 0.3.60")!.lowerBound < changelog.range(of: "## 0.3.59")!.lowerBound)
}

// MARK: - 도우미

private func twInvite(id: String, expiresIn seconds: TimeInterval) -> TetrisDuelInvite {
    TetrisDuelInvite(id: id, peer: TetrisDuelUser(id: twRival.id, displayName: "민수", avatarURL: nil,
                                                 characterID: "fox", isWorking: true, isCapable: true, inMatch: false),
                     stake: 5, expiresAt: Date().addingTimeInterval(seconds))
}

@MainActor
private func twOverlay() -> (ReactionEngine, CheckOverlayController, WorkTimerStore) {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: twDefaults("v0360-tetris-overlay"), workspaceNotifications: nil)
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_000) })
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: twDefaults("v0360-tetris-overlay"), workspaceNotifications: nil)
    return (engine, controller, store)
}

@MainActor
private func twMenuStore() -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: twDefaults("v0360-tetris-menu"), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: twMe)
    store.currentTeamID = "11111111-1111-1111-1111-111111111111"
    store.teamName = "아잉팀"
    store.isMenuPresented = true
    // 팀원 셋 — 본문이 레일보다 길게 시작해야 배너 높이가 창 높이 차로 그대로 드러난다(V0345 와 같은 이유).
    store.teamMembers = (0..<3).map { index in
        TeamMemberStatus(id: "00000000-0000-0000-0000-0000000000c\(index)", name: "멤버\(index)", status: .offWork,
                         updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 3_600)
    }
    return store
}

private func twDefaults(_ name: String) -> UserDefaults {
    let path = CheckTestScratch.suitePath(named: name)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

private enum TWError: Error { case render }

@MainActor
private func twBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw TWError.render }
    return bitmap
}

private func twSource(_ name: String) throws -> String {
    try String(contentsOf: CheckCoreSourceLayout.macDirectory.appendingCheckSourcePath(name), encoding: .utf8)
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다. **안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다.**
private func twStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func twCount(_ needle: String, in source: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var rest = Substring(source)
    while let found = rest.range(of: needle) {
        count += 1
        rest = rest[found.upperBound...]
    }
    return count
}

/// `start` 첫 등장 뒤부터 그 뒤 `end` 첫 등장 전까지.
private func twBetween(_ source: String, _ start: String, _ end: String) -> String? {
    guard let from = source.range(of: start),
          let to = source.range(of: end, range: from.upperBound..<source.endIndex) else { return nil }
    return String(source[from.upperBound..<to.lowerBound])
}

/// `marker`(여는 중괄호로 끝나는 글자) 첫 등장의 중괄호 블록 본문(짝 맞춤).
private func twBlock(_ source: String, after marker: String) -> String? {
    guard let found = source.range(of: marker) else { return nil }
    let open = source.index(before: found.upperBound)
    return twBraceBody(source, open: open)
}

private func twBraceBody(_ source: String, open: String.Index) -> String? {
    var depth = 0
    var index = open
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[source.index(after: open)..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

private func twFunctionBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "func \(name)(") else { return nil }
    guard let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex) else { return nil }
    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[open.upperBound..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}
