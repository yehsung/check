import SwiftUI

struct CheckMenuView: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        VStack(spacing: 8) {
            if store.isSignedIn {
                ProfileSummaryRow(store: store)
                TeamPanel(teamMembers: store.teamMembers, fallbackStatus: store.syncMessage, now: store.displayNow)
            } else {
                LoginPanel(store: store)
            }
        }
        .padding(8)
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
        HStack(spacing: 4) {
            Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                .symbolRenderingMode(.hierarchical)
            Text(MenuBarStatusFormatter.title(for: snapshot))
                .monospacedDigit()
        }
    }
}

private struct ProfileSummaryRow: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        HStack(spacing: 10) {
            CheckMascotView(snapshot: store.snapshot)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 7, height: 7)
                    Text(store.snapshot.localizedStatus)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                }
                Text(profileDetail)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: { store.toggle() }) {
                Label(buttonTitle, systemImage: store.snapshot.isWorking ? "stop.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(store.snapshot.isWorking ? CheckTheme.pending : CheckTheme.working)
                            .shadow(color: statusTint.opacity(0.25), radius: 8, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!store.canSync)
        }
        .padding(10)
        .panelStyle()
    }

    private var buttonTitle: String {
        store.snapshot.isWorking ? "근무 종료" : "근무 시작"
    }

    private var profileDetail: String {
        if store.syncMessage != "동기화됨", store.syncMessage != "로그인 필요" {
            return store.syncMessage
        }
        let elapsed = MenuBarStatusFormatter.duration(store.snapshot.elapsedSeconds)
        let today = MenuBarStatusFormatter.duration(store.todayDuration)
        return "현재 \(elapsed) · 오늘 \(today)"
    }

    private var statusTint: Color {
        if store.snapshot.pendingSync {
            return CheckTheme.pending
        }
        return store.snapshot.isWorking ? CheckTheme.working : CheckTheme.offWork
    }
}

private struct TeamPanel: View {
    let teamMembers: [TeamMemberStatus]
    let fallbackStatus: String
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            MetricRow(
                icon: "person.2.wave.2.fill",
                title: "팀",
                value: SupabaseConfig.teamName,
                detail: "\(workingCount)명 근무중 · 60시간 목표",
                tint: CheckTheme.working
            )
            TeamGoalGauge(goal: weeklyGoal)
            PanelDivider()
            VStack(spacing: 6) {
                if teamMembers.isEmpty {
                    TeamMemberRow(name: "팀원", status: fallbackStatus, detail: "스키마 적용 후 표시", tint: CheckTheme.pending)
                } else {
                    ForEach(teamMembers) { member in
                        TeamMemberRow(
                            name: member.name,
                            status: member.status.localizedStatus,
                            detail: memberDetail(member),
                            tint: member.status == .working ? CheckTheme.working : CheckTheme.offWork
                        )
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .panelStyle()
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
        return "현재 \(MenuBarStatusFormatter.hoursMinutes(member.currentDurationSeconds(now: now))) · \(weekly)"
    }
}

private struct LoginPanel: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        VStack(spacing: 7) {
            CredentialField(title: "별명", icon: "person.text.rectangle.fill", text: $store.displayName)
            CredentialField(title: "이메일", icon: "envelope.fill", text: $store.email)
            CredentialField(title: "비밀번호", icon: "lock.fill", text: $store.password, isSecure: true)
            HStack(spacing: 6) {
                CompactButton(title: "로그인", icon: "person.crop.circle.badge.checkmark") {
                    store.signIn()
                }
                CompactButton(title: "가입", icon: "person.badge.plus") {
                    store.signUp()
                }
            }
            .disabled(!store.canSync)
        }
        .padding(10)
        .panelStyle()
    }
}
