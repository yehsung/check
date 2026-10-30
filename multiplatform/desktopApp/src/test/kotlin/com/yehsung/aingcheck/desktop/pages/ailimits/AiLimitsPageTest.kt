package com.yehsung.aingcheck.desktop.pages.ailimits

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitOutcome
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitReadError
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitReadFailure
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitReadOutcome
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitStore
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 합성 리밋 장면 — 스냅숏 시험도 같은 장면을 쓴다. */
object AiLimitsFixture {
    /** 2026-10-15T05:00:00Z = 서울 오후 2:00. */
    val now: SwiftDate = SwiftDate.fromEpochMillis(1_792_040_400_000)
    val seoul: ZoneId = ZoneId.of("Asia/Seoul")
    private val t = now.timeIntervalSince1970

    class FakeActions(private val store: AILimitStore) : AiLimitsActions {
        val calls = mutableListOf<String>()
        override suspend fun setVisible(enabled: Boolean) { calls += "visible:$enabled"; store.setMasterEnabled(enabled) }
        override suspend fun setProviderEnabled(provider: AILimitProvider, enabled: Boolean) { calls += "provider:${provider.rawValue}:$enabled"; store.setProviderEnabled(provider, enabled) }
        override suspend fun loadDevices(force: Boolean) { calls += "load" }
        override suspend fun setMainDevice(deviceID: String) { calls += "main:$deviceID"; store.setMainDeviceLocally(deviceID) }
    }

    fun store(codexFails: Boolean = true, devices: Int = 3): AILimitStore {
        val store = AILimitStore(InMemoryDesktopKeyValueStore(), { now }, { "DESK-01" }, { _, _ -> AILimitReadOutcome() })
        val claude = AILimitProviderSnapshot(
            provider = AILimitProvider.claude,
            windows = listOf(
                AILimitWindowSnapshot(AILimitWindow.fiveHour, 42.0, t + 5_400, t - 30, AILimitSource.local),
                AILimitWindowSnapshot(AILimitWindow.weekly, 91.0, t + 3 * 86_400, t - 30, AILimitSource.local),
            ),
            planLabel = "Max",
        )
        val codex = AILimitProviderSnapshot(
            provider = AILimitProvider.codex,
            windows = listOf(AILimitWindowSnapshot(AILimitWindow.fiveHour, 71.0, t + 600, t - 30, AILimitSource.local)),
        )
        val results = buildMap {
            put(AILimitProvider.claude, AILimitOutcome.Ok(claude))
            put(AILimitProvider.codex, if (codexFails) AILimitOutcome.Err(AILimitReadError(AILimitReadFailure.expired)) else AILimitOutcome.Ok(codex))
        }
        store.apply(AILimitReadOutcome(results), now)
        val all = listOf(
            AILimitDevice("win:aaaa1111", "DESK-01", t - 60),
            AILimitDevice("mac:bbbb2222", "MacBook", t - 3_600),
            AILimitDevice("win:cccc3333", "DESK-01", t - 7_200),
        ).take(devices)
        store.applyDevices(all, null, now)
        return store
    }
}

class AiLimitsPageTest {
    @Test
    fun cardModelFollowsMacRowsAndNotice() {
        val store = AiLimitsFixture.store()
        val models = AiLimitCardModel.all(store, AiLimitsFixture.now, AiLimitsFixture.seoul)
        assertEquals(listOf(AILimitProvider.claude, AILimitProvider.codex), models.map { it.provider })
        val claude = models[0]
        assertEquals("42%", claude.display(AILimitWindow.fiveHour)?.valueText)
        assertEquals(AiLimitTint.NORMAL, AiLimitTint.of(claude.display(AILimitWindow.fiveHour)?.percent))
        assertEquals(AiLimitTint.DANGER, AiLimitTint.of(claude.display(AILimitWindow.weekly)?.percent))
        assertEquals("오후 3:30 리셋", claude.resetTexts[AILimitWindow.fiveHour])
        assertEquals("${AILimitProvider.claude.displayName} Max", claude.tooltipLines.first())
        val codex = models[1]
        assertTrue(codex.saysNothingButNotice, "읽기 실패만 있으면 알림 한 줄")
        assertEquals("코덱스를 한 번 실행해 주세요", codex.notice)
        assertTrue(AiLimitsRouteRule.showsRoute(store))
    }

    @Test
    fun tintThresholdsAreWholePercent() {
        assertEquals(AiLimitTint.NONE, AiLimitTint.of(null))
        assertEquals(AiLimitTint.NORMAL, AiLimitTint.of(69.4))
        assertEquals(AiLimitTint.WARN, AiLimitTint.of(70.0))
        assertEquals(AiLimitTint.WARN, AiLimitTint.of(89.0))
        assertEquals(AiLimitTint.DANGER, AiLimitTint.of(90.0))
    }

    @Test
    fun resetTextOnlyForFutureAndNotForResetClaim() {
        val store = AiLimitsFixture.store(codexFails = false)
        val codex = AiLimitCardModel.make(store, AILimitProvider.codex, AiLimitsFixture.now, AiLimitsFixture.seoul)
        assertEquals("오후 2:10 리셋", codex.resetTexts[AILimitWindow.fiveHour])
        assertNull(codex.display(AILimitWindow.weekly))
        assertTrue(codex.tooltipLines.contains("${AILimitWindow.weekly.displayName} ${AiLimitCardModel.ABSENT_VALUE_TEXT}"))
        val later = SwiftDate.fromEpochMillis(1_792_040_400_000 + 3_600_000)
        val d = store.display(AILimitProvider.codex, AILimitWindow.fiveHour, later)
        assertNull(AiLimitCardModel.resetText(d, later, AiLimitsFixture.seoul), "지난 리셋 시각은 글자로 내지 않는다")
    }

    @Test
    fun masterOffHidesRouteAndRows() {
        val store = AiLimitsFixture.store()
        store.setMasterEnabled(false)
        assertFalse(AiLimitsRouteRule.showsRoute(store))
        assertTrue(AiLimitCardModel.all(store, AiLimitsFixture.now, AiLimitsFixture.seoul).isEmpty())
        assertEquals(listOf(AILimitProvider.claude, AILimitProvider.codex), store.configurableProviders, "끈 동안에도 되켤 줄은 남는다")
    }
}
