import AppKit
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// 지역 아잉이(센터마다 하나씩 — 대표 2026-11-10 "각센터 사람들 자기들 지역만의 아잉이 하나씩 갖게끔").
//  ① 코어: 부산 갈매기 아잉이는 내장 열한째 · 마감 .busan · 선물 전용(종류 region) · 센터 → 캐릭터 짝 · 능력 번호 10 은 **두 센터를 다**
//     그릴 때만(서울 그림 전엔 9) · 지역 선물 해석 · 마련 요청(region_gift_ensure) 전선.
//  ② 맥 3D: 실제 앱 씬에 갈매기 마감(무지개 합성 디퓨즈 + 갈매기 셰이더 + ckShadeMap + 부리 · 발 둘 · 꼬리깃 + 표식) · 렌더(배 = 흰 몸 · 팔 끝 =
//     검정 · 부리 = 노랑) · 엔진 교체 왕복 · 그릴 수 있다 · 초상 URL.
// 증거 PNG: `CHECK_REGION_AING_EVIDENCE_DIR=<폴더>` — 정면 · 3/4 · 뒤 · 감은 눈 · 울트라(아잉과 나란히).

@Suite struct RegionAingCoreTests {
    static var macBusanPortraitsInSourceTree: Bool {
        RegionAingArt.portraitResourceNames(RegionAingArt.busanID).allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }
    static var macBusanArtInSourceTree: Bool {
        RegionAingArt.requiredResourceNames(RegionAingArt.busanID, for: .mac).allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }
    static var macSeoulPortraitsInSourceTree: Bool {
        RegionAingArt.portraitResourceNames(RegionAingArt.seoulID).allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }
    /// 두 센터 그림이 다 소스 트리에 있는가 — 능력 번호 10 의 기준선(누적 사슬 시험이 이 값을 읽는다).
    static var macRegionArtInSourceTree: Bool {
        CharacterCatalog.regionGiftBuiltInIDs.allSatisfy { id in
            RegionAingArt.requiredResourceNames(id, for: .mac).allSatisfy(V0354CoreArtBaseline.macResourceExists)
        }
    }

