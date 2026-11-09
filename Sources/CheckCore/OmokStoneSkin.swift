import CoreGraphics
import Foundation

// MARK: - 오목알 스킨(v0.3.81 맥 먼저 — 스킨 능력 번호 1)
//
// 대표 결정(결재함 원문 — 되묻지 않는다):
//   원문(서버 확인) "2. 이거 오목알 스킨 추가하자. 다만 꾸미더라도 이게 흑돌인지 백돌인지는 명확하게 알 수 있게 해야할듯"
//   받는 방식 #d_UVBJ8vJua1jD "상점 루비 (스킨마다 100)" · 보이는 범위 #d_RR2dyBIHDMW5 "상대에게도 보임"
//   3차 #d_TFKnfZL40Ax6 "2, 4, 5, 7, 6 채택" → 네온 · 주사위 · 고양이 · 흑백 아잉이 · 다이아 컷 + 픽셀(1차부터 통과).
//   3차 원칙(대표 "픽셀은 딱 내가 말하는 조건에 만족하는 디자인"): 돌 **생김새 전체**를 한 화풍으로 바꾸되 몸 바탕은
//   흑 = 짙은 무채색 · 백 = 밝은 무채색만. 색은 눈 · 테처럼 작은 곳만 — 일반 돌 · 다른 스킨과 섞여도 흑백이 갈린다.
//
// 그림은 시안 도구(omok-skins/skins3.swift — 섞인 판 흑백 대비 5.2~15.3배, 기준 4.5배)와 **같은 식**이다. 좌표는 y 가 아래로 자라는
// CGContext(SwiftUI `GraphicsContext.withCGContext` 와 같은 방향) · 빛은 왼쪽 위. 서버 정본은 20261111130000_omok_skins.sql
// (정의표 omok_skin_defs · omok_skins_state · buy_omok_skin · set_omok_skin · 대국/관전 match.black_skin · white_skin).

/// 오목알 스킨 하나. `rawValue` = 서버 id(정의표 `omok_skin_defs().id` 와 같은 글자). 모르는 id 는 nil — 일반 돌로 그린다.
package nonisolated enum OmokStoneSkin: String, CaseIterable, Sendable, Equatable {
    case neon, dice, cat, aing, diamond, pixel

    /// 이 빌드가 그릴 수 있는 스킨의 능력 번호(서버 `omok_skin_defs().min_protocol` ≤ 이 값인 스킨만 상점에 온다).
    /// 새 스킨을 더하면 그 스킨의 min_protocol 과 함께 올린다(번호는 누적 — 1 은 이 여섯).
    package static let protocolVersion = 1

    /// 서버 id → 스킨. 정확히 그 글자만(공백 · 대소문자 봐주지 않는다). 그 밖 · nil 은 nil(= 일반 돌).
    package init?(wireValue: String?) {
        guard let wireValue, let skin = Self(rawValue: wireValue) else { return nil }
        self = skin
    }

    /// 화면 이름(서버 정의표의 name 과 같은 글자 — 서버가 이름을 안 실어도 이 값으로 선다).
    package var displayName: String {
        switch self {
        case .neon: return "네온"
        case .dice: return "주사위"
        case .cat: return "고양이"
        case .aing: return "흑백 아잉이"
        case .diamond: return "다이아 컷"
        case .pixel: return "픽셀"
        }
    }

    /// 돌 하나를 그린다(그림자 포함). `center` · `radius` 는 판 좌표(돌 반지름 = 칸 × 0.46), `seed` 는 돌마다 다른 모양
    /// (주사위 눈 · 아잉이 표정)을 고르는 값 — 같은 자리 같은 값이면 언제나 같은 모양이다(판을 다시 그려도 안 흔들린다).
    package func draw(in ctx: CGContext, center: CGPoint, radius: CGFloat, black: Bool, seed: Int) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        switch self {
        case .neon: OmokStoneArt.neon(ctx, center, radius, black, seed)
        case .dice: OmokStoneArt.dice(ctx, center, radius, black, seed)
        case .cat: OmokStoneArt.cat(ctx, center, radius, black, seed)
        case .aing: OmokStoneArt.aingMono(ctx, center, radius, black, seed)
        case .diamond: OmokStoneArt.diamondCut(ctx, center, radius, black, seed)
        case .pixel: OmokStoneArt.pixel(ctx, center, radius, black, seed)
        }
    }
}

