import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.46 미니게임 — 타이밍 바. 규칙(순수 값 타입)·상태 기계·dt 클램프·렌더·프레임 프로브·소스 계약.
// 시드를 고정하면 판이 결정적이라(MiniGameRandom 만 쓴다) 목표 중심을 읽어 "정중앙에서 멈추는 시각"을 역산할 수 있다.
//
// v0.2.48 시각 개편(2026-09-10)에서 그림이 통째로 바뀌었다(논리 292×302 · 무대 · 3중 목표 구간 · 판정 등급 ·
// 세그먼트 바). 그래서 **렌더 단언은 새 그림 기준으로 다시 썼고**, 규칙 단언은 한 줄도 바뀌지 않았다 —
// 이 파일의 (1)(2)(3) 절과 `timingBarDifficultyConstantsAreFrozen` 이 "디자인 작업이 난이도를 안 건드렸다"의 증거다.

// MARK: - 픽스처

private let tbSeed: UInt64 = 0xC0FFEE
/// 스냅샷을 남길 곳(저장소 밖 — 스크래치).

/// 시작된 판(running 1, t = 0).
private func tbStarted(seed: UInt64 = tbSeed) -> TimingBarGame {
    var game = TimingBarGame(seed: seed)
    game.tap()
    return game
}

/// 마커가 목표 중심에 오는 시각(첫 왕복의 오르막 구간, p = 2t/T → t = c·T/2)까지 1/30 걸음으로 전진한다.
private func tbAdvanceToTargetCenter(_ game: inout TimingBarGame) {
    tbAdvanceToPosition(&game, game.target.center)
}

/// 첫 왕복 오르막에서 마커를 위치 p(0…1)까지 전진시킨다(t = p·T/2).
private func tbAdvanceToPosition(_ game: inout TimingBarGame, _ position: Double) {
    guard case .running(let round, let t0) = game.phase else { return }
    let goal = position * TimingBarGame.period(round: round) / 2
    var remaining = goal - t0
    while remaining > 1e-12 {
        let dt = min(remaining, TimingBarGame.maxStep)
        game.step(dt: dt)
        remaining -= dt
    }
}

/// 게임 시간을 `seconds` 만큼 1/30 걸음으로 흘린다(dt 클램프 때문에 한 번에 못 흘린다).
private func tbAdvance(_ game: inout TimingBarGame, by seconds: TimeInterval) {
    var remaining = seconds
    while remaining > 1e-12 {
        let dt = min(remaining, TimingBarGame.maxStep)
        game.step(dt: dt)
        remaining -= dt
    }
}

/// 결과 표시(0.6초)를 넘긴다 — 19 걸음(19/30 = 0.633초 > 0.6).
private func tbSkipResultHold(_ game: inout TimingBarGame) {
    for _ in 0..<19 { game.step(dt: TimingBarGame.maxStep) }
}

/// 정중앙에서 멈춘 완벽한 라운드 하나(점수 100)를 마치고 다음 상태까지 보낸다.
private func tbPlayPerfectRound(_ game: inout TimingBarGame) {
    tbAdvanceToTargetCenter(&game)
    game.tap()
    tbSkipResultHold(&game)
}

/// 목표 구간 **밖**에서 멈춘 라운드 하나(0점)를 마치고 다음 상태까지 보낸다.
private func tbPlayMissedRound(_ game: inout TimingBarGame) {
    tbTapOutsideTarget(&game)
    tbSkipResultHold(&game)
}

/// 목표에서 폭만큼 떨어진 자리(d = 2)에서 정지한다. 트랙 밖으로 나가는 쪽이면 반대편을 쓴다.
private func tbTapOutsideTarget(_ game: inout TimingBarGame) {
    let (center, width) = game.target
    let position = center + width <= 0.97 ? center + width : center - width
    tbAdvanceToPosition(&game, position)
    game.tap()
}

private func tbFinishedGame(seed: UInt64 = tbSeed) -> TimingBarGame {
    var game = tbStarted(seed: seed)
    for _ in 0..<TimingBarGame.roundCount { tbPlayPerfectRound(&game) }
    return game
}

/// 라운드 `round` 를 진행 중인 판(앞 라운드는 전부 100점). 마커는 트랙 한가운데(p = 0.5).
private func tbRunningRound(_ round: Int, seed: UInt64 = tbSeed) -> TimingBarGame {
    var game = tbStarted(seed: seed)
    for _ in 0..<(round - 1) { tbPlayPerfectRound(&game) }
    tbAdvance(&game, by: TimingBarGame.period(round: round) / 4)
    return game
}

// MARK: - (1) 순수 함수

@Test
func timingBarPeriodAndWidthTable() {
    // 2026-09-08 난이도 상향: 주기 1.40/−0.09 → 1.10/−0.075(하한 0.42), 폭 0.30/−0.022 → 0.24/−0.019(하한 0.07).
    #expect(abs(TimingBarGame.period(round: 1) - 1.10) < 1e-9)
    #expect(abs(TimingBarGame.period(round: 5) - 0.80) < 1e-9)
    #expect(abs(TimingBarGame.period(round: 10) - 0.425) < 1e-9)
    #expect(abs(TimingBarGame.targetWidth(round: 1) - 0.24) < 1e-9)
    #expect(abs(TimingBarGame.targetWidth(round: 5) - 0.164) < 1e-9)
    #expect(abs(TimingBarGame.targetWidth(round: 9) - 0.088) < 1e-9)
    // 하한: r10 에서 폭이 이미 하한(0.069 → 0.07)이고, 라운드가 더 가도 0.42 / 0.07 밑으로 안 내려간다.
    #expect(TimingBarGame.targetWidth(round: 10) == 0.07)
    #expect(TimingBarGame.period(round: 30) == 0.42)
    #expect(TimingBarGame.targetWidth(round: 30) == 0.07)
}

@Test
func timingBarGetsHarderEveryRoundUntilItFlattens() {
    // 라운드마다 더 빠르고(주기 ↓) 더 좁다(폭 ↓). 하한에 닿은 뒤로는 평평하다.
    for round in 1..<TimingBarGame.roundCount {
        #expect(TimingBarGame.period(round: round) > TimingBarGame.period(round: round + 1),
                "r\(round) 주기가 r\(round + 1) 보다 짧다")
        #expect(TimingBarGame.targetWidth(round: round) >= TimingBarGame.targetWidth(round: round + 1))
    }
    // 폭은 r9 → r10 에서도 실제로 좁아진다(하한에 닿기 직전 구간).
    #expect(TimingBarGame.targetWidth(round: 9) > TimingBarGame.targetWidth(round: 10))
    #expect(TimingBarGame.period(round: 11) == TimingBarGame.period(round: 40))
    #expect(TimingBarGame.targetWidth(round: 11) == TimingBarGame.targetWidth(round: 40))
    // 종전(1.40 · 0.30)보다 1라운드부터 어렵다 — 이 두 줄이 '난이도 상향'의 계약이다.
    #expect(TimingBarGame.period(round: 1) < 1.40)
    #expect(TimingBarGame.targetWidth(round: 1) < 0.30)
}

