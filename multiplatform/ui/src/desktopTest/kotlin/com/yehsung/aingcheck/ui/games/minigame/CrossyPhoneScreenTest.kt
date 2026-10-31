// 원본: Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift:195-232(canvasDrag 갈래) · Sources/check/MiniGamePanel.swift:1195-1215(armTokenKeeper) @ 1a5eeca6
//
// **실제 화면**(허브 openScreen · 프레임 루프 · 손가락 포인터)을 오프스크린으로 그려 "부르는 자리"를 잰다(기억 tests-measure-shape-not-result):
//  · 폰 경로(isPhone = true): 쓸기가 그 방향 한 칸 · 판을 켠 접촉은 다 쓴다 · 탭은 뗄 때 앞으로 한 칸.
//  · Windows 경로(기본값): 클릭은 누르는 순간 앞으로 한 칸 · 쓸기는 방향이 아니다(마우스 동작 변화 0) — 위와 다른 입력의 기준선.
//  · 판 도중 토큰 감시: 판이 도는 길건너 화면이 30초마다 깨어나고, 20분이 지나면 새 토큰을 받는다. 판이 끝나면 거둔다. 갈아 끼우지 않는 게임은 깨어나지 않는다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameHub
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class, ExperimentalCoroutinesApi::class)
class CrossyPhoneScreenTest {
    /** 390dp 폭 × 2배 — 캔버스는 위쪽에 선다(머리 줄 아래). 가운데 근처가 캔버스 안이다. */
    private val press = Offset(390f, 400f)

    private inner class Rig(val scope: TestScope, val h: UiGamesHarness, kind: MiniGameKind, isPhone: Boolean) {
        val store = GamesStore(h.context)
        val scene = ImageComposeScene(780, 1600, Density(2f)) {
            AingTheme(dark = true) {
                GamesMiniGameScreen(store, kind, 60, MiniGameArt.empty, null, Modifier.fillMaxSize(), isPhone = isPhone)
            }
        }
        private var frame = 0L
        fun render(times: Int = 1) = repeat(times) {
            frame += 1
            scene.render(frame * 16_666_667L)
            scope.testScheduler.runCurrent()
        }
        val controller: GamesPlayController get() = requireNotNull(store.miniGames.controller) { "화면이 허브에 판을 열지 않았다" }
        fun touch(type: PointerEventType, at: Offset) = scene.sendPointerEvent(type, at, type = PointerType.Touch)
        fun swipe(by: Offset) {
            touch(PointerEventType.Press, press)
            render()
            touch(PointerEventType.Move, press + by)
            render()
            touch(PointerEventType.Release, press + by)
            render()
        }
    }

    private suspend fun TestScope.rig(kind: MiniGameKind, isPhone: Boolean): Rig {
        var issued = 0
        val h = UiGamesHarness(this) { r -> UiFixtures.miniGameRoute(r) { ++issued } }
        h.signIn()
        val rig = Rig(this, h, kind, isPhone)
        rig.render(3)
        advanceUntilIdle()
        rig.render(2)
        return rig
    }

    /** 땅에 설 때까지 프레임을 민다. 뛰는 중 입력은 줄을 서므로 방향을 재려면 먼저 서 있어야 한다. */
    private fun Rig.settle() {
        var guard = 0
        while (controller.crossy.hop != null && guard < 200) {
            render()
            guard += 1
        }
    }

    @Test
    fun onThePhoneASwipeHopsThatWayAndTheStartingContactIsSpent() = runTest {
        val r = rig(MiniGameKind.crossy, isPhone = true)
        try {
            assertEquals(CrossyGame.Phase.Ready, r.controller.crossy.phase)
            // 시작 래치: 판을 켠 접촉이 흔들려도 한 칸 더 뛰지 않는다.
            r.swipe(Offset(100f, 0f))
            assertTrue(r.controller.isPlaying, "누름이 판을 켜지 않았다")
            assertEquals(1, r.controller.crossy.hopCount, "판을 켠 접촉이 한 칸 더 뛰었다")
            r.settle()
            val before = r.controller.crossy.hopCount
            r.swipe(Offset(100f, 0f)) // 50dp 오른쪽
            assertEquals(before + 1, r.controller.crossy.hopCount, "폰에서 쓸기가 안 먹었다")
            assertEquals(CrossyGame.Direction.right, r.controller.crossy.player.facing, "오른쪽으로 쓸었는데 다른 데로 갔다")
            r.settle()
            val count = r.controller.crossy.hopCount
            r.touch(PointerEventType.Press, press)
            r.render()
            assertEquals(count, r.controller.crossy.hopCount, "탭이 누르는 순간 뛰었다 — 폰은 쓸기와 가르려고 뗄 때 판정한다")
            r.touch(PointerEventType.Release, press)
            r.render()
            assertEquals(count + 1, r.controller.crossy.hopCount, "탭이 앞으로 한 칸을 안 냈다")
            assertEquals(CrossyGame.Direction.forward, r.controller.crossy.player.facing)
        } finally {
            r.scene.close()
            r.h.close()
        }
    }

