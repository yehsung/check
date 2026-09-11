import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.11 한글 조합 결함 세 가지 (2026-09-11)
//
// 증상(전부 새 입력칸 `CheckTextEditor` 도입 이후):
//   ① **자음·모음 분리**(운영자 직접): "특정 상황에서 메시지 보낼 때 한글 자음 모음이 다 분리되어서 하나씩
//      입력됨. 아예 팝오버 창을 닫았다가 다시 돌아오면 정상 동작."
//   ② **안내 문구와 글자가 겹친다**(기모찌 제보): "칸 안에 있는 '…입력하세요' 안내랑 글자랑 겹침, 초반에."
//   ③ **마지막 한 글자가 사라진다**(기모찌 제보): "자꾸 뭐 쓸 때 뒤에 한 글자가 사라져요."
//
// ★ **이 파일이 확정된 원인이 아니라 "그 원인이 만든 값"을 잰다**는 것을 먼저 읽어라.
//   증상 ①의 원인은 "팝오버가 앱 비활성·창 비-key 상태로 열려 입력 문맥(NSTextInputContext)이 안 켜진 것"이고,
//   그건 **이 프로세스로는 못 만든다**(헤드리스에는 창 서버도 활성 앱도 없다). 그래서 ①은 여기서 두 가지만
//   못 박는다: 여는 문이 활성화를 **거치는가**(소스 계약), 그리고 뷰가 그 상태를 **되살릴 자리를 갖고 있는가**.
//   실제 입력 재현은 프로브 로그에 있다(보고서의 경로).
//
// ②③ 은 반대로 **여기서 결정적으로 잴 수 있다**: 표시 글자(marked text)를 직접 심으면 실제 입력기가 부르는
// 그 경로(`setMarkedText`)를 그대로 지나기 때문이다. 2026-09-11 프로브가 잰 사실이 그대로 재현된다:
// 표시 글자 구간에는 `textDidChange` 가 오지 않아 **스토어가 한 음절 뒤처진다**(run5-markedtext.log).

// MARK: - 헬퍼 (이 파일 전용 — V0249 의 것과 이름이 겹치지 않게 kc 접두)

/// 스토어처럼 **관찰되는** 초안. 바깥에서 값을 바꾸면 SwiftUI 가 `updateNSView` 로 텍스트 뷰에 내려보낸다 —
/// 전송 성공·대화 상대 전환에서 스토어가 초안을 비우는 바로 그 경로다.
@MainActor
@Observable
private final class KCDraftModel {
    var text: String
    init(_ text: String = "") { self.text = text }
}

@MainActor
private final class KCSendLog {
    /// 전송 문이 **읽은 값**. 증상 ③의 정체가 바로 이 값이다.
    var reads: [String] = []
}

/// 제품과 같은 배선으로 올린 대화 입력칸. `onSend` 가 **제품의 전송 문과 같은 순서**를 지난다:
/// 조합을 먼저 확정하고(`commitActiveComposition`) 그다음에 초안을 읽는다.
private struct KCMountedComposer: View {
    @Bindable var model: KCDraftModel
    let canSend: Bool
    let log: KCSendLog
    var focusesWhenShown: Bool = false
    /// 확정 단계를 **일부러 빼는** 대조군. 증상 ③이 이 스위치 하나로 되살아나는 것을 보여 준다.
    var commitsBeforeSend: Bool = true

    var body: some View {
        MessageDraftEditor(
            text: $model.text,
            height: MessagePanelLayout.editorHeight,
            focusesWhenShown: focusesWhenShown,
            canSendNow: { canSend },
            onSend: {
                if commitsBeforeSend { CheckEditorTextView.commitActiveComposition() }
                log.reads.append(model.text)
                model.text = ""
            }
        )
    }
}

private struct KCMountedFeedbackEditor: View {
    @Bindable var model: KCDraftModel

    var body: some View {
        FeedbackBodyEditor(text: $model.text, height: FeedbackPanelLayout.editorHeight)
    }
}

@MainActor
private func kcFirstSubview<T: NSView>(of root: NSView, _ type: T.Type) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
        if let match = kcFirstSubview(of: child, type) { return match }
    }
    return nil
}

/// 런루프를 돌린다. SwiftUI 는 관찰 변화를 다음 바퀴에 내려보내고, 이 파일이 잰 것 중 둘(첫 빈칸 보고 ·
/// 줄바꿈 삼키기 창)은 **일부러 한 턴 뒤**에 일어난다.
@MainActor
private func kcSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func kcSpin(until condition: () -> Bool) {
    var remaining = 100
    while !condition(), remaining > 0 {
        kcSpin(0.01)
        remaining -= 1
    }
}

/// SwiftUI 에 올린 입력칸 안의 **진짜** 텍스트 뷰를 꺼낸다.
///
/// - Parameter focusesFirstResponder: 창이 이 칸을 붙들게 할 것인가. **포커스 테스트에서는 false** 로 두고
///   뷰가 스스로 가져오는지를 잰다(손으로 세워 놓고 "잡혔다"고 말하면 그 테스트는 아무것도 안 잰다).
@MainActor
private func kcMount<V: View>(
    _ view: V, width: CGFloat, height: CGFloat, focusesFirstResponder: Bool = true
) throws -> (NSWindow, NSHostingView<some View>, CheckEditorTextView) {
    let host = NSHostingView(rootView: view.frame(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    kcSpin()
    let textView = try #require(
        kcFirstSubview(of: host, CheckEditorTextView.self), "올린 입력칸 안에 진짜 텍스트 뷰가 없다"
    )
    if focusesFirstResponder { window.makeFirstResponder(textView) }
    kcSpin()
    return (window, host, textView)
}

/// 입력기가 표시 글자를 세우는 그 경로(`NSTextInputClient.setMarkedText`)를 그대로 지난다.
/// 앞에 이미 표시 글자가 있으면 그것을 갈아 끼운다(한글 입력기가 음절을 키워 갈 때 하는 일).
@MainActor
private func kcMark(_ text: String, in textView: CheckEditorTextView) {
    let replacement = textView.hasMarkedText()
        ? textView.markedRange()
        : NSRange(location: NSNotFound, length: 0)
    textView.setMarkedText(
        text,
        selectedRange: NSRange(location: text.utf16.count, length: 0),
        replacementRange: replacement
    )
    kcSpin(0.01)
}

/// 사람이 치듯 한 글자씩 확정해 넣는다(입력기가 확정할 때 부르는 것과 같은 문).
@MainActor
private func kcType(_ text: String, into textView: NSTextView) {
    for character in text {
        textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        kcSpin(0.01)
    }
    kcSpin()
}

@MainActor
private func kcReturn(_ window: NSWindow, shift: Bool = false) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
        isARepeat: false, keyCode: 36
    )!
}