    @Test("카탈로그: 부산 갈매기 · 서울의 밤 아잉이는 내장 열한째 · 열두째(맨 끝) · 마감 .busan · .seoul · 선물 전용(지역) · 희귀 · 뽑기 · 조각 · 미션 아님")
    func catalog() {
        #expect(CharacterCatalog.builtIns.suffix(2).map(\.id) == ["aing_busan", "aing_seoul"])
        #expect(CharacterCatalog.builtIns.count == 12)
        #expect(CharacterCatalog.builtInSeoulAing.displayName == "서울의 밤 아잉이")
        #expect(CharacterManifest.Finish(characterID: "aing_seoul") == .seoul)
        #expect(!CharacterManifest.Finish.seoul.isRare && !CharacterManifest.Finish.seoul.isCake)
        #expect(CharacterCatalog.isSeoulAing("aing_seoul") && !CharacterCatalog.isSeoulAing("aing_busan"))
        #expect(CharacterCatalog.builtInBusanAing.displayName == "부산 갈매기 아잉이")
        #expect(CharacterCatalog.builtInBusanAing.kind == .scene3D)
        #expect(CharacterManifest.Finish(characterID: "aing_busan") == .busan)
        #expect(!CharacterManifest.Finish.busan.isRare && !CharacterManifest.Finish.busan.isCake)
        #expect(CharacterCatalog.isGiftOnlyBuiltIn("aing_busan") && CharacterCatalog.isGiftOnlyBuiltIn("aing_seoul"))
        #expect(!CharacterCatalog.isGachaOnlyBuiltIn("aing_busan") && !CharacterCatalog.isShardOnlyBuiltIn("aing_busan")
                && !CharacterCatalog.isMissionRewardBuiltIn("aing_busan"))
        #expect(CharacterCatalog.isBusanAing("aing_busan") && !CharacterCatalog.isBusanAing("aing_busan ") && !CharacterCatalog.isBusanAing("aing"))
        #expect(CharacterCatalog.isRegionAing("aing_seoul") && !CharacterCatalog.isRegionAing("aing_dev"))
        #expect(CharacterCatalog(entries: []).manifest(id: "aing_seoul")?.kind == .scene3D)
        #expect(CharacterCatalog.giftKind(ofBuiltIn: "aing_seoul") == .region)
        #expect(CharacterCatalog.regionGiftBuiltInIDs == ["aing_busan", "aing_seoul"])
        #expect(CharacterCatalog.giftKind(ofBuiltIn: "aing_busan") == .region)
        // 상점 줄: 선물 전용 — 못 산다 · 뽑기 전용 아님.
        let row = ShopCharacterRow(id: "aing_busan", price: 2005, owned: false)
        #expect(row.isGiftOnly && !row.isPurchasable && !row.isGachaOnly)
    }

    @Test("센터 짝: busan → aing_busan · seoul → aing_seoul · 그 밖(빈 값 · 대문자 · nil)은 없다 · 이름")
    func centerPairs() {
        #expect(RegionAingArt.characterID(forCenter: "busan") == "aing_busan")
        #expect(RegionAingArt.characterID(forCenter: "seoul") == "aing_seoul")
        for bad in [nil, "", "Busan", "busan ", "daegu"] as [String?] {
            #expect(RegionAingArt.characterID(forCenter: bad) == nil, "\(String(describing: bad))")
        }
        #expect(RegionAingArt.center(of: "aing_busan") == "busan" && RegionAingArt.center(of: "aing_seoul") == "seoul")
        #expect(RegionAingArt.center(of: "aing") == nil)
        #expect(RegionAingArt.centerName(of: "aing_busan") == "부산" && RegionAingArt.centerName(of: "aing_seoul") == "서울")
    }

    @Test("능력 번호: 여기까지 전부 + 부산만 그리면 9 · 서울까지 그리면 10 · 서울만 있고 부산이 없으면 9(누적)")
    func protocolTen() {
        let upToDev = ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "aing_isul", "aing_pepero", "aing_hwoo",
                       "aing_ruby", "aing_dev"]
        #expect(ShopWire.regionProtocol == 10)
        #expect(ShopWire.regionCharacterIDs == ["aing_busan", "aing_seoul"])
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: upToDev + ["aing_busan"]) == 9)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: upToDev + ["aing_seoul"]) == 9)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: upToDev + ["aing_busan", "aing_seoul"]) == 10)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: upToDev.filter { $0 != "aing_dev" } + ["aing_busan", "aing_seoul"]) == 8)
        #expect(!ShopWire.supportsRegionGift(protocolVersion: 9) && ShopWire.supportsRegionGift(protocolVersion: 10))
    }

    @Test("그릴 수 있다(코어): 맥 = 초상 둘 + 밝기 맵 · 폰 = 초상 둘 · 하나만 빠져도 못 그린다 · 지역 아잉이가 아니면 언제나 못 그린다")
    func drawableDefinition() {
        #expect(RegionAingArt.requiredResourceNames("aing_busan", for: .mac) == ["aing_busan-neutral", "aing_busan-negative", "aing_rainbow-shade"])
        #expect(RegionAingArt.requiredResourceNames("aing_busan", for: .phone) == ["aing_busan-neutral", "aing_busan-negative"])
        #expect(RegionAingArt.isDrawable("aing_busan", on: .mac) { _ in true })
        for missing in RegionAingArt.requiredResourceNames("aing_busan", for: .mac) {
            #expect(!RegionAingArt.isDrawable("aing_busan", on: .mac) { $0 != missing }, "\(missing) 가 빠져도 그린다고 한다")
        }
        #expect(!RegionAingArt.isDrawable("aing_dev", on: .mac) { _ in true })
    }

    @Test("셰이더 글자: 흰 몸 · 등 회색 · 팔 판별(리본 띠와 같은 식) · 팔 끝 검정 · 흰 점 · 얼굴은 β 로 지킨다")
    func shaderText() {
        let f = GullAingShader.fragment()
        for needle in ["rgArm", "rgArmTip", "rgArmSpot", "float ckTh = atan2(ckP.x, ckP.z);", "ckInFace ? ckBeta : 1.0", "ckShadeMap"] {
            #expect(f.contains(needle), "\(needle) 가 없다")
        }
        #expect(!f.contains("ckLid"), "덮개 칠은 쓰지 않는다")
        #expect(GullAingShader.fragment(faceOff: true).contains("bool ckInFace = false"))
        #expect(GullAingDecor.decorNodeName == "check.busanDecor")
        // 서울의 밤: 같은 틀 · 별은 정해 둔 여덟 자리만(점 격자 없음 — 대표 메모 '환공포증') · 초승달 · 타워.
        let n = SeoulAingShader.fragment()
        #expect(n.contains("ckInFace ? ckBeta : 1.0") && n.contains("float ckAAT = max(fwidth(ckT), 1e-5);"))
        #expect(SeoulAingShader.stars.count == 8)
        #expect(n.components(separatedBy: "float arm = max(").count - 1 == SeoulAingShader.stars.count, "별 자리 수와 셰이더 별 수가 다르다")
        #expect(!n.contains("ckTh * 4.77") && !n.contains("* 45.0"), "2차 H5 의 촘촘한 별 · 창문 점 격자가 남았다")
    }

    @Test("장식 조각: 부리(노랑 → 검은 띠 → 빨간 점) · 발 둘(몸 아래) · 꼬리(뒤) — 이름 · 자리")
    func decorPieces() {
        let root = SIMD3<Float>(0, 0.32, 0.50)
        let pieces = GullAingDecor.pieces(beakRoot: root)
        #expect(pieces.map(\.name) == ["check.busan.beak", "check.busan.footR", "check.busan.footL", "check.busan.tail"])
        let beak = pieces[0]
        #expect(beak.color(0.5, 0.2) == GullAingDecor.beakYellow && beak.color(0.5, 0.78) == GullAingDecor.beakBand
                && beak.color(0.5, 0.95) == GullAingDecor.beakSpot)
        #expect(beak.pos(0.5, 1).z > root.z + 0.15, "부리는 앞으로 나온다")
        for foot in pieces[1...2] { #expect(foot.pos(0.5, 0.5).y < -0.80, "\(foot.name) 은 몸 아래") }
        #expect(pieces[3].pos(0.5, 0.5).z < -0.40, "꼬리는 뒤")
    }
}

