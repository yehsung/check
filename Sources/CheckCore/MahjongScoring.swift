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
    /// 형식 오류(장수·같은 id 둘·부로 모양·모순 깃발 — reference `_validate`)는 `.failure`(= SQL 22023).
    /// 화료 아님은 `.success(agari: false, reason: "not_complete"|"no_yaku")`.
    /// honbaBonus = 화료자가 받는 본장 몫 합(론 300 × 본장, 쯔모 100 × 본장 × 3 — 같은 값). reference 의
    /// `honba_bonus` 사전(`{ron:n}`·`{from_each:n}`)은 쯔모 여부로 갈리므로 정수 하나로 접었다(지불 칸은 settleWin 이 쓴다).
    /// 역만의 fu 는 0(reference null).
    package static func evaluate(_ ctx: MahjongWinContext) -> Result<MahjongScore, MahjongInputError> {
        if let error = validate(ctx) { return .failure(error) }
        if ctx.heavenly {
            // MJ-36 천화: 14장 가운데 어느 패를 화료패로 봐도 되므로 가장 높은 해석을 고른다(같은 종류·같은 적 여부는 한 번만).
            let tiles = ctx.closed + [ctx.win]
            var best: Candidate?
            for i in tiles.indices {
                let t = tiles[i]
                if tiles[..<i].contains(where: { $0.kind == t.kind && $0.isRed == t.isRed }) { continue }
                var c2 = ctx
                c2.closed = Array(tiles[..<i]) + Array(tiles[(i + 1)...])
                c2.win = t
                if case .agari(let cand) = evaluateOne(c2), best.map({ cand.ranks(before: $0) }) ?? true {
                    best = cand
                }
            }
            if let best { return .success(finish(best, ctx: ctx)) }
        }
        switch evaluateOne(ctx) {
        case .agari(let cand): return .success(finish(cand, ctx: ctx))
        case .notAgari(let reason): return .success(MahjongScore(agari: false, reason: reason))
        }
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

// MARK: - 손 계산 몸통(reference `_evaluate_one`·`_interpretations`·`_yakuman_checks`·`_normal_yaku`·`_calc_fu`·`_rank_key`)

extension MahjongScoring {
    /// 몸통 한 묶음. 머리는 따로(pairKind). opened = 밝은 몸통(울기·대명깡·가깡·론으로 완성한 커쯔).
    struct Group: Equatable {
        enum Shape { case seq, trip, kan }
        let shape: Shape
        /// 순쯔는 첫 종류, 커쯔·깡은 그 종류.
        let kind: Int
        let opened: Bool
    }

    /// 해석 하나 = 꼴 · 몸통(울기 포함) · 머리 종류 · 대기 이름.
    struct Interpretation {
        let form: String
        let groups: [Group]
        let pairKind: Int?
        let wait: String
    }

    /// 해석 하나의 점수 — `_rank_key` 로 견준다.
    struct Candidate {
        let yaku: [MahjongYakuHan]
        let yakuman: Int
        let han: Int
        let fu: Int
        let dora: Int, aka: Int, ura: Int
        let form: String
        let wait: String
        let base: Int
        let limit: String
        let points: MahjongPoints
        let totalBase: Int

        /// MJ-38 해석 고르기(reference `_rank_key` — 작은 쪽이 고른 해석): 지불 총액 큰 쪽 → 역만 역 해석 먼저(X-01) →
        /// 판 많은 쪽 → 부 많은 쪽 → 역 id 를 `MahjongYaku.order` 순번으로 정렬한 배열의 사전순 작은 쪽 → 대기 이름 순(X-02).
        func ranks(before other: Candidate) -> Bool {
            if totalBase != other.totalBase { return totalBase > other.totalBase }
            if (yakuman > 0) != (other.yakuman > 0) { return yakuman > 0 }
            if han != other.han { return han > other.han }
            if fu != other.fu { return fu > other.fu }
            let mine = yakuOrderKey, theirs = other.yakuOrderKey
            if mine != theirs { return mine.lexicographicallyPrecedes(theirs) }
            return MahjongScoring.waitOrder.firstIndex(of: wait) ?? 9 < MahjongScoring.waitOrder.firstIndex(of: other.wait) ?? 9
        }

        var yakuOrderKey: [Int] {
            yaku.map { MahjongScoring.orderIndex[$0.yaku] ?? 99 }.sorted()
        }
    }

    enum OneResult {
        case agari(Candidate)
        case notAgari(String)
    }

    /// X-02 대기 이름 순.
    static let waitOrder = ["ryanmen", "shanpon", "kanchan", "penchan", "tanki", "kokushi"]

    static let orderIndex: [MahjongYaku: Int] = {
        var out: [MahjongYaku: Int] = [:]
        for (i, y) in MahjongYaku.order.enumerated() { out[y] = i }
        return out
    }()

    static let dragons = [31, 32, 33]
    static let terminals = [0, 8, 9, 17, 18, 26]
    /// MJ-34 녹일색: 2·3·4·6·8삭 + 발.
    static let green = [19, 20, 21, 23, 25, 32]

    /// 결과 칸을 채운다(MJ-41 본장 · MJ-28 공탁).
    static func finish(_ c: Candidate, ctx: MahjongWinContext) -> MahjongScore {
        let honbaBonus = 300 * ctx.honba
        let kyoutakuBonus = 1000 * ctx.kyoutaku
        return MahjongScore(
            agari: true, reason: nil, yaku: c.yaku, yakuman: c.yakuman, dora: c.dora, aka: c.aka, ura: c.ura,
            han: c.han, fu: c.fu, limit: c.limit, base: c.base, points: c.points,
            honbaBonus: honbaBonus, kyoutakuBonus: kyoutakuBonus, total: c.totalBase + honbaBonus + kyoutakuBonus,
            wait: c.wait, form: c.form
        )
    }

    /// 부로 하나 → 몸통. 모양이 틀리면 nil(reference `_parse_meld`).
    static func meldGroup(_ meld: MahjongMeld) -> Group? {
        let ks = meld.tiles.map(\.kind).sorted()
        switch meld.type {
        case .chi:
            guard ks.count == 3, ks[0] < 27, ks[1] == ks[0] + 1, ks[2] == ks[0] + 2, ks[0] / 9 == ks[2] / 9 else { return nil }
            return Group(shape: .seq, kind: ks[0], opened: true)
        case .pon:
            guard ks.count == 3, Set(ks).count == 1 else { return nil }
            return Group(shape: .trip, kind: ks[0], opened: true)
        case .minkan, .kakan, .ankan:
            guard ks.count == 4, Set(ks).count == 1 else { return nil }
            return Group(shape: .kan, kind: ks[0], opened: meld.type != .ankan)
        }
    }

    /// 형식 검사(reference `_evaluate_one` 앞부분 + `_validate`). 오류가 없으면 nil.
    static func validate(_ ctx: MahjongWinContext) -> MahjongInputError? {
        let all = ctx.closed + [ctx.win] + ctx.melds.flatMap(\.tiles)
        if Set(all.map(\.id)).count != all.count { return .invalid(reason: "duplicate_tile") }
        if ctx.melds.count > 4 || ctx.closed.count != 13 - 3 * ctx.melds.count { return .invalid(reason: "tile_count") }
        var groups: [Group] = []
        for meld in ctx.melds {
            guard let g = meldGroup(meld) else { return .invalid(reason: "bad_meld") }
            groups.append(g)
        }
        let menzen = groups.allSatisfy { !$0.opened }
        let dealer = ctx.seatWind == .east
        let hasKan = groups.contains { $0.shape == .kan }
        let contradictions: [Bool] = [
            ctx.doubleRiichi && !ctx.riichi,                          // 더블 리치는 리치도 켠다
            (ctx.riichi || ctx.ippatsu) && !menzen,                   // MJ-27 리치는 멘젠만
            ctx.ippatsu && !ctx.riichi,                               // MJ-30 일발은 리치만
            ctx.rinshan && (!ctx.tsumo || !hasKan),                   // MJ-21 영상개화는 깡 뒤 쯔모
            ctx.rinshan && (ctx.ippatsu || ctx.haitei),               // MJ-33 영상개화는 일발·해저와 겹치지 않음
            ctx.chankan && ctx.tsumo,                                 // MJ-20 창깡은 론
            ctx.haitei && !ctx.tsumo,                                 // MJ-19 해저는 쯔모
            ctx.houtei && (ctx.tsumo || ctx.chankan),                 // MJ-19 하저는 타패 론
            ctx.heavenly && (!dealer || !ctx.tsumo || !ctx.melds.isEmpty),  // MJ-34 천화는 친·쯔모·울기 없음
            ctx.earthly && (dealer || !ctx.tsumo || !ctx.melds.isEmpty),    // MJ-34 지화는 자·쯔모·울기 없음
        ]
        return contradictions.contains(true) ? .invalid(reason: "flags") : nil
    }

    /// 형식 검사를 지난 손 하나(화료패 고정)의 가장 높은 해석.
    static func evaluateOne(_ ctx: MahjongWinContext) -> OneResult {
        let meldGroups = ctx.melds.compactMap(meldGroup)
        let menzen = meldGroups.allSatisfy { !$0.opened }
        let noMelds = meldGroups.isEmpty
        let winKind = ctx.win.kind
        let c13 = MahjongTiles.counts34(ctx.closed)
        var c14 = c13
        c14[winKind] += 1
        var call14 = c14   // 손 + 울기 전체(역 판정용) — 깡도 종류 판정에는 3장으로 충분
        for g in meldGroups {
            if g.shape == .seq {
                for j in 0..<3 { call14[g.kind + j] += 1 }
            } else {
                call14[g.kind] += 3
            }
        }
        let interps = interpretations(c14: c14, meldGroups: meldGroups, winKind: winKind, tsumo: ctx.tsumo, noMelds: noMelds)
        if interps.isEmpty { return .notAgari("not_complete") }

        let allKinds = (ctx.closed + [ctx.win] + ctx.melds.flatMap(\.tiles)).map(\.kind)
        func countDora(_ indicators: [MahjongTile]) -> Int {
            indicators.reduce(0) { sum, ind in
                let d = MahjongTiles.doraKind(ofIndicator: ind.kind)
                return sum + allKinds.filter { $0 == d }.count
            }
        }
        let dora = countDora(ctx.doraIndicators)
        let aka = (ctx.closed + [ctx.win] + ctx.melds.flatMap(\.tiles)).filter(\.isRed).count
        let ura = ctx.riichi ? countDora(ctx.uraIndicators) : 0
        let dealer = ctx.seatWind == .east
        let seatKind = 27 + windIndex(ctx.seatWind)
        let roundKind = 27 + windIndex(ctx.roundWind)

        var best: Candidate?
        for interp in interps {
            let cand: Candidate
            let ym = yakumanChecks(call14, interp, ctx: ctx, c13: c13, noMelds: noMelds)
            if !ym.isEmpty {
                let mult = ym.reduce(0) { $0 + $1.yakumanMultiple }
                let yaku = ym.sorted { (orderIndex[$0] ?? 0) < (orderIndex[$1] ?? 0) }.map { MahjongYakuHan(yaku: $0, han: $0.yakumanMultiple * 13) }
                let (base, limit) = limitBase(han: 0, fu: 0, yakuman: mult)
                let points = payments(base: base, dealer: dealer, tsumo: ctx.tsumo)
                cand = Candidate(yaku: yaku, yakuman: mult, han: 13 * mult, fu: 0, dora: 0, aka: 0, ura: 0,
                                 form: interp.form, wait: interp.wait, base: base, limit: limit, points: points, totalBase: total(points))
            } else {
                let ys = normalYaku(call14, interp, ctx: ctx, menzen: menzen, seatKind: seatKind, roundKind: roundKind)
                let yhan = ys.reduce(0) { $0 + $1.han }
                if yhan == 0 { continue }
                let fu: Int
                if interp.form == "chiitoi" {
                    fu = 25
                } else {
                    let pinfu = ys.contains { $0.yaku == .pinfu }
                    fu = calcFu(interp, tsumo: ctx.tsumo, menzen: menzen, pinfu: pinfu, seatKind: seatKind, roundKind: roundKind)
                }
                let han = yhan + dora + aka + ura
                let (base, limit) = limitBase(han: han, fu: fu, yakuman: 0)
                let points = payments(base: base, dealer: dealer, tsumo: ctx.tsumo)
                let sorted = ys.sorted { (orderIndex[$0.yaku] ?? 0) < (orderIndex[$1.yaku] ?? 0) }
                cand = Candidate(yaku: sorted, yakuman: 0, han: han, fu: fu, dora: dora, aka: aka, ura: ura,
                                 form: interp.form, wait: interp.wait, base: base, limit: limit, points: points, totalBase: total(points))
            }
            if best.map({ cand.ranks(before: $0) }) ?? true { best = cand }
        }
        guard let best else { return .notAgari("no_yaku") }
        return .agari(best)
    }

    static func windIndex(_ w: MahjongWind) -> Int {
        switch w {
        case .east: 0
        case .south: 1
        case .west: 2
        case .north: 3
        }
    }

    /// MJ-38 모든 해석 = (몸통 분해 × 화료패 자리). reference `_interpretations`.
    static func interpretations(c14: [Int], meldGroups: [Group], winKind: Int, tsumo: Bool, noMelds: Bool) -> [Interpretation] {
        var out: [Interpretation] = []
        if noMelds && MahjongHand.isKokushi(c14) {
            out.append(Interpretation(form: "kokushi", groups: [], pairKind: nil, wait: "kokushi"))
        }
        if noMelds && MahjongHand.isChiitoi(c14) {
            out.append(Interpretation(form: "chiitoi", groups: [], pairKind: winKind, wait: "tanki"))
        }
        for d in standardDecompositions(c14, melds: meldGroups.count) {
            guard let pair = d.first(where: { $0.shape == .pair })?.kind else { continue }
            let body = d.filter { $0.shape != .pair }
            // 화료패가 들어갈 자리: 머리 · 커쯔 · 순쯔의 몇 번째 칸. 같은 모양(같은 종류·같은 칸)은 한 번만.
            var places: [(shape: Part.Shape, kind: Int, offset: Int)] = []
            for part in d {
                switch part.shape {
                case .pair where part.kind == winKind: places.append((.pair, part.kind, -1))
                case .trip where part.kind == winKind: places.append((.trip, part.kind, -1))
                case .seq where part.kind <= winKind && winKind <= part.kind + 2: places.append((.seq, part.kind, winKind - part.kind))
                default: break
                }
            }
            var seen: [(Part.Shape, Int, Int)] = []
            for place in places {
                if seen.contains(where: { $0.0 == place.shape && $0.1 == place.kind && $0.2 == place.offset }) { continue }
                seen.append((place.shape, place.kind, place.offset))
                var groups: [Group] = []
                var used = false
                for part in body {
                    var opened = false
                    // 론으로 완성한 커쯔는 밝은 커쯔(MJ-33·MJ-37)
                    if !used && part.shape == .trip && place.shape == .trip && part.kind == place.kind && !tsumo {
                        opened = true
                        used = true
                    }
                    groups.append(Group(shape: part.shape == .seq ? .seq : .trip, kind: part.kind, opened: opened))
                }
                groups += meldGroups
                out.append(Interpretation(form: "standard", groups: groups, pairKind: pair,
                                          wait: waitName(place.shape, place.kind, winKind: winKind)))
            }
        }
        return out
    }

    /// 분해 조각(머리·커쯔·순쯔).
    struct Part: Equatable, Hashable {
        enum Shape: Int, Hashable { case pair, seq, trip }   // reference 정렬('pair' < 'seq' < 'trip')과 같은 순서
        let shape: Shape
        let kind: Int
    }

    /// 표준형 분해 전부(겹침 없이). reference `standard_decompositions`.
    static func standardDecompositions(_ counts: [Int], melds: Int) -> [[Part]] {
        var c = counts
        var out: [[Part]] = []
        var seen = Set<[Part]>()
        var path: [Part] = []
        func walk(need: Int, havePair: Bool, start: Int) {
            var i = start
            while i < 34 && c[i] == 0 { i += 1 }
            if i == 34 {
                if need == 0 && havePair {
                    let key = path.sorted { ($0.shape.rawValue, $0.kind) < ($1.shape.rawValue, $1.kind) }
                    if seen.insert(key).inserted { out.append(key) }
                }
                return
            }
            if !havePair && c[i] >= 2 {
                c[i] -= 2; path.append(Part(shape: .pair, kind: i))
                walk(need: need, havePair: true, start: i)
                path.removeLast(); c[i] += 2
            }
            if need > 0 && c[i] >= 3 {
                c[i] -= 3; path.append(Part(shape: .trip, kind: i))
                walk(need: need - 1, havePair: havePair, start: i)
                path.removeLast(); c[i] += 3
            }
            if need > 0 && i < 27 && i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0 {
                c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1; path.append(Part(shape: .seq, kind: i))
                walk(need: need - 1, havePair: havePair, start: i)
                path.removeLast(); c[i] += 1; c[i + 1] += 1; c[i + 2] += 1
            }
        }
        if (0...4).contains(melds) { walk(need: 4 - melds, havePair: false, start: 0) }
        return out
    }

    /// MJ-37-4 화료패가 든 몸통으로 대기 이름을 정한다. reference `_wait_kind`.
    static func waitName(_ shape: Part.Shape, _ k: Int, winKind: Int) -> String {
        switch shape {
        case .pair: return "tanki"
        case .trip: return "shanpon"
        case .seq:
            if winKind == k + 1 { return "kanchan" }
            if winKind == k { return k % 9 + 1 == 7 ? "penchan" : "ryanmen" }
            return winKind % 9 + 1 == 3 ? "penchan" : "ryanmen"
        }
    }

    /// MJ-34 역만. reference `_yakuman_checks`(c14 = 손 + 울기 전체 장수).
    static func yakumanChecks(_ c14: [Int], _ it: Interpretation, ctx: MahjongWinContext, c13: [Int], noMelds: Bool) -> [MahjongYaku] {
        var ym: [MahjongYaku] = []
        let allKinds = (0..<34).filter { c14[$0] > 0 }
        if ctx.heavenly { ym.append(.heavenly) }
        if ctx.earthly { ym.append(.earthly) }
        if it.form == "kokushi" {
            ym.append(MahjongTiles.yaochu.allSatisfy { c13[$0] == 1 } ? .kokushi13 : .kokushi)
        }
        if it.form == "standard" {
            let conceal = it.groups.filter { $0.shape != .seq && !$0.opened }.count
            if conceal == 4 { ym.append(it.wait == "tanki" ? .suuankouTanki : .suuankou) }
            let trips = it.groups.filter { $0.shape != .seq }.map(\.kind)
            if dragons.allSatisfy({ trips.contains($0) }) { ym.append(.daisangen) }
            let windTrips = trips.filter { MahjongTiles.winds.contains($0) }
            if windTrips.count == 4 {
                ym.append(.daisuushii)
            } else if windTrips.count == 3, let pair = it.pairKind, MahjongTiles.winds.contains(pair) {
                ym.append(.shousuushii)
            }
            if it.groups.filter({ $0.shape == .kan }).count == 4 { ym.append(.suukantsu) }
        }
        if it.form == "standard" || it.form == "chiitoi" {
            if allKinds.allSatisfy({ $0 >= 27 }) { ym.append(.tsuuiisou) }
            if allKinds.allSatisfy({ terminals.contains($0) }) { ym.append(.chinroutou) }
        }
        if allKinds.allSatisfy({ green.contains($0) }) { ym.append(.ryuuiisou) }
        // 구련보등: 멘젠·울기/깡 없음·한 색 1112345678999 + 1
        if noMelds && it.form == "standard" {
            let suits = Set(allKinds.map { MahjongSuit.of(kind: $0) })
            if suits.count == 1, let suit = suits.first, suit != .honor {
                let s = suit.rawValue
                let v = Array(c14[(s * 9)..<(s * 9 + 9)])
                if v[0] >= 3 && v[8] >= 3 && v[1..<8].allSatisfy({ $0 >= 1 }) {
                    let w13 = Array(c13[(s * 9)..<(s * 9 + 9)])
                    ym.append(w13 == [3, 1, 1, 1, 1, 1, 1, 1, 3] ? .junseiChuuren : .chuuren)
                }
            }
        }
        return ym
    }

    /// 일반 역의 (멘젠 판, 울었을 때 판 | nil = 멘젠만) — reference `YAKU`.
    static func hanValue(_ y: MahjongYaku) -> (closed: Int, open: Int?) {
        switch y {
        case .riichi, .ippatsu, .menzenTsumo, .pinfu, .iipeikou: (1, nil)
        case .doubleRiichi, .chiitoitsu: (2, nil)
        case .tanyao, .yakuhaiHaku, .yakuhaiHatsu, .yakuhaiChun, .bakaze, .jikaze, .chankan, .rinshan, .haitei, .houtei: (1, 1)
        case .sanshoku, .ittsu, .chanta: (2, 1)
        case .toitoi, .sanankou, .sanshokuDoukou, .sankantsu, .honroutou, .shousangen: (2, 2)
        case .honitsu, .junchan: (3, 2)
        case .ryanpeikou: (3, nil)
        case .chinitsu: (6, 5)
        default: (0, nil)   // 역만은 여기 오지 않는다
        }
    }

    /// MJ-32·MJ-33 일반 역. reference `_normal_yaku`.
    static func normalYaku(_ c14: [Int], _ it: Interpretation, ctx: MahjongWinContext, menzen: Bool, seatKind: Int, roundKind: Int) -> [MahjongYakuHan] {
        var ys: [MahjongYakuHan] = []
        func add(_ y: MahjongYaku) {
            let v = hanValue(y)
            guard let h = menzen ? v.closed : v.open else { return }
            ys.append(MahjongYakuHan(yaku: y, han: h))
        }
        let allKinds = (0..<34).filter { c14[$0] > 0 }
        let yaochu = MahjongTiles.yaochu
        if ctx.riichi {
            add(ctx.doubleRiichi ? .doubleRiichi : .riichi)
            if ctx.ippatsu { add(.ippatsu) }
        }
        if menzen && ctx.tsumo { add(.menzenTsumo) }
        if ctx.chankan { add(.chankan) }
        if ctx.rinshan { add(.rinshan) }
        if ctx.haitei { add(.haitei) }
        if ctx.houtei { add(.houtei) }
        if allKinds.allSatisfy({ !yaochu.contains($0) }) { add(.tanyao) }
        let suits = Set(allKinds.map { MahjongSuit.of(kind: $0) })
        if suits.subtracting([.honor]).count == 1 { add(suits.contains(.honor) ? .honitsu : .chinitsu) }
        if allKinds.allSatisfy({ yaochu.contains($0) }) && allKinds.contains(where: { $0 >= 27 }) && allKinds.contains(where: { $0 < 27 }) {
            add(.honroutou)
        }
        if it.form == "chiitoi" {
            add(.chiitoitsu)
            return ys
        }
        let seqs = it.groups.filter { $0.shape == .seq }.map(\.kind)
        let trips = it.groups.filter { $0.shape != .seq }.map(\.kind)
        let pair = it.pairKind ?? -1
        let pairIsValue = dragons.contains(pair) || pair == seatKind || pair == roundKind
        if menzen && seqs.count == 4 && !pairIsValue && it.wait == "ryanmen" { add(.pinfu) }
        if menzen {
            let peikou = Set(seqs).reduce(0) { sum, k in sum + seqs.filter { $0 == k }.count / 2 }
            if peikou >= 2 { add(.ryanpeikou) } else if peikou == 1 { add(.iipeikou) }
        }
        for k in trips {
            if k == 31 { add(.yakuhaiHaku) } else if k == 32 { add(.yakuhaiHatsu) } else if k == 33 { add(.yakuhaiChun) }
            if k == roundKind { add(.bakaze) }
            if k == seatKind { add(.jikaze) }
        }
        if (0..<7).contains(where: { n in seqs.contains(n) && seqs.contains(n + 9) && seqs.contains(n + 18) }) { add(.sanshoku) }
        if (0..<3).contains(where: { s in seqs.contains(s * 9) && seqs.contains(s * 9 + 3) && seqs.contains(s * 9 + 6) }) { add(.ittsu) }
        func hasYaochu(_ g: Group) -> Bool {
            g.shape == .seq ? (g.kind % 9 == 0 || g.kind % 9 == 6) : yaochu.contains(g.kind)
        }
        if !seqs.isEmpty && yaochu.contains(pair) && it.groups.allSatisfy(hasYaochu) {
            add(allKinds.contains(where: { $0 >= 27 }) ? .chanta : .junchan)
        }
        if trips.count == 4 { add(.toitoi) }
        if it.groups.filter({ $0.shape != .seq && !$0.opened }).count == 3 { add(.sanankou) }
        if (0..<9).contains(where: { n in trips.contains(n) && trips.contains(n + 9) && trips.contains(n + 18) }) { add(.sanshokuDoukou) }
        if it.groups.filter({ $0.shape == .kan }).count == 3 { add(.sankantsu) }
        if dragons.filter({ trips.contains($0) }).count == 2 && dragons.contains(pair) { add(.shousangen) }
        return ys
    }

    /// MJ-37 부(표준형). reference `_calc_fu`.
    static func calcFu(_ it: Interpretation, tsumo: Bool, menzen: Bool, pinfu: Bool, seatKind: Int, roundKind: Int) -> Int {
        if pinfu { return tsumo ? 20 : 30 }
        var fu = 20
        if menzen && !tsumo { fu += 10 }
        if tsumo { fu += 2 }
        if ["kanchan", "penchan", "tanki"].contains(it.wait) { fu += 2 }
        let pair = it.pairKind ?? -1
        if dragons.contains(pair) { fu += 2 }
        if pair == seatKind { fu += 2 }
        if pair == roundKind { fu += 2 }
        for g in it.groups where g.shape != .seq {
            var v = g.shape == .trip ? 2 : 8
            if MahjongTiles.yaochu.contains(g.kind) { v *= 2 }
            if !g.opened { v *= 2 }
            fu += v
        }
        let raw = fu
        fu = (fu + 9) / 10 * 10
        if !menzen && (raw == 20 || raw == 22) { fu = 30 }   // MJ-37-8 울음 핑후형
        return fu
    }
}
