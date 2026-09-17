import Foundation

// AI 와 두는 1:1 오목 한 판의 **로컬 상태** — 순수 값 타입(시계·무작위는 밖에서 넣는다). 설계: docs/plan/gomoku-ai.md §1·§3.
//
// ── 규칙은 서버 1:1 과 한 벌이다 ──
// 판정은 `GomokuRules.judge` 그대로(두 벌 만들지 않는다) · 흑 선공 · 흑만 금수 · 흑 정확히 5 / 백 5 이상이면 승 ·
// 판이 차면 무승부 · 백이 둔 뒤 흑이 둘 곳이 없으면 규칙 패스 · 사람 차례 30초가 지나면 **빈칸 중 균등 무작위** 대리 착수
// (흑이면 금수 제외 — 서버 `gomoku__pick_cell`) · 연속 N회(`GomokuStore.autoPlaceLossStreak`) 대리 착수면 사람 패(abandoned),
// 단 그 수로 5목·무승부가 되면 자연 종료가 이긴다(서버 `gomoku__autoplace` 순서 그대로).
//
// ── 서버와 다른 점 ──
// 루비·전적·순위가 없다(사용자 결정). AI 차례에는 시계가 없다. 창이 안 보이면 사람 시계를 멈춘다(`pause`/`resume` —
// 기다리는 상대가 없다). 이 타입은 창을 모른다 — 멈출지는 스토어가 정한다.

