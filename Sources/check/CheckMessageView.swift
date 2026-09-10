import SwiftUI

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
//   · Enter 는 **줄바꿈**, 전송은 **⌘Enter**.
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
                let lines = max(1, Int((Double(entry.body.count) / Double(charactersPerBubbleLine)).rounded(.up)))
                total += CGFloat(lines) * 15 + 10   // 줄 높이 + 말풍선 세로 padding 5×2
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

    private var thread: MessageThread? { store.selectedMessageThread }
    private var hasPeer: Bool { store.selectedMessagePeerID != nil }

    var body: some View {
        VStack(spacing: MessagePanelLayout.blockSpacing) {
            header
            PanelDivider()
            conversation
            composer
        }
        .padding(12)
        .panelStyle()
    }

    // MARK: 머리 — 뒤로 + 아바타 + 상대 이름

    /// **[뒤로]가 돌아가는 곳은 이 뷰가 정하지 않는다.** 들어온 문(`messagePanelOrigin`)이 정하고
    /// `closeMessagePanel()` 하나가 실행한다 — 뷰가 정하면 진입 경로가 늘 때마다 여기도 갈라진다.
    private var header: some View {
        HStack(spacing: 8) {
            IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
            if hasPeer {
                CheckAvatarView(name: peerName, avatarURL: store.selectedMessagePeerAvatarURL, size: 22)
            }
            Text(hasPeer ? peerName : "메시지")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            // 아직 못 받았을 때만 뜬다. **본문 자리가 아니라 머리 오른쪽**이다 — 본문 자리에 동기화 문구를
            // 쓰지 않는다는 규약이고, 이미 대화가 보이는 상태에서 갱신이 돌 때도 화면이 안 흔들린다.
            if store.messageHistoryLoading, !store.messageHistoryLoaded {
                Text("불러오는 중…")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize()
            }
        }
    }

    /// 화면에 쓸 상대 이름. 이력·콕찌르기 목록·수신 큐 셋 중 **먼저 아는 곳**에서 온다
    /// (스토어의 파생값 — 한 번도 대화한 적 없는 사람을 처음 누른 경우가 그 셋이 다 필요한 이유다).
    private var peerName: String { store.selectedMessagePeerName ?? "대화" }

    // MARK: 본문 — 말풍선

    @ViewBuilder
    private var conversation: some View {
        // 상한은 크롬 예산이 정하고, 그 안에서 **내용만큼만** 쓴다(짧은 대화가 긴 대화만큼 자리를 먹지 않게).
        let cap = MessagePanelLayout.conversationHeight(extraChromeHeight: extraChromeHeight)
        if let thread, !thread.messages.isEmpty {
            let items = MessageThreadBuilder.timeline(thread.messages, now: now)
            let natural = max(
                MessagePanelLayout.minShownConversationHeight,
                MessagePanelLayout.conversationContentHeight(items)
            )
            MessageConversationView(
                items: items,
                peerUserID: thread.peerUserID,
                lastMessageID: thread.messages.last?.id,
                clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll
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
        MessageComposerView(store: store, rendersPlainText: rendersPlainTextEditor)
    }
}

// MARK: - 대화(말풍선 더미)

/// 한 사람과의 대화. 말풍선을 **시간순으로 쌓고**, 처음 열면 맨 아래(최신)에 있다.
struct MessageConversationView: View {
    /// **이미 계산된** 타임라인(날짜 구분선 포함). 부모가 같은 값으로 틀 높이도 정하므로 여기서 다시
    /// 만들지 않는다 — 두 번 만들면 두 계산이 언젠가 갈리고, 그때 틀과 내용의 높이가 어긋난다.
    let items: [MessageTimelineItem]
    /// 상대가 바뀌었는지 알기 위한 키(스크롤을 맨 아래로 되돌리는 트리거).
    let peerUserID: String
    /// 새 말이 도착했는지 알기 위한 키(같은 트리거의 애니메이션 갈래).
    let lastMessageID: String?
    var clipsInsteadOfScrolling: Bool = false

    /// 맨 아래로 보낼 앵커. 마지막 말풍선 id 를 쓰지 않는 이유는 그 뒤의 아래 여백까지 보이게 하기 위해서다.
    private static let bottomAnchorID = "message-thread-bottom"

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
                    content
                    Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                }
                // 내용이 화면보다 짧아도 **아래에 붙인다**(메신저의 기본 감각이고, 스냅샷의 클립 갈래와
                // 같은 그림이 되게 하는 값이기도 하다 — 두 그림이 다르면 스냅샷으로 아무것도 확인할 수 없다).
                .defaultScrollAnchor(.bottom)
                // 처음 열 때 · 상대를 바꿀 때 · 새 말이 도착할 때 전부 맨 아래로. 셋을 한 함수로 모은 이유는
                // 세 자리가 갈리면 그중 하나만 고쳐지는 날이 오기 때문이다.
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: peerUserID) { _, _ in scrollToBottom(proxy, animated: false) }
                .onChange(of: lastMessageID) { _, _ in scrollToBottom(proxy, animated: true) }
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
            ForEach(items) { item in
                switch item {
                case .day(_, let label):
                    MessageDaySeparator(label: label)
                case .bubble(let entry):
                    MessageBubbleRow(entry: entry)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var clockText: String { MessageThreadBuilder.clockText(entry.createdAt) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if entry.isMine {
                // 보낸 것: 왼쪽을 비우고 시각을 말풍선 **왼쪽**에 둔다(오른쪽 끝은 화면 가장자리다).
                Spacer(minLength: MessagePanelLayout.bubbleOppositeInset)
                timeLabel
                bubble
            } else {
                CheckAvatarView(name: entry.peerName, avatarURL: entry.peerAvatarURL, size: 20)
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

    /// 본문. **폭을 프레임으로 못 박지 않는다** — 그 이유는 `bubbleOppositeInset` 주석에 있다.
    /// 여기서 하는 일은 둘뿐이다: 세로로만 자라게 두고(`fixedSize(vertical:)`), 글자를 감싸는 캡슐을 그린다.
    ///
    /// **`fixedSize(horizontal: true)` 는 금지다** — 200자가 한 줄을 요구해 화면 밖으로 넘친다.
    private var bubble: some View {
        Text(entry.body)
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
            .textSelection(.enabled)
    }
}

// MARK: - 입력줄

/// 여러 줄 입력 + 글자 수(N/200, **코드포인트**) + [보내기], 그리고 **사라지는 규칙 한 줄**.
///
/// **Enter 는 줄바꿈이고 전송은 ⌘Enter 다**(200자를 쓰는 칸이라 Enter 전송은 문장을 반토막 낸다).
/// 그래서 [보내기] 버튼이 `⌘↩` 단축키를 직접 들고 있다 — 단축키와 버튼이 같은 문(`sendDraftMessage`)을
/// 지나야 두 경로가 갈리지 않는다. 그 단축키를 **알리는 자리는 placeholder 와 툴팁**이다: 292pt 폭에서
/// 안내 줄을 하나 더 세우면 그만큼 대화가 줄어든다.
struct MessageComposerView: View {
    @Bindable var store: WorkTimerStore
    var rendersPlainText: Bool = false

    private var length: Int { store.messageDraftLength }
    private var isOverflowing: Bool { length > MessageBody.maxLength }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 전송 결과 한 줄. **성공만 초록**이고 나머지는 경고색이다 — 사유별로 색을 더 가르면
            // 사용자가 외워야 할 색만 늘어난다(제보 화면과 같은 규약).
            if let notice = store.messageNotice, !notice.isEmpty {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(
                        notice == WorkTimerStore.messageSentNotice ? CheckTheme.working : CheckTheme.pending
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MessageDraftEditor(
                text: $store.messageDraft,
                height: MessagePanelLayout.editorHeight,
                isOverflowing: isOverflowing,
                rendersPlainText: rendersPlainText
            )
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
                Button(action: { store.sendDraftMessage() }) {
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
                .help(sendHelp)
            }
        }
    }

    /// 왜 못 보내는지. **쿨타임 문구는 여기 없다**(v0.2.49 — 메시지에 쿨타임이 없다).
    /// 남은 사유는 셋뿐이고, 셋 다 사용자가 지금 고칠 수 있는 것이다.
    private var sendHelp: String {
        if store.isSendingMessage { return "보내는 중이에요" }
        if store.selectedMessagePeerID == nil { return "콕 찌르기에서 대화 상대를 골라 주세요" }
        switch MessageBody.validate(store.messageDraft) {
        case .ok: return "보내기 (⌘↩)"
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
/// **앱은 언제나 진짜 `TextEditor` 다** — 기본값이 false 이고 프로덕션에서 true 를 주는 자리는 없다.
struct MessageDraftEditor: View {
    @Binding var text: String
    var height: CGFloat
    var isOverflowing: Bool = false
    var rendersPlainText: Bool = false

    /// placeholder 가 ⌘↩ 를 말한다. 292pt 폭에서는 안내 줄 하나가 대화 한 줄을 먹으므로,
    /// **비어 있을 때만 쓰는 자리**에 단축키 안내를 얹는 것이 가장 싸다(툴팁이 그 답을 한 번 더 말한다).
    static let placeholder = "메시지를 입력하세요 · ⌘↩ 전송"

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: MessagePanelLayout.corner, style: .continuous)
                        // 초과는 테두리까지 빨갛게 — 카운터 숫자만으로는 못 보고 지나친다.
                        .stroke(isOverflowing ? CheckTheme.danger : CheckTheme.border, lineWidth: 1)
                )
            // placeholder — 비었을 때만. TextEditor 에는 placeholder 가 없다.
            if text.isEmpty {
                Text(Self.placeholder)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }
            if rendersPlainText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            } else {
                // ⚠︎ 입력 시점 필터를 붙이지 마라. 3글자 시절엔 이모지를 지우는 필터가 있었지만
                //   (자소/코드포인트 눈금 차이 때문에), 지금은 이모지가 정상 입력이고 길이는 코드포인트로 센다.
                //   그리고 조합 중인 한글을 코드가 되쓰면 마지막 글자가 씹힌다 — 그 회귀는 헤드리스로 못 잡는다.
                TextEditor(text: $text)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.primaryText)
                    // 에디터가 자기 배경(흰 판)을 그리면 다크 화면에 흰 상자가 뚫린다.
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
        .frame(height: height, alignment: .topLeading)
    }
}
