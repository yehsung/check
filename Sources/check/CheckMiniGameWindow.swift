import AppKit
import SwiftUI

// MARK: - 왜 팝오버 패널이 아니라 별도 창인가 (v0.2.46)
//
// 미니게임은 처음에 팀 카드 자리를 대체하는 하위 패널이었다. 실사용에서 두 가지가 걸렸다:
//   · 팝오버는 **다른 곳을 클릭하면 닫힌다.** 게임 중에 실수로 바깥을 누르면 판이 통째로 날아간다.
//   · 폭이 340 에 갇힌다(콘텐츠 292). 플래피의 논리 캔버스가 292×200 인데 여백이 0이라 더 키울 길이 없었다.
// 사용자 요구는 "설정 창처럼 별도 팝업으로 띄워 원하는 자리에 옮겨 놓고 하고 싶다" 였다.
//
// 창 계층은 새로 발명하지 않는다 — `CheckSettingsWindow.swift` 가 이미 이 저장소가 치러 본 값이다
// (지연 생성 · 멱등 열기 · 닫아도 파괴 안 함 · 자동저장 이름 · 고착 감시자 + 재생성 상한 · 테스트 알파 0).
// 그 파일의 머리 주석에 적힌 "왜 직접 만든 NSWindow 인가"(SwiftUI `Settings` scene 을 버린 이유)는
// 여기에도 그대로 적용된다. 다른 점만 아래에 적는다.
//
// 설정 창과 다른 점:
//   · `.miniaturizable` 을 **넣는다.** 설정은 잠깐 들렀다 닫는 표면이라 최소화가 오히려 창을 잃는 길이지만
//     (LSUIElement 는 Dock 타일이 없다), 게임 창은 "치워 뒀다 이따 다시" 가 자연스러운 표면이다.
//     Dock 타일이 없어 되찾는 길은 결국 캡션 행 버튼(= `show()`)인데, 그 버튼이 최소화된 창도 되살린다.
//   · **창이 키를 잃거나 닫히면 진행 중인 판을 끝낸다**(`miniGameInterruptToken`). 유휴 0% 불변이
//     팝오버 시절엔 `setMenuPresented(false)` 로 지켜졌는데, 창은 팝오버와 무관하게 살아 있으므로
//     정지 신호가 여기로 옮겨 왔다. 닫힘은 진입 버튼 하이라이트(`isMiniGamePanelVisible`)도 함께 내린다.

// MARK: - 미니게임 창 컨트롤러

/// 미니게임 창의 수명·표시·복구를 쥐는 단 하나의 지점.
///
/// **공개 진입점은 `CheckMiniGameWindowController.shared.show()` 하나다**(스토어의 `openMiniGameWindow()`가 그 문으로 간다).
/// 스토어를 물리는 일은 앱 시작 때 `configure(store:content:)` 가 한 번 한다.
@MainActor
final class CheckMiniGameWindowController: NSObject, NSWindowDelegate {
    /// 앱이 쓰는 단 하나의 인스턴스. `init` 을 막지 않은 이유는 **헤드리스 검증**이다 —
    /// 전역만 두면 창 하나 재는 데도 앱 전역 상태를 오염시켜야 한다(설정 창과 같은 근거).
    static let shared = CheckMiniGameWindowController()

    /// 창 제목. 스페이스 키 모니터가 "지금 키 창이 게임 창인가"를 이 문자열로 판정하므로 **계약이다**
    /// (MiniGamePanel.swift 의 `MiniGameSpaceKey`). CGWindowList 로 밖에서 셀 때의 표식이기도 하다.
    static let windowTitle = "미니게임"

    /// 창 위치를 기억하는 키(UserDefaults `NSWindow Frame …`). 사용자가 자기 자리(예: 두 번째 모니터)로
    /// 옮겨 두면 다음에도 거기서 열려야 한다 — 이 창의 존재 이유가 바로 "원하는 자리에서 하기" 다.
    static let frameAutosaveName = "check.miniGameWindow"

