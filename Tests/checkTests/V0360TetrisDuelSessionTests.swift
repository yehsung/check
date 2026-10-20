import Foundation
import Testing
@testable import CheckCore

// v0.3.60 테트리스 1:1 — 판 구동기(`TetrisDuelSession`): 주입 시계 · 따라잡기(D10) · 가속(D7) · 보고 차분 ·
// 그리고 **종료 보장 시뮬레이션**(가속을 켠 판은 6분 안에 끝나고, 끈 판은 더 오래 산다).

private typealias SPiece = TetrisGame.Piece
private typealias SActive = TetrisGame.ActivePiece

/// 시작 시각 100초(로컬 단조 시계)에 판 시계 0 이 오도록 맞춘 세션.
private func startedSession(seed: Int = 20_261_020, start: TimeInterval = 100) -> TetrisDuelSession {
    var s = TetrisDuelSession(seed: seed)
    s.syncStart(startAtMs: 5_000_000, serverNowMs: 5_000_000 - start * 1000, localNow: 0)
    return s
}

@Suite("v0.3.60 테트리스 대결 — 판 구동기")
struct V0360TetrisDuelSessionTests {

    // MARK: 가속 곡선

    @Test("가속 곡선 D7 — t<120 은 1, 그 뒤 min(28, 10 + (t−120)/10) · 초는 내림 · 이상한 값은 1/28")
    func rampCurveMatchesTheSpec() {
        let table: [(Double, Int)] = [
            (-5, 1), (0, 1), (60, 1), (119.999, 1), (120, 10), (129.99, 10), (130, 11), (169.5, 14),
            (170, 15), (299.9, 27), (300, 28), (480, 28), (10_000, 28), (5e12, 28),
        ]
        for (t, floor) in table {
            #expect(TetrisDuelSession.rampLevelFloor(elapsedSeconds: t) == floor, "t=\(t) → \(TetrisDuelSession.rampLevelFloor(elapsedSeconds: t)) ≠ \(floor)")
        }
        #expect(TetrisDuelSession.rampLevelFloor(elapsedSeconds: .nan) == 1)
        #expect(TetrisDuelSession.rampLevelFloor(elapsedSeconds: .infinity) == 1)
        // 서버 계약과 같은 숫자인가(설계서 D7 의 글자 그대로).
        #expect(TetrisDuelSession.rampStartSeconds == 120 && TetrisDuelSession.rampStartLevel == 10
                && TetrisDuelSession.rampSecondsPerLevel == 10 && TetrisDuelSession.rampMaxLevel == 28)
    }

    // MARK: 시작 · 카운트다운

    @Test("시작 시각 전에는 엔진이 안 열린다(카운트다운) · 넘는 순간 열리고 그 뒤로만 흐른다")
    func countdownHoldsTheEngine() {
        var s = startedSession()
        #expect(s.countdownRemaining(at: 97) == 3)
        s.advance(to: 99.9)
        #expect(!s.started)
        #expect(s.game.phase == .ready && s.simulated == 0)
        s.advance(to: 100.5)
        #expect(s.started && s.isLive)
        #expect(abs(s.simulated - 0.5) < 1e-9 && abs(s.game.elapsed - 0.5) < 1e-9)
        #expect(s.countdownRemaining(at: 100.5) == 0)
        #expect(s.matchElapsed(at: 101) == 1)
    }

    @Test("시작 시각을 모르면(둘 다 준비 전) 아무리 불러도 판이 안 열린다")
    func noStartNoGame() {
        var s = TetrisDuelSession(seed: 3)
        s.advance(to: 1_000)
        #expect(!s.started && s.game.phase == .ready && s.startAt == nil)
        #expect(s.matchElapsed(at: 5) == nil && s.countdownRemaining(at: 5) == nil)
    }

    @Test("서버 시각 옮기기 — 응답마다 불러도 가장 이른 추정만 남는다(판 시계가 뒤로 안 간다)")
    func startSyncKeepsTheEarliestEstimate() {
        var s = TetrisDuelSession(seed: 1)
        // start_at 은 서버 시각 10_000ms. 첫 응답: 서버 9_000ms 에 만들어져 로컬 50.3 에 받음 → 시작 51.3.
        s.syncStart(startAtMs: 10_000, serverNowMs: 9_000, localNow: 50.3)
        #expect(abs((s.startAt ?? 0) - 51.3) < 1e-9)
        // 더 빨리 온 응답(지연이 짧다) → 51.1 로 당겨진다.
        s.syncStart(startAtMs: 10_000, serverNowMs: 9_500, localNow: 50.6)
        #expect(abs((s.startAt ?? 0) - 51.1) < 1e-9)
        // 더 늦게 온 응답은 무시.
        s.syncStart(startAtMs: 10_000, serverNowMs: 9_600, localNow: 51.9)
        #expect(abs((s.startAt ?? 0) - 51.1) < 1e-9)
        s.syncStart(startAtMs: .nan, serverNowMs: 9_600, localNow: 0)
        #expect(abs((s.startAt ?? 0) - 51.1) < 1e-9)
    }

    // MARK: 따라잡기(D10)

    @Test("따라잡기 — 프레임이 10초 멎었다가 한 번 불려도 판은 10초 흐른다(엔진 혼자는 maxStep 만 흐른다 = 기준선)")
    func catchUpAdvancesTheWholeGap() {
        var s = startedSession()
        s.advance(to: 100)                 // 시작
        s.advance(to: 110)                 // 10초 공백 뒤 한 번
        #expect(abs(s.game.elapsed - 10) < 1e-6, "10초 공백 뒤 판 시계 \(s.game.elapsed)")
        #expect(s.droppedSeconds == 0)
        var bare = TetrisGame(seed: UInt64(s.seed))
        bare.action()
        bare.step(dt: 10)
        #expect(abs(bare.elapsed - TetrisGame.maxStep) < 1e-12, "기준선 전제가 깨졌다 — 엔진이 클램프를 안 한다")
        // 따라잡기는 maxStep 조각을 그대로 흘린 것과 비트 단위로 같다(시간을 버리거나 더하지 않는다).
        var manual = TetrisGame(seed: UInt64(s.seed))
        manual.action()
        var rem = 10.0
        while rem > 1e-9 { let d = min(rem, TetrisGame.maxStep); manual.step(dt: d); rem -= d }
        #expect(s.game == manual)
    }

    @Test("따라잡기 상한 30초 — 100초 공백이면 앞 70초는 버리고 뒤 30초만 흘린다 · 가속은 지금 시각에 맞는다")
    func catchUpIsCappedAtThirtySeconds() {
        var s = startedSession()
        s.advance(to: 100)
        s.advance(to: 225)                 // 판 시계 125초
        #expect(abs(s.droppedSeconds - 95) < 1e-6, "버린 시간 \(s.droppedSeconds)")
        #expect(abs(s.simulated - 125) < 1e-6)
        #expect(abs(s.game.elapsed - 30) < 1e-6 || s.game.isGameOver, "흘린 판 시간 \(s.game.elapsed)")
        #expect(s.game.levelFloor == 10, "판 시계 125초인데 바닥이 \(s.game.levelFloor)")
    }

    @Test("가속은 판 시계를 따라 오른다 — 120초 전 1 · 직후 10 · 공개 level 은 advance 그대로")
    func rampIsAppliedDuringPlay() {
        var s = startedSession()
        s.advance(to: 100)
        s.advance(to: 219.9)              // 89.9 버리고 89.9→119.9 흘림
        #expect(s.game.levelFloor == 1)
        s.advance(to: 220.2)
        #expect(s.game.levelFloor == 10)
        #expect(s.game.difficultyLevel == 10 && s.game.level < 10)
    }

    // MARK: 입력 게이트

    @Test("시작 전·탑아웃 뒤의 하드드롭은 새 판을 열지 않는다(엔진 action 은 ready/result 에서 새 판이다)")
    func inputsAreGatedSoActionNeverRestarts() {
        var s = startedSession()
        s.hardDrop(); s.rotate(clockwise: true); s.hold(); s.setLeftHeld(true)
        #expect(s.game.phase == .ready, "시작 전 입력이 판을 열었다")
        // 탑아웃까지: 손 대지 않고 판 시계를 민다(20G 바닥에서 빨리 끝난다).
        var over = TetrisDuelSession(seed: 9, startedGame: TetrisGame(seed: 9, board: TetrisGame.emptyBoard(), active: nil,
                                                                      phase: .are(remaining: 0.1), advance: 950),
                                     startAt: 0)
        var t = 0.0
        while !over.toppedOut, t < 120 { t += 0.25; over.advance(to: t) }
        #expect(over.toppedOut, "판이 안 끝났다")
        while over.game.phase != .result, t < 130 { t += 0.25; over.advance(to: t) }
        let advanceAtEnd = over.game.advance
        over.hardDrop()
        #expect(over.game.phase == .result && over.game.advance == advanceAtEnd, "결과 화면에서 하드드롭이 새 판을 열었다")
        #expect(!over.isLive)
    }

    @Test("서버가 판을 닫으면 시계·입력·보고가 멎는다")
    func finishFreezesEverything() {
        var s = startedSession()
        s.advance(to: 101)
        s.setLeftHeld(true)
        s.finish()
        let snapshot = s.game
        s.advance(to: 120)
        s.hardDrop()
        #expect(s.game.elapsed == snapshot.elapsed && s.game.board == snapshot.board)
        #expect(s.reportReason(at: 500) == nil)
        let absorbed = s.absorbOpponentAttack(total: 5)
        #expect(absorbed == 0)
    }

    // MARK: 상대 공격 차분

    @Test("상대 공격 누계 → 차분만 대기열에 · 같은 누계는 멱등 · 줄어든 누계는 무시 · 시작 전엔 보류")
    func opponentAttackIsAppliedAsDiffs() {
        var s = startedSession()
        let early = s.absorbOpponentAttack(total: 2)
        #expect(early == 0, "시작 전 공격을 받았다")
        #expect(s.garbageApplied == 0)
        s.advance(to: 100.2)
        // 시작 전에 왔던 공격이 다음 응답에서 들어간다 → 같은 누계는 멱등 → 늘어난 만큼만 → 줄어든 누계는 무시.
        let steps = [s.absorbOpponentAttack(total: 2), s.absorbOpponentAttack(total: 2),
                     s.absorbOpponentAttack(total: 5), s.absorbOpponentAttack(total: 4)]
        #expect(steps == [2, 0, 3, 0])
        #expect(s.garbageApplied == 5)
        #expect(s.game.pendingGarbage == [2, 3])
    }

    // MARK: 재개(앱을 다시 열었다 — 리뷰 RV1)

    @Test("재개 — 서버의 내 마지막 판(조각·방해 줄 표시)과 누계에서 다시 선다 · 받아들인 공격은 다시 안 넣는다 · 판 시계는 그 보고 시각부터")
    func resumingRebuildsTheServerBoard() throws {
        // 없으면: 앱을 다시 연 사람이 빈 판에서 다시 시작하고(침묵 15초 안에 껐다 켜면 거의 찬 판이 공짜로 비워진다),
        // 이미 받아들인 상대 공격이 0 에서 다시 세어져 통째로 한 번 더 들어온다.
        let rows = Array(repeating: "..........", count: 14)
            + ["...T......", "..TTT.....", "ZZ..SS....", "IJLOSTZ...", "GGGG.GGGGG", "GGGG.GGGGG"]
        let board = rows.joined()
        let point = TetrisDuelResumePoint(seq: 60, board: board, lines: 30, garbageSent: 7, garbageApplied: 12,
                                          pending: 3, elapsedSeconds: 59.5)
        var s = try #require(TetrisDuelSession(seed: 4_242, resumingFrom: point))
        #expect(TetrisDuelBoard.encode(s.game) == board, "재개한 판이 서버가 들고 있는 판과 다르다")
        let bottom = TetrisGame.totalRows - 1
        #expect(s.game.isGarbage(row: bottom, column: 0) && !s.game.isGarbage(row: bottom, column: 4))
        #expect(s.game.board[bottom][4] == nil && s.game.board[bottom][0] != nil, "방해 줄 구멍이 메워졌다")
        #expect(!s.game.isGarbage(row: bottom - 2, column: 0), "조각 칸을 방해 줄로 칠했다")
        #expect(s.started && s.isLive && !s.toppedOut)
        #expect(s.game.lines == 30 && s.game.attackSentTotal == 7 && s.game.pendingGarbageLines == 3)
        #expect(s.garbageApplied == 12 && s.seq == 60)

        // 상대 누계 12 = 이미 받아들인 만큼 → 아무것도 안 들어간다. 14 면 차분 2만.
        #expect(s.absorbOpponentAttack(total: 12) == 0, "이미 받아들인 공격을 다시 넣었다")
        #expect(s.absorbOpponentAttack(total: 14) == 2)
        #expect(s.game.pendingGarbageLines == 5 && s.garbageApplied == 14)

        // 판 시계: 시작(로컬 1,000)에서 60초 지난 지금 — 마지막 보고(59.5초) 뒤 공백 0.5초만 흘린다(ARE 뒤 첫 조각).
        s.syncStart(startAtMs: 5_000_000, serverNowMs: 5_060_000, localNow: 1_060)
        s.advance(to: 1_060)
        #expect(abs(s.simulated - 60) < 1e-9 && s.droppedSeconds == 0, "재개가 판 시계를 0 에서 다시 돌렸다")
        #expect(s.game.active != nil, "ARE 뒤 첫 조각이 안 나왔다")
        #expect(TetrisDuelBoard.encode(s.game) == board, "0.5초 공백에 굳은 판이 바뀌었다")

        // 다음 보고는 서버 seq 위로, 누계는 이어서.
        let report = s.makeReport(at: 1_060)
        #expect(report.seq == 61 && report.garbageApplied == 14 && report.garbageSent == 7)
        #expect(report.lines == 30 && report.pending == 5 && !report.toppedOut)

        // 깨진 판 글자(길이 · 모르는 글자)는 재개하지 않는다 — 지어낸 판보다 새 판이 낫다.
        var broken = point
        broken.board = String(board.dropLast())
        #expect(TetrisDuelSession(seed: 1, resumingFrom: broken) == nil)
        broken.board = String(board.dropLast()) + "x"
        #expect(TetrisDuelSession(seed: 1, resumingFrom: broken) == nil)
        // 새 판 init 도 받아들인 누계를 서버 값에서 잇는다.
        var fresh = TetrisDuelSession(seed: 1, startingSeq: 3, garbageApplied: 4)
        #expect(fresh.garbageApplied == 4 && fresh.makeReport(at: 0).garbageApplied == 4)
    }

    // MARK: 보고 차분

    @Test("보고 — 첫 보고는 준비 · 그 뒤 1초 하트비트 · 0.5초엔 없음 · 번호는 1씩 · 서버 seq 따라잡기")
    func heartbeatReports() {
        var s = startedSession()
        #expect(s.reportReason(at: 90) == .ready)
        let first = s.makeReport(at: 90)
        #expect(first.seq == 1 && first.board == TetrisDuelBoard.emptyText && !first.toppedOut)
        #expect(s.reportReason(at: 90.5) == nil)
        #expect(s.reportReason(at: 91.0) == .heartbeat)   // 카운트다운 중에도 하트비트(서버 last_seen)
        let second = s.makeReport(at: 91)
        #expect(second.seq == 2)
        s.adoptServerSeq(10)
        let third = s.makeReport(at: 92)
        #expect(third.seq == 11)
        s.adoptServerSeq(3)
        let fourth = s.makeReport(at: 93)
        #expect(fourth.seq == 12)
        var resumed = TetrisDuelSession(seed: 1, startingSeq: 40)
        let firstAfterResume = resumed.makeReport(at: 0)
        #expect(firstAfterResume.seq == 41)
    }

    @Test("보고 — 공격 누계가 늘면 하트비트를 안 기다리고 곧바로(단 0.25초 간격) · 실은 값이 엔진과 같다")
    func attackTriggersAnImmediateReport() {
        // 오른쪽 끝 열만 빈 4줄 + 세로 I → 하드드롭 한 번에 4줄(공격 4).
        let game = TetrisGame(seed: 4, board: TetrisGame.boardFixture(bottomRows: Array(repeating: "IIIIIIIII.", count: 4)),
                              active: SActive(piece: .i, rotation: .right, column: 7, row: TetrisGame.spawnRow))
        var s = TetrisDuelSession(seed: 4, startedGame: game, startAt: 0)
        _ = s.makeReport(at: 10)
        s.hardDrop()
        #expect(s.game.attackSentTotal == 4)
        #expect(s.reportReason(at: 10.1) == nil, "최소 간격 0.25초를 안 지켰다")
        #expect(s.reportReason(at: 10.25) == .attack)
        let r = s.makeReport(at: 10.25)
        #expect(r.garbageSent == 4 && r.lines == 4 && r.pending == 0 && r.garbageApplied == 0)
        #expect(r.board == TetrisDuelBoard.encode(s.game))
        #expect(s.reportReason(at: 10.6) == nil, "같은 누계로 또 곧바로 보고한다")
        #expect(s.reportReason(at: 11.25) == .heartbeat)
    }

    @Test("보고 — 탑아웃은 곧바로 · 실은 topped_out = true")
    func toppingOutTriggersAnImmediateReport() {
        var s = TetrisDuelSession(seed: 9, startedGame: TetrisGame(seed: 9, board: TetrisGame.emptyBoard(), active: nil,
                                                                   phase: .are(remaining: 0.1), advance: 950),
                                  startAt: 0)
        _ = s.makeReport(at: 0)
        var t = 0.0
        while !s.toppedOut, t < 120 { t += 0.05; s.advance(to: t) }
        #expect(s.toppedOut)
        #expect(t > 1, "전제: 마지막 보고에서 1초 넘게 지났다(하트비트와 겹쳐도 탑아웃이 이유여야 한다)")
        #expect(s.reportReason(at: t) == .toppedOut, "하트비트보다 탑아웃이 먼저다")
        let r = s.makeReport(at: t)
        #expect(r.toppedOut)
        #expect(s.reportReason(at: t + 0.3) == nil, "탑아웃을 두 번 곧바로 보낸다")
    }
}

