import AppKit
import SwiftUI
import CheckCore

// MARK: - 1:1 길건너 창 (SPEC v1.3 §9.1)
//
// `CheckTetrisDuelWindow.swift` 의 **형제**다(지연 생성 · 멱등 `show()` · 고정 크기 · `.resizable` 없음 · `.miniaturizable` ·
// `hidesOnDeactivate=false` · darkAqua · 고착 감시 재생성 3회 · 테스트 알파 0 · 최소화는 '안 보임' · 닫기와 최소화를 다른 통지로 ·
// `close()→onClosed?(false)` · 빨간 점 `windowWillClose→onClosed?(true)`). 길건너에서 달라지는 것:
//
//   · **`windowDidResignKey` 가 없다**(키를 잃어도 판은 흐른다 — 판은 스토어의 단조 시계로 돈다, 테트리스 D10 과 같은 까닭).
//   · **첫 클릭을 받는다**(v1.1 CC-16): contentView = `CrossyDuelHostingView`(`acceptsFirstMouse → true`). 메뉴바 앱이라 사람은
//     늘 다른 앱에서 온다 — 비활성 창의 첫 클릭이 '창 앞으로'에 먹히면 "클릭 = 앞으로" 가 빈다(마작 선례).
//   · **자기 프레임 상한 재료**(v1.1 CC-5): 공용 `MiniGameFrameRateMonitor.shared` 는 미니게임 창만 갱신한다 — 미니게임 창을 안 연
//     세션이면 폴백 60 이라 75·144Hz 화면에서 규칙적 저더가 난다. 그래서 이 컨트롤러가 **자기** 모니터를 들고
//     `show()`·`windowDidChangeScreen`·화면 구성 변경에서 `update(for:)` 한다(공용 값을 쓰면 다른 화면의 미니게임 창과 서로 덮는다).
//   · **전용 로컬 키 모니터**(`CrossyDuelKeys`): 게이트는 "키가 향한 창 === 이 창" 하나 · 갈아 끼우기 설치 · 뛰기 표는
//     `MiniGameSpaceKey.hopDirection(forKeyCode:)` 재사용 · **스페이스(49) = 앞으로**(v1.1 CC-8) · countdown·playing 동안 스페이스를
//     삼킨다(초점 단추 [기권] 연타 막기) · 키 반복은 삼키고 무시(꾹 누르기 = 자동 질주 막기) · 남의 창이면 안 삼킨다.
//   · ★ `MiniGameSpaceKey.standaloneWindowIDs` 에 이 창의 자동저장 이름을 넣는 일, `presentWindow`·`onClosed` 배선, App Nap 붙들기
//     (`CrossyDuelActivityHold`)를 스토어 신호에 잇는 일은 통합 갈래(T)가 `CheckApp`·`MiniGamePanel` 에서 한다(§9.5).

/// 1:1 길건너 창의 **고정** 레이아웃(v1.2 — Q2 답 C 경주 트랙). 순수 상수 — 창 크기를 두 곳에 적지 않는다.
///
/// 화면은 두 가지다.
///   · 대결(준비·카운트다운·판·결과) = 경주 트랙 띠(44) 아래 두 열 [캔버스 344 | 오른쪽 256].
///   · 로비 = 두 열 [사람·순위 탭 360 | 오른쪽 240(내 전적 · 받은/보낸 신청 · 규칙 요약)].
///
/// ── 숫자의 근거 ──
///  · `canvasSize 344×356` — **솔로 미니게임 캔버스와 같은 상수**다(`MiniGameWindowLayout.canvasSize`). 3D 구도·렌더 시험
///    '아잉이 52~60pt' 가 그대로 산다(MX:149).
///  · 본문 높이 = 띠 44 + 간격 12 + 캔버스 356 = **412**. 창 높이 = 여백 20×2 + 머리글 40 + 간격 12 + 412 = **504**.
///  · 폭 = 여백 20×2 + 캔버스 344 + 열 간격 20 + 오른쪽 256 = **660**. 로비도 같은 본문(360 + 20 + 240 = 620).
enum CrossyDuelWindowLayout {
    static let contentPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let headerHeight: CGFloat = 40
    static let headerSpacing: CGFloat = 12

