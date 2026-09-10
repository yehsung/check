import AppKit
import SwiftUI

// MARK: - 공용 여러 줄 입력칸 (v0.2.51)
//
// 사용자 지시(2026-09-11):
//   ② "커멘드 엔터로 보내는게 아니라 엔터로 보내는게 보통 일반적인거 아니야? 메세지 입력하고 엔터로 보낼 수 있게 해줘."
//   ③ "메세지 입력하는 텍스트 있는곳이랑 실제 텍스트 입력하는곳이랑 높이가 안맞아. … 제보 창에서도 똑같이 발생해."
//
// 그 두 문장이 이 파일이 있는 이유 전부다. SwiftUI `TextEditor` 로는 **둘 다 못 한다**:
//
//   · Enter 전송 — `TextEditor` 에는 키를 입력기보다 **먼저** 받아 "지금 표시 글자(marked text)가 떠
//     있는가"를 물어볼 자리가 없다. `NSTextView.keyDown` 은 입력기에 키를 넘기기 직전이라, 그 시점의
//     `hasMarkedText()` 가 "이 Enter 는 조합 확정용인가"를 말해 주는 유일한 자리다.
//
//     ⚠︎ 2026-09-11 실측(macOS 26 · 2벌식 한글, CGEvent 로 **실제 입력기**를 통과시킨 하네스 — 번들 없는 실행 파일과
//     NSPopover 에 세운 번들 앱 두 벌 모두): 이 입력기는 조합 중에도 **표시 글자를 쓰지 않는다.** 기본 NSTextView ·
//     SwiftUI `TextEditor` · 이 뷰 셋 다 "안녕하세요" 를 치는 내내 `markedRange` 길이가 0 이었고, 음절은 저장소에
//     곧바로 들어가 제자리에서 바뀌었다(안ㄴ → 안녀 → 안녕 …). 그래서 이 입력기에서는 **첫 Enter 가 "안녕하세요"
//     전체를 보낸다** — 사용자 지시 원안의 "조합 중 Enter 는 확정만" 은 이 입력기에서 **지켜지지 않는다.**
//     대신 걱정하던 사고(마지막 글자가 빠진 채 나감 · 비운 칸에 "요" 가 홀로 남음 · 전송 직후 친 글자가 앞 음절과
//     붙음)는 한 번도 안 났다. `.commitComposition` 갈래는 표시 글자를 **쓰는** 입력기(일본어·중국어 등)를 위한
//     것이다. 이 기기에는 그런 입력기가 없어 실입력으로는 못 쟀고, 헤드리스 테스트가 표시 글자를 직접 심어 잰다.
//     ★ 판단 자료(2026-09-11, 같은 실입력 하네스에 기록용 평범한 NSTextView 를 세워 입력기가 부르는 것을 받아 적었다):
//     이 입력기는 조합 중 Return 을 받으면 **마지막 음절을 같은 글자로 다시 넣어 조합을 끝내고**
//     (`insertText("요", replacementRange: {4, 1})`) 곧바로 `insertNewline:` 을 부른다. 조합이 없을 때의 Return 은
//     `insertNewline:` 하나뿐이다. 그러니 "조합 중 Enter" 를 가려낼 신호 자체는 있다. 다만 그 신호로 첫 Enter 를
//     "확정만"으로 바꾸면, 한글 문장은 거의 늘 마지막 음절이 조합 중인 채 끝나므로 **모든 메시지가 Enter 두 번**이 된다.
//     지금 코드는 그 신호를 쓰지 않는다(이 입력기에서 첫 Enter = 전송).
//   · 자리 맞추기 — `TextEditor` 안의 NSTextView 는 `lineFragmentPadding` 5pt 를 스스로 얹는다.
//     그래서 placeholder 에 아무리 padding 을 맞춰도 실제 글자는 늘 가로 5pt 만큼 밀려 있었고,
//     세로는 `textContainerInset` 을 못 만져 추측으로 맞출 수밖에 없었다. 여기서는 전부 **직접 정한다**
//     (`lineFragmentPadding = 0`, 스크롤 뷰를 `CheckEditorMetrics.frameInset` 만큼 물리고
//     `textContainerInset = CheckEditorMetrics.textContainerInset`) — 둘을 더한 값이 곧 `CheckEditorMetrics.inset`
//     이라, 자리 맞추기가 추측이 아니라 계산이 된다.
//
// ★ 편집 단축키(⌘V·⌘C·⌘X·⌘A·⌘Z·⇧⌘Z)는 이 텍스트 뷰가 **첫 응답자일 때** `performKeyEquivalent(with:)` 에서
//   직접 받는다. 2026-09-11 에 이 자리의 **전제를 바로잡았다**: 처음 주석은 "앱에 메인 메뉴가 없다"고 적었지만,
//   실행 중인 앱의 메뉴 막대를 손쉬운 사용(AX)으로 읽어 보니 SwiftUI 가 기본으로 세운 **Edit 메뉴가 있다**
//   (Undo ⌘Z · Redo ⇧⌘Z · Cut ⌘X · Copy ⌘C · Paste ⌘V · Select All ⌘A). `LSUIElement` 라 화면에 안 보일 뿐이다.
//   그래도 처리기를 남기는 이유는 `CheckEditorTextView.performKeyEquivalent` 주석에 있다.

