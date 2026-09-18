#if os(iOS)
import CheckCore
import SwiftUI
import UIKit

/// 가입 화면(w16 · 재디자인 B — 로그인과 같은 틀: 가운데 정렬 · 인셋 그룹 입력 · 채운 버튼 하나). 규칙은 전부 `MobileSignUpStore` 에 있다.
///
/// 칸 순서는 맥 가입 폼 그대로다: 별명 → 이메일 → 비밀번호 → 소속 센터 → 팀 코드(또는 팀 이름·주간 목표).
/// 센터는 **미선택이 기본**이고 고르기 전엔 채운 버튼이 비활성이다(스토어 `canSubmit`). 키보드 제출은 버튼을 보지 않고 스토어 가드를
/// 지나 이유를 말한다(맥 `submitPrimary` 주석 — 비활성만 두면 왜 막혔는지 말할 기회가 없다).
///
/// ★ 한글 조합(별명·팀 이름): iOS 도 조합 중인 마지막 음절은 marked text 라 바인딩에 아직 없다 — 메시지 입력줄이 겪은 결함
///   (`MessagesComposerView` 머리 주석 · 맥 v0.3.14 "팀명 마지막 글자 유실"). 여기서는 제출 전에 포커스를 내려 UIKit 이 조합을 확정해
///   바인딩에 싣게 한 뒤, 다음 차례에 스토어를 부른다(`submit()`). 키보드의 제출 키는 조합을 확정한 뒤 `onSubmit` 을 부른다(오목 채팅 실측).
///
/// ★ 가입 이메일 인증코드(w16 · SPEC-signup-otp 작업 P): 계정이 만들어졌는데 세션이 없으면(설정을 켠 서버) 이 화면이 **코드 단계**로
///   바뀐다. 코드 칸은 비밀번호 재설정과 같은 부품(`MobileCodeEntryGroup`)이다. 지금 서버(가입 즉시 세션)에서는 이 단계가 아예 뜨지 않는다.
struct MobileSignUpView: View {
    @State private var store: MobileSignUpStore
    @State private var previewDebounce: Task<Void, Never>?
    @State private var copiedCode = false
    /// 인증 코드는 **화면이 쥔다**(스토어에 남기지 않는다 — 화면을 벗어나면 사라지는 게 맞다, 재설정과 같다).
    @State private var code = ""
    /// 출구로 들어왔을 때 한 번만 코드를 보낸다(뷰가 다시 그려질 때마다 메일이 나가면 서버 간격에 걸린다).
    @State private var confirmEmail: String?
    @State private var didBeginConfirmation = false
    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = MobileLoginMetrics.iconWidth

    private enum Field { case displayName, email, password, teamCode, teamName, code }

    /// 코드 미리보기 디바운스(맥 `TeamCodeField` 와 같은 0.5초).
    static let previewDebounceSeconds: Double = 0.5

    init(session: MobileSessionStore, createTeam: Bool) {
        _store = State(initialValue: MobileSignUpStore(session: session, createTeam: createTeam))
    }

    /// 미확인 계정의 출구(`MobileAuthRoute.signUpConfirm`) — 가입 폼을 건너뛰고 코드 단계로 연다. 계정은 이미 있으므로
    /// 들어가면서 코드를 **다시 보낸다**(`beginConfirmation`).
    init(session: MobileSessionStore, confirmEmail: String) {
        _store = State(initialValue: MobileSignUpStore(session: session))
        _confirmEmail = State(initialValue: confirmEmail)
    }

