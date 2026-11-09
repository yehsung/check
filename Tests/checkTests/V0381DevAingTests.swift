import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 개발에 찌든 아잉이(제보 11-08 · 시안 D2 '후드티 개발자' — 대표 결정 2026-11-10 #d_NuLS5imieQds).
//  ① 코어: 내장 열째 · 마감 .dev(희귀 · 선물 · 뽑기 · 조각 전용 아님) · 능력 번호 9(누적) · 고르기는 서버가 행을 말할 때만.
//  ② 맥 3D: 실제 앱 씬에 마감이 선다(무지개 합성 디퓨즈 + 후드 셰이더 + ckShadeMap + 끈 장식 + 표식) · 렌더(배 = 회색 후드 · 얼굴 = 보라) ·
//     엔진 교체 왕복 · 그릴 수 있다 → 능력 번호 9 · 초상 URL.
// 증거 PNG: `CHECK_DEV_AING_EVIDENCE_DIR=<폴더>` — 정면 · 3/4 · 뒤 · 감은 눈 · 울트라(아잉과 나란히).

@Suite struct V0381DevAingCoreTests {
    static var macDevPortraitsInSourceTree: Bool { DevAingArt.portraitResourceNames.allSatisfy(V0354CoreArtBaseline.macResourceExists) }
    static var macDevArtInSourceTree: Bool { DevAingArt.requiredResourceNames(for: .mac).allSatisfy(V0354CoreArtBaseline.macResourceExists) }

    @Test("카탈로그: 개발 아잉이는 내장 열째(맨 끝) · id aing_dev · 마감 .dev · 희귀 · 케이크 · 뽑기 · 선물 · 조각 전용 아님")
    func catalog() {
        #expect(CharacterCatalog.builtIns.last?.id == "aing_dev")
        #expect(CharacterCatalog.builtIns.count == 10)
        #expect(CharacterCatalog.builtInDevAing.displayName == "개발에 찌든 아잉이")
        #expect(CharacterManifest.Finish(characterID: "aing_dev") == .dev)
        #expect(!CharacterManifest.Finish.dev.isRare && !CharacterManifest.Finish.dev.isCake)
        #expect(!CharacterCatalog.isGachaOnlyBuiltIn("aing_dev") && !CharacterCatalog.isGiftOnlyBuiltIn("aing_dev") && !CharacterCatalog.isShardOnlyBuiltIn("aing_dev"))
        #expect(CharacterCatalog.isDevAing("aing_dev") && !CharacterCatalog.isDevAing("aing_dev ") && !CharacterCatalog.isDevAing("aing"))
    }

    @Test("능력 번호: 여기까지 전부 + 개발 아잉이를 그리면 9 · 없으면 8 · 개발만 있고 루비가 없으면 7(누적)")
    func protocolNine() {
        let all = ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "aing_isul", "aing_pepero", "aing_hwoo", "aing_ruby", "aing_dev"]
        #expect(ShopWire.devProtocol == 9)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all) == 9)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all.filter { $0 != "aing_dev" }) == 8)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: all.filter { $0 != "aing_ruby" }) == 7)
    }

    @Test("고르기: 개발 아잉이는 서버가 행을 말하거나 · 가졌거나 · 입었을 때만 선다 — 로드 전 관용 · 뽑기 관용은 없다")
    func pickerListsOnlyWhenServerKnows() {
        let id = CharacterCatalog.devAingID
        let row = ShopCharacterRow(id: id, price: 300, owned: false)
        #expect(!WorkTimerStore.isCharacterListed(id, shopLoaded: false, gachaAvailable: false, owned: [], rows: []))
        #expect(!WorkTimerStore.isCharacterListed(id, shopLoaded: true, gachaAvailable: true, owned: [], rows: []))
        #expect(WorkTimerStore.isCharacterListed(id, shopLoaded: true, gachaAvailable: false, owned: [], rows: [row]))
        #expect(WorkTimerStore.isCharacterListed(id, shopLoaded: true, gachaAvailable: false, owned: [id], rows: []))
        #expect(WorkTimerStore.isCharacterListed(id, shopLoaded: false, gachaAvailable: false, owned: [], rows: [], wearing: id))
    }

    @Test("셰이더 글자: 후드 · 주머니 · 다크서클 · 눈꺼풀 덮개(ckLid) · 속눈썹은 눈 그림 텍셀에만(1 − β) · 얼굴 끈 구멍 높이")
    func shaderText() {
        let f = DevAingShader.fragment()
        #expect(f.contains("float ckLid = 0.0;") && f.contains("ckOut = mix(ckOut, ckLidCol.x < 0.0 ? ckCc : ckLidCol"))
        #expect(f.contains("lineA *= clamp(1.0 - ckBeta, 0.0, 1.0);"), "속눈썹 선이 감은 눈에서도 남는다")
        #expect(DevAingShader.fragment(faceOff: true).contains("bool ckInFace = false;"))
        #expect(DevAingArt.stringTopY < 0.30 - 0.36 + 0.05, "끈이 얼굴 구멍(가운데 0.30 · 세로 반지름 0.36) 아래 끝 근처가 아니다")
    }
}

