#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// MARK: - 팀 리그

struct RankingsLeagueSection: View {
    let store: RankingsStore

    var body: some View {
        let entries = store.leagueDisplay
        let state = store.leagueState
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(RankingsText.leagueTitle)
                Text(RankingsText.leagueCaption)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.secondaryText)
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
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    RankingsLeagueRow(rank: index + 1, entry: entry, isMyTeam: entry.id == store.myTeamID)
                }
            }
        }
    }
}

struct RankingsLeagueRow: View {
    let rank: Int
    let entry: TeamLeaderboardEntry
    let isMyTeam: Bool

    var body: some View {
        RankingsRowCard(highlighted: isMyTeam) {
            RankingsAdaptiveRow(rank: rank, name: entry.name, url: nil, centerLabel: entry.center) {
                VStack(alignment: .leading, spacing: 6) {
                    RankingsNameLine(name: entry.name, chips: isMyTeam ? [RankingsChip(text: RankingsText.myTeamChip)] : [])
                    Text(RankingsText.leagueAverage(entry))
                        .font(MobileTheme.number(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.primaryText)
                    HStack(spacing: 8) {
                        RankingsGauge(progress: entry.goal.progress, tint: entry.goal.isComplete ? MobileTheme.working : MobileTheme.accent)
                        Text("\(RankingsText.leaguePercent(entry))%")
                            .font(MobileTheme.number(.caption, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.secondaryText)
                            .fixedSize()
                    }
                    Text(RankingsText.leagueCaption(entry))
                        .font(.caption)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(RankingsText.leagueRowAccessibility(rank: rank, entry: entry, isMyTeam: isMyTeam)))
    }
}

struct RankingsGauge: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MobileTheme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(6, proxy.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - AI 토큰

struct RankingsTokenSection: View {
    let store: RankingsStore

    var body: some View {
        let state = store.tokenState
        let entries = store.tokenBoard
        let isCurrent = store.isCurrentTokenMonth
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            monthNavigator(isCurrent: isCurrent)
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
                }
                let todayKey = store.todayKey
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let isMe = store.myUserID != nil && entry.userID == store.myUserID
                    RankingsTokenRow(
                        rank: index + 1,
                        entry: entry,
                        isMe: isMe,
                        showsPrivateChip: isMe && store.myTokenUsagePublic == false,
                        todayKey: isCurrent ? todayKey : nil
                    )
                }
            }
        }
    }

    private func monthNavigator(isCurrent: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                store.stepTokenMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(Text(RankingsText.previousMonth))
            Spacer(minLength: 4)
            Text(store.tokenTitle)
                .font(MobileTheme.title(.headline))
                .foregroundStyle(MobileTheme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button {
                store.stepTokenMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(minWidth: 44, minHeight: 44)
                    // 이번 달이면 미래로 못 간다 — 명시 색이 비활성 흐림을 덮으므로 색으로도 꺼 보이게 한다.
                    .foregroundStyle(isCurrent ? MobileTheme.secondaryText.opacity(0.35) : MobileTheme.accent)
            }
            .disabled(isCurrent)
            .accessibilityLabel(Text(RankingsText.nextMonth))
        }
        .foregroundStyle(MobileTheme.accent)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MobileTheme.card)
        )
    }
}

struct RankingsTokenRow: View {
    let rank: Int
    let entry: TokenBoardEntry
    let isMe: Bool
    let showsPrivateChip: Bool
    /// nil 이면 "오늘 +N" 줄을 그리지 않는다(지난 달).
    let todayKey: String?

