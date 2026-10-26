import AppKit
import SwiftUI
import CheckCore

// MARK: - 생일 축하 창 (v0.3.66 — 케이크 아잉이 선물)
//
// 운영자가 생일 선물을 지급하면(서버 `character_gifts`) 받는 사람의 앱이 이 창을 띄운다(`WorkTimerStore.refreshCakeGift` — 열린 선물이 있으면
// **실행당 한 번** 스스로). 창 안은 두 화면뿐이다:
//   ① 고르기 — 제목 · 본문(`CakeGiftText`) · 두 초상을 크게(딸기 → 초코) · 확인 단추 · 실패 한 줄.
//   ② 받은 뒤 — 받은 캐릭터 초상 · "○○를 받았어요!" · [지금 입기](기존 착용 경로) · [닫기].
// 고르지 않고 닫으면 메뉴 팝오버의 '다시 열기' 카드가 받을 때까지 남는다(`CheckMenuView.TopBanner.cakeGift`).
//
// 창 계층은 뽑기 창(`CheckGachaWindow.swift`)의 규약 그대로다: 지연 생성 · 멱등 열기(최소화돼 있으면 되살린다) · 닫아도 파괴 안 함 ·
// 고유 자동저장 이름(= 창 식별자, `MiniGameSpaceKey.standaloneWindowIDs` 에 등록 — 확인 단추가 키보드로도 눌린다) · 고착 감시자 + 재생성 상한.
// **테스트 실행에서는 사용자 화면에 아무것도 안 뜬다**: 알파 0(`CheckPanelVisibility`) + 모든 화면 밖(x = -30000) + 클릭 통과 + 키를 가져가지 않는다.
// 외관은 앱 전체와 같은 다크(`CheckTheme`)다.

/// 축하 창의 고정 크기와 초상 크기.
enum CakeGiftWindowLayout {
    static let contentSize = CGSize(width: 440, height: 430)
    /// 고르기 화면의 초상 한 변(pt) — "두 초상을 크게".
    static let choiceArtSide: CGFloat = 150
    /// 받은 뒤 화면의 초상 한 변(pt).
    static let receivedArtSide: CGFloat = 190
}

// MARK: - 창 콘텐츠

struct CheckCakeGiftWindowView: View {
    @Bindable var store: WorkTimerStore
    var catalog: CharacterCatalog = CheckCharacter3DScene.catalog
    /// 창의 [닫기].
    let onClose: () -> Void

    var body: some View {
        ZStack {
            CheckTheme.background
            if let received = store.cakeGiftReceivedID {
                receivedScreen(received)
            } else {
                choosingScreen
            }
        }
        .frame(width: CakeGiftWindowLayout.contentSize.width, height: CakeGiftWindowLayout.contentSize.height)
    }

    // MARK: ① 고르기

    private var choosingScreen: some View {
        let options = store.cakeGiftPresented?.options ?? []
        return VStack(spacing: 12) {
            Text(CakeGiftText.title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(CheckTheme.primaryText)
                .padding(.top, 22)
            Text(CakeGiftText.body)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CheckTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // 운영자가 남긴 한 줄(있을 때만 — 서버 원문 그대로).
            if let note = store.cakeGiftPresented?.note {
                Text(note)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(CheckTheme.primaryText.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 16) {
                ForEach(options, id: \.self) { id in
                    optionCard(id)
                }
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
            // 실패 한 줄 — 자리는 늘 비워 둔다(문구가 와도 단추가 안 밀린다).
            Text(store.cakeGiftNotice ?? " ")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CheckTheme.danger)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30)
            Button {
                store.claimCakeGift()
            } label: {
                Text(store.cakeGiftClaiming ? "…" : CakeGiftText.confirmButton)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 200, height: 36)
                    .background {
                        if store.canConfirmCakeGift {
                            Capsule().fill(CheckTheme.gaugeGradient)
                        } else {
                            Capsule().fill(CheckTheme.trackFill)
                                .overlay(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1))
                        }
                    }
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(!store.canConfirmCakeGift)
            .opacity(store.canConfirmCakeGift ? 1 : 0.6)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(CakeGiftText.confirmButton)
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 24)
    }