/// 제품 소스를 주석 없이 읽는다. **주석을 걷어내지 않으면 설명을 지워야만 초록이 되는 테스트가 된다**
/// (이 저장소가 이미 겪은 함정).
private func kcSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)      // Tests/checkTests/V0311KoreanCompositionTests.swift
        .deletingLastPathComponent()                // Tests/checkTests
        .deletingLastPathComponent()                // Tests
        .deletingLastPathComponent()                // (repo root)
        .appendingPathComponent("Sources/check/\(name)")
    return kcStripComments(try String(contentsOf: url, encoding: .utf8))
}

private func kcStripComments(_ source: String) -> String {
    var out = ""
    var inString = false
    var index = source.startIndex
    while index < source.endIndex {
        let character = source[index]
        let next = source.index(after: index)
        if character == "\"" { inString.toggle(); out.append(character); index = next; continue }
        if !inString, character == "/", next < source.endIndex, source[next] == "/" {
            while index < source.endIndex, source[index] != "\n" { index = source.index(after: index) }
            continue
        }
        if !inString, character == "/", next < source.endIndex, source[next] == "*" {
            var cursor = source.index(after: next)
            while cursor < source.endIndex {
                if source[cursor] == "*", source.index(after: cursor) < source.endIndex,
                   source[source.index(after: cursor)] == "/" {
                    cursor = source.index(cursor, offsetBy: 2)
                    break
                }
                cursor = source.index(after: cursor)
            }
            index = cursor
            continue
        }
        out.append(character)
        index = next
    }
    return out
}

// MARK: - ① 입력 문맥이 꺼진 채로 굳지 않게 (원인 자리의 계약)

@Test
func theProgrammaticPopoverDoorActivatesTheAppBeforeItClicks() throws {
    // 증상 ① 의 원인 자리. 오버레이 말풍선 클릭 → `presentMenuPopover()` 로 팝오버가 서지만, 그 말풍선 창이
    // `nonactivatingPanel` 이라 앱이 **비활성인 채** 열린다(run9-present.log 4.15s: `appActive=false keyWin=none`).
    // 팝오버 창도 `nonactivatingPanel`(측정 styleMask 0x8080)이라 키는 받으므로 "타자는 되는데 조합만 안 되는"
    // 모양이 된다(run4.log 84.2~85.2s: "ㅇㅏㄴㄴㅕㅇㅎ", `hasMarkedText` 끝까지 false).
    //
    // 활성화는 창 서버가 있어야 실제로 일어나므로 여기서는 **그 줄이 문 안에 있는지**를 소스로 못 박는다.
    let anchor = try kcSource("CheckWindowAnchor.swift")
    let door = try #require(
        anchor.range(of: "static func presentMenuPopover"), "팝오버를 여는 문이 사라졌다"
    )
    let body = String(anchor[door.lowerBound...].prefix(600))
    #expect(body.contains("activateForKeyboardInput()"),
            "팝오버를 프로그램으로 열 때 앱을 활성화하지 않는다 — 그 팝오버에서는 한글이 자모로 쪼개진다")
    // ★ **판단보다 먼저** 불려야 한다. 판단 뒤로 가면 `.alreadyPresented`(팝오버가 이미 떠 있는데 말풍선을
    //   누른 경우)에서 활성화가 건너뛰어지고, 그 사용자는 떠 있는 팝오버에 한글을 못 치는 상태로 남는다.
    let activateAt = try #require(body.range(of: "activateForKeyboardInput()"))
    let decisionAt = try #require(body.range(of: "menuPopoverToggleDecision"))
    #expect(activateAt.lowerBound < decisionAt.lowerBound,
            "활성화가 판단 뒤에 있다 — 이미 떠 있는 팝오버에서는 영영 안 켜진다")
}

@MainActor
@Test
func theEditorCanAskForAppActivationWithoutAWindowOrAKeyWindow() {
    // 마지막 방어선의 **가드가 하나뿐**이어야 한다: "앱이 비활성인가".
    //
    // ★ 처음에는 `window.isKeyWindow` 도 요구했는데, 2026-09-11 실입력에서 그 고착 상태는
    //   **`keyWin=none` 인데도 키가 이 칸으로 들어오는** 모양이었다(live2-205256.log 12.9~14.9s:
    //   `appActive=false keyWin=none currentCtx=false` 에서 "ㅇㅏㄴㄴㅕㅇ" 이 날것으로 박혔다).
    //   그래서 방어선이 정확히 필요한 순간에 침묵했다. 창 조건을 다시 붙이지 마라.
    //
    // 헤드리스에는 활성 앱도 창 서버도 없으므로 여기서 잴 수 있는 것은 **부를 수 있는가**(크래시·정지 없이)다.
    // 실제로 문맥이 켜지는 것은 프로브가 잰다.
    let view = CheckEditorTextView(frame: NSRect(x: 0, y: 0, width: 292, height: 54))
    view.activateAppForTypedInputIfNeeded()      // 창이 없어도 조용히 지나간다
    let window = NSWindow(
        contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = view
    #expect(!window.isKeyWindow, "이 테스트의 전제(창이 key 가 아니다)가 깨졌다")
    view.activateAppForTypedInputIfNeeded()      // key 가 아니어도 부른다 — 그게 요점이다
    #expect(Bool(true))
}

@Test
func onlyTypedKeysMayActivateTheApp() throws {
    // 활성화를 부르는 자리는 **둘**이어야 한다: 팝오버를 여는 문과 **키가 실제로 들어온 자리**.
    // 포커스가 옮겨지는 자리(`becomeFirstResponder`)에서 부르면, 대화 패널에 들어가는 것만으로
    // 다른 앱의 앞자리를 빼앗는다(사용자 지시 ④-a: "포커스를 훔쳐 다른 화면을 망가뜨리면 안 된다").
    let source = try kcSource("CheckTextEditor.swift")
    #expect(source.components(separatedBy: "activateAppForTypedInputIfNeeded()").count - 1 == 2,
            "활성화를 부르는 자리 수가 바뀄다(선언 1 + keyDown 1 이어야 한다)")
    let becomeAt = try #require(source.range(of: "override func becomeFirstResponder()"))
    let block = String(source[becomeAt.lowerBound...].prefix(400))
    #expect(!block.contains("activateAppForTypedInputIfNeeded()"),
            "포커스를 잡는 자리에서 앱을 활성화한다 — 대화 패널 진입이 남의 앱 앞자리를 빼앗는다")
}

