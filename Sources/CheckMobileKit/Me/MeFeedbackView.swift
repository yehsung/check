#if os(iOS)
import CheckCore
import SwiftUI

/// 제보: 쓰기(종류 · 본문 1000자 · 자동 첨부 안내) + 내가 보낸 제보(상태 · 답장). 딥링크 `feedback/<id>` 는 그 제보를 펼쳐 보인다.
struct MeFeedbackView: View {
    let store: MeStore
    @State private var expanded: Set<String> = []
    @FocusState private var editorFocused: Bool

    var body: some View {
        @Bindable var store = store
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    composeCard(store: store)
                        .id("compose")
                    VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                        SectionHeader(FeedbackText.mineTitle)
                        listContent
                    }
                    .id("mine")
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.rowSpacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.loadFeedback() }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(MeText.feedbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                store.feedbackDidAppear()
                revealFocusedReport(proxy)
                if let target = MeDemoHooks.scrollTarget() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { proxy.scrollTo(target, anchor: .top) }
                }
            }
            .onDisappear { store.feedbackDidDisappear() }
            // 두 계기 — 목록이 새로 왔다(처음 연 화면) · 딥링크·알림이 또 가리켰다(이미 떠 있는 화면, 목록은 그대로일 수 있다).
            .onChange(of: store.feedbackList) { _, _ in revealFocusedReport(proxy) }
            .onChange(of: store.feedbackFocusSerial) { _, _ in revealFocusedReport(proxy) }
        }
    }

    /// 가리킨 제보가 목록에 있으면 펼치고 그 줄로 스크롤한다(없으면 목록이 올 때 다시 불린다).
    private func revealFocusedReport(_ proxy: ScrollViewProxy) {
        guard let focused = store.focusedReport else { return }
        expanded.insert(focused.id)
        DispatchQueue.main.async { proxy.scrollTo(focused.id, anchor: .top) }
    }

    private func composeCard(store: MeStore) -> some View {
        @Bindable var store = store
        return AingCard {
            Picker(MeText.feedbackKindLabel, selection: $store.feedbackKind) {
                ForEach(FeedbackKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.feedbackDraft)
                    .focused($editorFocused)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(MobileTheme.fill))
                    .accessibilityLabel(Text("제보 내용"))
                if store.feedbackDraft.isEmpty {
                    Text(FeedbackText.placeholder)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label3Text)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(store.feedbackAutoAttachNotice)
                    .font(.caption)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(FeedbackComposer.counterText(store.feedbackDraft))
                    .font(MobileTheme.number(.caption))
                    .monospacedDigit()
                    .foregroundStyle(FeedbackComposer.isCounterWarning(store.feedbackDraft) ? MobileTheme.pending : MobileTheme.label2)
                    .fixedSize()
            }
            if let notice = store.feedbackNotice {
                InlineNotice(text: notice, kind: FeedbackText.isSuccessNotice(notice) ? .info : .warning)
            }
            AingButton(
                store.isSendingFeedback ? FeedbackText.sending : FeedbackText.sendAction,
                systemImage: store.isSendingFeedback ? nil : "paperplane.fill",
                kind: .filled, size: .lg, fillsWidth: true
            ) {
                editorFocused = false
                Task { await store.sendFeedback() }
            }
            .disabled(!store.canSendFeedback)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        let state = store.feedbackState
        if store.feedbackList.isEmpty {
            AingCard {
                if state.isLoading, !state.hasLoaded {
                    LoadingRow(FeedbackText.loading)
                } else if state.hasFailed, !state.hasLoaded {
                    LoadFailureRow(FeedbackText.failed, isRetrying: state.isLoading) {
                        Task { await store.loadFeedback() }
                    }
                } else {
                    Text(FeedbackText.mineEmpty)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                }
            }
        } else {
            ForEach(store.feedbackList) { report in
                MeFeedbackRow(
                    report: report,
                    now: store.context.clock.now(),
                    isExpanded: expanded.contains(report.id),
                    isFocused: store.focusedReportID == report.id,
                    isUnseenReply: store.isUnseenReply(report),
                    toggle: {
                        if expanded.contains(report.id) { expanded.remove(report.id) } else { expanded.insert(report.id) }
                    }
                )
                .id(report.id)
            }
        }
    }
}

struct MeFeedbackRow: View {
    let report: FeedbackReport
    let now: Date
    let isExpanded: Bool
    let isFocused: Bool
    let isUnseenReply: Bool
    let toggle: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 8) {
                // 칩은 상태 하나(뜻 색 — 초록 금지). 종류는 칩이 아니라 시각 앞 글자로(한 카드에 칩 셋이던 것, w14 비평 29).
                HStack(alignment: .center, spacing: 6) {
                    statusChip
                    Text("\(report.kind.label) · \(FeedbackText.ageText(report.createdAt, now: now))")
                        .font(.caption)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Text(report.body)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(isExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if isExpanded, let version = report.appVersion, !version.isEmpty {
                    Text(MeText.feedbackVersionLine(appVersion: version, osVersion: report.osVersion))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label2)
                }
                if let reply = report.reply {
                    VStack(alignment: .leading, spacing: 4) {
                        replyHeader
                        Text(reply)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label)
                            .lineLimit(isExpanded ? nil : 3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 카드 안 카드(파랑 틴트 상자) 대신 왼쪽 선 하나로 답장을 가른다.
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(MobileTheme.accentLine)
                            .frame(width: 3)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(MobileTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
                        .strokeBorder(MobileTheme.accent, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(isExpanded ? "눌러서 접기" : "눌러서 펼치기"))
    }

    /// 답장 머리: '답장' · '새 답장' 캡슐 · 시각. 접근성 글자 크기에서는 줄로 나눈다 — 가로 그대로면 '답/장'·'21시간/전'이 꺾이고
    /// 캡슐이 원으로 눌려 글자가 밖으로 넘쳤다(AX5 실측). 캡슐은 늘 제 크기(`fixedSize`)를 지킨다.
    @ViewBuilder
    private var replyHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                replyTitle
                if isUnseenReply { replyBadge }
                replyTime
            }
        } else {
            HStack(spacing: 6) {
                replyTitle
                if isUnseenReply { replyBadge }
                Spacer(minLength: 4)
                replyTime
            }
        }
    }

    private var replyTitle: some View {
        Label(FeedbackText.replyBlockTitle, systemImage: "arrowshape.turn.up.left.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(MobileTheme.label2)
            .fixedSize()
    }

    private var replyBadge: some View {
        AingChip(text: MeText.feedbackReplyBadge, tint: MobileTheme.accent)
    }

    @ViewBuilder
    private var replyTime: some View {
        if let at = report.adminNoteAt {
            Text(FeedbackText.ageText(at, now: now))
                .font(.caption)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 상태 칩: 미해결 = 대기(앰버) · 진행 = 파랑 · 완료·보류 = 회색(`MeText.feedbackStatusTone`).
    @ViewBuilder
    private var statusChip: some View {
        switch MeText.feedbackStatusTone(report.status) {
        case .pending: AingChip(text: report.status.label, tint: MobileTheme.pending)
        case .accent: AingChip(text: report.status.label, tint: MobileTheme.accent)
        case .neutral: AingChip(text: report.status.label, tint: MobileTheme.label2, background: MobileTheme.fill)
        }
    }
}
#endif
