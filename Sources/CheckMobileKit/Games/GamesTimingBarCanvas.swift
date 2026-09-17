#if os(iOS)
import CheckCore
import SwiftUI

// 타이밍 바 한 프레임의 그림 — 맥 `MiniGameTimingBar.swift` 의 TimingBarFrame · TimingBarOverlay 를 옮겼다(값·순서 동일).
// 규칙은 코어 `TimingBarGame`, 판은 논리 292×302 이고 `MiniGameProjection` 이 캔버스에 **등비 확대**한다.
// 판정 등급·배점·주기·폭은 순위표가 걸린 난이도라 그림이 한 줄도 건드리지 않는다.

private enum TimingBarLayout {
    static let width = MiniGameCanvas.logicalWidth
    static let height = MiniGameCanvas.logicalHeight
    static var logicalSize: CGSize { CGSize(width: width, height: height) }
    static let headerY: CGFloat = 22
    static let comboY: CGFloat = 56
    static let trackLeft: CGFloat = 24
    static let trackWidth: CGFloat = 244
    static let trackY: CGFloat = 150
    static let trackHeight: CGFloat = 18
    static let markerWidth: CGFloat = 4
    static let markerHeight: CGFloat = 30
    static let markerTip: CGFloat = 6
    static let segmentsY: CGFloat = 250
    static let segmentHeight: CGFloat = 10
    static let popY: CGFloat = 106
    /// 90점 경계는 배점상 정확히 d < 0.35 다(맥 주석 그대로).
    static let innerTargetRatio: CGFloat = 0.35
    static let perfectLineWidth: CGFloat = 2
    static let perfectOverhang: CGFloat = 4
    static let outerTargetOpacity: Double = 0.78
    static let innerTargetOpacity: Double = 1.0
    static let ringDuration: Double = 0.4
    static let flashDuration: Double = 0.15
    static let shakeDuration: Double = 0.12
    static let stageFlareDuration: Double = 0.6
}

private extension MiniGameProjection {
    func trackX(_ position: Double) -> CGFloat {
        x(TimingBarLayout.trackLeft + CGFloat(position) * TimingBarLayout.trackWidth)
    }
}

/// 타이밍 바 캔버스(배경·트랙·마커·이펙트 + 글자층·카드).
struct GamesTimingBarCanvas: View {
    let game: TimingBarGame
    let bestScore: Int
    let reduceMotion: Bool

    var body: some View {
        let stage = MiniGameStage.forTimingRound(game.round)
        // 글자층은 GeometryReader 가 준 크기로 배치한다 — 크기를 @State 에 적어 두면(맥의 onGeometryChange 방식) 폰의
        // 비율 맞춤 틀 안에서 "크기 → 배율 → 카드 폭 → 크기" 되먹임이 생겨 본문이 끝없이 다시 그려졌다(데모 실측: CPU 100%).
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                draw(&context, size: size, stage: stage)
            }
            GeometryReader { geo in
                overlay(stage: stage, container: geo.size)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .offset(shakeOffset)
    }

    // MARK: 이펙트 시계 — phase 에서 파생(맥과 같다)

    private var sinceTap: Double? {
        guard case .roundResult(_, _, let hold) = game.phase else { return nil }
        return TimingBarGame.resultHold - hold
    }

    private var stageFlareProgress: Double? {
        guard case .running(let round, let t) = game.phase,
              round >= 3, round % 2 == 1, t < TimingBarLayout.stageFlareDuration else { return nil }
        return t / TimingBarLayout.stageFlareDuration
    }

    private var pulse: Double {
        guard !reduceMotion, case .running(_, let t) = game.phase else { return 1 }
        return 0.5 + 0.5 * sin(t * 5.5)
    }

    private var shakeOffset: CGSize {
        guard !reduceMotion, let elapsed = sinceTap, elapsed < TimingBarLayout.shakeDuration,
              let hit = game.lastHit else { return .zero }
        let decay = 1 - elapsed / TimingBarLayout.shakeDuration
        let amplitude = (hit ? 2.0 : 4.0) * decay
        return CGSize(width: amplitude * sin(elapsed * 160), height: amplitude * 0.6 * cos(elapsed * 130))
    }

