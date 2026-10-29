// 원본: 없음 — W4-b 완료 기준 ③(G §2-3) "ON_STOP 점수 확정"의 화면 쪽 몫. E§5.1: iOS .background ↔ Android ON_STOP → GamesStore.appDidEnterBackground
// (Android 배선은 androidApp screens/games/hub GamesLifecycleBridge — 그 배선 시험은 androidApp 쪽 GamesLifecycleBridgeTest).
//
// UI 루프(GamesMiniGameCanvasHost — 프레임 루프 · 손가락)로 판을 실제로 켜고 굴린 뒤 앱이 뒤로 가면:
//  · 테트리스 — **여기까지의 점수로 확정 제출**한다(폰에서 background 는 비용 0 의 무한 일시정지라 살려 두면 순위표가 흔들린다). 결과 화면 · 안내 줄
//    "여기까지 기록했어요" · 프레임 루프가 멎는다(렌더해도 점수가 안 바뀐다).
//  · 타이밍 바 · 플래피 — **기록 없이** 끝낸다(제출 0) · 안내 줄 "기록하지 않았어요".
// 기준선(기억 comparison-baseline-must-differ): 같은 판에서 앱이 앞으로 오는 것(appDidBecomeActive)은 판을 끝내지 않는다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalComposeUiApi::class, ExperimentalCoroutinesApi::class)
class MiniGameOnStopTest {
    private class Rig(val store: GamesStore, val controller: GamesPlayController, val scene: ImageComposeScene, val harness: UiGamesHarness) {
        var k = 0L
        fun render(times: Int = 1) = repeat(times) {
            k += 1
            scene.render(k * 16_666_667L)
            harness.testScope.testScheduler.runCurrent()
        }
        fun tap() {
            scene.sendPointerEvent(PointerEventType.Press, Offset(292f, 302f), type = PointerType.Touch)
            scene.sendPointerEvent(PointerEventType.Release, Offset(292f, 302f), type = PointerType.Touch)
        }
        fun submits(): List<String> = harness.server.bodies("minigame_submit_score")
        fun close() {
            scene.close()
            harness.close()
        }
    }

    private suspend fun TestScope.rig(kind: MiniGameKind): Rig {
        var issued = 0
        val h = UiGamesHarness(this) { r -> UiFixtures.miniGameRoute(r) { ++issued } }
        h.signIn()
        val store = GamesStore(h.context)
        store.appDidBecomeActive()
        store.miniGames.openScreen(kind)
        advanceUntilIdle()
        val controller = requireNotNull(store.miniGames.controller)
        val scene = ImageComposeScene(584, 604, Density(2f)) {
            AingTheme(dark = true) { GamesMiniGameCanvasHost(controller, 0L, 60, MiniGameArt.empty, Modifier.fillMaxSize()) }
        }
        scene.render(0L)
        return Rig(store, controller, scene, h)
    }

    @Test
    fun tetrisIsConfirmedAtTheScoreItReachedWhenTheAppStops() = runTest {
        val r = rig(MiniGameKind.tetris)
        try {
            r.tap() // 시작(시작 화면에서는 테트리스도 누름이 판을 켠다)
            assertTrue(r.controller.isPlaying)
            r.render(30)
            r.controller.hardDrop() // [즉시 내리기] 버튼과 같은 문 — 점수가 붙는다
            r.render(30)
            r.controller.hardDrop()
            r.render(10)
            val reached = r.controller.tetris.score
            assertTrue(reached > 0, "하드드롭 두 번이면 점수가 있다")
            // 기준선: 앞으로 오는 것은 판을 끝내지 않는다.
            r.store.appDidBecomeActive()
            assertTrue(r.controller.isPlaying, "앱이 앞으로 와도 판은 그대로")
            assertEquals(emptyList(), r.submits())
            // ON_STOP.
            r.store.appDidEnterBackground()
            r.harness.testScope.testScheduler.runCurrent()
            assertEquals(TetrisGame.Phase.Result, r.controller.tetris.phase, "확정 = 결과 화면")
            val bodies = r.submits()
            assertEquals(1, bodies.size, "확정 제출 한 번 — $bodies")
            val body = Json.parseToJsonElement(bodies.single()).jsonObject
            assertEquals("tetris", body.getValue("p_game").jsonPrimitive.content)
            assertEquals(reached.toLong(), body.getValue("p_score").jsonPrimitive.long, "나가는 순간까지의 점수")
            assertEquals("t1", body.getValue("p_token").jsonPrimitive.content)
            assertEquals(GamesMiniGameText.endedInBackground(MiniGameKind.tetris), r.store.miniGames.submitNotice)
            // 프레임 루프가 멎었다 — 더 렌더해도 판이 안 움직인다.
            val elapsed = r.controller.tetris.elapsed
            r.render(30)
            assertEquals(elapsed, r.controller.tetris.elapsed)
            assertEquals(1, r.submits().size, "다시 제출하지 않는다")
        } finally {
            r.close()
        }
    }

    @Test
    fun timingBarAndFlappyEndWithoutARecordWhenTheAppStops() = runTest {
        for (kind in listOf(MiniGameKind.timingBar, MiniGameKind.flappy)) {
            val r = rig(kind)
            try {
                r.tap()
                assertTrue(r.controller.isPlaying, "$kind: 누름이 판을 켠다")
                r.render(20)
                r.store.appDidEnterBackground()
                r.harness.testScope.testScheduler.runCurrent()
                assertTrue(!r.controller.isPlaying, "$kind: 판이 끝났다")
                when (kind) {
                    MiniGameKind.timingBar -> assertEquals(TimingBarGame.Phase.Ready, r.controller.timing.phase, "타이밍 바: 무효(시작 전으로)")
                    MiniGameKind.flappy -> assertEquals(FlappyGame.Phase.Ready, r.controller.flappy.phase, "플래피: 새 판(시작 전)으로 갈아 끼운다")
                    else -> Unit
                }
                assertEquals(emptyList(), r.submits(), "$kind: 기록하지 않는다")
                assertEquals(GamesMiniGameText.endedInBackground(kind), r.store.miniGames.submitNotice)
            } finally {
                r.close()
            }
        }
    }
}
