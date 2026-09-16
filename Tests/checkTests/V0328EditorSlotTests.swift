import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.28 입력칸 재사용 자리 — 세 번째 사용처가 생겨도 한글 조합이 안 죽는다
//
// 결함(적대적 검토 2026-09-16, 반증 실패): 입력칸 재사용 풀이 **한 칸짜리 정적 슬롯**이었다. 그 전제는
// "이 칸을 쓰는 두 패널(대화·제보)은 `CheckMenuView` 의 `if / else if` 로 서로 배타"라는 것이었는데,
// v0.3.27 의 오목 채팅칸이 그 전제를 깼다 — 그 칸은 팝오버가 아니라 **별도 창**에 살고, 창의 `close()` 는
// `orderOut` 뿐이라(`CheckGomokuWindow.close`) 창을 내려도 호스팅 뷰가 살아 있다. 즉 대국 화면이 서 있는
// 동안 오목 칸이 유일한 대기 칸을 `superview != nil` 로 쥐고, 그때 선 대화 칸은 **새로 만들어진다.**
// 새 NSTextView 는 한글 입력기 세션을 못 받아 자모가 하나씩 박힌다(`CheckTextEditor.makeNSView` 의 실측 —
// 제보 ①, v0.3.0~v0.3.12 가 바로 그 결함이고 풀은 그걸 고치려고 만든 것이다).
//
// ⚠︎ **이 파일이 메우는 구멍**: 저장소에 **동시 마운트를 세는 단언이 하나도 없었다.** V0313 은 칸 하나를
//   올렸다 내렸다 하는 것만 봤고(그래서 한 칸짜리 풀도 초록이었다), 그 눈금 때문에 이 결함이 들어왔다.
//   여기서는 **두 칸을 동시에 세워 놓고** 각자 자기 NSTextView 를 돌려받는지, 전송 문이 **각자의 칸**을
//   확정하는지를 잰다.
//
// ⚠︎ 헤드리스 한계: 실제 입력기는 이 프로세스에서 안 돈다 — 표시 글자는 `setMarkedText` 로 직접 심는다.
//   그 심기는 실제 입력기가 하는 일과 같다(V0249·V0311 주석의 2026-09-11 실측).

// MARK: - 헬퍼 (이 파일 전용 — es 접두)

@MainActor
@Observable
private final class ESDraft {
    var text: String
    /// 패널이 서 있는가. 내리면 SwiftUI 가 `dismantleNSView` 로 칸을 반납한다(제품에서 패널이 닫히는 경로).
    var shown = true
    init(_ text: String = "") { self.text = text }
}

/// 대화 패널의 입력칸을 **제품 배선 그대로** 올린다(호출부는 `CheckMessageView.swift` 의 그 자리다).
private struct ESMountedMessageEditor: View {
    @Bindable var model: ESDraft

    var body: some View {
        if model.shown {
            MessageDraftEditor(
                text: $model.text,
                height: MessagePanelLayout.editorHeight,
                focusesWhenShown: false,
                canSendNow: { true },
                onSend: {}
            )
        }
    }
}

/// 제보 패널의 본문 칸(호출부는 `CheckFeedbackView.swift` 의 그 자리다).
///
/// **왜 오목 칸이 아니라 제보 칸인가**: 오목 채팅칸을 감싼 `GomokuChatComposer` 는 `private` 이라 테스트가
/// 세울 수 없다. 재는 성질은 같다 — **서로 다른 호출 자리 두 곳이 동시에 마운트된 채로 각자 제 칸을
/// 돌려받는가**. 한 칸짜리 풀은 이 조합에서도 똑같이 깨진다(그리고 실제로 깨졌다: 아래 두 테스트는
/// 수리 전 빨갛다).
private struct ESMountedFeedbackEditor: View {
    @Bindable var model: ESDraft

    var body: some View {
        if model.shown {
            FeedbackBodyEditor(text: $model.text, height: FeedbackPanelLayout.editorHeight)
        }
    }
}

@MainActor
private func esSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func esSpin(until condition: () -> Bool) {
    var remaining = 100
    while !condition(), remaining > 0 {
        esSpin(0.01)
        remaining -= 1
    }
}

@MainActor
private func esTextView(in root: NSView) -> CheckEditorTextView? {
    if let match = root as? CheckEditorTextView { return match }
    for child in root.subviews {
        if let match = esTextView(in: child) { return match }
    }
    return nil
}

