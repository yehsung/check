import AppKit
import SwiftUI
import CheckCore

// MARK: - 1:1 알까기 창 (SPEC v1.1 §5.1)
//
// 1240×700 고정 창 하나를 재사용한다(닫아도 파괴하지 않는다 · 닫으면 화면을 내리고 다시 열 때 새로 담는다 — 0.3.80 그대로).
// 길건너 창(`CheckCrossyDuelWindow.swift`)에서 옮긴 것:
//   · **첫 클릭을 받는다**(DF#83): contentView = `CrossyDuelHostingView`(`acceptsFirstMouse → true`). 메뉴바 앱이라 사람은 늘 다른
//     앱에서 온다 — 비활성 창의 첫 클릭이 '창 앞으로'에 먹히면 판을 누른 손이 빈다.
//   · **고착 감시 재생성**(0.5초 · 3회): 화면에 못 올라간 창을 버리고 새로 만든다(판은 스토어에 있어 잃는 것이 없다).
//   · **보임 통지는 이 컨트롤러만 한다**(DF#46): show · 최소화 · 되살림 · 닫기 통지에서만 `windowDidShow`/`windowDidHide`.
//     패널이 `onAppear`/`onDisappear` 로 부르면 로비↔판 전환마다 불려 `isWindowVisible` 이 거짓으로 남을 수 있다.
//   · **닫기 ≠ 기권**: 키를 잃거나 닫혀도 판은 끝나지 않는다(서버가 30초 · 세 번 규칙으로 판정) — `windowDidResignKey` 가 없는 것이 계약.
@MainActor
final class CheckAlkkagiWindowController: NSObject, NSWindowDelegate {
    /// 이 창이 선 화면의 주사율 — 판 걸음 간격의 재료(길건너 1:1 과 같은 꼴: 창마다 자기 감시, 공용 값을 덮지 않는다).
    let frameRateMonitor = MiniGameFrameRateMonitor()
    /// 디스플레이 설정이 바뀌면(주사율 변경) 다시 읽는다 — 창 이동(`windowDidChangeScreen`)만 보면 절반을 놓친다.
    private var screenParametersObserver: NSObjectProtocol?
    static let shared = CheckAlkkagiWindowController()
    /// 창 제목(SPEC §1 — "1:1 알까기"). CGWindowList 로 밖에서 창을 셀 때의 표식이다. 게임 이름 한 곳에서 온다.
    static let windowTitle = AlkkagiText.gameName
    static let frameAutosaveName = "check.alkkagi.window"
    static let fixedContentSize = BoardGameLayout.contentSize

    private var windowStorage: NSWindow?
    private var onlineStore: AlkkagiOnlineStore?
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳. 약참조다(스토어 수명은 앱이 쥔다).
    private weak var safety: WorkTimerStore?
    /// 마지막으로 보인 연습 창의 나(재생성 때 같은 화면을 다시 담는다).
    private var lastMe = AlkkagiPlayerProfile(name: "플레이어 1")
    private(set) var isOpen = false
    var currentWindow: NSWindow? { windowStorage }
    var onClosed: (@MainActor (_ byUser: Bool) -> Void)?
    /// 스토어에 마지막으로 알린 표시 상태(true = windowDidShow, false = windowDidHide).
    private(set) var lastVisibilityNotice: Bool?
    /// 스토어에 마지막으로 알린 가림 상태.
    private(set) var lastOcclusionNotice: Bool?
    private(set) var frameAutosaveActive = false

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckAlkkagiWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    /// 앱 시작 시 1회(T 배선). `safety` 는 창 루트의 아바타 캐릭터 표(뒤집기·길건너 창과 같은 짝).
    func configure(store: AlkkagiOnlineStore, safety: WorkTimerStore? = nil) {
        onlineStore = store
        self.safety = safety
    }