@Test
func timingBarMarkerIsATriangleWave() {
    let period = 1.40
    #expect(abs(TimingBarGame.markerPosition(t: 0, period: period) - 0) < 1e-9)
    #expect(abs(TimingBarGame.markerPosition(t: period / 4, period: period) - 0.5) < 1e-9)
    #expect(abs(TimingBarGame.markerPosition(t: period / 2, period: period) - 1) < 1e-9)
    #expect(abs(TimingBarGame.markerPosition(t: period, period: period) - 0) < 1e-9)
    // 두 번째 왕복도 같은 모양(주기 함수).
    #expect(abs(TimingBarGame.markerPosition(t: period * 1.25, period: period) - 0.5) < 1e-9)
    // 음수 시각도 정의된다 — 마커 잔상(t − k/60)이 이 성질에 기대고 있다(v0.2.48).
    #expect(abs(TimingBarGame.markerPosition(t: -period / 4, period: period) - 0.5) < 1e-9)
    for frames in [2.0, 4.0, 6.0] {
        let ghost = TimingBarGame.markerPosition(t: 0.01 - frames / 60, period: period)
        #expect(ghost >= 0 && ghost <= 1, "잔상 위치가 트랙(0…1) 밖으로 나가면 안 된다")
    }
}

@Test
func timingBarRoundScoreTable() {
    // 구간 안: 정중앙 100 → 가장자리 70. 구간 밖: 0 (부분 점수 없음 — 사용자 결정 2026-09-08).
    #expect(TimingBarGame.roundScore(distance: 0) == 100)
    #expect(TimingBarGame.roundScore(distance: 0.5) == 85)
    #expect(TimingBarGame.roundScore(distance: 1) == 70)
    #expect(TimingBarGame.roundScore(distance: 1.0001) == 0)
    #expect(TimingBarGame.roundScore(distance: 1.5) == 0)
    #expect(TimingBarGame.roundScore(distance: 2.5) == 0)
}

@Test
func timingBarTargetStaysInsideTheTrackForEveryRound() {
    for seed: UInt64 in [1, 2, 3, tbSeed, 0xDEAD_BEEF] {
        var game = tbStarted(seed: seed)
        for round in 1...TimingBarGame.roundCount {
            guard case .running(let r, _) = game.phase else {
                Issue.record("라운드 \(round) 이 running 이 아니다: \(game.phase)")
                return
            }
            #expect(r == round)
            let width = TimingBarGame.targetWidth(round: round)
            #expect(abs(game.target.width - width) < 1e-9)
            let lo = width / 2 + 0.05, hi = 1 - width / 2 - 0.05
            #expect(game.target.center >= lo && game.target.center <= hi,
                    "시드 \(seed) 라운드 \(round): 중심 \(game.target.center) 가 [\(lo), \(hi)] 밖")
            tbPlayPerfectRound(&game)
        }
    }
}

/// **난이도 불변 회귀(v0.2.48 디자인 작업의 계약).** 판을 292×200 → 292×302 로 키우고 그림을 전부 새로
/// 그렸지만, 난이도를 정하는 값은 한 톨도 안 움직였다. 이 게임의 규칙은 정규화 좌표(0…1)라 판 크기와 무관하다.
@Test
func timingBarDifficultyConstantsAreFrozen() {
    let periods: [Double] = [1.10, 1.025, 0.95, 0.875, 0.80, 0.725, 0.65, 0.575, 0.50, 0.425]
    let widths: [Double] = [0.24, 0.221, 0.202, 0.183, 0.164, 0.145, 0.126, 0.107, 0.088, 0.07]
    for round in 1...TimingBarGame.roundCount {
        #expect(abs(TimingBarGame.period(round: round) - periods[round - 1]) < 1e-9,
                "r\(round) 주기가 \(periods[round - 1]) 에서 \(TimingBarGame.period(round: round)) 로 변했다")
        #expect(abs(TimingBarGame.targetWidth(round: round) - widths[round - 1]) < 1e-9,
                "r\(round) 목표 폭이 \(widths[round - 1]) 에서 \(TimingBarGame.targetWidth(round: round)) 로 변했다")
    }
    // 배점: d 0 → 100, 0.5 → 85, 1 → 70, 밖 → 0. 한 판 최대 1000점(= 서버 check 상한과 같다).
    // d 0.35 는 90점 **경계**라 부동소수 반올림이 89로 떨어진다 — 그래서 표에는 0.34 를 둔다
    // (안쪽 띠 폭 0.35 는 이 경계를 그린 것이다. MiniGameTimingBar.swift 의 innerTargetRatio 주석 참고).
    for (distance, score) in [(0.0, 100), (0.1, 97), (0.34, 90), (0.5, 85), (0.9, 73), (1.0, 70), (1.01, 0)] {
        #expect(TimingBarGame.roundScore(distance: distance) == score,
                "d \(distance) 의 점수가 \(score) 에서 \(TimingBarGame.roundScore(distance: distance)) 로 변했다")
    }
    #expect(TimingBarGame.roundCount == 10)
    #expect(TimingBarGame.roundCount * 100 == MiniGameKind.timingBar.maxScore)
    #expect(TimingBarGame.resultHold == 0.6)
    #expect(TimingBarGame.maxStep == 1.0 / 30.0)
}

// MARK: - (1b) 판정 등급 · 콤보 (v0.2.48)

@Test
func timingBarVerdictBoundaries() {
    // 경계는 100 / 90 / 80 / 70. 배점상 70 미만은 0 뿐이지만 함수는 그 사이 값도 빗나감으로 접는다.
    #expect(TimingBarGame.verdict(score: 100) == .perfect)
    #expect(TimingBarGame.verdict(score: 99) == .great)
    #expect(TimingBarGame.verdict(score: 90) == .great)
    #expect(TimingBarGame.verdict(score: 89) == .good)
    #expect(TimingBarGame.verdict(score: 80) == .good)
    #expect(TimingBarGame.verdict(score: 79) == .close)
    #expect(TimingBarGame.verdict(score: 70) == .close)
    #expect(TimingBarGame.verdict(score: 69) == .miss)
    #expect(TimingBarGame.verdict(score: 0) == .miss)
    // 실제로 나올 수 있는 점수(0 · 70…100)가 전부 등급을 얻는다.
    for distance in stride(from: 0.0, through: 1.2, by: 0.01) {
        let score = TimingBarGame.roundScore(distance: distance)
        let verdict = TimingBarGame.verdict(score: score)
        #expect((score == 0) == (verdict == .miss), "d \(distance): 점수 \(score) 와 등급 \(verdict) 가 어긋난다")
    }
    // 색만으로 알리지 않는다 — 등급마다 글자가 다르다.
    let labels = [TimingBarGame.Verdict.perfect, .great, .good, .close, .miss].map(\.label)
    #expect(Set(labels).count == labels.count, "등급 라벨이 겹친다: \(labels)")
    #expect(labels.allSatisfy { !$0.isEmpty })
}

@Test
func timingBarComboCountsTrailingHits() {
    var game = tbStarted()
    #expect(game.combo == 0, "시작 전엔 콤보가 없다")
    tbPlayPerfectRound(&game)
    #expect(game.combo == 1)
    tbPlayPerfectRound(&game)
    tbPlayPerfectRound(&game)
    #expect(game.combo == 3)
    // 한 번 빗나가면 그 자리에서 끊긴다(꼬리에서 세기 때문에 앞의 3연속은 잊힌다).
    tbPlayMissedRound(&game)
    #expect(game.roundScores.suffix(1) == [0])
    #expect(game.combo == 0)
    tbPlayPerfectRound(&game)
    #expect(game.combo == 1, "끊긴 뒤엔 1부터 다시")
    // 무효화하면 콤보도 사라진다.
    game.invalidate()
    #expect(game.combo == 0)
}

