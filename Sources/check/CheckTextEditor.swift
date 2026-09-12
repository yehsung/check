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
//     ⚠︎⚠︎ **그 실측은 틀렸다 — 위 단락은 꺼진 입력기를 잰 것이다**(2026-09-11 재측정, v0.3.11 결함 조사).
//     그날 하네스가 잰 것은 **앱이 비활성인 팝오버**였다. 그 상태에서는 입력 문맥(`NSTextInputContext.current`)이
//     아예 안 켜져서 입력기를 **건너뛴 날것의 자모**가 하나씩 박힌다(bubble-215806.log 15.47~15.79s:
//     `appActive=false currentCtx=false` 에서 "ㅇ" → "ㅇㅏ" → "ㅇㅏㄴ", `marked` 끝까지 false).
//     **앱이 활성인 채 같은 키를 넣으면 같은 입력기가 표시 글자를 쓴다**(bubble-220030.log 46.3~46.6s:
//     `marked=true` 로 "ㅇ" → "아" → "안"). 즉 2벌식 한글은 표시 글자를 **쓴다** — 위 단락의 "안 쓴다"는
//     입력기가 돌지 않았던 상태의 기록이고, 그 상태가 운영자 증상 ①(자음·모음 분리)의 정체다.
//     그래도 이 파일은 **두 전제를 모두 지킨다**(표시 글자가 뜨는 경우와 안 뜨는 경우 둘 다 같은 결과) —
//     입력기는 사용자가 고를 수 있고, 표시 글자를 안 쓰는 입력기도 있다.
//     · 앱이 비활성일 때 문맥이 안 켜지는 문제는 **여는 쪽**에서 막는다(`WindowTopAnchor.presentMenuPopover`
//       의 `activateForKeyboardInput` — 클릭 핸들러 안에서 부르면 14~35ms 안에 활성이 된다는 실측 표가 거기 있다),
//       그리고 이 뷰가 마지막 방어선을 둔다(`activateAppForTypedInputIfNeeded` — **그 묶음은 못 구한다**는
//       한계까지 그 주석에 적어 두었다).
//     · 표시 글자 구간에는 `textDidChange` 가 **오지 않는다**(run5-markedtext.log 4.43~5.47s: 뷰 "ㅇ" / 바인딩 "").
//       그래서 placeholder 는 스토어가 아니라 **뷰에 그려진 것**으로 판정하고(`onRenderedEmptyChange`),
//       전송은 **확정을 먼저**(`commitComposition`) 한다.
//     ★ 판단 자료(2026-09-11, 같은 실입력 하네스에 기록용 평범한 NSTextView 를 세워 입력기가 부르는 것을 받아 적었다):
//     이 입력기는 조합 중 Return 을 받으면 **마지막 음절을 같은 글자로 다시 넣어 조합을 끝내고**
//     (`insertText("요", replacementRange: {4, 1})`) 곧바로 `insertNewline:` 을 부른다. 조합이 없을 때의 Return 은
//     `insertNewline:` 하나뿐이다. 그러니 "조합 중 Enter" 를 가려낼 신호 자체는 있다. 다만 그 신호로 첫 Enter 를
//     "확정만"으로 바꾸면, 한글 문장은 거의 늘 마지막 음절이 조합 중인 채 끝나므로 **모든 메시지가 Enter 두 번**이 된다.
//     그래서 지금 코드는 그 갈래를 `.commitThenSend` 로 쓴다: **확정하고, 그 확정된 문자열을 보낸다**(Enter 한 번).
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

/// 안내 문구(placeholder)를 그리는가 — **순수 판정**(두 입력칸이 같이 쓴다).
///
/// **왜 규칙을 밖으로 뺐나**: 이 판정이 틀리면 사용자는 안내 문구와 자기 글자가 **겹친 화면**을 본다
/// (기모찌 제보 v0.3.11: "칸 안에 있는 '…입력하세요' 안내랑 글자랑 겹침, 초반에"). 겹침은 뷰 안에 숨어
/// 있으면 아무 테스트도 못 보는 종류의 결함이라(스냅샷은 조합 상태를 못 만든다) 값으로 잴 자리가 필요하다.
///
/// **규칙은 하나다: 텍스트 뷰가 말해 준 것이 있으면 그 말만 믿는다.**
///   · 조합 중 — 뷰에는 "안"이 떠 있는데 스토어는 `""` 다(표시 글자 구간에 `textDidChange` 가 안 온다).
///     스토어로 판정하면 안내 문구가 그 "안" 위에 겹친다. 뷰의 말은 "안 비었다"이므로 숨는다.
///   · 전송 직후 — 스토어는 `""` 인데 뷰에는 아직 글자가 남아 있을 수 있다(조합 가드). 이때도 겹친다.
///     같은 이유로 뷰의 말이 이긴다.
///   · 아직 못 들었을 때(nil) — 첫 그림과 **스냅샷 대체 경로**가 그렇다. 그 경로는 텍스트 뷰가 아예 없고
///     그려지는 것이 `Text(스토어 값)` 이므로, 스토어 값이 곧 "그려진 것"이다. 규칙이 갈리지 않는다.
enum CheckEditorPlaceholder {
    static func isVisible(storeText: String, editorRenderedEmpty: Bool?) -> Bool {
        if let editorRenderedEmpty { return editorRenderedEmpty }
        return storeText.isEmpty
    }
}

