import AppKit
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// v0.3.78 — 흑우 아잉이(조각 20개로만 바꾸는 캐릭터 · 시안 U9 '네온'). 대표 결정 2026-11-06(#d_V0mJ363LONEW · #d_rzIRawYYHrwS · #d_CtPxrfwWATBZ).
//  ① 코어: 내장 여덟째 · 마감 .hwoo(희귀 아님) · 뽑기 전용(루비로 안 팖) ⊃ 조각 교환 전용 · 능력 번호 7(누적) · 확률표에서 0% 줄 빼기 ·
//     교환 목록에 흑우(금 · 무지개 다음) · 얻는 길 문구("조각 20개로 교환" · "조각 교환으로만 얻을 수 있어요").
//  ② 맥 3D: 실제 앱 씬에 마감이 선다(무지개 합성 디퓨즈 + 네온 셰이더 + ckShadeMap + 표식) · 렌더가 짙은 몸 + 왼쪽 하늘색 · 오른쪽 분홍 테 ·
//     엔진 교체 왕복 · 그릴 수 있다 → 능력 번호 7 · 초상 URL.
// 증거 PNG: `CHECK_V0378_HWOO_EVIDENCE_DIR=<폴더>` 를 주면 앱 구도 정면 · 3/4 를 떨군다(창 없음).

@Suite struct V0378HwooCoreTests {
    /// 맥 소스 트리에 흑우 초상 두 장이 있는가(생성기 `scripts/make-hwoo-aing.swift` 결과를 커밋한다 — 이 판에선 늘 참).
    static var macHwooPortraitsInSourceTree: Bool {
        HwooAingArt.portraitResourceNames.allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }

    /// 맥 소스 트리에 흑우 그림이 다 있는가(초상 두 장 + 3D 마감이 같이 쓰는 무지개 밝기 맵).
    static var macHwooArtInSourceTree: Bool {
        HwooAingArt.requiredResourceNames(for: .mac).allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }

    @Test("카탈로그: 흑우는 내장 여덟째(맨 끝) · id aing_hwoo · 마감 .hwoo · 희귀 아님 · 루비로 안 판다 · 조각 교환 전용")
    func catalog() {
        #expect(CharacterCatalog.builtIns.last?.id == "aing_hwoo")
        #expect(CharacterCatalog.builtIns.count == 8)
        #expect(CharacterCatalog.builtInHwooAing.displayName == "흑우 아잉이")
        #expect(CharacterManifest.Finish(characterID: "aing_hwoo") == .hwoo)
        #expect(!CharacterManifest.Finish.hwoo.isRare && !CharacterManifest.Finish.hwoo.isCake)
        #expect(CharacterCatalog.isGachaOnlyBuiltIn("aing_hwoo") && CharacterCatalog.isShardOnlyBuiltIn("aing_hwoo"))
        #expect(!CharacterCatalog.isShardOnlyBuiltIn("aing_gold") && !CharacterCatalog.isShardOnlyBuiltIn("aing_rainbow"))
        #expect(!CharacterCatalog.isGiftOnlyBuiltIn("aing_hwoo"))
        #expect(CharacterCatalog.gachaOnlyBuiltInIDs == ["aing_gold", "aing_rainbow", "aing_hwoo"])
        #expect(!GachaRules.isNeverExchangeable("aing_hwoo"))
    }

