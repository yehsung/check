import AppKit
import Observation
import SwiftUI
import CheckCore

// MARK: - 아잉 마작 창 (내부 이름 mahjong) — 설계서 mj/SPEC.md §5.1 · §5.2 · §4.7
//
// 큐브 `CheckRummyWindow.swift` 의 틀(지연 생성 · 멱등 `show()` · 닫아도 파괴 안 함 · 고정 1240×700 · `.resizable` 없음 · darkAqua ·
// `CheckPanelVisibility.panelAlpha` · 고착 감시 재생성 3회 · 키 모니터 없음 · 보임/가림 통지 분리)에서 **`windowShouldClose` 를 뺐다**
// (닫기 ≠ 기권). 체스·리버시처럼 `close()`(프로그램)와 `windowWillClose`(사람) 두 길로 `onClosed(byUser:)` 를 가른다.
//
//   · **키를 잃거나 닫혀도 판은 끝나지 않는다.** 차례가 오면 서버가 쯔모기리·넘기기로 대신 두고, 연속 시간 초과 3번이면 자리
//     비움이 될 뿐이다(대표 카드 ⑨ — 자리 비움, 루비는 실제 등수대로). 그래서 이 컨트롤러는 판에 쓰는 RPC 를 **하나도 모른다**.
//   · **첫 클릭을 받는다**(CC-05 · D50): `contentView` = `MahjongHostingView`(`acceptsFirstMouse → true`). 메뉴바 앱이라 사람은
//     늘 다른 앱을 쓰다 이 창으로 온다 — 첫 누름이 '창 앞으로'에 먹히면 5초 중 0.5~1초를 잃고 "버렸는데 안 버려졌다"가 된다.
//   · **작은 화면**(CC-14 · D51): `show()` 마다 그 화면 visibleFrame 으로 배율(`MahjongWindowScale`)을 정하고 원점을 화면 안으로
//     민다(`CheckMiniGameWindowController.originKeepingOnScreen` — 부르기만).
//   · ★ `MiniGameSpaceKey.standaloneWindowIDs` 에 `check.mahjong.window` 를 넣는 일, `presentWindow`·`onClosed` 배선, App Nap
//     붙들기(`MahjongActivityHold`)를 스토어 신호에 잇는 일은 통합 갈래(T)가 `CheckApp`·`MiniGamePanel` 에서 한다.

/// 로비·방 화면의 **고정** 레이아웃 — 큐브 `RummyWindowLayout` 숫자 그대로(SPEC §5.2). 순수 상수.
enum MahjongWindowLayout {
    static let contentPadding: CGFloat = 20
    static let columnSpacing: CGFloat = 20
    static let headerHeight: CGFloat = 40
    static let headerSpacing: CGFloat = 12
    static let innerWidth: CGFloat = 1200
    static let bodyHeight: CGFloat = 608

    /// 창 콘텐츠 크기(고정 1240×700). 컨트롤러의 min/max 도 이 값 하나를 쓴다.
    static var contentSize: CGSize {
        CGSize(width: innerWidth + contentPadding * 2,
               height: contentPadding * 2 + headerHeight + headerSpacing + bodyHeight)
    }

    // MARK: 로비 두 열 [사람·순위 탭 440 | 오른쪽 740]
    static let lobbyListWidth: CGFloat = 440
    static var lobbySideWidth: CGFloat { innerWidth - columnSpacing - lobbyListWidth }
    static let lobbyTabHeight: CGFloat = 28
    /// 사람 행(56pt — SPEC §5.8).
    static let lobbyRowHeight: CGFloat = 56
    static let lobbyRowSpacing: CGFloat = 6
    static let cardPadding: CGFloat = 14
    static let sideSpacing: CGFloat = 12
    /// 받은 초대 + 공개 방 카드 한 줄의 높이(카드 셋이 한 줄에 든다).
    static let joinCardHeight: CGFloat = 176
    static var joinCardWidth: CGFloat { (lobbySideWidth - sideSpacing * 2) / 3 }
    static let joinEmptyHeight: CGFloat = 44
    static func tableCardHeight(hasJoinables: Bool) -> CGFloat {
        bodyHeight - (hasJoinables ? joinCardHeight : joinEmptyHeight) - sideSpacing
    }
    static let tableStageHeight: CGFloat = 280

