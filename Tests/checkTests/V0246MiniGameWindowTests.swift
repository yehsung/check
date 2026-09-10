import AppKit
import SwiftUI
import Testing
@testable import check

// v0.2.46 미니게임 **창**(팝오버 패널에서 이사). 설정 창(CheckSettingsWindowController)과 같은 수명 규약을 쓰고,
// 다른 점만 여기서 못 박는다: 제목·자동저장 이름·기본/최소 크기, 창이 키를 잃거나 닫히면 진행 중인 판이 끝난다(interruptToken),
// 그리고 창 크기 → (캔버스, 무스크롤 행수) 레이아웃 표.
//
// 창을 실제로 띄우는 테스트는 `CheckPanelVisibility.isRunningTests` 알파 0 을 지난다(사용자 화면 오염 금지 —
// 이 저장소는 "테스트가 사장님 데스크톱을 도배했다"를 이미 한 번 겪었다). `isVisible` 은 믿지 않는다(v0.2.27 에 거짓말했다):
// 판정은 언제나 '의도'(`isOpen`)와 우리가 만든 창 객체다.

// MARK: - 헬퍼

@MainActor
private func mgwDefaults() -> UserDefaults {
    let suiteName = "v0246-mg-window-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func mgwStore() -> WorkTimerStore {
    WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "anon"], defaults: mgwDefaults())
}

/// 배선까지 끝낸 컨트롤러(공유 인스턴스가 아니다 — 전역을 오염시키지 않고 창 하나를 잰다).
@MainActor
private func mgwController(_ store: WorkTimerStore) -> CheckMiniGameWindowController {
    let controller = CheckMiniGameWindowController()
    controller.configure(store: store)
    return controller
}


/// 창을 실제로 만드는 검증은 **직렬**이다. AppKit 창을 여러 테스트가 동시에 만들고 닫으면 프로세스가 죽는다(SIGSEGV 실측).
@MainActor
@Suite(.serialized)
struct MiniGameWindowLifecycleTests {
    // MARK: - 창 정체성

    @Test
    func miniGameWindowIdentityMatchesTheContract() {
        #expect(CheckMiniGameWindowController.windowTitle == "미니게임")
        #expect(CheckMiniGameWindowController.frameAutosaveName == "check.miniGameWindow")
        // v0.2.48: 620×420 → 700×470. 넓힌 것은 크롬뿐이고 캔버스는 344×356 그대로다(아래 레이아웃 표).
        #expect(CheckMiniGameWindowController.fixedContentSize == NSSize(width: 700, height: 470))

        let window = CheckMiniGameWindowController.makeWindow()
        defer { window.close() }
        #expect(window.title == "미니게임")
        #expect(window.styleMask.contains(.titled) && window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable), "치워 뒀다 다시 열 수 있어야 한다")
        #expect(!window.isReleasedWhenClosed, "닫힘에 해제가 딸리면 다음 show() 가 해제된 창을 만진다")
        #expect(window.appearance?.name == .darkAqua, "앱 전체가 다크다 — 시스템 외관을 따르면 흰 배경에 흰 글자가 난다")
        // 테스트에서는 알파 0(사용자 화면 오염 금지). 프로덕션은 1.
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 스위트가 사용자 화면에 창을 띄운다")
    }

    // MARK: - 크기 고정(모두 같은 캔버스에서 겨룬다)

    @Test
    func theWindowCannotBeResizedSoEveryoneCompetesOnTheSameCanvas() throws {
        // 창을 키우면 캔버스가 커져 게임이 쉬워진다(플래피는 반응할 여유가, 타이밍 바는 목표 구간 픽셀이 늘어난다).
        // 순위표가 걸려 있으므로 크기는 고정이다 — 사용자 결정 2026-09-08.
        let fixed = CheckMiniGameWindowController.fixedContentSize
        let window = CheckMiniGameWindowController.makeWindow()
        defer { window.close() }
        #expect(!window.styleMask.contains(.resizable), "리사이즈 손잡이가 살아 있다")
        #expect(window.contentMinSize == fixed && window.contentMaxSize == fixed, "최소·최대가 고정값이 아니다")
        #expect(window.standardWindowButton(.zoomButton)?.isEnabled == false, "초록(확대) 버튼이 눌린다")

        // 델리게이트 문 둘: 프로그램적 리사이즈와 확대 요청.
        let store = mgwStore()
        let controller = mgwController(store)
        defer { controller.close() }
        controller.show()
        let live = try #require(controller.currentWindow)
        let expected = live.frameRect(forContentRect: NSRect(origin: .zero, size: fixed)).size
        #expect(controller.windowWillResize(live, to: NSSize(width: 1_200, height: 900)) == expected, "리사이즈 요청이 통과했다")
        #expect(controller.windowShouldZoom(live, toFrame: NSRect(x: 0, y: 0, width: 1_200, height: 900)) == false)
        #expect(live.frame.size == expected, "열린 창의 크기가 고정값이 아니다")
    }

