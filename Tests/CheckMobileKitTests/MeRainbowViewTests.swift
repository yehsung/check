import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **무지개 아잉이**(1.0.10)의 화면·테마 못 — 희귀 둘(황금 v0.3.54 · 무지개 v0.3.59)이 **같은 급으로** 그려지는가.
//
// ── 무엇을 재는가 ──
// "함수를 불렀다" 는 재지 않는다. 뽑기 결과 줄 · 확률 시트 줄 · 상점 타일이 **실제로 받는 값**(머리말 글자 · 둘째 줄 ·
// 강조 Bool · 상태 줄 내용 · 일곱 빛 숫자)을 값으로 받아 단언한다. 그래서 `rareHeadline` 을 `goldHeadline` 로 되돌리거나
// `finish.isRare` 를 `isGold` 로 되돌리거나 일곱 빛 하나를 바꾸면 빨개진다(뮤테이션 실측 — 커밋 메시지).
//
// ── 왜 이런 모양인가 ──
// 폰 뷰는 전부 `#if os(iOS)` 라 macOS 스위트가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다'). 그래서
// 판정을 플랫폼 무관한 세 자리(`MeText.gachaResultLines` · `MeText.gachaOddsEmphasized` · `MeCharacterTileStatus.content`)에
// 두고 값으로 재고, **뷰가 그 값을 실제로 쓰는지**만 소스 글자로 되묻는다(§5 — `GamesChessWiringTests` 와 같은 관례).
// 소스 대조는 **주석을 걷고** 읽는다(저장소 메모 '소스 계약 테스트는 주석을 걷어내야 한다' — 안 걷으면 설명을 지워야 초록이 된다).
@Suite struct MeRainbowViewTests {
    static let rainbow = CharacterCatalog.rainbowAingID
    static let gold = CharacterCatalog.goldAingID

    static func result(_ id: String, duplicate: Bool) -> GachaPullResult {
        GachaPullResult(characterID: id, isDuplicate: duplicate, shardsGained: duplicate ? 1 : 0,
                        shards: duplicate ? 4 : 3, rubyBalance: 70, replayed: false)
    }

    /// 서버가 번호 3 에 주는 모양(금 3% · 무지개 2% · 나머지 — 금·무지개는 명목가 1000 의 뽑기 전용 행).
    static func oddsRows() -> [GachaOddsRow] {
        let info = GachaInfo(price: 50, shards: 3,
                             odds: [GachaOddsEntry(characterID: gold, percent: 3),
                                    GachaOddsEntry(characterID: rainbow, percent: 2),
                                    GachaOddsEntry(characterID: "fox", percent: 60),
                                    GachaOddsEntry(characterID: "robot", percent: 35)],
                             shardCosts: [gold: 20, rainbow: 20, "fox": 3, "robot": 8])
        let shopRows = [ShopCharacterRow(id: gold, price: 1000, owned: false, gachaOnly: true),
                        ShopCharacterRow(id: rainbow, price: 1000, owned: false, gachaOnly: true),
                        ShopCharacterRow(id: "fox", price: 60, owned: false, gachaOnly: false),
                        ShopCharacterRow(id: "robot", price: 200, owned: false, gachaOnly: false)]
        // 이름 풀이는 **스토어의 진짜 경로**(카드 → 코어 내장 → id)를 쓴다 — 카드가 아직 무지개를 모르면 코어 내장 이름이 온다.
        return GachaRules.oddsRows(info: info, shopRows: shopRows, displayName: MeStore.gachaDisplayName)
    }

    // MARK: - ① 뽑기 결과 줄(상점 카드)

