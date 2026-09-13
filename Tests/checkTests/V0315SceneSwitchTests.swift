import AppKit
import CoreGraphics
import SceneKit
import Testing
@testable import check

// MARK: - v0.3.15 2-A: 씬 분기(아잉 3D ↔ 스프라이트 평면) · 노드 교체 · 스프라이트 런타임
//
// 이 파일이 지키는 것 셋.
//
// ① **아잉 경로는 한 톨도 안 바뀐다.** `makeScene()` 무인자가 종전과 같은 씬을 낸다(wrapper → facing →
//    캐릭터 + 감은눈 노드 2 + 카메라). V0238CharacterTests·CheckSleepEyesTests·CheckOverlayTests 가
//    같은 것을 다른 각도에서 물고 있고, 여기서는 "기본값이 아잉이다"를 직접 못 박는다.
// ② **스프라이트 씬은 3D 전용 장치를 안 태운다.** 감은눈 노드가 없고, 아틀라스가 512 로 리샘플되지 않는다.
//    그런데도 `modelExtent`(리액션 진폭)와 카메라 구도는 아잉과 사실상 같은 숫자여야 한다 —
//    그게 `SpriteCharacterNode.targetExtent = 1.9210` 이 존재하는 이유 전부다.
// ③ **교체는 뷰가 아니라 노드다.** wrapper/facing 은 살아남고 그 자식만 바뀐다. 울트라 격발이 5초 안에
//    교체·원복 두 번을 하므로, 여기서 뷰가 재생성되면 감은눈 텍스처(연결성분 라벨링)가 메인 스레드에서
//    두 번 다시 만들어진다(`CheckOverlayCharacterView.characterBoxSize` 주석).

// MARK: - 헬퍼

/// 재질 디퓨즈가 CGImage 면 그것. CF 불투명 타입은 `as?` 가 늘 성공하므로 CFGetTypeID 로 판별한다.
private func v0315DiffuseImage(_ material: SCNMaterial) -> CGImage? {
    guard let contents = material.diffuse.contents,
          CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return nil }
    return (contents as! CGImage)
}

/// 번들에 실린 스프라이트 캐릭터 하나(매니페스트 + 아틀라스 이미지).
@MainActor
private func v0315Sprite(_ id: String = "fox") throws -> (manifest: CharacterManifest, atlas: CGImage) {
    let catalog = CharacterCatalog.load(bundle: CheckResources.bundle)
    let manifest = try #require(catalog.manifest(id: id), "번들에서 \(id) 를 못 찾았다")
    let url = try #require(catalog.atlasURL(for: id))
    let atlas = try #require(SpriteRuntime.decodeImage(at: url))
    return (manifest, atlas)
}

/// 씬 루트 → wrapper → facing → 그 아래 캐릭터 자식. 구조가 깨지면 여기서 먼저 터진다.
@MainActor
private func v0315Chain(_ scene: SCNScene) throws -> (wrapper: SCNNode, facing: SCNNode, character: SCNNode) {
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false),
        "reactionWrapper 가 없다"
    )
    let facing = try #require(
        wrapper.childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false),
        "facingWrapper 가 없다"
    )
    let character = try #require(facing.childNodes.first, "facing 아래에 캐릭터가 없다")
    return (wrapper, facing, character)
}

/// `ReactionEngine.attach` 가 뽑는 `modelExtent` 와 **같은 식**. 엔진의 그 프로퍼티는 private 이라
/// 값을 직접 못 읽는다 — 식을 복제하지 않고 엔진에서 되읽는 길은 `v0315EngineModelExtent` 에 있다.
private func v0315Extent(_ node: SCNNode) -> CGFloat {
    let (minB, maxB) = node.boundingBox
    return CGFloat(max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z)))
}

/// **엔진이 실제로 들고 있는** `modelExtent` 를 되읽는다.
///
/// 왜 이렇게까지 하나: bbox 식을 테스트에 복제하면 그 테스트는 엔진이 아니라 자기 자신을 검사한다
/// (기준선이 같은 입력이면 영원히 초록이다). 마일스톤 색종이 방출구는 `y = extent * 0.5` 에 **동기로**
/// 놓이므로, `request(.milestone)` 뒤 그 y 를 0.5 로 나누면 엔진 안의 값이 그대로 나온다.
/// (💤 는 `Task` 안에서 스폰돼 같은 턴에 안 보인다 — 실측으로 갈아탔다.)
@MainActor
private func v0315EngineModelExtent(scene: SCNScene) throws -> CGFloat {
    let engine = ReactionEngine()
    let chain = try v0315Chain(scene)
    engine.attach(node: chain.wrapper, sceneRoot: scene.rootNode, view: nil)
    #expect(engine.request(.milestone), "마일스톤이 거절됐다 — 이 프로브가 아무것도 못 잰다")
    let confetti = try #require(
        scene.rootNode.childNodes.first { $0.name == "check.reaction.confetti" },
        "색종이 방출구가 없다 — 프로브가 읽을 자리가 사라졌다"
    )
    return CGFloat(confetti.position.y) / 0.5
}

/// 씬의 카메라 노드와, 그 카메라에서 캐릭터 중심까지의 거리.
@MainActor
private func v0315Camera(_ scene: SCNScene) throws -> (node: SCNNode, distanceToOrigin: CGFloat) {
    let camera = try #require(scene.rootNode.childNodes.first { $0.camera != nil }, "카메라가 없다")
    let p = camera.position
    let d = sqrt(CGFloat(p.x * p.x + p.y * p.y + p.z * p.z))
    return (camera, d)
}