// MARK: - 종료 보장 시뮬레이션

/// 조종사가 모는 판 하나(가속 있음 = 세션 · 가속 없음 = 같은 따라잡기에 바닥만 1 로 둔 기준선).
private protocol DuelPilotDriver {
    var game: TetrisGame { get }
    mutating func advance(to now: TimeInterval)
    mutating func setLeft(_ held: Bool)
    mutating func setRight(_ held: Bool)
    mutating func rotateClockwise()
    mutating func rotateCounterClockwise()
    mutating func drop()
}

extension TetrisDuelSession: DuelPilotDriver {
    mutating func setLeft(_ held: Bool) { setLeftHeld(held) }
    mutating func setRight(_ held: Bool) { setRightHeld(held) }
    mutating func rotateClockwise() { rotate(clockwise: true) }
    mutating func rotateCounterClockwise() { rotate(clockwise: false) }
    mutating func drop() { hardDrop() }
}

/// 조종사 성향. 손은 `handInterval` 초에 한 번까지(회전 한 번 · 방향키 누르기 · 즉시 내리기 중 하나)이고,
/// 조각이 뜬 뒤 `think` 초 동안은 손을 안 댄다(보고 정하는 시간). 방향키는 **누른 채** 두어 DAS·ARR 로 밀고,
/// 목표 열에 닿는 프레임에 뗀다(떼기는 손으로 안 센다 — 사람도 손가락을 드는 데 시간을 안 쓴다).
private struct SimPilot {
    var think: TimeInterval
    var handInterval: TimeInterval = 0.1
}

