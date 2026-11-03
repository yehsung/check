import Foundation

// 아잉 마작 규칙 — 역·부·점수(MJ-22~MJ-42 · X-01 · X-02).
// 직접 작성, 외부 판정 코드 없음 — 정본 rules.md MJ-22~MJ-42, 대조 reference.py `evaluate`·`score_of`.
//
// `MahjongScoring.evaluate` = SQL `mahjong_evaluate(jsonb ctx)`. 입력·결과 키는 reference `evaluate()` 와 같고 다르게만 적는다:
// 패는 id(`MahjongTile`), 바람은 `MahjongWind`, 천화·지화 깃발은 `heavenly`·`earthly`(SPEC D5 — 흔한 로마자는 상표 시험 패턴과 같다).
// 해석이 여럿이면 reference `_rank_key` 순서: 지불 총액 → 역만 역 해석 먼저(X-01) → 판 → 부 → 역 id 의 `MahjongYaku.order`
// 순번 튜플 사전순 → 대기 이름 순(X-02). 점수는 100 단위 올림(ceil100). 형식 오류(14장 초과·같은 id 둘·모순 깃발) = SQL 22023.

/// 역 id — reference `YAKU`·`YAKUMAN` 의 id 그대로, 천화·지화만 `heavenly`·`earthly`(D5). raw 값 = 서버·코퍼스 id.
/// 와이어 디코드는 이 열거로 바로 하지 않는다(원문 문자열 + `var yakuKind: MahjongYaku?`, SPEC §4.1 끝 · CC-07).
package nonisolated enum MahjongYaku: String, Codable, Sendable, CaseIterable {
    case riichi, doubleRiichi = "double_riichi", ippatsu, menzenTsumo = "menzen_tsumo", pinfu, iipeikou, tanyao,
         yakuhaiHaku = "yakuhai_haku", yakuhaiHatsu = "yakuhai_hatsu", yakuhaiChun = "yakuhai_chun", bakaze, jikaze,
         chankan, rinshan, haitei, houtei, chiitoitsu, sanshoku, ittsu, chanta, toitoi, sanankou,
         sanshokuDoukou = "sanshoku_doukou", sankantsu, honroutou, shousangen, honitsu, junchan, ryanpeikou, chinitsu,
         heavenly, earthly, kokushi, kokushi13 = "kokushi_13", suuankou, suuankouTanki = "suuankou_tanki", daisangen,
         shousuushii, daisuushii, tsuuiisou, ryuuiisou, chinroutou, suukantsu, chuuren, junseiChuuren = "junsei_chuuren"

    /// = SQL `mahjong_yaku_order()` = reference `YAKU_ORDER`(역만 먼저, 그다음 일반 역 — 각 표의 적힌 순서). 해석 고르기 5단(X-02)의 순번.
    package static let order: [MahjongYaku] = [
        .heavenly, .earthly, .kokushi, .kokushi13, .suuankou, .suuankouTanki, .daisangen, .shousuushii, .daisuushii,
        .tsuuiisou, .ryuuiisou, .chinroutou, .suukantsu, .chuuren, .junseiChuuren,
        .riichi, .doubleRiichi, .ippatsu, .menzenTsumo, .pinfu, .iipeikou, .tanyao, .yakuhaiHaku, .yakuhaiHatsu,
        .yakuhaiChun, .bakaze, .jikaze, .chankan, .rinshan, .haitei, .houtei, .chiitoitsu, .sanshoku, .ittsu, .chanta,
        .toitoi, .sanankou, .sanshokuDoukou, .sankantsu, .honroutou, .shousangen, .honitsu, .junchan, .ryanpeikou, .chinitsu,
    ]

    /// reference 한국어 이름(천화·지화 포함). 화면 문구는 MahjongNoticeText 가 이것을 부른다.
    package var koreanName: String {
        switch self {
        case .riichi: "리치"
        case .doubleRiichi: "더블 리치"
        case .ippatsu: "일발"
        case .menzenTsumo: "멘젠쯔모"
        case .pinfu: "핑후"
        case .iipeikou: "이페코"
        case .tanyao: "탕야오"
        case .yakuhaiHaku: "역패 백"
        case .yakuhaiHatsu: "역패 발"
        case .yakuhaiChun: "역패 중"
        case .bakaze: "역패 장풍"
        case .jikaze: "역패 자풍"
        case .chankan: "창깡"
        case .rinshan: "영상개화"
        case .haitei: "해저모월"
        case .houtei: "하저로어"
        case .chiitoitsu: "치또이쯔"
        case .sanshoku: "삼색동순"
        case .ittsu: "일기통관"
        case .chanta: "찬타"
        case .toitoi: "또이또이"
        case .sanankou: "산안커"
        case .sanshokuDoukou: "삼색동각"
        case .sankantsu: "산깡쯔"
        case .honroutou: "혼노두"
        case .shousangen: "소삼원"
        case .honitsu: "혼일색"
        case .junchan: "준찬타"
        case .ryanpeikou: "량페코"
        case .chinitsu: "청일색"
        case .heavenly: "천화"
        case .earthly: "지화"
        case .kokushi: "국사무쌍"
        case .kokushi13: "국사무쌍 13면"
        case .suuankou: "사암각"
        case .suuankouTanki: "사암각 단기"
        case .daisangen: "대삼원"
        case .shousuushii: "소사희"
        case .daisuushii: "대사희"
        case .tsuuiisou: "자일색"
        case .ryuuiisou: "녹일색"
        case .chinroutou: "청노두"
        case .suukantsu: "사깡쯔"
        case .chuuren: "구련보등"
        case .junseiChuuren: "순정 구련보등"
        }
    }
}

