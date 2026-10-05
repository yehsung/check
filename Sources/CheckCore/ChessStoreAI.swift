import Foundation

// 체스 스토어의 **AI 대국** 갈래 — 기기 혼자 두는 한 판(A1·A5: 단일 난이도).
//
// ── 서버와 섞이지 않는다 ──
// AI 판은 `ChessAIGame`(순수 값)이 권위이고 `match` 는 그 값을 옮겨 적은 화면 값이다. 서버 경로는 id 머리말("ai-")로
// 막는다: `refreshMatch(id:)`·`send(_:)`·무승부 두 문이 맨 앞에서 거르고 `pollTick` 의 상태 분기는 `!isAIMatch` 를 본다.
// 1:1 판이 열리면(`applyState` 가 `match` 를 다른 id 로 바꾸면) `match` 관찰자가 AI 판을 **조용히 버린다** —
// 1:1 이 언제나 이긴다. 로그아웃(`reset`)도 버린다.
//
// ── 합법 수의 주인이 뒤집힌다(ChessStore 머리말 ⑦) ──
// 1:1 판의 하이라이트는 서버 `legal_moves` 다. **AI 판에는 서버가 없으므로** 로컬 `ChessRules.legalMoves` 가 그 자리를
// 채운다. 그래도 **사람 차례일 때만** 채운다 — 서버가 그러하므로(상대 차례엔 null) 뷰가 두 경로에서 같은 코드를 쓴다.
//
// ── 늦게 끝난 AI 수는 버린다 ──
// AI 수는 백그라운드에서 계산되고 그 사이 기권·로비·새 판·로그아웃이 올 수 있다. 계산을 시작할 때 세대
// (`aiRuntime.generation`)·판 id·수 번호·차례를 잡고, 끝났을 때 하나라도 다르면 결과를 버린다.
//
// ── 시계는 창이 보일 때만 돈다 ──
// 창이 안 보이거나 가려지면 **쓴 시간을 그 자리에서 빼고** 멈추고(`pause`), 다시 보이면 이어 간다(`resume`).
// 기다리는 상대가 없기 때문이다 — 1:1 은 반대다(창을 닫아도 서버에서 시간이 흐른다).
// 이 타입은 창을 모른다 — 멈출지는 스토어가 정한다.

/// AI 수 선택기. 국면과 반복 장부를 받아 한 수(없으면 nil)를 돌려준다. 테스트가 결정적 가짜로 갈아 끼운다.
package typealias ChessAIMoveChooser = @Sendable (ChessPosition, [String: Int]) async -> ChessMove?

/// AI 갈래의 관찰 대상이 아닌 장부(스토어 본문에 한 줄로 붙는다 — 저장 프로퍼티는 확장에 못 둔다).
@MainActor
package final class ChessAIRuntime {
    /// 기본 선택기: 엔진을 백그라운드에서 돌리고, 기다리던 쪽이 취소되면 **엔진에도 취소를 전한다**.
    /// 오목 `GomokuAIRuntime.engineChooser` 와 같은 모양이다(mapB §7-8: 서명만 베끼고 몸통은 버린다).
    package nonisolated static let engineChooser: ChessAIMoveChooser = { position, repetitionCounts in
        let search = Task.detached(priority: .userInitiated) {
            ChessAI.bestMove(position: position, repetitionCounts: repetitionCounts,
                             isCancelled: { Task.isCancelled })
        }
        return await withTaskCancellationHandler {
            await search.value
        } onCancel: {
            search.cancel()
        }
    }

    package var chooser: ChessAIMoveChooser = ChessAIRuntime.engineChooser
    /// AI 가 즉답해도 화면에 "생각 중" 을 이만큼은 보여 준다(초). 테스트는 0.
    package var minimumThinkSeconds: TimeInterval = 0.6

    /// 판이 바뀔 때마다(시작·버림·새 AI 차례) 오른다. 늦게 끝난 계산을 버리는 기준이다.
    package private(set) var generation = 0
    /// 선택기를 부른 횟수(진단·테스트 지점).
    package private(set) var chooserCalls = 0
    fileprivate var moveTask: Task<Void, Never>?
    fileprivate var clockTask: Task<Void, Never>?

    package init() {}

    @discardableResult
    fileprivate func bump() -> Int {
        generation &+= 1
        return generation
    }

    fileprivate func noteChooserCall() { chooserCalls += 1 }

    fileprivate func cancelTasks() {
        moveTask?.cancel()
        moveTask = nil
        clockTask?.cancel()
        clockTask = nil
    }
}

