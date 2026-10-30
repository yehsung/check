// 소셜 배선(SocialWiring) 시험 — 가짜 의존(MockEngine 녹음 · 진짜 SessionStore · 가짜 근무 사실)으로 start→stop 한 바퀴 +
// W-6 #1 깃발 꺼짐(poke=false → take_pokes·poke_user·ultra_poke_user 요청 0 · ultra=false → 발신·구매만 0, 지갑은 돈다) +
// W2-g3 '근무 시작 한 번에 take_pokes 2회 금지'. 음성 대조: 같은 장면을 poke=true 로 돌리면 take_pokes 가 나간다.
@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.poke.NoOpConsumedRowsSink
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeFacts
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPoke
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPokeSink
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.PokeFactsSource
import com.yehsung.aingcheck.feature.desktop.work.lap.LapWalletJudge
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.ExperimentalTime

class SocialWiringTest {
    private val takePokes = "/rpc/take_pokes"
    private val pokeUser = "/rpc/poke_user"
    private val ultraPokeUser = "/rpc/ultra_poke_user"
    private val buyUltra = "/rpc/buy_ultra"
    private val walletSync = "/rpc/ultra_wallet_sync"

    private class Built(val rig: WiringTestRig, val social: SocialWiring, val received: MutableList<List<ReceivedPoke>>)

    private fun TestScope.build(config: DesktopAppConfig, withSinks: Boolean = true): Built {
        val rig = WiringTestRig(this)
        val start = SwiftDate.fromEpochMillis(WiringTestRig.BASE_MS)
        val workState = InMemoryDesktopWorkState(DesktopWorkSnapshot(isWorking = true, startedAt = start, sessionId = "s-1"))
        val facts = PokeFactsSource {
            PokeConsumeFacts(
                localSessionOpen = true,
                adoptedRemoteSession = false,
                canonicalSessionID = "s-1",
                ownOpenSessionID = "s-1",
                ownDeviceClaims = null,
                deviceID = WiringTestRig.DEVICE,
                lastMeaningfulInputAt = start,
            )
        }
        val received = mutableListOf<List<ReceivedPoke>>()
        val social = SocialWiring(
            SocialDeps(
                sessionStore = rig.sessionStore,
                httpClient = rig.httpClient,
                desktopConfig = config,
                kv = rig.kv,
                clock = rig.clock,
                workState = workState,
                pokeFacts = facts,
                lapJudgment = LapWalletJudge,
                ruby = RubyBalanceCell(),
                runningTests = rig.runningTests,
                environment = emptyMap(),
                receivedPokes = if (withSinks) ReceivedPokeSink { received += it } else null,
                consumedRows = if (withSinks) NoOpConsumedRowsSink else null,
            ),
        )
        return Built(rig, social, received)
    }

    @Test
    fun start_stop_한_바퀴__로그인에_지갑_sync__stop_뒤_폴링_0() = runTest {
        val b = build(DesktopAppConfig(poke = true, ultra = true))
        try {
            assertNull(b.social.transport, "시험 프로세스는 실소켓 0(RunningTests)")
            b.social.start(b.rig.scope)
            b.rig.signIn()
            runCurrent()
            assertTrue(b.social.isStarted)
            assertTrue(b.rig.count(walletSync) >= 1, "로그인 → 지갑 sync(SignIn): ${b.rig.requests}")
            advanceTimeBy(16_000)
            runCurrent()
            assertTrue(b.rig.count(takePokes) >= 1, "켜진 빌드는 폴링 박자에 take_pokes")
            b.social.stop()
            val after = b.rig.count(takePokes)
            advanceTimeBy(5 * 60_000L)
            runCurrent()
            assertEquals(after, b.rig.count(takePokes), "stop 뒤 폴링 0")
            assertFalse(b.social.isStarted)
            b.social.shutdown()
            assertTrue(b.rig.uncaught.isEmpty(), "잡히지 않은 예외: ${b.rig.uncaught}")
        } finally {
            b.rig.close()
        }
    }

