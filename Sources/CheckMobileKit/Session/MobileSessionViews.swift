#if os(iOS)
import SwiftUI

/// 로그인 화면(SPEC-ios §2 · 재디자인 B): 이메일·비밀번호 로그인만. 가입·비밀번호 재설정은 맥 앱 안내.
/// 가운데 정렬 — 아잉 + 워드마크 · 입력 그룹(자리표시 회색) · 로그인 버튼(맥 startGradient — 로그인 전용) · 맨 아래 안내 두 줄.
struct MobileLoginView: View {
    let session: MobileSessionStore

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focused: Field?
    /// 입력 줄 기호 칸 폭(글자 크기를 따라 — 고정 24pt 면 접근성 크기에서 기호가 자리표시 글자를 덮었다, AX3 실측).
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = MobileLoginMetrics.iconWidth

    private enum Field { case email, password }

    var body: some View {
        MobileCenteredScreen {
            VStack(spacing: 0) {
                MobileBrandHeader(
                    mood: .working,
                    title: "aing-check",
                    message: "맥의 aing-check 와 같은 계정으로 로그인해요"
                )

                InsetGroup {
                    GroupRow(divider: .inset(MobileTheme.cardPadding + iconWidth + MobileTheme.space3), minHeight: MobileLoginMetrics.rowHeight) {
                        fieldIcon("envelope")
                        TextField(text: $email, prompt: prompt("이메일")) { Text("이메일") }
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focused, equals: .email)
                            .onSubmit { focused = .password }
                            .font(.body)
                            .foregroundStyle(MobileTheme.label)
                    }
                    GroupRow(divider: .none, minHeight: MobileLoginMetrics.rowHeight) {
                        fieldIcon("lock")
                        SecureField(text: $password, prompt: prompt("비밀번호")) { Text("비밀번호") }
                            .textContentType(.password)
                            .submitLabel(.go)
                            .focused($focused, equals: .password)
                            .onSubmit(signIn)
                            .font(.body)
                            .foregroundStyle(MobileTheme.label)
                    }
                }
                .padding(.top, MobileTheme.space6)

                if let notice = session.notice {
                    InlineNotice(text: notice, kind: .error)
                        .padding(.top, MobileTheme.space3)
                }

                Button(action: signIn) {
                    HStack(spacing: 8) {
                        if session.isSigningIn {
                            ProgressView().tint(MobileLoginMetrics.startInk)
                        }
                        Text(session.isSigningIn ? "로그인 중" : "로그인")
                    }
                }
                .buttonStyle(MobileStartButtonStyle())
                .disabled(session.isSigningIn)
                .padding(.top, MobileTheme.space4)
            }
        } footer: {
            VStack(spacing: 6) {
                Text(MobileSessionText.signUpOnMac)
                Text(MobileSessionText.passwordResetOnMac)
            }
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if email.isEmpty, let stored = session.storedEmail { email = stored }
        }
    }

    /// 자리표시자: 3단 글자(회색). 파랑·진한 색이면 이미 채운 값이나 링크처럼 읽힌다(비평 40).
    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(MobileTheme.label3Text)
    }

    private func fieldIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body)
            .foregroundStyle(MobileTheme.label2)
            .frame(width: iconWidth)
            .accessibilityHidden(true)
    }

    private func signIn() {
        focused = nil
        let email = email
        let password = password
        Task { await session.signIn(email: email, password: password) }
    }
}

/// 업데이트 필요 화면(SPEC-ios §2): 이 빌드 < 서버 최소 빌드 → TestFlight 열기. 로그인과 같은 가운데 정렬(시무룩한 아잉 — 막힌 상태).
struct MobileUpdateRequiredView: View {
    let minBuild: Int
    let currentBuild: Int
    @Environment(\.openURL) private var openURL

    var body: some View {
        MobileCenteredScreen {
            VStack(spacing: 0) {
                MobileBrandHeader(
                    mood: .off,
                    title: MobileSessionText.updateTitle,
                    message: MobileSessionText.updateBody
                )
                InsetGroup {
                    GroupRow(divider: .inset(MobileTheme.cardPadding)) {
                        buildRow("지금 빌드", value: "\(currentBuild)")
                    }
                    GroupRow(divider: .none) {
                        buildRow("필요한 빌드", value: "\(minBuild) 이상")
                    }
                }
                .padding(.top, MobileTheme.space6)
                AingButton(MobileSessionText.updateButton, kind: .filled, size: .lg, fillsWidth: true) {
                    openURL(MobileSessionText.testFlightURL)
                }
                .padding(.top, MobileTheme.space4)
            }
        } footer: {
            EmptyView()
        }
    }

    @ViewBuilder
    private func buildRow(_ title: String, value: String) -> some View {
        Text(title)
            .font(.body)
            .foregroundStyle(MobileTheme.label2)
        Spacer(minLength: 8)
        Text(value)
            .font(MobileTheme.number(.body))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
    }
}

// MARK: - 로그인 · 업데이트 공용(파일 안)

private enum MobileLoginMetrics {
    /// 입력 줄 높이(시안 그룹 행 44 보다 조금 높게 — 손가락 입력칸).
    static let rowHeight: CGFloat = 52
    /// 입력 줄 기호 칸 폭.
    static let iconWidth: CGFloat = 24
    /// 아잉 그림 크기(아잉 원본 192px — 3배 화면에서 크게 키우면 흐려진다).
    static let brandArt: CGFloat = 104
    /// 시작 그라디언트(#52D994→#2EAD9E) 위 글자: 흰 글자는 2:1 안팎이라 브랜드 남색(#1A1A2E, 6:1 이상)으로 쓴다.
    static let startInk = Color(
        red: MobileThemePalette.brandNavy.r,
        green: MobileThemePalette.brandNavy.g,
        blue: MobileThemePalette.brandNavy.b
    )
}

/// 로그인 버튼(채움 50 · 캡슐 · 맥 startGradient — 토큰 규칙상 로그인 버튼 전용).
private struct MobileStartButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(MobileLoginMetrics.startInk)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(MobileTheme.startGradient))
            .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.6))
            .contentShape(Capsule())
    }
}

/// 가운데 머리: 아잉(표정 = 상태) · 큰 제목 · 설명.
private struct MobileBrandHeader: View {
    let mood: CharacterMood
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: MobileTheme.space3) {
            CharacterPortrait(id: nil, mood: mood, size: MobileLoginMetrics.brandArt, framed: false)
                .accessibilityHidden(true)
            Text(title)
                .font(MobileTheme.title(.largeTitle))
                .foregroundStyle(MobileTheme.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 화면 높이 안에서 가운데로 모으고(짧은 화면의 아래 절반이 비지 않게), 넘치면 스크롤한다. `footer` 는 맨 아래에 붙는다.
private struct MobileCenteredScreen<Content: View, Footer: View>: View {
    private let content: Content
    private let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: MobileTheme.space6)
                    content
                    Spacer(minLength: MobileTheme.space6)
                    footer
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.bottom, MobileTheme.space4)
                // 폭은 화면 폭으로 못 박는다 — 유연한 틀(maxWidth)만 두면 큰 글자에서 자식의 이상 폭(520)으로 커져 글자가 화면 밖으로 잘렸다(AX3 실측).
                .frame(width: min(proxy.size.width, 520))
                .frame(width: proxy.size.width)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
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
                .foregroundStyle(MobileTheme.label)
            ProgressView()
                .accessibilityLabel(Text("불러오는 중"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MobileTheme.background.ignoresSafeArea())
    }
}
#endif