@Test
func theRewriteGuardStaysOneUnconditionalLine() throws {
    // "조합 중 되쓰기 금지"는 이 파일에서 가장 오래된 규약이고, **조건이 하나도 붙어서는 안 된다.**
    // 2026-09-11 에 "바깥이 비웠을 때만 예외"를 달아 봤다가 첫 음절이 즉시 확정되는 것을 실측하고 되돌렸다
    // (동작은 `nothingOutsideCanRewriteTheFieldWhileTheUserIsComposing` 가 잰다. 여기서는 그 예외가
    //  소스에 다시 나타나지 못하게 못 박는다 — 예외는 "고치는 것처럼 보이는" 모양이라 다음 사람이 또 넣는다).
    let source = try kcSource("CheckTextEditor.swift")
    #expect(source.contains("guard !textView.hasMarkedText(), textView.string != text else { return }"),
            "조합 중 되쓰기 가드가 사라졌거나 조건이 갈라졌다 — 조합이 끊겨 마지막 글자가 씹힌다")
    // 되쓰기의 문은 하나뿐이다(되돌리기 기록을 먼저 지우는 그 함수). 다른 자리에서 `string =` 을 쓰면
    // 그 자리의 ⌘Z 가 창째로 굳는다(`replaceTextFromOutside` 주석의 실측).
    #expect(source.components(separatedBy: "replaceTextFromOutside(text)").count - 1 == 1,
            "바깥에서 글을 되쓰는 자리가 둘 이상이다 — 한쪽이 조합 가드를 안 지난다")
}

// MARK: - ①-b 팝오버의 "지금 떠 있나"가 **실제로** 대답할 수 있어야 한다 (2026-09-11 검토 지적 ③)

@MainActor
@Test
func theAnchorHostViewReportsTheMomentItJoinsAWindow() {
    // ★ **왜 이 한 줄이 중요한가 — 관측과 추론을 갈라 읽어라.**
    //   **관측**: 앵커는 `updateNSView` 안의 `Task` 로 창을 잡고 있었는데, 한 프로브 실행에서 그 hop 이
    //   창을 못 잡았다(bubble-220030.log: `probeAnchor updateNSView window=-1` →
    //   `nextTurn window=-1 current=false presented=false`). 그 실행에서는 `WindowTopAnchor.current` 가
    //   끝까지 nil 이었다.
    //   **과장이었던 것**: 옛 코드로도 **앵커가 붙는 실행이 있다**(검토가 옛 코드를 별도 번들 프로브로
    //   재빌드해 확인했다). 그러니 "언제나 false" 가 아니라 **`Task` hop 타이밍 레이스**이고, 아래에 적는
    //   고장들은 **레이스에서 진 실행에만** 일어난다.
    //   **추론**: 진 실행에서는 `isMenuPopoverPresented()` 가 false 로 답하므로 떠 있는 팝오버에 말풍선을
    //   눌러도 버튼이 눌려 그 팝오버가 닫히고(검토가 지목한 `.alreadyPresented` 구멍), 위쪽 모서리 고정도
    //   키 획득/상실 통지도 안 돈다. 사용자에게는 "가끔 그런다"로 보인다.
    //   고친 뒤 같은 하네스에서 `popoverWin=#38148 … onScreen=true` 로 잡힌다(bubble2-221112.log 7.12s).
    //   여기서는 그 수리의 **기계**(창에 붙는 순간 알린다 = 레이스가 성립할 자리가 없다)를 결정적으로 잰다.
    let view = AnchorHostView(frame: .zero)
    var joined: [Int] = []
    view.onMoveToWindow = { joined.append($0.windowNumber) }
    #expect(joined.isEmpty, "창에 붙기도 전에 알렸다")

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    let host = NSView(frame: window.contentLayoutRect)
    window.contentView = host
    host.addSubview(view)
    #expect(joined.count == 1,
            "창에 붙는 순간을 안 알렸다 — 앵커가 SwiftUI 재평가에만 매달린다(그 재평가는 한 번만 왔다)")
    // 떼어질 때는 알리지 않는다(그 자리는 `detach` 가 맡는다). 여기서 알리면 nil 창으로 attach 를 부르게 된다.
    view.removeFromSuperview()
    #expect(joined.count == 1, "창에서 떼어질 때도 알렸다")
}

@Test
func theAnchorAccessorHangsTheAttachOnTheWindowNotOnSwiftUIReevaluation() throws {
    // 소스 계약: 되돌아가기 쉬운 수리라 못 박는다(`Task { … nsView.window … }` 한 줄로 되돌리면
    // 팝오버 판정이 다시 hop 타이밍 레이스가 되고, 진 실행의 고장은 어느 화면에도 안 보인다).
    let anchor = try kcSource("CheckWindowAnchor.swift")
    #expect(anchor.contains("AnchorHostView(frame: .zero)"),
            "접근자가 창 합류를 알리는 뷰를 안 쓴다")
    #expect(anchor.contains("onMoveToWindow"),
            "창에 붙는 순간을 받는 통로가 사라졌다")
    #expect(anchor.contains("if let window = nsView.window { coordinator.attach(to: window) }"),
            "이미 창에 붙어 있는 경우를 update 에서 안 잡는다")
}

@MainActor
@Test
func aBubbleClickOnAnAlreadyOpenPopoverMustNotPressTheButton() {
    // `.alreadyPresented` 갈래의 뜻: 누르면 **닫힌다.** 그래서 이 판정이 틀리면 사용자는 말풍선을 눌러
    // 대화를 열려다 그 대화를 닫는다. 활성화는 판정 **앞**에 있으므로 이 갈래에서도 일한다
    // (그 순서를 `theProgrammaticPopoverDoorActivatesTheAppBeforeItClicks` 가 지킨다).
    let now = Date()
    #expect(WindowTopAnchor.menuPopoverToggleDecision(
        intent: .present, presented: true, hasStatusItem: true, lastClickAt: nil, now: now
    ) == .alreadySettled, "떠 있는 팝오버에 여는 클릭을 보냈다 — 그 클릭은 닫는 클릭이다")
    #expect(WindowTopAnchor.menuPopoverToggleDecision(
        intent: .present, presented: false, hasStatusItem: true, lastClickAt: nil, now: now
    ) == .click, "닫혀 있는데 안 누른다 — 말풍선을 눌러도 대화가 안 열린다")
}

// MARK: - ② 안내 문구는 **그려진 것**을 보고 숨는다 (순수 판정)

