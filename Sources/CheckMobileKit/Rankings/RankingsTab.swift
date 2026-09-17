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

/// 순위 숫자 원. 1·2·3위는 메달 색(안의 글자는 늘 숫자 — 색만으로 말하지 않는다), 나머지는 흐린 숫자.
struct RankingsRankBadge: View {
    let rank: Int
    var usesMedals = true
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 28

    var body: some View {
        let medal = usesMedals ? RankingsMedal.color(rank: rank) : nil
        Text("\(rank)")
            .font(MobileTheme.number(.subheadline, weight: .heavy))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(medal == nil ? MobileTheme.secondaryText : RankingsMedal.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(medal ?? MobileTheme.cardElevated))
            .accessibilityHidden(true)
    }
}

/// 메달 색(맥 `MiniGameMedal` 과 같은 숫자). 메달 위 글자는 짙은 잉크 — 금·은 위 흰 글자는 대비가 무너진다.
enum RankingsMedal {
    static let gold = Color(red: 1.00, green: 0.824, blue: 0.290)
    static let silver = Color(red: 0.839, green: 0.863, blue: 0.902)
    static let bronze = Color(red: 0.878, green: 0.584, blue: 0.353)
    static let ink = Color.black.opacity(0.82)

    static func color(rank: Int) -> Color? {
        switch rank {
        case 1: return gold
        case 2: return silver
        case 3: return bronze
        default: return nil
        }
    }
}

/// 작은 캡슐 칩("우리 팀" · "나" · "비공개" · "루비 +20 받음").
struct RankingsChip: View {
    let text: String
    var tint: Color = MobileTheme.accent

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .fixedSize()
    }
}

/// 한 행 카드(내 행은 accent 테두리).
struct RankingsRowCard<Content: View>: View {
    var highlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(highlighted ? MobileTheme.accent.opacity(0.08) : MobileTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(highlighted ? MobileTheme.accent.opacity(0.7) : MobileTheme.separator, lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

/// 빈 목록·실패 카드(실패면 [다시 시도]).
struct RankingsEmptyCard: View {
    let text: String
    let showsRetry: Bool
    let isLoading: Bool
    let retry: () -> Void

    var body: some View {
        AingCard {
            if isLoading {
                LoadingRow(text)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if showsRetry {
                        Button(action: retry) {
                            Label(RankingsText.retry, systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(MobileTheme.accent)
                    }
                }
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
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 40

    var body: some View {
        VStack(spacing: 3) {
            AvatarView(name: name, url: url, size: size)
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
