import AppKit
import SwiftUI
import CheckCore

// MARK: - 1:1 테트리스 창 (v0.3.60)
//
// `CheckChessWindow.swift` 의 **형제**다. 규약을 그대로 베꼈다(지연 생성 · 멱등 열기 · 닫아도 파괴 안 함 · 고유 자동저장
// 이름 · 고착 감시자 + 재생성 상한 · 테스트 알파 0 · 최소화는 '안 보임' · 닫기와 최소화를 **다른 통지**로).
// 테트리스에서 달라지는 것은 셋이다.
//
//   · **창이 키를 잃어도 판을 끝내지 않는다**(`windowDidResignKey` 가 없는 것이 계약이다). 판은 스토어의 단조 시계로
//     흐르고(설계 D10) 창이 가려지거나 최소화돼도 조각은 계속 떨어진다 — 화면을 숨겨 판을 멈추는 이득이 없게 하려는
//     것이다. 솔로 미니게임 창은 키 상실을 **일시정지**로 받는다(0.3.62 — 그 전에는 판 종료였다). 여기서 멈추지
//     않는 이유는 상대가 기다리고 있다는 것이다 — 한쪽이 창을 비키면 판이 서는 대결은 상대의 시간을 인질로 잡는다.
//   · **키 모니터가 이 창 전용으로 하나 더 있다**(`TetrisDuelKeys`). 미니게임 창의 모니터(`MiniGameSpaceKey`)는 정적
//     토큰 하나라 다시 걸면 미니게임 창의 것을 빼앗는다. 그래서 따로 두고, 게이트는 "키가 향한 창 === 이 창" 하나다
//     (`isKeyWindow` 로 묻지 않는다 — 창을 막 연 순간이 죽는 그 금지는 여기서도 유효하다).
//   · ★ **`MiniGameSpaceKey.standaloneWindowIDs` 에 이 창의 자동저장 이름이 들어 있어야 한다.** 빠지면 미니게임 창을
//     띄워 둔 채 이 창에서 누른 스페이스(하드드롭)를 미니게임 모니터가 먼저 삼킨다(방향키는 미니게임 쪽이 이미 양보한다).

/// 1:1 테트리스 창의 **고정** 레이아웃. 순수 상수 — 창 크기를 두 곳에 적지 않는다.
///
/// 화면은 두 가지다.
///   · 대결(준비·카운트다운·판·결과) = 위 띠(판돈 · 경과 · 속도) 아래 세 열 [내 판 344 | 상대 220 | 오른쪽 256].
///   · 로비 = 두 열 [상대·순위 탭 440 | 오른쪽 400(내 전적 · 지금 대결 중 · 받은/보낸 신청)].
///
/// ── 숫자의 근거 ──
///  · `canvasSize 344×356` — **솔로 미니게임 캔버스와 같은 상수**다(`MiniGameWindowLayout.canvasSize`). 두 판의 배율이
///    같아야 솔로에서 익힌 손이 그대로 통한다 — 판이 커지거나 작아지면 같은 사람이 다른 게임을 하는 것이 된다.
///  · `bodyHeight` = 위 띠 34 + 간격 12 + 이름 카드 52 + 간격 8 + 캔버스 356 = **462**. 창 높이는 이 값에서 나온다
///    (여백 20×2 + 머리글 40 + 간격 12 + 462 = 554). 로비도 같은 본문 높이를 쓴다.
///  · 폭 900 = 여백 20×2 + 세 열 344 + 20 + 220 + 20 + 256. 13" 맥(1440×900 작업 영역)에 넉넉히 든다 —
///    체스 창(1240)처럼 넓을 이유가 없다: 판이 작고 기보 같은 세로 목록이 없다.
///  · 상대 열 220 — 미니 판(셀 9pt · 94×184)과 숫자 세 줄이 한 카드에 서고, 이름 카드의 긴 별명이 접히지 않는 폭.
enum TetrisDuelWindowLayout {
    static let contentPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let headerHeight: CGFloat = 40
    static let headerSpacing: CGFloat = 12

    /// 내 판 캔버스 — 솔로와 **같은 상수 한 벌**을 읽는다(위 근거).
    static var canvasSize: CGSize { MiniGameWindowLayout.canvasSize }

