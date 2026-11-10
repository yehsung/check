import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 부산 갈매기 아잉이 3D 마감 (지역 아잉이 · 시안 G1 '갈매기가 된 아잉이' — 대표 결정 2026-11-10 #d_afa6DRyExPLp)
//
// 원래 아잉 메시(aing.scn) 그대로다. 마감은 넷이다(틀은 개발 아잉이 `DevAingFinish` 와 같다):
//  ① 디퓨즈 합성 — 무지개와 같다(`RainbowAingFinish.rainbowDiffuse`). 깜빡임 · 졸기 · 울트라로 디퓨즈가 바뀌어도 몸 셰이더가 따라온다.
//  ② 몸 셰이더 — `GullAingShader`(흰 갈매기 몸 + 등 회색 + 날개 팔: 회색 · 끝 검정 · 흰 점). 얼굴 상자 안은 β 로 원본(눈 · 볼)을 지킨다.
//  ③ 장식 — 부리(입 자리를 덮음) · 물갈퀴 발 둘 · 꼬리깃(`GullAingDecor.decorNodeName` — `AingDecor.rootNames` 에 더함: 얼굴 탐색 · 클릭 ·
//     상자 계산이 뺀다). 모양 · 색은 CheckCore `GullAingDecor` 한 곳(초상 생성기와 같은 조각).
//  ④ 표식 — 캐릭터 노드의 빈 노드 `busanMarkerName`(엔진 `currentCharacterID` 가 가른다 — 같은 메시라 종류로 못 가른다).
// ★ 프레이밍: 내려 세우지 않는다 — 부리 · 발 · 꼬리는 몸 상자 안팎으로 조금만 나온다(발 아래 끝 −0.861 · 몸 −0.847).
enum RegionAingFinish {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    static let busanMarkerName = "check.busanAing"
    static let decorNodeName = GullAingDecor.decorNodeName

    static let busanShaderModifiers: [SCNShaderModifierEntryPoint: String] = [
        .geometry: GullAingShader.geometry, .fragment: GullAingShader.fragment(),
    ]

    // MARK: - 번들 자원 · 그릴 수 있다

    static func resourceURL(_ name: String) -> URL? {
        CheckResources.bundle.url(forResource: name, withExtension: RegionAingArt.resourceExtension)
    }

    static func portraitURL(for id: String, mood: CheckMascotAssets.Mood) -> URL? {
        resourceURL(mood == .neutral ? RegionAingArt.neutralPortraitResourceName(id) : RegionAingArt.negativePortraitResourceName(id))
    }

    /// 이 빌드가 이 지역 아잉이를 그릴 수 있는가(맥 = 초상 두 장 + 밝기 맵). **부산만** 3D 마감이 있다 — 서울은 그림이 정해지기 전이라
    /// 초상이 없어 거짓이다(능력 번호 10 을 말하지 않는다).
    static func isDrawable(_ id: String, fileManager: FileManager = .default) -> Bool {
        guard CharacterCatalog.isBusanAing(id) else { return false }
        return RegionAingArt.isDrawable(id, on: .mac) { name in
            guard let url = resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: - 장식

    typealias Cap = IsulAingFinish.IsulCap

    /// 몸 앞면 (x, y) 의 겉 점(물체 좌표).
    static func frontPoint(_ body: SCNNode, x: Float, y: Float) -> SIMD3<Float>? {
        let hits = body.hitTestWithSegment(from: SCNVector3(x, y, 2), to: SCNVector3(x, y, -2),
                                           options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let h = hits.max(by: { $0.localCoordinates.z < $1.localCoordinates.z }) else { return nil }
        return SIMD3(Float(h.localCoordinates.x), Float(h.localCoordinates.y), Float(h.localCoordinates.z))
    }

    /// 조각 하나 → 노드(빛은 몸 공간에 구운 텍스처 — 이슬 병뚜껑과 같은 길).
    static func node(_ piece: GullDecorPiece) -> SCNNode {
        let pos: Cap.SurfaceFn = { u, v in piece.pos(u, v) }
        return Cap.pieceNode(name: piece.name, nu: piece.nu, nv: piece.nv, closedU: piece.closedU, texW: piece.texW, texH: piece.texH, pos: pos,
                             albedo: { u, v, _ in Cap.lin(piece.color(u, v)) },
                             look: Cap.Look(ambient: piece.ambient, spec: piece.spec, gloss: piece.gloss, wrap: piece.wrap),
                             transform: matrix_identity_float4x4)
    }

    private static let templateLock = NSLock()
    nonisolated(unsafe) private static var template: SCNNode?

    /// 갈매기 장식 원본(프로세스당 한 번 굽고 사본을 준다). 몸 메시 노드의 물체 좌표다.
    static func decorNode(body: SCNNode) -> SCNNode? {
        templateLock.lock(); defer { templateLock.unlock() }
        if let template { return template.clone() }
        guard let beakRoot = frontPoint(body, x: GullAingDecor.beakX, y: GullAingDecor.beakY) else {
            logger.error("busan finish: 부리 자리를 못 쟀다 — 장식 없이 선다")
            return nil
        }
        let root = SCNNode()
        root.name = decorNodeName
        for piece in GullAingDecor.pieces(beakRoot: beakRoot) { root.addChildNode(node(piece)) }
        if !Thread.isMainThread { SCNTransaction.flush() }
        template = root
        return root.clone()
    }

    // MARK: - 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 부산 갈매기 마감을 입힌다: 디퓨즈 합성 · 몸 셰이더 · ckShadeMap · 장식 · 표식.
    /// **unlit 정규화 뒤 · 감은 눈 노드 앞에** 불러야 한다(개발 아잉이와 같은 순서). 그림 · 메시가 없으면 아무것도 안 바꾸고 false.
    @discardableResult
    static func applyBusan(to character: SCNNode) -> Bool {
        guard let shade = RainbowAingFinish.shadeImage() else {
            logger.error("busan finish: 밝기 맵이 없다 — 보라 아잉으로 선다")
            return false
        }
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
            logger.error("busan finish: 얼굴 재질을 못 찾았다 — 보라 아잉으로 선다")
            return false
        }
        guard let decor = decorNode(body: bodyNode) else { return false }
        for face in faces {
            face.material.diffuse.contents = face.composite
            face.material.shaderModifiers = busanShaderModifiers
            face.material.setValue(SCNMaterialProperty(contents: shade), forKey: GullAingShader.shadeMapKey)
        }
        bodyNode.addChildNode(decor)
        let marker = SCNNode()
        marker.name = busanMarkerName
        character.addChildNode(marker)
        return true
    }

    static func isBusan(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: busanMarkerName, recursively: false) != nil
    }
}
