import AppKit
import Observation
import SceneKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.77 — 빼빼로 아잉이 3D(맥) · 그림 저장소. 실제 앱 씬(`CheckCharacter3DScene.makeScene` · 교체 경로 · 엔진)을 오프스크린 SCNRenderer 로 그려
// **결과**를 잰다(창 없음 — 이슬 V0374IsulMac3DTests 와 같은 틀):
//  ① 생성기 사본: `PeperoAingFinish.swift` 의 pepero-decor 구획이 `scripts/make-pepero-aing.swift` 의 그 구획과 글자 그대로다(주석 · 공백을 걷고) ·
//     앱이 만든 장식 노드의 이름 · 자리 · 치수 · 꼭대기가 생성기 상수와 같다.
//  ② 마감이 선다: 몸 메시 노드에 `check.peperoDecor`(상자 + 막대 셋) · 표식 · 몸 재질은 아잉 그대로 · 내리지 않음. 렌더가 빨간 상자 · 초코 막대 · 보라 얼굴.
//  ③ 장식은 몸이 아니다(얼굴 탐색 · 몸 클릭 · 진폭) · 반응 배율은 wrapper 에 걸려 장식이 몸과 같이 찌그러진다(팔 ↔ 구멍 상대 자리 그대로).
//  ④ 프레이밍(부유 꼭대기 · 요 ±40°) · 감은 눈 · 엔진 교체 왕복.
//  ⑤ 그릴 수 있다 → 능력 번호 6 · 초상 URL · 아바타 눈금.
//  ⑥ 그림 저장소(`PeperoArt`): 판정 · 경로 · 번들 폴백 · 캐시 → 번들 · 받아들이기 · 판이 바뀌면 장식을 다시 굽는다 · 받은 초상이 그린 캐시(받는 창 ·
//     뽑기 창 포함)에 닿는다 · 이슬 저장소도 두 창 캐시를 비운다.
// 증거 PNG: `CHECK_V0377_MAC_EVIDENCE_DIR=<폴더>` 를 주면 앱 구도 스틸 · 아바타 · 상점 카드 · 받는 창 · 메뉴바를 떨군다(창 없음).

@MainActor
@Suite(.serialized) struct V0377PeperoMac3DTests {
    static let pepero = CharacterCatalog.builtInPeperoAing
    static let id = CharacterCatalog.peperoAingID
    static let appSize = CGSize(width: 280, height: 340)
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_V0377_MAC_EVIDENCE_DIR"]

    typealias Decor = PeperoDecor

    /// 이 묶음의 빼빼로 씬은 메인에서 선다 — 메인은 장식을 굽지 않으므로(검토 수리 — 원본이 없으면 상자 없이 서고 메인 밖에서 구워 뒤에 붙인다)
    /// 원본을 먼저 구워 둔다(첫 시험에서 한 번 · 그 뒤는 사본이라 싸다). 메인 굽기 금지 자체는 `V0377PeperoReviewFixTests.mainNeverBakesTheDecor`.
    init() { _ = PeperoAingFinish.decorNode() }

    // MARK: 도구

    static func decor(_ scene: SCNScene) -> SCNNode? {
        scene.rootNode.childNode(withName: PeperoAingFinish.decorNodeName, recursively: true)
    }

    static func bundledBox() throws -> CGImage {
        let url = try #require(PeperoArt.bundledURL(.box))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func renderer(_ scene: SCNScene, size: CGSize = appSize) throws -> SCNRenderer {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        return renderer
    }

    /// 이 장면에서 물체 좌표 점(캐릭터 노드 기준)의 화소 자리(위가 0).
    static func pixel(_ renderer: SCNRenderer, _ character: SCNNode, _ local: SCNVector3, size: CGSize = appSize) -> (Int, Int) {
        let p = renderer.projectPoint(character.convertPosition(local, to: nil))
        return (Int(p.x.rounded()), Int((size.height - p.y).rounded()))
    }

    // MARK: ① 생성기 사본

    @Test("생성기 사본: pepero-decor 구획이 scripts/make-pepero-aing.swift 의 BEGIN/END 구획과 글자 그대로다(주석 · 공백만 무시)")
    func generatorRegionIsVerbatim() throws {
        let script = try V0366CakeMac3DTests.source("scripts/make-pepero-aing.swift")
        let app = try V0366CakeMac3DTests.source("Sources/check/PeperoAingFinish.swift")
        let s = V0366CakeMac3DTests.normalized(try V0366CakeMac3DTests.region(script, from: "// BEGIN pepero-decor", to: "// END pepero-decor"))
        let a = V0366CakeMac3DTests.normalized(try V0366CakeMac3DTests.region(app, from: "// BEGIN pepero-decor", to: "// END pepero-decor"))
        #expect(s.count > 8_000, "pepero-decor 구획이 너무 짧다(\(s.count)) — 표식을 잘못 잡았다")
        #expect(a == s, "pepero-decor 구획이 생성기와 다르다 — 생성기를 고치고 다시 옮겨라(첫 차이: \(V0366CakeMac3DTests.firstDifference(a, s)))")
        // 기준선: 숫자 한 글자만 바꿔도 걸린다(비교가 헛돈다면 이 줄이 같다고 한다).
        #expect(s.contains("static let topY: Float = 1.0951"), "기준선 문자열이 구획에 없다 — 아래 줄이 헛돈다")
        #expect(s.replacingOccurrences(of: "static let topY: Float = 1.0951", with: "static let topY: Float = 1.0952") != s)
        // 앱 사본은 한 벌뿐이다(같은 구획이 두 번 들어오면 첫 것만 맞대고 둘째가 갈린다).
        #expect(app.components(separatedBy: "// BEGIN pepero-decor").count == 2 && app.components(separatedBy: "// END pepero-decor").count == 2)
    }

