// 원본: Tests/checkTests/MahjongTableEngineReplayTests.swift @ e4995a3a — Android 판 8
// 아잉 마작 판 진행 엔진을 판 진행 코퍼스 replay.json(table_ref.py 정답지 게이트 표본 65)과 맞춘다 — 사건 요약 · 국 결과 · advance · 판 끝 · 결정.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.mahjong.MahjongAdvance
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.rules.mahjong.MahjongRules
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal object MahjongReplay {
    const val PATH = "Tests/checkTests/Fixtures/mahjong/replay.json"
    const val GATE_MD5 = "1e49eed551d0aa63ed391be0c865ef92"
    const val SOURCE_MD5 = "59763ce6822a78940842b29637f2d26b"

    fun md5(path: String): String =
        MessageDigest.getInstance("MD5").digest(RepoFiles.readText(path).encodeToByteArray()).joinToString("") { "%02x".format(it) }

    val document: JsonObject by lazy { Json.parseToJsonElement(RepoFiles.readText(PATH)) as JsonObject }
    val records: List<JsonObject> by lazy { (document["records"] as JsonArray).map { it as JsonObject } }

    fun JsonElement?.int(): Int? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.intOrNull
    fun JsonElement?.str(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
    fun JsonElement?.items(): List<JsonElement> = (this as? JsonArray)?.toList() ?: emptyList()

    fun tiles(v: JsonElement?): List<MahjongTile> = v.items().mapNotNull { it.int()?.let(MahjongTile::of) }

    fun step(raw: JsonObject): MahjongEngineStep? {
        val seat = raw["seat"].int() ?: return null
        val op = raw["op"].str() ?: return null
        val action = raw["action"].str()
        val ts = tiles(raw["tiles"])
        return when (op) {
            "act" -> when (action) {
                "discard" -> ts.firstOrNull()?.let { MahjongTurnAction.Discard(it) }
                "riichi" -> ts.firstOrNull()?.let { MahjongTurnAction.Riichi(it) }
                "tsumo" -> MahjongTurnAction.Tsumo
                "ankan" -> MahjongTurnAction.Ankan(ts)
                "kakan" -> ts.firstOrNull()?.let { MahjongTurnAction.Kakan(it) }
                "kyuushu" -> MahjongTurnAction.Kyuushu
                else -> null
            }?.let { MahjongEngineStep.Act(seat, it) }
            "call" -> when (action) {
                "ron" -> MahjongCallAnswer.Ron
                "pass" -> MahjongCallAnswer.Pass
                "pon" -> MahjongCallAnswer.Pon(ts)
                "minkan" -> MahjongCallAnswer.Minkan(ts)
                "chi" -> MahjongCallAnswer.Chi(ts)
                else -> null
            }?.let { MahjongEngineStep.Call(seat, it) }
            "timeout" -> MahjongEngineStep.Timeout(seat)
            "away" -> action?.let(MahjongAwayReason::of)?.let { MahjongEngineStep.Away(seat, it) }
            "back" -> MahjongEngineStep.Back(seat)
            "wait" -> MahjongEngineStep.Wait
            else -> null
        }
    }

    private fun n(x: Int?): JsonElement = x?.let(::JsonPrimitive) ?: JsonNull
    private fun s(x: String) = JsonPrimitive(x)
    private fun b(x: Boolean) = JsonPrimitive(x)
    private fun ints(xs: List<Int>) = JsonArray(xs.map(::JsonPrimitive))
    private fun idList(ts: List<MahjongTile>?) = ints((ts ?: emptyList()).map { it.id })
    private fun arr(vararg xs: JsonElement) = JsonArray(xs.toList())
    private fun obj(vararg xs: Pair<String, JsonElement>) = JsonObject(mapOf(*xs))

    fun summary(e: MahjongEvent): JsonElement {
        val k = s(e.kind)
        return when (e.kind) {
            "deal" -> arr(k, n(e.dealerSeat), n(e.handIndex), n(e.round), n(e.handNo), n(e.honba), n(e.kyotaku), n(e.dora?.firstOrNull()?.id))
            "draw" -> arr(k, n(e.seat), n(e.tile?.id), b(e.rinshan ?: false))
            "discard" -> arr(k, n(e.seat), n(e.tile?.id), b(e.tsumogiri ?: false), b(e.riichi ?: false), b(e.isAutoDiscard))
            "call" -> arr(k, n(e.seat), s(e.type ?: ""), idList(e.tiles), n(e.called?.id), n(e.fromSeat))
            "kan" -> arr(k, n(e.seat), s(e.type ?: ""), idList(e.tiles))
            "dora" -> arr(k, JsonNull, n(e.indicator?.id))
            "riichi" -> arr(k, n(e.seat))
            "win" -> arr(k, JsonNull, ints(e.seats ?: emptyList()), n(e.fromSeat))
            "hand_draw" -> arr(k, JsonNull, s(e.reason ?: ""))
            "scores" -> arr(k, JsonNull, ints(e.deltas ?: emptyList()), ints(e.scoresAfter ?: emptyList()))
            "away" -> arr(k, n(e.seat), b(e.on ?: false), e.reason?.let(::s) ?: JsonNull)
            "end" -> arr(k, JsonNull, s(e.endReason ?: ""))
            else -> arr(k)
        }
    }

    fun result(r: MahjongHandResult, kyotakuAfter: Int): JsonElement {
        val wins = (r.wins ?: emptyList()).map { w ->
            obj(
                "seat" to n(w.seat), "from_seat" to n(w.fromSeat), "win_tile" to n(w.winTile?.id), "hand" to idList(w.hand),
                "melds" to JsonArray((w.melds ?: emptyList()).map { arr(s(it.type), idList(it.tiles)) }),
                "yaku" to JsonArray((w.yaku ?: emptyList()).map { arr(s(it.id), n(it.han)) }),
                "yakuman" to n(w.yakuman), "han" to n(w.han),
                "fu" to (if ((w.yakuman ?: 0) > 0 && w.fu == 0) JsonNull else n(w.fu)),
                "limit" to s(w.limit ?: ""), "dora" to n(w.dora), "aka" to n(w.aka), "ura" to n(w.ura),
                "ura_indicators" to (w.uraIndicators?.let(::idList) ?: JsonNull),
                "pao" to (w.pao?.let { obj("seat" to n(it.seat), "yaku" to s(it.yaku ?: "")) } ?: JsonNull),
            )
        }
        return obj(
            "kind" to s(r.kind), "reason" to (r.reason?.let(::s) ?: JsonNull), "wins" to JsonArray(wins),
            "tenpai" to ints((r.tenpai ?: emptyList()).map { it.seat }), "nagashi" to ints(r.nagashi ?: emptyList()), "bonus_to" to n(r.bonusTo),
            "deltas" to ints(r.deltas ?: emptyList()), "scores_after" to ints(r.scoresAfter ?: emptyList()), "renchan" to b(r.renchan ?: false),
            "kyotaku_after" to n(kyotakuAfter),
        )
    }

    fun advanceMatches(expected: JsonElement?, got: MahjongAdvance): String? {
        val e = expected as? JsonObject ?: return "advance 없음"
        val next = got.next?.let { obj("round" to n(it.round), "hand" to n(it.hand), "honba" to n(it.honba)) } ?: JsonNull
        val pairs = listOf(
            Triple("end", e["end"] ?: JsonNull, b(got.end)),
            Triple("reason", e["reason"] ?: JsonNull, got.reason?.let(::s) ?: JsonNull),
            Triple("next", e["next"] ?: JsonNull, next),
            Triple("extension", e["extension"] ?: b(false), b(got.isExtension)),
        )
        for ((key, a, bb) in pairs) if (firstDiff(a, bb, "") != null) return "advance.$key: $a ≠ $bb"
        return null
    }

    fun final(f: FinalRecord?): JsonElement = f?.let {
        obj("end_reason" to s(it.endReason), "order" to ints(it.order), "ranks" to ints(it.ranks), "final_scores" to ints(it.finalScores), "kyotaku" to n(it.kyotaku))
    } ?: JsonNull

    fun decision(d: MahjongDecision?): JsonElement = when (d) {
        is MahjongDecision.Turn -> obj(
            "kind" to s("turn"), "discard" to idList(d.discard), "riichi" to idList(d.riichi), "tsumo" to b(d.tsumo),
            "ankan" to JsonArray(d.ankan.map(::idList)), "kakan" to idList(d.kakan), "kyuushu" to b(d.kyuushu),
        )
        is MahjongDecision.Call -> obj(
            "kind" to s("call"), "window_kind" to s(d.windowKind), "tile" to n(d.tile.id), "from_seat" to n(d.fromSeat), "ron" to b(d.ron),
            "pon" to JsonArray(d.pon.map(::idList)), "minkan" to JsonArray(d.minkan.map(::idList)), "chi" to JsonArray(d.chi.map(::idList)),
        )
        null -> JsonNull
    }

    private fun prim(a: JsonPrimitive, b: JsonPrimitive): Boolean {
        if (a.isString || b.isString) return a.isString == b.isString && a.content == b.content
        val ad = a.doubleOrNull
        val bd = b.doubleOrNull
        if (ad != null && bd != null) return ad == bd
        return a.booleanOrNull != null && a.booleanOrNull == b.booleanOrNull
    }

    fun firstDiff(a: JsonElement, b: JsonElement, path: String): String? {
        if (a is JsonObject && b is JsonObject) {
            for (key in (a.keys + b.keys).sorted()) {
                val xa = a[key]
                val yb = b[key]
                if (xa == null || yb == null) return "$path.$key: 한쪽에만 있음"
                firstDiff(xa, yb, "$path.$key")?.let { return it }
            }
            return null
        }
        if (a is JsonArray && b is JsonArray) {
            for (i in 0 until minOf(a.size, b.size)) firstDiff(a[i], b[i], "$path[$i]")?.let { return it }
            return if (a.size == b.size) null else "$path: 길이 ${a.size} ≠ ${b.size}"
        }
        if (a is JsonNull || b is JsonNull) return if (a is JsonNull && b is JsonNull) null else "$path: $a ≠ $b"
        if (a is JsonPrimitive && b is JsonPrimitive) return if (prim(a, b)) null else "$path: $a ≠ $b"
        return "$path: $a ≠ $b"
    }

    class Run(val engine: MahjongTableEngine) {
        val events = mutableListOf<MahjongEvent>()
        val decisions = mutableListOf<JsonElement>()
        var failure: String? = null
    }

    fun run(rec: JsonObject): Run {
        val id = rec["id"].str() ?: "?"
        val format = rec["format"].str()?.let(MahjongFormat::of) ?: MahjongFormat.tonpuu
        val scores = rec["scores"].items().mapNotNull { it.int() }
        fun int(key: String) = rec[key].int() ?: 0
        val engine = MahjongTableEngine(format, listOf(null, null, null, null), scores, int("round"), int("hand_no"), int("honba"), int("kyotaku"))
        val r = Run(engine)
        val walls: List<List<Int>> = if (rec["kind"].str() == "game") rec["walls"].items().map { w -> w.items().mapNotNull { it.int() } }
        else listOf(rec["wall"].items().mapNotNull { it.int() })
        val first = walls.firstOrNull() ?: return r.also { it.failure = "$id: 패산 없음" }
        engine.enqueueWalls(walls.drop(1))
        val dealt = engine.deal(first)
        if (dealt.isEmpty()) return r.also { it.failure = "$id: 배패 실패" }
        r.events += dealt
        val expect = rec["expect"] as? JsonObject ?: JsonObject(emptyMap())
        val wantDecisions = expect.containsKey("decisions")
        for ((i, raw) in rec["script"].items().withIndex()) {
            raw as JsonObject
            val op = step(raw) ?: return r.also { it.failure = "$id: 걸음 $i 을 못 읽음" }
            var seen: Pair<Boolean, MahjongDecision?> = false to null
            val seat = raw["seat"].int() ?: 0
            val hook: ((MahjongTableEngine) -> Unit)? =
                if (wantDecisions && raw["op"].str() in setOf("act", "call", "timeout")) { e -> seen = true to e.decision(seat) } else null
            when (val res = engine.step(op, hook)) {
                is MahjongStepResult.Success -> r.events += res.events
                is MahjongStepResult.Failure -> return r.also { it.failure = "$id: 걸음 $i ${raw["op"]}/${raw["action"]} 거부 — ${res.error}" }
            }
            if (seen.first) r.decisions.add(arr(JsonPrimitive(i), JsonPrimitive(seat), decision(seen.second)))
        }
        return r
    }

    fun check(rec: JsonObject): String? {
        val id = rec["id"].str() ?: "?"
        val r = run(rec)
        r.failure?.let { return it }
        val e = r.engine
        if (e.wallQueue.isNotEmpty()) return "$id: 쓰지 않은 패산 ${e.wallQueue.size}"
        val expect = rec["expect"] as? JsonObject ?: JsonObject(emptyMap())
        firstDiff(expect["events"] ?: JsonNull, JsonArray(r.events.map(::summary)), "$id.events")?.let { return it }
        if (rec["kind"].str() == "hand") {
            if (e.hands.size != 1 || !(e.stage == Stage.handEnd || e.stage == Stage.finished)) return "$id: 국이 끝나지 않음(${e.stage})"
            val h = e.hands[0]
            firstDiff(expect["result"] ?: JsonNull, result(h.result, h.kyotakuAfter), "$id.result")?.let { return it }
            advanceMatches(expect["advance"], h.advance)?.let { return "$id: $it" }
        } else {
            if (e.stage != Stage.finished) return "$id: 판이 끝나지 않음(${e.stage})"
            val hs = expect["hands"].items()
            if (hs.size != e.hands.size) return "$id: 국 수 ${hs.size} ≠ ${e.hands.size}"
            for ((i, pair) in hs.zip(e.hands).withIndex()) {
                val (want, h) = pair
                want as JsonObject
                firstDiff(want["result"] ?: JsonNull, result(h.result, h.kyotakuAfter), "$id.hands[$i].result")?.let { return it }
                advanceMatches(want["advance"], h.advance)?.let { return "$id.hands[$i]: $it" }
            }
        }
        firstDiff(expect["final"] ?: JsonNull, final(e.finalRecord), "$id.final")?.let { return it }
        expect["decisions"]?.let { want -> firstDiff(want, JsonArray(r.decisions), "$id.decisions")?.let { return it } }
        return null
    }
}

class MahjongTableEngineReplayTest {
    @Test
    fun fixtureIsTheGateSample() {
        assertEquals(MahjongReplay.GATE_MD5, MahjongReplay.md5(MahjongReplay.PATH))
        val doc = MahjongReplay.document
        assertEquals("mahjong-replay/1", (doc["schema"] as JsonPrimitive).content)
        assertEquals(MahjongRules.timeoutAutoWin, (doc["timeout_auto_win"] as JsonPrimitive).booleanOrNull)
        val subset = doc["subset_of"] as JsonObject
        assertEquals(MahjongReplay.SOURCE_MD5, (subset["md5"] as JsonPrimitive).content)
        assertEquals(65, MahjongReplay.records.size)
        assertEquals(55, MahjongReplay.records.count { (it["origin"] as? JsonPrimitive)?.content == "crafted" })
        assertEquals(10, MahjongReplay.records.count { (it["origin"] as? JsonPrimitive)?.content == "random" })
    }

    // 없으면: 경계 국(더블론 · 창깡 · 영상 · 사깡 · 리치 성립 울림 · 후리텐 · 시간 초과 자동 화료 · 자리 비움 …)과 무작위 국의 흐름이 참조와 갈라져도 모른다.
    @Test
    fun everyGateRecordReplaysExactly() {
        val failures = MahjongReplay.records.mapNotNull { MahjongReplay.check(it) }
        assertTrue(failures.isEmpty(), "${failures.size}건:\n" + failures.take(8).joinToString("\n"))
    }
}
