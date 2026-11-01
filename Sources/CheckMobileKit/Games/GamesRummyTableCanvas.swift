#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// 폰 아잉 큐브 판 칸(맥 `RummyTableCanvasView` 의 그림 — 입력은 없다. 손은 화면 전체 제스처 하나가 받는다).
//
// ── 왜 `GamesRummyTile` 뷰를 안 쓰고 Canvas 에 그리는가 ──
// 판에는 타일이 100장 넘게 깔린다. `GamesRummyTile` 은 타일마다 그라데이션 · 글자 · `compositingGroup` · 그림자를 얹는 뷰라 100장이면 오프스크린 패스만 100번이고,
// 뷰가 100개면 판이 바뀔 때마다 비교도 100번이다. 그래서 판 쪽은:
//   ① **Canvas 하나**에 전부 그린다. 뷰 하나 · 같은 면 글자는 한 번만 푼다(`resolve`) · 그림자 대신 얇은 윤곽(타일이 작아 차이가 안 보인다).
//      `drawingGroup` 을 안 쓴 까닭: 그것도 안의 뷰 100개를 그대로 두고 평탄화만 하므로 뷰 비교 비용이 남는다.
//   ② **밀기는 다시 그리지 않는다.** 층을 캔버스 전체 크기(+ 손잡이 자리)로 한 번 그려 두고 `.offset` 으로 옮긴다. 입력이 같으면 `.equatable()` 이 본문을 건너뛴다.
//   ③ **핀치도 프레임마다 다시 그리지 않는다.** 그린 배율(`renderScale`)은 두고 층을 `.scaleEffect` 로 키운 뒤, 손을 떼면 그 배율로 또렷하게 다시 그린다.
//   ④ **끌기 중에는 안 다시 그린다.** 손가락 자리는 떠 있는 타일 잎 뷰만 읽고, 판 층 입력은 끌기가 시작·끝날 때만 바뀐다. 자석·캐럿·점선은 이 층 위의 따로 된 층이다.
// 타일 모양 치수는 `GamesRummyTile` 과 같은 `RummyTileSize` 에서 나온다.

/// 묶음 상자 · 타일 · 손잡이 층. 좌표 = 논리 좌표 × `scale` + `bleed`.
struct GamesRummyBoardLayer: View, Equatable {
    /// 캔버스 바깥 여백(왼끝 묶음의 손잡이 · 이번 차례 링이 잘리지 않게).
    static let bleed: CGFloat = 44

    let melds: [RummyBoardMeld]
    let scale: CGFloat
    let editable: Bool
    let dimmed: Set<Int>
    let lifted: Set<Int>
    let movingSet: Int?
    /// 지금 뷰로 떠서 움직이는 칸(`GamesRummyBoardMotion`) — 이 층은 그리지 않는다.
    var hidden: Set<GamesRummyBoardMotion.Slot> = []