/// 두 입력칸(메시지·제보)이 **같이 쓰는** 치수. 한 곳에서만 온다 — placeholder 와 실제 글자가 어긋난
/// 결함(사용자 지시 ③)이 정확히 "두 자리에 각각 숫자를 적어서" 생겼다. 다시 갈라 적지 마라.
enum CheckEditorMetrics {
    /// 글자의 좌상단이 앉는 자리(pt, 칸 테두리 상자 기준). placeholder 의 `.padding` 과 **같은 숫자여야 한다** —
    /// 실제 글자 쪽은 `frameInset` + `textContainerInset` + `lineFragmentPadding = 0` 으로 이 값이 그대로 좌표가 된다.
    ///
    /// 값의 근거(2026-09-11 실측, `NSFont.preferredFont(forTextStyle: .caption1)` = SwiftUI `.font(.caption)`
    /// = 10pt / 줄 높이 **13pt**):
    ///   · 세로 7 — 메시지 칸 54pt 에서 54 − 14 = 40 ≥ 13×3(3줄, `MessagePanelLayout.editorHeight` 산식),
    ///     제보 칸 68pt 에서 68 − 14 = 54 ≥ 13×4(4줄, `FeedbackPanelLayout.editorHeight` 산식). 둘 다 지켜진다.
    ///   · 가로 10 — 카드 모서리(`corner` 10)에 글자가 닿지 않는 최소치. 옛 placeholder 가 쓰던 값이라
    ///     **placeholder 는 제자리에 있고 실제 글자가 그리로 온다**(사용자가 보던 화면이 덜 흔들린다).
    static let inset = CGSize(width: 10, height: 7)

    /// 스크롤 뷰(= 글자가 그려질 수 있는 영역)가 칸 테두리에서 **안쪽으로 물러나는 폭**(pt).
    ///
    /// **왜**(2026-09-11 검증 지적): 스크롤 뷰가 둥근 사각형을 꽉 채우고 있으면, 넘친 글(빨간 테두리 상태)에서
    /// 걸친 줄이 **테두리 선 위로** 그려져 아래 테두리를 가린다(2x 실측: 맨 아래 두 픽셀 줄에 글자 픽셀 227/206).
    /// 옛 `TextEditor` 는 `.padding(4)` 안에서 잘렸으므로 그건 회귀였다. 이 폭만큼 스크롤 뷰를 줄이고
    /// `textContainerInset` 에서 같은 값을 빼서 **글자의 원점은 `inset` 그대로** 둔다.
    /// **0 으로 되돌리지 마라** — 테두리가 다시 글자에 먹힌다. `inset` 보다 크게 잡지도 마라 — 인셋이 음수가 된다.
    static let frameInset: CGFloat = 2

    /// `NSTextView.textContainerInset`. 스크롤 뷰가 이미 `frameInset` 만큼 들어와 있으므로 그만큼 뺀다 —
    /// 둘을 더한 값이 `inset` 이고, 그게 placeholder 의 `.padding` 과 같은 자리다.
    static var textContainerInset: CGSize {
        CGSize(width: inset.width - frameInset, height: inset.height - frameInset)
    }
}

