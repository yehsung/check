// 원본: Sources/CheckCore/MahjongScoring.swift @ e4995a3a(역 · 부 · 점수 — MJ-22~MJ-42 · X-01 · X-02) — Android 판 8
//
// `MahjongScoring.evaluate` = SQL `mahjong_evaluate(jsonb ctx)` = reference `evaluate()`. 해석이 여럿이면 `_rank_key` 순서:
// 지불 총액 → 역만 역 해석 먼저(X-01) → 판 → 부 → 역 id 의 [MahjongYaku.order] 순번 사전순 → 대기 이름 순(X-02). 점수는 100 단위 올림.
// 형식 오류(14장 초과 · 같은 id 둘 · 모순 깃발) = SQL 22023([MahjongInputError]).
package com.yehsung.aingcheck.core.rules.mahjong

import kotlin.math.max

enum class MahjongYaku(val rawValue: String, val koreanName: String) {
    riichi("riichi", "리치"), doubleRiichi("double_riichi", "더블 리치"), ippatsu("ippatsu", "일발"), menzenTsumo("menzen_tsumo", "멘젠쯔모"),
    pinfu("pinfu", "핑후"), iipeikou("iipeikou", "이페코"), tanyao("tanyao", "탕야오"), yakuhaiHaku("yakuhai_haku", "역패 백"),
    yakuhaiHatsu("yakuhai_hatsu", "역패 발"), yakuhaiChun("yakuhai_chun", "역패 중"), bakaze("bakaze", "역패 장풍"), jikaze("jikaze", "역패 자풍"),
    chankan("chankan", "창깡"), rinshan("rinshan", "영상개화"), haitei("haitei", "해저모월"), houtei("houtei", "하저로어"),
    chiitoitsu("chiitoitsu", "치또이쯔"), sanshoku("sanshoku", "삼색동순"), ittsu("ittsu", "일기통관"), chanta("chanta", "찬타"),
    toitoi("toitoi", "또이또이"), sanankou("sanankou", "산안커"), sanshokuDoukou("sanshoku_doukou", "삼색동각"), sankantsu("sankantsu", "산깡쯔"),
    honroutou("honroutou", "혼노두"), shousangen("shousangen", "소삼원"), honitsu("honitsu", "혼일색"), junchan("junchan", "준찬타"),
    ryanpeikou("ryanpeikou", "량페코"), chinitsu("chinitsu", "청일색"), heavenly("heavenly", "천화"), earthly("earthly", "지화"),
    kokushi("kokushi", "국사무쌍"), kokushi13("kokushi_13", "국사무쌍 13면"), suuankou("suuankou", "사암각"), suuankouTanki("suuankou_tanki", "사암각 단기"),
    daisangen("daisangen", "대삼원"), shousuushii("shousuushii", "소사희"), daisuushii("daisuushii", "대사희"), tsuuiisou("tsuuiisou", "자일색"),
    ryuuiisou("ryuuiisou", "녹일색"), chinroutou("chinroutou", "청노두"), suukantsu("suukantsu", "사깡쯔"), chuuren("chuuren", "구련보등"),
    junseiChuuren("junsei_chuuren", "순정 구련보등");

    /** 역만 배수(reference YAKUMAN 둘째 칸). 일반 역은 0. */
    val yakumanMultiple: Int
        get() = when (this) {
            kokushi13, suuankouTanki, daisuushii, junseiChuuren -> 2
            heavenly, earthly, kokushi, suuankou, daisangen, shousuushii, tsuuiisou, ryuuiisou, chinroutou, suukantsu, chuuren -> 1
            else -> 0
        }

