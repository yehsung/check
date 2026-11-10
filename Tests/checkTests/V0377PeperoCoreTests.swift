import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.77 빼빼로 아잉이(빼빼로 데이 11-11 기간 선물 전용) — 공용 코어 + 맥 번호.
///
/// 사용자 결정(2026-11-04): 얻는 길 "11-11 기간 선물 (이슬처럼)" · 판 "맥만, 따로 빨리 (0.3.77)". 그림(3D 마감 · 초상)은 아직 시안을 고르는 중이다.
///
/// 지키는 것:
///  ① 카탈로그: `aing_pepero` · 표시 이름 한 곳(`peperoAingDisplayName` — 상표 때문에 바뀔 수 있다) · 내장 일곱째(이슬 뒤) · 선물 전용 판정.
///  ② ★ 이슬 때의 갈래(설계서 §2 함정)를 지킨다 — 케이크 뜻(생일 목록 · `ShopWire.cakeCharacterIDs`) · 술 뜻(`drinkGiftBuiltInIDs` ·
///     `ShopWire.isulCharacterIDs`) 자리에 빼빼로가 섞이지 않는다. '선물 전용 전부'(`giftOnlyBuiltInIDs`)에만 붙는다.
///  ③ 능력 번호 누적: 이슬까지 → 5 · 빼빼로까지 → 6 · 빼빼로만 있고 이슬이 빠지면 4. ★ **그림이 붙기 전의 맥은 5 그대로**다
///     (빼빼로가 `drawableCharacterIDs` 에 없다) — 그림 없는 캐릭터를 받지 않게. 그림이 붙는 날 이 못을 고친다.
///  ④ 선물 전선: `kind = "pepero"` + 빼빼로만 · 다른 종류에 빼빼로가 섞이면 버림 · 번호 5 이하 빌드엔 빼빼로 선물을 띄우지 않는다 ·
///     수령 needs_update(min 6)도 같은 어휘.
///  ⑤ 문구는 대표 결정 C(#d_JyxuQRmHOYKC) 그대로 · 비어 있지 않다 · 본문의 캐릭터 이름은 표시 이름 상수에서 온다.
@Suite("v0.3.77 빼빼로 아잉이 공용 코어")
struct V0377PeperoCoreTests {
    static let pepero = "aing_pepero"
    static let isul = "aing_isul"
    static let strawberry = "aing_cake_strawberry"
    static let choco = "aing_cake_choco"
    static let giftID = "5e5e1111-0000-4000-8000-00000000b011"

    static func pending(_ json: String) throws -> CharacterGiftPendingResponse {
        try V0354GachaWireTests.decoder().decode(CharacterGiftPendingResponse.self, from: Data(json.utf8))
    }

