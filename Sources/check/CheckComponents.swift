import AppKit
import SwiftUI

// MARK: - Start / Stop pill

struct WorkTogglePill: View {
    let isWorking: Bool
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isWorking ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .black))
                Text(isWorking ? "근무 종료" : "근무 시작")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(
                Capsule()
                    .fill(isWorking ? CheckTheme.stopGradient : CheckTheme.startGradient)
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .brightness(hovering ? 0.06 : 0)
            .shadow(color: (isWorking ? CheckTheme.pending : CheckTheme.working).opacity(0.30), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }
}

// MARK: - Chips

struct StatusChip: View {
    let isWorking: Bool

    var body: some View {
        Text(isWorking ? "근무중" : "근무종료")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isWorking ? .white : CheckTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if isWorking {
                    Capsule().fill(CheckTheme.working.opacity(0.85))
                } else {
                    Capsule().stroke(CheckTheme.border, lineWidth: 1)
                }
            }
            .fixedSize()
    }
}

/// 팀원 3상태 칩. 라이브 근무(초록 "근무중"), 연결 끊김(앰버 "연결 끊김"), 근무종료(회색 테두리).
struct PresenceChip: View {
    let presence: MemberPresence

    private var label: String {
        switch presence {
        case .activeWorking: return "근무중"
        case .staleWorking: return "연결 끊김"
        case .offWork: return "근무종료"
        }
    }

    private var tint: Color {
        switch presence {
        case .activeWorking: return CheckTheme.working
        case .staleWorking: return CheckTheme.pending
        case .offWork: return CheckTheme.secondaryText
        }
    }

    private var isOff: Bool {
        if case .offWork = presence { return true }
        return false
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isOff ? CheckTheme.secondaryText : .white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if isOff {
                    Capsule().stroke(CheckTheme.border, lineWidth: 1)
                } else {
                    Capsule().fill(tint.opacity(0.85))
                }
            }
            .fixedSize()
    }
}

struct CountChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(CheckTheme.working)
                .frame(width: 6, height: 6)
            Text("\(count)명 근무중")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.working)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(CheckTheme.working.opacity(0.16)))
        .fixedSize()
    }
}

// MARK: - Weekly goal gauge

struct TeamGoalGauge: View {
    let goal: TeamWeeklyGoal
    /// 진행 시간 앞에 붙이는 접두어. 내 팀 카드의 "내 진행률" 게이지는 "내 " 를 붙여 총합이 아님을 드러낸다.
    var workedLabelPrefix: String = ""
    /// 목표 시간 앞에 붙이는 접두어. "각자 " 를 붙여 목표가 팀 총합이 아니라 1인당임을 드러낸다.
    var goalLabelPrefix: String = ""