    /// 내 판 캔버스 — 솔로와 **같은 상수 한 벌**을 읽는다.
    static var canvasSize: CGSize { MiniGameWindowLayout.canvasSize }

    // MARK: 대결 화면
    /// 경주 트랙 띠(SPEC §9.2 — 카드 모양 44pt).
    static let raceBandHeight: CGFloat = 44
    static let raceBandSpacing: CGFloat = 12
    static let sideColumnWidth: CGFloat = 256
    static let sideSpacing: CGFloat = 12
    static let actionRowHeight: CGFloat = 34
    static let cardPadding: CGFloat = 14

    static var bodyHeight: CGFloat { raceBandHeight + raceBandSpacing + canvasSize.height }
    /// 띠 아래 두 열이 쓰는 높이(= 캔버스 높이).
    static var matchColumnHeight: CGFloat { canvasSize.height }

    // MARK: 로비 두 열
    static let lobbyListWidth: CGFloat = 360
    static var lobbySideWidth: CGFloat { innerWidth - columnSpacing - lobbyListWidth }
    static let lobbyTabHeight: CGFloat = 28
    static let lobbyRowHeight: CGFloat = 52
    static let lobbyRowSpacing: CGFloat = 6
    static let lobbySideSpacing: CGFloat = 12
    static let lobbyRecordHeight: CGFloat = 64
    static let invitesTitleHeight: CGFloat = 20
    static let outgoingLineHeight: CGFloat = 30
    static let invitesSpacing: CGFloat = 8
    static let stakePromptWidth: CGFloat = 320

    static var innerWidth: CGFloat { canvasSize.width + columnSpacing + sideColumnWidth }
    /// 창 콘텐츠 크기(고정 660×504). 컨트롤러의 min/max 도 이 값 하나를 쓴다.
    static var contentSize: CGSize {
        CGSize(width: innerWidth + contentPadding * 2,
               height: contentPadding * 2 + headerHeight + headerSpacing + bodyHeight)
    }

    /// 창 콘텐츠 좌표에서의 캔버스 사각형(대결 화면). 레이아웃 상수에서만 나온다 — 시험이 **실제 호스팅 레이아웃**과 견준다.
    static var canvasRect: CGRect {
        CGRect(x: contentPadding,
               y: contentPadding + headerHeight + headerSpacing + raceBandHeight + raceBandSpacing,
               width: canvasSize.width, height: canvasSize.height)
    }

    /// 창 콘텐츠 좌표에서의 경주 트랙 띠 사각형.
    static var raceBandRect: CGRect {
        CGRect(x: contentPadding, y: contentPadding + headerHeight + headerSpacing,
               width: innerWidth, height: raceBandHeight)
    }

    /// 창 콘텐츠 좌표에서의 오른쪽 열 사각형(대결 화면).
    static var sideRect: CGRect {
        CGRect(x: canvasRect.maxX + columnSpacing, y: canvasRect.minY,
               width: sideColumnWidth, height: matchColumnHeight)
    }
}

