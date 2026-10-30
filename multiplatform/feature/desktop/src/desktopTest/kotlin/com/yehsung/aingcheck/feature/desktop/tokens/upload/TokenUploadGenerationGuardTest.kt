// W2-h3 세대 가드 — 요청이 날아가는 사이 계정이 바뀌면(로그아웃·전환 = sessionGeneration 증가) 옛 세션의 응답으로
// 이 기기 장부(lastUploadedUsage·계정 키·일별 기준선·재시도 깃발·하트비트 시각·내 행·스키마 신호)를 바꾸지 않는다.
// TokenUploadCoordinator 의 가드 여섯 곳 G1~G6 ↔ Swift WorkTimerStoreSync.swift(2026-10-30 메인 기준 줄):
//   G1 내 행 :735 · G2 월간 성공 :923 · G3 월간 실패 :934 · G4 일별 성공 :985 · G5 일별 실패 :990 · G6 하트비트 성공(:1066 함수 안 :1094)
// 시험마다 '전환 없음' 대조를 같이 돌려, 같은 경로가 실제로 장부를 바꾸는 길임을 먼저 보인다(가드를 지우면 전환 쪽이 대조와 같아진다).
package com.yehsung.aingcheck.feature.desktop.tokens.upload

import com.yehsung.aingcheck.core.rules.token.MyTokenRowOutcome
import com.yehsung.aingcheck.core.rules.token.TokenRowServerValue
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountProbeStatus
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexDiagnosticsStamp
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TokenUploadGenerationGuardTest {
    private val now = epoch(1_793_322_123)               // 2026-10-30T01:02:03Z = KST 10:02
    private val usage = TokenUsageMonthly(month = "2026-10", claudeInput = 1000, codexInput = 50, windowStart = "2026-08-08",
        claudeDaily = mapOf("2026-10-29" to 900L, "2026-10-30" to 100L), codexDaily = mapOf("2026-10-30" to 50L))

    private class Rig(statusFor: (String) -> Int = { 201 }, bodyFor: (String) -> String? = { null }) {
        val backend = RecordingBackend(statusFor, bodyFor)
        val host = FakeSessionHost(backend.service)
        val store = InMemoryDesktopKeyValueStore()
        var schemaMissingSignals = 0
        var switches = 0
        val coordinator = TokenUploadCoordinator(DesktopAppConfig(tokenUpload = true), host, { "win:dev-1" }, { true }, store, appBuild = 1,
            computeDiagnostics = { _, build -> CodexUsageDiagnostics(filesTotal = 3, appBuild = build) },
            onSchemaMissing = { schemaMissingSignals += 1 })

        /** [matches] 경로의 요청이 나가 있는 동안(응답 전) 다른 계정으로 바뀐다 — 세대 +1, 세션 u-2. */
        fun switchAccountDuring(matches: (String) -> Boolean) {
            backend.onRequest = { path ->
                if (matches(path)) {
                    host.sessionGeneration += 1
                    host.current = SupabaseSession("access-token-2", null, "u-2")
                    switches += 1
                }
            }
        }
    }

    @Test
    fun G1_myRowFetchAnsweredAfterAccountSwitchDoesNotTouchTheRow() = runTest {
        val row = TokenRowServerValue("u-1", "2026-10", 1000, 900, 100, 0, null, 0.0)
        fun rig() = Rig().also { it.coordinator.applyMyTokenRowOutcome(MyTokenRowOutcome.adopt(row)) }

        // 대조: 응답([] = 내 행 없음)은 clear 다 — 전환이 없으면 행과 저장값이 지워진다.
        val control = rig()
        control.coordinator.loadMyTokenRowIfDue(now, force = true)
        assertNull(control.coordinator.myTokenRow, "대조 전제: 빈 보드 응답은 내 행을 지운다")
        assertNull(control.store.getString(TokenUploadCoordinator.MY_ROW_KEY))

        val switched = rig()
        switched.switchAccountDuring { "/rpc/" in it }
        switched.coordinator.loadMyTokenRowIfDue(now, force = true)
        assertEquals(1, switched.switches, "전제: 보드 조회 중에 계정이 바뀌었다")
        assertEquals(row, switched.coordinator.myTokenRow, "G1 옛 세션의 보드 응답이 내 행을 바꿨다")
        assertNotNull(switched.store.getString(TokenUploadCoordinator.MY_ROW_KEY), "G1 옛 세션의 보드 응답이 저장된 내 행을 지웠다")
        assertEquals(now, switched.coordinator.lastMyTokenRowFetchAt, "시도 시각은 먼저 찍힌다(세대와 무관)")
    }

    @Test
    fun G2_monthlySuccessAfterAccountSwitchLeavesTheLedgerAndSkipsDaily() = runTest {
        val control = Rig()
        control.coordinator.uploadTokenUsageIfNeeded(usage, null, CodexAccountProbeStatus.NOT_LOGGED_IN, now)
        assertEquals(usage, control.coordinator.lastUploadedUsage, "대조 전제")
        assertNotNull(control.coordinator.lastUploadedAccountKey)
        assertTrue(control.coordinator.didUploadTokenUsage)
        assertEquals(listOf(TokenUploadPaths.DEVICE_MONTHLY, TokenUploadPaths.DEVICE_DAILY), control.backend.paths())

        val switched = Rig()
        switched.switchAccountDuring { it == TokenUploadPaths.DEVICE_MONTHLY }
        switched.coordinator.uploadTokenUsageIfNeeded(usage, null, CodexAccountProbeStatus.NOT_LOGGED_IN, now)
        assertEquals(1, switched.switches)
        assertNull(switched.coordinator.lastUploadedUsage, "G2 옛 세션 값으로 lastUploadedUsage 를 갱신했다 — 새 계정의 변경 게이트가 닫힌다")
        assertNull(switched.coordinator.lastUploadedAccountKey, "G2 옛 세션 값으로 계정 키를 갱신했다")
        assertFalse(switched.coordinator.didUploadTokenUsage, "G2 옛 세션 업로드로 내 행 강제 갱신을 예약했다")
        assertEquals(listOf(TokenUploadPaths.DEVICE_MONTHLY), switched.backend.paths(), "G2 전환 뒤 새 계정으로 일별을 이어 보냈다")
        // ★5 진단 도장은 세대 가드 **앞**(Swift :908-917 주석 — "이 기기가 이 달 진단을 남겼다"는 사실은 계정 전환과 무관).
        assertEquals("1:2026-10-30", switched.store.getString(CodexDiagnosticsStamp.KEY))
        assertEquals(now, switched.coordinator.lastTokenUploadAt, "★2 시도 시각은 먼저")
    }

    @Test
    fun G3_monthlySchemaMissingAnsweredAfterAccountSwitchRaisesNoSignal() = runTest {
        val schemaMissing = """{"code":"PGRST205","message":"Could not find the table 'public.token_usage_device_monthly' in the schema cache"}"""
        fun rig() = Rig(statusFor = { 404 }, bodyFor = { if (it == TokenUploadPaths.DEVICE_MONTHLY) schemaMissing else null })

        val control = rig()
        control.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now)
        assertEquals(1, control.schemaMissingSignals, "대조 전제: 스키마 부재 응답은 운영자 신호를 한 번 올린다")

        val switched = rig()
        switched.switchAccountDuring { it == TokenUploadPaths.DEVICE_MONTHLY }
        switched.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now)
        assertEquals(1, switched.switches)
        assertEquals(0, switched.schemaMissingSignals, "G3 옛 세션의 실패가 새 계정에 스키마 부재 신호를 올렸다")
        assertNull(switched.coordinator.lastUploadedUsage)
    }

    @Test
    fun G4_dailySuccessAfterAccountSwitchKeepsBaselineAndRetryFlag() = runTest {
        // 둘 다 첫 일별을 실패시켜 재시도 깃발을 세운 뒤, 두 번째 일별(직접 호출)이 성공하는 모양.
        fun rig(): Rig {
            var dailyFailures = 1
            val r = Rig(statusFor = { if (it == TokenUploadPaths.DEVICE_DAILY && dailyFailures-- > 0) 500 else 201 })
            return r
        }
        suspend fun Rig.armRetry() {
            coordinator.uploadTokenUsageIfNeeded(usage, null, null, now)
            assertTrue(coordinator.tokenDailyRetryPending, "전제: 첫 일별 실패로 재시도 깃발")
            assertTrue(coordinator.lastUploadedDaily.isEmpty())
        }

        val control = rig().apply { armRetry() }
        control.coordinator.uploadTokenUsageDailyIfNeeded(usage, null, control.host.sessionGeneration, now)
        assertFalse(control.coordinator.tokenDailyRetryPending, "대조 전제: 일별 성공이 재시도 깃발을 내린다")
        assertTrue(control.coordinator.lastUploadedDaily.isNotEmpty(), "대조 전제: 일별 성공이 기준선을 채운다")

        val switched = rig().apply { armRetry() }
        switched.switchAccountDuring { it == TokenUploadPaths.DEVICE_DAILY }
        switched.coordinator.uploadTokenUsageDailyIfNeeded(usage, null, switched.host.sessionGeneration, now)
        assertEquals(1, switched.switches)
        assertTrue(switched.coordinator.lastUploadedDaily.isEmpty(), "G4 옛 세션의 일별 성공으로 기준선을 채웠다 — 새 계정 일별이 '안 바뀜'으로 빠진다")
        assertTrue(switched.coordinator.tokenDailyRetryPending, "G4 옛 세션의 일별 성공으로 재시도 깃발을 내렸다")
    }

    @Test
    fun G5_dailyFailureAfterAccountSwitchDoesNotArmRetry() = runTest {
        fun rig() = Rig(statusFor = { if (it == TokenUploadPaths.DEVICE_DAILY) 500 else 201 })

        val control = rig()
        control.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now)
        assertTrue(control.coordinator.tokenDailyRetryPending, "대조 전제: 일별 실패는 재시도 깃발을 세운다")

        val switched = rig()
        switched.switchAccountDuring { it == TokenUploadPaths.DEVICE_DAILY }
        switched.coordinator.uploadTokenUsageIfNeeded(usage, null, null, now)
        assertEquals(1, switched.switches)
        assertFalse(switched.coordinator.tokenDailyRetryPending, "G5 옛 세션의 일별 실패가 새 계정에 재시도 깃발을 세웠다")
    }

    @Test
    fun G6_heartbeatAnsweredAfterAccountSwitchIsNotMarkedSent() = runTest {
        val control = Rig()
        control.coordinator.sendTokenScanHeartbeatIfNeeded(now, 7, now)
        assertEquals(now, control.coordinator.lastTokenScanHeartbeatAt, "대조 전제: 하트비트 성공은 보낸 스캔 시각을 적는다")

        val switched = Rig()
        switched.switchAccountDuring { it == TokenUploadPaths.DEVICE_MONTHLY }
        switched.coordinator.sendTokenScanHeartbeatIfNeeded(now, 7, now)
        assertEquals(1, switched.switches)
        assertNull(switched.coordinator.lastTokenScanHeartbeatAt, "G6 옛 세션 하트비트를 보낸 것으로 적었다 — 새 계정은 같은 스캔을 다시 못 보낸다")
    }
}
