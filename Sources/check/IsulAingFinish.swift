import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 이슬 아잉이 3D 마감 (v0.3.74 — '술 한잔' 선물 전용, 시안 R '초록 글씨 라벨')
//
// 이슬 아잉이는 아잉과 **같은 메시**(aing.scn)다. 마감은 넷이다(그림 생성기 `scripts/make-isul-aing.swift` 머리말 '앱이 할 일' 1–5):
//
//  ① 디퓨즈 합성 — 무지개 · 케이크와 **같다**(`isGoldSkin(원본) ? aing_rainbow-shade.png : 원본`). 같은 입력 · 같은 함수라 결과 그림도 같으므로
//     무지개의 캐시(`RainbowAingFinish.rainbowDiffuse`)를 그대로 쓴다 — 감은 눈도 무지개 · 케이크 순서(라벤더 원본에 먼저 감은 눈 → 같은 합성,
//     `CheckCharacter3DScene.makeClosedEyesImage` 의 무지개 갈래)를 그대로 탄다. 몸 셰이더가 '표본한 디퓨즈'에서 피부 비율을 읽으므로
//     깜빡임 · 졸기 · 울트라 교체로 디퓨즈가 바뀌어도 초록 유리가 따라온다.
//  ② 몸 셰이더 — `IsulBody.shaderModifiers`(geometry + fragment) + 셰이더 인자 둘: `ckShadeMap`(= aing_rainbow-shade.png — 무지개 캐시와 같은 그림)
//     · `ckLabelMap`(라벨 그림 — `IsulArt` 저장소: 디스크 캐시 → 번들 폴백, mipFilter .linear). **아래 '생성기 사본' 두 구획은 생성기의 글자
//     그대로다**(BEGIN/END 표식 사이 — 들여쓰기만 한 칸 안으로). `V0374IsulMac3DTests` 가 두 파일의 그 구획을 주석 · 공백을 걷어 맞댄다
//     (생성기를 고치면 여기도 같이 — 안 그러면 빨갛다).
//  ③ 병뚜껑 — `IsulCap.make(probe:)` 가 만든 `check.isulDecor` 노드 하나를 몸 메시 노드의 자식으로 붙인다(부유 · 살랑 · 요 회전을 그대로 따른다).
//     probe 는 케이크 `CakeAingFinish.meshSurfaceProbe(bodyNode)` 그대로다. 만들기는 **프로세스당 한 번**이고 씬마다 `clone()` 을 붙인다
//     (지오메트리 · 재질을 나눠 쓴다). 붙이는 순서는 케이크 장식과 같다 — 프레이밍 카메라를 몸만 보고 세운 **뒤** · 감은 눈 노드 **앞**.
//  ④ 표식 — 캐릭터 노드에 빈 노드 `markerName` 을 단다(엔진 `currentCharacterID` 가 아잉 · 케이크와 가른다 — 같은 메시라 종류로 못 가른다).
//
// ★ 장식은 몸이 아니다: 얼굴 재질 탐색(병뚜껑 텍스처 512×128 은 '큰 CGImage 디퓨즈' 조건을 만족한다) · 몸 클릭 hitTest · 리액션 진폭은
//   케이크 장식과 **같은 자리**에서 `AingDecor`(두 장식 루트 이름 — `check.cakeDecor` · `check.isulDecor`)로 뺀다.
// ★ 프레이밍: 케이크처럼 내려 세우지 않는다. 뚜껑 꼭대기(`IsulCap.capTopY` 1.0032)는 초코 불꽃(1.1839)보다 한참 낮아 지금 앱 카메라(몸만 보고
//   잡은 40°)로도 부유 꼭대기(+0.07)에서 프레임 위 여백이 남는다(생성기 실측 부유 0 → 0.095 · +0.07 → 0.071). `V0374IsulMac3DTests` 가 같은
//   앱 경로 렌더로 다시 잰다 — 카메라 식이 바뀌어 여백이 2% 밑으로 떨어지면 빨갛다.
enum IsulAingFinish {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// 장식 루트 이름(생성기 `IsulCap.decorNodeName` — "check.isulDecor"). 이 노드 **아래 전부**가 장식이다(`AingDecor.isDecor`).
    static var decorNodeName: String { IsulCap.decorNodeName }

    /// "이 캐릭터 노드는 이슬이다"의 표식 노드 이름(지오메트리 없는 빈 노드 — 몸 크기 계산에 안 낀다). 엔진의 `currentCharacterID` 가 읽는다.
    static let markerName = "check.isulAing"

