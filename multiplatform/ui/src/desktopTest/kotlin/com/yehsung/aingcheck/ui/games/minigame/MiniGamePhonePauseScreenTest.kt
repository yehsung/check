// 원본: Tests/CheckMobileKitTests/GamesMiniGamePauseTests.swift:921-942 @ 45ceda2d (화면 계약) · Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift @ de5c153b
//
// 폰 일시정지의 **부르는 자리**: 화면의 [일시정지] · 카드 · 3-2-1 이 허브를 지나 판을 움직이는지 실제 화면으로 잰다. iOS 는 소스 문자열로 잰 자리를 여기서는 진짜 눌러 본다.
// 기본값(Windows 창)은 [일시정지] · [그만두기] 가 없고 구동기를 안 얼린다 — 음성 짝을 같이 둔다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.minigame.MiniGamePauseState
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class, ExperimentalComposeUiApi::class)
class MiniGamePhonePauseScreenTest {
    private class Rig(val store: GamesStore, val h: UiGamesHarness) {
        val hub get() = store.miniGames
        val controller get() = requireNotNull(hub.controller)
        fun settle() = h.testScope.testScheduler.advanceUntilIdle()
    }

    private fun rig(kind: MiniGameKind, phone: Boolean = true): Rig {
        var issued = 0
        val h = UiGamesHarness(TestScope()) { r -> UiFixtures.miniGameRoute(r) { ++issued } }
        runBlocking { h.signIn() }
        val store = GamesStore(h.context)
        store.miniGames.phonePauseRules = phone
        store.miniGames.pauseSleep = { awaitCancellation() }
        store.miniGames.openScreen(kind)
        h.testScope.testScheduler.advanceUntilIdle()
        return Rig(store, h)
    }

    private val noDescription = SemanticsMatcher("contentDescription 없음") { SemanticsProperties.ContentDescription !in it.config }

    /** [일시정지]: 판이 돌 때만 · 카드가 뜨면 빠진다 · 3-2-1 에는 있다(누르면 취소). 카드의 [이어하기] 가 3-2-1 을 부르고, 그동안 판은 언다. */
    @Test
    fun thePauseButtonAndTheCardDriveTheHub() = runComposeUiTest {
        val r = rig(MiniGameKind.tetris)
        setContent { AingTheme(dark = true) { GamesMiniGameScreen(r.store, MiniGameKind.tetris, 60, MiniGameArt.empty, null, Modifier.fillMaxSize(), isPhone = true) } }
        mainClock.autoAdvance = false // 판이 돌면 프레임 루프가 안 멈춰 idle 이 오지 않는다
        waitForIdle()
        onNodeWithTag(MiniGameScreenTags.PAUSE).assertDoesNotExist()

        r.controller.tap()
        mainClock.advanceTimeByFrame()
        onNodeWithTag(MiniGameScreenTags.RESUME).assertDoesNotExist()
        onNodeWithTag(MiniGameScreenTags.PAUSE).performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(MiniGamePauseState.Paused, r.controller.pauseState, "[일시정지] 가 허브를 안 지난다")
        mainClock.advanceTimeByFrame()

        onNodeWithTag(MiniGameScreenTags.PAUSE).assertDoesNotExist() // 카드에 같은 뜻의 단추가 둘이면 어느 쪽인지 고민하게 된다
        onNodeWithText(GamesMiniGameText.pauseSubtitle(MiniGameKind.tetris)).assertExists()
        onNodeWithTag(MiniGameScreenTags.QUIT).assertExists()
        onNodeWithTag(MiniGameScreenTags.RESUME).performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(MiniGamePauseState.Resuming(3), r.controller.pauseState)
        mainClock.advanceTimeByFrame()

        onNodeWithText("3").assertExists()
        onNodeWithText(GamesMiniGameText.resumeCountdownCaption).assertExists()
        onNodeWithTag(MiniGameScreenTags.PAUSE).assertExists()
        onNodeWithTag(MiniGameScreenTags.RESUME).assertDoesNotExist()
        val frozenElapsed = r.controller.tetris.elapsed
        repeat(30) { mainClock.advanceTimeByFrame() }
        assertEquals(frozenElapsed, r.controller.tetris.elapsed, "3-2-1 동안 판이 움직였다")
        onNodeWithTag(MiniGameScreenTags.PAUSE).performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(MiniGamePauseState.Paused, r.controller.pauseState, "3-2-1 중 누르면 취소하고 다시 멈춘다")
        r.hub.togglePause()
        while (r.hub.advanceResumeCountdown()) Unit
        mainClock.advanceTimeByFrame()
        mainClock.advanceTimeByFrame()
        repeat(10) { mainClock.advanceTimeByFrame() }
        assertTrue(r.controller.tetris.elapsed > frozenElapsed, "다 내려갔는데 판이 안 돈다")
        r.h.close()
    }

