import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.32 오목 **AI 대국** — 로컬 판 규칙 · 스토어 연결 · 화면(docs/plan/gomoku-ai.md §3~§5).
//
// 사용자 결정(되묻지 않는다): 루비 안 걸기 · 순위·전적·기록 없음 · 사람 30초 뒤 무작위 자동 착수 · 단일 난이도.
// 엔진(`GomokuAI.bestMove`)은 이 파일이 믿지 않는다 — 스토어 시험은 **결정적 가짜 선택기**를 끼운다(엔진 갈래와 독립).
//
// 여기서 지키는 것:
//  ① 규칙은 서버 1:1 과 한 벌이다(5목 · 흑 금수 · 흑 규칙 패스 · 가득 차면 무승부 · 대리 착수는 흑 금수 제외 · 연속 3회 패,
//     단 그 수로 5목이면 자연 종료가 이긴다).
//  ② AI 판은 서버로 **한 건도** 안 나간다("ai-" id 가 조회·나가기·채팅·동기화에 안 실린다).
//  ③ 늦게 끝난 AI 수는 버린다(기권·새 판·1:1 시작 뒤).
//  ④ 1:1 판이 열리면 AI 판을 버리고, 로그아웃이 지운다.
//  ⑤ 창이 안 보이면 사람 시계가 멈추고 다시 보이면 남은 초로 이어 간다.
//  ⑥ 화면: 로비 머리글 [AI와 두기] · 돌 색 창 · AI 대국 · AI 결과가 고정 창 안에 노란 상자 없이 서고, 1:1 대국 머리글은 그대로다.

// MARK: - 픽스처

private let aiMe = "00000000-0000-0000-0000-0000000000a1"
private let aiRival = "00000000-0000-0000-0000-0000000000b2"
private let aiPvPMatchID = "abababab-2222-3333-4444-555555555555"
private let aiT0 = Date(timeIntervalSince1970: 1_800_000_000)

private func pt(_ notation: String) -> GomokuPoint { GomokuPoint(notation: notation)! }

private func board(black: [String] = [], white: [String] = []) -> GomokuBoard {
    var b = GomokuBoard()
    for n in black { b[pt(n)] = .black }
    for n in white { b[pt(n)] = .white }
    return b
}

/// 5목이 어디에도 없는 꽉 찬 판(가로 BBWW 반복 · 세로 BW 교대 · 두 대각 최대 2). 시험이 칸을 몇 개 비우거나 바꿔 쓴다.
private func tiledBoard() -> GomokuBoard {
    var b = GomokuBoard()
    for y in 0..<GomokuBoard.size {
        for x in 0..<GomokuBoard.size {
            b[GomokuPoint(x: x, y: y)!] = (x + 2 * y) % 4 < 2 ? .black : .white
        }
    }
    return b
}

/// K01(3-3) — 흑 F8·G8·H6·H7 이 있으면 H8 이 흑의 3-3 금수다(렌더 시험과 같은 모양).
private func doubleThreeBoard() -> GomokuBoard {
    board(black: ["F8", "G8", "H6", "H7"], white: ["C3", "M12", "K13", "B14"])
}

/// 천원에서 가장 가까운 합법 수(행→열 순서로 동점 해소). 결정적이라 시험이 AI 수를 미리 안다.
private let nearestChooser: GomokuAIMoveChooser = { board, color in
    let center = GomokuBoard.size / 2
    return GomokuAIGame.legalPoints(on: board, color: color).min { a, b in
        let da = abs(a.x - center) + abs(a.y - center), db = abs(b.x - center) + abs(b.y - center)
        return da != db ? da < db : (a.y, a.x) < (b.y, b.x)
    }
}

private func jsonText(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

/// 1:1 판 상태 묶음(서버 모양).
private func pvpState() -> [String: Any] {
    [
        "status": "ok",
        "match": [
            "id": aiPvPMatchID, "status": "active", "stake": 5, "black": aiRival, "white": aiMe,
            "challenger": aiRival, "opponent": aiMe, "move_count": 0, "turn": "black",
            "deadline_ms": Date().timeIntervalSince1970 * 1000 + 30_000, "result": NSNull(), "end_reason": NSNull(),
            "winner": NSNull(), "invite_expires_ms": NSNull()
        ] as [String: Any],
        "moves": [] as [Any],
        "my_color": "white",
        "opponent": ["user_id": aiRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"] as [String: Any],
        "ruby_balance": NSNull(),
        "server_now_ms": NSNull()
    ]
}

@MainActor
private enum AIRetention { static var stores: [WorkTimerStore] = [] }

/// 스텁 서버에 붙은 오목 스토어 + 결정적 AI(즉답). 요청은 호스트별로 기록된다(`GomokuStubProtocol`).
@MainActor
private func aiStore(
    _ label: String, handler: @escaping GomokuStubProtocol.Handler = { _, _, _ in nil }
) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0332-ai-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0332-ai"),
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: aiMe)
    AIRetention.stores.append(store)
    let gomoku = store.gomoku
    gomoku.aiRuntime.minimumThinkSeconds = 0
    gomoku.aiRuntime.randomIndex = { _ in 0 }
    gomoku.aiMoveChooser = nearestChooser
    return (store, gomoku, host)
}

