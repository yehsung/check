import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.46 플래피 아잉 — 규칙(순수)·난이도 곡선·상태 전이·dt 클램프·렌더·프레임 프로브·소스 계약.
//
// 판은 논리 292×302 다(창 캔버스 344×356 과 같은 비율 — 위아래 레터박스 없이 꽉 찬다).
// 물리 상수는 그 세로 길이에 맞춘 값이다: 중력 1360 · 점프 −317 · 낙하 574 · 히트박스 24 · 스프라이트 34.
// 난이도 곡선: 속도 130→230(3/점, 34점 상한) · 틈 132→96(3/점, 12점 하한) · 간격 150→115(2/점, 18점 하한).
// 15점부터는 20% 확률로 '틈이 한 번 확 튀는' 기둥이 섞인다(지연 0.45~1.10초 뒤 58pt, 0.12초 easeOut, 색 신호 없음).
//
// 2026-09-08 실기 지적 두 가지가 이 숫자들의 이유다 — (1) 292×200 을 344×356 에 비율 유지로 그리니 위아래가
// 60pt 씩 비어 기둥이 떠 보였다, (2) 상승 곡선이 약해 계속 쉬웠다.

private let W = FlappyGame.width      // 292
private let H = FlappyGame.height     // 302
private let birdX = FlappyGame.birdX  // 81.76
/// 창 캔버스 크기(미니게임 창은 고정 620×420 이고 그 안의 캔버스가 이 크기다).
private let CW: CGFloat = 344
private let CH: CGFloat = 356

private func pipe(x: CGFloat, centerY: CGFloat = H / 2, gap: CGFloat = 132, passed: Bool = false) -> FlappyGame.Pipe {
    FlappyGame.Pipe(x: x, centerY: centerY, gap: gap, passed: passed)
}

/// 튀는 기둥 픽스처. `at` 를 주면 이미 조준된(화면에 들어온) 상태다.
private func jumpPipe(x: CGFloat, centerY: CGFloat = H / 2, gap: CGFloat = 132,
                      delay: TimeInterval = 0.5, offset: CGFloat = FlappyGame.shiftJump,
                      at armedAt: TimeInterval? = nil) -> FlappyGame.Pipe {
    FlappyGame.Pipe(x: x, centerY: centerY, gap: gap, passed: false,
                    shiftDelay: delay, shiftOffset: offset, shiftAt: armedAt)
}

private func running(bird: FlappyGame.Bird, pipes: [FlappyGame.Pipe], score: Int = 0, seed: UInt64 = 1) -> FlappyGame {
    FlappyGame(seed: seed, bird: bird, pipes: pipes, score: score, phase: .running)
}

private func isOver(_ phase: FlappyGame.Phase) -> Bool {
    if case .over = phase { return true }
    return false
}

// MARK: - (0) 판 크기 — 캔버스를 꽉 채운다

@Test
func logicalBoardMatchesTheWindowCanvasAspectSoNothingIsLetterboxed() {
    #expect(FlappyGame.width == 292)
    #expect(FlappyGame.height == 302)
    #expect(FlappyGame.logicalSize == CGSize(width: 292, height: 302))
    // 창 캔버스(344×356)에 비율 유지로 얹으면 남는 여백이 가로 0 · 세로 0.5pt 미만이다.
    let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)
    #expect(abs(t.origin.x) < 0.01, "가로 여백 \(t.origin.x)")
    #expect(t.origin.y < 0.5, "세로 여백 \(t.origin.y) — 위아래가 비면 기둥이 천장·바닥에 안 닿는다")
    #expect(abs(t.scale * FlappyGame.height - CH) < 1)
    #expect(abs(t.scale * FlappyGame.width - CW) < 1)
}

@Test
func pipeHalvesReachTheCeilingAndTheFloor() {
    let p = pipe(x: 100, centerY: 150, gap: 132)   // 틈 84…216
    #expect(p.topRect(at: 0).minY == 0, "위 기둥은 천장(0)에서 시작한다")
    #expect(p.topRect(at: 0).maxY == 84)
    #expect(p.bottomRect(at: 0, height: H).minY == 216)
    #expect(p.bottomRect(at: 0, height: H).maxY == H, "아래 기둥은 바닥(302)까지 내려간다 — 바닥 띠는 없다")
    // 두 조각이 틈만 남기고 세로 전체를 덮는다.
    #expect(p.topRect(at: 0).height + p.gap + p.bottomRect(at: 0, height: H).height == H)
}

// MARK: - (1) 난이도 곡선

@Test
func gapShrinksThreePerPointDownToNinetySix() {
    #expect(FlappyGame.gap(forScore: 0) == 132)
    #expect(FlappyGame.gap(forScore: 1) == 129)
    #expect(FlappyGame.gap(forScore: 6) == 114)
    #expect(FlappyGame.gap(forScore: 11) == 99)
    #expect(FlappyGame.gap(forScore: 12) == 96, "12점부터 하한")
    #expect(FlappyGame.gap(forScore: 20) == 96)
    #expect(FlappyGame.gap(forScore: 999) == 96)
}

@Test
func speedGrowsThreePerPointUpToTwoThirty() {
    // 2026-09-08: 상승률 6→3, 상한 300→230. 그 자리에 '갑자기 튀는 틈'이 들어왔다.
    #expect(FlappyGame.speed(forScore: 0) == 130)
    #expect(FlappyGame.speed(forScore: 10) == 160)
    #expect(FlappyGame.speed(forScore: 33) == 229)
    #expect(FlappyGame.speed(forScore: 34) == 230, "34점부터 상한")
    #expect(FlappyGame.speed(forScore: 100) == 230)
    #expect(FlappyGame.speed(forScore: 500) == 230)
}

@Test
func spacingTightensTwoPerPointDownToOneFifteen() {
    #expect(FlappyGame.spacing(forScore: 0) == 150)
    #expect(FlappyGame.spacing(forScore: 10) == 130)
    #expect(FlappyGame.spacing(forScore: 17) == 116)
    #expect(FlappyGame.spacing(forScore: 18) == 115, "18점부터 하한")
    #expect(FlappyGame.spacing(forScore: 100) == 115)
}

@Test
func difficultyIsMonotonicUntilItFlattens() {
    // 점수가 오르면 빨라지고(속도 ↑) 좁아지고(틈 ↓) 잦아진다(간격 ↓). 상한·하한 뒤로는 평평하다.
    for (low, high) in [(0, 10), (10, 20), (5, 11)] {
        #expect(FlappyGame.speed(forScore: low) < FlappyGame.speed(forScore: high))
        #expect(FlappyGame.gap(forScore: low) > FlappyGame.gap(forScore: high))
        #expect(FlappyGame.spacing(forScore: low) > FlappyGame.spacing(forScore: high))
    }
    #expect(FlappyGame.speed(forScore: 34) == FlappyGame.speed(forScore: 900))
    #expect(FlappyGame.gap(forScore: 12) == FlappyGame.gap(forScore: 900))
    #expect(FlappyGame.spacing(forScore: 18) == FlappyGame.spacing(forScore: 900))
    // 음수 점수(있을 수 없지만)는 0 처럼 다룬다.
    #expect(FlappyGame.speed(forScore: -5) == 130 && FlappyGame.gap(forScore: -5) == 132)
}

// MARK: - (1b) 갑자기 튀는 틈

@Test
func surpriseJumpConstants() {
    // 사용자 결정 2026-09-08: 15점부터 · 30% 고정 확률 · 58pt 한 방 · 0.45~1.10초 지연 · 0.12초 보간.
    #expect(FlappyGame.shiftMinScore == 15)
    #expect(FlappyGame.shiftChance == 0.30)
    #expect(FlappyGame.shiftJump == 58)
    #expect(FlappyGame.shiftDelayRange == 0.45...1.10)
    #expect(FlappyGame.shiftDuration == 0.12)
}

@Test
func pipesBornBelowFifteenPointsNeverJump() {
    var rng = MiniGameRandom(seed: 11)
    for score in [0, 5, 14] {
        for _ in 0..<80 {
            let pipe = FlappyGame.makePipe(x: 0, score: score, rng: &rng)
            #expect(pipe.shiftDelay == nil, "\(score)점에서 생긴 기둥이 튄다")
            #expect(!pipe.isShifting)
            #expect(pipe.shiftOffset == 0)
            // 틈 보정도 없다 — 튀는 기둥이라고 넓혀 주지 않는다(2026-09-08 규칙 변경).
            #expect(pipe.gap == FlappyGame.gap(forScore: score))
        }
    }
}

@Test
func aboutAThirdOfPipesJumpOncePastFifteenPoints() {
    func jumpCount(seed: UInt64) -> Int {
        var rng = MiniGameRandom(seed: seed)
        return (0..<200).filter { _ in FlappyGame.makePipe(x: 0, score: 20, rng: &rng).isShifting }.count
    }
    let count = jumpCount(seed: 2026)
    // 시드 2026 에서 200개 중 정확히 56개(28.0%) — 결정론이라 값이 박힌다. 확률 상수를 건드리면 여기가 빨개진다.
    #expect(count == 56, "200개 중 \(count)개가 튄다 — 30% 언저리여야 한다")
    // 시드가 같으면 판도 같다(결정론).
    #expect(jumpCount(seed: 2026) == count)
    // 튀는 기둥도 틈은 고정 기둥과 같다.
    var rng = MiniGameRandom(seed: 3)
    for _ in 0..<120 {
        let pipe = FlappyGame.makePipe(x: 0, score: 20, rng: &rng)
        #expect(pipe.gap == FlappyGame.gap(forScore: 20))
    }
}

@Test
func theGapJumpsOnceAfterTheDelayAndStaysThere() {
    let pipe = jumpPipe(x: 100, centerY: 150, gap: 132, at: 1.0)
    // 조준 시각 전에는 기준선 그대로.
    #expect(pipe.center(at: 0) == 150)
    #expect(pipe.center(at: 0.999) == 150)
    // 0.12초 동안 easeOut 으로 옮겨 가고, 끝나면 그 자리에 머문다(왕복 없음).
    let mid = pipe.center(at: 1.0 + FlappyGame.shiftDuration / 2)
    #expect(mid > 150 && mid < 208, "보간 중간이 \(mid)")
    #expect(abs(pipe.center(at: 1.0 + FlappyGame.shiftDuration) - 208) < 1e-9)
    #expect(abs(pipe.center(at: 30) - 208) < 1e-9, "한 번 튀면 돌아오지 않는다")
    // 이동은 단조 증가한다(뒤로 물러서지 않는다).
    var previous = pipe.center(at: 1.0)
    for step in stride(from: 0.0, through: FlappyGame.shiftDuration, by: 0.01) {
        let now = pipe.center(at: 1.0 + step)
        #expect(now >= previous - 1e-9, "이동이 뒤로 갔다(\(previous) → \(now))")
        previous = now
    }
    // 위로 튀는 기둥도 같은 규칙.
    let up = jumpPipe(x: 100, centerY: 150, gap: 132, offset: -FlappyGame.shiftJump, at: 1.0)
    #expect(abs(up.center(at: 1.0 + FlappyGame.shiftDuration) - 92) < 1e-9)
}

@Test
func jumpDirectionAlwaysLandsInsideTheMargins() {
    var rng = MiniGameRandom(seed: 77)
    var jumps = 0
    for _ in 0..<400 {
        let pipe = FlappyGame.makePipe(x: 0, score: 40, rng: &rng)
        let lo = pipe.gap / 2 + FlappyGame.centerMargin
        let hi = H - pipe.gap / 2 - FlappyGame.centerMargin
        #expect(pipe.centerY >= lo && pipe.centerY <= hi, "기준선이 여백 밖(\(pipe.centerY))")
        guard pipe.isShifting else { continue }
        jumps += 1
        let landed = pipe.centerY + pipe.shiftOffset
        #expect(landed >= lo && landed <= hi, "튄 자리가 여백 밖(\(landed))")
        #expect(abs(pipe.shiftOffset) == FlappyGame.shiftJump)
        let delay = try! #require(pipe.shiftDelay)
        #expect(FlappyGame.shiftDelayRange.contains(delay))
    }
    #expect(jumps > 20, "400개 중 튀는 기둥이 \(jumps)개뿐이다")
}

@Test
func collisionFollowsTheMovedGapNotTheBaseline() {
    // 틈 132 가 기준선 150(84…216)에 있다가 아래로 58 튀면 142…274 — 히트박스(y 100)는 그때 위 기둥에 걸린다.
    let pipe = jumpPipe(x: birdX - 10, centerY: 150, gap: 132, at: 1.0)
    let side = FlappyGame.hitboxSize
    let box = CGRect(x: birdX - 10, y: 100 - side / 2, width: side, height: side)   // 88…112
    #expect(!FlappyGame.collides(bird: box, pipe: pipe, height: H, time: 0), "튀기 전엔 틈 안")
    #expect(FlappyGame.collides(bird: box, pipe: pipe, height: H, time: 1.0 + FlappyGame.shiftDuration),
            "튄 뒤엔 위 기둥에 걸린다")
}

@Test
func aPipeArmsItsJumpOnlyOnceItEntersTheScreen() {
    // 화면 밖(x = W + 40)에서는 조준되지 않는다 — 밖에서 튀면 보지도 못한 채 판이 바뀐다.
    var game = running(bird: .init(x: birdX, y: H / 2, vy: 0),
                       pipes: [jumpPipe(x: W + 40, gap: 132), pipe(x: W + 190), pipe(x: W + 340)], score: 20)
    game.step(dt: 1.0 / 60.0)
    #expect(game.pipes[0].shiftAt == nil, "화면 밖 기둥은 아직 조준되지 않는다")

    // 오른쪽 끝(x ≤ W)에 들어오는 순간 elapsed + delay 로 한 번 채워지고, 그 뒤로는 바뀌지 않는다.
    var entered = running(bird: .init(x: birdX, y: H / 2, vy: 0),
                          pipes: [jumpPipe(x: W + 0.5, gap: 132, delay: 0.7), pipe(x: W + 190), pipe(x: W + 340)],
                          score: 20)
    entered.step(dt: 1.0 / 60.0)
    let armed = try! #require(entered.pipes[0].shiftAt)
    #expect(abs(armed - (entered.elapsed + 0.7)) < 1e-9, "조준 시각이 \(armed)")
    entered.step(dt: 1.0 / 60.0)
    #expect(entered.pipes[0].shiftAt == armed, "조준은 한 번만 — 매 프레임 미뤄지면 영영 안 튄다")
}

@Test
func theBoardClockAdvancesOnlyWhileRunning() {
    var game = FlappyGame(seed: 4)
    game.step(dt: 1.0 / 30.0)
    #expect(game.elapsed == 0, "ready 에서는 시계가 안 간다")
    game.flap()
    game.step(dt: 1.0 / 30.0)
    #expect(abs(game.elapsed - 1.0 / 30.0) < 1e-9)
    // 새 판이면 0 부터 — 앞 판의 조준 시각이 새 판 기둥에 섞이지 않는다.
    game.interrupt()
    game.flap()
    #expect(game.elapsed == 0)
}

// MARK: - (1c) 그림 전용 상태 — 배경 시계 · 무대 · 점프/득점 기록

@Test
func scrolledAccumulatesExactlyLikeThePipesMove() {
    // 배경 패럴랙스의 유일한 시계다. 기둥과 같은 속도로 누적돼야 지면이 미끄러지지 않는다.
    var game = running(bird: .init(x: birdX, y: H / 2, vy: 0), pipes: [pipe(x: 600)], score: 10)
    #expect(game.scrolled == 0)
    game.step(dt: 1.0 / 60.0)
    #expect(abs(game.scrolled - FlappyGame.speed(forScore: 10) / 60) < 1e-9)
    #expect(abs((600 - game.pipes[0].x) - game.scrolled) < 1e-9, "배경과 기둥이 갈라졌다")
    game.step(dt: 1.0 / 60.0)
    #expect(abs(game.scrolled - FlappyGame.speed(forScore: 10) / 30) < 1e-9)
    // 시작 전·결과에서는 흐르지 않는다(정지 화면에서 배경만 흐르면 판이 도는 것처럼 보인다).
    var idle = FlappyGame(seed: 1)
    idle.step(dt: 1)
    #expect(idle.scrolled == 0)
}

@Test
func stageFollowsTheScoreBandsAndTheCurvesDoNotCare() {
    #expect(MiniGameStage.flappyThresholds == [0, 6, 13, 22, 34])
    for (score, id) in [(0, 0), (5, 0), (6, 1), (12, 1), (13, 2), (21, 2), (22, 3), (33, 3), (34, 4), (999, 4)] {
        let game = running(bird: .init(x: birdX, y: H / 2, vy: 0), pipes: [pipe(x: 600)], score: score)
        #expect(game.stage.id == id, "\(score)점의 무대가 \(game.stage.id)")
    }
    // 무대 경계는 튀는 기둥이 시작되는 15와 겹치지 않는다 — 배경이 바뀌는 순간이 예고가 되면 안 된다.
    #expect(!MiniGameStage.flappyThresholds.contains(FlappyGame.shiftMinScore))
    // 그리고 무대가 바뀌어도 난이도는 그 점수의 곡선 그대로다(색은 팔레트일 뿐이다).
    for score in [5, 6, 12, 13, 21, 22, 33, 34] {
        #expect(FlappyGame.gap(forScore: score) == max(96, 132 - CGFloat(3 * score)))
        #expect(FlappyGame.speed(forScore: score) == min(230, 130 + CGFloat(3 * score)))
    }
}

@Test
func viewOnlyMarkersRecordFlapsAndScores() {
    var game = FlappyGame(seed: 7)
    #expect(game.lastFlapAt == nil && game.flapCount == 0)

    game.flap()                                   // ready → running(첫 점프)
    #expect(game.flapCount == 1 && game.lastFlapAt == 0)
    game.step(dt: 1.0 / 60.0)
    game.flap()
    #expect(game.flapCount == 2)
    #expect(abs((game.lastFlapAt ?? -1) - game.elapsed) < 1e-9, "점프 시각은 판 시계 기준이다")

    // over 유예 중 클릭은 기록되지 않는다 — 죽은 뒤에 발밑 파편이 튀면 안 된다.
    var dying = running(bird: .init(x: birdX, y: 295, vy: 0), pipes: [pipe(x: 600)])
    dying.step(dt: 1.0 / 60.0)
    #expect(isOver(dying.phase))
    dying.flap()
    #expect(dying.flapCount == 0 && dying.lastFlapAt == nil)

    // 득점: 시각과 **그 기둥의 틈 중심**이 남는다("+1"과 링이 뜨는 자리).
    var scoring = running(bird: .init(x: birdX, y: H / 2, vy: 0),
                          pipes: [pipe(x: birdX - FlappyGame.pipeWidth + 0.5, centerY: 120, gap: 180),
                                  pipe(x: 400, gap: 180), pipe(x: 550, gap: 180)],
                          score: 5)
    scoring.step(dt: 1.0 / 60.0)
    #expect(scoring.score == 6)
    #expect(scoring.lastScoreAt == scoring.elapsed)
    #expect(scoring.lastScorePipeCenter == 120)
    // 무대(팔레트)는 점수에서 바로 나온다 — 5 → 6 은 새벽 → 한낮이다.
    #expect(scoring.stage == .day)

    // 새 판이면 그림용 기록도 전부 초기화된다 — 앞 판의 "+1"·파편이 새 판에 묻어 나오면 안 된다.
    scoring.interrupt()
    scoring.flap()
    #expect(scoring.scrolled == 0 && scoring.lastScoreAt == nil && scoring.lastScorePipeCenter == nil
            && scoring.flapCount == 1 && scoring.lastFlapAt == 0)
}

