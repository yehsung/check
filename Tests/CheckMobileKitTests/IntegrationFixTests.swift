import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 통합본 수리(w4/int-fix) 회귀 — 통합 검증(int-verify)이 찾은 **탭 사이에서 갈라진 규칙**을 한 곳에서 지킨다.
///
/// - 조회 실패를 "없음"으로 말하지 않는다: 게임 허브 카드 · 오목 받은 신청 · 대결 중 · 순위 탭 미니게임 정족수(공용 `MobileLoadKnowledge`).
/// - 제보 화면이 이미 떠 있어도 알림이 가리킨 제보를 펼친다(`MeStore.feedbackFocusSerial`).
/// - 디자인 일관성(소스 계약): 공용 [다시 시도] · 순위 원 · 아바타 크기 규칙.
@MainActor
@Suite(.serialized) struct IntegrationFixTests {
    // MARK: - 공용 규칙

    @Test("아는가 규칙: 줄이 있으면 줄 · 받았고 마지막이 성공이면 없음 · 모르고 실패면 실패 · 아니면 불러오는 중")
    func loadKnowledgeTable() {
        typealias K = MobileLoadKnowledge
        #expect(K.placeholder(hasRows: true, hasLoaded: false, lastFailed: true) == .rows, "지난 줄이 있으면 적어도 그만큼은 있다")
        #expect(K.placeholder(hasRows: false, hasLoaded: true, lastFailed: false) == .empty)
        #expect(K.placeholder(hasRows: false, hasLoaded: true, lastFailed: true) == .failed, "받았던 빈 목록도 마지막 조회가 실패면 '없음'이라 말하지 않는다")
        #expect(K.placeholder(hasRows: false, hasLoaded: false, lastFailed: true) == .failed)
        #expect(K.placeholder(hasRows: false, hasLoaded: false, lastFailed: false) == .loading)
        #expect(!K.knowsCount(hasRows: false, hasLoaded: false, lastFailed: true))
        #expect(K.knowsCount(hasRows: false, hasLoaded: true, lastFailed: false))
    }

    @Test("아바타 크기 규칙: 기본 글자에서 그대로 · 작은 글자에서 줄지 않음 · 큰 글자에서 1.5배 상한")
    func avatarScaleRule() {
        #expect(MobileAvatarScale.side(base: 48, textScale: 1) == 48)
        #expect(MobileAvatarScale.side(base: 48, textScale: 0.82) == 48, "작은 글자에서 아바타를 줄였다")
        #expect(MobileAvatarScale.side(base: 40, textScale: 1.2) == 48)
        #expect(MobileAvatarScale.side(base: 48, textScale: 2.76) == 72, "AX3 상한")
        #expect(MobileAvatarScale.side(base: 64, textScale: 3.5) == 96)
    }

    // MARK: - 게임 탭(medium)

    @Test("게임 허브 카드: 순위표를 못 불러왔으면 '오늘 기록 없음' 대신 실패 · 모르면 불러오는 중 · 알고 없으면 기록 없음")
    func hubCardSaysFailureNotEmpty() {
        var board = GamesMiniGameBoard()
        board.failed = true
        #expect(GamesText.todayLine(best: nil, rank: nil, board: board) == GamesText.recordLoadFailed)
        #expect(GamesText.todayLine(best: nil, rank: nil, board: GamesMiniGameBoard()) == GamesMiniGameText.loadingCaption)
        board = GamesMiniGameBoard()
        board.loaded = true
        #expect(GamesText.todayLine(best: nil, rank: nil, board: board) == GamesMiniGameText.noRankToday)
        board.failed = true
        #expect(GamesText.todayLine(best: 12, rank: 2, board: board) == "오늘 최고 12점 · 2위", "내 줄을 알면 실패여도 그대로")
        // 미니게임 화면 머리 줄: 순위표를 모르면 "오늘 기록 없음"을 그리지 않는다(아래 카드가 실패를 말한다).
        #expect(GamesMiniGameText.rankLine(nil, knowsBoard: false) == nil)
        #expect(GamesMiniGameText.rankLine(nil, knowsBoard: true) == GamesMiniGameText.noRankToday)
        #expect(GamesMiniGameText.rankLine(3, knowsBoard: false) == "오늘 3위")
        // 오목 카드: 받은함을 못 불러왔으면 "상대를 골라…"(= 받은 게 없다)로 접지 않는다. 진행 판·받은 신청이 있으면 그것이 먼저.
        #expect(GamesText.gomokuLine(incoming: 0, hasActiveMatch: false, hasOutgoing: false, inboxFailed: true) == GamesText.inboxLoadFailed)
        #expect(GamesText.gomokuLine(incoming: 0, hasActiveMatch: false, hasOutgoing: false) == "상대를 골라 대결을 신청해요")
        #expect(GamesText.gomokuLine(incoming: 2, hasActiveMatch: false, hasOutgoing: false, inboxFailed: true) == "받은 신청 2건")
        #expect(GamesText.gomokuLine(incoming: 0, hasActiveMatch: true, hasOutgoing: false, inboxFailed: true) == "진행 중인 대국이 있어요")
    }

