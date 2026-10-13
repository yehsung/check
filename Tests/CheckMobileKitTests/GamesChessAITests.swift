@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 "로봇과 두기"(체스 AI) — 가장 작은 레인이지만 **비로그인 사용자의 유일한 체스 길**이다(인수인계 §6 ⑫ · §7).
// 규칙·판·시계·AI 는 전부 코어이고 맥 스위트(V034x)가 지킨다 — 여기서 재는 것은 **폰이 더한 것**뿐이다:
//  ① 세션이 nil 인데도 입구가 열리고 판이 시작되고 수가 들어간다(서버 요청 0건)
//  ② 흑을 고르면 판이 뒤집힌다(`whiteAtBottom == false`) — 그 값은 한 자리에서만 나온다
//  ③ 승격은 도착 칸이 같은 합법 수가 **넷일 때만** 시트를 띄운다(하나면 안 띄우고 그대로 나간다)
//  ④ 판돈 0 · 루비 이동 0 · 체스 RPC 0건(요청이 나가면 빨강) — 세는 눈이 멀지 않았음을 **대조군**으로 함께 보인다
//  ⑤ 로봇 수에 애니메이션(`ChessStore.flight`)이 붙는다 — 화면이 창 가시성을 켜야 붙는다(기준선이 갈린다)
//  ⑥ 로봇 판 중 PvP — **판정만** 적는다(고치지 않는다, 다른 레인·통합 단계와 겹친다)
//  ⑦ 소스 계약: 뷰 구역에 로그인 게이트·뒤집기 산술·`ChessRules`·판돈이 **없다**
//
// 폰 뷰(`#if os(iOS)`)는 맥 스위트가 못 본다 — 그래서 판정은 전부 플랫폼 무관 표(`GamesChessAIChrome`)에 있고
// 뷰는 그 표만 읽는다. 뷰 자체의 그물은 `ios/scripts/build-sim.sh` 다.

// MARK: - 도우미

private func sq(_ notation: String) -> ChessSquare { ChessSquare(notation)! }

/// 체스 RPC 열한 개(이 중 **하나라도** 나가면 로봇 판이 서버를 탄 것이다).
private let chessRPCs: Set<String> = [
    "chess_lobby", "chess_challenge", "chess_cancel", "chess_respond", "chess_move", "chess_resign",
    "chess_offer_draw", "chess_respond_draw", "chess_state", "chess_ranking", "chess_watch"
]

/// 요청이 **나갈 수 있는** 체스 스토어 하나(host 가 붙어 있다 · 조작 시계 · 결정적 로봇).
/// host 를 nil 로 두면 "요청 0건" 은 아무것도 증명하지 않는다(기준선이 같은 입력이면 그 시험은 영원히 초록).
@MainActor
private func makeChessStore(_ harness: GamesHarness) -> ChessStore {
    let chess = ChessStore(host: harness.model.gomokuHost)
    let clock = harness.clock
    chess.clock = { clock.now }
    chess.aiRuntime.minimumThinkSeconds = 0
    // 결정적 로봇: 합법 수 목록의 첫 수(`ChessRules.legalMoves` 의 순서는 결정적이다 — 코어 대체 수와 같은 규칙).
    chess.aiMoveChooser = { position, _ in ChessRules.legalMoves(in: position).first }
    return chess
}

/// 로봇 판 하나를 띄울 수 있는 스토어 + 스텁 서버.
@MainActor
private func chessHarness(_ label: String, signedIn: Bool) async -> (GamesHarness, ChessStore) {
    let harness = GamesHarness(label: label)
    if signedIn { await harness.signIn() }
    return (harness, makeChessStore(harness))
}

@MainActor
private func tearDown(_ harness: GamesHarness, _ chess: ChessStore) async {
    chess.reset()
    await harness.tearDown()
}

/// ★ **배선 레인**(로비·입구)이 켜 주는 깃발 한 줄. 이 화면 파일은 켜지 않는다(`GamesStore` 는 그쪽 소유다).
/// 기본값이 꺼짐이라 켜지 않으면 `beginFlight` 가 맨 앞에서 막아 **로봇 수가 안 미끄러지고**, 로컬 시계도 멈춘 채다.
/// 거절이 의도된 동작이라 켜지 않은 시험은 초록이다 — 그래서 애니메이션 시험이 두 갈래를 **둘 다** 잰다.
@MainActor
private func wiringMadeScreenVisible(_ chess: ChessStore) {
    chess.isWindowVisible = true
}

/// 사람이 판을 두 번 누른다(화면이 누르는 문 그대로 — `GamesChessBoard.onTapSquare` → `store.tap`).
@MainActor
private func play(_ chess: ChessStore, _ from: String, _ to: String) async {
    await chess.tap(sq(from))
    await chess.tap(sq(to))
}