/// PNG 데이터의 알파 커버리지(%) 와 불투명 픽셀의 경계 상자(정규화, 좌하단 원점).
private func v0315AlphaStats(_ png: Data) -> (coverage: Double, box: CGRect?, size: CGSize)? {
    guard let rep = NSBitmapImageRep(data: png), let cg = rep.cgImage else { return nil }
    let w = cg.width, h = cg.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let base = ctx.data else { return nil }
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var opaque = 0
    for row in 0..<h {
        let offset = row * ctx.bytesPerRow
        for x in 0..<w where bytes[offset + x * 4 + 3] > 24 { opaque += 1 }
    }
    return (Double(opaque) / Double(w * h) * 100, MiniGameMascot.alphaBox(cg),
            CGSize(width: w, height: h))
}

/// 어두운 잉크(눈·입)의 가로 무게중심. 0.5 보다 크면 오른쪽으로 쏠렸다 = 오른쪽을 본다.
private func v0315InkCentroidX(_ image: NSImage) -> Double? {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let w = cg.width, h = cg.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let base = ctx.data else { return nil }
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var sum = 0.0, count = 0.0
    for row in 0..<h {
        let offset = row * ctx.bytesPerRow
        for x in 0..<w {
            let a = Int(bytes[offset + x * 4 + 3])
            guard a > 200 else { continue }
            let r = Int(bytes[offset + x * 4]), g = Int(bytes[offset + x * 4 + 1]), b = Int(bytes[offset + x * 4 + 2])
            guard (r * 299 + g * 587 + b * 114) / 1000 < 90 else { continue }
            sum += Double(x); count += 1
        }
    }
    guard count > 0 else { return nil }
    return sum / count / Double(w)
}

// MARK: - ① 아잉 기본값이 그대로다

@MainActor
@Test("makeScene() 무인자는 종전과 같은 아잉 씬이다")
func v0315DefaultSceneIsStillAing() throws {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let chain = try v0315Chain(scene)
    // 3D 전용 장치가 전부 제자리에 있다.
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true) != nil)
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeRightName, recursively: true) != nil)
    // 스프라이트 평면이 아니다.
    #expect(chain.character.name != SpriteCharacterNode.nodeName)
    _ = try v0315Camera(scene)
}

@MainActor
@Test("캐릭터 인자로 아잉을 넘겨도 무인자와 같은 씬이다")
func v0315ExplicitAingMatchesDefault() throws {
    let implicit = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let explicit = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: CharacterCatalog.builtInAing)
    )
    #expect(v0315Extent(try v0315Chain(implicit).wrapper) == v0315Extent(try v0315Chain(explicit).wrapper))
    #expect(try v0315Camera(implicit).node.position.z == (try v0315Camera(explicit).node.position.z))
}

// MARK: - ② 스프라이트 씬

@MainActor
@Test("스프라이트 씬은 같은 골격을 세우되 3D 감은눈 노드를 안 만든다")
func v0315SpriteSceneSkipsClosedEyes() throws {
    let fox = try v0315Sprite()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fox.manifest, atlas: fox.atlas)
    )
    let chain = try v0315Chain(scene)
    #expect(chain.character.name == SpriteCharacterNode.nodeName, "스프라이트 평면이 아니다")
    // ★ 3D 전용 파이프라인을 안 탄다(DECISIONS: 깜빡임·졸기는 프레임으로).
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true) == nil)
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeRightName, recursively: true) == nil)
    // 배경은 비어 있어야 패널 뒤가 비친다.
    #expect(scene.background.contents == nil)
    _ = try v0315Camera(scene)
}

@MainActor
@Test("아틀라스를 512 로 리샘플하지 않는다 — 매니페스트 픽셀 그대로다")
func v0315SpriteAtlasIsNotDownscaled() throws {
    let fox = try v0315Sprite()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fox.manifest, atlas: fox.atlas)
    )
    let chain = try v0315Chain(scene)
    let contents = try #require(chain.character.geometry?.firstMaterial?.diffuse.contents)
    #expect(CFGetTypeID(contents as CFTypeRef) == CGImage.typeID, "디퓨즈가 CGImage 가 아니다")
    let cg = contents as! CGImage
    let spec = try #require(fox.manifest.atlas)
    // `applyUnlitMaterials` 를 태웠다면 908×174 가 512×98 로 줄어 여기서 갈린다.
    #expect(cg.width == spec.width && cg.height == spec.height,
            "아틀라스가 \(cg.width)x\(cg.height) 로 바뀌었다 — 매니페스트는 \(spec.width)x\(spec.height)")
}

@MainActor
@Test("아틀라스가 없으면 아잉으로 접는다 — 빈 오버레이를 남기지 않는다")
func v0315SpriteWithoutAtlasFallsBackToAing() throws {
    let fox = try v0315Sprite()
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false, character: fox.manifest, atlas: nil))
    let chain = try v0315Chain(scene)
    #expect(chain.character.name != SpriteCharacterNode.nodeName, "아틀라스 없이 스프라이트를 세웠다")
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true) != nil,
            "아잉 폴백인데 감은눈 노드가 없다")
}

// MARK: - ② modelExtent · 카메라 구도 실측

