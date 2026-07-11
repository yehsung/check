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

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - Attach / detach

    /// 창을 잡고 노티를 배선한다. 같은 창으로 다시 불리면 무시(멱등). 창이 이미 보이면 초기 앵커를 예약한다.
    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        removeObservers()
        self.window = window
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
