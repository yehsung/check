import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 무지개 아잉이 3D 마감 (v0.3.59)
//
// 무지개 아잉이는 아잉과 **같은 메시**(aing.scn)다. 앱의 3D 경로는 전부 unlit(.constant)이다. 마감은 세 가지다:
//
//  ① 디퓨즈 합성 — 텍셀마다 `isGoldSkin(원본) ? 밝기 맵 : 원본`(금과 **같은 함수** `GoldAingFinish.composite`). 밝기 맵
//     (`aing_rainbow-shade.png`, 아트 스크립트가 구움)은 **라벤더 그대로** 밝기만 다듬은 것이다 — 눈·볼·입 둘레의 어두운 테와 1–2텍셀 밝은
//     티끌을 걷어 시안 E 의 밝기 장과 같게 했다. 합성 결과도 라벤더라 감은 눈 파이프라인(라벤더 피부 분류)이 그대로 돈다.
//  ② 몸 셰이더(`shaderModifiers`) — 지금 표본한 디퓨즈가 라벤더 피부(isGoldSkin 식)면 그 조각의 색을 **물체 좌표 높이**로 정한
//     파스텔 무지개(A 공식, 상수는 `RainbowAingArt`)로 바꾸고, 밝기는 그 표본의 OKLab L 에서 옮긴다. 아니면(눈·볼·입) 디퓨즈 그대로.
//     ★ 색을 텍스처에 굽지 않는 이유: aing.scn 의 삼각형 60개가 다른 UV 섬 텍셀을 같이 써서, 높이로 색을 구운 맵은 그 자리에 엉뚱한 띠 색
//       1–3px 점을 만든다(시안 speck-compare.png). 셰이더는 조각마다 자기 좌표로 색을 정해 그 점이 없다.
//     ★ 마스크를 **디퓨즈 표본**에서 읽는 이유: 깜빡임 · 졸기(엔진이 디퓨즈를 감은 눈 판으로 바꾼다) · 울트라 교체로 디퓨즈가 바뀌어도
//       마스크가 저절로 따라온다 — 따로 맞춰 바꿀 데이터 텍스처가 없다. 시간에 기대지 않는다(정적 — 흐르는 애니메이션 없음).
//  ③ 후광 판 — 금과 같은 판 36장 · 같은 칸 고르기 · 같은 창 합성 보정(`GoldAingFinish.makeHaloNode(name:cells:…)`), 그림만 무지개다.
//     표식 노드 이름(`haloNodeName`)이 "이 캐릭터는 무지개 아잉이다"의 표시고, 재질 이름 · 카테고리 비트는 금과 같아 엔진의 얼굴 탐색과
//     몸 클릭 hitTest 가 그대로 건너뛴다(후광은 몸 크기 계산 · 클릭 판정에서 빠진다).
enum RainbowAingFinish {
    /// 후광 표식 노드 이름. 이 이름의 노드가 캐릭터 아래에 있으면 **그 캐릭터는 무지개 아잉이다**(엔진의 `currentCharacterID` 판정).
    static let haloNodeName = "check.rainbowHalo"

    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    // MARK: 몸 셰이더

    /// 몸 재질에 거는 셰이더 수정자. geometry 가 물체 좌표를 넘기고(varyings), fragment 가 디퓨즈 표본을 보고 색을 정한다.
    /// 글은 `RainbowAingArt` 의 상수로 만든다(기준 구현 `RainbowAingArt.bodyColorLinear` 와 같은 식 — 시험이 GPU 결과와 맞댄다).
    static let shaderModifiers: [SCNShaderModifierEntryPoint: String] = [
        .geometry: geometryShader,
        .fragment: fragmentShader,
    ]

    static let geometryShader = """
    #pragma varyings
    float3 rbP;
    #pragma body
    out.rbP = _geometry.position.xyz;
    """

