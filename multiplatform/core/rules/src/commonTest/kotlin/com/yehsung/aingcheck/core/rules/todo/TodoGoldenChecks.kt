// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesTodo.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.todo

import com.yehsung.aingcheck.core.rules.format.SwiftDate
import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.parseSwiftJson
import com.yehsung.aingcheck.core.rules.text.TextGoldenChecks
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** 할 일 골든(E12)의 대조 몫(JVM 시험과 Android 계측이 같은 판정을 부른다 — 골든을 읽는 자리는 부르는 쪽이 정한다). */
object TodoGoldenChecks {
    private fun n(value: Long?): JsonElement = when {
        value == null -> JsonNull
        value >= -9_007_199_254_740_992L && value <= 9_007_199_254_740_992L -> JsonPrimitive(value)
        else -> JsonPrimitive("int:$value")
    }

    private fun s(value: String?): JsonElement = value?.let { JsonPrimitive(it) } ?: JsonNull
    private fun d(value: Double?): JsonElement = value?.let { JsonPrimitive(Golden.bitsText(it)) } ?: JsonNull
    private fun obj(vararg pairs: Pair<String, JsonElement>): JsonObject = JsonObject(linkedMapOf(*pairs))
    private fun canon(e: JsonElement): JsonElement = when (e) {
        is JsonObject -> JsonObject(e.entries.sortedBy { it.key }.associate { it.key to canon(it.value) })
        is JsonArray -> JsonArray(e.map(::canon))
        else -> e
    }

    private fun assertJson(want: JsonElement?, got: JsonElement, message: String) =
        assertEquals(canon(want ?: JsonNull).toString(), canon(got).toString(), message)

    private fun itemJson(i: TodoItem) = obj("id" to s(i.id), "title" to s(TextGoldenChecks.cps(i.title)), "createdAt" to d(i.createdAt),
        "updatedAt" to d(i.updatedAt), "completedAt" to d(i.completedAt), "deletedAt" to d(i.deletedAt), "originDayKey" to s(i.originDayKey))

    private fun itemOf(o: JsonObject): TodoItem {
        fun bits(key: String) = o[key].let { if (it == null || it is JsonNull) null else Golden.bits(it.jsonPrimitive.content) }
        return TodoItem(o.string("id"), TextGoldenChecks.text(o.string("title")), bits("createdAt")!!, bits("updatedAt")!!, bits("completedAt"),
            bits("deletedAt"), o.string("originDayKey"))
    }

    private fun ids(e: JsonElement?): Set<String> = (e as JsonArray).map { it.jsonPrimitive.content }.toSet()
    private fun idsJson(set: Set<String>): JsonElement = JsonArray(set.sorted().map { JsonPrimitive(it) })

