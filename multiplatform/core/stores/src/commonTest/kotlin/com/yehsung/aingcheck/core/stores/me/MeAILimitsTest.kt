// 원본: Tests/CheckMobileKitTests/MeAILimitsTests.swift · MeAILimitDeviceTests.swift · V0347AILimitClearedRowTests.swift(읽기만 · 기기 묶음 · 정규화) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.AILimitServerRow
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MeAILimitsTest {
    /** 기준 시각(05:05Z)에 가까운 관측 행. */
    private fun row(
        device: String?, provider: String, five: Double?, weekly: Double?, observed: String = "2026-09-17T05:03:00.128+00:00",
        label: String? = null, plan: String? = null,
    ): String {
        fun s(v: String?) = v?.let { "\"$it\"" } ?: "null"
        return """{"device_id":${s(device)},"device_label":${s(label)},"provider":"$provider","five_hour_percent":${five ?: "null"},
            "five_hour_resets_at":"2026-09-17T07:40:00+00:00","weekly_percent":${weekly ?: "null"},"weekly_resets_at":"2026-09-22T10:05:00+00:00",
            "plan_label":${s(plan)},"observed_at":"$observed"}"""
    }

    // ④ AI 리밋은 읽기만 한다

    @Test
    fun aiLimitsAreReadOnlyAcrossLoadRefreshAndReset() = runTest {
        val rows = "[" + listOf(
            row("mac-a", "claude", 27.0, 60.0, label = "사무실 iMac"),
            row("mac-b", "codex", 10.0, 56.0, label = "집 MacBook"),
        ).joinToString(",") + "]"
        val h = MeHarness(this) { r ->
            when {
                r.method == "GET" && r.path == "/rest/v1/ai_limits" -> MeReply.Json(rows)
                r.method == "GET" && r.path == "/rest/v1/ai_limits_prefs" -> MeReply.Json("""[{"main_device_id":"mac-b"}]""")
                else -> null
            }
        }
        h.signIn()
        h.store.aiLimits.refreshIfStale()
        advanceUntilIdle()
        h.store.aiLimits.load()
        advanceUntilIdle()
        h.store.aiLimits.reset()
        h.store.aiLimits.refreshIfStale()
        advanceUntilIdle()

        val limitRequests = h.server.requests.filter { it.path.startsWith("/rest/v1/ai_limits") }
        assertEquals(6, limitRequests.size, "맥 둘 → 조회마다 GET 둘(행 · 고른 맥)")
        assertEquals(setOf("GET"), limitRequests.map { it.method }.toSet(), "폰은 ai_limits · ai_limits_prefs 를 쓰지 않는다")
        assertTrue(h.server.requests.none { it.rpcName?.contains("limit") == true }, "리밋 RPC 도 없다")
        val select = limitRequests.first { it.path == "/rest/v1/ai_limits" }.queryValue("select")
        assertEquals("device_id,device_label,provider,five_hour_percent,five_hour_resets_at,weekly_percent,weekly_resets_at,plan_label,observed_at", select)
        assertEquals("mac-b", h.store.aiLimits.mainDeviceID)
        h.assertClean()
    }

    @Test
    fun singleMacAsksNoPrefsAndWidgetCarriesNoDeviceName() = runTest {
        val h = MeHarness(this) { r ->
            if (r.method == "GET" && r.path == "/rest/v1/ai_limits") MeReply.Json("[" + row("mac-a", "claude", 27.0, 60.0, label = "iMac") + "]") else null
        }
        h.signIn()
        h.store.aiLimits.load()
        advanceUntilIdle()
        assertEquals(0, h.server.requests.count { it.path == "/rest/v1/ai_limits_prefs" }, "한 대뿐이면 고른 맥을 묻지 않는다")
        assertFalse(h.store.aiLimits.showsDeviceNames)
        val panel = assertNotNull(h.links.panels.lastOrNull(), "받은 뒤 지금 탭에 넘긴다")
        assertNull(panel.deviceName)
        assertEquals(listOf("claude"), panel.providers.map { it.provider })
        assertEquals(27.0, panel.providers.single().fiveHourPercent, "날것 값을 싣는다")
        h.assertClean()
    }

    @Test
    fun prefsReadFailureKeepsTheChosenMacButANullAnswerClearsIt() = runTest {
        var prefs: MeReply = MeReply.Json("""[{"main_device_id":"mac-a"}]""")
        val rows = "[" + row("mac-a", "claude", 27.0, null) + "," + row("mac-b", "claude", 91.0, null) + "]"
        val h = MeHarness(this) { r ->
            when {
                r.method == "GET" && r.path == "/rest/v1/ai_limits" -> MeReply.Json(rows)
                r.method == "GET" && r.path == "/rest/v1/ai_limits_prefs" -> prefs
                else -> null
            }
        }
        h.signIn()
        h.store.aiLimits.load()
        advanceUntilIdle()
        assertEquals("mac-a", h.store.aiLimits.mainDeviceID)
        prefs = MeReply.serverDown
        h.store.aiLimits.load()
        advanceUntilIdle()
        assertEquals("mac-a", h.store.aiLimits.mainDeviceID, "못 읽었다 — 지킨다(위젯이 다른 맥으로 튀지 않게)")
        assertTrue(h.store.aiLimits.state.hasLoaded && !h.store.aiLimits.state.hasFailed, "둘째 조회 실패가 카드를 비우지 않는다")
        prefs = MeReply.Json("[]")
        h.store.aiLimits.load()
        advanceUntilIdle()
        assertNull(h.store.aiLimits.mainDeviceID, "읽었고 안 골랐다 — 그 사실을 반영한다")
        h.assertClean()
    }

    // fetchMyAILimits 결과 정규화

    @Test
    fun normalizationDropsRowsWithoutDeviceOrObservationAndFoldsLabels() {
        val wide = "가".repeat(70)
        val rows = listOf(
            AILimitServerRow(deviceId = "  mac-a\n", deviceLabel = "  사무실 iMac  ", provider = "claude", fiveHourPercent = 27.0,
                fiveHourResetsAt = "2026-09-17T07:40:00.434051+00:00", weeklyPercent = null, weeklyResetsAt = "2026-09-22T10:05:00Z",
                planLabel = " max ", observedAt = "2026-09-17T05:03:00.128+00:00"),
            AILimitServerRow(deviceId = "mac-b", deviceLabel = wide, provider = "codex", planLabel = "x".repeat(33), observedAt = "2026-09-17T05:00:00+00:00"),
            AILimitServerRow(deviceId = "   ", provider = "claude", observedAt = "2026-09-17T05:00:00+00:00"),
            AILimitServerRow(deviceId = null, provider = "claude", observedAt = "2026-09-17T05:00:00+00:00"),
            AILimitServerRow(deviceId = "mac-c", provider = "claude", observedAt = "어제"),
        )
        val out = MeAILimitsService.normalized(rows)
        assertEquals(listOf("mac-a", "mac-b"), out.map { it.deviceID }, "빈 기기 · 못 읽은 관측은 버린다(기기 신원을 지어내지 않는다)")
        val a = out[0]
        assertEquals("사무실 iMac", a.deviceLabel)
        assertEquals("max", a.planLabel)
        assertEquals(SwiftDate(1_789_621_380.128), a.observedAt, "소수초 있는 모양")
        assertEquals(SwiftDate(1_789_630_800.434), a.fiveHourResetsAt, "마이크로초는 밀리초로 자른다(Swift 포매터)")
        assertEquals(SwiftDate(1_790_071_500.0), a.weeklyResetsAt, "Z · 소수초 없는 모양도 읽는다")
        val b = out[1]
        assertEquals(64, MeText.scalarCount(b.deviceLabel!!), "이름은 64 스칼라에서 자른다(버리지 않는다)")
        assertNull(b.planLabel, "플랜 라벨은 32 를 넘으면 버린다(잘라서 반쯤 남은 라벨보다 없는 쪽이 정직하다)")
    }

    // 기기 묶음 · 대체 안내

    @Test
    fun ghostAndClearedRowsDisappearAndASubstitutedMainMacIsNamed() = runTest {
        val rows = "[" + listOf(
            row("mac-a", "claude", null, null, label = "Mac mini"), // 맥 설정에서 끈 제공자(값 전부 null)
            row("mac-b", "claude", 40.0, 70.0, label = "Mac mini"),
            row("mac-b", "future-provider", 99.0, 99.0, label = "Mac mini"), // 모르는 제공자
            row("mac-c", "codex", 5.0, 5.0, observed = "2026-09-14T05:05:00+00:00", label = "옛 맥"), // 3일 = 유령
        ).joinToString(",") + "]"
        val h = MeHarness(this) { r ->
            when {
                r.method == "GET" && r.path == "/rest/v1/ai_limits" -> MeReply.Json(rows)
                r.method == "GET" && r.path == "/rest/v1/ai_limits_prefs" -> MeReply.Json("""[{"main_device_id":"mac-a"}]""")
                else -> null
            }
        }
        h.signIn()
        h.store.aiLimits.load()
        advanceUntilIdle()
        val limits = h.store.aiLimits
        assertEquals(listOf("mac-b"), limits.displayGroups.map { it.device.deviceID }, "끈 맥 · 유령 맥은 묶음이 서지 않는다")
        assertEquals(listOf(AILimitProvider.claude), limits.displayRows.map { it.provider }, "모르는 제공자는 버린다")
        assertEquals(3, limits.roster.size, "명부는 걸러내기 전 행들로(맥 설정과 같은 입력)")
        assertTrue(limits.isShowingSubstituteDevice, "고른 맥(mac-a)이 조용해서 다른 맥을 그린다")
        assertTrue(limits.showsDeviceNames, "묶음이 하나여도 대체면 이름을 적는다")
        assertEquals("Mac mini", limits.displayGroups.single().name, "보이는 묶음 사이에서만 겹침을 가른다(꼬리 없음)")
        val panel = h.links.panels.last()
        assertEquals("Mac mini", panel.deviceName)
        assertNull(panel.deviceNameTail)
        assertNotNull(limits.fiveHourSummary)
        assertNotNull(limits.displayRows.single().display(AILimitWindow.fiveHour), "5시간 창이 있는 줄은 그 값을 그린다")
        h.assertClean()
    }

    @Test
    fun quietSecondMacStillAsksForTheChosenMacSoTheVisibleChoiceIsNotCalledASubstitute() = runTest {
        // 맥 둘 중 하나(mac-a)가 조용하다 — 그릴 묶음은 하나뿐이지만 명부는 둘이라 고른 맥을 **묻는다**(P1: groups.count 로 세면 안 묻는다).
        val rows = "[" + row("mac-a", "claude", null, null, label = "Mac mini") + "," + row("mac-b", "claude", 40.0, 70.0, label = "Mac mini") + "]"
        val h = MeHarness(this) { r ->
            when {
                r.method == "GET" && r.path == "/rest/v1/ai_limits" -> MeReply.Json(rows)
                r.method == "GET" && r.path == "/rest/v1/ai_limits_prefs" -> MeReply.Json("""[{"main_device_id":"mac-b"}]""")
                else -> null
            }
        }
        h.signIn()
        h.store.aiLimits.load()
        advanceUntilIdle()
        assertEquals(1, h.server.requests.count { it.path == "/rest/v1/ai_limits_prefs" })
        assertFalse(h.store.aiLimits.isShowingSubstituteDevice, "고른 맥(mac-b)을 멀쩡히 그리는 사람에게 대체 안내를 띄우지 않는다")
        assertFalse(h.store.aiLimits.showsDeviceNames, "보여 줄 맥이 아는 그 맥 하나뿐 — 이름 없음")
        assertNull(h.links.panels.last().deviceName)
        h.assertClean()
    }

    @Test
    fun twinMacsGetTailsAndTheWidgetCarriesTheTailSeparately() = runTest {
        val rows = "[" + row("aaaa-1111", "claude", 10.0, 20.0, label = "Mac mini") + "," +
            row("bbbb-2222", "claude", 30.0, 40.0, observed = "2026-09-17T05:04:00+00:00", label = "Mac mini") + "]"
        val h = MeHarness(this) { r ->
            when {
                r.method == "GET" && r.path == "/rest/v1/ai_limits" -> MeReply.Json(rows)
                r.method == "GET" && r.path == "/rest/v1/ai_limits_prefs" -> MeReply.Json("[]")
                else -> null
            }
        }
        h.signIn()
        h.store.aiLimits.load()
        advanceUntilIdle()
        val groups = h.store.aiLimits.displayGroups
        assertEquals(listOf("bbbb-2222", "aaaa-1111"), groups.map { it.device.deviceID }, "최근에 일한 맥 먼저")
        assertEquals(listOf("2222", "1111"), groups.map { it.nameParts.tail })
        val panel = h.links.panels.last()
        assertEquals("Mac mini (2222)", panel.deviceName, "안 골랐으면 가장 최근 맥")
        assertEquals("2222", panel.deviceNameTail)
        assertEquals(listOf(30.0), panel.providers.map { it.fiveHourPercent })
    }
}