    @Environment(\.displayScale) private var displayScale

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.scale == rhs.scale && lhs.editable == rhs.editable && lhs.movingSet == rhs.movingSet
            && lhs.dimmed == rhs.dimmed && lhs.lifted == rhs.lifted && lhs.hidden == rhs.hidden && lhs.melds == rhs.melds
    }

    var body: some View {
        let canvas = RummyCanvasTransform.canvas
        Canvas(rendersAsynchronously: false) { context, _ in
            draw(in: &context)
        }
        .frame(width: canvas.width * scale + Self.bleed * 2, height: canvas.height * scale + Self.bleed * 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext) {
        let tileW = CGFloat(RummyTableLayout.tileWidth) * scale
        let tileH = CGFloat(RummyTableLayout.tileHeight) * scale
        let inset = max(1, tileW * 0.05)
        let painter = GamesRummyTilePainter(size: CGSize(width: tileW - inset, height: tileH - inset), context: context,
                                            displayScale: displayScale)
        let pad = max(2, 3 * scale)
        func rect(_ logical: RummyRect) -> CGRect {
            CGRect(x: CGFloat(logical.x) * scale + Self.bleed, y: CGFloat(logical.y) * scale + Self.bleed,
                   width: CGFloat(logical.width) * scale, height: CGFloat(logical.height) * scale)
        }
        let invalid = RummyTilePalette.color(RummyTilePalette.invalid)
        // 묶음 상자.
        for (index, meld) in melds.enumerated() {
            var layer = context
            layer.opacity = movingSet == index ? 0.35 : 1
            let box = Path(roundedRect: rect(meld.frame).insetBy(dx: -pad, dy: -pad), cornerRadius: pad * 2, style: .continuous)
            layer.fill(box, with: .color(meld.invalid ? invalid.opacity(0.16) : Color.black.opacity(0.18)))
            layer.stroke(box, with: .color(meld.invalid ? invalid : Color.white.opacity(0.08)), lineWidth: meld.invalid ? 2 : 1)
        }
        // 타일.
        for (index, meld) in melds.enumerated() {
            let frame = rect(meld.frame)
            for (slot, tile) in meld.tiles.enumerated() {
                if hidden.contains(GamesRummyBoardMotion.Slot(meld: index, tile: slot)) { continue }
                let isLifted = tile.id.map(lifted.contains) ?? false
                let isDimmed = tile.id.map(dimmed.contains) ?? false
                let origin = CGPoint(x: frame.minX + CGFloat(slot) * tileW + inset / 2,
                                     y: frame.minY + inset / 2 - (isLifted ? 4 : 0))
                painter.draw(tile.face, at: origin, into: &context, highlighted: tile.highlighted, lifted: isLifted,
                             opacity: movingSet == index ? 0.35 : (isDimmed ? 0.28 : 1))
            }
        }
        // 손잡이(내 차례).
        guard editable else { return }
        for (index, meld) in melds.enumerated() {
            var layer = context
            layer.opacity = movingSet == index ? 0.35 : 1
            let frame = rect(meld.frame)
            let bar = GamesRummyGestureRules.handleBar(shown: frame, scale: scale)
            let width = bar.width
            let capsule = Path(roundedRect: bar, cornerRadius: width / 2, style: .continuous)
            layer.fill(capsule, with: .color(Color(red: 0.55, green: 0.45, blue: 1.0).opacity(0.55)))
            layer.stroke(capsule, with: .color(Color.white.opacity(0.25)), lineWidth: 0.8)
            let dot = max(2.5, width * 0.36), gap = max(2, frame.height * 0.08)
            for step in -1...1 {
                let center = CGPoint(x: bar.midX, y: bar.midY + CGFloat(step) * (dot + gap))
                layer.fill(Path(ellipseIn: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)),
                           with: .color(Color.white.opacity(0.75)))
            }
        }
    }
}

/// Canvas 안 타일 한 장 그리기 — 값은 `GamesRummyTile` 과 같은 `RummyTileSize`. 같은 면 글자를 한 번만 푼다(그리는 한 번 안에서만 쓴다).
private final class GamesRummyTilePainter {
    private let metrics: RummyTileSize
    private let width: CGFloat
    private let height: CGFloat
    private var numbers: [String: GraphicsContext.ResolvedText] = [:]
    private var joker: GraphicsContext.ResolvedImage?
    private let resolver: GraphicsContext
    private let body: Path
    private let top: Path

