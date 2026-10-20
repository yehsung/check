import SwiftUI

// MARK: - 금(균열)

struct GCrack {
    var pts: [CGPoint]      // 단위 좌표(캡슐 반지름 = 1, 중심 0,0)
    var len: [Double]       // [첫 톡 뒤, 두 번째 톡 뒤] 보이는 비율
}

enum GCracks {
    static func make(seed: UInt64) -> [GCrack] {
        var r = GRandom(seed ^ 0xC0FFEE)
        func walk(from s: CGPoint, heading: Double, steps: Int, step: ClosedRange<Double>, wiggle: Double) -> [CGPoint] {
            var pts = [s]
            var p = s
            var side = r.sign()
            for _ in 0..<steps {
                side = -side
                let a = heading + side * r.range(wiggle * 0.4, wiggle)
                let l = r.range(step.lowerBound, step.upperBound)
                p = CGPoint(x: p.x + cos(a) * l, y: p.y + sin(a) * l)
                pts.append(p)
            }
            return pts
        }
        let x0 = r.range(-0.28, 0.12)
        let up = -Double.pi / 2 + r.range(-0.25, 0.25)
        let a = walk(from: CGPoint(x: x0, y: 0.04), heading: up, steps: 6, step: 0.14...0.19, wiggle: 0.65)
        let bHeading = (a[2].x < 0 ? -0.35 : -2.8) + r.range(-0.2, 0.2)
        let b = walk(from: a[2], heading: bHeading, steps: 4, step: 0.12...0.17, wiggle: 0.6)
        let c = walk(from: CGPoint(x: x0 + r.range(0.18, 0.34), y: 0.07), heading: .pi / 2 + r.range(-0.4, 0.4),
                     steps: 4, step: 0.13...0.18, wiggle: 0.7)
        let dHeading = (a[4].x < 0 ? -2.6 : -0.5)
        let d = walk(from: a[4], heading: dHeading, steps: 3, step: 0.10...0.14, wiggle: 0.6)
        let e = walk(from: CGPoint(x: x0 - r.range(0.25, 0.4), y: 0.06), heading: .pi / 2 + 0.5,
                     steps: 3, step: 0.12...0.16, wiggle: 0.6)
        return [
            GCrack(pts: a, len: [0.55, 1.0]),
            GCrack(pts: c, len: [0.35, 1.0]),
            GCrack(pts: b, len: [0, 1.0]),
            GCrack(pts: d, len: [0, 1.0]),
            GCrack(pts: e, len: [0, 0.9]),
        ]
    }

    /// 탭 시각들로 각 금의 현재 비율.
    static func progress(_ crack: GCrack, tapTimes: [Date], now: Date) -> Double {
        guard !tapTimes.isEmpty else { return 0 }
        let n = min(tapTimes.count, 2)
        let target = crack.len[n - 1]
        let prev = n >= 2 ? crack.len[n - 2] : 0
        let t = now.timeIntervalSince(tapTimes[n - 1])
        return GMath.lerp(prev, target, GMath.easeOutCubic(t / 0.14))
    }

    static func partial(_ pts: [CGPoint], _ frac: Double) -> [CGPoint] {
        guard frac > 0, pts.count > 1 else { return [] }
        var lens: [Double] = []
        var total = 0.0
        for i in 1..<pts.count { let l = hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y); lens.append(l); total += l }
        var remain = total * min(1, frac)
        var out = [pts[0]]
        for i in 1..<pts.count {
            if remain >= lens[i-1] { out.append(pts[i]); remain -= lens[i-1] }
            else { let f = remain / lens[i-1]; out.append(GMath.lerp(pts[i-1], pts[i], f)); break }
        }
        return out
    }
}

