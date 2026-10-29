// 원본: Tests/checkTests/GoldenExport/desktop-ultra/GoldenExportDesktopUltra.swift(골든 생성기) — 골든 contract/golden/desktop-ultra/*.json 을 읽기만 한다
package com.yehsung.aingcheck.feature.desktop.ultra

import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.focus.FocusModeController
import com.yehsung.aingcheck.feature.desktop.focus.FocusStage
import com.yehsung.aingcheck.feature.desktop.focus.FocusStagePolicy
import com.yehsung.aingcheck.feature.desktop.focus.FocusStageRecord
import com.yehsung.aingcheck.feature.desktop.focus.FocusStageRecords
import com.yehsung.aingcheck.feature.desktop.focus.net.updateFocusMode
import com.yehsung.aingcheck.feature.desktop.ultra.net.BuyUltraResponse
import com.yehsung.aingcheck.feature.desktop.ultra.net.MissionProgress
import com.yehsung.aingcheck.feature.desktop.ultra.net.UltraWalletResponse
import com.yehsung.aingcheck.feature.desktop.ultra.net.buyUltra
import com.yehsung.aingcheck.feature.desktop.ultra.net.syncUltraWallet
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.bits
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/** 골든 셋(desktop-ultra/{wallet-apply,focus-stage,requests}) — Swift 가 쓴 표를 Kotlin 구현으로 다시 돌린다. */
class DesktopUltraGoldenTest {
    private fun JsonElement?.longOrNull(): Long? = if (this == null || this is JsonNull) null else jsonPrimitive.long
    private fun JsonElement?.textOrNull(): String? = if (this == null || this is JsonNull) null else jsonPrimitive.content
    private fun since1970(o: JsonObject, key: String): SwiftDate? =
        if (o[key] == null || o[key] is JsonNull) null else SwiftDate(o.bits(key))

    // ---- wallet-apply ----

    @Test
    fun walletApplyMatchesSwift() = runTest {
        val golden = Golden.load("desktop-ultra/wallet-apply")
        var checked = 0
        for (case in golden.cases) {
            val id = case.string("id")
            if (id == "constants") {
                assertEquals(UltraWalletStore.THROTTLE_SECONDS, case.bits("throttleSecondsBits"), "throttle")
                assertEquals(MissionProgress.DEFAULT_TARGET_SECONDS, case["defaultTargetSeconds"]!!.jsonPrimitive.long)
                for (row in case.array("hoursText")) {
                    val o = row.jsonObject
                    assertEquals(o.string("text"), MissionProgress.hoursText(o["seconds"]!!.jsonPrimitive.long), golden.failure(id, "hoursText $o"))
                }
                continue
            }
            val text = case.string("response")
            val decoded = runCatching { SwiftJson.decode(UltraWalletResponse.Serializer, text) }
            val expectError = case["decodeError"]!!.jsonPrimitive.boolean
            assertEquals(expectError, decoded.isFailure, golden.failure(id, "decodeError — ${decoded.exceptionOrNull()}"))
            if (expectError) continue
            val response = decoded.getOrThrow()
            val prior = case.obj("prior")
            val judgment = SwiftRuleLapJudgment()
            var charged = 0
            val clock = TestClock()
            val store = UltraWalletStore(
                host = FakeSessionHost(FakeServer(this).service(clock::now)),
                workState = InMemoryDesktopWorkState(),
                lapJudgment = judgment,
                chargedSink = { charged += 1 },
                scope = this,
                clock = clock::now,
                initial = UltraWalletState(
                    balance = prior["balance"].longOrNull(),
                    balanceCap = prior["cap"].longOrNull(),
                    unlimited = prior["unlimited"]!!.jsonPrimitive.boolean,
                    failed = prior["failed"]!!.jsonPrimitive.boolean,
                    missionTargetSeconds = prior["missionTargetSeconds"].longOrNull(),
                ),
            )
            store.apply(response)
            val s = store.state.value
            val after = case.obj("after")
            fun check(key: String, actual: Any?, expected: Any?) = assertEquals(expected, actual, golden.failure(id, key))
            check("balance", s.balance, after["balance"].longOrNull())
            check("cap", s.balanceCap, after["cap"].longOrNull())
            check("unlimited", s.unlimited, after["unlimited"]!!.jsonPrimitive.boolean)
            check("failed", s.failed, after["failed"]!!.jsonPrimitive.boolean)
            check("missionsLoaded", s.missionsLoaded, after["missionsLoaded"]!!.jsonPrimitive.boolean)
            check("streakDays", s.streakDays, after["streakDays"]!!.jsonPrimitive.int)
            check("streakIncludesToday", s.streakIncludesToday, after["streakIncludesToday"]!!.jsonPrimitive.boolean)
            check("missionNotice", s.missionNotice, after["missionNotice"].textOrNull())
            check("charged", charged, after["charged"]!!.jsonPrimitive.int)
            check("missionTargetSeconds", s.missionTargetSeconds, after["missionTargetSeconds"].longOrNull())
            check("isUnlimited", response.isUnlimited, after["isUnlimited"]!!.jsonPrimitive.boolean)
            check("rubyMissionGrant", response.rubyMissionGrant, after["rubyMissionGrant"].longOrNull())
            val rows = after.array("missions")
            check("missions.size", s.missions.size, rows.size)
            for ((i, row) in rows.withIndex()) {
                val o = row.jsonObject
                val m = s.missions[i]
                check("missions[$i].kind", m.kind.raw, o.string("kind"))
                check("missions[$i].progress", m.progress, if (o["progress"] is JsonNull) null else o.bits("progress"))
                check("missions[$i].claimed", m.claimedToday, o["claimed"]!!.jsonPrimitive.boolean)
                check("missions[$i].capped", m.cappedToday, o["capped"]!!.jsonPrimitive.boolean)
                check("missions[$i].detail", m.detail, o.string("detail"))
                check("missions[$i].laps", m.lapsGrantedToday, o["laps"]!!.jsonPrimitive.int)
                check("missions[$i].pending", m.isPending, o["pending"]!!.jsonPrimitive.boolean)
            }
            checked += 1
        }
        assertTrue(checked >= 25, "골든 케이스가 너무 적다: $checked")
    }