    companion object {
        fun of(raw: String): MahjongYaku? = entries.firstOrNull { it.rawValue == raw }

        /** = SQL `mahjong_yaku_order()` — 역만 먼저, 그다음 일반 역. 해석 고르기 5단(X-02)의 순번. */
        val order: List<MahjongYaku> = listOf(
            heavenly, earthly, kokushi, kokushi13, suuankou, suuankouTanki, daisangen, shousuushii, daisuushii,
            tsuuiisou, ryuuiisou, chinroutou, suukantsu, chuuren, junseiChuuren,
            riichi, doubleRiichi, ippatsu, menzenTsumo, pinfu, iipeikou, tanyao, yakuhaiHaku, yakuhaiHatsu,
            yakuhaiChun, bakaze, jikaze, chankan, rinshan, haitei, houtei, chiitoitsu, sanshoku, ittsu, chanta,
            toitoi, sanankou, sanshokuDoukou, sankantsu, honroutou, shousangen, honitsu, junchan, ryanpeikou, chinitsu,
        )
    }
}

/** 결과 yaku 의 한 칸 [id, 판]. 역만 역의 판 칸은 배수 × 13. */
data class MahjongYakuHan(val yaku: MahjongYaku, val han: Int)

/** 지불(본장 제외): 론 ron · 자 쯔모 fromDealer + fromChild · 친 쯔모 fromEach. */
data class MahjongPoints(val ron: Int? = null, val fromDealer: Int? = null, val fromChild: Int? = null, val fromEach: Int? = null)

/** 손 계산 입력(closed = 손 안의 패(화료패 제외, 13 − 3 × 부로 수) · win = 화료패 · 친 = seatWind == east). */
data class MahjongWinContext(
    val closed: List<MahjongTile>,
    val melds: List<MahjongMeld> = emptyList(),
    val win: MahjongTile,
    val tsumo: Boolean,
    val seatWind: MahjongWind = MahjongWind.east,
    val roundWind: MahjongWind = MahjongWind.east,
    val riichi: Boolean = false,
    val doubleRiichi: Boolean = false,
    val ippatsu: Boolean = false,
    val rinshan: Boolean = false,
    val chankan: Boolean = false,
    val haitei: Boolean = false,
    val houtei: Boolean = false,
    val heavenly: Boolean = false,
    val earthly: Boolean = false,
    val doraIndicators: List<MahjongTile> = emptyList(),
    val uraIndicators: List<MahjongTile> = emptyList(),
    val honba: Int = 0,
    val kyoutaku: Int = 0,
)

/** 손 계산 결과 = SQL `mahjong_evaluate` 결과. 화료 아님은 agari false + reason('not_complete' | 'no_yaku'). */
data class MahjongScore(
    val agari: Boolean,
    val reason: String? = null,
    val yaku: List<MahjongYakuHan> = emptyList(),
    val yakuman: Int = 0,
    val dora: Int = 0,
    val aka: Int = 0,
    val ura: Int = 0,
    val han: Int = 0,
    val fu: Int = 0,
    val limit: String = "",
    val base: Int = 0,
    val points: MahjongPoints = MahjongPoints(),
    val honbaBonus: Int = 0,
    val kyoutakuBonus: Int = 0,
    val total: Int = 0,
    val wait: String? = null,
    val form: String? = null,
)

/** 손 계산 입력 형식 오류 = SQL 22023. reason 예: tile_count · duplicate_tile · bad_meld · flags. */
data class MahjongInputError(val reason: String) : Exception(reason)

/** 결과 — 성공(화료 · 화료 아님) 또는 형식 오류(Swift `Result<MahjongScore, MahjongInputError>`). */
sealed interface MahjongEvaluation {
    data class Success(val score: MahjongScore) : MahjongEvaluation
    data class Failure(val error: MahjongInputError) : MahjongEvaluation
}

object MahjongScoring {
    /** 손 하나의 화료 판정 · 점수. 천화는 14장 중 가장 높은 해석의 화료패를 고른다(MJ-36). */
    fun evaluate(ctx: MahjongWinContext): MahjongEvaluation {
        validate(ctx)?.let { return MahjongEvaluation.Failure(it) }
        if (ctx.heavenly) {
            val tiles = ctx.closed + ctx.win
            var best: Candidate? = null
            for (i in tiles.indices) {
                val t = tiles[i]
                if (tiles.subList(0, i).any { it.kind == t.kind && it.isRed == t.isRed }) continue
                val c2 = ctx.copy(closed = tiles.subList(0, i) + tiles.subList(i + 1, tiles.size), win = t)
                val r = evaluateOne(c2)
                if (r is OneResult.Agari && (best == null || r.cand.ranksBefore(best))) best = r.cand
            }
            best?.let { return MahjongEvaluation.Success(finish(it, ctx)) }
        }
        return when (val r = evaluateOne(ctx)) {
            is OneResult.Agari -> MahjongEvaluation.Success(finish(r.cand, ctx))
            is OneResult.NotAgari -> MahjongEvaluation.Success(MahjongScore(agari = false, reason = r.reason))
        }
    }

