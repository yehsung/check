@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 케이크 아잉이 · 생일 선물 — 폰 검토 지적의 수리(v0366-fix-phone). 짝 파일 `MeCakeGiftTests` 의 하네스(`GiftServer`)를 그대로 쓴다.
//
//   ① 받는 중 [X]: 받는 중(.claiming)에는 시트가 닫히지 않는다 — 수령이 끝나면 받은 뒤 화면 · [지금 입기]가 선다
//   ② 다른 기기 수령: 상점이 새 보유를 말하면 선택지를 거르고(가진 것을 고르는 길이 없다) · 서버에 다시 묻고 · 남는 게 없으면 줄을 거둔다
//   ③ 다시 열기 [고르기]: 스로틀을 건너뛰고 다시 묻는다 — 닫힌 선물이면 시트 없이 줄이 걷힌다 · 오프라인이면 아는 선물(거른 값)로 연다
//   ④ 대국 중 미루기: 오목 · 체스 · 테트리스 화면이 떠 있으면 스스로 뜨지 않는다(다시 열기 줄만) · 앞으로 올 때 · 탭을 옮길 때 띄운다 ·
//      실행당 한 번은 **화면에 선 때** 센다
//   ⑤ 뷰 배선(맥 스위트가 못 보는 `#if os(iOS)` — 주석을 걷은 소스로 잰다): 시트 내용은 item 으로 · 받는 중 [X] 꺼짐 · 상점 막대
@MainActor
@Suite struct MeCakeGiftRepairTests {
    typealias Gift = MeCakeGiftTests
    static let strawberry = Gift.strawberry
    static let choco = Gift.choco

    // MARK: - ① 받는 중 [X]

    @Test("받는 중(.claiming)에는 닫기가 먹지 않는다 — 수령이 끝나면 받은 뒤 화면 · [지금 입기]")
    func dismissIgnoredWhileClaiming() async throws {
        let server = Gift.GiftServer()
        let h = await Gift.harness("me-cake-fix-claiming", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        store.selectCakeGiftOption(Self.strawberry)
        server.shop.mutate { $0 = Gift.shopJSON(ownsStrawberry: true) }
        store.confirmCakeGift()
        #expect(store.cakeGiftSheet?.phase == .claiming)
        store.dismissCakeGiftSheet()          // 머리 [X] · 끌어 내림 바인딩이 부르는 문
        #expect(store.cakeGiftSheet?.phase == .claiming, "받는 중에 시트가 닫혔다 — 결과를 모른 채 사라진다")
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.phase == .received(characterID: Self.strawberry), "받은 뒤 화면이 안 섰다")
        #expect(store.isOwned(Self.strawberry) && store.cakeGift == nil && !store.showsCakeGiftReopen)
        // 받은 뒤에는 닫힌다(기준선 — 닫기 문 자체가 죽은 것이 아니다).
        store.dismissCakeGiftSheet()
        #expect(store.cakeGiftSheet == nil)
        #expect(h.requests(rpc: "claim_character_gift").count == 1)
    }

    // MARK: - ② 다른 기기 수령