    var body: some View {
        @Bindable var store = store
        MobileCenteredScreen {
            VStack(spacing: 0) {
                MobileBrandHeader(mood: store.stage == .confirmCode ? .plain : .working, title: store.title, message: store.headline)

                switch store.stage {
                case .account:
                    accountGroup
                        .padding(.top, MobileTheme.space6)
                    centerGroup
                        .padding(.top, MobileTheme.space3)
                    teamBlock
                        .padding(.top, MobileTheme.space3)
                case .confirmCode:
                    MobileCodeEntryGroup(sentToEmail: store.confirmSentEmail, code: $code, field: Field.code, focused: $focused, onSubmit: submit)
                        .padding(.top, MobileTheme.space6)
                case .teamless:
                    InlineNotice(text: MobileSignUpText.accountCreatedNotice, kind: .info)
                        .padding(.top, MobileTheme.space6)
                    teamBlock
                        .padding(.top, MobileTheme.space3)
                case .createdTeam(let code):
                    createdCard(code)
                        .padding(.top, MobileTheme.space6)
                }

                if let notice = store.notice {
                    InlineNotice(text: notice, kind: store.noticeIsError ? .error : .info)
                        .padding(.top, MobileTheme.space3)
                }

                // 미확인 계정의 출구 — "이미 가입된 이메일"에서 코드 화면으로 간다(가입 도중 앱을 닫은 사람의 유일한 길).
                if store.offersConfirmationExit {
                    AingButton(MobileSignUpText.confirmExit, kind: .plain, size: .sm) { beginConfirmation(email: store.email) }
                        .disabled(store.isSubmitting || store.isResending)
                        .padding(.top, MobileTheme.space2)
                }

                AingButton(store.primaryTitle, kind: .filled, size: .lg, fillsWidth: true, isBusy: store.isSubmitting, action: submit)
                    .disabled(!store.isPrimaryEnabled(code: code))
                    .padding(.top, MobileTheme.space4)

                // 약관 동의 한 줄(앱스토어 1.2) — 계정이 실제로 만들어지는 단계에만 선다. 이미 계정이 있는 단계
                // (코드 확인 · 팀 없음 · 팀 생성 완료)에서 다시 말하면 "또 동의해야 하나"로 읽힌다.
                if store.stage == .account {
                    termsNotice
                }

                switch store.stage {
                case .createdTeam:
                    EmptyView()
                case .confirmCode:
                    // 재전송 + 고정 도움말(이미 인증된 계정이면 메일이 오지 않는다 — 그 사람이 할 일은 로그인이다).
                    MobileResendRow(title: store.resendTitle, isEnabled: store.isResendEnabled) {
                        Task { await store.resendCode() }
                    }
                    .padding(.top, MobileTheme.space2)
                    Text(MobileSignUpText.confirmHelp)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, MobileTheme.space2)
                case .account, .teamless:
                    modeSwitch
                        .padding(.top, MobileTheme.space2)
                }
            }
        } footer: {
            EmptyView()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut(duration: 0.22), value: store.stage)
        .task {
            // 출구로 열렸으면 코드를 보내고 코드 단계에 선다. 한 번만(다시 그려질 때마다 메일이 나가면 서버 간격에 걸린다).
            guard let confirmEmail, !didBeginConfirmation else { return }
            didBeginConfirmation = true
            await store.beginConfirmation(email: confirmEmail)
        }
        // 코드 단계로 넘어가면 커서를 코드 칸으로 — 없으면 사용자가 칸부터 눌러야 한다(재설정 화면과 같다).
        .onChange(of: store.stage) { _, stage in
            if stage == .confirmCode { focused = .code } else if focused == .code { focused = nil }
        }
        .onChange(of: store.teamCode) { _, new in
            // 대문자 · 공백/하이픈 제거(맥 TeamCodeField 의 uppercases + allowsSpace:false). 바뀔 때만 되써 루프를 만들지 않는다.
            let normalized = SupabaseWorkService.normalizeInviteCode(new)
            if normalized != new {
                store.teamCode = normalized
                return
            }
            previewDebounce?.cancel()
            previewDebounce = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.previewDebounceSeconds))
                guard !Task.isCancelled else { return }
                store.previewTeamCode()
            }
        }
        // 화면을 떠나면 날아가 있는 왕복과 카운트다운만 끊는다(상태는 그대로 — 서버의 계정은 미확인으로 남고,
        // 다음 로그인/가입 시도의 문구가 다시 이 화면으로 데려온다).
        .onDisappear {
            previewDebounce?.cancel()
            store.cancelPendingWork()
        }
    }

    // MARK: - 계정 칸

    private var accountGroup: some View {
        @Bindable var store = store
        return InsetGroup {
            inputRow("person.text.rectangle") {
                TextField(text: $store.displayName, prompt: prompt(MobileSignUpText.displayName)) { Text(MobileSignUpText.displayName) }
                    .textContentType(.nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focused, equals: .displayName)
                    .onSubmit { focused = .email }
                    .font(.body)
                    .foregroundStyle(MobileTheme.label)
            }
            inputRow("envelope") {
                TextField(text: $store.email, prompt: prompt(MobileSignUpText.email)) { Text(MobileSignUpText.email) }
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
            inputRow("lock", last: true) {
                SecureField(text: $store.password, prompt: prompt(MobileSignUpText.password)) { Text(MobileSignUpText.password) }
                    .textContentType(.newPassword)
                    .submitLabel(.next)
                    .focused($focused, equals: .password)
                    .onSubmit { focused = store.isCreateTeamMode ? .teamName : .teamCode }
                    .font(.body)
                    .foregroundStyle(MobileTheme.label)
            }
        }
    }

    // MARK: - 소속 센터(기본 미선택)

    /// 두 행(서울 · 부산) 중 고른 행에만 체크 — 기본값을 주지 않는다(맥 `CenterChoiceCells` 주석: 기본을 서울로 두면 부산 연수생이
    /// 아무것도 안 하고 서울로 잡히고 본인은 그 사실조차 모른다).
    private var centerGroup: some View {
        VStack(alignment: .leading, spacing: MobileTheme.space2) {
            Text(MobileSignUpText.centerLabel)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .padding(.leading, MobileTheme.cardPadding)
            InsetGroup {
                let values = CenterLabel.allServerValues
                ForEach(Array(values.enumerated()), id: \.element) { index, value in
                    let isSelected = store.center == value
                    GroupRow(divider: index == values.count - 1 ? .none : .inset(MobileTheme.cardPadding)) {
                        Button {
                            store.center = value
                        } label: {
                            HStack(spacing: MobileTheme.space3) {
                                Text(CenterLabel.display(value) ?? value)
                                    .font(.body)
                                    .foregroundStyle(MobileTheme.label)
                                Spacer(minLength: 8)
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.body)
                                    .foregroundStyle(isSelected ? MobileTheme.accent : MobileTheme.label3)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(CenterLabel.display(value) ?? value))
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
            }
        }
    }

    // MARK: - 팀 칸(코드 ↔ 만들기)

    @ViewBuilder
    private var teamBlock: some View {
        @Bindable var store = store
        if store.isCreateTeamMode {
            InsetGroup {
                inputRow("person.3") {
                    // 팀 이름은 한글 허용(ASCII 강제 없음 — 맥과 같다).
                    TextField(text: $store.createTeamName, prompt: prompt(MobileSignUpText.teamName)) { Text(MobileSignUpText.teamName) }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused, equals: .teamName)
                        .onSubmit(submit)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label)
                }
                GroupRow(divider: .none, minHeight: MobileLoginMetrics.rowHeight) {
                    fieldIcon("target")
                    Text(MobileSignUpText.weeklyGoal)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label)
                    Spacer(minLength: 8)
                    Text(MobileSignUpText.goalHours(store.createTeamGoalHours))
                        .font(MobileTheme.number(.body))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                    // 범위 1~168 시간(맥 WeeklyGoalStepper).
                    Stepper(value: $store.createTeamGoalHours, in: MobileSignUpStore.goalHoursRange) {
                        Text(MobileSignUpText.weeklyGoal)
                    }
                    .labelsHidden()
                    .accessibilityLabel(Text(MobileSignUpText.weeklyGoal))
                    .accessibilityValue(Text(MobileSignUpText.goalHours(store.createTeamGoalHours)))
                }
            }
        } else {
            InsetGroup {
                inputRow("key", last: true) {
                    TextField(text: $store.teamCode, prompt: prompt(MobileSignUpText.teamCode)) { Text(MobileSignUpText.teamCode) }
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.go)
                        .focused($focused, equals: .teamCode)
                        .onSubmit(submit)
                        .font(.body)
                        .foregroundStyle(MobileTheme.label)
                }
            }
            // 미리보기 한 줄: 찾은 팀 요약(안내색) · 못 찾음/확인 중(못 찾음은 오류색). 없으면 자리도 없다.
            if let line = store.previewLine {
                InlineNotice(text: line.text, kind: line.isSuccess || line.text == MobileSignUpText.previewChecking ? .info : .error)
                    .padding(.top, MobileTheme.space2)
            }
        }
    }

    /// "가입하면 이용약관과 개인정보 처리방침에 동의하는 것으로 봅니다" — 두 낱말이 곧 링크다(`termsAgreementAttributed`).
    /// 누르면 시스템 브라우저가 GitHub Pages 문서를 연다(약관 본문에 괴롭힘·혐오·음란물 무관용과 계정 정지가 적혀 있다).
    private var termsNotice: some View {
        Text(MobileSignUpText.termsAgreementAttributed)
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .tint(MobileTheme.accent)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.top, MobileTheme.space3)
    }

    /// 코드 입력 ↔ 팀 만들기 전환(맥 AuthLinkButton "팀 코드가 없나요? 새 팀 만들기" / "코드로 참여하기").
    private var modeSwitch: some View {
        HStack(spacing: 2) {
            if !store.isCreateTeamMode {
                Text(MobileSignUpText.noCodePrompt)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
            }
            AingButton(store.isCreateTeamMode ? MobileSignUpText.switchToCode : MobileSignUpText.switchToCreate, kind: .plain, size: .sm) {
                withAnimation(.easeInOut(duration: 0.22)) { store.toggleCreateTeamMode() }
            }
            .disabled(store.isSubmitting)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 팀 생성 완료 카드(맥 CreatedTeamCodeCard)

    private func createdCard(_ code: String) -> some View {
        InsetGroup {
            GroupRow(divider: .inset(MobileTheme.cardPadding), minHeight: MobileTheme.rowHeightTwoLine) {
                Text(code)
                    .font(MobileTheme.number(.title))
                    .monospacedDigit()
                    .tracking(3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(MobileTheme.label)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("참여코드 \(code.map(String.init).joined(separator: " "))"))
            }
            GroupRow(divider: .none) {
                Text(MobileSignUpText.createdBody)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                AingButton(copiedCode ? MobileSignUpText.copied : MobileSignUpText.copy, systemImage: copiedCode ? "checkmark" : "doc.on.doc", kind: .tinted, size: .sm) {
                    UIPasteboard.general.string = code
                    copiedCode = true
                }
            }
        }
    }

    // MARK: - 공용 조각(로그인 화면과 같은 모양)

    private func inputRow<Content: View>(_ icon: String, last: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        GroupRow(
            divider: last ? .none : .inset(MobileTheme.cardPadding + iconWidth + MobileTheme.space3),
            minHeight: MobileLoginMetrics.rowHeight
        ) {
            fieldIcon(icon)
            content()
        }
    }

    /// 자리표시자: 3단 글자(회색) — 로그인 화면과 같다.
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

    /// 조합 확정(포커스 내리기) → 다음 차례에 스토어 제출(머리 주석 ★). 막는 일은 스토어 가드가 한다 — 여기서 먼저 끊지 않는다.
    /// 코드 단계의 주 버튼만 다른 함수를 탄다(코드는 화면이 쥐므로 값을 실어 보낸다 — 재설정 화면과 같은 규약).
    private func submit() {
        focused = nil
        let code = code
        Task { @MainActor in
            await Task.yield()
            if store.stage == .confirmCode {
                await store.verifyCode(code)
            } else {
                store.submit()
            }
        }
    }

    /// 미확인 계정의 출구(가입 화면 안 · "이미 가입된 이메일"). 코드 칸은 비우고 시작한다 — 새 코드가 올 것이다.
    private func beginConfirmation(email: String) {
        focused = nil
        code = ""
        Task { @MainActor in
            await Task.yield()
            await store.beginConfirmation(email: email)
        }
    }
}
#endif