/// AI 와 두는 체스 한 판의 **로컬 상태** — 순수 값 타입(시계는 밖에서 `now` 로 넣는다).
///
/// 규칙은 서버 1:1 과 **한 벌**이다: `ChessRules` 하나가 합법 수·체크·종국을 판정하고(두 벌 만들지 않는다),
/// 3회 반복은 `ChessRepetitionLedger` 가 센다. 시계는 A3 의 5분 + 한 수 3초 가산이고 **다 쓰면 패배**다(B4).
/// 서버와 다른 것: 루비·전적·순위가 없고(사용자 결정) 무승부 합의 왕복이 없다(상대가 사람이 아니다).
package nonisolated struct ChessAIGame: Equatable, Sendable {
    /// 판 id 머리말. 서버 판 id 는 uuid 라 이 머리말로 시작할 수 없다 — **이 한 줄이 서버 경로 차단의 근거다.**
    package static let idPrefix = "ai-"

    /// 이 id 가 AI 판인가. 스토어의 서버 경로(조회·착수·무승부)가 이 판정으로 요청을 막는다.
    package static func isAIMatchID(_ id: String?) -> Bool { id?.hasPrefix(idPrefix) ?? false }

    package let id: String
    package let humanColor: ChessColor
    package var aiColor: ChessColor { humanColor.opponent }
    package let incrementMs: Int

    package private(set) var position: ChessPosition
    /// 3회 반복 장부. **시작 국면도 한 번 적는다** — 초기 국면으로 세 번 돌아오는 수순이 있다(서버 `chess__rep_count` 와 같은 눈금).
    package private(set) var ledger: ChessRepetitionLedger
    package private(set) var moves: [ChessMoveRecord]
    package private(set) var whiteMsLeft: Int
    package private(set) var blackMsLeft: Int
    /// 차례가 시작된 시각. **nil 이면 시계가 멈춰 있다**(창이 안 보인다 · 판이 끝났다).
    package private(set) var turnStartedAt: Date?
    package private(set) var isFinished = false
    /// **사람 기준** 결과.
    package private(set) var outcome: ChessMatchOutcome?
    package private(set) var endReason: ChessEndReason?

    /// 끝나면 nil(1:1 과 같은 규약 — 화면이 두 경로에서 같은 코드를 쓴다).
    package var turn: ChessColor? { isFinished ? nil : position.sideToMove }
    package var plyCount: Int { moves.count }
    package var lastMove: ChessMove? { moves.last?.move }

    package func msLeft(_ color: ChessColor) -> Int { color == .white ? whiteMsLeft : blackMsLeft }

    /// 새 판. 백이 먼저 두므로 사람이 백이면 곧바로 사람 시계가 돈다(멈출지는 스토어가 곧이어 정한다).
    package init(
        id: String = ChessAIGame.idPrefix + UUID().uuidString.lowercased(),
        humanColor: ChessColor,
        position: ChessPosition = .standard,
        initialMs: Int = 300_000,
        incrementMs: Int = 3_000,
        now: Date
    ) {
        self.id = id
        self.humanColor = humanColor
        self.incrementMs = max(0, incrementMs)
        self.position = position
        self.whiteMsLeft = max(0, initialMs)
        self.blackMsLeft = max(0, initialMs)
        self.moves = []
        var ledger = ChessRepetitionLedger()
        ledger.record(position)
        self.ledger = ledger
        self.turnStartedAt = now
        // 손으로 짠 시작 국면이 이미 끝난 판일 수 있다(검증·테스트 경로) — 새 판도 같은 문으로 판정한다.
        settleIfOver()
    }

    /// 차례인 쪽의 남은 초. **음수가 될 수 있다**(깃발이 떨어진 뒤로 얼마나 지났는가).
    package func rawRemainingSeconds(_ color: ChessColor, now: Date) -> Double {
        let stored = Double(msLeft(color)) / 1000
        guard !isFinished, let started = turnStartedAt, position.sideToMove == color else { return stored }
        return stored - now.timeIntervalSince(started)
    }

    /// 차례인 쪽의 깃발이 떨어졌는가(시계가 돌고 있을 때만).
    package func isFlagged(now: Date) -> Bool {
        guard !isFinished, turnStartedAt != nil else { return false }
        return rawRemainingSeconds(position.sideToMove, now: now) <= 0
    }

    /// 깃발이 떨어진 판을 닫는다 — 판정은 **FIDE 6.9**(`ChessRules.timeoutRuling`)다. 상대가 메이트할 기물이
    /// 없으면 패가 아니라 무승부이고, 그때 사유는 `timeout_insufficient` 다(서버 CHECK 와 같은 두 글자).
    package mutating func applyFlag(now: Date) {
        guard isFlagged(now: now) else { return }
        let flagged = position.sideToMove
        switch ChessRules.timeoutRuling(position: position, flagged: flagged) {
        case .drawByInsufficientMaterial:
            finish(winner: nil, reason: .timeoutInsufficient)
        case .loss(let side):
            finish(winner: side.opponent, reason: .timeout)
        }
        // 깃발이 떨어진 쪽의 시계는 0 이다(화면이 "1초 남음" 으로 멈추지 않게).
        if flagged == .white { whiteMsLeft = 0 } else { blackMsLeft = 0 }
    }

    /// 창이 안 보이게 됐다 — **쓴 시간을 그 자리에서 빼고** 멈춘다(남은 시간은 보존된다).
    package mutating func pause(now: Date) {
        guard !isFinished, let started = turnStartedAt else { return }
        let spent = max(0, Int((now.timeIntervalSince(started) * 1000).rounded()))
        let side = position.sideToMove
        let left = max(0, msLeft(side) - spent)
        if side == .white { whiteMsLeft = left } else { blackMsLeft = left }
        turnStartedAt = nil
    }

    /// 창이 다시 보인다 — 멈춘 시계를 이어 간다.
    package mutating func resume(now: Date) {
        guard !isFinished, turnStartedAt == nil else { return }
        turnStartedAt = now
    }

    /// 한 수를 둔다(사람·AI 공용). 거절이면 그 사유를 돌려준다(nil = 받아들였다).
    ///
    /// 순서가 서버 `chess_move` 와 같다: ① 깃발 먼저 — 시간을 다 쓴 뒤의 수는 받지 않는다 ② 합법성
    /// ③ 시계 차감(가산은 **둔 뒤에** 붙는다) ④ 기록 ⑤ 판 갱신 ⑥ 종국 판정. 순서를 바꾸면 시간이 지난 뒤에
    /// 둔 수가 살아나거나 불법 수가 시계를 흘린다.
    @discardableResult
    package mutating func play(_ move: ChessMove, now: Date) -> ChessTapRefusal? {
        guard !isFinished else { return .finished }
        if isFlagged(now: now) {
            applyFlag(now: now)
            return nil                          // 판이 끝났다 — 거절이 아니라 결과다
        }
        let legal = ChessRules.legalMoves(in: position)
        guard legal.contains(move), let san = ChessRules.san(for: move, in: position, legalMoves: legal),
              let after = ChessRules.apply(move, to: position) else { return .illegalTarget }

        let side = position.sideToMove
        let spent = turnStartedAt.map { max(0, Int((now.timeIntervalSince($0) * 1000).rounded())) } ?? 0
        let left = max(0, msLeft(side) - spent) + incrementMs
        if side == .white { whiteMsLeft = left } else { blackMsLeft = left }

        moves.append(ChessMoveRecord(
            seq: moves.count + 1, color: side, move: move, san: san, fen: after.fen,
            msLeft: left, msSpent: spent))
        position = after
        ledger.record(after)
        if turnStartedAt != nil { turnStartedAt = now }
        settleIfOver()
        return nil
    }

    /// 사람이 기권했다.
    package mutating func resign() {
        guard !isFinished else { return }
        finish(winner: aiColor, reason: .resign)
    }

    /// 화면 값으로 옮긴다. `legalMoves` 는 **사람 차례일 때만** 채운다(파일 머리말).
    package func matchState(opponent: ChessUser = .chessAI) -> ChessMatchState {
        ChessMatchState(
            id: id, stake: 0, myColor: humanColor, opponent: opponent, fen: position.fen,
            position: position, plyCount: plyCount, turn: turn, lastMove: lastMove, moves: moves,
            clock: ChessServerClock(
                whiteMsLeft: whiteMsLeft, blackMsLeft: blackMsLeft, incrementMs: incrementMs,
                turnStartedAt: isFinished ? nil : turnStartedAt,
                running: turnStartedAt == nil ? nil : turn),
            isInCheck: isFinished ? false : ChessRules.isInCheck(position),
            legalMoves: turn == humanColor ? ChessRules.legalMoves(in: position) : [],
            isFinished: isFinished, outcome: outcome, endReason: endReason,
            rubyDelta: isFinished ? 0 : nil, drawOfferBy: nil, drawOfferedByMe: false)
    }

    // MARK: 내부

    /// 지금 국면이 끝난 판인가 — **`ChessRules.outcome` 하나가 판정한다**(3회 반복은 장부로 센다).
    private mutating func settleIfOver() {
        guard !isFinished, let result = ChessRules.outcome(
            position: position, repetitionCounts: ledger.repetitionCounts) else { return }
        switch result {
        case .checkmate(let winner): finish(winner: winner, reason: .checkmate)
        case .stalemate: finish(winner: nil, reason: .stalemate)
        case .insufficientMaterial: finish(winner: nil, reason: .insufficientMaterial)
        case .fiftyMoveRule: finish(winner: nil, reason: .fiftyMove)
        case .threefoldRepetition: finish(winner: nil, reason: .threefold)
        }
    }

    private mutating func finish(winner: ChessColor?, reason: ChessEndReason) {
        isFinished = true
        endReason = reason
        turnStartedAt = nil
        switch winner {
        case humanColor?: outcome = .won
        case nil: outcome = .draw
        default: outcome = .lost
        }
    }
}

