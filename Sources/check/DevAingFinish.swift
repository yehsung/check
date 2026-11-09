import AppKit
import CheckCore
import os
import SceneKit
import simd

// MARK: - 개발에 찌든 아잉이 3D 마감 (시안 D2 '후드티 개발자' — 대표 결정 2026-11-10 #d_NuLS5imieQds)
//
// 원래 아잉 메시(aing.scn) 그대로다. 마감은 넷이다(틀은 흑우 · 이슬과 같다):
//  ① 디퓨즈 합성 — 무지개와 같다(`RainbowAingFinish.rainbowDiffuse`). 깜빡임 · 졸기 · 울트라로 디퓨즈가 바뀌어도 몸 셰이더가 따라온다.
//  ② 몸 셰이더 — `DevAingShader`(보라 몸 + 회색 후드 · 얼굴 구멍 · 캥거루 주머니 + 다크서클 + 졸린 눈꺼풀). 눈꺼풀은 얼굴 그림을 덮는
//     덮개 칠(ckLid)이다. 속눈썹 선은 눈 그림이 있는 텍셀에만 그려, 감은 눈 텍스처에서는 저절로 사라진다(감은 눈 선 판과 두 줄 방지).
//  ③ 장식 — 얼굴 구멍 아래에서 늘어진 흰 끈 둘(`check.devDecor` — `AingDecor.rootNames` 에 더함: 얼굴 탐색 · 클릭 · 상자 계산이 뺀다).
//  ④ 표식 — 캐릭터 노드의 빈 노드 `markerName`(엔진 `currentCharacterID` 가 가른다 — 같은 메시라 종류로 못 가른다).
enum DevAingFinish {
    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    static let markerName = "check.devAing"
    static let decorNodeName = "check.devDecor"

    static let shaderModifiers: [SCNShaderModifierEntryPoint: String] = [
        .geometry: DevAingShader.geometry, .fragment: DevAingShader.fragment(),
    ]

    // MARK: - 번들 자원 · 그릴 수 있다

    static func resourceURL(_ name: String) -> URL? {
        CheckResources.bundle.url(forResource: name, withExtension: DevAingArt.resourceExtension)
    }

    static func portraitURL(for mood: CheckMascotAssets.Mood) -> URL? {
        resourceURL(mood == .neutral ? DevAingArt.neutralPortraitResourceName : DevAingArt.negativePortraitResourceName)
    }

    /// 이 빌드가 개발 아잉이를 그릴 수 있는가(맥 = 초상 두 장 + 무지개와 같이 쓰는 밝기 맵). 상점 능력 번호 9 의 재료.
    static func isDrawable(fileManager: FileManager = .default) -> Bool {
        DevAingArt.isDrawable(on: .mac) { name in
            guard let url = resourceURL(name) else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }

    // MARK: - 끈 장식

    /// 몸 앞면 (x, y) 의 겉 점(물체 좌표).
    static func frontPoint(_ body: SCNNode, x: Float, y: Float) -> SIMD3<Float>? {
        let hits = body.hitTestWithSegment(from: SCNVector3(x, y, 2), to: SCNVector3(x, y, -2),
                                           options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let h = hits.max(by: { $0.localCoordinates.z < $1.localCoordinates.z }) else { return nil }
        return SIMD3(Float(h.localCoordinates.x), Float(h.localCoordinates.y), Float(h.localCoordinates.z))
    }

    /// 끈 하나(관 + 끝 매듭) — 시안 `devHoodStrings` 와 같은 길.
    static func stringNode(top: SIMD3<Float>, x: Float, index: Int) -> SCNNode {
        typealias Cap = IsulAingFinish.IsulCap
        let L = DevAingArt.stringLength, r0 = DevAingArt.stringRadius, r1 = DevAingArt.stringTipRadius
        let path: (Float) -> SIMD3<Float> = { v in top + SIMD3(x * 0.15 * v, -L * v, 0.03 * sin(v * 3.1)) }
        let pos: Cap.SurfaceFn = { u, v in
            let e: Float = 0.004
            let a = path(max(v - e, 0)), b = path(min(v + e, 1))
            var t = b - a
            if simd_length(t) < 1e-6 { t = SIMD3(0, -1, 0) }
            t = simd_normalize(t)
            let n1 = simd_normalize(simd_cross(t, SIMD3<Float>(0, 0, 1))), n2 = simd_cross(n1, t)
            let th = 2 * Float.pi * u
            let rad = v > 0.88 ? r1 : r0
            return path(v) + (n1 * cos(th) + n2 * sin(th)) * rad
        }
        let color = Cap.lin(DevAingArt.stringColor)
        return Cap.pieceNode(name: "check.dev.string\(index)", nu: 16, nv: 48, closedU: true, texW: 16, texH: 64, pos: pos,
                             albedo: { _, _, _ in color }, look: Cap.Look(ambient: 0.62, spec: 0.55, gloss: 60, wrap: 0.40),
                             transform: matrix_identity_float4x4)
    }

    private static let templateLock = NSLock()
    nonisolated(unsafe) private static var template: SCNNode?

    /// 끈 장식 원본(프로세스당 한 번 굽고 사본을 준다). 몸 메시 노드의 물체 좌표다.
    static func decorNode(body: SCNNode) -> SCNNode? {
        templateLock.lock(); defer { templateLock.unlock() }
        if let template { return template.clone() }
        let root = SCNNode()
        root.name = decorNodeName
        for (i, x) in DevAingArt.stringXs.enumerated() {
            guard let p = frontPoint(body, x: x, y: DevAingArt.stringTopY) else {
                logger.error("dev finish: 끈 자리를 못 쟀다 — 끈 없이 선다")
                return nil
            }
            root.addChildNode(stringNode(top: p + SIMD3(0, 0, 0.012), x: x, index: i))
        }
        if !Thread.isMainThread { SCNTransaction.flush() }
        template = root
        return root.clone()
    }

    // MARK: - 씬에 입히기

    /// 이 캐릭터 노드(아잉 메시)에 개발 아잉이 마감을 입힌다: 디퓨즈 합성 · 몸 셰이더 · ckShadeMap · 끈 장식 · 표식.
    /// **unlit 정규화 뒤 · 감은 눈 노드 앞에** 불러야 한다(흑우 · 이슬과 같은 순서). 그림 · 메시가 없으면 아무것도 안 바꾸고 false.
    @discardableResult
    static func apply(to character: SCNNode) -> Bool {
        guard let shade = RainbowAingFinish.shadeImage() else {
            logger.error("dev finish: 밝기 맵이 없다 — 보라 아잉으로 선다")
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
            logger.error("dev finish: 얼굴 재질을 못 찾았다 — 보라 아잉으로 선다")
            return false
        }
        guard let decor = decorNode(body: bodyNode) else { return false }
        for face in faces {
            face.material.diffuse.contents = face.composite
            face.material.shaderModifiers = shaderModifiers
            face.material.setValue(SCNMaterialProperty(contents: shade), forKey: DevAingShader.shadeMapKey)
        }
        bodyNode.addChildNode(decor)
        let marker = SCNNode()
        marker.name = markerName
        character.addChildNode(marker)
        return true
    }

    static func isDev(_ character: SCNNode?) -> Bool {
        character?.childNode(withName: markerName, recursively: false) != nil
    }
}
