@testable import CheckCore
import CoreGraphics
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
    /// 왜 시뮬 말고 **표도** 있나: 시뮬(아래 `tetrisHonestPlayClearsTheFloor`)은 우리 엔진이 낸 값을 우리 사본과
    /// 견주므로, **사본이 서버와 함께 틀리면** 둘 다 조용히 통과한다. 이 표는 그 고리를 끊는다 — 실서버 함수가
    /// 실제로 낸 아홉 점을 글자 그대로 박아 두었다(2026-09-23 실호출 · 20260923140000_minigame_tetris.sql §G(6)).
    /// 사본을 고치는 사람은 이 표부터 빨갛게 만나게 된다.
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

    // MARK: - 테트리스

    /// 굳은 판의 나쁨(낮을수록 좋다): 높이 합 · 구멍 · 들쭉날쭉 · 최고 높이. 고전 가중치를 그대로 쓴다 —
    /// 여기서 실력을 다투는 것이 아니라 **판을 오래 살려** 레벨이 오른 구간(조각당 시간이 제일 짧은 쪽)까지 재려는 것이다.
    private static func tetrisBoardCost(_ board: [[TetrisGame.Piece?]]) -> Double {
        var heights = [Int](repeating: 0, count: TetrisGame.columns)
        var holes = 0
        for column in 0..<TetrisGame.columns {
            var covered = false
            for row in 0..<TetrisGame.totalRows {
                if board[row][column] != nil {
                    if !covered {
                        covered = true
                        heights[column] = TetrisGame.totalRows - row
                    }
                } else if covered {
                    holes += 1
                }
            }
        }
        let bumpiness = zip(heights, heights.dropFirst()).reduce(0) { $0 + abs($1.0 - $1.1) }
        return Double(heights.reduce(0, +)) * 0.51 + Double(holes) * 3.6
            + Double(bumpiness) * 0.18 + Double(heights.max() ?? 0) * 0.5
    }

    /// 이 조각을 **어떻게 돌려 어느 열에** 놓을지 — 규칙 값 타입을 복제해 실제로 떨어뜨려 보고 고른다
    /// (플래피 자동 조종이 앞을 내다보는 것과 같은 방식이다). 순수 계산이고 화면·시계는 안 건드린다.
    /// - Returns: 시계 회전 횟수와 조각 왼쪽 끝이 설 열. 어디에도 못 놓으면 nil.
    private static func tetrisBestPlacement(_ game: TetrisGame) -> (turns: Int, column: Int)? {
        guard game.active != nil else { return nil }
        var best: (turns: Int, column: Int)?
        var bestCost = Double.infinity
        for turns in 0..<4 {
            for column in 0..<TetrisGame.columns {
                var probe = game
                for _ in 0..<turns { probe.rotate(clockwise: true) }
                guard let piece = probe.active else { continue }
                let leftmost = piece.cells.map { $0.column }.min() ?? 0
                for _ in 0..<abs(column - leftmost) {
                    if column < leftmost {
                        probe.setLeftHeld(true)
                        probe.setLeftHeld(false)
                    } else {
                        probe.setRightHeld(true)
                        probe.setRightHeld(false)
                    }
                }
                // 벽·굳은 칸에 막혀 그 열까지 못 갔으면 후보가 아니다.
                guard probe.active?.cells.map({ $0.column }).min() == column else { continue }
                let linesBefore = probe.lines
                probe.action()   // 진행 중 = 하드드롭 = 그 자리에서 굳는다(판·줄이 바로 확정된다)
                let cost = Self.tetrisBoardCost(probe.board) - 12 * Double(probe.lines - linesBefore)
                if cost < bestCost {
                    bestCost = cost
                    best = (turns, column)
                }
            }
        }
        return best
    }

    /// 테트리스 정직한 플레이가 서버 시간하한을 넘는가 — 위 두 게임과 같은 자리에서 같은 방식으로 잰다.
    ///
    /// 조종은 **사람 속도**다: 첫 손은 0.15초 뒤에야 닿고(반응 한계), 그 뒤로는 0.1초에 한 번까지만 손을 댄다
    /// (회전 한 번 · 한 칸 이동 · 즉시 내리기 중 하나). 전략이 둘인 이유는 재는 것이 실력이 아니라
    /// **점수당 흐르는 시간**이기 때문이다:
    /// · `stack` — 복제본에 미리 떨어뜨려 본 자리로 돌려서 옮긴 뒤 즉시 내리기. 판이 오래 살아 레벨이 오르고,
    ///   레벨이 오를수록 조각당 시간이 짧아진다 — 하한과 실제 소요가 제일 가까워지는 쪽이다.
    /// · `swipe` — 손 대는 방법이 **전부 손가락**인 arm: 회전은 캔버스 탭, 이동은 가로 끌기, 낙하는 세로 쓸기
    ///   (한 번의 끌기 = 소프트드롭 여러 칸 · 칸당 1점)다. 실측으로 **초당 점수가 가장 크고**(511점/초 대
    ///   쌓기 434점/초) 서버 하한 대비 여유도 제일 얇다(3.2배 대 5.4배). 여기가 안 넘으면 배선이 틀린 것이다.
    ///
    /// ⚠️ 2026-09-23 **이전의** 쓸기 arm 은 자리를 안 골라 `advance` 11~12 에서 죽어 **119점**이었다. 그 점수의
    ///    서버 하한은 0.095초라 무엇을 해도 넘어서 그 arm 은 **영원히 초록**이었다 — 주석은 그때도 "초당 점수가
    ///    가장 크다"고 적어 뒀지만 그 시점 실측은 41점/초로 쌓기의 1/10 이었다(주장이 거짓이었다).
    ///    자리를 고르게 고친 뒤에야 그 문장이 참이 됐고, 그래서 **arm 별 하한**(깊이·점수·여유 배율)을 아래에 둔다 —
    ///    합계만 보면 한 arm 이 통째로 죽어도 다른 arm 이 초록으로 가려 준다.
    ///
    /// 손가락 좌표부터 조각 위치까지 진짜 배선(`GamesPlayController`)을 지난다 — `canvasDragChanged`·
    /// `moveLeftOneCell`·`hardDrop` 가 그것이다. 엔진을 직접 밀면 제스처 배선이 시간을 훔쳐도 안 보인다.
    @Test("테트리스: 사람 속도로 두는 플레이는 **점수가 오를 때마다** 서버 하한을 넘는다 — 60·120Hz · 쌓기·쓸기")
    func tetrisHonestPlayClearsTheFloorAtEveryScore() {
        var bestScore = 0
        var deepestAdvance = 0
        var tightestRatio = Double.infinity
        // ★ arm 마다 따로 센다. 합쳐서만 보면 한 arm 이 통째로 죽어도(= 아무것도 안 재도) 다른 arm 이 초록으로
        //   가려 준다 — 쓸기 arm 이 advance 11 에서 죽어 있던 8일이 정확히 그 모양이었다.
        var deepestByStrategy: [String: Int] = [:]
        var bestByStrategy: [String: Int] = [:]
        var tightestByStrategy: [String: Double] = [:]
        // 셀 폭은 실기 근사값 20pt(논리 13 × 배율). 한 칸 문턱이 이 값이라 쓸기 거리도 이걸로 낸다.
        let cellWidth: CGFloat = 20
        for (hz, dt) in [(60, Self.frameInterval(hz: 60)), (120, Self.frameInterval(hz: 120)), (120, 1.0 / 120.0)] {
            for strategy in ["stack", "swipe"] {
                for seed in [UInt64(3), 20_260_923] {
                    let controller = GamesPlayController(kind: .tetris, seed: seed)
                    controller.updateCellWidth(cellWidth)
                    var finishedScore: Int?
                    controller.onFinished = { finishedScore = $0 }
                    var now = MobileClock.demoInstant
                    controller.tap()
                    controller.tick(at: now)
                    var elapsed = 0.0
                    var lastScore = 0
                    var frame = 0
                    var planTurns = 0
                    var planColumn = -1
                    var plannedAdvance = -1
                    let framesPerDecision = max(1, Int((0.1 / dt).rounded()))
                    // 최대 3분 — 중력 상한(advance 280 = L15, 20G)을 넘기고도 남는다.
                    for _ in 0..<Int(180 / dt) {
                        now = now.addingTimeInterval(dt)
                        elapsed += dt
                        controller.tick(at: now)
                        let game = controller.tetris
                        if game.score != lastScore {
                            lastScore = game.score
                            let need = Self.serverMinSeconds(.tetris, score: game.score)
                            #expect(elapsed >= need,
                                    "\(hz)Hz \(strategy) seed \(seed): \(game.score)점에서 경과 \(elapsed)초 < 하한 \(need)초")
                            if need > 0 {
                                tightestRatio = min(tightestRatio, elapsed / need)
                                tightestByStrategy[strategy] = min(tightestByStrategy[strategy] ?? .infinity, elapsed / need)
                            }
                        }
                        deepestAdvance = max(deepestAdvance, game.advance)
                        frame += 1
                        if finishedScore != nil { break }
                        // 사람 반응 한계: 판이 켜지고 0.15초 안에는 아무도 손을 못 댄다.
                        guard elapsed >= 0.15, frame % framesPerDecision == 0,
                              game.phase == .running, let active = game.active else { continue }
                        let leftmost = active.cells.map { $0.column }.min() ?? 0
                        if strategy == "stack" {
                            // 새 조각이 나왔다 — 그때 한 번만 자리를 고른다(사람도 조각을 보고 정한다).
                            if game.advance != plannedAdvance {
                                plannedAdvance = game.advance
                                let plan = Self.tetrisBestPlacement(game)
                                planTurns = plan?.turns ?? 0
                                planColumn = plan?.column ?? leftmost
                            }
                            if planTurns > 0 {
                                let before = active.rotation
                                controller.rotate(clockwise: true)   // 폰에서 시계 회전은 캔버스 탭이다
                                planTurns -= 1
                                // 못 돌았으면(킥까지 막혔다) 더 시도하지 않는다 — 사람도 한 번 해 보고 포기한다.
                                if controller.tetris.active?.rotation == before { planTurns = 0 }
                            } else if leftmost != planColumn {
                                if leftmost < planColumn {
                                    controller.moveRightOneCell()
                                } else {
                                    controller.moveLeftOneCell()
                                }
                                // 벽·굳은 칸에 막혀 한 칸도 못 갔으면 그 자리에서 내린다(무한정 밀지 않는다).
                                if controller.tetris.active?.cells.map({ $0.column }).min() == leftmost {
                                    controller.hardDrop()
                                }
                            } else {
                                controller.hardDrop()
                            }
                        } else {
                            // 새 조각이 나왔다 — 자리를 한 번 고른다. 여기서는 **손 대는 방법이 전부 손가락**이다:
                            // 회전은 캔버스 탭, 이동은 가로 끌기, 낙하는 세로 쓸기(버튼은 즉시 내리기 하나뿐).
                            if game.advance != plannedAdvance {
                                plannedAdvance = game.advance
                                let plan = Self.tetrisBestPlacement(game)
                                planTurns = plan?.turns ?? 0
                                planColumn = plan?.column ?? leftmost
                            }
                            // 한 번의 플릭: 시작점을 옮겨 새 접촉임을 알린다(트래커가 시작점으로 접촉을 가른다).
                            let start = CGPoint(x: 120, y: 60 + Double(frame % 3))
                            if planTurns > 0 {
                                // 캔버스 **탭**(8pt 미만 · 0.25초 안) = 시계 회전.
                                let before = active.rotation
                                controller.canvasDragChanged(startLocation: start, translation: .zero, at: now)
                                controller.canvasDragEnded(translation: CGSize(width: 1, height: 1),
                                                           at: now.addingTimeInterval(0.05))
                                planTurns -= 1
                                // 못 돌았으면(킥까지 막혔다) 더 시도하지 않는다 — 사람도 한 번 해 보고 포기한다.
                                if controller.tetris.active?.rotation == before { planTurns = 0 }
                            } else if leftmost != planColumn {
                                // 가로 **끌기** 한 번으로 그 열까지 — 한 번의 끌기가 여러 칸을 만드는 것이 폰의 관용구다.
                                let slide = CGSize(width: CGFloat(planColumn - leftmost) * cellWidth, height: 0)
                                controller.canvasDragChanged(startLocation: start, translation: slide, at: now)
                                controller.canvasDragEnded(translation: slide, at: now.addingTimeInterval(0.05))
                                // 벽·굳은 칸에 막혀 한 칸도 못 갔으면 그 자리에서 내린다(무한정 밀지 않는다).
                                if controller.tetris.active?.cells.map({ $0.column }).min() == leftmost {
                                    planColumn = leftmost
                                }
                            } else {
                                let swipe = CGSize(width: 0, height: Double(TetrisGame.visibleRows) * cellWidth)
                                controller.canvasDragChanged(startLocation: start, translation: swipe, at: now)
                                controller.canvasDragEnded(translation: swipe, at: now.addingTimeInterval(0.05))
                                controller.hardDrop()
                            }
                        }
                    }
                    bestScore = max(bestScore, lastScore)
                    bestByStrategy[strategy] = max(bestByStrategy[strategy] ?? 0, lastScore)
                    deepestByStrategy[strategy] = max(deepestByStrategy[strategy] ?? 0, controller.tetris.advance)
                    let final = finishedScore ?? lastScore
                    let need = Self.serverMinSeconds(.tetris, score: final)
                    #expect(elapsed >= need, "\(hz)Hz \(strategy) seed \(seed): 끝난 판 \(final)점에 경과 \(elapsed)초 < 하한 \(need)초")
                    print("[sim] tetris \(hz)Hz \(strategy) seed=\(seed) score=\(final) advance=\(controller.tetris.advance)"
                          + " elapsed=\(String(format: "%.3f", elapsed))s need=\(need)s")
                }
            }
        }
        // 시뮬레이션이 의미가 있으려면 조종사가 **깊이** 들어간다. advance 150 이면 레벨 8 이고 중력이 이미
        // 스폰 직후 접지에 가깝다 — 조각당 시간이 제일 짧아지는 구간이 여기부터다. 얕게 놀고 초록이면 이 테스트는
        // 스폰 직후만 재는 셈이 된다(실측: 자리를 안 고르는 조종사는 advance 34 에서 끝났다).
        #expect(deepestAdvance >= 150, "조종사가 중력이 빨라지는 구간에 못 갔다 — 재고 있는 곳이 판 앞머리뿐이다: \(deepestAdvance)")
        #expect(bestScore >= 10_000, "조종사가 점수를 거의 못 냈다 — 하한을 넘는 것이 당연해진다: \(bestScore)")
        // 서버 하한은 실제 소요의 몇 %뿐이라 여유가 크다. 그 여유가 **1 밑으로 내려가지 않았다**는 것이 이 테스트의 전부다.
        // (가장 빡빡한 자리는 언제나 **첫 득점**이다: 사람 반응 한계 0.15초 대 advance 1 의 하한 0.095초.)
        #expect(tightestRatio > 1, "가장 빡빡한 자리에서 여유가 사라졌다(배율 \(tightestRatio))")

        // ★ arm 별 하한 — **둘 다 실제로 재고 있는가.** 한 arm 이 판 앞머리에서 죽으면 그 arm 이 지나는 배선
        //   (쓸기 = 가로 끌기·소프트드롭)은 사실상 안 재는 것인데, 합계만 보면 그게 안 보인다.
        for strategy in ["stack", "swipe"] {
            let depth = deepestByStrategy[strategy] ?? 0
            let score = bestByStrategy[strategy] ?? 0
            #expect(depth >= 150, "\(strategy) arm 이 advance \(depth) 에서 끝났다 — 그 배선은 판 앞머리만 재고 있다")
            #expect(score >= 10_000, "\(strategy) arm 이 \(score)점뿐이다 — 그 점수대의 서버 하한은 1초 미만이라 판별력이 없다")
            let ratio = tightestByStrategy[strategy] ?? .infinity
            #expect(ratio > 1, "\(strategy) arm 의 여유가 사라졌다(배율 \(ratio))")
            #expect(ratio < 60, "\(strategy) arm 의 여유가 \(ratio)배다 — 하한 근처를 한 번도 안 지나 사실상 무조건 초록이다")
            print("[sim] tetris \(strategy): 최대 advance=\(depth) 최고 점수=\(score) 가장 빡빡한 여유=\(String(format: "%.1f", ratio))x")
        }
        print("[sim] tetris 가장 빡빡한 여유 배율=\(String(format: "%.1f", tightestRatio))x · 최대 advance=\(deepestAdvance)")
    }
}
