import SwiftUI

// MARK: - 제보 패널 (v0.2.50)
//
// 사용자 지시(2026-09-10): "제보 창도 쓸데없이 너무 넓어. 제보창도 팝오버 창 안에서만 뜨게 하면서.
// 배치도 좀 효율적으로 해줘." / "제보창에서 새로고침 버튼 없어도 될 듯."
//
// 그 세 문장이 이 파일에서 바뀐 것 전부다:
//   · **별도 창(520×560)이 사라졌다.** 이제 팝오버의 하위 패널이고, 쓸 수 있는 폭은 **292pt** 하나다
//     (본문 열 316 − 카드 padding 12×2). 창 시절 배치는 460pt 최소 폭을 전제로 짜여 있어서 통째로 다시 짰다.
//   · **[새로고침] 버튼이 사라졌다.** 목록을 받는 자리는 패널 열기·전송 성공·상태 변경 성공 셋이고,
//     그 셋이 곧 버튼이 하던 일이다(경로는 `WorkTimerStoreFeedback.openFeedbackPanel` 주석에 적어 뒀다).
//   · **줄 수를 줄였다.** 292pt 에서는 세로 한 줄이 곧 목록 한 행이다 — 아래 `FeedbackPanelLayout` 참고.
//
// 탭 둘: [보내기](모두) · [받은 제보](관리자만).
//
// **관리자 탭을 감추지 않고 아예 만들지 않는다.** `visibleTabs(isAdmin:)` 가 탭 배열 자체를 짧게 돌려주고
// 본문도 그 판정을 한 번 더 지난다(`store.showsFeedbackInbox`). 감추기(`opacity 0`·`hidden`)로 두면
// 접근성 트리와 키보드 순회에는 남아 있어서, 관리자가 아닌 사람이 탭 키만으로 그 표면에 닿을 수 있다.
//
// 그리고 이건 **발견성**이지 보안이 아니다 — 실제 차단은 서버 RLS/RPC 가 한다(WorkTimerStoreFeedback 머리 주석).
// 깃발을 뒤집어 탭을 열어도 `feedback_list` 는 남의 제보를 한 줄도 돌려주지 않는다.
//
// ★ 이 파일이 그리는 문자열 중 하나는 **사용자가 쓴 글**이다. 어떤 경로로도 로그·진단 문자열로 흘리지 마라.
//
// ── 초 단위 무효화 금지 ──
// 이 패널은 `store.displayNow` 를 읽지 않는다. "N분 전"에 쓰는 시각은 주입 인자 `now`(기본값 `Date()`)다 —
// 관찰 대상이 아니라 body 가 돌 때 한 번 읽히는 값이라 팝오버 루트가 매초 다시 그려지지 않는다.

/// 제보 창의 탭. rawValue 는 화면에 나가지 않는다(라벨은 `FeedbackText`).
enum FeedbackTab: String, CaseIterable, Identifiable, Equatable {
    case send
    case inbox

    var id: String { rawValue }

    var label: String {
        switch self {
        case .send: return FeedbackText.sendTab
        case .inbox: return FeedbackText.inboxTab
        }
    }
}

/// 제보 패널의 치수. **한 곳에서만 온다** — 뷰마다 숫자를 적으면 창 높이 상한 예산과 조용히 어긋나고,
/// 그 어긋남은 배너가 뜬 날에만 드러난다(테스트는 배너 없는 화면을 그려서 못 잡는다).
enum FeedbackPanelLayout {
    /// 패널 안쪽 폭(pt) = 본문 열 316 − 카드 padding 12×2.
    static let contentWidth: CGFloat = 292
    /// 블록 사이 간격(pt). 창 시절 12 → 패널 6. **292pt 에서 세로 한 줄은 목록 한 행과 같은 값**이라
    /// (사용자 지시 2 — "배치도 좀 효율적으로") 간격부터 줄였다. 6 은 이 저장소의 다른 패널이 카드 안에서
    /// 쓰는 최소 간격과 같아 낯설지 않다.
    static let sectionSpacing: CGFloat = 6

    /// 본문 에디터의 높이(pt). **산식**: 캡션 한 줄 ≈ 15pt × 4줄 + `TextEditor` 세로 padding 4×2 = 68.
    ///
    /// **왜 8줄(132)에서 4줄(68)로 줄였나**(사용자 지시 2 — "배치도 좀 효율적으로"): 132 는 창(560pt 높이)
    /// 기준이었다. 팝오버는 전부 합쳐 700pt 가 상한이고 그 안에 헤더 카드·푸터·배너가 함께 서므로,
    /// 에디터가 8줄을 쥐면 "내가 보낸 제보" 목록이 한 행도 못 남고 배너가 뜬 날엔 푸터가 잘린다
    /// (실측: 5줄로 잡았을 때 배너 + 목표 편집 조합이 **728pt** 로 상한을 넘었다).
    /// 4줄이면 292pt 폭에서 80자 남짓이 한눈에 들어오고, 넘치는 글은 `TextEditor` 가 자기 안에서 스크롤한다.
    ///
    /// **최소치가 아니라 고정값인 이유**: 이 블록 아래가 목록이라, 여기가 안 정해지면 에디터가 패널을 삼킨다.
    static let editorHeight: CGFloat = 68

    /// 목록 행 높이의 **추정치**(pt). 스크롤을 걸지 말지 정하는 데만 쓴다 — 실제 그리기는 자연 높이다.
    /// 그래서 조금 큰 쪽으로 잡아 둔다: 과소평가하면 목록이 프레임을 넘어 잘리고, 과대평가하면 스크롤이
    /// 조금 일찍 붙을 뿐이다(잘림은 결함이고 이른 스크롤은 아니다).
    static let mineRowHeight: CGFloat = 62
    static let inboxRowHeight: CGFloat = 96
    /// 펼친 행이 더 먹는 높이(전체 본문 + 진단 판 + 답장 칸 + [답장 보내기] 줄 + 상태 칩 + 안내 두 줄).
    /// **v0.3.14 에 190 → 236**: 보내기 버튼 줄(24 + 간격 6)과 안내가 한 줄 늘어난 몫(15 + 6)이다.
    static let inboxExpandedExtra: CGFloat = 236
    static let rowSpacing: CGFloat = 8

    /// 행에 그려진 **답장 판**이 먹는 높이의 추정치(pt). 답장이 없으면 0 이다.
    ///
    /// **길이로 줄 수를 세는 이유**: 이 판은 말줄임을 안 한다(제보자에게는 이게 유일한 수신 경로라
    /// 뒷부분을 잘라 버리면 답장을 반만 받는다). 그래서 500자짜리 답장은 정말로 행을 한 뼘 늘리고,
    /// 그 사실이 스크롤 판정에 들어가지 않으면 목록이 프레임을 넘어 잘린다.
    ///
    /// 292pt 폭에서 caption 한 줄은 한글 22자 남짓 들어가는데 **20자**로 나눈다 — 조금 큰 쪽으로 잡는
    /// 이 파일의 규약 그대로다(과소평가는 잘림이고 과대평가는 이른 스크롤이다).
    static func replyBlockHeight(_ reply: String?) -> CGFloat {
        guard let reply, !reply.isEmpty else { return 0 }
        let lines = max(1, Int(ceil(Double(reply.count) / 20.0)))
        // 이름표 13 + 간격 3 + 본문 줄수 × 15 + 세로 padding 6×2, 그리고 위 블록과의 간격 6.
        return 13 + 3 + CGFloat(lines) * 15 + 12 + 6
    }

    /// 머리(뒤로 + 제목 + 탭)와 본문 사이의 세로 간격(pt).
    static let blockSpacing: CGFloat = 8