@Test
func theVisualOverhaulDidNotTouchASingleDifficultyConstant() {
    // v0.2.48 은 그림만 바꿨다(사용자 지적 2026-09-10). 순위표가 걸린 게임이라 아래 값이 하나라도
    // 움직이면 지난 기록의 의미가 깨진다 — 이 테스트가 그 증거다.
    #expect(FlappyGame.gravity == 1360)
    #expect(FlappyGame.flapVelocity == -317)
    #expect(FlappyGame.maxFallSpeed == 574)
    #expect(FlappyGame.hitboxSize == 24)
    #expect(FlappyGame.spriteSize == 34)
    #expect(FlappyGame.pipeWidth == 44)
    #expect(FlappyGame.centerMargin == 36)
    #expect(FlappyGame.firstPipeX == 372)
    #expect(FlappyGame.pipeCount == 3)
    #expect(FlappyGame.overHold == 0.4)
    #expect(FlappyGame.maxStep == 1.0 / 30.0)
    #expect(FlappyGame.width == 292 && FlappyGame.height == 302)
    #expect(FlappyGame.gap(forScore: 0) == 132 && FlappyGame.gap(forScore: 12) == 96)
    #expect(FlappyGame.speed(forScore: 0) == 130 && FlappyGame.speed(forScore: 34) == 230)
    #expect(FlappyGame.spacing(forScore: 0) == 150 && FlappyGame.spacing(forScore: 18) == 115)
    #expect(FlappyGame.shiftMinScore == 15 && FlappyGame.shiftChance == 0.30)
    #expect(FlappyGame.shiftJump == 58 && FlappyGame.shiftDuration == 0.12)
    #expect(FlappyGame.shiftDelayRange == 0.45...1.10)
    // 캔버스 실측 크기(344×356)도 불변 — 창을 키워도 캔버스는 그대로다(배율은 짧은 축인 가로가 정한다).
    #expect(abs(MiniGameCanvas.transform(in: CGSize(width: CW, height: CH),
                                         logicalSize: FlappyGame.logicalSize).scale - CW / W) < 1e-12)
}

// MARK: - (1d) 잔상은 규칙에서 통째로 사라졌다 (v0.2.51)
//
// 사용자 지시 2026-09-11: "그냥 잔상 없애줘." v0.2.49~50 의 잔상은 **규칙 값 타입이 들고 있는 궤적**
// (`FlappyGame.trail` · `TrailPoint` · `trailLife/Interval/Max` · `advanceTrail`)이었다. 뷰에서 그리는
// 겹만 지우면 매 프레임 배열을 밀고·버리고·붙이는 일이 그대로 남으므로 **규칙에서 지웠다.**
// 여기 있던 잔상 테스트 넷(궤적 적립 · 상한/수명 · 새 판에서 비우기 · 자세별 꼬리 방향)은 지운 기능을
// 검사하던 것이라 함께 지웠다. 되살아남을 막는 것은 아래 (8) 소스 계약의 `trail` 식별자 0회 검사다.

// MARK: - (2) 물리

@Test
func gravityIntegratesAndClampsFallSpeed() {
    // 점프 직후 −317 에서 1초 자유낙하: −317 + 1360 = 1043 → 574 클램프.
    #expect(FlappyGame.nextVelocity(FlappyGame.flapVelocity, dt: 1.0) == 574)
    #expect(abs(FlappyGame.nextVelocity(0, dt: 1.0 / 30.0) - 1360.0 / 30.0) < 1e-9)

    // 실제 판: 위쪽에서 떨어뜨리면 13 프레임(0.433초, 45.33×13 = 589 → 574) 뒤 속도가 574 에 닿고
    // 아직 바닥엔 안 닿는다(y = 20 + 4110/30 = 157, 히트박스 아래 169 < 302).
    var game = running(bird: .init(x: birdX, y: 20, vy: 0), pipes: [pipe(x: 600)])
    for _ in 0..<13 { game.step(dt: 1.0 / 30.0) }
    #expect(game.bird.vy == 574)
    #expect(abs(game.bird.y - 157) < 1e-6)
    #expect(game.phase == .running)
    #expect(game.hitbox.maxY < H)
}

@Test
func flapSetsUpwardVelocityAndCeilingStopsTheBirdWithoutKilling() {
    var game = running(bird: .init(x: birdX, y: 150, vy: 0), pipes: [pipe(x: 600)])
    game.flap()
    #expect(game.bird.vy == -317)

    // 천장: 히트박스 윗변이 0 에 붙고 속도는 0, 충돌은 아니다.
    var top = running(bird: .init(x: birdX, y: FlappyGame.hitboxSize / 2, vy: -317), pipes: [pipe(x: 600)])
    top.step(dt: 1.0 / 60.0)
    #expect(top.hitbox.minY == 0)
    #expect(top.bird.vy == 0)
    #expect(top.phase == .running)
}

@Test
func jumpHeightStaysAboutAnEighthOfTheBoard() {
    // 점프 높이 = v² / (2g) = 317² / 2720 ≈ 36.9pt. 판(302)의 12.2% — 200pt 판의 24.5pt(12.25%)와 같은 비율이다.
    let jump = pow(FlappyGame.flapVelocity, 2) / (2 * FlappyGame.gravity)
    #expect(abs(jump - 36.94) < 0.1)
    #expect(abs(jump / H - 0.1225) < 0.005, "점프가 판 대비 너무 크거나 작다(\(jump / H))")
}

@Test
func seededPipesStayInsideTheVerticalMargins() {
    var rng = MiniGameRandom(seed: 42)
    for _ in 0..<100 {
        let p = FlappyGame.makePipe(x: 0, score: 0, rng: &rng)
        #expect(p.gap == 132)
        #expect(p.centerY >= 132 / 2 + 36 && p.centerY <= H - 132 / 2 - 36)   // 102…200
    }
    for _ in 0..<100 {
        let p = FlappyGame.makePipe(x: 0, score: 40, rng: &rng)
        #expect(p.gap == 96)
        #expect(p.centerY >= 96 / 2 + 36 && p.centerY <= H - 96 / 2 - 36)     // 84…218
    }
    // 같은 시드는 같은 기둥.
    var a = MiniGameRandom(seed: 9), b = MiniGameRandom(seed: 9)
    #expect(FlappyGame.makePipe(x: 0, score: 0, rng: &a) == FlappyGame.makePipe(x: 0, score: 0, rng: &b))
}

// MARK: - (3) 충돌 · 점수

@Test
func passingThroughTheGapScoresOnceAndKeepsRunning() {
    // 틈을 크게(180) 두고 바로 앞에 기둥. 속도가 붙으면 점프해 틈 안에 머문다.
    var game = running(bird: .init(x: birdX, y: H / 2, vy: 0),
                       pipes: [pipe(x: birdX + 5, gap: 180), pipe(x: 400, gap: 180), pipe(x: 550, gap: 180)])
    // 40프레임(0.67초)이면 기둥이 49pt 를 지나 점수가 나고, 아직 재활용(x + 44 < 0)되기 전이다.
    for _ in 0..<40 {
        if game.bird.vy > 100 { game.flap() }
        game.step(dt: 1.0 / 60.0)
    }
    #expect(game.score == 1, "기둥 하나를 지났으니 1점")
    #expect(game.pipes.first?.passed == true)
    #expect(game.phase == .running)
    // 더 지나도 같은 기둥으로 다시 점수가 나지 않는다.
    for _ in 0..<10 {
        if game.bird.vy > 100 { game.flap() }
        game.step(dt: 1.0 / 60.0)
    }
    #expect(game.score == 1)
}

@Test
func hittingTheTopPipeEndsTheRound() {
    var game = running(bird: .init(x: birdX, y: 20, vy: 0), pipes: [pipe(x: birdX - 12, centerY: 100, gap: 74)])
    game.step(dt: 1.0 / 60.0)
    #expect(isOver(game.phase))
    #expect(game.flashRemaining == FlappyGame.flashDuration)
    #expect(game.isPlaying, "over 유예 동안은 루프가 돌아야 결과 카드로 넘어간다")
    #expect(game.isGameOver)
}

@Test
func touchingTheFloorEndsTheRound() {
    // 바닥은 캔버스 아랫변(302) 자체다 — 별도 바닥 띠가 없다.
    var game = running(bird: .init(x: birdX, y: 295, vy: 0), pipes: [pipe(x: 600)])
    game.step(dt: 1.0 / 60.0)
    #expect(isOver(game.phase))
    #expect(game.hitbox.maxY >= H)

    // 조금 위(280)면 아직 산다.
    var alive = running(bird: .init(x: birdX, y: 280, vy: 0), pipes: [pipe(x: 600)])
    alive.step(dt: 1.0 / 60.0)
    #expect(alive.phase == .running)
}

@Test
func overHoldExpiresIntoResultAndIgnoresFlapsMeanwhile() {
    var game = running(bird: .init(x: birdX, y: 295, vy: 0), pipes: [pipe(x: 600)], score: 7)
    game.step(dt: 1.0 / 60.0)
    #expect(isOver(game.phase))
    game.flap()
    #expect(isOver(game.phase), "죽자마자 온 클릭은 새 판을 열지 않는다")
    for _ in 0..<15 { game.step(dt: 1.0 / 30.0) }   // 0.5초 > 0.4초 유예
    #expect(game.phase == .result)
    #expect(game.score == 7, "점수는 그대로 유효")
    #expect(!game.isPlaying)
    #expect(game.flashRemaining == 0)
}

@Test
func reachingTheScoreCapEndsInResultImmediately() {
    let almost = pipe(x: birdX - FlappyGame.pipeWidth + 0.5, gap: 180)
    var game = running(bird: .init(x: birdX, y: H / 2, vy: 0), pipes: [almost, pipe(x: 400, gap: 180), pipe(x: 550, gap: 180)],
                       score: FlappyGame.maxScore - 1)
    game.step(dt: 1.0 / 60.0)
    #expect(game.score == 999)
    #expect(game.phase == .result)
}

@Test
func collisionIsAxisAlignedBoxAgainstBothPipeHalves() {
    let p = pipe(x: 100, centerY: 100, gap: 74)   // 위 0..63, 아래 137..302
    let side = FlappyGame.hitboxSize
    let inside = CGRect(x: 100, y: 89, width: side, height: side)     // 틈 안(89..113)
    let top = CGRect(x: 100, y: 45, width: side, height: side)        // 위 기둥과 겹침
    let bottom = CGRect(x: 100, y: 125, width: side, height: side)    // 아래 기둥과 겹침
    let beside = CGRect(x: 30, y: 45, width: side, height: side)      // 기둥 왼쪽 밖
    #expect(!FlappyGame.collides(bird: inside, pipe: p, height: H, time: 0))
    #expect(FlappyGame.collides(bird: top, pipe: p, height: H, time: 0))
    #expect(FlappyGame.collides(bird: bottom, pipe: p, height: H, time: 0))
    #expect(!FlappyGame.collides(bird: beside, pipe: p, height: H, time: 0))
}

@Test
func pipesRecycleBehindTheLastOneWithTheCurrentGapAndSpacing() {
    // 첫 기둥이 왼쪽으로 완전히 나가면(x + 44 < 0) 버리고 마지막 기둥 뒤 `spacing(현재 점수)` 에 새 기둥을 단다.
    // 한 프레임으로 딱 그 순간만 본다: 점수 5 → 속도 145(1/60 에 2.417pt) · 간격 140 · 틈 117.
    // 점수 5 는 튀는 기둥 최소 점수(15) 미만이라 새 기둥도 고정이다.
    var game = running(bird: .init(x: birdX, y: H / 2, vy: 0),
                       pipes: [pipe(x: -50, gap: 180, passed: true),
                               pipe(x: 100, gap: 180, passed: true),
                               pipe(x: 250, gap: 180)],
                       score: 5, seed: 5)
    game.step(dt: 1.0 / 60.0)

    #expect(game.phase == .running)
    #expect(game.score == 5, "이미 지난 기둥으로 점수가 다시 나지 않는다")
    #expect(game.pipes.count == FlappyGame.pipeCount, "기둥은 언제나 \(FlappyGame.pipeCount)개")
    let fresh = try! #require(game.pipes.last)
    #expect(abs(fresh.x - (250 - 145.0 / 60.0 + FlappyGame.spacing(forScore: 5))) < 1e-6, "새 기둥이 \(fresh.x)")
    #expect(!fresh.isShifting, "15점 미만에서 생긴 기둥은 고정이다")
    #expect(fresh.gap == FlappyGame.gap(forScore: 5))
    #expect(fresh.gap == 117)
    #expect(!fresh.passed)
    #expect(abs((fresh.x - game.pipes[1].x) - FlappyGame.spacing(forScore: 5)) < 1e-6, "간격은 현재 점수 기준")
}

// MARK: - (4) 상태 전이

@Test
func readyFlapStartsARoundWithThreePipesAndAJump() {
    var game = FlappyGame(seed: 7)
    #expect(game.phase == .ready)
    #expect(!game.isPlaying)
    #expect(game.pipes.isEmpty)

    game.flap()
    #expect(game.phase == .running)
    #expect(game.isPlaying)
    #expect(game.bird.vy == -317)
    #expect(game.bird.x == birdX && game.bird.y == H / 2)
    #expect(game.pipes.count == 3)
    #expect(game.pipes[0].x == W + 80)          // 372
    #expect(game.pipes[1].x == W + 80 + 150)    // 522 — spacing(0)
    #expect(game.pipes[2].x == W + 80 + 300)    // 672
    #expect(game.pipes.allSatisfy { $0.gap == 132 })
}

@Test
func interruptWhileRunningSettlesTheScoreAsResult() {
    var game = FlappyGame(seed: 7)
    game.interrupt()
    #expect(game.phase == .ready, "시작 전 interrupt 는 아무것도 아니다")

    game.flap()
    game.step(dt: 1.0 / 60.0)
    game.interrupt()
    #expect(game.phase == .result)
    #expect(!game.isPlaying)

    // 결과에서 클릭 = 새 판(점수·기둥·캐릭터 초기화).
    let oldPipes = game.pipes
    game.flap()
    #expect(game.phase == .running)
    #expect(game.score == 0)
    #expect(game.bird.y == H / 2 && game.bird.vy == -317)
    #expect(game.pipes.count == 3 && game.pipes[0].x == W + 80)
    #expect(game.pipes.allSatisfy { !$0.passed })
    #expect(game.pipes != oldPipes || oldPipes.isEmpty)
}

// MARK: - (5) dt 클램프

@Test
func hugeDeltaTimeIsClampedToOneThirtieth() {
    var game = running(bird: .init(x: birdX, y: 100, vy: 0), pipes: [pipe(x: 600)])
    game.step(dt: 5)
    #expect(abs(game.bird.vy - 1360.0 / 30.0) < 1e-9, "1360 × 1/30 = 45.33 — 5초를 한 번에 밀지 않는다")
    #expect(abs(game.bird.y - (100 + (1360.0 / 30.0) / 30.0)) < 1e-6)
    #expect(abs(game.pipes[0].x - (600 - 130.0 / 30.0)) < 1e-6)
    #expect(game.phase == .running)

    // 음수 dt 는 0 으로.
    var still = running(bird: .init(x: birdX, y: 100, vy: 0), pipes: [pipe(x: 600)])
    still.step(dt: -1)
    #expect(still.bird.y == 100 && still.pipes[0].x == 600)
}

// MARK: - (6)(7) 렌더 · 프레임 프로브

private enum FlappyRenderError: Error { case failed }

@MainActor
private func renderBitmap(_ view: some View, width: CGFloat = CW, height: CGFloat = CH) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(CheckTheme.panel))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
        throw FlappyRenderError.failed
    }
    return bitmap
}

private func savePNG(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: name, sub: "flappy")
}

/// 영역 안에서 predicate(r,g,b,a) 를 만족하는 픽셀 수. 좌표는 pt(스케일 2).
private func count(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
                   where predicate: (Int, Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(bitmap.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(y.upperBound * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var n = 0
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3])) { n += 1 }
        }
    }
    return n
}

/// 논리 좌표 한 점의 색(스케일 2 비트맵). 두 기둥의 색이 같은지 직접 비교할 때 쓴다.
@MainActor
private func pixel(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> [Int]? {
    let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)
    let px = Int((t.origin.x + x * t.scale) * 2), py = Int((t.origin.y + y * t.scale) * 2)
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4,
          px >= 0, px < bitmap.pixelsWide, py >= 0, py < bitmap.pixelsHigh else { return nil }
    let o = py * bitmap.bytesPerRow + px * bitmap.samplesPerPixel
    return [Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3])]
}

/// 영역에서 파랑이 가장 진한 불투명 픽셀의 색. 테두리 원색을 위치와 무관하게 집어낸다.
private func brightestBlue(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> [Int] {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return [] }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(bitmap.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(y.upperBound * 2))
    var best: [Int] = []
    guard x0 <= x1, y0 <= y1 else { return best }
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            let value = [Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3])]
            guard value[3] >= 250 else { continue }
            if best.isEmpty || value[2] > best[2] { best = value }
        }
    }
    return best
}

/// 카드 바탕 panelElevated (54,56,74) — 바닥(panel + fieldFill ≈ (35,37,49))·기둥·스프라이트와 겹치지 않는 서명.
private func isCardPixel(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    a >= 250 && abs(r - 54) <= 8 && abs(g - 56) <= 8 && abs(b - 74) <= 8
}
/// Color → sRGB 정수 3채널.
private func rgb255(_ color: Color) -> (r: Int, g: Int, b: Int) {
    let ns = (NSColor(color).usingColorSpace(.sRGB)) ?? .black
    return (Int((ns.redComponent * 255).rounded()),
            Int((ns.greenComponent * 255).rounded()),
            Int((ns.blueComponent * 255).rounded()))
}

