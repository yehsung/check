#if os(iOS)
import CheckCore
import CoreText
import SwiftUI
import UIKit

// 아잉 마작 폰 패 그림(1.0.18). 그리기 식(몸체 · 뒷면 · 통 · 삭 · 1삭 새싹 · 글자 · 모서리 글자)은 맥 `MahjongTileArt`
// (Sources/check/MahjongTileView.swift)를 **글자 그대로** 옮겼다 — 배치는 코어 `MahjongTileArtModel`(맥 · 폰 공용 순수 값).
// 다른 것은 굽는 자리뿐이다: 맥 `NSImage(flipped:)` → 폰 `UIGraphicsImageRenderer`(위가 0 인 같은 좌표).
// 캐시 열쇠 `(face, size, state, rotation, 보조 글자, 배율)`. 받은 팔레트(Storage)는 쓰지 않는다 — 코드 팔레트(대표가 고른 'A 지금 그대로').
// `.shadow` 금지 · 실행 중 `ImageRenderer` 금지(맥과 같은 까닭 — 첫 두 장이 다르다).

@MainActor
enum GamesMahjongTileArt {
    nonisolated struct Key: Hashable, Sendable {
        let face: MahjongTileFace
        let size: MahjongTileSize
        let state: MahjongTileState
        let rotation: Int
        let cornerLabels: Bool
        let back: MahjongTileBackScheme
        let oneSou: MahjongOneSouMotif
        let corner: MahjongCornerLabelStyle
        let scale: Int

        init(face: MahjongTileFace, size: MahjongTileSize, state: MahjongTileState, rotation: Int, cornerLabels: Bool,
             style: MahjongTileArtStyle, scale: Int) {
            self.face = face
            self.size = size
            self.state = state
            self.rotation = ((rotation % 4) + 4) % 4
            self.cornerLabels = cornerLabels && !size.isSimplified
            back = style.backScheme
            oneSou = style.oneSouMotif
            corner = style.cornerLabel
            self.scale = max(1, scale)
        }
    }

    private static var images: [Key: CGImage] = [:]

    static func imageSize(_ size: MahjongTileSize, rotation: Int) -> CGSize {
        rotation % 2 == 0 ? size.size : CGSize(width: size.height, height: size.width)
    }