/// 콤보는 **표시 전용**이다. 총점에 섞이면 서버 상한 1000점을 넘겨 업로드가 거부되고 순위 의미가 깨진다.
@Test
func timingBarComboNeverEntersTheTotal() {
    var game = tbStarted()
    for _ in 0..<TimingBarGame.roundCount {
        tbPlayPerfectRound(&game)
        #expect(game.total == game.roundScores.reduce(0, +), "총점이 라운드 점수 합이 아니다(콤보가 섞였다)")
    }
    #expect(game.combo == 10)
    #expect(game.total == 1000, "10연속 완벽의 총점은 콤보와 무관하게 1000")
    #expect(game.total <= MiniGameKind.timingBar.maxScore)

    // 콤보가 끊긴 판도 마찬가지 — 합계는 라운드 점수의 합 그대로다.
    var mixed = tbStarted(seed: 99)
    for index in 0..<TimingBarGame.roundCount {
        if index % 3 == 0 { tbPlayMissedRound(&mixed) } else { tbPlayPerfectRound(&mixed) }
    }
    #expect(mixed.total == mixed.roundScores.reduce(0, +))
    #expect(mixed.roundScores == [0, 100, 100, 0, 100, 100, 0, 100, 100, 0])
    #expect(mixed.total == 600, "0점 4번(r1·r4·r7·r10) + 100점 6번")
}

@Test
func timingBarStageAdvancesEveryTwoRounds() {
    // 무대는 2라운드마다 한 단계. 시작 전(0)은 새벽, 10라운드는 오로라 — 창 상단 칩이 이 이름을 그대로 쓴다.
    let expected: [Int: String] = [0: "새벽", 1: "새벽", 2: "새벽", 3: "한낮", 4: "한낮", 5: "노을", 6: "노을",
                                   7: "밤", 8: "밤", 9: "오로라", 10: "오로라"]
    for (round, name) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(MiniGameStage.forTimingRound(round).name == name,
                "라운드 \(round) 무대가 \(name) 이 아니라 \(MiniGameStage.forTimingRound(round).name)")
    }
    // 라운드가 10을 넘어도 마지막 무대에서 멎는다(상한 없는 인덱싱 사고 방지).
    #expect(MiniGameStage.forTimingRound(50).name == "오로라")
    #expect(MiniGameStage.forTimingRound(9).id != MiniGameStage.forTimingRound(1).id)
}

// MARK: - (2) 상태 기계

@Test
func timingBarStartsOnFirstTap() {
    var game = TimingBarGame(seed: tbSeed)
    #expect(game.phase == .ready)
    #expect(!game.isPlaying)
    #expect(game.round == 0)
    game.tap()
    #expect(game.phase == .running(round: 1, t: 0))
    #expect(game.isPlaying)
    #expect(game.round == 1)
    #expect(game.roundScores.isEmpty)
    #expect(game.total == 0)
}

@Test
func timingBarTapAtTheCenterScoresAHundredThenAdvancesAfterTheHold() {
    var game = tbStarted()
    tbAdvanceToTargetCenter(&game)
    #expect(abs(game.markerPosition - game.target.center) < 1e-9)
    game.tap()
    guard case .roundResult(let round, let score, let hold) = game.phase else {
        Issue.record("정지 뒤 roundResult 가 아니다: \(game.phase)"); return
    }
    #expect(round == 1)
    #expect(score == 100)
    #expect(abs(hold - TimingBarGame.resultHold) < 1e-9)
    #expect(game.roundScores == [100])
    #expect(game.total == 100)
    #expect(game.isPlaying, "결과 표시 중에도 루프는 돈다(hold 를 깎아야 한다)")
    #expect(game.lastHit == true)
    // 결과 표시 중 클릭은 무시한다(두 번 눌러 다음 라운드를 잃지 않게).
    game.tap()
    #expect(game.roundScores == [100])
    // 0.6초가 지나면 스스로 다음 라운드.
    for _ in 0..<17 { game.step(dt: TimingBarGame.maxStep) }   // 0.567초 — 아직
    if case .roundResult = game.phase {} else { Issue.record("0.6초 전에 넘어갔다: \(game.phase)") }
    for _ in 0..<2 { game.step(dt: TimingBarGame.maxStep) }    // 0.633초 — 넘어간다
    #expect(game.phase == .running(round: 2, t: 0))
    #expect(game.round == 2)
}

@Test
func timingBarMissedTapScoresByDistance() {
    var game = tbStarted()
    // 마커가 t=0 에서 0 에 있다. 목표 중심은 ≥ 0.17 이므로 즉시 정지하면 d ≥ 0.17/0.12 > 1 이다(라운드 1 폭 0.24).
    let d = abs(0 - game.target.center) / (game.target.width / 2)
    game.tap()
    guard case .roundResult(_, let score, _) = game.phase else { Issue.record("roundResult 아님"); return }
    #expect(score == TimingBarGame.roundScore(distance: d))
    #expect(score == 0, "구간 밖은 0점")
    #expect(game.lastHit == (d <= 1))
    #expect(game.markerPosition == 0, "정지한 자리에 마커가 얼어 있다")
}

@Test
func timingBarFinishesAfterTenRoundsAndRestartsOnTap() {
    var game = tbStarted()
    for round in 1...TimingBarGame.roundCount {
        #expect(game.round == round)
        tbPlayPerfectRound(&game)
    }
    #expect(game.phase == .finished(total: 1000))
    #expect(game.total == 1000)
    #expect(game.roundScores.count == 10)
    #expect(!game.isPlaying)
    #expect(game.round == 10)
    // finished 에서 클릭 = 바로 새 판(ready 를 거치지 않는다).
    game.tap()
    #expect(game.phase == .running(round: 1, t: 0))
    #expect(game.roundScores.isEmpty)
    #expect(game.total == 0)
}

@Test
func timingBarInvalidateReturnsToReadyWithoutScores() {
    var game = tbStarted()
    tbPlayPerfectRound(&game)
    tbPlayPerfectRound(&game)
    #expect(game.roundScores.count == 2)
    game.invalidate()
    #expect(game.phase == .ready)
    #expect(game.roundScores.isEmpty)
    #expect(game.total == 0)
    #expect(!game.isPlaying)
    #expect(game.lastHit == nil)
    // 무효 뒤에도 다시 시작할 수 있다.
    game.tap()
    #expect(game.phase == .running(round: 1, t: 0))
}

@Test
func timingBarIsDeterministicForASeed() {
    var a = tbStarted(seed: 42), b = tbStarted(seed: 42)
    for _ in 0..<3 { tbPlayPerfectRound(&a); tbPlayPerfectRound(&b) }
    #expect(a == b)
    #expect(a.target.center == b.target.center)
    var c = tbStarted(seed: 43)
    tbPlayPerfectRound(&c)
    #expect(c.target.center != a.target.center || c.phase != a.phase)
}

// MARK: - (3) dt 클램프

@Test
func timingBarStepClampsLargeDeltas() {
    var game = tbStarted()
    game.step(dt: 5)
    #expect(game.phase == .running(round: 1, t: TimingBarGame.maxStep), "5초 걸음이 1/30 초로 잘려야 한다")
    game.step(dt: -1)
    #expect(game.phase == .running(round: 1, t: TimingBarGame.maxStep), "음수 dt 는 0 으로")
    // ready/finished 에서는 시간이 흐르지 않는다.
    var idle = TimingBarGame(seed: 1)
    idle.step(dt: 1)
    #expect(idle.phase == .ready)
}

