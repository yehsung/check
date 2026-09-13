import AppKit
import CoreGraphics
import SceneKit
import Testing
@testable import check

// MARK: - v0.3.15 2-B: 오버레이 스프라이트 통합(졸기 · 알파 클릭 · 방향 · 걷기 · 울트라 갈아입기)
//
// 이 파일이 지키는 것 다섯. 전부 "3D 아잉은 한 톨도 안 바뀐다"를 깔고 간다.
//
// ① **졸기가 아틀라스를 만지지 않는다.** 감은눈 파이프라인은 얼굴 재질을 "큰 CGImage 디퓨즈(≥256)"로 찾는데
//    스프라이트 아틀라스가 그 조건을 만족한다. 종류로 갈라야 막힌다 — 크기 임계값으로는 다음 캐릭터에서 또 뚫린다.
// ② **클릭은 그려진 픽셀에서만 먹는다.** 평면 한 장이라 지오메트리 히트는 투명한 여백에서도 난다.
//    판정의 정답지는 **실제로 렌더된 그림**이다(마스크를 마스크로 검사하면 그 테스트는 영원히 초록이다).
// ③ **방향은 회전이 아니라 프레임이다.** 평면을 y 로 돌리면 옆을 보는 게 아니라 카드가 기운다.
// ④ **걷기는 실제로 다리가 바뀌어야 한다.** 프레임 번호만 도는 것으로는 부족하다 — 픽셀로 가른다.
// ⑤ **울트라 원복은 실패해도 화면을 잃지 않는다.** 캐릭터가 안 돌아오는 것과 화면이 안 돌아오는 것은 급이 다르다.

// MARK: - 헬퍼

/// 번들에 실린 스프라이트 캐릭터 하나(매니페스트 + 아틀라스 이미지).
@MainActor
private func spriteFixture(_ id: String = "fox") throws -> (manifest: CharacterManifest, atlas: CGImage) {
    let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
    let manifest = try #require(catalog.manifest(id: id), "번들에서 \(id) 를 못 찾았다")
    let url = try #require(catalog.atlasURL(for: id))
    let atlas = try #require(SpriteRuntime.decodeImage(at: url))
    return (manifest, atlas)
}

/// 씬 루트 → wrapper → facing → 캐릭터.
@MainActor
private func chain(_ scene: SCNScene) throws -> (wrapper: SCNNode, facing: SCNNode, character: SCNNode) {
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
    let facing = try #require(
        wrapper.childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false))
    let character = try #require(facing.childNodes.first)
    return (wrapper, facing, character)
}

/// 스프라이트 씬 하나 + 그 씬에 붙은 엔진(헤드리스, 뷰 없음).
@MainActor
private func spriteEngine(_ id: String = "fox") throws
    -> (engine: ReactionEngine, scene: SCNScene, character: SCNNode, atlas: CGImage) {
    let fixture = try spriteFixture(id)
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fixture.manifest, atlas: fixture.atlas))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    return (engine, scene, parts.character, fixture.atlas)
}

/// 재질 디퓨즈가 CGImage 면 그것(CF 불투명 타입은 `as?` 가 늘 성공하므로 CFGetTypeID 로 판별).
private func diffuseImage(_ material: SCNMaterial) -> CGImage? {
    guard let contents = material.diffuse.contents,
          CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return nil }
    return (contents as! CGImage)
}

/// 서브트리에서 얼굴 재질('큰 CGImage 디퓨즈')을 찾는다 — 엔진의 `locateSleepEyeTargets` 와 같은 식.
@MainActor
private func faceMaterial(in node: SCNNode) -> SCNMaterial? {
    var found: SCNMaterial?
    node.enumerateHierarchy { child, stop in
        for material in child.geometry?.materials ?? [] where (diffuseImage(material)?.width ?? 0) >= 256 {
            found = material
            stop.pointee = true
            return
        }
    }
    return found
}

/// 노드에 지금 걸린 텍스처 변환의 이동 성분(= 아틀라스에서 어느 셀을 보고 있는가)과 x 스케일 부호(= 미러).
@MainActor
private func cellSignature(_ node: SCNNode) throws -> (offsetX: Float, offsetY: Float, scaleX: Float) {
    let material = try #require(node.geometry?.firstMaterial)
    let t = material.diffuse.contentsTransform
    return (Float(t.m41), Float(t.m42), Float(t.m11))
}

/// CGImage 를 RGBA8 로 펴서 알파 배열을 돌려준다(행 0 = **위쪽** 줄).
private func alphaPlane(_ image: CGImage) -> (alpha: [UInt8], width: Int, height: Int)? {
    let w = image.width, h = image.height
    guard w > 0, h > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ok: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard ok else { return nil }
    return (stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }, w, h)
}

/// PNG 두 장의 픽셀 차이 비율(%). 걷기가 **실제로 다리를 바꿨는지**를 숫자로 가른다.
private func pixelDifference(_ lhs: Data, _ rhs: Data) -> Double? {
    guard let a = NSBitmapImageRep(data: lhs)?.cgImage, let b = NSBitmapImageRep(data: rhs)?.cgImage,
          a.width == b.width, a.height == b.height else { return nil }
    func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? bytes : nil
    }
    guard let pa = rgba(a), let pb = rgba(b) else { return nil }
    var differing = 0
    for index in stride(from: 0, to: pa.count, by: 4) where
        abs(Int(pa[index]) - Int(pb[index])) > 16 || abs(Int(pa[index + 3]) - Int(pb[index + 3])) > 16 {
        differing += 1
    }
    return Double(differing) / Double(a.width * a.height) * 100
}

