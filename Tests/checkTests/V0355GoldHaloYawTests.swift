import AppKit
import ImageIO
import QuartzCore
import SceneKit
import simd
import Testing
@testable import check
@testable import CheckCore

// v0.3.55 — 황금 아잉이 후광이 몸의 **지금 각도**를 따른다(사용자 신고 2026-10-16: "캐릭터가 옆으로 움직일 때 뒤에 후광은 캐릭터
// 정면에만 맞춰져 있어서 이상해"). 정면 한 장이던 후광을 몸 요 10° 칸 36장으로 굽고, 렌더 프레임마다 presentation 자세에서
// 가장 가까운 칸 하나만 몸 자리에 세운다(`GoldAingFinish.haloCellTransform`). 여기서 재는 것:
//  · 요/롤 → 칸 · 판 변환(순수) — 감기 · 여러 바퀴 · 음수 · 경계 · 롤이 그대로 나오는가.
//  · 고르기가 presentation 을 탄다 — SCNAction 스핀과 **모델 값을 안 바꾸는** CAAnimation 스핀 둘 다 렌더 시각을 넘기면 칸이 바뀐다.
//  · 결과 — 실제 앱 씬을 앱 카메라 방향으로 그려, 후광이 몸을 감싸는 폭이 40° · 90° · 찔림 중간(롤 포함)에서도 0° 와 같다.
//    기준선: 같은 씬에 옛 정면 한 장을 붙이면 같은 잣대에서 빨갛다.
//  · 정면은 그대로 — 0° 앱 렌더가 0.3.54 판(정면 PNG 한 장 + 빌보드) 그대로다.
//  · 칸 그림 36장이 저장소·앱 번들에 있고, 맥 패키징 대본 둘이 조립한 앱 안에서 칸을 세어 빠지면 멈춘다(대본을 실제로 돌려 본다).
// 창은 띄우지 않는다 — 전부 SCNRenderer 오프스크린이다.

@MainActor
@Suite struct V0355GoldHaloYawTests {
    static let gold = CharacterCatalog.builtInGoldAing

    // MARK: 도구

    static func scene() throws -> SCNScene {
        try #require(CheckCharacter3DScene.makeScene(animated: false, character: gold))
    }

    static func wrapper(_ scene: SCNScene) throws -> SCNNode {
        try #require(scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
    }

    static func facing(_ scene: SCNScene) throws -> SCNNode {
        try #require(try wrapper(scene).childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false))
    }

    static func halo(_ scene: SCNScene) throws -> SCNNode {
        try #require(scene.rootNode.childNode(withName: GoldAingFinish.haloNodeName, recursively: true))
    }

    /// 지금 몸 자리에 선(= 고른) 칸 번호들. 고르지 않은 칸은 카메라 쪽으로 1만 단위 치워져 있다.
    static func visibleCells(_ scene: SCNScene) throws -> [Int] {
        let anchor = try halo(scene).presentation.simdWorldPosition
        return try halo(scene).childNodes.enumerated().compactMap { index, node in
            simd_distance(node.presentation.simdWorldPosition, anchor) < 0.5 ? index : nil
        }
    }

    /// 시각을 넘기며 같은 렌더러로 그린다(SCNAction · 애니메이션은 렌더 시각으로 간다).
    final class Shooter {
        let renderer: SCNRenderer
        init(_ scene: SCNScene, pointOfView: SCNNode?) throws {
            renderer = SCNRenderer(device: try #require(MTLCreateSystemDefaultDevice()), options: nil)
            renderer.scene = scene
            renderer.autoenablesDefaultLighting = false
            if let pointOfView { renderer.pointOfView = pointOfView }
        }
        func shot(at time: TimeInterval, size: CGSize = CGSize(width: 64, height: 64)) throws -> CGImage {
            let image = renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
            let rep = try #require(image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) })
            return try #require(rep.cgImage)
        }
    }

    /// 앱 카메라와 **같은 방향**에서 뒤로 물러난 카메라 — 앱 구도(280×340)는 판(2H)의 위아래를 자르므로, 후광 경계 전체를 재려고
    /// 시선 방향은 그대로 두고 거리만 늘린다(내려다보는 각 · 화면 정렬이 앱과 같다).
    static func pulledBackCamera(_ scene: SCNScene, factor: Float = 1.8) throws -> SCNNode {
        let app = try #require(V0354GoldAing3DTests.cameraNode(scene))
        let node = SCNNode()
        node.camera = app.camera?.copy() as? SCNCamera
        let world = app.simdWorldTransform
        let center = try halo(scene).simdWorldPosition
        let back = simd_normalize(SIMD3(world.columns.2.x, world.columns.2.y, world.columns.2.z))
        let distance = simd_distance(SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z), center)
        var moved = world
        moved.columns.3 += SIMD4(back * distance * (factor - 1), 0)
        node.simdTransform = moved
        scene.rootNode.addChildNode(node)
        return node
    }

