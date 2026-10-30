// 원본: Sources/check/WorkTimerStorePoke.swift 245-315(스로틀 300초 · 발사 시점 스탬프 · 실패는 잔량 유지) @ a90d8623
package com.yehsung.aingcheck.feature.desktop.ultra

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.feature.desktop.ultra.net.syncUltraWallet
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** ★U1 periodic 은 근무 중 300초마다 · 스탬프는 발사 시점 · U2 실패해도 잔량과 스탬프를 지우지 않는다. */
class WalletThrottleTest {
    private class Rig(scope: TestScope, working: Boolean, vararg replies: Reply) {
        val clock = TestClock()
        val server = FakeServer(scope).on("POST", WALLET_PATH, *replies)
        val host = FakeSessionHost(server.service(clock::now))
        val work = InMemoryDesktopWorkState(DesktopWorkSnapshot(isWorking = working, startedAt = if (working) clock.now() else null))
        val cadence = mutableListOf<UltraSyncReason>()
        val store = UltraWalletStore(host, work, SwiftRuleLapJudgment(), {}, scope, clock::now, { cadence += it })
        val syncs: Int get() = server.count("POST", WALLET_PATH)
    }

    @Test
    fun notWorkingPeriodicSendsNothing() = runTest {
        val rig = Rig(this, working = false, walletOk())
        repeat(5) {
            rig.store.sync(UltraSyncReason.Periodic)
            rig.clock.advance(400.0)
            advanceUntilIdle()
        }
        assertEquals(0, rig.syncs, "비근무 periodic = 요청 0건")
        assertNull(rig.store.lastSyncAt)
        assertTrue(rig.cadence.isEmpty(), "발사하지 않았으면 박자 훅도 0")
    }

    @Test
    fun workingPeriodicThrottlesAt300Seconds() = runTest {
        val rig = Rig(this, working = true, walletOk())
        rig.store.sync(UltraSyncReason.Periodic)
        advanceUntilIdle()
        assertEquals(1, rig.syncs)
        rig.clock.advance(299.0)
        rig.store.sync(UltraSyncReason.Periodic)
        advanceUntilIdle()
        assertEquals(1, rig.syncs, "299초 = 아직 스로틀")
        rig.clock.advance(1.0)
        rig.store.sync(UltraSyncReason.Periodic)
        advanceUntilIdle()
        assertEquals(2, rig.syncs, "300초 = 다시 발사")
        assertEquals(listOf(UltraSyncReason.Periodic, UltraSyncReason.Periodic), rig.cadence)
    }

    @Test
    fun failureKeepsStampAndBalance() = runTest {
        val rig = Rig(this, working = true, walletOk(balance = 4), Reply.Json("""{"message":"boom"}""", 500))
        rig.store.sync(UltraSyncReason.SignIn)
        advanceUntilIdle()
        assertEquals(4L, rig.store.state.value.balance)
        rig.clock.advance(301.0)
        val firedAt = rig.clock.now()
        rig.store.sync(UltraSyncReason.Periodic)
        advanceUntilIdle()
        assertEquals(2, rig.syncs)
        assertTrue(rig.store.state.value.failed, "실패 = 진단 깃발")
        assertEquals(4L, rig.store.state.value.balance, "U2 실패는 잔량을 지우지 않는다")
        assertEquals(firedAt, rig.store.lastSyncAt, "스탬프는 발사 시점 — 실패해도 남는다")
        // 서버가 죽어 있는 동안 매 tick 이 재시도하지 않는다(15초 박자 × 10).
        repeat(10) {
            rig.clock.advance(15.0)
            rig.store.sync(UltraSyncReason.Periodic)
            advanceUntilIdle()
        }
        assertEquals(2, rig.syncs, "실패 뒤에도 300초 스로틀")
    }

    @Test
    fun anyReasonStampsAndDefersPeriodic() = runTest {
        val rig = Rig(this, working = true, walletOk())
        rig.store.sync(UltraSyncReason.PanelOpen)
        rig.clock.advance(200.0)
        rig.store.sync(UltraSyncReason.Periodic)
        advanceUntilIdle()
        assertEquals(1, rig.syncs, "panelOpen 발사도 periodic 을 300초 미룬다(Swift 와 같다)")
        // 사용자·랩 이유는 스로틀을 받지 않는다.
        rig.store.sync(UltraSyncReason.MissionCandidate)
        rig.store.sync(UltraSyncReason.SignIn)
        advanceUntilIdle()
        assertEquals(3, rig.syncs)
    }

    @Test
    fun invalidIsNotFailure() = runTest {
        val rig = Rig(this, working = true, Reply.Json("""{"message":"boom"}""", 500), Reply.Json("""{"status":"invalid"}"""))
        rig.store.sync(UltraSyncReason.SignIn)
        advanceUntilIdle()
        assertTrue(rig.store.state.value.failed)
        rig.store.sync(UltraSyncReason.PanelOpen)
        advanceUntilIdle()
        assertFalse(rig.store.state.value.failed, "invalid(비로그인·프로필 없음)는 서버 오류가 아니다")
    }

    @Test
    fun noSessionSendsNothing() = runTest {
        val rig = Rig(this, working = true, walletOk())
        rig.host.session = null
        rig.store.sync(UltraSyncReason.SignIn)
        advanceUntilIdle()
        assertEquals(0, rig.syncs)
        assertNull(rig.store.lastSyncAt)
    }

    @Test
    fun staleGenerationIsDropped() = runTest {
        val rig = Rig(this, working = true, walletOk(balance = 7))
        rig.store.sync(UltraSyncReason.SignIn)
        rig.host.sessionGeneration += 1 // 응답이 오기 전에 로그아웃·계정 전환
        advanceUntilIdle()
        assertEquals(1, rig.syncs)
        assertNull(rig.store.state.value.balance, "떠난 세대의 응답은 버린다")
    }

    @Test
    fun missingFunctionThrowsUltraWalletUnavailable() = runTest {
        val clock = TestClock()
        val server = FakeServer(this).on("POST", WALLET_PATH, Reply.missingFunction("ultra_wallet_sync"))
        assertFailsWith<SupabaseWorkServiceError.UltraWalletUnavailable> { server.service(clock::now).syncUltraWallet("t") }
    }

    @Test
    fun grantedNowIsTheOnlyCelebrationTrigger() = runTest {
        // ★U3 claimed 만 참인 응답(5분마다 참)은 연출 0. 판정이 '축하'라고 해도 granted_now 가 없으면 0.
        val always = com.yehsung.aingcheck.feature.desktop.work.LapWalletJudgment { _, streak ->
            com.yehsung.aingcheck.feature.desktop.work.LapOutcome(true, 1, streak)
        }
        val clock = TestClock()
        var charged = 0
        val store = UltraWalletStore(
            FakeSessionHost(FakeServer(this).service(clock::now)), InMemoryDesktopWorkState(), always, { charged += 1 }, this, clock::now,
        )
        store.apply(
            com.yehsung.aingcheck.core.wire.json.SwiftJson.decode(
                com.yehsung.aingcheck.feature.desktop.ultra.net.UltraWalletResponse.Serializer,
                """{"status":"ok","balance":1,"day":"2026-10-30","missions":[{"key":"work3h","kst_day":"2026-10-30","target_seconds":10800,"progress_seconds":10800,"claimed":true,"granted_now":false}]}""",
            ),
        )
        assertEquals(0, charged)
        assertNull(store.state.value.missionNotice)
    }
}