/// 걷기 렌더 산출물 폴더(저장소 **밖**). 사람이 눈으로 보려고 여는 자리다.
private let walkRenderDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("check-v0315b-walk", isDirectory: true)

/// 패널을 화면 한복판에 세운다. **드래그 검증은 클램프에 닿으면 안 된다** — 기본 위치는 화면 오른쪽 끝이라
/// 어느 쪽으로든 60pt 를 끌면 한쪽이 클램프에 걸려 패널이 안 움직이고, 그러면 "이동 중" 신호가 서지 않아
/// 검사가 통째로 아무것도 못 본다(실제로 한 번 당했다).
@MainActor
private func centerPanel(_ controller: CheckOverlayController) {
    let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let size = controller.panel.frame.size
    controller.panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                            y: visible.midY - size.height / 2))
}

/// 격리된 UserDefaults 위에 세운 오버레이 컨트롤러(전역 도메인·노티 오염 금지 — 기존 스위트와 같은 규약).
@MainActor
private func isolatedOverlayController() -> CheckOverlayController {
    let suiteName = "check-v0315b-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    // ★ 스토어 상태를 **실제로** 근무중으로 맞춘다. updateWorking(true) 만 부르면 SwiftUI 루트 뷰의
    //   `.onChange(of: store.snapshot.isWorking, initial: true)` 가 곧바로 updateWorking(false) 를 되불러
    //   (wasVisible != visible) 방금 세운 격발을 endUltraTakeover 로 접는다 — 그 함정은 프로덕션 주석이
    //   이미 적어 둔 것이고, 여기서 걸리면 테스트가 아무것도 못 본다.
    store.setOverlayEnabled(true)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    let controller = CheckOverlayController(store: store, notificationCenter: NotificationCenter())
    controller.updateWorking(true)
    return controller
}

// MARK: - ① ☠︎ 졸기가 아틀라스를 만지지 않는다

@MainActor
@Test("스프라이트 졸기는 아틀라스를 건드리지 않는다 — 감은눈 파이프라인 자체를 안 태운다")
func v0315bDrowsyLeavesTheAtlasAlone() throws {
    let parts = try spriteEngine()
    let material = try #require(parts.character.geometry?.firstMaterial)
    let before = try #require(diffuseImage(material))

    #expect(parts.engine.isSpriteCharacter, "스프라이트를 붙였는데 엔진이 3D 로 본다 — 나머지 갈래가 전부 죽는다")
    #expect(parts.engine.request(.drowsy), "졸기가 거절됐다 — 이 검사가 아무것도 못 본다")
    #expect(parts.engine.state == .sleeping)

    let after = try #require(diffuseImage(material))
    let assignments = parts.engine.faceDiffuseCGImageAssignments + parts.engine.faceDiffuseTextureAssignments
    print("[v0315b] 졸기 단독 — 디퓨즈 대입 \(assignments)회 · 아틀라스 동일 \(after === before)")
    #expect(after === before, "졸기가 아틀라스를 감은눈 버전으로 갈아 끼웠다 — 몸에 피부색 얼룩이 생긴다")
    #expect(assignments == 0, "스프라이트인데 얼굴 디퓨즈를 대입했다")

    // 기울기는 그대로 걸려야 한다(DECISIONS: 전용 졸기 프레임이 없으면 기울기만). 잠에서 깨면 원복된다.
    #expect(parts.character.geometry?.firstMaterial?.diffuse.contentsTransform.m41 != nil)
    parts.engine.wakeQuietly()
    #expect(parts.engine.state == .idle)
    let awake = try #require(diffuseImage(material))
    #expect(awake === before, "기상이 아틀라스를 바꿨다")
}

@MainActor
@Test("Metal 뷰로 attach 해도 스프라이트는 얼굴 GPU 텍스처를 만들지 않는다")
func v0315bSpriteMakesNoFaceTextures() throws {
    let fixture = try spriteFixture()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fixture.manifest, atlas: fixture.atlas))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    let view = SCNView()
    view.scene = scene
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: view)
    #expect(engine.hasFaceTextures == false, "스프라이트인데 얼굴 텍스처 쌍을 구웠다 — 감은눈 파이프라인에 물렸다")

    // 깜빡임도 같은 이유로 물러난다(없는 프레임을 깜빡일 수는 없고, 격발 중이면 떼어 둔 아잉을 만진다).
    engine.renderActive = true
    engine.blink()
    #expect(engine.faceDiffuseCGImageAssignments + engine.faceDiffuseTextureAssignments == 0)
}

@MainActor
@Test("아잉(3D)의 감은눈 경로는 그대로다 — 스프라이트 분기가 3D 를 같이 끄지 않았다")
func v0315bAingSleepPathSurvives() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    #expect(engine.isSpriteCharacter == false, "아잉인데 스프라이트로 봤다")
    #expect(engine.request(.drowsy))
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName,
                                     recursively: true)?.isHidden == false,
            "아잉이 잠들었는데 감은 선이 안 보인다 — 3D 경로를 같이 껐다")
    #expect(engine.faceDiffuseCGImageAssignments >= 1, "아잉 얼굴 디퓨즈가 교체되지 않았다")
}

// MARK: - ③ 방향 → 프레임

