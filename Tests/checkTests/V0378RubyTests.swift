import AppKit
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// v0.3.78 — 루비 아잉이(상점 루비 1000 · 시안 7차 Y5 '배 띠 · 6:4'). 대표 결정 2026-11-06("루비 1000개로 구매 가능하게" · #d_YgODZOIrIg5y).
//  ① 코어: 내장 아홉째 · 마감 .ruby(희귀 아님 · 선물 · 뽑기 전용 아님) · 능력 번호 8(누적) · 고르기는 서버가 루비를 말할 때만 · 몸 빚기 굽기.
//  ② 맥 3D: 실제 앱 씬에 마감이 선다(몸 빚기 칸 + 무지개 합성 디퓨즈 + 보석 셰이더 + ckShadeMap + 표식) · CPU 메시는 원래 그대로 ·
//     렌더가 분홍 보석(모양이 바뀜) · 엔진 교체 왕복 · 감은 눈 선 판이 옮긴 눈을 따라감 · 그릴 수 있다 → 능력 번호 8 · 초상 URL.
// 증거 PNG: `CHECK_V0378_RUBY_EVIDENCE_DIR=<폴더>` 를 주면 앱 구도 정면 · 3/4 · 뒤를 떨군다(창 없음).

@Suite struct V0378RubyCoreTests {
    /// 맥 소스 트리에 루비 초상 두 장이 있는가(생성기 `scripts/make-ruby-aing.swift` 결과를 커밋한다 — 이 판에선 늘 참).
    static var macRubyPortraitsInSourceTree: Bool {
        RubyAingArt.portraitResourceNames.allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }

    /// 맥 소스 트리에 루비 그림이 다 있는가(초상 두 장 + 3D 마감이 같이 쓰는 무지개 밝기 맵).
    static var macRubyArtInSourceTree: Bool {
        RubyAingArt.requiredResourceNames(for: .mac).allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }

    @Test("카탈로그: 루비는 내장 아홉째(v0.3.81 부터 개발 아잉이 앞) · id aing_ruby · 마감 .ruby · 희귀 · 케이크 아님 · 뽑기 전용 · 선물 전용 · 조각 전용 아님")
    func catalog() {
        // v0.3.81: 개발에 찌든 아잉이가 열째로 뒤에 붙었다 — 루비의 자리(아홉째)는 그대로다.
        #expect(CharacterCatalog.builtIns.map(\.id).firstIndex(of: "aing_ruby") == 8)
        #expect(CharacterCatalog.builtIns.count == 12)   // 부산 갈매기 · 서울의 밤 아잉이가 열한째 · 열두째
        #expect(CharacterCatalog.builtInRubyAing.displayName == "루비 아잉이")
        #expect(CharacterManifest.Finish(characterID: "aing_ruby") == .ruby)
        #expect(!CharacterManifest.Finish.ruby.isRare && !CharacterManifest.Finish.ruby.isCake)
        #expect(!CharacterCatalog.isGachaOnlyBuiltIn("aing_ruby"))
        #expect(!CharacterCatalog.isGiftOnlyBuiltIn("aing_ruby"))
        #expect(!CharacterCatalog.isShardOnlyBuiltIn("aing_ruby"))
        #expect(CharacterCatalog.isRubyAing("aing_ruby") && !CharacterCatalog.isRubyAing("aing_ruby ") && !CharacterCatalog.isRubyAing("aing"))
        #expect(CharacterCatalog.shopBuiltInIDs == ["aing_ruby"])
    }

