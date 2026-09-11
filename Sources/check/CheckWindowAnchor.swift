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
    ///
    /// **여는 쪽과 닫는 쪽이 이 한 값을 나눠 쓴다**(v0.2.50). 누르는 수단이 같은 버튼 하나라, 방어선을
    /// 방향마다 따로 두면 "닫자마자 열기"가 서로를 못 보고 두 번 눌러 결과가 제자리로 돌아온다.
    private static var lastToggleClickAt: Date?
    /// 그 방어선의 길이(여닫기 공용). 사람이 두 번 누를 수 있는 간격보다는 짧고, 한 동작 안의 두 호출보다는 길다.
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
        let view = AnchorHostView(frame: .zero)
        view.onMoveToWindow = { [coordinator = context.coordinator] window in coordinator.attach(to: window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onVisibilityChange = onVisibilityChange
        (nsView as? AnchorHostView)?.onMoveToWindow = { window in coordinator.attach(to: window) }
        // 이미 창에 붙어 있으면 지금 잡는다. attach 는 멱등이라 콘텐츠 변화로 update 가 반복돼도 같은 창이면
        // 즉시 반환한다(재캡처는 창 노티가 담당).
        if let window = nsView.window { coordinator.attach(to: window) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: WindowTopAnchor) {
        coordinator.detach()
    }
}

/// 창 계층에 **붙는 순간**을 알리는 빈 뷰(그림은 안 그린다).
///
/// ★ **왜 `updateNSView` 안의 `Task` 로는 모자랐나 — 관측과 추론을 갈라 적는다.**
///
///   **관측된 것(2026-09-11 프로브).** 옛 구현은 첫 `updateNSView` 에서 다음 턴(`Task`)에 `nsView.window`
///   를 보고 창을 잡았다. 한 프로브 실행에서 그 줄이 창을 **못 잡았다**: `probeAnchor updateNSView window=-1`
///   (창 없음) 뒤 `nextTurn window=-1 current=false presented=false`(bubble-220030.log). 그 실행에서는
///   `WindowTopAnchor.current` 가 끝까지 nil 이었다.
///
///   **관측되지 않은 것 — 이 자리의 처음 주석이 과장했다.** 옛 코드로도 **앵커가 붙는 실행이 있다**:
///   검토가 같은 옛 코드를 별도 번들 프로브로 재빌드해 붙는 것을 확인했다. 그러니 이것은 "결정적 실패"가
///   아니라 **`Task` hop 타이밍 레이스**다 — hop 이 팝오버 창이 서기 전에 돌면 놓치고, 뒤에 돌면 잡는다.
///   처음 주석이 거기서 파생시킨 단언들("`isMenuPopoverPresented()` 가 **언제나** false",
///   "말풍선 클릭이 **늘** 대화를 닫는다", "`dismissMenuPopover` 가 아무것도 못 닫는다")도 같은 과장이다 —
///   전부 **레이스에서 진 실행에만** 해당한다.
///
///   **추론(관측에서 따라오는 것, 실행마다 확인하지는 않았다).** 레이스에서 지면 그 실행 동안 `current` 가
///   nil 이고, 거기 매달린 것이 조용히 죽는다: `isMenuPopoverPresented()` 가 false 로 답하므로
///   `presentMenuPopover()` 는 **떠 있는 팝오버에도 버튼을 눌러 그것을 닫고**(말풍선을 눌렀는데 대화가
///   닫히는 모양 — 검토가 지목한 `.alreadyPresented` 구멍), `dismissMenuPopover()` 는 반대로 아무것도
///   안 닫으며, 위쪽 모서리 고정(`restoreIfNeeded`)도 키 획득/상실 통지(`onVisibilityChange`)도 안 돈다.
///   사용자에게는 "가끔 그런다"로 보인다 — 그 간헐성이 이 결함을 오래 못 잡은 이유다.
///
///   **그래서 이 뷰는 유지할 값어치가 있다.** `viewDidMoveToWindow` 는 SwiftUI 재평가나 런루프 순서에
///   기대지 않는다 — 창에 붙는 그 순간 AppKit 이 부르므로 **레이스가 성립할 자리 자체가 없어진다**
///   (이길 확률을 올리는 것이 아니라 조건을 없앤다). (같은 이유로 `CheckEditorTextView` 도 포커스를
///   이 자리에서 잡는다.)
final class AnchorHostView: NSView {
    /// 창에 붙었을 때 한 번. 창에서 떼어질 때는 부르지 않는다(그 자리는 `detach` 가 맡는다).
    var onMoveToWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        MainActor.assumeIsolated { onMoveToWindow?(window) }
    }
}

