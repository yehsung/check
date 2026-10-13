@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰에서 **끝난 판이 남아 결과 화면이 다시 서던** 결함의 못(0.3.50 수리의 폰 몫 · 2026-10-13 신고).
//
// ── 무엇이 틀렸었나 ──
// 폰의 두 수명 훅(`GamesStore.gomokuScreenDidDisappear` · `chessScreenDidDisappear`)은 `stopWatching()` →
// `windowDidHide()` 만 불렀다. 그런데 폰에서 화면을 떠나는 것은 맥의 '최소화'가 아니라 **'창을 정말 닫았다'**다.
// 코어는 두 뜻을 일부러 갈라 두었고(`windowDidHide` = 최소화도 지나는 문 · `windowDidClose` = "그만 본다"),
// **끝난 판을 접는 일은 닫기 쪽에만 있다**(`GomokuStore.windowDidClose` · `ChessStore.windowDidClose` → `foldFinishedMatch`).
// 그 문을 한 번도 안 불렀으므로 결과 화면에서 [뒤로] 로 나가도 끝난 판이 그대로 남아, 게임 탭에서 오목·체스를
// 다시 누르면 **로비가 아니라 그 결과 화면이 다시 섰다**([로비로] 를 눌러야만 빠져나왔다). 오목은 그 위에
// 자기모순까지 있었다 — 서버에는 `gomoku_leave` 로 "나갔다"고 말하면서 화면은 그 판을 들고 있었다.
//
// ── 무엇을 재는가 ──
// "훅을 불렀나"가 아니라 **"다시 열면 로비가 서나"** 다(증상이 그것이므로). 넷을 나란히 잰다:
//  ① 끝난 판 → 떠남 → 다시 열기 → `phase == .lobby`(오목·체스 둘 다). 기준선은 **같은 상태에서 `windowDidClose()`
//     만 안 부른 하네스**이고, 그쪽은 결과 화면이 그대로 남는다 — 안 갈리면 ①의 초록은 아무것도 증명하지 않는다.
//  ② **진행 중인 내 판은 같은 왕복에서 살아남는다.** 이것이 없으면 "다 접어 버리기"로 ①을 통과시킬 수 있고,
//     그러면 떠나 있는 사이 대국이 죽는다(`GamesStore.swift` 머리말 · 두 훅 주석의 당부).
//  ③ 떠나는 길에서 **조회가 한 건도 안 나간다** — `leaveWatch()`(로비·받은함·순위를 다시 읽는 네트워크 호출)가
//     끼어들지 않았다는 뜻이다. 대조군으로 **같은 상태에서 `leaveWatch()` 를 부르면** 그 조회들이 나가는 것을
//     나란히 둔다(저장소 메모 '비교 기준선이 달라야 한다').
//     ※ 오목의 `gomoku_leave` **한 건은 예외이고 예전부터 있던 것**이다 — `windowDidHide` 가 결과 화면인 채로
//       떠난 판에서 나가는 쓰기이고(조회가 아니다), `leftMatchIDs` 가 판마다 한 번으로 묶으므로 접기가
//       같은 자리를 또 불러도 요청은 늘지 않는다. 그 "늘지 않는다"도 여기서 센다.
//
// 관례는 같은 폴더(`GamesGomokuWatchExitTests`·`GamesChessWiringTests`) 그대로다: `GamesHarness`(스텁 서버·
// 조작 시계·임시 저장소) · 테스트 하나 몫의 대기 예산 · 끝에서 폰 금지 호출 0건.

@MainActor
@Suite(.serialized) struct GamesStoreCloseTests {
    /// 이 테스트 하나 몫의 대기 예산(까닭은 `GamesWaitBudget`).
    private let waits = GamesWaitBudget()

    // MARK: - 픽스처

    private nonisolated static let gomokuOverID = "m-close-over"
    private nonisolated static let gomokuLiveID = "m-close-live"
    private nonisolated static let chessOverID = "c-close-over"
    private nonisolated static let chessLiveID = "c-close-live"
    private nonisolated static let chessRival = "p-close-rival"

    /// 빈 오목 순위표. 로비를 보는 순간 `spectatorWindowDidShow` 가 한 번 읽으므로 안 걸어 두면 그 조회가
    /// 실패로 접히며 아래 요청 수 측정 창에 늦게 끼어든다(오목 관전 테스트와 같은 까닭).
    private nonisolated static func gomokuRankingJSON(nowMs: Int) -> String {
        #"{"status":"ok","server_now_ms":\#(nowMs),"record_since_ms":null,"me":null,"rows":[]}"#
    }

