import AppKit
import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 창 (v0.3.69)
//
// 계약은 설계서 §5: 테트리스 창(`CheckTetrisDuelWindow.swift`) 계약 그대로 — 지연 생성 · 멱등 show · 닫아도 파괴 안 함 ·
// 고정 크기 **1240×700**(오목·체스와 같은 13" 상한) · .darkAqua · `CheckPanelVisibility.panelAlpha`(테스트 알파 0) ·
// 고착 감시자 + 재생성 상한 3 · 닫기와 최소화/가림을 **다른 통지**로.
// 테트리스와 달라지는 것.
//   · **키 모니터가 없다.** 판은 마우스 끌기로만 움직인다 — 미니게임 창의 스페이스 모니터와 다툴 키가 없다.
//   · 스토어 통지 문이 둘이다: `setWindowVisible(_:)`(보임/안 보임 — 열기·닫기·최소화) · `setWindowOccluded(_:)`(가림 —
//     폴링만 멈춘다). 최소화·가림은 '안 보임'일 뿐 판은 서버 시계로 흐른다.
//   · **사람이 누른 닫기(빨간 점 · ⌘W)는 의도적 이탈이다**(2판 §3 ⑨ — `windowShouldClose`). 판 중이면 "창을 닫으면 기권돼요"
//     확인 → `leaveForExit(.windowClosed)`, 방 손님은 묻지 않고 나가고, 방장은 "방이 닫혀요" 확인. 판단은
//     `RummyExitPolicy.closeDecision`, 확인 덮개는 패널 안(`RummyExitPrompt` 를 환경으로 받는다). 프로그램이 내리는
//     `close()`(로그아웃 정리·계정 전환)는 이 문을 거치지 않는다.
//   · 창이 키를 잃어도 아무것도 하지 않는다(`windowDidResignKey` 가 없는 것이 계약이다).
// 루트는 `RummyPanel(store:me:safety:)` + `.checkTooltipLayer().appUserAvatarCharacters(from: safety)`(패널 안에 있다).

/// 아잉 큐브 창의 **고정** 레이아웃. 순수 상수 — 창 크기를 두 곳에 적지 않는다.
///
/// 화면은 셋이다.
///   · 로비·방 = 두 열 [사람·순위 탭 440 | 오른쪽 740(탁자 — 새 탁자 또는 내 탁자 · 받은 초대 + 공개 방 한 줄)].
///   · 판 = 위 자리 띠 72 · 가운데 판 356 · 아래 랙 칸 160(상태 줄 22 + 간격 8 + 랙 카드 130).
///   · 결과 = 판 자리에 등수 카드.
///
/// ── 숫자의 근거 ──
///  · 폭 1240 · 높이 700 — 오목·체스 창과 같은 고정 크기(13" 작업 영역 상한). 안쪽 = 1200 × 608.
///  · 랙 카드 130 = 여백 10×2 + 랙 두 줄(52×2 + 6) — 랙 타일 38×52(설계서 §5).
///  · 판 356 = 본문 608 − 자리 띠 72 − 간격 10×2 − 아래 칸 160. 판 타일 32×44, 세트 높이 54(위아래 여백 5) + 줄 간격 10 이라
///    여백 12×2 를 빼고 다섯 줄(5×54 + 4×10 = 310)이 든다. 넘치면 세로 스크롤.
///  · 랙 한 줄 = (랙 폭 − 여백) / 42 = 22장, 두 줄 44장. 넘치면 가로 스크롤.
enum RummyWindowLayout {
    static let contentPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let headerHeight: CGFloat = 40
    static let headerSpacing: CGFloat = 12

    static let innerWidth: CGFloat = 1200
    static let bodyHeight: CGFloat = 608

    /// 창 콘텐츠 크기(고정). 컨트롤러의 min/max 도 이 값 하나를 쓴다.
    static var contentSize: CGSize {
        CGSize(width: innerWidth + contentPadding * 2,
               height: contentPadding * 2 + headerHeight + headerSpacing + bodyHeight)
    }

    // MARK: 로비 두 열
    static let lobbyListWidth: CGFloat = 440
    static var lobbySideWidth: CGFloat { innerWidth - columnSpacing - lobbyListWidth }
    static let lobbyTabHeight: CGFloat = 28
    static let lobbyRowHeight: CGFloat = 52
    static let lobbyRowSpacing: CGFloat = 6
    static let cardPadding: CGFloat = 14
    static let sideSpacing: CGFloat = 12
    /// 받은 초대 + 공개 방 카드 한 줄의 높이(카드 셋이 한 줄에 든다 — 넘치면 가로 스크롤).
    static let joinCardHeight: CGFloat = 176
    static var joinCardWidth: CGFloat { (lobbySideWidth - sideSpacing * 2) / 3 }
    /// 받을 것이 없을 때의 한 줄(빈 카드 대신).
    static let joinEmptyHeight: CGFloat = 44
    /// 탁자 카드 = 나머지(받을 것이 없으면 그만큼 커진다).
    static func tableCardHeight(hasJoinables: Bool) -> CGFloat {
        bodyHeight - (hasJoinables ? joinCardHeight : joinEmptyHeight) - sideSpacing
    }
    /// 탁자 그림(둥근 판 + 의자 넷)이 차지하는 높이 — 위·아래 의자가 판 가장자리에 18pt 걸친다.
    static let tableStageHeight: CGFloat = 280