/// 첫 클릭을 받는 호스팅 뷰(v1.1 CC-16 — 마작 `MahjongHostingView` 와 같은 한 줄).
final class CrossyDuelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 1:1 길건너 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다** —
/// 스토어의 `openWindow(focusMatchID:)` · 판 시작이 `presentWindow` 문(CheckApp 배선, T)을 거쳐 여기로 온다.
@MainActor
final class CheckCrossyDuelWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckCrossyDuelWindowController()

    /// 창 제목(SPEC §1). CGWindowList 로 밖에서 창을 셀 때의 표식이다.
    static let windowTitle = "1:1 길건너"

    /// 창 위치를 기억하는 키 = 창 식별자(SPEC §1). **다른 창과 겹치면 안 된다**(겹치면 `setFrameAutosaveName` 이 false 를 돌려주고
    /// 자리 저장이 조용히 죽는다). `MiniGameSpaceKey.standaloneWindowIDs`(T)와 키 모니터 게이트가 이 문자열을 읽는다.
    static let frameAutosaveName = "check.crossy-duel.window"

    static var fixedContentSize: NSSize {
        NSSize(width: CrossyDuelWindowLayout.contentSize.width, height: CrossyDuelWindowLayout.contentSize.height)
    }

    struct Wiring {
        let store: CrossyDuelStore
        let content: @MainActor (CrossyDuelStore) -> AnyView
    }

    private var wiring: Wiring?
    private weak var safety: WorkTimerStore?
    private var windowStorage: NSWindow?
    private var screenObserver: NSObjectProtocol?

    /// 이 창 **자기** 주사율(v1.1 CC-5). 패널이 `TimelineView` 간격과 `CrossySceneView(framesPerSecond:)` 둘 다에 쓴다.
    let frameRateMonitor = MiniGameFrameRateMonitor()

    private(set) var isOpen = false
    /// 창이 닫혔다 — `true` 면 사람이 닫았다(빨간 점 · ⌘W), `false` 면 프로그램 닫기(로그아웃 · 계정 전환). 앱 배선(T)이
    /// `duelWindowDidClose(.crossyDuel, byUser:)` 로 잇는다.
    var onClosed: (@MainActor (_ byUser: Bool) -> Void)?
    var hasWindow: Bool { windowStorage != nil }
    var currentWindow: NSWindow? { windowStorage }
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }
    private(set) var frameAutosaveActive = false
    private(set) var lastVisibilityNotice: Bool?
    private(set) var lastOcclusionNotice: Bool?

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckCrossyDuelWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. `me` 는 내 이름·캐릭터를 읽는 문이다(스토어는 상대만 든다 — 체스·테트리스와 같다).
    func configure(
        store: CrossyDuelStore,
        me: @escaping @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback },
        safety: WorkTimerStore? = nil
    ) {
        self.safety = safety
        let monitor = frameRateMonitor
        configure(store: store, content: { crossyDuel in
            AnyView(
                CrossyDuelPanel(store: crossyDuel, me: me, safety: safety)
                    .frameRate(monitor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(CheckTheme.background)
            )
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재기 위한 문). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(store: CrossyDuelStore, content: @escaping @MainActor (CrossyDuelStore) -> AnyView) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = CrossyDuelHostingView(rootView: wiring.content(wiring.store))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        if created.frame.size != created.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size {
            created.setContentSize(Self.fixedContentSize)
        }
        // 반환값을 버리지 않는다 — 이름 충돌이면 false 이고 자리 저장이 조용히 죽는다.
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        observeScreenParameters()
        return created
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            // `.resizable` 없음(고정 — 판 배율이 창 크기에 딸려 흔들리면 안 된다). `.miniaturizable` 은 넣는다 —
            // 최소화해도 판은 흐른다. 숨겨서 멈추는 이득이 없으니 치워 두는 표면으로 남겨도 된다.
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        // ★ 이 식별자가 `MiniGameSpaceKey.yieldsToOtherWindow` 와 `CrossyDuelKeys` 의 판정 재료다(머리 주석 ★).
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = fixedContentSize
        window.contentMaxSize = fixedContentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isReleasedWhenClosed = false
        // 다른 앱을 클릭해도 창은 남는다(판은 계속 흐른다).
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0. 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 열기 / 닫기

    /// 창을 연다(멱등 — 최소화돼 있으면 되살린다). 열 때마다 스토어에 '보임'을 알린다(준비 보고의 문이 여기서 열린다).
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
        frameRateMonitor.update(for: window)
        installKeys()
        notifyVisibility(true)
        armStuckWindowWatchdog()
    }

    /// 창을 내린다(멱등). **판은 끝나지 않는다** — 로그아웃·계정 전환에서도 이 문을 부른다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
        notifyVisibility(false)
        notifyClosed()
        onClosed?(false)
    }

    /// 빨간 점. '안 보임'과 **'닫혔다'**를 알린다 — 기권이 아니다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        notifyVisibility(false)
        notifyClosed()
        onClosed?(true)
    }

    /// 스토어에 **닫혔다**고 알린다 — `notifyVisibility(false)` 와 갈라 둔다(최소화는 닫기가 아니다).
    private func notifyClosed() {
        wiring?.store.windowDidClose()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        notifyVisibility(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        if isOpen { notifyVisibility(true) }
    }

    /// 가림 — 스토어에 폴링을 멈추고 시작 말풍선 문을 열라고 알린다(판은 흐른다 · `isWindowVisible` 은 그대로).
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        applyOcclusion(visible: window.occlusionState.contains(.visible))
    }

    /// 가림 판정을 스토어로 옮긴다(헤드리스 검증 문).
    func applyOcclusion(visible: Bool) {
        guard isOpen else { return }
        lastOcclusionNotice = visible
        wiring?.store.windowOcclusionDidChange(visible: visible)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        isOpen = true
    }

    /// 창이 다른 화면으로 옮겨졌다 — 주사율을 다시 읽는다(v1.1 CC-5).
    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        frameRateMonitor.update(for: window)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === windowStorage else { return frameSize }
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

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

    /// 화면 구성 변경(모니터 꽂기·주사율 바꾸기)에서도 주사율을 다시 읽는다. 창 하나에 관찰자 하나.
    private func observeScreenParameters() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.windowStorage else { return }
                self.frameRateMonitor.update(for: window)
            }
        }
    }

    /// 이 창 전용 키 모니터를 건다(멱등 — 이미 이 창에 걸려 있으면 그대로 둔다).
    private func installKeys() {
        guard !CrossyDuelKeys.isInstalled(for: self) else { return }
        CrossyDuelKeys.install(owner: self,
                               window: { [weak self] in self?.windowStorage },
                               store: { [weak self] in self?.wiring?.store })
    }

    // MARK: - 창이 화면에 못 올라갔을 때의 복구

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
        show()
    }

    static func isOnScreen(_ window: NSWindow) -> Bool? {
        CheckTodoBoardController.isOnScreen(window)
    }

    var diagnosticState: String {
        guard let windowStorage else { return "window=none isOpen=\(isOpen) rebuilds=\(stuckWindowRebuilds)" }
        let onScreen = Self.isOnScreen(windowStorage).map(String.init(describing:)) ?? "unknown"
        let f = windowStorage.frame
        return "window=\(windowStorage.windowNumber) isOpen=\(isOpen) isVisible=\(windowStorage.isVisible)"
            + " onScreen=\(onScreen) alpha=\(windowStorage.alphaValue) autosave=\(frameAutosaveActive)"
            + " frame=\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))"
            + " rebuilds=\(stuckWindowRebuilds) hz=\(frameRateMonitor.refreshHz)"
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다(테트리스 창과 같은 규약).
    func discardWindowForTesting() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        if CrossyDuelKeys.isInstalled(for: self) { CrossyDuelKeys.remove() }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
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

// MARK: - 키 (이 창 전용)

/// 키 한 번 → 스토어 입력의 **순수 규칙**. NSEvent 없이 테스트가 두드린다.
///
/// 뛰기 표는 솔로와 같다(`MiniGameSpaceKey.hopDirection(forKeyCode:)` — ↑↓←→ · WASD, 물리 keyCode 라 한글 입력기에서도 같은 자리).
/// 솔로 표에 없는 **스페이스(49) = 앞으로 한 칸**을 더한다(v1.1 CC-8 — 솔로 조작 "클릭 · 스페이스 · 방향키"와 같은 손).
/// 길건너는 '누르고 있는' 키가 없다(한 번 = 한 칸) — 래치·굳은 키 그물이 필요 없다.
enum CrossyDuelKeyRule {
    enum Command: Equatable {
        case hop(CrossyGame.Direction)
        case forward
    }

    /// 키 사건 하나. `belongs` = 키가 향한 창이 대결 창인가, `live` = 판 입력을 받는 흐름인가(카운트다운·판 중).
    /// 반환: 삼키는가(nil 을 돌려 AppKit 에 안 흘린다) · 스토어로 보낼 입력(없으면 nil).
    static func handle(keyCode: UInt16, isUp: Bool, isRepeat: Bool, hasModifier: Bool,
                       belongs: Bool, live: Bool) -> (consumed: Bool, command: Command?) {
        let command: Command
        if let direction = MiniGameSpaceKey.hopDirection(forKeyCode: keyCode) {
            command = .hop(direction)
        } else if keyCode == MiniGameSpaceKey.spaceKeyCode {
            command = .forward
        } else {
            return (false, nil)
        }
        // 남의 창 · 로비 · 결과에서는 아무것도 삼키지 않는다(초점 단추·다른 창의 키를 빼앗지 않는다).
        guard belongs, live else { return (false, nil) }
        // 뗌은 뜻이 없다 — 이 창으로 간 뗌만 삼킨다(누름을 삼키고 뗌을 흘리면 짝 잃은 뗌이 남의 손에 간다).
        if isUp { return (true, nil) }
        guard !hasModifier else { return (false, nil) }
        // 키 반복은 삼키기만 한다 — 꾹 누르기가 자동 질주가 되지 않게(솔로 계약 T/V0367CrossyTests 와 같은 뜻).
        guard !isRepeat else { return (true, nil) }
        return (true, command)
    }

    /// 입력 한 건을 스토어로(스토어는 판 중이 아니면 버린다 — 카운트다운엔 삼키기만 하고 판은 안 움직인다).
    @MainActor
    static func send(_ command: Command?, to store: CrossyDuelStore?) {
        guard let command, let store else { return }
        switch command {
        case .hop(let direction): store.hop(direction)
        case .forward: store.forward()
        }
    }
}

/// 1:1 길건너 창의 로컬 키 모니터(앱 하나에 하나). **전역 모니터가 아니다** — 전역 모니터는 우리 앱이 활성일 때 눈이 먼다.
@MainActor
enum CrossyDuelKeys {
    nonisolated(unsafe) private static var token: Any?
    private static weak var owner: AnyObject?

    static var isInstalled: Bool { token != nil }

    static func isInstalled(for candidate: AnyObject) -> Bool {
        token != nil && owner === candidate
    }

    /// 판 입력을 받는 화면 흐름(카운트다운에도 삼킨다 — 시작 직전 스페이스가 초점 단추를 누르지 않게. 입력 자체는 스토어가 버린다).
    static func isLive(_ store: CrossyDuelStore?) -> Bool {
        guard let phase = store?.phase else { return false }
        return phase == .playing || phase == .countdown
    }

    /// 건다(이미 걸려 있으면 갈아 끼운다 — 죽은 화면의 클로저를 쥔 모니터가 남지 않게).
    static func install(owner newOwner: AnyObject,
                        window: @escaping @MainActor () -> NSWindow?,
                        store: @escaping @MainActor () -> CrossyDuelStore?) {
        remove()
        owner = newOwner
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let isUp = event.type == .keyUp
            let keyCode = event.keyCode
            let hasModifier = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let isRepeat = isUp ? false : event.isARepeat
            // 창은 번호로 넘긴다 — NSEvent 를 메인 액터 클로저로 보내면 Swift 6 가 데이터 경쟁으로 막는다.
            let windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated { () -> Bool in
                let target = store()
                let belongs = MiniGameSpaceKey.strokeBelongsToGame(NSApp.window(withWindowNumber: windowNumber),
                                                                   gameWindow: window())
                let result = CrossyDuelKeyRule.handle(keyCode: keyCode, isUp: isUp, isRepeat: isRepeat,
                                                      hasModifier: hasModifier, belongs: belongs, live: isLive(target))
                CrossyDuelKeyRule.send(result.command, to: target)
                return result.consumed
            }
            return consumed ? nil : event
        }
    }

    static func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        owner = nil
    }

    #if DEBUG
    /// 테스트 전용: 합성 NSEvent 없이 모니터의 판정을 그대로 밟는다(창·팝오버는 합성 이벤트로 열리지 않는다).
    @discardableResult
    static func handleForTesting(keyCode: UInt16, isUp: Bool, isRepeat: Bool = false, hasModifier: Bool = false,
                                 eventWindow: NSWindow?, duelWindow: NSWindow?, store: CrossyDuelStore?) -> Bool {
        let belongs = MiniGameSpaceKey.strokeBelongsToGame(eventWindow, gameWindow: duelWindow)
        let result = CrossyDuelKeyRule.handle(keyCode: keyCode, isUp: isUp, isRepeat: isRepeat, hasModifier: hasModifier,
                                              belongs: belongs, live: isLive(store))
        CrossyDuelKeyRule.send(result.command, to: store)
        return result.consumed
    }
    #endif
}
