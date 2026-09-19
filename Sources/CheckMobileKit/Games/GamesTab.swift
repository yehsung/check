#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 게임 탭(SPEC-ios §3.5 · w15 시안 B 07): 큰 제목 + 상품 부제 · 오른쪽 위 루비 유리 알약(→ 상점) ·
/// 미니게임 타일 둘(캔버스 톤 그림 · 오늘 최고·순위) · 1:1 오목 카드(나무판 썸네일 · 받은 신청 칩 · 전적) ·
/// 오늘 내 순위(게임별 1등 · 참여 수 · 내 순위 원) · 지금 대결 중(로비를 이미 알 때만 — 새 조회를 더하지 않는다).
/// 경로는 `router.pathBinding(for: .games)`, 딥링크(`games/<game>` · `gomoku/lobby|invite|match`)는 `consumePendingRoute`.
struct GamesTab: View {
    let store: GamesStore

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .games)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(GamesMiniGameText.prizeCaption)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                    miniGameTiles
                        .padding(.top, 14)
                    gomokuCard
                        .padding(.top, 12)
                    todayRanks
                    liveMatches
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.bottom, 24)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(GamesText.tabTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    GamesToolbarRubyPill(balance: store.rubyBalance) { router.open(.shop) }
                }
            }
            .refreshable {
                for kind in MiniGameKind.allCases { await store.miniGames.loadBoard(kind, withWinner: false) }
                await store.context.gomoku.loadInbox()
            }
            .navigationDestination(for: GamesDestination.self) { destination in
                switch destination {
                case .miniGame(let kind):
                    GamesMiniGameScreen(store: store, kind: kind)
                case .gomoku:
                    GamesGomokuScreen(store: store)
                }
            }
        }
        // 대국 중 화면 꺼짐 방지는 뷰가 쓰지 않는다 — 주인은 스토어 하나(`GamesStore.installIdleTimerSink`, init 에서 단다).
        .onAppear {
            store.hubDidAppear()
            consumeRoute()
            applyDemoSeed()
        }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    // MARK: 미니게임 타일

    @ViewBuilder
    private var miniGameTiles: some View {
        // 큰 글자(접근성 크기): 한 열 — 반 폭 타일에서는 "오늘 최고 874점 · 3위"가 낱글자로 꺾인다.
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ForEach(MiniGameKind.allCases) { miniGameTile($0) }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(MiniGameKind.allCases) { miniGameTile($0) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func miniGameTile(_ kind: MiniGameKind) -> some View {
        let hub = store.miniGames
        let line = GamesText.todayLine(best: hub.myTodayBest(kind), rank: hub.myRank(kind), board: hub.boards[kind] ?? GamesMiniGameBoard())
        return Button {
            store.context.router.push(GamesDestination.miniGame(kind), on: .games)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                GamesTileArt(kind: kind)
                    .frame(height: 112)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                        .font(MobileTheme.rowTitle)
                        .foregroundStyle(MobileTheme.label)
                    Text(line)
                        .font(MobileTheme.rowSubtitle)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 13)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous).fill(MobileTheme.surface))
            .clipShape(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint("\(kind.title) 게임을 열어요")
    }

    // MARK: 오목 카드

    private var gomokuCard: some View {
        let incoming = store.badgeCount
        let gomoku = store.context.gomoku
        // AI 판은 받은 신청을 가리지 않는다 — 규칙과 까닭은 `GamesText.hubShowsActiveMatch`.
        let active = GamesText.hubShowsActiveMatch(
            active: store.hasActiveGomokuMatch, isAIMatch: gomoku.isAIMatch, incoming: incoming)
        let line = GamesText.gomokuLine(
            incoming: incoming, hasActiveMatch: active, hasOutgoing: gomoku.outgoing != nil,
            inboxFailed: gomoku.inboxLoadFailed && gomoku.incoming.isEmpty
        )
        let chip: String? = active ? GamesText.activeMatchChip : (incoming > 0 ? GamesText.incomingChip(incoming) : nil)
        let record = gomoku.record.map { GomokuPhoneText.recordTitle + " " + GomokuPhoneText.record($0) }
        // 칩이 없을 때: 보낸 신청 대기·받은함 실패는 그 한 줄이 먼저, 아니면 전적(모르면 안내 한 줄).
        let detail: String? = chip != nil ? record : ((gomoku.outgoing != nil || gomoku.inboxLoadFailed) ? line : (record ?? line))
        return Button {
            store.context.router.push(GamesDestination.gomoku, on: .games)
        } label: {
            InsetGroup {
                HStack(spacing: 14) {
                    GamesWoodThumbnail()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GomokuPhoneText.title)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(MobileTheme.label)
                        Text(GamesText.gomokuCardSubtitle)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { gomokuChip(chip); gomokuDetail(detail) }
                            VStack(alignment: .leading, spacing: 4) { gomokuChip(chip); gomokuDetail(detail) }
                        }
                        .padding(.top, 3)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MobileTheme.label3)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, MobileTheme.cardPadding)
                .padding(.vertical, 14)
            }
            .contentShape(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint("오목 대결 화면을 열어요")
    }

    @ViewBuilder
    private func gomokuChip(_ text: String?) -> some View {
        if let text {
            AingChip(text: text)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func gomokuDetail(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(MobileTheme.rowSubtitle)
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 오늘 내 순위

    @ViewBuilder
    private var todayRanks: some View {
        let router = store.context.router
        SectionHeader(GamesText.todayRankTitle, trailing: .action(GamesText.seeAllRankings) { router.open(.rankings(.minigame)) }, padded: true)
        InsetGroup {
            ForEach(Array(MiniGameKind.allCases.enumerated()), id: \.element) { index, kind in
                rankRow(kind, isLast: index == MiniGameKind.allCases.count - 1)
            }
        }
    }

    private func rankRow(_ kind: MiniGameKind, isLast: Bool) -> some View {
        let hub = store.miniGames
        let board = hub.boards[kind] ?? GamesMiniGameBoard()
        return Button {
            store.context.router.push(GamesDestination.miniGame(kind), on: .games)
        } label: {
            GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 30 + MobileTheme.space3)) {
                GamesGameIconSquare(kind: kind)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                        .font(MobileTheme.rowTitle)
                        .foregroundStyle(MobileTheme.label)
                    Text(GamesText.hubRankSubtitle(board: board))
                        .font(MobileTheme.rowSubtitle)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let rank = hub.myRank(kind) {
                    RankBadge(rank: rank)
                        .accessibilityLabel("내 순위 \(rank)위")
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    // MARK: 지금 대결 중

    @ViewBuilder
    private var liveMatches: some View {
        let lives = store.context.gomoku.liveMatches
        if !lives.isEmpty {
            SectionHeader(GomokuPhoneText.liveTitle, trailing: .text(GomokuPhoneText.liveCount(lives.count)), padded: true)
            InsetGroup {
                ForEach(Array(lives.enumerated()), id: \.element.id) { index, live in
                    GamesLiveMatchRow(store: store, live: live, isLast: index == lives.count - 1)
                }
            }
        }
    }

    /// 데모 스크린샷 전용: 로비를 다녀온 상태(`visited`) — 허브 자체는 로비를 부르지 않는다(새 조회 없음).
    private func applyDemoSeed() {
        #if DEBUG
        guard GamesDemoSeed.current(isDemo: store.context.isDemo) == .visited else { return }
        Task { await store.context.gomoku.refreshLobby() }
        #endif
    }

    // MARK: 딥링크

    /// 라우터가 남긴 링크를 꺼내 경로를 바꾼다. 무엇을 할지는 스토어가 정한다(오목 화면이 이미 보이면 대상 판을 코어에 바로 넘긴다).
    private func consumeRoute() {
        let router = store.context.router
        guard let route = router.consumePendingRoute(for: .games), let step = store.routeStep(for: route) else { return }
        switch step {
        case .popToRoot:
            router.popToRoot(.games)
        case .push(let destination):
            router.push(destination, on: .games)
        }
    }
}

// MARK: - 타일 그림

/// 미니게임 타일 그림(시안 `.b-art-timing` · `.b-art-flappy`). 캔버스 무대처럼 밤 톤이라 라이트·다크와 무관하게 같다.
private struct GamesTileArt: View {
    let kind: MiniGameKind

    var body: some View {
        GeometryReader { geo in
            switch kind {
            case .timingBar: timing(geo.size)
            case .flappy: flappy(geo.size)
            }
        }
        .accessibilityHidden(true)
    }

    private static let stars: [(x: CGFloat, y: CGFloat)] = [
        (0.12, 14), (0.30, 26), (0.52, 10), (0.70, 22), (0.86, 12), (0.22, 88), (0.78, 92), (0.92, 70)
    ]

    private func timing(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            EllipticalGradient(
                stops: [.init(color: gamesHex(0x7A4A6B), location: 0), .init(color: gamesHex(0x3A2856), location: 0.45),
                        .init(color: gamesHex(0x1D1733), location: 1)],
                center: UnitPoint(x: 0.5, y: 1.1), startRadiusFraction: 0, endRadiusFraction: 0.95
            )
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2, height: 2)
                    .offset(x: size.width * star.x, y: star.y)
            }
            let trackWidth = max(0, size.width - 28)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(gamesHex(0x120E1E))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Self.zone.opacity(0.2), Self.zone.opacity(0.85), Self.zone.opacity(0.2)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: trackWidth * 0.16)
                    .offset(x: trackWidth * 0.58)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 3, height: 26)
                    .shadow(color: .white, radius: 5)
                    .offset(x: trackWidth * 0.41)
            }
            .frame(width: trackWidth, height: 14)
            .offset(x: 14, y: 52)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private static let zone = Color(red: 1, green: 210 / 255, blue: 120 / 255)

    /// 기둥(시안 px 는 타일 폭 182 기준 — 폭 비율로 옮긴다): (왼쪽 비율, 위, 높이).
    private static let pipes: [(x: CGFloat, top: CGFloat, height: CGFloat)] = [
        (0.615, -4, 38), (0.615, 84, 40), (0.879, -4, 18), (0.879, 66, 60)
    ]

    private func flappy(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: gamesHex(0x1F4A63), location: 0), .init(color: gamesHex(0x2E6F73), location: 0.7),
                                   .init(color: gamesHex(0x3C8A6C), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            ForEach(Array(Self.pipes.enumerated()), id: \.offset) { _, pipe in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: gamesHex(0x3FA66A), location: 0), .init(color: gamesHex(0x6BD58F), location: 0.45),
                                                 .init(color: gamesHex(0x3A9660), location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 26, height: pipe.height)
                    .offset(x: size.width * pipe.x, y: pipe.top)
            }
            FlappyAingArt(size: 52)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 4)
                .offset(x: size.width * 0.24, y: 34)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// "오늘 내 순위" 행 앞 30pt 둥근 네모(시안 `.b-iconsq`) — 타일과 같은 무대 색 · 흰 기호(플래피는 아잉 옆모습).
private struct GamesGameIconSquare: View {
    let kind: MiniGameKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: kind == .timingBar ? [gamesHex(0x4B3274), gamesHex(0x8A4F74)] : [gamesHex(0x1F4A63), gamesHex(0x3C8A6C)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            switch kind {
            case .timingBar:
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
            case .flappy:
                FlappyAingArt(size: 24)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// 시안 px 색(무대 그림 전용 — 뜻 색이 아니다).
private func gamesHex(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}
#endif