    // MARK: 대결 화면 세로 예산
    static let matchTopBarHeight: CGFloat = 34
    static let matchTopBarSpacing: CGFloat = 12
    static let playerCardHeight: CGFloat = 52
    static let playerCardSpacing: CGFloat = 8

    static var bodyHeight: CGFloat {
        matchTopBarHeight + matchTopBarSpacing + playerCardHeight + playerCardSpacing + canvasSize.height
    }
    /// 위 띠 아래 세 열이 쓰는 높이(= 이름 카드 + 간격 + 캔버스).
    static var matchColumnHeight: CGFloat { bodyHeight - matchTopBarHeight - matchTopBarSpacing }

    // MARK: 대결 화면 세 열
    static let opponentColumnWidth: CGFloat = 220
    /// 오른쪽 열(상태 · 결과 · 조작 안내 · [기권]). 결과 카드의 "+8" 루비와 사유 두 줄이 접히지 않는 폭.
    static let sideColumnWidth: CGFloat = 256
    static let actionRowHeight: CGFloat = 34

    // MARK: 로비 두 열
    static let lobbyListWidth: CGFloat = 440
    static var lobbySideWidth: CGFloat { innerWidth - columnSpacing - lobbyListWidth }
    static let lobbyTabHeight: CGFloat = 28
    static let lobbyRowHeight: CGFloat = 52
    static let lobbyRowSpacing: CGFloat = 6
    static let lobbySideSpacing: CGFloat = 12
    static let lobbyRecordHeight: CGFloat = 64
    static let cardPadding: CGFloat = 14
    /// 받은·보낸 신청 칸 높이 예산(여백 14×2 + 제목 20 + 받은 카드 86 + 보낸 줄 30 + 안내 두 줄 36 + 간격 8×3).
    static let invitesTitleHeight: CGFloat = 20
    static let inviteCardHeight: CGFloat = 86
    static let outgoingLineHeight: CGFloat = 30
    static let noticeLineHeight: CGFloat = 36
    static let invitesSpacing: CGFloat = 8
    static var invitesMaxHeight: CGFloat {
        cardPadding * 2 + invitesTitleHeight + inviteCardHeight + outgoingLineHeight + noticeLineHeight + invitesSpacing * 3
    }
    /// "지금 대결 중" 칸 = 나머지.
    static var lobbyLiveHeight: CGFloat {
        bodyHeight - lobbyRecordHeight - invitesMaxHeight - lobbySideSpacing * 2
    }
    /// 로비 "지금 대결 중" 한 줄의 [관전] 칩·관전자 칩 높이. **18 이어야** 줄이 얼굴(18)보다 자라지 않는다 —
    /// 체스·오목이 같은 값으로 데인 자리다(20 으로 두면 카드가 통째로 자란다).
    static let liveWatchChipHeight: CGFloat = 18
    static let stakePromptWidth: CGFloat = 340

    // MARK: 관전 화면 (v0.3.65)
    //
    // 세 열 [a 280 | b 280 | 오른쪽 260]. **두 사람 판을 나란히** 놓는 것이 이 화면의 전부다.
    // 한 열의 쌓는 차례는 **판 카드가 먼저, 이름 카드가 아래**다(명세 §4). 세로 예산은 차례와 무관하게
    // 같은 합이므로 아래 상수는 그대로 쓴다 — 창은 한 톨도 자라지 않는다(시험이 그 항등식을 되묻는다).
    // 세로 예산(462) = 판 카드 402 + 간격 8 + 이름 카드 52. 판 카드 안쪽(402 − 여백 12×2 = 378)은
    // 판 304 + 간격 10 + 숫자 세 줄(18×3 + 4×2 = 62) = 376 이라 2pt 가 남는다 — 창 시험이 이 항등식을 되묻는다.
    // 셀 15pt 를 고른 까닭: 20행이 세로 예산에 드는 가장 큰 정수 셀이다(16 이면 324 라 8pt 넘친다).