    private var percent: Int {
        Int((goal.progress * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Text("주간 목표")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text("\(workedLabelPrefix)\(MenuBarStatusFormatter.hoursMinutes(goal.workedSeconds)) / \(goalLabelPrefix)\(MenuBarStatusFormatter.hoursMinutes(goal.goalSeconds))")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if goal.isComplete {
                    Label("완료", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.working)
                        .lineLimit(1)
                } else {
                    Text("\(percent)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .monospacedDigit()
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CheckTheme.trackFill)
                    Capsule()
                        .fill(CheckTheme.gaugeGradient)
                        .frame(width: max(8, proxy.size.width * goal.progress))
                        .shadow(color: CheckTheme.working.opacity(0.35), radius: 4, y: 1)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Weekly goal percent

/// 주간 목표 진행 퍼센트(정수). 실제 비율 기반이라 100%를 넘을 수 있고(상한 999%), 음수는 0으로 둔다.
/// 헤더 목표 바 캡션과 단위 테스트가 같은 계산을 쓰도록 한곳에 둔다.
enum GoalPercentFormatter {
    static func percent(workedSeconds: Int, goalSeconds: Int) -> Int {
        let worked = max(0, workedSeconds)
        let goal = max(1, goalSeconds)
        let raw = Int((Double(worked) / Double(goal) * 100).rounded())
        return min(999, max(0, raw))
    }
}

// MARK: - Team member row

struct TeamMemberRow: View {
    let name: String
    var avatarURL: URL? = nil
    let presence: MemberPresence
    let primaryDetail: String
    /// stale(연결 끊김) 상태의 "마지막 확인 N분 전" 보조줄. 그 외 상태에선 nil(한 줄만).
    var secondaryDetail: String? = nil
    /// 1인당 주간 목표 달성 여부. true면 주간 시간 옆에 은은한 ✓(working 그린)를 붙인다. 행 높이는 불변.
    var meetsWeeklyGoal: Bool = false
    /// 이 팀원의 1인당 주간 목표 진행 비율(0~1 클램프). non-nil 이면 텍스트 칼럼 밑에 슬림 바 + 우측 %를 그린다.
    /// nil(빈 팀 placeholder 등)이면 바를 그리지 않는다.
    var goalFraction: Double? = nil
    /// 내 행 여부. true면 아바타에 hover 카메라 배지 + 파일 선택을 붙인다.
    var isMe: Bool = false
    /// 내 행 아바타 교체 시 다운스케일된 JPEG Data를 전달받는 콜백.
    var onPickAvatar: ((Data) -> Void)? = nil

    // 아바타 칼럼(26) + 상단 HStack 간격(10). 목표 바를 텍스트 칼럼 시작점부터 그리도록 들여쓸 폭.
    private static let textColumnInset: CGFloat = 26 + 10

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(primaryDetail)
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .lineLimit(1)
                        if meetsWeeklyGoal {
                            // 은은한 목표 달성 표식 — 주간 목표(1인당)를 채운 팀원. 과하지 않게 작은 체크만.
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(CheckTheme.working.opacity(0.9))
                                .accessibilityLabel("주간 목표 달성")
                        }
                    }
                    if let secondaryDetail {
                        Text(secondaryDetail)
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.pending)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                PresenceChip(presence: presence)
            }
            if let goalFraction {
                // 바는 아바타가 아니라 텍스트 칼럼 시작점부터 행 우측 끝까지. 위치가 "이 팀원의 진행률"임을 말한다.
                goalBar(fraction: goalFraction)
                    .padding(.leading, Self.textColumnInset)
            }
        }
    }

    // 슬림 진행 바(높이 3pt) + 우측 끝 % 캡션. 달성 시 working, 미달 시 accent 로 채운다(트랙은 기존 게이지 관례).
    private func goalBar(fraction: Double) -> some View {
        let clamped = min(1, max(0, fraction))
        return HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CheckTheme.trackFill)
                    Capsule()
                        .fill(fraction >= 1.0 ? CheckTheme.working : CheckTheme.accent)
                        .frame(width: max(0, proxy.size.width * clamped))
                }
            }
            .frame(height: 3)
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .monospacedDigit()
                .fixedSize()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if isMe, let onPickAvatar {
            EditableAvatarView(name: name, avatarURL: avatarURL, size: 26, onPick: onPickAvatar)
        } else {
            CheckAvatarView(name: name, avatarURL: avatarURL, size: 26)
        }
    }
}

// MARK: - Team weekly totals (per-team list)

/// 팀 한 행: 이니셜 아바타 + 팀명(+우리 팀 칩) + 1인당 평균 근무시간 + 평균/목표 미니 게이지·% +
/// "각자 목표 G시간 · 총 X시간 · N명 · M명 근무중" 캡션. weekly_goal_hours 가 1인당 목표라 메인 숫자·게이지·%
/// 는 모두 총합이 아니라 평균 기준이다. 우리 팀에는 은은한 "우리 팀" 칩만 붙고 순위/경쟁 표기는 없다.
/// 높이는 LeaderboardPanel 이 고정으로 준다.
struct LeaderboardRow: View {
    let entry: TeamLeaderboardEntry
    var isMyTeam: Bool = false

