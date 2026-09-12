import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.14 답장 칸의 한글 조합 (2026-09-12 실측)
//
// **묻는 것**: v0.3.14 에 생긴 제보 **답장 칸**이 v0.3.11 의 "뒤에 한 글자가 사라져요"(기모찌 제보)를
// 그대로 되풀이하는가.
//
// **왜 의심했나**: v0.3.11 의 수리는 `CheckEditorSend.commitThenSend` 이고, 그 문은 대상을
// `CheckEditorTextView.focusedEditor` 로만 찾는다. 답장 칸은 `TextField`(→ `NSTextField`)라
// **그 정적 참조에 한 번도 등록되지 않는다.** 같은 결함이 새 자리에 날 자리가 그대로 있었다.
//
// ★ **잰 결과: 결함이 있었다.** 화면을 올려 조합을 심고 [답장 보내기]의 동작을 태운 값이다(수리 전):
//     확정 4글자 후 : editor="확인했어"   draft="확인했어"
//     조합 한 음절 후: editor="확인했어요" field="확인했어요" draft="확인했어"   ← 화면과 바인딩이 갈린다
//     나간 본문      : {"p_note":"확인했어","p_id":"r1"}                        ← 마지막 음절이 안 갔다
//   관리자가 화면에서 본 답장과 **제보자가 받은 답장이 다르다.** 그것도 답장은 목록에 그대로 남으므로
//   (`performSendFeedbackReply` 가 서버가 받은 값을 행에 쓴다) 관리자는 자기 글이 잘린 것을 못 본다.
//
// ★★ **이 저장소가 이 주제에서 두 번 오진했다. 그래서 가정 대신 값을 적어 둔다**(전부 이 파일의 하네스로
//    같은 화면에서 잰 것이다):
//    · 답장 칸의 진짜 뷰는 `AppKitTextField`(NSTextField 하위) 하나뿐이고, **글자를 받는 것은 그 필드가
//      아니라 창이 빌려주는 필드 에디터** `SwiftUI._SystemTextFieldFieldEditor`(NSTextView 하위)다.
//      `NSTextField` 에는 `hasMarkedText()` 자체가 **없다** — 물을 대상을 잘못 고르면 아무것도 못 잰다.
//    · 그 필드 에디터에서 조합 중 `hasMarkedText() == true`, `markedRange() == {4,1}` 이었다.
//      즉 이 칸에서도 2벌식 한글은 표시 글자를 **쓴다**(`CheckTextEditor.swift` 머리 주석의 재측정과 같은 결론).
//    · 표시 글자 구간에는 바인딩이 안 올라온다 — `field.stringValue` 는 "확인했어요"인데 바인딩은 "확인했어".
//      `NSTextField` 계열이라고 다르지 않았다. **한 음절 뒤처짐은 두 계열 공통이다.**
//
// **수리**: `FeedbackReplySend`(CheckFeedbackView.swift) — 필드 에디터를 상대하는 같은 관용구의 문.
// 네 후보를 같은 화면에서 재 보고 고른 근거는 그 enum 의 주석에 값으로 적혀 있다.
//
// ⚠︎ **고치지 않고 남긴 것 하나**(측정으로 확인했고, 이 파일의 마지막 테스트가 그 사실을 붙들어 둔다):
//    답장 **전체가 조합 중인 한 음절뿐**일 때("넵")는 바인딩이 `""` 라 `canSendFeedbackReply == false` 이고,
//    그래서 버튼이 `.disabled` 다 — **동작 자체가 안 불린다.** 문이 앞에 있어도 소용이 없다.
//    이건 답장 칸만의 결함이 아니라 보내기 탭 [보내기]도 같이 갖고 있는 **더 넓은 구멍**이고
//    (`canSendFeedback` 도 같은 초안을 읽는다), 고치려면 "판정은 스토어 하나"라는 이 화면의 규약
//    (`FeedbackInboxRow.canSendReply` 주석)을 건드려야 한다. 이 작업의 범위가 아니라 값만 남긴다.

// MARK: - 하네스 (이 파일 전용 — fr 접두)

@MainActor
private func frSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func frAll(_ view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap { frAll($0) }
}

/// 필드 에디터는 **창이 key 가 될 수 있을 때만** 선다. 보통의 borderless 창으로는 아무것도 안 잡힌다.
private final class FRKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private let frUserID = "00000000-0000-0000-0000-000000000002"
private let frOtherID = "00000000-0000-0000-0000-000000000003"