private func chessRequestNames(_ harness: GamesHarness) -> [String] {
    harness.server.requests.compactMap { $0.rpcName }.filter { chessRPCs.contains($0) }
}

// MARK: - ① 로그인을 보지 않는다

@MainActor
@Suite(.serialized)
struct GamesChessAISignedOutTests {
    @Test("비로그인에서 입구가 열리고 로봇 판이 돌아간다 — 서버는 한 번도 안 탄다")
    func robotGameRunsWithoutSession() async {
        // 없으면: 입구나 화면을 로그인 뒤로 숨겨도 **전부 초록**이다(로봇 판은 서버를 안 타므로 요청 시험이
        // 막힌 길도 통과시킨다). 비로그인 사용자의 유일한 체스 길이 조용히 막힌다 — §6 ⑫.
        let (harness, chess) = await chessHarness("chess-ai-anon", signedIn: false)
        #expect(harness.model.session.isSignedIn == false, "세션이 없어야 이 시험이 뜻을 갖는다")
        #expect(GamesChessAIChrome.requiresSignIn == false, "기본값도 값으로 — 이 한 줄이 레인의 계약이다")

        wiringMadeScreenVisible(chess)
        var chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.canStart, "비로그인인데 입구가 닫혔다")
        #expect(chrome.stage == .colorPick)
        // 막는 사유 한 줄도 **문구 표를 지난다**(`robotEntryBlock`). 로그인은 사유가 아니므로 최악의 값을
        // 넣어도 nil 이어야 한다 — 그 함수가 세션으로 가르기 시작하면 여기서 빨개진다.
        #expect(chrome.blockReason == nil, "비로그인이 입구를 막는 사유로 쓰였다")

        chess.startAIMatch(humanColor: .white)
        chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.stage == .playing, "색을 고르면 **바로** 판이 선다(확인 단계 없음)")
        #expect(chrome.board != nil)
        #expect(chess.match?.plyCount == 0)

        await play(chess, "e2", "e4")
        #expect(chess.match?.plyCount == 1, "비로그인 사용자의 수가 판에 들어가야 한다")
        #expect(await baseWaitUntil { chess.match?.plyCount == 2 }, "로봇이 답하지 않았다")
        #expect(chess.match?.turn == .white, "로봇이 둔 뒤 다시 사람 차례다")

        #expect(chessRequestNames(harness).isEmpty, "로봇 판이 서버를 탔다: \(chessRequestNames(harness))")
        await tearDown(harness, chess)
    }

    @Test("비로그인 로봇 판은 기권·다시 두기·로비로까지 요청 0건")
    func robotGameLifecycleSendsNothing() async {
        let (harness, chess) = await chessHarness("chess-ai-anon-life", signedIn: false)
        wiringMadeScreenVisible(chess)
        chess.startAIMatch(humanColor: .white)
        await play(chess, "e2", "e4")
        _ = await baseWaitUntil { chess.match?.plyCount == 2 }

        await chess.resign()                                   // [기권]
        #expect(GamesChessAIChrome(store: chess).stage == .result)
        #expect(chess.match?.outcome == .lost)
        chess.restartAIMatch()                                 // [다시 두기]
        #expect(GamesChessAIChrome(store: chess).stage == .playing)
        #expect(chess.match?.plyCount == 0)
        await chess.resign()
        chess.backToLobby()                                    // [그만두기]
        #expect(GamesChessAIChrome(store: chess).stage == .colorPick)
        #expect(GamesChessAIChrome(store: chess).canStart, "끝난 판을 치웠으면 입구가 다시 열린다")

        #expect(chessRequestNames(harness).isEmpty, "요청이 나갔다: \(chessRequestNames(harness))")
        await tearDown(harness, chess)
    }
}

// MARK: - ②③④⑤ 판·승격·판돈·애니메이션

