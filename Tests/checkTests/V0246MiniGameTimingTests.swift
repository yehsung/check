import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.46 미니게임 — 타이밍 바. 규칙(순수 값 타입)·상태 기계·dt 클램프·렌더·프레임 프로브·소스 계약.
// 시드를 고정하면 판이 결정적이라(MiniGameRandom 만 쓴다) 목표 중심을 읽어 "정중앙에서 멈추는 시각"을 역산할 수 있다.

// MARK: - 픽스처

private let tbSeed: UInt64 = 0xC0FFEE

/// 시작된 판(running 1, t = 0).
private func tbStarted(seed: UInt64 = tbSeed) -> TimingBarGame {
    var game = TimingBarGame(seed: seed)
    game.tap()
    return game
}

/// 마커가 목표 중심에 오는 시각(첫 왕복의 오르막 구간, p = 2t/T → t = c·T/2)까지 1/30 걸음으로 전진한다.
private func tbAdvanceToTargetCenter(_ game: inout TimingBarGame) {
    guard case .running(let round, let t0) = game.phase else { return }
    let period = TimingBarGame.period(round: round)
    let goal = game.target.center * period / 2
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

private func tbFinishedGame(seed: UInt64 = tbSeed) -> TimingBarGame {
    var game = tbStarted(seed: seed)
    for _ in 0..<TimingBarGame.roundCount { tbPlayPerfectRound(&game) }
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
private func tbRenderBitmap(_ view: some View, width: CGFloat = 292, height: CGFloat = 200) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(CheckTheme.panel).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
        throw TimingRenderError.failed
    }
    return bitmap
}

