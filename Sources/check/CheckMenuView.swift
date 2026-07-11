import AppKit
import SwiftUI

struct CheckMenuView: View {
    @Bindable var store: WorkTimerStore
    // 렌더 스냅샷/미리보기에서 초기 인증 모드를 주입할 수 있게 열어 둔다. 앱은 기본값(로그인)으로 진입.
    var initialAuthMode: AuthMode = .signIn
    // 렌더 스냅샷에서 비밀번호 필드의 "영어만" 안내가 떠 있는 상태를 재현하기 위한 미리보기 플래그.
    var previewASCIIWarning: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            if store.isSignedIn {
                HeaderCard(store: store)
                TeamPanel(teamMembers: store.teamMembers, fallbackStatus: store.syncMessage, now: store.displayNow)
                FooterBar(store: store)
            } else {
                LoginPanel(store: store, initialMode: initialAuthMode, previewWarning: previewASCIIWarning)
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
            if let mascot = CheckMascotAssets.menuBarImage(for: snapshot) {
                // 이미 18×18pt로 크기를 지정한 이미지라 .resizable()/.frame() 불필요.
                // MenuBarExtra 라벨이 intrinsic size를 써도 바 높이 안에 온전히 들어간다.
                Image(nsImage: mascot)
            } else {
                Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)
            }
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

/// 로그인/가입을 오가는 뷰 로컬 UI 상태. store가 아니라 뷰에서만 관리한다.
enum AuthMode {
    case signIn
    case signUp
}

/// 로그인/가입 패널의 Enter-키 포커스 체이닝 대상 필드.
enum AuthFocusField: Hashable {
    case displayName
    case email
    case password

    /// 이 필드에서 Enter를 눌렀을 때 옮겨 갈 다음 포커스 필드. nil이면 마지막 필드이므로 제출한다.
    /// 로그인 모드엔 별명 필드가 없으므로 로그인 모드의 displayName은 제출로 취급한다.
    func nextField(mode: AuthMode) -> AuthFocusField? {
        switch (mode, self) {
        case (.signUp, .displayName):
            return .email
        case (_, .email):
            return .password
        case (.signIn, .displayName), (_, .password):
            return nil
        }
    }
}

/// syncMessage 배너의 성격 분류. AuthStatusLine 색/아이콘과 모드 전환 시 오류 리셋 판정에 공유한다.
enum AuthMessageKind {
    case progress, info, error

    init(_ message: String) {
        switch message {
        case "로그인 중", "계정 생성 중":
            self = .progress
        case "확인 메일 필요", "이메일 확인 필요":
            self = .info
        default:
            self = .error
        }
    }
}

private struct LoginPanel: View {
    @Bindable var store: WorkTimerStore
    @State private var mode: AuthMode
    // 렌더 스냅샷 전용: 비밀번호 필드의 안내 캡션을 켠 채로 그린다. 앱에서는 항상 false.
    private let previewWarning: Bool
    @FocusState private var focus: AuthFocusField?

    init(store: WorkTimerStore, initialMode: AuthMode = .signIn, previewWarning: Bool = false) {
        self.store = store
        _mode = State(initialValue: initialMode)
        self.previewWarning = previewWarning
    }

    var body: some View {
        VStack(spacing: 12) {
            BrandHeader(subtitle: mode == .signUp ? "sudo 박수 팀에 합류" : "sudo 박수 팀 근무 타이머")
            PanelDivider()
            VStack(spacing: 8) {
                // 별명 필드는 두 모드에서 항상 자리를 차지하고 로그인 모드에선 opacity/hit-test만 꺼 둔다.
                // 조건부 삽입/삭제로 인한 카드 높이 변화(모드 전환 시 창 튐)를 없애기 위함이다.
                CredentialField(
                    title: "별명",
                    icon: "person.text.rectangle.fill",
                    text: $store.displayName,
                    focus: $focus,
                    fieldIdentifier: .displayName,
                    submitLabel: .next,
                    onSubmit: { advance(from: .displayName) }
                )
                .opacity(mode == .signUp ? 1 : 0)
                .disabled(mode != .signUp)
                .allowsHitTesting(mode == .signUp)
                .accessibilityHidden(mode != .signUp)
                CredentialField(
                    title: "이메일",
                    icon: "envelope.fill",
                    text: $store.email,
                    enforcesASCII: true,
                    allowsSpace: false,
                    focus: $focus,
                    fieldIdentifier: .email,
                    submitLabel: .next,
                    onSubmit: { advance(from: .email) }
                )
                CredentialField(
                    title: "비밀번호",
                    icon: "lock.fill",
                    text: $store.password,
                    isSecure: true,
                    enforcesASCII: true,
                    warnsInitially: previewWarning,
                    focus: $focus,
                    fieldIdentifier: .password,
                    submitLabel: .go,
                    onSubmit: { advance(from: .password) }
                )
            }
            primaryButton
                .disabled(!store.canSync)
            // 상태 배너 슬롯은 항상 확보하고 메시지 유무는 opacity로만 토글한다 — 오류 배너 등장 시 창 튐 제거.
            AuthStatusLine(message: store.syncMessage)
                .opacity(store.syncMessage == "로그인 필요" ? 0 : 1)
                .accessibilityHidden(store.syncMessage == "로그인 필요")
            switchLink
        }
        .padding(14)
        .panelStyle()
        .animation(.easeInOut(duration: 0.22), value: mode)
    }

    // 필드에서 Enter를 눌렀을 때: 다음 필드가 있으면 포커스를 옮기고, 없으면(마지막 필드) 제출한다.
    private func advance(from field: AuthFocusField) {
        if let next = field.nextField(mode: mode) {
            focus = next
        } else {
            submitPrimary()
        }
    }

    // Enter(제출) 시 로그인/가입 버튼과 동일하게 동작한다. canSync 가드로 키 없음 상태에선 무시한다.
    private func submitPrimary() {
        guard store.canSync else { return }
        switch mode {
        case .signIn:
            store.signIn()
        case .signUp:
            store.signUp()
        }
    }

    // 하나의 prominent 전체폭 버튼만 노출한다. 모드에 따라 로그인/가입으로 바뀐다.
    @ViewBuilder
    private var primaryButton: some View {
        switch mode {
        case .signIn:
            AuthButton(title: "로그인", icon: "person.crop.circle.badge.checkmark", prominent: true) {
                store.signIn()
            }
        case .signUp:
            AuthButton(title: "가입", icon: "person.badge.plus", prominent: true) {
                store.signUp()
            }
        }
    }

    @ViewBuilder
    private var switchLink: some View {
        switch mode {
        case .signIn:
            AuthLinkButton(prompt: "계정이 없나요?", action: "가입하기") {
                switchMode(to: .signUp)
            }
        case .signUp:
            AuthLinkButton(prompt: "이미 계정이 있나요?", action: "로그인") {
                switchMode(to: .signIn)
            }
        }
    }

    // 입력값(별명/이메일/비밀번호)은 유지하되, 이전 모드의 오류 배너가 새 모드에서 혼동을 주지 않도록 리셋한다.
    private func switchMode(to newMode: AuthMode) {
        if AuthMessageKind(store.syncMessage) == .error {
            store.syncMessage = "로그인 필요"
        }
        mode = newMode
    }
}

private struct AuthStatusLine: View {
    let message: String

    private var kind: AuthMessageKind { AuthMessageKind(message) }

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
