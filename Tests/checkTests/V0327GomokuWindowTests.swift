import AppKit
import SwiftUI
import Testing
@testable import check

// v0.3.27 1:1 오목 **창**과 받는 쪽 알림(캐릭터 말풍선 큐)·앱 배선.
//
// 창은 미니게임 창의 수명 규약을 그대로 쓰고, 다른 점을 여기서 못 박는다:
//   · 키를 잃거나 닫혀도 **대국이 끝나지 않는다**(판 중단 신호가 아예 없다) — 알리는 것은 표시 상태뿐이다.
//   · 자동저장 이름이 저장소 안 모든 창과 겹치지 않는다 · 크기 1000×700 고정.
//   · CheckApp 배선 네 문(창 · 신청 도착 · 말풍선 클릭 · 로그아웃 닫기)이 실제로 물려 있다(소스 계약).
//
// 창을 실제로 띄우는 검증은 `CheckPanelVisibility` 알파 0 을 지나고, 직렬이다(AppKit 창을 동시에 만들면 SIGSEGV 실측).
// `isVisible` 은 믿지 않는다 — 판정은 '의도'(`isOpen`)와 우리가 만든 창 객체다.

// MARK: - 헬퍼

/// 고정 이름 스위트(UUID 스위트는 실행마다 ~/Library/Preferences 에 plist 를 영구히 쌓는다).
@MainActor
private func gwDefaults() -> UserDefaults {
    let suiteName = "check-v0327-gomoku-window-tests"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private let gwOpponent = GomokuUser(
    id: "00000000-0000-0000-0000-00000000000a", displayName: "민수", avatarURL: nil,
    characterID: "fox", isWorking: true, isCapable: true, inMatch: true
)

@MainActor
private func gwActiveMatch() -> GomokuMatchState {
    var board = GomokuBoard()
    if let h8 = GomokuPoint(notation: "H8") { board[h8] = .black }
    if let i9 = GomokuPoint(notation: "I9") { board[i9] = .white }
    return GomokuMatchState(
        id: "match-1", stake: 5, myColor: .black, opponent: gwOpponent, board: board,
        lastMove: GomokuPoint(notation: "I9"), moveCount: 2, turn: .black,
        deadline: Date().addingTimeInterval(25), isFinished: false, outcome: nil, endReason: nil,
        rubyDelta: nil, blackPassed: false
    )
}

/// 창 계층만 재는 컨트롤러(콘텐츠는 빈 뷰 — 화면 내용 변화에 창 검증이 끌려다니지 않게). 공유 인스턴스가 아니다.
@MainActor
private func gwController(_ store: GomokuStore) -> CheckGomokuWindowController {
    let controller = CheckGomokuWindowController()
    controller.configure(store: store, content: { _ in AnyView(Color.clear) })
    return controller
}

@MainActor
private func gwInvite(id: String, expiresIn seconds: TimeInterval) -> GomokuInvite {
    GomokuInvite(id: id, peer: gwOpponent, stake: 5, expiresAt: Date().addingTimeInterval(seconds))
}

@MainActor
private func gwOverlay() -> (ReactionEngine, CheckOverlayController) {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: gwDefaults(),
        workspaceNotifications: nil
    )
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_000) })
    let controller = CheckOverlayController(
        store: store,
        notificationCenter: NotificationCenter(),
        engine: engine,
        defaults: gwDefaults(),
        workspaceNotifications: nil
    )
    return (engine, controller)
}

// MARK: - 창 수명