/// 글을 보내는 **단 하나의 문**(메시지 · 제보가 같이 쓴다).
///
/// **왜 문이 하나여야 하나**(2026-09-11 검토 지적 ②): 조합 확정을 갈래마다 손으로 넣으면 한 갈래가 빠지고,
/// 빠진 갈래는 **마지막 한 글자를 잃는다**(기모찌 제보 v0.3.11 "뒤에 한 글자가 사라져요"). 실제로 그랬다 —
/// 메시지 세 갈래는 확정을 지났는데 제보 [보내기]는 확정 없이 스토어를 읽어, 같은 결함이 한 화면에만 고쳐진
/// 채 남았다. 그래서 확정은 **이 함수 안에 한 번만** 적혀 있고, 두 화면은 각자의 스토어 호출만 넘긴다.
///
/// 순서가 뜻이다: 확정이 먼저다. 확정은 동기라 그 자리에서 `textDidChange` 가 와 바인딩(= 스토어의 초안)이
/// 갱신되고, 그다음 줄의 전송이 **사용자가 화면에서 보던 문장 전체**를 읽는다. 두 줄을 바꾸지 마라.
///
/// 확정할 것이 없으면(대부분의 전송) 아무 일도 안 한다 — 돌려주는 Bool 이 "확정했나"다.
@MainActor
enum CheckEditorSend {
    @discardableResult
    static func commitThenSend(_ send: () -> Void) -> Bool {
        let committed = CheckEditorTextView.commitActiveComposition()
        send()
        return committed
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
        /// 조합을 **먼저 확정하고, 그 확정된 문자열을 보낸다.**
        ///
        /// 규약(사용자 결정 2026-09-11 — 카톡과 같은 동작): **첫 Enter 가 조합 중 마지막 글자까지 보낸다.**
        /// 옛 갈래는 `.commitComposition`(확정만 하고 안 보냄)이었다. 그걸 되돌리면 한글 문장은 거의 늘
        /// 마지막 음절이 조합 중인 채 끝나므로 **모든 메시지가 Enter 두 번**이 된다 — 사용자가 고쳐 달라고
        /// 한 것이 그것이다. 이름을 바꾼 이유: "확정만"과 "확정하고 보낸다"는 사용자가 보는 결과가 정반대라,
        /// 같은 이름을 남기면 다음 사람이 뜻이 바뀐 것을 모르고 옛 주석을 믿는다.
        case commitThenSend
        /// 아무 일도 안 한다(줄바꿈도 아니다).
        case nothing
    }

