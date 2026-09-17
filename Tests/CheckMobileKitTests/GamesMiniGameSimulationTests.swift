@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

/// 미니게임 점수 제출이 서버 **최소 시간 검사**(`minigame_min_seconds`)를 통과하는가 — 스텁이 아니라 **엔진 시뮬레이션**으로 잰다
/// (SPEC-ios-build D6). 폰 엔진 구동기(`GamesPlayController`)를 폰 주사율(60·120Hz 화면이 실제로 받는 프레임 간격)로 밀며
/// 정직한 플레이(사람이 누를 수 있는 속도)로 낸 점수와 그때까지 흐른 실제 시간을 서버 식과 견준다.
///
/// 서버 식(supabase/migrations/20260914010000_minigame_round_token.sql §2, 여기서는 옮긴 판):
/// - 타이밍 바: 반주기 합 × 0.95(점수 무관).
/// - 플래피: Σ_{i<N} spacing(i)/speed(i) × 0.95.
/// 서버의 경과는 **토큰 발급(화면을 열 때 선발급)부터 제출까지**라 판 안의 경과보다 길다 — 여기서는 더 엄한 쪽(판 안 경과만)으로 잰다.
@MainActor
@Suite struct GamesMiniGameSimulationTests {
    /// 서버 `minigame_min_seconds(p_game, p_score)` 를 옮긴 것(여유 계수 0.95, 소수 넷째 자리 반올림).
    static func serverMinSeconds(_ kind: MiniGameKind, score: Int) -> Double {
        let margin = 0.95
        var sum = 0.0
        switch kind {
        case .timingBar:
            for round in 1...10 { sum += max(0.42, 1.10 - 0.075 * Double(round - 1)) }
            return ((sum / 2 * margin) * 10_000).rounded() / 10_000
        case .flappy:
            let n = max(score, 0)
            if n > 0 {
                for i in 0..<n { sum += max(115, 150 - 2 * Double(i)) / min(230, 130 + 3 * Double(i)) }
            }
            return ((sum * margin) * 10_000).rounded() / 10_000
        }
    }

    @Test("서버 식 옮김 검산: 타이밍 바 3.6219초 · 플래피 29점 20.9437초(여유 전 22.046) · 0점 0초")
    func serverFormulaPort() {
        #expect(Self.serverMinSeconds(.timingBar, score: 1) == Self.serverMinSeconds(.timingBar, score: 1000))
        #expect(abs(Self.serverMinSeconds(.timingBar, score: 500) - 3.8125 * 0.95) < 0.0001)
        #expect(abs(Self.serverMinSeconds(.flappy, score: 29) - 22.046 * 0.95) < 0.01)
        #expect(Self.serverMinSeconds(.flappy, score: 0) == 0)
    }

    /// 화면 주사율 → 엔진이 실제로 받는 프레임 간격(코어 `MiniGameFrameRate` — 뷰가 TimelineView 에 넘기는 값).
    private static func frameInterval(hz: Int) -> TimeInterval {
        let fps = MiniGameFrameRate.targetFPS(forRefreshRate: hz)
        return 1.0 / Double(fps)
    }

    @Test("타이밍 바: 가장 빨리 치는 사람(라운드가 뜨자마자 탭)도, 겨냥해 치는 사람도 서버 하한을 넘는다 — 60·120Hz")
    func timingBarHonestPlayClearsTheFloor() {
        let need = Self.serverMinSeconds(.timingBar, score: 1000)
        for (hz, dt) in [(60, Self.frameInterval(hz: 60)), (120, Self.frameInterval(hz: 120)), (120, 1.0 / 120.0)] {
            for strategy in ["mash", "aim"] {
                let controller = GamesPlayController(kind: .timingBar, seed: 20_260_917)
                var finishedScore: Int?
                controller.onFinished = { finishedScore = $0 }
                var now = MobileClock.demoInstant
                controller.tap()
                controller.tick(at: now)
                var elapsed = 0.0
                for _ in 0..<(120 * 60) {
                    now = now.addingTimeInterval(dt)
                    elapsed += dt
                    controller.tick(at: now)
                    if case .running(let round, let t) = controller.timing.phase {
                        switch strategy {
                        case "mash":
                            controller.tap()
                        default:
                            let (center, _) = controller.timing.target
                            let move = 2 / TimingBarGame.period(round: round) * dt
                            // 사람 반응 한계: 라운드 시작 0.15초 전에는 못 누른다.
                            if t >= 0.15, abs(controller.timing.markerPosition - center) <= move / 2 + 1e-9 { controller.tap() }
                        }
                    }
                    if finishedScore != nil { break }
                }
                #expect(finishedScore != nil, "\(hz)Hz \(strategy): 판이 안 끝났다")
                let score = finishedScore ?? -1
                #expect(elapsed >= need, "\(hz)Hz \(strategy): 경과 \(elapsed)초 < 서버 하한 \(need)초 (점수 \(score))")
                print("[sim] timing_bar \(hz)Hz \(strategy) score=\(score) elapsed=\(String(format: "%.3f", elapsed))s need=\(need)s")
            }
        }
    }

