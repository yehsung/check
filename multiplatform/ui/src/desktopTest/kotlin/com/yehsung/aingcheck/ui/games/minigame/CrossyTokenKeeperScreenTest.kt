// 원본: Sources/check/MiniGamePanel.swift:1195-1215(armTokenKeeper) @ 1a5eeca6
//
// **실제 화면**(허브 openScreen · 프레임 루프)을 오프스크린으로 그려 "부르는 자리"를 잰다: 판이 도는 길건너 화면이 30초마다 깨어나고, 20분이 지나면 새 토큰을 받는다.
// 판이 끝나면 거둔다. 갈아 끼우지 않는 게임은 깨어나지 않는다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameHub
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class, ExperimentalCoroutinesApi::class)
class CrossyTokenKeeperScreenTest {
    private inner class Rig(val scope: TestScope, val h: UiGamesHarness, kind: MiniGameKind) {
        val store = GamesStore(h.context).also { it.miniGames.visibleKinds = MiniGameExposure.desktopVisible }
        val scene = ImageComposeScene(780, 1600, Density(2f)) {
            AingTheme(dark = true) {
                GamesMiniGameScreen(store, kind, 60, MiniGameArt.empty, null, Modifier.fillMaxSize())
            }
        }
        private var frame = 0L
        fun render(times: Int = 1) = repeat(times) {
            frame += 1
            scene.render(frame * 16_666_667L)
            scope.testScheduler.runCurrent()
        }
        val controller: GamesPlayController get() = requireNotNull(store.miniGames.controller) { "화면이 허브에 판을 열지 않았다" }
    }

    private suspend fun TestScope.rig(kind: MiniGameKind): Rig {
        var issued = 0
        val h = UiGamesHarness(this) { r -> UiFixtures.miniGameRoute(r) { ++issued } }
        h.signIn()
        val rig = Rig(this, h, kind)
        rig.render(3)
        advanceUntilIdle()
        rig.render(2)
        return rig
    }

    private fun GamesMiniGameHub.stepSleep(): Pair<MutableList<Double>, Channel<Unit>> {
        val sleeps = mutableListOf<Double>()
        val wake = Channel<Unit>(Channel.UNLIMITED)
        sleep = { seconds ->
            sleeps += seconds
            wake.receive()
        }
        return sleeps to wake
    }

    /** 화면이 띄운 감시가 30초마다 깨어 20분 지난 토큰을 갈아 끼운다. 판이 끝나면 거둔다(기준선: 젊은 토큰은 그대로). */
    @Test
    fun theScreenKeepsTheCrossyRoundTokenFresh() = runTest {
        val r = rig(MiniGameKind.crossy)
        try {
            val hub = r.store.miniGames
            val (sleeps, wake) = hub.stepSleep()
            assertEquals("t1", hub.roundToken, "전제: 화면을 열며 토큰을 받았다")
            r.controller.tap()
            r.render(3)
            assertTrue(r.controller.isPlaying)
            assertEquals(listOf(GamesMiniGameHub.tokenKeeperIntervalSeconds), sleeps, "판이 도는데 감시가 안 섰다")
            // 젊은 토큰 — 깨어나도 받지 않는다.
            wake.trySend(Unit)
            r.render(2)
            assertEquals(1, r.h.server.count("minigame_start_round"))
            assertEquals(2, sleeps.size, "감시가 한 번 돌고 멈췄다")
            // 21분 뒤 — 갈아 끼운다.
            advanceTimeBy(21 * 60_000L)
            wake.trySend(Unit)
            r.render(2)
            advanceUntilIdle()
            r.render(1)
            assertEquals(2, r.h.server.count("minigame_start_round"), "20분 넘은 토큰을 안 갈아 끼웠다")
            assertEquals("t2", hub.roundToken)
            // 판이 끝나면 다음 깨어남에 돌아온다 — 더 받지 않는다.
            val size = sleeps.size
            r.controller.endRound()
            r.render(2)
            advanceTimeBy(21 * 60_000L)
            wake.trySend(Unit)
            r.render(2)
            assertTrue(sleeps.size <= size + 1, "끝난 판의 감시가 계속 돈다")
        } finally {
            r.scene.close()
            r.h.close()
        }
    }

    @Test
    fun gamesThatNeverSwapTokensArmNoKeeper() = runTest {
        val r = rig(MiniGameKind.flappy)
        try {
            val (sleeps, _) = r.store.miniGames.stepSleep()
            r.controller.tap()
            r.render(3)
            assertTrue(r.controller.isPlaying)
            assertEquals(emptyList(), sleeps, "플래피에 감시가 섰다")
        } finally {
            r.scene.close()
            r.h.close()
        }
    }
}
