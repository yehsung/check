#if os(iOS)
import SwiftUI

/// 로그인 화면(SPEC-ios §2 · 재디자인 B): 이메일·비밀번호 로그인 + 맨 아래 두 길(가입하기 · 비밀번호를 잊었어요 — w16).
/// 가운데 정렬 — 아잉 + 워드마크 · 입력 그룹(자리표시 회색) · 로그인 버튼(맥 startGradient — 로그인 전용) · 맨 아래 두 길.
///
/// 로그인 아래 화면(가입 `MobileSignUpView` · 재설정 `MobilePasswordResetView`)은 이 뷰의 `NavigationStack` 에 쌓인다 —
/// 뒤로 가는 길이 시스템 뒤로 버튼 하나라 닫기를 따로 두지 않는다. 로그인 화면 자체는 막대를 숨긴다(가운데 정렬이 막대만큼 내려앉지 않게).
/// 예전엔 "가입은 맥 앱에서 해요 / 재설정은 맥 앱에서" 두 줄이었다 — 맥이 없는 사용자(앱스토어)가 생긴다(SPEC 작업 B).
struct MobileLoginView: View {
    let session: MobileSessionStore
    /// 데모 라우트(`signup` · `reset`)로 바로 열 아래 화면. 실제 실행은 nil.
    var initialRoute: MobileAuthRoute? = nil

    @State private var email = ""
    @State private var password = ""
    @State private var path: [MobileAuthRoute] = []
    @State private var didOpenInitialRoute = false
    @FocusState private var focused: Field?
    /// 입력 줄 기호 칸 폭(글자 크기를 따라 — 고정 24pt 면 접근성 크기에서 기호가 자리표시 글자를 덮었다, AX3 실측).
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = MobileLoginMetrics.iconWidth

    private enum Field { case email, password }

    var body: some View {
        NavigationStack(path: $path) {
            loginScreen
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MobileAuthRoute.self) { route in
                    destination(route)
                }
        }
        .onAppear {
            if let initialRoute, !didOpenInitialRoute {
                didOpenInitialRoute = true
                path = [initialRoute]
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: MobileAuthRoute) -> some View {
        switch route {
        case .signUp(let createTeam):
            MobileSignUpView(session: session, createTeam: createTeam)
        case .signUpConfirm(let email):
            // 미확인 계정의 출구 — 가입 화면을 코드 단계로 연다(들어가면서 코드를 다시 보낸다).
            MobileSignUpView(session: session, confirmEmail: email)
        case .passwordReset:
            // 지금 입력해 둔 이메일을 그대로 들고 넘어간다 — 재설정 화면에서 다시 타이핑시키지 않는다(맥 PasswordResetEntryLink).
            MobilePasswordResetView(session: session, email: email)
        }
    }

    private var loginScreen: some View {
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
                    // ★ 미확인 계정의 출구(SPEC-signup-otp 작업 P). 가입 도중 앱을 닫은 사람은 계정만 만들어진 채
                    //   미확인이라 로그인하면 "이메일 확인 필요"만 본다 — 여기서 코드 화면으로 갈 길이 없으면 그 계정은
                    //   운영자가 Admin API 로 풀어 주기 전까지 영영 못 쓴다. 판정은 스토어(코어 매퍼의 문장)가 한다.
                    if MobileSignUpStore.offersConfirmationExit(for: notice) {
                        AingButton(MobileSignUpText.confirmExit, kind: .plain, size: .sm) {
                            path.append(.signUpConfirm(email: email))
                        }
                        .padding(.top, MobileTheme.space2)
                    }
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
            // 두 길은 글자 버튼(채운 버튼은 로그인 하나). 큰 글자에서는 "계정이 없나요?" 와 "가입하기" 가 줄을 바꿔 선다.
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    Text(MobileSessionText.signUpPrompt)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                    AingButton(MobileSessionText.signUpAction, kind: .plain, size: .sm) {
                        path.append(.signUp(createTeam: false))
                    }
                }
                AingButton(MobileSessionText.forgotPassword, kind: .plain, size: .sm) {
                    path.append(.passwordReset)
                }
            }
            .frame(maxWidth: .infinity)
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

// MARK: - 로그인 · 업데이트 · 가입 · 재설정 공용(세션 화면 네 벌이 같은 틀을 쓴다 — w16 부터 파일 밖 두 화면도)

enum MobileLoginMetrics {
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
struct MobileBrandHeader: View {
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

/// 6자리 코드 입력 그룹(비밀번호 재설정 · 가입 이메일 인증 **공용** — w16 SPEC-signup-otp 작업 P).
///
/// 두 흐름의 코드 단계는 화면상 완전히 같다: 어디로 보냈는지 알리는 두 줄 + 숫자 칸 하나. 한 벌로 두는 이유는 문구가 아니라
/// **동작**이다 — `.oneTimeCode`(메일 코드 자동 채움) · 숫자 키패드 · 고정폭 숫자 · 제출 키. 복사해 두면 한쪽만 고쳐지는 날이 온다.
///
/// 포커스 값은 부모의 Field 타입을 그대로 받는다(두 화면의 단계 집합이 다르다) — 그래서 제네릭이다.
struct MobileCodeEntryGroup<Field: Hashable>: View {
    /// 코드를 보낸 주소(정규화된 값). 주소를 잘못 적었을 때 스스로 알아챌 **유일한 단서**라 코드 칸보다 위에 둔다.
    let sentToEmail: String
    @Binding var code: String
    let field: Field
    @FocusState.Binding var focused: Field?
    let onSubmit: () -> Void
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = MobileLoginMetrics.iconWidth

    var body: some View {
        InsetGroup {
            GroupRow(divider: .inset(MobileTheme.cardPadding), minHeight: MobileTheme.rowHeightTwoLine) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MobilePasswordResetText.sentTo)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                    Text(sentToEmail)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MobileTheme.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
            }
            GroupRow(divider: .none, minHeight: MobileLoginMetrics.rowHeight) {
                Image(systemName: "number")
                    .font(.body)
                    .foregroundStyle(MobileTheme.label2)
                    .frame(width: iconWidth)
                    .accessibilityHidden(true)
                TextField(text: $code, prompt: Text(MobilePasswordResetText.codeLabel).foregroundStyle(MobileTheme.label3Text)) {
                    Text(MobilePasswordResetText.codeLabel)
                }
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .submitLabel(.go)
                .focused($focused, equals: field)
                .onSubmit(onSubmit)
                .font(MobileTheme.number(.body))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label)
            }
        }
    }
}

/// "코드가 안 왔나요? [다시 받기 (N초)]" 줄(재설정 · 가입 인증 공용). 채운 버튼은 화면당 하나라 여기선 글자 버튼이다.
struct MobileResendRow: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(MobilePasswordResetText.resendPrompt)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
            AingButton(title, kind: .plain, size: .sm, action: action)
                .disabled(!isEnabled)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 화면 높이 안에서 가운데로 모으고(짧은 화면의 아래 절반이 비지 않게), 넘치면 스크롤한다. `footer` 는 맨 아래에 붙는다.
struct MobileCenteredScreen<Content: View, Footer: View>: View {
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
