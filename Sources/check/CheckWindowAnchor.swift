import AppKit
import SwiftUI
import os

/// MenuBarExtra(.window) 팝오버 창의 위쪽(그리고 오른쪽) 모서리를 고정해, 콘텐츠 높이가 변해도
/// 창이 위로 튀어 상단이 화면 밖으로 잘리지 않게 한다.
///
/// 배경(버그): AppKit 창의 원점은 좌하단이라, 콘텐츠 높이가 커지면 시스템 리사이즈가 원점(origin.y)을
/// 유지한 채 maxY(위쪽 모서리)를 끌어올린다 → 창이 위로 자라 상단이 메뉴바/화면 밖으로 잘린다.
/// 동적 높이(상태별 콘텐츠 맞춤·팀원 수 비례)는 사용자 요구사항이라 유지하되, 위쪽 모서리(maxY)와
/// 오른쪽 모서리(maxX)를 앵커로 잡고 리사이즈/이동 때마다 origin을 되돌려 "아래로만" 자라게(또는 줄게) 한다.
///
/// 헤드리스 테스트를 위해 앵커 캡처/복원을 노티와 분리한 순수 메서드(`captureAnchor`/`restoreIfNeeded`/
/// `clearAnchor`)로 노출한다. 노티(키 획득/리사이즈/이동/키 상실)는 그 메서드를 부르는 얇은 배선일 뿐이다.
@MainActor
final class WindowTopAnchor {
    /// 관찰 중인 창(약참조 — 창 수명은 시스템이 소유).
    private(set) weak var window: NSWindow?

    /// 고정할 위쪽 모서리 y좌표(맥 좌표계 maxY). nil이면 앵커 없음(창 숨김 상태) → 복원에 개입하지 않는다.
    private(set) var anchorTopY: CGFloat?
    /// 고정할 오른쪽 모서리 x좌표(maxX).
    private(set) var anchorMaxX: CGFloat?

    /// 복원 setFrame이 didMove/didResize를 다시 유발해도 재귀 복원하지 않도록 막는 재진입 가드.
    private var isAdjusting = false

