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

// MARK: - 8) 팝오버를 프로그램으로 닫는 문 (v0.2.49)
//
// 실측이 먼저다. MenuBarExtra(.window) 최소 재현 앱에서 후보 넷을 재 본 결과가
// `WindowTopAnchor.dismissMenuPopover` 주석의 표다. 요지 둘:
//   · 다른 창을 NSApp.activate + makeKeyAndOrderFront 로 띄워도 팝오버는 **안 닫힌다**.
//   · orderOut / close 는 화면에서 지우지만 SwiftUI 의 표시 상태가 어긋나 **다음 클릭이 삼켜진다**
//     (사용자는 두 번 눌러야 팝오버를 다시 연다). close 는 창 객체까지 없앤다.
// 그래서 남은 길은 상태바 아이템을 **한 번 더 누르는 것**뿐이고, 그건 토글이라 "지금 떠 있는가"를
// 반드시 먼저 물어야 한다. 아래 테스트는 그 판단표를 헤드리스에서 못 박는다
// (실제 클릭은 창 서버의 일이라 여기서 잴 수 없다 — 그래서 판단을 순수 함수로 갈라 뒀다).

@MainActor
@Test
func dismissDecisionRefusesToClickWhenThePopoverIsNotUp() {
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    // 안 떠 있으면 **아무것도 안 한다.** 여기서 눌렀다면 닫는 게 아니라 여는 것이 된다.
    #expect(
        WindowTopAnchor.dismissDecision(presented: false, hasStatusItem: true, lastDismissAt: nil, now: now)
            == .notPresented
    )
    // 상태 아이템이 없는 실행(테스트 프로세스 등)에서는 누를 대상 자체가 없다.
    #expect(
        WindowTopAnchor.dismissDecision(presented: true, hasStatusItem: false, lastDismissAt: nil, now: now)
            == .noStatusItem
    )
    // 떠 있고 누를 대상이 있으면 누른다.
    #expect(
        WindowTopAnchor.dismissDecision(presented: true, hasStatusItem: true, lastDismissAt: nil, now: now)
            == .dismissed
    )
}

@MainActor
@Test
func dismissDecisionSwallowsTheSecondClickInTheSameGesture() {
    // 한 동작에서 두 경로가 각자 닫으려 드는 조합(창을 여는 스토어 메서드 + 그 버튼의 호출부)이
    // 실제로 생길 수 있다. 두 번 누르면 **토글이라 팝오버가 도로 열린다** — 사용자가 보는 결과는
    // "안 닫힘"이다. 그래서 두 번째는 삼킨다.
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let justNow = now.addingTimeInterval(-WindowTopAnchor.dismissDebounce / 2)
    #expect(
        WindowTopAnchor.dismissDecision(presented: true, hasStatusItem: true, lastDismissAt: justNow, now: now)
            == .debounced
    )
    // 방어선을 지나면 다시 누를 수 있다 — 사람이 팝오버를 다시 열고 또 버튼을 누르는 동선이 막히면 안 된다.
    let longAgo = now.addingTimeInterval(-WindowTopAnchor.dismissDebounce - 0.1)
    #expect(
        WindowTopAnchor.dismissDecision(presented: true, hasStatusItem: true, lastDismissAt: longAgo, now: now)
            == .dismissed
    )
    // 디바운스는 '떠 있음'보다 뒤다: 안 떠 있으면 방금 눌렀든 아니든 결론은 하나(안 누른다)여야 한다.
    #expect(
        WindowTopAnchor.dismissDecision(presented: false, hasStatusItem: true, lastDismissAt: justNow, now: now)
            == .notPresented
    )
}

@MainActor
@Test
func theDoorIsClosedWhenNoPopoverWindowIsAttached() {
    // 앵커가 창을 안 쥐고 있으면 "팝오버가 떠 있다"고 볼 근거가 없다. 근거 없이 누르면 여는 쪽이므로
    // 여기서는 반드시 false 여야 한다.
    let (_, anchor) = makeAnchoredWindow(NSRect(x: 200, y: 300, width: 340, height: 200))
    #expect(WindowTopAnchor.current === anchor, "attach 가 문의 현재 앵커를 안 세웠다")
    // 화면에 올린 적 없는 헤드리스 창이다 — 창 서버에도 없고 isVisible 도 false.
    #expect(WindowTopAnchor.isMenuPopoverPresented() == false)
    WindowTopAnchor.resetDismissDebounceForTesting()
    #expect(WindowTopAnchor.dismissMenuPopover() == .notPresented)

    anchor.detach()
    #expect(WindowTopAnchor.current == nil, "detach 가 문의 현재 앵커를 안 비웠다")
    #expect(WindowTopAnchor.isMenuPopoverPresented() == false)
    #expect(WindowTopAnchor.dismissMenuPopover() == .notPresented)
}

@MainActor
@Test
func aLateDetachDoesNotStealTheDoorFromTheNewAnchor() {
    // 팝오버가 다시 열리면 SwiftUI 는 콘텐츠를 새로 만든다 — **새 코디네이터가 먼저 attach 하고**
    // 옛 코디네이터의 dismantle(detach)이 뒤늦게 오는 순서가 실제로 있다. 그때 detach 가 무조건
    // 자리를 비우면, 그 순간부터 문이 영영 "팝오버가 없다"고 답해 미니게임 버튼이 조용히 아무것도
    // 안 하게 된다(픽셀로도 테스트로도 안 보이는 종류의 죽음이다).
    let (_, old) = makeAnchoredWindow(NSRect(x: 100, y: 100, width: 340, height: 200))
    let (_, fresh) = makeAnchoredWindow(NSRect(x: 500, y: 100, width: 340, height: 200))
    #expect(WindowTopAnchor.current === fresh)

    old.detach()
    #expect(WindowTopAnchor.current === fresh, "뒤늦은 detach 가 새 앵커의 자리를 빼앗았다")

    fresh.detach()
    #expect(WindowTopAnchor.current == nil)
}