    private var verdict: TimingBarGame.Verdict? {
        guard case .roundResult(_, let score, _) = game.phase else { return nil }
        return TimingBarGame.verdict(score: score)
    }

    // MARK: Canvas

    private func draw(_ context: inout GraphicsContext, size: CGSize, stage: MiniGameStage) {
        let projection = MiniGameProjection(container: size, logicalSize: TimingBarLayout.logicalSize)
        let full = CGRect(origin: .zero, size: size)
        MiniGameBackdrop.draw(into: &context, rect: full.insetBy(dx: -8, dy: -8), stage: stage,
                              scroll: 0, terrain: false, reduceMotion: reduceMotion)
        if let progress = stageFlareProgress {
            MiniGameEffects.flare(into: &context, rect: full, progress: progress, color: stage.glow)
        }
        drawTrackGlow(&context, projection: projection, stage: stage)
        drawTrack(&context, projection: projection, stage: stage)
        if game.isPlaying {
            drawTarget(&context, projection: projection, stage: stage)
            drawMarker(&context, projection: projection)
            drawHitEffects(&context, projection: projection, full: full, stage: stage)
            drawSegments(&context, projection: projection, stage: stage)
        }
        if let elapsed = sinceTap, verdict == .miss, elapsed < TimingBarLayout.flashDuration {
            let strength = 1 - elapsed / TimingBarLayout.flashDuration
            context.fill(Path(full), with: .color(CheckTheme.danger.opacity(0.24 * strength)))
        }
    }

    private func drawTrackGlow(_ context: inout GraphicsContext, projection: MiniGameProjection, stage: MiniGameStage) {
        let glow = projection.rect(TimingBarLayout.trackLeft - 46, TimingBarLayout.trackY - 52,
                                   TimingBarLayout.trackWidth + 92, 104)
        MiniGameEffects.glow(into: &context, in: glow, color: stage.glow, opacity: 0.22)
    }

    private func drawTrack(_ context: inout GraphicsContext, projection: MiniGameProjection, stage: MiniGameStage) {
        let body = projection.rect(TimingBarLayout.trackLeft, TimingBarLayout.trackY - TimingBarLayout.trackHeight / 2,
                                   TimingBarLayout.trackWidth, TimingBarLayout.trackHeight)
        let capsule = Path(roundedRect: body, cornerRadius: body.height / 2)
        context.fill(capsule, with: .linearGradient(
            Gradient(colors: [.black.opacity(0.86), .black.opacity(0.66)]),
            startPoint: CGPoint(x: body.midX, y: body.minY),
            endPoint: CGPoint(x: body.midX, y: body.maxY)
        ))
        context.stroke(capsule, with: .color(stage.structureEdge.opacity(0.35)), lineWidth: 1)
        for step in 0..<3 {
            let inset = 6 + CGFloat(step) * 5
            let tickHeight = 8 - CGFloat(step) * 2
            let opacity = 0.5 - Double(step) * 0.14
            for side in [-1.0, 1.0] as [CGFloat] {
                let center = side < 0
                    ? TimingBarLayout.trackLeft - inset
                    : TimingBarLayout.trackLeft + TimingBarLayout.trackWidth + inset
                let tick = projection.rect(center - 0.75, TimingBarLayout.trackY - tickHeight / 2, 1.5, tickHeight)
                context.fill(Path(tick), with: .color(stage.structureEdge.opacity(opacity)))
            }
        }
    }