@MainActor
@Suite(.serialized)
struct GamesChessAIBoardTests {
    @Test("흑을 고르면 판이 뒤집히고 로봇이 먼저 둔다")
    func choosingBlackFlipsTheBoard() async {
        // 기준선을 갈라 둔다 — 백·흑 둘 다 재지 않으면 `whiteAtBottom` 을 상수 true 로 박아도 초록이다.
        let (harness, white) = await chessHarness("chess-ai-black", signedIn: false)
        wiringMadeScreenVisible(white)
        white.startAIMatch(humanColor: .white)
        #expect(GamesChessAIChrome(store: white).board?.whiteAtBottom == true)
        #expect(white.match?.turn == .white, "사람이 백이면 사람이 먼저다")

        let chess = makeChessStore(harness)                     // 판 둘을 섞지 않게 스토어를 따로 세운다
        wiringMadeScreenVisible(chess)
        chess.startAIMatch(humanColor: .black)
        let chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.board?.whiteAtBottom == false, "흑으로 두는 사람의 판이 뒤집히지 않았다")
        #expect(chrome.humanColor == .black)
        #expect(await baseWaitUntil { chess.match?.plyCount == 1 }, "로봇(백)이 먼저 두지 않았다")
        #expect(chess.match?.turn == .black)
        #expect(chessRequestNames(harness).isEmpty)
        white.reset()
        await tearDown(harness, chess)
    }

    @Test("판 인자는 스토어가 쥔 한 칸만 읽는다 — 고른 칸·갈 수 있는 칸")
    func boardInputReadsTheStoreSelection() async {
        // §6 ② — 로봇 판은 로컬 규칙이, 1:1 은 서버가 `legalMoves` 를 채운다. 화면은 어느 쪽인지 모른 채
        // `selection.targets` 한 칸만 읽는다. 뷰가 스스로 합법 수를 만들면 1:1 에서 서버와 갈린다.
        let (harness, chess) = await chessHarness("chess-ai-select", signedIn: false)
        wiringMadeScreenVisible(chess)
        chess.startAIMatch(humanColor: .white)

        await chess.tap(sq("e2"))                               // 말을 고른다(한 단째)
        let chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.board?.selection == sq("e2"))
        #expect(chrome.board?.legalTargets == chess.selection?.targets)
        #expect(chrome.board?.legalTargets == Set([sq("e3"), sq("e4")]))
        #expect(chrome.board?.isMyTurn == true)
        await tearDown(harness, chess)
    }

    /// 체크는 **판에서 보여야 하는 정보**다. 로봇 판의 체크 깃발은 **코어**(`ChessAIGame`)가 주고, 화면은
    /// 그 깃발이 참일 때 배치에서 왕 칸을 읽는다 — 합법 수를 만들어 왕을 찾지 않는다(§6 ②).
    @Test("판 인자가 체크 받은 왕의 칸을 싣는다 — 체크가 아니면 nil(실제 체크를 둬서 가른다)")
    func boardInputCarriesTheCheckedKingSquare() async {
        // 없으면: 로봇 판에서 문구만 "체크예요" 라고 말하고 판에는 표시가 없다.
        let (harness, chess) = await chessHarness("chess-ai-check", signedIn: false)
        wiringMadeScreenVisible(chess)
        // 백 룩 e5 · 흑 왕 e8 · e 열이 열려 있다. 아직은 **체크가 아니다**(룩이 d5 에 있다).
        let position = ChessPosition(fen: "4k3/8/8/3R4/8/8/8/4K3 w - - 0 1")!
        let game = ChessAIGame(humanColor: .white, position: position, now: harness.clock.now)
        chess.aiGame = game
        chess.match = game.matchState()
        chess.phase = .playing
        #expect(GamesChessAIChrome(store: chess).board?.checkSquare == nil,
                "체크가 아닌데 덮개 칸이 선다 — 기준선이 안 갈린다")

        // 룩을 d5 → e5 로 옮기면 **흑이 체크**다. 코어가 깃발을 세우고 화면 표가 왕 칸을 싣는다.
        await play(chess, "d5", "e5")
        #expect(await baseWaitUntil { chess.match?.isInCheck == true }, "코어가 체크 깃발을 안 세웠다")
        let chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.isInCheck, "표의 체크 깃발이 꺼져 있다")
        #expect(chrome.board?.checkSquare == sq("e8"),
                "체크인데 흑 왕 칸이 안 선다(\(chrome.board?.checkSquare?.notation ?? "없음"))")
        #expect(chessRequestNames(harness).isEmpty, "로봇 판이 서버를 탔다: \(chessRequestNames(harness))")
        await tearDown(harness, chess)
    }

    @Test("승격은 합법 수가 넷일 때만 시트를 띄운다 — 하나면 그대로 나간다")
    func promotionAsksOnlyWhenFourMovesShareTheTarget() async {
        // §6 ⑩. 기준선을 갈라 둔다: **같은 판에서** 폰 승격(넷)과 왕 이동(하나)을 둘 다 눌러 본다 —
        // 승격만 재면 "언제나 묻는다"도, 평수만 재면 "한 번도 안 묻는다"도 초록이다.
        let (harness, chess) = await chessHarness("chess-ai-promo", signedIn: false)
        wiringMadeScreenVisible(chess)
        let position = ChessPosition(fen: "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1")!
        let game = ChessAIGame(humanColor: .white, position: position, now: harness.clock.now)
        chess.aiGame = game
        chess.match = game.matchState()
        chess.phase = .playing
        #expect(GamesChessAIChrome(store: chess).stage == .playing)

        // (가) 평수 — 왕 e1→e2: 합법 수가 하나다 → 묻지 않고 그대로 나간다.
        await play(chess, "e1", "e2")
        #expect(GamesChessAIChrome(store: chess).promotion == nil, "평수에 승격 시트가 떴다")
        #expect(await baseWaitUntil { chess.match?.plyCount == 2 }, "로봇이 답하지 않았다")

        // (나) 승격 — 폰 b7→b8: 같은 칸으로 가는 합법 수가 넷이다 → 그때만 네 말을 묻는다.
        await play(chess, "b7", "b8")
        let prompt = GamesChessAIChrome(store: chess).promotion
        #expect(prompt != nil, "승격인데 묻지 않았다")
        #expect(prompt?.from == sq("b7"))
        #expect(prompt?.to == sq("b8"))
        #expect(prompt?.choices == [.queen, .rook, .bishop, .knight])
        let plyBefore = chess.match?.plyCount ?? -1
        #expect(plyBefore == 2, "고르기 전에는 수가 **나가지 않는다**")

        await chess.choosePromotion(.knight)                    // 시트에서 나이트를 골랐다
        #expect(chess.match?.plyCount == plyBefore + 1)
        #expect(chess.match?.position?[sq("b8")]?.kind == .knight, "고른 말이 아니라 다른 말이 섰다")
        #expect(GamesChessAIChrome(store: chess).promotion == nil)
        #expect(chessRequestNames(harness).isEmpty)
        await tearDown(harness, chess)
    }

    @Test("판돈 0 · 루비 이동 0 · 체스 RPC 0건 — 그리고 세는 눈은 멀지 않았다")
    func robotGameTouchesNoRubyAndNoRanking() async {
        // ★ 대조군이 이 시험의 절반이다: 같은 스텁·같은 세는 눈으로 **요청 한 건을 실제로 잡아** 보인 뒤에만
        //   "0건" 이 뜻을 갖는다(host 를 안 붙이거나 RPC 이름이 틀렸으면 0 은 언제나 0 이다).
        let (harness, chess) = await chessHarness("chess-ai-ruby", signedIn: true)
        wiringMadeScreenVisible(chess)
        // ★ 기준선을 **로그인 뒤**에 뜬다(통합): 배선 레인이 로그인·활성 때 `chess_lobby` 를 한 번 당기므로
        //   (`GamesStore.appDidBecomeActive`·`hubDidAppear` — 한 사람 한 판이 그 조회에 달려 있다)
        //   스텁 서버의 누적 건수는 0 이 아니다. 이 시험이 재는 것은 **로봇 판이 내는 요청**이고,
        //   그것은 이 스토어의 몫이라 '여기서부터의 증가분' 으로 세야 뜻이 맞는다.
        //   그 한 건이 **비동기**로 날아가므로 먼저 가라앉힌다(안 가라앉으면 기준선 뒤에 떨어져 이 시험이
        //   로봇 판 탓으로 읽는다). 30초 스로틀이라 뒤따르는 건은 없고, 혹시 안 와도 기준선이 0 인 채로 맞다.
        _ = await baseWaitUntil { harness.server.requests("chess_lobby").count >= 1 }
        let rpcBaseline = chessRequestNames(harness)
        let lobbyBaseline = harness.server.requests("chess_lobby").count
        chess.rubyBalance = 500
        harness.model.gomokuHost.rubyBalance = 500
        #expect(chess.spectatorFeaturesEnabled == false, "순위·관전 주 스위치는 꺼짐이 기본값이다")

        chess.startAIMatch(humanColor: .white)
        await play(chess, "e2", "e4")
        _ = await baseWaitUntil { chess.match?.plyCount == 2 }
        await play(chess, "d2", "d4")
        _ = await baseWaitUntil { chess.match?.plyCount == 4 }

        let chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.matchStake == 0, "로봇 판에 판돈이 붙었다")
        #expect(GamesChessAIChrome.stake == 0)
        #expect(GamesChessAIChrome.entersRanking == false)
        #expect(chess.rubyBalance == 500, "루비가 움직였다")
        #expect(harness.model.gomokuHost.rubyBalance == 500, "호스트 루비 미러가 움직였다")
        #expect(chess.match?.rubyDelta == nil, "진행 중 판에 루비 변화가 적혔다")
        #expect(chessRequestNames(harness) == rpcBaseline,
                "로봇 판이 요청을 냈다: \(chessRequestNames(harness).dropFirst(rpcBaseline.count))")

        // 대조군 — 같은 세는 눈이 체스 요청을 **잡는다**(로비 조회는 로비 레인의 문이다).
        await chess.refreshLobby()
        #expect(harness.server.requests("chess_lobby").count == lobbyBaseline + 1,
                "세는 눈이 멀었다 — 증가 0 은 아무것도 증명하지 않는다")
        #expect(harness.server.requests("chess_ranking").isEmpty, "주 스위치가 꺼졌는데 순위를 당겼다")
        await tearDown(harness, chess)
    }

    @Test("로봇 수에 애니메이션이 붙는다 — 화면이 보이지 않으면 안 붙는다")
    func robotMoveSlidesOnlyWhileTheScreenIsVisible() async {
        // §5 — `ChessStore.flight` 는 `commitAIGame` 깔때기에 이미 붙어 있고 **스토어를 건드리지 않는다**.
        // 다만 `beginFlight` 의 거절 ①이 "창이 안 보인다" 라서, 화면이 가시성을 켜지 않으면 폰에서는
        // 애니메이션이 **한 번도** 안 뜬다(그리고 그래도 테스트는 초록이다 — 그래서 기준선을 갈라 둔다).
        let (harness, hidden) = await chessHarness("chess-ai-flight", signedIn: false)

        // (가) 기준선 — 가시성을 켜지 않은 판: 날 것이 없다.
        hidden.startAIMatch(humanColor: .white)
        await play(hidden, "e2", "e4")
        #expect(await baseWaitUntil { hidden.match?.plyCount == 2 })
        #expect(hidden.flight == nil, "안 보이는 화면을 60fps 로 깨웠다")
        hidden.reset()

        // (나) 화면이 나타난 뒤의 같은 수: 로봇 수가 미끄러진다.
        let chess = makeChessStore(harness)
        wiringMadeScreenVisible(chess)
        chess.startAIMatch(humanColor: .white)
        await play(chess, "e2", "e4")
        #expect(await baseWaitUntil { chess.match?.plyCount == 2 })
        let flight = chess.flight
        #expect(flight != nil, "로봇 수가 순간이동했다")
        #expect(flight?.matchID == chess.match?.id)
        #expect(flight?.ply == 2)
        #expect(chessRequestNames(harness).isEmpty)
        await tearDown(harness, chess)
    }
}