extension ChessUser {
    /// AI 상대(화면 값). id 는 uuid 가 아니라 서버 어떤 사람과도 겹치지 않는다.
    /// 캐릭터는 **로봇**이다(A6 — id `robot`): 체스를 두는 상대가 기기라는 것을 그림이 말한다.
    package static let chessAI = ChessUser(
        id: "ai", displayName: "로봇", avatarURL: nil, characterID: "robot",
        isWorking: true, isCapable: true, inMatch: false)

    package var isChessAI: Bool { id == ChessUser.chessAI.id }
}

extension ChessStore {
    // MARK: 읽기

    /// 지금 들고 있는 판이 AI 판인가.
    package var isAIMatch: Bool {
        guard let game = aiGame, let match else { return false }
        return match.id == game.id
    }

    /// AI 가 둘 차례인가(화면의 "생각 중").
    package var isAIThinking: Bool {
        guard isAIMatch, let game = aiGame else { return false }
        return !game.isFinished && game.turn == game.aiColor
    }

    /// 로비에서 AI 대국을 시작할 수 있는가. 1:1 판이 열려 있거나(서버가 진행 중이라 말함 포함) 보낸 신청이
    /// 떠 있으면 안 된다 — 신청이 수락되는 순간 1:1 이 AI 판을 이기므로 두던 판이 사라진다.
    package var canStartAIMatch: Bool {
        phase == .lobby && match == nil && outgoing == nil && activeMatchID == nil && !isBusy
    }

