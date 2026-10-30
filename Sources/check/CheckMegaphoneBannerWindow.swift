import AppKit
import SwiftUI
import Observation
import CheckCore

// MARK: - 확성기 배너 창 (2026-10-30 · 계약 docs/plan/megaphone-banner-contract.md "맥 배너")
//
// 받은 확성기를 **마우스가 있는 화면 위쪽 가운데**, 메뉴바 아래 12pt 에 한 장씩 띄운다. 판정(한 번에 하나 · 8초 · 쉬고 0.4초 ·
// 호버 멈춤의 "남은 시간과 3초 중 긴 쪽" · 미룸)은 전부 코어 `MegaphoneBannerStore` 에 있고, 이 파일은 그 `current` 를 그리기만 한다.
//
// ① 창: `CheckMousePanel` 하위 — 키를 안 잡는다(대결 중 키보드를 훔치지 않는다) · 모든 스페이스 · 전체화면 보조 · 캐릭터 패널(.floating)
//    한 칸 위 · 화면 공유에 안 비친다. **시험 실행에서는 알파 0 + 모든 화면 밖(x = -30000)** — 케이크 선물 창과 같은 규약.
// ② 움직임: 창 자체는 제자리에 서고, 안의 카드가 위에서 0.25초 미끄러져 내려온다(창이 메뉴바 아래 끝까지 닿아 있어 카드가 메뉴바 밑에서
//    나온다). 닫을 때는 0.2초 올라간다. **불투명도는 미끄러짐에 쓰지 않는다** — 이징으로 불투명도를 깎으면 밀려나기 전에 사라진다.
//    동작 줄이기가 켜져 있으면 미끄러짐 없이 페이드만.
// ③ 호버: `NSTrackingArea`(.activeAlways — 키가 아닌 패널에서도 온다, 캐릭터 패널 방식). 들어오면 멈추고, 떠나면 다시 센다.
// ④ [답장]: 보낸 사람과의 1:1 대화(`openMegaphoneReply` — 이름·아바타를 함께 넘겨 빈 대화 제목을 막는다) → 팝오버 → 배너 닫기.

/// 배너 자리 계산(순수 함수 — 시험이 화면 없이 잰다).
enum MegaphoneBannerLayout {
    /// 화면 한 장의 두 틀(AppKit 좌표 — 아래가 0).
    struct Screen: Equatable {
        var frame: CGRect
        var visibleFrame: CGRect
    }

    /// 메뉴바(보이는 틀 위 끝)와 카드 사이.
    static let topGap: CGFloat = 12
    /// 화면 폭에서 뺄 양(좌우 24pt 씩).
    static let horizontalInset: CGFloat = 48
    /// 카드 최대 폭.
    static let maxWidth: CGFloat = 520
    /// 본문 최대 줄 수.
    static let bodyLineLimit = 4
    /// 미끄러져 내려오는 시간 · 올라가는 시간.
    static let enterDuration: TimeInterval = 0.25
    static let exitDuration: TimeInterval = 0.2
    /// 시험 실행에서 창을 세우는 자리(모든 화면 밖 — 케이크 선물 창과 같은 값).
    static let testParkingOrigin = NSPoint(x: -30_000, y: 200)

    /// 카드 폭 = min(화면 폭 − 48, 520).
    static func width(screenWidth: CGFloat) -> CGFloat {
        max(0, min(screenWidth - horizontalInset, maxWidth))
    }

    /// 마우스가 있는 화면(경계 포함). 어느 화면에도 없으면(이론상) 첫 화면.
    static func screen(containing point: CGPoint, in screens: [Screen]) -> Screen? {
        screens.first { screen in
            point.x >= screen.frame.minX && point.x <= screen.frame.maxX
                && point.y >= screen.frame.minY && point.y <= screen.frame.maxY
        } ?? screens.first
    }

    /// 카드 틀: 보이는 틀 위쪽 가운데, 메뉴바 아래 12pt.
    static func cardFrame(visibleFrame: CGRect, cardHeight: CGFloat) -> CGRect {
        let width = width(screenWidth: visibleFrame.width)
        return CGRect(x: (visibleFrame.midX - width / 2).rounded(), y: visibleFrame.maxY - topGap - cardHeight,
                      width: width, height: cardHeight)
    }

