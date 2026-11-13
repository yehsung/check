import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 흑우 아잉이 3D 마감 (v0.3.78 — 조각 20개로만 바꾸는 캐릭터, 시안 U9 '네온')
//
// 흑우 아잉이는 아잉과 **같은 메시**(aing.scn)다. 마감은 셋이다(틀은 이슬 `IsulAingFinish` 와 같다 — 라벨 · 장식이 없을 뿐):
//
//  ① 디퓨즈 합성 — 무지개 · 케이크 · 이슬과 **같다**(`isGoldSkin(원본) ? aing_rainbow-shade.png : 원본`, 무지개 캐시 `RainbowAingFinish.rainbowDiffuse`).
//     몸 셰이더가 '표본한 디퓨즈'에서 피부 비율 β 를 읽으므로 깜빡임 · 졸기 · 울트라 교체로 디퓨즈가 바뀌어도 네온 몸이 따라온다.
//  ② 몸 셰이더 — `HwooBody.shaderModifiers`(geometry + fragment) + 셰이더 인자 `ckShadeMap`(= aing_rainbow-shade.png). 몸 색 = 짙은 남색
//     (`HwooAingArt.bodyColor`) + 시선 따라 도는 네온 테(왼쪽 하늘색 → 오른쪽 분홍, 물체 x 로 섞음) + 좁은 반짝. 얼굴 상자 안은 β 로 원본
//     (눈 · 입 · 볼터치)을 지킨다 — 이슬 `IsulBody.bodyOutput` 과 같은 sRGB 섞기. 전부 물체 좌표(메시 UV 섬 점 함정이 없다).
//  ③ 표식 — 캐릭터 노드에 빈 노드 `markerName`(엔진 `currentCharacterID` 가 아잉 · 무지개 · 이슬과 가른다 — 같은 메시라 종류로 못 가른다).
//
// 시안: `~/.claude/projects/-Users-yesung-check/aing-hwoo-ruby/r1/parts-r5.swift.txt` 의 `uNeon()`(시안 렌더러는 선형 섞기 · 이 파일은 이슬과
// 같은 sRGB 섞기 — 얼굴 테가 짙게 잘리지 않게).
enum HwooAingFinish {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// "이 캐릭터 노드는 흑우다"의 표식 노드 이름(지오메트리 없는 빈 노드 — 몸 크기 계산에 안 낀다). 엔진의 `currentCharacterID` 가 읽는다.
    static let markerName = "check.hwooAing"

    /// 흑우 몸 셰이더. 틀(β 얼굴 지키기 · 타원체 법선 · geometry 단계 시선)은 이슬 `IsulAingFinish.IsulBody` 와 같다.
    enum HwooBody {
        static let bodyTop = 0.848950
        static let bodyHeight = 1.695736
        static let ellipsoid = SIMD3<Double>(0.6084, 0.7191, 0.5329)
        static let skinYRef = 0.56530
        static let blushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
        static let shadeMapKey = "ckShadeMap"

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

        /// 네온 몸: 짙은 남색 바탕 + 시선 따라 도는 테(왼쪽 하늘색 → 오른쪽 분홍) + 좁은 반짝(얼굴 위에서는 약하게).
        static let pattern = """
        ckBase = \(f5hex(HwooAingArt.bodyColor));
        ckShadeMix = 0.9;
        float ckRim = pow(1.0 - ckNV, \(f5(HwooAingArt.rimPower)));
        float ckSide = smoothstep(-0.4, 0.4, ckP.x);
        float3 ckNeon = mix(\(f5hex(HwooAingArt.neonLeft)), \(f5hex(HwooAingArt.neonRight)), ckSide);
        ckAdd += ckNeon * ckRim * \(f5(HwooAingArt.rimStrength));
        float3 ckL = normalize(float3(-0.38, 0.55, 0.74));
        ckAdd += float3(0.9, 0.95, 1.0) * pow(max(dot(ckVn, ckL), 0.0), 100.0) * 0.6 * (1.0 - 0.85 * ckFace);
        """

