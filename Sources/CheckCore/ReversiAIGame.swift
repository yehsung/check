import Foundation

// AI 와 두는 아잉 뒤집기 한 판의 **로컬 상태** — 순수 값 타입(시계·무작위는 밖에서 넣는다). 설계: flip/SPEC.md §4.2.
// 오목 `GomokuAIGame` 과 같은 모양이다.
//
// ── 규칙은 서버 1:1 과 한 벌이다 ──
// 판정은 `ReversiRules.play` 그대로(두 벌 만들지 않는다) · 흑 선 · 상대가 둘 곳이 없으면 자동 패스(기록에 pass 한 줄) ·
// 둘 다 없으면 자연 종료(WOF 점수). 사람 차례 30초가 지나면 **사람 합법 수 가운데 균등 무작위** 자동 착수(서버 `reversi__autoplace`),
// 연속 3회 자동 착수면 사람 패(abandoned) — 단 그 세 번째 수로 판이 자연히 끝나면 자연 결과가 우선한다(V-14, 서버 `reversi__play` 순서).
// 사람 직접 착수는 연속 횟수를 0 으로 되돌리고, **자동 패스는 시계·연속 횟수 어디에도 넣지 않는다**(사용자 결정).
//
// ── 서버와 다른 점 ──
// 루비·전적·순위가 없다(사용자 결정). AI 차례에는 시계가 없다. 창이 안 보이면 사람 시계를 멈춘다(`pause`/`resume` —
// 기다리는 상대가 없다). 이 타입은 창을 모른다 — 멈출지는 스토어가 정한다.
// 사람이 패스하면 AI 차례가 연달아 온다. 오목과 달리 이것이 **정상 경로**다 — 스토어는 AI 수를 반영한 뒤 차례가 여전히 AI 면 다시 부른다.