/// 한 판의 흑 · 백 스킨(서버 `match.black_skin` · `white_skin`). nil = 일반 돌. 모르는 id 는 일반 돌로 접는다.
package nonisolated struct OmokStoneSkins: Equatable, Sendable {
    package var black: OmokStoneSkin?
    package var white: OmokStoneSkin?

    package init(black: OmokStoneSkin? = nil, white: OmokStoneSkin? = nil) {
        self.black = black
        self.white = white
    }

    /// 서버 글자 둘에서.
    package init(blackWire: String?, whiteWire: String?) {
        self.init(black: OmokStoneSkin(wireValue: blackWire), white: OmokStoneSkin(wireValue: whiteWire))
    }

    /// 한 색만 스킨(AI 판 — 사람 쪽만 내 스킨, AI 는 일반 돌).
    package init(color isBlack: Bool, skin: OmokStoneSkin?) {
        self.init(black: isBlack ? skin : nil, white: isBlack ? nil : skin)
    }

    package static let plain = OmokStoneSkins()

    package func skin(black isBlack: Bool) -> OmokStoneSkin? { isBlack ? black : white }

    /// 판 자리 → 모양 씨앗(같은 자리면 언제나 같은 값).
    package static func seed(x: Int, y: Int) -> Int { x &* 31 &+ y &* 17 &+ 5 }
}

