import Foundation

// 오목 스토어의 **AI 대국** 갈래 — 설계: docs/plan/gomoku-ai.md §4.
//
// ── 서버와 섞이지 않는다 ──
// AI 판은 `GomokuAIGame`(로컬 값)이 권위이고 `match` 는 그 값을 옮겨 적은 화면 값이다. 서버 경로는 id 머리말("ai-")로 막는다:
// `refreshMatch(id:)`·`leaveMatch`·채팅 두 문이 맨 앞에서 거르고, 동기화·폴링은 AI 판을 진행 중 판으로 보지 않는다.
// 1:1 판이 서버에서 열리면(`applyState` 가 `match` 를 다른 id 로 바꾸면) `match` 관찰자가 AI 판을 **조용히 버린다** —
// 1:1 이 언제나 이긴다. 로그아웃(`reset`)도 버린다.
//
// ── 늦게 끝난 AI 수는 버린다 ──
// AI 수는 백그라운드에서 계산되고, 그 사이 기권·로비·새 판·로그아웃이 올 수 있다. 계산을 시작할 때 세대(`aiRuntime.generation`)·
// 판 id·기록 수·차례를 잡고, 끝났을 때 하나라도 다르면 결과를 버린다(1:1 의 resetGeneration 과 같은 결의 방어).
//
// ── 사람 시계는 창이 보일 때만 돈다 ──
// 창이 안 보이거나 가려지면 멈추고(남은 초 보존), 다시 보이면 이어 간다. 기다리는 상대가 없기 때문이다.

/// AI 수 선택기. 판과 둘 색을 받아 한 수(없으면 nil)를 돌려준다. 테스트가 결정적 가짜로 갈아 끼운다.
package typealias GomokuAIMoveChooser = @Sendable (GomokuBoard, GomokuColor) async -> GomokuPoint?