    /// 관전 판 한 칸(pt). 대결 화면의 상대 미니 판(9pt)보다 크다 — 이 화면은 판 둘이 주인공이다.
    static let spectateBoardCell: CGFloat = 15
    /// 관전 판 하나의 크기(= 154 × 304). 그림은 **기존 `TetrisBoardPainter.drawMiniBoard`** 가 그린다.
    static var spectateBoardSize: CGSize { TetrisMiniBoardLayout.boardSize(cell: spectateBoardCell) }
    static let spectateSideWidth: CGFloat = 280
    /// 오른쪽 열(판돈 · 관전자 수 · 상태 · [나가기]) = 나머지(= 260).
    static var spectateInfoWidth: CGFloat { innerWidth - spectateSideWidth * 2 - columnSpacing * 2 }
    static let spectateCardPadding: CGFloat = 12
    /// 판과 숫자 세 줄 사이.
    static let spectateBoardGap: CGFloat = 10
    static let spectateStatRowHeight: CGFloat = 18
    static let spectateStatSpacing: CGFloat = 4
    /// 숫자 세 줄(지운 줄 · 보낸 공격 · 들어올 줄)이 차지하는 높이.
    static var spectateStatsHeight: CGFloat { spectateStatRowHeight * 3 + spectateStatSpacing * 2 }
    /// 판 카드 = 이름 카드와 간격을 뺀 나머지. 이름 카드가 **아래**로 내려가도 합은 같다(차례와 무관한 값).
    static var spectateBoardCardHeight: CGFloat { bodyHeight - playerCardHeight - playerCardSpacing }
    static let spectateInfoSpacing: CGFloat = 10
    static let spectateStatusMinHeight: CGFloat = 56
    static let spectateLeaveHeight: CGFloat = 34

    static var innerWidth: CGFloat {
        canvasSize.width + opponentColumnWidth + sideColumnWidth + columnSpacing * 2
    }
    /// 창 콘텐츠 크기(고정). 컨트롤러의 min/max 도 이 값 하나를 쓴다.
    static var contentSize: CGSize {
        CGSize(width: innerWidth + contentPadding * 2,
               height: contentPadding * 2 + headerHeight + headerSpacing + bodyHeight)
    }
}

