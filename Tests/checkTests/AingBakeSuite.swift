import AppKit
import CryptoKit
import Foundation
import ImageIO
import Metal
import SceneKit
import Testing
import simd
@testable import check
@testable import CheckCore

// MARK: - 3D 아잉이 굽기 (xplat W0-d · 설계 F §3)
//
// Windows·Android 판은 SceneKit 이 없다. 그래서 맥이 그리는 3D 아잉이(아잉 · 황금 · 무지개)를 **맥에서 미리 구운 2D 칸**으로 옮긴다.
// 이 파일이 굽기 엔진이다 — 테스트 타깃인 이유는 3D 장면 코드가 실행 타깃 `check` 안에 있고, `@testable import check` 는
// 테스트 타깃만 할 수 있어서다. 장면을 스크립트로 옮겨 적으면 두 벌이 되므로 **앱이 그리는 장면을 그대로** 굽는다.
//
// 굽기(`bake`)는 `CHECK_AING_BAKE_OUT=<폴더>` 가 있을 때만 돈다(진입점 `multiplatform/scripts/bake-aing/bake.sh`).
// 나머지 셋은 늘 돈다:
//   · 구운 매니페스트를 **지금의** Swift `CharacterManifest` 가 2칸 스프라이트로 읽는다(구버전 호환 — 설계 F §3.5)
//   · 진짜 `ReactionEngine` 졸기(.drowsy) 렌더 = 굽기 경로(감은 눈) 렌더, 바이트 동치(설계 F §3.2-3)
//   · SceneKit 이징 곡선 3종이 실측식과 소수 넷째 자리까지 같다(설계 F §3.2-4)
//
// 규칙: 창을 띄우지 않는다(`SCNRenderer` 오프스크린만, 엔진은 view: nil 로 붙인다). UserDefaults 를 읽지 않는다(캐릭터는 인자).
// 네트워크가 없다(bake.sh 가 sandbox-exec 로 막는다). 저장소에는 쓰지 않는다 — 산출물은 바깥 폴더로만 나가고,
// 저장소 `multiplatform/assets/aing-bake/` 로 옮기는 일은 bake.py 가 한다.

@MainActor
@Suite("AingBakeSuite", .serialized)
struct AingBakeSuite {
    nonisolated static let outDirectory = ProcessInfo.processInfo.environment["CHECK_AING_BAKE_OUT"]
    nonisolated static var bakeEnabled: Bool { outDirectory != nil }
    nonisolated static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// 저장소 꼭대기(이 파일 = Tests/checkTests/AingBakeSuite.swift).
    nonisolated static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: - 늘 도는 시험 ①: 구운 매니페스트 = 기존 형식의 상위집합

    @Test("구운 매니페스트 3종을 기존 Swift CharacterManifest 가 legacy 2칸 스프라이트로 디코드한다 — bake 키는 모르는 키로 무시")
    func legacyManifestsDecodeWithExistingSwiftDecoder() throws {
        let assets = Self.repoRoot.appendingPathComponent("multiplatform/assets/aing-bake")
        for finish in BakeFinish.allCases {
            let dir = assets.appendingPathComponent(finish.assetID)
            let data = try Data(contentsOf: dir.appendingPathComponent("manifest.json"))
            // 상위집합인지: bake 키가 실제로 있어야 한다(없으면 이 시험은 아무것도 재지 않는다).
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let bake = try #require(object["bake"] as? [String: Any], "\(finish.assetID): bake 키가 없다 — 상위집합이 아니다")
            #expect((bake["characterId"] as? String) == finish.manifest.id)
            // 칸 표(단마다 한 파일)와 그 페이지가 실제로 있다.
            let tiers = try #require(bake["tiers"] as? [[String: Any]])
            #expect(tiers.compactMap { $0["name"] as? String }.sorted() == ["L", "S", "U"])
            for tier in tiers {
                let file = try #require(tier["cellsFile"] as? String)
                let table = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(file))) as? [String: Any])
                #expect(((table["cells"] as? [Any])?.count ?? 0) > 0, "\(finish.assetID)/\(file): 칸이 비었다")
            }
            for page in try #require(bake["pages"] as? [String]) {
                #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(page).path), "\(finish.assetID)/\(page) 가 없다")
            }

            let manifest = try JSONDecoder().decode(CharacterManifest.self, from: data)
            #expect(manifest.id == finish.assetID)
            #expect(manifest.kind == .sprite)
            let atlas = try #require(manifest.atlas)
            #expect(atlas.file == "legacy.webp")
            #expect(atlas.states.keys.sorted() == [CharacterManifest.StateKey.frontIdle, CharacterManifest.StateKey.sideIdle])
            // 실제 그림 크기 = 매니페스트 크기(다르면 SpriteRuntime 이 거부한다).
            let image = try #require(Self.decodeImage(dir.appendingPathComponent(atlas.file)), "\(finish.assetID): legacy.webp 를 못 읽는다")
            #expect(image.width == atlas.width && image.height == atlas.height)
            // 구형 런타임이 실제로 평면을 세운다(디코드만 되고 못 서는 매니페스트는 쓸모가 없다).
            #expect(SpriteCharacterNode.make(manifest: manifest, atlas: image) != nil)

            // 음성 대조: 같은 파일에서 frontIdle 칸을 아틀라스 밖으로 밀면 같은 디코더가 throw 한다(디코더가 실제로 검사하고 있다).
            var broken = object
            var brokenAtlas = try #require(broken["atlas"] as? [String: Any])
            var states = try #require(brokenAtlas["states"] as? [String: Any])
            var front = try #require(states["frontIdle"] as? [String: Any])
            front["frames"] = [["x": atlas.width, "y": 0, "w": 10, "h": 10]]
            states["frontIdle"] = front
            brokenAtlas["states"] = states
            broken["atlas"] = brokenAtlas
            let brokenData = try JSONSerialization.data(withJSONObject: broken)
            #expect(throws: CharacterManifestError.rectOutsideAtlas(id: finish.assetID, state: "frontIdle", index: 0)) {
                _ = try JSONDecoder().decode(CharacterManifest.self, from: brokenData)
            }
        }
    }

    // MARK: - 늘 도는 시험 ②: 진짜 엔진 졸기 = 굽기 경로

    @Test("진짜 ReactionEngine 의 졸기(.drowsy) 렌더와 굽기 경로(감은 눈 패치) 렌더가 바이트로 같다 — 마감 3종", .enabled(if: hasMetal))
    func drowsyEngineRenderEqualsBakePath() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        for finish in BakeFinish.allCases {
            // 엔진 경로: attach(view: nil) → request(.drowsy) → 480Hz 로 2.1초 밀어 가라앉기를 끝낸다.
            let clock = BakeClock()
            let engineRig = try BakeRig(finish: finish, device: device, animated: false)
            let engine = ReactionEngine(clock: { clock.now })
            engine.zzzSleep = { _ in try? await Task.sleep(for: .seconds(1_000_000)) }
            engine.attach(node: engineRig.wrapper, sceneRoot: engineRig.scene.rootNode, view: nil)
            let t0 = 100.0
            engineRig.tick(t0)
            #expect(engine.request(.drowsy))
            #expect(engine.state == .sleeping)
            for k in 0...Int(2.1 * 480) { engineRig.tick(t0 + Double(k) / 480) }
            engineRig.removeTransientNodes()
            let tEnd = t0 + Double(Int(2.1 * 480)) / 480
            let enginePixels = try BakeRender.stable(engineRig.renderer, size: BakeSize(280, 340), time: tEnd).image
            let sleepPose = engineRig.wrapper.simdTransform

            // 졸기 끝 자세가 공식(x 14° · y −0.33×0.18×extent)과 같다 — 트랙 녹화가 이 자세를 그대로 담는다.
            let extent = engineRig.engineExtent
            let expectedEuler = SIMD3<Float>(Float(14 * Double.pi / 180), 0, 0)
            #expect(simd_length(engineRig.wrapper.simdEulerAngles - expectedEuler) < 1e-5)
            #expect(abs(Double(engineRig.wrapper.simdPosition.y) + 0.33 * 0.18 * extent) < 1e-5)

            // 굽기 경로: 새 장면 · 같은 자세 · 굽기의 감은 눈(얼굴 디퓨즈 = makeClosedEyesImage, 감은 선 노드 보이기).
            let bakeRig = try BakeRig(finish: finish, device: device, animated: false)
            bakeRig.wrapper.simdTransform = sleepPose
            try bakeRig.setEyes(closed: true)
            let bakePixels = try BakeRender.stable(bakeRig.renderer, size: BakeSize(280, 340), time: 0).image
            #expect(bakePixels.sameBytes(enginePixels), "\(finish.rawValue): 굽기 경로 감은 눈이 엔진과 다르다(다른 픽셀 \(bakePixels.countDifferent(enginePixels)))")

            // 기준선은 달라야 한다: 같은 자세에서 눈을 뜬 굽기 렌더는 엔진 렌더와 달라야 한다(이 비교가 눈을 실제로 본다).
            try bakeRig.setEyes(closed: false)
            let openPixels = try BakeRender.stable(bakeRig.renderer, size: BakeSize(280, 340), time: 0).image
            #expect(openPixels.countDifferent(enginePixels) > 50, "\(finish.rawValue): 뜬 눈과 감은 눈이 안 갈린다 — 기준선이 같은 입력이다")
            engine.stopSleeping()
        }
    }

    // MARK: - 늘 도는 시험 ③: SceneKit 이징 곡선

    @Test("SceneKit timingMode 곡선 3종(+시퀀스 전체 휨 · 앱 키프레임 2종)이 실측식과 소수 넷째 자리까지 같다", .enabled(if: hasMetal))
    func sceneKitCurvesMatchMeasuredFormulas() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let curves = BakeCurves.measure(device: device, hz: 480)
        for curve in curves {
            #expect(curve.maxAbsError < 5e-5, "\(curve.name): 최대 오차 \(curve.maxAbsError)")
        }
        // 음성 대조: 틀린 식(easeInEaseOut 자리에 easeOut 식)을 넣으면 같은 측정이 문턱을 크게 넘는다.
        let inOut = try #require(curves.first { $0.name == "easeInEaseOut" })
        let wrong = zip(inOut.times, inOut.values).map { abs($1 - BakeCurves.easeOut($0)) }.max() ?? 0
        #expect(wrong > 0.05, "틀린 식과도 맞는다 — 이 측정은 곡선을 안 본다(\(wrong))")
    }

    // MARK: - 굽기(환경변수로만)

    @Test("굽기 — CHECK_AING_BAKE_OUT 이 있을 때만", .enabled(if: bakeEnabled), .timeLimit(.minutes(60)))
    func bake() async throws {
        let out = URL(fileURLWithPath: try #require(Self.outDirectory))
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal 장치가 없다 — 굽기는 Metal 이 필요하다")
        let config = try BakeConfig.load(Self.repoRoot.appendingPathComponent("multiplatform/scripts/bake-aing/config.json"))
        let baker = Baker(out: out, config: config, device: device)
        try await baker.run()
        // 창 0: 이 프로세스가 가진 창이 하나도 없어야 한다(SCNRenderer 오프스크린만 썼다는 실측).
        #expect(Self.windowsOwnedByThisProcess() == 0)
    }

    // MARK: - 재현성 탐침(F-10 · CI aing-bake-verify)

    nonisolated static let probeOut = ProcessInfo.processInfo.environment["CHECK_AING_BAKE_PROBE_OUT"]
    nonisolated static var probeEnabled: Bool { probeOut != nil }

    /// 굽기와 **같은 함수**(`Baker.renderCell`)로 칸 몇 개를 그려 원본 다이제스트를 lock.json.raw 와 같은 키로 쓴다.
    /// 다른 맥(CI 러너)에서 돌려 이 맥의 굽기와 바이트로 같은지 잰다. 직선 RGBA 도 함께 써서 다르면 최대 Δ 를 잴 수 있게 한다.
    @Test("재현성 탐침 — CHECK_AING_BAKE_PROBE_OUT 이 있을 때만", .enabled(if: probeEnabled))
    func reproducibilityProbe() throws {
        let out = URL(fileURLWithPath: try #require(Self.probeOut))
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal 장치가 없다")
        let config = try BakeConfig.load(Self.repoRoot.appendingPathComponent("multiplatform/scripts/bake-aing/config.json"))
        let baker = Baker(out: out, config: config, device: device)
        let rig = try BakeRig(finish: .standard, device: device, animated: false)
        rig.setHaloVisible(false)
        let camera = BakeCamera(world: BakeMath.d(rig.camera.simdWorldTransform), fovDeg: Double(rig.camera.camera!.fieldOfView),
                                zNear: Double(rig.camera.camera!.zNear), zFar: Double(rig.camera.camera!.zFar),
                                verticalFov: rig.camera.camera!.projectionDirection == .vertical)
        let cells = [BakeCell(tier: "S", group: .rest, yaw: 0, tilt: config.grid.restTilt),
                     BakeCell(tier: "S", group: .rest, yaw: 40, tilt: config.grid.restTilt),
                     BakeCell(tier: "S", group: .band, yaw: 0, tilt: 28),
                     BakeCell(tier: "S", group: .spin, yaw: 180, tilt: 14),
                     BakeCell(tier: "L", group: .rest, yaw: 0, tilt: config.grid.restTilt),
                     BakeCell(tier: "U", group: .ultra, yaw: 0, tilt: 13)]
        var raw: [String: String] = [:]
        for cell in cells {
            let render = try baker.renderCell(cell, rig: rig, size: config.size(cell.tier), camera: camera,
                                              cameraDirection: simd_normalize(camera.position), patch: false)
            raw["aing/\(cell.id)"] = Baker.sha256(render.straight, w: render.crop.w, h: render.crop.h)
            try baker.emitImage(bytes: render.straight, w: render.crop.w, h: render.crop.h,
                                rawName: "aing/\(cell.id.replacingOccurrences(of: ":", with: "_"))", destination: "-", mode: "none")
        }
        try baker.write(["gpu": device.name, "raw": raw, "images": baker.images], to: "probe.json")
    }

    // MARK: - 보조

    nonisolated static func decodeImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    nonisolated static func windowsOwnedByThisProcess() -> Int {
        let pid = Int(getpid())
        let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
        return list.filter { ($0[kCGWindowOwnerPID as String] as? Int) == pid }.count
    }
}

// MARK: - 마감 · 장면

/// 구울 3D 아잉이 3종. 같은 메시(aing.scn)에 마감만 다르다.
enum BakeFinish: String, CaseIterable {
    case standard, gold, rainbow

    /// 자산 폴더 이름 = 매니페스트 id(파일 문법 `[a-z0-9-]` — 서버 id 의 밑줄은 못 쓴다 → `bake.characterId` 에 둔다).
    var assetID: String {
        switch self {
        case .standard: return "aing"
        case .gold: return "aing-gold"
        case .rainbow: return "aing-rainbow"
        }
    }

    var manifest: CharacterManifest {
        switch self {
        case .standard: return CharacterCatalog.builtInAing
        case .gold: return CharacterCatalog.builtInGoldAing
        case .rainbow: return CharacterCatalog.builtInRainbowAing
        }
    }

    var finishName: String {
        switch self {
        case .standard: return "standard"
        case .gold: return "gold"
        case .rainbow: return "rainbow"
        }
    }

    var haloNodeName: String? {
        switch self {
        case .standard: return nil
        case .gold: return GoldAingFinish.haloNodeName
        case .rainbow: return RainbowAingFinish.haloNodeName
        }
    }

    var haloCellFiles: [String]? {
        switch self {
        case .standard: return nil
        case .gold: return GoldAingArt.haloCellResourceNames.map { "\($0).png" }
        case .rainbow: return RainbowAingArt.haloCellResourceNames.map { "\($0).png" }
        }
    }

    var portraitFiles: (neutral: String, negative: String) {
        switch self {
        case .standard: return ("aing-neutral.png", "aing-negative.png")
        case .gold: return ("\(GoldAingArt.neutralPortraitResourceName).png", "\(GoldAingArt.negativePortraitResourceName).png")
        case .rainbow: return ("\(RainbowAingArt.neutralPortraitResourceName).png", "\(RainbowAingArt.negativePortraitResourceName).png")
        }
    }
}

struct BakeError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

/// 엔진 시계(주입). 리액션 사이에 크게 밀어 쿨다운·만료가 다음 요청을 막지 않게 한다.
@MainActor
final class BakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

struct BakeSize: Hashable {
    let w: Int, h: Int
    init(_ w: Int, _ h: Int) { self.w = w; self.h = h }
}

/// 앱의 `CheckCharacter3DScene.makeScene` 이 만든 장면 하나와 그 노드 사슬(root → wrapper → facing → 캐릭터).
@MainActor
final class BakeRig {
    let finish: BakeFinish
    let scene: SCNScene
    let wrapper: SCNNode
    let facing: SCNNode
    let character: SCNNode
    let camera: SCNNode
    let halo: SCNNode?
    let renderer: SCNRenderer
    private var face: (material: SCNMaterial, awake: CGImage, closed: CGImage?)?
    private var eyesClosed: Bool?

    init(finish: BakeFinish, device: MTLDevice, animated: Bool) throws {
        self.finish = finish
        guard let scene = CheckCharacter3DScene.makeScene(animated: animated, character: finish.manifest) else {
            throw BakeError("makeScene 실패 \(finish)")
        }
        guard let wrapper = scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false),
              let facing = wrapper.childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false),
              let character = facing.childNodes.first,
              let camera = scene.rootNode.childNodes.first(where: { $0.camera != nil }) else {
            throw BakeError("노드 사슬을 못 찾았다 \(finish)")
        }
        self.scene = scene
        self.wrapper = wrapper
        self.facing = facing
        self.character = character
        self.camera = camera
        self.halo = finish.haloNodeName.flatMap { character.childNode(withName: $0, recursively: false) }
        if finish != .standard, halo == nil { throw BakeError("\(finish): 후광 노드가 없다 — 마감 그림이 번들에 없다") }
        // 캐릭터 노드의 바탕 변환은 단위여야 한다: 칸 계산(몸 국소 = 캐릭터 좌표)과 idle(moveBy·rotateBy)이 그 위에서 정의된다.
        if !animated {
            let m = character.simdTransform
            let identity = matrix_identity_float4x4
            var worst: Float = 0
            for c in 0..<4 { worst = max(worst, simd_length(m[c] - identity[c])) }
            if worst > 1e-6 { throw BakeError("캐릭터 바탕 변환이 단위가 아니다(\(worst)) — 칸 정의를 다시 세워야 한다") }
        }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false
        renderer.pointOfView = camera
        self.renderer = renderer
    }

    /// 엔진 `attach` 가 쓰는 크기(wrapper bbox 최장변, z 포함) — 리액션 진폭의 단위.
    var engineExtent: Double {
        let (minB, maxB) = wrapper.boundingBox
        return Double(max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z)))
    }

    /// 몸 바운딩박스(후광·감은 선 전, 캐릭터 메시 기준이 아니라 앱 카메라가 보는 씬 루트 기준이 아님 — 후광 중심 계산과 같은 캐릭터 bbox).
    var characterBox: (min: SIMD3<Double>, max: SIMD3<Double>) {
        let (minB, maxB) = character.boundingBox
        return (SIMD3(Double(minB.x), Double(minB.y), Double(minB.z)), SIMD3(Double(maxB.x), Double(maxB.y), Double(maxB.z)))
    }

    /// 칸 렌더 직전 상태: 리액션 액션 없음 · wrapper/facing 단위 · 캐릭터 단위.
    func resetPose() {
        wrapper.removeAllActions()
        facing.removeAllActions()
        wrapper.simdTransform = matrix_identity_float4x4
        facing.simdTransform = matrix_identity_float4x4
        character.simdTransform = matrix_identity_float4x4
    }

    func setHaloVisible(_ visible: Bool) { halo?.isHidden = !visible }

    /// 액션 시계를 민다(8×8). SceneKit 액션을 실제로 진행시키는 것은 `snapshot(atTime:)` 뿐이다(`update(atTime:)` 은 0 — V0316 실측).
    func tick(_ time: TimeInterval) {
        _ = renderer.snapshot(atTime: time, with: CGSize(width: 8, height: 8), antialiasingMode: .none)
    }

    /// 엔진이 씬 루트에 붙이는 일시 노드(색종이 · 스파크 · 흡수 · 💤)를 걷는다 — 골든은 파티클을 끄고 굽는다.
    func removeTransientNodes() {
        for node in scene.rootNode.childNodes where (node.name ?? "").hasPrefix("check.reaction.") || node.particleSystems?.isEmpty == false {
            node.removeFromParentNode()
        }
    }

    /// 굽기 경로의 감은 눈: 엔진과 **같은 규칙**으로 얼굴 재질(큰 CGImage 디퓨즈, 후광 재질 제외)을 찾고,
    /// `CheckCharacter3DScene.makeClosedEyesImage` 를 대입한 뒤 감은 선 노드를 드러낸다(엔진 `applyClosedEyes` 와 같은 일).
    func setEyes(closed: Bool) throws {
        if face == nil {
            var found: (SCNMaterial, CGImage, SCNGeometry?)?
            scene.rootNode.enumerateHierarchy { node, stop in
                for material in node.geometry?.materials ?? [] {
                    guard material.name != GoldAingFinish.haloMaterialName else { continue }
                    let contents = material.diffuse.contents
                    guard CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { continue }
                    let cg = contents as! CGImage
                    if cg.width >= 256 {
                        found = (material, cg, node.geometry)
                        stop.pointee = true
                        return
                    }
                }
            }
            guard let (material, awake, geometry) = found else { throw BakeError("\(finish): 얼굴 재질을 못 찾았다") }
            face = (material, awake, CheckCharacter3DScene.makeClosedEyesImage(faceImage: awake, geometry: geometry))
        }
        guard let face else { return }
        if eyesClosed == closed { return }
        eyesClosed = closed
        if closed {
            guard let closedImage = face.closed else { throw BakeError("\(finish): 감은 눈 텍스처 생성 실패") }
            face.material.diffuse.contents = closedImage
        } else {
            face.material.diffuse.contents = face.awake
        }
        for name in [CheckCharacter3DScene.closedEyeLeftName, CheckCharacter3DScene.closedEyeRightName] {
            scene.rootNode.childNode(withName: name, recursively: true)?.isHidden = !closed
        }
    }
}