// MARK: - (4) 렌더

private enum TimingRenderError: Error { case failed }

@MainActor
private func tbRenderBitmap(_ view: some View, width: CGFloat = MiniGameWindowLayout.canvasSize.width,
                            height: CGFloat = MiniGameWindowLayout.canvasSize.height) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(CheckTheme.panel).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
        throw TimingRenderError.failed
    }
    return bitmap
}

/// 실제 창 캔버스(344×356)로 한 판을 그린다 — 사람이 보는 크기가 이것뿐이라 스냅샷도 전부 이 크기다.
@MainActor
private func tbCanvasBitmap(_ game: TimingBarGame, bestScore: Int = 0, reduceMotion: Bool = false) throws -> NSBitmapImageRep {
    let view = TimingBarGameView(host: .inert(bestScore: bestScore, reduceMotion: reduceMotion),
                                 input: MiniGameInput(), initialGame: game)
    return try tbRenderBitmap(view)
}

private func tbSavePNG(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: name, sub: "timing")
}

/// predicate(r,g,b,a) 를 만족하는 픽셀 수(전체).
private func tbCount(_ bitmap: NSBitmapImageRep, where predicate: (Int, Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var n = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3])) { n += 1 }
        }
    }
    return n
}

/// 영역(pt 좌표, 스케일 2) 안에서 predicate 를 만족하는 픽셀 수.
private func tbCountIn(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
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

/// 한 행에 predicate 가 `minRun` 개 이상 걸리는 첫 y(pt). 없으면 nil.
/// **행 단위로 세는 이유**: 그라디언트 경계에서 우연히 카드 색과 같아지는 낱 픽셀이 늘 몇십 개 나온다.
/// 카드는 폭 240pt(=480px)짜리 판이라 "이 행에 잔뜩 있다"로 봐야 진짜 카드의 윗변을 잡는다.
private func tbTopEdge(_ bitmap: NSBitmapImageRep, minRun: Int = 120,
                       where predicate: (Int, Int, Int, Int) -> Bool) -> CGFloat? {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return nil }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    for y in 0..<bitmap.pixelsHigh {
        var run = 0
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3])) { run += 1 }
        }
        if run >= minRun { return CGFloat(y) / 2 }
    }
    return nil
}

/// y 구간 안에서 한 행이 predicate 를 만족한 최대 개수.
private func tbMaxRowCount(_ bitmap: NSBitmapImageRep, y: ClosedRange<CGFloat>,
                           where predicate: (Int, Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(y.upperBound * 2))
    guard y0 <= y1 else { return 0 }
    var best = 0
    for py in y0...y1 {
        var run = 0
        for px in 0..<bitmap.pixelsWide {
            let o = py * bpr + px * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2]), Int(data[o + 3])) { run += 1 }
        }
        best = max(best, run)
    }
    return best
}