/// 지금 조각에 대한 조종사의 손 상태.
private struct SimHands {
    var turns: Int
    var column: Int
    var spawnTime: TimeInterval
    var lastHand: TimeInterval
    var held = 0
    var lastLeftmost = -1
    var lastShiftTime: TimeInterval = 0
}

/// 기준선·복제본용 구동기 — 세션과 **같은** 따라잡기(maxStep 조각)인데 가속 바닥을 넣지 않는다(엔진 바닥 그대로).
private struct NoRampDriver: DuelPilotDriver {
    var game: TetrisGame
    var simulated: TimeInterval

    init(seed: Int) {
        game = TetrisGame(seed: UInt64(clamping: seed))
        game.action()
        simulated = 0
    }

    init(game: TetrisGame, at now: TimeInterval) {
        self.game = game
        simulated = now
    }

    mutating func advance(to now: TimeInterval) {
        var remaining = now - simulated
        while remaining > 1e-9 {
            if case .result = game.phase { simulated = now; return }
            let dt = min(remaining, TetrisGame.maxStep)
            game.step(dt: dt)
            simulated += dt
            remaining -= dt
        }
    }

    mutating func setLeft(_ held: Bool) { game.setLeftHeld(held) }
    mutating func setRight(_ held: Bool) { game.setRightHeld(held) }
    mutating func rotateClockwise() { game.rotate(clockwise: true) }
    mutating func rotateCounterClockwise() { game.rotate(clockwise: false) }
    mutating func drop() { if case .running = game.phase { game.action() } }
}