    /// 알파 ≥ `threshold` 영역의 경계 픽셀.
    static func boundary(_ px: [UInt8], width w: Int, height h: Int, threshold: UInt8) -> [SIMD2<Float>] {
        var out = [SIMD2<Float>]()
        for y in 1..<(h - 1) { for x in 1..<(w - 1) where px[(y * w + x) * 4 + 3] >= threshold {
            if px[(y * w + x - 1) * 4 + 3] < threshold || px[(y * w + x + 1) * 4 + 3] < threshold
                || px[((y - 1) * w + x) * 4 + 3] < threshold || px[((y + 1) * w + x) * 4 + 3] < threshold {
                out.append(SIMD2(Float(x), Float(y)))
            }
        } }
        return out
    }

    /// 후광이 몸을 감싸는 폭: 후광(α ≥ 0.3) 경계 픽셀마다 몸(α ≥ 250) 경계까지 가장 가까운 거리 — 평균 · 최대(px).
    /// 맞는 후광은 어느 자세에서나 0° 와 비슷한 폭으로 몸을 두르고, 정면 날개가 박힌 후광은 옆모습에서 최대가 크게 튄다.
    struct Hug { var mean: Double; var max: Double }
    static func hug(full: CGImage, body: CGImage) throws -> Hug {
        let w = full.width, h = full.height
        let pf = try #require(GoldAingFinish.rgbaBytes(full)), pb = try #require(GoldAingFinish.rgbaBytes(body, width: w, height: h))
        let halo = boundary(pf, width: w, height: h, threshold: 77)
        let edge = boundary(pb, width: w, height: h, threshold: 250)
        try #require(!halo.isEmpty && !edge.isEmpty, "후광이나 몸이 안 그려졌다")
        var sum = 0.0, peak = 0.0
        for p in halo {
            var best = Float.infinity
            for q in edge { best = min(best, simd_distance_squared(p, q)) }
            let d = Double(best.squareRoot())
            sum += d
            peak = max(peak, d)
        }
        return Hug(mean: sum / Double(halo.count), max: peak)
    }

    /// 이 씬을 이 시각에 그려 감싸는 폭을 잰다(몸만 = 후광 숨긴 같은 시각의 렌더).
    static func hug(_ scene: SCNScene, shooter: Shooter, at time: TimeInterval, size: CGSize) throws -> Hug {
        let halo = try halo(scene)
        let full = try shooter.shot(at: time, size: size)
        halo.isHidden = true
        defer { halo.isHidden = false }
        let body = try shooter.shot(at: time, size: size)
        return try hug(full: full, body: body)
    }

    /// 칸 판 전부에 같은 그림을 붙인다(기준선: 0.3.54 처럼 어느 자세에서나 정면 한 장).
    static func forceFrontEverywhere(_ scene: SCNScene) throws {
        let front = try #require(GoldAingFinish.haloImage())
        for cell in try halo(scene).childNodes { cell.geometry?.firstMaterial?.diffuse.contents = front }
    }

    static func degrees(_ d: Double) -> Double { d * .pi / 180 }

    // MARK: ① 칸 고르기(순수)

    @Test("요 → 칸: 0 · ±40° · ±90° · ±180° · 370° · 720°+40° · 경계 ±5° · 음수는 거울이 아니라 반대쪽 칸 · 이름 36장")
    func yawMapsToNearestCell() {
        let cases: [(Double, Int)] = [
            (0, 0), (40, 4), (-40, 32), (90, 9), (-90, 27), (180, 18), (-180, 18),
            (370, 1), (720 + 40, 4), (-720 - 40, 32), (4.99, 0), (5.01, 1), (-4.99, 0), (-5.01, 35), (355.01, 0), (354.99, 35)
        ]
        for (deg, cell) in cases {
            #expect(GoldAingFinish.haloCell(yaw: Self.degrees(deg)) == cell, "\(deg)° → \(GoldAingFinish.haloCell(yaw: Self.degrees(deg))) (기대 \(cell))")
        }
        #expect(GoldAingFinish.haloCell(yaw: .nan) == 0 && GoldAingFinish.haloCell(yaw: .infinity) == 0, "NaN · ∞ 는 정면으로")
        #expect(GoldAingArt.haloCellCount == 36 && GoldAingArt.haloYawStepDegrees == 10)
        #expect(GoldAingArt.haloCellResourceNames.count == 36)
        #expect(GoldAingArt.haloCellResourceNames.first == GoldAingArt.haloResourceName)
        #expect(GoldAingArt.haloResourceName(cell: 4) == "aing_gold-halo-040")
        #expect(GoldAingArt.haloResourceName(cell: 32) == "aing_gold-halo-320")
        #expect(Set(GoldAingArt.haloCellResourceNames).count == 36)
    }

