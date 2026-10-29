// W2-h3 골든 대조 — 일별 순수 계산(token-usage/upload/daily) · 요청 모양(token-usage/upload/requests). Swift 생성기:
// Tests/checkTests/GoldenExport/token-usage/GoldenExportTokenUpload.swift.
package com.yehsung.aingcheck.feature.desktop.tokens.upload

import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountProbeStatus
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountUsage
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TokenUploadGoldenTest {
    private fun s(c: JsonObject, k: String) = c[k]!!.jsonPrimitive.content
    private fun optLong(e: JsonElement?): Long? = (e as? JsonPrimitive)?.longOrNull
    private fun longMap(e: JsonElement?): Map<String, Long> = (e as? JsonObject)?.mapValues { it.value.jsonPrimitive.long } ?: emptyMap()

    private fun value(o: JsonObject) = TokenUsageDailyValue(optLong(o["claude"]), optLong(o["codex"]), optLong(o["codexUTC"]),
        optLong(o["codexAccount"]), optLong(o["antigravity"]))

    private fun valueJson(v: TokenUsageDailyValue): JsonObject = JsonObject(mapOf(
        "claude" to (v.claude?.let { JsonPrimitive(it) } ?: JsonNull), "codex" to (v.codex?.let { JsonPrimitive(it) } ?: JsonNull),
        "codexUTC" to (v.codexUTC?.let { JsonPrimitive(it) } ?: JsonNull),
        "codexAccount" to (v.codexAccount?.let { JsonPrimitive(it) } ?: JsonNull),
        "antigravity" to (v.antigravity?.let { JsonPrimitive(it) } ?: JsonNull)))

    private fun account(e: JsonElement?): CodexAccountUsage? = (e as? JsonObject)?.let {
        CodexAccountUsage(epoch(it["fetchedAtEpoch"]?.jsonPrimitive?.long ?: 1_793_322_123), optLong(it["lifetimeTokens"]) ?: 1, longMap(it["buckets"]))
    }

    @Test
    fun dailyValuesChangedDaysAndRowsMatchSwift() {
        val golden = Golden.load("token-usage/upload/daily")
        assertTrue(golden.cases.size >= 4)
        for (c in golden.cases) {
            val id = s(c, "id")
            val usage = TokenUsageMonthly.decode(c["usage"].toString())
            val last = (c["lastUploaded"] as JsonObject).mapValues { value(it.value.jsonObject) }
            val values = TokenUsageDailyUpload.values(usage, account(c["account"]))
            assertEquals(c["values"], JsonObject(values.mapValues { valueJson(it.value) }), "$id values")
            val changed = TokenUsageDailyUpload.changedDays(values, last)
            assertEquals(c["changedDays"], JsonArray(changed.map { JsonPrimitive(it) }), "$id changedDays")
            val rows = TokenUsageDailyUpload.rows("u-1", "win:dev-1", changed, values)
            assertEquals(c["rows"], SwiftJson.parse(SwiftJson.encode(ListSerializer(TokenUsageDailyUpsertRow.serializer()), rows)), "$id rows")
        }
    }

    @Test
    fun requestShapesMatchSwift() = runTest {
        val golden = Golden.load("token-usage/upload/requests")
        val kinds = HashSet<String>()
        for (c in golden.cases) {
            val id = s(c, "id")
            val backend = RecordingBackend()
            when (val kind = s(c, "kind").also { kinds += it }) {
                "monthly" -> backend.service.upsertTokenUsage(
                    "access-token", "u-1", TokenUsageMonthly.decode(c["usage"].toString()), "win:dev-1",
                    account(c["account"]), optLong(c["accountStatus"])?.let { CodexAccountProbeStatus.ofRaw(it.toInt()) },
                    (c["diagnostics"] as? JsonObject)?.let { Json.decodeFromJsonElement(CodexUsageDiagnostics.serializer(), it) },
                )
                "daily" -> backend.service.upsertTokenUsageDaily("access-token", (c["rows"] as JsonArray).map { r ->
                    r as JsonObject
                    TokenUsageDailyUpsertRow(s(r, "userId"), s(r, "day"), s(r, "deviceId"), optLong(r["claudeTotal"]), optLong(r["codexTotal"]),
                        optLong(r["codexUtcTotal"]), optLong(r["codexAccount"]), optLong(r["antigravityTotal"]))
                })
                "heartbeat" -> backend.service.sendTokenScanHeartbeat("access-token", "u-1", s(c, "month"), "win:dev-1",
                    c["files"]!!.jsonPrimitive.int, epoch(c["scannedAtEpoch"]!!.jsonPrimitive.long))
                else -> error("모르는 kind $kind")
            }
            assertEquals(c["requests"], backend.take(), id)
        }
        assertEquals(setOf("monthly", "daily", "heartbeat"), kinds)
    }
}
