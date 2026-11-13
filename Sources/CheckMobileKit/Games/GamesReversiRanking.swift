import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **순위표 절**(로비 갈래 3/4) — 승점(승 − 패) 순위와 그 안의 내 자리. 본은 폰 체스 순위 절(`GamesChessRanking.swift`)이다.
//
// ── 순위는 하나다 ──
// 서버 `reversi_ranking` 은 전적 컷(`record_since_ms`) 이후 **누적 한 벌**만 준다(주간 순위가 없다 — 맥 `ReversiRankColumn` 도 한 벌).
// 머리 오른쪽 캡션이 그 기간을 말한다("10월 1일부터" · 컷이 없으면 "전체 기간").
//
// ── 왜 제자리 절인가 ──
// 새 라우트가 아니라 로비 안의 절이다: 코어 순위 조회는 창 표시를 요구하고(`canPollRanking`), 폰에서 자식 화면을 push 하면
// `reversiScreenDidDisappear()` → `windowDidHide()` 로 60초 폴링이 죽는다.
//
// ── 실패는 이 절 안에서만 ──
// 코어는 순위 조회 실패를 안내줄(notice)로 올리지 않는다(대국 안내를 가리지 않게) — 그리고 아잉 뒤집기 코어에는 "실패했다" 깃발이 없다.
// 그래서 못 받은 동안은 **로딩 줄**이고, 60초 주기가 다시 묻는다(그 줄이 거짓이 아니다 — 실제로 다시 부른다). 받은 행은 다음 실패에 지우지 않는다.

/// 순위 절의 **순수 판정**(맥에서 돈다).
@MainActor
package enum GamesReversiRankingPlan {
    /// 절이 그릴 것. **이 순서로** 본다(`content` 머리말).
    package enum Content: Equatable, Sendable {
        case rows
        /// 서버에 `reversi_ranking` 이 아직 없다(PGRST202) — "순위는 곧 열려요".
        case soon
        /// 받았고 비어 있다.
        case empty
        /// 아직 못 받았다.
        case loading
    }

    package static var collapsedRows: Int { ReversiPhoneText.rankCollapsedRows }
    package static var rowLimit: Int { ReversiPhoneText.rankRowLimit }

    /// ★ **0판인 사람은 안 낀다** — 서버가 이미 거르지만 화면이 그 약속을 다시 지킨다(전적 컷 직후 0승 0패 0무 줄이 사용자 수만큼 생길 수 있다).
    package static func playable(_ entries: [ReversiRankEntry]) -> [ReversiRankEntry] {
        entries.filter { $0.wins + $0.losses + $0.draws > 0 }
    }

    /// 들고 있는 행 — **재정렬하지 않는다**(서버 순서가 권위다 · 동률은 같은 rank). 거르기만 한다.
    package static func held(_ store: ReversiStore) -> [ReversiRankEntry] {
        playable(store.ranking?.entries ?? [])
    }

    package static func visible(_ store: ReversiStore, isExpanded: Bool) -> [ReversiRankEntry] {
        Array(held(store).prefix(isExpanded ? rowLimit : collapsedRows))
    }

    package static func total(_ store: ReversiStore) -> Int { min(held(store).count, rowLimit) }

    package static func showsToggle(_ store: ReversiStore) -> Bool { total(store) > collapsedRows }

    /// ★ **분기 순서**: 행 → 준비 중 → 빈·로딩. 행 갈래가 맨 앞이다 — 깃발을 먼저 보면 받아 둔 행을 버리고 "곧 열려요"를 말한다
    /// (폰 공용 규칙: 절이 줄을 들고 있으면 실패를 조용히 둔다 · 체스 순위 절이 고친 순서).
    package static func content(_ store: ReversiStore) -> Content {
        if !held(store).isEmpty { return .rows }
        if store.rankingUnavailable { return .soon }
        return store.ranking == nil ? .loading : .empty
    }

    /// 목록 **밖**의 내 순위. 순위 응답의 전적이 로비 전적과 어긋나면 nil — 섞으면 "8승 3패 · 승점 +4" 같은 자기모순이 뜬다(코어 판정 하나).
    package static func myRank(_ store: ReversiStore) -> ReversiMyRank? { store.myRankConsistentWithRecord }

    /// 머리 오른쪽 캡션. **한 번도 못 받았으면 아무것도 말하지 않는다** — 컷을 모르는데 "전체 기간"은 거짓이다.
    package static func sinceCaption(_ store: ReversiStore) -> String? {
        guard let ranking = store.ranking else { return nil }
        return ranking.recordSince.map(ReversiPhoneText.rankSince) ?? ReversiPhoneText.rankWholePeriod
    }
}

#if os(iOS)