/// 영역 평균 밝기(0…255).
private func tbBrightness(_ bitmap: NSBitmapImageRep, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> Double {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 4 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(x.lowerBound * 2)), x1 = min(bitmap.pixelsWide - 1, Int(x.upperBound * 2))
    let y0 = max(0, Int(y.lowerBound * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(y.upperBound * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var sum = 0.0, n = 0.0
    for py in y0...y1 {
        for px in x0...x1 {
            let o = py * bpr + px * spp
            sum += Double(Int(data[o]) + Int(data[o + 1]) + Int(data[o + 2])) / 3
            n += 1
        }
    }
    return n > 0 ? sum / n : 0
}

// ── 색 판별기 ────────────────────────────────────────────────────────────────────────────
// v0.2.48 부터 배경이 무대 색이라 "이 색이 있다"만으로는 약하다. 그래서 판별기는 **판정 색**(무대를 안 타는
// 다섯 색)과 **마커**(흰 블레이드)에만 쓰고, 나머지는 위치·밝기로 확인한다.

/// working 초록 (89,224,161) — 90점대(훌륭) 판정.
private func tbIsWorking(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool { a > 200 && g >= 180 && g - r >= 60 && g > b }
/// danger 빨강 (255,115,117) — 빗나감.
private func tbIsDanger(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool { a > 200 && r >= 200 && g < 160 && b < 160 }
/// 완벽(100점) 금색 (255,214,133).
private func tbIsGold(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool { a > 200 && r >= 225 && g >= 175 && g <= 235 && b < 175 }
/// 마커 블레이드(흰색 primaryText 0.94) — 진행 중 마커.
private func tbIsMarker(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool { a > 200 && r >= 215 && g >= 215 && b >= 215 }
/// 오버레이 카드 바탕 panelElevated(54,56,74) 0.94 를 무대 하늘 위에 얹은 값. 하늘은 r 과 g 가 이만큼
/// 붙는 구간이 없어(새벽·오로라 모두 g 가 r 보다 한참 낮거나 높다) 카드만 걸린다.
private func tbIsCard(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    a > 200 && abs(r - 53) <= 7 && abs(g - 56) <= 7 && abs(b - 73) <= 8
}

// ── 논리 좌표(292×302) → 실제 pt. 창 캔버스 344×356 에서 배율 ≈1.178 ────────────────────
private func tbScale() -> CGFloat {
    MiniGameCanvas.transform(in: MiniGameWindowLayout.canvasSize,
                             logicalSize: CGSize(width: MiniGameCanvas.logicalWidth, height: 302)).scale
}
private func tbOrigin() -> CGPoint {
    MiniGameCanvas.transform(in: MiniGameWindowLayout.canvasSize,
                             logicalSize: CGSize(width: MiniGameCanvas.logicalWidth, height: 302)).origin
}
private func tbY(_ logical: CGFloat) -> CGFloat { tbOrigin().y + logical * tbScale() }
private func tbX(_ logical: CGFloat) -> CGFloat { tbOrigin().x + logical * tbScale() }

// MARK: 스냅샷 8장 (사람이 눈으로 보는 검증)

@MainActor
@Test
func timingBarSnapshotsCoverEveryStateOnTheRealCanvas() throws {
    // 1) 시작 화면 — 트랙이 보이고 카드와 겹치지 않아야 한다(v0.2.48 의 핵심 요구).
    tbSavePNG(try tbCanvasBitmap(TimingBarGame(seed: tbSeed)), "timing-ready.png")
    // 2·3·4) 무대가 라운드로 바뀐다: r1 새벽 · r5 노을 · r9 오로라.
    tbSavePNG(try tbCanvasBitmap(tbRunningRound(1)), "timing-r1.png")
    tbSavePNG(try tbCanvasBitmap(tbRunningRound(5)), "timing-r5.png")
    tbSavePNG(try tbCanvasBitmap(tbRunningRound(9)), "timing-r9.png")
    // 5) 완벽 판정 직후 — 링 2개·파편·팝·섬광.
    tbSavePNG(try tbCanvasBitmap(tbPerfectMoment()), "timing-perfect.png")
    // 6) 빗나감 직후 — 붉은 플래시·danger 마커·"+0 · 빗나감".
    tbSavePNG(try tbCanvasBitmap(tbMissMoment()), "timing-miss.png")
    // 7) 콤보 3.
    tbSavePNG(try tbCanvasBitmap(tbComboThree()), "timing-combo.png")
    // 8) 결과 카드(신기록).
    tbSavePNG(try tbCanvasBitmap(tbFinishedGame(), bestScore: 700), "timing-result.png")
}

/// 완벽(100점) 판정 0.133초 뒤 — 링이 퍼지는 중.
private func tbPerfectMoment() -> TimingBarGame {
    var game = tbStarted()
    tbPlayPerfectRound(&game)
    tbPlayPerfectRound(&game)
    tbAdvanceToTargetCenter(&game)
    game.tap()
    for _ in 0..<4 { game.step(dt: TimingBarGame.maxStep) }
    return game
}

/// 빗나감 0.067초 뒤 — 붉은 플래시가 아직 살아 있고 화면이 흔들리는 중.
private func tbMissMoment() -> TimingBarGame {
    var game = tbStarted()
    tbPlayPerfectRound(&game)
    tbTapOutsideTarget(&game)
    for _ in 0..<2 { game.step(dt: TimingBarGame.maxStep) }
    return game
}

/// 3연속 명중 중인 판(앞에 한 번 빗나가 콤보가 정확히 3 이다).
private func tbComboThree() -> TimingBarGame {
    var game = tbStarted()
    tbPlayMissedRound(&game)
    for _ in 0..<3 { tbPlayPerfectRound(&game) }
    tbAdvance(&game, by: TimingBarGame.period(round: 5) / 4)
    return game
}

// MARK: 렌더 단언

@MainActor
@Test
func timingBarReadyShowsTheTrackAndTheCardWithoutOverlap() throws {
    // 종전에는 카드가 가운데를 덮어 트랙 양 끝만 괄호처럼 삐져나왔고, 그래서 시작 화면에 트랙을 아예 안 그렸다.
    // v0.2.48: 판이 세로로 길어졌으니 카드를 아래에 붙이고 트랙을 보여 준다 — 트랙이 이 게임의 얼굴이다.
    let bitmap = try tbCanvasBitmap(TimingBarGame(seed: tbSeed))
    #expect(bitmap.pixelsWide == Int(MiniGameWindowLayout.canvasSize.width) * 2)
    #expect(bitmap.pixelsHigh == Int(MiniGameWindowLayout.canvasSize.height) * 2)

    // (a) 트랙이 있다: 캡슐 안쪽(어두운 그라디언트)이 바로 위 하늘보다 뚜렷이 어둡다.
    let trackBand = tbBrightness(bitmap, x: tbX(60)...tbX(232), y: tbY(144)...tbY(156))
    let skyBand = tbBrightness(bitmap, x: tbX(60)...tbX(232), y: tbY(118)...tbY(130))
    #expect(trackBand < skyBand * 0.75, "트랙 캡슐이 안 보인다(트랙 \(trackBand) vs 하늘 \(skyBand))")

    // (b) 카드는 트랙 아래에서 시작한다 — 겹치면 이 단언이 무너진다.
    let cardTop = try #require(tbTopEdge(bitmap, where: tbIsCard), "시작 카드가 안 그려졌다")
    #expect(cardTop > tbY(160), "카드 윗변(\(cardTop)pt)이 트랙(\(tbY(159))pt)을 덮는다")
    #expect(tbMaxRowCount(bitmap, y: 0...tbY(160), where: tbIsCard) < 60,
            "트랙과 그 위쪽에 카드 몸통이 걸쳐 있다")

    // (c) 시작 전엔 마커도 목표 구간도 없다(트랙만 있다).
    #expect(tbCountIn(bitmap, x: 0...MiniGameWindowLayout.canvasSize.width, y: tbY(130)...tbY(172),
                      where: tbIsMarker) < 20, "시작 전엔 마커가 없다")
}

@MainActor
@Test
func timingBarRunningFrameShowsTheTargetLayersAndTheMarker() throws {
    let game = tbRunningRound(1)
    #expect(abs(game.markerPosition - 0.5) < 1e-9)
    let bitmap = try tbCanvasBitmap(game, bestScore: 640)
    // 마커: 흰 블레이드 + 삼각 촉. 트랙 밴드 안에서만 센다(하늘의 별이 섞이지 않게).
    let marker = tbCountIn(bitmap, x: tbX(120)...tbX(172), y: tbY(133)...tbY(167), where: tbIsMarker)
    #expect(marker > 250, "마커 블레이드가 안 보인다(\(marker)px)")
    // 목표 구간: 트랙 밴드가 하늘보다 밝은 구간(무대 structure 3중)이 있어야 한다.
    let (center, width) = game.target
    let inside = tbBrightness(bitmap, x: tbX(24 + CGFloat(center - width / 4) * 244)...tbX(24 + CGFloat(center + width / 4) * 244),
                              y: tbY(144)...tbY(156))
    let outside = tbBrightness(bitmap, x: tbX(28)...tbX(40), y: tbY(144)...tbY(156))
    #expect(inside > outside * 1.4, "목표 구간이 빈 트랙과 구별되지 않는다(\(inside) vs \(outside))")
    // 진행 중엔 카드가 없다(그라디언트 경계의 낱 픽셀은 행 단위로 세면 걸러진다).
    #expect(tbTopEdge(bitmap, where: tbIsCard) == nil, "running 중엔 오버레이 카드가 없다")
}

@MainActor
@Test
func timingBarStagesDifferByRound() throws {
    // 무대가 라운드로 갈린다 = 같은 자리(하늘)의 색이 r1 · r5 · r9 에서 서로 다르다.
    let frames = try [1, 5, 9].map { try tbCanvasBitmap(tbRunningRound($0)) }
    func skyColor(_ bitmap: NSBitmapImageRep) -> (Int, Int, Int) {
        guard let data = bitmap.bitmapData else { return (0, 0, 0) }
        let o = Int(tbY(95) * 2) * bitmap.bytesPerRow + Int(tbX(146) * 2) * bitmap.samplesPerPixel
        return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
    }
    let colors = frames.map(skyColor)
    for (a, b) in [(0, 1), (1, 2), (0, 2)] {
        let delta = abs(colors[a].0 - colors[b].0) + abs(colors[a].1 - colors[b].1) + abs(colors[a].2 - colors[b].2)
        #expect(delta > 20, "무대가 안 바뀌었다: \(colors[a]) vs \(colors[b])")
    }
}

@MainActor
@Test
func timingBarPerfectHitPaintsGoldRingsAndPop() throws {
    let bitmap = try tbCanvasBitmap(tbPerfectMoment())
    // 완벽은 금색 — 마커·링·파편·"+100 완벽!" 팝이 전부 같은 색으로 온다.
    #expect(tbCount(bitmap, where: tbIsGold) > 400, "완벽 판정의 금색이 거의 없다")
    // 링은 마커에서 퍼진다 — 트랙 밴드 바깥(위쪽)에도 금색이 있어야 한다.
    #expect(tbCountIn(bitmap, x: 0...MiniGameWindowLayout.canvasSize.width, y: tbY(96)...tbY(132), where: tbIsGold) > 40,
            "링·팝이 마커 위로 안 퍼졌다")
    #expect(tbCount(bitmap, where: tbIsDanger) < 40, "완벽인데 danger 색이 보인다")
}

@MainActor
@Test
func timingBarMissedRoundResultFlashesRedAndPaintsTheMarker() throws {
    let game = tbMissMoment()
    #expect(game.lastHit == false)
    let bitmap = try tbCanvasBitmap(game)
    #expect(tbCount(bitmap, where: tbIsDanger) > 300, "빗나간 정지는 마커·팝·세그먼트가 danger 색")
    // 붉은 플래시: 화면 전체가 붉게 물든다 — 하늘의 빨강 성분이 같은 프레임의 평상시보다 높다.
    var calm = game
    for _ in 0..<8 { calm.step(dt: TimingBarGame.maxStep) }   // 0.27초 — 플래시가 끝난 뒤
    let calmBitmap = try tbCanvasBitmap(calm)
    func redness(_ bitmap: NSBitmapImageRep) -> Double {
        guard let data = bitmap.bitmapData else { return 0 }
        var sum = 0.0, n = 0.0
        for y in stride(from: 40, to: 200, by: 4) {
            for x in stride(from: 40, to: 600, by: 4) {
                let o = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
                sum += Double(Int(data[o]) - Int(data[o + 2]))
                n += 1
            }
        }
        return n > 0 ? sum / n : 0
    }
    #expect(redness(bitmap) > redness(calmBitmap) + 8,
            "붉은 플래시가 없다(\(redness(bitmap)) vs \(redness(calmBitmap)))")
}

@MainActor
@Test
func timingBarComboChipAppearsOnlyFromTwoInARow() throws {
    // 콤보만 다른 두 판을 **같은 라운드(5 = 노을)** 에서 비교한다 — 무대가 다르면 하늘 색이 달라 비교가 안 된다.
    var one = tbStarted()
    for _ in 0..<3 { tbPlayMissedRound(&one) }     // r1~r3 빗나감
    tbPlayPerfectRound(&one)                        // r4 명중 → 콤보 1
    tbAdvance(&one, by: TimingBarGame.period(round: 5) / 4)
    #expect(one.combo == 1)
    let three = tbComboThree()
    #expect(three.combo == 3)
    let chipless = try tbCanvasBitmap(one)
    let chipped = try tbCanvasBitmap(three)
    // 콤보 칩은 헤더 아래(논리 y 56)에 뜬다. 칩의 글자·테두리는 하늘보다 훨씬 밝다.
    let band = (x: tbX(90)...tbX(202), y: tbY(46)...tbY(66))
    func chipPixels(_ bitmap: NSBitmapImageRep) -> Int {
        tbCountIn(bitmap, x: band.x, y: band.y) { r, g, b, a in a > 200 && r + g + b > 450 }
    }
    #expect(chipPixels(chipped) > 250, "콤보 3 칩이 안 보인다(\(chipPixels(chipped))px)")
    #expect(chipPixels(chipless) < 80, "콤보 1에서도 칩이 그려진다(\(chipPixels(chipless))px)")
}

@MainActor
@Test
func timingBarSegmentBarShowsOneCellPerRound() throws {
    // 라운드 5 진행 중: 앞 4칸이 완벽(금색)으로 채워지고 나머지는 테두리만.
    let game = tbRunningRound(5)
    #expect(game.roundScores == [100, 100, 100, 100])
    let bitmap = try tbCanvasBitmap(game)
    let band = tbY(244)...tbY(256)
    let filled = tbCountIn(bitmap, x: tbX(24)...tbX(122), y: band, where: tbIsGold)
    let empty = tbCountIn(bitmap, x: tbX(150)...tbX(268), y: band, where: tbIsGold)
    #expect(filled > 800, "끝낸 라운드 칸이 등급 색으로 안 찼다(\(filled)px)")
    #expect(empty < filled / 4, "아직 안 한 칸이 채워져 있다(\(empty)px)")

    // 빗나간 라운드가 섞이면 그 칸만 danger 색이다.
    var mixed = tbStarted()
    tbPlayMissedRound(&mixed)
    tbPlayPerfectRound(&mixed)
    tbAdvance(&mixed, by: 0.2)
    let mixedBitmap = try tbCanvasBitmap(mixed)
    #expect(tbCountIn(mixedBitmap, x: tbX(24)...tbX(46), y: band, where: tbIsDanger) > 200, "0점 칸이 빨갛지 않다")
    #expect(tbCountIn(mixedBitmap, x: tbX(48)...tbX(70), y: band, where: tbIsGold) > 200, "100점 칸이 금색이 아니다")
}

@MainActor
@Test
func timingBarFinishedFrameShowsTheResultCard() throws {
    let game = tbFinishedGame()
    #expect(game.phase == .finished(total: 1000))
    let bitmap = try tbCanvasBitmap(game, bestScore: 700)
    #expect(tbCount(bitmap, where: tbIsCard) > 800, "결과 카드(panelElevated)가 떠야 한다")
    // 신기록(1000 > 700)이면 '신기록!' 이 working 색으로 — 초록 글자 픽셀이 조금은 있다.
    #expect(tbCount(bitmap, where: tbIsWorking) > 0, "신기록 문구가 working 색이어야 한다")
    // 결과 화면에서도 트랙은 남아 있고, 카드가 그 위를 덮지 않는다.
    let cardTop = try #require(tbTopEdge(bitmap, where: tbIsCard))
    #expect(cardTop > tbY(160), "결과 카드가 트랙을 덮는다(\(cardTop)pt)")
}

@MainActor
@Test
func timingBarReduceMotionDropsGhostsAndShake() throws {
    // 동작 줄이기: 잔상·흔들림·맥동이 사라진다. 규칙(마커 위치·점수)은 그대로다.
    let game = tbRunningRound(1)
    let lively = try tbCanvasBitmap(game)
    let calm = try tbCanvasBitmap(game, reduceMotion: true)
    // 마커 왼쪽(지나온 쪽)의 잔상 3개가 사라지므로 그 띠의 흰 픽셀이 줄어든다.
    let ghostBand = (x: tbX(130)...tbX(145), y: tbY(136)...tbY(164))
    let withGhosts = tbCountIn(lively, x: ghostBand.x, y: ghostBand.y, where: tbIsMarker)
    let withoutGhosts = tbCountIn(calm, x: ghostBand.x, y: ghostBand.y, where: tbIsMarker)
    #expect(withGhosts >= withoutGhosts, "동작 줄이기가 잔상을 더 그린다")
    // 마커 자체는 두 경우 모두 그려진다(규칙은 접근성 설정을 안 탄다).
    let markerBand = (x: tbX(140)...tbX(152), y: tbY(133)...tbY(167))
    #expect(tbCountIn(calm, x: markerBand.x, y: markerBand.y, where: tbIsMarker) > 150)
}

@MainActor
@Test
func timingBarShrunkCanvasKeepsAspectAndStillDraws() throws {
    // 캔버스가 논리 비율보다 납작하면 좌우가 레터박스가 된다 — 그 여백엔 게임 요소가 없어야 한다.
    var game = tbStarted()
    tbAdvance(&game, by: 0.35)
    let view = TimingBarGameView(host: .inert(), input: MiniGameInput(), initialGame: game)
    let bitmap = try tbRenderBitmap(view, width: 292, height: 140)
    #expect(bitmap.pixelsHigh == 140 * 2)
    let logical = CGSize(width: MiniGameCanvas.logicalWidth, height: 302)
    let transform = MiniGameCanvas.transform(in: CGSize(width: 292, height: 140), logicalSize: logical)
    #expect(abs(transform.scale - 140 / 302) < 1e-9, "짧은 축(세로)이 배율을 정한다")
    #expect(transform.origin.x > 70, "가로가 남아 좌우로 레터박스가 생긴다")
    // 여백에는 **배경만** 깔린다(하늘은 캔버스 전체를 덮는다 — 그래야 축소된 캔버스가 액자처럼 안 보인다).
    // 그래서 별 몇 점은 걸릴 수 있고, 마커·목표 같은 게임 요소가 들어오면 수백 px 단위로 튄다.
    let leftStrip = tbCountIn(bitmap, x: 0...40, y: 0...140) { r, g, b, a in
        tbIsMarker(r, g, b, a) || tbIsGold(r, g, b, a)
    }
    let markerBand = tbCountIn(bitmap, x: 130...162, y: 55...85, where: tbIsMarker)
    #expect(leftStrip < 20, "레터박스 여백에 게임 요소가 그려지면 비율 유지가 깨진 것(\(leftStrip)px)")
    #expect(markerBand > leftStrip * 5, "마커가 있는 자리(\(markerBand)px)와 여백(\(leftStrip)px)이 구별되지 않는다")
}

// MARK: - (5) 프레임 프로브

@MainActor
@Test
func timingBarReadyViewDoesNotTickTheFrameLoop() throws {
    MiniGameFrameProbe.reset()
    _ = try tbCanvasBitmap(TimingBarGame(seed: 7))
    #expect(MiniGameFrameProbe.frames == 0, "시작 전(paused)엔 프레임 루프가 한 번도 돌지 않아야 한다")
    // running 상태는 ImageRenderer 가 첫 프레임을 그릴 수 있어 단언하지 않는다 — 기록만 남긴다.
    MiniGameFrameProbe.reset()
    _ = try tbCanvasBitmap(tbStarted())
    let runningFrames = MiniGameFrameProbe.frames
    #expect(runningFrames >= 0)
}

@MainActor
@Test
func timingBarPausedGameDoesNotTickEither() throws {
    // 일시정지 계약(v0.2.48): 허브가 판을 얼리면 프레임이 0 이어야 한다 — 정지 중 시간이 흐르면
    // 사용자가 안 보는 사이 라운드가 끝난다.
    MiniGameFrameProbe.reset()
    let view = TimingBarGameView(host: .inert(isPaused: true), input: MiniGameInput(), initialGame: tbStarted())
    _ = try tbRenderBitmap(view)
    #expect(MiniGameFrameProbe.frames == 0, "일시정지 중에 프레임이 돌았다(\(MiniGameFrameProbe.frames))")
}

// MARK: - (6) 소스 계약

private func tbSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/check/MiniGameTimingBar.swift")
}

/// 주석(`//` · `/* */`)을 걷어낸 코드만 남긴다 — 설명문에 든 이름이 단언에 걸리지 않게.
private func tbStrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") { rest = rest[close.upperBound...]; inBlock = false } else { rest = "" }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]; rest = rest[block.upperBound...]; inBlock = true; continue
            }
            if let comment = lineComment { kept += rest[..<comment.lowerBound]; rest = ""; continue }
            kept += rest; rest = ""
        }
        output += kept + "\n"
    }
    return output
}

