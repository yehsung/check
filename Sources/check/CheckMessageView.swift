import SwiftUI
import CheckCore

// MARK: - 1:1 대화 패널 (v0.2.50)
//
// 사용자 지시(2026-09-10): "각 사람의 메시지 버튼을 누르면 해당 창 안에서 그 사람과의 1대1 메시지 화면으로만
// 넘어가고, 거기서 그 사람이랑만 대화하게끔. 지금처럼 별도 창에서 나랑 대화하던 사람들이 왼쪽에 다 뜨는
// 방식이 아니라." — 확인 질문의 답은 **"팝오버 안에서 전환"**(창이 하나도 안 뜨는 쪽)이었다.
//
// 그 한 문단이 이 파일에서 지운 것과 남긴 것을 전부 정한다.
//
// ── 지운 것 ──
//   · **왼쪽 대화 상대 목록**(MessageThreadListView·MessageThreadRow). 이 화면은 한 사람짜리다. 다른 사람과
//     얘기하려면 [뒤로] → 콕찌르기 목록에서 그 사람을 다시 누른다. 그것이 사용자가 그린 길이다.
//   · **별도 창**(CheckMessageWindow.swift). 창 계층·최소 크기·자동저장 이름·고착 감시자가 통째로 사라졌다.
//   · **[새로고침] 버튼.** 이력은 패널을 열 때·전송 성공·수신 도착에 받는다(WorkTimerStoreMessages 규약).
//
// ── 남긴 것 ──
//   · 말풍선은 **시간순**(오래된 것 위 → 최신 아래). 받은 것은 왼쪽, 보낸 것은 오른쪽(`is_mine`).
//   · 날짜가 바뀌는 자리에 **구분선**. 그 판정은 뷰가 아니라 `MessageThreadBuilder.timeline` 이 한다.
//   · 처음 열면 **맨 아래(최신)**.
//   · **Enter 로 보낸다**(v0.2.51 — 사용자 지시 2026-09-11 ②). 줄바꿈은 ⇧Enter, ⌘Enter 도 계속 통한다.
//     판정은 `CheckEditorReturnKey` 하나가 한다. **첫 Enter 가 조합 중이던 마지막 글자까지 보낸다**(사용자 결정
//     2026-09-11 — 카톡과 같은 동작). 표시 글자가 떠 있으면 `.commitThenSend` 로 **확정을 먼저 하고** 그 확정된
//     문자열을 보낸다: 확정 없이 보내면 마지막 한 글자가 빠진다(기모찌 제보 v0.3.11 "뒤에 한 글자가 사라져요" —
//     실측은 CheckTextEditor.swift 머리 주석). 세 갈래(버튼·⌘↩·↩)가 전부 `MessageComposerView.send()` 하나를
//     지나야 그 확정이 어느 갈래에서도 빠지지 않는다.
//     **"Enter 는 줄바꿈"으로 되돌리지 마라**: 그건 사용자가 직접 고쳐 달라고 한 것이다.
//   · `MessageThreadBuilder` 의 묶기·타임라인·날짜 구분선 계산은 **그대로 재사용한다** — 목록 UI 가
//     사라졌을 뿐, peer 별로 묶는 일은 "그 사람 것만 골라 그린다"에 여전히 필요하다.
//
// ★ 이 파일이 그리는 문자열은 **두 사람이 주고받은 문장**이다. 어떤 경로로도 로그·진단 문자열로 흘리지 마라.
//
// ── 초 단위 무효화 금지 ──
// 이 패널은 `store.displayNow` 를 **읽지 않는다.** 날짜 라벨("오늘"/"어제")에 필요한 시각은 주입 인자
// `now`(기본값 `Date()`)로 받는다 — 관찰 대상이 아니라 body 가 돌 때 한 번 읽히는 값이라, 팝오버 루트가
// 매초 다시 그려지지 않는다(V0238MenuTests 가 그 무관찰을 못 박는다). 자정 경계에서 라벨이 한 박자 늦게
// 바뀌는 것은 감수한다: 그 대가가 트리 전체의 초당 재평가다.
//
// ── ImageRenderer 눈가리개(렌더 테스트 전용 대체 경로) ──
// `ImageRenderer` 는 ScrollView 안쪽과 `TextEditor` 를 못 그린다(제보 창이 겪은 함정, 그전엔 `Menu` 가
// 노란 상자로 나왔다). 그대로 두면 스냅샷이 머리만 남은 빈 화면이 되어 "잘림·겹침을 눈으로 본다"는
// 렌더 테스트의 목적이 통째로 사라진다. 그래서 **렌더 테스트만** 같은 자리·같은 치수의 순수 SwiftUI
// 대체 경로를 쓴다. **앱은 언제나 진짜 위젯이다**(두 스위치의 기본값이 false 이고 프로덕션에 true 를 주는 자리는 없다).

/// 대화 패널의 치수. **한 곳에서만 온다** — 뷰마다 숫자를 적으면 창 높이 상한 예산과 조용히 어긋나고,
/// 그 어긋남은 배너가 뜬 날에만 드러난다(테스트는 배너 없는 화면을 그려서 못 잡는다).
enum MessagePanelLayout {
    /// 패널 안쪽 폭(pt) = 본문 열 316 − 카드 padding 12×2. 이 저장소의 모든 패널이 쓰는 같은 값이다.
    static let contentWidth: CGFloat = 292

    /// 말풍선 **반대쪽에 반드시 남기는 여백**(pt). 말풍선 폭을 이걸로 제한하는 것이 요점이다.
    ///
    /// ★ `.frame(maxWidth:)` 를 쓰면 안 된다(2026-09-10 실측). 그 수식어는 부모가 폭을 주는 만큼
    ///   **끝까지 늘어나서**, "안녕" 두 글자짜리 말풍선이 화면 절반을 차지한다. 배경을 프레임 뒤에 붙이든
    ///   앞에 붙이든 둘 중 하나가 반드시 깨진다(캡슐이 상한 폭이 되거나, 글자가 상한 폭이 되거나).
    ///   그래서 상한을 **여백으로** 만든다: 짧은 말은 글자를 따라 줄어들고, 긴 말은 이 여백에 막혀 접힌다.
    ///
    /// 창(560폭) 시절의 44 에서 40 으로 줄였다 — 292 폭에서 44 는 200자 본문을 12줄까지 밀어 올린다.
    static let bubbleOppositeInset: CGFloat = 40

    /// 입력 에디터 높이(pt). **산식**: 캡션 글자 한 줄 ≈ 15pt × 3줄 + `TextEditor` 세로 padding 5×2 ≈ 55 → 54.
    ///
    /// **왜 3줄인가**: 창(68pt ≈ 4줄) 시절보다 낮췄다. 이 블록 위가 대화 스크롤이라 여기서 1pt 를 더 쓰면
    /// 대화가 1pt 를 잃는데, 292 폭에서는 말풍선 한 줄이 곧 스무 글자 남짓이라 그 손실이 눈에 보인다.
    /// 3줄이면 200자 중 60자 남짓이 한눈에 들어오고, 넘치는 글은 에디터가 자기 안에서 스크롤한다.
    ///
    /// **최소치가 아니라 고정값인 이유**: 위가 고정 높이 스크롤이라 여기가 안 정해지면 에디터가 패널을 삼킨다.
    static let editorHeight: CGFloat = 54

    /// 패널 사이 세로 간격(pt). 머리·구분선·대화·작성기 사이에 세 번 들어간다.
    static let blockSpacing: CGFloat = 8

    /// 크롬(배너·목표 편집 행)이 하나도 없을 때 대화가 갖는 높이(pt).
    ///
    /// **두 부등식이 이 값과 아래 최소치를 정한다**(2026-09-10 ImageRenderer 실측, 팝오버 상한 700pt).
    /// 실측 상수 둘: 패널 **밖** 크롬(바깥 padding + 헤더 카드 + 간격 + 푸터) = **193pt**,
    /// 이 패널의 **고정** 크롬(카드 padding 24 + 머리 27 + 간격 8 + 구분선 1 + 간격 8 + 간격 8 + 작성기 102) = **178pt**.
    ///
    ///  ① 크롬이 없을 때:      193 + 178 + `conversationHeight` ≤ 700  → 329 이하
    ///  ② 크롬이 가장 클 때:   193 + 178 + `minConversationHeight` + **241** ≤ 700 → 88 이하
    ///
    /// 241 은 팝오버가 얹을 수 있는 가장 큰 크롬이다: 새 버전 배너(81) + 패치노트 4줄(8 + 4×15 = 68)
    /// = 149, 거기에 주간 목표 편집 인라인 행 92. (노트가 4줄로 묶여 있으므로 — `UpdateCheckStore.maxNotes` —
    /// 이 값은 **상한이지 추정이 아니다.** 토큰 소모량 행은 하위 패널이 열리면 감춰지므로 여기 없다.)
    static let conversationHeight: CGFloat = 250

    /// 크롬에 아무리 깎여도 대화에 남기는 최소 높이(pt). 위 부등식 ②의 88 에서 안전 여유를 뺀 값이다.
    ///
    /// **76pt 는 말풍선 두 줄 남짓이다** — 인색해 보이지만 그 상태는 "새 버전 배너 + 패치노트 4줄 +
    /// 주간 목표 편집"이 **동시에** 떠 있을 때뿐이고, 그때도 대화는 사라지지 않는다(스크롤로 밀릴 뿐이고
    /// 처음 보이는 것은 늘 최신 쪽이다). 여기를 키우면 그 조합에서 푸터가 잘린다 — 로그아웃할 방법이 사라진다.
    static let minConversationHeight: CGFloat = 76

    /// 배너·목표 편집 행이 먹은 높이만큼 대화를 깎는다(다른 패널의 `extraChromeHeight` 규약과 같은 계산).
    /// 깎인 만큼은 사라지는 것이 아니라 스크롤로 밀린다 — 처음 보이는 것이 최신 쪽이라 밀리는 것은 옛 말이다.
    static func conversationHeight(extraChromeHeight: CGFloat) -> CGFloat {
        max(minConversationHeight, conversationHeight - max(0, extraChromeHeight))
    }

