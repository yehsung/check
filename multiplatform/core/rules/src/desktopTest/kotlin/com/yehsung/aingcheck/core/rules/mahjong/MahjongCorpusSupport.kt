// 원본: Tests/checkTests/MahjongScoringCorpusTests.swift:13-240(MahjongCorpus) @ e4995a3a — Android 판 8
//
// 아잉 마작 판정 코퍼스(`Tests/checkTests/Fixtures/mahjong/cases.json` — rules.md MJ-nn 의 정답지)를 **저장소 원본 그대로** 읽는다.
// 천화 · 지화의 흔한 로마자는 상표 시험 패턴과 같은 글자라 코드에 쓰지 않는다 — 별칭 표 `corpus_alias.json` 을 읽어 바꾼다.
// 비교는 reference.py `_sub` 와 같다: 기대값에 있는 키만 본다.
package com.yehsung.aingcheck.core.rules.mahjong

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

internal object MahjongCorpus {
    const val FOLDER = "Tests/checkTests/Fixtures/mahjong"

    fun load(name: String): JsonElement = Json.parseToJsonElement(RepoFiles.readText("$FOLDER/$name"))

    fun md5(name: String): String {
        val bytes = RepoFiles.readText("$FOLDER/$name").encodeToByteArray()
        return MessageDigest.getInstance("MD5").digest(bytes).joinToString("") { "%02x".format(it) }
    }

    /** 별칭 표(코퍼스 글자 → 저장소 글자). 시험 코드에는 그 글자를 쓰지 않는다 — 파일에서만 온다. */
    val alias: Map<String, String> by lazy {
        (load("corpus_alias.json") as? JsonObject)?.mapNotNull { (k, v) -> (v as? JsonPrimitive)?.takeIf { it.isString }?.let { k to it.content } }?.toMap() ?: emptyMap()
    }

    /** 별칭 적용: 객체 키와 **글자 전체가 같은** 문자열 값을 바꾼다. */
    fun applyAlias(v: JsonElement): JsonElement = when (v) {
        is JsonPrimitive -> if (v.isString) JsonPrimitive(alias[v.content] ?: v.content) else v
        is JsonArray -> JsonArray(v.map(::applyAlias))
        is JsonObject -> JsonObject(v.entries.associate { (k, x) -> (alias[k] ?: k) to applyAlias(x) })
    }

    fun aliasID(id: String): String {
        var out = id
        for ((from, to) in alias) out = out.replace(from, to.uppercase(), ignoreCase = true)
        return out
    }

    data class Case(val id: String, val type: String, val input: JsonObject, val expected: JsonElement)

    val document: JsonObject by lazy { load("cases.json") as JsonObject }

    val cases: List<Case> by lazy {
        ((document["cases"] as? JsonArray) ?: JsonArray(emptyList())).mapNotNull { raw ->
            raw as JsonObject
            val id = raw.str("id") ?: return@mapNotNull null
            val type = raw.str("type") ?: return@mapNotNull null
            val input = raw["input"] as? JsonObject ?: return@mapNotNull null
            val expected = raw["expected"] ?: return@mapNotNull null
            Case(aliasID(id), type, applyAlias(input) as JsonObject, applyAlias(expected))
        }
    }

    fun cases(ofType: String): List<Case> = cases.filter { it.type == ofType }

    fun byID(id: String): Case? = cases.firstOrNull { it.id == id }

    private fun same(a: JsonElement?, b: JsonElement): Boolean {
        if (a == null) return false
        if (a is JsonNull || b is JsonNull) return a is JsonNull && b is JsonNull
        if (a is JsonPrimitive && b is JsonPrimitive) {
            if (a.isString != b.isString) return false
            if (a.isString) return a.content == b.content
            val ad = a.doubleOrNull
            val bd = b.doubleOrNull
            if (ad != null && bd != null) return ad == bd
            return a.booleanOrNull != null && a.booleanOrNull == b.booleanOrNull
        }
        if (a is JsonArray && b is JsonArray) return a.size == b.size && a.indices.all { same(a[it], b[it]) }
        if (a is JsonObject && b is JsonObject) return a.keys == b.keys && a.keys.all { same(a[it], b[it]!!) }
        return false
    }

    /** reference `_sub`: 기대값에 있는 키만 비교한다. 다르면 차이 글 목록. */
    fun diffs(expected: JsonElement, actual: JsonElement?, path: String = ""): List<String> {
        when (expected) {
            is JsonObject -> {
                val a = actual as? JsonObject ?: return listOf("$path: ${actual ?: "<없음>"} (객체 기대)")
                return expected.keys.sorted().flatMap { diffs(expected[it]!!, a[it], "$path.$it") }
            }
            is JsonArray -> if (expected.firstOrNull().let { it is JsonArray || it is JsonObject }) {
                val a = actual as? JsonArray
                if (a == null || a.size != expected.size) return listOf("$path: ${actual ?: "<없음>"} ≠ $expected")
                return expected.indices.flatMap { diffs(expected[it], a[it], "$path[$it]") }
            }
            else -> Unit
        }
        return if (same(actual, expected)) emptyList() else listOf("$path: ${actual ?: "<없음>"} ≠ $expected")
    }

    // MARK: - 문자열 → 패 id

    /** 여러 문자열을 **한 산에서** 집듯 id 를 배정한다. 실패하면 null. */
    fun tiles(texts: List<String>): List<List<MahjongTile>>? {
        val sizes = texts.map { MahjongTiles.parse(it)?.size ?: return null }
        val all = MahjongTiles.parse(texts.joinToString("")) ?: return null
        var at = 0
        return sizes.map { n -> all.subList(at, at + n).also { at += n } }
    }

