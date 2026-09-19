import SwiftUI
import CheckCore

// MARK: - 받은 제보 탭 안의 [신고] 칸 (v0.3.34)
//
// SPEC w20 갈래 A-3: "받은 제보" 탭 **안에서** [제보] / [신고] 를 고르는 칩 하나, 그리고 신고 목록.
// 새 창·새 탭 체계를 만들지 않는다 — 운영자 전용 표면은 이미 하나(받은 제보 탭)이고, 그 표면을 만드는 규칙
// (관리자가 아니면 **아예 만들지 않는다** — `CheckFeedbackView.visibleTabs(isAdmin:)`)을 신고도 그대로 탄다:
// 이 파일의 뷰는 전부 `store.showsFeedbackInbox` 가 참일 때만 그려진다(`CheckFeedbackView.body`).
//
// ── [제보] 칸은 예전 그대로다 ──
// [제보] 칸은 예전 `FeedbackInboxView` 를 인자까지 **그대로** 그린다(이 파일은 그 뷰를 건드리지 않는다). 받은 제보 탭에 더해진
// 것은 맨 위 칩 한 줄(`FeedbackInboxSegmentRow`, 28pt)뿐이라 그 아래 전체가 28pt 내려앉을 뿐이고, 그 몫은 세로 예산 안에 든다
// (`ReportAdminLayout.segmentRowHeight` 주석). 기본 칸은 [제보]다 — 받은 제보 탭을 여는 사람이 보던 첫 화면이 바뀌지 않는다.
//
// ── 폭 292pt ──
// 행 하나의 배치: [신고자 → 대상] 한 줄 · 상세(접히면 2줄) · 신고된 메시지 원문 인용 판(접히면 3줄) · 처리 메모 판 ·
// [상태 칩][사유 배지](사람 신고) ··· 시각. 펼치면 메모 칸 → 상태 버튼 넷 → 안내 한 줄.
//
// ★ 이 파일이 그리는 문자열 중 셋(상세 · 신고된 메시지 원문 · 처리 메모)은 **사람이 쓴 글**이다. 어떤 경로로도 로그로 흘리지 마라.
// ★ 이 패널도 `store.displayNow` 를 읽지 않는다(초 단위 무효화 금지 — `CheckFeedbackView` 머리 주석). 시각의 기준은 주입 인자 `now`.

/// 신고 칸의 치수·세로 예산.
enum ReportAdminLayout {
    /// 받은 제보 탭 맨 위 칩 줄이 먹는 높이(칩 22 + 간격 6).
    ///
    /// **세로 예산**(`FeedbackPanelLayout` 의 두 부등식, 팝오버 상한 700pt): 받은 제보 탭의 고정 크롬이 96 → **124pt** 가 된다.
    ///   ① 크롬이 없을 때:    193 + 124 + 300(목록 기본) = 617 ≤ 700
    ///   ② 크롬이 가장 클 때: 193 + 124 +  96(목록 최소) + 241 = 654 ≤ 700
    /// 그래서 목록 예산(`inboxListHeight` · `minInboxListHeight`)은 **그대로 둔다** — 줄이면 [제보] 칸의 목록 높이가 바뀐다.
    /// 여유가 46pt 남는다. 이 줄에 무엇을 더하기 전에 `V0334ReportAdminViewTests` 의 최악 조합 렌더를 다시 돌려라.
    static let segmentRowHeight: CGFloat = 28

    /// 접힌 행의 뼈대(padding 8×2 + 이름 줄 18 + 간격 5 + 메타 줄 18). 추정은 **큰 쪽으로** 잡는다(잘림은 결함, 이른 스크롤은 아니다).
    static let rowBase: CGFloat = 16 + 18 + 5 + 20
    /// caption 한 줄(pt)과 292pt 폭에서 한 줄에 드는 글자 수(한글 22자 남짓 → **20** 으로 나눠 크게 잡는다).
    static let lineHeight: CGFloat = 15
    static let charsPerLine = 20
    /// 펼친 행이 더 먹는 높이: 구분선 1 + 메모 칸(3줄 45 + 세로 padding 12) + 상태 버튼 줄 22 + 안내 두 줄 30 + 간격 6×4.
    static let expandedExtra: CGFloat = 1 + 57 + 22 + 30 + 24
    static let quoteCollapsedLines = 3
    static let detailCollapsedLines = 2

