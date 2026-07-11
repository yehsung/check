import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - 헤드리스 창 헬퍼

/// 화면 제약(`constrainFrameRect`) 없이 지정한 프레임을 정확히 갖는 헤드리스 테스트 창.
/// 앵커 좌표 산술을 화면 크기와 무관하게 결정적으로 검증하기 위해 화면 클램프를 끈다.
private final class UnconstrainedTestWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// 지정 프레임의 헤드리스 창과, 그 창에 붙인 앵커를 만든다.
/// - 격리된 NotificationCenter를 써 전역 노티 오염을 막는다. 이 창은 orderFront 하지 않으므로(=isVisible false)
///   attach가 자동 캡처를 예약하지 않는다 → 테스트는 captureAnchor/restoreIfNeeded를 직접 호출해 결정적으로 검증한다.
@MainActor
private func makeAnchoredWindow(_ frame: NSRect) -> (NSWindow, WindowTopAnchor) {
    let window = UnconstrainedTestWindow(
        contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.setFrame(frame, display: false)
    let anchor = WindowTopAnchor(notificationCenter: NotificationCenter())
    anchor.attach(to: window)
    return (window, anchor)
}

// MARK: - 1) 콘텐츠 높이 증가 → 위쪽 모서리 고정, 아래로만 성장

@MainActor
@Test
func topAnchorKeepsTopFixedWhenContentGrows() {
    let (window, anchor) = makeAnchoredWindow(NSRect(x: 200, y: 300, width: 340, height: 200))
    // 클램프 상한을 프레임보다 크게 둬 클램프 없이(순수 산술) 검증한다.
    anchor.captureAnchor(screenVisibleMaxY: 10_000)
    #expect(anchor.anchorTopY == 500)   // 300 + 200
    #expect(anchor.anchorMaxX == 540)   // 200 + 340

    let originYBefore = window.frame.origin.y   // 300
    // 콘텐츠 높이 증가: AppKit은 좌하단 원점을 유지한 채 리사이즈 → maxY가 위로 자란다(버그 재현).
    window.setContentSize(NSSize(width: 340, height: 400))
    #expect(window.frame.maxY == 700)           // 버그: 위로 튐

    #expect(anchor.restoreIfNeeded() == true)
    // 위쪽 모서리 고정: maxY가 앵커로 복귀.
    #expect(window.frame.maxY == 500)
    // 오른쪽 모서리 고정.
    #expect(window.frame.maxX == 540)
    // 아래로만 성장: origin.y 감소(창이 아래로 자람).
    #expect(window.frame.origin.y < originYBefore)
    #expect(window.frame.origin.y == 100)       // 500 - 400
    // 새 높이는 유지(동적 높이 보존).
    #expect(window.frame.height == 400)

    // 멱등: 이미 앵커에 맞으므로 두 번째 복원은 개입하지 않는다.
    #expect(anchor.restoreIfNeeded() == false)
}

// MARK: - 2) 콘텐츠 높이 감소 → 위쪽 모서리 유지

@MainActor
@Test
func topAnchorKeepsTopFixedWhenContentShrinks() {
    let (window, anchor) = makeAnchoredWindow(NSRect(x: 200, y: 300, width: 340, height: 200))
    anchor.captureAnchor(screenVisibleMaxY: 10_000)

    // 콘텐츠 높이 감소: 좌하단 원점 유지 → maxY가 아래로 내려간다.
    window.setContentSize(NSSize(width: 340, height: 120))
    #expect(window.frame.maxY == 420)           // 앵커(500)에서 벗어남

    #expect(anchor.restoreIfNeeded() == true)
    // 위쪽 모서리 유지: maxY가 앵커로 복귀.
    #expect(window.frame.maxY == 500)
    #expect(window.frame.height == 120)
    #expect(window.frame.origin.y == 380)       // 500 - 120 (위로 붙어 아래로만 줄어듦)
}

// MARK: - 3) 시스템 이동 → 위쪽 모서리 복원

@MainActor
@Test
func topAnchorRestoresAfterSystemMove() {
    let (window, anchor) = makeAnchoredWindow(NSRect(x: 200, y: 300, width: 340, height: 200))
    anchor.captureAnchor(screenVisibleMaxY: 10_000)

    // 시스템이 창을 위로 이동시켰다고 가정(origin.y 상승 → maxY 상승).
    window.setFrameOrigin(NSPoint(x: 200, y: 360))
    #expect(window.frame.maxY == 560)

    #expect(anchor.restoreIfNeeded() == true)
    #expect(window.frame.maxY == 500)
    #expect(window.frame.maxX == 540)
    // 크기 변화가 없었으므로 원래 원점으로 완전 복원.
    #expect(window.frame.origin == NSPoint(x: 200, y: 300))
}

// MARK: - 4) 숨김(clearAnchor) 후엔 개입하지 않음

@MainActor
@Test
func topAnchorDoesNotInterveneWhileHidden() {
    let (window, anchor) = makeAnchoredWindow(NSRect(x: 200, y: 300, width: 340, height: 200))
    anchor.captureAnchor(screenVisibleMaxY: 10_000)

    // 창 숨김(orderOut → 키 상실) 시뮬레이션.
    anchor.clearAnchor()
    #expect(anchor.anchorTopY == nil)
    #expect(anchor.anchorMaxX == nil)

    // 숨김 상태에서 콘텐츠가 커져도(또는 이동해도) 복원에 개입하지 않는다.
    window.setContentSize(NSSize(width: 340, height: 400))
    let maxYAfterResize = window.frame.maxY     // 700
    #expect(anchor.restoreIfNeeded() == false)
    #expect(window.frame.maxY == maxYAfterResize)   // 그대로 — 개입 안 함
}

// MARK: - 5) 재표시 시 새 위치 기준으로 앵커 재캡처

@MainActor
@Test
func topAnchorRecapturesAtNewPositionOnReshow() {
    let (window, anchor) = makeAnchoredWindow(NSRect(x: 200, y: 300, width: 340, height: 200))
    anchor.captureAnchor(screenVisibleMaxY: 10_000)
    #expect(anchor.anchorTopY == 500)

    // 숨김.
    anchor.clearAnchor()
    // 상태바 아이콘 이동 등으로 시스템이 새 위치에 창을 배치.
    window.setFrame(NSRect(x: 900, y: 620, width: 340, height: 200), display: false)

    // 재표시 → 새 위치 기준으로 앵커 재캡처(옛 앵커에 얽매이지 않음).
    anchor.captureAnchor(screenVisibleMaxY: 10_000)
    #expect(anchor.anchorTopY == 820)    // 620 + 200
    #expect(anchor.anchorMaxX == 1_240)  // 900 + 340

    // 이후 성장은 새 앵커 기준으로 복원.
    window.setContentSize(NSSize(width: 340, height: 300))
    #expect(anchor.restoreIfNeeded() == true)
    #expect(window.frame.maxY == 820)        // 옛 앵커(500)가 아니라 새 앵커.
    #expect(window.frame.origin.y == 520)    // 820 - 300
}

// MARK: - 6) 앵커 캡처 시 화면 상단 초과 방지 클램프

@MainActor
@Test
func captureClampsAnchorToScreenTop() {
    // 창 위쪽 모서리가 화면 상단(visibleFrame.maxY)을 넘으면 앵커를 화면 상단으로 클램프한다.
    let (_, anchor) = makeAnchoredWindow(NSRect(x: 200, y: 300, width: 340, height: 400))
    // frame.maxY = 700. 화면 상단을 600으로 두면 700 > 600 → 600으로 클램프.
    anchor.captureAnchor(screenVisibleMaxY: 600)
    #expect(anchor.anchorTopY == 600)
    #expect(anchor.anchorMaxX == 540)   // maxX는 클램프 대상 아님.
}

// MARK: - 7) 창 키 획득/상실 → 표시 감지 콜백 발화 (팝오버 게이팅 이중 안전망)

@MainActor
@Test
func visibilityCallbackFiresOnKeyChanges() {
    let center = NotificationCenter()
    let window = UnconstrainedTestWindow(
        contentRect: NSRect(x: 200, y: 300, width: 340, height: 200),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    let anchor = WindowTopAnchor(notificationCenter: center)
    var events: [Bool] = []
    anchor.onVisibilityChange = { events.append($0) }
    anchor.attach(to: window)

    // 키 획득(창 표시)은 true, 키 상실(창 숨김)은 false 로 상위(setMenuPresented)에 전달돼야 한다.
    center.post(name: NSWindow.didBecomeKeyNotification, object: window)
    center.post(name: NSWindow.didResignKeyNotification, object: window)

    #expect(events == [true, false])
}
