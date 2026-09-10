import AppKit
import SwiftUI

// MARK: - 왜 별도 창인가 (v0.2.48)
//
// 제보는 **긴 글을 쓰는 표면**이다. 팝오버 안에 두면 두 가지가 곧바로 깨진다:
//   · 팝오버는 바깥을 클릭하면 닫힌다. 열 줄 쓰다가 다른 창을 잠깐 보면 글이 사라진다 —
//     그 사고를 한 번 겪은 사람은 두 번 다시 제보하지 않는다.
//   · 폭이 414 에 갇힌다(메인 팝오버). 관리자의 '받은 제보' 목록은 본문·버전·시각·상태 칩을 한 행에
//     담아야 해서 그 폭에서는 전부 말줄임이 된다.
//
// 창 계층은 새로 발명하지 않는다 — `CheckSettingsWindow.swift` 가 이미 이 저장소가 치러 본 값이다
// (지연 생성 · 멱등 열기 · 닫아도 파괴 안 함 · 자동저장 이름 · 고착 감시자 + 재생성 상한 · 테스트 알파 0).
// 그 파일 머리의 "왜 직접 만든 NSWindow 인가"(SwiftUI `Settings` scene 을 버린 이유)가 여기에도 그대로
// 적용된다. 다른 점만 아래에 적는다.
//
// 미니게임 창과 다른 점:
//   · **리사이즈가 가능하다.** 미니게임이 크기를 못 박은 이유는 공정성이었다(캔버스가 넓을수록 쉬워진다).
//     제보 창에는 겨룰 것이 없고, 반대로 긴 글과 긴 목록을 보는 창이라 사용자가 키울 수 있어야 한다.
//   · **최소화(.miniaturizable)는 없다.** 설정 창과 같은 이유다 — LSUIElement 앱은 Dock 타일이 없어
//     최소화한 창을 되찾는 길이 사실상 없다. 닫기(창은 살아 있다) + 다시 열기가 그 자리를 대신한다.
//   · **닫아도 초안을 지우지 않는다.** 그 규약은 스토어(`closeFeedbackWindow`)에 있고, 여기서는
//     창을 파괴하지 않는 것으로 그 약속을 거든다.

// MARK: - 제보 창 컨트롤러

/// 제보 창의 수명·표시·복구를 쥐는 단 하나의 지점.
///
/// **공개 진입점은 `WorkTimerStore.openFeedbackWindow()` 하나다** — 팝오버 레일의 제보 버튼은 그것만 부르고,
/// 이 컨트롤러를 알 필요가 없다. 스토어를 물리는 일은 앱 시작 때 `configure(store:content:)` 가 한 번 한다.
@MainActor
final class CheckFeedbackWindowController: NSObject, NSWindowDelegate {
    /// 앱이 쓰는 단 하나의 인스턴스. `init` 을 막지 않은 이유는 **헤드리스 검증**이다 —
    /// 전역만 두면 창 하나 재는 데도 앱 전역 상태를 오염시켜야 한다(설정 창과 같은 근거).
    static let shared = CheckFeedbackWindowController()

    /// 창 제목. CGWindowList 로 밖에서 창을 셀 때의 표식이기도 하다(중복 창 검사).
    static let windowTitle = FeedbackText.windowTitle

    /// 창 위치·크기를 기억하는 키(UserDefaults `NSWindow Frame …`). 리사이즈되는 창이라
    /// 자동저장이 **크기까지** 의미를 갖는다(미니게임 창과 정확히 반대 — 그쪽은 크기를 되돌린다).
    static let frameAutosaveName = "check.feedbackWindow"

    /// 기본 콘텐츠 크기(520×560). 폭은 관리자 행 한 줄(종류 배지 · 아바타+이름 · 본문 · 버전 · 시각 · 상태 칩)이
    /// 말줄임 없이 서는 최소치에서 왔고, 높이는 보내기 탭의 6줄 에디터 + 안내 + "내가 보낸 제보" 세 줄이
    /// 잘리지 않는 값이다.
    static let defaultContentSize = NSSize(width: 520, height: 560)

    /// 최소 크기(460×420). 이보다 좁히면 관리자 행의 상태 칩이 본문 위로 겹치고,
    /// 이보다 낮추면 에디터가 두 줄로 찌그러져 '긴 글을 쓰는 창'이라는 이 창의 존재 이유가 사라진다.
    static let minContentSize = NSSize(width: 460, height: 420)

