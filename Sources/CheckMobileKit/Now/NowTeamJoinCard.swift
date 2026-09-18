#if os(iOS)
import CheckCore
import SwiftUI

/// 무소속 카드(재디자인 B 토큰만): 안내 카드 → 팀 칸(코드 · 또는 이름 + 주간 목표) → 미리보기 줄 → 채운 버튼 하나 → 모드 전환.
///
/// 가입 화면(`MobileSignUpView`)의 팀 칸과 **같은 모양·같은 문구**다. 규칙(정규화 · 디바운스 · 가드 · 왕복)은
/// `MobileTeamJoinForm` 과 `NowTeamJoinStore` 가 쥔다 — 여기서는 그리기만 한다.
///
/// 성공하면 지금 탭이 소속을 다시 읽어 팀 화면이 된다(`NowStore.adoptSettledTeam`). 재로그인은 요구하지 않는다.
struct NowTeamJoinSection: View {
    let store: NowTeamJoinStore
    @State private var previewDebounce: Task<Void, Never>?
    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = MobileLoginMetrics.iconWidth

    private enum Field { case teamCode, teamName }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(NowText.noTeamTitle)
                    .font(.headline)
                    .foregroundStyle(MobileTheme.label)
                Text(NowText.noTeamBody)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .cardSegmentRow(.single, padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))

            // 코드 정규화·미리보기 디바운스는 **칸이 있는 이 줄에** 건다(절 전체에 걸면 절 안의 줄마다 한 번씩 돈다).
            teamFields
                .onChange(of: store.form.teamCode) { _, new in
                    // 대문자 · 공백/하이픈 제거(맥 TeamCodeField 의 uppercases + allowsSpace:false). 바뀔 때만 되써 루프를 만들지 않는다.
                    let normalized = SupabaseWorkService.normalizeInviteCode(new)
                    if normalized != new {
                        store.form.teamCode = normalized
                        return
                    }
                    previewDebounce?.cancel()
                    previewDebounce = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(MobileSignUpView.previewDebounceSeconds))
                        guard !Task.isCancelled else { return }
                        store.form.previewTeamCode()
                    }
                }
                .onDisappear {
                    // 칸이 사라졌으면 칠 곳도 없다 — 날아가 있는 미리보기만 끊는다(친 값은 그대로).
                    previewDebounce?.cancel()
                    store.cancelPendingWork()
                }
                .cardListPlainRow(top: 12, bottom: 0)

            // 코드 칸 아래 한 줄: 찾은 팀 요약(안내색) · 확인 중(안내색) · 못 찾음/다른 센터(오류색).
            if let line = store.previewLine {
                InlineNotice(
                    text: line.text,
                    kind: line.isSuccess || line.text == MobileSignUpText.previewChecking ? .info : .error
                )
                .cardListPlainRow(top: 8, bottom: 0)
            }

            if let notice = store.notice {
                InlineNotice(text: notice, kind: .error)
                    .cardListPlainRow(top: 8, bottom: 0)
            }

            VStack(spacing: MobileTheme.space2) {
                AingButton(
                    store.primaryTitle,
                    kind: .filled,
                    size: .lg,
                    fillsWidth: true,
                    isBusy: store.isSubmitting,
                    action: submit
                )
                .disabled(!store.canSubmit)
                modeSwitch
            }
            .cardListPlainRow(top: 12, bottom: 4)
        }
    }

    // MARK: - 팀 칸(코드 ↔ 만들기 — 가입 화면 `teamBlock` 과 같은 모양)

    @ViewBuilder
    private var teamFields: some View {
        @Bindable var form = store.form
        if form.isCreateTeamMode {
            InsetGroup {
                GroupRow(divider: .inset(MobileTheme.cardPadding + iconWidth + MobileTheme.space3), minHeight: MobileLoginMetrics.rowHeight) {
                    fieldIcon("person.3")
                    // 팀 이름은 한글 허용(ASCII 강제 없음 — 맥과 같다).
                    TextField(text: $form.createTeamName, prompt: prompt(MobileSignUpText.teamName)) { Text(MobileSignUpText.teamName) }
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
                    Text(MobileSignUpText.goalHours(form.createTeamGoalHours))
                        .font(MobileTheme.number(.body))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                    // 범위 1~168 시간(맥 WeeklyGoalStepper · 가입 화면과 같다).
                    Stepper(value: $form.createTeamGoalHours, in: MobileTeamJoinForm.goalHoursRange) {
                        Text(MobileSignUpText.weeklyGoal)
                    }
                    .labelsHidden()
                    .accessibilityLabel(Text(MobileSignUpText.weeklyGoal))
                    .accessibilityValue(Text(MobileSignUpText.goalHours(form.createTeamGoalHours)))
                }
            }
        } else {
            InsetGroup {
                GroupRow(divider: .none, minHeight: MobileLoginMetrics.rowHeight) {
                    fieldIcon("key")
                    TextField(text: $form.teamCode, prompt: prompt(MobileSignUpText.teamCode)) { Text(MobileSignUpText.teamCode) }
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
        }
    }

    /// 코드 입력 ↔ 팀 만들기 전환(가입 화면과 같은 문구).
    private var modeSwitch: some View {
        HStack(spacing: 2) {
            if !store.form.isCreateTeamMode {
                Text(MobileSignUpText.noCodePrompt)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
            }
            AingButton(store.form.isCreateTeamMode ? MobileSignUpText.switchToCode : MobileSignUpText.switchToCreate, kind: .plain, size: .sm) {
                focused = nil
                withAnimation(.easeInOut(duration: 0.22)) { store.toggleCreateTeamMode() }
            }
            .disabled(store.isSubmitting)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 조각(가입 화면과 같은 모양)

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

    /// 한글 조합(팀 이름)을 확정하려고 포커스를 내린 뒤 다음 차례에 스토어를 부른다(가입 화면 머리 주석 ★ — 마지막 음절 유실).
    /// 막는 일은 스토어 가드가 한다 — 여기서 먼저 끊지 않는다.
    private func submit() {
        focused = nil
        Task { @MainActor in
            await Task.yield()
            store.submit()
        }
    }
}
#endif