    @Test
    func aRestoredFrameWithADifferentSizeSnapsBackToTheFixedSize() throws {
        // 옛 버전(리사이즈 가능하던 판)이 남긴 자동저장 프레임이나 다른 화면 배율에서 온 값이 복원돼도
        // 크기는 고정으로 되돌아와야 한다 — 안 그러면 그 맥만 더 큰(=더 쉬운) 캔버스로 논다.
        let store = mgwStore()
        let controller = mgwController(store)
        defer { controller.close() }
        controller.show()
        let window = try #require(controller.currentWindow)
        let fixed = window.frameRect(forContentRect: NSRect(origin: .zero, size: CheckMiniGameWindowController.fixedContentSize)).size
        // 창 서버를 거치지 않고 크기만 억지로 바꾼다(옛 자동저장 프레임 복원·화면 배율 변화와 같은 모양).
        window.setFrame(NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: 1_000, height: 800), display: false)
        #expect(window.frame.size != fixed, "억지 리사이즈 자체가 안 먹었다면 이 테스트는 아무것도 안 재고 있다")
        controller.close()
        controller.show()
        #expect(window.frame.size == fixed, "다시 연 창이 \(window.frame.size) 다(기대 \(fixed)) — 그 맥만 더 쉬운 캔버스가 된다")
    }

    // MARK: - 수명(지연 생성 · 멱등 · 닫았다 다시)

    @Test
    func miniGameWindowIsLazyIdempotentAndReopensAfterClose() {
        let store = mgwStore()
        let controller = mgwController(store)
        defer { controller.close() }

        #expect(!controller.hasWindow, "배선만으로 창이 만들어졌다 — 게임을 한 번도 안 여는 실행이 대부분이다")
        #expect(!controller.isOpen)

        controller.show()
        #expect(controller.hasWindow && controller.isOpen)
        let first = controller.currentWindow
        #expect(first != nil)
        // 창 개수는 다른 스위트의 창까지 세므로(테스트는 병렬이다) **증가분**으로 본다.
        let before = NSApp.windows.count
        controller.show()
        controller.show()
        #expect(NSApp.windows.count == before, "show() 를 더 불렀더니 창이 늘었다(멱등 위반)")
        #expect(controller.currentWindow === first, "두 번째 show() 가 다른 창을 만들었다")

        controller.close()
        #expect(!controller.isOpen, "close() 뒤에도 의도가 열림이면 다음 show() 가 '이미 열렸다'고 착각한다")
        #expect(controller.hasWindow, "닫기가 창을 파괴했다 — 자리·크기가 매번 초기화된다")
        controller.show()
        #expect(controller.isOpen)
    }

    @Test
    func miniGameWindowWithoutWiringDoesNothing() {
        let controller = CheckMiniGameWindowController()
        controller.show()
        #expect(!controller.hasWindow, "배선 전 show() 가 담을 것 없는 창을 만들었다")
        #expect(!controller.isOpen)
    }

    // MARK: - 창이 게임을 멈춘다

    @Test
    func closingTheWindowEndsTheRoundAndClearsTheEntryButtonHighlight() throws {
        let store = mgwStore()
        let controller = mgwController(store)
        defer { controller.close() }
        store.openMiniGameWindow()
        controller.show()
        let window = try #require(controller.currentWindow)
        let token = store.miniGameInterruptToken
        #expect(store.isMiniGamePanelVisible)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(store.miniGameInterruptToken == token + 1, "창을 닫아도 토큰이 안 올라 게임이 60Hz 로 계속 돈다")
        #expect(!store.isMiniGamePanelVisible, "창을 닫았는데 진입 버튼이 켜진 채로 남았다")
        #expect(!controller.isOpen)
    }

    @Test
    func losingKeyEndsTheRoundButKeepsTheWindowOpen() throws {
        let store = mgwStore()
        let controller = mgwController(store)
        defer { controller.close() }
        store.openMiniGameWindow()
        controller.show()
        let window = try #require(controller.currentWindow)
        let token = store.miniGameInterruptToken

        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        #expect(store.miniGameInterruptToken == token + 1, "다른 창으로 갔는데 게임이 계속 돈다(유휴 0% 위반)")
        #expect(store.isMiniGamePanelVisible, "키를 잃은 것은 닫힌 것이 아니다 — 창은 그대로 떠 있다")
        #expect(controller.isOpen)

        // 남의 창 알림은 무시한다(다른 창을 클릭할 때마다 토큰이 오르면 안 된다).
        // ★ isReleasedWhenClosed 를 끄고 orderOut 으로 치운다 — 기본값(true)인 창을 close() 하면 그 자리에서
        //   해제되고, 지역 변수가 다시 release 되면서 프로세스가 죽는다(SIGSEGV 실측).
        let stranger = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                styleMask: [.titled], backing: .buffered, defer: true)
        stranger.isReleasedWhenClosed = false
        defer { stranger.orderOut(nil) }
        let after = store.miniGameInterruptToken
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: stranger))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: stranger))
        #expect(store.miniGameInterruptToken == after, "남의 창 알림이 우리 게임을 끝냈다")
    }

    // MARK: - 팝오버와 공존한다

    @Test
    func theGameWindowCoexistsWithPopoverPanelsAndSurvivesThePopoverClosing() {
        let store = mgwStore()
        store.isTokenBoardVisible = true
        store.isMenuPresented = true
        store.openMiniGameWindow()
        #expect(store.isMiniGamePanelVisible)
        #expect(store.isTokenBoardVisible, "창이 팝오버 패널을 닫았다 — 별도 창은 상호 배타 대상이 아니다")

        // 팝오버를 닫아도 창의 게임은 계속된다(예전 패널 규약은 여기서 판을 끝냈다).
        let token = store.miniGameInterruptToken
        store.setMenuPresented(false)
        #expect(store.miniGameInterruptToken == token, "팝오버를 닫았다고 창에서 하던 게임이 끝났다")

        // 다른 패널을 열어도 마찬가지.
        store.setMenuPresented(true)
        store.toggleLeaderboard()
        #expect(store.isMiniGamePanelVisible, "리그를 열었다고 미니게임 창이 닫혔다")
        #expect(store.miniGameInterruptToken == token)
    }

}

// MARK: - 레이아웃 표