/// 결과 `yaku` 의 한 칸 `[id, 판]`. Codable = 두 칸 배열(reference·서버 jsonb 그대로). 역만 역의 판 칸은 배수다.
package nonisolated struct MahjongYakuHan: Equatable, Hashable, Sendable, Codable {
    package let yaku: MahjongYaku
    package let han: Int

    package init(yaku: MahjongYaku, han: Int) {
        self.yaku = yaku
        self.han = han
    }

    package init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        yaku = try container.decode(MahjongYaku.self)
        han = try container.decode(Int.self)
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(yaku)
        try container.encode(han)
    }
}

/// 지불(본장 제외) — reference `points`: 론 `ron` · 자 쯔모 `from_dealer`+`from_child` · 친 쯔모 `from_each`. 해당 없는 칸은 nil(인코드에서 빠진다).
package nonisolated struct MahjongPoints: Equatable, Hashable, Sendable, Codable {
    package var ron: Int?
    package var fromDealer: Int?
    package var fromChild: Int?
    package var fromEach: Int?

    package init(ron: Int? = nil, fromDealer: Int? = nil, fromChild: Int? = nil, fromEach: Int? = nil) {
        self.ron = ron
        self.fromDealer = fromDealer
        self.fromChild = fromChild
        self.fromEach = fromEach
    }
}

/// 손 계산 입력 = SQL `mahjong_evaluate` 입력 jsonb(reference `evaluate()` 입력 — 패는 id).
/// closed = 손 안의 패(화료패 제외, 13 − 3 × 부로 수) · win = 화료패 · 친 = seatWind == .east.
package nonisolated struct MahjongWinContext: Sendable {
    package var closed: [MahjongTile]
    package var melds: [MahjongMeld]
    package var win: MahjongTile
    package var tsumo: Bool
    package var seatWind: MahjongWind
    package var roundWind: MahjongWind
    package var riichi, doubleRiichi, ippatsu, rinshan, chankan, haitei, houtei, heavenly, earthly: Bool
    /// 열린 도라 표시패(깡도라 포함).
    package var doraIndicators: [MahjongTile]
    /// 뒷도라 표시패(리치 화료만 센다).
    package var uraIndicators: [MahjongTile]
    package var honba: Int
    /// 판 위 리치봉 개수.
    package var kyoutaku: Int

    package init(
        closed: [MahjongTile], melds: [MahjongMeld] = [], win: MahjongTile, tsumo: Bool,
        seatWind: MahjongWind = .east, roundWind: MahjongWind = .east,
        riichi: Bool = false, doubleRiichi: Bool = false, ippatsu: Bool = false, rinshan: Bool = false,
        chankan: Bool = false, haitei: Bool = false, houtei: Bool = false, heavenly: Bool = false, earthly: Bool = false,
        doraIndicators: [MahjongTile] = [], uraIndicators: [MahjongTile] = [], honba: Int = 0, kyoutaku: Int = 0
    ) {
        self.closed = closed
        self.melds = melds
        self.win = win
        self.tsumo = tsumo
        self.seatWind = seatWind
        self.roundWind = roundWind
        self.riichi = riichi
        self.doubleRiichi = doubleRiichi
        self.ippatsu = ippatsu
        self.rinshan = rinshan
        self.chankan = chankan
        self.haitei = haitei
        self.houtei = houtei
        self.heavenly = heavenly
        self.earthly = earthly
        self.doraIndicators = doraIndicators
        self.uraIndicators = uraIndicators
        self.honba = honba
        self.kyoutaku = kyoutaku
    }
}

