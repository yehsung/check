import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 루비 아잉이 3D 마감 (v0.3.78 — 상점 루비 1000, 시안 7차 Y5 '배 띠 · 6:4')
//
// 루비 아잉이는 **몸 모양이 바뀌는 첫 캐릭터**다(다른 아잉이는 같은 메시에 색 · 장식만 바꾼다). 마감은 넷이다:
//
//  ① 몸 빚기 — 메시(aing.scn)의 정점 자리는 그대로 두고, 정점마다 '옮길 거리 · 모서리 거리 · 팔 무게 · 면 해시'를 구워(`RubyAingShape.bake`)
//     텍스처 좌표 칸 1 · 2 · 3 에 싣는다. 몸 셰이더의 geometry 단계가 그만큼 옮긴다. CPU 쪽 메시는 원래 아잉이라 감은 눈 UV 마스크 · 카메라 구도 ·
//     클릭 판정이 그대로 돈다. 굽기는 메시마다 한 번(정점 수로 캐시 — 울트라 교체 때 다시 굽지 않는다).
//  ② 디퓨즈 합성 — 무지개 · 케이크 · 이슬 · 흑우와 **같다**(`RainbowAingFinish.rainbowDiffuse`). 몸 셰이더가 표본한 디퓨즈에서 피부 비율 β 를
//     읽으므로 깜빡임 · 졸기 · 울트라 교체로 디퓨즈가 바뀌어도 보석 몸이 따라온다.
//  ③ 몸 셰이더 — `RubyAingShader`(geometry + fragment) + 셰이더 인자 `ckShadeMap`. 면마다 평평한 분홍 보석 · 흰 모서리 선. 얼굴 상자 안은 β 로
//     원본(눈 · 입 · 볼터치)을 지킨다(흑우와 같은 sRGB 섞기).
//  ④ 표식 — 캐릭터 노드에 빈 노드 `markerName`(엔진 `currentCharacterID` 가 가른다 — 같은 메시라 종류로 못 가른다). 감은 눈 선 판은
//     `closedEyeOffset` 만큼 옮겨 단다(`CheckCharacter3DScene.addClosedEyeNodes`).
enum RubyAingFinish {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// "이 캐릭터 노드는 루비 아잉이다"의 표식 노드 이름(지오메트리 없는 빈 노드 — 몸 크기 계산에 안 낀다).
    static let markerName = "check.rubyAing"

    static let shaderModifiers: [SCNShaderModifierEntryPoint: String] = [
        .geometry: RubyAingShader.geometry, .fragment: RubyAingShader.fragment(),
    ]

    // MARK: - 번들 자원 · 그릴 수 있다

    static func resourceURL(_ name: String) -> URL? {
        CheckResources.bundle.url(forResource: name, withExtension: RubyAingArt.resourceExtension)
    }

    /// 초상 URL(표정별).
    static func portraitURL(for mood: CheckMascotAssets.Mood) -> URL? {
        resourceURL(mood == .neutral ? RubyAingArt.neutralPortraitResourceName : RubyAingArt.negativePortraitResourceName)
    }