    // ── 생성기 사본 시작 ─────────────────────────────────────────────────────────────────────────────────────────────
    // 아래 두 구획(몸 셰이더 `IsulBody` / 병뚜껑 `IsulCap`)은 `scripts/make-isul-aing.swift` 의 BEGIN/END 구획을 **글자 그대로** 옮겼다
    // (들여쓰기 한 칸만 다르다). 고치지 마라 — 생성기를 고치고 다시 옮겨라(`V0374IsulMac3DTests.generatorRegionsAreVerbatim`).

    // BEGIN isul-body-shader — 앱 IsulAingFinish 가 이 구획을 글자 그대로 옮긴다(시험이 주석 · 공백을 걷고 맞댄다). 여기를 고치면 앱도 같이.

    /// 이슬 아잉이 몸 셰이더(시안 R). 틀은 케이크 초코(ChocoBody)와 같다: 디퓨즈 = 무지개 합성, 셰이더 인자 ckShadeMap(그 자리 피부 S),
    /// 얼굴은 피부 비율 β(초코의 눈 테 풀기 식)로 원본을 지킨다. 몸 색 = 초록 유리(시선 의존 프레넬 · 굴절 초승달 · 바닥 코스틱) + 화면 공간
    /// 반사 줄 + 흰 곡선 라벨(셰이더 인자 ckLabelMap 을 둘레각 θ · 높이 t 로 표본). 전부 물체 좌표 — 메시 UV 섬 점 함정이 없다.
    /// aing.scn 에는 법선이 없어 몸을 감싼 타원체 기울기로 법선을 만들고, unlit 이라 시선은 geometry 단계 varying 으로 넘긴다.
    enum IsulBody {
        // 몸 좌표(무지개 `RainbowAingArt` · 케이크와 같은 값 — 메시가 바뀌면 같이).
        static let bodyTop = 0.848950
        static let bodyHeight = 1.695736
        static let ellipsoid = SIMD3<Double>(0.6084, 0.7191, 0.5329)
        // 합성 디퓨즈 피부 텍셀 선형 휘도 중앙값 · 원본 디퓨즈 볼터치 평균(sRGB 0–255) — 케이크 chocoSkinYRef · chocoBlushSRGB 와 같다.
        static let skinYRef = 0.56530
        static let blushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
        static let shadeMapKey = "ckShadeMap"
        static let labelMapKey = "ckLabelMap"
        // 라벨 자리: 둘레각 θ ∈ [−halfWidth, +halfWidth](라디안, 정면 0) · 높이 t ∈ [t0, t1](정수리 0 → 바닥 1).
        static let labelHalfWidth = 1.00
        static let labelT0 = 0.475
        static let labelT1 = 0.800
        // 유리색(sRGB 16진): 가운데 · 중간 · 가장자리(두꺼운 유리) · 가장자리 밝은 테.
        static let glassCore = 0x5ED18C
        static let glassMid = 0x1E8E4E
        static let glassDeep = 0x094726
        static let glassRim = 0xB9F5CF
        static let glassEdgePow = 1.5
        static let glassShadeMix = 0.55

        static func f5(_ v: Double) -> String { String(format: "%.5f", v) }
        static func f5v(_ v: SIMD3<Double>) -> String { String(format: "float3(%.5f, %.5f, %.5f)", v.x, v.y, v.z) }
        static func toLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        static func f5hex(_ hex: Int) -> String {
            f5v(SIMD3(toLinear(Double((hex >> 16) & 255) / 255), toLinear(Double((hex >> 8) & 255) / 255), toLinear(Double(hex & 255) / 255)))
        }