/// 스킨 그림 식(시안 도구와 같은 식 — 이름도 같다). 일반 돌(`plain`)은 상점 미리보기의 '일반' 칸이 쓴다.
package nonisolated enum OmokStoneArt {
    static var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }

    static func circlePath(_ c: CGPoint, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil) }

    static func fill(_ ctx: CGContext, _ p: CGPath, _ col: CGColor) { ctx.addPath(p); ctx.setFillColor(col); ctx.fillPath() }

    static func stroke(_ ctx: CGContext, _ p: CGPath, _ col: CGColor, _ w: CGFloat) { ctx.addPath(p); ctx.setStrokeColor(col); ctx.setLineWidth(w); ctx.strokePath() }

    static func gradientIn(_ ctx: CGContext, _ p: CGPath, _ stops: [(CGFloat, CGColor)], from hl: CGPoint, end: CGFloat) {
        let grad = CGGradient(colorsSpace: sRGB, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        ctx.drawRadialGradient(grad, startCenter: hl, startRadius: 0, endCenter: hl, endRadius: end, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    static func dropShadow(_ ctx: CGContext, _ p: CGPath, _ dx: CGFloat, _ dy: CGFloat, _ a: Double) {
        ctx.saveGState(); ctx.translateBy(x: dx, y: dy); fill(ctx, p, W(0, a)); ctx.restoreGState()
    }
    /// 일반 돌과 같은 광택 바탕을 임의 윤곽에.

    static func glossBody(_ ctx: CGContext, _ p: CGPath, _ c: CGPoint, _ r: CGFloat, _ black: Bool) {
        let hl = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4)
        if black { gradientIn(ctx, p, [(0, W(0.42)), (1, W(0.05))], from: hl, end: r * 1.5) }
        else { gradientIn(ctx, p, [(0, W(1.0)), (1, W(0.80))], from: hl, end: r * 1.6); stroke(ctx, p, W(0, 0.22), 0.8) }
    }

    static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGRect { CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry) }

    static func neon(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ black: Bool, _: Int) {
        let tube = H(0x3CEBFF)
        for (w, a) in [(0.40, 0.08), (0.26, 0.13), (0.14, 0.22)] as [(CGFloat, Double)] {
            ctx.setStrokeColor(H(0x3CEBFF, a)); ctx.setLineWidth(r * w); ctx.strokeEllipse(in: ellipse(c, r * 0.96, r * 0.96))
        }
        let body = circlePath(c, r)
        if black {
            gradientIn(ctx, body, [(0, W(0.13)), (1, W(0.01))], from: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), end: r * 1.4)
            ctx.saveGState(); ctx.addPath(body); ctx.clip()
            ctx.setStrokeColor(H(0x3CEBFF, 0.16)); ctx.setLineWidth(r * 0.22); ctx.strokeEllipse(in: ellipse(c, r * 0.84, r * 0.84))
            ctx.restoreGState()
            ctx.setStrokeColor(tube); ctx.setLineWidth(r * 0.075); ctx.strokeEllipse(in: ellipse(c, r * 0.84, r * 0.84))
            ctx.setStrokeColor(W(1, 0.9)); ctx.setLineWidth(r * 0.022); ctx.strokeEllipse(in: ellipse(c, r * 0.84, r * 0.84))
            // 관에 비친 작은 반짝
            ctx.setFillColor(W(1, 0.55)); ctx.fillEllipse(in: ellipse(CGPoint(x: c.x - r * 0.30, y: c.y - r * 0.34), r * 0.10, r * 0.06))
        } else {
            gradientIn(ctx, body, [(0, W(1.0)), (0.6, W(0.99)), (1, H(0xD4F8FF))], from: CGPoint(x: c.x - r * 0.2, y: c.y - r * 0.25), end: r * 1.25)
            ctx.setStrokeColor(tube); ctx.setLineWidth(r * 0.075); ctx.strokeEllipse(in: ellipse(c, r * 0.93, r * 0.93))
            ctx.setStrokeColor(W(1, 0.95)); ctx.setLineWidth(r * 0.022); ctx.strokeEllipse(in: ellipse(c, r * 0.93, r * 0.93))
        }
    }

    static func dice(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ black: Bool, _ i: Int) {
        let h = r * 0.86, cr = r * 0.30
        let p = CGPath(roundedRect: ellipse(c, h, h), cornerWidth: cr, cornerHeight: cr, transform: nil)
        dropShadow(ctx, p, r * 0.06, r * 0.14, 0.25)
        glossBody(ctx, p, c, r, black)
        let inner = CGPath(roundedRect: ellipse(c, h * 0.86, h * 0.86), cornerWidth: cr * 0.8, cornerHeight: cr * 0.8, transform: nil)
        stroke(ctx, inner, black ? W(1, 0.10) : W(0, 0.06), r * 0.03)
        let face = 1 + Int(hash(i, 3) * 6) % 6
        let u = h * 0.50
        let spots: [[(CGFloat, CGFloat)]] = [[], [(0, 0)], [(-1, -1), (1, 1)], [(-1, -1), (0, 0), (1, 1)], [(-1, -1), (1, -1), (-1, 1), (1, 1)],
                                             [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)]]
        let pr = r * (face == 1 ? 0.24 : 0.145)
        for s in spots[face] {
            let q = CGPoint(x: c.x + s.0 * u, y: c.y + s.1 * u)
            ctx.setFillColor(black ? W(0.96) : W(0.08)); ctx.fillEllipse(in: ellipse(q, pr, pr))
        }
    }

    static func catShape(_ c: CGPoint, _ r: CGFloat) -> (body: CGPath, ears: [CGPath], center: CGPoint) {
        let bc = CGPoint(x: c.x, y: c.y + r * 0.09), br = r * 0.88
        var shape: CGPath = circlePath(bc, br)
        var inner: [CGPath] = []
        for s in [-1.0, 1.0] as [CGFloat] {
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: bc.x + s * r * 0.24, y: bc.y - r * 0.70)); tri.addLine(to: CGPoint(x: bc.x + s * r * 0.70, y: bc.y - r * 1.06))
            tri.addLine(to: CGPoint(x: bc.x + s * r * 0.84, y: bc.y - r * 0.32)); tri.closeSubpath()
            let round = tri.copy(strokingWithWidth: r * 0.14, lineCap: .round, lineJoin: .round, miterLimit: 1)
            shape = shape.union(tri).union(round)
            let it = CGMutablePath()
            it.move(to: CGPoint(x: bc.x + s * r * 0.38, y: bc.y - r * 0.66)); it.addLine(to: CGPoint(x: bc.x + s * r * 0.67, y: bc.y - r * 0.92))
            it.addLine(to: CGPoint(x: bc.x + s * r * 0.75, y: bc.y - r * 0.48)); it.closeSubpath()
            inner.append(it)
        }
        return (shape, inner, bc)
    }

    static func cat(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ black: Bool, _: Int) {
        let (p, ears, bc) = catShape(c, r)
        dropShadow(ctx, p, r * 0.06, r * 0.14, 0.25)
        glossBody(ctx, p, c, r, black)
        for e in ears { fill(ctx, e, black ? H(0x4B3542) : H(0xF4B6C6)) }
        for s in [-1.0, 1.0] as [CGFloat] {
            let e = CGPoint(x: bc.x + s * r * 0.36, y: bc.y - r * 0.12)
            ctx.setFillColor(black ? H(0xF2CF3A) : H(0x4F9FE6)); ctx.fillEllipse(in: ellipse(e, r * 0.17, r * 0.19))
            ctx.setFillColor(W(0.04)); ctx.fillEllipse(in: ellipse(e, r * 0.055, r * 0.16))
            ctx.setFillColor(W(1, 0.95)); ctx.fillEllipse(in: ellipse(CGPoint(x: e.x - r * 0.06, y: e.y - r * 0.08), r * 0.045, r * 0.045))
            // 수염
            ctx.setStrokeColor(black ? W(0.78, 0.85) : W(0.40, 0.8)); ctx.setLineWidth(r * 0.03); ctx.setLineCap(.round)
            for k in 0..<2 {
                let y0 = bc.y + r * (0.20 + 0.11 * CGFloat(k))
                ctx.move(to: CGPoint(x: bc.x + s * r * 0.42, y: y0)); ctx.addLine(to: CGPoint(x: bc.x + s * r * 0.86, y: y0 - r * (0.10 - 0.12 * CGFloat(k)))); ctx.strokePath()
            }
        }
        // 코 · 입(ω)
        let n = CGPoint(x: bc.x, y: bc.y + r * 0.16)
        ctx.setFillColor(black ? H(0xE38AA6) : H(0xF08AA8)); ctx.beginPath()
        ctx.move(to: CGPoint(x: n.x - r * 0.08, y: n.y - r * 0.05)); ctx.addLine(to: CGPoint(x: n.x + r * 0.08, y: n.y - r * 0.05)); ctx.addLine(to: CGPoint(x: n.x, y: n.y + r * 0.05)); ctx.closePath(); ctx.fillPath()
        ctx.setStrokeColor(black ? W(0.75) : W(0.25)); ctx.setLineWidth(r * 0.035); ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: n.x - r * 0.07, y: n.y + r * 0.08), radius: r * 0.07, startAngle: 0, endAngle: .pi, clockwise: false); ctx.strokePath()
        ctx.addArc(center: CGPoint(x: n.x + r * 0.07, y: n.y + r * 0.08), radius: r * 0.07, startAngle: 0, endAngle: .pi, clockwise: false); ctx.strokePath()
    }

    static func aingShape(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        let body = CGMutablePath(), n = 96
        let o = CGPoint(x: c.x, y: c.y + r * 0.05)
        for k in 0...n {
            let t = CGFloat(k) / CGFloat(n) * 2 * .pi
            let q = CGPoint(x: o.x + cos(t) * r * 0.86 * (1 + 0.10 * sin(t)), y: o.y + sin(t) * r * 0.90)   // sin>0 = 아래 → 아래가 넓은 달걀
            k == 0 ? body.move(to: q) : body.addLine(to: q)
        }
        body.closeSubpath()
        var shape: CGPath = body
        for s in [-1.0, 1.0] as [CGFloat] {
            var tr = CGAffineTransform(translationX: o.x + s * r * 0.86, y: o.y + r * 0.30).rotated(by: s * 0.5)
            let arm = CGPath(ellipseIn: ellipse(.zero, r * 0.13, r * 0.22), transform: &tr)
            shape = shape.union(arm)
        }
        return shape
    }

    static func aingMono(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ black: Bool, _ i: Int) {
        let p = aingShape(c, r)
        dropShadow(ctx, p, r * 0.06, r * 0.14, 0.25)
        glossBody(ctx, p, c, r, black)
        let mood = Int(hash(i, 9) * 5) % 5          // 0 기본 · 1 웃음 · 2 윙크 · 3 놀람 · 4 졸림
        let ey = c.y - r * 0.06, ex = r * 0.34
        let line = black ? W(0.96) : H(0x2A1C26)
        func roundEye(_ e: CGPoint) {
            if black {   // 까만 몸엔 흰자 + 검은 눈동자
                ctx.setFillColor(W(0.97)); ctx.fillEllipse(in: ellipse(e, r * 0.16, r * 0.19))
                ctx.setFillColor(W(0.05)); ctx.fillEllipse(in: ellipse(CGPoint(x: e.x, y: e.y + r * 0.02), r * 0.10, r * 0.13))
            } else {
                ctx.setFillColor(H(0x2A1C26)); ctx.fillEllipse(in: ellipse(e, r * 0.14, r * 0.17))
            }
            ctx.setFillColor(W(1, 0.95)); ctx.fillEllipse(in: ellipse(CGPoint(x: e.x - r * 0.04, y: e.y - r * 0.06), r * 0.05, r * 0.05))
        }
        func arcEye(_ e: CGPoint) {   // ^ 웃는 눈
            ctx.setStrokeColor(line); ctx.setLineWidth(r * 0.075); ctx.setLineCap(.round)
            ctx.addArc(center: CGPoint(x: e.x, y: e.y + r * 0.06), radius: r * 0.12, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false); ctx.strokePath()
        }
        func flatEye(_ e: CGPoint) {
            ctx.setStrokeColor(line); ctx.setLineWidth(r * 0.07); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: e.x - r * 0.12, y: e.y + r * 0.02)); ctx.addLine(to: CGPoint(x: e.x + r * 0.12, y: e.y + r * 0.02)); ctx.strokePath()
        }
        let L = CGPoint(x: c.x - ex, y: ey), Rr = CGPoint(x: c.x + ex, y: ey)
        switch mood {
        case 1: arcEye(L); arcEye(Rr)
        case 2: roundEye(L); arcEye(Rr)
        case 4: flatEye(L); flatEye(Rr)
        default: roundEye(L); roundEye(Rr)
        }
        // 볼터치
        ctx.setFillColor(black ? H(0xD9779E, 0.55) : H(0xFF9BB5, 0.60))
        for s in [-1.0, 1.0] as [CGFloat] { ctx.fillEllipse(in: ellipse(CGPoint(x: c.x + s * r * 0.55, y: c.y + r * 0.16), r * 0.14, r * 0.08)) }
        // 입 — 가운데(판 표시 자리)는 비우고 조금 아래
        let m = CGPoint(x: c.x, y: c.y + r * 0.30)
        switch mood {
        case 3:
            ctx.setFillColor(black ? W(0.96) : H(0x2A1C26)); ctx.fillEllipse(in: ellipse(m, r * 0.08, r * 0.10))
        case 4:
            ctx.setStrokeColor(line); ctx.setLineWidth(r * 0.06); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: m.x - r * 0.06, y: m.y)); ctx.addLine(to: CGPoint(x: m.x + r * 0.06, y: m.y)); ctx.strokePath()
        default:   // 벌린 웃음(반달 + 혀)
            ctx.saveGState()
            ctx.beginPath(); ctx.move(to: CGPoint(x: m.x - r * 0.15, y: m.y - r * 0.05))
            ctx.addArc(center: CGPoint(x: m.x, y: m.y - r * 0.05), radius: r * 0.15, startAngle: .pi, endAngle: 0, clockwise: true); ctx.closePath()
            ctx.setFillColor(black ? W(0.96) : H(0x4A2433)); ctx.fillPath()
            ctx.restoreGState()
            ctx.setFillColor(H(0xF07A8E)); ctx.fillEllipse(in: ellipse(CGPoint(x: m.x, y: m.y + r * 0.055), r * 0.075, r * 0.04))
        }
    }

    static func diamondCut(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ black: Bool, _ i: Int) {
        let n = 8
        func v(_ k: Int, _ rad: CGFloat, _ rot: CGFloat) -> CGPoint {
            let a = CGFloat(k) / CGFloat(n) * 2 * .pi + rot
            return CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
        }
        let outer = CGMutablePath()
        for k in 0..<n { k == 0 ? outer.move(to: v(k, r * 1.0, .pi / 8)) : outer.addLine(to: v(k, r * 1.0, .pi / 8)) }
        outer.closeSubpath()
        dropShadow(ctx, outer, r * 0.06, r * 0.14, 0.25)
        let light = CGPoint(x: -0.62, y: -0.78)
        func shadeFacet(_ pts: [CGPoint], _ bias: CGFloat) {
            let cx = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count), cy = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
            let dx = cx - c.x, dy = cy - c.y, d = max(0.001, hypot(dx, dy))
            let lam = (dx / d * light.x + dy / d * light.y) * min(1, d / (r * 0.5))   // 빛 쪽 면이 밝다
            let v = black ? 0.13 + 0.12 * Double(lam) + Double(bias) : 0.90 + 0.09 * Double(lam) + Double(bias)
            let fp = CGMutablePath(); fp.addLines(between: pts); fp.closeSubpath()
            fill(ctx, fp, W(min(1, max(0, v))))
            stroke(ctx, fp, black ? W(0.55, 0.35) : W(0.55, 0.30), r * 0.025)
        }
        for k in 0..<n {
            let o0 = v(k, r, .pi / 8), o1 = v(k + 1, r, .pi / 8), m = v(k + 1, r * 0.66, 0), m0 = v(k, r * 0.66, 0)
            shadeFacet([o0, o1, m], k % 2 == 0 ? 0.03 : -0.02)
            shadeFacet([o0, m, m0], k % 2 == 0 ? -0.03 : 0.01)
            let t0 = v(k, r * 0.40, .pi / 8), t1 = v(k + 1, r * 0.40, .pi / 8)
            shadeFacet([m0, m, t0], 0.0)
            shadeFacet([m, t1, t0], 0.02)
        }
        // 가운데 판(table)
        let table = CGMutablePath()
        for k in 0..<n { k == 0 ? table.move(to: v(k, r * 0.40, .pi / 8)) : table.addLine(to: v(k, r * 0.40, .pi / 8)) }
        table.closeSubpath()
        gradientIn(ctx, table, black ? [(0, W(0.30)), (1, W(0.10))] : [(0, W(1.0)), (1, W(0.88))], from: CGPoint(x: c.x - r * 0.2, y: c.y - r * 0.25), end: r * 0.6)
        stroke(ctx, table, black ? W(0.6, 0.35) : W(0.5, 0.3), r * 0.025)
        stroke(ctx, outer, black ? W(0, 0.6) : W(0, 0.28), 0.9)
        // 반짝(마름모 — 판의 십자 표시와 헷갈리지 않게)
        let s = CGPoint(x: c.x - r * 0.48, y: c.y - r * 0.50), Ls = r * 0.17
        ctx.setFillColor(W(1, 0.95)); ctx.beginPath()
        ctx.move(to: CGPoint(x: s.x, y: s.y - Ls)); ctx.addLine(to: CGPoint(x: s.x + Ls * 0.5, y: s.y)); ctx.addLine(to: CGPoint(x: s.x, y: s.y + Ls)); ctx.addLine(to: CGPoint(x: s.x - Ls * 0.5, y: s.y)); ctx.closePath(); ctx.fillPath()
        _ = i
    }

    static func C(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    static func H(_ hex: Int, _ a: Double = 1) -> CGColor { C(Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255, a) }

    static func W(_ v: Double, _ a: Double = 1) -> CGColor { C(v, v, v, a) }

    static func radial(_ ctx: CGContext, _ center: CGPoint, _ r: CGFloat, _ stops: [(CGFloat, CGColor)], from hl: CGPoint, end: CGFloat) {
        let grad = CGGradient(colorsSpace: sRGB, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
        ctx.drawRadialGradient(grad, startCenter: hl, startRadius: 0, endCenter: hl, endRadius: end, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    static func shadow(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        ctx.setFillColor(W(0, 0.25)); ctx.fillEllipse(in: CGRect(x: c.x - r + r * 0.06, y: c.y - r + r * 0.14, width: 2 * r, height: 2 * r))
    }

    static func clipCircle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) { ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.clip() }

    static func hash(_ a: Int, _ b: Int) -> Double { let v = sin(Double(a) * 127.1 + Double(b) * 311.7) * 43758.5453; return v - floor(v) }

    typealias StoneFn = (CGContext, CGPoint, CGFloat, Bool, Int) -> Void   // (ctx, 가운데, 반지름, 흑?, 돌 번호)

    package static func plain(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ black: Bool, _: Int) {
        shadow(ctx, c, r)
        let hl = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4)
        if black { radial(ctx, c, r, [(0, W(0.45)), (1, W(0.05))], from: hl, end: r * 1.5) }
        else {
            radial(ctx, c, r, [(0, W(1.0)), (1, W(0.80))], from: hl, end: r * 1.6)
            ctx.setStrokeColor(W(0, 0.2)); ctx.setLineWidth(0.8); ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
    }

    static func pixel(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ black: Bool, _: Int) {
        let n = 9   // 한 변 칸 수
        let cell = 2 * r / CGFloat(n)
        ctx.setFillColor(W(0, 0.22))
        for y in 0..<n { for x in 0..<n {
            let dx = (CGFloat(x) + 0.5) / CGFloat(n) * 2 - 1, dy = (CGFloat(y) + 0.5) / CGFloat(n) * 2 - 1
            if dx * dx + dy * dy <= 1.0 { ctx.fill(CGRect(x: c.x - r + CGFloat(x) * cell + cell * 0.5, y: c.y - r + CGFloat(y) * cell + cell * 0.9, width: cell, height: cell)) }
        } }
        for y in 0..<n { for x in 0..<n {
            let dx = (CGFloat(x) + 0.5) / CGFloat(n) * 2 - 1, dy = (CGFloat(y) + 0.5) / CGFloat(n) * 2 - 1
            guard dx * dx + dy * dy <= 1.0 else { continue }
            let edge = dx * dx + dy * dy > 0.62
            let lit = (dx + 0.35) * (dx + 0.35) + (dy + 0.40) * (dy + 0.40) < 0.10
            let col: CGColor
            if black { col = lit ? H(0x8C86A8) : (edge ? H(0x15131E) : H(0x2C2838)) }
            else { col = lit ? W(1.0) : (edge ? H(0xB9B6C8) : H(0xEDEBF5)) }
            ctx.setFillColor(col); ctx.fill(CGRect(x: c.x - r + CGFloat(x) * cell, y: c.y - r + CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5))
        } }
    }
}

// MARK: - 상점 · 끼기 서버 선(omok_skins_state · buy_omok_skin · set_omok_skin)

/// `omok_skins_state(p_protocol)` 응답: {status, ruby_balance, equipped, skins:[{id, name, price, owned, equipped}]}.
/// 줄 하나가 깨져도 나머지는 산다. 이 빌드가 모르는 id(새 서버 스킨)는 버린다 — 그릴 수 없는 칸을 세우지 않는다.
package nonisolated struct OmokSkinsState: Decodable, Equatable, Sendable {
    package struct Row: Equatable, Sendable, Identifiable {
        package let skin: OmokStoneSkin
        package var name: String
        package var price: Int?
        package var owned: Bool
        package var equipped: Bool
        package var id: String { skin.rawValue }

        package init(skin: OmokStoneSkin, name: String? = nil, price: Int? = nil, owned: Bool = false, equipped: Bool = false) {
            self.skin = skin
            self.name = (name?.isEmpty == false ? name : nil) ?? skin.displayName
            self.price = price.map { max(0, $0) }
            self.owned = owned
            self.equipped = equipped
        }
    }

    package var status: String?
    package var rubyBalance: Int?
    /// 낀 스킨(nil = 일반 돌 · 모르는 id).
    package var equipped: OmokStoneSkin?
    package var rows: [Row]

    package init(status: String? = "ok", rubyBalance: Int? = nil, equipped: OmokStoneSkin? = nil, rows: [Row] = []) {
        self.status = status
        self.rubyBalance = rubyBalance
        self.equipped = equipped
        var seen = Set<String>()
        self.rows = rows.filter { seen.insert($0.id).inserted }
    }

    package var isOK: Bool { status == "ok" }

    private enum CodingKeys: String, CodingKey { case status, rubyBalance, equipped, skins }
    private struct LossyRow: Decodable {
        let row: Row?
        enum K: String, CodingKey { case id, name, price, owned, equipped }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: K.self),
                  let skin = OmokStoneSkin(wireValue: c.achievementLossy(String.self, forKey: .id)) else { row = nil; return }
            row = Row(skin: skin, name: c.achievementLossy(String.self, forKey: .name), price: c.achievementLossyInt(forKey: .price),
                      owned: c.achievementLossy(Bool.self, forKey: .owned) ?? false,
                      equipped: c.achievementLossy(Bool.self, forKey: .equipped) ?? false)
        }
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(status: c.achievementLossy(String.self, forKey: .status),
                  rubyBalance: c.achievementLossyInt(forKey: .rubyBalance),
                  equipped: OmokStoneSkin(wireValue: c.achievementLossy(String.self, forKey: .equipped)),
                  rows: (c.achievementLossyList(LossyRow.self, forKey: .skins) ?? []).compactMap(\.row))
    }

    /// 사기 · 끼기 뒤 서버 값으로 줄을 맞춘 사본(순수). `owned` 는 그 스킨을 가진 것으로 · `equipped` 는 낀 것 하나만.
    package func applying(owned skin: OmokStoneSkin? = nil, equipped: OmokStoneSkin?, rubyBalance: Int? = nil) -> OmokSkinsState {
        var copy = self
        copy.equipped = equipped
        if let rubyBalance { copy.rubyBalance = rubyBalance }
        copy.rows = rows.map { row in
            var r = row
            if r.skin == skin { r.owned = true }
            r.equipped = r.skin == equipped
            return r
        }
        return copy
    }
}

