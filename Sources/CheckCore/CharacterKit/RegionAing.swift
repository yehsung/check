import Foundation
import simd

// MARK: - 지역 아잉이 — 센터마다 하나씩 주는 선물 캐릭터 (부산 갈매기 · 서울)
//
// 대표(2026-11-10, 서버 확인 #d_i1SA8M2VJR5a) "근데 서울만의 캐릭터도 넣자 그래서 각센터 사람들 자기들 지역만의 아잉이 하나씩 갖게끔."
// 얻는 길 #d_RyTlg0ZZED04 "가. 우리 센터 선물" — 그 센터(`profiles.center` 'busan' · 'seoul') 사람 모두 자동으로 하나씩(선물 종류 'region',
//   고를 것 없이 받는다 · 기한 없음). 다른 센터 사람에게는 상점에 잠긴 칸으로만 선다. 센터는 가입 때 한 번 고르고 못 바꾼다.
// 부산 그림 #d_afa6DRyExPLp "G1 갈매기가 된 아잉이" — 흰 갈매기 몸 · 회색 등 · 양 팔이 날개(끝 검정 · 흰 점) · 입 자리에 노란 부리
//   (끝 검은 띠 + 빨간 점 — 괭이갈매기) · 노란 물갈퀴 발 · 꼬리깃(검은 띠). 서울 그림은 고르는 중(2차 #d_MOlCB5s8cPsm).
// 시안 렌더러 `~/.claude/projects/-Users-yesung-check/region-aing/parts-region.swift.txt`(rgGullBody · rgFaceBeak · rgFeet · rgTailFeathers)의
// 식을 앱 몸 셰이더 · 장식(`RegionAingFinish`)과 초상 생성기(`scripts/make-region-aing.swift`)가 같은 값으로 쓴다.
// 이 파일은 Foundation · simd 만 쓴다 — 생성기가 이 파일만 같이 컴파일한다.

/// 지역 아잉이 id · 이름 · 그림 파일 이름 · "그릴 수 있다"의 판정. **파일 이름 · 센터 짝을 적는 곳은 여기 하나다.**
package nonisolated enum RegionAingArt {
    /// 부산 센터 아잉이(갈매기). 서버 CHECK · 가격표 · `character_gifts.options` 의 id 와 같다.
    package static let busanID = "aing_busan"
    /// 서울 센터 아잉이. 그림을 고르는 중이다 — 카탈로그에는 아직 안 세운다(그림이 없으니 어느 빌드도 그릴 수 있다고 말하지 않는다).
    package static let seoulID = "aing_seoul"

    /// 부산 아잉이의 표시 이름 — 한 곳.
    package static let busanDisplayName = "부산 갈매기 아잉이"

    /// 서버 `profiles.center` 값(정확히 'busan' · 'seoul' — 서버 CHECK 가 그 둘만 허락한다).
    package static let busanCenter = "busan"
    package static let seoulCenter = "seoul"

    /// 센터 → 그 센터 아잉이 id. 모르는 값 · 빈 값은 nil(센터가 없는 사람은 지역 아잉이를 받지 않는다).
    package static func characterID(forCenter center: String?) -> String? {
        switch center {
        case busanCenter: return busanID
        case seoulCenter: return seoulID
        default: return nil
        }
    }

    /// 지역 아잉이 id → 그 센터 값. 지역 아잉이가 아니면 nil.
    package static func center(of characterID: String?) -> String? {
        switch characterID {
        case busanID: return busanCenter
        case seoulID: return seoulCenter
        default: return nil
        }
    }

    /// 잠긴 칸 · 받는 창이 부르는 센터 이름("부산" · "서울").
    package static func centerName(of characterID: String?) -> String? {
        switch characterID {
        case busanID: return "부산"
        case seoulID: return "서울"
        default: return nil
        }
    }

    package static let resourceExtension = "png"

    /// 초상(192×192). 이름 규칙은 `<id>-<표정>`.
    package static func neutralPortraitResourceName(_ id: String) -> String { "\(id)-neutral" }
    package static func negativePortraitResourceName(_ id: String) -> String { "\(id)-negative" }
    package static func portraitResourceNames(_ id: String) -> [String] { [neutralPortraitResourceName(id), negativePortraitResourceName(id)] }

    /// 맥 3D 마감 재료 — 무지개와 같이 쓰는 라벤더 밝기 맵(디퓨즈 합성 · 셰이더 인자 ckShadeMap). 부리 · 발 · 꼬리는 코드가 만든다.
    package static let shadeResourceName = "aing_rainbow-shade"
    package static var finishResourceNames: [String] { [shadeResourceName] }

    package enum Platform: Sendable { case mac, phone }

    /// 이 id 를 그리는 데 필요한 번들 그림. 지역 아잉이가 아니면 빈 배열(그릴 수 없다).
    package static func requiredResourceNames(_ id: String, for platform: Platform) -> [String] {
        guard id == busanID || id == seoulID else { return [] }
        switch platform {
        case .mac: return portraitResourceNames(id) + finishResourceNames
        case .phone: return portraitResourceNames(id)
        }
    }

    /// 이 빌드가 이 지역 아잉이를 그릴 수 있는가 — 필요한 그림이 **전부** 있을 때만(목록이 비면 거짓).
    /// 서울은 그림(초상)이 아직 없어 언제나 거짓이다 → 능력 번호 10(`ShopWire.regionProtocol`)을 어느 빌드도 말하지 않는다.
    package static func isDrawable(_ id: String, on platform: Platform, resourceExists: (String) -> Bool) -> Bool {
        let names = requiredResourceNames(id, for: platform)
        return !names.isEmpty && names.allSatisfy(resourceExists)
    }
}

