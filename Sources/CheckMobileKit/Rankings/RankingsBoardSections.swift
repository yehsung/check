#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// MARK: - 팀 리그 (시안 B 05)

/// 팀 리그: 한 인셋 그룹 안의 행(6팀이 한 화면). 행 = 순위 원 · 이니셜 원 · [이름 + 센터 배지(+ '우리 팀') … 평균] ·
/// 부제 "5명 · ● 3명 근무 중 · 목표 40시간" · 얇은 막대 + 퍼센트. 게이지 그라디언트는 '우리 팀' 막대에만.
struct RankingsLeagueSection: View {
    let store: RankingsStore
    private let metrics = RankingsScaledMetrics()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // 머리글·보조 줄·행이 **같은 '지금'** 을 본다(맥이 겪은 "머리글과 행이 다른 말" 결함을 재현하지 않는다).
        let now = store.leagueNow
        let page = store.leagueDisplayPage
        let entries = page.entries
        let state = store.leagueState
        let isPast = store.isLeaguePastWeek
        VStack(alignment: .leading, spacing: 0) {
            RankingsSectionHeader(title: store.leagueTitle) {
                // 머리 오른쪽에 들어갈 자격은 **조작기**에 있다(토큰 판과 같은 자리·같은 부품). "1인당 평균" 힌트는
                // 아래 메타 줄로 내렸다 — 라벨이 조작기를 화면 밖으로 미는 배치는 틀렸다.
                if store.showsLeagueWeekNavigation {
                    RankingsPeriodStepper(
                        unit: .week,
                        periodName: store.leagueWeekName,
                        canStepBack: store.canStepLeagueWeekBack,
                        canStepForward: store.canStepLeagueWeekForward,
                        previous: { store.stepLeagueWeek(by: -1) },
                        next: { store.stepLeagueWeek(by: 1) }
                    )
                }
            }
            metaLine(note: RankingsText.leagueWeekNote(isPastWeek: isPast, myTeamMissing: page.myTeamMissing))
            if entries.isEmpty {
                RankingsEmptyCard(
                    text: RankingsText.leagueEmpty(
                        hasLoaded: state.hasLoaded,
                        isLoading: state.isLoading,
                        hasFailed: state.hasFailed,
                        unfilteredCount: page.unfilteredCount,
                        isPastWeek: isPast
                    ),
                    showsRetry: state.hasFailed && !state.isLoading && store.league.isEmpty,
                    isLoading: state.isLoading && !state.hasLoaded,
                    retry: { Task { await store.loadLeague() } }
                )
            } else {
                if state.hasFailed {
                    InlineNotice(text: RankingsText.leagueFailedText(isPastWeek: isPast), kind: .warning)
                        .padding(.bottom, 8)
                }
                InsetGroup {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        RankingsLeagueRow(
                            rank: index + 1,
                            entry: entry,
                            isMyTeam: entry.id == store.myTeamID,
                            isLast: index == entries.count - 1,
                            now: now,
                            metrics: metrics
                        )
                    }
                }
            }
        }
    }

    /// 머리와 목록 사이 한 줄: 왼쪽 = 과거 주 안내(0~1줄) · 오른쪽 = "1인당 평균"(행의 큰 숫자가 무엇인지).
    ///
    /// **이번 주에도 늘 그린다** — 과거 주에만 생기면 ‹ 를 누를 때마다 머리 아래가 늘었다 줄었다 하며 목록이 튄다.
    /// 이번 주 비용은 캡션 한 줄(≈18pt)뿐이고, 맥이 그 줄을 아껴야 했던 이유(창 700pt 상한 · 행 예산에서 뺀다)가 폰엔 없다(ScrollView).
    /// `.isHeader` 는 주지 않는다 — 제목 탐색이 각주에 멈추면 안 된다.
    private func metaLine(note: String?) -> some View {
        let hint = Text(RankingsText.leagueAverageHint)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    if let note { Text(note).fixedSize(horizontal: false, vertical: true) }
                    hint
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if let note { Text(note).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 8)
                    hint.fixedSize()
                }
            }
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.bottom, 8)
    }
}

