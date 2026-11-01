#if os(iOS)
import CheckCore
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// 폰 1.0.16 — 체스 판 위 투명한 터치 면. 탭과 끌기를 **인식기 하나**로 받는다(판단은 `GamesChessBoardTouch`).
//
// ## 왜 SwiftUI 제스처가 아닌가
// 판은 `ScrollView` 안에 있다. `DragGesture(minimumDistance: 0)` 를 `.gesture` 로 달면 판 위에서 스크롤이 죽고,
// `.simultaneousGesture` 로 달면 말을 끄는 동안 화면이 같이 움직이며 스크롤이 이기면 `onEnded` 가 안 온다.
// SwiftUI 에는 "문턱을 넘은 순간 내가 집을지 스크롤에 넘길지 정한다" 를 말할 자리가 없다. UIKit 에는 있다:
//
//  · 스크롤의 팬은 **이 인식기가 실패할 때까지 기다린다**(`shouldBeRequiredToFailBy`).
//  · 내 말에서 시작한 손이 문턱을 넘으면 `.began` — 스크롤은 시작도 못 한다.
//  · 그 밖의 손은 슬롭을 넘는 순간 `.failed` — 기다리던 스크롤이 **그 손 그대로** 이어 받는다.
//
// ## 왜 탭까지 여기서 받는가
// 맥 `ChessPlayBoard` 의 교훈 그대로다: 탭과 끌기를 둘로 나누면 문턱을 살짝 넘긴 누름에 둘이 함께 답해 "고르기가
// 해제되면서 끌린다" 가 된다. 탭의 판정(`onTapSquare`)은 전과 같은 입구로 나간다 — 2단은 스토어에 그대로 있다.

/// 판과 같은 크기의 투명한 면. 그림은 없다.
struct GamesChessBoardTouchSurface: UIViewRepresentable {
    let controller: GamesChessBoardDragController
    let port: GamesChessBoardDragController.Port

    func makeCoordinator() -> GamesChessBoardTouchRecognizer {
        GamesChessBoardTouchRecognizer(controller: controller)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        context.coordinator.port = port
        view.addGestureRecognizer(context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.port = port
    }

    /// 판이 화면에서 내려갔다 — 끌던 말을 걸쇠째 거둔다(결과 화면으로 넘어가는 자리).
    static func dismantleUIView(_ uiView: UIView, coordinator: GamesChessBoardTouchRecognizer) {
        coordinator.abandon()
    }
}

final class GamesChessBoardTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let controller: GamesChessBoardDragController
    var port: GamesChessBoardDragController.Port?
    /// 따라가는 손가락 하나. 둘째 손가락은 무시한다 — 끄는 중에 판을 받친 손이 말을 떨어뜨리면 안 된다.
    private weak var tracked: UITouch?

    init(controller: GamesChessBoardDragController) {
        self.controller = controller
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = false
    }

    func abandon() {
        controller.abandon(store: port?.store)
    }

    /// ★ 이 한 줄이 스크롤과의 계약이다: 판 위에서 시작한 손의 스크롤은 이 인식기가 **실패해야** 시작한다.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && other.view is UIScrollView
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard tracked == nil, let touch = touches.first, let view, let port else {
            touches.forEach { ignore($0, for: event) }
            return
        }
        tracked = touch
        touches.filter { $0 !== touch }.forEach { ignore($0, for: event) }
        controller.press(at: touch.location(in: view), port: port)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let tracked, touches.contains(tracked), let view, let port else { return }
        controller.move(to: tracked.location(in: view), port: port)
        switch state {
        case .possible:
            if controller.touch.draggingFrom != nil {
                state = .began
            } else if controller.touch.handsOffToScroll {
                state = .failed
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let tracked, touches.contains(tracked), let view, let port else { return }
        controller.release(at: tracked.location(in: view), port: port)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let tracked, touches.contains(tracked) else { return }
        abandon()
        state = state == .possible ? .failed : .cancelled
    }

    /// 끝나는 길이 무엇이든 UIKit 이 부른다 — 손을 잃은 채 말이 공중에 남는 일이 없게 여기서 한 번 더 치운다.
    /// (끝난 손은 이미 처음 상태라 아무 일도 안 한다.)
    override func reset() {
        super.reset()
        if tracked != nil { abandon() }
        tracked = nil
    }
}
#endif