@MainActor
@Suite struct V0381DevAingMac3DTests {
    static let dev = CharacterCatalog.builtInDevAing
    static let appSize = CGSize(width: 280, height: 340)
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_DEV_AING_EVIDENCE_DIR"]

    static func bodyGeometry(_ scene: SCNScene) throws -> SCNGeometry {
        var found: SCNGeometry?
        scene.rootNode.enumerateHierarchy { node, stop in
            guard let g = node.geometry, !AingDecor.isDecor(node),
                  g.materials.first?.diffuse.contents.map({ CFGetTypeID($0 as CFTypeRef) == CGImage.typeID }) ?? false else { return }
            if node.name?.hasPrefix("check.") == true { return }
            found = g; stop.pointee = true
        }
        return try #require(found)
    }

    @Test("씬: 얼굴 = 무지개 합성 + 후드 셰이더 + ckShadeMap · 끈 장식 둘(장식 판정) · 표식 — 다른 아잉 변형엔 없다")
    func finishIsApplied() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.dev)
        let character = try V0354GoldAing3DTests.character(scene)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        #expect(material.shaderModifiers?[.fragment] == DevAingShader.fragment(), "후드 셰이더가 안 걸렸다")
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        #expect(RainbowAingFinish.lavenderOriginal(ofRainbowFace: face) != nil)
        let shade = try #require(material.value(forKey: DevAingShader.shadeMapKey) as? SCNMaterialProperty)
        #expect(SleepEyeExplore.cgImage(from: shade.contents) === RainbowAingFinish.shadeImage())
        #expect(DevAingFinish.isDev(character))
        let decor = try #require(scene.rootNode.childNode(withName: DevAingFinish.decorNodeName, recursively: true))
        #expect(decor.childNodes.count == 2 && AingDecor.isDecor(decor.childNodes[0]))
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInRubyAing, CharacterCatalog.builtInHwooAing] {
            let s = try V0354GoldAing3DTests.scene(other)
            #expect(!DevAingFinish.isDev(try V0354GoldAing3DTests.character(s)), "\(other.id) 에 개발 표식")
            #expect(s.rootNode.childNode(withName: DevAingFinish.decorNodeName, recursively: true) == nil, "\(other.id) 에 끈")
        }
    }

    @Test("렌더: 배(주머니 위)는 회색 후드(채도 낮음) · 이마(얼굴 구멍 안)는 보라 — 셰이더 없으면 배도 보라")
    func rendersHoodie() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.dev)
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
        func oklch(_ img: [UInt8], _ local: SCNVector3) -> (L: Double, C: Double, h: Double) {
            let c = V0359Rainbow3DTests.averageColor(img, width: w, at: pixel(local), radius: 1)
            return V0359RainbowArtTests.oklch(c.0, c.1, c.2)
        }
        let belly = oklch(px, SCNVector3(0.20, -0.20, 0.66))
        let brow = oklch(px, SCNVector3(0.0, 0.58, 0.48))
        print(String(format: "[dev-aing] 배 L %.2f C %.3f h %.0f° · 이마 L %.2f C %.3f h %.0f°", belly.L, belly.C, belly.h, brow.L, brow.C, brow.h))
        #expect(belly.C < 0.04, "배가 회색 후드가 아니다(\(belly))")
        #expect(brow.C > 0.05 && V0359RainbowArtTests.hueDistance(brow.h, 295) < 40, "이마가 보라가 아니다(\(brow))")
        let plain = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize, modifiers: .some(nil)))
        #expect(oklch(plain, SCNVector3(0.20, -0.20, 0.66)).C > 0.04, "기준선: 셰이더 없는 배가 회색이다")
        if Self.evidenceDirectory != nil { try Self.write(image, "dev-front.png") }
    }

    @Test("엔진은 개발 아잉이를 가른다 — 아잉 → 개발 교체(울트라 경로)에 셰이더 · 끈 · 표식이 따라오고 원복하면 사라진다")
    func engineSwaps() throws {
        let engine = ReactionEngine()
        let scene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let stashed = try #require(engine.swapCharacter(to: Self.dev, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.devAingID, "\(engine.currentCharacterID)")
        #expect(scene.rootNode.childNode(withName: DevAingFinish.decorNodeName, recursively: true) != nil)
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
    }

    @Test("그릴 수 있다: 번들 그대로 개발 아잉이가 든다 · 하나만 빠져도 못 그린다 · 능력 번호 9 · 초상 URL · 192²")
    func drawableAndProtocolNine() throws {
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(CharacterCatalog.devAingID), "\(drawable)")
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.devProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) == ShopWire.devProtocol)
        #expect(DevAingFinish.isDrawable())
        #expect(DevAingArt.requiredResourceNames(for: .mac) == ["aing_dev-neutral", "aing_dev-negative", "aing_rainbow-shade"])
        for missing in DevAingArt.requiredResourceNames(for: .mac) {
            #expect(!DevAingArt.isDrawable(on: .mac) { $0 != missing }, "\(missing) 가 빠져도 그릴 수 있다고 한다")
        }
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.devAingID, mood: .neutral)?.lastPathComponent == "aing_dev-neutral.png")
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.devAingID, mood: .negative)?.lastPathComponent == "aing_dev-negative.png")
        #expect(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.devAingID)?.size.width == 192)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != CharacterCatalog.devAingID }) == ShopWire.rubyProtocol)
    }

    static func write(_ image: CGImage, _ name: String) throws {
        let dir = URL(fileURLWithPath: try #require(Self.evidenceDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    @Test("증거: 정면 · 3/4 · 뒤 · 감은 눈 · 울트라(아잉 나란히)", .enabled(if: evidenceDirectory != nil))
    func writeEvidence() throws {
        let big = CGSize(width: 560, height: 680)
        for (tag, manifest) in [("dev", Self.dev), ("aing", CharacterCatalog.builtInAing)] {
            let scene = try V0354GoldAing3DTests.scene(manifest)
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-1-front.png")
            let facing = try V0355GoldHaloYawTests.facing(scene)
            facing.eulerAngles = SCNVector3(0, CGFloat(35.0 * .pi / 180), 0)
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-2-three-quarter.png")
            facing.eulerAngles = SCNVector3(0, CGFloat.pi, 0)
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-3-back.png")
            facing.eulerAngles = SCNVector3(0, 0, 0)
            let material = try V0359Rainbow3DTests.faceMaterial(scene)
            let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
            let closed = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: face, geometry: try Self.bodyGeometry(scene),
                                                                               character: try V0354GoldAing3DTests.character(scene)))
            material.diffuse.contents = closed
            for (name, _) in CheckCharacter3DScene.closedEyeAnchors { scene.rootNode.childNode(withName: name, recursively: true)?.isHidden = false }
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-4-closed-eyes.png")
            let engine = ReactionEngine()
            let from = try V0354GoldAing3DTests.scene(tag == "dev" ? CharacterCatalog.builtInAing : Self.dev)
            engine.attach(node: try V0354GoldAing3DTests.wrapper(from), sceneRoot: from.rootNode, view: nil)
            _ = try #require(engine.swapCharacter(to: manifest, in: from))
            try Self.write(try V0359Rainbow3DTests.render(from, size: big), "\(tag)-5-ultra-swap.png")
        }
    }
}

