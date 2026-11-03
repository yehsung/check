import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 **창**과 레이아웃 산식(설계서 FLIP/SPEC.md §5.1 · §5.2 · §6.3 U 줄).
//
// 창은 체스 창의 수명 규약을 그대로 쓴다. 여기서 못 박는 것은 **이 창에서만 틀릴 수 있는 것**들이다:
//   · 자동저장 이름이 저장소 안 모든 창과 겹치지 않는다(겹치면 자리 저장이 **조용히** 죽는다).
//   · 판 608 = 8 × 76 · 1240×700 · 오른쪽 열 세로 예산의 합 608 · 로비 세 열.
//   · 판 좌표계에 **방향 뒤집기가 없다**(1행이 위) — 체스 좌표계를 베끼다 내 색을 아래로 돌리면 흑으로 두는 사람의 판이 거꾸로 선다.
//   · 지연 생성 · 멱등 · 닫아도 파괴 안 함 · 닫기와 최소화가 **다른 문**.
//   · 창이 키를 잃거나 닫혀도 판이 끝나지 않는다(키 상실 처리기가 **없다**).
//
// 스토어 몸통은 갈래 C 가 채우는 중이라(C1 뼈대 — `windowDidShow` 등이 비어 있다) 여기서는 **컨트롤러가 무엇을 알렸는가**
// (`lastVisibilityNotice` · `closedNoticeCount` · `lastOcclusionNotice`)를 잰다. 스토어가 그 통지로 무엇을 하는가는 C 의 시험 몫이다.
// AppKit 창을 동시에 만들면 SIGSEGV(실측)라 묶음 전체가 직렬이다.

@MainActor
@Suite(.serialized)
struct V03xxReversiWindowTests {
    // MARK: 레이아웃 산식(순수)

    /// 없으면: 판 한 변을 610 으로 바꿔도(칸 76.25 — 격자에 반 픽셀 이음선) 초록이다.
    @Test
    func theBoardSideDividesIntoEightWholeSquares() {
        let L = ReversiWindowLayout.self
        #expect(L.contentSize == CGSize(width: 1240, height: 700))
        #expect(L.innerSize == CGSize(width: 1200, height: 660))
        #expect(L.bodyHeight == 608)
        #expect(L.boardSide == 608)
        #expect(L.cellSide == 76)
        #expect(L.cellSide * 8 == L.boardSide)
        #expect(L.cellSide == L.cellSide.rounded(), "칸이 \(L.cellSide)pt 라 정수가 아니다 — 격자에 이음선이 생긴다")
        // 체스 창과 **같은 숫자**다(형제 창 — 같은 자리에서 번갈아 쓴다).
        #expect(L.contentSize == ChessWindowLayout.contentSize)
        #expect(L.boardSide == ChessWindowLayout.boardSide)
        #expect(CheckReversiWindowController.fixedContentSize == NSSize(width: 1240, height: 700))
    }

