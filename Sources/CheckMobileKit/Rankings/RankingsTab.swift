#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 순위 탭 화면(SPEC-ios §3.4 · 재디자인 시안 B 05·06): 큰 제목 + 한 줄 부제(판의 기간) · 세그먼트 3개 — 팀 리그 · AI 토큰 · 미니게임.
/// 경로는 `router.pathBinding(for: .rankings)`(하위 화면은 없다), 딥링크 `aingcheck://rankings/<board>` 는 세그먼트를 고른다.
struct RankingsTab: View {
    let store: RankingsStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .rankings)) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        RankingsBoardSubtitle(text: RankingsText.boardSubtitle(store.board))
                        boardPicker
                            .padding(.top, 14)
                        switch store.board {
                        case .league:
                            RankingsLeagueSection(store: store)
                        case .tokens:
                            RankingsTokenSection(store: store)
                        case .minigame:
                            RankingsMiniGameSection(store: store)
                        }
                        Color.clear.frame(height: 1).id(RankingsDemoHooks.bottomAnchor)
                    }
                    .padding(.horizontal, MobileTheme.sideMargin)
                    .padding(.bottom, MobileTheme.space6)
                }
                .refreshable { await store.refresh() }
                .background(MobileTheme.background.ignoresSafeArea())
                .navigationTitle(AingTab.rankings.title)
                .onAppear { RankingsDemoHooks.scrollIfRequested(proxy) }
            }
        }
        .onAppear {
            consumeRoute()
            store.tabDidAppear()
        }
        .onDisappear { store.tabDidDisappear() }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    private var boardPicker: some View {
        Picker(
            "순위 종류",
            selection: Binding(get: { store.board }, set: { store.select(board: $0) })
        ) {
            ForEach(AingRoute.RankingsBoard.allCases, id: \.self) { board in
                Text(RankingsText.segmentTitle(board)).tag(board)
            }
        }
        .pickerStyle(.segmented)
    }

    private func consumeRoute() {
        if let route = store.context.router.consumePendingRoute(for: .rankings) {
            store.open(route)
        }
    }
}

// MARK: - 제목 부제

/// 큰 제목 바로 아래 부제(시안 `.b-lt p` — 15pt 보조 글자, 제목과 1pt). 내비 막대 부제(iOS 26 `navigationSubtitle`)는 13pt 에
/// 막대 높이가 늘어 세그먼트가 한 줄 더 내려가서(실측), 목록 첫 줄로 둔다 — 스크롤하면 제목과 함께 접혀 올라간다.
private struct RankingsBoardSubtitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 데모 스크린샷 전용(DEBUG): `-AingCheckDemoRankingsScroll bottom` 이면 판 맨 아래(상품 안내)까지 내린다. Release 에서는 아무것도 안 한다.
@MainActor
enum RankingsDemoHooks {
    static let bottomAnchor = "rankings-bottom"

    static func scrollIfRequested(_ proxy: ScrollViewProxy) {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-AingCheckDemoRankingsScroll"), arguments.indices.contains(index + 1),
              arguments[index + 1] == "bottom" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
        #endif
    }
}

// MARK: - 내 초상

extension RankingsStore {
    /// 순위의 내 행에 세울 착용 캐릭터(시안 B "나 = 착용 캐릭터"). **새 서버 호출 없음** — 나 탭이 이미 알아 온 값, 모르면 위젯 스냅샷의 지난 값
    /// (둘 다 없으면 nil = 아잉).
    var myCharacterID: String? {
        if let me = context.links.me, me.equippedLoaded { return me.equippedCharacterID }
        return context.widgetSnapshots.current?.resolvedCharacterID
    }

    /// 내 초상의 표정 = 지금 근무 상태(지금 탭 카드 → 없으면 위젯 스냅샷 → 모르면 근무 안 함).
    var myCharacterMood: CharacterMood {
        if let card = context.links.now?.myCard(now: context.clock.now()) {
            return card.isWorking ? (card.isStale ? .lost : .working) : .off
        }
        if let status = context.widgetSnapshots.current?.me?.resolvedStatus {
            return CharacterMood(status)
        }
        return .off
    }
}

// MARK: - 공용 조각

/// 순위 원·메달·칩·행 문법은 게임 탭과 같은 공용 부품이다 — 같은 순위를 두 탭이 다르게 그리던 결함.
/// 원·칩은 `Components/MobileRankComponents.swift`, 행 조립(`RankRow`·`RankRowBody`·`RankRowFace`·치수)과
/// 어제 1등(`ChampionRow`)은 통합 때 `Components/RankBoardParts.swift` 로 승격했다.
typealias RankingsRankBadge = RankBadge
typealias RankingsChip = AingChip
typealias RankingsGroupRow = RankRow
typealias RankingsAdaptiveRow = RankRowBody
typealias RankingsRowMetrics = RankRowMetrics
typealias RankingsScaledMetrics = RankRowScaledMetrics
typealias RankingsFace = RankRowFace

/// 판 머리(시안 `.b-sh`): 제목 19 bold + 오른쪽 부속(보조 글자 · 게임 메뉴 알약 · 달 넘기기). 위 18 · 아래 8 · 좌우 20.
/// 공용 `SectionHeaderBar`(통합 때 승격 — 위 여백만 순위 판 값 18)의 얇은 겉면.
struct RankingsSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        SectionHeaderBar(title, topPadding: 18) { trailing }
    }
}

/// 이름 줄 — 공용 `PersonName` 한 벌(통합 때 승격: 이름 + 센터 배지 + 칩, 큰 글자에서 칩을 아래 줄로, 틴트 행 안 파랑 칩은
/// 다크에서 테두리형). 순위 탭은 **화면 글자** 센터("서울")를 들고 있어 서버 값으로 바꿔 넘기는 일만 한다.
struct RankingsNameLine: View {
    enum Chip: Equatable {
        case myTeam
        case me
        case privateUsage
    }

    let name: String
    let center: String?
    var chips: [Chip] = []
    var nameFont: Font = MobileTheme.rowTitle

    var body: some View {
        PersonName(
            name,
            center: CenterLabel.serverValue(forDisplay: center),
            chips: chips.map(Self.shared),
            font: nameFont,
            onTint: true
        )
    }

    private static func shared(_ chip: Chip) -> PersonName.Chip {
        switch chip {
        case .me: return .me
        case .myTeam: return .accent(RankingsText.myTeamChip)
        case .privateUsage: return .muted(RankingsText.privateChip)
        }
    }
}

/// 빈 목록·불러오는 중·실패(인셋 그룹 한 장 — 실패면 공용 `LoadFailureRow`: 경고 한 줄 + 44pt [다시 시도]).
struct RankingsEmptyCard: View {
    let text: String
    let showsRetry: Bool
    let isLoading: Bool
    let retry: () -> Void

    var body: some View {
        InsetGroup {
            Group {
                if isLoading {
                    LoadingRow(text)
                } else if showsRetry {
                    LoadFailureRow(text, retry: retry)
                } else {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(MobileTheme.cardPadding)
        }
    }
}
#endif