/// 재개 횟수 기반 대기(벽시계 상한은 전체 스위트에서 메인 액터가 붙잡히면 먼저 끝난다 — V0327 관례).
@MainActor
private func aiWait(_ turns: Int = 4_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<turns {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 서버로 나가면 안 되는 대국 RPC.
private let matchRPCs: Set<String> = [
    "gomoku_state", "gomoku_move", "gomoku_resign", "gomoku_leave", "gomoku_chat_send", "gomoku_chat_mute",
    "gomoku_challenge", "gomoku_respond", "gomoku_cancel"
]

/// 사람이 흑·백인 AI 판을 스토어에 **직접** 세운다(렌더·거절 시험용 — 선택기를 돌리지 않는다).
@MainActor
private func seat(_ gomoku: GomokuStore, _ game: GomokuAIGame) {
    gomoku.aiGame = game
    gomoku.match = game.matchState()
    gomoku.phase = game.isFinished ? .result : .playing
}

/// 열리고 닫히는 문(선택기를 붙잡아 두는 데 쓴다). 여러 계산이 함께 기다려도 안전하게 **깃발을 본다**.
private final class AIGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false
    private var entered = 0
    private var returned = 0

    var isOpen: Bool { lock.withLock { open } }
    var enteredCount: Int { lock.withLock { entered } }
    var returnedCount: Int { lock.withLock { returned } }
    func release() { lock.withLock { open = true } }
    func enter() -> Int { lock.withLock { entered += 1; return entered } }
    func leave() { lock.withLock { returned += 1 } }
}

/// 문에 붙잡히는 선택기. **첫 계산만** 구석(A1)을 낸다 — 늦게 끝난 앞 판의 수가 새 판에 얹히면 그 돌이 눈에 띈다
/// (둘 다 천원이면 같은 자리라 섞여도 초록이다).
private func gatedChooser(_ gate: AIGate) -> GomokuAIMoveChooser {
    { board, color in
        let call = gate.enter()
        defer { gate.leave() }
        // 스토어가 판을 버리면(세대가 밀리면) 기다리던 계산도 취소된다 — 취소를 보고 곧바로 나간다(헛돌지 않게).
        while !gate.isOpen, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
        }
        if call == 1, board[pt("A1")] == nil { return pt("A1") }
        return await nearestChooser(board, color)
    }
}

// MARK: - 1. 로컬 판 규칙 (순수)

@Test
func aiGameFiveWinsForEitherSideAndWhiteOverlineWins() {
    // 사람 흑이 5목.
    var human = GomokuAIGame(humanColor: .black, board: board(black: ["D8", "E8", "F8", "G8"], white: ["D9", "E9", "F9", "G9"]),
                             turn: .black, now: aiT0)
    let step1 = human.humanPlace(pt("H8"), now: aiT0)
    #expect(step1 == nil)
    #expect(human.isFinished && human.outcome == .won && human.endReason == .five)
    #expect(human.turn == nil && human.deadline == nil)
    let step2 = human.humanPlace(pt("A1"), now: aiT0)
    #expect(step2 == GomokuAIGame.Refusal(kind: .finished, reason: nil), "끝난 판에 또 둔다")

    // AI 흑이 5목 → 사람 패.
    var ai = GomokuAIGame(humanColor: .white, board: board(black: ["D8", "E8", "F8", "G8"], white: ["D9", "E9", "F9", "G9"]),
                          turn: .black, now: aiT0)
    let step3 = ai.applyAIMove(pt("H8"), now: aiT0)
    #expect(step3)
    #expect(ai.isFinished && ai.outcome == .lost && ai.endReason == .five)

    // 백은 장목(6)도 이긴다(흑만 금수).
    var white = GomokuAIGame(humanColor: .white, board: board(black: ["C1", "D1", "E1", "G1", "H1"], white: ["C8", "D8", "E8", "G8", "H8"]),
                             turn: .white, now: aiT0)
    let step4 = white.humanPlace(pt("F8"), now: aiT0)
    #expect(step4 == nil)
    #expect(white.outcome == .won && white.endReason == .five)
}

@Test
func aiGameRefusesForbiddenOccupiedAndOutOfTurnWithoutChangingTheBoard() {
    var game = GomokuAIGame(humanColor: .black, board: doubleThreeBoard(), turn: .black, now: aiT0)
    let before = game
    let step5 = game.humanPlace(pt("H8"), now: aiT0)
    #expect(step5 == GomokuAIGame.Refusal(kind: .forbidden, reason: .doubleThree))
    let step6 = game.humanPlace(pt("F8"), now: aiT0)
    #expect(step6 == GomokuAIGame.Refusal(kind: .occupied, reason: nil))
    #expect(game == before, "거절이 판을 바꿨다")

    // AI 차례에 사람이 둔다 · AI 가 규칙 밖의 수를 낸다.
    var aiTurn = GomokuAIGame(humanColor: .white, board: doubleThreeBoard(), turn: .black, now: aiT0)
    let step7 = aiTurn.humanPlace(pt("A1"), now: aiT0)
    #expect(step7 == GomokuAIGame.Refusal(kind: .notYourTurn, reason: nil))
    let step8 = aiTurn.applyAIMove(pt("H8"), now: aiT0)
    #expect(!step8, "AI 흑이 3-3 금수에 뒀다")
    let step9 = aiTurn.applyAIMove(pt("F8"), now: aiT0)
    #expect(!step9, "AI 가 이미 돌이 있는 자리에 뒀다")
    let step10 = aiTurn.applyAIMove(nil, now: aiT0)
    #expect(!step10, "둘 곳이 있는데 AI 패스가 받아들여졌다")
    #expect(aiTurn.board == doubleThreeBoard())
}

