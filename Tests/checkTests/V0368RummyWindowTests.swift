import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.68 아잉 큐브 **맥 창** — 레이아웃 항등식 · 끌기 기하(순수) · 창 수명.
//
// 창은 테트리스 창(v0.3.60) 수명 규약을 그대로 쓴다. 여기서 못 박는 것은 **아잉 큐브에서만 틀릴 수 있는 것**들이다:
//   · 고정 1240×700 안에 판(다섯 줄)·랙(두 줄 × 22장)·버튼 열이 넘치지 않고 맞물린다(항등식).
//   · 그리는 자리와 놓는 자리가 한 산식에서 나온다(`RummyBoardGeometry`·`RummyRackGeometry`·`RummyDropResolver`).
//   · 닫기·최소화는 '안 보임', 가림은 '가림' — 서로 다른 통지다. 키를 잃어도 아무것도 하지 않는다.
//
// 창을 실제로 띄우는 검증은 알파 0(`CheckPanelVisibility`) · 직렬이고, 띄운 창은 곧바로 화면 밖으로 옮긴다.
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

// MARK: - 레이아웃 산식(순수)

@MainActor
struct V0368RummyWindowLayoutTests {
@Test("아잉 큐브 창 크기 항등식 — 1240×700 고정 · 로비 두 열 · 판 세로 예산 · 랙 줄 폭")
func theRummyWindowLayoutAddsUp() {
    // 없으면: 한 칸 숫자를 바꾼 것이 창을 몇 pt 넘치게 해 아래 버튼 줄이 잘리거나, 로비 두 열이 안쪽 폭과 어긋난다.
    typealias L = RummyWindowLayout
    #expect(L.contentSize == CGSize(width: 1240, height: 700), "설계서 §5 고정 크기가 아니다")
    #expect(CheckRummyWindowController.fixedContentSize == NSSize(width: 1240, height: 700))
    #expect(L.innerWidth + L.contentPadding * 2 == L.contentSize.width)
    #expect(L.contentPadding * 2 + L.headerHeight + L.headerSpacing + L.bodyHeight == L.contentSize.height)
    #expect(L.lobbyListWidth + L.columnSpacing + L.lobbySideWidth == L.innerWidth, "로비 두 열이 안쪽 폭과 안 맞는다")
    #expect(L.lobbyListWidth == 440)
    #expect(L.roomCardHeight + L.invitesHeight + L.recordHeight + L.sideSpacing * 2 == L.bodyHeight)
    #expect(L.invitesHeight >= 56 * 2 + 40, "받은 초대 칸이 두 줄도 못 담는다(\(L.invitesHeight)pt)")
    // 판 세로 예산: 자리 띠 + 판 + 아래 칸(상태 줄 + 랙 카드) = 본문.
    #expect(L.seatBarHeight + L.sectionSpacing + L.boardHeight + L.sectionSpacing + L.bottomHeight == L.bodyHeight)
    #expect(L.bottomHeight == L.statusLineHeight + L.statusSpacing + L.rackCardHeight)
    // 판 안에 세트 다섯 줄이 든다(줄 높이 54 + 간격 10).
    let fiveRows = RummyBoardGeometry.meldHeight * 5 + RummyBoardGeometry.rowSpacing * 4
    #expect(fiveRows <= L.boardHeight - L.boardPadding * 2, "판에 세트 다섯 줄이 안 든다 — \(L.boardHeight)pt")
    // 랙 카드: 두 줄 + 여백. 버튼 두 줄도 같은 높이 안에 든다.
    #expect(L.rackAreaHeight == RummyRackGeometry.tile.height * 2 + RummyRackGeometry.rowSpacing)
    #expect(L.actionButtonHeight * 2 + 8 + L.rackCardPadding * 2 <= L.rackCardHeight, "버튼 두 줄이 랙 카드보다 높다")
    // 가로: 랙 창 + 여백 + 간격 + 버튼 열 = 안쪽 폭. 한 줄에 22장(두 줄 44장)이 넘침 없이 보인다.
    #expect(L.rackViewportWidth + L.rackCardPadding * 2 + L.columnSpacing + L.actionColumnWidth == L.innerWidth)
    #expect(RummyRackGeometry.capacity(viewportWidth: L.rackViewportWidth) >= 22,
            "랙 한 줄이 \(RummyRackGeometry.capacity(viewportWidth: L.rackViewportWidth))장 — 시작 14장 + 뽑기 몇 장에 벌써 스크롤")
    // 타일 크기(설계서 §5).
    #expect(RummyTileSize.table.size == CGSize(width: 32, height: 44))
    #expect(RummyTileSize.rack.size == CGSize(width: 38, height: 52))
    // 13" 작업 영역 상한.
    #expect(L.contentSize.width <= 1240 && L.contentSize.height <= 700)
}
}