    @Test("능력 번호: 여기까지 전부 + 흑우를 그리면 7 · 흑우가 없으면 6 · 흑우만 있고 빼빼로가 없으면 5(누적 — 건너뛰어 말하지 않는다)")
    func protocolSeven() {
        let all = ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "aing_isul", "aing_pepero", "aing_hwoo"]
        #expect(ShopWire.hwooProtocol == 7)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all) == 7)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all.filter { $0 != "aing_hwoo" }) == 6)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all.filter { $0 != "aing_pepero" }) == 5)
    }

    @Test("고르기: 흑우는 서버가 흑우를 말하거나(상점 행 · 교환 목록) · 가졌거나 · 입었을 때만 선다 — 로드 전 관용은 없다(흑우 행을 모르는 서버의 잠긴 유령 카드)")
    func pickerListsHwooOnlyWhenTheServerKnowsIt() {
        let hwoo = CharacterCatalog.hwooAingID
        let row = ShopCharacterRow(id: hwoo, price: 1001, owned: false, gachaOnly: true)
        #expect(!WorkTimerStore.isCharacterListed(hwoo, shopLoaded: false, gachaAvailable: false, owned: [], rows: []), "로드 전")
        #expect(!WorkTimerStore.isCharacterListed(hwoo, shopLoaded: true, gachaAvailable: false, owned: [], rows: []), "흑우를 모르는 서버")
        #expect(WorkTimerStore.isCharacterListed(hwoo, shopLoaded: true, gachaAvailable: true, owned: [], rows: []), "교환 목록에 흑우")
        #expect(WorkTimerStore.isCharacterListed(hwoo, shopLoaded: true, gachaAvailable: false, owned: [], rows: [row]), "서버 행")
        #expect(WorkTimerStore.isCharacterListed(hwoo, shopLoaded: true, gachaAvailable: false, owned: [hwoo], rows: []), "가짐")
        #expect(WorkTimerStore.isCharacterListed(hwoo, shopLoaded: false, gachaAvailable: false, owned: [], rows: [], wearing: hwoo), "입음")
        // 기준선: 금 · 무지개의 관용은 그대로다.
        #expect(WorkTimerStore.isCharacterListed("aing_gold", shopLoaded: false, gachaAvailable: false, owned: [], rows: []))
        #expect(WorkTimerStore.isCharacterListed("aing_rainbow", shopLoaded: true, gachaAvailable: true, owned: [], rows: []))
    }

    static func info(withHwoo: Bool = true, shards: Int? = 7) -> GachaInfo {
        var odds = [GachaOddsEntry(characterID: "aing_gold", percent: 3), GachaOddsEntry(characterID: "aing_rainbow", percent: 2),
                    GachaOddsEntry(characterID: "fox", percent: 95)]
        var costs = ["aing_gold": 20, "aing_rainbow": 20, "fox": 2]
        if withHwoo {
            odds.insert(GachaOddsEntry(characterID: "aing_hwoo", percent: 0), at: 0)   // 서버는 sort 0 — 맨 앞에 0 으로 싣는다
            costs["aing_hwoo"] = 20
        }
        return GachaInfo(price: 50, shards: shards, odds: odds, shardCosts: costs)
    }

    @Test("확률표: 0% 줄(흑우)은 뽑기 확률 표에 서지 않는다 · 합은 100 그대로(완전한 확률표) · 다른 줄은 순서 그대로")
    func oddsDropsTheZeroRow() {
        let info = Self.info()
        #expect(info.hasCompleteOdds)
        let rows = GachaRules.oddsRows(info: info, shopRows: [], displayName: { _ in nil })
        #expect(rows.map(\.characterID) == ["aing_gold", "aing_rainbow", "fox"])
    }

    @Test("교환 목록: 흑우가 금 · 무지개 다음에 선다 · 조각 7 → 13개 모자람 · 20이면 교환 가능 · 가지면 보유")
    func exchangeRowsIncludeHwoo() {
        let rows = GachaRules.exchangeRows(info: Self.info(), ownedIDs: [], displayName: { _ in nil })
        #expect(rows.prefix(3).map(\.characterID) == ["aing_gold", "aing_rainbow", "aing_hwoo"])
        #expect(rows.first { $0.characterID == "aing_hwoo" }?.availability == .short(cost: 20, missing: 13))
        #expect(GachaRules.exchangeRows(info: Self.info(shards: 20), ownedIDs: [], displayName: { _ in nil })
                    .first { $0.characterID == "aing_hwoo" }?.availability == .available(cost: 20))
        #expect(GachaRules.exchangeRows(info: Self.info(), ownedIDs: ["aing_hwoo"], displayName: { _ in nil })
                    .first { $0.characterID == "aing_hwoo" }?.availability == .owned)
        #expect(GachaRules.exchangeRows(info: Self.info(), ownedIDs: [], displayName: { _ in nil })
                    .first { $0.characterID == "aing_hwoo" }?.name == "흑우 아잉이")
    }

    @Test("문구: 흑우의 얻는 길은 '조각 20개로 교환' · 안내는 '조각 교환으로만' — 금 · 무지개는 그대로 '뽑기 또는 …' · '뽑기나 …'")
    func copy() {
        #expect(GachaText.shardOnlyPrice(shardCost: 20) == "조각 20개로 교환")
        #expect(GachaText.shardOnlyPrice(shardCost: nil) == "조각 교환 전용")
        #expect(GachaText.acquireHint(for: "aing_hwoo") == "조각 교환으로만 얻을 수 있어요")
        #expect(GachaText.acquireHint(for: "aing_gold") == GachaText.gachaOnlyHint)
        #expect(GachaText.gachaOnlyPrice(shardCost: 20) == "뽑기 또는 조각 20개")
        #expect(ShopCardLine.gachaOnly.tooltip(name: "흑우 아잉이", owned: false, acquireHint: GachaText.acquireHint(for: "aing_hwoo"))
                == "흑우 아잉이 — 조각 교환으로만 얻을 수 있어요")
    }
}

