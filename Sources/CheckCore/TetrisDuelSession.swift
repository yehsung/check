import Foundation

// v0.3.60 테트리스 1:1 — 한 사람 몫의 판 구동기(순수 값 타입 · 맥·폰 공용).
//
// 엔진(`TetrisGame`) 하나에 대결이 엔진 밖에서 필요한 셋을 묶는다.
//   ① 판 시계 = 단조 시계(D10). 화면 프레임이 아니라 **판 시작 뒤 흐른 실제 시간**만큼 엔진을 민다. 창을 가리거나
//      최소화해 프레임이 멎어도, 다음에 불릴 때 밀린 시간을 `maxStep` 조각으로 따라잡는다(한 번에 최대 30초).
//      화면을 숨겨 판을 멈추는 이득이 없게 하려는 것이다. 30초를 넘는 공백은 버린다 — 서버는 15초 침묵이면 이미
//      그 사람을 패로 닫으므로(`tetris_silence_ms`) 그 판은 끝난 판이다.
//   ② 가속(D7). 서버 기준 경과초 t 로 레벨 바닥을 정해 엔진에 넣는다: t < 120 → 1, 그 뒤 min(28, 10 + (t−120)/10)
//      (정수 나눗셈). 바닥은 따라잡기 조각마다 그 조각이 시작하는 판 시각으로 다시 정한다.
//   ③ 보고 차분. 보낼 때가 됐는지(준비 · 탑아웃 · 공격 누계 증가는 곧바로 · 최소 간격 0.25초 · 그 밖엔 1초 하트비트)와
//      상대 공격 누계에서 **아직 반영 안 한 차분만** 대기열에 넣는 일. 누계로 주고받으므로 응답이 겹치거나 빠져도 멱등이다.
//
// ── 시계는 주입받는다 ───────────────────────────────────────────────────────────────────
// 이 타입은 시계를 읽지 않는다. 시각이 필요한 함수는 전부 `now`(로컬 **단조** 시계의 초 — 맥은 systemUptime 류)를
// 인자로 받는다. 서버 시각(epoch ms)은 `syncStart(startAtMs:serverNowMs:localNow:)` 한 곳에서 로컬 단조 시계로 옮긴다.
// 벽시계(`Date`)를 쓰지 않는 이유: 사용자가 시계를 돌리면 판이 수 분을 건너뛰거나 멈춘다.

/// 서버 `tetris_report` 한 번에 실을 값(인자 이름은 서버 계약 `p_*` 와 한 짝).
package struct TetrisDuelReport: Equatable, Sendable {
    /// 보고 번호. 서버는 저장된 값 이하면 `stale` 로 버린다.
    package var seq: Int
    /// 보이는 판 200글자(`TetrisDuelBoard`).
    package var board: String
    /// 지운 줄 누계.
    package var lines: Int
    /// 보낸 공격 누계(단조 증가 · 서버가 상한으로 자른다).
    package var garbageSent: Int
    /// 상대 공격 중 내 대기열에 받아들인 누계.
    package var garbageApplied: Int
    /// 아직 판에 안 들어온 대기 방해 줄.
    package var pending: Int
    /// 내가 꼭대기에 닿았다(= 내 패배 신고). 서버가 믿는 몇 안 되는 주장이다(D9).
    package var toppedOut: Bool
}

/// 앱을 다시 열어 판으로 돌아올 때의 출발점 — 서버가 들고 있는 **내** 판 행(마지막으로 받아 적은 보고)이다.
package struct TetrisDuelResumePoint: Equatable, Sendable {
    /// 서버 저장 seq(다음 보고는 이 값 + 1).
    package var seq: Int
    /// 그 보고의 판 200글자.
    package var board: String
    package var lines: Int
    package var garbageSent: Int
    /// 서버가 '받아들였다'고 적어 둔 상대 공격 누계 — 이만큼은 다시 넣지 않는다.
    package var garbageApplied: Int
    package var pending: Int
    /// 그 보고가 서버에 닿은 판 경과초(`last_seen_ms − start_at_ms`). 판 시계는 여기서부터 지금까지를 따라잡는다.
    package var elapsedSeconds: TimeInterval

    package init(seq: Int, board: String, lines: Int, garbageSent: Int, garbageApplied: Int, pending: Int,
                 elapsedSeconds: TimeInterval) {
        self.seq = seq
        self.board = board
        self.lines = lines
        self.garbageSent = garbageSent
        self.garbageApplied = garbageApplied
        self.pending = pending
        self.elapsedSeconds = elapsedSeconds
    }
}

