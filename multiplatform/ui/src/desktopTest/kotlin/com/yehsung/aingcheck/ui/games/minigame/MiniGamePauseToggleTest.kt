// 원본: Sources/check/MiniGamePanel.swift:983-990(onEscape → PauseState.escaped → applyPause) · :499(isFrozen) · core MiniGamePauseState.toggled
// 공용 패치 11(W-6 #7): GamesMiniGameScreen 바깥 정지 토글(pauseToggleSerial) + 얼었는가 알림(onFrozenChanged). 데스크톱 창의 ESC 가 쓴다.
// 실제 화면(허브 openScreen · 프레임 루프 · 정지 가림막)을 오프스크린으로 그려 잰다:
//  · 기준선: 시작 전 토글은 아무 일도 없다(정지할 판이 없다 — 맥 ESC 도 그때는 안 삼킨다) · 판 중에 값을 안 바꾸면 얼지 않는다.
//  · 판 중 토글 = 정지(얼음 true · 판 시계 멈춤) → 다시 = 3-2-1(여전히 얼음) → 또 = 다시 정지(맥 "카운트다운 중 ESC 는 취소").
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class, ExperimentalCoroutinesApi::class)
class MiniGamePauseToggleTest {
    @Test
    fun externalToggleFreezesAndReportsLikeMacEscape() = runTest {
        var issued = 0
        val h = UiGamesHarness(this) { r -> UiFixtures.miniGameRoute(r) { ++issued } }
        h.signIn()
        val store = GamesStore(h.context)
        store.appDidBecomeActive()
        advanceUntilIdle()
        val serial = mutableIntStateOf(0)
        val reports = mutableListOf<Boolean>()
        val scene = ImageComposeScene(584, 1400, Density(2f)) {
            AingTheme(dark = true) {
                GamesMiniGameScreen(
                    store, MiniGameKind.tetris, 60, MiniGameArt.empty, null, Modifier.fillMaxSize(),
                    pauseToggleSerial = serial.intValue, onFrozenChanged = { reports += it },
                )
            }
        }
        var k = 0L
        fun render(times: Int = 1) = repeat(times) {
            k += 1
            scene.render(k * 16_666_667L)
            h.testScope.testScheduler.runCurrent()
        }
        try {
            render(3)
            val controller = requireNotNull(store.miniGames.controller) { "화면이 허브에 판을 열지 않았다" }
            assertEquals(listOf(false), reports, "처음엔 얼지 않았다를 한 번")

            // 기준선 ①: 시작 전 토글 — 정지할 판이 없다.
            assertFalse(controller.isPlaying)
            serial.intValue += 1
            render(3)
            assertEquals(listOf(false), reports, "시작 전 토글이 판을 얼렸다")

            controller.tap() // 시작
            assertTrue(controller.isPlaying)
            render(20)
            // 기준선 ②: 값을 안 바꾸면 판은 흐른다.
            val t0 = controller.tetris.elapsed
            render(20)
            assertTrue(controller.tetris.elapsed > t0, "기준선: 판 시계가 안 흐른다(아래 '멈춤'이 헛것)")
            assertEquals(listOf(false), reports)

            // 판 중 토글 = 정지.
            serial.intValue += 1
            render(3)
            assertEquals(listOf(false, true), reports, "판 중 토글이 판을 얼리지 않았다")
            val frozenAt = controller.tetris.elapsed
            render(30)
            assertEquals(frozenAt, controller.tetris.elapsed, "얼었는데 판 시계가 흐른다")

            // 다시 = 3-2-1(여전히 얼음) → 또 = 다시 정지. 얼음은 계속이라 알림은 늘지 않는다(바뀔 때만).
            serial.intValue += 1
            render(3)
            serial.intValue += 1
            render(3)
            assertEquals(listOf(false, true), reports, "카운트다운 · 취소 사이에 얼음이 풀렸다고 알렸다")
            assertEquals(frozenAt, controller.tetris.elapsed)
        } finally {
            scene.close()
            h.close()
        }
    }
}
