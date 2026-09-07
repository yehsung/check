import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.2.46 플래피 아잉 — 규칙(순수)·상태 전이·dt 클램프·렌더·프레임 프로브·소스 계약.
// 규칙 상수는 spec-flappy.md 의 숫자를 그대로 고정한다(중력 1500 · 점프 −430 · 낙하 620 · 기둥 44/150 · 틈 74→62).

private let W = FlappyGame.width      // 292
private let H = FlappyGame.height     // 200
private let birdX = FlappyGame.birdX  // 81.76

private func pipe(x: CGFloat, centerY: CGFloat = H / 2, gap: CGFloat = 74) -> FlappyGame.Pipe {
    FlappyGame.Pipe(x: x, centerY: centerY, gap: gap)
}

private func running(bird: FlappyGame.Bird, pipes: [FlappyGame.Pipe], score: Int = 0, seed: UInt64 = 1) -> FlappyGame {
    FlappyGame(seed: seed, bird: bird, pipes: pipes, score: score, phase: .running)
}

private func isOver(_ phase: FlappyGame.Phase) -> Bool {
    if case .over = phase { return true }
    return false
}

// MARK: - (1) 순수 규칙

@Test
func gapShrinksTwoEveryFivePointsDownToSixtyTwo() {
    #expect(FlappyGame.gap(forScore: 0) == 74)
    #expect(FlappyGame.gap(forScore: 4) == 74)
    #expect(FlappyGame.gap(forScore: 5) == 72)
    #expect(FlappyGame.gap(forScore: 30) == 62)
    #expect(FlappyGame.gap(forScore: 100) == 62)
}

@Test
func speedGrowsThreePerPointUpToOneNinety() {
    #expect(FlappyGame.speed(forScore: 0) == 120)
    #expect(FlappyGame.speed(forScore: 23) == 189)
    #expect(FlappyGame.speed(forScore: 40) == 190)
    #expect(FlappyGame.speed(forScore: 500) == 190)
}

@Test
func gravityIntegratesAndClampsFallSpeed() {
    // 점프 직후 −430 에서 1초 자유낙하: −430 + 1500 = 1070 → 620 클램프.
    #expect(FlappyGame.nextVelocity(FlappyGame.flapVelocity, dt: 1.0) == 620)
    #expect(abs(FlappyGame.nextVelocity(0, dt: 1.0 / 30.0) - 50) < 1e-9)

    // 실제 판: 위쪽에서 떨어뜨리면 13 프레임(0.433초) 뒤 속도가 620 에 닿고 아직 바닥엔 안 닿는다.
    var game = running(bird: .init(x: birdX, y: 20, vy: 0), pipes: [pipe(x: 600)])
    for _ in 0..<13 { game.step(dt: 1.0 / 30.0) }
    #expect(game.bird.vy == 620)
    #expect(game.phase == .running)
    #expect(game.hitbox.maxY < H - FlappyGame.floorBand)
}

@Test
func flapSetsUpwardVelocityAndCeilingStopsTheBirdWithoutKilling() {
    var game = running(bird: .init(x: birdX, y: 100, vy: 0), pipes: [pipe(x: 600)])
    game.flap()
    #expect(game.bird.vy == -430)

    // 천장: 히트박스 윗변이 0 에 붙고 속도는 0, 충돌은 아니다.
    var top = running(bird: .init(x: birdX, y: FlappyGame.hitboxSize / 2, vy: -430), pipes: [pipe(x: 600)])
    top.step(dt: 1.0 / 60.0)
    #expect(top.hitbox.minY == 0)
    #expect(top.bird.vy == 0)
    #expect(top.phase == .running)
}

@Test
func seededPipesStayInsideTheVerticalMargins() {
    var rng = MiniGameRandom(seed: 42)
    for _ in 0..<100 {
        let p = FlappyGame.makePipe(x: 0, score: 0, rng: &rng)
        #expect(p.gap == 74)
        #expect(p.centerY >= 74 / 2 + 24 && p.centerY <= H - 74 / 2 - 24 - FlappyGame.floorBand)
    }
    for _ in 0..<100 {
        let p = FlappyGame.makePipe(x: 0, score: 30, rng: &rng)
        #expect(p.gap == 62)
        #expect(p.centerY >= 62 / 2 + 24 && p.centerY <= H - 62 / 2 - 24 - FlappyGame.floorBand)
    }
    // 같은 시드는 같은 기둥.
    var a = MiniGameRandom(seed: 9), b = MiniGameRandom(seed: 9)
    #expect(FlappyGame.makePipe(x: 0, score: 0, rng: &a) == FlappyGame.makePipe(x: 0, score: 0, rng: &b))
}