/// Enter 키가 할 일 (순수 판정 — 헤드리스에서 결정적으로 잴 수 있는 지점).
///
/// **왜 뷰 밖으로 뺐나**: 갈래가 다섯이고 그중 둘(조합 중 · 못 보내는 상태)은 "아무 일도 안 일어나는 것"이
/// 정답이라, 뷰 안에 두면 회귀가 났을 때 **아무도 못 본다**(줄바꿈이 조용히 생기거나 조용히 사라진다).
enum CheckEditorReturnKey {
    enum Action: Equatable {
        /// 전송한다. 버튼·⌘↩ 과 **같은 문**(`store.sendDraftMessage()`)을 지난다.
        case send
        /// 줄바꿈. 시스템 기본 동작(`super.keyDown`)에 그대로 넘긴다.
        case newline
        /// 조합만 확정한다. IME 에 키를 넘기되 **뒤따라오는 줄바꿈은 삼킨다** — 아래 주석 참고.
        case commitComposition
        /// 아무 일도 안 한다(줄바꿈도 아니다).
        case nothing
    }

    /// - Parameters:
    ///   - sendsOnReturn: 이 칸이 Enter 로 보내는 칸인가. **제보 칸은 false 다** — 버그 설명은 여러 줄로
    ///     쓰는 글이라 Enter 전송이 문장을 반토막 낸다(사용자 지시 ②는 "메세지 입력"에 대한 말이었다).
    ///   - hasShift: ⇧ 가 눌렸는가. ⇧↩ 는 언제나 줄바꿈이다.
    ///   - isComposing: 입력기가 표시 글자(marked text)를 띄워 둔 상태인가(`NSTextView.hasMarkedText()`).
    ///     macOS 2벌식 한글은 표시 글자를 안 쓰므로 그 입력기에서는 늘 false 다(파일 머리 주석의 실측).
    ///   - canSend: 지금 보낼 수 있는가(`store.canSendMessageNow`).
    static func action(sendsOnReturn: Bool, hasShift: Bool, isComposing: Bool, canSend: Bool) -> Action {
        // 제보 칸: 조합이든 아니든 시스템이 하던 그대로.
        guard sendsOnReturn else { return .newline }
        // ⇧↩ 는 줄바꿈이다. 조합 중이어도 마찬가지 — IME 가 먼저 확정하고 줄이 바뀐다.
        if hasShift { return .newline }
        // ★ 표시 글자가 떠 있으면 이 Enter 는 **조합 확정용**이다. 여기서 보내면 조합 중인 글자가 빠진 문장이
        //   나가고, 확정된 글자는 방금 비운 칸에 홀로 남는다(옛 메신저들이 겪은 사고). 이 줄을 지우지 마라.
        if isComposing { return .commitComposition }
        // 못 보내는 상태(빈 칸 · 상대 없음 · 전송 중)에서는 **줄바꿈도 아니다**. 빈 칸에서 Enter 를 눌렀는데
        // 줄만 늘어나면 사용자는 "안 보내진다"가 아니라 "칸이 이상하다"로 읽는다.
        return canSend ? .send : .nothing
    }

    /// Return 키인가(본체 ↩ 와 키패드 ⌤ 둘 다).
    static func isReturn(keyCode: UInt16) -> Bool { keyCode == 36 || keyCode == 76 }
}

// MARK: - NSTextView

/// Enter 판정과 편집 단축키를 직접 받는 텍스트 뷰. `CheckTextEditor` 밖에서 쓰지 마라.
///
/// `final` 이 아닌 이유: 테스트가 이 클래스를 상속한 스파이로 ⌘V·⌘C·⌘X 가 **어느 명령을 부르는지** 잰다.
/// 진짜 명령을 부르면 사용자의 붙여넣기판(`NSPasteboard.general`)을 덮어쓰기 때문이다.
class CheckEditorTextView: NSTextView {
    /// Enter 로 보내는 칸인가(제보 칸은 false).
    var sendsOnReturn = false
    /// 지금 보낼 수 있는가. **값이 아니라 클로저다** — 뷰가 다시 그려질 때마다 갱신되므로,
    /// 스냅샷된 Bool 을 들고 있으면 "방금 지웠는데 아직 보낼 수 있다고 믿는" 창이 생긴다.
    var canSendNow: () -> Bool = { false }
    /// 보내는 문. `store.sendDraftMessage()` 하나로 간다.
    var onSend: () -> Void = {}

