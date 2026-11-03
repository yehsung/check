import Foundation

// 아잉 뒤집기 AI 연습 판(로컬) — 스토어 확장. 계약은 설계서 FLIP/SPEC.md §4.4 · DEC:20.
//
// ── 서버와 섞이지 않는다 ──
// 루비·기록 없음 · 단일 난이도 · 생각 상한 1.5초 · 서버 변경 없음. AI 판은 `ReversiAIGame`(로컬 값)이 권위이고 `match` 는
// 그 값을 옮겨 적은 화면 값이다(`isAI`). 서버 경로는 `"ai-"` id 머리말과 `isAI` 로 막는다 — `refreshMatch(id:)` 가 맨 앞에서
// 거르고, `syncOnce`·`pollTick`·`windowDidShow` 는 AI 판을 진행 중 1:1 판으로 보지 않으며, `onMatchFinished` 는 AI 판에 안 운다.
// 1:1 판이 서면(`applyState` 가 `match` 를 다른 id 로 바꾸면) `match` 관찰자가 AI 판을 **조용히 버린다** — 1:1 이 언제나 이긴다.
//
// ── 늦게 끝난 AI 수는 버린다 ──
// AI 수는 백그라운드에서 계산되고 그 사이 기권·로비·새 판·로그아웃이 올 수 있다. 계산을 시작할 때 세대(`aiRuntime.generation`)·
// 판 id·기록 수·차례를 잡고, 끝났을 때 하나라도 다르면 결과를 버린다.
//
// ── 사람 시계는 창이 보일 때만 돈다 ──
// 창이 안 보이거나 가려지면 멈추고(남은 초 보존), 다시 보이면 이어 간다. 기다리는 상대가 없기 때문이다.
// 사람 차례 30초가 지나면 사람 합법 수 가운데 무작위 자동 착수 · 연속 3회면 패(자연 종료 우선) — `ReversiAIGame` 이 판정한다.
//
// ── 사람이 패스하면 AI 차례가 이어진다 ──
// 오목과 달리 이것이 **정상 경로**다 — AI 수를 반영한 뒤 차례가 여전히 AI 면 `scheduleAITurnIfNeeded` 가 다시 부른다.

