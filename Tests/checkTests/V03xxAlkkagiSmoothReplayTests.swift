// 알까기 굴림 재생이 끊기지 않는가(제보 #9 '너무 버벅여요' · #10 '애니메이션은 각자 높은 프레임으로').
// 없으면 어떤 결함이 초록으로 통과하는가: 0.3.80 판 화면은 굴림을 프레임마다 **서버 시각**(응답마다 다시 잰 시계 차)에 맞춰 그렸다.
//  ① 받는 사람은 쏜 판을 0.2~0.5초 늦게 알아 첫 프레임에 그만큼 돌이 순간이동했다.
//  ② 시계 차가 응답마다 흔들리면(왕복 시간이 다르면) 돌이 멈칫하거나 건너뛰었다.
//  ③ 쏜 사람은 응답을 받는 순간 예측 굴림에서 서버 시각 굴림으로 갈아타, 서버가 쏘기를 받은 시각(편도)만큼 돌이 멈췄다.
// 시험은 같은 판 화면 모델(`AlkkagiLocalModel`)을 120Hz 로 밟으며 프레임마다 돌이 움직인 거리를 잰다 — 이상적인 굴림(같은 쏘기를
// 화면 걸음으로 끊김 없이)의 한 프레임 최대 거리와 견준다. 기준선: 신호를 놓쳐 아주 늦게 안 판(넘는 만큼 건너뜀)은 같은 측정이 큰 뜀을 잡는다.
@testable import CheckCore
import Foundation
import Testing
@testable import check

@MainActor
@Suite("알까기 굴림 재생 — 끊김 없이(제보 #9 · #10)", .serialized)
struct AlkkagiSmoothReplayTests {
    // MARK: 판 · 쏘기

    /// 흑 다섯(아래) · 백 다섯(위). 흑 2번(300, 470)이 곧장 위로 쏘아 백을 맞힌다.
    private static func stones() -> [AlkkagiGame.Stone] {
        var stones = AlkkagiGame().stones
        for index in stones.indices { stones[index].isPlaced = true; stones[index].isOut = false }
        let black: [(Double, Double)] = [(100, 470), (200, 470), (300, 470), (400, 470), (500, 470)]
        let white: [(Double, Double)] = [(300, 170), (322, 112), (120, 120), (470, 200), (540, 90)]
        for (i, p) in black.enumerated() { stones[i].position = AlkkagiVector(x: p.0, y: p.1) }
        for (i, p) in white.enumerated() { stones[5 + i].position = AlkkagiVector(x: p.0, y: p.1) }
        return stones
    }

    private struct Scenario {
        let aiming: AlkkagiMatch
        let rolling: AlkkagiMatch
        let after: AlkkagiMatch
        let duration: Double
        var endMs: Double { rolling.shot!.startedAtMs + duration * 1_000 }
        /// 같은 쏘기를 120Hz 화면 걸음으로 끊김 없이 굴렸을 때 한 프레임 최대 거리.
        let idealMaxStep: Double
    }

    private static func match(_ phase: AlkkagiMatchPhase, myColor: AlkkagiGame.Player, current: AlkkagiGame.Player,
                              revision: Int, stones: [AlkkagiGame.Stone], shotCount: Int, shot: AlkkagiShot? = nil,
                              deadlineMs: Double?) -> AlkkagiMatch {
        AlkkagiMatch(id: AK.matchID.uuidString.lowercased(), revision: revision, phase: phase, currentPlayer: current,
                     myColor: myColor, black: AK.black, white: AK.white, stones: stones, deadlineMs: deadlineMs,
                     shotCount: shotCount, shot: shot, placementRevision: 2, myReady: true, opponentReady: true,
                     stake: 5, myMissedTurns: 0, opponentMissedTurns: 0, forfeitAfter: 3)
    }

