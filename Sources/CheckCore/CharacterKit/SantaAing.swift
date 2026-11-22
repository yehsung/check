import Foundation
import simd

// MARK: - 산타 아잉이 — 크리스마스 기간 선물 캐릭터 (시안 S3 '수염 산타')
//
// 대표(2026-11-18 #d_3VZdglOgRABx) "산타아잉이는 그냥 주고, 루돌프 아잉이는 따로 이벤트를 기획하자. 지금할건 아니고 크리스마스 전에는 이벤트
// 기획하고 다 추가해놓는걸로." — 산타 아잉이는 빼빼로처럼 **기간 선물**(선물 종류 'santa' · 운영자 지급 · 고를 것 없이 받기 · 기간 뒤 안 받은 선물은
// 서버가 거둔다)이다. 루돌프(순록 아잉이)는 이 일에 없다.
// 그림 S3 '수염 산타': 원래 둥근 아잉 몸매 그대로(몸을 늘이거나 빚지 않는다) — 흰 수염이 몸 앞을 감싸고, 살구빛 얼굴 · 흰 콧수염 · 분홍 코 ·
//   빨간 모자 머리(정수리 쪽 빨강) · 흰 털 챙 · 털 방울 · 빨간 몸 · 검은 허리띠 · 아래 흰 털 단 · 검은 장화 · 둥근 팔(빨간 소매 · 흰 소맷부리 ·
//   검은 벙어리장갑). 원래의 지느러미 팔은 몸 겉면으로 접는다(둥근 팔이 따로 붙는다).
// 시안 렌더러 `~/.claude/projects/-Users-yesung-check/xmas-aing/santa/parts-santa.swift.txt` 의 S3 안(stClean · stRedBody · stBelt(arm: false) ·
//   stBeard(mus: false) · stBrim(0.085, 0.150) · stHem(from: 0.835) · 홍조 볼 + stCrownBall · stMustache · stBoots · stArms · 팔 접기 stCollapse)의
//   식을 앱 몸 셰이더 · 장식(`SantaAingFinish`)과 초상 생성기(`scripts/make-santa-aing.swift`)가 같은 값으로 쓴다.
// 이 파일은 Foundation · simd 만 쓴다 — 생성기가 이 파일만 같이 컴파일한다.

/// 산타 아잉이 id · 이름 · 그림 파일 이름 · "그릴 수 있다"의 판정. **파일 이름을 적는 곳은 여기 하나다.**
package nonisolated enum SantaAingArt {
    /// 서버 CHECK · 가격표(`gift_only = true` · `gift_kind = 'santa'` · `min_protocol = 11`) · `character_gifts.options` 의 id 와 같다.
    package static let characterID = "aing_santa"
    /// 표시 이름 — 한 곳.
    package static let displayName = "산타 아잉이"
    package static let resourceExtension = "png"

    /// 초상(192×192). 이름 규칙은 `<id>-<표정>`.
    package static let neutralPortraitResourceName = "\(characterID)-neutral"
    package static let negativePortraitResourceName = "\(characterID)-negative"
    package static var portraitResourceNames: [String] { [neutralPortraitResourceName, negativePortraitResourceName] }

    /// 맥 3D 마감 재료 — 무지개와 같이 쓰는 라벤더 밝기 맵(디퓨즈 합성 · 셰이더 인자 ckShadeMap). 수염 · 모자 · 장화 · 팔은 코드가 만든다.
    package static let shadeResourceName = "aing_rainbow-shade"
    package static var finishResourceNames: [String] { [shadeResourceName] }

    package enum Platform: Sendable { case mac, phone }

    package static func requiredResourceNames(for platform: Platform) -> [String] {
        switch platform {
        case .mac: return portraitResourceNames + finishResourceNames
        case .phone: return portraitResourceNames
        }
    }

    /// 이 빌드가 산타 아잉이를 그릴 수 있는가 — 필요한 그림이 **전부** 있을 때만. 능력 번호 11(`ShopWire.santaProtocol`)의 재료다.
    package static func isDrawable(on platform: Platform, resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames(for: platform).allSatisfy(resourceExists)
    }
}

// MARK: - 팔 접기(원래 지느러미 팔 → 몸 겉면)