    /// 배율 `scale` 로 구운 비트맵. 같은 열쇠면 캐시의 같은 그림.
    static func cgImage(_ face: MahjongTileFace, size: MahjongTileSize, state: MahjongTileState = .normal, rotation: Int = 0,
                        cornerLabels: Bool = true, style: MahjongTileArtStyle = .chosen, scale: CGFloat) -> CGImage? {
        let key = Key(face: face, size: size, state: state, rotation: rotation, cornerLabels: cornerLabels, style: style,
                      scale: Int(scale.rounded()))
        if let cached = images[key] { return cached }
        let palette = MahjongTilePalette.effective(back: style.backScheme, delivered: nil)
        let format = UIGraphicsImageRendererFormat()
        format.scale = CGFloat(key.scale)
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: imageSize(size, rotation: key.rotation), format: format)
        let image = renderer.image { context in
            draw(key: key, palette: palette, font: glyphFont, in: context.cgContext)
        }
        guard let cg = image.cgImage else { return nil }
        if images.count > 600 { images.removeAll() }
        images[key] = cg
        return cg
    }

    // MARK: 글꼴

    /// 요청 PostScript 이름 가운데 이 기기에 실제로 있는 첫 글꼴(이름이 같아야 쓴다 — 조용한 대체 방지).
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
            drawFace(layout, face: face, size: key.size, oneSou: key.oneSou, palette: palette, font: font, in: ctx)
            if key.cornerLabels, let label = key.corner.label(layout, face: key.face) {
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
                                             oneSou: MahjongOneSouMotif, palette: MahjongTilePalette, font: CTFont,
                                             in ctx: CGContext) {
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
        if layout.sprout {
            switch oneSou {
            case .sprout: drawSprout(face: face, palette: palette, in: ctx)
            case .aingFace: drawAingFace(face: face, simplified: size.isSimplified, in: ctx)
            case .bambooNode: drawBambooNode(face: face, palette: palette, in: ctx)
            }
        }
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

    /// 1삭 선택지 B — 아잉이 얼굴 느낌의 둥근 얼굴(코드 도형: 라벤더 몸 · 작은 팔 · 눈 둘 · 볼 · 입).
    /// 색은 저장소 아잉이(aing-neutral.png)의 결을 참고만 했다. 작은 크기(24×32 이하)는 눈 반짝임을 뺀다.
    nonisolated private static func drawAingFace(face: CGRect, simplified: Bool, in ctx: CGContext) {
        let fw = face.width, fh = face.height
        let center = CGPoint(x: face.midX, y: face.minY + fh * 0.56)
        let body = CGRect(x: center.x - fw * 0.43, y: center.y - fh * 0.35, width: fw * 0.86, height: fh * 0.70)
        let line = color("#7462CF")
        let lineWidth = max(0.8, fw * 0.035)
        // 팔 — 몸 양옆 아래(몸이 덮는다).
        for side in [-1.0, 1.0] {
            let arm = CGRect(x: -fw * 0.09, y: -fh * 0.07, width: fw * 0.18, height: fh * 0.14)
            var transform = CGAffineTransform(translationX: center.x + side * fw * 0.40, y: center.y + fh * 0.12)
                .rotated(by: side * 0.5)
            let path = CGPath(ellipseIn: arm, transform: &transform)
            ctx.addPath(path)
            ctx.setFillColor(color("#A898EF"))
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(line)
            ctx.setLineWidth(lineWidth)
            ctx.strokePath()
        }
        // 몸 — 위 밝고 아래 짙은 라벤더.
        ctx.saveGState()
        ctx.addEllipse(in: body)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: [color("#D3C9FF"), color("#9D8DEC")] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.minY), end: CGPoint(x: 0, y: body.maxY), options: [])
        }
        ctx.restoreGState()
        ctx.addEllipse(in: body)
        ctx.setStrokeColor(line)
        ctx.setLineWidth(lineWidth)
        ctx.strokePath()
        // 볼.
        ctx.setFillColor(color("#FF8FB8", alpha: 0.85))
        for side in [-1.0, 1.0] {
            let c = CGPoint(x: center.x + side * fw * 0.27, y: center.y + fh * 0.08)
            ctx.fillEllipse(in: CGRect(x: c.x - fw * 0.075, y: c.y - fh * 0.04, width: fw * 0.15, height: fh * 0.08))
        }
        // 눈 — 짙은 밤색 + 반짝임.
        for side in [-1.0, 1.0] {
            let c = CGPoint(x: center.x + side * fw * 0.165, y: center.y - fh * 0.04)
            ctx.setFillColor(color("#3B2522"))
            ctx.fillEllipse(in: CGRect(x: c.x - fw * 0.065, y: c.y - fh * 0.075, width: fw * 0.13, height: fh * 0.15))
            if !simplified {
                let r = fw * 0.03
                ctx.setFillColor(color("#FFFFFF"))
                ctx.fillEllipse(in: CGRect(x: c.x + fw * 0.005 - r, y: c.y - fh * 0.035 - r, width: r * 2, height: r * 2))
            }
        }
        // 입 — 위가 평평하고 아래가 둥근 웃는 입.
        let mouthTop = center.y + fh * 0.07, half = fw * 0.075
        let mouth = CGMutablePath()
        mouth.move(to: CGPoint(x: center.x - half, y: mouthTop))
        mouth.addLine(to: CGPoint(x: center.x + half, y: mouthTop))
        mouth.addQuadCurve(to: CGPoint(x: center.x - half, y: mouthTop), control: CGPoint(x: center.x, y: mouthTop + fh * 0.13))
        mouth.closeSubpath()
        ctx.addPath(mouth)
        ctx.setFillColor(color("#D63D5C"))
        ctx.fillPath()
    }

    /// 1삭 선택지 C — 굵은 대나무 한 마디(통 하나 + 위·아래 마디 띠 + 왼쪽 밝은 줄). 가장 단순.
    nonisolated private static func drawBambooNode(face: CGRect, palette: MahjongTilePalette, in ctx: CGContext) {
        let fw = face.width, fh = face.height
        let width = fw * 0.36
        let tube = CGRect(x: face.midX - width / 2, y: face.minY + fh * 0.08, width: width, height: fh * 0.84)
        ctx.addPath(CGPath(roundedRect: tube, cornerWidth: width * 0.3, cornerHeight: width * 0.3, transform: nil))
        ctx.setFillColor(color(palette.hex(.green)))
        ctx.fillPath()
        // 왼쪽 밝은 줄(둥근 통 느낌).
        let shine = CGRect(x: tube.minX + width * 0.18, y: tube.minY + fh * 0.12, width: width * 0.16, height: tube.height - fh * 0.24)
        ctx.addPath(CGPath(roundedRect: shine, cornerWidth: shine.width / 2, cornerHeight: shine.width / 2, transform: nil))
        ctx.setFillColor(color("#8DE6C6"))
        ctx.fillPath()
        // 마디 띠 — 통보다 조금 넓은 짙은 초록.
        let band = max(1.5, fh * 0.07)
        for y in [tube.minY + fh * 0.03, tube.maxY - fh * 0.03 - band] {
            let rect = CGRect(x: tube.minX - width * 0.1, y: y, width: width * 1.2, height: band)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: band / 2, cornerHeight: band / 2, transform: nil))
            ctx.setFillColor(color("#0B7D5B"))
            ctx.fillPath()
        }
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

// MARK: - SwiftUI

/// 패 한 장(손패 · 결과 · 작은 조각). `display` 를 주면 그 크기로 그린다(가로 판이 줄여 그릴 때 — 그림은 원래 크기 × 배율로 굽는다).
struct GamesMahjongTileView: View {
    let face: MahjongTileFace
    var size: MahjongTileSize = .hand
    var state: MahjongTileState = .normal
    var rotation: Int = 0
    var cornerLabels: Bool = true
    var display: CGSize? = nil

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let natural = GamesMahjongTileArt.imageSize(size, rotation: rotation)
        let frame = display ?? natural
        // 줄여 그리면 그만큼 높은 배율로 굽는다(흐리지 않게) — 늘려 그리면 그만큼 더.
        let factor = max(frame.width / natural.width, 0.1)
        Group {
            if let image = GamesMahjongTileArt.cgImage(face, size: size, state: state, rotation: rotation, cornerLabels: cornerLabels,
                                                       scale: max(1, (displayScale * factor).rounded(.up))) {
                Image(decorative: image, scale: 1)
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

#endif