    // MARK: 세로 예산
    //
    // **두 부등식이 아래 네 값을 정한다**(2026-09-10 ImageRenderer 실측, 팝오버 상한 700pt).
    // 실측 상수 둘: 패널 **밖** 크롬(바깥 padding + 헤더 카드 + 간격 + 푸터) = **193pt**,
    // 각 탭의 **고정** 크롬(= 스크롤 밖에 서는 것들):
    //   · 보내기      카드 padding 24 + 머리 27 + 8 + 구분선 1 + 8                    = **68pt**
    //   · 받은 제보   위 68 + 필터 줄 22 + 6                                          = **96pt**
    //
    //  ① 크롬이 없을 때:    193 + 고정 + `기본 높이` ≤ 700
    //  ② 크롬이 가장 클 때: 193 + 고정 + `최소 높이` + **241** ≤ 700
    //
    // 241 은 팝오버가 얹을 수 있는 가장 큰 크롬이다: 새 버전 배너(81) + 패치노트 4줄(8 + 4×15 = 68) = 149,
    // 거기에 주간 목표 편집 인라인 행 92. (노트가 4줄로 묶여 있으므로 — `UpdateCheckStore.maxNotes` —
    // 이 값은 **상한이지 추정이 아니다.** 토큰 소모량 행은 하위 패널이 열리면 감춰지므로 여기 없다.)
    //
    // ★ **보내기 탭은 목록이 아니라 본문 전체가 예산을 진다**(v0.2.50 실측에서 배운 것). 처음에는
    //   "내가 보낸 제보" 목록만 깎았는데, 그 탭은 고정 크롬(종류 칩 + 에디터 + 안내/카운터 + 소제목)이
    //   커서 목록을 0 까지 깎아도 최악 조합이 **743pt** 였다. 본문을 통째로 스크롤에 넣으면 어떤 크롬
    //   조합에서도 부등식 ②가 성립하고, **아무것도 화면에서 사라지지 않는다**(밀릴 뿐이다).

    /// 보내기 탭 본문(종류 + 에디터 + 안내/카운터 + 내가 보낸 제보)이 크롬 없이 갖는 높이(pt). 부등식 ①: ≤ 439.
    static let sendBodyHeight: CGFloat = 390
    /// 그 본문이 크롬에 깎여도 남기는 최소 높이(pt). 부등식 ②: ≤ 198.
    /// 180 이면 종류 칩 + 에디터 4줄 + 안내/카운터 줄(= 128pt)이 접힘선 위에 남는다 — **글을 쓰는 일은
    /// 어떤 배너 아래에서도 끝까지 할 수 있다**는 뜻이고, 밀리는 것은 지난 제보 목록뿐이다.
    static let minSendBodyHeight: CGFloat = 180

    /// 받은 제보 목록이 크롬 없이 갖는 최대 높이(pt). 부등식 ①: ≤ 411.
    static let inboxListHeight: CGFloat = 300
    /// 그 목록이 크롬에 깎여도 남기는 최소 높이(pt) = **접힌 행 하나**. 부등식 ②: ≤ 170.
    static let minInboxListHeight: CGFloat = 96

    /// 배너·목표 편집 행이 먹은 높이만큼 깎는다(다른 패널의 `extraChromeHeight` 규약과 같은 계산).
    static func budget(base: CGFloat, floor: CGFloat, extraChromeHeight: CGFloat) -> CGFloat {
        max(floor, base - max(0, extraChromeHeight))
    }

    /// 보내기 탭 본문의 **추정** 자연 높이(스크롤을 걸지 말지 정하는 데만 쓴다).
    /// 조금 큰 쪽으로 잡는다 — 과소평가하면 본문이 프레임을 넘어 잘리고, 과대평가하면 스크롤이 조금
    /// 일찍 붙을 뿐이다(잘림은 결함이고 이른 스크롤은 아니다).
    /// - Parameter rows: "내가 보낸 제보" 행들. **개수가 아니라 행 자체를 받는 이유**는 v0.3.14 다 —
    ///   답장이 달린 행은 답장 판만큼 높고, 그 몫을 안 세면 답장 하나가 목록을 프레임 밖으로 밀어낸다.
    static func sendBodyContentHeight(rows: [FeedbackReport], hasNotice: Bool) -> CGFloat {
        // 종류 22 + 에디터 + 안내/카운터 26 + 구분선 1 + 소제목 15, 그 사이 간격 다섯 번.
        var total: CGFloat = 22 + editorHeight + 26 + 1 + 15 + sectionSpacing * 5
        if hasNotice { total += 15 + sectionSpacing }
        if !rows.isEmpty {
            total += CGFloat(rows.count) * mineRowHeight + CGFloat(rows.count - 1) * rowSpacing + 6
            total += rows.reduce(0) { $0 + replyBlockHeight($1.reply) }
        } else {
            total += 20 + 6   // 빈 목록 한 줄
        }
        return total
    }

    static let corner: CGFloat = 10
}

// MARK: - 패널 본체

/// 제보 패널. 리그·토큰 보드·콕찌르기·내 기록·울트라와 **같은 뼈대**다:
/// 뒤로 버튼 + 제목 + 본문, 그리고 `extraChromeHeight` 를 받아 무스크롤 높이를 줄이는 규약.
struct CheckFeedbackView: View {
    @Bindable var store: WorkTimerStore
    /// 스냅샷 전용 대체 경로(아래 `FeedbackBodyEditor` 주석). **앱은 언제나 false** 다.
    var rendersPlainTextEditor: Bool = false
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다. **ImageRenderer 는 ScrollView 안쪽을 못 그린다** —
    /// 그대로 두면 스냅샷이 머리만 남은 빈 화면이 되어 "잘림·겹침을 눈으로 본다"는 렌더 테스트의 목적이 사라진다.
    /// **앱은 언제나 false** 다.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 배너·목표 편집 행이 목록 위에서 먹은 높이(pt). 그만큼 목록을 깎아 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    /// 상대 시각의 기준. **관찰 대상이 아니다**(파일 머리 주석의 "초 단위 무효화 금지").
    var now: Date = Date()
    let onBack: () -> Void

    /// 지금 그릴 탭들. **관리자가 아니면 `.inbox` 는 배열에 존재하지 않는다**(감춤이 아니라 미생성).
    static func visibleTabs(isAdmin: Bool) -> [FeedbackTab] {
        isAdmin ? [.send, .inbox] : [.send]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FeedbackPanelLayout.blockSpacing) {
            header
            PanelDivider()
            if store.showsFeedbackInbox {
                FeedbackInboxView(
                    store: store,
                    clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                    // 같은 스위치가 본문 에디터와 메모 칸을 함께 순수 SwiftUI 로 바꾼다 —
                    // 둘 다 AppKit 을 감싼 뷰라 ImageRenderer 앞에서 같은 눈가리개가 된다.
                    rendersPlainNoteField: rendersPlainTextEditor,
                    extraChromeHeight: extraChromeHeight,
                    now: now
                )
            } else {
                FeedbackSendView(
                    store: store,
                    rendersPlainTextEditor: rendersPlainTextEditor,
                    clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                    extraChromeHeight: extraChromeHeight,
                    now: now
                )
            }
        }
        .padding(12)
        .panelStyle()
    }

    // MARK: 머리(뒤로 + 제목 + 탭)
    //
    // **[새로고침]이 있던 자리가 여기다.** 292pt 폭에서 아이콘 버튼 하나는 탭 칩 하나만큼을 먹는데,
    // 그 버튼이 하던 일은 이제 "[뒤로] 뒤 다시 [제보]"가 대신한다(스토어 진입점 주석의 세 경로).

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
            Text(FeedbackText.windowTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            // 관리자가 아니면 탭이 **하나뿐**이라 칩을 아예 안 그린다 — 고를 것이 없는 자리에
            // 선택지를 세우면 292pt 폭에서 제목만 밀린다.
            if store.ultraUnlimited {
                ForEach(Self.visibleTabs(isAdmin: true)) { tab in
                    FeedbackTabChip(
                        label: tab.label,
                        // 미해결 배지는 받은 제보 탭에만. 0이면 안 그린다 — 0을 보여 주는 배지는 소음이다.
                        badge: tab == .inbox ? store.feedbackOpenCount : 0,
                        isSelected: (tab == .inbox) == store.showsFeedbackInbox
                    ) {
                        store.selectFeedbackTab(inbox: tab == .inbox)
                    }
                }
            }
        }
    }
}

// MARK: - 보내기 탭

/// 292pt 배치(사용자 지시 2 — "배치도 좀 효율적으로"). 창 시절과 달라진 두 가지:
///  · **카운터가 자기 줄을 잃었다.** 예전엔 에디터 아래 오른쪽 정렬 한 줄을 통째로 썼는데, 그 줄에는
///    카운터 말고 아무것도 없었다. 지금은 자동 첨부 안내 · 카운터 · [보내기]가 **한 줄**을 나눠 쓴다.
///  · **에디터가 8줄에서 5줄로**(FeedbackPanelLayout.editorHeight 의 산식). 그렇게 아낀 세로가
///    "내가 보낸 제보" 목록으로 갔다 — 창 시절 그 목록은 스크롤 맨 아래라 사실상 아무도 못 봤다.
struct FeedbackSendView: View {
    @Bindable var store: WorkTimerStore
    var rendersPlainTextEditor: Bool = false
    var clipsOverflowInsteadOfScroll: Bool = false
    var extraChromeHeight: CGFloat = 0
    var now: Date = Date()