@Test
func aiGameHumanClockStartsOnlyOnHumanTurnsAndPausesKeepingTheRemainder() {
    var game = GomokuAIGame(humanColor: .black, now: aiT0)
    #expect(game.id.hasPrefix(GomokuAIGame.idPrefix) && GomokuAIGame.isAIMatchID(game.id))
    #expect(!GomokuAIGame.isAIMatchID(aiPvPMatchID), "서버 uuid 를 AI 판으로 읽는다")
    #expect(game.deadline == aiT0.addingTimeInterval(30))
    #expect(!game.isHumanClockExpired(now: aiT0.addingTimeInterval(29.9)))
    #expect(game.isHumanClockExpired(now: aiT0.addingTimeInterval(30)))

    game.pause(now: aiT0.addingTimeInterval(10))
    #expect(game.deadline == nil && game.pausedRemaining == 20)
    #expect(!game.isHumanClockExpired(now: aiT0.addingTimeInterval(10_000)), "멈춘 시계가 다 됐다고 한다")
    game.resume(now: aiT0.addingTimeInterval(100))
    #expect(game.deadline == aiT0.addingTimeInterval(120) && game.pausedRemaining == nil, "남은 20초로 이어 가지 않는다")

    let step11 = game.humanPlace(pt("H8"), now: aiT0.addingTimeInterval(101))
    #expect(step11 == nil)
    #expect(game.turn == .white && game.deadline == nil, "AI 차례에 사람 시계가 돈다")
    let step12 = game.applyAIMove(pt("I9"), now: aiT0.addingTimeInterval(102))
    #expect(step12)
    #expect(game.deadline == aiT0.addingTimeInterval(132), "사람 차례가 오면 30초를 새로 준다")

    let state = game.matchState()
    #expect(state.stake == 0 && state.rubyDelta == nil && state.opponent.isGomokuAI && state.myColor == .black)
    #expect(state.moveCount == 2 && state.lastMove == pt("I9") && state.turn == .black)
}

@Test
func aiGameAutoPlaceSkipsBlackForbiddenPointsAndCountsTheStreak() throws {
    let shape = doubleThreeBoard()
    var empties: [GomokuPoint] = []
    for y in 0..<15 { for x in 0..<15 { let p = GomokuPoint(x: x, y: y)!; if shape[p] == nil { empties.append(p) } } }
    let legal = GomokuAIGame.legalPoints(on: shape, color: .black)
    #expect(!legal.contains(pt("H8")), "대리 착수 후보에 흑 금수가 들어 있다")
    #expect(legal.count == empties.count - 1)

    // 금수 칸이 '빈칸 목록'에서 서던 자리의 번호를 줘도 금수에 안 놓인다.
    let index = try #require(empties.firstIndex(of: pt("H8")))
    var game = GomokuAIGame(humanColor: .black, board: shape, turn: .black, now: aiT0)
    let step13 = game.autoPlaceHuman(now: aiT0.addingTimeInterval(31), randomIndex: { _ in index })
    #expect(step13)
    let placed = try #require(game.lastMove)
    #expect(placed != pt("H8"))
    #expect(game.autoPoints == [placed] && game.lastMoveWasAuto && game.humanAutoStreak == 1)
    #expect(game.turn == .white)

    // 직접 두면 0.
    let step14 = game.applyAIMove(pt("O15"), now: aiT0)
    #expect(step14)
    let step15 = game.humanPlace(pt("A15"), now: aiT0)
    #expect(step15 == nil)
    #expect(game.humanAutoStreak == 0 && !game.lastMoveWasAuto)
}

@Test
func threeAutoPlacementsInARowLoseUnlessTheThirdMakesFive() throws {
    var game = GomokuAIGame(humanColor: .black, now: aiT0)
    for round in 1...3 {
        let step16 = game.autoPlaceHuman(now: aiT0, randomIndex: { _ in 0 })
        #expect(step16)
        if round < 3 {
            #expect(!game.isFinished, "\(round)번째 대리 착수에 판이 끝났다")
            let step17 = game.applyAIMove(GomokuPoint(x: 14, y: 14 - round), now: aiT0)
            #expect(step17)
        }
    }
    #expect(game.isFinished && game.outcome == .lost && game.endReason == .abandoned)

    // 세 번째 대리 착수가 5목이면 자리 비움이 아니라 5목 승이다(서버 순서 — 이긴 수를 빼앗지 않는다).
    var lucky = GomokuAIGame(humanColor: .black, board: board(black: ["A1", "B1", "C1", "D1"], white: ["A3", "B3", "C3", "D3"]),
                             turn: .black, humanAutoStreak: 2, now: aiT0)
    let candidates = GomokuAIGame.legalPoints(on: lucky.board, color: .black)
    let five = try #require(candidates.firstIndex(of: pt("E1")))
    let step18 = lucky.autoPlaceHuman(now: aiT0, randomIndex: { _ in five })
    #expect(step18)
    #expect(lucky.outcome == .won && lucky.endReason == .five)
}

