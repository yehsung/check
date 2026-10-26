// `package` 타입(ShopStateResponse·GachaInfo·GachaRules·MobileDemoFixtures·MobileStubRequest·MeCharacterCards)의
// 멤버와이즈·내부 멤버를 쓰므로 `@testable` 로 받는다 — 같은 폴더 `MeAchievementsFixtureContractTests` 와 같은 길이다.
@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **무지개 아잉이**(맥 v0.3.59 / 폰 1.0.10) 데모 픽스처의 계약.
//
// ── 왜 이 파일인가 ──
// 무지개는 폰에서 **데이터로만** 들어온다: 서버 `shop_state`(능력 번호 3) · `gacha_pull` · `gacha_exchange` ·
// `app_user_characters`. 화면(폰 뷰)은 `#if os(iOS)` 라 맥 스위트가 한 줄도 못 보므로(저장소 메모 '폰 뷰는 맥 스위트가
// 못 본다'), 심사원·스크린샷이 보게 될 **그 데이터**를 여기서 못 박는다. 모양("키가 있다")이 아니라 **값**을 잰다 —
// 모델 디코드가 관대해서(칸 하나가 없으면 그 칸만 nil) 키를 빠뜨려도 화면은 멀쩡해 보인다.
//
// ── 무엇을 재는가 ──
//   §1 확률표: 두 `shop_state` 픽스처가 **8줄 · 정수 · 합 정확히 100 · 황금 3 · 무지개 2**(2026-10-20 운영 서버가
//      능력 번호 3 인 클라에게 주는 값 그대로). 두 파일이 같은 표인지도 본다 — 한 쪽만 고치면 상점 라우트와 나 탭이 다른 확률을 말한다.
//   §2 교환표: `shard_costs.aing_rainbow == 20` 이고, 그 값이 **데모에서 실제로 닿는다**(조각 23 ≥ 20 → `.available(cost: 20)`).
//      닿지 않으면 교환 응답 픽스처는 영영 안 쓰이는 죽은 파일이다.
//   §3 무지개 캐릭터 행: `gacha_only` 이고 **살 수 있는 줄이 아니다** — 명목가 1000 이 화면·구매에 쓰이지 않는다
//      (`ShopCharacterRow.isPurchasable` · `MeStore.price(of:)` 와 같은 규칙 · 확률표 상점가 칸은 "뽑기 또는 조각 20개").
//   §4 응답 픽스처: 기본 `gacha_pull` 이 **무지개 결과**로 풀린다(`GachaPullResult.Kind.rainbow` — 심사원이 그 연출을 본다) ·
//      루비·조각이 상점 값과 어긋나지 않는다 · 교환은 바늘(`@aing_rainbow`)로 무지개 줄에 닿는다.
//   §5 `app_user_characters`: 무지개 착용자가 **한 명 이상** 있고 그 값이 정확히 `aing_rainbow` 다(공백·대소문자 섞임 없음) ·
//      초상을 그릴 수 있는 빌드에서는 **이니셜로 접히지 않는다**.
//   §6 카드 그림이 11장(1.0.14 케이크 둘 포함)이고 무지개 카드의 픽셀 크기가 0이 아니다(1.0.9 는 8장이었고 무지개 착용자가 이니셜로 떨어졌다).
//
// ── 닿는 길(데모 라우트) ──
//   me                                      나 탭 — 캐릭터 카드 · 상점 카드(장면 `_me`)
//   me/shop                                 상점 하위 화면(장면 `_me-shop`)
//   me/shop + `-AingCheckDemoMeGacha odds`      확률표 시트(§1 · §3 의 글자가 그대로 보인다)
//   me/shop + `-AingCheckDemoMeGacha exchange`  조각 교환 시트(§2)
//   me/shop + `-AingCheckDemoMeGacha pull`      한 번 뽑기 → **무지개 결과 연출**(§4)
//   now                                     팀 목록에 무지개 착용자(보리)가 초상으로 선다(§5)
@Suite struct MeRainbowFixtureContractTests {

    // MARK: - §0 재료

    static let index = MobileDemoFixtures.load()

    /// 서비스 디코더와 같은 설정(`SupabaseWorkService` 가 쓰는 전략).
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static let rainbowID = CharacterCatalog.rainbowAingID
    static let goldID = CharacterCatalog.goldAingID