    init(size: CGSize, context: GraphicsContext, displayScale: CGFloat) {
        metrics = RummyTileSize(size)
        width = size.width
        height = size.height
        resolver = context
        body = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: metrics.corner, style: .continuous)
        top = Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height - metrics.bevel),
                   cornerRadius: metrics.corner, style: .continuous)
        // 판 타일이 커져도 또렷하게 — 상한(타일 폭 40)에 맞춘 한 장을 줄여 쓴다.
        if let image = MobileArt.character(id: AingCharacterArt.defaultID, expression: .neutral, pointSize: 40, displayScale: displayScale) {
            joker = context.resolve(Image(uiImage: image))
        }
    }

    func draw(_ face: RummyFace, at origin: CGPoint, into context: inout GraphicsContext, highlighted: Bool, lifted: Bool, opacity: Double) {
        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: origin.x, y: origin.y)
        layer.fill(body, with: .color(RummyTilePalette.color(RummyTilePalette.bevel)))
        layer.fill(top, with: .linearGradient(Gradient(colors: [RummyTilePalette.color(RummyTilePalette.bodyTop),
                                                                RummyTilePalette.color(RummyTilePalette.bodyBottom)]),
                                              startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))
        layer.stroke(body, with: .color(Color.black.opacity(0.28)), lineWidth: 0.6)
        let bodyHeight = height - metrics.bevel
        if let color = face.color, let number = face.number {
            let line = metrics.numberFont * 1.12
            let stack = line + metrics.stackSpacing + metrics.markSize
            let start = max(metrics.topPadding * 0.5, (bodyHeight - stack) / 2)
            layer.draw(numberText(face, number: number, color: color),
                       at: CGPoint(x: width / 2, y: start + line / 2), anchor: .center)
            let mark = CGRect(x: width / 2 - metrics.markSize / 2, y: start + line + metrics.stackSpacing,
                              width: metrics.markSize, height: metrics.markSize)
            layer.fill(markPath(color, in: mark), with: .color(RummyTilePalette.ink(for: color)))
        } else {
            let side = width * 0.76
            let dot = max(2, width * 0.1)
            let stack = side + metrics.stackSpacing + dot
            let start = max(0, (bodyHeight - stack) / 2)
            let face = CGRect(x: (width - side) / 2, y: start, width: side, height: side)
            if let joker {
                layer.draw(joker, in: face)
            } else {
                layer.fill(Path(ellipseIn: face), with: .color(RummyTilePalette.color((0x7B, 0x61, 0xFF))))
            }
            let gap = max(1, dot * 0.38)
            let total = dot * 4 + gap * 3
            for index in 0..<4 {
                layer.fill(Path(ellipseIn: CGRect(x: (width - total) / 2 + CGFloat(index) * (dot + gap),
                                                  y: start + side + metrics.stackSpacing, width: dot, height: dot)),
                           with: .color(RummyTilePalette.ink(for: index)))
            }
        }
        if highlighted {
            let ring = Path(roundedRect: CGRect(x: -1, y: -1, width: width + 2, height: height + 2),
                            cornerRadius: metrics.corner + 1, style: .continuous)
            layer.stroke(ring, with: .color(RummyTilePalette.color(RummyTilePalette.highlight)), lineWidth: max(1.5, width * 0.06))
        }
        if lifted {
            let ring = Path(roundedRect: CGRect(x: -1, y: -1, width: width + 2, height: height + 2),
                            cornerRadius: metrics.corner + 1, style: .continuous)
            layer.stroke(ring, with: .color(MobileTheme.accent), lineWidth: 2)
        }
    }

    private func numberText(_ face: RummyFace, number: Int, color: Int) -> GraphicsContext.ResolvedText {
        if let done = numbers[face.text] { return done }
        let text = resolver.resolve(Text(verbatim: "\(number)")
            .font(.system(size: metrics.numberFont, weight: .heavy, design: .rounded))
            .foregroundStyle(RummyTilePalette.ink(for: color)))
        numbers[face.text] = text
        return text
    }

    /// ●▲■◆ — `GamesRummyTileMark` 과 같은 도형.
    private func markPath(_ color: Int, in rect: CGRect) -> Path {
        switch color {
        case 0:
            return Path(ellipseIn: rect)
        case 1:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        case 2:
            return Path(rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06))
        default:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - 판 칸

/// 판 칸 — 펠트 · 판 층(옮기기만) · 미리보기 층. **이 뷰만 `viewport` 를 읽는다**(밀 때마다 여기만 다시 돈다).
struct GamesRummyTablePane: View {
    let model: GamesRummyMatchModel
    let scene: GamesRummyBoardScene
    let size: CGSize
    let editable: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 판 변화 모션 한 번. 판 층은 그 칸을 비우고 위 층이 옛 자리 → 새 자리로 옮긴다.
    @State private var motion: GamesRummyBoardMotion?
    @State private var motionLanded = false
    @State private var motionSerial = 0

    var body: some View {
        let viewport = model.viewport
        let transform = viewport.transform
        let ratio = viewport.scale / model.renderScale
        let origin = transform.toScreen(.zero)
        let bleed = GamesRummyBoardLayer.bleed * ratio
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .topLeading) {
            GamesRummyTableSurface()
                .frame(width: size.width, height: size.height)
            ZStack(alignment: .topLeading) {
                GamesRummyBoardLayer(melds: scene.melds, scale: model.renderScale, editable: editable,
                                     dimmed: model.draggingIDs, lifted: Set(model.lift?.surface == .board ? model.lift?.ids ?? [] : []),
                                     movingSet: model.movingSet, hidden: motion?.hidden ?? [])
                    .equatable()
                    .scaleEffect(ratio, anchor: .topLeading)
                    .offset(x: origin.x - bleed, y: origin.y - bleed)
                if let motion {
                    GamesRummyBoardMotionLayer(motion: motion, landed: motionLanded, transform: transform)
                }
                if let preview = model.boardPreview {
                    GamesRummyBoardPreviewLayer(preview: preview, melds: scene.melds, transform: transform, size: size)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesRummyText.boardSummary(melds: scene.melds.count, tiles: scene.tileCount))
        .onChange(of: scene.melds) { old, new in startMotion(from: old, to: new) }
    }

    /// 판이 바뀌었다 — 움직인 타일을 옛 자리에 세웠다가 다음 틈에 새 자리로 보낸다(맥 `slide` 와 같은 스프링). 끝나면 판 층이 다시 그린다. 끄는 중 · 동작 줄이기면 없다.
    private func startMotion(from old: [RummyBoardMeld], to new: [RummyBoardMeld]) {
        motionSerial += 1
        let serial = motionSerial
        guard !reduceMotion, model.drag == nil,
              let next = GamesRummyBoardMotion.make(from: old, to: new, excluding: model.recentDropIDs, landing: model.recentDropOrigins) else {
            motion = nil
            return
        }
        motionLanded = false
        motion = next
        Task { @MainActor in
            guard motionSerial == serial else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84), completionCriteria: .logicallyComplete) {
                motionLanded = true
            } completion: {
                if motionSerial == serial { motion = nil }
            }
        }
    }
}