    /// 창 틀: 카드 + 그 위 12pt(메뉴바 아래 끝까지 — 카드가 메뉴바 밑에서 미끄러져 나오는 길).
    static func windowFrame(visibleFrame: CGRect, cardHeight: CGFloat) -> CGRect {
        let card = cardFrame(visibleFrame: visibleFrame, cardHeight: cardHeight)
        return CGRect(x: card.minX, y: card.minY, width: card.width, height: cardHeight + topGap)
    }
}

// MARK: - 패널

/// 배너 패널. 키를 잡지 않는다 — 대결 · 미니게임 · 다른 앱에서 치던 키를 가로채지 않는다(머리 주석 ①).
final class MegaphoneBannerPanel: CheckMousePanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 시험 실행에서만 화면 안으로 끌어오기를 끈다(화면 밖 주차가 그대로 서게 — 케이크 선물 창과 같다).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard CheckPanelVisibility.isRunningTests else { return super.constrainFrameRect(frameRect, to: screen) }
        return frameRect
    }

    /// 캐릭터 패널(.floating)보다 한 칸 위.
    static let bannerLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

    static func make() -> MegaphoneBannerPanel {
        let panel = MegaphoneBannerPanel(contentRect: NSRect(x: 0, y: 0, width: MegaphoneBannerLayout.maxWidth, height: 120),
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        panel.level = bannerLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        // NSPanel 기본값(true)이면 다른 앱을 쓰는 동안 배너가 숨는다 — 배너는 바로 그때 떠야 한다.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        CheckPanelVisibility.apply(to: panel)
        return panel
    }
}

/// 호버 감지 뷰(창의 콘텐츠 뷰). `.activeAlways` 라 키가 아닌 패널에서도 들어옴/떠남이 온다.
final class MegaphoneBannerHoverView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private(set) var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

/// 첫 클릭부터 단추가 눌리는 호스팅 뷰(키가 아닌 패널 — 첫 클릭이 활성화에 먹히지 않게).
final class MegaphoneBannerHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - 화면 내용

/// 카드가 읽는 상태(컨트롤러가 쓴다).
@MainActor
@Observable
final class MegaphoneBannerPresentation {
    var banner: MegaphoneBanner?
    /// 카드가 제자리에 내려와 있는가(거짓이면 창 위로 숨어 있다 — 미끄러짐 · 페이드의 두 끝).
    var isShown = false
    var reduceMotion = false
    var width: CGFloat = MegaphoneBannerLayout.maxWidth
    /// 잰 카드 높이(숨은 자리 = 이만큼 + 12pt 위).
    var cardHeight: CGFloat = 120
}