    @Test("무지개 결과 줄: 머리말이 정확히 '무지개 아잉이!' · 둘째 줄이 처음·중복 **둘 다** 있다 · 마감은 .rainbow")
    func rainbowResultRow() {
        let name = MeCharacterName.display(Self.rainbow)
        #expect(name == "무지개 아잉이", "결과 줄에 설 이름: \(name)")
        let first = MeText.gachaResultLines(Self.result(Self.rainbow, duplicate: false), name: name)
        let again = MeText.gachaResultLines(Self.result(Self.rainbow, duplicate: true), name: name)

        #expect(first.headline == "무지개 아잉이!", "처음 뽑은 무지개 머리말: \(first.headline)")
        #expect(again.headline == "무지개 아잉이!", "중복 무지개 머리말: \(again.headline)")
        #expect(first.headline != "황금 아잉이!", "금 머리말이 무지개 자리에 왔다")
        #expect(first.detail != nil && again.detail != nil, "무지개 결과의 둘째 줄이 비었다: \(String(describing: first.detail)) · \(String(describing: again.detail))")
        #expect(first.detail == "새 캐릭터: 무지개 아잉이", "처음 둘째 줄: \(String(describing: first.detail))")
        #expect(again.detail == "이미 있는 무지개 아잉이 → 조각 +1", "중복 둘째 줄: \(String(describing: again.detail))")
        #expect(first.finish == .rainbow && again.finish == .rainbow, "무지개 마감이 아니다 — 받침·테두리가 평범해진다")
        #expect(first.finish.isRare && again.finish.isRare)
    }

    @Test("금 결과 줄은 그대로(머리말 '황금 아잉이!' · 마감 .gold) — 무지개를 들이며 금을 깨지 않았다")
    func goldResultRowUnchanged() {
        let name = MeCharacterName.display(Self.gold)
        #expect(name == "황금 아잉이", "결과 줄에 설 이름: \(name)")
        let first = MeText.gachaResultLines(Self.result(Self.gold, duplicate: false), name: name)
        let again = MeText.gachaResultLines(Self.result(Self.gold, duplicate: true), name: name)
        #expect(first.headline == "황금 아잉이!" && again.headline == "황금 아잉이!")
        #expect(first.detail == "새 캐릭터: 황금 아잉이" && again.detail == "이미 있는 황금 아잉이 → 조각 +1")
        #expect(first.finish == .gold && again.finish == .gold)
    }

    @Test("대조군: 평범한 캐릭터는 머리말이 이름 줄이고 **둘째 줄이 없다**(희귀만 두 줄)")
    func plainResultRowHasOneLine() {
        let first = MeText.gachaResultLines(Self.result("fox", duplicate: false), name: "여우")
        let again = MeText.gachaResultLines(Self.result("fox", duplicate: true), name: "여우")
        #expect(first.headline == "새 캐릭터: 여우" && first.detail == nil)
        #expect(again.headline == "이미 있는 여우 → 조각 +1" && again.detail == nil)
        #expect(first.finish == .standard && !first.finish.isRare, "평범한 캐릭터가 희귀 받침을 받는다")
    }

    // MARK: - ② 확률 시트 줄

    @Test("확률 줄 강조: 금·무지개 참 · 여우·로봇 거짓 — 뷰가 가르는 그 값(finish.isRare)")
    func oddsEmphasisCoversBothRares() throws {
        let rows = Self.oddsRows()
        #expect(rows.count == 4)
        let emphasized = rows.filter { MeText.gachaOddsEmphasized($0) }.map(\.characterID)
        #expect(emphasized == [Self.gold, Self.rainbow], "강조된 줄: \(emphasized)")

        let rainbowRow = try #require(rows.first { $0.characterID == Self.rainbow })
        #expect(MeText.gachaOddsEmphasized(rainbowRow), "무지개 줄이 평범하게 그려진다(isGold 로 가른 흔적)")
        #expect(rainbowRow.finish == .rainbow && !rainbowRow.isGold)
        // 확률 줄의 상점가 칸: 루비 값이 아니라 얻는 길(명목가 1000 을 보이지 않는다).
        #expect(rainbowRow.shopPrice == nil && rainbowRow.priceText == "뽑기 또는 조각 20개", "무지개 상점가 칸: \(rainbowRow.priceText)")
        #expect(rainbowRow.name == "무지개 아잉이", "이름이 id 로 떨어졌다: \(rainbowRow.name)")

        let fox = try #require(rows.first { $0.characterID == "fox" })
        #expect(!MeText.gachaOddsEmphasized(fox) && fox.finish == .standard, "여우가 강조된다 — 강조가 모두 참이면 가름이 없다")
        #expect(fox.shopPrice == 60 && fox.priceText == "60")
    }

