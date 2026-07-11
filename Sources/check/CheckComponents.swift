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

// MARK: - Initial avatar

struct InitialAvatar: View {
    let name: String
    var size: CGFloat = 30

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    var body: some View {
        let color = CheckTheme.avatarColor(for: name)
        Text(initial)
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Weekly goal gauge

struct TeamGoalGauge: View {
    let goal: TeamWeeklyGoal

    private var percent: Int {
        Int((goal.progress * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Text("주간 목표")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text("\(MenuBarStatusFormatter.hoursMinutes(goal.workedSeconds)) / \(MenuBarStatusFormatter.hoursMinutes(goal.goalSeconds))")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
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

// MARK: - Team member row

struct TeamMemberRow: View {
    let name: String
    let detail: String
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 10) {
            InitialAvatar(name: name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            StatusChip(isWorking: isWorking)
        }
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
        warnsInitially: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self._text = text
        self.isSecure = isSecure
        self.enforcesASCII = enforcesASCII
        self.allowsSpace = allowsSpace
        // warnsInitially는 렌더 스냅샷 등 미리보기에서 안내가 켜진 상태를 재현하기 위한 시드값이다.
        self._showWarning = State(initialValue: warnsInitially)
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
                    field
                        .textFieldStyle(.plain)
                        .foregroundStyle(CheckTheme.primaryText)
                        .tint(CheckTheme.accent)
                        .accessibilityLabel(title)
                        .focused($isFocused)
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
            if showWarning {
                Text("영어 문자만 입력할 수 있어요")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CheckTheme.danger)
                    .lineLimit(1)
                    .transition(.opacity)
                    .accessibilityLabel("영어 문자만 입력할 수 있어요")
            }
        }
        .onChange(of: isFocused) { _, focused in
            // 포커스를 얻는 순간 영어 자판으로 전환한다. 실패는 필터가 뒤에서 잡아 준다.
            guard focused, enforcesASCII else { return }
            EnglishInputSource.activate()
        }
        .onChange(of: text) { _, newValue in
            guard enforcesASCII else { return }
            let cleaned = ASCIIInputFilter.filtered(newValue, allowsSpace: allowsSpace)
            // filtered == text면 대입을 건너뛰어 IME 조합 중간 상태에서의 무한루프를 막는다.
            guard cleaned != newValue else { return }
            text = cleaned
            triggerWarning()
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

// MARK: - Brand header (login)

struct BrandHeader: View {
    // 부제는 화면(로그인/가입)에 따라 달라진다. 기본값은 로그인 화면 문구.
    var subtitle: String = "sudo 박수 팀 근무 타이머"

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
                Text("check")
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
                Text(prompt)
                    .foregroundStyle(CheckTheme.secondaryText)
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
