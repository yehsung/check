import SwiftUI

// MARK: - 도형

/// 반원(위/아래). 원점 중심 지름 = rect 폭.
struct GHalfDisc: Shape {
    var upper: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        p.move(to: CGPoint(x: c.x - r, y: c.y))
        p.addRelativeArc(center: c, radius: r, startAngle: .degrees(upper ? 180 : 0), delta: .degrees(180))
        p.closeSubpath()
        return p
    }
}

/// 조각(작은 결정). 그림 별/반짝이가 아니라 '물건' 하나.
struct GShardShape: Shape {
    static let pts: [CGPoint] = [
        CGPoint(x: 0.50, y: 0.00), CGPoint(x: 0.86, y: 0.30), CGPoint(x: 0.78, y: 0.76),
        CGPoint(x: 0.50, y: 1.00), CGPoint(x: 0.20, y: 0.74), CGPoint(x: 0.14, y: 0.28),
    ]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addLines(Self.pts.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        p.closeSubpath()
        return p
    }
}

/// 결정의 왼쪽 면(밝은 면).
struct GShardFacet: Shape {
    func path(in rect: CGRect) -> Path {
        let q = GShardShape.pts
        let c = CGPoint(x: 0.47, y: 0.50)
        var p = Path()
        p.addLines([q[0], q[5], q[4], q[3], c].map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        p.closeSubpath()
        return p
    }
}

struct GShardGem: View {
    var size: CGFloat
    var glow: Double = 0
    /// 바깥 테(밝은 바탕에서 결정이 묻히지 않게). nil 이면 없음.
    var outline: Color? = nil
    var body: some View {
        ZStack {
            if let outline {
                GShardShape()
                    .stroke(outline, style: StrokeStyle(lineWidth: max(1.2, size * 0.11), lineJoin: .round))
            }
            GShardShape()
                .fill(LinearGradient(colors: [GPalette.hex(0xE2D4FF), GPalette.hex(0xA98AFA), GPalette.hex(0x6E4DE0)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            GShardFacet()
                .fill(LinearGradient(colors: [Color.white.opacity(0.95), GPalette.hex(0xD9C8FF, 0.85)],
                                     startPoint: .top, endPoint: .bottom))
            GShardShape()
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: max(0.7, size * 0.045), lineJoin: .round))
        }
        .frame(width: size * 0.8, height: size)
        .frame(width: size, height: size)
        .shadow(color: GPalette.hex(0x8C6CF2).opacity(0.35 + 0.65 * glow), radius: 1.5 + 9 * glow)
    }
}

// MARK: - 캡슐

/// 그림 캡슐에서 위 반쪽이 끝나는 높이(이음매 띠 위쪽, 0…1).
enum GCapsuleArt { static let split: CGFloat = 0.50 }

/// 캡슐 반쪽. 그림이 있으면 흰 캡슐을 물들이고, 없으면 벡터로.
/// 황금은 금 캡슐 그림 그대로, 무지개(v0.3.59)는 흰 캡슐에 **위 → 아래 일곱 빛**을 곱한다(위 반쪽 = 빨·주·노, 아래 = 초·파·남·보).
struct GCapsuleHalf: View {
    var upper: Bool
    var d: CGFloat
    var tint: Color
    var rare: GRare?
    var art: GachaMachineArt