// MARK: - 끌기 기하(순수)

@Suite("아잉 큐브 끌기 기하(순수)")
struct V0368RummyWindowGeometryTests {
    let width = RummyWindowLayout.boardContentWidth

    @Test("판 흐름 — 세트는 왼쪽부터 놓이고 폭을 넘으면 다음 줄로 · 새 세트 자리는 마지막 세트 뒤")
    func boardFlowWraps() {
        // 없으면: 세트가 판 오른쪽 밖으로 그려지거나(줄바꿈 없음), 새 세트 점선이 기존 세트와 겹친다.
        let counts = Array(repeating: 13, count: 4)        // 13장 세트 = 452pt → 한 줄에 둘
        let g = RummyBoardGeometry(counts: counts, width: width)
        let threeWide: CGFloat = 110     // 여백 5×2 + 타일 32×3 + 간격 2×2
        #expect(RummyBoardGeometry.meldWidth(3) == threeWide)
        #expect(g.meldFrames.count == 4)
        for frame in g.meldFrames { #expect(frame.maxX <= width, "세트가 판 폭을 넘었다: \(frame)") }
        #expect(g.meldFrames[0].minY == 0 && g.meldFrames[1].minY == 0)
        #expect(g.meldFrames[2].minY == RummyBoardGeometry.meldHeight + RummyBoardGeometry.rowSpacing, "셋째 세트가 다음 줄로 안 갔다")
        #expect(g.meldFrames[2].minX == 0)
        for frame in g.meldFrames { #expect(!frame.intersects(g.newMeldFrame), "새 세트 자리가 세트와 겹친다") }
        #expect(g.contentHeight == g.newMeldFrame.maxY)
        // ★ 기준선: 짧은 세트 넷은 한 줄에 다 든다(같은 산식이 줄바꿈을 '언제나' 하는 것은 아니다).
        let short = RummyBoardGeometry(counts: [3, 3, 3, 3], width: width)
        #expect(Set(short.meldFrames.map(\.minY)) == [0])
    }

    @Test("판 놓기 — 세트 위 = 끼울 자리 · 세트 사이 틈 = 가까운 세트 · 빈 곳 = 새 세트 · 끌던 타일은 빼고 센다")
    func boardHitTesting() {
        // 없으면: 세트 위에 놓은 타일이 새 세트가 되거나, 같은 세트 안에서 한 칸 옮긴 것이 두 칸 옮겨진다.
        let g = RummyBoardGeometry(counts: [3, 4], width: width)
        let first = g.meldFrames[0]
        let tile1 = g.tileFrame(meld: 0, index: 1)
        // 1번 타일 왼쪽 절반 = 1번 자리에 끼움, 오른쪽 절반 = 2번 자리.
        #expect(g.hit(CGPoint(x: tile1.midX - 4, y: tile1.midY)).map { [$0.meld, $0.index] } == [0, 1])
        #expect(g.hit(CGPoint(x: tile1.midX + 4, y: tile1.midY)).map { [$0.meld, $0.index] } == [0, 2])
        // 세트 맨 끝 바로 뒤 틈(간격 절반 안) = 그 세트 끝.
        #expect(g.hit(CGPoint(x: first.maxX + 3, y: first.midY)).map { [$0.meld, $0.index] } == [0, 3])
        // 빈 곳 = nil(→ 새 세트).
        #expect(g.hit(CGPoint(x: width - 4, y: first.midY)) == nil)
        #expect(g.hit(CGPoint(x: 10, y: first.maxY + 120)) == nil)
        // 같은 세트의 0번을 끌어 1번 타일 오른쪽에 놓으면, 0번을 뺀 배열에서 2번 앞 = 1.
        #expect(g.hit(CGPoint(x: tile1.midX + 4, y: tile1.midY), excluding: (0, 0)).map { [$0.meld, $0.index] } == [0, 1])
        // ★ 기준선: 다른 세트의 타일을 뺀다고 이 세트의 번호가 바뀌지 않는다.
        #expect(g.hit(CGPoint(x: tile1.midX + 4, y: tile1.midY), excluding: (1, 0)).map { [$0.meld, $0.index] } == [0, 2])
    }

    @Test("랙 놓기 — 두 줄 · 첫 줄부터 · 보이는 폭을 넘으면 한 줄 칸 수가 늘어난다 · 끌던 타일은 빼고 센다")
    func rackGeometry() {
        // 없으면: 랙 두 번째 줄에 놓은 타일이 첫 줄 끝으로 가거나, 랙 안 재배치가 한 칸씩 밀린다.
        let viewport = RummyWindowLayout.rackViewportWidth
        let cap = RummyRackGeometry.capacity(viewportWidth: viewport)
        let fourteen = RummyRackGeometry(count: 14, viewportWidth: viewport)
        #expect(fourteen.perRow == cap)
        #expect(fourteen.frame(13).minY == 0, "14장이 첫 줄에 다 안 들었다")
        #expect(fourteen.contentWidth <= viewport)
        let full = RummyRackGeometry(count: cap * 2 + 6, viewportWidth: viewport)
        #expect(full.perRow == cap + 3, "넘친 랙이 두 줄에 고르게 안 퍼졌다")
        #expect(full.contentWidth > viewport, "넘친 랙이 가로 스크롤 폭을 안 만든다")
        #expect(full.frame(full.perRow).minY == RummyRackGeometry.tile.height + RummyRackGeometry.rowSpacing)

        let t2 = fourteen.frame(2)
        #expect(fourteen.insertionIndex(at: CGPoint(x: t2.midX - 3, y: t2.midY)) == 2)
        #expect(fourteen.insertionIndex(at: CGPoint(x: t2.midX + 3, y: t2.midY)) == 3)
        // 0번을 끌어 2번 오른쪽에 → 0번을 뺀 배열에서 2.
        #expect(fourteen.insertionIndex(at: CGPoint(x: t2.midX + 3, y: t2.midY), excluding: 0) == 2)
        // 둘째 줄(아직 빈 줄)에 놓으면 끝(14).
        #expect(fourteen.insertionIndex(at: CGPoint(x: 5, y: RummyRackGeometry.tile.height + 20)) == 14)
        // ★ 기준선: 둘째 줄이 찬 랙에서는 같은 자리가 둘째 줄 첫 칸이다.
        #expect(full.insertionIndex(at: CGPoint(x: 5, y: RummyRackGeometry.tile.height + 20)) == full.perRow)
    }

    @Test("놓을 자리 판정 — 랙 · 세트 · 새 세트 · 내 차례가 아니면 랙만 · 판 밖은 없음")
    func dropResolver() {
        // 없으면: 남의 차례에 판에 타일을 놓는 요청이 나가거나(서버가 거절하지만 화면이 흔들린다), 랙 위 놓기가 판으로 간다.
        let zones = RummyMatchZones.standard
        let board = RummyBoardGeometry(counts: [3], width: RummyWindowLayout.boardContentWidth)
        let rack = RummyRackGeometry(count: 14, viewportWidth: RummyWindowLayout.rackViewportWidth)
        let meld = board.meldFrames[0]
        let onMeld = CGPoint(x: zones.boardContentOrigin.x + meld.maxX - 2, y: zones.boardContentOrigin.y + meld.midY)
        let empty = CGPoint(x: zones.boardViewport.maxX - 40, y: zones.boardViewport.maxY - 40)
        let onRack = CGPoint(x: zones.rackContentOrigin.x + 3, y: zones.rackContentOrigin.y + 10)
        let outside = CGPoint(x: zones.boardViewport.midX, y: zones.boardViewport.minY - 30)   // 자리 띠

        #expect(RummyDropResolver.target(at: onMeld, zones: zones, board: board, rack: rack,
                                         source: .rack(index: 4), isMyTurn: true) == .meld(0, index: 3))
        #expect(RummyDropResolver.target(at: empty, zones: zones, board: board, rack: rack,
                                         source: .rack(index: 4), isMyTurn: true) == .newMeld)
        #expect(RummyDropResolver.target(at: onRack, zones: zones, board: board, rack: rack,
                                         source: .meld(0, index: 1), isMyTurn: true) == .rack(index: 0))
        #expect(RummyDropResolver.target(at: outside, zones: zones, board: board, rack: rack,
                                         source: .rack(index: 4), isMyTurn: true) == nil)
        // 내 차례가 아니면 판은 닫히고 랙만 열린다.
        #expect(RummyDropResolver.target(at: onMeld, zones: zones, board: board, rack: rack,
                                         source: .rack(index: 4), isMyTurn: false) == nil)
        #expect(RummyDropResolver.target(at: empty, zones: zones, board: board, rack: rack,
                                         source: .rack(index: 4), isMyTurn: false) == nil)
        #expect(RummyDropResolver.target(at: onRack, zones: zones, board: board, rack: rack,
                                         source: .rack(index: 4), isMyTurn: false) == .rack(index: 0))
    }

    @Test("판 화면 칸 자리 — 레이아웃 상수에서만 나온다(판·랙이 겹치지 않고 본문 안)")
    func zonesComeFromLayout() {
        // 없으면: 그리는 판과 놓는 판의 자리가 두 벌이 되어, 랙 위에 놓은 타일이 판으로 가는 띠가 생긴다.
        let z = RummyMatchZones.standard
        let L = RummyWindowLayout.self
        #expect(z.boardViewport.minY == L.seatBarHeight + L.sectionSpacing)
        #expect(z.boardViewport.height == L.boardHeight)
        #expect(!z.boardViewport.intersects(z.rackViewport))
        #expect(z.rackViewport.maxY == L.bodyHeight - L.rackCardPadding, "랙 창 아래가 랙 카드 여백과 안 맞는다")
        #expect(z.rackViewport.width == L.rackViewportWidth)
        #expect(z.boardContentOrigin == CGPoint(x: L.boardPadding, y: z.boardViewport.minY + L.boardPadding))
    }
}

