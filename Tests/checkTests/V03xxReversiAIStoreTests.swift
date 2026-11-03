import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 AI 연습 판 — 스토어 갈래(`ReversiStoreAI`) 계약. 갈래 C2. 하네스는 `V03xxReversiStoreTests.swift` 것을 쓴다.
//
// 판 규칙 자체(30초 자동 착수 · 연속 3회 패 · 자연 종료 우선 · 패스)는 `ReversiAIGameTests`(갈래 R)가 잰다. 여기서는 스토어가
// 그 판을 **어떻게 들고 있는가**만 본다: 서버로 한 건도 안 나가는가 · 창이 안 보이면 사람 시계가 멈추는가 · 사람이 패스하면
// AI 를 다시 부르는가 · 1:1 판이 서면 AI 판을 버리는가 · 미션 꼬리를 안 우는가.
//
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다.

/// 결정적 AI 선택기: 그 색의 합법 수 가운데 idx 가 가장 작은 것.
private let rvFirstLegal: ReversiAIMoveChooser = { board, color in
    ReversiRules.legalMoves(board, color: color).first
}

/// 영영 답하지 않는 선택기(AI 차례에서 판을 멈춰 두고 사람 시계·화면만 본다). 취소되면 nil.
private let rvNeverAnswers: ReversiAIMoveChooser = { _, _ in
    try? await Task.sleep(for: .seconds(3_600))
    return nil
}

@Suite("아잉 뒤집기 AI 판 — 스토어가 로컬 판을 들고 있는 법")
@MainActor
struct V03xxReversiAIStoreTests {

    @Test(.gomokuDefaultsCleanup)
    func ai_판은_서버로_한_건도_안_나간다() async throws {
        // 없으면: AI 판의 착수·기권·폴링·조회가 `reversi_move`·`reversi_state`·`reversi_resign` 으로 새도(없는 id 라 404 지만
        // 무료 플랜 요청이 샌다) 초록이다.
        let (store, host) = makeReversiStore("ai-offline", me: rvB, handler: rvHandler([
            "reversi_lobby": [try rvText("reversi_lobby__ok")],
            "reversi_move": [try rvText("reversi_move__ok")],
        ]))
        store.aiMoveChooser = rvFirstLegal
        store.isWindowVisible = true
        store.startAIMatch(humanColor: .black)
        let started = try #require(store.match)
        #expect(started.isAI)
        #expect(ReversiAIGame.isAIMatchID(started.id))
        #expect(store.phase == .playing)
        #expect(store.legalTargets == [19, 26, 37, 44])            // AI 판은 로컬 규칙
        await store.place(19)
        await rvWait { store.match?.isMyTurn == true && (store.match?.moveCount ?? 0) >= 2 }
        #expect(store.match?.moveCount == 2)                       // 사람 한 수 + AI 한 수
        await store.pollTick(at: Date().addingTimeInterval(3_600))
        await store.refreshMatch(id: started.id)
        await store.refreshMatch()
        store.handleSignal()                                        // AI 판 중의 신호는 로비로 본다
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") >= 1 }
        await store.resign()
        #expect(store.match?.isFinished == true)
        #expect(store.match?.endReason == .resign)
        #expect(store.match?.outcome == .lost)
        #expect(store.phase == .result)
        for rpc in ["reversi_move", "reversi_state", "reversi_resign"] {
            #expect(GomokuStubProtocol.count(host: host, rpc: rpc) == 0, "\(rpc) 가 AI 판에서 나갔다")
        }
        // 기준선: 같은 착수가 1:1 판에서는 한 번 나간다.
        let (duel, duelHost) = makeReversiStore("ai-offline-base", me: rvB, handler: rvHandler([
            "reversi_move": [try rvText("reversi_move__ok")],
        ]))
        duel.applyState(try rvState("reversi_state__my_turn"))
        await duel.place(19)
        #expect(GomokuStubProtocol.count(host: duelHost, rpc: "reversi_move") == 1)
    }

    @Test(.gomokuDefaultsCleanup)
    func 창이_안_보이면_사람_시계가_멈추고_다시_보이면_이어_간다() throws {
        // 없으면: 창을 닫아 둔 사이 AI 판의 30초가 흘러 자동 착수 세 번이면 사람이 지는데도(기다리는 상대가 없는데) 초록이다.
        let clock = RVClock(Date())
        let (store, _) = makeReversiStore("ai-pause", me: rvB, clock: clock, handler: rvHandler([:]))
        store.aiMoveChooser = rvNeverAnswers
        store.isWindowVisible = true
        store.startAIMatch(humanColor: .black)
        let t0 = clock.now
        // 기준선: 보이는 창이면 마감이 30초 뒤에 선다.
        #expect(store.match?.deadline == t0.addingTimeInterval(30))
        #expect(ReversiTurnWarning.watchesMyClock(store.match))
        clock.advance(10)
        store.windowDidHide()
        #expect(store.match?.deadline == nil)
        #expect(store.aiGame?.isClockPaused == true)
        #expect(store.remainingSeconds(now: clock.now) == nil)
        #expect(ReversiTurnWarning.watchesMyClock(store.match) == false)
        // 숨긴 동안 한 시간이 흘러도 자동 착수가 없다.
        clock.advance(3_600)
        store.handleAIClock(now: clock.now)
        #expect(store.match?.moveCount == 0)
        store.windowDidShow()
        let resumed = try #require(store.match?.deadline)
        #expect(abs(resumed.timeIntervalSince(clock.now) - 20) < 0.001)   // 남은 20초를 이어 간다
        // 가림도 같은 문이다(isWindowVisible 은 그대로).
        store.windowOcclusionDidChange(visible: false)
        #expect(store.match?.deadline == nil)
        #expect(store.isWindowVisible)
    }

