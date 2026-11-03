import AppKit
import Observation
import SwiftUI
import CheckCore

// MARK: - 아잉 뒤집기 창 (내부 이름 reversi)
//
// `CheckChessWindow.swift` 의 **형제**다. 그 파일의 수명 규약을 통째로 베꼈고(지연 생성 · 멱등 열기 · 닫아도 파괴 안 함 ·
// 고유 자동저장 이름 · 고착 감시자 + 재생성 상한 · 테스트 알파 0 · 키를 잃어도 판은 계속 · 최소화는 '안 보임' ·
// 닫기와 최소화를 **다른 통지**로), 달라지는 것은 제목·자동저장 이름·레이아웃 enum 셋뿐이다(설계서 FLIP/SPEC.md §5.1).
//
//   · **닫기 통지(`windowDidClose`)는 `windowWillClose`·`close()` 에서만 부른다.** `notifyVisibility` 안에 넣거나
//     `windowDidMiniaturize` 에 더하면 최소화만 해도 남의 판 관전이 로비로 떨어진다(오목 0.3.42 사고).
//   · **창이 키를 잃거나 닫혀도 판은 끝나지 않는다.** 한 수 30초가 지나면 서버가 합법 수 가운데 무작위로 대신 두고,
//     연달아 세 번이면 그 사람이 진다 — 그 판정은 **서버**가 한다. 다른 앱을 잠깐 봤다고 판을 끊으면 루비가 걸린 판을
//     사용자 실수 한 번에 잃는다. 그래서 이 컨트롤러는 판 중단 신호를 **아예 모른다**(`windowDidResignKey` 가 없는 것이 계약).
//   · ★ `MiniGameSpaceKey.standaloneWindowIDs` 에 이 창의 자동저장 이름이 들어가야 미니게임 창의 전역 스페이스 모니터가
//     이 창의 키를 양보한다 — 등록은 통합 갈래(T)가 `MiniGamePanel.swift` 에서 한다.

/// 아잉 뒤집기 창의 **고정** 레이아웃. 순수 상수 — 창 크기를 두 곳에 적지 않는다(체스 숫자 그대로, SPEC §5.2).
///
/// 화면은 전부 **두 열**이다(로비만 세 열):
///   · 대국 = [판 608 | 오른쪽 열 572]. 오른쪽 열은 위에서부터 상대 카드 · 내 카드 · 판돈과 상태 줄 ·
///     **돌 수·수 기록 카드** · [기권] 한 줄.
///   · 결과 = [판 | 결과 카드 · 돌 수·수 기록 카드].
///   · 관전 = 대국과 같은 두 열(`phase` 는 `.lobby` 그대로, `spectating` 이 있으면 로비 자리에 선다).
///   · 로비 = [상대 420 | 순위 340 | 오른쪽 400] — 오른쪽 열은 위에서부터 내 전적 · 지금 대결 중 · 받은/보낸 신청.
///
/// ── 숫자의 근거 ──
///  · `contentSize 1240×700` — 오목·체스 창과 같은 크기(13" 맥 작업 영역에 들어가는 상한이 1240 이라는 실측이 오목 창에 있다).
///  · `bodyHeight 608` = 660 − 머리글 40 − 간격 12.
///  · `boardSide 608` → **칸 76pt 정확**(608 = 8 × 76). 8×8 은 608 을 나머지 없이 나누므로 64칸이 전부 같은 크기이고
///    격자에 반 픽셀 이음선이 생기지 않는다.
///  · `sideColumnWidth 572` = 1200 − 20 − 608.
///  · `moveListHeight 322` = 608 − 카드 84×2 − 판돈줄 44 − 동작줄 34 − 간격 10×4. 체스 기보 자리와 같은 산식·같은 값이다.
///    돌 수("흑 N · 백 N · 빈칸 N")는 이 카드의 **제목 줄**에 서서 수 목록 행수를 깎지 않는다.
///  · `moveVisibleRows 11` = (262 + 2) / (22 + 2). 한 줄 = 흑 한 수 + 백 한 수(패스 줄 포함, 색으로 짝을 짓는다)라
///    60수 판은 최대 30줄이고 12번째 줄부터 스크롤이다(스냅샷은 클립 갈래).
enum ReversiWindowLayout {
    /// 창 콘텐츠 크기(고정). 컨트롤러의 min/max 도 이 값 하나를 쓴다.
    static let contentSize = CGSize(width: 1240, height: 700)
    static let contentPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let headerHeight: CGFloat = 40
    static let headerSpacing: CGFloat = 12