/// 기둥 **본체** 서명. 채움이 `structureDeep → structureDeepLit` 세로 그라디언트라(v0.2.48 후반: 캐릭터와
/// 3:1 이상 벌리려고 본체를 어두운 대역으로 내렸다), 그 두 색을 잇는 선분에서 가까운 픽셀을 기둥으로 본다.
/// 밝은 립·경계선·외곽선(structureEdge)은 **일부러 뺀다** — 본체가 그려졌는지를 재는 서명이기 때문이다.
/// v0.2.51 도 기둥은 v0.2.50 그대로다(2026-09-11 추가 지시). 서명을 `structureDeep` 단색으로 좁히지 마라 —
/// 그라디언트 기둥을 못 물어 천장 줄이 0픽셀로 나온다(2026-09-11 검토 실측). 단색 서명은 기둥을 단순화한
/// 초안에만 맞던 자였다.
///
/// 허용오차가 14 인 이유: 본체는 선분 위에 정확히 놓이므로(디더 ±1) 넉넉하고, 배경 중 가장 가까운
/// 새벽 먼 능선이 21.9 라 그 사이에 선을 그었다. 예전 42 는 어두워진 본체에서 배경까지 함께 물었다.
private func pipePixel(_ stage: MiniGameStage, tolerance: Double = 14) -> (Int, Int, Int, Int) -> Bool {
    let lo = rgb255(stage.structureDeep), hi = rgb255(stage.structureDeepLit)
    let dx = Double(hi.r - lo.r), dy = Double(hi.g - lo.g), dz = Double(hi.b - lo.b)
    let length = max(dx * dx + dy * dy + dz * dz, 1e-9)
    return { r, g, b, a in
        guard a >= 250 else { return false }
        let px = Double(r - lo.r), py = Double(g - lo.g), pz = Double(b - lo.b)
        let t = min(max((px * dx + py * dy + pz * dz) / length, 0), 1)
        let ex = px - dx * t, ey = py - dy * t, ez = pz - dz * t
        return ex * ex + ey * ey + ez * ez <= tolerance * tolerance
    }
}
private func isInkPixel(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    a >= 250 && min(r, min(g, b)) >= 215
}

@MainActor
private func view(_ game: FlappyGame, best: Int = 0, reduceMotion: Bool = false) -> FlappyGameView {
    FlappyGameView(host: .inert(bestScore: best, reduceMotion: reduceMotion),
                   input: MiniGameInput(), initialGame: game)
}

/// 판을 **보이지 않는 실제 창**에 올리고 메인 런루프를 20ms 씩 돌리며 `MiniGameFrameProbe` 를 센다.
/// ImageRenderer 는 TimelineView 틱을 돌리지 않아 프로브가 언제나 0 이다 — 유휴 검사는 이 길로만 한다.
///
/// 예산은 벽시계가 아니라 **스핀 횟수**다: 병렬 스위트에서 다른 @MainActor 테스트가 내 스핀 안에 중첩 실행되면
/// 벽시계 마감은 통째로 타 버린다(V0238CharacterTests 실측). 창은 알파 0 · 테두리 없음 · 마우스 무시이고
/// 화면에 올리지 않는다 — 테스트가 데스크톱에 그림을 띄우지 않게.
@MainActor
private func hostedFrameCount(_ game: FlappyGame, isPaused: Bool = false, spins: Int = 250,
                              stopWhen: (Int) -> Bool = { _ in false }) -> Int {
    let root = FlappyGameView(host: .inert(isPaused: isPaused), input: MiniGameInput(), initialGame: game)
        .frame(width: CW, height: CH)
    let hosting = NSHostingView(rootView: root)
    hosting.frame = NSRect(x: 0, y: 0, width: CW, height: CH)
    let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: CW, height: CH),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.contentView = hosting
    defer {
        window.contentView = nil
        window.orderOut(nil)
    }
    // 창에 붙는 첫 레이아웃이 끝난 뒤부터 센다.
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    MiniGameFrameProbe.reset()
    for _ in 0..<spins {
        if stopWhen(MiniGameFrameProbe.frames) { break }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    return MiniGameFrameProbe.frames
}

/// 두 비트맵이 `tolerance` 를 넘게 다른 첫 자리(같으면 nil). 튀는 기둥이 고정 기둥과 같게 그려지는지,
/// 동작 줄이기에서 장식이 정말 빠지는지를 색 서명 없이 못 박는다.
///
/// ⚠️ 허용오차가 0 이 아닌 이유(실측 2026-09-10): 스위트를 통째로 돌리면 **같은 스프라이트**를 두 번 그려도
/// 채널당 최대 2 가 흔들린다(마스코트 PNG 를 .interpolation(.high) 로 축소하는 리샘플 결과가 앞선 렌더에
/// 영향을 받는다 — 이 테스트 하나만 돌리면 0 이다). 색·모양 신호는 수십 단위로 벌어지므로 2 로도 충분히 잡힌다.
private func firstPixelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep,
                                  tolerance: Int = 2) -> String? {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          lhs.bytesPerRow == rhs.bytesPerRow, lhs.samplesPerPixel == rhs.samplesPerPixel else {
        return "비트맵 크기가 다르다"
    }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    for py in 0..<lhs.pixelsHigh {
        for px in 0..<lhs.pixelsWide {
            let o = py * bpr + px * spp
            for channel in 0..<spp where abs(Int(a[o + channel]) - Int(b[o + channel])) > tolerance {
                return "(\(px), \(py)) 채널 \(channel): \(a[o + channel]) vs \(b[o + channel])"
            }
        }
    }
    return nil
}

/// 그 영역에서 두 비트맵이 다른 픽셀 수. "여기에 무언가가 그려졌다"를 **색 서명 없이** 확인한다 —
/// 배경이 무대마다 바뀌면서 예전의 "바닥색(35,37,49)과 다르다"는 기준은 아무것도 증명하지 못하게 됐다(v0.2.48).
private func differing(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep,
                       x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>, tolerance: Int = 2) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.bytesPerRow == rhs.bytesPerRow, lhs.samplesPerPixel == rhs.samplesPerPixel else { return 0 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(lhs.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(lhs.pixelsHigh - 1, Int(y.upperBound * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var n = 0
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            if (0..<spp).contains(where: { abs(Int(a[o + $0]) - Int(b[o + $0])) > tolerance }) { n += 1 }
        }
    }
    return n
}

@Suite(.serialized)
@MainActor
struct V0246MiniGameFlappyRenderTests {
    /// 창 캔버스에서 논리 좌표 → 화면 좌표.
    private var t: (scale: CGFloat, origin: CGPoint) {
        MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)
    }

    @Test
    func runningFrameShowsPipesTouchingCeilingAndFloor() throws {
        // 기둥 x 160(폭 44) · 틈 132 를 151 에 두면 위 0…85 · 아래 217…302 로 천장·바닥에 닿는다.
        let game = running(bird: .init(x: birdX, y: 151, vy: 0),
                           pipes: [pipe(x: 160, centerY: 151, gap: 132), pipe(x: 310), pipe(x: 460)], score: 3)
        let bitmap = try renderBitmap(view(game))
        savePNG(bitmap, "flappy-running.png")
        #expect(bitmap.pixelsWide == Int(CW) * 2 && bitmap.pixelsHigh == Int(CH) * 2)
        #expect(game.stage == .dawn, "3점은 새벽 무대다")

        // 기둥이 그려진 화면 x 대역(안쪽으로 2pt 씩 좁혀 테두리 안티앨리어싱을 피한다).
        let px0 = t.origin.x + 160 * t.scale + 2, px1 = t.origin.x + (160 + FlappyGame.pipeWidth) * t.scale - 2
        // ★ 천장 맨 윗줄과 바닥 맨 아랫줄에 기둥 픽셀이 있다 — "떠 있는 막대"였던 것이 이 판의 이유다.
        #expect(count(bitmap, x: px0...px1, y: 0...2, where: pipePixel(.dawn)) > 40, "기둥이 천장에 안 닿는다")
        #expect(count(bitmap, x: px0...px1, y: (CH - 3)...(CH - 0.5), where: pipePixel(.dawn)) > 40,
                "기둥이 바닥에 안 닿는다")
        // 틈(151 ± 66 → 화면 100…255)엔 기둥이 없다. 하늘·별·능선은 무대 기둥색과 멀다.
        #expect(count(bitmap, x: px0...px1, y: 110...245, where: pipePixel(.dawn)) == 0)
        // 히트박스 자리에 스프라이트가 있다 — 캐릭터를 판 밖으로 옮긴 같은 프레임과 비교한다
        // (배경이 무대마다 바뀌므로 "바닥색과 다르다"로는 더 이상 아무것도 증명되지 않는다).
        let box = game.hitbox
        let bx = t.origin.x + box.minX * t.scale, by = t.origin.y + box.minY * t.scale
        let noBird = FlappyGame(seed: 1, bird: .init(x: birdX, y: -400, vy: 0),
                                pipes: game.pipes, score: 3, phase: .running)
        let without = try renderBitmap(view(noBird))
        #expect(differing(bitmap, without, x: bx...(bx + box.width * t.scale),
                          y: by...(by + box.height * t.scale)) > 300, "스프라이트가 안 보인다")
        // 진행 중엔 카드가 없고, 상단 점수(흰 글씨)는 있다.
        #expect(count(bitmap, x: 0...CW, y: 0...CH, where: isCardPixel) < 100,
                "카드(수천 픽셀)는 없다 — 스프라이트 가장자리 안티앨리어싱 몇십 픽셀은 허용")
        // 점수는 **가운데 위** 큰 숫자 하나다(v0.2.46 자리로 되돌렸다 — 2026-09-11 "나머지 다 초기로").
        // 왼쪽 위의 무대 점 5개·이름 칩과 오른쪽 위 정렬은 함께 지웠다.
        #expect(count(bitmap, x: 140...210, y: 8...50, where: isInkPixel) > 30, "가운데 위에 점수가 없다")
        #expect(count(bitmap, x: 290...335, y: 8...50, where: isInkPixel) == 0, "점수가 아직 오른쪽 위에 있다")
        #expect(count(bitmap, x: 14...110, y: 12...50, where: isInkPixel) == 0, "왼쪽 위에 HUD 잔재가 있다")
    }

    @Test
    func jumpedPipeLooksExactlyLikeAFixedOne() throws {
        // 왼쪽은 고정 기둥, 오른쪽은 이미 튄 기둥(조준 0.5초 + 보간 0.12초 → elapsed 1.0 이면 다 튀었다).
        // 사용자 결정 2026-09-08: 색으로 미리 알려 주지 않는다 — 두 기둥의 픽셀 서명이 같아야 한다.
        let fixed = pipe(x: 60, centerY: 151, gap: 132)
        let jumped = jumpPipe(x: 200, centerY: 151, gap: 132, at: 0.5)
        let game = FlappyGame(seed: 3, bird: .init(x: birdX, y: 151, vy: 0),
                              pipes: [fixed, jumped, pipe(x: 460)], score: 20, phase: .running, elapsed: 1.0)
        let bitmap = try renderBitmap(view(game))
        savePNG(bitmap, "flappy-shift.png")

        // 튄 기둥의 틈은 기준선 151 이 아니라 209 에 있다(아래로 58).
        #expect(abs(jumped.center(at: 1.0) - 209) < 1e-6)

        func band(_ x: CGFloat) -> ClosedRange<CGFloat> {
            (t.origin.x + x * t.scale + 3)...(t.origin.x + (x + FlappyGame.pipeWidth) * t.scale - 3)
        }
        // 두 기둥 모두 천장·바닥에 붙어 있고,
        #expect(count(bitmap, x: band(60), y: 0...2, where: pipePixel(.dusk)) > 40)
        #expect(count(bitmap, x: band(200), y: 0...2, where: pipePixel(.dusk)) > 40)
        // 같은 y 에서 두 기둥의 **픽셀 색이 같다** = 채움·테두리 색과 굵기가 같다(개수 비교는 x 반올림에 흔들린다).
        let fixedInk = count(bitmap, x: band(60), y: 20...60, where: pipePixel(.dusk))
        let jumpedInk = count(bitmap, x: band(200), y: 20...60, where: pipePixel(.dusk))
        #expect(fixedInk > 100 && jumpedInk > 100, "고정 \(fixedInk) · 튄 것 \(jumpedInk)")
        let fixedColor = try #require(pixel(bitmap, x: 60 + FlappyGame.pipeWidth / 2, y: 40))
        let jumpedColor = try #require(pixel(bitmap, x: 200 + FlappyGame.pipeWidth / 2, y: 40))
        // 채움은 v0.2.48 부터 세로 그라디언트다. Core Graphics 는 그라디언트를 **x 마다 다르게 디더**하므로
        // 서로 다른 x 에 있는 두 기둥은 채널당 ±1 이 뜬다 — 눈에 보이는 차이가 아니다.
        // "완전히 같다"는 아래 전체 화면 비교가 못 박는다(같은 자리의 고정 기둥과 한 바이트도 다르지 않다).
        #expect(zip(fixedColor, jumpedColor).allSatisfy { abs($0.0 - $0.1) <= 2 },
                "채움 색이 다르다 — 고정 \(fixedColor) · 튄 것 \(jumpedColor)")
        // 테두리도 같은 색이다. 가장자리 한 점을 집으면 x 소수점 위치에 따라 안티앨리어싱이 달라지므로,
        // 띠 안에서 **가장 진한 파랑**(= 테두리 원색)을 골라 비교한다.
        let fixedEdge = brightestBlue(bitmap, x: band(60), y: 20...60)
        let jumpedEdge = brightestBlue(bitmap, x: band(200), y: 20...60)
        #expect(fixedEdge.count == jumpedEdge.count
                && zip(fixedEdge, jumpedEdge).allSatisfy { abs($0.0 - $0.1) <= 2 },
                "테두리 색이 다르다 — 고정 \(fixedEdge) · 튄 것 \(jumpedEdge)")
        // ★ 그리고 **화면 전체가 눈에 띄게 다르지 않다**: 같은 자리에 있는 고정 기둥으로 바꿔 그려도
        //   그림이 같아야 한다(허용오차 2 = 스프라이트 리샘플 흔들림. 위 firstPixelDifference 주석 참고).
        //   v0.2.48 에서 무대 색이 주황인 구간(노을)이 생기면서 "주황 픽셀이 없다"는 예전 스캔은 더 이상
        //   신호가 아니다 — 대신 픽셀 동일성으로 못 박는다(사용자 결정 2026-09-08).
        let plain = FlappyGame(seed: 3, bird: .init(x: birdX, y: 151, vy: 0),
                               pipes: [fixed, pipe(x: 200, centerY: 209, gap: 132), pipe(x: 460)],
                               score: 20, phase: .running, elapsed: 1.0)
        #expect(abs(jumped.center(at: 1.0) - plain.pipes[1].center(at: 1.0)) < 1e-9, "두 기둥의 틈이 같은 자리다")
        let plainBitmap = try renderBitmap(view(plain))
        #expect(firstPixelDifference(bitmap, plainBitmap) == nil,
                "튄 기둥이 고정 기둥과 다르게 그려진다 — \(firstPixelDifference(bitmap, plainBitmap) ?? "")")
    }

    @Test
    func readyStateShowsTheStartCardAndNoPipes() throws {
        let bitmap = try renderBitmap(view(FlappyGame(seed: 1)))
        savePNG(bitmap, "flappy-ready.png")
        #expect(count(bitmap, x: 0...CW, y: 0...CH, where: isCardPixel) > 800)
        #expect(count(bitmap, x: 0...CW, y: 0...CH, where: isInkPixel) > 60)
        // 기둥은 하나도 없다 — **천장 줄과 바닥 줄**에서 센다. 기둥은 언제나 위아래 끝에 붙으므로 그 두 줄이
        // 비어 있으면 기둥이 없는 것이다. (카드 안쪽은 무대 강조색이고 마스코트는 연보라라 넓은 띠로 세면
        // 무대 기둥색과 스친다 — 2026-09-10 에 캐릭터를 카드 위로 올리면서 실제로 겹쳤다.)
        #expect(count(bitmap, x: 0...CW, y: 0...4, where: pipePixel(.dawn)) == 0)
        #expect(count(bitmap, x: 0...CW, y: 350...CH, where: pipePixel(.dawn)) == 0)
        // 캐릭터는 v0.2.46 처럼 판 한가운데(높이/2 = 151)에 있고 **카드 뒤**다. v0.2.48 은 카드에 가리지
        // 않게 뷰에서만 74 로 올려 두는 자리(`readyPerch`)를 뒀는데, 2026-09-11 "나머지 다 초기로"에
        // 함께 빠졌다. 그래서 여기서 확인하는 것은 "카드가 그 자리를 덮는다"이다.
        #expect(count(bitmap, x: 0...CW, y: 0...CH, where: isCardPixel) > 800)
        // 시작 화면엔 프레임 루프도 장식 애니메이션도 없다(부유는 지웠다) — 유휴 0%.
    }

    @Test
    func resultStateShowsTheScoreCard() throws {
        let game = FlappyGame(seed: 1, bird: .init(x: birdX, y: 220, vy: 0), pipes: [pipe(x: 160)],
                              score: 12, phase: .result)
        let bitmap = try renderBitmap(view(game, best: 20))
        #expect(count(bitmap, x: 0...CW, y: 0...CH, where: isCardPixel) > 800)
        #expect(count(bitmap, x: 0...CW, y: 0...CH, where: isInkPixel) > 100)
        // 카드는 신기록이 아니면 working(초록) 글씨가 없다.
        let greenBefore = count(bitmap, x: 0...CW, y: 0...CH) { r, g, b, a in a >= 250 && g >= 200 && r <= 120 && b <= 190 }
        let record = try renderBitmap(view(game, best: 5))
        savePNG(record, "flappy-result.png")     // 스냅샷은 신기록 쪽을 남긴다(두 상태 중 화려한 쪽)
        let greenAfter = count(record, x: 0...CW, y: 0...CH) { r, g, b, a in a >= 250 && g >= 200 && r <= 120 && b <= 190 }
        #expect(greenAfter > greenBefore, "신기록이면 '신기록!' 초록 글씨가 생긴다")
    }

    /// ready 와 허브 일시정지에서는 **프레임 루프**가 0회다 — **실제 창에 올리고 런루프를 돌려서** 잰다.
    ///
    /// ⚠️ 왜 ImageRenderer 로 재지 않는가(2026-09-11 검토): ImageRenderer 는 한 장을 그리고 끝이라 TimelineView 의
    /// 틱을 한 번도 돌리지 않는다. 그 위의 "프레임 0" 은 `paused:` 에서 `!game.isPlaying` 을 빼도(= ready 에서도
    /// 루프가 도는 뮤턴트) 0 이어서 초록이었다 — 유휴 0% 를 아무것도 증명하지 못했다. 그래서 (1) running 대조군이
    /// 같은 창·같은 스핀에서 프레임을 **센다**는 것을 먼저 보이고, (2) 그 자로 ready 와 일시정지의 0 을 요구한다.
    /// 대조군이 빨개지면 아래 0 은 '멈춤'이 아니라 '눈멂'이다 — 대조군을 지우지 마라.
    ///
    /// ⚠️ 이 테스트가 **못 재는 것**: 장식 애니메이션. SwiftUI 애니메이션(`repeatForever`)은 TimelineView 가 아니라
    /// 프레임 프로브의 시야 밖이고, 그래서 v0.2.48 초안은 이 테스트가 초록인 채로 코어의 3~4% 를 계속 태웠다
    /// (2026-09-10). 그쪽 가드는 소스 계약(`flappySourceKeepsTheLeafViewContract` 의 repeatForever 0회 단언)에 있다.
    @Test
    func readyStateDoesNotAdvanceAnyFrame() throws {
        // (1) 대조군 — 진행 중인 판. 캐릭터를 높이 두고 기둥을 화면 밖에 둬 스핀 동안 판이 끝나지 않게 한다.
        let live = running(bird: .init(x: birdX, y: 60, vy: 0), pipes: [pipe(x: 420)], score: 1)
        let liveFrames = hostedFrameCount(live, stopWhen: { $0 >= 3 })
        #expect(liveFrames >= 3, "running 대조군이 프레임을 \(liveFrames)번밖에 못 셌다 — 이 자로는 0 을 믿을 수 없다")
        // (2) ready — paused 라 0.
        let readyFrames = hostedFrameCount(FlappyGame(seed: 1), spins: 25)
        #expect(readyFrames == 0, "ready 에서 프레임 루프가 \(readyFrames)번 돌았다 — 유휴 0% 가 깨졌다")
        // (3) 허브 일시정지 — 진행 중인 판이어도 0(정지 중 시간이 흐르면 안 보는 사이 판이 끝난다).
        let pausedFrames = hostedFrameCount(live, isPaused: true, spins: 25)
        #expect(pausedFrames == 0, "허브 일시정지 중에 프레임 루프가 \(pausedFrames)번 돌았다")
    }

    @Test
    func smallerCanvasKeepsTheAspectAndStillDrawsEverything() throws {
        // 캔버스가 절반이어도(배율 ≈ 0.589) 규칙 좌표 그대로, 여전히 천장·바닥에 붙는다.
        let game = running(bird: .init(x: birdX, y: 151, vy: 0),
                           pipes: [pipe(x: 160, centerY: 151, gap: 132), pipe(x: 310), pipe(x: 460)], score: 3)
        let half = CGSize(width: CW / 2, height: CH / 2)
        let bitmap = try renderBitmap(view(game), width: half.width, height: half.height)
        let ht = MiniGameCanvas.transform(in: half, logicalSize: FlappyGame.logicalSize)
        #expect(abs(ht.scale - t.scale / 2) < 1e-9)
        let px0 = ht.origin.x + 160 * ht.scale + 1, px1 = ht.origin.x + (160 + FlappyGame.pipeWidth) * ht.scale - 1
        #expect(count(bitmap, x: px0...px1, y: 0...2, where: pipePixel(.dawn)) > 10)
        let box = game.hitbox
        let bx = ht.origin.x + box.minX * ht.scale, by = ht.origin.y + box.minY * ht.scale
        let noBird = FlappyGame(seed: 1, bird: .init(x: birdX, y: -400, vy: 0),
                                pipes: game.pipes, score: 3, phase: .running)
        let without = try renderBitmap(view(noBird), width: half.width, height: half.height)
        #expect(differing(bitmap, without, x: bx...(bx + box.width * ht.scale),
                          y: by...(by + box.height * ht.scale)) > 100, "작은 캔버스에서 스프라이트가 안 보인다")
    }

    // MARK: 무대별 스냅샷 — 이 작업의 진짜 검증(디자인은 "초록"이 아무것도 증명하지 않는다)

    /// 다섯 무대를 같은 자세로 한 장씩. 눈으로 보는 항목: 하늘·능선·별이 실제로 그려지는가 ·
    /// 기둥이 천장·바닥에 붙는가 · 캐릭터가 묻히지 않는가 · 숫자 대비 · 무대마다 달라 보이는가.
    @Test
    func everyStageDrawsItsOwnSkyAndPipes() throws {
        let cases: [(score: Int, file: String, stage: MiniGameStage)] = [
            (3, "flappy-stage0.png", .dawn), (8, "flappy-stage1.png", .day), (16, "flappy-stage2.png", .dusk),
            (26, "flappy-stage3.png", .night), (40, "flappy-stage4.png", .aurora)
        ]
        for entry in cases {
            let gap = FlappyGame.gap(forScore: entry.score)
            let spacing = FlappyGame.spacing(forScore: entry.score)
            let game = FlappyGame(seed: 9, bird: .init(x: birdX, y: 138, vy: -140),
                                  pipes: [pipe(x: 104, centerY: 140, gap: gap),
                                          pipe(x: 104 + spacing, centerY: 200, gap: gap),
                                          pipe(x: 104 + spacing * 2, centerY: 104, gap: gap)],
                                  score: entry.score, phase: .running, elapsed: 6, scrolled: 620,
                                  lastFlapAt: 5.94, flapCount: 12,
                                  lastScoreAt: 5.80, lastScorePipeCenter: 150)
            #expect(game.stage == entry.stage, "\(entry.score)점의 무대가 \(game.stage.name)")
            let bitmap = try renderBitmap(view(game, best: 30))
            savePNG(bitmap, entry.file)
            // 기둥이 그 무대의 색으로 천장에 붙어 있다.
            let px0 = t.origin.x + 104 * t.scale + 3, px1 = t.origin.x + (104 + FlappyGame.pipeWidth) * t.scale - 3
            #expect(count(bitmap, x: px0...px1, y: 0...2, where: pipePixel(entry.stage)) > 40,
                    "\(entry.stage.name): 기둥이 천장에 없다")
            // 하늘이 한 색이 아니다 — 배경(그라디언트·광원)이 실제로 그려졌다. 예전엔 fieldFill 단색이었다.
            let high = try #require(pixel(bitmap, x: 8, y: 12))
            let low = try #require(pixel(bitmap, x: 8, y: 150))
            #expect(zip(high, low).contains { abs($0.0 - $0.1) > 10 },
                    "\(entry.stage.name): 하늘이 단색이다 \(high) → \(low)")
        }
    }

    /// 별이 많은 무대(밤·오로라)는 실제로 별이 찍힌다. 왼쪽 위 띠에는 HUD·기둥·캐릭터가 없다.
    @Test
    func starryStagesActuallyDrawStars() throws {
        for stage in [MiniGameStage.night, .aurora] {
            let score = stage.id == 3 ? 26 : 40
            let game = FlappyGame(seed: 9, bird: .init(x: birdX, y: 138, vy: -140),
                                  pipes: [pipe(x: 150, centerY: 140, gap: FlappyGame.gap(forScore: score))],
                                  score: score, phase: .running, elapsed: 6, scrolled: 620)
            let bitmap = try renderBitmap(view(game))
            let stars = count(bitmap, x: 0...140, y: 50...110) { r, g, b, a in
                a >= 250 && min(r, min(g, b)) >= 150
            }
            #expect(stars > 10, "\(stage.name) 하늘에 별이 \(stars)픽셀뿐이다")
        }
    }

    /// 점프 직후 한 장 — v0.2.51 부터 점프의 증거는 **발밑 흰 파편 하나뿐**이다
    /// (스쿼시&스트레치·몸 아래쪽 흰 플래시는 "맨처음 기준" 지시로 함께 빠졌다 — 2026-09-11).
    @Test
    func flapFrameShowsTheJumpImpact() throws {
        func frame(flappedAt: TimeInterval?, reduceMotion: Bool = false) throws -> NSBitmapImageRep {
            let game = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: -280),
                                  pipes: [pipe(x: 205, centerY: 118, gap: 108), pipe(x: 335, centerY: 196, gap: 108)],
                                  score: 8, phase: .running, elapsed: 4.0, scrolled: 470,
                                  lastFlapAt: flappedAt, flapCount: 7)
            return try renderBitmap(view(game, best: 12, reduceMotion: reduceMotion))
        }
        let flapped = try frame(flappedAt: 3.95)
        savePNG(flapped, "flappy-flap.png")
        let calm = try frame(flappedAt: nil)
        // 캐릭터 발밑(파편)이 눈에 띄게 달라진다 — 사용자가 남기라고 한 "밑에 거품같은거"(2026-09-11).
        let cx = t.origin.x + birdX * t.scale, cy = t.origin.y + 150 * t.scale
        let reach = 40 * t.scale
        #expect(differing(flapped, calm, x: (cx - reach)...(cx + reach), y: (cy - reach)...(cy + reach)) > 200,
                "점프해도 화면이 그대로다")
        // 동작 줄이기에서는 그 장식이 통째로 빠진다(규칙·속도는 그대로).
        let calmRM = try frame(flappedAt: nil, reduceMotion: true)
        let flappedRM = try frame(flappedAt: 3.95, reduceMotion: true)
        #expect(firstPixelDifference(flappedRM, calmRM) == nil, "동작 줄이기인데 점프 장식이 남았다")
    }
}