    /// 이 빌드가 루비 아잉이를 그릴 수 있는가(맥 = 초상 두 장 + 무지개와 같이 쓰는 밝기 맵). 상점 능력 번호 8 의 재료.
    static func isDrawable(fileManager: FileManager = .default) -> Bool {
        RubyAingArt.isDrawable(on: .mac) { name in
            guard let url = resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: - 몸 빚기(굽기 캐시)

    struct Prepared {
        let baked: RubyAingShape.Baked
        let body: RubyAingShape.BodyProfile
    }

    /// 굽기 캐시(정점 수 → 값). 씬 짓기는 메인에서 돌지만 굽기 자체는 순수 계산이라 잠금으로만 지킨다.
    nonisolated(unsafe) private static var cache: [Int: Prepared] = [:]
    private static let cacheLock = NSLock()

    /// 정점 자리(물체 좌표). float3 가 아니면 nil.
    static func positions(of geometry: SCNGeometry) -> [SIMD3<Float>]? {
        guard let src = geometry.sources(for: .vertex).first, src.usesFloatComponents, src.bytesPerComponent == 4,
              src.componentsPerVector >= 3 else { return nil }
        var out = [SIMD3<Float>](repeating: .zero, count: src.vectorCount)
        src.data.withUnsafeBytes { raw in
            for i in 0..<src.vectorCount {
                let b = src.dataOffset + i * src.dataStride
                out[i] = SIMD3(raw.loadUnaligned(fromByteOffset: b, as: Float.self),
                               raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                               raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self))
            }
        }
        return out
    }

    /// 이 메시의 굽기(정점 수로 캐시 — 같은 aing.scn 이면 한 번만 굽는다).
    static func prepared(for geometry: SCNGeometry) -> Prepared? {
        guard let pos = positions(of: geometry), !pos.isEmpty else { return nil }
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let hit = cache[pos.count] { return hit }
        let made = Prepared(baked: RubyAingShape.bake(pos), body: RubyAingShape.BodyProfile(positions: pos))
        cache[pos.count] = made
        return made
    }

    /// 원래 정점 · 원래 UV(칸 0)는 그대로, 구운 값을 칸 1 · 2 · 3 에 더한 새 지오메트리(재질 · 요소는 그대로).
    static func geometry(_ g: SCNGeometry, adding baked: RubyAingShape.Baked) -> SCNGeometry? {
        guard let vertex = g.sources(for: .vertex).first, let uv = g.sources(for: .texcoord).first,
              vertex.vectorCount == baked.count, uv.vectorCount == baked.count else { return nil }
        let n = baked.count
        func source(_ pairs: [Float]) -> SCNGeometrySource {
            let data = pairs.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: data, semantic: .texcoord, vectorCount: n, usesFloatComponents: true,
                                     componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        }
        var c1 = [Float](repeating: 0, count: n * 2), c2 = c1, c3 = c1
        for i in 0..<n {
            let d = baked.displacement[i]
            c1[i * 2] = d.x; c1[i * 2 + 1] = d.y
            c2[i * 2] = d.z; c2[i * 2 + 1] = baked.edge[i]
            c3[i * 2] = baked.arm[i]; c3[i * 2 + 1] = baked.facet[i]
        }
        let others = g.sources.filter { $0.semantic != .vertex && $0.semantic != .texcoord }
        let made = SCNGeometry(sources: [vertex, uv, source(c1), source(c2), source(c3)] + others, elements: g.elements)
        made.materials = g.materials
        made.name = g.name
        return made
    }

    // MARK: - 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 루비 마감을 입힌다: 몸 지오메트리에 구운 값을 싣고, 얼굴 디퓨즈를 밝기 맵으로 합성하고(무지개와 같은 그림 · 같은 캐시),
    /// 그 재질에 몸 셰이더를 걸고 셰이더 인자(ckShadeMap)를 묶고, 표식을 단다. **unlit 정규화 뒤 · 감은 눈 노드 앞에** 불러야 한다(흑우와 같은 순서).
    /// 그림 · 메시가 없으면 아무것도 바꾸지 않고 false(보라 아잉이 그대로 선다 — 그 빌드는 능력 번호 8 을 보내지 않는다).
    @discardableResult
    static func apply(to character: SCNNode) -> Bool {
        guard let shade = RainbowAingFinish.shadeImage() else {
            logger.error("ruby finish: 밝기 맵이 없다 — 보라 아잉으로 선다")
            return false
        }
        var targets: [(node: SCNNode, material: SCNMaterial, composite: CGImage)] = []
        character.enumerateHierarchy { node, _ in
            guard !AingDecor.isDecor(node) else { return }
            for material in node.geometry?.materials ?? [] {
                guard let contents = material.diffuse.contents,
                      CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { continue }
                let face = contents as! CGImage
                guard face.width >= 256, let composite = RainbowAingFinish.rainbowDiffuse(for: face) else { continue }
                targets.append((node, material, composite))
            }
        }
        guard !targets.isEmpty else {
            logger.error("ruby finish: 얼굴 재질을 못 찾았다 — 보라 아잉으로 선다")
            return false
        }
        // 몸 빚기를 먼저 확인한다 — 굽기를 못 실으면 셰이더가 0 칸을 읽어 '보석 색의 원래 몸'이 되므로, 그 경우엔 아무것도 안 바꾼다.
        var rebuilt: [ObjectIdentifier: SCNGeometry] = [:]
        for target in targets where rebuilt[ObjectIdentifier(target.node)] == nil {
            guard let g = target.node.geometry, let prep = prepared(for: g), let made = geometry(g, adding: prep.baked) else {
                logger.error("ruby finish: 몸을 빚지 못했다(정점 형식) — 보라 아잉으로 선다")
                return false
            }
            rebuilt[ObjectIdentifier(target.node)] = made
        }
        for target in targets {
            if let made = rebuilt[ObjectIdentifier(target.node)], target.node.geometry !== made { target.node.geometry = made }
            target.material.diffuse.contents = target.composite
            target.material.shaderModifiers = shaderModifiers
            target.material.setValue(SCNMaterialProperty(contents: shade), forKey: RubyAingShader.shadeMapKey)
        }
        let marker = SCNNode()
        marker.name = markerName
        character.addChildNode(marker)
        return true
    }

    // MARK: - 감은 눈(깜빡임 · 졸기)

    /// 루비 감은 눈 텍스처: 무지개 갈래와 같이 굽고(라벤더 원본에서 감은 눈 → 밝기 맵 합성), **덮인 눈 자리(메시 UV 마스크 + 둘레 3 텍셀)를
    /// 밝기 맵 피부로 다시 채운다** — 볼터치 텍셀은 남긴다. 라벤더 몸에선 안 보이던 덮개 둘레의 옛 눈 결(둥근 테 · 하이라이트 조각)이 분홍 보석
    /// 위에서는 드러났다(대표 지적 11-07 · 총괄 #dl_T4VqXHzWytaF). 결과는 (얼굴 이미지 · 지오메트리)마다 한 번 굽는다.
    static func closedEyesImage(faceImage: CGImage, geometry: SCNGeometry?) -> CGImage? {
        closedLock.lock(); defer { closedLock.unlock() }
        if let hit = closedCache, hit.face === faceImage, hit.geometry === geometry { return hit.image }
        guard let original = RainbowAingFinish.lavenderOriginal(ofRainbowFace: faceImage),
              let base = RainbowAingFinish.closedEyesImage(rainbowFace: faceImage, original: original, lavenderClosedEyes: { lavender in
                  CheckCharacter3DScene.lavenderClosedEyesImage(faceImage: lavender, geometry: geometry)
              }) else { return nil }
        let made = cleanedClosedEyes(base, geometry: geometry) ?? base
        closedCache = (faceImage, geometry, made)
        return made
    }

    nonisolated(unsafe) private static var closedCache: (face: CGImage, geometry: SCNGeometry?, image: CGImage)?
    private static let closedLock = NSLock()

    /// 덮인 눈 자리(+ 둘레 `grow` 텍셀)를 밝기 맵 텍셀로 바꾼다 — 볼터치(밝기 맵 → 볼터치 색 선 위의 텍셀, 몸 셰이더 β 판정과 같은 식)는 남긴다.
    /// 마스크를 못 구하면 nil(원래 감은 눈 그대로 쓴다).
    static func cleanedClosedEyes(_ closed: CGImage, geometry: SCNGeometry?, grow: Int = 3) -> CGImage? {
        guard let geometry, let shade = RainbowAingFinish.shadeImage() else { return nil }
        let w = closed.width, h = closed.height
        guard let mask = SleepEyeTexture.eyeUVCoverMask(geometry: geometry, anchors: CheckCharacter3DScene.closedEyeAnchors.map { $0.position },
                                                       width: w, height: h, radius: CheckCharacter3DScene.eyeCoverRadius),
              var px = GoldAingFinish.rgbaBytes(closed), let skin = GoldAingFinish.rgbaBytes(shade, width: w, height: h) else { return nil }
        var grown = mask
        for y in 0..<h { for x in 0..<w where mask[y * w + x] {
            for dy in -grow...grow { for dx in -grow...grow {
                let xx = x + dx, yy = y + dy
                if xx >= 0, yy >= 0, xx < w, yy < h { grown[yy * w + xx] = true }
            } }
        } }
        let blush = RubyAingShader.blushSRGB
        for i in 0..<(w * h) where grown[i] {
            let p = SIMD3(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2]))
            let s = SIMD3(Double(skin[i * 4]), Double(skin[i * 4 + 1]), Double(skin[i * 4 + 2]))
            let dv = p - s, ks = blush - s
            let ak = simd_dot(dv, ks) / max(1e-6, simd_dot(ks, ks))
            let res = simd_length(dv - min(max(ak, 0), 1) * ks)
            if res <= 20 && ak > 0.08 { continue }   // 볼터치
            px[i * 4] = skin[i * 4]; px[i * 4 + 1] = skin[i * 4 + 1]; px[i * 4 + 2] = skin[i * 4 + 2]; px[i * 4 + 3] = 255
        }
        return GoldAingFinish.makeImage(px, width: w, height: h)
    }

    /// 이 캐릭터 노드가 루비 아잉이인가(표식).
    static func isRuby(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: markerName, recursively: false) != nil
    }

    /// 감은 눈 선 판을 옮길 거리 — 몸 셰이더가 그 눈 자리를 옮긴 만큼(루비가 아니거나 굽기가 없으면 0).
    static func closedEyeOffset(for character: SCNNode, anchor: SCNVector3) -> SCNVector3 {
        guard isRuby(character) else { return SCNVector3Zero }
        cacheLock.lock(); let body = cache.values.first?.body; cacheLock.unlock()
        guard let body else { return SCNVector3Zero }
        let d = RubyAingShape.displacement(at: SIMD3(Float(anchor.x), Float(anchor.y), Float(anchor.z)), body: body)
        return SCNVector3(CGFloat(d.x), CGFloat(d.y), CGFloat(d.z))
    }
}