// MARK: - 팝오버 닫기 (실측 근거는 아래 주석)

/// 상태바 버튼을 눌러 **어느 쪽으로 가려는가**. 누르는 수단이 토글 하나뿐이라 방향은 판정의 입력이다.
enum MenuPopoverIntent: Equatable, Sendable {
    case dismiss
    case present
}

/// 그 판정의 결과(여닫기 공용).
enum MenuPopoverToggleDecision: Equatable, Sendable {
    /// 눌러야 한다.
    case click
    /// **이미 원하는 상태다.** 여기서 누르면 오히려 반대로 뒤집힌다.
    case alreadySettled
    /// 상태바 버튼을 못 찾았다(상태 아이템이 없는 실행 — 테스트 프로세스 등).
    case noStatusItem
    /// 방금 눌렀다. 연달아 누르면 토글이라 도로 돌아오므로 두 번째는 삼킨다.
    case debounced
}

/// `presentMenuPopover()` 가 **무엇을 했는지**(닫는 쪽 `MenuPopoverDismissal` 과 같은 모양·같은 이유).
enum MenuPopoverPresentation: Equatable {
    /// 상태바 아이템을 눌러 실제로 열었다.
    case presented
    /// 팝오버가 이미 떠 있어 **아무것도 하지 않았다.** 이 자리에서 누르면 오히려 닫힌다.
    case alreadyPresented
    /// 상태바 버튼을 못 찾았다(상태 아이템이 없는 실행 — 테스트 프로세스 등).
    case noStatusItem
    /// 방금 눌렀다. 연달아 누르면 토글이라 도로 닫히므로 두 번째는 삼킨다.
    case debounced