@MainActor
@Test
func reattachingTheSameWindowRetakesTheDoor() {
    // 같은 창으로 다시 attach 하는 경로(멱등 반환)에서도 문의 자리는 되찾아야 한다 —
    // 위 '뒤늦은 detach' 와 짝이다. 한쪽만 고치면 순서에 따라 문이 비는 조합이 남는다.
    let (window, anchor) = makeAnchoredWindow(NSRect(x: 200, y: 300, width: 340, height: 200))
    let (_, other) = makeAnchoredWindow(NSRect(x: 700, y: 300, width: 340, height: 200))
    #expect(WindowTopAnchor.current === other)

    anchor.attach(to: window)   // 같은 창 — 배선은 그대로, 자리만 되찾는다
    #expect(WindowTopAnchor.current === anchor)

    anchor.detach()
    other.detach()
}

// MARK: - 9) 문은 헤드리스에서 죽지 않는다 (v0.2.49 통합에서 실제로 죽었다)

@MainActor
@Test
func theDoorNeverDereferencesNSAppWithoutCheckingItFirst() throws {
    // ★ 실제 사고: `NSApp` 은 `NSApplication!`(암시적 언래핑)이고, `NSApplication.shared` 를 한 번도
    //   안 만든 프로세스에서는 **nil** 이다. 헤드리스 테스트가 딱 그런 프로세스라
    //   `openMiniGameWindow()` → `dismissMenuPopover()` → `statusItemButton()` 의 `NSApp.windows` 가
    //   프로세스를 통째로 죽였다("exited with unexpected signal code 5" — 실패가 아니라 **크래시**라
    //   그 순간 같은 프로세스의 다른 테스트 결과까지 통째로 사라진다).
    //
    // 값으로 되묻지 않고 **소스로** 못 박는 이유: NSApp 이 nil 인지는 같은 프로세스에서 앞서 어떤
    // 테스트가 돌았는가에 달려 있다(창을 만드는 테스트가 먼저 돌면 non-nil 이다). 그래서 "부르면
    // 안 죽는다"는 단언은 순서에 따라 초록이 되는 가짜 그물이다. 지켜야 할 규칙 자체가 소스에 있다.
    //
    // 주석은 걷어내고 본다 — 위 설명 문단에 `NSApp.` 이 들어 있어서, 안 걷으면 이 설명을 지워야만
    // 초록이 되는 테스트가 된다(이 저장소가 이미 한 번 배운 함정).
    let source = try String(contentsOf: windowAnchorSourceURL(), encoding: .utf8)
    let code = swiftCodeStrippingCommentsForAnchorTests(source)

    // `NSApp` 은 오직 옵셔널 바인딩으로만 받는다. 멤버로 바로 내려가는 자리가 하나라도 있으면 빨감이다.
    #expect(
        !code.contains("NSApp."),
        "NSApp 을 확인 없이 바로 파고든다 — 헤드리스 프로세스에서 그 줄이 프로세스를 죽인다"
    )
    #expect(
        code.contains("guard let app: NSApplication = NSApp"),
        "NSApp 을 nil 검사 없이 받는다"
    )
    // `NSApplication.shared` 로 우회하지도 마라 — 그 접근은 앱 객체를 **만들어** 테스트 프로세스를
    // GUI 앱으로 승격시킨다(포커스가 튀고, 상태 아이템이 없는 것과 있는 것을 가를 수 없게 된다).
    #expect(
        !code.contains("NSApplication.shared"),
        "NSApplication.shared 가 테스트 프로세스에 앱 객체를 만든다"
    )

    // 그리고 실제로 불러 본다. 이 프로세스에서 NSApp 이 어느 쪽이든 **돌아와야** 한다.
    WindowTopAnchor.resetDismissDebounceForTesting()
    let outcome = WindowTopAnchor.dismissMenuPopover()
    #expect(outcome == .notPresented || outcome == .noStatusItem)
}

/// `Sources/check/CheckWindowAnchor.swift` 경로. 테스트 파일 위치(#filePath)에서 상대로 찾는다.
private func windowAnchorSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)          // Tests/checkTests/CheckWindowAnchorTests.swift
        .deletingLastPathComponent()         // Tests/checkTests
        .deletingLastPathComponent()         // Tests
        .deletingLastPathComponent()         // <repo>
        .appendingPathComponent("Sources/check/CheckWindowAnchor.swift")
}

/// 줄 주석·블록 주석을 걷어낸 소스. 계약을 소스로 되묻는 테스트는 **설명 문단**까지 세면 안 된다 —
/// 안 그러면 "왜 이렇게 썼는가"를 적을수록 테스트가 빨개지고, 다음 사람은 설명을 지워 초록을 만든다.
/// (문자열 리터럴 속 `//` 는 이 파일에 없다.)
private func swiftCodeStrippingCommentsForAnchorTests(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]
                rest = rest[block.upperBound...]
                inBlock = true
                continue
            }
            if let comment = lineComment {
                kept += rest[..<comment.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}
