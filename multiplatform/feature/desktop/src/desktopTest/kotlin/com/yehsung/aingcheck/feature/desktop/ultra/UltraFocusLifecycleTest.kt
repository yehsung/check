// 원본: Sources/check/WorkTimerStoreAuth.swift 75·120(로그인 지갑 sync) · Sources/check/WorkTimerStore.swift 3514(★L1 `if lap >= 1`)
//       · Sources/check/WorkTimerStorePoke.swift 394-411(★L2 폴링 박자: 서버값 로드(성공할 때까지) → 집중 만료 → 지갑 periodic)
//       · 306(★L3 지갑 실패 경로의 세대 가드) @ a90d8623
package com.yehsung.aingcheck.feature.desktop.ultra

import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.focus.FocusModeController
import com.yehsung.aingcheck.feature.desktop.focus.FocusStage
import com.yehsung.aingcheck.feature.desktop.focus.FocusStageRecord
import com.yehsung.aingcheck.feature.desktop.focus.FocusStageRecords
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun settings(focusOn: Boolean): Reply.Json =
    Reply.Json("""[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":$focusOn}]""")

class UltraFocusLifecycleTest {
    private class Rig(scope: TestScope, working: Boolean = false) {
        val clock = TestClock()
        val server = FakeServer(scope)
        val host = FakeSessionHost(server.service(clock::now))
        val kv = InMemoryDesktopKeyValueStore()
        val work = InMemoryDesktopWorkState(DesktopWorkSnapshot(isWorking = working, startedAt = if (working) clock.now() else null))
        val cadence = mutableListOf<UltraSyncReason>()
        val wallet = UltraWalletStore(host, work, SwiftRuleLapJudgment(), {}, scope, clock::now, { cadence += it })
        val focus = FocusModeController(host, kv, scope, clock::now)
        val life = UltraFocusLifecycle(wallet, focus)
        val gets: Int get() = server.count("GET", PROFILES_PATH)
        val walletSyncs: Int get() = server.count("POST", WALLET_PATH)
        val patches: List<String> get() = server.calls.filter { it.method == "PATCH" }.map { it.body }
    }

    @Test
    fun signInSyncsWalletAndLoadsServerFocusOnce() = runTest {
        // 로그인 = 지갑 SignIn 1건 + 서버 집중값 GET 1건(서버 켜짐 + 기록 없음 → 계속).
        val rig = Rig(this)
        rig.server.on("GET", PROFILES_PATH, settings(true)).on("POST", WALLET_PATH, walletOk())
        rig.life.onSignedIn()
        advanceUntilIdle()
        assertEquals(1, rig.walletSyncs)
        assertEquals(listOf(UltraSyncReason.SignIn), rig.cadence)
        assertEquals(1, rig.gets, "로그인 박자에 서버 집중값을 읽는다")
        assertEquals(true, rig.focus.serverValue)
        assertTrue(rig.focus.isFocusOn)
        assertEquals(FocusStage.ALWAYS, rig.focus.focusStage(rig.clock.now()))
    }

    @Test
    fun l1LapGateStartsAtFirstLap() = runTest {
        // ★L1 랩 0(시작 직후)은 미션 후보가 아니다 — 1부터 지갑 MissionCandidate.
        val rig = Rig(this, working = true)
        rig.server.on("POST", WALLET_PATH, walletOk())
        rig.life.onLapCrossed(0)
        advanceUntilIdle()
        assertEquals(0, rig.walletSyncs, "랩 0 = 요청 0")
        assertTrue(rig.cadence.isEmpty())
        rig.life.onLapCrossed(1)
        advanceUntilIdle()
        assertEquals(1, rig.walletSyncs)
        rig.life.onLapCrossed(2)
        advanceUntilIdle()
        assertEquals(2, rig.walletSyncs)
        assertEquals(listOf(UltraSyncReason.MissionCandidate, UltraSyncReason.MissionCandidate), rig.cadence)
    }

    @Test
    fun l2OfflineSignInRetriesFocusLoadOnPollBeatAndExpiresFinishedTimedStage() = runTest {
        // ★L2 오프라인으로 켠 앱: 로그인 GET 이 실패해도 폴링 박자가 성공할 때까지 다시 읽는다.
        // 받고 나면 앱이 꺼진 동안 끝난 1단을 서버에서 끈다(F1 만료는 클라). 이 재시도가 없으면 서버 focus_mode 가
        // 다음 로그인까지 true 로 남아 남의 찌르기가 target_focused 로 막히는데 화면은 '끔'이다.
        val rig = Rig(this)
        rig.server.on("GET", PROFILES_PATH, Reply.Offline, settings(true))
            .on("PATCH", PROFILES_PATH, Reply.Json("", 204))
            .on("POST", WALLET_PATH, walletOk())
        FocusStageRecords(rig.kv).write(FocusStageRecord(FocusStage.TIMED, rig.clock.now().addingTimeInterval(-60.0)), TEST_USER)
        rig.life.onSignedIn()
        advanceUntilIdle()
        assertEquals(1, rig.gets)
        assertTrue(rig.patches.isEmpty())
        repeat(5) {
            rig.clock.advance(15.0)
            rig.life.onPollBeat(rig.clock.now())
            advanceUntilIdle()
        }
        assertEquals(2, rig.gets, "성공할 때까지만 다시 읽는다(받은 뒤엔 0)")
        assertEquals(listOf("""{"focus_mode":false}"""), rig.patches, "끝난 1단을 서버에서 끈다")
        assertEquals(false, rig.focus.serverValue)
        assertFalse(rig.focus.isFocusOn)
        assertNull(rig.focus.record(TEST_USER))
    }

    @Test
    fun l3WalletFailureFromLeftSessionRaisesNoFlag() = runTest {
        // ★L3 실패 경로도 세대를 본다 — 떠난 세션의 실패가 새 세션 화면에 '못 읽었어요'를 세우지 않는다.
        val rig = Rig(this, working = true)
        rig.server.on("POST", WALLET_PATH, Reply.Json("""{"message":"boom"}""", 500))
        rig.wallet.sync(UltraSyncReason.SignIn)
        rig.host.sessionGeneration += 1 // 응답이 오기 전에 로그아웃·계정 전환
        advanceUntilIdle()
        assertEquals(1, rig.walletSyncs)
        assertFalse(rig.wallet.state.value.failed, "떠난 세대의 실패는 버린다")
    }
}