struct MegaphoneBannerView: View {
    let presentation: MegaphoneBannerPresentation
    let store: WorkTimerStore?
    let onReply: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: MegaphoneBannerLayout.topGap)
            if let banner = presentation.banner {
                card(banner)
                    .offset(y: slideOffset)
                    .opacity(presentation.reduceMotion ? (presentation.isShown ? 1 : 0) : 1)
            }
        }
        .frame(width: presentation.width, alignment: .top)
        .clipped()
        .checkTooltipLayer()
        .appUserAvatarCharacters(from: store)
        .environment(\.colorScheme, .dark)
    }

    /// 미끄러짐: 숨은 자리는 창 위(카드 높이 + 12pt). 동작 줄이기면 움직이지 않는다.
    private var slideOffset: CGFloat {
        guard !presentation.reduceMotion, !presentation.isShown else { return 0 }
        return -(presentation.cardHeight + MegaphoneBannerLayout.topGap)
    }

    private func card(_ banner: MegaphoneBanner) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 사진 → 착용 캐릭터 → (표가 모르는 사람) 기본 아잉.
            CheckAvatarView(name: banner.senderName, userID: banner.senderID, avatarURL: banner.senderAvatarURL,
                            size: 36, characterHint: "aing")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("📢").font(.system(size: 14))
                    Text(banner.senderName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                    if banner.isOwn {
                        Text("· 모두의 화면에 이렇게 떴어요")
                            .font(.system(size: 12))
                            .foregroundStyle(CheckTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(banner.body)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(MegaphoneBannerLayout.bodyLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if banner.canReply {
                        bannerButton("답장", prominent: true, action: onReply)
                            .checkTooltip("1:1 대화로 답장해요")
                    }
                    bannerButton("닫기", prominent: false, action: onClose)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CheckTheme.background.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CheckTheme.border, lineWidth: 1)
        )
    }

    private func bannerButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : CheckTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(prominent ? CheckTheme.accent : CheckTheme.trackFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 컨트롤러

/// 배너 스토어의 `current` 를 지켜보다 창을 띄우고 내린다. 앱 시작 때 오버레이 컨트롤러를 만든 **뒤에** `start()` 한다(AppDelegate).
@MainActor
final class MegaphoneBannerWindowController {
    /// 바깥 세계로 나가는 문(시험은 가짜로 갈아 끼운다 — 진짜 팝오버 단추를 누르지 않는다).
    struct Hooks {
        var presentPopover: @MainActor () -> Void
        var mouseLocation: @MainActor () -> CGPoint
        var screens: @MainActor () -> [MegaphoneBannerLayout.Screen]
        var reduceMotion: @MainActor () -> Bool
        /// 퇴장 애니메이션이 끝난 뒤 창을 내리는 타이머.
        var schedule: @MainActor (_ after: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Void

        static var live: Hooks {
            Hooks(
                presentPopover: { _ = WindowTopAnchor.presentMenuPopover() },
                mouseLocation: { NSEvent.mouseLocation },
                screens: { NSScreen.screens.map { MegaphoneBannerLayout.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) } },
                reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
                schedule: { after, fire in
                    DispatchQueue.main.asyncAfter(deadline: .now() + after) { MainActor.assumeIsolated { fire() } }
                }
            )
        }
    }

    let store: WorkTimerStore
    var hooks: Hooks
    let presentation = MegaphoneBannerPresentation()
    private(set) var panel: MegaphoneBannerPanel?
    private(set) var hoverView: MegaphoneBannerHoverView?
    /// 표시 의도(헤드리스 검증 지점 — `isVisible` 은 이 저장소에서 거짓말한 적이 있다).
    private(set) var isOpen = false
    /// 마지막으로 계산한 카드 틀(시험 실행에서는 창이 화면 밖에 서므로 이것이 "어디에 떴을까"의 답이다).
    private(set) var lastCardFrame: CGRect?
    private var shownBannerID: String?
    private var started = false
    private var generation = 0

    init(store: WorkTimerStore, hooks: Hooks = .live) {
        self.store = store
        self.hooks = hooks
    }

    /// 지켜보기를 시작한다(멱등).
    func start() {
        guard !started else { return }
        started = true
        arm()
        apply()
    }

    /// 지켜보기를 멈추고 창을 내린다(시험 정리 · 앱 종료).
    func stop() {
        started = false
        generation += 1
        isOpen = false
        shownBannerID = nil
        panel?.orderOut(nil)
    }

    private func arm() {
        withObservationTracking {
            _ = store.megaphoneBanner.current
            _ = store.isMegaphoneBannerDeferred
        } onChange: { [weak self] in
            // onChange 는 값이 바뀌기 직전(willSet)에 온다 — 한 틱 뒤 메인 액터에서 새 값을 읽는다.
            Task { @MainActor in self?.applyThenRearm() }
        }
    }

    private func applyThenRearm() {
        guard started else { return }
        apply()
        arm()
    }

    /// 지금 상태대로 맞춘다: 미룸이 바뀌었으면 스토어에 알리고(떠 있던 배너를 줄로 되돌리거나 · 기다리던 것을 띄운다), `current` 를 그린다.
    func apply() {
        store.megaphoneBannerDeferralMayHaveChanged()
        if let banner = store.megaphoneBanner.current {
            show(banner)
        } else {
            hide()
        }
    }

    // MARK: 단추 · 호버

    /// [답장] — 보낸 사람과의 대화를 열고(이름·아바타 함께) 팝오버를 띄운 뒤 배너를 닫는다.
    func reply() {
        guard let banner = store.megaphoneBanner.current, store.openMegaphoneReply(banner) else { return }
        hooks.presentPopover()
        store.megaphoneBanner.dismissCurrent()
    }

    /// [닫기].
    func close() {
        store.megaphoneBanner.dismissCurrent()
    }

    /// 마우스가 배너에 들어왔다/떠났다 — 멈춤 · 다시 세기(남은 시간과 3초 중 긴 쪽)는 스토어가 정한다.
    func hoverChanged(_ inside: Bool) {
        if inside {
            store.megaphoneBanner.pauseTimer()
        } else {
            store.megaphoneBanner.resumeTimer()
        }
    }

    // MARK: 띄우기 · 내리기

    private func show(_ banner: MegaphoneBanner) {
        // 같은 배너의 정보만 얹힌 경우(새로고침이 아바타를 맞췄다) — 다시 미끄러지지 않는다.
        if isOpen, shownBannerID == banner.megaphoneID {
            presentation.banner = banner
            return
        }
        guard let panel = ensurePanel() else { return }
        generation += 1
        shownBannerID = banner.megaphoneID
        let screen = MegaphoneBannerLayout.screen(containing: hooks.mouseLocation(), in: hooks.screens())
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let reduce = hooks.reduceMotion()
        presentation.reduceMotion = reduce
        presentation.isShown = false
        presentation.width = MegaphoneBannerLayout.width(screenWidth: visible.width)
        presentation.banner = banner
        let cardHeight = Self.measureCardHeight(banner: banner, width: presentation.width)
        presentation.cardHeight = cardHeight
        let frame = MegaphoneBannerLayout.windowFrame(visibleFrame: visible, cardHeight: cardHeight)
        lastCardFrame = MegaphoneBannerLayout.cardFrame(visibleFrame: visible, cardHeight: cardHeight)
        if CheckPanelVisibility.isRunningTests {
            panel.setFrame(NSRect(origin: MegaphoneBannerLayout.testParkingOrigin, size: frame.size), display: false)
        } else {
            panel.setFrame(frame, display: false)
        }
        // 키를 잡지 않고 맨 앞에 선다.
        panel.orderFrontRegardless()
        isOpen = true
        if CheckPanelVisibility.isRunningTests {
            presentation.isShown = true
        } else {
            let token = generation
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.generation == token else { return }
                    withAnimation(reduce ? .linear(duration: MegaphoneBannerLayout.enterDuration)
                                         : .easeOut(duration: MegaphoneBannerLayout.enterDuration)) {
                        self.presentation.isShown = true
                    }
                }
            }
            // 이미 마우스가 그 자리에 있다(앞 배너 위에 올려 둔 채 다음 장이 떴다) — 들어옴 알림이 다시 오지 않으니 여기서 멈춘다.
            if frame.contains(hooks.mouseLocation()) { hoverChanged(true) }
        }
    }

    private func hide() {
        guard isOpen else { return }
        isOpen = false
        shownBannerID = nil
        generation += 1
        let token = generation
        if CheckPanelVisibility.isRunningTests {
            presentation.isShown = false
            panel?.orderOut(nil)
            presentation.banner = nil
            return
        }
        withAnimation(presentation.reduceMotion ? .linear(duration: MegaphoneBannerLayout.exitDuration)
                                                : .easeIn(duration: MegaphoneBannerLayout.exitDuration)) {
            presentation.isShown = false
        }
        hooks.schedule(MegaphoneBannerLayout.exitDuration + 0.05) { [weak self] in
            // 그 사이 다음 배너가 떴으면 그 창을 내리지 않는다.
            guard let self, self.generation == token else { return }
            self.panel?.orderOut(nil)
            self.presentation.banner = nil
        }
    }

    /// 카드 높이를 잰다(폭 고정 — 본문 줄 수만큼 자란다). 떠 있는 호스팅 뷰는 관찰 갱신이 다음 틱에 와서 방금 바꾼 값을 못 잰다 —
    /// 그 값으로 처음부터 그리는 잼 전용 호스팅 뷰를 하나 세워 잰다.
    static func measureCardHeight(banner: MegaphoneBanner, width: CGFloat) -> CGFloat {
        let probe = MegaphoneBannerPresentation()
        probe.banner = banner
        probe.width = width
        probe.isShown = true
        let view = NSHostingView(rootView: MegaphoneBannerView(presentation: probe, store: nil, onReply: {}, onClose: {}))
        let total = view.fittingSize.height
        return max(60, (total - MegaphoneBannerLayout.topGap).rounded(.up))
    }

    private func ensurePanel() -> MegaphoneBannerPanel? {
        if let panel { return panel }
        let created = MegaphoneBannerPanel.make()
        let hover = MegaphoneBannerHoverView(frame: created.contentLayoutRect)
        hover.autoresizingMask = [.width, .height]
        hover.onHoverChanged = { [weak self] inside in self?.hoverChanged(inside) }
        let hosting = MegaphoneBannerHostingView(rootView: MegaphoneBannerView(
            presentation: presentation, store: store,
            onReply: { [weak self] in self?.reply() },
            onClose: { [weak self] in self?.close() }
        ))
        // 고유 크기만 알린다 — 최소·최대 크기 제약을 걸면 창 틀(자리 계산이 정한다)과 다툰다.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.frame = hover.bounds
        hosting.autoresizingMask = [.width, .height]
        hover.addSubview(hosting)
        created.contentView = hover
        hover.updateTrackingAreas()
        panel = created
        hoverView = hover
        return created
    }
}