    var body: some View {
        // ★ **스크롤은 하나뿐이다**(위 `FeedbackPanelLayout` 의 세로 예산 주석). 본문 전체가 이 안에
        //   들어가므로 "내가 보낸 제보" 목록은 자기 스크롤을 갖지 않는다 — 두 스크롤이 겹치면 목록 위에서
        //   굴린 휠이 어느 쪽을 움직이는지 사용자가 알 수 없다.
        FeedbackListBox(
            contentHeight: FeedbackPanelLayout.sendBodyContentHeight(
                rows: store.myFeedback,
                hasNotice: store.feedbackNotice != nil
            ),
            capHeight: FeedbackPanelLayout.budget(
                base: FeedbackPanelLayout.sendBodyHeight,
                floor: FeedbackPanelLayout.minSendBodyHeight,
                extraChromeHeight: extraChromeHeight
            ),
            clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll
        ) {
            VStack(alignment: .leading, spacing: FeedbackPanelLayout.sectionSpacing) {
                kindPicker
                FeedbackBodyEditor(
                    text: $store.feedbackDraft,
                    height: FeedbackPanelLayout.editorHeight,
                    rendersPlainText: rendersPlainTextEditor
                )
                actionRow
                // 전송 결과 한 줄. **줄을 따로 쓰는 이유**: 가장 긴 문장이 24자라(레이트리밋) 위 줄에 얹으면
                // 카운터와 버튼을 밀어낸다. 없을 때는 자리도 안 먹는다(대부분의 프레임이 그렇다).
                if let notice = store.feedbackNotice {
                    Text(notice)
                        .font(.caption2)
                        // 성공만 초록. 나머지(레이트리밋·실패·권한)는 경고색이다 — 셋을 색으로 더 가르면
                        // 사용자가 외워야 할 색이 늘어날 뿐이다. 판정은 `FeedbackText.isSuccessNotice` 하나다
                        // (아래 받은 제보 탭의 같은 줄과 **같은 값**을 봐야 한 쪽만 고쳐지는 일이 없다).
                        .foregroundStyle(FeedbackText.isSuccessNotice(notice) ? CheckTheme.working : CheckTheme.pending)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PanelDivider()
                mineSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// [버그] [요청] 캡슐 2개. 기본은 버그다(대부분의 제보가 버그이고, 요청은 의식적으로 고르는 쪽이다).
    private var kindPicker: some View {
        HStack(spacing: 6) {
            ForEach(FeedbackKind.allCases) { kind in
                FeedbackSegmentChip(
                    label: kind.label,
                    tint: kind.isDanger ? CheckTheme.danger : CheckTheme.accent,
                    isSelected: store.feedbackKind == kind
                ) {
                    store.selectFeedbackKind(kind)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 자동 첨부 안내 · 글자 수 · [보내기] 한 줄.
    ///
    /// **안내가 유연 폭을 갖고 카운터·버튼이 고정 폭인 이유**: 그 문장은 "몰래 보내지 않는다"는 약속이라
    /// 말줄임으로 잘리면 안 된다(9pt 로 낮추고 두 줄까지 접히게 둔다). 카운터와 버튼은 글자 수가
    /// 정해져 있어 `fixedSize` 로 자기 크기를 지킨다 — 셋의 우선순위가 곧 이 줄의 계약이다.
    private var actionRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(store.feedbackAutoAttachNotice)
                .font(.system(size: 9))
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(FeedbackComposer.counterText(store.feedbackDraft))
                .font(.caption2.weight(.semibold).monospacedDigit())
                // 900자를 넘으면 경고색. 색만으로 정보를 주지 않게 숫자가 언제나 함께 있다.
                .foregroundStyle(
                    FeedbackComposer.isCounterWarning(store.feedbackDraft)
                        ? CheckTheme.pending
                        : CheckTheme.secondaryText
                )
                .fixedSize()
            FeedbackPrimaryButton(
                label: store.isSendingFeedback ? FeedbackText.sending : FeedbackText.sendAction,
                enabled: store.canSendFeedback,
                action: sendTapped
            )
        }
    }

    /// [보내기] 버튼의 동작.
    ///
    /// ★ **메시지 칸과 같은 문을 지난다**(`CheckEditorSend.commitThenSend`). 여기서 스토어 전송을 바로
    ///   부르면 조합 중인 마지막 음절이 스토어에 아직 없어 그 글자가 빠진 제보가 나간다 —
    ///   2026-09-11 검토 지적 ②가 정확히 그것이었다(메시지 세 갈래만 확정을 지나고 이 버튼은 안 지났다).
    ///
    /// **왜 인라인 클로저가 아니라 이름 있는 값인가**(`private` 이 아닌 이유도 같다): SwiftUI `Button` 은
    /// 이 저장소의 헤드리스 테스트에서 **누를 수 없다** — 합성 NSEvent 도 `accessibilityPerformPress()` 도
    /// 안 먹는 것이 실측돼 있다(`CheckMenuView.swift` 의 같은 자리 주석). 그래서 버튼의 동작을 한 값으로
    /// 빼고, 테스트가 **올린 화면 그대로** 이 값을 태워 서버로 나가는 본문을 잰다
    /// (`V0311KoreanCompositionTests.theFeedbackSendButtonActionShipsTheComposingSyllable`).
    /// 이 자리를 다시 인라인 클로저로 되돌리면 그 테스트가 재는 길이 화면이 지나는 길과 갈린다 —
    /// 소스 문자열 계약만으로는 그 갈림이 안 보인다(계약은 문이 **있는지**만 알지 **불리는지**는 모른다).
    @MainActor
    func sendTapped() {
        CheckEditorSend.commitThenSend { store.sendFeedback() }
    }

    private var mineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(FeedbackText.mineTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
            let mine = store.myFeedback
            if mine.isEmpty {
                FeedbackEmptyLine(
                    state: FeedbackEmptyMessage.mine(
                        loaded: store.feedbackLoaded,
                        failed: store.feedbackFailed
                    ),
                    showsRetry: store.feedbackFailed && !store.feedbackLoaded,
                    retry: { store.loadFeedback() }
                )
            } else {
                // 자기 스크롤이 **없다** — 바깥 본문 스크롤 하나가 전부를 나른다(위 body 주석).
                VStack(alignment: .leading, spacing: FeedbackPanelLayout.rowSpacing) {
                    ForEach(mine) { report in
                        FeedbackMineRow(report: report, now: now)
                    }
                }
            }
        }
    }
}

// MARK: - 받은 제보 탭(관리자)

struct FeedbackInboxView: View {
    @Bindable var store: WorkTimerStore
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용(아래 `FeedbackNoteField` 주석). **앱은 언제나 false** 다.
    var rendersPlainNoteField: Bool = false
    var extraChromeHeight: CGFloat = 0
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: FeedbackPanelLayout.sectionSpacing) {
            filterRow
            let rows = store.visibleFeedback
            if rows.isEmpty {
                // ★ 빈 목록은 **스크롤 밖**에서 그린다. 스크롤 안에서는 제안 높이가 무한이라
                //   `maxHeight: .infinity` 가 크기를 정하지 못하고(에디터가 창 절반을 삼켰던 그 함정),
                //   무엇보다 스크롤할 것이 없는 화면이다.
                FeedbackEmptyPanel(
                    state: FeedbackEmptyMessage.inbox(
                        loaded: store.feedbackLoaded,
                        failed: store.feedbackFailed,
                        filter: store.feedbackFilter,
                        // 필터 전 원본 건수. 이게 0 이면 '필터 탓'이라고 말할 수 없다(진짜 빈 목록이다).
                        unfilteredCount: store.feedbackList.count
                    ),
                    showsRetry: store.feedbackFailed && !store.feedbackLoaded,
                    retry: { store.loadFeedback() }
                )
                // 창 시절엔 이 카드가 창의 83%를 무지로 채웠다(그래서 가운데 정렬이 필요했다). 패널에서는
                // 자연 높이로 그린다 — 아래에 푸터가 바로 붙으므로 넓은 빈 판 자체가 생기지 않는다.
            } else {
                FeedbackListBox(
                    contentHeight: Self.estimatedHeight(rows, expandedID: store.expandedFeedbackID),
                    capHeight: FeedbackPanelLayout.budget(
                        base: FeedbackPanelLayout.inboxListHeight,
                        floor: FeedbackPanelLayout.minInboxListHeight,
                        extraChromeHeight: extraChromeHeight
                    ),
                    clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll
                ) {
                    VStack(alignment: .leading, spacing: FeedbackPanelLayout.rowSpacing) {
                        ForEach(rows) { report in
                            FeedbackInboxRow(
                                report: report,
                                now: now,
                                isExpanded: store.expandedFeedbackID == report.id,
                                note: $store.feedbackNoteDraft,
                                rendersPlainNoteField: rendersPlainNoteField,
                                canSendReply: store.canSendFeedbackReply,
                                isReplySending: store.feedbackReplySending,
                                onToggle: { store.toggleFeedbackExpansion(report.id) },
                                onStatus: { store.applyFeedbackStatusFromEditor(id: report.id, status: $0) },
                                onReply: { replyTapped(report) }
                            )
                        }
                    }
                }
            }
            notice
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// [답장 보내기] 버튼의 동작.
    ///
    /// ★ **보내기 탭의 `sendTapped` 와 같은 모양이지만 문이 다르다.** 그쪽 칸은 `CheckEditorTextView`
    ///   (NSTextView)라 `CheckEditorSend` 가 맡고, 이 칸은 `TextField`(→ `NSTextField`)라 그 문이
    ///   **한 번도 상대해 본 적 없는 계열**이다. v0.3.14 첫 판은 그래서 확정 없이 스토어를 바로 불렀고,
    ///   v0.3.11 의 "뒤에 한 글자가 사라져요"가 이 자리에 그대로 재현됐다(2026-09-12 실측: 화면은
    ///   "확인했어요"인데 서버로 나간 본문은 `{"p_note":"확인했어","p_id":"r1"}`). 근거는 `FeedbackReplySend`.
    ///
    /// **왜 인라인 클로저가 아니라 이름 있는 값인가**: `sendTapped` 와 같은 이유다 — SwiftUI `Button` 은
    /// 헤드리스에서 못 누르므로, 테스트가 **올린 화면 그대로** 이 값을 태워 서버로 나가는 본문을 잰다
    /// (`V0314FeedbackReplyIMETests`). 인라인으로 되돌리면 테스트가 재는 길과 화면이 지나는 길이 갈린다.
    ///
    /// 인자가 id 가 아니라 **행이 그린 제보 그대로**인 이유: 답장은 언제나 "이 행"의 것이고, 그 사실이
    /// 소스에 `store.sendFeedbackReply(id: report.id)` 한 줄로 남아야 한다
    /// (`V0314FeedbackReplyTests.theReplyButtonSitsOnItsOwnLineAndTheOldExcuseIsGone` 이 그 줄을 읽는다).
    @MainActor
    func replyTapped(_ report: FeedbackReport) {
        FeedbackReplySend.commitThenSend { store.sendFeedbackReply(id: report.id) }
    }

    /// 목록의 **추정** 총 높이(스크롤을 걸지 말지 정하는 데만 쓴다 — 위 `inboxRowHeight` 주석).
    static func estimatedHeight(_ rows: [FeedbackReport], expandedID: String?) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        var total = CGFloat(rows.count) * FeedbackPanelLayout.inboxRowHeight
            + CGFloat(rows.count - 1) * FeedbackPanelLayout.rowSpacing
        // 답장 판은 **접힌 행에도** 그려지므로(답장은 편집 상태가 아니라 제보의 성질이다) 전부 센다.
        total += rows.reduce(0) { $0 + FeedbackPanelLayout.replyBlockHeight($1.reply) }
        if let expandedID, rows.contains(where: { $0.id == expandedID }) {
            total += FeedbackPanelLayout.inboxExpandedExtra
        }
        return total
    }

    /// 목록 아래 안내 한 줄(답장 성공·상태 변경 실패 등). 빈 화면과 목록 화면이 **같은 조각**을 쓴다.
    ///
    /// **v0.3.14 에 색이 갈렸다**: 이 줄에 좋은 소식("답장을 보냈어요")이 들어오기 시작했는데, 경고색으로
    /// 그리면 관리자는 답장을 보낼 때마다 뭔가 잘못된 줄 안다. 판정은 보내기 탭과 **같은 값**을 쓴다.
    @ViewBuilder
    private var notice: some View {
        if let notice = store.feedbackNotice {
            Text(notice)
                .font(.caption2)
                .foregroundStyle(FeedbackText.isSuccessNotice(notice) ? CheckTheme.working : CheckTheme.pending)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 전체 / 미해결 / 진행 / 완료 / 보류. 누르면 **왕복 없이** 걸러진다(목록은 이미 전부 받아 왔다).
    /// 칩 다섯이 292pt 안에 선다(라벨 2~3자 × caption2 + 좌우 padding 8×2 + 간격 5×4 ≈ 250pt).
    private var filterRow: some View {
        HStack(spacing: 5) {
            FeedbackSegmentChip(
                label: FeedbackText.filterAll,
                tint: CheckTheme.accent,
                isSelected: store.feedbackFilter == nil
            ) {
                store.selectFeedbackFilter(nil)
            }
            ForEach(FeedbackStatus.known, id: \.self) { status in
                FeedbackSegmentChip(
                    label: status.label,
                    tint: CheckTheme.accent,
                    isSelected: store.feedbackFilter == status
                ) {
                    store.selectFeedbackFilter(status)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 행

/// 보내기 탭 아래의 "내가 보낸 제보" 한 줄. 관리자 행보다 얇다 — 여기서 할 수 있는 일이 없기 때문이다
/// (상태를 보는 것이 전부다). 펼침도 없다.
struct FeedbackMineRow: View {
    let report: FeedbackReport
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            FeedbackKindBadge(kind: report.kind)
            VStack(alignment: .leading, spacing: 3) {
                // **사용자가 쓴 글만** 보여 준다. 앱이 뒤에 붙인 진단 줄(FeedbackDiagnostics)이 이 두 줄을
                // 먹으면, 정작 자기가 뭘 보냈는지가 안 보인다(무엇이 함께 가는지는 위 안내 한 줄이 말한다).
                Text(FeedbackDiagnostics.split(report.body).body)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Text(FeedbackText.ageText(report.createdAt, now: now))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                // ★ **제보자에게 이것이 유일한 수신 경로다**(v0.3.14). v0.3.13 까지 `adminNote` 는 이 파일에
                //   한 번도 나오지 않았고, 그래서 여태 쓴 답장은 아무도 못 봤다. 펼침이 없는 행이라
                //   말줄임도 없다 — 여기서 자르면 제보자는 답장을 반만 받는다.
                //   조건을 **호출부에 두는 이유**: 뷰 안에서 접으면 답장 없는 행에도 VStack 간격 3pt 가
                //   남아, 답장 하나 없는 화면이 조용히 길어진다.
                if let reply = report.reply {
                    FeedbackReplyBlock(note: reply, at: report.adminNoteAt, now: now)
                }
            }
            Spacer(minLength: 4)
            FeedbackStatusChip(status: report.status)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
    }
}

/// 관리자 목록의 한 행. 접히면 본문 2줄, 펼치면 전체 본문 + 메모 + 상태 버튼.
///
/// **292pt 에서 머리 줄을 두 줄로 나눈 것이 v0.2.50 의 배치 변경이다.** 창(460pt 최소 폭) 시절에는
/// [종류 배지][아바타][이름][Spacer][상태 칩]이 한 줄에 섰는데, 292 에서는 이름이 15pt 남짓만 받아
/// 두 글자에서 잘리고 긴 이름은 상태 칩을 밀어냈다. 지금은 배지·아바타·이름이 첫 줄, 상태 칩과 시각이
/// 메타 줄로 내려간다 — 이름에 200pt 넘게 남으므로 어지간한 별명은 온전히 보인다.
struct FeedbackInboxRow: View {
    let report: FeedbackReport
    let now: Date
    let isExpanded: Bool
    @Binding var note: String
    /// 스냅샷 전용(아래 `FeedbackNoteField` 주석). **앱은 언제나 false** 다.
    var rendersPlainNoteField: Bool = false
    /// 지금 [답장 보내기]를 누를 수 있는가. **판정은 스토어 하나**이고 행이 다시 세지 않는다 —
    /// 두 곳에서 세면 "버튼은 살아 있는데 스토어가 조용히 되돌아가는" 조합이 생긴다.
    var canSendReply: Bool = false
    /// 답장 왕복이 떠 있는가(라벨이 "보내는 중…"으로 바뀐다).
    var isReplySending: Bool = false
    let onToggle: () -> Void
    let onStatus: (FeedbackStatus) -> Void
    /// [답장 보내기] 동작. 다른 둘과 같이 **기본값이 없다** — 빈 클로저 기본값을 두면 배선을 빠뜨린
    /// 호출부가 컴파일을 통과하고, 그 화면의 버튼은 눌러도 아무 일도 안 한다(그리고 그건 이 기능이
    /// 고치려던 결함 그 자체다).
    let onReply: () -> Void

    /// 사람이 쓴 글과 앱이 붙인 진단을 가른 두 조각. **한 번만 가른다** — 본문과 진단이 서로 다른 판정에서
    /// 나오면 언젠가 한쪽만 고쳐져 진단이 본문에도 남는다(같은 글자가 두 번 보인다).
    private var parts: FeedbackBodyParts { FeedbackDiagnostics.split(report.body) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        FeedbackKindBadge(kind: report.kind)
                        CheckAvatarView(name: report.authorName, avatarURL: report.authorAvatarURL, size: 18)
                        Text(report.authorName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                    }
                    Text(parts.body)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.primaryText)
                        // 접히면 2줄 말줄임, 펼치면 전부. 클릭으로 펼친다.
                        .lineLimit(isExpanded ? nil : 2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // 메타 줄: 상태 칩이 **이름과 다른 줄**에 있다(구조체 머리 주석의 배치 근거).
                    HStack(spacing: 6) {
                        FeedbackStatusChip(status: report.status)
                        if let version = report.appVersion, !version.isEmpty {
                            Text(version)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(CheckTheme.secondaryText)
                                .lineLimit(1)
                        }
                        if isExpanded, let os = report.osVersion, !os.isEmpty {
                            Text("macOS \(os)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(CheckTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(FeedbackText.ageText(report.createdAt, now: now))
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .fixedSize()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 보낸 답장은 **접힌 행에도** 그린다(진단·macOS 버전과 갈리는 지점이다). 그 둘은 파고들 때만
            // 필요한 참고값이지만, 답장은 "이 제보는 처리됐고 상대도 그 사실을 봤다"는 목록 차원의 사실이다 —
            // 펼쳐야만 보이면 관리자는 자기가 답장한 제보에 또 답장한다.
            if let reply = report.reply {
                FeedbackReplyBlock(note: reply, at: report.adminNoteAt, now: now)
            }

            // 앱이 붙인 진단은 **펼쳤을 때만**, 그리고 사용자가 쓴 문장과 **다른 판에** 그린다
            // (2026-09-10 — 설정 창에 있던 두 줄이 여기로 왔다). macOS 버전 줄이 펼침에서만 나오는 것과 같은 규약이다.
            if isExpanded, let diagnostics = parts.diagnostics {
                FeedbackDiagnosticsBlock(text: diagnostics)
            }

            if isExpanded {
                editor
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
    }

    /// 펼친 행의 처리 도구.
    ///
    /// **v0.3.14 에 [답장 보내기]가 생겼다.** v0.3.13 까지 메모는 상태 칩을 눌러야만 저장됐고, 그 근거는
    /// *"따로 저장하는 버튼을 두면 메모만 쓰고 상태를 안 바꾼 경우가 생기고, 그 상태는 이 화면 어디에도
    /// 표시되지 않는다"* 였다. 그 근거는 **답장 판이 행에 그려지는 순간 사라진다** — 이제 답장만 보낸
    /// 제보도 화면에 그렇게 보인다. 그래서 둘을 같이 고쳤다(하나만 고치면 안 됐다).
    ///
    /// **[답장 보내기]가 상태 칩과 다른 줄에 서는 이유**: 292pt 에 칩이 이미 넷이다(`FeedbackStatus.transitions`
    /// — [완료]를 잘못 눌러도 [미해결]로 되돌릴 수 있어야 한다). v0.2.48 에 바로 이 자리에서 안내 문구가
    /// 말줄임으로 잘렸고, 그래서 줄을 나눴다. 버튼을 그 줄에 도로 밀어 넣으면 같은 사고가 재현된다.
    ///
    /// 세 줄의 순서가 곧 동선이다: **쓴다(칸) → 보낸다(버튼) → 분류한다(칩)**, 그리고 마지막 줄이
    /// "둘은 따로 저장된다"를 말한다.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelDivider()
            FeedbackNoteField(text: $note, rendersPlainText: rendersPlainNoteField)
            // 메모칸 **바로 아래 줄**. 버튼 하나뿐이라 292pt 에서 잘릴 것이 없다.
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                FeedbackPrimaryButton(
                    label: isReplySending ? FeedbackText.replySending : FeedbackText.replyAction,
                    enabled: canSendReply,
                    action: onReply
                )
            }
            HStack(spacing: 5) {
                ForEach(FeedbackStatus.transitions, id: \.self) { status in
                    FeedbackSegmentChip(
                        label: status.label,
                        tint: CheckTheme.accent,
                        isSelected: report.status == status
                    ) {
                        onStatus(status)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(FeedbackText.noteSave)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 조각

/// 목록이 앉는 자리. **내용이 상한보다 짧으면 그 자연 높이 그대로**이고, 넘칠 때만 상한에서 스크롤한다.
///
/// **왜 무조건 상한 높이를 쓰지 않는가**: 짧은 목록에 상한을 씌우면 그 아래가 통째로 빈 판이 되고,
/// 창 시절의 그 결함("83%가 무지")이 패널에서 다시 살아난다. 팝오버는 콘텐츠 높이가 곧 창 높이라
/// 빈 자리를 만들면 창까지 함께 길어진다.
///
/// **왜 스냅샷에서만 클립인가**: `ImageRenderer` 는 `ScrollView` 안쪽을 그리지 않는다(이 저장소의 다른
/// 패널들이 이미 같은 우회를 쓴다). 그대로 두면 스냅샷에 머리만 남아, "잘림·겹침을 사람이 눈으로 본다"는
/// 렌더 테스트의 목적이 통째로 사라진다. 실제로 이 저장소는 그런 눈먼 자리에서 색 결함을 8일간 놓친 적이 있다.
struct FeedbackListBox<Content: View>: View {
    let contentHeight: CGFloat
    let capHeight: CGFloat
    let clipsInsteadOfScrolling: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if contentHeight <= capHeight {
            content().frame(maxWidth: .infinity, alignment: .top)
        } else if clipsInsteadOfScrolling {
            // `.fixedSize(vertical:)` 이 **없으면 스냅샷이 거짓 겹침을 그린다**(2026-09-10 실측):
            // 자식이 바탕 높이를 제안받아 행들이 그 안에 욱여넣어진다. 앱의 ScrollView 는 높이를 무한으로
            // 제안하니 그런 일이 없다 — 즉 그 겹침은 화면에 없는 것이다. 없는 결함을 그리는 스냅샷은
            // 있는 결함을 숨기는 스냅샷만큼 나쁘다.
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                content().frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(height: capHeight)
        }
    }
}

/// 본문 에디터.
///
/// **`rendersPlainText` 가 있는 이유**: `ImageRenderer` 는 AppKit 을 감싼 뷰를 못 그리는 전례가 있다
/// (이 저장소에서 `Menu` 는 노란 상자로 그려졌고, 그 자리는 픽셀 커버리지가 0이라 색 결함이 8일간 안 잡혔다).
/// 스냅샷이 빈 상자만 남기면 잘림·겹침을 눈으로 확인한다는 렌더 테스트의 목적이 통째로 사라진다.
/// 그래서 **렌더 테스트만** 같은 자리·같은 치수의 순수 SwiftUI 대체 경로를 쓴다.
/// **앱은 언제나 진짜 `CheckTextEditor` 다** — 기본값이 false 이고 프로덕션에서 true 를 주는 자리는 없다.
///
/// ★ **여기서 Enter 는 줄바꿈이다**(v0.2.51). 메시지 칸은 Enter 로 보내지만(사용자 지시 2026-09-11 ②)
///   이 칸은 아니다 — 버그 설명은 "무엇을 하다 생겼는지"를 여러 줄로 쓰는 글이라, Enter 전송은 첫 문장만
///   보내고 나머지를 버린다. `sendsOnReturn` 을 true 로 바꾸지 마라.
struct FeedbackBodyEditor: View {
    @Binding var text: String
    var height: CGFloat
    var rendersPlainText: Bool = false

    /// 텍스트 뷰가 마지막으로 알린 "그려진 것이 비었나". **nil = 아직 못 들었다**(첫 그림 · 스냅샷 경로).
    /// 메시지 칸과 **같은 규칙**(`CheckEditorPlaceholder.isVisible`)을 쓴다 — 이 칸에도 같은 증상이 있었다
    /// (조합 중에는 스토어가 비어 있어 안내 문구가 사용자가 친 글자 위에 겹친다).
    @State private var editorRenderedEmpty: Bool?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous)
                        .stroke(CheckTheme.border, lineWidth: 1)
                )
            // placeholder — **뷰에 그려진 것이 없을 때만**. 텍스트 뷰에는 placeholder 가 없다.
            // ★ padding 은 **실제 글자와 같은 상수**다(`CheckEditorMetrics.inset`). 숫자를 여기 따로 적으면
            //   사용자 지시 ③("높이가 안맞아")이 이 칸에서 그대로 되살아난다.
            // ★ `text.isEmpty`(스토어 값)로 되돌리지 마라 — 조합 중 겹침이 그대로 돌아온다.
            if CheckEditorPlaceholder.isVisible(storeText: text, editorRenderedEmpty: editorRenderedEmpty) {
                Text(FeedbackText.placeholder)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .padding(.horizontal, CheckEditorMetrics.inset.width)
                    .padding(.vertical, CheckEditorMetrics.inset.height)
                    .allowsHitTesting(false)
                    .fixedSize(horizontal: false, vertical: true)
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
                // 포커스는 **잡지 않는다**(요청 밖 — 제보 화면은 목록을 먼저 읽는 화면이다).
                CheckTextEditor(text: $text, onRenderedEmptyChange: { editorRenderedEmpty = $0 })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height, alignment: .topLeading)
    }
}

/// 관리자 메모 입력칸. `FeedbackBodyEditor` 와 **같은 이유로** 스냅샷 대체 경로를 갖는다 —
/// 첫 판에서 `TextField(axis: .vertical)` 이 `ImageRenderer` 에 **노란 상자**로 그려졌다
/// (이 저장소가 `Menu` 에서 겪은 것과 같은 눈가리개). 그 자리가 노란 판이면 그 아래 버튼 줄이
/// 겹쳤는지 잘렸는지 아무도 못 본다. **앱은 언제나 진짜 `TextField` 다.**
struct FeedbackNoteField: View {
    @Binding var text: String
    var rendersPlainText: Bool = false

    var body: some View {
        Group {
            if rendersPlainText {
                Text(text.isEmpty ? FeedbackText.notePlaceholder : text)
                    .font(.caption)
                    .foregroundStyle(text.isEmpty ? CheckTheme.secondaryText : CheckTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(FeedbackText.notePlaceholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .lineLimit(1...3)
                    .foregroundStyle(CheckTheme.primaryText)
                    // 이 칸이 선 창을 전송 문에 알려 준다 — **진짜 `TextField` 일 때만**.
                    // 스냅샷 갈래에 끼우면 `ImageRenderer` 가 대체 경로를 쓰는 이유(위 주석)를 스스로 깬다.
                    .background(FeedbackReplyWindowAnchor().frame(width: 0, height: 0))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CheckTheme.trackFill))
    }
}

// MARK: - 답장 칸의 조합 확정 (v0.3.14)

/// 답장을 **조합 중이던 마지막 음절까지** 실어 보내는 문. `CheckEditorSend.commitThenSend` 와 같은 일을
/// 하지만 **다른 뷰 계열**을 상대한다.
///
/// **왜 문이 하나 더 필요한가**(2026-09-12 실측). v0.3.11 의 "뒤에 한 글자가 사라져요"(기모찌 제보)는
/// `CheckEditorTextView`(NSTextView)에서 고쳤고, 그 문은 `CheckEditorTextView.focusedEditor` 로만 대상을
/// 찾는다. 답장 칸은 `TextField`(→ `NSTextField`)라 그 정적 참조에 **한 번도 등록되지 않는다** — 그래서
/// 같은 결함이 새 자리에 그대로 났다. 헤드리스로 화면을 올려 잰 값이 그것이다:
///   · 조합 중 화면/필드는 `"확인했어요"`, 그런데 바인딩(`store.feedbackNoteDraft`)은 `"확인했어"`,
///   · 그 상태에서 [답장 보내기]의 동작을 태우니 서버로 나간 본문이 `{"p_note":"확인했어","p_id":"r1"}`.
/// 마지막 음절이 **제보자에게 안 간 채** 답장이 저장됐다.
///
/// **`NSTextField` 에서 `hasMarkedText()` 를 묻지 마라 — 그 메서드가 없다.** 글자를 실제로 받는 것은
/// 필드가 아니라 **창이 빌려주는 필드 에디터**(`NSTextView`, SwiftUI 에서는 `_SystemTextFieldFieldEditor`)다.
/// 조합도 거기 있고, 실측에서 그 뷰의 `hasMarkedText()` 는 조합 중 `true` · `markedRange` 는 `{4,1}` 이었다.
/// 즉 2벌식 한글은 이 칸에서도 표시 글자를 **쓴다**(`CheckTextEditor.swift` 머리 주석의 재측정과 같은 결론).
///
/// **고른 방법과 버린 방법**(다섯 다 같은 화면에서 재 봤다 — 값은 조합 "요"를 세운 `"확인했어"` 기준):
///   · `unmarkText()` — **된다**(바인딩이 `"확인했어요"` 로). 채택.
///   · `didChangeText()` 만 — **안 된다.** 표시 글자가 남아 있는 동안에는 알림이 와도 바인딩이 `"확인했어"`.
///   · `window.endEditing(for: nil)` — **안 된다.** 불러도 필드 에디터가 첫 응답자로 남고 바인딩은 `"확인했어"`.
///   · `window.makeFirstResponder(nil)` — 된다. 하지만 **커서를 뺏는다**(보낸 뒤 이어 쓰려면 다시 눌러야 한다).
///   · `NSTextInputContext.current?.discardMarkedText()` — **쓰지 않는다.** 이름 그대로 버리는 쪽이고,
///     헤드리스에서는 그 정적 접근자가 애초에 `nil` 이었다(앱이 활성이 아니면 안 켜진다).
///
/// **관측과 추론을 갈라 적는다.** 아래 세 줄 중 헤드리스에서 **값을 바꾼 줄은 `unmarkText()` 하나**다
/// (`inputContext?.discardMarkedText()` 뒤에도 `hasMarkedText()` 는 여전히 true 였다 — 붙어 있는 실제
/// 입력기가 없으니 당연하다). 그래도 첫 줄과 셋째 줄을 **지우지 마라**: 그 둘은 실제 입력기가 붙어 있을
/// 때를 위한 것이고, 근거는 `CheckEditorTextView.commitComposition` 의 같은 순서에 이미 값으로 적혀 있다
/// (①이 없으면 입력기가 방금 확정한 음절을 자기 버퍼에 계속 들고 있어 다음 글자가 거기 다시 붙는다,
/// ③은 ①②가 알림을 안 낼 수 있는 경로의 마지막 못).
/// 여기서 부르는 것은 정적 `NSTextInputContext.current` 가 아니라 **이 에디터의** 입력 문맥이고,
/// 어느 쪽이든 글자는 저장소에 이미 들어 있어 남는다(그 사실은 테스트가 값으로 지킨다 —
/// `theCommitKeepsEveryCharacterItFound`).
@MainActor
enum FeedbackReplySend {
    /// 답장 칸이 서 있는 창(약참조 — 수명은 SwiftUI/AppKit 이 쥔다).
    ///
    /// **왜 창인가**: 필드 에디터는 창이 빌려주는 **한 벌**이고, 지금 누가 쓰고 있는지는 창의 첫 응답자가
    /// 말해 준다. SwiftUI 가 만든 `NSTextField` 는 우리가 서브클래싱할 수 없어 `focusedEditor` 같은
    /// 자기 등록을 못 시킨다 — 그래서 칸 옆에 0pt 표식을 세워 **창만** 받아 온다.
    ///
    /// 행을 접어 칸이 사라져도 이 참조는 굳이 지우지 않는다. 지울 자리(dismantle)는 SwiftUI 가 뷰를
    /// 다시 만드는 경로에서도 불려서 방금 선 표식을 지울 수 있고, 남아 있어도 아래 두 관문
    /// (**필드 에디터인가 · 조합 중인가**)이 전부 걸러 낸다.
    private(set) static weak var host: NSWindow?

    static func register(_ window: NSWindow?) {
        guard let window else { return }
        host = window
    }

    /// 지금 글자를 받고 있는 **필드 에디터**. 답장 칸이 아니면 nil 이다.
    ///
    /// `isFieldEditor` 관문이 두 문을 갈라 놓는다: 본문 칸(`CheckEditorTextView`)은 필드 에디터가 아니라
    /// 여기서 절대 잡히지 않는다. 두 문이 같은 뷰를 두고 다투면 확정이 두 번 일어난다.
    static func activeFieldEditor() -> NSTextView? {
        guard let editor = host?.firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
        return editor
    }

    /// 조합(표시 글자)을 화면에 보이는 그대로 확정한다. 돌려주는 값은 "확정할 것이 있었나"다.
    ///
    /// 확정은 **동기**다(실측: 런루프를 한 턴도 돌리지 않고 읽은 바인딩이 이미 `"확인했어요"` 였다).
    /// 그래서 아래 `commitThenSend` 의 두 줄 사이에 기다릴 것이 없다.
    @discardableResult
    static func commitActiveComposition() -> Bool {
        guard let editor = activeFieldEditor(), editor.hasMarkedText() else { return false }
        editor.inputContext?.discardMarkedText()
        if editor.hasMarkedText() { editor.unmarkText() }
        editor.didChangeText()
        return true
    }

    /// 확정하고, 그다음에 보낸다. **순서가 뜻이다**(`CheckEditorSend` 와 같은 규약) — 확정이 바인딩을
    /// 그 자리에서 올려 주므로 다음 줄의 전송이 **사용자가 화면에서 보던 문장 전체**를 읽는다.
    /// 두 줄을 바꾸지 마라.
    @discardableResult
    static func commitThenSend(_ send: () -> Void) -> Bool {
        let committed = commitActiveComposition()
        send()
        return committed
    }
}

/// 답장 칸이 선 창을 위 문에 알려 주는, 그림을 그리지 않는 0pt 뷰.
/// `TodoBoardWindowVisibility`/`WindowAnchorAccessor` 와 같은 관용구다 — 창에 붙는 순간을 AppKit 이
/// 알려 주므로(`viewDidMoveToWindow`) SwiftUI 재평가 순서에 기대는 레이스가 성립하지 않는다.
struct FeedbackReplyWindowAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AnchorView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 이미 창에 붙어 있으면 지금 잡는다(뷰가 재사용되며 `viewDidMoveToWindow` 가 안 오는 경로).
        FeedbackReplySend.register(nsView.window)
    }

    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            FeedbackReplySend.register(window)
        }
    }
}

/// 운영자가 보낸 **답장**이 앉는 판. **관리자와 제보자가 같은 조각을 본다** — 갈라 두면 언젠가 한쪽만
/// 고쳐지고, 그 한쪽이 제보자 화면이면 아무도 눈치채지 못한다(v0.3.13 까지가 정확히 그 상태였다:
/// 서버는 답장을 내려주는데 화면이 한 번도 그리지 않았다).
///
/// **`FeedbackDiagnosticsBlock` 과 같은 결(안쪽 트랙 색 판)인 이유**: 둘 다 "이 줄은 본문과 읽는 결이
/// 다르다"를 말한다. 다만 글자색은 다르다 — 진단은 보조색이지만 답장은 **사람이 사람에게 쓴 글**이라
/// 본문색으로 읽힌다. 제보자에게 이 판은 참고값이 아니라 받은 편지다.
///
/// 시각은 **있을 때만** 말한다(`adminNoteAt` 이 nil = 서버가 아직 그 컬럼을 모른다). 모르는 시각을
/// `Date()` 로 지어내면 여덟 달 전 답장이 "방금"으로 뜬다 — 모르면 침묵한다.
///
/// ★ `ImageRenderer` 눈가리개 없음: 여기 있는 것은 `Text` 둘뿐이라 AppKit 을 감싼 뷰가 아니다
///   (`FeedbackNoteField` 가 `rendersPlainText` 를 갖는 이유가 그 반대 경우다). 이 판에 입력 위젯을
///   들이지 마라 — 들이는 순간 스냅샷에서 이 자리가 노란 상자가 되고, 그 아래 버튼 줄이 겹쳤는지
///   잘렸는지 아무도 못 본다.
struct FeedbackReplyBlock: View {
    /// 이미 공백을 걷어낸 답장(`FeedbackReport.reply`). 빈 문자열은 여기까지 오지 않는다.
    let note: String
    let at: Date?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(FeedbackText.replyBlockTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.accent)
                Spacer(minLength: 4)
                if let at {
                    Text(FeedbackText.ageText(at, now: now))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize()
                }
            }
            // 말줄임이 **없다**: 제보자에게 이 판이 유일한 수신 경로라 뒤를 자르면 답장을 반만 받는다.
            // 길어진 행 몫은 `FeedbackPanelLayout.replyBlockHeight` 가 스크롤 판정에 넣는다.
            Text(note)
                .font(.caption)
                .foregroundStyle(CheckTheme.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CheckTheme.trackFill))
    }
}

/// 받은 제보에서 **앱이 붙인 줄**이 앉는 판(관리자만 본다).
///
/// **왜 판을 가르는가**(2026-09-10): 이 줄들은 사람이 쓴 문장이 아니라 기계가 붙인 진단이다. 둘을 한
/// 덩어리로 이어 그리면 관리자는 매번 "여기부터가 기계인가"를 눈으로 골라야 하고, 그 사이에서 사용자가
/// 쓴 마지막 문장이 묻힌다. 안쪽 트랙 색 + 고정폭 숫자 + 보조색이 "여기는 읽는 결이 다르다"를 말한다.
///
/// 표식(`FeedbackDiagnostics.marker`) 자체는 그리지 않는다. 판이 이미 그 일을 하고 있는데 구분선까지
/// 그리면 같은 말을 두 번 하는 셈이다.
struct FeedbackDiagnosticsBlock: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(FeedbackText.diagnosticsBlockTitle)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text(text)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(CheckTheme.secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CheckTheme.trackFill))
    }
}

/// 탭 칩(배지 포함). 선택된 탭만 채워 그린다.
struct FeedbackTabChip: View {
    let label: String
    /// 0이면 안 그린다.
    let badge: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : CheckTheme.secondaryText)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(CheckTheme.danger.opacity(0.9)))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    Capsule().fill(CheckTheme.accent.opacity(0.85))
                } else {
                    Capsule().stroke(CheckTheme.border, lineWidth: 1)
                }
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// 종류·필터·상태 전이가 함께 쓰는 캡슐 버튼. 선택되면 채우고, 아니면 테두리만.
/// 292pt 폭에서 칩 다섯이 한 줄에 서야 하므로 좌우 padding 은 창 시절(10)보다 한 급 좁다.
struct FeedbackSegmentChip: View {
    let label: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? .white : CheckTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    if isSelected {
                        Capsule().fill(tint.opacity(0.85))
                    } else {
                        Capsule().stroke(CheckTheme.border, lineWidth: 1)
                    }
                }
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// 종류 배지. 버그는 danger, 요청은 accent — 색과 **글자가 함께** 있다(색만으로 정보를 주지 않는다).
struct FeedbackKindBadge: View {
    let kind: FeedbackKind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill((kind.isDanger ? CheckTheme.danger : CheckTheme.accent).opacity(0.85)))
            .fixedSize()
    }
}

/// 상태 칩. 미해결만 채워 그린다 — 눈이 가야 하는 것은 아직 손 안 댄 제보 하나다.
struct FeedbackStatusChip: View {
    let status: FeedbackStatus