@Test
func thePlaceholderFollowsWhatIsDrawnNotWhatIsStored() {
    // 규칙은 하나다: **텍스트 뷰가 말해 준 것이 있으면 그 말만 믿는다.**
    //
    // ① 아직 못 들었다(첫 그림 · 스냅샷 대체 경로) — 스토어 값으로 판단한다. 그 경로에 그려지는 것이
    //    `Text(스토어 값)` 이라 스토어 값이 곧 "그려진 것"이다(규칙이 갈리지 않는다).
    #expect(CheckEditorPlaceholder.isVisible(storeText: "", editorRenderedEmpty: nil))
    #expect(!CheckEditorPlaceholder.isVisible(storeText: "안녕", editorRenderedEmpty: nil))
    // ② **조합 중** — 뷰에는 "안"이 떠 있는데 스토어는 비었다(표시 글자 구간에 textDidChange 가 안 온다).
    //    스토어로 판정하면 안내 문구가 그 "안" 위에 겹친다 = 기모찌 제보 그 화면이다.
    #expect(!CheckEditorPlaceholder.isVisible(storeText: "", editorRenderedEmpty: false),
            "조합 중인 글자 위에 안내 문구가 겹친다")
    #expect(!CheckEditorPlaceholder.isVisible(storeText: "안녕하세", editorRenderedEmpty: false))
    // ③ **전송 직후** — 스토어에 아직 값이 남아 있어도 뷰가 비었으면 안내 문구가 돌아와야 한다
    //    (그 반대가 "빈 칸인데 안내가 없는" 화면이고, 사용자는 칸이 죽은 줄로 읽는다).
    #expect(CheckEditorPlaceholder.isVisible(storeText: "옛 문장", editorRenderedEmpty: true))
    #expect(CheckEditorPlaceholder.isVisible(storeText: "", editorRenderedEmpty: true))
}

@Test
func bothEditorsAskTheSameRuleAndNeitherAsksTheStoreDirectly() throws {
    // 규칙이 한 곳에서만 오는지 본다. 한 칸이 `text.isEmpty` 로 되돌아가면 그 칸에서만 겹침이 되살아나고,
    // 그 차이는 아무 스냅샷에도 안 보인다(스냅샷은 조합 상태를 만들 수 없다).
    for name in ["CheckMessageView.swift", "CheckFeedbackView.swift"] {
        let source = try kcSource(name)
        #expect(source.contains("CheckEditorPlaceholder.isVisible(storeText:"),
                "\(name) 의 안내 문구가 공용 규칙을 안 쓴다")
        #expect(source.contains("onRenderedEmptyChange: { editorRenderedEmpty = $0 }"),
                "\(name) 이 '그려진 것'을 받아 오지 않는다 — 규칙에 넣을 재료가 없다")
        #expect(!source.contains("if text.isEmpty {\n                Text("),
                "\(name) 이 아직 스토어 값으로 안내 문구를 숨긴다")
    }
}

@MainActor
@Test
func markedTextHidesThePlaceholderEvenThoughTheStoreIsStillEmpty() throws {
    let model = KCDraftModel("")
    let (_, _, textView) = try kcMount(
        KCMountedComposer(model: model, canSend: true, log: KCSendLog()),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    // 전제: 빈 칸에서는 안내 문구가 보인다(뷰가 "비었다"고 알렸다).
    kcSpin()
    #expect(textView.renderedTextIsEmpty, "빈 칸이 '비었다'고 말하지 않는다 — 이 테스트가 재는 것이 없다")

    kcMark("안", in: textView)
    // ★ 2026-09-11 프로브가 잰 사실이 그대로 재현된다: 표시 글자 구간에는 알림이 안 와서 **스토어가 비어 있다.**
    #expect(model.text.isEmpty,
            "표시 글자가 스토어까지 흘렀다 — 이 테스트의 전제(스토어가 뒤처진다)가 깨졌다: \(model.text.debugDescription)")
    // 그런데 뷰에는 글자가 있다. 그래서 안내 문구는 숨어야 한다.
    #expect(!textView.renderedTextIsEmpty, "조합 중인 글자를 '그려진 것'으로 안 센다")
    #expect(!CheckEditorPlaceholder.isVisible(storeText: model.text, editorRenderedEmpty: textView.renderedTextIsEmpty),
            "조합 중인데 안내 문구가 보인다 — 글자와 겹친 그 화면이다")
}

/// 실제로 그려진 픽셀에서 두 화면의 **다른 픽셀 수**를 센다.
///
/// **왜 `ImageRenderer` 가 아닌가**: 그것은 AppKit 을 감싼 뷰를 못 그린다(이 저장소에서 `Menu` 는 노란 상자로
/// 나왔고 그 자리의 픽셀 커버리지는 0이었다). 여기서 봐야 하는 것이 바로 그 AppKit 텍스트 뷰의 글자다.
/// `cacheDisplay(in:to:)` 는 뷰 계층을 실제로 그리므로 표시 글자까지 함께 나온다.
@MainActor
private func kcPixels(_ host: NSView) throws -> NSBitmapImageRep {
    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds), "비트맵을 못 만들었다")
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

@MainActor
private func kcDiffCount(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
          let pa = a.bitmapData, let pb = b.bitmapData else { return -1 }
    let bytes = a.bytesPerRow * a.pixelsHigh
    var differing = 0
    var index = 0
    while index < bytes {
        if pa[index] != pb[index] { differing += 1 }
        index += 1
    }
    return differing
}

@MainActor
@Test
func thePlaceholderIsNotDrawnOnTopOfTheComposingSyllable() throws {
    // ★ **픽셀로 본다.** 위 테스트는 판정의 재료를 재고, 이것은 사용자가 실제로 보는 화면을 잰다.
    //   기준선이 셋이라 자기 자신으로 눈금을 만든다(고정 숫자를 적으면 폰트가 바뀌는 날 거짓으로 초록이 된다):
    //     E = 빈 칸(안내 문구가 보인다)   M = 조합 중 "안"(스토어는 "")   C = 확정된 "안"(스토어도 "안")
    //   겹치지 않으면 M 은 C 와 거의 같아야 한다. 겹치면 M = C + 안내 문구가 되어 E−C 만큼 벌어진다.
    let width = MessagePanelLayout.contentWidth, height = MessagePanelLayout.editorHeight

    let emptyModel = KCDraftModel("")
    let (_, emptyHost, _) = try kcMount(
        KCMountedComposer(model: emptyModel, canSend: true, log: KCSendLog()),
        width: width, height: height, focusesFirstResponder: false
    )
    kcSpin()
    let emptyShot = try kcPixels(emptyHost)

    let committedModel = KCDraftModel("안")
    let (_, committedHost, committedView) = try kcMount(
        KCMountedComposer(model: committedModel, canSend: true, log: KCSendLog()),
        width: width, height: height, focusesFirstResponder: false
    )
    kcSpin(until: { committedView.string == "안" })
    kcSpin()
    let committedShot = try kcPixels(committedHost)

    let markedModel = KCDraftModel("")
    let (_, markedHost, markedView) = try kcMount(
        KCMountedComposer(model: markedModel, canSend: true, log: KCSendLog()),
        width: width, height: height, focusesFirstResponder: false
    )
    kcMark("안", in: markedView)
    kcSpin()
    let markedShot = try kcPixels(markedHost)

    let placeholderInk = kcDiffCount(emptyShot, committedShot)
    let overlapInk = kcDiffCount(markedShot, committedShot)
    // 전제: 두 기준선이 실제로 다르다. 같으면(둘 다 빈 그림이면) 아래 비교는 영원히 초록이다.
    try #require(placeholderInk > 200,
                 "안내 문구와 글자 하나의 차이가 \(placeholderInk) 바이트뿐이다 — 아무것도 안 그려졌다")
    // 표시 글자에는 밑줄이 붙으므로 M 과 C 가 딱 같지는 않다. 안내 문구 한 줄(≈ placeholderInk)의 4분의 1
    // 안쪽이면 "안내 문구가 그려지지 않았다"로 읽어도 된다.
    #expect(overlapInk < placeholderInk / 4,
            "조합 중 화면이 확정된 화면보다 \(overlapInk) 바이트 다르다(안내 문구 한 줄 = \(placeholderInk)) — 안내 문구가 글자 위에 그려졌다")
}