@MainActor
@Suite(.serialized)
struct GomokuWindowLifecycleTests {
    @Test
    func gomokuWindowIdentityMatchesTheContract() {
        #expect(CheckGomokuWindowController.windowTitle == "1:1 오목")
        #expect(CheckGomokuWindowController.frameAutosaveName == "check.gomoku.window")
        #expect(CheckGomokuWindowController.frameAutosaveName != CheckMiniGameWindowController.frameAutosaveName)
        #expect(CheckGomokuWindowController.frameAutosaveName != CheckSettingsWindowController.frameAutosaveName)
        #expect(CheckGomokuWindowController.fixedContentSize == NSSize(width: 1000, height: 700))

        let window = CheckGomokuWindowController.makeWindow()
        defer { window.close() }
        #expect(window.title == "1:1 오목")
        #expect(window.styleMask.contains(.titled) && window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(!window.isReleasedWhenClosed, "닫힘에 해제가 딸리면 다음 show() 가 해제된 창을 만진다")
        #expect(!window.hidesOnDeactivate, "다른 앱을 누르면 창이 사라진다 — 대국은 계속되는데 판이 안 보인다")
        #expect(window.appearance?.name == .darkAqua)
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 스위트가 사용자 화면에 창을 띄운다")
    }

    @Test
    func theWindowIsLazyIdempotentAndSurvivesClose() throws {
        let store = GomokuStore()
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }

        #expect(!controller.hasWindow, "배선만으로 창이 만들어졌다")
        #expect(controller.lastVisibilityNotice == nil)

        controller.show()
        #expect(controller.hasWindow && controller.isOpen)
        #expect(controller.frameAutosaveActive, "자동저장 이름이 다른 창과 겹쳐 자리 저장이 죽었다")
        #expect(controller.lastVisibilityNotice == true, "창을 열었는데 스토어에 '보임'을 안 알렸다 — 로비·인박스 재조회가 안 돈다")
        let first = try #require(controller.currentWindow)
        let before = NSApp.map { $0.windows.count }
        controller.show()
        controller.show()
        #expect(NSApp.map { $0.windows.count } == before, "show() 를 더 불렀더니 창이 늘었다(멱등 위반)")
        #expect(controller.currentWindow === first)