    /// 조합 확정 직후 따라오는 줄바꿈 하나를 삼킬 것인가.
    ///
    /// **왜 필요한가**: 표시 글자를 쓰는 입력기는 조합 중 Return 을 받으면 조합을 확정한 뒤 그 키를
    /// **처리하지 않은 것으로 돌려줄 수 있다**. 그러면 `interpretKeyEvents` 가 이어서 `insertNewline(_:)` 을
    /// 부르고, 사용자는 글자를 확정했을 뿐인데 줄이 하나 생긴다. 그 한 줄을 여기서 삼킨다.
    /// (입력기가 Return 을 먹어 버리면 `insertNewline` 은 애초에 안 불리므로 이 깃발은 아무 일도 안 한다.)
    private var swallowsNextNewline = false

    override func keyDown(with event: NSEvent) {
        guard CheckEditorReturnKey.isReturn(keyCode: event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌘↩ 는 보내기 버튼의 `keyboardShortcut` 이 먼저 먹어서 보통 여기까지 오지 않는다.
        // 와도 삼키지 않는다 — 손버릇을 깨지 않는다는 약속(사용자 지시 ②는 "엔터도 되게"이지 "⌘엔터를 없애라"가 아니다).
        guard !flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else {
            super.keyDown(with: event)
            return
        }
        switch CheckEditorReturnKey.action(
            sendsOnReturn: sendsOnReturn,
            hasShift: flags.contains(.shift),
            isComposing: hasMarkedText(),
            canSend: canSendNow()
        ) {
        case .newline:
            super.keyDown(with: event)
        case .commitComposition:
            // IME 가 조합을 확정하는 동안만 문을 닫는다. `super.keyDown` 은 동기라(입력기 처리 →
            // 필요하면 곧바로 `insertNewline`) 이 한 줄 뒤에 여는 것으로 충분하다.
            swallowsNextNewline = true
            super.keyDown(with: event)
            swallowsNextNewline = false
        case .send:
            onSend()
        case .nothing:
            break
        }
    }

    override func insertNewline(_ sender: Any?) {
        guard !swallowsNextNewline else { return }
        super.insertNewline(sender)
    }

    /// ⌃↩ 등이 부르는 "줄 나눔"은 U+2028(LINE SEPARATOR)을 넣는다. 그 글자는 서버로 가서
    /// 말풍선·제보 목록에서 **줄로 보이지 않고** 사라진 것처럼 보인다. 평범한 개행으로 되돌린다.
    override func insertLineBreak(_ sender: Any?) {
        insertNewline(sender)
    }

    /// 편집 단축키 여섯(⌘V·⌘C·⌘X·⌘A·⌘Z·⇧⌘Z)을 직접 받는다.
    ///
    /// ★ **첫 응답자일 때만 받는다**(2026-09-11 검증 지적). `performKeyEquivalent` 는 포커스를 따라가는 호출이
    ///   아니라 **창의 뷰 계층 전체를 도는** 호출이다. 이 가드가 없으면 같은 창의 다른 입력칸에 포커스가 있어도
    ///   이 칸이 ⌘A·⌘V·⌘Z 를 가로챈다(헤드리스 실측: SwiftUI `TextField` 에 포커스를 둔 채 창에 ⌘A →
    ///   처리됨 = true, 이 칸의 선택만 {13,0} → {0,13}). 가드를 넣은 뒤 실이벤트 하네스에서는 `TextField` 포커스의 ⌘A 가
    ///   메뉴로 가고 이 칸의 선택은 {3,0} 그대로였다. 지우지 마라.
    ///
    /// **Edit 메뉴가 있는데 왜 남기나**(파일 머리 주석의 AX 실측):
    ///   · **이 칸에 포커스가 있으면 실제로 먼저 받는 쪽이 이 처리기다.** 2026-09-11 실이벤트 하네스(NSPopover 에 이 파일을
    ///     그대로 세우고, 실앱과 같은 항목의 Edit 메뉴를 달아 항목이 불리면 기록)에서 ⌘Z · ⇧⌘Z · 한글 자판 ⌘A 는 메뉴 기록을
    ///     **한 줄도 안 남겼다** — 창의 뷰 계층이 메뉴보다 먼저 키 등가물을 받는다. 그러니 이 처리기를 지우면 되돌리기·
    ///     붙여넣기가 메뉴 경로로 바뀌고, 그 경로는 이 칸에서 따로 재 본 적이 없다.
    ///   · 그 메뉴는 SwiftUI 가 세운 **보이지 않는 기본값**이다. 누가 `.commands` 로 편집 묶음을 갈아 끼우면 팝오버 안
    ///     붙여넣기·되돌리기가 조용히 죽고, `LSUIElement` 앱이라 그 죽음을 알려 줄 메뉴 막대도 없다.
    /// 처리기는 첫 응답자인 자기 자신에게 메뉴와 **같은 명령**을 부른다. 처리하는 것은 이 여섯뿐이고 나머지는 흘려보낸다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else {
            return super.performKeyEquivalent(with: event)
        }
        let shifted = flags.contains(.shift)
        switch Self.editingKey(characters: event.characters, ignoringModifiers: event.charactersIgnoringModifiers) {
        case "v" where !shifted: paste(nil)
        case "c" where !shifted: copy(nil)
        case "x" where !shifted: cut(nil)
        case "a" where !shifted: selectAll(nil)
        case "z" where !shifted: undoManager?.undo()
        case "z" where shifted: undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// ⌘ 와 함께 눌린 글자를 **영문 한 글자**로 읽는다. 둘 중 영문인 쪽을 쓴다.
    ///
    /// ★ 2026-09-11 실측(2벌식 한글 입력기, ⌘V): `characters` = "v", `charactersIgnoringModifiers` = **"ㅍ"**.
    ///   `charactersIgnoringModifiers` 하나만 보면 한글 자판에서 이 처리기의 ⌘V·⌘A·⌘Z 가 통째로 빗나간다.
    ///   반대로 ⌘, 모니터(`CheckSettingsShortcut`)는 `characters` 가 조합 중 글자를 돌려준 적이 있어
    ///   `charactersIgnoringModifiers` 를 본다 — 그래서 한쪽만 믿지 않고 **영문이 나온 쪽**을 쓴다.
    /// `nonisolated` 인 이유: 뷰 상태를 안 만지는 순수 판정이다. NSTextView 의 메인 액터 격리를 물려받으면
    /// 헤드리스 테스트가 이 한 줄을 재려고 메인 액터로 올라가야 한다.
    nonisolated static func editingKey(characters: String?, ignoringModifiers: String?) -> String {
        for candidate in [characters, ignoringModifiers] {
            guard let value = candidate?.lowercased(), value.count == 1,
                  let scalar = value.unicodeScalars.first, scalar.isASCII else { continue }
            return value
        }
        return ""
    }

    /// 바깥(스토어)이 글을 바꿔 쓸 때의 **유일한 문**. `string =` 을 바로 쓰지 마라 — 아래 이유로 되돌리기가 굳는다.
    ///
    /// **왜 되돌리기 기록부터 지우나**(2026-09-11 검증 지적 — NSPopover 번들 앱에 실제 키 이벤트로 재현):
    /// 스토어는 전송 성공 · 대화 상대 전환 · 제보 전송 성공에서 초안을 `""` 로 비운다. `string =` 은 되돌리기에
    /// 등록되지 않으므로, 그 전에 친 글자의 기록("hello" 다섯 글자)이 **이제 없는 범위**를 가리킨 채 남는다.
    /// 그 뒤 첫 ⌘Z 가 안에서 `NSRangeException`(Range {0, 5} out of bounds; string length 0)을 내고 멈추면서
    /// 창의 되돌리기 관리자가 묶음을 연 채(grouping level 1) 굳는다 — **그 팝오버 창에서는 앱을 끌 때까지
    /// ⌘Z 가 다시는 안 된다.** 옛 SwiftUI `TextEditor` 에도 있던 구조지만 테스트가 못 잡고 있었다.
    /// 고친 뒤 같은 실이벤트 재현: 보내고 비운 뒤의 ⌘Z 는 예외 없이 level 0, 이어 친 "abc" 는 ⌘Z 로 비고 ⇧⌘Z 로 돌아왔다.
    ///
    /// **왜 되쓰기 자체를 되돌릴 수 있게 등록하지 않나**: 그러면 ⌘Z 가 방금 보낸 말이나 **앞사람에게 쓰던 초안**을
    /// 새 상대의 칸에 되살리고, Enter 한 번이면 그대로 나간다 — 스토어가 초안을 비우는 이유 그 자체를 무너뜨린다.
    ///
    /// **왜 `removeAllActions()` 가 아닌가**: 이 관리자는 창의 것이라 같은 팝오버의 다른 입력칸 기록까지 날아간다.
    /// 타이핑 기록은 **텍스트 저장소를 대상으로** 쌓인다(2026-09-11 헤드리스 실측: 텍스트 뷰를 대상으로 지우면
    /// `canUndo` 가 그대로 true, 저장소를 대상으로 지우면 false 가 되고 그 뒤 타이핑·⌘Z·⇧⌘Z 가 정상).
    /// 텍스트 뷰 대상도 함께 지우는 것은, 그런 기록이 생기더라도 같은 범위 오류를 남기지 않게 하려는 것이다.
    /// `breakUndoCoalescing()` 을 먼저 부르는 이유: 다음 타이핑이 지워진 기록에 이어 붙지 않고 새 묶음에서
    /// 시작하게 한다(되쓰기가 스스로 묶음을 끊는지는 AppKit 내부 사정이라 기대지 않는다).
    func replaceTextFromOutside(_ text: String) {
        breakUndoCoalescing()
        if let undoManager {
            if let textStorage { undoManager.removeAllActions(withTarget: textStorage) }
            undoManager.removeAllActions(withTarget: self)
        }
        string = text
        // 되쓴 뒤에는 타이핑 속성이 초기화되므로 다시 얹는다(안 그러면 다음 글자가 기본 폰트로 들어간다).
        font = CheckTextEditor.font
        textColor = NSColor(CheckTheme.primaryText)
        typingAttributes = CheckTextEditor.typingAttributes
    }
}

// MARK: - SwiftUI 래퍼

/// 팝오버 안에서 쓰는 여러 줄 입력칸. 배경·테두리·placeholder 는 **부모가 그린다** —
/// 이 뷰는 자기 배경을 그리지 않는다(다크 화면에 흰 상자가 뚫린다).
///
/// 부모는 이 뷰를 **테두리 상자에 꽉 채워** 놓기만 한다(`.frame(maxWidth: .infinity, maxHeight: .infinity)`).
/// 테두리에서 물러나는 폭(`CheckEditorMetrics.frameInset`)은 **여기서 한 번만** 준다 — 부모마다 따로 주게 두면
/// 한 칸이 잊는 순간 그 칸의 글자만 2pt 어긋나고, 그게 사용자 지시 ③이 생긴 경위 그대로다.
struct CheckTextEditor: View {
    @Binding var text: String
    /// Enter 로 보내는 칸인가. 기본은 false — **새로 쓰는 칸의 기본값은 "Enter 는 줄바꿈"이어야 한다**
    /// (여러 줄 글을 쓰는 칸이 압도적으로 많고, 잘못 보낸 글은 되돌릴 수 없다).
    var sendsOnReturn: Bool = false
    var canSendNow: () -> Bool = { false }
    var onSend: () -> Void = {}

