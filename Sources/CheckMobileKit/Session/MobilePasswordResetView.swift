#if os(iOS)
import CheckCore
import SwiftUI

/// 비밀번호 재설정 화면(w16 · 재디자인 B — 로그인과 같은 틀). 3단(이메일 → 코드 → 새 비밀번호)이고 왕복 중엔 직전 화면에 머문다.
/// 규칙·문구는 전부 `MobilePasswordResetStore`(맥 재설정 패널과 같은 규칙 — 계정 유무를 흘리지 않는 문구).
/// 코드·새 비밀번호는 화면 상태다(스토어에 남기지 않는다 — 화면을 벗어나면 사라지는 게 맞다, 맥과 같다).
struct MobilePasswordResetView: View {
    @State private var store: MobilePasswordResetStore
    @State private var code = ""
    @State private var newPassword = ""
    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = MobileLoginMetrics.iconWidth

    private enum Field { case email, code, newPassword }

    init(session: MobileSessionStore, email: String) {
        _store = State(initialValue: MobilePasswordResetStore(session: session, email: email, clock: session.clock))
    }

    var body: some View {
        @Bindable var store = store
        MobileCenteredScreen {
            VStack(spacing: 0) {
                MobileBrandHeader(mood: .plain, title: headerTitle, message: headerMessage)

                stepGroup
                    .padding(.top, MobileTheme.space6)

                if let text = store.noticeText {
                    InlineNotice(text: text, kind: store.noticeIsError ? .error : .info)
                        .padding(.top, MobileTheme.space3)
                }

                AingButton(store.primaryTitle, kind: .filled, size: .lg, fillsWidth: true, isBusy: store.isBusy, action: perform)
                    .disabled(!store.isPrimaryEnabled(code: code, newPassword: newPassword))
                    .padding(.top, MobileTheme.space4)

                // 재발송은 **코드 화면에만**(3단계에선 코드가 이미 소모됐다). 대상은 지금 보는 칸이 아니라 실제로 보낸 주소다.
                if store.step == .code {
                    MobileResendRow(title: store.resendTitle, isEnabled: store.isResendEnabled) {
                        Task { await store.requestCode() }
                    }
                    .padding(.top, MobileTheme.space2)
                }
            }
        } footer: {
            EmptyView()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.22), value: store.step)
        // 단계가 넘어가면 커서를 그 화면의 칸으로 — 없으면 코드 확인 직후 3단계가 떠도 사용자가 칸부터 눌러야 한다(맥과 같다).
        .onAppear { focused = focusField(for: store.step) }
        .onChange(of: store.step) { _, step in focused = focusField(for: step) }
        .onDisappear { store.cancel() }
    }

    /// 단계별 입력 그룹. 코드 단계는 가입 인증과 **같은 부품**(`MobileCodeEntryGroup`) — 동작(자동 채움·키패드·제출 키)이
    /// 두 흐름에서 갈리지 않게 한 벌로 둔다.
    @ViewBuilder
    private var stepGroup: some View {
        @Bindable var store = store
        switch store.step {
        case .email:
            InsetGroup {
                inputRow("envelope", last: true) {
                    TextField(text: $store.email, prompt: prompt(MobileSignUpText.email)) { Text(MobileSignUpText.email) }
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($focused, equals: .email)
                        .onSubmit(perform)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label)
                }
            }
        case .code:
            MobileCodeEntryGroup(sentToEmail: store.email, code: $code, field: Field.code, focused: $focused, onSubmit: perform)
        case .newPassword:
            InsetGroup {
                inputRow("lock.rotation", last: true) {
                    SecureField(text: $newPassword, prompt: prompt(MobilePasswordResetText.newPasswordLabel)) { Text(MobilePasswordResetText.newPasswordLabel) }
                        .textContentType(.newPassword)
                        .submitLabel(.go)
                        .focused($focused, equals: .newPassword)
                        .onSubmit(perform)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label)
                }
            }
        }
    }

    private var headerTitle: String {
        store.step == .newPassword ? MobilePasswordResetText.verifiedTitle : MobilePasswordResetText.title
    }

    private var headerMessage: String {
        switch store.step {
        case .email: return MobilePasswordResetText.emailHelp
        case .code: return MobilePasswordResetText.codeLabel
        case .newPassword: return MobilePasswordResetText.newPasswordHelp
        }
    }

    private func focusField(for step: MobilePasswordResetStore.Step) -> Field {
        switch step {
        case .email: return .email
        case .code: return .code
        case .newPassword: return .newPassword
        }
    }

    /// 주 버튼·키보드 제출 — 화면마다 **그 화면에서 친 값 하나만** 싣는다. 막는 일은 스토어 가드가 한다(비활성 우회 뒷문 없음, 문구는 스토어가).
    private func perform() {
        focused = nil
        let code = code
        let newPassword = newPassword
        Task { @MainActor in
            switch store.step {
            case .email: await store.requestCode()
            case .code: await store.verifyCode(code)
            case .newPassword: await store.submitNewPassword(newPassword)
            }
        }
    }

    private func inputRow<Content: View>(_ icon: String, last: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        GroupRow(
            divider: last ? .none : .inset(MobileTheme.cardPadding + iconWidth + MobileTheme.space3),
            minHeight: MobileLoginMetrics.rowHeight
        ) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(MobileTheme.label2)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            content()
        }
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(MobileTheme.label3Text)
    }
}
#endif