@MainActor
@Test("스프라이트의 modelExtent 가 아잉과 같은 1.9210 근처다 — 리액션 진폭이 여기서 나온다")
func v0315ModelExtentMatchesAing() throws {
    let fox = try v0315Sprite()
    let aingScene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let foxScene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fox.manifest, atlas: fox.atlas)
    )
    let aingExtent = try v0315EngineModelExtent(scene: aingScene)
    let foxExtent = try v0315EngineModelExtent(scene: foxScene)
    let aingCam = try v0315Camera(aingScene), foxCam = try v0315Camera(foxScene)
    let aingBox = aingScene.rootNode.boundingBox, foxBox = foxScene.rootNode.boundingBox

    print(String(format: "[v0315] modelExtent  아잉 %.4f · 여우 %.4f (targetExtent %.4f)",
                 aingExtent, foxExtent, SpriteCharacterNode.targetExtent))
    print(String(format: "[v0315] 씬루트 bbox  아잉 dx %.4f dy %.4f dz %.4f · 여우 dx %.4f dy %.4f dz %.4f",
                 aingBox.max.x - aingBox.min.x, aingBox.max.y - aingBox.min.y, aingBox.max.z - aingBox.min.z,
                 foxBox.max.x - foxBox.min.x, foxBox.max.y - foxBox.min.y, foxBox.max.z - foxBox.min.z))
    print(String(format: "[v0315] 카메라 위치   아잉 (%.4f, %.4f, %.4f) · 여우 (%.4f, %.4f, %.4f)",
                 aingCam.node.position.x, aingCam.node.position.y, aingCam.node.position.z,
                 foxCam.node.position.x, foxCam.node.position.y, foxCam.node.position.z))
    // ★ 카메라가 **원점**에서 얼마나 떨어졌는지는 비교 대상이 아니다. `addFramingCamera` 는
    //   `z = maxB.z + distance` 로 **bbox 앞면에서 일정 거리**에 카메라를 세운다. 아잉은 두께(dz 1.46)가
    //   있어 앞면이 앞으로 나와 있고 평면은 dz=0 이라, 원점 기준으로는 15% 가 갈리지만 **캐릭터 앞면까지의
    //   거리는 같다**. 화면에 그려지는 크기가 그 거리로 정해지므로, 재야 할 값은 이쪽이다
    //   (렌더 실루엣 비 0.99 가 그 증거다 — v0315SpriteSceneActuallyRenders).
    let aingFront = CGFloat(aingCam.node.position.z - aingBox.max.z)
    let foxFront = CGFloat(foxCam.node.position.z - foxBox.max.z)
    print(String(format: "[v0315] 원점까지 거리  아잉 %.4f · 여우 %.4f (%.1f%%)",
                 aingCam.distanceToOrigin, foxCam.distanceToOrigin,
                 (foxCam.distanceToOrigin / aingCam.distanceToOrigin - 1) * 100))
    print(String(format: "[v0315] bbox 앞면까지  아잉 %.4f · 여우 %.4f (%.2f%%)",
                 aingFront, foxFront, (foxFront / aingFront - 1) * 100))

    // ★ 리액션 진폭(hop·tilt·파티클 위치)이 전부 이 값의 배수다. 1% 를 넘게 갈리면 스프라이트만
    //   다른 크기로 폴짝인다.
    #expect(abs(foxExtent - SpriteCharacterNode.targetExtent) < 0.01,
            "여우 modelExtent \(foxExtent) 가 targetExtent \(SpriteCharacterNode.targetExtent) 와 다르다")
    #expect(abs(foxExtent - aingExtent) / aingExtent < 0.01,
            "여우 \(foxExtent) vs 아잉 \(aingExtent) — 리액션 진폭이 갈린다")
    // 캐릭터 앞면까지의 거리는 **1% 안**이어야 한다. 여기가 갈리면 같은 자리에서 캐릭터 크기가 튄다.
    #expect(abs(foxFront / aingFront - 1) < 0.01,
            "앞면까지 거리가 아잉 \(aingFront) vs 여우 \(foxFront) 로 갈렸다")
    // 카메라 높이(내려다보는 각)도 같은 extent 에서 나오므로 사실상 같아야 한다.
    #expect(abs(CGFloat(foxCam.node.position.y - aingCam.node.position.y)) < 0.02,
            "카메라 높이가 갈렸다 — 내려다보는 각이 달라진다")
}

// MARK: - ② attach 가 스프라이트에서 안전한가(크래시·예외 금지)