// MARK: - 우리 센터 선물 — 해석 · 마련 요청(region_gift_ensure)

@Suite struct RegionGiftWireTests {
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(json.utf8))
    }

    @Test("종류: 'region' 원문 · 내장 = 부산 → 서울 · 문턱 10 · 문구 묶음은 다른 종류와 다르다")
    func kind() {
        #expect(CharacterGiftKind(wireValue: "region") == .region)
        #expect(CharacterGiftKind(wireValue: "Region") == nil)
        #expect(CharacterGiftKind.region.builtInIDs == ["aing_busan", "aing_seoul"])
        #expect(CharacterGiftKind.region.minProtocol == 10)
        #expect(!CharacterGiftKind.region.isSupported(protocolVersion: 9) && CharacterGiftKind.region.isSupported(protocolVersion: 10))
        #expect(CharacterGiftKind(builtInID: "aing_busan") == .region && CharacterGiftKind(builtInID: "aing_seoul") == .region)
        #expect(CharacterGiftKind.region.copy == .region && CharacterGiftKind.region.copy.title == RegionGiftText.title)
        #expect(CharacterGiftKind.region.showsInviteScreen)
        #expect(CharacterGiftKind.region.reopenSymbolName == "mappin.circle.fill")
    }

    @Test("선물 해석: 지역 선물(부산 하나) · 다른 종류 id 가 섞여 오면 버린다 · 지역 id 가 없으면 선물 없음")
    func offerDecodes() throws {
        let ok = try Self.decode(CharacterGiftPendingResponse.self,
                                 #"{"status":"ok","gift":{"id":"g1","kind":"region","options":["aing_busan","aing_isul"],"note":null}}"#)
        #expect(ok.offer?.kind == .region && ok.offer?.options == ["aing_busan"])
        let none = try Self.decode(CharacterGiftPendingResponse.self,
                                   #"{"status":"ok","gift":{"id":"g2","kind":"region","options":["aing_pepero"]}}"#)
        #expect(none.offer == nil)
    }

    @Test("마련 요청: {p_protocol} 하나만 싣는다 · 응답 status · 경로")
    func ensureWire() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let body = try #require(String(data: try encoder.encode(RegionGiftEnsureRequest(pProtocol: 10)), encoding: .utf8))
        #expect(body == #"{"p_protocol":10}"#)
        #expect(try Self.decode(RegionGiftEnsureResponse.self, #"{"status":"granted","gift_id":"x"}"#).status == "granted")
        #expect(SupabaseWorkService.regionGiftEnsurePath == "/rest/v1/rpc/region_gift_ensure")
        let seoul = try Self.decode(CharacterGiftPendingResponse.self,
                                    #"{"status":"ok","gift":{"id":"g3","kind":"region","options":["aing_seoul"]}}"#)
        #expect(seoul.offer?.options == ["aing_seoul"])
    }

    @Test("받는 창 말투(대표 #d_vxeOaE7gAxzt \"부산센터 선물 도착!\"): 선물 한 장의 제목 · 본문 · 다시 열기에 그 센터 이름 · 모르면 '우리 센터'")
    func perCenterCopy() {
        let busan = CharacterGiftOffer(id: "g-b", options: ["aing_busan"], kind: .region)
        let seoul = CharacterGiftOffer(id: "g-s", options: ["aing_seoul"], kind: .region)
        #expect(busan.copy.title == "부산센터 선물 도착!")
        #expect(seoul.copy.title == "서울센터 선물 도착!")
        #expect(busan.copy.body == "부산센터 사람에게만 주는 아잉이예요. 지금 받아 가세요!")
        #expect(seoul.copy.body == "서울센터 사람에게만 주는 아잉이예요. 지금 받아 가세요!")
        #expect(busan.copy.reopenTitle == "부산센터 선물이 기다려요" && seoul.copy.reopenTitle == "서울센터 선물이 기다려요")
        // 단추 · 잠긴 칸 줄 · 실패 줄은 센터와 무관하게 같다.
        for offer in [busan, seoul] {
            #expect(offer.copy.confirmButton == "받기" && offer.copy.lockedCaption == RegionGiftText.lockedCaption
                    && offer.copy.lockedHint == RegionGiftText.lockedHint && offer.copy.claimFailed == RegionGiftText.claimFailed)
        }
        // 센터를 모르는 판(종류만 알 때) — "우리 센터".
        #expect(RegionGiftText.title == "우리 센터 선물 도착!" && CharacterGiftCopy.region.reopenTitle == "우리 센터 선물이 기다려요")
        #expect(CharacterGiftKind.region.copy(for: nil) == .region && CharacterGiftKind.region.copy(for: "aing_busan") == busan.copy)
        // 다른 종류는 선물 한 장의 묶음 = 종류의 묶음 그대로.
        #expect(CharacterGiftOffer(id: "g-d", options: ["aing_isul"], kind: .drink).copy == .drink)
        #expect(CharacterGiftKind.pepero.copy(for: "aing_pepero") == .pepero)
    }

    @Test("문구: 잠긴 칸 캡션 · 안내는 다른 선물과 다르다 · 받는 창 단추는 '받기'")
    func copyText() {
        let others: [CharacterGiftCopy] = [.birthday, .drink, .pepero]
        #expect(!others.contains { $0.lockedCaption == RegionGiftText.lockedCaption || $0.lockedHint == RegionGiftText.lockedHint })
        #expect(RegionGiftText.confirmButton == "받기")
        #expect(RegionGiftText.lockedHint.contains("센터"))
    }
}

