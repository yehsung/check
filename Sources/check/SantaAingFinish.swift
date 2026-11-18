import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 산타 아잉이 3D 마감 (크리스마스 기간 선물 · 시안 S3 '수염 산타' — 대표 #d_3VZdglOgRABx "산타아잉이는 그냥 주고")
//
// 원래 아잉 메시(aing.scn) · 원래 둥근 몸매 그대로다. 마감은 다섯이다(틀은 지역 아잉이 `RegionAingFinish` + 루비 아잉이의 정점 옮기기):
//  ① 팔 접기 — 정점 자리는 그대로 두고, 정점마다 '옮길 거리 · 접힘 표시'를 구워(`SantaAingShape.bake`) 텍스처 좌표 칸 1 · 2 에 싣는다. 몸 셰이더의
//     geometry 단계가 원래 지느러미 팔을 몸 겉면으로 접는다(둥근 팔은 ③ 장식). CPU 쪽 메시는 원래 아잉이라 감은 눈 UV 마스크 · 카메라 구도 ·
//     클릭 판정이 그대로 돈다. 굽기는 메시마다 한 번(정점 수로 캐시).
//  ② 디퓨즈 합성 — 무지개와 같다(`RainbowAingFinish.rainbowDiffuse`). 깜빡임 · 졸기 · 울트라로 디퓨즈가 바뀌어도 몸 셰이더가 따라온다.
//  ③ 몸 셰이더 — `SantaAingShader`(빨간 몸 · 살구빛 얼굴 · 흰 수염 · 흰 털 챙 · 검은 허리띠 · 아래 털 단 · 홍조 볼). 얼굴 상자 안은 β 로 원본(눈 · 입 ·
//     볼)을 지킨다. 출력은 시안 렌더러와 같은 선형 식이다.
//  ④ 장식 — 털 방울 · 콧수염 둘 · 코 · 장화 둘 · 둥근 팔 둘(소매 · 소맷부리 · 장갑)(`SantaAingDecor.decorNodeName` — `AingDecor.rootNames` 에 더함:
//     얼굴 탐색 · 클릭 · 상자 계산이 뺀다). 모양 · 색 · 굽기는 CheckCore `SantaAingDecor` · `SantaDecorBake` 한 곳(초상 생성기와 같은 조각 · 같은 텍스처).
//  ⑤ 표식 — 캐릭터 노드의 빈 노드 `markerName`(엔진 `currentCharacterID` 가 가른다 — 같은 메시라 종류로 못 가른다).
// ★ 프레이밍: 내려 세우지 않는다 — 털 방울 꼭대기(≈ 1.08)는 빼빼로 막대 끝(1.0951)보다 낮고, 장화 바닥(≈ −0.88)도 몸 상자 밑에 조금만 나온다.
// ★ 장식 굽기(텍스처 열넷)는 프로세스당 한 번이고 행을 나눠 여러 코어로 굽는다 — 원본을 한 번 만들고 씬마다 `clone()` 을 붙인다(지역 아잉이와 같은 길).
enum SantaAingFinish {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// "이 캐릭터 노드는 산타 아잉이다"의 표식 노드 이름(지오메트리 없는 빈 노드 — 몸 크기 계산에 안 낀다).
    static let markerName = "check.santaAing"
    static let decorNodeName = SantaAingDecor.decorNodeName

    static let shaderModifiers: [SCNShaderModifierEntryPoint: String] = [
        .geometry: SantaAingShader.geometry, .fragment: SantaAingShader.fragment(),
    ]

    // MARK: - 번들 자원 · 그릴 수 있다

    static func resourceURL(_ name: String) -> URL? {
        CheckResources.bundle.url(forResource: name, withExtension: SantaAingArt.resourceExtension)
    }

    static func portraitURL(for mood: CheckMascotAssets.Mood) -> URL? {
        resourceURL(mood == .neutral ? SantaAingArt.neutralPortraitResourceName : SantaAingArt.negativePortraitResourceName)
    }

    /// 이 빌드가 산타 아잉이를 그릴 수 있는가(맥 = 초상 두 장 + 밝기 맵). 지역 두 센터까지 서고 산타도 서야 능력 번호 11 이 나간다.
    static func isDrawable(fileManager: FileManager = .default) -> Bool {
        SantaAingArt.isDrawable(on: .mac) { name in
            guard let url = resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: - 팔 접기(굽기 캐시)

    /// 굽기 캐시(정점 수 → 값). 씬 짓기는 메인에서 돌지만 굽기 자체는 순수 계산이라 잠금으로만 지킨다.
    nonisolated(unsafe) private static var bakeCache: [Int: SantaAingShape.Baked] = [:]
    private static let bakeLock = NSLock()

    /// 이 메시의 팔 접기 굽기(정점 수로 캐시 — 같은 aing.scn 이면 한 번만 굽는다).
    static func baked(for geometry: SCNGeometry) -> SantaAingShape.Baked? {
        guard let pos = RubyAingFinish.positions(of: geometry), !pos.isEmpty else { return nil }
        bakeLock.lock(); defer { bakeLock.unlock() }
        if let hit = bakeCache[pos.count] { return hit }
        let made = SantaAingShape.bake(pos)
        bakeCache[pos.count] = made
        return made
    }

    /// 원래 정점 · 원래 UV(칸 0)는 그대로, 굽기를 칸 1(dx, dy) · 칸 2(dz, 접힘)에 더한 새 지오메트리(재질 · 요소는 그대로).
    static func geometry(_ g: SCNGeometry, adding baked: SantaAingShape.Baked) -> SCNGeometry? {
        guard let vertex = g.sources(for: .vertex).first, let uv = g.sources(for: .texcoord).first,
              vertex.vectorCount == baked.count, uv.vectorCount == baked.count else { return nil }
        let n = baked.count
        func source(_ pairs: [Float]) -> SCNGeometrySource {
            let data = pairs.withUnsafeBufferPointer { Data(buffer: $0) }
            return SCNGeometrySource(data: data, semantic: .texcoord, vectorCount: n, usesFloatComponents: true,
                                     componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 0, dataStride: 8)
        }
        var c1 = [Float](repeating: 0, count: n * 2), c2 = c1
        for i in 0..<n {
            let d = baked.displacement[i]
            c1[i * 2] = d.x; c1[i * 2 + 1] = d.y
            c2[i * 2] = d.z; c2[i * 2 + 1] = baked.fold[i]
        }
        let others = g.sources.filter { $0.semantic != .vertex && $0.semantic != .texcoord }
        let made = SCNGeometry(sources: [vertex, uv, source(c1), source(c2)] + others, elements: g.elements)
        made.materials = g.materials
        made.name = g.name
        return made
    }

    // MARK: - 장식

    /// 몸 윗면 (x, z) 의 겉 점과 바깥(위) 법선(물체 좌표).
    static func crownPoint(_ body: SCNNode, x: Float, z: Float) -> (SIMD3<Float>, SIMD3<Float>)? {
        let hits = body.hitTestWithSegment(from: SCNVector3(x, 3, z), to: SCNVector3(x, -3, z),
                                           options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let top = hits.max(by: { $0.localCoordinates.y < $1.localCoordinates.y }) else { return nil }
        let p = top.localCoordinates, n = top.localNormal
        var nn = simd_normalize(SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z)))
        if nn.y < 0 { nn = -nn }
        return (SIMD3(Float(p.x), Float(p.y), Float(p.z)), nn)
    }

    /// 조각 하나 → 노드(메시 + 몸 공간 고정 빛을 구운 텍스처 — CheckCore `SantaDecorBake` 한 곳).
    static func node(_ piece: SantaDecorPiece) -> SCNNode {
        let mesh = SantaDecorBake.mesh(piece)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }),
                                             SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }),
                                             SCNGeometrySource(textureCoordinates: mesh.uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })],
                                   elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)])
        var px = SantaDecorBake.texture(piece)
        let w = piece.texW, h = piece.texH
        let image = px.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.diffuse.wrapS = piece.closedU ? .repeat : .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = piece.name
        return node
    }

    private static let templateLock = NSLock()
    nonisolated(unsafe) private static var template: SCNNode?

    /// 산타 장식 원본(프로세스당 한 번 굽고 사본을 준다). 몸 메시 노드의 물체 좌표다. 자리를 못 재면 nil(장식 없이 선다).
    static func decorNode(body: SCNNode) -> SCNNode? {
        templateLock.lock(); defer { templateLock.unlock() }
        if let template { return template.clone() }
        let g = SantaAingDecor.mustacheGap, y = SantaAingDecor.mustacheY
        guard let crown = crownPoint(body, x: SantaAingDecor.crownX, z: SantaAingDecor.crownZ),
              let right = RegionAingFinish.frontPoint(body, x: g, y: y), let left = RegionAingFinish.frontPoint(body, x: -g, y: y),
              let nose = RegionAingFinish.frontPoint(body, x: 0, y: SantaAingDecor.noseY) else {
            logger.error("santa finish: 장식 자리를 못 쟀다 — 장식 없이 선다")
            return nil
        }
        let root = SCNNode()
        root.name = decorNodeName
        for piece in SantaAingDecor.pieces(crown: crown.0, crownNormal: crown.1, mustacheRoots: (right, left), noseRoot: nose) {
            root.addChildNode(node(piece))
        }
        if !Thread.isMainThread { SCNTransaction.flush() }
        template = root
        return root.clone()
    }

    // MARK: - 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 산타 마감을 입힌다: 팔 접기 굽기 · 디퓨즈 합성 · 몸 셰이더 · ckShadeMap · 장식 · 표식.
    /// **unlit 정규화 뒤 · 감은 눈 노드 앞에** 불러야 한다(지역 아잉이와 같은 순서). 그림 · 메시가 없으면 아무것도 안 바꾸고 false
    /// (보라 아잉이 그대로 선다 — 그 빌드는 능력 번호 11 을 보내지 않는다).
    @discardableResult
    static func apply(to character: SCNNode) -> Bool {
        guard let shade = RainbowAingFinish.shadeImage() else {
            logger.error("santa finish: 밝기 맵이 없다 — 보라 아잉으로 선다")
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
        guard let bodyNode = targets.first?.node else {
            logger.error("santa finish: 얼굴 재질을 못 찾았다 — 보라 아잉으로 선다")
            return false
        }
        // 팔 접기를 먼저 확인한다 — 굽기를 못 실으면 셰이더가 0 칸을 읽어 지느러미 팔이 둥근 팔과 겹치므로, 그 경우엔 아무것도 안 바꾼다.
        var rebuilt: [ObjectIdentifier: SCNGeometry] = [:]
        for target in targets where rebuilt[ObjectIdentifier(target.node)] == nil {
            guard let g = target.node.geometry, let baked = baked(for: g), let made = geometry(g, adding: baked) else {
                logger.error("santa finish: 팔을 접지 못했다(정점 형식) — 보라 아잉으로 선다")
                return false
            }
            rebuilt[ObjectIdentifier(target.node)] = made
        }
        guard let decor = decorNode(body: bodyNode) else { return false }
        for target in targets {
            if let made = rebuilt[ObjectIdentifier(target.node)], target.node.geometry !== made { target.node.geometry = made }
            target.material.diffuse.contents = target.composite
            target.material.shaderModifiers = shaderModifiers
            target.material.setValue(SCNMaterialProperty(contents: shade), forKey: SantaAingShader.shadeMapKey)
        }
        bodyNode.addChildNode(decor)
        let marker = SCNNode()
        marker.name = markerName
        character.addChildNode(marker)
        return true
    }

    /// 이 캐릭터 노드가 산타 아잉이인가(표식).
    static func isSanta(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: markerName, recursively: false) != nil
    }
}