struct RankingsLeagueRow: View {
    let rank: Int
    let entry: TeamLeaderboardEntry
    let isMyTeam: Bool
    let isLast: Bool
    /// 섹션이 재는 '지금' 한 벌(행마다 Date() 를 새로 뜨면 머리글과 갈릴 수 있다).
    let now: Date
    let metrics: RankingsScaledMetrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RankingsGroupRow(isMine: isMyTeam, isLast: isLast, dividerInset: metrics.dividerInset(faceBase: 36), verticalPadding: (12, 13)) {
            RankingsAdaptiveRow(rank: rank, alignment: .top, badgeTopOffset: metrics.badgeTopOffset(faceBase: 36)) {
                RankingsFace(name: entry.name, colorSeed: entry.name, url: nil, userID: nil, base: 36, me: nil)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    RankingsTitleLine {
                        RankingsNameLine(name: entry.name, center: entry.center, chips: isMyTeam ? [.myTeam] : [])
                    } value: {
                        Text(RankingsText.leagueValue(entry))
                            .font(MobileTheme.number(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.label)
                    }
                    subtitle
                        .padding(.top, 2)
                    HStack(spacing: 10) {
                        ProgressBar(entry.goal.progress, style: barStyle, thin: true)
                        Text(RankingsText.leaguePercentText(entry))
                            .font(MobileTheme.number(.footnote, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.label2)
                            .frame(minWidth: 34, alignment: .trailing)
                            .fixedSize()
                    }
                    .padding(.top, 8)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(RankingsText.leagueRowAccessibility(rank: rank, entry: entry, isMyTeam: isMyTeam, now: now)))
    }

    /// "5명 · ● 3명 근무 중 · 목표 40시간" — 점은 근무 중인 사람이 있을 때만(초록 = 근무 중). 한 줄에 안 들어가면 조각 사이에서 끊어
    /// "5명 · ● 3명 근무 중" / "목표 40시간" 두 줄(큰 글자 실측: 그대로 줄바꿈하면 '… · 목표' / '40시간' 으로 조각 안에서 끊겼다 — 비평 "구분점이 줄 끝에 매달림").
    private var subtitle: some View {
        ViewThatFits(in: .horizontal) {
            styled(Text("\(headText) · \(RankingsText.leagueGoal(entry))"))
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 1) {
                styled(headText).fixedSize(horizontal: false, vertical: true)
                styled(Text(RankingsText.leagueGoal(entry))).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(MobileTheme.label2)
    }

    /// 이번 주 "5명 · ● 3명 근무 중"(점은 근무 중인 사람이 있을 때만) · 과거 주 "5명 중 4명 참여"(한 조각).
    /// 과거 주엔 초록 점이 없다 — workingCount 는 '지금 근무 중'이라 과거 주엔 뜻이 없다.
    /// **0 인지 따지지 않고 주 판정으로 끊는다**(값이 새어 들어와도 점이 되살아나지 않게). 과거 판정은 **행이 스스로** 한다.
    private var headText: Text {
        if entry.isPastWeek(now: now) { return Text(RankingsText.leagueParticipation(entry)) }
        let members = RankingsText.leagueMembers(entry)
        let working = RankingsText.leagueWorking(entry)
        guard entry.workingCount > 0 else { return Text("\(members) · \(working)") }
        let dot = Text(Image(systemName: "circle.fill"))
            .font(.system(size: 6))
            .foregroundStyle(MobileTheme.workingDot)
            .baselineOffset(1.5)
        return Text("\(members) · \(dot) \(working)")
    }

    private func styled(_ text: Text) -> some View {
        text
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
    }

    private var barStyle: ProgressBar.Style {
        switch RankingsText.leagueBarKind(entry, isMyTeam: isMyTeam) {
        case .done: return .done
        case .gauge: return .gauge
        case .accent: return .accent
        }
    }
}

/// 이름 줄 + 오른쪽 끝 큰 숫자(기준선 맞춤). 접근성 글자 크기에서는 숫자를 이름 아래 줄로.
struct RankingsTitleLine<Name: View, Value: View>: View {
    @ViewBuilder let name: Name
    @ViewBuilder let value: Value
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                name
                value.fixedSize(horizontal: false, vertical: true)
            }
        } else {
            // 사이 간격은 Spacer 하나로만(8) — HStack 간격까지 더하면 '아잉 데모팀 [서울] [우리 팀] 22시간 07분'이 2pt 모자라 칩이 아래 줄로 떨어졌다.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                name
                Spacer(minLength: 8)
                value.fixedSize()
            }
        }
    }
}