/// 움직이는 타일만 잠깐 뷰로 띄운다(많아야 `GamesRummyBoardMotion.maxMoves` 장 · 판 층의 크기 값과 같다).
private struct GamesRummyBoardMotionLayer: View {
    let motion: GamesRummyBoardMotion
    let landed: Bool
    let transform: RummyCanvasTransform

    var body: some View {
        let tileW = CGFloat(RummyTableLayout.tileWidth) * transform.scale
        let tileH = CGFloat(RummyTableLayout.tileHeight) * transform.scale
        let inset = max(1, tileW * 0.05)
        ZStack(alignment: .topLeading) {
            ForEach(motion.moves) { move in
                let point = transform.toScreen(landed ? move.to : move.from)
                GamesRummyTile(face: move.face, size: CGSize(width: tileW - inset, height: tileH - inset), highlighted: move.highlighted)
                    .position(x: point.x + tileW / 2, y: point.y + tileH / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 놓기 미리보기

/// 자석 · 끼울 자리 캐럿 · 새 묶음 점선 · 맞는 세트 체크(맥 `previewUnder`·`previewOver`). 판 층 위 따로 된 층이라 놓을 자리가 바뀌어도 타일을 다시 안 그린다.
private struct GamesRummyBoardPreviewLayer: View {
    let preview: RummyBoardPreview
    let melds: [RummyBoardMeld]
    let transform: RummyCanvasTransform
    let size: CGSize

    private var pad: CGFloat { max(2, 3 * transform.scale) }
    private func tint(valid: Bool) -> Color { valid ? MobileTheme.working : MobileTheme.accent }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let set = preview.targetSet, melds.indices.contains(set) {
                let frame = transform.rect(melds[set].frame)
                RoundedRectangle(cornerRadius: pad * 2, style: .continuous)
                    .stroke(tint(valid: preview.completes), lineWidth: 2)
                    .frame(width: frame.width + pad * 2, height: frame.height + pad * 2)
                    .position(x: frame.midX, y: frame.midY)
            }
            switch preview {
            case .ghost(let rect):
                dashed(rect, color: MobileTheme.accent, fill: 0.16, grow: 2)
            case .attach(_, let side, let slots, let landing, let valid):
                dashed(slots, color: tint(valid: valid), fill: 0.2, grow: 1)
                let frame = transform.rect(slots)
                // 배지는 이음 위에 선다 — 맨 윗줄 묶음이면 칸 위로 잘리니 아래로 내린다.
                let badge = max(18, 26 * transform.scale)
                GamesRummyMagnetSeam(color: tint(valid: valid), height: frame.height + pad * 2 + 6, side: side, badge: badge,
                                     badgeBelow: frame.minY - pad - badge < 0)
                    .position(x: transform.toScreen(CGPoint(x: CGFloat(preview.magnetSeamX ?? slots.x), y: 0)).x, y: frame.midY)
                if valid { checkBadge(landing) }
            case .insert(let set, let caretX, let landing, let valid):
                dashed(landing, color: tint(valid: valid), fill: 0.1, grow: pad + 3)
                if melds.indices.contains(set) {
                    let frame = transform.rect(melds[set].frame)
                    GamesRummyInsertCaret(color: tint(valid: valid), height: frame.height + pad * 2 + 8)
                        .position(x: transform.toScreen(CGPoint(x: CGFloat(caretX), y: 0)).x, y: frame.midY)
                }
                if valid { checkBadge(landing) }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func dashed(_ rect: RummyRect, color: Color, fill: Double, grow: CGFloat) -> some View {
        let frame = transform.rect(rect)
        return RoundedRectangle(cornerRadius: 6 * max(transform.scale, 0.6), style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(fill)))
            .frame(width: frame.width + grow * 2, height: frame.height + grow * 2)
            .position(x: frame.midX, y: frame.midY)
    }

    private func checkBadge(_ landing: RummyRect) -> some View {
        let frame = transform.rect(landing)
        let d = max(14, 18 * transform.scale)
        return Image(systemName: "checkmark")
            .font(.system(size: d * 0.55, weight: .black))
            .foregroundStyle(Color.black.opacity(0.8))
            .frame(width: d, height: d)
            .background(Circle().fill(MobileTheme.working))
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.2))
            .position(x: frame.maxX + pad, y: frame.minY - pad)
    }
}

/// 끼울 자리 캐럿 — 타일 사이에 서는 빛나는 세로 막대.
private struct GamesRummyInsertCaret: View {
    let color: Color
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(color).frame(width: 9, height: 9)
            Capsule().fill(color).frame(width: 4, height: max(8, height - 18))
            Circle().fill(color).frame(width: 9, height: 9)
        }
        .overlay(Capsule().fill(Color.white.opacity(0.7)).frame(width: 1.4, height: max(4, height - 22)))
        .shadow(color: color.opacity(0.9), radius: 6)
        .frame(width: 12, height: height)
    }
}

/// 붙을 끝 자석 — 이음 막대 + 말굽자석 배지(열린 쪽이 블록이 붙는 쪽).
private struct GamesRummyMagnetSeam: View {
    let color: Color
    let height: CGFloat
    let side: RummyAttachSide
    let badge: CGFloat
    var badgeBelow = false

