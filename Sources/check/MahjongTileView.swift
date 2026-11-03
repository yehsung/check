import AppKit
import CoreText
import SwiftUI
import CheckCore

// MARK: - 아잉 마작 패 그림 (SPEC §5.9 · UX §2.6)
//
// 패 얼굴은 **우리 코드로** 그린다 — 배치는 코어 `MahjongTileArtModel`(맥·폰 공용 순수 값), 그리기는 여기.
//
// ── 규약 ──
//  · CoreGraphics/CoreText 로 `NSImage(size:flipped:drawingHandler:)` 에 그린다. 배율이 바뀌면(레티나 ↔ 1배 모니터) AppKit 이
//    처리기를 다시 부른다. **실행 중 `ImageRenderer` 로 Canvas 를 굽지 않는다** — 이 저장소에서 첫 두 장이 다르게 나와 첫 장이
//    캐시에 박히면 그 세션 내내 틀린 패가 된다(CC-15).
//  · 캐시 열쇠 `(face, size, state, rotation, 보조 글자)` — 강·부로 네 방향과 리치 가로 포함. 화면 비트맵은 `cgImage(…scale:)` 가
//    배율마다 따로 굽는다(같은 열쇠·같은 배율이면 같은 바이트).
//  · **패 몸체만 극단 밝기**(밝은 크림) — 펠트·칸·덮개는 중간 톤이라 렌더 시험이 '그 자리에 패가 섰는가'를 잉크로 잰다.
//    `.shadow` 금지(첫 두 장이 다르다). 큐브 `RummyTileBack` 은 `.shadow` 를 쓰므로 베끼지 않았다.
//  · 글꼴은 PostScript 이름이 요청과 같은지 확인한다(조용한 대체 방지 — 伍 포함, CC-29).
//  · 그림은 직접 그린 1차 시안이다 — 렌더를 대표께 보이고 고친다.
// 임시(패 그림) — 대표 확인 전 1차 시안. 출시 전 이 표지를 grep 해 0건으로 만든다(SPEC §5.9 끝).

@MainActor
enum MahjongTileArt {
    /// 캐시 열쇠.
    nonisolated struct Key: Hashable, Sendable {
        let face: MahjongTileFace
        let size: MahjongTileSize
        let state: MahjongTileState
        /// 시계 방향 90° 회전 수(0~3).
        let rotation: Int
        let cornerLabels: Bool
    }

    nonisolated private struct BitmapKey: Hashable, Sendable {
        let key: Key
        let scale: Int
    }

    /// 지금 팔레트(코드 기본값 — 선택 JSON 이 오면 `apply(palette:)`).
    private(set) static var palette = MahjongTilePalette.standard
    private static var images: [Key: NSImage] = [:]
    private static var bitmaps: [BitmapKey: CGImage] = [:]
    /// 진단 — 처리기가 실제로 그린 횟수(시험이 캐시를 잰다). 처리기는 어느 스레드에서든 불릴 수 있다.
    nonisolated(unsafe) private(set) static var drawCount = 0

    /// 팔레트를 바꾼다(받은 JSON → `MahjongTilePalette.resolved(from:)`). 바뀌면 캐시를 비운다.
    static func apply(palette next: MahjongTilePalette) {
        guard next != palette else { return }
        palette = next
        images.removeAll()
        bitmaps.removeAll()
    }

    /// 회전을 반영한 그림 크기(pt).
    static func imageSize(_ size: MahjongTileSize, rotation: Int) -> CGSize {
        rotation % 2 == 0 ? size.size : CGSize(width: size.height, height: size.width)
    }

    /// 면 그림(벡터 — 배율마다 AppKit 이 처리기를 부른다).
    static func image(_ face: MahjongTileFace, size: MahjongTileSize, state: MahjongTileState = .normal,
                      rotation: Int = 0, cornerLabels: Bool = true) -> NSImage {
        let key = Key(face: face, size: size, state: state, rotation: ((rotation % 4) + 4) % 4,
                      cornerLabels: cornerLabels && !size.isSimplified)
        if let cached = images[key] { return cached }
        let palette = palette
        let made = NSImage(size: imageSize(size, rotation: key.rotation), flipped: true) { @Sendable _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            MahjongTileArt.drawCount += 1
            MahjongTileArt.draw(key: key, palette: palette, font: MahjongTileArt.glyphFont, in: context)
            return true
        }
        made.accessibilityDescription = face.spokenName
        images[key] = made
        return made
    }

