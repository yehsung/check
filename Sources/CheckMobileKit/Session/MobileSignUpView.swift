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
struct MobileSignUpView: View {
    @State private var store: MobileSignUpStore
    @State private var previewDebounce: Task<Void, Never>?
    @State private var copiedCode = false
    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = MobileLoginMetrics.iconWidth

    private enum Field { case displayName, email, password, teamCode, teamName }

    /// 코드 미리보기 디바운스(맥 `TeamCodeField` 와 같은 0.5초).
    static let previewDebounceSeconds: Double = 0.5

    init(session: MobileSessionStore, createTeam: Bool) {
        _store = State(initialValue: MobileSignUpStore(session: session, createTeam: createTeam))
    }

    var body: some View {
        @Bindable var store = store
        MobileCenteredScreen {
            VStack(spacing: 0) {
                MobileBrandHeader(mood: .working, title: MobileSignUpText.title, message: store.headline)

                switch store.stage {
                case .account:
                    accountGroup
                        .padding(.top, MobileTheme.space6)
                    centerGroup
                        .padding(.top, MobileTheme.space3)
                    teamBlock
                        .padding(.top, MobileTheme.space3)
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
                    InlineNotice(text: notice, kind: .error)
                        .padding(.top, MobileTheme.space3)
                }

                AingButton(store.primaryTitle, kind: .filled, size: .lg, fillsWidth: true, isBusy: store.isSubmitting, action: submit)
                    .disabled(!store.canSubmit)
                    .padding(.top, MobileTheme.space4)

                if case .createdTeam = store.stage {
                    EmptyView()
                } else {
                    modeSwitch
                        .padding(.top, MobileTheme.space2)
                }
            }
        } footer: {
            EmptyView()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
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
        .onDisappear { previewDebounce?.cancel() }
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
    private func submit() {
        focused = nil
        Task { @MainActor in
            await Task.yield()
            store.submit()
        }
    }
}
#endif