    /// 상점 픽스처 둘. **정확히 이 둘**이다(`_me-` 는 뽑기가 아예 없는 갓 가입 장면이라 이 계약 밖이다 — §1 이 로스터를 센다).
    static let shopPaths = [
        "me/_me/rpc.shop_state.json",
        "me/_me-shop/rpc.shop_state.json",
    ]
    /// 뽑기가 없는 장면(옛 서버·갓 가입 모양) — 확률표 계약을 적용하지 않는 유일한 예외.
    static let shopPathWithoutGacha = "me/_me-/rpc.shop_state.json"

    static let pullPath = "me/rpc.gacha_pull.json"
    static let exchangePath = "me/rpc.gacha_exchange.json"
    static let exchangeRainbowPath = "me/rpc.gacha_exchange@aing_rainbow.json"
    static let charactersPath = "base/rpc.app_user_characters.json"

    /// 2026-10-20 운영 서버가 능력 번호 3 인 클라에게 주는 확률표 — **순서까지** 그대로. 정본은 서버다
    /// (값이 바뀌는 날 이 표와 픽스처를 같이 고친다 — 둘 중 하나만 고치면 빨개진다).
    static let odds: [(id: String, percent: Int)] = [
        ("aing_gold", 3), ("aing_rainbow", 2), ("fox", 24), ("squirrel", 24),
        ("shiba", 14), ("ghost", 14), ("jellyfish", 11), ("robot", 8),
    ]
    /// 서버 교환표(`shard_costs`) 그대로 — 무지개는 금과 같은 20.
    static let shardCosts: [String: Int] = [
        "aing_gold": 20, "aing_rainbow": 20, "fox": 2, "squirrel": 2,
        "shiba": 4, "ghost": 4, "jellyfish": 5, "robot": 8,
    ]

    static func entry(_ path: String) throws -> MobileDemoFixtures.Entry {
        try #require(index.entries.first { $0.relativePath == path }, "픽스처 없음: \(path)")
    }

