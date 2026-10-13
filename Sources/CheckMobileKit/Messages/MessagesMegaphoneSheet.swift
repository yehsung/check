#if os(iOS)
import CheckCore
import SwiftUI
import UIKit

/// 확성기(📢 1.0.7) 작성 시트 — 메시지 탭 오른쪽 위 📢 버튼이 띄운다. 루비로 **앱을 쓰는 모두에게** 1:1 메시지를 한 줄씩 보낸다.
///
/// 판정·문구·요청 id·잔량 미러는 전부 코어 `MegaphoneStore`(맥과 한 벌)에 있고, 이 화면은 그리기와 **조합 확정**만 한다.
/// - 흐름(2단 확인 — 맥 상점 패널과 같다): 글 → [보내기] → "루비 50개로 N명에게 보낼까요?" → [보내기] → 결과 한 줄.
/// - 입력칸은 대화 입력줄과 같은 `UITextView`(`MessagesComposerTextView`)다 — 한글 조합 중에 누르면 먼저 확정하고(`unmarkText`)
///   확정된 글로 판정한다. SwiftUI `TextField` 는 조합 중인 글자를 알려 주지 않아 마지막 음절이 빠진다(대화 입력줄 머리말).
/// - 잔량은 오목·체스·상점과 같은 미러(`context.gomokuHost.rubyBalance`)를 오른쪽 위에 보여 준다 — 보내면 서버가 준 값으로 바뀐다.
struct MessagesMegaphoneSheet: View {
    let store: MessagesStore

    @Environment(\.dismiss) private var dismiss
    @State private var editor = MessagesComposerEditorHandle()
    @State private var isComposing = false
    @State private var editorHeight: CGFloat = 44

    var body: some View {
        let mega = store.megaphone
        let now = store.context.clock.now()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    Text(MegaphoneText.explainer)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    field(mega)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(mega.infoLine(now: now))
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(mega.counterText)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(mega.isOverLength ? MobileTheme.danger : MobileTheme.label2)
                            .fixedSize()
                            .accessibilityLabel(Text("\(mega.draftLength)자 중 \(mega.maxLength)자"))
                    }
                    if let notice = mega.notice {
                        InlineNotice(text: notice, kind: mega.noticeIsError ? .error : .info)
                    }
                    actions(mega)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space3)
                .padding(.bottom, MobileTheme.space6)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(MegaphoneText.badgeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RubyBalanceChip(store.context.gomokuHost.rubyBalance, style: .toolbar)
                }
            }
            .sheetCloseButton { dismiss() }
        }
        .onAppear { mega.open() }
        .onDisappear { mega.close() }
    }

    @ViewBuilder
    private func field(_ mega: MegaphoneStore) -> some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous)
        ZStack(alignment: .topLeading) {
            MessagesComposerTextView(
                text: Binding(get: { mega.draft }, set: { mega.setDraft($0) }),
                isComposing: $isComposing,
                height: $editorHeight,
                handle: editor
            )
            .frame(height: max(editorHeight, 96))
            .disabled(mega.isSending)
            if mega.draft.isEmpty && !isComposing {
                Text(MegaphoneText.placeholder)
                    .font(.body)
                    .foregroundStyle(MobileTheme.label3Text)
                    .padding(.horizontal, MessagesComposerTextView.horizontalInset + 5)
                    .padding(.vertical, MessagesComposerTextView.verticalInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(shape.fill(MobileTheme.surface))
        .overlay(shape.strokeBorder(mega.isOverLength ? MobileTheme.danger : MobileTheme.separator,
                                    lineWidth: mega.isOverLength ? 1 : 0.5))
    }

    @ViewBuilder
    private func actions(_ mega: MegaphoneStore) -> some View {
        if mega.isConfirming, let question = mega.confirmQuestion {
            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                Text(question)
                    .font(.headline)
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text("보내면 되돌릴 수 없어요")
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                // ★ 실제 요청은 이 버튼 하나뿐이다(confirmSend). 위의 [보내기] 는 이 단계로 오기만 한다.
                AingButton(MegaphoneText.sendButton, kind: .filled, fillsWidth: true, isBusy: mega.isSending) {
                    commitThen { mega.confirmSend() }
                }
                .padding(.top, MobileTheme.space1)
                AingButton(MegaphoneText.cancelButton, kind: .gray, fillsWidth: true) {
                    mega.cancelConfirm()
                }
                .disabled(mega.isSending)
            }
            .padding(MobileTheme.cardPadding)
            .background(RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous).fill(MobileTheme.surface))
        } else {
            AingButton(sendTitle(mega), kind: .filled, fillsWidth: true, isBusy: mega.isSending) {
                commitThen { mega.requestSend() }
            }
            // 조합 중이면 켠다(누르면 확정한 뒤 판정한다 — 대화 입력줄과 같은 규칙).
            .disabled(!(isComposing || mega.canRequestSend))
        }
    }

    /// 첫 단계 버튼 글자. 값을 알면 값을 말한다(모르면 지어내지 않는다).
    private func sendTitle(_ mega: MegaphoneStore) -> String {
        guard let price = mega.price else { return MegaphoneText.sendButton }
        return "루비 \(price)개로 \(MegaphoneText.sendButton)"
    }

    /// 조합 중이면 먼저 확정하고, 확정된 글이 바인딩에 닿은 다음 차례에 동작한다(대화 입력줄 `send()` 와 같은 순서).
    private func commitThen(_ action: @escaping @MainActor () -> Void) {
        guard editor.hasMarkedText else {
            action()
            return
        }
        editor.commitMarkedText()
        let editor = editor
        let mega = store.megaphone
        let composing = $isComposing
        Task { @MainActor in
            if let text = editor.currentText { mega.setDraft(text) }
            composing.wrappedValue = editor.hasMarkedText
            guard !editor.hasMarkedText else { return }
            action()
        }
    }
}
#endif
