import SwiftUI

// MARK: - 제보 창 내용 (v0.2.48)
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

/// 제보 창의 치수. **한 곳에서만 온다** — 뷰마다 숫자를 적으면 창 최소 크기(460×420)와 조용히 어긋나고,
/// 그 어긋남은 사용자가 창을 줄였을 때만 드러난다(테스트는 자연 크기로 그려서 못 잡는다).
enum FeedbackLayout {
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
    /// 본문 에디터의 높이 — 캡션 글자로 8줄 남짓이다(요구는 "최소 6줄"). 이보다 낮추면 '긴 글을 쓰는 창'이 아니게 된다.
    ///
    /// **최소치가 아니라 고정값인 이유**: 이 블록은 스크롤 안에 있고, 스크롤 안에서 `Shape` 배경은
    /// 제안 높이가 무한이라 크기가 정해지지 않는다(첫 판에서 에디터가 창 절반을 삼켰다).
    /// 넘치는 글은 `TextEditor` 가 자기 안에서 스크롤한다 — 창을 키우면 목록이 더 보이고 에디터는 그대로다.
    static let editorHeight: CGFloat = 132
    /// 목록 행의 최소 높이(접힌 상태: 종류 배지 + 두 줄 본문 + 메타 한 줄).
    static let rowMinHeight: CGFloat = 62
    static let corner: CGFloat = 10
}

// MARK: - 창 내용

struct CheckFeedbackView: View {
    @Bindable var store: WorkTimerStore
    /// 스냅샷 전용 대체 경로(아래 `FeedbackBodyEditor` 주석). **앱은 언제나 false** 다.
    var rendersPlainTextEditor: Bool = false
    /// 스냅샷 전용: 본문을 ScrollView 대신 클립으로 그린다. **ImageRenderer 는 ScrollView 안쪽을 못 그린다** —
    /// 그대로 두면 스냅샷이 헤더만 남은 빈 화면이 되어 "잘림·겹침을 눈으로 본다"는 렌더 테스트의 목적이 사라진다
    /// (미니게임 창의 `clipsOverflowInsteadOfScroll` 과 같은 우회). **앱은 언제나 false** 다.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 상대 시각의 기준. 기본은 지금이고 렌더 테스트가 고정값을 준다 — 스냅샷이 실행 시각에 흔들리면
    /// 사람이 눈으로 비교할 수 없다.
    var now: Date = Date()