    @Test("다른 기기에서 받았다: 상점이 보유를 말하면 선택지를 거르고 서버에 다시 묻는다 — 선물이 닫혔으면 다시 열기 줄이 걷힌다(10분 안)")
    func otherDeviceClaimClearsReopenRow() async throws {
        let server = Gift.GiftServer()
        let h = await Gift.harness("me-cake-fix-other-device", server: server)
        defer { h.tearDown() }
        let store = h.me
        store.appDidBecomeActive()
        await h.quiesceMe()
        store.cakeGiftSheetDidAppear()
        store.dismissCakeGiftSheet()
        store.cakeGiftSheetDidDisappear()
        #expect(store.showsCakeGiftReopen)
        let asked = h.requests(rpc: "character_gift_pending").count
        // 맥에서 딸기를 받았다 → 서버: 선물 닫힘 · 딸기 보유.
        server.pending.mutate { $0 = .json(#"{"status":"ok"}"#) }
        server.shop.mutate { $0 = Gift.shopJSON(ownsStrawberry: true) }
        await store.loadShop()
        // 상점이 읽힌 그 자리에서 선택지는 이미 걸러져 있다(가진 딸기를 고르는 길이 없다).
        #expect(store.cakeGift.map { $0.options == [Self.choco] } ?? true, "가진 딸기가 선택지에 남았다: \(String(describing: store.cakeGift))")
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == asked + 1, "보유가 움직였는데 서버에 다시 묻지 않았다(스로틀 안)")
        #expect(store.cakeGift == nil && !store.showsCakeGiftReopen && store.cakeGiftSheet == nil,
                "다른 기기에서 받은 선물이 폰에 남았다")
    }