// MARK: - (2) 충돌 · 점수

@Test
func passingThroughTheGapScoresOnceAndKeepsRunning() {
    // 틈을 크게(180) 두고 바로 앞에 기둥. 속도가 붙으면 점프해 틈 안에 머문다.
    var game = running(bird: .init(x: birdX, y: H / 2, vy: 0),
                       pipes: [pipe(x: birdX + 5, centerY: H / 2, gap: 180), pipe(x: 400, gap: 180), pipe(x: 550, gap: 180)])
    for _ in 0..<60 {
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
func touchingTheFloorBandEndsTheRound() {
    var game = running(bird: .init(x: birdX, y: 185, vy: 0), pipes: [pipe(x: 600)])
    game.step(dt: 1.0 / 60.0)
    #expect(isOver(game.phase))
}

@Test
func overHoldExpiresIntoResultAndIgnoresFlapsMeanwhile() {
    var game = running(bird: .init(x: birdX, y: 185, vy: 0), pipes: [pipe(x: 600)], score: 7)
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
    let almost = FlappyGame.Pipe(x: birdX - FlappyGame.pipeWidth + 0.5, centerY: H / 2, gap: 180)
    var game = running(bird: .init(x: birdX, y: H / 2, vy: 0), pipes: [almost, pipe(x: 400, gap: 180), pipe(x: 550, gap: 180)],
                       score: FlappyGame.maxScore - 1)
    game.step(dt: 1.0 / 60.0)
    #expect(game.score == 999)
    #expect(game.phase == .result)
}

@Test
func collisionIsAxisAlignedBoxAgainstBothPipeHalves() {
    let p = pipe(x: 100, centerY: 100, gap: 74)   // 위 0..63, 아래 137..200
    let inside = CGRect(x: 100, y: 89, width: 22, height: 22)     // 틈 안(89..111)
    let top = CGRect(x: 100, y: 50, width: 22, height: 22)        // 위 기둥과 겹침
    let bottom = CGRect(x: 100, y: 130, width: 22, height: 22)    // 아래 기둥과 겹침
    let beside = CGRect(x: 30, y: 50, width: 22, height: 22)      // 기둥 왼쪽 밖
    #expect(!FlappyGame.collides(bird: inside, pipe: p, height: H))
    #expect(FlappyGame.collides(bird: top, pipe: p, height: H))
    #expect(FlappyGame.collides(bird: bottom, pipe: p, height: H))
    #expect(!FlappyGame.collides(bird: beside, pipe: p, height: H))
}

@Test
func pipesRecycleBehindTheLastOneWithTheCurrentGap() {
    // 첫 기둥이 왼쪽으로 완전히 나가면(x + 44 < 0) 버리고 마지막 기둥 뒤 150 에 새 기둥을 단다. 틈은 그때 점수 기준.
    var game = running(bird: .init(x: birdX, y: H / 2, vy: 0),
                       pipes: [pipe(x: 0, gap: 180), pipe(x: 150, gap: 180), pipe(x: 300, gap: 180)], seed: 5)
    var recycled = false
    for _ in 0..<60 {
        if game.bird.vy > 100 { game.flap() }
        game.step(dt: 1.0 / 60.0)
        if game.pipes[0].gap != 180 || game.pipes.last?.x ?? 0 > 300 { recycled = true; break }
    }
    #expect(recycled, "1초 안에 첫 기둥(x 0)이 −44 를 지나 재활용된다")
    #expect(game.phase == .running)
    #expect(game.pipes.count == FlappyGame.pipeCount, "기둥은 언제나 \(FlappyGame.pipeCount)개")
    let xs = game.pipes.map(\.x)
    for i in 1..<xs.count { #expect(abs((xs[i] - xs[i - 1]) - FlappyGame.pipeSpacing) < 1e-6, "간격 150 유지") }
    let fresh = try! #require(game.pipes.last)
    #expect(fresh.gap == FlappyGame.gap(forScore: game.score))
    #expect(!fresh.passed)
}

// MARK: - (3) 상태 전이

@Test
func readyFlapStartsARoundWithThreePipesAndAJump() {
    var game = FlappyGame(seed: 7)
    #expect(game.phase == .ready)
    #expect(!game.isPlaying)
    #expect(game.pipes.isEmpty)

    game.flap()
    #expect(game.phase == .running)
    #expect(game.isPlaying)
    #expect(game.bird.vy == -430)
    #expect(game.bird.x == birdX && game.bird.y == H / 2)
    #expect(game.pipes.count == 3)
    #expect(game.pipes[0].x == W + 40)
    #expect(game.pipes[1].x == W + 40 + 150)
    #expect(game.pipes[2].x == W + 40 + 300)
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
    #expect(game.bird.y == H / 2 && game.bird.vy == -430)
    #expect(game.pipes.count == 3 && game.pipes[0].x == W + 40)
    #expect(game.pipes.allSatisfy { !$0.passed })
    #expect(game.pipes != oldPipes || oldPipes.isEmpty)
}

// MARK: - (4) dt 클램프

@Test
func hugeDeltaTimeIsClampedToOneThirtieth() {
    var game = running(bird: .init(x: birdX, y: 100, vy: 0), pipes: [pipe(x: 600)])
    game.step(dt: 5)
    #expect(abs(game.bird.vy - 50) < 1e-9, "1500 × 1/30 = 50 — 5초를 한 번에 밀지 않는다")
    #expect(abs(game.bird.y - (100 + 50.0 / 30.0)) < 1e-6)
    #expect(abs(game.pipes[0].x - (600 - 120.0 / 30.0)) < 1e-6)
    #expect(game.phase == .running)

    // 음수 dt 는 0 으로.
    var still = running(bird: .init(x: birdX, y: 100, vy: 0), pipes: [pipe(x: 600)])
    still.step(dt: -1)
    #expect(still.bird.y == 100 && still.pipes[0].x == 600)
}

// MARK: - (5)(6) 렌더 · 프레임 프로브

private enum FlappyRenderError: Error { case failed }

@MainActor
private func renderBitmap(_ view: some View, width: CGFloat = W, height: CGFloat = H) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(CheckTheme.panel))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
        throw FlappyRenderError.failed
    }
    return bitmap
}