    data class ScoreRow(val base: Int, val limit: String, val points: MahjongPoints, val total: Int)

    /** MJ-39 · MJ-40 점수표 한 칸(본장 제외). yakuman = 역만 배수. 절상만관 없음. */
    fun scoreOf(han: Int, fu: Int, dealer: Boolean, tsumo: Boolean, yakuman: Int = 0): ScoreRow {
        val (base, limit) = limitBase(han, fu, yakuman)
        val points = payments(base, dealer, tsumo)
        return ScoreRow(base, limit, points, total(points))
    }

    internal fun limitBase(han: Int, fu: Int, yakuman: Int): Pair<Int, String> {
        if (yakuman > 0) return 8000 * yakuman to "yakuman"
        if (han >= 13) return 8000 to "yakuman"
        if (han >= 11) return 6000 to "sanbaiman"
        if (han >= 8) return 4000 to "baiman"
        if (han >= 6) return 3000 to "haneman"
        if (han >= 5) return 2000 to "mangan"
        val b = fu * (1 shl max(han + 2, 0))
        return if (b > 2000) 2000 to "mangan" else b to ""
    }

    internal fun ceil100(x: Int): Int = if (x >= 0) (x + 99) / 100 * 100 else -((-x) / 100 * 100)

    internal fun payments(base: Int, dealer: Boolean, tsumo: Boolean): MahjongPoints {
        if (!tsumo) return MahjongPoints(ron = ceil100(base * (if (dealer) 6 else 4)))
        if (dealer) return MahjongPoints(fromEach = ceil100(base * 2))
        return MahjongPoints(fromDealer = ceil100(base * 2), fromChild = ceil100(base))
    }

    internal fun total(p: MahjongPoints): Int {
        p.ron?.let { return it }
        p.fromEach?.let { return it * 3 }
        return (p.fromDealer ?: 0) + 2 * (p.fromChild ?: 0)
    }

    // MARK: - 몸통

    internal enum class GroupShape { seq, trip, kan }

    internal data class Group(val shape: GroupShape, val kind: Int, val opened: Boolean)

    internal data class Interpretation(val form: String, val groups: List<Group>, val pairKind: Int?, val wait: String)

    internal class Candidate(
        val yaku: List<MahjongYakuHan>, val yakuman: Int, val han: Int, val fu: Int, val dora: Int, val aka: Int, val ura: Int,
        val form: String, val wait: String, val base: Int, val limit: String, val points: MahjongPoints, val totalBase: Int,
    ) {
        /** MJ-38 해석 고르기(작은 쪽이 고른 해석). */
        fun ranksBefore(other: Candidate): Boolean {
            if (totalBase != other.totalBase) return totalBase > other.totalBase
            if ((yakuman > 0) != (other.yakuman > 0)) return yakuman > 0
            if (han != other.han) return han > other.han
            if (fu != other.fu) return fu > other.fu
            val mine = yakuOrderKey
            val theirs = other.yakuOrderKey
            if (mine != theirs) {
                for (i in 0 until minOf(mine.size, theirs.size)) if (mine[i] != theirs[i]) return mine[i] < theirs[i]
                return mine.size < theirs.size
            }
            return (waitOrder.indexOf(wait).takeIf { it >= 0 } ?: 9) < (waitOrder.indexOf(other.wait).takeIf { it >= 0 } ?: 9)
        }

        val yakuOrderKey: List<Int> get() = yaku.map { orderIndex[it.yaku] ?: 99 }.sorted()
    }

    internal sealed interface OneResult {
        class Agari(val cand: Candidate) : OneResult
        class NotAgari(val reason: String) : OneResult
    }