    static func lines(_ text: String?, cap: Int?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        let explicit = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / Double(charsPerLine)))) }
        return cap.map { min($0, explicit) } ?? explicit
    }

    /// 한 행의 **추정** 높이(스크롤을 걸지 말지 정하는 데만 쓴다 — 그리기는 자연 높이다).
    static func rowHeight(_ report: ContentReportAdminItem, expanded: Bool) -> CGFloat {
        var total = rowBase
        let detailLines = lines(report.detail, cap: expanded ? nil : detailCollapsedLines)
        if detailLines > 0 { total += 5 + CGFloat(detailLines) * lineHeight }
        let quoteLines = lines(report.messageBody, cap: expanded ? nil : quoteCollapsedLines)
        // 인용 판: 이름표 13 + 간격 3 + 본문 줄 + 세로 padding 6×2, 그리고 위와의 간격 6.
        if quoteLines > 0 { total += 6 + 13 + 3 + CGFloat(quoteLines) * lineHeight + 12 }
        // 메모 판은 접힌 행에도 그린다 — 제보 답장 판과 같은 산식이다.
        total += FeedbackPanelLayout.replyBlockHeight(report.adminNote)
        if expanded { total += expandedExtra }
        return total
    }

    static func estimatedHeight(_ rows: [ContentReportAdminItem], expandedID: String?) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(0) { $0 + rowHeight($1, expanded: $1.id == expandedID) }
            + CGFloat(rows.count - 1) * FeedbackPanelLayout.rowSpacing
    }
}

// MARK: - 칩 줄 [제보] / [신고]

/// 받은 제보 탭 맨 위의 칸 고르기. 헤더의 탭 칩과 **같은 부품**(`FeedbackTabChip`, 배지 포함)을 쓴다 — 각 칸의 미해결 건수가
/// 칩에 붙어, 운영자는 칸을 열지 않고도 어느 쪽에 손 안 댄 것이 있는지 본다. 0 이면 배지를 안 그린다(부품의 규약).
struct FeedbackInboxSegmentRow: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        HStack(spacing: 6) {
            FeedbackTabChip(
                label: ReportAdminText.feedbackSegment,
                badge: store.feedbackOpenCount,
                isSelected: !store.showsReportAdmin
            ) {
                store.selectInboxSegment(reports: false)
            }
            FeedbackTabChip(
                label: ReportAdminText.reportSegment,
                badge: store.reportOpenCount,
                isSelected: store.showsReportAdmin
            ) {
                store.selectInboxSegment(reports: true)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }
}

// MARK: - [신고] 칸 본체