/// 1:1 테트리스 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다** —
/// 스토어의 `openWindow(focusMatchID:)` · 판 시작(`noteMatchStarted`)이 `presentWindow` 문(CheckApp 배선)을 거쳐 여기로 온다.
@MainActor
final class CheckTetrisDuelWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckTetrisDuelWindowController()

    /// 창 제목. CGWindowList 로 밖에서 창을 셀 때의 표식이다.
    static let windowTitle = "1:1 테트리스"

    /// 창 위치를 기억하는 키 = 창 식별자. **다른 창과 겹치면 안 된다**(겹치면 `setFrameAutosaveName` 이 false 를 돌려주고
    /// 자리 저장이 조용히 죽는다). `MiniGameSpaceKey.standaloneWindowIDs` 와 키 모니터 게이트가 이 문자열을 읽는다.
    static let frameAutosaveName = "check.tetris-duel.window"

    static var fixedContentSize: NSSize {
        NSSize(width: TetrisDuelWindowLayout.contentSize.width, height: TetrisDuelWindowLayout.contentSize.height)
    }

    struct Wiring {
        let store: TetrisDuelStore
        let content: @MainActor (TetrisDuelStore) -> AnyView
    }

    private var wiring: Wiring?
    private weak var safety: WorkTimerStore?
    private var windowStorage: NSWindow?

    private(set) var isOpen = false
    var hasWindow: Bool { windowStorage != nil }
    var currentWindow: NSWindow? { windowStorage }
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }
    private(set) var frameAutosaveActive = false
    private(set) var lastVisibilityNotice: Bool?
    private(set) var lastOcclusionNotice: Bool?

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckTetrisDuelWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. `me` 는 내 이름·캐릭터를 읽는 문이다(스토어는 상대만 든다 — 체스와 같다).
    func configure(
        store: TetrisDuelStore,
        me: @escaping @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback },
        safety: WorkTimerStore? = nil
    ) {
        self.safety = safety
        configure(store: store, content: { tetris in
            AnyView(
                TetrisDuelPanel(store: tetris, me: me, safety: safety)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(CheckTheme.background)
            )
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재기 위한 문). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(store: TetrisDuelStore, content: @escaping @MainActor (TetrisDuelStore) -> AnyView) {
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
            // `.resizable` 없음(고정 — 판 배율이 창 크기에 딸려 흔들리면 안 된다). `.miniaturizable` 은 넣는다 —
            // 최소화해도 판은 흐른다(D10). 숨겨서 멈추는 이득이 없으니 치워 두는 표면으로 남겨도 된다.
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        // ★ 이 식별자가 `MiniGameSpaceKey.yieldsToOtherWindow` 와 `TetrisDuelKeys` 의 판정 재료다(머리 주석 ★).
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
    }

    /// 빨간 점. '안 보임'과 **'닫혔다'**를 알린다 — 기권이 아니다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        notifyVisibility(false)
        notifyClosed()
    }

    /// 스토어에 **닫혔다**고 알린다 — `notifyVisibility(false)` 와 갈라 둔다(체스 창의 ★ 그대로: 최소화는 닫기가 아니다).
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

    /// 가림 — 스토어에 **폴링만** 멈추라고 알린다(판은 흐른다 · `isWindowVisible` 은 그대로).
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        applyOcclusion(visible: window.occlusionState.contains(.visible))
    }

    /// 가림 판정을 스토어로 옮긴다(헤드리스 검증 문). 가려지면 눌린 키도 놓는다(가려진 창은 keyUp 을 못 받는다).
    func applyOcclusion(visible: Bool) {
        guard isOpen else { return }
        lastOcclusionNotice = visible
        if !visible { TetrisDuelKeys.releaseAll(store: wiring?.store) }
        wiring?.store.windowOcclusionDidChange(visible: visible)
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

    private func notifyVisibility(_ visible: Bool) {
        if !visible, lastVisibilityNotice != true { return }
        lastVisibilityNotice = visible
        guard let store = wiring?.store else { return }
        if visible {
            store.windowDidShow()
        } else {
            TetrisDuelKeys.releaseAll(store: store)
            store.windowDidHide()
        }
    }

    /// 이 창 전용 키 모니터를 건다(멱등 — 이미 이 창에 걸려 있으면 그대로 둔다).
    private func installKeys() {
        guard !TetrisDuelKeys.isInstalled(for: self) else { return }
        TetrisDuelKeys.install(owner: self,
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
            + " rebuilds=\(stuckWindowRebuilds)"
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다(체스 창과 같은 규약).
    func discardWindowForTesting() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        if TetrisDuelKeys.isInstalled(for: self) { TetrisDuelKeys.remove() }
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

/// 키 한 번 → 스토어 입력 문들의 **순수 규칙**. NSEvent 없이 테스트가 두드린다.
///
/// 재사용하는 것: 키 표(`MiniGameSpaceKey.Stroke.key(forKeyCode:)` — 물리 keyCode, 한글 입력기에서도 같은 자리) ·
/// 래치(`MiniGameKeyLatch` — 뗌은 언제나 · 회전·홀드의 뗌은 아무 일도 안 함) · 굳은 키 그물(`TetrisKeyWatchdog` 8초).
/// 솔로와 다른 것: ESC 정지가 **없다**(대결은 멈출 수 없다) · 스페이스는 하드드롭 하나(시작은 서버가 정한다).
struct TetrisDuelKeyLatch: Equatable {
    /// 스토어로 보낼 입력 한 건.
    enum Command: Equatable {
        case left(Bool), right(Bool), softDrop(Bool)
        case rotate(clockwise: Bool)
        case hold
        case hardDrop
    }

    /// 지금 눌린 레벨 키(래치가 든다 — `MiniGameInput` 의 세 칸만 뜻이 있다).
    private(set) var input = MiniGameInput()
    /// 레벨 키가 눌리기 시작한 단조 시각(굳은 키 그물).
    private(set) var leftSince: TimeInterval?
    private(set) var rightSince: TimeInterval?
    private(set) var softSince: TimeInterval?

    /// 키 사건 하나. `belongs` = 키가 향한 창이 대결 창인가, `live` = 지금 판 입력을 받는가(카운트다운·판 중).
    /// 반환: 삼키는가(nil 을 돌려 AppKit 에 안 흘린다) · 스토어로 보낼 입력.
    mutating func handle(keyCode: UInt16, isUp: Bool, isRepeat: Bool, hasModifier: Bool,
                         belongs: Bool, live: Bool, now: TimeInterval) -> (consumed: Bool, commands: [Command]) {
        if let key = MiniGameSpaceKey.Stroke.key(forKeyCode: keyCode) {
            if isUp {
                // ★ 뗌은 게이트보다 먼저, 무조건(솔로 모니터의 ★★ 그대로) — 게이트 뒤에 두면 다른 창으로 간 뗌을 놓쳐 키가 굳는다.
                MiniGameKeyLatch.release(key, from: &input)
                restamp(now: now)
                return (belongs && live, Self.releaseCommand(key).map { [$0] } ?? [])
            }
            guard belongs, live, !hasModifier else { return (false, []) }
            // 키 반복은 삼키기만 한다 — DAS·ARR 은 엔진 시계가 만든다(OS 키 반복 속도가 승부를 가르지 않게).
            guard !isRepeat else { return (true, []) }
            MiniGameKeyLatch.apply(MiniGameSpaceKey.Stroke(key: key, isDown: true), to: &input, isFrozen: false)
            restamp(now: now)
            return (true, [Self.pressCommand(key)])
        }
        guard keyCode == MiniGameSpaceKey.spaceKeyCode, !isUp, !hasModifier, belongs, live else { return (false, []) }
        guard !isRepeat else { return (true, []) }
        return (true, [.hardDrop])
    }

    /// 8초 넘게 눌린 레벨 키를 뗀다(⌘ 를 누르는 순간 keyUp 이 사라지는 출구 — 솔로와 같은 그물).
    mutating func releaseStuck(now: TimeInterval) -> [Command] {
        var out: [Command] = []
        if input.moveLeftHeld, !TetrisKeyWatchdog.isLive(pressed: true, since: leftSince, now: now) {
            input.moveLeftHeld = false
            out.append(.left(false))
        }
        if input.moveRightHeld, !TetrisKeyWatchdog.isLive(pressed: true, since: rightSince, now: now) {
            input.moveRightHeld = false
            out.append(.right(false))
        }
        if input.softDropHeld, !TetrisKeyWatchdog.isLive(pressed: true, since: softSince, now: now) {
            input.softDropHeld = false
            out.append(.softDrop(false))
        }
        if !out.isEmpty { restamp(now: now) }
        return out
    }

    /// 전부 뗀다(창 숨김·가림 · 앱 비활성 — 그 사이 keyUp 은 오지 않는다).
    mutating func releaseAll() {
        MiniGameKeyLatch.releaseAll(&input)
        leftSince = nil
        rightSince = nil
        softSince = nil
    }

    private mutating func restamp(now: TimeInterval) {
        leftSince = TetrisKeyWatchdog.stamp(pressed: input.moveLeftHeld, since: leftSince, now: now)
        rightSince = TetrisKeyWatchdog.stamp(pressed: input.moveRightHeld, since: rightSince, now: now)
        softSince = TetrisKeyWatchdog.stamp(pressed: input.softDropHeld, since: softSince, now: now)
    }

    private static func pressCommand(_ key: MiniGameSpaceKey.GameKey) -> Command {
        switch key {
        case .moveLeft: return .left(true)
        case .moveRight: return .right(true)
        case .softDrop: return .softDrop(true)
        case .rotateCW: return .rotate(clockwise: true)
        case .rotateCCW: return .rotate(clockwise: false)
        case .hold: return .hold
        }
    }

    /// 뗌의 입력. 회전·홀드의 뗌은 아무 일도 안 한다(멱등 — 래치와 같은 규칙).
    private static func releaseCommand(_ key: MiniGameSpaceKey.GameKey) -> Command? {
        switch key {
        case .moveLeft: return .left(false)
        case .moveRight: return .right(false)
        case .softDrop: return .softDrop(false)
        case .rotateCW, .rotateCCW, .hold: return nil
        }
    }

    /// 입력 한 건을 스토어로. 스토어는 넣기 전에 판을 지금까지 민다(입력이 한 걸음 앞 시각의 판에 들어가지 않게).
    @MainActor
    static func send(_ commands: [Command], to store: TetrisDuelStore?) {
        guard let store else { return }
        for command in commands {
            switch command {
            case .left(let held): store.setLeftHeld(held)
            case .right(let held): store.setRightHeld(held)
            case .softDrop(let held): store.setSoftDropHeld(held)
            case .rotate(let clockwise): store.rotate(clockwise: clockwise)
            case .hold: store.hold()
            case .hardDrop: store.hardDrop()
            }
        }
    }
}

/// 1:1 테트리스 창의 로컬 키 모니터(앱 하나에 하나). **전역 모니터가 아니다** — 전역 모니터는 우리 앱이 활성일 때 눈이 먼다.
@MainActor
enum TetrisDuelKeys {
    nonisolated(unsafe) private static var token: Any?
    nonisolated(unsafe) private static var resignObserver: NSObjectProtocol?
    private static weak var owner: AnyObject?
    private static var latch = TetrisDuelKeyLatch()
    private static var storeProvider: (@MainActor () -> TetrisDuelStore?)?

    static var isInstalled: Bool { token != nil }

    static func isInstalled(for candidate: AnyObject) -> Bool {
        token != nil && owner === candidate
    }

    /// 판 입력을 받는 화면 흐름(카운트다운에도 삼킨다 — 시작 직전 스페이스가 초점 단추를 누르지 않게. 입력 자체는 스토어가 버린다).
    static func isLive(_ store: TetrisDuelStore?) -> Bool {
        guard let phase = store?.phase else { return false }
        return phase == .playing || phase == .countdown
    }

    /// 건다(이미 걸려 있으면 갈아 끼운다 — 죽은 화면의 클로저를 쥔 모니터가 남지 않게).
    static func install(owner newOwner: AnyObject,
                        window: @escaping @MainActor () -> NSWindow?,
                        store: @escaping @MainActor () -> TetrisDuelStore?) {
        remove()
        owner = newOwner
        storeProvider = store
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
                let result = latch.handle(keyCode: keyCode, isUp: isUp, isRepeat: isRepeat, hasModifier: hasModifier,
                                          belongs: belongs, live: isLive(target),
                                          now: ProcessInfo.processInfo.systemUptime)
                TetrisDuelKeyLatch.send(result.commands, to: target)
                return result.consumed
            }
            return consumed ? nil : event
        }
        // 앱이 뒤로 가면 그 사이 keyUp 이 오지 않는다 — 눌린 키를 놓는다(창을 숨기지 않아도 생기는 출구).
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { releaseAll(store: storeProvider?()) }
        }
    }

    static func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        owner = nil
        storeProvider = nil
        latch = TetrisDuelKeyLatch()
    }

    /// 눌린 키를 전부 놓는다(래치와 판 둘 다).
    static func releaseAll(store: TetrisDuelStore?) {
        latch.releaseAll()
        store?.releaseAllKeys()
    }

    /// 굳은 키 그물 — 판 그림의 프레임 틱이 부른다.
    static func releaseStuckKeys(store: TetrisDuelStore?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let commands = latch.releaseStuck(now: now)
        guard !commands.isEmpty else { return }
        TetrisDuelKeyLatch.send(commands, to: store)
    }

    #if DEBUG
    /// 테스트 전용: 래치가 지금 쥔 눌림·도장(굳은 키 그물의 기준 시각)을 읽는다.
    static var latchForTesting: TetrisDuelKeyLatch { latch }

    /// 테스트 전용: 합성 NSEvent 없이 모니터의 판정을 그대로 밟는다(창·팝오버는 합성 이벤트로 열리지 않는다).
    @discardableResult
    static func handleForTesting(keyCode: UInt16, isUp: Bool, isRepeat: Bool = false, hasModifier: Bool = false,
                                 eventWindow: NSWindow?, duelWindow: NSWindow?, store: TetrisDuelStore?,
                                 now: TimeInterval) -> Bool {
        let belongs = MiniGameSpaceKey.strokeBelongsToGame(eventWindow, gameWindow: duelWindow)
        let result = latch.handle(keyCode: keyCode, isUp: isUp, isRepeat: isRepeat, hasModifier: hasModifier,
                                  belongs: belongs, live: isLive(store), now: now)
        TetrisDuelKeyLatch.send(result.commands, to: store)
        return result.consumed
    }
    #endif
}