/// 원래 메시의 지느러미 팔을 몸 겉면으로 접는다(시안 `stCollapse` 그대로). 둥근 팔은 장식으로 따로 붙는다.
///
/// ★ 메시(aing.scn)의 정점 자리는 **바꾸지 않는다**(루비 아잉이와 같은 길): 정점마다 '옮길 거리'와 '접힘 표시(0…1)'만 구워 텍스처 좌표 칸
///   1 · 2 에 싣고, 몸 셰이더의 geometry 단계가 그만큼 옮긴다(`SantaAingShader.geometry`). CPU 쪽 메시를 읽는 일(감은 눈 UV 마스크 · 카메라 구도 ·
///   클릭 판정)은 원래 아잉 그대로 돈다. 얼굴은 옮기지 않는다(팔 자리만) — 감은 눈 선 판도 그대로다.
package nonisolated enum SantaAingShape {
    /// 몸 반지름 표(실측 — 지느러미 팔을 뺀 둘레 최대, y = −0.85 + 0.05k). 시안 `stRTab` 그대로.
    package static let radiusTable: [Float] = [
        0.069, 0.285, 0.393, 0.472, 0.534, 0.579, 0.617, 0.647, 0.670, 0.690, 0.704, 0.717, 0.725, 0.731, 0.733, 0.734, 0.733,
        0.730, 0.727, 0.720, 0.713, 0.704, 0.695, 0.680, 0.664, 0.646, 0.625, 0.606, 0.574, 0.543, 0.495, 0.439, 0.366, 0.266, 0.104,
    ]

    /// 높이 y 의 몸 반지름(팔 뺀 둘레).
    package static func bodyRadius(_ y: Float) -> Float {
        let f = min(max((y + 0.85) / 0.05, 0), 33.999)
        let i = Int(f), t = f - Float(i)
        return radiusTable[i] + (radiusTable[i + 1] - radiusTable[i]) * t
    }

    static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 정점 하나 → (접은 점, 접힘 표시 0…1). 표시는 팔뿌리 둘레 몸 겉면까지 넓게 — 몸 셰이더가 그 자리 원래 그림(보라 팔 칠 · 팔뿌리 그늘)을
    /// 버리고 음영을 몸 법선으로 다시 낸다.
    package static func collapse(_ p: SIMD3<Float>) -> (SIMD3<Float>, Float) {
        let r = (p.x * p.x + p.z * p.z).squareRoot()
        guard p.y > -0.72, p.y < 0.38, r > 1e-4 else { return (p, 0) }
        let th = abs(atan2(p.x, p.z))
        let w = smooth(0.80, 1.00, th) * (1 - smooth(2.14, 2.34, th))
        let R = bodyRadius(p.y)
        guard w > 0 else { return (p, 0) }
        let d = r - R
        let flag = w * smooth(-0.035, -0.005, d) * smooth(-0.74, -0.62, p.y) * (1 - smooth(0.26, 0.36, p.y))
        guard d > 0 else { return (p, flag) }
        let rn = R + 0.004 * tanh(d / 0.004)
        let r2 = r + (rn - r) * w
        return (SIMD3(p.x * r2 / r, p.y, p.z * r2 / r), flag)
    }

    /// 정점마다 구운 값 — 옮길 거리(물체 좌표)와 접힘 표시.
    package struct Baked: Sendable, Equatable {
        package var displacement: [SIMD3<Float>]
        package var fold: [Float]
        package var count: Int { displacement.count }
    }

    /// 메시 정점 전부를 굽는다(결정적 — 같은 입력이면 같은 값).
    package static func bake(_ positions: [SIMD3<Float>]) -> Baked {
        var out = Baked(displacement: [], fold: [])
        out.displacement.reserveCapacity(positions.count)
        out.fold.reserveCapacity(positions.count)
        for p in positions {
            let (q, flag) = collapse(p)
            out.displacement.append(q - p)
            out.fold.append(flag)
        }
        return out
    }
}

// MARK: - 몸 셰이더(시안 S3)