@MainActor
@Test("방향은 y 회전이 아니라 프레임이다 — 0 정면 · +1 옆모습 · -1 같은 프레임 미러")
func v0315bFacingSwitchesFramesNotRotation() throws {
    let parts = try spriteEngine()
    let manifest = try #require(CharacterCatalog.load(bundle: CheckResources.bundle).manifest(id: "fox"))
    let spec = try #require(manifest.atlas)
    let front = try #require(spec.states[CharacterManifest.StateKey.frontIdle]?.frames.first)
    let side = try #require(spec.states[CharacterManifest.StateKey.sideIdle]?.frames.first)
    let facing = try chain(parts.scene).facing

    // 0 = 정면.
    #expect(parts.engine.spriteFrameState?.state == CharacterManifest.StateKey.frontIdle)
    var signature = try cellSignature(parts.character)
    #expect(abs(signature.offsetX - Float(CGFloat(front.x) / CGFloat(spec.width))) < 1e-5)
    #expect(signature.scaleX > 0, "정면인데 미러가 걸렸다")

    // +1 = 옆모습(미러 없음).
    parts.engine.setDragFacing(1)
    #expect(parts.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle)
    #expect(parts.engine.spriteFrameState?.mirrored == false)
    signature = try cellSignature(parts.character)
    #expect(abs(signature.offsetX - Float(CGFloat(side.x) / CGFloat(spec.width))) < 1e-5,
            "+1 이 옆모습 셀을 안 가리킨다")
    #expect(signature.scaleX > 0)

    // -1 = **같은 프레임**의 수평 미러. 셀이 달라지면 추가 에셋을 쓴 것이다(그럴 에셋이 없다).
    parts.engine.setDragFacing(-1)
    #expect(parts.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle)
    #expect(parts.engine.spriteFrameState?.mirrored == true)
    let mirrored = try cellSignature(parts.character)
    #expect(mirrored.scaleX < 0, "-1 인데 x 스케일이 양수다 — 미러가 안 걸렸다")
    // 미러는 오프셋을 셀의 **오른쪽 끝**으로 민다(contentsTransform 식). 셀 폭만큼 차이가 나야 한다.
    let cellWidth = Float(CGFloat(side.w) / CGFloat(spec.width))
    #expect(abs((mirrored.offsetX - signature.offsetX) - cellWidth) < 1e-5,
            "미러 오프셋이 같은 셀의 오른쪽 끝이 아니다 — 다른 프레임을 보고 있다")

    // facing 노드는 **끝까지 정면에 못 박혀 있어야 한다**. 평면을 y 로 돌리면 카드가 기운다.
    #expect(abs(Double(facing.eulerAngles.y)) < 1e-6, "스프라이트인데 facing 노드가 돌았다")

    // 즉시 스냅 계약(보간 없음): facing 에 액션이 남아 있으면 안 된다.
    #expect(facing.action(forKey: "check.facing") == nil)
    print("[v0315b] 방향 프레임 — 정면 \(front.x) · 옆 \(side.x) · 미러 scaleX \(mirrored.scaleX)")
}

@MainActor
@Test("아잉(3D)의 방향은 여전히 y 회전이다 — 프레임 분기가 3D 를 가로채지 않았다")
func v0315bAingFacingStillRotates() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    engine.setDragFacing(1)
    #expect(abs(CGFloat(parts.facing.eulerAngles.y) - ReactionEngine.dragFacingAngle) < 1e-5)
    engine.setDragFacing(-1, moving: true)   // moving 은 3D 에서 아무 일도 하지 않는다
    #expect(abs(CGFloat(parts.facing.eulerAngles.y) + ReactionEngine.dragFacingAngle) < 1e-5)
    engine.setDragFacing(0)
    #expect(abs(CGFloat(parts.facing.eulerAngles.y)) < 1e-6)
}

// MARK: - ④ 걷기

@MainActor
@Test("드래그로 이동 중이면 옆모습 걷기, 멈추면 옆모습 idle, 놓으면 정면")
func v0315bWalkStateFollowsMovement() throws {
    let parts = try spriteEngine()

    parts.engine.setDragFacing(1, moving: true)
    #expect(parts.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideWalk, "이동 중인데 안 걷는다")
    #expect(parts.engine.isWalking)

    // 같은 방향으로 계속 끌어도 프레임이 0 으로 리셋되지 않는다(setState 의 no-op 계약).
    // ★ 시계는 **런타임이 기록한 시작 시각** 기준이다(엔진의 clock 은 절대 시각이라 0.15 를 그냥 주면
    //   경과가 음수가 되어 영원히 첫 프레임이다 — 실제로 한 번 당했다).
    let walkStart = try #require(parts.engine.spriteRuntime).stateStartedAt
    parts.engine.advanceSpriteFrame(now: walkStart + 0.15)
    let advanced = try #require(parts.engine.spriteFrameState)
    parts.engine.setDragFacing(1, moving: true)
    #expect(parts.engine.spriteFrameState?.frame == advanced.frame, "같은 방향 재호출이 걷기를 첫 프레임으로 되감았다")

    // 방향만 잡고 멈추면 옆모습 idle.
    parts.engine.setDragFacing(1, moving: false)
    #expect(parts.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle, "멈췄는데 계속 걷는다")
    #expect(parts.engine.isWalking == false)

    // 놓으면(정면 복귀) 걷기는 의미가 없다.
    parts.engine.setDragFacing(0, moving: true)
    #expect(parts.engine.spriteFrameState?.state == CharacterManifest.StateKey.frontIdle)
    #expect(parts.engine.isWalking == false, "정면을 보면서 걷고 있다")

    // setWalking 은 방향을 건드리지 않고 걷기만 끈다(handleMouseUp 의 계약).
    parts.engine.setDragFacing(-1, moving: true)
    #expect(parts.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideWalk)
    parts.engine.setWalking(false)
    #expect(parts.engine.currentDragFacing == -1, "setWalking 이 방향까지 바꿨다")
    #expect(parts.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle)
}