@MainActor
@Test
func windowLayoutIsAFixedTwoColumnConstantTable() {
    let layout = MiniGameWindowLayout.layout(hasChampionRow: true)
    // ★★ 이 저장소에서 가장 중요한 회귀 방지선. 캔버스는 **창 크기와 무관한 상수 344×356** 이어야 한다.
    // v0.2.48 에 창을 620×420 → 700×470 으로 넓히면서 계산 방향을 뒤집었다(예전엔 캔버스가 창에서 계산됐다).
    // 여기가 흔들리면 순위표에 쌓인 모든 기록의 의미가 갈린다 — 캔버스가 커지면 플래피는 반응할 여유가 늘고
    // 타이밍 바는 목표 구간이 픽셀로 넓어져 "모두가 같은 조건" 이라는 전제가 깨진다(사용자 결정 2026-09-08).
    #expect(MiniGameWindowLayout.canvasSize == CGSize(width: 344, height: 356), "캔버스가 \(MiniGameWindowLayout.canvasSize) 다")
    #expect(layout.canvasSize == CGSize(width: 344, height: 356))
    // 순위 열은 **나머지**다(창을 넓히면 여기만 자란다).
    #expect(MiniGameWindowLayout.rankWidth == 314, "순위 열 폭이 \(MiniGameWindowLayout.rankWidth) 다")
    #expect(layout.rankSize == CGSize(width: 314, height: 442), "순위 열이 \(layout.rankSize) 다")

    // 논리 좌표는 비율 유지로 그려진다 — **두 게임이 실제로 그리는 판**(292×302)으로 재야 이 단언이
    // 무언가를 잰다(예전엔 아무 게임도 안 쓰는 200 으로 계산했다). 배율이 1 이상이어야 축소가 없다.
    #expect(FlappyGame.logicalSize == MiniGameCanvas.logicalSize, "플래피가 공용 논리 판을 안 쓴다")
    let scale = MiniGameCanvas.transform(in: layout.canvasSize, logicalSize: MiniGameCanvas.logicalSize).scale
    #expect(scale >= 1, "논리 캔버스가 축소돼 그려진다(배율 \(scale))")
    // 그리고 레터박스가 거의 0 이다(같은 비율) — 위아래로 60pt 씩 비던 292×200 시절로 돌아가지 않는다.
    let letterbox = layout.canvasSize.height - MiniGameCanvas.logicalHeight * scale
    #expect(letterbox < 1, "위아래 레터박스가 \(letterbox)pt 다 — 기둥이 천장·바닥에 안 닿는다")

    // 두 단의 머리글 높이·그 아래 간격이 **같은 상수**여야 본문 윗변이 같은 y 에서 시작한다(2026-09-08 지적).
    #expect(MiniGameWindowLayout.headerHeight == 32)
    #expect(MiniGameWindowLayout.headerSpacing == 10)

    // 무스크롤 행수: 어제 챔피언 카드가 있으면 9, 없으면 10. 넘치면 ScrollView.
    #expect(MiniGameWindowLayout.visibleRows(hasChampionRow: true) == 9)
    #expect(MiniGameWindowLayout.visibleRows(hasChampionRow: false) == 10)
    #expect(MiniGameWindowLayout.listHeight(rows: 9) == 310)
    #expect(MiniGameWindowLayout.listHeight(rows: 10) == 345)
    #expect(MiniGameWindowLayout.listHeight(rows: 0) == 0)

    // 두 열이 창 안에 들어온다(470 넘침 없음).
    let inner = MiniGameWindowLayout.innerSize
    #expect(inner == CGSize(width: 672, height: 442))
    let width = layout.canvasSize.width + MiniGameWindowLayout.columnSpacing + layout.rankSize.width
    #expect(width == inner.width, "두 열 폭 합 \(width) 가 안쪽 폭 \(inner.width) 와 다르다")
    #expect(MiniGameWindowLayout.gameColumnHeight == 440)
    #expect(MiniGameWindowLayout.gameColumnHeight <= inner.height,
            "게임 열 \(MiniGameWindowLayout.gameColumnHeight) 이 안쪽 높이를 넘는다 — 하단 스트립이 창 밖으로 잘린다")
    for hasChampion in [true, false] {
        let column = MiniGameWindowLayout.rankChrome(hasChampionRow: hasChampion)
            + MiniGameWindowLayout.listHeight(rows: MiniGameWindowLayout.visibleRows(hasChampionRow: hasChampion))
        #expect(column <= inner.height, "순위 열(챔피언 \(hasChampion)) \(column) 이 안쪽 높이를 넘는다")
    }
    // 창 상수와 레이아웃 상수는 한 곳에서 온다.
    #expect(CheckMiniGameWindowController.fixedContentSize.width == MiniGameWindowLayout.contentSize.width)
    #expect(CheckMiniGameWindowController.fixedContentSize.height == MiniGameWindowLayout.contentSize.height)
}

/// 소스 계약: 캔버스를 다시 창 크기에서 **계산**하는 모양으로 되돌아가면, 다음에 창을 넓히는 사람이
/// 아무 경고 없이 게임 난이도를 바꾼다. 그래서 `canvasSize` 는 리터럴 상수여야 한다.
@Test
func canvasSizeIsALiteralConstantNotDerivedFromTheWindow() throws {
    let source = mgwStrippingComments(try String(contentsOf: mgwSourceURL("MiniGamePanel.swift"), encoding: .utf8))
    #expect(source.contains("static let canvasSize = CGSize(width: 344, height: 356)"),
            "canvasSize 가 리터럴 상수가 아니다 — 창을 넓히는 순간 난이도가 따라 바뀐다")
    #expect(source.contains("static var rankWidth: CGFloat { innerSize.width - columnSpacing - canvasSize.width }"),
            "순위 열이 나머지로 잡히지 않는다")
}

// MARK: - 스페이스 키는 게임 창이 떠 있을 때만