/// 산타 몸 셰이더. 틀(β 얼굴 지키기 · 타원체 법선)은 지역 아잉이와 같고, 출력은 시안 렌더러와 **같은 선형 식**(얼굴 밖 원래 그림의 잔점을 버림 ·
/// 홍조 볼)이다. geometry 단계가 팔 접기 거리만큼 정점을 옮긴다.
package nonisolated enum SantaAingShader {
    package static let bodyTop = 0.848950
    package static let bodyHeight = 1.695736
    package static let ellipsoid = SIMD3<Double>(0.6084, 0.7191, 0.5329)
    package static let skinYRef = 0.56530
    package static let blushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
    package static let shadeMapKey = "ckShadeMap"

    // 색(sRGB 16진) — 시안 S3.
    package static let red = 0xD8252D          // 산타 빨강
    package static let redDeep = 0x8A0E19      // 가장자리 짙은 빨강
    package static let furWhite = 0xFFFFFF     // 흰 털
    package static let furShade = 0xD5DBE6     // 털 그늘
    package static let beardShade = 0xD3D9E4   // 수염 그늘
    package static let black = 0x1E1F25        // 허리띠 · 장화 · 장갑
    package static let peach = 0xFFD9C7        // 살구빛 얼굴

    /// 흰 털 챙(모자 아래 끝) 높이 t 구간 · 아래 털 단 시작 t · 허리띠 t 구간(정수리 0 → 바닥 1).
    package static let brim = (t0: 0.085, t1: 0.150)
    package static let hemFrom = 0.835
    package static let belt = (t0: 0.600, t1: 0.665)

    static func f1(_ v: Double) -> String { String(format: "%.5f", v) }
    static func f3v(_ v: SIMD3<Double>) -> String { String(format: "float3(%.5f, %.5f, %.5f)", v.x, v.y, v.z) }
    static func toLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    package static func linear(_ hex: Int) -> SIMD3<Double> {
        SIMD3(toLinear(Double((hex >> 16) & 255) / 255), toLinear(Double((hex >> 8) & 255) / 255), toLinear(Double(hex & 255) / 255))
    }
    static func f3(_ hex: Int) -> String { f3v(linear(hex)) }

    /// geometry 단계: 팔 접기 거리(칸 1 · 2)만큼 정점을 옮기고, 무늬 좌표 ckVP · 법선 ckVN 은 **옮긴 자리**의 타원체 법선(시안 S3 — 몸 모양은 그대로라
    /// 야코비안이 없다). 접힘 표시는 ckFn.x 로 넘긴다.
    package static let geometry = """
    #pragma varyings
    float3 ckVP;
    float2 ckUV;
    float3 ckVN;
    float3 ckVE;
    float3 ckFn;
    #pragma body
    float3 ckQ = _geometry.position.xyz + float3(_geometry.texcoords[1].x, _geometry.texcoords[1].y, _geometry.texcoords[2].x);
    _geometry.position.xyz = ckQ;
    out.ckVP = ckQ;
    out.ckFn = float3(_geometry.texcoords[2].y, 0.0, 0.0);
    out.ckVE = (scn_node.modelViewTransform * float4(ckQ, 1.0)).xyz;
    out.ckUV = _geometry.texcoords[0];
    float3 ckG = (ckQ - float3(0.0, 0.001, 0.0)) / (\(f3v(ellipsoid)) * \(f3v(ellipsoid)));
    out.ckVN = (scn_node.normalTransform * float4(ckG, 0.0)).xyz;
    """

    /// 값 잡음(3D 격자 · 결정적) — 시안 `hrNoise` 그대로. 이름 `name` 의 float 하나를 선언한다.
    static func noise(_ name: String, _ p: String, salt: Double = 0) -> String {
        func corner(_ x: Int, _ y: Int, _ z: Int) -> String {
            "fract(sin(dot(\(name)i + float3(\(x).0, \(y).0, \(z).0), float3(127.1, 311.7, 74.7)) + \(f1(salt))) * 43758.5453)"
        }
        return """
        float \(name);
        {
            float3 \(name)p = \(p);
            float3 \(name)i = floor(\(name)p);
            float3 \(name)f = fract(\(name)p);
            float3 \(name)u = \(name)f * \(name)f * (3.0 - 2.0 * \(name)f);
            float a0 = mix(\(corner(0, 0, 0)), \(corner(1, 0, 0)), \(name)u.x);
            float a1 = mix(\(corner(0, 1, 0)), \(corner(1, 1, 0)), \(name)u.x);
            float a2 = mix(\(corner(0, 0, 1)), \(corner(1, 0, 1)), \(name)u.x);
            float a3 = mix(\(corner(0, 1, 1)), \(corner(1, 1, 1)), \(name)u.x);
            \(name) = mix(mix(a0, a1, \(name)u.y), mix(a2, a3, \(name)u.y), \(name)u.z);
        }

        """
    }

    /// 접은 팔 자리 + 잔점 지우기(시안 `stClean`): 원래 그림(보라 팔 칠 · 텍스처 얼룩)을 버리고, 접은 자리 음영은 몸 법선으로 다시 낸다.
    static let clean = """
    ckKeepTex = 0.0;
    {
        float fin = clamp(in.ckFn.x, 0.0, 1.0);
        ckLin = mix(ckLin, ckSL, fin);
        ckShade = mix(ckShade, clamp(0.88 + 0.62 * ckN.y, 0.50, 1.30), fin);
    }

    """

    /// 산타 빨강 몸: 윤 있는 빨강(가장자리는 짙게) + 좁은 반짝 + 넓은 윤 + 붉은 테(시안 `stRedBody`).
    static let redBody = """
    ckBase = mix(\(f3(red)), \(f3(redDeep)), pow(1.0 - ckNV, 2.0) * 0.55);
    ckShadeMix = 1.0;
    {
        float3 L = normalize(float3(-0.38, 0.55, 0.74));
        float g1 = pow(max(dot(ckVn, L), 0.0), 90.0);
        float g2 = pow(max(dot(ckVn, L), 0.0), 9.0);
        float rim = pow(1.0 - ckNV, 3.0);
        float hiF = 1.0 - 0.85 * ckFace;
        ckAdd += float3(1.0, 0.95, 0.95) * \(f1(1.0)) * (g1 * 0.60 + g2 * 0.08) * hiF;
        ckAdd += \(f3(0xFF7A7A)) * \(f1(1.0)) * rim * 0.10;
    }

    """

    /// 흰 털 칠(마스크 m · 잡음 nz 를 이미 계산한 블록 안에서 쓴다 — 시안 `stFurInk`).
    static func furInk(_ m: String, _ nz: String, tint: Int = furWhite, shade: Int = furShade) -> String {
        """
            {
                float3 Lf = normalize(float3(-0.38, 0.55, 0.74));
                float lam = max(dot(ckVn, Lf), 0.0);
                float3 fc = mix(\(f3(shade)), \(f3(tint)), clamp(0.30 + 0.60 * \(nz) + 0.30 * lam, 0.0, 1.0));
                ckBase = mix(ckBase, fc, \(m));
                ckAdd *= 1.0 - 0.80 * \(m);
                ckAdd += float3(1.0) * pow(1.0 - ckNV, 3.0) * 0.05 * \(m);
                ckShadeMix = mix(ckShadeMix, 0.90, \(m));
            }

        """
    }

    /// 검은 허리띠(팔 칠 없음 — 둥근 팔은 장식이다. 시안 `stBelt(arm: false)`).
    static let beltBand = """
    {
        float rgArm = 0.0;
        float aa = ckAAT;
        float b = smoothstep(\(f1(belt.t0)) - aa, \(f1(belt.t0)) + aa, ckT) * (1.0 - smoothstep(\(f1(belt.t1)) - aa, \(f1(belt.t1)) + aa, ckT)) * (1.0 - rgArm);
        float3 L = normalize(float3(-0.38, 0.55, 0.74));
        float3 bc = \(f3(black)) * (0.9 + 0.3 * pow(max(dot(ckVn, L), 0.0), 3.0));
        ckBase = mix(ckBase, bc, b);
        ckAdd = mix(ckAdd, float3(1.0) * (pow(max(dot(ckVn, L), 0.0), 70.0) * 0.55 + pow(1.0 - ckNV, 3.0) * 0.06), b);
        ckShadeMix = mix(ckShadeMix, 0.8, b);
    }

    """

    /// 살구빛 얼굴 + 몸 앞을 감싸는 흰 수염(얼굴 아래 · 옆 구레나룻 → 가슴까지, 아래 끝 물결). 콧수염은 장식이다(시안 `stBeard(mus: false)`).
    static var beard: String {
        noise("bdA", "ckP * 30.0 + float3(1.5, 6.1, 3.9)") + noise("bdB", "ckP * 9.0 + float3(7.4, 3.2, 8.3)", salt: 7) + """
        {
            float front = smoothstep(0.02, 0.22, ckP.z);
            float fx = ckP.x / 0.53, fy = (ckP.y - 0.37) / 0.245;
            float fd = fx * fx + fy * fy;
            float aaF = max(fwidth(fd), 1e-4) * 1.5;
            float face = (1.0 - smoothstep(1.0 - aaF, 1.0 + aaF, fd)) * front;
            float3 pc = \(f3(peach));
            ckBase = mix(ckBase, pc, face);
            ckAdd = mix(ckAdd, ckAdd * 0.6, face);
            float bx = ckP.x / 0.64;
            float wav = 0.035 * abs(sin(ckP.x * 17.0)) + 0.03 * (bdB - 0.5);
            float yb = -0.46 + 0.62 * bx * bx + wav;
            float aaY = max(fwidth(ckP.y), 1e-4) * 1.5;
            float below = smoothstep(yb - aaY, yb + aaY, ckP.y);
            float top = 1.0 - smoothstep(0.60 - aaY, 0.60 + aaY, ckP.y);
            float side = 1.0 - smoothstep(1.00, 1.18, abs(ckTh));
            float beard = below * top * side * smoothstep(-0.10, 0.10, ckP.z) * (1.0 - face);
            float m = clamp(beard, 0.0, 1.0);
            float curl = 0.5 + 0.5 * sin(ckP.y * 44.0 + 3.2 * sin(ckP.x * 10.0 + 0.4) + 2.4 * bdB);
            float nz = clamp(0.30 + 0.55 * curl + 0.15 * bdA, 0.0, 1.0);
        \(furInk("m", "nz", shade: beardShade))
            ckBase = mix(ckBase, \(f3(0xAFB9CB)), pow(1.0 - ckNV, 2.2) * 0.60 * m);
        }

        """
    }

    /// 이마 흰 털 띠(모자 챙 — 시안 `stBrim(0.085, 0.150)`). 그 위(정수리 쪽)는 빨간 몸 그대로라 모자 머리가 된다.
    static var brimBand: String {
        noise("brA", "ckP * 24.0 + float3(6.3, 2.1, 9.7)") + noise("brB", "ckP * 7.0 + float3(1.4, 8.2, 2.3)", salt: 4) + """
        {
            float e0 = \(f1(brim.t0)) - 0.010 * abs(sin(ckTh * 8.0 + 0.5)) - 0.012 * (brB - 0.5);
            float e1 = \(f1(brim.t1)) + 0.010 * abs(sin(ckTh * 8.0 + 1.3)) + 0.012 * (brB - 0.5);
            float aa = ckAAT * 1.5;
            float m = smoothstep(e0 - aa, e0 + aa, ckT) * (1.0 - smoothstep(e1 - aa, e1 + aa, ckT));
            float nz = brA * 0.7 + brB * 0.3;
        \(furInk("m", "nz"))
        }

        """
    }

    /// 아래 흰 털 단(시안 `stHem(from: 0.835)` — 가장자리는 보송한 물결).
    static var hem: String {
        noise("hmA", "ckP * 24.0 + float3(2.3, 5.1, 7.7)") + noise("hmB", "ckP * 7.0 + float3(4.4, 1.2, 3.3)", salt: 2) + """
        {
            float edge = \(f1(hemFrom)) - 0.016 * abs(sin(ckTh * 9.0)) - 0.020 * (hmB - 0.5);
            float aa = ckAAT * 1.5;
            float m = smoothstep(edge - aa, edge + aa, ckT);
            float nz = hmA * 0.7 + hmB * 0.3;
        \(furInk("m", "nz"))
        }

        """
    }

    /// 홍조 볼(시안 `flushCheeks` — 이슬 Q 와 같다): 볼터치 텍셀을 더 진한 장밋빛(출력 단계) + 볼 중심 둘레 몸색을 붉게.
    static let flushCheeks = """
    ckFlush = 1.0;
    float2 ckC1 = float2(ckP.x - 0.39, ckP.y - 0.22), ckC2 = float2(ckP.x + 0.39, ckP.y - 0.22);
    float ckHalo = (exp(-dot(ckC1, ckC1) / 0.024) + exp(-dot(ckC2, ckC2) / 0.024)) * smoothstep(0.30, 0.50, ckP.z);
    ckBase = mix(ckBase, ckBase * float3(1.7, 0.62, 0.70) + float3(0.12, 0.0, 0.02), clamp(ckHalo, 0.0, 1.0) * 0.75);

    """

    /// 무늬 전부(시안 S3 의 순서 그대로).
    package static var pattern: String { clean + redBody + beltBand + beard + brimBand + hem + flushCheeks }

    /// 몸 출력 — 시안 렌더러와 같은 선형 식(`ckKeepTex` 0 이면 얼굴 밖 원래 그림의 잔점을 버린다 · 홍조 볼).
    /// `faceOff` = 얼굴 상자를 끈다(초상 생성기의 '얼굴 없는 몸').
    package static func bodyOutput(faceOff: Bool = false) -> String {
        """
        float3 ckCol = ckBase * mix(1.0, ckShade, ckShadeMix) + ckAdd;
        bool ckInFace = \(faceOff ? "false" : "ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62");
        float ckB = ckInFace ? ckBeta : 1.0;
        float ckDrop = (1.0 - ckKeepTex) * (ckInFace ? smoothstep(0.80, 1.0, ckB) : 1.0);
        float3 ckOut = ckLin + ckB * (ckCol - ckSL) - ckDrop * (ckLin - ckSL);
        float ckBlushAmt = (ckInFace && ckRes <= 20.0 && ckAk > 0.0) ? clamp(ckAk * 1.3, 0.0, 1.0) : 0.0;
        ckOut = mix(ckOut, ckOut * float3(1.0, 0.50, 0.56), ckBlushAmt * ckFlush);
        _output.color = float4(clamp(ckOut, float3(0.0), float3(1.0)), 1.0);
        """
    }

    package static func fragment(faceOff: Bool = false) -> String {
        """
        #pragma arguments
        texture2d<float> ckShadeMap;
        #pragma varyings
        float3 ckVP;
        float2 ckUV;
        float3 ckVN;
        float3 ckVE;
        float3 ckFn;
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
        float ckShade = clamp(dot(ckSL, float3(0.2126, 0.7152, 0.0722)) / \(f1(skinYRef)), 0.40, 1.45);
        float3 ckP = in.ckVP;
        float3 ckN = normalize((ckP - float3(0.0, 0.001, 0.0)) / (\(f3v(ellipsoid)) * \(f3v(ellipsoid))));
        float3 ckVn = normalize(in.ckVN);
        float3 ckEye = normalize(-in.ckVE);
        float ckNV = min(abs(dot(ckVn, ckEye)), 1.0);
        float ckT = (\(f1(bodyTop)) - ckP.y) / \(f1(bodyHeight));
        float ckTh = atan2(ckP.x, ckP.z);
        float ckR = length(ckP.xz);
        float ckAAT = max(fwidth(ckT), 1e-5);
        float ckFx = ckP.x / 0.60;
        float ckFy = (ckP.y - 0.34) / 0.30;
        float ckFace = (1.0 - smoothstep(0.85, 1.15, ckFx * ckFx + ckFy * ckFy)) * smoothstep(0.05, 0.25, ckP.z);
        float3 ckBase = float3(1.0);
        float3 ckAdd = float3(0.0);
        float ckShadeMix = 1.0;
        float ckFlush = 0.0;
        float ckKeepTex = 1.0;
        \(pattern)
        \(bodyOutput(faceOff: faceOff))
        """
    }
}