// MARK: - 렌더 · 그림

/// 프리멀티 RGBA8(sRGB), 위-왼쪽 원점.
struct BakeImage {
    let w: Int
    let h: Int
    var px: [UInt8]

    func sameBytes(_ other: BakeImage) -> Bool {
        guard w == other.w, h == other.h else { return false }
        return px.withUnsafeBytes { a in other.px.withUnsafeBytes { b in memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0 } }
    }

    func countDifferent(_ other: BakeImage) -> Int {
        guard w == other.w, h == other.h else { return Int.max }
        return px.withUnsafeBufferPointer { a in other.px.withUnsafeBufferPointer { b in
            var n = 0
            for i in 0..<(w * h) {
                let o = i * 4
                if a[o] != b[o] || a[o + 1] != b[o + 1] || a[o + 2] != b[o + 2] || a[o + 3] != b[o + 3] { n += 1 }
            }
            return n
        } }
    }

    func maxChannelDelta(_ other: BakeImage) -> Int {
        px.withUnsafeBufferPointer { a in other.px.withUnsafeBufferPointer { b in
            var m = 0
            for i in 0..<a.count { m = max(m, abs(Int(a[i]) - Int(b[i]))) }
            return m
        } }
    }

    /// 알파 > 0 상자(닫힌 구간). 비었으면 nil.
    func alphaBox() -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        px.withUnsafeBufferPointer { p in
            var x0 = w, y0 = h, x1 = -1, y1 = -1
            for y in 0..<h {
                let row = y * w * 4
                for x in 0..<w where p[row + x * 4 + 3] != 0 {
                    if x < x0 { x0 = x }
                    if x > x1 { x1 = x }
                    if y < y0 { y0 = y }
                    if y > y1 { y1 = y }
                }
            }
            return x1 >= 0 ? (x0, y0, x1, y1) : nil
        }
    }

    /// 두 그림이 다른 픽셀의 상자(닫힌 구간). 같으면 nil.
    func diffBox(_ other: BakeImage) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        px.withUnsafeBufferPointer { a in other.px.withUnsafeBufferPointer { b in
            var x0 = w, y0 = h, x1 = -1, y1 = -1
            for y in 0..<h {
                for x in 0..<w {
                    let o = (y * w + x) * 4
                    if a[o] != b[o] || a[o + 1] != b[o + 1] || a[o + 2] != b[o + 2] || a[o + 3] != b[o + 3] {
                        if x < x0 { x0 = x }
                        if x > x1 { x1 = x }
                        if y < y0 { y0 = y }
                        if y > y1 { y1 = y }
                    }
                }
            }
            return x1 >= 0 ? (x0, y0, x1, y1) : nil
        } }
    }

    func crop(x: Int, y: Int, w cw: Int, h ch: Int) -> BakeImage {
        var out = [UInt8](repeating: 0, count: cw * ch * 4)
        px.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for yy in 0..<ch {
                    let sy = y + yy
                    guard sy >= 0, sy < h else { continue }
                    for xx in 0..<cw {
                        let sx = x + xx
                        guard sx >= 0, sx < w else { continue }
                        let s = (sy * w + sx) * 4, d = (yy * cw + xx) * 4
                        dst[d] = src[s]; dst[d + 1] = src[s + 1]; dst[d + 2] = src[s + 2]; dst[d + 3] = src[s + 3]
                    }
                }
            }
        }
        return BakeImage(w: cw, h: ch, px: out)
    }

    /// 파일용 직선(straight) 알파: C = min(255, round(P·255/A)). 디코더가 다시 곱한 round(C·A/255) 와 원래 P 의 차이를 함께 잰다.
    /// ⚠️ 설계 F §3.4 는 이 변환이 무손실이라고 적었지만 **P > A 인 픽셀에서는 손실이 난다**: SceneKit 은 반투명을 "선형 프리멀티 후
    /// sRGB 부호화"로 적어서 밝은 가장자리 픽셀의 P(부호화된 값)가 A 를 넘는다(sRGB 부호화가 오목하다). 그 픽셀은 C 가 255 로
    /// 잘려 P' = A 가 된다. 실측 수치는 plan.reports["alpha"] — 보고서의 설계 충돌 항목.
    func straightened() -> (bytes: [UInt8], stats: AlphaStats) {
        var out = [UInt8](repeating: 0, count: px.count)
        var stats = AlphaStats()
        px.withUnsafeBufferPointer { p in
            out.withUnsafeMutableBufferPointer { o in
                for i in stride(from: 0, to: p.count, by: 4) {
                    let a = Int(p[i + 3])
                    guard a > 0 else { continue }
                    stats.translucent += a < 255 ? 1 : 0
                    stats.visible += 1
                    o[i + 3] = UInt8(a)
                    var over = false
                    for c in 0..<3 {
                        let pc = Int(p[i + c])
                        if pc > a { over = true }
                        let s = min(255, (pc * 510 + a) / (2 * a))
                        o[i + c] = UInt8(s)
                        let back = (2 * s * a + 255) / 510
                        let err = abs(back - pc)
                        if err > 0 { stats.channelMismatches += 1; stats.sumAbsError += err; stats.maxAbsError = max(stats.maxAbsError, err) }
                    }
                    if over { stats.overAlpha += 1 }
                }
            }
        }
        return (out, stats)
    }
}

/// 직선 알파 왕복 손실 집계.
struct AlphaStats {
    var visible = 0, translucent = 0, overAlpha = 0, channelMismatches = 0, sumAbsError = 0, maxAbsError = 0
    mutating func add(_ o: AlphaStats) {
        visible += o.visible; translucent += o.translucent; overAlpha += o.overAlpha
        channelMismatches += o.channelMismatches; sumAbsError += o.sumAbsError; maxAbsError = max(maxAbsError, o.maxAbsError)
    }
    var report: [String: Any] {
        ["visiblePixels": visible, "translucentPixels": translucent, "pixelsWithColorAboveAlpha": overAlpha,
         "channelMismatches": channelMismatches, "maxAbsError": maxAbsError,
         "meanAbsErrorOverMismatches": channelMismatches == 0 ? 0 : BakeMath.r6(Double(sumAbsError) / Double(channelMismatches))]
    }
}

enum BakeRender {
    /// 한 장. snapshot 의 CGImage 를 sRGB 프리멀티 RGBA8 문맥에 복사로 옮긴다(프로브와 같은 경로).
    @MainActor
    static func capture(_ renderer: SCNRenderer, size: BakeSize, time: TimeInterval,
                        antialiasing: SCNAntialiasingMode = .multisampling4X) throws -> BakeImage {
        let image = renderer.snapshot(atTime: time, with: CGSize(width: size.w, height: size.h), antialiasingMode: antialiasing)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw BakeError("snapshot → CGImage 실패") }
        guard cg.width == size.w, cg.height == size.h else { throw BakeError("snapshot 크기 \(cg.width)×\(cg.height) ≠ \(size.w)×\(size.h)") }
        var px = [UInt8](repeating: 0, count: size.w * size.h * 4)
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: size.w, height: size.h, bitsPerComponent: 8, bytesPerRow: size.w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setBlendMode(.copy)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size.w, height: size.h))
            return true
        }
        guard ok else { throw BakeError("CGContext 실패") }
        return BakeImage(w: size.w, h: size.h, px: px)
    }

    /// 굳히기: 연속 두 장이 바이트까지 같아질 때까지 다시 그린다(최소 3 · 최대 6 — 기억 imagerenderer-first-two-renders-differ).
    ///
    /// `period2` 를 주면 굳지 않을 때 한 번 더 본다: 마지막 넷이 A·B·A·B(주기 2)면 둘 중 sha256 이 작은 쪽을 고르고(위상과 무관하게
    /// 결정적) 차이(픽셀 수 · 최대 채널 Δ)를 호출부에 알린다 — 골든 JSON 이 그 칸에 `haloFlicker` 로 적는다.
    /// 후광이 보이는 장면에서만 생긴다: 앱의 후광 칸 제약(`GoldAingFinish.makeHaloCellNode` 의 빌보드 → 변환 제약)이 같은 시각을
    /// 다시 그릴 때마다 두 값을 오간다(실측: 골든 113 금 찔림 3픽셀 Δ1 · 골든 176 무지개 근무 종료 120픽셀, 후광을 숨기면 첫 장부터 같다).
    /// 칸 굽기(후광 숨김)는 이 길을 쓰지 않는다 — 거기서는 굳지 않으면 굽기가 실패한다.
    @MainActor
    static func stable(_ renderer: SCNRenderer, size: BakeSize, time: TimeInterval, minimum: Int = 3, maximum: Int = 6,
                       antialiasing: SCNAntialiasingMode = .multisampling4X,
                       period2: ((_ kind: String, _ pixels: Int, _ maxDelta: Int) -> Void)? = nil) throws -> (image: BakeImage, renders: Int) {
        var history = [try capture(renderer, size: size, time: time, antialiasing: antialiasing)]
        var diffs: [Int] = []
        while true {
            let next = try capture(renderer, size: size, time: time, antialiasing: antialiasing)
            let same = next.sameBytes(history[history.count - 1])
            diffs.append(same ? 0 : next.countDifferent(history[history.count - 1]))
            history.append(next)
            if history.count >= minimum, same { return (next, history.count) }
            if history.count >= maximum {
                let n = history.count
                if let period2, n >= 4, history[n - 1].sameBytes(history[n - 3]), history[n - 2].sameBytes(history[n - 4]) {
                    let a = history[n - 1], b = history[n - 2]
                    let pixels = a.countDifferent(b), delta = a.maxChannelDelta(b)
                    period2("period2", pixels, delta)
                    let ha = Baker.sha256(a.px, w: a.w, h: a.h), hb = Baker.sha256(b.px, w: b.w, h: b.h)
                    return (ha < hb ? a : b, n)
                }
                if let period2 {
                    // 주기도 없다(후광 제약이 몇 프레임 더 헤맨다) — 마지막 장을 쓴다. 굽기 순서가 같으면 같은 장이다(① 두 번 굽기로 잰다).
                    period2("unsettled", diffs.max() ?? 0, history[n - 1].maxChannelDelta(history[n - 2]))
                    return (history[n - 1], n)
                }
                throw BakeError("렌더가 \(maximum)장 안에 굳지 않았다(연속 차이 픽셀 \(diffs))")
            }
        }
    }
}

// MARK: - 카메라 · 투영

/// 앱 카메라(`addFramingCamera`)의 world 변환 · fov 로 world → 화면 픽셀(위-왼쪽 원점, 연속 좌표: 픽셀 i 는 [i, i+1)).
struct BakeCamera {
    let world: simd_double4x4
    let fovDeg: Double
    let zNear: Double
    let zFar: Double
    let verticalFov: Bool

    var position: SIMD3<Double> { SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z) }

    func project(_ p: SIMD3<Double>, size: BakeSize) -> SIMD2<Double> {
        let view = world.inverse
        let c = view * SIMD4(p, 1)
        let f = 1 / tan(fovDeg * .pi / 360)
        let aspect = Double(size.w) / Double(size.h)
        let fx = verticalFov ? f / aspect : f
        let fy = verticalFov ? f : f * aspect
        let nx = fx * c.x / -c.z, ny = fy * c.y / -c.z
        return SIMD2((nx + 1) / 2 * Double(size.w), (1 - (ny + 1) / 2) * Double(size.h))
    }

    /// 열 우선 4×4 투영행렬(OpenGL 꼴, 오른손 · 카메라는 −z 를 본다).
    func projectionMatrix(size: BakeSize) -> simd_double4x4 {
        let f = 1 / tan(fovDeg * .pi / 360)
        let aspect = Double(size.w) / Double(size.h)
        let fx = verticalFov ? f / aspect : f
        let fy = verticalFov ? f : f * aspect
        return simd_double4x4(columns: (SIMD4(fx, 0, 0, 0), SIMD4(0, fy, 0, 0),
                                        SIMD4(0, 0, (zFar + zNear) / (zNear - zFar), -1),
                                        SIMD4(0, 0, 2 * zFar * zNear / (zNear - zFar), 0)))
    }
}

