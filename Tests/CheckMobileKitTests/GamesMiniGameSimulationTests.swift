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
        case .tetris:
            // 서버 20260923140000_minigame_tetris.sql §E 의 tetris 갈래를 그대로 옮긴 것.
            //   A = advance(조각 고정 +1 · 줄 소거 +1). level(A) = 1 + A/20 (A<280) · 15 + (A−280)/50 (A≥280) — **정수 나눗셈**.
            //   한 advance 가 낼 수 있는 점수의 상계 5000×min(level,30) 을 쌓아 점수를 넘는 최소 A 를 찾는다.
            //   시간 = 0.1·A(ARE) + 0.025·max(0, (4A−200)/14)(줄소거 정지) — 판 용량 200칸이 강제하는 '조각 최대·소거 최소' 분해다.
            // ⚠️ `sum` 을 쓰지 않는 유일한 갈래다(위 둘은 누적합, 여기는 닫힌 식) — 윗줄 `var sum` 을 지우지 마라.
            let n = max(score, 0)
            if n <= 0 { return 0 }
            var advance = 0
            var cap = 0.0
            while true {
                advance += 1
                let level = min(30, advance < 280 ? 1 + advance / 20 : 15 + (advance - 280) / 50)
                cap += 5000 * Double(level)
                // 루프 상한 4000 은 int 최대 입력에 대한 안전 탈출이다(1억은 A = 1,076 에서 넘는다).
                if cap >= Double(n) || advance >= 4000 { break }
            }
            let seconds = 0.1 * Double(advance) + 0.025 * max(0, (4 * Double(advance) - 200) / 14.0)
            return ((seconds * margin) * 10_000).rounded() / 10_000
        }
    }

    @Test("서버 식 옮김 검산: 타이밍 바 3.6219초 · 플래피 29점 20.9437초(여유 전 22.046) · 0점 0초")
    func serverFormulaPort() {
        #expect(Self.serverMinSeconds(.timingBar, score: 1) == Self.serverMinSeconds(.timingBar, score: 1000))
        #expect(abs(Self.serverMinSeconds(.timingBar, score: 500) - 3.8125 * 0.95) < 0.0001)
        #expect(abs(Self.serverMinSeconds(.flappy, score: 29) - 22.046 * 0.95) < 0.01)
        #expect(Self.serverMinSeconds(.flappy, score: 0) == 0)
    }

    /// 테트리스 하한 옮김 검산 — **로컬 Postgres 에서 실제 함수가 낸 값**과 글자 그대로 비교한다
    /// (2026-09-23, 20260923140000_minigame_tetris.sql §G(6) 의 검산표와 같은 값).
    ///
    /// 왜 시뮬레이션이 아니라 표인가: 폰에는 아직 테트리스 엔진이 없다(`MiniGameKind.phoneCases` 밖). 엔진이 붙기 전까지
    /// 이 사본이 서버와 어긋났는지 알 길은 이 표뿐이고, 표가 없으면 새 게임만 **조용히 검증 밖으로 빠진다**.
    /// 모바일 세션이 엔진을 물리면 위 두 게임처럼 "정직한 플레이가 하한을 넘는다"를 시뮬로 재는 테스트를 더해라.
    @Test("서버 식 옮김 검산(테트리스): 실서버 함수가 낸 아홉 점과 정확히 같다 · 0점 0초 · 단조 증가")
    func tetrisServerFormulaPort() {
        #expect(Self.serverMinSeconds(.tetris, score: 0) == 0)
        #expect(Self.serverMinSeconds(.tetris, score: -5) == 0)
        let table: [(score: Int, seconds: Double)] = [
            (10_000, 0.1900), (50_000, 0.9500), (100_000, 1.9000), (300_000, 3.8000),
            (800_000, 6.7857), (1_600_000, 10.1446), (5_000_000, 19.0000), (99_999_999, 109.1821),
            // 루프 상한 4000 에서 탈출하는 자리(int 최대 입력) — 여기가 안 맞으면 탈출 조건이 틀린 것이다.
            (2_147_483_647, 406.8036),
        ]
        for row in table {
            #expect(Self.serverMinSeconds(.tetris, score: row.score) == row.seconds,
                    "tetris \(row.score)점: \(Self.serverMinSeconds(.tetris, score: row.score)) ≠ \(row.seconds)")
        }
        // 점수가 오르면 하한도 오르기만 한다 — 어딘가에서 내려가면 "더 높은 점수를 더 빨리" 낼 수 있다는 뜻이다.
        var previous = 0.0
        for score in stride(from: 0, through: 2_000_000, by: 5_000) {
            let now = Self.serverMinSeconds(.tetris, score: score)
            #expect(now >= previous, "tetris 하한이 \(score)점에서 내려갔다(\(previous) → \(now))")
            previous = now
        }
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