    internal val waitOrder = listOf("ryanmen", "shanpon", "kanchan", "penchan", "tanki", "kokushi")
    internal val orderIndex: Map<MahjongYaku, Int> = MahjongYaku.order.withIndex().associate { it.value to it.index }
    internal val dragons = listOf(31, 32, 33)
    internal val terminals = listOf(0, 8, 9, 17, 18, 26)
    /** MJ-34 녹일색: 2·3·4·6·8삭 + 발. */
    internal val green = listOf(19, 20, 21, 23, 25, 32)

    internal fun finish(c: Candidate, ctx: MahjongWinContext): MahjongScore {
        val honbaBonus = 300 * ctx.honba
        val kyoutakuBonus = 1000 * ctx.kyoutaku
        return MahjongScore(
            agari = true, reason = null, yaku = c.yaku, yakuman = c.yakuman, dora = c.dora, aka = c.aka, ura = c.ura,
            han = c.han, fu = c.fu, limit = c.limit, base = c.base, points = c.points,
            honbaBonus = honbaBonus, kyoutakuBonus = kyoutakuBonus, total = c.totalBase + honbaBonus + kyoutakuBonus,
            wait = c.wait, form = c.form,
        )
    }

    /** 부로 하나 → 몸통. 모양이 틀리면 null. */
    internal fun meldGroup(meld: MahjongMeld): Group? {
        val ks = meld.tiles.map { it.kind }.sorted()
        return when (meld.type) {
            MahjongMeldType.chi -> {
                if (ks.size != 3 || ks[0] >= 27 || ks[1] != ks[0] + 1 || ks[2] != ks[0] + 2 || ks[0] / 9 != ks[2] / 9) null
                else Group(GroupShape.seq, ks[0], true)
            }
            MahjongMeldType.pon -> if (ks.size != 3 || ks.toSet().size != 1) null else Group(GroupShape.trip, ks[0], true)
            MahjongMeldType.minkan, MahjongMeldType.kakan, MahjongMeldType.ankan ->
                if (ks.size != 4 || ks.toSet().size != 1) null else Group(GroupShape.kan, ks[0], meld.type != MahjongMeldType.ankan)
        }
    }

    internal fun validate(ctx: MahjongWinContext): MahjongInputError? {
        val all = ctx.closed + ctx.win + ctx.melds.flatMap { it.tiles }
        if (all.map { it.id }.toSet().size != all.size) return MahjongInputError("duplicate_tile")
        if (ctx.melds.size > 4 || ctx.closed.size != 13 - 3 * ctx.melds.size) return MahjongInputError("tile_count")
        val groups = ctx.melds.map { meldGroup(it) ?: return MahjongInputError("bad_meld") }
        val menzen = groups.all { !it.opened }
        val dealer = ctx.seatWind == MahjongWind.east
        val hasKan = groups.any { it.shape == GroupShape.kan }
        val contradictions = listOf(
            ctx.doubleRiichi && !ctx.riichi,
            (ctx.riichi || ctx.ippatsu) && !menzen,
            ctx.ippatsu && !ctx.riichi,
            ctx.rinshan && (!ctx.tsumo || !hasKan),
            ctx.rinshan && (ctx.ippatsu || ctx.haitei),
            ctx.chankan && ctx.tsumo,
            ctx.haitei && !ctx.tsumo,
            ctx.houtei && (ctx.tsumo || ctx.chankan),
            ctx.heavenly && (!dealer || !ctx.tsumo || ctx.melds.isNotEmpty()),
            ctx.earthly && (dealer || !ctx.tsumo || ctx.melds.isNotEmpty()),
        )
        return if (contradictions.any { it }) MahjongInputError("flags") else null
    }

