import Foundation

// 1:1 길건너 판 루프 · 입력 · 경주 스냅숏(SPEC v1.3 §8.3 · §3.1 · §8.4 스냅숏).
// ★ C1 뼈대: `tick` 은 판을 움직이지 않고 보고도 내지 않는다(C2). `hop`·`forward` 는 구동기에 그대로 넘긴다.
//   `raceSnapshot` 은 지금 든 `match`·`duel` 에서 값을 읽기만 한다 — U 의 렌더 시험은 `match`·`duel`·`phase` 를
//   직접 세우고(@testable) `uptime` 을 주입한 init 으로 시각을 고정해 이 값을 읽는다.

extension CrossyDuelStore {
    /// 판 루프 한 걸음 + 보고 판단(창과 무관 — 테트리스 D10). 인자가 없으면 `uptime()`(v1.1 CC-1).
    /// C1 빈 몸통 — C2 가 `duel.advance` · `reportDue` · 프레임 장부 걸음을 채운다.
    package func tick(now: TimeInterval? = nil) {
        _ = now ?? uptime()
    }

    /// 방향 입력(판 중에만 — 얼었거나 시작 전이면 구동기가 무시한다).
    package func hop(_ direction: CrossyGame.Direction) {
        guard phase == .playing, !playingElsewhere else { return }
        duel?.input(direction)
    }

    /// 앞으로 한 칸(스페이스·클릭).
    package func forward() {
        guard phase == .playing, !playingElsewhere else { return }
        duel?.forward()
    }

    /// 경주 트랙 값 하나(v1.1 단조 시계, CC-1). 판이 없으면 nil.
    /// C1: 든 값에서 읽기만 한다. 프레임 병합(`max(프레임 sc, DB)`) · `opponentQuiet` 계산 · `waitingForResult` 는 C2.
    package func raceSnapshot(at now: TimeInterval? = nil) -> CrossyDuelRaceSnapshot? {
        guard let match else { return nil }
        let t = now ?? uptime()
        let game = duel?.game
        let goal = game?.rules.goalScore ?? CrossyDuelSession.expectedGoal
        let myScore = match.isFinished ? (match.finalMyScore ?? game?.score ?? match.myServerScore)
                                       : (game?.score ?? match.myServerScore)
        let opponentScore = match.isFinished ? (match.finalOpponentScore ?? match.opponentScore)
                                             : (frameLink?.mergedOpponentScore(db: match.opponentScore) ?? match.opponentScore)
        var respawnIn: TimeInterval?
        if let game, game.rules.respawnDelay != nil, case .over(let hold) = game.phase { respawnIn = max(0, hold) }
        let shielded = game.map { g in g.respawnShield.map { g.elapsed < $0.until } ?? false } ?? false
        let countdown = duel?.countdownRemaining(at: t).flatMap { $0 > 0 ? $0 : nil }
        let frozen = match.isFinished || (duel?.finished ?? false)
        return CrossyDuelRaceSnapshot(
            myScore: myScore, opponentScore: opponentScore, goal: goal,
            myDeaths: game?.deaths ?? 0, opponentDeaths: match.opponentDeaths,
            countdown: countdown, remaining: duel?.remaining(at: t), respawnIn: respawnIn,
            shielded: shielded, frozen: frozen, waitingForResult: false, opponentQuiet: false)
    }
}
