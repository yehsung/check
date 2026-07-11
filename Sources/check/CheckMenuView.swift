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
    // 스냅샷 전용: owner 팀 카드에서 참여코드 인라인 행이 펼쳐진 상태를 강제로 그린다. 앱에서는 항상 false(키 버튼 토글).
    var previewOwnerCodeRevealed: Bool = false

    var body: some View {
        content
            .padding(12)
            // 폭만 고정(340). 높이는 상태별 콘텐츠에 맞춰 동적으로 잡는다(MenuBarExtra 창 크기 = 콘텐츠 크기).
            .frame(width: 340)
            .background(CheckTheme.background)
            .foregroundStyle(CheckTheme.primaryText)
            // 팝오버 표시/숨김을 스토어에 알려 티커/폴링 게이팅을 켠다(창 노티 콜백과 수렴 — 멱등이라 중복 무해).
            .onAppear { store.setMenuPresented(true) }
            .onDisappear { store.setMenuPresented(false) }
            .task {
                await store.activateStoredSession()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isSignedIn {
            if store.isTeamless {
                // 로그인은 됐지만 소속 팀이 없다 — 메인 대신 팀 코드 입력/새 팀 만들기 패널을 보여 준다.
                VStack(spacing: 10) {
                    TeamlessPanel(store: store)
                    FooterBar(store: store)
                }
            } else {
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
                        // store 를 통째로 내려보내 초단위(displayNow) 의존을 잎 뷰로 격리한다 — TeamPanel 본체는
                        // displayNow 를 읽지 않으므로 매초 재정렬/재계산이 사라진다.
                        TeamPanel(
                            store: store,
                            previewCodeRevealed: previewOwnerCodeRevealed,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    }
                    FooterBar(store: store)
                }
            }
        } else {
            // 로그인/가입 카드는 콘텐츠 natural 높이로만 그린다(세로 중앙정렬용 Spacer 제거 — 창을 짧게).
            LoginPanel(store: store, initialMode: initialAuthMode, previewWarning: previewASCIIWarning)
        }
    }
}

struct MenuBarStatusLabel: View {
    // 아이콘 판정용 스냅샷(상태/대기). 텍스트는 스토어가 계산해 둔 파생 저장값(menuBarTitle)을 그대로 쓴다.
    let snapshot: WorkStatusSnapshot
    // 상단바에 표시할 라벨 텍스트. 스토어가 == 가드와 함께 갱신하므로 여기선 그리기만 한다(매초 재계산 없음).
    let title: String

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
            Text(title)
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
                // 큰 타이머·이번 주 줄은 매초 displayNow 에 의존하므로 잎 뷰로 격리한다 — 헤더 카드 본체가
                // 매초 무효화되지 않게(무효화 반경을 이 두 텍스트로 한정).
                TodayTimerText(store: store)
                MyWeeklyLine(store: store)
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

// MARK: - Header live leaves (초단위 격리)

/// 큰 타이머(오늘 누적). store.todayDuration(=displayNow 파생)만 읽어 매초 이 텍스트만 무효화된다.
private struct TodayTimerText: View {
    let store: WorkTimerStore

    var body: some View {
        // 큰 타이머 = 오늘 누적. 쉬었다 재개해도 0이 아니라 오늘 총합에서 이어 흐른다.
        Text(MenuBarStatusFormatter.duration(store.todayDuration))
            .font(.system(.title2, design: .monospaced).weight(.semibold))
            .foregroundStyle(CheckTheme.primaryText)
            .monospacedDigit()
    }
}

/// 헤더 보조줄(내 이번 주 누적). store.myLiveWeeklySeconds(=displayNow 파생)만 읽어 이 줄만 무효화된다.
private struct MyWeeklyLine: View {
    let store: WorkTimerStore

    var body: some View {
        // 내 이번 주 누적. 목표(1인당)의 서술은 아래 게이지의 "/ 각자 N시간" 이 맡는다.
        Text("이번 주 \(MenuBarStatusFormatter.hoursMinutes(store.myLiveWeeklySeconds))")
            .font(.caption2)
            .foregroundStyle(CheckTheme.secondaryText)
            .lineLimit(1)
    }
}

// MARK: - Team card

private struct TeamPanel: View {
    // store 를 통째로 받아 대부분의 값을 파생 읽기한다. 초단위(displayNow) 의존은 잎 뷰로 격리하므로
    // 본체는 displayNow 를 읽지 않는다 — 매초 재정렬/재계산이 사라진다.
    let store: WorkTimerStore
    // 스냅샷 전용: 참여코드 인라인 행이 펼쳐진 상태로 그린다(키 버튼 클릭을 대신). 앱은 false.
    var previewCodeRevealed: Bool = false
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    // 렌더 결정성용 시각 주입. nil 이면 잎 뷰가 store.displayNow 를 읽는다.
    var nowOverride: Date? = nil