    /** [그만두기]: 표대로 — 테트리스는 그 점수로 제출하고 결과로, 플래피는 제출 없이 시작 전으로. 화면은 그대로다. */
    @Test
    fun quitFollowsTheTable() = runComposeUiTest {
        val tetris = rig(MiniGameKind.tetris)
        val flappy = rig(MiniGameKind.flappy)
        val shown = mutableIntStateOf(0)
        setContent {
            AingTheme(dark = true) {
                val r = if (shown.intValue == 0) tetris else flappy
                GamesMiniGameScreen(r.store, if (shown.intValue == 0) MiniGameKind.tetris else MiniGameKind.flappy, 60, MiniGameArt.empty, null, Modifier.fillMaxSize(), isPhone = true)
            }
        }
        mainClock.autoAdvance = false
        waitForIdle()
        tetris.controller.tap()
        repeat(4) { tetris.controller.softDropOneCell() }
        val score = tetris.controller.score
        tetris.hub.togglePause()
        mainClock.advanceTimeByFrame()
        onNodeWithTag(MiniGameScreenTags.QUIT).performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(TetrisGame.Phase.Result, tetris.controller.tetris.phase)
        tetris.h.testScope.testScheduler.runCurrent()
        val bodies = tetris.h.server.bodies("minigame_submit_score")
        assertEquals(1, bodies.size, "$bodies")
        assertTrue("\"p_score\":$score" in bodies[0], bodies[0])
        mainClock.advanceTimeByFrame()
        onNodeWithTag(MiniGameScreenTags.QUIT).assertDoesNotExist()

        shown.intValue = 1
        mainClock.advanceTimeByFrame()
        mainClock.advanceTimeByFrame()
        flappy.settle()
        flappy.controller.tap()
        flappy.hub.togglePause()
        mainClock.advanceTimeByFrame()
        onNodeWithText(GamesMiniGameText.pauseSubtitle(MiniGameKind.flappy)).assertExists()
        onNodeWithTag(MiniGameScreenTags.QUIT).performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(FlappyGame.Phase.Ready, flappy.controller.flappy.phase)
        flappy.settle()
        assertEquals(emptyList(), flappy.h.server.bodies("minigame_submit_score"), "플래피를 접었는데 기록했다(사용자 답 '지금처럼 버림')")
        tetris.h.close()
        flappy.h.close()
    }

    /** 정지 중 TalkBack 은 판을 못 읽고 버튼 줄도 없다(점수·조작이 스크림 뒤에 남으면 가린 것이 아니다). 도는 판에는 있다(대조). */
    @Test
    fun aFrozenBoardIsHiddenFromTalkBack() = runComposeUiTest {
        val r = rig(MiniGameKind.tetris)
        setContent { AingTheme(dark = true) { GamesMiniGameScreen(r.store, MiniGameKind.tetris, 60, MiniGameArt.empty, null, Modifier.fillMaxSize(), isPhone = true) } }
        mainClock.autoAdvance = false
        waitForIdle()
        r.controller.tap()
        mainClock.advanceTimeByFrame()
        onNodeWithTag(MiniGameScreenTags.HOLD).assertExists()
        onNodeWithTag(MiniGameScreenTags.CANVAS).assert(!noDescription)
        r.hub.togglePause()
        mainClock.advanceTimeByFrame()
        onNodeWithTag(MiniGameScreenTags.HOLD).assertDoesNotExist()
        onNodeWithTag(MiniGameScreenTags.CANVAS).assert(noDescription)
        r.h.close()
    }

    /** 스크림 위 탭은 판으로 새지 않는다 · 버튼 줄 자리를 눌러도 조용하다. 풀리면 같은 자리 탭이 먹는다(대조). */
    @Test
    fun touchesOnAFrozenScreenNeverReachTheRound() = runTest2 { r, scene, press ->
        val c = r.controller
        c.tap()
        scene.renderFrames(3)
        val before = c.flappy
        val serial = c.tapSerial
        r.hub.togglePause()
        scene.renderFrames(3)
        press(CANVAS_CENTER)
        scene.renderFrames(3)
        assertEquals(before, c.flappy, "스크림 위 탭이 판으로 샜다")
        assertEquals(serial, c.tapSerial)
        assertEquals(MiniGamePauseState.Paused, c.pauseState, "스크림 위 탭이 판을 풀었다")
        r.hub.togglePause()
        while (r.hub.advanceResumeCountdown()) Unit
        scene.renderFrames(3)
        press(CANVAS_CENTER)
        scene.renderFrames(1)
        assertTrue(c.tapSerial > serial, "대조: 풀린 판에 같은 자리 탭이 안 먹는다 — 위 단언이 공허하다")
    }