    internal fun evaluateOne(ctx: MahjongWinContext): OneResult {
        val meldGroups = ctx.melds.mapNotNull(::meldGroup)
        val menzen = meldGroups.all { !it.opened }
        val noMelds = meldGroups.isEmpty()
        val winKind = ctx.win.kind
        val c13 = MahjongTiles.counts34(ctx.closed)
        val c14 = c13.copyOf().also { it[winKind] += 1 }
        val call14 = c14.copyOf()
        for (g in meldGroups) {
            if (g.shape == GroupShape.seq) for (j in 0 until 3) call14[g.kind + j] += 1 else call14[g.kind] += 3
        }
        val interps = interpretations(c14, meldGroups, winKind, ctx.tsumo, noMelds)
        if (interps.isEmpty()) return OneResult.NotAgari("not_complete")
        val allTiles = ctx.closed + ctx.win + ctx.melds.flatMap { it.tiles }
        val allKinds = allTiles.map { it.kind }
        fun countDora(indicators: List<MahjongTile>): Int = indicators.sumOf { ind ->
            val d = MahjongTiles.doraKind(ind.kind)
            allKinds.count { it == d }
        }
        val dora = countDora(ctx.doraIndicators)
        val aka = allTiles.count { it.isRed }
        val ura = if (ctx.riichi) countDora(ctx.uraIndicators) else 0
        val dealer = ctx.seatWind == MahjongWind.east
        val seatKind = 27 + windIndex(ctx.seatWind)
        val roundKind = 27 + windIndex(ctx.roundWind)
        var best: Candidate? = null
        for (interp in interps) {
            val ym = yakumanChecks(call14, interp, ctx, c13, noMelds)
            val cand: Candidate
            if (ym.isNotEmpty()) {
                val mult = ym.sumOf { it.yakumanMultiple }
                val yaku = ym.sortedBy { orderIndex[it] ?: 0 }.map { MahjongYakuHan(it, it.yakumanMultiple * 13) }
                val (base, limit) = limitBase(0, 0, mult)
                val points = payments(base, dealer, ctx.tsumo)
                cand = Candidate(yaku, mult, 13 * mult, 0, 0, 0, 0, interp.form, interp.wait, base, limit, points, total(points))
            } else {
                val ys = normalYaku(call14, interp, ctx, menzen, seatKind, roundKind)
                val yhan = ys.sumOf { it.han }
                if (yhan == 0) continue
                val fu = if (interp.form == "chiitoi") 25 else calcFu(interp, ctx.tsumo, menzen, ys.any { it.yaku == MahjongYaku.pinfu }, seatKind, roundKind)
                val han = yhan + dora + aka + ura
                val (base, limit) = limitBase(han, fu, 0)
                val points = payments(base, dealer, ctx.tsumo)
                cand = Candidate(ys.sortedBy { orderIndex[it.yaku] ?: 0 }, 0, han, fu, dora, aka, ura, interp.form, interp.wait, base, limit, points, total(points))
            }
            val b = best
            if (b == null || cand.ranksBefore(b)) best = cand
        }
        val b = best ?: return OneResult.NotAgari("no_yaku")
        return OneResult.Agari(b)
    }

    internal fun windIndex(w: MahjongWind): Int = when (w) {
        MahjongWind.east -> 0
        MahjongWind.south -> 1
        MahjongWind.west -> 2
        MahjongWind.north -> 3
    }

    internal enum class PartShape { pair, seq, trip }

    internal data class Part(val shape: PartShape, val kind: Int)

    internal fun interpretations(c14: IntArray, meldGroups: List<Group>, winKind: Int, tsumo: Boolean, noMelds: Boolean): List<Interpretation> {
        val out = mutableListOf<Interpretation>()
        if (noMelds && MahjongHand.isKokushi(c14)) out += Interpretation("kokushi", emptyList(), null, "kokushi")
        if (noMelds && MahjongHand.isChiitoi(c14)) out += Interpretation("chiitoi", emptyList(), winKind, "tanki")
        for (d in standardDecompositions(c14, meldGroups.size)) {
            val pair = d.firstOrNull { it.shape == PartShape.pair }?.kind ?: continue
            val body = d.filter { it.shape != PartShape.pair }
            data class Place(val shape: PartShape, val kind: Int, val offset: Int)
            val places = mutableListOf<Place>()
            for (part in d) {
                when {
                    part.shape == PartShape.pair && part.kind == winKind -> places += Place(PartShape.pair, part.kind, -1)
                    part.shape == PartShape.trip && part.kind == winKind -> places += Place(PartShape.trip, part.kind, -1)
                    part.shape == PartShape.seq && part.kind <= winKind && winKind <= part.kind + 2 -> places += Place(PartShape.seq, part.kind, winKind - part.kind)
                    else -> Unit
                }
            }
            val seen = mutableListOf<Place>()
            for (place in places) {
                if (place in seen) continue
                seen += place
                val groups = mutableListOf<Group>()
                var used = false
                for (part in body) {
                    var opened = false
                    if (!used && part.shape == PartShape.trip && place.shape == PartShape.trip && part.kind == place.kind && !tsumo) {
                        opened = true
                        used = true
                    }
                    groups += Group(if (part.shape == PartShape.seq) GroupShape.seq else GroupShape.trip, part.kind, opened)
                }
                groups += meldGroups
                out += Interpretation("standard", groups, pair, waitName(place.shape, place.kind, winKind))
            }
        }
        return out
    }