    // 키 버튼으로 토글하는 참여코드 인라인 노출 상태. 스냅샷은 previewCodeRevealed 로 시드된다.
    @State private var showsInviteCode: Bool

    init(
        store: WorkTimerStore,
        previewCodeRevealed: Bool = false,
        clipsOverflowInsteadOfScroll: Bool = false,
        nowOverride: Date? = nil
    ) {
        self.store = store
        self.previewCodeRevealed = previewCodeRevealed
        self.clipsOverflowInsteadOfScroll = clipsOverflowInsteadOfScroll
        self.nowOverride = nowOverride
        _showsInviteCode = State(initialValue: previewCodeRevealed)
    }

    // owner + 코드 보유 시에만 키 버튼/인라인 행을 노출한다.
    private var canRevealCode: Bool {
        store.isTeamOwner && store.myTeamInviteCode != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(store.teamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // "N명 근무중" 카운트는 presence(now:) 파생이라 잎 뷰로 격리(본체가 매초 무효화되지 않게).
                TeamWorkingCountChip(store: store, nowOverride: nowOverride)
                if canRevealCode {
                    IconButton(
                        icon: showsInviteCode ? "key.fill" : "key",
                        help: showsInviteCode ? "참여코드 숨기기" : "참여코드 보기",
                        tint: showsInviteCode ? CheckTheme.accent : CheckTheme.secondaryText
                    ) {
                        showsInviteCode.toggle()
                    }
                }
                IconButton(icon: "chart.bar.xaxis", help: "팀별 현황") { store.toggleLeaderboard() }
            }
            // 참여코드 인라인 행은 헤더 아래에만 나타나 상단 앵커 원칙(아래로만 성장)을 지킨다.
            if canRevealCode, showsInviteCode, let inviteCode = store.myTeamInviteCode {
                InviteCodeInlineRow(code: inviteCode)
            }
            // 내 진행률 게이지 — 분자엔 "내"(나 한 사람의 주간 누적), 분모엔 "각자"(1인당 목표)를 붙여
            // 팀 총합이 아니라 각자의 주간 약속 대비 내 진행률임을 드러낸다. myLiveWeeklySeconds 는 displayNow
            // 파생이라 잎 뷰(MyWeeklyGauge)가 읽는다.
            MyWeeklyGauge(store: store, teamGoalSeconds: store.teamGoalSeconds)
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
    // 행 내부의 시간/프레즌스는 displayNow 파생이라 TeamMemberLiveRow 잎 뷰가 읽는다(본체는 정렬만 담당).
    @ViewBuilder
    private var rows: some View {
        let myUserID = store.session?.userID
        VStack(spacing: Self.rowSpacing) {
            if sortedMembers.isEmpty {
                TeamMemberRow(name: "팀원", presence: .offWork, primaryDetail: store.syncMessage)
                    .frame(height: CheckTheme.memberRowHeight)
            } else {
                ForEach(sortedMembers) { member in
                    let isMe = myUserID != nil && member.id == myUserID
                    TeamMemberLiveRow(
                        store: store,
                        member: member,
                        teamGoalSeconds: store.teamGoalSeconds,
                        isMe: isMe,
                        onPickAvatar: isMe ? { store.updateAvatar(imageData: $0) } : nil,
                        nowOverride: nowOverride
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
        store.teamMembers.sorted { lhs, rhs in
            let lhsWorking = lhs.status == .working
            let rhsWorking = rhs.status == .working
            if lhsWorking != rhsWorking {
                return lhsWorking
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

// MARK: - Team card live leaves (초단위 격리)

/// "N명 근무중" 카운트 칩. presence(now:) 파생이라 잎 뷰로 분리해 이 칩만 매초 무효화되게 한다.
private struct TeamWorkingCountChip: View {
    let store: WorkTimerStore
    var nowOverride: Date? = nil

    var body: some View {
        let now = nowOverride ?? store.displayNow
        // 라이브 근무(activeWorking)만 집계한다. 연결 끊김은 제외.
        CountChip(count: store.teamMembers.filter { $0.presence(now: now) == .activeWorking }.count)
    }
}

/// 내 주간 진행률 게이지. myLiveWeeklySeconds(=displayNow 파생)만 읽어 게이지만 무효화되게 한다.
private struct MyWeeklyGauge: View {
    let store: WorkTimerStore
    // 1인당 주간 목표시간(초). teams.weekly_goal_hours(store.teamGoalSeconds) — 팀 총합이 아니라 "각자 X시간".
    let teamGoalSeconds: Int

    var body: some View {
        TeamGoalGauge(
            goal: TeamWeeklyGoal(workedSeconds: store.myLiveWeeklySeconds, goalSeconds: teamGoalSeconds),
            workedLabelPrefix: "내 ",
            goalLabelPrefix: "각자 "
        )
    }
}

/// 팀원 한 행의 라이브 래퍼. store.displayNow(또는 nowOverride)를 읽어 시간/프레즌스를 계산하고
/// TeamMemberRow 에 값으로 넘긴다 — presence(now:)를 행당 1회만 계산해 하위 파생에 재사용한다.
private struct TeamMemberLiveRow: View {
    let store: WorkTimerStore
    let member: TeamMemberStatus
    let teamGoalSeconds: Int
    let isMe: Bool
    var onPickAvatar: ((Data) -> Void)? = nil
    var nowOverride: Date? = nil

    var body: some View {
        let now = nowOverride ?? store.displayNow
        let presence = member.presence(now: now)
        TeamMemberRow(
            name: member.name,
            avatarURL: member.avatarURL,
            presence: presence,
            primaryDetail: Self.primaryDetail(member, presence: presence, now: now),
            secondaryDetail: Self.secondaryDetail(member, presence: presence, now: now),
            meetsWeeklyGoal: member.hasMetWeeklyGoal(goalSeconds: teamGoalSeconds, now: now),
            isMe: isMe,
            onPickAvatar: isMe ? onPickAvatar : nil
        )
    }

    // 상태별 표시용 현재 세션 시간. active는 라이브 틱, stale은 마지막 신호에서 동결, off는 0.
    private static func displayCurrentSeconds(_ member: TeamMemberStatus, presence: MemberPresence, now: Date) -> Int {
        switch presence {
        case .activeWorking:
            return member.currentDurationSeconds(now: now)
        case .staleWorking(let frozen):
            return frozen
        case .offWork:
            return 0
        }
    }

    // 상태별 표시용 주간 누적. stale은 마지막 신호에서 동결된 현재 세션분까지만 더한다.
    private static func displayWeeklySeconds(_ member: TeamMemberStatus, presence: MemberPresence, now: Date) -> Int {
        switch presence {
        case .staleWorking(let frozen):
            return member.weeklyDurationSeconds + frozen
        default:
            return member.liveWeeklyDurationSeconds(now: now)
        }
    }

    private static func primaryDetail(_ member: TeamMemberStatus, presence: MemberPresence, now: Date) -> String {
        let weekly = "주 \(MenuBarStatusFormatter.hoursMinutes(displayWeeklySeconds(member, presence: presence, now: now)))"
        switch presence {
        case .offWork:
            return weekly
        case .activeWorking, .staleWorking:
            return "현재 \(MenuBarStatusFormatter.duration(displayCurrentSeconds(member, presence: presence, now: now))) · \(weekly)"
        }
    }

    // stale 상태에만 "마지막 확인 N분 전" 보조줄을 붙인다. 그 외엔 nil.
    private static func secondaryDetail(_ member: TeamMemberStatus, presence: MemberPresence, now: Date) -> String? {
        guard case .staleWorking = presence, let seen = member.lastSeenAt else {
            return nil
        }
        let minutes = max(1, Int(now.timeIntervalSince(seen) / 60))
        return "마지막 확인 \(minutes)분 전"
    }
}

// MARK: - Team league page

/// 팀 카드 자리를 대체하는 팀별 현황 페이지. 헤더/푸터는 CheckMenuView 가 유지하고, 이 카드만 교체된다.
/// 제목 + 뒤로 버튼 + 1인당 평균 내림차순 팀 목록(우리 팀 칩). 팀이 많으면 memberList 패턴으로 스크롤.
private struct LeaderboardPanel: View {
    // 1인당 평균 내림차순으로 정렬된 팀 목록(store 에서 이미 정렬됨). 서버 정렬을 신뢰하지 않고 뷰에서도 다시 정렬한다.
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
        entries.sortedByAverageDescending()
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
            IconButton(
                icon: store.isOverlayEnabled ? "person.fill" : "person.fill.xmark",
                help: store.isOverlayEnabled ? "캐릭터 표시 중 — 누르면 숨김" : "캐릭터 숨김 — 누르면 표시"
            ) {
                store.toggleOverlayEnabled()
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

    // 가입(create 모드)에 성공하면 참여코드 공유 카드로 화면을 대체한다.
    private var showsCreatedCode: Bool {
        mode == .signUp && store.createdTeamCode != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsCreatedCode, let code = store.createdTeamCode {
                BrandHeader(subtitle: "팀 생성 완료")
                PanelDivider()
                CreatedTeamCodeCard(code: code) { store.dismissCreatedTeamCode() }
            } else {
                BrandHeader(subtitle: subtitle)
                PanelDivider()
                credentialFields
                primaryButton
                    .disabled(!store.canSync)
                // 상태 배너 슬롯은 항상 확보하고 메시지 유무는 opacity로만 토글한다 — 오류 배너 등장 시 창 튐 제거.
                AuthStatusLine(message: store.syncMessage)
                    .opacity(store.syncMessage == "로그인 필요" ? 0 : 1)
                    .accessibilityHidden(store.syncMessage == "로그인 필요")
                links
            }
        }
        .padding(14)
        .panelStyle()
        .animation(.easeInOut(duration: 0.22), value: mode)
        .animation(.easeInOut(duration: 0.22), value: store.isCreateTeamMode)
    }

    private var subtitle: String {
        switch mode {
        case .signIn:
            return "sudo 박수 팀 근무 타이머"
        case .signUp:
            return store.isCreateTeamMode ? "새 팀을 만들어요" : "팀 코드로 합류해요"
        }
    }

    // 별명(가입만) / 이메일 / 비밀번호 + 가입 모드의 팀 코드 또는 팀 만들기 폼.
    @ViewBuilder
    private var credentialFields: some View {
        VStack(spacing: 8) {
            if mode == .signUp {
                CredentialField(
                    title: "별명",
                    icon: "person.text.rectangle.fill",
                    text: $store.displayName,
                    focus: $focus,
                    fieldIdentifier: .displayName,
                    submitLabel: .next,
                    onSubmit: { advance(from: .displayName) }
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
            if mode == .signUp {
                if store.isCreateTeamMode {
                    // 팀 이름은 한글 허용(ASCII 강제 없음). 주간 목표는 스테퍼(1~168시간).
                    CredentialField(
                        title: "팀 이름",
                        icon: "person.3.fill",
                        text: $store.createTeamName
                    )
                    WeeklyGoalStepper(hours: $store.createTeamGoalHours)
                } else {
                    TeamCodeField(
                        code: $store.signupTeamCode,
                        preview: store.joinPreview,
                        message: store.joinPreviewMessage,
                        onDebouncedChange: { store.previewTeamCode() }
                    )
                }
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

    // 하나의 prominent 전체폭 버튼만 노출한다. 모드/서브모드에 따라 로그인/가입/팀 만들기로 바뀐다.
    @ViewBuilder
    private var primaryButton: some View {
        switch mode {
        case .signIn:
            AuthButton(title: "로그인", icon: "person.crop.circle.badge.checkmark", prominent: true) {
                store.signIn()
            }
        case .signUp:
            if store.isCreateTeamMode {
                AuthButton(title: "팀 만들고 시작하기", icon: "flag.fill", prominent: true) {
                    store.signUp()
                }
            } else {
                AuthButton(title: "가입", icon: "person.badge.plus", prominent: true) {
                    store.signUp()
                }
            }
        }
    }

    // 가입 모드엔 두 개의 링크: (1) 코드↔팀 만들기 전환, (2) 로그인 복귀. 로그인 모드엔 가입 전환 하나.
    @ViewBuilder
    private var links: some View {
        VStack(spacing: 8) {
            if mode == .signUp {
                AuthLinkButton(
                    prompt: store.isCreateTeamMode ? "" : "팀 코드가 없나요?",
                    action: store.isCreateTeamMode ? "코드로 참여하기" : "새 팀 만들기"
                ) {
                    toggleCreateTeamMode()
                }
            }
            switchLink
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

    // 코드 입력 ↔ 팀 만들기 폼 전환. 이전 코드 미리보기 잔상을 지워 혼동을 막는다.
    private func toggleCreateTeamMode() {
        store.isCreateTeamMode.toggle()
        store.joinPreview = nil
        store.joinPreviewMessage = ""
    }

    // 입력값은 유지하되, 이전 모드의 오류 배너가 새 모드에서 혼동을 주지 않도록 리셋한다.
    private func switchMode(to newMode: AuthMode) {
        if AuthMessageKind(store.syncMessage) == .error {
            store.syncMessage = "로그인 필요"
        }
        mode = newMode
        // 가입은 항상 코드 입력으로 시작한다(팀 만들기는 하단 링크로 전환).
        if newMode == .signUp {
            store.isCreateTeamMode = false
        }
    }
}

// MARK: - Teamless panel (signed in, no team)

/// 로그인은 됐지만 소속 팀이 없을 때(무소속) 메인 대신 보여 주는 간단 패널.
/// 코드로 참여(참여하기) ↔ 새 팀 만들기 폼을 오간다. 코드 미리보기 UX는 가입 화면과 동일하다.
private struct TeamlessPanel: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        VStack(spacing: 12) {
            if let code = store.createdTeamCode {
                // 팀을 막 만든 직후 — 참여코드 공유 카드로 대체한다.
                BrandHeader(subtitle: "팀 생성 완료")
                PanelDivider()
                CreatedTeamCodeCard(code: code) { store.dismissCreatedTeamCode() }
            } else {
                BrandHeader(subtitle: store.isCreateTeamMode ? "새 팀을 만들어요" : "합류할 팀을 찾아요")
                PanelDivider()
                if store.isCreateTeamMode {
                    createForm
                } else {
                    joinForm
                }
                AuthStatusLine(message: store.syncMessage)
                    .opacity(store.syncMessage == "동기화됨" || store.syncMessage == "로그인 필요" ? 0 : 1)
                    .accessibilityHidden(store.syncMessage == "동기화됨" || store.syncMessage == "로그인 필요")
                modeLink
            }
        }
        .padding(14)
        .panelStyle()
        .animation(.easeInOut(duration: 0.22), value: store.isCreateTeamMode)
    }

    // 코드로 참여: 안내 문구 + 팀 코드 필드(미리보기) + [참여하기].
    @ViewBuilder
    private var joinForm: some View {
        VStack(spacing: 10) {
            Text("소속된 팀이 없어요. 팀 코드를 입력해 합류하세요.")
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            TeamCodeField(
                code: $store.signupTeamCode,
                preview: store.joinPreview,
                message: store.joinPreviewMessage,
                onDebouncedChange: { store.previewTeamCode() }
            )
            AuthButton(title: "참여하기", icon: "person.badge.plus", prominent: true) {
                store.joinTeamWithCode()
            }
            .disabled(!store.canSync)
        }
    }

    // 새 팀 만들기: 팀 이름 + 주간 목표 스테퍼 + [팀 만들고 시작하기]. 가입 화면 폼과 같은 컨트롤을 재사용한다.
    @ViewBuilder
    private var createForm: some View {
        VStack(spacing: 8) {
            CredentialField(
                title: "팀 이름",
                icon: "person.3.fill",
                text: $store.createTeamName
            )
            WeeklyGoalStepper(hours: $store.createTeamGoalHours)
            AuthButton(title: "팀 만들고 시작하기", icon: "flag.fill", prominent: true) {
                // 팀 생성은 가입 화면과 동일한 진입점(signUp)을 쓴다 — create 모드면 create_team 을 실행한다.
                store.signUp()
            }
            .disabled(!store.canSync)
        }
    }

    // 코드 참여 ↔ 새 팀 만들기 전환 링크. 전환 시 이전 코드 미리보기 잔상을 지운다.
    @ViewBuilder
    private var modeLink: some View {
        AuthLinkButton(
            prompt: store.isCreateTeamMode ? "" : "팀 코드가 없나요?",
            action: store.isCreateTeamMode ? "코드로 참여하기" : "새 팀 만들기"
        ) {
            store.isCreateTeamMode.toggle()
            store.joinPreview = nil
            store.joinPreviewMessage = ""
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