/// AI 대국 한 판.
package nonisolated struct GomokuAIGame: Equatable, Sendable {
    /// 판 id 머리말. 서버 판 id 는 uuid 라 이 머리말로 시작할 수 없다 — **이 한 줄이 서버 경로 차단의 근거다**.
    package static let idPrefix = "ai-"

    /// 이 id 가 AI 판인가. 스토어의 서버 경로(조회·나가기·채팅)가 이 판정으로 요청을 막는다.
    package static func isAIMatchID(_ id: String?) -> Bool {
        id?.hasPrefix(idPrefix) ?? false
    }

    /// 판을 막 둔 결과의 거절(사람 착수). 스토어는 이것을 기존 탭 거절 문구·진단 줄로 그대로 흘린다.
    package struct Refusal: Equatable, Sendable {
        package let kind: GomokuTapRefusal
        package let reason: GomokuForbiddenReason?
    }

    package let id: String
    package let humanColor: GomokuColor
    package var aiColor: GomokuColor { humanColor.opponent }
    /// 사람 한 수 제한(초).
    package let turnSeconds: TimeInterval
    /// 연속 대리 착수 몇 번에 사람이 지는가.
    package let autoLossStreak: Int

    package private(set) var board = GomokuBoard()
    /// 기록 수(규칙 패스 포함 — 서버 move_count 와 같은 눈금).
    package private(set) var moveCount = 0
    package private(set) var lastMove: GomokuPoint?
    /// 끝나면 nil.
    package private(set) var turn: GomokuColor? = .black
    /// 사람 차례이고 시계가 돌 때만 값이 있다.
    package private(set) var deadline: Date?
    /// 사람 차례인데 시계가 멈춰 있을 때 남은 초.
    package private(set) var pausedRemaining: TimeInterval?
    package private(set) var isFinished = false
    /// **사람 기준** 결과.
    package private(set) var outcome: GomokuOutcome?
    package private(set) var endReason: GomokuEndReason?
    /// 시간이 지나 대신 놓인 사람 돌.
    package private(set) var autoPoints: Set<GomokuPoint> = []
    package private(set) var lastMoveWasAuto = false
    /// 직전 기록이 흑 규칙 패스다(백이 두면 내린다).
    package private(set) var blackPassed = false
    /// 사람이 **연속으로** 대리 착수당한 횟수. 직접 한 수 두면 0.
    package private(set) var humanAutoStreak = 0

    /// 새 판. 흑이 먼저 두므로 사람이 흑이면 곧바로 사람 시계가 돈다(멈출지는 스토어가 곧이어 정한다).
    package init(
        id: String = GomokuAIGame.idPrefix + UUID().uuidString.lowercased(),
        humanColor: GomokuColor,
        turnSeconds: TimeInterval = 30,
        autoLossStreak: Int = 3,
        now: Date
    ) {
        self.id = id
        self.humanColor = humanColor
        self.turnSeconds = turnSeconds
        self.autoLossStreak = max(1, autoLossStreak)
        startTurn(.black, now: now)
    }

    /// 검증·렌더용: 주어진 판에서 `turn` 차례로 시작한다(기록 수 = 판 위 돌 수). 규칙 판정은 새 판과 같은 길을 탄다.
    package init(
        id: String = GomokuAIGame.idPrefix + UUID().uuidString.lowercased(),
        humanColor: GomokuColor,
        board: GomokuBoard,
        turn: GomokuColor,
        humanAutoStreak: Int = 0,
        turnSeconds: TimeInterval = 30,
        autoLossStreak: Int = 3,
        now: Date
    ) {
        self.id = id
        self.humanColor = humanColor
        self.turnSeconds = turnSeconds
        self.autoLossStreak = max(1, autoLossStreak)
        self.board = board
        self.moveCount = board.stoneCount
        self.humanAutoStreak = humanAutoStreak
        startTurn(turn, now: now)
    }

    // MARK: 사람

    /// 사람 한 수. 거절이면 판은 그대로다.
    @discardableResult
    package mutating func humanPlace(_ point: GomokuPoint, now: Date) -> Refusal? {
        guard !isFinished else { return Refusal(kind: .finished, reason: nil) }
        guard turn == humanColor else { return Refusal(kind: .notYourTurn, reason: nil) }
        switch GomokuRules.judge(board: board, point: point, color: humanColor) {
        case .occupied: return Refusal(kind: .occupied, reason: nil)
        case .forbidden(let reason): return Refusal(kind: .forbidden, reason: reason)
        case .outOfRange: return Refusal(kind: .occupied, reason: nil)
        case .win:
            humanAutoStreak = 0
            placeStone(point, color: humanColor, auto: false)
            finish(winner: humanColor, reason: .five)
        case .legal:
            humanAutoStreak = 0
            placeStone(point, color: humanColor, auto: false)
            advance(after: humanColor, now: now)
        }
        return nil
    }

    /// 사람 시계가 다 됐는가(멈춰 있으면 절대 아니다).
    package func isHumanClockExpired(now: Date) -> Bool {
        guard !isFinished, turn == humanColor, let deadline else { return false }
        return now >= deadline
    }

    /// 시간이 지난 사람 차례를 대신 둔다. `randomIndex(n)` 은 0..<n 중 하나(테스트는 고정한다).
    /// 사람 차례가 아니거나 끝난 판이면 아무것도 안 한다(false).
    @discardableResult
    package mutating func autoPlaceHuman(now: Date, randomIndex: (Int) -> Int) -> Bool {
        guard !isFinished, turn == humanColor else { return false }
        humanAutoStreak += 1
        let candidates = Self.legalPoints(on: board, color: humanColor)
        if candidates.isEmpty {
            // 둘 곳이 하나도 없다(흑 금수뿐) — 서버처럼 대리 패스, 연속 횟수는 올린다(시계를 놓친 것은 맞다).
            recordPass(color: humanColor)
            startTurn(aiColor, now: now)
        } else {
            let index = min(max(randomIndex(candidates.count), 0), candidates.count - 1)
            let point = candidates[index]
            let verdict = GomokuRules.judge(board: board, point: point, color: humanColor)
            placeStone(point, color: humanColor, auto: true)
            if verdict == .win {
                finish(winner: humanColor, reason: .five)
            } else {
                advance(after: humanColor, now: now)
            }
        }
        // 자연 종료(5목·무승부)가 아니었을 때만 — 이긴 수를 빼앗지 않는다(서버 순서).
        if !isFinished, humanAutoStreak >= autoLossStreak {
            finish(winner: aiColor, reason: .abandoned)
        }
        return true
    }

    /// 기권 — 사람 패.
    package mutating func resign() {
        guard !isFinished else { return }
        finish(winner: aiColor, reason: .resign)
    }

    // MARK: AI

    /// AI 한 수. nil 은 "둘 곳 없음"이다. 규칙에 맞지 않는 수(이미 돌이 있음 · 흑 금수 · 차례 아님)면 **판을 안 바꾸고** false —
    /// 스토어가 무작위 합법 수로 대신 둔다(엔진 결함 하나로 판이 멈추지 않게).
    @discardableResult
    package mutating func applyAIMove(_ point: GomokuPoint?, now: Date) -> Bool {
        guard !isFinished, turn == aiColor else { return false }
        guard let point else {
            // 흑이 둘 곳이 정말 없을 때만 패스가 성립한다.
            guard Self.legalPoints(on: board, color: aiColor, stopAtFirst: true).isEmpty else { return false }
            recordPass(color: aiColor)
            startTurn(humanColor, now: now)
            return true
        }
        switch GomokuRules.judge(board: board, point: point, color: aiColor) {
        case .win:
            placeStone(point, color: aiColor, auto: false)
            finish(winner: aiColor, reason: .five)
            return true
        case .legal:
            placeStone(point, color: aiColor, auto: false)
            advance(after: aiColor, now: now)
            return true
        case .occupied, .forbidden, .outOfRange:
            return false
        }
    }

    /// AI 가 둘 수 있는 무작위 합법 수(엔진이 규칙 밖의 수를 냈을 때의 대타). 없으면 nil.
    package func randomAIFallback(randomIndex: (Int) -> Int) -> GomokuPoint? {
        let candidates = Self.legalPoints(on: board, color: aiColor)
        guard !candidates.isEmpty else { return nil }
        return candidates[min(max(randomIndex(candidates.count), 0), candidates.count - 1)]
    }

    // MARK: 시계 일시정지

    /// 사람 시계를 멈춘다(남은 초 보존). 돌고 있지 않으면 아무것도 안 한다.
    package mutating func pause(now: Date) {
        guard let deadline else { return }
        pausedRemaining = max(0, deadline.timeIntervalSince(now))
        self.deadline = nil
    }

    /// 멈춘 시계를 이어 간다.
    package mutating func resume(now: Date) {
        guard let remaining = pausedRemaining else { return }
        deadline = now.addingTimeInterval(remaining)
        pausedRemaining = nil
    }

    // MARK: 화면 값

    /// 기존 대국·결과 화면이 **그대로 읽는 모양**. 판돈 0 · 루비 변화 0(끝났을 때) — 화면이 AI 판이면 루비 줄을 그리지 않는다.
    package func matchState(opponent: GomokuUser = .gomokuAI) -> GomokuMatchState {
        GomokuMatchState(
            id: id, stake: 0, myColor: humanColor, opponent: opponent, board: board, lastMove: lastMove,
            moveCount: moveCount, turn: turn, deadline: deadline, isFinished: isFinished, outcome: outcome,
            endReason: endReason, rubyDelta: isFinished ? 0 : nil, blackPassed: blackPassed,
            autoPoints: autoPoints, lastMoveWasAuto: lastMoveWasAuto
        )
    }

    // MARK: 내부

    /// 빈칸 중 `color` 가 둘 수 있는 칸(행 → 열 순서). 흑은 금수(예산 초과 포함)를 뺀다.
    package static func legalPoints(on board: GomokuBoard, color: GomokuColor, stopAtFirst: Bool = false) -> [GomokuPoint] {
        var result: [GomokuPoint] = []
        for y in 0..<GomokuBoard.size {
            for x in 0..<GomokuBoard.size {
                guard let point = GomokuPoint(x: x, y: y), board[point] == nil else { continue }
                if color == .black {
                    switch GomokuRules.judge(board: board, point: point, color: .black) {
                    case .legal, .win: break
                    default: continue
                    }
                }
                result.append(point)
                if stopAtFirst { return result }
            }
        }
        return result
    }

    private mutating func placeStone(_ point: GomokuPoint, color: GomokuColor, auto: Bool) {
        board[point] = color
        moveCount += 1
        lastMove = point
        lastMoveWasAuto = auto
        blackPassed = false
        if auto { autoPoints.insert(point) } else { autoPoints.remove(point) }
    }

    private mutating func recordPass(color: GomokuColor) {
        moveCount += 1
        lastMoveWasAuto = false
        blackPassed = color == .black
    }

    /// 돌을 놓은 뒤(끝나지 않았을 때) 다음 차례를 세운다: 판이 차면 무승부, 다음이 흑인데 둘 곳이 없으면 규칙 패스.
    private mutating func advance(after color: GomokuColor, now: Date) {
        guard board.stoneCount < GomokuBoard.cellCount else {
            finish(winner: nil, reason: .boardFull)
            return
        }
        let next = color.opponent
        if next == .black, Self.legalPoints(on: board, color: .black, stopAtFirst: true).isEmpty {
            recordPass(color: .black)
            startTurn(.white, now: now)
            return
        }
        startTurn(next, now: now)
    }

    private mutating func startTurn(_ color: GomokuColor, now: Date) {
        turn = color
        pausedRemaining = nil
        deadline = color == humanColor ? now.addingTimeInterval(turnSeconds) : nil
    }

    private mutating func finish(winner: GomokuColor?, reason: GomokuEndReason) {
        isFinished = true
        turn = nil
        deadline = nil
        pausedRemaining = nil
        endReason = reason
        switch winner {
        case humanColor?: outcome = .won
        case nil: outcome = .draw
        default: outcome = .lost
        }
    }
}

extension GomokuUser {
    /// AI 상대(화면 값). id 는 uuid 가 아니라 서버 어떤 사람과도 겹치지 않는다.
    package static let gomokuAI = GomokuUser(
        id: "ai", displayName: "AI", avatarURL: nil, characterID: nil,
        isWorking: true, isCapable: true, inMatch: false
    )

    /// 이 사람이 AI 상대인가.
    package var isGomokuAI: Bool { id == GomokuUser.gomokuAI.id }
}