@Test
func timingBarSourceContract() throws {
    let raw = try String(contentsOf: tbSourceURL(), encoding: .utf8)
    let code = tbStrippingComments(raw)
    #expect(!code.contains("Timer.publish"), "상시 타이머 금지 — 프레임은 TimelineView 로만")
    #expect(!code.contains("DispatchSource"), "디스패치 타이머 금지")
    #expect(!code.contains("store."), "게임 뷰는 스토어를 모른다(host 만 본다)")
    #expect(!code.contains("Double.random") && !code.contains("Int.random") && !code.contains("SystemRandomNumberGenerator"),
            "난수는 MiniGameRandom(시드 주입)만")
    #expect(code.contains("MiniGameRandom"))
    #expect(code.contains("TimelineView(.animation("), "60fps 루프는 TimelineView(.animation) 하나")
    #expect(code.contains("paused:"), "진행 중이 아니면 반드시 paused")
    #expect(code.contains("MiniGameFrameProbe.note()"), "프레임 프로브를 찍어야 헤드리스 검증이 된다")
    #expect(!code.contains(".gesture(") && !code.contains("onTapGesture"), "입력은 허브가 actionCount 로 넘긴다 — 뷰에 제스처 금지")
    #expect(!code.contains("aiToken"), "보라(aiToken)는 토큰 잔디 전용")
    #expect(!code.contains("GeometryReader"), "캔버스 크기는 부모가 준다")
    // 규칙 상수가 스펙 그대로 박혀 있다.
    #expect(code.contains("1.0 / 30.0") || code.contains("1 / 30"))

    // v0.2.48 시각 개편이 지켜야 할 것들.
    #expect(!code.contains("addFilter") && !code.contains("drawLayer"),
            "60Hz 예산: blur 필터·drawLayer 금지(통합 GPU 에서 프레임이 깨진다)")
    // 일시정지 계약을 **두 줄 다** 글자로 못 박는다(플래피 계약과 대칭).
    // `contains("host.isPaused")` 하나로는 tick 가드만 있어도 통과해, paused 식에서 host.isPaused 를
    // 떨어뜨려도 아무 테스트가 빨개지지 않는다 — 그러면 정지 중 60fps 로 CPU 를 태운다(2026-09-10 뮤테이션 실증).
    #expect(code.contains("paused: !game.isPlaying || host.isPaused"),
            "정지 중에 TimelineView 가 안 멈춘다 — 판은 얼어도 프레임 루프는 계속 돈다")
    #expect(code.contains("guard game.isPlaying, !host.isPaused else { lastTick = nil; return }"),
            "정지 중 tick 이 시간을 흘리지 않는다는 가드가 없다")

    // v0.2.50: 프레임 상한은 **화면 주사율에서** 온다. 리터럴을 다시 박으면 60 으로 나눠떨어지지 않는 화면
    // (75Hz·144Hz·90Hz …)에서 네 프레임에 한 장이 두 배로 늘어진다 — 사용자가 "살짝 버벅인다"로 신고한 그것이다.
    #expect(code.contains("MiniGameFrameRate.minimumInterval(forRefreshRate: host.refreshHz)"),
            "프레임 간격을 주사율에서 안 가져온다")
    for hardCoded in ["minimumInterval: 1.0 / 60.0", "minimumInterval: 1.0/60.0", "minimumInterval: 1/60",
                      "minimumInterval: nil"] {
        #expect(!code.contains(hardCoded), "\(hardCoded) — 프레임 상한을 여기 박지 마라(MiniGameFrameRate 가 정한다)")
    }
    // 마커 잔상은 프레임 수가 아니라 **시간**으로 뒤를 돌아본다(주사율마다 꼬리 길이가 달라지지 않게).
    #expect(code.contains("for (age, opacity) in"), "잔상 나이가 시간 단위가 아니다")

    #expect(code.contains("MiniGameBackdrop.draw") && code.contains("terrain: false"),
            "배경은 공용 배경 키트로, 정적 게임이라 능선은 끈다")
    #expect(code.contains("MiniGameStage.forTimingRound"), "무대는 라운드가 정한다")
    #expect(code.contains("reduceMotion"), "동작 줄이기에서 장식을 꺼야 한다")
    // 난이도 상수가 글자 그대로 남아 있다 — 디자인 작업이 값을 못 건드렸다는 소스 수준의 증거.
    #expect(code.contains("max(0.42, 1.10 - 0.075 * Double(round - 1))"), "주기 곡선이 바뀌었다")
    #expect(code.contains("max(0.07, 0.24 - 0.019 * Double(round - 1))"), "목표 폭 곡선이 바뀌었다")
    #expect(code.contains("100 - Int((30 * d).rounded())"), "배점 함수가 바뀌었다")
    #expect(code.contains("roundScores.reduce(0, +)"), "총점은 라운드 점수의 단순 합이다(콤보 보너스 금지)")
}