@MainActor
@Test
func theFeedbackEditorHidesItsPlaceholderWhileComposingToo() throws {
    // 운영자가 겪은 자리는 **제보 답변 칸**이었다(순정 TextField). 그 위젯은 자기 안내 문구를 스스로 그리지만,
    // 제보 **본문** 칸은 우리 래퍼라 같은 결함이 있었다. 같은 규칙을 쓰는지 올린 그대로 확인한다.
    let model = KCDraftModel("")
    let (_, _, textView) = try kcMount(
        KCMountedFeedbackEditor(model: model),
        width: FeedbackPanelLayout.contentWidth, height: FeedbackPanelLayout.editorHeight
    )
    kcSpin()
    try #require(textView.renderedTextIsEmpty, "빈 제보 칸이 '비었다'고 말하지 않는다")
    kcMark("재", in: textView)
    #expect(model.text.isEmpty, "제보 칸의 표시 글자가 스토어까지 흘렀다 — 전제가 깨졌다")
    #expect(!textView.renderedTextIsEmpty, "제보 칸이 조합 중인 글자를 '그려진 것'으로 안 센다")
    #expect(!CheckEditorPlaceholder.isVisible(storeText: model.text, editorRenderedEmpty: textView.renderedTextIsEmpty),
            "제보 칸에서 안내 문구가 조합 중인 글자와 겹친다")
}

// MARK: - ③ 전송은 **확정된 문자열**을 보낸다

@MainActor
@Test
func theSendDoorCommitsTheCompositionBeforeItReadsTheDraft() throws {
    let log = KCSendLog()
    let model = KCDraftModel("")
    let (_, _, textView) = try kcMount(
        KCMountedComposer(model: model, canSend: true, log: log),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    kcType("안녕하세", into: textView)
    kcMark("요", in: textView)
    // 프로브가 잰 그 상태를 그대로 만들었다(run8-note.log 23.94s): 뷰 "안녕하세요" / 스토어 "안녕하세".
    try #require(textView.string == "안녕하세요", "전제가 안 만들어졌다: \(textView.string.debugDescription)")
    try #require(model.text == "안녕하세", "전제가 안 만들어졌다: \(model.text.debugDescription)")
    try #require(CheckEditorTextView.focusedEditor === textView,
                 "포커스를 쥔 칸을 전송 문이 못 찾는다 — 버튼·⌘↩ 갈래가 확정을 건너뛴다")

    // 버튼·⌘↩ 이 지나는 문 그대로.
    #expect(CheckEditorTextView.commitActiveComposition(), "확정할 조합이 있는데 문이 아무 일도 안 했다")
    #expect(!textView.hasMarkedText(), "확정 뒤에도 표시 글자가 남았다 — 다음 글자가 그 음절에 다시 붙는다")
    #expect(model.text == "안녕하세요",
            "확정이 스토어까지 안 올라왔다 — 전송이 마지막 글자를 잃는다: \(model.text.debugDescription)")
    #expect(textView.string == "안녕하세요", "확정이 화면의 글자를 바꿨다: \(textView.string.debugDescription)")
}

@MainActor
@Test
func theFirstEnterSendsTheWholeSentenceIncludingTheComposingSyllable() throws {
    // 규약(사용자 결정 2026-09-11 — 카톡과 같은 동작): **첫 Enter 가 조합 중 마지막 글자까지 보낸다.**
    let log = KCSendLog()
    let model = KCDraftModel("")
    let (window, _, textView) = try kcMount(
        KCMountedComposer(model: model, canSend: true, log: log),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    kcType("안녕하세", into: textView)
    kcMark("요", in: textView)
    textView.keyDown(with: kcReturn(window))

    #expect(log.reads == ["안녕하세요"],
            "첫 Enter 가 보낸 값이 화면의 문장과 다르다(= 마지막 한 글자가 사라진다): \(log.reads)")
    // 확정 뒤 따라오는 줄바꿈은 삼킨다 — 보낸 칸에 빈 줄이 남으면 다음 글자가 두 번째 줄에서 시작한다.
    kcSpin(until: { textView.string.isEmpty })
    #expect(!textView.string.contains("\n"), "보내는 Enter 가 줄을 넣었다: \(textView.string.debugDescription)")
    #expect(textView.string.isEmpty,
            "전송 뒤 비운 칸에 옛 문장이 남았다: \(textView.string.debugDescription)")
    // ★ 조합이 확정된 뒤였으므로 **되돌아올 글자가 없다**(run8 24.54s 의 사고가 닫혔는지 본다).
    kcSpin()
    #expect(model.text.isEmpty, "비운 칸에 옛 문장이 되돌아왔다: \(model.text.debugDescription)")
}

@MainActor
@Test
func skippingTheCommitIsExactlyHowTheLastSyllableDisappears() throws {
    // ★ **대조군(이 스위트가 뭔가를 잰다는 증거).** 확정 단계만 빼면 증상 ③이 그 자리에서 되살아난다.
    //   이 테스트가 초록인 것은 "고쳐졌다"가 아니라 "재는 눈금이 맞다"는 뜻이다.
    let log = KCSendLog()
    let model = KCDraftModel("")
    let (_, _, textView) = try kcMount(
        KCMountedComposer(model: model, canSend: true, log: log, commitsBeforeSend: false),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    kcType("안녕하세", into: textView)
    kcMark("요", in: textView)
    CheckEditorTextView.focusedEditor?.onSend()
    #expect(log.reads == ["안녕하세"],
            "확정을 빼도 전량이 나갔다 — 이 스위트의 눈금이 증상 ③을 못 잡는다: \(log.reads)")
}

