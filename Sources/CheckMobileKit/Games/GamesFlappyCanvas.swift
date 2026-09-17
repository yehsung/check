#if os(iOS)
import CheckCore
import SwiftUI

// 플래피 아잉 한 프레임의 그림 — 맥 `MiniGameFlappy.swift` 의 v0.2.51 그림을 옮겼다. **남긴 넷과 기둥만** 그린다:
// ① 오른쪽을 보는 옆모습 ② 점프 때 발밑 흰 파편 ③ 기둥을 지날 때 "+1" ④ 뒤 배경(점수 무대) + v0.2.50 기둥.
// 맥 파일 머리의 "다시 넣지 마라" 목록(잔상·스쿼시·플래시·링·플레어·배너…)은 폰에도 그대로 적용된다 — 사용자가 보고 물린 것이다.

private enum FlappyFX {
    static let flapSpark: TimeInterval = 0.35
    static let scorePopHold: TimeInterval = 0.60
    static let tiltRange: ClosedRange<Double> = -20...25
    static let lip: CGFloat = 10
    static let scoreY: CGFloat = 26
    static let scorePopBack: CGFloat = FlappyGame.pipeWidth * 0.75
    static let flapSparkRadius: CGFloat = 44
    static let flapSparkDot: CGFloat = 2.0
    static let flapSparkAngles: ClosedRange<Double> = (0.28 * .pi)...(1.22 * .pi)
    static let flapSparkColor = Color.white.opacity(0.82)
}