// MARK: - AI 토큰

/// AI 토큰: 머리 = "9월 AI 토큰 소모량" + 달 넘기기 알약(목록 첫 행과 섞이지 않게 카드가 아닌 머리 줄로). 행 = 이름 줄 … 총합(억/만) ·
/// 도구 줄(Claude·Codex) … 오늘 +N · 1등 대비 보라 막대. 메달 규칙은 다른 판과 같다(1–3 금은동).
struct RankingsTokenSection: View {
    let store: RankingsStore
    private let metrics = RankingsScaledMetrics()

    var body: some View {
        let state = store.tokenState
        let entries = store.tokenBoard
        let isCurrent = store.isCurrentTokenMonth
        VStack(alignment: .leading, spacing: 0) {
            RankingsSectionHeader(title: store.tokenTitle) {
                RankingsMonthStepper(
                    canStepForward: !isCurrent,
                    previous: { store.stepTokenMonth(by: -1) },
                    next: { store.stepTokenMonth(by: 1) }
                )
            }
            if entries.isEmpty {
                RankingsEmptyCard(
                    text: RankingsText.tokenEmpty(hasLoaded: state.hasLoaded, isLoading: state.isLoading, hasFailed: state.hasFailed, isCurrentMonth: isCurrent),
                    showsRetry: state.hasFailed && !state.isLoading && !state.hasLoaded,
                    isLoading: state.isLoading && !state.hasLoaded,
                    retry: { Task { await store.loadTokens() } }
                )
            } else {
                if state.hasFailed {
                    InlineNotice(text: RankingsText.tokenFailed, kind: .warning)
                        .padding(.bottom, 8)
                }
                let todayKey = store.todayKey
                let top = entries.map(\.total).max() ?? 0
                let me = (id: store.myCharacterID, mood: store.myCharacterMood)
                InsetGroup {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        let isMe = store.myUserID != nil && entry.userID == store.myUserID
                        RankingsTokenRow(
                            rank: index + 1,
                            entry: entry,
                            isMe: isMe,
                            me: isMe ? me : nil,
                            showsPrivateChip: isMe && store.myTokenUsagePublic == false,
                            todayKey: isCurrent ? todayKey : nil,
                            barFraction: RankingsText.tokenBarFraction(total: entry.total, top: top),
                            isLast: index == entries.count - 1,
                            metrics: metrics
                        )
                    }
                }
            }
        }
    }
}

/// 기간 넘기기 알약(‹ ›). 보이는 높이 30 · 누름 영역 44. 달과 주가 **라벨과 하한만** 다르다 —
/// 기호는 `chevron.left/right` 그대로다(맥이 삼각형을 쓴 이유는 뒤로 버튼과 붙어서인데 폰 머리엔 뒤로가 없다).
/// 햅틱은 넣지 않는다(공용 부품이라 토큰 판 손맛까지 같이 바뀐다 — 이번 범위 밖).
struct RankingsPeriodStepper: View {
    enum Unit { case month, week }