    init(_ decision: MenuPopoverToggleDecision) {
        switch decision {
        case .click: self = .presented
        case .alreadySettled: self = .alreadyPresented
        case .noStatusItem: self = .noStatusItem
        case .debounced: self = .debounced
        }
    }
}

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
            lastDismissAt: lastToggleClickAt,
            now: now
        )
        guard decision == .dismissed else { return decision }
        lastToggleClickAt = now
        button?.performClick(nil)
        return decision
    }

    /// 팝오버를 **여는** 문(v0.2.50). 캐릭터 머리 위 '메시지 도착' 말풍선을 누른 경우가 유일한 호출부다 —
    /// 메시지가 별도 창에서 팝오버 하위 패널로 내려오면서, 그 클릭이 갈 곳이 팝오버 **안**이 됐다.
    ///
    /// **닫는 문과 같은 버튼·같은 판단이다.** 누르는 수단이 `NSStatusBarButton.performClick` 하나뿐이고
    /// 그것은 토글이라, 여는 일과 닫는 일의 차이는 "지금 떠 있는가"를 어느 쪽으로 읽느냐 하나다 —
    /// 그래서 판정을 두 벌로 만들지 않고 `menuPopoverToggleDecision(intent:)` 하나에 방향만 넘긴다.
    ///
    /// ⚠️ **여기서 확인할 수 있는 것은 판단까지다.** 헤드리스에서는 창 서버를 흉내 낼 수 없어 "정말 떴는가"는
    ///    이 프로세스로 잴 수 없다(닫는 문도 v0.2.49 부터 같은 한계 안에 있다 — 위 실측 표는 별도 재현 앱에서
    ///    `CGWindowListCopyWindowInfo` 로 밖에서 센 것이다). 그래서 실패해도 **조용히 아무 일도 없는 쪽**으로
    ///    틀리게 짰다: 패널 상태는 이 호출과 무관하게 이미 세워져 있으므로, 팝오버가 안 떠도 사용자가 다음에
    ///    아이콘을 누르면 그 대화가 그 자리에 있다.
    @discardableResult
    static func presentMenuPopover(now: Date = Date()) -> MenuPopoverPresentation {
        // ★ **판단보다 먼저 앱을 활성화한다.** 아래 함수 주석에 실측이 있다. 판단 뒤로 미루면
        //   `.alreadySettled`(말풍선을 눌렀는데 팝오버가 이미 떠 있는 경우)에서 활성화가 건너뛰어져,
        //   그 사용자는 **떠 있는 팝오버에 한글을 못 치는 상태**로 남는다 — 증상 ①이 가장 자주 나는 모양이고,
        //   그 갈래에서는 버튼을 누르는 것이 답이 될 수 없다(누르면 그 팝오버가 닫힌다).
        activateForKeyboardInput()
        let button = statusItemButton()
        let decision = menuPopoverToggleDecision(
            intent: .present,
            presented: isMenuPopoverPresented(),
            hasStatusItem: button != nil,
            lastClickAt: lastToggleClickAt,
            now: now
        )
        guard decision == .click else { return MenuPopoverPresentation(decision) }
        lastToggleClickAt = now
        button?.performClick(nil)
        return .presented
    }

    /// 팝오버를 **프로그램으로** 열 때 앱을 활성 상태로 만든다. 증상 ①(한글 자음·모음 분리)의 원인 자리다.
    ///
    /// **왜 활성화가 필요한가**(2026-09-11 실측):
    ///   · 이 문의 유일한 호출부는 캐릭터 머리 위 '메시지 도착' 말풍선 클릭이고(`CheckApp.swift`),
    ///     그 말풍선 창은 `nonactivatingPanel`(`CheckOverlayWindow.makePanel`)이라 **클릭이 앱을 활성화하지
    ///     않는다** — 말풍선을 CGEvent 로 진짜 클릭해 재 봤다: `BUBBLE mouseDown appActive=false panelKey=false`
    ///     (bubble-215806.log 12.77s). 그 패널은 borderless 라 `canBecomeKey=false` 이기도 해서, 클릭해도
    ///     key 창조차 생기지 않는다.
    ///   · 팝오버 창 자체는 `nonactivatingPanel`(측정 styleMask 0x8080)이라 **앱 활성 없이 키를 받는다.**
    ///     입력 문맥(`NSTextInputContext.current`)은 앱이 활성일 때만 켜지므로, 키는 들어오는데 입력기는
    ///     돌지 않는다 → 한글이 **날것의 자모**로 박힌다. 같은 하네스에서 재현했다(bubble-215806.log
    ///     15.47~15.79s: 비활성으로 시작한 한 묶음이 "ㅇ" → "ㅇㅏ" → "ㅇㅏㄴ"). 반대로 활성인 채 친 묶음은
    ///     `marked=true` 로 "ㅇ" → "아" → "안" 이 됐다(bubble-220030.log 46.3~46.6s) — 즉 2벌식 한글은
    ///     표시 글자를 **쓴다.** 예전에 "안 쓴다"로 잰 것은 이 꺼진 상태를 잰 것이었다.
    ///   · 더 나쁜 것: 한 번 꺼진 채 시작한 묶음은 **그 묶음 내내 날것으로 남았다**(첫 타에 앱이 활성으로
    ///     바뀐 뒤의 2·3타도 조합되지 않았다 — 같은 로그 15.5~15.8s). 그래서 "첫 타자에서 되살리기"로는
    ///     못 고치고, **팝오버가 서는 이 순간에** 끝내야 한다.
    ///
    /// **무엇이 실제로 먹는가 — 후보를 하나씩 재 봤다**(Finder 를 프런트로 만든 뒤 말풍선을 CGEvent 로 클릭,
    /// 클릭 핸들러 안에서 후보를 부르고 0.1·0.4·1.0초 뒤 상태를 찍었다. bubble-220030.log):
    ///
    /// | 후보                                        | 클릭 핸들러 안에서 | 결과                                   |
    /// |---------------------------------------------|--------------------|----------------------------------------|
    /// | `NSApp.activate()`                          | **먹는다**         | 호출 직후엔 `isActive=false` 인데 **14~35ms 뒤** `DidBecomeActive` + 팝오버 창이 key 로 돌아왔다(유휴 상태 7회 재측정, 7/7 첫 타자부터 정상 조합). |
    /// | `NSApp.activate(ignoringOtherApps: true)`   | 먹는다(같음)       | 위와 구별되는 이점이 없다 — 그래서 안 쓴다(더 센 API 를 쓸 이유가 없다). |
    /// | 상태바 버튼 `performClick` **만**            | **못 믿는다**      | 그 상태에서 눌렀더니 활성화도, 팝오버도 없었다(33.75s: `appActive=false`, 1초 뒤도 false). AppKit 이 팝오버를 "열려 있다"로 알고 있으면 그 클릭은 **닫는** 클릭이다. |
    /// | activate + `performClick`(지금 코드)         | 먹는다             | 44.008s 클릭 → 44.022s 활성 + 팝오버 key. 닫혀 있던 경우엔 클릭이 열고, 가려져 있던 경우엔 활성화가 되살린다. |
    ///
    /// ⏱ **그 여유가 얼마인가 — 숫자를 과장하지 마라.** 위 표의 "14~35ms"는 **유휴 상태 7회**를 다시 잰
    ///    범위다(처음 이 자리에는 한 번 관측한 `6ms` 가 표로 못 박혀 있었다 — 그 숫자로 여유를 계산하지 마라).
    ///    결론은 7/7 그대로다: 팝오버가 선 뒤 **첫 타자부터 한글이 정상 조합된다.** 다만 이 여유는
    ///    **부하에서는 좁아진다**(활성화 완료는 메인 런루프가 돌려주는 비동기 통지다 — 앱이 바쁘면 늦게 온다).
    ///    그래도 이 한 줄에 거는 이유: **`keyDown` 쪽 방어선은 한 번 꺼진 채 시작한 묶음을 못 구한다**
    ///    (`CheckEditorTextView.activateAppForTypedInputIfNeeded` 의 실측 — 첫 타에 활성화가 끝나도 그 묶음의
    ///    2·3타는 날것으로 들어갔다). 그러니 **이 여유가 사실상 유일한 방어선**이고, 좁아지면 좁아지는 만큼
    ///    첫 묶음이 자모로 박힐 위험이 남는다.
    ///
    /// 읽는 법이 둘이다.
    ///  1. **`activate()` 는 "안 먹는" 것이 아니라 "사용자 이벤트 안에서만" 먹는다.** 타이머에서 부르면
    ///     3초 뒤에도 `appActive=false` 였다(activate-213108.log, 3회 모두). macOS 는 앱이 **스스로** 앞자리를
    ///     뺏는 것만 막는다 — 사용자가 우리 창을 누른 그 처리 중에는 허락한다. 그래서 이 문은 반드시
    ///     클릭 핸들러 사슬 안에서만 불려야 하고(지금 유일한 호출부가 그렇다), **비동기로 완료된다**
    ///     (돌아온 직후 `isActive` 를 읽어 판단하는 코드를 쓰지 마라 — 아직 false 다).
    ///  2. **`performClick` 은 활성화 수단이 아니다.** 팝오버가 닫혀 있을 때만 열면서 활성화를 데려온다.
    ///     앱이 비활성이 되면 팝오버 창은 화면에서 사라지는데(측정: `vis=false`) AppKit 은 여전히 열린 것으로
    ///     알고 있을 수 있어, 그 상태의 클릭은 **닫기**로 소모된다. 활성화는 activate 가, 열기는 클릭이 한다.
    ///
    /// **고친 뒤 세 상태를 다시 다 재 봤다**(말풍선을 CGEvent 로 클릭. bubble2-222718.log):
    ///   · A 팝오버 떠 있음 + 앱 활성   → `alreadyPresented`(버튼을 안 누른다 = 그 대화가 닫히지 않는다),
    ///     그대로 한글 조합 정상(`marked=true` "ㅇ"→"아"→"안", 12.4~12.7s).
    ///   · B 팝오버 떠 있음 + 앱 **비활성** → 클릭 전 상태가 `currentCtx=false`(= 자모가 박히는 그 상태)였는데,
    ///     `alreadyPresented` 로 버튼은 안 누르고 **활성화만** 18ms 뒤 완료(mouseUp 17.798 → DidBecomeActive
    ///     17.816) → 문맥이 켜지고 조합 정상. **검토가 지목한 그 구멍이 닫혔다.**
    ///   · C 팝오버 닫힘 + 앱 비활성 → `presented`(클릭이 연다) + 33ms 뒤 활성(27.441 → 27.474), 조합 정상.
    ///
    /// **왜 창을 따로 key 로 만들지 않나**: 활성화 한 줄이 이미 창을 key 로 되돌린다(위 표의 활성화 줄).
    /// 우리가 `makeKey()` 를 더 부르면 아직 서지 않은 창을 붙들어 SwiftUI 의 표시 상태와 어긋난다 —
    /// `dismissMenuPopover` 주석의 실측 표가 `orderOut`/`close` 에서 이미 겪은 종류의 어긋남이다.
    ///
    /// **왜 이미 활성이면 아무것도 안 하나**: `activate()` 는 부를 때마다 다른 앱에서 포커스를 빼앗는다.
    /// 사용자가 우리 팝오버를 이미 쓰고 있는 정상 경로에서 그 짓을 반복할 이유가 없다.
    ///
    /// `NSApp` 을 `if let` 으로 받는 이유는 `statusItemButton()` 주석과 같다 — 헤드리스 테스트 프로세스에서는
    /// nil 이고, `NSApplication.shared` 로 받으면 그 접근이 앱 객체를 **만들어** 테스트를 GUI 앱으로 승격시킨다.
    private static func activateForKeyboardInput() {
        guard let app: NSApplication = NSApp, !app.isActive else { return }
        app.activate()
    }

    /// 무엇을 할지 정하는 **순수** 판단(헤드리스 검증 지점). 창 서버를 흉내 낼 수 없으므로 실제 클릭은
    /// 잴 수 없지만, 누를지 말지를 가르는 표는 전부 여기 있다 — `dismissMenuPopover`/`presentMenuPopover` 는
    /// 이 결정을 그대로 따르는 얇은 배선일 뿐이다.
    ///
    /// 순서가 곧 뜻이다. `presented` 판정이 맨 앞인 이유는 **누르는 것이 토글**이기 때문이다 — 원하는 상태에
    /// 이미 있으면 누르는 것이 그 상태를 되돌린다(안 떠 있는데 '닫으려' 누르면 열리고, 떠 있는데 '열려'
    /// 누르면 닫힌다). 디바운스가 상태 아이템 확인보다 앞인 이유는, 방금 눌러 놓고 아직 창 서버 목록이
    /// 안 따라잡은 순간에도 두 번째 클릭을 막아야 하기 때문이다.
    static func menuPopoverToggleDecision(
        intent: MenuPopoverIntent,
        presented: Bool,
        hasStatusItem: Bool,
        lastClickAt: Date?,
        now: Date
    ) -> MenuPopoverToggleDecision {
        let needsClick = (intent == .dismiss) ? presented : !presented
        guard needsClick else { return .alreadySettled }
        if let lastClickAt, now.timeIntervalSince(lastClickAt) < dismissDebounce { return .debounced }
        guard hasStatusItem else { return .noStatusItem }
        return .click
    }

    /// 닫는 쪽의 이름표. **판단은 위 하나뿐이고 여기서는 이름만 갈아입힌다** — 두 벌로 나뉘면 언젠가
    /// 한쪽만 고쳐진다(이 저장소가 게이트를 짝으로 관리하는 이유와 같다).
    static func dismissDecision(
        presented: Bool,
        hasStatusItem: Bool,
        lastDismissAt: Date?,
        now: Date
    ) -> MenuPopoverDismissal {
        switch menuPopoverToggleDecision(
            intent: .dismiss,
            presented: presented,
            hasStatusItem: hasStatusItem,
            lastClickAt: lastDismissAt,
            now: now
        ) {
        case .click: return .dismissed
        case .alreadySettled: return .notPresented
        case .noStatusItem: return .noStatusItem
        case .debounced: return .debounced
        }
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
        lastToggleClickAt = nil
    }
}