    static let fragmentShader: String = {
        func f(_ v: Double) -> String { String(format: "%.6f", v) }
        func list(_ xs: [Double]) -> String { xs.map(f).joined(separator: ", ") }
        let art = RainbowAingArt.self
        let windows = art.shadowWindows.map { w in
            """
                    { float d = fmod(fmod(rbHs - \(f(w.centre)), 360.0) + 360.0, 360.0); d = min(d, 360.0 - d);
                      float hw = 1.0 - smoothstep(\(f(w.inner)), \(f(w.outer)), d);
                      rbHw = max(rbHw, hw); rbLift = max(rbLift, hw * \(f(w.lift))); }
            """
        }.joined(separator: "\n")
        return """
        #pragma varyings
        float3 rbP;
        #pragma body
        // 디퓨즈 표본(선형) → sRGB 부호 → isGoldSkin(색상 215–300° · 채도 0.05–0.75 · 루마 > 0.10) — GoldAingFinish.isGoldSkin 과 같은 식.
        float3 rbLin = clamp(_surface.diffuse.rgb, float3(0.0), float3(1.0));
        float3 rbE = select(1.055 * pow(rbLin, float3(1.0 / 2.4)) - 0.055, rbLin * 12.92, rbLin <= float3(0.0031308));
        float rbMx = max(rbE.r, max(rbE.g, rbE.b));
        float rbMn = min(rbE.r, min(rbE.g, rbE.b));
        float rbSat = rbMx > 0.0 ? (rbMx - rbMn) / rbMx : 0.0;
        float rbHueDeg = 0.0;
        if (rbMx > rbMn) {
            float rbSpan = rbMx - rbMn;
            if (rbMx == rbE.r) { rbHueDeg = 60.0 * ((rbE.g - rbE.b) / rbSpan); }
            else if (rbMx == rbE.g) { rbHueDeg = 60.0 * ((rbE.b - rbE.r) / rbSpan + 2.0); }
            else { rbHueDeg = 60.0 * ((rbE.r - rbE.g) / rbSpan + 4.0); }
            if (rbHueDeg < 0.0) { rbHueDeg += 360.0; }
        }
        float rbLuma = 0.299 * rbE.r + 0.587 * rbE.g + 0.114 * rbE.b;
        if (rbHueDeg >= 215.0 && rbHueDeg <= 300.0 && rbSat > 0.05 && rbSat < 0.75 && rbLuma > 0.10) {
            // 밝기 차 dL = OKLab L(표본) − 기준.
            float rbL1 = pow(max(0.4122214708 * rbLin.r + 0.5363325363 * rbLin.g + 0.0514459929 * rbLin.b, 0.0), 1.0 / 3.0);
            float rbM1 = pow(max(0.2119034982 * rbLin.r + 0.6806995451 * rbLin.g + 0.1073969566 * rbLin.b, 0.0), 1.0 / 3.0);
            float rbS1 = pow(max(0.0883024619 * rbLin.r + 0.2817188376 * rbLin.g + 0.6299787005 * rbLin.b, 0.0), 1.0 / 3.0);
            float rbDL = 0.2104542553 * rbL1 + 0.7936177850 * rbM1 - 0.0040720468 * rbS1 - \(f(art.lightnessReference));
            const float rbStopL[7] = { \(list(art.stopLightness)) };
            const float rbStopC[7] = { \(list(art.stopChroma)) };
            const float rbStopH[7] = { \(list(art.stopHue)) };
            // 높이 t: 정수리 0 → 바닥 1(물체 좌표 — 노드 변환 · 부유 · 회전과 무관하게 몸에 붙는다).
            float rbT = (\(f(art.bodyTop)) - in.rbP.y) / \(f(art.bodyHeight));
            float rbS = clamp(7.0 * rbT - 0.5, 0.0, 6.0);
            int rbK = min(int(floor(rbS)), 5);
            float rbF = rbS - float(rbK);
            float rbLs = mix(rbStopL[rbK], rbStopL[rbK + 1], rbF);
            float rbCs = mix(rbStopC[rbK], rbStopC[rbK + 1], rbF);
            float rbHs = mix(rbStopH[rbK], rbStopH[rbK + 1], rbF);
            float rbKc = clamp(1.0 - \(f(art.chromaSlope)) * rbDL, \(f(art.chromaFloor)), \(f(art.chromaCeil)));
            float rbDLs = rbDL;
            if (rbDL < 0.0) {
                float rbHw = 0.0, rbLift = 0.0;
        \(windows)
                rbKc -= (rbKc - min(rbKc, 1.0)) * rbHw * smoothstep(0.0, 0.06, -rbDL);
                rbDLs = rbDL * (1.0 - rbLift);
            }
            float rbLL = clamp(rbLs + rbDLs, \(f(art.lightnessMin)), \(f(art.lightnessMax)));
            float rbCC = rbCs * rbKc;
            float rbHue = rbHs * 0.017453292519943295;
            float rbCa = cos(rbHue), rbSa = sin(rbHue);
            // 색역(선형 바닥 · 천장) 밖이면 L·h 를 두고 C 만 이분해 줄인다(첫 판정 + 12회).
            float rbLo = 0.0, rbHi = 1.0, rbScale = 1.0;
            for (int it = 0; it < 13; it++) {
                float rbM = (it == 0) ? 1.0 : 0.5 * (rbLo + rbHi);
                float rbA = rbCC * rbM * rbCa, rbB = rbCC * rbM * rbSa;
                float rl = rbLL + 0.3963377774 * rbA + 0.2158037573 * rbB;
                float rm = rbLL - 0.1055613458 * rbA - 0.0638541728 * rbB;
                float rs = rbLL - 0.0894841775 * rbA - 1.2914855480 * rbB;
                rl = rl * rl * rl; rm = rm * rm * rm; rs = rs * rs * rs;
                float3 rc = float3(4.0767416621 * rl - 3.3077115913 * rm + 0.2309699292 * rs,
                                   -1.2684380046 * rl + 2.6097574011 * rm - 0.3413193965 * rs,
                                   -0.0041960863 * rl - 0.7034186147 * rm + 1.7076147010 * rs);
                bool ok = all(rc >= float3(\(f(art.gamutFloor)))) && all(rc <= float3(\(f(art.gamutCeil))));
                if (it == 0) { if (ok) { break; } rbScale = 0.0; continue; }
                if (ok) { rbLo = rbM; } else { rbHi = rbM; }
                rbScale = rbLo;
            }
            float rbA2 = rbCC * rbScale * rbCa, rbB2 = rbCC * rbScale * rbSa;
            float l3 = rbLL + 0.3963377774 * rbA2 + 0.2158037573 * rbB2;
            float m3 = rbLL - 0.1055613458 * rbA2 - 0.0638541728 * rbB2;
            float s3 = rbLL - 0.0894841775 * rbA2 - 1.2914855480 * rbB2;
            l3 = l3 * l3 * l3; m3 = m3 * m3 * m3; s3 = s3 * s3 * s3;
            float3 rbRGB = clamp(float3(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
                                        -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
                                        -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3), 0.0, 1.0);
            _output.color.rgb = rbRGB * _output.color.a;
        }
        """
    }()