@MainActor
@Test("걷기 프레임은 시간이 지나면 돌고, 바뀌었을 때만 노드를 갱신한다")
func v0315bWalkAdvancesFrames() throws {
    let parts = try spriteEngine()
    parts.engine.setDragFacing(1, moving: true)

    // 여우 걷기는 140ms × 4. 같은 프레임 안에서는 노드를 만지지 않아야 한다.
    let base = try #require(parts.engine.spriteRuntime).stateStartedAt
    #expect(parts.engine.advanceSpriteFrame(now: base + 0.05) == false, "같은 프레임인데 노드를 갱신했다")
    var seen: [Int] = [try #require(parts.engine.spriteFrameState).frame]
    var cells: [Float] = [try cellSignature(parts.character).offsetX]
    for step in 1...4 {
        let changed = parts.engine.advanceSpriteFrame(now: base + Double(step) * 0.14 + 0.001)
        #expect(changed, "프레임 경계를 넘겼는데 안 바뀌었다(step \(step))")
        seen.append(try #require(parts.engine.spriteFrameState).frame)
        cells.append(try cellSignature(parts.character).offsetX)
    }
    print("[v0315b] 걷기 프레임 진행 \(seen) · 셀 오프셋 \(cells.map { String(format: "%.3f", $0) })")
    #expect(seen == [0, 1, 2, 3, 0], "걷기가 0,1,2,3 을 돌고 처음으로 안 돌아왔다")
    // 여우 재생순서는 0,1,2,1 이라 셀 1 과 3 은 **같은 rect** 다. 0/1/2 는 서로 달라야 한다.
    #expect(cells[0] != cells[1] && cells[1] != cells[2] && cells[0] != cells[2],
            "걷기 프레임이 같은 셀만 가리킨다 — 다리가 안 바뀐다")
    #expect(abs(cells[1] - cells[3]) < 1e-6, "여우 재생순서(0,1,2,1)가 깨졌다")
}

@MainActor
@Test("걷기 프레임이 없는 캐릭터는 옆모습 idle 로 접는다 — frontIdle 로 떨어지지 않는다")
func v0315bWalkFoldsToSideIdleWhenMissing() throws {
    let fixture = try spriteFixture()
    let spec = try #require(fixture.manifest.atlas)
    // 걷기만 뺀 매니페스트(같은 아틀라스). 런타임의 자동 폴백은 frontIdle 이라, 여기서 sideIdle 로
    // 접어 주는 사람이 없으면 "옆을 보라고 했는데 정면"이 된다.
    let noWalk = CharacterManifest(
        id: fixture.manifest.id, displayName: fixture.manifest.displayName, kind: .sprite,
        atlas: CharacterManifest.Atlas(
            file: spec.file, width: spec.width, height: spec.height,
            states: spec.states.filter { $0.key != CharacterManifest.StateKey.sideWalk }),
        portrait: fixture.manifest.portrait)
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    // ★ **매니페스트를 아는 경로**로 넣는다. attach 의 자동 판정은 아틀라스로 카탈로그를 역추적하므로
    //   번들의 여우(걷기 있음)를 찾아내고, 이 픽스처가 통째로 무시된다(그렇게 한 번 당했다).
    #expect(engine.swapCharacter(to: noWalk, in: scene) != nil, "교체가 실패했다 — 이 검사가 아무것도 못 본다")
    let runtime = try #require(engine.spriteRuntime)
    #expect(runtime.manifest.atlas?.states[CharacterManifest.StateKey.sideWalk] == nil)
    #expect(runtime.hasState(CharacterManifest.StateKey.sideWalk) == false)

    engine.setDragFacing(1, moving: true)
    #expect(engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle,
            "걷기가 없는 캐릭터가 frontIdle 로 떨어졌다 — 옆을 보라고 했는데 정면이다")
}

@MainActor
@Test("걷기를 오프스크린으로 구워 눈으로 확인한다 — 다리가 실제로 바뀐다")
func v0315bWalkRendersDistinctLegs() throws {
    let fixture = try spriteFixture()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fixture.manifest, atlas: fixture.atlas))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    engine.setDragFacing(1, moving: true)
    let runtime = try #require(engine.spriteRuntime)
    #expect(runtime.stateKey == CharacterManifest.StateKey.sideWalk)

    try? FileManager.default.createDirectory(at: walkRenderDirectory, withIntermediateDirectories: true)
    var frames: [Data] = []
    var paths: [String] = []
    for index in 0..<4 {
        // 시계를 프레임 경계 너머로 밀어 한 칸씩 진행시킨다(실시간을 기다리지 않는다).
        if index > 0 { engine.advanceSpriteFrame(now: runtime.stateStartedAt + Double(index) * 0.14 + 0.001) }
        #expect(runtime.frameIndex == index, "프레임 \(index) 로 못 갔다")
        let png = try #require(CheckCharacter3DScene.renderSnapshotPNG(
            scene: scene, size: CGSize(width: 280, height: 340)), "프레임 \(index) 렌더 실패")
        frames.append(png)
        let url = walkRenderDirectory.appendingPathComponent("fox-sidewalk-\(index).png")
        try? png.write(to: url)
        paths.append(url.path)
    }
    print("[v0315b] 걷기 렌더 \(paths.joined(separator: " "))")

    // ★ 정답지는 프레임 번호가 아니라 **그림**이다. 번호만 도는 채 같은 셀을 그리면 "걷는 것으로 보이지 않는다".
    let d01 = try #require(pixelDifference(frames[0], frames[1]))
    let d12 = try #require(pixelDifference(frames[1], frames[2]))
    let d02 = try #require(pixelDifference(frames[0], frames[2]))
    let d13 = try #require(pixelDifference(frames[1], frames[3]))
    print(String(format: "[v0315b] 걷기 픽셀 차이 %% — 0↔1 %.2f · 1↔2 %.2f · 0↔2 %.2f · 1↔3 %.2f",
                 d01, d12, d02, d13))
    #expect(d01 > 0.5 && d12 > 0.5 && d02 > 0.5, "걷기 프레임이 그림으로 구별되지 않는다 — 다리가 안 바뀐다")
    #expect(d13 < 0.01, "여우 재생순서(0,1,2,1)라면 1 과 3 은 같은 그림이어야 한다")
}