    private nonisolated static func chessRankingJSON(nowMs: Int) -> String {
        #"{"status":"ok","server_now_ms":\#(nowMs),"record_since_ms":null,"me":null,"rows":[]}"#
    }

    /// `chess_lobby` 한 벌. `active_match_id` 를 걸면 "서버도 그 판이 진행 중이라고 말한다"가 된다.
    private nonisolated static func chessLobbyJSON(nowMs: Int, activeMatchID: String? = nil) -> String {
        let active = activeMatchID.map { "\"\($0)\"" } ?? "null"
        return #"{"status":"ok","server_now_ms":\#(nowMs),"stakes":[3,5,10],"initial_ms":600000,"increment_ms":3000,"grace_ms":2000,"invite_ttl_seconds":60,"ruby_balance":100,"me":{"ruby_balance":100,"wins":2,"losses":1,"draws":0,"active_match_id":\#(active),"outgoing_match_id":null,"incoming_match_id":null},"users":[],"matches":[]}"#
    }

    /// `chess_state` 한 벌(나는 백). 끝난 판은 `turn_started_ms`·`deadline_ms`·`in_check` 가 null 이다 — 서버 계약 그대로다
    /// (`Sources/CheckMobileKit/Demo/Fixtures/games/rpc.chess_state@demo-chess-mate-win.json` 의 실측 모양).
    private nonisolated static func chessStateJSON(nowMs: Int, matchID: String, finished: Bool) -> String {
        let status = finished ? "finished" : "active"
        let result = finished ? #""white_win""# : "null"
        let reason = finished ? #""resign""# : "null"
        let winner = finished ? #""\#(GamesHarness.userID)""# : "null"
        let deadline = finished ? "null" : "\(nowMs + 588_000)"
        let turnStarted = finished ? "null" : "\(nowMs - 2_000)"
        let inCheck = finished ? "null" : "false"
        let opponent = #"{"user_id":"\#(chessRival)","display_name":"체스라이벌","avatar_url":null,"character":null,"center":"seoul"}"#
        let match = #"{"id":"\#(matchID)","status":"\#(status)","stake":5,"white":"\#(GamesHarness.userID)","black":"\#(chessRival)","ply_count":0,"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","turn":"white","white_ms_left":600000,"black_ms_left":600000,"white_grace_ms":2000,"black_grace_ms":2000,"increment_ms":3000,"turn_started_ms":\#(turnStarted),"deadline_ms":\#(deadline),"started_ms":\#(nowMs - 30_000),"result":\#(result),"end_reason":\#(reason),"winner":\#(winner),"draw_offer_by":null}"#
        return #"{"status":"ok","server_now_ms":\#(nowMs),"match":\#(match),"moves":[],"my_color":"white","opponent":\#(opponent),"ruby_balance":100,"in_check":\#(inCheck),"legal_moves":null}"#
    }