// MARK: - 얻는 길: 도전 미션 '누적 근무 100시간'(대표 #d_OwYy6Avg5alV) — 서버 20261111120000

/// 서버 응답 모양(`achievements__character_status` · `achievement_character_claim`) — 하네스가 같은 모양을 잰다(t1_dev_mission.sql 2) · 5)).
enum V0381MissionFixture {
    static func characterRow(progress: Int, achieved: Bool, claimed: Bool, claimable: Bool) -> String {
        """
        {"key": "work100", "title": "누적 근무 100시간", "detail": "지금까지 근무한 시간을 모두 셉니다", "character_id": "aing_dev",
         "reward": 0, "target": 100, "progress": \(progress), "progress_seconds": \(progress * 3600), "achieved": \(achieved),
         "claimed": \(claimed), "claimable": \(claimable), "achieved_at_ms": null, "claimed_at_ms": \(claimed ? "1789000000000" : "null"),
         "sort": 140}
        """
    }

    static func status(character: String?, extra: String = "") -> String {
        """
        {"launch_at_ms": 1781234567890,
         "missions": [{"key": "todo3", "series": "todo3", "tier": 1, "title": "할 일 3개 이상 등록하기", "detail": "", "reward": 20,
                       "target": 3, "progress": 3, "achieved": true, "claimed": false, "achieved_at_ms": 1, "claimed_at_ms": null, "sort": 20}],
         "claimable_count": 1, "claimable_ruby": 20, "ruby_balance": 100, "server_now_ms": 1789000000000, "streak_days": 3
         \(character.map { ", \"character_missions\": [\($0)]" } ?? "")\(extra)}
        """
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(json.utf8))
    }
}

