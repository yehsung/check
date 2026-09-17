#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 순위 탭 화면(SPEC-ios §3.4): 세그먼트 3개 — 팀 리그 · AI 토큰 · 미니게임.
/// 경로는 `router.pathBinding(for: .rankings)`(하위 화면은 없다), 딥링크 `aingcheck://rankings/<board>` 는 세그먼트를 고른다.
struct RankingsTab: View {
    let store: RankingsStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .rankings)) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                        boardPicker
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
                    .padding(.vertical, MobileTheme.rowSpacing)
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

// MARK: - 공용 조각

/// 순위 원·메달·칩은 게임 탭과 같은 공용 부품(`Components/MobileRankComponents.swift`) — 같은 순위를 두 탭이 다른 색으로 그리던 결함.
typealias RankingsRankBadge = RankBadge
typealias RankingsMedal = RankMedal
typealias RankingsChip = AingChip

/// 한 행 카드(내 행·내 팀은 공용 강조 — `RankRowSurface`).
struct RankingsRowCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        content.rankRowSurface(isMine: highlighted, standsAlone: true)
    }
}

/// 빈 목록·실패 카드(실패면 공용 `LoadFailureRow` — 경고 한 줄 + 44pt [다시 시도]).
struct RankingsEmptyCard: View {
    let text: String
    let showsRetry: Bool
    let isLoading: Bool
    let retry: () -> Void

    var body: some View {
        AingCard {
            if isLoading {
                LoadingRow(text)
            } else if showsRetry {
                LoadFailureRow(text, retry: retry)
            } else {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 행 머리(순위 · 아바타) + 본문. 보통 크기는 가로 한 줄, **접근성 글자 크기**에서는 머리를 위 한 줄로 올려 본문에 폭을 다 준다
/// (큰 글자 실측: 가로 그대로면 이름이 한 글자씩 꺾이고 숫자가 잘렸다).
struct RankingsAdaptiveRow<Content: View>: View {
    let rank: Int
    var usesMedals = true
    let name: String
    let url: URL?
    let centerLabel: String?
    var alignment: VerticalAlignment = .top
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    RankingsRankBadge(rank: rank, usesMedals: usesMedals)
                    RankingsAvatar(name: name, url: url, centerLabel: centerLabel)
                }
                content
            }
        } else {
            HStack(alignment: alignment, spacing: 12) {
                RankingsRankBadge(rank: rank, usesMedals: usesMedals)
                RankingsAvatar(name: name, url: url, centerLabel: centerLabel)
                content
            }
        }
    }
}

/// 이름 + 칩. 접근성 글자 크기에서는 칩을 이름 아래 줄로 내린다(이름이 칩에 밀려 한 글자씩 꺾이지 않게).
struct RankingsNameLine: View {
    let name: String
    let chips: [RankingsChip]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                nameText
                if !chips.isEmpty {
                    HStack(spacing: 6) { chipViews }
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                nameText.lineLimit(2)
                chipViews
                Spacer(minLength: 0)
            }
        }
    }

    private var nameText: some View {
        Text(name)
            .font(.headline)
            .foregroundStyle(MobileTheme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chipViews: some View {
        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in chip }
    }
}

/// 아바타 + 센터 배지(아바타 아래에 겹치지 않게 세로로). 엔트리의 `center` 는 이미 화면 글자("서울")라 서버값으로 되돌려 넘긴다.
struct RankingsAvatar: View {
    let name: String
    let url: URL?
    let centerLabel: String?

    var body: some View {
        VStack(spacing: 3) {
            // 크기는 공용 규칙(`AvatarView` 가 글자 배율을 따라 키운다 · 상한 있음) — 제 `@ScaledMetric` 으로 따로 키우지 않는다.
            AvatarView(name: name, url: url, size: 40)
            if let serverValue = CenterLabel.serverValue(forDisplay: centerLabel) {
                CenterBadge(serverValue)
            } else {
                // 센터 없는 행도 같은 높이 — 순위 목록의 행 높이가 들쭉날쭉하지 않게 자리만 잡는다.
                CenterBadge(CenterLabel.seoul).hidden()
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
