import AppKit
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// v0.3.55 — 황금 아잉이 후광 미리보기(사람이 보는 그림). 기본 실행에서는 꺼져 있다 —
// `CHECK_V0355_HALO_STILLS_DIR=<폴더>` 를 주면 실제 앱 씬을 앱 카메라(280×340 = 140×170pt @2x)로 오프스크린 렌더해
// 여러 자세(요 0 · 16 · 40 · 90 · 140 · 180°, 근무 시작 360° 스핀 중간, 찔림 중간 — 롤 포함)를 투명 그대로(`-raw`)와
// 밝은·어두운 바탕(창 합성기처럼 sRGB 프리멀티 over)에 얹은 PNG 로 떨군다. 파일 앞머리는 `CHECK_V0355_HALO_STILLS_PREFIX`(기본 after).
// 창은 띄우지 않는다. 0.3.54 의 공개 골격(makeScene · wrapper/facing · ReactionActions)만 써서 옛 코드에서도 같은 그림을 뽑을 수 있다.

@MainActor
@Suite struct V0355GoldHaloStillsTests {
    nonisolated static let directory = ProcessInfo.processInfo.environment["CHECK_V0355_HALO_STILLS_DIR"]

    @Test("미리보기: 후광 자세별 스틸(밝은·어두운 바탕 · 투명)", .enabled(if: directory != nil))
    func writeStills() throws {
        let dir = URL(fileURLWithPath: try #require(Self.directory))
        let prefix = ProcessInfo.processInfo.environment["CHECK_V0355_HALO_STILLS_PREFIX"] ?? "after"
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 280, height: 340)
        // (이름, 자세 걸기 → 그 뒤 몇 초에 찍나)
        let poses: [(String, (SCNNode, SCNNode, CGFloat) -> TimeInterval)] = [
            ("yaw000", { _, facing, _ in facing.eulerAngles = SCNVector3(0, 0, 0); return 0 }),
            ("yaw016", { _, facing, _ in facing.eulerAngles = SCNVector3(0, 16 * CGFloat.pi / 180, 0); return 0 }),
            ("yaw040", { _, facing, _ in facing.eulerAngles = SCNVector3(0, 40 * CGFloat.pi / 180, 0); return 0 }),
            ("yaw090", { _, facing, _ in facing.eulerAngles = SCNVector3(0, 90 * CGFloat.pi / 180, 0); return 0 }),
            ("yaw140", { _, facing, _ in facing.eulerAngles = SCNVector3(0, 140 * CGFloat.pi / 180, 0); return 0 }),
            ("yaw180", { _, facing, _ in facing.eulerAngles = SCNVector3(0, CGFloat.pi, 0); return 0 }),
            // 근무 시작: 폴짝 + 360° 스핀(0.6초, 선형) — 0.2초면 120° 돈 자리.
            ("spin-commute-0.20s", { wrapper, _, extent in wrapper.runAction(ReactionActions.commuteStart(hop: extent * 0.32)); return 0.20 }),
            // 찔림: 반 바퀴 스핀 + z 흔들림 — 0.70초면 요 약 62° · 롤 약 20°(V0355GoldHaloYawTests 가 잰 자리).
            ("spin-poked-0.70s", { wrapper, _, extent in wrapper.runAction(ReactionActions.poked(extent: extent)); return 0.70 })
        ]
        for (name, pose) in poses {
            let scene = try #require(CheckCharacter3DScene.makeScene(animated: false, character: CharacterCatalog.builtInGoldAing))
            let wrapper = try #require(scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
            let facing = try #require(wrapper.childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false))
            let box = wrapper.boundingBox
            let extent = CGFloat(max(box.max.x - box.min.x, box.max.y - box.min.y))
            let renderer = SCNRenderer(device: try #require(MTLCreateSystemDefaultDevice()), options: nil)
            renderer.scene = scene
            renderer.autoenablesDefaultLighting = false
            renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
            _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
            let offset = pose(wrapper, facing, extent)
            _ = renderer.snapshot(atTime: 1, with: size, antialiasingMode: .multisampling4X)   // 액션은 다음 렌더 시각부터 돈다
            let shot = renderer.snapshot(atTime: 1 + offset, with: size, antialiasingMode: .multisampling4X)
            let raw = try #require(shot.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.cgImage)
            try Self.write(raw, dir.appendingPathComponent("\(prefix)-\(name)-raw.png"))
            for (bg, gray) in [("light", 0.95), ("dark", 0.11)] {
                try Self.write(try #require(V0354GoldAing3DTests.composite(raw, over: gray)), dir.appendingPathComponent("\(prefix)-\(name)-\(bg).png"))
            }
        }
    }

    static func write(_ image: CGImage, _ url: URL) throws {
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