    /// 없으면: 오른쪽 열의 한 칸(카드·동작 줄)을 키워 합이 608 을 넘겨도 초록이다 — 그 넘침은 부모의 `.clipped()` 에 잘린다.
    @Test
    func theColumnBudgetsAddUpExactly() {
        let L = ReversiWindowLayout.self
        // 대국·결과·관전: [판 | 오른쪽 열]
        #expect(L.boardSide + L.columnSpacing + L.sideColumnWidth == L.innerSize.width)
        #expect(L.sideColumnWidth == 572)
        // 오른쪽 열 세로: 카드 84×2 + 판돈·상태 44 + 돌 수·수 기록 322 + 동작 34 + 간격 10×4 = 608.
        #expect(L.playerCardHeight == 84 && L.stakeStatusMinHeight == 44 && L.actionRowHeight == 34)
        #expect(L.matchSideSpacing == 10)
        #expect(L.moveListHeight == 322)
        #expect(L.playerCardHeight * 2 + L.stakeStatusMinHeight + L.moveListHeight + L.actionRowHeight
                + L.matchSideSpacing * 4 == L.bodyHeight)
        // 수 목록 11줄이 262 에 **정확히** 든다(12번째부터 스크롤). 60수 판 = 최대 30줄.
        #expect(L.moveListInnerHeight == 262)
        #expect(L.moveVisibleRows == 11)
        let used = CGFloat(L.moveVisibleRows) * L.moveRowHeight + CGFloat(L.moveVisibleRows - 1) * L.moveRowSpacing
        #expect(used <= L.moveListInnerHeight)
        #expect(used + L.moveRowSpacing + L.moveRowHeight > L.moveListInnerHeight,
                "한 줄 더 넣어도 들어간다 — moveVisibleRows 가 모자라게 세고 있다")
        // 선수 카드 가로: 초상 60+8 · 이름 칸 · 링 54 가 572 안에 선다.
        let cardInner = L.sideColumnWidth - L.cardInsetX * 2
        #expect(L.portraitSide + 8 + 12 + L.nameColumnWidth + 4 + L.clockSide <= cardInner)
        // 판돈 칩 + 상태 상자가 한 줄에 선다(상태 상자 폭 ≥ 200).
        #expect(L.sideColumnWidth - L.stakeChipWidth - L.matchSideSpacing >= 200)
        // 로비: [상대 420 | 순위 340 | 오른쪽 400]
        #expect(L.lobbyUsersWidth + L.columnSpacing + L.lobbyRankWidth == L.lobbyListWidth)
        #expect(L.lobbyListWidth + L.columnSpacing + L.lobbySideWidth == L.innerSize.width)
        #expect(L.lobbyUsersWidth == 420 && L.lobbyRankWidth == 340 && L.lobbySideWidth == 400)
        // 로비 오른쪽 열 세로: 내 전적 72 + 지금 대결 중 + 받은/보낸 신청 + 간격 둘 = 608.
        #expect(L.lobbyRecordHeight == 72)
        #expect(L.lobbyRecordHeight + L.lobbyLiveHeight + L.lobbyInvitesMaxHeight + L.lobbySideSpacing * 2 == L.bodyHeight)
        // 받은/보낸 신청 칸의 예산은 **조각의 합**이다(체스 2026-10-05 — 여백·제목을 빼먹은 200 이 처음부터 모자랐다).
        #expect(L.lobbyInvitesMaxHeight == L.cardPadding * 2 + L.lobbyInvitesTitleHeight + L.lobbyInviteCardHeight
                + L.lobbyOutgoingLineHeight + L.lobbyNoticeLineHeight + L.lobbyInvitesSpacing * 3)
        #expect(L.lobbyInvitesMaxHeight == 232 && L.lobbyLiveHeight == 280)
        // 순위 열: 14행이 548 에 든다.
        #expect(L.rankListHeight == 548 && L.rankVisibleRows == 14)
        // 30초 링 그림(`GomokuClockRing`)은 오목 상수를 읽는다 — 리버시 상수와 갈리면 링이 엉뚱한 초에서 가득 찬다.
        #expect(ReversiText.turnSeconds == GomokuText.turnSeconds)
    }

    /// 없으면: 체스 좌표계(rank 가 위로 자람 · 내 색 아래)를 베껴도 초록이다 — 그러면 d3 를 눌렀는데 d6 에 놓인다.
    @Test
    func theBoardGeometryHasNoFlipAndRowOneIsOnTop() throws {
        let g = ReversiBoardGeometry(side: ReversiWindowLayout.boardSide)
        var seen = Set<String>()
        for idx in 0..<64 {
            let box = g.rect(idx: idx)
            #expect(box.width == ReversiWindowLayout.cellSide && box.height == ReversiWindowLayout.cellSide)
            #expect(seen.insert("\(box.minX),\(box.minY)").inserted, "idx \(idx) 가 다른 칸과 같은 자리다")
            for probe in [CGPoint(x: box.midX, y: box.midY), CGPoint(x: box.minX + 1, y: box.minY + 1),
                          CGPoint(x: box.maxX - 1, y: box.maxY - 1)] {
                #expect(g.idx(at: probe) == idx, "idx \(idx): \(probe) 가 \(String(describing: g.idx(at: probe))) 로 떨어진다")
            }
        }
        #expect(seen.count == 64)
        // 판 밖은 아무 칸도 아니다(반 칸 관용 없음).
        #expect(g.idx(at: CGPoint(x: -1, y: 10)) == nil)
        #expect(g.idx(at: CGPoint(x: 10, y: -1)) == nil)
        #expect(g.idx(at: CGPoint(x: g.side, y: 10)) == nil)
        #expect(g.idx(at: CGPoint(x: 10, y: g.side)) == nil)
        #expect(g.idx(at: CGPoint(x: CGFloat.nan, y: 10)) == nil)
        // ★ 방향: a1(idx 0) 은 왼쪽 **위**, h1(7) 은 오른쪽 위, a8(56) 은 왼쪽 아래(V-01 idx = row*8 + col).
        #expect(g.rect(idx: 0) == CGRect(x: 0, y: 0, width: 76, height: 76))
        #expect(g.rect(idx: 7) == CGRect(x: 532, y: 0, width: 76, height: 76))
        #expect(g.rect(idx: 56) == CGRect(x: 0, y: 532, width: 76, height: 76))
        // d3 = idx 19 = (col 3, row 2) — 화면 표기와 와이어 idx 가 같은 칸을 가리킨다.
        let d3 = try #require(ReversiPoint(coord: "d3"))
        #expect(d3.idx == 19)
        #expect(g.rect(idx: d3.idx) == CGRect(x: 228, y: 152, width: 76, height: 76))
        // 기준선이 갈린다: 체스 좌표계(백 기준)는 1행을 **아래**에 그린다.
        let chess = ChessBoardGeometry(side: 608, orientation: .white)
        let chessA1 = try #require(ChessSquare("a1"))
        #expect(chess.rect(of: chessA1) != g.rect(idx: 0), "리버시 판이 체스처럼 1행을 아래에 그린다")
    }

    // MARK: 창 정체성

    /// 없으면: 자동저장 이름을 체스 것 그대로 베껴도 초록이다 — 두 창이 같은 자리를 다투고 하나는 자리 저장이 죽는다.
    @Test
    func reversiWindowIdentityMatchesTheContract() {
        #expect(CheckReversiWindowController.windowTitle == "아잉 뒤집기")
        #expect(CheckReversiWindowController.windowTitle == ReversiNoticeText.gameName)
        #expect(CheckReversiWindowController.frameAutosaveName == "check.reversi.window")
        for other in [CheckChessWindowController.frameAutosaveName, CheckGomokuWindowController.frameAutosaveName,
                      CheckMiniGameWindowController.frameAutosaveName, CheckSettingsWindowController.frameAutosaveName,
                      CheckRummyWindowController.frameAutosaveName] {
            #expect(CheckReversiWindowController.frameAutosaveName != other)
        }

        let window = CheckReversiWindowController.makeWindow()
        defer { window.close() }
        #expect(window.title == "아잉 뒤집기")
        #expect(window.styleMask.contains(.titled) && window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(!window.styleMask.contains(.resizable), "크기가 바뀌면 판 좌표계가 창에 딸려 흔들린다")
        #expect(!window.isReleasedWhenClosed, "닫힘에 해제가 딸리면 다음 show() 가 해제된 창을 만진다")
        #expect(!window.hidesOnDeactivate, "다른 앱을 누르면 창이 사라진다 — 판은 계속되는데 판이 안 보인다")
        #expect(window.appearance?.name == .darkAqua)
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        #expect(window.contentMinSize == CheckReversiWindowController.fixedContentSize)
        #expect(window.contentMaxSize == CheckReversiWindowController.fixedContentSize)
        #expect(window.identifier?.rawValue == CheckReversiWindowController.frameAutosaveName)
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 묶음이 사용자 화면에 창을 띄운다")
    }

    // MARK: 창 수명

    /// 없으면: `show()` 가 부를 때마다 창을 새로 만들어도(멱등 위반) · 닫기가 창을 파괴해도 초록이다.
    @Test
    func theWindowIsLazyIdempotentAndSurvivesClose() throws {
        let controller = rvController(ReversiStore())
        defer { controller.discardWindowForTesting() }

        #expect(!controller.hasWindow, "배선만으로 창이 만들어졌다")
        #expect(controller.lastVisibilityNotice == nil)

        controller.show()
        #expect(controller.hasWindow && controller.isOpen)
        #expect(controller.frameAutosaveActive, "자동저장 이름이 다른 창과 겹쳐 자리 저장이 죽었다")
        #expect(controller.lastVisibilityNotice == true, "창을 열었는데 스토어에 '보임'을 안 알렸다 — 로비 재조회가 안 돈다")
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
        #expect(controller.closedNoticeCount == 1, "프로그램 닫기(로그아웃)가 '닫혔다'를 안 알린다")
        controller.show()
        #expect(controller.isOpen && controller.lastVisibilityNotice == true, "다시 열었는데 재조회의 문이 안 열렸다")
        #expect(controller.currentWindow === first, "다시 열었더니 다른 창이다 — 닫기가 창을 버렸다")
    }

    @Test
    func withoutWiringShowDoesNothing() {
        let controller = CheckReversiWindowController()
        controller.show()
        #expect(!controller.hasWindow)
        #expect(!controller.isOpen)
        #expect(controller.lastVisibilityNotice == nil)
    }

    /// 없으면: 키 상실 처리기(`windowDidResignKey`)가 판을 끊어도 초록이다 — 다른 앱을 잠깐 본 것이 루비가 걸린 판의 기권이 된다.
    @Test
    func losingKeyOrClosingTheWindowDoesNotEndTheMatch() throws {
        #expect(!CheckReversiWindowController().responds(to: #selector(NSWindowDelegate.windowDidResignKey(_:))),
                "창이 키 상실에 반응한다 — 다른 앱을 잠깐 보는 것이 판 중단이 되면 안 된다")

        let store = ReversiStore()
        let match = ReversiMatchState(id: "m-key", stake: 5, myColor: .black,
                                      opponent: ReversiUser(id: "u-key", displayName: "민수"),
                                      legalMoves: [19, 26, 37, 44])
        store.phase = .playing
        store.match = match
        let controller = rvController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        let window = try #require(controller.currentWindow)

        // AppKit 이 던지는 그 알림을 그대로 던진다(메서드 직접 호출은 배선이 빠져도 초록이다).
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didResignMainNotification, object: window)
        #expect(store.match == match, "키를 잃었더니 판이 바뀌었다")
        #expect(store.phase == .playing)
        #expect(controller.isOpen, "키를 잃은 것은 닫힌 것이 아니다")
        #expect(controller.lastVisibilityNotice == true, "키를 잃었다고 '안 보임'을 알렸다 — 판을 보는 사람의 동기화가 멎는다")
        #expect(controller.closedNoticeCount == 0)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(!controller.isOpen)
        #expect(controller.lastVisibilityNotice == false)
        #expect(controller.closedNoticeCount == 1)
        #expect(store.match == match, "창을 닫았더니 판이 바뀌었다 — 닫기는 기권이 아니다")
        #expect(store.phase == .playing)
    }

    /// ★ **최소화는 '안 보임'만, 닫기는 '안 보임' + '닫혔다'.** 두 통지를 합치면 최소화가 관전을 죽인다.
    /// 없으면: `notifyClosed()` 를 `windowDidMiniaturize`(또는 `notifyVisibility`) 안에 넣어도 초록이다.
    @Test
    func minimizingIsNotClosing() throws {
        let controller = rvController(ReversiStore())
        defer { controller.discardWindowForTesting() }
        controller.show()
        let window = try #require(controller.currentWindow)

        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        #expect(controller.lastVisibilityNotice == false, "최소화가 '안 보임'을 안 알렸다 — 치운 창의 폴링이 계속 돈다")
        #expect(controller.closedNoticeCount == 0, "최소화만 했는데 '닫혔다'를 알렸다 — 되살리면 관전이 로비로 떨어진다")
        #expect(controller.isOpen, "최소화는 닫기가 아니다")

        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        #expect(controller.lastVisibilityNotice == true, "되살렸는데 '보임'을 안 알렸다")

        // 기준선이 갈린다: 같은 창, 다른 통지 → '닫혔다' 한 번.
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(controller.closedNoticeCount == 1, "빨간 점 닫기가 '닫혔다'를 안 알린다 — 관전이 닫기 뒤에도 남는다")
        // 다른 창의 통지는 무시한다.
        let stranger = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 10, height: 10),
                                styleMask: [.titled], backing: .buffered, defer: false)
        stranger.isReleasedWhenClosed = false
        defer { stranger.close() }
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: stranger))
        #expect(controller.closedNoticeCount == 1, "남의 창 닫기 통지에 반응했다")
    }

    /// 창이 닫힘을 **사람이 닫았다(true) / 프로그램이 닫았다(false)** 로 가려 알린다(가지 `fix/window-return-1103` b63734bd 의
    /// 오목·체스·테트리스 창과 같은 칸 — 합칠 때 `CheckApp` 이 이 칸을 `duelWindowDidClose(.reversi, byUser:)` 로 잇는다).
    /// 없으면: 빨간 점·⌘W 와 로그아웃 닫기를 같은 값으로 알려도(둘 다 true — 로그아웃·계정 전환마다 미니게임 창이 튀어나온다)
    /// 아예 안 알려도(사람이 닫아도 미니게임 창이 안 선다) · 최소화나 못 뜬 창 재생성을 닫기로 알려도 초록이다.
    @Test
    func closingTellsAUserCloseFromAProgramClose() throws {
        var heard: [Bool] = []
        let controller = rvController(ReversiStore())
        controller.onClosed = { heard.append($0) }
        defer { controller.discardWindowForTesting() }
        controller.show()
        let window = try #require(controller.currentWindow)

        // 사람: 빨간 점 · ⌘W — AppKit 이 창을 닫으며 대리자에게 windowWillClose 를 보낸다(메서드를 직접 부르지 않는다 —
        // 대리자 배선이 빠져도 초록이 되지 않게).
        window.close()
        #expect(heard == [true], "사람이 닫았는데 '사람'으로 안 알렸다: \(heard)")
        #expect(!controller.isOpen && controller.closedNoticeCount == 1)

        // 프로그램: 로그아웃 · 계정 전환의 close()(orderOut — windowWillClose 를 안 보낸다).
        controller.show()
        controller.close()
        #expect(heard == [true, false], "로그아웃 닫기를 '프로그램'으로 안 알렸다: \(heard)")

        // 기준선: 닫기가 아닌 것들은 울리지 않는다 — 최소화 · 남의 창 닫기 통지 · 못 뜬 창의 재생성(대리자를 떼고 닫는다).
        controller.show()
        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        let stranger = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 10, height: 10),
                                styleMask: [.titled], backing: .buffered, defer: false)
        stranger.isReleasedWhenClosed = false
        defer { stranger.close() }
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: stranger))
        controller.rebuildStuckWindow()
        #expect(controller.isOpen && controller.stuckWindowRebuilds == 1, "전제: 재생성이 돌아 창이 다시 섰다")
        #expect(heard == [true, false], "닫기가 아닌 통지에 울렸다: \(heard)")
    }

    /// 가림은 **폴링만** 멈춘다 — '안 보임'으로 번지지 않는다. 닫힌 창의 가림 통지는 무시한다.
    @Test
    func occlusionStopsPollingButNotVisibility() throws {
        let controller = rvController(ReversiStore())
        defer { controller.discardWindowForTesting() }
        controller.applyOcclusion(visible: false)
        #expect(controller.lastOcclusionNotice == nil, "열지도 않은 창의 가림 통지를 받았다")
        controller.show()
        controller.applyOcclusion(visible: false)
        #expect(controller.lastOcclusionNotice == false)
        #expect(controller.lastVisibilityNotice == true, "가려졌다고 '안 보임'까지 됐다 — 보이는 창의 시계가 멈춘다")
        controller.applyOcclusion(visible: true)
        #expect(controller.lastOcclusionNotice == true)
    }

    // MARK: 소스 계약

    /// 닫기와 '안 보임'은 **다른 문**이다(위 결과 시험의 짝 — 여기서는 두 문이 섞이지 않았는가를 본다).
    @Test
    func closingIsItsOwnDoorNotJustInvisibility() throws {
        let source = rvStripped(try rvSource("CheckReversiWindow.swift"))
        let willClose = try #require(rvFunctionBody(source, name: "windowWillClose"))
        let programmatic = try #require(rvFunctionBody(source, name: "close"))
        let visibility = try #require(rvFunctionBody(source, name: "notifyVisibility"))
        let miniaturize = try #require(rvFunctionBody(source, name: "windowDidMiniaturize"))
        let closed = try #require(rvFunctionBody(source, name: "notifyClosed"))
        #expect(willClose.contains("notifyClosed()"))
        #expect(programmatic.contains("notifyClosed()"), "프로그램 닫기가 '닫혔다'를 안 알린다 — orderOut 은 windowWillClose 를 안 보낸다")
        #expect(closed.contains("store.windowDidClose()"), "notifyClosed 가 스토어 문을 안 부른다")
        #expect(!visibility.contains("notifyClosed") && !visibility.contains("windowDidClose"))
        #expect(!miniaturize.contains("notifyClosed") && !miniaturize.contains("windowDidClose"))
        #expect(miniaturize.contains("notifyVisibility(false)"))
    }

    @Test
    func theWindowNeverEndsTheMatchOnItsOwn() throws {
        let source = rvStripped(try rvSource("CheckReversiWindow.swift"))
        #expect(!source.contains("resign("), "창 수명이 기권을 부른다")
        #expect(!source.contains("func windowDidResignKey("), "키 상실 처리기가 생겼다")
        #expect(source.contains("frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)"),
                "자동저장 반환값을 버린다 — 이름이 겹쳐도 아무도 모른다")
        #expect(source.contains("old.setFrameAutosaveName(\"\")"), "재생성 때 자동저장 이름을 안 놓는다")
        let occlusion = try #require(rvFunctionBody(source, name: "windowDidChangeOcclusionState"))
        let apply = try #require(rvFunctionBody(source, name: "applyOcclusion"))
        #expect(occlusion.contains("occlusionState.contains(.visible)") && occlusion.contains("applyOcclusion("))
        #expect(apply.contains("windowOcclusionDidChange(visible: visible)"))
        #expect(!apply.contains("windowDidHide") && !apply.contains("notifyVisibility"), "가림 통지가 '안 보임'으로 번졌다")
    }

    /// 창 루트의 **두 줄** — 말풍선 툴팁 레이어와 남의 캐릭터 한 표. 지우면 툴팁이 안 뜨고 남의 얼굴이 전부 이니셜이 된다.
    @Test
    func theRootCarriesTheTooltipLayerAndTheCharacterTable() throws {
        let panel = rvStripped(try rvSource("ReversiPanel.swift"))
        #expect(panel.contains("height: ReversiWindowLayout.contentSize.height, alignment: .topLeading) "
                               + ".background(CheckTheme.background) .foregroundStyle(CheckTheme.primaryText) "
                               + ".checkTooltipLayer() .appUserAvatarCharacters(from: safety)"),
                "창 루트의 툴팁 레이어·캐릭터 표 두 줄이 그 자리에 없다")
        #expect(rvCount(".checkTooltipLayer()", in: panel) == 1)
        #expect(rvCount(".appUserAvatarCharacters(from:", in: panel) == 1)
        // 레이어가 **실제로 쓰이는** 자리(툴팁)가 창 안에 있다.
        var tooltips = 0
        for file in ["ReversiPanel.swift", "ReversiPanelLobby.swift", "ReversiPanelBoard.swift", "ReversiPanelMatch.swift"] {
            tooltips += rvCount(".checkTooltip(", in: rvStripped(try rvSource(file)))
        }
        #expect(tooltips >= 3, "창에 말풍선 툴팁을 붙인 자리가 \(tooltips)곳뿐이다 — 레이어가 장식이다")
        #expect(rvStripped(try rvSource("CheckReversiWindow.swift"))
            .contains("ReversiPanel(store: reversi, me: me, safety: safety)"))
    }

    /// 화면 파일에 **렌더 감지기를 눈멀게 하는 부품**이 없다: `.shadow`(첫 두 장이 다르다) · Picker/Menu/TextField(노란 상자 · 픽셀 0).
    /// 없으면: 판에 `.shadow` 를 달아도 다른 시험이 순서에 따라 깜빡일 뿐 이 자리를 짚지 못한다.
    @Test
    func theScreensAvoidRenderBlindingParts() throws {
        for file in ["ReversiPanel.swift", "ReversiPanelLobby.swift", "ReversiPanelBoard.swift", "ReversiPanelMatch.swift",
                     "ReversiPanelRules.swift", "ReversiPanelBanner.swift", "CheckReversiWindow.swift"] {
            let code = rvStripped(try rvSource(file))
            for banned in [".shadow(", "Picker(", "Menu(", "TextField(", "withAnimation("] {
                #expect(!code.contains(banned), "\(file) 에 \(banned) 가 있다")
            }
        }
    }

    /// 저장소 안 모든 창의 자동저장 이름이 서로 다르다(겹치면 자리 저장이 **조용히** 죽는다).
    @Test
    func everyWindowAutosaveNameIsStillUniqueAfterAddingReversi() throws {
        let directory = rvSourcesDirectory()
        let enumerator = try #require(FileManager.default.checkSourcesEnumerator(at: directory, includingPropertiesForKeys: nil))
        var names: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = rvStripped(try String(contentsOf: file, encoding: .utf8))
            var rest = Substring(text)
            while let found = rest.range(of: "frameAutosaveName = \"") {
                let after = rest[found.upperBound...]
                guard let end = after.firstIndex(of: "\"") else { break }
                names.append(String(after[..<end]))
                rest = after[end...]
            }
        }
        #expect(names.contains("check.reversi.window"))
        #expect(names.contains("check.chess.window"))
        #expect(names.count >= 5, "창 이름을 못 찾았다(\(names)) — 이 시험이 아무것도 안 잰다")
        #expect(Set(names).count == names.count, "자동저장 이름이 겹친다: \(names)")
    }
}

// MARK: - 헬퍼(다른 파일의 것은 private 이라 복사 — 파일마다 private 복사가 관례다)

/// 창 계층만 재는 컨트롤러(콘텐츠는 빈 뷰). 공유 인스턴스가 아니다.
@MainActor
private func rvController(_ store: ReversiStore) -> CheckReversiWindowController {
    let controller = CheckReversiWindowController()
    controller.configure(store: store, content: { _ in AnyView(Color.clear) })
    return controller
}

private func rvSourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check", isDirectory: true)
}

private func rvSource(_ name: String) throws -> String {
    try String(contentsOf: rvSourcesDirectory().appendingCheckSourcePath(name), encoding: .utf8)
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다. **안 걷어내면 설명을 지워야만 초록이 되는 시험이 된다.**
private func rvStripped(_ source: String) -> String {
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

private func rvCount(_ needle: String, in source: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var rest = Substring(source)
    while let found = rest.range(of: needle) {
        count += 1
        rest = rest[found.upperBound...]
    }
    return count
}

private func rvFunctionBody(_ source: String, name: String) -> String? {
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
