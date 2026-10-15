import AppKit
import ImageIO
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// v0.3.54 — 황금 아잉이 3D(맥). 실제 앱 씬(`CheckCharacter3DScene.makeScene`)을 오프스크린으로 그려 **결과**를 잰다:
//  · 금 착용자의 몸이 금빛이고(시안 통계 — ref measure.swift 정의), 보라 아잉은 같은 잣대에 걸린다(기준선).
//  · 후광 판이 아트 스크립트 머리말의 크기·자리로 서고, 몸 크기 계산(프레이밍 · 리액션 진폭 · 클릭 rect)에 끼지 않는다.
//  · 감은 눈은 라벤더 원본에서 굽고 같은 합성을 한다 — 금 몸에 라벤더 눈꺼풀이 안 남는다(금에서 바로 구우면 남는다 — 기준선).
//  · 울트라 가드가 아잉과 황금 아잉이를 가른다(지도 함정 8) — 금 착용자가 아잉에게 맞으면 갈아입는다.
//
// 미리보기: 환경변수 `CHECK_V0354_MAC_PREVIEW_DIR` 가 있으면 렌더를 PNG 로 떨군다(`CHECK_V0354_TARGET_DIR` 가 있으면 시안과 나란히).

@MainActor
@Suite struct V0354GoldAing3DTests {
    static let gold = CharacterCatalog.builtInGoldAing
    static let aing = CharacterCatalog.builtInAing

    // MARK: 도구

    static func scene(_ manifest: CharacterManifest) throws -> SCNScene {
        try #require(CheckCharacter3DScene.makeScene(animated: false, character: manifest))
    }

    static func wrapper(_ scene: SCNScene) throws -> SCNNode {
        try #require(scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
    }

    static func character(_ scene: SCNScene) throws -> SCNNode {
        let facing = try #require(try wrapper(scene).childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false))
        return try #require(facing.childNodes.first)
    }

    static func faceImage(_ scene: SCNScene) throws -> CGImage {
        let material = try #require(SleepEyeExplore.faceMaterial(in: scene))
        return try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
    }

    static func halo(_ scene: SCNScene) -> SCNNode? {
        scene.rootNode.childNode(withName: GoldAingFinish.haloNodeName, recursively: true)
    }

    static func cameraNode(_ scene: SCNScene) -> SCNNode? {
        var found: SCNNode?
        scene.rootNode.enumerateHierarchy { node, stop in
            if node.camera != nil { found = node; stop.pointee = true }
        }
        return found
    }

    /// 아트 스크립트의 정면 시안 카메라(FOV 30 · 거리 = H/2/tan15° × 2.0 · 몸 중심보다 0.05H 위) — 확정 시안과 같은 구도.
    static func frontCamera(for scene: SCNScene) -> SCNNode {
        let (minB, maxB) = scene.rootNode.boundingBox
        let center = SIMD3<Float>(Float(minB.x + maxB.x) / 2, Float(minB.y + maxB.y) / 2, Float(minB.z + maxB.z) / 2)
        let h = Float(maxB.y - minB.y)
        let distance = h / 2 / tan(15 * Float.pi / 180) * 2.0
        let node = SCNNode()
        node.camera = SCNCamera()
        node.camera?.fieldOfView = 30
        node.camera?.zNear = 0.01
        node.camera?.zFar = 1_000
        node.simdPosition = SIMD3(center.x, center.y + h * 0.05, center.z + distance)
        node.simdLook(at: center)
        return node
    }

    static func render(_ scene: SCNScene, pointOfView: SCNNode? = nil, size: CGSize,
                       background: NSColor? = nil) throws -> CGImage {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = SCNRenderer(device: device, options: nil)
        let previous = scene.background.contents
        if let background { scene.background.contents = background }
        defer { scene.background.contents = previous }
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = false
        if let pointOfView { renderer.pointOfView = pointOfView }
        let shot = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        let rep = try #require(shot.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) })
        return try #require(rep.cgImage)
    }