    var body: some View {
        CheckEditorScrollView(text: $text, sendsOnReturn: sendsOnReturn, canSendNow: canSendNow, onSend: onSend)
            // ★ 스크롤 뷰를 테두리 안쪽으로 물린다. 이 줄을 지우면 넘친 글이 빨간 테두리를 덮고,
            //   `textContainerInset` 이 이 폭을 뺀 값이라 글자 자리도 2pt 어긋난다(`CheckEditorMetrics.frameInset`).
            .padding(CheckEditorMetrics.frameInset)
    }

    /// SwiftUI `.font(.caption)` 과 **같은 폰트**(2026-09-11 실측: 둘 다 10pt / 줄 높이 13pt).
    /// placeholder 는 SwiftUI 로 그리고 본문은 AppKit 으로 그리므로, 둘이 다르면 자리도 다시 어긋난다.
    static let font = NSFont.preferredFont(forTextStyle: .caption1)

    /// 새로 치는 글자에 붙는 속성. 되쓴 뒤에도 같은 것을 다시 얹어야 다음 글자가 기본 폰트로 안 들어간다.
    static let typingAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(CheckTheme.primaryText)
    ]
}

/// `CheckTextEditor` 의 AppKit 몸통. 테두리 여백은 바깥 래퍼가 주므로 여기서는 받은 자리를 꽉 채운다.
private struct CheckEditorScrollView: NSViewRepresentable {
    @Binding var text: String
    var sendsOnReturn: Bool
    var canSendNow: () -> Bool
    var onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none

