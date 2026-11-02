import AppKit
import Observation
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// v0.3.74 — 이슬 아잉이 3D(맥) · 그림 저장소. 실제 앱 씬(`CheckCharacter3DScene.makeScene` · 교체 경로 · 엔진)을 오프스크린 SCNRenderer 로 그려
// **결과**를 잰다(창 없음 — 몸 클릭은 hitTest 결과와 판정 함수로, 울트라는 엔진 교체 경로로 잰다):
//  ① 생성기 사본: `IsulAingFinish` 의 몸 셰이더 · 병뚜껑 구획이 `scripts/make-isul-aing.swift` 의 BEGIN/END 구획과 글자 그대로다(주석 · 공백을 걷고 맞댄다) ·
//     상수가 케이크 상수와 같다 · 뚜껑 꼭대기가 생성기 상수와 같다(앱이 만든 뚜껑으로 다시 잰다).
//  ② 마감이 선다: 얼굴 재질 = 무지개와 같은 합성 디퓨즈 + 이슬 몸 셰이더 + 셰이더 인자 둘(ckShadeMap · ckLabelMap mipFilter .linear) · 몸 메시에
//     `check.isulDecor` · 표식 · 내리지 않음. 아잉 · 황금 · 무지개 · 케이크에는 없다(기준선). 렌더가 초록 유리다.
//  ③ 감은 눈(엔진 CGImage 경로 · 뷰가 있는 GPU 텍스처 경로)에서도 눈 자리가 초록 유리다 — 라벤더가 아니다.
//  ④ 장식은 몸이 아니다: 얼굴 탐색이 뚜껑 재질을 안 잡고 · 뚜껑 자리 hitTest 맞음은 전부 장식이다 · 리액션 진폭은 몸만 잰다.
//  ⑤ 프레이밍: 뚜껑 위 끝이 부유 꼭대기(+0.07)에서도 프레임 위 2% 안쪽(생성기 실측 0.071) · 아잉 구도 그대로.
//  ⑥ 엔진이 이슬을 가르고 교체 · 원복 왕복에서 마감이 따라온다(울트라 교체 = `makeCharacterNode` 같은 갈래).
//  ⑦ 그릴 수 있다 → 능력 번호 5.
//  ⑧ 그림 저장소(`IsulArt`): 판정 · 경로 · 번들 폴백 · 디스크 캐시 → 번들 · 응답 받아들이기(200 · 304 · 404 · 못 쓰는 그림) · 조건부 요청 머리.
// 증거 PNG: `CHECK_V0374_MAC_EVIDENCE_DIR=<폴더>` 를 주면 앱 구도 스틸 · 아바타 · 상점 초상을 떨군다(창 없음).

@MainActor
@Suite struct V0374IsulMac3DTests {
    static let isul = CharacterCatalog.builtInIsulAing
    static let appSize = CGSize(width: 280, height: 340)
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_V0374_MAC_EVIDENCE_DIR"]

    typealias Body = IsulAingFinish.IsulBody
    typealias Cap = IsulAingFinish.IsulCap

    // MARK: 도구

    static func decor(_ scene: SCNScene) -> SCNNode? {
        scene.rootNode.childNode(withName: IsulAingFinish.decorNodeName, recursively: true)
    }

    static func source(_ relative: String) throws -> String {
        try V0366CakeMac3DTests.source(relative)
    }

    static func normalized(_ code: String) -> String {
        V0366CakeMac3DTests.normalized(code)
    }

    static func region(_ text: String, _ name: String) throws -> String {
        try V0366CakeMac3DTests.region(text, from: "// BEGIN \(name)", to: "// END \(name)")
    }

    // MARK: ① 생성기 사본

    @Test("생성기 사본: 몸 셰이더 · 병뚜껑 구획이 scripts/make-isul-aing.swift 의 BEGIN/END 구획과 글자 그대로다(주석 · 공백만 무시)")
    func generatorRegionsAreVerbatim() throws {
        let script = try Self.source("scripts/make-isul-aing.swift")
        let app = try Self.source("Sources/check/IsulAingFinish.swift")
        for name in ["isul-body-shader", "isul-cap-decor"] {
            let s = Self.normalized(try Self.region(script, name))
            let a = Self.normalized(try Self.region(app, name))
            #expect(s.count > 2_000, "\(name) 구획이 너무 짧다(\(s.count)) — 표식을 잘못 잡았다")
            #expect(a == s, "\(name) 구획이 생성기와 다르다 — 생성기를 고치고 다시 옮겨라(첫 차이: \(V0366CakeMac3DTests.firstDifference(a, s)))")
        }
        // 기준선: 한 글자만 바꿔도 걸린다(비교가 헛돈다면 이 줄이 같다고 한다).
        let s = Self.normalized(try Self.region(script, "isul-body-shader"))
        #expect(s.replacingOccurrences(of: "static let glassShadeMix = 0.55", with: "static let glassShadeMix = 0.56") != s)
        #expect(s.contains("static let glassShadeMix = 0.55"), "기준선 문자열이 구획에 없다 — 위 줄이 헛돈다")
    }

    @Test("상수: 이슬 몸 좌표 · 타원체 · 피부 기준 휘도 · 볼터치가 케이크(초코) 상수와 같다 · 인자 이름 · 장식 이름 · 뚜껑 꼭대기")
    func constantsMatchTheCake() throws {
        #expect(Body.bodyTop == CakeAingFinish.bodyTop && Body.bodyHeight == CakeAingFinish.bodyHeight)
        #expect(Body.bodyTop == RainbowAingArt.bodyTop && Body.bodyHeight == RainbowAingArt.bodyHeight)
        #expect(Body.skinYRef == CakeAingFinish.chocoSkinYRef && Body.skinYRef == 0.56530)
        #expect(Body.blushSRGB == CakeAingFinish.chocoBlushSRGB)
        #expect(Body.ellipsoid == SIMD3(0.6084, 0.7191, 0.5329))
        // 케이크 초코 셰이더의 타원체 법선과 같은 값(초코는 글 안에 박았다 — 주석을 걷은 소스로 맞댄다).
        let cake = Self.normalized(try Self.source("Sources/check/CakeAingFinish.swift"))
        #expect(cake.contains("float3(0.6084, 0.7191, 0.5329)"), "케이크 초코 타원체가 바뀌었다 — 이슬도 같이")
        #expect(Body.shadeMapKey == CakeAingFinish.ChocoBody.shadeMapKey && Body.shadeMapKey == "ckShadeMap")
        #expect(Body.labelMapKey == "ckLabelMap")
        #expect(IsulAingFinish.decorNodeName == "check.isulDecor" && Cap.capNodeName == "check.isul.cap")
        #expect(AingDecor.rootNames == [CakeAingFinish.cakeDecorNodeName, IsulAingFinish.decorNodeName])
        // 뚜껑 꼭대기: 앱이 만든 뚜껑으로 다시 잰다(생성기가 실행 때 맞대는 상수와 같다).
        let decor = try #require(IsulAingFinish.decorNode())
        #expect(abs(Double(Cap.topY(decor)) - Cap.capTopY) < 5e-4, "뚜껑 꼭대기 \(Cap.topY(decor)) ≠ 상수 \(Cap.capTopY)")
        // 앱은 셰이더 글을 한 번만 짓는다 — 생성기 계산 속성과 같은 글.
        #expect(IsulAingFinish.bodyShaderModifiers == Body.shaderModifiers)
    }