    // MARK: 가운데 작은 창
    static let sheetWidth: CGFloat = 380
    static let rulesSize = CGSize(width: 980, height: 600)
}

/// 판 화면 레이아웃(본문 1200×660, 창 머리글 없음 — 큐브 0.3.70 · UX §1.3 표 그대로). 사각형은 **본문 좌표**(창 여백 20 안).
enum MahjongMatchLayout {
    static let bodySize = CGSize(width: 1200, height: 660)
    static var bodyOrigin: CGPoint {
        CGPoint(x: MahjongWindowLayout.contentPadding, y: MahjongWindowLayout.contentPadding)
    }

    static let info = CGRect(x: 0, y: 0, width: 230, height: 46)
    static let chromeLeft = CGRect(x: 238, y: 0, width: 184, height: 46)
    static let topSeat = CGRect(x: 430, y: 0, width: 340, height: 46)
    static let chromeRight = CGRect(x: 778, y: 0, width: 184, height: 46)
    static let aids = CGRect(x: 970, y: 0, width: 230, height: 46)
    static let leftSeat = CGRect(x: 0, y: 195, width: 150, height: 220)
    static let rightSeat = CGRect(x: 1050, y: 195, width: 150, height: 220)
    static let felt = CGRect(x: 158, y: 54, width: 884, height: 502)
    static let mySeat = CGRect(x: 0, y: 564, width: 150, height: 96)
    static let hand = CGRect(x: 158, y: 564, width: 790, height: 96)
    static let actions = CGRect(x: 964, y: 564, width: 236, height: 96)

    // MARK: 펠트 안 탁자 덩어리 536×502(가운데, 펠트 좌표 x=174)
    static let handStrip: CGFloat = 34
    static let riverDepth: CGFloat = 122
    static let centerSide: CGFloat = 200
    static let gap: CGFloat = 6
    /// 세로 34+6+122+6+200+6+122+6 = 502(내 손은 펠트 밖 — 아래쪽 손 띠가 없다).
    static var blockHeight: CGFloat { handStrip + gap + riverDepth + gap + centerSide + gap + riverDepth + gap }
    /// 가로 34+6+122+6+200+6+122+6+34 = 536.
    static var blockWidth: CGFloat { handStrip + gap + riverDepth + gap + centerSide + gap + riverDepth + gap + handStrip }
    /// 펠트 안 덩어리 왼쪽 위(펠트 좌표).
    static var blockOrigin: CGPoint { CGPoint(x: (felt.width - blockWidth) / 2, y: 0) }
    /// 가운데 판(덩어리 좌표).
    static var center: CGRect {
        CGRect(x: handStrip + gap + riverDepth + gap, y: handStrip + gap + riverDepth + gap, width: centerSide, height: centerSide)
    }

    /// 방위별 강 자리(덩어리 좌표). 셋째 줄은 넘치면 이 칸 밖(바람개비 모서리)으로 늘어난다.
    static func river(_ compass: MahjongCompass) -> CGRect {
        let c = center
        switch compass {
        case .bottom: return CGRect(x: c.minX, y: c.maxY + gap, width: centerSide, height: riverDepth)
        case .top: return CGRect(x: c.minX, y: c.minY - gap - riverDepth, width: centerSide, height: riverDepth)
        case .right: return CGRect(x: c.maxX + gap, y: c.minY, width: riverDepth, height: centerSide)
        case .left: return CGRect(x: c.minX - gap - riverDepth, y: c.minY, width: riverDepth, height: centerSide)
        }
    }