/// AI 갈래의 관찰 대상이 아닌 장부(스토어 본문에 한 줄로 붙는다 — 저장 프로퍼티는 확장에 못 둔다).
@MainActor
package final class ReversiAIRuntime {
    /// 기본 선택기: 엔진을 백그라운드에서 돌리고, 기다리던 쪽이 취소되면 엔진에도 취소를 전한다.
    package nonisolated static let engineChooser: ReversiAIMoveChooser = { board, color in
        let search = Task.detached(priority: .userInitiated) {
            ReversiAI.bestMove(board: board, toMove: color, isCancelled: { Task.isCancelled })
        }
        return await withTaskCancellationHandler {
            await search.value
        } onCancel: {
            search.cancel()
        }
    }

    package var chooser: ReversiAIMoveChooser = ReversiAIRuntime.engineChooser
    /// AI 가 즉답해도 화면에 "생각 중"을 이만큼은 보여 준다(초). 시험은 0.
    package var minimumThinkSeconds: TimeInterval = 0.6
    /// 0..<n 중 하나. 사람 자동 착수·엔진 대타·무작위 색이 쓴다(시험은 고정한다).
    package var randomIndex: @Sendable (Int) -> Int = { Int.random(in: 0..<max(1, $0)) }

    /// 판이 바뀔 때마다(시작·버림·새 AI 차례) 오른다. 늦게 끝난 계산을 버리는 기준.
    package private(set) var generation = 0
    /// 선택기를 부른 횟수(진단·시험 지점).
    package private(set) var chooserCalls = 0
    fileprivate var moveTask: Task<Void, Never>?
    fileprivate var clockTask: Task<Void, Never>?

    package init() {}

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

extension ReversiUser {
    /// AI 상대(화면 값). id 는 uuid 가 아니라 서버 어떤 사람과도 겹치지 않는다(체스 로봇과 같은 얼굴).
    package static let reversiAI = ReversiUser(
        id: "ai", displayName: "로봇", characterID: "robot", isWorking: true, isCapable: true)
}

extension ReversiStore {
    // MARK: 읽기

    /// 지금 들고 있는 판이 AI 판인가(로컬 판과 화면 값이 같은 id).
    package var isAIMatch: Bool {
        guard let game = aiGame, let match else { return false }
        return match.id == game.id
    }

    /// AI 가 지금 생각 중인가(AI 판 · 안 끝남 · AI 차례). 선수 카드가 "생각 중"을 그린다.
    package var isAIThinking: Bool {
        guard let match, match.isAI, !match.isFinished, let turn = match.turn else { return false }
        return turn == match.myColor.opponent
    }

    /// 로비에서 AI 대국을 시작할 수 있는가. 1:1 판이 열려 있거나(서버가 진행 중이라 말함 포함) 보낸 신청이 떠 있으면
    /// 안 된다 — 신청이 수락되는 순간 1:1 이 AI 판을 이기므로 두던 판이 사라진다.
    package var canStartAIMatch: Bool {
        phase == .lobby && match == nil && outgoing == nil && activeMatchID == nil && !isBusy
    }

    /// 시험 주입점: AI 수 선택기.
    package var aiMoveChooser: ReversiAIMoveChooser {
        get { aiRuntime.chooser }
        set { aiRuntime.chooser = newValue }
    }

    // MARK: 동작

    /// AI 판을 연다. `humanColor` nil = 무작위. AI 가 흑이면 곧바로 AI 가 생각한다.
    package func startAIMatch(humanColor: ReversiColor?) {
        guard canStartAIMatch else {
            if match != nil || activeMatchID != nil { setNotice(ReversiNoticeText.busy) }
            return
        }
        let color = humanColor ?? (aiRuntime.randomIndex(2) == 0 ? .black : .white)
        beginAIGame(humanColor: color)
    }

    /// 같은 색으로 새 AI 판(결과 카드 [다시 두기]).
    package func restartAIMatch() {
        guard isAIMatch, let game = aiGame, game.isFinished else { return }
        beginAIGame(humanColor: game.humanColor)
    }

    /// 사람 시계가 다 됐으면 대신 둔다(시계 작업이 깨어나 부른다 — 시험은 `now` 를 넣어 직접 부른다).
    package func handleAIClock(now: Date) {
        guard isAIMatch, var game = aiGame else { return }
        guard game.isHumanClockExpired(at: now) else {
            scheduleAIClock()
            return
        }
        game.autoPlaceHuman(at: now, randomIndex: aiRuntime.randomIndex)
        commitAIGame(game)
        setNotice(ReversiNoticeText.autoPlaced)
        scheduleAITurnIfNeeded()
    }

    // MARK: 스토어 본문의 앞머리 분기가 부르는 문

    /// 사람 착수(본문 `place` 의 거절 가드를 **다 지난 뒤**). 규칙 밖이면 그 까닭을 문구로 남긴다.
    func placeInAIMatch(_ idx: Int) {
        guard var game = aiGame else { return }
        switch game.playHuman(idx, at: clock()) {
        case .failure(let reason):
            setNotice(ReversiNoticeText.illegal(reason))
        case .success:
            setNotice(nil)
            commitAIGame(game)
            scheduleAITurnIfNeeded()
        }
    }

    /// 기권(본문 `resign` 의 앞머리).
    func resignAIMatch() {
        guard var game = aiGame, !game.isFinished else { return }
        game.resign(at: clock())
        setNotice(nil)
        commitAIGame(game)
    }

    /// 창이 안 보이게 됐다 — 사람 시계를 멈춘다(AI 차례여도 깃발을 세워 다음 사람 차례가 멈춘 채 시작한다).
    func pauseAIClock() {
        guard isAIMatch, var game = aiGame, !game.isFinished, !game.isClockPaused else { return }
        game.pause(at: clock())
        commitAIGame(game)
    }

    /// 창이 다시 보인다 — 멈춘 시계를 이어 간다(보이지 않거나 가려져 있으면 그대로 둔다).
    func resumeAIClockIfVisible() {
        guard isAIMatch, isWindowVisible, !isWindowOccluded, var game = aiGame, game.isClockPaused else { return }
        game.resume(at: clock())
        commitAIGame(game)
    }

    /// AI 판을 버린다(1:1 판이 열렸다 · 로비로 · 로그아웃). `match` 는 건드리지 않는다 — 부르는 쪽이 이미 바꿨다.
    func discardAIGame() {
        aiRuntime.cancelTasks()
        _ = aiRuntime.bump()
        if aiGame != nil { aiGame = nil }
    }

    // MARK: 내부

    private func beginAIGame(humanColor: ReversiColor) {
        aiRuntime.cancelTasks()
        _ = aiRuntime.bump()
        let game = ReversiAIGame(humanColor: humanColor, startedAt: clock())
        // 순서가 계약이다: 판을 먼저 세우고 화면 값을 옮긴다(`match` 관찰자는 id 가 같으면 버리지 않는다).
        aiGame = game
        setNotice(nil)
        commitAIGame(game)
        scheduleAITurnIfNeeded()
    }

    /// 로컬 판을 화면 값으로 옮긴다. 창이 안 보이면 사람 시계를 곧바로 멈춘 채로 옮긴다(시작 순간·AI 수 직후 포함).
    private func commitAIGame(_ value: ReversiAIGame) {
        var game = value
        if !(isWindowVisible && !isWindowOccluded), !game.isFinished, !game.isClockPaused { game.pause(at: clock()) }
        if aiGame != game { aiGame = game }
        let previous = match
        let next = Self.aiMatchState(game)
        if match != next { match = next }
        noteBoardProgress(previous: previous, next: next)
        let nextPhase: ReversiPhase = game.isFinished ? .result : .playing
        if phase != nextPhase { phase = nextPhase }
        scheduleAIClock()
    }

    /// AI 판 → 화면 값(순수). 루비·관전자 없음, 상대는 로봇. 마감은 사람 차례에 시계가 돌 때만 선다.
    package nonisolated static func aiMatchState(_ game: ReversiAIGame) -> ReversiMatchState {
        let ai = ReversiUser.reversiAI
        return ReversiMatchState(
            id: game.id, isAI: true, status: game.isFinished ? .finished : .active, stake: 0,
            myColor: game.humanColor, opponent: ai,
            blackUser: game.aiColor == .black ? ai : nil, whiteUser: game.aiColor == .white ? ai : nil,
            board: game.board, moveCount: game.moveCount, turn: game.turn, turnStartedAt: game.turnStartedAt,
            deadline: game.humanDeadline(), legalMoves: game.turn == game.humanColor ? game.legalMoves : [],
            plies: game.plies, lastStoneIdx: game.lastStoneIdx, autoStones: game.autoStones, counts: game.counts,
            score: game.score, result: game.result, endReason: game.endReason, winner: game.winner,
            myAutoStreak: game.humanAutoStreak, opponentAutoStreak: 0,
            autoAbandonStreak: ReversiAIGame.autoLossStreak, watchers: 0)
    }

    /// AI 차례면 한 번 생각을 맡긴다. 끝나면 세대·판 id·기록 수·차례가 그대로일 때만 반영한다.
    func scheduleAITurnIfNeeded() {
        guard isAIMatch, let game = aiGame, !game.isFinished, game.turn == game.aiColor else { return }
        aiRuntime.moveTask?.cancel()
        let generation = aiRuntime.bump()
        let id = game.id
        let expectedCount = game.moveCount
        let color = game.aiColor
        let board = game.board
        let chooser = aiRuntime.chooser
        let minimum = aiRuntime.minimumThinkSeconds
        aiRuntime.noteChooserCall()
        aiRuntime.moveTask = Task { @MainActor [weak self] in
            let started = Date()
            let move = await chooser(board, color)
            let remaining = minimum - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled, let self else { return }
            guard self.aiRuntime.generation == generation, let current = self.aiGame, current.id == id,
                  current.moveCount == expectedCount, current.turn == color, !current.isFinished
            else {
                Self.logger.notice("ai move dropped (stale)")
                return
            }
            self.aiRuntime.moveTask = nil
            self.applyAIMove(move)
        }
    }

    private func applyAIMove(_ move: Int?) {
        guard var game = aiGame else { return }
        let now = clock()
        var placed = false
        if let move { placed = game.playAI(move, at: now) }
        if !placed {
            // 엔진이 규칙 밖의 수를 냈다(또는 nil) — 판이 멈추지 않게 무작위 합법 수로 대신 둔다(진단 줄 하나).
            Self.logger.notice("ai move rejected, using fallback")
            guard let fallback = game.randomAIFallback(randomIndex: aiRuntime.randomIndex),
                  game.playAI(fallback, at: now) else { return }
        }
        commitAIGame(game)
        // 사람이 둘 곳이 없으면(자동 패스) AI 차례가 이어진다 — 정상 경로다.
        scheduleAITurnIfNeeded()
    }

    /// 사람 시계 작업을 (다시) 건다. 시계가 돌 때만 마감에 깨어난다.
    private func scheduleAIClock() {
        aiRuntime.clockTask?.cancel()
        aiRuntime.clockTask = nil
        guard isAIMatch, let game = aiGame, let deadline = game.humanDeadline() else { return }
        let delay = max(0, deadline.timeIntervalSince(clock())) + 0.05
        let generation = aiRuntime.generation
        aiRuntime.clockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.aiRuntime.generation == generation else { return }
            self.aiRuntime.clockTask = nil
            self.handleAIClock(now: self.clock())
        }
    }
}