// MARK: - 장식(털 방울 · 콧수염 · 코 · 장화 · 둥근 팔)

/// 장식 조각의 구운 빛 모양(시안 `Look` — 앰비언트 · 반짝 세기 · 반짝 좁기 · 감싸기 · 가장자리 테).
package nonisolated struct SantaDecorLook: Sendable, Equatable {
    package var ambient: Double
    package var spec: Double
    package var gloss: Double
    package var wrap: Double
    package var rim: Double

    package init(ambient: Double, spec: Double, gloss: Double, wrap: Double, rim: Double) {
        self.ambient = ambient
        self.spec = spec
        self.gloss = gloss
        self.wrap = wrap
        self.rim = rim
    }
}

/// 장식 조각 하나의 모양 · 색(순수 — 맥 마감과 초상 생성기가 같은 조각 · 같은 굽기로 노드를 만든다). 좌표는 몸 메시 노드의 물체 좌표다.
/// 닫힘(pos · albedo)은 값만 잡은 순수 함수라 여러 코어 굽기(`SantaDecorBake.texture`)에서 같이 읽어도 안전하다(`@unchecked Sendable`).
package nonisolated struct SantaDecorPiece: @unchecked Sendable {
    package let name: String
    package let nu: Int
    package let nv: Int
    package let closedU: Bool
    package let texW: Int
    package let texH: Int
    /// (u, v) → 물체 좌표 점.
    package let pos: (Float, Float) -> SIMD3<Float>
    /// (u, v) → 선형 색.
    package let albedo: (Double, Double) -> SIMD3<Double>
    package let look: SantaDecorLook
}