/// 캡슐 표면의 금 + 새어 나오는 빛(캡슐 위에 얹는다, 원으로 잘림).
struct GCrackOverlay: View {
    var cracks: [GCrack]
    var tapTimes: [Date]
    var now: Date
    var glow: Double          // 0…1.6
    /// 희귀 캡슐(황금 · 무지개)이면 그 빛깔로 샌다. nil = 평범한 흰 빛.
    var rare: GRare?
    var body: some View {
        Canvas { ctx, size in
            let R = size.width / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.clip(to: Path(ellipseIn: CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)))
            var paths: [Path] = []
            for cr in cracks {
                let f = GCracks.progress(cr, tapTimes: tapTimes, now: now)
                let pts = GCracks.partial(cr.pts, f)
                guard pts.count > 1 else { continue }
                var p = Path()
                p.addLines(pts.map { CGPoint(x: c.x + $0.x * R, y: c.y + $0.y * R) })
                paths.append(p)
            }
            guard !paths.isEmpty else { return }
            let light = rare?.light ?? Color.white
            let glowColor = rare?.primary ?? GPalette.hex(0xFFF6D8)
            // 어두운 가장자리
            for p in paths {
                ctx.stroke(p, with: .color(GPalette.plum.opacity(0.45)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            }
            // 번지는 빛(두 겹: 넓고 옅게 + 좁고 밝게)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 5 + 4 * glow))
                for p in paths {
                    l.stroke(p, with: .color(glowColor.opacity(min(1, 0.5 + 0.35 * glow))),
                             style: StrokeStyle(lineWidth: 8 + 9 * glow, lineCap: .round, lineJoin: .round))
                }
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 2))
                for p in paths {
                    l.stroke(p, with: .color(Color.white.opacity(min(1, 0.6 + 0.3 * glow))),
                             style: StrokeStyle(lineWidth: 3.5 + 2.5 * glow, lineCap: .round, lineJoin: .round))
                }
            }
            // 밝은 심
            for p in paths {
                ctx.stroke(p, with: .color(light.opacity(0.95)), style: StrokeStyle(lineWidth: 1.4 + 0.6 * glow, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

/// 캡슐 뒤에서 금 사이로 뻗는 빛줄기 + 둥근 후광(캡슐보다 먼저 그린다).
struct GLeakLight: View {
    var cracks: [GCrack]
    var tapTimes: [Date]
    var now: Date
    var intensity: Double     // 0…2
    var halo: Double          // 0…1 둥근 후광
    /// 희귀 캡슐(황금 · 무지개)이면 그 빛깔. 무지개는 빛줄기마다 일곱 빛을 돈다.
    var rare: GRare?
    var capsuleD: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = capsuleD / 2
            let col = rare?.primary ?? GPalette.hex(0xFFF8E4)
            if halo > 0 {
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 14))
                    let hr = R * (1.25 + 0.35 * halo)
                    l.fill(Path(ellipseIn: CGRect(x: c.x - hr, y: c.y - hr, width: hr * 2, height: hr * 2)),
                           with: .radialGradient(Gradient(colors: [col.opacity(0.85 * halo), col.opacity(0)]),
                                                 center: c, startRadius: R * 0.6, endRadius: hr))
                }
            }
            guard intensity > 0 else { return }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 3.5))
                for (ci, cr) in cracks.enumerated() {
                    let f = GCracks.progress(cr, tapTimes: tapTimes, now: now)
                    let pts = GCracks.partial(cr.pts, f)
                    for (i, p) in pts.enumerated() where i > 0 {
                        let rayCol = rare.map { $0 == .rainbow ? $0.ray(ci * 3 + i, of: 14) : col } ?? col
                        let dist = hypot(p.x, p.y)
                        guard dist > 0.25 else { continue }
                        let a = atan2(p.y, p.x)
                        let len = R * (1.1 + 1.1 * min(1.6, intensity)) * (0.7 + 0.3 * Double((i * 37) % 5) / 4)
                        let w = 0.08 + 0.05 * min(1.6, intensity)
                        let o = CGPoint(x: c.x + p.x * R * 0.9, y: c.y + p.y * R * 0.9)
                        var path = Path()
                        path.move(to: o)
                        path.addLine(to: CGPoint(x: o.x + cos(a - w) * len, y: o.y + sin(a - w) * len))
                        path.addLine(to: CGPoint(x: o.x + cos(a + w) * len, y: o.y + sin(a + w) * len))
                        path.closeSubpath()
                        l.fill(path, with: .radialGradient(Gradient(colors: [rayCol.opacity(min(1, 0.75 * intensity)), rayCol.opacity(0)]),
                                                           center: o, startRadius: 0, endRadius: len))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 터지는 빛(빛줄기 · 고리 · 심) — 별/반짝이 모양 없음

struct GLightBurst: View {
    var t: Double            // 터진 뒤 시간(음수면 아무것도)
    /// 희귀 공개(황금 · 무지개)면 그 빛깔 · 긴 빛줄기 · 고리 넷. nil = 평범한 흰 빛.
    var rare: GRare?
    var center: CGPoint
    var dark: Bool           // 어두운 바탕
    /// 빛줄기 회전 각(라디안). 시간에 곱하지 않고 밖에서 넘긴다 — 잦아들 때 멈출 수 있게.
    var spin: Double
    /// 동작 줄이기: 빛줄기 · 고리 없이 가운데 빛만 은은하게 켠다.
    var reduced: Bool = false
    var body: some View {
        Canvas { ctx, size in
            guard t >= 0 else { return }
            let gold = rare != nil
            let c = center
            if !reduced {
                // 빛줄기: 확 켜졌다가 은은하게 남는다
                let rise = GMath.easeOutCubic(t / (gold ? 0.35 : 0.18))
                let hold = gold ? 0.75 : 0.55
                let rays = rise * GMath.lerp(1, hold, GMath.smooth(0.25, 1.4, t))
                let n = gold ? 18 : 12
                let rot = spin + 0.2
                let R = (gold ? 330.0 : 250.0) * GMath.lerp(0.55, 1, GMath.easeOutCubic(t / 0.6))
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: gold ? 5 : 4))
                    for i in 0..<n {
                        let longRay = i % 2 == 0
                        let a = Double(i) / Double(n) * 2 * .pi + rot
                        let len = R * (longRay ? 1 : 0.68)
                        let half = (gold ? 0.075 : 0.065) * (longRay ? 1 : 0.7)
                        var p = Path()
                        p.move(to: c)
                        p.addLine(to: CGPoint(x: c.x + cos(a - half) * len, y: c.y + sin(a - half) * len))
                        p.addLine(to: CGPoint(x: c.x + cos(a + half) * len, y: c.y + sin(a + half) * len))
                        p.closeSubpath()
                        let alpha = (dark ? 0.55 : 0.75) * rays * (longRay ? 1 : 0.75)
                        let rayCol = rare?.ray(i, of: n) ?? Color.white
                        l.fill(p, with: .radialGradient(Gradient(colors: [rayCol.opacity(alpha), rayCol.opacity(0)]),
                                                        center: c, startRadius: 10, endRadius: len))
                    }
                }
            }
            // 심 광채
            let core = reduced ? GMath.smooth(0, 0.35, t) * (gold ? 0.75 : 0.6)
                               : GMath.lerp(1.0, gold ? 0.7 : 0.55, GMath.smooth(0.1, 1.0, t))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 10))
                let r = (gold ? 120.0 : 95.0) * (reduced ? 1 : GMath.lerp(0.6, 1, GMath.easeOutCubic(t / 0.4)))
                let col = rare?.core ?? Color.white
                l.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .radialGradient(Gradient(colors: [col.opacity(0.95 * core), col.opacity(0.35 * core), col.opacity(0)]),
                                             center: c, startRadius: 0, endRadius: r))
            }
            guard !reduced else { return }
            // 퍼지는 빛 고리
            let starts: [Double] = gold ? [0, 0.30, 0.60, 0.95] : [0, 0.13]
            let dur = gold ? 1.6 : 0.85
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: gold ? 4 : 3))
                for (k, s) in starts.enumerated() {
                    let tau = t - s
                    guard tau > 0, tau < dur else { continue }
                    let p = tau / dur
                    let r = GMath.lerp(50, gold ? 420 : 300, GMath.easeOutCubic(p))
                    let w = (gold ? 18.0 : 12.0) * (1 - p) + 1.5
                    let a = (gold ? 0.85 : 0.75) * pow(1 - p, 1.6)
                    let col = rare?.ring(k) ?? Color.white
                    l.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(col.opacity(a)), lineWidth: w)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 손잡이 힌트 화살표(돌아가는 빛이 흐르는 호)

