// 원본(생성기): Tests/checkTests/GoldenExport/token-usage/GoldenExportAILimit.swift @ a90d8623
// 골든 `token-usage/limits/readers`(Swift parseCredentials·parseUsage·ResetTrust·DateParser·HTTP.failure·Retry-After·문구표) ·
// `token-usage/limits/upload`(값 행·비우는 행 키 집합 동일 · 명시 null · 지문 키 없음 · 중복 PK 접기 · 메인 기기 본문 · 장부 지문).
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSnapshotBundle
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.bits
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import io.ktor.http.HttpMethod
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private fun bits(d: Double?): JsonElement = d?.let { JsonPrimitive(Golden.bitsText(it)) } ?: JsonNull
private fun str(s: String?): JsonElement = s?.let(::JsonPrimitive) ?: JsonNull
private fun obj(vararg pairs: Pair<String, JsonElement>) = JsonObject(linkedMapOf(*pairs))
private fun JsonObject.optString(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
private fun JsonObject.optBits(key: String): Double? = optString(key)?.let(Golden::bits)

private fun errJson(e: AILimitReadError) = obj("failure" to str(e.failure.rawValue), "retryAfterBits" to bits(e.retryAfter))

private fun snapJson(s: AILimitProviderSnapshot) = obj(
    "provider" to str(s.provider.rawValue), "planLabel" to str(s.planLabel), "accountFingerprint" to str(s.accountFingerprint),
    "windows" to JsonArray(s.windows.map {
        obj("window" to str(it.window.rawValue), "usedPercentBits" to bits(it.usedPercent), "resetsAtBits" to bits(it.resetsAt),
            "observedAtBits" to bits(it.observedAt), "source" to str(it.source.rawValue))
    }),
)

private fun <T> outcomeJson(o: AILimitOutcome<T>, ok: (T) -> JsonElement) = when (o) {
    is AILimitOutcome.Ok -> obj("ok" to ok(o.value))
    is AILimitOutcome.Err -> obj("err" to errJson(o.error))
}

class AILimitReaderGoldenTest {
    private val golden = Golden.load("token-usage/limits/readers")

    @Test
    fun readersMatchSwiftBitForBit() {
        val mismatches = mutableListOf<String>()
        val kinds = mutableMapOf<String, Int>()
        for (c in golden.cases) {
            val id = c.string("id")
            val kind = c.string("kind")
            kinds[kind] = (kinds[kind] ?: 0) + 1
            fun check(key: String, actual: JsonElement) {
                if (c[key] != actual) mismatches += "$id.$key: Swift ${c[key]} · Kotlin $actual"
            }
            val input = c.optString("input")?.encodeToByteArray()
            when (kind) {
                "claudeCredentials" -> check("output", outcomeJson(AILimitClaudeReader.parseCredentials(input!!)) {
                    obj("accessToken" to str(it.accessToken), "expiresAtBits" to bits(it.expiresAt?.timeIntervalSince1970), "planLabel" to str(it.planLabel))
                })
                "claudeUsage" -> check("output", outcomeJson(
                    AILimitClaudeReader.parseUsage(input!!, SwiftDate(c.bits("observedAtBits")), c.optString("planLabel")), ::snapJson,
                ))
                "codexCredentials" -> check("output", outcomeJson(AILimitCodexReader.parseCredentials(input!!)) {
                    obj("accessToken" to str(it.accessToken), "accountID" to str(it.accountID), "planLabel" to str(it.planLabel),
                        "expiresAtBits" to bits(it.expiresAt?.timeIntervalSince1970))
                })
                "codexUsage" -> check("output", outcomeJson(
                    AILimitCodexReader.parseUsage(input!!, SwiftDate(c.bits("observedAtBits")), c.optString("fallbackPlanLabel"), c.optString("accountID")),
                    ::snapJson,
                ))
                "resetTrust" -> check("trusts", JsonPrimitive(AILimitResetTrust.trusts(c.bits("usedPercentBits"), c.optBits("resetAfterBits"), c.optBits("windowSecondsBits"))))
                "date" -> check("outBits", bits(AILimitDateParser.date(c.optString("raw"))?.timeIntervalSince1970))
                "httpFailure" -> check("output", AILimitHTTP.failure(c.int("status"), c.optBits("retryAfterBits"))?.let(::errJson) ?: JsonNull)
                "retryAfterHeader" -> check("outBits", bits(AILimitHTTP.retryAfterSeconds(c.string("raw"))))
                "failureTable" -> {
                    val failure = AILimitReadFailure.of(c.string("failure"))!!
                    val provider = AILimitProvider.of(c.string("provider"))!!
                    check("noticeText", str(failure.noticeText(provider)))
                    check("hidesProvider", JsonPrimitive(failure.hidesProvider))
                }
                else -> mismatches += "$id: 모르는 kind $kind"
            }
        }
        println("AINGCHECK-W2H2-READERS cases=${golden.cases.size} kinds=$kinds mismatches=${mismatches.size}")
        assertTrue(mismatches.isEmpty(), mismatches.take(15).joinToString("\n"))
        assertEquals(9, kinds.size, "kind 아홉 벌이 전부 있어야 한다: $kinds")
    }

    @Test
    fun specConstantsMatchSwift() {
        assertEquals(golden.spec.string("claudeUsageURL"), AILimitClaudeReader.usageURL)
        assertEquals(golden.spec.string("claudeBetaHeader"), AILimitClaudeReader.betaHeader)
        assertEquals(golden.spec.string("codexUsageURL"), AILimitCodexReader.usageURL)
        assertEquals(golden.spec.bits("timeoutBits"), AILimitHTTP.timeout)
        assertEquals(golden.spec.string("userAgent"), AILimitHTTP.userAgent("1.2.3", "ai-limits"))
    }
}

class AILimitUploadBodyGoldenTest {
    private val golden = Golden.load("token-usage/limits/upload")

    private fun bundleOf(specs: JsonArray): AILimitSnapshotBundle = AILimitSnapshotBundle(providers = specs.map { e ->
        val p = e.jsonObject
        AILimitProviderSnapshot(
            AILimitProvider.of(p.string("provider"))!!,
            p.array("windows").map { we ->
                val w = we.jsonObject
                // Swift 는 `Date(timeIntervalSince1970:)` 로 굳힌 뒤 읽는다 — 같은 왕복.
                AILimitWindowSnapshot(AILimitWindow.of(w.string("window"))!!, w.bits("usedPercentBits"),
                    w.optBits("resetsAtBits")?.let { SwiftDate(it).timeIntervalSince1970 },
                    SwiftDate(w.bits("observedAtBits")).timeIntervalSince1970, AILimitSource.local)
            },
            p.optString("planLabel"), p.optString("accountFingerprint"),
        )
    })

    private fun rowJson(r: AILimitUpsertRow) = obj(
        "user_id" to str(r.userId), "device_id" to str(r.deviceId), "device_label" to str(r.deviceLabel), "provider" to str(r.provider),
        "five_hour_percent" to bits(r.fiveHourPercent), "five_hour_resets_at" to str(r.fiveHourResetsAt), "weekly_percent" to bits(r.weeklyPercent),
        "weekly_resets_at" to str(r.weeklyResetsAt), "plan_label" to str(r.planLabel), "observed_at" to str(r.observedAt),
    )

    private fun shape(body: ByteArray): JsonArray = JsonArray(Json.parseToJsonElement(body.decodeToString()).jsonArray.map { e ->
        val o = e.jsonObject
        obj("keys" to JsonArray(o.keys.sorted().map(::JsonPrimitive)),
            "nullKeys" to JsonArray(o.filterValues { it is JsonNull }.keys.sorted().map(::JsonPrimitive)))
    })

    @Test
    fun uploadBodiesMatchSwift() {
        val mismatches = mutableListOf<String>()
        val rowKeys = golden.spec.array("rowKeys").map { (it as JsonPrimitive).content }
        assertEquals(rowKeys, AILimitUpsertRow.keys, "열 칸 순서·이름 = Swift CodingKeys")
        var rowsSeen = 0
        for (c in golden.cases) {
            val id = c.string("id")
            fun check(key: String, actual: JsonElement) {
                if (c[key] != actual) mismatches += "$id.$key: Swift ${c[key]} · Kotlin $actual"
            }
            when (c.string("kind")) {
                "rows" -> {
                    val bundle = bundleOf(c.array("bundle"))
                    val rows = AILimitUpload.rows(c.string("userID"), c.string("deviceID"), c.optString("deviceLabel"), bundle,
                        c.array("clearedProviders").map { AILimitProvider.of((it as JsonPrimitive).content)!! }, SwiftDate(c.bits("clearedAtBits")))
                    check("rows", JsonArray(rows.map(::rowJson)))
                    val body = AILimitUpload.body(rows)
                    check("encoded", shape(body))
                    check("fingerprint", JsonPrimitive(AILimitUploadLedger.fingerprint(bundle)))
                    // ④ 계약: 행마다 키 집합이 같고(PGRST102) 지문 칸이 없고 기기 id 는 win:….
                    for (o in Json.parseToJsonElement(body.decodeToString()).jsonArray.map { it.jsonObject }) {
                        assertEquals(rowKeys.sorted(), o.keys.sorted(), "$id: 키 집합")
                        assertFalse("account_fingerprint" in o, "$id: 지문 칸이 본문에 실렸다")
                        assertTrue((o["device_id"] as JsonPrimitive).content.startsWith("win:"), "$id: 기기 id")
                    }
                    rowsSeen += rows.size
                }
                "prefs" -> {
                    val normalized = AILimitMainDeviceIDContract.normalized(c.optString("raw"))
                    check("mainDeviceID", str(normalized))
                    val s = shape(AILimitMainDeviceIDContract.body("u", c.optString("raw")))[0].jsonObject
                    check("keys", s["keys"]!!)
                    check("nullKeys", s["nullKeys"]!!)
                }
                "percentText" -> check("text", JsonPrimitive(AILimitUploadLedger.percentText(c.bits("valueBits"))))
                "percent" -> check("outBits", bits(AILimitUpload.percent(c.bits("valueBits"))))
                "bucket" -> check("bucket", JsonPrimitive(AILimitUploadLedger.observedBucket(SwiftDate(c.bits("secondsBits")).timeIntervalSince1970)))
                else -> mismatches += "$id: 모르는 kind"
            }
        }
        println("AINGCHECK-W2H2-UPLOAD cases=${golden.cases.size} rows=$rowsSeen mismatches=${mismatches.size}")
        assertTrue(mismatches.isEmpty(), mismatches.take(15).joinToString("\n"))
        assertTrue(rowsSeen >= 8, "값 행·비우는 행이 고루 있어야 한다($rowsSeen)")
    }

    @Test
    fun upsertSendsOnePostWithPkConflictAndPrefer() = runTest {
        val http = RecordingHttp(RecordingHttp.ok(""))
        val service = fakeService(http)
        val c = golden.cases.first { it.string("id") == "rows-values-two-providers" }
        val bundle = bundleOf(c.array("bundle"))
        service.upsertAILimits("tok", c.string("userID"), c.string("deviceID"), c.optString("deviceLabel"), bundle, listOf(AILimitProvider.codex),
            SwiftDate(c.bits("clearedAtBits")))
        assertEquals(1, http.requests.size)
        val r = http.requests.single()
        assertEquals(HttpMethod.Post, r.method)
        assertEquals(golden.spec.string("path"), r.url.encodedPath)
        assertEquals(golden.spec.string("onConflict"), r.url.parameters["on_conflict"])
        assertEquals(golden.spec.string("prefer"), r.headers["Prefer"])
        val expected = AILimitUpload.rows(c.string("userID"), c.string("deviceID"), c.optString("deviceLabel"), bundle, listOf(AILimitProvider.codex),
            SwiftDate(c.bits("clearedAtBits")))
        assertEquals(AILimitUpload.body(expected).decodeToString(), r.bodyBytes().decodeToString())
        // 빈 본문이면 요청 0.
        service.upsertAILimits("tok", "u", "win:x", null, AILimitSnapshotBundle(providers = emptyList()), emptyList(), SwiftDate(0.0))
        assertEquals(1, http.requests.size)
        // 메인 기기 되돌리기 = 명시 null 한 행.
        service.upsertAILimitMainDeviceID("tok", "u", null)
        val prefs = http.requests.last()
        assertEquals(golden.spec.string("prefsPath"), prefs.url.encodedPath)
        assertEquals(golden.spec.string("prefsOnConflict"), prefs.url.parameters["on_conflict"])
        assertEquals("""[{"user_id":"u","main_device_id":null}]""", prefs.bodyBytes().decodeToString())
    }
}