@Test
func spaceKeyGateIsScopedToTheVisibleGameWindow() throws {
    let source = mgwStrippingComments(try String(contentsOf: mgwSourceURL("MiniGamePanel.swift"), encoding: .utf8))
    // 창 제목·키 창 게이트는 2026-09-09 에 걷어냈다(창을 막 연 순간 스페이스가 죽었다). 대신 창 가시성으로 판정한다.
    #expect(source.contains("CheckMiniGameWindowController.shared.isWindowOnScreen"),
            "스페이스 게이트가 창 가시성을 안 본다 — 설정 창·할 일 보드에서 스페이스를 삼킨다")
    #expect(!source.contains("store.isMenuPresented"), "팝오버 조건이 남아 있다 — 게임은 이제 별도 창이다")
    #expect(source.contains("NSEvent.addLocalMonitorForEvents"), "로컬 모니터가 없으면 근무 알약이 스페이스를 먹는다")
    #expect(!source.contains("addGlobalMonitorForEvents"), "전역 모니터는 우리 앱이 활성일 때 눈이 먼다")
}

// MARK: - 배선 · 소스 계약

@Test
func windowWiringIsInstalledOnceAtLaunchAndThePopoverNoLongerDrawsThePanel() throws {
    let app = mgwStrippingComments(try String(contentsOf: mgwSourceURL("CheckApp.swift"), encoding: .utf8))
    #expect(app.contains("CheckMiniGameWindowController.shared.configure(store: store)"), "앱 시작 배선이 없다 — 창이 영영 안 뜬다")

    let menu = mgwStrippingComments(try String(contentsOf: mgwSourceURL("CheckMenuView.swift"), encoding: .utf8))
    #expect(!menu.contains("MiniGamePanel("), "팝오버가 아직 미니게임 패널을 그린다")
    #expect(!menu.contains("|| store.isMiniGamePanelVisible"), "isSubPanelOpen 이 창을 하위 패널로 센다 — 토큰 행이 사라진다")
    #expect(menu.contains("store.openMiniGameWindow()"), "레일 진입 버튼이 창을 열지 않는다")

    let store = mgwStrippingComments(try String(contentsOf: mgwSourceURL("WorkTimerStore.swift"), encoding: .utf8))
    for name in ["toggleLeaderboard", "toggleTokenBoard", "togglePokePanel", "openUltraPanel", "toggleInsightsPanel"] {
        let body = try #require(mgwFunctionBody(store, name: name), "\(name) 본문을 못 찾았다")
        #expect(!body.contains("closeMiniGamePanel()"), "\(name) 이 아직 미니게임을 닫는다 — 창은 팝오버와 공존한다")
    }
    let presented = try #require(mgwFunctionBody(store, name: "setMenuPresented"))
    #expect(!presented.contains("miniGameInterruptToken += 1"), "팝오버 닫힘이 창의 게임을 끝낸다")
}

// MARK: - 소스 계약 헬퍼(다른 파일의 것은 private)

private func mgwSourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/check/\(name)")
}

private func mgwStrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") { rest = rest[close.upperBound...]; inBlock = false } else { rest = "" }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]; rest = rest[block.upperBound...]; inBlock = true; continue
            }
            if let comment = lineComment { kept += rest[..<comment.lowerBound]; rest = ""; continue }
            kept += rest; rest = ""
        }
        output += kept + "\n"
    }
    return output
}

private func mgwFunctionBody(_ source: String, name: String) -> String? {
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

// MARK: - 스페이스 모니터 재설치 (2026-09-09 실사용 제보)

/// 창을 닫을 때 `onDisappear` 가 오지 않는 경우가 있어(AppKit 창은 orderOut 뒤에도 뷰가 살아 있다), 예전
/// `guard token == nil` 은 **죽은 화면의 클로저를 쥔 모니터**를 그대로 남겼다. 그러면 다시 연 창에서 클릭은
/// 되는데 스페이스만 먹통이 된다 — 사람마다 갈리는 증상의 정체다. 설치는 언제나 갈아 끼워야 한다.
@MainActor
@Test
func spaceMonitorAlwaysRebindsToTheNewestScreen() {
    MiniGameSpaceKey.remove()
    defer { MiniGameSpaceKey.remove() }

    final class Box { var count = 0 }
    let first = Box(), second = Box()

    MiniGameSpaceKey.install(shouldConsume: { true }, action: { first.count += 1 })
    #expect(MiniGameSpaceKey.isInstalled)
    // 옛 화면을 정리하지 못한 채(remove 없이) 새 화면이 뜬 상황.
    MiniGameSpaceKey.install(shouldConsume: { true }, action: { second.count += 1 })
    #expect(MiniGameSpaceKey.isInstalled, "재설치 뒤에도 모니터는 걸려 있어야 한다")

    MiniGameSpaceKey.fireForTesting()
    #expect(second.count == 1, "스페이스가 최신 화면으로 가야 한다")
    #expect(first.count == 0, "죽은 화면의 클로저가 살아 있으면 안 된다")

    MiniGameSpaceKey.remove()
    #expect(!MiniGameSpaceKey.isInstalled)
}

/// 소스 계약: 설치가 `guard token == nil` 로 첫 설치만 살리는 모양으로 되돌아가면 위 증상이 그대로 재발한다.
@Test
func spaceMonitorInstallDoesNotSkipWhenAlreadyInstalled() throws {
    let source = mgwStrippingComments(try String(contentsOf: mgwSourceURL("MiniGamePanel.swift"), encoding: .utf8))
    let body = try #require(source.range(of: "static func install(shouldConsume:")).lowerBound
    let end = try #require(source.range(of: "static func remove()", range: body..<source.endIndex)).lowerBound
    let install = String(source[body..<end])
    #expect(!install.contains("guard token == nil"), "첫 설치만 살리면 죽은 화면에 스페이스가 묶인다")
    #expect(install.contains("remove()"), "설치 전에 옛 모니터를 떼야 한다")
}


/// 창을 **막 연 순간** — 팝오버가 닫히며 키가 아직 넘어오지 않은 그 짧은 창 — 에도 스페이스가 살아 있어야 한다.
/// 모니터에서 `isKeyWindow`·창 제목 게이트를 뺀 것이 이 계약이다(2026-09-09 제보: "업데이트 뒤 처음 열어
/// 플레이할 때 스페이스가 안 됐다"). 대신 게이트는 `shouldConsume` — 창이 실제로 떠 있는지 — 하나뿐이다.
@Test
func spaceMonitorDoesNotRequireTheWindowToBeKey() throws {
    let source = mgwStrippingComments(try String(contentsOf: mgwSourceURL("MiniGamePanel.swift"), encoding: .utf8))
    let start = try #require(source.range(of: "static func install(shouldConsume:")).lowerBound
    let end = try #require(source.range(of: "static func remove()", range: start..<source.endIndex)).lowerBound
    let install = String(source[start..<end])
    #expect(!install.contains("isKeyWindow"), "키 창을 요구하면 창을 막 연 순간 스페이스가 죽는다")
    #expect(!install.contains("window.title"), "창 제목 게이트도 같은 이유로 뺐다 — 가시성은 shouldConsume 이 본다")
    #expect(install.contains("spaceKeyCode"), "스페이스 키만 가로채는 조건은 남아 있어야 한다")

    // 화면 쪽 게이트는 컨트롤러의 '창이 실제로 떠 있는가' 하나다.
    let panel = mgwStrippingComments(try String(contentsOf: mgwSourceURL("MiniGamePanel.swift"), encoding: .utf8))
    #expect(panel.contains("shouldConsume: { CheckMiniGameWindowController.shared.isWindowOnScreen }"))
    let controller = mgwStrippingComments(try String(contentsOf: mgwSourceURL("CheckMiniGameWindow.swift"), encoding: .utf8))
    #expect(controller.contains("var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }"),
            "의도(isOpen)와 사실(isVisible)을 함께 본다 — isVisible 은 이 저장소에서 거짓말한 적이 있다")
}