    /// 상대 손 띠(덩어리 좌표). 나(아래)는 손이 펠트 밖이라 없다.
    static func handStripRect(_ compass: MahjongCompass) -> CGRect? {
        switch compass {
        case .bottom: return nil
        case .top: return CGRect(x: 0, y: 0, width: blockWidth, height: handStrip)
        case .left: return CGRect(x: 0, y: 0, width: handStrip, height: blockHeight)
        case .right: return CGRect(x: blockWidth - handStrip, y: 0, width: handStrip, height: blockHeight)
        }
    }

    // MARK: 손·ACTIONS 안
    static let statusLineHeight: CGFloat = 20
    /// 손패 윗변(손 칸 좌표) — 상태 줄 20 + 간격 10. 호버 8pt 가 그 간격으로 들린다.
    static let handTileTop: CGFloat = 30
    static let hoverLift: CGFloat = 8
    /// 13장 뒤 쯔모 칸 간격 · 쯔모 칸 뒤 부로 간격(UX:116-117).
    static let drawnGap: CGFloat = 14
    static let meldGap: CGFloat = 12
    /// 14장 + 쯔모 칸(= 46×14 + 14 = 658 ≤ 790).
    static var fullHandWidth: CGFloat { MahjongTileSize.hand.width * 14 + drawnGap }

    // MARK: 국 결과 카드
    static let handResultSize = CGSize(width: 600, height: 400)
}

/// 작은 화면 배율(CC-14 · D51 — 순수). 창 틀 포함 1240×728 이 visibleFrame 에 안 들면 본문을 줄인다.
enum MahjongWindowScale {
    /// 창 틀(제목 막대 포함) 크기.
    static let titleBarHeight: CGFloat = 28
    static var frameSize: CGSize {
        CGSize(width: MahjongWindowLayout.contentSize.width, height: MahjongWindowLayout.contentSize.height + titleBarHeight)
    }
    /// 하한(설계 상수 (추정)) — 이보다 작으면 본문 글자가 너무 작아 "잘려요" 안내를 낸다.
    static let lowerBound: CGFloat = 0.82

    /// 그 화면에 들어가는 날 배율(하한 적용 전).
    static func rawFit(visible: CGSize) -> CGFloat {
        min(1, visible.width / frameSize.width, visible.height / frameSize.height)
    }

    /// 쓸 배율 = min(1, 가로비, 세로비), 하한 0.82.
    static func fit(visible: CGSize) -> CGFloat {
        max(lowerBound, rawFit(visible: visible))
    }

    /// 하한보다도 작은 화면 — 로비 머리에 한 줄 안내.
    static func isCramped(visible: CGSize) -> Bool { rawFit(visible: visible) < lowerBound }

    /// 창 자리 한 번 정하기(순수 — 시험 문). 창과 가장 많이 겹치는 화면(없으면 첫 화면)의 visibleFrame 으로 배율을 정하고,
    /// 그 배율의 창 크기로 **위 변을 지킨 채** 줄인 뒤 원점을 화면 안으로 민다.
    static func placement(frame: NSRect, visibleFrames: [NSRect]) -> (scale: CGFloat, frame: NSRect, cramped: Bool) {
        guard let first = visibleFrames.first else { return (1, frame, false) }
        func overlap(_ screen: NSRect) -> CGFloat {
            let shared = screen.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        let best = visibleFrames.max { overlap($0) < overlap($1) } ?? first
        let screen = overlap(best) > 0 ? best : first
        let scale = fit(visible: screen.size)
        // 내림 — 반올림하면 1pt 넘쳐 화면 밖으로 나간다(1280×705 에서 706).
        let size = NSSize(width: (MahjongWindowLayout.contentSize.width * scale).rounded(.down),
                          height: (MahjongWindowLayout.contentSize.height * scale).rounded(.down) + titleBarHeight)
        var sized = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        sized.origin = CheckMiniGameWindowController.originKeepingOnScreen(sized, visibleFrames: visibleFrames)
        return (scale, sized, isCramped(visible: screen.size))
    }
}

/// 창 배율 상자 — 컨트롤러가 정하고 루트가 읽는다.
@MainActor
@Observable
final class MahjongWindowScaleBox {
    var scale: CGFloat = 1
    var cramped = false
}

/// 첫 클릭을 받는 호스팅 뷰(CC-05). 판 화면만이 아니라 창 전체(로비 [참가]도)에 쓴다.
final class MahjongHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 배율을 입힌 루트 — 본문은 늘 1240×700 좌표로 그리고 통째로 줄인다(입력 좌표도 같이 줄어든다).
struct MahjongScaledRoot<Content: View>: View {
    let box: MahjongWindowScaleBox
    @ViewBuilder let content: Content