// MARK: - (7b) v0.2.51 남긴 넷 · 점프 파편 · 캐릭터 대비 — 눈으로 판정하는 증거
//
// 사용자 지시 2026-09-11: "잔상 없애줘 … 캐릭터 옆으로 돌린거랑 점프할때 밑에 거품같은거 … 각 기둥 지나갈때
// +1 되는거 … 뒤 배경. 이거 4개만 유지하고 나머지 다 초기로."
// 여기 있던 잔상 검사(궤적이 캐릭터에 달라붙지 않는가 · 잔상이 단색 실루엣인가)는 지운 기능의 것이라
// 함께 지웠다. 대신 ① 남긴 넷이 **실제로 그려지는가** ② 지운 장식이 **한 픽셀도 안 남았는가**
// ③ 얹는 장치(림·명암)를 뺀 뒤에도 캐릭터가 하늘·기둥에서 떨어지는가 — 셋을 픽셀로 못 박는다.

/// 같은 프레임에서 **점프 장식만** 뺀 판(배경·기둥·캐릭터는 그대로). 점프의 잉크만 남기려면
/// 나머지가 한 픽셀도 다르지 않아야 한다.
private func withoutFlapImpact(_ game: FlappyGame) -> FlappyGame {
    FlappyGame(seed: 5, bird: game.bird, pipes: game.pipes, score: game.score, phase: game.phase,
               elapsed: game.elapsed, scrolled: game.scrolled,
               lastFlapAt: nil, flapCount: game.flapCount,
               lastScoreAt: game.lastScoreAt, lastScorePipeCenter: game.lastScorePipeCenter)
}

/// 같은 프레임에서 **캐릭터만** 판 밖으로 뺀 판. "이 자리에 캐릭터가 그려졌다"와 "그 뒤에 무엇이 있었나"를
/// 색 서명 없이 재는 기준선이다 — 배경이 무대마다 바뀌므로 "바닥색과 다르다"로는 아무것도 증명되지 않는다.
private func withoutCharacter(_ game: FlappyGame) -> FlappyGame {
    FlappyGame(seed: 5, bird: .init(x: game.bird.x, y: -600, vy: game.bird.vy),
               pipes: game.pipes, score: game.score, phase: game.phase,
               elapsed: game.elapsed, scrolled: game.scrolled,
               lastFlapAt: nil, flapCount: game.flapCount,
               lastScoreAt: game.lastScoreAt, lastScorePipeCenter: game.lastScorePipeCenter)
}

/// 그 영역에서 **따뜻한 무대 강조색**(새벽 주황 · 한낮 크림 · 노을 금색)인 픽셀의 개수와 무게중심 y(pt).
///
/// v0.2.49 에는 이것으로 "호가 머리 위 어디까지 올라갔나"를 쟀다. 호를 걷어낸 뒤로는 반대로 쓴다 —
/// **여기 잉크가 0 이어야 한다**: 머리 위에서는 호가 되살아나지 않았다는 뜻이고, 발밑에서는 파편이
/// `stage.glow`(사용자가 "갈색"이라 부른 그 색)로 되돌아가지 않았다는 뜻이다.
/// 문턱은 그 색이 0.6 까지 옅어져도 잡히게 잡았다(그 아래는 눈으로도 거의 안 보인다).
private func glowInk(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>)
    -> (count: Int, centroidY: CGFloat) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return (0, 0) }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(bitmap.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(y.upperBound * 2))
    guard x0 <= x1, y0 <= y1 else { return (0, 0) }
    var count = 0, sum = 0.0
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            // 따뜻한 강조색은 r−b 가 크게 양수이고, 몸통은 연보라(b 가 가장 크다) · 하늘·능선은 파랑 ·
            // 별·HUD 숫자·**흰 파편**은 무채색(b 도 높다)이라 전부 빠진다.
            guard r >= 150, g >= 140, b <= 205, r - b >= 20 else { continue }
            count += 1
            sum += Double(py)
        }
    }
    return (count, count == 0 ? 0 : CGFloat(sum / Double(count) / 2))
}

/// 그 영역의 **흰 파편**을 잰다. 파편만 남기는 방법은 하나뿐이다: "점프 장식만 뺀 같은 프레임과 다른 픽셀"
/// ∩ "그 자리가 더 밝아진 픽셀". 색 서명으로는 안 된다 — 반투명 흰색을 무대마다 다른 배경 위에 얹으면
/// 결과 색이 배경을 따라가고(노을 하늘 위 = 살구빛), 밤·오로라의 **별** 수십 개가 그대로 딸려 들어온다.
///
/// - count: 파편 픽셀 수.
/// - ink / behind: 그 픽셀들의 평균 휘도(파편 프레임 / 같은 자리의 배경). 둘의 비가 ratio 다.
/// - neutralBright: 그중 **무채색이면서 밝은** 픽셀 수 —
///   (최소 채널 ≥ 185 · 채널 폭 ≤ 40) 점 한가운데의 색이다. 무대 강조색 다섯(주황 255,196,138 ·
///   크림 255,232,168 · 금색 255,209,122 · 하늘색 140,227,255 · 민트 125,255,212)은 채널 폭이
///   85~130 이라 이 자를 통과할 수 없다.
///   **이 한 줄이 "파편은 흰색"이라는 사용자 지시를 회귀에서 지킨다.**
/// - peak: 파편 픽셀 중 가장 밝은 휘도(점 한가운데). 몸통(연보라 — v0.2.51 실측 169/255)보다 위여야 겹쳐도 갈린다.
/// - maxY: 가장 아래 파편의 y(pt). 프레임이 갈수록 내려가는지로 '퍼진다'를 잰다.
private func sparkInk(_ jump: NSBitmapImageRep, _ calm: NSBitmapImageRep,
                      x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>, tolerance: Int = 2)
    -> (count: Int, ink: Double, behind: Double, ratio: Double, neutralBright: Int, peak: Double, maxY: CGFloat) {
    guard let a = jump.bitmapData, let b = calm.bitmapData,
          jump.bytesPerRow == calm.bytesPerRow, jump.samplesPerPixel == calm.samplesPerPixel,
          jump.samplesPerPixel >= 4 else { return (0, 0, 0, 0, 0, 0, 0) }
    let spp = jump.samplesPerPixel, bpr = jump.bytesPerRow
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(jump.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(jump.pixelsHigh - 1, Int(y.upperBound * 2))
    guard x0 <= x1, y0 <= y1 else { return (0, 0, 0, 0, 0, 0, 0) }
    func luma(_ p: UnsafePointer<UInt8>, _ o: Int) -> Double {
        0.2126 * Double(p[o]) + 0.7152 * Double(p[o + 1]) + 0.0722 * Double(p[o + 2])
    }
    var count = 0, neutral = 0, inkSum = 0.0, bgSum = 0.0, peak = 0.0
    var maxY = CGFloat(0)
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            guard (0..<spp).contains(where: { abs(Int(a[o + $0]) - Int(b[o + $0])) > tolerance }) else { continue }
            let here = luma(a, o), there = luma(b, o)
            guard here > there else { continue }   // 흰 파편은 **밝히기만** 한다.
            count += 1
            inkSum += here
            peak = max(peak, here)
            bgSum += there
            maxY = max(maxY, CGFloat(py) / 2)
            let r = Int(a[o]), g = Int(a[o + 1]), bl = Int(a[o + 2])
            if min(r, min(g, bl)) >= 185, max(r, max(g, bl)) - min(r, min(g, bl)) <= 40 { neutral += 1 }
        }
    }
    guard count > 0 else { return (0, 0, 0, 0, 0, 0, 0) }
    let ink = inkSum / Double(count), behind = bgSum / Double(count)
    return (count, ink, behind, (ink + 5) / (behind + 5), neutral, peak, maxY)
}

/// 논리 좌표 한 자리를 중심으로 한 정사각(±half pt) 안의 휘도 최소·최대·평균과 백분위 폭(P90−P10).
@MainActor
private func luminance(_ bitmap: NSBitmapImageRep, atLogical point: CGPoint, half: CGFloat)
    -> (min: Double, max: Double, mean: Double, spread: Double) {
    let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)
    let cx = (t.origin.x + point.x * t.scale) * 2, cy = (t.origin.y + point.y * t.scale) * 2
    let r = half * t.scale * 2
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return (0, 0, 0, 0) }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(cx - r)), x1 = min(bitmap.pixelsWide - 1, Int(cx + r))
    let y0 = max(0, Int(cy - r)), y1 = min(bitmap.pixelsHigh - 1, Int(cy + r))
    guard x0 <= x1, y0 <= y1 else { return (0, 0, 0, 0) }
    var values: [Double] = []
    values.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            values.append(0.2126 * Double(data[o]) + 0.7152 * Double(data[o + 1]) + 0.0722 * Double(data[o + 2]))
        }
    }
    guard !values.isEmpty else { return (0, 0, 0, 0) }
    let sorted = values.sorted()
    let p10 = sorted[Int(Double(sorted.count - 1) * 0.10)]
    let p90 = sorted[Int(Double(sorted.count - 1) * 0.90)]
    return (sorted[0], sorted[sorted.count - 1], values.reduce(0, +) / Double(values.count), p90 - p10)
}

/// sRGB 8비트 한 픽셀의 **상대 휘도**(WCAG 2.x, 0…1). 감마를 풀고 재야 "1.01:1 이라 겹치면 사라진다"가
/// 눈에 보이는 것과 맞는다 — 8비트 값 평균으로 재면 어두운 쪽 차이가 실제보다 크게 나온다.
private func relativeLuminance(_ r: Int, _ g: Int, _ b: Int) -> Double {
    func lin(_ v: Int) -> Double {
        let c = Double(v) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

/// **캐릭터와 그 뒤 배경의 휘도비**(WCAG 대비, (밝은+0.05)/(어두운+0.05)).
///
/// 재는 법: 같은 프레임을 두 장 그린다 — 캐릭터가 있는 판과 `withoutCharacter` 로 캐릭터만 판 밖으로 뺀 판.
/// 두 장이 **크게 다른 픽셀**(어느 채널이든 24 초과)이 곧 캐릭터의 몸이다(가장자리 안티앨리어싱은 문턱에서
/// 빠진다 — 그 픽셀은 몸도 배경도 아닌 섞인 색이라 대비를 낙관적으로 만든다).
/// 그 픽셀 집합에서 캐릭터 쪽 평균 휘도와 **같은 자리의** 배경 평균 휘도를 각각 구해 비를 낸다.
///
/// 왜 이 자가 필요한가: v0.2.51 에서 캐릭터에 얹던 어두운 림·뒤통수 그늘·앞쪽 반사광을 뺐다(장식이므로).
/// 뺀 뒤 실루엣이 하늘이나 기둥에 묻히면 그건 장식이 아니라 **가독성 장치를 뺀 것**이 된다 —
/// 눈대중으로 정하지 않으려고 자를 만들었다.
@MainActor
private func characterContrast(_ drawn: NSBitmapImageRep, _ empty: NSBitmapImageRep,
                               around logicalCenter: CGPoint, half: CGFloat)
    -> (ratio: Double, character: Double, background: Double, pixels: Int) {
    let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)
    let cx = (t.origin.x + logicalCenter.x * t.scale) * 2, cy = (t.origin.y + logicalCenter.y * t.scale) * 2
    let r = half * t.scale * 2
    guard let a = drawn.bitmapData, let b = empty.bitmapData,
          drawn.bytesPerRow == empty.bytesPerRow, drawn.samplesPerPixel >= 4 else { return (0, 0, 0, 0) }
    let spp = drawn.samplesPerPixel, bpr = drawn.bytesPerRow
    let x0 = max(0, Int(cx - r)), x1 = min(drawn.pixelsWide - 1, Int(cx + r))
    let y0 = max(0, Int(cy - r)), y1 = min(drawn.pixelsHigh - 1, Int(cy + r))
    guard x0 <= x1, y0 <= y1 else { return (0, 0, 0, 0) }
    var charSum = 0.0, bgSum = 0.0, n = 0
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            let solid = (0..<3).contains { abs(Int(a[o + $0]) - Int(b[o + $0])) > 24 }
            guard solid else { continue }
            charSum += relativeLuminance(Int(a[o]), Int(a[o + 1]), Int(a[o + 2]))
            bgSum += relativeLuminance(Int(b[o]), Int(b[o + 1]), Int(b[o + 2]))
            n += 1
        }
    }
    guard n > 0 else { return (0, 0, 0, 0) }
    let character = charSum / Double(n), background = bgSum / Double(n)
    let hi = max(character, background), lo = min(character, background)
    return ((hi + 0.05) / (lo + 0.05), character, background, n)
}