    var body: some View {
        RankingsRowCard(highlighted: isMe) {
            RankingsAdaptiveRow(rank: rank, usesMedals: false, name: entry.name, url: entry.avatarURL, centerLabel: entry.center) {
                VStack(alignment: .leading, spacing: 4) {
                    RankingsNameLine(name: entry.name, chips: chips)
                    if let label = entry.toolUsageLabel {
                        Text(label)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // ★ 숫자는 **자르지 않는다** — 말줄임("5,014,407,…")은 자릿수 오독이다(맥 TokenBoardRowView 의 회귀 지점).
                    //   좁으면 먼저 조금 줄이고, 그래도 안 되면 줄을 바꾼다(큰 글자 실측 — 한 줄 고정이면 접근성 크기에서 잘렸다).
                    Text(RankingsText.tokenTotal(entry))
                        .font(MobileTheme.number(.subheadline, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let todayKey {
                        Text(RankingsText.tokenToday(entry, todayKey: todayKey))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.aiToken)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(RankingsText.tokenRowAccessibility(rank: rank, entry: entry, isMe: isMe, isPrivate: showsPrivateChip, todayKey: todayKey)))
    }

    private var chips: [RankingsChip] {
        var result: [RankingsChip] = []
        if isMe { result.append(RankingsChip(text: RankingsText.meChip)) }
        if showsPrivateChip { result.append(RankingsChip(text: RankingsText.privateChip, tint: MobileTheme.secondaryText)) }
        return result
    }
}

// MARK: - 미니게임

struct RankingsMiniGameSection: View {
    let store: RankingsStore

    var body: some View {
        let state = store.miniGameState
        let entries = store.miniGameBoard
        VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
            Picker(
                "게임 종류",
                selection: Binding(get: { store.miniGameKind }, set: { store.select(miniGame: $0) })
            ) {
                ForEach(MiniGameKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionHeader(RankingsText.miniGameRankTitle)
                if store.miniGamePlayers > 0 {
                    Label("\(store.miniGamePlayers)명", systemImage: "person.2.fill")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize()
                        .accessibilityLabel(Text("오늘 \(store.miniGamePlayers)명 참여"))
                }
            }

            if let winner = store.miniGameWinner {
                RankingsChampionCard(winner: winner)
            }

            if entries.isEmpty {
                RankingsEmptyCard(
                    text: RankingsText.miniGameEmptyText(hasLoaded: state.hasLoaded, hasFailed: state.hasFailed),
                    showsRetry: state.hasFailed && !state.hasLoaded && !state.isLoading,
                    isLoading: state.isLoading && !state.hasLoaded,
                    retry: { Task { await store.loadMiniGame() } }
                )
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    RankingsMiniGameRow(rank: index + 1, entry: entry, isMe: store.myUserID != nil && entry.userID == store.myUserID)
                }
            }

            prizeFooter(players: store.knowsMiniGamePlayerCount ? store.miniGamePlayers : nil)
        }
    }

    /// 상품 안내. 정족수 줄은 사람 수를 알 때만(`players` nil = 모른다 — 불러오지 못한 순위를 "아무도 안 했어요"로 말하지 않는다).
    private func prizeFooter(players: Int?) -> some View {
        AingCard {
            Label {
                Text(RankingsText.prizeCaption)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(MobileTheme.pending)
            }
            if let players {
                Label {
                    Text(RankingsText.quorumCaption(players: players))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: players >= RankingsText.prizeQuorum ? "checkmark.seal.fill" : "person.2.fill")
                        .foregroundStyle(players >= RankingsText.prizeQuorum ? MobileTheme.working : MobileTheme.secondaryText)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(MobileTheme.secondaryText)
    }
}

struct RankingsChampionCard: View {
    let winner: MiniGameWinner
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RankingsRowCard {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) { crown; avatar }
                    texts
                    score
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    crown
                    avatar
                    texts
                    Spacer(minLength: 4)
                    score
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(RankingsText.yesterdayChampion), \(winner.name), \(RankingsText.score(winner.score))" + (winner.awarded ? ", \(RankingsText.awardedChip)" : "")))
    }

    private var crown: some View {
        Image(systemName: "crown.fill")
            .font(.title3)
            .foregroundStyle(RankingsMedal.gold)
            .accessibilityHidden(true)
    }

    private var avatar: some View {
        RankingsAvatar(name: winner.name, url: winner.avatarURL, centerLabel: winner.center)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RankingsText.yesterdayChampion)
                .font(.caption.weight(.bold))
                .foregroundStyle(MobileTheme.pending)
            Text(winner.name)
                .font(.headline)
                .foregroundStyle(MobileTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if winner.awarded {
                RankingsChip(text: RankingsText.awardedChip, tint: MobileTheme.working)
            }
        }
    }

    private var score: some View {
        Text(RankingsText.score(winner.score))
            .font(MobileTheme.number(.headline, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.primaryText)
            .fixedSize()
    }
}

struct RankingsMiniGameRow: View {
    let rank: Int
    let entry: MiniGameBoardEntry
    let isMe: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RankingsRowCard(highlighted: isMe) {
            RankingsAdaptiveRow(rank: rank, name: entry.name, url: entry.avatarURL, centerLabel: entry.center, alignment: .center) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        RankingsNameLine(name: entry.name, chips: isMe ? [RankingsChip(text: RankingsText.meChip)] : [])
                        score
                    }
                } else {
                    HStack(alignment: .center, spacing: 6) {
                        RankingsNameLine(name: entry.name, chips: isMe ? [RankingsChip(text: RankingsText.meChip)] : [])
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
            .font(MobileTheme.number(.headline, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.primaryText)
            .fixedSize()
    }
}
#endif