    /// 오목 화면이 부르는 조회들 + 나가기 쓰기를 걸어 둔다. `activeID` 는 로비·받은함이 말하는 진행 중 판이다.
    private func serveGomoku(_ harness: GamesHarness, state: String, activeID: String? = nil) {
        let nowMs = harness.serverNowMs
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs, active: activeID))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs, active: activeID))
        harness.server.setDefault("gomoku_ranking", json: Self.gomokuRankingJSON(nowMs: nowMs))
        harness.server.setDefault("gomoku_leave", json: #"{"status":"ok","both_left":false}"#)
        harness.server.setDefault("gomoku_state", json: state)
    }

    /// 체스 화면이 부르는 조회들을 걸어 둔다(체스에는 나가기 쓰기가 없다 — `chess_leave` 가 없다).
    private func serveChess(_ harness: GamesHarness, state: String, activeID: String? = nil) {
        let nowMs = harness.serverNowMs
        harness.server.setDefault("chess_lobby", json: Self.chessLobbyJSON(nowMs: nowMs, activeMatchID: activeID))
        harness.server.setDefault("chess_ranking", json: Self.chessRankingJSON(nowMs: nowMs))
        harness.server.setDefault("chess_state", json: state)
        // 게임 탭 허브가 함께 부르는 오목 조회(체스만 보는 테스트에서도 나간다).
        harness.server.setDefault("gomoku_inbox", json: GamesGomokuJSON.inbox(nowMs: nowMs))
        harness.server.setDefault("gomoku_lobby", json: GamesGomokuJSON.lobby(nowMs: nowMs))
    }

    private nonisolated static func gomokuState(_ json: String) throws -> GomokuStatePayload {
        try JSONDecoder.gamesSnake.decode(GomokuStateResponse.self, from: Data(json.utf8)).state
    }

    private nonisolated static func chessState(_ json: String) throws -> ChessStatePayload {
        try JSONDecoder.gamesSnake.decode(ChessStateResponse.self, from: Data(json.utf8)).state
    }

    // MARK: - 1. 끝난 판을 들고 떠났다 → 다시 열면 로비다 (오목)

    @Test("오목: 결과 화면에서 [뒤로] 뒤에 오목을 다시 열면 **로비**가 선다 — 끝난 판이 남으면 결과가 다시 선다")
    func reopeningGomokuAfterAFinishedMatchLandsInTheLobby() async throws {
        // 없으면: 신고 그대로다 — 결과 화면에서 나갔는데 게임 탭에서 오목을 누르면 그 결과가 다시 서고
        // [로비로] 를 눌러야만 빠져나온다. 고치는 자리는 폰 배선 한 줄(`windowDidClose()`)이고,
        // **그 줄을 지워도 빨개지는 테스트가 이것 말고는 없다**(그래서 이 결함이 지금까지 살아 있었다).
        let harness = GamesHarness(label: "close-gomoku-over")
        let overJSON = GamesGomokuJSON.state(nowMs: harness.serverNowMs, matchID: Self.gomokuOverID,
                                            finished: true, moves: [("black", "H8"), ("white", "I9")])
        serveGomoku(harness, state: overJSON)
        await harness.signIn()

        harness.games.gomokuScreenDidAppear()
        #expect(await waits.wait { harness.gomoku.hasLoadedLobby }, "로비 조회가 안 닿았다 — 손짓 자체가 안 걸렸다")
        harness.gomoku.applyState(try Self.gomokuState(overJSON))
        #expect(harness.gomoku.phase == .result, "픽스처가 결과 화면을 못 세웠다 — 아래 단언은 기준선 없이 초록이다")
        #expect(harness.gomoku.match?.id == Self.gomokuOverID)
        #expect(harness.gomoku.match?.isFinished == true)

        // [뒤로] → 게임 탭에서 오목을 다시 누른다.
        harness.games.gomokuScreenDidDisappear()
        #expect(harness.gomoku.match == nil, "떠나는 길에서 끝난 판이 안 접혔다 — windowDidClose() 를 안 불렀다")
        harness.games.gomokuScreenDidAppear()
        await harness.barrier()
        await baseYield(turns: 12)
        await harness.barrier()
        #expect(harness.gomoku.phase == .lobby,
                "다시 열었더니 로비가 아니라 \(harness.gomoku.phase) 다 — 끝난 판이 남아 결과 화면이 다시 섰다")
        #expect(harness.gomoku.match == nil, "끝난 판이 되살아났다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // ★ 기준선: **같은 상태**에서 `windowDidClose()` 만 안 부르면(= 수리 한 줄을 지운 것) 결과 화면이 그대로 남는다.
        //   안 갈리면 위 초록은 코어가 알아서 접는다는 뜻이고 폰 배선을 하나도 재지 않는다.
        let bare = GamesHarness(label: "close-gomoku-bare")
        let bareJSON = GamesGomokuJSON.state(nowMs: bare.serverNowMs, matchID: Self.gomokuOverID,
                                             finished: true, moves: [("black", "H8"), ("white", "I9")])
        serveGomoku(bare, state: bareJSON)
        await bare.signIn()
        bare.games.gomokuScreenDidAppear()
        #expect(await waits.wait { bare.gomoku.hasLoadedLobby })
        bare.gomoku.applyState(try Self.gomokuState(bareJSON))
        #expect(bare.gomoku.phase == .result)
        bare.gomoku.stopWatching()
        bare.gomoku.windowDidHide()          // = 폰 훅에서 windowDidClose() 를 지운 것
        #expect(bare.gomoku.phase == .result,
                "기준선이 안 갈린다 — 코어 windowDidHide 가 이미 끝난 판을 접는다면 위 단언은 배선을 재지 않는다")
        #expect(bare.gomoku.match?.id == Self.gomokuOverID)
        await bare.tearDown()
    }

    // MARK: - 2. 끝난 판을 들고 떠났다 → 다시 열면 로비다 (체스)

    @Test("체스: 결과 화면에서 [뒤로] 뒤에 체스를 다시 열면 **로비**가 선다 — 오목과 같은 결함이었다")
    func reopeningChessAfterAFinishedMatchLandsInTheLobby() async throws {
        // 없으면: 오목과 같은 증상이 체스에도 그대로 있다(체스 훅은 오목 훅을 본보기로 만들어 같은 구멍을 물려받았다).
        let harness = GamesHarness(label: "close-chess-over")
        let overJSON = Self.chessStateJSON(nowMs: harness.serverNowMs, matchID: Self.chessOverID, finished: true)
        serveChess(harness, state: overJSON)
        await harness.signIn()

        harness.games.chessScreenDidAppear()
        #expect(await waits.wait { harness.model.chess.hasLoadedLobby }, "로비 조회가 안 닿았다")
        harness.model.chess.applyState(try Self.chessState(overJSON))
        #expect(harness.model.chess.phase == .result, "픽스처가 결과 화면을 못 세웠다")
        #expect(harness.model.chess.match?.id == Self.chessOverID)
        #expect(harness.model.chess.match?.isFinished == true)

        harness.games.chessScreenDidDisappear()
        #expect(harness.model.chess.match == nil, "떠나는 길에서 끝난 판이 안 접혔다 — windowDidClose() 를 안 불렀다")
        harness.games.chessScreenDidAppear()
        await harness.barrier()
        await baseYield(turns: 12)
        await harness.barrier()
        #expect(harness.model.chess.phase == .lobby,
                "다시 열었더니 로비가 아니라 \(harness.model.chess.phase) 다 — 끝난 판이 남아 결과 화면이 다시 섰다")
        #expect(harness.model.chess.match == nil, "끝난 판이 되살아났다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // ★ 기준선: 같은 상태에서 `windowDidClose()` 만 안 부르면 결과 화면이 그대로 남는다.
        let bare = GamesHarness(label: "close-chess-bare")
        let bareJSON = Self.chessStateJSON(nowMs: bare.serverNowMs, matchID: Self.chessOverID, finished: true)
        serveChess(bare, state: bareJSON)
        await bare.signIn()
        bare.games.chessScreenDidAppear()
        #expect(await waits.wait { bare.model.chess.hasLoadedLobby })
        bare.model.chess.applyState(try Self.chessState(bareJSON))
        #expect(bare.model.chess.phase == .result)
        bare.model.chess.stopWatching()
        bare.model.chess.windowDidHide()     // = 폰 훅에서 windowDidClose() 를 지운 것
        #expect(bare.model.chess.phase == .result,
                "기준선이 안 갈린다 — 코어 windowDidHide 가 이미 끝난 판을 접는다면 위 단언은 배선을 재지 않는다")
        #expect(bare.model.chess.match?.id == Self.chessOverID)
        await bare.tearDown()
    }

    // MARK: - 3. ★ 진행 중인 내 판은 같은 왕복에서 살아남는다

    @Test("진행 중인 내 판은 화면을 떠났다 돌아와도 **그대로**다 — 끝난 판을 접는 수리가 대국까지 접지 않았다(오목·체스)")
    func aRunningMatchSurvivesTheSameRoundTrip() async throws {
        // ★ 이것이 없으면 "들고 있는 판을 다 접어 버리기"로 위 두 테스트를 통과시킬 수 있다. 그러면 탭을 옮긴
        //   사이 대국이 화면에서 사라지고(서버 시계는 계속 흐른다) 판돈째 시간패한다 — 두 훅 주석과
        //   `GamesStore.swift` 머리말이 되풀이해 당부하는 바로 그 사고다.
        //   가드는 코어 안에 있다(`windowDidClose` 의 `isFinished` 가름 · `foldFinishedMatch` 의 첫 줄).
        //   이 테스트는 **폰 배선이 그 가드를 우회하지 않았다**를 잰다.
        let harness = GamesHarness(label: "close-gomoku-live")
        let liveJSON = GamesGomokuJSON.state(nowMs: harness.serverNowMs, matchID: Self.gomokuLiveID,
                                             moves: [("black", "H8"), ("white", "I9")])
        serveGomoku(harness, state: liveJSON, activeID: Self.gomokuLiveID)
        await harness.signIn()
        harness.gomoku.applyState(try Self.gomokuState(liveJSON))
        #expect(harness.gomoku.match?.id == Self.gomokuLiveID, "픽스처가 진행 중인 판을 못 세웠다")
        #expect(harness.gomoku.match?.isFinished == false)
        #expect(harness.gomoku.phase == .playing)

        harness.games.gomokuScreenDidAppear()
        #expect(await waits.wait { harness.gomoku.hasLoadedLobby })
        harness.games.gomokuScreenDidDisappear()
        #expect(harness.gomoku.match?.id == Self.gomokuLiveID, "떠나는 길이 진행 중인 내 판을 접었다")
        harness.games.gomokuScreenDidAppear()
        await harness.barrier()
        await baseYield(turns: 12)
        await harness.barrier()
        #expect(harness.gomoku.match?.id == Self.gomokuLiveID,
                "화면을 떠났다 돌아왔더니 진행 중인 내 판이 사라졌다 — 떠나 있는 사이 대국이 죽는다")
        #expect(harness.gomoku.match?.isFinished == false)
        #expect(harness.gomoku.phase == .playing, "진행 중인 판인데 로비로 떨어졌다")
        #expect(harness.server.requests("gomoku_leave").isEmpty,
                "진행 중인 내 판에서 나가 버렸다 — 결과 화면일 때만 나가는 것이 코어 규칙이다")
        #expect(harness.violations.isEmpty, "\(harness.violations)")
        await harness.tearDown()

        // 체스도 같다. 체스에는 `chess_leave` 가 없으니 재는 것은 "판이 그대로 있나" 하나다.
        let chessHarness = GamesHarness(label: "close-chess-live")
        let chessLive = Self.chessStateJSON(nowMs: chessHarness.serverNowMs, matchID: Self.chessLiveID, finished: false)
        serveChess(chessHarness, state: chessLive, activeID: Self.chessLiveID)
        await chessHarness.signIn()
        chessHarness.model.chess.applyState(try Self.chessState(chessLive))
        #expect(chessHarness.model.chess.match?.id == Self.chessLiveID, "픽스처가 진행 중인 판을 못 세웠다")
        #expect(chessHarness.model.chess.match?.isFinished == false)
        #expect(chessHarness.model.chess.phase == .playing)

        chessHarness.games.chessScreenDidAppear()
        #expect(await waits.wait { chessHarness.model.chess.hasLoadedLobby })
        chessHarness.games.chessScreenDidDisappear()
        #expect(chessHarness.model.chess.match?.id == Self.chessLiveID, "떠나는 길이 진행 중인 내 판을 접었다")
        chessHarness.games.chessScreenDidAppear()
        await chessHarness.barrier()
        await baseYield(turns: 12)
        await chessHarness.barrier()
        #expect(chessHarness.model.chess.match?.id == Self.chessLiveID,
                "화면을 떠났다 돌아왔더니 진행 중인 내 판이 사라졌다 — 서버 시계는 그동안에도 흐른다")
        #expect(chessHarness.model.chess.match?.isFinished == false)
        #expect(chessHarness.model.chess.phase == .playing, "진행 중인 판인데 로비로 떨어졌다")
        #expect(chessHarness.violations.isEmpty, "\(chessHarness.violations)")
        await chessHarness.tearDown()
    }

    // MARK: - 4. ★ 떠나는 길에서 조회는 0건 — `leaveWatch()` 를 부른 대조군과 나란히

    @Test("떠나는 길에서 **조회는 0건**이다(오목은 예전부터 있던 gomoku_leave 한 건뿐) — 같은 상태에서 leaveWatch() 는 조회를 쏜다")
    func theExitPathIssuesNoQueries() async throws {
        // 없으면: 끝난 판을 접는 자리를 `backToLobby()`·`leaveWatch()` 로 바꿔 놓아도 위 테스트들이 전부 초록이다.
        // 그 둘은 로비·받은함·순위를 **다시 읽는다** — 화면을 떠나는 길에서 조회 셋이 나간다(무료 플랜 · `GamesStore` 당부).
        // `windowDidClose()` 는 조회를 쏘지 않는다(다음에 화면을 여는 `openWindow` 가 읽는다).
        let harness = GamesHarness(label: "close-gomoku-quiet")
        let overJSON = GamesGomokuJSON.state(nowMs: harness.serverNowMs, matchID: Self.gomokuOverID,
                                             finished: true, moves: [("black", "H8"), ("white", "I9")])
        serveGomoku(harness, state: overJSON)
        await harness.signIn()
        harness.games.gomokuScreenDidAppear()
        #expect(await waits.wait { harness.gomoku.hasLoadedLobby })
        #expect(await waits.wait { harness.gomoku.hasLoadedRanking }, "순위 한 번 읽기가 측정 창에 늦게 끼어든다")
        harness.gomoku.applyState(try Self.gomokuState(overJSON))
        #expect(harness.gomoku.phase == .result)

        // 사건 장벽: 이미 떠난 요청·늦은 응답을 먼저 흘려보낸다(오목 관전 테스트와 같은 관례).
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        let lobbyBefore = harness.server.requests("gomoku_lobby").count
        let inboxBefore = harness.server.requests("gomoku_inbox").count
        let rankingBefore = harness.server.requests("gomoku_ranking").count
        let before = harness.server.requests.count

        harness.games.gomokuScreenDidDisappear()
        await harness.barrier()
        await baseYield(turns: 12)
        await harness.barrier()
        #expect(harness.server.requests("gomoku_lobby").count == lobbyBefore,
                "떠나는 길에서 로비를 다시 읽었다 — leaveWatch()·backToLobby() 가 끼어들었다")
        #expect(harness.server.requests("gomoku_inbox").count == inboxBefore, "떠나는 길에서 받은함을 다시 읽었다")
        #expect(harness.server.requests("gomoku_ranking").count == rankingBefore, "떠나는 길에서 순위를 다시 읽었다")
        // 나간 것은 **쓰기 한 건**(`gomoku_leave`)뿐이다 — 결과 화면인 채로 떠난 판에서 나가는, 예전부터 있던 호출이다.
        let extra = harness.server.requests.dropFirst(before).map(GamesStubServer.key)
        #expect(extra == ["gomoku_leave"], "떠나는 길에서 나간 요청이 gomoku_leave 한 건이 아니다: \(extra)")
        // 접기가 같은 자리를 또 부르지만 `leftMatchIDs` 가 판마다 한 번으로 묶으므로 요청은 늘지 않는다.
        #expect(harness.server.requests("gomoku_leave").count == 1,
                "같은 판에서 두 번 나갔다: \(harness.server.requests("gomoku_leave").count)건")
        // 두 번 불려도 멱등이다(SwiftUI 가 onDisappear 를 겹쳐 부를 수 있다).
        harness.games.gomokuScreenDidDisappear()
        await harness.barrier()
        await baseYield(turns: 8)
        await harness.barrier()
        #expect(harness.server.requests.dropFirst(before).map(GamesStubServer.key) == ["gomoku_leave"],
                "두 번째 호출이 요청을 냈다")

        // ★ 대조군: **같은 하네스·같은 자리**에서 `leaveWatch()` 를 부르면 조회가 나간다. 기준선이 안 갈리면
        //   위 0건은 아무것도 증명하지 않는다(스텁이 조용한 것일 수도 있다).
        let lobbyQuiet = harness.server.requests("gomoku_lobby").count
        let inboxQuiet = harness.server.requests("gomoku_inbox").count
        harness.gomoku.leaveWatch()
        #expect(await waits.wait { harness.server.requests("gomoku_lobby").count > lobbyQuiet },
                "대조군이 조회를 안 냈다 — 이 측정은 leaveWatch 를 가릴 수 없다")
        #expect(await waits.wait { harness.server.requests("gomoku_inbox").count > inboxQuiet })
        await harness.tearDown()

        // 체스: `chess_leave` 가 없으니 떠나는 길의 요청은 **정확히 0건**이다.
        let chessHarness = GamesHarness(label: "close-chess-quiet")
        let chessOver = Self.chessStateJSON(nowMs: chessHarness.serverNowMs, matchID: Self.chessOverID, finished: true)
        serveChess(chessHarness, state: chessOver)
        await chessHarness.signIn()
        chessHarness.games.chessScreenDidAppear()
        #expect(await waits.wait { chessHarness.model.chess.hasLoadedLobby })
        #expect(await waits.wait { chessHarness.model.chess.hasLoadedRanking })
        chessHarness.model.chess.applyState(try Self.chessState(chessOver))
        #expect(chessHarness.model.chess.phase == .result)
        await chessHarness.barrier()
        await baseYield(turns: 8)
        await chessHarness.barrier()
        let chessBefore = chessHarness.server.requests.count

        chessHarness.games.chessScreenDidDisappear()
        await chessHarness.barrier()
        await baseYield(turns: 12)
        await chessHarness.barrier()
        let chessExtra = chessHarness.server.requests.dropFirst(chessBefore).map(GamesStubServer.key)
        #expect(chessExtra.isEmpty, "체스가 떠나는 길에서 요청을 냈다: \(chessExtra)")

        // ★ 대조군: 같은 자리에서 `leaveWatch()` 는 로비·순위를 다시 읽는다.
        let chessLobbyQuiet = chessHarness.server.requests("chess_lobby").count
        let chessRankingQuiet = chessHarness.server.requests("chess_ranking").count
        chessHarness.model.chess.leaveWatch()
        #expect(await waits.wait { chessHarness.server.requests("chess_lobby").count > chessLobbyQuiet },
                "대조군이 조회를 안 냈다 — 이 측정은 leaveWatch 를 가릴 수 없다")
        #expect(await waits.wait { chessHarness.server.requests("chess_ranking").count > chessRankingQuiet })
        await chessHarness.tearDown()
    }

    // MARK: - 5. 소스 계약 (두 훅이 그 문을 실제로 부르는가)

    @Test("두 수명 훅이 **windowDidClose() 를 부른다** — windowDidHide() 뒤이고, leaveWatch() 는 여전히 안 부른다")
    func bothLifecycleHooksCallWindowDidClose() throws {
        // 값으로 재는 쪽은 위 넷이다. 이 테스트는 그 값이 **우연히** 맞는 경우(코어가 언젠가 `windowDidHide`
        // 에서도 끝난 판을 접게 바뀌는 날)에도 순서 계약이 남아 있게 못을 박는다. 순서를 맥과 같게 두는 까닭:
        // 맥 창 배선도 `notifyVisibility(false)` → `notifyClosed()` 다(`CheckGomokuWindow`·`CheckChessWindow`).
        let code = try Self.strippedSource("Sources/CheckMobileKit/Games/GamesStore.swift")
        for hook in ["func gomokuScreenDidDisappear", "func chessScreenDidDisappear"] {
            let body = try #require(Self.slice(code, from: hook, length: 460), "\(hook) 를 못 찾았다")
            let hide = try #require(body.range(of: "windowDidHide()"), "\(hook): windowDidHide() 가 없다")
            let close = try #require(body.range(of: "windowDidClose()"),
                                     "\(hook): windowDidClose() 를 안 부른다 — 끝난 판이 남아 결과 화면이 다시 선다")
            #expect(hide.upperBound < close.lowerBound,
                    "\(hook): windowDidClose() 가 windowDidHide() 앞에 있다 — 맥 창 배선과 순서가 어긋난다")
            #expect(!body.contains("leaveWatch"), "\(hook): 떠나는 길에서 leaveWatch() 를 부른다 — 조회가 나간다")
            #expect(!body.contains("backToLobby"), "\(hook): 떠나는 길에서 backToLobby() 를 부른다 — 조회가 나간다")
        }
        // background 는 **가림**이다 — 거기서 닫으면 알림 하나 읽고 온 사람의 끝난 판·관전이 사라진다.
        let background = try #require(Self.slice(code, from: "func appDidEnterBackground", length: 1_100))
        #expect(!background.contains("windowDidClose"),
                "background 가 창을 닫았다 — 잠깐 나간 것이 '그만 본다'가 된다(최소화는 닫기가 아니다)")
    }

    // MARK: - 소스 읽기 도우미 (관례는 `GamesChessWiringTests` 그대로)

    /// 저장소 파일 한 벌을 **주석을 걷어내고** 돌려준다(저장소 메모 '소스 계약 테스트는 주석을 걷어내야 한다').
    static func strippedSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        let raw = try String(contentsOf: url, encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// `needle` 뒤 `length` 글자(없으면 nil).
    static func slice(_ source: String, from needle: String, length: Int) -> String? {
        guard let hit = source.range(of: needle) else { return nil }
        return String(source[hit.upperBound...].prefix(length))
    }
}