    // MARK: 판
    static let seatBarHeight: CGFloat = 72
    static let sectionSpacing: CGFloat = 10
    static let statusLineHeight: CGFloat = 22
    static let statusSpacing: CGFloat = 8
    static let rackCardPadding: CGFloat = 10
    static let actionColumnWidth: CGFloat = 236
    static let actionButtonHeight: CGFloat = 34

    static var rackAreaHeight: CGFloat {
        RummyRackGeometry.tile.height * CGFloat(RummyRackGeometry.rows)
            + RummyRackGeometry.rowSpacing * CGFloat(RummyRackGeometry.rows - 1)
    }
    static var rackCardHeight: CGFloat { rackAreaHeight + rackCardPadding * 2 }
    static var bottomHeight: CGFloat { statusLineHeight + statusSpacing + rackCardHeight }
    static var boardHeight: CGFloat { bodyHeight - seatBarHeight - sectionSpacing * 2 - bottomHeight }
    static let boardPadding: CGFloat = 12
    static var boardContentWidth: CGFloat { innerWidth - boardPadding * 2 }
    /// 랙이 보이는 폭(가로 스크롤의 창).
    static var rackViewportWidth: CGFloat { innerWidth - actionColumnWidth - columnSpacing - rackCardPadding * 2 }

    // MARK: 결과
    static let resultRowHeight: CGFloat = 92
    static let resultRowSpacing: CGFloat = 10
}