/// 실제로 몇 프레임을 굴려 만든 판. **손으로 찍은 상태는 규칙이 정말 그렇게 흐르는지를 증명하지 못한다.**
private func flown(y: CGFloat, vy: CGFloat, frames: Int, flapAfter: Int? = nil,
                   score: Int = 8) -> FlappyGame {
    var game = FlappyGame(seed: 5, bird: .init(x: birdX, y: y, vy: vy),
                          pipes: [pipe(x: 205, centerY: 118, gap: 108), pipe(x: 335, centerY: 216, gap: 108)],
                          score: score, phase: .running)
    for frame in 0..<frames {
        if frame == flapAfter { game.flap() }
        game.step(dt: 1.0 / 60.0)
    }
    return game
}

@MainActor
@Suite(.serialized)
struct V0251FlappyKeptFourTests {
    private let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)

    /// 논리 사각형(캐릭터 기준 상대 좌표)을 화면 pt 범위로.
    private func band(_ x: ClosedRange<CGFloat>, _ y: ClosedRange<CGFloat>, around cy: CGFloat)
        -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        ((t.origin.x + (birdX + x.lowerBound) * t.scale)...(t.origin.x + (birdX + x.upperBound) * t.scale),
         (t.origin.y + (cy + y.lowerBound) * t.scale)...(t.origin.y + (cy + y.upperBound) * t.scale))
    }

    /// **이 작업의 못.** 사용자가 남기라고 한 넷이 전부 실제로 **그려지는지**를 한 자리에서 픽셀로 잰다
    /// (2026-09-11: "캐릭터 옆으로 돌린거 · 점프할때 밑에 거품같은거 · 각 기둥 지나갈때 +1 · 뒤 배경").
    /// 넷 중 하나라도 조용히 빠지면 여기가 빨개진다.
    @Test
    func theFourKeptThingsAreActuallyDrawn() throws {
        MiniGameMascot.resetCacheForTesting()
        _ = MiniGameMascot.sideProfile()

        // ① **오른쪽을 보는 옆모습.** 눈·입(어두운 잉크)의 가로 무게중심을 캐릭터 중심에서 잰다(vy = 0 → 기울기 0).
        //    정면 PNG 는 눈·입이 몸통 중심에 대칭이라 0 근처이고, 돌아선 옆모습은 오른쪽(+)으로 쏠린다.
        //    ⚠️ 처음엔 "스프라이트를 좌우로 접었을 때 다른 픽셀 수"로 쟀는데 옆모습 861 · 정면 PNG 847 로
        //    **갈리지 않았다**(2026-09-11, 대조군을 붙이자마자 드러났다 — 몸통 음영·안티앨리어싱이 대칭을 깬다).
        //    대조군 없이 "> 200" 만 두었다면 정면으로 내려가도 초록이었다. 그래서 얼굴 잉크만 본다.
        //    배경(한낮 하늘은 채널 최대 79)도 어두우므로 "캐릭터를 뺀 같은 프레임과 24 넘게 다른" 픽셀로 제한한다.
        //    (구운 그림 자체의 잉크 무게중심은 (9) 가 따로 못 박는다 — 여기는 **실제 게임 화면**에서의 확인이다.)
        let still = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: 0),
                               pipes: [pipe(x: 250, centerY: 150, gap: 120)],
                               score: 8, phase: .running, elapsed: 1.0)
        let sideInk = faceInkOffset(try renderBitmap(view(still, best: 12)),
                                    try renderBitmap(view(withoutCharacter(still), best: 12)),
                                    aroundLogicalX: birdX, y: 150, half: 17)
        // 대조군: 같은 자리·같은 자세의 **정면 PNG**(게임오버 표정은 3D 에 없어 언제나 정면으로 내려간다).
        let frontal = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: 0),
                                 pipes: [pipe(x: 250, centerY: 150, gap: 120)],
                                 score: 8, phase: .over(hold: 0.3), elapsed: 1.0)
        let frontInk = faceInkOffset(try renderBitmap(view(frontal, best: 12)),
                                     try renderBitmap(view(withoutCharacter(frontal), best: 12)),
                                     aroundLogicalX: birdX, y: 150, half: 17)
        print("[kept] ① 얼굴 잉크 가로 무게중심(pt, +오른쪽): 옆모습 \(String(format: "%.2f", sideInk.offset)) " +
              "(\(sideInk.samples)px) · 정면 PNG \(String(format: "%.2f", frontInk.offset)) (\(frontInk.samples)px)")
        #expect(sideInk.samples > 20 && frontInk.samples > 20, "얼굴 잉크를 못 찾는다 — 자가 고장 났다")
        #expect(sideInk.offset > frontInk.offset + 2,
                "게임 화면의 얼굴이 오른쪽으로 안 쏠렸다(옆 \(sideInk.offset) · 정면 \(frontInk.offset)) — 정면으로 내려갔다")

        // ② **점프할 때 발밑 흰 파편.** 점프 장식만 뺀 같은 프레임과 비교한다.
        let flap = flown(y: 190, vy: -60, frames: 10, flapAfter: 7)
        let flapShot = try renderBitmap(view(flap, best: 12))
        let flapCalm = try renderBitmap(view(withoutFlapImpact(flap), best: 12))
        let foot = band((-34)...22, 24...52, around: flap.bird.y)
        let sparks = sparkInk(flapShot, flapCalm, x: foot.x, y: foot.y)
        print("[kept] ② 파편 count=\(sparks.count) neutralBright=\(sparks.neutralBright)")
        #expect(sparks.count > sparkInkMin, "발밑에 파편이 \(sparks.count)픽셀뿐이다")

        // ③ **기둥을 지날 때 뜨는 "+1".** 방금 득점한 프레임과 득점 기록이 없는 프레임을 비교한다.
        //    자리는 캐릭터 뒤 33pt(= 기둥 폭 × 0.75), 높이는 지나온 기둥의 틈 중심이다.
        let scoredAt: TimeInterval = 4.0
        func scoreFrame(popped: Bool) -> FlappyGame {
            FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: -60),
                       pipes: [pipe(x: 205, centerY: 118, gap: 108)],
                       score: 8, phase: .running, elapsed: scoredAt,
                       lastScoreAt: popped ? scoredAt - 0.10 : nil,
                       lastScorePipeCenter: popped ? 150 : nil)
        }
        let popped = try renderBitmap(view(scoreFrame(popped: true), best: 12))
        let unpopped = try renderBitmap(view(scoreFrame(popped: false), best: 12))
        let popBand = band((-64)...(-10), (-34)...16, around: 150)
        let popInk = differing(popped, unpopped, x: popBand.x, y: popBand.y)
        print("[kept] ③ +1 잉크 = \(popInk)")
        #expect(popInk > 150, "기둥을 지나도 \"+1\" 이 안 뜬다(\(popInk)픽셀)")
        // 그리고 0.6초가 지나면 사라진다(상시 글씨는 판을 가린다).
        let expired = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: -60),
                                 pipes: [pipe(x: 205, centerY: 118, gap: 108)],
                                 score: 8, phase: .running, elapsed: scoredAt,
                                 lastScoreAt: scoredAt - 0.70, lastScorePipeCenter: 150)
        #expect(firstPixelDifference(try renderBitmap(view(expired, best: 12)), unpopped) == nil,
                "\"+1\" 이 0.6초 뒤에도 남아 있다")

        // ④ **뒤 배경.** 하늘이 단색이 아니고(그라디언트·능선·별), 무대가 다르면 그림도 다르다.
        //    (무대 5종 각각의 스냅샷·별 검사는 렌더 스위트에 있다.)
        let dawn = try renderBitmap(view(FlappyGame(seed: 9, bird: .init(x: birdX, y: -600, vy: 0),
                                                    pipes: [], score: 3, phase: .running,
                                                    elapsed: 6, scrolled: 620), best: 30))
        let night = try renderBitmap(view(FlappyGame(seed: 9, bird: .init(x: birdX, y: -600, vy: 0),
                                                     pipes: [], score: 26, phase: .running,
                                                     elapsed: 6, scrolled: 620), best: 30))
        let high = try #require(pixel(dawn, x: 8, y: 12)), low = try #require(pixel(dawn, x: 8, y: 150))
        #expect(zip(high, low).contains { abs($0.0 - $0.1) > 10 }, "하늘이 단색이다 \(high) → \(low)")
        #expect(firstPixelDifference(dawn, night) != nil, "무대가 달라도 배경이 같다")
    }

    /// **지운 장식이 한 픽셀도 안 남았다.** 사용자가 물린 것들이라 "거의 없다"로는 부족하다.
    /// 각 장식이 살아 있던 자리에 그 장식만이 만들 수 있는 차이를 대고 0 을 요구한다.
    @Test
    func theRemovedDecorationsLeaveNoInk() throws {
        MiniGameMascot.resetCacheForTesting()
        _ = MiniGameMascot.sideProfile()

        // ⓐ 잔상 — 10프레임을 실제로 날았다. 예전에는 이 프레임의 캐릭터 **뒤쪽**에 꼬리(최대 8겹)가 있었다.
        //    캐릭터만 뺀 같은 프레임과 비교해 캐릭터 상자 밖(뒤 34…8pt)에 잉크가 0 이어야 한다.
        let climb = flown(y: 230, vy: FlappyGame.flapVelocity, frames: 10)
        let climbShot = try renderBitmap(view(climb, best: 12))
        let noChar = try renderBitmap(view(withoutCharacter(climb), best: 12))
        for (name, rect) in [("뒤·아래", band((-34)...(-20), 16...46, around: climb.bird.y)),
                             ("뒤·위", band((-34)...(-20), (-46)...(-16), around: climb.bird.y)),
                             ("뒤·수평", band((-34)...(-20), (-9)...9, around: climb.bird.y))] {
            let ink = differing(climbShot, noChar, x: rect.x, y: rect.y)
            #expect(ink == 0, "\(name)에 잔상이 \(ink)픽셀 남았다 — 꼬리가 되살아났다")
        }

        // ⓑ 바닥 그림자 타원 — 캐릭터 바로 아래 **바닥 줄**에 있었다. 캐릭터를 빼도 그 자리가 같아야 한다
        //    (그림자는 캐릭터 위치를 따라 그려지던 것이라 캐릭터를 빼면 사라진다 = 차이로 잡힌다).
        let floorBand = ((t.origin.x + (birdX - 20) * t.scale)...(t.origin.x + (birdX + 20) * t.scale),
                         (t.origin.y + (FlappyGame.height - 12) * t.scale)...(t.origin.y + FlappyGame.height * t.scale))
        let shadowInk = differing(climbShot, noChar, x: floorBand.0, y: floorBand.1)
        #expect(shadowInk == 0, "바닥에 그림자 타원이 \(shadowInk)픽셀 남았다")

        // ⓒ 무대 전환 플레어·이름 배너 — 규칙에서 `stageChangedAt` 자체를 지웠으므로 **그릴 근거가 없다**.
        //    남은 확인은 HUD 왼쪽 위(무대 점 5개·이름 칩 자리)가 비어 있다는 것이다.
        let hud = try renderBitmap(view(flown(y: 150, vy: -60, frames: 6, score: 13), best: 30))
        #expect(count(hud, x: 14...110, y: 12...50, where: isInkPixel) == 0, "왼쪽 위에 무대 점·이름 칩이 있다")

        // ⓓ 죽은 뒤 회전·낙하·붉은 파편 — 규칙이 말하는 **그 자리 그대로** 그려져야 한다(뷰에서 떨어뜨리던
        //    연출을 지웠다). 유예가 **거의 끝난** 프레임을 쓰는 이유: 예전 낙하는 46 × 진행도² 라 유예 절반
        //    (hold 0.18)에서는 14pt 밖에 안 내려가 아래 두 대역 어느 쪽으로도 갈리지 않는다 — 그 픽스처로는
        //    연출이 되살아나도 초록이었다(2026-09-11 검토). hold 0.001 이면 예전 연출은 +45.8pt 아래에 있다.
        let over = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: 300),
                              pipes: [pipe(x: 250, centerY: 150, gap: 120)],
                              score: 8, phase: .over(hold: 0.001), elapsed: 4.0, scrolled: 470)
        let overShot = try renderBitmap(view(over, best: 12))
        let overNoChar = try renderBitmap(view(withoutCharacter(over), best: 12))
        // 규칙의 자리(150)에 캐릭터가 있다.
        let atRule = band((-18)...18, (-18)...18, around: 150)
        #expect(differing(overShot, overNoChar, x: atRule.x, y: atRule.y) > 300, "죽은 프레임에 캐릭터가 없다")
        // 그리고 예전에 떨어뜨리던 자리(+46 아래)에는 아무것도 없다.
        let dropped = band((-18)...18, (46 - 14)...(46 + 18), around: 150)
        let dropInk = differing(overShot, overNoChar, x: dropped.x, y: dropped.y)
        #expect(dropInk == 0, "죽은 뒤 낙하 연출이 \(dropInk)픽셀 남았다")
        savePNG(overShot, "flappy-over.png")
    }

    /// **점프에는 파편 하나뿐**이다. 호도, 스쿼시도, 몸에 얹히는 흰 플래시도 없다.
    ///
    /// 왜 이 형태인가: 점프에 붙인 도형은 **세 번 거부됐다**. v0.2.48 넓은 U(`MiniGameEffects.arch`) ·
    /// v0.2.49 ∩ 한 쌍(`wingBeat`) · v0.2.51 에서는 스쿼시&스트레치와 몸 아래쪽 흰 플래시까지
    /// "맨처음 기준"으로 빠졌다(2026-09-11). 그래서 이 검사는 ①(호가 없다) ②(그래도 파편은 있다)
    /// ③(파편이 흰색이다) ④(스쿼시·플래시가 없다) ⑤(판을 가리지 않는다)로 짜여 있다.
    @Test
    func theJumpIsSparksOnlyAndTheSparksAreWhite() throws {
        MiniGameMascot.resetCacheForTesting()
        _ = MiniGameMascot.sideProfile()
        // 10프레임을 날다 3프레임 전에 쳤다 — 점프 장식이 한창인 프레임.
        let flap = flown(y: 190, vy: -60, frames: 10, flapAfter: 7)
        let sinceFlap = try #require(flap.lastFlapAt).distance(to: flap.elapsed)
        #expect(sinceFlap > 0 && sinceFlap < 0.09, "점프 장식이 한창인 프레임이 아니다(\(sinceFlap)초)")
        let bitmap = try renderBitmap(view(flap, best: 12))
        savePNG(bitmap, "flapfx-jump.png")
        // 같은 자리·같은 배경에서 **점프 장식만** 뺀 판. 아래 차분은 전부 이것과의 차분이다.
        let calm = try renderBitmap(view(withoutFlapImpact(flap), best: 12))
        savePNG(calm, "flapfx-level.png")
        let cy = flap.bird.y

        // ① 스프라이트 상자 **위**로는 아무것도 그려지지 않는다(호가 살던 자리다).
        let overhead = band((-40)...40, (-46)...(-20), around: cy)
        let overheadInk = differing(bitmap, calm, x: overhead.x, y: overhead.y)
        #expect(overheadInk == 0, "머리 위에 점프 장식이 \(overheadInk)픽셀 남았다")
        // ①-b **∩ 한 쌍이 실제로 살던 대역**(어깨 밖~머리 옆)에 무대색 잉크가 한 점도 없다.
        //     호는 stage.glow 한 색이고 몸통은 연보라라 **색으로만** 깨끗하게 갈린다.
        let arcBand = band((-40)...40, (-30)...(-10), around: cy)
        let arcInk = glowInk(bitmap, x: arcBand.x, y: arcBand.y)
        print("[flapfx] arc glow=\(arcInk.count) overhead diff=\(overheadInk)")
        #expect(arcInk.count == 0, "어깨~머리 옆에 무대색 호가 \(arcInk.count)px 있다 — ∩ 한 쌍이 되살아났다")
        // ①-c 그 0 이 **진짜 없음**이지 눈먼 자가 아니라는 증거: 똑같은 대역·똑같은 함수로 무대색 글씨
        //     ("+1")가 있는 프레임을 재면 실측 120px 이 잡힌다. 이 줄이 없으면 glowInk 이 고장 나도
        //     ①-b 가 영원히 초록이다. (새벽 glow 는 주황이라 이 자에 걸린다.)
        let popped = try renderBitmap(view(FlappyGame(seed: 5, bird: flap.bird, pipes: flap.pipes,
                                                      score: 3, phase: flap.phase,
                                                      elapsed: flap.elapsed, scrolled: flap.scrolled,
                                                      lastScoreAt: flap.elapsed - 0.05,
                                                      lastScorePipeCenter: cy - 20), best: 12))
        let probe = glowInk(popped, x: arcBand.x, y: arcBand.y).count
        print("[flapfx] glow probe = \(probe)")
        #expect(probe > arcProbeMin, "같은 대역에서 무대색을 못 본다 — ①-b 가 아무것도 안 본다")

        // ② 파편은 스프라이트 상자 **아래**에 있다.
        let footBand = band((-34)...22, 24...52, around: cy)
        let sparks = sparkInk(bitmap, calm, x: footBand.x, y: footBand.y)
        print("[flapfx] spark count=\(sparks.count) ink=\(Int(sparks.ink)) behind=\(Int(sparks.behind)) " +
              "neutralBright=\(sparks.neutralBright)")
        #expect(sparks.count > sparkInkMin, "발밑에 파편이 \(sparks.count)픽셀뿐이다")

        // ③ **파편이 흰색이다** — 2026-09-10: "밑에 거품처럼 뜨는 거 색깔을 흰색으로. 지금 갈색 안 어울려".
        #expect(sparks.neutralBright > neutralSparkMin,
                "파편에 흰 점(무채색·밝음)이 \(sparks.neutralBright)px 뿐이다 — 무대색으로 되돌아갔다")
        let warm = glowInk(bitmap, x: footBand.x, y: footBand.y)
        #expect(warm.count == 0, "발밑 파편이 따뜻한 색(\(warm.count)px)이다 — 갈색으로 읽힌다")

        // ④ **몸은 그대로다** — 스쿼시&스트레치도 몸 아래쪽 흰 플래시도 없다(2026-09-11 "나머지 다 초기로").
        //
        //    ⚠️ 몸 상자 **전체** 차분으로는 못 잰다 — 첫 판이 실제로 빨개졌다(2026-09-11): 스쿼시·플래시를 다
        //    지운 소스에서도 96px 이 달랐고, flapfx-jump-zoom.png 를 열어 보니 **파편 점 하나가 팔과 몸통 사이의
        //    투명한 틈으로 비쳐** 있었다. 파편은 스프라이트 아래 캔버스에 있으니 알파가 0 인 자리로는 보인다.
        //    그래서 스프라이트가 **불투명한** 픽셀만 골라 잰다 — 파편은 거기를 절대 못 바꾸고, 스쿼시(모양)와
        //    플래시(몸 위에 얹는 흰빛)는 바로 거기를 바꾼다.
        //    불투명 마스크는 **배경만 바꿔 한 번 더 그려서** 만든다: 같은 자세의 캐릭터를 한낮·밤 무대에 그리면
        //    불투명 픽셀은 한 바이트도 안 변하고, 반투명·투명 픽셀은 뒤 하늘을 따라 변한다.
        let nightCalm = try renderBitmap(view(FlappyGame(seed: 5, bird: flap.bird, pipes: flap.pipes,
                                                         score: 26, phase: flap.phase,
                                                         elapsed: flap.elapsed, scrolled: flap.scrolled,
                                                         flapCount: flap.flapCount), best: 12))
        let noChar = try renderBitmap(view(withoutCharacter(flap), best: 12))
        let bodyBox = band((-20)...20, (-20)...20, around: cy)
        let body = opaqueBodyDifference(bitmap, calm, nightCalm: nightCalm, noCharacter: noChar,
                                        x: bodyBox.x, y: bodyBox.y)
        // 이 자가 눈이 멀지 않았다는 증거: 같은 마스크로 **자세만 다른** 프레임(낙하 속도 +200 → 기울기가 바뀐다)을
        // 재면 불투명 픽셀이 대거 바뀐다. 모양이 바뀌는 스쿼시가 되살아나면 이 숫자처럼 잡힌다.
        let tilted = try renderBitmap(view(FlappyGame(seed: 5, bird: .init(x: flap.bird.x, y: flap.bird.y,
                                                                          vy: flap.bird.vy + 200),
                                                      pipes: flap.pipes, score: flap.score, phase: flap.phase,
                                                      elapsed: flap.elapsed, scrolled: flap.scrolled,
                                                      flapCount: flap.flapCount), best: 12))
        let tiltProbe = opaqueBodyDifference(tilted, calm, nightCalm: nightCalm, noCharacter: noChar,
                                             x: bodyBox.x, y: bodyBox.y)
        print("[flapfx] 몸 상자 전체 차분=\(differing(bitmap, calm, x: bodyBox.x, y: bodyBox.y)) · " +
              "불투명 \(body.opaque)px 중 점프로 바뀐 것=\(body.changed) · 자세 바꾼 대조군=\(tiltProbe.changed)")
        #expect(body.opaque > 1500, "불투명 마스크가 \(body.opaque)px 뿐이다 — 자가 고장 났다")
        #expect(tiltProbe.changed > 300, "자세가 바뀌어도 마스크가 못 본다(\(tiltProbe.changed)) — ④ 가 아무것도 안 본다")
        #expect(body.changed == 0,
                "점프가 몸의 불투명 픽셀 \(body.changed)개를 바꾼다 — 스쿼시나 흰 플래시가 되살아났다")

        // ⑤ 그리고 **판을 가리지 않는다**: 파편의 발자국이 캐릭터 주위를 벗어나지 않는다.
        let farLeft = band((-140)...(-42), (-60)...60, around: cy)
        let farRight = band(42...140, (-60)...60, around: cy)
        let farUp = band((-40)...40, (-110)...(-45), around: cy)
        #expect(differing(bitmap, calm, x: farLeft.x, y: farLeft.y) == 0, "점프 장식이 왼쪽으로 샌다")
        #expect(differing(bitmap, calm, x: farRight.x, y: farRight.y) == 0, "점프 장식이 오른쪽으로 샌다")
        #expect(differing(bitmap, calm, x: farUp.x, y: farUp.y) == 0, "점프 장식이 기둥 틈까지 올라간다")

        // ⑥ 확대(6배) — 사용자가 실제로 보는 픽셀. 호가 없는지·파편이 흰지를 눈으로 판정한다.
        let crop = CGRect(x: t.origin.x + (birdX - 44) * t.scale, y: t.origin.y + (cy - 44) * t.scale,
                          width: 88 * t.scale, height: 88 * t.scale)
        if let zoomed = cropZoom(bitmap, ptRect: crop, zoom: 6) { savePNG(zoomed, "flapfx-jump-zoom.png") }

        // ⑦ 동작 줄이기면 점프 장식이 통째로 빠진다.
        let rm = try renderBitmap(view(flap, best: 12, reduceMotion: true))
        let rmCalm = try renderBitmap(view(withoutFlapImpact(flap), best: 12, reduceMotion: true))
        #expect(firstPixelDifference(rm, rmCalm) == nil, "동작 줄이기인데 점프 장식이 남았다")
        savePNG(rm, "flappy-reduce-motion.png")
    }

    /// 점프 직후 **네 프레임**을 이어 붙인다. 정지 한 장으로는 "발밑에 점이 있다"까지만 말할 수 있고
    /// 임팩트는 움직임에서 나온다 — 파편이 프레임마다 퍼지고 옅어지는 것을 숫자와 그림 둘 다로 남긴다.
    @Test
    func theSparksSpreadFrameByFrameSoTheJumpReadsAsMotion() throws {
        MiniGameMascot.resetCacheForTesting()
        _ = MiniGameMascot.sideProfile()
        var tiles: [NSBitmapImageRep] = []
        var reach: [CGFloat] = [], counts: [Int] = []
        // after 9 → 1프레임 뒤, 6 → 4프레임 뒤. 점프 파편은 0.35초(21프레임)를 산다.
        for after in [9, 8, 7, 6] {
            let frame = flown(y: 190, vy: -60, frames: 10, flapAfter: after)
            let shot = try renderBitmap(view(frame, best: 12))
            let bare = try renderBitmap(view(withoutFlapImpact(frame), best: 12))
            let cy = frame.bird.y
            let foot = band((-40)...26, 22...58, around: cy)
            let ink = sparkInk(shot, bare, x: foot.x, y: foot.y)
            counts.append(ink.count)
            // 캐릭터 기준 상대 깊이(pt) — 프레임마다 캐릭터가 다른 높이에 있으므로 상대로 잰다.
            reach.append(ink.maxY - (t.origin.y + cy * t.scale))
            let crop = CGRect(x: t.origin.x + (birdX - 40) * t.scale, y: t.origin.y + (cy - 34) * t.scale,
                              width: 76 * t.scale, height: 96 * t.scale)
            if let zoomed = cropZoom(shot, ptRect: crop, zoom: 3) { tiles.append(zoomed) }
        }
        print("[flapfx] seq counts=\(counts) reach=\(reach.map { Int($0) })")
        if let strip = stitch(tiles) { savePNG(strip, "flapfx-jump-seq.png") }
        // 첫 프레임(친 지 1/60초)은 열 점이 아직 발밑 한자리에 겹쳐 있어 이 대역 밖이다 — 그래서 문턱이 낮다.
        #expect(counts.allSatisfy { $0 > 15 }, "네 프레임 중 파편이 빈 프레임이 있다 \(counts)")
        // 파편은 **퍼진다** — 가장 아래 점이 프레임마다 더 내려간다(0.5pt 이상씩).
        #expect(zip(reach, reach.dropFirst()).allSatisfy { $0 < $1 - 0.5 },
                "파편이 퍼지지 않는다(움직임이 안 읽힌다) \(reach)")
    }

    /// **흰 파편이 무대 5종 전부에서 배경과 갈린다.** 색을 무대색에서 흰색으로 바꾼 것이 밝은 무대
    /// (한낮 하늘·오로라 커튼)에서 묻히지 않는지, 캐릭터 몸통(연보라)과도 갈리는지를 실측한다.
    @Test
    func theWhiteSparksReadOnEveryStage() throws {
        MiniGameMascot.resetCacheForTesting()
        _ = MiniGameMascot.sideProfile()
        var tiles: [NSBitmapImageRep] = []
        for (index, stage) in MiniGameStage.all.enumerated() {
            let score = MiniGameStage.flappyThresholds[index] + 1
            func frame(flappedAt: TimeInterval?) throws -> NSBitmapImageRep {
                let game = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: -280),
                                      pipes: [pipe(x: 215, centerY: 118, gap: 108)],
                                      score: score, phase: .running, elapsed: 4.0, scrolled: 470,
                                      lastFlapAt: flappedAt, flapCount: 7)
                return try renderBitmap(view(game, best: 40))
            }
            // 친 지 0.04초 — 열 점이 아직 짙을 때다(파편 색을 재려면 점 한가운데가 가장 불투명한 프레임이어야 한다).
            let jump = try frame(flappedAt: 3.96)
            let calm = try frame(flappedAt: nil)
            let foot = band((-34)...26, 20...54, around: 150)
            let ink = sparkInk(jump, calm, x: foot.x, y: foot.y)
            // 캐릭터 몸통(연보라)의 실제 휘도. 파편은 스프라이트 **아래 레이어**라 몸에 가려 겹치지 않지만,
            // 만에 하나 겹쳐도 파편 쪽이 더 밝아야 갈린다 — 그 여유를 여기서 잰다.
            let body = luminance(jump, atLogical: CGPoint(x: birdX, y: 158), half: 4)
            print("[flapfx] \(stage.name): count=\(ink.count) ink=\(Int(ink.ink)) behind=\(Int(ink.behind)) " +
                  "ratio=\(String(format: "%.2f", ink.ratio)) neutralBright=\(ink.neutralBright) " +
                  "peak=\(Int(ink.peak)) 몸통=\(Int(body.mean))")
            #expect(ink.count > sparkInkMin, "\(stage.name)에서 파편이 \(ink.count)픽셀뿐이다")
            #expect(ink.ratio > sparkContrastMin, "\(stage.name)에서 파편이 배경에 묻힌다(대비 \(ink.ratio))")
            #expect(ink.neutralBright > neutralSparkMin,
                    "\(stage.name) 파편이 흰색이 아니다(무채색 밝은 점 \(ink.neutralBright)px)")
            #expect(ink.peak > body.mean + 12,
                    "\(stage.name) 파편(\(Int(ink.peak)))이 몸통(\(Int(body.mean)))보다 밝지 않다")
            let crop = CGRect(x: t.origin.x + (birdX - 40) * t.scale, y: t.origin.y + (150 - 34) * t.scale,
                              width: 76 * t.scale, height: 96 * t.scale)
            if let zoomed = cropZoom(jump, ptRect: crop, zoom: 3) { tiles.append(zoomed) }
        }
        if let strip = stitch(tiles) { savePNG(strip, "flapfx-stages.png") }
    }

    /// **캐릭터가 하늘에도 기둥에도 묻히지 않는다 — 얹는 장치를 뺀 뒤 실측한 자리.**
    ///
    /// v0.2.51 에서 어두운 림·뒤통수 그늘·앞쪽 반사광을 뺐다(사용자: "나머지 다 초기로"). 그 셋은 장식이지만
    /// 림만은 **대비 장치**이기도 했다 — 그래서 눈대중이 아니라 5개 무대 × (하늘 위 · 기둥 위) 열 조합에서
    /// 캐릭터와 그 뒤 배경의 WCAG 휘도비를 실측하고, 어느 조합도 2.0:1 아래로 내려가지 않는 것을 확인한 뒤
    /// 뺐다. 이 테스트가 그 실측을 코드로 남긴 것이다 — 무대 색이나 스프라이트가 바뀌면 여기가 먼저 빨개진다.
    ///
    /// 2.0:1 인 이유: WCAG 최소 대비(비텍스트 3:1)보다 낮지만, 여기서 판정하는 것은 글자 판독이 아니라
    /// **34pt 실루엣이 배경에서 떨어지는가**다. 기둥에서 캐릭터가 사라졌던 v0.2.48 판이 1.01:1 이었고,
    /// 실기에서 "겹쳐도 보인다"가 성립한 v0.2.49~50 판이 3.1:1 이상이었다 — 2.0 은 그 사이의 바닥이다.
    @Test
    func theCharacterStaysReadableOnEveryStageWithNoRim() throws {
        MiniGameMascot.resetCacheForTesting()
        _ = MiniGameMascot.sideProfile()
        var worst = (ratio: Double.greatestFiniteMagnitude, label: "")
        var tiles: [NSBitmapImageRep] = []
        for (index, stage) in MiniGameStage.all.enumerated() {
            let score = MiniGameStage.flappyThresholds[index] + 1
            // 하늘 위: 기둥을 멀리 둔다. 기둥 위: 폭 44 기둥이 스프라이트(64.8…98.8)를 통째로 덮게 x = 60,
            // 틈은 위로 밀어 캐릭터가 **기둥 몸통 한가운데**에 놓이게 한다.
            let onSky = FlappyGame(seed: 9, bird: .init(x: birdX, y: 150, vy: 0),
                                   pipes: [pipe(x: 250, centerY: 150, gap: 108)],
                                   score: score, phase: .running, elapsed: 4.0, scrolled: 470)
            let onPipe = FlappyGame(seed: 9, bird: .init(x: birdX, y: 150, vy: 0),
                                    pipes: [pipe(x: 60, centerY: 40, gap: 108)],
                                    score: score, phase: .running, elapsed: 4.0, scrolled: 470)
            for (where_, game) in [("하늘 위", onSky), ("기둥 위", onPipe)] {
                let drawn = try renderBitmap(view(game, best: 40))
                let empty = try renderBitmap(view(withoutCharacter(game), best: 40))
                let measured = characterContrast(drawn, empty, around: CGPoint(x: birdX, y: 150), half: 18)
                print("[contrast] \(stage.name) \(where_): \(String(format: "%.2f", measured.ratio)):1 " +
                      "(캐릭터 L=\(String(format: "%.3f", measured.character)) · " +
                      "배경 L=\(String(format: "%.3f", measured.background)) · \(measured.pixels)px)")
                #expect(measured.pixels > 400, "\(stage.name) \(where_): 캐릭터 픽셀이 \(measured.pixels)개뿐 — 자가 고장 났다")
                #expect(measured.ratio >= characterContrastMin,
                        "\(stage.name) \(where_)에서 캐릭터가 배경에 묻힌다(\(measured.ratio):1) — 림을 되살려야 한다")
                if measured.ratio < worst.ratio { worst = (measured.ratio, "\(stage.name) \(where_)") }
                if where_ == "기둥 위" { savePNG(drawn, "flappy-onpipe-stage\(stage.id).png") }
                if where_ == "기둥 위",
                   let zoomed = cropZoom(drawn, ptRect: CGRect(x: t.origin.x + (birdX - 30) * t.scale,
                                                               y: t.origin.y + (150 - 30) * t.scale,
                                                               width: 60 * t.scale, height: 60 * t.scale), zoom: 4) {
                    tiles.append(zoomed)
                }
            }
        }
        print("[contrast] 최솟값 \(String(format: "%.2f", worst.ratio)):1 — \(worst.label)")
        if let strip = stitch(tiles) { savePNG(strip, "flappy-contrast-onpipe.png") }
    }
}

