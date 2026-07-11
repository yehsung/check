import AppKit
import SwiftUI

struct CheckMenuView: View {
    @Bindable var store: WorkTimerStore
    // 렌더 스냅샷/미리보기에서 초기 인증 모드를 주입할 수 있게 열어 둔다. 앱은 기본값(로그인)으로 진입.
    var initialAuthMode: AuthMode = .signIn
    // 렌더 스냅샷에서 비밀번호 필드의 "영어만" 안내가 떠 있는 상태를 재현하기 위한 미리보기 플래그.
    var previewASCIIWarning: Bool = false
    // 렌더 스냅샷에서 12시간 확인 배너가 떠 있는 상태를 재현하기 위한 미리보기 플래그. 앱에서는 항상 false.
    var previewLongSessionBanner: Bool = false
    // 스냅샷 전용: 초과(스크롤) 리스트를 ScrollView 대신 "보이는 첫 maxVisibleRows행 클립"으로 그린다.
    // ImageRenderer는 NSScrollView(=ScrollView) 내용을 못 그리므로, 육안 확인 스냅샷에서만 켠다. 앱은 항상 false(ScrollView).
    var previewClipsOverflowList: Bool = false

    var body: some View {
        content
            .padding(12)
            // 폭만 고정(340). 높이는 상태별 콘텐츠에 맞춰 동적으로 잡는다(MenuBarExtra 창 크기 = 콘텐츠 크기).
            .frame(width: 340)
            .background(CheckTheme.background)
            .foregroundStyle(CheckTheme.primaryText)
            .task {
                await store.activateStoredSession()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isSignedIn {
            // 헤더 카드·팀 카드(헤더/게이지)·푸터는 콘텐츠 natural 높이. 팀 멤버 리스트만 팀원 수에 비례해 자라고,
            // maxVisibleRows를 넘으면 그 높이로 고정 후 스크롤한다. 팀별 현황 페이지도 같은 자리에서 동일 패턴.
            VStack(spacing: 10) {
                HeaderCard(store: store, previewLongSessionBanner: previewLongSessionBanner)
                if store.isLeaderboardVisible {
                    LeaderboardPanel(
                        entries: store.leaderboard,
                        myTeamID: store.currentTeamID,
                        fallbackStatus: store.syncMessage,
                        onBack: { store.isLeaderboardVisible = false },
                        clipsOverflowInsteadOfScroll: previewClipsOverflowList
                    )
                } else {
                    TeamPanel(
                        teamMembers: store.teamMembers,
                        teamName: store.teamName,
                        teamGoalSeconds: store.teamGoalSeconds,
                        fallbackStatus: store.syncMessage,
                        now: store.displayNow,
                        myUserID: store.session?.userID,
                        onUpdateAvatar: { store.updateAvatar(imageData: $0) },
                        onShowLeaderboard: { store.toggleLeaderboard() },
                        clipsOverflowInsteadOfScroll: previewClipsOverflowList
                    )
                }
                FooterBar(store: store)
            }
        } else {
            // 로그인/가입 카드는 콘텐츠 natural 높이로만 그린다(세로 중앙정렬용 Spacer 제거 — 창을 짧게).
            LoginPanel(store: store, initialMode: initialAuthMode, previewWarning: previewASCIIWarning)
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
    // 렌더 스냅샷 전용: 12시간 배너를 켠 채로 그린다. 앱에서는 store.isLongSessionPromptActive만 사용.
    var previewLongSessionBanner: Bool = false

    // 실제 활성화(store)든 미리보기 플래그든 하나라도 켜지면 배너를 노출한다.
    private var showsLongSessionBanner: Bool {
        store.isLongSessionPromptActive || previewLongSessionBanner
    }

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
        // 배너는 헤더 카드 위 overlay로 얹어 카드 높이를 바꾸지 않는다(창 튐 방지).
        .overlay {
            if showsLongSessionBanner {
                LongSessionBanner(onConfirm: { store.confirmStillWorking() })
            }
        }
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
    // 팀 카드 헤더 이름. 로그인 후 store.teamName(미확정 시 "팀")을 그대로 표시한다.
    let teamName: String
    // 팀 주간 목표시간(초). 출처는 teams.weekly_goal_hours(store.teamGoalSeconds). 게이지 분모로만 쓴다.
    let teamGoalSeconds: Int
    let fallbackStatus: String
    let now: Date
    // 내 행 판정용. store.session?.userID == member.id 인 행에만 아바타 편집을 붙인다.
    var myUserID: String? = nil
    // 내 행 아바타 교체 시 다운스케일된 JPEG Data를 store.updateAvatar로 넘기는 콜백.
    var onUpdateAvatar: ((Data) -> Void)? = nil
    // 진입 버튼 액션. 팀별 현황 페이지를 연다.
    var onShowLeaderboard: (() -> Void)? = nil
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(teamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                CountChip(count: activeWorkingCount)
                if let onShowLeaderboard {
                    IconButton(icon: "chart.bar.xaxis", help: "팀별 현황", action: onShowLeaderboard)
                }
            }
            TeamGoalGauge(goal: weeklyGoal)
            PanelDivider()
            memberList
        }
        .padding(12)
        // 팀 카드 높이는 콘텐츠(멤버 리스트 포함)에 맞춘다 — 남는 공간 채우기(maxHeight:.infinity) 없음.
        .panelStyle()
    }

    // 행 사이 간격. 리스트 총 높이(팀원 수 비례) 계산에도 쓴다.
    private static let rowSpacing: CGFloat = 10
    // 스크롤 없이 그대로 보여 주는 최대 행 수. 이 수까지는 팀원 수에 비례해 자라고, 초과하면 이 높이로 고정 후 스크롤.
    static let maxVisibleRows = 7

    // 표시할 행 개수(빈 팀은 안내용 1행).
    private var rowCount: Int {
        sortedMembers.isEmpty ? 1 : sortedMembers.count
    }

    // 멤버 리스트 높이 = 팀원 수 비례. maxVisibleRows까지는 rowHeight*count 그대로 자라고(스크롤 없음),
    // 초과하면 maxVisibleRows 높이로 고정하고 ScrollView로 스크롤한다(창 높이 상한).
    @ViewBuilder
    private var memberList: some View {
        let capHeight = Self.listContentHeight(rowCount: Self.maxVisibleRows)
        if rowCount <= Self.maxVisibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 maxVisibleRows행만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
            rows.frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                rows.frame(maxWidth: .infinity)
            }
            .frame(height: capHeight)
        }
    }

    // 각 행은 memberRowHeight 상수로 고정 — 보조줄("마지막 확인 N분 전") 유무와 무관하게 동일 높이.
    @ViewBuilder
    private var rows: some View {
        VStack(spacing: Self.rowSpacing) {
            if sortedMembers.isEmpty {
                TeamMemberRow(name: "팀원", presence: .offWork, primaryDetail: fallbackStatus)
                    .frame(height: CheckTheme.memberRowHeight)
            } else {
                ForEach(sortedMembers) { member in
                    let isMe = myUserID != nil && member.id == myUserID
                    TeamMemberRow(
                        name: member.name,
                        avatarURL: member.avatarURL,
                        presence: member.presence(now: now),
                        primaryDetail: primaryDetail(member),
                        secondaryDetail: secondaryDetail(member),
                        isMe: isMe,
                        onPickAvatar: isMe ? onUpdateAvatar : nil
                    )
                    .frame(height: CheckTheme.memberRowHeight)
                }
            }
        }
    }

    // 고정 행 높이·간격으로 계산한 리스트 총 높이(팀원 수 비례). 스크롤 상한(maxVisibleRows) 높이 산정에도 쓴다.
    static func listContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * CheckTheme.memberRowHeight + CGFloat(rowCount - 1) * rowSpacing
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

    // 헤더 "N명 근무중" 카운트는 라이브 근무(activeWorking)만 집계한다. 연결 끊김은 제외.
    private var activeWorkingCount: Int {
        teamMembers.filter { $0.presence(now: now) == .activeWorking }.count
    }

    private var weeklyTotal: Int {
        teamMembers.reduce(0) { $0 + displayWeeklySeconds($1) }
    }

    // 목표시간은 store.teamGoalSeconds(= teams.weekly_goal_hours)로만 결정된다. 앱엔 목표 입력 UI가 없다.
    private var weeklyGoal: TeamWeeklyGoal {
        TeamWeeklyGoal(workedSeconds: weeklyTotal, goalSeconds: teamGoalSeconds)
    }

    // 상태별 표시용 현재 세션 시간. active는 라이브 틱, stale은 마지막 신호에서 동결, off는 0.
    private func displayCurrentSeconds(_ member: TeamMemberStatus) -> Int {
        switch member.presence(now: now) {
        case .activeWorking:
            return member.currentDurationSeconds(now: now)
        case .staleWorking(let frozen):
            return frozen
        case .offWork:
            return 0
        }
    }

    // 상태별 표시용 주간 누적. stale은 마지막 신호에서 동결된 현재 세션분까지만 더한다.
    private func displayWeeklySeconds(_ member: TeamMemberStatus) -> Int {
        switch member.presence(now: now) {
        case .staleWorking(let frozen):
            return member.weeklyDurationSeconds + frozen
        default:
            return member.liveWeeklyDurationSeconds(now: now)
        }
    }

    private func primaryDetail(_ member: TeamMemberStatus) -> String {
        let weekly = "주 \(MenuBarStatusFormatter.hoursMinutes(displayWeeklySeconds(member)))"
        switch member.presence(now: now) {
        case .offWork:
            return weekly
        case .activeWorking, .staleWorking:
            return "현재 \(MenuBarStatusFormatter.duration(displayCurrentSeconds(member))) · \(weekly)"
        }
    }

    // stale 상태에만 "마지막 확인 N분 전" 보조줄을 붙인다. 그 외엔 nil.
    private func secondaryDetail(_ member: TeamMemberStatus) -> String? {
        guard case .staleWorking = member.presence(now: now),
              let seen = member.lastSeenAt else {
            return nil
        }
        let minutes = max(1, Int(now.timeIntervalSince(seen) / 60))
        return "마지막 확인 \(minutes)분 전"
    }
}