private func simLeftmost(_ game: TetrisGame) -> Int? {
    game.active.map { $0.cells.map(\.column).min() ?? 0 }
}

/// 한 프레임의 손. 실제 판(세션·기준선)과 자리 고르기 복제본이 **같은 함수**를 쓴다.
private func simPolicyTick<D: DuelPilotDriver>(_ d: inout D, _ h: inout SimHands, now: TimeInterval, pilot: SimPilot) {
    guard case .running = d.game.phase, let leftmost = simLeftmost(d.game) else { return }
    if leftmost != h.lastLeftmost { h.lastLeftmost = leftmost; h.lastShiftTime = now }
    if h.held != 0 {
        let reached = h.held < 0 ? leftmost <= h.column : leftmost >= h.column
        // 벽·굳은 칸에 막혀 DAS 가 한참 안 밀면 그 자리를 목표로 삼는다.
        let stuck = now - h.lastShiftTime > TetrisGame.dasSeconds + 2 * TetrisGame.arrSeconds
        if reached || stuck {
            if h.held < 0 { d.setLeft(false) } else { d.setRight(false) }
            h.held = 0
            if stuck && !reached { h.column = leftmost }
        }
        return
    }
    guard now - h.spawnTime >= pilot.think - 1e-9, now - h.lastHand >= pilot.handInterval - 1e-9 else { return }
    h.lastHand = now
    if h.turns != 0 {
        let before = d.game.active?.rotation
        if h.turns == 3 { d.rotateCounterClockwise() } else { d.rotateClockwise() }
        let turned = d.game.active?.rotation != before
        h.turns = turned ? (h.turns == 3 ? 0 : h.turns - 1) : 0
        return
    }
    if leftmost != h.column {
        h.held = leftmost < h.column ? 1 : -1
        h.lastShiftTime = now
        if h.held < 0 { d.setLeft(true) } else { d.setRight(true) }
        return
    }
    d.drop()
}