private func tbSavePNG(_ bitmap: NSBitmapImageRep, _ name: String) {
    let dir = "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/agent-tune2"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
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

/// accent 파랑 계열(테두리 (84,171,255) · .35 채움 (≈52,84,121)): 파랑이 빨강보다 40 이상 앞선다.
private func tbIsAccentish(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool { a > 200 && b >= 110 && b - r >= 40 && b > g }
/// working 초록 (89,224,161): 초록이 빨강보다 60 이상 앞서고 파랑보다 크다.
private func tbIsWorking(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool { a > 200 && g >= 180 && g - r >= 60 && g > b }
/// danger 빨강 (255,115,117).
private func tbIsDanger(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool { a > 200 && r >= 200 && g < 150 && b < 150 }
/// 오버레이 카드 바탕 panelElevated (54,56,74) — 캔버스 바닥(fieldFill 위 panel ≈ (34,37,49))보다 밝은 청회색.
private func tbIsCard(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool { a > 200 && abs(r - 54) <= 3 && abs(g - 56) <= 3 && abs(b - 74) <= 3 }

@MainActor
@Test
func timingBarLastRoundDrawsTheNarrowestTarget() throws {
    // r10 은 폭 0.07(트랙의 7%) — 난이도 상향의 끝이 눈에 어떻게 보이는지 남긴다. 창 캔버스 크기로 찍는다.
    var game = tbStarted()
    for _ in 0..<(TimingBarGame.roundCount - 1) { tbPlayPerfectRound(&game) }
    guard case .running(let round, _) = game.phase else {
        Issue.record("r10 이 아니다: \(game.phase)")
        return
    }
    #expect(round == 10)
    #expect(abs(game.target.width - 0.07) < 1e-9)
    tbAdvance(&game, by: TimingBarGame.period(round: 10) / 4)
    let view = TimingBarGameView(host: .inert(bestScore: 900), input: MiniGameInput(), initialGame: game)
    let bitmap = try tbRenderBitmap(view, width: 344, height: 356)
    tbSavePNG(bitmap, "timing-round10.png")
    #expect(tbCount(bitmap, where: tbIsAccentish) > 100, "좁아도 목표 구간은 보여야 한다")
    #expect(tbCount(bitmap, where: tbIsWorking) > 60, "마커(working)")
}

@MainActor
@Test
func timingBarRunningFrameShowsTargetAndMarker() throws {
    var game = tbStarted()
    // 마커를 트랙 중간(p = 0.5, t = T/4)에 둔다 — 목표와 겹쳐도 색 픽셀은 둘 다 남는다.
    // 주기는 라운드 1 값을 그때그때 읽는다(난이도를 조정하면 상수가 바뀐다 — 0.35 로 박아 두면 그때 빨개진다).
    tbAdvance(&game, by: TimingBarGame.period(round: 1) / 4)
    #expect(abs(game.markerPosition - 0.5) < 1e-9)
    let view = TimingBarGameView(host: .inert(bestScore: 640), input: MiniGameInput(), initialGame: game)
    let bitmap = try tbRenderBitmap(view)
    tbSavePNG(bitmap, "timing-running.png")
    #expect(bitmap.pixelsWide == 292 * 2 && bitmap.pixelsHigh == 200 * 2)
    #expect(tbCount(bitmap, where: tbIsAccentish) > 200, "목표 구간(accent)이 그려져야 한다")
    #expect(tbCount(bitmap, where: tbIsWorking) > 60, "마커(working)가 그려져야 한다")
    #expect(tbCount(bitmap, where: tbIsCard) < 50, "running 중엔 오버레이 카드가 없다")
}

@MainActor
@Test
func timingBarReadyFrameShowsTheStartCard() throws {
    let view = TimingBarGameView(host: .inert(), input: MiniGameInput(), initialGame: TimingBarGame(seed: tbSeed))
    let bitmap = try tbRenderBitmap(view)
    tbSavePNG(bitmap, "timing-ready.png")
    #expect(tbCount(bitmap, where: tbIsCard) > 800, "시작 안내 카드(panelElevated)가 캔버스 위에 떠야 한다")
    #expect(tbCount(bitmap, where: tbIsWorking) == 0, "시작 전엔 마커가 없다")
}

@MainActor
@Test
func timingBarFinishedFrameShowsTheResultCard() throws {
    let game = tbFinishedGame()
    #expect(game.phase == .finished(total: 1000))
    let view = TimingBarGameView(host: .inert(bestScore: 700), input: MiniGameInput(), initialGame: game)
    let bitmap = try tbRenderBitmap(view)
    tbSavePNG(bitmap, "timing-finished.png")
    #expect(tbCount(bitmap, where: tbIsCard) > 800, "결과 카드(panelElevated)가 떠야 한다")
    // 신기록(1000 > 700)이면 '신기록!' 이 working 색으로 — 초록 글자 픽셀이 조금은 있다.
    #expect(tbCount(bitmap, where: tbIsWorking) > 0, "신기록 문구가 working 색이어야 한다")
}

@MainActor
@Test
func timingBarMissedRoundResultPaintsTheMarkerRed() throws {
    var game = tbStarted()
    game.tap()   // t=0, p=0 → 목표 밖(중심 ≥ 0.2) → danger
    #expect(game.lastHit == false)
    let bitmap = try tbRenderBitmap(TimingBarGameView(host: .inert(), input: MiniGameInput(), initialGame: game))
    #expect(tbCount(bitmap, where: tbIsDanger) > 40, "빗나간 정지는 마커가 danger 색")
}

@MainActor
@Test
func timingBarShrunkCanvasKeepsAspectAndStillDraws() throws {
    var game = tbStarted()
    tbAdvance(&game, by: 0.35)
    let view = TimingBarGameView(host: .inert(), input: MiniGameInput(), initialGame: game)
    let bitmap = try tbRenderBitmap(view, height: 140)
    #expect(bitmap.pixelsHigh == 140 * 2)
    #expect(tbCount(bitmap, where: tbIsAccentish) > 100)
    #expect(tbCount(bitmap, where: tbIsWorking) > 30)
    // 비율 유지: 배율 0.7 이라 트랙이 가로 292 를 다 쓰지 않는다 — 왼쪽 40pt 띠(원점 43.8 앞)엔 목표·마커 색이 없다.
    #expect(MiniGameCanvas.transform(in: CGSize(width: 292, height: 140)).scale == 0.7)
    let leftStrip = tbCountIn(bitmap, x: 0...40, y: 0...140) { r, g, b, a in tbIsAccentish(r, g, b, a) || tbIsWorking(r, g, b, a) }
    #expect(leftStrip == 0, "축소된 캔버스의 왼쪽 여백에 게임 요소가 그려지면 비율 유지가 깨진 것")
}

// MARK: - (5) 프레임 프로브

@MainActor
@Test
func timingBarReadyViewDoesNotTickTheFrameLoop() throws {
    MiniGameFrameProbe.reset()
    _ = try tbRenderBitmap(TimingBarGameView(host: .inert(), input: MiniGameInput(), initialGame: TimingBarGame(seed: 7)))
    #expect(MiniGameFrameProbe.frames == 0, "시작 전(paused)엔 프레임 루프가 한 번도 돌지 않아야 한다")
    // running 상태는 ImageRenderer 가 첫 프레임을 그릴 수 있어 단언하지 않는다 — 기록만 남긴다.
    MiniGameFrameProbe.reset()
    _ = try tbRenderBitmap(TimingBarGameView(host: .inert(), input: MiniGameInput(), initialGame: tbStarted()))
    let runningFrames = MiniGameFrameProbe.frames
    #expect(runningFrames >= 0)
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
}