/// 산타 장식 — 시안 S3 의 stCrownBall · stMustache · stBoots · stArms 그대로(이름만 `check.santa.*`).
package nonisolated enum SantaAingDecor {
    /// 장식 루트 노드 이름(얼굴 탐색 · 몸 클릭 · 상자 계산이 뺀다 — 맥 `AingDecor.rootNames`).
    package static let decorNodeName = "check.santaDecor"

    /// 정수리 털 방울 자리(몸 윗면 hitTest 의 x · z) · 반지름 · 모자에 묻는 몫.
    package static let crownX: Float = 0
    package static let crownZ: Float = -0.02
    package static let pompomRadius: Float = 0.125
    package static let pompomSink: Float = 0.30
    /// 콧수염(입 양옆 위 — 몸 앞면 hitTest 의 x = ±gap · y) · 코(앞면 (0, noseY)).
    package static let mustacheY: Float = 0.282
    package static let mustacheGap: Float = 0.105
    package static let noseY: Float = 0.322
    package static let noseRadius: Float = 0.036

    static let ellipsoid = SIMD3<Float>(0.6084, 0.7191, 0.5329)

    // MARK: 도우미(시안 rgFrame · stBlob · hrTube)

    /// 자기 좌표 틀: 원점 o · x 축 = xAxis · z 는 zRef 쪽(직교화) · y = z × x.
    static func frame(_ o: SIMD3<Float>, x xAxis: SIMD3<Float>, zRef: SIMD3<Float>) -> simd_float4x4 {
        let x = simd_normalize(xAxis)
        let z = simd_normalize(zRef - x * simd_dot(zRef, x))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(o, 1)))
    }

    static func apply(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> {
        let q = m * SIMD4<Float>(p.x, p.y, p.z, 1)
        return SIMD3(q.x, q.y, q.z)
    }

    static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ t: Double) -> SIMD3<Double> { a + (b - a) * min(max(t, 0), 1) }

    static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func lin(_ hex: Int) -> SIMD3<Double> { SantaAingShader.linear(hex) }

    /// 바깥을 보는 (초)타원체 조각(시안 `stBlob`). albedo 는 자기 단위 좌표(−1…1)를 받는다.
    static func blob(_ name: String, frame: simd_float4x4 = matrix_identity_float4x4, c: SIMD3<Float>, r: SIMD3<Float>,
                     rot: simd_quatf = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0)), e: Float = 1, look: SantaDecorLook,
                     nu: Int = 64, nv: Int = 40, tex: Int = 256, albedo: @escaping (SIMD3<Float>) -> SIMD3<Double>) -> SantaDecorPiece {
        func C(_ w: Float) -> Float { let c = cos(w); return (c < 0 ? -1 : 1) * pow(abs(c), e) }
        func S(_ w: Float) -> Float { let s = sin(w); return (s < 0 ? -1 : 1) * pow(abs(s), e) }
        let local: (Float, Float) -> SIMD3<Float> = { u, v in
            let eta = -Float.pi / 2 + Float.pi * v, om = Float.pi - 2 * Float.pi * u
            return SIMD3(C(eta) * C(om), S(eta), C(eta) * S(om))
        }
        let m3 = simd_float3x3(rot)
        return SantaDecorPiece(name: "check.santa." + name, nu: nu, nv: nv, closedU: true, texW: tex, texH: tex,
                               pos: { u, v in apply(frame, c + m3 * (local(u, v) * r)) },
                               albedo: { u, v in albedo(local(Float(u), Float(v))) }, look: look)
    }

    /// 중심선 c · 반지름 r 의 관 위 점(시안 `hrTube` — 기준 축 (0, 0, 1)).
    static func tube(_ c: @escaping (Float) -> SIMD3<Float>, _ r: @escaping (Float) -> Float) -> (Float, Float) -> SIMD3<Float> {
        { u, v in
            let e: Float = 1e-3
            let va = max(v - e, 0), vb = min(v + e, 1)
            var t = c(vb) - c(va)
            if simd_length(t) < 1e-8 { t = SIMD3(0, 1, 0) }
            t = simd_normalize(t)
            var a = simd_cross(t, SIMD3<Float>(0, 0, 1))
            if simd_length(a) < 1e-4 { a = simd_cross(t, SIMD3<Float>(1, 0, 0)) }
            a = simd_normalize(a)
            let b = simd_cross(t, a)
            let ang = 2 * Float.pi * u
            return c(v) + r(v) * (cos(ang) * a + sin(ang) * b)
        }
    }

    // MARK: 조각

    /// 정수리 털 방울(큰 덩이 몇 개로 울퉁불퉁한 윤곽 · 아랫면 회청색 그늘 — 시안 `stFluffBall` · `stCrownBall(r: 0.125, sink: 0.30)`).
    /// `crown` · `normal` = 몸 윗면 (crownX, crownZ) 의 겉 점과 바깥 법선.
    package static func pompom(crown: SIMD3<Float>, normal: SIMD3<Float>) -> SantaDecorPiece {
        let r = pompomRadius, lumps: Float = 0.07
        let u = simd_normalize(normal)
        let c = crown + u * (r * (1 - pompomSink))
        let ref: SIMD3<Float> = abs(u.y) < 0.9 ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1)
        let xA = simd_normalize(simd_cross(u, ref))
        let zA = simd_cross(xA, u)
        func dir(_ uu: Float, _ vv: Float) -> SIMD3<Float> {
            let eta = -Float.pi / 2 + Float.pi * vv, om = Float.pi - 2 * Float.pi * uu
            return SIMD3(cos(eta) * cos(om), sin(eta), cos(eta) * sin(om))
        }
        func rad(_ d: SIMD3<Float>) -> Float {
            let big = sin(d.x * 3.1 + 1.3) * sin(d.y * 2.9 + 0.4) * sin(d.z * 3.3 + 2.1)
            let mid = sin(d.x * 7.3 + 0.2) * sin(d.y * 6.9 + 1.9) * sin(d.z * 7.7 + 0.8)
            let fine = sin(d.x * 23 + 0.9) * sin(d.y * 21 + 0.3) * sin(d.z * 25 + 1.7)
            return r * (1 + lumps * big * 1.6 + lumps * 0.45 * mid + 0.012 * fine)
        }
        let topC = lin(0xFFFDF8), underC = lin(0xD9DDE6)
        return SantaDecorPiece(name: "check.santa.pompom", nu: 96, nv: 64, closedU: true, texW: 256, texH: 256,
                               pos: { uu, vv in
                                   let d = dir(uu, vv)
                                   return c + (xA * d.x + u * d.y + zA * d.z) * rad(d)
                               },
                               albedo: { uu, vv in
                                   let d = dir(Float(uu), Float(vv))
                                   let w = xA * d.x + u * d.y + zA * d.z
                                   let k = Double(0.5 + 0.5 * w.y)
                                   let soft = Double(sin(d.x * 5.3 + 0.7) * sin(d.y * 4.9 + 2.2) * sin(d.z * 5.7 + 1.1)) * 0.5 + 0.5
                                   return mix(underC, topC, smooth(0.0, 0.55, k)) * (0.97 + 0.04 * soft)
                               },
                               look: SantaDecorLook(ambient: 0.82, spec: 0.10, gloss: 10, wrap: 0.60, rim: 0.0))
    }

    /// 콧수염 한 덩이(입 양옆 위로 말려 올라감 — 시안 `stMustache`). `root` = 몸 앞면 (side × gap, mustacheY) 의 겉 점. side = +1 오른쪽 · −1 왼쪽.
    package static func mustache(root p: SIMD3<Float>, side: Float) -> SantaDecorPiece {
        let n = simd_normalize(p / (ellipsoid * ellipsoid))
        let ref = SIMD3<Float>(side, 0.30, 0)
        let xd = simd_normalize(ref - n * simd_dot(ref, n))
        let f = frame(p + n * 0.006, x: xd, zRef: n)
        return blob("mustache" + (side > 0 ? "R" : "L"), frame: f, c: .zero, r: SIMD3(0.105, 0.050, 0.040),
                    rot: simd_quatf(angle: side * 0.10, axis: SIMD3(0, 0, 1)), e: 0.9,
                    look: SantaDecorLook(ambient: 0.72, spec: 0.14, gloss: 14, wrap: 0.5, rim: 0.0), nu: 48, nv: 32, tex: 128) { q in
            let k = Double(0.5 + 0.5 * q.y)
            return mix(lin(0xD3D9E4), lin(0xFFFDF8), 0.25 + 0.75 * k)
        }
    }

    /// 작은 분홍 코. `root` = 몸 앞면 (0, noseY) 의 겉 점.
    package static func nose(root p: SIMD3<Float>) -> SantaDecorPiece {
        let r = noseRadius
        return blob("nose", c: p + SIMD3(0, 0, r * 0.35), r: SIMD3(r * 1.15, r, r * 0.85),
                    look: SantaDecorLook(ambient: 0.62, spec: 0.55, gloss: 40, wrap: 0.4, rim: 0.10), nu: 32, nv: 24, tex: 64) { _ in lin(0xF29A9A) }
    }

    /// 검은 장화 둘(몸 아래 앞 — 시안 `stBoots`).
    package static func boots() -> [SantaDecorPiece] {
        [Float(1), -1].map { side in
            let f = frame(SIMD3(side * 0.25, -0.80, 0.31), x: SIMD3(side * 0.22, 0, 1), zRef: SIMD3(0, 1, 0))
            return blob("boot" + (side > 0 ? "R" : "L"), frame: f, c: .zero, r: SIMD3(0.175, 0.13, 0.075), e: 0.8,
                        look: SantaDecorLook(ambient: 0.55, spec: 0.85, gloss: 55, wrap: 0.3, rim: 0.18)) { _ in lin(SantaAingShader.black) }
        }
    }

    /// 둥근 팔 한 짝: 빨간 소매(타원체) · 흰 털 소맷부리(고리) · 검은 벙어리장갑. 어깨는 몸 옆(접은 지느러미 팔 자리 — 시안 `stArms`).
    package static func arm(side: Float) -> [SantaDecorPiece] {
        let shoulderY: Float = 0.04, out: Float = 0.50, len: Float = 0.44, thick: Float = 0.118, fwd: Float = 0.10, mittenR: Float = 0.088
        let S = SIMD3<Float>(side * (SantaAingShape.bodyRadius(shoulderY) - 0.05), shoulderY, 0.02)
        let d = simd_normalize(SIMD3<Float>(side * out, -1, fwd))
        let z0 = simd_normalize(SIMD3<Float>(0, 0, 1) - d * d.z)
        let x0 = simd_cross(d, z0)
        let f = frame(S, x: x0, zRef: z0)     // 자기 y = 팔 방향
        let tag = side > 0 ? "R" : "L"
        let sc = lin(SantaAingShader.red)
        let sleeve = blob("sleeve" + tag, frame: f, c: SIMD3(0, len * 0.40, 0), r: SIMD3(thick, len * 0.50, thick * 0.94),
                          look: SantaDecorLook(ambient: 0.56, spec: 0.55, gloss: 42, wrap: 0.35, rim: 0.10), nu: 56, nv: 40, tex: 128) { p in
            mix(sc, sc * 0.78, Double(max(-p.y, 0)) * 0.35)
        }
        let cy = len * 0.80
        let ringR = thick * 0.80
        let ringPath: (Float) -> SIMD3<Float> = { v in
            let a = 2 * Float.pi * v
            return apply(f, SIMD3(ringR * cos(a), cy, ringR * 0.94 * sin(a)))
        }
        let cuffLow = lin(0xD9DDE6), cuffHigh = lin(0xFFFDF8)
        let cuff = SantaDecorPiece(name: "check.santa.cuff" + tag, nu: 24, nv: 96, closedU: true, texW: 64, texH: 256,
                                   pos: tube(ringPath, { v in 0.046 + 0.006 * sin(v * 2 * .pi * 7) }),
                                   albedo: { u, v in
                                       let k = 0.5 + 0.5 * sin(u * 2 * .pi)
                                       return mix(cuffLow, cuffHigh, 0.45 + 0.55 * k) * (0.96 + 0.05 * sin(v * 2 * .pi * 23))
                                   },
                                   look: SantaDecorLook(ambient: 0.72, spec: 0.10, gloss: 10, wrap: 0.5, rim: 0.0))
        let mitten = blob("mitten" + tag, frame: f, c: SIMD3(0, cy + mittenR * 0.85, 0.005), r: SIMD3(mittenR * 0.98, mittenR * 1.08, mittenR * 0.92),
                          look: SantaDecorLook(ambient: 0.55, spec: 0.80, gloss: 50, wrap: 0.30, rim: 0.18), nu: 40, nv: 28, tex: 64) { _ in
            lin(SantaAingShader.black)
        }
        return [sleeve, cuff, mitten]
    }

    /// 장식 전부(시안 S3 순서 — 털 방울 → 콧수염 둘 → 코 → 장화 둘 → 오른팔 → 왼팔).
    /// `crown` · `crownNormal` = 몸 윗면 (crownX, crownZ) 의 겉 점 · 법선, `mustacheRoots` = 앞면 (+gap, mustacheY) · (−gap, mustacheY) 의 겉 점,
    /// `noseRoot` = 앞면 (0, noseY) 의 겉 점.
    package static func pieces(crown: SIMD3<Float>, crownNormal: SIMD3<Float>, mustacheRoots: (right: SIMD3<Float>, left: SIMD3<Float>),
                               noseRoot: SIMD3<Float>) -> [SantaDecorPiece] {
        [pompom(crown: crown, normal: crownNormal), mustache(root: mustacheRoots.right, side: 1), mustache(root: mustacheRoots.left, side: -1),
         nose(root: noseRoot)] + boots() + arm(side: 1) + arm(side: -1)
    }
}