    /// 채워진 미해결 칩의 글자색. **여기만 흰색이 아니다.**
    ///
    /// 실측(2026-09-10, 카드 배경 #181A23 위에 `pending`(#FFB854) 85% 합성 = **#DDA04D**):
    ///   · 흰 글자 = **2.28:1** — 큰 글자 기준(3:1)에도 못 미친다. 10pt 굵은 글자라 더 나쁘다.
    ///   · 이 잉크(#1A1408 근처) = **약 8:1**. (순수 검정으로도 9.2:1 이 이 칩의 물리적 상한이다 —
    ///     검토 메모의 "10 이상"은 나올 수 없는 숫자다. 계산은 V0248FeedbackTests 가 다시 한다.)
    ///
    /// **왜 이 칩만 뒤집는가**(다른 칩 규약은 건드리지 않는다): 이 화면의 나머지 채움색은 `accent`(파랑)와
    /// `danger`(빨강)라 흰 글자가 읽히는 쪽이다. 규약은 "칩 글자는 언제나 흰색"이 아니라
    /// **"채움색에서 읽히는 극을 고른다"** 이고, 밝은 호박색은 그 규약이 검은 극을 가리키는 유일한 자리다.
    /// 여기를 흰색으로 되돌리면 목록에서 **가장 중요한 칩 하나만** 안 읽히는 상태로 돌아간다.
    static let openInk = Color(red: 0.10, green: 0.08, blue: 0.03)

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.isOpen ? Self.openInk : CheckTheme.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background {
                if status.isOpen {
                    Capsule().fill(CheckTheme.pending.opacity(0.85))
                } else {
                    Capsule().stroke(CheckTheme.border, lineWidth: 1)
                }
            }
            .fixedSize()
    }
}