    // 1인당 평균 대비 목표 진행률 게이지(entry.goal 이 평균 기준으로 계산됨).
    private var goal: TeamWeeklyGoal {
        entry.goal
    }

    private var percent: Int {
        Int((goal.progress * 100).rounded())
    }

    // "각자 목표 G시간 · 총 X시간 · N명 · M명 근무중" — 팀마다 목표가 다를 수 있어 각 행에 목표시간을 명시한다.
    private var caption: String {
        "각자 목표 \(entry.weeklyGoalHours)시간 · 총 \(MenuBarStatusFormatter.hoursMinutes(entry.totalSeconds)) · \(entry.memberCount)명 · \(entry.workingCount)명 근무중"
    }

    var body: some View {
        HStack(spacing: 11) {
            // 팀명 해시색 이니셜 아바타(팀원 행 아바타와 같은 톤). 순위 배지 대신 담백한 표식.
            CheckAvatarView(name: entry.name, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    if isMyTeam {
                        Text("우리 팀")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CheckTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
                            .fixedSize()
                    }
                    Spacer(minLength: 6)
                    // 메인 숫자 = 1인당 평균("평균 X시간 Y분") — 총합이 아니라 팀원 한 명 기준임을 문구로 드러낸다.
                    Text("평균 \(MenuBarStatusFormatter.hoursMinutes(entry.averageSeconds))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    miniGauge
                    Text("\(percent)%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                        .fixedSize()
                }
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var miniGauge: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CheckTheme.trackFill)
                Capsule()
                    .fill(CheckTheme.gaugeGradient)
                    .frame(width: max(6, proxy.size.width * goal.progress))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Long-session (12h) confirmation banner

/// 연속 12시간 근무 시 헤더에 덧씌우는 앰버 확인 배너.
/// "12시간 넘게 근무 중이에요 — 아직 근무 중이신가요?" + [네, 근무 중이에요] 액션.
/// 헤더 카드 위 overlay로 얹혀 레이아웃 높이를 바꾸지 않는다(창 튐 방지).
struct LongSessionBanner: View {
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CheckTheme.pending)
            VStack(alignment: .leading, spacing: 2) {
                Text("12시간 넘게 근무 중이에요")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Text("아직 근무 중이신가요?")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button(action: onConfirm) {
                Text("네, 근무 중이에요")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Capsule().fill(CheckTheme.pending))
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.pending.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.pending.opacity(0.55), lineWidth: 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CheckTheme.panel)
                )
        )
    }
}

// MARK: - Auth buttons + fields