/// 지금 보고해야 하는 까닭.
package enum TetrisDuelReportReason: Equatable, Sendable {
    /// 첫 보고 = 준비 완료(서버가 둘째 준비 시각 + 3초로 판 시작을 정한다).
    case ready
    /// 탑아웃 — 곧바로(최소 간격만 지킨다).
    case toppedOut
    /// 공격 누계가 늘었다 — 곧바로(최소 간격만 지킨다).
    case attack
    /// 1초 하트비트(침묵 판정을 막고 상대 판을 받아 온다).
    case heartbeat
}

package struct TetrisDuelSession: Equatable, Sendable {

    // MARK: - 확정 상수

    /// 가속이 시작되는 판 경과초(D7).
    package static let rampStartSeconds = 120
    /// 가속이 시작될 때의 레벨 바닥.
    package static let rampStartLevel = 10
    /// 바닥이 한 레벨 오르는 데 걸리는 초.
    package static let rampSecondsPerLevel = 10
    /// 바닥의 끝(리셋 한도 2 — 벽에 못 닿아 판이 끝난다).
    package static let rampMaxLevel = 28
    /// 한 번에 따라잡는 판 시간의 상한(D10).
    package static let maxCatchUpSeconds: TimeInterval = 30
    /// 하트비트 간격.
    package static let heartbeatSeconds: TimeInterval = 1.0
    /// 곧바로 보내는 보고(공격·탑아웃) 사이의 최소 간격.
    package static let minReportGapSeconds: TimeInterval = 0.25

    /// 판 경과초 → 레벨 바닥(D7). 초는 내림한 정수로 셈한다(서버 식과 같은 정수 나눗셈).
    package static func rampLevelFloor(elapsedSeconds t: Double) -> Int {
        guard t.isFinite, t >= Double(rampStartSeconds) else { return 1 }
        // 터무니없이 큰 값에서 Int 변환이 넘치지 않게 — 그 전에 이미 바닥 끝이다.
        guard t < 1_000_000 else { return rampMaxLevel }
        let seconds = Int(t.rounded(.down))
        return min(rampMaxLevel, rampStartLevel + (seconds - rampStartSeconds) / rampSecondsPerLevel)
    }

    /// 서버 시각을 로컬 단조 시계로 옮긴 판 시작 시각. `serverNowMs` 는 응답이 만들어진 서버 시각이고 `localNow` 는
    /// 그 응답을 **받은** 로컬 시각이다 — 그래서 이 값은 언제나 참값보다 내려받는 지연만큼 늦다(이르지는 않다).
    package static func localStart(startAtMs: Double, serverNowMs: Double, localNow: TimeInterval) -> TimeInterval {
        localNow + (startAtMs - serverNowMs) / 1000
    }

    // MARK: - 상태

    /// 서버가 수락 때 뽑은 판 시드(0…2147483647). 두 사람이 같은 값으로 엔진을 새로 만든다 → 조각 순서가 같다.
    package let seed: Int
    package private(set) var game: TetrisGame
    /// 판 시계 0 의 로컬 단조 시각. nil = 서버가 아직 시작을 안 정했다(둘 다 준비 전).
    package private(set) var startAt: TimeInterval?
    /// 엔진에 흘려 준 판 시간(초). 시작 전에는 0.
    package private(set) var simulated: TimeInterval
    /// 판이 시작됐는가(엔진 `action()` 을 한 번 불렀다).
    package private(set) var started: Bool
    /// 서버가 판을 닫았다(이후로는 시계·입력·보고가 전부 멎는다).
    package private(set) var finished: Bool
    /// 따라잡기 상한을 넘어 버린 판 시간 합(진단용).
    package private(set) var droppedSeconds: TimeInterval
    /// 상대 공격 중 받아들인 누계(보고의 `garbage_applied`).
    package private(set) var garbageApplied: Int
    /// 마지막으로 낸 보고 번호.
    package private(set) var seq: Int
    /// 마지막 보고를 낸 로컬 단조 시각. nil = 아직 한 번도(= 준비 보고 전).
    package private(set) var lastReportAt: TimeInterval?
    /// 마지막 보고에 실은 공격 누계·탑아웃(차분 판정의 기준).
    package private(set) var reportedAttackSent: Int
    package private(set) var reportedToppedOut: Bool

    /// - Parameters:
    ///   - seed: 서버 `seed`.
    ///   - startingSeq: 서버에 이미 저장된 seq(앱을 다시 열어 이어 보고할 때). 다음 보고는 이 값 + 1 이다.
    ///   - garbageApplied: 서버가 이미 '받아들였다'고 적어 둔 상대 공격 누계(`me.garbage_applied`). 이만큼은 다시 넣지 않는다 —
    ///     0 에서 출발하면 앱을 다시 연 사람이 상대의 공격 이력을 통째로 한 번 더 맞는다(리뷰 RV1).
    package init(seed: Int, startingSeq: Int = 0, garbageApplied: Int = 0) {
        self.seed = seed
        game = TetrisGame(seed: UInt64(clamping: seed))
        startAt = nil
        simulated = 0
        started = false
        finished = false
        droppedSeconds = 0
        self.garbageApplied = max(0, garbageApplied)
        seq = max(0, startingSeq)
        lastReportAt = nil
        reportedAttackSent = 0
        reportedToppedOut = false
    }

    /// 앱을 다시 열어 **이미 시작한** 판으로 돌아온다 — 서버가 들고 있는 내 마지막 보고(판 200글자 · 누계)에서 판을 다시 세운다.
    ///
    /// 왜 빈 판에서 다시 시작하지 않는가(리뷰 RV1): 서버 침묵 판정(15초) 안에 앱을 껐다 켜면 거의 찬 판이 공짜로 비워진다.
    /// 판은 서버의 마지막 판 그대로(방해 줄 `G` 는 회색 표시까지), 지운 줄 · 보낸 공격 · 받아들인 공격 · 대기 방해 줄도 그 값에서
    /// 잇는다 — 보낸 공격을 0 에서 다시 세면 서버가 단조 최댓값으로 받으므로 옛 누계를 넘을 때까지 새 공격이 상대에게 안 간다.
    /// 판 시계는 **그 보고가 닿은 판 시각**(`point.elapsedSeconds`)에 서 있고, 다음 `advance` 가 지금까지의 공백을 따라잡는다
    /// (D10 — 앱이 꺼져 있던 동안에도 조각은 떨어졌다). 떨어지던 조각 · 넥스트 · 홀드 · 레벨 시계는 보고에 없어 새로 시작한다
    /// (첫 조각은 ARE 뒤에 나온다). 엔진은 고치지 않았다 — 임의 상태에서 여는 엔진 init(규칙 픽스처와 같은 문)을 쓴다.
    /// - Returns: 판 글자가 서버 CHECK 모양(200글자 · `.IJLOSTZG`)이 아니면 nil — 깨진 판을 지어내지 않는다.
    package init?(seed: Int, resumingFrom point: TetrisDuelResumePoint) {
        guard let cells = TetrisDuelBoard.decode(point.board) else { return nil }
        var board = TetrisGame.emptyBoard()
        var mask = [UInt16](repeating: 0, count: TetrisGame.totalRows)
        for (offset, row) in cells.enumerated() {
            let boardRow = TetrisGame.firstVisibleRow + offset
            for (column, cell) in row.enumerated() {
                switch cell {
                case .empty:
                    continue
                case .piece(let piece):
                    board[boardRow][column] = piece
                case .garbage:
                    // 엔진이 방해 줄을 넣을 때와 같은 모양: 찬 칸(.i) + 표시 비트.
                    board[boardRow][column] = .i
                    mask[boardRow] |= UInt16(1) << column
                }
            }
        }
        self.init(seed: seed, startingSeq: point.seq, garbageApplied: point.garbageApplied)
        game = TetrisGame(seed: UInt64(clamping: seed), board: board, active: nil,
                          phase: .are(remaining: TetrisGame.areSeconds),
                          lines: max(0, point.lines),
                          pendingGarbage: point.pending > 0 ? [point.pending] : [],
                          attackSentTotal: max(0, point.garbageSent),
                          garbageMask: mask)
        started = true
        simulated = point.elapsedSeconds.isFinite ? max(0, point.elapsedSeconds) : 0
        reportedAttackSent = game.attackSentTotal
    }

    /// 테스트 픽스처 — **이미 시작한** 판에서 출발한다(엔진 상태를 직접 준다. 판 시계 0 = `startAt`).
    package init(seed: Int, startedGame game: TetrisGame, startAt: TimeInterval, simulated: TimeInterval = 0) {
        self.init(seed: seed)
        self.game = game
        self.startAt = startAt
        self.simulated = max(0, simulated)
        started = true
    }

    // MARK: - 읽기

    /// 내가 꼭대기에 닿았다(판이 시작된 뒤의 게임 오버만 — 시작 전 엔진은 `.ready` 다).
    package var toppedOut: Bool { started && game.isGameOver }

    /// 입력을 받는 상태(시작했고 · 안 끝났고 · 탑아웃 전).
    package var isLive: Bool { started && !finished && !game.isGameOver }

    /// 판 경과초(로컬 단조 시계 기준). 시작 시각을 모르면 nil, 카운트다운 중이면 음수.
    package func matchElapsed(at now: TimeInterval) -> TimeInterval? {
        startAt.map { now - $0 }
    }

    /// 카운트다운 남은 초(시작 시각을 모르면 nil, 시작했으면 0).
    package func countdownRemaining(at now: TimeInterval) -> TimeInterval? {
        startAt.map { max(0, $0 - now) }
    }

    /// 지금 가속 바닥(화면의 "속도 올라가는 중" 판정은 `> 1`).
    package var currentLevelFloor: Int { game.levelFloor }

    // MARK: - 시계

    /// 서버가 정한 판 시작(`start_at_ms`)을 로컬 단조 시계로 옮겨 둔다. 응답마다 불러도 된다 —
    /// 추정값은 언제나 참값보다 늦으므로 **가장 이른 추정**을 남긴다(판 시계가 뒤로 가는 일은 없다).
    package mutating func syncStart(startAtMs: Double, serverNowMs: Double, localNow: TimeInterval) {
        guard startAtMs.isFinite, serverNowMs.isFinite, localNow.isFinite else { return }
        let estimate = Self.localStart(startAtMs: startAtMs, serverNowMs: serverNowMs, localNow: localNow)
        startAt = min(startAt ?? estimate, estimate)
    }

    /// 판 시계를 `now` 까지 민다. 프레임마다 불러도 되고, 프레임이 멎었다가 한참 뒤에 불러도 된다(따라잡기).
    /// 시작 시각 전이면 아무 일도 안 한다(카운트다운). 시작 시각을 처음 넘는 순간 엔진을 연다.
    package mutating func advance(to now: TimeInterval) {
        guard !finished, let startAt, now.isFinite else { return }
        let target = now - startAt
        guard target >= 0 else { return }
        if !started {
            started = true
            simulated = 0
            game.action()        // .ready → 새 판(이 한 번뿐이다 — 그 뒤 action 은 하드드롭이다)
        }
        var remaining = target - simulated
        guard remaining > 0 else { return }
        if remaining > Self.maxCatchUpSeconds {
            // 앞쪽을 버리고 **뒤쪽 30초**를 흘린다 — 그래야 바닥(가속)이 지금 시각에 맞는다.
            let skip = remaining - Self.maxCatchUpSeconds
            droppedSeconds += skip
            simulated += skip
            remaining = Self.maxCatchUpSeconds
        }
        while remaining > 1e-9 {
            if case .result = game.phase {
                simulated += remaining
                return
            }
            game.setLevelFloor(Self.rampLevelFloor(elapsedSeconds: simulated))
            let dt = min(remaining, TetrisGame.maxStep)
            game.step(dt: dt)
            simulated += dt
            remaining -= dt
        }
    }

    /// 서버가 판을 닫았다(승패·무승부 무엇이든). 눌린 키를 풀고 이후로는 멎는다.
    package mutating func finish() {
        finished = true
        game.releaseAllKeys()
    }

    // MARK: - 입력(살아 있을 때만 · 뗌은 언제나)

    package mutating func setLeftHeld(_ held: Bool) {
        guard isLive || !held else { return }
        game.setLeftHeld(held)
    }

    package mutating func setRightHeld(_ held: Bool) {
        guard isLive || !held else { return }
        game.setRightHeld(held)
    }

    package mutating func setSoftDropHeld(_ held: Bool) {
        guard isLive || !held else { return }
        game.setSoftDropHeld(held)
    }

    package mutating func rotate(clockwise: Bool) {
        guard isLive else { return }
        game.rotate(clockwise: clockwise)
    }

    /// 가로 **한 칸**(폰 끌기 · 보이스오버 이동 액션). 엔진 무수정으로, 누름과 뗌을 **같은 호출 안에서 연달아** 준다 —
    /// `updateRepeat(pressed:)` 가 이동을 즉시 하고 뗌은 이동을 안 주므로, 쌍 사이에 시간이 안 흘러 DAS(0.167초)가
    /// 만기될 수 없고 쌍이 끝나면 반복 상태가 완전히 원상복구된다.
    /// ⚠️ **쌍 사이에 `advance(to:)`·`step(dt:)` 을 끼우지 마라** — 그 순간 자동 반복이 살아나 한 걸음이 여러 칸이 된다.
    /// 솔로 폰이 같은 배선으로 먼저 증명한 자리다(`GamesPlayController.feed`).
    package mutating func moveLeftOneCell() {
        guard isLive else { return }
        game.setLeftHeld(true)
        game.setLeftHeld(false)
    }

    package mutating func moveRightOneCell() {
        guard isLive else { return }
        game.setRightHeld(true)
        game.setRightHeld(false)
    }

    /// 세로 한 칸(엔진 `softDropOneCell` — 한 칸 · 1점 · 접지 리셋 예산 안 씀 · 중력 되감기).
    /// 눌림(`setSoftDropHeld`)으로 흉내 내지 마라: 폰 제스처는 **거리**를 주고 눌린 시간을 주지 않는다.
    @discardableResult
    package mutating func softDropOneCell() -> Bool {
        guard isLive else { return false }
        return game.softDropOneCell()
    }

    package mutating func hold() {
        guard isLive else { return }
        game.holdCurrentPiece()
    }

    /// 하드드롭. 엔진 `action()` 은 `.ready`/`.result` 에서 **새 판**이라 조각이 있을 때만 부른다.
    package mutating func hardDrop() {
        guard isLive, case .running = game.phase else { return }
        game.action()
    }

    package mutating func releaseAllKeys() {
        game.releaseAllKeys()
    }

    // MARK: - 상대 공격

    /// 상대 공격 누계(서버 응답 `opponent.garbage_sent`)를 받는다. 지난번 받아들인 누계와의 **차분만** 대기열에 넣는다.
    /// 판이 받을 수 없는 때(시작 전 · 끝난 뒤)에는 누계를 올리지 않는다 — 시작 전에 온 공격은 다음 응답에서 들어간다.
    /// - Returns: 이번에 대기열에 넣은 줄 수.
    @discardableResult
    package mutating func absorbOpponentAttack(total: Int) -> Int {
        guard !finished, started else { return 0 }
        let diff = total - garbageApplied
        guard diff > 0 else { return 0 }
        guard game.receiveGarbage(lines: diff) else { return 0 }
        garbageApplied = total
        return diff
    }

    // MARK: - 보고

    /// 지금 보고할 때인가. 첫 보고는 준비(언제든 곧바로), 그 뒤로는 탑아웃·공격 누계 증가는 최소 간격(0.25초)만 지키고 곧바로,
    /// 그 밖에는 1초 하트비트다. 서버가 판을 닫은 뒤에는 보내지 않는다.
    package func reportReason(at now: TimeInterval) -> TetrisDuelReportReason? {
        guard !finished else { return nil }
        guard let last = lastReportAt else { return .ready }
        let since = now - last
        if since >= Self.minReportGapSeconds {
            if toppedOut && !reportedToppedOut { return .toppedOut }
            if game.attackSentTotal > reportedAttackSent { return .attack }
        }
        if since >= Self.heartbeatSeconds { return .heartbeat }
        return nil
    }

    /// 보고 한 벌을 만들고 장부(번호 · 시각 · 실은 누계)를 넘긴다. 실은 값은 전부 **누계**라 이 보고가 사라져도
    /// 다음 보고가 같은 사실을 다시 싣는다.
    package mutating func makeReport(at now: TimeInterval) -> TetrisDuelReport {
        seq += 1
        lastReportAt = now
        reportedAttackSent = game.attackSentTotal
        reportedToppedOut = toppedOut
        return TetrisDuelReport(seq: seq, board: TetrisDuelBoard.encode(game), lines: game.lines,
                                garbageSent: game.attackSentTotal, garbageApplied: garbageApplied,
                                pending: game.pendingGarbageLines, toppedOut: toppedOut)
    }

    /// 서버가 `stale` 로 돌려준 저장 seq 를 따라잡는다(다음 보고가 그보다 크게).
    package mutating func adoptServerSeq(_ serverSeq: Int) {
        seq = max(seq, serverSeq)
    }
}