// MARK: - 장식 굽기(메시 · 빛을 구운 텍스처) — 맥 마감과 초상 생성기가 같은 값을 쓴다

/// 장식 조각 → 삼각형 메시와 몸 공간 고정 빛을 구운 텍스처(시안 `pieceNode` · `lit` 그대로 — 위 · 앞 · 살짝 왼쪽 주광 + 오른쪽 보조 반짝 + 가장자리 테).
package nonisolated enum SantaDecorBake {
    static let keyLight = simd_normalize(SIMD3<Double>(-0.30, 0.85, 0.45))
    static let viewLight = simd_normalize(SIMD3<Double>(0, 0.30, 1))
    static let fillLight = simd_normalize(SIMD3<Double>(0.70, 0.25, 0.65))

    /// 선형 색 하나에 빛을 굽는다.
    package static func lit(_ albedo: SIMD3<Double>, _ n: SIMD3<Double>, _ look: SantaDecorLook) -> SIMD3<Double> {
        let ndl = simd_dot(n, keyLight)
        let diff = min(max((ndl + look.wrap) / (1 + look.wrap), 0), 1)
        let ao = 1 - 0.22 * max(-n.y, 0)
        var c = albedo * (look.ambient + (1 - look.ambient) * diff) * ao
        let h = simd_normalize(keyLight + viewLight)
        c += SIMD3(repeating: pow(max(simd_dot(n, h), 0), look.gloss) * look.spec)
        let h2 = simd_normalize(fillLight + viewLight)
        c += SIMD3(repeating: pow(max(simd_dot(n, h2), 0), look.gloss * 1.4) * look.spec * 0.35)
        if look.rim > 0 { c += (albedo * 1.8 + SIMD3(repeating: 0.15)) * (pow(1 - max(simd_dot(n, viewLight), 0), 3) * look.rim) }
        return simd_clamp(c, .zero, SIMD3(repeating: 1))
    }

    /// 곡면 법선(u · v 편미분의 외적 — 극점은 조금 비켜 잰다).
    package static func normal(_ piece: SantaDecorPiece, _ u: Float, _ v: Float) -> SIMD3<Float> {
        func at(_ vv: Float) -> SIMD3<Float> {
            let e: Float = 1e-3
            let u0 = piece.closedU ? u - e : max(u - e, 0), u1 = piece.closedU ? u + e : min(u + e, 1)
            let v0 = max(vv - e, 0), v1 = min(vv + e, 1)
            return simd_cross(piece.pos(u1, vv) - piece.pos(u0, vv), piece.pos(u, v1) - piece.pos(u, v0))
        }
        var n = at(v)
        var nudge: Float = 0.004
        while simd_length(n) < 1e-9 && nudge < 0.1 {
            n = at(v < 0.5 ? v + nudge : v - nudge)
            nudge *= 2
        }
        return simd_length(n) < 1e-12 ? SIMD3(0, 1, 0) : simd_normalize(n)
    }

    /// 격자 메시(정점 (nu+1)(nv+1) · 삼각형 2·nu·nv — 바깥을 보는 감김).
    package struct Mesh: Sendable {
        package var positions: [SIMD3<Float>]
        package var normals: [SIMD3<Float>]
        package var uvs: [SIMD2<Float>]
        package var indices: [UInt32]
    }

    package static func mesh(_ piece: SantaDecorPiece) -> Mesh {
        var m = Mesh(positions: [], normals: [], uvs: [], indices: [])
        for j in 0...piece.nv { for i in 0...piece.nu {
            let u = Float(i) / Float(piece.nu), v = Float(j) / Float(piece.nv)
            m.positions.append(piece.pos(u, v))
            m.normals.append(normal(piece, u, v))
            m.uvs.append(SIMD2(u, v))
        } }
        let row = UInt32(piece.nu + 1)
        for j in 0..<UInt32(piece.nv) { for i in 0..<UInt32(piece.nu) {
            let a = j * row + i, b = a + 1, c = a + row, d = c + 1
            m.indices += [a, b, c, b, d, c]
        } }
        return m
    }

    static func srgbByte(_ v: Double) -> UInt8 {
        let c = min(max(v, 0), 1)
        let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (s * 255).rounded())))
    }

    /// 텍스처(texW × texH RGBA · sRGB · 불투명, 위 행부터) — 텍셀마다 albedo 2×2 표본 평균에 그 자리 법선의 빛을 굽는다. 행을 나눠 여러 코어로 굽는다.
    package static func texture(_ piece: SantaDecorPiece) -> [UInt8] {
        let w = piece.texW, h = piece.texH
        let rows = SantaRowBuffer(width: w, height: h)
        DispatchQueue.concurrentPerform(iterations: h) { y in
            var line = [UInt8](repeating: 255, count: w * 4)
            for x in 0..<w {
                var acc = SIMD3<Double>(0, 0, 0)
                for sy in 0..<2 { for sx in 0..<2 {
                    let u = (Double(x) + 0.25 + 0.5 * Double(sx)) / Double(w), v = (Double(y) + 0.25 + 0.5 * Double(sy)) / Double(h)
                    acc += piece.albedo(u, v)
                } }
                let u = Float((Double(x) + 0.5) / Double(w)), v = Float((Double(y) + 0.5) / Double(h))
                let nf = normal(piece, u, v)
                let c = lit(acc / 4, simd_normalize(SIMD3<Double>(Double(nf.x), Double(nf.y), Double(nf.z))), piece.look)
                line[x * 4] = srgbByte(c.x); line[x * 4 + 1] = srgbByte(c.y); line[x * 4 + 2] = srgbByte(c.z)
            }
            rows.set(y, line)
        }
        return rows.joined()
    }
}

/// 행 단위 굽기 결과를 모으는 자리(여러 코어가 다른 행을 쓴다 — 잠금으로만 지킨다).
private final class SantaRowBuffer: @unchecked Sendable {
    private var rows: [[UInt8]]
    private let lock = NSLock()

    init(width: Int, height: Int) {
        rows = Array(repeating: [], count: height)
    }

    func set(_ y: Int, _ line: [UInt8]) {
        lock.lock(); rows[y] = line; lock.unlock()
    }

    func joined() -> [UInt8] {
        lock.lock(); defer { lock.unlock() }
        return rows.flatMap { $0 }
    }
}
