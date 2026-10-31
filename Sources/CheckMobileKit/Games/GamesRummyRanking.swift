import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 큐브 **순위 탭**(설계서 §5) — 1등 많은 순(맥 `RummyRankList`)과 그 안의 내 자리. 모양은 테트리스 순위 절(`GamesTetrisDuelRanking`)과 같다.
//
// ── 왜 로비 안 탭인가 ──
// 자식 화면을 push 하면 큐브 화면의 `onDisappear` 로 폴링이 죽는다(오목·체스·테트리스의 실측). 조회는 코어가 쥔다: 창이 보일 때 · 로비 단계에서 60초마다.
// 뷰는 **타이머를 만들지 않는다.** 이 파일이 내는 조회는 "순위 탭을 골랐는데 들고 있는 값이 없다" 한 갈래뿐이다.
//
// ── 실패는 이 탭 안에서만 말한다 ──
// 순위 조회 실패를 안내줄(notice)로 올리지 않는다(코어 `loadRanking` 이 안 올린다).

/// 순위 탭의 **순수 판정**(맥에서 돈다).
package enum GamesRummyRankingPlan {
    package enum Content: Equatable, Sendable {
        case rows, empty, failed, loading
    }

    package static var collapsedRows: Int { 5 }
    package static var rowLimit: Int { 100 }

    /// 0판인 사람은 순위에 안 낀다. 서버가 이미 거르지만 그 약속을 화면이 다시 지킨다. **재정렬하지 않는다** — 서버 순서가 권위다.
    package static func playable(_ rows: [RummyRankRow]) -> [RummyRankRow] {
        rows.filter { ($0.games ?? 0) > 0 }
    }

    package static func held(_ ranking: RummyRanking?) -> [RummyRankRow] {
        Array(playable(ranking?.rows ?? []).prefix(rowLimit))
    }

    package static func visible(_ ranking: RummyRanking?, isExpanded: Bool) -> [RummyRankRow] {
        Array(held(ranking).prefix(isExpanded ? rowLimit : collapsedRows))
    }

    package static func showsToggle(_ ranking: RummyRanking?) -> Bool { held(ranking).count > collapsedRows }

    /// 줄이 있으면 실패를 조용히 둔다(공용 규칙). 받은 적이 있는지는 `ranking` 이 말한다.
    package static func content(ranking: RummyRanking?, failed: Bool) -> Content {
        switch MobileLoadKnowledge.placeholder(hasRows: !held(ranking).isEmpty, hasLoaded: ranking != nil, lastFailed: failed) {
        case .rows: return .rows
        case .empty: return .empty
        case .failed: return .failed
        case .loading: return .loading
        }
    }

    /// 목록 밖의 내 순위. 순위 응답의 `me` 와 로비 전적이 어긋나면 그리지 않는다(한쪽이 늦었다 — 섞으면 자기모순 문장이 뜬다). 0판(rank null)도 그리지 않는다.
    /// 로비 전적을 **아직 모르면** 막지 않는다.
    package static func myRank(ranking: RummyRanking?, lobbyMe: RummyLobbyMe?) -> RummyRankingMe? {
        guard let mine = ranking?.me, mine.rank != nil else { return nil }
        guard let lobbyMe, lobbyMe.games != nil else { return mine }
        return lobbyMe.games == mine.games && lobbyMe.wins == mine.wins ? mine : nil
    }

    /// 순위 탭을 고른 그 순간의 조회. 값을 들고 있으면 코어 60초 주기에 맡긴다 — 탭을 오갈 때마다 긁지 않는다.
    /// ★ 단계 가드: 판·방 중에는 로비가 화면에 없고 코어도 로비 단계에서만 당긴다.
    @MainActor
    package static func shouldRefresh(_ store: RummyStore, tab: GamesRummyLobbyTab) -> Bool {
        store.rankingEnabled && tab == .ranking && store.phase == .lobby && store.ranking == nil
    }

    @MainActor
    package static func refreshIfNeeded(_ store: RummyStore, tab: GamesRummyLobbyTab) {
        guard shouldRefresh(store, tab: tab) else { return }
        store.refreshRanking()
    }
}

#if os(iOS)