    @Test("능력 번호: 여기까지 전부 + 루비를 그리면 8 · 루비가 없으면 7 · 루비만 있고 흑우가 없으면 6(누적 — 건너뛰어 말하지 않는다)")
    func protocolEight() {
        let all = ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "aing_isul", "aing_pepero", "aing_hwoo", "aing_ruby"]
        #expect(ShopWire.rubyProtocol == 8)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all) == 8)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all.filter { $0 != "aing_ruby" }) == 7)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all.filter { $0 != "aing_hwoo" }) == 6)
    }

    @Test("고르기: 루비는 서버가 루비 행을 말하거나 · 가졌거나 · 입었을 때만 선다 — 로드 전 관용 · 뽑기 관용은 없다")
    func pickerListsRubyOnlyWhenTheServerKnowsIt() {
        let ruby = CharacterCatalog.rubyAingID
        let row = ShopCharacterRow(id: ruby, price: 1000, owned: false)
        #expect(!WorkTimerStore.isCharacterListed(ruby, shopLoaded: false, gachaAvailable: false, owned: [], rows: []), "로드 전")
        #expect(!WorkTimerStore.isCharacterListed(ruby, shopLoaded: true, gachaAvailable: false, owned: [], rows: []), "루비를 모르는 서버")
        #expect(!WorkTimerStore.isCharacterListed(ruby, shopLoaded: true, gachaAvailable: true, owned: [], rows: []), "뽑기와 무관")
        #expect(WorkTimerStore.isCharacterListed(ruby, shopLoaded: true, gachaAvailable: false, owned: [], rows: [row]), "서버 행")
        #expect(WorkTimerStore.isCharacterListed(ruby, shopLoaded: true, gachaAvailable: false, owned: [ruby], rows: []), "가짐")
        #expect(WorkTimerStore.isCharacterListed(ruby, shopLoaded: false, gachaAvailable: false, owned: [], rows: [], wearing: ruby), "입음")
        // 루비 행은 보통 상점 칸(값 1000 · 살 수 있음)이다 — 뽑기 전용 · 선물 전용 표식이 없다.
        #expect(row.isPurchasable)
    }

    @Test("몸 빚기: 굽기는 결정적 · 몸 정점은 보석 쪽으로 40 % 옮겨 간다 · 띠(배 높이)가 가장 넓다 · 팔은 평행 이동(모양 그대로)")
    func bake() throws {
        // 원래 몸을 흉내 낸 구(반지름 0.73, 중심 y −0.04) — 실제 메시 굽기는 3D 시험이 잰다.
        var pts: [SIMD3<Float>] = []
        for i in 0..<40 { for j in 0..<80 {
            let th = Float.pi * (Float(i) + 0.5) / 40, ph = 2 * Float.pi * Float(j) / 80
            pts.append(SIMD3(0.73 * sin(th) * cos(ph), -0.04 + 0.89 * cos(th), 0.73 * sin(th) * sin(ph)))
        } }
        let a = RubyAingShape.bake(pts), b = RubyAingShape.bake(pts)
        #expect(a == b)
        #expect(a.count == pts.count)
        // 정면(+z) 배 높이(y ≈ −0.11): 보석 띠 반지름 0.76 쪽으로 — 0.73 + 0.4·(0.76 − 0.73) 근처.
        let belly = try #require(pts.indices.min { abs(pts[$0].y + 0.11) + abs(pts[$0].x) * 3 + (pts[$0].z < 0 ? 9 : 0) < abs(pts[$1].y + 0.11) + abs(pts[$1].x) * 3 + (pts[$1].z < 0 ? 9 : 0) })
        let moved = pts[belly] + a.displacement[belly]
        #expect(abs(simd_length(SIMD2(moved.x, moved.z)) - 0.742) < 0.02, "배 띠 반지름 \(simd_length(SIMD2(moved.x, moved.z)))")
        // 정수리(y ≈ 0.85 — 원래 메시 꼭대기 0.849): 판(y 0.80) 쪽으로 40 % 내려온다.
        let top = try #require(pts.indices.max { pts[$0].y < pts[$1].y })
        #expect(a.displacement[top].y < -0.01 && a.displacement[top].y > -0.04, "정수리 이동 \(a.displacement[top].y)")
        // 면 해시 · 모서리 거리는 0…1.
        #expect(a.facet.allSatisfy { $0 >= 0 && $0 <= 1 } && a.edge.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}

@MainActor
@Suite struct V0378RubyMac3DTests {
    static let ruby = CharacterCatalog.builtInRubyAing
    static let appSize = CGSize(width: 280, height: 340)
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_V0378_RUBY_EVIDENCE_DIR"]

    static func bodyGeometry(_ scene: SCNScene) throws -> SCNGeometry {
        var found: SCNGeometry?
        scene.rootNode.enumerateHierarchy { node, stop in
            guard let g = node.geometry, g.sources(for: .texcoord).count >= 4 || (g.materials.first?.diffuse.contents.map { CFGetTypeID($0 as CFTypeRef) == CGImage.typeID } ?? false) else { return }
            if node.name?.hasPrefix("check.") == true { return }
            found = g; stop.pointee = true
        }
        return try #require(found)
    }

    @Test("루비 씬: 몸 빚기 칸 셋이 실리고 CPU 정점은 원래 그대로 · 얼굴 = 무지개 합성 + 보석 셰이더 + ckShadeMap · 표식 — 다른 아잉 변형엔 없다")
    func finishIsApplied() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.ruby)
        let character = try V0354GoldAing3DTests.character(scene)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        #expect(material.shaderModifiers?[.geometry] == RubyAingShader.geometry, "몸 빚기 셰이더가 안 걸렸다")
        #expect(material.shaderModifiers?[.fragment] == RubyAingShader.fragment(), "보석 셰이더가 안 걸렸다")
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        #expect(RainbowAingFinish.lavenderOriginal(ofRainbowFace: face) != nil, "디퓨즈가 무지개 합성이 아니다 — 감은 눈 갈래를 못 탄다")
        let shade = try #require(material.value(forKey: RubyAingShader.shadeMapKey) as? SCNMaterialProperty)
        #expect(SleepEyeExplore.cgImage(from: shade.contents) === RainbowAingFinish.shadeImage())
        #expect(RubyAingFinish.isRuby(character))
        let g = try Self.bodyGeometry(scene)
        #expect(g.sources(for: .texcoord).count == 4, "몸 빚기 칸(1 · 2 · 3)이 없다")
        // CPU 정점은 원래 아잉 그대로(감은 눈 UV 마스크 · 구도 · 클릭이 원래 메시를 본다).
        let plain = try Self.bodyGeometry(try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing))
        let p0 = try #require(RubyAingFinish.positions(of: g)), p1 = try #require(RubyAingFinish.positions(of: plain))
        #expect(p0 == p1, "루비가 CPU 정점을 바꿨다")
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInHwooAing, CharacterCatalog.builtInIsulAing] {
            #expect(!RubyAingFinish.isRuby(try V0354GoldAing3DTests.character(try V0354GoldAing3DTests.scene(other))), "\(other.id) 에 루비 표식")
        }
    }

    @Test("렌더: 배가 분홍 보석(자홍 색상 · 진한 채도) · 실루엣이 원래 아잉과 다르다(정수리가 판으로 내려옴) · 셰이더 없으면 라벤더")
    func rendersGem() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.ruby)
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
        let bellyAt = pixel(SCNVector3(0.0, -0.40, 0.60))
        let c = V0359Rainbow3DTests.averageColor(px, width: w, at: bellyAt, radius: 1)
        let belly = V0359RainbowArtTests.oklch(c.0, c.1, c.2)
        print(String(format: "[v0378-ruby] 배 L %.2f C %.3f h %.0f°", belly.L, belly.C, belly.h))
        #expect(V0359RainbowArtTests.hueDistance(belly.h, 330) < 30 && belly.C > 0.15, "배가 분홍 보석이 아니다(\(belly))")
        // 실루엣: 원래 아잉의 정수리 바로 아래(y 0.83)는 루비에선 판(0.80 쪽으로 40 %) 위라 비어 있거나 가장자리다 — 알파를 원래와 비교.
        func alphaColumn(_ img: CGImage) -> Int {
            let p = V0354GoldAingArtTests.rgba(img), (x, _) = pixel(SCNVector3(0, 0, 0))
            var top = 0
            for y in 0..<img.height where p[(y * img.width + x) * 4 + 3] > 128 { top = y; break }
            return top
        }
        let plainScene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        let plainTop = alphaColumn(try V0359Rainbow3DTests.render(plainScene, size: Self.appSize))
        let rubyTop = alphaColumn(image)
        print("[v0378-ruby] 정수리 화소 행 — 아잉 \(plainTop) · 루비 \(rubyTop)")
        #expect(rubyTop > plainTop, "정수리가 원래 아잉과 같다 — 몸 빚기가 안 돌았다")
        // 기준선: 셰이더를 떼면 원래 라벤더 배다(색상이 분홍에서 멀다).
        let plain = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize, modifiers: .some(nil)))
        let pc = V0359Rainbow3DTests.averageColor(plain, width: w, at: bellyAt, radius: 1)
        let base = V0359RainbowArtTests.oklch(pc.0, pc.1, pc.2)
        print(String(format: "[v0378-ruby] 셰이더 없는 배 L %.2f C %.3f h %.0f°", base.L, base.C, base.h))
        #expect(V0359RainbowArtTests.hueDistance(base.h, 330) > 25 || base.C < 0.10, "기준선: 셰이더 없는 배가 라벤더가 아니다(\(base))")
        if Self.evidenceDirectory != nil { try Self.write(image, "ruby-front.png") }
    }

    @Test("감은 눈 선 판: 루비는 몸 셰이더가 그 눈 자리를 옮긴 만큼(굽기와 같은 값) 같이 옮긴다 · 다른 캐릭터는 원래 자리")
    func closedEyesFollowTheShape() throws {
        let rubyScene = try V0354GoldAing3DTests.scene(Self.ruby)
        let plainScene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        let body = RubyAingShape.BodyProfile(positions: try #require(RubyAingFinish.positions(of: try Self.bodyGeometry(rubyScene))))
        for (name, anchor) in CheckCharacter3DScene.closedEyeAnchors {
            let r = try #require(rubyScene.rootNode.childNode(withName: name, recursively: true)).position
            let p = try #require(plainScene.rootNode.childNode(withName: name, recursively: true)).position
            let d = SIMD3(Float(r.x - p.x), Float(r.y - p.y), Float(r.z - p.z))
            let want = RubyAingShape.displacement(at: SIMD3(Float(anchor.x), Float(anchor.y), Float(anchor.z)), body: body)
            print(String(format: "[v0378-ruby] %@ 감은 눈 이동 (%.4f, %.4f, %.4f)", name, d.x, d.y, d.z))
            #expect(simd_length(d - want) < 1e-4, "\(name) 이동 \(d) ≠ 굽기 \(want)")
            #expect(simd_length(d) < 0.05, "\(name) 눈 자리가 너무 많이 움직였다 \(d) — Y5 는 얼굴 둘레가 원래와 가깝다")
        }
    }

    /// 초상 눈 두 점(얼굴 위 절반의 눈동자 화소 덩어리 중심 — 좌우).
    static func portraitEyes(_ image: CGImage) -> (SIMD2<Double>, SIMD2<Double>)? {
        let px = V0354GoldAingArtTests.rgba(image), w = image.width, h = image.height
        var sL = SIMD2<Double>(0, 0), nL = 0.0, sR = SIMD2<Double>(0, 0), nR = 0.0
        for y in (h * 25 / 100)..<(h * 60 / 100) { for x in 0..<w {
            let i = (y * w + x) * 4
            guard px[i + 3] > 250 else { continue }
            let l = (0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])) / 255
            guard l < 0.12 else { continue }   // 눈동자(아주 어두운 갈색)만 — 눈썹(짙은 보라 · 0.12 보다 밝다)은 안 센다
            if x < w / 2 { sL += SIMD2(Double(x), Double(y)); nL += 1 } else { sR += SIMD2(Double(x), Double(y)); nR += 1 }
        } }
        guard nL > 4, nR > 4 else { return nil }
        return (sL / nL, sR / nR)
    }

    @Test("초상: 시무룩도 눈은 기본과 같은 자리(루비 3D 눈 — 대표 지적 11-07 '슬플때 눈이 이상한데? 위치가 이상해') · 입 자리는 바뀐다")
    func negativePortraitKeepsTheEyes() throws {
        func load(_ name: String) throws -> CGImage {
            let url = try #require(RubyAingFinish.resourceURL(name))
            return try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
        let neutral = try load(RubyAingArt.neutralPortraitResourceName), negative = try load(RubyAingArt.negativePortraitResourceName)
        let (nl, nr) = try #require(Self.portraitEyes(neutral)), (gl, gr) = try #require(Self.portraitEyes(negative))
        print(String(format: "[v0378-ruby] 초상 눈 — 기본 (%.1f, %.1f) (%.1f, %.1f) · 시무룩 (%.1f, %.1f) (%.1f, %.1f)", nl.x, nl.y, nr.x, nr.y, gl.x, gl.y, gr.x, gr.y))
        #expect(simd_length(nl - gl) < 1.5 && simd_length(nr - gr) < 1.5, "시무룩 눈이 기본 눈과 다른 자리에 있다")
        // 입 자리(두 눈 사이 아래)는 기본(웃는 입)과 시무룩(처진 입)이 달라야 한다.
        let a = V0354GoldAingArtTests.rgba(neutral), b = V0354GoldAingArtTests.rgba(negative), w = neutral.width
        let mid = (nl + nr) / 2, e = simd_length(nr - nl)
        var diff = 0
        for y in Int(mid.y + 0.1 * e)..<Int(mid.y + 0.7 * e) { for x in Int(mid.x - 0.3 * e)..<Int(mid.x + 0.3 * e) {
            let i = (y * w + x) * 4
            if abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i + 1]) - Int(b[i + 1])) + abs(Int(a[i + 2]) - Int(b[i + 2])) > 60 { diff += 1 }
        } }
        #expect(diff > 20, "입 자리가 기본과 같다(\(diff) 화소) — 시무룩 입이 안 얹혔다")
    }

    @Test("감은 눈 텍스처: 루비는 덮인 눈 자리를 밝기 맵 피부로 다시 채운다(볼터치는 남김) · 다른 캐릭터 갈래는 그대로")
    func closedEyeTextureIsCleaned() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.ruby)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        let g = try Self.bodyGeometry(scene)
        let generic = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: face, geometry: g))
        let ruby = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: face, geometry: g, character: try V0354GoldAing3DTests.character(scene)))
        let w = ruby.width, h = ruby.height
        let mask = try #require(SleepEyeTexture.eyeUVCoverMask(geometry: g, anchors: CheckCharacter3DScene.closedEyeAnchors.map { $0.position },
                                                               width: w, height: h, radius: CheckCharacter3DScene.eyeCoverRadius))
        let shadeImage = try #require(RainbowAingFinish.shadeImage())
        let shade = try #require(GoldAingFinish.rgbaBytes(shadeImage, width: w, height: h))
        let r = try #require(GoldAingFinish.rgbaBytes(ruby)), gp = try #require(GoldAingFinish.rgbaBytes(generic))
        var inside = 0, equalShade = 0, changed = 0
        for i in 0..<(w * h) where mask[i] {
            inside += 1
            if r[i * 4] == shade[i * 4] && r[i * 4 + 1] == shade[i * 4 + 1] && r[i * 4 + 2] == shade[i * 4 + 2] { equalShade += 1 }
            if r[i * 4] != gp[i * 4] || r[i * 4 + 1] != gp[i * 4 + 1] || r[i * 4 + 2] != gp[i * 4 + 2] { changed += 1 }
        }
        print("[v0378-ruby] 감은 눈 마스크 \(inside) 텍셀 · 밝기 맵과 같음 \(equalShade) · 일반 갈래와 다름 \(changed)")
        #expect(inside > 100 && Double(equalShade) / Double(inside) > 0.85, "덮인 눈 자리가 밝기 맵 피부로 안 채워졌다")
        #expect(changed > 0, "루비 갈래가 일반 감은 눈과 같다 — 손질이 안 돌았다")
        // 다른 캐릭터(아잉)는 character 를 줘도 일반 갈래 그대로다.
        let plain = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        let pm = try V0359Rainbow3DTests.faceMaterial(plain)
        let pf = try #require(SleepEyeExplore.cgImage(from: pm.diffuse.contents))
        let pg = try Self.bodyGeometry(plain)
        let a1 = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: pf, geometry: pg))
        let a2 = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: pf, geometry: pg, character: try V0354GoldAing3DTests.character(plain)))
        #expect(GoldAingFinish.rgbaBytes(a1) == GoldAingFinish.rgbaBytes(a2), "아잉 감은 눈이 바뀌었다")
    }

    @Test("엔진은 루비를 가른다 — 아잉 → 루비 교체(울트라 경로)에 셰이더 · 표식이 따라오고 원복하면 사라진다")
    func engineSwapsRuby() throws {
        let engine = ReactionEngine()
        let scene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let stashed = try #require(engine.swapCharacter(to: Self.ruby, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.rubyAingID, "루비로 갈아입었는데 \(engine.currentCharacterID)")
        #expect(try V0359Rainbow3DTests.faceMaterial(scene).shaderModifiers?[.geometry] == RubyAingShader.geometry)
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
    }

    @Test("그릴 수 있다: 번들 그대로 루비가 든다(초상 두 장 + 밝기 맵) · 하나만 빠져도 못 그린다 · 능력 번호 8 · 초상 URL · 192²")
    func drawableAndProtocolEight() throws {
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(CharacterCatalog.rubyAingID), "\(drawable)")
        // v0.3.81: 번호는 누적 — 개발 아잉이까지 실리면 9(루비의 몫은 "8 이상").
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) >= ShopWire.rubyProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) >= ShopWire.rubyProtocol)
        #expect(RubyAingFinish.isDrawable())
        #expect(RubyAingArt.requiredResourceNames(for: .mac) == ["aing_ruby-neutral", "aing_ruby-negative", "aing_rainbow-shade"])
        for missing in RubyAingArt.requiredResourceNames(for: .mac) {
            #expect(!RubyAingArt.isDrawable(on: .mac) { $0 != missing }, "\(missing) 가 빠져도 그릴 수 있다고 한다")
        }
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.rubyAingID, mood: .neutral)?.lastPathComponent == "aing_ruby-neutral.png")
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.rubyAingID, mood: .negative)?.lastPathComponent == "aing_ruby-negative.png")
        #expect(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.rubyAingID)?.size.width == 192)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != CharacterCatalog.rubyAingID }) == ShopWire.hwooProtocol)
    }

    static func write(_ image: CGImage, _ name: String) throws {
        let dir = URL(fileURLWithPath: try #require(Self.evidenceDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    /// 표정 · 상태 전부를 루비와 아잉 나란히 떨군다(대표 지적 11-07 "슬플때 눈이 이상한데? 위치가 이상해" — 앞뒤 비교용).
    /// 3D 는 표정이 하나(기본)뿐이고 깜빡임 · 졸기는 감은 눈 텍스처 + 선 판, 울트라는 엔진 교체다. 2D(기본 · 시무룩)는 번들 초상 그대로.
    @Test("증거: 표정 · 상태 전부(루비 · 아잉 나란히)", .enabled(if: evidenceDirectory != nil))
    func writeStatesEvidence() throws {
        let big = CGSize(width: 560, height: 680)
        for (tag, manifest) in [("ruby", Self.ruby), ("aing", CharacterCatalog.builtInAing)] {
            let scene = try V0354GoldAing3DTests.scene(manifest)
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-1-default.png")
            let material = try V0359Rainbow3DTests.faceMaterial(scene)
            let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
            let g = try Self.bodyGeometry(scene)
            let closed = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: face, geometry: g,
                                                                               character: try V0354GoldAing3DTests.character(scene)))
            material.diffuse.contents = closed
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-2-closed-texture.png")
            for (name, _) in CheckCharacter3DScene.closedEyeAnchors { scene.rootNode.childNode(withName: name, recursively: true)?.isHidden = false }
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-3-closed-eyes.png")
            let facing = try V0355GoldHaloYawTests.facing(scene)
            facing.eulerAngles = SCNVector3(0, CGFloat(35.0 * .pi / 180), 0)
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-3b-closed-eyes-34.png")
            for (name, _) in CheckCharacter3DScene.closedEyeAnchors { scene.rootNode.childNode(withName: name, recursively: true)?.isHidden = true }
            material.diffuse.contents = face
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-1b-default-34.png")
            facing.eulerAngles = SCNVector3(0, 0, 0)
            // 울트라 갈아입기: 아잉 씬을 엔진이 이 캐릭터로 바꿔 입힌 모습(루비) · 루비 씬을 아잉으로(아잉).
            let engine = ReactionEngine()
            let from = try V0354GoldAing3DTests.scene(tag == "ruby" ? CharacterCatalog.builtInAing : Self.ruby)
            engine.attach(node: try V0354GoldAing3DTests.wrapper(from), sceneRoot: from.rootNode, view: nil)
            _ = try #require(engine.swapCharacter(to: manifest, in: from))
            try Self.write(try V0359Rainbow3DTests.render(from, size: big), "\(tag)-4-ultra-swap.png")
        }
    }

    @Test("증거: 앱 구도 3/4 · 뒤 · 감은 눈", .enabled(if: evidenceDirectory != nil))
    func writeEvidence() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.ruby)
        let facing = try V0355GoldHaloYawTests.facing(scene)
        facing.eulerAngles = SCNVector3(0, CGFloat(35.0 * .pi / 180), 0)
        try Self.write(try V0359Rainbow3DTests.render(scene, size: Self.appSize), "ruby-three-quarter.png")
        facing.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
        try Self.write(try V0359Rainbow3DTests.render(scene, size: Self.appSize), "ruby-back.png")
        facing.eulerAngles = SCNVector3(0, 0, 0)
        // 감은 눈: 엔진처럼 얼굴을 감은 눈 텍스처로 바꾸고 선 판을 켠다.
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        let g = try Self.bodyGeometry(scene)
        if let closed = CheckCharacter3DScene.makeClosedEyesImage(faceImage: face, geometry: g, character: try V0354GoldAing3DTests.character(scene)) {
            material.diffuse.contents = closed
        }
        for (name, _) in CheckCharacter3DScene.closedEyeAnchors { scene.rootNode.childNode(withName: name, recursively: true)?.isHidden = false }
        try Self.write(try V0359Rainbow3DTests.render(scene, size: Self.appSize), "ruby-closed-eyes.png")
    }
}