    /// - Parameters:
    ///   - sendsOnReturn: 이 칸이 Enter 로 보내는 칸인가. **제보 칸은 false 다** — 버그 설명은 여러 줄로
    ///     쓰는 글이라 Enter 전송이 문장을 반토막 낸다(사용자 지시 ②는 "메세지 입력"에 대한 말이었다).
    ///   - hasShift: ⇧ 가 눌렸는가. ⇧↩ 는 언제나 줄바꿈이다.
    ///   - isComposing: 입력기가 표시 글자(marked text)를 띄워 둔 상태인가(`NSTextView.hasMarkedText()`).
    ///     ★ **2벌식 한글에서도 실제로 true 가 된다.** 앱이 활성이라 입력 문맥이 켜져 있으면 이 입력기는
    ///     표시 글자를 쓴다(2026-09-11 실측 bubble-220030.log 46.3~46.6s: `marked=true` 로 "ㅇ"→"아"→"안").
    ///     이 줄에는 한동안 "macOS 2벌식 한글은 표시 글자를 안 쓰므로 늘 false" 라고 적혀 있었는데, 그 실측은
    ///     **입력기가 아예 안 돌던 상태**(앱 비활성 → 문맥 꺼짐)를 잰 것이라 취소됐다(파일 머리 주석).
    ///     그 한 줄만 읽고 아래 `.commitThenSend` 갈래를 **죽은 코드로 오해하지 마라** — 그 오해가
    ///     v0.3.11 제보("뒤에 한 글자가 사라져요")를 만든 잘못된 전제 그 자체다.
    ///     (표시 글자를 정말 안 쓰는 입력기도 있다. 그래서 이 판정은 두 경우 모두에서 같은 결과를 낸다.)
    ///   - canSend: 지금 보낼 수 있는가(`store.canSendMessageNow`).
    static func action(sendsOnReturn: Bool, hasShift: Bool, isComposing: Bool, canSend: Bool) -> Action {
        // 제보 칸: 조합이든 아니든 시스템이 하던 그대로.
        guard sendsOnReturn else { return .newline }
        // ⇧↩ 는 줄바꿈이다. 조합 중이어도 마찬가지 — IME 가 먼저 확정하고 줄이 바뀐다.
        if hasShift { return .newline }
        // ★ 표시 글자가 떠 있으면 **확정을 먼저 하고 그 값을 보낸다.** 확정 없이 보내면 조합 중인 글자가 빠진
        //   문장이 나가고(증상 ③ — run5 40.27s: 뷰 "안녕하세요" / 스토어 "안녕하세" → SEND read="안녕하세"),
        //   확정된 글자는 방금 비운 칸에 홀로 남는다(run8-note.log 24.54s).
        //
        //   ⚠︎ **`canSend` 를 여기서 보지 않는다.** 그 값은 스토어(= 확정된 글자만 든 곳)에서 왔으므로
        //   조합 중에는 한 박자 낡았다 — 한 음절만 써 놓은 상태는 스토어에서 **빈 칸**으로 보여 `canSend` 가
        //   false 다. 여기서 그 값을 믿고 `.nothing` 을 돌려주면 첫 낱말이 영영 안 나간다. 확정한 **뒤에**
        //   부르는 쪽이 다시 묻는다(`CheckEditorTextView.keyDown` 의 `.commitThenSend` 갈래).
        if isComposing { return .commitThenSend }
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
    /// 보내는 문. `store.sendDraftMessage()` 하나로 간다. **조합 확정을 이미 지난 뒤에** 불린다.
    var onSend: () -> Void = {}

    /// 이 칸이 화면에 서면 **커서를 가져올 것인가**(사용자 지시 2026-09-11: "콕찌르기에서 말풍선을 눌러
    /// 1:1 대화로 들어가면 마우스 클릭 없이 바로 타자가 되게").
    ///
    /// 기본값 false 다 — **새 칸이 말없이 포커스를 훔치면 안 된다.** 지금 true 를 주는 자리는 대화 패널의
    /// 입력칸 하나뿐이고(`MessageComposerView`), 그 패널은 사용자가 말풍선을 눌렀을 때만 존재한다.
    /// 제보 칸에는 주지 마라(요청 밖이고, 제보 화면은 목록을 먼저 읽는 화면이다).
    var focusesWhenShown = false

    /// **뷰에 그려진 글자가 비었는가**를 바깥(placeholder)에 알리는 통로. 조합 중 표시 글자도 "그려진 것"이다.
    ///
    /// **왜 바인딩(스토어)으로는 안 되나**(2026-09-11 실측 run5-markedtext.log 4.43~5.47s): 표시 글자 구간에는
    /// `textDidChange` 가 **한 번도 안 온다.** 그래서 뷰에 "안"이 떠 있는데 스토어는 `""` 이고, placeholder 를
    /// `text.isEmpty` 로 숨기면 안내 문구와 글자가 **겹친다**(제보 증상 ②). 반대 방향도 있다: 조합 중 전송이
    /// 스토어를 비우면 `apply()` 의 조합 가드 때문에 뷰에는 옛 문장이 남아, 빈 스토어 + 남은 글자 = 또 겹침
    /// (run8-note.log 23.94s). 두 방향 모두 "뷰에 그려진 것"으로 판정하면 사라진다.
    var onRenderedEmptyChange: ((Bool) -> Void)?

    /// 마지막으로 알린 값. 같은 값을 다시 알리지 않는다(SwiftUI 상태를 매 타자마다 흔들지 않기 위해서다).
    private var lastReportedRenderedEmpty: Bool?

    /// 조합 확정 직후 따라오는 줄바꿈 하나를 삼킬 것인가.
    ///
    /// **왜 필요한가**: 표시 글자를 쓰는 입력기는 조합 중 Return 을 받으면 조합을 확정한 뒤 그 키를
    /// **처리하지 않은 것으로 돌려줄 수 있다**. 그러면 `interpretKeyEvents` 가 이어서 `insertNewline(_:)` 을
    /// 부르고, 사용자는 글자를 확정했을 뿐인데 줄이 하나 생긴다. 그 한 줄을 여기서 삼킨다.
    ///
    /// ★ **창을 한 턴만 연다**(2026-09-11). 옛 구현은 `super.keyDown` 이 도는 **동기 구간만** 열어 놓았는데,
    ///   입력기가 확정을 비동기로 끝내면 그 뒤에 오는 `insertNewline` 이 창이 닫힌 다음에 도착해 줄바꿈이
    ///   그대로 새어 들어갔다(run10-enter.log 7.29s: 뷰가 "하이요\n" 이 됐다). 반대로 영구히 열어 두면
    ///   사용자가 일부러 누른 ⇧↩ 의 줄바꿈까지 먹는다 — 그래서 **한 턴**이다.
    private var swallowsNextNewline = false

    /// 지금 포커스를 쥔 입력칸(약참조). **전송 문이 "확정할 대상"을 찾는 유일한 통로다.**
    ///
    /// 왜 필요한가: [보내기] 버튼과 ⌘↩ 은 **키 이벤트가 이 뷰로 오지 않는다**(버튼의 동작 클로저와 SwiftUI
    /// 단축키다). 그래서 그 두 갈래는 자기 손으로 조합을 확정할 수 없고, 확정 없이 보내면 스토어에 아직
    /// 없는 마지막 음절이 빠진 문장이 나간다(증상 ③ — run8-note.log 23.94s: `SEND read="안녕하세"`).
    /// 약참조인 이유는 창과 같다 — 수명은 SwiftUI/AppKit 이 쥔다.
    private(set) static weak var focusedEditor: CheckEditorTextView?

    override func keyDown(with event: NSEvent) {
        // ★ 키가 여기까지 왔다 = **사용자가 이 칸에 타이핑하고 있다**(로컬 키 이벤트는 우리 앱 창에만 온다).
        //   그런데 앱이 비활성이면 입력 문맥이 안 켜져 한글이 자모로 쪼개져 박힌다
        //   (증상 ① — 실측은 `activateAppForTypedInputIfNeeded` 주석). 그 상태를 여기서 되살린다.
        //   여는 쪽(`presentMenuPopover`)이 이미 막지만, 이 줄은 **굳지 않게 하는 마지막 방어선**이다:
        //   최악의 경우 앞 글자 몇 개만 날것으로 들어가고 그다음부터 정상 조합된다.
        activateAppForTypedInputIfNeeded()
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
        case .commitThenSend:
            // ★ **확정을 우리가 한다** — 입력기에 Return 을 넘기지 않는다.
            //   넘기면 입력기가 확정을 **비동기로** 끝낼 수 있어, 바로 뒤에서 부르는 전송이 확정 전 값을 읽고
            //   (증상 ③) 확정 뒤에 오는 줄바꿈이 동기 창을 지나 새어 들어간다(run10-enter.log 7.29s).
            //   확정을 우리가 하면 그 순간 바인딩까지 올라오므로(`commitComposition`), 아래 한 줄이 읽는 값이
            //   **사용자가 화면에서 보던 문장 전체**가 된다.
            commitComposition()
            // 그래도 입력기가 줄바꿈을 뒤늦게 부를 수 있다 — 한 턴만 삼킨다(그 깃발의 주석 참고).
            swallowNewlineForOneTurn()
            // ★ 확정한 **뒤에** 다시 묻는다. 확정 전의 `canSend` 는 낡았다 — 조합 중인 한 음절만 써 놓은
            //   상태는 스토어에서 빈 칸으로 보여 false 다(그 값을 믿으면 첫 낱말이 영영 안 나간다).
            //   반대로 넘친 글(200자 초과)·상대 없음·전송 중은 확정 뒤에도 false 이므로 그대로 막힌다.
            if canSendNow() { onSend() }
        case .send:
            onSend()
        case .nothing:
            break
        }
    }