// MARK: - (7) 프레임 간격이 달라도 같은 판인가 (v0.2.50)
//
// 프레임 상한이 화면 주사율을 따라가면서 같은 판이 60·75·120fps 로 각각 밀린다. 타이밍 바는 **정확도**가
// 곧 점수라 여기가 갈리면 순위표가 화면의 것이 된다. 규칙은 dt 의 합만 보므로 원리적으로는 같아야 하는데,
// 그 '원리'가 코드에 남아 있는지는 여기서만 확인된다.

/// 1/15초를 한 '틱'으로 — 60fps 는 4프레임, 75fps 는 5프레임, 120fps 는 8프레임이라 **세 간격 모두**
/// 틱 경계가 정확히 같은 시각이다(정지 버튼을 누르는 시각이 간격에 따라 갈리지 않는다).
private let tbFpsTickHz = 15

/// 같은 시드로 시작해 tapEveryTick 마다 정지를 누른다. 10라운드를 마칠 때까지.
private func tbFpsPlay(fps: Int, tapEveryTick: Int, seed: UInt64 = tbSeed) -> (total: Int, scores: [Int], ticks: Int) {
    var game = TimingBarGame(seed: seed)
    game.tap()                                     // 시작(ready → running 1)
    let dt = 1.0 / Double(fps)
    let framesPerTick = fps / tbFpsTickHz
    var tick = 0
    while tick < 600 {
        tick += 1
        for _ in 0..<framesPerTick { game.step(dt: dt) }
        if case .finished = game.phase { break }
        if tick % tapEveryTick == 0 { game.tap() }
    }
    return (game.total, game.roundScores, tick)
}