    var body: some View {
        Group {
            if rare == .gold, let g = art.goldCapsule {
                g.resizable().interpolation(.high).frame(width: d, height: d)
            } else if rare == .rainbow, let img = art.capsule {
                ZStack {
                    img.resizable().interpolation(.high)
                    // 흰 캡슐 × 일곱 빛(그림 알파 안에서만) — 곱하기라 그림의 음영 · 이음매가 그대로 산다.
                    LinearGradient(colors: GRare.spectrum, startPoint: .top, endPoint: .bottom)
                        .mask(img.resizable().interpolation(.high))
                        .blendMode(.multiply)
                    // 흰 하이라이트를 되살린다(물들인 캡슐과 같은 처리)
                    img.resizable().interpolation(.high)
                        .brightness(-0.42).contrast(5.5)
                        .blendMode(.screen)
                        .opacity(upper ? 0.9 : 0.75)
                }
                .compositingGroup()
                .frame(width: d, height: d)
            } else if rare == nil, let img = art.capsule {
                ZStack {
                    img.resizable().interpolation(.high)
                        .colorMultiply(tint)
                        .saturation(1.15)
                    // 흰 하이라이트를 되살린다(곱하기로 죽은 반사광만)
                    img.resizable().interpolation(.high)
                        .brightness(-0.42).contrast(5.5)
                        .blendMode(.screen)
                        .opacity(upper ? 0.9 : 0.75)
                }
                .compositingGroup()
                .frame(width: d, height: d)
            } else {
                GVectorCapsuleHalf(upper: upper, tint: rare == .gold ? GPalette.gold : tint,
                                   spectrum: rare == .rainbow ? GRare.spectrum : nil)
                    .frame(width: d, height: d)
            }
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(upper ? Color.black : Color.clear).frame(height: d * GCapsuleArt.split)
                Rectangle().fill(upper ? Color.clear : Color.black)
            }
            .frame(width: d + 2, height: d)
        }
    }
}

struct GVectorCapsuleHalf: View {
    var upper: Bool
    var tint: Color
    /// 무지개 캡슐(v0.3.59): 한 색 대신 위 → 아래 일곱 빛(반원 둘이 한 띠를 나눠 갖는다 — 그라데이션이 반쪽 틀이 아니라 공 전체에 걸린다).
    var spectrum: [Color]? = nil
    var body: some View {
        GeometryReader { g in
            let d = g.size.width
            ZStack {
                if let spectrum {
                    GHalfDisc(upper: upper)
                        .fill(LinearGradient(colors: spectrum, startPoint: .top, endPoint: .bottom))
                        .opacity(upper ? 0.85 : 1)
                } else {
                    GHalfDisc(upper: upper)
                        .fill(LinearGradient(colors: upper ? [tint.opacity(0.55), tint.opacity(0.85)] : [tint, tint.opacity(0.75)],
                                             startPoint: .top, endPoint: .bottom))
                }
                GHalfDisc(upper: upper)
                    .fill(RadialGradient(colors: [Color.white.opacity(upper ? 0.65 : 0.35), .clear],
                                         center: UnitPoint(x: 0.36, y: upper ? 0.30 : 0.55), startRadius: 0, endRadius: d * 0.45))
                if upper {
                    Ellipse().fill(Color.white.opacity(0.8))
                        .frame(width: d * 0.30, height: d * 0.12)
                        .rotationEffect(.degrees(-28))
                        .position(x: d * 0.32, y: d * 0.22)
                } else {
                    Rectangle().fill(Color.black.opacity(0.10)).frame(width: d, height: d * 0.06)
                        .position(x: d / 2, y: d * 0.53)
                        .mask(GHalfDisc(upper: false))
                }
                GHalfDisc(upper: upper).stroke(Color.black.opacity(0.10), lineWidth: 1)
            }
        }
    }
}

/// 캡슐 한 알(두 반쪽).
struct GCapsuleBall: View {
    var d: CGFloat
    var top: Color
    var bottom: Color
    var rare: GRare?
    var art: GachaMachineArt
    var body: some View {
        ZStack {
            GCapsuleHalf(upper: true, d: d, tint: top, rare: rare, art: art)
            GCapsuleHalf(upper: false, d: d, tint: bottom, rare: rare, art: art)
        }
        .frame(width: d, height: d)
    }
}

// MARK: - 캡슐 미리 굽기
//
// 물들인 캡슐은 반쪽마다 마스크·합성 그룹이 들어 매 프레임 오프스크린 패스가 생긴다(돔 19알 × 2).
// 처음 한 번 ImageRenderer(순수 SwiftUI)로 구워 두고 이후엔 평범한 그림으로 그린다. 같은 그림 묶음이면
// 창을 다시 열어도 다시 굽지 않는다(`cacheKey`).

@MainActor
final class GachaCapsuleSprites {
    static let heroSize: CGFloat = 128
    static let domeSize: CGFloat = 36
    let domeBalls: [Image]
    let heroTop: [Image]
    let heroBottom: [Image]
    let goldTop: Image
    let goldBottom: Image
    /// 무지개 캡슐 두 반쪽(v0.3.59).
    let rainbowTop: Image
    let rainbowBottom: Image

    private static var cache: [String: GachaCapsuleSprites] = [:]
    /// 마지막으로 굽는 데 걸린 시간(초) — 측정용.
    private(set) static var lastBakeSeconds: Double = 0