        // TextKit 1 로 만든다(`NSTextView(frame:textContainer:)`). 자리 맞추기의 근거가 되는
        // `lineFragmentPadding`·`textContainerInset` 이 여기서는 정확히 좌표가 된다.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        // ★ 이 0 이 사용자 지시 ③의 절반이다. 기본값 5 는 placeholder 를 아무리 맞춰도 실제 글자만
        //   가로로 5pt 밀어낸다(그리고 그 5 는 어느 숫자에도 안 적혀 있어서 아무도 못 찾는다).
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let textView = CheckEditorTextView(frame: .zero, textContainer: container)
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // 다크 화면이다. 에디터가 자기 배경(흰 판)을 그리면 상자가 뚫린다.
        textView.drawsBackground = false
        // 스크롤 뷰가 이미 `frameInset` 만큼 들어와 있다 — 여기에 `inset` 을 그대로 넣으면 글자가 2pt 더 밀린다.
        textView.textContainerInset = CheckEditorMetrics.textContainerInset
        textView.font = CheckTextEditor.font
        textView.textColor = NSColor(CheckTheme.primaryText)
        textView.insertionPointColor = NSColor(CheckTheme.primaryText)
        textView.typingAttributes = CheckTextEditor.typingAttributes
        textView.allowsUndo = true
        // 서식 없는 글이다. 리치 텍스트를 켜 두면 붙여넣기가 남의 폰트·색을 그대로 들고 들어온다.
        textView.isRichText = false
        textView.importsGraphics = false
        // ⚠︎ 자동 치환은 전부 끈다. 따옴표를 “ ” 로 바꾸는 치환이 붙어 있으면 사용자가 친 글자와
        //   서버로 가는 글자가 달라진다(그리고 그 차이는 아무 화면에도 안 보인다).
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.delegate = context.coordinator