// MARK: - 창 수명 (직렬 — AppKit 창을 동시에 만들면 SIGSEGV 실측)

@MainActor
private func rwController(_ store: RummyStore) -> CheckRummyWindowController {
    let controller = CheckRummyWindowController()
    controller.configure(store: store, content: { _ in AnyView(Color.clear) })
    return controller
}

@MainActor
private func rwMoveOffscreen(_ controller: CheckRummyWindowController) {
    controller.currentWindow?.setFrameOrigin(NSPoint(x: -6000, y: -6000))
}

@MainActor
@Suite(.serialized)
struct V0368RummyWindowLifecycleTests {
    @Test
    func theWindowIdentityMatchesTheContract() {
        // 없으면: 자동저장 이름이 다른 창과 겹쳐 자리 저장이 조용히 죽거나, 창이 늘어나 끌던 자리가 흔들리거나,
        //        테스트가 사용자 화면에 창을 띄운다.
        #expect(CheckRummyWindowController.windowTitle == "아잉 큐브")
        #expect(CheckRummyWindowController.frameAutosaveName == "check.rummy.window")
        let others = [CheckTetrisDuelWindowController.frameAutosaveName, CheckChessWindowController.frameAutosaveName,
                      CheckMiniGameWindowController.frameAutosaveName]
        #expect(!others.contains(CheckRummyWindowController.frameAutosaveName), "자동저장 이름이 다른 창과 겹친다")
        let window = CheckRummyWindowController.makeWindow()
        defer { window.close() }
        #expect(window.styleMask.contains(.miniaturizable) && window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable), "크기가 바뀌면 판·랙 배치가 창에 딸려 흔들린다")
        #expect(!window.isReleasedWhenClosed)
        #expect(!window.hidesOnDeactivate, "다른 앱을 누르면 창이 사라진다 — 차례 시계는 계속 흐르는데 안 보인다")
        #expect(window.appearance?.name == .darkAqua)
        #expect(window.contentMinSize == CheckRummyWindowController.fixedContentSize)
        #expect(window.contentMaxSize == CheckRummyWindowController.fixedContentSize)
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        #expect(window.identifier?.rawValue == CheckRummyWindowController.frameAutosaveName)
        #expect(window.title == "아잉 큐브")
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 스위트가 사용자 화면에 창을 띄운다")
    }