// MARK: - Team league page

/// 팀 카드 자리를 대체하는 팀별 현황 페이지. 헤더/푸터는 CheckMenuView 가 유지하고, 이 카드만 교체된다.
/// 제목 + 뒤로 버튼 + 총시간 내림차순 팀 목록(우리 팀 칩). 팀이 많으면 memberList 패턴으로 스크롤.
private struct LeaderboardPanel: View {
    // 총시간 내림차순으로 정렬된 팀 목록(store 에서 이미 정렬됨). 서버 정렬을 신뢰하지 않고 뷰에서도 다시 정렬한다.
    let entries: [TeamLeaderboardEntry]
    // 우리 팀 id(칩 표시 판정용). 무소속이면 nil 이라 어떤 행에도 칩이 붙지 않는다.
    var myTeamID: String? = nil
    // 아직 로드 전/실패 시 빈 목록 자리에 표시할 안내 문구.
    let fallbackStatus: String
    var onBack: () -> Void = {}
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 팀 행 고정 높이·간격. 팀원 행보다 높다(아바타 + 이름/시간 + 게이지 + 캡션 3단).
    private static let rowHeight: CGFloat = 58
    private static let rowSpacing: CGFloat = 10
    // 스크롤 없이 그대로 보여 주는 최대 팀 수. 행이 팀원 행보다 높아 창 높이 상한(≤700pt)을 지키도록 6으로 둔다.
    static let maxVisibleRows = 6

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("팀별 이번 주")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            PanelDivider()
            entryList
        }
        .padding(12)
        .panelStyle()
    }

    private var sortedEntries: [TeamLeaderboardEntry] {
        entries.sorted { $0.totalSeconds > $1.totalSeconds }
    }

    private var rowCount: Int {
        sortedEntries.isEmpty ? 1 : sortedEntries.count
    }

    // 리스트 높이 = 팀 수 비례. maxVisibleRows까지는 그대로 자라고(스크롤 없음), 초과하면 그 높이로 고정 후 스크롤.
    @ViewBuilder
    private var entryList: some View {
        let capHeight = Self.listContentHeight(rowCount: Self.maxVisibleRows)
        if rowCount <= Self.maxVisibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 maxVisibleRows행만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
            rows.frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                rows.frame(maxWidth: .infinity)
            }
            .frame(height: capHeight)
        }
    }

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: Self.rowSpacing) {
            if sortedEntries.isEmpty {
                Text(fallbackStatus)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                ForEach(sortedEntries, id: \.id) { entry in
                    LeaderboardRow(entry: entry, isMyTeam: entry.id == myTeamID)
                        .frame(height: Self.rowHeight)
                }
            }
        }
    }

    static func listContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }
}