    /// 말풍선 한 줄에 들어가는 글자 수(추정). 292pt 에서 말풍선이 쓸 수 있는 폭은
    /// 292 − 반대쪽 여백 40 − 아바타 20 − 시각 26 − 말풍선 padding 16 ≈ 190pt 이고, 캡션 한글 한 글자가
    /// 대략 12pt 이므로 15 자 남짓이다. **추정이어도 되는 이유**는 아래 `conversationContentHeight` 주석에 있다.
    static let charactersPerBubbleLine = 15

    /// 말풍선 더미의 **추정** 자연 높이(pt).
    ///
    /// **틀려도 잘리지 않는다.** 이 값은 `min(상한, 이 값)` 으로 스크롤 **틀의 높이**만 정하고, 안쪽은
    /// 언제나 ScrollView 다 — 과소평가하면 틀이 조금 작아 스크롤이 일찍 붙고, 과대평가하면 아래에 여백이
    /// 조금 남을 뿐이다. 정확한 측정(GeometryReader/PreferenceKey)을 하지 않는 이유가 그것이다:
    /// 얻는 것이 몇 pt 이고, 잃는 것은 레이아웃 왕복 한 판이다.
    ///
    /// **왜 필요한가**(2026-09-10 스냅샷): 틀을 상한 250pt 로 못 박았더니 말풍선 세 개짜리 대화 위에
    /// 회색 빈 판이 150pt 남았다. 팝오버는 콘텐츠 높이가 곧 창 높이라, 그 여백은 보기 싫은 것을 넘어
    /// **창을 그만큼 길게 만든다**(짧은 대화가 긴 대화만큼 자리를 먹는다).
    static func conversationContentHeight(_ items: [MessageTimelineItem]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        var total: CGFloat = 16   // 위아래 padding 8×2
        for (index, item) in items.enumerated() {
            if index > 0 { total += 6 }   // LazyVStack spacing
            switch item {
            case .day:
                total += 18
            case .bubble(let entry):
                // 아잉이 이모티콘(v0.3.62)은 **글자가 아니라 그림 한 장**이라 줄 수로 세면 7글자 = 한 줄 =
                // 25pt 로 센다. 실제로는 120pt 를 쓰므로 틀의 높이가 그림의 1/5 로 잡혀, 이모티콘 하나뿐인
                // 대화가 통째로 스크롤 안에 갇힌다(스크롤이 붙긴 하지만 보이는 것이 그림의 윗동만이다).
                //
                // ★ 판정은 **말풍선 행과 같은 하나**(`AingStickerArt.drawable`)다. `parse` 만 보면 그림을
                //   못 읽는 배포본에서 행은 글자 한 줄로 접히는데 여기는 122pt 로 세어, 이모티콘 건수만큼
                //   회색 빈 판이 쌓인다(아래 "2026-09-10 스냅샷"이 바로 그 증상이다).
                if AingStickerArt.drawable(for: entry.body) != nil {
                    total += stickerSide + 2   // 그림 + 말풍선 배경이 없는 자리의 아주 작은 숨통
                    continue
                }
                let lines = max(1, Int((Double(entry.body.count) / Double(charactersPerBubbleLine)).rounded(.up)))
                total += CGFloat(lines) * 15 + 10   // 줄 높이 + 말풍선 세로 padding 5×2
            }
        }
        return total
    }

    /// 말풍선 안 아잉이 이모티콘 한 장의 한 변(pt · v0.3.62).
    ///
    /// **왜 120 인가**: 이 패널의 말풍선이 쓸 수 있는 폭은 292 − 반대쪽 여백 40 − 아바타 20 − 시각 26 ≈ 206pt 다
    /// (위 `charactersPerBubbleLine` 주석의 같은 산식). 120 은 그 폭의 절반을 조금 넘겨 "글이 아니라 그림"으로
    /// 읽히는 크기이고, 세로로는 대화 틀(무크롬 250pt)의 절반이라 **이모티콘 두 장이 한 화면에 들어온다**.
    /// 더 키우면(160) 한 장이 틀을 거의 다 먹어서 직전 대화가 안 보이고, 줄이면(80) 표정이 안 읽힌다.
    static let stickerSide: CGFloat = 120

    /// 찌르기 기록 한 줄의 높이(pt · v0.3.65). 9pt 글자 한 줄 + 위아래 숨통 — 날짜 구분선(18)보다 낮게 둔다(말이 주인공이다).
    static let pokeLineHeight: CGFloat = 16

    /// 대화 줄(찌르기 기록 포함)의 **추정** 자연 높이(pt · v0.3.65). 말풍선·날짜 줄은 위 `conversationContentHeight(_:)` 의 산식을
    /// **그대로 빌린다**(한 줄짜리 타임라인으로 물어 바깥 padding 16 을 뺀다) — 두 산식이 갈리면 빈 회색 판이 생긴다.
    static func conversationContentHeight(lines: [MessageConversationLine]) -> CGFloat {
        guard !lines.isEmpty else { return 0 }
        var total: CGFloat = 16   // 위아래 padding 8×2
        for (index, line) in lines.enumerated() {
            if index > 0 { total += 6 }   // LazyVStack spacing
            switch line {
            case .day(let key, let label):
                total += conversationContentHeight([.day(key: key, label: label)]) - 16
            case .bubble(let entry):
                total += conversationContentHeight([.bubble(entry)]) - 16
            case .poke:
                total += pokeLineHeight
            }
        }
        return total
    }

    /// 대화가 아무리 짧아도 틀에 남기는 높이(pt). 말풍선 하나가 판 안에 앉아 보이는 최소치.
    static let minShownConversationHeight: CGFloat = 56
    /// 빈 상태(아이콘 + 제목 + 보조 한 줄 + 때때로 [다시 시도])가 쓰는 높이(pt). 상한에 걸리면 그만큼 줄어든다.
    static let emptyStateHeight: CGFloat = 118

    static let corner: CGFloat = 10
}

/// 대화 화면의 빈 자리 문구 판정(순수 — 결정적 검증 지점).
///
/// 뷰 안에서 갈래를 세면 "실패했는데 '없어요'라고 단정하는" 조합이 언젠가 생긴다(토큰 보드가 실제로 그랬다).
/// 갈래는 넷이고, 넷의 답이 서로 다르다:
///   ① 상대를 못 정했다 — 할 일은 '고르기'다. 이 화면에는 사람 목록이 없으므로 어디로 가야 하는지 말해 준다.
///   ② 아직 못 받았다 — 기다림이다(본문 자리에 동기화 문구를 쓰지 않는다는 규약).
///   ③ 실패했다 — 기다림과 다른 문장 + [다시 시도].
///   ④ 받았는데 이 사람과의 대화가 없다 — 할 일은 '시작하기'다.
enum MessagePanelEmptyMessage {
    static func state(hasPeer: Bool, loaded: Bool, failed: Bool) -> MessagePanelEmptyState {
        guard hasPeer else {
            return MessagePanelEmptyState(
                symbol: "person.crop.circle.badge.questionmark",
                title: "대화 상대를 고르지 않았어요",
                hint: "콕 찌르기 목록에서 말풍선 버튼을 누르면 그 사람과의 대화가 열려요",
                showsRetry: false
            )
        }
        if failed, !loaded {
            return MessagePanelEmptyState(
                symbol: "exclamationmark.triangle",
                title: "대화를 불러오지 못했어요",
                hint: nil,
                showsRetry: true
            )
        }
        if !loaded {
            return MessagePanelEmptyState(symbol: "hourglass", title: "불러오는 중…", hint: nil, showsRetry: false)
        }
        return MessagePanelEmptyState(
            symbol: "bubble.left.and.bubble.right",
            title: "아직 주고받은 메시지가 없어요",
            hint: "아래에 먼저 한마디 남겨 보세요",
            showsRetry: false
        )
    }
}

struct MessagePanelEmptyState: Equatable {
    let symbol: String
    let title: String
    let hint: String?
    let showsRetry: Bool
}

/// 내가 보낸 말풍선 옆 **안 읽음 1**의 판정과 모양 상수(v0.3.30 — 순수 · 결정적 검증 지점).
///
/// 조건은 셋이 **모두** 맞을 때뿐이다: 서버가 읽음을 안다(`messageReadReceiptsAvailable`) · 내가 보낸 말이다 ·
/// 서버가 "상대가 아직 안 읽었다"(`readByPeer == false`)고 말했다.
///  · `readByPeer == nil` 은 "모름"이다(받은 말 · 옛 `message_history`). 모르는 것을 1로 그리면 거짓이다.
///  · 서버가 읽음을 모르면(옛 서버로 접힌 이력) 행에 값이 남아 있어도 그리지 않는다 — 스토어가 두 사실을 따로 들고
///    있어서, 한쪽만 보면 db push 가 되돌아간 날 낡은 1이 영영 남는다.
/// **시각을 비교하지 않는다** — 읽음 판정은 서버가 마이크로초로 끝냈고, 뷰가 `createdAt`(초)으로 다시 세면 같은 초 안의
/// 말들이 서로 뒤바뀐다(`MessageHistoryEntry.isUnread` 주석).
enum MessageReadReceiptMark {
    /// 말풍선 옆에 찍는 글자. 카톡과 같은 "1" — 남은 안 읽은 사람 수가 아니라 1:1 대화라 늘 1이다.
    static let text = "1"
    /// 보이스오버 문구(글자 "1"만 읽히면 무엇의 1인지 모른다).
    static let accessibilityLabel = "안 읽음"

    static func showsUnreadOne(for entry: MessageHistoryEntry, receiptsAvailable: Bool) -> Bool {
        receiptsAvailable && entry.isMine && entry.readByPeer == false
    }
}

// MARK: - 패널 본체

/// 한 사람과의 대화 패널. 리그·토큰 보드·콕찌르기·내 기록·울트라와 **같은 뼈대**다:
/// 뒤로 버튼 + 제목 + 본문, 그리고 `extraChromeHeight` 를 받아 무스크롤 높이를 줄이는 규약.
struct CheckMessageView: View {
    @Bindable var store: WorkTimerStore
    /// 스냅샷 전용 대체 경로(파일 머리 주석). **앱은 언제나 false** 다.
    var rendersPlainTextEditor: Bool = false
    /// 스냅샷 전용: 대화를 ScrollView 대신 클립으로 그린다. **앱은 언제나 false** 다.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 배너·목표 편집 행이 목록 위에서 먹은 높이(pt). 그만큼 대화를 깎아 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    /// 날짜 라벨의 기준. **관찰 대상이 아니다**(파일 머리 주석의 "초 단위 무효화 금지").
    var now: Date = Date()
    let onBack: () -> Void

