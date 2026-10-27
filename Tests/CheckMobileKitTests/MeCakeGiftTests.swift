@testable import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CheckMobileKit

// 폰 **케이크 아잉이 · 생일 선물**(맥 0.3.66 / 폰 1.0.14)의 계약.
//
// ── 왜 이 파일인가 ──
// 폰 뷰(상점 타일 · 축하 시트 · 다시 열기 줄 · 아바타)는 `#if os(iOS)` 라 맥 스위트가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가
// 못 본다'). 그래서 화면이 가르는 판정을 전부 플랫폼 무관한 자리(`MeStoreCakeGift` · `MeStoreCharacters` · `MeCharacterTileStatus` ·
// `AingCharacterArt.avatarFraming`)에 두었고, 여기서 **값**과 **실제 요청**으로 잰다. 뷰는 시뮬레이터 스크린샷이 본다.
//
//   ① 번호: 번들 그대로의 폰은 4 를 말한다 · 케이크 하나만 빼도 3 — 초상 파일 ⟺ 목록 ⟺ 번호 양방향
//   ② 아바타 틀: 케이크 초상을 틀로 되돌리면 몸이 아잉 몸과 겹친다(얼굴 크기가 같다) · 아잉 · 금 · 무지개 · 모르는 id 는 그대로
//   ③ 상점 · 고르기: 고르기는 가진 사람에게만 · 안 가진 사람은 상점의 잠긴 칸('생일 선물 전용' — 가격 · 구매 없음) · 누르면 안내
//   ④ 축하 시트: 앞에 올 때 10분 스로틀 · 실행당 한 번 · 닫으면 다시 열기 · 수령 · 받은 뒤 상점 다시 읽기 · [지금 입기] · 실패 갈래
//   ⑤ 데모 픽스처: 모든 데모 라우트에서 선물 조회가 404 없이 '선물 없음' · 축하 시트 장면(`me/gift…`)의 열린 선물 · 상점 두 케이크 행
@MainActor
@Suite struct MeCakeGiftTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    nonisolated static let strawberry = CharacterCatalog.cakeStrawberryAingID
    nonisolated static let choco = CharacterCatalog.cakeChocoAingID
    nonisolated static let giftID = "9f3c1b2a-0000-4000-8000-00000000ca4e"

    static func portraitFileExists(_ id: String) -> Bool {
        AingCharacterArt.Expression.allCases.allSatisfy { expression in
            FileManager.default.fileExists(atPath: root
                .appendingPathComponent("Sources/CheckMobileShared/Resources/Portraits/\(id)-\(expression.rawValue).png").path)
        }
    }

    // MARK: - ① 번호

    @Test("번들 그대로의 폰은 4 를 말한다 · 케이크 하나만 빼도 3 이다 — 초상 파일 ⟺ 목록 ⟺ 번호")
    func protocolTracksCakePortraits() {
        #expect(ShopWire.cakeProtocol == 4, "서버 `character_prices.min_protocol = 4` 와 같은 숫자여야 한다")
        let known = AingCharacterArt.knownIDs
        for id in ShopWire.cakeCharacterIDs {
            #expect(Self.portraitFileExists(id), "\(id) 초상 두 장이 폰 번들에 없다")
            #expect(known.contains(id) == Self.portraitFileExists(id), "\(id): 번들 초상과 knownIDs 가 갈렸다")
        }
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)
        #expect(derived == ShopWire.cakeProtocol, Comment(rawValue: "목록 \(known) → \(derived)"))
        #expect(ShopWire.supportsCakeGift(protocolVersion: derived))
        // 반대 방향: 케이크 하나만 빠져도 4 가 아니다(그림 없는 쪽을 골라 받으면 아잉 그림의 '케이크 아잉이'가 된다).
        for id in ShopWire.cakeCharacterIDs {
            let without = known.filter { $0 != id }
            #expect(ShopWire.protocolVersion(drawableCharacterIDs: without) == ShopWire.rainbowProtocol,
                    Comment(rawValue: "\(id) 를 뺀 목록이 3 이 아니다 — 번호가 목록에서 파생되지 않는다"))
        }
        // 스토어 자리(번호를 박지 않는다 — `MeStore.drawableCharacterIDs` 기본값이 이 목록이다).
        #expect(known == ["aing", "aing_gold", "aing_rainbow", Self.strawberry, Self.choco,
                          "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel"],
                "순서: 내장 다섯(코어 CharacterCatalog.allIDs 순서) → 나머지 이름순")
        #expect(AingCharacterArt.resolvedID(Self.choco) == Self.choco && AingCharacterArt.resolvedID(" \(Self.strawberry) ") == Self.strawberry)
    }

    // MARK: - ② 아바타 틀(얼굴 크기)

    struct AlphaShape: Equatable, CustomStringConvertible {
        var bottom: Int
        var widest: Int
        var widestY: Int
        var description: String { "아래끝 \(bottom) · 최대폭 \(widest)@\(widestY)" }
    }

    /// 초상을 192² 캔버스에 **아바타 틀 그대로**(가운데 기준 배율 → 세로 이동) 그린 알파.
    static func framedAlpha(_ image: CGImage, framing: AingCharacterArt.AvatarFraming) throws -> [UInt8] {
        let side = AingCharacterArt.portraitPixelSize
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            let drawn = Double(side) * framing.scale
            let originX = (Double(side) - drawn) / 2
            // 위가 0 인 좌표에서 위쪽 끝 = (side − drawn)/2 + side·offsetY. CG 는 아래가 0 이라 뒤집는다.
            let topY = (Double(side) - drawn) / 2 + Double(side) * framing.offsetY
            context.draw(image, in: CGRect(x: originX, y: Double(side) - topY - drawn, width: drawn, height: drawn))
            return true
        }
        try #require(ok)
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// 몸 모양(알파 > 0.5): 아래 끝 · 가장 넓은 줄의 폭(장식이 없는 아래 절반에서만 잰다 — 장식은 머리 위다).
    static func bodyShape(_ alpha: [UInt8]) -> AlphaShape {
        let side = AingCharacterArt.portraitPixelSize
        var bottom = -1, widest = 0, widestY = -1
        for y in 0..<side {
            var minX = side, maxX = -1
            for x in 0..<side where alpha[y * side + x] > 127 { minX = min(minX, x); maxX = max(maxX, x) }
            guard maxX >= minX else { continue }
            bottom = y
            if y >= side / 2, maxX - minX + 1 > widest { widest = maxX - minX + 1; widestY = y }
        }
        return AlphaShape(bottom: bottom, widest: widest, widestY: widestY)
    }

    @Test("아바타 틀: 케이크 초상을 틀로 되돌리면 몸이 아잉 몸과 겹친다(얼굴 크기가 아잉 · 황금 · 무지개와 같다)",
          arguments: [strawberry, choco])
    func cakeAvatarFramingMatchesAingBody(cake: String) throws {
        let framing = AingCharacterArt.avatarFraming(id: cake)
        #expect(framing.scale > 1.1 && framing.scale < 1.2, "케이크는 키워야 한다(0.88 축소를 되돌린다): \(framing)")
        #expect(framing.offsetY < 0, "케이크는 몸을 위로 올려야 한다: \(framing)")
        for expression in AingCharacterArt.Expression.allCases {
            let aing = try #require(AingCharacterArt.portraitImage(id: "aing", expression: expression))
            let image = try #require(AingCharacterArt.portraitImage(id: cake, expression: expression))
            let reference = Self.bodyShape(try Self.framedAlpha(aing, framing: .identity))
            let framed = Self.bodyShape(try Self.framedAlpha(image, framing: framing))
            let raw = Self.bodyShape(try Self.framedAlpha(image, framing: .identity))
            // 기준선이 다르다: 틀 없이 그린 케이크는 아잉보다 몸이 좁고(0.88) 아래 끝이 낮다 — 이 단언이 늘 초록이 되는 그림이 아니다.
            #expect(abs(raw.widest - reference.widest) > 10, "틀 없는 케이크가 이미 아잉 폭이다 — 생성기 배치가 바뀌었다(\(raw) vs \(reference))")
            #expect(abs(framed.widest - reference.widest) <= 3, "\(cake)-\(expression): 틀 뒤 \(framed) · 아잉 \(reference)")
            #expect(abs(framed.bottom - reference.bottom) <= 2, "\(cake)-\(expression): 틀 뒤 \(framed) · 아잉 \(reference)")
            #expect(abs(framed.widestY - reference.widestY) <= 6, "\(cake)-\(expression): 틀 뒤 \(framed) · 아잉 \(reference)")
        }
    }

    @Test("아바타 틀: 아잉 · 황금 · 무지개 · 스프라이트 · 모르는 id 는 그대로다(identity)")
    func otherCharactersKeepPortrait() {
        for id in ["aing", "aing_gold", "aing_rainbow", "fox", "robot", "dragon", "", "AING_CAKE_CHOCO"] {
            #expect(AingCharacterArt.avatarFraming(id: id) == .identity, "\(id)")
        }
        #expect(AingCharacterArt.avatarFraming(id: nil) == .identity)
        #expect(AingCharacterArt.avatarFraming(id: " \(Self.choco) ") == AingCharacterArt.avatarFraming(id: Self.choco), "착용값 접기와 같은 규칙")
    }

    @Test("아바타 틀: 그리는 다섯 자리가 모두 틀을 쓴다(작은 원 · 내 초상 · 탭 막대 · 위젯 두 얼굴) — 주석을 걷고 본다")
    func avatarSitesApplyFraming() throws {
        let sites = [
            "Sources/CheckMobileKit/Components/CharacterPortrait.swift",
            "Sources/CheckMobileKit/Components/PersonComponents.swift",
            "Sources/CheckMobileKit/Components/CharacterTabIcon.swift",
            "Sources/CheckWidgetsKit/Widgets/AingWidgetParts.swift",
        ]
        for site in sites {
            let code = try IntegrationContractTests.code(site)
            #expect(code.contains("AingCharacterArt.avatarFraming("), "\(site) 가 아바타 틀을 안 쓴다 — 케이크 착용자만 얼굴이 작게 선다")
        }
        let widget = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingWidgetParts.swift")
        #expect(widget.components(separatedBy: "AingCharacterArt.avatarFraming(").count - 1 >= 4, "위젯 얼굴 둘(내 초상 · 남의 얼굴) 모두")
    }

    // MARK: - ③ 상점 · 고르기

    nonisolated static func shopJSON(ownsStrawberry: Bool, giftFlag: Bool = true) -> String {
        let flag = giftFlag ? #","gift_only":true"# : ""
        return #"""
        {"ruby_balance":5000,"characters":[
          {"id":"fox","price":60,"owned":true,"gacha_only":false,"gift_only":false},
          {"id":"aing_gold","price":1000,"owned":false,"gacha_only":true,"gift_only":false},
          {"id":"aing_cake_strawberry","price":2000,"owned":\#(ownsStrawberry),"gacha_only":true\#(flag)},
          {"id":"aing_cake_choco","price":2001,"owned":false,"gacha_only":true\#(flag)}]}
        """#
    }

    @Test("고르기: 케이크는 가진 사람에게만 선다 · 상점 목록에는 둘 다 선다(안 가진 것은 잠긴 칸)")
    func pickerShowsOnlyOwnedCakes() async {
        let shop = BaseLockedBox(Self.shopJSON(ownsStrawberry: true))
        let harness = await RankMeHarness(label: "me-cake-picker") { request in
            request.rpcName == "shop_state" ? .json(shop.get()) : nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        // 상점을 못 읽은 채로도 케이크는 서지 않는다(다른 캐릭터의 '못 읽으면 막지 않는다' 관용이 케이크에는 없다).
        #expect(!store.pickerIDs.contains(Self.strawberry) && !store.pickerIDs.contains(Self.choco), "\(store.pickerIDs)")
        await store.loadShop()
        #expect(store.pickerIDs.contains(Self.strawberry), "가진 케이크가 고르기에 없다: \(store.pickerIDs)")
        #expect(!store.pickerIDs.contains(Self.choco), "안 가진 케이크가 고르기에 섰다: \(store.pickerIDs)")
        #expect(store.shopRows.map(\.id).contains(Self.choco) && store.shopRows.map(\.id).contains(Self.strawberry))
        // 서버 표식이 빠진 응답(옛 모양)에서도 케이크 id 는 언제나 선물 전용이다.
        shop.mutate { $0 = Self.shopJSON(ownsStrawberry: false, giftFlag: false) }
        await store.loadShop()
        #expect(!store.pickerIDs.contains(Self.strawberry) && !store.pickerIDs.contains(Self.choco), "\(store.pickerIDs)")
        #expect(store.isGiftOnly(Self.strawberry) && store.isGiftOnly(Self.choco))
        #expect(!store.isGachaOnly(Self.choco), "케이크가 뽑기 전용으로 읽힌다 — 뽑기 기계가 열리고 '뽑기나 조각 교환으로'라고 거짓말한다")
        harness.expectNoForbiddenCalls()
    }

    @Test("상점: 안 가진 케이크는 가격 · 구매가 없고 누르면 잠긴 칸 안내 · 가진 케이크는 '이미 갖고 있어요'")
    func shopLockedCakeTile() async {
        let harness = await RankMeHarness(label: "me-cake-shop") { request in
            request.rpcName == "shop_state" ? .json(Self.shopJSON(ownsStrawberry: true)) : nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadShop()
        #expect(store.price(of: Self.choco) == nil && store.price(of: Self.strawberry) == nil, "장식값 2000 이 가격으로 섰다")
        store.selectShopItem(Self.choco)
        #expect(store.shopSelection == nil && store.shopGachaHintID == nil, "잠긴 칸이 사는 줄로 골라졌다")
        // 아래 막대의 대상은 그 칸(이름 · 얻는 길) — 사기 단추는 이 값이 있으면 서지 않는다(`MeShopView.purchaseBar`).
        #expect(store.shopGiftHintID == Self.choco)
        #expect(store.shopNotice == CakeGiftText.lockedHint && store.shopBarDetail == CakeGiftText.lockedHint)
        #expect(!store.canConfirmPurchase)
        store.confirmPurchase()
        store.selectShopItem(Self.choco)
        #expect(store.shopGiftHintID == Self.choco, "잠긴 칸을 다시 눌렀더니 안내가 풀렸다(사는 줄처럼 토글한다)")
        store.selectShopItem(Self.strawberry)
        #expect(store.shopNotice == MeText.alreadyOwned)
        #expect(store.shopGiftHintID == nil, "다른 칸을 눌렀는데 잠긴 칸 막대가 남았다")
        store.selectShopItem(Self.choco)
        store.shopDidDisappear()
        #expect(store.shopGiftHintID == nil && store.shopNotice == nil)
        // 고르기에서 안 가진 케이크를 누르면(목록에 안 서지만 — 안전망) 같은 안내이고 요청은 없다.
        store.chooseCharacter(Self.choco)
        #expect(store.characterNotice == CakeGiftText.lockedHint)
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "buy_character").isEmpty && harness.requests(rpc: "set_character").isEmpty)
    }

    @Test("타일 상태: 잠긴 칸은 자물쇠 + '생일 선물 전용' — 루비 값 · 반짝임이 아니다")
    func lockedTileContent() {
        #expect(MeCharacterTileStatus.giftOnly.content == .locked("생일 선물 전용"))
        #expect(MeCharacterTileStatus.giftOnly.content == .locked(CakeGiftText.lockedCaption))
        if case .ruby = MeCharacterTileStatus.giftOnly.content { Issue.record("잠긴 칸이 루비 값을 말한다") }
        if case .acquire = MeCharacterTileStatus.giftOnly.content { Issue.record("잠긴 칸이 뽑기 길을 말한다") }
    }

    // MARK: - ④ 축하 시트

    nonisolated static func pendingJSON(options: [String] = [strawberry, choco], id: String = giftID) -> String {
        let list = options.map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"status":"ok","gift":{"id":"\#(id)","options":[\#(list)],"note":null,"created_at":"2026-10-26T07:51:40.123456+00:00"}}"#
    }

    /// 선물 · 수령 · 상점 · 착용 응답을 상자에서 꺼내는 하네스.
    final class GiftServer: @unchecked Sendable {
        let pending = BaseLockedBox(MobileStubResponse.json(MeCakeGiftTests.pendingJSON()))
        let claim = BaseLockedBox(MobileStubResponse.json(#"{"status":"ok","character_id":"aing_cake_strawberry","replayed":false}"#))
        let shop = BaseLockedBox(MeCakeGiftTests.shopJSON(ownsStrawberry: false))

        func respond(_ request: MobileStubRequest) -> MobileStubResponse? {
            switch request.rpcName {
            case "character_gift_pending": return pending.get()
            case "claim_character_gift": return claim.get()
            case "shop_state": return .json(shop.get())
            case "set_character": return .json(#"{"status":"ok","character":"aing_cake_strawberry"}"#)
            default: return nil
            }
        }
    }

    static func harness(_ label: String, server: GiftServer) async -> RankMeHarness {
        await RankMeHarness(label: label) { server.respond($0) }
    }

    @Test("앞에 올 때: 번호 4 로 묻고 · 열린 선물이면 시트가 스스로 뜬다 · 10분 안에는 다시 묻지 않는다")
    func foregroundChecksWithThrottle() async throws {
        let server = GiftServer()
        let h = await Self.harness("me-cake-foreground", server: server)
        defer { h.tearDown() }
        let store = h.me
        store.appDidBecomeActive()
        await h.quiesceMe()
        let sent = h.requests(rpc: "character_gift_pending")
        #expect(sent.count == 1)
        #expect(Set(sent.first?.jsonBody.keys.map { $0 } ?? []) == ["p_protocol"] && sent.first?.jsonBody["p_protocol"] as? Int == 4)
        let sheet = try #require(store.cakeGiftSheet, "열린 선물인데 시트가 안 섰다")
        #expect(sheet.gift.options == [Self.strawberry, Self.choco] && sheet.phase == .choosing && sheet.selection == nil && !sheet.canConfirm)
        #expect(store.cakeGift?.id == Self.giftID && !store.showsCakeGiftReopen)

        // 9분 59초 — 묻지 않는다.
        h.clock.advance(599)
        store.appDidBecomeActive()
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == 1, "10분 안에 다시 물었다")
        // 10분 — 다시 묻는다.
        h.clock.advance(1)
        store.appDidBecomeActive()
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == 2)
        h.expectNoForbiddenCalls()
    }

    @Test("실행당 한 번: 닫은 뒤 다시 물어도 같은 선물로는 시트가 안 뜨고 '다시 열기' 줄이 남는다 · [고르기]로 다시 연다")
    func autoPresentOncePerLaunch() async throws {
        let server = GiftServer()
        let h = await Self.harness("me-cake-once", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        #expect(store.cakeGiftSheet != nil)
        store.cakeGiftSheetDidAppear()      // 시트 뷰가 화면에 섰다 — 이때 '띄웠다'로 센다
        store.dismissCakeGiftSheet()
        store.cakeGiftSheetDidDisappear()
        #expect(store.showsCakeGiftReopen, "고르지 않고 닫았는데 다시 열기 줄이 없다")
        await store.loadCakeGift()
        #expect(store.cakeGiftSheet == nil, "같은 실행에서 같은 선물로 시트가 또 떴다")
        #expect(store.showsCakeGiftReopen)
        let asked = h.requests(rpc: "character_gift_pending").count
        store.reopenCakeGift()
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == asked + 1, "[고르기]가 서버에 다시 묻지 않았다(10분 스로틀 안)")
        #expect(store.cakeGiftSheet?.gift.id == Self.giftID && !store.showsCakeGiftReopen)
        // 다른 선물(새 지급)이면 그것은 처음 보는 선물이다 — 닫혀 있으면 스스로 뜬다.
        store.dismissCakeGiftSheet()
        store.cakeGiftSheetDidDisappear()
        server.pending.mutate { $0 = .json(Self.pendingJSON(options: [Self.choco], id: "another-gift")) }
        await store.loadCakeGift()
        #expect(store.cakeGiftSheet?.gift.id == "another-gift" && store.cakeGiftSheet?.gift.options == [Self.choco])
    }

    @Test("수령: 고른 것 · 선물 id · 번호를 싣고 · 받은 뒤 화면 · 보유 · 다시 열기 거둠 · 상점 다시 읽기")
    func claimReceivesAndRereadsShop() async throws {
        let server = GiftServer()
        let h = await Self.harness("me-cake-claim", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        store.confirmCakeGift()
        #expect(h.requests(rpc: "claim_character_gift").isEmpty, "고르기 전에 수령이 나갔다")
        store.selectCakeGiftOption("fox")
        #expect(store.cakeGiftSheet?.selection == nil, "선택지 밖을 골랐다")
        store.selectCakeGiftOption(Self.strawberry)
        #expect(store.cakeGiftSheet?.canConfirm == true)
        let shopBefore = h.requests(rpc: "shop_state").count
        server.shop.mutate { $0 = Self.shopJSON(ownsStrawberry: true) }
        store.confirmCakeGift()
        #expect(store.cakeGiftSheet?.phase == .claiming)
        await h.quiesceMe()
        let body = try #require(h.requests(rpc: "claim_character_gift").last?.jsonBody)
        #expect(Set(body.keys) == ["p_gift", "p_character", "p_protocol"], "키 셋을 언제나 싣는다: \(body)")
        #expect(body["p_gift"] as? String == Self.giftID && body["p_character"] as? String == Self.strawberry && body["p_protocol"] as? Int == 4)
        #expect(store.cakeGiftSheet?.phase == .received(characterID: Self.strawberry))
        #expect(CakeGiftText.received(name: MeCharacterName.display(Self.strawberry)) == "딸기 케이크 아잉이를 받았어요!")
        #expect(store.isOwned(Self.strawberry) && store.cakeGift == nil && !store.showsCakeGiftReopen)
        #expect(h.requests(rpc: "shop_state").count == shopBefore + 1, "받은 뒤 상점을 다시 안 읽었다")
        #expect(store.pickerIDs.contains(Self.strawberry), "받은 케이크가 고르기에 없다")
        // 수령 전에 떠난 조회가 늦게 와도 선물이 되살아나지 않는다(받기 도장).
        store.dismissCakeGiftSheet()
        #expect(!store.showsCakeGiftReopen)
        h.expectNoForbiddenCalls()
    }

    @Test("받은 뒤 [지금 입기]: 시트를 닫고 기존 착용 경로(set_character)로 입는다")
    func wearNowUsesExistingPath() async throws {
        let server = GiftServer()
        let h = await Self.harness("me-cake-wear", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadShop()
        await store.loadCakeGift()
        store.selectCakeGiftOption(Self.strawberry)
        // 받은 뒤의 서버(보유 기입이 끝났다) — 받은 뒤 다시 읽는 상점이 이 값을 준다.
        server.shop.mutate { $0 = Self.shopJSON(ownsStrawberry: true) }
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(store.isOwned(Self.strawberry))
        store.wearReceivedCakeGift()
        #expect(store.cakeGiftSheet == nil)
        await h.quiesceMe()
        let body = try #require(h.requests(rpc: "set_character").last?.jsonBody)
        #expect(body["p_id"] as? String == Self.strawberry, "\(body)")
        #expect(store.equippedCharacterID == Self.strawberry, "착용값이 아잉으로 접혔다 — 카드 표가 케이크를 모른다")
        #expect(store.characterNotice == MeText.characterSaved)
    }

    @Test("수령 실패 갈래: 오프라인은 다시 누르게 · 업데이트 필요는 선물을 남기고 · 내 선물 아님은 거두고 · 이미 받음(id)은 받은 화면")
    func claimFailureBranches() async throws {
        let server = GiftServer()
        let h = await Self.harness("me-cake-fail", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()

        // ① 오프라인 — 결과를 모른다: 고르는 화면 + 실패 문구, 선물은 그대로.
        server.claim.mutate { $0 = .networkFailure() }
        store.selectCakeGiftOption(Self.choco)
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.phase == .choosing && store.cakeGiftSheet?.notice == CakeGiftText.claimFailed)
        #expect(store.cakeGiftSheet?.selection == Self.choco, "다시 누를 수 있게 고른 것이 남아야 한다")
        #expect(store.cakeGift != nil)

        // ② 업데이트 필요 — 아무것도 안 움직였다: 안내, 선물은 열린 채(닫으면 다시 열기 줄).
        server.claim.mutate { $0 = .json(#"{"status":"needs_update","min_protocol":4}"#) }
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.phase == .choosing && store.cakeGiftSheet?.notice == CakeGiftText.needsUpdate)
        store.dismissCakeGiftSheet()
        #expect(store.showsCakeGiftReopen)

        // ③ 서버 미배포(404) — 받을 수 없다는 안내, 선물은 그대로.
        store.reopenCakeGift()
        await h.quiesceMe()
        store.selectCakeGiftOption(Self.choco)
        server.claim.mutate { $0 = .missingFunction("claim_character_gift") }
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.notice == CakeGiftText.unavailable && store.cakeGift != nil)

        // ④ 이미 다른 것으로 받음(id 있음) — 받은 화면으로(그 사람은 이미 가졌다), 선물은 거둔다.
        server.shop.mutate { $0 = Self.shopJSON(ownsStrawberry: true) }
        server.claim.mutate { $0 = .json(#"{"status":"already_claimed","character_id":"aing_cake_strawberry"}"#) }
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.phase == .received(characterID: Self.strawberry))
        #expect(store.isOwned(Self.strawberry) && store.cakeGift == nil && !store.showsCakeGiftReopen)
    }

    @Test("내 선물이 아님(not_found): 안내와 [닫기]만 · 선물을 거둔다")
    func notFoundClosesGift() async {
        let server = GiftServer()
        server.claim.mutate { $0 = .json(#"{"status":"not_found"}"#) }
        let h = await Self.harness("me-cake-notfound", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        store.selectCakeGiftOption(Self.strawberry)
        store.confirmCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.phase == .closed && store.cakeGiftSheet?.notice == CakeGiftText.notFound)
        #expect(store.cakeGift == nil && !store.isOwned(Self.strawberry))
        store.dismissCakeGiftSheet()
        #expect(!store.showsCakeGiftReopen)
    }

    @Test("옛 서버(404) · 선물 없음 · 번호 3 빌드: 시트도 줄도 없다 — 번호 3 이면 묻지도 않는다")
    func noGiftCases() async {
        let server = GiftServer()
        server.pending.mutate { $0 = .missingFunction("character_gift_pending") }
        let h = await Self.harness("me-cake-none", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        #expect(store.cakeGift == nil && store.cakeGiftSheet == nil && !store.showsCakeGiftReopen)
        server.pending.mutate { $0 = .json(#"{"status":"ok"}"#) }
        await store.loadCakeGift()
        #expect(store.cakeGift == nil && store.cakeGiftSheet == nil)
        // 케이크를 다 못 그리는 빌드(번호 3)는 묻지 않는다 — 서버도 gift 를 안 싣는다(헛왕복).
        let before = h.requests(rpc: "character_gift_pending").count
        store.drawableCharacterIDs = AingCharacterArt.knownIDs.filter { $0 != Self.choco }
        server.pending.mutate { $0 = .json(Self.pendingJSON()) }
        await store.loadCakeGift()
        #expect(h.requests(rpc: "character_gift_pending").count == before && store.cakeGiftSheet == nil)
    }

    @Test("계정이 바뀌면(reset) 선물 · 시트 · 스로틀을 비운다 — 다음 계정은 곧바로 묻는다")
    func resetClearsGift() async {
        let server = GiftServer()
        let h = await Self.harness("me-cake-reset", server: server)
        defer { h.tearDown() }
        let store = h.me
        store.refreshCakeGiftIfStale()
        await h.quiesceMe()
        #expect(store.cakeGift != nil && store.cakeGiftCheckedAt != nil)
        store.cakeGiftSheetDidAppear()
        store.reset()
        #expect(store.cakeGift == nil && store.cakeGiftSheet == nil && store.cakeGiftCheckedAt == nil && !store.showsCakeGiftReopen)
        #expect(store.cakeGiftAutoShownIDs.contains(Self.giftID), "실행당 한 번 기록은 계정이 아니라 실행에 묶인다")
    }

    @Test("늦은 조회: 수령 전에 떠난 조회(열린 선물)가 수령 뒤에 도착해도 선물 · 다시 열기 줄을 되살리지 않는다")
    func lateFetchAfterClaimIsDropped() async {
        let server = GiftServer()
        let h = await Self.harness("me-cake-late", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        store.selectCakeGiftOption(Self.strawberry)
        // ① 조회 하나를 붙잡아 둔다 — 응답은 수령 **전**의 서버(열린 선물).
        let hold = BaseHold.install(host: h.host) { $0.rpcName == "character_gift_pending" }
        h.clock.advance(Double(MeStore.cakeGiftCheckInterval))
        store.refreshCakeGiftIfStale()
        #expect(await hold.waitHeld(1))
        // ② 그 사이 수령이 끝난다.
        store.confirmCakeGift()
        // 붙잡힌 조회도 `inflight` 에 있어 `quiesceMe` 는 못 쓴다 — 받은 뒤 상점 다시 읽기까지 끝나기를 조건으로 기다린다.
        #expect(await baseWaitUntil { store.cakeGiftSheet?.phase == .received(characterID: Self.strawberry) && !store.shopState.isLoading })
        #expect(store.cakeGift == nil)
        store.dismissCakeGiftSheet()
        // ③ 붙잡힌 조회가 이제 도착한다 — 버려야 한다.
        #expect(await hold.releaseAndWaitDelivered())
        await h.quiesceMe()
        #expect(store.cakeGift == nil && !store.showsCakeGiftReopen && store.cakeGiftSheet == nil,
                "수령 전에 떠난 조회가 받은 선물을 되살렸다")
        // 기준선: 도장이 같은(수령이 끼지 않은) 조회는 옮긴다 — 새로 열린 선물이면 줄이 선다.
        server.pending.mutate { $0 = .json(Self.pendingJSON(options: [Self.choco], id: "fresh-gift")) }
        await store.loadCakeGift()
        #expect(store.cakeGift?.id == "fresh-gift")
    }

    // MARK: - ⑤ 데모 픽스처

    static let fixtures = MobileDemoFixtures.load()

    static func demoRequest(_ rpc: String, body: String) -> MobileStubRequest {
        MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)", query: "", headers: [:], bodyText: body)
    }

    static let snakeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("데모: 모든 데모 라우트에서 선물 조회가 404 없이 '선물 없음'이다(심사원 화면에 축하 시트가 안 뜬다)")
    func demoPendingIsNoGiftEverywhere() throws {
        for route in IntegrationContractTests.demoRoutes {
            let scene = route.replacingOccurrences(of: "/", with: "-").lowercased()
            let response = Self.fixtures.response(for: Self.demoRequest("character_gift_pending", body: #"{"p_protocol":4}"#),
                                                  scenario: scene)
            #expect(response.status == 200, "데모 라우트 \(route) 에서 character_gift_pending 이 \(response.status)")
            let decoded = try Self.snakeDecoder.decode(CharacterGiftPendingResponse.self, from: response.body)
            #expect(decoded.status == "ok" && decoded.offer == nil, "데모 라우트 \(route) 에 열린 선물이 있다 — 심사원 화면에 축하 시트가 뜬다")
        }
    }

    @Test("데모 me/gift…: 바늘로 열린 선물(딸기 · 초코)을 고르고 나 탭을 연다 · 케이크 없는 여우 착용자 · 받은 뒤엔 받은 것만 보유 · 선물 없음")
    func demoGiftRoute() throws {
        #expect(MobileDemoCakeGiftRoute(demoRoute: "me/gift") == MobileDemoCakeGiftRoute(action: nil))
        #expect(MobileDemoCakeGiftRoute(demoRoute: "me/gift/picked")?.action == "picked")
        #expect(MobileDemoCakeGiftRoute(demoRoute: "/me/gift/received/")?.action == "received")
        #expect(MobileDemoCakeGiftRoute(demoRoute: "me/gift/dismissed")?.action == "dismissed")
        #expect(MobileDemoCakeGiftRoute(demoRoute: "me/gift/whatever")?.action == nil)
        #expect(MobileDemoCakeGiftRoute(demoRoute: "me/shop") == nil && MobileDemoCakeGiftRoute(demoRoute: "me/gifts") == nil)
        let route = try #require(MobileDemoCakeGiftRoute(demoRoute: "me/gift"))
        #expect(AingRoute(path: route.openRoute) != nil, "열 라우트를 앱이 모른다")
        let pending = Self.fixtures.response(
            for: route.rewrite(Self.demoRequest("character_gift_pending", body: #"{"p_protocol":4}"#)), scenario: route.scene)
        let offer = try #require(try Self.snakeDecoder.decode(CharacterGiftPendingResponse.self, from: pending.body).offer,
                                 "me/gift 장면에 열린 선물이 없다")
        #expect(offer.options == [Self.strawberry, Self.choco])
        // 서버가 만들 수 있는 상태여야 한다: 서버는 가진 케이크를 선택지에서 뺀다 — 선물 장면의 나는 케이크를 **하나도** 안 가졌고
        // 여우를 입고 있다(예전 픽스처는 딸기를 가지고 입은 사람에게 딸기 · 초코를 선택지로 줬다).
        let equipped = MobileStubRequest(method: "GET", host: MobileDemo.host, path: "/rest/v1/profiles", query: "select=character&id=eq.\(MobileDemo.userID)",
                                         headers: [:], bodyText: "")
        let worn = Self.fixtures.response(for: route.rewrite(equipped), scenario: route.scene)
        #expect(String(decoding: worn.body, as: UTF8.self).contains("\"fox\""), "선물 장면의 착용값이 여우가 아니다")
        let shopRequest = Self.demoRequest("shop_state", body: #"{"p_protocol":4}"#)
        let before = try Self.demoOwnedCakes(Self.fixtures.response(for: route.rewrite(shopRequest), scenario: route.scene))
        #expect(before.isEmpty, "선물 장면(받기 전)에 이미 가진 케이크가 있다: \(before)")
        #expect(Set(offer.options).isDisjoint(with: before), "가진 케이크가 선택지에 있다 — 서버에서 불가능한 상태")
        // 일반 상점 장면(심사원의 기본 경로)은 케이크 두 행(딸기 보유 · 초코 잠김) 그대로 — 그 장면의 선물 조회는 '선물 없음'이다.
        #expect(try Self.demoOwnedCakes(Self.fixtures.response(for: shopRequest, scenario: "me")) == [Self.strawberry])
        let plainPending = Self.fixtures.response(for: Self.demoRequest("character_gift_pending", body: #"{"p_protocol":4}"#), scenario: "me")
        #expect(try Self.snakeDecoder.decode(CharacterGiftPendingResponse.self, from: plainPending.body).offer == nil)
        for choice in [Self.strawberry, Self.choco] {
            // 데모 한 실행 = 기록 한 벌. 받기 전 바늘로 수령을 부르고, 응답을 기록하면 그 뒤 요청은 받은 뒤 바늘로 고른다.
            let ledger = MobileDemoCakeGiftRoute.Ledger()
            let claimRequest = Self.demoRequest("claim_character_gift",
                                                body: #"{"p_gift":"\#(offer.id)","p_character":"\#(choice)","p_protocol":4}"#)
            let claim = Self.fixtures.response(for: route.rewrite(claimRequest, ledger: ledger), scenario: route.scene)
            let decoded = try Self.snakeDecoder.decode(CharacterGiftClaimResponse.self, from: claim.body)
            #expect(CharacterGiftClaimOutcome(response: decoded, requestedID: choice) == .received(characterID: choice, replayed: false))
            ledger.record(claimRequest, response: claim)
            // 받은 뒤: 상점은 받은 것**만** 보유 · 선물 조회는 선물 없음(받은 케이크와 열린 선물이 같이 서지 않는다).
            let after = try Self.demoOwnedCakes(Self.fixtures.response(for: route.rewrite(shopRequest, ledger: ledger), scenario: route.scene))
            #expect(after == [choice], "받은 뒤 상점 보유가 \(after) 다(기대 \(choice) 하나)")
            let pendingAfter = Self.fixtures.response(
                for: route.rewrite(Self.demoRequest("character_gift_pending", body: #"{"p_protocol":4}"#), ledger: ledger), scenario: route.scene)
            #expect(pendingAfter.status == 200)
            #expect(try Self.snakeDecoder.decode(CharacterGiftPendingResponse.self, from: pendingAfter.body).offer == nil,
                    "받은 뒤에도 선물이 열려 있다")
            // [지금 입기]는 받은 것으로 · 받은 뒤 바늘이 다른 착용 요청을 가로채지 않는다(바늘에 캐릭터 id 를 통째로 넣지 않는 까닭).
            let wear = Self.fixtures.response(for: route.rewrite(Self.demoRequest("set_character", body: #"{"p_id":"\#(choice)"}"#),
                                                                 ledger: ledger), scenario: route.scene)
            #expect(try Self.snakeDecoder.decode(SetCharacterResponse.self, from: wear.body).character == choice)
            let other = Self.fixtures.response(for: route.rewrite(Self.demoRequest("set_character", body: #"{"p_id":"fox"}"#),
                                                                  ledger: ledger), scenario: route.scene)
            #expect(try Self.snakeDecoder.decode(SetCharacterResponse.self, from: other.body).character?.hasPrefix("aing_cake") == false,
                    "받은 뒤 바늘이 여우 착용 요청을 케이크 응답으로 가로챘다")
        }
        // 수령이 아닌 요청 · 실패한 수령은 기록하지 않는다(받기 전 바늘 그대로).
        let idle = MobileDemoCakeGiftRoute.Ledger()
        idle.record(shopRequest, response: .json(#"{"status":"ok","character_id":"aing_cake_choco"}"#))
        idle.record(Self.demoRequest("claim_character_gift", body: "{}"), response: .json(#"{"status":"not_found"}"#))
        idle.record(Self.demoRequest("claim_character_gift", body: "{}"), response: .json(#"{"status":"ok","character_id":"fox"}"#))
        #expect(idle.needle == MobileDemoCakeGiftRoute.needle)
    }

    /// 데모 상점 응답에서 **가진** 케이크 id(서버 순서).
    static func demoOwnedCakes(_ response: MobileStubResponse) throws -> [String] {
        #expect(response.status == 200)
        let rows = try #require(try snakeDecoder.decode(ShopStateResponse.self, from: response.body).characters)
        return rows.filter { CharacterCatalog.isCakeAing($0.id) && $0.owned == true }.map(\.id)
    }

    @Test("데모 선물 라우트 값은 #if DEBUG 안에만 있다 — Release 바이너리에 이름이 남지 않는다(출시 게이트 금지 심볼 MobileDemo)")
    func demoGiftRouteIsDebugOnly() throws {
        let file = try String(contentsOf: Self.root.appendingPathComponent("Sources/CheckMobileKit/Demo/MobileDemoCakeGiftRoute.swift"),
                              encoding: .utf8)
        let lines = file.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.first == "#if DEBUG" && lines.last == "#endif", "값 파일이 통째로 DEBUG 가 아니다")
        let users = try IntegrationContractTests.files(containing: ["MobileDemoCakeGiftRoute"], under: "Sources")
        #expect(users == ["Sources/CheckMobileKit/Demo/MobileDemo.swift", "Sources/CheckMobileKit/Demo/MobileDemoCakeGiftRoute.swift",
                          "Sources/CheckMobileKit/Me/MeTab.swift"], "\(users)")
        // Demo/ 밖의 한 자리(나 탭 데모 훅)는 `#if DEBUG` 갈래 안이어야 한다 — 가장 가까운 위쪽 분기 줄이 `#if DEBUG` 다.
        let tab = stripComments(try String(contentsOf: Self.root.appendingPathComponent("Sources/CheckMobileKit/Me/MeTab.swift"),
                                                                    encoding: .utf8))
        let tabLines = tab.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for (index, line) in tabLines.enumerated() where line.contains("MobileDemoCakeGiftRoute") {
            let branch = tabLines[..<index].last { $0.hasPrefix("#if") || $0.hasPrefix("#else") || $0.hasPrefix("#endif") }
            #expect(branch == "#if DEBUG", "MeTab.swift \(index + 1)번째 줄의 데모 값이 DEBUG 갈래 밖이다(\(branch ?? "분기 없음"))")
        }
    }

    @Test("데모 상점: 두 상점 픽스처에 케이크 두 행(gift_only · gacha_only · 2000/2001 · 딸기만 보유) · 살 수 없다",
          arguments: ["me/_me/rpc.shop_state.json", "me/_me-shop/rpc.shop_state.json"])
    func demoShopCakeRows(path: String) throws {
        let entry = try #require(Self.fixtures.entries.first { $0.relativePath == path })
        let state = try Self.snakeDecoder.decode(ShopStateResponse.self, from: entry.data)
        let rows = try #require(state.characters)
        let strawberry = try #require(rows.first { $0.id == Self.strawberry })
        let choco = try #require(rows.first { $0.id == Self.choco })
        #expect(strawberry.giftOnly == true && strawberry.gachaOnly == true && strawberry.price == 2000 && strawberry.owned == true)
        #expect(choco.giftOnly == true && choco.gachaOnly == true && choco.price == 2001 && choco.owned == false)
        #expect(!strawberry.isPurchasable && !choco.isPurchasable && choco.isGiftOnly && !choco.isGachaOnly)
        // 서버 순서 그대로(가격 → id): 케이크 둘이 맨 뒤, 딸기 → 초코.
        #expect(rows.suffix(2).map(\.id) == [Self.strawberry, Self.choco])
        #expect(rows.dropLast(2).allSatisfy { $0.giftOnly == false }, "케이크가 아닌 줄의 gift_only 는 false 다(서버 모양)")
        // 확률표 · 교환표에는 케이크가 없다(뽑기 ✗ · 조각 교환 ✗).
        let gacha = try #require(state.gacha)
        #expect(!(gacha.odds ?? []).contains { CharacterCatalog.isCakeAing($0.characterID) })
        #expect(!(gacha.shardCosts ?? [:]).keys.contains { CharacterCatalog.isCakeAing($0) })
    }

    @Test("데모 지금 탭: 케이크 착용자가 있고(얼굴 크기 스크린샷) 이 빌드는 그를 이니셜로 접지 않는다")
    func demoCakeWearers() throws {
        let response = Self.fixtures.response(for: Self.demoRequest("app_user_characters", body: "{}"), scenario: "now")
        let rows = try Self.snakeDecoder.decode([AppUserCharacterRow].self, from: response.body)
        let directory = AppUserCharacterDirectory(knownIDs: AingCharacterArt.knownIDs, rows: rows)
        // 코랄(201) · 하늘(202)은 지금 탭 '지금 근무 중' 목록에 서는 사람이다(디렉터리 is_working) — 라임(아잉) · 보리(무지개) 옆에서
        // 얼굴 크기를 눈으로 맞대는 자리다.
        #expect(directory.characterID(for: "d0000000-0000-4000-8000-000000000201") == Self.choco)
        #expect(directory.characterID(for: "d0000000-0000-4000-8000-000000000202") == Self.strawberry)
        #expect(directory.avatar(for: "d0000000-0000-4000-8000-000000000201", photoURL: nil) == .character(Self.choco))
        #expect(directory.characterID(for: "d0000000-0000-4000-8000-000000000104") == "aing_rainbow", "무지개 착용자(보리)는 그대로")
    }
}