// MARK: - 결과 문구 (로봇 판 표 · FIDE 6.9)

@MainActor
@Suite(.serialized)
struct GamesChessAIResultTextTests {
    /// 끝난 로봇 판 하나를 시계로 세운다(사람이 백 · 로봇이 흑). `flagged` 쪽의 깃발이 떨어진다.
    @MainActor
    private static func finishedByFlag(_ harness: GamesHarness, fen: String) -> ChessStore {
        let chess = makeChessStore(harness)
        let position = ChessPosition(fen: fen)!
        let game = ChessAIGame(humanColor: .white, position: position, initialMs: 1_000,
                               incrementMs: 0, now: harness.clock.now)
        chess.aiGame = game
        chess.match = game.matchState()
        chess.phase = .playing
        chess.handleAIClock(now: harness.clock.now.addingTimeInterval(2))
        return chess
    }

    @Test("결과 이유는 로봇 판 표를 쓴다 — 1인칭 표의 '상대' 문장이 아니다")
    func resultUsesTheRobotEndReasonTable() async {
        // 표가 셋이다(`endReason` 1인칭 · `robotEndReason` 로봇 · `watchEndReason` 관전). 1인칭 표는 루비와
        // "상대" 를 말하므로 로봇 판에 쓰면 **없는 루비 변화**와 없는 사람을 말한다. 두 표가 **갈리는 경우**로
        // 재야 한다 — 로봇이 시간을 다 쓴 판(내가 이김)에서 두 문장이 다르다.
        let harness = GamesHarness(label: "chess-ai-robot-text")
        // 흑(로봇) 차례인데 깃발이 떨어진다. 백은 K+Q 라 메이트할 기물이 있다 → 백(사람) 승.
        let chess = Self.finishedByFlag(harness, fen: "4k3/8/8/8/8/8/3Q4/4K3 b - - 0 1")
        let chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.stage == .result)
        #expect(chrome.outcome == .won)
        #expect(chrome.endReason == .timeout)
        #expect(chrome.endReasonLine == ChessPhoneText.robotEndReason(.timeout, outcome: .won))
        #expect(chrome.endReasonLine != ChessPhoneText.endReason(.timeout, outcome: .won),
                "1인칭 표를 쓰고 있다 — 로봇 판에 '상대' 가 나온다")
        #expect(!chrome.endReasonLine.contains("상대"), "로봇 판에 '상대' 어휘가 나왔다")
        #expect(!chrome.endReasonLine.contains("루비"), "판돈이 없는 판이 루비를 말했다")
        chess.reset()
        await harness.tearDown()
    }

    @Test("FIDE 6.9 — 시간이 다 됐는데도 무승부라고 말한다")
    func fideSixNineSaysDraw() async {
        // §6 ③ — 깃발이 떨어진 쪽이 져야 할 것 같지만, 남은 쪽에 메이트할 기물이 없으면 **무승부**다.
        // 코어가 판정하고(사유 `timeout_insufficient`) 화면은 **문구만** 그 경우를 말한다. 기준선이 갈린다:
        // 같은 '시간 초과' 인데 위 시험은 패·승을, 이 시험은 무승부를 말해야 한다.
        let harness = GamesHarness(label: "chess-ai-fide69")
        // 백(사람) 차례인데 깃발이 떨어진다. 흑은 왕뿐이라 메이트할 수 없다 → 무승부.
        let chess = Self.finishedByFlag(harness, fen: "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1")
        let chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.endReason == .timeoutInsufficient, "코어가 FIDE 6.9 로 판정해야 한다")
        #expect(chrome.outcome == .draw, "2배 승리가 아니라 무승부다")
        #expect(chrome.endReasonLine.contains("무승부"), "시간이 다 됐는데 무승부라고 말하지 않았다")
        #expect(chrome.endReasonLine != ChessPhoneText.robotEndReason(.timeout, outcome: .draw),
                "timeout 과 같은 문장으로 접혔다 — 돌려받은 루비를 잃은 것으로 읽힌다")
        #expect(ChessPhoneText.outcomeTitle(chrome.outcome) == "무승부예요")
        chess.reset()
        await harness.tearDown()
    }
}