/// 창이 떠 있지 않으면 스페이스를 삼키지 않는다(다른 화면의 스페이스를 훔치지 않는다).
@MainActor
@Test
func spaceIsIgnoredWhileTheGameWindowIsNotOnScreen() {
    MiniGameSpaceKey.remove()
    defer { MiniGameSpaceKey.remove() }
    var fired = 0
    MiniGameSpaceKey.install(shouldConsume: { false }, action: { fired += 1 })
    MiniGameSpaceKey.fireForTesting()
    #expect(fired == 1, "발화 훅은 모니터가 쥔 동작을 그대로 태운다 — 게이트 검증은 소스 계약이 맡는다")
}

// MARK: - 일시정지 (v0.2.48 — "게임 도중에 그냥 포기하고 다른 게임 하고 싶을 때 멈추는 게 안 되네", 2026-09-10)

/// 정지 상태 기계는 순수 값이다(뷰의 @State 밖에서 잰다). 규칙은 넷:
///   · 진행 중일 때만 정지할 수 있다 · 정지 중에도(카운트다운 포함) 판은 얼어 있다
///   · 재개는 3 → 2 → 1 → none · 카운트다운 중 다시 누르면 정지로 되돌아간다
@Test
func pauseStateMachineOnlyPausesWhilePlayingAndCountsBackFromThree() {
    typealias Pause = CheckMiniGameWindowView.PauseState

    // 시작 전·결과 화면에서는 얼리지 않는다(얼리면 클릭이 안 먹는 창이 된다).
    #expect(Pause.none.toggled(isPlaying: false) == .none, "진행 중이 아닌데 정지됐다")
    #expect(Pause.none.toggled(isPlaying: true) == .paused)

    // 정지 → 재개는 곧바로 풀리지 않는다. 3-2-1 이 있어야 정지로 얻은 리듬 이점이 사라진다.
    #expect(Pause.countdownStart == 3)
    #expect(Pause.paused.toggled(isPlaying: true) == .resuming(3))
    #expect(Pause.resuming(3).steppedDown() == .resuming(2))
    #expect(Pause.resuming(2).steppedDown() == .resuming(1))
    #expect(Pause.resuming(1).steppedDown() == .none)
    #expect(Pause.none.steppedDown() == .none, "정지가 아닌 상태에서 카운트다운이 돈다")

    // 카운트다운 중 ESC 는 다시 정지(취소).
    #expect(Pause.resuming(2).toggled(isPlaying: true) == .paused)

    // 판이 얼어 있는가 = host.isPaused. 카운트다운 중에도 참이어야 한다 — 아니면 3-2-1 동안 기둥이 온다.
    #expect(!Pause.none.isFrozen)
    #expect(Pause.paused.isFrozen)
    #expect(Pause.resuming(3).isFrozen && Pause.resuming(1).isFrozen)
    // 카드(이어하기·그만두기)는 정지 상태에서만. 카운트다운 중에는 숫자만 크게 뜬다.
    #expect(Pause.paused.showsCard)
    #expect(!Pause.resuming(2).showsCard)
    #expect(Pause.resuming(2).countdown == 2 && Pause.paused.countdown == nil)
}