// MARK: - 맥 3D

@MainActor @Suite struct RegionAingMac3DTests {
    static let busan = CharacterCatalog.builtInBusanAing
    static let appSize = CGSize(width: 280, height: 340)
    nonisolated static let evidenceDirectory = ProcessInfo.processInfo.environment["CHECK_REGION_AING_EVIDENCE_DIR"]

    @Test("씬: 얼굴 = 무지개 합성 + 갈매기 셰이더 + ckShadeMap · 장식 넷(장식 판정) · 표식 — 다른 아잉 변형엔 없다")
    func finishIsApplied() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.busan)
        let character = try V0354GoldAing3DTests.character(scene)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        #expect(material.shaderModifiers?[.fragment] == GullAingShader.fragment(), "갈매기 셰이더가 안 걸렸다")
        let face = try #require(SleepEyeExplore.cgImage(from: material.diffuse.contents))
        #expect(RainbowAingFinish.lavenderOriginal(ofRainbowFace: face) != nil)
        let shade = try #require(material.value(forKey: GullAingShader.shadeMapKey) as? SCNMaterialProperty)
        #expect(SleepEyeExplore.cgImage(from: shade.contents) === RainbowAingFinish.shadeImage())
        #expect(RegionAingFinish.isBusan(character))
        let decor = try #require(scene.rootNode.childNode(withName: RegionAingFinish.decorNodeName, recursively: true))
        #expect(decor.childNodes.map(\.name) == ["check.busan.beak", "check.busan.footR", "check.busan.footL", "check.busan.tail"])
        #expect(decor.childNodes.allSatisfy(AingDecor.isDecor))
        for other in [CharacterCatalog.builtInAing, CharacterCatalog.builtInDevAing, CharacterCatalog.builtInHwooAing] {
            let s = try V0354GoldAing3DTests.scene(other)
            #expect(!RegionAingFinish.isBusan(try V0354GoldAing3DTests.character(s)), "\(other.id) 에 부산 표식")
            #expect(s.rootNode.childNode(withName: RegionAingFinish.decorNodeName, recursively: true) == nil, "\(other.id) 에 갈매기 장식")
        }
    }

    @Test("렌더: 배는 흰 몸(밝고 채도 낮음) · 팔 끝은 검정 · 부리는 노랑 — 셰이더 없으면 배가 보라")
    func rendersGull() throws {
        let scene = try V0354GoldAing3DTests.scene(Self.busan)
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
        let belly = oklch(px, SCNVector3(0.20, -0.30, 0.66))
        let beak = oklch(px, SCNVector3(0.0, 0.30, 0.66))
        print(String(format: "[busan-aing] 배 L %.2f C %.3f · 부리 L %.2f C %.3f h %.0f°", belly.L, belly.C, beak.L, beak.C, beak.h))
        #expect(belly.L > 0.85 && belly.C < 0.04, "배가 흰 몸이 아니다(\(belly))")
        #expect(beak.C > 0.08 && V0359RainbowArtTests.hueDistance(beak.h, 90) < 35, "부리가 노랑이 아니다(\(beak))")
        let plain = V0354GoldAingArtTests.rgba(try V0359Rainbow3DTests.render(scene, size: Self.appSize, modifiers: .some(nil)))
        #expect(oklch(plain, SCNVector3(0.20, -0.30, 0.66)).C > 0.04, "기준선: 셰이더 없는 배가 흰색이다")
        if Self.evidenceDirectory != nil { try Self.write(image, "busan-front.png") }
    }

    @Test("서울의 밤: 얼굴 = 무지개 합성 + 밤하늘 셰이더 + ckShadeMap · 장식 없음 · 표식 · 렌더(배는 짙은 남색) · 엔진 교체 왕복")
    func seoulFinish() throws {
        let seoul = CharacterCatalog.builtInSeoulAing
        let scene = try V0354GoldAing3DTests.scene(seoul)
        let character = try V0354GoldAing3DTests.character(scene)
        let material = try V0359Rainbow3DTests.faceMaterial(scene)
        #expect(material.shaderModifiers?[.fragment] == SeoulAingShader.fragment(), "밤하늘 셰이더가 안 걸렸다")
        #expect(RegionAingFinish.isSeoul(character) && !RegionAingFinish.isBusan(character))
        #expect(scene.rootNode.childNode(withName: RegionAingFinish.decorNodeName, recursively: true) == nil, "서울에 갈매기 장식")
        let image = try V0359Rainbow3DTests.render(scene, size: Self.appSize)
        let px = V0354GoldAingArtTests.rgba(image)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = V0354GoldAing3DTests.cameraNode(scene)
        _ = renderer.snapshot(atTime: 0, with: Self.appSize, antialiasingMode: .none)
        let p = renderer.projectPoint(character.convertPosition(SCNVector3(-0.20, -0.05, 0.66), to: nil))
        let c = V0359Rainbow3DTests.averageColor(px, width: image.width, at: (Int(p.x.rounded()), Int((Self.appSize.height - p.y).rounded())), radius: 1)
        let lch = V0359RainbowArtTests.oklch(c.0, c.1, c.2)
        print(String(format: "[seoul-aing] 배 L %.2f C %.3f h %.0f°", lch.L, lch.C, lch.h))
        #expect(lch.L < 0.45 && V0359RainbowArtTests.hueDistance(lch.h, 275) < 35, "배가 남색 밤하늘이 아니다(\(lch))")
        let engine = ReactionEngine()
        let from = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        engine.attach(node: try V0354GoldAing3DTests.wrapper(from), sceneRoot: from.rootNode, view: nil)
        let stashed = try #require(engine.swapCharacter(to: seoul, in: from))
        #expect(engine.currentCharacterID == CharacterCatalog.seoulAingID, "\(engine.currentCharacterID)")
        #expect(engine.restoreCharacterNode(stashed) && engine.currentCharacterID == CharacterCatalog.builtInAingID)
        if Self.evidenceDirectory != nil { try Self.write(image, "seoul-front.png") }
    }

    @Test("엔진은 부산 갈매기 아잉이를 가른다 — 아잉 → 부산 교체(울트라 경로)에 셰이더 · 장식 · 표식이 따라오고 원복하면 사라진다")
    func engineSwaps() throws {
        let engine = ReactionEngine()
        let scene = try V0354GoldAing3DTests.scene(CharacterCatalog.builtInAing)
        engine.attach(node: try V0354GoldAing3DTests.wrapper(scene), sceneRoot: scene.rootNode, view: nil)
        let stashed = try #require(engine.swapCharacter(to: Self.busan, in: scene))
        #expect(engine.currentCharacterID == CharacterCatalog.busanAingID, "\(engine.currentCharacterID)")
        #expect(scene.rootNode.childNode(withName: RegionAingFinish.decorNodeName, recursively: true) != nil)
        #expect(engine.restoreCharacterNode(stashed))
        #expect(engine.currentCharacterID == CharacterCatalog.builtInAingID)
    }

    @Test("그릴 수 있다: 번들 그대로 두 센터가 든다 → 능력 번호 10 · 하나만 빠져도 9 · 초상 URL · 192²")
    func drawable() throws {
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(CharacterCatalog.busanAingID) && drawable.contains(CharacterCatalog.seoulAingID), "\(drawable)")
        #expect(RegionAingFinish.isDrawable(CharacterCatalog.busanAingID) && RegionAingFinish.isDrawable(CharacterCatalog.seoulAingID))
        #expect(!RegionAingFinish.isDrawable(CharacterCatalog.devAingID))
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == ShopWire.regionProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) == ShopWire.regionProtocol)
        for one in CharacterCatalog.regionGiftBuiltInIDs {
            #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != one }) == ShopWire.devProtocol, "\(one) 가 빠졌는데 10")
        }
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.seoulAingID, mood: .neutral)?.lastPathComponent == "aing_seoul-neutral.png")
        #expect(CheckMascotAssets.image(for: .negative, characterID: CharacterCatalog.seoulAingID)?.size.width == 192)
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.busanAingID, mood: .neutral)?.lastPathComponent == "aing_busan-neutral.png")
        #expect(CheckMascotAssets.catalog.portraitURL(for: CharacterCatalog.busanAingID, mood: .negative)?.lastPathComponent == "aing_busan-negative.png")
        #expect(CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.busanAingID)?.size.width == 192)
    }

    static func write(_ image: CGImage, _ name: String) throws {
        let dir = URL(fileURLWithPath: try #require(Self.evidenceDirectory))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent(name))
    }

    @Test("증거: 정면 · 3/4 · 뒤 · 감은 눈 · 울트라(아잉 나란히)", .enabled(if: evidenceDirectory != nil))
    func writeEvidence() throws {
        let big = CGSize(width: 560, height: 680)
        for (tag, manifest) in [("busan", Self.busan), ("seoul", CharacterCatalog.builtInSeoulAing), ("aing", CharacterCatalog.builtInAing)] {
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
            let closed = try #require(CheckCharacter3DScene.makeClosedEyesImage(faceImage: face, geometry: try V0381DevAingMac3DTests.bodyGeometry(scene),
                                                                               character: try V0354GoldAing3DTests.character(scene)))
            material.diffuse.contents = closed
            for (name, _) in CheckCharacter3DScene.closedEyeAnchors { scene.rootNode.childNode(withName: name, recursively: true)?.isHidden = false }
            try Self.write(try V0359Rainbow3DTests.render(scene, size: big), "\(tag)-4-closed-eyes.png")
            let engine = ReactionEngine()
            let from = try V0354GoldAing3DTests.scene(tag == "aing" ? Self.busan : CharacterCatalog.builtInAing)
            engine.attach(node: try V0354GoldAing3DTests.wrapper(from), sceneRoot: from.rootNode, view: nil)
            _ = try #require(engine.swapCharacter(to: manifest, in: from))
            try Self.write(try V0359Rainbow3DTests.render(from, size: big), "\(tag)-5-ultra-swap.png")
        }
    }
}
