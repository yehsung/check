import CheckCore
import SwiftUI

// MARK: - 설정 → 계정 삭제 (v0.3.51 — 심사 지침 5.1.1(v), 두 판 모두)

/// 설정 '내 정보' 머리 줄의 [계정 삭제]가 여는 화면. 설정 본문과 **자리를 바꾼다**([차단한 사람]과 같은 규약 — 본문에 펼치면
/// 이 창의 높이 계약이 흔들린다).
///
/// 위에서 아래로: 뒤로 · 제목 → 무엇이 지워지는지 한 줄 + 목록 → 되돌릴 수 없음 → 제보는 익명으로 남는다 → 비밀번호 →
/// 결과 한 줄 → [계정 삭제] → (누르면 같은 자리가) [취소] [영구 삭제]. 폰의 계정 삭제 시트(`MeAccountDeletionSheet`)와 같은 순서다.
///
/// **2단 확인이다.** 비밀번호를 넣고 [계정 삭제]를 누르면 같은 줄이 확인 문장 + [취소]·[영구 삭제]로 바뀌고, **두 번째 누름만**
/// 삭제를 부른다(`store.deleteMyAccount()` 를 부르는 곳은 이 파일의 그 버튼 하나다). 비밀번호 칸에서 Enter 를 쳐도 지우지 않는다 —
/// 로그인 폼은 Enter 가 제출이지만 그건 되돌릴 수 있는 동작이다.
struct CheckAccountDeletionSettingsPage: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        let deleting = store.isDeletingAccount
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: AccountDeletionText.back, enabled: !deleting) {
                    store.closeAccountDeletionSettings()
                }
                Text(AccountDeletionText.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                Spacer(minLength: 6)
            }
            Text(AccountDeletionText.lede)
                .font(.caption)
                .foregroundStyle(CheckTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(AccountDeletionText.items, id: \.self) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CheckTheme.danger)
                            .frame(width: 14)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(CheckTheme.primaryText)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelStyle()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("지워지는 것: \(AccountDeletionText.items.joined(separator: ", "))"))
            Text(AccountDeletionText.irreversible)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.pending)
                .fixedSize(horizontal: false, vertical: true)
            Text(AccountDeletionText.feedbackNote)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                SecureField(AccountDeletionText.passwordPrompt, text: $store.accountDeletionPassword)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CheckTheme.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(CheckTheme.border, lineWidth: 1)
                            )
                    )
                    .disabled(deleting)
                    // 비밀번호를 고치면 무장된 확인을 푼다 — 확인은 '이 비밀번호로 지운다'에 대한 것이다.
                    .onChange(of: store.accountDeletionPassword) { _, _ in
                        if store.isConfirmingAccountDeletion { store.isConfirmingAccountDeletion = false }
                    }
                    .accessibilityLabel(AccountDeletionText.passwordPrompt)
                Text(AccountDeletionText.passwordHelp)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = store.accountDeletionNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionRow(deleting: deleting)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func actionRow(deleting: Bool) -> some View {
        if store.isConfirmingAccountDeletion || deleting {
            VStack(alignment: .trailing, spacing: 8) {
                Text(AccountDeletionText.confirmQuestion)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    FeedbackSegmentChip(label: AccountDeletionText.cancel, tint: CheckTheme.accent, isSelected: false) {
                        guard !deleting else { return }
                        store.isConfirmingAccountDeletion = false
                    }
                    FeedbackPrimaryButton(
                        label: deleting ? AccountDeletionText.inFlight : AccountDeletionText.confirm,
                        enabled: !deleting && store.canDeleteAccount,
                        // 되돌릴 수 없는 동작이라 danger 로 칠한다(차단·사진 되돌리기 확인과 같은 규약).
                        tint: CheckTheme.danger
                    ) {
                        guard store.canDeleteAccount else { return }
                        Task { @MainActor in
                            await store.deleteMyAccount()
                            if store.showsAccountDeletionInSettings { store.isConfirmingAccountDeletion = false }
                        }
                    }
                }
            }
        } else {
            HStack {
                Spacer(minLength: 0)
                FeedbackPrimaryButton(
                    label: AccountDeletionText.action,
                    enabled: store.canDeleteAccount,
                    tint: CheckTheme.danger
                ) {
                    // 누르는 순간 앞선 결과 한 줄을 치운다 — 안 치우면 새 확인 위에 옛 실패 문장이 남는다.
                    store.accountDeletionNotice = nil
                    store.isConfirmingAccountDeletion = true
                }
            }
        }
    }
}
