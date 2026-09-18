#if os(iOS)
import SwiftUI

/// 계정 삭제 시트(앱스토어 5.1.1(v) — 앱 안에서 계정을 지울 수 있어야 한다).
///
/// 위에서 아래로: 머리(✕ · 제목) → 무엇이 지워지는지 한 줄 + 목록 → 되돌릴 수 없음(경고 안내) → 제보는 익명으로 남는다는 한 줄 →
/// 비밀번호 재입력 → 실패 문구 → [영구 삭제](파괴적 색 · `role: .destructive`). **삭제를 부르는 곳은 이 파일뿐이고, 이 파일 안에서도
/// 버튼 하나뿐이다**(소스 계약 — 키보드 제출 키는 삭제를 부르지 않는다). 설정 화면은 시트만 연다. 도는 중에는 ✕ 를 잠그고 쓸어내려
/// 닫지 못하게 한다(닫힌 뒤 성공하면 사용자가 왜 로그인 화면인지 모른다).
///
/// 불투명 시트(`presentationBackground(surface)`)인 이유는 기권 확인(`AingConfirmSheet`)과 같다 — 알림창은 재질이 뒤 색을 빨아들여
/// 빨간 글자의 대비가 무너지고 시스템 빨강은 토큰 밖이다. `.large` 하나인 이유: 키보드가 올라오면 중간 높이에서는 버튼이 가려진다.
struct MeAccountDeletionSheet: View {
    let store: MeStore
    let onClose: () -> Void
    @FocusState private var passwordFocused: Bool
    /// 입력 줄 기호 칸 폭(로그인 화면과 같은 규칙 — 고정 폭이면 접근성 크기에서 기호가 자리표시 글자를 덮는다).
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            SheetHeader(MeText.deleteAccountTitle, onClose: close)
                .disabled(store.isDeletingAccount)
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    Text(MeText.deleteAccountLede)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)

                    InsetGroup {
                        ForEach(Array(MeText.deleteAccountItems.enumerated()), id: \.offset) { index, item in
                            let isLast = index == MeText.deleteAccountItems.count - 1
                            GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + iconWidth + MobileTheme.space3)) {
                                Image(systemName: "trash")
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
                    .accessibilityLabel(Text("지워지는 것: \(MeText.deleteAccountItems.joined(separator: ", "))"))

                    InlineNotice(text: MeText.deleteAccountIrreversible, kind: .warning)
                    Text(MeText.deleteAccountFeedbackNote)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)

                    passwordField
                    Text(MeText.deleteAccountPasswordHelp)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)

                    if let notice = store.accountDeletionNotice {
                        InlineNotice(text: notice, kind: .error)
                    }

                    AingButton(
                        store.isDeletingAccount ? MeText.deletingAccount : MeText.deleteAccountConfirm,
                        kind: .destructive,
                        size: .lg,
                        fillsWidth: true,
                        isBusy: store.isDeletingAccount,
                        role: .destructive,
                        action: confirm
                    )
                    .disabled(!store.canDeleteAccount)
                    .padding(.top, MobileTheme.space1)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space6)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(MobileTheme.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(MobileTheme.surface)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.isDeletingAccount)
        .onDisappear { store.accountDeletionDidDisappear() }
    }

    /// 비밀번호 한 줄(로그인 화면과 같은 입력 그룹 모양 — 자물쇠 기호 · 자리표시 회색).
    ///
    /// 키보드의 '완료' 키는 **키보드만 내린다**. 로그인 폼은 `.onSubmit(signIn)` 이지만 그건 되돌릴 수 있는 동작이다 — 여기서 같은 규칙을
    /// 쓰면 키보드를 닫으려는 습관 한 번에 계정이 영구 삭제된다. 삭제는 [영구 삭제] 버튼 하나로만 나간다(소스 계약).
    private var passwordField: some View {
        @Bindable var store = store
        return InsetGroup {
            GroupRow(divider: .none, minHeight: 52) {
                Image(systemName: "lock")
                    .font(.body)
                    .foregroundStyle(MobileTheme.label2)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                SecureField(text: $store.accountDeletionPassword, prompt: Text(MeText.deleteAccountPasswordPrompt).foregroundStyle(MobileTheme.label3Text)) {
                    Text(MeText.deleteAccountPasswordPrompt)
                }
                .textContentType(.password)
                .submitLabel(.done)
                .focused($passwordFocused)
                .onSubmit { passwordFocused = false }
                .disabled(store.isDeletingAccount)
                .font(.body)
                .foregroundStyle(MobileTheme.label)
                .accessibilityLabel(Text(MeText.deleteAccountPasswordPrompt))
            }
        }
    }

    private func close() {
        guard !store.isDeletingAccount else { return }
        onClose()
    }

    /// 제출 가드는 스토어의 `deleteAccount()` 가 한 번 더 본다(버튼 비활성만으로는 왜 막혔는지 말할 기회가 없다).
    private func confirm() {
        guard store.canDeleteAccount else { return }
        passwordFocused = false
        Task { await store.deleteAccount() }
    }
}
#endif