/// 손 계산 결과 = SQL `mahjong_evaluate` 결과(키 이름 그대로 — 카멜, 인코더·디코더가 스네이크로 바꾼다).
/// 화료 아님은 `agari == false` + `reason`('not_complete'|'no_yaku') 이고 나머지 칸은 0·빈 값.
/// limit: ''|mangan|haneman|baiman|sanbaiman|yakuman. wait: ryanmen|shanpon|kanchan|penchan|tanki|kokushi. form: standard|chiitoi|kokushi.
package nonisolated struct MahjongScore: Equatable, Sendable, Codable {
    package let agari: Bool
    package let reason: String?
    package let yaku: [MahjongYakuHan]
    /// 역만 배수(0 = 역만 아님).
    package let yakuman: Int
    package let dora: Int
    package let aka: Int
    package let ura: Int
    package let han: Int
    package let fu: Int
    package let limit: String
    package let base: Int
    package let points: MahjongPoints
    package let honbaBonus: Int
    package let kyoutakuBonus: Int
    package let total: Int
    package let wait: String?
    package let form: String?

    package init(
        agari: Bool, reason: String? = nil, yaku: [MahjongYakuHan] = [], yakuman: Int = 0,
        dora: Int = 0, aka: Int = 0, ura: Int = 0, han: Int = 0, fu: Int = 0,
        limit: String = "", base: Int = 0, points: MahjongPoints = MahjongPoints(),
        honbaBonus: Int = 0, kyoutakuBonus: Int = 0, total: Int = 0, wait: String? = nil, form: String? = nil
    ) {
        self.agari = agari
        self.reason = reason
        self.yaku = yaku
        self.yakuman = yakuman
        self.dora = dora
        self.aka = aka
        self.ura = ura
        self.han = han
        self.fu = fu
        self.limit = limit
        self.base = base
        self.points = points
        self.honbaBonus = honbaBonus
        self.kyoutakuBonus = kyoutakuBonus
        self.total = total
        self.wait = wait
        self.form = form
    }

    private enum CodingKeys: String, CodingKey {
        case agari, reason, yaku, yakuman, dora, aka, ura, han, fu, limit, base, points
        case honbaBonus, kyoutakuBonus, total, wait, form
    }

    /// 화료 아님 결과(`{agari:false, reason}`)처럼 칸이 빠져도 받는다 — 빠진 칸은 0·빈 값.
    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            agari: try c.decode(Bool.self, forKey: .agari),
            reason: try c.decodeIfPresent(String.self, forKey: .reason),
            yaku: try c.decodeIfPresent([MahjongYakuHan].self, forKey: .yaku) ?? [],
            yakuman: try c.decodeIfPresent(Int.self, forKey: .yakuman) ?? 0,
            dora: try c.decodeIfPresent(Int.self, forKey: .dora) ?? 0,
            aka: try c.decodeIfPresent(Int.self, forKey: .aka) ?? 0,
            ura: try c.decodeIfPresent(Int.self, forKey: .ura) ?? 0,
            han: try c.decodeIfPresent(Int.self, forKey: .han) ?? 0,
            fu: try c.decodeIfPresent(Int.self, forKey: .fu) ?? 0,
            limit: try c.decodeIfPresent(String.self, forKey: .limit) ?? "",
            base: try c.decodeIfPresent(Int.self, forKey: .base) ?? 0,
            points: try c.decodeIfPresent(MahjongPoints.self, forKey: .points) ?? MahjongPoints(),
            honbaBonus: try c.decodeIfPresent(Int.self, forKey: .honbaBonus) ?? 0,
            kyoutakuBonus: try c.decodeIfPresent(Int.self, forKey: .kyoutakuBonus) ?? 0,
            total: try c.decodeIfPresent(Int.self, forKey: .total) ?? 0,
            wait: try c.decodeIfPresent(String.self, forKey: .wait),
            form: try c.decodeIfPresent(String.self, forKey: .form)
        )
    }
}