@Test
func blackWithNoLegalPointPassesAndAFullBoardIsADraw() throws {
    // 꽉 찬 판에서 두 칸만 비운다: A1(백이 둘 자리) · H8(흑에게 장목 금수 — 가로 흑 E~G · I~J 사이).
    var shape = tiledBoard()
    for (notation, color) in [("D8", GomokuColor.white), ("E8", .black), ("F8", .black), ("G8", .black),
                              ("I8", .black), ("J8", .black), ("K8", .white)] {
        shape[pt(notation)] = color
    }
    shape[pt("H8")] = nil
    shape[pt("A1")] = nil
    #expect(GomokuRules.judge(board: shape, point: pt("H8"), color: .black) == .forbidden(.overline), "시험 판이 틀렸다")
    #expect(GomokuRules.judge(board: shape, point: pt("A1"), color: .white) == .legal, "시험 판이 틀렸다")

    var game = GomokuAIGame(humanColor: .white, board: shape, turn: .white, now: aiT0)
    let step19 = game.humanPlace(pt("A1"), now: aiT0)
    #expect(step19 == nil)
    #expect(!game.isFinished)
    #expect(game.turn == .white, "흑이 둘 곳이 없는데 차례가 흑에 멈췄다")
    #expect(game.blackPassed, "흑 규칙 패스가 기록에 없다")
    #expect(game.moveCount == shape.stoneCount + 2, "기록 수에 패스가 안 들어갔다")
    #expect(game.deadline == aiT0.addingTimeInterval(30))

    var afterPass = game
    #expect(GomokuRules.judge(board: afterPass.board, point: pt("H8"), color: .white) == .legal, "시험 판이 틀렸다")
    let step20 = afterPass.humanPlace(pt("H8"), now: aiT0)
    #expect(step20 == nil)
    #expect(afterPass.isFinished && afterPass.outcome == .draw && afterPass.endReason == .boardFull)
    #expect(!afterPass.blackPassed)

    // AI 가 흑인데 둘 곳이 없으면 패스만 받는다.
    var aiBlack = GomokuAIGame(humanColor: .white, board: game.board, turn: .black, now: aiT0)
    let step21 = aiBlack.applyAIMove(pt("H8"), now: aiT0)
    #expect(!step21)
    let step22 = aiBlack.applyAIMove(nil, now: aiT0)
    #expect(step22)
    #expect(aiBlack.turn == .white && aiBlack.blackPassed)
    game.resign()
    #expect(game.outcome == .lost && game.endReason == .resign)
}

// MARK: - 2. 스토어 — 서버와 섞이지 않는다