struct GamesFlappyCanvas: View {
    let game: FlappyGame
    let bestScore: Int
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                draw(&context, size: size)
            }
            spriteAndScore
            scorePop
            if !reduceMotion, game.flashRemaining > 0 {
                CheckTheme.danger
                    .opacity(0.25 * game.flashRemaining / FlappyGame.flashDuration)
                    .allowsHitTesting(false)
            }
            overlayCard
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let t = MiniGameProjection(container: size, logicalSize: FlappyGame.logicalSize)
        let full = CGRect(origin: .zero, size: size)
        let stage = game.stage
        MiniGameBackdrop.draw(into: &context, rect: full, stage: stage, scroll: game.scrolled,
                              terrain: true, reduceMotion: reduceMotion)
        // 기둥 — 맥 v0.2.50 그리기 그대로(세로 그라디언트는 캔버스 전체 기준 · 입구 립 · 립 경계선 · 1.5pt 외곽선).
        let pipeShading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [stage.structureDeep, stage.structureDeepLit]),
            startPoint: CGPoint(x: full.midX, y: full.minY),
            endPoint: CGPoint(x: full.midX, y: full.maxY)
        )
        for pipe in game.pipes {
            let halves: [(rect: CGRect, isTop: Bool)] = [
                (pipe.topRect(at: game.elapsed), true),
                (pipe.bottomRect(at: game.elapsed, height: FlappyGame.height), false)
            ]
            for half in halves where half.rect.height > 0 {
                let path = Path(t.rect(half.rect))
                context.fill(path, with: pipeShading)
                let lipHeight = min(FlappyFX.lip, half.rect.height)
                let lipY = half.isTop ? half.rect.maxY - lipHeight : half.rect.minY
                context.fill(Path(t.rect(CGRect(x: half.rect.minX, y: lipY, width: half.rect.width, height: lipHeight))),
                             with: .color(stage.structureEdge.opacity(0.55)))
                if half.rect.height > FlappyFX.lip {
                    let edgeY = half.isTop ? lipY : lipY + lipHeight - 1
                    context.fill(Path(t.rect(CGRect(x: half.rect.minX, y: edgeY, width: half.rect.width, height: 1))),
                                 with: .color(stage.structureEdge.opacity(0.95)))
                }
                context.stroke(path, with: .color(stage.structureEdge.opacity(0.92)), lineWidth: 1.5)
            }
        }
        if !reduceMotion, game.phase == .running, let at = game.lastFlapAt {
            let foot = t.point(game.bird.x + FlappyGame.spriteSize * 0.08, game.bird.y + FlappyGame.spriteSize * 0.52)
            MiniGameEffects.sparks(into: &context, center: foot,
                                   progress: (game.elapsed - at) / FlappyFX.flapSpark,
                                   count: 10, maxRadius: FlappyFX.flapSparkRadius * t.scale,
                                   color: FlappyFX.flapSparkColor, seed: UInt64(game.flapCount),
                                   dotRadius: FlappyFX.flapSparkDot * t.scale,
                                   angles: FlappyFX.flapSparkAngles)
        }
    }

    private static let scorePopX = FlappyGame.birdX - FlappyFX.scorePopBack

    private var spriteAndScore: some View {
        GeometryReader { geo in
            let t = MiniGameCanvas.transform(in: geo.size, logicalSize: FlappyGame.logicalSize)
            let side = FlappyGame.spriteSize * t.scale
            mascot
                .frame(width: side, height: side)
                .rotationEffect(.degrees(spriteAngle))
                .position(x: t.origin.x + game.bird.x * t.scale, y: t.origin.y + game.bird.y * t.scale)
            if showsTopScore {
                Text("\(game.score)")
                    .font(.system(size: 26 * t.scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .shadow(color: .black.opacity(0.40), radius: 7)
                    .position(x: t.origin.x + FlappyGame.width / 2 * t.scale, y: t.origin.y + FlappyFX.scoreY * t.scale)
            }
        }
        .allowsHitTesting(false)
    }

    /// 아잉 고정(맥과 같다). 게임오버면 시무룩 정면.
    @ViewBuilder
    private var mascot: some View {
        if let image = game.isGameOver ? GamesMascotArt.negative : GamesMascotArt.side {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Circle().fill(CheckTheme.working)
        }
    }

    @ViewBuilder
    private var scorePop: some View {
        if let at = game.lastScoreAt, let center = game.lastScorePipeCenter,
           game.elapsed - at < FlappyFX.scorePopHold, showsTopScore {
            GeometryReader { geo in
                let t = MiniGameCanvas.transform(in: geo.size, logicalSize: FlappyGame.logicalSize)
                GamesScorePop(text: "+1", tint: game.stage.glow, reduceMotion: reduceMotion, scale: t.scale)
                    .id(game.score)
                    .position(x: t.origin.x + Self.scorePopX * t.scale, y: t.origin.y + center * t.scale)
            }
            .allowsHitTesting(false)
        }
    }

    private var showsTopScore: Bool {
        switch game.phase {
        case .running, .over: true
        case .ready, .result: false
        }
    }

    private var spriteAngle: Double {
        guard !reduceMotion else { return 0 }
        let raw = Double(game.bird.vy / FlappyGame.maxFallSpeed) * FlappyFX.tiltRange.upperBound
        return min(FlappyFX.tiltRange.upperBound, max(FlappyFX.tiltRange.lowerBound, raw))
    }

    @ViewBuilder
    private var overlayCard: some View {
        GeometryReader { geo in
            let scale = MiniGameCanvas.transform(in: geo.size, logicalSize: FlappyGame.logicalSize).scale
            Group {
                switch game.phase {
                case .ready:
                    GamesOverlayCard(
                        title: MiniGameKind.flappy.title,
                        subtitle: GamesMiniGameText.howToPlay(.flappy),
                        action: GamesMiniGameText.startAction,
                        icon: MiniGameKind.flappy.icon,
                        tint: game.stage.glow, scale: scale)
                case .result:
                    GamesOverlayCard(
                        title: "\(game.score)점", titleIsScore: true,
                        subtitle: game.score > bestScore ? "신기록!" : "최고 \(bestScore)",
                        subtitleIsHighlighted: game.score > bestScore,
                        action: GamesMiniGameText.againAction,
                        icon: MiniGameKind.flappy.icon,
                        tint: game.stage.glow, scale: scale)
                case .running, .over:
                    EmptyView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}
#endif