struct ReportAdminInboxView: View {
    @Bindable var store: WorkTimerStore
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로(`FeedbackListBox` 주석). **앱은 언제나 false** 다.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용: 메모 칸을 순수 SwiftUI 로(`FeedbackNoteField` 주석 — `TextField` 는 ImageRenderer 앞에서 노란 상자다).
    var rendersPlainNoteField: Bool = false
    var extraChromeHeight: CGFloat = 0
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: FeedbackPanelLayout.sectionSpacing) {
            filterRow
            let rows = store.visibleReports
            if rows.isEmpty {
                FeedbackEmptyPanel(
                    state: store.reportAdminEmptyState,
                    showsRetry: store.reportAdminShowsRetry,
                    retry: { store.loadReportAdmin() }
                )
            } else {
                // 목록 예산은 받은 제보 목록과 **같은 값**이다(`ReportAdminLayout.segmentRowHeight` 의 두 부등식).
                FeedbackListBox(
                    contentHeight: ReportAdminLayout.estimatedHeight(rows, expandedID: store.expandedReportID),
                    capHeight: FeedbackPanelLayout.budget(
                        base: FeedbackPanelLayout.inboxListHeight,
                        floor: FeedbackPanelLayout.minInboxListHeight,
                        extraChromeHeight: extraChromeHeight
                    ),
                    clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll
                ) {
                    VStack(alignment: .leading, spacing: FeedbackPanelLayout.rowSpacing) {
                        ForEach(rows) { report in
                            ReportAdminRow(
                                report: report,
                                now: now,
                                isExpanded: store.expandedReportID == report.id,
                                note: $store.reportNoteDraft,
                                rendersPlainNoteField: rendersPlainNoteField,
                                canUpdate: store.canUpdateReport,
                                isUpdating: store.reportUpdatingID == report.id,
                                onToggle: { store.toggleReportExpansion(report.id) },
                                onStatus: { statusTapped(report, $0) }
                            )
                        }
                    }
                }
            }
            notice
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 상태 버튼의 동작. **메모 칸의 조합 중 마지막 음절까지** 싣고 보낸다 — 제보 답장 칸과 같은 문
    /// (`FeedbackReplySend.commitThenSend`)을 지난다. 이 칸도 `TextField`(→ 필드 에디터)라 확정 없이 부르면
    /// "뒤에 한 글자가 사라져요"(v0.3.11 · v0.3.14 에 두 번 난 결함)가 메모에서 그대로 재현된다.
    ///
    /// 칸의 자리(slot)는 답장 칸과 **같은** `.feedbackReply` 다: 두 칸은 같은 팝오버 창에 서고 한 번에 하나만 그려진다
    /// ([제보] / [신고] 칸이 서로를 대신한다) — 자리는 "칸이 선 창"을 적어 두는 것이라 나눌 이유가 없다.
    ///
    /// 이름 있는 값인 이유는 `replyTapped` 와 같다(헤드리스에서 SwiftUI `Button` 을 누를 수 없어 테스트가 이 값을 태운다).
    @MainActor
    func statusTapped(_ report: ContentReportAdminItem, _ status: ContentReportStatus) {
        FeedbackReplySend.commitThenSend { store.applyReportStatus(id: report.id, status: status) }
    }

    /// 목록 아래 안내 한 줄(처리 결과·실패). 성공만 초록이다(제보 칸과 같은 색 규약).
    @ViewBuilder
    private var notice: some View {
        if let notice = store.reportAdminNotice {
            Text(notice)
                .font(.caption2)
                .foregroundStyle(ReportAdminText.isSuccessNotice(notice) ? CheckTheme.working : CheckTheme.pending)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 전체 / 미해결 / 처리 중 / 조치함 / 무시. **왕복 없이** 걸러진다(목록은 이미 전부 받아 왔다).
    /// 칩 다섯이 292pt 안에 선다(가장 긴 "처리 중" 4자 기준 ≈ 260pt).
    private var filterRow: some View {
        HStack(spacing: 5) {
            FeedbackSegmentChip(label: ReportAdminText.filterAll, tint: CheckTheme.accent, isSelected: store.reportFilter == nil) {
                store.selectReportFilter(nil)
            }
            ForEach(ContentReportStatus.reportTransitions, id: \.self) { status in
                FeedbackSegmentChip(label: status.reportLabel, tint: CheckTheme.accent, isSelected: store.reportFilter == status) {
                    store.selectReportFilter(status)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 행

/// 신고 한 건. 접히면 상세 2줄 · 원문 3줄, 펼치면 전부 + 처리 도구.
struct ReportAdminRow: View {
    let report: ContentReportAdminItem
    let now: Date
    let isExpanded: Bool
    @Binding var note: String
    var rendersPlainNoteField: Bool = false
    /// 지금 처리 버튼을 누를 수 있는가(떠 있는 처리가 없다). **판정은 스토어 하나** — 행이 다시 세지 않는다.
    var canUpdate: Bool = true
    /// 이 행의 처리 왕복이 떠 있는가("저장하는 중…").
    var isUpdating: Bool = false
    let onToggle: () -> Void
    /// 기본값이 없다 — 빈 클로저 기본값은 배선을 빠뜨린 호출부를 컴파일시켜 버튼이 아무 일도 안 하게 만든다(`FeedbackInboxRow.onReply` 와 같은 이유).
    let onStatus: (ContentReportStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 5) {
                    names
                    if let detail = report.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(CheckTheme.primaryText)
                            .lineLimit(isExpanded ? nil : ReportAdminLayout.detailCollapsedLines)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let quote = report.messageBody {
                        ReportQuoteBlock(text: quote, isExpanded: isExpanded)
                    }
                    meta
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.accessibilitySummary(report))

            // 처리 메모는 **접힌 행에도** 그린다 — "이 신고는 누가 손댔다"는 목록 차원의 사실이다(제보 답장 판과 같은 판단).
            if let memo = report.adminNote {
                ReportNoteBlock(note: memo, at: report.handledAt, now: now)
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

    /// 신고자 → 대상. 둘 다 이름이 잘리지 않게 **같은 몫**을 나눈다(292pt 에서 각 100pt 남짓).
    private var names: some View {
        HStack(spacing: 5) {
            CheckAvatarView(name: report.reporterName, userID: report.reporterID, avatarURL: report.reporterAvatarURL, size: 16)
            Text(report.reporterName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(report.reporterDeparted ? CheckTheme.secondaryText : CheckTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CheckTheme.secondaryText)
                .accessibilityHidden(true)
            CheckAvatarView(name: report.targetName, userID: report.targetID, avatarURL: report.targetAvatarURL, size: 16)
            Text(report.targetName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    /// 상태 칩 · 사유 배지 · (사람 신고) ··· 접수 시각.
    private var meta: some View {
        HStack(spacing: 6) {
            ReportStatusChip(status: report.status)
            ReportReasonBadge(label: report.reasonLabel)
            if !report.isMessageReport {
                Text(ReportAdminText.personReport)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Text(FeedbackText.ageText(report.createdAt, now: now))
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize()
        }
    }

    /// 펼친 행의 처리 도구: **쓴다(메모) → 고른다(상태 버튼 — 메모를 함께 저장)**, 그리고 마지막 줄이 그 사실과 "메모는 신고자에게
    /// 안 보인다"를 말한다. 버튼은 떠 있는 처리가 있으면 전부 잠긴다(두 처리가 겹치지 않게 — 스토어 `reportUpdatingID`).
    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelDivider()
            ReportNoteField(text: $note, rendersPlainText: rendersPlainNoteField)
            HStack(spacing: 5) {
                ForEach(ContentReportStatus.reportTransitions, id: \.self) { status in
                    FeedbackSegmentChip(
                        label: status.reportLabel,
                        tint: CheckTheme.accent,
                        isSelected: report.status == status
                    ) {
                        onStatus(status)
                    }
                    .disabled(!canUpdate)
                    .opacity(canUpdate ? 1 : 0.5)
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(isUpdating ? ReportAdminText.updating : ReportAdminText.noteHint)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // 처리 시각은 **있을 때만** 말한다(모르는 시각을 지어내지 않는다 — 답장 판과 같은 규약).
                if let handled = report.handledAt {
                    Text(ReportAdminText.handledAge(FeedbackText.ageText(handled, now: now)))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize()
                }
            }
        }
    }

    /// 보이스오버 한 줄(행 버튼이 하위 글자를 한 덩어리로 읽는다). 사람이 쓴 글(상세·원문)은 **싣지 않는다** — 그건 펼쳐서 읽는다.
    static func accessibilitySummary(_ report: ContentReportAdminItem) -> String {
        "\(report.reporterName)님이 \(report.targetName)님을 신고 — \(report.reasonLabel) · \(report.status.reportLabel)"
    }
}

// MARK: - 조각

/// **신고된 메시지 원문**(신고 순간의 스냅숏)을 인용 판으로. 메시지는 24시간 뒤 서버에서 사라지므로 운영자가 볼 수 있는 원문은
/// 이것 하나다 — 판단의 증거라서 다른 글과 **결이 다르게**(왼쪽 경고색 막대 + 안쪽 판) 그린다.
///
/// 막대를 HStack 의 형제가 아니라 `overlay` 로 두는 이유: 이 판은 `fixedSize(vertical:)` 안에 서므로 형제 도형은 제안 높이를
/// 못 받아 자기 기본 높이(10pt)로 쪼그라든다. overlay 는 글 판의 높이를 그대로 받는다.
struct ReportQuoteBlock: View {
    let text: String
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ReportAdminText.quoteTitle)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text(text)
                .font(.caption)
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(isExpanded ? nil : ReportAdminLayout.quoteCollapsedLines)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 9)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(CheckTheme.danger.opacity(0.75))
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CheckTheme.trackFill))
    }
}

/// 처리 메모 판. 제보 답장 판(`FeedbackReplyBlock`)과 같은 결이지만 **글자색이 보조색**이다 — 답장은 사람에게 보낸 편지라 본문색,
/// 이 메모는 운영자 자신의 기록이라 참고값의 결이다.
struct ReportNoteBlock: View {
    let note: String
    let at: Date?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(ReportAdminText.noteTitle)
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
            Text(note)
                .font(.caption)
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

/// 신고 상태 칩. `FeedbackStatusChip` 과 **같은 모양·같은 색 판단**이고 글자만 신고 라벨이다(미해결만 채운다 —
/// 눈이 가야 하는 것은 아직 손 안 댄 신고 하나다. 채운 호박색 위 글자는 그 칩의 대비 실측 그대로 짙은 잉크).
struct ReportStatusChip: View {
    let status: ContentReportStatus

    var body: some View {
        Text(status.reportLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.isOpen ? FeedbackStatusChip.openInk : CheckTheme.secondaryText)
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

/// 사유 배지(스팸 · 욕설·괴롭힘 · 부적절한 내용 · 기타). 색은 하나다 — 사유를 색으로 가르면 운영자가 외울 색만 는다.
/// 글자가 뜻을 말한다(색만으로 정보를 주지 않는다).
struct ReportReasonBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(CheckTheme.danger.opacity(0.85)))
            .fixedSize()
    }
}

/// 처리 메모 칸. `FeedbackNoteField` 와 같은 모양·같은 스냅샷 대체 경로이고, 안내 글자만 다르다(답장이 아니라 메모다).
/// 칸이 선 창을 전송 문에 알리는 표식도 같다(`ReportAdminInboxView.statusTapped` 주석 — 같은 자리 `.feedbackReply`).
struct ReportNoteField: View {
    @Binding var text: String
    var rendersPlainText: Bool = false

    var body: some View {
        Group {
            if rendersPlainText {
                Text(text.isEmpty ? ReportAdminText.notePlaceholder : text)
                    .font(.caption)
                    .foregroundStyle(text.isEmpty ? CheckTheme.secondaryText : CheckTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(ReportAdminText.notePlaceholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .lineLimit(1...3)
                    .foregroundStyle(CheckTheme.primaryText)
                    .background(FeedbackReplyWindowAnchor(slot: .feedbackReply).frame(width: 0, height: 0))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CheckTheme.trackFill))
    }
}

/// 빈 목록 문구의 **결정적 판정**. 제보 `FeedbackEmptyMessage.inbox` 의 네 갈래(실패 · 로딩 · 필터 탓 · 진짜 빈 목록)에
/// **서버 함수 부재**가 하나 더 붙는다 — 제보함은 그 창을 빈 목록으로 접지만, 신고 표는 이미 운영 중이라 "없어요"가 거짓이다
/// (`WorkTimerStore.reportAdminSchemaMissing` 주석). 로딩보다 **앞**에서 본다: 부재 응답은 loaded 를 세우지 않는다.
enum ReportAdminEmptyMessage {
    static func state(
        loaded: Bool,
        failed: Bool,
        schemaMissing: Bool = false,
        filter: ContentReportStatus? = nil,
        unfilteredCount: Int = 0
    ) -> FeedbackEmptyState {
        if failed, !loaded {
            return FeedbackEmptyState(text: ReportAdminText.failed, hint: nil, symbol: FeedbackEmptyMessage.failedSymbol)
        }
        if schemaMissing {
            return FeedbackEmptyState(
                text: ReportAdminText.schemaMissingList,
                hint: ReportAdminText.schemaMissingListHint,
                symbol: FeedbackEmptyMessage.loadingSymbol
            )
        }
        if !loaded {
            return FeedbackEmptyState(text: ReportAdminText.loading, hint: nil, symbol: FeedbackEmptyMessage.loadingSymbol)
        }
        if let filter, unfilteredCount > 0 {
            return FeedbackEmptyState(
                text: ReportAdminText.filterEmpty(filter),
                hint: ReportAdminText.filterEmptyHint,
                symbol: "line.3.horizontal.decrease.circle"
            )
        }
        return FeedbackEmptyState(text: ReportAdminText.empty, hint: ReportAdminText.emptyHint, symbol: "shield")
    }
}