    var body: some View {
        ZStack {
            Capsule().fill(color).frame(width: 5, height: height)
                .shadow(color: color.opacity(0.95), radius: 7)
            GamesRummyMagnetShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: badge * 0.17, lineCap: .butt, lineJoin: .round))
                .overlay(GamesRummyMagnetTips().fill(Color(white: 0.2)))
                .frame(width: badge * 0.56, height: badge * 0.6)
                .rotationEffect(.degrees(side == .right ? 45 : -45))
                .frame(width: badge, height: badge)
                .background(Circle().fill(color))
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.2))
                .offset(y: (height / 2 + badge * 0.3) * (badgeBelow ? 1 : -1))
        }
        .frame(width: badge, height: height)
    }
}

private struct GamesRummyMagnetShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.15
        let left = rect.minX + inset, right = rect.maxX - inset
        let bend = rect.minY + rect.height * 0.4
        let bottom = rect.maxY - inset
        var p = Path()
        p.move(to: CGPoint(x: left, y: rect.minY))
        p.addLine(to: CGPoint(x: left, y: bend))
        p.addCurve(to: CGPoint(x: right, y: bend),
                   control1: CGPoint(x: left, y: bend + (bottom - bend) * 4 / 3),
                   control2: CGPoint(x: right, y: bend + (bottom - bend) * 4 / 3))
        p.addLine(to: CGPoint(x: right, y: rect.minY))
        return p
    }
}