@MainActor
@Test(.gomokuDefaultsCleanup)
func anAIMatchNeverSendsAMatchRequestToTheServer() async throws {
    let (_, gomoku, host) = aiStore("no-server")
    gomoku.isWindowVisible = true
    #expect(gomoku.canStartAIMatch)

    gomoku.startAIMatch(humanColor: .black)
    #expect(gomoku.isAIMatch && gomoku.phase == .playing)
    let id = try #require(gomoku.match?.id)
    #expect(GomokuAIGame.isAIMatchID(id))
    #expect(gomoku.match?.deadline != nil, "보이는 창에서 사람 시계가 안 돈다")

    await gomoku.place(pt("H8"))
    await aiWait { gomoku.match?.turn == .black && gomoku.match?.moveCount == 2 }
    #expect(gomoku.match?.moveCount == 2, "AI 가 안 뒀다")
    #expect(gomoku.aiRuntime.chooserCalls == 1)

    // 서버로 가는 문을 전부 두드린다.
    await gomoku.refreshMatch()
    await gomoku.refreshMatch(id: id)
    await gomoku.pollTick(at: Date().addingTimeInterval(1_000))
    gomoku.chatDraft = "안녕"
    gomoku.sendChatDraft()
    gomoku.sendQuick(.hi)
    gomoku.setChatMuted(true)
    await aiWait(40) { false }
    #expect(GomokuStubProtocol.calls(host: host).isEmpty,
            "AI 판이 서버로 나갔다: \(GomokuStubProtocol.calls(host: host).map(\.rpc))")

    // 동기화 신호는 받은함(1:1 신청)으로만 간다.
    await gomoku.syncOnce()
    #expect(GomokuStubProtocol.calls(host: host).map(\.rpc) == ["gomoku_inbox"])

    // 기권 → 결과 → 창 닫기 → 로비: 나가기·기권 RPC 없음.
    await gomoku.resign()
    #expect(gomoku.phase == .result && gomoku.match?.outcome == .lost && gomoku.match?.endReason == .resign)
    gomoku.windowDidHide()
    gomoku.backToLobby()
    await aiWait(200) { GomokuStubProtocol.count(host: host, rpc: "gomoku_lobby") > 0 }
    #expect(gomoku.phase == .lobby && gomoku.match == nil && gomoku.aiGame == nil)
    let calls = GomokuStubProtocol.calls(host: host)
    #expect(calls.filter { matchRPCs.contains($0.rpc) }.isEmpty, "대국 RPC 가 나갔다: \(calls.map(\.rpc))")
    #expect(!calls.contains { $0.body.contains(GomokuAIGame.idPrefix) }, "AI 판 id 가 요청 본문에 실렸다")
    #expect(gomoku.activeMatchID == nil, "AI 판 id 가 서버 진행 중 판 장부에 들어갔다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func aLateAIMoveIsDroppedAfterResignAndAfterANewGame() async {
    let (_, gomoku, _) = aiStore("late")
    gomoku.isWindowVisible = true
    let gate = AIGate()
    gomoku.aiMoveChooser = gatedChooser(gate)

    // 사람 백 → AI 흑이 곧바로 생각한다(문에 붙잡힘).
    gomoku.startAIMatch(humanColor: .white)
    await aiWait { gate.enteredCount == 1 }
    #expect(gomoku.isAIThinking)
    await gomoku.resign()
    #expect(gomoku.match?.isFinished == true)

    // 새 판(같은 색) — AI 가 또 생각한다. 앞 판의 계산은 아직 안 끝났다.
    gomoku.restartAIMatch()
    await aiWait { gate.enteredCount == 2 }
    let secondID = gomoku.match?.id
    #expect(gomoku.phase == .playing && gomoku.match?.board.stoneCount == 0)

    gate.release()
    await aiWait { gate.returnedCount == 2 && gomoku.match?.moveCount == 1 }
    await aiWait(40) { false }
    #expect(gomoku.match?.id == secondID)
    #expect(gomoku.match?.board.stoneCount == 1, "앞 판의 늦은 수가 새 판에 두 번째 돌로 얹혔다")
    #expect(gomoku.match?.board[pt("A1")] == nil, "앞 판의 늦은 수(A1)가 새 판에 놓였다")
    #expect(gomoku.match?.board[pt("H8")] == .black, "새 판의 AI 수가 안 놓였다")
    #expect(gomoku.match?.turn == .white)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func acceptingAOneOnOneInviteDiscardsTheAIMatch() async {
    let (_, gomoku, host) = aiStore("pvp-wins") { rpc, _, _ in
        guard rpc == "gomoku_respond" else { return nil }
        return GomokuStubProtocol.Reply(body: jsonText(["status": "ok", "state": pvpState()]))
    }
    gomoku.isWindowVisible = true
    let gate = AIGate()
    gomoku.aiMoveChooser = gatedChooser(gate)
    gomoku.startAIMatch(humanColor: .white)
    await aiWait { gate.enteredCount == 1 }
    let aiGeneration = gomoku.aiRuntime.generation

    let peer = GomokuUser(id: aiRival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: false)
    gomoku.incoming = [GomokuInvite(id: aiPvPMatchID, peer: peer, stake: 5, expiresAt: Date().addingTimeInterval(50))]
    await gomoku.respond(inviteID: aiPvPMatchID, accept: true)

    #expect(gomoku.match?.id == aiPvPMatchID, "1:1 수락이 AI 판을 못 이겼다")
    #expect(gomoku.aiGame == nil && !gomoku.isAIMatch)
    #expect(gomoku.aiRuntime.generation > aiGeneration, "버린 AI 판의 계산이 여전히 유효한 세대다")

    gate.release()
    await aiWait { gate.returnedCount == 1 }
    await aiWait(40) { false }
    #expect(gomoku.match?.id == aiPvPMatchID && gomoku.match?.board.stoneCount == 0, "버린 AI 판의 수가 1:1 판에 얹혔다")
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_respond") == 1)
    gomoku.stopPolling()
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func signingOutClearsTheAIMatchAndStartIsRefusedWhileAOneOnOneIsPending() {
    let (_, gomoku, _) = aiStore("reset")
    gomoku.startAIMatch(humanColor: .black)
    #expect(gomoku.isAIMatch)
    gomoku.reset()
    #expect(gomoku.aiGame == nil && gomoku.match == nil && gomoku.phase == .lobby)

    // 보낸 신청이 떠 있으면 시작하지 않는다(수락되는 순간 1:1 이 AI 판을 이긴다).
    let peer = GomokuUser(id: aiRival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: false)
    gomoku.outgoing = GomokuInvite(id: aiPvPMatchID, peer: peer, stake: 5, expiresAt: Date().addingTimeInterval(50))
    #expect(!gomoku.canStartAIMatch)
    gomoku.startAIMatch(humanColor: .black)
    #expect(gomoku.aiGame == nil && gomoku.phase == .lobby)
    gomoku.outgoing = nil

    // 1:1 판이 떠 있으면 시작하지 않고 그 사실을 말한다.
    gomoku.match = GomokuMatchState(
        id: aiPvPMatchID, stake: 5, myColor: .black, opponent: peer, board: GomokuBoard(), lastMove: nil,
        moveCount: 0, turn: .black, deadline: nil, isFinished: false, outcome: nil, endReason: nil,
        rubyDelta: nil, blackPassed: false
    )
    gomoku.startAIMatch(humanColor: .black)
    #expect(gomoku.aiGame == nil && gomoku.match?.id == aiPvPMatchID)
    #expect(gomoku.notice == GomokuNoticeText.busy)
}

// MARK: - 3. 스토어 — 사람 시계

