import AppKit
import Observation
import SwiftUI

// MARK: - 1:1 오목 창 (v0.3.27)
//
// 틀은 `CheckMiniGameWindow.swift` 그대로다(지연 생성 · 멱등 열기 · 닫아도 파괴 안 함 · 고유 자동저장 이름 ·
// 고착 감시자 + 재생성 상한 · 테스트 알파 0). 그 파일과 **다른 점**만 적는다.
//
//   · **창이 키를 잃거나 닫혀도 대국은 끝나지 않는다.** 미니게임은 60Hz 판이라 포커스를 잃으면 판을 멈춰야 유휴 0% 가
//     지켜졌다(`miniGameInterruptToken`). 오목은 턴제이고 시간 판정은 **서버 시계**가 한다 — 다른 앱을 잠깐 봤다고,
//     창을 닫았다고 대국을 끝내면 루비가 걸린 판을 사용자 실수 한 번에 잃는다(설계서 §1 "창을 닫거나 포커스를 잃어도
//     대국은 끝나지 않는다"). 그래서 이 컨트롤러는 판 중단 신호를 **아예 모른다**. 알리는 것은 창 표시 상태뿐이다
//     (`GomokuStore.windowDidShow/Hide` — 폴링은 창이 보일 때만 돈다, 무료 플랜 요청 예산).
//     그래서 `windowDidResignKey` 를 두지 않는다. 키를 잃어도 창은 화면에 있고, 사용자가 판을 보고 있다.
//   · **최소화는 '안 보임'이다.** 최소화된 창에서 3초 폴링을 돌릴 이유가 없다(실시간 신호는 그대로 온다).
//     되살리면 다시 '보임'을 알린다.
//   · 스페이스/ESC 모니터·주사율 감시자가 없다 — 턴제라 프레임 루프가 없고, 미니게임 전용 전역 싱글턴
//     (`MiniGameSpaceKey`·`MiniGameFrameRateMonitor.shared`)과 부딪칠 일을 원천적으로 만들지 않는다.
//   · 크기는 **1000×700 고정**이다(`GomokuWindowLayout.contentSize`). 15×15 판의 칸이 손가락 대신 마우스로
//     정확히 찍을 만큼 커야 하고(칸 38pt), 오른쪽에 두 사람 카드와 판돈·기권이 함께 서야 한다.

/// 오목 창의 **고정** 레이아웃. 순수 상수 — 창 크기를 두 곳에 적지 않는다.
///
/// 산식:
///   · 안쪽 = 1000−40 × 700−40 = 960 × 660
///   · 본문 높이 = 660 − 머리글 40 − 간격 12 = 608
///   · 대국: 판 608×608(정사각) | 오른쪽 열 960 − 20 − 608 = 332
///   · 로비: 상대 목록 540 | 오른쪽 열 960 − 20 − 540 = 400
enum GomokuWindowLayout {
    /// 창 콘텐츠 크기(고정). 컨트롤러의 min/max 도 이 값 하나를 쓴다.
    static let contentSize = CGSize(width: 1000, height: 700)
    static let contentPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let headerHeight: CGFloat = 40
    static let headerSpacing: CGFloat = 12
    /// 로비 왼쪽(상대 목록) 폭.
    static let lobbyListWidth: CGFloat = 540

    static var innerSize: CGSize {
        CGSize(width: contentSize.width - contentPadding * 2, height: contentSize.height - contentPadding * 2)
    }
    static var bodyHeight: CGFloat { innerSize.height - headerHeight - headerSpacing }
    /// 판 한 변 = 본문 높이(정사각).
    static var boardSide: CGFloat { bodyHeight }
    /// 대국·결과 화면의 오른쪽 열 = 나머지.
    static var sideColumnWidth: CGFloat { innerSize.width - columnSpacing - boardSide }
    /// 로비 오른쪽 열 = 나머지.
    static var lobbySideWidth: CGFloat { innerSize.width - columnSpacing - lobbyListWidth }
}

/// 오목 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다** —
/// 스토어의 `openWindow(focusMatchID:)` 가 `presentWindow` 문(CheckApp 배선)을 거쳐 여기로 온다.
@MainActor
final class CheckGomokuWindowController: NSObject, NSWindowDelegate {
    /// 앱이 쓰는 단 하나의 인스턴스. `init` 을 막지 않은 이유는 헤드리스 검증이다(미니게임·설정 창과 같다).
    static let shared = CheckGomokuWindowController()

