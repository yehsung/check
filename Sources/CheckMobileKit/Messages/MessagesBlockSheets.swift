#if os(iOS)
import CheckCore
import SwiftUI

/// 차단 확인 시트와 신고 시트(앱스토어 심사 지침 1.2 — 신고 창구 · 차단 기능).
///
/// 둘 다 **불투명 시트**다(`presentationBackground(surface)`) — 까닭은 기권 확인·계정 삭제와 같다(`AingConfirmSheet` 주석):
/// 알림창 재질이 뒤 화면 색을 빨아들여 위험한 동작의 빨간 글자 대비가 무너지고, 시스템 빨강은 우리 색 토큰 밖이다.
/// 닫기는 왼쪽 위 유리 ✕ 하나(`SheetHeader`).

// MARK: - 차단 확인

/// 차단 확인: 무엇이 막히는지 **세 줄** → 무엇이 안 막히는지 한 줄 → 되돌릴 수 있다는 한 줄 → [차단하기].
///
/// **차단을 부르는 곳은 이 시트뿐이다**(소스 계약 — 메뉴는 시트만 연다). 확인 없는 차단은 만들지 마라:
/// 차단은 상대에게 알리지 않는 조용한 동작이라, 잘못 눌러도 사용자가 알아채는 신호가 없다.
struct MessagesBlockConfirmSheet: View {
    let peerName: String
    let onConfirm: () -> Void
    let onClose: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(BlockReportText.blockAction, onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    Text(BlockReportText.blockConfirmTitle(peerName))
                        .font(.headline)
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                        .accessibilityAddTraits(.isHeader)

                    InsetGroup {
                        ForEach(Array(BlockReportText.blockConfirmItems(.phone).enumerated()), id: \.offset) { index, item in
                            let isLast = index == BlockReportText.blockConfirmItems(.phone).count - 1
                            GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + iconWidth + MobileTheme.space3)) {
                                Image(systemName: "nosign")
                                    .font(.body)
                                    .foregroundStyle(MobileTheme.danger)
                                    .frame(width: iconWidth)
                                    .accessibilityHidden(true)
                                Text(item)
                                    .font(.body)
                                    .foregroundStyle(MobileTheme.label)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("차단하면: \(BlockReportText.blockConfirmItems(.phone).joined(separator: ", "))"))

                    Text(BlockReportText.blockConfirmScopeNote)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    Text(BlockReportText.blockConfirmUndoNote(.phone))
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)

                    AingButton(BlockReportText.blockConfirm, kind: .destructive, size: .lg, fillsWidth: true, role: .destructive, action: onConfirm)
                        .padding(.top, MobileTheme.space1)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space6)
            }
        }
        .background(MobileTheme.surface.ignoresSafeArea())
        // 큰 글자에서 세 줄이 여섯 줄이 된다 — 중간 높이에서 버튼이 잘리면 사람이 올려서 본다.
        .presentationDetents([.medium, .large])
        .presentationBackground(MobileTheme.surface)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 신고

/// 신고 대상(사람 하나 · 또는 그 사람이 보낸 메시지 한 건). `sheet(item:)` 의 값이라 `Identifiable` 이다.
struct MessagesReportTarget: Identifiable, Equatable {
    let peerID: String
    let peerName: String
    /// 메시지 한 건을 신고하는 경우의 그 메시지 id. nil 이면 사람 신고.
    var messageID: String?
    /// 메시지를 신고할 때 운영자가 볼 본문(화면에도 한 번 보여 준다 — 무엇을 신고하는지 눈으로 확인하게).
    var messageBody: String?

    var id: String { messageID ?? peerID }
}

/// 신고 시트: 사유 4개(필수) · 자유 입력 200자(선택) · [신고하면서 차단](기본 켬) · "24시간 안에 확인합니다" · [신고 보내기].
///
/// 보내는 문은 하나다(`store.submitReport`). 성공해야 시트가 닫힌다 — 실패하면 쓴 글을 쥔 채 이유 한 줄을 세운다.
struct MessagesReportSheet: View {
    let store: MessagesStore
    let target: MessagesReportTarget
    /// 보냈다. `blocked` 면 대화 화면도 목록으로 빠져나온다.
    let onSent: (_ blocked: Bool) -> Void
    let onClose: () -> Void