@MainActor
@Test(.gomokuDefaultsCleanup)
func theHumanClockPausesWhileTheWindowIsHiddenOrOccluded() async {
    let (_, gomoku, _) = aiStore("clock")
    final class Clock: @unchecked Sendable { var now = aiT0 }
    let clock = Clock()
    gomoku.clock = { clock.now }
    gomoku.pollStepSeconds = 3_600

    // 창이 안 보이는 채로 시작하면 시계가 멈춘 채로 선다(30초 그대로).
    gomoku.startAIMatch(humanColor: .black)
    #expect(gomoku.match?.deadline == nil && gomoku.aiGame?.pausedRemaining == 30)
    gomoku.handleAIClock(now: aiT0.addingTimeInterval(1_000))
    #expect(gomoku.match?.moveCount == 0, "멈춘 시계로 대리 착수가 일어났다")

    clock.now = aiT0.addingTimeInterval(5)
    gomoku.windowDidShow()
    #expect(gomoku.match?.deadline == aiT0.addingTimeInterval(35))

    clock.now = aiT0.addingTimeInterval(15)
    gomoku.windowDidHide()
    #expect(gomoku.match?.deadline == nil && gomoku.aiGame?.pausedRemaining == 20, "창을 닫았는데 시계가 돈다")

    clock.now = aiT0.addingTimeInterval(600)
    gomoku.windowDidShow()
    #expect(gomoku.match?.deadline == aiT0.addingTimeInterval(620), "다시 보이면 남은 20초로 이어 가야 한다")

    clock.now = aiT0.addingTimeInterval(605)
    gomoku.windowOcclusionDidChange(visible: false)
    #expect(gomoku.aiGame?.pausedRemaining == 15, "다른 창에 가려졌는데 시계가 돈다")
    clock.now = aiT0.addingTimeInterval(700)
    gomoku.windowOcclusionDidChange(visible: true)
    #expect(gomoku.match?.deadline == aiT0.addingTimeInterval(715))

    // 시간이 다 되면 대리 착수 → 안내 → AI 가 받아 둔다.
    gomoku.handleAIClock(now: aiT0.addingTimeInterval(715))
    #expect(gomoku.match?.autoPoints.count == 1 && gomoku.myAutoStreak == 1)
    #expect(gomoku.notice == GomokuNoticeText.autoPlaced)
    await aiWait { gomoku.match?.moveCount == 2 }
    #expect(gomoku.match?.turn == .black)
    gomoku.stopPolling()
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func threeMissedClocksInARowLoseTheAIMatch() async {
    let (_, gomoku, host) = aiStore("abandon")
    final class Clock: @unchecked Sendable { var now = aiT0 }
    let clock = Clock()
    gomoku.clock = { clock.now }
    gomoku.isWindowVisible = true

    gomoku.startAIMatch(humanColor: .black)
    for round in 1...3 {
        gomoku.handleAIClock(now: clock.now.addingTimeInterval(31))
        if round == 2 {
            #expect(gomoku.autoStreakWarning == "한 번 더 놓치면 집니다", "마지막 한 번 전 경고가 없다")
        }
        if round < 3 {
            await aiWait { gomoku.match?.turn == .black && gomoku.match?.moveCount == round * 2 }
            #expect(gomoku.match?.moveCount == round * 2)
        }
    }
    #expect(gomoku.phase == .result)
    #expect(gomoku.match?.outcome == .lost && gomoku.match?.endReason == .abandoned)
    #expect(GomokuStubProtocol.calls(host: host).isEmpty)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func tapsInAnAIMatchReuseTheOneOnOneRefusalsAndAnIllegalEngineMoveFallsBack() async {
    let (_, gomoku, host) = aiStore("refusals")
    gomoku.isWindowVisible = true
    seat(gomoku, GomokuAIGame(humanColor: .black, board: doubleThreeBoard(), turn: .black, now: Date()))

    await gomoku.place(pt("H8"))
    #expect(gomoku.notice == GomokuNoticeText.forbidden(.doubleThree))
    await gomoku.place(pt("F8"))
    #expect(gomoku.notice == GomokuNoticeText.occupied)
    #expect(gomoku.match?.board == doubleThreeBoard())

    // 엔진이 이미 돌이 있는 자리를 내도 판이 멈추지 않는다(무작위 합법 수로 대신 둔다).
    gomoku.aiMoveChooser = { _, _ in GomokuPoint(notation: "F8") }
    await gomoku.place(pt("A1"))
    #expect(gomoku.notice == nil, "성공한 착수가 앞 거절 안내를 안 지웠다")
    await aiWait { gomoku.match?.turn == .black && gomoku.match?.board.stoneCount == doubleThreeBoard().stoneCount + 2 }
    #expect(gomoku.match?.board.stoneCount == doubleThreeBoard().stoneCount + 2)
    #expect(gomoku.match?.board[pt("F8")] == .black, "대타 수가 남의 돌을 덮었다")

    // AI 차례에 누르면 1:1 과 같은 말.
    seat(gomoku, GomokuAIGame(humanColor: .black, board: doubleThreeBoard(), turn: .white, now: Date()))
    await gomoku.place(pt("A2"))
    #expect(gomoku.notice == GomokuNoticeText.notYourTurn)
    #expect(GomokuStubProtocol.calls(host: host).isEmpty)
}

// MARK: - 4. 소스 계약 (주석을 걷어낸 뒤)

@Test
func serverDoorsFilterAIMatchIDs() throws {
    let code = gomokuCollapsed(V0317ShopTests.stripped(try CheckCoreSourceLayout.joinedSplitSource("GomokuStore.swift")))
    let refresh = try #require(gomokuBody(of: "func refreshMatch(id rawID: String?)", in: code))
    #expect(refresh.contains("!GomokuAIGame.isAIMatchID(requested)"), "상태 조회가 AI 판 id 를 거르지 않는다")
    #expect(gomokuBody(of: "private func leaveMatch(", in: code)?.contains("GomokuAIGame.isAIMatchID(id)") == true,
            "나가기가 AI 판 id 를 거르지 않는다")
    #expect(gomokuBody(of: "private func sendChat(", in: code)?.contains("GomokuAIGame.isAIMatchID(id)") == true)
    #expect(gomokuBody(of: "func setChatMuted(", in: code)?.contains("GomokuAIGame.isAIMatchID(current.id)") == true)
    #expect(gomokuBody(of: "func syncOnce()", in: code)?.contains("!isAIMatch") == true,
            "동기화가 AI 판을 진행 중 판으로 보고 받은함을 안 본다")
    #expect(gomokuBody(of: "func reset()", in: code)?.contains("discardAIGame()") == true, "로그아웃이 AI 판을 안 지운다")
    let matchDecl = try #require(code.range(of: "var match: GomokuMatchState? {"))
    #expect(code[matchDecl.upperBound...].prefix(400).contains("discardAIGame()"), "1:1 판이 열려도 AI 판이 남는다")
}

