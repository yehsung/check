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

/// 무대 이름 배너 길이(초). 소스의 FlappyFX 는 private 이라 여기 값과 갈라질 수 있다 —
/// 갈라지면 아래 "0.9초 뒤엔 사라진다" 테스트가 빨개져서 알려 준다.
private let FlappyFX_stageBannerProbe: TimeInterval = 0.9

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
func viewOnlyMarkersRecordFlapsScoresAndStageChanges() {
    var game = FlappyGame(seed: 7)
    #expect(game.lastFlapAt == nil && game.flapCount == 0 && game.stageChangedAt == nil)

    game.flap()                                   // ready → running(첫 점프)
    #expect(game.flapCount == 1 && game.lastFlapAt == 0)
    game.step(dt: 1.0 / 60.0)
    game.flap()
    #expect(game.flapCount == 2)
    #expect(abs((game.lastFlapAt ?? -1) - game.elapsed) < 1e-9, "점프 시각은 판 시계 기준이다")

    // over 유예 중 클릭은 기록되지 않는다 — 죽은 뒤에 날개가 퍼덕이면 안 된다.
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
    #expect(scoring.stageChangedAt == scoring.elapsed, "5 → 6 은 무대 경계(새벽 → 한낮)다")

    // 경계가 아닌 득점에서는 무대 표시가 갱신되지 않는다(배너가 매 점수마다 뜨면 시야를 먹는다).
    let banner = scoring.stageChangedAt
    scoring.step(dt: 1.0 / 60.0)
    #expect(scoring.stageChangedAt == banner)

    // 새 판이면 그림용 기록도 전부 초기화된다 — 앞 판의 배너·파편이 새 판에 묻어 나오면 안 된다.
    scoring.interrupt()
    scoring.flap()
    #expect(scoring.scrolled == 0 && scoring.lastScoreAt == nil && scoring.lastScorePipeCenter == nil
            && scoring.stageChangedAt == nil && scoring.flapCount == 1 && scoring.lastFlapAt == 0)
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
        // 점수는 **오른쪽 위**다 — 타이밍 바와 같은 모서리(HUD 규약 통일, 2026-09-10).
        #expect(count(bitmap, x: 290...335, y: 8...50, where: isInkPixel) > 30, "오른쪽 위에 점수가 없다")
        #expect(count(bitmap, x: 140...210, y: 8...50, where: isInkPixel) == 0, "점수가 아직 가운데에 있다")
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
        // 그리고 캐릭터는 카드 **위**에 떠 있다(예전엔 카드 뒤에서 유령처럼 비쳤다 — 2026-09-10).
        // 마스코트는 연보라(밝다)이고 그 높이의 새벽 하늘은 어두운 자주라 밝기로 갈린다.
        let t = MiniGameCanvas.transform(in: CGSize(width: CW, height: CH), logicalSize: FlappyGame.logicalSize)
        let side = FlappyGame.spriteSize * t.scale
        let px = t.origin.x + birdX * t.scale, py = t.origin.y + 74 * t.scale
        let mascot = count(bitmap, x: (px - side / 2)...(px + side / 2),
                           y: (py - side / 2)...(py + side / 2)) { r, _, b, a in a >= 250 && r >= 120 && b >= 150 }
        #expect(mascot > 300, "시작 화면 카드 위에 캐릭터가 없다 — 밝은 픽셀 \(mascot)개")
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

    /// ready 에서는 **프레임 루프**가 0회다.
    ///
    /// ⚠️ 이 테스트가 **못 재는 것**: 장식 애니메이션. 시작 화면의 부유는 TimelineView 가 아니라 SwiftUI
    /// 애니메이션이라 프레임 프로브의 시야 밖이고, 그래서 v0.2.48 초안은 이 테스트가 초록인 채로 코어의
    /// 3~4% 를 계속 태웠다(2026-09-10). 그쪽 가드는 소스 계약
    /// (`flappySourceKeepsTheLeafViewContract` 의 bobEnabled 분기 단언)에 있다.
    @Test
    func readyStateDoesNotAdvanceAnyFrame() throws {
        MiniGameFrameProbe.reset()
        _ = try renderBitmap(view(FlappyGame(seed: 1)))
        #expect(MiniGameFrameProbe.frames == 0, "ready 는 paused — 프레임 루프가 0회여야 유휴 0% 가 지켜진다")
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

    /// 무대가 바뀌는 순간 한 장 — 이름 칩(0.9초)과 플레어. 칩은 진행 점과 **같은 자리**(HUD 왼쪽 위)를 쓴다
    /// (따로 두면 HUD 가 판 안쪽으로 자라 캐릭터·기둥과 겹친다).
    @Test
    func stageChangeShowsTheBannerInsteadOfTheDots() throws {
        func frame(changedAt: TimeInterval?) throws -> NSBitmapImageRep {
            let game = FlappyGame(seed: 9, bird: .init(x: birdX, y: 150, vy: -100),
                                  pipes: [pipe(x: 104, centerY: 140, gap: FlappyGame.gap(forScore: 13)),
                                          pipe(x: 104 + FlappyGame.spacing(forScore: 13), centerY: 200,
                                               gap: FlappyGame.gap(forScore: 13))],
                                  score: 13, phase: .running, elapsed: 12, scrolled: 1400,
                                  stageChangedAt: changedAt)
            return try renderBitmap(view(game, best: 30))
        }
        let banner = try frame(changedAt: 11.8)      // 0.2초 전 — 배너와 플레어가 한창일 때
        savePNG(banner, "flappy-stage-banner.png")
        let plain = try frame(changedAt: nil)
        // HUD 왼쪽 위(진행 점 자리)가 눈에 띄게 달라진다 — 점 대신 무대 이름 칩이 들어섰다.
        #expect(differing(banner, plain, x: 14...110, y: 12...50) > 150, "무대 배너가 안 뜬다")
        // 그리고 아래쪽 하늘도 플레어로 밝아진다.
        #expect(differing(banner, plain, x: 20...120, y: 250...340) > 500, "무대 전환 플레어가 없다")
        // 0.9초가 지나면 배너는 사라진다(상시 글씨는 시야를 먹는다).
        let after = try frame(changedAt: 12 - FlappyFX_stageBannerProbe)
        #expect(differing(after, plain, x: 14...110, y: 12...50) == 0, "배너가 0.9초 뒤에도 남아 있다")
    }

    /// 점프 직후 한 장 — 스쿼시·날개·파편이 함께 있는 구간.
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
        // 캐릭터 주위(날개·파편·스쿼시)가 눈에 띄게 달라진다 — "점프하는 듯한 임팩트"(2026-09-10).
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
    #expect(code.contains("MiniGameBackdrop.draw("))
    #expect(code.contains("MiniGameEffects."))
    #expect(code.contains("MiniGameScorePop("))
    #expect(code.contains("MiniGameStage"))
    // 일시정지 계약(두 줄): paused 에 host.isPaused 가 들어가고, tick 이 정지 중 시간을 흘리지 않는다.
    #expect(code.contains("paused: !game.isPlaying || host.isPaused"))
    #expect(code.contains("guard game.isPlaying, !host.isPaused else { lastTick = nil; return }"))
    // 정지 화면은 허브가 그린다 — 게임 쪽에 두 벌째를 만들지 않는다.
    #expect(!code.contains("일시정지됨") && !code.contains("PausedOverlay"))

    // ★ 유휴 0%: 시작 화면의 부유는 `repeatForever` 다. **값만 내려서는 안 멈춘다** —
    //   창을 닫아도 최소화해도 컴포지터가 계속 돌아 코어의 3~4% 를 태웠다(2026-09-10 실측:
    //   계속 켠 판 3.4~4.1% · 값만 내린 판 2.7~3.2% · 구조 분기로 정체성을 갈아치운 판 0.02~0.35%).
    //   그래서 두 가지를 글자로 못 박는다: ① repeatForever 가 **구조 분기 안에만** 있다
    //   ② 허브가 판을 끊으면(창 닫힘·포커스 상실·전환·[그만두기]) 그 분기가 갈린다.
    #expect(code.contains("if bobEnabled, game.phase == .ready, !host.reduceMotion {"),
            "부유가 구조 분기 밖에 있다 — 애니메이션이 붙은 뷰 정체성이 안 버려진다")
    #expect(code.components(separatedBy: "repeatForever").count - 1 == 1,
            "repeatForever 가 그 분기 말고 다른 곳에도 있다")
    let interrupt = try #require(code.range(of: ".onChange(of: host.interruptToken)"))
    let afterInterrupt = String(code[interrupt.lowerBound...].prefix(220))
    #expect(afterInterrupt.contains("bobEnabled = false"),
            "판을 끊어도 부유가 안 꺼진다 — 창을 닫은 뒤에도 애니메이션이 계속 돈다")
    // 60Hz 예산: 캔버스 전체 blur·drawLayer 금지(통합 GPU 에서 프레임이 깨진다).
    #expect(!code.contains("addFilter") && !code.contains("drawLayer"))

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
