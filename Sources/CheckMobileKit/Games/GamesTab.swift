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
                    chessCard
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
                for kind in MiniGameKind.phoneCases { await store.miniGames.loadBoard(kind, withWinner: false) }
                await store.context.gomoku.loadInbox()
                // 체스는 받은함 RPC 가 없다 — 받은 신청·진행 판·전적이 전부 로비 응답에 실려 온다(`GamesStore.hubDidAppear`).
                await store.chess.refreshLobby()
            }
            .navigationDestination(for: GamesDestination.self) { destination in
                switch destination {
                case .miniGame(let kind):
                    GamesMiniGameScreen(store: store, kind: kind)
                case .gomoku:
                    GamesGomokuScreen(store: store)
                case .chess:
                    GamesChessScreen(store: store)
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
                ForEach(MiniGameKind.phoneCases) { miniGameTile($0) }
            }
        } else {
            // 2열 격자다(예전엔 HStack 하나). 게임이 셋이 되면 한 줄에 안 들어간다 —
            // 격자는 셋째 타일을 다음 줄 왼쪽에 세우고, 줄 안 두 타일의 높이도 맞춰 준다.
            LazyVGrid(columns: Self.tileColumns, spacing: 12) {
                ForEach(MiniGameKind.phoneCases) { miniGameTile($0) }
            }
        }
    }

    private static let tileColumns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top)
    ]

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
        // ★ 한 사람 한 판(B8) — **이 방향은 클라밖에 막는 데가 없다.** 서버의 오목 게이트는 체스를 모르므로
        //   (`GamesBusyGame` 머리말) 체스 판이 흐르는 동안 이 카드를 열어 두면 오목 로비의 [수락]으로
        //   오목이 시작되고, 판돈이 걸린 체스가 조용히 시간패한다(맥 적대 검증이 P0 으로 잡은 자리).
        //   화면을 **아예 열지 않는 것**이 지금 그 수락을 막는 유일한 길이다(로비의 [수락]에는 게이트가 없다).
        //   딥링크로 들어오는 같은 길은 `GamesStore.routeStep` 이 막는다 — 두 입구가 짝이다.
        let blockedBy = store.gomokuEntryBlock
        // AI 판은 받은 신청을 가리지 않는다 — 규칙과 까닭은 `GamesText.hubShowsActiveMatch`.
        let active = GamesText.hubShowsActiveMatch(
            active: store.hasActiveGomokuMatch, isAIMatch: gomoku.isAIMatch, incoming: incoming)
        let line = GamesText.gomokuLine(
            incoming: incoming, hasActiveMatch: active, hasOutgoing: gomoku.outgoing != nil,
            inboxFailed: gomoku.inboxLoadFailed && gomoku.incoming.isEmpty
        )
        let chip: String? = blockedBy != nil
            ? GamesCrossGameText.busyChip(blockedBy)
            : (active ? GamesText.activeMatchChip : (incoming > 0 ? GamesText.incomingChip(incoming) : nil))
        let record = gomoku.record.map { GomokuPhoneText.recordTitle + " " + GomokuPhoneText.record($0) }
        // 칩이 없을 때: 보낸 신청 대기·받은함 실패는 그 한 줄이 먼저, 아니면 전적(모르면 안내 한 줄).
        let detail: String? = blockedBy != nil
            ? GamesCrossGameText.busyDetail(blockedBy)
            : (chip != nil ? record : ((gomoku.outgoing != nil || gomoku.inboxLoadFailed) ? line : (record ?? line)))
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
            .opacity(blockedBy == nil ? 1 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .disabled(blockedBy != nil)
        .accessibilityHint(blockedBy == nil ? "오목 대결 화면을 열어요" : GamesCrossGameText.busyDetail(blockedBy))
    }

    // MARK: 체스 카드

    /// 1:1 체스 카드 — 오목 카드와 **같은 모양**(썸네일 60 · 제목 · 부제 · 칩 + 보조 한 줄 · 꺾쇠).
    /// 입구 하나로 로비·대국·결과·순위·관전·로봇을 다 연다(체스 화면이 단계를 갈아 끼운다).
    ///
    /// ★ 막는 방향은 **양쪽이다**: 오목 판이 흐르면 이 카드가 막히고(아래 `blockedBy`), 체스 판이 흐르면
    ///   위 오목 카드가 막힌다. 한 방향만 막으면 막히지 않은 쪽으로 들어가 다른 판을 시간패한다.
    private var chessCard: some View {
        let chess = store.chess
        let blockedBy = store.chessEntryBlock
        let incoming = chess.visibleIncoming
        // 로봇 판은 사람의 신청을 가리지 않는다 — 오목 카드와 같은 규칙(`GamesText.hubShowsActiveMatch`).
        let active = GamesText.hubShowsActiveMatch(
            active: store.hasActiveChessMatch, isAIMatch: chess.isAIMatch, incoming: incoming == nil ? 0 : 1)
        let chip: String? = blockedBy != nil
            ? GamesCrossGameText.busyChip(blockedBy)
            : (active ? GamesText.activeMatchChip : (incoming != nil ? GamesCrossGameText.chessIncomingChip : nil))
        let record = chess.record.map { GamesCrossGameText.chessRecordTitle + " " + GamesCrossGameText.chessRecord($0) }
        let detail: String? = blockedBy != nil
            ? GamesCrossGameText.busyDetail(blockedBy)
            : (chip != nil ? record : (chess.outgoing != nil ? GamesCrossGameText.chessOutgoingLine
                                                            : (record ?? GamesCrossGameText.chessIdleLine)))
        return Button {
            store.context.router.push(GamesDestination.chess, on: .games)
        } label: {
            InsetGroup {
                HStack(spacing: 14) {
                    GamesChessTabThumbnail()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GamesCrossGameText.chessTitle)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(MobileTheme.label)
                        Text(GamesCrossGameText.chessSubtitle)
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
            .opacity(blockedBy == nil ? 1 : 0.55)
            .contentShape(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .disabled(blockedBy != nil)
        .accessibilityHint(blockedBy == nil ? "체스 대결 화면을 열어요" : GamesCrossGameText.busyDetail(blockedBy))
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
            ForEach(Array(MiniGameKind.phoneCases.enumerated()), id: \.element) { index, kind in
                rankRow(kind, isLast: index == MiniGameKind.phoneCases.count - 1)
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
            case .tetris: tetris(geo.size)
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

    /// 테트리스 타일: 무대 밤 톤 하늘 + 가운데 우물 + 쌓인 조각 + 떨어지는 I.
    ///
    /// 조각 색은 **판과 같은 표**(`TetrisPalette`)에서 온다 — 타일만 다른 색이면 열고 나서 다른 게임처럼 보인다.
    /// 우물도 같은 잉크·불투명도라 타일이 판의 축소판이 된다.
    private func tetris(_ size: CGSize) -> some View {
        let cell: CGFloat = 14
        let wellWidth = cell * 6
        let wellHeight = cell * 7
        let originX = (size.width - wellWidth) / 2
        let originY: CGFloat = 7
        return ZStack(alignment: .topLeading) {
            LinearGradient(stops: [.init(color: gamesHex(0x151A3A), location: 0), .init(color: gamesHex(0x24204E), location: 0.55),
                                   .init(color: gamesHex(0x3A2A5E), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            ForEach(Array(Self.stars.prefix(5).enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2, height: 2)
                    .offset(x: size.width * star.x, y: star.y)
            }
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(TetrisPalette.wellColor.opacity(TetrisPalette.wellOpacity))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .frame(width: wellWidth, height: wellHeight)
                .offset(x: originX, y: originY)
            ForEach(Array(Self.tetrisCells.enumerated()), id: \.offset) { _, block in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(TetrisPalette.color(block.piece))
                    .frame(width: cell - 1, height: cell - 1)
                    .offset(x: originX + CGFloat(block.x) * cell + 0.5, y: originY + CGFloat(block.y) * cell + 0.5)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// 타일 한 장의 판(6×7 칸): 아래 두 줄은 쌓인 조각, 위 한 줄은 **떨어지는 중인 I** — 정지 그림 한 장으로
    /// "움직이는 게임"이라고 말하는 자리다(플래피 타일의 아잉과 같은 역할).
    private static let tetrisCells: [(x: Int, y: Int, piece: TetrisGame.Piece)] = [
        (1, 1, .i), (2, 1, .i), (3, 1, .i), (4, 1, .i),
        (0, 5, .l), (1, 5, .l), (2, 5, .o), (3, 5, .o), (5, 5, .t),
        (0, 6, .l), (1, 6, .z), (2, 6, .o), (3, 6, .o), (4, 6, .s), (5, 6, .t)
    ]
}

/// "오늘 내 순위" 행 앞 30pt 둥근 네모(시안 `.b-iconsq`) — 타일과 같은 무대 색 · 흰 기호(플래피는 아잉 옆모습).
private struct GamesGameIconSquare: View {
    let kind: MiniGameKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: Self.backdrop(kind), startPoint: .topLeading, endPoint: .bottomTrailing))
            switch kind {
            case .timingBar:
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
            case .flappy:
                FlappyAingArt(size: 24)
            case .tetris:
                // 타일 그림과 같은 두 색(I 하늘 · O 노랑)으로 작은 조각 하나. 기호(`square.grid.2x2.fill`)를 쓰면
                // 30pt 에서 오목 입구(3×3 격자)와 실루엣이 겹친다.
                HStack(spacing: 1.5) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(TetrisPalette.color(.i))
                        .frame(width: 5, height: 14)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(TetrisPalette.color(.o))
                        .frame(width: 10, height: 10)
                        .offset(y: 2)
                }
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    /// 아이콘 바탕 — 게임마다 자기 타일의 무대 색이다. 예전에는 삼항 하나라 테트리스가 플래피 색으로 떨어졌다.
    private static func backdrop(_ kind: MiniGameKind) -> [Color] {
        switch kind {
        case .timingBar: return [gamesHex(0x4B3274), gamesHex(0x8A4F74)]
        case .flappy: return [gamesHex(0x1F4A63), gamesHex(0x3C8A6C)]
        case .tetris: return [gamesHex(0x24204E), gamesHex(0x3A2A5E)]
        }
    }
}

// MARK: - 체스 카드 조각

/// 체스판 썸네일 60pt — 오목 나무판 썸네일(`GamesWoodThumbnail`)과 **같은 변·같은 둥글기**라 두 카드가 한 열로 선다.
/// 판 캔버스(`GamesChessBoard` — 다른 레인)와는 별개다: 이쪽은 정지 그림 한 장이고 좌표·방향·애니메이션이 없다.
private struct GamesChessTabThumbnail: View {
    var side: CGFloat = 60

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let clip = Path(roundedRect: rect, cornerRadius: side * 0.2, style: .continuous)
            context.fill(clip, with: .color(Self.light))
            context.clip(to: clip)
            let cell = size.width / 8
            for rank in 0..<8 {
                for file in 0..<8 where (rank + file) % 2 == 1 {
                    let square = CGRect(x: CGFloat(file) * cell, y: CGFloat(rank) * cell, width: cell, height: cell)
                    context.fill(Path(square), with: .color(Self.dark))
                }
            }
            // 흑·백 한 점씩 — 정지 그림 한 장으로 "두 사람이 두는 판"이라고 말하는 자리(오목 썸네일의 돌과 같은 역할).
            for (file, rank, color) in Self.pieces {
                let center = CGPoint(x: (CGFloat(file) + 0.5) * cell, y: (CGFloat(rank) + 0.5) * cell)
                let dot = CGRect(x: center.x - cell * 0.3, y: center.y - cell * 0.3, width: cell * 0.6, height: cell * 0.6)
                context.fill(Path(ellipseIn: dot), with: .color(color))
                context.stroke(Path(ellipseIn: dot), with: .color(Color.black.opacity(0.25)), lineWidth: 0.5)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private static let light = Color(red: 0.93, green: 0.88, blue: 0.78)
    private static let dark = Color(red: 0.54, green: 0.38, blue: 0.27)
    private static let pieces: [(Int, Int, Color)] = [
        (3, 6, Color.white), (4, 4, Color.white), (4, 1, Color(white: 0.12)), (2, 3, Color(white: 0.12))
    ]
}

/// 두 게임 카드가 **같이** 쓰는 문구(한 사람 한 판 안내)와 체스 카드 문구.
///
/// **임시 자리다** — 옮길 자리가 이미 정해져 있다(문구 레인의 `ChessPhoneText`, 별칭 `GamesChessText`):
///  · `busyChip(_:)`   → `ChessPhoneText.busyTitle(.chess)` / `.gomoku`
///  · `busyDetail(_:)` → `ChessPhoneText.busyHint(.chess)` / `.gomoku`
///  · 나머지 체스 줄   → `ChessPhoneText` 의 해당 항목
/// 그 파일이 이 레인의 워크트리에는 **아직 없어서**(세션 시작 HEAD 포크) 부르면 컴파일되지 않는다.
/// 그래서 임시로 두고 **오목 쪽 공용 파일(`GamesText.swift`)은 한 줄도 건드리지 않았다.**
///
/// ★ 시간 수치는 카드에 싣지 않는다 — 그 값은 서버가 말하고(로비 `initial_ms`·`increment_ms`) 카드는 로비를
///   안 읽었을 수도 있다. 10-12 에 5분 → 10분으로 늘어난 값이라 박아 두면 그 자리가 곧 거짓이 된다.
private enum GamesCrossGameText {
    static let chessTitle = "1:1 체스"
    /// 시간 수치는 카드에 싣지 않는다 — 그 값은 서버가 말하고(로비 응답) 카드는 로비를 안 읽을 수도 있다.
    static let chessSubtitle = "FIDE 규칙 · 백 선공 · 로봇과도 둬요"
    static let chessRecordTitle = "내 전적"
    static let chessIncomingChip = "받은 신청 1건"
    static let chessOutgoingLine = "보낸 신청을 기다리고 있어요"
    static let chessIdleLine = "상대를 골라 대결을 신청해요"

    static func chessRecord(_ record: ChessRecord) -> String {
        "\(record.wins)승 \(record.losses)패 \(record.draws)무"
    }

    /// 다른 게임 판이 흐르는 동안의 칩. **한 사람은 한 판만** 둘 수 있다(B8).
    static func busyChip(_ busy: GamesBusyGame?) -> String {
        switch busy {
        case .chess: return "체스 대국 중"
        case .gomoku: return "오목 대국 중"
        case nil: return ""
        }
    }

    /// 그 까닭 한 줄 — 비활성 카드의 보조 줄이자 보이스오버 힌트. "지금은 못 눌러요"가 아니라
    /// **언제 열리는지**를 말한다(사용자가 할 수 있는 일을 말하는 규약).
    static func busyDetail(_ busy: GamesBusyGame?) -> String {
        switch busy {
        case .chess: return "체스 대국이 끝나면 열려요 · 한 번에 한 판만 둘 수 있어요"
        case .gomoku: return "오목 대국이 끝나면 열려요 · 한 번에 한 판만 둘 수 있어요"
        case nil: return ""
        }
    }
}

/// 시안 px 색(무대 그림 전용 — 뜻 색이 아니다).
private func gamesHex(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}
#endif