    let unit: Unit
    /// 지금 보고 있는 칸 이름("9월" · "9월 14일 주"). 주면 값이 바뀔 때 보이스오버가 알아챈다. nil 이면 예전 그대로.
    var periodName: String? = nil
    /// 달은 과거 하한이 없어 늘 true, 주는 6주 전에서 false.
    var canStepBack: Bool = true
    let canStepForward: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: backLabel, enabled: canStepBack, disabledValue: backBlocked, action: previous)
            Rectangle()
                .fill(MobileTheme.separator)
                .frame(width: 1, height: 16)
                .accessibilityHidden(true)
            arrow("chevron.right", label: forwardLabel, enabled: canStepForward, disabledValue: forwardBlocked, action: next)
        }
        .background(Capsule().fill(MobileTheme.fill))
        .fixedSize()
        // 제목 글자가 바뀌어도 포커스 밖이면 보이스오버는 다시 읽지 않는다. **값 변화로** 걸어 둔다 —
        // 누른 경우뿐 아니라 월요일 0시 스냅·옛 서버 되돌림처럼 조용히 바뀌는 경우가 오히려 알려야 할 쪽이다.
        .onChange(of: periodName) { _, new in
            if let new { AccessibilityNotification.Announcement(new).post() }
        }
    }

    private var backLabel: String { unit == .week ? RankingsText.previousWeek : RankingsText.previousMonth }
    private var forwardLabel: String { unit == .week ? RankingsText.nextWeek : RankingsText.nextMonth }
    /// 달은 과거 하한이 없어 ◂ 가 막히는 일이 없다 → 읽어 줄 사유도 없다.
    private var backBlocked: String { unit == .week ? RankingsText.noEarlierWeek : "" }
    private var forwardBlocked: String { unit == .week ? RankingsText.noLaterWeek : RankingsText.noLaterMonth }

    private func arrow(_ symbol: String, label: String, enabled: Bool, disabledValue: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                // 명시 색이 비활성 흐림을 덮으므로 색으로도 꺼 보이게 한다(3단 기호 색).
                .foregroundStyle(enabled ? MobileTheme.label : MobileTheme.label3)
                .frame(minWidth: 44, minHeight: 30)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
                .padding(.vertical, -7)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
        // 비활성 화살표는 **막힌 이유**를 값으로 말한다(흐린 기호만으로는 6주 상한을 알 길이 없다).
        .accessibilityValue(Text(enabled ? "" : disabledValue))
    }
}

/// 달 넘기기 — 위 부품의 달 설정 한 벌(과거 하한 없음). **호출부를 한 글자도 바꾸지 않으려고 이름을 남긴다.**
struct RankingsMonthStepper: View {
    let canStepForward: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        RankingsPeriodStepper(unit: .month, canStepForward: canStepForward, previous: previous, next: next)
    }
}

