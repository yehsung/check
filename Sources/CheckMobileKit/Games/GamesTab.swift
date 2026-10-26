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
                    tetrisDuelCard
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
                // 테트리스도 같다(P5) — 당겨서 새로고침이 카드의 "받은 신청" 칩을 **지금** 맞추는 유일한 길이다
                // (허브 조회는 30초 스로틀이라 사용자가 당긴 것에 답하지 않는다).
                await store.tetris.refreshLobby()
            }
            .navigationDestination(for: GamesDestination.self) { destination in
                switch destination {
                case .miniGame(let kind):
                    GamesMiniGameScreen(store: store, kind: kind)
                case .gomoku:
                    GamesGomokuScreen(store: store)
                case .chess:
                    // ★ 데모 절 닻은 **이 자리가 아니라 체스 화면 안**에 있다(`GamesChessScreen.lobbyScroll`).
                    //   여기서 달면 닻이 보는 값(관전 중인가)이 `navigationDestination` 클로저의 의존성이 되고,
                    //   그 값이 바뀌는 순간 목적지가 다시 세워져 **화면이 한 번 사라졌다 선다**:
                    //   `onDisappear` → `chessScreenDidDisappear()` → `stopWatching()` 이 관전을 내리고,
                    //   그러면 값이 또 바뀌어 같은 일이 되풀이된다. 실측에서 관전 화면이 **영영 안 떴다**.
                    GamesChessScreen(store: store)
                case .tetrisDuel:
                    // ★ 이 가지가 없으면 **iOS 빌드가 통째로 안 선다**(`switch must be exhaustive`) — 그런데
                    //   맥 `swift build` 는 이 파일을 컴파일조차 하지 않는다(`#if os(iOS)`). 유일한 그물은
                    //   `ios/scripts/build-sim.sh` 다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다').
                    // ★ 체스와 같은 까닭으로 **데모 닻을 여기 달지 않는다**: 이 클로저에서 읽는 값이 바뀌면
                    //   목적지가 다시 세워져 화면이 헐리고 `tetrisScreenDidDisappear()` 가 돌아, 수락한 판이
                    //   화면 없이 15초 침묵으로 진다(D5). 로비 탭 선택은 화면 안에서 쥔다.
                    GamesTetrisDuelScreen(store: store)
                }
            }
        }
        // 대국 중 화면 꺼짐 방지는 뷰가 쓰지 않는다 — 주인은 스토어 하나(`GamesStore.installIdleTimerSink`, init 에서 단다).
        .onAppear {
            store.hubDidAppear()
            consumeRoute()
            applyDemoChessRoute()
            applyDemoTetrisRoute()
            applyDemoSeed()
        }
        // 라우트 계기에서도 꺼낸다 — 탭 막대가 이 탭을 **먼저** 마운트했으면 깃발이 서기 전에 onAppear 가 끝난다.
        .onChange(of: router.routeSerial) {
            consumeRoute()
            applyDemoChessRoute()
            applyDemoTetrisRoute()
        }
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
            ? ChessPhoneText.entryBlock(playing: blockedBy?.text)
            : (active ? GamesText.activeMatchChip : (incoming > 0 ? GamesText.incomingChip(incoming) : nil))
        let record = gomoku.record.map { GomokuPhoneText.recordTitle + " " + GomokuPhoneText.record($0) }
        // 칩이 없을 때: 보낸 신청 대기·받은함 실패는 그 한 줄이 먼저, 아니면 전적(모르면 안내 한 줄).
        let detail: String? = blockedBy != nil
            ? ChessPhoneText.entryBlockHint(playing: blockedBy?.text, blocked: .gomoku)
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
        .accessibilityHint(blockedBy == nil
                           ? "오목 대결 화면을 열어요"
                           : (ChessPhoneText.entryBlockHint(playing: blockedBy?.text, blocked: .gomoku) ?? ""))
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
            ? ChessPhoneText.entryBlock(playing: blockedBy?.text)
            : (active ? GamesText.activeMatchChip : (incoming != nil ? ChessPhoneText.incomingChip : nil))
        let record = chess.record.map { ChessPhoneText.recordTitle + " " + ChessPhoneText.record($0) }
        let detail: String? = blockedBy != nil
            ? ChessPhoneText.entryBlockHint(playing: blockedBy?.text, blocked: .chess)
            : (chip != nil ? record : (chess.outgoing != nil ? ChessPhoneText.outgoingLine
                                                            : (record ?? ChessPhoneText.idleLine)))
        return Button {
            store.context.router.push(GamesDestination.chess, on: .games)
        } label: {
            InsetGroup {
                HStack(spacing: 14) {
                    GamesChessTabThumbnail()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ChessPhoneText.title)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(MobileTheme.label)
                        Text(ChessPhoneText.cardSubtitle)
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
        .accessibilityHint(blockedBy == nil
                           ? ChessPhoneText.cardOpenHint
                           : (ChessPhoneText.entryBlockHint(playing: blockedBy?.text, blocked: .chess) ?? ""))
    }

    // MARK: 1:1 테트리스 카드

    /// 1:1 테트리스 카드(설계서 P2) — 체스 카드 **바로 아래**, 모양도 **같다**(썸네일 60 · 제목 · 부제 ·
    /// 칩 + 보조 한 줄 · 꺾쇠). 입구 하나로 로비·준비·판·결과·순위를 다 연다(화면이 단계를 갈아 끼운다 — P6).
    ///
    /// ★ 막는 방향은 **삼각이다**(P3): 오목·체스 판이 흐르면 이 카드가 막히고, 테트리스 판이 흐르면 위 두 카드가
    ///   막힌다. 서버 `chess__busy` 는 셋을 함께 보지만 **오목 쪽 게이트는 남을 모르므로** 안 막은 입구로
    ///   들어가면 흐르던 테트리스 판이 15초 침묵으로 **판돈째 진다**(서버 D5).
    ///
    /// ★ 칩과 보조 줄의 **서열은 `GamesTetrisDuelCard` 한 곳**이다(차단 > 진행 중 판 > 받은 신청 > 보낸 신청 >
    ///   전적 > 기본 한 줄). 여기서 삼항으로 다시 고르면 서열이 두 벌이 되어 한쪽만 고쳐지고, 그 상태가
    ///   **초록인 채로** 남는다 — 그 판정은 맥 스위트가 값으로 잰다(폰 뷰는 못 본다).
    ///
    /// ★ 막혔을 때 **두 자리를 다 그린다**(칩 = 왜 · 보조 줄 = 언제 풀리는지). 한 자리만 그리면 사용자가
    ///   기다릴 끝을 모른다(폰엔 호버 툴팁이 없다).
    private var tetrisDuelCard: some View {
        let blockedBy = store.tetrisEntryBlock
        let chip = GamesTetrisDuelCard.chip(store)
        let detail = GamesTetrisDuelCard.detail(store)
        return Button {
            store.context.router.push(GamesDestination.tetrisDuel, on: .games)
        } label: {
            InsetGroup {
                HStack(spacing: 14) {
                    GamesTetrisDuelTabThumbnail()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(TetrisPhoneText.title)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(MobileTheme.label)
                        Text(TetrisPhoneText.cardSubtitle)
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
        .accessibilityHint(blockedBy == nil
                           ? TetrisPhoneText.cardOpenHint
                           : (ChessPhoneText.entryBlockHint(playing: blockedBy?.text, blocked: .tetris) ?? ""))
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

    /// 데모 스크린샷 전용: 시작 라우트가 체스 장면(`games/chess/…`)이면 체스를 쌓는다.
    /// 깃발은 앱 모델이 세운다(`MobileAppModel.openDemoRouteIfNeeded` — `AingRoute` 에 체스 가지가 없는 까닭이 거기 있다).
    /// `consume…` 이라 두 계기에서 불려도 한 번만 쌓는다.
    ///
    /// ★ **꼬리는 여기서 쓰지 않는다** — 쌓는 화면은 라우트 일곱이 다 같은 `.chess` 하나다(순위·관전은 로비 안
    ///   절이고 대국은 같은 화면이 단계로 갈아 끼운다). 꼬리는 `store.demoChessRoute` 에 남아 두 자리가 읽는다:
    ///   판·관전은 `GamesStore.chessScreenDidAppear`, 절은 위 `gamesDemoChessSectionAnchor` 닻.
    private func applyDemoChessRoute() {
        guard store.consumePendingDemoChessScreen() else { return }
        store.context.router.push(GamesDestination.chess, on: .games)
    }

    /// 데모 스크린샷 전용: 시작 라우트가 1:1 테트리스 장면(`games/tetris/…`)이면 테트리스를 쌓는다.
    /// 깃발은 앱 모델이 세운다(`MobileAppModel.openDemoRouteIfNeeded`). `consume…` 이라 두 계기에서 불려도
    /// **한 번만** 쌓는다.
    ///
    /// ★ **꼬리는 여기서 쓰지 않는다** — 쌓는 화면은 라우트 아홉이 다 같은 `.tetrisDuel` 하나다(설계서 P6:
    ///   순위는 로비 안 탭이고 판은 같은 화면이 단계로 갈아 끼운다). 꼬리는 `store.demoTetrisRoute` 에 남아
    ///   두 자리가 읽는다: 열 판은 `GamesStore.tetrisScreenDidAppear`(`openWindow(focusMatchID:)`), 로비 탭은
    ///   `GamesTetrisDuelScreen.applyDemoTab`.
    private func applyDemoTetrisRoute() {
        guard store.consumePendingDemoTetrisScreen() else { return }
        store.context.router.push(GamesDestination.tetrisDuel, on: .games)
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
            // 길건너 아잉이(v0.3.67)는 폰 타일 목록(`phoneCases`)에 없어 여기 오지 않는다 — 망라 switch 를 지키는 빈 그림.
            case .crossy: EmptyView()
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
            case .crossy:
                // 폰에 없음(`phoneCases`) — 기호 하나로 망라 switch 만 지킨다.
                Image(systemName: kind.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
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
        case .crossy: return [gamesHex(0x2E5A2A), gamesHex(0x4F8A3C)]   // 폰에 없음(`phoneCases`)
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

/// 1:1 테트리스 썸네일 60pt — 오목 나무판·체스판 썸네일과 **같은 변·같은 둥글기**라 세 카드가 한 열로 선다.
///
/// 그림은 **우물 둘**이다(1:1 이라는 사실을 정지 그림 한 장으로 말하는 자리 — 솔로 타일은 우물 하나다).
/// 조각 색·우물 잉크는 **판과 같은 표**(`TetrisPalette`)에서 온다 — 썸네일만 다른 색이면 열고 나서 다른
/// 게임처럼 보인다. 솔로 테트리스 타일 그림(`GamesTileArt.tetris`)은 **한 글자도 건드리지 않았다**(설계서 P1).
private struct GamesTetrisDuelTabThumbnail: View {
    var side: CGFloat = 60

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let clip = Path(roundedRect: rect, cornerRadius: side * 0.2, style: .continuous)
            context.fill(clip, with: .linearGradient(
                Gradient(colors: [gamesHex(0x1D2148), gamesHex(0x3A2A5E)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            context.clip(to: clip)
            let cell = size.width / 11
            for (index, origin) in Self.wellOrigins.enumerated() {
                let wellRect = CGRect(x: origin.x * size.width, y: origin.y * size.height,
                                      width: cell * 4, height: cell * 7)
                let well = Path(roundedRect: wellRect, cornerRadius: 2, style: .continuous)
                context.fill(well, with: .color(TetrisPalette.wellColor.opacity(TetrisPalette.wellOpacity)))
                context.stroke(well, with: .color(Color.white.opacity(0.18)), lineWidth: 0.5)
                for block in Self.blocks[index] {
                    let square = CGRect(x: wellRect.minX + CGFloat(block.x) * cell + 0.5,
                                        y: wellRect.minY + CGFloat(block.y) * cell + 0.5,
                                        width: cell - 1, height: cell - 1)
                    // 방해 줄은 **회색**이다(판과 같은 토큰 — `TetrisDuelPalette.garbageColor`). 조각 색으로
                    // 그리면 썸네일이 공격형이라는 사실을 못 말한다.
                    let color = block.piece.map(TetrisPalette.color) ?? TetrisDuelPalette.garbageColor
                    context.fill(Path(roundedRect: square, cornerRadius: 1, style: .continuous), with: .color(color))
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// 우물 둘의 왼쪽 위(변 비율) — 가운데를 비워 두 판이 마주 본다.
    private static let wellOrigins: [(x: CGFloat, y: CGFloat)] = [(0.09, 0.14), (0.545, 0.14)]

    /// 왼쪽은 떨어지는 I + 쌓인 두 줄, 오른쪽은 **회색 방해 줄**(nil)이 올라온 판 — 공격형이라는 사실(D2)을
    /// 정지 그림 한 장으로 말하는 자리다.
    private static let blocks: [[(x: Int, y: Int, piece: TetrisGame.Piece?)]] = [
        [(0, 0, .i), (1, 0, .i), (2, 0, .i), (3, 0, .i),
         (0, 5, .l), (1, 5, .o), (2, 5, .o), (0, 6, .l), (1, 6, .o), (2, 6, .o), (3, 6, .t)],
        [(2, 3, .s), (3, 3, .s), (1, 4, .s), (2, 4, .s),
         (0, 5, .z), (1, 5, .z), (2, 5, .t), (0, 6, nil), (1, 6, nil), (2, 6, nil), (3, 6, nil)]
    ]
}

/// 시안 px 색(무대 그림 전용 — 뜻 색이 아니다).
private func gamesHex(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}

extension View {
    #if DEBUG
    /// 데모 스크린샷 전용: 체스 **로비 안 절**에서 스크롤을 시작한다(`-AingCheckDemoRoute games/chess/ranking…` ·
    /// `…/watch/<id>`). nil·`.top` 이면 아무것도 안 한다.
    ///
    /// ★ **화면을 밀어 올리지 않는다.** 순위·관전은 자식 라우트가 아니라 로비 스크롤 안의 절이고
    ///   (`GamesChessScreen` 머리말 — push 하면 `onDisappear` → `windowDidHide()` 로 폴링이 죽는다),
    ///   그 둘은 로비의 **마지막 두 절**이라 옮길 것이 닻 하나(`defaultScrollAnchor(.bottom)`)다.
    ///   오목·미니게임이 `-AingCheckGamesDemo bottom` 으로 쓰는 수단과 **같은 수단**이다
    ///   (`gamesDemoScrollAnchor` — 그쪽은 실행 인자가, 이쪽은 라우트 꼬리가 고른다).
    ///
    /// **`#if DEBUG` 안이다**: 인자 타입이 DEBUG 전용 `MobileDemoChessRoute.Section` 이다(출시 게이트
    /// `ios/scripts/check-release-app.sh` — 까닭은 `Demo/MobileDemoChessRoute.swift` 머리). 부르는 자리
    /// (`GamesChessScreen.lobbyScroll`)도 같은 게이트 안이다. Release 에서 잃는 것은 없다: 값을 세우는 자리가
    /// 데모 라우트뿐이라(`MobileAppModel.openDemoRouteIfNeeded`) 그 구성에서는 `demoChessRoute` 가 영원히
    /// nil 이고, nil·`.top` 이면 이 닻은 원래부터 아무것도 하지 않았다.
    ///
    /// ★ **관전이 선 뒤에는 닻을 놓는다**(`isWatching`). 이 닻은 `[관전]` 카드를 보이게 하려던 것인데, 관전이
    ///   시작되면 그 자리의 내용이 **판으로 바뀐다**(`GamesChessWatchSection` — 절 머리 + 카드 + 판 + 상태 상자).
    ///   바닥 닻은 그때도 계속 바닥(순위 절)을 붙잡아 **판을 통째로 접힘 위로 밀어 올렸다**: 실측에서
    ///   `watch/demo-chess-live`·`watch/demo-chess-over`(402·390 둘 다)는 파일 글자(a~h) 한 줄만 네비 바 밑에
    ///   걸쳤고, 앞선 두 레인은 이 화면을 아예 못 봤거나 픽스처를 손대 우회했다. 닻을 놓으면 스크롤이 머리에서
    ///   서고, 관전 절을 화면 위로 올리는 것은 바로 아래 닻이 한다(`GamesChessScreen.watchSectionAnchorID` —
    ///   위쪽 절들이 응답마다 자라므로 한 번 올리는 것으로는 다시 밀려난다).
    ///
    /// ★★ **`if/else` 로 가르지 않는다**(`defaultScrollAnchor` 는 `UnitPoint?` 를 받는다 — nil 이 '닻 없음'이다).
    ///   `@ViewBuilder` 의 두 갈래는 **서로 다른 신원**이라, 값이 뒤집히는 순간 SwiftUI 가 그 아래 나무를
    ///   **헐고 다시 세운다**. 이 닻이 보는 값은 관전 중인가이고 관전은 화면이 서 있는 동안 뒤집히므로,
    ///   갈래로 적으면 로비 스크롤이 통째로 다시 서서 스크롤 자리와 관전 판의 뷰포트 측정이 날아간다
    ///   (이 닻을 `navigationDestination` 자리에 달았을 때는 **체스 화면 자체**가 헐려
    ///   `chessScreenDidDisappear()` → `stopWatching()` 이 돌아 관전이 영영 안 섰다 — 실측).
    func gamesDemoChessSectionAnchor(_ section: MobileDemoChessRoute.Section?, isWatching: Bool) -> some View {
        defaultScrollAnchor(section == .bottom && !isWatching ? .bottom : nil)
    }
    #endif

    /// 데모 스크린샷 전용: **관전 절을 화면 위로** 올린다(`-AingCheckDemoRoute games/chess/watch/<id>`).
    ///
    /// 한 번만 올리면 안 된다 — 로비 응답·관전 응답이 차례로 도착하며 **관전 절 위쪽이 자라** 그만큼 다시 밀려난다
    /// (사람 목록 · 받은 신청 · 안내줄). 그래서 처음 몇 초만 짧게 되풀이한다. 애니메이션을 쓰지 않는 것도 일부러다
    /// (스크린샷이 흐르는 중간을 찍으면 안 된다).
    ///
    /// Release 에서는 **한 줄도 돌지 않는다**: `#if DEBUG` 안이고, 그 안에서도 데모 실행(`isDemo`)이어야 한다.
    ///
    /// ★ 위 닻과 같은 까닭으로 **`if/else` 로 가르지 않는다** — `watchID` 가 nil → 값으로 뒤집히는 순간
    ///   갈래가 바뀌면 로비 스크롤이 헐리고 다시 선다. 갈래 대신 `task(id:)` 를 늘 달고 **안에서** 돌아선다.
    func gamesDemoChessWatchAnchor(isDemo: Bool, watchID: String?, proxy: ScrollViewProxy, id: String) -> some View {
        #if DEBUG
        return task(id: watchID) {
            guard isDemo, watchID != nil else { return }
            for _ in 0..<12 {
                proxy.scrollTo(id, anchor: .top)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        #else
        return self
        #endif
    }
}

#endif