/// 사람처럼 논다: 마커가 목표 중심을 지나는 **그 프레임**에 멈춘다(절대 시각이 아니라 화면을 보고 누른다).
private func tbFpsPlayByEye(fps: Int, seed: UInt64 = tbSeed) -> (total: Int, scores: [Int], seconds: Double) {
    var game = TimingBarGame(seed: seed)
    game.tap()
    let dt = 1.0 / Double(fps)
    var frames = 0
    var previous: Double?
    while frames < fps * 40 {
        frames += 1
        game.step(dt: dt)
        if case .finished = game.phase { break }
        guard case .running(let round, let t) = game.phase else { previous = nil; continue }
        let p = TimingBarGame.markerPosition(t: t, period: TimingBarGame.period(round: round))
        let c = game.target.center
        // 중심을 막 지난 프레임(부호가 뒤집힌 그 순간)에 누른다.
        if let previous, (previous - c) * (p - c) <= 0 { game.tap() }
        previous = p
    }
    return (game.total, game.roundScores, Double(frames) * dt)
}

@Test
func timingBarMarkerRunsAtTheSameSpeedAtEveryFrameRate() {
    // ① **판이 같은 속도로 흐른다.** 정확히 2.000초를 각 간격으로 민 뒤(60→120프레임 · 75→150 · 120→240)
    //    마커가 같은 자리에 있어야 한다. 규칙이 프레임 수로 시간을 세면 여기가 25% 어긋난다.
    var positions: [Int: Double] = [:]
    for fps in [55, 60, 75, 90, 120] {
        var game = TimingBarGame(seed: tbSeed)
        game.tap()
        for _ in 0..<(fps * 2) { game.step(dt: 1.0 / Double(fps)) }
        guard case .running(let round, let t) = game.phase else {
            Issue.record("fps=\(fps): 2초 뒤에 라운드가 안 돌고 있다")
            continue
        }
        #expect(round == 1, "fps=\(fps): 2초 만에 라운드가 넘어갔다")
        positions[fps] = TimingBarGame.markerPosition(t: t, period: TimingBarGame.period(round: round))
    }
    let reference = positions[60] ?? -1
    for (fps, p) in positions.sorted(by: { $0.key < $1.key }) {
        #expect(abs(p - reference) < 1e-9, "fps=\(fps): 2초 뒤 마커가 \(p) 로 60fps(\(reference))와 다르다")
    }

    // ② 라운드 넘어가는 시각(정지 → 결과 0.6초 → 다음 라운드)도 간격을 타지 않는다 — **한 프레임 안**이다.
    //    딱 같을 수는 없다: 0.6 을 dt 로 깎는 카운트다운이 프레임 경계에서 끝나기 때문이다(부동소수 끝자리에
    //    따라 마지막 한 프레임이 붙거나 떨어진다). 사람은 절대 시각이 아니라 **화면을 보고** 누르므로
    //    이 한 프레임은 난이도가 아니다 — 마커와 사람이 같이 밀린다.
    for fps in [55, 60, 75, 90, 120] {
        var game = TimingBarGame(seed: tbSeed)
        game.tap()
        let dt = 1.0 / Double(fps)
        for _ in 0..<fps { game.step(dt: dt) }       // 1초 진행 후
        game.tap()                                   // 정지 → 결과 표시
        var frames = 0
        while frames < fps * 3 {
            frames += 1
            game.step(dt: dt)
            if case .running(let round, _) = game.phase, round == 2 { break }
        }
        let seconds = Double(frames) * dt
        #expect(abs(seconds - TimingBarGame.resultHold) <= dt + 1e-9,
                "fps=\(fps): 다음 라운드가 \(seconds)초 만에 왔다(결과 표시는 \(TimingBarGame.resultHold)초)")
    }
}

@Test
func timingBarStaysPlayableAtEveryFrameRate() {
    // 사람처럼(화면을 보고 중심을 지나는 프레임에 정지) 한 판을 끝까지 논다. 어느 주사율에서도 10라운드가
    // 돌고 점수가 무너지지 않아야 한다.
    //
    // ★ 정확히 같은 점수는 **나오지 않고, 나올 수도 없다**: 멈출 수 있는 자리의 해상도가 곧 프레임 간격이다
    //   (마커 위치는 프레임에서 누적한 t 의 함수다). 60fps 는 초당 60번, 75fps 는 75번 멈춰 볼 수 있다 —
    //   이 로봇처럼 0ms 반응이면 그 차이가 총점에 그대로 나온다(실측 55→810 · 60→921 · 75→911 · 120→942).
    //   사람의 타이밍 흔들림(수십 ms)이 프레임 간격 차이(60↔75 는 3.3ms)보다 훨씬 크므로 실사용에서는 묻힌다.
    //   이것은 이번 변경이 만든 성질이 아니다 — 바꾸기 전에도 75Hz 화면의 프레임은 대부분 13.33ms 였다.
    var totals: [Int: Int] = [:]
    for fps in [55, 60, 75, 90, 120] {
        let result = tbFpsPlayByEye(fps: fps)
        totals[fps] = result.total
        #expect(result.scores.count == TimingBarGame.roundCount, "fps=\(fps): 10라운드를 못 채웠다")
        #expect(result.total >= 700, "fps=\(fps): 총점 \(result.total) — 이 주사율에서 판이 무너졌다")
        #expect(result.seconds < 12, "fps=\(fps): 한 판이 \(result.seconds)초 걸렸다 — 판이 느려졌다")
    }
    print("[tb-fps] 주사율별 로봇 총점: " + totals.sorted { $0.key < $1.key }.map { "\($0.key)fps=\($0.value)" }.joined(separator: " "))
}