    /// 선택지 한 장 — 큰 초상 + 이름. 고른 것은 강조색 테두리 + 체크 배지(캐릭터 고르기 카드와 같은 문법).
    private func optionCard(_ id: String) -> some View {
        let picked = store.cakeGiftChoice == id
        let name = catalog.manifest(id: id)?.displayName ?? id
        return Button {
            store.chooseCakeGift(id)
        } label: {
            VStack(spacing: 8) {
                Self.portrait(id)
                    .frame(width: CakeGiftWindowLayout.choiceArtSide, height: CakeGiftWindowLayout.choiceArtSide)
                Text(name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(picked ? CheckTheme.primaryText : CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(picked ? AnyShapeStyle(CheckTheme.gaugeGradient.opacity(0.22)) : AnyShapeStyle(CheckTheme.trackFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(picked ? CheckTheme.accent : CheckTheme.border, lineWidth: picked ? 2.5 : 1)
                    }
            }
            .overlay(alignment: .topTrailing) {
                if picked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(CheckTheme.accent))
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(store.cakeGiftClaiming)
        .accessibilityLabel(name)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: ② 받은 뒤

    private func receivedScreen(_ id: String) -> some View {
        let name = catalog.manifest(id: id)?.displayName ?? id
        return VStack(spacing: 14) {
            Spacer(minLength: 0)
            Self.portrait(id)
                .frame(width: CakeGiftWindowLayout.receivedArtSide, height: CakeGiftWindowLayout.receivedArtSide)
            Text(CakeGiftText.received(name: name))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(CheckTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            HStack(spacing: 12) {
                Button {
                    store.wearCakeGift()
                } label: {
                    Text(CakeGiftText.wearNowButton)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 140, height: 36)
                        .background(Capsule().fill(CheckTheme.gaugeGradient))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(CakeGiftText.wearNowButton)
                Button(action: onClose) {
                    Text(CakeGiftText.closeButton)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(CheckTheme.primaryText)
                        .frame(width: 110, height: 36)
                        .background(Capsule().fill(CheckTheme.trackFill)
                            .overlay(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1)))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(CakeGiftText.closeButton)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    // MARK: 그림

    @MainActor private static var portraitCache: [String: CGImage] = [:]

    /// 192px 중립 초상 그대로(장식까지 다 보이게 — 조이지 않는다). `Image(nsImage:)` 는 보간을 무시하므로 CGImage 로 내린다.
    @MainActor static func portrait(_ id: String) -> some View {
        let cg: CGImage? = portraitCache[id] ?? {
            let made = CheckMascotAssets.image(for: .neutral, characterID: id)?
                .cgImage(forProposedRect: nil, context: nil, hints: nil)
            if let made { portraitCache[id] = made }
            return made
        }()
        return Group {
            if let cg {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "gift.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(30)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
        }
    }
}

// MARK: - 창 컨트롤러

/// 축하 창의 NSWindow. 뽑기 창과 같다 — **테스트 실행에서만** 화면 안으로 끌어오기를 끈다.
final class CheckCakeGiftNSWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard CheckPanelVisibility.isRunningTests else { return super.constrainFrameRect(frameRect, to: screen) }
        return frameRect
    }
}

/// 축하 창의 수명 · 표시 · 복구를 쥐는 단 하나의 지점. 공개 진입점은 `show()` 하나다(스토어의 `cakeGiftWindowHooks` 를 거쳐 온다).
/// 스토어를 물리는 일은 앱 시작 때 `configure(store:)` 가 한 번 한다.
@MainActor
final class CheckCakeGiftWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckCakeGiftWindowController()

    /// 창 제목(CGWindowList 로 밖에서 창을 셀 때의 표식).
    static let windowTitle = CakeGiftText.title

    /// 창 위치를 기억하는 키 = 창 식별자. 다른 창과 겹치면 안 된다(`MiniGameSpaceKey.standaloneWindowIDs` 가 이 문자열로 이 창을 알아본다).
    static let frameAutosaveName = "check.cakeGift.window"

    static let fixedContentSize = NSSize(width: CakeGiftWindowLayout.contentSize.width,
                                         height: CakeGiftWindowLayout.contentSize.height)

    /// 테스트 실행에서 창을 세우는 자리(모든 화면 밖).
    static let testParkingOrigin = NSPoint(x: -30_000, y: 200)

    struct Wiring {
        let store: WorkTimerStore
        let content: @MainActor (WorkTimerStore, @escaping @MainActor () -> Void) -> AnyView
    }

    private var wiring: Wiring?
    private var windowStorage: NSWindow?
    /// 표시 의도(헤드리스 검증 지점 — `isVisible` 은 이 저장소에서 거짓말한 적이 있다).
    private(set) var isOpen = false
    var hasWindow: Bool { windowStorage != nil }
    var currentWindow: NSWindow? { windowStorage }
    private(set) var frameAutosaveActive = false

    // MARK: - 배선

    /// 앱 시작 시 1회. 기본 화면(`CheckCakeGiftWindowView`)을 물린다.
    func configure(store: WorkTimerStore) {
        configure(store: store, content: { store, close in
            AnyView(CheckCakeGiftWindowView(store: store, onClose: close))
        })
    }

    /// 담을 뷰를 직접 주입한다(창 계층을 화면 내용과 떼어 재기 위한 문). 마지막 배선이 이긴다.
    func configure(store: WorkTimerStore, content: @escaping @MainActor (WorkTimerStore, @escaping @MainActor () -> Void) -> AnyView) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        // [닫기] 는 스토어를 거친다 — 받은 뒤 화면을 걷고 창을 내린다(`closeCakeGiftWindow` → 훅 → 여기 `close()`).
        let hosting = NSHostingView(rootView: wiring.content(wiring.store, { [weak store = wiring.store] in
            store?.closeCakeGiftWindow()
        }))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        if created.frame.size != created.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size {
            created.setContentSize(Self.fixedContentSize)
        }
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    /// 축하 창을 만든다.
    static func makeWindow() -> NSWindow {
        let window = CheckCakeGiftNSWindow(
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
        // 앱 전체가 다크다(`CheckTheme`).
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.alphaValue = CheckPanelVisibility.panelAlpha
        if CheckPanelVisibility.isRunningTests {
            // 사용자 화면에 아무것도 안 뜬다 — 클릭도 안 먹는다(머리 주석).
            window.ignoresMouseEvents = true
        }
        return window
    }

    // MARK: - 열기 / 닫기

    /// 축하 창을 연다(멱등 — 최소화돼 있으면 되살린다).
    func show() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        let fixedFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
        if window.frame.size != fixedFrame { window.setContentSize(Self.fixedContentSize) }
        if CheckPanelVisibility.isRunningTests {
            // 키를 가져가지 않고, 모든 화면 밖에 세운다(머리 주석).
            window.setFrameOrigin(Self.testParkingOrigin)
            window.orderFront(nil)
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
        isOpen = true
        armStuckWindowWatchdog()
    }

    /// 축하 창을 내린다(멱등). 창은 남는다. 떠 있는 수령 왕복은 끊지 않는다 — 결과는 스토어에 옮겨진다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
    }

    /// 사용자가 빨간 점을 눌렀다 — 고르지 않고 닫았으면 선물은 남는다('다시 열기' 카드). 받은 뒤 화면이었으면 다음엔 고르기부터.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        wiring?.store.cakeGiftDidClose()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === windowStorage else { return frameSize }
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    // MARK: - 창이 화면에 못 올라갔을 때의 복구(다른 창과 같은 규약)

    static let stuckWindowCheckSeconds: Double = 0.5
    static let maxStuckWindowRebuilds = 3

    private var stuckWindowWatchdog: Task<Void, Never>?
    private(set) var stuckWindowRebuilds = 0

    /// `makeKeyAndOrderFront` 도 조용히 실패할 수 있다(v0.2.27 실측). 통한 복구는 창을 버리고 새로 만드는 것뿐이었다.
    /// 테스트 실행에서는 걸지 않는다 — 화면 밖 창은 창 서버가 '화면에 없음'으로 답해 멀쩡한 창을 버린다.
    private func armStuckWindowWatchdog() {
        stuckWindowWatchdog?.cancel()
        guard !CheckPanelVisibility.isRunningTests else { return }
        let delay = Self.stuckWindowCheckSeconds
        stuckWindowWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isOpen,
                  let stuck = self.windowStorage, CheckTodoBoardController.isOnScreen(stuck) == false
            else { return }
            self.rebuildStuckWindow()
        }
    }

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 잃는 것은 화면뿐 — 선물 · 고른 것은 스토어에 있다.
    func rebuildStuckWindow() {
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        old.delegate = nil
        old.contentView = nil
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        old.close()
        windowStorage = nil
        isOpen = false
        show()
    }

    #if DEBUG
    /// 테스트 전용: 창을 버리고 자동저장 이름을 놓는다(한 프로세스에서 컨트롤러를 여럿 만들면 먼저 만든 창이 이름을 쥔다).
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