// MARK: - 5. 화면

private let aiRenderMe = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

@MainActor
private func aiPanel(_ store: GomokuStore, prompt: Bool = false) -> some View {
    GomokuPanel(store: store, me: { aiRenderMe }, clipsOverflowInsteadOfScroll: true, previewAIPrompt: prompt)
}

private enum AIRenderError: Error { case failed }

@MainActor
private func aiBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw AIRenderError.failed }
    return bitmap
}

private func aiSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "gomoku-ai")
}

private func aiYellowPixels(_ bitmap: NSBitmapImageRep) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var hits = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if data[o] >= 240 && data[o + 1] >= 195 && data[o + 2] <= 40 { hits += 1 }
        }
    }
    return hits
}

/// 사각형(pt) 안에서 두 그림의 채널 차가 8 을 넘는 픽셀 수.
private func aiDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, rect: CGRect) -> Int {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, let pa = a.bitmapData, let pb = b.bitmapData
    else { return Int.max }
    let bpr = a.bytesPerRow, spp = a.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(a.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(a.pixelsHigh - 1, Int(rect.maxY * 2))
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if abs(Int(pa[o]) - Int(pb[o])) > 8 || abs(Int(pa[o + 1]) - Int(pb[o + 1])) > 8
                || abs(Int(pa[o + 2]) - Int(pb[o + 2])) > 8 { count += 1 }
        }
    }
    return count
}

private func aiLuma(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> Int {
    guard let data = bitmap.bitmapData else { return 0 }
    let o = Int(y * 2) * bitmap.bytesPerRow + Int(x * 2) * bitmap.samplesPerPixel
    return (Int(data[o]) + Int(data[o + 1]) + Int(data[o + 2])) / 3
}

@MainActor
private func aiExpectFitsWindow(_ bitmap: NSBitmapImageRep, _ name: String) {
    let size = GomokuWindowLayout.contentSize
    #expect(bitmap.pixelsWide == Int(size.width) * 2 && bitmap.pixelsHigh == Int(size.height) * 2,
            "\(name) 가 \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)px 다 — 고정 창을 넘치거나 모자란다")
    #expect(aiYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다")
}

/// 창 아래 여백 띠(본문이 넘치면 여기에 카드 테두리가 그려진다).
@MainActor
private var aiBottomBand: CGRect {
    let size = GomokuWindowLayout.contentSize
    return CGRect(x: 0, y: size.height - GomokuWindowLayout.contentPadding + 2,
                  width: size.width, height: GomokuWindowLayout.contentPadding - 4)
}

/// 머리글 오른쪽 절반(칩·버튼 자리).
@MainActor
private var aiHeaderRight: CGRect {
    CGRect(x: GomokuWindowLayout.contentSize.width / 2, y: GomokuWindowLayout.contentPadding,
           width: GomokuWindowLayout.contentSize.width / 2 - GomokuWindowLayout.contentPadding,
           height: GomokuWindowLayout.headerHeight)
}

/// 대국 오른쪽 열의 가운데(1:1 은 채팅 카드, AI 는 안내 카드가 서는 높이).
@MainActor
private var aiSideMiddle: CGRect {
    let top = GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing
    let x = GomokuWindowLayout.contentPadding + GomokuWindowLayout.boardSide + GomokuWindowLayout.columnSpacing
    return CGRect(x: x, y: top + 260, width: GomokuWindowLayout.sideColumnWidth, height: 200)
}

@MainActor
@Test
func lobbyHeaderShowsTheAIButtonAndThePromptOpensInTheMiddle() throws {
    func lobby() -> GomokuStore {
        let store = GomokuStore()
        store.users = [GomokuUser(id: aiRival, displayName: "민수", avatarURL: nil, characterID: "fox",
                                  isWorking: true, isCapable: true, inMatch: false)]
        store.record = GomokuRecord(wins: 3, losses: 1, draws: 0)
        store.rubyBalance = 42
        return store
    }
    let enabled = try aiBitmap(aiPanel(lobby()))
    aiSave(enabled, "ai-lobby")
    aiExpectFitsWindow(enabled, "로비")

    // 보낸 신청이 떠 있으면 버튼이 흐려진다 — 머리글 오른쪽이 달라져야 버튼이 실제로 서 있다는 뜻이다.
    let busy = lobby()
    busy.outgoing = GomokuInvite(id: aiPvPMatchID, peer: busy.users[0], stake: 5,
                                 expiresAt: Date(timeIntervalSince1970: 2_000_000_000))
    let disabled = try aiBitmap(aiPanel(busy))
    #expect(aiDiff(enabled, disabled, rect: aiHeaderRight) > 200, "머리글에 [AI와 두기] 버튼이 없거나 상태에 반응하지 않는다")

    // 대국 중 머리글에는 버튼이 없다 — 1:1 대국 머리글과 AI 대국 머리글이 같은 픽셀이다.
    let pvp = lobby()
    pvp.match = GomokuMatchState(
        id: aiPvPMatchID, stake: 5, myColor: .black, opponent: pvp.users[0], board: GomokuBoard(), lastMove: nil,
        moveCount: 0, turn: .white, deadline: nil, isFinished: false, outcome: nil, endReason: nil,
        rubyDelta: nil, blackPassed: false
    )
    pvp.phase = .playing
    let pvpBitmap = try aiBitmap(aiPanel(pvp))
    #expect(aiDiff(pvpBitmap, enabled, rect: aiHeaderRight) > 200, "대국 중에도 머리글 버튼이 남아 있다")

    let prompt = try aiBitmap(aiPanel(lobby(), prompt: true))
    aiSave(prompt, "ai-prompt")
    aiExpectFitsWindow(prompt, "돌 색 고르기 창")
    let center = CGRect(x: (GomokuWindowLayout.contentSize.width - GomokuWindowLayout.stakePromptWidth) / 2,
                        y: GomokuWindowLayout.contentSize.height / 2 - 80,
                        width: GomokuWindowLayout.stakePromptWidth, height: 160)
    #expect(aiDiff(prompt, enabled, rect: center) > 5_000, "가운데에 돌 색 고르기 창이 안 떴다")
    #expect(aiLuma(prompt, x: 30, y: 660) + 10 < aiLuma(enabled, x: 30, y: 660), "창 뒤가 어두워지지 않았다")
}

