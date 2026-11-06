import Foundation
import simd

// MARK: - 루비 아잉이 몸 빚기 (v0.3.78 — 상점 루비 1000)
//
// 대표 결정(2026-11-06, 시안 7차 #d_YgODZOIrIg5y): "Y5 배 띠 · 6:4". 루비 아잉이는 **몸 모양이 바뀌는 첫 캐릭터**다 — 아잉이 몸을
// 앱 루비 아이콘처럼 깎인 팔각 보석(판 · 관 · 배 높이 띠 · 아래)으로 빚되, 원래 몸매와 6 : 4 로 섞는다(원래 60 % · 보석 40 %).
//
// ★ 메시(aing.scn)의 정점 자리는 **바꾸지 않는다.** 정점마다 '옮길 거리'만 구워 텍스처 좌표 칸(1 · 2 · 3번)에 싣고, 몸 셰이더의
//   geometry 단계가 그만큼 옮긴다(`RubyAingShader.geometry`). 그래서 CPU 쪽 메시를 읽는 일 — 감은 눈 UV 마스크(`eyeUVCoverMask`) ·
//   카메라 구도(몸 상자) · 클릭 판정 — 은 원래 아잉 그대로 돈다(Y5 는 원래 몸과 가까워 어긋남이 작다). 감은 눈 선 판만 같은 거리만큼
//   옮긴다(`displacement(at:)`).
//
// 방법(시안 렌더러 `~/.claude/projects/-Users-yesung-check/ruby-r6/parts-r6.swift.txt` 의 r6Apply · r7ChubbyIcon 과 같은 식):
//   중심 c 에서 정점으로 뻗는 빛살이 보석 겉면(팔각 단면 × 높이별 배율, 위아래는 평평한 뚜껑)과 만나는 거리 T 를 구하고,
//   몸 정점은 원래 거리 r 에서 r + α(T − r) 로 옮긴다. 팔 정점(몸 둘레보다 바깥)은 몸 겉면이 그 방향으로 움직인 만큼 평행 이동한다.
//   모서리 밝은 선 · 면마다 다른 밝기를 위해 '가장 가까운 모서리까지 거리'와 '면 번호 해시'를 같이 굽는다.
//
// 이 파일은 Foundation · simd 만 쓴다 — 초상 생성기(`scripts/make-ruby-aing.swift`)가 이 파일만 같이 컴파일해 **같은 식**으로 굽는다.
package nonisolated enum RubyAingShape {
    /// 빛살 중심(물체 좌표).
    package static let center = SIMD3<Float>(0, -0.04, 0)
    /// 원래 몸 ↔ 보석 섞기(0 = 원래 아잉 · 1 = 보석 그대로). Y5 = 0.4.
    package static let blend: Float = 0.4
    /// 단면 변의 수(팔각 — 앱 루비 아이콘과 같다). 정면(+z)에 면 하나가 오게 첫 꼭짓점을 22.5° 에 둔다.
    package static let sides = 8
    /// (높이 y, 단면 배율 — 변까지 거리) 오름차순. 바닥 뚜껑 → 띠 아래 → 띠 위 → 판(위 뚜껑).
    package static let profile: [SIMD2<Float>] = [
        SIMD2(-0.84, 0.12), SIMD2(-0.15, 0.76), SIMD2(-0.07, 0.76), SIMD2(0.80, 0.42),
    ]

    /// 정점마다 구운 값. `displacement` = 옮길 거리(물체 좌표) · `edge` = 가장 가까운 모서리까지 거리(0…1, 팔은 1) ·
    /// `arm` = 팔 무게(0 몸 … 1 팔) · `facet` = 면 번호 해시(0…1 — 면마다 다른 밝기).
    package struct Baked: Sendable, Equatable {
        package var displacement: [SIMD3<Float>]
        package var edge: [Float]
        package var arm: [Float]
        package var facet: [Float]
        package var count: Int { displacement.count }
    }

    // MARK: 원래 몸 둘레(팔 없는 앞뒤 정점으로 잰다)

    /// 원래 몸의 높이별 수평 반지름(y 0.005 칸). 팔은 ±x 쪽에만 있으므로 |x| ≤ |z| 인 정점만 잰다.
    package struct BodyProfile: Sendable {
        static let y0: Float = -0.86, step: Float = 0.005
        package let rho: [Float]

        package init(positions: [SIMD3<Float>]) {
            let n = Int(1.72 / Self.step) + 1
            var r = [Float](repeating: 0, count: n)
            for p in positions where abs(p.x) <= abs(p.z) {
                let i = Int(((p.y - Self.y0) / Self.step).rounded())
                if i >= 0 && i < n { r[i] = max(r[i], (p.x * p.x + p.z * p.z).squareRoot()) }
            }
            var f = r
            for i in 0..<n where f[i] == 0 {
                var best: Float = 0
                for k in max(0, i - 4)...min(n - 1, i + 4) { best = max(best, r[k]) }
                f[i] = best
            }
            rho = f
        }

        package func at(_ y: Float) -> Float {
            let f = (y - Self.y0) / Self.step
            if f < 0 || f > Float(rho.count - 1) { return 0 }
            let i = min(Int(f), rho.count - 2), t = f - Float(i)
            return rho[i] * (1 - t) + rho[i + 1] * t
        }

        /// c 에서 u 방향으로 원래 몸 겉면까지 거리.
        package func reach(_ c: SIMD3<Float>, _ u: SIMD3<Float>) -> Float {
            func inside(_ t: Float) -> Bool {
                let p = c + u * t
                return p.y > -0.85 && p.y < 0.85 && (p.x * p.x + p.z * p.z).squareRoot() <= at(p.y)
            }
            var lo: Float = 0, hi: Float = 0.01
            while inside(hi) && hi < 3 { lo = hi; hi += 0.01 }
            for _ in 0..<24 { let m = (lo + hi) / 2; if inside(m) { lo = m } else { hi = m } }
            return lo
        }
    }

    // MARK: 보석 겉면

    /// 정다각형(변까지 거리 = 1). 첫 꼭짓점 각 = 90° − 180°/n(정면에 면 하나).
    package static let polygon: [SIMD2<Float>] = {
        let R = 1 / cos(Float.pi / Float(sides))
        let first = (90 - 180 / Float(sides)) * .pi / 180
        return (0..<sides).map { k in
            let a = first + 2 * .pi * Float(k) / Float(sides)
            return SIMD2(R * cos(a), R * sin(a))
        }
    }()

    static func polyReach(_ e: SIMD2<Float>) -> (Float, Int) {
        var best = Float.infinity, bi = 0
        for i in 0..<polygon.count {
            let p = polygon[i], d = polygon[(i + 1) % polygon.count] - p
            let den = -e.x * d.y + e.y * d.x
            if abs(den) < 1e-9 { continue }
            let t = (-p.x * d.y + p.y * d.x) / den
            let s = (e.x * p.y - e.y * p.x) / den
            if t > 0 && s >= -1e-5 && s <= 1 + 1e-5 && t < best { best = t; bi = i }
        }
        return (best, bi)
    }

    static func scale(_ a: Float) -> Float {
        if a < profile.first!.x || a > profile.last!.x { return -1 }
        for k in 0..<(profile.count - 1) where a <= profile[k + 1].x {
            let t = (a - profile[k].x) / max(profile[k + 1].x - profile[k].x, 1e-6)
            return profile[k].y + (profile[k + 1].y - profile[k].y) * t
        }
        return profile.last!.y
    }

    static func segmentDistance(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let ab = b - a, l2 = simd_length_squared(ab)
        let t = l2 < 1e-12 ? 0 : min(max(simd_dot(p - a, ab) / l2, 0), 1)
        return simd_length(p - (a + ab * t))
    }

    /// 면 번호 → 0…1(시안 렌더러 r6IdHash = r5Hash(k·1.37 + 0.5, 7.7) 와 같은 식).
    static func idHash(_ k: Int) -> Float {
        let a = Float(k) * 1.37 + 0.5, b: Float = 7.7
        let v = sin(a * 127.1 + b * 311.7) * 43758.5453
        return v - floor(v)
    }

    /// 빛살(중심 c · 단위 방향 u)이 보석 겉면과 만나는 거리 · 그 점에서 가장 가까운 모서리까지 거리 · 면 번호 해시.
    package static func hit(_ u: SIMD3<Float>, from c: SIMD3<Float> = center) -> (t: Float, edge: Float, facet: Float) {
        let ua = u.y
        let uq = SIMD2(u.x, u.z)
        let ac = c.y
        let lq = simd_length(uq)
        let (h, jEdge) = lq > 1e-6 ? polyReach(uq / lq) : (Float.infinity, -1)
        func inside(_ t: Float) -> Bool { let s = scale(ac + t * ua); return s >= 0 && t * lq <= s * h }
        var lo: Float = 0, hi: Float = 0.01
        while inside(hi) && hi < 3 { lo = hi; hi += 0.01 }
        for _ in 0..<26 { let m = (lo + hi) / 2; if inside(m) { lo = m } else { hi = m } }
        let t = lo
        // 모서리까지 거리 — (단면 x, 단면 y, 높이) 좌표에서.
        let a = ac + t * ua, q = uq * t
        let P = SIMD3<Float>(q.x, q.y, a)
        func ring(_ k: Int) -> Float {
            var d = Float.infinity
            for j in 0..<polygon.count {
                let A = polygon[j] * profile[k].y, B = polygon[(j + 1) % polygon.count] * profile[k].y
                d = min(d, segmentDistance(P, SIMD3(A.x, A.y, profile[k].x), SIMD3(B.x, B.y, profile[k].x)))
            }
            return d
        }
        var k0 = 0
        for k in 0..<(profile.count - 1) where a >= profile[k].x - 1e-5 { k0 = k }
        var e = min(ring(k0), ring(k0 + 1))
        if k0 > 0 { e = min(e, ring(k0 - 1)) }
        if k0 + 2 < profile.count { e = min(e, ring(k0 + 2)) }
        for j in 0..<polygon.count {
            let A = SIMD3(polygon[j].x * profile[k0].y, polygon[j].y * profile[k0].y, profile[k0].x)
            let B = SIMD3(polygon[j].x * profile[k0 + 1].y, polygon[j].y * profile[k0 + 1].y, profile[k0 + 1].x)
            e = min(e, segmentDistance(P, A, B))
        }
        let onCap = abs(a - profile.last!.x) < 1e-4 || abs(a - profile.first!.x) < 1e-4
        let fid = onCap ? (a > 0 ? 9001 : 9002) : (k0 * 97 + jEdge)
        return (t, e, idHash(fid))
    }

    // MARK: 굽기

    static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }

    /// 정점 하나의 값(몸 둘레 `body` 는 같은 메시에서 한 번 잰 것).
    package static func bakeOne(_ p: SIMD3<Float>, body: BodyProfile) -> (SIMD3<Float>, Float, Float, Float) {
        let c = center
        let d = p - c, r = simd_length(d)
        let u = r > 1e-6 ? d / r : SIMD3<Float>(0, 1, 0)
        let h = hit(u, from: c)
        let rb = body.at(p.y)
        let ex = (p.x * p.x + p.z * p.z).squareRoot() - rb
        let w = rb > 0.05 ? smooth(0.004, 0.045, ex) : 0
        var q = c + u * (r + (h.t - r) * blend)
        if w > 0 {
            let r0 = body.reach(c, u)
            let pa = p + u * ((h.t - r0) * blend)
            q = q + (pa - q) * w
        }
        return (q - p, w > 0.5 ? 1 : min(h.edge, 1), w, h.facet)
    }

    /// 메시 정점 전부를 굽는다(결정적 — 같은 입력이면 같은 값). 10만 정점 기준 수십 ms(여러 코어).
    package static func bake(_ positions: [SIMD3<Float>]) -> Baked {
        let body = BodyProfile(positions: positions)
        let n = positions.count, chunks = 16
        let parts = ChunkResults(count: chunks)
        DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
            let lo = n * chunk / chunks, hi = n * (chunk + 1) / chunks
            var part = Baked(displacement: [], edge: [], arm: [], facet: [])
            part.displacement.reserveCapacity(hi - lo); part.edge.reserveCapacity(hi - lo)
            part.arm.reserveCapacity(hi - lo); part.facet.reserveCapacity(hi - lo)
            for i in lo..<hi {
                let v = bakeOne(positions[i], body: body)
                part.displacement.append(v.0); part.edge.append(v.1); part.arm.append(v.2); part.facet.append(v.3)
            }
            parts.set(chunk, part)
        }
        var out = Baked(displacement: [], edge: [], arm: [], facet: [])
        for part in parts.all() {
            out.displacement += part.displacement; out.edge += part.edge; out.arm += part.arm; out.facet += part.facet
        }
        return out
    }

    /// 청크 결과를 잠금으로 모은다(굽기 전용).
    final class ChunkResults: @unchecked Sendable {
        private var parts: [Baked?]
        private let lock = NSLock()
        init(count: Int) { parts = Array(repeating: nil, count: count) }
        func set(_ i: Int, _ part: Baked) { lock.lock(); parts[i] = part; lock.unlock() }
        func all() -> [Baked] { lock.lock(); defer { lock.unlock() }; return parts.map { $0! } }
    }

    /// 몸 겉면 한 점(감은 눈 선 자리 등)을 몸 셰이더와 같은 만큼 옮길 거리.
    package static func displacement(at p: SIMD3<Float>, body: BodyProfile) -> SIMD3<Float> {
        bakeOne(p, body: body).0
    }
}