    /// 배율 `scale` 로 구운 비트맵(sRGB). 같은 열쇠·같은 배율이면 캐시의 같은 그림.
    static func cgImage(_ face: MahjongTileFace, size: MahjongTileSize, state: MahjongTileState = .normal,
                        rotation: Int = 0, cornerLabels: Bool = true, scale: CGFloat) -> CGImage? {
        let source = image(face, size: size, state: state, rotation: rotation, cornerLabels: cornerLabels)
        let key = Key(face: face, size: size, state: state, rotation: ((rotation % 4) + 4) % 4,
                      cornerLabels: cornerLabels && !size.isSimplified)
        let bitmapKey = BitmapKey(key: key, scale: max(1, Int(scale.rounded())))
        if let cached = bitmaps[bitmapKey] { return cached }
        guard let made = rasterize(source, scale: CGFloat(bitmapKey.scale)) else { return nil }
        bitmaps[bitmapKey] = made
        return made
    }

    /// NSImage → 배율 비트맵(처리기를 그 배율로 부른다).
    static func rasterize(_ image: NSImage, scale: CGFloat) -> CGImage? {
        let width = Int((image.size.width * scale).rounded()), height = Int((image.size.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: 글꼴

    /// 요청 PostScript 이름 가운데 이 맥에 실제로 있는 첫 글꼴(이름이 같아야 쓴다 — 조용한 대체 방지).
    nonisolated static let resolvedFontName: String? = MahjongTileArtModel.preferredFontNames.first { name in
        (CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 12, nil)) as String) == name
    }

    /// 만·자패 글자 글꼴(크기 1 — 그릴 때 키운다).
    nonisolated(unsafe) static let glyphFont: CTFont = CTFontCreateWithName((resolvedFontName ?? "PingFangSC-Semibold") as CFString, 1, nil)

    /// 글꼴이 이 글자들을 모두 가졌는가.
    nonisolated static func covers(_ text: String, font: CTFont = glyphFont) -> Bool {
        let units = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) && !glyphs.contains(0)
    }

    // MARK: 그리기(처리기 안 — 위가 0 인 뒤집힌 좌표)