struct AuthButton: View {
    let title: String
    let icon: String
    var prominent: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(prominent ? .white : CheckTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background {
                    if prominent {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(CheckTheme.startGradient)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.border, lineWidth: 1))
                    }
                }
                .brightness(hovering ? 0.05 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CredentialField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var isSecure = false
    /// true면 포커스 시 영어 자판으로 자동 전환하고, 비-ASCII 입력을 걸러 낸 뒤 안내를 띄운다.
    var enforcesASCII = false
    /// 공백 허용 여부. 비밀번호는 허용, 이메일은 차단한다. `enforcesASCII`일 때만 의미가 있다.
    var allowsSpace = true
    /// true면 입력값을 대문자로 정규화해 표시한다(팀 코드 필드용). ASCII 필터와 함께 쓸 수 있다.
    var uppercases = false
    /// 외부(패널) 포커스 상태. Enter-키 체이닝을 위해 부모가 소유하고 각 필드가 자기 케이스로 바인딩한다.
    /// nil이면 내부 isFocused만 쓰는 독립 필드(단위 테스트 등)로 동작한다.
    var focus: FocusState<AuthFocusField?>.Binding?
    /// 이 필드가 대응하는 포커스 케이스. `focus`와 함께 주어져야 체이닝이 활성화된다.
    var fieldIdentifier: AuthFocusField?
    /// 리턴 키 라벨. 다음 필드로 넘기는 필드는 `.next`, 제출 필드는 `.go`.
    var submitLabel: SubmitLabel = .return
    /// Enter(제출) 시 실행할 동작 — 다음 필드로의 포커스 이동 또는 로그인/가입 제출.
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var showWarning: Bool
    @State private var warningTask: Task<Void, Never>?

    init(
        title: String,
        icon: String,
        text: Binding<String>,
        isSecure: Bool = false,
        enforcesASCII: Bool = false,
        allowsSpace: Bool = true,
        uppercases: Bool = false,
        warnsInitially: Bool = false,
        focus: FocusState<AuthFocusField?>.Binding? = nil,
        fieldIdentifier: AuthFocusField? = nil,
        submitLabel: SubmitLabel = .return,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.icon = icon
        self._text = text
        self.isSecure = isSecure
        self.enforcesASCII = enforcesASCII
        self.allowsSpace = allowsSpace
        self.uppercases = uppercases
        // warnsInitially는 렌더 스냅샷 등 미리보기에서 안내가 켜진 상태를 재현하기 위한 시드값이다.
        self._showWarning = State(initialValue: warnsInitially)
        self.focus = focus
        self.fieldIdentifier = fieldIdentifier
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(width: 16)
                ZStack(alignment: .leading) {
                    // 플레이스홀더는 비었을 때만 깔고, 히트테스트 대상에서 제외한다.
                    if text.isEmpty {
                        Text(title)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                    styledField
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CheckTheme.fieldFill)
                    // 안내가 떠 있는 동안엔 테두리를 danger로 물들여 레이아웃 밀림 없이도 상태를 알린다.
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(showWarning ? CheckTheme.danger : CheckTheme.border, lineWidth: 1))
            )
            if enforcesASCII {
                // 안내 캡션은 항상 자리를 차지하고 보임/숨김만 opacity로 토글한다 — 등장/소멸로 인한
                // 높이 변화(창 튐)를 원천 제거한다. ASCII 필드(이메일·비밀번호)만 슬롯을 확보한다.
                Text("영어 문자만 입력할 수 있어요")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CheckTheme.danger)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(showWarning ? 1 : 0)
                    .accessibilityHidden(!showWarning)
                    .accessibilityLabel("영어 문자만 입력할 수 있어요")
            }
        }
        .onChange(of: isFocused) { _, focused in
            // 외부 포커스를 안 쓰는 독립 필드 경로: 포커스를 얻는 순간 영어 자판으로 전환한다.
            guard focused, enforcesASCII else { return }
            EnglishInputSource.activate()
        }
        .onChange(of: focus?.wrappedValue) { _, newValue in
            // 외부 포커스 체이닝 경로: 이 필드로 포커스가 옮겨 오면 영어 자판으로 전환한다.
            guard let fieldIdentifier, newValue == fieldIdentifier, enforcesASCII else { return }
            EnglishInputSource.activate()
        }
        .onChange(of: text) { _, newValue in
            guard enforcesASCII || uppercases else { return }
            var cleaned = newValue
            var asciiRemoved = false
            if enforcesASCII {
                let filtered = ASCIIInputFilter.filtered(cleaned, allowsSpace: allowsSpace)
                asciiRemoved = filtered != cleaned
                cleaned = filtered
            }
            if uppercases {
                cleaned = cleaned.uppercased()
            }
            // cleaned == newValue면 대입을 건너뛰어 IME 조합 중간 상태에서의 무한루프를 막는다.
            if cleaned != newValue {
                text = cleaned
            }
            // 안내는 ASCII 필터가 실제로 문자를 제거했을 때만 띄운다(대문자화는 안내 대상이 아님).
            if asciiRemoved {
                triggerWarning()
            }
        }
        .onDisappear {
            warningTask?.cancel()
        }
    }

    // 안내 캡션을 띄우고 약 2.5초 뒤 자동으로 감춘다. 연속 트리거 시 이전 타이머를 리셋한다.
    private func triggerWarning() {
        warningTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            showWarning = true
        }
        warningTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showWarning = false
            }
        }
    }

    // 공통 스타일 + 제출/포커스 배선을 얹은 실제 입력 필드.
    // 외부 포커스가 주어지면 자기 케이스로 바인딩(체이닝), 없으면 내부 isFocused로 동작한다.
    @ViewBuilder
    private var styledField: some View {
        let base = field
            .textFieldStyle(.plain)
            .foregroundStyle(CheckTheme.primaryText)
            .tint(CheckTheme.accent)
            .accessibilityLabel(title)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
        if let focus, let fieldIdentifier {
            base.focused(focus, equals: fieldIdentifier)
        } else {
            base.focused($isFocused)
        }
    }

    @ViewBuilder
    private var field: some View {
        // 플레이스홀더는 위 Text 오버레이가 담당하므로 라벨은 비운다.
        if isSecure {
            SecureField("", text: $text)
        } else {
            TextField("", text: $text)
        }
    }
}