// MARK: - ⑥ 로봇 판 중 PvP (판정만 — 고치지 않는다)

@MainActor
@Suite(.serialized)
struct GamesChessAIVersusPvPTests {
    private static func peer() -> ChessUser {
        ChessUser(id: "7f3c1e2a-0000-4000-8000-0000000000aa", displayName: "상대", avatarURL: nil,
                  characterID: "fox", isWorking: true, isCapable: true, inMatch: false)
    }

    private static func pvpMatch(now: Date) -> ChessMatchState {
        ChessMatchState(
            id: "7f3c1e2a-0000-4000-8000-000000000001", stake: 3, myColor: .white, opponent: peer(),
            fen: ChessPosition.standard.fen, position: .standard, plyCount: 0, turn: .white, lastMove: nil,
            moves: [], clock: ChessServerClock(whiteMsLeft: ChessClock.initialMs, blackMsLeft: ChessClock.initialMs,
                                               incrementMs: 3_000, turnStartedAt: now, running: .white),
            isInCheck: false, legalMoves: [], isFinished: false, outcome: nil, endReason: nil,
            rubyDelta: nil, drawOfferBy: nil, drawOfferedByMe: false)
    }

    @Test("한 사람 한 판은 **한 방향만** 걸린다 — 1:1 판이 서면 로봇 판은 말없이 사라진다")
    func pvpSilentlyWinsOverTheRobotGame() async {
        // ⑥ 판정(고치지 않는다 — 다른 레인·통합 단계와 겹친다). 서버 `chess__busy` 는 `chess_matches` ·
        // `gomoku_matches` 만 본다(duel.sql:1088) — **로봇 판은 서버에 없어 보이지 않는다.** 그래서:
        //   · 로봇 판 중에도 남이 나를 신청할 수 있고, 내가 수락하면 1:1 판이 선다.
        //   · 그 순간 코어 `match` 관찰자가 로봇 판을 **조용히** 버린다(ChessStore.swift:655 `discardAIGame`).
        //     문구도 확인도 없다 — 두던 판이 그냥 없어진다(걸린 루비가 0 이라 돈은 잃지 않는다).
        //   · 반대 방향은 막혀 있다: 1:1 판·보낸 신청이 있으면 `canStartAIMatch` 가 false 다.
        let (harness, chess) = await chessHarness("chess-ai-pvp", signedIn: true)
        wiringMadeScreenVisible(chess)
        chess.startAIMatch(humanColor: .white)
        await play(chess, "e2", "e4")
        _ = await baseWaitUntil { chess.match?.plyCount == 2 }
        #expect(chess.aiGame != nil)

        // 신청을 수락하면 서버가 이 판을 내려 준다(`applyState` 가 하는 일을 한 줄로 세운다).
        chess.match = Self.pvpMatch(now: harness.clock.now)
        #expect(chess.aiGame == nil, "1:1 판이 섰는데 로봇 판이 남았다")
        #expect(chess.notice == nil, "판정: 로봇 판이 사라진 것을 **알리는 문구가 없다**")
        let chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.stage == .colorPick, "로봇 화면은 색 고르기로 되돌아간다")
        #expect(chrome.canStart == false, "1:1 판 중에는 로봇 판을 새로 열 수 없다(반대 방향은 막혀 있다)")
        #expect(chrome.blocked == .playing, "판이 떠 있는데 다른 까닭을 고른다")
        #expect(chrome.blockReason == ChessPhoneText.robotEntryBlockNotice(.playing),
                "막힌 입구가 사유를 말해야 한다(문구 표의 양방향 표현 + 언제 풀리는지)")
        #expect(chrome.blockReason?.contains(ChessPhoneText.busyTitle(.chess)) == true)
        await tearDown(harness, chess)
    }

    @Test("로봇 판 중에 보내는 PvP 신청은 클라가 막지 않는다 — 요청이 그대로 나간다")
    func challengeDuringRobotGameIsNotBlockedByTheClient() async {
        // ⑥ 판정의 나머지 반쪽. `ChessStore.challenge` 에는 `isAIMatch` 가드가 없고 서버도 로봇 판을 모른다 —
        // 신청은 나가고 수락되면 위 시험의 길로 로봇 판이 사라진다. **고치지 않는다**(판정만): 막을 자리는
        // 로비 입구(다른 레인)이거나 "로봇 판을 먼저 끝내시겠어요?" 를 묻는 통합 단계다.
        let (harness, chess) = await chessHarness("chess-ai-challenge", signedIn: true)
        wiringMadeScreenVisible(chess)
        chess.startAIMatch(humanColor: .white)
        #expect(chess.isAIMatch)

        await chess.challenge(userID: Self.peer().id)
        #expect(harness.server.requests("chess_challenge").count == 1,
                "판정: 로봇 판 중에도 1:1 신청이 서버로 나간다(막는 자리가 없다)")
        await tearDown(harness, chess)
    }

    @Test("★ 신청만 보낸 사람은 '두는 중' 이라고 듣지 않는다 — 게이트는 그대로, **문구만** 갈린다")
    func anOutgoingInviteDoesNotClaimAGameIsBeingPlayed() async {
        // 헤드리스 실측 결함(D3): `canStartAIMatch` 의 다섯 조건을 깃발 하나로 접고 문구를 하나로 박아 둬서,
        // **보낸 신청만 있는 사람**이 "체스를 두는 중이에요" 를 들었다 — 두고 있지 않은 판을 두고 있다고
        // 듣고, 할 일(신청 취소)을 못 찾았다. 게이트는 고치지 않는다(신청이 수락되는 순간 1:1 이 로봇 판을
        // 이기므로 막는 것이 맞다) — 가르는 것은 문구뿐이다.
        let (harness, chess) = await chessHarness("chess-ai-outgoing", signedIn: true)
        wiringMadeScreenVisible(chess)

        // 보낸 신청만 있다 — 판은 없다(이것이 결함이 살던 자리다).
        chess.outgoing = ChessInvite(id: "7f3c1e2a-0000-4000-8000-0000000000b1", peer: Self.peer(),
                                     stake: 3, expiresAt: harness.clock.now.addingTimeInterval(60))
        #expect(chess.match == nil, "전제: 두는 판이 없어야 이 시험이 뜻을 갖는다")
        var chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.canStart == false, "게이트는 그대로다 — 보낸 신청이 있으면 로봇 판을 열지 않는다")
        #expect(chrome.blocked == .outgoingInvite, "보낸 신청을 '두는 중' 으로 접었다")
        let waiting = try! #require(chrome.blockReason)
        #expect(!waiting.contains(ChessPhoneText.busyTitle(.chess)),
                "두고 있지 않은 판을 두고 있다고 말한다: \(waiting)")
        #expect(waiting.contains("취소"), "취소하면 풀린다는 것을 말하지 않는다")
        // 같은 화면, **판이 서면** 말이 바뀐다(기준선이 달라야 한다 — 한 입력만 바꿔 비교한다).
        chess.outgoing = nil
        chess.match = Self.pvpMatch(now: harness.clock.now)
        chrome = GamesChessAIChrome(store: chess)
        #expect(chrome.blocked == .playing)
        #expect(chrome.blockReason?.contains(ChessPhoneText.busyTitle(.chess)) == true,
                "판이 떠 있는데 '두는 중' 이라고 말하지 않는다")
        #expect(chrome.blockReason != waiting, "두 까닭이 같은 말을 한다 — 가른 뜻이 없다")
        await tearDown(harness, chess)
    }
}