/// 칸을 **자기 창에** 세운다. 창이 둘이어야 이 결함이 재현된다 — 첫 응답자는 창마다 따로라
/// 두 칸이 **동시에** 자기 창의 첫 응답자일 수 있다(2026-09-16 실측).
@MainActor
private func esMount<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> (NSWindow, NSHostingView<some View>) {
    let host = NSHostingView(rootView: view.frame(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    esSpin()
    return (window, host)
}

/// 사람이 치듯 한 글자씩 확정해 넣는다(입력기가 확정할 때 부르는 그 문).
@MainActor
private func esType(_ text: String, into textView: NSTextView) {
    for character in text {
        textView.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        esSpin(0.01)
    }
    esSpin()
}

/// 입력기가 표시 글자를 세우는 그 경로(`NSTextInputClient.setMarkedText`)를 그대로 지난다.
@MainActor
private func esMark(_ text: String, in textView: CheckEditorTextView) {
    let replacement = textView.hasMarkedText()
        ? textView.markedRange()
        : NSRange(location: NSNotFound, length: 0)
    textView.setMarkedText(
        text,
        selectedRange: NSRange(location: text.utf16.count, length: 0),
        replacementRange: replacement
    )
    esSpin(0.01)
}

// MARK: - ① 동시에 선 두 칸은 **각자 자기 NSTextView** 를 쓴다

@MainActor
@Test
func twoEditorsMountedAtOnceEachReuseTheirOwnTextView() throws {
    CheckTextEditor.resetPoolForTesting()
    defer { CheckTextEditor.resetPoolForTesting() }

    let talk = ESDraft()
    let report = ESDraft()
    let (_, talkHost) = esMount(
        ESMountedMessageEditor(model: talk),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    let (_, reportHost) = esMount(
        ESMountedFeedbackEditor(model: report),
        width: FeedbackPanelLayout.contentWidth, height: FeedbackPanelLayout.editorHeight
    )
    esSpin()

    let talk1 = try #require(esTextView(in: talkHost), "대화 칸이 안 올라왔다")
    let report1 = try #require(esTextView(in: reportHost), "제보 칸이 안 올라왔다")
    // 한 뷰는 두 곳에 못 붙는다 — 여기서 같으면 뷰 계층이 이미 깨진 것이다.
    #expect(talk1 !== report1, "동시에 선 두 칸이 NSTextView 한 벌을 나눠 쓴다")

    // 두 패널을 내린다(오목 창이 뜬 채 팝오버가 닫혔다 다시 서는, 바로 그 경로).
    talk.shown = false
    report.shown = false
    esSpin(until: { esTextView(in: talkHost) == nil && esTextView(in: reportHost) == nil })
    try #require(esTextView(in: talkHost) == nil, "대화 칸이 안 내려갔다 — 반납 경로를 안 지났다")
    try #require(esTextView(in: reportHost) == nil, "제보 칸이 안 내려갔다 — 반납 경로를 안 지났다")

    // 다시 세운다. **각자 자기 칸을 돌려받아야 한다.**
    talk.shown = true
    report.shown = true
    esSpin(until: { esTextView(in: talkHost) != nil && esTextView(in: reportHost) != nil })
    let talk2 = try #require(esTextView(in: talkHost), "대화 칸이 다시 안 올라왔다")
    let report2 = try #require(esTextView(in: reportHost), "제보 칸이 다시 안 올라왔다")

    // ★ 한 칸짜리 풀에서는 나중에 반납한 칸이 앞의 것을 덮어써, 둘 중 하나는 **새로 만들어진다.**
    //   새로 만들어진 NSTextView 는 한글 입력기 세션을 못 받아 자모가 하나씩 박힌다(제보 ①).
    #expect(talk2 === talk1,
            "대화 칸이 자기 NSTextView 를 못 돌려받았다 — 새로 만들어진 칸은 한글 조합이 죽는다(v0.3.13 회귀)")
    #expect(report2 === report1,
            "제보 칸이 자기 NSTextView 를 못 돌려받았다 — 같은 자모 분리 결함이 이 칸에서 되살아난다")
}

// MARK: - ② 전송 문은 **사용자가 치고 있던 칸**을 확정한다

@MainActor
@Test
func theSendDoorCommitsTheEditorTheUserIsComposingIn() throws {
    CheckTextEditor.resetPoolForTesting()
    defer { CheckTextEditor.resetPoolForTesting() }

    let talk = ESDraft()
    let report = ESDraft()
    let (talkWindow, talkHost) = esMount(
        ESMountedMessageEditor(model: talk),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    let (reportWindow, reportHost) = esMount(
        ESMountedFeedbackEditor(model: report),
        width: FeedbackPanelLayout.contentWidth, height: FeedbackPanelLayout.editorHeight
    )
    esSpin()
    let talkEditor = try #require(esTextView(in: talkHost), "대화 칸이 안 올라왔다")
    let reportEditor = try #require(esTextView(in: reportHost), "제보 칸이 안 올라왔다")

    // 두 칸이 **각자 자기 창의 첫 응답자**가 된다. 포커스를 나중에 받은 쪽은 제보 칸이다 —
    // 옛 규칙(정적 한 칸)은 이 시점부터 **영영 제보 칸만** 가리킨다.
    talkWindow.makeFirstResponder(talkEditor)
    reportWindow.makeFirstResponder(reportEditor)
    esSpin()
    try #require(talkEditor.holdsFirstResponder, "대화 칸이 자기 창의 첫 응답자가 아니다 — 전제가 안 섰다")
    try #require(reportEditor.holdsFirstResponder, "제보 칸이 자기 창의 첫 응답자가 아니다 — 전제가 안 섰다")

    // 사용자는 **대화 칸**에 쓰고 있다(마지막 음절은 조합 중).
    esType("안녕하세", into: talkEditor)
    esMark("요", in: talkEditor)
    try #require(talkEditor.string == "안녕하세요", "전제가 안 만들어졌다: \(talkEditor.string.debugDescription)")
    try #require(talk.text == "안녕하세", "전제가 안 만들어졌다: \(talk.text.debugDescription)")
    try #require(!reportEditor.hasMarkedText(), "제보 칸이 조합 중이다 — 전제가 안 섰다")

    // 화면의 [보내기]가 지나는 그 문.
    var read: String?
    let committed = CheckEditorSend.commitThenSend { read = talk.text }
    #expect(committed, "확정할 조합이 있는데 문이 아무 일도 안 했다 — 다른 창의 칸을 확정했다")
    #expect(read == "안녕하세요",
            "전송 문이 엉뚱한 칸을 확정해 이 칸의 마지막 음절이 사라졌다: \(read.debugDescription)")
    #expect(!talkEditor.hasMarkedText(), "확정 뒤에도 표시 글자가 남았다")

    // 반대 방향도 같다. 캐시를 **대화 칸**으로 되돌려 놓고(resign → become) 제보 칸에 쓴다.
    // (이미 첫 응답자인 칸에 `makeFirstResponder` 를 다시 불러도 `becomeFirstResponder` 는 안 온다 —
    //  2026-09-16 실측. 그래서 캐시를 옮기려면 한 번 놓았다 다시 잡아야 한다.)
    talkWindow.makeFirstResponder(nil)
    talkWindow.makeFirstResponder(talkEditor)
    esSpin()
    esType("재현 순서", into: reportEditor)
    esMark("요", in: reportEditor)
    try #require(reportEditor.string == "재현 순서요", "전제가 안 만들어졌다: \(reportEditor.string.debugDescription)")
    try #require(!talkEditor.hasMarkedText(), "대화 칸이 조합 중이다 — 전제가 안 섰다")

    var reportRead: String?
    let reportCommitted = CheckEditorSend.commitThenSend { reportRead = report.text }
    #expect(reportCommitted, "제보 칸의 조합을 문이 못 찾았다 — 대화 칸을 확정했다")
    #expect(reportRead == "재현 순서요",
            "전송 문이 엉뚱한 칸을 확정해 제보 칸의 마지막 음절이 사라졌다: \(reportRead.debugDescription)")
}