// MARK: - Team code preview slot (signup / teamless)

/// 팀 코드 필드 아래 고정 높이 슬롯. 코드 미리보기 결과를 한 줄로 보여 준다.
/// - 성공(joinPreview 있음): 그린 "✓ 팀 브라보 · 3명 · 주 60시간"
/// - 실패/안내(joinPreviewMessage 있음): danger 문구
/// - 미확인(둘 다 없음): 비어 있지만 높이는 항상 확보해 입력 중 점프를 없앤다.
struct TeamCodePreviewSlot: View {
    let preview: TeamJoinPreview?
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            if let preview {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("팀 \(preview.name) · \(preview.memberCount)명 · 주 \(preview.weeklyGoalHours)시간")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            } else if !message.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(preview != nil ? CheckTheme.working : CheckTheme.danger)
        // 결과 유무와 무관하게 슬롯 높이를 고정해 코드 입력 중 카드 높이가 튀지 않게 한다.
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }
}

// MARK: - Team code field (signup / teamless)

/// 팀 코드 입력 필드 + 미리보기 슬롯 묶음. CredentialField(대문자·ASCII) + TeamCodePreviewSlot.
/// 입력이 바뀌면 ~0.5초 디바운스 후 onDebouncedChange 로 미리보기 갱신을 요청한다(디바운스는 UI 몫).
struct TeamCodeField: View {
    @Binding var code: String
    let preview: TeamJoinPreview?
    let message: String
    /// 디바운스가 끝난 뒤 호출된다(store.previewTeamCode() 배선용).
    var onDebouncedChange: () -> Void = {}

    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CredentialField(
                title: "팀 코드",
                icon: "key.fill",
                text: $code,
                enforcesASCII: true,
                allowsSpace: false,
                uppercases: true
            )
            TeamCodePreviewSlot(preview: preview, message: message)
        }
        .onChange(of: code) { _, _ in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                onDebouncedChange()
            }
        }
        .onDisappear { debounceTask?.cancel() }
    }
}

// MARK: - Weekly goal stepper (create team)

/// 팀 만들기 폼의 주간 목표 스테퍼. 필드 톤 + 순수 SwiftUI -/+ 버튼(ImageRenderer 렌더 가능).
/// 범위 1~168시간, "N시간" 표기.
struct WeeklyGoalStepper: View {
    @Binding var hours: Int
    let range: ClosedRange<Int> = 1...168

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "target")
                .font(.system(size: 12))
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: 16)
            Text("주간 목표")
                .font(.subheadline)
                .foregroundStyle(CheckTheme.primaryText)
            Spacer(minLength: 6)
            Text("\(hours)시간")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
            HStack(spacing: 0) {
                stepButton(icon: "minus", enabled: hours > range.lowerBound) {
                    hours = max(range.lowerBound, hours - 1)
                }
                Rectangle()
                    .fill(CheckTheme.border)
                    .frame(width: 1, height: 18)
                stepButton(icon: "plus", enabled: hours < range.upperBound) {
                    hours = min(range.upperBound, hours + 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CheckTheme.border, lineWidth: 1))
            )
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CheckTheme.fieldFill)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.border, lineWidth: 1))
        )
    }

    private func stepButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? CheckTheme.primaryText : CheckTheme.secondaryText.opacity(0.4))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Created-team invite code share card