struct RankingsTokenRow: View {
    let rank: Int
    let entry: TokenBoardEntry
    let isMe: Bool
    let me: (id: String?, mood: CharacterMood)?
    let showsPrivateChip: Bool
    /// nil 이면 "오늘 +N" 을 그리지 않는다(지난 달).
    let todayKey: String?
    let barFraction: Double
    let isLast: Bool
    let metrics: RankingsScaledMetrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RankingsGroupRow(isMine: isMe, isLast: isLast, dividerInset: metrics.dividerInset(faceBase: 36), verticalPadding: (12, 13)) {
            RankingsAdaptiveRow(rank: rank, alignment: .top, badgeTopOffset: metrics.badgeTopOffset(faceBase: 36)) {
                RankingsFace(name: entry.name, colorSeed: entry.name, url: entry.avatarURL, userID: entry.userID, base: 36, me: me)
            } content: {
                VStack(alignment: .leading, spacing: 0) {
                    RankingsTitleLine {
                        RankingsNameLine(name: entry.name, center: entry.center, chips: chips)
                    } value: {
                        // 억/만 한 체계(도구 줄과 같은 말). 정확한 값은 보이스오버가 읽는다.
                        Text(RankingsText.tokenTotalCompact(entry))
                            .font(MobileTheme.number(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.label)
                    }
                    if entry.toolUsageLabel != nil || todayKey != nil {
                        detailLine
                            .padding(.top, 2)
                    }
                    ProgressBar(barFraction, style: .ai, thin: true)
                        .padding(.top, 8)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(RankingsText.tokenRowAccessibility(rank: rank, entry: entry, isMe: isMe, isPrivate: showsPrivateChip, todayKey: todayKey)))
    }

    @ViewBuilder
    private var detailLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                if let label = entry.toolUsageLabel { wrappedToolText(label) }
                if let todayKey { todayText(todayKey).fixedSize(horizontal: false, vertical: true) }
            }
        } else {
            // 한 줄에 다 들어가면 도구 줄 … 오늘 +N, 안 들어가면 오늘 +N 을 아래 줄로(큰 글자 실측: 한 줄 고정은 'Claude 44.3억 ·…' 로 잘렸다).
            ViewThatFits(in: .horizontal) {
                // 사이 간격은 Spacer 하나로만(8) — HStack 간격(8×2)까지 더하면 'Claude 5.9억 · Codex 1,358만 … 오늘 +346만'이 몇 pt 모자라 두 줄이 됐다(실측).
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if let label = entry.toolUsageLabel { toolText(label).lineLimit(1) }
                    Spacer(minLength: 8)
                    if let todayKey { todayText(todayKey).fixedSize() }
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let label = entry.toolUsageLabel { wrappedToolText(label) }
                        if let todayKey { todayText(todayKey).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 도구 줄이 한 줄에 안 들어가면 도구마다 한 줄("Claude 5.9억" / "Codex 1,358만") — 그냥 줄바꿈하면 'Codex' / '1,358만' 처럼
    /// 조각 안에서 끊겼다(큰 글자 실측). 조각 구분은 `toolUsageLabel` 의 " · ".
    private func wrappedToolText(_ label: String) -> some View {
        ViewThatFits(in: .horizontal) {
            toolText(label).lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(label.components(separatedBy: " · ").enumerated()), id: \.offset) { _, part in
                    toolText(part).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func toolText(_ label: String) -> some View {
        Text(label)
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
    }

    private func todayText(_ todayKey: String) -> some View {
        let grew = entry.todayDelta(currentDate: todayKey) > 0
        return Text(RankingsText.tokenTodayCompact(entry, todayKey: todayKey))
            .font(.system(.footnote, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(grew ? MobileTheme.aiToken : MobileTheme.label2)
    }

    private var chips: [RankingsNameLine.Chip] {
        var result: [RankingsNameLine.Chip] = []
        if isMe { result.append(.me) }
        if showsPrivateChip { result.append(.privateUsage) }
        return result
    }
}

// MARK: - 미니게임 (시안 B 06)

/// 미니게임: 머리 = "오늘 순위" + 게임 메뉴 알약(세그먼트 두 줄을 한 줄로) · 어제 1등 한 줄 그룹(왕관 원 + 이름·점수 + 초록 획득 칩) ·
/// 오늘 순위 그룹(행 48) · 상품 문구(숫자마다 실제 보석) + 정족수 줄.
struct RankingsMiniGameSection: View {
    let store: RankingsStore
    private let metrics = RankingsScaledMetrics()

    var body: some View {
        let state = store.miniGameState
        let entries = store.miniGameBoard
        VStack(alignment: .leading, spacing: 0) {
            RankingsSectionHeader(title: RankingsText.miniGameRankTitle) {
                RankingsGameMenu(selected: store.miniGameKind) { store.select(miniGame: $0) }
            }

            if let winner = store.miniGameWinner {
                RankingsChampionRow(winner: winner)
                    .padding(.bottom, 12)
            }

            if entries.isEmpty {
                RankingsEmptyCard(
                    text: RankingsText.miniGameEmptyText(hasLoaded: state.hasLoaded, hasFailed: state.hasFailed),
                    showsRetry: state.hasFailed && !state.hasLoaded && !state.isLoading,
                    isLoading: state.isLoading && !state.hasLoaded,
                    retry: { Task { await store.loadMiniGame() } }
                )
            } else {
                let me = (id: store.myCharacterID, mood: store.myCharacterMood)
                InsetGroup {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        let isMe = store.myUserID != nil && entry.userID == store.myUserID
                        RankingsMiniGameRow(
                            rank: index + 1,
                            entry: entry,
                            isMe: isMe,
                            me: isMe ? me : nil,
                            isLast: index == entries.count - 1,
                            metrics: metrics
                        )
                    }
                }
            }

            prizeFooter(players: store.knowsMiniGamePlayerCount ? store.miniGamePlayers : nil)
        }
    }

    /// 상품 안내. 정족수 줄은 사람 수를 알 때만(`players` nil = 모른다 — 불러오지 못한 순위를 "아무도 안 했어요"로 말하지 않는다).
    private func prizeFooter(players: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RankingsPrizeLine()
            if let players {
                Text(RankingsText.quorumCaption(players: players))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, 8)
    }
}

/// "자정에 1·2·3등에게 루비 [보석]20 · [보석]10 · [보석]5" — 한 줄에 안 들어가면(큰 글자) 보석 없는 문장으로 줄바꿈.
struct RankingsPrizeLine: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                Text("자정에 1·2·3등에게 루비")
                ForEach(Array(RankingsText.rubyPrizes.enumerated()), id: \.offset) { index, amount in
                    if index > 0 { Text("·") }
                    HStack(spacing: 2) {
                        RubyIcon(size: 14)
                        Text("\(amount)").monospacedDigit()
                    }
                }
            }
            .lineLimit(1)
            Text(RankingsText.prizeCaption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(RankingsText.prizeCaption))
    }
}

/// 게임 고르기 메뉴 알약(시안 `.b-menu` — 회색 알약 30 · 누름 영역 44).
struct RankingsGameMenu: View {
    let selected: MiniGameKind
    let select: (MiniGameKind) -> Void

    var body: some View {
        Menu {
            Picker("게임 종류", selection: Binding(get: { selected }, set: { select($0) })) {
                ForEach(MiniGameKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selected.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            // 시안 `.b-sh span` 이 알약 글자에도 내려와 보조 글자색(회색 알약 + 회색 글자 — 주요 동작이 아니다).
            .foregroundStyle(MobileTheme.label2)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(minHeight: 30)
            .background(Capsule().fill(MobileTheme.fill))
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .padding(.vertical, -7)
        }
        .fixedSize()
        .accessibilityLabel(Text("게임 종류"))
        .accessibilityValue(Text(selected.title))
    }
}

/// 어제 1등 한 줄 — **게임 탭과 같은 공용 부품** `ChampionRow`(통합 때 승격, 비평 4a). 순위 탭은 문구와 점수 꾸밈만 넘긴다.
struct RankingsChampionRow: View {
    let winner: MiniGameWinner

    var body: some View {
        ChampionRow(
            caption: RankingsText.yesterdayChampion,
            name: winner.name,
            center: CenterLabel.serverValue(forDisplay: winner.center),
            score: RankingsText.score(winner.score),
            awarded: winner.awarded ? RankingsText.rubyPrizes[0] : nil
        )
    }
}

struct RankingsMiniGameRow: View {
    let rank: Int
    let entry: MiniGameBoardEntry
    let isMe: Bool
    let me: (id: String?, mood: CharacterMood)?
    let isLast: Bool
    let metrics: RankingsScaledMetrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RankingsGroupRow(isMine: isMe, isLast: isLast, dividerInset: metrics.dividerInset(faceBase: 30), minHeight: 48, verticalPadding: (7, 7)) {
            RankingsAdaptiveRow(rank: rank, alignment: .center) {
                RankingsFace(name: entry.name, colorSeed: entry.name, url: entry.avatarURL, userID: entry.userID, base: 30, me: me)
            } content: {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        RankingsNameLine(name: entry.name, center: entry.center, chips: isMe ? [.me] : [])
                        score
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        RankingsNameLine(name: entry.name, center: entry.center, chips: isMe ? [.me] : [])
                        Spacer(minLength: 4)
                        score
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(RankingsText.miniGameRowAccessibility(rank: rank, entry: entry, isMe: isMe)))
    }

    private var score: some View {
        Text(RankingsText.score(entry.bestScore))
            .font(MobileTheme.number(.callout, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
            .fixedSize()
    }
}
#endif
