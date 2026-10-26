import AppKit
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// v0.3.66 — 케이크 아잉이 3D(맥). 실제 앱 씬(`CheckCharacter3DScene.makeScene` · 교체 경로 · 엔진)을 오프스크린으로 그려 **결과**를 잰다:
//  ① 생성기 사본: `CakeAingFinish` 의 몸 셰이더 · 장식 구획이 `scripts/make-cake-aing.swift` 와 글자 그대로다(주석을 걷고 맞댄다) · 상수가 같다 ·
//     장식 불꽃 끝이 생성기 상수와 같다(앱이 만든 장식으로 다시 잰다).
//  ② 마감이 선다: 얼굴 재질 = 무지개와 같은 합성 디퓨즈 + 케이크 몸 셰이더(초코는 ckShadeMap) · 몸 메시에 `check.cakeDecor` · 표식 · 내림.
//     아잉 · 황금 · 무지개에는 없다(기준선).
//  ③ 감은 눈(엔진 CGImage 경로 · 뷰가 있는 GPU 텍스처 경로)에서도 눈 자리가 케이크 색이다 — 라벤더가 아니다.
//  ④ 장식은 몸이 아니다: 얼굴 탐색이 장식 재질을 안 잡고 · 몸 클릭 판정이 장식 맞음을 뺀다(장식 위 점은 몸이 아니다 — 기준선: 날 hitTest 는 장식을 맞힌다).
//  ⑤ 프레이밍: 초코 빛 번짐 위 끝이 부유 꼭대기에서도 프레임 안(≥ 2%) · 몸 아래 끝도 안 · 내리지 않으면 잘린다(기준선) · 다른 캐릭터 구도는 그대로.
//  ⑥ 울트라 교체가 아잉 · 딸기 · 초코를 가르고 · 리액션 진폭은 몸만 잰다.
//  ⑦ 그릴 수 있다 → 능력 번호 4.
// 증거 PNG: `CHECK_V0366_MAC_EVIDENCE_DIR=<폴더>` 를 주면 앱 구도 스틸을 떨군다(창 없음).

@MainActor
@Suite struct V0366CakeMac3DTests {
    static let strawberry = CharacterCatalog.builtInCakeStrawberryAing
    static let choco = CharacterCatalog.builtInCakeChocoAing
    static let cakes = [strawberry, choco]
    static let appSize = CGSize(width: 280, height: 340)
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_V0366_MAC_EVIDENCE_DIR"]

    // MARK: 도구

    static func kind(_ manifest: CharacterManifest) throws -> CakeAingFinish.Kind {
        try #require(CakeAingFinish.Kind(characterID: manifest.id))
    }

    static func decor(_ scene: SCNScene) -> SCNNode? {
        scene.rootNode.childNode(withName: CakeAingFinish.cakeDecorNodeName, recursively: true)
    }

