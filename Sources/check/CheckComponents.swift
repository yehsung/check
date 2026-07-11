import SwiftUI

struct MetricRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color
    var showsProgress = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                    Spacer()
                    Text(value)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                if showsProgress {
                    Capsule()
                        .fill(tint)
                        .frame(height: 3)
                }
            }
        }
        .padding(10)
    }
}

struct TeamMemberRow: View {
    let name: String
    let status: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(status)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

struct TeamGoalGauge: View {
    let goal: TeamWeeklyGoal

    var body: some View {
        VStack(spacing: 6) {
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
                    Text("\(MenuBarStatusFormatter.hoursMinutes(goal.remainingSeconds)) 남음")
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.22))
                    Capsule()
                        .fill(CheckTheme.working)
                        .frame(width: proxy.size.width * goal.progress)
                }
            }
            .frame(height: 7)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}

struct CompactButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
}

struct CredentialField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: 14)
            ZStack(alignment: .leading) {
                Text(displayText)
                    .foregroundStyle(text.isEmpty ? CheckTheme.secondaryText : CheckTheme.primaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                field
                    .textFieldStyle(.plain)
                    .foregroundStyle(.clear)
                    .tint(CheckTheme.accent)
                    .opacity(0.001)
            }
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CheckTheme.border))
        )
    }

    private var displayText: String {
        if text.isEmpty {
            return title
        }
        if isSecure {
            return String(repeating: "•", count: max(6, min(text.count, 16)))
        }
        return text
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(title, text: $text)
        } else {
            TextField(title, text: $text)
        }
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(CheckTheme.border)
            .frame(height: 1)
            .padding(.horizontal, 8)
    }
}

extension View {
    func panelStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 7)
                .fill(CheckTheme.panel)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CheckTheme.border))
        )
    }
}