    private func drawTarget(_ context: inout GraphicsContext, projection: MiniGameProjection, stage: MiniGameStage) {
        let (center, width) = game.target
        let height = TimingBarLayout.trackHeight
        let top = TimingBarLayout.trackY - height / 2
        let outerWidth = CGFloat(width) * TimingBarLayout.trackWidth
        let outerLeft = TimingBarLayout.trackLeft + CGFloat(center - width / 2) * TimingBarLayout.trackWidth
        let outer = projection.rect(outerLeft, top, outerWidth, height)
        context.fill(Path(roundedRect: outer, cornerRadius: 3 * projection.scale),
                     with: .color(stage.structure.opacity(TimingBarLayout.outerTargetOpacity)))
        let innerWidth = outerWidth * TimingBarLayout.innerTargetRatio
        let inner = projection.rect(outerLeft + (outerWidth - innerWidth) / 2, top + 2, innerWidth, height - 4)
        let innerPath = Path(roundedRect: inner, cornerRadius: 2 * projection.scale)
        context.fill(innerPath, with: .color(stage.structureEdge.opacity(TimingBarLayout.innerTargetOpacity)))
        context.stroke(innerPath, with: .color(.black.opacity(0.50)), lineWidth: 1)
        let lineX = TimingBarLayout.trackLeft + CGFloat(center) * TimingBarLayout.trackWidth
        let slotWidth = TimingBarLayout.perfectLineWidth + 2
        let slot = projection.rect(lineX - slotWidth / 2, top - TimingBarLayout.perfectOverhang,
                                   slotWidth, height + TimingBarLayout.perfectOverhang * 2)
        context.fill(Path(slot), with: .color(.black.opacity(0.55)))
        let line = projection.rect(lineX - TimingBarLayout.perfectLineWidth / 2, top - TimingBarLayout.perfectOverhang,
                                   TimingBarLayout.perfectLineWidth, height + TimingBarLayout.perfectOverhang * 2)
        context.fill(Path(line), with: .color(stage.glow))
    }

    private func drawMarker(_ context: inout GraphicsContext, projection: MiniGameProjection) {
        let color = verdict?.tint ?? CheckTheme.primaryText
        if !reduceMotion, case .running(let round, let t) = game.phase {
            let period = TimingBarGame.period(round: round)
            for (age, opacity) in [(2.0 / 60.0, 0.28), (4.0 / 60.0, 0.16), (6.0 / 60.0, 0.08)] {
                let past = TimingBarGame.markerPosition(t: t - age, period: period)
                let ghost = bladeRect(at: past, projection: projection).insetBy(dx: 0, dy: 4 * projection.scale)
                context.fill(Path(roundedRect: ghost, cornerRadius: 1.5 * projection.scale), with: .color(color.opacity(opacity)))
            }
        }
        let markerX = projection.trackX(game.markerPosition)
        let centerY = projection.y(TimingBarLayout.trackY)
        let halo = 26 * projection.scale
        MiniGameEffects.glow(into: &context, in: CGRect(x: markerX - halo, y: centerY - halo, width: halo * 2, height: halo * 2),
                             color: color, opacity: 0.38)
        let blade = bladeRect(at: game.markerPosition, projection: projection)
        context.fill(Path(roundedRect: blade, cornerRadius: 1.5 * projection.scale), with: .color(color))
        let half = 5 * projection.scale
        let tip = TimingBarLayout.markerTip * projection.scale
        var top = Path()
        top.move(to: CGPoint(x: markerX, y: blade.minY + 1))
        top.addLine(to: CGPoint(x: markerX - half, y: blade.minY - tip))
        top.addLine(to: CGPoint(x: markerX + half, y: blade.minY - tip))
        top.closeSubpath()
        var bottom = Path()
        bottom.move(to: CGPoint(x: markerX, y: blade.maxY - 1))
        bottom.addLine(to: CGPoint(x: markerX - half, y: blade.maxY + tip))
        bottom.addLine(to: CGPoint(x: markerX + half, y: blade.maxY + tip))
        bottom.closeSubpath()
        context.fill(top, with: .color(color))
        context.fill(bottom, with: .color(color))
    }

    private func bladeRect(at position: Double, projection: MiniGameProjection) -> CGRect {
        CGRect(
            x: projection.trackX(position) - TimingBarLayout.markerWidth / 2 * projection.scale,
            y: projection.y(TimingBarLayout.trackY - TimingBarLayout.markerHeight / 2),
            width: TimingBarLayout.markerWidth * projection.scale,
            height: TimingBarLayout.markerHeight * projection.scale
        )
    }