        static let geometry = """
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

        /// 초록 유리 바탕: 가운데(시선과 마주한 면)는 밝은 초록, 가장자리로 갈수록 두꺼운 유리라 짙은 병 초록. 바닥은 짙고 그 위로 밝은 띠(코스틱).
        static let glass = """
        float ckFr = pow(1.0 - ckNV, \(f5(glassEdgePow)));
        float3 ckGlass = mix(\(f5hex(glassCore)), \(f5hex(glassMid)), smoothstep(0.0, 0.36, ckFr));
        ckGlass = mix(ckGlass, \(f5hex(glassDeep)), smoothstep(0.32, 0.95, ckFr));
        float ckCres = smoothstep(0.18, 0.40, ckNV) * (1.0 - smoothstep(0.45, 0.70, ckNV)) * smoothstep(-0.15, -0.65, ckVn.y + 0.35 * ckVn.x);
        ckGlass = mix(ckGlass, \(f5hex(glassCore)) * 1.15, ckCres * 0.55);
        float ckBottom = smoothstep(0.86, 0.985, ckT);
        ckGlass = mix(ckGlass, \(f5hex(glassDeep)), ckBottom * 0.55);
        float ckCaustic = (1.0 - smoothstep(0.0, 0.06, abs(ckT - 0.84))) * smoothstep(0.2, 0.7, ckNV);
        ckGlass += \(f5hex(glassCore)) * ckCaustic * 0.25;
        ckBase = ckGlass;
        ckShadeMix = \(f5(glassShadeMix));
        """

        /// 유리 반사: 화면 공간에 고정된 세로 반사 줄 셋 + 정수리 반짝 + 가장자리 밝은 테. 얼굴 위에서는 약하게.
        static let highlights = """
        float ckS1 = (1.0 - smoothstep(0.045, 0.085, abs(ckVn.x + 0.56 - 0.10 * ckVn.y))) * smoothstep(-0.62, -0.18, ckVn.y) * (1.0 - smoothstep(0.50, 0.78, ckVn.y));
        float ckS2 = (1.0 - smoothstep(0.012, 0.028, abs(ckVn.x + 0.74 - 0.06 * ckVn.y))) * smoothstep(-0.45, -0.05, ckVn.y) * (1.0 - smoothstep(0.35, 0.60, ckVn.y));
        float ckS3 = (1.0 - smoothstep(0.015, 0.035, abs(ckVn.x - 0.66))) * smoothstep(-0.30, 0.0, ckVn.y) * (1.0 - smoothstep(0.30, 0.50, ckVn.y));
        float ckTop = pow(max(dot(ckVn, normalize(float3(-0.30, 0.62, 0.72))), 0.0), 70.0);
        float ckRimL = pow(1.0 - ckNV, 5.0);
        float ckHiFace = 1.0 - 0.75 * ckFace;
        ckAdd += float3(0.86, 1.0, 0.90) * ((ckS1 * 0.55 + ckS2 * 0.45 + ckS3 * 0.30) * ckHiFace + ckTop * 0.70);
        ckAdd += \(f5hex(glassRim)) * ckRimL * 0.22;
        """

        /// 라벨: 텍스처(프리멀티 — 표본 rgb 는 이미 알파를 곱했다)를 (θ, t) 로 읽어 유리 위에 얹는다. 라벨 위에서는 반사를 줄인다.
        static let label = """
        constexpr sampler ckLblSmp(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_zero);
        float2 ckLuv = float2((ckTh + \(f5(labelHalfWidth))) / \(f5(2 * labelHalfWidth)), (ckT - \(f5(labelT0))) / \(f5(labelT1 - labelT0)));
        float4 ckL4 = ckLabelMap.sample(ckLblSmp, ckLuv);
        ckBase = ckBase * (1.0 - ckL4.a) + ckL4.rgb;
        ckAdd *= 1.0 - 0.75 * ckL4.a;
        """

        static let pattern = glass + highlights + label

        /// 몸 출력: 무늬 색 × 구운 밝기 + 반사. 얼굴 상자 안은 β 로 원본(눈 · 입 · 볼터치)을 지킨다. ★ 섞기는 β 를 잰 sRGB 0–255 공간에서
        /// 한다(선형에서 섞으면 눈꺼풀 · 입 테 텍셀이 라벤더를 지나치게 빼서 짙은 순초록으로 잘린다 — 생성기 머리말 '고친 것' ①).
        static let bodyOutput = """
        float3 ckCol = ckBase * mix(1.0, ckShade, ckShadeMix) + ckAdd;
        bool ckInFace = ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62;
        float ckB = ckInFace ? ckBeta : 1.0;
        float3 ckCc = clamp(ckCol, float3(0.0), float3(1.0));
        float3 ckCe = 255.0 * select(1.055 * pow(ckCc, float3(1.0 / 2.4)) - 0.055, ckCc * 12.92, ckCc <= float3(0.0031308));
        float3 ckOe = clamp((ckPe + ckB * (ckCe - ckSe)) / 255.0, float3(0.0), float3(1.0));
        float3 ckOut = select(pow((ckOe + 0.055) / 1.055, float3(2.4)), ckOe / 12.92, ckOe <= float3(0.04045));
        _output.color = float4(ckOut, 1.0);
        """

        /// fragment 수정자: 디퓨즈 P · 피부 S · 피부 비율 β(케이크 초코와 같은 식) · 물체 좌표 값들 → 무늬(`pattern`) → `output`.
        /// 무늬가 쓸 수 있는 값: ckP(물체 좌표) · ckT(정수리 0 → 바닥 1) · ckTh(둘레각, 정면 0) · ckVn(화면 공간 법선) · ckNV(시선 · 법선 코사인,
        /// 0 = 가장자리) · ckFace(얼굴 둘레 0…1). 정할 값: ckBase(선형 바탕색) · ckAdd(더할 반사광) · ckShadeMix(구운 밝기를 얼마나 쓸지).
        static func fragment(output: String) -> String {
            """
            #pragma arguments
            texture2d<float> ckShadeMap;
            texture2d<float> ckLabelMap;
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
            float ckFx = ckP.x / 0.60;
            float ckFy = (ckP.y - 0.34) / 0.30;
            float ckFace = (1.0 - smoothstep(0.85, 1.15, ckFx * ckFx + ckFy * ckFy)) * smoothstep(0.05, 0.25, ckP.z);
            float3 ckBase = float3(1.0);
            float3 ckAdd = float3(0.0);
            float ckShadeMix = 1.0;
            \(pattern)
            \(output)
            """
        }

        static var shaderModifiers: [SCNShaderModifierEntryPoint: String] {
            [.geometry: geometry, .fragment: fragment(output: bodyOutput)]
        }
    }

    // END isul-body-shader

    // BEGIN isul-cap-decor — 앱 IsulAingFinish 가 이 구획을 글자 그대로 옮긴다(시험이 주석 · 공백을 걷고 맞댄다). 여기를 고치면 앱도 같이.

    /// 돌려 따는 초록 병뚜껑(시안 R): 옆면 세로 홈 36(널링) · 아래쪽 따개 고리 틈 · 둥근 윗모서리 · 윗면 가운데 살짝 오목. 정수리 (x 0.09, z 0.01)에
    /// 몸 법선을 30% 따라 세우고 바깥으로 0.28 라디안 더 기울인다(비스듬히). 매개 곡면 → SCNGeometry + 음영을 구운 작은 텍스처(몸 공간 고정 빛), unlit.
    enum IsulCap {
        static let decorNodeName = "check.isulDecor"
        static let capNodeName = "check.isul.cap"
        static let crownX: Float = 0.09
        static let crownZ: Float = 0.01
        static let follow: Float = 0.30
        static let tilt: Float = 0.28
        static let radius: Float = 0.185
        static let height: Float = 0.165
        /// 뚜껑 꼭대기(물체 좌표 y) — 앱 프레이밍이 쓴다. 생성기가 실행 때 다시 재서 맞댄다.
        static let capTopY = 1.0032
        static let metal = 0x1F7A45
        static let metalHi = 0x6CC892
        static let metalTop = 0x2E9058

        typealias SurfaceProbe = (Float, Float) -> (SIMD3<Float>, SIMD3<Float>)
        typealias SurfaceFn = (Float, Float) -> SIMD3<Float>

        struct Look {
            var ambient = 0.62
            var spec = 0.25
            var gloss = 24.0
            var wrap = 0.4
        }

        /// 몸 공간에 고정한 빛(위 · 앞 · 살짝 왼쪽) — 아잉 디퓨즈에 구운 음영과 같은 쪽.
        static let keyLight = simd_normalize(SIMD3<Double>(-0.30, 0.85, 0.45))
        static let viewLight = simd_normalize(SIMD3<Double>(0, 0.30, 1))

        static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
            let t = min(max((x - e0) / (e1 - e0), 0), 1)
            return t * t * (3 - 2 * t)
        }

        static func lin(_ hex: Int) -> SIMD3<Double> {
            func l(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return SIMD3(l(Double((hex >> 16) & 255) / 255), l(Double((hex >> 8) & 255) / 255), l(Double(hex & 255) / 255))
        }

        static func srgbByte(_ v: Double) -> UInt8 {
            let c = min(max(v, 0), 1)
            let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
            return UInt8(max(0, min(255, (s * 255).rounded())))
        }

        static func lit(_ albedo: SIMD3<Double>, _ n: SIMD3<Double>, _ look: Look) -> SIMD3<Double> {
            let ndl = simd_dot(n, keyLight)
            let diff = min(max((ndl + look.wrap) / (1 + look.wrap), 0), 1)
            let ao = 1 - 0.22 * max(-n.y, 0)
            var c = albedo * (look.ambient + (1 - look.ambient) * diff) * ao
            let h = simd_normalize(keyLight + viewLight)
            c += SIMD3(repeating: pow(max(simd_dot(n, h), 0), look.gloss) * look.spec)
            return simd_clamp(c, .zero, SIMD3(repeating: 1))
        }

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

        static func pieceNode(name: String, nu: Int, nv: Int, closedU: Bool, texW: Int, texH: Int, pos: @escaping SurfaceFn,
                              albedo: (Double, Double, SIMD3<Float>) -> SIMD3<Double>, look: Look, transform: simd_float4x4) -> SCNNode {
            let rot = simd_float3x3(simd_make_float3(transform.columns.0), simd_make_float3(transform.columns.1), simd_make_float3(transform.columns.2))
            var verts = [SCNVector3](), norms = [SCNVector3](), uvs = [CGPoint]()
            for j in 0...nv { for i in 0...nu {
                let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
                let p = pos(u, v), n = surfaceNormal(pos, u, v, closedU: closedU)
                verts.append(SCNVector3(p.x, p.y, p.z)); norms.append(SCNVector3(n.x, n.y, n.z)); uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            } }
            var idx = [UInt32]()
            let row = UInt32(nu + 1)
            for j in 0..<UInt32(nv) { for i in 0..<UInt32(nu) {
                let a = j * row + i, b = a + 1, c = a + row, d = c + 1
                idx += [a, b, c, b, d, c]
            } }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                                 SCNGeometrySource(textureCoordinates: uvs)],
                                       elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
            var px = [UInt8](repeating: 255, count: texW * texH * 4)
            for y in 0..<texH { for x in 0..<texW {
                var acc = SIMD3<Double>(0, 0, 0)
                for sy in 0..<2 { for sx in 0..<2 {
                    let u = (Double(x) + 0.25 + 0.5 * Double(sx)) / Double(texW), v = (Double(y) + 0.25 + 0.5 * Double(sy)) / Double(texH)
                    acc += albedo(u, v, pos(Float(u), Float(v)))
                } }
                let u = Float((Double(x) + 0.5) / Double(texW)), v = Float((Double(y) + 0.5) / Double(texH))
                let nw = rot * surfaceNormal(pos, u, v, closedU: closedU)
                let c = lit(acc / 4, simd_normalize(SIMD3<Double>(Double(nw.x), Double(nw.y), Double(nw.z))), look)
                let o = (y * texW + x) * 4
                px[o] = srgbByte(c.x); px[o + 1] = srgbByte(c.y); px[o + 2] = srgbByte(c.z)
            } }
            let ctx = CGContext(data: &px, width: texW, height: texH, bitsPerComponent: 8, bytesPerRow: texW * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = ctx.makeImage()!
            material.diffuse.wrapS = closedU ? .repeat : .clamp
            material.diffuse.wrapT = .clamp
            material.diffuse.mipFilter = .linear
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = name
            node.simdTransform = transform
            return node
        }

        static func lathe(_ profile: @escaping (Float) -> (r: Float, y: Float), ridge: ((Float, Float) -> Float)? = nil) -> SurfaceFn {
            { u, v in
                let (r0, y) = profile(v)
                let a = 2 * Float.pi * u
                let r = r0 * (ridge?(u, v) ?? 1)
                return SIMD3(r * sin(a), y, r * cos(a))
            }
        }

        /// 정수리 (crownX, crownZ) 의 몸 표면 점에 세운 변환: 위 방향 = 세로축과 몸 법선 사이(follow) + 바깥으로 tilt 라디안.
        static func placement(probe: SurfaceProbe) -> simd_float4x4 {
            let (p, n0) = probe(crownX, crownZ)
            var n = simd_normalize(n0)
            if n.y < 0 { n = -n }
            var up = simd_normalize(simd_mix(SIMD3<Float>(0, 1, 0), n, SIMD3(repeating: follow)))
            let outward = simd_normalize(SIMD3<Float>(crownX, 0, crownZ) + SIMD3(1e-4, 0, 0))
            up = simd_normalize(up + outward * tan(tilt))
            var m = simd_float4x4(simd_quatf(from: SIMD3(0, 1, 0), to: up))
            m.columns.3 = SIMD4(p.x, p.y, p.z, 1)
            return m
        }

        static func capNode(transform: simd_float4x4) -> SCNNode {
            let rc = radius, hc = height
            let e: Float = 0.022, sink: Float = 0.045
            let side = hc - e, arc = Float.pi / 2 * e, cap = rc - e, total = side + arc + cap
            let profile: (Float) -> (r: Float, y: Float) = { s in
                let d = s * total
                if d < side {
                    let y = d - sink
                    let notch = Float(1 - 0.07 * smooth(0.0, 1.0, 1 - abs(Double(y + sink) - 0.068) / 0.008))
                    return (rc * notch, y)
                }
                if d < side + arc {
                    let phi = (d - side) / e
                    return (rc - e + e * cos(phi), side - sink + e * sin(phi))
                }
                let t = (d - side - arc) / cap
                return (max(0, (rc - e) * (1 - t)), hc - sink - 0.004 * Float(sin(Double(t) * .pi)))
            }
            let ridge: (Float, Float) -> Float = { u, v in
                let d = v * total
                guard d < side - 0.004, d > 0.082 else { return 1 }
                return 1 + 0.030 * Float(pow(abs(cos(Double(u) * 2 * .pi * 36)), 2) - 0.5)
            }
            let base = lin(metal), hi = lin(metalHi), top = lin(metalTop)
            func albedo(_ u: Double, _ v: Double, _ p: SIMD3<Float>) -> SIMD3<Double> {
                let d = v * Double(total)
                if d >= Double(side + arc) { return top }
                let groove = pow(abs(cos(u * 2 * .pi * 36)), 2)
                var c = base + (hi - base) * groove * 0.6
                if d < 0.082 { c = base * 0.95 + (hi - base) * 0.25 }
                return c
            }
            return pieceNode(name: capNodeName, nu: 240, nv: 40, closedU: true, texW: 512, texH: 128, pos: lathe(profile, ridge: ridge),
                             albedo: albedo, look: Look(ambient: 0.55, spec: 0.55, gloss: 42, wrap: 0.35), transform: transform)
        }

        /// 장식 루트(이름 `decorNodeName`) — 캐릭터 노드의 자식으로 붙인다.
        static func make(probe: SurfaceProbe) -> SCNNode {
            let root = SCNNode()
            root.name = decorNodeName
            root.addChildNode(capNode(transform: placement(probe: probe)))
            return root
        }

        /// 장식 루트 좌표(= 물체 좌표)에서 정점의 가장 높은 y.
        static func topY(_ decor: SCNNode) -> Float {
            var top = -Float.infinity
            func walk(_ node: SCNNode, _ parent: simd_float4x4) {
                let m = parent * node.simdTransform
                if let source = node.geometry?.sources(for: .vertex).first {
                    source.data.withUnsafeBytes { raw in
                        for i in 0..<source.vectorCount {
                            let b = source.dataOffset + i * source.dataStride
                            let p: SIMD3<Float>
                            if source.bytesPerComponent == 8 {
                                p = SIMD3(Float(raw.loadUnaligned(fromByteOffset: b, as: Double.self)), Float(raw.loadUnaligned(fromByteOffset: b + 8, as: Double.self)),
                                          Float(raw.loadUnaligned(fromByteOffset: b + 16, as: Double.self)))
                            } else {
                                p = SIMD3(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                                          raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self))
                            }
                            top = max(top, (m * SIMD4(p.x, p.y, p.z, 1)).y)
                        }
                    }
                }
                for child in node.childNodes { walk(child, m) }
            }
            for child in decor.childNodes { walk(child, matrix_identity_float4x4) }
            return top
        }
    }

    // END isul-cap-decor

    // ── 생성기 사본 끝 ───────────────────────────────────────────────────────────────────────────────────────────────

    /// 몸 셰이더(생성기 사본 그대로 — 생성기의 `IsulBody.shaderModifiers` 는 부를 때마다 글을 새로 짓는 계산 속성이라 프로세스당 한 번만 짓는다).
    static let bodyShaderModifiers: [SCNShaderModifierEntryPoint: String] = IsulBody.shaderModifiers

    // MARK: - 번들 자원 · 그릴 수 있다

    /// 이슬을 그리는 데 필요한 **번들** 그림 — 초상 두 장 · 라벨 폴백(`IsulArt` 의 번들 사본) + 무지개와 **같이 쓰는** 밝기 맵
    /// (`aing_rainbow-shade.png` — 디퓨즈 합성 · 셰이더 인자 ckShadeMap). 병뚜껑 텍스처는 코드가 만들므로 파일이 없다.
    /// 디스크 캐시(운영 Storage 에서 받은 새 그림)는 '그릴 수 있다'의 재료가 아니다 — 번들 폴백이 늘 있어야 캐시가 지워져도 선다.
    static func requiredResourceNames() -> [String] {
        IsulArt.Kind.allCases.map(\.bundleName) + [RainbowAingArt.shadeResourceName]
    }

    /// 이 빌드가 이슬을 그릴 수 있는가 — 위 네 장이 **실재**한다(케이크 규약). 상점 능력 번호 5(`ShopWire.protocolVersion`)의 재료다.
    static func isDrawable(resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames().allSatisfy(resourceExists)
    }

    static func isDrawable(fileManager: FileManager = .default) -> Bool {
        isDrawable { name in
            guard let url = CakeAingFinish.resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: - 라벨 텍스처(셰이더 인자 ckLabelMap)

    /// 라벨 그림이 없을 때(번들 폴백까지 깨진 빌드) 묶는 1×1 투명 — 셰이더는 표본 알파 0 이면 라벨 없는 유리 병으로 선다(생성기 머리말 3).
    static let emptyLabelImage: CGImage = CakeAingFinish.makeImage([0, 0, 0, 0], 1, 1)

    /// 재질 하나에 묶을 라벨 인자(생성기 `makeRig` 와 같은 설정 — mipFilter .linear). 그림은 `IsulArt` 저장소(디스크 캐시 → 번들)에서 온다.
    static func labelProperty(_ image: CGImage? = IsulArt.shared.labelImage()) -> SCNMaterialProperty {
        let property = SCNMaterialProperty(contents: image ?? emptyLabelImage)
        property.mipFilter = .linear
        return property
    }

    // MARK: - 병뚜껑(프로세스당 한 번 만들고 씬마다 사본)

    /// 원본 하나 + 새로 구운 횟수(시험 관찰). 자물쇠 안에서 굽는다 — 두 스레드가 같이 찾아도 한 번만 굽고 기다린 쪽은 그 원본을 받는다.
    private struct TemplateState {
        var template: SCNNode?
        var builds = 0
        /// 원본을 구운 스레드가 메인이었는가(굽기마다 하나 — 시험 전용 관찰).
        var onMain: [Bool] = []
    }

    private static let templateState = OSAllocatedUnfairLock(uncheckedState: TemplateState())

    /// 병뚜껑 사본(루트 이름 `decorNodeName`). 처음 한 번은 몸 메시를 따로 읽어 정수리 hitTest 로 자리를 잡아 만든다 — 메시가 한 벌이라
    /// 자리가 캐릭터마다 같다. 사본은 지오메트리 · 재질을 나눠 쓴다. 메시를 못 읽으면 nil.
    ///
    /// 처음 만들기 비용은 `V0374IsulMac3DTests.decorIsBuiltOncePerProcess` 가 찍는다(뚜껑 한 조각 — 241×41 정점 · 512×128 텍스처). 실측
    /// debug 210ms(2026-11-03) — 케이크 딸기(debug 2.7초 · release 78ms)의 1/13 이지만 첫 이슬 씬이 메인에서 구우면 그만큼 멎으므로, 케이크와
    /// 같은 자리 · 같은 방식으로 시작 뒤 메인 밖에서 미리 굽는다(`CakeAingFinish.prewarmDecorTemplates` — 검토 수리). 원본은 **어느 씬에도 붙지 않은**
    /// 새 노드라 어느 스레드에서 불러도 된다(케이크 `decorNode` 주석과 같은 이유). 자물쇠 안에서 굽고 넣으므로 미리 굽기와 메인이 겹쳐도 한 번이다.
    static func decorNode() -> SCNNode? {
        templateState.withLockUnchecked { state -> SCNNode? in
            if let template = state.template { return template.clone() }
            guard let scene = CheckCharacter3DScene.loadModelScene(), let body = firstGeometryNode(in: scene.rootNode) else {
                logger.error("isul finish: 병뚜껑 자리를 잴 메시가 없다 — 뚜껑 없이 선다")
                return nil
            }
            let started = CFAbsoluteTimeGetCurrent()
            let template = IsulCap.make(probe: CakeAingFinish.meshSurfaceProbe(body))
            let ms = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            let onMain = Thread.isMainThread
            // 런 루프가 없는 스레드에서 만들면 SceneKit 의 암묵 트랜잭션이 열린 채 남는다 — 닫는다(케이크 `decorNode` 와 같은 이유).
            if !onMain { SCNTransaction.flush() }
            logger.notice("isul cap built ms=\(ms, format: .fixed(precision: 1), privacy: .public) main=\(onMain, privacy: .public)")
            state.template = template
            state.builds += 1
            state.onMain.append(onMain)
            return template.clone()
        }
    }

    /// 시험 전용: 지금까지 원본을 새로 구운 횟수.
    static var decorBuildCountForTesting: Int { templateState.withLockUnchecked { $0.builds } }

    /// 시험 전용: 원본을 구운 스레드가 메인이었는가(굽기마다 하나).
    static var decorBuildsOnMainForTesting: [Bool] { templateState.withLockUnchecked { $0.onMain } }

    /// 시험 전용: 병뚜껑 원본을 버린다(굽기 기록도 — 케이크 `resetCacheForTesting` 과 같다).
    static func resetDecorCacheForTesting() {
        templateState.withLockUnchecked { $0 = TemplateState() }
    }

    private static func firstGeometryNode(in root: SCNNode) -> SCNNode? {
        var found: SCNNode?
        root.enumerateHierarchy { node, stop in
            if node.geometry != nil, !AingDecor.isDecor(node) { found = node; stop.pointee = true }
        }
        return found
    }

    // MARK: - 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 이슬 마감을 입힌다: 얼굴 디퓨즈를 밝기 맵으로 합성하고(무지개와 같은 그림 · 같은 캐시), 그 재질에
    /// 몸 셰이더를 걸고 셰이더 인자 둘(ckShadeMap · ckLabelMap)을 묶고, 몸 메시 노드에 병뚜껑 사본을 붙이고, 표식을 단다. 내려 세우지 않는다
    /// (머리말 ★ 프레이밍). **unlit 정규화(`applyUnlitMaterials`) 뒤 · 감은 눈 노드 앞에** 불러야 한다(금 · 무지개 · 케이크와 같은 순서).
    /// 그림 · 메시가 없으면 아무것도 바꾸지 않고 false(보라 아잉이 그대로 선다 — 그 빌드는 능력 번호 5 를 보내지 않는다).
    @discardableResult
    static func apply(to character: SCNNode) -> Bool {
        guard let shade = RainbowAingFinish.shadeImage() else {
            logger.error("isul finish: 밝기 맵이 없다 — 보라 아잉으로 선다")
            return false
        }
        // 먼저 다 구해 두고 나서 바꾼다 — 중간에 실패하면 반쯤 입힌 캐릭터가 남지 않게.
        var faces: [(material: SCNMaterial, composite: CGImage)] = []
        var bodyNode: SCNNode?
        character.enumerateHierarchy { node, _ in
            guard !AingDecor.isDecor(node) else { return }
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
            logger.error("isul finish: 얼굴 재질을 못 찾았다 — 보라 아잉으로 선다")
            return false
        }
        guard let decor = decorNode() else { return false }
        let label = IsulArt.shared.labelImage()
        for face in faces {
            face.material.diffuse.contents = face.composite
            face.material.shaderModifiers = bodyShaderModifiers
            face.material.setValue(SCNMaterialProperty(contents: shade), forKey: IsulBody.shadeMapKey)
            face.material.setValue(labelProperty(label), forKey: IsulBody.labelMapKey)
        }
        // 뚜껑은 **몸 메시 노드**의 자식이다(정수리 hitTest 가 그 노드의 물체 좌표로 자리를 잡았다 — aing.scn 은 캐릭터 노드가 곧 메시 노드다).
        bodyNode.addChildNode(decor)
        let marker = SCNNode()
        marker.name = markerName
        character.addChildNode(marker)
        return true
    }

    /// 이 캐릭터 노드가 이슬인가(표식).
    static func isIsul(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: markerName, recursively: false) != nil
    }
}

// MARK: - 아잉 메시에 붙는 런타임 장식(케이크 · 이슬) — 몸이 아니다

/// 케이크 장식(`check.cakeDecor` — v0.3.66) · 이슬 병뚜껑(`check.isulDecor` — v0.3.74) · 빼빼로 상자 · 막대(`check.peperoDecor` — v0.3.77)를 **한 판정**으로 뺀다. 얼굴 재질 탐색
/// (`ReactionEngine.locateSleepEyeTargets`) · 몸 클릭 hitTest(`isBodyAtScreenPoint`) · 리액션 진폭과 클릭 프리체크 상자(`modelExtent` ·
/// `projectedBodyViewRect`)가 이것을 쓴다 — 장식이 늘면 이름을 여기 하나에 더한다.
enum AingDecor {
    /// 장식 루트 이름들. 이 이름의 노드 **아래 전부**가 장식이다.
    /// 빼빼로 상자 · 막대(`check.peperoDecor` — v0.3.77)도 여기 하나에 더했다(얼굴 탐색 · 몸 클릭 · 진폭 · 클릭 상자가 같이 뺀다).
    /// 개발에 찌든 아잉이 끈(`check.devDecor`)도 여기 하나에 더했다.
    static let rootNames: Set<String> = [CakeAingFinish.cakeDecorNodeName, IsulAingFinish.IsulCap.decorNodeName, PeperoDecor.decorNodeName,
                                         DevAingFinish.decorNodeName, RegionAingFinish.decorNodeName]

    /// 이 노드가 장식인가 — 자기나 조상 중에 장식 루트가 있다.
    static func isDecor(_ node: SCNNode) -> Bool {
        var cursor: SCNNode? = node
        while let current = cursor {
            if let name = current.name, rootNames.contains(name) { return true }
            cursor = current.parent
        }
        return false
    }

    /// 이 노드(보통 리액션 wrapper) 아래 **몸만**의 바운딩박스(이 노드 좌표). 장식이 없으면 SceneKit 값 그대로다(다른 캐릭터는 한 비트도
    /// 안 바뀐다). 있으면 장식 밖 지오메트리 노드의 **지오메트리** 상자 여덟 모서리를 이 노드 좌표로 옮겨 합친다 — 노드 상자는 자손(장식)을
    /// 감싸므로 쓰지 않는다(케이크 `CakeAingFinish.bodyBoundingBox` 의 실측 주석 — 몸 위 끝 0.849 → 1.122).
    static func bodyBoundingBox(of node: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
        var hasDecor = false
        node.enumerateHierarchy { child, stop in
            if let name = child.name, rootNames.contains(name) { hasDecor = true; stop.pointee = true }
        }
        guard hasDecor else { return node.boundingBox }
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
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