    /// 창을 물릴 재료. **스토어와 콘텐츠를 함께 묶는다** — 따로 두면 스토어만 물리고 콘텐츠는
    /// 플레이스홀더인 채로 배포되는 조합이 만들어진다(그러면 사용자는 빈 창을 본다).
    struct Wiring {
        let store: WorkTimerStore
        /// 창에 담을 뷰. 주입 지점을 남긴 이유는 **창을 뷰 없이 재기 위해서**다(창 계층 검증이
        /// 제보 화면의 내용 변화에 끌려다니면 안 된다).
        let content: @MainActor (WorkTimerStore) -> AnyView
    }

    private var wiring: Wiring?
    /// 지연 생성된 창. **닫아도 파괴하지 않는다** — 사용자가 옮겨 둔 자리·키워 둔 크기가 매번 초기화되는
    /// 것도 나쁘지만, 여기서는 더 나쁜 것이 있다: 창을 파괴하면 SwiftUI 뷰 트리가 사라진다.
    /// 초안 자체는 스토어에 있어 살아남지만(그 설계의 이유가 이것이다), 창을 다시 세우는 비용은 그대로다.
    private var windowStorage: NSWindow?

    /// 표시 의도(헤드리스 검증 지점). 실제 표시 여부는 창 서버가 아는 사실이고 `isVisible` 은
    /// 이 저장소에서 이미 한 번 거짓말했다 — 그래서 '의도'와 '사실'을 다른 이름으로 분리해 둔다.
    private(set) var isOpen = false

    /// 창을 이미 만들었는가(헤드리스 검증 지점). `window` 를 읽으면 그 순간 만들어지므로 이 문으로만 묻는다.
    var hasWindow: Bool { windowStorage != nil }

    /// 지금 쥐고 있는 창(**읽기 전용** — 진단·헤드리스 검증 지점). 만들지 않는다.
    var currentWindow: NSWindow? { windowStorage }

    /// 지금 창이 실제로 자리를 저장하고 있는가(헤드리스 검증 지점). false 면 다음에 열 때 창이 중앙으로
    /// 되돌아간다 — 눈에 잘 안 띄는 퇴행이라 값으로 붙들어 둔다.
    private(set) var frameAutosaveActive = false

    /// 이 인스턴스의 고착 확인 지연(초). 프로덕션은 언제나 `Self.stuckWindowCheckSeconds`. **테스트만** 짧게 주입한다.
    let stuckWindowCheckSeconds: Double

    init(stuckWindowCheckSeconds: Double = CheckFeedbackWindowController.stuckWindowCheckSeconds) {
        self.stuckWindowCheckSeconds = stuckWindowCheckSeconds
        super.init()
    }

    // MARK: - 배선

    /// 앱 시작 시 1회. 스토어와 담을 뷰를 물린다(두 번 불러도 안전 — 마지막 배선이 이긴다).
    func configure(
        store: WorkTimerStore,
        content: @escaping @MainActor (WorkTimerStore) -> AnyView = { store in
            // 뷰는 자기 폭·높이를 채우고, 배경은 **창 쪽**에서 칠한다 — 안 칠하면 리사이즈했을 때
            // 아래쪽에 시스템 기본 회색 판이 드러나 창 절반이 다른 앱처럼 보인다(설정 창과 같은 함정).
            AnyView(
                CheckFeedbackView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(CheckTheme.background)
            )
        }
    ) {
        wiring = Wiring(store: store, content: content)
    }

    // MARK: - 창