/// 캐릭터 픽셀 중 **어두운 잉크**(눈·입 — 채널 최대 ≤ 110)의 가로 무게중심을, 캐릭터 중심 기준 논리 pt 로.
/// 캐릭터 픽셀 = `bare`(캐릭터만 뺀 같은 프레임)와 어느 채널이든 24 넘게 다른 픽셀. 배경의 어두운 하늘이
/// 잉크로 섞여 들지 않게 하는 장치다.
@MainActor
private func faceInkOffset(_ drawn: NSBitmapImageRep, _ bare: NSBitmapImageRep,
                           aroundLogicalX cx: CGFloat, y: CGFloat, half: CGFloat) -> (offset: Double, samples: Int) {
    let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)
    guard let a = drawn.bitmapData, let b = bare.bitmapData, drawn.samplesPerPixel >= 4,
          drawn.bytesPerRow == bare.bytesPerRow else { return (0, 0) }
    let spp = drawn.samplesPerPixel, bpr = drawn.bytesPerRow
    let axis = Double((t.origin.x + cx * t.scale) * 2)
    let x0 = max(0, Int((t.origin.x + (cx - half) * t.scale) * 2))
    let x1 = min(drawn.pixelsWide - 1, Int((t.origin.x + (cx + half) * t.scale) * 2))
    let y0 = max(0, Int((t.origin.y + (y - half) * t.scale) * 2))
    let y1 = min(drawn.pixelsHigh - 1, Int((t.origin.y + (y + half) * t.scale) * 2))
    guard x0 <= x1, y0 <= y1 else { return (0, 0) }
    var sum = 0.0, n = 0
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            guard (0..<3).contains(where: { abs(Int(a[o + $0]) - Int(b[o + $0])) > 24 }),
                  max(a[o], max(a[o + 1], a[o + 2])) <= 110 else { continue }
            sum += (Double(px) - axis) / Double(2 * t.scale)
            n += 1
        }
    }
    return (n == 0 ? 0 : sum / Double(n), n)
}

/// 스프라이트가 **불투명한** 픽셀에서만 `jump` 와 `calm` 이 다른 수를 센다(스케일 2).
/// - 불투명: `calm`(한낮)과 `nightCalm`(같은 자세·밤 무대)이 **한 바이트도 안 다르고**, 그 자리에 캐릭터가
///   있다(`noCharacter` 와 어느 채널이든 24 초과 차이). 배경을 따라 변하는 픽셀은 반투명·투명이다.
/// - changed: 그 불투명 픽셀 중 `jump` 가 채널당 2 를 넘게 다른 수. 스프라이트 아래 캔버스(파편)는
///   불투명 픽셀을 바꿀 수 없으므로, 여기가 0 이 아니면 **몸 자체**가 바뀐 것이다.
private func opaqueBodyDifference(_ jump: NSBitmapImageRep, _ calm: NSBitmapImageRep,
                                  nightCalm: NSBitmapImageRep, noCharacter: NSBitmapImageRep,
                                  x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> (opaque: Int, changed: Int) {
    guard let j = jump.bitmapData, let c = calm.bitmapData, let n = nightCalm.bitmapData,
          let e = noCharacter.bitmapData, jump.samplesPerPixel >= 4,
          jump.bytesPerRow == calm.bytesPerRow, calm.bytesPerRow == nightCalm.bytesPerRow,
          calm.bytesPerRow == noCharacter.bytesPerRow else { return (0, 0) }
    let spp = jump.samplesPerPixel, bpr = jump.bytesPerRow
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(jump.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(jump.pixelsHigh - 1, Int(y.upperBound * 2))
    guard x0 <= x1, y0 <= y1 else { return (0, 0) }
    var opaque = 0, changed = 0
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            guard (0..<3).allSatisfy({ c[o + $0] == n[o + $0] }),
                  (0..<3).contains(where: { abs(Int(c[o + $0]) - Int(e[o + $0])) > 24 }) else { continue }
            opaque += 1
            if (0..<3).contains(where: { abs(Int(j[o + $0]) - Int(c[o + $0])) > 2 }) { changed += 1 }
        }
    }
    return (opaque, changed)
}