    fun tile(token: String): MahjongTile? = MahjongTiles.parse(token)?.firstOrNull()

    /** 문자열 → 종류 목록(id 배정 없이). 글자가 틀리면 null. */
    fun kindList(text: String): List<Int>? {
        val digits = mutableListOf<Int>()
        val out = mutableListOf<Int>()
        for (ch in text) {
            if (ch == ' ') continue
            if (ch in '0'..'9') { digits += ch - '0'; continue }
            val offset = MahjongTiles.suitOffset(ch) ?: return null
            if (digits.isEmpty()) return null
            for (d in digits) {
                if (ch == 'z' && d !in 1..7) return null
                out += offset + (if (d == 0) 5 else d) - 1
            }
            digits.clear()
        }
        return if (digits.isEmpty()) out else null
    }

    fun kinds(text: String): List<Int> = kindList(text) ?: emptyList()

    fun counts(text: String): IntArray = IntArray(34).also { c -> kinds(text).forEach { c[it] += 1 } }

    fun wind(v: JsonElement?): MahjongWind = (v as? JsonPrimitive)?.takeIf { it.isString }?.content?.let(MahjongWind::of) ?: MahjongWind.east

    /** 코퍼스 hand 입력 → 손 계산 입력. 표시패는 손 다음 id 를 쓰고, 겹치면 따로 배정한다. */
    fun context(input: JsonObject): MahjongWinContext? {
        val closedText = input.str("closed") ?: ""
        val winText = input.str("win") ?: return null
        val meldValues = (input["melds"] as? JsonArray)?.map { it as JsonObject } ?: emptyList()
        val meldTexts = meldValues.map { it.str("tiles") ?: "" }
        val doraText = input.str("dora") ?: ""
        val uraText = input.str("ura") ?: ""
        val handTexts = listOf(closedText, winText) + meldTexts
        val groups: List<List<MahjongTile>> = tiles(handTexts + listOf(doraText, uraText)) ?: run {
            val hand = tiles(handTexts) ?: return null
            val dora = MahjongTiles.parse(doraText) ?: return null
            val ura = MahjongTiles.parse(uraText) ?: return null
            hand + listOf(dora, ura)
        }
        if (groups[1].size != 1) return null
        val melds = meldValues.mapIndexed { i, m ->
            val type = m.str("type")?.let(MahjongMeldType::of) ?: return null
            MahjongMeld(type, groups[2 + i], null, null)
        }
        fun flag(key: String): Boolean = input.bool(key) ?: false
        return MahjongWinContext(
            closed = groups[0], melds = melds, win = groups[1][0], tsumo = flag("tsumo"),
            seatWind = wind(input["seat_wind"]), roundWind = wind(input["round_wind"]),
            riichi = flag("riichi"), doubleRiichi = flag("double_riichi"), ippatsu = flag("ippatsu"), rinshan = flag("rinshan"),
            chankan = flag("chankan"), haitei = flag("haitei"), houtei = flag("houtei"),
            heavenly = flag(MahjongYaku.heavenly.rawValue), earthly = flag(MahjongYaku.earthly.rawValue),
            doraIndicators = groups[groups.size - 2], uraIndicators = groups[groups.size - 1],
            honba = input.int("honba") ?: 0, kyoutaku = input.int("kyoutaku") ?: 0,
        )
    }

    // MARK: - 결과 → reference 꼴

    fun n(x: Int): JsonPrimitive = JsonPrimitive(x)

    fun points(p: MahjongPoints): JsonObject = JsonObject(buildMap {
        p.ron?.let { put("ron", n(it)) }
        p.fromDealer?.let { put("from_dealer", n(it)) }
        p.fromChild?.let { put("from_child", n(it)) }
        p.fromEach?.let { put("from_each", n(it)) }
    })

    /** reference `_hand_view` 꼴. 형식 오류는 `{error: true}`. */
    fun view(result: MahjongEvaluation, tsumo: Boolean): JsonObject {
        val s = (result as? MahjongEvaluation.Success)?.score ?: return JsonObject(mapOf("error" to JsonPrimitive(true)))
        if (!s.agari) return JsonObject(mapOf("agari" to JsonPrimitive(false), "reason" to (s.reason?.let(::JsonPrimitive) ?: JsonNull)))
        val honba = if (tsumo) JsonObject(mapOf("from_each" to n(s.honbaBonus / 3))) else JsonObject(mapOf("ron" to n(s.honbaBonus)))
        return JsonObject(mapOf(
            "agari" to JsonPrimitive(true),
            "yaku" to JsonArray(s.yaku.map { JsonArray(listOf(JsonPrimitive(it.yaku.rawValue), n(it.han))) }),
            "yakuman" to n(s.yakuman), "dora" to n(s.dora), "aka" to n(s.aka), "ura" to n(s.ura), "han" to n(s.han),
            "fu" to (if (s.yakuman > 0) JsonNull else n(s.fu)), "limit" to JsonPrimitive(s.limit), "base" to n(s.base), "points" to points(s.points),
            "honba_bonus" to honba, "kyoutaku_bonus" to n(s.kyoutakuBonus), "total" to n(s.total),
            "wait" to (s.wait?.let(::JsonPrimitive) ?: JsonNull), "form" to (s.form?.let(::JsonPrimitive) ?: JsonNull),
        ))
    }

    fun evaluate(input: JsonObject): Pair<MahjongWinContext, MahjongEvaluation>? {
        val ctx = context(input) ?: return null
        return ctx to MahjongScoring.evaluate(ctx)
    }
}

internal fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
internal fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.intOrNull
internal fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.booleanOrNull
internal fun JsonElement?.asObject(): JsonObject? = this as? JsonObject
internal fun JsonElement?.asArray(): JsonArray? = this as? JsonArray
internal fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