    /// 테스트 주입점: AI 수 선택기.
    package var aiMoveChooser: ChessAIMoveChooser {
        get { aiRuntime.chooser }
        set { aiRuntime.chooser = newValue }
    }

    // MARK: 동작

    /// 로비에서 AI 대국을 시작한다. 사람이 고른 색으로 두고, AI 가 백이면 곧바로 AI 가 생각한다.
    package func startAIMatch(humanColor: ChessColor) {
        guard canStartAIMatch else {
            if match != nil || activeMatchID != nil { setNotice(ChessNoticeText.busy) }
            return
        }
        beginAIGame(humanColor: humanColor)
    }

    /// 결과 화면 [다시 두기] — 같은 색으로 새 판.
    package func restartAIMatch() {
        guard isAIMatch, let game = aiGame, game.isFinished else { return }
        beginAIGame(humanColor: game.humanColor)
    }

    /// 시계가 다 됐으면 판을 닫는다(시계 작업이 깨어나 부른다 — 테스트는 `now` 를 넣어 직접 부른다).
    package func handleAIClock(now: Date) {
        guard isAIMatch, var game = aiGame else { return }
        guard game.isFlagged(now: now) else {
            scheduleAIClock()
            return
        }
        game.applyFlag(now: now)
        commitAIGame(game)
    }