        controller.close()
        #expect(!controller.isOpen)
        #expect(controller.hasWindow, "닫기가 창을 파괴했다 — 옮겨 둔 자리가 매번 초기화된다")
        #expect(controller.lastVisibilityNotice == false, "닫았는데 '안 보임'을 안 알렸다 — 안 보이는 창의 폴링이 계속 돈다")
        controller.show()
        #expect(controller.isOpen && controller.lastVisibilityNotice == true, "다시 열었는데 재조회의 문('보임')이 안 열렸다")
    }

    @Test
    func withoutWiringShowDoesNothing() {
        let controller = CheckGomokuWindowController()
        controller.show()
        #expect(!controller.hasWindow)
        #expect(!controller.isOpen)
    }

    @Test
    func losingKeyOrClosingTheWindowDoesNotEndTheMatch() throws {
        // 가장 강한 형태로 못 박는다: 키 상실 처리기 자체가 **없다**.
        #expect(!CheckGomokuWindowController().responds(to: #selector(NSWindowDelegate.windowDidResignKey(_:))),
                "오목 창이 키 상실에 반응한다 — 다른 앱을 잠깐 보는 것이 대국 중단이 되면 안 된다")

        let store = GomokuStore()
        let match = gwActiveMatch()
        store.phase = .playing
        store.match = match
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        let window = try #require(controller.currentWindow)

        // AppKit 이 던지는 그 알림을 그대로 던진다(메서드 직접 호출은 배선이 빠져도 초록이다).
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: window)
        #expect(store.match == match, "키를 잃었더니 대국이 바뀌었다")
        #expect(store.phase == .playing)
        #expect(controller.isOpen, "키를 잃은 것은 닫힌 것이 아니다")
        #expect(controller.lastVisibilityNotice == true, "키를 잃었다고 '안 보임'을 알렸다 — 판을 보고 있는 사람의 동기화가 멎는다")

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(!controller.isOpen)
        #expect(controller.lastVisibilityNotice == false)
        #expect(store.match == match, "창을 닫았더니 대국이 바뀌었다 — 닫기는 기권이 아니다")
        #expect(store.phase == .playing)

        controller.show()
        #expect(controller.lastVisibilityNotice == true)
    }

    @Test
    func minimizingIsHiddenAndRestoringIsShown() throws {
        let store = GomokuStore()
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        let window = try #require(controller.currentWindow)

        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        #expect(controller.lastVisibilityNotice == false, "최소화한 창에서 폴링이 계속 돈다")
        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        #expect(controller.lastVisibilityNotice == true, "되살렸는데 '보임'을 안 알렸다")
    }

    @Test
    func notificationsFromOtherWindowsAreIgnored() throws {
        let store = GomokuStore()
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()

        // 기본값(해제됨)인 창을 close() 하면 지역 변수가 다시 release 되며 프로세스가 죽는다(SIGSEGV 실측) — 끄고 orderOut.
        let stranger = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                styleMask: [.titled], backing: .buffered, defer: true)
        stranger.isReleasedWhenClosed = false
        defer { stranger.orderOut(nil) }
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: stranger))
        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: stranger))
        #expect(controller.isOpen, "남의 창이 닫혔는데 우리 의도가 닫힘이 됐다")
        #expect(controller.lastVisibilityNotice == true, "남의 창 알림이 우리 폴링을 멈췄다")
        #expect(controller.windowWillResize(stranger, to: NSSize(width: 10, height: 10)) == NSSize(width: 10, height: 10))
    }

    @Test
    func theWindowSizeIsFixed() throws {
        let fixed = CheckGomokuWindowController.fixedContentSize
        let bare = CheckGomokuWindowController.makeWindow()
        defer { bare.close() }
        #expect(!bare.styleMask.contains(.resizable), "리사이즈 손잡이가 살아 있다")
        #expect(bare.contentMinSize == fixed && bare.contentMaxSize == fixed)
        #expect(bare.standardWindowButton(.zoomButton)?.isEnabled == false)

        let store = GomokuStore()
        let controller = gwController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        let live = try #require(controller.currentWindow)
        let expected = live.frameRect(forContentRect: NSRect(origin: .zero, size: fixed)).size
        #expect(controller.windowWillResize(live, to: NSSize(width: 1_400, height: 900)) == expected)
        #expect(controller.windowShouldZoom(live, toFrame: NSRect(x: 0, y: 0, width: 1_400, height: 900)) == false)
        #expect(live.frame.size == expected)

        live.setFrame(NSRect(x: live.frame.origin.x, y: live.frame.origin.y, width: 1_200, height: 900), display: false)
        #expect(live.frame.size != expected, "억지 리사이즈가 안 먹었다면 아래 단언은 아무것도 안 잰다")
        controller.close()
        controller.show()
        #expect(live.frame.size == expected, "다시 연 창이 \(live.frame.size) 다(기대 \(expected))")
    }

    @Test
    func theDefaultContentHostsTheGomokuPanel() throws {
        let store = GomokuStore()
        let controller = CheckGomokuWindowController()
        controller.configure(store: store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        let window = try #require(controller.currentWindow)
        #expect(window.contentView is NSHostingView<AnyView>, "기본 배선이 화면을 안 담았다")
    }

    @Test
    func signingOutOrSwitchingAccountsClosesTheWindow() async throws {
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"], defaults: gwDefaults())
        store.session = SupabaseSession(accessToken: "access-a", refreshToken: nil, userID: "user-a")
        let controller = gwController(GomokuStore())
        defer { controller.discardWindowForTesting() }
        controller.show()

        final class Box { var closes = 0 }
        let box = Box()
        GomokuAccountWatcher(userID: { store.session?.userID }) {
            controller.close()
            box.closes += 1
        }.start()

        // 계정 전환.
        store.session = SupabaseSession(accessToken: "access-b", refreshToken: nil, userID: "user-b")
        for _ in 0..<100 where box.closes == 0 { await Task.yield() }
        #expect(box.closes == 1, "계정이 바뀌었는데 창이 안 닫혔다 — 다음 사람이 앞 계정의 판을 본다")
        #expect(!controller.isOpen)

        // 같은 사람의 토큰 갱신은 닫지 않는다.
        controller.show()
        store.session = SupabaseSession(accessToken: "access-b2", refreshToken: nil, userID: "user-b")
        for _ in 0..<20 { await Task.yield() }
        #expect(box.closes == 1, "토큰만 바뀌었는데 창이 닫혔다")
        #expect(controller.isOpen)

        // 로그아웃.
        store.session = nil
        for _ in 0..<100 where box.closes == 1 { await Task.yield() }
        #expect(box.closes == 2, "로그아웃했는데 창이 안 닫혔다")
        #expect(!controller.isOpen)
    }

    // MARK: - 받는 쪽: 캐릭터 말풍선 큐

    @Test
    func anInviteBubbleWaitsBehindAnotherBubbleAndIsNotConsumed() {
        let (engine, controller) = gwOverlay()
        defer {
            controller.clearGomokuInvites()
            controller.updateWorking(false)
        }
        engine.showBubble("다른 안내", seconds: 60)
        controller.enqueueGomokuInvite(gwInvite(id: "invite-1", expiresIn: 50))

        #expect(controller.showNextGomokuInviteBubble() == false)
        #expect(controller.gomokuInviteQueue.map(\.id) == ["invite-1"], "못 띄운 신청을 큐에서 뺐다 — 그 신청은 말풍선 없이 사라진다")
        #expect(engine.greetingText == "다른 안내", "신청 말풍선이 떠 있던 안내를 덮었다")
    }

    @Test
    func anInviteBubbleShowsOnceAndRemembersWhichMatchToOpen() {
        let (engine, controller) = gwOverlay()
        defer {
            controller.clearGomokuInvites()
            controller.updateWorking(false)
        }
        let invite = gwInvite(id: "invite-2", expiresIn: 50)
        controller.enqueueGomokuInvite(invite)
        controller.enqueueGomokuInvite(invite)
        #expect(controller.gomokuInviteQueue.count == 1, "같은 신청이 두 번 들어갔다")

        #expect(controller.showNextGomokuInviteBubble())
        let text = CheckOverlayController.gomokuInviteBubbleText(name: "민수", stake: 5)
        #expect(engine.greetingText == text)
        #expect(controller.gomokuInviteQueue.isEmpty)
        #expect(controller.shownGomokuInvite?.matchID == "invite-2")

        #expect(controller.gomokuInviteBubbleScreenRect() == nil, "열 곳이 배선되기 전인데 클릭 자리가 생겼다")
        controller.onOpenGomoku = { _ in }
        #expect(controller.gomokuInviteBubbleScreenRect() != nil, "배선했는데 말풍선을 누를 자리가 없다")
        engine.greetingText = nil
        #expect(controller.gomokuInviteBubbleScreenRect() == nil, "말풍선이 사라졌는데 클릭 자리가 남았다")
    }

    @Test
    func expiredInvitesAreDroppedInsteadOfShown() {
        let (engine, controller) = gwOverlay()
        defer {
            controller.clearGomokuInvites()
            controller.updateWorking(false)
        }
        controller.enqueueGomokuInvite(gwInvite(id: "old", expiresIn: -1))
        #expect(controller.showNextGomokuInviteBubble() == false)
        #expect(controller.gomokuInviteQueue.isEmpty, "만료된 신청이 큐에 남아 다음 말풍선 자리를 막는다")
        #expect(engine.greetingText == nil)
    }
}