@MainActor
@Test("스프라이트 씬에 attach·졸기·깨기를 태워도 크래시하지 않고 아틀라스가 바뀌지 않는다")
func v0315AttachIsSafeOnSprites() throws {
    let fox = try v0315Sprite()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fox.manifest, atlas: fox.atlas)
    )
    let chain = try v0315Chain(scene)
    let material = try #require(chain.character.geometry?.firstMaterial)
    let before = try #require(v0315DiffuseImage(material), "디퓨즈가 CGImage 가 아니다")

    let engine = ReactionEngine()
    let started = CFAbsoluteTimeGetCurrent()
    engine.attach(node: chain.wrapper, sceneRoot: scene.rootNode, view: nil)
    let attachMs = (CFAbsoluteTimeGetCurrent() - started) * 1_000

    // 리액션 11종을 전부 태운다 — 어느 하나가 스프라이트에서 터지면 여기서 잡힌다.
    let kinds: [ReactionKind] = [
        .hit, .commuteStart, .commuteEnd, .milestone, .greeting(name: "테스트"),
        .poked(bubbleText: "콕"), .ultraPoked(bubbleText: "울트라"), .goalAchieved,
        .ultraCharged, .drowsy, .wake
    ]
    for kind in kinds { _ = engine.request(kind) }

    // ⚠️ 이 테스트가 무는 것은 **"터지지 않는다"뿐**이다. 아틀라스가 그대로인지는 여기서 묻지 마라 —
    //    앞선 리액션이 상태를 물고 있으면 `.drowsy` 가 **거절**돼 감은눈 경로에 아예 안 들어가고,
    //    그러면 "안 바뀌었다"가 초록으로 나온다(아무것도 안 본 초록). 그 검사는 졸기를 단독으로 태우는
    //    `v0315DrowsyAloneDoesNotTouchTheAtlas` 에 있다.
    let after = v0315DiffuseImage(material)
    let msText = String(format: "%.1f", attachMs)
    print("[v0315] sprite attach \(msText)ms · 리액션 11종 통과 · 디퓨즈 여전히 CGImage \(after != nil)")
    #expect(after != nil, "리액션을 태우고 나니 디퓨즈가 CGImage 가 아니다")
    #expect(chain.character.parent === chain.facing, "리액션이 캐릭터를 씬에서 떼어냈다")
    _ = before
}

/// ☠︎ **닫힌 결함(2-B, v0.3.15).** 표식을 걷어낸 자리다 — 아래 두 줄이 이제 그냥 초록이어야 한다.
///
/// 있었던 일: `ReactionEngine.locateSleepEyeTargets` 는 얼굴 재질을 **"큰 CGImage 디퓨즈(width ≥ 256)"** 로
/// 찾는데, 스프라이트 아틀라스(여우 908×174 · 로봇 640×192)가 그 조건을 **그대로 만족**해 얼굴로 오인됐다.
/// 졸기 진입의 `applyClosedEyes` 가 아틀라스를 감은눈 버전으로 갈아 끼웠고(실측: 대입 1회, 객체가 바뀐다),
/// 화면에서는 걷는 여우 몸통에 "눈으로 분류된" 자리가 피부색 얼룩으로 번졌다. 덤으로 `makeClosedEyesImage` 가
/// 아틀라스 전체를 **메인 스레드에서** 훑었다(같은 머신 실측 ~2.65초, 디버그 빌드).
///
/// 고친 방법: `attach` 가 **캐릭터 종류로** 분기해 스프라이트에는 감은눈 파이프라인을 아예 태우지 않는다.
/// 크기 임계값을 조이는 길은 택하지 않았다 — 아틀라스 크기는 캐릭터마다 다르므로 어떤 임계값도 다음
/// 캐릭터에서 다시 뚫린다. 졸기는 스프라이트에서 기울기(drowsySink)만 남는다(DECISIONS: 전용 프레임 없음).
@MainActor
@Test("☠︎ 졸기가 스프라이트 아틀라스를 갈아 끼우지 않는다(2-B 가 닫았다)")
func v0315DrowsyAloneDoesNotTouchTheAtlas() throws {
    let fox = try v0315Sprite()
    let scene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fox.manifest, atlas: fox.atlas)
    )
    let chain = try v0315Chain(scene)
    let material = try #require(chain.character.geometry?.firstMaterial)
    let before = try #require(v0315DiffuseImage(material))

    let engine = ReactionEngine()
    engine.attach(node: chain.wrapper, sceneRoot: scene.rootNode, view: nil)
    // ★ 갓 attach 한 idle 상태에서 **졸기만** 요청한다. 앞선 리액션이 물고 있으면 request 가 거절돼
    //   이 검사가 아무것도 안 보게 된다(초록인 채로 통과하는 그 자리 — 실제로 한 번 당했다).
    #expect(engine.request(.drowsy), "졸기가 거절됐다 — 이 검사가 아무것도 못 본다")
    #expect(engine.state == .sleeping)
    let after = try #require(v0315DiffuseImage(material))
    let assignments = engine.faceDiffuseCGImageAssignments + engine.faceDiffuseTextureAssignments
    print("[v0315] ☠︎ 졸기 단독 — 얼굴 디퓨즈 대입 \(assignments)회 · 아틀라스 동일 \(after === before)")
    #expect(after === before,
            "졸기가 스프라이트 아틀라스를 감은눈 버전으로 갈아 끼웠다 — 몸에 피부색 얼룩이 생긴다")
    #expect(assignments == 0)
}