    /// 앞을 내다보는 자동 조종: 지금 누르지 않아도 앞으로 `depth × decision` 초 동안 살아남는 누름 순서가 있으면 누르지 않고,
    /// 없으면 누른다(규칙 값 타입을 복사해 미리 굴려 본다). 누름은 `decision` 초에 한 번까지 — 사람이 누를 수 있는 속도다.
    /// 이 시험이 재는 것은 실력이 아니라 **점수당 흐르는 시간**이다 — 기둥 하나를 지나는 시간은 속도·간격(규칙)이 정하고
    /// 조종 실력과 무관하다. 오래 살아남는 조종사일수록 높은 점수 구간(속도 상한 34점 너머)까지 잰다.
    private static func flappyShouldFlap(_ game: FlappyGame, dt: TimeInterval, framesPerDecision: Int, depth: Int) -> Bool {
        !survives(game, flapNow: false, dt: dt, frames: framesPerDecision, depth: depth)
    }

    private static func survives(_ game: FlappyGame, flapNow: Bool, dt: TimeInterval, frames: Int, depth: Int) -> Bool {
        var g = game
        if flapNow { g.flap() }
        for _ in 0..<frames {
            g.step(dt: dt)
            guard g.phase == .running else { return false }
        }
        guard depth > 1 else { return true }
        return survives(g, flapNow: false, dt: dt, frames: frames, depth: depth - 1)
            || survives(g, flapNow: true, dt: dt, frames: frames, depth: depth - 1)
    }

    @Test("플래피: 사람 속도(0.1초에 한 번까지)로 누르는 플레이로 점수가 오를 때마다 그때까지의 경과가 서버 하한 이상이다 — 30·60·120fps · 여러 판")
    func flappyHonestPlayClearsTheFloorAtEveryScore() {
        var bestScore = 0
        // 프레임 간격: 60Hz 화면 · ProMotion 120Hz 화면(코어 규칙상 60fps 로 돈다) · 규칙이 바뀌어 120fps 로 도는 경우 · 느린 기기 30fps.
        let intervals = [Self.frameInterval(hz: 60), Self.frameInterval(hz: 120), 1.0 / 120.0, 1.0 / 30.0]
        for (hz, dt) in intervals.enumerated().map({ (Int((1 / $0.element).rounded()), $0.element) }) {
            for seed in [UInt64(1), 7, 42, 2_026, 9_170_917] {
                let controller = GamesPlayController(kind: .flappy, seed: seed)
                var finishedScore: Int?
                controller.onFinished = { finishedScore = $0 }
                var now = MobileClock.demoInstant
                controller.tap()
                controller.tick(at: now)
                var elapsed = 0.0
                var lastScore = 0
                var frame = 0
                let framesPerDecision = max(1, Int((0.1 / dt).rounded()))
                // 최대 3분 — 점수 40이면 멈춘다(그 뒤 하한 증가는 기둥당 0.5초로 일정하다).
                for _ in 0..<Int(180 / dt) {
                    now = now.addingTimeInterval(dt)
                    elapsed += dt
                    controller.tick(at: now)
                    let game = controller.flappy
                    if game.score != lastScore {
                        lastScore = game.score
                        let need = Self.serverMinSeconds(.flappy, score: game.score)
                        #expect(elapsed >= need, "\(hz)fps seed \(seed): \(game.score)점에서 경과 \(elapsed)초 < 하한 \(need)초")
                    }
                    frame += 1
                    if game.phase == .running, frame % framesPerDecision == 0,
                       Self.flappyShouldFlap(game, dt: dt, framesPerDecision: framesPerDecision, depth: 6) {
                        controller.tap()
                    }
                    if finishedScore != nil || game.score >= 40 { break }
                }
                bestScore = max(bestScore, lastScore)
                let final = finishedScore ?? lastScore
                #expect(elapsed >= Self.serverMinSeconds(.flappy, score: final))
                print("[sim] flappy \(hz)fps seed=\(seed) score=\(final) elapsed=\(String(format: "%.3f", elapsed))s need=\(Self.serverMinSeconds(.flappy, score: final))s")
            }
        }
        // 시뮬레이션이 의미가 있으려면 조종사가 실제로 점수를 낸다(움직이는 기둥이 나오는 15점 너머까지).
        #expect(bestScore >= 35, "자동 조종이 속도 상한(34점) 구간까지 못 갔다 — 높은 점수 구간을 재지 않았다: \(bestScore)")
    }
}
