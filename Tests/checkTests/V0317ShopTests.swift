import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

/// 상점(루비) 화면의 계약.
///
/// **서버가 아직 프로덕션에 없다** — 그래서 여기서 물을 수 있는 것은 (가) 응답 디코딩 (나) 순수 문구
/// (다) 렌더(잘림·노란 상자·창 높이) 셋뿐이고, 그 셋을 전부 판다. 실호출 검증은 서버가 올라간 뒤다.
@Suite("v0.3.17 상점")
struct V0317ShopTests {

    // MARK: - ① 응답 디코딩 (구버전 서버가 키를 빼도 죽지 않아야 한다)

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    /// ★ 이 저장소가 실제로 겪은 사고: 비옵셔널 필드 하나가 **구버전 서버 응답에서 디코드를 통째로
    ///   throw** 시켜 기능이 죽었다(`PokeSendResponse.ultraBalance` 주석). 상점 응답은 키가 앞으로도
    ///   늘어날 자리라 그 사고가 가장 잘 재발한다.
    @Test("상점 상태 — 키가 하나도 없어도 디코드된다")
    func shopStateSurvivesMissingKeys() throws {
        let empty = try Self.decoder().decode(ShopStateResponse.self, from: Data("{}".utf8))
        #expect(empty.rubyBalance == nil)
        #expect(empty.ultraPrice == nil)
        #expect(empty.characters == nil)

        let full = try Self.decoder().decode(ShopStateResponse.self, from: Data(#"""
        {"ruby_balance":42,"ultra_balance":7,"ultra_price":3,
         "characters":[{"id":"fox","price":30,"owned":false},
                       {"id":"ghost","price":50,"owned":true}]}
        """#.utf8))
        #expect(full.rubyBalance == 42)
        #expect(full.ultraBalance == 7)
        #expect(full.ultraPrice == 3)
        #expect(full.characters?.count == 2)
        #expect(full.characters?.first?.price == 30)
        #expect(full.characters?.last?.owned == true)

        // 목록 행에서 price/owned 가 빠져도 죽지 않는다(가격 미정 캐릭터를 서버가 실어 보낼 수 있다).
        let sparse = try Self.decoder().decode(ShopStateResponse.self,
                                               from: Data(#"{"characters":[{"id":"fox"}]}"#.utf8))
        #expect(sparse.characters?.first?.id == "fox")
        #expect(sparse.characters?.first?.price == nil)
        #expect(sparse.characters?.first?.owned == nil)
    }

    @Test("캐릭터 구매 — 어휘 여섯 가지가 전부 디코드된다")
    func buyCharacterDecodesEveryStatus() throws {
        let cases: [(String, String)] = [
            (#"{"status":"ok","character":"fox","price":30,"ruby_balance":12}"#, "ok"),
            (#"{"status":"already_owned","character":"fox"}"#, "already_owned"),
            (#"{"status":"unknown_character"}"#, "unknown_character"),
            (#"{"status":"insufficient","need":30,"have":12}"#, "insufficient"),
            (#"{"status":"unauthorized"}"#, "unauthorized"),
            (#"{"status":"no_profile"}"#, "no_profile"),
        ]
        for (json, status) in cases {
            let decoded = try Self.decoder().decode(BuyCharacterResponse.self, from: Data(json.utf8))
            #expect(decoded.status == status, Comment(rawValue: json))
        }
        let short = try Self.decoder().decode(BuyCharacterResponse.self,
                                              from: Data(#"{"status":"insufficient","need":30,"have":12}"#.utf8))
        #expect(short.need == 30 && short.have == 12)
    }

    @Test("울트라 구매 — 어휘 다섯 가지가 전부 디코드된다")
    func buyUltraDecodesEveryStatus() throws {
        for json in [#"{"status":"ok","ultra_balance":8,"ruby_balance":9}"#,
                     #"{"status":"insufficient"}"#,
                     #"{"status":"invalid"}"#,
                     #"{"status":"unauthorized"}"#,
                     #"{"status":"no_profile"}"#] {
            _ = try Self.decoder().decode(BuyUltraResponse.self, from: Data(json.utf8))
        }
        let ok = try Self.decoder().decode(BuyUltraResponse.self,
                                           from: Data(#"{"status":"ok","ultra_balance":8,"ruby_balance":9}"#.utf8))
        #expect(ok.ultraBalance == 8 && ok.rubyBalance == 9)
    }

    @Test("set_character 의 새 어휘 not_owned 가 디코드된다")
    func setCharacterDecodesNotOwned() throws {
        let decoded = try Self.decoder().decode(SetCharacterResponse.self,
                                                from: Data(#"{"status":"not_owned","id":"ghost"}"#.utf8))
        #expect(decoded.status == "not_owned")
        #expect(decoded.id == "ghost")
    }

    @Test("p_id · p_count 본문이 스네이크로 실린다")
    func requestBodiesUseSnakeCase() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let character = try #require(String(data: try encoder.encode(BuyCharacterRequest(pId: "fox")), encoding: .utf8))
        #expect(character.contains("\"p_id\"") && character.contains("fox"), Comment(rawValue: character))
        let ultra = try #require(String(data: try encoder.encode(BuyUltraRequest(pCount: 2)), encoding: .utf8))
        #expect(ultra.contains("\"p_count\"") && ultra.contains("2"), Comment(rawValue: ultra))
    }

    // MARK: - ② 순수 문구 (숫자를 지어내지 않는다)

    @Test("모자란 양은 서버가 준 숫자로만 말한다")
    func shortfallOnlySpeaksServerNumbers() {
        #expect(WorkTimerStore.shortfallNotice(need: 30, have: 12) == "루비 18개 더 필요해요")
        // 서버가 숫자를 안 줬으면 **수를 지어내지 않는다**.
        #expect(WorkTimerStore.shortfallNotice(need: nil, have: 12) == "루비가 모자라요")
        #expect(WorkTimerStore.shortfallNotice(need: 30, have: nil) == "루비가 모자라요")
        // need <= have 는 서버와 화면이 갈린 상태다. 음수("-3개 더")를 그리지 않는다.
        #expect(WorkTimerStore.shortfallNotice(need: 10, have: 30) == "루비가 모자라요")
    }

    @Test("카드 아래 줄 — 보유는 가격 대신 사실을 말한다")
    func cardPriceText() {
        #expect(ShopText.cardPrice(owned: true, price: 30) == "보유")
        #expect(ShopText.cardPrice(owned: false, price: 30) == "30")
        #expect(ShopText.cardPrice(owned: false, price: nil) == "—")
    }

    @Test("울트라 줄은 가격을 모르면 수량을 단정하지 않는다")
    func ultraRowTitleStaysHonest() {
        #expect(ShopText.ultraRowTitle(price: nil) == "울트라 찌르기")
        #expect(ShopText.ultraRowTitle(price: 3) == "울트라 찌르기 1개")
        #expect(ShopText.ultraHeld(nil) == "보유 —")
        #expect(ShopText.ultraHeld(7) == "보유 7개")
    }

    // MARK: - ③ 울트라 잔량 자릿수 (보유 상한 폐지, 2026-09-13)

    /// 예전에는 매일 자정에 잔량이 3 으로 깎여 배지가 **한 자리**였고 제목 행 폭 예산이 그 전제였다.
    /// 이제 루비로 얼마든지 살 수 있다. 계산상 천장이 두 자리라(3자리 힌트 66pt < 가장 긴 힌트 71pt)
    /// 99 를 넘으면 접고, 그 조합에서는 힌트가 짧은 문구로 양보한다.
    @Test("잔량이 두 자리를 넘으면 배지가 접히고 힌트가 양보한다")
    func badgeFoldsAboveTwoDigits() {
        #expect(UltraBalanceText.badge(balance: 7) == "7")
        #expect(UltraBalanceText.badge(balance: 42) == "42")
        #expect(UltraBalanceText.badge(balance: 99) == "99")
        #expect(UltraBalanceText.badge(balance: 100) == "99+")
        #expect(UltraBalanceText.badge(balance: 1234) == "99+")
        // 무제한(관리자)은 숫자 자리를 기호로 바꾼다 — 접힘 규칙과 무관하다.
        #expect(UltraBalanceText.badge(balance: 1234, unlimited: true) == UltraBalanceText.unlimitedBadge)

        #expect(UltraBalanceText.badgeOverflows(balance: 99) == false)
        #expect(UltraBalanceText.badgeOverflows(balance: 100))
        #expect(UltraBalanceText.badgeOverflows(balance: nil) == false)

        // 힌트: 접히는 조합에서만 짧은 문구.
        #expect(UltraBalanceText.hint(balance: 42) == UltraBalanceText.discover)
        #expect(UltraBalanceText.hint(balance: 100) == UltraBalanceText.discoverShort)
        // 0 은 충전 안내가 먼저다(접힘 규칙보다 앞선다).
        #expect(UltraBalanceText.hint(balance: 0) == UltraBalanceText.empty)
        // 정확한 수는 툴팁이 그대로 말한다 — 접는 것은 그림뿐이다.
        #expect(UltraBalanceText.badgeHelp(balance: 1234).contains("1234"))
    }

    /// 폭 예산이 실제로 두 자리까지만 성립한다는 사실을 **숫자로** 못 박는다.
    /// 이 단언이 빨개지면 배지를 더 넓히기 전에 제목 행에서 무엇을 줄일지부터 정해야 한다.
    @Test("제목 행 폭 예산 — 두 자리는 되고 세 자리는 안 된다")
    func titleRowBudgetCeilingIsTwoDigits() {
        #expect(PokeTitleRowWidthBudget.maxBadgeDigits == 2)
        #expect(PokeTitleRowWidthBudget.hintWidth(digits: 2) >= PokeTitleRowWidthBudget.longestHintWidth)
        // ★ 기준선이 실제로 다르다: 세 자리는 **못 들어간다**(그래서 99+ 로 접는다).
        #expect(PokeTitleRowWidthBudget.hintWidth(digits: 3) < PokeTitleRowWidthBudget.longestHintWidth)
        // 접힘 배지가 섰을 때 남는 폭에 **짧은 힌트**는 들어간다.
        let shortHintWidth = CGFloat(UltraBalanceText.discoverShort.count)
            * PokeTitleRowWidthBudget.koreanCaptionGlyphWidth
        #expect(PokeTitleRowWidthBudget.hintWidthWhenOverflowing >= shortHintWidth,
                Comment(rawValue: "접힘 조합 힌트 폭 \(PokeTitleRowWidthBudget.hintWidthWhenOverflowing)pt "
                        + "< 짧은 힌트 \(shortHintWidth)pt"))
    }

    // MARK: - ④ 소유 게이트 — 치료 쪽(서버 not_owned → 로컬 되돌리기)

    /// ⚠️ **클라 게이트는 짝으로 있다.** 예방(선택 패널에서 못 고르게)만 있으면 다른 경로로 들어온
    /// 상태가 남는다 — 상점 이전 빌드에서 골라 둔 로컬 값, 기기 두 대 중 한쪽에서만 산 경우.
    /// 그때 서버는 `not_owned` 로 거절하는데, 클라가 그 어휘를 모르면 **내 화면엔 유령, 남에겐 아잉**이 된다.
    @MainActor
    @Test("not_owned 를 받으면 로컬 선택이 아잉으로 돌아가고 그 사실을 말한다")
    func notOwnedRevertsLocalSelection() async throws {
        let host = "v0317-not-owned-\(UUID().uuidString.lowercased())"
        TokenBoardURLProtocol.setResponse(#"{"status":"not_owned","id":"ghost"}"#, forHost: host)

        // ★ **전역 UserDefaults 를 빌리지 않는다.** 착용 캐릭터는 오버레이 격발 테스트도 읽으므로,
        //   전역을 갈아 끼우면 병렬 스위트가 간헐적으로 빨개진다(실제로 그렇게 만들었다가 잡았다).
        //   그래서 스토어에 `characterDefaults` 주입 지점을 두고 여기서는 격리 suite 만 쓴다.
        let target = try #require(
            CheckCharacter3DScene.catalog.allIDs.first { $0 != CharacterCatalog.builtInAingID },
            "번들에 아잉 말고 캐릭터가 없다")
        let store = Self.stubStore(host: host)
        let defaults = store.characterDefaults
        defaults.set(target, forKey: CharacterSelection.defaultsKey)
        let selection = CharacterSelection(defaults: defaults, catalog: CheckCharacter3DScene.catalog)
        #expect(selection.selectedID == target, "준비 실패 — 기준선이 아잉이면 이 테스트는 공허하다")

        store.syncMessage = "시작값"
        // ★ announcesFailure: false — 로그인 경로다. 되돌리기는 이 깃발과 **무관하게** 일어나야 한다.
        await store.pushCharacter(target, announcesFailure: false)

        #expect(selection.selectedID == CharacterCatalog.builtInAingID,
                "not_owned 인데 로컬이 그대로다 — 내 화면엔 그 캐릭터, 남에게는 아잉이 된다")
        #expect(store.syncMessage == WorkTimerStore.notOwnedRevertNotice,
                "되돌린 사실을 안 말했다 — 아무 말 없이 캐릭터가 바뀌면 버그로 보인다")
    }

    @MainActor
    @Test("ok 응답은 로컬을 건드리지 않는다 — 기준선이 실제로 다르다")
    func okKeepsLocalSelection() async throws {
        let host = "v0317-ok-\(UUID().uuidString.lowercased())"
        TokenBoardURLProtocol.setResponse(#"{"status":"ok","character":"ghost"}"#, forHost: host)
        let target = try #require(CheckCharacter3DScene.catalog.allIDs.first { $0 != CharacterCatalog.builtInAingID })
        let store = Self.stubStore(host: host)
        store.characterDefaults.set(target, forKey: CharacterSelection.defaultsKey)
        let selection = CharacterSelection(defaults: store.characterDefaults,
                                           catalog: CheckCharacter3DScene.catalog)
        await store.pushCharacter(target, announcesFailure: false)
        #expect(selection.selectedID == target,
                "성공 응답인데 되돌렸다 — 되돌리기 조건이 너무 넓다")
    }

    // MARK: - ⑤ 소유 게이트 — 예방 쪽(로드 전에는 아무것도 안 잠근다)

    @MainActor
    @Test("서버가 말해 주기 전에는 아무것도 잠기지 않는다")
    func nothingLocksBeforeTheServerSpeaks() {
        let store = Self.plainStore()
        // shopLoaded == false: 이 집합이 비어 있다고 해서 "안 샀다"로 읽으면 **이미 산 캐릭터까지**
        // 잠긴 채로 첫 화면이 그려진다.
        #expect(store.shopLoaded == false)
        #expect(store.isCharacterUnlocked("ghost"))
        #expect(store.isCharacterUnlocked(CharacterCatalog.builtInAingID))

        store.applyShopState(ShopStateResponse(
            rubyBalance: 42, ultraBalance: 7, ultraPrice: 3,
            characters: [ShopCharacterRow(id: "fox", price: 30, owned: true),
                         ShopCharacterRow(id: "ghost", price: 50, owned: false)]))
        store.shopLoaded = true
        #expect(store.rubyBalance == 42)
        #expect(store.ultraPrice == 3)
        #expect(store.isCharacterUnlocked("fox"))
        #expect(store.isCharacterUnlocked("ghost") == false, "안 산 캐릭터가 안 잠겼다")
        // 아잉은 무료라 서버 목록에 없어도 언제나 열려 있다.
        #expect(store.isCharacterUnlocked(CharacterCatalog.builtInAingID))
        #expect(store.shopPrice(of: "ghost") == 50)
    }

    @MainActor
    @Test("nil 필드는 기존 값을 덮지 않는다 — '모른다'를 0 으로 적지 않는다")
    func nilFieldsDoNotClobber() {
        let store = Self.plainStore()
        store.rubyBalance = 42
        store.ultraPrice = 3
        store.applyShopState(ShopStateResponse(rubyBalance: nil, ultraBalance: nil,
                                               ultraPrice: nil, characters: nil))
        #expect(store.rubyBalance == 42, "모른다는 응답이 잔량을 0 으로 지웠다")
        #expect(store.ultraPrice == 3)
    }

    // MARK: - ⑤-b 2단 구매 (이번 변경의 핵심 — 회귀하면 사용자가 또 실수로 산다)

    /// ★ **카드를 누르는 것만으로는 절대 사지 않는다.** 사용자 신고 2026-09-14: "누르면 바로
    ///   구입되는데 이건 실수로 구매하는걸 방지하지 못해" — 실제로 실수로 전부 사 버렸다.
    @MainActor
    @Test("카드를 눌러도 구매가 시작되지 않는다 — 고르기일 뿐이다")
    func tappingACardNeverBuys() {
        let store = Self.shopStore(ruby: 1_000)
        store.selectShopItem(.character("ghost"))
        #expect(store.shopSelection == .character("ghost"), "고르지도 않았다")
        #expect(store.purchasingID == nil, "카드를 눌렀는데 구매가 시작됐다 — 실수 구매가 그대로 재발한다")

        // 울트라도 **같은 경로**다(상품마다 구매 방법이 다르면 그게 곧 실수의 자리다).
        store.selectShopItem(.ultra)
        #expect(store.shopSelection == .ultra)
        #expect(store.purchasingID == nil, "울트라를 눌렀는데 구매가 시작됐다")

        // 같은 것을 다시 누르면 선택이 풀린다(되돌리는 길).
        store.selectShopItem(.ultra)
        #expect(store.shopSelection == nil)
    }

    /// 구매로 가는 문이 **하단 버튼 하나뿐**인지 소스로 못 박는다. 행동 테스트만으로는
    /// "다른 뷰에서 buyCharacter 를 직접 부르는" 조합을 못 잡는다.
    @Test("구매 호출은 confirmShopPurchase 하나에서만 나간다")
    func onlyTheConfirmButtonBuys() throws {
        let panel = Self.stripped(try Self.source("CheckShopPanel.swift"))
        #expect(panel.contains("store.confirmShopPurchase()"), "하단 구매 버튼이 없다")
        #expect(!panel.contains("store.buyCharacter("),
                "패널이 buyCharacter 를 직접 부른다 — 2단 구매가 우회된다")
        #expect(!panel.contains("store.buyUltra("),
                "패널이 buyUltra 를 직접 부른다 — 2단 구매가 우회된다")
        let auth = Self.stripped(try Self.source("WorkTimerStoreAuth.swift"))
        // 스토어 안에서도 buyCharacter/buyUltra 를 부르는 곳은 confirmShopPurchase 뿐이어야 한다.
        #expect(auth.contains("case .character(let id): buyCharacter(id)")
                && auth.contains("case .ultra: buyUltra(count: 1)"),
                "confirmShopPurchase 가 실제 구매로 안 이어진다")
    }

    @MainActor
    @Test("잔량이 모자라면 구매하기가 비활성이고 얼마가 모자란지 말한다")
    func shortfallDisablesTheConfirmButton() {
        let store = Self.shopStore(ruby: 12)
        store.selectShopItem(.character("ghost"))   // 50루비
        #expect(store.shopSelectionPrice == 50)
        #expect(store.canConfirmShopPurchase == false, "못 사는데 구매하기가 켜져 있다")
        #expect(ShopText.barDetail(notice: nil, selection: store.shopSelection,
                                   price: store.shopSelectionPrice,
                                   balance: store.rubyBalance) == "루비 38개 더 필요해요")
        // 눌러도 서버로 안 나간다.
        store.confirmShopPurchase()
        #expect(store.purchasingID == nil, "못 사는데 서버 왕복이 생겼다")

        // ★ 기준선이 실제로 다르다: 살 수 있으면 켜진다.
        store.rubyBalance = 100
        #expect(store.canConfirmShopPurchase, "살 수 있는데 구매하기가 꺼져 있다")
    }

    @MainActor
    @Test("이미 가진 캐릭터는 골라지지 않고 그 사실을 말한다")
    func ownedCharactersCannotBeSelected() {
        let store = Self.shopStore(ruby: 1_000, ownedIDs: ["ghost"])
        store.selectShopItem(.character("ghost"))
        #expect(store.shopSelection == nil, "이미 가진 것이 골라졌다")
        #expect(store.shopNotice == WorkTimerStore.alreadyOwnedNotice)
        #expect(store.canConfirmShopPurchase == false)
    }

    @MainActor
    @Test("잔량이나 값을 모르면 구매하기가 안 켜진다")
    func unknownValuesNeverEnableTheButton() {
        let unknownBalance = Self.shopStore(ruby: nil)
        unknownBalance.selectShopItem(.character("ghost"))
        #expect(unknownBalance.canConfirmShopPurchase == false, "잔량을 모르는데 살 수 있다고 한다")

        let unknownPrice = Self.shopStore(ruby: 1_000)
        unknownPrice.ultraPrice = nil
        unknownPrice.selectShopItem(.ultra)
        #expect(unknownPrice.canConfirmShopPurchase == false, "값을 모르는데 살 수 있다고 한다")
        unknownPrice.confirmShopPurchase()
        #expect(unknownPrice.purchasingID == nil, "값을 모르는데 샀다")
    }

    @Test("하단 바는 어떤 상태에서도 문구를 돌려준다 — 높이를 상태에 안 맡긴다")
    func theBarAlwaysHasText() {
        // 둘째 줄은 빈 문자열이라도 **반드시** 있어야 한다(없으면 그 줄이 사라져 바 높이가 흔들린다).
        #expect(ShopText.barDetail(notice: nil, selection: nil, price: nil, balance: nil) == " ")
        #expect(ShopText.barDetail(notice: "샀어요!", selection: nil, price: nil, balance: nil) == "샀어요!")
        // 안내가 모자람보다 앞선다 — "샀어요!" 직후 잔량이 모자라도 방금 산 것이 실패로 읽히면 안 된다.
        #expect(ShopText.barDetail(notice: "샀어요!", selection: .ultra, price: 3, balance: 0) == "샀어요!")
    }

    @MainActor
    @Test("잔량을 모를 때 0 이라고 말하지 않는다")
    func unknownBalanceIsNotZero() {
        let store = Self.plainStore()
        #expect(store.rubyBalance == nil, "초기값이 0 이면 실제로 3 을 가진 사람에게 '0' 이라고 말한다")
        #expect(ShopText.balance(nil) == "—")
        #expect(ShopText.balance(0) == "0")
        #expect(ShopText.balance(42) == "42")
        // 모르면 **사지 않는다**(0 으로 단정하지도, 있다고 가정하지도 않는다).
        store.applyShopState(ShopStateResponse(rubyBalance: nil, ultraBalance: nil, ultraPrice: 3,
                                               ultraBuyMax: 20, characters: nil))
        store.selectShopItem(.ultra)
        store.confirmShopPurchase()
        #expect(store.purchasingID == nil, "잔량을 모르는데 샀다")
        #expect(store.ultraBuyMax == 20, "ultra_buy_max 를 안 읽었다 — 수량 선택을 붙이는 날 상한을 모른다")
    }

    @Test("울트라 부족 응답의 need·have 를 읽는다 — 캐릭터와 같은 문법")
    func buyUltraReadsNeedAndHave() throws {
        let decoded = try Self.decoder().decode(BuyUltraResponse.self, from: Data(#"""
        {"status":"insufficient","need":6,"have":1,"ruby_balance":1,"unit":3,"count":2}
        """#.utf8))
        #expect(decoded.need == 6 && decoded.have == 1)
        #expect(decoded.unit == 3 && decoded.count == 2)
        #expect(WorkTimerStore.shortfallNotice(need: decoded.need, have: decoded.have) == "루비 5개 더 필요해요")
        let invalid = try Self.decoder().decode(BuyUltraResponse.self,
                                                from: Data(#"{"status":"invalid","count":99,"max":20}"#.utf8))
        #expect(invalid.max == 20)
    }

    // MARK: - ⑥ 렌더 — 노란 상자 없음 · 세 상태 · 창 높이 계약

    @MainActor
    @Test("상점 패널이 실제로 그려진다 — 노란 상자 0, 세 상태")
    func shopPanelRendersInThreeStates() throws {
        // 2단 구매의 다섯 상태 + 보유.
        let states: [(String, Int, Set<String>, ShopSelection?)] = [
            ("idle", 100, [], nil),                                   // ① 아무것도 안 고름
            ("picked", 100, [], .character("ghost")),                 // ② 캐릭터를 고름(가격 + 구매하기)
            ("poor", 5, [], .character("jellyfish")),                 // ③ 잔량 부족
            ("owned", 100, Set(Self.sprites), .character("ghost")),   // ④ 이미 보유한 것을 누름
            ("ultra", 100, [], .ultra),                               // ⑤ 울트라를 고름
        ]
        for (name, ruby, ownedIDs, selection) in states {
            let store = Self.plainStore()
            let rows = Self.rows(ownedIDs: ownedIDs)
            store.applyShopState(ShopStateResponse(rubyBalance: ruby, ultraBalance: 7,
                                                   ultraPrice: 3, ultraBuyMax: 20, characters: rows))
            store.shopLoaded = true
            if let selection { store.selectShopItem(selection) }
            let panel = CheckShopPanel(store: store, onBack: {})
            let bitmap = try #require(Self.bitmap(panel, width: CheckMenuView.contentColumnWidth),
                                      "렌더 실패")
            // ImageRenderer 는 Menu·Picker·TextField 자리에 (255,204,0) 상자를 박는다. 하나라도 있으면
            // 이 패널은 스냅샷에서 **보이지 않는 것과 같다**.
            #expect(Self.yellowPixels(bitmap) == 0,
                    Comment(rawValue: "\(name): '못 그림' 노란 상자가 있다 — Menu/TextField 를 썼다"))
            // 캐릭터 그림이 실제로 칠해졌는가(이 화면의 회색 팔레트에 없는 유채색 덩어리).
            // ★ 임계가 캐릭터 패널(2,000)보다 낮은 이유: 상점 카드의 그림은 80×56 으로 저쪽(80×72)보다
            //   작고, **살 수 없는 카드는 opacity 0.5** 라 어두운 바탕과 섞여 채도가 절반으로 떨어진다.
            //   실측 최소가 1,915(잔량 부족 상태)라 1,200 을 쓴다 — 빈 상자(0에 가까움)와는 여전히 멀다.
            #expect(Self.colorfulPixels(bitmap) > 1_200,
                    Comment(rawValue: "\(name): 카드가 빈 상자다(유채색 \(Self.colorfulPixels(bitmap))개)"))
            Self.save(bitmap, name: "v0317-shop-\(name).png")
        }
    }

    /// `ShopPanelGridBudget.chromeOutsideGrid` 는 **추정이 아니라 실측**이어야 한다.
    /// 틀리면 창이 700pt 상한을 넘어 푸터(로그아웃/앱 종료)가 잘린다.
    @MainActor
    @Test("상점 패널 크롬 높이가 실측과 맞다")
    func shopChromeHeightMatchesMeasurement() throws {
        // 행 수를 바꿔 두 번 재면 **크롬 = 패널 높이 − 격자 자연 높이** 가 행 수와 무관하게 같아야 한다.
        var measured: [CGFloat] = []
        for count in [3, 6] {
            let store = Self.plainStore()
            store.applyShopState(ShopStateResponse(rubyBalance: 10, ultraBalance: 1, ultraPrice: 3,
                                                   characters: Self.rows(ownedIDs: [], limit: count)))
            store.shopLoaded = true
            let panel = CheckShopPanel(store: store, onBack: {})
            let height = try #require(Self.height(panel, width: CheckMenuView.contentColumnWidth))
            let rows = ShopPanelGridBudget.rowCount(cardCount: count)
            measured.append(height - ShopPanelGridBudget.naturalHeight(rowCount: rows))
        }
        #expect(abs(measured[0] - measured[1]) < 1.0,
                Comment(rawValue: "크롬이 행 수에 따라 달라진다: \(measured) — 예산 계산이 거짓이 된다"))
        print("[v0317] 상점 크롬 실측 = \(measured) pt")
        #expect(abs(measured[0] - ShopPanelGridBudget.chromeOutsideGrid) < 1.0,
                Comment(rawValue: "실측 크롬 \(measured[0])pt 인데 상수는 "
                        + "\(ShopPanelGridBudget.chromeOutsideGrid)pt 다 — 상수를 실측값으로 고쳐라"))
    }

    /// 최악 조합(배너 + 목표 편집 행 + 상점)에서도 팝오버가 700pt 상한 안이어야 한다.
    @MainActor
    @Test("최악 조합에서도 창이 700pt 상한 안이다")
    func popoverStaysUnderTheCapInTheWorstCase() throws {
        let store = Self.teamStore(members: 8)
        store.toggleShopPanel()
        store.applyShopState(ShopStateResponse(rubyBalance: 42, ultraBalance: 7, ultraPrice: 3,
                                               characters: Self.rows(ownedIDs: [])))
        store.shopLoaded = true
        store.isEditingWeeklyGoal = true
        let view = CheckMenuView(store: store,
                                 previewClipsOverflowList: true,
                                 previewGoalEditing: true,
                                 characterDefaults: Self.isolatedDefaults())
        let height = try #require(Self.popoverHeight(view))
        let rows = ShopPanelGridBudget.rowCount(cardCount: Self.sprites.count)
        let natural = ShopPanelGridBudget.naturalHeight(rowCount: rows)
        let cap = ShopPanelGridBudget.capHeight(extraChromeHeight: 92)   // 목표 편집 행
        print("[v0317] 최악 조합 팝오버 \(height)pt · 격자 자연 \(natural)pt vs 캡 \(cap)pt "
              + "→ 스크롤로 밀리는 양 \(Swift.max(0, natural - cap))pt")
        #expect(height <= 700,
                Comment(rawValue: "팝오버가 \(height)pt — 700pt 상한을 넘어 푸터가 잘린다"))
        if let bitmap = Self.bitmap(view, width: CheckMenuView.mainWindowWidth) {
            Self.save(bitmap, name: "v0317-shop-popover-worst.png")
        }
    }

    /// 레일이 창 높이를 결정하지 않는지 **픽셀로** 잰다(계약 테스트의 초록만으로는 여유가 몇 pt 인지 모른다).
    @MainActor
    @Test("레일 여유를 픽셀로 잰다")
    func railSlackMeasuredInPixels() throws {
        let railOnly = CheckMenuSideRail.contentHeight + 12 * 2
        let shortest = try #require(Self.popoverHeight(
            CheckMenuView(store: Self.teamStore(members: 0))))
        print("[v0317] 레일 \(CheckMenuSideRail.itemCount)칸 × \(CheckMenuSideRail.buttonHeight)pt "
              + "→ 레일만 \(railOnly)pt · 최단 메인 화면 \(shortest)pt · 여유 \(shortest - railOnly)pt")
        #expect(shortest > railOnly,
                Comment(rawValue: "최단 화면 \(shortest)pt 가 레일 \(railOnly)pt 보다 낮다 — 레일이 창 높이를 결정한다"))
        // 눈으로도 확인할 수 있게 굽는다(1인팀 = 레일이 제일 이기기 쉬운 화면).
        if let bitmap = Self.bitmap(CheckMenuView(store: Self.teamStore(members: 1)),
                                    width: CheckMenuView.mainWindowWidth) {
            Self.save(bitmap, name: "v0317-rail-7items-1member.png")
        }
    }

    // MARK: - ⑦ 배선 계약 (여기가 끊기면 화면은 멀쩡한데 문이 없다)

    @Test("헤더 루비 칩이 상점을 열고, 레일 칸 수는 그대로다")
    func headerChipOpensTheShopAndTheRailIsUntouched() throws {
        let menu = Self.stripped(try Self.source("CheckMenuView.swift"))
        #expect(menu.contains("store.toggleShopPanel()"),
                "레일에 상점 칸이 없다 — 상점으로 가는 문이 하나도 없다")
        #expect(menu.contains("icon: \"bag.fill\""), "상점 칸 아이콘이 없다")
        // ★ 헤더에는 **없어야** 한다(사용자가 뒤집었다 — 루비 칩은 진입점이 아니다).
        #expect(!menu.contains("RubyEntryButton"), "헤더 루비 칩이 아직 남아 있다")
        #expect(menu.contains("store.isShopPanelVisible"), "상점 깃발이 isSubPanelOpen 에 없다")
        #expect(menu.contains("CheckShopPanel("), "상점 패널이 라우팅에 없다")
        // ★ 레일은 **1pt 도 건드리지 않는다**(378pt vs 최단 화면 381pt — 한 칸이면 레일이 창 높이를 결정한다).
        // 칸은 일곱이 됐고, 그 대신 칸 높이를 54 → 45pt 로 내려 레일 총 높이는 **줄었다**.
        #expect(CheckMenuSideRail.itemCount == 7)
        #expect(CheckMenuSideRail.buttonHeight == 45)
        #expect(CheckMenuSideRail.contentHeight + 24 < 378,
                Comment(rawValue: "레일이 \(CheckMenuSideRail.contentHeight + 24)pt — 예전 378pt 보다 크면 "
                        + "1인팀 창이 자란다"))
    }

    @Test("소유 게이트가 예방·치료 양쪽에 다 있다")
    func ownershipGateExistsOnBothSides() throws {
        let menu = Self.stripped(try Self.source("CheckMenuView.swift"))
        #expect(menu.contains("isUnlocked:") && menu.contains("onLocked:"),
                "선택 패널에 소유 게이트(예방)가 안 배선됐다")
        let auth = Self.stripped(try Self.source("WorkTimerStoreAuth.swift"))
        #expect(auth.contains("case \"not_owned\":") && auth.contains("revertCharacterToDefault()"),
                "서버 거절을 받아 되돌리는 치료 쪽이 없다 — 로컬과 서버가 갈린 채로 남는다")
    }

    // MARK: - 헬퍼

    @MainActor
    static var sprites: [String] {
        CheckCharacter3DScene.catalog.allIDs.filter { $0 != CharacterCatalog.builtInAingID }
    }

    /// **실제 서버 가격**(2026-09-13 프로덕션). 그림이 거짓말하지 않게 픽스처도 같은 값을 쓴다.
    static let realPrices: [String: Int] = ["fox": 30, "squirrel": 30, "shiba": 50,
                                            "ghost": 50, "jellyfish": 70]

    @MainActor
    static func rows(ownedIDs: Set<String>, limit: Int? = nil) -> [ShopCharacterRow] {
        let ids = limit.map { Array(sprites.prefix($0)) } ?? sprites
        return ids.map { id in
            ShopCharacterRow(id: id, price: realPrices[id] ?? 30, owned: ownedIDs.contains(id))
        }
    }

    static func isolatedDefaults() -> UserDefaults {
        let name = "v0317-shop-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 상점 상태가 채워진 스토어(실제 서버 가격).
    @MainActor
    static func shopStore(ruby: Int?, ownedIDs: Set<String> = []) -> WorkTimerStore {
        let store = plainStore()
        store.applyShopState(ShopStateResponse(rubyBalance: ruby, ultraBalance: 7, ultraPrice: 3,
                                               ultraBuyMax: 20, characters: rows(ownedIDs: ownedIDs)))
        store.rubyBalance = ruby
        store.shopLoaded = true
        return store
    }

    @MainActor
    static func plainStore() -> WorkTimerStore {
        WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
                       defaults: isolatedDefaults())
    }

    @MainActor
    static func stubStore(host: String) -> WorkTimerStore {
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!,
                                          anonKey: "anon-test-key",
                                          session: TokenBoardURLProtocol.session())
        let store = WorkTimerStore(service: service,
                                   environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: isolatedDefaults())
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
        store.membershipConfirmed = true
        // 착용 캐릭터도 격리한다 — 전역을 건드리면 병렬 스위트가 빨개진다(위 주석).
        store.characterDefaults = isolatedDefaults()
        return store
    }

    @MainActor
    static func teamStore(members: Int) -> WorkTimerStore {
        let store = plainStore()
        store.isMenuPresented = true
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil,
                                        userID: "00000000-0000-0000-0000-000000000002")
        store.displayNow = Date()
        store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
        store.teamName = "아잉팀"
        store.myCenterLoaded = true
        store.myCenter = CenterLabel.seoul
        let names = ["영식", "민수", "지현", "서준", "하윤", "도현", "예린", "yesung"]
        store.teamMembers = Array(names.prefix(members)).enumerated().map { index, name in
            TeamMemberStatus(id: "00000000-0000-0000-0000-00000000000\(index)", name: name,
                             status: index % 3 == 2 ? .offWork : .working, updatedAt: nil,
                             currentSessionStartedAt: nil,
                             weeklyDurationSeconds: 3_600 * index * 5,
                             todayDurationSeconds: 3_600 * index)
        }
        return store
    }

    @MainActor
    static func bitmap(_ view: some View, width: CGFloat) -> NSBitmapImageRep? {
        // 배율은 **언제나 명시한다** — 기본값은 주 디스플레이 backingScaleFactor 라 기계마다 갈린다.
        let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap
    }

    @MainActor
    static func height(_ view: some View, width: CGFloat) -> CGFloat? {
        bitmap(view, width: width).map { CGFloat($0.pixelsHigh) / 2 }
    }

    /// 팝오버는 **자연 폭**으로 그린다(레일이 붙으면 창이 넓어진다 — 폭을 고정하면 그 사실이 지워진다).
    @MainActor
    static func popoverHeight(_ view: CheckMenuView) -> CGFloat? {
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return CGFloat(bitmap.pixelsHigh) / 2
    }

    static func count(_ bitmap: NSBitmapImageRep, _ test: (Int, Int, Int) -> Bool) -> Int {
        var hits = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let r = Int(color.redComponent * 255), g = Int(color.greenComponent * 255)
                let b = Int(color.blueComponent * 255)
                if test(r, g, b) { hits += 1 }
            }
        }
        return hits
    }

    static func yellowPixels(_ bitmap: NSBitmapImageRep) -> Int {
        count(bitmap) { r, g, b in r >= 240 && g >= 195 && b <= 40 }
    }

    /// 회색 팔레트에 없는 **유채색** 픽셀(캐릭터 그림·루비).
    static func colorfulPixels(_ bitmap: NSBitmapImageRep) -> Int {
        count(bitmap) { r, g, b in max(r, max(g, b)) - min(r, min(g, b)) > 40 }
    }

    static func save(_ bitmap: NSBitmapImageRep, name: String) {
        let dir = ProcessInfo.processInfo.environment["CHECK_V0317_SHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0317", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }

    static func source(_ name: String) throws -> String {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/check", isDirectory: true)
        return try String(contentsOf: dir.appendingCheckSourcePath(name), encoding: .utf8)
    }

    /// 주석을 걷어내고 공백을 한 칸으로 접는다. 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다.
    static func stripped(_ source: String) -> String {
        var out = ""
        var inLine = false, inBlock = false, inString = false, escaped = false
        var index = source.startIndex
        while index < source.endIndex {
            let c = source[index]
            let nextIndex = source.index(after: index)
            let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
            if inLine {
                if c == "\n" { inLine = false; out.append(c) }
            } else if inBlock {
                if c == "*", next == "/" { inBlock = false; index = nextIndex }
            } else if inString {
                out.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "/", next == "/" {
                inLine = true; index = nextIndex
            } else if c == "/", next == "*" {
                inBlock = true; index = nextIndex
            } else if c == "\"" {
                inString = true; out.append(c)
            } else {
                out.append(c)
            }
            index = source.index(after: index)
        }
        return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