/// 소스 계약: 화면이 정지 상태를 게임에 넘기고(host.isPaused), 정지 중에는 종류 칩을 **푼다**.
/// 사용자가 원한 것이 정확히 "포기하고 다른 게임 하기"다 — 잠긴 채로 두면 요구가 반만 채워진다.
@Test
func pauseFreezesTheBoardAndUnlocksTheKindChips() throws {
    let source = mgwStrippingComments(try String(contentsOf: mgwSourceURL("MiniGamePanel.swift"), encoding: .utf8))
    #expect(source.contains("isPaused: pauseState.isFrozen"), "정지 상태가 게임에 안 넘어간다 — 판이 뒤에서 계속 돈다")
    #expect(source.contains("isEnabled: !isPlaying || pauseState.isFrozen || kind == store.miniGameKind"),
            "정지 중에도 종류 칩이 잠겨 있다 — '포기하고 다른 게임' 이 안 된다")
    // 스크림은 캔버스를 통째로 가린다(정지해 놓고 다음 기둥을 외우는 것이 이득이 되면 안 된다).
    // 두 층이다: 불투명 바닥(CheckTheme.panel) + 색조(panelElevated 0.93). 바닥을 빼면 밑그림이 7% 비쳐
    // 시작 카드의 흰 글자가 그대로 읽힌다(2026-09-10 스냅샷 실측).
    #expect(source.contains("CheckTheme.panelElevated.opacity(0.93)"), "정지 스크림이 없거나 불투명도가 바뀌었다")
    let overlay = try #require(source.range(of: "private var pauseOverlay: some View {"))
    let overlayHead = String(source[overlay.upperBound...].prefix(120))
    #expect(overlayHead.contains("CheckTheme.panel\n"), "스크림 바닥이 반투명뿐이다 — 판이 비쳐 보인다")
    // 카운트다운 Task 는 창이 닫히거나 판이 끝나면 반드시 취소된다.
    #expect(source.contains("resumeTask?.cancel()"), "카운트다운 Task 취소 경로가 없다")
    let disappear = try #require(source.range(of: ".onDisappear {"))
    let tail = String(source[disappear.upperBound...].prefix(200))
    #expect(tail.contains("cancelResume()"), "창이 사라져도 1초 Task 가 남는다")
    // interrupt(창 닫힘·포커스 상실·종류 전환·그만두기) 가 오면 즉시 풀린다 + Task 취소.
    let interrupt = try #require(source.range(of: ".onChange(of: store.miniGameInterruptToken)"))
    let body = String(source[interrupt.upperBound...].prefix(240))
    #expect(body.contains("cancelResume()") && body.contains("pauseState = .none"),
            "판이 끝났는데 스크림이 남는다 — 아무것도 못 누르는 창이 된다")
}

/// [그만두기] 는 스토어의 새 문으로 간다. 하는 일은 토큰 하나지만, 창 컨트롤러가 프로퍼티를 직접 만지는
/// 경로만 있던 자리에 **화면이 부를 이름**을 낸 것이 이 메서드의 존재 이유다.
@MainActor
@Test
func abortMiniGameRoundRaisesTheInterruptTokenAndKeepsTheWindowOpen() {
    let store = mgwStore()
    store.isMiniGamePanelVisible = true
    let token = store.miniGameInterruptToken
    store.abortMiniGameRound()
    #expect(store.miniGameInterruptToken == token + 1, "[그만두기] 가 판을 안 끝낸다")
    #expect(store.isMiniGamePanelVisible, "그만뒀다고 창까지 닫으면 다른 게임으로 못 넘어간다")
    store.abortMiniGameRound()
    #expect(store.miniGameInterruptToken == token + 2, "연속 호출마다 새 신호여야 한다")
}

// MARK: - ESC 는 스페이스와 **같은 모니터**에 얹혀 있다

/// 모니터를 두 벌 걸면 설치·제거 규약이 두 곳이 되어, 2026-09-09 에 고친 두 버그(죽은 화면 고착 · 키 창 게이트)가
/// 한쪽에서만 고쳐진 채 남는다. 그래서 ESC 는 같은 install 에 얹는다.
@MainActor
@Test
func escapeIsHandledByTheSameMonitorAsSpaceAndOnlySwallowedWhenUsed() {
    MiniGameSpaceKey.remove()
    defer { MiniGameSpaceKey.remove() }

    final class Box { var space = 0; var escape = 0 }
    let box = Box()
    // 화면이 "안 썼다"고 답하는 경우: ESC 는 삼켜지지 않아야 한다(다른 화면의 취소 키를 훔치지 않는다).
    MiniGameSpaceKey.install(shouldConsume: { true }, action: { box.space += 1 },
                             onEscape: { box.escape += 1; return false })
    #expect(MiniGameSpaceKey.fireEscapeForTesting() == false, "안 쓴 ESC 를 삼켰다")
    #expect(box.escape == 1 && box.space == 0, "ESC 가 스페이스 동작을 태웠다")

    // 화면이 "정지했다"고 답하면 삼킨다.
    MiniGameSpaceKey.install(shouldConsume: { true }, action: { box.space += 1 },
                             onEscape: { box.escape += 1; return true })
    #expect(MiniGameSpaceKey.fireEscapeForTesting() == true)
    #expect(box.escape == 2)
    // 재설치는 여전히 최신 화면으로 갈아 끼운다(스페이스 쪽 계약을 ESC 가 깨지 않았다).
    MiniGameSpaceKey.fireForTesting()
    #expect(box.space == 1)

    MiniGameSpaceKey.remove()
    #expect(!MiniGameSpaceKey.isInstalled)
    #expect(MiniGameSpaceKey.fireEscapeForTesting() == false, "떼어낸 모니터의 ESC 처리기가 살아 있다")
}

/// 소스 계약: ESC 가 같은 `install` 안에서 처리되고, 게이트(shouldConsume)는 스페이스와 **한 벌**이다.
/// 창이 안 떠 있으면 ESC 도 그대로 흘러간다.
@Test
func escapeSharesTheSpaceMonitorGate() throws {
    let source = mgwStrippingComments(try String(contentsOf: mgwSourceURL("MiniGamePanel.swift"), encoding: .utf8))
    let start = try #require(source.range(of: "static func install(shouldConsume:")).lowerBound
    let end = try #require(source.range(of: "static func remove()", range: start..<source.endIndex)).lowerBound
    let install = String(source[start..<end])
    #expect(install.contains("escapeKeyCode"), "ESC 가 이 모니터에서 안 잡힌다")
    #expect(install.contains("guard shouldConsume() else { return false }"),
            "ESC 가 창 가시성 게이트를 우회한다 — 창이 안 떠 있어도 ESC 를 훔친다")
    #expect(source.contains("static let escapeKeyCode: UInt16 = 53"), "ESC keyCode 가 53 이 아니다")
    // 모니터는 여전히 **하나**다.
    #expect(source.components(separatedBy: "NSEvent.addLocalMonitorForEvents").count - 1 == 1,
            "모니터가 두 벌이다 — 설치·제거 규약이 갈린다")
    #expect(source.contains("onEscape: { togglePause() }"), "화면이 ESC 를 정지 토글에 안 물렸다")
}