    @State private var reason: ContentReportReason?
    @State private var detail = ""
    /// 기본 켬 — 신고할 정도면 대개 보고 싶지 않다(SPEC 범위 결정).
    @State private var alsoBlock = true
    @FocusState private var detailFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(BlockReportText.reportTitle, onClose: close)
                .disabled(store.isSendingReport)
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    Text(target.messageID == nil ? BlockReportText.reportLede(target.peerName) : BlockReportText.reportMessageLede)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)

                    if let body = target.messageBody {
                        quotedMessage(body)
                    }

                    header(BlockReportText.reportReasonHeader)
                    InsetGroup {
                        ForEach(Array(ContentReportReason.allCases.enumerated()), id: \.element) { index, value in
                            reasonRow(value, isLast: index == ContentReportReason.allCases.count - 1)
                        }
                    }

                    header(BlockReportText.reportDetailHeader)
                    detailEditor

                    InsetGroup {
                        GroupRow(divider: .none, minHeight: MobileTheme.rowHeightTwoLine) {
                            Toggle(isOn: $alsoBlock) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(BlockReportText.reportAlsoBlock)
                                        .font(.body)
                                        .foregroundStyle(MobileTheme.label)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(BlockReportText.reportAlsoBlockDetail)
                                        .font(.footnote)
                                        .foregroundStyle(MobileTheme.label2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(MobileTheme.accentFill)
                            .disabled(store.isSendingReport)
                        }
                    }

                    Text(BlockReportText.reviewPromise)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)

                    if let notice = store.reportNotice {
                        InlineNotice(text: notice, kind: .error)
                    }

                    AingButton(
                        store.isSendingReport ? BlockReportText.reportSending : BlockReportText.reportSubmit,
                        kind: .filled,
                        size: .lg,
                        fillsWidth: true,
                        isBusy: store.isSendingReport,
                        action: submit
                    )
                    .disabled(!canSubmit)
                    .padding(.top, MobileTheme.space1)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space6)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(MobileTheme.surface.ignoresSafeArea())
        // 키보드가 올라오면 중간 높이에서는 보내기 버튼이 가린다(계정 삭제 시트와 같은 근거).
        .presentationDetents([.large])
        .presentationBackground(MobileTheme.surface)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.isSendingReport)
        .onDisappear { store.reportSheetDidDisappear() }
    }

    private var canSubmit: Bool {
        BlockReportRules.canSubmitReport(reason: reason, detail: detail, isSending: store.isSendingReport)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
    }

    /// 신고하는 메시지 본문 한 장(읽기 전용 · 세 줄까지). 무엇을 신고하는지 눈으로 확인하는 자리다.
    private func quotedMessage(_ body: String) -> some View {
        Text(body)
            .font(.subheadline)
            .foregroundStyle(MobileTheme.label)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(MobileTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(MobileTheme.bubbleIn))
    }

    private func reasonRow(_ value: ContentReportReason, isLast: Bool) -> some View {
        let isSelected = reason == value
        return GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding)) {
            Button {
                reason = value
                // 사유를 고르면 "사유를 골라 주세요" 는 더 이상 참이 아니다.
                store.reportNotice = nil
            } label: {
                HStack(spacing: MobileTheme.space3) {
                    Text(value.label)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: MobileTheme.space2)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(isSelected ? MobileTheme.accent : MobileTheme.label3)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: AingButtonMetrics.minimumTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isSendingReport)
            .accessibilityLabel(Text(value.label))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    /// 자유 입력(선택 · 200자). 카운터는 상한 가까이에서만 선다(입력칸과 같은 규칙).
    private var detailEditor: some View {
        VStack(alignment: .leading, spacing: MobileTheme.space2) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $detail)
                    .focused($detailFocused)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(MobileTheme.fill))
                    .disabled(store.isSendingReport)
                    .accessibilityLabel(Text(BlockReportText.reportDetailHeader))
                if detail.isEmpty {
                    Text(BlockReportText.reportDetailPlaceholder)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label3Text)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            if let counter = BlockReportRules.detailCounterText(detail) {
                Text(counter)
                    .font(MobileTheme.number(.caption))
                    .monospacedDigit()
                    .foregroundStyle(BlockReportRules.isDetailOverflowing(detail) ? MobileTheme.danger : MobileTheme.label2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            }
        }
    }

    private func close() {
        guard !store.isSendingReport else { return }
        onClose()
    }

    /// 제출 가드는 스토어의 `submitReport` 가 한 번 더 본다(비활성만으로는 왜 막혔는지 말할 기회가 없다 — 계정 삭제 시트와 같은 규칙).
    private func submit() {
        detailFocused = false
        let blocked = alsoBlock
        Task { @MainActor in
            let sent = await store.submitReport(
                peerID: target.peerID,
                reason: reason,
                detail: detail,
                messageID: target.messageID,
                alsoBlock: blocked
            )
            if sent { onSent(blocked) }
        }
    }
}
#endif
