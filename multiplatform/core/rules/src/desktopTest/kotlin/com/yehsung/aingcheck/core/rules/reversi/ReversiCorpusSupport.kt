// 원본: Tests/checkTests/ReversiRulesTests.swift:14-187(ReversiCorpus · ReversiCorpusFile) · ReversiPerftTests.swift:26-99(ReversiPerftFixture) @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.fail

// 아잉 뒤집기 시험의 정답지 두 장을 **저장소 원본 그대로** 읽는다(복사하지 않는다 — 맥 시험·서버 마이그레이션·파이썬 참조 구현과 같은 파일):
//  · `Tests/checkTests/Fixtures/reversi/cases.json`(schema reversi-cases/1) — 손 사례 48 · 연속 자동 착수 5 · 기보 표본 200 · perft 공표값.
//  · `Tests/checkTests/Fixtures/reversi-perft.json` — 시작 판 depth 1~10 · 잎 다섯(ⓐ~ⓔ).
// 사례는 id·라벨 머리글자로 집는다 — 배열 인덱스로 집으면 줄 순서만 바뀌어도 다른 판을 잰다.

internal const val REVERSI_CORPUS = "Tests/checkTests/Fixtures/reversi/cases.json"
internal const val REVERSI_PERFT = "Tests/checkTests/Fixtures/reversi-perft.json"

internal fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content
internal fun JsonObject.intOrNull(key: String): Int? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.intOrNull
internal fun JsonObject.boolOrNull(key: String): Boolean? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull
internal fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
internal fun JsonObject.ints(key: String): List<Int>? = (this[key] as? JsonArray)?.map { it.jsonPrimitive.int }
internal fun JsonObject.objects(key: String): List<JsonObject> = (this[key] as? JsonArray)?.map { it.jsonObject } ?: emptyList()
internal fun JsonElement?.isJsonNull(): Boolean = this == null || this is JsonNull

/** 코퍼스 `{black, white, empty}`·`{black, white}` 칸 → 돌 수. */
internal fun JsonObject.counts(): ReversiCounts = ReversiCounts(intOrNull("black")!!, intOrNull("white")!!, intOrNull("empty")!!)

/** WOF 점수(코퍼스 `{black, white, result}`)와 견줄 Kotlin 점수의 글자 꼴. */
internal fun ReversiScore.triple(): Triple<Int, Int, String> = Triple(black, white, result.rawValue)
internal fun JsonObject.scoreTriple(): Triple<Int, Int, String> = Triple(intOrNull("black")!!, intOrNull("white")!!, str("result")!!)

/** Swift `ReversiCorpusFile` — 매번 읽는다(수 ms). 전역 캐시를 두면 그 캐시가 또 하나의 상태가 된다. */
internal object ReversiCorpusFile {
    fun load(): JsonObject = Json.parseToJsonElement(RepoFiles.readText(REVERSI_CORPUS)).jsonObject

    fun hand(corpus: JsonObject = load()): List<JsonObject> = corpus.objects("hand")

    fun hand(id: String, corpus: JsonObject = load()): JsonObject =
        hand(corpus).firstOrNull { it.str("id") == id }
            ?: fail("cases.json 에 사례 $id 가 없다 — 조용히 건너뛰면 그 자리가 아무것도 안 재면서 초록이 된다")

    fun board(text: String?, label: String): ReversiBoard =
        text?.let { ReversiBoard.fromString(it) } ?: fail("$label: 판 문자열을 못 읽었다 — $text")

    fun color(text: String?, label: String): ReversiColor = ReversiColor.of(text) ?: fail("$label: 색을 못 읽었다 — $text")

    /** "f5f6e6…" → [37, 45, …]. */
    fun indices(moves: String, label: String): List<Int> {
        if (moves.length % 2 != 0) fail("$label: 수 목록 길이가 홀수다")
        return (moves.indices step 2).map { offset ->
            val coord = moves.substring(offset, offset + 2)
            ReversiPoint.fromCoord(coord)?.idx ?: fail("$label: 좌표 $coord 를 못 읽었다")
        }
    }
}

/** Swift `ReversiPerftFixture` 의 한 항목. counts[0] 이 깊이 1. */
internal class ReversiPerftItem(val json: JsonObject) {
    val label: String = json.str("label")!!
    val board: String = json.str("board")!!
    val color: String = json.str("color")!!
    val counts: List<Long> = json["counts"]!!.jsonArray.map { it.jsonPrimitive.long }

    /** null(차례인 쪽이 둘 곳 있음) · "pass" · 끝 사유. 잎에만 있다. */
    val outcome: String? = json.str("outcome")
    val terminalChildren: List<Int>? = json.ints("terminal_children")

    /** 라벨 머리글자(①·ⓐ…). */
    val marker: String = label.take(1)
}

internal object ReversiPerftFixture {
    fun raw(): JsonObject = Json.parseToJsonElement(RepoFiles.readText(REVERSI_PERFT)).jsonObject

    fun positions(): List<ReversiPerftItem> = raw().objects("positions").map(::ReversiPerftItem)

    fun leaves(): List<ReversiPerftItem> = raw().objects("leaves").map(::ReversiPerftItem)

    fun all(): List<ReversiPerftItem> = positions() + leaves()

    fun item(marker: String): ReversiPerftItem =
        all().firstOrNull { it.marker == marker } ?: fail("픽스처에 $marker 국면이 없다(있는 것: ${all().joinToString(" ") { it.marker }})")
}

/** Swift `expectReversiPerft` — 어긋나면 판과 divide 를 함께 남긴다(성공할 때는 divide 를 계산하지 않는다). */
internal fun expectReversiPerft(item: ReversiPerftItem, depth: Int) {
    val board = ReversiCorpusFile.board(item.board, item.label)
    val color = ReversiCorpusFile.color(item.color, item.label)
    if (depth < 1 || depth > item.counts.size) fail("${item.label}: 픽스처에 깊이 $depth 기대값이 없다(있는 깊이 1…${item.counts.size})")
    val expected = item.counts[depth - 1]
    val actual = ReversiRules.perft(board, color, depth)
    if (actual == expected) return
    val divide = ReversiRules.perftDivide(board, color, depth).joinToString("\n") { row ->
        "  ${row.idx?.let { ReversiPoint.of(it)?.coord } ?: "패스"} ${row.nodes}"
    }
    fail("${item.label} 깊이 $depth: $actual ≠ $expected (차 ${actual - expected})\n${item.board} · ${item.color} 차례\ndivide(깊이 $depth):\n$divide")
}