/// 말풍선 문구는 언제나 두 줄 캡슐 안에 들어가고, 메시지 도착 말풍선으로 오인되지 않는다(오인되면 클릭이 대화 패널로 간다).
@Test
func inviteBubbleTextAlwaysFitsTheCapsule() {
    for name in ["민수", "아주아주긴이름의사람", "Christopher Robin", "😀😀😀😀😀😀😀"] {
        for stake in [3, 5, 10] {
            let text = CheckOverlayController.gomokuInviteBubbleText(name: name, stake: stake)
            #expect(OverlayMessageBubble.fitsCapsule(text), "'\(text)' 가 두 줄 캡슐을 넘친다")
            #expect(text.hasSuffix("\(stake)💎"), "'\(text)' 에서 판돈이 빠졌다")
            #expect(!OverlayMessageBubble.isArrival(text), "'\(text)' 가 메시지 도착 말풍선으로 읽힌다")
        }
    }
    #expect(CheckOverlayController.gomokuInviteBubbleText(name: "민수", stake: 5).hasPrefix("민수님"))
}

// MARK: - 레이아웃 표 · 판 좌표

@MainActor
@Test
func gomokuWindowLayoutIsAFixedConstantTable() {
    #expect(GomokuWindowLayout.contentSize == CGSize(width: 1000, height: 700))
    #expect(GomokuWindowLayout.innerSize == CGSize(width: 960, height: 660))
    #expect(GomokuWindowLayout.bodyHeight == 608)
    #expect(GomokuWindowLayout.boardSide == 608)
    #expect(GomokuWindowLayout.sideColumnWidth == 332)
    #expect(GomokuWindowLayout.lobbySideWidth == 400)
    #expect(GomokuWindowLayout.lobbyListWidth + GomokuWindowLayout.columnSpacing + GomokuWindowLayout.lobbySideWidth
            == GomokuWindowLayout.innerSize.width)
    #expect(GomokuWindowLayout.boardSide + GomokuWindowLayout.columnSpacing + GomokuWindowLayout.sideColumnWidth
            == GomokuWindowLayout.innerSize.width)
    // 창 상수와 레이아웃 상수는 한 곳에서 온다.
    #expect(CheckGomokuWindowController.fixedContentSize.width == GomokuWindowLayout.contentSize.width)
    #expect(CheckGomokuWindowController.fixedContentSize.height == GomokuWindowLayout.contentSize.height)
    // 칸이 마우스로 정확히 찍을 만큼 크다.
    #expect(GomokuBoardGeometry(side: GomokuWindowLayout.boardSide).cell >= 30)
}