/// 로비 **순위 탭**. 상태는 전부 코어 `RummyStore`, 판정은 `GamesRummyRankingPlan`.
struct GamesRummyRankingSection: View {
    let store: RummyStore
    /// 내 행을 고르는 값(소문자 id) — 화면이 넘긴다(테트리스 절과 같은 자리).
    let myUserID: String?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        // 탭을 고른 순간 말고 **탭이 선 채로 화면이 다시 뜬 길**도 있다.
        .onAppear { GamesRummyRankingPlan.refreshIfNeeded(store, tab: .ranking) }
    }

    @ViewBuilder
    private var content: some View {
        SectionHeader(GamesRummyText.rankHeader, padded: true)
        switch GamesRummyRankingPlan.content(ranking: store.ranking, failed: store.rankingLoadFailed) {
        case .rows:
            rows
        case .empty:
            InsetGroup {
                GroupRow(divider: .none) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GamesRummyText.emptyRanking)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                        Text(GamesRummyText.rankEmptyHint)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        case .failed:
            InsetGroup {
                GroupRow(divider: .none) {
                    LoadFailureRow(GamesRummyText.rankLoadFailed) { Task { await store.loadRanking() } }
                }
            }
        case .loading:
            InsetGroup {
                GroupRow(divider: .none) {
                    LoadingRow(GamesRummyText.rankLoading)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        let ranking = store.ranking
        let visible = GamesRummyRankingPlan.visible(ranking, isExpanded: isExpanded)
        let showsToggle = GamesRummyRankingPlan.showsToggle(ranking)
        // 접힌 상태에서 내가 5위 밖이면 이 줄이 그 정보를 맡는다.
        if let mine = GamesRummyRankingPlan.myRank(ranking: ranking, lobbyMe: store.lobby?.me) {
            InsetGroup {
                GroupRow(divider: .none, isHighlighted: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GamesRummyText.myRankTitle)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                        Text(GamesRummyText.myRankLine(rank: mine.rank, games: mine.games, wins: mine.wins))
                            .font(MobileTheme.rowTitle)
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.bottom, MobileTheme.rowSpacing)
        }
        InsetGroup {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                GamesRummyRankRow(row: row, isMe: row.id.uuidString.lowercased() == myUserID,
                                  isLast: !showsToggle && index == visible.count - 1)
            }
            if showsToggle { toggleRow(total: GamesRummyRankingPlan.held(ranking).count) }
        }
    }

    /// 그룹 맨 아래 [전체 보기] · [접기] — 제자리에서 펴고 접는다(새 화면을 밀면 폴링이 죽는다).
    private func toggleRow(total: Int) -> some View {
        GroupRow(divider: .none,
                 padding: EdgeInsets(top: 2, leading: MobileTheme.cardPadding - 13, bottom: 2, trailing: MobileTheme.cardPadding)) {
            AingButton(isExpanded ? GamesRummyText.rankCollapse : GamesRummyText.rankSeeAll(total: total),
                       systemImage: isExpanded ? "chevron.up" : "chevron.down", kind: .plain, size: .sm) {
                isExpanded.toggle()
            }
            Spacer(minLength: 0)
        }
    }
}

/// 순위 한 줄 — 공용 부품(`RankRow`·`RankRowBody`): 순위 원 · 얼굴 · 이름 · 오른쪽 1등 횟수와 판 수. 순위 숫자는 서버 것 그대로다.
private struct GamesRummyRankRow: View {
    let row: RummyRankRow
    let isMe: Bool
    let isLast: Bool

    private let metrics = RankRowScaledMetrics()
    @Environment(\.dynamicTypeSize) private var typeSize

    private var name: String { row.displayName ?? "?" }

    var body: some View {
        RankRow(isMine: isMe, isLast: isLast, dividerInset: metrics.dividerInset(faceBase: 30),
                minHeight: 48, verticalPadding: (7, 7)) {
            RankRowBody(rank: row.rank ?? 0, alignment: .center) {
                PersonAvatar(name: name, colorSeed: row.id.uuidString.lowercased(),
                             url: row.avatarUrl.flatMap(URL.init(string:)), userID: row.id.uuidString.lowercased(), size: 30,
                             characterHint: row.character)
            } content: {
                if typeSize.isAccessibilitySize {
                    stacked
                } else {
                    // 320pt 좁은 기기: 들어가면 한 줄, 안 들어가면 쌓는다.
                    ViewThatFits(in: .horizontal) {
                        inline
                        stacked
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesRummyText.rankRowAccessibility(rank: row.rank, name: name, isMe: isMe, games: row.games, wins: row.wins))
    }

    private var inline: some View {
        HStack(alignment: .center, spacing: 8) {
            PersonName(name, isMe: isMe, onTint: true)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                winsText
                gamesText
            }
            .fixedSize()
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            PersonName(name, isMe: isMe, onTint: true)
            VStack(alignment: .leading, spacing: 2) {
                winsText
                gamesText
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var winsText: some View {
        Text(GamesRummyText.rankWins(row.wins))
            .font(MobileTheme.number(.callout, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
    }

    private var gamesText: some View {
        Text(GamesRummyText.rankGames(row.games))
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
    }
}

#endif