/// ⚠️ **교차 갈래 계측** — `ReactionEngine.locateSleepEyeTargets` 는 얼굴 재질을 "큰 CGImage 디퓨즈
/// (width ≥ 256)"로 찾는다. 스프라이트 아틀라스(여우 908×174 · 로봇 640×192)가 그 조건을 **그대로 만족**하므로
/// 스프라이트 씬에서도 얼굴로 오인되고, 그 뒤 `makeClosedEyesImage`(연결성분 라벨링 + 인페인트)가
/// **메인 스레드에서** 아틀라스 전체를 훑는다. 결과가 화면을 망치지는 않는 것으로 실측됐지만(디퓨즈 대입 0회),
/// **비용은 실제로 든다**. 그 비용을 숫자로 남겨 2-B/오케스트레이터가 `attach` 에 kind 분기를 넣을지 판단하게 한다.
/// 이 파일은 `CheckOverlayReactions.swift` 를 소유하지 않으므로 여기서 고치지 않는다.
@MainActor
@Test("스프라이트 attach 비용을 숫자로 남긴다 — 아틀라스가 얼굴로 오인되는 값을 잰다")
func v0315SpriteAttachCostProbe() throws {
    let fox = try v0315Sprite()
    let foxScene = try #require(
        CheckCharacter3DScene.makeScene(animated: false, character: fox.manifest, atlas: fox.atlas)
    )
    let aingScene = try #require(CheckCharacter3DScene.makeScene(animated: false))

    func attachMs(_ scene: SCNScene, engine: ReactionEngine) throws -> Double {
        let chain = try v0315Chain(scene)
        let t = CFAbsoluteTimeGetCurrent()
        engine.attach(node: chain.wrapper, sceneRoot: scene.rootNode, view: nil)
        return (CFAbsoluteTimeGetCurrent() - t) * 1_000
    }

    // 워밍업(첫 SceneKit/CoreGraphics 접촉 비용을 이 줄이 먹는다).
    _ = try attachMs(aingScene, engine: ReactionEngine())

    let aingEngine = ReactionEngine(), foxEngine = ReactionEngine()
    let aingFirst = try attachMs(aingScene, engine: aingEngine)
    let foxFirst = try attachMs(foxScene, engine: foxEngine)
    // 같은 sceneRoot 로의 재-attach 는 캐시를 재사용한다(그 가드가 실제로 먹는지도 여기서 보인다).
    let foxSecond = try attachMs(foxScene, engine: foxEngine)

    // 오인의 직접 증거 — 아틀라스를 "얼굴"로 넣었을 때의 감은눈 텍스처 생성 비용.
    let planeGeometry = try v0315Chain(foxScene).character.geometry
    let bakeStart = CFAbsoluteTimeGetCurrent()
    let baked = CheckCharacter3DScene.makeClosedEyesImage(faceImage: fox.atlas, geometry: planeGeometry)
    let bakeMs = (CFAbsoluteTimeGetCurrent() - bakeStart) * 1_000

    print(String(format: "[v0315] attach ms — 아잉 %.1f · 여우 %.1f · 여우 재-attach %.1f", aingFirst, foxFirst, foxSecond))
    print(String(format: "[v0315] 아틀라스를 얼굴로 오인했을 때의 감은눈 굽기 %.1fms · 결과 %@",
                 bakeMs, baked == nil ? "nil" : "이미지"))
    // 재-attach 가드는 반드시 먹어야 한다(울트라가 5초 안에 attach 를 두 번 부른다).
    #expect(foxSecond < max(foxFirst, 1) , "같은 씬 재-attach 가 캐시를 못 쓴다")
}

// MARK: - ③ swapCharacter 왕복

@MainActor
@Test("아잉 → 여우 → 아잉 왕복에도 wrapper/facing 노드가 그대로다")
func v0315SwapRoundTripKeepsTheChain() throws {
    let fox = try v0315Sprite()
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let start = try v0315Chain(scene)
    // ★ **객체 아이덴티티**를 잡아 둔다. 이름만 비교하면 "새로 만든 같은 이름 노드"도 통과한다
    //   (그건 곧 뷰 재생성과 같은 비용이다).
    let wrapperID = ObjectIdentifier(start.wrapper), facingID = ObjectIdentifier(start.facing)
    let cameraCount = scene.rootNode.childNodes.filter { $0.camera != nil }.count

    #expect(CheckCharacter3DScene.swapCharacter(in: scene, to: fox.manifest, atlas: fox.atlas, animated: false))
    let mid = try v0315Chain(scene)
    #expect(ObjectIdentifier(mid.wrapper) == wrapperID, "wrapper 가 새로 만들어졌다")
    #expect(ObjectIdentifier(mid.facing) == facingID, "facing 이 새로 만들어졌다")
    #expect(mid.character.name == SpriteCharacterNode.nodeName)
    #expect(mid.facing.childNodes.count == 1, "facing 아래에 옛 캐릭터가 남았다(\(mid.facing.childNodes.count)개)")
    // 감은눈 노드는 아잉 캐릭터에 붙어 있었으므로 함께 사라져야 한다.
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true) == nil)

    #expect(CheckCharacter3DScene.swapCharacter(
        in: scene, to: CharacterCatalog.builtInAing, atlas: nil, animated: false
    ))
    let back = try v0315Chain(scene)
    #expect(ObjectIdentifier(back.wrapper) == wrapperID)
    #expect(ObjectIdentifier(back.facing) == facingID)
    #expect(back.character.name != SpriteCharacterNode.nodeName, "아잉으로 안 돌아왔다")
    #expect(back.facing.childNodes.count == 1)
    // 아잉으로 돌아오면 감은눈 노드가 다시 있어야 한다(졸기가 되살아나야 하므로).
    #expect(scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true) != nil,
            "아잉 복귀인데 감은눈 노드가 없다 — 졸기가 조용히 사라진다")
    #expect(scene.rootNode.childNodes.filter { $0.camera != nil }.count == cameraCount,
            "왕복이 카메라를 늘리거나 줄였다")
}