/// 스텁 네트워크에 물린 관리자 스토어 + 펼쳐 둔 제보 한 건.
/// `FeedbackURLProtocol`(V0248 의 것)에 호스트별로 응답을 심고 **나간 본문**을 되받는다.
@MainActor
private func frStore(host: String) -> WorkTimerStore {
    FeedbackURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: FeedbackURLProtocol.session()
    )
    let suite = "v0314-ime-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: frUserID)
    store.ultraUnlimited = true
    store.appVersionProvider = { AppVersionReport(build: 58, version: "0.3.14") }
    store.osVersionProvider = { "15.6" }
    store.feedbackList = [
        FeedbackReport(
            id: "r1", userID: frOtherID, kind: .bug, body: "샘플 본문", status: .open,
            adminNote: nil, adminNoteAt: nil, appVersion: "0.3.14 (58)", osVersion: "15.6",
            createdAt: Date(timeIntervalSince1970: 1_789_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_789_000_000),
            authorName: "동료", authorAvatarURL: nil
        )
    ]
    store.feedbackLoaded = true
    store.toggleFeedbackExpansion("r1")
    return store
}

/// 제품 화면(받은 제보 탭)을 그대로 올리고, 답장 칸에 **입력기가 부르는 그 문으로** 글을 넣는다.
///
/// - Parameters:
///   - typed: 확정해 넣을 글자들(`insertText` — 입력기가 음절을 확정할 때 부르는 문).
///   - marked: 조합 중으로 남길 마지막 음절(`setMarkedText` — 입력기가 표시 글자를 세우는 그 문).
/// - Returns: (창, 화면, 답장 칸, 필드 에디터)
@MainActor
private func frMountComposing(
    _ store: WorkTimerStore, typed: String, marked: String
) throws -> (NSWindow, FeedbackInboxView, NSTextField, NSTextView) {
    let screen = FeedbackInboxView(store: store)
    let hosting = NSHostingView(rootView: screen.frame(width: 292, height: 420))
    hosting.frame = NSRect(x: 0, y: 0, width: 292, height: 420)
    let window = FRKeyWindow(
        contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    frSpin()
    window.makeKeyAndOrderFront(nil)

    let field = try #require(
        frAll(hosting).compactMap { $0 as? NSTextField }.first { $0.isEditable },
        "올린 화면에 편집 가능한 답장 칸이 없다"
    )
    _ = window.makeFirstResponder(field)
    frSpin()
    let editor = try #require(
        field.currentEditor() as? NSTextView, "답장 칸에 필드 에디터가 안 섰다 — 조합을 심을 자리가 없다"
    )
    for character in typed {
        editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
        frSpin(0.01)
    }
    frSpin()
    if !marked.isEmpty {
        editor.setMarkedText(
            marked,
            selectedRange: NSRange(location: (marked as NSString).length, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        frSpin()
    }
    return (window, screen, field, editor)
}

/// 조건이 설 때까지 기다린다.
///
/// **왜 2000번인가**(V0248/V0311 의 200번에서 늘렸다): 전송은 `Task { @MainActor in … }` 한 홉을 건너뛴 뒤에야
/// 왕복을 시작하는데, 전체 테스트가 한꺼번에 돌 때는 메인 액터가 다른 렌더 테스트에 붙들려 그 홉이 늦게 온다.
/// 200번(≈1초)으로는 **부하에서만** 빈손으로 끝났다(2026-09-12 전체 실행: 나간 요청 0건으로 빨개졌다).
/// 상한을 늘려도 조건이 서면 즉시 빠져나오므로 평소 실행은 그대로 빠르다.
private func frWait(_ condition: @Sendable () async -> Bool) async {
    for _ in 0..<2000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 나간 `reply_feedback` 본문에서 답장 글만 꺼낸다.
private func frSentNote(host: String, path: String) -> String? {
    guard let raw = FeedbackURLProtocol.sentBodies(host: host, path: path).first,
          let payload = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
    else { return nil }
    return payload["p_note"] as? String
}

/// 제품 소스를 **주석 없이** 읽는다. 걷어내지 않으면 설명을 지워야만 초록이 되는 테스트가 된다
/// (이 저장소가 이미 겪은 함정 — V0311 의 `kcSource` 와 같은 이유).
private func frSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)      // Tests/checkTests/V0314FeedbackReplyIMETests.swift
        .deletingLastPathComponent()                // Tests/checkTests
        .deletingLastPathComponent()                // Tests
        .deletingLastPathComponent()                // (repo root)
        .appendingPathComponent("Sources/check/\(name)")
    return frStripComments(try String(contentsOf: url, encoding: .utf8))
}