/// 아잉 뒤집기 로비 **순위표 절**. 상태는 코어 `ReversiStore` 가, 판정은 `GamesReversiRankingPlan` 이 한다. 이 뷰는 타이머를 만들지 않는다.
struct GamesReversiRankingSection: View {
    let store: ReversiStore

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch GamesReversiRankingPlan.content(store) {
        case .rows:
            rows
        case .soon:
            header
            InsetGroup { messageRow(ReversiPhoneText.rankingUnavailable, hint: nil) }
        case .empty:
            header
            InsetGroup { messageRow(ReversiPhoneText.noRanking, hint: ReversiPhoneText.noRankingHint) }
        case .loading:
            header
            InsetGroup {
                GroupRow(divider: .none) { LoadingRow(ReversiPhoneText.rankLoading) }
            }
        }
    }

    private var header: some View {
        SectionHeader(ReversiPhoneText.rankTitle, trailing: headerTrailing, padded: true)
    }

    private var headerTrailing: SectionHeader.Trailing {
        guard let caption = GamesReversiRankingPlan.sinceCaption(store) else { return .none }
        return .text(caption)
    }

    /// 절 아래 작은 두 줄: 승점의 뜻 + 0판인 사람은 안 낀다는 사실(짧은 목록을 사고로 읽지 않게).
    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ReversiPhoneText.rankCaption)
                .fixedSize(horizontal: false, vertical: true)
            Text(ReversiPhoneText.rankZeroGamesNote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rows: some View {
        let visible = GamesReversiRankingPlan.visible(store, isExpanded: isExpanded)
        let showsToggle = GamesReversiRankingPlan.showsToggle(store)
        header
        myRankRow
        InsetGroup {
            // 내 행은 `myUserID` 로 고른다(순위 응답의 `me` 와 무관하게 **행 자체가 나인가** — 맥과 같은 판정).
            let mine = store.myUserID
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                GamesReversiRankRow(entry: entry, isMe: entry.id == mine,
                                    isLast: !showsToggle && index == visible.count - 1)
            }
            if showsToggle { toggleRow(total: GamesReversiRankingPlan.total(store)) }
        }
        caption
    }

    @ViewBuilder
    private var myRankRow: some View {
        if let mine = GamesReversiRankingPlan.myRank(store) {
            InsetGroup {
                GroupRow(divider: .none, isHighlighted: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ReversiPhoneText.myRankTitle)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                        Text(ReversiPhoneText.myRankLine(mine))
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
    }

    /// [전체 보기] · [접기] — **제자리에서** 펴고 접는다(새 화면을 밀면 폴링이 죽는다).
    private func toggleRow(total: Int) -> some View {
        GroupRow(
            divider: .none,
            padding: EdgeInsets(top: 2, leading: MobileTheme.cardPadding - 13, bottom: 2, trailing: MobileTheme.cardPadding)
        ) {
            AingButton(
                isExpanded ? ReversiPhoneText.rankCollapse : ReversiPhoneText.rankSeeAll(total: total),
                systemImage: isExpanded ? "chevron.up" : "chevron.down",
                kind: .plain,
                size: .sm
            ) {
                isExpanded.toggle()
            }
            Spacer(minLength: 0)
        }
    }

    private func messageRow(_ text: String, hint: String?) -> some View {
        GroupRow(divider: .none) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 순위 한 줄 — 순위 탭·체스와 같은 공용 부품(`RankRow` · `RankRowBody` · `PersonName`): 순위 원 · 얼굴 30 · 이름(+ 센터) · 승점과 승·패·무.
/// ★ **일곱 칸을 다 그린다**(순위 · 얼굴 · 이름 · 승점 · 승 · 패 · 무) — 승점만 띄우는 것은 사용자가 금지했다.
private struct GamesReversiRankRow: View {
    let entry: ReversiRankEntry
    let isMe: Bool
    let isLast: Bool

    private let metrics = RankRowScaledMetrics()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        RankRow(isMine: isMe, isLast: isLast, dividerInset: metrics.dividerInset(faceBase: 30),
                minHeight: 48, verticalPadding: (7, 7)) {
            RankRowBody(rank: entry.rank, alignment: .center) {
                // 상태 점은 달지 않는다 — 순위 행 사람은 코어 경계에서 근무가 늘 거짓이다(순위판은 근무 상태판이 아니다).
                PersonAvatar(name: entry.user.displayName, colorSeed: entry.user.id,
                             url: entry.user.avatarURL.flatMap(URL.init(string:)), userID: entry.user.id, size: 30,
                             characterHint: entry.user.characterID)
            } content: {
                if typeSize.isAccessibilitySize {
                    stacked
                } else {
                    ViewThatFits(in: .horizontal) {
                        inline
                        stacked
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ReversiPhoneText.rankRowAccessibility(entry, isMe: isMe)))
    }

    private var inline: some View {
        HStack(alignment: .center, spacing: 8) {
            nameLine
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                pointsText
                recordText
            }
            .fixedSize()
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameLine
            VStack(alignment: .leading, spacing: 2) {
                pointsText
                recordText
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameLine: some View {
        PersonName(entry.user.displayName, center: CenterLabel.serverValue(forDisplay: entry.user.center),
                   isMe: isMe, onTint: true)
    }

    private var pointsText: some View {
        Text(ReversiPhoneText.points(entry.points))
            .font(MobileTheme.number(.callout, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
    }

    private var recordText: some View {
        Text(ReversiPhoneText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
    }
}

#endif