    fun todoRulesMatchSwift(golden: GoldenFile) {
        val titles = golden.case("titles")
        for (row in titles.array("rows")) {
            val r = row.jsonObject
            val raw = TextGoldenChecks.text(r.string("cps"))
            val normalized = TodoRules.normalizedTitle(raw)
            assertEquals(r.string("normalized"), TextGoldenChecks.cps(normalized), "normalizedTitle ${r.string("cps")}")
            assertEquals(r["fits"]!!.jsonPrimitive.boolean, TodoRules.titleFitsLimits(normalized), "fits ${r.string("cps")}")
            assertEquals(r["fitsRaw"]!!.jsonPrimitive.boolean, TodoRules.titleFitsLimits(raw), "fitsRaw ${r.string("cps")}")
        }
        val constants = titles.obj("constants")
        assertEquals(constants.int("maxTitleLength"), TodoRules.maxTitleLength)
        assertEquals(constants.int("maxTitleCodePoints"), TodoRules.maxTitleCodePoints)
        assertEquals(constants.int("counterVisibleFrom"), TodoRules.counterVisibleFrom)
        assertEquals(constants.int("oldItemDays"), TodoRules.oldItemDays)
        assertEquals(constants.int("purgeDays"), TodoRules.purgeDays)
        assertEquals(constants.string("undoSecondsBits"), Golden.bitsText(TodoRules.undoSeconds))
        val carried = golden.case("carried")
        for (row in carried.array("rows")) {
            val r = row.jsonObject
            val days = TodoRules.carriedDays(r.string("origin"), r.string("today"))
            assertEquals(r.int("days"), days, "carriedDays $r")
            assertJson(r["badge"], s(TodoRules.carryBadge(days)), "badge $r")
        }
        for (row in carried.array("badges")) {
            val r = row.jsonObject
            assertJson(r["badge"], s(TodoRules.carryBadge(r.int("days"))), "badge ${r.int("days")}")
        }
        val visibility = golden.case("visibility")
        val items = visibility.array("items").map { itemOf(it.jsonObject) }
        assertJson(visibility["items"], JsonArray(items.map(::itemJson)), "items round trip")
        for (row in visibility.array("rows")) {
            val r = row.jsonObject
            val today = r.string("today")
            assertJson(r["visible"], JsonArray(TodoRules.visible(items, today).map { s(it.id) }), "visible $today")
            assertJson(r["visibleKeeping5"], JsonArray(TodoRules.visible(items, today, "00000000-0000-4000-8000-000000000005").map { s(it.id) }), "keeping $today")
            assertJson(r["old"], JsonArray(items.filter { TodoRules.isOld(it, today) }.map { s(it.id) }), "old $today")
        }
        assertJson(visibility["pruned"], JsonArray(TodoRules.pruned(items, 1_792_940_400.0).map { s(it.id) }), "pruned")
        for (row in golden.case("milliseconds").array("rows")) {
            val r = row.jsonObject
            // Swift 는 Date(timeIntervalSince1970: t) 로 만든 뒤 잰다 — 같은 왕복을 거친 값으로 견준다.
            val t = SwiftDate.since1970(Golden.bits(r.string("secondsBits")))
            val ms = TodoRules.milliseconds(t)
            assertJson(r["ms"], n(ms), "ms ${r.string("secondsBits")}")
            assertEquals(r.string("roundTripBits"), Golden.bitsText(TodoRules.date(ms)), "round trip $t")
            assertEquals(r.string("normalizedBits"), Golden.bitsText(TodoRules.normalizedTime(t)), "normalized $t")
        }
        var merges = 0
        for (case in golden.cases.filter { it.string("id").startsWith("merge-") }) {
            val local = case.array("local").map { itemOf(it.jsonObject) }
            val server = case.array("server").map { itemOf(it.jsonObject) }
            val sent = case.obj("sent").mapValues { it.value.jsonPrimitive.content.toLong() }
            val result = TodoRules.mergedSync(local, ids(case["pending"]), sent, server, ids(case["rejected"]), case["full"]!!.jsonPrimitive.boolean,
                ids(case["held"]), ids(case["protected"]))
            assertJson(case["result"], obj("items" to JsonArray(result.items.map(::itemJson)), "pending" to idsJson(result.pending),
                "heldRejectedIDs" to idsJson(result.heldRejectedIDs), "deferredIDs" to idsJson(result.deferredIDs)), golden.failure(case.string("id"), "mergedSync"))
            val again = TodoRules.mergedSync(result.items, result.pending, sent, server, ids(case["rejected"]), case["full"]!!.jsonPrimitive.boolean,
                result.heldRejectedIDs, ids(case["protected"]))
            val idempotent = again.items == result.items && again.pending == result.pending && again.heldRejectedIDs == result.heldRejectedIDs
            assertEquals(case["idempotent"]!!.jsonPrimitive.boolean, idempotent, golden.failure(case.string("id"), "멱등"))
            merges++
        }
        assertEquals(15, merges, "병합 시나리오 수")
    }