    /// 지금 그릴 탭들. **관리자가 아니면 `.inbox` 는 배열에 존재하지 않는다**(감춤이 아니라 미생성).
    static func visibleTabs(isAdmin: Bool) -> [FeedbackTab] {
        isAdmin ? [.send, .inbox] : [.send]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider()
            if store.showsFeedbackInbox {
                FeedbackInboxView(
                    store: store,
                    clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                    // 같은 스위치가 본문 에디터와 메모 칸을 함께 순수 SwiftUI 로 바꾼다 —
                    // 둘 다 AppKit 을 감싼 뷰라 ImageRenderer 앞에서 같은 눈가리개가 된다.
                    rendersPlainNoteField: rendersPlainTextEditor,
                    now: now
                )
            } else {
                FeedbackSendView(
                    store: store,
                    rendersPlainTextEditor: rendersPlainTextEditor,
                    clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                    now: now
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 헤더(탭 + 새로고침)

    private var header: some View {
        HStack(spacing: 8) {
            ForEach(Self.visibleTabs(isAdmin: store.ultraUnlimited)) { tab in
                FeedbackTabChip(
                    label: tab.label,
                    // 미해결 배지는 받은 제보 탭에만. 0이면 안 그린다 — 0을 보여 주는 배지는 소음이다.
                    badge: tab == .inbox ? store.feedbackOpenCount : 0,
                    isSelected: (tab == .inbox) == store.showsFeedbackInbox
                ) {
                    store.selectFeedbackTab(inbox: tab == .inbox)
                }
            }
            Spacer(minLength: 4)
            IconButton(icon: "arrow.clockwise", help: "새로고침") { store.loadFeedback() }
        }
        .padding(.horizontal, FeedbackLayout.contentPadding)
        .padding(.vertical, 10)
    }
}

// MARK: - 보내기 탭

struct FeedbackSendView: View {
    @Bindable var store: WorkTimerStore
    var rendersPlainTextEditor: Bool = false
    var clipsOverflowInsteadOfScroll: Bool = false
    var now: Date = Date()

    var body: some View {
        FeedbackScrollContainer(clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll) {
            VStack(alignment: .leading, spacing: FeedbackLayout.sectionSpacing) {
                kindPicker
                editorBlock
                // 자동 첨부를 **밝히는** 한 줄. 몰래 보내지 않는다는 약속이 이 문장이다.
                Text(store.feedbackAutoAttachNotice)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                actionRow
                PanelDivider()
                mineSection
            }
            .padding(FeedbackLayout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// [버그] [요청] 캡슐 2개. 기본은 버그다(대부분의 제보가 버그이고, 요청은 의식적으로 고르는 쪽이다).
    private var kindPicker: some View {
        HStack(spacing: 8) {
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

    private var editorBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            FeedbackBodyEditor(
                text: $store.feedbackDraft,
                height: FeedbackLayout.editorHeight,
                rendersPlainText: rendersPlainTextEditor
            )
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Text(FeedbackComposer.counterText(store.feedbackDraft))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    // 900자를 넘으면 경고색. 색만으로 정보를 주지 않게 숫자가 언제나 함께 있다.
                    .foregroundStyle(
                        FeedbackComposer.isCounterWarning(store.feedbackDraft)
                            ? CheckTheme.pending
                            : CheckTheme.secondaryText
                    )
            }
        }
    }

    private var actionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let notice = store.feedbackNotice {
                Text(notice)
                    .font(.caption)
                    // 성공만 초록. 나머지(레이트리밋·실패·권한)는 경고색이다 — 셋을 색으로 더 가르면
                    // 사용자가 외워야 할 색이 늘어날 뿐이다.
                    .foregroundStyle(notice == FeedbackText.sendSuccess ? CheckTheme.working : CheckTheme.pending)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            FeedbackPrimaryButton(
                label: store.isSendingFeedback ? FeedbackText.sending : FeedbackText.sendAction,
                enabled: store.canSendFeedback
            ) {
                store.sendFeedback()
            }
        }
    }

    private var mineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                ForEach(mine) { report in
                    FeedbackMineRow(report: report, now: now)
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
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            filterRow
            let rows = store.visibleFeedback
            if rows.isEmpty {
                // ★ 빈 목록은 **스크롤 밖**에서 그린다. 스크롤 안에서는 제안 높이가 무한이라
                //   `maxHeight: .infinity` 가 크기를 정하지 못하고(에디터가 창 절반을 삼켰던 그 함정),
                //   무엇보다 스크롤할 것이 없는 화면이다.
                emptyArea
            } else {
                FeedbackScrollContainer(clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { report in
                            FeedbackInboxRow(
                                report: report,
                                now: now,
                                isExpanded: store.expandedFeedbackID == report.id,
                                note: $store.feedbackNoteDraft,
                                rendersPlainNoteField: rendersPlainNoteField,
                                onToggle: { store.toggleFeedbackExpansion(report.id) },
                                onStatus: { store.applyFeedbackStatusFromEditor(id: report.id, status: $0) }
                            )
                        }
                        notice
                    }
                    .padding(.horizontal, FeedbackLayout.contentPadding)
                    .padding(.bottom, FeedbackLayout.contentPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// 목록이 빈 화면. 카드가 목록 영역을 채우고 문구는 그 가운데 선다(`FeedbackEmptyPanel` 주석).
    /// 안내 한 줄(`feedbackNotice`)은 카드 **아래**에 남긴다 — 상태 변경 실패 문구가 사라지면 안 된다.
    private var emptyArea: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            notice
        }
        .padding(.horizontal, FeedbackLayout.contentPadding)
        .padding(.bottom, FeedbackLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 목록 아래 안내 한 줄(상태 변경 실패 등). 빈 화면과 목록 화면이 **같은 조각**을 쓴다.
    @ViewBuilder
    private var notice: some View {
        if let notice = store.feedbackNotice {
            Text(notice)
                .font(.caption)
                .foregroundStyle(CheckTheme.pending)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 전체 / 미해결 / 진행 / 완료 / 보류. 누르면 **왕복 없이** 걸러진다(목록은 이미 전부 받아 왔다).
    private var filterRow: some View {
        HStack(spacing: 6) {
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
        .padding(.horizontal, FeedbackLayout.contentPadding)
        .padding(.bottom, 10)
    }
}

// MARK: - 행

/// 보내기 탭 아래의 "내가 보낸 제보" 한 줄. 관리자 행보다 얇다 — 여기서 할 수 있는 일이 없기 때문이다
/// (상태를 보는 것이 전부다). 펼침도 없다.
struct FeedbackMineRow: View {
    let report: FeedbackReport
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
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
            }
            Spacer(minLength: 4)
            FeedbackStatusChip(status: report.status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FeedbackLayout.corner, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: FeedbackLayout.corner, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
    }
}

/// 관리자 목록의 한 행. 접히면 본문 2줄, 펼치면 전체 본문 + 메모 + 상태 버튼.
struct FeedbackInboxRow: View {
    let report: FeedbackReport
    let now: Date
    let isExpanded: Bool
    @Binding var note: String
    /// 스냅샷 전용(아래 `FeedbackNoteField` 주석). **앱은 언제나 false** 다.
    var rendersPlainNoteField: Bool = false
    let onToggle: () -> Void
    let onStatus: (FeedbackStatus) -> Void

    /// 사람이 쓴 글과 앱이 붙인 진단을 가른 두 조각. **한 번만 가른다** — 본문과 진단이 서로 다른 판정에서
    /// 나오면 언젠가 한쪽만 고쳐져 진단이 본문에도 남는다(같은 글자가 두 번 보인다).
    private var parts: FeedbackBodyParts { FeedbackDiagnostics.split(report.body) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        FeedbackKindBadge(kind: report.kind)
                        CheckAvatarView(name: report.authorName, avatarURL: report.authorAvatarURL, size: 20)
                        Text(report.authorName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckTheme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        FeedbackStatusChip(status: report.status)
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
                    HStack(spacing: 6) {
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
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 앱이 붙인 진단은 **펼쳤을 때만**, 그리고 사용자가 쓴 문장과 **다른 판에** 그린다
            // (2026-09-10 — 설정 창에 있던 두 줄이 여기로 왔다). macOS 버전 줄이 펼침에서만 나오는 것과 같은 규약이다.
            if isExpanded, let diagnostics = parts.diagnostics {
                FeedbackDiagnosticsBlock(text: diagnostics)
            }

            if isExpanded {
                editor
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: FeedbackLayout.rowMinHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FeedbackLayout.corner, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: FeedbackLayout.corner, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
    }

    /// 펼친 행의 처리 도구. 메모는 상태 버튼과 **함께** 저장된다 — 따로 저장하는 버튼을 두면
    /// 메모만 쓰고 상태를 안 바꾼 경우가 생기고, 그 상태는 이 화면 어디에도 표시되지 않는다.
    ///
    /// **버튼 줄과 안내 문구가 두 줄로 나뉘어 있는 이유**(v0.2.48 수정): 전이가 셋에서 **넷**으로 늘었다
    /// (`FeedbackStatus.transitions` — [완료]를 잘못 눌러도 [미해결]로 되돌릴 수 있어야 한다).
    /// 한 줄에 칩 넷 + 안내 문구를 같이 두면 창 최소 폭(460pt)에서 안내 문구가 말줄임으로 잘리는데,
    /// 그 문장은 "메모 저장 버튼이 왜 없는가"의 답이라 잘리면 안 된다. 줄을 나누면 칩은 자기 크기를
    /// 유지하고(`fixedSize`) 문구는 온전히 남는다 — 460pt 스냅샷이 그 배치를 눈으로 못 박는다.
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelDivider()
            FeedbackNoteField(text: $note, rendersPlainText: rendersPlainNoteField)
            HStack(spacing: 6) {
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

/// 본문이 앉는 자리. 앱에서는 진짜 `ScrollView` 이고, **스냅샷에서만** 클립으로 바뀐다.
///
/// **왜 필요한가**: `ImageRenderer` 는 `ScrollView` 안쪽을 그리지 않는다(이 저장소의 다른 패널들이
/// 이미 같은 우회를 쓴다 — `CheckMiniGameWindowView.clipsOverflowInsteadOfScroll`). 그대로 두면
/// 스냅샷에 헤더만 남아, "잘림·겹침을 사람이 눈으로 본다"는 렌더 테스트의 목적이 통째로 사라진다.
/// 실제로 이 저장소는 그런 눈먼 자리에서 색 결함을 8일간 놓친 적이 있다.
private struct FeedbackScrollContainer<Content: View>: View {
    let clipsInsteadOfScrolling: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if clipsInsteadOfScrolling {
            // 두 가지가 실측으로 정해졌다(2026-09-10, 펼침 스냅샷에서 첫 행의 배지가 반으로 잘렸다):
            //  ① `.frame(maxHeight: .infinity, alignment: .top)` 로는 **안 된다** — 자식이 프레임보다 크면
            //     SwiftUI 가 가운데로 넘치게 둔다. 빈 판(`Color.clear`)이 제안 크기를 먹고 그 위에 `.top`
            //     정렬 오버레이로 얹어야 윗변이 붙는다.
            //  ② `.clipped()` 를 붙이면 **윗변이 다시 몇 px 잘린다.** 붙이지 않는다 — 넘치는 아래쪽은
            //     어차피 `ImageRenderer` 의 비트맵 경계가 자른다(이 갈래는 스냅샷 전용이다).
            //  ③ `.fixedSize(vertical:)` 이 **없으면 스냅샷이 거짓 겹침을 그린다**(2026-09-10 실측):
            //     overlay 안쪽은 바탕(Color.clear)의 크기를 제안받으므로, 목록이 창보다 길면 SwiftUI 가
            //     행들을 그 높이에 **욱여넣어** 카드가 서로 겹친 그림이 나온다. 앱의 ScrollView 는 높이를
            //     무한으로 제안하니 그런 일이 없다 — 즉 그 겹침은 화면에 없는 것이다. 없는 결함을 그리는
            //     스냅샷은 있는 결함을 숨기는 스냅샷만큼 나쁘다(사람이 매번 "이건 진짜인가"를 따져야 한다).
            //     이상 높이를 쓰게 두고 아래로 넘치게 두면 앱과 같은 배치가 되고, 넘친 부분만 잘린다.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { content().fixedSize(horizontal: false, vertical: true) }
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                content()
            }
        }
    }
}

/// 본문 에디터.
///
/// **`rendersPlainText` 가 있는 이유**: `ImageRenderer` 는 AppKit 을 감싼 뷰를 못 그리는 전례가 있다
/// (이 저장소에서 `Menu` 는 노란 상자로 그려졌고, 그 자리는 픽셀 커버리지가 0이라 색 결함이 8일간 안 잡혔다).
/// 스냅샷이 빈 상자만 남기면 잘림·겹침을 눈으로 확인한다는 렌더 테스트의 목적이 통째로 사라진다.
/// 그래서 **렌더 테스트만** 같은 자리·같은 치수의 순수 SwiftUI 대체 경로를 쓴다.
/// **앱은 언제나 진짜 `TextEditor` 다** — 기본값이 false 이고 프로덕션에서 true 를 주는 자리는 없다.
struct FeedbackBodyEditor: View {
    @Binding var text: String
    var height: CGFloat
    var rendersPlainText: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: FeedbackLayout.corner, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: FeedbackLayout.corner, style: .continuous)
                        .stroke(CheckTheme.border, lineWidth: 1)
                )
            // placeholder — 비었을 때만. TextEditor 에는 placeholder 가 없다.
            if text.isEmpty {
                Text(FeedbackText.placeholder)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rendersPlainText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
            } else {
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
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CheckTheme.trackFill))
    }
}

/// 받은 제보에서 **앱이 붙인 줄**이 앉는 판(관리자만 본다).
///
/// **왜 판을 가르는가**(2026-09-10): 이 줄들은 사람이 쓴 문장이 아니라 기계가 붙인 진단이다. 둘을 한
/// 덩어리로 이어 그리면 관리자는 매번 "여기부터가 기계인가"를 눈으로 골라야 하고, 그 사이에서 사용자가
/// 쓴 마지막 문장이 묻힌다. 안쪽 트랙 색 + 고정폭 숫자 + 보조색이 "여기는 읽는 결이 다르다"를 말한다
/// (설정 창 각주가 쓰던 10pt 고정폭을 그대로 물려받았다 — 운영자가 이미 아는 얼굴이다).
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
            HStack(spacing: 5) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : CheckTheme.secondaryText)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(CheckTheme.danger.opacity(0.9)))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
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
                .padding(.horizontal, 10)
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
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
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
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 28)
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
/// 자리에는 아래 `FeedbackEmptyPanel` 을 쓴다 — 창의 83%가 무지인 채로 왼쪽 위에 한 줄만 서면
/// 그건 '빈 상태'가 아니라 '덜 그려진 화면'으로 읽힌다.
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

/// 목록 영역이 통째로 빈 자리(받은 제보 탭). **카드 하나가 그 영역을 차지하고 문구는 가운데 선다.**
///
/// **왜 카드인가**: 이 저장소의 빈 상태 규약이 그렇다 — 미니게임 순위판도 빈 목록을 `fieldFill` +
/// `border` 카드로 그려 행이 설 자리를 유지한다(MiniGamePanel). 여기서는 행 하나가 아니라 목록 전체가
/// 비므로 카드도 영역을 채운다.
///
/// **왜 가운데인가**(2026-09-10 실측): 첫 판은 좌측 상단 한 줄이었고 그 아래 465pt(창의 83%)가 빈 판이었다.
/// 문구가 목록의 시작점에만 있으면 눈은 그 아래 여백을 '아직 안 그려진 목록'으로 읽는다.
///
/// 보조 한 줄(`hint`)이 필터/진짜-빈-목록을 가른다 — 문구 판정은 `FeedbackEmptyMessage` 하나가 한다.
struct FeedbackEmptyPanel: View {
    let state: FeedbackEmptyState
    let showsRetry: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 아이콘은 **글자와 함께**만 뜻을 갖는다(색·그림만으로 정보를 주지 않는다는 이 저장소의 규약).
            // 여기서 하는 일은 넓은 빈 판에 시선이 앉을 자리를 만드는 것 하나다.
            Image(systemName: state.symbol)
                .font(.system(size: 26, weight: .light))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: FeedbackLayout.corner, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: FeedbackLayout.corner, style: .continuous)
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