/// 발밑 파편의 최소 픽셀 수(스케일 2). 실측 170(한낮 한 프레임) · 무대 5종 235~240.
private let sparkInkMin = 120
/// 그중 **무채색이면서 밝은** 픽셀(점 한가운데)의 최소 수. 실측 106(한낮 한 프레임) · 무대 5종 148~162(2026-09-11).
/// 무대 강조색으로 되돌리면 채널 폭이 85~130 이라 **0** 이 된다 — 이 한 줄이 "파편은 흰색"을 지킨다.
private let neutralSparkMin = 60
/// 파편과 그 뒤 배경의 최소 휘도비. 무대 5종 실측 1.92(한낮 — 하늘이 가장 밝다) ~ 3.20(밤).
/// 1.6 은 그 아래 한 단계다: 세기를 0.82 에서 더 내리면 한낮부터 걸린다.
private let sparkContrastMin = 1.6
/// "호가 살던 대역에 무대색이 0" 을 재는 자의 **살아 있음 문턱**. 같은 대역·같은 함수로 무대 강조색 글씨
/// ("+1", 대역 왼쪽 끝에 걸쳐 일부만 들어온다)를 재면 실측 120px(2026-09-11). 60 은 그 절반이다 —
/// 예전 문턱 100 은 득점 링(316px)을 대조군으로 쓰던 시절 값이라 링이 빠진 지금은 아슬아슬했다.
/// 이 줄이 빨개지면 0 이 '없음'이 아니라 '눈멂'이라는 뜻이다.
private let arcProbeMin = 60
/// 캐릭터와 그 뒤 배경의 **최소 WCAG 휘도비**. 근거는 위 `theCharacterStaysReadableOnEveryStageWithNoRim` 주석에.
private let characterContrastMin = 2.0

// MARK: - (8) 소스 계약

private func swiftCodeStrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
            } else if let open = rest.range(of: "/*"), rest.range(of: "//").map({ open.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<open.lowerBound]
                rest = rest[open.upperBound...]
                inBlock = true
            } else if let slash = rest.range(of: "//") {
                kept += rest[..<slash.lowerBound]
                rest = ""
            } else {
                kept += rest
                rest = ""
            }
        }
        output += kept + "\n"
    }
    return output
}

@Test
func flappySourceKeepsTheLeafViewContract() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let raw = try String(contentsOf: root.appendingPathComponent("Sources/check/MiniGameFlappy.swift"), encoding: .utf8)
    let code = swiftCodeStrippingComments(raw)
    for forbidden in ["SCNView", "renderSnapshotPNG", "Timer.publish", "store.", "Double.random", "Int.random",
                      ".size =", "lockFocus", "DispatchSource", "aiToken",
                      // 바닥 띠는 없앴다(바닥 = 캔버스 아랫변) · 카드는 공용 것을 쓴다.
                      "floorBand", "FlappyOverlayCard"] {
        #expect(!code.contains(forbidden), "\(forbidden) 은 이 파일에 있으면 안 된다")
    }
    #expect(code.contains("TimelineView(.animation("))
    #expect(code.contains("paused:"))
    #expect(code.contains("CheckMascotAssets.image(for:"))
    // v0.2.49: 옆모습은 **구운 그림 한 장**으로만 들어온다. 씬·렌더러가 이 파일에 있으면 60Hz 루프 안에서
    // 3D 를 돌릴 길이 열린다 — 굽기는 MiniGameMascot 한 곳에만 둔다.
    #expect(code.contains("MiniGameMascot.sideProfile("))
    for forbidden3D in ["SCNRenderer", "SCNScene", "SCNNode", "MTLCreateSystemDefaultDevice"] {
        #expect(!code.contains(forbidden3D), "\(forbidden3D) 은 이 파일에 있으면 안 된다 — 굽기는 한 곳이다")
    }
    // 목도리는 뺐다(v0.2.49). 얼굴이 실제로 돌아가면서 존재 이유가 사라졌고, 돌아선 몸통 위에서는
    // 정면 PNG 기준으로 잰 좌표가 몸을 가로지르는 붉은 칼자국으로 읽혔다.
    #expect(!code.contains("Scarf"), "목도리가 되살아났다 — 옆모습과 겹쳐 보고 뺀 것이다")
    #expect(code.contains("MiniGameRandom"))
    #expect(code.contains("MiniGameFrameProbe.note()"))
    // 판이 자기 논리 크기(292×302)를 쓴다 — 공용 200 을 쓰면 위아래가 빈다.
    #expect(code.contains("MiniGameCanvas.transform(in:"))
    #expect(code.contains("logicalSize: FlappyGame.logicalSize"))
    #expect(code.contains("MiniGameOverlayCard("))
    // 갑자기 튀는 틈: 한 방(왕복 없음) · 화면에 들어와야 조준 · 색 신호 없음.
    #expect(code.contains("shiftJump"))
    #expect(code.contains("shiftAt"))
    #expect(code.contains("shiftDuration"))
    #expect(!code.contains("CheckTheme.pending"), "튀는 기둥을 색으로 표시하지 않는다(2026-09-08 결정)")
    // 입력은 허브가 넘긴다 — 잎 뷰에 제스처가 없다.
    #expect(!code.contains(".gesture(") && !code.contains("onTapGesture"))

    // v0.2.48: 그림은 공용 시각 키트를 쓴다(게임마다 따로 그리면 두 게임이 다른 제품처럼 보인다).
    // 남긴 넷이 전부 이 네 줄에 걸린다: 배경 · 파편(MiniGameEffects.sparks) · "+1" · 무대 팔레트.
    #expect(code.contains("MiniGameBackdrop.draw("))
    #expect(code.contains("MiniGameEffects.sparks("))
    #expect(code.contains("MiniGameScorePop("))
    #expect(code.contains("MiniGameStage"))
    // 일시정지 계약(두 줄): paused 에 host.isPaused 가 들어가고, tick 이 정지 중 시간을 흘리지 않는다.
    #expect(code.contains("paused: !game.isPlaying || host.isPaused"))
    #expect(code.contains("guard game.isPlaying, !host.isPaused else { lastTick = nil; return }"))

    // v0.2.50: 프레임 상한은 **화면 주사율에서** 온다. 리터럴을 다시 박으면 60 으로 나눠떨어지지 않는 화면
    // (75Hz·144Hz·90Hz …)에서 네 프레임에 한 장이 두 배로 늘어진다 — 사용자가 "살짝 버벅인다"로 신고한 그것이다.
    #expect(code.contains("MiniGameFrameRate.minimumInterval(forRefreshRate: host.refreshHz)"),
            "프레임 간격을 주사율에서 안 가져온다")
    for hardCoded in ["minimumInterval: 1.0 / 60.0", "minimumInterval: 1.0/60.0", "minimumInterval: 1/60",
                      "minimumInterval: nil"] {
        #expect(!code.contains(hardCoded), "\(hardCoded) — 프레임 상한을 여기 박지 마라(MiniGameFrameRate 가 정한다)")
    }

    // 정지 화면은 허브가 그린다 — 게임 쪽에 두 벌째를 만들지 않는다.
    #expect(!code.contains("일시정지됨") && !code.contains("PausedOverlay"))

    // ★ 유휴 0%: 시작 화면의 부유(`repeatForever`)는 v0.2.51 에서 통째로 지웠다.
    //   왜 글자로 막는가: `repeatForever` 는 **값만 내려서는 안 멈춘다**. 창을 닫아도 최소화해도 컴포지터가
    //   계속 돌아 코어의 3~4% 를 태웠다(2026-09-10 실측: 계속 켠 판 3.4~4.1% · 값만 내린 판 2.7~3.2% ·
    //   구조 분기로 정체성을 갈아치운 판 0.02~0.35%). 지금은 그 분기 자체가 없어졌으니, 다시 들어오는 것을
    //   막는 가장 싼 자물쇠가 "이 파일에 repeatForever 가 0회"다.
    #expect(!code.contains("repeatForever"),
            "반복 애니메이션이 되살아났다 — 창을 닫아도 컴포지터가 계속 돈다(2026-09-10 실측)")
    #expect(!code.contains("withAnimation"), "잎 뷰에 애니메이션이 들어왔다 — 프레임 루프 하나만 돌아야 한다")
    // 60Hz 예산: 캔버스 전체 blur·drawLayer 금지(통합 GPU 에서 프레임이 깨진다).
    #expect(!code.contains("addFilter") && !code.contains("drawLayer"))

    // ★★ v0.2.51 의 핵심 못 — **잔상은 규칙에서도 뷰에서도 흔적이 없다.**
    //   사용자 지시 2026-09-11: "그냥 잔상 없애줘." 뷰의 겹만 지우면 규칙이 매 프레임 배열을 밀고·버리고·
    //   붙이는 일이 그대로 남는다(= 지운 의미가 없다). 그래서 **식별자 자체가 0회**여야 한다.
    //   주석은 위에서 걷어냈다 — 안 걷으면 "잔상을 지웠다"고 적은 설명 때문에 이 줄이 빨개져서,
    //   초록으로 만들려면 설명을 지워야 하는 테스트가 된다.
    for ghost in ["trail", "Trail", "ghost", "silhouette"] {
        #expect(!code.contains(ghost), "\(ghost) 이 코드에 남아 있다 — 잔상이 되살아났다(2026-09-11 지시)")
    }
    // 지운 장식들의 이름도 함께 막는다. 죽은 상수·필드를 남기면 다음 사람이 "원래 있던 것"으로 되살린다.
    for removed in ["squash", "flapFlash", "shadowOpacity", "shadowFlatness", "deathSpin", "deathDrop",
                    "deathSpark", "stageFlare", "stageBanner", "stageChangedAt", "MiniGameStageChip",
                    "scorePunch", "idleBob", "bobEnabled", "readyPerch", "idleFloat", "scoreRing",
                    "rimOpacity", "rimScale", "backShade", "frontLight", "baseTilt", "hudInset",
                    "MiniGameEffects.ring(", "MiniGameEffects.flare("] {
        #expect(!code.contains(removed),
                "\(removed) 이 되살아났다 — 사용자가 보고 물린 장식이다(2026-09-11: 남긴 넷 말고 다 초기로)")
    }
    // ★ v0.2.50 점프 이펙트: **호는 전부 걷어냈다.** 두 번 거부당한 자리다 —
    //   v0.2.48 `MiniGameEffects.arch`(발밑에서 아래로 퍼지는 넓은 U) · v0.2.49 `wingBeat`(어깨 밖에서
    //   머리 위로 훑는 ∩ 한 쌍). 공용 헬퍼(MiniGameEffects.arch)는 키트에 남아 있지만 이 게임은 쓰지 않는다.
    #expect(!code.contains("MiniGameEffects.arch("),
            "넓은 U 아치가 되살아났다 — 몸은 위로 솟는데 신호는 아래를 말한다(2026-09-10 지적)")
    #expect(!code.contains("wingBeat"),
            "∩ 한 쌍이 되살아났다 — 34pt 실물에서 머리 위 \"^ ^\" 로 읽힌다(2026-09-10 지적)")
    #expect(!code.contains("flapWing"), "날개짓 호 상수가 남아 있다 — 죽은 상수는 되살아난다")
    // 남긴 넷의 글자 증거: 옆모습 · 발밑 파편 · "+1" 자리 · 배경 시계.
    #expect(code.contains("FlappyMascot(mood:"), "캐릭터가 FlappyMascot 을 안 쓴다")
    #expect(code.contains("facing:"), "옆모습 경로 스위치가 사라졌다")
    #expect(code.contains("FlappyFX.flapSparkAngles"), "발밑 파편이 사라졌다")
    #expect(code.contains("FlappyFX.scorePopBack"), "\"+1\" 자리 상수가 사라졌다")
    #expect(code.contains("scroll: game.scrolled"), "배경이 판 거리를 안 읽는다 — 패럴랙스가 멈춘다")
    // 파편 색은 무대와 무관한 **흰색**이다(2026-09-10: "밑에 거품처럼 뜨는 거 색깔을 흰색으로").
    #expect(code.contains("static let flapSparkColor = Color.white"),
            "점프 파편이 흰색이 아니다 — 무대 glow 로 되돌리면 새벽·노을에서 갈색으로 읽힌다")
    #expect(code.contains("color: FlappyFX.flapSparkColor"), "점프 파편이 그 색을 쓰지 않는다")
    // 기둥은 **v0.2.50 그대로**다(2026-09-11 사용자 추가 지시: "기둥도 변경한거 그대로 유지해도 될듯 … 기둥은
    // 버벅임에 영향 없어"). v0.2.51 초안이 "맨처음 기준"을 기둥까지 넓혀 단색 채움 + 1pt 외곽선으로 단순화했다가
    // 되돌렸다 — 그 단순화가 다시 들어오면 여기서 빨개진다. 기둥은 끊김의 원인이 아니다(도형 몇 개).
    #expect(code.contains("Gradient(colors: [stage.structureDeep, stage.structureDeepLit])"),
            "기둥 세로 그라디언트가 사라졌다 — 기둥은 v0.2.50 그대로 둔다(2026-09-11 추가 지시)")
    #expect(code.contains("context.fill(path, with: pipeShading)"), "기둥 본체가 그라디언트로 안 칠해진다")
    #expect(code.contains("let lipHeight = min(FlappyFX.lip, half.rect.height)"), "기둥 입구 립이 사라졌다")
    #expect(code.contains("static let lip: CGFloat = 10"), "기둥 입구 립 두께(10)가 바뀌었다")
    #expect(code.contains("with: .color(stage.structureEdge.opacity(0.95))"), "립과 몸통의 1pt 경계선이 사라졌다")
    #expect(code.contains("context.stroke(path, with: .color(stage.structureEdge.opacity(0.92)), lineWidth: 1.5)"),
            "기둥 외곽선이 1.5pt 가 아니다 — 1pt 로는 밤·오로라에서 어두운 본체가 하늘에 묻힌다")
    #expect(!code.contains("context.fill(path, with: .color(stage.structureDeep))"),
            "기둥이 단색 채움으로 단순화됐다 — 기둥은 '초기로' 목록에 없다(2026-09-11 추가 지시)")
    // 파편은 **스프라이트 아래 레이어**다. 뒤집으면 점이 얼굴 위로 올라온다.
    let canvasZ = try #require(code.range(of: "Canvas(rendersAsynchronously"))
    let spriteZ = try #require(code.range(of: "spriteAndScore\n"))
    #expect(canvasZ.lowerBound < spriteZ.lowerBound,
            "파편 캔버스가 스프라이트 위로 올라갔다 — 점이 얼굴을 덮는다")

    // ★ 그리기 함수 안에는 튀는 기둥 분기가 한 글자도 없다 — 색·모양으로 미리 알려 주지 않기로 한
    //   결정(2026-09-08)은 "그림이 shift* 를 읽지 않는다"로만 지켜진다.
    let drawStart = try #require(code.range(of: "private func draw(_ context: inout GraphicsContext"))
    let drawEnd = try #require(code.range(of: "private static let scorePopX"))
    let drawing = String(code[drawStart.lowerBound..<drawEnd.lowerBound])
    for forbidden in ["isShifting", "shiftDelay", "shiftAt", "shiftOffset"] {
        #expect(!drawing.contains(forbidden), "그리기가 \(forbidden) 를 읽으면 튀는 기둥이 눈에 띈다")
    }
    #expect(drawing.contains("MiniGameBackdrop.draw("), "배경을 그리는 자리가 draw 안이 맞는지")
}

// MARK: - (9) v0.2.49 옆모습 — 오버레이의 3D 모델을 구워 스프라이트로 쓴다
//
// 사용자 판정 기준(2026-09-10): "플래피에서도 캐릭터가 오른쪽을 바라보게. 드래그하면 돌아보는 그 캐릭터처럼."
// v0.2.48 의 그늘·목도리는 방향'감'까지였다 — 얼굴이 실제로 돌아가야 한다. 그래서 오버레이가 쓰는 그 모델을
// 오버레이가 쓰는 그 각도로 돌려 한 번 굽는다. 아래 검사는 그 굽기가 (1) 실제로 나오는지 (2) PNG 와 같은
// 크기로 앉는지 (3) 얼굴이 정말 오른쪽으로 쏠렸는지를 픽셀로 못 박는다.

/// pt 사각형을 잘라 정수배 확대(보간 없음 — 사용자가 실제로 보는 픽셀을 그대로 키운다).
private func cropZoom(_ bitmap: NSBitmapImageRep, ptRect: CGRect, zoom: CGFloat) -> NSBitmapImageRep? {
    guard let cg = bitmap.cgImage else { return nil }
    let px = CGRect(x: (ptRect.minX * 2).rounded(), y: (ptRect.minY * 2).rounded(),
                    width: (ptRect.width * 2).rounded(), height: (ptRect.height * 2).rounded())
        .intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    guard px.width >= 1, px.height >= 1, let cropped = cg.cropping(to: px) else { return nil }
    let w = Int(px.width * zoom), h = Int(px.height * zoom)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .none
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let out = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: out)
}

/// 여러 비트맵을 가로로 이어 붙인다(무대 비교용 한 장).
private func stitch(_ tiles: [NSBitmapImageRep]) -> NSBitmapImageRep? {
    let images = tiles.compactMap { $0.cgImage }
    guard !images.isEmpty else { return nil }
    let w = images.reduce(0) { $0 + $1.width }, h = images.map(\.height).max() ?? 0
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .none
    var x = 0
    for image in images {
        ctx.draw(image, in: CGRect(x: x, y: h - image.height, width: image.width, height: image.height))
        x += image.width
    }
    guard let out = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: out)
}

/// 캐릭터를 넉넉히 감싸는 pt 사각형(캔버스 좌표). 확대 스냅샷의 잘라내기 자리다.
///
/// v0.2.51 부터 **뷰가 그리는 y 와 규칙의 `bird.y` 가 언제나 같다.** 예전에는 두 자리에서 갈렸는데
/// (시작 전 카드에 안 가리게 74 로 올리기 · 죽은 뒤 46pt 떨어뜨리기) 둘 다 "맨처음 기준" 지시로 빠졌다
/// (2026-09-11). 그래서 이 함수에 phase 분기가 없다 — 분기가 다시 생기면 그림도 다시 갈린 것이다.
@MainActor
private func mascotBox(_ game: FlappyGame, pad: CGFloat = 13) -> CGRect {
    let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)
    let side = (FlappyGame.spriteSize + pad * 2) * t.scale
    return CGRect(x: t.origin.x + FlappyGame.birdX * t.scale - side / 2,
                  y: t.origin.y + game.bird.y * t.scale - side / 2, width: side, height: side)
}