@MainActor
@Suite struct V0378HwooMac3DTests {
    static let hwoo = CharacterCatalog.builtInHwooAing
    static let appSize = CGSize(width: 280, height: 340)
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_V0378_HWOO_EVIDENCE_DIR"]

    @Test("흑우 씬: 얼굴 = 무지개 합성 디퓨즈 + 네온 셰이더 + ckShadeMap · 표식 · 장식 · 후광 없음 — 다른 아잉 변형엔 없다")
    func finishIsApplied() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.hwoo)
        let character = try V0354GoldAing3DTests.character(scene)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        #expect(material.shaderModifiers?[.fragment] == HwooAingFinish.HwooBody.shaderModifiers[.fragment], "네온 셰이더가 안 걸렸다")
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        #expect(RainbowAingFinish.lavenderOriginal(ofRainbowFace: face) != nil, "디퓨즈가 무지개 합성이 아니다 — 감은 눈 갈래를 못 탄다")
        let shade = try #require(material.value(forKey: HwooAingFinish.HwooBody.shadeMapKey) as? SCNMaterialProperty)
        #expect(SleepEyeExplore.cgImage(from: shade.contents) === RainbowAingFinish.shadeImage())
        #expect(HwooAingFinish.isHwoo(character))
        #expect(character.simdPosition == .zero)
        #expect(scene.rootNode.childNode(withName: RainbowAingFinish.haloNodeName, recursively: true) == nil, "흑우에 무지개 후광이 섰다")
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInRainbowAing, CharacterCatalog.builtInIsulAing] {
            #expect(!HwooAingFinish.isHwoo(try V0354GoldAing3DTests.character(try V0354GoldAing3DTests.scene(other))), "\(other.id) 에 흑우 표식")
        }
    }

    @Test("렌더: 정면 옆구리가 짙은 남색 · 왼쪽 가장자리 하늘색 · 오른쪽 가장자리 분홍(셰이더 없으면 라벤더)")
    func rendersNeon() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.hwoo)
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
            let c = V0359Rainbow3DTests.averageColor(px, width: w, at: pixel(local), radius: 1)
            return V0359RainbowArtTests.oklch(c.0, c.1, c.2)
        }
        let belly = color(SCNVector3(0.0, -0.35, 0.50))          // 배 가운데(얼굴 상자 밖 · 시선과 마주) — 짙다
        // 가장자리 바로 안쪽(실루엣 테): 몸 왼쪽 · 오른쪽 끝에서 조금 안(배 높이).
        let leftRim = color(SCNVector3(-0.57, -0.15, 0.12))
        let rightRim = color(SCNVector3(0.57, -0.15, 0.12))
        print(String(format: "[v0378-hwoo] 배 L %.2f C %.3f h %.0f° · 왼 테 L %.2f C %.3f h %.0f° · 오른 테 L %.2f C %.3f h %.0f°",
                     belly.L, belly.C, belly.h, leftRim.L, leftRim.C, leftRim.h, rightRim.L, rightRim.C, rightRim.h))
        #expect(belly.L < 0.40, "배가 짙지 않다(\(belly))")
        #expect(V0359RainbowArtTests.hueDistance(leftRim.h, 210) < 45 && leftRim.C > 0.05, "왼쪽 테가 하늘색이 아니다(\(leftRim))")
        #expect(V0359RainbowArtTests.hueDistance(rightRim.h, 350) < 45 && rightRim.C > 0.05, "오른쪽 테가 분홍이 아니다(\(rightRim))")
        let plain = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize, modifiers: .some(nil)))
        let c = V0359Rainbow3DTests.averageColor(plain, width: w, at: pixel(SCNVector3(0.0, -0.35, 0.50)), radius: 1)
        #expect(V0359RainbowArtTests.oklch(c.0, c.1, c.2).L > 0.55, "기준선: 셰이더 없는 배가 밝은 라벤더가 아니다")
        if Self.evidenceDirectory != nil { try Self.write(image, "hwoo-front.png") }
    }

    @Test("엔진은 흑우를 가른다 — 아잉 → 흑우 교체(울트라 경로)에 셰이더 · 표식이 따라오고 원복하면 사라진다")
    func engineSwapsHwoo() throws {
        let engine = ReactionEngine()
        let scene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let stashed = try #require(engine.swapCharacter(to: Self.hwoo, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.hwooAingID, "흑우로 갈아입었는데 \(engine.currentCharacterID)")
        #expect(try V0359Rainbow3DTests.faceMaterial(scene).shaderModifiers?[.fragment] == HwooAingFinish.HwooBody.shaderModifiers[.fragment])
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
    }

    @Test("그릴 수 있다: 번들 그대로 흑우가 든다(초상 두 장 + 밝기 맵) · 하나만 빠져도 못 그린다 · 능력 번호 7 · 초상 URL · 192²")
    func drawableAndProtocolSeven() throws {
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(CharacterCatalog.hwooAingID), "\(drawable)")
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.hwooProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) == ShopWire.hwooProtocol)
        #expect(HwooAingFinish.isDrawable())
        #expect(HwooAingArt.requiredResourceNames(for: .mac) == ["aing_hwoo-neutral", "aing_hwoo-negative", "aing_rainbow-shade"])
        for missing in HwooAingArt.requiredResourceNames(for: .mac) {
            #expect(!HwooAingArt.isDrawable(on: .mac) { $0 != missing }, "\(missing) 가 빠져도 그릴 수 있다고 한다")
        }
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.hwooAingID, mood: .neutral)?.lastPathComponent == "aing_hwoo-neutral.png")
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.hwooAingID, mood: .negative)?.lastPathComponent == "aing_hwoo-negative.png")
        #expect(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.hwooAingID)?.size.width == 192)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != CharacterCatalog.hwooAingID }) == ShopWire.peperoProtocol)
    }

    static func write(_ image: CGImage, _ name: String) throws {
        let dir = URL(fileURLWithPath: try #require(Self.evidenceDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    @Test("증거: 앱 구도 3/4", .enabled(if: evidenceDirectory != nil))
    func writeEvidence() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.hwoo)
        try V0355GoldHaloYawTests.facing(scene).eulerAngles = SCNVector3(0, CGFloat(35.0 * .pi / 180), 0)
        try Self.write(try V0359Rainbow3DTests.render(scene, size: Self.appSize), "hwoo-three-quarter.png")
    }
}