    func show(me: AlkkagiPlayerProfile = AlkkagiPlayerProfile(name: "플레이어 1")) {
        lastMe = me
        let window: NSWindow
        if let windowStorage {
            window = windowStorage
        } else {
            window = Self.makeWindow()
            window.delegate = self
            if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
            // 반환값을 버리지 않는다 — 이름 충돌이면 false 이고 자리 저장이 조용히 죽는다.
            frameAutosaveActive = window.setFrameAutosaveName(Self.frameAutosaveName)
            windowStorage = window
        }
        if !isOpen || window.contentView == nil {
            window.contentView = makeContent(me: me)
        }
        window.setContentSize(Self.fixedContentSize)
        frameRateMonitor.update(for: window)
        if screenParametersObserver == nil {
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.frameRateMonitor.update(for: self?.windowStorage) }
            }
        }
        if !CheckPanelVisibility.isRunningTests { NSApp.activate() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        isOpen = true
        window.makeKeyAndOrderFront(nil)
        notifyVisibility(true)
        armStuckWindowWatchdog()
    }

    /// 담을 화면 — 온라인 스토어가 있으면 창 루트 패널, 없으면(시험 · 독립 연습) 판 화면 하나. 첫 클릭을 받는 호스팅 뷰.
    private func makeContent(me: AlkkagiPlayerProfile) -> NSView {
        let hosting: NSView
        if let onlineStore {
            var panel = AlkkagiOnlinePanel(store: onlineStore, safety: safety)
            panel.frameRateMonitor = frameRateMonitor
            hosting = CrossyDuelHostingView(rootView: panel)
        } else {
            var game = AlkkagiGameView(onReturn: { [weak self] in
                self?.closeFromUser()
            }, me: me)
            game.frameRateMonitor = frameRateMonitor
            hosting = CrossyDuelHostingView(rootView: game)
        }
        hosting.autoresizingMask = [.width, .height]
        return hosting
    }

    /// 로그아웃과 계정 전환은 목록을 다시 열지 않는다. 숨은 게임의 타이머도 함께 거둔다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        guard isOpen else { return }
        windowStorage?.orderOut(nil)
        isOpen = false
        windowStorage?.contentView = nil
        notifyVisibility(false)
        onClosed?(false)
    }

    /// 화면의 돌아가기 버튼도 빨간 점과 같은 닫기 통지를 거친다.
    func closeFromUser() {
        guard isOpen else { return }
        windowStorage?.performClose(nil)
    }

    /// 빨간 점. '안 보임'과 **'닫혔다'**를 알린다 — 기권이 아니다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage, isOpen else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        windowStorage?.contentView = nil
        lastVisibilityNotice = false
        onlineStore?.windowDidClose()
        onClosed?(true)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        notifyVisibility(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        if isOpen { notifyVisibility(true) }
    }

    func windowDidChangeScreen(_ notification: Notification) { frameRateMonitor.update(for: windowStorage) }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        applyOcclusion(visible: window.occlusionState.contains(.visible))
    }

    /// 가림 판정을 스토어로 옮긴다(헤드리스 검증 문).
    func applyOcclusion(visible: Bool) {
        guard isOpen else { return }
        lastOcclusionNotice = visible
        onlineStore?.windowOcclusionDidChange(visible: visible)
    }

    /// 보임 통지 한 곳. 안 보임은 보인 적이 있을 때만(두 번 알리지 않는다).
    private func notifyVisibility(_ visible: Bool) {
        if !visible, lastVisibilityNotice != true { return }
        lastVisibilityNotice = visible
        if visible {
            onlineStore?.windowDidShow()
        } else {
            onlineStore?.windowDidHide()
        }
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = fixedContentSize
        window.contentMaxSize = fixedContentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 창이 화면에 못 올라갔을 때의 복구(길건너 창과 같은 꼴)

    static let stuckWindowCheckSeconds: Double = 0.5
    static let maxStuckWindowRebuilds = 3

    private var stuckWindowWatchdog: Task<Void, Never>?
    private(set) var stuckWindowRebuilds = 0

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

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 판은 스토어에 있으므로 잃는 것이 없다.
    func rebuildStuckWindow() {
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        old.delegate = nil
        old.contentView = nil
        // ★ 자동저장 이름을 반드시 놓아준다(안 풀면 재생성된 창이 자리를 영영 저장하지 못한다).
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        old.close()
        windowStorage = nil
        isOpen = false
        show(me: lastMe)
    }

    static func isOnScreen(_ window: NSWindow) -> Bool? {
        CheckTodoBoardController.isOnScreen(window)
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다(길건너 창과 같은 규약).
    func discardWindowForTesting() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        if let screenParametersObserver { NotificationCenter.default.removeObserver(screenParametersObserver) }
        screenParametersObserver = nil
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