private func frStripComments(_ source: String) -> String {
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

// MARK: - ① 바닥 사실: 답장 칸이 무엇으로 되어 있고, 조합 중 무엇이 어긋나는가

/// **이 테스트는 수리를 재지 않는다 — 수리가 상대해야 할 세계를 못 박는다.**
/// 이 칸을 `CheckTextEditor` 로 갈아 끼우거나 SwiftUI 가 뒷단을 바꾸면 여기서 먼저 빨개져야,
/// 아래 두 테스트가 "무엇을 재고 있었는지 모른 채" 초록으로 남는 일이 없다.
@MainActor
@Test
func theReplyFieldIsAnNSTextFieldWhoseFieldEditorHoldsTheKoreanComposition() throws {
    let store = frStore(host: "v0314-ime-ground")
    let (_, _, field, editor) = try frMountComposing(store, typed: "확인했어", marked: "")

    // 뒷단 계약 — 여기가 바뀌면 아래 측정이 재는 길이 화면이 지나는 길과 갈린다.
    #expect(field is NSTextField, "답장 칸이 더는 NSTextField 계열이 아니다")
    #expect(editor.isFieldEditor, "글자를 받는 것이 필드 에디터가 아니다 — 조합이 다른 곳에 있다")

    // 확정 구간에는 바인딩이 제때 따라온다. (뒤처짐은 **조합 구간에만** 있다는 것을 갈라 보인다.)
    #expect(editor.string == "확인했어", "확정 입력이 뷰에 안 들어갔다: \(editor.string.debugDescription)")
    #expect(store.feedbackNoteDraft == "확인했어",
            "확정 구간인데 바인딩이 안 따라왔다: \(store.feedbackNoteDraft.debugDescription)")

    // 조합 한 음절을 세운다 — 입력기가 부르는 그 문 그대로.
    editor.setMarkedText(
        "요", selectedRange: NSRange(location: 1, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    frSpin()

    // ★ 잰 값: 화면에는 있고 바인딩에는 없다.
    #expect(editor.hasMarkedText(), "이 칸에서는 2벌식 한글이 표시 글자를 안 쓴다 — 전제가 통째로 다르다")
    #expect(editor.markedRange() == NSRange(location: 4, length: 1),
            "표시 글자 구간이 예상과 다르다: \(editor.markedRange())")
    #expect(editor.string == "확인했어요", "필드 에디터: \(editor.string.debugDescription)")
    #expect(field.stringValue == "확인했어요", "필드: \(field.stringValue.debugDescription)")
    #expect(store.feedbackNoteDraft == "확인했어",
            "바인딩이 조합 중 음절까지 갖고 있다 — 그렇다면 수리도 아래 두 테스트도 재는 것이 없다: \(store.feedbackNoteDraft.debugDescription)")
}

// MARK: - ② 결함: 문을 안 지나면 마지막 음절이 안 나간다 (대조군)