    /** 얼기 전에 닿아 있던 손가락은 풀린 뒤에도 판을 못 움직인다(뗌은 전화 수신이면 안 온다 — 끌기가 새 걸음으로 먹으면 첫 조각이 튄다). 안 얼렸으면 움직인다(대조). */
    @Test
    fun aContactHeldAcrossAFreezeDoesNothingAfterThawing() {
        for (freeze in listOf(false, true)) {
            val r = rig(MiniGameKind.tetris)
            var k = 0L
            val scene = ImageComposeScene(780, 1688, Density(2f)) {
                AingTheme(dark = true) { GamesMiniGameScreen(r.store, MiniGameKind.tetris, 60, MiniGameArt.empty, null, Modifier.fillMaxSize(), isPhone = true) }
            }
            fun render(times: Int) = repeat(times) { k += 1; scene.render(k * 16_666_667L) }
            try {
                render(3)
                r.controller.tap()
                render(3)
                val column = assertNotNull(r.controller.tetris.active).column
                scene.sendPointerEvent(PointerEventType.Press, Offset(CANVAS_CENTER.x, CANVAS_CENTER.y), type = PointerType.Touch)
                render(1)
                if (freeze) {
                    r.hub.togglePause()
                    render(2)
                    r.hub.togglePause()
                    while (r.hub.advanceResumeCountdown()) Unit
                    render(2)
                }
                scene.sendPointerEvent(PointerEventType.Move, Offset(CANVAS_CENTER.x + 200f, CANVAS_CENTER.y), type = PointerType.Touch)
                render(1)
                val after = assertNotNull(r.controller.tetris.active).column
                if (freeze) assertEquals(column, after, "얼기 전 접촉이 풀린 판을 움직였다")
                else assertNotEquals(column, after, "대조: 안 얼린 끌기가 안 먹는다 — 위 단언이 공허하다")
            } finally {
                scene.close()
                r.h.close()
            }
        }
    }

    /** 기본값(Windows 창): [일시정지] · [그만두기] 가 없고, 정지는 화면의 상태라 구동기·허브 시계가 그대로다. 화면의 ESC 토글과 카드([이어하기])는 산다. */
    @Test
    fun theDefaultPathHasNoPhonePauseChrome() = runComposeUiTest {
        val r = rig(MiniGameKind.tetris, phone = false)
        val serial = mutableIntStateOf(0)
        setContent { AingTheme(dark = true) { GamesMiniGameScreen(r.store, MiniGameKind.tetris, 60, MiniGameArt.empty, null, Modifier.fillMaxSize(), pauseToggleSerial = serial.intValue) } }
        mainClock.autoAdvance = false
        waitForIdle()
        r.controller.tap()
        mainClock.advanceTimeByFrame()
        onNodeWithTag(MiniGameScreenTags.PAUSE).assertDoesNotExist()
        serial.intValue += 1
        mainClock.advanceTimeByFrame()
        mainClock.advanceTimeByFrame()
        onNodeWithText(GamesMiniGameText.resumeAction).assertExists()
        onNodeWithTag(MiniGameScreenTags.QUIT).assertDoesNotExist()
        assertEquals(MiniGamePauseState.None, r.controller.pauseState, "Windows 정지가 구동기로 샜다 — 입력 가드가 그쪽으로 뜻이 바뀐다")
        assertFalse(r.controller.isFrozen)
        assertEquals(0.0, r.hub.pausedSecondsUsed)
        r.h.close()
    }

    private class Scene(private val scene: ImageComposeScene) {
        private var k = 0L
        fun renderFrames(times: Int) = repeat(times) { k += 1; scene.render(k * 16_666_667L) }
    }

    /** 합성 눌렀다 떼기가 필요한 시험의 틀(플래피 — 탭이 곧 행동). */
    private fun runTest2(body: (Rig, Scene, (Offset) -> Unit) -> Unit) {
        val r = rig(MiniGameKind.flappy)
        val image = ImageComposeScene(780, 1688, Density(2f)) {
            AingTheme(dark = true) { GamesMiniGameScreen(r.store, MiniGameKind.flappy, 60, MiniGameArt.empty, null, Modifier.fillMaxSize(), isPhone = true) }
        }
        val scene = Scene(image)
        try {
            scene.renderFrames(3)
            body(r, scene) { at ->
                image.sendPointerEvent(PointerEventType.Press, at, type = PointerType.Touch)
                image.sendPointerEvent(PointerEventType.Release, at, type = PointerType.Touch)
            }
        } finally {
            image.close()
            r.h.close()
        }
    }

    private companion object {
        /** 배율 2 · 폭 390dp 화면의 캔버스 가운데(머리 52dp + 머리 줄 ≈ 30dp + 캔버스 절반 ≈ 195dp). */
        val CANVAS_CENTER = Offset(390f, 500f)
    }
}