    // MARK: 번들 자원

    static func resourceURL(_ name: String) -> URL? {
        CheckResources.bundle.url(forResource: name, withExtension: RainbowAingArt.resourceExtension)
    }

    /// 초상 URL(표정별).
    static func portraitURL(for mood: CheckMascotAssets.Mood) -> URL? {
        resourceURL(mood == .neutral ? RainbowAingArt.neutralPortraitResourceName : RainbowAingArt.negativePortraitResourceName)
    }

    /// 이 빌드가 무지개 아잉이를 그릴 수 있는가(맥 = 초상 두 장 + 밝기 맵 + 후광). 상점 능력 번호 3 의 재료.
    static func isDrawable(fileManager: FileManager = .default) -> Bool {
        RainbowAingArt.isDrawable(on: .mac) { name in
            guard let url = resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: 캐시(프로세스당 한 번)

    private struct Cache {
        var shade: CGImage??
        /// 후광 각도 칸 36장(창 합성 보정 끝). 빠진 칸은 정면으로 채운다. 정면이 없으면 nil.
        var haloCells: [CGImage]??
        /// 마지막으로 합성한 (라벤더 원본, 무지개 디퓨즈). 같은 메시 · 같은 텍스처라 한 벌이면 된다.
        var rainbow: (original: CGImage, rainbow: CGImage)?
        /// 위 무지개 디퓨즈의 감은 눈 판.
        var rainbowSleep: CGImage?
    }

    private final class Locked: @unchecked Sendable {
        private let lock = NSLock()
        private var state = Cache()
        func withLock<R>(_ body: (inout Cache) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }
    }

    private static let cache = Locked()

    private static func decode(_ name: String) -> CGImage? {
        guard let url = resourceURL(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func shadeImage() -> CGImage? {
        if let hit = cache.withLock({ $0.shade }) { return hit }
        let made = decode(RainbowAingArt.shadeResourceName)
        cache.withLock { $0.shade = .some(made) }
        return made
    }

    /// 후광 각도 칸 36장(0 칸 = 정면 512², 나머지 160²) — 금과 같은 창 합성 보정 · 같은 접기 규칙(캐시).
    static func haloCellImages() -> [CGImage]? {
        if let hit = cache.withLock({ $0.haloCells }) { return hit }
        let made = GoldAingFinish.compensatedHaloCells(names: RainbowAingArt.haloCellResourceNames, label: "rainbow", decode: decode)
        cache.withLock { $0.haloCells = .some(made) }
        return made
    }

    /// 라벤더 원본 → 무지개 디퓨즈(밝기 맵 합성, 캐시). 처음 한 번만 굽고 그 뒤로는 **같은 객체**를 돌려준다 — 엔진이 이 객체로
    /// "이 얼굴은 무지개다"를 알아본다(`lavenderOriginal(ofRainbowFace:)`). 원본 크기가 바뀌면 다시 굽는다.
    static func rainbowDiffuse(for original: CGImage) -> CGImage? {
        if let hit = cache.withLock({ state -> CGImage? in
            guard let made = state.rainbow, made.rainbow.width == original.width, made.rainbow.height == original.height else { return nil }
            return made.rainbow
        }) {
            return hit
        }
        guard let shade = shadeImage(), let rainbow = GoldAingFinish.compositeImage(original: original, skin: shade) else { return nil }
        return cache.withLock { state -> CGImage in
            if let existing = state.rainbow, existing.rainbow.width == rainbow.width, existing.rainbow.height == rainbow.height {
                return existing.rainbow
            }
            state.rainbow = (original, rainbow)
            state.rainbowSleep = nil
            return rainbow
        }
    }

    /// 이 얼굴 디퓨즈가 우리가 구운 무지개 디퓨즈면 그 라벤더 원본(감은 눈을 굽는 재료), 아니면 nil.
    static func lavenderOriginal(ofRainbowFace face: CGImage) -> CGImage? {
        cache.withLock { state in
            guard let made = state.rainbow, made.rainbow === face else { return nil }
            return made.original
        }
    }

    /// 무지개 얼굴의 감은 눈 판 — **라벤더 원본으로 감은 눈을 굽고** 같은 합성을 한다(금과 같은 순서, 캐시). 그래서 덮인 눈 자리도
    /// 밝기 맵의 매끈한 밝기(메시 표면으로 번진 값)를 받아 셰이더가 둘레와 이어진 무지개로 칠한다.
    static func closedEyesImage(
        rainbowFace: CGImage,
        original: CGImage,
        lavenderClosedEyes: (CGImage) -> CGImage?
    ) -> CGImage? {
        if let hit = cache.withLock({ state -> CGImage? in
            guard let made = state.rainbow, made.rainbow === rainbowFace else { return nil }
            return state.rainbowSleep
        }) {
            return hit
        }
        guard let shade = shadeImage(),
              let lavenderClosed = lavenderClosedEyes(original),
              let closed = GoldAingFinish.compositeImage(original: lavenderClosed, skin: shade) else { return nil }
        cache.withLock { state in
            if let made = state.rainbow, made.rainbow === rainbowFace { state.rainbowSleep = closed }
        }
        return closed
    }

    /// 테스트 전용: 캐시를 비운다.
    static func resetCacheForTesting() {
        cache.withLock { $0 = Cache() }
    }

    // MARK: 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 무지개 마감을 입힌다: 얼굴 디퓨즈를 밝기 맵으로 합성하고, 그 재질에 몸 셰이더를 걸고, 몸 뒤에 후광 판을 세운다.
    /// **unlit 정규화(`applyUnlitMaterials`) 뒤 · 감은 눈 노드 앞에** 불러야 한다(금과 같은 순서 — 얼굴 재질을 "큰 CGImage 디퓨즈"로 찾는다).
    /// 밝기 맵이 없으면 아무것도 바꾸지 않고 false(보라 아잉이 그대로 선다 — 그 빌드는 능력 번호 3 을 보내지 않는다).
    @discardableResult
    static func apply(to character: SCNNode) -> Bool {
        // 몸 크기는 **아무것도 붙이기 전에** 잰다(감은 눈 선 · 후광이 섞이지 않게).
        let body = character.boundingBox
        var faces: [SCNMaterial] = []
        character.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] {
                guard let contents = material.diffuse.contents,
                      CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { continue }
                let face = contents as! CGImage
                guard face.width >= 256, let rainbow = rainbowDiffuse(for: face) else { continue }
                material.diffuse.contents = rainbow
                faces.append(material)
            }
        }
        guard !faces.isEmpty else {
            logger.error("rainbow finish: 밝기 맵 합성 실패 — 보라 아잉으로 선다")
            return false
        }
        for material in faces {
            material.shaderModifiers = shaderModifiers
        }
        character.addChildNode(GoldAingFinish.makeHaloNode(name: haloNodeName, cells: haloCellImages(),
                                                          bodyMin: body.min, bodyMax: body.max))
        return true
    }

    /// 이 캐릭터 노드가 무지개 아잉이인가(후광 표식이 붙어 있다).
    static func isRainbow(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: haloNodeName, recursively: false) != nil
    }
}