// MARK: - ③ 자리는 **호출부마다 하나**이고 늘지 않는다

@MainActor
@Test
func theEditorPoolKeepsOneSlotPerCallSiteAndDoesNotGrow() throws {
    CheckTextEditor.resetPoolForTesting()
    defer { CheckTextEditor.resetPoolForTesting() }

    let box = ESDraft()
    let binding = Binding(get: { box.text }, set: { box.text = $0 })

    // 줄이 다르면 자리가 다르다 — 그래야 동시에 서도 서로의 칸을 안 뺏는다.
    let here = CheckTextEditor(text: binding)
    let there = CheckTextEditor(text: binding)
    #expect(here.slot != there.slot,
            "호출 자리가 다른데 같은 자리를 쓴다 — 동시에 서면 한쪽이 새 칸을 받아 한글 조합이 죽는다")

    // 같은 줄에서 몇 번을 만들어도 자리는 하나다(**자리가 유한한 이유** — 키가 소스 위치라서 그렇다).
    var repeated = Set<CheckEditorSlot>()
    for _ in 0..<5 { repeated.insert(CheckTextEditor(text: binding).slot) }
    #expect(repeated.count == 1,
            "같은 호출 자리가 부를 때마다 새 자리를 만든다 — 풀이 무한정 자란다: \(repeated.count)")

    // 올렸다 내리기를 되풀이해도 자리는 그 하나뿐이다.
    let model = ESDraft()
    let (_, host) = esMount(
        ESMountedMessageEditor(model: model),
        width: MessagePanelLayout.contentWidth, height: MessagePanelLayout.editorHeight
    )
    for _ in 0..<3 {
        model.shown = false
        esSpin(until: { esTextView(in: host) == nil })
        model.shown = true
        esSpin(until: { esTextView(in: host) != nil })
    }
    model.shown = false
    esSpin(until: { esTextView(in: host) == nil })
    #expect(CheckTextEditor.pooledSlotCountForTesting() == 1,
            "마운트를 되풀이하자 자리가 늘었다: \(CheckTextEditor.pooledSlotCountForTesting())")
}