// MARK: - Footer utility bar

private struct FooterBar: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        HStack(spacing: 8) {
            SyncStatusView(message: store.syncMessage)
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                Text("캐릭터")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                Toggle("캐릭터 표시", isOn: Binding(
                    get: { store.isOverlayEnabled },
                    set: { store.setOverlayEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(CheckTheme.working)
                .help("근무중일 때 화면 우상단 캐릭터 표시")
            }
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
                // 팀 선택은 가입 모드에만 노출한다. 창이 고정 높이라 모드 간 카드 높이 차이는 튐을 만들지 않는다.
                if mode == .signUp {
                    TeamPickerField(
                        teams: store.teamDirectory,
                        selectedTeamID: Binding(
                            get: { store.selectedSignupTeamID },
                            set: { store.selectedSignupTeamID = $0 }
                        )
                    )
                }
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
        .onAppear {
            // 가입 모드로 진입한 상태면 팀 목록을 로드한다(모드 전환 경로는 switchMode 에서 처리).
            if mode == .signUp {
                store.loadTeamDirectory()
            }
        }
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
        // 가입 모드로 전환하는 순간 팀 목록을 로드한다(진입 경로는 onAppear 에서 처리).
        if newMode == .signUp {
            store.loadTeamDirectory()
        }
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