/// `buy_omok_skin` · `set_omok_skin` 응답(같은 칸을 같이 읽는다).
/// status: ok · already_owned · unknown_skin · needs_update · insufficient · not_owned · unauthorized · no_profile.
package nonisolated struct OmokSkinWriteResponse: Decodable, Equatable, Sendable {
    package var status: String?
    package var skin: String?
    package var price: Int?
    package var rubyBalance: Int?
    package var equipped: String?
    package var need: Int?
    package var have: Int?

    package init(status: String?, skin: String? = nil, price: Int? = nil, rubyBalance: Int? = nil, equipped: String? = nil,
                 need: Int? = nil, have: Int? = nil) {
        self.status = status; self.skin = skin; self.price = price; self.rubyBalance = rubyBalance
        self.equipped = equipped; self.need = need; self.have = have
    }
}

/// 본문들 — 키를 **언제나** 싣는다(null 포함 — 키 집합이 흔들리면 PostgREST 가 다른 함수를 찾는다).
package nonisolated struct OmokSkinsStateRequest: Encodable, Equatable, Sendable {
    package let pProtocol: Int
    package init(protocolNumber: Int = OmokStoneSkin.protocolVersion) { pProtocol = protocolNumber }
}

package nonisolated struct OmokSkinBuyRequest: Encodable, Equatable, Sendable {
    package let pSkin: String
    package let pProtocol: Int
    package init(skin: OmokStoneSkin, protocolNumber: Int = OmokStoneSkin.protocolVersion) {
        pSkin = skin.rawValue
        pProtocol = protocolNumber
    }
}

