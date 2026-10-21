// 골든 로더(K1 · K2 `Golden.load(name)` — G §8-3 으로 W0-b 소유). 형식 정본: contract/README.md
// 원본(작성기): Tests/CheckGoldenSupport/GoldenExport.swift · GoldenJSON.swift @ W0-b
package com.yehsung.aingcheck.testkit.golden

import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Swift 가 쓴 골든을 읽는다. Kotlin 은 **읽기만** 한다(쓰기·고치기는 맥의 `scripts/golden-export.sh` 한 곳).
 *
 * - `Golden.load("rng/splitmix64")` → `contract/golden/rng/splitmix64.json`(계약 — 소비 시험이 `GoldenCoverageTest` 에 잡힌다).
 * - `Golden.loadProbe("w0b-probe/pow3")` → `multiplatform/testkit/src/desktopTest/resources/golden/…`(실험 표 — 계약 아님).
 * - 머리말 여덟 칸(`golden`·`schema`·`equivalence`·`generator`·`swiftSources`·`platformSensitive`·`spec`·`cases`)을 확인하고,
 *   이름이 파일과 다르거나 `schema` 가 모르는 판이면 읽기부터 실패한다(조용히 다른 형식을 대조하지 않게).
 * - 64비트 값은 `"0x…"` 글자([hex64]), 실수는 `…Bits` 16진([bits]). 64비트 정수를 JSON 숫자로 읽지 않는다(2^53 너머 정밀도).
 */
object Golden {
    const val SCHEMA: Int = 1
    const val CONTRACT_DIR: String = "contract/golden"
    const val PROBE_DIR: String = "multiplatform/testkit/src/desktopTest/resources/golden"

    private val NAME = Regex("""^[a-z0-9][a-z0-9-]*(/[a-z0-9][a-z0-9._-]*)+$""")
    private val HEADER = setOf("golden", "schema", "equivalence", "generator", "swiftSources", "platformSensitive", "spec", "cases")
    private val EQUIVALENCE = setOf("bit", "discrete", "set")
    private val json = Json { isLenient = false }

    /** 계약 골든. */
    fun load(name: String): GoldenFile = read(name, CONTRACT_DIR)

    /** 실험 표(W0-b 탐침 — C-X1 · C-X4 · C-X12 …). */
    fun loadProbe(name: String): GoldenFile = read(name, PROBE_DIR)

