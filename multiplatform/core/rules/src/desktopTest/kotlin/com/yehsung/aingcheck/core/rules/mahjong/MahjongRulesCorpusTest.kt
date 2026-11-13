// 원본: Tests/checkTests/MahjongRulesCorpusTests.swift · MahjongScoringCorpusTests.swift(settle_win) · MahjongHandTests.swift · MahjongXvalTests.swift @ e4995a3a — Android 판 8
// 아잉 마작 판정(후리텐 · 울기 · 쿠이카에 · 리치 · 리치 뒤 암깡 · 도라 · 황패 · 도중 유국 · 국 끝 · 등수 · 화료 정산 · 꼴)을 코퍼스와 맞춘다 — id 로.
package com.yehsung.aingcheck.core.rules.mahjong

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class MahjongRulesCorpusTest {
    private fun run(type: String, count: Int, body: (MahjongCorpus.Case) -> JsonElement?): List<String> {
        val cases = MahjongCorpus.cases(type)
        val failures = if (cases.size == count) mutableListOf() else mutableListOf("$type: ${cases.size}건 ≠ $count")
        for (c in cases) {
            val got = body(c)
            if (got == null) { failures += "${c.id}: 입력을 못 읽음"; continue }
            val d = MahjongCorpus.diffs(c.expected, got)
            if (d.isNotEmpty()) failures += "${c.id}: " + d.joinToString(" | ")
        }
        return failures
    }

    private fun n(x: Int) = JsonPrimitive(x)
    private fun s(x: String) = JsonPrimitive(x)
    private fun b(x: Boolean) = JsonPrimitive(x)
    private fun obj(vararg pairs: Pair<String, JsonElement>) = JsonObject(mapOf(*pairs))
    private fun JsonElement?.items(): List<JsonElement> = (this as? JsonArray)?.toList() ?: emptyList()
    private fun JsonElement.string(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonElement.int(): Int? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.intOrNull
    private fun JsonElement.bool(): Boolean? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.booleanOrNull

    private fun tilesLoose(texts: List<String>): List<List<MahjongTile>>? =
        MahjongCorpus.tiles(texts) ?: texts.map { MahjongTiles.parse(it) ?: return null }

    private fun tokens(kinds: List<Int>) = JsonArray(kinds.map { s(MahjongTiles.token(it)) })

    private fun assertNoFailures(failures: List<String>) = assertTrue(failures.isEmpty(), failures.joinToString("\n"))

    @Test
    fun furiten() = assertNoFailures(run("furiten", 8) { c ->
        var hand = c.input.str("closed") ?: ""
        val melds = c.input.int("n_melds") ?: 0
        var f = MahjongFuriten()
        val log = mutableListOf<JsonElement>()
        fun waits() = MahjongHand.waits(MahjongCorpus.counts(hand), melds)
        for (event in c.input["events"].items()) {
            val parts = event.items()
            val op = parts.firstOrNull()?.string() ?: return@run null
            val arg = parts.getOrNull(1)?.string() ?: ""
            when (op) {
                "discard" -> f = f.ownDiscard(MahjongCorpus.kinds(arg).firstOrNull() ?: -1)
                "riichi" -> f = f.declareRiichi()
                "draw" -> f = f.drawLive()
                "pass" -> if ((MahjongCorpus.kinds(arg).firstOrNull() ?: -1) in waits()) f = f.missed()
                "set_hand" -> hand = arg
                "call" -> Unit
                "check" -> {
                    val w = waits()
                    val ok = (MahjongCorpus.kinds(arg).firstOrNull() ?: -1) in w && f.canRon(w)
                    log += obj("tile" to s(arg), "can_ron" to b(ok), "furiten" to JsonArray(f.kinds(w).map { s(it.rawValue) }))
                }
                else -> return@run null
            }
        }
        obj("checks" to JsonArray(log))
    })

    private fun claimKind(x: String) = if (x == "kan") MahjongClaimKind.minkan else MahjongClaimKind.of(x)
    private fun claimAnswer(x: String) = if (x == "kan") MahjongClaimAnswer.minkan else MahjongClaimAnswer.of(x)

    @Test
    fun claim() = assertNoFailures(run("claim", 11) { c ->
        val discarder = c.input.int("discarder") ?: return@run null
        val eligible = mutableMapOf<Int, List<MahjongClaimKind>>()
        for ((k, v) in c.input.obj("eligible") ?: JsonObject(emptyMap())) {
            eligible[k.toIntOrNull() ?: return@run null] = v.items().mapNotNull { it.string()?.let(::claimKind) }
        }
        val answers = mutableMapOf<Int, MahjongClaimAnswer>()
        for ((k, v) in c.input.obj("answers") ?: JsonObject(emptyMap())) {
            val seat = k.toIntOrNull() ?: return@run null
            answers[seat] = v.string()?.let(::claimAnswer) ?: return@run null
        }
        when (val r = MahjongRules.resolveClaims(discarder, eligible, answers)) {
            MahjongClaimResolution.Wait -> obj("status" to s("wait"))
            MahjongClaimResolution.None -> obj("status" to s("done"), "action" to s("none"), "seats" to JsonArray(emptyList()))
            is MahjongClaimResolution.Ron -> obj("status" to s("done"), "action" to s("ron"), "seats" to JsonArray(r.seats.map(::n)))
            is MahjongClaimResolution.Claim -> obj(
                "status" to s("done"), "action" to s(if (r.kind == MahjongClaimKind.minkan) "kan" else r.kind.rawValue), "seats" to JsonArray(listOf(n(r.seat))),
            )
        }
    })

    @Test
    fun kuikae() = assertNoFailures(run("kuikae", 8) { c ->
        val call = c.input.str("call")?.let(MahjongMeldType::of) ?: return@run null
        val calledText = c.input.str("called") ?: return@run null
        val fromText = c.input.str("from_hand") ?: return@run null
        val texts = listOfNotNull(calledText, fromText, c.input.str("closed_after"))
        val g = tilesLoose(texts) ?: return@run null
        val called = g[0].firstOrNull() ?: return@run null
        val out = mutableMapOf<String, JsonElement>("forbidden" to s(MahjongTiles.text(MahjongRules.kuikaeForbidden(call, called, g[1]))))
        if (texts.size == 3) out["allowed"] = b(MahjongRules.callAllowed(call, called, g[1], g[2]))
        JsonObject(out)
    })

    @Test
    fun riichi() = assertNoFailures(run("riichi", 7) { c ->
        val tiles = c.input.str("closed14")?.let(MahjongTiles::parse) ?: return@run null
        val score = c.input.int("score") ?: return@run null
        val live = c.input.int("live_left") ?: return@run null
        val kinds = MahjongRules.riichiDiscards(tiles, c.input.int("n_ankan") ?: 0, score, live, c.input.bool("menzen") ?: true, c.input.bool("already") ?: false)
        obj("discards" to tokens(kinds))
    })

    @Test
    fun riichiAnkan() = assertNoFailures(run("riichi_ankan", 3) { c ->
        val closedText = c.input.str("closed13") ?: return@run null
        val drawnText = c.input.str("drawn") ?: return@run null
        val g = MahjongCorpus.tiles(listOf(closedText, drawnText)) ?: return@run null
        val drawn = g[1].firstOrNull() ?: return@run null
        val kan = c.input.str("kan")?.let { MahjongCorpus.kinds(it).firstOrNull() }
        obj("allowed" to b(MahjongRules.riichiAnkanOK(g[0], drawn, kan, c.input.int("n_melds") ?: 0)))
    })

    @Test
    fun dora() = assertNoFailures(run("dora", 8) { c ->
        val out = mutableMapOf<String, JsonElement>()
        val indicators = MahjongTiles.parse(c.input.str("indicators") ?: "") ?: emptyList()
        if (c.input.containsKey("indicators")) out["dora_kinds"] = tokens(indicators.map { MahjongTiles.doraKind(it.kind) })
        c.input.str("tiles")?.let { text ->
            val tiles = MahjongTiles.parse(text) ?: emptyList()
            out["count"] = n(indicators.sumOf { ind -> tiles.count { it.kind == MahjongTiles.doraKind(ind.kind) } })
            out["aka"] = n(tiles.count { it.isRed })
        }
        (c.input["events"] as? JsonArray)?.let { events ->
            var timer = MahjongDoraTimer()
            val seen = mutableListOf<JsonElement>()
            for (e in events) {
                val parts = e.items()
                when (parts.firstOrNull()?.string()) {
                    "kan" -> timer = timer.kan(parts.getOrNull(1)?.string()?.let(MahjongMeldType::of) ?: return@run null)
                    "discard" -> timer = timer.discard()
                    "look" -> seen += n(timer.open)
                    else -> return@run null
                }
            }
            out["open_counts"] = JsonArray(seen)
        }
        JsonObject(out)
    })

    @Test
    fun exhaustive() = assertNoFailures(run("exhaustive", 9) { c ->
        val dealer = c.input.int("dealer") ?: return@run null
        val tenpai = (c.input["tenpai"] as? JsonArray)?.mapNotNull { it.bool() } ?: return@run null
        val nagashi = (c.input["nagashi"] as? JsonArray)?.mapNotNull { it.bool() } ?: listOf(false, false, false, false)
        val r = MahjongRules.settleExhaustive(dealer, tenpai, nagashi)
        val out = mutableMapOf<String, JsonElement>("deltas" to JsonArray(r.deltas.map(::n)), "renchan" to b(r.renchan))
        (c.input["discards"] as? JsonArray)?.let { discards ->
            out["nagashi_ok"] = JsonArray(discards.map { d ->
                d as JsonObject
                b(MahjongRules.nagashiOK(MahjongCorpus.kinds(d.str("discards") ?: ""), d.bool("called_away") ?: false))
            })
        }
        JsonObject(out)
    })

    @Test
    fun abortive() = assertNoFailures(run("abortive", 10) { c ->
        val ok = when (c.input.str("check")) {
            "kyuushu" -> MahjongRules.kyuushuOK(MahjongTiles.parse(c.input.str("hand14") ?: "") ?: emptyList(), c.input.bool("first_turn_uninterrupted") ?: true)
            "suufon" -> MahjongRules.suufonRenda(MahjongCorpus.kinds(c.input.str("first_discards") ?: ""), c.input.bool("any_call") ?: false)
            "suukaikan" -> MahjongRules.suukaikan(c.input["kan_seats"].items().mapNotNull { it.int() })
            "suucha_riichi" -> c.input.int("riichi_established") == 4
            else -> return@run null
        }
        obj("ok" to b(ok))
    })

    @Test
    fun advance() = assertNoFailures(run("advance", 22) { c ->
        val i = c.input
        val format = i.str("length")?.let(MahjongFormat::of) ?: return@run null
        val round = i.int("round") ?: return@run null
        val hand = i.int("hand") ?: return@run null
        val honba = i.int("honba") ?: return@run null
        val scores = (i["scores"] as? JsonArray)?.mapNotNull { it.int() } ?: return@run null
        val outcome = i.str("outcome")?.let(MahjongHandOutcome::of) ?: return@run null
        val r = MahjongRules.advance(format, round, hand, honba, scores, outcome)
        val out = mutableMapOf<String, JsonElement>("end" to b(r.end))
        r.reason?.let { out["reason"] = s(it) }
        r.next?.let { out["next"] = obj("round" to n(it.round), "hand" to n(it.hand), "honba" to n(it.honba)) }
        JsonObject(out)
    })

    @Test
    fun rank() = assertNoFailures(run("rank", 3) { c ->
        val scores = (c.input["scores"] as? JsonArray)?.mapNotNull { it.int() } ?: return@run null
        val r = MahjongRules.finalResult(scores, c.input.int("kyoutaku") ?: 0)
        obj("order" to JsonArray(r.order.map(::n)), "ranks" to JsonArray(r.ranks.map(::n)), "final_scores" to JsonArray(r.finalScores.map(::n)))
    })

    private fun pao(v: JsonElement?): MahjongPao? {
        val o = v as? JsonObject ?: return null
        val seat = o.int("seat") ?: return null
        val yaku = o.str("yaku")?.let(MahjongYaku::of) ?: return null
        return MahjongPao(seat, yaku)
    }

    private fun scoreOf(hand: JsonElement?): MahjongScore? =
        ((hand as? JsonObject)?.let(MahjongCorpus::evaluate)?.second as? MahjongEvaluation.Success)?.score

    @Test
    fun settleWin() = assertNoFailures(run("settle_win", 9) { c ->
        val i = c.input
        val dealer = i.int("dealer") ?: 0
        val honba = i.int("honba") ?: 0
        val kyoutaku = i.int("kyoutaku") ?: 0
        val winners = i["winners"] as? JsonArray
        if (winners != null) {
            val wins = winners.mapNotNull { w ->
                w as JsonObject
                val seat = w.int("seat") ?: return@mapNotNull null
                val score = scoreOf(w["hand"]) ?: return@mapNotNull null
                MahjongRonWin(seat, score, pao(w["pao"]))
            }
            val discarder = i.int("discarder")
            if (wins.size != winners.size || discarder == null) return@run null
            val r = MahjongRules.settleRonMulti(discarder, dealer, wins, honba, kyoutaku)
            obj("deltas" to JsonArray(r.deltas.map(::n)), "bonus_to" to n(r.bonusTo), "renchan" to b(r.renchan))
        } else {
            val winner = i.int("winner") ?: return@run null
            val score = scoreOf(i["hand"]) ?: return@run null
            val d = MahjongRules.settleWin(winner, dealer, score, i.int("discarder"), honba, kyoutaku, pao(i["pao"]), true)
            obj("deltas" to JsonArray(d.map(::n)))
        }
    })

    @Test
    fun shape() = assertNoFailures(run("shape", 11) { c ->
        if (MahjongCorpus.kindList(c.input.str("closed") ?: "x") == null) return@run null
        val melds = c.input.int("n_melds") ?: 0
        val counts = MahjongCorpus.counts(c.input.str("closed") ?: "")
        val waits = MahjongHand.waits(counts, melds)
        obj("shanten" to n(MahjongHand.shanten(counts, melds)), "waits" to s(MahjongTiles.text(waits)), "tenpai" to b(waits.isNotEmpty()))
    })

    @Test
    fun quadRulesAndCompleteShapes() {
        for ((id, shanten, waits) in listOf(Triple("T-QUAD-NOTEN", 1, ""), Triple("T-DOUBLE-QUAD", null, ""), Triple("T-QUAD-OK", 0, "4m"))) {
            val c = assertNotNull(MahjongCorpus.byID(id), id)
            val counts = MahjongCorpus.counts(c.input.str("closed") ?: "")
            val melds = c.input.int("n_melds") ?: 0
            assertEquals(waits, MahjongTiles.text(MahjongHand.waits(counts, melds)), id)
            if (shanten != null) assertEquals(shanten, MahjongHand.shanten(counts, melds), id)
        }
        assertEquals(listOf(8), MahjongHand.waits(MahjongCorpus.counts("111m9m234p567p789p"), 0))
        val c = MahjongCorpus::counts
        assertTrue(MahjongHand.isComplete(c("123m456p789s11z222z"), 0))
        assertTrue(MahjongHand.isComplete(c("1133557799m1122z"), 0))
        assertTrue(!MahjongHand.isComplete(c("1111m335577m1122z"), 0))
        assertTrue(MahjongHand.isComplete(c("19m19p19s12345677z"), 0))
        assertTrue(!MahjongHand.isComplete(c("19m19p19s12345677z"), 1))
        assertTrue(MahjongHand.isComplete(c("123m11z"), 3))
        assertTrue(!MahjongHand.isComplete(c("123m11z"), 2))
        assertEquals(-1, MahjongHand.shanten(c("123m456p789s11z222z"), 0))
        assertEquals(-1, MahjongHand.shanten(c("1133557799m1122z"), 0))
        assertEquals(0, MahjongHand.shanten(c("19m19p19s1234567z"), 0))
        assertEquals(-1, MahjongHand.shanten(c("123m11z"), 3))
        assertEquals(0, MahjongHand.shanten(c("13m11z"), 3))
        assertEquals(8, MahjongHand.shanten(IntArray(33), 0))
        assertEquals(1, MahjongHand.shanten(c("99m3444567p2245s"), 0), "색별 파레토 반례")
        assertTrue(MahjongHand.waits(c("99m3444567p2245s"), 0).isEmpty())
    }

    // MARK: - 무작위 대조(xval-hands.json — reference.py 결과)

    private val compareKeys = setOf("agari", "reason", "yaku", "yakuman", "han", "fu", "limit", "base", "points", "honba_bonus",
        "kyoutaku_bonus", "total", "dora", "aka", "ura", "wait", "form")

    private fun ids(v: JsonElement?): List<MahjongTile> = v.items().mapNotNull { e -> e.int()?.let { MahjongTile.of(it) } }

    private fun xvalContext(i: JsonObject): MahjongWinContext? {
        val win = i.int("win")?.let { MahjongTile.of(it) } ?: return null
        val melds = i["melds"].items().map { m ->
            m as JsonObject
            MahjongMeld(m.str("type")?.let(MahjongMeldType::of) ?: return null, ids(m["tiles"]), null, null)
        }
        fun flag(key: String) = i.bool(key) ?: false
        return MahjongWinContext(
            closed = ids(i["closed"]), melds = melds, win = win, tsumo = flag("tsumo"),
            seatWind = MahjongCorpus.wind(i["seat_wind"]), roundWind = MahjongCorpus.wind(i["round_wind"]),
            riichi = flag("riichi"), doubleRiichi = flag("double_riichi"), ippatsu = flag("ippatsu"), rinshan = flag("rinshan"),
            chankan = flag("chankan"), haitei = flag("haitei"), houtei = flag("houtei"),
            heavenly = flag(MahjongYaku.heavenly.rawValue), earthly = flag(MahjongYaku.earthly.rawValue),
            doraIndicators = ids(i["dora"]), uraIndicators = ids(i["ura"]),
            honba = i.int("honba") ?: 0, kyoutaku = i.int("kyoutaku") ?: 0,
        )
    }

    @Test
    fun xvalGate() {
        assertEquals("a5776f3bda850cf1ef4bcb59dc500fb5", MahjongCorpus.md5("xval-hands.json"))
        val gate = MahjongCorpus.load("xval-hands.json") as JsonObject
        assertEquals("mahjong-xval/1", gate.str("schema"))
        val failures = mutableListOf<String>()
        var agari = 0
        val wins = gate["win"].items()
        assertEquals(300, wins.size)
        for (r in wins) {
            r as JsonObject
            val id = r.str("id") ?: "?"
            val ctx = (r["input"] as? JsonObject)?.let(::xvalContext)
            val full = r["expect"] as? JsonObject
            if (ctx == null || full == null) { failures += "$id: 레코드를 못 읽음"; continue }
            val expected = JsonObject(full.filterKeys { it in compareKeys })
            val result = MahjongScoring.evaluate(ctx)
            if ((result as? MahjongEvaluation.Success)?.score?.agari == true) agari += 1
            val d = MahjongCorpus.diffs(expected, MahjongCorpus.view(result, ctx.tsumo))
            if (d.isNotEmpty()) failures += "$id: " + d.joinToString(" | ")
        }
        assertEquals(276, agari, "기준선: 화료 276 · 역 없음 24")
        for ((key, count, tenpaiCount) in listOf(Triple("shape13", 120, 33), Triple("shape_meld", 60, 29))) {
            val records = gate[key].items()
            assertEquals(count, records.size, key)
            var tenpai = 0
            for (r in records) {
                r as JsonObject
                val counts = MahjongTiles.counts34(ids(r["closed"]))
                val melds = r.int("n_melds") ?: 0
                val waits = MahjongHand.waits(counts, melds)
                if (waits.isNotEmpty()) tenpai += 1
                val got = obj("shanten" to n(MahjongHand.shanten(counts, melds)), "waits" to JsonArray(waits.map(::n)), "tenpai" to b(waits.isNotEmpty()))
                val d = MahjongCorpus.diffs(r["expect"] ?: JsonNull, got)
                if (d.isNotEmpty()) failures += "${r.str("id")}: " + d.joinToString(" | ")
            }
            assertEquals(tenpaiCount, tenpai, key)
        }
        assertTrue(failures.isEmpty(), "${failures.size}건:\n" + failures.take(10).joinToString("\n"))
    }
}
