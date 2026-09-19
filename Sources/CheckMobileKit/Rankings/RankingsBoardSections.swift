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

    var body: some View {
        let entries = store.leagueDisplay
        let state = store.leagueState
        VStack(alignment: .leading, spacing: 0) {
            RankingsSectionHeader(title: RankingsText.leagueTitle) {
                Text(RankingsText.leagueHeaderTrailing)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize()
            }
            if entries.isEmpty {
                RankingsEmptyCard(
                    text: RankingsText.leagueEmpty(
                        hasLoaded: state.hasLoaded,
                        isLoading: state.isLoading,
                        hasFailed: state.hasFailed,
                        unfilteredCount: store.league.count
                    ),
                    showsRetry: state.hasFailed && !state.isLoading && store.league.isEmpty,
                    isLoading: state.isLoading && !state.hasLoaded,
                    retry: { Task { await store.loadLeague() } }
                )
            } else {
                if state.hasFailed {
                    InlineNotice(text: RankingsText.leagueFailed, kind: .warning)
                        .padding(.bottom, 8)
                }
                InsetGroup {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        RankingsLeagueRow(
                            rank: index + 1,
                            entry: entry,
                            isMyTeam: entry.id == store.myTeamID,
                            isLast: index == entries.count - 1,
                            metrics: metrics
                        )
                    }
                }
            }
        }
    }
}

struct RankingsLeagueRow: View {
    let rank: Int
    let entry: TeamLeaderboardEntry
    let isMyTeam: Bool
    let isLast: Bool
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
        .accessibilityLabel(Text(RankingsText.leagueRowAccessibility(rank: rank, entry: entry, isMyTeam: isMyTeam)))
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

    /// "5명 · ● 3명 근무 중"(점은 근무 중인 사람이 있을 때만).
    private var headText: Text {
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

/// 달 넘기기 알약(‹ ›). 보이는 높이 30 · 누름 영역 44. 이번 달이면 › 는 꺼진다(흐린 기호).
struct RankingsMonthStepper: View {
    let canStepForward: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: RankingsText.previousMonth, enabled: true, action: previous)
            Rectangle()
                .fill(MobileTheme.separator)
                .frame(width: 1, height: 16)
                .accessibilityHidden(true)
            arrow("chevron.right", label: RankingsText.nextMonth, enabled: canStepForward, action: next)
        }
        .background(Capsule().fill(MobileTheme.fill))
        .fixedSize()
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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