/// 팀 생성 직후 참여코드 공유 카드. 큰 모노스페이스 코드 + [복사] + 안내 + [확인].
/// 로그인/무소속 패널이 createdTeamCode 존재 시 폼 대신 이 카드를 보여 준다.
struct CreatedTeamCodeCard: View {
    let code: String
    var onConfirm: () -> Void = {}

    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CheckTheme.working)
                Text("팀이 만들어졌어요")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
            }
            Text(code)
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundStyle(CheckTheme.primaryText)
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(CheckTheme.fieldFill)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CheckTheme.border, lineWidth: 1))
                )
            Text("팀원에게 이 코드를 전달하세요")
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button {
                    CheckPasteboard.copy(code)
                    copied = true
                } label: {
                    Label(copied ? "복사됨" : "복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.border, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                AuthButton(title: "확인", icon: "checkmark.circle.fill", prominent: true, action: onConfirm)
            }
        }
    }
}

// MARK: - Owner invite code reveal (team card header)

/// 팀 카드 헤더에서 키 버튼을 눌렀을 때 인라인으로 펼쳐지는 참여코드 행.
/// 모노스페이스 코드 + [복사] 버튼. 상단 앵커 원칙상 헤더 아래로만 자란다.
struct InviteCodeInlineRow: View {
    let code: String

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CheckTheme.accent)
            Text("참여코드")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
            Text(code)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .tracking(2)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                CheckPasteboard.copy(code)
                copied = true
            } label: {
                Label(copied ? "복사됨" : "복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(CheckTheme.accent.opacity(0.16)))
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(CheckTheme.accent.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1))
        )
    }
}

// MARK: - Pasteboard helper

/// NSPasteboard 복사 래퍼. 참여코드 공유(복사 버튼)에 쓴다.
enum CheckPasteboard {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

// MARK: - Brand header (login)

struct BrandHeader: View {
    // 부제는 화면(로그인/가입)에 따라 달라진다. 기본값은 로그인 화면 문구.
    var subtitle: String = "팀 근무 타이머"

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CheckTheme.startGradient)
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("aing-check")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckTheme.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Auth mode switch link

/// 로그인 ↔ 가입 화면을 전환하는 텍스트 링크 버튼.
/// 안내 문구는 secondary, 실제 링크 단어는 accent + hover 시 밑줄/밝기로 버튼임을 드러낸다.
struct AuthLinkButton: View {
    let prompt: String
    let action: String
    let perform: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                // 안내 문구가 비어 있으면(예: "코드로 참여하기" 단독) 링크 단어만 보인다.
                if !prompt.isEmpty {
                    Text(prompt)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
                Text(action)
                    .foregroundStyle(CheckTheme.accent)
                    .underline(hovering)
                    .brightness(hovering ? 0.12 : 0)
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Footer utility bar pieces

struct SyncStatusView: View {
    let message: String

    private var isSynced: Bool {
        message == "동기화됨"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isSynced ? CheckTheme.working : CheckTheme.pending)
                .frame(width: 7, height: 7)
                .shadow(color: (isSynced ? CheckTheme.working : CheckTheme.pending).opacity(0.5), radius: 3)
            Text(message)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
        }
    }
}

struct IconButton: View {
    let icon: String
    let help: String
    var tint: Color = CheckTheme.secondaryText
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? CheckTheme.primaryText : tint)
                .frame(width: 27, height: 27)
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Shared bits

struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(CheckTheme.border)
            .frame(height: 1)
    }
}

extension View {
    func panelStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.border, lineWidth: 1)
                )
        )
    }
}