    override func insertNewline(_ sender: Any?) {
        // 하나만 삼킨다. 깃발을 여기서 내리지 않으면 같은 턴에 두 번째 줄바꿈까지 먹는다.
        if swallowsNextNewline {
            swallowsNextNewline = false
            return
        }
        super.insertNewline(sender)
    }

    /// 줄바꿈 삼키기 창을 **한 런루프 턴** 동안 연다. 왜 한 턴인지는 `swallowsNextNewline` 주석에 있다.
    private func swallowNewlineForOneTurn() {
        swallowsNextNewline = true
        Self.onNextRunLoopTurn { [weak self] in
            MainActor.assumeIsolated { self?.swallowsNextNewline = false }
        }
    }

    /// 다음 런루프 턴에 한 번 실행한다.
    ///
    /// ★ **`DispatchQueue.main.async` 를 쓰지 마라**(2026-09-11 실측). 이 저장소의 테스트는 NSApplication 없이
    ///   `RunLoop.current.run(until:)` 로 시간을 돌리는데, 그 런루프는 **메인 디스패치 큐를 흘리지 않는다**
    ///   (진단: `DispatchQueue.main.async { ran = true }` 뒤 0.1초를 돌려도 `ran == false`). 그래서 디스패치로
    ///   미룬 일은 앱에서는 돌고 테스트에서는 안 돌아 — **검증이 못 보는 코드**가 된다. 런루프 예약은 둘 다 돈다.
    ///
    /// `.common` 모드인 이유: 팝오버·메뉴가 떠 있는 동안 앱의 런루프는 이벤트 추적 모드로 돈다. 기본 모드만
    /// 넣으면 그 순간의 예약이 팝오버가 닫힐 때까지 잠든다 — 포커스를 잡는 일이 바로 그 순간에 일어난다.
    static func onNextRunLoopTurn(_ work: @escaping @Sendable () -> Void) {
        RunLoop.main.perform(inModes: [.common]) { work() }
    }

    // MARK: - 조합(표시 글자) 확정 — 전송 세 갈래가 모두 먼저 지나는 문

    /// 지금 포커스를 쥔 입력칸의 조합을 확정한다. **[보내기] 버튼과 ⌘↩ 이 부르는 문**(그 둘은 키 이벤트가
    /// 이 뷰로 오지 않아 자기 손으로 확정할 수 없다 — `focusedEditor` 주석).
    ///
    /// 돌려주는 값은 "확정할 것이 있었나"다. 없었으면 false — 그 경우가 대부분이고 아무 일도 안 한다.
    @discardableResult
    static func commitActiveComposition() -> Bool {
        guard let editor = focusedEditor else { return false }
        return editor.commitComposition()
    }

    /// 조합(표시 글자)을 **화면에 보이는 그대로** 확정한다. 확정된 글자는 그 자리에서 바인딩까지 올라간다.
    ///
    /// **왜 이 문이 있어야 하나**(2026-09-11 실측): 표시 글자 구간에는 `textDidChange` 가 오지 않아 스토어가
    /// 한 음절 뒤처진다(run5-markedtext.log: 뷰 "ㅇ" / draft ""). 그 상태로 보내면
    ///   · 마지막 음절이 빠진 문장이 나가고(run5 40.27s · run8 23.94s: `SEND read="안녕하세"`),
    ///   · 확정된 글자는 방금 비운 칸에 옛 문장 전체와 함께 되살아난다(run8 24.54s: `draft="안녕하세요"`).
    ///
    /// **순서가 뜻이다.**
    ///   ① `discardMarkedText()` — 입력기에게 조합 세션을 끝내라고 알린다. 이 줄이 없으면 입력기는 방금
    ///      확정한 음절을 **자기 버퍼에 계속 들고 있어**, 다음에 친 글자가 그 음절에 다시 붙거나 같은 음절이
    ///      한 번 더 들어간다(옛 메신저들이 겪은 "요 가 두 번 나오는" 사고).
    ///   ② 그래도 표시가 남아 있으면 클라이언트 쪽에서 거둔다(`unmarkText()` — run6-unmark.log 5.03s 에서
    ///      문자열을 그대로 두고 확정되는 것을 확인했다).
    ///   ③ `didChangeText()` — 확정으로 늘어난 글자를 바인딩으로 올린다. ①②가 알림을 보장하지 않으므로
    ///      여기서 한 번 더 못 박는다(델리게이트가 같은 값이면 스스로 접는다).
    @discardableResult
    func commitComposition() -> Bool {
        guard hasMarkedText() else { return false }
        inputContext?.discardMarkedText()
        if hasMarkedText() { unmarkText() }
        didChangeText()
        return true
    }

    // MARK: - 입력 문맥(IME)을 켜 두기 — 증상 ①