struct GHintArc: View {
    var now: Date
    var radius: CGFloat
    var opacity: Double
    /// 흐르는 밝은 토막의 세기(잦아들면 호와 화살촉만 남는다).
    var flow: Double
    var body: some View {
        Canvas { ctx, size in
            guard opacity > 0.01 else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let a0 = -40.0 * .pi / 180, a1 = 62.0 * .pi / 180
            var arc = Path()
            arc.addArc(center: c, radius: radius, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
            ctx.stroke(arc, with: .color(Color.white.opacity(0.55 * opacity)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            // 흐르는 밝은 토막
            if flow > 0.01 {
                let t = now.timeIntervalSinceReferenceDate
                let p = (t.truncatingRemainder(dividingBy: 1.5)) / 1.5
                let head = GMath.lerp(a0, a1 + 0.5, GMath.easeInOutCubic(p))
                let tail = head - 0.7
                let h = min(head, a1), tl = max(tail, a0)
                if h > tl {
                    var seg = Path()
                    seg.addArc(center: c, radius: radius, startAngle: .radians(tl), endAngle: .radians(h), clockwise: false)
                    ctx.stroke(seg, with: .color(Color.white.opacity(opacity * flow)), style: StrokeStyle(lineWidth: 3.6, lineCap: .round))
                }
            }
            // 화살촉
            let tip = CGPoint(x: c.x + cos(a1) * radius, y: c.y + sin(a1) * radius)
            let dir = a1 + .pi / 2
            var head3 = Path()
            let s: CGFloat = 7
            head3.move(to: CGPoint(x: tip.x + cos(dir) * s, y: tip.y + sin(dir) * s))
            head3.addLine(to: CGPoint(x: tip.x + cos(dir + 2.45) * s, y: tip.y + sin(dir + 2.45) * s))
            head3.addLine(to: CGPoint(x: tip.x + cos(dir - 2.45) * s, y: tip.y + sin(dir - 2.45) * s))
            head3.closeSubpath()
            ctx.fill(head3, with: .color(Color.white.opacity(0.9 * opacity)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 금빛(무지개빛) 글자 반짝임

struct GShimmerTitle: View {
    var text: String
    var size: CGFloat
    var t: Double
    /// 지나가는 반짝임 횟수 상한(그 뒤엔 멈춘 글자 — 매 프레임 그릴 일이 없다). 0 이면 반짝임 없음.
    var passes: Int = 2
    /// 글자 빛깔(황금 · 무지개 — v0.3.59). 반짝임 · 둘레 빛 모양은 같다.
    var rare: GRare = .gold
    var body: some View {
        let label = Text(text).font(.system(size: size, weight: .heavy, design: .rounded))
        let cycle = 2.4
        let index = Int(max(0, t) / cycle)
        let p = index < passes ? (t.truncatingRemainder(dividingBy: cycle)) / 1.2 : 2   // 1.2초 지나가고 1.2초 쉼
        let x = GMath.lerp(-0.4, 1.4, GMath.easeInOutCubic(p))
        label
            .foregroundStyle(rare.titleFill)
            .overlay {
                if p < 1 {
                    LinearGradient(colors: [.clear, Color.white.opacity(0.95), .clear],
                                   startPoint: UnitPoint(x: x - 0.18, y: 0.2), endPoint: UnitPoint(x: x + 0.18, y: 0.8))
                        .mask(label)
                }
            }
            .shadow(color: rare.titleGlow, radius: 10)
            .shadow(color: rare.titleEdge, radius: 1, y: 1)
    }
}