@MainActor
@Test("왕복 뒤에도 modelExtent 가 원래 값으로 돌아온다")
func v0315SwapRoundTripRestoresExtent() throws {
    let fox = try v0315Sprite()
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let chain = try v0315Chain(scene)
    let before = v0315Extent(chain.wrapper)
    #expect(CheckCharacter3DScene.swapCharacter(in: scene, to: fox.manifest, atlas: fox.atlas, animated: false))
    let during = v0315Extent(chain.wrapper)
    #expect(CheckCharacter3DScene.swapCharacter(
        in: scene, to: CharacterCatalog.builtInAing, atlas: nil, animated: false
    ))
    let after = v0315Extent(chain.wrapper)
    print(String(format: "[v0315] wrapper extent 아잉 %.4f → 여우 %.4f → 아잉 %.4f", before, during, after))
    #expect(abs(after - before) < 0.0001, "왕복이 크기를 바꿨다")
}

@MainActor
@Test("교체에 실패하면 씬을 건드리지 않는다 — 빈 facing 을 남기지 않는다")
func v0315FailedSwapLeavesTheSceneIntact() throws {
    let fox = try v0315Sprite()
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let chain = try v0315Chain(scene)
    let characterID = ObjectIdentifier(chain.character)
    // 스프라이트인데 아틀라스가 없다 = 만들 수 없다.
    #expect(CheckCharacter3DScene.swapCharacter(in: scene, to: fox.manifest, atlas: nil) == false)
    let after = try v0315Chain(scene)
    #expect(ObjectIdentifier(after.character) == characterID, "실패한 교체가 캐릭터를 지웠다")

    // wrapper/facing 이 없는 씬(makeScene 이 만든 것이 아닌 씬)에서도 false 다.
    let bare = SCNScene()
    #expect(CheckCharacter3DScene.swapCharacter(in: bare, to: fox.manifest, atlas: fox.atlas) == false)
}

@MainActor
@Test("교체 뒤 다시 attach 해도 안전하다 — 울트라 격발이 이 경로다")
func v0315ReattachAfterSwap() throws {
    let fox = try v0315Sprite()
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let chain = try v0315Chain(scene)
    let engine = ReactionEngine()
    engine.attach(node: chain.wrapper, sceneRoot: scene.rootNode, view: nil)
    engine.setDragFacing(-1)

    #expect(CheckCharacter3DScene.swapCharacter(in: scene, to: fox.manifest, atlas: fox.atlas, animated: false))
    engine.attach(node: chain.wrapper, sceneRoot: scene.rootNode, view: nil)
    // ☠︎ 재-attach 가 보관 중인 방향을 다시 적용해야 한다(안 그러면 값-노드가 갈려 영구 고착).
    #expect(engine.currentDragFacing == -1)

    #expect(CheckCharacter3DScene.swapCharacter(
        in: scene, to: CharacterCatalog.builtInAing, atlas: nil, animated: false
    ))
    engine.attach(node: chain.wrapper, sceneRoot: scene.rootNode, view: nil)
    #expect(engine.currentDragFacing == -1)
    // 원복 뒤 졸기가 다시 살아난다(감은눈 선 노드가 토글된다).
    let left = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.closedEyeLeftName, recursively: true)
    )
    #expect(left.isHidden)
    #expect(engine.request(.drowsy))
    #expect(!left.isHidden, "아잉으로 돌아왔는데 감은눈 선이 안 켜진다")
}

// MARK: - SpriteRuntime 계약

@MainActor
@Test("같은 (상태, 미러) 재호출은 프레임을 0 으로 되돌리지 않는다")
func v0315RuntimeSetStateIsIdempotent() throws {
    let fox = try v0315Sprite()
    let runtime = try #require(SpriteRuntime(manifest: fox.manifest, atlas: fox.atlas))
    runtime.setState(CharacterManifest.StateKey.sideWalk, mirrored: false, now: 0)
    #expect(runtime.stateKey == CharacterManifest.StateKey.sideWalk)
    // 140ms × 4프레임 — 0.3초면 2번 프레임.
    #expect(runtime.tick(now: 0.30))
    let advanced = runtime.frameIndex
    #expect(advanced == 2, "프레임이 \(advanced) 다 — 140ms 씩이면 0.30초는 2번")
    // ★ 드래그 중 setDragFacing 은 매 이벤트마다 같은 방향을 다시 준다. 여기서 리셋되면 걷기가 얼어붙는다.
    runtime.setState(CharacterManifest.StateKey.sideWalk, mirrored: false, now: 0.30)
    #expect(runtime.frameIndex == advanced, "같은 상태 재요청이 프레임을 되돌렸다")
    // 미러가 바뀌면 전환이다.
    runtime.setState(CharacterManifest.StateKey.sideWalk, mirrored: true, now: 0.30)
    #expect(runtime.mirrored)
    #expect(runtime.frameIndex == 0)
}

@MainActor
@Test("tick 은 프레임이 바뀐 틱에만 true 다")
func v0315RuntimeTickReportsChangeOnly() throws {
    let fox = try v0315Sprite()
    let runtime = try #require(SpriteRuntime(manifest: fox.manifest, atlas: fox.atlas))
    runtime.setState(CharacterManifest.StateKey.sideWalk, mirrored: false, now: 0)
    #expect(runtime.tick(now: 0.05) == false, "같은 프레임인데 true 를 냈다 — 매 틱 재질을 건드리게 된다")
    #expect(runtime.tick(now: 0.15), "140ms 를 넘겼는데 프레임이 안 바뀌었다")
    #expect(runtime.tick(now: 0.16) == false)
}