// MARK: - 몸 셰이더(앱 3D · 초상 생성기가 같은 글자를 쓴다)

/// 루비 아잉이 몸 셰이더. 틀(β 얼굴 지키기 · 타원체 법선 · sRGB 섞기)은 흑우 `HwooAingFinish.HwooBody` 와 같고,
/// ① geometry 단계가 정점을 `RubyAingShape` 가 구운 거리만큼 옮기고 ② 무늬가 면마다 평평한 보석으로 칠한다(화면 미분 법선 · 면 해시 밝기 ·
/// 반짝 · 구운 모서리 거리로 흰 모서리 선).
///
/// 텍스처 좌표 칸: 0 = 원래 UV · 1 = (dx, dy) · 2 = (dz, 모서리 거리) · 3 = (팔 무게, 면 해시).
package nonisolated enum RubyAingShader {
    package static let bodyTop = 0.848950
    package static let bodyHeight = 1.695736
    package static let ellipsoid = SIMD3<Double>(0.6084, 0.7191, 0.5329)
    package static let skinYRef = 0.56530
    package static let blushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
    package static let shadeMapKey = "ckShadeMap"

    // 색(sRGB 16진) — 시안 r6App(앱 루비 아이콘 분홍).
    package static let baseColor = 0xEC5CEC
    package static let deepColor = 0x8E1FAE
    package static let lightColor = 0xFFC4FF
    package static let edgeColor = 0xFFE6FF
    package static let edgeWidth = 0.020
    package static let edgeStrength = 0.75
    package static let sparkle = 0.9
    package static let facetVariation = 0.45
    package static let lift = 0.40

    static func f5(_ v: Double) -> String { String(format: "%.5f", v) }
    static func f5v(_ v: SIMD3<Double>) -> String { String(format: "float3(%.5f, %.5f, %.5f)", v.x, v.y, v.z) }
    static func toLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func f5hex(_ hex: Int) -> String {
        f5v(SIMD3(toLinear(Double((hex >> 16) & 255) / 255), toLinear(Double((hex >> 8) & 255) / 255), toLinear(Double(hex & 255) / 255)))
    }

    package static let geometry = """
    #pragma varyings
    float3 ckVP;
    float2 ckUV;
    float3 ckVN;
    float3 ckVE;
    float3 ckRb;
    #pragma body
    float3 ckO = _geometry.position.xyz;
    out.ckVP = ckO;
    _geometry.position.xyz = ckO + float3(_geometry.texcoords[1].x, _geometry.texcoords[1].y, _geometry.texcoords[2].x);
    out.ckRb = float3(_geometry.texcoords[2].y, _geometry.texcoords[3].x, _geometry.texcoords[3].y);
    out.ckVE = (scn_node.modelViewTransform * float4(_geometry.position.xyz, 1.0)).xyz;
    out.ckUV = _geometry.texcoords[0];
    float3 ckG = (ckO - float3(0.0, 0.001, 0.0)) / (\(f5v(ellipsoid)) * \(f5v(ellipsoid)));
    out.ckVN = (scn_node.normalTransform * float4(ckG, 0.0)).xyz;
    """

    /// 보석 몸: 면마다 평평한 법선 · 면마다 다른 밝기 · 반짝 · 모서리 밝은 선. 팔은 둥근 법선.
    package static let pattern = """
    ckShadeMix = 0.0;
    {
        float3 gP = in.ckVE;
        float3 gN = normalize(cross(dfdx(gP), dfdy(gP)));
        if (dot(gN, -gP) < 0.0) gN = -gN;
        float arm = clamp(in.ckRb.y, 0.0, 1.0);
        float3 gNs = normalize(mix(gN, ckVn, arm));
        float3 L = normalize(float3(-0.38, 0.55, 0.74));
        float3 V = normalize(-gP);
        float ndl = dot(gNs, L);
        float h = mix(in.ckRb.z, 0.5, arm);
        float k = clamp(\(f5(lift)) + 0.42 * ndl + (h - 0.5) * \(f5(facetVariation)), 0.0, 1.0);
        float3 c = mix(\(f5hex(deepColor)), \(f5hex(baseColor)), smoothstep(0.02, 0.62, k));
        c = mix(c, \(f5hex(lightColor)), smoothstep(0.68, 1.0, k));
        ckBase = c;
        float3 H = normalize(L + V);
        float sp = pow(max(dot(gNs, H), 0.0), 48.0);
        float faceK = 1.0 - 0.85 * ckFace;
        ckAdd += float3(1.0, 0.96, 0.98) * sp * \(f5(sparkle)) * faceK;
        float ew = \(f5(edgeWidth));
        float aa = fwidth(in.ckRb.x);
        float ed = 1.0 - smoothstep(ew * 0.30 - aa, ew + aa, in.ckRb.x);
        ckAdd += \(f5hex(edgeColor)) * ed * \(f5(edgeStrength)) * (1.0 - arm) * mix(1.0, 0.40, ckFace);
    }
    """

    /// 몸 출력 — 흑우 · 이슬과 같은 식(얼굴 상자 안은 β 로 원본을 지킨다 · sRGB 0–255 공간에서 섞는다).
    /// `faceOff` = 참이면 얼굴 상자를 끈다(초상 생성기의 '얼굴 없는 몸' 판 — 시무룩 얼굴을 얹을 바탕).
    package static func bodyOutput(faceOff: Bool = false) -> String {
        """
        float3 ckCol = ckBase * mix(1.0, ckShade, ckShadeMix) + ckAdd;
        bool ckInFace = \(faceOff ? "false" : "ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62");
        float ckB = ckInFace ? ckBeta : 1.0;
        float3 ckCc = clamp(ckCol, float3(0.0), float3(1.0));
        float3 ckCe = 255.0 * select(1.055 * pow(ckCc, float3(1.0 / 2.4)) - 0.055, ckCc * 12.92, ckCc <= float3(0.0031308));
        float3 ckOe = clamp((\(faceOff ? "ckSe" : "ckPe") + ckB * (ckCe - ckSe)) / 255.0, float3(0.0), float3(1.0));
        float3 ckOut = select(pow((ckOe + 0.055) / 1.055, float3(2.4)), ckOe / 12.92, ckOe <= float3(0.04045));
        _output.color = float4(ckOut, 1.0);
        """
    }

    /// fragment 수정자 — 흑우 `HwooBody.fragment` 와 같은 머리(디퓨즈 P · 피부 S · 피부 비율 β · 물체 좌표 값들) + 루비 무늬 + 출력.
    package static func fragment(faceOff: Bool = false) -> String {
        """
        #pragma arguments
        texture2d<float> ckShadeMap;
        #pragma varyings
        float3 ckVP;
        float2 ckUV;
        float3 ckVN;
        float3 ckVE;
        float3 ckRb;
        #pragma body
        constexpr sampler ckSmp(coord::normalized, filter::linear, mip_filter::linear, address::repeat);
        float3 ckLin = clamp(_surface.diffuse.rgb, float3(0.0), float3(1.0));
        float3 ckSL = clamp(ckShadeMap.sample(ckSmp, in.ckUV).rgb, float3(0.0), float3(1.0));
        float3 ckPe = 255.0 * select(1.055 * pow(ckLin, float3(1.0 / 2.4)) - 0.055, ckLin * 12.92, ckLin <= float3(0.0031308));
        float3 ckSe = 255.0 * select(1.055 * pow(ckSL, float3(1.0 / 2.4)) - 0.055, ckSL * 12.92, ckSL <= float3(0.0031308));
        float3 ckDv = ckPe - ckSe;
        float3 ckKs = \(String(format: "float3(%.2f, %.2f, %.2f)", blushSRGB.x, blushSRGB.y, blushSRGB.z)) - ckSe;
        float ckAk = dot(ckDv, ckKs) / max(1e-6, dot(ckKs, ckKs));
        float ckRes = length(ckDv - clamp(ckAk, 0.0, 1.0) * ckKs);
        float3 ckAd = ckDv / min(-ckSe, float3(-1e-3));
        float3 ckAb = ckDv / max(float3(255.0) - ckSe, float3(1e-3));
        float3 ckAc = select(ckAb, ckAd, ckDv < float3(0.0));
        float ckCover = clamp(max(ckAc.r, max(ckAc.g, ckAc.b)), 0.0, 1.0);
        float3 ckF = ckSe + ckDv / max(ckCover, 1e-3);
        float ckFY = dot(ckF, float3(0.299, 0.587, 0.114)) / 255.0;
        float ckFm = min(ckF.r, min(ckF.g, ckF.b)) / 255.0;
        float ckTrust = max(1.0 - smoothstep(0.19, 0.25, ckFY), smoothstep(0.88, 0.95, ckFm));
        float ckOld = clamp(1.0 - length(ckDv) / 80.0, 0.0, 1.0);
        float ckBeta = (ckRes <= 20.0 && ckAk > -0.1 && ckAk < 1.1) ? 1.0 - clamp(ckAk, 0.0, 1.0) : mix(ckOld, 1.0 - ckCover, ckTrust);
        float ckShade = clamp(dot(ckSL, float3(0.2126, 0.7152, 0.0722)) / \(f5(skinYRef)), 0.40, 1.45);
        float3 ckP = in.ckVP;
        float3 ckVn = normalize(in.ckVN);
        float3 ckEye = normalize(-in.ckVE);
        float ckNV = min(abs(dot(ckVn, ckEye)), 1.0);
        float ckT = (\(f5(bodyTop)) - ckP.y) / \(f5(bodyHeight));
        float ckFx = ckP.x / 0.60;
        float ckFy = (ckP.y - 0.34) / 0.30;
        float ckFace = (1.0 - smoothstep(0.85, 1.15, ckFx * ckFx + ckFy * ckFy)) * smoothstep(0.05, 0.25, ckP.z);
        float3 ckBase = float3(1.0);
        float3 ckAdd = float3(0.0);
        float ckShadeMix = 1.0;
        \(pattern)
        \(bodyOutput(faceOff: faceOff))
        """
    }
}