    /// 창 제목. CGWindowList 로 밖에서 창을 셀 때의 표식이다.
    static let windowTitle = "1:1 오목"

    /// 창 위치를 기억하는 키. **다른 창과 겹치면 안 된다** — 같은 이름이 이미 등록돼 있으면
    /// `setFrameAutosaveName` 이 false 를 돌려주고 자리 저장이 조용히 죽는다(`frameAutosaveActive` 로 잰다).
    static let frameAutosaveName = "check.gomoku.window"

    /// 콘텐츠 크기 — 고정. 숫자는 `GomokuWindowLayout.contentSize` 한 곳에서 온다.
    static let fixedContentSize = NSSize(
        width: GomokuWindowLayout.contentSize.width,
        height: GomokuWindowLayout.contentSize.height
    )

    /// 창을 물릴 재료. 스토어와 콘텐츠를 **함께** 묶는다(따로 두면 콘텐츠만 플레이스홀더인 조합이 생긴다).
    struct Wiring {
        let store: GomokuStore
        let content: @MainActor (GomokuStore) -> AnyView
    }

    private var wiring: Wiring?
    /// 지연 생성된 창. 닫아도 파괴하지 않는다 — 옮겨 둔 자리가 매번 초기화되는 게 더 나쁘다.
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). `isVisible` 은 이 저장소에서 거짓말한 적이 있어 '의도'와 '사실'을 나눈다.
    private(set) var isOpen = false
    /// 창을 이미 만들었는가(`window` 를 읽으면 그 순간 만들어지므로 이 문으로만 묻는다).
    var hasWindow: Bool { windowStorage != nil }
    /// 지금 쥐고 있는 창(읽기 전용 — 만들지 않는다).
    var currentWindow: NSWindow? { windowStorage }
    /// 의도와 사실이 **둘 다** 참일 때만 떠 있다고 본다.
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }
    /// 지금 창이 실제로 자리를 저장하고 있는가(헤드리스 검증 지점).
    private(set) var frameAutosaveActive = false
    /// 스토어에 마지막으로 알린 표시 상태(헤드리스 검증 지점 — true = windowDidShow, false = windowDidHide).
    /// 스토어의 반응(폴링 시작 등)은 core 가 정한다 — 이 값은 **알렸는가** 만 잰다.
    private(set) var lastVisibilityNotice: Bool?
    /// 스토어에 마지막으로 알린 가림 상태(헤드리스 검증 지점 — true = 보임, false = 가려짐).
    private(set) var lastOcclusionNotice: Bool?

    /// 이 인스턴스의 고착 확인 지연(초). 프로덕션은 언제나 `Self.stuckWindowCheckSeconds`.
    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckGomokuWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. 기본 화면(`GomokuPanel`)을 물린다. `me` 는 내 이름·캐릭터를 읽는 문이다 —
    /// `GomokuStore` 는 상대만 들고 있어서(§6.3) 나는 앱 배선이 `WorkTimerStore` 에서 읽어 넘긴다.
    func configure(
        store: GomokuStore,
        me: @escaping @MainActor () -> GomokuPlayerFace = { GomokuPlayerFace.fallback }
    ) {
        configure(store: store, content: { gomoku in
            // 뷰는 고정 크기를 채운다. 배경을 창 쪽에서 채우지 않으면 화면 배율이 바뀌는 순간 시스템 회색 판이 드러난다.
            AnyView(
                GomokuPanel(store: gomoku, me: me)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(CheckTheme.background)
            )
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재기 위한 문). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(store: GomokuStore, content: @escaping @MainActor (GomokuStore) -> AnyView) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    /// 창(첫 `show()` 에 생성). 배선 전이면 nil 이다.
    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = NSHostingView(rootView: wiring.content(wiring.store))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        // 복원은 `setFrameUsingName`, 저장은 `setFrameAutosaveName`(설정 창과 같은 함정).
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        if created.frame.size != created.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size {
            created.setContentSize(Self.fixedContentSize)
        }
        // 반환값을 버리지 않는다 — 이름 충돌이면 false 이고 자리 저장이 조용히 죽는다.
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    /// 오목 창을 만든다.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            // `.resizable` 은 없다(고정). `.miniaturizable` 은 넣는다 — 상대 차례에 치워 뒀다 다시 꺼내는 표면이다.
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = fixedContentSize
        window.contentMaxSize = fixedContentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        // 우리가 창을 붙들고 재사용한다 — 닫힘에 해제가 끼면 다음 show() 가 해제된 창을 만진다.
        window.isReleasedWhenClosed = false
        // 다른 앱을 클릭해도 창은 남는다(대국은 계속된다 — 시간은 서버가 잰다).
        window.hidesOnDeactivate = false
        // 앱 전체가 다크다(`CheckTheme`).
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0. 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 열기 / 닫기

    /// 오목 창을 연다(멱등 — 최소화돼 있으면 되살린다). 열 때마다 스토어에 '보임'을 알린다 —
    /// `orderOut` 된 창은 뷰가 살아 있어 `onAppear` 가 다시 오지 않으므로, 재조회의 문은 여기다.
    func show() {
        guard let window else { return }
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        let fixedFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
        if window.frame.size != fixedFrame { window.setContentSize(Self.fixedContentSize) }
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        notifyVisibility(true)
        armStuckWindowWatchdog()
    }

    /// 오목 창을 내린다(멱등). 창과 그 안의 상태는 남는다. **대국은 끝나지 않는다.**
    /// 로그아웃·계정 전환에서도 이 문을 부른다(`GomokuAccountWatcher`) — 깃발만 내리면 내용이 빈 창이 남는다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
        notifyVisibility(false)
    }

    /// 사용자가 빨간 점을 눌렀다. 의도를 맞추고 '안 보임'만 알린다 — 기권이 아니다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        notifyVisibility(false)
    }

    /// 최소화 — 화면에서 사라졌으니 폴링을 멈추게 한다(대국은 계속).
    func windowDidMiniaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        notifyVisibility(false)
    }

    /// 최소화에서 되살아났다 — 다시 '보임'.
    func windowDidDeminiaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        if isOpen { notifyVisibility(true) }
    }

    /// 가림 상태가 바뀌었다 — 다른 창에 완전히 가려짐 · 다른 Space · 화면 잠금. 스토어에 **폴링만** 멈추라고 알린다
    /// (`isWindowVisible` 과 시계 잎 뷰는 그대로다 — 가림 통지가 틀려도 보이는 창의 시계가 멈추면 안 된다).
    /// 대국 중 가려진 동안에도 실시간 신호로는 판을 다시 읽으므로 수를 놓치지 않는다.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        applyOcclusion(visible: window.occlusionState.contains(.visible))
    }

    /// 가림 판정을 스토어로 옮긴다(헤드리스 검증 문 — 알파 0 테스트 창의 occlusionState 는 화면 사정에 따라 달라서 값을 주입한다).
    /// 닫힌 창의 통지는 무시한다(닫기는 이미 '안 보임'을 알렸다).
    func applyOcclusion(visible: Bool) {
        guard isOpen else { return }
        lastOcclusionNotice = visible
        wiring?.store.windowOcclusionDidChange(visible: visible)
    }

    /// 창이 앞으로 왔다. 의도를 맞춘다(다른 경로로 창이 올라온 경우에도 `isOpen` 이 사실과 갈리지 않게).
    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        isOpen = true
    }

    /// 크기 고정의 마지막 문.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === windowStorage else { return frameSize }
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
    }

    /// 확대 거부(버튼은 비활성이지만 ⌥클릭·접근성 경로가 남아 있다).
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    /// 스토어에 표시 상태를 알린다. '보임'은 열 때마다(재조회의 문), '안 보임'은 보이던 때만 한 번.
    private func notifyVisibility(_ visible: Bool) {
        if !visible, lastVisibilityNotice != true { return }
        lastVisibilityNotice = visible
        guard let store = wiring?.store else { return }
        if visible {
            store.windowDidShow()
        } else {
            store.windowDidHide()
        }
    }

    // MARK: - 창이 화면에 못 올라갔을 때의 복구

    static let stuckWindowCheckSeconds: Double = 0.5
    static let maxStuckWindowRebuilds = 3

    private var stuckWindowWatchdog: Task<Void, Never>?
    private(set) var stuckWindowRebuilds = 0

    /// `makeKeyAndOrderFront` 도 조용히 실패할 수 있다(v0.2.27 실측). 통한 복구는 창을 버리고 새로 만드는 것뿐이었다.
    private func armStuckWindowWatchdog() {
        stuckWindowWatchdog?.cancel()
        let delay = stuckWindowCheckSeconds
        stuckWindowWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isOpen,
                  let stuck = self.windowStorage, Self.isOnScreen(stuck) == false
            else { return }
            self.rebuildStuckWindow()
        }
    }

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 대국 상태는 스토어에 있으므로 잃는 것이 없다.
    func rebuildStuckWindow() {
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        // 델리게이트를 먼저 뗀다 — close() 의 windowWillClose 가 우리에게 오면 새 창을 세우는 도중 의도가 뒤집힌다.
        old.delegate = nil
        old.contentView = nil
        // ★ 자동저장 이름을 반드시 놓아준다(안 풀면 재생성된 창이 자리를 영영 저장하지 못한다).
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        old.close()
        windowStorage = nil
        show()
    }

    /// 이 창이 지금 **실제로** 화면에 올라가 있는가를 창 서버에 직접 묻는다(판정은 한 벌만 둔다).
    static func isOnScreen(_ window: NSWindow) -> Bool? {
        CheckTodoBoardController.isOnScreen(window)
    }

    /// 지금 창의 상태를 한 줄로(진단·사후 분석용).
    var diagnosticState: String {
        guard let windowStorage else { return "window=none isOpen=\(isOpen) rebuilds=\(stuckWindowRebuilds)" }
        let onScreen = Self.isOnScreen(windowStorage).map(String.init(describing:)) ?? "unknown"
        let f = windowStorage.frame
        return "window=\(windowStorage.windowNumber) isOpen=\(isOpen) isVisible=\(windowStorage.isVisible)"
            + " onScreen=\(onScreen) alpha=\(windowStorage.alphaValue) autosave=\(frameAutosaveActive)"
            + " frame=\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))"
            + " rebuilds=\(stuckWindowRebuilds)"
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다. 한 프로세스에서 컨트롤러를 여럿 만들면
    /// 먼저 만든 창이 이름을 쥐고 있어 다음 창의 `frameAutosaveActive` 가 거짓이 된다(재생성 경로와 같은 정리).
    func discardWindowForTesting() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        guard let old = windowStorage else { return }
        old.delegate = nil
        old.contentView = nil
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        old.close()
        windowStorage = nil
    }
    #endif
}