/// 손 계산 입력 형식 오류 = SQL `22023`(예외 글에 패를 넣지 않는다, SPEC §2.2). reason 은 고정 낱말(진단).
package nonisolated enum MahjongInputError: Error, Equatable, Sendable {
    /// 14장 초과·같은 id 둘·부로 모양 틀림·모순 깃발(reference `_validate`) 등. reason 예: "tile_count" · "duplicate_tile" · "bad_meld" · "flags".
    case invalid(reason: String)
}

/// 손 계산(SQL `mahjong_evaluate` · `mahjong_score_of` 쌍둥이).
package nonisolated enum MahjongScoring {
    /// 손 하나의 화료 판정·점수(MJ-22~MJ-41). 천화는 MJ-36 대로 14장 중 가장 높은 화료패를 고른다.
    // R2 가 채운다 — 지금은 형식 검사 일부와 '화료 꼴 아님'만 돌려준다(역·부·점수는 R2).
    package static func evaluate(_ ctx: MahjongWinContext) -> Result<MahjongScore, MahjongInputError> {
        let all = ctx.closed + [ctx.win] + ctx.melds.flatMap(\.tiles)
        guard Set(all.map(\.id)).count == all.count else { return .failure(.invalid(reason: "duplicate_tile")) }
        guard ctx.closed.count + 1 + ctx.melds.count * 3 == 14 else { return .failure(.invalid(reason: "tile_count")) }
        let counts = MahjongTiles.counts34(ctx.closed + [ctx.win])
        guard MahjongHand.isComplete(counts, melds: ctx.melds.count) else {
            return .success(MahjongScore(agari: false, reason: "not_complete"))
        }
        return .success(MahjongScore(agari: false, reason: "no_yaku"))
    }

    /// MJ-39·MJ-40 점수표 한 칸(본장 제외) = reference `score_of`. yakuman = 역만 배수(0 = 아님). 절상만관 없음.
    package static func scoreOf(han: Int, fu: Int, dealer: Bool, tsumo: Bool, yakuman: Int = 0) -> (base: Int, limit: String, points: MahjongPoints, total: Int) {
        let (base, limit) = limitBase(han: han, fu: fu, yakuman: yakuman)
        let points = payments(base: base, dealer: dealer, tsumo: tsumo)
        return (base, limit, points, total(points))
    }

    // MARK: - 내부(reference `_limit_base`·`payments`·`_total`·`ceil100`)

    static func limitBase(han: Int, fu: Int, yakuman: Int) -> (Int, String) {
        if yakuman > 0 { return (8000 * yakuman, "yakuman") }
        if han >= 13 { return (8000, "yakuman") }
        if han >= 11 { return (6000, "sanbaiman") }
        if han >= 8 { return (4000, "baiman") }
        if han >= 6 { return (3000, "haneman") }
        if han >= 5 { return (2000, "mangan") }
        let b = fu * (1 << max(han + 2, 0))
        return b > 2000 ? (2000, "mangan") : (b, "")
    }

    static func ceil100(_ x: Int) -> Int {
        x >= 0 ? (x + 99) / 100 * 100 : -((-x) / 100 * 100)
    }

    static func payments(base: Int, dealer: Bool, tsumo: Bool) -> MahjongPoints {
        if !tsumo { return MahjongPoints(ron: ceil100(base * (dealer ? 6 : 4))) }
        if dealer { return MahjongPoints(fromEach: ceil100(base * 2)) }
        return MahjongPoints(fromDealer: ceil100(base * 2), fromChild: ceil100(base))
    }

    static func total(_ p: MahjongPoints) -> Int {
        if let ron = p.ron { return ron }
        if let each = p.fromEach { return each * 3 }
        return (p.fromDealer ?? 0) + 2 * (p.fromChild ?? 0)
    }
}