/// [보내기] 버튼. 비활성일 때 자리를 유지한 채 흐려진다(사라졌다 나타나면 화면이 흔들린다).
struct FeedbackPrimaryButton: View {
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CheckTheme.accent.opacity(enabled ? 0.9 : 0.35))
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.7)
    }
}

/// 빈 목록 자리의 한 줄(+ 실패면 [다시 시도]). 이 저장소의 규약 그대로다 —
/// **본문 자리에 동기화 문구를 쓰지 않고**, 실패는 로딩과 다른 문장에 재시도 버튼을 붙인다.
///
/// 이건 **다른 내용 사이에 끼는 한 줄**이다(보내기 탭의 "내가 보낸 제보" 아래). 목록 영역 전체가 비는
/// 자리에는 아래 `FeedbackEmptyPanel` 을 쓴다.
struct FeedbackEmptyLine: View {
    let state: FeedbackEmptyState
    let showsRetry: Bool
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(state.text)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if showsRetry {
                FeedbackRetryButton(action: retry)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 목록 영역이 통째로 빈 자리(받은 제보 탭). **카드 하나가 그 자리를 차지하고 문구는 가운데 선다.**
///
/// **왜 카드인가**: 이 저장소의 빈 상태 규약이 그렇다 — 미니게임 순위판도 빈 목록을 `fieldFill` +
/// `border` 카드로 그려 행이 설 자리를 유지한다(MiniGamePanel).
///
/// **v0.2.50 에서 `maxHeight: .infinity` 를 뺐다.** 창 시절엔 카드가 영역을 채워야 했다(안 그러면 창의
/// 83%가 무지였다). 패널은 콘텐츠 높이가 곧 창 높이라 반대다 — 카드를 늘리면 **팝오버가 그만큼 길어져**
/// 아무것도 없는 화면이 700pt 상한을 갉아먹는다. 자연 높이로 그리면 그 아래에 푸터가 바로 붙는다.
///
/// 보조 한 줄(`hint`)이 필터/진짜-빈-목록을 가른다 — 문구 판정은 `FeedbackEmptyMessage` 하나가 한다.
struct FeedbackEmptyPanel: View {
    let state: FeedbackEmptyState
    let showsRetry: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // 아이콘은 **글자와 함께**만 뜻을 갖는다(색·그림만으로 정보를 주지 않는다는 이 저장소의 규약).
            Image(systemName: state.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(CheckTheme.secondaryText.opacity(0.55))
                .padding(.bottom, 2)
            Text(state.text)
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
            if showsRetry {
                FeedbackRetryButton(action: retry)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: FeedbackPanelLayout.corner, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
    }
}

/// 빈 자리의 [다시 시도]. 한 줄 자리와 카드 자리가 **같은 버튼**을 쓴다 — 둘로 나뉘면 언젠가 한쪽만
/// 고쳐진다(이 저장소의 다른 패널들이 쓰는 `PanelRetryButton` 과 같은 모양이다).
struct FeedbackRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(FeedbackText.retry, systemImage: "arrow.clockwise")
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.accent)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(CheckTheme.accent.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1))
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// 빈 자리에 쓸 문구 한 벌(제목 + 보조 한 줄). 보조 줄은 **없을 수 있다**(로딩·실패에는 안 붙인다 —
/// 그 두 상태에서 할 말은 [다시 시도] 버튼이 이미 하고 있다).
struct FeedbackEmptyState: Equatable {
    let text: String
    let hint: String?
    /// 넓은 빈 판에 쓰는 그림(SF Symbol). **필터로 숨겨진 것과 진짜 빈 것이 다른 그림이다** —
    /// 문구가 갈렸다는 사실을 한 번 더 말해 준다(글자를 대신하지는 않는다).
    var symbol: String = "tray"
}

/// 빈 목록 문구의 **결정적 판정**. 뷰 안에서 갈래를 세면 "실패했는데 '없어요'라고 단정하는" 조합이
/// 언젠가 생긴다(토큰 보드가 실제로 그랬다 — 없다는 단정 옆에 [다시 시도]가 함께 뜬 화면).
///
/// 받은 제보 쪽은 갈래가 **넷**이다. 넷째가 v0.2.48 에 빠져 있던 것이다: 필터를 걸어 아무것도 안 남은
/// 화면과 진짜 빈 화면이 **같은 문장**이라, 관리자는 "필터를 잘못 걸었나"와 "아직 아무도 안 보냈다"를
/// 구분할 수 없었다(필터 칩 다섯은 그대로 떠 있는 채로). 리그 페이지가 이미 세운 규약을 그대로 쓴다 —
/// 필터 전 원본에 행이 있었으면(unfilteredCount > 0) 그건 '숨겨진 것'이지 '없는 것'이 아니다.
enum FeedbackEmptyMessage {
    static func mine(loaded: Bool, failed: Bool) -> FeedbackEmptyState {
        if failed, !loaded { return FeedbackEmptyState(text: FeedbackText.failed, hint: nil, symbol: failedSymbol) }
        if !loaded { return FeedbackEmptyState(text: FeedbackText.loading, hint: nil, symbol: loadingSymbol) }
        return FeedbackEmptyState(text: FeedbackText.mineEmpty, hint: nil)
    }