/// AI 갈래의 관찰 대상이 아닌 장부(스토어 본문에 한 줄로 붙는다 — 저장 프로퍼티는 확장에 못 둔다).
@MainActor
package final class GomokuAIRuntime {
    /// 기본 선택기: 엔진을 백그라운드에서 돌리고, 기다리던 쪽이 취소되면 엔진에도 취소를 전한다.
    package nonisolated static let engineChooser: GomokuAIMoveChooser = { board, color in
        let search = Task.detached(priority: .userInitiated) {
            GomokuAI.bestMove(board: board, toMove: color, isCancelled: { Task.isCancelled })
        }
        return await withTaskCancellationHandler {
            await search.value
        } onCancel: {
            search.cancel()
        }
    }

    package var chooser: GomokuAIMoveChooser = GomokuAIRuntime.engineChooser
    /// AI 가 즉답해도 화면에 "생각 중"을 이만큼은 보여 준다(초). 테스트는 0.
    package var minimumThinkSeconds: TimeInterval = 0.6
    /// 0..<n 중 하나. 대리 착수·엔진 대타가 쓴다(테스트는 고정한다).
    package var randomIndex: @Sendable (Int) -> Int = { Int.random(in: 0..<max(1, $0)) }

    /// 판이 바뀔 때마다(시작·버림·새 AI 차례) 오른다. 늦게 끝난 계산을 버리는 기준.
    package private(set) var generation = 0
    /// 선택기를 부른 횟수(진단·테스트 지점).
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

extension GomokuStore {
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

    /// 로비에서 AI 대국을 시작할 수 있는가. 1:1 판이 열려 있거나(서버가 진행 중이라 말함 포함) 보낸 신청이 떠 있으면 안 된다 —
    /// 신청이 수락되는 순간 1:1 이 AI 판을 이기므로 두던 판이 사라진다.
    package var canStartAIMatch: Bool {
        phase == .lobby && match == nil && outgoing == nil && activeMatchID == nil && !isBusy
    }

    /// 테스트 주입점: AI 수 선택기.
    package var aiMoveChooser: GomokuAIMoveChooser {
        get { aiRuntime.chooser }
        set { aiRuntime.chooser = newValue }
    }

    // MARK: 동작

    /// 로비에서 AI 대국을 시작한다. 사람이 고른 색으로 두고, AI 가 흑이면 곧바로 AI 가 생각한다.
    package func startAIMatch(humanColor: GomokuColor) {
        guard canStartAIMatch else {
            if match != nil || activeMatchID != nil { setAINotice(GomokuNoticeText.busy) }
            return
        }
        beginAIGame(humanColor: humanColor)
    }

    /// 결과 화면 [다시 두기] — 같은 색으로 새 판.
    package func restartAIMatch() {
        guard isAIMatch, let game = aiGame, game.isFinished else { return }
        beginAIGame(humanColor: game.humanColor)
    }

    /// 사람 시계가 다 됐으면 대신 둔다(시계 작업이 깨어나 부른다 — 테스트는 `now` 를 넣어 직접 부른다).
    package func handleAIClock(now: Date) {
        guard isAIMatch, var game = aiGame else { return }
        guard game.isHumanClockExpired(now: now) else {
            scheduleAIClock()
            return
        }
        game.autoPlaceHuman(now: now, randomIndex: aiRuntime.randomIndex)
        commitAIGame(game)
        setAINotice(GomokuNoticeText.autoPlaced)
        scheduleAITurnIfNeeded()
    }

    // MARK: 스토어 본문의 앞머리 분기가 부르는 문

    /// 사람 착수(본문 `place` 의 거절 가드를 **다 지난 뒤**). 거절이면 그 사유를 돌려준다(본문이 기존 문구·진단 줄로 흘린다).
    func placeInAIMatch(_ point: GomokuPoint) -> GomokuAIGame.Refusal? {
        guard var game = aiGame else { return GomokuAIGame.Refusal(kind: .noMatch, reason: nil) }
        if let refusal = game.humanPlace(point, now: clock()) { return refusal }
        setAINotice(nil)
        commitAIGame(game)
        scheduleAITurnIfNeeded()
        return nil
    }

    /// 기권(본문 `resign` 의 앞머리).
    func resignAIMatch() {
        guard var game = aiGame, !game.isFinished else { return }
        game.resign()
        setAINotice(nil)
        commitAIGame(game)
    }

    /// 결과 화면 [로비로](본문 `backToLobby` 의 앞머리). 끝난 AI 판만 내린다 — 나머지(화면 전환·안내 지우기·로비 재조회)는
    /// 본문이 1:1 과 같은 길로 이어서 한다. **진행 중인 판이면 아무것도 안 한다**(본문의 `isFinished` 가드가 그대로 막는다 —
    /// 빠져나가는 길은 기권뿐, 1:1 과 같다). 1:1 전용 장부(dismissedMatchIDs·나가기·lastOpponent)는 AI 판을 모른다.
    func backToLobbyFromAIMatch() {
        guard let game = aiGame, game.isFinished else { return }
        match = nil   // 관찰자가 AI 판을 버린다
    }

    /// 창이 안 보이게 됐다 — 사람 시계를 멈춘다.
    func pauseAIClock() {
        guard isAIMatch, var game = aiGame, game.deadline != nil else { return }
        game.pause(now: clock())
        commitAIGame(game)
    }

    /// 창이 다시 보인다 — 멈춘 시계를 이어 간다(보이지 않으면 그대로 둔다).
    func resumeAIClockIfVisible() {
        guard isAIMatch, isWindowVisible, !isWindowOccluded, var game = aiGame, game.pausedRemaining != nil else { return }
        game.resume(now: clock())
        commitAIGame(game)
    }

    /// AI 판을 버린다(1:1 판이 열렸다 · 로비로 · 로그아웃). `match` 는 건드리지 않는다 — 부르는 쪽이 이미 바꿨다.
    func discardAIGame() {
        aiRuntime.cancelTasks()
        _ = aiRuntime.bump()
        if aiGame != nil { aiGame = nil }
    }

    // MARK: 내부

    private func beginAIGame(humanColor: GomokuColor) {
        aiRuntime.cancelTasks()
        _ = aiRuntime.bump()
        let game = GomokuAIGame(
            humanColor: humanColor, turnSeconds: TimeInterval(turnSeconds),
            autoLossStreak: autoAbandonStreak, now: clock()
        )
        // 순서가 계약이다: 판을 먼저 세우고 화면 값을 옮긴다(`match` 관찰자는 id 가 같으면 버리지 않는다).
        aiGame = game
        setAINotice(nil)
        commitAIGame(game)
        scheduleAITurnIfNeeded()
    }

    /// 로컬 판을 화면 값으로 옮긴다. 창이 안 보이면 사람 시계를 곧바로 멈춘 채로 옮긴다(시작 순간·AI 수 직후 포함).
    private func commitAIGame(_ value: GomokuAIGame) {
        var game = value
        if !(isWindowVisible && !isWindowOccluded), game.deadline != nil { game.pause(now: clock()) }
        if aiGame != game { aiGame = game }
        let next = game.matchState()
        if match != next { match = next }
        let nextPhase: GomokuPhase = game.isFinished ? .result : .playing
        if phase != nextPhase { phase = nextPhase }
        if myAutoStreak != game.humanAutoStreak { myAutoStreak = game.humanAutoStreak }
        scheduleAIClock()
    }

    private func setAINotice(_ text: String?) {
        if notice != text { notice = text }
    }

    /// AI 차례면 한 번 생각을 맡긴다. 끝나면 세대·판 id·기록 수·차례가 그대로일 때만 반영한다.
    private func scheduleAITurnIfNeeded() {
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

    private func applyAIMove(_ move: GomokuPoint?) {
        guard var game = aiGame else { return }
        let now = clock()
        if !game.applyAIMove(move, now: now) {
            // 엔진이 규칙 밖의 수를 냈다 — 판이 멈추지 않게 무작위 합법 수로 대신 둔다(진단 줄 하나).
            Self.logger.notice("ai move rejected, using fallback")
            let fallback = game.randomAIFallback(randomIndex: aiRuntime.randomIndex)
            guard game.applyAIMove(fallback, now: now) else { return }
        }
        commitAIGame(game)
        // AI 수 뒤에 흑 규칙 패스로 다시 AI 차례가 올 수는 없다(패스는 흑만 하고, AI 가 흑이면 다음은 사람이다) —
        // 그래도 판이 한 수라도 AI 차례에 멈추지 않도록 한 번 더 본다.
        scheduleAITurnIfNeeded()
    }

    /// 사람 시계 작업을 (다시) 건다. 시계가 돌 때만 마감에 깨어난다.
    private func scheduleAIClock() {
        aiRuntime.clockTask?.cancel()
        aiRuntime.clockTask = nil
        guard isAIMatch, let game = aiGame, let deadline = game.deadline else { return }
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