// MARK: - 프레임 상한 = 화면 주사율의 약수 (v0.2.50)
//
// 사용자 신고 "살짝 버벅인다"의 원인은 `TimelineView(minimumInterval: 1/60)` 이었다 — 이 기계는 75Hz 라
// 60 과 나눠떨어지지 않아 네 프레임에 한 장이 두 배(26.67ms)로 늘어졌다(실측 25.1%). 고친 방식은 상한을
// 푸는 것이 아니라 **화면 주사율의 약수로 맞추는 것**이다(사용자 지시 2026-09-10). 여기서 그 표를 못 박는다.
// 규칙과 근거는 `MiniGameFrameRate` 머리 주석에 있다 — 표를 고치려면 그 주석부터 고쳐야 한다.

@Test
func miniGameFrameRatePicksTheDivisorNearest60() {
    // 사용자 지시에 함께 온 기대값(그대로다).
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: 60) == 60)
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: 75) == 75)
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: 120) == 60)
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: 144) == 72)
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: 240) == 60)
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: 90) == 90)
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: 30) == 30)

    // 60 이하는 화면이 주는 그대로(더 줄 수가 없다).
    for hz in [24, 25, 30, 48, 50, 59, 60] {
        #expect(MiniGameFrameRate.targetFPS(forRefreshRate: hz) == hz, "\(hz)Hz 는 그 값 그대로여야 한다")
    }
    // 60 초과 · 상한 안 — 자기 자신이 60 이상 최소 약수다.
    for hz in [72, 75, 85, 90, 100, 119] {
        #expect(MiniGameFrameRate.targetFPS(forRefreshRate: hz) == hz, "\(hz)Hz")
    }
    // 60 초과 — 나눠서 60 쪽으로 내려온다.
    for (hz, fps) in [(120, 60), (144, 72), (160, 80), (170, 85), (180, 60), (200, 100),
                      (240, 60), (300, 60), (360, 60), (480, 60)] {
        #expect(MiniGameFrameRate.targetFPS(forRefreshRate: hz) == fps, "\(hz)Hz → \(fps) 여야 한다")
    }
    // 상한(120)이 **실제로 거는** 유일한 흔한 주사율. 165 의 약수는 1·3·5·11·15·33·55·165 뿐이라
    // 60 이상은 자기 자신뿐이고 그것은 상한 밖이다 → 아래쪽에서 가장 가까운 55(3 vsync).
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: 165) == 55)
    // 바닥(40)이 거는 곳 — 60~120 에 약수가 없고 아래쪽 최선이 너무 낮다. 저더를 감수하고 60 으로 간다.
    for hz in [121, 125, 127, 143, 155, 169, 175, 187, 209] {
        #expect(MiniGameFrameRate.targetFPS(forRefreshRate: hz) == 60, "\(hz)Hz 는 60 폴백이어야 한다")
    }
}

@MainActor
@Test
func miniGameFrameRateFallsBackWhenThereIsNoScreen() {
    // 헤드리스·화면 없음·잘못 읽은 값. 여기서 0 으로 나누거나 1fps 로 떨어지면 게임이 멈춘 것처럼 보인다.
    for hz in [0, -1, -60, 1, 7, 23] {
        #expect(MiniGameFrameRate.targetFPS(forRefreshRate: hz) == 60, "\(hz) → 60 폴백이어야 한다")
        #expect(MiniGameFrameRate.minimumInterval(forRefreshRate: hz) == 1.0 / 60.0, "\(hz) → 정확히 1/60")
    }
    // 이 테스트가 도는 곳에 화면이 없을 수도 있다 — 그 경로가 죽지 않는지(값이 언제나 쓸 만한지).
    let live = MiniGameFrameRate.refreshRate(of: nil)
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: live) >= 24)
    #expect(MiniGameFrameRate.targetFPS(forRefreshRate: live) <= MiniGameFrameRate.maxFPS)
}

@Test
func miniGameFrameRateIntervalLandsOnExactlyOneVsyncBoundary() {
    // 이 단언이 이 변경의 심장이다: 요구 간격은 **k번째 vsync 를 고르고 k−1 번째는 못 고르는** 구간 안에
    // 있어야 한다. 위로 넘치면 프레임 하나가 통째로 늦어지고(= 고치려던 저더), 아래로 (k−1)V 이하면
    // 한 틱 이른 프레임이 상시로 생긴다.
    for hz in 24...600 {
        let fps = MiniGameFrameRate.targetFPS(forRefreshRate: hz)
        let interval = MiniGameFrameRate.minimumInterval(forRefreshRate: hz)
        if hz <= MiniGameFrameRate.baselineFPS {
            // 규칙 ①: 화면이 60 이하면 그 값 그대로다(바닥은 여기 적용되지 않는다 — 24Hz 화면에서
            // 40fps 를 요구하면 vsync 를 못 맞춰 도로 저더가 된다).
            #expect(fps == hz, "\(hz)Hz 는 그 값 그대로여야 한다(목표 \(fps))")
        } else {
            #expect(fps >= MiniGameFrameRate.minFPS, "\(hz)Hz 목표 \(fps) — 바닥 아래다")
        }
        #expect(fps <= MiniGameFrameRate.maxFPS, "\(hz)Hz 목표 \(fps) — 상한 위다")
        #expect(interval > 0)
        guard hz % fps == 0 else {
            // 나눠떨어지지 않는 폴백(저더 감수) — 뺄 vsync 가 없으니 정확히 1/60 이다.
            #expect(fps == 60)
            #expect(interval == 1.0 / 60.0, "\(hz)Hz 폴백 간격이 1/60 이 아니다")
            continue
        }
        let vsync = 1.0 / Double(hz)
        let k = Double(hz / fps)
        #expect(interval <= k * vsync, "\(hz)Hz: 간격이 \(k)vsync 를 넘겼다 — 프레임이 늦는다")
        #expect(interval > (k - 1) * vsync, "\(hz)Hz: 간격이 \(k - 1)vsync 이하다 — 프레임이 이르다")
        // 여유는 vsync 한 틱 기준이라 k 에 끌려다니지 않는다.
        #expect(abs(interval - (k - MiniGameFrameRate.vsyncHeadroom) * vsync) < 1e-12, "\(hz)Hz 여유가 k 에 끌려다닌다")
    }
    // 실제 화면 값 두 개(하나는 이 기계).
    #expect(abs(MiniGameFrameRate.minimumInterval(forRefreshRate: 75) - 0.99 / 75.0) < 1e-12)
    #expect(abs(MiniGameFrameRate.minimumInterval(forRefreshRate: 60) - 0.99 / 60.0) < 1e-12)
}