/// 고전 가중치 판 비용(GamesMiniGameSimulationTests 의 조종사와 같은 식).
private func simBoardCost(_ board: [[SPiece?]]) -> Double {
    var heights = [Int](repeating: 0, count: TetrisGame.columns)
    var holes = 0
    for column in 0..<TetrisGame.columns {
        var covered = false
        for row in 0..<TetrisGame.totalRows {
            if board[row][column] != nil {
                if !covered { covered = true; heights[column] = TetrisGame.totalRows - row }
            } else if covered {
                holes += 1
            }
        }
    }
    let bumpiness = zip(heights, heights.dropFirst()).reduce(0) { $0 + abs($1.0 - $1.1) }
    return Double(heights.reduce(0, +)) * 0.51 + Double(holes) * 3.6
        + Double(bumpiness) * 0.18 + Double(heights.max() ?? 0) * 0.5
}

private let simFrame: TimeInterval = 1.0 / 32.0

/// **중력·DAS·락까지 흉내 낸** 자리 고르기: 후보(회전 수 × 목표 열)마다 복제본에서 같은 손 함수(`simPolicyTick`)를
/// 같은 프레임으로 굴려 실제로 굳은 판의 비용으로 고른다. 높은 중력에서는 조각이 손보다 먼저 내려앉아 공중에서만 갈 수 있는
/// 자리가 막히므로(첫 판본은 그 자리를 골라 L9 · 75초에 죽었다), '갈 수 있는가'를 복제본이 직접 답하게 한다.
private func simBestPlan(_ game: TetrisGame, now: TimeInterval, hands template: SimHands, pilot: SimPilot) -> (turns: Int, column: Int)? {
    guard game.active != nil else { return nil }
    var best: (turns: Int, column: Int)?
    var bestCost = Double.infinity
    let startAdvance = game.advance
    for turns in 0..<4 {
        for column in 0..<TetrisGame.columns {
            var probe = NoRampDriver(game: game, at: now)
            var h = template
            h.turns = turns
            h.column = column
            var t = now
            simPolicyTick(&probe, &h, now: t, pilot: pilot)
            while probe.game.advance == startAdvance, !probe.game.isGameOver, t - now < 4 {
                t += simFrame
                probe.advance(to: t)
                simPolicyTick(&probe, &h, now: t, pilot: pilot)
            }
            guard probe.game.advance != startAdvance, !probe.game.isGameOver else { continue }
            let cost = simBoardCost(probe.game.board) - 12 * Double(probe.game.lines - game.lines)
            if cost < bestCost { bestCost = cost; best = (turns, column) }
        }
    }
    return best
}