    static var innerSize: CGSize {
        CGSize(width: contentSize.width - contentPadding * 2, height: contentSize.height - contentPadding * 2)
    }
    static var bodyHeight: CGFloat { innerSize.height - headerHeight - headerSpacing }

    /// 판 한 변 = 본문 높이(정사각). **8 로 나누어떨어진다**(608 = 8 × 76).
    static var boardSide: CGFloat { bodyHeight }
    /// 칸 한 변. 이 값이 정수가 아니게 되는 변경은 격자에 이음선을 만든다(창 시험이 되묻는다).
    static var cellSide: CGFloat { boardSide / 8 }
    /// 대국·결과·관전 화면의 오른쪽 열 = 판을 뺀 나머지.
    static var sideColumnWidth: CGFloat { innerSize.width - columnSpacing - boardSide }

    // MARK: 카드 크롬

    /// 카드의 기본 안쪽 여백. 수 목록 행수 산식이 이 값을 두 번 뺀다 — 뷰와 산식이 같은 숫자를 봐야 한다.
    static let cardPadding: CGFloat = 16

    // MARK: 대국 오른쪽 열의 세로 예산

    static let matchSideSpacing: CGFloat = 10
    /// 두 사람 카드의 **고정** 높이(초상 60 + 안쪽 여백 4×2 = 68, 카드 위아래 여백 8×2 → 84).
    static let playerCardHeight: CGFloat = 84
    static let portraitSide: CGFloat = 60
    /// 카드 안 이름 칸 폭(고정 — 긴 별명이 링을 밀지 않는다).
    static let nameColumnWidth: CGFloat = 170
    static let cardInsetX: CGFloat = 12
    /// 30초 링 한 변(오목 카드와 같은 54).
    static let clockSide: CGFloat = 54
    /// 판돈 칩 | 상태 상자 줄의 최소 높이.
    static let stakeStatusMinHeight: CGFloat = 44
    /// 판돈 칩 폭(체스 `ChessStakeChip` 의 190 과 같다 — AI 칩도 같은 폭으로 선다).
    static let stakeChipWidth: CGFloat = 190
    /// [기권] 한 줄 높이.
    static let actionRowHeight: CGFloat = 34

    /// 돌 수·수 기록 카드 높이 = 두 카드·판돈 줄·동작 줄·간격 넷을 뺀 나머지(= 322).
    static var moveListHeight: CGFloat {
        bodyHeight - playerCardHeight * 2 - stakeStatusMinHeight - actionRowHeight - matchSideSpacing * 4
    }
    /// 제목 줄 높이(돌 수가 이 줄에 선다 — 프레임으로 못 박아 행수 산식이 안 흔들린다).
    static let moveHeaderHeight: CGFloat = 20
    static let moveHeaderSpacing: CGFloat = 8
    /// 수 목록 한 줄(번호 + 흑 수 + 백 수) 높이.
    static let moveRowHeight: CGFloat = 22
    static let moveRowSpacing: CGFloat = 2
    /// 목록에 남는 높이 = 322 − 여백 32 − 제목 20 − 간격 8 = 262.
    static var moveListInnerHeight: CGFloat {
        moveListHeight - cardPadding * 2 - moveHeaderHeight - moveHeaderSpacing
    }
    /// 스크롤 없이 보이는 줄 수(= 11).
    static var moveVisibleRows: Int {
        Int((moveListInnerHeight + moveRowSpacing) / (moveRowHeight + moveRowSpacing))
    }
    /// 수 목록 왼쪽 번호 칸 폭("30." 까지).
    static let moveNumberWidth: CGFloat = 36
    /// 수 한 칸 폭("d3 · 자동" 이 줄지 않고 든다).
    static let moveCellWidth: CGFloat = 110

    // MARK: 로비 세 열

    static var lobbyListWidth: CGFloat { innerSize.width - columnSpacing - lobbySideWidth }
    static let lobbyUsersWidth: CGFloat = 420
    /// 순위 열 폭 = 왼쪽 블록에서 상대 목록과 간격을 뺀 나머지(= 340).
    static var lobbyRankWidth: CGFloat { lobbyListWidth - columnSpacing - lobbyUsersWidth }
    static let lobbySideWidth: CGFloat = 400
    static let lobbySideSpacing: CGFloat = 12
    static let lobbyRecordHeight: CGFloat = 72
    static let lobbyUserRowHeight: CGFloat = 56
    static let lobbyUserRowSpacing: CGFloat = 6