// MARK: - ⑦ 소스 계약 (뷰 구역)

@MainActor
@Suite(.serialized)
struct GamesChessAISourceContractTests {
    /// `GamesChessAIViews.swift` 의 **뷰 구역**(입구부터 끝까지) — 주석을 걷어낸다(안 걷으면 설명을 지워야
    /// 초록이 된다). 자리표시 블록은 입구보다 **앞**에 있어 이 구역에 들어오지 않는다(병합 때 지워질 코드다).
    static func viewRegion() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CheckMobileKit/Games/GamesChessAIViews.swift")
        let raw = try String(contentsOf: url, encoding: .utf8)
        let stripped = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
        guard let hit = stripped.range(of: "struct GamesChessAISection") else { return "" }
        return String(stripped[hit.lowerBound...])
    }

    @Test("뷰 구역에 로그인 게이트가 없다")
    func viewsHaveNoSignInGate() throws {
        let code = try Self.viewRegion()
        #expect(!code.isEmpty, "뷰 구역을 못 찾았다 — 이름이 바뀌었으면 이 시험을 먼저 고쳐라")
        #expect(!code.contains("session"), "로봇 판이 세션을 본다 — 비로그인 사용자의 체스 길이 막힌다(§6 ⑫)")
        #expect(!code.contains("isSignedIn"))
    }

    @Test("창 가시성은 이 화면이 켜지 않는다 — 배선 레인의 것이다")
    func viewsDoNotTouchWindowVisibility() throws {
        // 켜는 자리가 둘이 되면 통합에서 충돌한다(`GamesStore`·`MobileAppModel` 은 배선 레인 소유다).
        // 반대로 **아무도 안 켜면** 로봇 수가 안 미끄러지고 로컬 시계가 멈춘 채다 — 보고에 적은 인수 조건이다.
        let code = try Self.viewRegion()
        #expect(!code.contains("isWindowVisible"), "화면이 창 가시성을 켠다 — 배선 레인과 충돌한다")
        #expect(!code.contains("windowOcclusionDidChange"), "화면이 가림 통지를 흉내낸다(폴링까지 멈춘다)")
        #expect(!code.contains("windowDidShow"), "화면이 로비·판 재조회를 쏜다")
    }

    @Test("뒤집기는 한 자리만 지난다 — 뷰가 좌표를 다시 계산하지 않는다")
    func viewsDeriveOrientationOnlyOnce() throws {
        let code = try Self.viewRegion()
        let passes = code.components(separatedBy: "whiteAtBottom:").count - 1
        #expect(passes == 1, "판에 뒤집기를 넘기는 자리가 \(passes) 군데다 — 한 군데여야 한다(§6 ①·④)")
        // 체크 칸도 **표에서 받는다**(뷰가 nil 을 박으면 로봇 판만 체크가 안 보인다).
        #expect(code.contains("checkSquare: board.checkSquare"), "판에 체크 칸을 넘기지 않는다")
        // `myColor:` 를 **넘기는 것**(승격 시트의 인자)은 괜찮다 — 금지하는 것은 그 값에서 방향을 **다시 만드는** 것이다.
        #expect(!code.contains(".myColor"), "뷰가 판에서 내 색을 다시 읽는다 — 흑으로 두는 사람만 틀어진다")
        #expect(!code.contains("myColor =="), "뷰가 내 색으로 방향을 가른다")
        #expect(!code.contains("7 -"), "뷰에 칸 뒤집기 산술이 있다")
        #expect(!code.contains("file:"), "뷰가 칸 좌표를 만든다")
    }

    @Test("결과 문구는 1인칭 표를 부르지 않는다 — 파일 어디에도 없다")
    func fileNeverCallsTheFirstPersonEndReasonTable() throws {
        // 표가 셋이라 **부르는 이름 하나**로 갈린다(`robotEndReason`). 1인칭 표를 부르면 로봇 판이 루비·"상대"
        // 를 말한다 — 값 시험(`GamesChessAIResultTextTests`)과 짝으로 둬서 이름이 바뀌어도 한쪽이 잡는다.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CheckMobileKit/Games/GamesChessAIViews.swift")
        let raw = try String(contentsOf: url, encoding: .utf8)
        let stripped = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
        #expect(!stripped.contains("Text.endReason("), "1인칭 끝난 이유 표를 부른다")
        #expect(!stripped.contains("watchEndReason"), "관전 표를 부른다(로봇 판은 3인칭이 아니다)")
        #expect(stripped.contains("robotEndReason("), "로봇 판 표를 부르지 않는다")
    }

    @Test("뷰 구역이 합법 수를 만들지 않고 판돈을 그리지 않는다")
    func viewsNeitherComputeLegalMovesNorDrawStake() throws {
        let code = try Self.viewRegion()
        #expect(!code.contains("ChessRules"), "화면이 합법 수를 만든다 — 1:1 에서는 서버가 권위다(§6 ②)")
        #expect(!code.contains("stake"), "로봇 판에 판돈 줄이 있다(§7 — 판돈 없음)")
        #expect(!code.contains("ranking"), "로봇 판이 순위를 그린다(§7 — 순위에 안 들어감)")
        #expect(!code.contains("rubyDelta"), "로봇 판 결과에 루비 변화가 있다")
    }
}
