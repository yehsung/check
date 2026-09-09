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
        #expect(CheckMiniGameWindowController.fixedContentSize == NSSize(width: 620, height: 420))

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
    let layout = MiniGameWindowLayout.layout(hasYesterdayRow: true)
    // 캔버스 344×356 — 폭은 596 − 12(단 사이) − 240(순위 열), 높이는 칩 줄 아래 남는 세로 전부(396 − 28 − 12).
    // 비율(292:200)로 236 을 쓰면 게임 열 아래 120pt 가 비었다. transform(in:) 이 짧은 축 기준으로 배율을
    // 잡아 가운데 정렬하므로 그릇이 세로로 길어도 게임 난이도는 그대로다 — 위아래 바닥이 더 그려질 뿐.
    #expect(layout.canvasSize == CGSize(width: 344, height: 356), "캔버스가 \(layout.canvasSize) 다")
    #expect(layout.rankSize == CGSize(width: 240, height: 396), "순위 열이 \(layout.rankSize) 다")
    #expect(MiniGameWindowLayout.rankWidth == 240)
    // 캔버스와 순위 열의 아랫변이 같은 줄에서 끝난다(두 단이 나란히 꽉 찬다).
    #expect(layout.canvasSize.height + MiniGameWindowLayout.chipRowHeight + MiniGameWindowLayout.columnSpacing
            == layout.rankSize.height, "두 단의 아랫변이 어긋난다")
    // 논리 좌표는 비율 유지로 그려지므로, 배율은 짧은 축(폭)이 정한다 — 그 배율이 1 이상이어야 축소가 없다.
    let scale = min(layout.canvasSize.width / MiniGameCanvas.logicalWidth,
                    layout.canvasSize.height / MiniGameCanvas.logicalHeight)
    #expect(scale >= 1, "논리 캔버스가 축소돼 그려진다(배율 \(scale))")

    // 행수는 어제 1등 줄이 있으나 없으나 상한 10 이다(고정 높이에 여유가 있어 그 22pt 를 흡수한다).
    #expect(MiniGameWindowLayout.visibleRows(hasYesterdayRow: true) == 10)
    #expect(MiniGameWindowLayout.visibleRows(hasYesterdayRow: false) == 10)
    #expect(MiniGameWindowLayout.listHeight(rows: 10) == 296)
    #expect(MiniGameWindowLayout.listHeight(rows: 0) == 0)

    // 두 열이 창 안에 들어온다.
    let inner = MiniGameWindowLayout.innerSize
    #expect(inner == CGSize(width: 596, height: 396))
    let width = layout.canvasSize.width + MiniGameWindowLayout.columnSpacing + layout.rankSize.width
    #expect(width == inner.width, "두 열 폭 합 \(width) 가 안쪽 폭 \(inner.width) 와 다르다")
    let gameColumn = MiniGameWindowLayout.chipRowHeight + MiniGameWindowLayout.chipRowSpacing + layout.canvasSize.height
    let rankColumn = MiniGameWindowLayout.rankChrome(hasYesterdayRow: true) + MiniGameWindowLayout.listHeight(rows: layout.visibleRows)
    #expect(gameColumn <= inner.height, "게임 열 \(gameColumn) 이 안쪽 높이를 넘는다")
    #expect(rankColumn <= inner.height, "순위 열 \(rankColumn) 이 안쪽 높이를 넘는다")
    // 창 상수와 레이아웃 상수는 한 곳에서 온다.
    #expect(CheckMiniGameWindowController.fixedContentSize.width == MiniGameWindowLayout.contentSize.width)
    #expect(CheckMiniGameWindowController.fixedContentSize.height == MiniGameWindowLayout.contentSize.height)
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
    #expect(menu.contains("store.openMiniGameWindow()"), "캡션 행 버튼이 창을 열지 않는다")

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