@Suite struct V0381DevAingMissionTests {
    @Test("응답: character_missions 한 줄 → 캐릭터 줄(보상 루비 0 · 캐릭터 aing_dev) · 루비 미션은 그대로 · 키 없는 옛 서버는 빈 목록")
    func decodesCharacterMissions() throws {
        let status = try V0381MissionFixture.decode(AchievementStatus.self,
            V0381MissionFixture.status(character: V0381MissionFixture.characterRow(progress: 100, achieved: true, claimed: false, claimable: true)))
        let row = try #require(status.characterMissions.first)
        #expect(status.characterMissions.count == 1 && status.missions.count == 1)
        #expect(row.key == DevAingMission.key && row.characterID == CharacterCatalog.devAingID && row.reward == 0)
        #expect(row.title == "누적 근무 100시간" && row.target == 100 && row.progress == 100 && row.state == .claimable)
        // 받을 것 = 루비 1 + 캐릭터 1(배지 · 절 머리) · 루비 합은 루비 줄만 · [모두 받기]의 실패 표시 대상은 루비 줄만.
        #expect(status.claimableCount == 2 && status.claimableRuby == 20 && status.claimable.map(\.key) == ["todo3"])
        // 절의 줄: 루비 계열 줄 뒤에 캐릭터 줄.
        #expect(status.sectionRows.map(\.key) == ["todo3", "work100"])
        let old = try V0381MissionFixture.decode(AchievementStatus.self, V0381MissionFixture.status(character: nil))
        #expect(old.characterMissions.isEmpty && old.claimableCount == 1 && old.sectionRows.map(\.key) == ["todo3"])
        // 캐릭터 칸이 빠진 줄은 버린다(아잉 그림의 '캐릭터 보상'을 세우지 않는다) — 나머지는 산다.
        let broken = try V0381MissionFixture.decode(AchievementStatus.self, V0381MissionFixture.status(
            character: #"{"key": "x", "title": "모양 틀림", "target": 1}"#))
        #expect(broken.characterMissions.isEmpty && broken.missions.count == 1)
    }

    @Test("진행 · 받음: 99시간은 진행 중(99/100시간) · 받은 줄은 받음 · 받음은 늦게 온 옛 응답에 되돌아가지 않는다")
    func statesAndStickyClaim() throws {
        let progress = try V0381MissionFixture.decode(AchievementStatus.self,
            V0381MissionFixture.status(character: V0381MissionFixture.characterRow(progress: 99, achieved: false, claimed: false, claimable: false)))
        let row = try #require(progress.characterMissions.first)
        #expect(row.state == .inProgress && AchievementCopy.count(row) == "99/100시간" && progress.claimableCount == 1)
        let claimed = try V0381MissionFixture.decode(AchievementStatus.self,
            V0381MissionFixture.status(character: V0381MissionFixture.characterRow(progress: 100, achieved: true, claimed: true, claimable: false)))
        #expect(claimed.characterMissions.first?.state == .claimed)
        let stale = try V0381MissionFixture.decode(AchievementStatus.self,
            V0381MissionFixture.status(character: V0381MissionFixture.characterRow(progress: 100, achieved: true, claimed: false, claimable: true)))
        #expect(stale.merged(over: claimed).characterMissions.first?.state == .claimed, "받은 캐릭터 줄에 [받기]가 다시 섰다")
        #expect(AchievementSectionState.make(status: stale, unavailable: false, failed: false)
                == .loaded(rows: stale.sectionRows, claimableCount: 2))
    }

    @Test("받기 요청 · 응답: {p_key, p_protocol} 둘 다 싣는다 · status ok + claimed_now 캐릭터 · 모르는 어휘는 nil")
    func claimWire() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        let body = try #require(String(data: try encoder.encode(AchievementCharacterClaimRequest(key: DevAingMission.key, protocolNumber: 9)),
                                       encoding: .utf8))
        #expect(body == #"{"p_key":"work100","p_protocol":9}"#)
        #expect(SupabaseWorkService.achievementCharacterClaimPath == "/rest/v1/rpc/achievement_character_claim")
        let ok = try V0381MissionFixture.decode(AchievementCharacterClaimResponse.self, V0381MissionFixture.status(
            character: V0381MissionFixture.characterRow(progress: 100, achieved: true, claimed: true, claimable: false),
            extra: #", "status": "ok", "claimed_now": [{"key": "work100", "title": "누적 근무 100시간", "character_id": "aing_dev"}]"#))
        #expect(ok.outcome == .ok && ok.claimedCharacterIDs == ["aing_dev"] && ok.status.characterMissions.first?.claimed == true)
        // 캐릭터 받기의 claimed_now 는 루비가 아니다 — 루비 연출 합은 0.
        #expect(ok.status.claimedNowRuby == 0)
        for (raw, expected) in [("already", AchievementCharacterClaimResponse.Outcome.already), ("not_met", .notMet), ("hidden", .hidden),
                                ("unknown_key", .unknownKey), ("needs_update", .needsUpdate)] {
            let r = try V0381MissionFixture.decode(AchievementCharacterClaimResponse.self,
                                                    V0381MissionFixture.status(character: nil, extra: ", \"status\": \"\(raw)\", \"claimed_now\": []"))
            #expect(r.outcome == expected && r.claimedCharacterIDs.isEmpty)
        }
        let unknown = try V0381MissionFixture.decode(AchievementCharacterClaimResponse.self, V0381MissionFixture.status(character: nil, extra: #", "status": "weird""#))
        #expect(unknown.outcome == nil)
    }

    @Test("상점: 개발 행(gacha_only 표식)은 뽑기 전용이 아니다 · 못 산다 · 안 가지면 '미션 보상' 잠긴 칸 · 가지면 보유 칸")
    func shopCell() {
        let row = ShopCharacterRow(id: "aing_dev", price: 2004, owned: false, gachaOnly: true, giftOnly: false)
        #expect(row.isMissionReward && !row.isGachaOnly && !row.isGiftOnly && !row.isPurchasable)
        #expect(!WorkTimerStore.isGachaOnly("aing_dev", rows: [row]) && !WorkTimerStore.isGiftOnly("aing_dev", rows: [row]))
        #expect(ShopCardLine.of(id: "aing_dev", owned: false, rows: [row]) == .missionLocked)
        #expect(ShopCardLine.of(id: "aing_dev", owned: true, rows: [row]) == .price)
        #expect(ShopCardLine.missionLocked.tooltip(name: "개발에 찌든 아잉이", owned: false)
                == "개발에 찌든 아잉이 — 누적 미션 '누적 근무 100시간'을 채우면 받아요")
        #expect(CheckCharacterPanel.lockedLabel("aing_dev", name: "개발에 찌든 아잉이")
                == "개발에 찌든 아잉이 잠김 — 누적 미션 '누적 근무 100시간'을 채우면 받아요")
        // 다른 뽑기 전용(황금)은 그대로 뽑기 전용이다.
        #expect(WorkTimerStore.isGachaOnly("aing_gold", rows: []))
    }
}