    static func writePreview(_ image: CGImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["CHECK_V0354_MAC_PREVIEW_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    /// 노랑 계열 금(빨강·초록이 둘 다 파랑보다 20 이상 크다 — 아트 테스트와 같은 판정).
    static func isGold(_ r: Int, _ g: Int, _ b: Int) -> Bool { r - b >= 20 && g - b >= 20 }

    // MARK: ① 합성 · 후광 판

    @Test("황금 아잉이 씬: 얼굴 디퓨즈의 라벤더 피부가 전부 금으로 바뀌고 눈·볼·입은 그대로다 — 아잉 씬은 라벤더 그대로(기준선)")
    func goldSceneCompositesTheFace() throws {
        let plain = try Self.faceImage(try Self.scene(Self.aing))
        let gold = try Self.faceImage(try Self.scene(Self.gold))
        #expect(plain.width == gold.width && plain.height == gold.height)
        let p = SleepEyeExplore.rgbaBuffer(plain), g = SleepEyeExplore.rgbaBuffer(gold)
        var lavender = 0, lavenderLeft = 0, goldened = 0, decoration = 0, decorationChanged = 0
        for o in stride(from: 0, to: p.count, by: 4) {
            let pr = Int(p[o]), pg = Int(p[o + 1]), pb = Int(p[o + 2])
            if GoldAingFinish.isGoldSkin(pr, pg, pb) {
                lavender += 1
                if GoldAingFinish.isGoldSkin(Int(g[o]), Int(g[o + 1]), Int(g[o + 2])) { lavenderLeft += 1 }
                if Self.isGold(Int(g[o]), Int(g[o + 1]), Int(g[o + 2])) { goldened += 1 }
            } else {
                decoration += 1
                if (0..<3).contains(where: { abs(Int(p[o + $0]) - Int(g[o + $0])) > 2 }) { decorationChanged += 1 }
            }
        }
        #expect(lavender > 100_000, "기준선: 아잉 디퓨즈의 라벤더 피부가 \(lavender) 텍셀뿐 — 잣대가 아무것도 못 본다")
        #expect(lavenderLeft == 0, "금 씬에 라벤더 피부가 \(lavenderLeft) 텍셀 남았다(날개 이음매 보라 줄)")
        #expect(goldened == lavender, "라벤더 \(lavender) 중 금이 된 텍셀 \(goldened)")
        #expect(decoration > 1_000 && decorationChanged * 100 <= decoration,
                "눈·볼·입 텍셀 \(decoration) 중 \(decorationChanged) 이 바뀌었다 — 피부만 바꿔야 한다")
    }

    @Test("isGoldSkin 은 감은 눈의 isSkin 을 품는다(이 텍스처에서 isSkin ⊂ isGoldSkin) · 더 넓은 몫이 아트 실측(605 텍셀)과 같다")
    func goldMaskContainsTheSleepEyeSkin() throws {
        let plain = SleepEyeExplore.rgbaBuffer(try Self.faceImage(try Self.scene(Self.aing)))
        var skinOnly = 0, wider = 0
        for o in stride(from: 0, to: plain.count, by: 4) {
            let r = Int(plain[o]), g = Int(plain[o + 1]), b = Int(plain[o + 2])
            let skin = SleepEyeTexture.isSkin(r, g, b), goldSkin = GoldAingFinish.isGoldSkin(r, g, b)
            if skin && !goldSkin { skinOnly += 1 }
            if goldSkin && !skin { wider += 1 }
        }
        #expect(skinOnly == 0, "isSkin 인데 isGoldSkin 이 아닌 텍셀 \(skinOnly) — 금 합성이 감은 눈 피부를 놓친다")
        #expect(wider == 605, "isGoldSkin 이 isSkin 보다 넓은 몫 \(wider) — 아트 스크립트(605)와 식이 갈렸다")
    }

    @Test("후광 판: 아트 규약(2.0×H 정사각 · 바운딩박스 중심 · 빌보드 · 순서 −1 · 깊이 끔 · 알파)대로 캐릭터 노드 아래에 선다 — 아잉엔 없다")
    func haloPlaneFollowsTheArtContract() throws {
        let goldScene = try Self.scene(Self.gold)
        #expect(Self.halo(try Self.scene(Self.aing)) == nil, "보라 아잉에 후광이 섰다")
        let halo = try #require(Self.halo(goldScene), "황금 아잉이에 후광이 없다")
        #expect(halo.parent === (try Self.character(goldScene)),
                "후광이 캐릭터 노드 아래가 아니다 — 부유(bob)를 따라 움직이지 않는다")
        let plane = try #require(halo.geometry as? SCNPlane)
        // 아트 스크립트 머리말: H = 1.695736 → 3.391472, 중심 (−0.001055, 0.001083, −0.000753).
        #expect(abs(plane.width - 3.391472) < 0.001 && abs(plane.height - 3.391472) < 0.001,
                "후광 판 \(plane.width)×\(plane.height) — 2.0×H(3.391472)가 아니다")
        #expect(abs(halo.position.x + 0.001055) < 0.0002 && abs(halo.position.y - 0.001083) < 0.0002
                && abs(halo.position.z + 0.000753) < 0.0002, "후광 판 중심 \(halo.position)")
        #expect(halo.renderingOrder == -1)
        #expect(halo.constraints?.contains { $0 is SCNBillboardConstraint } == true, "빌보드가 아니다")
        #expect(halo.categoryBitMask == GoldAingFinish.haloCategoryBit)
        let material = try #require(plane.firstMaterial)
        #expect(material.lightingModel == .constant && material.blendMode == .alpha && material.isDoubleSided)
        #expect(!material.writesToDepthBuffer && !material.readsFromDepthBuffer)
        #expect(material.name == GoldAingFinish.haloMaterialName)
    }

    @Test("후광은 몸 크기 계산에 안 낀다: 카메라 프레이밍·몸 바운딩박스가 보라 아잉과 같다(판이 끼면 두 배 가까이 부푼다)")
    func haloDoesNotInflateTheBody() throws {
        let goldScene = try Self.scene(Self.gold), plainScene = try Self.scene(Self.aing)
        let goldCamera = try #require(Self.cameraNode(goldScene)), plainCamera = try #require(Self.cameraNode(plainScene))
        #expect(simd_distance(goldCamera.simdPosition, plainCamera.simdPosition) < 1e-4,
                "금 씬 카메라 \(goldCamera.simdPosition) ≠ 아잉 \(plainCamera.simdPosition) — 후광이 프레이밍을 밀었다")
        let goldBox = try Self.wrapper(goldScene).boundingBox, plainBox = try Self.wrapper(plainScene).boundingBox
        let goldExtent = max(goldBox.max.x - goldBox.min.x, goldBox.max.y - goldBox.min.y)
        let plainExtent = max(plainBox.max.x - plainBox.min.x, plainBox.max.y - plainBox.min.y)
        #expect(abs(goldExtent - plainExtent) < 0.01,
                "몸 크기 금 \(goldExtent) vs 아잉 \(plainExtent) — 리액션 진폭·클릭 rect 가 부푼다")
        // 기준선: 판의 바운딩박스를 안 덮었다면 판 크기(3.39)가 그대로 섞인다 — 잣대가 그 차이를 가른다.
        let raw = SCNPlane(width: 3.391472, height: 3.391472)
        #expect(raw.boundingBox.max.x - raw.boundingBox.min.x > CGFloat(plainExtent) * 1.5)
    }

    // MARK: ② 렌더 결과 — 시안 통계

    @Test("실제 앱 씬을 시안 카메라로 그리면 몸 색이 확정 시안 통계(평균 ±8 · 밝기 분위 ±12) 안이다 — 보라 아잉은 걸린다")
    func goldRenderMatchesTheTarget() throws {
        let goldScene = try Self.scene(Self.gold), plainScene = try Self.scene(Self.aing)
        let size = CGSize(width: 512, height: 512)
        // 몸 통계는 몸만으로 잰다(후광은 몸 밖 빛 — 아트 검증과 같은 절차).
        let halo = try #require(Self.halo(goldScene))
        halo.isHidden = true
        let goldBody = try Self.render(goldScene, pointOfView: Self.frontCamera(for: goldScene), size: size)
        halo.isHidden = false
        let plainBody = try Self.render(plainScene, pointOfView: Self.frontCamera(for: plainScene), size: size)
        let goldStats = V0354GoldAingArtTests.bodyStats(goldBody), plainStats = V0354GoldAingArtTests.bodyStats(plainBody)
        print("[v0354-3d] 금 몸 mean \(Int(goldStats.mean.0)) \(Int(goldStats.mean.1)) \(Int(goldStats.mean.2)) · lum \(goldStats.p10)/\(goldStats.p50)/\(goldStats.p90) · n \(goldStats.n)")
        #expect(goldStats.n > 20_000, "금빛 몸 픽셀이 \(goldStats.n) 개뿐 — 몸이 금이 아니다")
        #expect(V0354GoldAingArtTests.matchesTarget(goldStats),
                "금 몸 mean \(Int(goldStats.mean.0)) \(Int(goldStats.mean.1)) \(Int(goldStats.mean.2)) · lum \(goldStats.p10)/\(goldStats.p50)/\(goldStats.p90) — 시안(240 203 103 · 166/211/235) 밖")
        #expect(!V0354GoldAingArtTests.matchesTarget(plainStats) && plainStats.n < goldStats.n / 10,
                "기준선: 보라 아잉이 금 잣대를 통과한다(n \(plainStats.n))")
        Self.writePreview(goldBody, "gold-3d-front-body.png")

        // 후광 — 앱처럼 **투명 배경**으로 그린 뒤, 창 합성기와 같은 방식(sRGB 프리멀티 'over')으로 밝은·어두운 바탕에 얹어
        // 시안 후광(= `aing_gold-halo.png`, 몸 밖 픽셀이 시안과 같다 — 아트 보고)을 같은 바탕에 얹은 것과 맞댄다.
        // 기준선: 보정 안 한 후광 PNG 를 그대로 판에 붙이면(SceneKit 이 선형 프리멀티로 적는다) 같은 잣대에서 크게 벗어난다.
        let haloURL = try #require(GoldAingFinish.resourceURL(GoldAingArt.haloResourceName))
        let rawHalo = try #require(CGImageSourceCreateWithURL(haloURL as CFURL, nil)
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let transparent = try Self.render(goldScene, pointOfView: Self.frontCamera(for: goldScene), size: size)
        let haloMaterial = try #require(halo.geometry?.firstMaterial)
        let compensated = haloMaterial.diffuse.contents
        haloMaterial.diffuse.contents = rawHalo
        let uncompensated = try Self.render(goldScene, pointOfView: Self.frontCamera(for: goldScene), size: size)
        haloMaterial.diffuse.contents = compensated
        for (name, gray) in [("light", 0.95), ("dark", 0.11)] {
            let target = try #require(Self.composite(rawHalo, over: gray))
            let app = try #require(Self.composite(transparent, over: gray))
            let raw = try #require(Self.composite(uncompensated, over: gray))
            let appDiff = Self.meanDiffOutsideBody(app, target, body: goldBody)
            let rawDiff = Self.meanDiffOutsideBody(raw, target, body: goldBody)
            print(String(format: "[v0354-3d] 후광 %@ 바탕: 시안과 몸 밖 평균 |ΔRGB| 보정 %.2f · 보정 없음 %.2f", name, appDiff.mean, rawDiff.mean)
                  + " · 최대 \(appDiff.peak) / \(rawDiff.peak)")
            #expect(appDiff.mean < 2.5, "\(name) 바탕: 창에 보일 후광이 시안과 평균 \(appDiff.mean) 다르다")
            #expect(rawDiff.mean > appDiff.mean * 3, "기준선이 안 갈린다(보정 없음 \(rawDiff.mean) vs 보정 \(appDiff.mean))")
            Self.writePreview(app, "gold-3d-front-halo-\(name).png")
            let appCamera = try #require(Self.composite(try Self.render(goldScene, size: CGSize(width: 280, height: 340)), over: gray))
            Self.writePreview(appCamera, "gold-3d-app-camera-\(name).png")
        }
    }

    /// 투명 렌더를 회색 바탕에 sRGB 프리멀티 'over' 로 얹는다(창 서버가 투명 창을 합성하는 방식 — 적힌 값 + 바탕·(1−A)).
    static func composite(_ image: CGImage, over gray: Double) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// 몸(알파 ≥ 250 · 2px 팽창) 밖 픽셀의 평균·최대 |ΔRGB|.
    static func meanDiffOutsideBody(_ a: CGImage, _ b: CGImage, body: CGImage) -> (mean: Double, peak: Int) {
        let w = a.width, h = a.height
        guard let pa = GoldAingFinish.rgbaBytes(a), let pb = GoldAingFinish.rgbaBytes(b, width: w, height: h),
              let mask = GoldAingFinish.rgbaBytes(body, width: w, height: h) else { return (.infinity, 255) }
        var sum = 0.0, count = 0.0, peak = 0
        for y in 0..<h { for x in 0..<w {
            var nearBody = false
            for dy in -2...2 { for dx in -2...2 {
                let xx = x + dx, yy = y + dy
                if xx >= 0, yy >= 0, xx < w, yy < h, mask[(yy * w + xx) * 4 + 3] >= 250 { nearBody = true }
            } }
            if nearBody { continue }
            let o = (y * w + x) * 4
            let d = (0..<3).map { abs(Int(pa[o + $0]) - Int(pb[o + $0])) }
            sum += Double(d.reduce(0, +)) / 3; count += 1; peak = max(peak, d.max() ?? 0)
        } }
        return (count > 0 ? sum / count : .infinity, peak)
    }

    // MARK: ③ 감은 눈

    @Test("감은 눈: 금 얼굴은 라벤더 원본에서 굽고 합성한다 — 덮인 텍셀이 전부 금 · 금에서 바로 구우면 라벤더가 남는다(기준선)")
    func closedEyesOnGoldAreGold() throws {
        let goldScene = try Self.scene(Self.gold)
        let goldFace = try Self.faceImage(goldScene)
        let geometry = SleepEyeExplore.faceGeometry(in: goldScene)
        let closed = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: goldFace, geometry: geometry))
        let open = SleepEyeExplore.rgbaBuffer(goldFace), shut = SleepEyeExplore.rgbaBuffer(closed)
        var covered = 0, notGold = 0
        for i in 0..<(open.count / 4) where (0..<3).contains(where: { abs(Int(open[i * 4 + $0]) - Int(shut[i * 4 + $0])) > 6 }) {
            covered += 1
            if !Self.isGold(Int(shut[i * 4]), Int(shut[i * 4 + 1]), Int(shut[i * 4 + 2])) { notGold += 1 }
        }
        #expect(covered > 500, "감은 눈이 \(covered) 텍셀만 바꿨다 — 커버가 안 돌았다")
        #expect(notGold * 100 <= covered, "금 감은 눈 커버 \(covered) 중 금이 아닌 텍셀 \(notGold) — 라벤더 눈꺼풀 얼룩")
        // 기준선: 금 디퓨즈에서 **바로** 구우면(감은 눈 색 분류가 금 피부를 못 알아본다) 금이 아닌 커버가 크게 남는다.
        let naive = try #require(CheckCharacter3DScene.lavenderClosedEyesImage(faceImage: goldFace, geometry: geometry))
        let naivePx = SleepEyeExplore.rgbaBuffer(naive)
        var naiveCovered = 0, naiveNotGold = 0
        for i in 0..<(open.count / 4) where (0..<3).contains(where: { abs(Int(open[i * 4 + $0]) - Int(naivePx[i * 4 + $0])) > 6 }) {
            naiveCovered += 1
            if !Self.isGold(Int(naivePx[i * 4]), Int(naivePx[i * 4 + 1]), Int(naivePx[i * 4 + 2])) { naiveNotGold += 1 }
        }
        print("[v0354-3d] 감은 눈 커버: 금 \(covered)/비금 \(notGold) · 금에서 바로 \(naiveCovered)/비금 \(naiveNotGold)")
        #expect(naiveNotGold * 10 > naiveCovered, "기준선이 안 갈린다 — 금에서 바로 구워도 금이다(이 검사가 아무것도 못 본다)")
    }

    @Test("엔진: 금 착용자가 졸면 얼굴이 금 감은 눈으로 바뀌고 깨면 금 뜬 눈으로 돌아온다(라벤더로 새지 않는다)")
    func engineSleepsAndWakesInGold() throws {
        var now = Date(timeIntervalSince1970: 70_000)
        let engine = ReactionEngine(clock: { now })
        let scene = try Self.scene(Self.gold)
        let material = try #require(SleepEyeExplore.faceMaterial(in: scene))
        engine.attach(node: try Self.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        // 오른눈 아틀라스 픽셀(512 기준 — CheckSleepEyesTests 와 같은 자리). 뜬 눈은 눈, 감은 눈은 피부(금).
        let eyeX = 235, eyeY = 392
        let awake = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
        #expect(SleepEyeTexture.isEye(awake.0, awake.1, awake.2), "기준선: 뜬 눈 자리가 눈이 아니다")
        engine.request(.drowsy)
        #expect(engine.state == .sleeping)
        let asleep = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
        #expect(Self.isGold(asleep.0, asleep.1, asleep.2) && !SleepEyeTexture.isSkin(asleep.0, asleep.1, asleep.2),
                "감은 눈 자리 \(asleep) — 금이 아니다(라벤더면 금 몸에 보라 눈꺼풀)")
        engine.request(.wake)
        let woken = SleepEyeExplore.diffusePixel(material, eyeX, eyeY)
        #expect(SleepEyeTexture.isEye(woken.0, woken.1, woken.2))
        // 깬 뒤 피부는 여전히 금(라벤더 원본으로 되돌아가지 않는다).
        let skin = SleepEyeExplore.diffusePixel(material, 256, 120)
        #expect(!GoldAingFinish.isGoldSkin(skin.0, skin.1, skin.2), "깬 뒤 피부 \(skin) 가 라벤더다")
        now = now.addingTimeInterval(1)
    }

    // MARK: ④ 식별 · 울트라 가드

    @Test("엔진은 아잉과 황금 아잉이를 가른다 — 교체·원복 왕복에서도")
    func engineTellsGoldFromAing() throws {
        let engine = ReactionEngine()
        let scene = try Self.scene(Self.gold)
        engine.attach(node: try Self.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        #expect(engine.currentCharacterID == CharacterCatalog.goldAingID)
        let stashed = try #require(engine.swapCharacter(to: Self.aing, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID, "보라 아잉으로 갈아입었는데 금이라고 한다")
        #expect(Self.halo(scene) == nil, "보라 아잉으로 갈아입었는데 후광이 남았다")
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == CharacterCatalog.goldAingID)
        #expect(Self.halo(scene) != nil, "원복한 금 아잉에 후광이 없다")
        // 교체로 세운 금(makeCharacterNode 경로)도 금 마감을 입는다.
        let plainScene = try Self.scene(Self.aing)
        let plainEngine = ReactionEngine()
        plainEngine.attach(node: try Self.wrapper(plainScene), sceneRoot: plainScene.rootNode, view: nil)
        #expect(plainEngine.currentCharacterID == CharacterCatalog.builtInAingID)
        #expect(plainEngine.swapCharacter(to: Self.gold, in: plainScene) != nil)
        #expect(plainEngine.currentCharacterID == CharacterCatalog.goldAingID)
        let swappedFace = SleepEyeExplore.rgbaBuffer(try Self.faceImage(plainScene))
        let lavenderLeft = stride(from: 0, to: swappedFace.count, by: 4).filter {
            GoldAingFinish.isGoldSkin(Int(swappedFace[$0]), Int(swappedFace[$0 + 1]), Int(swappedFace[$0 + 2]))
        }.count
        #expect(lavenderLeft == 0, "교체로 세운 금 아잉 얼굴에 라벤더 피부 \(lavenderLeft) 텍셀")
    }

    @Test("울트라: 금 착용자가 아잉 착용자에게 맞으면 보라 아잉으로 갈아입고, 끝나면 금으로 돌아온다")
    func ultraFromAingSwapsTheGoldWearer() throws {
        let controller = try V0354UltraHarness.mounted(receiver: Self.gold)
        #expect(controller.engine.currentCharacterID == CharacterCatalog.goldAingID, "기준선이 금이 아니다")
        var atCover: String?
        controller.onUltraWillCoverScreen = { [weak controller] in atCover = controller?.engine.currentCharacterID }
        controller.handleReceivedPokes([V0354UltraHarness.ultra(from: nil)])   // nil = 아잉
        #expect(controller.isUltraActive)
        #expect(atCover == CharacterCatalog.builtInAingID,
                "화면을 덮을 때 \(atCover ?? "nil") — 금 착용자가 아잉에게 맞았는데 내 금 아잉이 섰다(지도 함정 8)")
        controller.endUltraTakeover()
        #expect(controller.engine.currentCharacterID == CharacterCatalog.goldAingID, "원복이 금 아잉을 안 돌려놨다")
        controller.updateWorking(false)
    }

    @Test("울트라: 금 착용자가 찌르면 받는 쪽 화면에 후광 달린 황금 아잉이가 선다")
    func ultraFromGoldShowsTheGoldAing() throws {
        let controller = try V0354UltraHarness.mounted(receiver: Self.aing)
        controller.handleReceivedPokes([V0354UltraHarness.ultra(from: CharacterCatalog.goldAingID)])
        #expect(controller.isUltraActive)
        #expect(controller.engine.currentCharacterID == CharacterCatalog.goldAingID)
        let scene = try #require(controller.engine.attachedScene)
        #expect(Self.halo(scene) != nil, "찌른 사람의 황금 아잉이에 후광이 없다")
        controller.endUltraTakeover()
        #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID)
        controller.updateWorking(false)
    }

    // MARK: ⑤ 클릭 — 후광은 몸이 아니다

    @Test("몸 클릭 hitTest 는 후광 판을 빼고 묻는다 — 몸 밖·후광 안 점은 안 맞고, 몸 가운데는 맞는다")
    func bodyHitTestIgnoresTheHalo() throws {
        let scene = try Self.scene(Self.gold)
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 280, height: 340))
        view.scene = scene
        view.pointOfView = Self.cameraNode(scene)
        _ = view.snapshot()   // 렌더 한 번 — 표현 트리(빌보드 제약 포함)가 서야 hitTest 가 앱과 같은 판을 본다
        let wrapper = try Self.wrapper(scene)
        // 몸 밖(왼쪽 가장자리 · 가운데 높이 — 판 안, 몸 밖)·후광 안 점과 몸 가운데 점. 가운데 높이라 뷰 좌표가 뒤집혀 있어도 같다.
        let outside = NSPoint(x: 8, y: 170), center = NSPoint(x: 140, y: 170)
        func hits(_ point: NSPoint, mask: Bool) -> [SCNHitTestResult] {
            var options: [SCNHitTestOption: Any] = [.rootNode: wrapper, .boundingBoxOnly: false, .ignoreHiddenNodes: true]
            if mask { options[.categoryBitMask] = GoldAingFinish.bodyHitCategoryMask }
            return view.hitTest(point, options: options)
        }
        // 앱 그대로(점 바운딩박스 + 카테고리 마스크): 몸 밖·후광 안 점은 안 맞고 몸 가운데는 맞는다.
        #expect(hits(outside, mask: true).isEmpty, "몸 밖·후광 안 점이 몸으로 맞았다 — 바탕화면 클릭을 먹는다")
        #expect(hits(center, mask: true).contains { $0.node.name != GoldAingFinish.haloNodeName }, "몸 가운데가 안 맞는다")
        // 기준선: 같은 크기·자리의 **장치 없는** 판(바운딩박스 그대로 · 기본 카테고리)을 같은 부모에 세우면 같은 점에서 맞는다
        // — 점 고르기가 판 위라는 증거다. 그 판에 후광 카테고리 비트를 주면 앱 마스크가 걸러 낸다(바운딩박스 덮기와 별개로 막는다).
        let halo = try #require(Self.halo(scene))
        let side = try #require(halo.geometry as? SCNPlane).width
        let probe = SCNNode(geometry: SCNPlane(width: side, height: side))
        probe.name = "probe.plainHalo"
        probe.position = halo.position
        try #require(halo.parent).addChildNode(probe)
        _ = view.snapshot()   // 렌더 한 번 — 새 노드가 표현 트리에 실린다(안 그리면 hitTest 가 아직 모른다)
        #expect(hits(outside, mask: false).contains { $0.node === probe },
                "기준선: 몸 밖 점에서 장치 없는 판이 안 맞는다 — 점 고르기가 틀렸다")
        probe.categoryBitMask = GoldAingFinish.haloCategoryBit
        _ = view.snapshot()
        #expect(hits(outside, mask: true).isEmpty, "카테고리 비트만으로는 후광 판을 못 거른다")
        probe.removeFromParentNode()
        // 앱 경로가 이 마스크를 실제로 쓴다(소스 계약 — 주석을 걷어내고 본다).
        let source = try String(contentsOf: V0354CoreArtBaseline.repoRoot
            .appendingPathComponent("Sources/check/CheckOverlayReactions.swift"), encoding: .utf8)
        let code = source.split(separator: "\n").map { line -> Substring in
            guard let range = line.range(of: "//") else { return line }
            return line[..<range.lowerBound]
        }.joined(separator: "\n")
        #expect(code.contains(".categoryBitMask: GoldAingFinish.bodyHitCategoryMask"), "몸 클릭 hitTest 가 후광 마스크를 안 쓴다")
    }

    // MARK: ⑥ 초상

    @Test("초상 조회: 금 id 는 금 초상(아잉 폴백 아님) · 남의 아바타·그릴 수 있는 목록·능력 번호 2 에 든다")
    func goldPortraitLookups() throws {
        let neutral = try #require(CheckMascotAssets.portraitURL(for: .neutral, characterID: CharacterCatalog.goldAingID))
        let negative = try #require(CheckMascotAssets.portraitURL(for: .negative, characterID: CharacterCatalog.goldAingID))
        #expect(neutral.lastPathComponent == "aing_gold-neutral.png" && negative.lastPathComponent == "aing_gold-negative.png")
        let goldImage = try #require(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.goldAingID)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil))
        let plainImage = try #require(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.builtInAingID)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil))
        let goldStats = V0354GoldAingArtTests.bodyStats(goldImage), plainStats = V0354GoldAingArtTests.bodyStats(plainImage)
        #expect(goldStats.n > plainStats.n * 3, "메뉴바·헤더 금 초상이 금이 아니다(아잉 폴백?) 금 \(goldStats.n) vs 아잉 \(plainStats.n)")
        #expect(AppUserAvatarArt.knownIDs.contains(CharacterCatalog.goldAingID), "남의 아바타가 금 초상을 모른다(이니셜이 선다)")
        #expect(CheckMascotAssets.drawableCharacterIDs().contains(CharacterCatalog.goldAingID))
        #expect(GoldAingFinish.isDrawable())
        // 기준선: 마감 그림 하나가 없는 번들은 그릴 수 없다(초상만으로는 아니다).
        #expect(!GoldAingArt.isDrawable(on: .mac) { $0 != GoldAingArt.haloResourceName })
    }
}

// MARK: - 울트라 하네스(V0321 과 같은 모양 — 격리 스토어 위 근무 중 컨트롤러 + 마운트된 씬)

@MainActor
enum V0354UltraHarness {
    static func mounted(receiver: CharacterManifest, function: String = #function) throws -> CheckOverlayController {
        let defaults = CheckTestScratch.defaults("v0354-ultra", function: function)
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
                                   defaults: defaults, workspaceNotifications: nil)
        store.setOverlayEnabled(true)
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        let controller = CheckOverlayController(store: store, notificationCenter: NotificationCenter())
        controller.updateWorking(true)
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false, character: receiver))
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 140, height: 170))
        view.scene = scene
        let wrapper = try #require(scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false))
        controller.engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: view)
        return controller
    }

    static func ultra(from characterID: String?, id: String = "u1") -> ReceivedPoke {
        ReceivedPoke(id: id, fromName: "보낸이", createdAt: Date(), kind: .ultra, fromCharacterID: characterID)
    }
}