@MainActor
@Test("없는 상태는 frontIdle 로 접힌다 — 폴백은 런타임 한 곳에서만")
func v0315RuntimeFoldsMissingStates() throws {
    let spec = CharacterManifest.Atlas(
        file: "atlas.png", width: 64, height: 32,
        states: [CharacterManifest.StateKey.frontIdle: .init(
            frames: [.init(x: 0, y: 0, w: 32, h: 32)], durationsMs: [100], loop: true
        )]
    )
    let manifest = CharacterManifest(
        id: "frontonly", displayName: "정면만", kind: .sprite, atlas: spec,
        portrait: .init(neutral: "n.png", negative: "g.png")
    )
    // 32×32 이상이면 마스크가 구워진다 — 알파 없는 단색으로 만든다.
    let atlas = try #require(v0315SolidImage(width: 64, height: 32))
    let runtime = try #require(SpriteRuntime(manifest: manifest, atlas: atlas))
    #expect(runtime.hasState(CharacterManifest.StateKey.sideIdle) == false)
    runtime.setState(CharacterManifest.StateKey.sideWalk, mirrored: false, now: 0)
    #expect(runtime.stateKey == CharacterManifest.StateKey.frontIdle, "폴백이 안 걸렸다")
    #expect(runtime.currentFrame.w == 32)
}

@MainActor
@Test("isOpaque 는 atlasUV 를 거쳐 현재 프레임의 알파를 본다")
func v0315RuntimeAlphaGoesThroughAtlasUV() throws {
    let fox = try v0315Sprite()
    let runtime = try #require(SpriteRuntime(manifest: fox.manifest, atlas: fox.atlas))
    // 평면 한복판(몸통)은 불투명, 좌상단 모서리는 투명이어야 한다.
    #expect(runtime.isOpaque(planeUV: CGPoint(x: 0.5, y: 0.5)))
    #expect(runtime.isOpaque(planeUV: CGPoint(x: 0.01, y: 0.01)) == false)

    // ★ `atlasUV` 를 건너뛰고 마스크에 평면 UV 를 그대로 먹이면 **아틀라스 전체** 기준이라
    //   다른 프레임(여우는 가로로 4셀)의 알파를 본다. 그 차이를 여기서 잰다.
    runtime.setState(CharacterManifest.StateKey.sideIdle, mirrored: false, now: 0)
    var differing = 0, total = 0
    for i in 0..<40 {
        for j in 0..<20 {
            let uv = CGPoint(x: (Double(i) + 0.5) / 40, y: (Double(j) + 0.5) / 20)
            total += 1
            if runtime.isOpaque(planeUV: uv) != runtime.mask.isOpaque(u: uv.x, v: uv.y) { differing += 1 }
        }
    }
    print("[v0315] atlasUV 경유 vs 직접 조회 불일치 \(differing)/\(total)")
    #expect(differing > total / 10,
            "두 경로가 거의 같다 — 이 테스트가 atlasUV 를 실제로 못 보고 있다")
}

@MainActor
@Test("매니페스트와 아틀라스 픽셀이 다르면 런타임을 안 만든다")
func v0315RuntimeRejectsMismatchedAtlas() throws {
    let fox = try v0315Sprite()
    let wrong = try #require(v0315SolidImage(width: 64, height: 32))
    #expect(SpriteRuntime(manifest: fox.manifest, atlas: wrong) == nil)
    #expect(SpriteRuntime(manifest: CharacterCatalog.builtInAing, atlas: fox.atlas) == nil,
            "3D 캐릭터로 스프라이트 런타임을 만들었다")
}

/// 알파가 전부 1인 단색 이미지(마스크 굽기가 성공하는 최소 픽스처).
private func v0315SolidImage(width: Int, height: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
}

// MARK: - MiniGameMascot.sideProfile

@MainActor
@Test("스프라이트 캐릭터의 옆모습은 아틀라스 프레임에서 온다 — 3D 굽기를 안 탄다")
func v0315SideProfileUsesTheAtlas() throws {
    MiniGameMascot.resetCacheForTesting()
    let fox = try v0315Sprite()
    let image = try #require(MiniGameMascot.sideProfile(character: fox.manifest),
                             "여우 옆모습을 못 만들었다")
    // 3D 굽기를 탔다면 lastBakeSource 가 채워진다.
    #expect(MiniGameMascot.lastBakeSource == nil, "스프라이트인데 3D 모델을 구웠다")
    #expect(image.size.width == MiniGameMascot.spritePixels)
    #expect(image.size.height == MiniGameMascot.spritePixels)

    // 실루엣이 `targetFill` 만큼 차지해야 한다 — 그 비율이 곧 "그리는 몸 vs 죽는 몸"의 어긋남이다.
    let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let box = try #require(MiniGameMascot.alphaBox(cg))
    let fill = max(box.width, box.height)
    let centroid = v0315InkCentroidX(image)
    print(String(format: "[v0315] fox sideProfile fill %.3f (목표 %.2f) · 중심 (%.3f, %.3f) · ink centroid %@",
                 fill, MiniGameMascot.targetFill, box.midX, box.midY,
                 centroid.map { String(format: "%.3f", $0) } ?? "-"))
    #expect(abs(fill - MiniGameMascot.targetFill) < 0.02, "실루엣 채움이 \(fill) 다")
    #expect(abs(box.midX - 0.5) < 0.02 && abs(box.midY - 0.5) < 0.02, "실루엣이 가운데가 아니다")
}