    static func raw(_ path: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try entry(path).data) as? [String: Any],
                     "\(path): JSON 객체가 아니다")
    }

    static func shop(_ path: String) throws -> ShopStateResponse {
        try decoder.decode(ShopStateResponse.self, from: try entry(path).data)
    }

    static func gacha(_ path: String) throws -> GachaInfo {
        try #require(try shop(path).gacha, "\(path): gacha 키가 없다 — 능력 번호 3 응답이 아니다")
    }

    static func row(_ path: String, _ id: String) throws -> ShopCharacterRow {
        let rows = try #require(try shop(path).characters, "\(path): characters 가 없다")
        return try #require(rows.first { $0.id == id }, "\(path): \(id) 행이 없다")
    }

    /// 폰 이름 출처(나 탭 카드 표) — 맥은 카탈로그, 폰은 이 표다.
    static func displayName(_ id: String) -> String? { MeCharacterCards.card(id: id)?.displayName }

    static func request(rpc: String, body: String) -> MobileStubRequest {
        MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)",
                          query: "", headers: [:], bodyText: body)
    }

    /// 서비스 인코더와 같은 설정(`SupabaseWorkService.init` — `convertToSnakeCase`). RPC 본문 글자를 실제 모양으로 만든다.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static func bodyText<Body: Encodable>(_ body: Body) throws -> String {
        String(decoding: try encoder.encode(body), as: UTF8.self)
    }

    // MARK: - §1 확률표: 8줄 · 정수 · 합 100 · 황금 3 · 무지개 2

    @Test("상점 픽스처 로스터: 확률표를 싣는 파일은 정확히 둘이고, 뽑기 없는 장면은 하나다")
    func shopFixtureRoster() throws {
        let found = Set(Self.index.entries.filter { $0.key == "rpc.shop_state" }.map(\.relativePath))
        let want = Set(Self.shopPaths + [Self.shopPathWithoutGacha])
        #expect(found == want, "상점 픽스처 목록이 바뀌었다: \(found.symmetricDifference(want))")
        // 갓 가입 장면은 뽑기 키가 **없어야** 한다(있으면 §1 을 안 재고도 초록이 되는 구멍이 생긴다).
        let fresh = try Self.shop(Self.shopPathWithoutGacha)
        #expect(fresh.gacha == nil, "\(Self.shopPathWithoutGacha) 에 뽑기가 생겼다 — 확률표 계약에 넣어야 한다")
    }

    @Test("확률표: 두 픽스처 모두 8줄 · 전부 정수 · 합이 정확히 100 · 황금 3 · 무지개 2 · 서버 순서 그대로", arguments: shopPaths)
    func oddsAreTheServerTable(path: String) throws {
        let info = try Self.gacha(path)
        let rows = try #require(info.odds, "\(path): odds 가 없다")
        #expect(rows.count == 8, "\(path): 확률이 \(rows.count)줄이다(서버는 8줄)")
        #expect(rows.map(\.characterID) == Self.odds.map(\.id), "\(path): 확률표 순서·id 가 서버와 다르다 — \(rows.map(\.characterID))")

        // 합을 **스스로 더한다**. 정수 합이라 부동소수 오차가 끼지 않는다(정수 단언이 먼저 서는 까닭).
        let percents = rows.map(\.percent)
        for (row, want) in zip(rows, Self.odds) {
            #expect(row.percent == Double(want.percent), "\(path): \(row.characterID) 확률이 \(row.percent)다(서버는 \(want.percent))")
            #expect(row.percent == row.percent.rounded(), "\(path): \(row.characterID) 확률이 정수가 아니다(\(row.percent))")
        }
        #expect(percents.reduce(0, +) == 100, "\(path): 확률 합이 \(percents.reduce(0, +))다 — 100 이어야 한다")

        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.characterID, $0.percent) })
        #expect(byID[Self.goldID] == 3, "\(path): 황금 확률이 \(byID[Self.goldID] ?? -1)다(서버는 3)")
        #expect(byID[Self.rainbowID] == 2, "\(path): 무지개 확률이 \(byID[Self.rainbowID] ?? -1)다(서버는 2)")

        // 원문이 **정수 글자**인지도 본다 — 디코드가 Double 이라 `2.0` 이 와도 위 단언은 전부 초록이다(서버는 정수를 준다).
        let rawGacha = try #require(try Self.raw(path)["gacha"] as? [String: Any], "\(path): gacha 가 객체가 아니다")
        let rawRows = try #require(rawGacha["odds"] as? [[String: Any]], "\(path): odds 가 배열이 아니다")
        for rawRow in rawRows {
            let id = (rawRow["character_id"] as? String) ?? "?"
            let number = try #require(rawRow["percent"] as? NSNumber, "\(path): \(id) percent 가 숫자가 아니다")
            #expect(!"\(number)".contains("."), "\(path): \(id) 확률이 정수 글자가 아니다(\(number))")
        }
    }

    @Test("확률표: 두 픽스처가 같은 표다(한 쪽만 고치면 상점 라우트와 나 탭이 다른 확률을 말한다)")
    func bothShopFixturesAgree() throws {
        let first = try Self.gacha(Self.shopPaths[0])
        let second = try Self.gacha(Self.shopPaths[1])
        #expect(first == second, "두 상점 픽스처의 뽑기 값이 갈렸다")
        let firstRows = try Self.shop(Self.shopPaths[0]).characters
        let secondRows = try Self.shop(Self.shopPaths[1]).characters
        #expect(firstRows == secondRows, "두 상점 픽스처의 캐릭터 목록이 갈렸다")
    }

    // MARK: - §2 교환표: 무지개 20 · 데모에서 실제로 닿는다

    @Test("교환표: shard_costs 가 서버 표 그대로이고 무지개는 20이다", arguments: shopPaths)
    func shardCostsAreTheServerTable(path: String) throws {
        let costs = try #require(try Self.gacha(path).shardCosts, "\(path): shard_costs 가 없다")
        #expect(costs == Self.shardCosts, "\(path): 교환표가 서버와 다르다 — \(costs)")
        #expect(costs[Self.rainbowID] == 20, "\(path): 무지개 교환값이 \(costs[Self.rainbowID].map(String.init) ?? "없다")다(서버는 20)")
    }

    @Test("교환: 데모 조각으로 무지개 줄이 실제로 눌린다(.available(cost: 20)) · 금과 같은 값", arguments: shopPaths)
    func rainbowExchangeIsReachableInTheDemo(path: String) throws {
        let info = try Self.gacha(path)
        let shards = try #require(info.shards, "\(path): 조각 수가 없다")
        #expect(shards >= 20, "\(path): 데모 조각이 \(shards)개라 무지개(20) 교환 줄이 비활성이다 — 교환 응답 픽스처가 죽은 파일이 된다")

        let shopRows = try #require(try Self.shop(path).characters, "\(path): characters 가 없다")
        let owned = Set(shopRows.filter { $0.owned == true }.map(\.id))
        #expect(!owned.contains(Self.rainbowID), "\(path): 데모가 무지개를 이미 가졌다 — 교환 줄이 '보유'로 선다")
        let rows = GachaRules.exchangeRows(info: info, ownedIDs: owned, displayName: Self.displayName(_:))
        let rainbow = try #require(rows.first { $0.characterID == Self.rainbowID }, "\(path): 교환 목록에 무지개 줄이 없다")
        #expect(rainbow.availability == .available(cost: 20), "\(path): 무지개 교환 줄이 \(rainbow.availability)다")
        #expect(rainbow.name == "무지개 아잉이", "\(path): 교환 줄 이름이 '\(rainbow.name)'다")
        // 희귀 둘이 맨 위, 금 먼저 · 무지개 다음(코어 규칙 — 서버 순서와 무관).
        #expect(rows.prefix(2).map(\.characterID) == [Self.goldID, Self.rainbowID], "\(path): 교환 목록 맨 위가 \(rows.prefix(2).map(\.characterID))다")
    }

    // MARK: - §3 무지개 행: 뽑기 전용이고 **살 수 있는 줄이 아니다**

    @Test("캐릭터 행: 무지개는 gacha_only 이고 명목가 1000 이 구매·화면에 쓰이지 않는다", arguments: shopPaths)
    func rainbowRowIsNotForSale(path: String) throws {
        let rainbow = try Self.row(path, Self.rainbowID)
        #expect(rainbow.gachaOnly == true, "\(path): 무지개 행에 gacha_only 표식이 없다")
        #expect(rainbow.price == 1000, "\(path): 무지개 명목가가 \(rainbow.price.map(String.init) ?? "없다")다(서버는 1000)")
        // 사는 줄이 아니다 — 이 한 판정이 [1000 사기] 를 끈다(`MeStore.price(of:)` 가 이 값을 묻는다).
        #expect(!rainbow.isPurchasable, "\(path): 무지개가 살 수 있는 줄로 선다 — 서버가 not_for_sale 로 거절한다")
        // 금과 같은 급: 금도 같은 모양이어야 한다(한 쪽만 맞으면 무지개가 특별 취급을 못 받는다).
        let gold = try Self.row(path, Self.goldID)
        #expect(!gold.isPurchasable, "\(path): 황금이 살 수 있는 줄로 선다")
        // 살 수 있는 줄은 그대로 살 수 있다(위 단언이 전부를 잠가서 초록이 되는 것을 막는다).
        let fox = try Self.row(path, "fox")
        #expect(fox.isPurchasable, "\(path): 여우가 살 수 없는 줄이 됐다")
    }

    @Test("확률표 상점가 칸: 무지개는 루비 값 대신 '뽑기 또는 조각 20개'를 말한다", arguments: shopPaths)
    func rainbowOddsRowSaysHowToGetItInsteadOfAPrice(path: String) throws {
        let state = try Self.shop(path)
        let info = try #require(state.gacha)
        let rows = GachaRules.oddsRows(info: info, shopRows: state.characters ?? [], displayName: Self.displayName(_:))
        let rainbow = try #require(rows.first { $0.characterID == Self.rainbowID }, "\(path): 확률표에 무지개 줄이 없다")
        #expect(rainbow.isGachaOnly, "\(path): 무지개 줄이 뽑기 전용이 아니다")
        #expect(rainbow.isRainbow && !rainbow.isGold, "\(path): 무지개 줄의 희귀 판정이 틀렸다")
        #expect(rainbow.shopPrice == nil, "\(path): 무지개 줄에 상점가 \(rainbow.shopPrice.map(String.init) ?? "")가 섰다")
        #expect(rainbow.shardCost == 20, "\(path): 무지개 줄의 교환값이 \(rainbow.shardCost.map(String.init) ?? "없다")다")
        #expect(rainbow.priceText == "뽑기 또는 조각 20개", "\(path): 무지개 줄 상점가 칸이 '\(rainbow.priceText)'다")
        #expect(rainbow.percentText == "2%", "\(path): 무지개 줄 확률 글자가 '\(rainbow.percentText)'다")
        #expect(rainbow.name == "무지개 아잉이", "\(path): 무지개 줄 이름이 '\(rainbow.name)'다")
        // 보통 캐릭터는 숫자 그대로(기준선이 같은 입력이면 그 테스트는 영원히 초록이다).
        #expect(rows.first { $0.characterID == "fox" }?.priceText == "60", "\(path): 여우 상점가 칸이 숫자가 아니다")
    }

    @Test("뽑기 버튼: 데모 루비로 뽑을 수 있다(확률표·교환 시트가 열리는 전제)", arguments: shopPaths)
    func demoCanPull(path: String) throws {
        let state = try Self.shop(path)
        #expect(GachaRules.pullAvailability(info: state.gacha, rubyBalance: state.rubyBalance) == .ready(price: 50),
                "\(path): 뽑기 버튼이 비활성이다 — 뽑기 결과 픽스처에 닿을 길이 없다")
    }

    // MARK: - §4 응답 픽스처: 기본 뽑기가 무지개 연출로 풀린다

    @Test("뽑기 응답: 기본 픽스처가 무지개 결과다(심사원·스크린샷이 그 연출을 본다)")
    func defaultPullIsRainbow() throws {
        let response = try Self.decoder.decode(GachaPullResponse.self, from: try Self.entry(Self.pullPath).data)
        #expect(response.status == .ok)
        #expect(response.characterID == Self.rainbowID, "기본 뽑기 결과가 \(response.characterID ?? "없다")다")
        guard case .pulled(let result) = GachaPullOutcome(response: response) else {
            Issue.record("기본 뽑기 픽스처가 결과로 풀리지 않는다")
            return
        }
        #expect(result.kind == .rainbow, "뽑기 연출 갈래가 \(result.kind)다 — 무지개 연출이 안 뜬다")
        #expect(result.isRainbow && !result.isGold)
        #expect(!result.isDuplicate && result.shardsGained == 0, "처음 뽑은 결과인데 조각을 줬다")
        #expect(!result.replayed, "재응답으로 표시된 픽스처는 '깎이지 않았다' 안내를 띄운다")

        // 숫자가 상점 값과 어긋나지 않는다: 루비는 1회값만큼 줄고, 조각은 (처음 뽑기라) 그대로다.
        let info = try Self.gacha(Self.shopPaths[0])
        let state = try Self.shop(Self.shopPaths[0])
        let before = try #require(state.rubyBalance, "상점 픽스처에 루비 잔량이 없다")
        let price = try #require(info.price, "상점 픽스처에 1회값이 없다")
        #expect(response.price == price, "응답의 1회값(\(response.price.map(String.init) ?? "없다"))이 상점(\(price))과 다르다")
        #expect(result.rubyBalance == before - price, "뽑은 뒤 루비가 \(result.rubyBalance.map(String.init) ?? "없다")다(\(before) - \(price) 이어야 한다)")
        #expect(result.shards == info.shards, "뽑은 뒤 조각이 \(result.shards.map(String.init) ?? "없다")다(상점은 \(info.shards.map(String.init) ?? "없다"))")
    }

    @Test("뽑기 응답: 바늘이 없다 — 뽑기 본문에는 캐릭터 id 가 없으므로 기본 파일이 곧 데모 결과다")
    func pullHasNoVariantBecauseTheBodyCarriesNoCharacter() throws {
        // `gacha_pull(p_protocol, p_request_id)` — 본문에 캐릭터가 없다(코어 `GachaPullRequest`). 그래서 변형을 고를 바늘이
        // 없고, 데모가 무지개 연출을 보여 주는 길은 **기본 파일을 무지개로 두는 것** 하나다. 이 단언은 그 사실에 못을 박는다:
        // 누가 `rpc.gacha_pull@…` 을 더하면 그 파일은 영영 안 쓰이는 죽은 파일이라 여기서 빨개진다.
        let variants = Self.index.entries.filter { $0.key == "rpc.gacha_pull" && $0.needle != nil }
        #expect(variants.isEmpty, "뽑기 변형은 고를 길이 없다(본문에 캐릭터 id 가 없다): \(variants.map(\.relativePath))")
        let body = try Self.bodyText(GachaPullRequest(protocolVersion: ShopWire.rainbowProtocol, requestID: UUID()))
        #expect(!body.contains(Self.rainbowID) && !body.contains(Self.goldID), "뽑기 본문에 캐릭터 id 가 생겼다: \(body)")
        #expect(body.contains("\"p_protocol\":3"), "능력 번호 3 을 싣지 않는다: \(body)")
    }

    @Test("교환 응답: 무지개 줄을 누르면 바늘이 무지개 응답을 고른다 · 기본은 여전히 다람쥐다")
    func exchangeVariantAnswersTheRainbowRow() throws {
        // 교환 본문에는 캐릭터 id 가 있다(`GachaExchangeRequest.pCharacterId`) — 뽑기와 달리 바늘을 쓸 수 있다.
        let rainbowBody = try Self.bodyText(GachaExchangeRequest(
            characterID: Self.rainbowID, protocolVersion: ShopWire.rainbowProtocol, requestID: UUID()))
        let picked = try #require(Self.index.entry(for: Self.request(rpc: "gacha_exchange", body: rainbowBody), scenario: "me"))
        #expect(picked.relativePath == Self.exchangeRainbowPath, "무지개 교환이 \(picked.relativePath) 로 떨어진다")

        let rainbow = try Self.decoder.decode(GachaExchangeResponse.self, from: picked.data)
        #expect(rainbow.status == .ok)
        #expect(rainbow.characterID == Self.rainbowID)
        #expect(rainbow.cost == 20, "무지개 교환이 조각 \(rainbow.cost.map(String.init) ?? "없다")개를 썼다(서버 교환표는 20)")
        let shopInfo = try Self.gacha(Self.shopPaths[0])
        let shards = try #require(shopInfo.shards, "상점 픽스처에 조각 수가 없다")
        #expect(rainbow.shards == shards - 20, "교환 뒤 조각이 \(rainbow.shards.map(String.init) ?? "없다")다(\(shards) - 20 이어야 한다)")
        guard case .exchanged(let id, _, let cost, _) = GachaExchangeOutcome(response: rainbow, requestedID: Self.rainbowID) else {
            Issue.record("무지개 교환 픽스처가 결과로 풀리지 않는다")
            return
        }
        #expect(id == Self.rainbowID && cost == 20)

        // 기본(바늘 없는) 응답은 그대로 다람쥐다 — 무지개가 기본을 빼앗으면 다른 줄을 눌러도 무지개가 나와 데모가 거짓을 말한다.
        let squirrelBody = try Self.bodyText(GachaExchangeRequest(
            characterID: "squirrel", protocolVersion: ShopWire.rainbowProtocol, requestID: UUID()))
        let fallback = try #require(Self.index.entry(for: Self.request(rpc: "gacha_exchange", body: squirrelBody), scenario: "me"))
        #expect(fallback.relativePath == Self.exchangePath)
        let squirrel = try Self.decoder.decode(GachaExchangeResponse.self, from: fallback.data)
        #expect(squirrel.characterID == "squirrel")
        #expect(squirrel.cost == Self.shardCosts["squirrel"], "다람쥐 교환값이 교환표와 다르다")
        #expect(squirrel.shards == shards - 2, "다람쥐 교환 뒤 조각이 상점 조각 수와 어긋난다")
    }

    // MARK: - §5 착용자: 한 명 이상 · 이니셜로 접히지 않는다

    @Test("캐릭터 한 표: 무지개 착용자가 한 명 이상이고 값이 정확히 aing_rainbow 다")
    func someoneWearsRainbow() throws {
        let data = try Self.entry(Self.charactersPath).data
        let rawRows = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let rawValues = rawRows.compactMap { $0["character"] as? String }
        let rainbowRaw = rawValues.filter { $0.contains("rainbow") }
        #expect(rainbowRaw.count >= 1, "무지개 착용자가 없다 — 1.0.10 의 팀 목록 초상을 볼 길이 없다")
        #expect(rainbowRaw.allSatisfy { $0 == Self.rainbowID }, "착용값이 정확한 id 가 아니다(공백·대소문자): \(rainbowRaw)")

        let rows = try Self.decoder.decode([AppUserCharacterRow].self, from: data)
        let wearers = rows.filter { $0.character == Self.rainbowID }.compactMap(\.userId)
        #expect(wearers.count >= 1, "디코드 뒤 무지개 착용자가 사라졌다")
        // 금을 입은 사람이 있으면 건드리지 않았다(있으면 그대로 — 이 단언은 금을 요구하지 않고 '무지개가 금을 밀어내지 않았다'를 본다).
        #expect(rows.count >= 15, "표가 \(rows.count)행으로 줄었다 — 다른 데모 단언들이 덜 재고 초록이 된다")
    }

    @Test("접기: 무지개 착용자는 초상을 그릴 수 있는 빌드에서 이니셜로 떨어지지 않는다")
    func rainbowWearerDoesNotFoldToInitials() throws {
        let rows = try Self.decoder.decode([AppUserCharacterRow].self, from: try Self.entry(Self.charactersPath).data)
        let wearer = try #require(rows.first { $0.character == Self.rainbowID }?.userId, "무지개 착용자가 없다")

        // 이 레인은 초상 번들 목록(`AingCharacterArt.knownIDs` — CheckMobileShared)을 소유하지 않는다. 그래서 단언을 **그 사실에
        // 걸어** 쓴다: 목록이 무지개를 알면 초상이 서야 하고(1.0.10 의 계약), 아직 모르면 이니셜이 서는 것이 맞다(1.0.9 의 사실).
        // 다른 레인이 그 목록에 무지개를 더하는 순간 위 가지로 넘어가고, 그때 접히면 여기서 빨개진다.
        if AingCharacterArt.knownIDs.contains(Self.rainbowID) {
            let directory = AppUserCharacterDirectory(knownIDs: AingCharacterArt.knownIDs, rows: rows)
            #expect(directory.characterID(for: wearer) == Self.rainbowID,
                    "무지개 착용자가 \(directory.characterID(for: wearer) ?? "이니셜")로 떨어진다")
        } else {
            let directory = AppUserCharacterDirectory(knownIDs: AingCharacterArt.knownIDs, rows: rows)
            #expect(directory.characterID(for: wearer) == nil,
                    "초상 목록이 무지개를 모르는데 그림이 섰다 — 빈 그림이 서면 이니셜보다 나쁘다")
        }

        // 목록이 무지개를 알 때의 판정은 **지금도** 잴 수 있다 — 픽스처 값이 접기 규칙을 그대로 통과하는지(공백·별칭 없음)를 본다.
        let known = AppUserCharacterDirectory(knownIDs: AingCharacterArt.knownIDs + [Self.rainbowID], rows: rows)
        #expect(known.characterID(for: wearer) == Self.rainbowID,
                "무지개를 아는 빌드에서도 착용값이 \(known.characterID(for: wearer) ?? "이니셜")로 접힌다 — 픽스처 값이 id 가 아니다")
        #expect(known.avatar(for: wearer, photoURL: nil) == .character(Self.rainbowID), "아바타가 캐릭터로 서지 않는다")
        // 나 탭 카드 표는 이 레인 소유다 — 여기는 조건 없이 알아야 한다.
        #expect(MeCharacterCards.equippedID(fromServer: Self.rainbowID) == Self.rainbowID, "나 탭이 무지개 착용값을 아잉으로 접는다")
    }

    // MARK: - §6 카드 그림

    @Test("카드 그림: 열한 장이고(1.0.14 케이크 둘을 더해) 무지개 카드의 픽셀 크기가 0이 아니다")
    func rainbowCardIsBaked() throws {
        #expect(MeCharacterCards.bundled.count == 11, "카드가 \(MeCharacterCards.bundled.count)장이다(무지개 9장 + 케이크 둘 = 11장)")
        #expect(MeCharacterCards.knownIDs.contains(Self.rainbowID), "카드 표가 무지개를 모른다")
        let card = try #require(MeCharacterCards.card(id: Self.rainbowID), "무지개 카드가 없다")
        #expect(card.displayName == "무지개 아잉이")
        #expect(card.pixelWidth > 0 && card.pixelHeight > 0, "무지개 카드 크기가 \(card.pixelWidth)×\(card.pixelHeight)다")
        #expect(card.sourceCropWidth > 0 && card.sourceCropHeight > 0, "무지개 카드 원본 상자가 비었다")
        #expect(!card.heicBase64.isEmpty, "무지개 카드 그림이 비었다")
        let image = try #require(MeCharacterCards.image(id: Self.rainbowID), "무지개 카드가 디코드되지 않는다")
        #expect(image.width == card.pixelWidth && image.height == card.pixelHeight,
                "디코드한 그림이 \(image.width)×\(image.height)다(박힌 값은 \(card.pixelWidth)×\(card.pixelHeight))")
    }
}