enum BakeMath {
    static func d(_ m: simd_float4x4) -> simd_double4x4 {
        simd_double4x4(columns: (SIMD4<Double>(m.columns.0), SIMD4<Double>(m.columns.1), SIMD4<Double>(m.columns.2), SIMD4<Double>(m.columns.3)))
    }

    static func f(_ m: simd_double4x4) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }

    static func rad(_ deg: Double) -> Double { deg * .pi / 180 }
    static func deg(_ rad: Double) -> Double { rad * 180 / .pi }

    /// 몸 국소에서 본 카메라 방향(칸 키 → 단위벡터). ψ + = 얼굴이 화면 오른쪽(후광 칸과 같은 부호).
    static func cellDirection(yawDeg: Double, tiltDeg: Double) -> SIMD3<Double> {
        let y = rad(yawDeg), t = rad(tiltDeg)
        return SIMD3(-sin(y) * cos(t), sin(t), cos(y) * cos(t))
    }

    /// 단위벡터 → (ψ, τ) 도.
    static func yawTilt(_ n: SIMD3<Double>) -> (yaw: Double, tilt: Double) {
        (deg(-atan2(n.x, n.z)), deg(asin(max(-1, min(1, n.y)))))
    }

    /// 칸 렌더용 wrapper 회전: 몸 국소 n 이 원점→카메라 방향 d0 와 겹치고, 몸 위 축이 화면에서 기울지 않게(롤 0). 프로브 `cellRotation`.
    static func cellRotation(yawDeg: Double, tiltDeg: Double, cameraDirection d0: SIMD3<Double>) -> simd_double3x3 {
        let n = cellDirection(yawDeg: yawDeg, tiltDeg: tiltDeg)
        let up = SIMD3<Double>(0, 1, 0)
        let rl = simd_normalize(simd_cross(up, n)), ul = simd_cross(n, rl)
        let rw = simd_normalize(simd_cross(up, d0)), uw = simd_cross(d0, rw)
        let w = simd_double3x3(columns: (rw, uw, d0)), l = simd_double3x3(columns: (rl, ul, n))
        return w * l.transpose
    }

    static func m4(_ r: simd_double3x3, translation: SIMD3<Double> = .zero) -> simd_double4x4 {
        simd_double4x4(columns: (SIMD4(r.columns.0, 0), SIMD4(r.columns.1, 0), SIMD4(r.columns.2, 0), SIMD4(translation, 1)))
    }

    static func m3(_ m: simd_double4x4) -> simd_double3x3 {
        simd_double3x3(columns: (SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                                 SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                 SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)))
    }

    /// 몸 world 변환 + 카메라 위치 → 칸 고르기 방향 n = normalize(B⁻¹ d), d = normalize(카메라 − 피벗)(설계 F §3.2-2).
    static func viewDirection(bodyWorld: simd_double4x4, camera: SIMD3<Double>) -> SIMD3<Double> {
        let p = SIMD3(bodyWorld.columns.3.x, bodyWorld.columns.3.y, bodyWorld.columns.3.z)
        let d = simd_normalize(camera - p)
        return simd_normalize(m3(bodyWorld).inverse * d)
    }

    static func angleDeg(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        deg(acos(max(-1, min(1, simd_dot(a, b)))))
    }

    static func r6(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }
    static func r3(_ x: Double) -> Double { (x * 1e3).rounded() / 1e3 }

    static func list(_ m: simd_double4x4) -> [Double] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [r6($0.x), r6($0.y), r6($0.z), r6($0.w)] }
    }
}

// MARK: - 칸 격자

struct BakeCell: Hashable {
    enum Group: String { case rest, band, spin, ultra }
    let tier: String
    let group: Group
    let yaw: Int          // 도, (−180, 180]
    let tilt: Double      // 도
    var id: String { "\(tier):\(String(format: "%+04d", yaw)):\(String(format: "%.1f", tilt))" }
    var direction: SIMD3<Double> { BakeMath.cellDirection(yawDeg: Double(yaw), tiltDeg: tilt) }

    static func normalizeYaw(_ yaw: Int) -> Int {
        var y = yaw % 360
        if y <= -180 { y += 360 }
        if y > 180 { y -= 360 }
        return y
    }
}

enum BakeGrid {
    static func band(_ b: BakeConfig.Band) -> [Int] {
        Array(stride(from: b.center - b.half, through: b.center + b.half, by: b.step)).map(BakeCell.normalizeYaw)
    }

    /// 표준 단 격자(설계 F §3.2-2 표). 같은 (요, 기울기)가 두 무리에 있으면 앞 무리(쉬는 > 띠 > 스핀)만 남긴다.
    static func standard(_ g: BakeConfig.Grid, tier: String = "S") -> (cells: [BakeCell], duplicates: Int) {
        var cells: [BakeCell] = []
        var seen = Set<String>()
        var duplicates = 0
        func add(_ c: BakeCell) {
            let key = "\(c.yaw)|\(c.tilt)"
            if seen.insert(key).inserted { cells.append(c) } else { duplicates += 1 }
        }
        for b in g.restBands { for y in band(b) { add(BakeCell(tier: tier, group: .rest, yaw: y, tilt: g.restTilt)) } }
        for t in g.bandTilts { for b in g.bandBands { for y in band(b) { add(BakeCell(tier: tier, group: .band, yaw: y, tilt: t)) } } }
        for t in g.spinTilts {
            for k in 0..<(360 / g.spinYawStep) { add(BakeCell(tier: tier, group: .spin, yaw: BakeCell.normalizeYaw(k * g.spinYawStep), tilt: t)) }
        }
        return (sorted(cells), duplicates)
    }

    static func rest(_ g: BakeConfig.Grid, tier: String) -> [BakeCell] {
        sorted(g.restBands.flatMap { b in band(b).map { BakeCell(tier: tier, group: .rest, yaw: $0, tilt: g.restTilt) } })
    }

    static func ultra(_ g: BakeConfig.Grid) -> [BakeCell] {
        sorted(g.ultraTilts.values.flatMap { t in band(g.ultraBand).map { BakeCell(tier: "U", group: .ultra, yaw: $0, tilt: t) } })
    }

    static func sorted(_ cells: [BakeCell]) -> [BakeCell] {
        let order: [BakeCell.Group: Int] = [.rest: 0, .band: 1, .spin: 2, .ultra: 3]
        return cells.sorted { a, b in
            if order[a.group]! != order[b.group]! { return order[a.group]! < order[b.group]! }
            if a.tilt != b.tilt { return a.tilt < b.tilt }
            return a.yaw < b.yaw
        }
    }

    /// 감은 눈 패치를 굽는 칸: 쉬는 행(깜빡임) + 띠 행 τ ∈ [min, max](가라앉기 · 졸기 · 기상).
    static func closedEyeCapable(_ c: BakeCell, _ g: BakeConfig.Grid) -> Bool {
        switch c.group {
        case .rest: return true
        case .band: return c.tilt >= g.closedEyeTiltMin && c.tilt <= g.closedEyeTiltMax
        case .spin, .ultra: return false
        }
    }
}

/// 가장 가까운 칸(각 거리) — 굽기의 사용 기반 솎기와 골든의 "Swift 참조 칸" 이 같은 함수다.
/// 2°×2° 상자마다 후보를 미리 거른다: 상자 안 어느 점 x 에서도 d(x,c) ≥ d(중심,c) − r, d(x,c*) ≤ d(중심,c*) + r 이므로
/// d(중심,c) ≤ d_min + 2r 인 칸만 보면 정확하다(r = 상자 외접 반경, 1.5° 로 넉넉히). 범위 밖이면 전수.
struct BakeSelector {
    let cells: [BakeCell]
    let dirs: [SIMD3<Double>]
    private let bins: [[Int32]]
    private static let yawBins = 180, tiltBins = 28, tiltMin = -10.0, step = 2.0, radius = 1.5

    init(_ cells: [BakeCell]) {
        self.cells = cells
        let dirs = cells.map(\.direction)
        self.dirs = dirs
        var bins: [[Int32]] = []
        bins.reserveCapacity(Self.yawBins * Self.tiltBins)
        for ti in 0..<Self.tiltBins {
            for yi in 0..<Self.yawBins {
                let center = BakeMath.cellDirection(yawDeg: -180 + (Double(yi) + 0.5) * Self.step,
                                                    tiltDeg: Self.tiltMin + (Double(ti) + 0.5) * Self.step)
                let dist = dirs.map { BakeMath.angleDeg(center, $0) }
                let best = dist.min() ?? 0
                bins.append(dist.indices.filter { dist[$0] <= best + 2 * Self.radius + 1e-9 }.map { Int32($0) })
            }
        }
        self.bins = bins
    }

    /// (칸 번호, 각 거리 도). 동점은 번호가 작은 쪽(정렬 순서 = 결정적).
    func nearest(_ n: SIMD3<Double>) -> (index: Int, angle: Double) {
        let (yaw, tilt) = BakeMath.yawTilt(n)
        let ti = Int(floor((tilt - Self.tiltMin) / Self.step))
        var y = yaw
        if y >= 180 { y -= 360 }
        let yi = min(Self.yawBins - 1, max(0, Int(floor((y + 180) / Self.step))))
        var bestIndex = -1, bestDot = -2.0
        func consider(_ i: Int) {
            let dot = simd_dot(n, dirs[i])
            if dot > bestDot + 1e-15 || (abs(dot - bestDot) <= 1e-15 && i < bestIndex) { bestDot = dot; bestIndex = i }
        }
        if ti >= 0, ti < Self.tiltBins {
            for i in bins[ti * Self.yawBins + yi] { consider(Int(i)) }
        } else {
            for i in dirs.indices { consider(i) }
        }
        return (bestIndex, BakeMath.deg(acos(max(-1, min(1, bestDot)))))
    }
}

// MARK: - 설정

struct BakeConfig: Decodable {
    struct Tier: Decodable { let viewport: [Int]; let pageMaxWidth: Int; let pageMaxCells: Int }
    struct Band: Decodable { let center: Int; let half: Int; let step: Int }
    struct Range: Decodable {
        let from: Double, to: Double, step: Double
        var values: [Double] { Array(stride(from: from, through: to + 1e-9, by: step)) }
    }
    struct Grid: Decodable {
        let restTilt: Double
        let restBands: [Band]
        let bandTilts: [Double]
        let bandBands: [Band]
        let spinTilts: [Double]
        let spinYawStep: Int
        let ultraTilts: Range
        let ultraBand: Band
        let closedEyeTiltMin: Double
        let closedEyeTiltMax: Double
    }
    struct Cull: Decodable {
        let simHz: Int
        let facingsDeg: [Double]
        let swayPhases: Int
        let swayPhaseStepS: Double
        let slowDegPerS: Double, slowTolDeg: Double, fastDegPerS: Double, fastTolDeg: Double
        let safetyYawStep: Int
        let safetyTilts: [Double]
    }
    struct Golden: Decodable { let viewport: [Int]; let swayPhasesS: [Double]; let facingsDeg: [Double]; let fractions: [Double] }

    let bakeFormat: Int
    let cwebp: String
    let trackHz: Int
    let stabilizeMin: Int
    let stabilizeMax: Int
    let slotAlign: Int
    let cellMarginPx: Int
    let patchMarginPx: Int
    let quadHalfUnits: Double
    let tiers: [String: Tier]
    let grid: Grid
    let cull: Cull
    let golden: Golden

    static func load(_ url: URL) throws -> BakeConfig {
        try JSONDecoder().decode(BakeConfig.self, from: Data(contentsOf: url))
    }

    func size(_ tier: String) -> BakeSize {
        let v = tiers[tier]!.viewport
        return BakeSize(v[0], v[1])
    }
}

// MARK: - 곡선 측정

enum BakeCurves {
    struct Measured { let name: String; let formula: String; let times: [Double]; let values: [Double]; let maxAbsError: Double }

    static func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    static func easeIn(_ t: Double) -> Double { 2 * t * t - t * t * t }
    static func easeOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) * (1 + t) }
    static func keyframeEaseOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
    static func keyframeEaseInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

    /// 노드 하나에 실제 SCNAction 을 걸고 480Hz 로 밀어 값을 읽는다.
    @MainActor
    static func measure(device: MTLDevice, hz: Int) -> [Measured] {
        let scene = SCNScene()
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 5)
        scene.rootNode.addChildNode(cameraNode)
        renderer.pointOfView = cameraNode

        func run(_ build: (SCNNode) -> Void, read: (SCNNode) -> Double, duration: Double, base: Double) -> ([Double], [Double]) {
            let node = SCNNode()
            scene.rootNode.addChildNode(node)
            _ = renderer.snapshot(atTime: base, with: CGSize(width: 8, height: 8), antialiasingMode: .none)
            build(node)
            var ts: [Double] = [], vs: [Double] = []
            let steps = Int((duration * Double(hz)).rounded())
            for k in 0...steps {
                let t = Double(k) / Double(hz)
                _ = renderer.snapshot(atTime: base + t, with: CGSize(width: 8, height: 8), antialiasingMode: .none)
                ts.append(t / duration)
                vs.append(read(node))
            }
            node.removeFromParentNode()
            return (ts, vs)
        }

        func measured(_ name: String, _ formula: String, _ data: ([Double], [Double]), _ fn: (Double) -> Double) -> Measured {
            let err = zip(data.0, data.1).map { abs($1 - fn($0)) }.max() ?? 0
            return Measured(name: name, formula: formula, times: data.0, values: data.1, maxAbsError: err)
        }

        var results: [Measured] = []
        let modes: [(String, String, SCNActionTimingMode, (Double) -> Double)] = [
            ("easeInEaseOut", "3t^2-2t^3", .easeInEaseOut, smoothstep),
            ("easeIn", "2t^2-t^3", .easeIn, easeIn),
            ("easeOut", "1-(1-t)^2(1+t)", .easeOut, easeOut),
            ("linear", "t", .linear, { $0 })
        ]
        var base = 1000.0
        for (name, formula, mode, fn) in modes {
            let data = run({ node in
                let a = SCNAction.moveBy(x: 1, y: 0, z: 0, duration: 1.0)
                a.timingMode = mode
                node.runAction(a)
            }, read: { Double($0.position.x) }, duration: 1.0, base: base)
            results.append(measured(name, formula, data, fn))
            base += 10
        }
        // 시퀀스에 건 timingMode 는 시퀀스 전체 시간을 휜다(0.5s + 0.5s, 값 0…2 → 절반으로 나눠 0…1).
        let seq = run({ node in
            let s = SCNAction.sequence([.moveBy(x: 1, y: 0, z: 0, duration: 0.5), .moveBy(x: 1, y: 0, z: 0, duration: 0.5)])
            s.timingMode = .easeInEaseOut
            node.runAction(s)
        }, read: { Double($0.position.x) / 2 }, duration: 1.0, base: base)
        results.append(measured("sequenceEaseInEaseOut", "3t^2-2t^3 over the whole sequence", seq, smoothstep))
        base += 10
        // 그룹에 건 timingMode(졸기 · 기상 · 화들짝 — group 전체)도 같은 꼴인지.
        let group = run({ node in
            let g = SCNAction.group([.moveBy(x: 1, y: 0, z: 0, duration: 1.0), .rotateTo(x: 0, y: 1, z: 0, duration: 1.0)])
            g.timingMode = .easeInEaseOut
            node.runAction(g)
        }, read: { Double($0.eulerAngles.y) }, duration: 1.0, base: base)
        results.append(measured("groupEaseInEaseOut", "3t^2-2t^3 for every child of the group", group, smoothstep))
        base += 10
        // 앱의 축별 스케일 키프레임(customAction — SceneKit 곡선이 아니다).
        for (name, formula, timing, fn) in [("keyframeEaseOut", "1-(1-t)^2", SCNAction.ScaleTiming.easeOut, keyframeEaseOut),
                                            ("keyframeEaseInEaseOut", "t<.5 ? 2t^2 : 1-(-2t+2)^2/2", SCNAction.ScaleTiming.easeInEaseOut, keyframeEaseInOut)] {
            let data = run({ node in
                node.runAction(.scaleKeyframe(from: SCNVector3(1, 1, 1), to: SCNVector3(2, 1, 1), duration: 1.0, timing: timing))
            }, read: { Double($0.scale.x) - 1 }, duration: 1.0, base: base)
            results.append(measured(name, formula, data, fn))
            base += 10
        }
        return results
    }
}

// MARK: - 굽기 본체

@MainActor
final class Baker {
    let out: URL
    let config: BakeConfig
    let device: MTLDevice
    let hz: Int

    /// 원본 다이제스트(키 → sha256 hex). lock.json.raw 가 된다.
    var raw: [String: String] = [:]
    /// python 이 인코딩할 그림들.
    var images: [[String: Any]] = []
    var reports: [String: Any] = [:]
    var renderCounts: [Int: Int] = [:]
    var period2Goldens: [[String: Any]] = []
    var haloWorstPx = 0.0
    var haloCellMismatches = 0
    var alphaCells = AlphaStats()
    var alphaGoldens = AlphaStats()
    var alphaOther = AlphaStats()

    init(out: URL, config: BakeConfig, device: MTLDevice) {
        self.out = out
        self.config = config
        self.device = device
        self.hz = config.trackHz
    }

    // MARK: 공통 쓰기