    /** 표준형 분해 전부(겹침 없이). */
    internal fun standardDecompositions(counts: IntArray, melds: Int): List<List<Part>> {
        val c = counts.copyOf()
        val out = mutableListOf<List<Part>>()
        val seen = mutableSetOf<List<Part>>()
        val path = mutableListOf<Part>()
        fun walk(need: Int, havePair: Boolean, start: Int) {
            var i = start
            while (i < 34 && c[i] == 0) i += 1
            if (i == 34) {
                if (need == 0 && havePair) {
                    val key = path.sortedWith(compareBy<Part>({ it.shape.ordinal }, { it.kind }))
                    if (seen.add(key)) out += key
                }
                return
            }
            if (!havePair && c[i] >= 2) {
                c[i] -= 2; path += Part(PartShape.pair, i)
                walk(need, true, i)
                path.removeAt(path.size - 1); c[i] += 2
            }
            if (need > 0 && c[i] >= 3) {
                c[i] -= 3; path += Part(PartShape.trip, i)
                walk(need - 1, havePair, i)
                path.removeAt(path.size - 1); c[i] += 3
            }
            if (need > 0 && i < 27 && i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0) {
                c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1; path += Part(PartShape.seq, i)
                walk(need - 1, havePair, i)
                path.removeAt(path.size - 1); c[i] += 1; c[i + 1] += 1; c[i + 2] += 1
            }
        }
        if (melds in 0..4) walk(4 - melds, false, 0)
        return out
    }

    internal fun waitName(shape: PartShape, k: Int, winKind: Int): String = when (shape) {
        PartShape.pair -> "tanki"
        PartShape.trip -> "shanpon"
        PartShape.seq -> when {
            winKind == k + 1 -> "kanchan"
            winKind == k -> if (k % 9 + 1 == 7) "penchan" else "ryanmen"
            else -> if (winKind % 9 + 1 == 3) "penchan" else "ryanmen"
        }
    }