package nonisolated struct OmokSkinSetRequest: Encodable, Equatable, Sendable {
    package let pSkin: String?
    package init(skin: OmokStoneSkin?) { pSkin = skin?.rawValue }
    private enum CodingKeys: String, CodingKey { case pSkin }
    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let pSkin { try c.encode(pSkin, forKey: .pSkin) } else { try c.encodeNil(forKey: .pSkin) }
    }
}

extension SupabaseWorkService {
    package nonisolated static let omokSkinsStatePath = "/rest/v1/rpc/omok_skins_state"
    package nonisolated static let buyOmokSkinPath = "/rest/v1/rpc/buy_omok_skin"
    package nonisolated static let setOmokSkinPath = "/rest/v1/rpc/set_omok_skin"

    /// 스킨 상점 상태. 함수가 없는 서버(db push 전)는 `.databaseSchemaMissing` — 부르는 쪽이 '오목알' 탭을 감춘다.
    package func omokSkinsState(accessToken: String) async throws -> OmokSkinsState {
        let data = try await send(path: Self.omokSkinsStatePath, method: "POST", body: OmokSkinsStateRequest(),
                                  accessToken: accessToken, prefer: nil)
        return try decoder.decode(OmokSkinsState.self, from: data)
    }

    /// 스킨 사기(루비 100 · 사면 바로 낀다).
    package func buyOmokSkin(accessToken: String, skin: OmokStoneSkin) async throws -> OmokSkinWriteResponse {
        let data = try await send(path: Self.buyOmokSkinPath, method: "POST", body: OmokSkinBuyRequest(skin: skin),
                                  accessToken: accessToken, prefer: nil)
        return try decoder.decode(OmokSkinWriteResponse.self, from: data)
    }

    /// 스킨 끼기(nil = 일반 돌).
    package func setOmokSkin(accessToken: String, skin: OmokStoneSkin?) async throws -> OmokSkinWriteResponse {
        let data = try await send(path: Self.setOmokSkinPath, method: "POST", body: OmokSkinSetRequest(skin: skin),
                                  accessToken: accessToken, prefer: nil)
        return try decoder.decode(OmokSkinWriteResponse.self, from: data)
    }
}