    @Test("오목 받은함: 오프라인·거절이면 실패 깃발(받은 적 없음) · 성공하면 내린다 · 로그아웃이 비운다 — 로비 화면은 그 깃발로 실패를 그린다")
    func gomokuInboxFailureIsRemembered() async {
        let harness = GamesHarness(label: "int-fix-inbox")
        let mode = BaseLockedBox(0)
        let nowMs = harness.serverNowMs
        harness.server.setDefault("gomoku_inbox") { _ in
            switch mode.get() {
            case 0: return .networkFailure()
            case 1: return .json(GamesGomokuJSON.inbox(nowMs: nowMs))
            default: return .json(#"{"status":"unauthorized"}"#)
            }
        }
        await harness.signIn()
        let gomoku = harness.gomoku

        await gomoku.loadInbox()
        #expect(await baseWaitUntil { gomoku.inboxLoadFailed }, "오프라인 받은함 실패를 기억하지 않았다 — 화면이 '받은 신청이 없어요'라 말한다")
        #expect(!gomoku.hasLoadedInbox && gomoku.incoming.isEmpty)
        #expect(MobileLoadKnowledge.placeholder(hasRows: false, hasLoaded: gomoku.hasLoadedInbox, lastFailed: gomoku.inboxLoadFailed) == .failed)

        mode.mutate { $0 = 1 }
        await gomoku.loadInbox()
        #expect(await baseWaitUntil { gomoku.hasLoadedInbox && !gomoku.inboxLoadFailed }, "성공한 받은함이 실패 깃발을 내리지 않았다")
        #expect(MobileLoadKnowledge.placeholder(hasRows: false, hasLoaded: gomoku.hasLoadedInbox, lastFailed: gomoku.inboxLoadFailed) == .empty)

        mode.mutate { $0 = 2 }
        await gomoku.loadInbox()
        #expect(await baseWaitUntil { gomoku.inboxLoadFailed }, "거절 응답(unauthorized)을 '받은 신청 없음'으로 믿었다")

        gomoku.reset()
        #expect(!gomoku.inboxLoadFailed && !gomoku.hasLoadedInbox, "로그아웃이 받은함 깃발을 남겼다")
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    @Test("게임 허브 순위: 첫 화면 요약 조회가 오프라인이면 두 게임 보드 모두 실패로 남고 카드 줄은 실패 문구다")
    func hubSummaryOffline() async {
        let harness = GamesHarness(label: "int-fix-hub")
        harness.server.setDefault("minigame_board") { _ in .networkFailure() }
        await harness.signIn()
        harness.games.hubDidAppear()
        for kind in MiniGameKind.allCases {
            #expect(await baseWaitUntil { harness.hub.boards[kind]?.failed == true && harness.hub.boards[kind]?.loading == false })
            let board = harness.hub.boards[kind] ?? GamesMiniGameBoard()
            #expect(!board.knowsPlayerCount)
            #expect(GamesText.todayLine(best: harness.hub.myTodayBest(kind), rank: harness.hub.myRank(kind), board: board) == GamesText.recordLoadFailed)
        }
        #expect(harness.violations.isEmpty)
        await harness.tearDown()
    }

    // MARK: - 순위 탭(low)

    @Test("순위 탭 미니게임: 조회 실패면 사람 수를 모른다(정족수 줄 없음) · 성공한 빈 판이면 0명을 안다 — 게임 탭과 같은 규칙")
    func rankingsMiniGameQuorumNeedsKnowledge() async {
        let mode = BaseLockedBox(0)
        let harness = await RankMeHarness(label: "int-fix-rank-quorum") { request in
            guard request.rpcName == "minigame_board" else { return nil }
            return mode.get() == 0 ? .networkFailure() : .json("[]")
        }
        defer { harness.tearDown() }
        let store = harness.rankings
        await store.loadMiniGame()
        #expect(store.miniGameState.hasFailed && store.miniGamePlayers == 0)
        #expect(!store.knowsMiniGamePlayerCount, "실패로 0 인 값을 '오늘은 아직 아무도 안 했어요'로 말한다")

        mode.mutate { $0 = 1 }
        await store.loadMiniGame()
        #expect(store.miniGameState.hasLoaded && store.knowsMiniGamePlayerCount)

        // 두 탭이 같은 규칙을 쓰는지(같은 입력 → 같은 답).
        var board = GamesMiniGameBoard()
        board.loaded = store.miniGameState.hasLoaded
        board.failed = store.miniGameState.hasFailed
        #expect(board.knowsPlayerCount == store.knowsMiniGamePlayerCount)
        harness.expectNoForbiddenCalls()
    }

    // MARK: - 나 탭 제보 초점(low)

    @Test("제보 딥링크가 같은 제보를 또 가리키면 초점 순번이 오른다(떠 있는 제보 화면이 펼치고 스크롤할 계기) · 로그아웃은 0")
    func feedbackFocusSerialBumpsOnEveryOpen() async {
        let harness = await RankMeHarness(label: "int-fix-feedback-focus") { _ in nil }
        defer { harness.tearDown() }
        let me = harness.me
        let before = me.feedbackFocusSerial
        me.open(.feedback(reportID: "fb02"))
        #expect(me.focusedReportID == "fb02" && me.feedbackFocusSerial == before + 1)
        me.open(.feedback(reportID: "fb02"))
        #expect(me.feedbackFocusSerial == before + 2, "같은 id 로 다시 열면 화면이 깨어날 계기가 없다(목록도 같으면 onChange 가 오지 않는다)")
        me.open(.settings)
        #expect(me.feedbackFocusSerial == before + 2)
        me.reset()
        #expect(me.feedbackFocusSerial == 0 && me.focusedReportID == nil)
    }

    // MARK: - 소스 계약(디자인 일관성)

    @Test("화면 계약: 게임 허브·오목 로비는 실패 깃발을 읽는다 · 순위 탭 정족수 줄은 '아는가'를 본다 · 제보 화면은 초점 순번을 본다")
    func viewsReadFailureAndFocus() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesTab.swift")
        #expect(tab.contains("board: hub.boards[kind]"), "허브 카드 줄이 순위표 상태를 보지 않는다")
        #expect(tab.contains("inboxFailed: gomoku.inboxLoadFailed"), "허브 오목 카드가 받은함 실패를 보지 않는다")
        let lobby = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuScreen.swift")
        #expect(lobby.contains("hasLoaded: gomoku.hasLoadedInbox, lastFailed: gomoku.inboxLoadFailed"), "받은 신청 절이 받은함 실패를 보지 않는다")
        #expect(lobby.contains("hasLoaded: gomoku.hasLoadedLobby, lastFailed: gomoku.lobbyLoadFailed"), "대결 중 절이 로비 실패를 보지 않는다")
        let screen = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift")
        #expect(screen.contains("knowsBoard:"), "미니게임 머리 줄이 순위표를 모르는 채 '오늘 기록 없음'을 그린다")
        let rankings = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift")
        #expect(rankings.contains("store.knowsMiniGamePlayerCount ?"), "순위 탭 정족수 줄이 '아는가'를 보지 않는다")
        let feedback = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeFeedbackView.swift")
        #expect(feedback.contains(".onChange(of: store.feedbackFocusSerial)"), "제보 화면이 초점 순번을 보지 않는다(떠 있는 화면에서 알림을 눌러도 안 펼친다)")
    }

    @Test("디자인 계약: [다시 시도]는 공용 부품 하나(44pt · 한 문구) · `.bordered` 캡슐 없음 · 순위 원 색은 한 곳 · 아바타를 탭이 따로 키우지 않는다")
    func designConsistencyContracts() throws {
        let retryLiterals = try IntegrationContractTests.files(containing: ["\"다시 시도\"", "\"다시 불러오기\""], under: "Sources/CheckMobileKit")
        #expect(retryLiterals == ["Sources/CheckMobileKit/Components/MobileComponentRules.swift"], "재시도 문구가 공용 상수 밖에 흩어졌다: \(retryLiterals)")
        let connectionLiterals = try IntegrationContractTests.files(containing: ["연결을 확인하고 다시 시도해 주세요", "네트워크를 확인하고"], under: "Sources/CheckMobileKit")
        #expect(connectionLiterals == ["Sources/CheckMobileKit/Components/MobileComponentRules.swift"], "연결 안내 문장이 탭마다 갈렸다: \(connectionLiterals)")
        let bordered = try IntegrationContractTests.files(containing: [".buttonStyle(.bordered)"], under: "Sources/CheckMobileKit")
        #expect(bordered.isEmpty, "`.bordered` 캡슐(약 32~35pt)이 남았다: \(bordered)")
        let components = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/MobileComponents.swift")
        #expect(components.contains("static let minimumTarget: CGFloat = 44"))
        #expect(components.contains("frame(minWidth: Self.minimumTarget, minHeight: Self.minimumTarget)"), "보조 버튼 캡슐이 44pt 를 보장하지 않는다")
        // 실패 행을 쓰는 탭(대조: 공용 부품이 실제로 쓰인다).
        let failureRows = try IntegrationContractTests.files(containing: ["LoadFailureRow("], under: "Sources/CheckMobileKit")
        for folder in ["Now", "Rankings", "Me", "Games"] {
            #expect(failureRows.contains { $0.hasPrefix("Sources/CheckMobileKit/\(folder)/") }, "\(folder) 탭이 공용 실패 행을 쓰지 않는다")
        }

        let medalDefinitions = try IntegrationContractTests.files(containing: ["Color(red: 1.00, green: 0.824"], under: "Sources/CheckMobileKit")
        #expect(medalDefinitions == ["Sources/CheckMobileKit/Components/MobileRankComponents.swift"], "메달 색 정의가 두 벌이다: \(medalDefinitions)")
        for file in ["Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift", "Sources/CheckMobileKit/Rankings/RankingsTab.swift"] {
            let code = try IntegrationContractTests.code(file)
            #expect(code.contains("RankBadge"), "\(file) 가 공용 순위 원을 쓰지 않는다")
            #expect(code.contains("rankRowSurface(isMine:"), "\(file) 가 공용 내 행 강조를 쓰지 않는다")
        }

        let scaledAvatars = try IntegrationContractTests.files(containing: ["@ScaledMetric(relativeTo: .body) private var size", "var avatarSize: CGFloat = "], under: "Sources/CheckMobileKit")
            .filter { path in
                (try? IntegrationContractTests.code(path))?.range(of: #"@ScaledMetric[^\n]*(avatarSize|var size)"#, options: .regularExpression) != nil
            }
        #expect(scaledAvatars.isEmpty, "탭이 아바타를 제 @ScaledMetric 으로 따로 키운다: \(scaledAvatars)")
    }

    @Test("카드 조각 자리: 한 행이면 단독 · 첫·가운데·끝 — 위는 단독·첫만, 아래는 단독·끝만 둥글다")
    func cardSegmentPositions() {
        #expect(CardSegmentPosition.of(index: 0, count: 1) == .single)
        #expect(CardSegmentPosition.of(index: 0, count: 0) == .single)
        #expect(CardSegmentPosition.of(index: 0, count: 3) == .first)
        #expect(CardSegmentPosition.of(index: 1, count: 3) == .middle)
        #expect(CardSegmentPosition.of(index: 2, count: 3) == .last)
        #expect(CardSegmentPosition.of(index: 0, count: 2) == .first && CardSegmentPosition.of(index: 1, count: 2) == .last)
        #expect(CardSegmentPosition.single.roundsTop && CardSegmentPosition.single.roundsBottom)
        #expect(CardSegmentPosition.first.roundsTop && !CardSegmentPosition.first.roundsBottom)
        #expect(!CardSegmentPosition.middle.roundsTop && !CardSegmentPosition.middle.roundsBottom)
        #expect(!CardSegmentPosition.last.roundsTop && CardSegmentPosition.last.roundsBottom)
    }

    @Test("카드 모양 계약: 지금·메시지 목록은 시스템 절 모양(insetGrouped 행 배경) 대신 AingCard 와 같은 카드 조각을 그린다")
    func listTabsDrawAingCardSegments() throws {
        for file in ["Sources/CheckMobileKit/Now/NowTab.swift", "Sources/CheckMobileKit/Now/NowTodoSection.swift", "Sources/CheckMobileKit/Messages/MessagesTab.swift"] {
            let code = try IntegrationContractTests.code(file)
            #expect(!code.contains(".listRowBackground(MobileTheme.card)"), "\(file) 가 시스템 절 모양(모서리 약 18~21pt · 테두리 없음)으로 카드를 그린다")
            #expect(code.contains(".cardSegmentRow("), "\(file) 가 카드 조각을 쓰지 않는다")
        }
        #expect(!(try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTodoSection.swift")).contains("DisclosureGroup("),
                "시스템 DisclosureGroup 은 펼친 줄의 자리를 몰라 카드 조각이 끊긴다")
        let segment = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/MobileCardSegment.swift")
        #expect(segment.contains("MobileTheme.cardRadius") && segment.contains(".stroke(MobileTheme.separator, lineWidth: 1)"),
                "카드 조각이 AingCard 토큰(반경 · 1px 선)을 쓰지 않는다")
    }
}