/// 알파가 있는 픽셀 안에서 **어두운 잉크**(눈·입)의 가로 무게중심을, 실루엣 폭에 대한 0…1 로.
/// 정면 대칭 PNG 는 0.5 근처, 오른쪽을 본 옆모습은 0.5 보다 크다 — 이 한 숫자가 "얼굴이 돌아갔다"의 증거다.
private func inkCentroidX(_ image: NSImage) -> (centroid: Double, samples: Int)? {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let box = MiniGameMascot.alphaBox(cg) else { return nil }
    let w = cg.width, h = cg.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let base = ctx.data else { return nil }
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    let x0 = box.minX * CGFloat(w), boxW = box.width * CGFloat(w)
    var sum = 0.0, n = 0
    for row in 0..<h {
        let offset = row * ctx.bytesPerRow
        for x in 0..<w {
            let o = offset + x * 4
            guard bytes[o + 3] > 200 else { continue }
            // 프리멀티플라이드라 알파가 1 인 곳만 보므로 채널이 곧 색이다. 눈·입은 확연히 어둡다.
            let luma = 0.299 * Double(bytes[o]) + 0.587 * Double(bytes[o + 1]) + 0.114 * Double(bytes[o + 2])
            guard luma < 90 else { continue }
            sum += (Double(x) - Double(x0)) / Double(boxW)
            n += 1
        }
    }
    guard n > 20 else { return nil }
    return (sum / Double(n), n)
}

@MainActor
@Suite(.serialized)
struct V0249FlappyFacingTests {
    private let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)

    /// 굽기가 실제로 나오고, PNG 와 **같은 자리·같은 크기**로 앉는다.
    @Test
    func theSideProfileIsBakedAndFillsTheFrameLikeThePNG() throws {
        MiniGameMascot.resetCacheForTesting()
        let baked = MiniGameMascot.sideProfile()
        guard let baked else {
            // 헤드리스에 Metal 이 없는 환경 — 게임은 PNG 로 돈다. 그 사실만 남기고 통과시킨다.
            print("[facing] no metal device — PNG 폴백 경로")
            return
        }
        let cg = try #require(baked.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let box = try #require(MiniGameMascot.alphaBox(cg))
        print("[facing] baked \(cg.width)x\(cg.height) fill w=\(box.width) h=\(box.height) " +
              "center=(\(box.midX), \(box.midY)) ms=\(MiniGameMascot.lastBakeMilliseconds ?? -1) " +
              "source=\(MiniGameMascot.lastBakeSource?.rawValue ?? "-")")
        #expect(cg.width == Int(MiniGameMascot.spritePixels))
        #expect(abs(max(box.width, box.height) - MiniGameMascot.targetFill) < 0.03,
                "구운 캐릭터 크기가 PNG(0.85)와 어긋난다 — 히트박스 체감이 바뀐다")
        #expect(abs(box.midX - 0.5) < 0.03 && abs(box.midY - 0.5) < 0.03, "프레임 중앙에 안 앉았다")
        // 두 번째 호출은 캐시다 — 프레임마다 다시 굽지 않는다.
        let again = MiniGameMascot.sideProfile()
        #expect(again === baked, "옆모습이 캐시되지 않았다 — 60Hz 예산이 무너진다")
        // 굽기 값(참고용 계측). 첫 굽기는 Metal·SceneKit 첫 접촉이 섞여 크고, 그 뒤는 10ms 대다.
        var times: [Double] = []
        for _ in 0..<3 {
            MiniGameMascot.resetCacheForTesting()
            _ = MiniGameMascot.sideProfile()
            times.append(((MiniGameMascot.lastBakeMilliseconds ?? -1) * 10).rounded() / 10)
        }
        print("[facing] BAKE_TIMES \(times)")
    }

    /// **방향의 증거.** 어두운 잉크(눈·입)의 무게중심이 정면 PNG 는 가운데, 구운 옆모습은 오른쪽으로 쏠린다.
    @Test
    func theFaceActuallyLeansRight() throws {
        MiniGameMascot.resetCacheForTesting()
        let png = try #require(CheckMascotAssets.image(for: .neutral))
        let frontal = try #require(inkCentroidX(png))
        print("[facing] PNG ink centroid=\(frontal.centroid) n=\(frontal.samples)")
        #expect(abs(frontal.centroid - 0.5) < 0.06, "정면 PNG 는 좌우 대칭이어야 한다(기준선)")
        guard let baked = MiniGameMascot.sideProfile(), let side = inkCentroidX(baked) else { return }
        print("[facing] 3D ink centroid=\(side.centroid) n=\(side.samples)")
        #expect(side.centroid > frontal.centroid + 0.04,
                "구운 옆모습의 얼굴이 오른쪽으로 안 쏠렸다 — 정면과 구별되지 않는다")
    }

    /// 프리베이크 `.scn` 이 없는 머신이 타는 **usdz 폴백**도 같은 그림을 낸다. 그 경로는 USD/ModelIO 를
    /// 상주시키고 2048² 텍스처를 디코드하므로 느리다 — 얼마나 느린지를 숫자로 남긴다(캐시라 한 번뿐이다).
    @Test
    func theUSDZFallbackAlsoBakesARightFacingProfile() throws {
        let prebaked = MiniGameMascot.bakeForTesting(order: [.prebaked])
        let started = Date()
        guard let usdz = MiniGameMascot.bakeForTesting(order: [.usdz]) else {
            print("[facing] usdz 폴백을 구울 수 없다(Metal 없음 또는 리소스 없음)")
            return
        }
        let ms = Date().timeIntervalSince(started) * 1_000
        let side = try #require(inkCentroidX(usdz))
        print("[facing] usdz source=\(MiniGameMascot.lastBakeSource?.rawValue ?? "-") " +
              "ink centroid=\(side.centroid) n=\(side.samples) ms=\((ms * 10).rounded() / 10)")
        #expect(MiniGameMascot.lastBakeSource == .usdz, "usdz 폴백을 안 탔다 — 이 검사가 아무것도 안 본다")
        #expect(side.centroid > 0.55, "usdz 폴백에서 얼굴이 오른쪽으로 안 쏠렸다")
        if let prebaked, let base = inkCentroidX(prebaked) {
            #expect(abs(side.centroid - base.centroid) < 0.08,
                    "두 출처가 다른 그림을 낸다 — 머신마다 캐릭터가 달라 보인다")
        }
        if let cg = usdz.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            savePNG(NSBitmapImageRep(cgImage: cg), "facing-usdz.png")
        }
    }

    /// **폴백이 실제로 게임을 살린다.** 굽기가 nil 인 경우(Metal 없는 헤드리스 · 모델 없음)와 같은 경로를
    /// 게임오버 표정이 그대로 탄다 — `.negative` 는 3D 로 못 내므로 언제나 PNG 다. 그 프레임에서도
    /// 캐릭터가 그려지는지를 "새를 판 밖으로 뺀 같은 프레임"과 비교해 못 박는다.
    @Test
    func aBakeThatReturnsNilStillDrawsTheCharacter() throws {
        #expect(MiniGameMascot.sideProfile(mood: .negative) == nil,
                "게임오버 표정을 3D 로 지어내고 있다 — 없는 표정이다")
        let over = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: 300),
                              pipes: [pipe(x: 70, centerY: 118, gap: 108)],
                              score: 8, phase: .over(hold: 0.18), elapsed: 4.0, scrolled: 470)
        let drawn = try renderBitmap(view(over, best: 12))
        let gone = FlappyGame(seed: 5, bird: .init(x: birdX, y: -600, vy: 300),
                              pipes: over.pipes, score: 8, phase: .over(hold: 0.18), elapsed: 4.0, scrolled: 470)
        let empty = try renderBitmap(view(gone, best: 12))
        let box = mascotBox(over, pad: 0)
        #expect(differing(drawn, empty, x: box.minX...box.maxX, y: box.minY...box.maxY) > 300,
                "PNG 폴백에서 캐릭터가 안 그려진다 — Metal 없는 환경에서 게임이 빈다")
    }

    /// 다섯 무대 · 진행 · 점프 · 죽은 뒤 스냅샷. 눈으로 판정하는 증거를 남긴다.
    @Test
    func facingSnapshots() throws {
        MiniGameMascot.resetCacheForTesting()
        _ = MiniGameMascot.sideProfile()

        // 1) 진행 중 한 장 — 한낮 무대(8점).
        let run = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: -60),
                             pipes: [pipe(x: 205, centerY: 118, gap: 108), pipe(x: 335, centerY: 196, gap: 108)],
                             score: 8, phase: .running, elapsed: 4.0, scrolled: 470,
                             lastFlapAt: 3.4, flapCount: 7)
        #expect(run.stage == .day)
        let runBitmap = try renderBitmap(view(run, best: 12))
        savePNG(runBitmap, "facing-run.png")

        // 2) 캐릭터만 8배 — 판정의 핵심 증거. 보간 없이 키운다(사용자가 보는 그 픽셀).
        let zoom = try #require(cropZoom(runBitmap, ptRect: mascotBox(run), zoom: 8))
        savePNG(zoom, "facing-zoom.png")

        // 3) 무대 5종 — 캐릭터 자리만 잘라 4배로 이어 붙인다.
        var tiles: [NSBitmapImageRep] = []
        for score in [3, 8, 16, 26, 40] {
            let gap = FlappyGame.gap(forScore: score), spacing = FlappyGame.spacing(forScore: score)
            let game = FlappyGame(seed: 9, bird: .init(x: birdX, y: 138, vy: -140),
                                  pipes: [pipe(x: 104, centerY: 140, gap: gap),
                                          pipe(x: 104 + spacing, centerY: 200, gap: gap)],
                                  score: score, phase: .running, elapsed: 6, scrolled: 620,
                                  lastFlapAt: 5.2, flapCount: 12)
            let bitmap = try renderBitmap(view(game, best: 30))
            if let tile = cropZoom(bitmap, ptRect: mascotBox(game), zoom: 4) { tiles.append(tile) }
        }
        if let strip = stitch(tiles) { savePNG(strip, "facing-stages.png") }

        // 4) 점프 프레임 — 스쿼시·플래시·파편과 겹친 얼굴.
        let flap = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: -280),
                              pipes: [pipe(x: 205, centerY: 118, gap: 108), pipe(x: 335, centerY: 196, gap: 108)],
                              score: 8, phase: .running, elapsed: 4.0, scrolled: 470,
                              lastFlapAt: 3.95, flapCount: 7)
        let flapBitmap = try renderBitmap(view(flap, best: 12))
        savePNG(flapBitmap, "facing-flap.png")
        if let zoomed = cropZoom(flapBitmap, ptRect: mascotBox(flap, pad: 22), zoom: 6) {
            savePNG(zoomed, "facing-flap-zoom.png")
        }

        // 5) 죽은 뒤(회전 낙하 중) — 유예 0.4 중 절반쯤.
        let over = FlappyGame(seed: 5, bird: .init(x: birdX, y: 150, vy: 300),
                              pipes: [pipe(x: 70, centerY: 118, gap: 108), pipe(x: 200, centerY: 196, gap: 108)],
                              score: 8, phase: .over(hold: 0.18), elapsed: 4.0, scrolled: 470,
                              lastFlapAt: 3.2, flapCount: 7)
        let overBitmap = try renderBitmap(view(over, best: 12))
        savePNG(overBitmap, "facing-over.png")
        if let zoomed = cropZoom(overBitmap, ptRect: mascotBox(over, pad: 22), zoom: 6) {
            savePNG(zoomed, "facing-over-zoom.png")
        }
    }
}

// MARK: - 프레임 간격이 달라도 같은 판인가 (v0.2.50)
//
// 프레임 상한이 화면 주사율을 따라가면서 **같은 판이 60fps 와 75fps 로 각각 밀린다.** 순위표가 걸린
// 게임이라 그 둘이 다른 난이도면 안 된다. 물리는 실 dt 를 쓰고 `maxStep`(1/30) 클램프도 그대로라
// 원리적으로는 같아야 하는데, 그 '원리'가 코드에 남아 있는지는 여기서만 확인된다 —
// 누가 dt 대신 프레임당 상수를 박으면 75fps 판은 그 즉시 25% 빨라진다.

/// 1/15초를 한 '틱'으로 삼는다 — 60fps 는 4프레임, 75fps 는 5프레임, 120fps 는 8프레임이라
/// **세 간격 모두에서 틱 경계가 정확히 같은 시각**이다(점프 시각과 비교 시각이 갈리지 않는다).
private let fpsTickHz = 15

private struct FpsSample {
    let tick: Int
    let y: Double
    let vy: Double
    let score: Int
    let scrolled: Double
    let elapsed: Double
    let playing: Bool
    let running: Bool
}

/// 같은 시드·같은 점프 일정을 주어진 프레임 간격으로 민다. 점프는 틱 경계에서만 일어난다.
private func fpsTrace(fps: Int, ticks: Int, flapEveryTick: Int, seed: UInt64 = 0xF1A99) -> [FpsSample] {
    var game = FlappyGame(seed: seed)
    game.flap()                                   // 시작(ready → running)
    let dt = 1.0 / Double(fps)
    let framesPerTick = fps / fpsTickHz
    var out: [FpsSample] = []
    for tick in 1...ticks {
        for _ in 0..<framesPerTick { game.step(dt: dt) }
        if tick % flapEveryTick == 0 { game.flap() }
        var running = false
        if case .running = game.phase { running = true }
        out.append(FpsSample(tick: tick, y: Double(game.bird.y), vy: Double(game.bird.vy),
                             score: game.score, scrolled: Double(game.scrolled),
                             elapsed: game.elapsed, playing: game.isPlaying, running: running))
    }
    return out
}

/// 7틱(0.4667초)마다 점프하면 판이 **제자리에서 오르내린다** — 점프 한 번의 상승과 그다음 낙하가 정확히
/// 상쇄되는 주기다(T = −2·flapVelocity/gravity = 2×317/1360 = 0.466s). 그래서 이 리듬이면 새가 오래 살고
/// 기둥도 몇 개 지나간다: 프레임 간격을 비교할 창이 열린다.
private let fpsHoverTicks = 7

@Test
func flappyRunsTheSameBoardAtEveryFrameRate() {
    let at60 = fpsTrace(fps: 60, ticks: 200, flapEveryTick: fpsHoverTicks)
    let at75 = fpsTrace(fps: 75, ticks: 200, flapEveryTick: fpsHoverTicks)
    let at120 = fpsTrace(fps: 120, ticks: 200, flapEveryTick: fpsHoverTicks)
    let run60 = at60.prefix { $0.running }.count
    let run75 = at75.prefix { $0.running }.count
    let run120 = at120.prefix { $0.running }.count

    // ① **이 변경이 실제로 쥔 두 값**(60 = 지금까지 · 75 = 이 기계)은 같은 판을 살고 같은 틱에 죽는다.
    #expect(run60 == run75, "60fps 와 75fps 가 다른 틱에 죽었다(\(run60) vs \(run75)) — 판이 프레임에 끌려간다")
    #expect(run60 > 60, "비교할 창이 너무 짧다(\(run60)틱) — 픽스처가 무너졌다")

    let window = min(run60, min(run75, run120))
    #expect(at60[window - 1].score >= 2, "기둥을 하나도 안 지났다 — 비교가 시시하다")

    var worstY75 = 0.0, worstY120 = 0.0, worstScroll = 0.0, worstElapsed = 0.0
    for i in 0..<window {
        let a = at60[i], b = at75[i], c = at120[i]
        // ② 판 시계와 스크롤은 dt 의 단순 합이라 **간격과 무관하게 같다**.
        //    누가 dt 대신 프레임당 상수를 박으면 75fps 판이 25% 빨라져 여기가 통째로 갈린다.
        worstElapsed = max(worstElapsed, max(abs(a.elapsed - b.elapsed), abs(a.elapsed - c.elapsed)))
        worstScroll = max(worstScroll, max(abs(a.scrolled - b.scrolled), abs(a.scrolled - c.scrolled)))
        worstY75 = max(worstY75, abs(a.y - b.y))
        worstY120 = max(worstY120, abs(a.y - c.y))
        // ③ 같은 틱에 같은 점수 — 기둥을 지나는 시각까지 같다.
        #expect(a.score == b.score, "틱 \(a.tick): 60/75 점수가 갈렸다(\(a.score) vs \(b.score))")
        #expect(a.score == c.score, "틱 \(a.tick): 60/120 점수가 갈렸다(\(a.score) vs \(c.score))")
    }
    let seconds = at60[window - 1].elapsed
    #expect(worstElapsed < 1e-9, "판 시계가 프레임 간격을 탄다(\(worstElapsed)s)")
    // 스크롤은 점수가 오르는 프레임에서 속도 단계가 한 프레임 어긋날 수 있어 딱 0 은 아니다(실측 0.03pt).
    // 프레임이 판을 밀고 있었다면 이 값은 수백 pt 가 된다.
    #expect(worstScroll < 0.2, "스크롤이 프레임 간격을 탄다(\(worstScroll)pt)")

    // ④ 새의 높이만 걸음 크기에 끌린다. **그 끌림이 정확히 '알고 있는 한 항'인지**를 재는 것이 이 단언이다:
    //    중력 적분이 semi-implicit Euler(vy 를 먼저 밀고 그 vy 로 y 를 민다)라 한 걸음에 g·h/2 만큼 더
    //    내려가고, 그 차이가 시간에 비례해 쌓인다 → 초당 gravity × (h₁ − h₂) / 2.
    //    이 항 말고 다른 프레임 의존이 생기면(dt 대신 상수, 프레임 수로 세는 타이머 …) 비율이 무너진다.
    //    **이 항은 이번 변경이 만든 것이 아니라 원래 있던 적분 방식이다** — 상수는 한 글자도 안 건드렸다.
    for (label, worst, fps) in [("75", worstY75, 75.0), ("120", worstY120, 120.0)] {
        let predicted = Double(FlappyGame.gravity) * (1.0 / 60.0 - 1.0 / fps) / 2 * seconds
        let ratio = worst / predicted
        print("[fps-invariance] 60↔\(label): 높이차 \(String(format: "%.2f", worst))pt "
              + "(예측 \(String(format: "%.2f", predicted))pt · 비 \(String(format: "%.3f", ratio)))")
        #expect(abs(ratio - 1) < 0.15,
                "60↔\(label)fps 높이차가 오일러 적분 항으로 설명되지 않는다(비 \(ratio)) — 새 프레임 의존이 생겼다")
    }
    print("[fps-invariance] window=\(window)틱(\(String(format: "%.2f", seconds))s) "
          + "score=\(at60[window - 1].score) 생존틱 60/75/120=\(run60)/\(run75)/\(run120) "
          + "worstElapsed=\(worstElapsed) worstScroll=\(String(format: "%.4f", worstScroll))")
}