    /// 창 표시/숨김(키 획득 true / 키 상실 false)을 상위로 전달하는 콜백. 팝오버 표시 감지(setMenuPresented) 배선용.
    var onVisibilityChange: ((Bool) -> Void)?

    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "kingcheck", category: "window")

    /// maxY/maxX가 앵커에서 이만큼(pt) 이상 벗어나야 복원한다(부동소수 잡음 무시).
    private static let tolerance: CGFloat = 0.5

    // MARK: - 팝오버를 프로그램으로 닫는 문 (v0.2.49)

    /// 지금 화면에 서 있는 팝오버의 앵커. `MenuBarExtra` 콘텐츠는 앱에 하나뿐이라 살아 있는 코디네이터도
    /// 하나이고, 그래서 이 정적 약참조가 **뷰 바깥의 코드(스토어)가 팝오버에 닿는 유일한 통로**다.
    /// 약참조인 이유는 창과 같다 — 수명은 SwiftUI 가 쥔다.
    private(set) static weak var current: WindowTopAnchor?

    /// 마지막으로 상태바 아이템을 누른 시각(중복 방어). 두 번 누르면 **토글이라 팝오버가 도로 열린다** —
    /// 한 동작에서 두 경로가 각자 닫으려 드는 조합(예: 창을 여는 스토어 메서드와 그 버튼의 호출부가
    /// 둘 다 닫으려는 경우)에서 사용자가 보는 결과가 "안 닫힘"이 되지 않게 막는다.
    private static var lastDismissAt: Date?
    /// 그 방어선의 길이. 사람이 두 번 누를 수 있는 간격보다는 짧고, 한 동작 안의 두 호출보다는 길다.
    /// (테스트가 이 값을 읽는다 — 리터럴을 다시 적으면 길이를 바꿔도 가드가 안 따라온다.)
    static let dismissDebounce: TimeInterval = 0.6

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - Attach / detach

    /// 창을 잡고 노티를 배선한다. 같은 창으로 다시 불리면 무시(멱등). 창이 이미 보이면 초기 앵커를 예약한다.
    func attach(to window: NSWindow) {
        guard self.window !== window else {
            // 같은 창이면 배선은 그대로 두되 **현재 앵커 자리는 다시 차지한다** — 콘텐츠가 다시 만들어지며
            // 새 코디네이터가 붙는 경로에서, 옛 코디네이터의 detach 가 뒤늦게 와 자리를 비워 놓을 수 있다.
            Self.current = self
            return
        }
        removeObservers()
        self.window = window
        // 팝오버를 닫는 문(dismissMenuPopover)이 "지금 팝오버가 떠 있는가"를 묻는 유일한 통로.
        // MenuBarExtra 콘텐츠는 앱에 하나뿐이라 살아 있는 코디네이터도 하나다.
        Self.current = self
        // 리사이즈 애니메이션 제거 — 복원이 스냅으로 즉시 반영되게(잔상/튐 방지).
        window.animationBehavior = .none
        installObservers(on: window)
        // 접근자가 창을 늦게 얻는 경우(이미 표시된 첫 오픈)를 위해 다음 런루프 턴에 한 번 캡처한다.
        if window.isVisible || window.isKeyWindow {
            scheduleCapture()
        }
    }

    /// 노티를 해제하고 앵커를 비운다. 접근자 dismantle 시 호출.
    func detach() {
        removeObservers()
        // 내가 현재 앵커일 때만 자리를 비운다. 팝오버가 다시 열리며 **새 코디네이터가 먼저 attach 하고**
        // 옛 코디네이터의 dismantle 이 뒤늦게 오는 순서가 실제로 있는데, 무조건 nil 로 만들면
        // 그 순간부터 팝오버를 닫는 문이 영영 "팝오버가 없다"고 답한다.
        if Self.current === self { Self.current = nil }
        window = nil
        anchorTopY = nil
        anchorMaxX = nil
    }

    // MARK: - Anchor capture / restore (테스트에서 직접 호출 가능한 결정적 로직)

    /// 현재 창 프레임의 위/오른쪽 모서리를 앵커로 캡처한다. 위쪽은 화면 상단(visibleFrame.maxY)을 넘지 않게 클램프한다.
    ///
    /// 창이 보일 때마다(키 획득 노티) 다음 런루프 턴에 호출된다 — 시스템이 상태바 아이템 아래로 배치를 끝낸 값을 잡기 위함.
    /// - Parameter screenVisibleMaxY: 위쪽 모서리 클램프 상한. nil이면 창이 놓인 화면(없으면 주 화면)의 visibleFrame.maxY를 쓴다.
    func captureAnchor(screenVisibleMaxY: CGFloat? = nil) {
        guard let window else { return }
        let frame = window.frame
        var topY = frame.maxY
        if let limit = screenVisibleMaxY ?? (window.screen ?? NSScreen.main)?.visibleFrame.maxY {
            topY = min(topY, limit)
        }
        anchorTopY = topY
        anchorMaxX = frame.maxX
    }

    /// 창의 위쪽 모서리(maxY)나 오른쪽 모서리(maxX)가 앵커에서 벗어났으면 origin을 되돌려 두 모서리를 고정한다
    /// (아래로만 성장/수축). 앵커가 없으면(창 숨김) 개입하지 않는다. 실제 복원이 일어났으면 true.
    @discardableResult
    func restoreIfNeeded() -> Bool {
        guard !isAdjusting, let window, let anchorTopY, let anchorMaxX else { return false }
        let frame = window.frame
        let topOff = abs(frame.maxY - anchorTopY) >= Self.tolerance
        let rightOff = abs(frame.maxX - anchorMaxX) >= Self.tolerance
        guard topOff || rightOff else { return false }

        // 새 크기는 그대로 두고 origin만 이동 → 위·오른쪽 모서리 고정, 아래로만 성장/수축.
        let target = NSRect(
            x: anchorMaxX - frame.width,
            y: anchorTopY - frame.height,
            width: frame.width,
            height: frame.height
        )
        let oldMaxY = Double(frame.maxY)
        isAdjusting = true
        window.setFrame(target, display: true)
        isAdjusting = false

        logger.debug("top-anchor restore: maxY \(oldMaxY, privacy: .public) -> \(Double(anchorTopY), privacy: .public)")
        return true
    }

    /// 앵커를 해제한다(창 숨김/키 상실). 이후 복원 개입을 멈춘다. 다시 보일 때 attach/키획득 경로에서 재캡처된다.
    func clearAnchor() {
        anchorTopY = nil
        anchorMaxX = nil
    }

    // MARK: - Notification wiring

    private func installObservers(on window: NSWindow) {
        // 창이 보이게 될 때(키 획득): 시스템 배치가 끝난 다음 런루프 턴에 앵커 캡처.
        let becomeKey = notificationCenter.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleCapture()
                self?.onVisibilityChange?(true)
            }
        }
        // 콘텐츠 높이 변화(리사이즈) → maxY가 앵커에서 벗어났으면 복원(아래로만 성장/수축).
        let resize = notificationCenter.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.restoreIfNeeded() }
        }
        // 시스템 임의 이동 → 동일 복원(창이 보이는 동안만; 숨김이면 앵커가 nil이라 no-op).
        let move = notificationCenter.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.restoreIfNeeded() }
        }
        // 창이 숨겨질 때(키 상실 → orderOut): 앵커 해제, 개입 중단. 다시 열리면 재캡처(상태바 아이콘 이동 대응).
        let resignKey = notificationCenter.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearAnchor()
                self?.onVisibilityChange?(false)
            }
        }
        observers = [becomeKey, resize, move, resignKey]
    }

    private func removeObservers() {
        observers.forEach { notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    /// 다음 런루프 턴에 앵커를 캡처한다. 시스템이 상태바 아이템 아래로 배치를 끝낸 뒤 값을 잡기 위함.
    private func scheduleCapture() {
        Task { @MainActor [weak self] in
            self?.captureAnchor()
        }
    }
}

/// MenuBarExtra 콘텐츠가 속한 NSWindow를 찾아 `WindowTopAnchor`에 물려 주는, 그림을 그리지 않는 배경 뷰.
///
/// CheckApp의 MenuBarExtra 콘텐츠 `.background(WindowAnchorAccessor())`로 부착한다. 코디네이터가
/// 앵커 로직(`WindowTopAnchor`)을 소유하고, 뷰가 창 계층에 붙으면 그 창을 앵커에 연결한다.
struct WindowAnchorAccessor: NSViewRepresentable {
    /// 창 표시/숨김(키 획득/상실)을 상위로 알리는 콜백. 팝오버 표시 감지의 이중 안전망(onAppear/onDisappear 와 수렴).
    var onVisibilityChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> WindowTopAnchor {
        WindowTopAnchor()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onVisibilityChange = onVisibilityChange
        // 첫 update 시 뷰가 아직 창 계층에 붙기 전일 수 있으니 다음 턴에 창을 잡는다. attach는 멱등이라
        // 콘텐츠 변화로 update가 반복돼도 같은 창이면 즉시 반환한다(재캡처는 창 노티가 담당).
        Task { @MainActor in
            guard let window = nsView.window else { return }
            coordinator.attach(to: window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: WindowTopAnchor) {
        coordinator.detach()
    }
}

// MARK: - 팝오버 닫기 (실측 근거는 아래 주석)

/// `dismissMenuPopover()` 가 **무엇을 했는지**. 헤드리스에서는 창 서버를 흉내 낼 수 없으므로
/// 값으로 확인할 수 있는 것이 판단뿐이다 — 그래서 Bool 이 아니라 이유를 돌려준다.
enum MenuPopoverDismissal: Equatable {
    /// 상태바 아이템을 눌러 실제로 닫았다.
    case dismissed
    /// 팝오버가 안 떠 있어 **아무것도 하지 않았다.** 이 자리에서 누르면 오히려 팝오버가 열린다.
    case notPresented
    /// 상태바 버튼을 못 찾았다(상태 아이템이 없는 실행 — 테스트 프로세스 등).
    case noStatusItem
    /// 방금 닫았다. 연달아 누르면 토글이라 도로 열리므로 두 번째는 삼킨다.
    case debounced
}

extension WindowTopAnchor {
    /// 팝오버(MenuBarExtra 창)를 닫는다. 사용자 요구 2026-09-10: "미니게임 버튼은 눌렀을 때 미니게임 창
    /// 열리면서 상단 탭바 화면은 닫히게 해줘."
    ///
    /// **왜 상태바 버튼을 누르는가 — 네 후보를 실제로 재 본 결과다**(MenuBarExtra(.window) 최소 재현 앱,
    /// 화면 사실은 `CGWindowListCopyWindowInfo` 로 밖에서 세고, 되열기는 상태바 아이콘 클릭 횟수로 셌다):
    ///
    /// | 후보                                   | 팝오버가 닫히나 | 아이콘 한 번 클릭으로 되열리나 |
    /// |----------------------------------------|-----------------|--------------------------------|
    /// | 다른 창을 `NSApp.activate`+key 로 띄우기 | **아니오**      | —                              |
    /// | `window.resignKey()`                    | **아니오**      | —                              |
    /// | `window.orderOut(nil)`                  | 예              | **아니오(두 번 눌러야 열린다)** |
    /// | `window.close()`                        | 예              | **아니오(두 번 눌러야 열린다)** |
    /// | **상태바 버튼 `performClick`**          | **예**          | **예**                         |
    ///
    /// 읽는 법이 셋이다.
    ///  1. **설정 창이 팝오버를 닫아 왔다는 말은 사실이 아니다.** 앱 활성화 경로(`NSApp.activate()` +
    ///     `makeKeyAndOrderFront`)로는 팝오버가 그대로 떠 있다 — 실측 1행. 그래서 이 문이 필요하다.
    ///  2. `orderOut`/`close` 는 **화면에서는 지워지지만 SwiftUI 의 표시 상태가 어긋난다.** 다음 클릭이
    ///     "닫기"로 소모돼 사용자는 두 번 눌러야 팝오버를 다시 연다. 게다가 `close()` 는 창 객체까지
    ///     없애서(다음 열기는 새 인스턴스다) 앵커의 약참조가 끊긴다. 둘 다 쓰면 안 되는 이유다.
    ///  3. 상태바 버튼을 누르는 것은 **사용자가 아이콘을 다시 클릭한 것과 같은 경로**라 상태가 갈릴 곳이
    ///     없다. `NSStatusBarButton` 은 공개 클래스이고 `performClick(_:)` 도 공개 API 다.
    ///
    /// **닫힌 뒤 `setMenuPresented(false)` 는 흐른다.** 같은 재현 앱에서 잰 사실: 이 경로로 닫으면
    /// 콘텐츠의 `onDisappear` 가 매번 발화한다(`CheckMenuView` 가 거기서 흘린다). 앵커의
    /// `didResignKey` 쪽은 이 경로에서 발화하지 않으므로 **그 이중 안전망에 기대면 안 된다** — 티커·폴링
    /// 게이팅이 "열려 있다"로 굳는지의 답은 `onDisappear` 한 줄에 달려 있다.
    ///
    /// 토글이라 **팝오버가 안 떠 있을 때 부르면 오히려 열린다.** 그래서 누르기 전에 두 번 되묻는다.
    @discardableResult
    static func dismissMenuPopover(now: Date = Date()) -> MenuPopoverDismissal {
        let button = statusItemButton()
        let decision = dismissDecision(
            presented: isMenuPopoverPresented(),
            hasStatusItem: button != nil,
            lastDismissAt: lastDismissAt,
            now: now
        )
        guard decision == .dismissed else { return decision }
        lastDismissAt = now
        button?.performClick(nil)
        return decision
    }

    /// 무엇을 할지 정하는 **순수** 판단(헤드리스 검증 지점). 창 서버를 흉내 낼 수 없으므로 실제 클릭은
    /// 잴 수 없지만, 누를지 말지를 가르는 표는 전부 여기 있다 — 위 `dismissMenuPopover` 는 이 결정을
    /// 그대로 따르는 얇은 배선일 뿐이다.
    ///
    /// 순서가 곧 뜻이다. `presented` 가 맨 앞인 이유는 **누르는 것이 토글**이기 때문이다 — 안 떠 있는데
    /// 누르면 닫는 게 아니라 연다. 디바운스가 상태 아이템 확인보다 앞인 이유는, 방금 눌러 놓고 아직
    /// 창 서버 목록이 안 따라잡은 순간에도 두 번째 클릭을 막아야 하기 때문이다.
    static func dismissDecision(
        presented: Bool,
        hasStatusItem: Bool,
        lastDismissAt: Date?,
        now: Date
    ) -> MenuPopoverDismissal {
        guard presented else { return .notPresented }
        if let lastDismissAt, now.timeIntervalSince(lastDismissAt) < dismissDebounce { return .debounced }
        guard hasStatusItem else { return .noStatusItem }
        return .dismissed
    }

    /// 팝오버가 지금 **실제로** 화면에 서 있는가.
    ///
    /// `NSWindow.isVisible` 은 이 저장소에서 이미 한 번 거짓말했다(v0.2.27 — 창은 어느 Space 에도 없는데
    /// true 였다). 그래서 창 서버에 되묻는 같은 도구를 재사용한다(`CheckTodoBoardController.isOnScreen` —
    /// 두 벌로 만들면 언젠가 두 판정이 갈린다). 그 질의가 "모른다"(nil)를 돌려주면 AppKit 의 대답으로
    /// 내려간다: 이 문을 부르는 자리는 **팝오버 안의 버튼**이라, 모를 때는 떠 있다고 보는 쪽이 맞다.
    static func isMenuPopoverPresented() -> Bool {
        guard let window = current?.window else { return false }
        if let onScreen = CheckTodoBoardController.isOnScreen(window) { return onScreen }
        return window.isVisible
    }

    /// 우리 상태 아이템의 버튼. `NSStatusBarButton` 은 공개 클래스라 클래스 이름 문자열을 더듬지 않는다.
    /// 이 앱의 상태 아이템은 `MenuBarExtra` 하나뿐이라 처음 찾은 것이 곧 그것이다.
    ///
    /// ★ **`NSApp` 을 반드시 `if let` 으로 받는다.** 이것은 `NSApplication!`(암시적 언래핑)이고,
    ///   `NSApplication.shared` 를 한 번도 안 만든 프로세스에서는 **nil** 이다 — 헤드리스 테스트가 딱 그렇다.
    ///   `NSApp.windows` 로 바로 읽으면 그 자리에서 프로세스가 죽는다(v0.2.49 통합에서 실제로 크래시했다:
    ///   `openMiniGameWindow()` → `dismissMenuPopover()` → 여기). `NSApplication.shared` 로 대신 받지도
    ///   마라 — 그 접근이 앱 객체를 **만들어** 테스트 프로세스를 GUI 앱으로 승격시킨다.
    ///   nil 이면 누를 상태 아이템이 없다는 뜻이고, 그 답이 곧 `.noStatusItem` 이다.
    private static func statusItemButton() -> NSStatusBarButton? {
        guard let app: NSApplication = NSApp else { return nil }
        for window in app.windows {
            if let button = firstStatusBarButton(in: window.contentView) { return button }
        }
        return nil
    }

    private static func firstStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = firstStatusBarButton(in: subview) { return button }
        }
        return nil
    }

    /// 중복 방어 래치를 비운다. **테스트 전용** — 한 프로세스에서 여러 판정을 이어 재려면
    /// 앞 테스트가 눌러 둔 시각이 다음 테스트를 `.debounced` 로 만들기 때문이다.
    static func resetDismissDebounceForTesting() {
        lastDismissAt = nil
    }
}