    /// 스크롤 따라가기 상태가 바뀔 때마다 알린다(**테스트 전용 관찰 문** — 앱은 nil). 호스팅 렌더로 "위로 올려 둔 채 새 말 → 버튼"을 잰다.
    var onFollowChange: ((MessageScrollFollow) -> Void)? = nil

    /// 이 뷰 인스턴스의 표식(v0.3.31 M4). 스토어가 "대화가 화면에 서 있는가"를 뷰마다 따로 센다 — 이유는
    /// `WorkTimerStore.messageConversationViewTokens` 주석(나타남·사라짐이 어느 순서로 와도 수렴).
    @State private var viewToken = UUID()

    /// 아잉이 이모티콘 그리드가 펼쳐져 있는가(v0.3.62).
    ///
    /// **스토어가 아니라 뷰가 든다.** 이 깃발은 서버·세션과 아무 관계가 없고, [뒤로]로 나가면 접혀 있는 쪽이
    /// 맞다(다시 들어오면 뷰가 새로 만들어진다). 스토어에 두면 팝오버를 닫고 열어도 펼친 채로 남는다.
    @State private var stickerGridOpen = false

    /// 보이스오버·스냅샷 프로브 전용: 그리드를 **펼친 채로 못 박는다**. 앱은 언제나 false 다
    /// (파일 머리 "두 스위치의 기본값이 false 이고 프로덕션에 true 를 주는 자리는 없다"와 같은 규약).
    ///
    /// 왜 필요한가: 펼친 화면은 `@State` 뒤에 있어 **밖에서 만들 길이 없다**. 그러면 덮개의 보이스오버
    /// 단언이 소스 substring 으로 내려앉고, 그 단언은 `.accessibilityHidden` 한 줄을 `.overlay` **뒤**로
    /// 옮겨도(그리드까지 보이스오버에서 사라진다 — 고치려던 것보다 나쁘다) 그대로 초록이다.
    var pinsStickerGridOpen: Bool = false

    /// 읽는 자리는 전부 이것을 본다(상태 ∨ 못 박기).
    private var showsStickerGrid: Bool { stickerGridOpen || pinsStickerGridOpen }

    private var thread: MessageThread? { store.selectedMessageThread }
    private var hasPeer: Bool { store.selectedMessagePeerID != nil }

    var body: some View {
        if let sheet = store.blockReportSheet(on: .message) {
            // 신고·차단 시트(v0.3.34)는 대화 **자리에** 선다 — 팝오버는 콘텐츠 높이가 곧 창 높이라 겹쳐 띄울 자리가 없다.
            // 본문 상한은 대화 패널의 예산을 그대로 빌린다(`BlockReportSheetLayout.popoverBodyCap` — 넘치면 스크롤로 밀린다).
            BlockReportSheetView(
                store: store,
                sheet: sheet,
                rendersPlainTextEditor: rendersPlainTextEditor,
                clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll,
                bodyCap: BlockReportSheetLayout.popoverBodyCap(
                    extraChromeHeight: extraChromeHeight,
                    hasFooterNotice: sheet.kind == .report && store.reportNotice != nil
                )
            )
            .padding(12)
            .pagePanelStyle()
        } else {
            VStack(spacing: MessagePanelLayout.blockSpacing) {
                header
                PanelDivider()
                conversation
                composer
            }
            .padding(12)
            .pagePanelStyle()
            // ★ 도착한 메시지를 **재진입 없이** 그리는 판정의 한 축이다(v0.3.31 M4). 팝오버 표시 칸(`isMenuPresented`)만 보던 0.3.29 는
            //   떠 있는 팝오버에서 그 칸이 false 로 남으면 [뒤로] 뒤 다시 들어가야 새 말이 떴다. 이 두 줄을 지우면 판정이 그 한 칸으로 돌아간다.
            .onAppear { store.messageConversationViewDidAppear(viewToken) }
            .onDisappear { store.messageConversationViewDidDisappear(viewToken) }
        }
    }

    // MARK: 머리 — 뒤로 + 아바타 + 상대 이름