        scroll.documentView = textView
        context.coordinator.textView = textView
        apply(to: textView, coordinator: context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? CheckEditorTextView else { return }
        apply(to: textView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    private func apply(to textView: CheckEditorTextView, coordinator: Coordinator) {
        coordinator.text = $text
        textView.sendsOnReturn = sendsOnReturn
        textView.canSendNow = canSendNow
        textView.onSend = onSend
        // ★ **조합 중에는 절대 되쓰지 마라.** 코드가 `string` 을 다시 넣으면 IME 의 조합 상태가 끊겨
        //   마지막 글자가 씹힌다 — 그 회귀는 헤드리스로 못 잡는다(사람이 한글을 쳐야만 보인다).
        guard !textView.hasMarkedText(), textView.string != text else { return }
        // 되쓰기는 반드시 이 문으로 — 되돌리기 기록을 먼저 지운다(그 함수 주석: 안 지우면 ⌘Z 가 창째로 굳는다).
        textView.replaceTextFromOutside(text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: CheckEditorTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 조합 중인 글자도 그대로 흘린다 — 카운터("N/200")가 지금 화면에 보이는 글자를 세야 한다.
            // 여기서 거르면 조합이 끝나기 전까지 숫자가 멈춰 보인다.
            let value = textView.string
            guard text.wrappedValue != value else { return }
            text.wrappedValue = value
        }
    }
}