    /// 스토어 본문 `send(_:)` 의 AI 분기. 거절이면 그 사유를 돌려준다(본문이 문구·진단 줄로 흘린다).
    func moveInAIMatch(_ move: ChessMove) -> ChessTapRefusal? {
        guard var game = aiGame else { return .noMatch }
        guard game.turn == game.humanColor else { return .notYourTurn }
        if let refusal = game.play(move, now: clock()) { return refusal }
        setNotice(nil)
        commitAIGame(game)
        scheduleAITurnIfNeeded()
        return nil
    }

    /// 기권(본문 `resign` 의 앞머리).
    func resignAIMatch() {
        guard var game = aiGame, !game.isFinished else { return }
        game.resign()
        setNotice(nil)
        commitAIGame(game)
    }

    /// 창이 안 보이게 됐다 — 시계를 멈춘다.
    func pauseAIClock() {
        guard isAIMatch, var game = aiGame, game.turnStartedAt != nil else { return }
        game.pause(now: clock())
        commitAIGame(game)
    }

    /// 창이 다시 보인다 — 멈춘 시계를 이어 간다(보이지 않으면 그대로 둔다).
    func resumeAIClockIfVisible() {
        guard isAIMatch, isWindowVisible, !isWindowOccluded,
              var game = aiGame, !game.isFinished, game.turnStartedAt == nil else { return }
        game.resume(now: clock())
        commitAIGame(game)
    }

    /// AI 판을 버린다(1:1 판이 열렸다 · 로비로 · 로그아웃). `match` 는 건드리지 않는다 — 부르는 쪽이 이미 바꿨다.
    func discardAIGame() {
        aiRuntime.cancelTasks()
        aiRuntime.bump()
        if aiGame != nil { aiGame = nil }
    }

    // MARK: 내부

    private func beginAIGame(humanColor: ChessColor) {
        aiRuntime.cancelTasks()
        aiRuntime.bump()
        let game = ChessAIGame(
            humanColor: humanColor, initialMs: initialMs, incrementMs: incrementMs, now: clock())
        // 순서가 계약이다: 판을 먼저 세우고 화면 값을 옮긴다(`match` 관찰자는 id 가 같으면 버리지 않는다).
        aiGame = game
        setNotice(nil)
        commitAIGame(game)
        scheduleAITurnIfNeeded()
    }