    internal fun yakumanChecks(c14: IntArray, it: Interpretation, ctx: MahjongWinContext, c13: IntArray, noMelds: Boolean): List<MahjongYaku> {
        val ym = mutableListOf<MahjongYaku>()
        val allKinds = (0 until 34).filter { c14[it] > 0 }
        if (ctx.heavenly) ym += MahjongYaku.heavenly
        if (ctx.earthly) ym += MahjongYaku.earthly
        if (it.form == "kokushi") ym += if (MahjongTiles.yaochu.all { k -> c13[k] == 1 }) MahjongYaku.kokushi13 else MahjongYaku.kokushi
        if (it.form == "standard") {
            val conceal = it.groups.count { g -> g.shape != GroupShape.seq && !g.opened }
            if (conceal == 4) ym += if (it.wait == "tanki") MahjongYaku.suuankouTanki else MahjongYaku.suuankou
            val trips = it.groups.filter { g -> g.shape != GroupShape.seq }.map { g -> g.kind }
            if (dragons.all { d -> d in trips }) ym += MahjongYaku.daisangen
            val windTrips = trips.filter { k -> k in MahjongTiles.winds }
            if (windTrips.size == 4) {
                ym += MahjongYaku.daisuushii
            } else if (windTrips.size == 3 && it.pairKind != null && it.pairKind in MahjongTiles.winds) {
                ym += MahjongYaku.shousuushii
            }
            if (it.groups.count { g -> g.shape == GroupShape.kan } == 4) ym += MahjongYaku.suukantsu
        }
        if (it.form == "standard" || it.form == "chiitoi") {
            if (allKinds.all { k -> k >= 27 }) ym += MahjongYaku.tsuuiisou
            if (allKinds.all { k -> k in terminals }) ym += MahjongYaku.chinroutou
        }
        if (allKinds.all { k -> k in green }) ym += MahjongYaku.ryuuiisou
        if (noMelds && it.form == "standard") {
            val suits = allKinds.map { k -> MahjongSuit.of(k) }.toSet()
            if (suits.size == 1) {
                val suit = suits.first()
                if (suit != MahjongSuit.honor) {
                    val s = suit.ordinal
                    val v = (0 until 9).map { i -> c14[s * 9 + i] }
                    if (v[0] >= 3 && v[8] >= 3 && (1 until 8).all { i -> v[i] >= 1 }) {
                        val w13 = (0 until 9).map { i -> c13[s * 9 + i] }
                        ym += if (w13 == listOf(3, 1, 1, 1, 1, 1, 1, 1, 3)) MahjongYaku.junseiChuuren else MahjongYaku.chuuren
                    }
                }
            }
        }
        return ym
    }

    /** 일반 역의 (멘젠 판, 울었을 때 판 | null = 멘젠만). */
    internal fun hanValue(y: MahjongYaku): Pair<Int, Int?> = when (y) {
        MahjongYaku.riichi, MahjongYaku.ippatsu, MahjongYaku.menzenTsumo, MahjongYaku.pinfu, MahjongYaku.iipeikou -> 1 to null
        MahjongYaku.doubleRiichi, MahjongYaku.chiitoitsu -> 2 to null
        MahjongYaku.tanyao, MahjongYaku.yakuhaiHaku, MahjongYaku.yakuhaiHatsu, MahjongYaku.yakuhaiChun, MahjongYaku.bakaze, MahjongYaku.jikaze,
        MahjongYaku.chankan, MahjongYaku.rinshan, MahjongYaku.haitei, MahjongYaku.houtei -> 1 to 1
        MahjongYaku.sanshoku, MahjongYaku.ittsu, MahjongYaku.chanta -> 2 to 1
        MahjongYaku.toitoi, MahjongYaku.sanankou, MahjongYaku.sanshokuDoukou, MahjongYaku.sankantsu, MahjongYaku.honroutou, MahjongYaku.shousangen -> 2 to 2
        MahjongYaku.honitsu, MahjongYaku.junchan -> 3 to 2
        MahjongYaku.ryanpeikou -> 3 to null
        MahjongYaku.chinitsu -> 6 to 5
        else -> 0 to null
    }