    @Test
    fun onWindowsAClickHopsOnPressAndADragIsNotADirection() = runTest {
        val r = rig(MiniGameKind.crossy, isPhone = false)
        try {
            r.touch(PointerEventType.Press, press)
            r.render()
            r.touch(PointerEventType.Release, press)
            r.render()
            assertTrue(r.controller.isPlaying)
            r.settle()
            val before = r.controller.crossy.hopCount
            r.touch(PointerEventType.Press, press)
            r.render()
            assertEquals(before + 1, r.controller.crossy.hopCount, "클릭이 누르는 순간 뛰지 않았다(맥 마우스 다운)")
            r.touch(PointerEventType.Move, press + Offset(100f, 0f))
            r.render()
            r.touch(PointerEventType.Release, press + Offset(100f, 0f))
            r.render()
            assertEquals(before + 1, r.controller.crossy.hopCount, "Windows 끌기가 방향이 됐다")
            assertEquals(CrossyGame.Direction.forward, r.controller.crossy.player.facing)
        } finally {
            r.scene.close()
            r.h.close()
        }
    }

    /** 뒤로(화면 사라짐) = 그 점수로 확정 제출 — iOS 와 같다. */
    @Test
    fun leavingTheScreenSubmitsTheScore() = runTest {
        val r = rig(MiniGameKind.crossy, isPhone = true)
        try {
            r.swipe(Offset.Zero)
            assertTrue(r.controller.isPlaying)
            r.store.miniGames.closeScreen(MiniGameKind.crossy)
            advanceUntilIdle()
            assertNull(r.store.miniGames.controller)
            assertEquals(1, r.h.server.count("minigame_submit_score"), "뒤로 간 길건너 판이 제출되지 않았다")
        } finally {
            r.scene.close()
            r.h.close()
        }
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

    /** 화면이 띄운 감시가 30초마다 깨어 20분 지난 토큰을 갈아 끼운다. 판이 끝나면 거둔다(기준선: 젊은 토큰은 그대로 · 갈아 끼우지 않는 게임은 아예 안 잔다). */
    @Test
    fun theScreenKeepsTheCrossyRoundTokenFresh() = runTest {
        val r = rig(MiniGameKind.crossy, isPhone = true)
        try {
            val hub = r.store.miniGames
            val (sleeps, wake) = hub.stepSleep()
            assertEquals("t1", hub.roundToken, "전제: 화면을 열며 토큰을 받았다")
            r.swipe(Offset.Zero) // 판 시작
            assertTrue(r.controller.isPlaying)
            r.render(2)
            assertEquals(listOf(GamesMiniGameHub.tokenKeeperIntervalSeconds), sleeps, "판이 도는데 감시가 안 섰다")
            assertEquals(30.0, GamesMiniGameHub.tokenKeeperIntervalSeconds)
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
        val r = rig(MiniGameKind.flappy, isPhone = true)
        try {
            val (sleeps, _) = r.store.miniGames.stepSleep()
            r.controller.tap()
            r.render(3)
            assertTrue(r.controller.isPlaying)
            assertEquals(emptyList(), sleeps, "플래피에 감시가 섰다")
            assertFalse(MiniGameKind.flappy.roundTokenMidRunRefreshSeconds != null)
        } finally {
            r.scene.close()
            r.h.close()
        }
    }

    @Test
    fun theTrackerGateOpensForCrossyOnThePhoneOnly() {
        assertTrue(usesCanvasTracker(MiniGameKind.crossy, isPhone = true))
        assertFalse(usesCanvasTracker(MiniGameKind.crossy, isPhone = false), "Windows 클릭이 뗄 때로 밀렸다")
        assertTrue(usesCanvasTracker(MiniGameKind.tetris, isPhone = false), "Windows 테트리스 끌기는 그대로다")
        assertTrue(usesCanvasTracker(MiniGameKind.tetris, isPhone = true))
        assertFalse(usesCanvasTracker(MiniGameKind.flappy, isPhone = true))
        assertFalse(usesCanvasTracker(MiniGameKind.timingBar, isPhone = true))
    }
}