    @Test("자세 나누기: 카메라 기준 Rz(롤)·Rx(기울기)·Ry(요) 를 그대로 돌려준다 — 롤은 그대로 통과, 요는 롤·기울기와 섞이지 않는다")
    func poseDecompositionRoundTrips() {
        func rotation(_ axis: SIMD3<Float>, _ deg: Double) -> simd_float4x4 {
            simd_float4x4(simd_quatf(angle: Float(Self.degrees(deg)), axis: axis))
        }
        // 카메라: 앱처럼 17° 내려다보는 것과 수평 둘. 몸 = 카메라 · (Rz·Rx·Ry) — 카메라 기준 자세를 월드로 옮긴다.
        for cameraPitch in [0.0, -17.0] {
            let camera = rotation(SIMD3(1, 0, 0), cameraPitch)
            for (yaw, roll, tilt) in [(0.0, 0.0, 0.0), (40, 0, 0), (-40, 0, 0), (90, 26, 0), (170, -24, 10), (-120, 15, -20)] {
                let relative = rotation(SIMD3(0, 0, 1), roll) * rotation(SIMD3(1, 0, 0), tilt) * rotation(SIMD3(0, 1, 0), yaw)
                var body = camera * relative
                body.columns.0 *= 1.16; body.columns.1 *= 0.8   // 스쿼시가 섞여도 방향만 본다
                let pose = GoldAingFinish.haloPose(camera: camera, body: body)
                #expect(abs(Double(pose.yaw) - Self.degrees(yaw)) < 1e-4, "요 \(yaw) → \(pose.yaw * 180 / .pi)")
                #expect(abs(Double(pose.roll) - Self.degrees(roll)) < 1e-4, "롤 \(roll) → \(pose.roll * 180 / .pi)")
                #expect(abs(Double(pose.tilt) - Self.degrees(tilt)) < 1e-4, "기울기 \(tilt) → \(pose.tilt * 180 / .pi)")
            }
        }
        // 실제 SceneKit 노드(앱 골격 wrapper → facing): 수평 카메라 · wrapper z 롤 26° · facing y 40° → 롤 26° · 요 40° · 기울기 0.
        // 앱처럼 내려다보는 카메라(위로 2 · 앞으로 6)와 선 몸 · facing y −90° → 요 −90° · 롤 0 · 기울기 = 내려다보는 각.
        let root = SCNNode(), wrapper = SCNNode(), facing = SCNNode(), camera = SCNNode()
        root.addChildNode(wrapper); wrapper.addChildNode(facing); root.addChildNode(camera)
        camera.position = SCNVector3(0, 0, 6); camera.look(at: SCNVector3(0, 0, 0))
        wrapper.eulerAngles = SCNVector3(0, 0, Self.degrees(26))
        facing.eulerAngles = SCNVector3(0, Self.degrees(40), 0)
        let rolled = GoldAingFinish.haloPose(camera: camera.simdWorldTransform, body: facing.simdWorldTransform)
        #expect(abs(Double(rolled.roll) - Self.degrees(26)) < 1e-4 && abs(Double(rolled.yaw) - Self.degrees(40)) < 1e-4
                && abs(Double(rolled.tilt)) < 1e-4,
                "SceneKit 노드: 롤 \(rolled.roll * 180 / .pi) · 요 \(rolled.yaw * 180 / .pi) · 기울기 \(rolled.tilt * 180 / .pi)")
        camera.position = SCNVector3(0, 2, 6); camera.look(at: SCNVector3(0, 0, 0))
        wrapper.eulerAngles = SCNVector3(0, 0, 0)
        facing.eulerAngles = SCNVector3(0, Self.degrees(-90), 0)
        let looked = GoldAingFinish.haloPose(camera: camera.simdWorldTransform, body: facing.simdWorldTransform)
        #expect(abs(Double(looked.yaw) + Self.degrees(90)) < 1e-4 && abs(Double(looked.roll)) < 1e-4
                && abs(Double(looked.tilt) - atan2(2, 6)) < 1e-4,
                "내려다보는 카메라: 요 \(looked.yaw * 180 / .pi) · 롤 \(looked.roll * 180 / .pi) · 기울기 \(looked.tilt * 180 / .pi)")
    }

    @Test("칸 판 변환: 고른 칸은 몸 중심에 화면 정렬 + 롤, 크기는 몸에서 · 나머지는 카메라 뒤로 1만")
    func cellTransformPlacesOnlyTheChosenCell() {
        let camera = matrix_identity_float4x4
        var body = simd_float4x4(simd_quatf(angle: Float(Self.degrees(40)), axis: SIMD3(0, 1, 0)))
        body = simd_float4x4(simd_quatf(angle: Float(Self.degrees(20)), axis: SIMD3(0, 0, 1))) * body
        body.columns.3 = SIMD4(0.3, -0.2, 0.1, 1)
        // 빌보드 결과의 위치·크기는 지난 프레임에 치운 자리가 남은 것이라 믿지 않는다.
        var billboard = camera
        billboard.columns.0 *= 7; billboard.columns.3 = SIMD4(0, 0, 9_999, 1)
        let chosen = GoldAingFinish.haloCellTransform(billboard: billboard, anchor: body, cell: 4)
        #expect(simd_distance(SIMD3(chosen.columns.3.x, chosen.columns.3.y, chosen.columns.3.z), SIMD3(0.3, -0.2, 0.1)) < 1e-5)
        let up = simd_normalize(SIMD3(chosen.columns.1.x, chosen.columns.1.y, chosen.columns.1.z))
        #expect(abs(Double(atan2(-up.x, up.y)) - Self.degrees(20)) < 1e-4, "판이 몸 롤 20° 만큼 안 기울었다")
        #expect(abs(simd_length(SIMD3(chosen.columns.0.x, chosen.columns.0.y, chosen.columns.0.z)) - 1) < 1e-4, "크기가 빌보드에서 왔다")
        #expect(abs(chosen.columns.2.z - 1) < 1e-5, "판이 카메라를 안 본다")
        for other in [0, 3, 5, 31] {
            let hidden = GoldAingFinish.haloCellTransform(billboard: billboard, anchor: body, cell: other)
            #expect(hidden.columns.3.z > 9_000, "칸 \(other) 가 안 치워졌다")
        }
    }

    // MARK: ② presentation

    @Test("고르기는 presentation 을 탄다: SCNAction 스핀과 모델 값을 안 바꾸는 CAAnimation 스핀 둘 다 렌더 시각을 넘기면 칸이 바뀐다")
    func selectionFollowsThePresentation() throws {
        // SCNAction — 360° 를 1초에(선형). 0 · 0.25 · 0.5 · 0.75 초 → 0° · 90° · 180° · 270°.
        let actionScene = try Self.scene()
        let shooter = try Shooter(actionScene, pointOfView: V0354GoldAing3DTests.cameraNode(actionScene))
        _ = try shooter.shot(at: 0)
        #expect(try Self.visibleCells(actionScene) == [0], "가만히 선 정면에서 0° 칸이 아니다")
        try Self.facing(actionScene).runAction(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1))
        var seen: [Int] = []
        for t in [0.0, 0.25, 0.5, 0.75] {
            _ = try shooter.shot(at: 10 + t)
            seen.append(contentsOf: try Self.visibleCells(actionScene))
        }
        #expect(seen == [0, 9, 18, 27], "SCNAction 스핀 중 칸 \(seen) — 0·9·18·27 이어야 한다(언제나 하나만)")

        // CAAnimation — 모델 eulerAngles 는 0 으로 남고 presentation 만 돈다. 모델을 읽으면 내내 0 칸이다.
        let animScene = try Self.scene()
        let animShooter = try Shooter(animScene, pointOfView: V0354GoldAing3DTests.cameraNode(animScene))
        let spin = CABasicAnimation(keyPath: "eulerAngles.y")
        spin.fromValue = 0
        spin.toValue = Double.pi
        spin.duration = 1
        // usesSceneTimeBase 를 켜면 SCNRenderer 스냅숏에서 아예 안 돈다(실측) — 기본 시간축이 렌더 시각을 따른다.
        try Self.facing(animScene).addAnimation(spin, forKey: "v0355.spin")
        var animSeen: [Int] = []
        for t in [0.0, 0.5, 0.9] {
            _ = try animShooter.shot(at: t)
            animSeen.append(contentsOf: try Self.visibleCells(animScene))
        }
        #expect(try Self.facing(animScene).eulerAngles.y == 0, "전제: CAAnimation 은 모델 값을 안 바꾼다")
        #expect(animSeen == [0, 9, 16], "CAAnimation 스핀 중 칸 \(animSeen) — presentation 을 안 읽는다")
    }

    // MARK: ③ 결과 — 후광이 몸을 감싼다

    @Test("결과: 앱 카메라 방향에서 40° · 90° · 찔림 중간(롤)에도 후광이 몸을 0° 와 같은 폭으로 감싼다 — 옛 정면 한 장은 빨갛다(기준선)")
    func haloHugsTheBodyAtEveryPose() throws {
        let size = CGSize(width: 512, height: 512)
        // 자세를 걸고(액션이면 다음 렌더 시각부터 돈다) 1초에 한 번 그려 시작시킨 뒤 1 + 반환값 초에 잰다.
        func measure(front: Bool, pose: (SCNScene) throws -> TimeInterval) throws -> Hug {
            let scene = try Self.scene()
            if front { try Self.forceFrontEverywhere(scene) }
            let shooter = try Shooter(scene, pointOfView: try Self.pulledBackCamera(scene))
            _ = try shooter.shot(at: 0)
            let offset = try pose(scene)
            _ = try shooter.shot(at: 1)
            return try Self.hug(scene, shooter: shooter, at: 1 + offset, size: size)
        }
        func yaw(_ deg: Double) -> (SCNScene) throws -> TimeInterval {
            { scene in try Self.facing(scene).eulerAngles = SCNVector3(0, Self.degrees(deg), 0); return 0 }
        }
        // 찔림(실제 리액션 SCNAction). 반 바퀴 스핀 + z 흔들림이라 프레임마다 요·롤이 섞인다 — 0.40…1.60초를 0.05초 간격으로 훑어
        // ① 옆모습 쪽(요 60…120°)이면서 롤이 큰(|롤| > 10°) 첫 프레임과 ② 뒷모습 쪽(요 > 150°)이면서 롤이 큰 첫 프레임을 고른다.
        func pokeStart(_ scene: SCNScene) throws {
            let wrapper = try Self.wrapper(scene)
            let box = wrapper.boundingBox
            wrapper.runAction(ReactionActions.poked(extent: CGFloat(max(box.max.x - box.min.x, box.max.y - box.min.y))))
        }
        let probe = try Self.scene()
        let probeShooter = try Shooter(probe, pointOfView: V0354GoldAing3DTests.cameraNode(probe))
        _ = try probeShooter.shot(at: 0)
        try pokeStart(probe)
        _ = try probeShooter.shot(at: 1)
        var side: (TimeInterval, GoldAingFinish.HaloPose)?, back: (TimeInterval, GoldAingFinish.HaloPose)?
        for offset in stride(from: 0.40, through: 1.60, by: 0.05) {
            _ = try probeShooter.shot(at: 1 + offset)
            let camera = try #require(V0354GoldAing3DTests.cameraNode(probe)).presentation.simdWorldTransform
            let p = GoldAingFinish.haloPose(camera: camera, body: try Self.halo(probe).presentation.simdWorldTransform)
            let yawDeg = abs(Double(p.yaw)) * 180 / .pi, rollDeg = abs(Double(p.roll)) * 180 / .pi
            if side == nil, (60...120).contains(yawDeg), rollDeg > 10 { side = (offset, p) }
            if back == nil, yawDeg > 150, rollDeg > 10 { back = (offset, p) }
        }
        let sidePose = try #require(side, "전제: 찔림에 옆모습 + 롤 프레임이 없다")
        let backPose = try #require(back, "전제: 찔림에 뒷모습 + 롤 프레임이 없다")
        func poked(_ offset: TimeInterval) -> (SCNScene) throws -> TimeInterval {
            { scene in try pokeStart(scene); return offset }
        }
        let zero = try measure(front: false, pose: yaw(0))
        var rows: [String] = []
        // 기준선(옛 정면 한 장)은 정면과 실루엣이 다른 자세에서만 갈린다 — 뒷모습(≈180°)은 정면과 거의 같은 윤곽이라 기준선을 안 건다.
        let poses: [(String, (SCNScene) throws -> TimeInterval, Bool)] = [
            ("40°", yaw(40), true), ("90°", yaw(90), true), ("-90°", yaw(-90), true), ("140°", yaw(140), true),
            (String(format: "찔림 %.2fs", sidePose.0), poked(sidePose.0), true), (String(format: "찔림 %.2fs", backPose.0), poked(backPose.0), false)
        ]
        for (name, pose, baseline) in poses {
            let new = try measure(front: false, pose: pose)
            let old = try measure(front: true, pose: pose)
            rows.append(String(format: "%@ 칸 평균 %.1f 최대 %.1f | 정면 한 장 평균 %.1f 최대 %.1f", name, new.mean, new.max, old.mean, old.max))
            #expect(new.max <= zero.max + 4 && abs(new.mean - zero.mean) <= 1.5,
                    "\(name): 후광이 몸을 감싸는 폭 평균 \(new.mean) · 최대 \(new.max) — 0° 는 \(zero.mean) · \(zero.max)")
            if baseline {
                #expect(old.max > zero.max + 8, "기준선이 안 갈린다(\(name) 정면 한 장 최대 \(old.max) vs 0° \(zero.max))")
            }
        }
        for (offset, p) in [sidePose, backPose] {
            rows.append(String(format: "찔림 %.2fs 자세: 요 %.1f° · 롤 %.1f° · 기울기 %.1f° → 칸 %d", offset, p.yaw * 180 / .pi, p.roll * 180 / .pi,
                               p.tilt * 180 / .pi, GoldAingFinish.haloCell(yaw: Double(p.yaw))))
        }
        print("[v0355-hug] 0° 평균 \(String(format: "%.1f", zero.mean)) 최대 \(String(format: "%.1f", zero.max)) · " + rows.joined(separator: " · "))
    }

    // MARK: ④ 정면은 그대로

    @Test("정면은 그대로: 0° 앱 렌더(앱 카메라 · 시안 카메라)가 0.3.54 판(정면 PNG 한 장 + 빌보드)과 같다")
    func frontLookIsUnchanged() throws {
        for (label, size, front) in [("앱 280×340", CGSize(width: 280, height: 340), false), ("시안 512", CGSize(width: 512, height: 512), true)] {
            let now = try Self.scene()
            let old = try Self.scene()
            // 0.3.54 판을 같은 씬에 다시 세운다: 칸들을 걷고 표식 노드에 정면 판 하나 + 빌보드.
            let oldHalo = try Self.halo(old)
            let cell0 = try #require(oldHalo.childNodes.first)
            let plane = try #require(cell0.geometry?.copy() as? SCNGeometry)
            for child in oldHalo.childNodes { child.removeFromParentNode() }
            plane.boundingBox = (min: SCNVector3(-0.001, -0.001, -0.001), max: SCNVector3(0.001, 0.001, 0.001))
            oldHalo.geometry = plane
            oldHalo.renderingOrder = GoldAingFinish.haloRenderingOrder
            oldHalo.constraints = [SCNBillboardConstraint()]
            let nowImage = try V0354GoldAing3DTests.render(now, pointOfView: front ? V0354GoldAing3DTests.frontCamera(for: now) : nil, size: size)
            let oldImage = try V0354GoldAing3DTests.render(old, pointOfView: front ? V0354GoldAing3DTests.frontCamera(for: old) : nil, size: size)
            let a = try #require(GoldAingFinish.rgbaBytes(nowImage)), b = try #require(GoldAingFinish.rgbaBytes(oldImage))
            var peak = 0, sum = 0
            for i in 0..<a.count { let d = abs(Int(a[i]) - Int(b[i])); peak = max(peak, d); sum += d }
            print(String(format: "[v0355-front] %@: 0.3.54 판과 채널 차 최대 %d · 평균 %.4f", label, peak, Double(sum) / Double(a.count)))
            #expect(peak <= 1, "\(label): 0° 렌더가 0.3.54 판과 최대 \(peak) 다르다")
            #expect(try Self.visibleCells(now) == [0])
        }
        // 기준선: 0° 칸을 160² 로 줄인 그림이면 같은 잣대에서 갈린다(잣대가 차이를 본다).
        let shrunk = try Self.scene()
        let cell0 = try #require(try Self.halo(shrunk).childNodes.first)
        let front = try #require(GoldAingFinish.haloImage())
        let ctx = try #require(CGContext(data: nil, width: 160, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.interpolationQuality = .high
        ctx.draw(front, in: CGRect(x: 0, y: 0, width: 160, height: 160))
        cell0.geometry?.firstMaterial?.diffuse.contents = ctx.makeImage()
        let reference = try V0354GoldAing3DTests.render(try Self.scene(), size: CGSize(width: 280, height: 340))
        let small = try V0354GoldAing3DTests.render(shrunk, size: CGSize(width: 280, height: 340))
        let a = try #require(GoldAingFinish.rgbaBytes(reference)), b = try #require(GoldAingFinish.rgbaBytes(small))
        let peak = zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(peak > 1, "기준선: 0° 칸을 줄여도 잣대가 안 갈린다(최대 \(peak))")
    }

    @Test("각도 칸도 창 합성 보정을 거친다: 90° 를 시안 카메라로 투명 렌더해 바탕에 얹으면 칸 PNG 를 바탕에 얹은 것과 같다 — 보정 없으면 벗어난다")
    func cellsAreWindowCompensated() throws {
        let size = CGSize(width: 512, height: 512)
        let scene = try Self.scene()
        try Self.facing(scene).eulerAngles = SCNVector3(0, Self.degrees(90), 0)
        let halo = try Self.halo(scene)
        halo.isHidden = true
        let body = try V0354GoldAing3DTests.render(scene, pointOfView: V0354GoldAing3DTests.frontCamera(for: scene), size: size)
        halo.isHidden = false
        let transparent = try V0354GoldAing3DTests.render(scene, pointOfView: V0354GoldAing3DTests.frontCamera(for: scene), size: size)
        #expect(try Self.visibleCells(scene) == [9])
        // 칸 PNG(160²)를 512 로 키워 바탕에 얹은 것이 목표(시안 카메라 512 프레임 = 몸 중심 깊이에서 판 2H 그대로).
        let name = GoldAingArt.haloResourceName(cell: 9)
        let raw = try V0354GoldAingArtTests.image(V0354GoldAingArtTests.macDir.appendingPathComponent("\(name).png"))
        let ctx = try #require(CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.interpolationQuality = .high
        ctx.draw(raw, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        let rawLarge = try #require(ctx.makeImage())
        let material = try #require(halo.childNodes[9].geometry?.firstMaterial)
        let compensated = material.diffuse.contents
        material.diffuse.contents = raw
        let uncompensated = try V0354GoldAing3DTests.render(scene, pointOfView: V0354GoldAing3DTests.frontCamera(for: scene), size: size)
        material.diffuse.contents = compensated
        for (bg, gray) in [("light", 0.95), ("dark", 0.11)] {
            let target = try #require(V0354GoldAing3DTests.composite(rawLarge, over: gray))
            let app = V0354GoldAing3DTests.meanDiffOutsideBody(try #require(V0354GoldAing3DTests.composite(transparent, over: gray)), target, body: body)
            let off = V0354GoldAing3DTests.meanDiffOutsideBody(try #require(V0354GoldAing3DTests.composite(uncompensated, over: gray)), target, body: body)
            print(String(format: "[v0355-window] 90° 칸 %@ 바탕: 칸 PNG 와 몸 밖 평균 |ΔRGB| 보정 %.2f · 보정 없음 %.2f", bg, app.mean, off.mean)
                  + " · 최대 \(app.peak) / \(off.peak)")
            #expect(app.mean < 2.5, "\(bg): 창에 보일 90° 후광이 칸 PNG 와 평균 \(app.mean) 다르다")
            #expect(off.mean > app.mean * 3, "\(bg): 기준선이 안 갈린다(보정 없음 \(off.mean) vs 보정 \(app.mean))")
        }
    }

    // MARK: ⑤ 판의 계약 · 교체

    @Test("칸 판 36개: 표식 노드 아래 · 2.0×H 정사각 · 빌보드 → 칸 고르기 · 순서 −1 · 깊이 끔 · 후광 비트 · 0° 만 512²")
    func cellNodesFollowTheArtContract() throws {
        let scene = try Self.scene()
        let halo = try Self.halo(scene)
        #expect(halo.geometry == nil, "표식 노드는 지오메트리가 없다(칸 판이 자식이다)")
        #expect(halo.childNodes.count == 36)
        for (index, cell) in halo.childNodes.enumerated() {
            #expect(cell.name == GoldAingFinish.haloCellNodePrefix + String(format: "%03d", index * 10))
            let plane = try #require(cell.geometry as? SCNPlane)
            #expect(abs(plane.width - 3.391472) < 0.001 && abs(plane.height - 3.391472) < 0.001)
            #expect(plane.boundingBox.max.x - plane.boundingBox.min.x < 0.01, "칸 \(index) 바운딩박스가 점이 아니다")
            #expect(cell.renderingOrder == -1 && cell.categoryBitMask == GoldAingFinish.haloCategoryBit)
            let constraints = cell.constraints ?? []
            #expect(constraints.count == 2 && constraints.first is SCNBillboardConstraint && constraints.last is SCNTransformConstraint,
                    "칸 \(index) 제약 \(constraints)")
            let material = try #require(plane.firstMaterial)
            #expect(material.name == GoldAingFinish.haloMaterialName)
            #expect(material.lightingModel == .constant && material.blendMode == .alpha && material.isDoubleSided)
            #expect(!material.writesToDepthBuffer && !material.readsFromDepthBuffer)
            let image = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
            #expect(image.width == (index == 0 ? 512 : 160), "칸 \(index) 그림 \(image.width)² — 빠져서 정면으로 접혔나")
        }
        // 칸 그림은 서로 다르다(같은 그림 36장이면 고르기가 아무것도 안 바꾼다).
        let images = try halo.childNodes.dropFirst().map { try #require(SleepEyeExplore.cgImage(from: $0.geometry?.firstMaterial?.diffuse.contents)) }
        let bytes = images.map { GoldAingFinish.rgbaBytes($0) ?? [] }
        #expect(Set(bytes.map { $0.hashValue }).count == 35, "각도 칸 그림이 겹친다")
    }

    @Test("교체·원복(울트라 경로)에도 후광 칸 36개가 다시 서고, 렌더하면 하나만 몸 자리에 선다")
    func swapAndRestoreKeepTheCells() throws {
        let engine = ReactionEngine()
        let scene = try Self.scene()
        engine.attach(node: try Self.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let stashed = try #require(engine.swapCharacter(to: CharacterCatalog.builtInAing, in: scene))
        #expect(scene.rootNode.childNode(withName: GoldAingFinish.haloNodeName, recursively: true) == nil)
        #expect(engine.restoreCharacterNode(stashed))
        let shooter = try Shooter(scene, pointOfView: V0354GoldAing3DTests.cameraNode(scene))
        try Self.facing(scene).eulerAngles = SCNVector3(0, Self.degrees(90), 0)
        _ = try shooter.shot(at: 0)
        #expect(try Self.halo(scene).childNodes.count == 36)
        let restored = try Self.visibleCells(scene)
        #expect(restored == [9], "원복한 금 아잉 90° 에서 칸 \(restored)")
        // 교체로 새로 세운 금(makeCharacterNode 경로)도 같다.
        let plain = try #require(CheckCharacter3DScene.makeScene(animated: false, character: CharacterCatalog.builtInAing))
        let plainEngine = ReactionEngine()
        plainEngine.attach(node: try Self.wrapper(plain), sceneRoot: plain.rootNode, view: nil)
        #expect(plainEngine.swapCharacter(to: Self.gold, in: plain) != nil)
        let plainShooter = try Shooter(plain, pointOfView: V0354GoldAing3DTests.cameraNode(plain))
        try Self.facing(plain).eulerAngles = SCNVector3(0, Self.degrees(-40), 0)
        _ = try plainShooter.shot(at: 0)
        let swapped = try Self.visibleCells(plain)
        #expect(swapped == [32], "교체로 세운 금 아잉 −40° 에서 칸 \(swapped)")
    }

    // MARK: ⑥ 그림 · 번들 · 패키징

    @Test("각도 칸 그림 35장(160²)이 저장소와 앱 리소스 번들에 있고 · 테두리 2px 알파 ≤ 0.04 · 빛이 실제로 있다")
    func cellImagesExistAndFade() throws {
        for cell in 1..<GoldAingArt.haloCellCount {
            let name = GoldAingArt.haloResourceName(cell: cell)
            let image = try V0354GoldAingArtTests.image(V0354GoldAingArtTests.macDir.appendingPathComponent("\(name).png"))
            #expect(image.width == 160 && image.height == 160, "\(name) \(image.width)×\(image.height)")
            #expect(V0354GoldAingArtTests.borderAlpha(image) <= 0.04, "\(name) 테두리 알파 \(V0354GoldAingArtTests.borderAlpha(image))")
            #expect(V0354GoldAingArtTests.maxAlpha(image) > 0.9, "\(name) 이 비어 있다")
            #expect(CheckResources.bundle.url(forResource: name, withExtension: "png") != nil, "\(name).png 이 앱 리소스 번들에 없다")
        }
    }

    @Test("맥 패키징 대본 둘: 조립한 앱 안에서 후광 칸 36장을 센다 — 다 있으면 지나가고 한 장 빠지면 멈춘다(대본 조각을 실제로 돌린다)")
    func packagingChecksTheCells() throws {
        for script in ["scripts/build-local.sh", "scripts/package-mas.sh"] {
            let text = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent(script), encoding: .utf8)
            let snippet = try #require(Self.haloCheckSnippet(text), "\(script): 후광 칸 확인 고리가 없다")
            let run = { (present: [String]) throws -> Int32 in try Self.runSnippet(snippet, present: present) }
            #expect(try run(GoldAingArt.haloCellResourceNames) == 0, "\(script): 36장이 다 있는데 멈춘다(이름 규칙이 앱과 다르다)")
            for missing in [GoldAingArt.haloResourceName, GoldAingArt.haloResourceName(cell: 9), GoldAingArt.haloResourceName(cell: 35)] {
                #expect(try run(GoldAingArt.haloCellResourceNames.filter { $0 != missing }) != 0, "\(script): \(missing) 이 빠져도 지나간다")
            }
        }
    }

    /// 대본에서 후광 칸 확인 조각(`GOLD_ART_DIR=` 줄부터 그 뒤 첫 고리의 `done` 까지)을 꺼낸다. 셸 주석 줄은 걷어 낸다.
    static func haloCheckSnippet(_ script: String) -> String? {
        let lines = script.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        guard let start = lines.firstIndex(where: { $0.hasPrefix("GOLD_ART_DIR=") }),
              let loop = lines[start...].firstIndex(where: { $0.hasPrefix("for HALO_DEG in ") }),
              let end = lines[loop...].firstIndex(where: { $0 == "done" }) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    /// 임시 `RES_DIR/check_check.bundle/Contents/Resources` 에 `present` 이름의 PNG(빈 파일 아님)를 만들고 조각을 bash 로 돌린다.
    static func runSnippet(_ snippet: String, present: [String]) throws -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("v0355-halo-pack-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("check_check.bundle/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        for name in present { try Data([0x89, 0x50, 0x4E, 0x47]).write(to: resources.appendingPathComponent("\(name).png")) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "set -euo pipefail\ndie() { echo \"$*\" >&2; exit 1; }\nRES_DIR=\"$1\"\n" + snippet, "snippet", root.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