    /// 실패·로딩의 그림. 빈 자리 그림이 언제나 '빈 상자'면 못 불러온 화면도 "없어요"처럼 보인다.
    static let failedSymbol = "exclamationmark.triangle"
    static let loadingSymbol = "hourglass"

    static func inbox(
        loaded: Bool,
        failed: Bool,
        filter: FeedbackStatus? = nil,
        unfilteredCount: Int = 0
    ) -> FeedbackEmptyState {
        if failed, !loaded { return FeedbackEmptyState(text: FeedbackText.failed, hint: nil, symbol: failedSymbol) }
        if !loaded { return FeedbackEmptyState(text: FeedbackText.loading, hint: nil, symbol: loadingSymbol) }
        // 필터가 걸렸고 원본에는 제보가 있다 = 지금 화면이 빈 것은 **필터 탓**이다.
        // (원본도 비어 있으면 필터를 탓할 수 없다 — 그때는 진짜 빈 목록 문구를 쓴다.)
        if let filter, unfilteredCount > 0 {
            return FeedbackEmptyState(
                text: FeedbackText.inboxFilterEmpty(filter),
                hint: FeedbackText.inboxFilterEmptyHint,
                symbol: "line.3.horizontal.decrease.circle"
            )
        }
        return FeedbackEmptyState(text: FeedbackText.inboxEmpty, hint: FeedbackText.inboxEmptyHint)
    }
}