/// 아잉 큐브 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다** —
/// 스토어의 `openWindow(focusMatchID:)` · 판 시작·내 차례가 `presentWindow` 문(CheckApp 배선)을 거쳐 여기로 온다.
@MainActor
final class CheckRummyWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckRummyWindowController()

    /// 창 제목(§1). CGWindowList 로 밖에서 창을 셀 때의 표식이다.
    static let windowTitle = "아잉 큐브"

    /// 창 위치를 기억하는 키 = 창 식별자(§1). **다른 창과 겹치면 안 된다**(겹치면 `setFrameAutosaveName` 이 false 를
    /// 돌려주고 자리 저장이 조용히 죽는다).
    static let frameAutosaveName = "check.rummy.window"

    static var fixedContentSize: NSSize {
        NSSize(width: RummyWindowLayout.contentSize.width, height: RummyWindowLayout.contentSize.height)
    }

    struct Wiring {
        let store: RummyStore
        let content: @MainActor (RummyStore) -> AnyView
    }

    private var wiring: Wiring?
    private weak var safety: WorkTimerStore?
    /// 창 닫기 확인(패널 안 덮개)의 상태 — 패널이 환경으로 받는다.
    let exitPrompt = RummyExitPrompt()
    /// 마지막 닫기 판단(헤드리스 검증 문).
    private(set) var lastCloseDecision: RummyCloseDecision?
    private var windowStorage: NSWindow?

    private(set) var isOpen = false
    var hasWindow: Bool { windowStorage != nil }
    var currentWindow: NSWindow? { windowStorage }
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }
    private(set) var frameAutosaveActive = false
    /// 스토어에 마지막으로 보낸 보임 통지(헤드리스 검증 문).
    private(set) var lastVisibilityNotice: Bool?
    /// 스토어에 마지막으로 보낸 가림 통지(true = 가려짐).
    private(set) var lastOcclusionNotice: Bool?

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckRummyWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. `me` 는 내 이름·캐릭터를 읽는 문이다(테트리스와 같은 타입). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(
        store: RummyStore,
        me: @escaping @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback },
        safety: WorkTimerStore? = nil
    ) {
        self.safety = safety
        let prompt = exitPrompt
        configure(store: store, content: { rummy in
            AnyView(
                RummyPanel(store: rummy, me: me, safety: safety)
                    .environment(prompt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(CheckTheme.background)
            )
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재기 위한 문). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(store: RummyStore, content: @escaping @MainActor (RummyStore) -> AnyView) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = NSHostingView(rootView: wiring.content(wiring.store))
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
        return created
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            // `.resizable` 없음(고정 — 판·랙 배치가 창 크기에 딸려 흔들리면 끌던 자리가 바뀐다).
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
        // 다른 앱을 클릭해도 창은 남는다(판은 서버 시계로 계속 흐른다).
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0. 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 열기 / 닫기

    /// 창을 연다(멱등 — 최소화돼 있으면 되살린다). 열 때마다 스토어에 '보임'을 알린다(창 밖 폴링의 문이 여기서 열린다).
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

    /// 창을 내린다(멱등). **판은 끝나지 않는다** — 로그아웃·계정 전환에서도 이 문을 부른다.
    func close() {
        exitPrompt.cancel()
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
        notifyVisibility(false)
    }

    /// 사람이 누른 닫기(빨간 점 · ⌘W)만 온다 — `close()`(orderOut)는 여기를 거치지 않는다.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === windowStorage, let store = wiring?.store else { return true }
        return requestClose(store: store)
    }

    /// 닫기 판단을 실행한다(헤드리스 검증 문). true = 지금 닫는다, false = 패널 안 확인을 띄웠다.
    @discardableResult
    func requestClose(store: RummyStore) -> Bool {
        let decision = RummyExitPolicy.closeDecision(for: store)
        lastCloseDecision = decision
        switch decision {
        case .close:
            return true
        case .leaveRoom:
            // 묻지 않는 나가기 — 그새 판이 시작됐으면 기권을 보내지 않고 판을 든다(`leaveRoomForExit`).
            Task { @MainActor in _ = await store.leaveRoomForExit(reason: .windowClosed) }
            return true
        case .confirmForfeit, .confirmCloseRoom:
            exitPrompt.ask(decision) { [weak self] in self?.confirmClose(asked: decision, store: store) }
            return false
        }
    }

    /// 확인을 골랐다. 묻던 사이 판단이 바뀌었으면(방장 확인 중 판이 시작됐다 · 판이 끝났다) **지금 판단**으로 간다 —
    /// "루비는 그대로예요" 를 읽고 고른 버튼이 판돈을 잃는 기권이 되면 안 된다. 바뀐 확인은 새 문구로 다시 묻는다.
    private func confirmClose(asked: RummyCloseDecision, store: RummyStore) {
        let now = RummyExitPolicy.closeDecision(for: store)
        lastCloseDecision = now
        switch now {
        case asked where asked == .confirmCloseRoom:
            close()
            Task { @MainActor in _ = await store.leaveRoomForExit(reason: .windowClosed) }
        case asked:
            closeAndLeave(store: store)
        case .close:
            close()
        case .leaveRoom:
            close()
            Task { @MainActor in _ = await store.leaveRoomForExit(reason: .windowClosed) }
        case .confirmForfeit, .confirmCloseRoom:
            exitPrompt.ask(now) { [weak self] in self?.confirmClose(asked: now, store: store) }
        }
    }

    /// 확인을 골랐다 — 창을 바로 내리고 이탈은 뒤에서(최대 2초, 못 닿아도 이 기기에선 판을 접는다).
    private func closeAndLeave(store: RummyStore) {
        close()
        Task { @MainActor in _ = await store.leaveForExit(reason: .windowClosed) }
    }

    /// 창이 닫혔다(사람이 닫았거나 확인 뒤). '안 보임'을 알린다 — 이탈은 위 `requestClose` 가 이미 정했다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        exitPrompt.cancel()
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        notifyVisibility(false)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        notifyVisibility(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        if isOpen { notifyVisibility(true) }
    }

    /// 가림 — 스토어에 **폴링만** 멈추라고 알린다(판은 흐른다 · 보임 통지는 그대로).
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        applyOcclusion(visible: window.occlusionState.contains(.visible))
    }

    /// 가림 판정을 스토어로 옮긴다(헤드리스 검증 문). 닫힌 창의 가림 통지는 버린다(닫기가 이미 '안 보임'을 보냈다).
    func applyOcclusion(visible: Bool) {
        guard isOpen else { return }
        let occluded = !visible
        lastOcclusionNotice = occluded
        wiring?.store.setWindowOccluded(occluded)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        isOpen = true
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === windowStorage else { return frameSize }
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    /// 보임/안 보임을 스토어로. '안 보임'은 '보임'을 보낸 적이 있을 때만 보낸다(앱 시작 직후 닫기 통지가 헛돌지 않게).
    private func notifyVisibility(_ visible: Bool) {
        if !visible, lastVisibilityNotice != true { return }
        lastVisibilityNotice = visible
        wiring?.store.setWindowVisible(visible)
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

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 판은 서버·스토어에 있으므로 잃는 것이 없다.
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
            + " rebuilds=\(stuckWindowRebuilds)"
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다(체스·테트리스 창과 같은 규약).
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