@MainActor
@Test
func aiMatchScreensFitTheWindowAndReplaceChatWithTheNoRecordCard() throws {
    let stones = board(black: ["H8", "G7", "I9"], white: ["H9", "G9", "J10"])

    func aiPlaying(turn: GomokuColor) -> GomokuStore {
        let store = GomokuStore()
        store.rubyBalance = 42
        store.record = GomokuRecord(wins: 3, losses: 1, draws: 0)
        seat(store, GomokuAIGame(humanColor: .black, board: stones, turn: turn, now: Date(timeIntervalSince1970: 2_000_000_000)))
        return store
    }
    func pvpPlaying(turn: GomokuColor) -> GomokuStore {
        let store = GomokuStore()
        store.rubyBalance = 42
        store.record = GomokuRecord(wins: 3, losses: 1, draws: 0)
        store.match = GomokuMatchState(
            id: aiPvPMatchID, stake: 5, myColor: .black,
            opponent: GomokuUser(id: aiRival, displayName: "민수", avatarURL: nil, characterID: "fox",
                                 isWorking: true, isCapable: true, inMatch: true),
            board: stones, lastMove: nil, moveCount: 6, turn: turn, deadline: Date(timeIntervalSince1970: 2_000_000_000),
            isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false
        )
        store.phase = .playing
        return store
    }

    for (name, turn) in [("ai-playing-my-turn", GomokuColor.black), ("ai-playing-ai-thinking", .white)] {
        let ai = try aiBitmap(aiPanel(aiPlaying(turn: turn)))
        aiSave(ai, name)
        aiExpectFitsWindow(ai, name)
        let pvp = try aiBitmap(aiPanel(pvpPlaying(turn: turn)))
        #expect(aiDiff(ai, pvp, rect: aiBottomBand) <= 2, "\(name): 오른쪽 열이 창 아래 여백까지 자란다")
        #expect(aiDiff(ai, pvp, rect: aiHeaderRight) <= 2, "\(name): 대국 머리글이 1:1 과 달라졌다")
        #expect(aiDiff(ai, pvp, rect: aiSideMiddle) > 2_000, "\(name): 채팅 카드 자리에 AI 안내 카드가 안 섰다")
    }

    // 결과: 이김(5목) · 짐(기권) — 루비 줄이 없다.
    var won = GomokuAIGame(humanColor: .black, board: board(black: ["D8", "E8", "F8", "G8"], white: ["D9", "E9", "F9", "G9"]),
                           turn: .black, now: Date(timeIntervalSince1970: 2_000_000_000))
    won.humanPlace(pt("H8"), now: Date(timeIntervalSince1970: 2_000_000_000))
    var lost = GomokuAIGame(humanColor: .white, board: stones, turn: .white, now: Date(timeIntervalSince1970: 2_000_000_000))
    lost.resign()
    for (name, game) in [("ai-result-won", won), ("ai-result-lost", lost)] {
        let store = GomokuStore()
        store.rubyBalance = 42
        seat(store, game)
        #expect(store.phase == .result)
        let bitmap = try aiBitmap(aiPanel(store))
        aiSave(bitmap, name)
        aiExpectFitsWindow(bitmap, name)

        let pvp = GomokuStore()
        pvp.rubyBalance = 42
        var state = game.matchState()
        state = GomokuMatchState(
            id: aiPvPMatchID, stake: 5, myColor: state.myColor,
            opponent: GomokuUser(id: aiRival, displayName: "민수", avatarURL: nil, characterID: "fox",
                                 isWorking: true, isCapable: true, inMatch: false),
            board: state.board, lastMove: state.lastMove, moveCount: state.moveCount, turn: nil, deadline: nil,
            isFinished: true, outcome: state.outcome, endReason: state.endReason, rubyDelta: 0, blackPassed: false
        )
        pvp.match = state
        pvp.phase = .result
        let pvpBitmap = try aiBitmap(aiPanel(pvp))
        #expect(aiDiff(bitmap, pvpBitmap, rect: aiBottomBand) <= 2, "\(name): 결과 열이 창 아래로 넘친다")
        // 결과 카드 오른쪽 끝(1:1 은 루비 변화가 서는 자리).
        let top = GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing
        let rubyArea = CGRect(x: GomokuWindowLayout.contentSize.width - GomokuWindowLayout.contentPadding - 130, y: top + 20,
                              width: 110, height: 70)
        #expect(aiDiff(bitmap, pvpBitmap, rect: rubyArea) > 300, "\(name): AI 결과에 루비 변화가 그려졌다")
    }
}