    // MARK: 받은·보낸 신청 칸 (조각을 더해 예산을 낸다 — 체스 2026-10-05 교훈)

    static let lobbyInvitesSpacing: CGFloat = 8
    static let lobbyInvitesTitleHeight: CGFloat = 20
    static let lobbyInviteCardHeight: CGFloat = 90
    static let lobbyOutgoingLineHeight: CGFloat = 30
    /// 안내 줄 높이 — **두 줄**이다(`lineLimit(2)`).
    static let lobbyNoticeLineHeight: CGFloat = 36
    static var lobbyInvitesMaxHeight: CGFloat {
        cardPadding * 2 + lobbyInvitesTitleHeight + lobbyInviteCardHeight
            + lobbyOutgoingLineHeight + lobbyNoticeLineHeight + lobbyInvitesSpacing * 3
    }
    /// "지금 대결 중" 칸의 높이 = 나머지.
    static var lobbyLiveHeight: CGFloat {
        bodyHeight - lobbyRecordHeight - lobbyInvitesMaxHeight - lobbySideSpacing * 2
    }
    static var rankListHeight: CGFloat { bodyHeight - cardPadding * 2 - rankHeaderHeight - rankHeaderSpacing }
    static let rankHeaderHeight: CGFloat = 20
    static let rankHeaderSpacing: CGFloat = 8
    static let rankRowHeight: CGFloat = 34
    static let rankRowSpacing: CGFloat = 5
    static let rankTrailingWidth: CGFloat = 96
    static var rankVisibleRows: Int { Int((rankListHeight + rankRowSpacing) / (rankRowHeight + rankRowSpacing)) }
    /// "지금 대결 중" 카드 첫째 줄의 [관전] 칩 높이(18 이어야 카드가 얼굴 높이를 넘겨 자라지 않는다).
    static let liveWatchChipHeight: CGFloat = 18

    // MARK: 가운데 작은 창

    static let stakePromptWidth: CGFloat = 340
    /// AI 색 고르기 창 폭(흑 · 백 · 무작위 세 버튼이 한 줄에 선다).
    static let aiPromptWidth: CGFloat = 400
    /// 규칙 창 폭 · 예시 판 한 변.
    static let rulesWidth: CGFloat = 860
    static let rulesExampleSide: CGFloat = 150

    // MARK: 관전 오른쪽 열

    static let spectateLeaveHeight: CGFloat = 34
}

