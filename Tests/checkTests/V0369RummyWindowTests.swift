import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.69 아잉 큐브 **맥 창** — 레이아웃 항등식 · 끌기 기하(순수) · 창 수명.
//
// 창은 테트리스 창(v0.3.60) 수명 규약을 그대로 쓴다. 여기서 못 박는 것은 **아잉 큐브에서만 틀릴 수 있는 것**들이다:
//   · 고정 1240×700 안에 판(다섯 줄)·랙(두 줄 × 22장)·버튼 열이 넘치지 않고 맞물린다(항등식).
//   · 그리는 자리와 놓는 자리가 한 산식에서 나온다(2판: `V0369RummyV2MatchTests` 가 판 캔버스·받침대 기하를 본다).
//   · 닫기·최소화는 '안 보임', 가림은 '가림' — 서로 다른 통지다. 키를 잃어도 아무것도 하지 않는다.
//
// 창을 실제로 띄우는 검증은 알파 0(`CheckPanelVisibility`) · 직렬이고, 띄운 창은 곧바로 화면 밖으로 옮긴다.
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

// MARK: - 레이아웃 산식(순수)

@MainActor
struct V0369RummyWindowLayoutTests {
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
    // 2판 로비: 탁자 + (받은 초대·공개 방 카드 한 줄 | 없으면 한 줄 안내) = 본문. 카드 셋이 한 줄 폭에 든다.
    for has in [true, false] {
        #expect(L.tableCardHeight(hasJoinables: has) + L.sideSpacing + (has ? L.joinCardHeight : L.joinEmptyHeight) == L.bodyHeight)
    }
    #expect(L.joinCardWidth * 3 + L.sideSpacing * 2 == L.lobbySideWidth)
    #expect(L.tableCardHeight(hasJoinables: true) >= L.tableStageHeight + 26 + 38 + 16 + 8 * 3 + 28,
            "탁자 카드가 머리·탁자 그림·안내·버튼을 다 못 담는다(\(L.tableCardHeight(hasJoinables: true))pt)")
    // 판 세로 예산: 자리 띠 + 판 + 아래 칸(상태 줄 + 랙 카드) = 본문.
    #expect(L.seatBarHeight + L.sectionSpacing + L.boardHeight + L.sectionSpacing + L.bottomHeight == L.bodyHeight)
    #expect(L.bottomHeight == L.statusLineHeight + L.statusSpacing + L.rackCardHeight)
    // 랙 카드: 두 줄 + 여백. 버튼 두 줄도 같은 높이 안에 든다.
    #expect(L.rackAreaHeight == RummyRackGeometry.tile.height * 2 + RummyRackGeometry.rowSpacing)
    #expect(L.actionButtonHeight * 2 + 8 + L.rackCardPadding * 2 <= L.rackCardHeight, "버튼 두 줄이 랙 카드보다 높다")
    // 가로: 랙 창 + 여백 + 간격 + 버튼 열 = 안쪽 폭. 한 줄에 22장(두 줄 44장)이 넘침 없이 보인다.
    #expect(L.rackViewportWidth + L.rackCardPadding * 2 + L.columnSpacing + L.actionColumnWidth == L.innerWidth)
    // 타일 크기(설계서 §5 · 2판 받침대 36×50).
    #expect(RummyTileSize.table.size == CGSize(width: 32, height: 44))
    #expect(RummyTileSize.rack.size == CGSize(width: 36, height: 50))
    // 13" 작업 영역 상한.
    #expect(L.contentSize.width <= 1240 && L.contentSize.height <= 700)
}
}

// 끌기 기하(순수)는 2판 판 화면(자유 배치 캔버스 · 반 칸 받침대)으로 옮겼다 — `V0369RummyV2MatchTests`.

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
struct V0369RummyWindowLifecycleTests {
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