    @Test("상수 · 노드: 장식 이름(루트 · 상자 · 막대 셋) · 상자 치수 · 막대 자리 · 판 규약 · 꼭대기(앱이 만든 장식으로 다시 잰다) · AingDecor 셋")
    func decorShapeMatchesTheGenerator() throws {
        #expect(PeperoAingFinish.decorNodeName == "check.peperoDecor" && Decor.boxNodeName == "check.pepero.box")
        #expect(Decor.sticks.map(\.name) == ["check.pepero.stickL", "check.pepero.stickR1", "check.pepero.stickR2"])
        #expect(AingDecor.rootNames == [CakeAingFinish.cakeDecorNodeName, IsulAingFinish.decorNodeName, PeperoAingFinish.decorNodeName,
                                       DevAingFinish.decorNodeName])   // v0.3.81 개발 아잉이 끈
        #expect(Decor.sheetWidth == 1024 && Decor.sheetHeight == 1024)
        #expect(Decor.frontRows == 0..<396 && Decor.backRows == 412..<808 && Decor.sideRows == 824..<1024)
        let decor = try #require(PeperoAingFinish.decorNode())
        #expect(decor.name == Decor.decorNodeName && decor.simdTransform == matrix_identity_float4x4)
        #expect(decor.childNodes.map { $0.name ?? "?" } == [Decor.boxNodeName] + Decor.sticks.map(\.name))
        // 상자: 단위 변환 · 지오메트리 상자 = 치수 상수(가로 ±a · 깊이 ±b · 바닥 y0 · 위 테 y1).
        let box = try #require(decor.childNode(withName: Decor.boxNodeName, recursively: false))
        #expect(box.simdTransform == matrix_identity_float4x4)
        let (lo, hi) = try #require(box.geometry).boundingBox
        print(String(format: "[v0377-3d] 상자 x %.3f…%.3f y %.3f…%.3f z %.3f…%.3f", lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
        #expect(abs(Float(hi.x) - Decor.a) < 2e-3 && abs(Float(lo.x) + Decor.a) < 2e-3, "상자 가로 \(lo.x)…\(hi.x) ≠ ±\(Decor.a)")
        #expect(abs(Float(hi.z) - Decor.b) < 2e-3 && abs(Float(lo.z) + Decor.b) < 2e-3, "상자 깊이 \(lo.z)…\(hi.z) ≠ ±\(Decor.b)")
        #expect(abs(Float(lo.y) - Decor.y0) < 2e-3 && abs(Float(hi.y) - Decor.y1) < 2e-3, "상자 높이 \(lo.y)…\(hi.y) ≠ \(Decor.y0)…\(Decor.y1)")
        // 막대: 아래 끝 = base · 축 = dir.
        for stick in Decor.sticks {
            let node = try #require(decor.childNode(withName: stick.name, recursively: false))
            let t = node.simdTransform
            #expect(simd_distance(SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z), stick.base) < 1e-5, "\(stick.name) 자리")
            let axis = simd_normalize(SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z))
            #expect(simd_distance(axis, simd_normalize(stick.dir)) < 1e-4, "\(stick.name) 축")
        }
        // 꼭대기: 앱이 만든 장식으로 다시 잰다(생성기가 실행 때 맞대는 상수와 같다).
        #expect(abs(Decor.measuredTopY(decor) - Decor.topY) < 5e-4, "장식 꼭대기 \(Decor.measuredTopY(decor)) ≠ 상수 \(Decor.topY)")
    }

    @Test("장식: 원본은 프로세스당 한 번 굽고 씬마다 사본(지오메트리 · 재질을 나눠 쓴다) · 재질 .constant · 상자 2048×768 · 막대 256×1024 · 판 규약 밖이면 nil")
    func decorIsBuiltOncePerProcessAndPerSheet() throws {
        let sheet = try #require(PeperoArt.shared.boxImage())
        let started = CFAbsoluteTimeGetCurrent()
        let first = try #require(PeperoAingFinish.decorNode(sheet: sheet))
        let ms = (CFAbsoluteTimeGetCurrent() - started) * 1_000
        let builds = PeperoAingFinish.decorBuildCountForTesting
        let second = try #require(PeperoAingFinish.decorNode(sheet: sheet))
        print(String(format: "[v0377-3d] 장식 첫 조회 %.1fms(이미 구웠으면 사본만) · 원본 구운 횟수 %d", ms, builds))
        #expect(builds >= 1 && PeperoAingFinish.decorBuildCountForTesting == builds, "두 번째 조회가 또 구웠다")
        #expect(first !== second && first.name == PeperoAingFinish.decorNodeName)
        let boxA = try #require(first.childNode(withName: Decor.boxNodeName, recursively: false))
        let boxB = try #require(second.childNode(withName: Decor.boxNodeName, recursively: false))
        #expect(boxA.geometry === boxB.geometry, "사본이 지오메트리를 나눠 쓰지 않는다")
        let boxMaterial = try #require(boxA.geometry?.firstMaterial)
        #expect(boxMaterial.lightingModel == .constant)
        let boxTexture = try #require(SleepEyeExplore.cgImage(from: boxMaterial.diffuse.contents))
        #expect(boxTexture.width == Decor.bakeWidth && boxTexture.height == Decor.bakeHeight)
        for stick in Decor.sticks {
            let material = try #require(first.childNode(withName: stick.name, recursively: false)?.geometry?.firstMaterial)
            #expect(material.lightingModel == .constant)
            let texture = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
            #expect(texture.width == 256 && texture.height == 1024)
        }
        // 규약 밖 판(512²) → 장식 없음 · 원본은 그대로(다음 조회가 옛 판 사본을 준다).
        let small = CakeAingFinish.makeImage([UInt8](repeating: 255, count: 512 * 512 * 4), 512, 512)
        #expect(PeperoAingFinish.decorNode(sheet: small) == nil)
        #expect(PeperoAingFinish.decorNode(sheet: nil) == nil)
        #expect(PeperoAingFinish.decorBuildCountForTesting == builds, "못 쓰는 판이 원본을 건드렸다")
        #expect(try #require(PeperoAingFinish.decorNode(sheet: sheet)).childNode(withName: Decor.boxNodeName, recursively: false)?.geometry
                === boxA.geometry, "못 쓰는 판 뒤에 원본이 바뀌었다")
    }

    // MARK: ② 마감이 선다

    @Test("빼빼로 씬: 몸 메시 노드에 장식 · 표식 · 몸 재질은 아잉 그대로(셰이더 · 합성 없음) · 내리지 않음 — 다른 아잉 변형엔 없다")
    func finishIsApplied() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.pepero)
        let character = try V0354GoldAing3DTests.character(scene)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        #expect(material.shaderModifiers == nil || material.shaderModifiers?.isEmpty == true, "몸에 셰이더가 걸렸다 — 몸은 원래 아잉이다")
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        #expect(RainbowAingFinish.lavenderOriginal(ofRainbowFace: face) == nil, "몸 디퓨즈가 무지개 합성이다 — 원래 아잉이 아니다")
        let plain = try #require(SleepEyeExplore.cgImage(from: try V0359Rainbow3DTests.faceMaterial(try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)).diffuse.contents))
        #expect(face.width == plain.width && face.height == plain.height && V0354GoldAingArtTests.rgba(face) == V0354GoldAingArtTests.rgba(plain),
                "몸 디퓨즈가 아잉 원본과 다르다")
        let decor = try #require(Self.decor(scene), "장식이 없다")
        let mesh = try #require(decor.parent)
        #expect(mesh.geometry?.materials.contains { $0 === material } == true, "장식이 몸 메시 노드 자식이 아니다(\(mesh.name ?? "?"))")
        #expect(PeperoAingFinish.isPepero(character))
        // 장식 자리 상수는 메시 물체 좌표다 — 메시 노드가 캐릭터 노드와 같은 좌표(단위 변환)여야 생성기 구도(캐릭터 기준)와 같다.
        let m = mesh.simdConvertTransform(matrix_identity_float4x4, to: character)
        let offIdentity = (0..<4).map { simd_distance(m[$0], matrix_identity_float4x4[$0]) }.max() ?? 1
        #expect(offIdentity < 1e-5, "몸 메시 좌표가 캐릭터 좌표와 다르다(\(m)) — 장식이 생성기 자리에서 벗어난다")
        #expect(character.simdPosition == .zero, "빼빼로는 내려 세우지 않는다(\(character.simdPosition))")
        #expect(V0366CakeMac3DTests.decor(scene) == nil && V0374IsulMac3DTests.decor(scene) == nil, "빼빼로에 케이크 · 이슬 장식이 섰다")
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInGoldAing, CharacterCatalog.builtInRainbowAing,
                      CharacterCatalog.builtInCakeChocoAing, CharacterCatalog.builtInIsulAing] {
            let scene = try V0354GoldAing3DTests.scene(other)
            #expect(Self.decor(scene) == nil, "\(other.id) 에 빼빼로 장식이 섰다")
            #expect(!PeperoAingFinish.isPepero(try V0354GoldAing3DTests.character(scene)))
        }
    }

    @Test("렌더: 상자 앞면이 빨강 · 막대 코팅이 초코 갈색 · 정수리 얼굴이 라벤더(몸 그대로) — 아잉 같은 자리는 빨강이 아니다(기준선)")
    func rendersRedBoxAndChocoSticks() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.pepero)
        let image = try V0359Rainbow3DTests.render(scene, size: Self.appSize)
        let px = V0354GoldAingArtTests.rgba(image)
        let character = try V0354GoldAing3DTests.character(scene)
        let renderer = try Self.renderer(scene)
        func color(_ local: SCNVector3, in rgba: [UInt8]) -> (L: Double, C: Double, h: Double) {
            let c = V0359Rainbow3DTests.averageColor(rgba, width: image.width, at: Self.pixel(renderer, character, local), radius: 2)
            return V0359RainbowArtTests.oklch(c.0, c.1, c.2)
        }
        func color(_ local: SCNVector3) -> (L: Double, C: Double, h: Double) { color(local, in: px) }
        // 상자 앞면 아래쪽(인쇄 글자 아래 빨강 바탕 — t ≈ 0.85), 막대 R1 코팅 중간, 정수리(상자 위 얼굴 둘레).
        let boxSpot = color(SCNVector3(0.55, -0.54, Double(Decor.b) + 0.01))
        let r1 = Decor.sticks[1]
        let tip = r1.base + simd_normalize(r1.dir) * (r1.length * 0.70)
        let stickSpot = color(SCNVector3(tip.x, tip.y, tip.z + 0.06))
        let headSpot = color(SCNVector3(0.0, 0.72, 0.30))
        print(String(format: "[v0377-3d] 상자 L %.2f C %.3f h %.0f° · 막대 L %.2f C %.3f h %.0f° · 정수리 L %.2f C %.3f h %.0f°",
                     boxSpot.L, boxSpot.C, boxSpot.h, stickSpot.L, stickSpot.C, stickSpot.h, headSpot.L, headSpot.C, headSpot.h))
        #expect(V0359RainbowArtTests.hueDistance(boxSpot.h, 25) < 25 && boxSpot.C > 0.12, "상자 앞면이 빨강이 아니다(\(boxSpot))")
        #expect(V0359RainbowArtTests.hueDistance(stickSpot.h, 55) < 30 && stickSpot.L < 0.65, "막대 코팅이 초코가 아니다(\(stickSpot))")
        #expect(V0359RainbowArtTests.hueDistance(headSpot.h, 290) < 35, "정수리가 라벤더가 아니다 — 몸이 바뀌었다(\(headSpot))")
        // 기준선: 아잉 씬의 같은 자리는 빨강이 아니다(상자가 실제로 그 자리에 그려졌다).
        let aingScene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        let aingPx = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(aingScene, size: Self.appSize))
        let base = color(SCNVector3(0.55, -0.54, Double(Decor.b) + 0.01), in: aingPx)
        #expect(V0359RainbowArtTests.hueDistance(base.h, 25) > 40 || base.C < 0.08, "기준선: 아잉 씬 같은 자리도 빨강이다 — 점을 잘못 잡았다(\(base))")
    }

    // MARK: ③ 장식은 몸이 아니다 · 반응

    @Test("얼굴 탐색은 장식을 건너뛴다: 졸면 몸 디퓨즈만 감은 눈 판으로 바뀌고 상자 · 막대 텍스처('큰 CGImage')는 그대로 · 눈 자리가 덮인다")
    func faceSearchSkipsTheDecor() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.pepero)
        let decor = try #require(Self.decor(scene))
        var decorTextures: [(SCNMaterial, CGImage)] = []
        decor.enumerateHierarchy { node, _ in
            for m in node.geometry?.materials ?? [] {
                if let cg = SleepEyeExplore.cgImage(from: m.diffuse.contents), cg.width >= 256 { decorTextures.append((m, cg)) }
            }
        }
        #expect(decorTextures.count == 4, "기준선: 장식에 '큰 CGImage 디퓨즈'(얼굴로 오인될 판)가 넷이 아니다(\(decorTextures.count))")
        let body = try V0359Rainbow3DTests.faceMaterial(scene)
        let awake = try #require(SleepEyeExplore.cgImage(from: body.diffuse.contents))
        let eye = try V0359Rainbow3DTests.eyePixel(scene, size: Self.appSize)
        let width = Int(Self.appSize.width)
        let awakeEye = V0359Rainbow3DTests.averageColor(V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize)), width: width, at: eye)
        let engine = ReactionEngine()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        engine.request(.drowsy)
        #expect(engine.state == .sleeping)
        let asleep = try #require(SleepEyeExplore.cgImage(from: body.diffuse.contents))
        #expect(asleep !== awake, "졸았는데 몸 디퓨즈가 안 바뀌었다 — 얼굴 탐색이 몸을 못 잡았다(장식을 얼굴로 잡았다)")
        for (material, image) in decorTextures {
            #expect(SleepEyeExplore.cgImage(from: material.diffuse.contents) === image, "장식 텍스처가 감은 눈으로 바뀌었다")
        }
        let closedEye = V0359Rainbow3DTests.averageColor(V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize)), width: width, at: eye)
        engine.request(.wake)
        let a = V0359RainbowArtTests.oklch(awakeEye.0, awakeEye.1, awakeEye.2)
        let c = V0359RainbowArtTests.oklch(closedEye.0, closedEye.1, closedEye.2)
        print(String(format: "[v0377-3d] 감은 눈 자리 L %.2f h %.0f° · 뜬 눈 L %.2f", c.L, c.h, a.L))
        #expect(c.L > a.L + 0.1 && V0359RainbowArtTests.hueDistance(c.h, 290) < 40, "감은 눈 자리가 라벤더 피부로 안 덮였다(\(c) · 뜬 눈 \(a))")
        let stick = try #require(decor.childNode(withName: Decor.sticks[0].name, recursively: false))
        let character = try V0354GoldAing3DTests.character(scene)
        #expect(AingDecor.isDecor(stick) && AingDecor.isDecor(decor) && !AingDecor.isDecor(character))
    }

    @Test("몸 클릭: 막대 끝(머리 위)의 hitTest 맞음은 전부 장식이고 엔진은 몸이 아니라 한다 · 몸 가운데는 몸 · 상자 앞(몸 앞)을 눌러도 몸")
    func decorHitsAreDecor() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.pepero)
        let renderer = try Self.renderer(scene)
        let character = try V0354GoldAing3DTests.character(scene)
        let options: [SCNHitTestOption: Any] = [.rootNode: try V0354GoldAing3DTests.wrapper(scene), .boundingBoxOnly: false, .ignoreHiddenNodes: true]
        let engine = ReactionEngine()
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let l = Decor.sticks[0]
        let tip = l.base + simd_normalize(l.dir) * (l.length - 0.04)
        let tipPoint = renderer.projectPoint(character.convertPosition(SCNVector3(tip.x, tip.y, tip.z), to: nil))
        let raw = renderer.hitTest(CGPoint(x: tipPoint.x, y: tipPoint.y), options: options)
        #expect(raw.contains { AingDecor.isDecor($0.node) }, "기준선: 막대 끝의 날 hitTest 가 막대를 안 맞힌다 — 점을 잘못 잡았다")
        #expect(!raw.contains { !AingDecor.isDecor($0.node) }, "막대 끝 hitTest 에 몸이 섞였다 — 머리 위가 아니다")
        #expect(!engine.isBodyHit(atViewPoint: CGPoint(x: tipPoint.x, y: tipPoint.y), renderer: renderer), "엔진이 막대 끝을 몸으로 친다 — 바탕화면 클릭을 먹는다")
        let centerPoint = CGPoint(x: Self.appSize.width / 2, y: Self.appSize.height / 2)
        #expect(engine.isBodyHit(atViewPoint: centerPoint, renderer: renderer), "엔진이 몸 가운데를 몸이 아니라 한다")
        let front = renderer.projectPoint(character.convertPosition(SCNVector3(0.0, -0.40, Double(Decor.b)), to: nil))
        let frontHits = renderer.hitTest(CGPoint(x: front.x, y: front.y), options: options)
        #expect(frontHits.first.map { AingDecor.isDecor($0.node) } == true, "기준선: 상자 앞면 점의 첫 맞음이 상자가 아니다")
        #expect(engine.isBodyHit(atViewPoint: CGPoint(x: front.x, y: front.y), renderer: renderer), "상자 앞(몸 앞)을 눌렀는데 몸이 아니라 한다")
    }

    @Test("리액션 진폭 · 클릭 프리체크 상자는 몸만 잰다: 빼빼로 몸 상자 = 아잉 몸 상자 · 장식은 상자를 키운다(기준선)")
    func bodyBoundingBoxIgnoresTheDecor() throws {
        let a = try V0354GoldAing3DTests.wrapper(try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)).boundingBox
        let wrapper = try V0354GoldAing3DTests.wrapper(try V0354GoldAing3DTests.scene(Self.pepero))
        let whole = wrapper.boundingBox
        let body = AingDecor.bodyBoundingBox(of: wrapper)
        #expect(whole.max.y > body.max.y + 0.2, "기준선: 막대가 상자를 안 키운다(\(whole.max.y) vs \(body.max.y)) — 시험이 헛돈다")
        #expect(abs(body.max.y - a.max.y) < 1e-3 && abs(body.min.y - a.min.y) < 1e-3 && abs(body.max.x - a.max.x) < 1e-3 && abs(body.min.z - a.min.z) < 1e-3,
                "빼빼로 몸 상자 \(body.min.y)…\(body.max.y) ≠ 아잉 \(a.min.y)…\(a.max.y)")
    }

    @Test("반응 배율은 wrapper 에 걸린다 — 장식이 몸과 같이 찌그러져 팔 단면 ↔ 팔 구멍 상대 자리가 그대로다(몸 메시에만 걸리면 갈린다 — 기준선)")
    func squashMovesTheDecorWithTheBody() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.pepero)
        let wrapper = try V0354GoldAing3DTests.wrapper(scene)
        let character = try V0354GoldAing3DTests.character(scene)
        let decor = try #require(Self.decor(scene))
        // 엔진의 반응은 wrapper 에 액션을 건다(캐릭터 · 몸 메시엔 안 건다).
        let engine = ReactionEngine()
        engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: nil)
        #expect(engine.request(.hit))
        #expect(wrapper.hasActions, "때리기 반응이 wrapper 에 안 걸렸다")
        #expect(!character.hasActions && !decor.hasActions, "반응이 캐릭터 · 장식 노드에 따로 걸렸다 — 장식과 몸이 갈린다")
        wrapper.removeAllActions()
        // 팔 단면 점(바깥 벽 |x| = a, 구멍 가운데)을 몸 좌표에서 장식 좌표로 옮겨 본다 — 찌부(1.28, 0.62, 1.28) 전후가 같아야 한다.
        let arm = SCNVector3(Double(Decor.a), Double(Decor.holeY), Double(Decor.holeZ))
        func inDecor() -> SCNVector3 { decor.convertPosition(character.convertPosition(arm, to: nil), from: nil) }
        let rest = inDecor()
        wrapper.scale = SCNVector3(1.28, 0.62, 1.28)
        let squashed = inDecor()
        #expect(abs(squashed.x - rest.x) < 1e-4 && abs(squashed.y - rest.y) < 1e-4 && abs(squashed.z - rest.z) < 1e-4,
                "찌부에서 팔 단면이 구멍을 벗어난다(\(rest) → \(squashed))")
        // 기준선: 배율을 몸 메시(캐릭터)에만 걸고 장식은 남겨 두면(장식을 wrapper 로 옮긴 꼴) 같은 점이 갈린다.
        wrapper.scale = SCNVector3(1, 1, 1)
        let detached = decor.clone()
        wrapper.addChildNode(detached)
        let detachedRest = detached.convertPosition(character.convertPosition(arm, to: nil), from: nil)
        character.scale = SCNVector3(1.28, 0.62, 1.28)
        let detachedSquashed = detached.convertPosition(character.convertPosition(arm, to: nil), from: nil)
        character.scale = SCNVector3(1, 1, 1)
        detached.removeFromParentNode()
        #expect(abs(detachedSquashed.y - detachedRest.y) > 0.05, "기준선: 몸만 찌그러뜨려도 상대 자리가 같다 — 시험이 헛돈다")
    }

    // MARK: ④ 프레이밍 · 엔진

    @Test("프레이밍: 막대 끝이 부유 꼭대기(+0.07)에서도 프레임 위 2% 안쪽 — 생성기 실측(0 → 0.065 · +0.07 → 0.044)과 같은 카메라 · 요 ±40° · 아잉 구도 그대로")
    func framingKeepsTheSticksInside() throws {
        let aing = try V0366CakeMac3DTests.frame(CharacterCatalog.builtInAing, float: true)
        let rest = try V0366CakeMac3DTests.frame(Self.pepero, float: false)
        let up = try V0366CakeMac3DTests.frame(Self.pepero, float: true)
        print(String(format: "[v0377-3d] 빼빼로 위 여백: 쉼 %.3f · 부유 꼭대기 %.3f · 쉼 아래 %.3f(아잉 부유 꼭대기 위 %.3f)", rest.top, up.top, rest.bottom, aing.top))
        #expect(abs(rest.top - 0.065) < 0.012 && abs(up.top - 0.044) < 0.012,
                "앱 카메라가 생성기 실측과 갈렸다(쉼 \(rest.top) · 부유 \(up.top)) — 카메라 식이 바뀌었으면 생성기 appCamera 도 같이")
        for yaw in [0.0, 40.0, -40.0, 90.0] {
            let f = try V0366CakeMac3DTests.frame(Self.pepero, float: true, yawDegrees: yaw)
            #expect(f.top >= 0.02, "요 \(yaw)°: 부유 꼭대기에서 막대 끝 여유 \(f.top) — 잘린다")
        }
        #expect(rest.bottom >= 0.15, "아래 끝 여유 \(rest.bottom)")
        #expect(abs(aing.top - 0.124) < 0.006, "아잉 구도가 바뀌었다(\(aing.top))")
    }

    @Test("엔진은 빼빼로를 가른다 — 아잉 → 빼빼로 교체(울트라 경로)에 장식 · 표식이 따라오고, 빼빼로 → 이슬 → 원복 왕복도 맞다")
    func engineSwapsPepero() throws {
        do {
            let engine = ReactionEngine()
            let scene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
            engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
            let stashed = try #require(engine.swapCharacter(to: Self.pepero, in: scene))
            #expect(engine.currentCharacterID == Self.id, "빼빼로로 갈아입었는데 \(engine.currentCharacterID)")
            #expect(Self.decor(scene) != nil, "교체로 선 빼빼로에 장식이 없다")
            #expect(try V0354GoldAing3DTests.character(scene).simdPosition == .zero)
            #expect(engine.restoreCharacterNode(stashed))
            #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID && Self.decor(scene) == nil, "아잉으로 돌아왔는데 장식이 남았다")
        }
        do {
            let engine = ReactionEngine()
            let scene = try V0354GoldAing3DTests.scene(Self.pepero)
            engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
            #expect(engine.currentCharacterID == Self.id)
            let stashed = try #require(engine.swapCharacter(to: CharacterCatalog.builtInIsulAing, in: scene))
            #expect(engine.currentCharacterID == CharacterCatalog.isulAingID)
            #expect(Self.decor(scene) == nil && V0374IsulMac3DTests.decor(scene) != nil, "이슬로 갈아입었는데 상자가 남았거나 뚜껑이 없다")
            #expect(engine.restoreCharacterNode(stashed))
            #expect(engine.currentCharacterID == Self.id && Self.decor(scene) != nil)
        }
    }

    // MARK: ⑤ 그릴 수 있다 → 능력 번호 6

    @Test("그릴 수 있다: 번들 그대로 빼빼로가 든다(판 + 초상 두 장) · 하나만 빠져도 못 그린다 · 능력 번호 6 · 초상 URL · 초상 PNG 규격")
    func drawableAndProtocolSix() throws {
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(Self.id) && drawable.contains(CharacterCatalog.isulAingID), "\(drawable)")
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) >= ShopWire.peperoProtocol, "v0.3.78 흑우가 얹히면 7(누적)")
        #expect(PeperoAingFinish.isDrawable())
        #expect(PeperoAingFinish.requiredResourceNames() == ["aing_pepero-box", "aing_pepero-neutral", "aing_pepero-negative"])
        for missing in PeperoAingFinish.requiredResourceNames() {
            #expect(!PeperoAingFinish.isDrawable { $0 != missing }, "\(missing) 가 빠져도 그릴 수 있다고 한다")
        }
        // 빼빼로가 빠지면 5(누적 — 이슬까지).
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != Self.id }) == ShopWire.isulProtocol)
        for mood in [CheckMascotAssets.Mood.neutral, .negative] {
            let url = try #require(CheckMascotAssets.catalog.portraitURL(for: Self.id, mood: mood))
            #expect(url.lastPathComponent == "aing_pepero-\(mood == .neutral ? "neutral" : "negative").png")
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 192 && image.height == 192, "\(url.lastPathComponent) \(image.width)×\(image.height)")
            #expect(PeperoArt.isAcceptable(data: try Data(contentsOf: url), kind: PeperoArt.Kind(mood: mood)))
            // 테두리 2px 는 거의 투명(막대 · 상자가 안 잘렸다 — 생성기 규약).
            let px = V0354GoldAingArtTests.rgba(image)
            var border = 0
            for y in 0..<192 { for x in 0..<192 where x < 2 || y < 2 || x >= 190 || y >= 190 { border = max(border, Int(px[(y * 192 + x) * 4 + 3])) } }
            #expect(border <= 40, "\(url.lastPathComponent) 테두리 알파 \(border)")
        }
        #expect(CheckMascotAssets.image(for: .neutral, characterID: Self.id)?.size.width == 192)
        // 초상 조회가 그림 저장소를 탄다(소스 계약 — 주석을 걷고 본다).
        let bridge = V0351IfConfig.strippingComments(try V0366CakeMac3DTests.source("Sources/check/CheckCoreBridge.swift"))
        #expect(bridge.contains("PeperoArt.current.portraitURL(mood)"), "초상 조회가 빼빼로 그림 저장소를 안 탄다")
        let assets = V0351IfConfig.strippingComments(try V0366CakeMac3DTests.source("Sources/check/CheckMascotAssets.swift"))
        #expect(assets.contains("if CharacterCatalog.isPeperoAing(id) { return PeperoAingFinish.isDrawable(fileManager: fileManager) }"),
                "drawable 의 빼빼로 줄이 마감 실재 판정이 아니다")
    }

    @Test("아바타: 빼빼로는 알파 상자(케이크 자르기 아님) — 얼굴 눈금이 이슬 · 케이크와 5% 안(실측 3.6% 작음) · 케이크 자르기면 10% 넘게 작아진다(기준선)")
    func avatarFaceMatchesTheOtherVariants() throws {
        #expect(AppUserAvatarArt.framing(characterID: Self.id) == .tight)
        #expect(AppUserAvatarArt.knownIDs.contains(Self.id))
        let art = try #require(AppUserAvatarArt.portrait(characterID: Self.id))
        let url = try #require(CheckMascotAssets.portraitURL(for: .neutral, characterID: Self.id))
        let raw = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        func scale(_ image: CGImage) -> Double {
            Double(AppUserAvatarArt.portraitBox(diameter: 46, artSize: CGSize(width: image.width, height: image.height)).width) / Double(image.width)
        }
        let isul = try #require(AppUserAvatarArt.portrait(characterID: CharacterCatalog.isulAingID))
        let cake = try #require(AppUserAvatarArt.portrait(characterID: CharacterCatalog.cakeChocoAingID))
        let cakeCut = CharacterCardArt.cakeBodyFramed(raw)
        print(String(format: "[v0377-3d] 46pt 아바타 눈금 빼빼로 %d×%d %.4f · 이슬 %d×%d %.4f · 초코 %d×%d %.4f · 빼빼로 케이크 자르기 %d×%d %.4f",
                     art.width, art.height, scale(art), isul.width, isul.height, scale(isul), cake.width, cake.height, scale(cake),
                     cakeCut.width, cakeCut.height, scale(cakeCut)))
        #expect(abs(scale(art) / scale(isul) - 1) < 0.05 && abs(scale(art) / scale(cake) - 1) < 0.05,
                "빼빼로 얼굴 눈금 \(scale(art)) 이 이슬 \(scale(isul)) · 초코 \(scale(cake)) 과 갈렸다")
        #expect(scale(cakeCut) < scale(art) * 0.9, "기준선: 케이크 자르기 눈금 \(scale(cakeCut)) 이 알파 상자 \(scale(art)) 와 비슷하다 — 고른 이유가 사라졌다")
    }

    // MARK: ⑥ 그림 저장소(PeperoArt)

    @Test("그림 판정(순수): 판은 정사각 1024 불투명 · 초상은 정사각 128px 이상 · 응답 → 할 일(200 바꿈 · 304 그대로 · 404 · 400 not_found 되돌림 · 그 밖 · 깨진 그림 그대로)")
    func artVerdicts() throws {
        typealias A = PeperoArt
        #expect(A.isAcceptable(pixelWidth: 1024, pixelHeight: 1024, kind: .box))
        #expect(!A.isAcceptable(pixelWidth: 2048, pixelHeight: 2048, kind: .box), "판 크기가 다르면 띠 자리가 어긋난다")
        #expect(!A.isAcceptable(pixelWidth: 1024, pixelHeight: 768, kind: .box))
        for kind in [A.Kind.neutral, .negative] {
            #expect(A.isAcceptable(pixelWidth: 192, pixelHeight: 192, kind: kind) && A.isAcceptable(pixelWidth: 1024, pixelHeight: 1024, kind: kind))
            #expect(!A.isAcceptable(pixelWidth: 96, pixelHeight: 96, kind: kind), "128px 밑")
            #expect(!A.isAcceptable(pixelWidth: 192, pixelHeight: 180, kind: kind), "정사각이 아니다")
        }
        let box = try Data(contentsOf: try #require(A.bundledURL(.box)))
        let portrait = try Data(contentsOf: try #require(A.bundledURL(.neutral)))
        #expect(A.isOpaque(try Self.bundledBox()), "번들 판이 불투명이 아니다")
        #expect(A.outcome(status: 200, data: box, kind: .box) == .replace)
        #expect(A.outcome(status: 200, data: portrait, kind: .neutral) == .replace)
        #expect(A.outcome(status: 200, data: portrait, kind: .box) == .keep, "초상을 판으로 받으면 버린다")
        #expect(A.outcome(status: 200, data: Data("not a png".utf8), kind: .box) == .keep)
        // 1024² 인데 투명 화소가 있는 판 — 상자 벽에 검은 구멍으로 굽힌다 → 버린다.
        var holed = V0354GoldAingArtTests.rgba(try Self.bundledBox())
        holed[(500 * 1024 + 500) * 4 + 3] = 0
        holed[(500 * 1024 + 500) * 4] = 0; holed[(500 * 1024 + 500) * 4 + 1] = 0; holed[(500 * 1024 + 500) * 4 + 2] = 0
        let holedData = try #require(NSBitmapImageRep(cgImage: CakeAingFinish.makeImage(holed, 1024, 1024)).representation(using: .png, properties: [:]))
        #expect(A.outcome(status: 200, data: holedData, kind: .box) == .keep, "투명 화소가 있는 판을 받았다")
        #expect(A.outcome(status: 304, data: Data(), kind: .box) == .keep)
        #expect(A.outcome(status: 404, data: Data(), kind: .negative) == .revert)
        let notFound = Data(#"{"statusCode":"404","error":"not_found","message":"Object not found"}"#.utf8)
        #expect(A.outcome(status: 400, data: notFound, kind: .box) == .revert, "400 + not_found 본문을 없는 개체로 안 읽었다")
        #expect(A.outcome(status: 400, data: Data(), kind: .box) == .keep, "본문 없는 400 을 되돌렸다")
        for status in [401, 403, 500, 503] {
            #expect(A.outcome(status: status, data: box, kind: .box) == .keep && A.outcome(status: status, data: notFound, kind: .box) == .keep, "\(status)")
        }
    }

    @Test("그림 위치: Storage game-art/pepero/<이름>.png · 캐시 Caches/check.game-art/pepero/<이름>.png · 번들 폴백 세 장이 쓸 만하다 · 시험 중엔 캐시도 네트워크도 안 탄다")
    func artLocations() throws {
        for kind in PeperoArt.Kind.allCases {
            #expect(PeperoArt.remoteURL(kind).absoluteString
                    == "\(SupabaseConfig.projectURL.absoluteString)/storage/v1/object/public/game-art/pepero/\(kind.rawValue).png")
            #expect(PeperoArt.shared.cacheFile(kind).path.hasSuffix("/Caches/check.game-art/pepero/\(kind.rawValue).png"), "\(PeperoArt.shared.cacheFile(kind).path)")
            let bundled = try #require(PeperoArt.bundledURL(kind), "\(kind) 번들 폴백이 없다")
            #expect(bundled.lastPathComponent == "aing_pepero-\(kind.rawValue).png")
            #expect(PeperoArt.isAcceptable(data: try Data(contentsOf: bundled), kind: kind), "\(kind) 번들 폴백이 판정을 못 지난다")
            #expect(PeperoArt.shared.url(kind) == bundled)
        }
        #expect(!PeperoArt.shared.readsCache && !PeperoArt.shared.usesNetwork, "시험 중인데 공용 저장소가 캐시 · 네트워크를 탄다")
        #expect(PeperoArt.current === PeperoArt.shared)
    }

    static func scratchCache(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("v0377-pepero-art-\(label)-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("디스크 캐시 → 번들: 쓸 만한 캐시는 그 파일 · 못 쓰는 캐시는 번들 · 200(바꿈 · 메타) → 304 → 404(지우고 번들) · 판이 바뀌면 판 객체가 바뀌고 장식을 다시 굽는다")
    func cacheThenBundleRoundTrip() throws {
        let dir = try Self.scratchCache("roundtrip")
        let art = PeperoArt(cacheDirectory: dir, readsCache: true, usesNetwork: false)
        let bundledBox = try #require(PeperoArt.bundledURL(.box))
        #expect(art.url(.box) == bundledBox)
        #expect(art.conditionalRequest(.box).value(forHTTPHeaderField: "If-None-Match") == nil)
        // 못 쓰는 캐시(초상을 판 자리에) → 번들 · 조건부 머리 없음.
        let other = PeperoArt(cacheDirectory: dir, readsCache: true, usesNetwork: false)
        try Data(contentsOf: try #require(PeperoArt.bundledURL(.neutral))).write(to: other.cacheFile(.box))
        try Data(#"{"etag":"\"v1\""}"#.utf8).write(to: other.metaFile(.box))
        #expect(other.url(.box) == bundledBox, "못 쓰는 캐시를 썼다")
        #expect(other.conditionalRequest(.box).value(forHTTPHeaderField: "If-None-Match") == nil, "못 쓰는 캐시인데 If-None-Match 를 단다")
        // 200 — 새 판(번들 판에서 한 점만 바꾼 판).
        var px = V0354GoldAingArtTests.rgba(try Self.bundledBox())
        px[0] = 0; px[1] = 200; px[2] = 0
        let newBox = try #require(NSBitmapImageRep(cgImage: CakeAingFinish.makeImage(px, 1024, 1024)).representation(using: .png, properties: [:]))
        let before = try #require(art.boxImage())
        #expect(art.boxImage() === before, "판을 바꾸기 전인데 객체가 바뀐다 — 장식을 매번 다시 굽는다")
        #expect(art.absorb(kind: .box, status: 200, data: newBox, etag: "\"v2\"", lastModified: "Wed, 04 Nov 2026 00:00:00 GMT") == .replace)
        #expect(art.url(.box) == art.cacheFile(.box))
        let after = try #require(art.boxImage())
        #expect(after !== before, "판을 바꿨는데 옛 판 객체를 준다")
        #expect(art.conditionalRequest(.box).value(forHTTPHeaderField: "If-None-Match") == "\"v2\"")
        // 판이 바뀌면 장식 원본을 다시 굽는다(같은 판이면 안 굽는다).
        _ = try #require(PeperoAingFinish.decorNode(sheet: before))
        let builds = PeperoAingFinish.decorBuildCountForTesting
        _ = try #require(PeperoAingFinish.decorNode(sheet: before))
        #expect(PeperoAingFinish.decorBuildCountForTesting == builds)
        _ = try #require(PeperoAingFinish.decorNode(sheet: after))
        #expect(PeperoAingFinish.decorBuildCountForTesting == builds + 1, "새 판인데 장식을 다시 굽지 않았다 — 옛 인쇄가 남는다")
        _ = PeperoAingFinish.decorNode(sheet: PeperoArt.shared.boxImage())   // 원본을 공용 판으로 되돌린다(뒤 시험이 다시 굽지 않게).
        // 304 · 5xx · 못 쓰는 200 — 그대로.
        #expect(art.absorb(kind: .box, status: 304, data: Data()) == .keep)
        #expect(art.absorb(kind: .box, status: 503, data: Data()) == .keep)
        #expect(art.absorb(kind: .box, status: 200, data: Data("x".utf8)) == .keep)
        #expect(art.boxImage() === after, "그대로여야 할 응답이 판을 바꿨다")
        // 404 — 캐시 · 메타를 지우고 번들로.
        #expect(art.absorb(kind: .box, status: 404, data: Data()) == .revert)
        #expect(!FileManager.default.fileExists(atPath: art.cacheFile(.box).path) && !FileManager.default.fileExists(atPath: art.metaFile(.box).path))
        #expect(art.url(.box) == bundledBox && art.boxImage() !== after)
        // 초상도 같은 길.
        #expect(art.absorb(kind: .neutral, status: 200, data: try Data(contentsOf: try #require(PeperoArt.bundledURL(.neutral)))) == .replace)
        #expect(art.portraitURL(.neutral) == art.cacheFile(.neutral) && art.portraitURL(.negative) == PeperoArt.bundledURL(.negative))
        // 판 풀기: 고른 캐시가 그 뒤 깨졌으면 번들로 한 번 더 푼다.
        let broken = PeperoArt(cacheDirectory: try Self.scratchCache("broken"), readsCache: true, usesNetwork: false)
        try Data(contentsOf: bundledBox).write(to: broken.cacheFile(.box))
        #expect(broken.url(.box) == broken.cacheFile(.box))
        try Data("not a png".utf8).write(to: broken.cacheFile(.box))
        let fallback = try #require(broken.boxImage(), "캐시를 못 풀자 판 없이 섰다")
        #expect(fallback.width == 1024 && fallback.height == 1024)
    }

    @Test("받은 초상은 곧바로 화면으로: 저장소가 200 을 흡수하면 관찰 값이 오르고 메뉴바 · 헤더 · 카드 · 아바타 · 받는 창 · 뽑기 창 캐시가 새 그림을 준다")
    func absorbedPortraitReachesTheDrawnCaches() async throws {
        let dir = try Self.scratchCache("redraw")
        let art = PeperoArt(cacheDirectory: dir, readsCache: true, usesNetwork: false)
        let id = Self.id
        let marked = try Self.greenCornerPortrait(try Data(contentsOf: try #require(PeperoArt.bundledURL(.neutral))))
        #expect(PeperoArt.isAcceptable(data: marked, kind: .neutral), "전제: 표식 초상이 판정을 못 지난다")
        func giftCorner() -> Bool { Self.greenInk(of: CheckCakeGiftWindowView.portrait(id)) > 20 }
        func gachaCorner() -> Bool { Self.greenInk(of: CheckGachaWindowView.portrait(id).resizable().frame(width: 192, height: 192)) > 20 }
        try await PeperoArt.$testOverride.withValue(art) {
            #expect(PeperoArt.current === art)
            PeperoArt.forgetDrawnPortraits()
            #expect(!Self.isGreenCorner(CheckMascotAssets.image(for: .neutral, characterID: id)), "기준선: 흡수 전부터 새 그림이다")
            let cardBefore = try #require(CharacterCardArt.image(characterID: id))
            #expect(!giftCorner() && !gachaCorner(), "기준선: 두 창이 흡수 전부터 새 그림이다")
            let redraws = V0374IsulMac3DTests.RedrawCount()
            withObservationTracking {
                _ = CheckMascotAssets.menuBarImage(for: .neutral, characterID: id)
            } onChange: { redraws.add() }
            let revision = PeperoArtRevision.shared.count
            #expect(art.absorb(kind: .neutral, status: 200, data: marked) == .replace)
            #expect(await V0354CoreStub.waitUntil { PeperoArtRevision.shared.count > revision }, "관찰 값이 안 올랐다 — 그린 화면이 다시 안 그린다")
            #expect(redraws.value == 1, "메뉴바 초상을 그린 화면이 바뀜을 못 들었다(\(redraws.value))")
            #expect(Self.isGreenCorner(CheckMascotAssets.image(for: .neutral, characterID: id)), "헤더 초상이 옛 그림이다")
            #expect(Self.isGreenCorner(CheckMascotAssets.menuBarImage(for: .neutral, characterID: id)), "메뉴바 초상이 옛 그림이다")
            let cardAfter = try #require(CharacterCardArt.image(characterID: id))
            #expect(cardAfter !== cardBefore, "카드 그림이 옛 그림 객체다")
            #expect(giftCorner(), "받는 창 초상이 옛 그림이다 — 받는 창 portraitCache 를 안 비웠다")
            #expect(gachaCorner(), "뽑기 창 초상이 옛 그림이다 — 뽑기 창 portraitCache 를 안 비웠다")
            // 다른 캐릭터는 이 값에 묶이지 않는다.
            let aingRedraws = V0374IsulMac3DTests.RedrawCount()
            withObservationTracking {
                _ = CheckMascotAssets.menuBarImage(for: .neutral, characterID: CharacterCatalog.builtInAingID)
            } onChange: { aingRedraws.add() }
            PeperoArtRevision.shared.bump()
            #expect(aingRedraws.value == 0, "아잉 초상을 그린 화면까지 빼빼로 그림 값에 묶였다")
        }
        PeperoArt.forgetDrawnPortraits()
        #expect(!Self.isGreenCorner(CheckMascotAssets.image(for: .neutral, characterID: id)), "뒷정리 뒤에도 시험 그림이 남았다")
        #expect(!giftCorner(), "뒷정리 뒤에도 받는 창에 시험 그림이 남았다")
    }

    @Test("이슬 저장소도 받는 창 · 뽑기 창 초상 캐시를 비운다(같은 결함 — 소스 계약 + 결과)")
    func isulForgetAlsoClearsTheWindowCaches() throws {
        let isul = CharacterCatalog.isulAingID
        _ = CheckCakeGiftWindowView.portrait(isul)
        _ = CheckGachaWindowView.portrait(isul)
        let source = V0351IfConfig.strippingComments(try V0366CakeMac3DTests.source("Sources/check/IsulArt.swift"))
        #expect(source.contains("CheckCakeGiftWindowView.forgetPortrait(characterID: CharacterCatalog.isulAingID)"), "이슬 저장소가 받는 창 캐시를 안 비운다")
        #expect(source.contains("CheckGachaWindowView.forgetPortrait(characterID: CharacterCatalog.isulAingID)"), "이슬 저장소가 뽑기 창 캐시를 안 비운다")
        let pepero = V0351IfConfig.strippingComments(try V0366CakeMac3DTests.source("Sources/check/PeperoArt.swift"))
        #expect(pepero.contains("CheckCakeGiftWindowView.forgetPortrait(characterID: id)") && pepero.contains("CheckGachaWindowView.forgetPortrait(characterID: id)"))
    }

    /// 케이크 · 이슬 미리 굽기(모든 사람)가 빼빼로를 안 굽는 것은 `V0377PeperoPrewarmTests.nonOwnerNeverBakes` 가 그 함수 몸통으로 잰다 — 여기서
    /// 공용 굽기 횟수로 재면 나란히 도는 빼빼로 묶음(`V0377PeperoReviewFixTests` 의 init)이 비운 캐시를 다시 구워 엉킨다.
    @Test("장식 미리 굽기(입은 사람 · 가진 사람만 — 조정자 결정 11-04): 앱 굽기(liveBake)를 단 문이 입은 사람에게 메인 밖에서 한 번 굽는다 — 그 뒤 첫 빼빼로 씬은 굽지 않는다")
    func decorIsPrewarmedOffMain() async throws {
        PeperoAingFinish.resetDecorCacheForTesting()
        let gate = PeperoPrewarmGate(bake: PeperoPrewarmGate.liveBake)
        let work = try #require(gate.arm(after: 0, wornID: Self.id, ownedIDs: [CharacterCatalog.builtInAingID]), "입은 사람의 시작이 굽기를 안 걸었다")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in work.notify(queue: .main) { done.resume() } }
        #expect(PeperoAingFinish.decorBuildCountForTesting == 1 && PeperoAingFinish.decorBuildsOnMainForTesting == [false],
                "입은 사람의 미리 굽기가 빼빼로 장식을 메인 밖에서 한 번 굽지 않았다 — \(PeperoAingFinish.decorBuildsOnMainForTesting)")
        _ = try V0354GoldAing3DTests.scene(Self.pepero)
        #expect(PeperoAingFinish.decorBuildCountForTesting == 1, "미리 구웠는데 첫 씬이 메인에서 또 구웠다")
    }

    // MARK: 도구 — SwiftUI 그림의 왼쪽 위 점(받는 창 · 뽑기 창 초상)

    /// 번들 초상의 왼쪽 위 32×32 를 순초록(0 255 0)으로 칠한 PNG — 빼빼로 초상에는 없는 색이라(빨강은 상자에 있다) 줄여 그린 화면에서도 가른다.
    static func greenCornerPortrait(_ data: Data) throws -> Data {
        let image = try #require(CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        var px = V0354GoldAingArtTests.rgba(image)
        for y in 0..<32 { for x in 0..<32 { let o = (y * image.width + x) * 4; px[o] = 0; px[o + 1] = 255; px[o + 2] = 0; px[o + 3] = 255 } }
        return try #require(NSBitmapImageRep(cgImage: CakeAingFinish.makeImage(px, image.width, image.height)).representation(using: .png, properties: [:]))
    }

    static func isGreenCorner(_ image: NSImage?) -> Bool {
        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let px = V0354GoldAingArtTests.rgba(cg)
        return px[3] > 200 && px[1] > 200 && px[0] < 60 && px[2] < 60
    }

    /// 이 화면을 굽고 순초록에 가까운 화소 수(받는 창 · 뽑기 창 초상 — 시험 그림만 초록 구석이 있다).
    static func greenInk(of view: some View) -> Int {
        let renderer = ImageRenderer(content: view.frame(width: 192, height: 192))
        renderer.scale = 1
        _ = renderer.cgImage
        guard let cg = renderer.cgImage else { return 0 }
        let px = V0354GoldAingArtTests.rgba(cg)
        var count = 0
        var i = 0
        while i + 3 < px.count {
            if px[i + 3] > 200 && px[i + 1] > 190 && px[i] < 70 && px[i + 2] < 70 { count += 1 }
            i += 4
        }
        return count
    }

    // MARK: ⑦ 증거 스틸(사람이 보는 그림 — 기본 실행에서는 꺼져 있다)

    static func write(_ image: CGImage, _ name: String) throws {
        let dir = URL(fileURLWithPath: try #require(Self.evidenceDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    static func sheet(_ tiles: [CGImage], gap: Int = 8, gray: Double = 0.5) throws -> CGImage {
        let w = tiles.map(\.width).max() ?? 1, h = tiles.map(\.height).max() ?? 1
        let ctx = try #require(CGContext(data: nil, width: w * tiles.count + (tiles.count - 1) * gap, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(srgbRed: gray, green: gray, blue: gray, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: h))
        for (i, tile) in tiles.enumerated() { ctx.draw(tile, in: CGRect(x: i * (w + gap), y: h - tile.height, width: tile.width, height: tile.height)) }
        return try #require(ctx.makeImage())
    }

    @Test("증거: 앱 구도 3D(정면 · 3/4 · 반응 찌부 · 감은 눈 · 부유 꼭대기) · 울트라 945² · 46pt 아바타 · 상점 카드 · 받는 창 · 메뉴바", .enabled(if: evidenceDirectory != nil))
    func writeEvidence() throws {
        let dark = (28.0 / 255, 28.0 / 255, 30.0 / 255)
        let light = (0.96, 0.96, 0.97)
        var tiles: [CGImage] = []
        for (label, yaw, sleep, float, squash) in [("front", 0.0, false, false, false), ("three-quarter", 35.0, false, false, false),
                                                   ("reaction-squash", 0.0, false, false, true), ("closed", 0.0, true, false, false),
                                                   ("float-top", 0.0, false, true, false), ("side", 90.0, false, false, false)] {
            let scene = try V0354GoldAing3DTests.scene(Self.pepero)
            let engine = ReactionEngine()
            let wrapper = try V0354GoldAing3DTests.wrapper(scene)
            engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: nil)
            try V0355GoldHaloYawTests.facing(scene).eulerAngles = SCNVector3(0, CGFloat(yaw * .pi / 180), 0)
            if sleep { engine.request(.drowsy) }
            if float { try V0354GoldAing3DTests.character(scene).simdPosition.y += 0.07 }
            // 때리기 반응의 찌부 열쇠 자세(ReactionActions.hit — wrapper 배율 1.28 · 0.62 · 1.28)를 그대로 세운다.
            if squash { wrapper.scale = SCNVector3(1.28, 0.62, 1.28) }
            let raw = try V0359Rainbow3DTests.render(scene, size: CGSize(width: 560, height: 680))
            let tile = try V0359Rainbow3DTests.onBackground(raw, dark)
            try Self.write(tile, "aing_pepero-3d-\(label).png")
            try Self.write(try V0359Rainbow3DTests.onBackground(raw, light), "aing_pepero-3d-\(label)-light.png")
            tiles.append(tile)
        }
        try Self.write(try Self.sheet(tiles), "sheet-3d-aing_pepero.png")
        let ultra = try V0354GoldAing3DTests.scene(Self.pepero)
        try V0354GoldAing3DTests.character(ultra).simdPosition.y += 0.07
        try Self.write(try V0359Rainbow3DTests.onBackground(try V0359Rainbow3DTests.render(ultra, size: CGSize(width: 945, height: 945)), dark),
                       "aing_pepero-ultra945-float-top.png")
        // 프로필 원 46pt(@2x 92px · @1x 46px) — 빼빼로 · 이슬 · 초코 · 아잉 나란히.
        let ids = [Self.id, CharacterCatalog.isulAingID, CharacterCatalog.cakeChocoAingID, CharacterCatalog.builtInAingID]
        for (scaleLabel, d) in [("2x", 92), ("1x", 46)] {
            let gap = 12
            let avatar = try #require(CGContext(data: nil, width: ids.count * (d + gap) + gap, height: d + 2 * gap, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            avatar.setFillColor(CGColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: 1))
            avatar.fill(CGRect(x: 0, y: 0, width: avatar.width, height: avatar.height))
            avatar.interpolationQuality = .high
            for (i, id) in ids.enumerated() {
                let art = try #require(AppUserAvatarArt.portrait(characterID: id), "\(id) 아바타 없음")
                let box = AppUserAvatarArt.portraitBox(diameter: CGFloat(d), artSize: CGSize(width: art.width, height: art.height))
                let cx = CGFloat(gap + i * (d + gap)) + CGFloat(d) / 2, cy = CGFloat(gap) + CGFloat(d) / 2
                avatar.saveGState()
                avatar.addEllipse(in: CGRect(x: cx - CGFloat(d) / 2, y: cy - CGFloat(d) / 2, width: CGFloat(d), height: CGFloat(d)))
                avatar.clip()
                avatar.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
                avatar.fill(CGRect(x: cx - CGFloat(d) / 2, y: cy - CGFloat(d) / 2, width: CGFloat(d), height: CGFloat(d)))
                avatar.draw(art, in: CGRect(x: cx - box.width / 2, y: cy - box.height / 2 - box.offsetY, width: box.width, height: box.height))
                avatar.restoreGState()
            }
            try Self.write(try #require(avatar.makeImage()), "avatar-46pt@\(scaleLabel)-pepero-isul-choco-aing.png")
        }
        // 상점 · 고르기 카드 그림(80×72pt @2x 칸) — 실제 카드 뷰(CharacterPortrait)를 ImageRenderer 로.
        var cards: [CGImage] = []
        for id in ids {
            let view = CharacterPortrait(characterID: id).frame(width: 80, height: 72).background(Color(white: 0.96))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            _ = renderer.cgImage
            cards.append(try #require(renderer.cgImage, "\(id) 카드 그림 없음"))
        }
        try Self.write(try Self.sheet(cards, gray: 0.8), "shop-card-80x72@2x-pepero-isul-choco-aing.png")
        // 받는 창 초대장(빼빼로 선물 화면) — 창 훅 대역(진짜 창 없음).
        let store = V0366CakeMacScreensTests.menuStore("v0377-evidence-invite")
        store.cakeGiftWindowHooks = CakeGiftWindowHooks(show: { _ in }, close: {}, isOpen: { false }, returnToPopover: {})
        store.applyCakeGiftPending(CharacterGiftOffer(id: "5e5e1111-0000-4000-8000-00000000e011", options: [Self.id],
                                                      note: "빼빼로 데이 축하해요", createdAt: "2026-11-11T00:00:00+00:00", kind: .pepero))
        #expect(store.cakeGiftPresented?.kind == .pepero)
        let size = CakeGiftWindowLayout.contentSize
        let invite = ImageRenderer(content: CheckCakeGiftWindowView(store: store, onClose: {}).frame(width: size.width, height: size.height))
        invite.scale = 2
        _ = invite.cgImage
        try Self.write(try #require(invite.cgImage), "gift-invite-pepero@2x.png")
        // 메뉴바(18pt @1x · @2x) — 어두운 · 밝은 막대에 빼빼로 · 이슬 · 아잉.
        for (label, bg) in [("dark", dark), ("light", light)] {
            for scale in [1, 2] {
                let s = 18 * scale, gap = 8 * scale
                let bar = try #require(CGContext(data: nil, width: ids.count * (s + gap) + gap, height: 24 * scale, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                bar.setFillColor(CGColor(srgbRed: bg.0, green: bg.1, blue: bg.2, alpha: 1))
                bar.fill(CGRect(x: 0, y: 0, width: bar.width, height: bar.height))
                bar.interpolationQuality = .high
                for (i, id) in ids.enumerated() {
                    let image = try #require(CheckMascotAssets.menuBarImage(for: .neutral, characterID: id))
                    var rect = CGRect(x: 0, y: 0, width: s, height: s)
                    let cg = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
                    bar.draw(cg, in: CGRect(x: gap + i * (s + gap), y: 3 * scale, width: s, height: s))
                }
                try Self.write(try #require(bar.makeImage()), "menubar-\(label)@\(scale)x-pepero-isul-choco-aing.png")
            }
        }
        for mood in [CheckMascotAssets.Mood.neutral, .negative] {
            let url = try #require(CheckMascotAssets.portraitURL(for: mood, characterID: Self.id))
            let raw = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            try Self.write(try V0359Rainbow3DTests.onBackground(raw, light), "portrait-\(url.lastPathComponent)")
        }
    }
}

// MARK: - 릴리스 게이트용 못(0.3.77 출시 꾸러미가 게이트 필터에 이 이름을 넣는다)

/// 빼빼로를 싣는 맥 판은 **번들만으로** 빼빼로를 그릴 수 있어야 하고(능력 번호 6) — 그렇지 않으면 맥은 조용히 5 에 머물고 11-11 에 아무도
/// 빼빼로 선물을 못 받는다(미리 구현 검토 cRev ③). 게이트가 이 스위트 이름(`V0377PeperoReleaseGateTests`)으로 고른다.
@MainActor
@Suite struct V0377PeperoReleaseGateTests {
    @Test("릴리스 게이트: 번들 drawable 에 aing_pepero · 상점 능력 번호 6 · 빼빼로 선물을 받을 수 있다")
    func bundledPeperoAndProtocolSix() {
        #expect(WorkTimerStore.bundledDrawableCharacterIDs.contains(CharacterCatalog.peperoAingID),
                "번들 drawable 에 aing_pepero 가 없다 — 그림(판 · 초상 두 장)이 번들에 안 실렸다 \(WorkTimerStore.bundledDrawableCharacterIDs)")
        // v0.3.78: 흑우가 얹혀 7 이 된다(누적) — 이 게이트의 뜻은 '빼빼로 선물을 받을 수 있는 6 이상'이다.
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) >= ShopWire.peperoProtocol)
        let store = V0317ShopTests.plainStore()
        #expect(store.shopProtocolVersion >= ShopWire.peperoProtocol, "스토어 능력 번호 \(store.shopProtocolVersion) — 빼빼로 선물이 안 온다")
        #expect(ShopWire.supportsPeperoGift(protocolVersion: store.shopProtocolVersion))
        #expect(CharacterGiftKind.pepero.isSupported(protocolVersion: store.shopProtocolVersion))
    }
}
