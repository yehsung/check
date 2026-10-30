// W2-h3 업로드 게이트 — 깃발(DesktopAppConfig.tokenUpload) · 세션 · 기기 키 · 수집 · 옛 표 0 · 월간→일별 순서 · 진단 도장.
// tokens.md §5 TokenUploadGateTest. 규약 번호는 TokenUploadCoordinator 의 ★1~★6.
package com.yehsung.aingcheck.feature.desktop.tokens.upload

import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountProbeStatus
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexDiagnosticsStamp
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TokenUploadGateTest {
    private val now = epoch(1_793_322_123)               // 2026-10-30T01:02:03Z = KST 10:02
    private val usage = TokenUsageMonthly(month = "2026-10", claudeInput = 1000, codexInput = 50, windowStart = "2026-08-08",
        claudeDaily = mapOf("2026-10-29" to 900L, "2026-10-30" to 100L), codexDaily = mapOf("2026-10-30" to 50L))

    private class Rig(config: DesktopAppConfig, device: String? = "win:dev-1", collect: Boolean = true, signedIn: Boolean = true,
                      statusFor: (String) -> Int = { 201 }) {
        val backend = RecordingBackend(statusFor)
        val host = FakeSessionHost(backend.service).also { if (!signedIn) it.current = null }
        val store = InMemoryDesktopKeyValueStore()
        var diagCalls = 0
        val coordinator = TokenUploadCoordinator(config, host, { device }, { collect }, store, appBuild = 1,
            computeDiagnostics = { _, build -> diagCalls += 1; CodexUsageDiagnostics(filesTotal = 3, appBuild = build) })
    }

    private suspend fun Rig.everything(at: com.yehsung.aingcheck.core.wire.SwiftDate) {
        coordinator.uploadTokenUsageIfNeeded(usage, null, CodexAccountProbeStatus.NOT_LOGGED_IN, at)
        coordinator.uploadTokenUsageDailyIfNeeded(usage, null, host.sessionGeneration, at)
        coordinator.sendTokenScanHeartbeatIfNeeded(at, 7, at)
    }

    @Test
    fun rule1_defaultConfigKeepsTokenUploadClosed() {
        assertFalse(DesktopAppConfig().tokenUpload, "tokenUpload 기본값은 false(서버 ④·⑥ 전) — 기본을 true 로 바꾸지 마라")
    }

    @Test
    fun rule1_flagOffMeansZeroTokenUsageWritesEvenWithSessionDeviceAndCollect() = runTest {
        val rig = Rig(DesktopAppConfig())
        rig.everything(now)
        rig.everything(now.addingTimeInterval(3600.0))
        assertEquals(emptyList(), rig.backend.paths(), "깃발 꺼짐인데 token_usage_* 요청이 나갔다")
        assertEquals(0, rig.diagCalls, "깃발 꺼짐인데 진단 전량 순회를 돌았다")
        assertNull(rig.store.getString(CodexDiagnosticsStamp.KEY))
    }

    @Test
    fun rule2_missingDeviceIdSessionOrCollectMeansZero() = runTest {
        for (rig in listOf(Rig(DesktopAppConfig(tokenUpload = true), device = null), Rig(DesktopAppConfig(tokenUpload = true), signedIn = false),
                           Rig(DesktopAppConfig(tokenUpload = true), collect = false))) {
            rig.everything(now)
            assertEquals(emptyList(), rig.backend.paths())
        }
    }

    @Test
    fun rule3_flagOnSendsMonthlyThenDailyThenHeartbeat_neverTheLegacyTable() = runTest {
        val rig = Rig(DesktopAppConfig(tokenUpload = true))
        rig.everything(now)
        assertEquals(listOf(TokenUploadPaths.DEVICE_MONTHLY, TokenUploadPaths.DEVICE_DAILY, TokenUploadPaths.DEVICE_MONTHLY), rig.backend.paths())
        val requests = rig.backend.take().map { it as JsonObject }
        assertTrue(requests.all { (it["path"].toString()).let { p -> "token_usage_device_" in p } }, "★6 옛 표 요청이 섞였다")
        val monthly = requests[0]["body"] as JsonObject
        assertEquals("1", monthly["codex_diag_build"].toString(), "진단 빌드 = Windows 빌드 1")
        assertEquals("3", monthly["codex_account_status"].toString())
        assertFalse("codex_account_month" in monthly, "미로그인이면 스냅샷 키를 싣지 않는다")
        val heartbeat = requests[2]["body"] as JsonObject
        assertEquals(setOf("user_id", "month", "device_id", "last_scan_at", "scan_files"), heartbeat.keys)
        // ★5 도장은 성공 뒤 · 같은 KST 날짜엔 다시 계산하지 않는다.
        assertEquals("1:2026-10-30", rig.store.getString(CodexDiagnosticsStamp.KEY))
        rig.coordinator.uploadTokenUsageIfNeeded(usage.copy(claudeInput = 2000), null, null, now.addingTimeInterval(120.0))
        assertEquals(1, rig.diagCalls)
        val second = rig.backend.take().map { it as JsonObject }
        assertFalse((second[0]["body"] as JsonObject).keys.any { it.startsWith("codex_diag_") }, "도장이 같은 날 진단을 다시 실었다")
    }

    @Test
    fun rule2_sixtySecondThrottleAndAttemptStampFirst() = runTest {
        val rig = Rig(DesktopAppConfig(tokenUpload = true), statusFor = { 500 })
        rig.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now)
        assertEquals(1, rig.backend.paths().size)
        assertEquals(now, rig.coordinator.lastTokenUploadAt, "실패해도 시도 시각은 먼저 찍힌다")
        assertNull(rig.store.getString(CodexDiagnosticsStamp.KEY), "전송 실패인데 진단 도장을 찍었다")
        rig.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now.addingTimeInterval(30.0))
        assertEquals(1, rig.backend.paths().size, "60초 안 재시도")
        rig.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now.addingTimeInterval(61.0))
        assertEquals(2, rig.backend.paths().size)
    }

    @Test
    fun rule3_dailyFailureIsIndependentAndRetriedNextCycle() = runTest {
        val rig = Rig(DesktopAppConfig(tokenUpload = true), statusFor = { if (it == TokenUploadPaths.DEVICE_DAILY) 500 else 201 })
        rig.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now)
        assertEquals(usage, rig.coordinator.lastUploadedUsage, "월간은 일별 실패와 독립")
        assertTrue(rig.coordinator.tokenDailyRetryPending)
        assertTrue(rig.coordinator.lastUploadedDaily.isEmpty())
        rig.backend.take()
        rig.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now.addingTimeInterval(61.0))
        assertEquals(listOf(TokenUploadPaths.DEVICE_MONTHLY, TokenUploadPaths.DEVICE_DAILY), rig.backend.paths(), "값이 그대로여도 일별 재시도")
    }

    @Test
    fun zeroUsageAndNoAccountSendsNothingButHeartbeatStillGoes() = runTest {
        val rig = Rig(DesktopAppConfig(tokenUpload = true))
        rig.coordinator.uploadTokenUsageIfNeeded(TokenUsageMonthly(month = "2026-10"), null, null, now)
        assertEquals(emptyList(), rig.backend.paths())
        rig.coordinator.sendTokenScanHeartbeatIfNeeded(now, 0, now)
        rig.coordinator.sendTokenScanHeartbeatIfNeeded(now, 0, now.addingTimeInterval(5.0))
        assertEquals(listOf(TokenUploadPaths.DEVICE_MONTHLY), rig.backend.paths(), "같은 스캔 시각은 한 번만")
    }
}