private struct GamesRummyMagnetTips: Shape {
    func path(in rect: CGRect) -> Path {
        let leg = rect.width * 0.3
        let h = rect.height * 0.2
        var p = Path()
        p.addRect(CGRect(x: rect.minX, y: rect.minY, width: leg, height: h))
        p.addRect(CGRect(x: rect.maxX - leg, y: rect.minY, width: leg, height: h))
        return p
    }
}

// MARK: - 전체 보기 · 화면 밖 배지

/// [전체 보기] 토글 — 오른쪽 열(판 위에 두면 타일을 가린다).
struct GamesRummyZoomButton: View {
    let model: GamesRummyMatchModel

    var body: some View {
        let full = model.viewport.isFullView
        Button {
            model.toggleFullView()
        } label: {
            Image(systemName: full ? "plus.magnifyingglass" : "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MobileTheme.label)
                .frame(width: AingButtonMetrics.minimumTarget, height: AingButtonMetrics.minimumTarget)
                .background(GlassBackground(shape: Circle()))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(full ? GamesRummyText.zoomDefault : GamesRummyText.zoomFull)
    }
}

/// 화면 밖 묶음 배지. 입력 층 **위**에 있어 제스처보다 먼저 눌린다(그래서 그 자리 타일은 못 집는다). 끄는 동안은 숨는다(자동 밀기·미리보기를 가리지 않게).
struct GamesRummyTableControls: View {
    let model: GamesRummyMatchModel
    let scene: GamesRummyBoardScene
    let size: CGSize
    /// 판 아래쪽에서 비워 둘 높이(다른 기기 안내).
    var badgeLift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let viewport = model.viewport
        let frames = scene.layout.frames
        let counts = viewport.offscreenCounts(frames)
        let vertical = viewport.offscreenVerticalCounts(frames)
        let dragging = !model.draggingIDs.isEmpty
        ZStack {
            if !dragging {
                // 좌우는 판 아래쪽 — 묶음은 위부터 깔리니 숫자를 덜 가린다.
                if counts.left > 0 {
                    badge(.left, count: counts.left, frames: frames)
                        .padding(.bottom, badgeLift)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                if counts.right > 0 {
                    badge(.right, count: counts.right, frames: frames)
                        .padding(.bottom, badgeLift)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                if vertical.up > 0 {
                    badge(.up, count: vertical.up, frames: frames)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                if vertical.down > 0 {
                    badge(.down, count: vertical.down, frames: frames)
                        .padding(.bottom, badgeLift)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func badge(_ side: GamesRummyViewport.Side, count: Int, frames: [RummyRect]) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)) {
                model.reveal(side, frames: frames)
            }
        } label: {
            HStack(spacing: 2) {
                switch side {
                case .left: arrow("arrowtriangle.left.fill")
                case .up: arrow("arrowtriangle.up.fill")
                case .right, .down: EmptyView()
                }
                Text(verbatim: "\(count)").font(.caption.weight(.heavy)).monospacedDigit()
                switch side {
                case .right: arrow("arrowtriangle.right.fill")
                case .down: arrow("arrowtriangle.down.fill")
                case .left, .up: EmptyView()
                }
            }
            .foregroundStyle(MobileTheme.onAccentFill)
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(Capsule().fill(MobileTheme.accentFill))
            .overlay(Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1))
            .padding(.horizontal, 5)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GamesRummyText.offscreen(side, count: count))
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 8, weight: .black))
    }
}
#endif