@MainActor
@Test
func theLateNewlineFromTheInputMethodDoesNotLeakIntoTheField() throws {
    // 2026-09-11 실측(run10-enter.log 7.29s): 옛 구현은 `super.keyDown` **동기 구간만** 삼킴 창을 열어 놓아,
    // 입력기가 확정을 비동기로 끝낸 뒤 부르는 `insertNewline` 이 그대로 줄바꿈이 됐다("하이요\n").
    let log = KCSendLog()
    let model = KCDraftModel("")
    let (window, _, textView) = try kcMount(
        KCMountedComposer(model: model, canSend: false, log: log),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    kcType("하이", into: textView)
    kcMark("요", in: textView)
    // 못 보내는 상태(canSend=false)로 두었다 — 여기서 재는 것은 전송이 아니라 **줄바꿈이 새는가**다.
    textView.keyDown(with: kcReturn(window))
    #expect(log.reads.isEmpty, "못 보내는 상태에서 전송이 나갔다: \(log.reads)")
    // 같은 턴에 입력기가 뒤늦게 부르는 줄바꿈 — 삼켜야 한다.
    textView.insertNewline(nil)
    #expect(textView.string == "하이요",
            "확정 뒤 늦게 온 줄바꿈이 칸에 들어갔다: \(textView.string.debugDescription)")

    // 대조군: 창은 **한 턴만** 열린다. 한 바퀴 돈 뒤의 ⇧Enter 는 여전히 줄을 바꿔야 한다
    // (영구히 삼키면 사용자가 일부러 누른 줄바꿈이 사라진다).
    kcSpin()
    textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    textView.keyDown(with: kcReturn(window, shift: true))
    #expect(textView.string == "하이요\n",
            "⇧Enter 의 줄바꿈까지 삼켰다: \(textView.string.debugDescription)")
}

@MainActor
@Test
func nothingOutsideCanRewriteTheFieldWhileTheUserIsComposing() throws {
    // ★ **이 규약이 이 파일에서 가장 오래된 것이고, 2026-09-11 에 한 번 깨 봤다가 되돌렸다.**
    //
    //   깨 본 내용: "바깥이 칸을 **비웠을 때만** 예외로 되쓴다"(run8-note.log 24.54s 의 '비운 칸에 옛 문장이
    //   되돌아온다'를 막으려고). 실측 결과 그 예외는 **첫 음절을 치는 순간 발화했다** — 조합 중에는 스토어가
    //   한 음절 뒤처지므로 `text.isEmpty` 가 "바깥이 비웠다"와 "아직 안 올라왔다"를 구별하지 못한다.
    //   그래서 조합이 즉시 확정되고, 사용자에게는 증상 ①(자모가 하나씩 들어감)과 같은 화면이 됐다.
    //
    //   이 테스트는 그 예외가 **다시 들어오지 못하게** 한다: 조합 중이면 바깥이 무엇을 써도 뷰는 안 바뀐다.
    //   run8 의 사고는 **전송이 조합을 먼저 확정하는 것**으로 막는다(위 전송 테스트들).
    let model = KCDraftModel("")
    let (_, _, textView) = try kcMount(
        KCMountedComposer(model: model, canSend: true, log: KCSendLog()),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    kcType("안녕하세", into: textView)
    kcMark("요", in: textView)
    try #require(textView.hasMarkedText(), "전제(조합 중)가 안 만들어졌다")

    // ① 바깥이 비운다(전송 성공 · 대화 상대 전환이 하는 일).
    model.text = ""
    kcSpin(); kcSpin()
    #expect(textView.string == "안녕하세요",
            "조합 중인 칸을 바깥이 비웠다 — 마지막 글자가 씹힌다: \(textView.string.debugDescription)")
    #expect(textView.hasMarkedText(), "조합이 끊겼다 — 되쓰기 가드가 뚫렸다")

    // ② 바깥이 **다른 글**을 넣는 경로도 같다(초안 복원 등).
    model.text = "엉뚱한 초안"
    kcSpin(); kcSpin()
    #expect(textView.string == "안녕하세요",
            "조합 중인 칸을 바깥이 갈아 썼다: \(textView.string.debugDescription)")
    #expect(textView.hasMarkedText(), "조합이 끊겼다 — 되쓰기 가드가 뚫렸다")

    // ③ 조합이 끝나면 바깥의 값이 다시 흐른다(가드가 "영영 안 받는다"로 굳은 게 아니다).
    #expect(textView.commitComposition(), "확정할 조합이 있는데 문이 아무 일도 안 했다")
    model.text = ""
    kcSpin(until: { textView.string.isEmpty })
    #expect(textView.string.isEmpty, "조합이 끝난 뒤에도 바깥이 칸을 못 비운다: \(textView.string.debugDescription)")
}

// MARK: - ③-b 제보 칸도 **같은 문**을 지난다 (2026-09-11 검토 지적 ②)

@MainActor
@Test
func theFeedbackSendGoesThroughTheSameCommitDoorAsTheMessageSend() throws {
    // ★ 검토가 잡은 구멍: 메시지 세 갈래는 확정을 지났는데 **제보 [보내기]는 확정 없이 스토어를 읽었다.**
    //   같은 결함이 두 화면에 있었고 한쪽만 고쳐져 있었다. 이제 확정은 문 하나(`CheckEditorSend`)에만 있다.
    //   여기서는 그 문을 **제보 본문 칸에 올린 그대로** 통과시켜 값으로 잰다.
    let model = KCDraftModel("")
    let (_, _, textView) = try kcMount(
        KCMountedFeedbackEditor(model: model),
        width: FeedbackPanelLayout.contentWidth, height: FeedbackPanelLayout.editorHeight
    )
    kcType("재현 순서", into: textView)
    kcMark("요", in: textView)
    // 프로브가 잰 그 상태(뷰가 한 음절 앞선다)를 제보 칸에서 그대로 만들었다.
    try #require(textView.string == "재현 순서요", "전제가 안 만들어졌다: \(textView.string.debugDescription)")
    try #require(model.text == "재현 순서", "전제가 안 만들어졌다: \(model.text.debugDescription)")
    try #require(CheckEditorTextView.focusedEditor === textView, "제보 칸을 전송 문이 못 찾는다")

    var read: String?
    let committed = CheckEditorSend.commitThenSend { read = model.text }
    #expect(committed, "확정할 조합이 있는데 문이 아무 일도 안 했다")
    #expect(read == "재현 순서요",
            "제보 [보내기]가 마지막 글자를 잃었다(= 검토 지적 ② 그대로다): \(read.debugDescription)")
    #expect(!textView.hasMarkedText(), "확정 뒤에도 표시 글자가 남았다")
    // ⚠︎ **이 테스트의 한계**(2026-09-11 검토 지적 ④-b): 여기서는 문(`CheckEditorSend.commitThenSend`)을
    //   테스트가 직접 부른다. 그러니 이것이 재는 것은 **문이 제 일을 하는가**이지 **화면의 [보내기] 버튼이
    //   그 문을 지나는가**가 아니다 — 버튼이 문을 안 지나도 이 테스트는 초록이다. 그 갈림은 아래
    //   `theFeedbackSendButtonActionShipsTheComposingSyllable` 이 버튼의 동작을 태워 값으로 잡는다.
}

// MARK: - ③-c 화면의 [보내기]가 **실제로** 그 문을 지나는가 — 나가는 본문으로 잰다 (검토 지적 ④-b)