/// **기준선이 달라야 한다.** 이 테스트는 v0.3.14 첫 판이 하던 일(`store.sendFeedbackReply` 직접 호출)을
/// 그대로 태워, 아래 ③과 **정확히 문 하나만 다른** 두 값을 만든다. 이게 없으면 ③은 "원래 잘 되던 것"을
/// 재고 있는지 알 수 없다.
@MainActor
@Test
func withoutTheDoorTheReplyLeavesWithoutItsLastSyllable() async throws {
    let host = "v0314-ime-nodoor"
    let path = "/rest/v1/rpc/reply_feedback"
    let store = frStore(host: host)
    FeedbackURLProtocol.set(.init(status: 200, body: #""2026-09-12T00:00:00Z""#), host: host, path: path)
    _ = try frMountComposing(store, typed: "확인했어", marked: "요")

    // 옛 배선 그대로: 확정 없이 스토어를 바로 부른다.
    store.sendFeedbackReply(id: "r1")
    await frWait { FeedbackURLProtocol.count(host: host, path: path) > 0 }

    #expect(frSentNote(host: host, path: path) == "확인했어",
            "문 없이도 마지막 음절이 실렸다 — 그렇다면 ③이 재는 차이가 없다: \(String(describing: frSentNote(host: host, path: path)))")
}

// MARK: - ③ 수리: 화면의 [답장 보내기] 동작이 조합 중이던 음절까지 보낸다

/// 두 가지를 이어 붙인다(V0311 의 `theFeedbackSendButtonActionShipsTheComposingSyllable` 과 같은 구조):
///   ① 버튼의 동작이 `replyTapped` 라는 것 — SwiftUI Button 은 헤드리스에서 못 누른다(합성 NSEvent·
///      `accessibilityPerformPress` 둘 다 안 먹는 것이 이 저장소에서 실측됐다),
///   ② 올린 화면 그대로 그 동작을 태웠을 때 **서버로 나가는 본문**에 조합 중이던 음절이 실린다는 것.
@MainActor
@Test
func theReplyButtonActionShipsTheComposingSyllable() async throws {
    let source = try frSource("CheckFeedbackView.swift")
    try #require(source.contains("onReply: { replyTapped(report) }"),
                 "[답장 보내기] 버튼이 replyTapped 를 안 쓴다 — 아래 값 측정이 화면이 안 지나는 길을 재게 된다")

    let host = "v0314-ime-door"
    let path = "/rest/v1/rpc/reply_feedback"
    let store = frStore(host: host)
    FeedbackURLProtocol.set(.init(status: 200, body: #""2026-09-12T00:00:00Z""#), host: host, path: path)
    let (window, screen, _, editor) = try frMountComposing(store, typed: "확인했어", marked: "요")

    // 전제(②와 같은 상태)가 실제로 만들어졌는지 먼저 확인한다.
    try #require(editor.string == "확인했어요", "전제가 안 만들어졌다: \(editor.string.debugDescription)")
    try #require(store.feedbackNoteDraft == "확인했어",
                 "전제가 안 만들어졌다: \(store.feedbackNoteDraft.debugDescription)")
    try #require(store.canSendFeedbackReply, "버튼이 잠겨 있다 — 동작을 태워도 화면과 다른 길을 재게 된다")
    // 문이 대상을 찾는 통로. 이 프로세스에 화면을 여러 벌 올리므로 **내 창이 잡혀 있는지** 못 박는다
    // (다른 테스트의 창이 잡혀 있으면 아래 측정은 조용히 틀린 것을 잰다).
    try #require(FeedbackReplySend.host === window, "답장 칸이 선 창을 문이 못 찾는다")

    // 버튼이 하는 일 그대로.
    screen.replyTapped(try #require(store.feedbackList.first, "펼쳐 둔 제보가 없다"))
    // 목록 반영까지 기다린다 — 왕복이 **끝났다**는 신호가 그것이다(`performSendFeedbackReply` 는
    // 성공 갈래에서만 행을 건드린다). 요청 수만 보고 넘어가면 아래 마지막 단언이 왕복 도중을 잰다.
    await frWait { @MainActor in store.feedbackList.first?.adminNote != nil }

    #expect(FeedbackURLProtocol.count(host: host, path: path) == 1,
            "[답장 보내기] 가 답장을 안 보냈다(나간 요청 \(FeedbackURLProtocol.count(host: host, path: path))건)")
    #expect(frSentNote(host: host, path: path) == "확인했어요",
            "[답장 보내기] 가 마지막 글자를 잃은 채 보냈다(= 기모찌 제보 v0.3.11 이 답장 칸에 재현된 것): \(String(describing: frSentNote(host: host, path: path)))")
    // 화면에 그려진 답장도 같은 값이어야 한다 — 관리자가 본 것과 제보자가 받은 것이 갈리면 그게 이 결함이다.
    #expect(store.feedbackList.first?.adminNote == "확인했어요",
            "행에 그려진 답장: \(String(describing: store.feedbackList.first?.adminNote))")
}

// MARK: - ④ 확정은 **글자를 버리지 않는다**