    var body: some View {
        let size = MahjongWindowLayout.contentSize
        content
            .environment(\.mahjongCramped, box.cramped)
            .frame(width: size.width, height: size.height)
            .scaleEffect(box.scale, anchor: .topLeading)
            .frame(width: size.width * box.scale, height: size.height * box.scale, alignment: .topLeading)
    }
}

private struct MahjongCrampedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 화면이 하한보다도 좁다(로비 머리에 "화면이 좁아 마작 판이 잘려요").
    var mahjongCramped: Bool {
        get { self[MahjongCrampedKey.self] }
        set { self[MahjongCrampedKey.self] = newValue }
    }
}

/// 아잉 마작 창의 수명·표시·복구를 쥐는 단 하나의 지점. **공개 진입점은 `show()` 하나다** —
/// 스토어의 `openWindow(focusMatchID:)` 가 `presentWindow` 문(통합 갈래의 CheckApp 배선)을 거쳐 여기로 온다.
@MainActor
final class CheckMahjongWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckMahjongWindowController()

    /// 창 제목 = 게임 이름 한 곳(`MahjongInviteText.gameName` ← 코어 `MahjongNoticeText.gameName`).
    static let windowTitle = MahjongInviteText.gameName

    /// 창 위치를 기억하는 키(다른 창과 겹치면 `setFrameAutosaveName` 이 false — `frameAutosaveActive` 로 잰다).
    static let frameAutosaveName = "check.mahjong.window"

    static let fixedContentSize = NSSize(
        width: MahjongWindowLayout.contentSize.width,
        height: MahjongWindowLayout.contentSize.height
    )

    /// 창을 물릴 재료. 스토어와 콘텐츠를 **함께** 묶는다.
    struct Wiring {
        let store: MahjongStore
        let content: @MainActor (MahjongStore) -> AnyView
    }

    private var wiring: Wiring?
    private var windowStorage: NSWindow?
    let scaleBox = MahjongWindowScaleBox()

    /// 표시 의도(헤드리스 검증 지점 — `isVisible` 은 이 저장소에서 거짓말한 적이 있다).
    private(set) var isOpen = false
    /// 창이 닫혔다 — `true` 면 사람이 닫았다(빨간 점 · ⌘W), `false` 면 프로그램 닫기(로그아웃 · 계정 전환).
    /// 앱 배선(T)이 미니게임 문 복귀(`MiniGameDuelDoor.mahjong`)에 잇는다. 스토어의 닫기 안내는 이 컨트롤러가 직접 알린다.
    var onClosed: (@MainActor (_ byUser: Bool) -> Void)?
    var hasWindow: Bool { windowStorage != nil }
    var currentWindow: NSWindow? { windowStorage }
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }
    private(set) var frameAutosaveActive = false
    private(set) var lastVisibilityNotice: Bool?
    private(set) var lastOcclusionNotice: Bool?
    /// 스토어에 '닫혔다'를 알린 횟수(최소화와 닫기가 다른 문인지 잰다).
    private(set) var closedNoticeCount = 0
    /// 화면 visibleFrame 목록(시험이 갈아 끼운다).
    var visibleFrames: @MainActor () -> [NSRect] = { NSScreen.screens.map(\.visibleFrame) }

    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckMahjongWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. 루트 `MahjongPanel(store:me:safety:)` — 툴팁 레이어 · 아바타 캐릭터 표는 패널 안(짝 — §4.6 #23).
    func configure(
        store: MahjongStore,
        me: @escaping @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback },
        safety: WorkTimerStore? = nil
    ) {
        configure(store: store, content: { mahjong in
            AnyView(MahjongPanel(store: mahjong, me: me, safety: safety))
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재는 문). 두 번 불러도 안전 — 마지막 배선이 이긴다.
    func configure(store: MahjongStore, content: @escaping @MainActor (MahjongStore) -> AnyView) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let box = scaleBox
        let root = AnyView(MahjongScaledRoot(box: box) { wiring.content(wiring.store) })
        let hosting = MahjongHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    /// 창을 (아직 없으면) 만들기만 한다 — 화면에 올리지 않는다(헤드리스 검증 문. 시험은 `show()` 대신 이것을 부른다).
    @discardableResult
    func prepareWindow() -> NSWindow? { window }

    /// 아잉 마작 창을 만든다.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            // `.resizable` 은 없다(고정 — 작은 화면 배율만 컨트롤러가 정한다).
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = NSSize(width: fixedContentSize.width * MahjongWindowScale.lowerBound,
                                       height: fixedContentSize.height * MahjongWindowScale.lowerBound)
        window.contentMaxSize = fixedContentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    /// 지금 화면에 맞춘 배율·자리를 창에 입힌다.
    func fitToScreen() {
        guard let window = windowStorage else { return }
        let placed = MahjongWindowScale.placement(frame: window.frame, visibleFrames: visibleFrames())
        scaleBox.scale = placed.scale
        scaleBox.cramped = placed.cramped
        let content = NSSize(width: (Self.fixedContentSize.width * placed.scale).rounded(.down),
                             height: (Self.fixedContentSize.height * placed.scale).rounded(.down))
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        var frame = NSRect(x: placed.frame.minX, y: window.frame.maxY - target.height, width: target.width, height: target.height)
        frame.origin = CheckMiniGameWindowController.originKeepingOnScreen(frame, visibleFrames: visibleFrames())
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    // MARK: - 열기 / 닫기

    /// 창을 연다(멱등 — 최소화돼 있으면 되살린다). 열 때마다 스토어에 '보임'을 알린다(재조회의 문).
    func show() {
        guard let window else { return }
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        fitToScreen()
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        notifyVisibility(true)
        armStuckWindowWatchdog()
    }

    /// 창을 내린다(멱등 — 로그아웃·계정 전환도 이 문). 창과 그 안의 상태는 남는다. **판은 끝나지 않는다.**
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        let wasOpen = isOpen
        isOpen = false
        notifyVisibility(false)
        guard wasOpen else { return }
        // 프로그램 닫기도 닫기다 — `orderOut` 은 `windowWillClose` 를 안 보낸다.
        notifyClosed(byUser: false)
    }

    /// 사용자가 빨간 점을 눌렀다. 기권이 아니다 — '안 보임'과 '닫혔다(사람)'만 알린다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        notifyVisibility(false)
        notifyClosed(byUser: true)
    }

    /// 스토어와 앱 배선에 **닫혔다**고 알린다 — `notifyVisibility(false)` 와 갈라 둔다(최소화는 닫기가 아니다).
    private func notifyClosed(byUser: Bool) {
        closedNoticeCount += 1
        wiring?.store.windowDidClose(byUser: byUser)
        onClosed?(byUser)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        notifyVisibility(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        if isOpen { notifyVisibility(true) }
    }

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

    func windowDidChangeScreen(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage, isOpen else { return }
        fitToScreen()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === windowStorage else { return frameSize }
        return sender.frame.size
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
            + " scale=\(scaleBox.scale) frame=\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))"
            + " rebuilds=\(stuckWindowRebuilds)"
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다.
    func discardWindowForTesting() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        lastVisibilityNotice = nil
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