private struct SimOutcome {
    var endedAt: TimeInterval?
    var lines: Int
    var advance: Int
    var maxDifficulty: Int
    var pieces: Int
}

/// 사람 속도 조종사로 판 하나를 끝까지(또는 `limit` 초까지) 둔다. 프레임은 1/32초(2의 거듭제곱)이고 판 시계는 구동기가
/// 흘린다(세션은 단조 시계 + 가속, 기준선은 같은 따라잡기에 가속만 없다).
private func simPlay<D: DuelPilotDriver>(_ driver: inout D, pilot: SimPilot, from start: TimeInterval = 0,
                                         limit: TimeInterval) -> SimOutcome {
    var now = start
    var hands = SimHands(turns: 0, column: 0, spawnTime: start, lastHand: start - 1)
    var planAdvance = -1
    var maxDifficulty = 1
    var pieces = 0
    driver.advance(to: start)
    while now < limit {
        now += simFrame
        driver.advance(to: now)
        let g = driver.game
        maxDifficulty = max(maxDifficulty, g.difficultyLevel)
        if g.isGameOver {
            return SimOutcome(endedAt: now, lines: g.lines, advance: g.advance, maxDifficulty: maxDifficulty, pieces: pieces)
        }
        guard case .running = g.phase, g.active != nil else { continue }
        if g.advance != planAdvance {
            planAdvance = g.advance
            pieces += 1
            if hands.held < 0 { driver.setLeft(false) } else if hands.held > 0 { driver.setRight(false) }
            hands = SimHands(turns: 0, column: 0, spawnTime: now, lastHand: hands.lastHand)
            let plan = simBestPlan(driver.game, now: now, hands: hands, pilot: pilot)
            hands.turns = plan?.turns ?? 0
            hands.column = plan?.column ?? (simLeftmost(driver.game) ?? 0)
        }
        simPolicyTick(&driver, &hands, now: now, pilot: pilot)
    }
    let g = driver.game
    return SimOutcome(endedAt: nil, lines: g.lines, advance: g.advance, maxDifficulty: maxDifficulty, pieces: pieces)
}

@Suite("v0.3.60 테트리스 대결 — 종료 보장(조종사 시뮬레이션)")
struct V0360TetrisDuelTerminationTests {

    private static let sixMinutes: TimeInterval = 360
    private static let seeds = [3, 20_261_020, 777]

    private static func endText(_ outcome: SimOutcome, limit: TimeInterval) -> String {
        outcome.endedAt.map { String(format: "%.1f", $0) } ?? "살아 있음(\(Int(limit)))"
    }