    /** 정규 글자를 바로 읽는다(로더 자기 시험 · 파일 없이 형식만 볼 때). */
    fun parse(name: String, text: String, path: String = "<글자>"): GoldenFile {
        require(NAME.matches(name)) { "골든 이름 규칙(영역/이름, 소문자) 밖이다: $name" }
        val root = runCatching { json.parseToJsonElement(text).jsonObject }
            .getOrElse { throw IllegalStateException("골든 $path 를 JSON 객체로 못 읽었다: ${it.message}", it) }
        val keys = root.keys
        check(keys == HEADER) { "골든 $path 머리말 칸이 다르다 — 있는 칸 ${keys.sorted()}, 기대 ${HEADER.sorted()}" }
        val golden = root.string("golden")
        check(golden == name) { "골든 $path 의 golden 칸이 '$golden' 이다(요청 '$name') — 파일을 옮겼거나 이름을 바꿨다" }
        val schema = root["schema"]?.jsonPrimitive?.intOrNull
        check(schema == SCHEMA) { "골든 $name 의 schema $schema 를 모른다(이 로더는 $SCHEMA) — 로더를 같은 커밋에서 올린다" }
        val equivalence = root.string("equivalence")
        check(equivalence in EQUIVALENCE) { "골든 $name 의 equivalence '$equivalence' 를 모른다" }
        val platformSensitive = root["platformSensitive"]?.jsonPrimitive?.booleanOrNull
            ?: error("골든 $name 의 platformSensitive 가 불이 아니다")
        val cases = root["cases"]!!.jsonArray.mapIndexed { i, e ->
            (e as? JsonObject) ?: error("골든 $name cases[$i] 가 객체가 아니다")
        }
        check(cases.isNotEmpty()) { "골든 $name 의 cases 가 비었다" }
        val ids = cases.mapIndexed { i, c ->
            (c["id"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: error("골든 $name cases[$i] 에 글자 id 가 없다")
        }
        check(ids.toSet().size == ids.size) { "골든 $name 의 case id 가 겹친다" }
        return GoldenFile(
            golden = golden,
            schema = schema,
            equivalence = equivalence,
            generator = root.string("generator"),
            swiftSources = root["swiftSources"]!!.jsonArray.map { it.jsonPrimitive.content },
            platformSensitive = platformSensitive,
            spec = root["spec"]!!.jsonObject,
            cases = cases,
            path = path,
        )
    }

    private fun read(name: String, dir: String): GoldenFile {
        require(NAME.matches(name)) { "골든 이름 규칙(영역/이름, 소문자) 밖이다: $name" }
        val path = "$dir/$name.json"
        val text = runCatching { RepoFiles.readText(path) }.getOrElse {
            throw IllegalStateException("골든 $path 를 못 읽었다 — 맥에서 CHECK_GOLDEN_WRITE=1 scripts/golden-export.sh 로 만든다(${it.message})", it)
        }
        return parse(name, text, path)
    }

    /** `"0x"` + 16진 16자리 → ULong. 모양이 다르면 실패한다(10진·짧은 글자를 조용히 받지 않는다). */
    fun hex64(text: String): ULong {
        require(text.length == 18 && text.startsWith("0x")) { "64비트 글자는 \"0x\" + 16진 16자리다: '$text'" }
        return text.substring(2).toULong(16)
    }

    /** IEEE-754 비트 16진 16자리("0x" 없음) → Double. */
    fun bits(text: String): Double {
        require(text.length == 16) { "Double 비트 글자는 16진 16자리다: '$text'" }
        return Double.fromBits(text.toULong(16).toLong())
    }

    /** Double → 골든 비트 글자(실패 문구용). */
    fun bitsText(value: Double): String = value.toRawBits().toULong().toString(16).padStart(16, '0')

    /** ULong → 골든 64비트 글자(실패 문구용). */
    fun hex64Text(value: ULong): String = "0x" + value.toString(16).padStart(16, '0')
}

/** 읽은 골든 한 벌. 실패 문구는 [failure] 로 만든다(C§5.5: 골든 이름 · case id · 첫 불일치 · swiftSources · Swift 자세히 보기). */
class GoldenFile(
    val golden: String,
    val schema: Int,
    val equivalence: String,
    val generator: String,
    val swiftSources: List<String>,
    val platformSensitive: Boolean,
    val spec: JsonObject,
    val cases: List<JsonObject>,
    val path: String,
) {
    fun case(id: String): JsonObject = cases.firstOrNull { it.string("id") == id } ?: error("골든 $golden 에 case '$id' 가 없다")

    fun failure(caseId: String, detail: String): String =
        "골든 $golden · case $caseId · $detail\n" +
            "  Swift 원본: ${swiftSources.joinToString()}\n" +
            "  생성 시험: $generator\n" +
            "  Swift 쪽 자세히 보기: CHECK_GOLDEN_VERBOSE=$caseId scripts/golden-export.sh"
}

// ---------- 칸 읽기 도우미 ----------

fun JsonObject.string(key: String): String =
    (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: error("골든 칸 '$key' 가 글자가 아니다: ${this[key]}")

fun JsonObject.int(key: String): Int =
    (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull ?: error("골든 칸 '$key' 가 정수가 아니다: ${this[key]}")

fun JsonObject.long(key: String): Long =
    (this[key] as? JsonPrimitive)?.takeIf { !it.isString }?.content?.toLongOrNull() ?: error("골든 칸 '$key' 가 정수가 아니다: ${this[key]}")

fun JsonObject.hex64(key: String): ULong = Golden.hex64(string(key))

fun JsonObject.bits(key: String): Double = Golden.bits(string(key))

fun JsonObject.array(key: String): JsonArray = (this[key] as? JsonArray) ?: error("골든 칸 '$key' 가 배열이 아니다: ${this[key]}")

fun JsonObject.obj(key: String): JsonObject = (this[key] as? JsonObject) ?: error("골든 칸 '$key' 가 객체가 아니다: ${this[key]}")

fun JsonElement.stringValue(): String =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: error("골든 값이 글자가 아니다: $this")

fun JsonElement.isJsonNull(): Boolean = this is JsonNull