    /// 창(첫 `show()` 에 생성). 제보를 한 번도 안 여는 실행이 대부분이라 앱 시작 시 만들지 않는다.
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
        // 반환값을 버리지 않는다 — 같은 이름이 이미 등록돼 있으면 false 를 돌려주고 자리 저장이 조용히 죽는다.
        frameAutosaveActive = created.setFrameAutosaveName(Self.frameAutosaveName)
        windowStorage = created
        return created
    }

    /// 제보 창을 만든다.
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultContentSize),
            // `.resizable` 은 **넣는다**(긴 글·긴 목록을 보는 창이다 — 미니게임과 달리 공정성 문제가 없다).
            // `.miniaturizable` 은 **뺀다**(Dock 타일이 없는 앱이라 최소화한 창을 되찾을 길이 없다).
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = minContentSize
        // 우리가 창을 붙들고 재사용하므로 닫힘에 딸린 해제가 끼면 다음 `show()` 가 해제된 창을 만진다.
        window.isReleasedWhenClosed = false
        // 다른 앱을 클릭해도 창은 남는다 — 재현 과정을 다시 해 보면서 제보를 쓰는 것이 정상 사용 형태다.
        window.hidesOnDeactivate = false
        // ★ 앱 전체가 다크다(`CheckTheme`). 시스템 외관을 따르면 밝은 테마에서 흰 배경에 흰 글자가 난다.
        window.appearance = NSAppearance(named: .darkAqua)
        // 지금 보고 있는 화면으로 온다. `.canJoinAllSpaces` 는 떠 있는 보조 패널의 계약이지 이 창의 것이 아니다.
        // `.fullScreenAuxiliary` 는 남의 앱이 전체화면일 때도 뜨게 한다(그때 못 뜨면 제보할 길이 없다).
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // 테스트 실행일 때만 알파 0(프로덕션은 1). 판정은 `CheckPanelVisibility` 한 곳뿐이다.
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }

    // MARK: - 열기 / 닫기

    /// 제보 창을 연다(멱등 — 여러 번 불러도 창은 하나다. 이미 떠 있으면 앞으로 가져오기만 한다).
    ///
    /// `NSApp.activate()` 가 필요한 이유는 설정 창과 같다(LSUIElement 라 활성 앱이 되는 일이 거의 없다).
    /// **여기서는 특히 중요하다** — 활성화가 없으면 텍스트 에디터에 키보드 포커스가 오지 않아
    /// 사용자 눈에는 "창은 떴는데 글이 안 써진다"가 된다.
    ///
    /// **단, 테스트에서는 활성화하지 않는다.** 알파 0 은 창을 감출 뿐 포커스는 못 막는다.
    func show() {
        guard let window else { return }
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        window.makeKeyAndOrderFront(nil)
        isOpen = true
        armStuckWindowWatchdog()
    }

    /// 제보 창을 내린다(멱등). 창과 그 안의 상태는 남는다 — 다시 열면 같은 자리에 같은 크기로 선다.
    func close() {
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        windowStorage?.orderOut(nil)
        isOpen = false
    }

    /// 사용자가 타이틀바의 빨간 점을 눌렀을 때. 우리가 부른 `close()` 가 아니므로 여기서 의도를 맞추고,
    /// 레일 진입 버튼의 하이라이트(`isFeedbackWindowVisible`)도 내린다.
    /// **초안은 건드리지 않는다** — 창을 잘못 닫았다고 쓰던 글이 사라지면 안 된다.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        stuckWindowWatchdog?.cancel()
        stuckWindowWatchdog = nil
        isOpen = false
        if let store = wiring?.store, store.isFeedbackWindowVisible {
            store.isFeedbackWindowVisible = false
        }
    }

    /// 창이 앞으로 왔다. 의도를 맞춘다(다른 경로로 창이 올라온 경우에도 `isOpen` 이 사실과 갈리지 않게).
    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage else { return }
        isOpen = true
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
            // 취소 검사가 없으면 cancel() 이 곧 즉시 실행이다(이 저장소의 다른 감시 태스크와 같은 계약).
            guard let self, !Task.isCancelled, self.isOpen,
                  let stuck = self.windowStorage, Self.isOnScreen(stuck) == false
            else { return }
            self.rebuildStuckWindow()
        }
    }

    /// 못 뜨는 창을 버리고 새로 만들어 다시 연다.
    ///
    /// **잃는 것이 여기서는 거의 없다**: 창 안의 SwiftUI `@State` 뿐인데, 이 화면의 값(초안·필터·펼침)은
    /// 전부 스토어에 있다. 그 설계 덕분에 재생성이 '쓰던 글을 날리는 복구'가 되지 않는다.
    func rebuildStuckWindow() {
        // 상한은 **여기** 하나뿐이다(감시자 쪽에도 두면 언젠가 두 판정이 갈린다).
        guard stuckWindowRebuilds < Self.maxStuckWindowRebuilds, let old = windowStorage else { return }
        stuckWindowRebuilds += 1
        // 델리게이트를 먼저 뗀다 — 아래 close() 의 windowWillClose 가 우리에게 오면 새 창을 세우는 도중에
        // isOpen 이 뒤집히고 레일 하이라이트까지 내려간다.
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
    /// **제보 본문은 여기 없다** — 진단 문자열은 로그로 흘러가는 값이고, 그 자리에 사용자가 쓴 글이 있으면 안 된다.
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