    @Test(.gomokuDefaultsCleanup)
    func 사람_시계가_다_되면_무작위_자동_착수와_문구() throws {
        // 없으면: AI 판에서 사람 시계가 다 돼도 판이 멈춰 있거나(자동 착수 없음) 연속 횟수·문구가 안 서도 초록이다.
        let clock = RVClock(Date())
        let (store, _) = makeReversiStore("ai-clock", me: rvB, clock: clock, handler: rvHandler([:]))
        store.aiMoveChooser = rvNeverAnswers
        store.aiRuntime.randomIndex = { _ in 0 }
        store.isWindowVisible = true
        store.startAIMatch(humanColor: .black)
        let t0 = clock.now
        // 기준선: 29.9초에는 아무 일도 없다.
        store.handleAIClock(now: t0.addingTimeInterval(29.9))
        #expect(store.match?.moveCount == 0)
        clock.set(t0.addingTimeInterval(30))
        store.handleAIClock(now: clock.now)
        #expect(store.match?.moveCount == 1)
        #expect(store.match?.lastStoneIdx == 19)                   // 합법 수 [19,26,37,44] 의 0번째
        #expect(store.match?.autoStones == [19])
        #expect(store.match?.myAutoStreak == 1)
        #expect(store.notice == ReversiNoticeText.autoPlaced)
        #expect(store.isAIThinking)
    }

    @Test(.gomokuDefaultsCleanup)
    func 사람이_패스하면_AI_를_다시_부른다() async throws {
        // 없으면: 사람이 둘 곳이 없어 AI 차례가 연달아 올 때 AI 를 한 번만 불러 판이 AI 차례에 영영 멈춰도 초록이다.
        // 판: 흑(AI)이 c1(2)에 두면 백(사람)은 둘 곳이 없다 → 흑이 다시 c8(58)에 두어 백 전멸(서버 픽스처 ok_pass 와 같은 국면).
        let board = try #require(ReversiBoard(string: "bw" + String(repeating: ".", count: 54) + "bw" + "......"))
        #expect(ReversiRules.legalMoves(board, color: .black) == [2, 58])
        let (store, _) = makeReversiStore("ai-pass", me: rvB, handler: rvHandler([:]))
        store.aiMoveChooser = rvFirstLegal
        store.isWindowVisible = true
        let game = ReversiAIGame(humanColor: .white, board: board, turn: .black, startedAt: Date())
        store.aiGame = game
        store.match = ReversiStore.aiMatchState(game)
        store.phase = .playing
        #expect(store.isAIThinking)
        store.scheduleAITurnIfNeeded()
        await rvWait { store.match?.isFinished == true }
        #expect(store.aiRuntime.chooserCalls == 2)
        #expect(store.match?.plies.map(\.kind) == [.stone, .pass, .stone])
        #expect(store.match?.endReason == .wipeout)
        #expect(store.match?.outcome == .lost)
        #expect(store.phase == .result)
        #expect(store.isAIThinking == false)
    }

    @Test(.gomokuDefaultsCleanup)
    func 일대일_판이_서면_AI_판을_버리고_AI_판은_미션_꼬리를_안_운다() async throws {
        // 없으면: 수락된 1:1 판이 와도 AI 판이 남아 둘이 섞이거나, AI 판이 끝날 때 일일 미션 조회가 울어도 초록이다.
        let (store, _) = makeReversiStore("ai-yield", me: rvB, handler: rvHandler([:]))
        var finished = 0
        store.onMatchFinished = { finished += 1 }
        store.aiMoveChooser = rvNeverAnswers
        store.isWindowVisible = true
        store.startAIMatch(humanColor: .black)
        await store.resign()
        #expect(store.match?.isFinished == true)
        #expect(finished == 0)
        store.restartAIMatch()
        #expect(store.match?.isFinished == false)
        #expect(store.aiGame != nil)
        store.applyState(try rvState("reversi_respond__accepted"))
        #expect(store.match?.id == rvMainMatch)
        #expect(store.match?.isAI == false)
        #expect(store.aiGame == nil)
        // 기준선: 1:1 판이 끝나면 꼬리가 한 번 운다.
        store.applyState(try rvState("reversi_move__finished_board_full"))
        #expect(finished == 1)
    }

    @Test(.gomokuDefaultsCleanup)
    func 진행_중_판이_있으면_AI_판을_못_연다() throws {
        // 없으면: 서버가 진행 중이라 말하는 판(다른 기기에서 수락)이 있는데 AI 판을 열어 곧 1:1 판에 덮여도 초록이다.
        let (store, _) = makeReversiStore("ai-gate", me: rvB, handler: rvHandler([:]))
        #expect(store.canStartAIMatch)
        let lobby = try rvMutated("reversi_lobby__ok") { top in            // 바꾼 칸: me.active_match_id
            var me = top["me"] as! [String: Any]
            me["active_match_id"] = rvMainMatch
            top["me"] = me
        }
        store.applyLobby(try rvDecode(ReversiLobbyResponse.self, lobby))
        #expect(store.canStartAIMatch == false)
        store.startAIMatch(humanColor: nil)
        #expect(store.match == nil)
        #expect(store.notice == ReversiNoticeText.busy)
    }
}