    /// 로컬 판을 화면 값으로 옮긴다. 창이 안 보이면 시계를 곧바로 멈춘 채로 옮긴다(시작 순간·AI 수 직후 포함).
    private func commitAIGame(_ value: ChessAIGame) {
        var game = value
        if !(isWindowVisible && !isWindowOccluded), game.turnStartedAt != nil { game.pause(now: clock()) }
        if aiGame != game { aiGame = game }
        let next = game.matchState()
        if match != next { match = next }
        let nextPhase: ChessPhase = game.isFinished ? .result : .playing
        if phase != nextPhase { phase = nextPhase }
        scheduleAIClock()
    }

    /// AI 차례면 한 번 생각을 맡긴다. 끝나면 세대·판 id·수 번호·차례가 그대로일 때만 반영한다.
    private func scheduleAITurnIfNeeded() {
        guard isAIMatch, let game = aiGame, !game.isFinished, game.turn == game.aiColor else { return }
        aiRuntime.moveTask?.cancel()
        let generation = aiRuntime.bump()
        let id = game.id
        let expectedPly = game.plyCount
        let color = game.aiColor
        let position = game.position
        let counts = game.ledger.repetitionCounts
        let chooser = aiRuntime.chooser
        let minimum = aiRuntime.minimumThinkSeconds
        aiRuntime.noteChooserCall()
        aiRuntime.moveTask = Task { @MainActor [weak self] in
            let started = Date()
            let move = await chooser(position, counts)
            let remaining = minimum - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled, let self else { return }
            guard self.aiRuntime.generation == generation, let current = self.aiGame, current.id == id,
                  current.plyCount == expectedPly, current.turn == color, !current.isFinished
            else {
                Self.logger.notice("ai move dropped (stale)")
                return
            }
            self.aiRuntime.moveTask = nil
            self.applyAIMove(move)
        }
    }

    /// AI 가 낸 수를 로컬 판에 둔다. `play` 가 nil 을 내면 **판이 한 걸음 나아갔다**는 뜻이고(수를 뒀거나
    /// 깃발이 떨어져 끝났거나), 사유를 내면 아무것도 안 바뀌었다는 뜻이다.
    ///
    /// 엔진이 수를 못 내거나 규칙 밖의 수를 내면 판이 멈추지 않게 **결정적인 첫 합법 수**로 대신 둔다
    /// (`ChessRules.legalMoves` 의 순서는 결정적이다 — 무작위를 쓰면 같은 판이 실행마다 달라진다).
    private func applyAIMove(_ move: ChessMove?) {
        guard var game = aiGame else { return }
        let now = clock()
        var advanced = false
        if let move {
            if game.play(move, now: now) == nil {
                advanced = true
            } else {
                Self.logger.notice("ai move rejected, using fallback")
            }
        }
        if !advanced, !game.isFinished, let fallback = ChessRules.legalMoves(in: game.position).first {
            advanced = game.play(fallback, now: now) == nil
        }
        commitAIGame(game)
        if advanced { scheduleAITurnIfNeeded() }
    }

    /// 시계 작업을 (다시) 건다. 시계가 돌 때만 깃발 시각에 깨어난다.
    private func scheduleAIClock() {
        aiRuntime.clockTask?.cancel()
        aiRuntime.clockTask = nil
        guard isAIMatch, let game = aiGame, !game.isFinished, game.turnStartedAt != nil else { return }
        let delay = max(0, game.rawRemainingSeconds(game.position.sideToMove, now: clock())) + 0.05
        let generation = aiRuntime.generation
        aiRuntime.clockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.aiRuntime.generation == generation else { return }
            self.aiRuntime.clockTask = nil
            self.handleAIClock(now: self.clock())
        }
    }
}