    /// 콘텐츠 크기 — **고정**이다(리사이즈 불가). 사용자 결정 2026-09-08: "창 크기는 수정 불가능하게 해라.
    /// 확대해서 하면 더 쉬워지잖아." 순위표가 걸린 게임이라 캔버스가 사람마다 다르면 겨루는 것이 실력이 아니라
    /// 창 크기가 된다(플래피는 화면이 넓을수록 반응할 여유가 늘고, 타이밍 바는 목표 구간이 픽셀로 넓어진다).
    /// 숫자는 `MiniGameWindowLayout.contentSize` 하나에서 온다 — 두 곳에 적으면 언젠가 갈린다.
    static let fixedContentSize = NSSize(
        width: MiniGameWindowLayout.contentSize.width,
        height: MiniGameWindowLayout.contentSize.height
    )

    /// 창을 물릴 재료. **스토어와 콘텐츠를 함께 묶는다** — 따로 두면 스토어만 물리고 콘텐츠는
    /// 플레이스홀더인 채로 배포되는 조합이 만들어진다.
    struct Wiring {
        let store: WorkTimerStore
        /// 창에 담을 뷰. 주입 지점을 남긴 이유는 **창을 뷰 없이 재기 위해서**다(창 계층 검증이 게임 화면의
        /// 내용 변화에 끌려다니면 안 된다).
        let content: @MainActor (WorkTimerStore) -> AnyView
    }