    internal fun normalYaku(c14: IntArray, it: Interpretation, ctx: MahjongWinContext, menzen: Boolean, seatKind: Int, roundKind: Int): List<MahjongYakuHan> {
        val ys = mutableListOf<MahjongYakuHan>()
        fun add(y: MahjongYaku) {
            val (closed, open) = hanValue(y)
            val h = if (menzen) closed else open ?: return
            ys += MahjongYakuHan(y, h)
        }
        val allKinds = (0 until 34).filter { c14[it] > 0 }
        val yaochu = MahjongTiles.yaochu
        if (ctx.riichi) {
            add(if (ctx.doubleRiichi) MahjongYaku.doubleRiichi else MahjongYaku.riichi)
            if (ctx.ippatsu) add(MahjongYaku.ippatsu)
        }
        if (menzen && ctx.tsumo) add(MahjongYaku.menzenTsumo)
        if (ctx.chankan) add(MahjongYaku.chankan)
        if (ctx.rinshan) add(MahjongYaku.rinshan)
        if (ctx.haitei) add(MahjongYaku.haitei)
        if (ctx.houtei) add(MahjongYaku.houtei)
        if (allKinds.all { k -> k !in yaochu }) add(MahjongYaku.tanyao)
        val suits = allKinds.map { k -> MahjongSuit.of(k) }.toSet()
        if ((suits - MahjongSuit.honor).size == 1) add(if (MahjongSuit.honor in suits) MahjongYaku.honitsu else MahjongYaku.chinitsu)
        if (allKinds.all { k -> k in yaochu } && allKinds.any { k -> k >= 27 } && allKinds.any { k -> k < 27 }) add(MahjongYaku.honroutou)
        if (it.form == "chiitoi") {
            add(MahjongYaku.chiitoitsu)
            return ys
        }
        val seqs = it.groups.filter { g -> g.shape == GroupShape.seq }.map { g -> g.kind }
        val trips = it.groups.filter { g -> g.shape != GroupShape.seq }.map { g -> g.kind }
        val pair = it.pairKind ?: -1
        val pairIsValue = pair in dragons || pair == seatKind || pair == roundKind
        if (menzen && seqs.size == 4 && !pairIsValue && it.wait == "ryanmen") add(MahjongYaku.pinfu)
        if (menzen) {
            val peikou = seqs.toSet().sumOf { k -> seqs.count { s -> s == k } / 2 }
            if (peikou >= 2) add(MahjongYaku.ryanpeikou) else if (peikou == 1) add(MahjongYaku.iipeikou)
        }
        for (k in trips) {
            if (k == 31) add(MahjongYaku.yakuhaiHaku) else if (k == 32) add(MahjongYaku.yakuhaiHatsu) else if (k == 33) add(MahjongYaku.yakuhaiChun)
            if (k == roundKind) add(MahjongYaku.bakaze)
            if (k == seatKind) add(MahjongYaku.jikaze)
        }
        if ((0 until 7).any { n -> n in seqs && n + 9 in seqs && n + 18 in seqs }) add(MahjongYaku.sanshoku)
        if ((0 until 3).any { s -> s * 9 in seqs && s * 9 + 3 in seqs && s * 9 + 6 in seqs }) add(MahjongYaku.ittsu)
        fun hasYaochu(g: Group): Boolean = if (g.shape == GroupShape.seq) (g.kind % 9 == 0 || g.kind % 9 == 6) else g.kind in yaochu
        if (seqs.isNotEmpty() && pair in yaochu && it.groups.all(::hasYaochu)) add(if (allKinds.any { k -> k >= 27 }) MahjongYaku.chanta else MahjongYaku.junchan)
        if (trips.size == 4) add(MahjongYaku.toitoi)
        if (it.groups.count { g -> g.shape != GroupShape.seq && !g.opened } == 3) add(MahjongYaku.sanankou)
        if ((0 until 9).any { n -> n in trips && n + 9 in trips && n + 18 in trips }) add(MahjongYaku.sanshokuDoukou)
        if (it.groups.count { g -> g.shape == GroupShape.kan } == 3) add(MahjongYaku.sankantsu)
        if (dragons.count { d -> d in trips } == 2 && pair in dragons) add(MahjongYaku.shousangen)
        return ys
    }

    /** MJ-37 부(표준형). */
    internal fun calcFu(it: Interpretation, tsumo: Boolean, menzen: Boolean, pinfu: Boolean, seatKind: Int, roundKind: Int): Int {
        if (pinfu) return if (tsumo) 20 else 30
        var fu = 20
        if (menzen && !tsumo) fu += 10
        if (tsumo) fu += 2
        if (it.wait in listOf("kanchan", "penchan", "tanki")) fu += 2
        val pair = it.pairKind ?: -1
        if (pair in dragons) fu += 2
        if (pair == seatKind) fu += 2
        if (pair == roundKind) fu += 2
        for (g in it.groups) {
            if (g.shape == GroupShape.seq) continue
            var v = if (g.shape == GroupShape.trip) 2 else 8
            if (g.kind in MahjongTiles.yaochu) v *= 2
            if (!g.opened) v *= 2
            fu += v
        }
        val raw = fu
        fu = (fu + 9) / 10 * 10
        if (!menzen && (raw == 20 || raw == 22)) fu = 30
        return fu
    }
}