    @Test("병뚜껑: 원본은 프로세스당 한 번 굽고 씬마다 사본(지오메트리를 나눠 쓴다) · 루트 아래 뚜껑 한 조각 · 재질은 .constant 512×128")
    func decorIsBuiltOncePerProcess() throws {
        let started = CFAbsoluteTimeGetCurrent()
        let first = try #require(IsulAingFinish.decorNode())
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        let builds = IsulAingFinish.decorBuildCountForTesting
        let second = try #require(IsulAingFinish.decorNode())
        // 굽기 비용(캐시 없이 한 벌 — 앱이 프로세스당 한 번 내는 값). 미리 굽기가 필요한지 판단 근거.
        let scene = try #require(CheckCharacter3DScene.loadModelScene())
        var body: SCNNode?
        scene.rootNode.enumerateHierarchy { node, stop in if node.geometry != nil { body = node; stop.pointee = true } }
        let t0 = CFAbsoluteTimeGetCurrent()
        _ = Cap.make(probe: CakeAingFinish.meshSurfaceProbe(try #require(body)))
        print(String(format: "[v0374-3d] 병뚜껑 한 벌 새로 굽기 %.1fms(이 빌드 구성)", (CFAbsoluteTimeGetCurrent() - t0) * 1_000))
        print(String(format: "[v0374-3d] 병뚜껑 첫 조회 %.1fms(이미 구웠으면 사본만) · 원본 구운 횟수 %d", ms, builds))
        #expect(builds == 1, "원본을 \(builds) 번 구웠다")
        #expect(IsulAingFinish.decorBuildCountForTesting == builds, "두 번째 조회가 또 구웠다")
        #expect(first !== second && first.name == IsulAingFinish.decorNodeName && second.name == IsulAingFinish.decorNodeName)
        let capA = try #require(first.childNode(withName: Cap.capNodeName, recursively: false))
        let capB = try #require(second.childNode(withName: Cap.capNodeName, recursively: false))
        #expect(capA.geometry === capB.geometry, "사본이 지오메트리를 나눠 쓰지 않는다")
        let material = try #require(capA.geometry?.firstMaterial)
        #expect(material.lightingModel == .constant)
        let texture = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        #expect(texture.width == 512 && texture.height == 128)
    }

    // MARK: ② 마감이 선다

    @Test("이슬 씬: 얼굴 = 무지개와 같은 합성 디퓨즈 + 이슬 몸 셰이더 + ckShadeMap · ckLabelMap(.linear) · 몸 메시에 병뚜껑 · 표식 · 내리지 않음 — 다른 아잉 변형엔 없다")
    func finishIsApplied() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.isul)
        let character = try V0354GoldAing3DTests.character(scene)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        #expect(material.shaderModifiers?[.fragment] == IsulAingFinish.bodyShaderModifiers[.fragment], "몸 셰이더가 안 걸렸다")
        #expect(material.shaderModifiers?[.geometry] == IsulAingFinish.bodyShaderModifiers[.geometry])
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        #expect(RainbowAingFinish.lavenderOriginal(ofRainbowFace: face) != nil, "디퓨즈가 무지개 합성(같은 객체)이 아니다 — 감은 눈 갈래를 못 탄다")
        let shade = try #require(material.value(forKey: Body.shadeMapKey) as? SCNMaterialProperty, "ckShadeMap 이 없다")
        #expect(SleepEyeExplore.cgImage(from: shade.contents) === RainbowAingFinish.shadeImage(), "ckShadeMap 이 무지개 캐시와 같은 그림이 아니다")
        let label = try #require(material.value(forKey: Body.labelMapKey) as? SCNMaterialProperty, "ckLabelMap 이 없다")
        #expect(label.mipFilter == .linear)
        let labelImage = try #require(SleepEyeExplore.cgImage(from: label.contents))
        #expect(labelImage === IsulArt.shared.labelImage(), "라벨 인자가 그림 저장소의 그림이 아니다")
        #expect(labelImage.width == 1200 && labelImage.height == 551, "번들 라벨 폴백이 아니다(\(labelImage.width)×\(labelImage.height))")
        let decor = try #require(Self.decor(scene), "병뚜껑이 없다")
        let mesh = try #require(decor.parent)
        #expect(mesh.geometry?.materials.contains { $0 === material } == true, "뚜껑이 몸 메시 노드 자식이 아니다(\(mesh.name ?? "?"))")
        #expect(IsulAingFinish.isIsul(character))
        #expect(character.simdPosition == .zero, "이슬은 내려 세우지 않는다(\(character.simdPosition))")
        #expect(V0366CakeMac3DTests.decor(scene) == nil && CakeAingFinish.kind(of: character) == nil, "이슬에 케이크 장식이 섰다")
        #expect(scene.rootNode.childNode(withName: RainbowAingFinish.haloNodeName, recursively: true) == nil, "이슬에 무지개 후광이 섰다")
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInGoldAing, CharacterCatalog.builtInRainbowAing,
                      CharacterCatalog.builtInCakeStrawberryAing, CharacterCatalog.builtInCakeChocoAing] {
            let scene = try V0354GoldAing3DTests.scene(other)
            #expect(Self.decor(scene) == nil, "\(other.id) 에 병뚜껑이 섰다")
            #expect(!IsulAingFinish.isIsul(try V0354GoldAing3DTests.character(scene)))
            #expect(try V0359Rainbow3DTests.faceMaterial(scene).value(forKey: Body.labelMapKey) == nil, "\(other.id) 에 라벨 인자가 섰다")
        }
    }

    @Test("렌더: 정면 몸이 초록 유리다(라벤더 아님) · 라벨 자리가 밝은 흰 판 · 뚜껑 자리가 짙은 초록")
    func rendersGreenGlass() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.isul)
        let image = try V0359Rainbow3DTests.render(scene, size: Self.appSize)
        let px = V0354GoldAingArtTests.rgba(image)
        let w = image.width
        let character = try V0354GoldAing3DTests.character(scene)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = renderer.snapshot(atTime: 0, with: Self.appSize, antialiasingMode: .none)
        func pixel(_ local: SCNVector3) -> (Int, Int) {
            let p = renderer.projectPoint(character.convertPosition(local, to: nil))
            return (Int(p.x.rounded()), Int((Self.appSize.height - p.y).rounded()))
        }
        func color(_ local: SCNVector3) -> (L: Double, C: Double, h: Double) {
            let c = V0359Rainbow3DTests.averageColor(px, width: w, at: pixel(local), radius: 2)
            return V0359RainbowArtTests.oklch(c.0, c.1, c.2)
        }
        // 몸 옆구리(얼굴 상자 밖 · 라벨 위) — 초록.
        let flank = color(SCNVector3(0.42, 0.62, 0.30))
        // 라벨 가운데(정면 t ≈ 0.64 → y = 0.849 − 0.64·1.696 ≈ −0.236) — 흰 판(밝고 채도 낮음) 또는 초록 글씨.
        let labelSpot = color(SCNVector3(0.0, -0.30, 0.50))
        // 뚜껑(정수리 위) — 짙은 초록 금속.
        let capSpot = color(SCNVector3(0.09, 0.93, 0.01))
        print(String(format: "[v0374-3d] 옆구리 L %.2f C %.3f h %.0f° · 라벨 L %.2f C %.3f h %.0f° · 뚜껑 L %.2f C %.3f h %.0f°",
                     flank.L, flank.C, flank.h, labelSpot.L, labelSpot.C, labelSpot.h, capSpot.L, capSpot.C, capSpot.h))
        #expect(V0359RainbowArtTests.hueDistance(flank.h, 150) < 35 && flank.C > 0.05, "옆구리가 초록 유리가 아니다(\(flank))")
        #expect(labelSpot.L > 0.6, "라벨 자리가 밝은 판이 아니다(\(labelSpot))")
        #expect(V0359RainbowArtTests.hueDistance(capSpot.h, 150) < 35 && capSpot.L < 0.75, "뚜껑 자리가 짙은 초록이 아니다(\(capSpot))")
        // 기준선: 셰이더를 빼면 같은 옆구리가 라벤더다(위 판정이 헛돌지 않는다).
        let plain = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize, modifiers: .some(nil)))
        let c = V0359Rainbow3DTests.averageColor(plain, width: w, at: pixel(SCNVector3(0.42, 0.62, 0.30)), radius: 2)
        let lavender = V0359RainbowArtTests.oklch(c.0, c.1, c.2)
        #expect(V0359RainbowArtTests.hueDistance(lavender.h, 290) < 35, "기준선: 셰이더 없는 옆구리가 라벤더가 아니다(\(lavender))")
    }

    // MARK: ③ 감은 눈

    @Test("감은 눈(엔진 CGImage 경로): 눈 자리가 초록 유리다 — 라벤더(셰이더 없이 같은 자리)와 색상이 다르고 뜬 눈보다 밝다")
    func closedEyesAreGlass() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.isul)
        let engine = ReactionEngine()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let eye = try V0359Rainbow3DTests.eyePixel(scene, size: Self.appSize)
        let width = Int(Self.appSize.width)
        let awake = V0359Rainbow3DTests.averageColor(V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize)), width: width, at: eye)
        engine.request(.drowsy)
        #expect(engine.state == .sleeping)
        let closed = V0359Rainbow3DTests.averageColor(V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize)), width: width, at: eye)
        let lavender = V0359Rainbow3DTests.averageColor(
            V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize, modifiers: .some(nil))), width: width, at: eye)
        engine.request(.wake)
        let a = V0359RainbowArtTests.oklch(awake.0, awake.1, awake.2)
        let c = V0359RainbowArtTests.oklch(closed.0, closed.1, closed.2)
        let l = V0359RainbowArtTests.oklch(lavender.0, lavender.1, lavender.2)
        print(String(format: "[v0374-3d] 감은 눈 자리 L %.2f C %.3f h %.0f° · 라벤더 h %.0f° · 뜬 눈 L %.2f", c.L, c.C, c.h, l.h, a.L))
        #expect(a.L < 0.5, "기준선: 뜬 눈 자리가 어둡지 않다 — 눈 좌표가 틀렸다")
        #expect(V0359RainbowArtTests.hueDistance(l.h, 290) < 30, "기준선이 라벤더가 아니다(\(l.h)°)")
        #expect(V0359RainbowArtTests.hueDistance(c.h, 150) < 40, "감은 눈 자리 색상 \(c.h)° 가 초록이 아니다")
        #expect(V0359RainbowArtTests.hueDistance(c.h, l.h) > 60, "감은 눈 자리가 라벤더다")
        #expect(c.L > a.L + 0.1, "감은 눈 자리가 뜬 눈만큼 어둡다 — 눈이 안 덮였다")
    }

    @Test("감은 눈(뷰가 있는 GPU 텍스처 경로 — 깜빡임이 쓰는 길): 눈 자리가 초록 유리다")
    func blinkOnGPUTexturePathIsGlass() throws {
        let engine = ReactionEngine()
        let scene = try V0354GoldAing3DTests.scene(Self.isul)
        let view = SCNView(frame: NSRect(origin: .zero, size: NSSize(width: Self.appSize.width / 2, height: Self.appSize.height / 2)))
        view.scene = scene
        view.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        view.antialiasingMode = .none
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: view)
        #expect(engine.hasFaceTextures, "뷰가 있는데 얼굴 GPU 텍스처가 안 섰다")
        let eye = try V0359Rainbow3DTests.eyePixel(scene, size: Self.appSize)
        engine.request(.drowsy)
        #expect(engine.faceDiffuseTextureAssignments > 0, "감은 눈이 GPU 텍스처로 안 바뀌었다")
        let shot = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let px = V0354GoldAingArtTests.rgba(shot)
        let scale = Double(shot.width) / Double(Self.appSize.width)
        let color = V0359Rainbow3DTests.averageColor(px, width: shot.width, at: (Int(Double(eye.0) * scale), Int(Double(eye.1) * scale)))
        let c = V0359RainbowArtTests.oklch(color.0, color.1, color.2)
        print(String(format: "[v0374-3d] GPU 경로 감은 눈: L %.2f C %.3f h %.0f°", c.L, c.C, c.h))
        #expect(V0359RainbowArtTests.hueDistance(c.h, 150) < 40, "GPU 경로 감은 눈 자리가 초록이 아니다(\(c))")
        #expect(c.L > 0.3, "GPU 경로 감은 눈 자리가 눈처럼 어둡다(\(c))")
        engine.request(.wake)
    }

    // MARK: ④ 장식은 몸이 아니다

    @Test("얼굴 탐색은 병뚜껑을 건너뛴다: 졸면 몸 디퓨즈만 감은 눈 판으로 바뀌고 뚜껑 텍스처(512×128 — '큰 CGImage')는 그대로 · isDecor 는 조상으로 가른다")
    func faceSearchSkipsTheCap() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.isul)
        let decor = try #require(Self.decor(scene))
        var capTextures: [(SCNMaterial, CGImage)] = []
        decor.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] {
                if let cg = SleepEyeExplore.cgImage(from: m.diffuse.contents), cg.width >= 256 { capTextures.append((m, cg)) }
            }
        }
        #expect(!capTextures.isEmpty, "기준선: 뚜껑에 '큰 CGImage 디퓨즈'(얼굴로 오인될 판)가 없다 — 이 시험이 헛돈다")
        let body = try V0359Rainbow3DTests.faceMaterial(scene)
        let awake = try #require(SleepEyeExplore.cgImage(from: body.diffuse.contents))
        let engine = ReactionEngine()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        engine.request(.drowsy)
        let asleep = try #require(SleepEyeExplore.cgImage(from: body.diffuse.contents))
        #expect(asleep !== awake, "졸았는데 몸 디퓨즈가 안 바뀌었다 — 얼굴 탐색이 몸을 못 잡았다")
        for (material, image) in capTextures {
            #expect(SleepEyeExplore.cgImage(from: material.diffuse.contents) === image, "뚜껑 텍스처가 감은 눈으로 바뀌었다")
        }
        engine.request(.wake)
        let cap = try #require(decor.childNode(withName: Cap.capNodeName, recursively: false))
        #expect(AingDecor.isDecor(cap) && AingDecor.isDecor(decor))
        #expect(!AingDecor.isDecor(try V0354GoldAing3DTests.character(scene)))
        // 케이크 장식도 같은 판정으로 빠진다(한 판정 — 장식 루트 이름 둘).
        let cake = try #require(V0366CakeMac3DTests.decor(try V0354GoldAing3DTests.scene(CharacterCatalog.builtInCakeChocoAing)))
        #expect(AingDecor.isDecor(cake))
    }

    @Test("몸 클릭: 뚜껑 자리(머리 위)의 hitTest 맞음은 전부 장식이고(몸이 아니다) 몸 가운데는 몸이다 · 엔진은 장식 판정을 AingDecor 로 한다")
    func capHitsAreDecor() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.isul)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = renderer.snapshot(atTime: 0, with: Self.appSize, antialiasingMode: .none)
        let cap = try #require(Self.decor(scene)?.childNode(withName: Cap.capNodeName, recursively: false))
        let (lo, hi) = cap.boundingBox
        let top = cap.convertPosition(SCNVector3((lo.x + hi.x) / 2, hi.y - (hi.y - lo.y) * 0.2, (lo.z + hi.z) / 2), to: nil)
        let p = renderer.projectPoint(top)
        let options: [SCNHitTestOption: Any] = [.rootNode: try V0354GoldAing3DTests.wrapper(scene), .boundingBoxOnly: false, .ignoreHiddenNodes: true]
        let raw = renderer.hitTest(CGPoint(x: p.x, y: p.y), options: options)
        #expect(raw.contains { AingDecor.isDecor($0.node) }, "기준선: 뚜껑 자리의 날 hitTest 가 뚜껑을 안 맞힌다 — 점을 잘못 잡았다")
        #expect(!raw.contains { !AingDecor.isDecor($0.node) }, "뚜껑 자리 hitTest 에 몸이 섞였다 — 머리 위가 아니다")
        let centerPoint = CGPoint(x: Self.appSize.width / 2, y: Self.appSize.height / 2)
        let center = renderer.hitTest(centerPoint, options: options)
        #expect(center.contains { !AingDecor.isDecor($0.node) }, "몸 가운데가 몸이 아니다")
        // 엔진의 판정 함수 그대로(창 없이 — 오프스크린 렌더러를 뷰 자리에): 뚜껑 투영점 = 몸 아님 · 몸 가운데 = 몸(검토 수리).
        let engine = ReactionEngine()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        #expect(!engine.isBodyHit(atViewPoint: CGPoint(x: p.x, y: p.y), renderer: renderer), "엔진이 뚜껑 자리를 몸으로 친다 — 바탕화면 클릭을 먹는다")
        #expect(engine.isBodyHit(atViewPoint: centerPoint, renderer: renderer), "엔진이 몸 가운데를 몸이 아니라 한다")
        // 엔진의 판정 줄이 이 함수를 쓴다(소스 계약 — 주석을 걷고 본다).
        let reactions = V0351IfConfig.strippingComments(try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayReactions.swift"))
        #expect(reactions.contains("return hits.contains { !AingDecor.isDecor($0.node) }"), "몸 클릭 판정이 AingDecor 를 안 쓴다")
        #expect(reactions.contains("guard !AingDecor.isDecor(node) else { return }"), "얼굴 탐색이 AingDecor 를 안 쓴다")
        #expect(!reactions.contains("CakeAingFinish.isDecor(") && !reactions.contains("CakeAingFinish.bodyBoundingBox("),
                "케이크 전용 판정이 남았다 — 이슬 뚜껑이 몸으로 친다")
    }

    @Test("리액션 진폭 · 클릭 프리체크 상자는 몸만 잰다: 이슬의 몸 상자 = 아잉 몸 상자(내리지 않는다) · 뚜껑은 상자를 키운다(기준선)")
    func bodyBoundingBoxIgnoresTheCap() throws {
        let aing = try V0354GoldAing3DTests.wrapper(try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing))
        let a = aing.boundingBox
        let wrapper = try V0354GoldAing3DTests.wrapper(try V0354GoldAing3DTests.scene(Self.isul))
        let whole = wrapper.boundingBox
        let body = AingDecor.bodyBoundingBox(of: wrapper)
        #expect(whole.max.y > body.max.y + 0.1, "기준선: 뚜껑이 상자를 안 키운다(\(whole.max.y) vs \(body.max.y)) — 시험이 헛돈다")
        #expect(abs(body.max.y - a.max.y) < 1e-3 && abs(body.min.y - a.min.y) < 1e-3 && abs(body.max.x - a.max.x) < 1e-3,
                "이슬 몸 상자 \(body.min.y)…\(body.max.y) ≠ 아잉 \(a.min.y)…\(a.max.y)")
        // 장식 없는 캐릭터는 SceneKit 값 그대로 · 케이크 쪽 옛 함수와 같은 답.
        let viaHelper = AingDecor.bodyBoundingBox(of: aing)
        #expect(viaHelper.min.x == a.min.x && viaHelper.max.y == a.max.y)
        let choco = try V0354GoldAing3DTests.wrapper(try V0354GoldAing3DTests.scene(CharacterCatalog.builtInCakeChocoAing))
        let old = CakeAingFinish.bodyBoundingBox(of: choco), new = AingDecor.bodyBoundingBox(of: choco)
        #expect(old.min.y == new.min.y && old.max.y == new.max.y && old.max.x == new.max.x, "케이크 몸 상자가 바뀌었다")
    }

    // MARK: ⑤ 프레이밍

    @Test("프레이밍: 뚜껑 위 끝이 부유 꼭대기(+0.07)에서도 프레임 위 2% 안쪽 — 생성기 실측(0 → 0.095 · +0.07 → 0.071)과 같은 카메라 · 요 ±40° · 아잉 구도 그대로")
    func framingKeepsTheCapInside() throws {
        let aing = try V0366CakeMac3DTests.frame(CharacterCatalog.builtInAing, float: true)
        let rest = try V0366CakeMac3DTests.frame(Self.isul, float: false)
        let up = try V0366CakeMac3DTests.frame(Self.isul, float: true)
        print(String(format: "[v0374-3d] 이슬 위 여백: 쉼 %.3f · 부유 꼭대기 %.3f · 쉼 아래 %.3f(아잉 부유 꼭대기 위 %.3f)", rest.top, up.top, rest.bottom, aing.top))
        #expect(abs(rest.top - 0.095) < 0.01 && abs(up.top - 0.071) < 0.01,
                "앱 카메라가 생성기 실측과 갈렸다(쉼 \(rest.top) · 부유 \(up.top)) — 카메라 식이 바뀌었으면 생성기 appCamera 도 같이")
        for yaw in [0.0, 40.0, -40.0] {
            let f = try V0366CakeMac3DTests.frame(Self.isul, float: true, yawDegrees: yaw)
            #expect(f.top >= 0.02, "요 \(yaw)°: 부유 꼭대기에서 뚜껑 위 끝 여유 \(f.top) — 잘린다")
        }
        #expect(rest.bottom >= 0.2, "몸 아래 끝 여유 \(rest.bottom)")
        // 아잉 구도는 그대로(V0366 실측 — 부유 꼭대기 위 0.124 @ 280×340).
        #expect(abs(aing.top - 0.124) < 0.006, "아잉 구도가 바뀌었다(\(aing.top))")
        // 뚜껑 꼭대기 상수로도: 부유 꼭대기에서 투영하면 프레임 위 3% 안쪽이다.
        let scene = try V0354GoldAing3DTests.scene(Self.isul)
        let character = try V0354GoldAing3DTests.character(scene)
        character.simdPosition.y += 0.07
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = renderer.snapshot(atTime: 0, with: Self.appSize, antialiasingMode: .none)
        let tip = character.convertPosition(SCNVector3(Cap.crownX, Float(Cap.capTopY), Cap.crownZ), to: nil)
        let fromTop = (Self.appSize.height - renderer.projectPoint(tip).y) / Self.appSize.height
        #expect(fromTop > 0.03, "뚜껑 꼭대기(상수)가 프레임 위 가장자리에 붙는다(\(fromTop))")
    }

    // MARK: ⑥ 엔진 · 울트라 교체

    @Test("엔진은 이슬을 가른다 — 아잉 → 이슬 교체(울트라 경로)에 뚜껑 · 셰이더 · 라벨 · 표식이 따라오고, 이슬 → 초코 → 원복 왕복도 맞다")
    func engineSwapsIsul() throws {
        do {
            let engine = ReactionEngine()
            let scene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
            engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
            #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
            let stashed = try #require(engine.swapCharacter(to: Self.isul, in: scene))
            #expect(engine.currentCharacterID == CharacterCatalog.isulAingID, "이슬로 갈아입었는데 \(engine.currentCharacterID)")
            let material = try V0359Rainbow3DTests.faceMaterial(scene)
            #expect(material.shaderModifiers?[.fragment] == IsulAingFinish.bodyShaderModifiers[.fragment])
            #expect(material.value(forKey: Body.labelMapKey) is SCNMaterialProperty && material.value(forKey: Body.shadeMapKey) is SCNMaterialProperty)
            #expect(Self.decor(scene) != nil, "교체로 선 이슬에 뚜껑이 없다")
            #expect(try V0354GoldAing3DTests.character(scene).simdPosition == .zero)
            #expect(engine.restoreCharacterNode(stashed))
            #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
            #expect(Self.decor(scene) == nil, "아잉으로 돌아왔는데 뚜껑이 남았다")
        }
        do {
            let engine = ReactionEngine()
            let scene = try V0354GoldAing3DTests.scene(Self.isul)
            engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
            #expect(engine.currentCharacterID == CharacterCatalog.isulAingID)
            let stashed = try #require(engine.swapCharacter(to: CharacterCatalog.builtInCakeChocoAing, in: scene))
            #expect(engine.currentCharacterID == CharacterCatalog.cakeChocoAingID)
            #expect(Self.decor(scene) == nil && V0366CakeMac3DTests.decor(scene) != nil, "초코로 갈아입었는데 뚜껑이 남았거나 케이크 장식이 없다")
            #expect(engine.restoreCharacterNode(stashed))
            #expect(engine.currentCharacterID == CharacterCatalog.isulAingID)
            #expect(Self.decor(scene) != nil)
            #expect(try V0359Rainbow3DTests.faceMaterial(scene).shaderModifiers?[.fragment] == IsulAingFinish.bodyShaderModifiers[.fragment])
        }
    }

    // MARK: ⑦ 그릴 수 있다 → 능력 번호 5

    @Test("그릴 수 있다: 번들 그대로 이슬이 든다(초상 두 장 + 라벨 폴백 + 밝기 맵) · 하나만 빠져도 못 그린다 · 능력 번호 5 · 초상 URL")
    func drawableAndProtocolFive() throws {
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(CharacterCatalog.isulAingID), "\(drawable)")
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.isulProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) == 5)
        let store = V0317ShopTests.plainStore()
        #expect(store.shopProtocolVersion == 5 && store.supportsCakeGift)
        #expect(IsulAingFinish.isDrawable())
        #expect(IsulAingFinish.requiredResourceNames() == ["aing_isul-label", "aing_isul-neutral", "aing_isul-negative", "aing_rainbow-shade"])
        for missing in IsulAingFinish.requiredResourceNames() {
            #expect(!IsulAingFinish.isDrawable { $0 != missing }, "\(missing) 가 빠져도 그릴 수 있다고 한다")
        }
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.isulAingID, mood: .neutral)?.lastPathComponent == "aing_isul-neutral.png")
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.isulAingID, mood: .negative)?.lastPathComponent == "aing_isul-negative.png")
        #expect(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.isulAingID)?.size.width == 192)
        // 이슬이 빠지면 4(누적 — 케이크까지).
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != CharacterCatalog.isulAingID }) == ShopWire.cakeProtocol)
    }

    @Test("아바타: 이슬은 케이크와 같은 자르기(몸 상자 + 둘레 8%) — 얼굴이 아잉 변형(케이크 · 금 · 아잉)과 같은 눈금 · 알파 상자로 조이면 얼굴이 커진다(기준선)")
    func avatarFramesTheBodyLikeTheOtherVariants() throws {
        #expect(AppUserAvatarArt.framing(characterID: CharacterCatalog.isulAingID) == .cakeBodyFramed)
        #expect(AppUserAvatarArt.knownIDs.contains(CharacterCatalog.isulAingID))
        let art = try #require(AppUserAvatarArt.portrait(characterID: CharacterCatalog.isulAingID))
        let url = try #require(CheckMascotAssets.portraitURL(for: .neutral, characterID: CharacterCatalog.isulAingID))
        let imageSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let raw = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let alphaBox = CharacterCardArt.tightened(raw)
        // 얼굴 눈금 = 26pt 원 안에서 초상 1px 이 몇 pt 인가(`portraitBox` 가 정한 폭 ÷ 그림 폭). 같은 2D 몸(0.88배)이라 이 값이 같으면 얼굴 크기가 같다.
        func scale(_ image: CGImage) -> Double {
            Double(AppUserAvatarArt.portraitBox(diameter: 26, artSize: CGSize(width: image.width, height: image.height)).width) / Double(image.width)
        }
        let cake = try #require(AppUserAvatarArt.portrait(characterID: CharacterCatalog.cakeChocoAingID))
        let gold = try #require(AppUserAvatarArt.portrait(characterID: CharacterCatalog.goldAingID))
        print(String(format: "[v0374-3d] 아바타 상자 이슬 %d×%d(눈금 %.4f) · 초코 %d×%d(%.4f) · 금 %d×%d(%.4f) · 이슬 알파 상자 %d×%d(%.4f)",
                     art.width, art.height, scale(art), cake.width, cake.height, scale(cake), gold.width, gold.height, scale(gold),
                     alphaBox.width, alphaBox.height, scale(alphaBox)))
        #expect(abs(scale(art) / scale(cake) - 1) < 0.03 && abs(scale(art) / scale(gold) - 1) < 0.03,
                "이슬 얼굴 눈금 \(scale(art)) 이 케이크 \(scale(cake)) · 금 \(scale(gold)) 과 갈렸다")
        // 기준선: 알파 상자(뚜껑까지)로 조이면 얼굴이 5% 넘게 커진다 — 이슬 몸이 0.88배 초상이라 둘레 8% 를 더해야 아잉 변형과 같은 눈금이다.
        #expect(scale(alphaBox) > scale(art) * 1.05, "기준선: 알파 상자 눈금 \(scale(alphaBox)) 이 몸 상자 눈금 \(scale(art)) 과 같다 — 자르기가 할 일이 없다")
    }

    // MARK: ⑧ 그림 저장소(IsulArt)

    @Test("그림 판정(순수): 라벨은 가로로 긴 판 · 초상은 정사각 128px 이상 · 응답 → 할 일(200 바꿈 · 304 그대로 · 404 되돌림 · 그 밖 그대로 · 못 쓰는 그림 그대로)")
    func artVerdicts() throws {
        typealias A = IsulArt
        #expect(A.isAcceptable(pixelWidth: 1200, pixelHeight: 551, kind: .label))
        #expect(A.isAcceptable(pixelWidth: 600, pixelHeight: 300, kind: .label))
        #expect(!A.isAcceptable(pixelWidth: 551, pixelHeight: 1200, kind: .label), "세로로 긴 라벨")
        #expect(!A.isAcceptable(pixelWidth: 1200, pixelHeight: 200, kind: .label), "너무 납작한 라벨(6:1)")
        #expect(!A.isAcceptable(pixelWidth: 200, pixelHeight: 100, kind: .label), "너무 작은 라벨")
        for kind in [A.Kind.neutral, .negative] {
            #expect(A.isAcceptable(pixelWidth: 192, pixelHeight: 192, kind: kind))
            #expect(A.isAcceptable(pixelWidth: 384, pixelHeight: 384, kind: kind))
            #expect(!A.isAcceptable(pixelWidth: 96, pixelHeight: 96, kind: kind), "128px 밑")
            #expect(!A.isAcceptable(pixelWidth: 192, pixelHeight: 180, kind: kind), "정사각이 아니다")
            #expect(!A.isAcceptable(pixelWidth: 1200, pixelHeight: 551, kind: kind), "라벨을 초상 자리에")
        }
        let label = try Data(contentsOf: try #require(A.bundledURL(.label)))
        let portrait = try Data(contentsOf: try #require(A.bundledURL(.neutral)))
        #expect(A.outcome(status: 200, data: label, kind: .label) == .replace)
        #expect(A.outcome(status: 200, data: portrait, kind: .neutral) == .replace)
        #expect(A.outcome(status: 200, data: portrait, kind: .label) == .keep, "초상을 라벨로 받으면 버린다")
        #expect(A.outcome(status: 200, data: Data("not a png".utf8), kind: .neutral) == .keep)
        #expect(A.outcome(status: 304, data: Data(), kind: .label) == .keep)
        #expect(A.outcome(status: 404, data: Data(), kind: .negative) == .revert)
        // 없는 개체 — Supabase Storage 는 버전 · 게이트웨이에 따라 400 + 본문 not_found 로 준다(`deleteAvatarFile` 과 같은 판정).
        let notFound = Data(#"{"statusCode":"404","error":"not_found","message":"Object not found"}"#.utf8)
        #expect(A.outcome(status: 400, data: notFound, kind: .label) == .revert, "400 + not_found 본문을 없는 개체로 안 읽었다")
        #expect(A.outcome(status: 400, data: Data(#"{"error":"not_found"}"#.utf8), kind: .neutral) == .revert)
        #expect(A.outcome(status: 400, data: Data(#"{"statusCode":"404"}"#.utf8), kind: .negative) == .revert)
        // 본문 없는 400 · not_found 표식 없는 400 = 잘못된 요청 — 그대로.
        #expect(A.outcome(status: 400, data: Data(), kind: .label) == .keep, "본문 없는 400 을 되돌렸다")
        #expect(A.outcome(status: 400, data: Data(#"{"statusCode":"400","error":"InvalidRequest"}"#.utf8), kind: .label) == .keep)
        // 표식은 400 에서만 본다(403 · 5xx 본문에 같은 글자가 섞여도 캐시를 안 지운다).
        for status in [401, 403, 500, 503] {
            #expect(A.outcome(status: status, data: label, kind: .label) == .keep, "\(status)")
            #expect(A.outcome(status: status, data: notFound, kind: .label) == .keep, "\(status) + not_found")
        }
    }

    @Test("그림 위치: Storage game-art/isul/<이름>.png · 캐시 Caches/check.game-art/isul/<이름>.png · 번들 폴백 세 장이 실재하고 쓸 만하다 · 시험 중엔 캐시도 네트워크도 안 탄다")
    func artLocations() throws {
        for kind in IsulArt.Kind.allCases {
            #expect(IsulArt.remoteURL(kind).absoluteString
                    == "\(SupabaseConfig.projectURL.absoluteString)/storage/v1/object/public/game-art/isul/\(kind.rawValue).png")
            #expect(IsulArt.shared.cacheFile(kind).path.hasSuffix("/Caches/check.game-art/isul/\(kind.rawValue).png"), "\(IsulArt.shared.cacheFile(kind).path)")
            let bundled = try #require(IsulArt.bundledURL(kind), "\(kind) 번들 폴백이 없다")
            #expect(bundled.lastPathComponent == "aing_isul-\(kind.rawValue).png")
            #expect(IsulArt.isAcceptable(data: try Data(contentsOf: bundled), kind: kind), "\(kind) 번들 폴백이 판정을 못 지난다")
            // 시험 중 공용 저장소는 번들을 준다(사용자 디스크 캐시를 읽지 않는다).
            #expect(IsulArt.shared.url(kind) == bundled)
        }
        #expect(!IsulArt.shared.readsCache && !IsulArt.shared.usesNetwork, "시험 중인데 공용 저장소가 캐시 · 네트워크를 탄다")
        #expect(IsulArt.shared.portraitURL(.negative) == IsulArt.bundledURL(.negative))
    }

    /// 시험 전용 캐시 폴더(지우지 않는다 — 시각이 붙은 새 이름).
    static func scratchCache(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v0374-isul-art-\(label)-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("디스크 캐시 → 번들: 쓸 만한 캐시는 그 파일 · 못 쓰는 캐시는 번들 · 받아들이기 200(바꿈 · 메타) → 304(그대로) → 404(지우고 번들) · 조건부 머리는 캐시가 있을 때만")
    func cacheThenBundleRoundTrip() throws {
        let dir = try Self.scratchCache("roundtrip")
        let art = IsulArt(cacheDirectory: dir, readsCache: true, usesNetwork: false)
        let bundledLabel = try #require(IsulArt.bundledURL(.label))
        let bundledNeutral = try #require(IsulArt.bundledURL(.neutral))
        // 캐시 없음 → 번들 · 조건부 머리 없음.
        #expect(art.url(.label) == bundledLabel)
        #expect(art.conditionalRequest(.label).value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(art.conditionalRequest(.label).url == IsulArt.remoteURL(.label))
        // 못 쓰는 캐시(초상 크기 그림을 라벨 자리에) → 번들.
        let other = IsulArt(cacheDirectory: dir, readsCache: true, usesNetwork: false)
        try Data(contentsOf: bundledNeutral).write(to: other.cacheFile(.label))
        #expect(other.url(.label) == bundledLabel, "못 쓰는 캐시를 썼다")
        // 못 쓰는 캐시엔 조건부 머리를 안 단다(메타가 남아 있어도) — 달면 304 를 받아 번들에 갇힌다(검토 수리).
        try Data(#"{"etag":"\"v1\"","last_modified":"Sun, 02 Nov 2026 00:00:00 GMT"}"#.utf8).write(to: other.metaFile(.label))
        #expect(other.conditionalRequest(.label).value(forHTTPHeaderField: "If-None-Match") == nil, "못 쓰는 캐시인데 If-None-Match 를 단다")
        #expect(other.conditionalRequest(.label).value(forHTTPHeaderField: "If-Modified-Since") == nil, "못 쓰는 캐시인데 If-Modified-Since 를 단다")
        // 받아들이기 200 — 새 라벨(번들 라벨 바이트 · 캐시에 씀) → 캐시 파일 · 메타.
        let labelData = try Data(contentsOf: bundledLabel)
        let before = art.labelImage()
        #expect(art.absorb(kind: .label, status: 200, data: labelData, etag: "\"v2\"", lastModified: "Mon, 03 Nov 2026 00:00:00 GMT") == .replace)
        #expect(art.url(.label) == art.cacheFile(.label), "바꾼 뒤에도 번들을 준다")
        #expect(try Data(contentsOf: art.cacheFile(.label)) == labelData)
        let after = try #require(art.labelImage())
        #expect(after !== before, "라벨을 바꿨는데 옛 그림 객체를 준다")
        let request = art.conditionalRequest(.label)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"v2\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Mon, 03 Nov 2026 00:00:00 GMT")
        // 304 · 5xx · 못 쓰는 200 — 그대로.
        #expect(art.absorb(kind: .label, status: 304, data: Data()) == .keep)
        #expect(art.absorb(kind: .label, status: 503, data: Data()) == .keep)
        #expect(art.absorb(kind: .label, status: 200, data: Data("x".utf8)) == .keep)
        #expect(art.url(.label) == art.cacheFile(.label) && art.labelImage() === after, "그대로여야 할 응답이 그림을 바꿨다")
        // 404 — 캐시 · 메타를 지우고 번들로.
        #expect(art.absorb(kind: .label, status: 404, data: Data()) == .revert)
        #expect(!FileManager.default.fileExists(atPath: art.cacheFile(.label).path) && !FileManager.default.fileExists(atPath: art.metaFile(.label).path))
        #expect(art.url(.label) == bundledLabel)
        #expect(art.conditionalRequest(.label).value(forHTTPHeaderField: "If-None-Match") == nil, "캐시가 없는데 조건부 머리를 단다 — 304 에 갇힌다")
        // 초상도 같은 길(정사각 판정).
        #expect(art.absorb(kind: .neutral, status: 200, data: try Data(contentsOf: bundledNeutral)) == .replace)
        #expect(art.portraitURL(.neutral) == art.cacheFile(.neutral) && art.portraitURL(.negative) == IsulArt.bundledURL(.negative))
        // 시험 중 공용 저장소가 고른 파일은 3D 마감 · 초상 둘 다 같은 저장소를 탄다(소스 계약 — 주석을 걷고 본다).
        let bridge = V0351IfConfig.strippingComments(try Self.source("Sources/check/CheckCoreBridge.swift"))
        #expect(bridge.contains("IsulArt.current.portraitURL(mood)"), "초상 조회가 그림 저장소를 안 탄다")
        let finish = V0351IfConfig.strippingComments(try Self.source("Sources/check/IsulAingFinish.swift"))
        #expect(finish.contains("let label = IsulArt.shared.labelImage()"), "3D 라벨이 그림 저장소를 안 탄다")
    }

    @Test("라벨 풀기: 고른 캐시 파일이 그 뒤 깨졌으면(풀리지 않는다) 번들로 한 번 더 푼다 — 라벨 없는 병이 되지 않는다(검토 수리)")
    func labelFallsBackToTheBundleWhenTheCacheWontDecode() throws {
        let dir = try Self.scratchCache("label-fallback")
        let art = IsulArt(cacheDirectory: dir, readsCache: true, usesNetwork: false)
        let bundledLabel = try #require(IsulArt.bundledURL(.label))
        try Data(contentsOf: bundledLabel).write(to: art.cacheFile(.label))
        #expect(art.url(.label) == art.cacheFile(.label), "전제: 쓸 만한 캐시를 고르지 않았다")
        // 고른 뒤 캐시 파일이 깨졌다(다른 프로세스 · 디스크) — 기억한 주소는 캐시 그대로다.
        try Data("not a png".utf8).write(to: art.cacheFile(.label))
        let image = try #require(art.labelImage(), "캐시를 못 풀자 라벨 없이 섰다 — 번들로 다시 풀지 않았다")
        let bundled = try #require(CGImageSourceCreateWithURL(bundledLabel as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == bundled.width && image.height == bundled.height, "번들 라벨이 아니다(\(image.width)×\(image.height))")
    }

    /// 관찰 바뀜 횟수(onChange 는 어느 스레드에서든 온다).
    final class RedrawCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func add() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    /// 번들 초상 PNG 의 왼쪽 위 한 점만 빨강으로 칠한 PNG(사람 눈엔 같은 그림 — 시험은 그 점으로 새 그림을 가른다).
    static func markedPortrait(_ data: Data) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        // RGBA 버퍼에 그리고 버퍼 0행 0열(= 그림의 왼쪽 위)을 불투명 빨강으로 — 표현(rep)의 색공간에 기대지 않는다.
        let w = image.width, h = image.height
        let context = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        pixels[0] = 255; pixels[1] = 0; pixels[2] = 0; pixels[3] = 255
        let marked = try #require(context.makeImage())
        let out = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, marked, nil)
        #expect(CGImageDestinationFinalize(destination))
        return out as Data
    }

    static func isRedCorner(_ image: NSImage?) -> Bool {
        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let color = NSBitmapImageRep(cgImage: cg).colorAt(x: 0, y: 0), color.type == .componentBased,
              color.numberOfComponents >= 3 else { return false }
        // 표현의 RGB 성분 그대로(sRGB 로 옮기면 색공간 변환이 초록을 0.15 까지 올린다 — 옛 그림의 구석은 투명 0 0 0 0 이다).
        return color.alphaComponent > 0.9 && color.redComponent > 0.9 && color.greenComponent < 0.3 && color.blueComponent < 0.3
    }

    @Test("받은 초상은 곧바로 화면으로: 초상 조회가 타는 저장소에 200 을 흡수하면 관찰 값이 올라(그린 화면이 다시 그린다) 메뉴바 · 헤더 · 카드 · 아바타 캐시가 새 그림을 준다(검토 수리)")
    func absorbedPortraitReachesTheDrawnCaches() async throws {
        let dir = try Self.scratchCache("redraw")
        let art = IsulArt(cacheDirectory: dir, readsCache: true, usesNetwork: false)
        let id = CharacterCatalog.isulAingID
        let marked = try Self.markedPortrait(try Data(contentsOf: try #require(IsulArt.bundledURL(.neutral))))
        #expect(IsulArt.isAcceptable(data: marked, kind: .neutral), "전제: 칠한 초상이 판정을 못 지난다")
        try await IsulArt.$testOverride.withValue(art) {
            #expect(IsulArt.current === art, "전제: 따로 저장소가 안 끼워졌다")
            IsulArt.forgetDrawnPortraits()
            let before = CheckMascotAssets.image(for: .neutral, characterID: id)
            #expect(before != nil && !Self.isRedCorner(before), "기준선: 흡수 전부터 새 그림이다")
            let cardBefore = try #require(CharacterCardArt.image(characterID: id))
            #expect(AppUserAvatarArt.portrait(characterID: id) != nil)
            // 그린 화면이 관찰하는 값 — 초상을 그리는 함수를 부르는 동안 읽힌다.
            let redraws = RedrawCount()
            withObservationTracking {
                _ = CheckMascotAssets.menuBarImage(for: .neutral, characterID: id)
            } onChange: { redraws.add() }
            let revision = IsulArtRevision.shared.count

            #expect(art.absorb(kind: .neutral, status: 200, data: marked) == .replace)
            #expect(await V0354CoreStub.waitUntil { IsulArtRevision.shared.count > revision }, "관찰 값이 안 올랐다 — 그린 화면이 다시 안 그린다")
            #expect(redraws.value == 1, "메뉴바 초상을 그린 화면이 바뀜을 못 들었다(\(redraws.value))")
            #expect(Self.isRedCorner(CheckMascotAssets.image(for: .neutral, characterID: id)), "헤더 초상이 옛 그림이다 — 캐시를 안 비웠다")
            #expect(Self.isRedCorner(CheckMascotAssets.menuBarImage(for: .neutral, characterID: id)), "메뉴바 초상이 옛 그림이다")
            let cardAfter = try #require(CharacterCardArt.image(characterID: id))
            #expect(cardAfter !== cardBefore, "카드 그림이 옛 그림 객체다 — CharacterCardArt 의 이슬 몫을 안 비웠다")
            #expect(cardAfter.width > cardBefore.width || cardAfter.height > cardBefore.height,
                    "카드 그림이 새 초상(구석 한 점까지 조인 상자)이 아니다 — \(cardBefore.width)×\(cardBefore.height) → \(cardAfter.width)×\(cardAfter.height)")
            // 다른 캐릭터는 이 값에 묶이지 않는다.
            let aingRedraws = RedrawCount()
            withObservationTracking {
                _ = CheckMascotAssets.menuBarImage(for: .neutral, characterID: CharacterCatalog.builtInAingID)
            } onChange: { aingRedraws.add() }
            IsulArtRevision.shared.bump()
            #expect(aingRedraws.value == 0, "아잉 초상을 그린 화면까지 이슬 그림 값에 묶였다")
        }
        // 뒷정리: 시험 그림을 쥔 앱 캐시를 비운다(공용 저장소 = 번들로 다시 읽는다).
        IsulArt.forgetDrawnPortraits()
        #expect(!Self.isRedCorner(CheckMascotAssets.image(for: .neutral, characterID: id)), "뒷정리 뒤에도 시험 그림이 남았다")
    }

    @Test("병뚜껑 미리 굽기: 케이크와 같은 자리(prewarmDecorTemplates)가 메인 밖에서 한 번 굽는다 — 그 뒤 첫 이슬 씬은 굽지 않는다(검토 수리)")
    func capIsPrewarmedOffMain() async throws {
        IsulAingFinish.resetDecorCacheForTesting()
        let work = CakeAingFinish.prewarmDecorTemplates()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in work.notify(queue: .main) { done.resume() } }
        #expect(IsulAingFinish.decorBuildCountForTesting == 1 && IsulAingFinish.decorBuildsOnMainForTesting == [false],
                "미리 굽기가 병뚜껑을 메인 밖에서 한 번 굽지 않았다 — \(IsulAingFinish.decorBuildsOnMainForTesting)")
        let decor = try #require(IsulAingFinish.decorNode())
        #expect(decor.name == IsulAingFinish.decorNodeName)
        #expect(IsulAingFinish.decorBuildCountForTesting == 1, "미리 구웠는데 첫 씬이 메인에서 또 구웠다")
    }

    // MARK: ⑨ 증거 스틸(사람이 보는 그림 — 기본 실행에서는 꺼져 있다)

    static func write(_ image: CGImage, _ name: String) throws {
        let dir = URL(fileURLWithPath: try #require(Self.evidenceDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    @Test("증거: 앱 구도 3D(정면 · 3/4 · 감은 눈 · 부유 꼭대기) · 울트라 945² · 아바타 · 상점 초상", .enabled(if: evidenceDirectory != nil))
    func writeEvidence() throws {
        let dark = (28.0 / 255, 28.0 / 255, 30.0 / 255)
        let light = (0.96, 0.96, 0.97)
        var tiles: [CGImage] = []
        for (label, yaw, sleep, float) in [("front", 0.0, false, false), ("three-quarter", 35.0, false, false),
                                           ("closed", 0.0, true, false), ("float-top", 0.0, false, true)] {
            let scene = try V0354GoldAing3DTests.scene(Self.isul)
            let engine = ReactionEngine()
            engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
            try V0355GoldHaloYawTests.facing(scene).eulerAngles = SCNVector3(0, CGFloat(yaw * .pi / 180), 0)
            if sleep { engine.request(.drowsy) }
            if float { try V0354GoldAing3DTests.character(scene).simdPosition.y += 0.07 }
            let raw = try V0359Rainbow3DTests.render(scene, size: CGSize(width: 560, height: 680))
            let tile = try V0359Rainbow3DTests.onBackground(raw, dark)
            try Self.write(tile, "aing_isul-3d-\(label).png")
            try Self.write(try V0359Rainbow3DTests.onBackground(raw, light), "aing_isul-3d-\(label)-light.png")
            tiles.append(tile)
        }
        let w = 560, h = 680
        let ctx = try #require(CGContext(data: nil, width: w * tiles.count + (tiles.count - 1) * 8, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: h))
        for (i, tile) in tiles.enumerated() { ctx.draw(tile, in: CGRect(x: i * (w + 8), y: 0, width: w, height: h)) }
        try Self.write(try #require(ctx.makeImage()), "sheet-3d-aing_isul.png")
        // 울트라 크기(945²) — 부유 꼭대기.
        let scene = try V0354GoldAing3DTests.scene(Self.isul)
        try V0354GoldAing3DTests.character(scene).simdPosition.y += 0.07
        try Self.write(try V0359Rainbow3DTests.onBackground(try V0359Rainbow3DTests.render(scene, size: CGSize(width: 945, height: 945)), dark),
                       "aing_isul-ultra945-float-top.png")
        // 아바타(26pt 원 · @4x 104px)와 상점 초상(카드 그림 · 192²) — 이슬 · 초코 · 금 나란히.
        let ids = [CharacterCatalog.isulAingID, CharacterCatalog.cakeChocoAingID, CharacterCatalog.goldAingID, CharacterCatalog.builtInAingID]
        let d = 104, gap = 16
        let avatar = try #require(CGContext(data: nil, width: ids.count * (d + gap) + gap, height: d + 2 * gap, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        avatar.setFillColor(CGColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: 1))
        avatar.fill(CGRect(x: 0, y: 0, width: avatar.width, height: avatar.height))
        for (i, id) in ids.enumerated() {
            let art = try #require(AppUserAvatarArt.portrait(characterID: id), "\(id) 아바타 없음")
            let box = AppUserAvatarArt.portraitBox(diameter: CGFloat(d), artSize: CGSize(width: art.width, height: art.height))
            let cx = CGFloat(gap + i * (d + gap)) + CGFloat(d) / 2, cy = CGFloat(gap) + CGFloat(d) / 2
            avatar.saveGState()
            avatar.addEllipse(in: CGRect(x: cx - CGFloat(d) / 2, y: cy - CGFloat(d) / 2, width: CGFloat(d), height: CGFloat(d)))
            avatar.clip()
            avatar.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
            avatar.fill(CGRect(x: cx - CGFloat(d) / 2, y: cy - CGFloat(d) / 2, width: CGFloat(d), height: CGFloat(d)))
            // offsetY 는 SwiftUI(아래로 +) — CG(위로 +)에선 부호를 뒤집는다.
            avatar.draw(art, in: CGRect(x: cx - box.width / 2, y: cy - box.height / 2 - box.offsetY, width: box.width, height: box.height))
            avatar.restoreGState()
        }
        try Self.write(try #require(avatar.makeImage()), "avatar-26pt@4x-isul-choco-gold-aing.png")
        let shop = try #require(CGContext(data: nil, width: ids.count * (192 + gap) + gap, height: 192 + 2 * gap, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        shop.setFillColor(CGColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: 1))
        shop.fill(CGRect(x: 0, y: 0, width: shop.width, height: shop.height))
        for (i, id) in ids.enumerated() {
            let card = try #require(CharacterCardArt.image(characterID: id), "\(id) 카드 그림 없음")
            let scale = min(192 / CGFloat(card.width), 192 / CGFloat(card.height))
            let cw = CGFloat(card.width) * scale, ch = CGFloat(card.height) * scale
            shop.draw(card, in: CGRect(x: CGFloat(gap + i * (192 + gap)) + (192 - cw) / 2, y: CGFloat(gap), width: cw, height: ch))
        }
        try Self.write(try #require(shop.makeImage()), "shop-card-isul-choco-gold-aing.png")
        for mood in [CheckMascotAssets.Mood.neutral, .negative] {
            let url = try #require(CheckMascotAssets.portraitURL(for: mood, characterID: CharacterCatalog.isulAingID))
            let imageSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let raw = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            try Self.write(try V0359Rainbow3DTests.onBackground(raw, light), "portrait-\(url.lastPathComponent)")
        }
    }
}