    /// 이 칸에 키가 들어왔는데 **앱이 비활성**이면 앱을 활성화한다 — 증상 ①이 **굳지 않게** 하는 마지막 방어선.
    ///
    /// ⚠︎ **이 줄은 "고치는" 줄이 아니다. 바닥일 뿐이다**(2026-09-11 실측으로 한계를 확인했다).
    ///   키가 들어온 뒤의 활성화는 **그 묶음을 구하지 못한다**: 비활성으로 시작한 묶음에서 첫 타가
    ///   활성화를 불러 31ms 뒤 앱이 활성이 됐는데도, 이어진 2·3타까지 조합되지 않고 날것으로 들어갔다
    ///   (bubble-215806.log 15.47~15.79s: `currentCtx=true` 인데 "ㅇㅏ" → "ㅇㅏㄴ"). 입력기 쪽 세션이
    ///   그 묶음 동안은 돌아오지 않는다. 그래서 **진짜 수리는 팝오버가 서는 순간에 활성화를 끝내는 것**이고
    ///   (`WindowTopAnchor.activateForKeyboardInput` — 클릭 핸들러 안에서 **14~35ms** 안에 완료된다.
    ///   유휴 상태 7회 재측정이고, 7/7 첫 타자부터 정상 조합이었다. 처음 이 자리에 적혔던 `6ms` 는 한 번의
    ///   관측이었다 — 그 숫자로 여유를 계산하지 마라. **부하에서는 좁아진다**: 활성화 완료는 메인 런루프가
    ///   돌려주는 비동기 통지라 앱이 바쁘면 늦게 온다),
    ///   이 줄은 그 경로를 지나지 않고 비활성 상태에 빠진 경우가 **영구히 굳지 않게** 하는 것뿐이다.
    ///   ⚠︎ 뒤집어 말하면 **저 여유가 사실상 유일한 방어선**이다 — 아래 실측대로 이 `keyDown` 방어선은
    ///   한 번 꺼진 채 시작한 묶음을 **못 구한다.** 여유가 좁아지는 만큼 첫 묶음이 자모로 박힐 위험이 남는다.
    ///
    /// **왜**(2026-09-11 실측): 입력 문맥(`NSTextInputContext.current`)은 **앱이 활성일 때만** 켜진다.
    /// 메뉴바 팝오버 창은 `nonactivatingPanel`(측정 styleMask 0x8080)이라 **앱이 비활성인 채 키를 받는다** —
    /// 그 상태에서 한글을 치면 입력기를 건너뛴 날것의 자모가 하나씩 박힌다(bubble-215806.log 15.47~15.79s
    /// `appActive=false currentCtx=false` 에서 "ㅇ" → "ㅇㅏ" → "ㅇㅏㄴ"; 같은 하네스에서 활성인 채 친 묶음은
    /// `marked=true` 로 "ㅇ" → "아" → "안" 이었다 — bubble-220030.log 46.3~46.6s).
    /// 문맥은 스스로 켜지지 않는다 — `inputContext.activate()` 를 직접 불러도 안 켜졌다(run7-ctx.log 11.50s).
    /// 그래서 한 번 빠지면 팝오버를 닫고 상태바 아이콘을 진짜로 눌러 다시 열 때까지 **굳는다** — 운영자 증상 ①의
    /// "아예 팝오버 창을 닫았다가 다시 돌아오면 정상 동작"이 그것이다.
    ///
    /// **키를 버리거나 미루지 않는 이유**(검토 지적 ③의 두 번째 선택지): 위 실측대로 활성화 뒤에도 그 묶음은
    /// 조합되지 않으므로, 버리든 미루든 "자모가 안 박힌다"를 **보장하지 못한다**(미뤄서 다시 흘려도 그 묶음의
    /// 입력기는 꺼진 채다). 보장되는 것은 하나뿐이다 — 그 자리에서 키를 버리면 사용자가 친 글자가 **사라진다.**
    /// 그래서 확실한 손해와 불확실한 이득을 맞바꾸지 않고, 활성화를 **여는 순간으로** 옮기는 쪽으로 고쳤다.
    ///
    /// **가드는 "앱이 비활성인가" 하나다.** 창이 key 인지 묻지 않는다 — 2026-09-11 실측에서 그 고착 상태는
    /// `keyWin=none`(어느 창도 key 가 아니다)이었는데도 키는 이 칸으로 들어왔다. `isKeyWindow` 를 요구했더니
    /// 방어선이 정확히 필요한 그 순간에 침묵했다(같은 로그 12.9s: 자모가 그대로 박혔다).
    /// **포커스를 훔칠 위험은 없다**: 로컬 키 이벤트는 우리 앱의 창에만 온다 — 여기 도달했다는 것은
    /// 사용자가 **우리 칸에** 타이핑하고 있다는 뜻이고, 그러면 앱이 활성이어야 맞다.
    /// (그래서 `becomeFirstResponder` 에서는 부르지 않는다 — 그 자리는 "키가 왔다"는 증거가 없어서
    ///  코드가 포커스를 옮기기만 해도 다른 앱의 앞자리를 빼앗게 된다.)
    ///
    /// `NSApp` 을 `if let` 으로 받는 이유는 `WindowTopAnchor.statusItemButton()` 주석과 같다 — 헤드리스
    /// 테스트 프로세스에서는 nil 이고, `NSApplication.shared` 로 받으면 그 접근이 앱 객체를 **만든다.**
    func activateAppForTypedInputIfNeeded() {
        guard let app: NSApplication = NSApp, !app.isActive else { return }
        app.activate()
    }

    // MARK: - 포커스 (사용자 지시 2026-09-11 ④)

    /// 커서를 가져갈 것인가 — **순수 판정**(헤드리스 검증 지점).
    ///
    /// 세 조건이 모두 참일 때만 잡는다: ① 이 칸이 잡으라고 지정된 칸이다, ② 창에 올라와 있다(= 화면에
    /// 서 있는 패널의 일부다), ③ 아직 내가 첫 응답자가 아니다. ③이 없으면 SwiftUI 재평가마다 첫 응답자를
    /// 다시 세워 조합이 끊긴다(초당 시계·15초 폴링이 이 트리를 지난다).
    nonisolated static func claimsFocus(focusesWhenShown: Bool, hasWindow: Bool, alreadyFirstResponder: Bool) -> Bool {
        focusesWhenShown && hasWindow && !alreadyFirstResponder
    }