    private var wiring: Wiring?
    /// 지연 생성된 창. **닫아도 파괴하지 않는다** — 사용자가 옮겨 둔 자리와 창 크기가 매번 초기화되는 게 더 나쁘다.
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). 실제 표시 여부는 창 서버가 아는 사실이고 `isVisible` 은
    /// 이 저장소에서 이미 한 번 거짓말했다 — 그래서 '의도'와 '사실'을 다른 이름으로 분리해 둔다.
    private(set) var isOpen = false

    /// 창을 이미 만들었는가(헤드리스 검증 지점). `window` 를 읽으면 그 순간 만들어지므로 이 문으로만 묻는다.
    var hasWindow: Bool { windowStorage != nil }

    /// 지금 쥐고 있는 창(**읽기 전용** — 진단·헤드리스 검증 지점). 만들지 않는다.
    /// 창을 식별자로 `NSApp.windows` 에서 찾으면 다른 인스턴스(테스트가 여럿 띄운 경우)의 창을 집을 수 있다.
    var currentWindow: NSWindow? { windowStorage }

    /// 창이 지금 화면에 떠 있는가(스페이스 모니터의 유일한 게이트).
    ///
    /// `isVisible` 은 이 저장소에서 한 번 거짓말한 적이 있어(v0.2.27) '의도(`isOpen`)'와 함께 본다 —
    /// **둘 다 참일 때만** 스페이스를 게임이 가져간다. 창을 닫았는데 모니터가 남아 있어도 여기서 막힌다.
    var isWindowOnScreen: Bool { isOpen && (windowStorage?.isVisible ?? false) }

    /// 지금 창이 실제로 자리를 저장하고 있는가(헤드리스 검증 지점).
    private(set) var frameAutosaveActive = false

    /// 이 인스턴스의 고착 확인 지연(초). 프로덕션은 언제나 `Self.stuckWindowCheckSeconds`. **테스트만** 짧게 주입한다.
    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckMiniGameWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. 스토어와 담을 뷰를 물린다(두 번 불러도 안전 — 마지막 배선이 이긴다).
    func configure(
        store: WorkTimerStore,
        content: @escaping @MainActor (WorkTimerStore) -> AnyView = { store in
            // 뷰는 주어진 크기를 채운다(창이 리사이즈되면 캔버스와 순위 행수가 함께 자란다 —
            // `MiniGameWindowLayout`). 배경을 창 쪽에서 채우지 않으면 리사이즈 때 시스템 회색 판이 드러난다.
            AnyView(
                CheckMiniGameWindowView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(CheckTheme.background)
            )
        }
    ) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    /// 창(첫 `show()` 에 생성). 게임을 한 번도 안 여는 실행이 대부분이라 앱 시작 시 만들지 않는다.
    /// **배선 전이면 nil 이다** — 스토어 없이 만든 창은 담을 게 없다.
    private var window: NSWindow? {
        if let windowStorage { return windowStorage }
        guard let wiring else { return nil }
        let created = Self.makeWindow()
        let hosting = NSHostingView(rootView: wiring.content(wiring.store))
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        created.delegate = self
        // 저장된 자리가 있으면 거기서, 없으면 화면 중앙에서. `setFrameAutosaveName` 은 저장만 하고
        // 복원은 `setFrameUsingName` 이 한다(설정 창과 같은 함정).
        if !created.setFrameUsingName(Self.frameAutosaveName) {
            created.center()
        }
        // 자동저장은 **위치만** 의미가 있다. 옛 버전(리사이즈 가능하던 판)이 저장해 둔 크기나 다른 화면 배율에서
        // 온 값이 복원되면 고정 크기로 되돌린다 — 안 그러면 그 맥만 더 큰(=더 쉬운) 캔버스로 논다.
        if created.frame.size != created.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size {
            created.setContentSize(Self.fixedContentSize)
        }
        // 반환값을 버리지 않는다 — 같은 이름이 이미 등록돼 있으면 false 를 돌려주고 자리 저장이 조용히 죽는다.
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    /// 미니게임 창을 만든다.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            // `.resizable` 은 **없다**(크기 고정 — 위 fixedContentSize 주석). `.miniaturizable` 은 넣는다
            // (치워 뒀다 캡션 행 버튼으로 되찾는다 — 그 버튼이 최소화된 창도 되살린다).
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        // 최소 = 최대 = 고정. styleMask 에서 `.resizable` 을 뺐어도 프로그램적 리사이즈·화면 배율 변화가
        // 남아 있어 두 값을 같이 못 박는다.
        window.contentMinSize = fixedContentSize
        window.contentMaxSize = fixedContentSize
        // 초록 버튼(확대)도 막는다 — 눌러도 아무 일이 없으면 사용자는 앱이 멈춘 줄 안다.
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        // 우리가 창을 붙들고 재사용하므로 닫힘에 딸린 해제가 끼면 다음 `show()` 가 해제된 창을 만진다.
        window.isReleasedWhenClosed = false
        // 다른 앱을 클릭해도 창은 남는다(게임을 켜 둔 채 잠깐 다른 일을 볼 수 있어야 한다 — 판은 멈춘다).
        window.hidesOnDeactivate = false
        // ★ 앱 전체가 다크다(`CheckTheme`). 시스템 외관을 따르면 밝은 테마에서 흰 배경에 흰 글자가 난다.
        window.appearance = NSAppearance(named: .darkAqua)
        // 지금 보고 있는 화면으로 온다. `.canJoinAllSpaces` 는 떠 있는 보조 패널의 계약이지 이 창의 것이 아니다.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0(프로덕션은 1). 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 열기 / 닫기

    /// 미니게임 창을 연다(멱등 — 여러 번 불러도 창은 하나다. 최소화돼 있으면 되살린다).
    ///
    /// `NSApp.activate()` 가 필요한 이유는 설정 창과 같다(LSUIElement 라 활성 앱이 되는 일이 거의 없다).
    /// **테스트에서는 활성화하지 않는다** — 알파 0 은 창을 감출 뿐 포커스는 못 막는다.
    func show() {
        guard let window else { return }
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        // 최소화해 둔 창은 makeKeyAndOrderFront 만으로 돌아오지 않는다(Dock 타일이 없는 앱이라 되찾을 길이 이것뿐이다).
        if window.isMiniaturized { window.deminiaturize(nil) }
        // 크기 고정의 마지막 방어선. contentMaxSize 는 **사용자** 리사이즈만 막는다 — 프로그램적 setFrame,
        // 옛 자동저장 프레임 복원, 화면 배율 변화는 통과하므로 열 때마다 되돌린다(그 맥만 더 쉬운 캔버스가 되지 않게).
        let fixedFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
        if window.frame.size != fixedFrame { window.setContentSize(Self.fixedContentSize) }
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        armStuckWindowWatchdog()
    }

    /// 미니게임 창을 내린다(멱등). 창과 그 안의 상태는 남는다 — 다시 열면 같은 자리에 같은 크기로 선다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
    }

    /// 사용자가 타이틀바의 빨간 점을 눌렀을 때. 우리가 부른 `close()` 가 아니므로 여기서 의도를 맞추고,
    /// **진행 중인 판을 끝내며**(유휴 0%) 캡션 행 진입 버튼의 하이라이트도 내린다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        endRound(closing: true)
    }

    /// 다른 창으로 포커스가 갔다. 창은 그대로 떠 있지만 **판은 끝낸다** — 안 그러면 보이지도 않는 창에서
    /// 60Hz 루프가 계속 돈다(유휴 0% 불변). 다시 하려면 캔버스를 클릭하면 된다(그 클릭이 새 판을 연다).
    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        endRound(closing: false)
    }

    /// 크기 고정의 마지막 문. `.resizable` 이 없어도 AppKit 은 프로그램적 리사이즈(화면 배율 변경 등)를
    /// 이 델리게이트에 물어 오므로, 여기서 언제나 고정값을 돌려준다.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === windowStorage else { return frameSize }
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
    }

    /// 초록 버튼(확대) 거부. 버튼은 이미 비활성이지만 ⌥클릭·접근성 경로가 남아 있다.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    /// 창이 앞으로 왔다. 의도를 맞춘다(다른 경로로 창이 올라온 경우에도 `isOpen` 이 사실과 갈리지 않게).
    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        isOpen = true
    }

    /// 진행 중인 판을 끝낸다(+ 닫힘이면 진입 버튼 하이라이트도 내린다). 스토어가 없으면(배선 전) 아무 일도 없다.
    private func endRound(closing: Bool) {
        guard let store = wiring?.store else { return }
        store.miniGameInterruptToken += 1
        if closing, store.isMiniGamePanelVisible { store.isMiniGamePanelVisible = false }
    }

    // MARK: - 창이 화면에 못 올라갔을 때의 복구

    /// 주문 뒤 창이 실제로 떴는지 확인하기까지 두는 여유(초). 근거는 `CheckSettingsWindowController` 와 같다.
    static let stuckWindowCheckSeconds: Double = 0.5
    /// 한 실행에서 허용하는 재생성 횟수(상한이 없으면 창 서버가 계속 거부하는 극단에서 무한 루프다).
    static let maxStuckWindowRebuilds = 3

    private var stuckWindowWatchdog: Task<Void, Never>?
    /// 이 실행에서 실제로 다시 만든 횟수(헤드리스 검증 지점).
    private(set) var stuckWindowRebuilds = 0

    /// `makeKeyAndOrderFront` 도 조용히 실패할 수 있다(v0.2.27 실측). 그때 통한 복구는 창을 버리고 새로 만드는 것뿐이었다.
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

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다. 잃는 것은 창 안의 SwiftUI `@State`(진행 중이던 판)뿐이고,
    /// 자리·크기는 `frameAutosaveName` 이 되살린다.
    func rebuildStuckWindow() {
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        // 델리게이트를 먼저 뗀다 — 아래 close() 의 windowWillClose 가 우리에게 오면 새 창을 세우는 도중에
        // isOpen 이 뒤집히고 진행 중인 판까지 끝난다.
        old.delegate = nil
        old.contentView = nil
        // ★ 자동저장 이름을 반드시 놓아준다(안 풀면 재생성된 창이 자리를 영영 저장하지 못한다).
        old.setFrameAutosaveName("")
        frameAutosaveActive = false
        // `orderOut` 이 아니라 `close()` — AppKit 은 close 할 때까지 창 목록에서 붙들고 있다(설정 창 실측).
        old.close()
        windowStorage = nil
        show()
    }

    /// 이 창이 지금 **실제로** 화면에 올라가 있는가를 창 서버에 직접 묻는다.
    /// 판정이 두 벌이 되지 않게 `CheckTodoBoardController.isOnScreen` 을 그대로 부른다(설정 창과 같은 근거).
    static func isOnScreen(_ window: NSWindow) -> Bool? {
        CheckTodoBoardController.isOnScreen(window)
    }

    /// 지금 창의 상태를 한 줄로(진단·사후 분석에서 같은 문장을 본다).
    var diagnosticState: String {
        guard let windowStorage else { return "window=none isOpen=\(isOpen) rebuilds=\(stuckWindowRebuilds)" }
        let onScreen = Self.isOnScreen(windowStorage).map(String.init(describing:)) ?? "unknown"
        let f = windowStorage.frame
        return "window=\(windowStorage.windowNumber) isOpen=\(isOpen) isVisible=\(windowStorage.isVisible)"
            + " onScreen=\(onScreen) alpha=\(windowStorage.alphaValue) autosave=\(frameAutosaveActive)"
            + " frame=\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))"
            + " rebuilds=\(stuckWindowRebuilds)"
    }
}
