@testable import CheckCore
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 상점 · 고르기 칸의 얻는 길: 흑우 아잉이는 '조각 교환 전용', 개발에 찌든 아잉이는 '미션 보상'(맥과 같은 글자).
// 서버는 두 행을 `gacha_only` 로 싣는다 — 그대로 두면 폰이 둘 다 "뽑기 · 조각 N" 으로 그려 거짓이 된다(흑우는 뽑기에서 안 나오고, 개발은
// 뽑기도 교환도 아니다).
@Suite("폰 1.0.18 — 흑우 · 개발 아잉이 칸의 얻는 길")
struct V1018CharacterShopTests {
    static let hwoo = CharacterCatalog.hwooAingID
    static let dev = CharacterCatalog.devAingID

    @Test("타일 내용: 흑우 = 조각 교환 전용(뽑기 글자 없음) · 개발 = 잠긴 '미션 보상' · 금은 그대로 '뽑기 · 조각 20'")
    func tileContent() {
        #expect(MeCharacterTileStatus.shardOnly(shardCost: 20).content == .acquire(GachaText.shardOnlyPrice(shardCost: 20)))
        if case .acquire(let text) = MeCharacterTileStatus.shardOnly(shardCost: 20).content {
            #expect(!text.contains(GachaText.pullButton), "흑우 칸이 뽑기를 말한다: \(text)")
        }
        #expect(MeCharacterTileStatus.missionLocked.content == .locked(DevAingMission.lockedCaption))
        #expect(DevAingMission.lockedCaption == "미션 보상")
        #expect(MeCharacterTileStatus.gachaOnly(shardCost: 20).content == .acquire(MeText.gachaTileStatus(shardCost: 20)))
    }

    @Test("안내 · 보이스오버: 흑우는 '교환으로만', 금은 '뽑기 또는' · 개발은 미션 길")
    func phrases() {
        #expect(MeText.acquirePhrase(id: Self.hwoo, shardCost: 20).contains("교환으로만"))
        #expect(!MeText.acquirePhrase(id: Self.hwoo, shardCost: 20).contains("뽑기"))
        #expect(MeText.acquirePhrase(id: CharacterCatalog.goldAingID, shardCost: 20) == MeText.gachaAcquirePhrase(shardCost: 20))
        #expect(MeText.acquireNotice(id: Self.hwoo, shardCost: 20).hasPrefix("흑우 아잉이는 "))
        #expect(MeText.lockedAcquireCharacter(id: Self.hwoo, shardCost: nil).hasSuffix(GachaText.shardOnlyHint))
        #expect(MeText.shardOnlyAcquirePhrase(shardCost: 20) == "\(GachaText.shardCost(20)) 교환으로만 얻을 수 있어요")
        #expect(MeText.shardOnlyAcquirePhrase(shardCost: nil) == GachaText.shardOnlyHint)
    }

    @Test("스토어 판정: 개발 = 미션 잠김 · 흑우 = 조각 교환 전용 · 둘 다 선물 전용은 아니다")
    @MainActor
    func storeClassification() async {
        let harness = await RankMeHarness(label: "v1018-shop") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(store.isMissionLocked(Self.dev) && !store.isMissionLocked(Self.hwoo))
        #expect(store.isShardOnly(Self.hwoo) && !store.isShardOnly(Self.dev))
        #expect(!store.isGiftOnly(Self.dev) && !store.isGiftOnly(Self.hwoo))
        store.selectShopItem(Self.dev)
        #expect(store.shopSelection == nil && store.shopGiftHintID == Self.dev && store.shopNotice == DevAingMission.lockedHint)
    }
    @Test("빼빼로 선물 시트: 고를 것 없는 한 개 선물 — 처음부터 빼빼로를 고른 채 · 문구는 빼빼로 묶음(C '빼빼로 받아랏! 🍫') · 다시 열기 기호 🍫")
    func peperoGiftSheet() {
        let offer = CharacterGiftOffer(id: "g", options: [CharacterCatalog.peperoAingID], note: nil, kind: .pepero)
        let sheet = MeCakeGiftSheet(gift: offer)
        #expect(sheet.selection == CharacterCatalog.peperoAingID && sheet.canConfirm)
        #expect(sheet.copy.title == PeperoGiftText.title && PeperoGiftText.title == "빼빼로 받아랏! 🍫")
        #expect(MeCharacterTileStatus.giftOnly(.pepero).content == .locked(PeperoGiftText.lockedCaption))
        #expect(CharacterGiftKind.pepero.phoneReopenEmoji == "🍫")
        // 생일은 그대로 고르게 한다(1.0.14 동작).
        let birthday = MeCakeGiftSheet(gift: CharacterGiftOffer(id: "b", options: [CharacterCatalog.cakeStrawberryAingID]))
        #expect(birthday.selection == nil)
    }
}
