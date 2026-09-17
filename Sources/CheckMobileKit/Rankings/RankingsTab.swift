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

/// 순위 원·메달·칩은 게임 탭과 같은 공용 부품(`Components/MobileRankComponents.swift`) — 같은 순위를 두 탭이 다른 색으로 그리던 결함.
typealias RankingsRankBadge = RankBadge
typealias RankingsChip = AingChip

/// 판 머리(시안 `.b-sh`): 제목 19 bold + 오른쪽 부속(보조 글자 · 게임 메뉴 알약 · 달 넘기기). 위 18 · 아래 8 · 좌우 20.
struct RankingsSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    titleText
                    trailing
                }
            } else {
                HStack(alignment: .center, spacing: 8) {
                    titleText
                    Spacer(minLength: 8)
                    trailing
                }
            }
        }
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var titleText: some View {
        Text(title)
            .font(MobileTheme.sectionTitle)
            .foregroundStyle(MobileTheme.label)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 인셋 그룹 안 순위 한 행. 행마다 카드가 아니라 **한 그룹 안의 행**(비평 "목록 밀도") — 내 행(내 팀)은 공용 강조 파랑 6%.
/// 구분선은 이름 글자 시작점부터(`RankingsRowMetrics.dividerInset`), 마지막 행은 긋지 않는다.
struct RankingsGroupRow<Content: View>: View {
    let isMine: Bool
    let isLast: Bool
    let dividerInset: CGFloat
    var minHeight: CGFloat = MobileTheme.rowHeight
    var verticalPadding: (top: CGFloat, bottom: CGFloat) = (10, 10)
    @ViewBuilder let content: Content

    var body: some View {
        GroupRow(
            divider: isLast ? .none : .inset(dividerInset),
            minHeight: minHeight,
            padding: EdgeInsets(top: verticalPadding.top, leading: MobileTheme.cardPadding, bottom: verticalPadding.bottom, trailing: MobileTheme.cardPadding)
        ) {
            content
        }
        .rankRowSurface(isMine: isMine, standsAlone: false, padding: 0, cornerRadius: 0)
    }
}

/// 행 머리(순위 원 · 얼굴) + 본문. 보통 크기는 가로 한 줄, **접근성 글자 크기**에서는 머리를 위 한 줄로 올려 본문에 폭을 다 준다
/// (큰 글자 실측: 가로 그대로면 이름이 한 글자씩 꺾이고 숫자가 잘렸다).
struct RankingsAdaptiveRow<Face: View, Content: View>: View {
    let rank: Int
    var alignment: VerticalAlignment = .center
    /// 윗줄 맞춤 행(팀 리그)에서 순위 원을 얼굴 가운데 높이로 내리는 양.
    var badgeTopOffset: CGFloat = 0
    @ViewBuilder let face: Face
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    RankingsRankBadge(rank: rank)
                    face
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: RankingsRowMetrics.gap) {
                RankingsRankBadge(rank: rank)
                    .padding(.top, alignment == .top ? badgeTopOffset : 0)
                face
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 행 치수(시안 `.b-lg-row` · `.b-mg-row`): 순위 원 24 · 사이 10 · 얼굴 36(리그·토큰)/30(미니게임). 얼굴은 글자를 따라 커진다
/// (`MobileAvatarScale` — `PersonAvatar` 와 같은 규칙) — 구분선 시작점도 같은 배율로 옮긴다.
enum RankingsRowMetrics {
    static let gap: CGFloat = 10

    static func dividerInset(rankSide: CGFloat, faceBase: CGFloat, textScale: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
        if isAccessibilitySize { return MobileTheme.cardPadding }
        return MobileTheme.cardPadding + rankSide + gap + MobileAvatarScale.side(base: faceBase, textScale: textScale) + gap
    }
}

/// 그룹 행에서 쓰는 치수 읽기(글자 배율 · 순위 원 크기 — 공용 부품과 같은 기준 글자).
struct RankingsScaledMetrics: DynamicProperty {
    @ScaledMetric(relativeTo: .body) var textScale: CGFloat = 1
    @ScaledMetric(relativeTo: .subheadline) var rankSide: CGFloat = 24
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    func dividerInset(faceBase: CGFloat) -> CGFloat {
        RankingsRowMetrics.dividerInset(rankSide: rankSide, faceBase: faceBase, textScale: textScale, isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    /// 윗줄 맞춤 행에서 순위 원을 얼굴 가운데 높이로 내리는 양(시안 `.b-lg-row .b-rank{margin-top:6px}` = (36 − 24) / 2).
    func badgeTopOffset(faceBase: CGFloat) -> CGFloat {
        max(0, (MobileAvatarScale.side(base: faceBase, textScale: textScale) - rankSide) / 2)
    }
}

/// 행의 얼굴: 내 행은 착용 캐릭터 초상(표정 = 근무 상태), 남은 이니셜 틴트 원(사진이 있으면 사진). 점은 그리지 않는다(순위판은 근무 상태판이 아니다).
struct RankingsFace: View {
    let name: String
    let colorSeed: String
    let url: URL?
    let base: CGFloat
    let me: (id: String?, mood: CharacterMood)?
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        if let me {
            CharacterPortrait(id: me.id, mood: me.mood, size: MobileAvatarScale.side(base: base, textScale: textScale))
        } else {
            PersonAvatar(name: name, colorSeed: colorSeed, url: url, size: base)
        }
    }
}

/// 이름 줄: 이름 + 센터 배지(늘 이름 뒤) + 칩('우리 팀' · '나' · '비공개'). 한 줄에 안 들어가면 칩을 아래 줄로(이름이 칩에 밀려 꺾이지 않게).
/// 내 행(파랑 틴트) 안의 파랑 칩은 다크에서 테두리형(시안 B 다크 보정 — 틴트 위 틴트 3.5:1).
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 6) {
                    nameText.lineLimit(1)
                    badges
                }
                stacked
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 3) {
            nameText.fixedSize(horizontal: false, vertical: true)
            if hasBadges {
                HStack(spacing: 6) { badges }
            }
        }
    }

    private var nameText: some View {
        Text(name)
            .font(nameFont)
            .foregroundStyle(MobileTheme.label)
    }

    private var hasBadges: Bool { !chips.isEmpty || CenterLabel.display(serverCenter) != nil }

    private var serverCenter: String? { CenterLabel.serverValue(forDisplay: center) }

    @ViewBuilder
    private var badges: some View {
        CenterBadge(serverCenter)
        ForEach(chips, id: \.self) { chip in
            switch chip {
            case .me:
                MeChip(outlined: colorScheme == .dark)
            case .myTeam:
                RankingsSmallChip(text: RankingsText.myTeamChip, tint: MobileTheme.accent, outlined: colorScheme == .dark)
            case .privateUsage:
                RankingsSmallChip(text: RankingsText.privateChip, tint: MobileTheme.label2, outlined: false, fill: MobileTheme.fill)
            }
        }
    }
}

/// 이름 뒤 작은 칩(높이 18 · 11pt — 시안 `.b-me-chip`, 센터 배지와 같은 키). 공용 `AingChip` 은 22pt 라 이름 줄에서 배지와 높이가 어긋난다.
struct RankingsSmallChip: View {
    let text: String
    let tint: Color
    var outlined = false
    var fill: Color?

    var body: some View {
        Text(text)
            .font(.system(.caption2, weight: .bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background {
                if outlined {
                    Capsule().strokeBorder(MobileTheme.accentLine, lineWidth: 1)
                } else {
                    Capsule().fill(fill ?? MobileTheme.accentTint)
                }
            }
            .fixedSize()
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