    @Test
    func showIsLazyIdempotentAndClosingKeepsTheWindow() throws {
        // 없으면: 앱 시작에 창이 미리 만들어지거나(지연 생성), 두 번 열면 창이 둘이 되거나, 닫으면 창이 파괴돼
        //        다시 열 때 자리·내용을 잃는다.
        let controller = rwController(RummyStore())
        defer { controller.discardWindowForTesting() }
        #expect(!controller.hasWindow, "configure 만으로 창이 생겼다 — 지연 생성이 아니다")
        controller.show()
        rwMoveOffscreen(controller)
        let first = try #require(controller.currentWindow)
        #expect(controller.isOpen && controller.frameAutosaveActive, "자동저장 이름이 다른 창과 겹친다")
        controller.show()
        #expect(controller.currentWindow === first, "두 번 열었더니 창이 새로 생겼다")
        #expect(first.contentLayoutRect.size == CheckRummyWindowController.fixedContentSize)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: first))
        #expect(!controller.isOpen)
        #expect(controller.hasWindow && controller.currentWindow === first, "닫았더니 창이 버려졌다")
        controller.show()
        #expect(controller.currentWindow === first && controller.isOpen, "닫은 창을 다시 열지 못했다")
        // 크기 고정 — 늘리려 해도 고정 크기가 돌아온다.
        let asked = controller.windowWillResize(first, to: NSSize(width: 2000, height: 1400))
        #expect(asked == first.frameRect(forContentRect: NSRect(origin: .zero,
                                                               size: CheckRummyWindowController.fixedContentSize)).size)
        #expect(!controller.windowShouldZoom(first, toFrame: .zero))
    }

    @Test
    func closeMinimizeAndOcclusionAreSeparateNotices() throws {
        // 없으면: 가림이 '안 보임'으로 번져 창 안 폴링이 멎거나, 최소화를 되살려도 '보임'이 안 돌아오거나, 닫기 통지가
        //        빠져 닫힌 창을 위해 폴링이 계속 돈다. 키 상실 처리기가 생기면 다른 앱을 잠깐 본 것이 판에 닿는다.
        #expect(!CheckRummyWindowController().responds(to: #selector(NSWindowDelegate.windowDidResignKey(_:))),
                "아잉 큐브 창이 키 상실에 반응한다")
        let controller = rwController(RummyStore())
        defer { controller.discardWindowForTesting() }
        // 열기 전 닫기 통지는 헛돌지 않는다.
        controller.close()
        #expect(controller.lastVisibilityNotice == nil, "열지도 않은 창이 '안 보임'을 보냈다")
        controller.show()
        rwMoveOffscreen(controller)
        let window = try #require(controller.currentWindow)
        #expect(controller.lastVisibilityNotice == true, "열었는데 '보임'을 안 보냈다")

        controller.applyOcclusion(visible: false)
        #expect(controller.lastOcclusionNotice == true, "가림을 안 알렸다")
        #expect(controller.lastVisibilityNotice == true, "가렸다고 '안 보임'까지 됐다")
        controller.applyOcclusion(visible: true)
        #expect(controller.lastOcclusionNotice == false)

        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        #expect(controller.lastVisibilityNotice == false, "최소화가 '안 보임'을 안 알렸다")
        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        #expect(controller.lastVisibilityNotice == true, "최소화를 되살렸는데 '보임'이 안 돌아왔다")

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(controller.lastVisibilityNotice == false, "닫았는데 '안 보임'을 안 보냈다")
        // 닫힌 창의 늦은 가림 통지는 버린다.
        controller.applyOcclusion(visible: false)
        #expect(controller.lastOcclusionNotice == false, "닫힌 창의 가림 통지가 스토어로 갔다")
        // ★ 기준선: 다른 창의 통지는 이 창의 상태를 바꾸지 않는다.
        controller.show()
        let stranger = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: stranger))
        #expect(controller.isOpen && controller.lastVisibilityNotice == true, "남의 창 닫기 통지에 이 창이 닫혔다")
    }

    @Test
    func theRootPanelCarriesTooltipLayerAndAvatarCharacters() throws {
        // 없으면: 새 창 루트에 말풍선 레이어가 없어 [777]·[789] 툴팁이 안 뜨거나, 사람 아바타가 캐릭터 대신 이니셜로 나온다.
        let panel = V0317ShopTests.stripped(try V0317ShopTests.source("RummyPanel.swift"))
        #expect(panel.contains(".checkTooltipLayer()"))
        #expect(panel.contains(".appUserAvatarCharacters(from: safety)"))
        let window = V0317ShopTests.stripped(try V0317ShopTests.source("CheckRummyWindow.swift"))
        #expect(window.contains("RummyPanel(store: rummy, me: me, safety: safety)"), "창이 패널을 이 배선으로 담지 않는다")
        #expect(window.contains("window.alphaValue = CheckPanelVisibility.panelAlpha"))
    }
}