// MARK: - 로그아웃·계정 전환 감시

/// 로그인한 사용자 id 가 **바뀌는 순간**(로그아웃 = nil, 계정 전환 = 다른 id)만 지켜보다가 오목 창을 닫는다.
///
/// 왜 필요한가: 오목 상태 리셋은 core 가 `WorkTimerStore` 로그아웃 경로에서 `gomoku.reset()` 으로 하지만,
/// 창은 ui 쪽 수명이다. 깃발만 비우면 **내용이 빈 창이 화면에 남고**, 다음 사람이 앞 계정의 판을 본다.
/// 스토어에 콜백 구멍을 뚫지 않고 `@Observable` 값 하나를 뒤에서 추적한다(`TodoDisableWatcher` 와 같은 수법).
@MainActor
final class GomokuAccountWatcher {
    private let userID: @MainActor () -> String?
    private let onChange: @MainActor () -> Void
    private var lastUserID: String?

    init(userID: @escaping @MainActor () -> String?, onChange: @escaping @MainActor () -> Void) {
        self.userID = userID
        self.onChange = onChange
        lastUserID = userID()
    }

    /// 감시를 건다. 등록된 onChange 가 자신을 강하게 붙들기 때문에 호출자가 수명을 들 필요가 없다.
    func start() { arm() }

    private func arm() {
        withObservationTracking {
            _ = userID()
        } onChange: { [self] in
            // onChange 는 값이 바뀌기 **직전**(willSet)에 온다 — 한 틱 뒤 메인 액터에서 새 값을 읽는다.
            Task { @MainActor in self.applyThenRearm() }
        }
    }

    private func applyThenRearm() {
        let current = userID()
        if current != lastUserID {
            lastUserID = current
            onChange()
        }
        arm()
    }
}