    @Test("교환 줄: 무지개도 금과 같은 급(강조 · '조각 20개') · 순서는 **코어가 준 대로**(화면이 다시 정렬하지 않는다)")
    func rainbowExchangeRow() throws {
        let info = GachaInfo(price: 50, shards: 25,
                             odds: [GachaOddsEntry(characterID: "fox", percent: 60),
                                    GachaOddsEntry(characterID: Self.rainbow, percent: 2),
                                    GachaOddsEntry(characterID: Self.gold, percent: 3),
                                    GachaOddsEntry(characterID: "robot", percent: 35)],
                             shardCosts: [Self.gold: 20, Self.rainbow: 20, "fox": 3, "robot": 8])
        let rows = GachaRules.exchangeRows(info: info, ownedIDs: ["fox"], displayName: MeStore.gachaDisplayName)
        // 서버가 무지개를 금보다 먼저 실어도 코어가 금 → 무지개 → 서버 순서로 준다.
        #expect(rows.map(\.characterID).prefix(2) == [Self.gold, Self.rainbow], "순서: \(rows.map(\.characterID))")

        let rainbowRow = try #require(rows.first { $0.characterID == Self.rainbow })
        #expect(rainbowRow.name == "무지개 아잉이")
        #expect(rainbowRow.availability == .available(cost: 20), "교환 상태: \(rainbowRow.availability)")
        #expect(GachaText.shardCost(20) == "조각 20개")
        #expect(CharacterManifest.Finish(characterID: rainbowRow.characterID).isRare, "교환 줄 강조가 평범하다")

        let fox = try #require(rows.first { $0.characterID == "fox" })
        #expect(fox.availability == .owned && !CharacterManifest.Finish(characterID: fox.characterID).isRare)

        // 화면이 다시 정렬하지 않는다(코어 순서가 유일한 주인).
        let code = try Self.strippedSource("Sources/CheckMobileKit/Me/MeGachaViews.swift")
        #expect(!code.contains("rows.sorted") && !code.contains(".sorted {"), "뽑기 화면이 코어 순서를 다시 정렬한다")
    }

    @Test("확률 시트는 합계 줄을 두지 않는다 — 표시는 한 자리 반올림이라 더하면 100.1% 가 된다")
    func oddsSheetHasNoTotalRow() throws {
        let code = try Self.strippedSource("Sources/CheckMobileKit/Me/MeGachaViews.swift")
        for needle in ["합계", "reduce(0", "\"100", "percentTotal"] {
            #expect(!code.contains(needle), "확률 시트에 합계 자리가 생겼다: \(needle)")
        }
        // 대조군: 이 파일을 실제로 읽었다.
        #expect(code.contains("MeGachaOddsSheet"), "소스를 못 읽었다 — 경로가 틀렸다(공허한 초록 방지)")
    }

    // MARK: - ③ 상점·고르기 타일

    @Test("무지개 상점 카드(.gachaOnly(shardCost: 20)): **루비 값을 안 말하고** '뽑기 · 조각 20' 을 말한다")
    func rainbowShopTileHidesRubyPrice() {
        let status = MeCharacterTileStatus.gachaOnly(shardCost: 20)
        #expect(status.content == .acquire("뽑기 · 조각 20"), "상태 줄 내용: \(status.content)")
        if case .ruby = status.content {
            Issue.record("뽑기 전용 타일이 루비 값을 말한다 — 서버 명목가 1000 이 사는 값처럼 보인다")
        }
        // 교환값을 모르면 숫자를 지어내지 않는다.
        #expect(MeCharacterTileStatus.gachaOnly(shardCost: nil).content == .acquire("뽑기 전용"))
        // 대조군: 루비로 사는 줄은 값을 말한다(가름이 실제로 있다).
        #expect(MeCharacterTileStatus.price(60, balance: 10).content == .ruby(price: 60, balance: 10))
        #expect(MeCharacterTileStatus.owned.content == .text("보유", emphasized: false))
        #expect(MeCharacterTileStatus.equipped.content == .text("착용 중", emphasized: true))
        #expect(MeCharacterTileStatus.busy.content == .spinner)
    }