        /// 몸 출력 — 이슬 `IsulBody.bodyOutput` 과 같은 식(얼굴 상자 안은 β 로 원본을 지킨다 · sRGB 0–255 공간에서 섞는다).
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

        /// fragment 수정자 — 이슬 `IsulBody.fragment(output:)` 에서 라벨 인자만 뺐다(디퓨즈 P · 피부 S · 피부 비율 β · 물체 좌표 값들 → 무늬 → 출력).
        static let fragment = """
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
        float ckFx = ckP.x / 0.60;
        float ckFy = (ckP.y - 0.34) / 0.30;
        float ckFace = (1.0 - smoothstep(0.85, 1.15, ckFx * ckFx + ckFy * ckFy)) * smoothstep(0.05, 0.25, ckP.z);
        float3 ckBase = float3(1.0);
        float3 ckAdd = float3(0.0);
        float ckShadeMix = 1.0;
        \(pattern)
        \(bodyOutput)
        """

        static let shaderModifiers: [SCNShaderModifierEntryPoint: String] = [.geometry: geometry, .fragment: fragment]
    }

    // MARK: - 번들 자원 · 그릴 수 있다

    static func resourceURL(_ name: String) -> URL? {
        CheckResources.bundle.url(forResource: name, withExtension: HwooAingArt.resourceExtension)
    }

    /// 초상 URL(표정별).
    static func portraitURL(for mood: CheckMascotAssets.Mood) -> URL? {
        resourceURL(mood == .neutral ? HwooAingArt.neutralPortraitResourceName : HwooAingArt.negativePortraitResourceName)
    }

    /// 이 빌드가 흑우를 그릴 수 있는가(맥 = 초상 두 장 + 무지개와 같이 쓰는 밝기 맵). 상점 능력 번호 7 의 재료.
    static func isDrawable(fileManager: FileManager = .default) -> Bool {
        HwooAingArt.isDrawable(on: .mac) { name in
            guard let url = resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: - 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 흑우 마감을 입힌다: 얼굴 디퓨즈를 밝기 맵으로 합성하고(무지개와 같은 그림 · 같은 캐시), 그 재질에 몸 셰이더를 걸고
    /// 셰이더 인자(ckShadeMap)를 묶고, 표식을 단다. **unlit 정규화 뒤 · 감은 눈 노드 앞에** 불러야 한다(무지개 · 이슬과 같은 순서).
    /// 그림 · 메시가 없으면 아무것도 바꾸지 않고 false(보라 아잉이 그대로 선다 — 그 빌드는 능력 번호 7 을 보내지 않는다).
    @discardableResult
    static func apply(to character: SCNNode) -> Bool {
        guard let shade = RainbowAingFinish.shadeImage() else {
            logger.error("hwoo finish: 밝기 맵이 없다 — 보라 아잉으로 선다")
            return false
        }
        var faces: [(material: SCNMaterial, composite: CGImage)] = []
        character.enumerateHierarchy { node, _ in
            guard !AingDecor.isDecor(node) else { return }
            for material in node.geometry?.materials ?? [] {
                guard let contents = material.diffuse.contents,
                      CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { continue }
                let face = contents as! CGImage
                guard face.width >= 256, let composite = RainbowAingFinish.rainbowDiffuse(for: face) else { continue }
                faces.append((material, composite))
            }
        }
        guard !faces.isEmpty else {
            logger.error("hwoo finish: 얼굴 재질을 못 찾았다 — 보라 아잉으로 선다")
            return false
        }
        for face in faces {
            face.material.diffuse.contents = face.composite
            face.material.shaderModifiers = HwooBody.shaderModifiers
            face.material.setValue(SCNMaterialProperty(contents: shade), forKey: HwooBody.shadeMapKey)
        }
        let marker = SCNNode()
        marker.name = markerName
        character.addChildNode(marker)
        return true
    }

    /// 이 캐릭터 노드가 흑우인가(표식).
    static func isHwoo(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: markerName, recursively: false) != nil
    }
}