    func write(_ object: Any, to relative: String) throws {
        let url = out.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: url)
    }

    static func sha256(_ bytes: [UInt8], w: Int, h: Int) -> String {
        var header = [UInt8]()
        for v in [UInt32(w), UInt32(h)] { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        var hasher = SHA256()
        hasher.update(data: header)
        hasher.update(data: bytes)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 자산 폴더에 그대로 들어갈 파일(JSON · 바이너리). python 이 files/ 아래를 자산 폴더로 옮긴다.
    func writeAsset(_ object: Any, to relative: String) throws {
        try write(object, to: "files/\(relative)")
    }

    func writeAsset(_ data: Data, to relative: String) throws {
        let url = out.appendingPathComponent("files/\(relative)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// 직선 RGBA 를 deflate 로 눌러 쓰고, python 이 PAM 으로 풀어 cwebp 로 인코딩한다.
    func emitImage(bytes: [UInt8], w: Int, h: Int, rawName: String, destination: String, mode: String) throws {
        let rawURL = out.appendingPathComponent("raw/\(rawName).rgba.z")
        try FileManager.default.createDirectory(at: rawURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let compressed = try (Data(bytes) as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: rawURL)
        images.append(["src": "raw/\(rawName).rgba.z", "w": w, "h": h, "dst": destination, "mode": mode,
                       "sha256": Self.sha256(bytes, w: w, h: h)])
    }

    // MARK: 실행

    func run() async throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let started = Date()

        // ① 장면 · 카메라
        let probe = try BakeRig(finish: .standard, device: device, animated: false)
        let camera = BakeCamera(world: BakeMath.d(probe.camera.simdWorldTransform),
                                fovDeg: Double(probe.camera.camera!.fieldOfView),
                                zNear: Double(probe.camera.camera!.zNear), zFar: Double(probe.camera.camera!.zFar),
                                verticalFov: probe.camera.camera!.projectionDirection == .vertical)
        let cameraDirection = simd_normalize(camera.position)
        let extent = probe.engineExtent
        try writeCamera(rig: probe, camera: camera, extent: extent)

        // ② 곡선
        let curves = BakeCurves.measure(device: device, hz: hz)
        for c in curves where c.maxAbsError >= 5e-5 { throw BakeError("곡선 \(c.name) 오차 \(c.maxAbsError)") }

        // ③ 트랙(진짜 엔진)
        let tracks = try await recordTracks(extent: extent)
        try writeMotion(tracks: tracks, curves: curves, extent: extent)
        try await writeParticles(extent: extent)
        try writeGlyph()

        // ④ 사용 기반 솎기
        let grid = BakeGrid.standard(config.grid)
        let culled = cull(grid: grid.cells, tracks: tracks, camera: camera)
        reports["F-9"] = culled.report.merging(["gridCells": grid.cells.count, "gridDuplicatesRemoved": grid.duplicates]) { a, _ in a }

        // ⑤ 칸 굽기(마감 3종)
        var manifests: [String: Any] = [:]
        var patchStats: [[String: Any]] = []
        for finish in BakeFinish.allCases {
            let (manifest, stats) = try bakeFinish(finish, sCells: culled.cells, camera: camera, cameraDirection: cameraDirection)
            manifests["\(finish.assetID)/manifest.json"] = manifest
            patchStats.append(stats)
        }
        reports["F-11"] = patchStats

        // ⑥ 골든
        let selector = BakeSelector(culled.cells)
        let closedSelector = BakeSelector(culled.cells.filter { BakeGrid.closedEyeCapable($0, config.grid) })
        try await bakeGoldens(tracks: tracks, camera: camera, selector: selector, closedSelector: closedSelector)

        // ⑦ 실험 보고(F-3 · F-4 · F-6 · F-13)
        // 실험은 실패도 결과다 — 굽기를 막지 않고 오류를 그대로 적는다.
        func attempt(_ body: () throws -> [String: Any]) -> [String: Any] {
            do { return try body() } catch { return ["error": "\(error)"] }
        }
        reports["F-3"] = attempt { try projectionReport(camera: camera) }
        reports["F-4"] = attempt { try billboardReport(camera: camera) }
        reports["F-13"] = attempt { try msaaReport() }
        do { reports["F-6"] = try await particleSemanticsReport() } catch { reports["F-6"] = ["error": "\(error)"] }

        reports["renders"] = ["stabilizeHistogram": renderCounts.sorted { $0.key < $1.key }.map { ["renders": $0.key, "count": $0.value] },
                              "alpha": ["cells": alphaCells.report, "goldens": alphaGoldens.report, "other": alphaOther.report],
                              "goldensPeriod2": period2Goldens,
                              "haloT4": ["maxQuadDiffPx": BakeMath.r6(haloWorstPx), "cellMismatches": haloCellMismatches],
                              "seconds": BakeMath.r6(Date().timeIntervalSince(started))]
        reports["windowsOwnedByProcess"] = AingBakeSuite.windowsOwnedByThisProcess()

        try write(["bakeFormat": config.bakeFormat,
                   "tool": ["gpu": device.name, "metalDeviceRegistryID": device.registryID.description],
                   "images": images,
                   "manifests": manifests,
                   "raw": raw,
                   "reports": reports], to: "plan.json")
    }

    // MARK: 카메라

    func writeCamera(rig: BakeRig, camera: BakeCamera, extent: Double) throws {
        var viewports: [String: Any] = [:]
        var worstProjectPointError = 0.0
        for (name, size) in [("S", config.size("S")), ("L", config.size("L")), ("U", config.size("U")), ("overlayPt", BakeSize(140, 170))] {
            // SceneKit projectPoint 와 내 투영이 같은지(bbox 8 모서리 + 원점) — 다르면 Kotlin 이 카메라를 다시 세울 수 없다.
            rig.resetPose()
            _ = renderer(rig, size: size)
            let (minB, maxB) = rig.character.boundingBox
            var points: [SIMD3<Double>] = [.zero]
            for x in [minB.x, maxB.x] { for y in [minB.y, maxB.y] { for z in [minB.z, maxB.z] { points.append(SIMD3(Double(x), Double(y), Double(z))) } } }
            for p in points {
                let mine = camera.project(p, size: size)
                let sk = rig.renderer.projectPoint(SCNVector3(p.x, p.y, p.z))
                let theirs = SIMD2(Double(sk.x), Double(size.h) - Double(sk.y))
                worstProjectPointError = max(worstProjectPointError, simd_length(mine - theirs))
            }
            viewports[name] = ["size": [size.w, size.h], "projection": BakeMath.list(camera.projectionMatrix(size: size))]
        }
        if worstProjectPointError > 0.01 { throw BakeError("투영 불일치 \(worstProjectPointError)px") }
        let box = rig.characterBox
        try write(["format": 1,
                   "worldTransform": BakeMath.list(camera.world),
                   "position": [camera.position.x, camera.position.y, camera.position.z].map(BakeMath.r6),
                   "fovDeg": camera.fovDeg, "fovAxis": camera.verticalFov ? "vertical" : "horizontal",
                   "zNear": camera.zNear, "zFar": camera.zFar,
                   "extent": BakeMath.r6(extent),
                   "bodyBox": ["min": [box.min.x, box.min.y, box.min.z].map(BakeMath.r6), "max": [box.max.x, box.max.y, box.max.z].map(BakeMath.r6)],
                   "pixelConvention": "top-left origin, continuous (pixel i covers [i, i+1))",
                   "matrixLayout": "column-major 4x4, 16 numbers, OpenGL clip space, camera looks down -z",
                   "projectPointMaxErrorPx": BakeMath.r6(worstProjectPointError),
                   "viewports": viewports], to: "files/camera.json")
    }

    /// projectPoint 가 쓰는 뷰포트를 맞추려고 한 번 그린다.
    @discardableResult
    func renderer(_ rig: BakeRig, size: BakeSize) -> BakeImage? {
        try? BakeRender.capture(rig.renderer, size: size, time: 0)
    }

    // MARK: 트랙

    struct Sample {
        var s: SIMD3<Double>
        var q: simd_quatd
        var p: SIMD3<Double>
        static func read(_ node: SCNNode) -> Sample {
            Sample(s: SIMD3<Double>(node.simdScale), q: simd_quatd(vector: SIMD4<Double>(node.simdOrientation.vector)),
                   p: SIMD3<Double>(node.simdPosition))
        }
        var matrix: simd_double4x4 {
            let r = simd_double3x3(q)
            let rs = simd_double3x3(columns: (r.columns.0 * s.x, r.columns.1 * s.y, r.columns.2 * s.z))
            return BakeMath.m4(rs, translation: p)
        }
    }

    struct Track {
        let name: String
        let variant: String          // "3d" · "flat" · "shared"
        let samples: [Sample]
        let positionUnits: String    // "extent" · "model"
        let extent: Double
        var extra: [String: Any] = [:]
        var duration: Double { Double(samples.count - 1) }
    }

    struct Tracks {
        var reactions: [String: Track] = [:]     // 3D 이름 → 트랙(위치는 model 단위 그대로, 직렬화 때 extent 로 나눈다)
        var flat: [String: Track] = [:]
        var idle: Track!
        var emitters: [String: Any] = [:]
        var zzz: [String: Any] = [:]
        var reactionTable: [[String: Any]] = []
        var sleepPose: Sample!
        var wakeCheck: [String: Any] = [:]
    }

    /// 리액션 하나를 진짜 엔진으로 걸고 480Hz 로 wrapper 모델 변환을 읽는다.
    func recordReaction(rig: BakeRig, start: inout Double, seconds: Double, trigger: () -> Void) -> [Sample] {
        rig.tick(start)
        trigger()
        var samples: [Sample] = []
        let steps = Int((seconds * Double(hz)).rounded(.up))
        for k in 0...steps {
            rig.tick(start + Double(k) / Double(hz))
            samples.append(Sample.read(rig.wrapper))
        }
        start += seconds + 10
        return samples
    }

    static let reactionKinds: [(name: String, kind: ReactionKind)] = [
        ("hit", .hit), ("commuteStart", .commuteStart), ("commuteEnd", .commuteEnd), ("milestone", .milestone),
        ("greeting", .greeting(name: "아잉")), ("poked", .poked(bubbleText: "콕!")), ("ultraPoked", .ultraPoked(bubbleText: "울트라!")),
        ("goalAchieved", .goalAchieved), ("ultraCharged", .ultraCharged), ("rubyReward", .rubyReward(amount: 20))
    ]

    static func bubbleSeconds(_ kind: ReactionKind) -> Double? {
        switch kind {
        case .hit: return ReactionEngine.hitBubbleSeconds
        case .commuteStart: return ReactionEngine.commuteStartBubbleSeconds
        case .commuteEnd: return ReactionEngine.commuteEndBubbleSeconds
        case .greeting: return ReactionEngine.greetingBubbleSeconds
        case .wake: return ReactionEngine.wakeBubbleSeconds
        case .poked: return ReactionEngine.pokedBubbleSeconds
        case .ultraPoked: return ReactionEngine.ultraPokedBubbleSeconds
        case .goalAchieved: return ReactionEngine.goalBubbleSeconds
        case .ultraCharged, .rubyReward: return ReactionEngine.ultraChargedBubbleSeconds
        case .milestone, .drowsy: return nil
        }
    }

    func makeEngine(rig: BakeRig, clock: BakeClock) -> ReactionEngine {
        let engine = ReactionEngine(clock: { clock.now })
        engine.zzzSleep = { _ in try? await Task.sleep(for: .seconds(1_000_000)) }
        engine.attach(node: rig.wrapper, sceneRoot: rig.scene.rootNode, view: nil)
        return engine
    }

    func settle(_ engine: ReactionEngine, rig: BakeRig, clock: BakeClock) {
        engine.cancelActiveReaction()
        engine.stopSleeping()
        clock.advance(100)
        rig.removeTransientNodes()
        rig.resetPose()
    }

    func recordTracks(extent: Double) async throws -> Tracks {
        var tracks = Tracks()
        let clock = BakeClock()
        let rig = try BakeRig(finish: .standard, device: device, animated: false)
        let engine = makeEngine(rig: rig, clock: clock)
        var t = 10.0

        for (name, kind) in Self.reactionKinds {
            settle(engine, rig: rig, clock: clock)
            guard let action = engine.reactionAction(for: kind) else { throw BakeError("\(name): 액션 없음") }
            var accepted = false
            let samples = recordReaction(rig: rig, start: &t, seconds: action.duration + 2.0 / Double(hz)) {
                accepted = engine.request(kind)
            }
            if !accepted { throw BakeError("\(name): 엔진이 거부했다") }
            let bubble = engine.greetingText
            // 방출구(파티클) 노드: 진짜 엔진이 씬 루트에 붙인 것을 읽는다.
            for node in rig.scene.rootNode.childNodes where (node.name ?? "").hasPrefix("check.reaction.") {
                tracks.emitters[node.name!] = ["positionModel": [Double(node.position.x), Double(node.position.y), Double(node.position.z)].map(BakeMath.r6),
                                               "positionExtent": [Double(node.position.x), Double(node.position.y), Double(node.position.z)].map { BakeMath.r6($0 / extent) },
                                               "reaction": name]
            }
            if name != "rubyReward" {
                tracks.reactions[name] = Track(name: name, variant: "3d", samples: samples, positionUnits: "extent", extent: extent,
                                               extra: ["actionDurationS": BakeMath.r6(action.duration)])
            }
            var row: [String: Any] = ["name": name, "priority": kind.priority, "durationS": kind.duration,
                                      "motionDurationS": BakeMath.r6(action.duration),
                                      "track": name == "rubyReward" ? "ultraCharged" : name]
            if let bubble { row["bubbleTextSample"] = bubble }
            if let s = Self.bubbleSeconds(kind) { row["bubbleSeconds"] = s }
            tracks.reactionTable.append(row)
        }

        // 보상 방출구 오므리기: ultraCharged 를 다시 걸고 방출구 노드의 scale 을 녹화한다.
        settle(engine, rig: rig, clock: clock)
        rig.tick(t)
        #expect(engine.request(.ultraCharged))
        var collapse: [Double] = []
        var removedAt: Double?
        for k in 0...Int(1.9 * Double(hz)) {
            rig.tick(t + Double(k) / Double(hz))
            if let node = rig.scene.rootNode.childNode(withName: "check.reaction.ultracharge", recursively: false) {
                collapse.append(BakeMath.r6(Double(node.scale.x)))
            } else if removedAt == nil {
                removedAt = Double(k) / Double(hz)
            }
        }
        t += 12
        tracks.emitters["ultraChargeCollapse"] = ["sampleHz": hz, "scale": collapse, "removedAtS": removedAt as Any]
        for (name, reaction) in [("check.reaction.confetti", ReactionKind.milestone), ("check.reaction.goalspark", .goalAchieved)] {
            settle(engine, rig: rig, clock: clock)
            rig.tick(t)
            #expect(engine.request(reaction))
            var gone: Double?
            for k in 0...Int(2.6 * Double(hz)) {
                rig.tick(t + Double(k) / Double(hz))
                if gone == nil, rig.scene.rootNode.childNode(withName: name, recursively: false) == nil { gone = Double(k) / Double(hz) }
            }
            t += 13
            var entry = tracks.emitters[name] as? [String: Any] ?? [:]
            entry["removedAtS"] = gone as Any
            tracks.emitters[name] = entry
        }

        // 졸기: 가라앉기(2.0s) + 유지 자세, 💤 버스트, 화들짝 기상 · 조용한 기상.
        settle(engine, rig: rig, clock: clock)
        rig.tick(t)
        #expect(engine.request(.drowsy))
        for _ in 0..<20 { await Task.yield() }
        let sinkSeconds = engine.drowsySinkAction().duration
        var sink: [Sample] = []
        var zzzContainer: SCNNode?
        var zNodes: [SCNNode] = []
        var zFloats: [Float] = []
        var zCount = 0
        var containerGone: Double?
        let zzzSteps = Int(3.1 * Double(hz))
        for k in 0...max(zzzSteps, Int((sinkSeconds * Double(hz)).rounded(.up)) + 2) {
            rig.tick(t + Double(k) / Double(hz))
            if Double(k) <= sinkSeconds * Double(hz) + 2 { sink.append(Sample.read(rig.wrapper)) }
            if zzzContainer == nil, let found = rig.scene.rootNode.childNode(withName: "check.reaction.zzz", recursively: false) {
                zzzContainer = found
                zNodes = found.childNodes      // 처음 본 순간의 세 노드를 붙든다(지워지면 자식 번호가 당겨지므로 번호로 읽지 않는다)
            }
            if let container = zzzContainer, k <= zzzSteps {
                if container.parent == nil, containerGone == nil { containerGone = Double(k) / Double(hz) }
                for z in zNodes {
                    if z.parent == nil {
                        zFloats.append(contentsOf: [0, 0, 0, -1])   // 지워졌다
                    } else {
                        zFloats.append(contentsOf: [Float(Double(z.position.x) / extent), Float(Double(z.position.y) / extent),
                                                    Float(Double(z.position.z) / extent), Float(z.opacity)])
                    }
                }
                zCount += 1
            }
        }
        guard let container = zzzContainer, zNodes.count == 3 else { throw BakeError("💤 버스트가 안 나왔다(엔진 zzz 루프가 안 돌았다)") }
        try writeAsset(zFloats.withUnsafeBufferPointer { Data(buffer: $0) }, to: "tracks/zzz.f32")
        tracks.zzz = ["sampleHz": hz, "count": zCount, "file": "tracks/zzz.f32",
                      "layout": "float32le[count][3 Z nodes][4] = position xyz (extent units, local to the container), opacity; opacity -1 = node removed",
                      "containerPositionExtent": [Double(container.position.x), Double(container.position.y), Double(container.position.z)].map { BakeMath.r6($0 / extent) },
                      "zScaleExtent": BakeMath.r6(Double(ReactionActions.makeZNode(extent: 1).scale.x)),
                      "containerRemovedAtS": containerGone as Any, "intervalS": ReactionEngine.zzzIntervalSeconds]
        tracks.reactions["drowsySink"] = Track(name: "drowsySink", variant: "3d", samples: sink, positionUnits: "extent", extent: extent,
                                               extra: ["holdsEnd": true, "actionDurationS": BakeMath.r6(sinkSeconds)])
        tracks.sleepPose = sink.last
        t += 14

        // 화들짝(현재 자세에서 출발): 스냅 0.15 easeOut 은 공식, 되튀기만 트랙.
        for (name, wakeKind) in [("wake", 0), ("quietRise", 1)] {
            settle(engine, rig: rig, clock: clock)
            rig.tick(t)
            #expect(engine.request(.drowsy))
            let sinkSteps = Int((sinkSeconds * Double(hz)).rounded(.up)) + 2
            for k in 0...sinkSteps { rig.tick(t + Double(k) / Double(hz)) }
            let wakeStart = t + Double(sinkSteps + 1) / Double(hz)
            let from = Sample.read(rig.wrapper)
            let fromEuler = SIMD3<Double>(rig.wrapper.simdEulerAngles)
            let seconds = wakeKind == 0 ? ReactionActions.wake(tilt: extent * 0.18).duration : ReactionActions.drowsyRise().duration
            var start = wakeStart
            let samples = recordReaction(rig: rig, start: &start, seconds: seconds + 2.0 / Double(hz)) {
                if wakeKind == 0 { _ = engine.request(.wake) } else { engine.wakeQuietly() }
            }
            t = start
            // 공식(오일러 성분별 선형 · 위치 선형 × 곡선)과의 최대 오차.
            let snapSeconds = wakeKind == 0 ? 0.15 : seconds
            func curve(_ x: Double) -> Double { wakeKind == 0 ? BakeCurves.easeOut(x) : BakeCurves.smoothstep(x) }
            var worstAngle = 0.0, worstPos = 0.0
            for (k, s) in samples.enumerated() {
                let tt = Double(k) / Double(hz)
                guard tt <= snapSeconds else { break }
                let c = curve(min(1, tt / snapSeconds))
                let e = fromEuler * (1 - c)
                let predicted = Self.quat(euler: e)
                worstAngle = max(worstAngle, BakeMath.deg(Self.angle(predicted, s.q)))
                worstPos = max(worstPos, simd_length(from.p * (1 - c) - s.p))
            }
            tracks.wakeCheck[name] = ["toIdentitySeconds": snapSeconds, "curve": wakeKind == 0 ? "easeOut" : "easeInEaseOut",
                                      "maxAngleErrorDeg": BakeMath.r6(worstAngle), "maxPositionErrorModel": BakeMath.r6(worstPos)]
            if wakeKind == 0 {
                // 되튀기: 스냅 뒤(0.15s~)만 트랙으로.
                let bounceFrom = Int((0.15 * Double(hz)).rounded())
                tracks.reactions["wakeBounce"] = Track(name: "wakeBounce", variant: "3d", samples: Array(samples[bounceFrom...]),
                                                       positionUnits: "extent", extent: extent,
                                                       extra: ["startsAfterToIdentityS": 0.15])
                tracks.reactions["wake"] = Track(name: "wake", variant: "3d", samples: samples, positionUnits: "extent", extent: extent,
                                                 extra: ["startsFrom": "sleepPose", "note": "golden/cull only; runtime uses toIdentity + wakeBounce"])
            } else {
                tracks.reactions["quietRise"] = Track(name: "quietRise", variant: "3d", samples: samples, positionUnits: "extent", extent: extent,
                                                      extra: ["startsFrom": "sleepPose", "note": "golden/cull only; runtime uses toIdentity"])
            }
            if worstAngle > 0.05 || worstPos > 1e-4 * extent {
                throw BakeError("\(name): toIdentity 공식과 어긋난다(각 \(worstAngle)° · 위치 \(worstPos))")
            }
        }
        settle(engine, rig: rig, clock: clock)
        tracks.reactionTable.append(["name": "drowsy", "priority": ReactionKind.drowsy.priority, "durationS": ReactionKind.drowsy.duration,
                                     "motionDurationS": BakeMath.r6(sinkSeconds), "track": "drowsySink", "holdsEnd": true])
        tracks.reactionTable.append(["name": "wake", "priority": ReactionKind.wake.priority, "durationS": ReactionKind.wake.duration,
                                     "toIdentity": ["seconds": 0.15, "curve": "easeOut"], "track": "wakeBounce",
                                     "bubbleSeconds": ReactionEngine.wakeBubbleSeconds])
        tracks.reactionTable.append(["name": "quietRise", "toIdentity": ["seconds": ReactionActions.drowsyRise().duration, "curve": "easeInEaseOut"]])

        // 평면판(스프라이트) 트랙: 진짜 엔진을 스프라이트 장면에 붙이면 flat 갈래를 고른다.
        let catalog = CheckCharacter3DScene.catalog
        let shiba = try #require(catalog.manifest(id: "shiba"), "번들에 shiba 가 없다")
        let atlas = try #require(CheckCharacter3DScene.atlasImage(for: shiba))
        let spriteScene = try #require(CheckCharacter3DScene.makeScene(animated: false, character: shiba, atlas: atlas))
        let spriteWrapper = try #require(spriteScene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
        let spriteRenderer = SCNRenderer(device: device, options: nil)
        spriteRenderer.scene = spriteScene
        let spriteClock = BakeClock()
        let spriteEngine = ReactionEngine(clock: { spriteClock.now })
        spriteEngine.zzzSleep = { _ in try? await Task.sleep(for: .seconds(1_000_000)) }
        spriteEngine.attach(node: spriteWrapper, sceneRoot: spriteScene.rootNode, view: nil)
        guard spriteEngine.isSpriteCharacter else { throw BakeError("스프라이트 엔진이 3D 로 본다") }
        let (sMin, sMax) = spriteWrapper.boundingBox
        let spriteExtent = Double(max(sMax.x - sMin.x, max(sMax.y - sMin.y, sMax.z - sMin.z)))
        var st = 10.0
        for (name, kind) in [("commuteStart", ReactionKind.commuteStart), ("commuteEnd", .commuteEnd),
                             ("poked", .poked(bubbleText: "콕!")), ("goalAchieved", .goalAchieved), ("drowsySink", .drowsy)] {
            spriteEngine.cancelActiveReaction()
            spriteEngine.stopSleeping()
            spriteClock.advance(100)
            spriteWrapper.removeAllActions()
            spriteWrapper.simdTransform = matrix_identity_float4x4
            let seconds = kind == .drowsy ? spriteEngine.drowsySinkAction().duration : spriteEngine.reactionAction(for: kind)!.duration
            _ = spriteRenderer.snapshot(atTime: st, with: CGSize(width: 8, height: 8), antialiasingMode: .none)
            if kind == .drowsy {
                #expect(spriteEngine.request(kind))        // 졸기 진입은 drowsySinkAction()(평면 갈림길 있음)을 탄다
            } else {
                // ⚠️ 엔진의 `request` → `perform` 은 지금 평면 갈림길을 거치지 않고 3D 동작(y 스핀 · x 숙임)을 스프라이트에도 건다
                //    (CheckOverlayReactions.swift perform — 갈림길은 attach 재생 경로의 `reactionAction(for:)` 에만 있다). 평면판 트랙은
                //    설계된 동작(사용자 결정 2026-09-13)을 담아야 하므로 엔진 자신의 갈림길 함수가 돌려준 액션을 그대로 건다.
                guard let flatAction = spriteEngine.reactionAction(for: kind) else { throw BakeError("\(name).flat: 액션 없음") }
                spriteWrapper.runAction(flatAction, forKey: "check.reaction", completionHandler: nil)
            }
            var samples: [Sample] = []
            for k in 0...Int(((seconds + 2.0 / Double(hz)) * Double(hz)).rounded(.up)) {
                _ = spriteRenderer.snapshot(atTime: st + Double(k) / Double(hz), with: CGSize(width: 8, height: 8), antialiasingMode: .none)
                samples.append(Sample.read(spriteWrapper))
            }
            st += seconds + 10
            // 평면판 계약: x · y 회전이 한 톨도 없다.
            // (쿼터니언의 x·y 성분이 0 = 회전축이 z 뿐. 오일러 역산은 같은 회전을 (π, π, π−θ) 로도 돌려줄 수 있어 쓰지 않는다.)
            for s in samples where abs(s.q.vector.x) > 1e-6 || abs(s.q.vector.y) > 1e-6 {
                throw BakeError("\(name).flat 에 x/y 회전이 있다(q = \(s.q.vector))")
            }
            tracks.flat[name] = Track(name: name, variant: "flat", samples: samples, positionUnits: "extent", extent: spriteExtent,
                                      extra: ["recordedOn": "shiba", "actionDurationS": BakeMath.r6(seconds),
                                              "source": kind == .drowsy ? "ReactionEngine.request(.drowsy)" : "ReactionEngine.reactionAction(for:) on a sprite engine"])
        }
        spriteEngine.stopSleeping()

        // idle(부유 · 살랑) 한 바퀴 14.4s — 진짜 addIdleAnimations(animated: true 장면)의 캐릭터 노드.
        let idleRig = try BakeRig(finish: .standard, device: device, animated: true)
        let cycle = 14.4
        var idle: [Sample] = []
        let idleSteps = Int((cycle * Double(hz)).rounded())
        for k in 0..<idleSteps {
            idleRig.tick(50 + Double(k) / Double(hz))
            idle.append(Sample.read(idleRig.character))
        }
        idleRig.tick(50 + cycle)
        let wrap = Sample.read(idleRig.character)
        let idleWrapError = max(simd_length(wrap.p - idle[0].p), BakeMath.deg(Self.angle(wrap.q, idle[0].q)))
        // 공식과의 오차(부유 0.07 · smoothstep 1.8s 왕복, 살랑 ±0.14rad 3.6/7.2/3.6 smoothstep).
        var idleWorst = 0.0
        for (k, s) in idle.enumerated() {
            let (bob, sway) = Self.idleFormula(Double(k) / Double(hz))
            idleWorst = max(idleWorst, abs(s.p.y - bob), abs(2 * atan2(s.q.vector.y, s.q.vector.w) - sway), abs(s.q.vector.x) + abs(s.q.vector.z))
        }
        tracks.idle = Track(name: "idle", variant: "shared", samples: idle, positionUnits: "model", extent: 1,
                            extra: ["cycleS": cycle, "wrapErrorAfterCycle": BakeMath.r6(idleWrapError), "maxFormulaError": BakeMath.r6(idleWorst),
                                    "bob": ["amplitudeModel": 0.07, "halfPeriodS": 1.8, "curve": "easeInEaseOut", "startsGoing": "up"],
                                    "sway": ["amplitudeRad": Double(CheckCharacter3DScene.idleSwayRadians), "segmentsS": [3.6, 7.2, 3.6],
                                             "segmentsRad": [0.14, -0.28, 0.14], "curve": "easeInEaseOut"]])
        if idleWorst > 1e-4 { throw BakeError("idle 이 공식과 어긋난다(\(idleWorst))") }
        return tracks
    }

    static func idleFormula(_ t: Double) -> (bob: Double, sway: Double) {
        let b = t.truncatingRemainder(dividingBy: 3.6)
        let bob = b < 1.8 ? 0.07 * BakeCurves.smoothstep(b / 1.8) : 0.07 * (1 - BakeCurves.smoothstep((b - 1.8) / 1.8))
        let s = t.truncatingRemainder(dividingBy: 14.4)
        let a = Double(CheckCharacter3DScene.idleSwayRadians)
        let sway: Double
        if s < 3.6 { sway = a * BakeCurves.smoothstep(s / 3.6) }
        else if s < 10.8 { sway = a - 2 * a * BakeCurves.smoothstep((s - 3.6) / 7.2) }
        else { sway = -a + a * BakeCurves.smoothstep((s - 10.8) / 3.6) }
        return (bob, sway)
    }

    static func euler(_ q: simd_quatd) -> SIMD3<Double> {
        let node = SCNNode()
        node.simdOrientation = simd_quatf(vector: SIMD4<Float>(q.vector))
        return SIMD3<Double>(node.simdEulerAngles)
    }

    static func quat(euler e: SIMD3<Double>) -> simd_quatd {
        let node = SCNNode()
        node.simdEulerAngles = SIMD3<Float>(e)
        return simd_quatd(vector: SIMD4<Double>(node.simdOrientation.vector))
    }

    static func angle(_ a: simd_quatd, _ b: simd_quatd) -> Double {
        let d = abs(simd_dot(a.vector, b.vector))
        return 2 * acos(min(1, d))
    }

    // MARK: motion.json

    func encodeTrack(_ track: Track, fileName: String) throws -> [String: Any] {
        var floats: [Float] = []
        floats.reserveCapacity(track.samples.count * 10)
        var previous: simd_quatd?
        for s in track.samples {
            var q = s.q
            if let prev = previous, simd_dot(prev.vector, q.vector) < 0 { q = simd_quatd(vector: -q.vector) }
            previous = q
            let p = track.positionUnits == "extent" ? s.p / track.extent : s.p
            floats.append(contentsOf: [Float(s.s.x), Float(s.s.y), Float(s.s.z), Float(q.vector.x), Float(q.vector.y), Float(q.vector.z), Float(q.vector.w),
                                       Float(p.x), Float(p.y), Float(p.z)])
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }   // 리틀엔디언(arm64)
        try writeAsset(data, to: "tracks/\(fileName).f32")
        var out: [String: Any] = ["variant": track.variant, "sampleHz": hz, "count": track.samples.count,
                                  "durationS": BakeMath.r6(Double(track.samples.count - 1) / Double(hz)),
                                  "positionUnits": track.positionUnits, "recordedExtent": BakeMath.r6(track.extent),
                                  "layout": "float32le[count][10] = scale xyz, quaternion xyzw, position xyz",
                                  "file": "tracks/\(fileName).f32"]
        for (k, v) in track.extra { out[k] = v }
        return out
    }

    func writeMotion(tracks: Tracks, curves: [BakeCurves.Measured], extent: Double) throws {
        var trackObjects: [String: Any] = [:]
        for (name, track) in tracks.reactions { trackObjects[name] = try encodeTrack(track, fileName: name) }
        for (name, track) in tracks.flat { trackObjects["\(name).flat"] = try encodeTrack(track, fileName: "\(name).flat") }
        trackObjects["idle"] = try encodeTrack(tracks.idle, fileName: "idle")
        let sleep = tracks.sleepPose!
        try write(["format": 1,
                   "sampleHz": hz,
                   "extent": BakeMath.r6(extent),
                   "curves": curves.map { ["name": $0.name, "formula": $0.formula, "maxAbsError": $0.maxAbsError] },
                   "tracks": trackObjects,
                   "reactions": tracks.reactionTable,
                   "emitters": tracks.emitters,
                   "zzz": tracks.zzz,
                   "toIdentityCheck": tracks.wakeCheck,
                   "sleepPose": ["scale": [sleep.s.x, sleep.s.y, sleep.s.z].map(BakeMath.r6),
                                 "quaternion": [sleep.q.vector.x, sleep.q.vector.y, sleep.q.vector.z, sleep.q.vector.w].map(BakeMath.r6),
                                 "positionExtent": [sleep.p.x / extent, sleep.p.y / extent, sleep.p.z / extent].map(BakeMath.r6)],
                   "engine": ["idleFPS": ReactionEngine.idleFPS, "activeFPS": ReactionEngine.activeFPS, "blinkSeconds": ReactionEngine.blinkSeconds,
                              "hitCooldownS": ReactionEngine.hitCooldown, "dragFacingDeg": BakeMath.r6(BakeMath.deg(Double(ReactionEngine.dragFacingAngle))),
                              "zzzIntervalS": ReactionEngine.zzzIntervalSeconds, "walkStopTimeoutS": ReactionEngine.walkStopTimeout,
                              "spriteTickIntervalS": ReactionEngine.spriteTickInterval, "fpsResetAfterS": 0.1]],
                  to: "files/motion.json")
    }

    // MARK: particles.json

    static func colorComponents(_ color: NSColor, appearance: NSAppearance.Name) -> [Double] {
        var out: [Double] = []
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            if let c = color.usingColorSpace(.sRGB) {
                out = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { BakeMath.r6(Double($0)) }
            }
        }
        return out
    }

    static func describe(_ system: SCNParticleSystem) -> [String: Any] {
        var shape: [String: Any] = ["type": "none"]
        if let sphere = system.emitterShape as? SCNSphere { shape = ["type": "sphere", "radius": BakeMath.r6(Double(sphere.radius))] }
        if let cylinder = system.emitterShape as? SCNCylinder {
            shape = ["type": "cylinder", "radius": BakeMath.r6(Double(cylinder.radius)), "height": BakeMath.r6(Double(cylinder.height))]
        }
        let blend: [SCNParticleBlendMode: String] = [.additive: "additive", .subtract: "subtract", .multiply: "multiply",
                                                    .screen: "screen", .alpha: "alpha", .replace: "replace"]
        let direction: [SCNParticleBirthDirection: String] = [.constant: "constant", .surfaceNormal: "surfaceNormal", .random: "random"]
        let location: [SCNParticleBirthLocation: String] = [.surface: "surface", .volume: "volume", .vertex: "vertex"]
        let v = system.particleColorVariation
        return [
            "birthRate": Double(system.birthRate), "birthRateVariation": Double(system.birthRateVariation),
            "emissionDurationS": Double(system.emissionDuration), "emissionDurationVariation": Double(system.emissionDurationVariation),
            "loops": system.loops, "warmupDurationS": Double(system.warmupDuration), "idleDurationS": Double(system.idleDuration),
            "lifeSpanS": Double(system.particleLifeSpan), "lifeSpanVariation": Double(system.particleLifeSpanVariation),
            "size": Double(system.particleSize), "sizeVariation": Double(system.particleSizeVariation),
            "velocity": Double(system.particleVelocity), "velocityVariation": Double(system.particleVelocityVariation),
            "spreadingAngleDeg": Double(system.spreadingAngle),
            "emitterShape": shape,
            "birthDirection": direction[system.birthDirection] ?? "\(system.birthDirection.rawValue)",
            "birthLocation": location[system.birthLocation] ?? "\(system.birthLocation.rawValue)",
            "emittingDirection": [system.emittingDirection.x, system.emittingDirection.y, system.emittingDirection.z].map { BakeMath.r6(Double($0)) },
            "acceleration": [system.acceleration.x, system.acceleration.y, system.acceleration.z].map { BakeMath.r6(Double($0)) },
            "colorSRGB": ["aqua": colorComponents(system.particleColor, appearance: .aqua),
                          "darkAqua": colorComponents(system.particleColor, appearance: .darkAqua)],
            "colorVariation": [v.x, v.y, v.z, v.w].map { BakeMath.r6(Double($0)) },
            "angle": Double(system.particleAngle), "angleVariation": Double(system.particleAngleVariation),
            "angularVelocity": Double(system.particleAngularVelocity), "angularVelocityVariation": Double(system.particleAngularVelocityVariation),
            "blendMode": blend[system.blendMode] ?? "\(system.blendMode.rawValue)",
            "isLightingEnabled": system.isLightingEnabled,
            "particleImage": system.particleImage == nil ? "nil(default)" : "custom",
            "dampingFactor": Double(system.dampingFactor), "speedFactor": Double(system.speedFactor),
            "stretchFactor": Double(system.stretchFactor), "isAffectedByGravity": system.isAffectedByGravity,
            "orientationMode": system.orientationMode.rawValue, "sortingMode": system.sortingMode.rawValue,
            "fresnelExponent": Double(system.fresnelExponent), "isBlackPassEnabled": system.isBlackPassEnabled
        ]
    }

    func writeParticles(extent: Double) async throws {
        // 진짜 엔진이 방출구에 붙인 시스템을 그대로 읽는다(손으로 옮겨 적지 않는다).
        let clock = BakeClock()
        let rig = try BakeRig(finish: .standard, device: device, animated: false)
        let engine = makeEngine(rig: rig, clock: clock)
        var systems: [String: Any] = [:]
        var t = 10.0
        for (key, name, kind) in [("confetti", "check.reaction.confetti", ReactionKind.milestone),
                                  ("goalSpark", "check.reaction.goalspark", .goalAchieved),
                                  ("ultraCharge", "check.reaction.ultracharge", .ultraCharged)] {
            settle(engine, rig: rig, clock: clock)
            rig.tick(t)
            #expect(engine.request(kind))
            guard let node = rig.scene.rootNode.childNode(withName: name, recursively: false),
                  let system = node.particleSystems?.first else { throw BakeError("\(key): 방출구가 없다") }
            var d = Self.describe(system)
            d["emitterPositionExtent"] = [node.position.x, node.position.y, node.position.z].map { BakeMath.r6(Double($0) / extent) }
            d["attachedTo"] = "sceneRoot"
            systems[key] = d
            t += 20
        }
        settle(engine, rig: rig, clock: clock)
        try write(["format": 1, "systems": systems,
                   "note": "read from SCNParticleSystem instances that the real ReactionEngine attached; colors resolved under aqua and darkAqua; F-6 semantics in plan reports"],
                  to: "files/particles.json")
    }

    // MARK: 💤 글리프

    func writeGlyph() throws {
        let text = try #require(ReactionActions.makeZNode(extent: 1).geometry as? SCNText)
        let scene = SCNScene()
        scene.background.contents = nil
        let node = SCNNode(geometry: text)
        scene.rootNode.addChildNode(node)
        let (minB, maxB) = text.boundingBox
        let cx = Double(minB.x + maxB.x) / 2, cy = Double(minB.y + maxB.y) / 2
        let half = max(Double(maxB.x - minB.x), Double(maxB.y - minB.y)) / 2 * 1.08
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true
        cam.camera!.orthographicScale = half
        cam.camera!.zNear = 0.01
        cam.camera!.zFar = 100
        cam.position = SCNVector3(cx, cy, 10)
        scene.rootNode.addChildNode(cam)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cam
        renderer.autoenablesDefaultLighting = false
        let size = BakeSize(512, 512)
        let (img, n) = try BakeRender.stable(renderer, size: size, time: 0)
        renderCounts[n, default: 0] += 1
        let straight = img.straightened()
        alphaOther.add(straight.stats)
        raw["glyph-z"] = Self.sha256(straight.bytes, w: size.w, h: size.h)
        try emitImage(bytes: straight.bytes, w: size.w, h: size.h, rawName: "glyph-z", destination: "glyph-z.webp", mode: "lossless")
        let unitsPerPixel = 2 * half / Double(size.h)
        reports["glyph"] = ["file": "glyph-z.webp", "sizePx": [512, 512],
                            "localBoxMin": [Double(minB.x), Double(minB.y)].map(BakeMath.r6), "localBoxMax": [Double(maxB.x), Double(maxB.y)].map(BakeMath.r6),
                            "imageTopLeftLocal": [cx - half, cy + half].map(BakeMath.r6), "unitsPerPixel": BakeMath.r6(unitsPerPixel),
                            "material": "white alpha 0.85, unlit, double sided; node scale = extent*0.12"]
    }

    // MARK: 사용 기반 솎기

    struct CullResult { let cells: [BakeCell]; let report: [String: Any] }

    func cull(grid: [BakeCell], tracks: Tracks, camera: BakeCamera) -> CullResult {
        let selector = BakeSelector(grid)
        let closedCells = grid.enumerated().filter { BakeGrid.closedEyeCapable($0.element, config.grid) }
        let closedSelector = BakeSelector(closedCells.map(\.element))
        let closedIndex = closedCells.map(\.offset)
        var used = Set<Int>()
        let cam = camera.position
        let c = config.cull
        let stride2 = max(1, hz / c.simHz)
        let idle = tracks.idle.samples
        let phaseStep = Int((c.swayPhaseStepS * Double(hz)).rounded())
        var perTrack: [[String: Any]] = []
        var totalSamples = 0, totalMisses = 0

        func tolerance(_ speed: Double) -> Double {
            if speed < c.slowDegPerS { return c.slowTolDeg }
            if speed >= c.fastDegPerS { return c.fastTolDeg }
            return c.slowTolDeg + (speed - c.slowDegPerS) / (c.fastDegPerS - c.slowDegPerS) * (c.fastTolDeg - c.slowTolDeg)
        }

        // (이름, wrapper 표본, 눈 감김, 위상 수)
        var jobs: [(String, [Sample], Bool, Int)] = []
        for name in tracks.reactions.keys.sorted() where name != "wakeBounce" {
            jobs.append((name, tracks.reactions[name]!.samples, name == "drowsySink", c.swayPhases))
        }
        // 졸음 유지(가라앉은 자세 + idle 한 바퀴) · 서 있기(idle 한 바퀴, 깜빡임 = 감은 눈도).
        jobs.append(("sleepHold", Array(repeating: tracks.sleepPose, count: idle.count), true, 1))
        jobs.append(("rest", Array(repeating: Sample(s: SIMD3(1, 1, 1), q: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), p: .zero), count: idle.count), false, 1))
        jobs.append(("restBlink", Array(repeating: Sample(s: SIMD3(1, 1, 1), q: simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), p: .zero), count: idle.count), true, 1))

        let idleMatrices = idle.map(\.matrix)
        for (name, samples, closed, phases) in jobs {
            var misses = 0, count = 0, worst = 0.0, worstSpeed = 0.0
            let wrapperMatrices = samples.map(\.matrix)
            for facing in c.facingsDeg {
                let facingM = BakeMath.m4(simd_double3x3(simd_quatd(angle: BakeMath.rad(facing), axis: SIMD3(0, 1, 0))))
                let wf = wrapperMatrices.map { $0 * facingM }
                for phase in 0..<phases {
                    var previous: SIMD3<Double>?
                    for k in stride(from: 0, to: samples.count, by: stride2) {
                        // body = W · Ry(facing) · C(idle)
                        let body = wf[k] * idleMatrices[(phase * phaseStep + k) % idle.count]
                        let n = BakeMath.viewDirection(bodyWorld: body, camera: cam)
                        let pick: (index: Int, angle: Double)
                        if closed {
                            let r = closedSelector.nearest(n)
                            pick = (closedIndex[r.index], r.angle)
                        } else {
                            pick = selector.nearest(n)
                        }
                        used.insert(pick.index)
                        let speed = previous.map { BakeMath.angleDeg($0, n) * Double(c.simHz) } ?? 0
                        previous = n
                        worstSpeed = max(worstSpeed, speed)
                        if pick.angle > tolerance(speed) { misses += 1 }
                        worst = max(worst, pick.angle)
                        count += 1
                    }
                }
            }
            totalSamples += count
            totalMisses += misses
            perTrack.append(["track": name, "samples": count, "overTolerance": misses, "worstAngleDeg": BakeMath.r6(worst),
                             "peakSpeedDegPerS": BakeMath.r6(worstSpeed), "eyesClosed": closed])
        }
        // 30°×10° 성긴 안전망.
        var safety = Set<Int>()
        for tilt in c.safetyTilts {
            for k in 0..<(360 / c.safetyYawStep) {
                let n = BakeMath.cellDirection(yawDeg: Double(BakeCell.normalizeYaw(k * c.safetyYawStep)), tiltDeg: tilt)
                safety.insert(selector.nearest(n).index)
            }
        }
        let keep = used.union(safety)
        let cells = BakeGrid.sorted(keep.map { grid[$0] })
        var byGroup: [String: Any] = [:]
        for g in [BakeCell.Group.rest, .band, .spin] {
            byGroup[g.rawValue] = ["grid": grid.filter { $0.group == g }.count, "kept": cells.filter { $0.group == g }.count,
                                   "used": used.filter { grid[$0].group == g }.count]
        }
        return CullResult(cells: cells, report: [
            "usedBySimulation": used.count, "safetyNet": safety.count, "safetyOnly": safety.subtracting(used).count,
            "kept": cells.count, "keptRatio": BakeMath.r6(Double(cells.count) / Double(grid.count)),
            "reductionRatio": BakeMath.r6(1 - Double(cells.count) / Double(grid.count)),
            "byGroup": byGroup, "samples": totalSamples, "samplesOverTolerance": totalMisses, "perTrack": perTrack
        ])
    }

    // MARK: 칸 굽기

    struct CellRender {
        let cell: BakeCell
        let crop: BakeImage           // 프리멀티
        let straight: [UInt8]
        let originX: Int, originY: Int
        let quad: [[Double]]
        let pivot: [Double]
        var patch: (straight: [UInt8], w: Int, h: Int, atX: Int, atY: Int)?
    }

    func renderCell(_ cell: BakeCell, rig: BakeRig, size: BakeSize, camera: BakeCamera, cameraDirection: SIMD3<Double>,
                    patch: Bool) throws -> CellRender {
        rig.resetPose()
        let r = BakeMath.cellRotation(yawDeg: Double(cell.yaw), tiltDeg: cell.tilt, cameraDirection: cameraDirection)
        rig.wrapper.simdTransform = BakeMath.f(BakeMath.m4(r))
        try rig.setEyes(closed: false)
        let (open, n) = try BakeRender.stable(rig.renderer, size: size, time: 0, minimum: config.stabilizeMin, maximum: config.stabilizeMax)
        renderCounts[n, default: 0] += 1
        guard let box = open.alphaBox() else { throw BakeError("\(cell.id): 빈 렌더") }
        let m = config.cellMarginPx
        if box.x0 - m < 0 || box.y0 - m < 0 || box.x1 + m >= size.w || box.y1 + m >= size.h {
            throw BakeError("\(cell.id): 몸이 뷰포트 끝에 닿는다 — 잘린 칸")
        }
        let ox = box.x0 - m, oy = box.y0 - m
        let crop = open.crop(x: ox, y: oy, w: box.x1 - box.x0 + 1 + 2 * m, h: box.y1 - box.y0 + 1 + 2 * m)
        let straight = crop.straightened()
        alphaCells.add(straight.stats)

        // 4점: 몸 국소 피벗 ± h·r ± h·u (r·u ⟂ n) → 화면 → 칸 좌표. 순서 TL · TR · BR · BL.
        let nLocal = cell.direction
        let up = SIMD3<Double>(0, 1, 0)
        let rl = simd_normalize(simd_cross(up, nLocal)), ul = simd_cross(nLocal, rl)
        let h = config.quadHalfUnits
        let quad = [(-1.0, 1.0), (1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)].map { sx, sy -> [Double] in
            let local = rl * (sx * h) + ul * (sy * h)
            let world = r * local
            let p = camera.project(world, size: size)
            return [BakeMath.r3(p.x - Double(ox)), BakeMath.r3(p.y - Double(oy))]
        }
        let pv = camera.project(.zero, size: size)
        var result = CellRender(cell: cell, crop: crop, straight: straight.bytes, originX: ox, originY: oy, quad: quad,
                                pivot: [BakeMath.r3(pv.x - Double(ox)), BakeMath.r3(pv.y - Double(oy))], patch: nil)
        if patch {
            try rig.setEyes(closed: true)
            let (closed, n2) = try BakeRender.stable(rig.renderer, size: size, time: 0, minimum: config.stabilizeMin, maximum: config.stabilizeMax)
            renderCounts[n2, default: 0] += 1
            try rig.setEyes(closed: false)
            if let d = open.diffBox(closed) {
                let pm = config.patchMarginPx
                let x0 = max(ox, d.x0 - pm), y0 = max(oy, d.y0 - pm)
                let x1 = min(ox + crop.w - 1, d.x1 + pm), y1 = min(oy + crop.h - 1, d.y1 + pm)
                if d.x0 < ox || d.y0 < oy || d.x1 > ox + crop.w - 1 || d.y1 > oy + crop.h - 1 {
                    throw BakeError("\(cell.id): 감은 눈 차이가 칸 밖으로 나간다")
                }
                let p = closed.crop(x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1)
                let ps = p.straightened()
                alphaCells.add(ps.stats)
                result.patch = (ps.bytes, p.w, p.h, x0 - ox, y0 - oy)
            }
        }
        return result
    }

    struct Placed { let key: String; let x: Int; let y: Int; let w: Int; let h: Int }

    /// 선반 채우기. 칸 자리는 slotAlign(16) 배수로 맞춘다 — 손실 WebP 의 16×16 매크로블록이 두 칸에 걸치지 않게.
    func pack(_ items: [(key: String, w: Int, h: Int, bytes: [UInt8])], maxWidth: Int) -> (w: Int, h: Int, placed: [Placed], buffer: [UInt8]) {
        let a = config.slotAlign
        func up(_ v: Int) -> Int { (v + a - 1) / a * a }
        var x = 0, y = 0, shelf = 0, width = 0
        var placed: [Placed] = []
        for item in items {
            let sw = up(item.w), sh = up(item.h)
            if x > 0, x + sw > maxWidth { y += shelf; x = 0; shelf = 0 }
            placed.append(Placed(key: item.key, x: x, y: y, w: item.w, h: item.h))
            x += sw
            width = max(width, x)
            shelf = max(shelf, sh)
        }
        let pw = up(max(width, a)), ph = up(max(y + shelf, a))
        var buffer = [UInt8](repeating: 0, count: pw * ph * 4)
        buffer.withUnsafeMutableBufferPointer { dst in
            for (item, place) in zip(items, placed) {
                item.bytes.withUnsafeBufferPointer { src in
                    for row in 0..<item.h {
                        let s = row * item.w * 4, d = ((place.y + row) * pw + place.x) * 4
                        for i in 0..<(item.w * 4) { dst[d + i] = src[s + i] }
                    }
                }
            }
        }
        return (pw, ph, placed, buffer)
    }

    func bakeFinish(_ finish: BakeFinish, sCells: [BakeCell], camera: BakeCamera, cameraDirection: SIMD3<Double>) throws -> ([String: Any], [String: Any]) {
        let rig = try BakeRig(finish: finish, device: device, animated: false)
        rig.setHaloVisible(false)
        let g = config.grid
        var pages: [String] = []
        var cellObjects: [[String: Any]] = []
        var tiers: [[String: Any]] = []
        var legacyParts: [String: CellRender] = [:]
        var patchAreas: [Double] = []
        var patchBytes = 0

        let plan: [(tier: String, cells: [BakeCell], patches: Bool)] = [
            ("S", sCells, true),
            ("L", BakeGrid.rest(g, tier: "L"), true),
            ("U", BakeGrid.ultra(g), false)
        ]
        for (tier, cells, wantPatches) in plan {
            let size = config.size(tier)
            let t = config.tiers[tier]!
            var tierPages: [String] = []
            var patchItems: [(key: String, w: Int, h: Int, bytes: [UInt8])] = []
            var patchOwners: [String: (cellIndex: Int, atX: Int, atY: Int)] = [:]
            var bodyBoxes: [Int] = []
            let groups = Dictionary(grouping: cells, by: \.group)
            for group in [BakeCell.Group.rest, .band, .spin, .ultra] {
                guard let groupCells = groups[group] else { continue }
                let chunks = stride(from: 0, to: groupCells.count, by: t.pageMaxCells).map { Array(groupCells[$0..<min($0 + t.pageMaxCells, groupCells.count)]) }
                for (chunkIndex, chunk) in chunks.enumerated() {
                    var renders: [CellRender] = []
                    for cell in chunk {
                        let render = try renderCell(cell, rig: rig, size: size, camera: camera, cameraDirection: cameraDirection,
                                                    patch: wantPatches && BakeGrid.closedEyeCapable(cell, g))
                        renders.append(render)
                        if tier == "S", cell.group == .rest, cell.yaw == 0 || cell.yaw == 40 { legacyParts["\(cell.yaw)"] = render }
                    }
                    let pageName = "\(tier)-\(group.rawValue)-\(chunkIndex)"
                    let packed = pack(renders.map { ($0.cell.id, $0.crop.w, $0.crop.h, $0.straight) }, maxWidth: t.pageMaxWidth)
                    if packed.h > 4096 || packed.w > 4096 { throw BakeError("\(pageName): 페이지가 4096 을 넘는다 \(packed.w)×\(packed.h)") }
                    let pageIndex = pages.count
                    pages.append("\(pageName).webp")
                    tierPages.append("\(pageName).webp")
                    try emitImage(bytes: packed.buffer, w: packed.w, h: packed.h, rawName: "\(finish.assetID)/\(pageName)",
                                  destination: "\(finish.assetID)/\(pageName).webp", mode: "lossy")
                    for (render, place) in zip(renders, packed.placed) {
                        raw["\(finish.assetID)/\(render.cell.id)"] = Self.sha256(render.straight, w: render.crop.w, h: render.crop.h)
                        bodyBoxes.append(max(render.crop.w, render.crop.h) - 2 * config.cellMarginPx)
                        var object: [String: Any] = [
                            "id": render.cell.id, "tier": tier, "group": render.cell.group.rawValue,
                            "bodyYawDeg": render.cell.yaw, "viewTiltDeg": render.cell.tilt,
                            "page": pageIndex, "rect": ["x": place.x, "y": place.y, "w": place.w, "h": place.h],
                            "quad": render.quad, "pivot": render.pivot
                        ]
                        if let patch = render.patch {
                            let key = "\(render.cell.id)#closed"
                            raw["\(finish.assetID)/\(key)"] = Self.sha256(patch.straight, w: patch.w, h: patch.h)
                            patchItems.append((key, patch.w, patch.h, patch.straight))
                            patchOwners[key] = (cellObjects.count, patch.atX, patch.atY)
                            patchAreas.append(Double(patch.w * patch.h) / Double(render.crop.w * render.crop.h))
                        } else if wantPatches && BakeGrid.closedEyeCapable(render.cell, g) {
                            object["closedPatch"] = NSNull()
                        }
                        cellObjects.append(object)
                    }
                }
            }
            if !patchItems.isEmpty {
                let chunks = stride(from: 0, to: patchItems.count, by: 200).map { Array(patchItems[$0..<min($0 + 200, patchItems.count)]) }
                for (chunkIndex, chunk) in chunks.enumerated() {
                    let pageName = "\(tier)-patch-\(chunkIndex)"
                    let packed = pack(chunk, maxWidth: t.pageMaxWidth)
                    let pageIndex = pages.count
                    pages.append("\(pageName).webp")
                    tierPages.append("\(pageName).webp")
                    try emitImage(bytes: packed.buffer, w: packed.w, h: packed.h, rawName: "\(finish.assetID)/\(pageName)",
                                  destination: "\(finish.assetID)/\(pageName).webp", mode: "lossy")
                    patchBytes += packed.w * packed.h * 4
                    for place in packed.placed {
                        let owner = patchOwners[place.key]!
                        cellObjects[owner.cellIndex]["closedPatch"] = ["page": pageIndex, "rect": ["x": place.x, "y": place.y, "w": place.w, "h": place.h],
                                                                      "at": ["x": owner.atX, "y": owner.atY]] as [String: Any]
                    }
                }
            }
            let sortedBoxes = bodyBoxes.sorted()
            let tierCells = cellObjects.filter { ($0["tier"] as? String) == tier }
            try writeAsset(["format": config.bakeFormat, "tier": tier, "pages": pages, "cells": tierCells], to: "\(finish.assetID)/cells-\(tier).json")
            tiers.append(["name": tier, "viewport": [size.w, size.h], "pages": tierPages, "cellsFile": "cells-\(tier).json",
                          "bodyPxMedian": sortedBoxes.isEmpty ? 0 : sortedBoxes[sortedBoxes.count / 2], "cells": cells.count])
        }

        // legacy 2칸(frontIdle = S ψ0 τ13, sideIdle = S ψ+40 τ13): 같은 캔버스 · 같은 피벗 픽셀.
        guard let front = legacyParts["0"], let side = legacyParts["40"] else { throw BakeError("legacy 칸이 없다") }
        let parts = [front, side]
        let px = parts.map { Int($0.pivot[0].rounded()) }, py = parts.map { Int($0.pivot[1].rounded()) }
        let left = px.max()!, top = py.max()!
        let right = zip(parts, px).map { $0.crop.w - $1 }.max()!, bottom = zip(parts, py).map { $0.crop.h - $1 }.max()!
        let cw = left + right, ch = top + bottom
        var legacy = [UInt8](repeating: 0, count: cw * 2 * ch * 4)
        for (i, part) in parts.enumerated() {
            let dx = i * cw + (left - px[i]), dy = top - py[i]
            for row in 0..<part.crop.h {
                for col in 0..<(part.crop.w * 4) {
                    legacy[((dy + row) * cw * 2 + dx) * 4 + col] = part.straight[row * part.crop.w * 4 + col]
                }
            }
        }
        raw["\(finish.assetID)/legacy"] = Self.sha256(legacy, w: cw * 2, h: ch)
        try emitImage(bytes: legacy, w: cw * 2, h: ch, rawName: "\(finish.assetID)/legacy", destination: "\(finish.assetID)/legacy.webp", mode: "lossy")

        let box = rig.characterBox
        let center = (box.min + box.max) / 2
        var bake: [String: Any] = [
            "format": config.bakeFormat, "characterId": finish.manifest.id, "finish": finish.finishName,
            "camera": "../camera.json", "motion": "../motion.json", "particles": "../particles.json", "glyph": "../glyph-z.webp", "tracks": "../tracks/",
            "quadHalfUnits": config.quadHalfUnits, "quadOrder": "TL,TR,BR,BL",
            "pages": pages, "tiers": tiers,
            "cellsNote": "cells live in cells-<tier>.json (page = index into bake.pages) — a platform ships only the tiers it uses",
            "legacyPivot": ["x": left, "y": top],
            "cellPixelConvention": "rect/quad/pivot in pixels, top-left origin; quad/pivot are continuous coordinates within the cell rect",
            "alpha": "files are straight alpha; premultiply after decode (SceneKit wrote sRGB-encoded premultiplied values)",
            "inputsHash": "see ../lock.json"
        ]
        if let files = finish.haloCellFiles {
            bake["halo"] = ["cellFiles": files, "source": "Sources/check/Resources (Gradle Sync, no git copy)",
                            "yawStepDeg": GoldAingArt.haloYawStepDegrees, "sideOverBodyHeight": Double(GoldAingFinish.haloSideOverBodyHeight),
                            "centerUnits": [center.x, center.y, center.z].map(BakeMath.r6),
                            "restBandDeg": BakeMath.r6(GoldAingFinish.haloRestBandDegrees), "sideRestDeg": GoldAingFinish.haloSideRestDegrees,
                            "renderingOrder": GoldAingFinish.haloRenderingOrder, "art": "raw PNG (not window-compensated) drawn src-over before the body"]
        }
        let portrait = finish.portraitFiles
        let manifest: [String: Any] = [
            "id": finish.assetID, "displayName": finish.manifest.displayName, "kind": "sprite", "pixelArt": false,
            "atlas": ["file": "legacy.webp", "width": cw * 2, "height": ch,
                      "states": ["frontIdle": ["frames": [["x": 0, "y": 0, "w": cw, "h": ch]], "durationsMs": [1000], "loop": true],
                                 "sideIdle": ["frames": [["x": cw, "y": 0, "w": cw, "h": ch]], "durationsMs": [1000], "loop": true]]],
            "portrait": ["neutral": portrait.neutral, "negative": portrait.negative],
            "bake": bake
        ]
        let sortedAreas = patchAreas.sorted()
        let stats: [String: Any] = ["finish": finish.assetID, "patches": patchAreas.count,
                                    "patchAreaRatioMedian": sortedAreas.isEmpty ? 0 : BakeMath.r6(sortedAreas[sortedAreas.count / 2]),
                                    "patchAreaRatioMax": BakeMath.r6(sortedAreas.last ?? 0)]
        return (manifest, stats)
    }

    // MARK: 골든

    func bakeGoldens(tracks: Tracks, camera: BakeCamera, selector: BakeSelector, closedSelector: BakeSelector) async throws {
        let gc = config.golden
        let size = BakeSize(gc.viewport[0], gc.viewport[1])
        let reactions: [(name: String, kind: ReactionKind?, track: String)] = [
            ("hit", .hit, "hit"), ("commuteStart", .commuteStart, "commuteStart"), ("commuteEnd", .commuteEnd, "commuteEnd"),
            ("milestone", .milestone, "milestone"), ("greeting", .greeting(name: "아잉"), "greeting"), ("poked", .poked(bubbleText: "콕!"), "poked"),
            ("ultraPoked", .ultraPoked(bubbleText: "울트라!"), "ultraPoked"), ("goalAchieved", .goalAchieved, "goalAchieved"),
            ("ultraCharged", .ultraCharged, "ultraCharged"), ("drowsy", .drowsy, "drowsySink"), ("wake", nil, "wake"),
            ("quietRise", nil, "quietRise"), ("idle", nil, "idle")
        ]
        var entries: [[String: Any]] = []
        var index = 0
        for (fi, finish) in BakeFinish.allCases.enumerated() {
            let clock = BakeClock()
            let rig = try BakeRig(finish: finish, device: device, animated: false)
            let engine = makeEngine(rig: rig, clock: clock)
            var base = 10.0
            for (ri, reaction) in reactions.enumerated() {
                let track = reaction.name == "idle" ? tracks.idle! : tracks.reactions[reaction.track]!
                let duration = Double(track.samples.count - 1) / Double(hz)
                // 시점 6개: 비율 5개 + 정점(가장 크게 변한 표본).
                let peak = reaction.name == "idle" ? Int((3.6 * Double(hz)).rounded()) : track.samples.indices.max { a, b in
                    Self.magnitude(track.samples[a], extent: track.extent) < Self.magnitude(track.samples[b], extent: track.extent)
                }!
                var steps = Set(gc.fractions.map { Int(($0 * duration * Double(hz)).rounded()) })
                steps.insert(peak)
                var extra = 1
                while steps.count < 6 { steps.insert(Int((Double(extra) * 0.05 * duration * Double(hz)).rounded())); extra += 2 }
                for (ki, step) in steps.sorted().prefix(6).enumerated() {
                    let facing = gc.facingsDeg[(fi + ri + ki) % gc.facingsDeg.count]
                    let phase = gc.swayPhasesS[(ri + ki) % gc.swayPhasesS.count]
                    try await renderGolden(index: index, finish: finish, rig: rig, engine: engine, clock: clock, base: &base,
                                           reaction: reaction, step: step, facing: facing, phase: phase, eyesClosed: nil,
                                           tracks: tracks, camera: camera, size: size, selector: selector, closedSelector: closedSelector,
                                           entries: &entries)
                    index += 1
                }
            }
            // 깜빡임(서 있기 + 감은 눈) 2장.
            for facing in [0.0, 40.0] {
                try await renderGolden(index: index, finish: finish, rig: rig, engine: engine, clock: clock, base: &base,
                                       reaction: ("blink", nil, "idle"), step: Int((1.0 * Double(hz)).rounded()), facing: facing,
                                       phase: gc.swayPhasesS[0], eyesClosed: true, tracks: tracks, camera: camera, size: size,
                                       selector: selector, closedSelector: closedSelector, entries: &entries)
                index += 1
            }
            settle(engine, rig: rig, clock: clock)
        }
        try write(["format": 1, "viewport": [size.w, size.h], "particles": "off", "halo": "on (real SceneKit render)",
                   "transforms": "world 4x4 column-major (presentation), model units",
                   "referenceSelection": "nearest S cell by angle among the baked cells (closed eyes: cells with closedPatch)",
                   "pixelEncoding": "premultiplied sRGB RGBA8 exactly as SceneKit wrote it (RGB may exceed A) — decode WITHOUT premultiplying, then treat as premultiplied",
                   "entries": entries], to: "files/golden/golden.json")
    }

    static func magnitude(_ s: Sample, extent: Double) -> Double {
        let sv = simd_reduce_max(simd_abs(s.s - SIMD3(1, 1, 1)))
        return sv + angle(s.q, simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)) + simd_length(s.p) / extent
    }

    func renderGolden(index: Int, finish: BakeFinish, rig: BakeRig, engine: ReactionEngine, clock: BakeClock, base: inout Double,
                      reaction: (name: String, kind: ReactionKind?, track: String), step: Int, facing: Double, phase: Double,
                      eyesClosed: Bool?, tracks: Tracks, camera: BakeCamera, size: BakeSize,
                      selector: BakeSelector, closedSelector: BakeSelector, entries: inout [[String: Any]]) async throws {
        settle(engine, rig: rig, clock: clock)
        rig.setHaloVisible(true)
        try rig.setEyes(closed: false)
        var start = base
        rig.tick(start)
        var closed = false
        switch reaction.name {
        case "wake", "quietRise":
            #expect(engine.request(.drowsy))
            let sinkSteps = Int((engine.drowsySinkAction().duration * Double(hz)).rounded(.up)) + 2
            for k in 0...sinkSteps { rig.tick(start + Double(k) / Double(hz)) }
            start += Double(sinkSteps + 1) / Double(hz)
            rig.tick(start)
            if reaction.name == "wake" { #expect(engine.request(.wake)) } else { engine.wakeQuietly() }
        case "idle", "blink":
            break
        default:
            guard let kind = reaction.kind else { throw BakeError("골든 \(reaction.name): 종류 없음") }
            #expect(engine.request(kind))
            closed = kind == .drowsy
        }
        for k in 0...step { rig.tick(start + Double(k) / Double(hz)) }
        let time = start + Double(step) / Double(hz)
        if eyesClosed == true { try rig.setEyes(closed: true); closed = true }
        rig.facing.simdEulerAngles = SIMD3<Float>(0, Float(BakeMath.rad(facing)), 0)
        let idle = tracks.idle.samples
        let idleSample = idle[(Int((phase * Double(hz)).rounded()) + step) % idle.count]
        rig.character.simdOrientation = simd_quatf(vector: SIMD4<Float>(idleSample.q.vector))
        rig.character.simdPosition = SIMD3<Float>(idleSample.p)
        rig.removeTransientNodes()
        let image: BakeImage, n: Int
        do {
            (image, n) = try BakeRender.stable(rig.renderer, size: size, time: time, minimum: config.stabilizeMin, maximum: config.stabilizeMax,
                                               period2: { kind, pixels, delta in self.period2Goldens.append(["golden": index, "kind": kind, "pixels": pixels, "maxDelta": delta]) })
        } catch {
            // 진단: 12장을 더 그려 어떤 픽셀이 어떤 주기로 바뀌는지 적는다.
            var renders: [BakeImage] = []
            for _ in 0..<12 { renders.append(try BakeRender.capture(rig.renderer, size: size, time: time)) }
            var lines: [String] = []
            for i in 1..<renders.count {
                let box = renders[i].diffBox(renders[i - 1])
                lines.append("\(i): prev \(renders[i].countDifferent(renders[i - 1])) box \(String(describing: box)) · i-2 \(i >= 2 ? renders[i].countDifferent(renders[i - 2]) : -1)")
            }
            let halos = rig.halo?.childNodes.filter { abs($0.presentation.simdWorldTransform.columns.1.y) > 1e-3 || abs($0.presentation.simdWorldTransform.columns.0.x) > 1e-3 }.map { $0.name ?? "?" } ?? []
            throw BakeError("\(error) · 골든 \(index) \(finish.assetID) \(reaction.name) step \(step) · halo \(halos)\n" + lines.joined(separator: "\n"))
        }
        renderCounts[n, default: 0] += 1
        base = time + 20
        let flicker = period2Goldens.last.flatMap { ($0["golden"] as? Int) == index ? $0 : nil }
        // 골든은 **진짜 렌더 그대로**(SceneKit 이 쓴 프리멀티 바이트)를 무손실로 담는다 — 직선으로 바꾸면 P > A 픽셀이 잘려(아래 알파 보고)
        // 진짜가 아니게 된다. 직선 변환 손실은 집계만 한다.
        alphaGoldens.add(image.straightened().stats)
        let id = String(format: "%03d-%@-%@-t%04d", index, finish.assetID, reaction.name, step)
        raw["golden/\(id)"] = Self.sha256(image.px, w: size.w, h: size.h)
        try emitImage(bytes: image.px, w: size.w, h: size.h, rawName: "golden/\(id)", destination: "golden/\(id).webp", mode: "lossless")
        let body = BakeMath.d(rig.character.presentation.simdWorldTransform)
        let nView = BakeMath.viewDirection(bodyWorld: body, camera: camera.position)
        let pick = closed ? closedSelector.nearest(nView) : selector.nearest(nView)
        let chosen = (closed ? closedSelector : selector).cells[pick.index]
        let (yaw, tilt) = BakeMath.yawTilt(nView)
        // 후광(금 · 무지개): 앱의 순수 함수(haloPose → haloCell → haloCellTransform, 빌보드 = 카메라 축)로 칸과 판 네 꼭짓점을 내고,
        // 같은 프레임에 SceneKit 이 실제로 세운 칸 판(presentation)의 꼭짓점과 비교한다(T4 의 Swift 몫).
        var haloObject: Any = NSNull()
        if let halo = rig.halo, let plane = halo.childNodes.first?.geometry as? SCNPlane {
            let marker = halo.presentation.simdWorldTransform
            let camWorld = rig.camera.presentation.simdWorldTransform
            let pose = GoldAingFinish.haloPose(camera: camWorld, body: marker)
            let cellIndex = GoldAingFinish.haloCell(yaw: Double(pose.yaw))
            let transform = BakeMath.d(GoldAingFinish.haloCellTransform(billboard: camWorld, anchor: marker, cell: cellIndex))
            let half = Double(plane.width) / 2
            let corners = [(-half, half), (half, half), (half, -half), (-half, -half)]
            func quad(_ m: simd_double4x4) -> [[Double]] {
                corners.map { x, y in
                    let w = m * SIMD4(x, y, 0, 1)
                    let p = camera.project(SIMD3(w.x, w.y, w.z), size: size)
                    return [BakeMath.r6(p.x), BakeMath.r6(p.y)]
                }
            }
            let mine = quad(transform)
            var actual: [[Double]]?
            var actualCell: Int?
            for (i, node) in halo.childNodes.enumerated() {
                let m = BakeMath.d(node.presentation.simdWorldTransform)
                if simd_length(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z)) > 1e-3 { actual = quad(m); actualCell = i }
            }
            let worst = actual.map { a in zip(a, mine).map { hypot($0[0] - $1[0], $0[1] - $1[1]) }.max() ?? 0 } ?? -1
            haloWorstPx = max(haloWorstPx, worst)
            if actualCell != cellIndex { haloCellMismatches += 1 }
            haloObject = ["cell": cellIndex, "yawDeg": BakeMath.r6(BakeMath.deg(Double(pose.yaw))), "rollDeg": BakeMath.r6(BakeMath.deg(Double(pose.roll))),
                          "tiltDeg": BakeMath.r6(BakeMath.deg(Double(pose.tilt))), "sideUnits": BakeMath.r6(Double(plane.width)),
                          "quadPx": mine, "sceneKitCell": actualCell as Any, "sceneKitQuadMaxDiffPx": BakeMath.r6(worst)] as [String: Any]
        }
        entries.append(["id": id, "halo": haloObject, "file": "\(id).webp", "finish": finish.assetID, "reaction": reaction.name, "track": reaction.track,
                        "tS": BakeMath.r6(Double(step) / Double(hz)), "sampleIndex": step, "facingDeg": facing, "swayPhaseS": phase,
                        "eyesClosed": closed,
                        "world": ["wrapper": BakeMath.list(BakeMath.d(rig.wrapper.presentation.simdWorldTransform)),
                                  "facing": BakeMath.list(BakeMath.d(rig.facing.presentation.simdWorldTransform)),
                                  "character": BakeMath.list(body)],
                        "view": ["yawDeg": BakeMath.r6(yaw), "tiltDeg": BakeMath.r6(tilt)],
                        "referenceCell": ["id": chosen.id, "angleDeg": BakeMath.r6(pick.angle)],
                        "haloFlicker": flicker.map { ["kind": $0["kind"]!, "pixels": $0["pixels"]!, "maxDelta": $0["maxDelta"]!] as [String: Any] } as Any])
    }

    // MARK: 실험 보고

    /// F-3: SCNCamera.projectionTransform(withViewportSize:) 가용성과 내 투영 · projectPoint 와의 차이.
    func projectionReport(camera: BakeCamera) throws -> [String: Any] {
        let rig = try BakeRig(finish: .standard, device: device, animated: false)
        let cam = rig.camera.camera!
        var out: [String: Any] = ["api": "SCNCamera.projectionTransform(withViewportSize:)"]
        var rows: [[String: Any]] = []
        for (name, size) in [("S", config.size("S")), ("U", config.size("U"))] {
            let sk = BakeMath.d(simd_float4x4(cam.projectionTransform(withViewportSize: CGSize(width: size.w, height: size.h))))
            let mine = camera.projectionMatrix(size: size)
            var worst = 0.0
            for c in 0..<4 { worst = max(worst, simd_length(sk[c] - mine[c])) }
            rows.append(["viewport": name, "maxMatrixDiff": worst, "sceneKit": BakeMath.list(sk)])
        }
        out["viewports"] = rows
        out["projectPointCrossCheck"] = "camera.json projectPointMaxErrorPx (bbox corners, 4 viewports)"
        return out
    }

    /// F-4: 후광 빌보드가 화면 정렬인가 시점 지향인가 — 몸을 옆으로 옮긴 뒤 칸 판의 z 축을 카메라 z 축 · (판→카메라) 방향과 비교한다.
    func billboardReport(camera: BakeCamera) throws -> [String: Any] {
        let rig = try BakeRig(finish: .gold, device: device, animated: false)
        rig.resetPose()
        rig.wrapper.simdPosition = SIMD3<Float>(0.9, 0.3, 0)
        _ = try BakeRender.capture(rig.renderer, size: config.size("S"), time: 0)
        guard let halo = rig.halo, let cell = halo.childNodes.first else { throw BakeError("F-4: 후광 칸이 없다") }
        let m = BakeMath.d(cell.presentation.simdWorldTransform)
        let z = simd_normalize(SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        let pos = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        let camZ = simd_normalize(SIMD3(camera.world.columns.2.x, camera.world.columns.2.y, camera.world.columns.2.z))
        let toCamera = simd_normalize(camera.position - pos)
        let screen = BakeMath.angleDeg(z, camZ), view = BakeMath.angleDeg(z, toCamera)
        return ["haloCellZvsCameraZDeg": BakeMath.r6(screen), "haloCellZvsToCameraDeg": BakeMath.r6(view),
                "angleBetweenHypothesesDeg": BakeMath.r6(BakeMath.angleDeg(camZ, toCamera)),
                "verdict": screen < view ? "screen-aligned" : "view-oriented"]
    }

    /// F-13: 맥 실시간 2X MSAA 와 굽기 4X 의 가장자리 차이(같은 자세 · 같은 렌더러, 창 없이).
    func msaaReport() throws -> [String: Any] {
        var rows: [[String: Any]] = []
        for finish in BakeFinish.allCases {
            let rig = try BakeRig(finish: finish, device: device, animated: false)
            let size = config.size("S")
            let (a4, _) = try BakeRender.stable(rig.renderer, size: size, time: 0)
            let (a2, _) = try BakeRender.stable(rig.renderer, size: size, time: 0, antialiasing: .multisampling2X)
            var inter = 0, union = 0, unionAny = 0, maxDelta = 0, changed = 0
            var sum = 0.0
            for i in 0..<(size.w * size.h) {
                let a = Int(a4.px[i * 4 + 3]), b = Int(a2.px[i * 4 + 3])
                if a > 127 && b > 127 { inter += 1 }
                if a > 127 || b > 127 { union += 1 }
                if a > 0 || b > 0 {
                    unionAny += 1
                    var m = 0
                    for c in 0..<4 { let d = abs(Int(a4.px[i * 4 + c]) - Int(a2.px[i * 4 + c])); sum += Double(d); m = max(m, d) }
                    maxDelta = max(maxDelta, m)
                    if m > 0 { changed += 1 }
                }
            }
            rows.append(["finish": finish.assetID, "iou": BakeMath.r6(Double(inter) / Double(max(union, 1))),
                         "meanAbsDelta": BakeMath.r6(sum / Double(max(unionAny * 4, 1))), "maxDelta": maxDelta,
                         "changedPixels": changed, "unionPixels": unionAny])
        }
        return ["comparison": "SCNRenderer snapshot multisampling2X vs multisampling4X, rest pose 280x340 (no window — proxy for the live SCNView)",
                "rows": rows]
    }

    /// F-6: 파티클 의미 — 기본 입자 모양(particleImage nil), 각속도 단위, 색 변동(HSB) 축. 한 번에 한 매개변수만 극단으로.
    func particleSemanticsReport() async throws -> [String: Any] {
        let size = BakeSize(256, 256)
        func scene(_ configure: (SCNParticleSystem) -> Void) -> (SCNRenderer, SCNScene) {
            let scene = SCNScene()
            scene.background.contents = nil
            let cam = SCNNode()
            cam.camera = SCNCamera()
            cam.camera!.usesOrthographicProjection = true
            cam.camera!.orthographicScale = 1
            cam.position = SCNVector3(0, 0, 5)
            scene.rootNode.addChildNode(cam)
            let emitter = SCNNode()
            let system = SCNParticleSystem()
            system.particleImage = nil
            system.loops = false
            system.emissionDuration = 0.001
            system.birthRate = 1000
            system.particleLifeSpan = 100
            system.particleVelocity = 0
            system.particleSize = 0.6
            system.isLightingEnabled = false
            system.blendMode = .alpha
            system.particleColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
            system.emitterShape = nil
            system.birthLocation = .surface
            configure(system)
            emitter.addParticleSystem(system)
            scene.rootNode.addChildNode(emitter)
            let renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene
            renderer.pointOfView = cam
            renderer.autoenablesDefaultLighting = false
            return (renderer, scene)
        }
        func run(_ renderer: SCNRenderer, until seconds: Double) throws -> BakeImage {
            var image: BakeImage?
            for k in 0...Int(seconds * 60) { image = try BakeRender.capture(renderer, size: size, time: 500 + Double(k) / 60, antialiasing: .none) }
            return image!
        }
        // ① 모양: 한 입자(그 자리에 여러 개가 겹쳐도 모양은 같다) — 알파 상자 대비 덮인 비율. 사각 1.0 · 원 0.785.
        let (r1, _) = scene { $0.birthRate = 60; $0.emissionDuration = 0.05; $0.emitterShape = SCNSphere(radius: 0.001); $0.birthLocation = .volume }
        let shapeImage = try run(r1, until: 0.6)
        var shape: [String: Any] = [:]
        if let box = shapeImage.alphaBox() {
            var covered = 0, soft = 0
            for y in box.y0...box.y1 { for x in box.x0...box.x1 {
                let a = shapeImage.px[(y * size.w + x) * 4 + 3]
                if a > 127 { covered += 1 }
                if a > 0 && a < 250 { soft += 1 }
            } }
            let area = Double((box.x1 - box.x0 + 1) * (box.y1 - box.y0 + 1))
            shape = ["boxPx": [box.x1 - box.x0 + 1, box.y1 - box.y0 + 1], "coverageOfBox": BakeMath.r6(Double(covered) / area),
                     "softPixelRatio": BakeMath.r6(Double(soft) / area)]
        } else {
            shape = ["boxPx": "empty"]
        }
        // ② 각속도: 각 0 · 각속도 30 · 1초 → 30° 이면 도/초, 30 rad ≈ 1718.9° (mod 90 = 8.9°) 이면 라디안/초. 사각형의 기울기로 잰다.
        func squareAngle(_ img: BakeImage) -> Double? {
            var sx = 0.0, sy = 0.0, n = 0.0
            var pts: [(Double, Double)] = []
            for y in 0..<img.h { for x in 0..<img.w where img.px[(y * img.w + x) * 4 + 3] > 127 { pts.append((Double(x), Double(y))); sx += Double(x); sy += Double(y); n += 1 } }
            guard n > 20 else { return nil }
            let cx = sx / n, cy = sy / n
            // 중심에서 가장 먼 점(모서리)의 각 — 사각형 모서리는 45° + 회전각.
            let far = pts.max { ($0.0 - cx) * ($0.0 - cx) + ($0.1 - cy) * ($0.1 - cy) < ($1.0 - cx) * ($1.0 - cx) + ($1.1 - cy) * ($1.1 - cy) }!
            var a = BakeMath.deg(atan2(-(far.1 - cy), far.0 - cx)) - 45
            a = a.truncatingRemainder(dividingBy: 90)
            if a < 0 { a += 90 }
            return a
        }
        let (r0, _) = scene { $0.birthRate = 60; $0.emissionDuration = 0.05; $0.emitterShape = SCNSphere(radius: 0.001); $0.birthLocation = .volume; $0.particleAngularVelocity = 0 }
        let still = try run(r0, until: 1.0)
        let (r2, _) = scene { $0.birthRate = 60; $0.emissionDuration = 0.05; $0.emitterShape = SCNSphere(radius: 0.001); $0.birthLocation = .volume; $0.particleAngularVelocity = 30 }
        let spun = try run(r2, until: 1.0)
        let a0 = squareAngle(still), a1 = squareAngle(spun)
        var angular: [String: Any] = ["angleAtRestDeg": a0.map(BakeMath.r6) as Any, "angleAfter1sAt30Deg": a1.map(BakeMath.r6) as Any]
        if let a0, let a1 {
            let delta = (a1 - a0 + 90).truncatingRemainder(dividingBy: 90)
            let degHypo = 30.0.truncatingRemainder(dividingBy: 90), radHypo = BakeMath.deg(30).truncatingRemainder(dividingBy: 90)
            angular["observedDeltaMod90"] = BakeMath.r6(delta)
            angular["verdict"] = abs(delta - degHypo) < abs(delta - radHypo) ? "degrees per second" : "radians per second"
            angular["hypotheses"] = ["degPerS": degHypo, "radPerS": BakeMath.r6(radHypo)]
        }
        // ③ 색 변동: 빨강 바탕에 x(=H?)만 0.5 → 색상이 퍼지는가, z(=B?)만 0.5 → 밝기만 퍼지는가. 많은 입자를 흩뿌려 잰다.
        func spread(_ variation: SCNVector4) throws -> [String: Any] {
            let (r, _) = scene {
                $0.birthRate = 400; $0.emissionDuration = 0.2; $0.particleSize = 0.05; $0.particleVelocity = 0
                $0.emitterShape = SCNBox(width: 1.6, height: 1.6, length: 0.01, chamferRadius: 0); $0.birthLocation = .volume
                $0.particleColorVariation = variation
            }
            let img = try run(r, until: 0.3)
            var hues: [Double] = [], values: [Double] = [], sats: [Double] = []
            for i in 0..<(img.w * img.h) where img.px[i * 4 + 3] > 250 {
                let c = NSColor(srgbRed: CGFloat(img.px[i * 4]) / 255, green: CGFloat(img.px[i * 4 + 1]) / 255, blue: CGFloat(img.px[i * 4 + 2]) / 255, alpha: 1)
                hues.append(Double(c.hueComponent)); sats.append(Double(c.saturationComponent)); values.append(Double(c.brightnessComponent))
            }
            func range(_ xs: [Double]) -> Double { (xs.max() ?? 0) - (xs.min() ?? 0) }
            let circularHue = hues.map { $0 > 0.5 ? $0 - 1 : $0 }
            return ["opaquePixels": hues.count, "hueRange": BakeMath.r6(range(circularHue)), "saturationRange": BakeMath.r6(range(sats)),
                    "brightnessRange": BakeMath.r6(range(values))]
        }
        let color: [String: Any] = ["x0.5": try spread(SCNVector4(0.5, 0, 0, 0)), "y0.5": try spread(SCNVector4(0, 0.5, 0, 0)),
                                    "z0.5": try spread(SCNVector4(0, 0, 0.5, 0)), "none": try spread(SCNVector4(0, 0, 0, 0))]
        return ["shapeParticleImageNil": shape, "angularVelocity": angular, "colorVariation": color,
                "note": "orthographic, 1 particle (shape/angle) or a scatter (color); render .none AA at 60Hz steps"]
    }
}