/// 미션 줄 · 상점 칸 렌더(창 없음 — ImageRenderer). 증거 PNG 는 `CHECK_DEV_AING_EVIDENCE_DIR`.
@MainActor
@Suite(.serialized) struct V0381DevAingMissionRenderTests {
    static func bitmap(_ view: some View) throws -> NSBitmapImageRep {
        try #require(CheckRenderSettle.bitmap(view.fixedSize(), scale: 2))
    }

    static func mission(progress: Int, achieved: Bool, claimed: Bool) throws -> AchievementStatus.Mission {
        try #require(try V0381MissionFixture.decode(AchievementStatus.self, V0381MissionFixture.status(
            character: V0381MissionFixture.characterRow(progress: progress, achieved: achieved, claimed: claimed, claimable: achieved && !claimed)))
            .characterMissions.first)
    }

    static func row(_ mission: AchievementStatus.Mission, burst: Bool = false) throws -> NSBitmapImageRep {
        var context = MissionClaimContext()
        if burst {
            context.bursts = [MissionClaimBurst.achievementTarget(series: mission.series):
                                MissionClaimBurst(serial: 1, target: MissionClaimBurst.achievementTarget(series: mission.series), amount: 0,
                                                  characterID: mission.characterID)]
            context.frozenBurstProgress = 0.45
        }
        return try bitmap(AchievementRowView(mission: mission).frame(width: 292).background(Color.black)
            .environment(\.missionClaim, context)
            .environment(\.colorScheme, .dark))
    }

    @Test("줄: 받을 수 있음 → [받기 + 개발 아잉이 초상](그라데이션) · 진행 중 → 칩(초상 + 이름) · 받음 → ✓ 받음 — 높이 56pt")
    func rowStates() throws {
        let claimable = try Self.row(try Self.mission(progress: 100, achieved: true, claimed: false))
        let progress = try Self.row(try Self.mission(progress: 37, achieved: false, claimed: false))
        let claimed = try Self.row(try Self.mission(progress: 100, achieved: true, claimed: true))
        #expect(claimable.pixelsHigh == 112 && progress.pixelsHigh == 112 && claimed.pixelsHigh == 112)
        // 세 상태는 서로 다른 그림이다(버튼 · 칩 · 받음 표시).
        let a = try #require(claimable.representation(using: .png, properties: [:]))
        let b = try #require(progress.representation(using: .png, properties: [:]))
        let c = try #require(claimed.representation(using: .png, properties: [:]))
        #expect(a != b && b != c && a != c)
        if let dir = V0381DevAingMac3DTests.evidenceDirectory {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try a.write(to: URL(fileURLWithPath: "\(dir)/mission-claimable.png"))
            try b.write(to: URL(fileURLWithPath: "\(dir)/mission-progress.png"))
            try c.write(to: URL(fileURLWithPath: "\(dir)/mission-claimed.png"))
            let burst = try Self.row(try Self.mission(progress: 100, achieved: true, claimed: true), burst: true)
            try #require(burst.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "\(dir)/mission-burst.png"))
        }
    }

    @Test("상점 잠긴 칸 글자: 자물쇠 + '미션 보상'")
    func lockedCaption() throws {
        let caption = try Self.bitmap(ShopMissionLockedCaption().padding(6).background(Color.black).environment(\.colorScheme, .dark))
        #expect(caption.pixelsWide > 40)
        if let dir = V0381DevAingMac3DTests.evidenceDirectory {
            try #require(caption.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "\(dir)/shop-locked-caption.png"))
        }
    }
}
