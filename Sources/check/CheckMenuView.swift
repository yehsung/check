import AppKit
import SwiftUI

struct CheckMenuView: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        VStack(spacing: 10) {
            if store.isSignedIn {
                HeaderCard(store: store)
                TeamPanel(teamMembers: store.teamMembers, fallbackStatus: store.syncMessage, now: store.displayNow)
                FooterBar(store: store)
            } else {
                LoginPanel(store: store)
            }
        }
        .padding(12)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        .task {
            await store.activateStoredSession()
        }
    }
}

struct MenuBarStatusLabel: View {
    let snapshot: WorkStatusSnapshot

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                .symbolRenderingMode(.hierarchical)
                .imageScale(.medium)
            Text(MenuBarStatusFormatter.title(for: snapshot))
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
    }
}

// MARK: - Header card

private struct HeaderCard: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        HStack(spacing: 12) {
            CheckMascotView(snapshot: store.snapshot)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.snapshot.localizedStatus)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(MenuBarStatusFormatter.duration(store.snapshot.elapsedSeconds))
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .monospacedDigit()
                Text("오늘 누적 \(MenuBarStatusFormatter.hoursMinutes(store.todayDuration))")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            WorkTogglePill(
                isWorking: store.snapshot.isWorking,
                enabled: store.canSync,
                action: { store.toggle() }
            )
        }
        .padding(12)
        .panelStyle()
    }

    private var statusTint: Color {
        if store.snapshot.pendingSync {
            return CheckTheme.pending
        }
        return store.snapshot.isWorking ? CheckTheme.working : CheckTheme.offWork
    }
}

// MARK: - Team card

private struct TeamPanel: View {
    let teamMembers: [TeamMemberStatus]
    let fallbackStatus: String
    let now: Date

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(SupabaseConfig.teamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                CountChip(count: workingCount)
            }
            TeamGoalGauge(goal: weeklyGoal)
            PanelDivider()
            VStack(spacing: 12) {
                if sortedMembers.isEmpty {
                    TeamMemberRow(name: "팀원", detail: fallbackStatus, isWorking: false)
                } else {
                    ForEach(sortedMembers) { member in
                        TeamMemberRow(
                            name: member.name,
                            detail: memberDetail(member),
                            isWorking: member.status == .working
                        )
                    }
                }
            }
        }
        .padding(12)
        .panelStyle()
    }

    private var sortedMembers: [TeamMemberStatus] {
        teamMembers.sorted { lhs, rhs in
            let lhsWorking = lhs.status == .working
            let rhsWorking = rhs.status == .working
            if lhsWorking != rhsWorking {
                return lhsWorking
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var workingCount: Int {
        teamMembers.filter { $0.status == .working }.count
    }

    private var weeklyTotal: Int {
        teamMembers.reduce(0) { $0 + $1.liveWeeklyDurationSeconds(now: now) }
    }

    private var weeklyGoal: TeamWeeklyGoal {
        TeamWeeklyGoal(workedSeconds: weeklyTotal)
    }

    private func memberDetail(_ member: TeamMemberStatus) -> String {
        let weekly = "주 \(MenuBarStatusFormatter.hoursMinutes(member.liveWeeklyDurationSeconds(now: now)))"
        guard member.status == .working else {
            return weekly
        }
        return "현재 \(MenuBarStatusFormatter.duration(member.currentDurationSeconds(now: now))) · \(weekly)"
    }
}

// MARK: - Footer utility bar

private struct FooterBar: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        HStack(spacing: 8) {
            SyncStatusView(message: store.syncMessage)
            Spacer(minLength: 6)
            IconButton(icon: "arrow.clockwise", help: "새로고침") {
                store.refreshTeamStatus()
            }
            IconButton(icon: "rectangle.portrait.and.arrow.right", help: "로그아웃") {
                store.signOut()
            }
            IconButton(icon: "power", help: "앱 종료", tint: CheckTheme.danger) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelStyle()
    }
}

// MARK: - Login panel

private struct LoginPanel: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        VStack(spacing: 12) {
            BrandHeader()
            PanelDivider()
            VStack(spacing: 8) {
                CredentialField(title: "별명", icon: "person.text.rectangle.fill", text: $store.displayName)
                CredentialField(title: "이메일", icon: "envelope.fill", text: $store.email)
                CredentialField(title: "비밀번호", icon: "lock.fill", text: $store.password, isSecure: true)
            }
            HStack(spacing: 8) {
                AuthButton(title: "로그인", icon: "person.crop.circle.badge.checkmark", prominent: true) {
                    store.signIn()
                }
                AuthButton(title: "가입", icon: "person.badge.plus") {
                    store.signUp()
                }
            }
            .disabled(!store.canSync)
            if store.syncMessage != "로그인 필요" {
                AuthStatusLine(message: store.syncMessage)
            }
        }
        .padding(14)
        .panelStyle()
    }
}

private struct AuthStatusLine: View {
    let message: String

    private enum Kind {
        case progress, info, error
    }

    private var kind: Kind {
        switch message {
        case "로그인 중", "계정 생성 중":
            return .progress
        case "확인 메일 필요", "이메일 확인 필요":
            return .info
        default:
            return .error
        }
    }

    private var tint: Color {
        switch kind {
        case .progress: return CheckTheme.accent
        case .info: return CheckTheme.pending
        case .error: return CheckTheme.danger
        }
    }

    private var icon: String {
        switch kind {
        case .progress: return "arrow.triangle.2.circlepath"
        case .info: return "envelope.badge.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
        )
    }
}