/// `discardMarkedText()` 라는 이름 때문에 "버린다"로 읽기 쉽다. 실제로 무엇이 남는지를 값으로 못 박는다 —
/// 만약 이 문이 글자를 버리면 사용자는 **화면에서 글자가 사라지는** 훨씬 나쁜 결함을 본다.
@MainActor
@Test
func theCommitKeepsEveryCharacterItFound() throws {
    let store = frStore(host: "v0314-ime-keep")
    let (window, _, field, editor) = try frMountComposing(store, typed: "확인했어", marked: "요")
    try #require(FeedbackReplySend.host === window, "답장 칸이 선 창을 문이 못 찾는다")

    #expect(FeedbackReplySend.commitActiveComposition(), "확정할 조합이 있는데 문이 아무 일도 안 했다")
    #expect(editor.string == "확인했어요", "확정이 글자를 버렸다: \(editor.string.debugDescription)")
    #expect(field.stringValue == "확인했어요", "필드: \(field.stringValue.debugDescription)")
    #expect(!editor.hasMarkedText(), "확정했는데 표시 글자가 남아 있다 — 다음 글자가 이 음절에 다시 붙는다")
    // ★ 확정은 **동기**다. 런루프를 한 턴도 돌리지 않고 읽는다 — `commitThenSend` 의 두 줄 사이에
    //   기다릴 것이 없다는 사실이 그 순서의 전제다.
    #expect(store.feedbackNoteDraft == "확인했어요",
            "확정이 바인딩까지 못 올렸다(그러면 바로 다음 줄의 전송이 낡은 값을 읽는다): \(store.feedbackNoteDraft.debugDescription)")
    // 커서를 안 뺏는다 — 보낸 뒤 이어 쓰려고 다시 클릭하게 만들면 그것도 결함이다.
    #expect(window.firstResponder === editor, "확정이 포커스를 뺏었다: \(String(describing: window.firstResponder))")

    // 조합이 없으면 아무 일도 안 한다(대부분의 전송이 이 갈래다).
    #expect(!FeedbackReplySend.commitActiveComposition(), "확정할 것이 없는데 뭔가 했다")
}

// MARK: - ⑤ 두 문이 서로의 칸을 건드리지 않는다

/// 답장 칸의 문이 **본문 칸**(`CheckEditorTextView`)을 확정해 버리면, 다른 탭에서 쓰다 만 제보가
/// 조용히 확정되고 그쪽 입력기 세션이 끊긴다. 관문은 `isFieldEditor` 하나다 — 값으로 못 박는다.
@MainActor
@Test
func theReplyDoorNeverTouchesTheBodyEditor() throws {
    let store = frStore(host: "v0314-ime-split")
    let (window, _, _, _) = try frMountComposing(store, typed: "확인했어", marked: "요")
    try #require(FeedbackReplySend.host === window, "답장 칸이 선 창을 문이 못 찾는다")

    // 같은 창에 본문 칸을 세우고 포커스를 거기로 옮긴다(탭을 바꾼 상태와 같다).
    let body = CheckEditorTextView(frame: NSRect(x: 0, y: 0, width: 292, height: 54))
    window.contentView?.addSubview(body)
    _ = window.makeFirstResponder(body)
    frSpin()
    body.string = "제보 본문"
    body.setSelectedRange(NSRange(location: ("제보 본문" as NSString).length, length: 0))
    body.setMarkedText(
        "요", selectedRange: NSRange(location: 1, length: 0),
        replacementRange: NSRange(location: NSNotFound, length: 0)
    )
    frSpin()
    try #require(body.hasMarkedText(), "본문 칸에 표시 글자를 못 심었다 — 이 테스트가 재는 것이 없다")

    #expect(!FeedbackReplySend.commitActiveComposition(),
            "답장 칸의 문이 본문 칸을 확정했다 — 두 문이 같은 뷰를 두고 다툰다")
    #expect(body.hasMarkedText(), "본문 칸의 조합이 남의 손에 끝났다")

    body.removeFromSuperview()
}

// MARK: - ⑥ 소스 계약: 답장 전송이 문을 지나고, 부르는 자리가 하나뿐

/// 계약은 문이 **불리는지**는 모른다(그건 ③이 값으로 잰다). 계약이 막는 것은 **갈래가 늘어나는 것**이다 —
/// v0.3.11 의 결함이 정확히 "세 갈래는 확정을 지나고 한 갈래는 안 지난" 모양이었다.
@Test
func theReplyTravelsThroughOneDoorAndOnlyOne() throws {
    let feedback = try frSource("CheckFeedbackView.swift")
    #expect(feedback.contains("FeedbackReplySend.commitThenSend { store.sendFeedbackReply(id: report.id) }"),
            "답장 전송이 확정 문을 안 지난다 — 답장 칸에서 마지막 글자가 사라진다")
    #expect(feedback.components(separatedBy: "store.sendFeedbackReply(").count - 1 == 1,
            "답장 전송 호출이 둘 이상이다 — 확정을 건너뛰는 갈래가 생겼다")
    // 확정은 **문 안에 한 번만** 적혀 있어야 한다(V0311 이 `CheckTextEditor` 에 건 것과 같은 규약).
    #expect(feedback.components(separatedBy: "editor.unmarkText()").count - 1 == 1,
            "확정을 손으로 부르는 자리가 문 밖에도 있다")
    // 답장 칸의 문은 **본문 칸의 문과 갈라져 있어야** 한다. 같은 문을 부르면 아무것도 확정 안 되면서
    // 다른 탭의 본문 칸만 건드린다(그 근거는 `FeedbackReplySend` 주석).
    #expect(!feedback.contains("CheckEditorSend.commitThenSend { store.sendFeedbackReply"),
            "답장 전송이 본문 칸 전용 문을 부른다 — 답장 칸에서는 아무것도 확정하지 않는다")

    // 창 표식은 **한 자리에서만** 붙는다. 여러 칸이 각자 붙이면 마지막에 붙은 것이 앞의 것을 덮어,
    // 문이 엉뚱한 창의 첫 응답자를 본다.
    #expect(feedback.components(separatedBy: ".background(FeedbackReplyWindowAnchor()").count - 1 == 1,
            "창 표식을 붙이는 자리가 하나가 아니다")
}