    nonisolated private static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let rgb = MahjongTilePalette.rgb(hex: hex) ?? (0.5, 0.5, 0.5)
        return CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    nonisolated private static func draw(key: Key, palette: MahjongTilePalette, font: CTFont, in ctx: CGContext) {
        let w = key.size.width, h = key.size.height
        ctx.saveGState()
        // 회전 — 패를 바로 세운 좌표(0,0,w,h)로 옮긴다.
        switch key.rotation {
        case 1: ctx.translateBy(x: h, y: 0); ctx.rotate(by: .pi / 2)
        case 2: ctx.translateBy(x: w, y: h); ctx.rotate(by: .pi)
        case 3: ctx.translateBy(x: 0, y: w); ctx.rotate(by: -.pi / 2)
        default: break
        }
        switch key.state {
        case .taken: ctx.setAlpha(0.42)
        case .disabled: ctx.setAlpha(0.38)
        default: break
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let body = CGRect(x: 0, y: 0, width: w, height: h)
        let radius = w * 0.14
        let layout = MahjongTileArtModel.layout(face: key.face)
        if layout.isBack {
            drawBack(body, radius: radius, palette: palette, in: ctx)
        } else {
            drawBody(body, radius: radius, palette: palette, in: ctx)
            let face = CGRect(x: w * 0.10, y: h * 0.10, width: w * 0.80, height: h * 0.74)
            drawFace(layout, face: face, size: key.size, palette: palette, font: font, in: ctx)
            if key.cornerLabels, let label = layout.cornerLabel {
                drawCorner(label, tile: body, palette: palette, in: ctx)
            }
            if key.state == .tsumogiri {
                ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius,
                                   transform: nil))
                ctx.setFillColor(CGColor(gray: 0, alpha: 0.16))
                ctx.fillPath()
            }
        }
        if key.state == .highlighted {
            ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1, dy: 1), cornerWidth: radius, cornerHeight: radius,
                               transform: nil))
            ctx.setStrokeColor(CGColor(srgbRed: 0.33, green: 0.67, blue: 1.0, alpha: 1))
            ctx.setLineWidth(2)
            ctx.strokePath()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// 몸체: 베벨(아래 8%) 위에 크림-라벤더 그라데이션, 가는 테두리(옆 패와 크림이 이어지지 않게).
    nonisolated private static func drawBody(_ body: CGRect, radius: CGFloat, palette: MahjongTilePalette, in ctx: CGContext) {
        let outer = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(outer)
        ctx.setFillColor(color(palette.bevel))
        ctx.fillPath()
        let top = CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height * 0.92)
        let topPath = CGPath(roundedRect: top, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(topPath)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [color(palette.bodyTop), color(palette.bodyBottom)] as CFArray,
                                     locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top.minY), end: CGPoint(x: 0, y: top.maxY), options: [])
        }
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
        ctx.setStrokeColor(color("#8E84B4"))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    /// 뒷면: 짙은 남색 그라데이션 + 분홍 테두리 + 가운데 작은 고리.
    nonisolated private static func drawBack(_ body: CGRect, radius: CGFloat, palette: MahjongTilePalette, in ctx: CGContext) {
        let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [color(palette.backTop), color(palette.backBottom)] as CFArray,
                                     locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        }
        ctx.restoreGState()
        let rim = max(1, body.width * 0.07)
        ctx.addPath(CGPath(roundedRect: body.insetBy(dx: rim / 2, dy: rim / 2), cornerWidth: radius, cornerHeight: radius,
                           transform: nil))
        ctx.setStrokeColor(color(palette.backRim))
        ctx.setLineWidth(rim)
        ctx.strokePath()
        let ring = body.width * 0.16
        ctx.addEllipse(in: CGRect(x: body.midX - ring, y: body.midY - ring, width: ring * 2, height: ring * 2))
        ctx.setStrokeColor(color(palette.backRim, alpha: 0.8))
        ctx.setLineWidth(max(1, body.width * 0.05))
        ctx.strokePath()
    }

    nonisolated private static func drawFace(_ layout: MahjongTileLayout, face: CGRect, size: MahjongTileSize,
                                             palette: MahjongTilePalette, font: CTFont, in ctx: CGContext) {
        func point(_ p: MahjongArtPoint) -> CGPoint {
            CGPoint(x: face.minX + face.width * p.x, y: face.minY + face.height * p.y)
        }
        // 통 — 바깥 고리 + 몸체색 틈 + 가운데 점.
        for pip in layout.pips {
            let c = point(pip.center), r = face.width * pip.radius
            ctx.setFillColor(color(palette.hex(pip.ink)))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            let gap = r * 0.64
            ctx.setFillColor(color(palette.bodyTop))
            ctx.fillEllipse(in: CGRect(x: c.x - gap, y: c.y - gap, width: gap * 2, height: gap * 2))
            let dot = r * 0.34
            ctx.setFillColor(color(palette.hex(pip.ink)))
            ctx.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
        }
        // 삭 — 둥근 막대 + 가운데 마디 줄. 작은 크기는 막대를 가늘게(사이를 넓힌다).
        let stickWidth = face.width * (size.isSimplified ? 0.08 : 0.115)
        for stick in layout.sticks {
            let c = point(stick.center), length = face.height * stick.length
            let rect = CGRect(x: c.x - stickWidth / 2, y: c.y - length / 2, width: stickWidth, height: length)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: stickWidth / 2, cornerHeight: stickWidth / 2, transform: nil))
            ctx.setFillColor(color(palette.hex(stick.ink)))
            ctx.fillPath()
            ctx.setFillColor(color(palette.bodyTop))
            ctx.fill(CGRect(x: rect.minX, y: c.y - max(0.5, length * 0.04), width: rect.width, height: max(1, length * 0.08)))
        }
        if layout.sprout { drawSprout(face: face, palette: palette, in: ctx) }
        if layout.hakuFrame {
            let frame = face.insetBy(dx: face.width * 0.16, dy: face.height * 0.12)
            ctx.addPath(CGPath(roundedRect: frame, cornerWidth: frame.width * 0.2, cornerHeight: frame.width * 0.2,
                               transform: nil))
            ctx.setStrokeColor(color(palette.hex(.lavender)))
            ctx.setLineWidth(max(1, face.width * 0.09))
            ctx.strokePath()
        }
        for glyph in layout.glyphs {
            drawGlyph(glyph.text, center: point(glyph.center), height: face.height * glyph.size,
                      color: color(palette.hex(glyph.ink)), font: font, in: ctx)
        }
        if layout.goldDot {
            let r = face.width * 0.09
            let c = CGPoint(x: face.maxX - r * 0.6, y: face.minY + r * 0.4)
            ctx.setFillColor(color(palette.hex(.gold)))
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
    }

    /// 1삭 — 우리 모양: 굵은 대 한 마디 + 잎 둘 + 빨간 점(새싹).
    nonisolated private static func drawSprout(face: CGRect, palette: MahjongTilePalette, in ctx: CGContext) {
        let green = color(palette.hex(.green))
        let stemWidth = face.width * 0.16
        let stem = CGRect(x: face.midX - stemWidth / 2, y: face.minY + face.height * 0.42, width: stemWidth,
                          height: face.height * 0.52)
        ctx.addPath(CGPath(roundedRect: stem, cornerWidth: stemWidth / 2, cornerHeight: stemWidth / 2, transform: nil))
        ctx.setFillColor(green)
        ctx.fillPath()
        ctx.setFillColor(color(palette.bodyTop))
        ctx.fill(CGRect(x: stem.minX, y: stem.midY, width: stem.width, height: max(1, face.height * 0.035)))
        for side in [-1.0, 1.0] {
            let leaf = CGRect(x: -face.width * 0.2, y: -face.height * 0.075, width: face.width * 0.4, height: face.height * 0.15)
            var transform = CGAffineTransform(translationX: face.midX + side * face.width * 0.2, y: face.minY + face.height * 0.36)
                .rotated(by: side * -0.55)
            ctx.addPath(CGPath(ellipseIn: leaf, transform: &transform))
            ctx.setFillColor(green)
            ctx.fillPath()
        }
        let r = face.width * 0.1
        let c = CGPoint(x: face.midX, y: face.minY + face.height * 0.18)
        ctx.setFillColor(color(palette.hex(.red)))
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    /// 글자 한 자를 (center) 에 높이 `height` 로 — 뒤집힌 좌표라 글자 행렬을 위아래로 뒤집는다.
    nonisolated private static func drawGlyph(_ text: String, center: CGPoint, height: CGFloat, color: CGColor,
                                              font: CTFont, in ctx: CGContext) {
        let sized = CTFontCreateCopyWithAttributes(font, height, nil, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): sized,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y + bounds.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// 모서리 보조 글자(수패 1~9 · 자패 동남서북백발중).
    nonisolated private static func drawCorner(_ label: String, tile: CGRect, palette: MahjongTilePalette, in ctx: CGContext) {
        let size = tile.height * 0.15
        let font = CTFontCreateWithName("AppleSDGothicNeo-Bold" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(palette.ink, alpha: 0.72),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: tile.minX + tile.width * 0.07 - bounds.minX, y: tile.minY + tile.height * 0.04 + bounds.maxY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

// MARK: - SwiftUI 패 한 장

/// 패 한 장(손패·결과·작은 조각). 강·상대 띠는 띠마다 Canvas 한 장으로 `MahjongTileStrip` 이 그린다.
struct MahjongTileView: View {
    let face: MahjongTileFace
    var size: MahjongTileSize = .hand
    var state: MahjongTileState = .normal
    var rotation: Int = 0
    var cornerLabels: Bool = true

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let frame = MahjongTileArt.imageSize(size, rotation: rotation)
        Group {
            if let image = MahjongTileArt.cgImage(face, size: size, state: state, rotation: rotation,
                                                  cornerLabels: cornerLabels, scale: displayScale) {
                Image(decorative: image, scale: CGFloat(max(1, Int(displayScale.rounded()))))
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: frame.width, height: frame.height)
        .accessibilityElement()
        .accessibilityLabel(face.spokenName)
    }
}

/// 띠 한 장에 놓을 패 하나(띠 좌표 pt).
struct MahjongStripTile: Hashable {
    let face: MahjongTileFace
    let size: MahjongTileSize
    var state: MahjongTileState = .normal
    var rotation: Int = 0
    let origin: CGPoint
}

/// 강·상대 손 띠·도라 판 — **띠마다 Canvas 한 장**(UX:208). 각 패는 캐시 비트맵을 `context.draw` 로 놓는다.
struct MahjongTileStrip: View {
    let tiles: [MahjongStripTile]
    let size: CGSize
    var cornerLabels: Bool = true
    var accessibilityText: String = ""

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let scale = displayScale
        let images: [(CGImage, CGRect)] = tiles.compactMap { tile in
            guard let image = MahjongTileArt.cgImage(tile.face, size: tile.size, state: tile.state, rotation: tile.rotation,
                                                     cornerLabels: cornerLabels, scale: scale)
            else { return nil }
            return (image, CGRect(origin: tile.origin, size: MahjongTileArt.imageSize(tile.size, rotation: tile.rotation)))
        }
        Canvas { context, _ in
            for (image, rect) in images {
                context.draw(Image(decorative: image, scale: CGFloat(max(1, Int(scale.rounded())))).resizable()
                    .interpolation(.high), in: rect)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }
}
