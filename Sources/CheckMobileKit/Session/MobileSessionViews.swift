#if os(iOS)
import SwiftUI

/// 로그인 화면(SPEC-ios §2): 이메일·비밀번호 로그인만. 가입·비밀번호 재설정은 맥 앱 안내.
struct MobileLoginView: View {
    let session: MobileSessionStore

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("aing-check")
                        .font(MobileTheme.title(.largeTitle))
                        .foregroundStyle(MobileTheme.primaryText)
                    Text("맥의 aing-check 와 같은 계정으로 로그인해요")
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 32)

                AingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        field(title: "이메일") {
                            TextField("name@example.com", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.next)
                                .focused($focused, equals: .email)
                                .onSubmit { focused = .password }
                        }
                        field(title: "비밀번호") {
                            SecureField("비밀번호", text: $password)
                                .textContentType(.password)
                                .submitLabel(.go)
                                .focused($focused, equals: .password)
                                .onSubmit(signIn)
                        }
                        if let notice = session.notice {
                            InlineNotice(text: notice, kind: .error)
                        }
                        Button(action: signIn) {
                            if session.isSigningIn {
                                ProgressView().tint(MobileTheme.onAccent)
                            } else {
                                Text("로그인")
                            }
                        }
                        .buttonStyle(AingPrimaryButtonStyle())
                        .disabled(session.isSigningIn)
                        .accessibilityLabel(Text(session.isSigningIn ? "로그인 중" : "로그인"))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(MobileSessionText.signUpOnMac, systemImage: "laptopcomputer")
                    Label(MobileSessionText.passwordResetOnMac, systemImage: "key.fill")
                }
                .font(.footnote)
                .foregroundStyle(MobileTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MobileTheme.background.ignoresSafeArea())
        .onAppear {
            if email.isEmpty, let stored = session.storedEmail { email = stored }
        }
    }

    @ViewBuilder
    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MobileTheme.secondaryText)
            content()
                .font(.body)
                .foregroundStyle(MobileTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MobileTheme.cardElevated))
        }
    }

    private func signIn() {
        focused = nil
        let email = email
        let password = password
        Task { await session.signIn(email: email, password: password) }
    }
}

/// 업데이트 필요 화면(SPEC-ios §2): 이 빌드 < 서버 최소 빌드 → TestFlight 열기.
struct MobileUpdateRequiredView: View {
    let minBuild: Int
    let currentBuild: Int
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(.largeTitle))
                    .imageScale(.large)
                    .foregroundStyle(MobileTheme.accent)
                    .padding(.top, 64)
                    .accessibilityHidden(true)
                Text(MobileSessionText.updateTitle)
                    .font(MobileTheme.title())
                    .foregroundStyle(MobileTheme.primaryText)
                    .multilineTextAlignment(.center)
                Text(MobileSessionText.updateBody)
                    .font(.body)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                AingCard {
                    HStack {
                        Text("지금 빌드")
                            .foregroundStyle(MobileTheme.secondaryText)
                        Spacer()
                        Text("\(currentBuild)")
                            .font(MobileTheme.number(.body))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.primaryText)
                    }
                    Divider().overlay(MobileTheme.separator)
                    HStack {
                        Text("필요한 빌드")
                            .foregroundStyle(MobileTheme.secondaryText)
                        Spacer()
                        Text("\(minBuild) 이상")
                            .font(MobileTheme.number(.body))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.primaryText)
                    }
                }
                Button(MobileSessionText.updateButton) {
                    openURL(MobileSessionText.testFlightURL)
                }
                .buttonStyle(AingPrimaryButtonStyle())
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, 24)
        }
        .background(MobileTheme.background.ignoresSafeArea())
    }
}

/// 실행 직후(client_release · 복원) 잠깐 보이는 화면.
struct MobileLaunchingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("aing-check")
                .font(MobileTheme.title(.largeTitle))
                .foregroundStyle(MobileTheme.primaryText)
            ProgressView()
                .accessibilityLabel(Text("불러오는 중"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MobileTheme.background.ignoresSafeArea())
    }
}
#endif