// MARK: - ⑥-b 스냅샷 갈래에는 표식이 없다 (값으로)

/// **왜 값으로도 재나**: 소스 계약은 표식이 "한 자리에 있다"까지만 알고, 그 자리가 **진짜 `TextField`
/// 갈래인지**는 모른다. 스냅샷 갈래(`rendersPlainText`)에 끼우면 `ImageRenderer` 가 대체 경로를 쓰는
/// 이유를 스스로 깬다 — 이 저장소가 `Menu` 에서 겪은 '노란 상자' 눈가리개가 그것이다.
@MainActor
@Test
func theSnapshotPathOfTheReplyFieldPlantsNoWindowAnchor() throws {
    let store = frStore(host: "v0314-ime-plain")
    let screen = FeedbackInboxView(store: store, rendersPlainNoteField: true)
    let hosting = NSHostingView(rootView: screen.frame(width: 292, height: 420))
    hosting.frame = NSRect(x: 0, y: 0, width: 292, height: 420)
    let window = FRKeyWindow(
        contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false
    )
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    frSpin()

    #expect(frAll(hosting).compactMap { $0 as? NSTextField }.first { $0.isEditable } == nil,
            "스냅샷 갈래인데 진짜 입력칸이 서 있다")
    #expect(FeedbackReplySend.host !== window,
            "스냅샷 갈래가 창 표식을 심었다 — ImageRenderer 가 대체 경로를 쓰는 이유가 깨진다")
}

// MARK: - ⑦ 고치지 않고 남긴 것: 답장 전체가 조합 중인 한 음절일 때

/// **이 테스트는 수리를 재지 않는다. 남은 구멍을 값으로 붙들어 둔다** — 파일 머리 ⚠︎ 의 그것이다.
/// "넵" 한 음절만 쓴 상태에서는 바인딩이 `""` 라 버튼이 `.disabled` 이고, 그래서 **동작 자체가 안 불린다.**
/// 문은 동작 안에 있으므로 손쓸 자리가 없다. 장래에 판정을 화면이 그린 글자로 바꾸면(보내기 탭의
/// `canSendFeedback` 과 **같이** 바꿔야 한다) 여기가 빨개진다 — 그때 이 주석을 지워라.
@MainActor
@Test
func aReplyThatIsStillOneComposingSyllableCannotEvenBeSent() throws {
    let store = frStore(host: "v0314-ime-onesyllable")
    let (window, _, field, editor) = try frMountComposing(store, typed: "", marked: "넵")
    try #require(FeedbackReplySend.host === window, "답장 칸이 선 창을 문이 못 찾는다")

    #expect(editor.string == "넵", "필드 에디터: \(editor.string.debugDescription)")
    #expect(field.stringValue == "넵", "필드: \(field.stringValue.debugDescription)")
    #expect(store.feedbackNoteDraft.isEmpty,
            "바인딩이 조합 중 음절을 갖고 있다 — 그렇다면 이 구멍은 이미 없다: \(store.feedbackNoteDraft.debugDescription)")
    #expect(!store.canSendFeedbackReply, "버튼이 살아 있다 — 그렇다면 이 구멍은 이미 없다")

    // 문 자체는 이 상태도 확정할 수 있다(못 하는 것은 문이 아니라 **버튼이 안 눌리는 것**이다).
    #expect(FeedbackReplySend.commitActiveComposition(), "문이 한 음절짜리 조합을 못 확정한다")
    #expect(store.feedbackNoteDraft == "넵", "확정 후 바인딩: \(store.feedbackNoteDraft.debugDescription)")
    #expect(store.canSendFeedbackReply, "확정했는데도 버튼이 잠겨 있다")
}