    @Test("다른 기기에서 둘 다 가졌다: 서버에 못 물어도(오프라인) 남는 선택지가 없으면 선물 · 줄을 거둔다")
    func allOptionsOwnedDropsGiftEvenOffline() async throws {
        let server = Gift.GiftServer()
        let h = await Gift.harness("me-cake-fix-all-owned", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        store.cakeGiftSheetDidAppear()
        store.dismissCakeGiftSheet()
        store.cakeGiftSheetDidDisappear()
        #expect(store.showsCakeGiftReopen)
        server.pending.mutate { $0 = .networkFailure() }
        server.shop.mutate {
            $0 = Gift.shopJSON(ownsStrawberry: true).replacingOccurrences(
                of: #"{"id":"aing_cake_choco","price":2001,"owned":false"#, with: #"{"id":"aing_cake_choco","price":2001,"owned":true"#)
        }
        await store.loadShop()
        #expect(store.isOwned(Self.strawberry) && store.isOwned(Self.choco), "픽스처가 둘 다 보유를 말하지 않는다 — 기준선이 틀렸다")
        #expect(store.cakeGift == nil && !store.showsCakeGiftReopen)
        await h.quiesceMe()
        #expect(store.cakeGift == nil, "실패한 조회가 지난 선물을 되살렸다")
    }

    @Test("고르는 중에 다른 기기에서 받았다: 시트 선택지가 걸러지고 고른 것이 풀린다 · 둘 다 가졌으면 '이미 받은 선물이에요' + [닫기]")
    func choosingSheetFollowsOwnership() async throws {
        let server = Gift.GiftServer()
        let h = await Gift.harness("me-cake-fix-sheet-owned", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        store.selectCakeGiftOption(Self.strawberry)
        server.shop.mutate { $0 = Gift.shopJSON(ownsStrawberry: true) }
        await store.loadShop()
        let sheet = try #require(store.cakeGiftSheet)
        #expect(sheet.phase == .choosing && sheet.gift.options == [Self.choco] && sheet.selection == nil && !sheet.canConfirm,
                "가진 딸기를 고른 채로 [이걸로 받을게요]가 켜져 있다: \(sheet)")
        store.selectCakeGiftOption(Self.strawberry)
        #expect(store.cakeGiftSheet?.selection == nil, "가진 케이크를 고를 수 있다")
        await h.quiesceMe()
        // 서버는 아직 선물을 연 채(초코)라고 말한다 — 시트는 초코 하나로 남는다.
        #expect(store.cakeGiftSheet?.gift.options == [Self.choco])
        // 이제 초코도 가졌다(다른 기기) — 고를 것이 없다.
        server.pending.mutate { $0 = .json(#"{"status":"ok"}"#) }
        server.shop.mutate {
            $0 = Gift.shopJSON(ownsStrawberry: true).replacingOccurrences(
                of: #"{"id":"aing_cake_choco","price":2001,"owned":false"#, with: #"{"id":"aing_cake_choco","price":2001,"owned":true"#)
        }
        await store.loadShop()
        #expect(store.cakeGiftSheet?.phase == .closed && store.cakeGiftSheet?.notice == CakeGiftText.alreadyClaimed)
        await h.quiesceMe()
        store.dismissCakeGiftSheet()
        #expect(store.cakeGiftSheet == nil && !store.showsCakeGiftReopen)
        #expect(h.requests(rpc: "claim_character_gift").isEmpty)
    }

    // MARK: - ③ 다시 열기 [고르기]

    @Test("[고르기]: 스로틀 안에서도 서버에 다시 묻는다 — 닫힌 선물이면 시트 없이 줄이 걷히고 · 열려 있으면 보유와 거른 선택지로 연다")
    func reopenAsksServerFirst() async throws {
        let server = Gift.GiftServer()
        let h = await Gift.harness("me-cake-fix-reopen", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        store.cakeGiftSheetDidAppear()
        store.dismissCakeGiftSheet()
        store.cakeGiftSheetDidDisappear()
        // ① 서버가 아직 두 선택지를 말해도(낡은 응답) 상점이 딸기 보유를 말하면 시트에는 초코만 선다.
        server.shop.mutate { $0 = Gift.shopJSON(ownsStrawberry: true) }
        await store.loadShop()
        await h.quiesceMe()
        let asked = h.requests(rpc: "character_gift_pending").count
        store.reopenCakeGift()
        #expect(store.cakeGiftReopening, "묻는 동안 단추가 돌지 않는다")
        store.reopenCakeGift()                  // 겹쳐 누르기 — 한 번만 묻는다
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == asked + 1)
        #expect(!store.cakeGiftReopening)
        #expect(store.cakeGiftSheet?.gift.options == [Self.choco], "이미 가진 딸기를 고르는 길이 열렸다: \(String(describing: store.cakeGiftSheet))")
        store.dismissCakeGiftSheet()
        // ② 오프라인 — 아는 선물(거른 값)로 연다. 수령이 서버에서 다시 판정된다.
        server.pending.mutate { $0 = .networkFailure() }
        store.reopenCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet?.gift.options == [Self.choco])
        store.dismissCakeGiftSheet()
        // ③ 서버가 선물 없음 — 시트는 안 뜨고 줄이 걷힌다.
        server.pending.mutate { $0 = .json(#"{"status":"ok"}"#) }
        store.reopenCakeGift()
        await h.quiesceMe()
        #expect(store.cakeGiftSheet == nil && store.cakeGift == nil && !store.showsCakeGiftReopen)
        #expect(h.requests(rpc: "claim_character_gift").isEmpty)
    }

    // MARK: - ④ 대국 중 미루기 · 실행당 한 번은 화면에 선 때

    @Test("대국·관전 화면이 떠 있으면 스스로 뜨지 않는다(다시 열기 줄만) · 화면을 떠나 앞으로 올 때 띄운다", arguments: ["gomoku", "chess", "tetris"])
    func deferWhileMatchScreenVisible(game: String) async throws {
        let server = Gift.GiftServer()
        let h = await Gift.harness("me-cake-fix-defer-\(game)", server: server)
        defer { h.tearDown() }
        let store = h.me
        let games = h.model.games
        switch game {
        case "gomoku": games.gomokuScreenDidAppear()
        case "chess": games.chessScreenDidAppear()
        default: games.tetrisScreenDidAppear()
        }
        #expect(games.isAnyMatchScreenVisible)
        store.appDidBecomeActive()
        await h.quiesceMe()
        #expect(store.cakeGift != nil, "선물을 못 받았다 — 기준선")
        #expect(store.cakeGiftSheet == nil, "\(game) 화면 위에 축하 시트가 섰다")
        #expect(store.showsCakeGiftReopen, "미룬 동안 다시 열기 줄이 없다")
        #expect(!store.cakeGiftAutoShownIDs.contains(Gift.giftID), "띄우지도 않았는데 실행당 한 번을 썼다")
        // 아직 화면 위 — 앞으로 와도 미룬다.
        store.appDidBecomeActive()
        #expect(store.cakeGiftSheet == nil)
        switch game {
        case "gomoku": games.gomokuScreenDidDisappear()
        case "chess": games.chessScreenDidDisappear()
        default: games.tetrisScreenDidDisappear()
        }
        #expect(!games.isAnyMatchScreenVisible)
        // 다음 기회: 앞으로 올 때(묻지 않고 아는 선물로 — 10분 스로틀 안).
        let asked = h.requests(rpc: "character_gift_pending").count
        store.appDidBecomeActive()
        #expect(store.cakeGiftSheet?.gift.id == Gift.giftID, "대국 화면을 떠난 뒤에도 시트가 안 선다")
        await h.quiesceMe()
        #expect(h.requests(rpc: "character_gift_pending").count == asked, "미룬 시트를 띄우려고 서버에 또 물었다")
    }

    @Test("탭을 옮길 때도 미룬 시트를 띄운다 — 단 게임 탭으로 들어갈 때는 아니다")
    func tabChangePresentsDeferredSheet() async throws {
        let server = Gift.GiftServer()
        let h = await Gift.harness("me-cake-fix-tab", server: server)
        defer { h.tearDown() }
        let store = h.me
        let games = h.model.games
        games.tetrisScreenDidAppear()
        await store.loadCakeGift()
        #expect(store.cakeGiftSheet == nil && store.showsCakeGiftReopen)
        games.tetrisScreenDidDisappear()
        h.model.router.selectedTab = .games
        h.model.tabDidChange()
        #expect(store.cakeGiftSheet == nil, "게임 탭으로 들어가는 순간 시트가 섰다 — 곧 설 대국 화면을 덮는다")
        h.model.router.selectedTab = .me
        h.model.tabDidChange()
        #expect(store.cakeGiftSheet?.gift.id == Gift.giftID)
    }

    @Test("실행당 한 번은 화면에 선 때 센다: 못 띄우고 내린 시트(다른 시트가 떠 있었다)는 다음 기회에 다시 · 섰다가 닫은 시트는 다시 안 뜬다")
    func oncePerLaunchCountsOnlyShownSheets() async throws {
        let server = Gift.GiftServer()
        let h = await Gift.harness("me-cake-fix-once", server: server)
        defer { h.tearDown() }
        let store = h.me
        await store.loadCakeGift()
        #expect(store.cakeGiftSheet != nil)
        // 탭 막대의 '못 띄운 시트 거두기'(2초 안에 화면에 안 섰다) — 같은 문(`dismissCakeGiftSheet`)으로 내린다.
        store.dismissCakeGiftSheet()
        #expect(store.showsCakeGiftReopen)
        store.appDidBecomeActive()
        #expect(store.cakeGiftSheet != nil, "한 번도 화면에 못 선 선물인데 다음 기회에 다시 안 떴다")
        store.cakeGiftSheetDidAppear()
        store.dismissCakeGiftSheet()
        store.cakeGiftSheetDidDisappear()
        store.appDidBecomeActive()
        h.model.tabDidChange()
        await store.loadCakeGift()
        #expect(store.cakeGiftSheet == nil, "화면에 섰다가 닫은 선물이 같은 실행에서 또 떴다")
        #expect(store.showsCakeGiftReopen)
    }

    // MARK: - 데모 선물 장면 상점 변형

    @Test("데모 선물 장면 상점 변형 셋은 _me 상점과 케이크 보유 칸만 다르다(받기 전 둘 다 잠김 · 받은 뒤 받은 것만)")
    func giftSceneShopVariants() throws {
        func object(_ path: String) throws -> [String: Any] {
            let entry = try #require(MeRainbowFixtureContractTests.index.entries.first { $0.relativePath == path }, "\(path) 가 없다")
            return try #require(try JSONSerialization.jsonObject(with: entry.data) as? [String: Any])
        }
        /// 케이크 보유 칸을 걷어 낸 모양(비교용) · 케이크 보유 표.
        func split(_ shop: [String: Any]) throws -> (rest: NSDictionary, owned: [String: Bool]) {
            var copy = shop
            var owned: [String: Bool] = [:]
            let rows = try #require(shop["characters"] as? [[String: Any]])
            copy["characters"] = rows.map { row -> [String: Any] in
                guard let id = row["id"] as? String, CharacterCatalog.isCakeAing(id) else { return row }
                owned[id] = row["owned"] as? Bool
                var stripped = row
                stripped["owned"] = nil
                return stripped
            }
            return (copy as NSDictionary, owned)
        }
        let base = try split(try object("me/_me/rpc.shop_state.json"))
        let want: [String: [String: Bool]] = [
            "me/_me/rpc.shop_state@demo-gift.json": [Self.strawberry: false, Self.choco: false],
            "me/_me/rpc.shop_state@demo-gift-got-strawberry.json": [Self.strawberry: true, Self.choco: false],
            "me/_me/rpc.shop_state@demo-gift-got-choco.json": [Self.strawberry: false, Self.choco: true],
        ]
        #expect(Set(want.keys) == Set(MeRainbowFixtureContractTests.giftScenePaths))
        for (path, owned) in want {
            let variant = try split(try object(path))
            #expect(variant.rest == base.rest, "\(path) 가 케이크 보유 밖에서 _me 상점과 다르다")
            #expect(variant.owned == owned, "\(path) 케이크 보유 \(variant.owned)")
        }
        #expect(base.owned == [Self.strawberry: true, Self.choco: false], "일반 상점 장면(심사원 기본 경로)의 케이크 두 행이 바뀌었다")
    }

    // MARK: - ⑤ 뷰 배선(iOS 전용 — 소스로)

    @Test("뷰 배선: 시트 내용은 .sheet(item:) 의 item 으로 · 받는 중 [X] 꺼짐 · 대국 화면 피하기 · 상점 잠긴 칸 막대엔 사기 단추 없음")
    func viewWiring() throws {
        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        #expect(root.contains(".sheet(item: cakeGiftSheet) { item in") && root.contains("MeCakeGiftSheetView(store: model.me, item: item)"),
                "축하 시트가 item 을 안 넘긴다 — 내려가는 동안 판이 빈다")
        #expect(root.contains("!model.games.isAnyMatchScreenVisible"), "시트 바인딩이 대국 화면을 안 피한다")
        #expect(root.contains(".onChange(of: model.games.isAnyMatchScreenVisible)") && root.contains("model.me.presentCakeGiftIfDue()"))
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCakeGiftViews.swift")
        #expect(sheet.contains("if let live = store.cakeGiftSheet, live.id == item.id { return live }") && sheet.contains("return item"))
        #expect(!sheet.contains("if let sheet = store.cakeGiftSheet {"), "본문이 다시 스토어 값으로만 그린다(닫히는 순간 빈 판)")
        #expect(sheet.contains(".disabled(sheet.phase == .claiming)"), "받는 중에 머리 [X] 가 켜져 있다")
        #expect(sheet.contains(".interactiveDismissDisabled(sheet.phase == .claiming)"))
        #expect(sheet.contains("isBusy: store.cakeGiftReopening"), "[고르기]가 묻는 동안 돌지 않는다")
        let shop = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCharacterViews.swift")
        #expect(shop.contains("let giftHint = selection == nil ? store.shopGiftHintID : nil"))
        #expect(shop.components(separatedBy: "if giftHint == nil { buyButton(selection: selection) }").count - 1 == 2,
                "잠긴 칸 막대의 두 모양(가로 · 세로) 모두 사기 단추를 거둬야 한다")
        #expect(shop.contains("store.shopSelection == id || store.shopGiftHintID == id"))
    }
}