    /// ① 판 전체 — **느리게 두는 사람**(조각을 보고 1초 생각한 뒤 손을 댄다). 솔로 난이도는 놓은 조각 수(advance)로 오르므로
    ///    느린 사람은 오래 낮은 레벨에 머문다 — 가속이 없으면 그 판이 길게 간다. 가속은 120초에 바닥을 L10 으로 올려 그 판을 끝낸다.
    ///    (빠른 조종사(생각 0.25초)는 advance 가 바닥보다 먼저 올라 가속이 거의 안 걸린다 — 실측 seed 3: 둘 다 188.4초.
    ///     그래서 가속의 몫을 재는 기준선은 느린 사람이다.)
    @Test("느린 사람: 가속을 켠 판은 6분 안에(실측 약 125초) 끝나고, 같은 조종사·같은 시드로 가속을 끈 판은 더 오래 산다")
    func rampEndsASlowPlayersGame() {
        let limit: TimeInterval = 900
        let pilot = SimPilot(think: 1.0)
        for seed in Self.seeds {
            var ramp = startedSession(seed: seed, start: 0)
            let withRamp = simPlay(&ramp, pilot: pilot, limit: limit)
            var plain = NoRampDriver(seed: seed)
            let withoutRamp = simPlay(&plain, pilot: pilot, limit: limit)
            let rampEnd = withRamp.endedAt ?? .infinity
            let plainEnd = withoutRamp.endedAt ?? .infinity
            print("[sim] tetris duel slow seed=\(seed) ramp: end=\(Self.endText(withRamp, limit: limit))s pieces=\(withRamp.pieces) lines=\(withRamp.lines) advance=\(withRamp.advance) maxL=\(withRamp.maxDifficulty)"
                  + " | no ramp: end=\(Self.endText(withoutRamp, limit: limit))s pieces=\(withoutRamp.pieces) lines=\(withoutRamp.lines) advance=\(withoutRamp.advance) maxL=\(withoutRamp.maxDifficulty)")
            #expect(rampEnd < Self.sixMinutes, "seed \(seed): 가속을 켠 판이 6분 안에 안 끝났다(\(rampEnd))")
            // 기준선이 달라야 한다: 조종사가 120초 전에 죽으면 이 시뮬은 가속을 안 잰다.
            #expect(rampEnd > TimeInterval(TetrisDuelSession.rampStartSeconds),
                    "seed \(seed): 조종사가 가속 전에(\(rampEnd)초) 죽었다 — 가속을 안 잰다")
            #expect(withRamp.maxDifficulty >= TetrisDuelSession.rampStartLevel, "seed \(seed): 가속 바닥이 안 걸렸다")
            #expect(withoutRamp.maxDifficulty < TetrisDuelSession.rampStartLevel,
                    "seed \(seed): 기준선도 L\(withoutRamp.maxDifficulty)까지 갔다 — 느린 사람이 아니다")
            #expect(plainEnd > rampEnd + 10, "seed \(seed): 가속을 끈 판(\(plainEnd))이 켠 판(\(rampEnd))보다 오래 못 살았다")
        }
    }

    /// ② 판 끝머리 — **5분까지 버틴 잘하는 사람**. 생각 없이(0초) 0.1초마다 손을 대고 DAS 로 미는 조종사를 판 시계 300초
    ///    (가속 바닥 L28 = 리셋 한도 2 · 20G)의 빈 판에 세운다. 리셋 한도 2 로는 양 끝 열에 못 닿아 판이 반드시 끝난다
    ///    (설계서 D6·D7: 정상 판의 끝 ≈ 5분 40초). 기준선은 같은 빈 판·같은 조종사에서 가속만 뺀 것(L1 에서 출발).
    @Test("잘하는 사람: 판 시계 5분에 빈 판으로 서도 가속(L28)이 6분 전에 끝내고, 가속을 끈 같은 판은 더 오래 산다")
    func rampEndsAStrongPlayersGameBeforeSixMinutes() {
        let start: TimeInterval = 300
        let limit: TimeInterval = 900
        let pilot = SimPilot(think: 0)
        for seed in Self.seeds {
            var fresh = TetrisGame(seed: UInt64(seed))
            fresh.action()
            var ramp = TetrisDuelSession(seed: seed, startedGame: fresh, startAt: 0, simulated: start)
            let withRamp = simPlay(&ramp, pilot: pilot, from: start, limit: limit)
            var plain = NoRampDriver(game: fresh, at: start)
            let withoutRamp = simPlay(&plain, pilot: pilot, from: start, limit: limit)
            let rampEnd = withRamp.endedAt ?? .infinity
            let plainEnd = withoutRamp.endedAt ?? .infinity
            print("[sim] tetris duel strong@300 seed=\(seed) ramp: end=\(Self.endText(withRamp, limit: limit))s pieces=\(withRamp.pieces) lines=\(withRamp.lines) maxL=\(withRamp.maxDifficulty)"
                  + " | no ramp: end=\(Self.endText(withoutRamp, limit: limit))s pieces=\(withoutRamp.pieces) lines=\(withoutRamp.lines) advance=\(withoutRamp.advance) maxL=\(withoutRamp.maxDifficulty)")
            #expect(withRamp.maxDifficulty == TetrisDuelSession.rampMaxLevel)
            #expect(rampEnd < Self.sixMinutes, "seed \(seed): 가속 L28 에서도 6분 안에 안 끝났다(\(rampEnd))")
            #expect(withRamp.pieces >= 5, "seed \(seed): 조각 \(withRamp.pieces)장 만에 끝났다 — 조종사가 아무것도 안 했다")
            #expect(plainEnd > rampEnd + 30, "seed \(seed): 가속을 끈 판(\(plainEnd))이 켠 판(\(rampEnd))보다 오래 못 살았다")
        }
    }

    /// ③ 두 사람이 붙는 판 — 서버 흉내(공격 누계는 단조 · 상한 8 + 3×경과초로 자른다)를 사이에 두고 보고·응답을 주고받는다.
    ///    같은 시드라 두 사람의 조각 순서가 같고, 공격이 상대 대기열로 건너가 판에 들어오고, 누가 먼저 꼭대기에 닿는다.
    @Test("두 사람 대결 — 같은 시드면 조각 순서가 같고, 공격이 건너가 들어오며, 6분 안에 한쪽이 끝난다")
    func twoPilotsExchangeGarbageThroughReports() {
        let pilots = [SimPilot(think: 0), SimPilot(think: 0.25)]
        var sessions = [startedSession(seed: 4_242, start: 0), startedSession(seed: 4_242, start: 0)]
        var hands = [SimHands(turns: 0, column: 0, spawnTime: 0, lastHand: -1), SimHands(turns: 0, column: 0, spawnTime: 0, lastHand: -1)]
        var planAdvance = [-1, -1]
        var order: [[SPiece]] = [[], []]
        var serverSent = [0, 0]
        var sawGarbageRows = [false, false]
        var maxPending = [0, 0]
        var now = 0.0
        var loser: Int?
        while now < Self.sixMinutes, loser == nil {
            now += simFrame
            for i in 0..<2 {
                sessions[i].advance(to: now)
                if sessions[i].toppedOut { loser = loser ?? i }
                let g = sessions[i].game
                if g.garbageMask.contains(where: { $0 != 0 }) { sawGarbageRows[i] = true }
                maxPending[i] = max(maxPending[i], g.pendingGarbageLines)
                if case .running = g.phase, g.active != nil, g.advance != planAdvance[i] {
                    planAdvance[i] = g.advance
                    order[i].append(g.active!.piece)
                    if hands[i].held < 0 { sessions[i].setLeft(false) } else if hands[i].held > 0 { sessions[i].setRight(false) }
                    hands[i] = SimHands(turns: 0, column: 0, spawnTime: now, lastHand: hands[i].lastHand)
                    let plan = simBestPlan(g, now: now, hands: hands[i], pilot: pilots[i])
                    hands[i].turns = plan?.turns ?? 0
                    hands[i].column = plan?.column ?? (simLeftmost(g) ?? 0)
                }
                simPolicyTick(&sessions[i], &hands[i], now: now, pilot: pilots[i])
                // 보고 → 서버(단조 · 상한) → 응답의 상대 누계를 차분으로 받는다.
                if sessions[i].reportReason(at: now) != nil {
                    let report = sessions[i].makeReport(at: now)
                    #expect(TetrisDuelBoard.isValid(report.board))
                    let cap = 8 + 3 * Int(max(0, now))
                    serverSent[i] = max(serverSent[i], min(report.garbageSent, cap))
                    sessions[i].absorbOpponentAttack(total: serverSent[1 - i])
                }
            }
        }
        print("[sim] tetris duel pair: loser=\(loser.map(String.init) ?? "없음") t=\(String(format: "%.1f", now))s sent=\(serverSent)"
              + " applied=\([sessions[0].garbageApplied, sessions[1].garbageApplied]) maxPending=\(maxPending) pieces=\([order[0].count, order[1].count])")
        #expect(loser != nil, "6분 안에 아무도 안 끝났다")
        let n = min(order[0].count, order[1].count)
        #expect(n >= 30, "비교할 조각이 \(n)장뿐이다")
        #expect(Array(order[0].prefix(n)) == Array(order[1].prefix(n)), "같은 시드인데 두 사람의 조각 순서가 갈렸다")
        #expect(serverSent[0] > 0 && serverSent[1] > 0, "공격이 한쪽이라도 0이다 — 교환을 안 쟀다")
        for i in 0..<2 {
            #expect(sessions[i].garbageApplied <= serverSent[1 - i], "받은 누계가 상대가 보낸 것보다 크다")
            #expect(sessions[i].garbageApplied >= serverSent[1 - i] - 8, "보낸 공격이 거의 안 건너왔다")
        }
        #expect(sawGarbageRows[0] || sawGarbageRows[1], "방해 줄이 한 번도 판에 안 들어왔다")
    }
}