    /// 알파 상자(좌상단 원점 픽셀 — x0, x1, y0, y1).
    static func alphaBox(_ image: CGImage, threshold: UInt8 = 8) -> (x0: Int, x1: Int, y0: Int, y1: Int)? {
        let px = V0354GoldAingArtTests.rgba(image)
        let w = image.width, h = image.height
        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > threshold {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        } }
        return x1 >= x0 ? (x0, x1, y0, y1) : nil
    }

    static var repoRoot: URL { CheckCoreSourceLayout.repoRoot }

    static func source(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// `start` 로 시작하는 줄부터 `end` 로 시작하는 줄 앞까지(앞 공백 무시).
    static func region(_ text: String, from start: String, to end: String) throws -> String {
        let lines = text.components(separatedBy: "\n")
        let a = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(start) }, "\(start) 가 없다")
        let b = try #require(lines[(a + 1)...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(end) }, "\(end) 가 없다")
        return lines[a..<b].joined(separator: "\n")
    }

    /// 주석을 걷고 모든 공백을 한 칸으로 접는다(들여쓰기 차이를 지운다).
    static func normalized(_ code: String) -> String {
        V0351IfConfig.strippingComments(code)
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
    }

    // MARK: ① 생성기 사본

    @Test("생성기 사본: 몸 셰이더(딸기 · 초코) · 장식(딸기 · 초코) 구획이 scripts/make-cake-aing.swift 와 글자 그대로다(주석 · 들여쓰기만 무시)")
    func generatorRegionsAreVerbatim() throws {
        let script = try Self.source("scripts/make-cake-aing.swift")
        let app = try Self.source("Sources/check/CakeAingFinish.swift")
        let pairs = [("// MARK: - ① 몸 셰이더 — 딸기", "// MARK: - ② 장식 공통"), ("// MARK: - ② 장식 — 딸기", "// MARK: - 케이크 종류")]
        for (start, end) in pairs {
            let s = Self.normalized(try Self.region(script, from: start, to: end))
            // 앱 쪽은 두 구획 사이에 '② 장식 공통'이 없다(앱이 따로 옮겼다) — 첫 구획은 다음 구획 머리에서, 둘째는 사본 끝 표식에서 끊는다.
            let appEnd = end == "// MARK: - ② 장식 공통" ? "// MARK: - ② 장식 — 딸기" : "// ── 생성기 사본 끝"
            let a = Self.normalized(try Self.region(app, from: start, to: appEnd))
            #expect(s.count > 2_000, "구획이 너무 짧다(\(s.count)) — 표식을 잘못 잡았다")
            #expect(a == s, "\(start) 구획이 생성기와 다르다 — 생성기를 고치고 다시 옮겨라(첫 차이: \(Self.firstDifference(a, s)))")
        }
        // 기준선: 한 글자만 바꿔도 걸린다(비교가 헛돌지 않는다).
        let s = Self.normalized(try Self.region(script, from: pairs[0].0, to: pairs[0].1))
        #expect(s.replacingOccurrences(of: "0.142 + 0.060", with: "0.142 + 0.061") != s)
    }

    static func firstDifference(_ a: String, _ b: String) -> String {
        let ac = Array(a), bc = Array(b)
        let n = min(ac.count, bc.count)
        let i = (0..<n).first { ac[$0] != bc[$0] } ?? n
        return "…\(String(ac[max(0, i - 40)..<min(ac.count, i + 40)]))… ≠ …\(String(bc[max(0, i - 40)..<min(bc.count, i + 40)]))…"
    }

    @Test("상수: 앱 CakeAingFinish 의 몸 좌표 · 초코 기준 · 불꽃 끝 · 장식 이름이 생성기의 살아 있는 let 줄과 같고, 몸 좌표는 무지개와 같다")
    func constantsMatchTheGenerator() throws {
        let script = Self.normalized(try Self.source("scripts/make-cake-aing.swift"))
        let lines: [(String, String)] = [
            ("let bodyTop = 0.848950", "\(CakeAingFinish.bodyTop)"),
            ("let bodyHeight = 1.695736", "\(CakeAingFinish.bodyHeight)"),
            ("let lReference = 0.8327", "\(CakeAingFinish.lReference)"),
            ("let chocoSkinYRef = 0.56530", "\(CakeAingFinish.chocoSkinYRef)"),
            ("let chocoBlushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)", "\(CakeAingFinish.chocoBlushSRGB)"),
            ("let strawberryFlameTopY = 1.1396", "\(CakeAingFinish.strawberryFlameTopY)"),
            ("let chocoFlameTopY = 1.1839", "\(CakeAingFinish.chocoFlameTopY)"),
            ("let cakeDecorNodeName = \"check.cakeDecor\"", CakeAingFinish.cakeDecorNodeName),
        ]
        for (line, _) in lines {
            #expect(script.contains(line), "생성기에 '\(line)' 이 없다 — 상수가 바뀌었으면 앱도 같이 고쳐라")
        }
        #expect(CakeAingFinish.bodyTop == 0.848950 && CakeAingFinish.bodyHeight == 1.695736 && CakeAingFinish.lReference == 0.8327)
        #expect(CakeAingFinish.chocoSkinYRef == 0.56530 && CakeAingFinish.chocoBlushSRGB == SIMD3(245.62, 172.26, 200.68))
        #expect(CakeAingFinish.strawberryFlameTopY == 1.1396 && CakeAingFinish.chocoFlameTopY == 1.1839)
        #expect(CakeAingFinish.cakeDecorNodeName == "check.cakeDecor")
        #expect(CakeAingFinish.bodyTop == RainbowAingArt.bodyTop && CakeAingFinish.bodyHeight == RainbowAingArt.bodyHeight
                    && CakeAingFinish.lReference == RainbowAingArt.lightnessReference)
    }

    @Test("장식: 앱이 만든 장식 루트 이름 · 자식(딸기 check.cake.* · 초코 cake.*) · 불꽃 끝 높이가 생성기 상수와 같다 · 사본은 빌보드를 지닌다")
    func decorMatchesTheGenerator() throws {
        let scene = try #require(CheckCharacter3DScene.loadModelScene())
        var body: SCNNode?
        scene.rootNode.enumerateHierarchy { node, stop in if node.geometry != nil { body = node; stop.pointee = true } }
        let probe = CakeAingFinish.meshSurfaceProbe(try #require(body))
        let strawberryTop = CakeAingFinish.StrawberryDecor.flameTopY(probe: probe)
        let chocoTop = CakeAingFinish.ChocoDecor.flameTopY(probe: probe)
        print(String(format: "[v0366-3d] 불꽃 끝 y: 딸기 %.4f(상수 %.4f) · 초코 %.4f(상수 %.4f)", strawberryTop, CakeAingFinish.strawberryFlameTopY,
                     chocoTop, CakeAingFinish.chocoFlameTopY))
        #expect(abs(strawberryTop - CakeAingFinish.strawberryFlameTopY) < 5e-4)
        #expect(abs(chocoTop - CakeAingFinish.chocoFlameTopY) < 5e-4)
        for kind in CakeAingFinish.Kind.allCases {
            let decor = try #require(CakeAingFinish.decorNode(kind))
            #expect(decor.name == CakeAingFinish.cakeDecorNodeName)
            var names: [String] = []
            var billboards = 0
            decor.enumerateHierarchy { node, _ in
                if let name = node.name { names.append(name) }
                if node.constraints?.contains(where: { $0 is SCNBillboardConstraint }) == true { billboards += 1 }
            }
            switch kind {
            case .strawberry:
                #expect(names.contains("check.cake.candle") && names.contains("check.cake.strawberry") && names.contains("flame") && names.contains("glow"),
                        "딸기 장식 자식 \(names)")
            case .choco:
                #expect(names.contains("cake.candle") && names.contains("cake.strawberry") && names.contains("cake.flame") && names.contains("cake.glow0"),
                        "초코 장식 자식 \(names)")
            }
            #expect(billboards >= 1, "\(kind) 장식 사본에 빛 번짐 빌보드가 없다")
            // 사본은 지오메트리를 나눠 쓴다(프로세스당 한 번 만든다).
            let again = try #require(CakeAingFinish.decorNode(kind))
            #expect(again !== decor)
            var g1: [SCNGeometry] = [], g2: [SCNGeometry] = []
            decor.enumerateHierarchy { node, _ in if let g = node.geometry { g1.append(g) } }
            again.enumerateHierarchy { node, _ in if let g = node.geometry { g2.append(g) } }
            #expect(g1.count == g2.count && zip(g1, g2).allSatisfy { $0 === $1 }, "\(kind) 장식이 씬마다 다시 만들어진다")
        }
    }

    // MARK: ② 마감이 선다

    @Test("케이크 씬: 얼굴 = 무지개와 같은 합성 디퓨즈 + 케이크 몸 셰이더(초코는 ckShadeMap) · 몸 메시에 장식 · 표식 · 프레이밍 내림 — 아잉·황금·무지개엔 없다")
    func finishIsApplied() throws {
        for manifest in Self.cakes {
            let kind = try Self.kind(manifest)
            let scene = try V0354GoldAing3DTests.scene(manifest)
            let character = try V0354GoldAing3DTests.character(scene)
            let material = try V0359Rainbow3DTests.faceMaterial(scene)
            #expect(material.shaderModifiers?[.fragment] == kind.bodyShaderModifiers[.fragment], "\(manifest.id) 몸 셰이더가 안 걸렸다")
            #expect(material.shaderModifiers?[.geometry] == kind.bodyShaderModifiers[.geometry])
            let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
            #expect(RainbowAingFinish.lavenderOriginal(ofRainbowFace: face) != nil, "\(manifest.id) 디퓨즈가 무지개 합성(같은 객체)이 아니다 — 감은 눈 갈래를 못 탄다")
            let shadeMap = material.value(forKey: CakeAingFinish.ChocoBody.shadeMapKey) as? SCNMaterialProperty
            #expect((shadeMap != nil) == (kind == .choco), "\(manifest.id) ckShadeMap \(shadeMap == nil ? "없음" : "있음")")
            let decor = try #require(Self.decor(scene), "\(manifest.id) 장식이 없다")
            // 장식은 **몸 메시 노드**(얼굴 재질을 쥔 지오메트리 노드 — 정수리 hitTest 가 그 물체 좌표로 자리를 잡았다)의 자식이고, 그 노드는 캐릭터 아래다.
            let mesh = try #require(decor.parent, "\(manifest.id) 장식에 부모가 없다")
            #expect(mesh.geometry?.materials.contains { $0 === material } == true, "장식이 몸 메시 노드 자식이 아니다(\(mesh.name ?? "?"))")
            var cursor: SCNNode? = mesh
            while let current = cursor, current !== character { cursor = current.parent }
            #expect(cursor === character, "장식이 캐릭터 노드 아래가 아니다")
            #expect(CakeAingFinish.kind(of: character) == kind)
            #expect(abs(character.simdPosition.y + CakeAingFinish.framingDrop) < 1e-6, "\(manifest.id) 프레이밍 내림 \(character.simdPosition.y)")
            #expect(scene.rootNode.childNode(withName: RainbowAingFinish.haloNodeName, recursively: true) == nil, "케이크에 무지개 후광이 섰다")
        }
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInGoldAing, CharacterCatalog.builtInRainbowAing] {
            let scene = try V0354GoldAing3DTests.scene(other)
            let character = try V0354GoldAing3DTests.character(scene)
            #expect(Self.decor(scene) == nil, "\(other.id) 에 케이크 장식이 섰다")
            #expect(CakeAingFinish.kind(of: character) == nil)
            #expect(character.simdPosition == .zero, "\(other.id) 구도가 바뀌었다(\(character.simdPosition))")
        }
    }

    // MARK: ③ 감은 눈

    /// 눈 자리 평균색(엔진이 졸 때). 기준선 = 같은 씬을 셰이더 없이(디퓨즈 그대로) 그린 같은 자리.
    static func closedEyeColors(_ manifest: CharacterManifest) throws -> (cake: (L: Double, C: Double, h: Double), lavender: (L: Double, C: Double, h: Double),
                                                                         awakeL: Double) {
        let scene = try V0354GoldAing3DTests.scene(manifest)
        let engine = ReactionEngine()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let eye = try V0359Rainbow3DTests.eyePixel(scene, size: appSize)
        let awake = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: appSize))
        let awakeColor = V0359Rainbow3DTests.averageColor(awake, width: Int(appSize.width), at: eye)
        engine.request(.drowsy)
        #expect(engine.state == .sleeping)
        let closed = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: appSize))
        let closedColor = V0359Rainbow3DTests.averageColor(closed, width: Int(appSize.width), at: eye)
        let lavender = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: appSize, modifiers: .some(nil)))
        let lavenderColor = V0359Rainbow3DTests.averageColor(lavender, width: Int(appSize.width), at: eye)
        engine.request(.wake)
        return (V0359RainbowArtTests.oklch(closedColor.0, closedColor.1, closedColor.2),
                V0359RainbowArtTests.oklch(lavenderColor.0, lavenderColor.1, lavenderColor.2),
                V0359RainbowArtTests.oklch(awakeColor.0, awakeColor.1, awakeColor.2).L)
    }

    @Test("감은 눈(엔진 CGImage 경로): 눈 자리가 케이크 색이다 — 딸기는 밝은 분홍 크림 · 초코는 어두운 갈색, 라벤더(셰이더 없이 같은 자리)와 색상이 다르다")
    func closedEyesAreCake() throws {
        let strawberry = try Self.closedEyeColors(Self.strawberry)
        let choco = try Self.closedEyeColors(Self.choco)
        print(String(format: "[v0366-3d] 감은 눈 자리: 딸기 L %.2f C %.3f h %.0f° · 초코 L %.2f C %.3f h %.0f° · 라벤더 h %.0f° · 뜬 눈 L %.2f/%.2f",
                     strawberry.cake.L, strawberry.cake.C, strawberry.cake.h, choco.cake.L, choco.cake.C, choco.cake.h, strawberry.lavender.h,
                     strawberry.awakeL, choco.awakeL))
        #expect(strawberry.awakeL < 0.5 && choco.awakeL < 0.5, "기준선: 뜬 눈 자리가 어둡지 않다 — 눈 좌표가 틀렸다")
        #expect(V0359RainbowArtTests.hueDistance(strawberry.lavender.h, 290) < 30, "기준선이 라벤더가 아니다(\(strawberry.lavender.h)°)")
        // 딸기: 밝은 분홍(크림) — 라벤더와 색상이 떨어지고 밝다.
        #expect(strawberry.cake.L > 0.75, "딸기 감은 눈 자리가 어둡다(L \(strawberry.cake.L)) — 눈이 남았다")
        #expect(V0359RainbowArtTests.hueDistance(strawberry.cake.h, strawberry.lavender.h) > 40, "딸기 감은 눈 자리 색상 \(strawberry.cake.h)° 가 라벤더와 같다")
        // 초코: 밀크초콜릿 몸(갈색 — 색상 30–80°) · 라벤더보다 확연히 어둡다. 뜬 눈(검은 눈동자)보다는 밝다.
        #expect(choco.cake.L < strawberry.lavender.L - 0.15, "초코 감은 눈 자리 L \(choco.cake.L) — 라벤더(\(strawberry.lavender.L))처럼 밝다")
        #expect(V0359RainbowArtTests.hueDistance(choco.cake.h, 55) < 35, "초코 감은 눈 자리 색상 \(choco.cake.h)° 가 갈색이 아니다")
        #expect(choco.cake.L > choco.awakeL + 0.1, "초코 감은 눈 자리가 뜬 눈만큼 어둡다 — 눈이 안 덮였다")
    }

    @Test("감은 눈(뷰가 있는 GPU 텍스처 경로 — 깜빡임이 쓰는 길): 두 케이크 다 눈 자리가 케이크 색이다")
    func blinkOnGPUTexturePathIsCake() throws {
        for manifest in Self.cakes {
            let engine = ReactionEngine()
            let scene = try V0354GoldAing3DTests.scene(manifest)
            let view = SCNView(frame: NSRect(origin: .zero, size: NSSize(width: Self.appSize.width / 2, height: Self.appSize.height / 2)))
            view.scene = scene
            view.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
            view.antialiasingMode = .none
            engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: view)
            #expect(engine.hasFaceTextures, "\(manifest.id): 뷰가 있는데 얼굴 GPU 텍스처가 안 섰다")
            let eye = try V0359Rainbow3DTests.eyePixel(scene, size: Self.appSize)
            engine.request(.drowsy)
            #expect(engine.faceDiffuseTextureAssignments > 0, "\(manifest.id): 감은 눈이 GPU 텍스처로 안 바뀌었다")
            let shot = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let px = V0354GoldAingArtTests.rgba(shot)
            let scale = Double(shot.width) / Double(Self.appSize.width)
            let color = V0359Rainbow3DTests.averageColor(px, width: shot.width, at: (Int(Double(eye.0) * scale), Int(Double(eye.1) * scale)))
            let c = V0359RainbowArtTests.oklch(color.0, color.1, color.2)
            print(String(format: "[v0366-3d] GPU 경로 감은 눈 %@: L %.2f C %.3f h %.0f°", manifest.id, c.L, c.C, c.h))
            #expect(V0359RainbowArtTests.hueDistance(c.h, 290) > 40, "\(manifest.id) GPU 경로 감은 눈 자리가 라벤더다(\(c))")
            #expect(c.L > 0.3, "\(manifest.id) GPU 경로 감은 눈 자리가 눈처럼 어둡다(\(c))")
            engine.request(.wake)
        }
    }

    // MARK: ④ 장식은 몸이 아니다

    @Test("얼굴 탐색은 장식을 건너뛴다: 졸면 몸 디퓨즈만 감은 눈 판으로 바뀌고 장식 텍스처는 그대로다 · isDecor 는 조상으로 가른다")
    func faceSearchSkipsTheDecor() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.strawberry)
        let decor = try #require(Self.decor(scene))
        var decorTextures: [(SCNMaterial, CGImage)] = []
        decor.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] {
                if let cg = SleepEyeExplore.cgImage(from: m.diffuse.contents), cg.width >= 256 { decorTextures.append((m, cg)) }
            }
        }
        #expect(!decorTextures.isEmpty, "기준선: 딸기 장식에 '큰 CGImage 디퓨즈'(얼굴로 오인될 판)가 없다 — 이 시험이 헛돈다")
        let body = try V0359Rainbow3DTests.faceMaterial(scene)
        let awake = try #require(SleepEyeExplore.cgImage(from: body.diffuse.contents))
        let engine = ReactionEngine()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        engine.request(.drowsy)
        let asleep = try #require(SleepEyeExplore.cgImage(from: body.diffuse.contents))
        #expect(asleep !== awake, "졸았는데 몸 디퓨즈가 안 바뀌었다 — 얼굴 탐색이 몸을 못 잡았다")
        for (material, image) in decorTextures {
            #expect(SleepEyeExplore.cgImage(from: material.diffuse.contents) === image, "장식 텍스처가 감은 눈으로 바뀌었다")
        }
        engine.request(.wake)
        // 조상 판정.
        var leaf: SCNNode?
        decor.enumerateHierarchy { node, stop in if node.geometry != nil { leaf = node; stop.pointee = true } }
        #expect(CakeAingFinish.isDecor(try #require(leaf)) && CakeAingFinish.isDecor(decor))
        #expect(!CakeAingFinish.isDecor(try V0354GoldAing3DTests.character(scene)))
    }

    /// 화면 밖 창(주문하지 않는다 — 화면에 안 뜬다)에 뷰를 얹어 엔진의 클릭 판정을 실제로 탄다.
    static func attachInOffscreenWindow(_ engine: ReactionEngine, _ manifest: CharacterManifest) throws -> (NSWindow, SCNView, SCNScene) {
        let scene = try V0354GoldAing3DTests.scene(manifest)
        let size = NSSize(width: 280, height: 340)
        let view = SCNView(frame: NSRect(origin: .zero, size: size))
        view.scene = scene
        view.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -30_000, y: 300), size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.contentView = view
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: view)
        _ = view.snapshot()
        return (window, view, scene)
    }

    @Test("몸 클릭 판정은 장식을 뺀다: 초 · 불꽃 자리(머리 위)는 몸이 아니고 몸 가운데는 몸이다 — 기준선: 같은 점의 날 hitTest 는 장식을 맞힌다")
    func bodyHitTestIgnoresTheDecor() throws {
        for manifest in Self.cakes {
            let engine = ReactionEngine()
            let (window, view, scene) = try Self.attachInOffscreenWindow(engine, manifest)
            defer { window.contentView = nil }
            let decor = try #require(Self.decor(scene))
            // 초 몸통 가운데(불꽃 끝 바로 아래 — 머리 위 허공)를 뷰 좌표로.
            var candle: SCNNode?
            decor.enumerateHierarchy { node, stop in
                if node.name == "candle" || node.name == "cake.candle" { candle = node; stop.pointee = true }
            }
            let candleNode = try #require(candle)
            let (lo, hi) = candleNode.boundingBox
            let top = candleNode.convertPosition(SCNVector3((lo.x + hi.x) / 2, hi.y - (hi.y - lo.y) * 0.15, (lo.z + hi.z) / 2), to: nil)
            let p = view.projectPoint(top)
            let local = NSPoint(x: p.x, y: p.y)
            let raw = view.hitTest(local, options: [.rootNode: try V0354GoldAing3DTests.wrapper(scene), .boundingBoxOnly: false,
                                                   .ignoreHiddenNodes: true])
            #expect(raw.contains { CakeAingFinish.isDecor($0.node) }, "\(manifest.id) 기준선: 초 자리의 날 hitTest 가 장식을 안 맞힌다 — 점을 잘못 잡았다")
            #expect(!raw.contains { !CakeAingFinish.isDecor($0.node) }, "\(manifest.id) 기준선: 초 자리 뒤에 몸이 있다 — 머리 위가 아니다")
            let screen = window.convertPoint(toScreen: view.convert(local, to: nil))
            #expect(!engine.isBodyAtScreenPoint(screen), "\(manifest.id) 초를 누르면 몸으로 친다")
            let center = window.convertPoint(toScreen: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil))
            #expect(engine.isBodyAtScreenPoint(center), "\(manifest.id) 몸 가운데가 몸이 아니다")
        }
    }

    // MARK: ⑤ 프레이밍

    struct Frame { var top: Double; var bottom: Double }

    /// 앱 구도(280×340)에서 알파 > 8 상자의 위 여유 · 아래 여유(프레임 높이 비율). `float` = 부유 꼭대기(+0.07)에 세운다.
    static func frame(_ manifest: CharacterManifest, float: Bool, undo drop: Bool = false, yawDegrees: Double = 0) throws -> Frame {
        let scene = try V0354GoldAing3DTests.scene(manifest)
        scene.rootNode.childNode(withName: GoldAingFinish.haloNodeName, recursively: true)?.isHidden = true
        scene.rootNode.childNode(withName: RainbowAingFinish.haloNodeName, recursively: true)?.isHidden = true
        let character = try V0354GoldAing3DTests.character(scene)
        try V0355GoldHaloYawTests.facing(scene).eulerAngles = SCNVector3(0, CGFloat(yawDegrees * .pi / 180), 0)
        if float { character.simdPosition.y += 0.07 }
        if drop { character.simdPosition.y += CakeAingFinish.framingDrop }
        let box = try #require(Self.alphaBox(try V0359Rainbow3DTests.render(scene, size: appSize)))
        return Frame(top: Double(box.y0) / appSize.height, bottom: 1 - Double(box.y1 + 1) / appSize.height)
    }

    @Test("프레이밍: 케이크 장식(빛 번짐까지) 위 끝이 부유 꼭대기에서도 프레임 위 2% 안쪽 · 몸 아래 끝도 프레임 안 — 내리지 않은 초코는 잘린다(기준선) · 아잉 구도 그대로")
    func framingKeepsTheFlameInside() throws {
        let aing = try Self.frame(CharacterCatalog.builtInAing, float: true)
        let aingRest = try Self.frame(CharacterCatalog.builtInAing, float: false)
        print(String(format: "[v0366-3d] 아잉 부유 꼭대기 위 %.3f · 쉼 아래 %.3f", aing.top, aingRest.bottom))
        for manifest in Self.cakes {
            for yaw in [0.0, 40.0, -40.0] {
                let up = try Self.frame(manifest, float: true, yawDegrees: yaw)
                let rest = try Self.frame(manifest, float: false, yawDegrees: yaw)
                print(String(format: "[v0366-3d] %@ 요 %.0f°: 부유 꼭대기 위 %.3f · 쉼 아래 %.3f", manifest.id, yaw, up.top, rest.bottom))
                #expect(up.top >= 0.02, "\(manifest.id) 요 \(yaw)°: 부유 꼭대기에서 장식 위 끝 여유 \(up.top) — 잘린다")
                #expect(rest.bottom >= 0.2, "\(manifest.id) 요 \(yaw)°: 몸 아래 끝 여유 \(rest.bottom)")
            }
        }
        // 기준선: 내리지 않으면(`framingDrop` 이 없던 자리) 초코 빛 번짐이 부유 꼭대기에서 위 가장자리에 닿는다(생성기 실측 −0.006).
        let undropped = try Self.frame(Self.choco, float: true, undo: true)
        #expect(undropped.top < 0.01, "기준선: 내리지 않은 초코도 여유가 있다(\(undropped.top)) — 내림이 필요 없거나 잣대가 틀렸다")
        // 다른 캐릭터 구도는 그대로(아잉 실측 — 부유 꼭대기 위 0.124 · 쉼 아래 0.332 @ 280×340).
        #expect(abs(aing.top - 0.124) < 0.006 && abs(aingRest.bottom - 0.332) < 0.006, "아잉 구도가 바뀌었다(\(aing.top), \(aingRest.bottom))")
        // 불꽃 끝 상수로도: 초코 불꽃 끝(물체 좌표)을 부유 꼭대기에서 투영하면 프레임 위 3% 안쪽이다.
        let scene = try V0354GoldAing3DTests.scene(Self.choco)
        let character = try V0354GoldAing3DTests.character(scene)
        character.simdPosition.y += 0.07
        let renderer = SCNRenderer(device: try #require(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = renderer.snapshot(atTime: 0, with: Self.appSize, antialiasingMode: .none)
        let tip = character.convertPosition(SCNVector3(-0.20, CakeAingFinish.chocoFlameTopY, -0.10), to: nil)
        let projected = renderer.projectPoint(tip)
        let tipFromTop = (Self.appSize.height - projected.y) / Self.appSize.height
        print(String(format: "[v0366-3d] 초코 불꽃 끝(상수) 부유 꼭대기 투영: 위에서 %.3f", Double(tipFromTop)))
        #expect(tipFromTop > 0.03, "초코 불꽃 끝이 프레임 위 가장자리에 붙는다(\(tipFromTop))")
    }

    @Test("리액션 진폭 · 클릭 프리체크 상자는 몸만 잰다: 케이크의 몸 상자 = 아잉 몸 상자(내린 만큼만 아래로) · 장식 없는 캐릭터는 SceneKit 값 그대로")
    func bodyBoundingBoxIgnoresTheDecor() throws {
        let aing = try V0354GoldAing3DTests.wrapper(try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing))
        let a = aing.boundingBox
        let viaHelper = CakeAingFinish.bodyBoundingBox(of: aing)
        #expect(viaHelper.min.x == a.min.x && viaHelper.max.y == a.max.y && viaHelper.min.z == a.min.z, "장식 없는 캐릭터의 상자가 바뀌었다")
        for manifest in Self.cakes {
            let wrapper = try V0354GoldAing3DTests.wrapper(try V0354GoldAing3DTests.scene(manifest))
            let whole = wrapper.boundingBox
            let body = CakeAingFinish.bodyBoundingBox(of: wrapper)
            #expect(whole.max.y > body.max.y + 0.2, "기준선: 장식이 상자를 안 키운다(\(whole.max.y) vs \(body.max.y)) — 시험이 헛돈다")
            let drop = CGFloat(CakeAingFinish.framingDrop)
            #expect(abs(body.max.y - (a.max.y - drop)) < 1e-3 && abs(body.min.y - (a.min.y - drop)) < 1e-3,
                    "\(manifest.id) 몸 상자 y \(body.min.y)…\(body.max.y) ≠ 아잉 \(a.min.y)…\(a.max.y) − \(drop)")
            #expect(abs((body.max.x - body.min.x) - (a.max.x - a.min.x)) < 1e-3)
        }
    }

    // MARK: ⑥ 울트라

    @Test("엔진은 아잉 · 딸기 · 초코를 가른다 — 교체 · 원복 왕복에서 장식 · 셰이더 · 표식 · 내림이 따라온다")
    func engineTellsCakesApart() throws {
        let engine = ReactionEngine()
        let scene = try V0354GoldAing3DTests.scene(Self.strawberry)
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        #expect(engine.currentCharacterID == CharacterCatalog.cakeStrawberryAingID)
        let stashed = try #require(engine.swapCharacter(to: Self.choco, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.cakeChocoAingID, "초코로 갈아입었는데 \(engine.currentCharacterID)")
        let swapped = try V0354GoldAing3DTests.character(scene)
        #expect(CakeAingFinish.kind(of: swapped) == .choco && abs(swapped.simdPosition.y + CakeAingFinish.framingDrop) < 1e-6,
                "교체로 세운 초코의 내림이 \(swapped.simdPosition.y)")
        #expect(try V0359Rainbow3DTests.faceMaterial(scene).shaderModifiers?[.fragment] == CakeAingFinish.ChocoBody.shaderModifiers[.fragment])
        #expect(Self.decor(scene) != nil)
        _ = try #require(engine.swapCharacter(to: CharacterCatalog.builtInAing, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
        #expect(Self.decor(scene) == nil, "아잉으로 갈아입었는데 장식이 남았다")
        #expect(try V0354GoldAing3DTests.character(scene).simdPosition == .zero, "아잉 구도가 케이크 내림을 물려받았다")
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == CharacterCatalog.cakeStrawberryAingID)
        #expect(try V0359Rainbow3DTests.faceMaterial(scene).shaderModifiers?[.fragment] == CakeAingFinish.strawberryBodyModifiers[.fragment])
    }

    @Test("울트라: 아잉 착용자가 초코에게 맞으면 장식 달린 초코가 서고 끝나면 아잉으로 · 딸기 착용자가 아잉에게 맞으면 갈아입고 끝나면 딸기로")
    func ultraSwapsTheCake() throws {
        do {
            let controller = try V0354UltraHarness.mounted(receiver: CharacterCatalog.builtInAing)
            controller.handleReceivedPokes([V0354UltraHarness.ultra(from: CharacterCatalog.cakeChocoAingID)])
            #expect(controller.isUltraActive)
            #expect(controller.engine.currentCharacterID == CharacterCatalog.cakeChocoAingID,
                    "아잉 화면에 초코가 안 섰다(\(controller.engine.currentCharacterID))")
            let scene = try #require(controller.engine.attachedScene)
            #expect(Self.decor(scene) != nil, "찌른 사람의 초코 케이크에 장식이 없다")
            controller.endUltraTakeover()
            #expect(controller.engine.currentCharacterID == CharacterCatalog.builtInAingID)
            controller.updateWorking(false)
        }
        do {
            let controller = try V0354UltraHarness.mounted(receiver: Self.strawberry)
            #expect(controller.engine.currentCharacterID == CharacterCatalog.cakeStrawberryAingID, "기준선이 딸기가 아니다")
            var atCover: String?
            controller.onUltraWillCoverScreen = { [weak controller] in atCover = controller?.engine.currentCharacterID }
            controller.handleReceivedPokes([V0354UltraHarness.ultra(from: nil)])
            #expect(atCover == CharacterCatalog.builtInAingID, "화면을 덮을 때 \(atCover ?? "nil")")
            controller.endUltraTakeover()
            #expect(controller.engine.currentCharacterID == CharacterCatalog.cakeStrawberryAingID, "원복이 딸기를 안 돌려놨다")
            controller.updateWorking(false)
        }
    }

    // MARK: ⑦ 그릴 수 있다 → 능력 번호 4

    @Test("그릴 수 있다: 번들 그대로 두 케이크가 든다(초상 두 장 + 밝기 맵) · 하나만 빠져도 못 그린다 · 능력 번호 4 · 초상 URL")
    func drawableAndProtocolFour() throws {
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(CharacterCatalog.cakeStrawberryAingID) && drawable.contains(CharacterCatalog.cakeChocoAingID), "\(drawable)")
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.cakeProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) == 4)
        let store = V0317ShopTests.plainStore()
        #expect(store.shopProtocolVersion == 4 && store.supportsCakeGift)
        for kind in CakeAingFinish.Kind.allCases {
            #expect(CakeAingFinish.isDrawable(kind))
            #expect(CakeAingFinish.requiredResourceNames(kind) == ["\(kind.characterID)-neutral", "\(kind.characterID)-negative", "aing_rainbow-shade"])
            for missing in CakeAingFinish.requiredResourceNames(kind) {
                #expect(!CakeAingFinish.isDrawable(kind) { $0 != missing }, "\(missing) 가 빠져도 그릴 수 있다고 한다")
            }
            #expect(CheckMascotAssets.catalog.portraitURL(for: kind.characterID, mood: .neutral)?.lastPathComponent == "\(kind.characterID)-neutral.png")
            #expect(CheckMascotAssets.catalog.portraitURL(for: kind.characterID, mood: .negative)?.lastPathComponent == "\(kind.characterID)-negative.png")
        }
        // 케이크가 하나만 그려지면 3 에 머문다(누적 규칙) — 앱이 쓰는 파생이 그 규칙을 그대로 탄다.
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != CharacterCatalog.cakeChocoAingID }) == 3)
    }

    // MARK: ⑧ 증거 스틸(사람이 보는 그림 — 기본 실행에서는 꺼져 있다)

    static func onBackground(_ image: CGImage, _ rgb: (Double, Double, Double)) throws -> CGImage {
        try V0359Rainbow3DTests.onBackground(image, rgb)
    }

    static func write(_ image: CGImage, _ name: String) throws {
        let dir = URL(fileURLWithPath: try #require(Self.evidenceDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    @Test("증거: 오버레이 구도 3D(정면 · 옆 40° · 감은 눈 · 부유 꼭대기) — 딸기 · 초코 · 아잉 기준", .enabled(if: evidenceDirectory != nil))
    func writeEvidence() throws {
        let dark = (28.0 / 255, 28.0 / 255, 30.0 / 255)
        for manifest in [Self.strawberry, Self.choco, CharacterCatalog.builtInAing] {
            var tiles: [CGImage] = []
            for (label, yaw, sleep, float) in [("front", 0.0, false, false), ("side40", 40.0, false, false),
                                               ("closed", 0.0, true, false), ("float-top", 0.0, false, true)] {
                let scene = try V0354GoldAing3DTests.scene(manifest)
                let engine = ReactionEngine()
                engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
                try V0355GoldHaloYawTests.facing(scene).eulerAngles = SCNVector3(0, CGFloat(yaw * .pi / 180), 0)
                if sleep { engine.request(.drowsy) }
                if float { try V0354GoldAing3DTests.character(scene).simdPosition.y += 0.07 }
                let raw = try V0359Rainbow3DTests.render(scene, size: CGSize(width: 560, height: 680))
                let tile = try Self.onBackground(raw, dark)
                try Self.write(tile, "\(manifest.id)-\(label).png")
                tiles.append(tile)
            }
            // 한 장 시트(네 칸 — 칸마다 프레임 테두리 1px).
            let w = 560, h = 680
            let ctx = try #require(CGContext(data: nil, width: w * tiles.count + (tiles.count - 1) * 8, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: h))
            for (i, tile) in tiles.enumerated() {
                ctx.draw(tile, in: CGRect(x: i * (w + 8), y: 0, width: w, height: h))
            }
            try Self.write(try #require(ctx.makeImage()), "sheet-3d-\(manifest.id).png")
        }
        // 울트라 크기(945²) — 초코 부유 꼭대기.
        let scene = try V0354GoldAing3DTests.scene(Self.choco)
        try V0354GoldAing3DTests.character(scene).simdPosition.y += 0.07
        try Self.write(try Self.onBackground(try V0359Rainbow3DTests.render(scene, size: CGSize(width: 945, height: 945)), dark),
                       "aing_cake_choco-ultra945-float-top.png")
    }
}