    private func drawHitEffects(_ context: inout GraphicsContext, projection: MiniGameProjection, full: CGRect, stage: MiniGameStage) {
        guard let elapsed = sinceTap, let verdict, verdict != .miss else { return }
        let progress = elapsed / TimingBarLayout.ringDuration
        guard progress < 1 else { return }
        let center = CGPoint(x: projection.trackX(game.markerPosition), y: projection.y(TimingBarLayout.trackY))
        MiniGameEffects.ring(into: &context, center: center, progress: progress,
                             maxRadius: 42 * projection.scale, color: verdict.tint, lineWidth: 2)
        MiniGameEffects.ring(into: &context, center: center, progress: min(1, progress * 1.5),
                             maxRadius: 24 * projection.scale, color: verdict.tint.opacity(0.85), lineWidth: 1.5)
        MiniGameEffects.sparks(into: &context, center: center, progress: progress, count: 8,
                               maxRadius: 34 * projection.scale, color: verdict.tint,
                               seed: UInt64(max(1, game.round)), dotRadius: 2.2 * projection.scale)
        if verdict == .perfect {
            MiniGameEffects.flare(into: &context, rect: full, progress: elapsed / TimingBarLayout.stageFlareDuration, color: stage.glow)
        }
    }

    private func drawSegments(_ context: inout GraphicsContext, projection: MiniGameProjection, stage: MiniGameStage) {
        let count = TimingBarGame.roundCount
        let gap: CGFloat = 3
        let cellWidth = (TimingBarLayout.trackWidth - gap * CGFloat(count - 1)) / CGFloat(count)
        let currentIndex: Int? = {
            if case .running(let round, _) = game.phase { return round - 1 }
            return nil
        }()
        for index in 0..<count {
            let left = TimingBarLayout.trackLeft + CGFloat(index) * (cellWidth + gap)
            let cell = projection.rect(left, TimingBarLayout.segmentsY - TimingBarLayout.segmentHeight / 2,
                                       cellWidth, TimingBarLayout.segmentHeight)
            let path = Path(roundedRect: cell, cornerRadius: 3 * projection.scale)
            if index < game.roundScores.count {
                let verdict = TimingBarGame.verdict(score: game.roundScores[index])
                context.fill(path, with: .color(verdict.tint.opacity(0.85)))
                context.stroke(path, with: .color(verdict.tint), lineWidth: 1)
                drawGlyph(&context, verdict.glyph, in: cell)
            } else if index == currentIndex {
                context.fill(path, with: .color(stage.glow.opacity(0.14 + 0.16 * pulse)))
                context.stroke(path, with: .color(stage.glow.opacity(0.55 + 0.45 * pulse)), lineWidth: 1.6)
            } else {
                context.stroke(path, with: .color(stage.structureEdge.opacity(0.28)), lineWidth: 1)
            }
        }
    }