    private static func scenario(myColor: AlkkagiGame.Player, pullScale: Double, shotID: String,
                                 startedAtMs: Double) throws -> Scenario {
        let stones = stones()
        let pull = AlkkagiVector(x: 0, y: AlkkagiGame.maxPull * pullScale)
        var game = try #require(AlkkagiGame.restore(stones: stones, currentPlayer: .black, phase: .aiming, shotCount: 4))
        let shotAccepted = game.shoot(stoneID: 2, pull: pull)
        try #require(shotAccepted)
        let replayStart = game
        var steps = 0
        while game.phase == .rolling && steps < 240 * 30 { _ = game.advance(dt: 1.0 / 240); steps += 1 }
        try #require(game.phase != .rolling, "쏘기가 30초 안에 서지 않았다")
        let duration = Double(steps) / 240
        // 이상적인 굴림 — 화면 걸음(1/120)으로 끊김 없이.
        var ideal = replayStart
        var idealMax = 0.0
        while ideal.phase == .rolling {
            let before = ideal.stones
            _ = ideal.advance(dt: 1.0 / 120)
            idealMax = max(idealMax, maxStep(before, ideal.stones))
        }
        let shot = AlkkagiShot(id: shotID, stoneID: 2, pull: pull, startedAtMs: startedAtMs, steps: steps, initialStones: stones)
        let aiming = match(.aiming, myColor: myColor, current: .black, revision: 9, stones: stones, shotCount: 4,
                           deadlineMs: startedAtMs + 20_000)
        let rolling = match(.rolling, myColor: myColor, current: .black, revision: 10, stones: stones, shotCount: 5,
                            shot: shot, deadlineMs: startedAtMs + duration * 1_000)
        let after = match(game.phase == .finished ? .finished : .aiming, myColor: myColor, current: game.currentPlayer,
                          revision: 11, stones: game.stones, shotCount: 5,
                          deadlineMs: startedAtMs + duration * 1_000 + 30_000)
        return Scenario(aiming: aiming, rolling: rolling, after: after, duration: duration, idealMaxStep: idealMax)
    }

    /// 두 돌 배열 사이 한 프레임 최대 거리(둘 다 판 위인 돌만).
    private static func maxStep(_ a: [AlkkagiGame.Stone], _ b: [AlkkagiGame.Stone]) -> Double {
        var worst = 0.0
        for stone in b where stone.isPlaced && !stone.isOut {
            guard let old = a.first(where: { $0.id == stone.id }), old.isPlaced, !old.isOut else { continue }
            worst = max(worst, (stone.position - old.position).length)
        }
        return worst
    }

    // MARK: 받는 사람

    private struct Run {
        var maxStep = 0.0
        var stalls = 0
        /// '굴림 뒤' 판이 온 뒤에도 화면이 굴린 프레임 수(마저 굴리기).
        var rollingFramesAfterServerFinished = 0
        var finalStones: [AlkkagiGame.Stone] = []
    }

    /// 받는 사람: 쏜 판을 `lateBy` 초 늦게 안다. 프레임 `jitter` 에서 시계 차가 흔들린다(초). 서버는 굴림 끝 + 50ms 에 '굴림 뒤' 판.
    private static func receiverRun(_ sc: Scenario, lateBy: Double, jitter: [Int: Double] = [:]) -> Run {
        let clock = AKClock(milliseconds: sc.rolling.shot!.startedAtMs - 500)
        let store = AlkkagiOnlineStore(clock: { clock.date })
        store.me = AK.white
        store.state = sc.aiming
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        model.hitStopEnabled = false
        model.attachOnline(store)
        var now = 50.0
        model.tick(now: now)
        clock.milliseconds = sc.rolling.shot!.startedAtMs + lateBy * 1_000
        store.state = sc.rolling
        var run = Run()
        var previous = sc.rolling.shot!.initialStones
        var sentAfter = false
        var settledFrames = 0
        for frame in 0..<(120 * 15) {
            now += 1.0 / 120
            clock.advance(1.0 / 120)
            if let shift = jitter[frame] { clock.advance(shift) }
            if !sentAfter, clock.milliseconds >= sc.endMs + 50 {
                store.state = sc.after
                sentAfter = true
            }
            let wasRolling = model.game.phase == .rolling
            model.tick(now: now)
            let step = maxStep(previous, model.game.stones)
            run.maxStep = max(run.maxStep, step)
            if wasRolling, model.game.phase == .rolling, step < 1e-9 { run.stalls += 1 }
            if sentAfter, model.game.phase == .rolling { run.rollingFramesAfterServerFinished += 1 }
            previous = model.game.stones
            if sentAfter, model.game.phase != .rolling {
                settledFrames += 1
                if settledFrames > 10 { break }
            }
        }
        run.finalStones = model.game.stones
        return run
    }

