import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 케이크 아잉이 3D 마감 (v0.3.66 — 생일 선물 전용 딸기 · 초코)
//
// 케이크 아잉이는 아잉과 **같은 메시**(aing.scn)다. 마감은 셋이다(그림 생성기 `scripts/make-cake-aing.swift` 머리말 '앱이 할 일' 1–4):
//
//  ① 디퓨즈 합성 — 무지개와 **같다**(`isGoldSkin(원본) ? aing_rainbow-shade.png : 원본`). 같은 입력 · 같은 함수라 결과 그림도 같으므로
//     무지개의 캐시(`RainbowAingFinish.rainbowDiffuse`)를 그대로 쓴다 — 감은 눈도 무지개 순서(라벤더 원본에 먼저 감은 눈 → 같은 합성,
//     `CheckCharacter3DScene.makeClosedEyesImage` 의 무지개 갈래)를 그대로 탄다. 몸 셰이더가 '표본한 디퓨즈'에서 마스크를 읽으므로
//     깜빡임 · 졸기 · 울트라 교체로 디퓨즈가 바뀌어도 케이크 색이 따라온다.
//  ② 몸 셰이더 — 딸기 `StrawberryBody.shaderModifiers(albedoOnly: false)` · 초코 `ChocoBody.shaderModifiers` + 셰이더 인자 `ckShadeMap`
//     (= aing_rainbow-shade.png). **아래 '생성기 사본' 두 구획은 생성기의 글자 그대로다** — 주석까지 옮겼고(들여쓰기만 한 칸 안으로),
//     `V0366CakeMac3DTests` 가 두 파일의 그 구획을 주석을 걷어 맞댄다(생성기를 고치면 여기도 같이 — 안 그러면 빨갛다).
//  ③ 장식 — `StrawberryDecor.make(probe:)` · `ChocoDecor.make(probe:)` 가 만든 `check.cakeDecor` 노드 하나를 캐릭터(메시) 노드의 자식으로
//     붙인다(부유 · 살랑 · 요 회전을 그대로 따른다). 만들기는 **프로세스당 케이크마다 한 번**(디버그 빌드는 딸기 텍스처 17장 굽기가 느리다)이고
//     씬마다 `clone()` 을 붙인다(지오메트리 · 재질은 나눠 쓴다). 붙이는 순서는 금 · 무지개 후광 자리와 같다 — 프레이밍 카메라를 몸만 보고
//     세운 **뒤**(`CheckCharacter3DScene.makeAingScene`) · 감은 눈 노드 **앞**.
//
// ★ 장식은 몸이 아니다: 얼굴 재질 탐색(`ReactionEngine.locateSleepEyeTargets` — 딸기 판 텍스처는 512×256 이라 '큰 CGImage 디퓨즈'
//   조건을 만족한다)과 몸 클릭 hitTest(`ReactionEngine.isBodyAtScreenPoint`)는 `check.cakeDecor` 를 **조상으로 가진** 노드를 건너뛴다
//   (`isDecor`). 자식 이름은 두 케이크가 다르다(딸기 check.cake.* 아래 berry · calyxN · candle · wick · flame · glow, 초코 cake.*).
//   리액션 진폭(`modelExtent`)도 몸만 잰다(`bodyBoundingBox`) — 초 · 빛 번짐이 섞이면 케이크만 28% 크게 뛴다.
// ★ 프레이밍: 카메라는 몸만 보고 선다(모든 아잉 변형이 같은 구도 — 손대지 않는다). 그 구도에서 초코의 빛 번짐 위 끝이 부유 꼭대기(+0.07)에서
//   프레임 위로 나갔다(생성기 실측 −0.006). 그래서 케이크 캐릭터 노드만 `framingDrop` 만큼 내려 세운다(`apply` 가 건다 — 울트라 교체로
//   남의 씬에 서도 같이 따라간다). 값의 근거와 시험은 `framingDrop` 주석.
enum CakeAingFinish {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    // MARK: 상수(생성기 `scripts/make-cake-aing.swift` 의 같은 이름 — 시험이 두 파일을 맞댄다)

    /// 장식 루트 이름. 이 노드 **아래 전부**가 장식이다(`isDecor`).
    static let cakeDecorNodeName = "check.cakeDecor"
    // 셰이더 몸 좌표 상수(무지개 `RainbowAingArt` 와 같은 값 — 메시가 바뀌면 생성기가 멈춘다).
    static let bodyTop = 0.848950
    static let bodyHeight = 1.695736
    static let lReference = 0.8327
    // 초코 셰이더 상수 — 합성 디퓨즈 피부 텍셀 선형 휘도의 중앙값 · 원본 디퓨즈 볼터치 평균(sRGB 0–255). 생성기가 실행 때 다시 재서 맞댄다.
    static let chocoSkinYRef = 0.56530
    static let chocoBlushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
    // 장식 꼭대기(물체 좌표 y) — 불꽃 끝. 생성기가 장식 노드에서 다시 재서 맞댄다(프레이밍 근거).
    static let strawberryFlameTopY = 1.1396
    static let chocoFlameTopY = 1.1839

    // MARK: 생성기 공통 도구(생성기의 같은 이름 함수 — 전역 함수를 이 이름공간의 정적 함수로 옮겼다. 몸통은 같다)

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// RGBA8 premultipliedLast 바이트 → CGImage(기본 sRGB 태그 — 생성기 `makeImage` 와 같다).
    static func makeImage(_ px: [UInt8], _ w: Int, _ h: Int, space: CGColorSpace = sRGB) -> CGImage {
        var p = px
        let image: CGImage? = p.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        // 크기가 0 이 아닌 한 실패하지 않는다(생성기는 강제 언랩). 앱은 죽지 않게 1×1 투명으로 접는다.
        if let image { return image }
        logger.error("cake finish: CGImage 만들기 실패 \(w, privacy: .public)×\(h, privacy: .public)")
        var clear: [UInt8] = [0, 0, 0, 0]
        return clear.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }

    @inline(__always) static func srgbToLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    @inline(__always) static func linearToSrgb(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    static func linearToOklab(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let l = cbrt(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
        let m = cbrt(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
        let s = cbrt(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
        return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func oklabToLinear(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
        let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
        let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    static func srgbBytesToLinear(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> {
        SIMD3(srgbToLinear(r / 255), srgbToLinear(g / 255), srgbToLinear(b / 255))
    }

    static func labOf(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> { linearToOklab(srgbBytesToLinear(r, g, b)) }

    static func linearToBytes(_ c: SIMD3<Double>) -> (UInt8, UInt8, UInt8) {
        func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (linearToSrgb(min(max(v, 0), 1)) * 255).rounded()))) }
        return (q(c.x), q(c.y), q(c.z))
    }

    /// 셰이더 글 숫자 — 딸기(시안 B) 쪽은 소수 6자리(`f6`), 초코(시안 D) 쪽은 5자리(`f5`). 생성기와 같은 글자.
    static func f6(_ v: Double) -> String { String(format: "%.6f", v) }
    static func f6v(_ v: SIMD3<Double>) -> String { "float3(\(f6(v.x)), \(f6(v.y)), \(f6(v.z)))" }
    static func f5(_ v: Double) -> String { String(format: "%.5f", v) }
    static func f5v(_ v: SIMD3<Double>) -> String { String(format: "float3(%.5f, %.5f, %.5f)", v.x, v.y, v.z) }
    /// sRGB 16진 → 선형.
    static func linHex(_ hex: Int) -> SIMD3<Double> {
        SIMD3(srgbToLinear(Double((hex >> 16) & 255) / 255), srgbToLinear(Double((hex >> 8) & 255) / 255), srgbToLinear(Double(hex & 255) / 255))
    }
    static func f5hex(_ hex: Int) -> String { f5v(linHex(hex)) }

    /// 정수리 위 (x, z) → 몸 표면 점 · 법선(물체 좌표). 생성기와 같은 모양.
    typealias SurfaceProbe = (Float, Float) -> (SIMD3<Float>, SIMD3<Float>)

    /// 몸 메시 노드에 위(y 3)에서 아래(y −3)로 선분 hitTest — 가장 높은 맞은 점 · 그 법선(뒤집지 않은 그대로). 생성기 `meshSurfaceProbe` 와 같다.
    /// 다른 점 하나: 생성기는 못 맞으면 멈추지만(fail) 앱은 멈출 수 없다 — 정수리 높이 · 위쪽 법선으로 접고 기록을 남긴다(장식이 뜰 뿐 앱은 산다).
    static func meshSurfaceProbe(_ bodyNode: SCNNode) -> SurfaceProbe {
        { x, z in
            let hits = bodyNode.hitTestWithSegment(from: SCNVector3(x, 3, z), to: SCNVector3(x, -3, z),
                                                   options: [SCNHitTestOption.backFaceCulling.rawValue: false])
            guard let top = hits.max(by: { $0.localCoordinates.y < $1.localCoordinates.y }) else {
                logger.error("cake finish: 정수리 hitTest 실패 (\(x, privacy: .public), \(z, privacy: .public)) — 정수리 높이로 접는다")
                return (SIMD3(x, Float(bodyTop), z), SIMD3(0, 1, 0))
            }
            let p = top.localCoordinates, n = top.localNormal
            return (SIMD3(Float(p.x), Float(p.y), Float(p.z)), simd_normalize(SIMD3(Float(n.x), Float(n.y), Float(n.z))))
        }
    }

    // ── 생성기 사본 시작 ─────────────────────────────────────────────────────────────────────────────────────────────
    // 아래 두 구획(① 몸 셰이더 딸기 · 초코 / ② 장식 딸기 · 초코)은 `scripts/make-cake-aing.swift` 의 같은 구획을 **글자 그대로** 옮겼다
    // (들여쓰기 한 칸만 다르다). 고치지 마라 — 생성기를 고치고 다시 옮겨라(`V0366CakeMac3DTests.generatorRegionsAreVerbatim`).

    // MARK: - ① 몸 셰이더 — 딸기(시안 B '녹아내린 크림', lane-a 틀)

    /// 몸 전체 연분홍 딸기 크림, 정수리에 흰 크림이 녹아 흘러내린 물결 테두리(앞은 짧게 — 눈을 덮지 않는다). 흘러내림 = 둘레 각마다 캡슐 + 끝 방울
    /// (물체 좌표의 표면 거리로 잰 SDF), 캡과 매끈한 합집합(필렛). 밝기는 표본 디퓨즈의 OKLab L 차(dL)로 옮긴다(무지개와 같은 길).
    enum StrawberryBody {
        /// 아잉 디퓨즈 실측(피부 텍셀 중앙값 · 볼터치 핵심 평균, sRGB 0–1) — 볼터치 번짐 판정의 두 끝.
        static let lavenderSRGB = SIMD3<Double>(207, 186, 254) / 255
        static let blushSRGB = SIMD3<Double>(245.6, 172.3, 200.7) / 255
        static let blushLinear = SIMD3(srgbToLinear(blushSRGB.x), srgbToLinear(blushSRGB.y), srgbToLinear(blushSRGB.z))
        /// 몸 밝기 옮기기(셰이더의 `ckK` · `ckO` 줄과 같은 식): L = 무늬 L + dL, 그늘(dL < 0)은 분홍 · 보라 쪽으로 살짝 물들이고 채도는 조금 진하게.
        static let shadeTintA = 0.05, shadeTintB = -0.025, chromaSlope = 1.5, chromaFloor = 0.85, chromaCeil = 1.2
        static let creamLab = labOf(254, 251, 247)        // 생크림(살짝 따뜻한 흰색)
        static let pinkCreamLab = labOf(252, 196, 212)    // 몸: 딸기 크림 연분홍
        /// (각도°, 길이, 반지름) — 앞(0°)은 짧게, 눈 기둥(±26°) 근처는 비운다.
        static let drips: [(Double, Double, Double)] = [
            (0, 0.030, 0.036), (54, 0.175, 0.043), (-57, 0.120, 0.040), (75, 0.050, 0.034), (-73, 0.075, 0.036),
            (96, 0.300, 0.050), (-98, 0.255, 0.047), (122, 0.095, 0.039), (-126, 0.205, 0.045), (146, 0.335, 0.052),
            (-150, 0.085, 0.037), (164, 0.055, 0.034), (-167, 0.150, 0.042), (181, 0.230, 0.047),
        ]

        static func lab3(_ v: SIMD3<Double>) -> String { f6v(v) }

        static func applyShade(_ lab: SIMD3<Double>, dL: Double) -> SIMD3<Double> {
            let sh = max(-dL, 0)
            let k = min(max(1 - chromaSlope * dL, chromaFloor), chromaCeil)
            let L = min(max(lab.x + dL, 0.25), 0.995)
            return oklabToLinear(SIMD3(L, lab.y * k + shadeTintA * sh, lab.z * k + shadeTintB * sh))
        }

        static let geometryShader = """
        #pragma varyings
        float3 ckP;
        #pragma body
        out.ckP = _geometry.position.xyz;
        """

        /// 무늬: 물체 좌표(ckPos · 높이 ckT · 둘레 각 ckTh)로 `ckLab`(dL = 0 일 때의 OKLab) · `ckShadeAdd` 를 정한다.
        static let pattern: String = {
            let list = drips.map { "float4(\(f6($0.0 * .pi / 180)), \(f6($0.1)), \(f6($0.2)), 0.0)" }.joined(separator: ", ")
            return """
            float3 ckPink = \(lab3(pinkCreamLab));
            float3 ckWhite = \(lab3(creamLab));
            float ckR = max(length(ckPos.xz), 0.05);
            float ckBase = 0.142 + 0.060 * (1.0 - cos(ckTh)) * 0.5 + 0.007 * sin(ckTh * 7.0 + 0.7) + 0.004 * sin(ckTh * 13.0 + 2.1);
            float ckY = (ckT - ckBase) * \(f6(bodyHeight));
            float ckDist = ckY;
            const float4 ckDrips[\(drips.count)] = { \(list) };
            for (int i = 0; i < \(drips.count); i++) {
                float ckDa = ckTh - ckDrips[i].x;
                ckDa = ckDa - 6.283185307 * floor((ckDa + 3.14159265) / 6.283185307);
                float ckX = ckDa * ckR;
                float ckCap = length(float2(ckX, ckY - clamp(ckY, 0.0, ckDrips[i].y))) - ckDrips[i].z;
                float ckBulb = length(float2(ckX, ckY - ckDrips[i].y)) - ckDrips[i].z * 1.16;
                float ckDd = min(ckCap, ckBulb);
                float ckHh = clamp(0.5 + 0.5 * (ckDd - ckDist) / 0.03, 0.0, 1.0);
                ckDist = mix(ckDd, ckDist, ckHh) - 0.03 * ckHh * (1.0 - ckHh);
            }
            float ckW = max(fwidth(ckDist), 0.0008);
            float ckCov = 1.0 - smoothstep(-ckW, ckW, ckDist);
            ckLab = mix(ckPink, ckWhite, ckCov);
            ckShadeAdd = -0.070 * (1.0 - smoothstep(0.0, 0.030, ckDist)) * (1.0 - ckCov)
                       - 0.040 * (1.0 - smoothstep(0.0, 0.016, -ckDist)) * ckCov;
            """
        }()

        /// 몸 fragment 수정자. `albedoOnly` = 초상용 무늬 지도: 피부 판정 없이 모든 조각에 dL = 0 의 무늬 색을 쓴다(앱은 false).
        static func fragmentShader(albedoOnly: Bool) -> String {
            let skinTest = albedoOnly ? "true" : "ckHue >= 215.0 && ckHue <= 300.0 && ckSat > 0.05 && ckSat < 0.75 && ckLuma > 0.10"
            let dl = albedoOnly ? "0.0" : "0.2104542553 * ckL1 + 0.7936177850 * ckM1 - 0.0040720468 * ckS1 - \(f6(lReference))"
            return """
            #pragma varyings
            float3 ckP;
            #pragma body
            float3 ckLin = clamp(_surface.diffuse.rgb, float3(0.0), float3(1.0));
            float3 ckE = select(1.055 * pow(ckLin, float3(1.0 / 2.4)) - 0.055, ckLin * 12.92, ckLin <= float3(0.0031308));
            float ckMx = max(ckE.r, max(ckE.g, ckE.b));
            float ckMn = min(ckE.r, min(ckE.g, ckE.b));
            float ckSat = ckMx > 0.0 ? (ckMx - ckMn) / ckMx : 0.0;
            float ckHue = 0.0;
            if (ckMx > ckMn) {
                float ckSpan = ckMx - ckMn;
                if (ckMx == ckE.r) { ckHue = 60.0 * ((ckE.g - ckE.b) / ckSpan); }
                else if (ckMx == ckE.g) { ckHue = 60.0 * ((ckE.b - ckE.r) / ckSpan + 2.0); }
                else { ckHue = 60.0 * ((ckE.r - ckE.g) / ckSpan + 4.0); }
                if (ckHue < 0.0) { ckHue += 360.0; }
            }
            float ckLuma = 0.299 * ckE.r + 0.587 * ckE.g + 0.114 * ckE.b;
            // 볼터치 번짐: 피부가 아닌 텍셀 중 '라벤더 피부 ↔ 볼터치' 선분 위에 있는 것(볼 가장자리 그러데이션). 그대로 두면 새 몸 위에
            // 라벤더 테가 남는다 → 케이크 색과 볼터치 색을 그 비율(ckBa)로 섞는다. 입 · 눈 · 하이라이트는 선분에서 멀어 걸리지 않는다.
            float3 ckDv = \(f6v(blushSRGB)) - \(f6v(lavenderSRGB));
            float ckBa = clamp(dot(ckE - \(f6v(lavenderSRGB)), ckDv) / dot(ckDv, ckDv), 0.0, 1.0);
            float ckRes = length(ckE - (\(f6v(lavenderSRGB)) + ckBa * ckDv));
            // 얼굴 상자(물체 좌표 — 눈 · 볼 · 입 텍셀 실측 x ±0.52 · y 0.16–0.53 · z > 0.4 에 여유) 밖은 전부 피부로 본다: 원본 디퓨즈의 뒤통수 ·
            // 아래쪽에 피부 판정을 못 넘는 옅은 텍셀 몇 개가 있어 라벤더 위에선 안 보이지만 크림 위에선 분홍 · 보라 티끌이 된다(실측: 정수리 뒤).
            float3 ckObj = in.ckP;
            bool ckInFace = ckObj.z > 0.30 && abs(ckObj.x) < 0.58 && ckObj.y > 0.08 && ckObj.y < 0.62;
            bool ckIsSkin = (\(skinTest)) || !ckInFace;
            float ckBw = (!ckIsSkin && ckLuma > 0.45 && ckBa > 0.02) ? 1.0 - smoothstep(0.05, 0.08, ckRes) : 0.0;
            if (ckIsSkin || ckBw > 0.0) {
                float ckL1 = pow(max(0.4122214708 * ckLin.r + 0.5363325363 * ckLin.g + 0.0514459929 * ckLin.b, 0.0), 1.0 / 3.0);
                float ckM1 = pow(max(0.2119034982 * ckLin.r + 0.6806995451 * ckLin.g + 0.1073969566 * ckLin.b, 0.0), 1.0 / 3.0);
                float ckS1 = pow(max(0.0883024619 * ckLin.r + 0.2817188376 * ckLin.g + 0.6299787005 * ckLin.b, 0.0), 1.0 / 3.0);
                float ckDL = \(dl);
                float3 ckPos = in.ckP;
                float ckT = (\(f6(bodyTop)) - ckPos.y) / \(f6(bodyHeight));
                float ckTh = atan2(ckPos.x, ckPos.z);
                float3 ckLab = \(lab3(creamLab));
                float ckShadeAdd = 0.0;
            \(pattern)
                ckLab.x += ckShadeAdd;
                float ckSh = max(-ckDL, 0.0);
                float ckK = clamp(1.0 - \(f6(chromaSlope)) * ckDL, \(f6(chromaFloor)), \(f6(chromaCeil)));
                float3 ckO = float3(clamp(ckLab.x + ckDL, 0.25, 0.995), ckLab.y * ckK + \(f6(shadeTintA)) * ckSh, ckLab.z * ckK + \(f6(shadeTintB)) * ckSh);
                float ckl = ckO.x + 0.3963377774 * ckO.y + 0.2158037573 * ckO.z;
                float ckm = ckO.x - 0.1055613458 * ckO.y - 0.0638541728 * ckO.z;
                float cks = ckO.x - 0.0894841775 * ckO.y - 1.2914855480 * ckO.z;
                ckl = ckl * ckl * ckl; ckm = ckm * ckm * ckm; cks = cks * cks * cks;
                float3 ckRGB = clamp(float3(4.0767416621 * ckl - 3.3077115913 * ckm + 0.2309699292 * cks,
                                            -1.2684380046 * ckl + 2.6097574011 * ckm - 0.3413193965 * cks,
                                            -0.0041960863 * ckl - 0.7034186147 * ckm + 1.7076147010 * cks), 0.0, 1.0);
                float3 ckBlushLin = \(f6v(blushLinear));
                ckRGB = mix(ckRGB, mix(ckRGB, ckBlushLin, ckBa), ckBw);
                float3 ckKeepOrig = ckLin;
                _output.color.rgb = mix(ckRGB, ckKeepOrig, ckIsSkin ? 0.0 : 1.0 - ckBw) * _output.color.a;
            }
            """
        }

        static func shaderModifiers(albedoOnly: Bool) -> [SCNShaderModifierEntryPoint: String] {
            [.geometry: geometryShader, .fragment: fragmentShader(albedoOnly: albedoOnly)]
        }
    }

    // MARK: - ① 몸 셰이더 — 초코(시안 D, lane-b 틀)

    /// 밀크초콜릿 스펀지 몸에 흰 · 분홍 크림 띠, 정수리 가나슈(흘러내림 12줄 — 눈 자리는 짧게). 피부 = 표본 디퓨즈 P 와 그 자리 피부 S(셰이더 인자
    /// `ckShadeMap` = aing_rainbow-shade.png)로 잰 비율 β(머리말 ①)만큼 케이크로 — 출력 = P + β·(케이크 − S). 밝기 = S 의 선형 휘도 ÷ `chocoSkinYRef`.
    enum ChocoBody {
        static let shadeMapKey = "ckShadeMap"
        static let shadeGamma = 1.0
        /// (중심각°, 길이 t, 반폭 t) — 눈(정면 ±13…42°)과 볼 위는 짧게, 옆 · 뒤는 길게.
        static let drips: [(Double, Double, Double)] = [
            (0, 0.030, 0.019), (-27, 0.018, 0.020), (27, 0.022, 0.019), (-60, 0.150, 0.024), (63, 0.115, 0.023),
            (-95, 0.075, 0.022), (97, 0.170, 0.025), (-128, 0.125, 0.024), (131, 0.060, 0.021), (-160, 0.165, 0.025),
            (163, 0.095, 0.023), (180, 0.045, 0.020),
        ]
        static let ganacheEdge = 0.112

        /// 가로 띠(아래위 경계가 살짝 물결) 덮임. 이름 `name` 의 float 를 만든다.
        static func band(_ name: String, _ top: Double, _ bottom: Double, wave: Double = 0.004, freq: Double = 7, phase: Double = 0) -> String {
            """
            float \(name)A = \(f5(top)) + \(f5(wave)) * sin(ckTh * \(f5(freq)) + \(f5(phase)));
            float \(name)B = \(f5(bottom)) + \(f5(wave)) * sin(ckTh * \(f5(freq + 2)) + \(f5(phase + 1.7)));
            float \(name) = smoothstep(\(name)A - ckAAT, \(name)A + ckAAT, ckT) * (1.0 - smoothstep(\(name)B - ckAAT, \(name)B + ckAAT, ckT));
            """
        }

        /// 무늬 코드: ckBase(선형 바탕색 — 밝기 배율을 곱한다) · ckAdd(더할 광택) · ckKeep(1 이면 라벤더 그대로)를 정한다.
        static let pattern: String = {
            let edge = ganacheEdge
            var s = """
            float ckEdge = \(f5(edge)) + 0.005 * sin(ckTh * 5.0 + 0.7);
            float ckD = ckT - ckEdge;
            """
            for (i, d) in drips.enumerated() {
                s += """

                { float dth = ckTh - \(f5(d.0 * .pi / 180));
                  dth -= 6.2831853 * floor((dth + 3.14159265) / 6.2831853);
                  float sx = abs(dth) * ckR / \(f5(bodyHeight));
                  float ty = ckT - clamp(ckT, \(f5(edge)), \(f5(edge + d.1)));
                  float dd = sqrt(sx * sx + ty * ty) - \(f5(d.2));
                  float hk = clamp(0.5 + 0.5 * (dd - ckD) / 0.022, 0.0, 1.0);
                  ckD = mix(dd, ckD, hk) - 0.022 * hk * (1.0 - hk); } // drip \(i)
                """
            }
            s += """

            float ckAAD = max(fwidth(ckD), 1e-5);
            float ckGan = 1.0 - smoothstep(-ckAAD, ckAAD, ckD);
            \(band("ckCream", 0.430, 0.500, phase: 0.3))
            \(band("ckPink", 0.680, 0.740, phase: 2.1))
            float3 ckCake = \(f5hex(0x9A6444));
            ckCake = mix(ckCake, \(f5hex(0xFFF4EA)), ckCream);
            ckCake = mix(ckCake, \(f5hex(0xFFB3C6)), ckPink);
            // 가나슈: 짙은 초콜릿 + 윤기(물체 좌표에 고정된 반사 — 몸 텍스처의 빛 방향과 같다) + 가장자리 살짝 두꺼운 테.
            float3 ckH = normalize(float3(-0.38, 0.80, 0.46));
            float ckSpec = pow(max(dot(ckN, ckH), 0.0), 28.0) * 0.30 + pow(max(dot(ckN, ckH), 0.0), 5.0) * 0.02;
            float ckRim = smoothstep(-0.016, -0.002, ckD);
            float3 ckGanCol = mix(\(f5hex(0x5B3420)), \(f5hex(0x46281A)), ckRim * 0.8);
            ckBase = mix(ckCake, ckGanCol, ckGan);
            ckAdd = float3(ckSpec) * ckGan * (1.0 - ckRim * 0.5);
            """
            return s
        }()

        static let geometryShader = """
        #pragma varyings
        float3 ckVP;
        float2 ckUV;
        #pragma body
        out.ckVP = _geometry.position.xyz;
        out.ckUV = _geometry.texcoords[0];
        """

        /// 무늬는 **피부 판정 분기 밖**에서 계산한다(fwidth 는 갈라진 흐름 안에서 정의되지 않는다).
        static let fragmentShader: String = {
            let blush = String(format: "float3(%.2f, %.2f, %.2f)", chocoBlushSRGB.x, chocoBlushSRGB.y, chocoBlushSRGB.z)
            return """
            #pragma arguments
            texture2d<float> ckShadeMap;
            #pragma varyings
            float3 ckVP;
            float2 ckUV;
            #pragma body
            constexpr sampler ckSmp(coord::normalized, filter::linear, mip_filter::linear, address::repeat);
            float3 ckLin = clamp(_surface.diffuse.rgb, float3(0.0), float3(1.0));
            float3 ckSL = clamp(ckShadeMap.sample(ckSmp, in.ckUV).rgb, float3(0.0), float3(1.0));
            float3 ckPe = 255.0 * select(1.055 * pow(ckLin, float3(1.0 / 2.4)) - 0.055, ckLin * 12.92, ckLin <= float3(0.0031308));
            float3 ckSe = 255.0 * select(1.055 * pow(ckSL, float3(1.0 / 2.4)) - 0.055, ckSL * 12.92, ckSL <= float3(0.0031308));
            float3 ckDv = ckPe - ckSe;
            // 피부 비율 β(스크립트 `skinFraction` 과 같은 식): ① 볼터치 선(S→K) 위면 그 비율.
            float3 ckKs = \(blush) - ckSe;
            float ckAk = dot(ckDv, ckKs) / max(1e-6, dot(ckKs, ckKs));
            float ckRes = length(ckDv - clamp(ckAk, 0.0, 1.0) * ckKs);
            // ② 눈꺼풀 · 흰자 안티에일리어스 풀기: P = (1 − a)·S + a·F, F = S→P 방향 RGB 상자 끝 → a = 채널별 '끝까지 간 비율'의 최대.
            //    F 가 검정 쪽(루마 < 0.19…0.25)이거나 흰색 쪽(최소 채널 > 0.88…0.95)이면 β = 1 − a(테 텍셀이 몸색과 섞인다 · 눈 자체는 a = 1 → 원본),
            //    아니면(입 안 · 혀) 옛 식 1 − |P − S|/80.
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
            float ckShade = pow(clamp(dot(ckSL, float3(0.2126, 0.7152, 0.0722)) / \(f5(chocoSkinYRef)), 0.40, 1.45), \(f5(shadeGamma)));
            float3 ckP = in.ckVP;
            // aing.scn 에는 법선 소스가 없다(정점 · UV 뿐 — `_geometry.normal` 은 쓰레기). 윤기용 매끈한 법선은 몸을 감싼 타원체 기울기로 만든다.
            float3 ckN = normalize((ckP - float3(0.0, 0.001, 0.0)) / float3(0.6084, 0.7191, 0.5329));
            float ckT = (\(f5(bodyTop)) - ckP.y) / \(f5(bodyHeight));
            float ckTh = atan2(ckP.x, ckP.z);
            float ckR = length(ckP.xz);
            float ckAAT = max(fwidth(ckT), 1e-5);
            float3 ckBase = float3(1.0);
            float3 ckAdd = float3(0.0);
            float ckKeep = 0.0;
            \(pattern)
            float3 ckCol = mix(ckBase * ckShade + ckAdd, ckSL, ckKeep);
            // 얼굴 상자(물체 좌표 — 딸기 셰이더와 같은 상자) 밖은 전부 케이크: 원본 디퓨즈의 뒤통수 · 몸 아래에 피부 판정을 못 넘는 옅은 텍셀이
            // 흩어져 있어 라벤더 위에선 안 보이지만 어두운 몸 위에선 분홍 · 보라 티끌이 된다(시안 D 뒷모습 실측). 앞 몸 아래에 남는 1px 밝은 점은
            // 다른 UV 섬 텍셀을 같이 쓰는 삼각형의 밝기 점이다(무지개 머리말 ★ — 라벤더 · 무지개에도 있다).
            bool ckInFace = ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62;
            float3 ckOut = ckInFace ? ckLin + ckBeta * (ckCol - ckSL) : ckCol;
            _output.color.rgb = clamp(ckOut, float3(0.0), float3(1.0)) * _output.color.a;
            """
        }()

        static let shaderModifiers: [SCNShaderModifierEntryPoint: String] = [.geometry: geometryShader, .fragment: fragmentShader]
    }

    // MARK: - ② 장식 — 딸기(시안 B: 초 하나 + 딸기 둘, lane-a 틀)

    /// 장식 조각마다 매개 곡면 → SCNGeometry + 음영을 구운 작은 텍스처(몸 공간 고정 빛, 반 램버트 + 하이라이트). 전부 unlit.
    enum StrawberryDecor {
        struct Look {
            var ambient = 0.62
            var spec = 0.25
            var gloss = 24.0
            var wrap = 0.4
        }

        /// 몸 공간에 고정한 빛(위 · 앞 · 살짝 왼쪽) — 아잉 디퓨즈에 구운 음영과 같은 쪽.
        static let keyLight = simd_normalize(SIMD3<Double>(-0.30, 0.85, 0.45))
        static let viewLight = simd_normalize(SIMD3<Double>(0, 0.30, 1))

        static func lit(_ albedo: SIMD3<Double>, _ n: SIMD3<Double>, _ look: Look) -> SIMD3<Double> {
            let ndl = simd_dot(n, keyLight)
            let diff = min(max((ndl + look.wrap) / (1 + look.wrap), 0), 1)
            let ao = 1 - 0.22 * max(-n.y, 0)
            var c = albedo * (look.ambient + (1 - look.ambient) * diff) * ao
            let h = simd_normalize(keyLight + viewLight)
            c += SIMD3(repeating: pow(max(simd_dot(n, h), 0), look.gloss) * look.spec)
            return simd_clamp(c, .zero, SIMD3(repeating: 1))
        }

        typealias SurfaceFn = (Float, Float) -> SIMD3<Float>

        static func surfaceNormal(_ pos: SurfaceFn, _ u: Float, _ v: Float, closedU: Bool) -> SIMD3<Float> {
            func at(_ vv: Float) -> SIMD3<Float> {
                let e: Float = 1e-3
                let u0 = closedU ? u - e : max(u - e, 0), u1 = closedU ? u + e : min(u + e, 1)
                let v0 = max(vv - e, 0), v1 = min(vv + e, 1)
                return simd_cross(pos(u1, vv) - pos(u0, vv), pos(u, v1) - pos(u, v0))
            }
            var n = at(v)
            var nudge: Float = 0.004
            while simd_length(n) < 1e-9 && nudge < 0.1 {
                n = at(v < 0.5 ? v + nudge : v - nudge)
                nudge *= 2
            }
            return simd_length(n) < 1e-12 ? SIMD3(0, 1, 0) : simd_normalize(n)
        }

        /// 매개 곡면 하나를 노드로: 정점 격자(nu × nv) · 법선 · UV, 텍스처 = 텍셀마다 albedo(2×2 표본 평균)에 몸 공간 법선으로 음영을 구운 것.
        /// `upFacing`: 열린 판(꽃받침)은 법선을 위쪽으로 맞춘다(양면).
        static func pieceNode(name: String, nu: Int, nv: Int, closedU: Bool, texW: Int, texH: Int, pos: @escaping SurfaceFn,
                              albedo: (Double, Double, SIMD3<Float>) -> SIMD3<Double>, look: Look, transform: simd_float4x4,
                              upFacing: Bool = false) -> SCNNode {
            let rot = simd_float3x3(simd_make_float3(transform.columns.0), simd_make_float3(transform.columns.1), simd_make_float3(transform.columns.2))
            func normal(_ u: Float, _ v: Float) -> SIMD3<Float> {
                var n = surfaceNormal(pos, u, v, closedU: closedU)
                if upFacing && simd_dot(rot * n, SIMD3(0, 1, 0)) < 0 { n = -n }
                return n
            }
            var verts = [SCNVector3](), norms = [SCNVector3](), uvs = [CGPoint]()
            for j in 0...nv {
                for i in 0...nu {
                    let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
                    let p = pos(u, v), n = normal(u, v)
                    verts.append(SCNVector3(p.x, p.y, p.z)); norms.append(SCNVector3(n.x, n.y, n.z)); uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
                }
            }
            var idx = [UInt32]()
            let row = UInt32(nu + 1)
            for j in 0..<UInt32(nv) {
                for i in 0..<UInt32(nu) {
                    let a = j * row + i, b = a + 1, c = a + row, d = c + 1
                    idx += [a, b, c, b, d, c]
                }
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                                 SCNGeometrySource(textureCoordinates: uvs)],
                                       elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
            // 텍스처(행 0 = v 0 — SceneKit UV 원점은 그림 왼쪽 위).
            var px = [UInt8](repeating: 255, count: texW * texH * 4)
            for y in 0..<texH {
                for x in 0..<texW {
                    var acc = SIMD3<Double>(0, 0, 0)
                    for sy in 0..<2 { for sx in 0..<2 {
                        let u = (Double(x) + 0.25 + 0.5 * Double(sx)) / Double(texW), v = (Double(y) + 0.25 + 0.5 * Double(sy)) / Double(texH)
                        acc += albedo(u, v, pos(Float(u), Float(v)))
                    } }
                    let u = Float((Double(x) + 0.5) / Double(texW)), v = Float((Double(y) + 0.5) / Double(texH))
                    let nw = rot * normal(u, v)
                    let c = lit(acc / 4, simd_normalize(SIMD3<Double>(Double(nw.x), Double(nw.y), Double(nw.z))), look)
                    let (r, g, b) = linearToBytes(c)
                    let o = (y * texW + x) * 4
                    px[o] = r; px[o + 1] = g; px[o + 2] = b
                }
            }
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = makeImage(px, texW, texH)
            material.diffuse.wrapS = closedU ? .repeat : .clamp
            material.diffuse.wrapT = .clamp
            material.diffuse.mipFilter = .linear
            material.isDoubleSided = upFacing
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = name
            node.simdTransform = transform
            return node
        }

        static func lathe(_ profile: @escaping (Float) -> (r: Float, y: Float), ridge: ((Float, Float) -> Float)? = nil,
                          lean: ((Float) -> SIMD2<Float>)? = nil) -> SurfaceFn {
            { u, v in
                let (r0, y) = profile(v)
                let a = 2 * Float.pi * u
                let r = r0 * (ridge?(u, v) ?? 1)
                let shift = lean?(v) ?? .zero
                return SIMD3(r * sin(a) + shift.x, y, r * cos(a) + shift.y)
            }
        }

        static func lin(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> { srgbBytesToLinear(r, g, b) }
        static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
        static func wrapDiff(_ a: Double) -> Double { a - (a + 0.5).rounded(.down) }   // −0.5 … 0.5

        // 딸기

        struct StrawberrySpec { var radius: Float = 0.105; var height: Float = 0.235 }

        static func strawberryProfile(_ spec: StrawberrySpec) -> (Float) -> (r: Float, y: Float) {
            { s in
                let shoulder = sqrt(max(0, 1 - pow(1 - min(s / 0.2, 1), 2)))
                return (spec.radius * 1.12 * pow(max(1 - s, 0), 0.55) * shoulder, spec.height * s)
            }
        }

        /// 딸기 한 알(끝이 위) + 꽃받침 6장. `transform` = 몸(캐릭터) 공간.
        static func strawberryNode(_ spec: StrawberrySpec, transform: simd_float4x4, seed: Double) -> SCNNode {
            let group = SCNNode()
            group.name = "check.cake.strawberry"
            let profile = strawberryProfile(spec)
            let surface = lathe(profile)
            // 씨: 줄마다 둘레 길이에 맞춘 개수, 줄마다 반 칸 엇갈림. 표면 길이 단위로 잰 타원.
            let rows: [Double] = stride(from: 0.17, through: 0.86, by: 0.088).map { $0 }
            let rowCounts = rows.map { s -> Int in max(3, Int((2 * Double.pi * Double(profile(Float(s)).r) / 0.040).rounded())) }
            let berry = lin(236, 52, 76), berryTip = lin(250, 92, 104), seedColor = lin(255, 232, 150)
            func albedo(_ u: Double, _ v: Double, _ p: SIMD3<Float>) -> SIMD3<Double> {
                var c = berry + (berryTip - berry) * smooth(0.55, 1.0, v)
                let r = Double(profile(Float(v)).r)
                let dvLen = Double(spec.height) * 1.05
                var bestSeed = 1e9, bestPit = 1e9
                for (k, s) in rows.enumerated() where abs(s - v) < 0.09 {
                    let n = Double(rowCounts[k])
                    let offset = (k % 2 == 0 ? 0 : 0.5) + seed * 0.37
                    let cell = (u * n - offset).rounded()
                    for dc in -1...1 {
                        let su = (cell + Double(dc) + offset) / n
                        let dx = wrapDiff(u - su) * 2 * Double.pi * max(r, 0.01)
                        let dy = (v - s) * dvLen
                        let e = (dx / 0.0068) * (dx / 0.0068) + (dy / 0.0095) * (dy / 0.0095)
                        bestSeed = min(bestSeed, e)
                        bestPit = min(bestPit, (dx / 0.0125) * (dx / 0.0125) + (dy / 0.016) * (dy / 0.016))
                    }
                }
                if bestPit < 1 { c *= 0.80 + 0.20 * smooth(0.55, 1.0, bestPit) }
                if bestSeed < 1.15 { c = c + (seedColor - c) * (1 - smooth(0.85, 1.15, bestSeed)) }
                return c
            }
            group.addChildNode(pieceNode(name: "berry", nu: 72, nv: 48, closedU: true, texW: 512, texH: 256, pos: surface,
                                         albedo: albedo, look: Look(ambient: 0.6, spec: 0.55, gloss: 36, wrap: 0.4), transform: transform))
            // 꽃받침: 몸통 아래쪽에서 바깥으로 뻗어 살짝 처지는 잎 6장.
            let leafGreen = lin(66, 150, 72), leafTip = lin(128, 196, 92), rib = lin(150, 210, 120)
            for i in 0..<6 {
                let psi = Float(i) * 2 * Float.pi / 6 + Float(seed) * 0.6
                let dir = SIMD3<Float>(sin(psi), 0, cos(psi)), side = SIMD3<Float>(cos(psi), 0, -sin(psi))
                let length: Float = 0.085 * (i % 2 == 0 ? 1.0 : 0.86), width: Float = 0.030
                let startR = spec.radius * 0.78, startY = spec.height * 0.13
                let leaf: SurfaceFn = { u, v in
                    let hw = width * pow(max(sin(Float.pi * (0.12 + 0.88 * v)), 0), 0.9)
                    let across = (u * 2 - 1) * hw
                    let fold = 0.006 * (1 - (u * 2 - 1) * (u * 2 - 1))
                    let centre = dir * (startR + length * v) + SIMD3<Float>(0, startY - 0.034 * v * v + 0.006 * v, 0)
                    return centre + side * across + SIMD3<Float>(0, fold, 0)
                }
                func leafAlbedo(_ u: Double, _ v: Double, _ p: SIMD3<Float>) -> SIMD3<Double> {
                    var c = leafGreen + (leafTip - leafGreen) * smooth(0.0, 1.0, v)
                    let ribAmt = 1 - smooth(0.04, 0.10, abs(u * 2 - 1))
                    c = c + (rib - c) * ribAmt * 0.6
                    return c
                }
                group.addChildNode(pieceNode(name: "calyx\(i)", nu: 8, nv: 14, closedU: false, texW: 32, texH: 64, pos: leaf,
                                             albedo: leafAlbedo, look: Look(ambient: 0.62, spec: 0.12, gloss: 14, wrap: 0.5),
                                             transform: transform, upFacing: true))
            }
            return group
        }

        // 초 · 심지 · 불꽃 · 빛

        struct CandleSpec {
            var radius: Float = 0.037
            var height: Float = 0.20
            var stripe = lin(246, 112, 156)
            var base = lin(255, 251, 246)
        }

        /// 불꽃 끝의 초 공간 높이(꽂힌 깊이 0.04 를 뺀 바닥 기준) — `make` 가 몸 공간 꼭대기를 잴 때 쓴다.
        static func flameTipLocalY(_ spec: CandleSpec) -> Float { spec.height - 0.04 + 0.034 - 0.018 + 0.125 }

        static func candleNode(_ spec: CandleSpec, transform: simd_float4x4) -> SCNNode {
            let group = SCNNode()
            group.name = "check.cake.candle"
            let rc = spec.radius, hc = spec.height, e: Float = 0.009
            let side = hc - e, arc = Float.pi / 2 * e, cap = rc - e, total = side + arc + cap
            let profile: (Float) -> (r: Float, y: Float) = { s in
                let d = s * total
                if d < side { return (rc, d - 0.04) }
                if d < side + arc { let phi = (d - side) / e; return (rc - e + e * cos(phi), side - 0.04 + e * sin(phi)) }
                return (max(0, (rc - e) * (1 - (d - side - arc) / cap)), hc - 0.04)
            }
            // 꽂힌 깊이 0.04 — 모양은 y = −0.04 에서 시작한다(몸 표면 아래로 묻힌다).
            let stripe = spec.stripe, base = spec.base
            func albedo(_ u: Double, _ v: Double, _ p: SIMD3<Float>) -> SIMD3<Double> {
                let y = Double(p.y) + 0.04
                let onSide = Double(simd_length(SIMD2(p.x, p.z))) > Double(rc) - 0.0015 && y < Double(hc) - 0.004
                if !onSide { return base }
                let phase = u * 2 + y / 0.085
                let f = phase - phase.rounded(.down)
                let edge = 0.012
                let amt = smooth(-edge, edge, f - 0.08) * (1 - smooth(-edge, edge, f - 0.5))
                return base + (stripe - base) * amt
            }
            group.addChildNode(pieceNode(name: "candle", nu: 48, nv: 40, closedU: true, texW: 256, texH: 256, pos: lathe(profile),
                                         albedo: albedo, look: Look(ambient: 0.62, spec: 0.35, gloss: 30, wrap: 0.45), transform: transform))
            // 심지
            let wickTop = hc - 0.04 + 0.034
            let wick = lathe({ s in (0.0058 * (1 - 0.35 * s * s), hc - 0.045 + s * 0.079) })
            group.addChildNode(pieceNode(name: "wick", nu: 12, nv: 6, closedU: true, texW: 16, texH: 16, pos: wick,
                                         albedo: { _, v, _ in lin(70, 52, 46) + (lin(150, 90, 60) - lin(70, 52, 46)) * smooth(0.7, 1.0, v) },
                                         look: Look(ambient: 0.75, spec: 0.0, gloss: 8, wrap: 0.5), transform: transform))
            // 불꽃: 아래 둥글고 위가 뾰족한 물방울. 셰이더가 시선 · 법선 각으로 가운데 흰빛 → 가장자리 주황.
            let flameH: Float = 0.125, flameR: Float = 0.031
            let flameBase = wickTop - 0.018
            let flameProfile: (Float) -> (r: Float, y: Float) = { s in
                (flameR * 1.72 * sqrt(max(s, 0)) * pow(max(1 - s, 0), 1.05), flameBase + flameH * s)
            }
            var fVerts = [SCNVector3](), fNorms = [SCNVector3]()
            let fnu = 32, fnv = 24
            let flameSurface = lathe(flameProfile, lean: { s in SIMD2(0, 0) + SIMD2(0.004 * s * s, 0) })
            for j in 0...fnv { for i in 0...fnu {
                let u = Float(i) / Float(fnu), v = Float(j) / Float(fnv)
                let p = flameSurface(u, v), n = surfaceNormal(flameSurface, u, v, closedU: true)
                fVerts.append(SCNVector3(p.x, p.y, p.z)); fNorms.append(SCNVector3(n.x, n.y, n.z))
            } }
            var fIdx = [UInt32]()
            let fRow = UInt32(fnu + 1)
            for j in 0..<UInt32(fnv) { for i in 0..<UInt32(fnu) {
                let a = j * fRow + i, b = a + 1, c = a + fRow, d = c + 1
                fIdx += [a, b, c, b, d, c]
            } }
            let flameGeo = SCNGeometry(sources: [SCNGeometrySource(vertices: fVerts), SCNGeometrySource(normals: fNorms)],
                                       elements: [SCNGeometryElement(indices: fIdx, primitiveType: .triangles)])
            let flameMat = SCNMaterial()
            flameMat.lightingModel = .constant
            flameMat.shaderModifiers = [
                .geometry: "#pragma varyings\nfloat ckH;\n#pragma body\nout.ckH = _geometry.position.y;\n",
                .fragment: """
                #pragma varyings
                float ckH;
                #pragma body
                float ckF = clamp(dot(normalize(_surface.normal), normalize(_surface.view)), 0.0, 1.0);
                float ckS = clamp((in.ckH - \(f6(Double(flameBase)))) / \(f6(Double(flameH))), 0.0, 1.0);
                float3 ckEdge = float3(1.0, 0.36, 0.06);
                float3 ckMid = float3(1.0, 0.70, 0.16);
                float3 ckCore = float3(1.0, 0.96, 0.74);
                float3 ckC = mix(ckEdge, ckMid, smoothstep(0.05, 0.50, ckF));
                ckC = mix(ckC, ckCore, smoothstep(0.50, 0.90, ckF) * (1.0 - smoothstep(0.30, 0.85, ckS)));
                _output.color = float4(ckC, 1.0);
                """,
            ]
            flameGeo.materials = [flameMat]
            let flame = SCNNode(geometry: flameGeo)
            flame.name = "flame"
            flame.simdTransform = transform
            group.addChildNode(flame)
            // 빛 번짐: 불꽃 가운데의 빌보드 판(알파 · 깊이 안 씀).
            let glowSize = 64
            var gpx = [UInt8](repeating: 0, count: glowSize * glowSize * 4)
            for y in 0..<glowSize { for x in 0..<glowSize {
                let dx = (Double(x) + 0.5) / Double(glowSize) * 2 - 1, dy = (Double(y) + 0.5) / Double(glowSize) * 2 - 1
                let r2 = dx * dx + dy * dy
                let a = 0.42 * exp(-r2 * 5.0) * (1 - smooth(0.7, 1.0, sqrt(r2)))
                let o = (y * glowSize + x) * 4
                gpx[o] = UInt8((255 * a).rounded()); gpx[o + 1] = UInt8((214 * a).rounded()); gpx[o + 2] = UInt8((120 * a).rounded())
                gpx[o + 3] = UInt8((255 * a).rounded())
            } }
            let plane = SCNPlane(width: 0.26, height: 0.26)
            let glowMat = SCNMaterial()
            glowMat.lightingModel = .constant
            glowMat.diffuse.contents = makeImage(gpx, glowSize, glowSize)
            glowMat.blendMode = .alpha
            glowMat.writesToDepthBuffer = false
            glowMat.isDoubleSided = true
            plane.materials = [glowMat]
            let glow = SCNNode(geometry: plane)
            glow.name = "glow"
            glow.renderingOrder = 10
            let flameCenter = transform * SIMD4<Float>(0, flameBase + flameH * 0.42, 0, 1)
            glow.simdPosition = SIMD3(flameCenter.x, flameCenter.y, flameCenter.z)
            glow.constraints = [SCNBillboardConstraint()]
            group.addChildNode(glow)
            return group
        }

        // 자리 잡기

        /// 표면 점에 세우는 변환: 위(+y)를 (수직 ↔ 법선) 사이 `follow` 비율로 기울이고, `extraTilt`(라디안, 바깥쪽)만큼 더 눕히고, y 로 `spin` 돌리고,
        /// 법선 방향으로 `sink` 만큼 묻는다. 법선은 위를 보게 뒤집는다(시안 crownPoint).
        static func placement(_ probe: SurfaceProbe, x: Float, z: Float, follow: Float, sink: Float, spin: Float = 0, extraTilt: Float = 0,
                              scale: Float = 1) -> simd_float4x4 {
            var (p, n) = probe(x, z)
            if n.y < 0 { n = -n }
            var up = simd_normalize(simd_mix(SIMD3<Float>(0, 1, 0), n, SIMD3(repeating: follow)))
            if extraTilt != 0 {
                let outward = simd_normalize(SIMD3<Float>(x, 0, z) + SIMD3(1e-4, 0, 0))
                up = simd_normalize(up + outward * tan(extraTilt))
            }
            let q = simd_quatf(from: SIMD3(0, 1, 0), to: up) * simd_quatf(angle: spin, axis: SIMD3(0, 1, 0))
            var m = simd_float4x4(q)
            m.columns.0 *= scale; m.columns.1 *= scale; m.columns.2 *= scale
            let at = p - n * sink
            m.columns.3 = SIMD4(at.x, at.y, at.z, 1)
            return m
        }

        static let candle = CandleSpec()
        static let candleSeat: (x: Float, z: Float, follow: Float, sink: Float) = (0.0, -0.10, 0.1, 0.0)

        /// 시안 B 장식: 뒤쪽 가운데 초 하나 + 앞 양옆 딸기 둘(끝이 위). 반환 노드 이름 = `cakeDecorNodeName`.
        static func make(probe: SurfaceProbe) -> SCNNode {
            let d = SCNNode(); d.name = cakeDecorNodeName
            d.addChildNode(candleNode(candle, transform: placement(probe, x: candleSeat.x, z: candleSeat.z, follow: candleSeat.follow, sink: candleSeat.sink)))
            d.addChildNode(strawberryNode(StrawberrySpec(radius: 0.118, height: 0.262),
                                          transform: placement(probe, x: -0.21, z: 0.06, follow: 0.6, sink: 0.04, spin: 0.9, extraTilt: 0.14), seed: 0.7))
            d.addChildNode(strawberryNode(StrawberrySpec(radius: 0.118, height: 0.262),
                                          transform: placement(probe, x: 0.21, z: 0.08, follow: 0.6, sink: 0.04, spin: -0.5, extraTilt: 0.14), seed: 1.9))
            return d
        }

        /// 불꽃 끝의 몸 공간 y(앱 프레이밍 상수 `strawberryFlameTopY` 의 근거).
        static func flameTopY(probe: SurfaceProbe) -> Double {
            let m = placement(probe, x: candleSeat.x, z: candleSeat.z, follow: candleSeat.follow, sink: candleSeat.sink)
            return Double((m * SIMD4<Float>(0, flameTipLocalY(candle), 0, 1)).y)
        }
    }

    // MARK: - ② 장식 — 초코(시안 D: 크림 장미 위 딸기 하나 + 줄무늬 초 하나, lane-b 틀)

    /// 정점을 캐릭터 물체 좌표로 미리 옮긴 SCNGeometry 몇 개(같은 재질끼리 합침)를 단위 변환 노드 하나 아래 둔다. 음영은 재질 셰이더가
    /// **캐릭터 좌표에 고정된 가상 빛**(왼쪽 위 앞)으로 계산한다. 촛불만 화면 공간 발광 + 빌보드 빛무리 판 하나.
    enum ChocoDecor {
        struct DMesh {
            var p: [SIMD3<Float>] = []
            var n: [SIMD3<Float>] = []
            var uv: [SIMD2<Float>] = []
            var idx: [UInt32] = []

            mutating func append(_ o: DMesh) {
                let base = UInt32(p.count)
                p += o.p; n += o.n; uv += o.uv; idx += o.idx.map { $0 + base }
            }

            func transformed(_ m: simd_float4x4) -> DMesh {
                let m3 = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z), SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                       SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
                let nm = m3.inverse.transpose
                var o = self
                o.p = p.map { q in let v = m * SIMD4(q, 1); return SIMD3(v.x, v.y, v.z) }
                o.n = n.map { simd_normalize(nm * $0) }
                return o
            }
        }

        /// 회전체: profile(s) → (반지름, 높이), s 는 0(아래) → 1(위). radial(θ, s) 는 반지름 배수. uv = (θ/2π, s).
        static func lathe(rings: Int, segments: Int, profile: (Float) -> (Float, Float), radial: ((Float, Float) -> Float)? = nil) -> DMesh {
            var m = DMesh()
            let cols = segments + 1
            for i in 0..<rings {
                let s = Float(i) / Float(rings - 1)
                let (r, y) = profile(s)
                for j in 0...segments {
                    let u = Float(j) / Float(segments), th = u * 2 * .pi
                    let rr = max(r * (radial?(th, s) ?? 1), 1e-5)
                    m.p.append(SIMD3(rr * sin(th), y, rr * cos(th)))
                    m.uv.append(SIMD2(u, s))
                }
            }
            for i in 0..<rings {
                for j in 0...segments {
                    let jj = j % segments
                    let jp = (jj + 1) % segments, jm = (jj - 1 + segments) % segments
                    let dth = m.p[i * cols + jp] - m.p[i * cols + jm]
                    let ds = m.p[min(i + 1, rings - 1) * cols + jj] - m.p[max(i - 1, 0) * cols + jj]
                    var nn = simd_cross(dth, ds)
                    if simd_length(nn) < 1e-12 { nn = SIMD3(0, i == 0 ? -1 : 1, 0) }
                    m.n.append(simd_normalize(nn))
                }
            }
            for i in 0..<(rings - 1) {
                for j in 0..<segments {
                    let a = UInt32(i * cols + j), b = a + 1, c = a + UInt32(cols), d = c + 1
                    m.idx += [a, b, d, a, d, c]
                }
            }
            return m
        }

        /// 점 사이 Catmull-Rom 보간(s 오름차순 점들).
        static func curve(_ pts: [(Float, Float)]) -> (Float) -> Float {
            return { s in
                guard let k = pts.indices.dropLast().first(where: { s <= pts[$0 + 1].0 }) else { return pts.last!.1 }
                let p0 = pts[max(k - 1, 0)].1, p1 = pts[k].1, p2 = pts[k + 1].1, p3 = pts[min(k + 2, pts.count - 1)].1
                let t = (s - pts[k].0) / max(pts[k + 1].0 - pts[k].0, 1e-6)
                let t2 = t * t, t3 = t2 * t
                return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            }
        }

        static func translation(_ v: SIMD3<Float>) -> simd_float4x4 {
            var m = matrix_identity_float4x4; m.columns.3 = SIMD4(v, 1); return m
        }
        static func scaling(_ v: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(v, 1)) }
        static func rotation(_ angle: Float, _ axis: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis))) }
        /// +y 를 `axis` 로 돌리는 회전.
        static func aligning(_ axis: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(axis))) }

        /// 장식 재질 셰이더: 캐릭터 좌표 고정 가상 빛(왼쪽 위 앞) + 둘레 감싸기 + 반사. `code` 가 base(선형) · specK · emit 를 정한다.
        static func decorMaterial(_ code: String, amb: Double = 0.58, dif: Double = 0.52, wrap: Double = 0.35, spec: Double = 0.25, shin: Double = 24,
                                  name: String) -> SCNMaterial {
            let geometry = """
            #pragma varyings
            float3 ckP;
            float3 ckN;
            float2 ckUV;
            #pragma body
            out.ckP = _geometry.position.xyz;
            out.ckN = _geometry.normal;
            out.ckUV = _geometry.texcoords[0];
            """
            let fragment = """
            #pragma varyings
            float3 ckP;
            float3 ckN;
            float2 ckUV;
            #pragma body
            float3 n = normalize(in.ckN);
            float2 uv = in.ckUV;
            float3 p = in.ckP;
            float3 base = float3(1.0);
            float specK = \(f5(spec));
            float emit = 0.0;
            \(code)
            float3 Ld = normalize(float3(-0.35, 0.80, 0.50));
            float ndl = clamp((dot(n, Ld) + \(f5(wrap))) / \(f5(1 + wrap)), 0.0, 1.0);
            float3 Hh = normalize(Ld + normalize(float3(0.0, 0.35, 1.0)));
            float sp = pow(max(dot(n, Hh), 0.0), \(f5(shin))) * specK;
            float3 col = base * (\(f5(amb)) + \(f5(dif)) * ndl) + float3(sp);
            col = mix(col, base, emit);
            _output.color = float4(clamp(col, float3(0.0), float3(1.0)), 1.0);
            """
            let m = SCNMaterial()
            m.name = name
            m.lightingModel = .constant
            m.diffuse.contents = NSColor.white
            m.isDoubleSided = true
            m.shaderModifiers = [.geometry: geometry, .fragment: fragment]
            return m
        }

        enum Mat {
            static func strawberry() -> SCNMaterial {
                decorMaterial("""
                float3 red = \(f5hex(0xE8293B));
                base = mix(red * 0.86, red, smoothstep(0.0, 0.30, uv.y));
                base = mix(base, \(f5hex(0xFF8A86)), smoothstep(0.80, 0.97, uv.y));
                // 씨: 엇갈린 줄(16칸 × 8줄) — 노란 씨 + 둘레 움푹한 어두운 자리.
                float vS = (uv.y - 0.08) / 0.80;
                float inRows = step(0.0, vS) * step(vS, 1.0);
                float rowF = vS * 8.0;
                float row = floor(rowF);
                float fu = uv.x * 16.0 + 0.5 * fmod(row, 2.0);
                float2 cell = float2(fract(fu) - 0.5, fract(rowF) - 0.5);
                float d = length(cell * float2(0.039 / 0.0046, 0.024 / 0.0068));
                float aa = max(fwidth(d), 1e-4);
                float seed = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, d)) * inRows;
                float pit = (1.0 - smoothstep(1.6 - aa, 1.9 + aa, d)) * inRows;
                base = mix(base, base * 0.70, pit * 0.55);
                base = mix(base, \(f5hex(0xFFE07A)), seed);
                specK = 0.42 * (1.0 - seed);
                """, amb: 0.55, dif: 0.55, spec: 0.42, shin: 46, name: "cake.strawberry")
            }
            static func leaf() -> SCNMaterial {
                decorMaterial("base = mix(\(f5hex(0x2E9E48)), \(f5hex(0x7BD65A)), clamp(n.y * 0.5 + 0.5, 0.0, 1.0));",
                              amb: 0.55, dif: 0.5, spec: 0.15, shin: 14, name: "cake.leaf")
            }
            static func cream(_ hex: Int = 0xFFF9F2) -> SCNMaterial {
                decorMaterial("base = \(f5hex(hex));", amb: 0.70, dif: 0.36, wrap: 0.5, spec: 0.10, shin: 10, name: "cake.cream")
            }
            static func candle(_ c1: Int, _ c2: Int, turns: Double = 2.4) -> SCNMaterial {
                decorMaterial("""
                float st = fract(uv.x * 2.0 + uv.y * \(f5(turns)));
                float sd = abs(st - 0.5) - 0.25;
                float aa = max(fwidth(st), 1e-4);
                float k = smoothstep(-aa, aa, sd);
                base = mix(\(f5hex(c1)), \(f5hex(c2)), k);
                base = mix(base, \(f5hex(c1)), step(1.001, uv.y));
                """, amb: 0.62, dif: 0.45, spec: 0.28, shin: 30, name: "cake.candle")
            }
            static func wick() -> SCNMaterial {
                decorMaterial("base = \(f5hex(0x3A2A22));", amb: 0.8, dif: 0.3, spec: 0.0, shin: 8, name: "cake.wick")
            }
            static func flame() -> SCNMaterial {
                decorMaterial("""
                float f = clamp(abs(normalize(_surface.normal).z), 0.0, 1.0);
                float3 c = mix(\(f5hex(0xFF9A2E)), \(f5hex(0xFFD54A)), smoothstep(0.05, 0.55, f));
                c = mix(c, \(f5hex(0xFFF8D8)), smoothstep(0.60, 0.95, f) * (1.0 - smoothstep(0.45, 0.85, uv.y)));
                base = c;
                emit = 1.0;
                """, spec: 0.0, name: "cake.flame")
            }
        }

        /// 빛무리(따뜻한 노랑, 가운데 알파 0.40 → 0, 가우스 × (1 − r²)² — 판 가장자리 훨씬 안에서 0 이 된다).
        static let glowImage: CGImage = {
            let s = 128
            var px = [UInt8](repeating: 0, count: s * s * 4)
            for y in 0..<s { for x in 0..<s {
                let dx = (Double(x) + 0.5) / Double(s) * 2 - 1, dy = (Double(y) + 0.5) / Double(s) * 2 - 1
                let r2 = dx * dx + dy * dy
                let a = 0.40 * exp(-r2 / 0.09) * max(0, 1 - r2) * max(0, 1 - r2)
                let o = (y * s + x) * 4
                px[o] = UInt8((255 * a).rounded()); px[o + 1] = UInt8((222 * a).rounded()); px[o + 2] = UInt8((130 * a).rounded()); px[o + 3] = UInt8((255 * a).rounded())
            } }
            return makeImage(px, s, s)
        }()

        /// 장식 한 덩어리(같은 재질끼리 합친 메시).
        final class Builder {
            var parts: [(String, DMesh, SCNMaterial)] = []
            var glows: [SIMD3<Float>] = []
            var flameTips: [SIMD3<Float>] = []

            func add(_ key: String, _ mesh: DMesh, _ material: @autoclosure () -> SCNMaterial) {
                if let i = parts.firstIndex(where: { $0.0 == key }) { parts[i].1.append(mesh) } else { parts.append((key, mesh, material())) }
            }

            /// 짜 올린 크림(별깍지 로제트): 바닥 중심 `base`, 축 `axis`. 반환: 꼭대기 근처(딸기를 얹을 자리).
            @discardableResult
            func rosette(at base: SIMD3<Float>, axis: SIMD3<Float>, radius: Float = 0.17, height: Float = 0.15, color: Int = 0xFFF9F2, key: String = "cream") -> SIMD3<Float> {
                let m = lathe(rings: 44, segments: 128, profile: { s in
                    let r = radius * pow(max(1 - s, 0), 0.62) * (0.80 + 0.20 * min(s / 0.18, 1))
                    return (r, height * s)
                }, radial: { th, s in 1 + 0.15 * cos(8 * th + 7.5 * s) * (1 - 0.7 * s) })
                add(key, m.transformed(translation(base) * aligning(axis)), Mat.cream(color))
                return base + simd_normalize(axis) * height * 0.78
            }

            /// 딸기(끝이 아래, 꼭지 잎이 위). `tip` 에 끝이 닿는다.
            func strawberry(tip: SIMD3<Float>, axis: SIMD3<Float>, height: Float = 0.29, radius: Float = 0.118, spin: Float = 0.3) {
                let shape = curve([(0, 0), (0.06, 0.30), (0.18, 0.62), (0.35, 0.86), (0.55, 0.99), (0.72, 1.0), (0.85, 0.90), (0.94, 0.66), (0.985, 0.32), (1.0, 0.0)])
                let body = lathe(rings: 72, segments: 96, profile: { s in (radius * max(shape(s), 0), height * s - (s > 0.9 ? (s - 0.9) * height * 0.25 : 0)) },
                                 radial: { th, s in 1 + 0.035 * cos(3 * th + 0.4) * sin(.pi * s) })
                let frame = translation(tip) * aligning(axis) * rotation(spin, SIMD3(0, 1, 0))
                add("strawberry", body.transformed(frame), Mat.strawberry())
                // 꼭지 잎 6장 + 줄기.
                let topY = height * 0.975 + 0.004
                for k in 0..<6 {
                    let ang = Float(k) / 6 * 2 * .pi + (k % 2 == 0 ? 0 : 0.15)
                    let len: Float = k % 2 == 0 ? 0.072 : 0.060
                    let leaf = lathe(rings: 14, segments: 20, profile: { s in (sin(.pi * s), -cos(.pi * s)) })
                    // 꼭지 잎은 어깨를 따라 살짝만 처진다(0.22 rad) — 더 처지면 딸기 어깨 속에 묻힌다(실측).
                    let local = rotation(ang, SIMD3(0, 1, 0)) * rotation(0.22, SIMD3(1, 0, 0)) * translation(SIMD3(0, 0, len * 0.80))
                        * scaling(SIMD3(0.030, 0.0080, len))
                    add("leaf", leaf.transformed(frame * translation(SIMD3(0, topY, 0)) * local), Mat.leaf())
                }
                let stem = lathe(rings: 8, segments: 16, profile: { s in (0.009 - 0.003 * s, 0.045 * s) })
                add("leaf", stem.transformed(frame * translation(SIMD3(0, topY - 0.006, 0)) * rotation(0.35, SIMD3(0, 0, 1))), Mat.leaf())
            }

            /// 생일 초(나선 줄무늬) + 심지 + 불꽃 + 빛무리. `base` 는 몸 속으로 묻힐 바닥.
            func candle(at base: SIMD3<Float>, axis: SIMD3<Float>, height: Float, radius: Float = 0.030, colors: (Int, Int), key: String) {
                let frame = translation(base) * aligning(axis)
                let body = lathe(rings: 40, segments: 48, profile: { s in
                    if s < 0.03 { return (radius * s / 0.03, 0) }
                    if s < 0.94 { return (radius, height * (s - 0.03) / 0.91) }
                    let q = (s - 0.94) / 0.06
                    return (radius * (1 - q * q * 0.96), height + 0.008 * sin(q * .pi / 2))
                })
                // uv.y 를 높이 비율로(위 뚜껑은 1 넘게 — 셰이더가 단색으로 칠한다).
                var b = body
                b.uv = b.p.map { SIMD2(0, $0.y / height) }
                for i in b.uv.indices { b.uv[i].x = body.uv[i].x; if body.uv[i].y >= 0.94 { b.uv[i].y = 1.002 } }
                add(key, b.transformed(frame), Mat.candle(colors.0, colors.1))
                let wick = lathe(rings: 6, segments: 12, profile: { s in (0.0048, height - 0.004 + 0.040 * s) })
                add("wick", wick.transformed(frame), Mat.wick())
                let fh: Float = 0.105, fr: Float = 0.029
                let flame = lathe(rings: 40, segments: 40, profile: { s in (fr * pow(sin(.pi * pow(s, 0.62)), 0.85), fh * s) })
                let flameBase = height + 0.016
                add("flame", flame.transformed(frame * translation(SIMD3(0, flameBase, 0))), Mat.flame())
                let c = frame * SIMD4(0, flameBase + fh * 0.38, 0, 1)
                glows.append(SIMD3(c.x, c.y, c.z))
                let tip = frame * SIMD4(0, flameBase + fh, 0, 1)
                flameTips.append(SIMD3(tip.x, tip.y, tip.z))
            }

            func node() -> SCNNode {
                let root = SCNNode()
                root.name = cakeDecorNodeName
                for (key, m, material) in parts {
                    let vs = SCNGeometrySource(vertices: m.p.map { SCNVector3($0.x, $0.y, $0.z) })
                    let ns = SCNGeometrySource(normals: m.n.map { SCNVector3($0.x, $0.y, $0.z) })
                    let ts = SCNGeometrySource(textureCoordinates: m.uv.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                    let el = SCNGeometryElement(indices: m.idx, primitiveType: .triangles)
                    let g = SCNGeometry(sources: [vs, ns, ts], elements: [el])
                    g.materials = [material]
                    let child = SCNNode(geometry: g)
                    child.name = "cake.\(key)"
                    root.addChildNode(child)
                }
                for (i, c) in glows.enumerated() {
                    let plane = SCNPlane(width: 0.30, height: 0.30)
                    let m = SCNMaterial()
                    m.lightingModel = .constant
                    m.diffuse.contents = ChocoDecor.glowImage
                    m.blendMode = .alpha
                    m.writesToDepthBuffer = false
                    m.isDoubleSided = true
                    plane.materials = [m]
                    let g = SCNNode(geometry: plane)
                    g.name = "cake.glow\(i)"
                    g.simdPosition = c
                    g.constraints = [SCNBillboardConstraint()]
                    g.renderingOrder = 50
                    root.addChildNode(g)
                }
                return root
            }
        }

        /// 머리 위 자리: 표면 점에서 `sink` 만큼 묻고, 축은 위와 법선 사이(`tilt`).
        static func seat(_ probe: SurfaceProbe, _ x: Float, _ z: Float, sink: Float, tilt: Float) -> (SIMD3<Float>, SIMD3<Float>) {
            let (p, n) = probe(x, z)
            let axis = simd_normalize(simd_mix(SIMD3<Float>(0, 1, 0), n, SIMD3(repeating: tilt)))
            return (p - axis * sink, axis)
        }

        static func build(probe: SurfaceProbe) -> Builder {
            let b = Builder()
            let (rb, ra) = seat(probe, 0.07, 0.08, sink: 0.03, tilt: 0.6)
            let top = b.rosette(at: rb, axis: ra)
            b.strawberry(tip: top - ra * 0.02, axis: simd_normalize(ra + SIMD3(0.10, 0, 0.06)), spin: 0.4)
            let (cb, ca) = seat(probe, -0.20, -0.10, sink: 0.05, tilt: 0.25)
            b.candle(at: cb, axis: ca, height: 0.31, colors: (0xFFFFFF, 0xFF7FA6), key: "candle")
            return b
        }

        /// 시안 D 장식: 앞 오른쪽 크림 장미 위 딸기 하나 + 뒤 왼쪽 흰 · 분홍 줄무늬 초 하나. 반환 노드 이름 = `cakeDecorNodeName`.
        static func make(probe: SurfaceProbe) -> SCNNode { build(probe: probe).node() }

        /// 불꽃 끝의 몸 공간 y(앱 프레이밍 상수 `chocoFlameTopY` 의 근거).
        static func flameTopY(probe: SurfaceProbe) -> Double { Double(build(probe: probe).flameTips.map(\.y).max() ?? 0) }
    }

    // ── 생성기 사본 끝 ───────────────────────────────────────────────────────────────────────────────────────────────

    // MARK: - 케이크 종류

    enum Kind: String, CaseIterable, Sendable {
        case strawberry, choco

        var characterID: String {
            switch self {
            case .strawberry: return CharacterCatalog.cakeStrawberryAingID
            case .choco: return CharacterCatalog.cakeChocoAingID
            }
        }

        init?(finish: CharacterManifest.Finish) {
            switch finish {
            case .cakeStrawberry: self = .strawberry
            case .cakeChoco: self = .choco
            case .standard, .gold, .rainbow: return nil
            }
        }

        init?(characterID: String?) {
            self.init(finish: CharacterManifest.Finish(characterID: characterID))
        }

        /// 몸 재질에 거는 셰이더 수정자(생성기 사본 그대로 — 프로세스당 한 번 만든 글).
        var bodyShaderModifiers: [SCNShaderModifierEntryPoint: String] {
            switch self {
            case .strawberry: return CakeAingFinish.strawberryBodyModifiers
            case .choco: return ChocoBody.shaderModifiers
            }
        }

        /// 불꽃 끝(물체 좌표 y — 생성기 상수).
        var flameTopY: Double {
            switch self {
            case .strawberry: return strawberryFlameTopY
            case .choco: return chocoFlameTopY
            }
        }

        /// 장식 한 벌을 새로 만든다(생성기 `StrawberryDecor.make` · `ChocoDecor.make`). 앱은 `decorNode(_:)` 의 사본을 쓴다.
        func makeDecor(probe: @escaping SurfaceProbe) -> SCNNode {
            switch self {
            case .strawberry: return StrawberryDecor.make(probe: probe)
            case .choco: return ChocoDecor.make(probe: probe)
            }
        }

        /// "이 캐릭터 노드는 이 케이크다"의 표식 노드 이름(지오메트리 없는 빈 노드 — 몸 크기 계산에 안 낀다). 엔진의 `currentCharacterID` 가 읽는다.
        var markerName: String { "check.cakeAing.\(rawValue)" }
    }

    /// 딸기 몸 셰이더(앱 = `albedoOnly: false`). 글을 한 번만 만든다.
    static let strawberryBodyModifiers = StrawberryBody.shaderModifiers(albedoOnly: false)

    // MARK: - 번들 자원 · 그릴 수 있다

    /// 초상 리소스 이름(`<id>-neutral` · `<id>-negative` — 금 · 무지개 규약).
    static func portraitResourceName(_ kind: Kind, mood: CheckMascotAssets.Mood) -> String {
        "\(kind.characterID)-\(mood == .neutral ? "neutral" : "negative")"
    }

    static func resourceURL(_ name: String) -> URL? {
        CheckResources.bundle.url(forResource: name, withExtension: GoldAingArt.resourceExtension)
    }

    static func portraitURL(_ kind: Kind, mood: CheckMascotAssets.Mood) -> URL? {
        resourceURL(portraitResourceName(kind, mood: mood))
    }

    /// 이 케이크를 그리는 데 필요한 번들 그림 — 초상 두 장 + **무지개와 같이 쓰는** 밝기 맵(`aing_rainbow-shade.png` — 디퓨즈 합성 · 초코 셰이더 인자).
    /// 장식 텍스처는 코드가 만들므로 파일이 없다(생성기 머리말 ★).
    static func requiredResourceNames(_ kind: Kind) -> [String] {
        [portraitResourceName(kind, mood: .neutral), portraitResourceName(kind, mood: .negative), RainbowAingArt.shadeResourceName]
    }

    /// 이 빌드가 이 케이크를 그릴 수 있는가 — 위 세 장이 **실재**한다. 상점 능력 번호 4(`ShopWire.protocolVersion`)의 재료다
    /// (둘 다 그릴 수 있어야 4 — 하나만이면 3 에 머문다).
    static func isDrawable(_ kind: Kind, resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames(kind).allSatisfy(resourceExists)
    }

    static func isDrawable(_ kind: Kind, fileManager: FileManager = .default) -> Bool {
        isDrawable(kind) { name in
            guard let url = resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: - 장식(프로세스당 케이크마다 한 번 만들고 씬마다 사본)

    private final class Templates: @unchecked Sendable {
        private let lock = NSLock()
        private var made: [Kind: SCNNode] = [:]
        func withLock<R>(_ body: (inout [Kind: SCNNode]) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&made)
        }
    }

    private static let templates = Templates()

    /// 이 케이크의 장식 사본(루트 이름 `cakeDecorNodeName`). 처음 한 번은 몸 메시를 따로 읽어 정수리 hitTest 로 자리를 잡아 만든다 —
    /// 메시가 한 벌이라 자리가 캐릭터마다 같다. 사본은 지오메트리 · 재질을 나눠 쓴다(빌보드 제약은 노드째 복사된다). 메시를 못 읽으면 nil.
    static func decorNode(_ kind: Kind) -> SCNNode? {
        if let hit = templates.withLock({ $0[kind] }) { return hit.clone() }
        guard let scene = CheckCharacter3DScene.loadModelScene(), let body = firstGeometryNode(in: scene.rootNode) else {
            logger.error("cake finish: 장식 자리를 잴 메시가 없다 — 장식 없이 선다")
            return nil
        }
        let started = CFAbsoluteTimeGetCurrent()
        let template = kind.makeDecor(probe: meshSurfaceProbe(body))
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        logger.notice("cake decor built kind=\(kind.rawValue, privacy: .public) ms=\(ms, format: .fixed(precision: 1), privacy: .public)")
        let kept = templates.withLock { made -> SCNNode in
            if let existing = made[kind] { return existing }
            made[kind] = template
            return template
        }
        return kept.clone()
    }

    /// 테스트 전용: 장식 원본을 버린다.
    static func resetCacheForTesting() {
        templates.withLock { $0.removeAll() }
    }

    private static func firstGeometryNode(in root: SCNNode) -> SCNNode? {
        var found: SCNNode?
        root.enumerateHierarchy { node, stop in
            if node.geometry != nil, !isDecor(node) { found = node; stop.pointee = true }
        }
        return found
    }

    // MARK: - 프레이밍

    /// 케이크 캐릭터 노드를 **아래로** 내려 세우는 양(모델 단위 — 부유 · 살랑은 이 자리를 중심으로 돈다).
    ///
    /// 카메라는 모든 아잉 변형이 같은 구도로 몸만 보고 선다(`CheckCharacter3DScene.addFramingCamera` — 위로 0.55·extent 올려 0.16·extent
    /// 아래를 본다). 그 구도는 위가 빠듯하고 아래가 넉넉하다(아잉 실측: 부유 꼭대기 몸 위 끝 프레임 위에서 0.103 · 부유 바닥 몸 아래 끝 바닥에서
    /// 0.151 — `V0366CakeMac3DTests.framingKeepsTheFlameInside` 가 같은 렌더로 다시 잰다). 초코는 초와 빛 번짐이 몸 위로 0.34 + 판 반폭만큼 솟아
    /// 부유 꼭대기에서 위로 나갔다(생성기 실측 −0.006). 몸을 줄이면(카메라를 물리면) 다른 아잉 변형과 크기가 갈리고, 카메라를 올리면 씬마다 다른
    /// 구도가 된다(울트라 교체는 남의 씬 카메라를 그대로 쓴다) — 그래서 **케이크 노드만** 내린다. 크기 · 다른 캐릭터의 구도는 그대로다.
    ///
    /// 값: 초코 빛 번짐(알파 > 8/255)의 위 끝이 부유 꼭대기에서도 프레임 위 가장자리에서 2% 이상 떨어지고, 몸 아래 끝은 부유 바닥에서도 프레임
    /// 바닥에서 2% 이상 떨어지게(시험이 둘 다 렌더로 잰다). 두 케이크가 같은 값이다(나란히 놓여도 몸 자리가 같다 — 초상과 같은 규약).
    static let framingDrop: Float = 0.075

    // MARK: - 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 케이크 마감을 입힌다: 얼굴 디퓨즈를 밝기 맵으로 합성하고(무지개와 같은 그림 · 같은 캐시), 그 재질에
    /// 몸 셰이더를 걸고(초코는 `ckShadeMap` 인자까지), 몸 메시 노드에 장식 사본을 붙이고, 표식을 달고, 노드를 `framingDrop` 만큼 내린다.
    /// **unlit 정규화(`applyUnlitMaterials`) 뒤 · 감은 눈 노드 앞에** 불러야 한다(금 · 무지개와 같은 순서). 그림 · 메시가 없으면 아무것도
    /// 바꾸지 않고 false(보라 아잉이 그대로 선다 — 그 빌드는 능력 번호 4 를 보내지 않는다).
    @discardableResult
    static func apply(_ kind: Kind, to character: SCNNode) -> Bool {
        guard let shade = RainbowAingFinish.shadeImage() else {
            logger.error("cake finish: 밝기 맵이 없다 — 보라 아잉으로 선다")
            return false
        }
        // 먼저 다 구해 두고 나서 바꾼다 — 중간에 실패하면 반쯤 입힌 캐릭터가 남지 않게.
        var faces: [(material: SCNMaterial, composite: CGImage)] = []
        var bodyNode: SCNNode?
        character.enumerateHierarchy { node, _ in
            guard !isDecor(node) else { return }
            for material in node.geometry?.materials ?? [] {
                guard let contents = material.diffuse.contents,
                      CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { continue }
                let face = contents as! CGImage
                guard face.width >= 256, let composite = RainbowAingFinish.rainbowDiffuse(for: face) else { continue }
                faces.append((material, composite))
                if bodyNode == nil { bodyNode = node }
            }
        }
        guard let bodyNode, !faces.isEmpty else {
            logger.error("cake finish: 얼굴 재질을 못 찾았다 — 보라 아잉으로 선다")
            return false
        }
        guard let decor = decorNode(kind) else { return false }
        for face in faces {
            face.material.diffuse.contents = face.composite
            face.material.shaderModifiers = kind.bodyShaderModifiers
            if kind == .choco {
                face.material.setValue(SCNMaterialProperty(contents: shade), forKey: ChocoBody.shadeMapKey)
            }
        }
        // 장식은 **몸 메시 노드**의 자식이다(정수리 hitTest 가 그 노드의 물체 좌표로 자리를 잡았다 — aing.scn 은 캐릭터 노드가 곧 메시 노드다).
        bodyNode.addChildNode(decor)
        let marker = SCNNode()
        marker.name = kind.markerName
        character.addChildNode(marker)
        character.simdPosition.y -= framingDrop
        return true
    }

    /// 이 캐릭터 노드가 어느 케이크인가(표식). 케이크가 아니면 nil.
    static func kind(of character: SCNNode?) -> Kind? {
        guard let character else { return nil }
        return Kind.allCases.first { character.childNode(withName: $0.markerName, recursively: false) != nil }
    }

    /// 이 노드가 케이크 장식인가 — 자기나 조상 중에 `cakeDecorNodeName` 이 있다. 얼굴 탐색 · 몸 클릭 hitTest 가 이 판정으로 건너뛴다.
    static func isDecor(_ node: SCNNode) -> Bool {
        var cursor: SCNNode? = node
        while let current = cursor {
            if current.name == cakeDecorNodeName { return true }
            cursor = current.parent
        }
        return false
    }

    /// 이 노드(보통 리액션 wrapper) 아래 **몸만**의 바운딩박스(이 노드 좌표). 케이크 장식이 없으면 SceneKit 값 그대로다(다른 캐릭터는 한 비트도
    /// 안 바뀐다). 있으면 장식 밖 지오메트리 노드의 상자 여덟 모서리를 이 노드 좌표로 옮겨 합친다 — 리액션 진폭(`modelExtent`)과 클릭 프리체크
    /// 상자가 초 · 빛 번짐에 부풀지 않게.
    static func bodyBoundingBox(of node: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
        var hasDecor = false
        node.enumerateHierarchy { child, stop in
            if child.name == cakeDecorNodeName { hasDecor = true; stop.pointee = true }
        }
        guard hasDecor else { return node.boundingBox }
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        // ★ 노드의 `boundingBox` 가 아니라 **지오메트리의** `boundingBox` 를 잰다: SceneKit 노드 상자는 자손을 감싼다 — 장식은 몸 메시 노드의
        //   자식이라 그 노드 상자에 초 · 빛 번짐이 그대로 들어온다(`V0366CakeMac3DTests.bodyBoundingBoxIgnoresTheDecor` 실측 — 몸 위 끝 0.849 → 1.122).
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry, !isDecor(child) else { return }
            let (a, b) = geometry.boundingBox
            for corner in [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, a.y, a.z), SCNVector3(a.x, b.y, a.z), SCNVector3(b.x, b.y, a.z),
                           SCNVector3(a.x, a.y, b.z), SCNVector3(b.x, a.y, b.z), SCNVector3(a.x, b.y, b.z), SCNVector3(b.x, b.y, b.z)] {
                let p = child.convertPosition(corner, to: node)
                let v = SIMD3(Float(p.x), Float(p.y), Float(p.z))
                lo = simd_min(lo, v)
                hi = simd_max(hi, v)
            }
        }
        guard lo.x <= hi.x else { return node.boundingBox }
        return (SCNVector3(lo.x, lo.y, lo.z), SCNVector3(hi.x, hi.y, hi.z))
    }
}