    @Test("타일·막대 이름: 카드 표에 무지개가 없어도 'aing_rainbow' 가 아니라 '무지개 아잉이' 가 선다")
    func rainbowTileName() {
        #expect(MeCharacterName.display(Self.rainbow) == "무지개 아잉이",
                "카드 표 이름을 그대로 쓰면 id 가 선다: \(MeCharacterName.display(Self.rainbow))")
        #expect(MeCharacterName.display(Self.gold) == "황금 아잉이")
        #expect(MeCharacterName.display("fox") == "여우")
        #expect(MeCharacterName.display(MeCharacterCards.aingID) == "아잉")
        // 서버가 준 모르는 캐릭터는 이름을 지어내지 않는다(id 그대로).
        #expect(MeCharacterName.display("dragon") == "dragon")
    }

    @Test("무지개 타일 보이스오버·안내는 금과 같은 꼴(이름만 다르다)")
    func rainbowTileSpeech() {
        #expect(MeText.gachaTileAccessibility(name: "무지개 아잉이", shardCost: 20) == "무지개 아잉이, 뽑기 또는 조각 20개로 얻을 수 있어요")
        #expect(MeText.gachaOnlyNotice("무지개 아잉이", shardCost: 20) == "무지개 아잉이는 뽑기 또는 조각 20개로 얻을 수 있어요")
        #expect(MeText.lockedGachaCharacter("무지개 아잉이", shardCost: 20) == "무지개 아잉이는 아직 없어요 — 뽑기 또는 조각 20개로 얻을 수 있어요")
        #expect(MeText.gachaTileAccessibility(name: "황금 아잉이", shardCost: 20) == "황금 아잉이, 뽑기 또는 조각 20개로 얻을 수 있어요")
    }

    // MARK: - ④ 테마 — 일곱 빛

    @Test("무지개 일곱 빛(정본 = 다크)은 맥 CheckGachaPanel.rainbowColors 와 **같다** — 주석 걷고 소스 대조")
    func rainbowSpectrumMatchesMac() throws {
        let mac = try Self.strippedSource("Sources/check/CheckGachaPanel.swift")
        // 선언이 **하나**여야 한다 — 주석에 옛 줄을 남기고 값을 바꾸는 표류를 막는다(맥 95aadd2 가 배운 것).
        #expect(mac.components(separatedBy: "static let rainbowColors").count - 1 == 1,
                "맥 rainbowColors 선언이 하나가 아니다 — 이름이 바뀌었거나 둘로 갈렸다")
        let macColors = try Self.parseColors(mac, after: "static let rainbowColors: [Color] = [")
        #expect(macColors.count == 7, "맥에서 읽은 색이 \(macColors.count)개다")

        let phone = MobileThemePalette.rainbowSpectrum
        #expect(phone.count == 7, "폰 일곱 빛이 \(phone.count)개다")
        for (index, mine) in phone.enumerated() {
            let theirs = macColors[index]
            #expect(abs(mine.r - theirs.0) < 1e-9 && abs(mine.g - theirs.1) < 1e-9 && abs(mine.b - theirs.2) < 1e-9,
                    "\(index)번째 빛이 맥과 다르다 — 맥 \(theirs) ≠ 폰 (\(mine.r), \(mine.g), \(mine.b))")
            #expect(mine.alpha == 1, "일곱 빛은 불투명해야 한다(받침은 `rareTintOpacity` 가 깐다)")
        }
    }

    @Test("라이트 일곱 빛은 **같은 색상**(채널 비 하나)으로 밝기만 내린 값이다 — 무지개 차례가 어긋나지 않았다")
    func lightStopsKeepTheHue() {
        for (index, pair) in MobileThemePalette.rainbowStops.enumerated() {
            let ratios = [(pair.light.r, pair.dark.r), (pair.light.g, pair.dark.g), (pair.light.b, pair.dark.b)]
                .filter { $0.1 > 0.05 }
                .map { $0.0 / $0.1 }
            let spread = (ratios.max() ?? 0) - (ratios.min() ?? 0)
            #expect(spread < 0.03, "\(index)번째 빛의 라이트가 색상을 바꿨다(채널 비 \(ratios))")
            #expect((ratios.min() ?? 0) > 0.3 && (ratios.max() ?? 1) < 0.8, "\(index)번째 빛의 밝기 내림이 \(ratios) — 너무 세거나 없다")
        }
        // 금도 같은 규칙(라이트만 내리고 다크는 메달 금 그대로).
        #expect(MobileThemePalette.goldText.dark == MobileThemePalette.gold.dark, "다크 금빛 글자는 메달 금과 같은 값이어야 한다")
        #expect(MobileThemePalette.goldText.light != MobileThemePalette.gold.light, "라이트 금빛 글자가 메달 금 그대로다 — 흰 카드 위 1.8:1")
    }

    @Test("희귀 글자는 라이트·다크 모두 카드·바탕·2차 상자 위 4.5:1(일곱 빛 + 금빛 글자)")
    func rareInkIsReadableInBothModes() {
        let light = [("카드", MobileThemePalette.surface.light), ("바탕", MobileThemePalette.background.light),
                     ("2차 상자", MobileThemePalette.surface2.light)]
        let dark = [("카드", MobileThemePalette.surface.dark), ("바탕", MobileThemePalette.background.dark),
                    ("2차 상자", MobileThemePalette.surface2.dark)]
        let stops = MobileThemePalette.rainbowStops + [MobileThemePalette.goldText]
        for (index, pair) in stops.enumerated() {
            for (name, face) in light {
                #expect(pair.light.contrast(against: face) >= 4.5,
                        "\(index)번째 희귀 글자(라이트)가 \(name) 위 \(String(format: "%.2f", pair.light.contrast(against: face))):1")
            }
            for (name, face) in dark {
                #expect(pair.dark.contrast(against: face) >= 4.5,
                        "\(index)번째 희귀 글자(다크)가 \(name) 위 \(String(format: "%.2f", pair.dark.contrast(against: face))):1")
            }
        }
        // 대조군: 이 검사는 실제로 가른다 — 맥의 파스텔·메달 금을 라이트에 그대로 쓰면 떨어진다.
        #expect(MobileThemePalette.rainbowSpectrum[2].contrast(against: MobileThemePalette.surface.light) < 2,
                "맥 파스텔 노랑이 흰 카드에서 통과한다 — 대비 계산이 안 가른다")
        #expect(MobileThemePalette.gold.light.contrast(against: MobileThemePalette.surface.light) < 4.5)
    }

    // MARK: - ④-2 반짝임 기호(장식)의 색 규칙 — 글자와 갈린다(폰 1.0.10 색 고르기, 2026-10-20)
    //
    // 사장님이 시안을 보고 고른 것: 기호의 **금은 옛 메달 금으로 되돌리고**(기호는 글자가 아니라 장식이라 1.8:1 도 괜찮다),
    // **무지개는 라이트에서 단색 보라**다(작은 기호에 일곱 빛을 깔면 짙은 청록 한 색으로 읽힌다 — 실측). **다크는 그대로.**
    //
    // 값으로 잰다 — 폰 뷰·테마는 `#if os(iOS)` 라 맥 스위트가 `MobileTheme` 을 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥
    // 스위트가 못 본다'). 그래서 그 색의 뼈대인 `MobileThemePalette` 숫자를 재고, 뷰·테마가 **그 토큰을 쓰는지**는 ⑤ 가 본다.

    @Test("라이트 반짝임: 금은 메달 금 #F5B700(글자색 goldText 가 아니다) · 무지개는 일곱 중 여섯 번째 보라 단색")
    func sparkleLightFollowsDecorationRule() {
        let white = MobileThemePalette.surface.light

        // ① 금 — 기호는 글자 기준(4.5:1)을 벗어나 메달 금으로 돌아갔다. 두 값이 **다르다**는 것이 이 변경의 전부다.
        #expect(MobileThemePalette.gold.light == MobileThemePalette.RGB(hex: 0xF5B700),
                "라이트 기호 금이 메달 금이 아니다: \(MobileThemePalette.gold.light)")
        #expect(MobileThemePalette.gold.light != MobileThemePalette.goldText.light,
                "기호 금과 글자 금이 같아졌다 — 두 갈래가 다시 하나로 합쳐졌다")
        let goldOnCard = MobileThemePalette.gold.light.contrast(against: white)
        #expect(goldOnCard > 1.7 && goldOnCard < 1.9,
                "라이트 기호 금의 흰 카드 대비가 \(String(format: "%.2f", goldOnCard)):1 — 1.80 에서 움직였다")
        // 장식이니 괜찮다는 판단이지, **글자**에 쓰면 여전히 안 된다 — 확률·교환 시트의 이름 글자는 그대로 `goldText`.
        #expect(MobileThemePalette.goldText.light.contrast(against: white) >= 4.5,
                "글자용 금빛이 기호 값으로 뒤따라갔다(황금 아잉이 이름이 안 보인다)")

        // ② 무지개 — 라이트 단색은 **새 색이 아니라 그 일곱 중 여섯 번째**(보라)다(신원이 흔들리지 않는다).
        let solid = MobileThemePalette.rainbowStops[5].light
        #expect(solid == MobileThemePalette.RGB(0.43, 0.40, 0.66), "단색 보라가 바뀌었다: \(solid)")
        #expect(solid.b == MobileThemePalette.rainbowStops.map(\.light.b).max(),
                "여섯 번째가 가장 파란(보라) 빛이 아니다 — 일곱 빛 차례가 어긋났다")
        // 같은 토큰이 확률 **숫자**(글자)에도 서니 글자 기준 4.5:1 은 지킨다.
        for (name, face) in [("카드", MobileThemePalette.surface.light), ("바탕", MobileThemePalette.background.light),
                             ("2차 상자", MobileThemePalette.surface2.light)] {
            #expect(solid.contrast(against: face) >= 4.5,
                    "단색 보라가 \(name) 위 \(String(format: "%.2f", solid.contrast(against: face))):1 — 확률 숫자가 안 보인다")
        }
        // 대조군: 다크 보라를 그대로 라이트에 썼다면 이 검사가 갈랐다 — 즉 검사가 실제로 가른다.
        #expect(MobileThemePalette.rainbowStops[5].dark.contrast(against: white) < 4.5,
                "다크 보라가 흰 카드에서 통과한다 — 대비 계산이 안 가른다")
    }

    @Test("다크는 한 픽셀도 안 바뀐다 — 기호 금 #FFD24A(= goldText.dark) · 다크 무지개는 일곱 빛 그대로")
    func sparkleDarkIsUntouched() {
        // 기호를 `gold` 로 되돌려도 다크가 안 바뀌는 **이유**: 두 토큰의 다크 값이 같은 숫자다(직접 확인한 사실).
        #expect(MobileThemePalette.gold.dark == MobileThemePalette.RGB(hex: 0xFFD24A),
                "다크 메달 금: \(MobileThemePalette.gold.dark)")
        #expect(MobileThemePalette.goldText.dark == MobileThemePalette.RGB(hex: 0xFFD24A),
                "다크 금빛 글자: \(MobileThemePalette.goldText.dark)")
        #expect(MobileThemePalette.gold.dark == MobileThemePalette.goldText.dark,
                "다크 기호 금과 글자 금이 갈렸다 — 기호를 `gold` 로 되돌리면 다크까지 바뀐다")

        // 다크 무지개: 기호·확률 숫자 둘 다 일곱 빛 그대로다(단색 가름은 `colorScheme == .light` 하나뿐 — ⑤ 가 본다).
        let dark = MobileThemePalette.rainbowStops.map(\.dark)
        #expect(dark.count == 7)
        #expect(dark == MobileThemePalette.rainbowSpectrum, "다크 일곱 빛이 정본(맥과 같은 숫자)과 갈렸다")
        #expect(dark[5] == MobileThemePalette.RGB(0.65, 0.61, 1.00), "다크 여섯 번째 빛이 바뀌었다: \(dark[5])")
        // 다크에서는 일곱이 **서로 다른** 색이어야 한다 — 라이트 단색이 다크로 새면 일곱이 한 색으로 주저앉는다.
        #expect(Set(dark.map(\.hex)).count == 7, "다크 일곱 빛에 같은 색이 섞였다: \(dark.map(\.hex))")
    }

    // MARK: - ⑤ 뷰가 그 값을 실제로 쓴다(소스 글자 — 주석 걷고)

    @Test("뷰 배선: 결과 줄·확률 줄·교환 줄·타일이 희귀 둘을 가르는 값을 쓴다(금만 가리키는 옛 가름은 남아 있지 않다)")
    func viewsUseTheRareGates() throws {
        let gacha = try Self.strippedSource("Sources/CheckMobileKit/Me/MeGachaViews.swift")
        let characters = try Self.strippedSource("Sources/CheckMobileKit/Me/MeCharacterViews.swift")
        let theme = try Self.strippedSource("Sources/CheckMobileKit/Theme/MobileTheme.swift")

        var checked = 0
        let required: [(String, String, String)] = [
            ("결과 줄 문구·마감", "MeText.gachaResultLines(result, name: name)", gacha),
            ("결과 줄 받침", "MobileTheme.tint(lines.finish, otherwise: MobileTheme.surface2)", gacha),
            ("결과 줄 테두리", "MobileTheme.rare(lines.finish)", gacha),
            ("확률 줄 강조", "MeText.gachaOddsEmphasized(row)", gacha),
            ("확률 줄 글자색", "MobileTheme.ink(row.finish, otherwise: MobileTheme.label)", gacha),
            ("교환 줄 글자색", "MobileTheme.ink(finish, otherwise: MobileTheme.label)", gacha),
            ("타일 상태 내용", "switch status.content", characters),
            // 기호는 **글자 갈래가 아니라 기호 갈래**를 쓴다(1.0.10 색 고르기 — 아래 forbidden 이 옛 갈래를 막는다).
            ("타일 반짝임 갈래", "MobileTheme.sparkle(CharacterManifest.Finish(characterID: id), in: colorScheme)", characters),
            ("확률 숫자 라이트 단색 가름", "row.finish == .rainbow && colorScheme == .light", gacha),
            ("확률 숫자가 그 가름을 쓴다", "foregroundStyle(percentInk)", gacha),
            ("기호 갈래 — 라이트 무지개는 단색", "case .rainbow: return colorScheme == .light ? AnyShapeStyle(rainbowSolid) : AnyShapeStyle(rainbow)", theme),
            ("기호 갈래 — 금·평범은 메달 금", "case .gold, .standard: return AnyShapeStyle(gold)", theme),
            ("단색 보라는 일곱 중 여섯 번째", "color(MobileThemePalette.rainbowStops[5])", theme),
            ("무지개 칠", "case .rainbow: return AnyShapeStyle(rainbow)", theme),
            ("금빛 글자 칠", "case .gold: return AnyShapeStyle(goldText)", theme),
            ("평범은 호출부 기본색", "case .standard: return nil", theme),
            ("일곱 빛 그라디언트", "MobileThemePalette.rainbowStops.map(color)", theme),
        ]
        for (what, needle, source) in required {
            #expect(source.contains(needle), "\(what): `\(needle)` 가 없다")
            checked += 1
        }

        let forbidden: [(String, String, String)] = [
            ("확률 줄이 금만 본다", "row.isGold", gacha),
            ("결과 줄이 금만 본다", "result.kind == .gold", gacha),
            ("결과 받침을 금으로 못 박았다", "MobileTheme.gold.opacity", gacha),
            ("타일 반짝임을 금으로 못 박았다", "foregroundStyle(MobileTheme.gold)", characters),
            ("결과 머리말을 금으로 못 박았다", "GachaText.goldHeadline", gacha),
            // 되돌리기 막기: 기호가 다시 글자 갈래(= 라이트에서 흙빛 `goldText`)로 가면 빨개진다.
            ("타일 반짝임이 글자 갈래로 되돌아갔다", "MobileTheme.ink(CharacterManifest.Finish", characters),
            ("타일에 글자용 금빛이 남았다", "MobileTheme.goldText", characters),
        ]
        for (what, needle, source) in forbidden {
            #expect(!source.contains(needle), "\(what): `\(needle)` 가 남아 있다")
            checked += 1
        }
        #expect(checked == 24, "훑은 자리가 \(checked)곳뿐이다(공허한 초록 방지)")
    }

    // MARK: - 도우미

    /// `Color(red: … green: … blue: …)` 세 쌍을 `anchor` 다음 대괄호 안에서 읽는다.
    static func parseColors(_ source: String, after anchor: String) throws -> [(Double, Double, Double)] {
        let start = try #require(source.range(of: anchor), "닻을 못 찾았다: \(anchor)")
        let rest = source[start.upperBound...]
        let end = try #require(rest.range(of: "]"), "닻 뒤에 닫는 대괄호가 없다")
        let body = String(rest[rest.startIndex..<end.lowerBound])
        let pattern = #"Color\(red:\s*([0-9.]+),\s*green:\s*([0-9.]+),\s*blue:\s*([0-9.]+)\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { match in
            let parts = (1...3).compactMap { index -> Double? in
                guard let range = Range(match.range(at: index), in: body) else { return nil }
                return Double(body[range])
            }
            return parts.count == 3 ? (parts[0], parts[1], parts[2]) : nil
        }
    }

    /// 저장소 파일 한 벌을 **주석을 걷어내고** 돌려준다(저장소 메모 '소스 계약 테스트는 주석을 걷어내야 한다' —
    /// `GamesChessDemoRouteTests.strippedSource` 와 같은 방식).
    static func strippedSource(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        let raw = try String(contentsOf: url, encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }
}