    static func host(_ label: String) -> String {
        "v0377-pepero-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    }

    /// 맥 소스 트리에 빼빼로 초상 두 장이 있는가(그림 갈래 전엔 거짓). 그림이 들어오는 날 ③ 의 못을 고칠 때 이 값을 본다.
    static var macPeperoPortraitsInSourceTree: Bool {
        ["\(pepero)-neutral", "\(pepero)-negative"].allSatisfy(V0354CoreArtBaseline.macResourceExists)
    }

    /// 맥 소스 트리에 빼빼로 그림이 다 있는가(초상 두 장 + 상자 인쇄 판 폴백 — 3D 마감 `PeperoAingFinish` 의 번들 재료).
    static var macPeperoArtInSourceTree: Bool {
        macPeperoPortraitsInSourceTree && V0354CoreArtBaseline.macResourceExists("\(pepero)-box")
    }

    /// 맥 빌드의 상점 능력 번호 기대값(누적): 이슬 그림이 있으면 5, 빼빼로 그림까지 있으면 6, 아니면 케이크 4.
    static var expectedMacProtocolFromIsulOn: Int {
        // v0.3.78: 흑우 그림까지 있으면 7(누적 — 빼빼로가 없으면 흑우가 있어도 6 을 건너뛰지 않는다).
        V0374IsulCoreTests.macIsulArtInSourceTree
            ? (macPeperoArtInSourceTree
                ? (V0378HwooCoreTests.macHwooArtInSourceTree
                    ? (V0378RubyCoreTests.macRubyArtInSourceTree ? (V0381DevAingCoreTests.macDevArtInSourceTree ? (RegionAingCoreTests.macRegionArtInSourceTree ? ShopWire.regionProtocol : ShopWire.devProtocol) : ShopWire.rubyProtocol) : ShopWire.hwooProtocol)   // v0.3.78 루비까지 8
                    : ShopWire.peperoProtocol)
                : ShopWire.isulProtocol)
            : ShopWire.cakeProtocol
    }

    // MARK: - ① 카탈로그

    @Test("카탈로그: id · 표시 이름(한 곳 상수) · scene3D · 내장 일곱째(이슬 뒤) · 정확한 id 만")
    func catalogEntry() {
        #expect(CharacterCatalog.peperoAingID == Self.pepero)
        #expect(CharacterCatalog.peperoAingDisplayName == "빼빼로 아잉이")
        #expect(CharacterCatalog.builtInPeperoAing.id == Self.pepero)
        #expect(CharacterCatalog.builtInPeperoAing.displayName == CharacterCatalog.peperoAingDisplayName, "표시 이름이 상수에서 안 온다")
        #expect(CharacterCatalog.builtInPeperoAing.kind == .scene3D)
        let order = ["aing", "aing_gold", "aing_rainbow", Self.strawberry, Self.choco, Self.isul, Self.pepero, CharacterCatalog.hwooAingID, CharacterCatalog.rubyAingID, CharacterCatalog.devAingID, CharacterCatalog.busanAingID, CharacterCatalog.seoulAingID]
        #expect(CharacterCatalog.builtIns.map(\.id) == order)
        let empty = CharacterCatalog(entries: [])
        #expect(empty.allIDs == order)
        #expect(empty.manifest(id: Self.pepero)?.displayName == CharacterCatalog.peperoAingDisplayName)
        // 확률표 · 교환 줄이 쓰는 내장 이름 폴백도 빼빼로를 안다.
        #expect(GachaRules.name(for: Self.pepero, displayName: { _ in nil }) == CharacterCatalog.peperoAingDisplayName)
        #expect(CharacterCatalog.isPeperoAing(Self.pepero))
        for near in ["aing_pepero ", "AING_PEPERO", "aing_pepero2", "pepero", "aing_isul", "", nil] as [String?] {
            #expect(!CharacterCatalog.isPeperoAing(near), "\(String(describing: near))")
        }
        // 파일 매니페스트로는 못 싣는다(밑줄 id) · 같은 id 를 넣어도 내장이 이긴다.
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(CharacterManifest.self, from: Data(#"{"id":"aing_pepero","displayName":"가짜","kind":"scene3D"}"#.utf8))
        }
        let fake = CharacterCatalog(manifests: [CharacterManifest(id: Self.pepero, displayName: "가짜 빼빼로", kind: .sprite)])
        #expect(fake.manifest(id: Self.pepero)?.kind == .scene3D && fake.manifest(id: Self.pepero)?.displayName == "빼빼로 아잉이")
    }

    @Test("선물 전용: 빼빼로는 선물 전용 · 케이크 아님 · 이슬 아님 · 뽑기 전용 아님 · 마감 .pepero(희귀 아님) · 조각 교환 불가")
    func giftOnlyLists() {
        #expect(CharacterCatalog.isGiftOnlyBuiltIn(Self.pepero))
        #expect(!CharacterCatalog.isCakeAing(Self.pepero))
        #expect(!CharacterCatalog.isIsulAing(Self.pepero))
        #expect(!CharacterCatalog.isGachaOnlyBuiltIn(Self.pepero))
        #expect(CharacterCatalog.peperoGiftBuiltInIDs == [Self.pepero])
        #expect(CharacterCatalog.giftOnlyBuiltInIDs == [Self.strawberry, Self.choco, Self.isul, Self.pepero, CharacterCatalog.busanAingID, CharacterCatalog.seoulAingID])
        #expect(Set(CharacterCatalog.giftOnlyBuiltInIDs) == Set(CharacterCatalog.builtIns.map(\.id).filter(CharacterCatalog.isGiftOnlyBuiltIn)))
        #expect(CharacterCatalog.giftKind(ofBuiltIn: Self.pepero) == .pepero)
        #expect(CharacterCatalog.giftKind(ofBuiltIn: Self.isul) == .drink, "이슬 종류가 빼빼로에 먹혔다")
        #expect(GachaRules.isNeverExchangeable(Self.pepero))
        #expect(CharacterManifest.Finish(characterID: Self.pepero) == .pepero)
        #expect(CharacterCatalog.builtInPeperoAing.finish == .pepero)
        #expect(!CharacterManifest.Finish.pepero.isRare)
        #expect(!CharacterManifest.Finish.pepero.isCake)
        #expect(CharacterManifest.Finish(characterID: Self.isul) == .isul, "이슬 마감 판정이 빼빼로에 먹히지 않는다")
        // 상점 줄: 표식이 있든 없든 못 산다.
        let flagged = ShopCharacterRow(id: Self.pepero, price: 2003, owned: false, gachaOnly: true, giftOnly: true)
        #expect(!flagged.isPurchasable && flagged.isGiftOnly && !flagged.isGachaOnly)
        let bare = ShopCharacterRow(id: Self.pepero, price: 2003, owned: false)
        #expect(!bare.isPurchasable && bare.isGiftOnly, "표식이 빠져도 빼빼로 id 는 팔지 않는다")
    }

    // MARK: - ② 케이크 뜻 · 술 뜻 자리에 안 섞인다(설계서 §2 함정)

    @Test("갈래: 케이크 뜻 · 술 뜻 목록은 그대로 · 상점 케이크 순서는 빼빼로를 안 옮긴다 · 잠긴 안내는 빼빼로 문구 · 고르기는 가진 사람만")
    func meaningSitesStaySplit() {
        #expect(CharacterCatalog.birthdayGiftBuiltInIDs == [Self.strawberry, Self.choco])
        #expect(CharacterCatalog.drinkGiftBuiltInIDs == [Self.isul])
        #expect(ShopWire.cakeCharacterIDs == [Self.strawberry, Self.choco])
        #expect(ShopWire.isulCharacterIDs == [Self.isul])
        #expect(ShopWire.peperoCharacterIDs == [Self.pepero])
        #expect(CharacterGiftKind.birthday.builtInIDs == [Self.strawberry, Self.choco])
        #expect(CharacterGiftKind.drink.builtInIDs == [Self.isul])
        #expect(CharacterGiftKind.pepero.builtInIDs == [Self.pepero])
        // 서버 순서(값 · id): 초코 2000 → 딸기 2000 → 이슬 2002 → 빼빼로. 케이크 둘만 딸기 → 초코로 바로 서고 나머지는 그 자리.
        let rows = [Self.choco, Self.pepero, Self.isul, "robot", Self.strawberry].map { ShopCharacterRow(id: $0, price: 1) }
        #expect(WorkTimerStore.giftOnlyInDisplayOrder(rows).map(\.id) == [Self.strawberry, Self.pepero, Self.isul, "robot", Self.choco])
        #expect(CheckCharacterPanel.lockedLabel(Self.pepero, name: "빼빼로 아잉이") == "빼빼로 아잉이 잠김 — \(PeperoGiftText.lockedHint)")
        #expect(CheckCharacterPanel.lockedLabel(Self.isul, name: "이슬") == "이슬 잠김 — \(DrinkGiftText.lockedHint)")
        #expect(WorkTimerStore.giftCopy(for: Self.pepero) == .pepero)
        #expect(WorkTimerStore.giftCopy(for: Self.isul) == .drink)
        // 고르기: 가진 사람에게만(케이크 · 이슬과 같다).
        #expect(!WorkTimerStore.isCharacterListed(Self.pepero, shopLoaded: true, gachaAvailable: true, owned: [], rows: []))
        #expect(WorkTimerStore.isCharacterListed(Self.pepero, shopLoaded: true, gachaAvailable: false, owned: [Self.pepero], rows: []))
        #expect(WorkTimerStore.isCharacterListed(Self.pepero, shopLoaded: false, gachaAvailable: false, owned: [], rows: [], wearing: Self.pepero))
    }

    // MARK: - ③ 능력 번호

    @Test("능력 번호 누적: 이슬까지 5 · 빼빼로까지 6 · 빼빼로만(이슬 없음) 4 · 케이크 하나 빠지면 3 · 문턱 6")
    func protocolCumulative() {
        let base = ["robot", "aing_gold", "aing_rainbow", Self.strawberry, Self.choco]
        #expect(ShopWire.peperoProtocol == 6)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: base + [Self.isul]) == 5)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: base + [Self.isul, Self.pepero]) == 6)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: base + [Self.pepero]) == 4, "이슬 없이 빼빼로만 — 5 도 못 보낸다")
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: ["robot", "aing_gold", "aing_rainbow", Self.choco, Self.isul, Self.pepero]) == 3)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: [Self.isul, Self.pepero]) == 0)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: CharacterCatalog.builtIns.map(\.id) + ["robot"]) == ShopWire.regionProtocol, "내장 전부 + robot — v0.3.78 흑우 7 · 루비까지 8 · v0.3.81 개발 아잉이까지 9 · 지역 아잉이 둘까지 10")
        #expect(!ShopWire.supportsPeperoGift(protocolVersion: 5))
        #expect(ShopWire.supportsPeperoGift(protocolVersion: 6))
        #expect(ShopWire.supportsDrinkGift(protocolVersion: 6) && ShopWire.supportsCakeGift(protocolVersion: 6), "번호는 누적이다")
        #expect(CharacterGiftKind.pepero.minProtocol == 6)
        #expect(CharacterGiftKind.drink.minProtocol == 5, "이슬 문턱이 움직였다")
        #expect(!CharacterGiftKind.pepero.isSupported(protocolVersion: 5))
        #expect(CharacterGiftKind.pepero.isSupported(protocolVersion: 6))
    }

    @Test("맥 번들: 빼빼로 그림(판 · 초상 두 장)이 소스 트리에 있으면 그릴 수 있음 → 능력 번호 6, 없으면 빼빼로 전(이슬까지 5) 그대로(누적 규칙)")
    @MainActor
    func macProtocolFollowsThePeperoArt() {
        // v0.3.77 그림 갈래(078df8ed 병합)부터 판 · 초상이 번들에 있다 — 그 전의 못(`macDoesNotClaimPeperoBeforeTheArt`)을 이슬과 같은 모양으로 뒤집었다.
        let art = Self.macPeperoArtInSourceTree
        let expected = Self.expectedMacProtocolFromIsulOn
        let drawable = CheckMascotAssets.drawableCharacterIDs()
        #expect(drawable.contains(Self.pepero) == art, "빼빼로 그림 판정이 소스 트리와 갈렸다 — \(drawable)")
        #expect(WorkTimerStore.bundledDrawableCharacterIDs.contains(Self.pepero) == art)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable) == expected)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: WorkTimerStore.bundledDrawableCharacterIDs) == expected)
        let store = V0317ShopTests.plainStore()
        #expect(store.shopProtocolVersion == expected, "스토어 번호 \(store.shopProtocolVersion)")
        #expect(ShopWire.supportsPeperoGift(protocolVersion: store.shopProtocolVersion) == (expected >= ShopWire.peperoProtocol), "v0.3.78 흑우가 얹히면 7(누적)")
        // 판정은 마감 실재 한 곳 — 그림 셋 중 하나만 빠져도 빼빼로는 빠지고 번호는 5 로 내려간다.
        if art {
            for missing in PeperoAingFinish.requiredResourceNames() {
                #expect(!PeperoAingFinish.isDrawable { $0 != missing }, "\(missing) 가 빠져도 그릴 수 있다고 한다")
            }
            #expect(ShopWire.protocolVersion(drawableCharacterIDs: drawable.filter { $0 != Self.pepero }) < ShopWire.peperoProtocol)
        }
        #expect(CheckCharacter3DScene.catalog.manifest(id: Self.pepero)?.finish == .pepero)
    }

    // MARK: - ④ 선물 전선

    @Test("종류: 원문 값 셋 · 'pepero' 정확히 · 내장 → 종류")
    func giftKind() {
        #expect(CharacterGiftKind.allCases == [.birthday, .drink, .pepero, .region])   // 지역 아잉이(우리 센터 선물)가 넷째
        #expect(CharacterGiftKind.pepero.wireValue == "pepero")
        #expect(CharacterGiftKind(wireValue: "pepero") == .pepero)
        for odd in ["Pepero", " pepero", "pepero ", "peppero", "빼빼로", "", nil] as [String?] {
            #expect(CharacterGiftKind(wireValue: odd) == nil, "\(String(describing: odd))")
        }
        #expect(CharacterGiftKind(builtInID: Self.pepero) == .pepero)
        #expect(CharacterGiftKind(builtInID: Self.isul) == .drink)
    }

    @Test("디코드: 빼빼로 선물 + 빼빼로 → 하나 · 다른 종류에 빼빼로가 섞이면 버림 · 빼빼로 선물에 이슬만 → 없음 · kind 없음(생일)에 빼빼로만 → 없음")
    func pendingDecodesPepero() throws {
        let pepero = try Self.pending(#"{"status":"ok","gift":{"id":"\#(Self.giftID)","kind":"pepero","options":["aing_pepero"],"note":"빼빼로 데이 축하해요","created_at":"2026-11-11T00:00:00Z"}}"#)
        #expect(pepero.offer == CharacterGiftOffer(id: Self.giftID, options: [Self.pepero], note: "빼빼로 데이 축하해요",
                                                   createdAt: "2026-11-11T00:00:00Z", kind: .pepero))
        let mixedDrink = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":"drink","options":["aing_pepero","aing_isul"]}}"#)
        #expect(mixedDrink.offer?.kind == .drink && mixedDrink.offer?.options == [Self.isul])
        let mixedBirthday = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":"birthday","options":["aing_pepero","aing_cake_choco"]}}"#)
        #expect(mixedBirthday.offer?.options == [Self.choco])
        let isulInPepero = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":"pepero","options":["aing_isul","aing_cake_choco"]}}"#)
        #expect(isulInPepero.offer == nil && isulInPepero.status == "ok")
        let legacyPeperoOnly = try Self.pending(#"{"status":"ok","gift":{"id":"g","options":["aing_pepero"]}}"#)
        #expect(legacyPeperoOnly.offer == nil, "kind 없는 옛 서버 모양(생일로 읽음)에 빼빼로만 — 고를 것 없음")
        let mixedPepero = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":"pepero","options":["aing_isul","aing_pepero","aing_pepero"]}}"#)
        #expect(mixedPepero.offer?.options == [Self.pepero])
        // 모르는 종류는 여전히 선물 없음 — 옛 빌드(0.3.74~0.3.76)가 'pepero' 를 받는 길이 이것이다(그 빌드의 종류엔 pepero 가 없다).
        for odd in [#""valentine""#, #""Pepero""#, "6", #"["pepero"]"#] {
            let response = try Self.pending(#"{"status":"ok","gift":{"id":"g","kind":\#(odd),"options":["aing_pepero"]}}"#)
            #expect(response.offer == nil && response.status == "ok", "\(odd)")
        }
        #expect(CharacterGiftOffer.choosable([Self.isul, Self.pepero, Self.choco], kind: .pepero) == [Self.pepero])
        #expect(CharacterGiftOffer(id: "g", options: [Self.pepero], kind: .pepero) != CharacterGiftOffer(id: "g", options: [Self.pepero], kind: .drink))
    }

    @Test("서비스: 번호 6 만 빼빼로 선물을 받는다 · 4 · 5 엔 섞여 와도 띄우지 않는다 · 요청 키 집합은 그대로")
    func servicePendingByProtocol() async throws {
        let host = Self.host("pending")
        GomokuStubProtocol.register(host: host) { rpc, _, _ in
            guard rpc == "character_gift_pending" else { return nil }
            // 일부러 번호와 무관하게 빼빼로 선물을 싣는다(서버가 잘못 실어도 클라가 막는지 잰다).
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","gift":{"id":"g-pepero","kind":"pepero","options":["aing_pepero"],"note":null}}"#)
        }
        let service = V0354GachaWireTests.service(host: host)
        #expect(try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.cakeProtocol) == nil)
        #expect(try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.isulProtocol) == nil,
                "번호 5(빼빼로 그림이 없는 지금의 맥)는 빼빼로를 못 그린다 — 받을 수 없는 창을 띄우지 않는다")
        let six = try await service.fetchCharacterGiftPending(accessToken: "t", protocolVersion: ShopWire.peperoProtocol)
        #expect(six == CharacterGiftOffer(id: "g-pepero", options: [Self.pepero], kind: .pepero))
        let calls = GomokuStubProtocol.calls(host: host, rpc: "character_gift_pending")
        #expect(calls.map { $0.json["p_protocol"] as? Int } == [4, 5, 6])
        #expect(calls.allSatisfy { Set($0.json.keys) == ["p_protocol"] })
    }

    @Test("수령: 빼빼로 선물 needs_update(min_protocol 6)도 같은 어휘 · 받으면 받은 뒤 한 줄")
    func claimNeedsUpdate() throws {
        let response = try V0354GachaWireTests.decoder().decode(
            CharacterGiftClaimResponse.self, from: Data(#"{"status":"needs_update","min_protocol":6}"#.utf8))
        #expect(response.minProtocol == 6)
        let outcome = CharacterGiftClaimOutcome(response: response, requestedID: Self.pepero)
        #expect(outcome == .needsUpdate && !outcome.settlesGift)
        #expect(PeperoGiftText.notice(for: outcome) { $0 } == CakeGiftText.needsUpdate)
        let received = CharacterGiftClaimOutcome(
            response: CharacterGiftClaimResponse(status: "ok", characterId: Self.pepero, replayed: false), requestedID: Self.pepero)
        #expect(received == .received(characterID: Self.pepero, replayed: false))
        #expect(PeperoGiftText.notice(for: received) { $0 } == nil)
    }

    // MARK: - ⑤ 문구(대표 결정 C — #d_JyxuQRmHOYKC)

    @Test("문구: 대표 결정 C 그대로 · 본문 이름은 표시 이름 상수 · 비어 있지 않음 · 종류 → 묶음 · 이슬 · 생일 묶음과 다르다")
    func peperoText() {
        #expect(PeperoGiftText.title == "빼빼로 받아랏! 🍫")
        #expect(PeperoGiftText.body == "몰래 하나 챙겨 왔어요. 빼빼로 아잉이 쏙!")
        #expect(PeperoGiftText.body.contains(CharacterCatalog.peperoAingDisplayName), "본문의 캐릭터 이름이 상수에서 안 온다")
        #expect(PeperoGiftText.confirmButton == "쏙 받기")
        #expect(PeperoGiftText.reopenTitle == "빼빼로가 쏙 들어왔어요")
        #expect(PeperoGiftText.reopenButton == "받기")
        #expect(PeperoGiftText.wearNowButton == "지금 입기" && PeperoGiftText.closeButton == "닫기")
        #expect(PeperoGiftText.lockedCaption == "빼빼로 데이 선물 전용")
        #expect(PeperoGiftText.lockedHint == "빼빼로 데이 선물로만 받을 수 있어요. 루비나 뽑기로는 얻을 수 없어요.")
        #expect(PeperoGiftText.received(name: CharacterCatalog.peperoAingDisplayName) == "빼빼로 아잉이를 받았어요!")
        #expect(PeperoGiftText.claimFailed == CakeGiftText.claimFailed)

        for kind in CharacterGiftKind.allCases {
            let copy = kind.copy
            let lines = [copy.title, copy.body, copy.confirmButton, copy.wearNowButton, copy.closeButton,
                         copy.lockedCaption, copy.lockedHint, copy.reopenTitle, copy.reopenButton, copy.claimFailed]
            #expect(lines.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "\(kind): \(lines)")
        }
        #expect(CharacterGiftKind.pepero.copy == .pepero)
        #expect(CharacterGiftCopy.pepero.title == PeperoGiftText.title && CharacterGiftCopy.pepero.body == PeperoGiftText.body)
        #expect(CharacterGiftCopy.pepero.lockedHint == PeperoGiftText.lockedHint && CharacterGiftCopy.pepero.lockedCaption == PeperoGiftText.lockedCaption)
        #expect(CharacterGiftCopy.pepero.reopenTitle == PeperoGiftText.reopenTitle)
        #expect(CharacterGiftCopy.pepero != .drink && CharacterGiftCopy.pepero != .birthday)
        // 상점 잠긴 칸 안내 · 캡션은 종류마다 달라야 바가 어느 선물의 얻는 길인지 가린다(`ShopText.isGiftLockedHint`).
        #expect(Set(CharacterGiftKind.allCases.map(\.copy.lockedHint)).count == CharacterGiftKind.allCases.count)
        #expect(Set(CharacterGiftKind.allCases.map(\.copy.lockedCaption)).count == CharacterGiftKind.allCases.count)
        // 이슬 확정 문구(대표 결정 C)는 그대로다.
        #expect(DrinkGiftText.title == "짠! 🥂" && DrinkGiftText.confirmButton == "짠 받기")
    }
}