// MARK: - 부산 갈매기 아잉이 — 몸 셰이더(시안 G1)

/// 갈매기 몸 셰이더. 틀(β 얼굴 지키기 · 타원체 법선 · sRGB 섞기)은 개발 아잉이 `DevAingShader` 와 같고, 무늬가 흰 갈매기 몸 +
/// 등 회색(뒤쪽) + 날개 팔(회색 · 끝 검정 · 흰 점)이다. 팔 판별은 빼빼로 리본 띠(`ribbonWrap`)와 같은 식(몸은 거의 회전체 — 팔은 옆에서 튀어나온다).
package nonisolated enum GullAingShader {
    package static let bodyTop = 0.848950
    package static let bodyHeight = 1.695736
    package static let ellipsoid = SIMD3<Double>(0.6084, 0.7191, 0.5329)
    package static let skinYRef = 0.56530
    package static let blushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
    package static let shadeMapKey = "ckShadeMap"

    // 색(sRGB 16진) — 시안 G1.
    package static let bodyColor = 0xF7F8FA       // 흰 갈매기 몸
    package static let backColor = 0x7D8895       // 등 · 날개 회색
    package static let wingTipColor = 0x1E2026    // 날개 끝 검정
    package static let rimColor = 0xB9C6D6        // 가장자리 푸른 테

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
    #pragma body
    out.ckVP = _geometry.position.xyz;
    out.ckVE = (scn_node.modelViewTransform * float4(_geometry.position.xyz, 1.0)).xyz;
    out.ckUV = _geometry.texcoords[0];
    float3 ckG = (_geometry.position.xyz - float3(0.0, 0.001, 0.0)) / (\(f5v(ellipsoid)) * \(f5v(ellipsoid)));
    out.ckVN = (scn_node.normalTransform * float4(ckG, 0.0)).xyz;
    """

    /// 흰 몸 + 윤(좁은 반짝 · 넓은 윤 · 푸른 가장자리 테).
    static let white = """
    ckBase = \(f5hex(bodyColor));
    ckShadeMix = 1.0;
    {
        float3 L = normalize(float3(-0.38, 0.55, 0.74));
        float s1 = pow(max(dot(ckVn, L), 0.0), 80.0);
        float s2 = pow(max(dot(ckVn, L), 0.0), 8.0);
        float hiF = 1.0 - 0.85 * ckFace;
        ckAdd += float3(0.95, 0.95, 1.0) * (s1 * 0.55 + s2 * 0.06) * hiF;
        ckAdd += \(f5hex(rimColor)) * pow(1.0 - ckNV, 3.0) * 0.16;
    }
    """

    /// 등(뒤쪽 위 · 팔 밖) 회색 + 날개 팔(회색 · 끝 검정 · 끝 흰 점).
    static let wings = """
    {
        float rgYq = (ckP.y + 0.06) / 0.832;
        float rgRb = 0.73 * sqrt(max(1.0 - rgYq * rgYq, 0.0));
        float rgSide = smoothstep(0.95, 1.15, abs(ckTh)) * (1.0 - smoothstep(2.00, 2.20, abs(ckTh)));
        float rgAx = ckR - rgRb;
        float rgAa = max(fwidth(rgAx), 1e-4);
        float rgArm = smoothstep(0.010 - rgAa, 0.030 + rgAa, rgAx) * rgSide;
        float rgAxA = max(fwidth(ckP.x), 1e-4);
        float rgArmTip = rgArm * smoothstep(0.80 - rgAxA, 0.80 + rgAxA, abs(ckP.x));
        float rgArmSpot = rgArmTip * (1.0 - smoothstep(0.028, 0.040, length(float2(abs(ckP.x) - 0.875, ckP.y + 0.20))));
        float back = (1.0 - smoothstep(-0.20, 0.05, ckP.z)) * smoothstep(0.14, 0.24, ckT) * (1.0 - smoothstep(0.72, 0.82, ckT));
        ckBase = mix(ckBase, \(f5hex(backColor)), back * (1.0 - rgArm));
        float3 wing = mix(\(f5hex(backColor)), \(f5hex(wingTipColor)), rgArmTip);
        wing = mix(wing, float3(1.0), rgArmSpot);
        ckBase = mix(ckBase, wing, rgArm);
        ckAdd *= 1.0 - 0.6 * rgArm;
    }
    """

    package static var pattern: String { white + wings }

    /// 몸 출력 — 개발 아잉이(`DevAingShader.bodyOutput`)와 같은 식(덮개 칠 없이). `faceOff` = 얼굴 상자를 끈다(초상 생성기의 '얼굴 없는 몸').
    package static func bodyOutput(faceOff: Bool = false) -> String {
        """
        float3 ckCol = ckBase * mix(1.0, ckShade, ckShadeMix) + ckAdd;
        bool ckInFace = \(faceOff ? "false" : "ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62");
        float ckB = ckInFace ? ckBeta : 1.0;
        float3 ckCc = clamp(ckCol, float3(0.0), float3(1.0));
        float3 ckCe = 255.0 * select(1.055 * pow(ckCc, float3(1.0 / 2.4)) - 0.055, ckCc * 12.92, ckCc <= float3(0.0031308));
        float3 ckOe = clamp((\(faceOff ? "ckSe" : "ckPe") + ckB * (ckCe - ckSe)) / 255.0, float3(0.0), float3(1.0));
        float ckSkinish = (1.0 - smoothstep(10.0, 28.0, length(ckDv))) * ckB;
        ckOe = mix(ckOe, ckCe / 255.0, ckSkinish);
        float3 ckOut = select(pow((ckOe + 0.055) / 1.055, float3(2.4)), ckOe / 12.92, ckOe <= float3(0.04045));
        _output.color = float4(ckOut, 1.0);
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
        float ckTh = atan2(ckP.x, ckP.z);
        float ckR = length(ckP.xz);
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

// MARK: - 부산 갈매기 아잉이 — 장식(부리 · 물갈퀴 발 · 꼬리깃)

/// 장식 조각 하나의 모양 · 색(순수 — 맥 마감과 초상 생성기가 같은 조각으로 노드를 만든다). 좌표는 몸 메시 노드의 물체 좌표다.
package nonisolated struct GullDecorPiece {
    package let name: String
    package let nu: Int
    package let nv: Int
    package let closedU: Bool
    package let texW: Int
    package let texH: Int
    /// (u, v) → 물체 좌표 점.
    package let pos: (Float, Float) -> SIMD3<Float>
    /// (u, v) → sRGB 16진 색.
    package let color: (Double, Double) -> Int
    /// 구운 빛의 모양(앰비언트 · 반짝 세기 · 반짝 좁기 · 감싸기).
    package let ambient: Double
    package let spec: Double
    package let gloss: Double
    package let wrap: Double
}

/// 갈매기 장식 — 시안 rgFaceBeak · rgFeet · rgTailFeathers 그대로.
package nonisolated enum GullAingDecor {
    /// 장식 루트 노드 이름(얼굴 탐색 · 몸 클릭 · 상자 계산이 뺀다 — 맥 `AingDecor.rootNames`).
    package static let decorNodeName = "check.busanDecor"

    // 색(sRGB 16진)
    package static let beakYellow = 0xF4C22F
    package static let beakBand = 0x1C1E24
    package static let beakSpot = 0xD8382C
    package static let feetColor = 0xF2B53A
    package static let tailWhite = 0xF8F9FB
    package static let tailBand = 0x1E2026

    /// 부리 뿌리 = 몸 앞면 (0, beakY) 의 겉 점(입 자리). 길이 · 굵기.
    package static let beakX: Float = 0
    package static let beakY: Float = 0.32
    package static let beakLength: Float = 0.24
    package static let beakRadius: Float = 0.072

    /// 관 끝을 둥글게 닫는 반지름(끝 end 몫).
    static func cap(_ v: Float, _ r: Float, end: Float) -> Float {
        v > 1 - end ? r * sqrt(max(0, 1 - pow((v - (1 - end)) / end, 2))) : r
    }

    /// 중심선 path · 반지름 rad 의 관 위 점(시안 `hrTube` 와 같은 틀 — 기준 축 (0, 0, 1)).
    static func tube(_ path: @escaping (Float) -> SIMD3<Float>, _ rad: @escaping (Float) -> Float) -> (Float, Float) -> SIMD3<Float> {
        { u, v in
            let e: Float = 1e-3
            let va = max(v - e, 0), vb = min(v + e, 1)
            var t = path(vb) - path(va)
            if simd_length(t) < 1e-8 { t = SIMD3(0, 1, 0) }
            t = simd_normalize(t)
            var a = simd_cross(t, SIMD3<Float>(0, 0, 1))
            if simd_length(a) < 1e-4 { a = simd_cross(t, SIMD3<Float>(1, 0, 0)) }
            a = simd_normalize(a)
            let b = simd_cross(t, a)
            let ang = 2 * Float.pi * u
            return path(v) + rad(v) * (cos(ang) * a + sin(ang) * b)
        }
    }

    /// 타원체의 자기 단위 좌표(시안 `rgBlob` 과 같은 매개 — e = 1).
    static func unitEllipsoid(_ u: Float, _ v: Float) -> SIMD3<Float> {
        let eta = -Float.pi / 2 + Float.pi * v, om = -Float.pi + 2 * Float.pi * u
        return SIMD3(cos(eta) * cos(om), sin(eta), cos(eta) * sin(om))
    }

    /// 틀: 원점 o · x 축 = xAxis · z 는 zRef 쪽(직교화) · y = z × x(시안 `rgFrame`).
    static func frame(_ o: SIMD3<Float>, x xAxis: SIMD3<Float>, zRef: SIMD3<Float>) -> (SIMD3<Float>) -> SIMD3<Float> {
        let x = simd_normalize(xAxis)
        let z = simd_normalize(zRef - x * simd_dot(zRef, x))
        let y = simd_cross(z, x)
        return { p in o + x * p.x + y * p.y + z * p.z }
    }

    /// 부리(입 자리를 덮음): 노랑 + 끝 검은 띠 + 빨간 점, 끝이 아래로 굽음. `root` = 몸 앞면 (beakX, beakY) 의 겉 점.
    package static func beak(root p: SIMD3<Float>) -> GullDecorPiece {
        let len = beakLength, r0 = beakRadius
        let path: (Float) -> SIMD3<Float> = { v in p + SIMD3(0, -0.05 * v - 0.07 * pow(v, 3), -0.035 + len * v) }
        return GullDecorPiece(name: "check.busan.beak", nu: 28, nv: 64, closedU: true, texW: 64, texH: 256,
                              pos: tube(path, { v in cap(v, r0 * (1 - 0.66 * v) + 0.004, end: 0.14) }),
                              color: { _, v in v > 0.86 ? beakSpot : (v > 0.72 ? beakBand : beakYellow) },
                              ambient: 0.66, spec: 0.35, gloss: 30, wrap: 0.45)
    }

    /// 물갈퀴 발 둘(몸 아래 앞 · 발가락 사이 짙은 선 둘).
    package static func feet() -> [GullDecorPiece] {
        [Float(1), -1].map { side in
            let f = frame(SIMD3(side * 0.22, -0.835, 0.30), x: SIMD3(side * 0.25, 0, 1), zRef: SIMD3(0, side, 0))
            let r = SIMD3<Float>(0.135, 0.105, 0.026)
            let dark = 0xBC8C2D
            return GullDecorPiece(name: "check.busan.foot" + (side > 0 ? "R" : "L"), nu: 64, nv: 40, closedU: true, texW: 256, texH: 256,
                                  pos: { u, v in f(unitEllipsoid(u, v) * r) },
                                  color: { u, v in
                                      let q = unitEllipsoid(Float(u), Float(v))
                                      return (q.x > -0.1 && abs(abs(q.y) - 0.33) < 0.06) ? dark : feetColor
                                  },
                                  ambient: 0.66, spec: 0.35, gloss: 30, wrap: 0.45)
        }
    }

    /// 꼬리깃(엉덩이 뒤 — 흰 바탕 + 검은 띠 + 흰 끝).
    package static func tail() -> GullDecorPiece {
        let f = frame(SIMD3(0, -0.42, -0.50), x: SIMD3(0, -0.30, -1), zRef: SIMD3(0, 1, 0))
        let r = SIMD3<Float>(0.20, 0.20, 0.045), c = SIMD3<Float>(0.10, 0, 0)
        return GullDecorPiece(name: "check.busan.tail", nu: 64, nv: 40, closedU: true, texW: 256, texH: 256,
                              pos: { u, v in f(c + unitEllipsoid(u, v) * r) },
                              color: { u, v in
                                  let q = unitEllipsoid(Float(u), Float(v))
                                  return (q.x > 0.25 && q.x < 0.70) ? tailBand : tailWhite
                              },
                              ambient: 0.66, spec: 0.35, gloss: 30, wrap: 0.45)
    }

    /// 장식 전부(부리 → 발 둘 → 꼬리). `beakRoot` 는 몸 앞면 (beakX, beakY) 의 겉 점.
    package static func pieces(beakRoot: SIMD3<Float>) -> [GullDecorPiece] {
        [beak(root: beakRoot)] + feet() + [tail()]
    }
}