/// 스텁 네트워크에 물린 제보 스토어. `FeedbackURLProtocol`(V0248 의 것, 파일 밖에서도 쓸 수 있다)에
/// 호스트별로 응답을 심고 **나간 본문**을 되받는다.
@MainActor
private func kcFeedbackStore(host: String) -> WorkTimerStore {
    FeedbackURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackURLProtocol.session()
    )
    let suite = "v0311-feedback-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.session = SupabaseSession(
        accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002"
    )
    store.appVersionProvider = { AppVersionReport(build: 58, version: "0.3.11") }
    store.osVersionProvider = { "15.6" }
    return store
}

@MainActor
@Test
func theFeedbackSendButtonActionShipsTheComposingSyllable() async throws {
    // ★ **소스 문자열 계약이 못 재는 것을 여기서 잰다.** 계약은 문이 파일에 **있는지**만 알고,
    //   버튼이 그 문을 **부르는지**는 모른다. 그래서 이 테스트는 두 가지를 이어 붙인다:
    //     ① 버튼의 동작이 `sendTapped` 라는 것(아래 한 줄 — SwiftUI Button 은 헤드리스에서 못 누른다.
    //        합성 NSEvent·accessibilityPerformPress 둘 다 안 먹는 것이 이 저장소에서 실측됐다),
    //     ② 올린 화면 그대로 그 동작을 태웠을 때 **서버로 나가는 본문**에 조합 중이던 마지막 음절이 실린다는 것.
    let source = try kcSource("CheckFeedbackView.swift")
    try #require(source.contains("action: sendTapped"),
                 "[보내기] 버튼이 sendTapped 를 안 쓴다 — 아래 값 측정이 화면이 안 지나는 길을 재게 된다")

    let host = "v0311-feedback-button"
    let path = "/rest/v1/rpc/submit_feedback"
    let store = kcFeedbackStore(host: host)
    FeedbackURLProtocol.set(
        .init(status: 200, body: #""11111111-1111-1111-1111-111111111111""#), host: host, path: path
    )

    // 제품 화면 그대로 올린다(제보 [보내기] 탭 전체).
    let screen = FeedbackSendView(store: store)
    let (_, _, textView) = try kcMount(
        screen, width: FeedbackPanelLayout.contentWidth, height: FeedbackPanelLayout.sendBodyHeight
    )
    kcType("재현 순서", into: textView)
    kcMark("요", in: textView)
    // 프로브가 잰 그 상태(뷰가 한 음절 앞선다)를 화면 위에서 그대로 만들었다.
    try #require(textView.string == "재현 순서요", "전제가 안 만들어졌다: \(textView.string.debugDescription)")
    try #require(store.feedbackDraft == "재현 순서", "전제가 안 만들어졌다: \(store.feedbackDraft.debugDescription)")
    try #require(CheckEditorTextView.focusedEditor === textView, "화면의 제보 칸을 전송 문이 못 찾는다")

    // 버튼이 하는 일 그대로.
    screen.sendTapped()
    for _ in 0..<200 {
        if FeedbackURLProtocol.count(host: host, path: path) > 0 { break }
        try? await Task.sleep(for: .milliseconds(5))
    }

    let sent = FeedbackURLProtocol.sentBodies(host: host, path: path)
    #expect(sent.count == 1, "[보내기] 가 제보를 안 보냈다(나간 요청 \(sent.count)건)")
    let raw = try #require(sent.first, "나간 본문이 없다 — 버튼의 동작이 전송 문에 닿지 않았다")
    let payload = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] ?? [:]
    let body = try #require(payload["p_body"] as? String, "본문 키가 없다: \(raw)")
    // 사용자 글은 진단 아래에 붙으므로 화면이 쓰는 **같은 함수**로 되돌려 가른다.
    let parts = FeedbackDiagnostics.split(body)
    #expect(parts.body == "재현 순서요",
            "제보 [보내기] 가 마지막 글자를 잃은 채 보냈다(= 기모찌 제보 v0.3.11): \(parts.body.debugDescription)")
}

@Test
func bothScreensSendThroughTheOneDoorAndNeitherCallsTheStoreDirectly() throws {
    // 소스 계약: 확정이 **문 안에 한 번만** 적혀 있어야 한다. 갈래마다 `store.send…()` 를 직접 부르면
    // 그 갈래에서 확정이 빠지고, 빠진 쪽은 마지막 한 글자를 잃는다(같은 결함이 다시 갈리는 모양).
    let editor = try kcSource("CheckTextEditor.swift")
    #expect(editor.components(separatedBy: "CheckEditorTextView.commitActiveComposition()").count - 1 == 1,
            "확정을 부르는 자리가 문(CheckEditorSend) 밖에도 있다")

    let message = try kcSource("CheckMessageView.swift")
    #expect(message.contains("CheckEditorSend.commitThenSend { store.sendDraftMessage() }"),
            "메시지 전송이 공용 문을 안 지난다")
    #expect(message.components(separatedBy: "store.sendDraftMessage()").count - 1 == 1,
            "메시지 전송 호출이 둘 이상이다 — 확정을 건너뛰는 갈래가 생겼다")

    let feedback = try kcSource("CheckFeedbackView.swift")
    #expect(feedback.contains("CheckEditorSend.commitThenSend { store.sendFeedback() }"),
            "제보 전송이 공용 문을 안 지난다 — 제보 칸에서 마지막 글자가 사라진다")
    #expect(feedback.components(separatedBy: "store.sendFeedback()").count - 1 == 1,
            "제보 전송 호출이 둘 이상이다 — 확정을 건너뛰는 갈래가 생겼다")
    // 제보 칸의 Enter 는 **여전히 줄바꿈**이다(전송 아님). 그 규약은 유지한다 — 버그 설명이 반토막 난다.
    #expect(!feedback.contains("sendsOnReturn: true"),
            "제보 칸이 Enter 로 전송한다 — 버그 설명이 반토막 난 채 나간다")
}

// MARK: - ④ 확정이 **알림 없이** 끝나는 경로 (2026-09-11 검토 지적 ④ — 생존 뮤테이션)

/// 입력기가 표시 글자를 **알림 없이** 거두는 경로를 흉내 내는 칸.
///
/// **왜 이런 칸이 필요한가**: `commitComposition()` 은 ① `discardMarkedText()` ② 남았으면 `unmarkText()`
/// ③ `didChangeText()` 의 순서로 확정한다. 헤드리스에서는 ②의 `super.unmarkText()` 가 이미 알림을 내므로
/// ③을 지워도 **전부 초록이었다**(검토 지적 ④). 하지만 실제 입력기 경로에서는 ①이 표시 글자를 스스로 거두어
/// ②가 아예 안 불릴 수 있고, 그러면 알림을 낼 사람이 ③뿐이다 — 알림이 없으면 확정된 음절이 스토어에 영영
/// 안 올라가 **전송이 마지막 글자를 잃는다**(증상 ③이 그대로 돌아온다).
/// 그 경로를 이 프로세스에서 만들 수 있는 유일한 방법이 "알림을 내지 않는 unmark" 한 줄을 갈아 끼우는 것이다.
@MainActor
private final class KCSilentUnmarkEditor: CheckEditorTextView {
    override func unmarkText() {
        // super 를 부르지 않는다 = **알림이 없다**(실제 입력기가 ①에서 표시를 거둬 간 경우와 같은 상태).
    }
}