    // ---- focus-stage ----

    @Test
    fun focusStageMatchesSwift() = runTest {
        val golden = Golden.load("desktop-ultra/focus-stage")
        for (case in golden.cases) {
            val id = case.string("id")
            when (id) {
                "record-keys" -> for (row in case.array("keys")) {
                    val o = row.jsonObject
                    assertEquals(o.string("key"), FocusStageRecords.key(o.string("userID")), golden.failure(id, o.string("userID")))
                }
                "constants" -> {
                    assertEquals(FocusStagePolicy.TIMED_DURATION_SECONDS, case.bits("timedDurationBits"))
                    assertEquals(FocusStagePolicy.EXPIRY_RETRY_SECONDS, case.bits("expiryRetryBits"))
                    assertEquals(FocusStagePolicy.CHANGE_FAILED_NOTICE, case.string("changeFailedNotice"))
                    assertEquals(case.array("stageRaw").map { it.jsonPrimitive.content }, FocusStage.entries.map { it.raw })
                }
                else -> {
                    val now = since1970(case, "now")!!
                    val record = (case["record"] as? JsonObject)?.let { r ->
                        FocusStageRecord(FocusStage.fromRaw(r.string("stage"))!!, since1970(r, "until"))
                    }
                    assertEquals(case.string("stageServerOn"), FocusStagePolicy.stage(true, record) { now }.raw, golden.failure(id, "serverOn"))
                    assertEquals(case.string("stageServerOff"), FocusStagePolicy.stage(false, record) { now }.raw, golden.failure(id, "serverOff"))
                    val expired = case["isExpired"]
                    if (record != null) {
                        assertEquals(expired!!.jsonPrimitive.boolean, FocusStagePolicy.isExpired(record) { now }, golden.failure(id, "isExpired"))
                    }
                    // 컨트롤러(Swift store 자리) — 기록을 칸에 넣고 집중 값을 켜기 전·후로 단계와 화면 칸을 읽는다.
                    val kv = InMemoryDesktopKeyValueStore()
                    FocusStageRecords(kv).write(record, TEST_USER)
                    val host = FakeSessionHost(FakeServer(this).service { now }, user = null)
                    val focus = FocusModeController(host, kv, this, { now })
                    host.session = com.yehsung.aingcheck.core.wire.SupabaseSession("access-token", null, TEST_USER)
                    assertEquals(case.string("storeStageFocusOff"), focus.focusStage(now).raw, golden.failure(id, "store off"))
                    host.session = null
                    focus.setFocusMode(true) // 세션 없음 = 값만 바꾼다(요청 0)
                    host.session = com.yehsung.aingcheck.core.wire.SupabaseSession("access-token", null, TEST_USER)
                    assertEquals(case.string("storeStageFocusOn"), focus.focusStage(now).raw, golden.failure(id, "store on"))
                    val face = focus.focusStageFace(now)
                    val f = case.obj("face")
                    assertEquals(f.string("stage"), face.stage.raw, golden.failure(id, "face.stage"))
                    assertEquals(f["remainingSeconds"].longOrNull()?.toInt(), face.remainingSeconds, golden.failure(id, "face.remaining"))
                }
            }
        }
    }