/// 아잉 뒤집기 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다** —
/// 스토어의 `openWindow(focusMatchID:)` 가 `presentWindow` 문(통합 갈래의 CheckApp 배선)을 거쳐 여기로 온다.
@MainActor
final class CheckReversiWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckReversiWindowController()

    /// 창 제목. CGWindowList 로 밖에서 창을 셀 때의 표식이다. 게임 이름 한 곳(`ReversiText.gameName`)에서 온다.
    static let windowTitle = ReversiText.gameName

    /// 창 위치를 기억하는 키. **다른 창과 겹치면 안 된다** — 겹치면 `setFrameAutosaveName` 이 false 를 돌려주고
    /// 자리 저장이 조용히 죽는다(`frameAutosaveActive` 로 잰다). `MiniGameSpaceKey.standaloneWindowIDs` 가 읽는 식별자이기도 하다.
    static let frameAutosaveName = "check.reversi.window"

    static let fixedContentSize = NSSize(
        width: ReversiWindowLayout.contentSize.width,
        height: ReversiWindowLayout.contentSize.height
    )

    /// 창을 물릴 재료. 스토어와 콘텐츠를 **함께** 묶는다.
    struct Wiring {
        let store: ReversiStore
        let content: @MainActor (ReversiStore) -> AnyView
    }

    private var wiring: Wiring?
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳. 약참조다(스토어 수명은 앱이 쥔다).
    private weak var safety: WorkTimerStore?
    /// 지연 생성된 창. 닫아도 파괴하지 않는다.
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). `isVisible` 은 이 저장소에서 거짓말한 적이 있어 '의도'와 '사실'을 나눈다.
    private(set) var isOpen = false
    /// 창이 닫혔다 — `true` 면 사람이 닫았다(빨간 점 · ⌘W), `false` 면 프로그램 닫기(로그아웃 · 계정 전환). 앱 배선(`CheckApp`)이
    /// 스토어의 `duelWindowDidClose` 로 잇는다 — 미니게임 창에서 들어온 창이면 사람이 닫은 순간 미니게임 창이 다시 선다(2026-11-03 ⑧).
    /// 오목·체스·테트리스 창과 같은 칸이다.
    var onClosed: (@MainActor (_ byUser: Bool) -> Void)?
    var hasWindow: Bool { windowStorage != nil }
    var currentWindow: NSWindow? { windowStorage }
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }
    private(set) var frameAutosaveActive = false
    /// 스토어에 마지막으로 알린 표시 상태(true = windowDidShow, false = windowDidHide).
    private(set) var lastVisibilityNotice: Bool?
    /// 스토어에 마지막으로 알린 가림 상태.
    private(set) var lastOcclusionNotice: Bool?
    /// 스토어에 '닫혔다'를 알린 횟수(헤드리스 검증 지점 — 최소화와 닫기가 다른 문인지 잰다).
    private(set) var closedNoticeCount = 0

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckReversiWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. 기본 화면(`ReversiPanel`)을 물린다. `me` 는 내 이름·캐릭터를 읽는 문이다 —
    /// `ReversiStore` 는 상대만 들고 있어서 나는 앱 배선이 `WorkTimerStore` 에서 읽어 넘긴다(`ReversiPlayerFace.me(from:)`).
    func configure(
        store: ReversiStore,
        me: @escaping @MainActor () -> ReversiPlayerFace = { ReversiPlayerFace.fallback },
        safety: WorkTimerStore? = nil
    ) {
        self.safety = safety
        configure(store: store, content: { reversi in
            AnyView(
                ReversiPanel(store: reversi, me: me, safety: safety)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(CheckTheme.background)
            )
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재기 위한 문). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(store: ReversiStore, content: @escaping @MainActor (ReversiStore) -> AnyView) {
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

    /// 아잉 뒤집기 창을 만든다.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            // `.resizable` 은 없다(고정 — 판 좌표계가 창 크기에 딸려 흔들리면 안 된다). `.miniaturizable` 은 넣는다.
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        // ★ 이 식별자가 `MiniGameSpaceKey.yieldsToOtherWindow` 의 판정 재료다.
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = fixedContentSize
        window.contentMaxSize = fixedContentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isReleasedWhenClosed = false
        // 다른 앱을 클릭해도 창은 남는다(판은 계속된다 — 시간은 서버가 잰다).
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0. 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 열기 / 닫기

    /// 창을 연다(멱등 — 최소화돼 있으면 되살린다). 열 때마다 스토어에 '보임'을 알린다(재조회의 문).
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

    /// 창을 내린다(멱등). 창과 그 안의 상태는 남는다. **판은 끝나지 않는다.**
    /// 로그아웃·계정 전환에서도 이 문을 부른다(`ChessAccountWatcher` 재사용).
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
        notifyVisibility(false)
        // 프로그램 닫기(로그아웃·계정 전환)도 닫기다 — `orderOut` 은 `windowWillClose` 를 안 보낸다.
        notifyClosed()
        onClosed?(false)
    }

    /// 사용자가 빨간 점을 눌렀다. 의도를 맞추고 '안 보임'과 **'닫혔다'**를 알린다 — 기권이 아니다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        notifyVisibility(false)
        notifyClosed()
        onClosed?(true)
    }

    /// 스토어에 **닫혔다**고 알린다 — `notifyVisibility(false)` 와 갈라 둔다.
    /// ★ 이 문을 `notifyVisibility` 안에 넣지 마라 — '안 보임'은 최소화도 부르므로 합치면 최소화가 관전을 죽인다.
    private func notifyClosed() {
        closedNoticeCount += 1
        wiring?.store.windowDidClose()
    }

    /// 최소화 — 화면에서 사라졌으니 폴링을 멈추게 한다(판은 계속).
    func windowDidMiniaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        notifyVisibility(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        if isOpen { notifyVisibility(true) }
    }

    /// 가림 상태가 바뀌었다. 스토어에 **폴링만** 멈추라고 알린다(`isWindowVisible` 과 시계 잎 뷰는 그대로다).
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === windowStorage else { return }
        applyOcclusion(visible: window.occlusionState.contains(.visible))
    }

    /// 가림 판정을 스토어로 옮긴다(헤드리스 검증 문). 닫힌 창의 통지는 무시한다.
    func applyOcclusion(visible: Bool) {
        guard isOpen else { return }
        lastOcclusionNotice = visible
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

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 판 상태는 스토어에 있으므로 잃는 것이 없다.
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
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다.
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