// MARK: - ② 알파 히트테스트(실제 창 + 실제 렌더 정답지)

@MainActor
@Test("클릭은 그려진 픽셀에서만 먹는다 — 격자 점을 렌더 그림과 대조한다")
func v0315bAlphaHitTestMatchesWhatIsDrawn() throws {
    #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 거짓이면 아래 창이 사용자 화면에 뜬다")
    let fixture = try spriteFixture()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fixture.manifest, atlas: fixture.atlas))
    let parts = try chain(scene)

    let size = NSSize(width: 140, height: 170)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = 0            // 기하는 그대로, 합성만 지운다(CheckPanelVisibility 와 같은 규약).
    window.isOpaque = false
    window.backgroundColor = .clear
    defer { window.orderOut(nil) }
    let view = SCNView(frame: NSRect(origin: .zero, size: size))
    view.scene = scene
    view.backgroundColor = .clear
    window.contentView = view
    window.orderFrontRegardless()

    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: view)
    #expect(engine.isSpriteCharacter)

    // ★ 정답지는 **같은 씬을 같은 크기로 렌더한 그림**이다. 마스크를 마스크로 검사하면 그 테스트는
    //   기준선이 자기 자신이라 영원히 초록이다(기준선이 달라야 한다).
    let png = try #require(CheckCharacter3DScene.renderSnapshotPNG(scene: scene, size: size))
    let shot = try #require(NSBitmapImageRep(data: png)?.cgImage)
    let plane = try #require(alphaPlane(shot))

    func drawnAlpha(atViewPoint point: NSPoint) -> UInt8 {
        // 뷰 로컬(좌하단 원점) → 렌더 픽셀(좌상단 원점). 렌더 해상도가 뷰 포인트와 다를 수 있어 비율로 옮긴다.
        let x = Int((point.x / size.width) * CGFloat(plane.width))
        let y = Int(((size.height - point.y) / size.height) * CGFloat(plane.height))
        guard x >= 0, y >= 0, x < plane.width, y < plane.height else { return 0 }
        return plane.alpha[y * plane.width + x]
    }

    var agree = 0, total = 0, disagree: [(NSPoint, Bool, UInt8)] = []
    var opaqueHits = 0
    for column in 0..<20 {
        for row in 0..<24 {
            let local = NSPoint(x: (CGFloat(column) + 0.5) * size.width / 20,
                                y: (CGFloat(row) + 0.5) * size.height / 24)
            let screen = window.convertPoint(toScreen: view.convert(local, to: nil))
            let hit = engine.isBodyAtScreenPoint(screen)
            let drawn = drawnAlpha(atViewPoint: local)
            total += 1
            if hit { opaqueHits += 1 }
            // 가장자리 안티에일리어싱(0 < alpha < 255)은 두 판정이 갈려도 정상이다 — 확실한 픽셀만 센다.
            if drawn > 200 || drawn < 16 {
                if hit == (drawn > 200) { agree += 1 } else { disagree.append((local, hit, drawn)) }
            } else {
                agree += 1
            }
        }
    }
    let rate = Double(agree) / Double(total) * 100
    print(String(format: "[v0315b] 알파 히트테스트 격자 %d점 — 일치 %d (%.1f%%) · 몸 판정 %d점 · 불일치 %d",
                 total, agree, rate, opaqueHits, disagree.count))
    for (point, hit, drawn) in disagree.prefix(6) {
        print(String(format: "[v0315b]   불일치 (%.1f, %.1f) hit=%@ drawnAlpha=%d",
                     point.x, point.y, hit ? "true" : "false", Int(drawn)))
    }
    #expect(rate >= 97, "클릭 판정이 화면에 그려진 것과 갈린다(일치 \(String(format: "%.1f", rate))%)")

    // 몸통 중앙은 반드시 true. (프레이밍 카메라가 캐릭터를 화면 중앙에 세운다.)
    let center = window.convertPoint(toScreen: view.convert(NSPoint(x: size.width / 2, y: size.height / 2), to: nil))
    #expect(engine.isBodyAtScreenPoint(center), "몸통 중앙이 몸이 아니라고 나온다")
    // 네 모서리(투명 여백)는 반드시 false — 평면 한 장이라 **지오메트리 히트는 여기서도 난다**.
    for corner in [NSPoint(x: 3, y: 3), NSPoint(x: size.width - 3, y: 3),
                   NSPoint(x: 3, y: size.height - 3), NSPoint(x: size.width - 3, y: size.height - 3)] {
        let screen = window.convertPoint(toScreen: view.convert(corner, to: nil))
        #expect(engine.isBodyAtScreenPoint(screen) == false,
                "투명한 모서리 (\(corner.x), \(corner.y)) 에서 클릭이 먹는다")
    }
}

// MARK: - ⑥ 울트라 = 찌른 사람 캐릭터