@MainActor
@Suite(.serialized)
struct V0250MiniGameFrameRateWiringTests {
    /// 창을 열면 **그 창이 선 화면**에서 주사율을 읽는다. 창 생성 시점에는 `window.screen` 이 nil 이라
    /// 그때 읽으면 두 번째 모니터에 놓아 둔 창이 주 화면의 값으로 논다.
    @Test
    func showReadsTheRefreshRateOfTheScreenTheWindowStandsOn() {
        let store = mgwStore()
        // 말도 안 되는 값으로 시작한다 — 갱신이 실제로 일어났는지 값으로 구별하기 위해서다.
        let monitor = MiniGameFrameRateMonitor(refreshHz: 1)
        let controller = CheckMiniGameWindowController(frameRateMonitor: monitor)
        controller.configure(store: store)
        #expect(MiniGameFrameRate.targetFPS(forRefreshRate: monitor.refreshHz) == 60, "1Hz 는 폴백이어야 한다")
        controller.show()
        defer { controller.close() }
        let expected = MiniGameFrameRate.refreshRate(of: controller.currentWindow)
        #expect(monitor.refreshHz == expected, "창을 열었는데 주사율을 안 읽었다(\(monitor.refreshHz) vs \(expected))")
        #expect(monitor.refreshHz >= 24, "쓸 수 없는 주사율을 들고 있다")
    }

    /// **창을 다른 모니터로 옮겼을 때** 갱신되는가. AppKit 은 `NSWindow.didChangeScreenNotification` 을 던지고
    /// 창은 그것을 델리게이트의 `windowDidChangeScreen(_:)` 로 넘긴다 — 여기서는 그 알림을 직접 던져
    /// **우리 델리게이트가 실제로 그 경로에 걸려 있는지**까지 확인한다(메서드를 직접 부르면 배선이 빠져도 초록이다).
    @Test
    func movingTheWindowToAnotherScreenRefreshesTheRate() throws {
        let store = mgwStore()
        let monitor = MiniGameFrameRateMonitor(refreshHz: 1)
        let controller = CheckMiniGameWindowController(frameRateMonitor: monitor)
        controller.configure(store: store)
        controller.show()
        defer { controller.close() }
        let window = try #require(controller.currentWindow)
        let expected = MiniGameFrameRate.refreshRate(of: window)

        // 화면을 옮긴 척: 값을 되돌려 놓고 AppKit 이 던지는 그 알림을 그대로 던진다.
        monitor.setForTesting(1)
        #expect(monitor.refreshHz == 1)
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        #expect(monitor.refreshHz == expected,
                "창이 화면을 옮겼는데 주사율이 그대로다 — 게임이 옛 간격으로 계속 돈다")

        // 화면 **구성**이 바뀌는 갈래(창은 그 자리, 주사율만 바뀜)도 같은 자리로 온다.
        monitor.setForTesting(1)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(monitor.refreshHz == expected, "화면 구성이 바뀌었는데 주사율을 다시 안 읽었다")

        // 다른 창의 알림은 우리 값을 건드리지 않는다(창이 여럿인 앱이다).
        monitor.setForTesting(1)
        let stranger = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                                styleMask: [.titled], backing: .buffered, defer: false)
        // 닫으면 해제되는 기본값을 끈다 — ARC 가 쥔 참조가 남은 채 해제돼 프로세스가 죽는다(SIGSEGV 실측).
        stranger.isReleasedWhenClosed = false
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: stranger)
        #expect(monitor.refreshHz == 1, "남의 창 알림에 반응했다")
        stranger.orderOut(nil)
    }

    /// 허브가 그 값을 **게임까지** 나른다. 스토어를 거치지 않는 유일한 값이라 배선이 빠져도 화면은 돌아간다 —
    /// 그래서 소스 계약으로 못 박는다(끊기면 60 폴백으로 조용히 되돌아간다).
    @Test
    func hubHandsTheRefreshRateToTheGame() throws {
        let source = mgwStrippingComments(try String(contentsOf: mgwSourceURL("MiniGamePanel.swift"), encoding: .utf8))
        #expect(source.contains("refreshHz: MiniGameFrameRateMonitor.shared.refreshHz"),
                "허브가 주사율을 게임에 안 넘긴다 — 두 게임이 영영 60 폴백으로 돈다")
        let controller = mgwStrippingComments(try String(contentsOf: mgwSourceURL("CheckMiniGameWindow.swift"), encoding: .utf8))
        #expect(controller.contains("func windowDidChangeScreen("), "화면 이동 델리게이트가 없다")
        #expect(controller.contains("NSApplication.didChangeScreenParametersNotification"), "화면 구성 변경을 안 본다")
    }
}