@Test
func boardGeometryRoundTripsEveryIntersection() throws {
    let board = GomokuBoardGeometry(side: GomokuWindowLayout.boardSide)
    for y in 0..<GomokuBoard.size {
        for x in 0..<GomokuBoard.size {
            let point = try #require(GomokuPoint(x: x, y: y))
            let location = board.location(of: point)
            #expect(board.point(at: location) == point, "\(point.notation) 이 제자리로 안 돌아온다")
            // 반 칸 안쪽으로 비껴 찍어도 같은 교차점이다.
            let nudged = CGPoint(x: location.x + board.cell * 0.4, y: location.y - board.cell * 0.4)
            #expect(board.point(at: nudged) == point)
        }
    }
    // 행 1 이 아래, 행 15 가 위(렌주 표기).
    let h1 = try #require(GomokuPoint(notation: "H1"))
    let h15 = try #require(GomokuPoint(notation: "H15"))
    #expect(board.location(of: h1).y > board.location(of: h15).y)
    // 판 밖(반 칸 넘게)은 교차점이 아니다.
    #expect(board.point(at: CGPoint(x: -board.cell, y: board.inset)) == nil)
    #expect(board.point(at: CGPoint(x: board.side + 4, y: board.side + 4)) == nil)

    // 규칙 예시용 9×9 자르기도 같은 좌표계다.
    let crop = GomokuRuleExample.cropGeometry
    let small = GomokuBoardGeometry(side: 158, lines: crop.lines, originX: crop.originX, originY: crop.originY, insetRatio: 0.07)
    let h8 = try #require(GomokuPoint(notation: "H8"))
    #expect(small.contains(h8))
    #expect(small.point(at: small.location(of: h8)) == h8)
    let a1 = try #require(GomokuPoint(notation: "A1"))
    #expect(!small.contains(a1))
}

// MARK: - 소스 계약(주석을 걷어낸 뒤)