    /// **[뒤로]가 돌아가는 곳은 이 뷰가 정하지 않는다.** 들어온 문(`messagePanelOrigin`)이 정하고
    /// `closeMessagePanel()` 하나가 실행한다 — 뷰가 정하면 진입 경로가 늘 때마다 여기도 갈라진다.
    private var header: some View {
        HStack(spacing: 8) {
            IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
            if hasPeer {
                CheckAvatarView(name: peerName, userID: store.selectedMessagePeerID, avatarURL: store.selectedMessagePeerAvatarURL, size: 22)
            }
            // 이름 아래 상대의 상태메시지 한 줄(v0.3.51). **머리 높이를 늘리지 않는다**: 맥의 subheadline(11pt) 한 줄 +
            // caption2(10pt) 한 줄이 [뒤로] 버튼(27pt) 높이 안에 든다 — 이 패널의 최악 크롬 여유는 12pt 뿐이라(위 부등식 ②)
            // 머리가 자라면 그만큼 푸터가 잘린다. V0351 이 상태 유무로 패널 높이가 같은지를 그려서 되묻는다.
            VStack(alignment: .leading, spacing: 0) {
                Text(hasPeer ? peerName : "메시지")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if hasPeer, let status = store.selectedMessagePeerStatusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .checkTooltip(status)
                        .accessibilityLabel("상태메시지: \(status)")
                }
            }
            Spacer(minLength: 6)
            // 아직 못 받았을 때만 뜬다. **본문 자리가 아니라 머리 오른쪽**이다 — 본문 자리에 동기화 문구를
            // 쓰지 않는다는 규약이고, 이미 대화가 보이는 상태에서 갱신이 돌 때도 화면이 안 흔들린다.
            if store.messageHistoryLoading, !store.messageHistoryLoaded {
                Text("불러오는 중…")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize()
            }
            // ··· → [신고하기] · [차단하기](v0.3.34). **시트를 열 뿐**이다 — 차단은 확인 시트의 [차단하기]만 보낸다.
            if let peer = store.selectedMessagePeerID {
                BlockReportMoreButton { item in
                    let target = BlockReportTarget(peerID: peer, peerName: peerName)
                    switch item {
                    case .report: store.openReport(target, surface: .message)
                    case .block: store.openBlockConfirm(target, surface: .message)
                    }
                }
            }
        }
    }

    /// 화면에 쓸 상대 이름. 이력·콕찌르기 목록·수신 큐 셋 중 **먼저 아는 곳**에서 온다
    /// (스토어의 파생값 — 한 번도 대화한 적 없는 사람을 처음 누른 경우가 그 셋이 다 필요한 이유다).
    private var peerName: String { store.selectedMessagePeerName ?? "대화" }

    // MARK: 본문 — 말풍선

    /// 대화 자리. **아잉이 이모티콘 그리드(v0.3.62)는 이 자리를 덮는다 — 패널 높이를 1pt 도 늘리지 않는다.**
    ///
    /// 신고·차단 시트가 대화 **자리에** 서는 것과 같은 규약이다(이 파일 머리의 `BlockReportSheetView` 갈래):
    /// 팝오버는 콘텐츠 높이가 곧 창 높이라 **겹쳐 띄울 자리가 없다**. 아래로 펼치는 서랍으로 만들면
    /// 그 높이가 그대로 창 높이에 더해져, 새 버전 배너가 떠 있는 날 푸터(로그아웃)가 잘린다
    /// (`conversationHeight` 의 부등식 ②).
    ///
    /// ★ 그리드가 펼쳐지면 대화 자리가 **예산 전체(cap)** 를 쓴다. 평소에는 "내용만큼만" 쓰므로
    ///   말풍선 한 줄짜리 대화에서는 56pt 밖에 없는데, 거기에 여섯 칸을 세우면 두 줄 중 아래 줄이 사라진다.
    ///   cap 은 이 패널이 **이미 쓸 수 있도록 예산된** 높이라 여기서 창 상한을 넘기지 않는다.
    @ViewBuilder
    private var conversation: some View {
        // 상한은 크롬 예산이 정하고, 그 안에서 **내용만큼만** 쓴다(짧은 대화가 긴 대화만큼 자리를 먹지 않게).
        let cap = MessagePanelLayout.conversationHeight(extraChromeHeight: extraChromeHeight)
        conversationBody(cap: cap)
            .frame(height: showsStickerGrid ? cap : nil)
            // 덮개는 **눈만** 가린다 — 보이스오버에는 가려진 말풍선이 그대로 남아, 훑으면 안 보이는 본문·
            // 시각·'안 읽음'이 계속 읽히고 여섯 칸이 어디서 시작하는지 알 수 없다(신고·차단 시트는 대화를
            // **교체**해서 이 문제가 없었다 — 이 그리드가 이 패널의 첫 겹침 덮개다).
            .accessibilityHidden(showsStickerGrid)
            .overlay {
                if showsStickerGrid {
                    AingStickerGridView(
                        availableHeight: cap,
                        // 칸도 버튼과 **같은 판정**을 본다. 펼쳐 둔 뒤에 못 보내는 상태가 되면(글을 보낸
                        // 왕복 0.2~1.5초) 버튼만 흐려지고 칸 여섯 개는 그대로라, 누른 이모티콘이 아무
                        // 안내 없이 삼켜졌다(두 겹 게이트의 뷰 쪽 짝 — 한쪽만 걸면 조용히 아무 일도 안 난다).
                        canSend: store.canSendStickerNow,
                        onPick: { sticker in
                            // 고른 그 순간 **그 자리에서 전송**된다(사용자 결정 — 글과 섞지 않는다).
                            // 문은 스토어 하나다: `sendSticker` 가 `sendMessage(to:body:)` 로 들어간다.
                            //
                            // ★ **보냈을 때만 접는다.** 못 보냈는데 접으면 화면에 남는 신호가 "그리드가
                            //   닫혔다" 하나뿐이라, 직전 전송의 "보냈어요"를 보고 이모티콘도 간 줄 안다.
                            if store.sendSticker(sticker) { stickerGridOpen = false }
                        },
                        onClose: { stickerGridOpen = false }
                    )
                    .background(
                        RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                            // 대화를 **가린다**(반투명으로 두면 말풍선 글자가 그림 뒤에 겹쳐 읽힌다).
                            .fill(CheckTheme.background)
                            .overlay(conversationBackground)
                    )
                }
            }
    }

    @ViewBuilder
    private func conversationBody(cap: CGFloat) -> some View {
        // v0.3.65: 메시지 사이에 **찌르기 기록**을 시간 순서로 끼운다(서버가 24시간 안의 것만 내려 주므로 오래된 줄은 저절로 사라진다).
        // 끼움 판정은 코어 `MessageConversationTimeline` 한 곳이다 — 뷰는 자리만 그린다. 찌르기가 없으면 예전 타임라인과 줄 단위로 같다.
        let messages = thread?.messages ?? []
        let pokes = store.selectedMessagePokeLog
        if let peer = store.selectedMessagePeerID, !messages.isEmpty || !pokes.isEmpty {
            let lines = MessageConversationTimeline.lines(
                messages: messages, pokes: pokes, chronology: store.messagePokeChronology, now: now
            )
            let natural = max(
                MessagePanelLayout.minShownConversationHeight,
                MessagePanelLayout.conversationContentHeight(lines: lines)
            )
            MessageConversationView(
                lines: lines,
                peerUserID: peer,
                // 새 줄(메시지든 찌르기든)이 붙었는지 아는 키 — 바닥 근처면 따라 내려간다.
                lastMessageID: lines.last?.id,
                // 내가 보낸 말은 위로 올려 둔 상태여도 바닥으로 따라간다(v0.3.31 M4 — 메신저 감각: 방금 친 말이 화면 밖에 붙으면 안 된다).
                lastMessageIsMine: lines.last?.isMine ?? false,
                // 읽음 기능 여부는 **값**으로 내린다(v0.3.30). 시계가 아니라 이력 응답이 바꾸는 값이라 잎으로 가둘 이유가 없다.
                readReceiptsAvailable: store.messageReadReceiptsAvailable,
                clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll,
                onFollowChange: onFollowChange,
                // 받은 말풍선 우클릭 → [이 메시지 신고하기](v0.3.34). 그 메시지 id 를 싣는다 — 운영자가 무엇을 볼지 정해진다.
                onReport: { entry in
                    guard let target = MessageBubbleReportRule.target(for: entry) else { return }
                    store.openReport(target, surface: .message)
                }
            )
            .frame(height: min(cap, natural))
            .frame(maxWidth: .infinity)
            .background(conversationBackground)
        } else {
            emptyState
                .frame(height: min(cap, MessagePanelLayout.emptyStateHeight))
                .frame(maxWidth: .infinity)
                .background(conversationBackground)
        }
    }

    private var conversationBackground: some View {
        RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
            .fill(Color.white.opacity(0.04))
    }

    private var emptyState: some View {
        let state = MessagePanelEmptyMessage.state(
            hasPeer: hasPeer,
            loaded: store.messageHistoryLoaded,
            failed: store.messageHistoryFailed
        )
        return VStack(spacing: 6) {
            Spacer(minLength: 0)
            // 아이콘은 **글자와 함께**만 뜻을 갖는다(색·그림만으로 정보를 주지 않는다는 이 저장소의 규약).
            Image(systemName: state.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(CheckTheme.secondaryText.opacity(0.55))
            Text(state.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let hint = state.hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.showsRetry {
                PanelRetryButton { store.loadMessageHistory() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 작성기

    private var composer: some View {
        // 이모티콘 깃발은 **뷰 하나가 들고** 작성기와 대화 자리가 같은 값을 본다 — 두 벌로 나누면
        // 버튼은 눌렸는데 그리드는 안 뜨는(또는 그 반대) 조합이 생긴다.
        MessageComposerView(
            store: store,
            rendersPlainText: rendersPlainTextEditor,
            // 못 박기(`pinsStickerGridOpen`)까지 함께 보는 묶음이다 — 작성기 버튼과 대화 자리가 다른 값을
            // 보면 프로브가 "버튼은 닫기인데 그리드는 없는" 화면을 재게 된다.
            stickerGridShown: Binding(get: { showsStickerGrid }, set: { stickerGridOpen = $0 })
        )
    }
}

// MARK: - 대화(말풍선 더미)

/// 한 사람과의 대화. 말풍선을 **시간순으로 쌓고**, 처음 열면 맨 아래(최신)에 있다.
struct MessageConversationView: View {
    /// **이미 계산된** 대화 줄(날짜 구분선 · 말풍선 · 찌르기 기록 — v0.3.65). 부모가 같은 값으로 틀 높이도 정하므로 여기서 다시
    /// 만들지 않는다 — 두 번 만들면 두 계산이 언젠가 갈리고, 그때 틀과 내용의 높이가 어긋난다.
    let lines: [MessageConversationLine]
    /// 상대가 바뀌었는지 알기 위한 키(스크롤을 맨 아래로 되돌리는 트리거).
    let peerUserID: String
    /// 새 말이 도착했는지 알기 위한 키(같은 트리거의 애니메이션 갈래).
    let lastMessageID: String?
    /// 마지막 말이 내가 보낸 것인가(v0.3.31 M4). 보낸 말은 위로 올려 둔 상태여도 바닥으로 따라간다.
    var lastMessageIsMine: Bool = false
    /// 서버가 읽음을 아는가(`WorkTimerStore.messageReadReceiptsAvailable`). false 면 보낸 말풍선 옆 1을 하나도 그리지 않는다.
    /// **기본값 false** — 모르는 쪽으로 틀리는 것이 안전하다(없는 1을 그리면 상대가 안 읽었다는 거짓말이 된다).
    var readReceiptsAvailable: Bool = false
    var clipsInsteadOfScrolling: Bool = false
    /// 따라가기 상태가 바뀔 때마다 알린다(테스트 전용 관찰 문 — 앱은 nil).
    var onFollowChange: ((MessageScrollFollow) -> Void)? = nil
    /// 받은 말풍선 우클릭 → [이 메시지 신고하기](v0.3.34). nil 이면 우클릭 메뉴가 없다(스냅샷·옛 호출부). 어느 말풍선에 서는지는
    /// `MessageBubbleReportRule.offersReport` 한 곳이 정한다 — **내 말풍선에는 서지 않는다.**
    var onReport: ((MessageHistoryEntry) -> Void)? = nil

    /// 맨 아래로 보낼 앵커. 마지막 말풍선 id 를 쓰지 않는 이유는 그 뒤의 아래 여백까지 보이게 하기 위해서다.
    private static let bottomAnchorID = "message-thread-bottom"

    /// 바닥 따라가기 / "새 메시지 ↓" 판정(v0.3.31 M4). 규칙은 `MessageScrollFollow` 한 곳이다.
    @State private var follow = MessageScrollFollow()
    /// 스크롤 틀의 높이(pt)와 내용 전체의 틀(스크롤 좌표계 기준 — minY 가 곧 −스크롤 위치).
    @State private var viewportHeight: CGFloat = 0
    @State private var contentFrame: CGRect = .zero

    var body: some View {
        if clipsInsteadOfScrolling {
            // 스냅샷 전용(ImageRenderer 는 ScrollView 안쪽을 못 그린다). **아래쪽이 최신이므로 위를 자른다** —
            // 앱에서 처음 보이는 것이 최신 쪽이라, 위를 남기고 아래를 자르면 스냅샷과 화면이 다른 것을 보여 준다.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { content.fixedSize(horizontal: false, vertical: true) }
                .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack {
                        content
                        Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                    }
                    // 내용의 틀을 스크롤 좌표계로 잰다 — 바닥까지 남은 거리와 "내용이 자랐는가"를 한 번에 안다.
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(MessageScrollFollow.coordinateSpaceName))
                    } action: { frame in
                        contentFrame = frame
                        follow.measured(contentHeight: frame.height, viewportHeight: viewportHeight, contentMaxY: frame.maxY)
                    }
                }
                .coordinateSpace(.named(MessageScrollFollow.coordinateSpaceName))
                .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { height in
                    viewportHeight = height
                    follow.measured(contentHeight: contentFrame.height, viewportHeight: height, contentMaxY: contentFrame.maxY)
                }
                // 내용이 화면보다 짧아도 **아래에 붙인다**(메신저의 기본 감각이고, 스냅샷의 클립 갈래와
                // 같은 그림이 되게 하는 값이기도 하다 — 두 그림이 다르면 스냅샷으로 아무것도 확인할 수 없다).
                .defaultScrollAnchor(.bottom)
                // 위로 올려 두고 읽는 중에 새 말이 오면 끌어내리지 않고 이 버튼만 띄운다(v0.3.31 M4).
                .overlay(alignment: .bottom) {
                    if follow.showsNewMessageButton {
                        MessageNewMessageJumpButton {
                            follow.jumpedToBottom()
                            scrollToBottom(proxy, animated: true)
                        }
                        .padding(.bottom, 6)
                    }
                }
                // 처음 열 때 · 상대를 바꿀 때는 무조건 맨 아래로. 새 말이 도착하면 **바닥 근처였거나 내가 보낸 말일 때만** 따라간다.
                .onAppear {
                    follow.jumpedToBottom()
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: peerUserID) { _, _ in
                    follow.jumpedToBottom()
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: lastMessageID) { _, _ in
                    // ★ **애니메이션 없이** 보낸다(v0.3.31 M4). 새 줄이 붙는 바로 그 갱신 안의 애니메이션 스크롤은 도착을 확인할 길이 없었다 —
                    //   화면 밖 호스팅 측정(V0331MessageArrivalViewTests ④)에서 애니메이션 갈래는 위로 올려 둔 대화를 제자리에 두었고, 즉시 갈래는
                    //   바닥에 닿았다(화면 밖이라 애니메이션이 안 도는 것인지 목표가 새 줄 배치 전 높이로 잡힌 것인지는 가르지 못했다).
                    //   요구가 "바로 뜨게"라, 검증되는 쪽을 쓴다. [새 메시지 ↓] 버튼은 새 줄과 같은 갱신이 아니라 애니메이션을 남겼다.
                    if follow.lastMessageChanged(isMine: lastMessageIsMine) {
                        scrollToBottom(proxy, animated: false)
                    }
                }
                .onChange(of: follow) { _, next in onFollowChange?(next) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard animated else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                switch line {
                case .day(_, let label):
                    MessageDaySeparator(label: label)
                case .bubble(let entry):
                    MessageBubbleRow(
                        entry: entry,
                        showsUnreadOne: MessageReadReceiptMark.showsUnreadOne(
                            for: entry, receiptsAvailable: readReceiptsAvailable
                        ),
                        onReport: MessageBubbleReportRule.offersReport(for: entry) ? onReport.map { report in { report(entry) } } : nil
                    )
                case .poke(let entry):
                    // 말풍선이 아니다 — 답장·읽음 1·신고 메뉴 대상이 아니다(v0.3.65).
                    MessagePokeLogLine(entry: entry)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MessageConversationView {
    /// 찌르기 기록이 없는 타임라인으로 만든다(v0.3.65 이전 모양 — 스냅샷·프로브 호출부가 그대로 쓴다). 줄은 그대로 옮긴다.
    init(
        items: [MessageTimelineItem],
        peerUserID: String,
        lastMessageID: String?,
        lastMessageIsMine: Bool = false,
        readReceiptsAvailable: Bool = false,
        clipsInsteadOfScrolling: Bool = false,
        onFollowChange: ((MessageScrollFollow) -> Void)? = nil,
        onReport: ((MessageHistoryEntry) -> Void)? = nil
    ) {
        self.init(
            lines: items.map { item in
                switch item {
                case .day(let key, let label): return .day(key: key, label: label)
                case .bubble(let entry): return .bubble(entry)
                }
            },
            peerUserID: peerUserID,
            lastMessageID: lastMessageID,
            lastMessageIsMine: lastMessageIsMine,
            readReceiptsAvailable: readReceiptsAvailable,
            clipsInsteadOfScrolling: clipsInsteadOfScrolling,
            onFollowChange: onFollowChange,
            onReport: onReport
        )
    }
}

/// 대화 사이에 끼는 **찌르기 기록 한 줄**(v0.3.65 — 사용자 결정 "서로 찌르거나 울트라 찌르기 한거 메세지창에 기록으로").
///
/// 가운데 정렬 작은 회색 줄이다: 아이콘(레일 콕 손가락 · 울트라 번개) + "○○님이 콕 찔렀어요 · 15:12" / "내가 울트라 찔렀어요 · 15:15".
/// **말풍선이 아니다** — 배경·아바타·읽음 1·우클릭 메뉴가 없다. 이름이 길면 주어만 줄이고 시각은 언제나 보인다.
/// 높이는 `MessagePanelLayout.pokeLineHeight` 하나다(틀 높이 추정과 같은 값).
struct MessagePokeLogLine: View {
    let entry: MessagePokeLogEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: MessagePokeLogText.symbol(entry.kind))
                .font(.system(size: 8, weight: .semibold))
            // 주어와 술어 사이는 낱말 띄어쓰기 한 칸 폭이다(바깥 4pt 간격을 그대로 쓰면 두 칸처럼 벌어진다).
            HStack(spacing: 2.5) {
                Text(MessagePokeLogText.subject(for: entry))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(MessagePokeLogText.predicate(for: entry))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.system(size: 9).monospacedDigit())
        .foregroundStyle(CheckTheme.secondaryText.opacity(0.85))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: MessagePanelLayout.pokeLineHeight)
        // 보이스오버는 한 문장으로 읽는다(아이콘 이름 · 조각 셋으로 끊어 읽히면 무엇의 기록인지 흩어진다).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MessagePokeLogText.line(for: entry))
    }
}

/// 대화 스크롤의 **바닥 따라가기** 판정(v0.3.31 M4 — 순수 · 결정적 검증 지점).
///
/// 사용자 요구: "실제 메신저앱처럼 메시지마다 바로 대화창에 뜨게". 메신저의 두 감각을 그대로 옮긴다:
///  · 바닥 근처(`nearBottomThreshold` 안)에서 보고 있으면 새 말이 오는 대로 따라 내려간다.
///  · 위로 올려 옛 말을 읽는 중이면 **끌어내리지 않는다** — 대신 "새 메시지 ↓" 버튼을 띄우고, 누르거나 스스로 바닥에 닿으면 사라진다.
///  · 내가 보낸 말은 어디서 보냈든 따라간다(방금 친 말이 화면 밖에 붙으면 전송이 실패한 것처럼 보인다).
///
/// ★ **내용이 자라서 멀어진 것은 "위로 올렸다"가 아니다.** 바닥에서 보던 중에 새 말이 붙으면 그 말의 높이만큼 바닥이 멀어진 측정이
///   따라가기 판정보다 먼저 올 수 있다(레이아웃과 onChange 의 순서는 SwiftUI 가 약속하지 않는다). 그 측정으로 `isNearBottom` 을 내리면
///   바닥에서 보던 사람에게 버튼만 뜨고 새 말은 화면 밖에 붙는다 — 정확히 신고의 모양이다. 그래서 내용 높이가 바뀐 측정은 "가까워짐"만 반영한다.
struct MessageScrollFollow: Equatable, Sendable {
    /// 바닥 근처의 폭(pt). 말풍선 두 줄 남짓 — 마지막 말을 읽으며 살짝 올린 정도는 "바닥에서 보는 중"으로 친다.
    static let nearBottomThreshold: CGFloat = 60
    /// 스크롤 좌표계 이름(측정 전용).
    static let coordinateSpaceName = "message-conversation-scroll"

    private(set) var isNearBottom = true
    private(set) var showsNewMessageButton = false
    /// 마지막 측정의 내용 높이(내용이 자랐는지 가르는 기준). nil = 아직 못 쟀다.
    private var lastContentHeight: CGFloat?

    /// 스크롤 위치·틀·내용이 새로 측정됐다. `contentMaxY` 는 스크롤 좌표계에서 내용 바닥의 y(= 내용 높이 − 스크롤 위치).
    mutating func measured(contentHeight: CGFloat, viewportHeight: CGFloat, contentMaxY: CGFloat) {
        guard viewportHeight > 0, contentHeight > 0 else { return }
        let distance = contentMaxY - viewportHeight
        let grew = lastContentHeight.map { abs($0 - contentHeight) > 0.5 } ?? true
        lastContentHeight = contentHeight
        if distance <= Self.nearBottomThreshold {
            isNearBottom = true
            showsNewMessageButton = false
        } else if !grew {
            // 내용은 그대로인데 바닥이 멀어졌다 = 사람이 위로 올렸다.
            isNearBottom = false
        }
    }

    /// 마지막 말이 바뀌었다. **바닥으로 따라가야 하면 true.** 못 따라가면 버튼을 세운다.
    mutating func lastMessageChanged(isMine: Bool) -> Bool {
        if isNearBottom || isMine {
            isNearBottom = true
            showsNewMessageButton = false
            return true
        }
        showsNewMessageButton = true
        return false
    }

    /// 코드가 바닥으로 보냈다(처음 열기 · 상대 바꾸기 · 버튼).
    mutating func jumpedToBottom() {
        isNearBottom = true
        showsNewMessageButton = false
    }
}

/// "새 메시지 ↓" — 위로 올려 둔 대화에 새 말이 왔다는 작은 알약. 누르면 바닥으로 간다.
struct MessageNewMessageJumpButton: View {
    static let title = "새 메시지 ↓"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Self.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(CheckTheme.accent))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("새 메시지로 이동")
    }
}

/// 날짜 구분선("오늘" / "어제" / "9월 8일"). 가운데 캡슐 + 양옆 실선.
private struct MessageDaySeparator: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(CheckTheme.border).frame(height: 1)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .fixedSize()
            Rectangle().fill(CheckTheme.border).frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}

/// 말풍선 한 줄. 받은 것은 왼쪽(아바타 있음), 보낸 것은 오른쪽(아바타 없음 — 내 얼굴은 내가 안다).
private struct MessageBubbleRow: View {
    let entry: MessageHistoryEntry
    /// 이 말풍선 옆에 안 읽음 1을 찍는가. 판정은 `MessageReadReceiptMark.showsUnreadOne` 하나다 — 행이 조건을 다시 세지 않는다.
    var showsUnreadOne: Bool = false
    /// 우클릭 → [이 메시지 신고하기](v0.3.34). **받은 말풍선에만** 들어온다(`MessageBubbleReportRule` — 대화 뷰가 거른다).
    var onReport: (() -> Void)? = nil

    private var clockText: String { MessageThreadBuilder.clockText(entry.createdAt) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if entry.isMine {
                // 보낸 것: 왼쪽을 비우고 시각을 말풍선 **왼쪽**에 둔다(오른쪽 끝은 화면 가장자리다).
                Spacer(minLength: MessagePanelLayout.bubbleOppositeInset)
                sentMeta
                bubble
            } else {
                CheckAvatarView(name: entry.peerName, userID: entry.peerUserID, avatarURL: entry.peerAvatarURL, size: 20)
                bubble
                timeLabel
                Spacer(minLength: MessagePanelLayout.bubbleOppositeInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.isMine ? .trailing : .leading)
    }

    private var timeLabel: some View {
        Text(clockText)
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(CheckTheme.secondaryText.opacity(0.8))
            .fixedSize()
    }

    /// 보낸 말풍선의 바깥 아래쪽 곁 — 안 읽음 1(있으면) 위, 시각 아래(v0.3.30).
    ///
    /// **옆이 아니라 위아래로 쌓는다**: 말풍선 폭은 반대쪽 여백(`bubbleOppositeInset`)이 정하는데, 1을 시각 옆에 세우면
    /// 긴 말풍선이 그만큼 좁아져 줄이 하나 늘 수 있다(틀 높이 추정 `conversationContentHeight` 가 모르는 변화다).
    /// 쌓으면 폭은 시각 글자 그대로이고, 높이는 말풍선 한 줄(25pt) 안에 1(11pt)과 시각(11pt)이 들어간다.
    /// 1이 없으면 예전과 **같은 뷰**(시각 하나)다 — 읽음을 모르는 서버에서 화면이 한 픽셀도 달라지지 않는다.
    @ViewBuilder
    private var sentMeta: some View {
        if showsUnreadOne {
            VStack(alignment: .trailing, spacing: 0) {
                Text(MessageReadReceiptMark.text)
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(CheckTheme.accent)
                    .fixedSize()
                    .accessibilityLabel(MessageReadReceiptMark.accessibilityLabel)
                timeLabel
            }
        } else {
            timeLabel
        }
    }

    /// 본문. **폭을 프레임으로 못 박지 않는다** — 그 이유는 `bubbleOppositeInset` 주석에 있다.
    /// 여기서 하는 일은 둘뿐이다: 세로로만 자라게 두고(`fixedSize(vertical:)`), 글자를 감싸는 캡슐을 그린다.
    ///
    /// **`fixedSize(horizontal: true)` 는 금지다** — 200자가 한 줄을 요구해 화면 밖으로 넘친다.
    ///
    /// **받은 말풍선은 우클릭 메뉴를 갖는다**(v0.3.34 — [복사] · [이 메시지 신고하기]). 그 말풍선에는 글자 선택(`textSelection`)을
    /// 걸지 않는다: 선택 가능한 글자는 우클릭을 자기 메뉴(복사·찾아보기)로 가져가 신고 항목이 안 뜬다. 대신 [복사]를 메뉴에 둔다
    /// (폰의 길게 누름 메뉴와 같은 차림). 내 말풍선은 예전 그대로 글자 선택이다.
    @ViewBuilder
    private var bubble: some View {
        if let onReport {
            bubbleText
                .contextMenu {
                    Button {
                        CheckPasteboard.copy(entry.body)
                    } label: {
                        Label("복사", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive, action: onReport) {
                        Label(BlockReportText.reportMessageAction, systemImage: "exclamationmark.bubble")
                    }
                }
        } else {
            bubbleText
                .textSelection(.enabled)
        }
    }

    /// 본문이 아잉이 이모티콘 하나면 **글자 대신 그림**이다(v0.3.62). 아니면 예전 그대로 글자 말풍선이다.
    ///
    /// ★ **그림을 못 읽으면 글자로 접는다.** 번들이 깨진 배포본(맥 패키징이 리소스 번들 복사를 빠뜨린 경우)에서
    ///   빈 말풍선이 되면 사용자는 상대가 뭘 보냈는지 알 길이 없다 — 이름 글자("아잉이 기쁨")가 보이는 쪽이
    ///   낫다. 그 판정은 `AingStickerArt.drawable` 하나이고, **틀 높이 추정이 부르는 것과 같은 함수다**
    ///   (`MessagePanelLayout.conversationContentHeight` — 두 자리가 갈리면 빈 회색 판이 생긴다).
    @ViewBuilder
    private var bubbleText: some View {
        if let drawn = AingStickerArt.drawable(for: entry.body) {
            stickerBubble(drawn.art)
        } else {
            textBubble
        }
    }

    /// 이모티콘 말풍선. **배경·테두리가 없다** — 카톡 이모티콘처럼 그림만 뜬다(사용자 결정: 말풍선 한 칸을
    /// 통째로 차지하는 큰 그림). 읽음 표시·시각·정렬은 바깥 행이 그리므로 **예전과 똑같다**.
    ///
    /// ★ 보이스오버 문구는 **그림 안에** 있다(`AingStickerArt.labeledImage`). 여기서 `.accessibilityLabel` 로
    ///   붙이지 않는 이유는 그 실측이다 — 꾸밈용 그림에 건 라벨은 AX 요소가 없어 **버려진다**.
    private func stickerBubble(_ art: Image) -> some View {
        art
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: MessagePanelLayout.stickerSide, height: MessagePanelLayout.stickerSide)
    }

    /// 글자 말풍선. **이모티콘 폴백도 이 자리로 온다** — 그때는 날것 토큰(`[아잉:기쁨]`) 대신 이름으로
    /// 읽힌다("아잉이 기쁨"). 같은 저장소가 날것을 "깨진 메시지로 읽힌다"고 적어 둔 그 글자이고,
    /// 폴백의 목적(상대가 뭘 보냈는지 알게)은 이름이 더 잘 달성한다. 평범한 본문은 `preview` 가
    /// **글자 하나도** 바꾸지 않는다. 우클릭 [복사]는 날것 그대로다(붙여넣어 다시 보내면 그림이 된다).
    private var textBubble: some View {
        Text(AingStickerText.preview(for: entry.body))
            .font(.caption)
            .foregroundStyle(entry.isMine ? .white : CheckTheme.primaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                    .fill(entry.isMine ? CheckTheme.accent.opacity(0.85) : Color.white.opacity(0.10))
            )
    }
}

// MARK: - 입력줄

/// 여러 줄 입력 + 글자 수(N/200, **코드포인트**) + [보내기], 그리고 **사라지는 규칙 한 줄**.
///
/// **Enter 가 전송이다**(v0.2.51 — 사용자 지시 2026-09-11 ②: "메세지 입력하고 엔터로 보낼 수 있게 해줘").
/// 줄바꿈은 ⇧Enter 이고, 옛 손버릇인 ⌘Enter 도 그대로 통한다 — [보내기] 버튼이 들고 있는
/// `keyboardShortcut(.return, modifiers: .command)` 이 그것이다. 세 경로(버튼·⌘↩·↩)가 전부
/// **같은 문**(`store.sendDraftMessage()`)을 지나야 판정이 갈리지 않는다.
///
/// Enter 판정 자체는 이 파일이 하지 않는다 — `CheckEditorReturnKey.action` 한 함수다(조합 중 · 못 보내는
/// 상태의 "아무 일도 안 일어남"까지 거기서 결정적으로 잰다). 그 단축키를 **알리는 자리는 placeholder 와
/// 툴팁**이다: 292pt 폭에서 안내 줄을 하나 더 세우면 그만큼 대화가 줄어든다.
struct MessageComposerView: View {
    @Bindable var store: WorkTimerStore
    var rendersPlainText: Bool = false

    /// 아잉이 이모티콘 그리드가 펼쳐져 있는가(v0.3.62). 깃발은 **대화 패널이 들고** 그리드는 대화 자리에 선다.
    ///
    /// `@Binding` 대신 `Binding<Bool>` 프로퍼티인 이유: 기본값 `.constant(false)` 를 줄 수 있어
    /// `MessageComposerView(store:)` 로 쓰는 기존 테스트·스냅샷 호출부가 **무수정으로** 컴파일된다.
    var stickerGridShown: Binding<Bool> = .constant(false)

    private var length: Int { store.messageDraftLength }
    private var isOverflowing: Bool { length > MessageBody.maxLength }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 전송 결과 한 줄. **성공만 초록**이고 나머지는 경고색이다 — 사유별로 색을 더 가르면
            // 사용자가 외워야 할 색만 늘어난다(제보 화면과 같은 규약).
            // 신고 결과(v0.3.34 — "신고를 접수했어요")도 **같은 자리**에 선다: 줄을 하나 더 세우면 대화 패널의 높이 예산이 깨진다.
            if let line = noticeLine {
                Text(line.text)
                    .font(.caption2)
                    .foregroundStyle(line.isPositive ? CheckTheme.working : CheckTheme.pending)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 입력칸 **옆**에 아잉이 버튼 하나(v0.3.62). 같은 줄에 두므로 이 블록의 높이는
            // 예전과 같은 `editorHeight` 고정값이다 — 줄을 하나 더 세우면 그만큼 대화가 깎인다.
            HStack(alignment: .center, spacing: 6) {
                MessageDraftEditor(
                    text: $store.messageDraft,
                    height: MessagePanelLayout.editorHeight,
                    isOverflowing: isOverflowing,
                    rendersPlainText: rendersPlainText,
                    // ★ **대화 패널에 들어오면 커서가 여기 있다**(사용자 지시 2026-09-11 ④: 콕찌르기에서
                    //   말풍선을 눌러 들어가면 마우스 클릭 없이 바로 타자가 되게). 이 칸은 대화 패널이 화면에
                    //   설 때만 존재하므로(`CheckMenuView` 의 `if store.isMessagePanelVisible`) 다른 화면의
                    //   포커스를 훔칠 경로가 없고, [뒤로]로 나갔다 들어오면 뷰가 새로 만들어져 다시 잡는다.
                    focusesWhenShown: true,
                    // ★ 판정도 문도 **버튼과 같은 것**을 넘긴다. 여기서 조건을 다시 세면 Enter 와 버튼이
                    //   서로 다른 날 갈린다(그리고 갈린 쪽은 아무 화면에도 안 보인다).
                    canSendNow: { store.canSendMessageNow },
                    onSend: send
                )
                stickerButton
            }
            HStack(spacing: 8) {
                // **사라지는 규칙을 모르면 사용자는 그것을 버그로 읽는다**(그 오해는 제보로 온다).
                // 줄을 따로 세우지 않고 이 줄의 남는 폭에 9pt 로 얹는다 — 자리를 많이 먹지 않게.
                Text(WorkTimerStore.messageExpiryNotice)
                    .font(.system(size: 9))
                    .foregroundStyle(CheckTheme.secondaryText.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                // 글자 수는 **코드포인트**다(MessageBody.length) — 자소로 세면 이모지에서 서버와 눈금이 갈린다.
                Text("\(length)/\(MessageBody.maxLength)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isOverflowing ? CheckTheme.danger : CheckTheme.secondaryText)
                    .fixedSize()
                Button(action: send) {
                    Text(store.isSendingMessage ? "보내는 중…" : "보내기")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background(
                            Capsule().fill(CheckTheme.accent.opacity(store.canSendMessageNow ? 1 : 0.35))
                        )
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .disabled(!store.canSendMessageNow)
                .keyboardShortcut(.return, modifiers: .command)
                .checkTooltip(sendHelp)
            }
        }
    }

    /// 아잉이 이모티콘 그리드를 펼치는 버튼(v0.3.62). 누르면 대화 자리에 여섯 칸이 선다.
    ///
    /// **그림이 아니라 SF 심볼이다.** 버튼 얼굴에 이모티콘 그림을 쓰면 번들이 빠진 배포본에서
    /// **아무것도 없는 버튼**이 된다(그림을 못 읽는 바로 그 상황이라 폴백도 같이 사라진다).
    /// 저장소의 그림은 512×512 로 구운 진짜 그림이지만(`scripts/bake-aing-stickers.swift`),
    /// 그 사실은 이 결론을 바꾸지 않는다 — 막는 것은 "그림이 없는 배포본"이다.
    ///
    /// 못 보낼 때(상대 없음 · 왕복 중)는 [보내기]와 **같은 모양으로** 흐려진다 — 열어 놓고 골랐는데
    /// 아무 일도 안 일어나는 것이 가장 나쁘다.
    ///
    /// ★ **펼쳐 둔 동안에는 못 보내도 눌린다**(v0.3.62 검토 지적 ①). 펼친 뒤에 왕복이 시작되면 이 버튼은
    ///   더 이상 "보내기 문"이 아니라 **닫기**다 — 그때 같이 잠그면 그리드 쪽 [x] 와 함께 탈출구가 0 이 된다.
    private var stickerButton: some View {
        Button {
            stickerGridShown.wrappedValue.toggle()
        } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(stickerGridShown.wrappedValue ? CheckTheme.accent : CheckTheme.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(stickerGridShown.wrappedValue ? 0.12 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .disabled(!stickerCanToggle)
        .opacity(stickerCanToggle ? 1 : 0.35)
        .accessibilityLabel(stickerGridShown.wrappedValue ? AingStickerText.closeGridLabel : AingStickerText.buttonLabel)
        .checkTooltip(stickerHelp)
    }

    /// 이 버튼이 눌리는가. 펼친 상태면 **언제나** 눌린다(= 닫기), 접힌 상태면 보낼 수 있을 때만 눌린다(= 펼치기).
    var stickerCanToggle: Bool { stickerGridShown.wrappedValue || store.canSendStickerNow }

    /// 이모티콘 버튼의 툴팁. 못 누르는 사유는 [보내기]와 **같은 어휘**로 말한다(사유가 두 어휘면 한쪽이 낡는다).
    ///
    /// **펼친 상태가 사유보다 먼저다**: 그때 이 버튼은 닫기라 눌리는데, "보내는 중이에요"라고 말하면
    /// 눌리는 버튼을 못 누르는 것으로 읽는다.
    var stickerHelp: String {
        if stickerGridShown.wrappedValue { return AingStickerText.closeGridLabel }
        if store.isSendingMessage { return "보내는 중이에요" }
        if store.selectedMessagePeerID == nil { return "콕 찌르기에서 대화 상대를 골라 주세요" }
        return AingStickerText.buttonLabel
    }

    /// 입력칸 위 한 줄: 신고·차단 결과(이 자리 몫)가 먼저, 없으면 전송 결과. 전송하면 신고 결과는 내려간다(`sendDraftMessage`).
    private var noticeLine: (text: String, isPositive: Bool)? {
        if let notice = store.blockReportNotice(on: .message) {
            return (notice.text, !notice.isError)
        }
        guard let notice = store.messageNotice, !notice.isEmpty else { return nil }
        return (notice, notice == WorkTimerStore.messageSentNotice)
    }

    /// 전송 문 — **세 갈래(버튼 · ⌘↩ · ↩)가 전부 이 하나를 지난다.**
    ///
    /// ★ **조합 확정은 `CheckEditorSend.commitThenSend` 안에 있다.** 여기서 직접 확정하지 마라 —
    ///   제보 화면도 **같은 문**을 쓰고(2026-09-11 검토 지적 ②: 확정이 메시지에만 있어서 제보 칸에서는
    ///   마지막 글자가 계속 사라졌다), 확정이 두 곳에 적히면 다음에 또 한쪽만 고쳐진다.
    ///   버튼과 ⌘↩ 은 키 이벤트가 텍스트 뷰로 가지 않아 스스로 확정할 수 없으므로, 그 문이 확정 대상을
    ///   `CheckEditorTextView.focusedEditor` 로 찾는다(그 주석에 왜 그 통로뿐인지 있다).
    ///
    /// 확정 뒤에도 `sendDraftMessage()` 의 `canSendMessageNow` 가 한 번 더 거른다(빈 칸·200자 초과·상대
    /// 없음·전송 중) — 여기서 조건을 다시 세지 않는 이유는 위 `canSendNow` 주석과 같다.
    ///
    /// **근무 여부를 보지 않는다**(v0.3.30 — 서버가 send_message 의 근무 조건을 지웠다). 여기에 근무 선게이트를 얹으면
    /// 스토어·서버를 다 풀어도 비근무 사용자의 [보내기]는 조용히 아무 일도 안 한다(두 겹 게이트의 뷰 쪽 짝).
    /// `private` 이 아닌 이유: 테스트가 **이 문을 그대로** 눌러 비근무 사용자의 전송이 서버까지 가는지 센다
    /// (`sendHelp` 와 같은 근거 — 스토어 함수만 부르면 뷰에 다시 생긴 게이트를 못 잡는다).
    @MainActor
    func send() {
        CheckEditorSend.commitThenSend { store.sendDraftMessage() }
    }

    /// 왜 못 보내는지 — 보낼 수 있으면 **보내는 법**(↩ · 줄바꿈은 ⇧↩)을 말한다. **쿨타임 문구는 여기 없다**
    /// (v0.2.49 — 메시지에 쿨타임이 없다). 남은 사유는 셋뿐이고, 셋 다 사용자가 지금 고칠 수 있는 것이다.
    ///
    /// `private` 이 아닌 이유(2026-09-11 검증 지적): 테스트가 [보내기] 버튼에 **실제로 붙는 이 값**을 되묻는다.
    /// 상수(`MessageDraftEditor.sendHelp`)만 재면 이 계산이 옛 "⌘↩" 문구를 돌려줘도 초록이었다.
    var sendHelp: String {
        if store.isSendingMessage { return "보내는 중이에요" }
        if store.selectedMessagePeerID == nil { return "콕 찌르기에서 대화 상대를 골라 주세요" }
        switch MessageBody.validate(store.messageDraft) {
        case .ok: return MessageDraftEditor.sendHelp
        case .empty: return "보낼 말을 입력해 주세요"
        case .tooLong(let maxLength): return WorkTimerStore.messageTooLongNotice(maxLength: maxLength)
        }
    }
}

/// 입력 에디터.
///
/// **`rendersPlainText` 가 있는 이유**: `ImageRenderer` 는 AppKit 을 감싼 뷰를 못 그린다
/// (이 저장소에서 `Menu` 는 노란 상자로 그려졌고, 제보 창의 `TextEditor`/`TextField(axis:)` 도 같았다).
/// 스냅샷이 빈 상자만 남기면 잘림·겹침을 눈으로 확인한다는 렌더 테스트의 목적이 통째로 사라진다.
/// **앱은 언제나 진짜 `CheckTextEditor` 다** — 기본값이 false 이고 프로덕션에서 true 를 주는 자리는 없다.
///
/// ★ 대체 경로의 padding 은 실물과 **같은 상수**(`CheckEditorMetrics.inset`)여야 한다. 숫자를 따로 적으면
///   스냅샷이 "맞다"고 말하는 자리와 사용자가 보는 자리가 갈리고, 그게 사용자 지시 ③이 생긴 경위다.
struct MessageDraftEditor: View {
    @Binding var text: String
    var height: CGFloat
    var isOverflowing: Bool = false
    var rendersPlainText: Bool = false
    /// 이 칸이 화면에 서면 커서를 가져올 것인가(대화 패널만 true). 기본은 false — 새 칸이 말없이 포커스를
    /// 훔치면 안 된다(`CheckEditorTextView.focusesWhenShown`).
    var focusesWhenShown: Bool = false
    /// 지금 Enter 로 보낼 수 있는가(`store.canSendMessageNow`). 못 보내면 Enter 는 아무 일도 안 한다.
    var canSendNow: () -> Bool = { false }
    /// Enter 가 지나는 문. 버튼·⌘↩ 과 **같은 문**이어야 한다.
    var onSend: () -> Void = {}

    /// 텍스트 뷰가 마지막으로 알린 "그려진 것이 비었나". **nil = 아직 못 들었다**(첫 그림 · 스냅샷 경로).
    /// 판정은 `CheckEditorPlaceholder.isVisible` 하나가 한다 — 규칙을 이 파일에 다시 적지 마라.
    @State private var editorRenderedEmpty: Bool?

    /// placeholder 가 ↩ 를 말한다. 292pt 폭에서는 안내 줄 하나가 대화 한 줄을 먹으므로,
    /// **비어 있을 때만 쓰는 자리**에 단축키 안내를 얹는 것이 가장 싸다(툴팁이 그 답을 한 번 더 말한다).
    static let placeholder = "메시지를 입력하세요 · ↩ 전송"

    /// 보내기 버튼 툴팁. placeholder 는 비어 있을 때만 보이므로, **줄바꿈 방법을 말하는 자리는 여기뿐이다**.
    static let sendHelp = "보내기 (↩) · 줄바꿈은 ⇧↩"

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                        // 초과는 테두리까지 빨갛게 — 카운터 숫자만으로는 못 보고 지나친다.
                        .stroke(isOverflowing ? CheckTheme.danger : CheckTheme.border, lineWidth: 1)
                )
            // placeholder — **뷰에 그려진 것이 없을 때만**. 텍스트 뷰에는 placeholder 가 없다.
            // `text.isEmpty`(스토어 값)로 되돌리지 마라: 조합 중에는 스토어가 비어 있어서 안내 문구가
            // 사용자가 방금 친 글자 위에 겹친다(제보 증상 ② — `CheckEditorPlaceholder` 주석의 실측).
            if CheckEditorPlaceholder.isVisible(storeText: text, editorRenderedEmpty: editorRenderedEmpty) {
                Text(Self.placeholder)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, CheckEditorMetrics.inset.width)
                    .padding(.vertical, CheckEditorMetrics.inset.height)
                    .allowsHitTesting(false)
            }
            if rendersPlainText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, CheckEditorMetrics.inset.width)
                    .padding(.vertical, CheckEditorMetrics.inset.height)
            } else {
                // ⚠︎ 입력 시점 필터를 붙이지 마라. 3글자 시절엔 이모지를 지우는 필터가 있었지만
                //   (자소/코드포인트 눈금 차이 때문에), 지금은 이모지가 정상 입력이고 길이는 코드포인트로 센다.
                //   그리고 조합 중인 한글을 코드가 되쓰면 마지막 글자가 씹힌다 — 그 회귀는 헤드리스로 못 잡는다.
                CheckTextEditor(
                    text: $text,
                    sendsOnReturn: true,
                    focusesWhenShown: focusesWhenShown,
                    canSendNow: canSendNow,
                    onSend: onSend,
                    // 조합 중 표시 글자까지 세어 알려 준다 — 위 placeholder 판정의 유일한 재료다.
                    onRenderedEmptyChange: { editorRenderedEmpty = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height, alignment: .topLeading)
    }
}

// MARK: - 아잉이 이모티콘 고르기 (v0.3.62)

/// 여섯 칸 그리드의 치수. **한 곳에서만 온다** — 칸 크기는 폭과 "남은 높이" 둘 다에 걸려 있어서
/// 뷰 안에 숫자를 흩어 두면 크롬이 큰 조합에서만 아래 줄이 사라진다(그 조합은 테스트가 잘 안 그린다).
enum AingStickerGridLayout {
    /// 가로 칸 수. 여섯 종 ÷ 3 = 두 줄이다(네 줄로 세우면 한 줄이 넷·둘로 갈려 아래 줄이 비뚤어진다).
    static let columns = 3
    static let rows = 2
    /// 칸 사이 간격(pt). 제목 줄과 칸 사이에도 한 번 들어간다.
    static let spacing: CGFloat = 6
    /// 제목 줄(제목 + [닫기])의 높이(pt).
    static let titleHeight: CGFloat = 20
    /// 바깥 여백(pt) — 제목을 접은 좁은 자리에서는 더 얇다(아래 `padding(availableHeight:)`).
    static let roomyPadding: CGFloat = 8
    static let tightPadding: CGFloat = 4
    /// 칸 한 변이 아무리 깎여도 이보다 작아지지 않는다(pt). 이보다 작으면 **누를 수 없는 과녁**이다 —
    /// 넘치는 것은 잘려도 괜찮지만 못 누르는 것은 기능이 없는 것과 같다.
    static let minCell: CGFloat = 28

    /// 제목 줄을 세우는가. **좁으면 접는다** — 제목을 지키려다 아래 줄 세 칸이 잘리면 그 세 표정은
    /// 화면에 없는 기능이 된다.
    ///
    /// ★ **접는 것은 제목 글자뿐이고 [x] 는 접지 않는다**(v0.3.62 검토 지적 ①). 예전엔 "닫는 길은 입력칸 옆
    ///   토글이 들고 있다"고 적혀 있었는데, 그 토글은 **못 보내는 동안 잠긴다**(왕복 0.2~1.5초) — 제목이
    ///   접히는 좁은 크롬에서 그 두 가지가 겹치면 탈출구가 **0** 이 된다(칸도 `.disabled` 라 눌러도 안 닫힌다).
    ///   그래서 좁은 자리에서는 [x] 가 세로를 안 먹는 **겹침**으로 자리를 옮긴다(`AingStickerGridView`).
    ///
    /// 경계는 "제목을 세운 채 두 줄을 최소 과녁으로 그릴 수 있는 가장 낮은 높이"다
    /// (= 여백 16 + 제목 20 + 간격 12 + 과녁 56 = 104pt).
    static func showsTitle(availableHeight: CGFloat) -> Bool {
        availableHeight >= roomyPadding * 2 + titleHeight + spacing * 2 + minCell * CGFloat(rows)
    }

    static func padding(availableHeight: CGFloat) -> CGFloat {
        showsTitle(availableHeight: availableHeight) ? roomyPadding : tightPadding
    }

    /// 칸을 뺀 세로 크롬(pt): 바깥 여백 둘 + (제목 + 그 아래 간격) + 줄 사이 간격 하나.
    static func verticalChrome(availableHeight: CGFloat) -> CGFloat {
        let pad = padding(availableHeight: availableHeight) * 2
        let title = showsTitle(availableHeight: availableHeight) ? titleHeight + spacing : 0
        return pad + title + spacing * CGFloat(rows - 1)
    }

    /// 칸 한 변(pt). 폭이 정하는 값과 **남은 높이**가 정하는 값 중 작은 쪽이다.
    ///
    /// 높이를 보는 이유: 이 그리드는 대화 자리를 쓰고, 그 자리는 크롬(새 버전 배너 + 패치노트 + 주간 목표 편집)에
    /// 76pt 까지 깎인다(`MessagePanelLayout.conversationHeight` 의 부등식 ②). 폭만 보고 64pt 칸을 그리면
    /// 그 조합에서 아래 줄 세 칸이 통째로 사라진다 — 화면에 없는 기능이 된다.
    static func cellSide(availableHeight: CGFloat, width: CGFloat = MessagePanelLayout.contentWidth) -> CGFloat {
        let pad = padding(availableHeight: availableHeight)
        let byWidth = (width - pad * 2 - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = (availableHeight - verticalChrome(availableHeight: availableHeight)) / CGFloat(rows)
        return max(minCell, min(byWidth, byHeight))
    }

    /// 이 높이에서 그리드가 **실제로 쓰는** 세로 길이(pt). 뷰와 테스트가 같은 산식을 본다 —
    /// 테스트가 숫자를 따로 적으면 뷰를 고친 날 테스트만 초록으로 남는다.
    static func usedHeight(availableHeight: CGFloat, width: CGFloat = MessagePanelLayout.contentWidth) -> CGFloat {
        verticalChrome(availableHeight: availableHeight)
            + cellSide(availableHeight: availableHeight, width: width) * CGFloat(rows)
    }
}

/// 아잉이 이모티콘 여섯 칸. **고르면 그 자리에서 전송된다**(사용자 결정 — 이모티콘은 말풍선 한 칸을 통째로
/// 차지하므로 글과 섞지 않는다). 그래서 이 뷰에는 "담기"가 없고 `onPick` 하나뿐이다.
///
/// ★ **전송 문을 여기서 만들지 않는다.** `onPick` 은 대화 패널이 `store.sendSticker(_:)` 로 잇고,
///   그 함수가 기존 전송 문(`sendMessage(to:body:)`)으로 들어간다 — 실패 문구·왕복 겹침 방지·성공 뒤
///   이력 재조회가 전부 그 한 자리에 있다.
///
/// 칸 순서는 `AingSticker.allCases` 그대로다(열거 선언 순서 = 사용자가 보는 차례).
struct AingStickerGridView: View {
    /// 이 그리드가 쓸 수 있는 높이(pt). 대화 패널이 자기 예산에서 계산해 넘긴다.
    let availableHeight: CGFloat
    /// 지금 이모티콘을 보낼 수 있는가(`store.canSendStickerNow`). **칸이 이것을 본다** —
    /// 입력칸 옆 버튼과 같은 판정·같은 흐림이어야 "눌렀는데 아무 일도 안 난다"가 없다.
    var canSend: Bool = true
    let onPick: (AingSticker) -> Void
    let onClose: () -> Void

    private var cell: CGFloat { AingStickerGridLayout.cellSide(availableHeight: availableHeight) }
    /// 좁은 자리에서는 제목을 접는다(여섯 칸이 제목보다 먼저다 — `AingStickerGridLayout.showsTitle`).
    private var showsTitle: Bool { AingStickerGridLayout.showsTitle(availableHeight: availableHeight) }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(cell), spacing: AingStickerGridLayout.spacing),
            count: AingStickerGridLayout.columns
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AingStickerGridLayout.spacing) {
            if showsTitle {
                HStack(spacing: 6) {
                    Text(AingStickerText.gridTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    closeButton
                }
                .frame(height: AingStickerGridLayout.titleHeight)
            }
            // ★ 열을 **고정 폭**(`.fixed(cell)`)으로 둔다: 칸이 여섯뿐이라 게으름은 필요 없지만,
            //   유동 열이 "남는 폭을 나눠 갖는" 기본 동작을 하면 칸이 정사각이 아니게 된다.
            LazyVGrid(columns: columns, spacing: AingStickerGridLayout.spacing) {
                ForEach(AingSticker.allCases, id: \.self) { sticker in
                    AingStickerGridCell(sticker: sticker, side: cell, canSend: canSend) { onPick(sticker) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AingStickerGridLayout.padding(availableHeight: availableHeight))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // ★ 제목이 접힌 좁은 자리의 [x]. **겹쳐서** 둔다 — 세로를 1pt 도 안 쓰므로 여섯 칸이 그대로다.
        //   여기서 안 그리면 탈출구가 0 인 조합이 생긴다(위 `showsTitle` 주석 ★ · 칸은 왕복 중 `.disabled`).
        //   칸을 안 가린다: 76pt 에서 칸 띠는 75…209.5pt 이고(`LazyVGrid` 가 남는 폭 안에서 가운데로 선다 —
        //   렌더 실측) 이 손잡이는 270…288pt 다. 그 둘이 안 겹친다는 것까지 시험이 그림으로 되묻는다.
        .overlay(alignment: .topTrailing) {
            if !showsTitle {
                closeButton.padding(AingStickerGridLayout.tightPadding)
            }
        }
        // 덮개가 **보이스오버에서도** 덮개다 — 밑의 대화는 `.accessibilityHidden` 으로 내려가 있고,
        // 훑기는 이 여섯 칸(과 [x]) 안에서 돈다.
        .accessibilityAddTraits(.isModal)
    }

    /// 닫기 손잡이. **`canSend` 를 보지 않는다** — 못 보내는 상태야말로 닫고 싶은 상태다.
    /// 제목 줄과 겹침 자리가 **같은 하나**를 쓴다(두 벌로 두면 한쪽만 고쳐지는 날이 온다).
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AingStickerText.closeGridLabel)
        .checkTooltip(AingStickerText.closeGridLabel)
    }
}

/// 그리드 한 칸. 그림을 못 읽으면 **이름 글자**로 접는다(`AingSticker` 머리말의 폴백 규약) —
/// 번들이 깨진 배포본에서 "아무것도 없는 여섯 칸"이 되면 고를 수가 없다.
private struct AingStickerGridCell: View {
    let sticker: AingSticker
    let side: CGFloat
    /// 보낼 수 있는가. 못 보낼 때는 **[보내기]와 같은 모양으로** 흐려지고 눌리지 않는다.
    var canSend: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                if let art = AingStickerArt.image(sticker) {
                    art
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(3)
                } else {
                    Text(sticker.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(2)
                }
            }
            .frame(width: side, height: side)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.35)
        .accessibilityLabel(AingStickerText.accessibilityLabel(sticker))
        .checkTooltip(canSend ? AingStickerText.accessibilityLabel(sticker) : AingStickerText.sendingNowNotice)
    }
}