@MainActor
@Test("울트라가 발신자 캐릭터로 갈아입고 원복한다 — 뷰가 아니라 노드를 바꾼다")
func v0315bUltraSwapsCharacterAndRestoresTheSameNode() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)

    let fox = try #require(CheckCharacter3DScene.catalog.manifest(id: "fox"))
    let stashed = try #require(engine.swapCharacter(to: fox, in: scene), "교체가 실패했다")
    #expect(stashed === parts.character, "떼어낸 것이 내 캐릭터가 아니다")
    #expect(engine.currentCharacterID == "fox")
    #expect(engine.isSpriteCharacter)
    // ★ wrapper/facing 은 **같은 객체**로 살아남아야 한다(뷰 재생성과 같은 비용을 내지 않았다는 증거).
    let afterSwap = try chain(scene)
    #expect(afterSwap.wrapper === parts.wrapper && afterSwap.facing === parts.facing)
    #expect(afterSwap.character !== parts.character)

    // 원복은 **떼어 뒀던 그 노드**를 도로 붙이는 것이다(다시 만들면 USDZ 재로드 + 감은눈 굽기가 또 돈다).
    #expect(engine.restoreCharacterNode(stashed))
    let restored = try chain(scene)
    #expect(restored.character === parts.character, "원복이 아잉을 새로 만들었다")
    #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
    #expect(engine.isSpriteCharacter == false)

    // 원복 뒤 아잉의 감은눈 경로가 살아 있어야 한다(교체가 캐시를 죽이지 않았다).
    #expect(engine.request(.drowsy))
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName,
                                     recursively: true)?.isHidden == false,
            "격발 왕복 뒤 아잉이 눈을 못 감는다 — 감은눈 캐시가 떼어낸 노드를 가리키고 있다")
}

@MainActor
@Test("모르는 캐릭터 ID·nil 은 교체하지 않는다 — throw 하지 않고 내 캐릭터 그대로")
func v0315bUnknownCharacterIDKeepsMine() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)

    #expect(CheckCharacter3DScene.catalog.manifest(id: "nope-not-a-character") == nil)
    // 씬을 못 잡는 경우(뷰 미마운트)도 조용히 실패한다.
    let headless = ReactionEngine()
    let fox = try #require(CheckCharacter3DScene.catalog.manifest(id: "fox"))
    #expect(headless.swapCharacter(to: fox) == nil, "attach 도 안 된 엔진이 교체에 성공했다")
    #expect(try chain(scene).character === parts.character)
    #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
}

@MainActor
@Test("격발 왕복 뒤에도 방향·걷기 계약이 살아 있다 — 재-attach 가 방향을 다시 먹인다")
func v0315bFacingSurvivesTheSwap() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    engine.setDragFacing(-1)   // 3D 로 왼쪽을 보고 있다(facing y 회전).
    #expect(abs(CGFloat(parts.facing.eulerAngles.y) + ReactionEngine.dragFacingAngle) < 1e-5)

    let fox = try #require(CheckCharacter3DScene.catalog.manifest(id: "fox"))
    let stashed = try #require(engine.swapCharacter(to: fox, in: scene))
    // 보관 중이던 -1 이 **프레임으로** 다시 적용돼야 한다(재-attach 가 applyDragFacingToNode 를 부른다).
    #expect(engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle)
    #expect(engine.spriteFrameState?.mirrored == true, "-1 이 미러로 안 넘어왔다")
    #expect(abs(Double(parts.facing.eulerAngles.y)) < 1e-6, "스프라이트가 3D 의 옛 회전각을 물려받았다")

    #expect(engine.restoreCharacterNode(stashed))
    #expect(abs(CGFloat(parts.facing.eulerAngles.y) + ReactionEngine.dragFacingAngle) < 1e-5,
            "아잉으로 돌아왔는데 회전이 복원되지 않았다")
}

// MARK: - ⑤ 컨트롤러 배선(드래그 → 걷기, 격발 → 갈아입기, 원복의 우선순위)

@MainActor
@Test("드래그가 걷기를 켜고 놓으면 끈다 — 보드 연동 순서는 그대로")
func v0315bDragWiringDrivesWalking() throws {
    let controller = isolatedOverlayController()
    let fixture = try spriteFixture()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fixture.manifest, atlas: fixture.atlas))
    let parts = try chain(scene)
    controller.engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    #expect(controller.engine.isSpriteCharacter)

    centerPanel(controller)
    let origin = controller.panel.frame.origin
    let start = NSPoint(x: controller.panel.frame.midX, y: controller.panel.frame.midY)
    controller.handleMouseDown(at: start)
    // ★ **왼쪽으로** 끈다. 기본 위치가 화면 오른쪽 끝이라 +x 는 클램프에 걸려 패널이 안 움직이고,
    //   그러면 "이동 중" 신호가 서지 않아 이 검사가 통째로 아무것도 못 본다(실제로 한 번 당했다).
    controller.handleMouseDragged(at: NSPoint(x: start.x - 60, y: start.y))
    #expect(controller.engine.currentDragFacing == -1, "왼쪽으로 끄는데 왼쪽을 안 본다")
    #expect(controller.engine.isWalking, "끄는 중인데 안 걷는다")
    #expect(controller.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideWalk)
    #expect(controller.engine.spriteFrameState?.mirrored == true, "왼쪽인데 미러가 안 걸렸다")
    #expect(controller.panel.frame.origin != origin, "패널이 안 움직였다 — 이 검사가 아무것도 못 본다")

    // 같은 자리로 다시 통지(= 이동 없음) → 방향은 유지, 걷기만 꺼진다.
    let held = controller.panel.frame.origin
    controller.handleMouseDragged(at: NSPoint(x: start.x - 60, y: start.y))
    #expect(controller.panel.frame.origin == held)
    #expect(controller.engine.isWalking == false, "제자리인데 계속 걷는다")
    #expect(controller.engine.currentDragFacing == -1, "멈췄다고 방향까지 풀렸다")
    #expect(controller.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle)

    // 놓으면 걷기는 반드시 꺼지고(보드 계약과 무관), 보드가 닫혀 있으므로 정면으로 돌아온다.
    controller.handleMouseDragged(at: NSPoint(x: start.x - 90, y: start.y))
    #expect(controller.engine.isWalking)
    controller.handleMouseUp(at: NSPoint(x: start.x - 90, y: start.y))
    #expect(controller.engine.isWalking == false, "손을 뗐는데 계속 걷는다")
    #expect(controller.engine.currentDragFacing == 0)
    #expect(controller.engine.spriteFrameState?.state == CharacterManifest.StateKey.frontIdle)
    controller.updateWorking(false)
}