@Test
func appWiresTheGomokuWindowAndItsDoorsAtLaunch() throws {
    let app = gwStripped(try gwSource("CheckApp.swift"))
    #expect(app.contains("CheckGomokuWindowController.shared.configure(store: store.gomoku"), "창 배선이 없다 — 창이 영영 안 뜬다")
    let settings = try #require(gwFunctionBody(app, name: "wireSettingsWindow"))
    #expect(settings.contains("CheckGomokuWindowController.shared.configure(store: store.gomoku"),
            "창 configure 가 다른 창들과 같은 자리(wireSettingsWindow)에 없다")
    #expect(app.contains("gomoku.presentWindow = { CheckGomokuWindowController.shared.show() }"),
            "presentWindow 가 안 물렸다 — 입구·배너·말풍선이 상태만 불러오고 창은 안 뜬다")
    #expect(app.contains("gomoku.onInviteArrived = {") && app.contains("enqueueGomokuInvite(invite)"),
            "받은 신청이 캐릭터 말풍선 큐로 안 간다")
    #expect(app.contains("overlayController?.onOpenGomoku = {") && app.contains("openWindow(focusMatchID: matchID)"),
            "신청 말풍선을 눌러도 아무 일이 없다")
    #expect(app.contains("GomokuAccountWatcher(") && app.contains("CheckGomokuWindowController.shared.close()")
            && app.contains("clearGomokuInvites()"),
            "로그아웃·계정 전환에 창이 안 닫힌다")
    // 말풍선 큐는 오버레이 컨트롤러에 산다 — 그걸 만든 **뒤에** 이어야 첫 신청이 받을 곳이 있다.
    let overlay = try #require(app.range(of: "overlayController = CheckOverlayController("))
    let wire = try #require(app.range(of: "wireGomoku()"))
    #expect(overlay.lowerBound < wire.lowerBound, "오목 배선이 오버레이 컨트롤러보다 먼저다")
}

@Test
func theGomokuWindowNeverEndsTheMatchOnItsOwn() throws {
    let source = gwStripped(try gwSource("CheckGomokuWindow.swift"))
    #expect(!source.contains("InterruptToken"), "창이 판 중단 신호를 올린다")
    #expect(!source.contains("resign("), "창 수명이 기권을 부른다")
    #expect(!source.contains("func windowDidResignKey("), "키 상실 처리기가 생겼다")
    #expect(source.contains("frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)"),
            "자동저장 반환값을 버린다 — 이름이 겹쳐도 아무도 모른다")
    #expect(source.contains("old.setFrameAutosaveName(\"\")"), "재생성 때 자동저장 이름을 안 놓는다")
}

/// 저장소 안 모든 창의 자동저장 이름이 서로 다르다(겹치면 `setFrameAutosaveName` 이 false 를 돌려주고 자리 저장이 조용히 죽는다).
@Test
func everyWindowAutosaveNameIsUnique() throws {
    let directory = gwSourcesDirectory()
    let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
    var names: [String] = []
    for case let file as URL in enumerator where file.pathExtension == "swift" {
        let text = gwStripped(try String(contentsOf: file, encoding: .utf8))
        var rest = Substring(text)
        while let found = rest.range(of: "frameAutosaveName = \"") {
            let after = rest[found.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { break }
            names.append(String(after[..<end]))
            rest = after[end...]
        }
    }
    #expect(names.contains("check.gomoku.window"))
    #expect(names.count >= 3, "창 이름을 못 찾았다(\(names)) — 이 테스트가 아무것도 안 잰다")
    #expect(Set(names).count == names.count, "자동저장 이름이 겹친다: \(names)")
}

// MARK: - 소스 헬퍼(다른 파일의 것은 private 이라 복사 — V0317ShopTests.stripped 와 같은 규칙)

private func gwSourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check", isDirectory: true)
}

private func gwSource(_ name: String) throws -> String {
    try String(contentsOf: gwSourcesDirectory().appendingPathComponent(name), encoding: .utf8)
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다. 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다.
private func gwStripped(_ source: String) -> String {
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

private func gwFunctionBody(_ source: String, name: String) -> String? {
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