@MainActor
private final class KCTextChangeSpy: NSObject, NSTextViewDelegate {
    var changes: [String] = []

    func textDidChange(_ notification: Notification) {
        changes.append((notification.object as? NSTextView)?.string ?? "")
    }
}

@MainActor
@Test
func theCommitAnnouncesTheTextEvenWhenUnmarkingIsSilent() throws {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 292, height: 54),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    let view = KCSilentUnmarkEditor(frame: NSRect(x: 0, y: 0, width: 292, height: 54))
    window.contentView = view
    window.makeFirstResponder(view)
    let spy = KCTextChangeSpy()
    view.delegate = spy
    view.string = "안녕하세"
    view.setSelectedRange(NSRange(location: ("안녕하세" as NSString).length, length: 0))
    view.setMarkedText(
        "요",
        selectedRange: NSRange(location: 1, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    try #require(view.hasMarkedText(), "표시 글자를 못 심었다 — 이 테스트가 재는 것이 없다")
    // 조합을 세우는 동안의 알림은 센 것에서 뺀다. 여기서 재는 것은 **확정이 내는 알림** 하나다.
    spy.changes.removeAll()

    #expect(view.commitComposition(), "확정할 조합이 있는데 문이 아무 일도 안 했다")
    // ★ 이 단언이 `commitComposition()` 의 `didChangeText()` 한 줄을 잰다. 그 줄을 지우면
    //   (알림을 낼 사람이 아무도 없으므로) 여기가 빈 배열이 되어 빨강이 된다.
    #expect(spy.changes.last == "안녕하세요",
            "확정이 알림을 안 냈다 — 확정된 음절이 스토어로 안 올라가 전송이 마지막 글자를 잃는다: \(spy.changes)")
}

// MARK: - ④ 대화창에 들어오면 커서가 입력칸에 있다 (사용자 지시 2026-09-11)

@Test
func theFocusRuleTakesTheCursorOnlyWhenItShouldAndOnlyOnce() {
    // 셋이 모두 참일 때만 잡는다. ③(이미 내가 쥐었다)이 빠지면 SwiftUI 재평가마다 첫 응답자를 다시 세워
    // **조합이 매 타자마다 끊긴다** — 증상 ①을 우리 손으로 새로 만드는 길이다(초당 시계·15초 폴링이 이 트리를 지난다).
    #expect(CheckEditorTextView.claimsFocus(focusesWhenShown: true, hasWindow: true, alreadyFirstResponder: false))
    #expect(!CheckEditorTextView.claimsFocus(focusesWhenShown: true, hasWindow: true, alreadyFirstResponder: true),
            "이미 포커스를 쥔 칸을 다시 잡는다 — 재평가마다 조합이 끊긴다")
    #expect(!CheckEditorTextView.claimsFocus(focusesWhenShown: true, hasWindow: false, alreadyFirstResponder: false),
            "창에 올라오지도 않은 칸이 포커스를 잡는다")
    // 지정되지 않은 칸(제보 본문 등)은 어떤 조합에서도 잡지 않는다 — 요청 밖이고, 말없이 훔치면 사고다.
    for hasWindow in [false, true] {
        for holding in [false, true] {
            #expect(!CheckEditorTextView.claimsFocus(
                focusesWhenShown: false, hasWindow: hasWindow, alreadyFirstResponder: holding
            ), "포커스를 잡으라고 하지 않은 칸이 잡았다")
        }
    }
}

@Test
func onlyTheConversationComposerAsksForTheCursor() throws {
    // 켜는 자리가 **대화 패널의 입력칸 하나**뿐인지 소스로 못 박는다. 제보 칸에 생기면 그건 사고다
    // (제보 화면은 목록을 먼저 읽는 화면이고, 사용자가 요청한 것도 대화창이다).
    #expect(try kcSource("CheckMessageView.swift").contains("focusesWhenShown: true"),
            "대화 입력칸이 커서를 안 가져온다 — 들어가서 마우스로 한 번 눌러야 타자가 된다")
    #expect(!(try kcSource("CheckFeedbackView.swift").contains("focusesWhenShown")),
            "제보 칸이 커서를 훔친다 — 요청 밖이다")
}

@MainActor
@Test
func theConversationComposerTakesTheCursorByItselfWhenItAppears() throws {
    // **손으로 세워 주지 않는다**(`focusesFirstResponder: false`) — 뷰가 스스로 가져오는지를 잰다.
    let model = KCDraftModel("")
    let (window, _, textView) = try kcMount(
        KCMountedComposer(model: model, canSend: true, log: KCSendLog(), focusesWhenShown: true),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight,
        focusesFirstResponder: false
    )
    kcSpin(until: { window.firstResponder === textView })
    #expect(window.firstResponder === textView,
            "대화 입력칸이 화면에 서면서 커서를 안 가져왔다 — 마우스로 눌러야 타자가 된다")

    // ★ 포커스를 잡은 것이 조합을 깨지 않는다(사용자 지시 ④-d). 잡힌 상태에서 조합을 세우고,
    //   한 바퀴 더 돌려도(재평가 · 다음 턴의 포커스 주장) 표시 글자가 살아 있어야 한다.
    kcMark("안", in: textView)
    kcSpin()
    kcSpin()
    #expect(textView.hasMarkedText(), "포커스 주장이 조합을 끊었다 — 증상 ①을 새로 만들었다")
    #expect(textView.string == "안", "조합 중 글자가 바뀌었다: \(textView.string.debugDescription)")
}

@MainActor
@Test
func theComposerThatWasNotAskedToFocusStaysWhereItIs() throws {
    // 대조군: 기본값(false)인 칸은 커서를 안 가져간다. 이 갈래가 깨지면 "팝오버가 열리는 순간 다른 화면의
    // 포커스를 훔친다"는 사고가 된다(사용자 지시 ④-a).
    let model = KCDraftModel("")
    let (window, _, textView) = try kcMount(
        KCMountedComposer(model: model, canSend: true, log: KCSendLog(), focusesWhenShown: false),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight,
        focusesFirstResponder: false
    )
    kcSpin()
    kcSpin()
    #expect(window.firstResponder !== textView, "포커스를 잡으라고 하지 않은 칸이 커서를 가져갔다")
}