    private func drawGlyph(_ context: inout GraphicsContext, _ glyph: TimingBarSegmentGlyph, in cell: CGRect) {
        let ink = GraphicsContext.Shading.color(.black.opacity(0.72))
        let r = min(cell.height, cell.width) * 0.28
        let c = CGPoint(x: cell.midX, y: cell.midY)
        let box = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        switch glyph {
        case .star, .disc:
            context.fill(Path(ellipseIn: box), with: ink)
            if glyph == .star {
                context.fill(Path(ellipseIn: box.insetBy(dx: r * 0.5, dy: r * 0.5)), with: .color(.white.opacity(0.85)))
            }
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: c.x, y: c.y - r))
            path.addLine(to: CGPoint(x: c.x + r, y: c.y))
            path.addLine(to: CGPoint(x: c.x, y: c.y + r))
            path.addLine(to: CGPoint(x: c.x - r, y: c.y))
            path.closeSubpath()
            context.fill(path, with: ink)
        case .ring:
            context.stroke(Path(ellipseIn: box), with: ink, lineWidth: max(1, r * 0.55))
        case .cross:
            var path = Path()
            path.move(to: CGPoint(x: c.x - r, y: c.y - r))
            path.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
            path.move(to: CGPoint(x: c.x + r, y: c.y - r))
            path.addLine(to: CGPoint(x: c.x - r, y: c.y + r))
            context.stroke(path, with: ink, lineWidth: max(1, r * 0.55))
        }
    }

    // MARK: 글자층

    @ViewBuilder
    private func overlay(stage: MiniGameStage, container: CGSize) -> some View {
        let projection = MiniGameProjection(container: container, logicalSize: TimingBarLayout.logicalSize)
        let scale = projection.scale
        ZStack {
            HStack(alignment: .center, spacing: 6 * scale) {
                Text("라운드 \(max(1, game.round))/\(TimingBarGame.roundCount)")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(CheckTheme.primaryText.opacity(0.86))
                GamesStageChip(stage: stage, scale: scale)
                Spacer(minLength: 4)
                Text(String(game.total))
                    .font(.system(size: 25 * scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
            }
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .frame(width: (TimingBarLayout.width - 28) * scale)
            .position(x: projection.x(TimingBarLayout.width / 2), y: projection.y(TimingBarLayout.headerY))

            if game.isPlaying, game.combo >= 2 {
                HStack(spacing: 3 * scale) {
                    Image(systemName: "flame.fill").font(.system(size: 9 * scale, weight: .bold))
                    Text("콤보 x\(game.combo)").font(.system(size: 11 * scale, weight: .heavy))
                }
                .foregroundStyle(stage.glow)
                .padding(.horizontal, 9 * scale)
                .padding(.vertical, 3 * scale)
                .background(Capsule().fill(stage.glow.opacity(0.18)))
                .overlay(Capsule().stroke(stage.glow.opacity(0.50), lineWidth: 1))
                .scaleEffect(game.combo >= 3 ? 1.14 : 1)
                .position(x: projection.x(TimingBarLayout.width / 2), y: projection.y(TimingBarLayout.comboY))
            }

            if case .roundResult(let round, let score, _) = game.phase {
                let verdict = TimingBarGame.verdict(score: score)
                let clamped = min(max(game.markerPosition, 0.10), 0.90)
                GamesScorePop(text: "+\(score)", caption: verdict.label, tint: verdict.tint,
                                     reduceMotion: reduceMotion, scale: scale)
                    .id(round)
                    .position(x: projection.trackX(clamped), y: projection.y(TimingBarLayout.popY))
            }

            // 카드는 판 배율보다 한 단계 작게 — 판 배율 그대로 키우면 아래에 붙인 카드 윗변이 트랙(y 150)을 덮는다
            // (맥은 카드가 배율을 안 타서 344pt 판에서 트랙 아래에 섰다 — 같은 자리를 지키는 값).
            card(stage: stage, scale: scale * 0.82)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func card(stage: MiniGameStage, scale: CGFloat) -> some View {
        switch game.phase {
        case .ready:
            bottomAligned(GamesOverlayCard(
                title: MiniGameKind.timingBar.title,
                subtitle: GamesMiniGameText.howToPlay(.timingBar),
                action: GamesMiniGameText.startAction,
                icon: MiniGameKind.timingBar.icon,
                tint: stage.glow, scale: scale), scale: scale)
        case .finished(let total):
            bottomAligned(GamesOverlayCard(
                title: "총점 \(total)", titleIsScore: true,
                subtitle: total > bestScore ? "신기록!" : "최고 \(bestScore)",
                subtitleIsHighlighted: total > bestScore,
                action: GamesMiniGameText.againAction,
                icon: MiniGameKind.timingBar.icon,
                tint: stage.glow, scale: scale), scale: scale)
        case .running, .roundResult:
            EmptyView()
        }
    }

    private func bottomAligned(_ content: some View, scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
        }
        .padding(.bottom, 10 * scale)
    }
}
#endif