    /// 창에 붙거나 떼어질 때 불린다. **붙는 순간이 "대화 패널이 화면에 섰다"는 뜻**이고, [뒤로]로 나갔다
    /// 다시 들어오면 뷰가 새로 만들어지므로(`CheckMenuView` 의 `if store.isMessagePanelVisible`) 여기가 다시 온다.
    ///
    /// **다음 런루프 턴에 잡는다**: 이 시점에는 SwiftUI 가 아직 계층을 붙이는 중이고 창의 첫 응답자도 그 뒤에
    /// 한 번 더 정리된다 — 지금 잡으면 그 정리에 밀려 사라진다.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusesWhenShown, window != nil else { return }
        Self.onNextRunLoopTurn { [weak self] in
            MainActor.assumeIsolated { self?.claimFocusIfNeeded() }
        }
    }

    /// 위 순수 판정을 실제로 실행한다.
    func claimFocusIfNeeded() {
        guard let window else { return }
        guard Self.claimsFocus(
            focusesWhenShown: focusesWhenShown,
            hasWindow: true,
            alreadyFirstResponder: window.firstResponder === self
        ) else { return }
        window.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        guard accepted else { return false }
        // 전송 문이 조합을 확정할 대상. **여기 말고 다른 데서 대입하지 마라** — 두 곳이 되면 방금 닫힌 칸을
        // 가리킨 채 남는 창이 생기고, 그러면 전송이 엉뚱한 칸의 조합을 확정한다.
        Self.focusedEditor = self
        // ★ **여기서 앱을 활성화하지 않는다.** 이 자리에는 "사용자가 우리에게 타이핑하고 있다"는 증거가 없다 —
        //   코드가 포커스를 옮기기만 해도(대화 패널 진입) 다른 앱의 앞자리를 빼앗게 된다.
        //   문맥을 되살리는 일은 키가 실제로 들어오는 자리에서만 한다(`keyDown`).
        return true
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        // 내가 쥐고 있었을 때만 자리를 비운다(새 칸이 먼저 잡고 옛 칸의 resign 이 뒤늦게 오는 순서가 있다 —
        // `WindowTopAnchor.detach` 가 같은 이유로 같은 모양을 쓴다).
        if resigned, Self.focusedEditor === self { Self.focusedEditor = nil }
        return resigned
    }

    // MARK: - "그려진 것이 비었나" 알리기 — 증상 ②

    /// 뷰에 그려진 글자가 비었는가. **조합 중 표시 글자도 그려진 것이다** — 표시 글자는 `string` 에 이미
    /// 들어 있으므로(`markedRange` 는 그 안의 구간이다) 이 한 줄이 곧 "화면에 아무것도 없나"다.
    var renderedTextIsEmpty: Bool { string.isEmpty }

    /// 값이 **바뀌었을 때만** 알린다. 매 타자마다 같은 false 를 알리면 SwiftUI 상태가 그만큼 흔들린다.
    func reportRenderedEmptinessIfChanged() {
        let value = renderedTextIsEmpty
        guard lastReportedRenderedEmpty != value else { return }
        lastReportedRenderedEmpty = value
        onRenderedEmptyChange?(value)
    }

    /// 입력기가 표시 글자를 세우거나 갈아 끼울 때. **이 자리가 없으면 조합 중 안내 문구가 글자와 겹친다**
    /// (`textDidChange` 는 이 구간에 오지 않는다 — run5-markedtext.log).
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        reportRenderedEmptinessIfChanged()
    }

    /// 조합이 확정 없이 끝나는 경로(입력기 취소 · 우리 `commitComposition` 의 ②).
    override func unmarkText() {
        super.unmarkText()
        reportRenderedEmptinessIfChanged()
    }

    /// 글이 실제로 바뀌는 모든 경로(타이핑 확정 · 붙여넣기 · 지우기 · 되돌리기)가 여기를 지난다.
    override func didChangeText() {
        super.didChangeText()
        reportRenderedEmptinessIfChanged()
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
        // `string =` 은 `didChangeText()` 를 부르지 않는다 — 그래서 여기서 직접 알린다. 안 알리면
        // 스토어가 칸을 비운 뒤에도 placeholder 가 안 돌아오고(뷰는 비었는데 마지막 보고가 "안 비었다"),
        // 반대로 바깥이 글을 넣어 준 칸에는 안내 문구가 글자 위에 남는다.
        reportRenderedEmptinessIfChanged()
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
    /// **반납되어 대기 중인** 입력칸. 위 `makeNSView` 주석이 이 프로퍼티의 존재 이유다 — 새로 만든 칸은
    /// 한글 입력기 세션을 못 받아 자모가 하나씩 박힌다.
    ///
    /// ★ **쥐고 있는 칸은 여기 없다.** `makeNSView` 가 꺼내 갈 때 nil 로 비우고, `dismantleNSView`(패널이
    ///   내려갈 때)가 되돌려 놓는다. 그래서 **두 곳이 같은 칸을 동시에 쥘 수 없다** — 한 벌을 그냥 공유하게
    ///   두었더니 병렬 렌더 테스트들이 같은 칸을 나눠 쓰며 서로의 글자를 봤다(2026-09-12 전체 스위트에서
    ///   `footerButtonsAreRealButtonsNotMenus` · `theMountedMessageEditorIgnoresEnterWhenTheStoreCannotSend` ·
    ///   `todoSwitch…` 셋이 동시에 빨개졌고, 재사용을 끄면 셋 다 초록이었다).
    ///   대기 칸이 비어 있으면 새로 만든다 — 동시에 여러 칸이 필요한 경우(테스트)에도 안전하다.
    ///
    /// `nonisolated(unsafe)`: SwiftUI 의 make/dismantle 는 메인에서만 불린다.
    nonisolated(unsafe) fileprivate static var pooledScroll: NSScrollView?

    /// 테스트 전용. 앱이 쓰는 재사용 규칙(`CheckEditorScrollView.reusableScrollIfAvailable`)을 그대로 되묻는다.
    @MainActor
    static func reusableScrollForTesting() -> NSScrollView? { CheckEditorScrollView.takePooledScroll()?.scroll }

    /// 테스트 전용. 재사용 칸을 세우거나 비운다(테스트끼리 상태를 물려주면 순서에 따라 결과가 갈린다).
    @MainActor
    static func setReusableScrollForTesting(_ scroll: NSScrollView?) { pooledScroll = scroll }

    @Binding var text: String
    /// Enter 로 보내는 칸인가. 기본은 false — **새로 쓰는 칸의 기본값은 "Enter 는 줄바꿈"이어야 한다**
    /// (여러 줄 글을 쓰는 칸이 압도적으로 많고, 잘못 보낸 글은 되돌릴 수 없다).
    var sendsOnReturn: Bool = false
    /// 이 칸이 화면에 서면 커서를 가져올 것인가. 기본은 false — `CheckEditorTextView.focusesWhenShown` 주석.
    var focusesWhenShown: Bool = false
    var canSendNow: () -> Bool = { false }
    var onSend: () -> Void = {}
    /// 뷰에 그려진 글자(조합 중 표시 글자 포함)가 비었는지 알려 준다. placeholder 를 숨기는 판정의 재료다 —
    /// `CheckEditorTextView.onRenderedEmptyChange` 주석에 "왜 스토어 값으로는 안 되는가"가 있다.
    var onRenderedEmptyChange: ((Bool) -> Void)?

    var body: some View {
        CheckEditorScrollView(
            text: $text,
            sendsOnReturn: sendsOnReturn,
            focusesWhenShown: focusesWhenShown,
            canSendNow: canSendNow,
            onSend: onSend,
            onRenderedEmptyChange: onRenderedEmptyChange
        )
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
    var focusesWhenShown: Bool
    var canSendNow: () -> Bool
    var onSend: () -> Void
    var onRenderedEmptyChange: ((Bool) -> Void)?

    /// 재사용할 수 있는 입력칸이 있으면 돌려준다. **판정 규칙은 여기 한 곳에만 있다** —
    /// 테스트가 `Context` 없이 이 규칙을 되묻는다(SwiftUI 의 Context 는 테스트에서 만들 수 없다).
    /// 붙어 있는(superview != nil) 칸은 재사용하지 않는다 — 한 뷰는 두 곳에 못 붙는다.
    @MainActor
    static func takePooledScroll() -> (scroll: NSScrollView, text: CheckEditorTextView)? {
        guard let cached = CheckTextEditor.pooledScroll, cached.superview == nil,
              let text = cached.documentView as? CheckEditorTextView else { return nil }
        CheckTextEditor.pooledScroll = nil   // ★ 꺼내 갔으면 대기열에서 뺀다(두 곳이 같이 쥐지 못하게)
        return (cached, text)
    }

    /// 패널이 내려갈 때 SwiftUI 가 부른다. 쓰던 칸을 **대기열에 되돌려** 다음 마운트가 같은 칸을 쓰게 한다.
    /// 이 문이 없으면 대기열이 영영 비어 있어 매번 새 칸이 만들어지고, 한글 조합이 다시 죽는다.
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        nsView.removeFromSuperview()
        if let text = nsView.documentView as? CheckEditorTextView {
            text.delegate = nil
            // 다음 사람이 옛 글을 물려받지 않게 비운다(내용은 `updateNSView` 가 다시 채운다).
            text.string = ""
        }
        CheckTextEditor.pooledScroll = nsView
    }

    func makeNSView(context: Context) -> NSScrollView {
        // ★ **입력칸을 다시 만들지 않고 같은 것을 계속 쓴다**(2026-09-12, v0.3.13).
        //   **이 재사용을 걷어내지 마라.** 한글 자모가 하나씩 박히던 결함(제보 ①, v0.3.0~v0.3.12)의 뿌리다.
        //
        //   무슨 일이 있었나: 대화 상대를 바꾸면 패널이 내려갔다 다시 서면서 SwiftUI 가 이 칸을 **새로 만든다.**
        //   그런데 **새로 만들어진 NSTextView 는 한글 입력기 세션을 받지 못한다.** 첫 응답자도 제대로 되고
        //   입력 문맥도 제 것인데(실측 `fr=true`, `inputContext === NSTextInputContext.current`) 조합만
        //   시작을 안 한다. 그 상태의 서명은 `insertText` 의 교체 범위다:
        //     · 정상 — `insertText("두", replacementRange: {0,1})` = 앞 글자를 **교체**한다(2벌식 조합).
        //     · 고장 — `insertText("ㅜ", replacementRange: {대상없음,0})` = 그냥 **붙인다** → 자모가 하나씩 쌓인다.
        //
        //   ⚠︎ `hasMarkedText()` 로는 이 고장을 **못 잰다.** 이 입력기는 정상일 때도 표시 글자를 쓰지 않아
        //   89키 전부 false 였다(2026-09-12 실측). 그 오독이 v0.3.12 의 오진("앱이 비활성이라 입력기가
        //   안 켜진다")으로 이어졌고, 그 수정은 증상을 못 고쳤다.
        //
        //   되살리려는 시도는 전부 **실측으로 기각**됐다(같은 날, 운영자 맥에서 재현하며):
        //     ① 팝오버가 설 때 앱 활성화 — `NSApp.isActive == true` 인데도 깨졌다.
        //     ② 첫 응답자가 되는 순간 문맥 재바인딩(`updateWindows()` + `inputContext.activate()`) — 깨졌다.
        //     ③ 옛 칸이 `deinit` 된 **뒤** 다시 재바인딩 — 그래도 깨졌다.
        //     ④ 바깥이 글을 되쓰는 경로(`replaceTextFromOutside`) 의심 — 그 구간에 **한 번도 안 불렸다.**
        //   즉 문맥·활성·되쓰기 어느 쪽도 아니고, 남은 사실은 "새 뷰는 조합을 못 받는다" 하나였다.
        //   그래서 세션을 되살리려 싸우는 대신 **뷰를 갈지 않는다.** 12회 연속 상대 교체에서 고장 0건.
        //
        //   왜 한 벌로 충분한가: 이 칸을 쓰는 두 패널(대화·제보)은 `CheckMenuView` 의 `if / else if` 로
        //   **서로 배타**라 동시에 서지 않는다. 그래도 혹시 둘이 겹치면(한 뷰는 두 곳에 못 붙는다)
        //   `superview != nil` 로 걸러 그때만 새로 만든다.
        if let cached = Self.takePooledScroll() {
            // 대리자·바인딩은 이번 마운트의 것으로 갈아 끼운다(칸의 내용물은 `updateNSView` 가 맞춘다).
            cached.text.delegate = context.coordinator
            context.coordinator.textView = cached.text
            apply(to: cached.text, coordinator: context.coordinator)
            return cached.scroll
        }
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
        textView.focusesWhenShown = focusesWhenShown
        textView.canSendNow = canSendNow
        textView.onSend = onSend
        textView.onRenderedEmptyChange = onRenderedEmptyChange
        // 첫 보고는 **다음 턴**에 넘긴다. 이 함수는 `updateNSView` 안에서도 불리므로 여기서 바로 알리면
        // SwiftUI 가 뷰를 그리는 중에 부모의 상태를 바꾸게 된다(경고 + 재평가 되돌이).
        // 조합·타이핑 경로의 보고는 이벤트 처리 중에 오므로 그쪽은 바로 알려도 된다.
        Self.reportSoon(textView)
        // ★ **조합 중에는 절대 되쓰지 마라.** 코드가 `string` 을 다시 넣으면 IME 의 조합 상태가 끊겨
        //   마지막 글자가 씹힌다 — 그 회귀는 헤드리스로 못 잡는다(사람이 한글을 쳐야만 보인다).
        //
        // ⚠︎ **"바깥이 비웠을 때만 예외로 되쓴다"를 넣지 마라 — 2026-09-11 에 넣어 봤고 해로웠다.**
        //   조합 중에는 스토어가 한 음절 뒤처지므로(표시 글자 구간에 `textDidChange` 가 안 온다)
        //   `text.isEmpty` 는 "바깥이 비웠다"와 "아직 안 올라왔다"를 **구별하지 못한다.** 실측 결과:
        //   첫 음절을 치는 순간 그 예외가 발화해 조합이 즉시 확정됐다(V0311 테스트가 그 값을 잡았다) —
        //   사용자에게는 증상 ①(자모가 하나씩 들어감)과 같은 화면이다.
        //   run8-note.log 24.54s 의 "비운 칸에 옛 문장이 되돌아온다"는 **전송이 조합을 먼저 확정하는 것**으로
        //   막는다(`MessageComposerView.send()`), 여기서 되쓰는 것으로 막지 않는다.
        guard !textView.hasMarkedText(), textView.string != text else { return }
        // 되쓰기는 반드시 이 문으로 — 되돌리기 기록을 먼저 지운다(그 함수 주석: 안 지우면 ⌘Z 가 창째로 굳는다).
        textView.replaceTextFromOutside(text)
    }

    /// 첫 "그려진 것" 보고를 다음 턴으로 미룬다(왜 디스패치가 아닌지는 `onNextRunLoopTurn` 주석).
    private static func reportSoon(_ textView: CheckEditorTextView) {
        CheckEditorTextView.onNextRunLoopTurn {
            MainActor.assumeIsolated { textView.reportRenderedEmptinessIfChanged() }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: CheckEditorTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // 뷰에 있는 것을 그대로 흘린다(거르지 않는다).
            //
            // ⚠︎ **다만 이 알림은 조합 중에 오지 않는다**(2026-09-11 실측 run5-markedtext.log 4.43~5.47s:
            //   표시 글자 구간에 `NSText.didChange` 가 한 줄도 없다). 그래서 스토어는 **확정된 글자만** 든다.
            //   그 사실에서 두 가지가 따라온다 — 잊으면 증상 ②③이 되살아난다:
            //     · placeholder 는 스토어가 아니라 **뷰에 그려진 것**으로 판정한다(`onRenderedEmptyChange`).
            //     · 전송은 **확정을 먼저** 한다(`commitComposition`) — 그래야 이 알림이 와서 값이 올라온다.
            //   글자 수 카운터("N/200")도 같은 이유로 조합 중인 한 음절만큼 뒤처진다. 그건 고치지 않는다:
            //   스토어에 조합 중 글자를 밀어 넣으면 `canSendMessageNow` 가 확정 전에 참이 되어, 버튼 경로가
            //   **확정되지 않은 글**을 보낼 수 있게 된다(증상 ③을 반대 방향으로 되살리는 짓이다).
            let value = textView.string
            guard text.wrappedValue != value else { return }
            text.wrappedValue = value
        }
    }
}