@MainActor
@Test("보드가 열려 있으면 놓는 순간에도 걷기만 꺼진다 — 방향의 주인은 보드다")
func v0315bReleaseWithBoardOpenStopsWalkingOnly() throws {
    let controller = isolatedOverlayController()
    let fixture = try spriteFixture()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fixture.manifest, atlas: fixture.atlas))
    let parts = try chain(scene)
    controller.engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)
    centerPanel(controller)
    controller.isBoardOpen = { true }
    // 보드 배선이 하는 일을 그대로 흉내낸다: 프레임 통지를 받으면 보드 쪽(-1)을 바라보게 한다.
    controller.onCharacterFrameChanged = { [weak controller] (_: NSRect, _: NSRect) in
        controller?.engine.setDragFacing(1)
    }

    let start = NSPoint(x: controller.panel.frame.midX, y: controller.panel.frame.midY)
    controller.handleMouseDown(at: start)
    controller.handleMouseDragged(at: NSPoint(x: start.x - 60, y: start.y))
    #expect(controller.engine.currentDragFacing == -1, "드래그 중에는 '가는 방향'이 보드 쪽을 덮는다(기존 계약)")
    #expect(controller.engine.isWalking)

    controller.handleMouseUp(at: NSPoint(x: start.x - 60, y: start.y))
    #expect(controller.engine.isWalking == false, "손을 뗐는데 계속 걷는다")
    #expect(controller.engine.currentDragFacing == 1, "보드가 열려 있는데 정면으로 되돌렸다")
    #expect(controller.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle)

    // ★ 보드는 열려 있는데 **배선이 없는** 세계(통지를 받는 쪽이 아직 안 꽂혔다). 여기서는 아무도
    //   setDragFacing 을 되불러 주지 않으므로, handleMouseUp 자신이 걷기를 끄지 않으면 캐릭터가
    //   손을 뗀 자리에서 **영원히 제자리걸음**을 한다(방향은 보드 몫이라 정면 복귀도 안 온다).
    controller.onCharacterFrameChanged = nil
    controller.handleMouseDown(at: start)
    controller.handleMouseDragged(at: NSPoint(x: start.x - 60, y: start.y))
    #expect(controller.engine.isWalking, "이 검사가 아무것도 못 본다 — 걷기가 안 켜졌다")
    controller.handleMouseUp(at: NSPoint(x: start.x - 60, y: start.y))
    #expect(controller.engine.isWalking == false, "배선 없는 보드에서 손을 뗐는데 제자리걸음이 남았다")
    #expect(controller.engine.spriteFrameState?.state == CharacterManifest.StateKey.sideIdle)

    controller.isBoardOpen = nil
    controller.updateWorking(false)
}

@MainActor
@Test("울트라 원복은 캐릭터가 안 돌아와도 프레임·못박기를 반드시 푼다")
func v0315bUltraRestoreNeverLosesTheScreen() throws {
    let controller = isolatedOverlayController()
    let before = controller.panel.frame
    // 캐릭터가 붙어 있지 않은 상태(씬 미마운트)로 격발한다 = 갈아입기가 **실패하는** 세계.
    controller.handleReceivedPokes([
        ReceivedPoke(id: "u1", fromName: "누군가", createdAt: Date(), kind: .ultra, fromCharacterID: "fox")
    ])
    #expect(controller.isUltraActive, "격발이 안 섰다 — 이 검사가 아무것도 못 본다")
    #expect(controller.panel.frame != before, "격발이 화면을 안 덮었다")

    controller.endUltraTakeover()
    #expect(controller.isUltraActive == false)
    #expect(controller.panel.frame == before, "원복이 프레임을 안 되돌렸다 — 화면을 잃는 사고다")
    #expect(controller.panel.ignoresMouseEvents, "못 박기가 안 풀렸다 — 화면이 영영 클릭을 먹는다")
    controller.updateWorking(false)
}

@MainActor
@Test("아잉 → 아잉 교체에도 감은눈이 **화면의** 캐릭터에 걸린다 — 캐시 열쇠는 씬이 아니라 노드다")
func v0315bSleepEyeCacheFollowsTheVisibleCharacter() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let parts = try chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: parts.wrapper, sceneRoot: scene.rootNode, view: nil)

    // 발신자도 아잉인 격발(내가 스프라이트를 입고 있을 때 일어난다). 씬은 그대로, **캐릭터만** 새 아잉으로
    // 바뀐다 — 씬 루트만 열쇠로 쓰면 여기서 캐시가 그대로 재사용돼 **떼어낸 옛 노드**에 감은눈을 칠한다.
    #expect(engine.swapCharacter(to: CharacterCatalog.builtInAing, in: scene) != nil)
    let fresh = try chain(scene).character
    #expect(fresh !== parts.character, "교체가 같은 노드를 돌려줬다 — 이 검사가 아무것도 못 본다")

    let staleMaterial = try #require(faceMaterial(in: parts.character), "옛 아잉에서 얼굴 재질을 못 찾았다")
    let staleBefore = try #require(diffuseImage(staleMaterial))
    let visibleFace = try #require(faceMaterial(in: fresh), "새 아잉에서 얼굴 재질을 못 찾았다")
    let visibleBefore = try #require(diffuseImage(visibleFace))
    #expect(visibleFace !== staleMaterial, "두 아잉이 같은 재질을 공유한다 — 이 검사가 아무것도 못 본다")

    #expect(engine.request(.drowsy))
    #expect(diffuseImage(visibleFace) !== visibleBefore,
            "화면에 있는 캐릭터가 눈을 안 감았다 — 감은눈 캐시가 떼어낸 옛 노드를 가리키고 있다")
    #expect(diffuseImage(staleMaterial) === staleBefore, "떼어낸 옛 캐릭터의 얼굴을 건드렸다")
}