    static func shared(for art: GachaMachineArt) -> GachaCapsuleSprites {
        if let hit = cache[art.cacheKey] { return hit }
        let t0 = Date()
        let made = GachaCapsuleSprites(art: art)
        lastBakeSeconds = Date().timeIntervalSince(t0)
        cache[art.cacheKey] = made
        return made
    }

    init(art: GachaMachineArt) {
        func bake<V: View>(_ v: V, _ size: CGFloat) -> Image {
            let r = ImageRenderer(content: v.frame(width: size, height: size))
            r.scale = 3
            if let cg = r.cgImage { return Image(decorative: cg, scale: 3) }
            return Image(systemName: "circle.fill")
        }
        let pairs = GPalette.capsulePairs
        let hs = Self.heroSize, ds = Self.domeSize
        domeBalls = pairs.map { bake(GCapsuleBall(d: ds, top: $0.0, bottom: $0.1, rare: nil, art: art), ds) }
        heroTop = pairs.map { bake(GCapsuleHalf(upper: true, d: hs, tint: $0.0, rare: nil, art: art), hs) }
        heroBottom = pairs.map { bake(GCapsuleHalf(upper: false, d: hs, tint: $0.1, rare: nil, art: art), hs) }
        goldTop = bake(GCapsuleHalf(upper: true, d: hs, tint: GPalette.gold, rare: .gold, art: art), hs)
        goldBottom = bake(GCapsuleHalf(upper: false, d: hs, tint: GPalette.gold, rare: .gold, art: art), hs)
        rainbowTop = bake(GCapsuleHalf(upper: true, d: hs, tint: .white, rare: .rainbow, art: art), hs)
        rainbowBottom = bake(GCapsuleHalf(upper: false, d: hs, tint: .white, rare: .rainbow, art: art), hs)
    }
}

/// 주인공 캡슐 반쪽(구운 그림이 있으면 그것으로).
struct GHeroHalf: View {
    var upper: Bool
    var d: CGFloat
    var pair: Int
    var rare: GRare?
    var art: GachaMachineArt
    var sprites: GachaCapsuleSprites?
    var body: some View {
        if let sp = sprites {
            let img: Image = {
                switch rare {
                case .gold: return upper ? sp.goldTop : sp.goldBottom
                case .rainbow: return upper ? sp.rainbowTop : sp.rainbowBottom
                case nil: return upper ? sp.heroTop[pair] : sp.heroBottom[pair]
                }
            }()
            img.resizable().interpolation(.high).frame(width: d, height: d)
        } else {
            let c = GPalette.capsulePairs[pair]
            GCapsuleHalf(upper: upper, d: d, tint: upper ? c.0 : c.1, rare: rare, art: art)
        }
    }
}

struct GHeroBall: View {
    var d: CGFloat
    var pair: Int
    var rare: GRare?
    var art: GachaMachineArt
    var sprites: GachaCapsuleSprites?
    var body: some View {
        ZStack {
            GHeroHalf(upper: true, d: d, pair: pair, rare: rare, art: art, sprites: sprites)
            GHeroHalf(upper: false, d: d, pair: pair, rare: rare, art: art, sprites: sprites)
        }
        .frame(width: d, height: d)
    }
}

// MARK: - 돔 속 캡슐

struct GDomeCapsule {
    var p: CGPoint        // 돔 중심 기준
    var d: CGFloat
    var rot: Double
    var pair: Int
    var top: Color
    var bottom: Color
    var phase: Double
    var freq: Double
    var kick: CGVector    // 덜컹 방향(크기 포함)
    var spin: Double      // 덜컹 회전(도)
    var lift: Double      // 위로 튀는 정도 0…1
}

enum GDome {
    static let capsules: [GDomeCapsule] = {
        var r = GRandom(42)
        var out: [GDomeCapsule] = []
        let rows: [(y: Double, xs: [Double])] = [
            (40, [-58, -29, 0, 29, 58]),
            (15, [-72, -43.5, -14.5, 14.5, 43.5, 72]),
            (-11, [-58, -29, 0, 29, 58]),
            (-37, [-40, -8, 26, 55]),
        ]
        let pairs = GPalette.capsulePairs
        for (ri, row) in rows.enumerated() {
            for x in row.xs {
                let pi = Int(r.next() % UInt64(pairs.count))
                let pair = pairs[pi]
                let depth = Double(ri) / 3.0 // 0 바닥 … 1 위
                out.append(GDomeCapsule(
                    p: CGPoint(x: x + r.range(-3, 3), y: row.y + r.range(-2.5, 2.5)),
                    d: r.range(29, 33),
                    rot: r.range(-180, 180),
                    pair: pi, top: pair.0, bottom: pair.1,
                    phase: r.range(0, 2 * .pi), freq: r.range(0.45, 0.8),
                    kick: CGVector(dx: r.range(6, 13) * r.sign(), dy: r.range(10, 22) * (0.45 + depth)),
                    spin: r.range(50, 140) * r.sign(),
                    lift: 0.4 + 0.6 * depth))
            }
        }
        // 뒤(위) 줄부터 그려 앞줄이 덮게
        return out.sorted { $0.p.y < $1.p.y }
    }()
}

/// 유리 돔(벡터 유리) + 안의 캡슐.
struct GDomeView: View {
    var now: Date
    var kicks: [Double]           // 커밋 기준 덜컹 시각들
    var commitTime: Date?
    var art: GachaMachineArt
    var sprites: GachaCapsuleSprites?
    /// 잔잔한 들썩임 · 유리 광택의 크기(0 이면 멈춘 그림).
    var ambient: Double
    /// 동작 줄이기: 덜컹에 캡슐이 튀지 않는다.
    var still: Bool
    var theme: GachaMachineTheme
    var body: some View {
        let R = GLayout.domeR
        let t = now.timeIntervalSinceReferenceDate
        ZStack {
            // 유리 뒷면
            Circle()
                .fill(RadialGradient(colors: [theme.glassBack.0, theme.glassBack.1],
                                     center: UnitPoint(x: 0.42, y: 0.38), startRadius: 4, endRadius: R))
            Circle()
                .fill(LinearGradient(colors: [.clear, theme.glassTint], startPoint: .top, endPoint: .bottom))

            // 캡슐
            ZStack {
                ForEach(Array(GDome.capsules.enumerated()), id: \.offset) { _, c in
                    let m = motion(c, t: t)
                    Group {
                        if let sp = sprites {
                            sp.domeBalls[c.pair].resizable().interpolation(.high).frame(width: c.d, height: c.d)
                        } else {
                            GCapsuleBall(d: c.d, top: c.top, bottom: c.bottom, rare: nil, art: art)
                        }
                    }
                    .rotationEffect(.degrees(c.rot + m.rot))
                    .position(x: R + c.p.x + m.dx, y: R + c.p.y + m.dy)
                }
            }
            .frame(width: R * 2, height: R * 2)
            .clipShape(Circle().inset(by: 3))

            // 유리 앞면 반사
            Circle().stroke(Color.white.opacity(theme.dark ? 0.6 : 0.9), lineWidth: 2.5)
            Circle().stroke(GPalette.hex(0xA98DF0, 0.45), lineWidth: 1).padding(-1)
            Circle()
                .trim(from: 0.56, to: 0.70)
                .stroke(Color.white.opacity(theme.dark ? 0.6 : 0.85), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .padding(12)
                .blur(radius: 0.6)
            Circle()
                .trim(from: 0.73, to: 0.76)
                .stroke(Color.white.opacity(theme.dark ? 0.5 : 0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .padding(12)
            Ellipse().fill(Color.white.opacity(theme.dark ? 0.4 : 0.55)).frame(width: 14, height: 9)
                .rotationEffect(.degrees(30))
                .position(x: R * 1.62, y: R * 0.62)
            // 가끔 지나가는 유리 광택(잦아들면 안 보인다)
            if ambient > 0.01 { glint(t: t, R: R) }
        }
        .frame(width: R * 2, height: R * 2)
    }

    private func glint(t: Double, R: CGFloat) -> some View {
        let cycle = 4.2
        let p = (t.truncatingRemainder(dividingBy: cycle)) / 1.1  // 1.1초 동안 지나가고 나머지는 쉼
        let x = GMath.lerp(-0.6, 1.6, GMath.easeInOutCubic(p))
        return LinearGradient(colors: [.clear, Color.white.opacity(p < 1 ? 0.35 * ambient : 0), .clear],
                              startPoint: UnitPoint(x: x - 0.25, y: 0), endPoint: UnitPoint(x: x + 0.05, y: 0.3))
            .clipShape(Circle())
            .allowsHitTesting(false)
    }

    private func motion(_ c: GDomeCapsule, t: Double) -> (dx: Double, dy: Double, rot: Double) {
        // 늘 살짝 들썩(잦아들면 제자리)
        var dx = ambient * 0.7 * sin(2 * .pi * c.freq * t + c.phase)
        var dy = ambient * 0.9 * sin(2 * .pi * c.freq * 1.3 * t + c.phase * 1.7)
        var rot = ambient * 3.0 * sin(2 * .pi * c.freq * 0.8 * t + c.phase)
        guard let commit = commitTime, !still else { return (dx, dy, rot) }
        let tc = now.timeIntervalSince(commit)
        for (k, kt) in kicks.enumerated() {
            let tau = tc - kt
            guard tau >= 0, tau < 1.8 else { continue }
            let amp = k == 0 ? 1.0 : 0.6
            let f = 2.2 + c.freq
            dx += amp * c.kick.dx * GMath.ring(tau, freq: f, decay: 3.0)
            // 위로 튀었다 떨어진다
            dy -= amp * c.kick.dy * c.lift * abs(GMath.ring(tau, freq: f * 0.75, decay: 3.4))
            rot += amp * c.spin * GMath.ring(tau, freq: 0.9, decay: 2.2)
        }
        return (dx, dy, rot)
    }
}

// MARK: - 기계 몸통 · 손잡이 · 배출구 덮개

struct GMachineBody: View {
    var art: GachaMachineArt
    var body: some View {
        if let img = art.body {
            img.resizable().interpolation(.high)
                .frame(width: GLayout.bodySize.width, height: GLayout.bodySize.height)
        } else {
            GVectorBody().frame(width: GLayout.bodySize.width, height: GLayout.bodySize.height)
        }
    }
}

struct GVectorBody: View {
    var body: some View {
        let k = GLayout.bodyK
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 40)
                .fill(LinearGradient(colors: [GPalette.hex(0xDCCBFF), GPalette.hex(0xB9A0F7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 704 * k, height: 490 * k).offset(x: 8 * k, y: 70 * k)
            Capsule().fill(LinearGradient(colors: [.white, GPalette.hex(0xE9E1FF)], startPoint: .top, endPoint: .bottom))
                .frame(width: 515 * k, height: 86 * k).offset(x: 100 * k, y: 2 * k)
            Circle().fill(GPalette.hex(0xB8A0F2)).frame(width: 186 * k, height: 186 * k).offset(x: 265 * k, y: 129 * k)
            RoundedRectangle(cornerRadius: 14).fill(GPalette.hex(0xA88EEA))
                .frame(width: 282 * k, height: 237 * k).offset(x: 218 * k, y: 318 * k)
            RoundedRectangle(cornerRadius: 11)
                .fill(LinearGradient(colors: [GPalette.hex(0x2C1F57), GPalette.hex(0x5A44A0)], startPoint: .top, endPoint: .bottom))
                .frame(width: 257 * k, height: 202 * k).offset(x: 233 * k, y: 333 * k)
        }
    }
}

/// 배출구 덮개. 캡슐이 나올 때 위 경첩을 축으로 바깥으로 젖혀졌다가 닫힌다(닫힐 때 살짝 흔들린다).
///
/// 그림 몸통엔 덮개가 **구워져** 있다. 그래서 열릴 때만: 그 자리를 배출구 안쪽 색으로 덮고, 같은 그림에서 덮개 칸만
/// 잘라 그 조각을 돌린다(닫힌 순간엔 아무것도 안 그린다 — 몸통 그림 그대로다). 벡터 몸통엔 덮개가 없으니 늘 그린다.
struct GChuteFlap: View {
    var art: GachaMachineArt
    /// 0 닫힘 … 1 활짝(넘쳐서 음수 = 안쪽으로 살짝 넘어감).
    var open: Double

    static let maxAngle = 74.0

    var body: some View {
        let r = GLayout.flapRect
        let shape = RoundedRectangle(cornerRadius: GLayout.flapCorner, style: .continuous)
        let moving = abs(open) > 0.002
        ZStack(alignment: .topLeading) {
            if art.body != nil {
                if moving {
                    // 원래 덮개 자리 = 배출구 안쪽(그림에서 잰 색: 덮개 바로 아래 39,20,52)
                    shape.inset(by: 2)
                        .fill(LinearGradient(colors: [GPalette.hex(0x1D0F2B), GPalette.hex(0x2A1638)], startPoint: .top, endPoint: .bottom))
                        .frame(width: r.width, height: r.height)
                    piece(shape)
                }
            } else {
                if moving {
                    shape.inset(by: 2).fill(GPalette.hex(0x2C1F57))
                        .frame(width: r.width, height: r.height)
                }
                vectorFlap(shape)
            }
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .position(x: r.midX, y: r.midY)
        .allowsHitTesting(false)
    }

    /// 몸통 그림에서 덮개 칸만 잘라 경첩(위)으로 젖힌다.
    private func piece(_ shape: RoundedRectangle) -> some View {
        let r = GLayout.flapRect
        return ZStack(alignment: .topLeading) {
            art.body?.resizable().interpolation(.high)
                .frame(width: GLayout.bodySize.width, height: GLayout.bodySize.height)
                .offset(x: GLayout.bodyOrigin.x - r.minX, y: GLayout.bodyOrigin.y - r.minY)
        }
        .frame(width: r.width, height: r.height, alignment: .topLeading)
        .clipShape(shape)
        .brightness(0.06 * max(0, open))
        .rotation3DEffect(.degrees(Self.maxAngle * open), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
    }

    private func vectorFlap(_ shape: RoundedRectangle) -> some View {
        let r = GLayout.flapRect
        return shape
            .fill(LinearGradient(colors: [GPalette.hex(0xE9DEFF, 0.55), GPalette.hex(0xB9A0F5, 0.45)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.stroke(Color.white.opacity(0.6), lineWidth: 1.2))
            .frame(width: r.width, height: r.height)
            .rotation3DEffect(.degrees(Self.maxAngle * open), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
    }
}

struct GKnob: View {
    var art: GachaMachineArt
    var body: some View {
        let d = GLayout.knobR * 2
        if let img = art.knob {
            img.resizable().interpolation(.high).frame(width: d, height: d)
        } else {
            ZStack {
                Circle().fill(RadialGradient(colors: [.white, GPalette.hex(0xEDE6FF)], center: .topLeading, startRadius: 2, endRadius: d))
                Circle().stroke(GPalette.hex(0xB49BF5), lineWidth: 5)
                Capsule().fill(LinearGradient(colors: [GPalette.hex(0xCDB8FF), GPalette.hex(0xA587F2)], startPoint: .top, endPoint: .bottom))
                    .frame(width: d * 0.9, height: d * 0.26)
                Circle().fill(.white).frame(width: d * 0.24, height: d * 0.24)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .frame(width: d, height: d)
        }
    }
}

// MARK: - 칩

struct GRubyChip: View {
    var balance: Int
    var ruby: Image
    var pulse: Double
    var theme: GachaMachineTheme
    var body: some View {
        HStack(spacing: 5) {
            ruby.resizable().interpolation(.high).frame(width: 18, height: 18)
            Text("\(balance)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(balance)))
                .foregroundStyle(theme.chipText)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(theme.chipFill))
        .overlay(Capsule().stroke(theme.chipStroke, lineWidth: 1))
        .shadow(color: GPalette.hex(0x6A4FC8, theme.dark ? 0.3 : 0.12), radius: 6, y: 2)
        .scaleEffect(pulse)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GachaMachineText.rubyLabel(balance))
    }
}

struct GShardChip: View {
    var count: Int
    var pulse: Double
    /// 조각이 막 들어온 빛(1 → 0).
    var glow: Double
    var theme: GachaMachineTheme
    var body: some View {
        HStack(spacing: 5) {
            GShardGem(size: 15, glow: glow)
            Text("조각 \(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
                .foregroundStyle(theme.chipText)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            ZStack {
                Capsule().fill(theme.chipFill)
                // 들어온 순간 칩 바탕이 라벤더로 번쩍(밝은 · 어두운 바탕 둘 다에서 보이는 색)
                Capsule().fill(GPalette.hex(theme.dark ? 0x6A4FC8 : 0xD9C8FF, 0.95 * glow))
            }
        )
        .overlay(Capsule().stroke(theme.chipStroke.opacity(1 - glow), lineWidth: 1))
        .overlay(Capsule().stroke(GPalette.hex(theme.dark ? 0xE4D8FF : 0x7B5CE6, glow), lineWidth: 2))
        .shadow(color: GPalette.hex(0x7B5CE6, 0.12 + 0.6 * glow), radius: 6 + 10 * glow, y: 2)
        .scaleEffect(pulse)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GachaMachineText.shardLabel(count))
    }
}