    // ---- requests ----

    @Test
    fun requestsMatchSwift() = runTest {
        val golden = Golden.load("desktop-ultra/requests")
        val server = FakeServer(this)
            .on("POST", WALLET_PATH, walletOk())
            .on("POST", BUY_PATH, Reply.Json("""{"status":"ok"}"""))
            .on("PATCH", PROFILES_PATH, Reply.Json("", 204))
        val clock = TestClock()
        val service = server.service(clock::now)
        service.syncUltraWallet("access-token")
        service.syncUltraWallet("access-token", daysBack = 0)
        service.syncUltraWallet("access-token", daysBack = 7)
        service.buyUltra("access-token", 1)
        service.buyUltra("access-token", 3)
        service.updateFocusMode("access-token", TEST_USER, true)
        service.updateFocusMode("access-token", TEST_USER, false)
        val calls = server.calls
        val labels = listOf("wallet-default", "wallet-0", "wallet-7", "buy-1", "buy-3", "focus-on", "focus-off")
        assertEquals(labels.size, calls.size)
        for (case in golden.cases) {
            val id = case.string("id")
            when {
                id in labels -> {
                    val call = calls[labels.indexOf(id)]
                    assertEquals(case.string("method"), call.method, golden.failure(id, "method"))
                    assertEquals(case.string("path"), call.path, golden.failure(id, "path"))
                    val query = case.array("query").map { it.jsonArray.let { p -> p[0].jsonPrimitive.content to p[1].jsonPrimitive.content } }
                    assertEquals(query, call.query, golden.failure(id, "query"))
                    assertEquals(case["prefer"].textOrNull(), call.header("Prefer"), golden.failure(id, "prefer"))
                    assertEquals(case.string("body"), call.body, golden.failure(id, "body bytes"))
                }
                id.startsWith("buy-") -> {
                    val decoded = runCatching { SwiftJson.decode(BuyUltraResponse.serializer(), case.string("response")) }
                    val expectError = case["decodeError"]!!.jsonPrimitive.boolean
                    assertEquals(expectError, decoded.isFailure, golden.failure(id, "decodeError ${decoded.exceptionOrNull()}"))
                    if (expectError) continue
                    val r = decoded.getOrThrow()
                    val o = case.obj("decoded")
                    assertEquals(o.string("status"), r.status, golden.failure(id, "status"))
                    assertEquals(
                        listOf("ultraBalance", "rubyBalance", "need", "have", "unit", "count", "max").map { o[it].longOrNull() },
                        listOf(r.ultraBalance, r.rubyBalance, r.need, r.have, r.unit, r.count, r.max),
                        golden.failure(id, "fields"),
                    )
                }
                id == "shortfall" -> for (row in case.array("rows")) {
                    val o = row.jsonObject
                    assertEquals(o.string("text"), SharedText.shortfallNotice(o["need"].longOrNull(), o["have"].longOrNull()), golden.failure(id, "$o"))
                }
                else -> fail("모르는 케이스 $id")
            }
        }
        // buy 안내도 같은 문구표를 쓴다(insufficient → shortfall) — 구매 경로 한 번.
        val ruby = RubyBalanceCell(12)
        val purchase = UltraPurchase(FakeSessionHost(service), ruby, UltraWalletStore(
            FakeSessionHost(service), InMemoryDesktopWorkState(), SwiftRuleLapJudgment(), {}, this, clock::now,
        ), this, { 10 })
        purchase.apply(BuyUltraResponse(status = "insufficient"), count = 3)
        assertEquals(SharedText.shortfallNotice(30, 12), purchase.notice.value)
    }
}