    @Test
    fun poke_꺼짐__찌르기_서버_경로_요청_0__지갑_집중은_돈다() = runTest {
        val b = build(DesktopAppConfig()) // 기본 = 전부 꺼짐(spectator 만 켬)
        try {
            assertNull(b.social.poller)
            assertNull(b.social.drainer)
            assertNull(b.social.sender)
            assertNull(b.social.purchase)
            b.social.start(b.rig.scope)
            b.rig.signIn()
            runCurrent()
            b.social.lifecycle.onWorkStarted()
            b.social.lifecycle.onUserStoppedWork(isTerminating = false)
            assertNull(b.social.actions.sendPoke("peer"))
            assertNull(b.social.actions.sendUltraPoke("peer"))
            assertNull(b.social.actions.buyUltra())
            advanceTimeBy(5 * 60_000L)
            runCurrent()
            assertEquals(0, b.rig.count(takePokes), "W-6 #1 poke=false → take_pokes 0: ${b.rig.requests}")
            assertEquals(0, b.rig.count(pokeUser))
            assertEquals(0, b.rig.count(ultraPokeUser))
            assertEquals(0, b.rig.count(buyUltra))
            assertTrue(b.rig.count(walletSync) >= 1, "ultra=false 여도 지갑 sync 는 돈다")
            assertTrue(b.rig.countContaining("focus_mode") >= 5, "폴러 없이도 자기 박자(15초)로 집중 모드를 본다: ${b.rig.countContaining("focus_mode")}")
        } finally {
            b.social.shutdown()
            b.rig.close()
        }
    }

    @Test
    fun poke_켜짐_같은_장면은_take_pokes_가_나간다__깃발_시험의_음성_대조() = runTest {
        val b = build(DesktopAppConfig(poke = true))
        try {
            b.social.start(b.rig.scope)
            b.rig.signIn()
            runCurrent()
            b.social.lifecycle.onWorkStarted()
            advanceTimeBy(5 * 60_000L)
            runCurrent()
            assertTrue(b.rig.count(takePokes) >= 2, "근무 시작 drain + 폴링 박자: ${b.rig.count(takePokes)}")
        } finally {
            b.social.shutdown()
            b.rig.close()
        }
    }

    @Test
    fun 받는_쪽이_없으면_poke_켜져도_drainer_0() = runTest {
        val b = build(DesktopAppConfig(poke = true), withSinks = false)
        try {
            assertNull(b.social.drainer)
            assertNotNull(b.social.poller)
            b.social.start(b.rig.scope)
            b.rig.signIn()
            runCurrent()
            b.social.lifecycle.onWorkStarted()
            advanceTimeBy(2 * 60_000L)
            runCurrent()
            assertEquals(0, b.rig.count(takePokes))
        } finally {
            b.social.shutdown()
            b.rig.close()
        }
    }

    @Test
    fun 근무_시작_한_번에_take_pokes_는_한_번() = runTest {
        val b = build(DesktopAppConfig(poke = true))
        try {
            b.social.start(b.rig.scope)
            b.rig.signIn()
            runCurrent()
            assertEquals(0, b.rig.count(takePokes), "폴러 첫 동작은 sleep — 시작 즉시 0")
            b.social.lifecycle.onWorkStarted()
            runCurrent()
            assertEquals(1, b.rig.count(takePokes), "W2-g3: requestDrain 은 찌르기 한 곳 — 러너 onWorkStarted 는 drain 하지 않는다")
        } finally {
            b.social.shutdown()
            b.rig.close()
        }
    }

    @Test
    fun ultra_꺼짐은_울트라_발신_구매만_막는다() = runTest {
        val b = build(DesktopAppConfig(poke = true, ultra = false))
        try {
            b.social.start(b.rig.scope)
            b.rig.signIn()
            runCurrent()
            assertFalse(b.social.actions.canUltra)
            assertFalse(b.social.actions.canBuyUltra)
            assertNull(b.social.actions.sendUltraPoke("peer"))
            assertNull(b.social.actions.buyUltra(1))
            assertNotNull(b.social.actions.sendPoke("peer"))
            runCurrent()
            assertEquals(1, b.rig.count(pokeUser), "일반 찌르기는 나간다")
            assertEquals(0, b.rig.count(ultraPokeUser))
            assertEquals(0, b.rig.count(buyUltra))
            assertTrue(b.rig.count(walletSync) >= 1, "지갑은 깃발 없이")
        } finally {
            b.social.shutdown()
            b.rig.close()
        }
    }
}