@MainActor
@Test("게임오버(.negative)는 스프라이트에서도 nil 이다 — 기존 계약")
func v0315SideProfileNegativeStaysNil() throws {
    MiniGameMascot.resetCacheForTesting()
    let fox = try v0315Sprite()
    #expect(MiniGameMascot.sideProfile(mood: .negative, character: fox.manifest) == nil)
    #expect(MiniGameMascot.sideProfile(mood: .negative) == nil)
}

@MainActor
@Test("캐시가 캐릭터별로 갈린다 — 캐릭터를 바꿔도 옛 그림이 안 나온다")
func v0315SideProfileCacheIsPerCharacter() throws {
    MiniGameMascot.resetCacheForTesting()
    let fox = try v0315Sprite("fox")
    let bot = try v0315Sprite("bot")
    let foxImage = try #require(MiniGameMascot.sideProfile(character: fox.manifest))
    let botImage = try #require(MiniGameMascot.sideProfile(character: bot.manifest))
    let foxAgain = try #require(MiniGameMascot.sideProfile(character: fox.manifest))
    #expect(foxImage === foxAgain, "같은 캐릭터인데 다시 만들었다 — 캐시가 안 먹는다")
    #expect(foxImage !== botImage, "캐릭터가 다른데 같은 그림이 나왔다")
}

// MARK: - 오프스크린 렌더(실제 그림)

@MainActor
@Test("여우 스프라이트 씬이 실제로 그려진다 — 알파 커버리지·투명 배경·크기")
func v0315SpriteSceneActuallyRenders() throws {
    let fox = try v0315Sprite()
    let size = CGSize(width: 280, height: 340)
    guard let aingPNG = CheckCharacter3DScene.renderSnapshotPNG(size: size) else {
        print("[v0315] Metal 없음 — 렌더 검증을 건너뛴다")
        return
    }
    let foxPNG = try #require(
        CheckCharacter3DScene.renderSnapshotPNG(size: size, character: fox.manifest, atlas: fox.atlas)
    )
    let botFixture = try v0315Sprite("bot")
    let botPNG = CheckCharacter3DScene.renderSnapshotPNG(size: size, character: botFixture.manifest,
                                                         atlas: botFixture.atlas)

    let aing = try #require(v0315AlphaStats(aingPNG))
    let foxStats = try #require(v0315AlphaStats(foxPNG))
    print(String(format: "[v0315] 렌더 %.0fx%.0f — 아잉 알파 %.2f%% box(%.3f,%.3f,%.3f,%.3f)",
                 aing.size.width, aing.size.height, aing.coverage,
                 aing.box?.minX ?? -1, aing.box?.minY ?? -1, aing.box?.width ?? -1, aing.box?.height ?? -1))
    print(String(format: "[v0315] 렌더 %.0fx%.0f — 여우 알파 %.2f%% box(%.3f,%.3f,%.3f,%.3f)",
                 foxStats.size.width, foxStats.size.height, foxStats.coverage,
                 foxStats.box?.minX ?? -1, foxStats.box?.minY ?? -1,
                 foxStats.box?.width ?? -1, foxStats.box?.height ?? -1))
    if let bot = botPNG.flatMap(v0315AlphaStats) {
        print(String(format: "[v0315] 렌더 %.0fx%.0f — 로봇 알파 %.2f%%", bot.size.width, bot.size.height, bot.coverage))
    }

    // 저장 — 사람이 직접 열어 본다.
    if let rep = NSBitmapImageRep(data: foxPNG) { MiniGameSnapshots.save(rep, name: "scene-fox.png", sub: "v0315") }
    if let rep = NSBitmapImageRep(data: aingPNG) { MiniGameSnapshots.save(rep, name: "scene-aing.png", sub: "v0315") }
    if let png = botPNG, let rep = NSBitmapImageRep(data: png) {
        MiniGameSnapshots.save(rep, name: "scene-bot.png", sub: "v0315")
    }
    if let image = MiniGameMascot.sideProfile(character: fox.manifest),
       let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        MiniGameSnapshots.save(NSBitmapImageRep(cgImage: cg), name: "sideprofile-fox.png", sub: "v0315")
    }
    print("[v0315] 스냅샷 경로: \(MiniGameSnapshots.directory("v0315").path)")

    // (a) 캐릭터가 보인다.
    #expect(foxStats.coverage > 5, "여우가 거의 안 그려졌다(\(foxStats.coverage)%)")
    // (b) 배경이 투명하다 — 꽉 찬 사각형이면 100% 에 가까워진다.
    #expect(foxStats.coverage < 70, "배경이 투명하지 않다(\(foxStats.coverage)%)")
    // (c) 아잉과 크기가 비슷하다. 프레임 안 실루엣 상자의 긴 변으로 잰다.
    let aingBox = try #require(aing.box), foxBox = try #require(foxStats.box)
    let aingSide = max(aingBox.width, aingBox.height), foxSide = max(foxBox.width, foxBox.height)
    print(String(format: "[v0315] 실루엣 긴 변 — 아잉 %.3f · 여우 %.3f (비 %.3f)",
                 aingSide, foxSide, foxSide / aingSide))
    #expect(abs(foxSide / aingSide - 1) < 0.35,
            "여우 실루엣이 아잉의 \(foxSide / aingSide) 배다 — 같은 자리에서 크기가 튄다")
}