    private static func sameStones(_ a: [AlkkagiGame.Stone], _ b: [AlkkagiGame.Stone]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.id == $1.id && $0.isOut == $1.isOut && ($0.position - $1.position).length < 1e-6
        }
    }

    @Test("받는 사람: 0.35초 늦게 안 쏘기도 처음부터 굴린다 — 순간이동 · 멈칫 없이, 끝 자리는 서버와 같다")
    func receiverLateShotHasNoTeleport() throws {
        let sc = try Self.scenario(myColor: .white, pullScale: 0.8, shotID: "shot-r", startedAtMs: AK.nowMs)
        print("[굴림] 길이 \(sc.duration)초 · 이상적 한 프레임 최대 \(sc.idealMaxStep)")
        let run = Self.receiverRun(sc, lateBy: 0.35, jitter: [30: 0.08, 60: -0.08, 90: 0.05, 120: -0.06])
        print("[굴림] 받는 사람 한 프레임 최대 \(run.maxStep) · 멈춘 프레임 \(run.stalls)")
        #expect(run.maxStep <= sc.idealMaxStep * 1.6 + 0.01,
                "돌이 한 프레임에 \(run.maxStep) 움직였다(끊김 없는 굴림 최대 \(sc.idealMaxStep) × 1.5배 따라잡기)")
        #expect(run.stalls == 0, "굴리는 중 돌이 멈춘 프레임 \(run.stalls)")
        #expect(Self.sameStones(run.finalStones, sc.after.stones), "끝 자리가 서버 판과 다르다")
    }

    @Test("받는 사람: 짧은 쏘기를 늦게 알아 서버가 먼저 끝나도 남은 굴림을 마저 굴린 뒤 받는다(끝에서 순간이동 없음)")
    func receiverDrainsBeforeAdoptingServerResult() throws {
        let sc = try Self.scenario(myColor: .white, pullScale: 0.45, shotID: "shot-short", startedAtMs: AK.nowMs)
        print("[굴림] 짧은 쏘기 길이 \(sc.duration)초")
        let lateBy = min(0.55, sc.duration * 0.6)
        let run = Self.receiverRun(sc, lateBy: lateBy)
        print("[굴림] 서버가 끝난 뒤 화면이 더 굴린 프레임 \(run.rollingFramesAfterServerFinished) · 한 프레임 최대 \(run.maxStep)")
        #expect(run.rollingFramesAfterServerFinished >= 2, "서버 판을 받자마자 굴림을 끊었다(남은 굴림이 순간이동)")
        #expect(run.maxStep <= sc.idealMaxStep * 1.6 + 0.01)
        #expect(run.stalls == 0)
        #expect(Self.sameStones(run.finalStones, sc.after.stones))
    }

    @Test("기준선: 신호를 놓쳐 아주 늦게 안 쏘기는 넘는 만큼 건너뛴다 — 같은 측정이 큰 뜀을 잡는다")
    func baselineVeryLateShotSkips() throws {
        let sc = try Self.scenario(myColor: .white, pullScale: 0.8, shotID: "shot-late", startedAtMs: AK.nowMs)
        let lateBy = AlkkagiLocalModel.maxReplayLag + min(0.8, sc.duration * 0.4)
        let run = Self.receiverRun(sc, lateBy: lateBy)
        print("[굴림] 기준선 \(lateBy)초 늦게: 한 프레임 최대 \(run.maxStep)")
        #expect(run.maxStep > sc.idealMaxStep * 3, "아주 늦게 안 판인데 뜀이 안 잡힌다 — 측정이 아무것도 안 잰다")
        #expect(Self.sameStones(run.finalStones, sc.after.stones))
    }

    // MARK: 쏜 사람

    @Test("쏜 사람: 응답을 받는 순간 굴림이 멈추지 않는다(서버가 쏘기를 받은 시각만큼 뒤로 맞추지 않음)")
    func shooterKeepsRollingThroughReply() async throws {
        let clock = AKClock()
        let script = AKScript()
        let store = AK.store(script, clock: clock)
        let aiming = Self.match(.aiming, myColor: .black, current: .black, revision: 9, stones: Self.stones(),
                                shotCount: 4, deadlineMs: AK.nowMs + 20_000)
        script.route("alkkagi_lobby", AK.lobby(state: aiming))
        script.fallback = { [weak store] _ in AK.response(store?.state) }
        await store.refreshLobby()
        try #require(store.state?.phase == .aiming && store.canShoot, "쏠 수 있는 판이 서지 않았다")
        let model = AlkkagiLocalModel()
        model.soundEnabled = false
        model.hitStopEnabled = false
        model.attachOnline(store)
        var now = 50.0
        model.tick(now: now)
        script.enqueue(.suspended)
        let pull = AlkkagiVector(x: 0, y: AlkkagiGame.maxPull * 0.8)
        model.aim(start: AlkkagiVector(x: 300, y: 470), translation: pull)
        model.release()
        let releasedAtMs = clock.milliseconds
        try await akEventually { script.calls.contains { if case .shoot = $0 { true } else { false } } }
        let shootIndex = try #require(script.calls.lastIndex { if case .shoot = $0 { true } else { false } })
        guard case let .shoot(_, _, _, _, actionID) = script.calls[shootIndex] else { throw CancellationError() }
        #expect(model.game.phase == .rolling, "놓자마자 내 화면에서 굴러야 한다(예측)")
        var previous = model.game.stones
        var stalls = 0
        var maxStep = 0.0
        func frame() {
            now += 1.0 / 120
            clock.advance(1.0 / 120)
            let wasRolling = model.game.phase == .rolling
            model.tick(now: now)
            let step = Self.maxStep(previous, model.game.stones)
            maxStep = max(maxStep, step)
            if wasRolling, model.game.phase == .rolling, step < 1e-9 { stalls += 1 }
            previous = model.game.stones
        }
        for _ in 0..<18 { frame() }   // 왕복 150ms
        // 서버는 편도(75ms) 뒤에 쏘기를 받아 그 시각을 굴림 시작으로 적는다.
        let sc = try Self.scenario(myColor: .black, pullScale: 0.8, shotID: actionID.uuidString.lowercased(),
                                   startedAtMs: releasedAtMs + 75)
        script.resume(shootIndex, returning: AK.response(sc.rolling, serverNowMs: releasedAtMs + 75))
        try await akEventually { store.state?.phase == .rolling }
        for _ in 0..<5 { await Task.yield() }
        var sentAfter = false
        for _ in 0..<(120 * 10) {
            if !sentAfter, clock.milliseconds >= sc.endMs + 50 {
                store.state = sc.after
                sentAfter = true
            }
            frame()
            if sentAfter, model.game.phase != .rolling { break }
        }
        print("[굴림] 쏜 사람 멈춘 프레임 \(stalls) · 한 프레임 최대 \(maxStep) (이상적 \(sc.idealMaxStep))")
        #expect(stalls == 0, "응답 뒤 굴림이 \(stalls) 프레임 멈췄다")
        #expect(maxStep <= sc.idealMaxStep * 1.6 + 0.01)
        #expect(Self.sameStones(model.game.stones, sc.after.stones))
        script.finish()
    }
}