/// AI 대국 한 판.
package nonisolated struct ReversiAIGame: Equatable, Sendable {
    /// 판 id 머리말. 서버 판 id 는 uuid 라 이 머리말로 시작할 수 없다 — **이 한 줄이 서버 경로 차단의 근거다**.
    package static let idPrefix = "ai-"

    /// 이 id 가 AI 판인가. 스토어의 서버 경로(조회·착수·기권)가 이 판정으로 요청을 막는다.
    package static func isAIMatchID(_ id: String?) -> Bool {
        id?.hasPrefix(idPrefix) ?? false
    }

    /// 사람 한 수 제한(초) — 1:1 과 같은 30초(유예 2초는 서버 왕복 몫이라 로컬 판엔 없다).
    package static let turnSeconds: TimeInterval = 30
    /// 연속 자동 착수 몇 번에 사람이 지는가(V-14).
    package static let autoLossStreak = 3

    package let id: String
    package let humanColor: ReversiColor
    package var aiColor: ReversiColor { humanColor.opponent }

    package private(set) var board: ReversiBoard
    /// 지금 둘 차례. 끝나면 nil. 진행 중이면 이 색은 늘 합법 수가 하나 이상 있다(V-09 불변식).
    package private(set) var turn: ReversiColor?
    /// 수 기록(돌·패스, seq 1 부터).
    package private(set) var plies: [ReversiPly] = []
    /// 지금 차례의 시계 기준 시각. 사람 차례의 마감은 `turnStartedAt + 30초`다 — 멈췄다 이으면 멈춘 만큼 뒤로 민다. 끝나면 nil.
    package private(set) var turnStartedAt: Date?
    /// 사람이 **연속으로** 자동 착수당한 횟수. 직접 한 수 두면 0, 자동 패스는 그대로.
    package private(set) var humanAutoStreak = 0
    package private(set) var isFinished = false
    /// 결과(색 기준). 끝나야 값이 있다.
    package private(set) var result: ReversiResult?
    package private(set) var endReason: ReversiEndReason?
    /// WOF 점수 — 자연 종료일 때만. 기권·abandoned 는 점수 없이 승패만(V-15).
    package private(set) var score: ReversiScore?
    /// 끝난 시각.
    package private(set) var finishedAt: Date?
    /// 사람 시계가 멈춰 있다(창이 안 보임). 멈춘 동안 새로 오는 사람 차례도 멈춘 채 30초를 들고 시작한다.
    package private(set) var isClockPaused = false
    /// 멈춘 동안 사람 차례의 남은 초.
    private var pausedRemaining: TimeInterval?

    /// 새 판. 흑이 먼저 두므로 사람이 흑이면 곧바로 사람 시계가 돈다(멈출지는 스토어가 곧이어 정한다).
    package init(
        humanColor: ReversiColor,
        startedAt: Date,
        id: String = ReversiAIGame.idPrefix + UUID().uuidString.lowercased()
    ) {
        self.id = id
        self.humanColor = humanColor
        self.board = .start
        startTurn(.black, at: startedAt)
    }

    /// 검증·렌더용: 주어진 판에서 `turn` 차례로 시작한다(기록은 빈 채로). `turn` 이 둘 곳이 없으면 V-09 대로 바로잡는다 —
    /// 상대에게 수가 있으면 `turn` 의 패스 한 줄을 남기고 상대 차례, 둘 다 없으면 자연 종료.
    package init(
        humanColor: ReversiColor,
        board: ReversiBoard,
        turn: ReversiColor,
        startedAt: Date,
        humanAutoStreak: Int = 0,
        id: String = ReversiAIGame.idPrefix + UUID().uuidString.lowercased()
    ) {
        self.id = id
        self.humanColor = humanColor
        self.board = board
        self.humanAutoStreak = max(0, humanAutoStreak)
        if ReversiRules.hasLegalMove(board, color: turn) {
            startTurn(turn, at: startedAt)
        } else {
            foldStuckTurn(turn, at: startedAt)
        }
    }

    // MARK: 화면 값

    /// 기록 수(패스 포함) — 서버 move_count 와 같은 눈금.
    package var moveCount: Int { plies.count }
    package var counts: ReversiCounts { board.counts }
    /// 이긴 색. 진행 중·무승부면 nil.
    package var winner: ReversiColor? { result?.winner }
    /// 마지막으로 놓인 돌의 칸(패스는 건너뛴다).
    package var lastStoneIdx: Int? { plies.last(where: { $0.kind == .stone })?.idx }
    /// 시간 초과로 대신 놓인 돌의 칸들.
    package var autoStones: Set<Int> { Set(plies.compactMap { $0.auto ? $0.idx : nil }) }
    /// 지금 차례의 합법 수(오름차순). 끝났으면 [].
    package var legalMoves: [Int] {
        guard let turn else { return [] }
        return ReversiRules.legalMoves(board, color: turn)
    }

    /// 사람 차례의 마감. 사람 차례가 아니거나 · 끝났거나 · 시계가 멈춰 있으면 nil.
    package func humanDeadline() -> Date? {
        guard !isFinished, turn == humanColor, !isClockPaused, let turnStartedAt else { return nil }
        return turnStartedAt.addingTimeInterval(Self.turnSeconds)
    }

    /// 사람 차례의 남은 초(멈춰 있으면 멈춘 값). 사람 차례가 아니거나 끝났으면 nil.
    package func humanRemaining(at now: Date) -> TimeInterval? {
        guard !isFinished, turn == humanColor else { return nil }
        if isClockPaused { return pausedRemaining ?? Self.turnSeconds }
        guard let deadline = humanDeadline() else { return nil }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// 사람 시계가 다 됐는가(멈춰 있으면 절대 아니다). 스토어가 이것을 보고 `autoPlaceHuman` 을 부른다.
    package func isHumanClockExpired(at now: Date) -> Bool {
        guard let deadline = humanDeadline() else { return false }
        return now >= deadline
    }

    // MARK: 사람

    /// 사람 한 수. 불법이면 까닭만 돌려주고 판은 그대로다. 끝났거나 사람 차례가 아니면 `.outOfRange`(둘 수 없는 칸).
    package mutating func playHuman(_ idx: Int, at now: Date) -> Result<ReversiMoveOutcome, ReversiIllegalReason> {
        guard !isFinished, turn == humanColor else { return .failure(.outOfRange) }
        switch ReversiRules.play(board, color: humanColor, idx: idx) {
        case .failure(let reason):
            return .failure(reason)
        case .success(let outcome):
            humanAutoStreak = 0
            record(outcome, color: humanColor, idx: idx, auto: false, at: now)
            return .success(outcome)
        }
    }

    /// 시간이 지난 사람 차례를 대신 둔다(사람 합법 수 가운데 `randomIndex(n)` 번째, 0..<n — 테스트는 고정한다).
    /// 연속 횟수 +1, 3 이 되면 사람 패(abandoned) — 단 그 수로 판이 자연히 끝나면 자연 결과가 우선한다.
    /// 놓인 칸을 돌려준다. 사람 차례가 아니거나 끝난 판이면 아무것도 안 하고 nil. 마감이 지났는지는 부르는 쪽이 본다.
    @discardableResult
    package mutating func autoPlaceHuman(at now: Date, randomIndex: (Int) -> Int) -> Int? {
        guard !isFinished, turn == humanColor else { return nil }
        let candidates = ReversiRules.legalMoves(board, color: humanColor)
        guard !candidates.isEmpty else {
            // 불변식(차례 주인은 늘 합법 수 ≥ 1)이 깨졌다 — 판을 죽이지 않고 V-09 로 접는다(SPEC §2.2).
            assertionFailure("ReversiAIGame: 사람 차례인데 둘 곳이 없다")
            foldStuckTurn(humanColor, at: now)
            return nil
        }
        let idx = candidates[min(max(randomIndex(candidates.count), 0), candidates.count - 1)]
        guard case .success(let outcome) = ReversiRules.play(board, color: humanColor, idx: idx) else { return nil }
        humanAutoStreak += 1
        record(outcome, color: humanColor, idx: idx, auto: true, at: now)
        // 자연 종료가 아니었을 때만 — 판을 끝낸 수를 빼앗지 않는다(서버 순서).
        if !isFinished, humanAutoStreak >= Self.autoLossStreak {
            finish(winner: aiColor, reason: .abandoned, at: now)
        }
        return idx
    }

    /// 기권 — 사람 패(점수 없음).
    package mutating func resign(at now: Date) {
        guard !isFinished else { return }
        finish(winner: aiColor, reason: .resign, at: now)
    }

    // MARK: AI

    /// AI 한 수. 규칙 밖의 수(범위 밖·이미 돌·못 뒤집음·AI 차례 아님)면 **판을 안 바꾸고** false —
    /// 부르는 쪽이 `randomAIFallback` 으로 대신 둔다(엔진 결함 하나로 판이 멈추지 않게).
    @discardableResult
    package mutating func playAI(_ idx: Int, at now: Date) -> Bool {
        guard !isFinished, turn == aiColor else { return false }
        guard case .success(let outcome) = ReversiRules.play(board, color: aiColor, idx: idx) else { return false }
        record(outcome, color: aiColor, idx: idx, auto: false, at: now)
        return true
    }

    /// AI 차례의 무작위 합법 수(엔진이 규칙 밖의 수를 냈을 때의 대타). AI 차례가 아니면 nil.
    package func randomAIFallback(randomIndex: (Int) -> Int) -> Int? {
        guard !isFinished, turn == aiColor else { return nil }
        let candidates = ReversiRules.legalMoves(board, color: aiColor)
        guard !candidates.isEmpty else { return nil }
        return candidates[min(max(randomIndex(candidates.count), 0), candidates.count - 1)]
    }

    // MARK: 시계 일시정지

    /// 사람 시계를 멈춘다(남은 초 보존). 이미 멈췄거나 끝났으면 아무것도 안 한다.
    /// AI 차례에 멈춰도 깃발은 선다 — 그 뒤 사람 차례가 오면 멈춘 채(30초) 시작한다.
    package mutating func pause(at now: Date) {
        guard !isFinished, !isClockPaused else { return }
        isClockPaused = true
        if turn == humanColor, let turnStartedAt {
            pausedRemaining = max(0, turnStartedAt.addingTimeInterval(Self.turnSeconds).timeIntervalSince(now))
        } else {
            pausedRemaining = nil
        }
    }

    /// 멈춘 시계를 이어 간다: 사람 차례면 마감 = 지금 + 남은 초(`turnStartedAt` 을 그만큼 뒤로 민다).
    package mutating func resume(at now: Date) {
        guard isClockPaused else { return }
        isClockPaused = false
        if !isFinished, turn == humanColor {
            let remaining = pausedRemaining ?? Self.turnSeconds
            turnStartedAt = now.addingTimeInterval(remaining - Self.turnSeconds)
        }
        pausedRemaining = nil
    }

    // MARK: 내부

    /// 합법 수 하나를 기록하고 다음 차례를 세운다. 상대 자동 패스면 그 사람의 pass 줄(auto=false)을 남기고 둔 사람이 이어 둔다 —
    /// 패스는 시계·연속 횟수를 건드리지 않는다(이어 두는 사람의 새 차례가 지금부터 시작할 뿐이다).
    private mutating func record(_ outcome: ReversiMoveOutcome, color: ReversiColor, idx: Int, auto: Bool, at now: Date) {
        board = outcome.board
        plies.append(ReversiPly(seq: plies.count + 1, color: color, kind: .stone, idx: idx, flipped: outcome.flipped, auto: auto))
        if outcome.passed {
            plies.append(ReversiPly(seq: plies.count + 1, color: color.opponent, kind: .pass, idx: nil, flipped: [], auto: false))
        }
        if let next = outcome.next {
            startTurn(next, at: now)
        } else {
            finishNaturally(at: now)
        }
    }

    /// 차례 주인이 둘 곳이 없을 때(불변식 위반·검증용 시작 판)의 V-09 복구: 상대에게 수가 있으면 패스 한 줄 + 상대 차례,
    /// 둘 다 없으면 자연 종료. 연속 횟수는 건드리지 않는다.
    private mutating func foldStuckTurn(_ color: ReversiColor, at now: Date) {
        if ReversiRules.hasLegalMove(board, color: color.opponent) {
            plies.append(ReversiPly(seq: plies.count + 1, color: color, kind: .pass, idx: nil, flipped: [], auto: false))
            startTurn(color.opponent, at: now)
        } else {
            finishNaturally(at: now)
        }
    }

    private mutating func startTurn(_ color: ReversiColor, at now: Date) {
        turn = color
        turnStartedAt = now
        pausedRemaining = (isClockPaused && color == humanColor) ? Self.turnSeconds : nil
    }

    private mutating func finishNaturally(at now: Date) {
        let natural = ReversiRules.wofScore(board)
        score = natural
        result = natural.result
        endReason = ReversiEndReason(ReversiRules.endKindOfFinished(board))
        close(at: now)
    }

    private mutating func finish(winner: ReversiColor, reason: ReversiEndReason, at now: Date) {
        score = nil
        result = ReversiResult(winner: winner)
        endReason = reason
        close(at: now)
    }

    private mutating func close(at now: Date) {
        isFinished = true
        turn = nil
        turnStartedAt = nil
        pausedRemaining = nil
        finishedAt = now
    }
}