    fun todoWireMatchesSwift(golden: GoldenFile) {
        var responses = 0
        for (case in golden.cases.filter { it.string("id").startsWith("response-") }) {
            val id = case.string("id")
            val response = try { TodoSyncResponse.decode(parseSwiftJson(case.string("json"))) } catch (e: SwiftDecodingError) { null }
            if (case["throws"] != null) {
                assertEquals(null, response, golden.failure(id, "throw 해야 한다"))
                continue
            }
            response!!
            assertJson(case["status"], s(response.status), golden.failure(id, "status"))
            assertJson(case["watermarkMs"], n(response.watermarkMs), golden.failure(id, "watermark"))
            assertJson(case["full"], response.full?.let { JsonPrimitive(it) } ?: JsonNull, golden.failure(id, "full"))
            assertJson(case["max"], n(response.max), golden.failure(id, "max"))
            assertJson(case["items"], response.items?.let { list -> JsonArray(list.map { w ->
                obj("id" to s(w.id), "title" to (w.title?.let { s(TextGoldenChecks.cps(it)) } ?: JsonNull), "createdAtMs" to n(w.createdAtMs),
                    "updatedAtMs" to n(w.updatedAtMs), "completedAtMs" to n(w.completedAtMs), "deletedAtMs" to n(w.deletedAtMs),
                    "originDayKey" to s(w.originDayKey), "todoItem" to (w.todoItem()?.let(::itemJson) ?: JsonNull))
            }) } ?: JsonNull, golden.failure(id, "items"))
            assertJson(case["rejected"], response.rejected?.let { list -> JsonArray(list.map { obj("id" to s(it.id), "reason" to s(it.reason)) }) } ?: JsonNull,
                golden.failure(id, "rejected"))
            assertJson(case["mergeable"], response.mergeableResult()?.let { r ->
                obj("items" to JsonArray(r.items.map(::itemJson)), "rejectedIDs" to idsJson(r.rejectedIDs), "full" to JsonPrimitive(r.full),
                    "watermarkMs" to n(r.watermarkMs))
            } ?: JsonNull, golden.failure(id, "mergeableResult"))
            responses++
        }
        assertTrue(responses >= 15, "응답 대조 수 $responses")
        val base = 1_792_940_400.0
        val sd = SwiftDate::since1970
        val items = listOf(
            TodoItem("00000000-0000-4000-8000-000000000001", "가/나", sd(base + 0.001), sd(base + 0.0015), sd(base + 2), null, "20261026"),
            TodoItem("00000000-0000-4000-8000-000000000002", "😀", sd(base), sd(base), null, sd(base + 3), "20261026"),
        ).map(TodoSyncWireItem::of)
        listOf<Long?>(null, 0, 1_792_940_400_123).forEachIndexed { index, since ->
            val request = TodoSyncRequest(if (index == 0) emptyList() else items, since)
            val case = golden.case("request-$index")
            assertJson(Json.parseToJsonElement(case.string("rpcBody")), request.rpcBody(), "rpcBody $index")
            assertJson(Json.parseToJsonElement(case.string("changesJSON")), request.changesJSON(), "changesJSON $index")
        }
        val batches = golden.case("batches")
        assertEquals(batches.int("batchLimit"), TodoSyncRules.batchLimit)
        assertEquals(batches.string("debounceBits"), Golden.bitsText(TodoSyncRules.debounceSeconds))
        assertEquals(batches.string("periodicBits"), Golden.bitsText(TodoSyncRules.periodicSeconds))
        assertEquals(batches.string("cooldownBits"), Golden.bitsText(TodoSyncRules.serverMissingCooldownSeconds))
        for (row in batches.array("rows")) {
            val r = row.jsonObject
            val count = r.int("count")
            val ids = (0 until count).map { "00000000-0000-4000-8000-" + ((it.toLong() * 7919) % 100_003).toString().padStart(12, '0') }
            val result = TodoSyncRules.batches(ids)
            assertJson(r["sizes"], JsonArray(result.map { JsonPrimitive(it.size) }), "batch sizes $count")
            assertJson(r["firsts"], JsonArray(result.map { s(it.firstOrNull()) }), "batch firsts $count")
        }
    }
}