private func savePNG(_ bitmap: NSBitmapImageRep, _ name: String) {
    let dir = "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/agent-flappy"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
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

/// 카드 바탕 panelElevated (54,56,74) — 바닥(panel + fieldFill ≈ (35,37,49))·기둥·스프라이트와 겹치지 않는 서명.
private func isCardPixel(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    a >= 250 && abs(r - 54) <= 8 && abs(g - 56) <= 8 && abs(b - 74) <= 8
}
/// 기둥: accent(84,171,255) .55 → 약 (62,111,162), 테두리는 accent 그대로. 파랑이 압도하고 초록이 빨강보다 크다
/// (보라 스프라이트는 g < r 이라 걸리지 않는다).
private func isPipePixel(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    a >= 250 && b >= 130 && b - r >= 60 && g - r >= 20
}
/// 캔버스 바닥 색과 다른 픽셀(스프라이트 존재 판정용).
private func isNotFloorPixel(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    abs(r - 35) > 30 || abs(g - 37) > 30 || abs(b - 49) > 30
}
private func isInkPixel(_ r: Int, _ g: Int, _ b: Int, _ a: Int) -> Bool {
    a >= 250 && min(r, min(g, b)) >= 215
}

@MainActor
private func view(_ game: FlappyGame, best: Int = 0) -> FlappyGameView {
    FlappyGameView(host: .inert(bestScore: best), input: MiniGameInput(), initialGame: game)
}

@Suite(.serialized)
@MainActor
struct V0246MiniGameFlappyRenderTests {
    @Test
    func runningFrameShowsPipesAndTheSpriteAndNoCard() throws {
        let game = running(bird: .init(x: birdX, y: 100, vy: 0),
                           pipes: [pipe(x: 160, centerY: 100, gap: 74), pipe(x: 310), pipe(x: 460)], score: 3)
        let bitmap = try renderBitmap(view(game))
        savePNG(bitmap, "flappy-running.png")
        #expect(bitmap.pixelsWide == Int(W) * 2 && bitmap.pixelsHigh == Int(H) * 2)

        // 기둥(160..204, 위 0..63 · 아래 137..192)에 파란 픽셀.
        #expect(count(bitmap, x: 160...204, y: 0...60, where: isPipePixel) > 1500)
        #expect(count(bitmap, x: 160...204, y: 140...190, where: isPipePixel) > 1500)
        // 틈(100±37)엔 기둥이 없다.
        #expect(count(bitmap, x: 160...204, y: 70...130, where: isPipePixel) == 0)
        // 히트박스 자리(81.76±11, 100±11)에 바닥과 다른 픽셀 — 스프라이트가 그려졌다.
        let box = game.hitbox
        #expect(count(bitmap, x: box.minX...box.maxX, y: box.minY...box.maxY, where: isNotFloorPixel) > 300)
        // 진행 중엔 카드가 없고, 상단 점수(흰 글씨)는 있다.
        #expect(count(bitmap, x: 0...W, y: 0...H, where: isCardPixel) < 100, "카드(수천 픽셀)는 없다 — 스프라이트 가장자리 안티앨리어싱 몇십 픽셀은 허용")
        #expect(count(bitmap, x: (W / 2 - 20)...(W / 2 + 20), y: 8...36, where: isInkPixel) > 30)
        // 바닥띠(192..200)는 어둡다(trackFill).
        #expect(count(bitmap, x: 0...W, y: 193...199, where: isPipePixel) == 0)
    }

    @Test
    func readyStateShowsTheStartCardAndNoPipes() throws {
        let bitmap = try renderBitmap(view(FlappyGame(seed: 1)))
        savePNG(bitmap, "flappy-ready.png")
        #expect(count(bitmap, x: 0...W, y: 0...H, where: isCardPixel) > 800)
        #expect(count(bitmap, x: 0...W, y: 0...H, where: isInkPixel) > 60)
        #expect(count(bitmap, x: 0...W, y: 0...H, where: isPipePixel) == 0)
    }

    @Test
    func resultStateShowsTheScoreCard() throws {
        let game = FlappyGame(seed: 1, bird: .init(x: birdX, y: 150, vy: 0), pipes: [pipe(x: 160)], score: 12, phase: .result)
        let bitmap = try renderBitmap(view(game, best: 20))
        savePNG(bitmap, "flappy-result.png")
        #expect(count(bitmap, x: 0...W, y: 0...H, where: isCardPixel) > 800)
        #expect(count(bitmap, x: 0...W, y: 0...H, where: isInkPixel) > 100)
        // 카드는 신기록이 아니면 working(초록) 글씨가 없다.
        let greenBefore = count(bitmap, x: 0...W, y: 0...H) { r, g, b, a in a >= 250 && g >= 200 && r <= 120 && b <= 190 }
        let record = try renderBitmap(view(game, best: 5))
        let greenAfter = count(record, x: 0...W, y: 0...H) { r, g, b, a in a >= 250 && g >= 200 && r <= 120 && b <= 190 }
        #expect(greenAfter > greenBefore, "신기록이면 '신기록!' 초록 글씨가 생긴다")
    }

    @Test
    func readyStateDoesNotAdvanceAnyFrame() throws {
        MiniGameFrameProbe.reset()
        _ = try renderBitmap(view(FlappyGame(seed: 1)))
        #expect(MiniGameFrameProbe.frames == 0, "ready 는 paused — 프레임 루프가 0회여야 유휴 0% 가 지켜진다")
    }

    @Test
    func smallerCanvasKeepsTheAspectAndStillDrawsEverything() throws {
        // 높이 예산이 줄어 140 이 되어도(배율 0.7) 규칙 좌표 그대로 그린다.
        let game = running(bird: .init(x: birdX, y: 100, vy: 0),
                           pipes: [pipe(x: 160, centerY: 100, gap: 74), pipe(x: 310), pipe(x: 460)], score: 3)
        let bitmap = try renderBitmap(view(game), height: MiniGameCanvas.minimumHeight)
        let t = MiniGameCanvas.transform(in: CGSize(width: W, height: MiniGameCanvas.minimumHeight))
        #expect(abs(t.scale - 0.7) < 1e-9)
        let px = t.origin.x + 160 * t.scale, pw = 44 * t.scale
        #expect(count(bitmap, x: px...(px + pw), y: 0...(60 * t.scale), where: isPipePixel) > 500)
        let box = game.hitbox
        let bx = t.origin.x + box.minX * t.scale, by = t.origin.y + box.minY * t.scale
        #expect(count(bitmap, x: bx...(bx + box.width * t.scale), y: by...(by + box.height * t.scale), where: isNotFloorPixel) > 100)
    }
}

// MARK: - (7) 소스 계약

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
    for forbidden in ["SCNView", "renderSnapshotPNG", "Timer.publish", "store.", "Double.random", "Int.random", ".size =", "lockFocus", "DispatchSource", "aiToken"] {
        #expect(!code.contains(forbidden), "\(forbidden) 은 게임 잎 뷰에 있으면 안 된다")
    }
    #expect(code.contains("TimelineView(.animation("))
    #expect(code.contains("paused:"))
    #expect(code.contains("CheckMascotAssets.image(for:"))
    #expect(code.contains("MiniGameRandom"))
    #expect(code.contains("MiniGameFrameProbe.note()"))
    #expect(code.contains("MiniGameCanvas.transform(in:"))
    // 입력은 허브가 넘긴다 — 잎 뷰에 제스처가 없다.
    #expect(!code.contains(".gesture(") && !code.contains("onTapGesture"))
}