@MainActor
@Test("격발이 발신자 캐릭터를 실제로 세우고, 원복이 화면과 캐릭터를 함께 되돌린다")
func v0315bUltraTakeoverSwapsAndRestoresThroughTheController() throws {
    let controller = isolatedOverlayController()
    let before = controller.panel.frame
    // ★ 씬을 주입하지 않는다. 격발이 패널을 띄우는 순간 SwiftUI 가 SCNView 를 **실제로 마운트**하고
    //   그 makeNSView 가 engine.attach 를 부른다 — 갈아입기는 그 뒤에 일어나야 붙잡을 씬이 있다.
    //   이 테스트가 확인하는 것의 절반이 바로 그 순서다.
    controller.handleReceivedPokes([
        ReceivedPoke(id: "u1", fromName: "이유성", createdAt: Date(), kind: .ultra, fromCharacterID: "fox")
    ])
    #expect(controller.isUltraActive, "격발이 안 섰다")
    let scene = try #require(controller.engine.attachedScene, "격발이 뷰를 못 세웠다 — 이 검사가 아무것도 못 본다")
    let during = try chain(scene)
    #expect(controller.engine.currentCharacterID == "fox", "찌른 사람 캐릭터로 안 갈아입었다")
    #expect(controller.engine.isSpriteCharacter)

    controller.endUltraTakeover()
    #expect(controller.isUltraActive == false)
    #expect(controller.panel.frame == before, "원복이 프레임을 안 되돌렸다 — 화면을 잃는 사고다")
    #expect(controller.panel.ignoresMouseEvents, "못 박기가 안 풀렸다")
    #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID, "내 캐릭터로 안 돌아왔다")
    // ★ wrapper/facing 은 왕복 내내 **같은 객체**여야 한다 — 뷰를 다시 만들지 않았다는 증거
    //   (울트라는 5초 안에 교체·원복 두 번이고, 뷰 재생성은 그때마다 감은눈 굽기를 메인 스레드에서 다시 돌린다).
    let after = try chain(scene)
    #expect(after.wrapper === during.wrapper && after.facing === during.facing)
    #expect(controller.engine.isSpriteCharacter == false, "스프라이트인 채로 남았다")
    // 격발 리액션이 재-attach 로 되살아나면 안 된다(5초짜리가 작은 패널에서 처음부터 다시 돈다).
    #expect(controller.engine.state == .idle, "원복 뒤에도 격발 리액션이 살아 있다")
    controller.updateWorking(false)
}

@MainActor
@Test("나와 같은 캐릭터·모르는 ID 는 갈아입지 않는다 — 일반 찌르기도 건드리지 않는다")
func v0315bSameCharacterUltraSkipsTheSwap() throws {
    let controller = isolatedOverlayController()
    // 뷰를 먼저 세워 둔다(격발이 마운트하기 전에 '내 캐릭터'를 잡아 두려면 한 번 띄워야 한다).
    controller.handleReceivedPokes([
        ReceivedPoke(id: "warm", fromName: "이유성", createdAt: Date(), kind: .ultra)
    ])
    let scene = try #require(controller.engine.attachedScene)
    controller.endUltraTakeover()
    let parts = try chain(scene)

    // 발신자도 아잉 = 내 캐릭터와 같다 → 노드를 건드리지 않는다(교체 비용 0).
    controller.handleReceivedPokes([
        ReceivedPoke(id: "u1", fromName: "이유성", createdAt: Date(), kind: .ultra,
                     fromCharacterID: CharacterCatalog.builtInAingID)
    ])
    #expect(controller.isUltraActive)
    #expect(try chain(scene).character === parts.character, "같은 캐릭터인데 노드를 갈아 끼웠다")
    controller.endUltraTakeover()

    // 모르는 ID 도 마찬가지다(구버전·아직 모르는 새 캐릭터). throw 하지 않고 내 캐릭터 그대로.
    controller.handleReceivedPokes([
        ReceivedPoke(id: "u2", fromName: "이유성", createdAt: Date(), kind: .ultra,
                     fromCharacterID: "character-from-the-future")
    ])
    #expect(controller.isUltraActive)
    #expect(try chain(scene).character === parts.character)
    #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID)
    controller.endUltraTakeover()

    // **일반 찌르기는 건드리지 않는다** — 캐릭터 ID 가 실려 와도 내 캐릭터가 폴짝 뛰는 그대로다.
    controller.handleReceivedPokes([
        ReceivedPoke(id: "n1", fromName: "이유성", createdAt: Date(), kind: .normal, fromCharacterID: "fox")
    ])
    #expect(controller.isUltraActive == false)
    #expect(try chain(scene).character === parts.character, "일반 찌르기가 캐릭터를 갈아 끼웠다")
    #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID)
    controller.updateWorking(false)
}
