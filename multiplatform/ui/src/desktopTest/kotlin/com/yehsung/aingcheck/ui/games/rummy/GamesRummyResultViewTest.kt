// 원본: Tests/checkTests/V0369RummyPanelRenderTests.swift · V0370RummyIntegrationRenderTests.swift 의 뜻(결과 · 최종 판 · 규칙 · 나가기 확인) — 픽셀 대신 값·상호작용으로 잰다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val MATCH = "7e7e0000-0000-4000-8000-000000000073"
private const val USER = "7e7e0000-0000-4000-8000-0000000000a1"
private const val PEER = "7e7e0000-0000-4000-8000-0000000000b2"
private const val THIRD = "7e7e0000-0000-4000-8000-0000000000c3"
private val ME = RummySeatFace("나", null, null)

/** 3인 판돈 5 — 받는 몫 10·5·0, 순수익 +5·0·−5. 내 자리는 2등. */
private fun finished(table: String = """[["B7","C7","D7"]]""", layout: String = "[[80,40]]"): RummyMatchState = SwiftJson.decode(
    RummyMatchState.serializer(),
    """{"id":"$MATCH","status":"finished","host_id":"$PEER","stake":5,"is_public":true,"seq":9,"end_reason":"rack_empty","my_seat_no":0,"table":$table,"table_layout":$layout,"seats":[""" +
        """{"seat_no":0,"user_id":"$USER","display_name":"나","state":"done","final_rank":2,"final_score":-12,"payout":5,"final_rack":["A1","J"]},""" +
        """{"seat_no":1,"user_id":"$PEER","display_name":"비","state":"done","final_rank":1,"final_score":42,"payout":10,"is_winner":true,"final_rack":[]},""" +
        """{"seat_no":2,"user_id":"$THIRD","display_name":"씨","state":"forfeit","final_rank":3,"final_score":-30,"payout":0,"final_rack":["D9"]}]}""",
)

private fun room(): RummyMatchState = SwiftJson.decode(
    RummyMatchState.serializer(),
    """{"id":"$MATCH","status":"forming","host_id":"$USER","stake":5,"seq":1,"my_seat_no":0,"table":[],"seats":[{"seat_no":0,"user_id":"$USER","display_name":"나","state":"joined"}]}""",
)

@OptIn(ExperimentalTestApi::class)
class GamesRummyResultViewTest {
    private class Rig(val h: UiGamesHarness, val rummy: RummyStore, val games: GamesStore)

    /** 호스트 없는 스토어 — 네트워크 0. */
    private fun rig(): Rig {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = true)) { null }
        val rummy = RummyStore(h.storeScope).also {
            it.clock = { SwiftDate(1_800_000_000.0) }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.heartbeatEnabled = false
            it.deadlineWakeEnabled = false
        }
        h.rummy = rummy
        return Rig(h, rummy, GamesStore(h.context))
    }

    private val now: () -> SwiftDate = { SwiftDate(1_800_000_000.0) }

    @Test
    fun rowsSpeakRankRubyAndRack() = runComposeUiTest {
        val x = rig()
        x.rummy.applyState(finished())
        setContent {
            AingTheme(dark = false) { GamesRummyResultView(x.rummy, USER, ME, reduceMotion = false, onRules = {}, onBack = {}, now = now, modifier = Modifier.fillMaxSize()) }
        }
        onNodeWithText("비님이 랙을 비웠어요").assertExists()
        onNodeWithText("1등").assertExists()
        onNodeWithText(RummyPhoneText.forfeit).assertExists()
        // 받은 몫(10·5·0)이 아니라 순수익이다.
        onNodeWithContentDescription("루비 +5").assertExists()
        // 내 몫은 머리 카드와 내 줄 두 곳에 선다.
        assertEquals(2, onAllNodesWithContentDescription("루비 0").fetchSemanticsNodes().size)
        assertEquals(2, onAllNodesWithText(RummyPhoneText.myResult(2, forfeited = false)).fetchSemanticsNodes().size, "머리 카드 + 내 줄")
        onNodeWithContentDescription("루비 −5").assertExists()
        // 남은 타일 — 내 랙의 조커와 기권한 사람의 랙이 보인다.
        onNodeWithContentDescription("조커").assertExists()
        onNodeWithContentDescription("주황 9").assertExists()
        // 줄은 등수 순이다(자리 순 1·0·2 와 구별되게 내 자리가 0번).
        val first = onNodeWithTag(GamesRummyResultTags.row(1)).getUnclippedBoundsInRoot().top
        val second = onNodeWithTag(GamesRummyResultTags.row(0)).getUnclippedBoundsInRoot().top
        val third = onNodeWithTag(GamesRummyResultTags.row(2)).getUnclippedBoundsInRoot().top
        assertTrue(first < second && second < third, "$first $second $third")
        x.h.close()
    }

    /** 없으면: 결과 화면에서 보낸 반응 말풍선이 설 자리가 없다. */
    @Test
    fun rowsAreReactionAnchors() = runComposeUiTest {
        val x = rig()
        x.rummy.applyState(finished())
        val anchors = GamesRummyReactionAnchors()
        setContent {
            AingTheme(dark = false) {
                CompositionLocalProvider(LocalGamesRummyReactionAnchors provides anchors) {
                    GamesRummyResultView(x.rummy, USER, ME, reduceMotion = false, onRules = {}, onBack = {}, now = now, modifier = Modifier.fillMaxSize())
                }
            }
        }
        waitForIdle()
        assertEquals(setOf(0L, 1L, 2L), anchors.rects.keys.toSet())
        x.h.close()
    }

    /** 펼침 값은 밖(GamesStore)이 쥔다 — 등수 줄 ↔ 최종 판을 갈아 끼우고, [등수]로 돌아온다. */
    @Test
    fun boardToggleSwapsRowsForTheFinalBoard() = runDesktopComposeUiTest(734, 372) {
        val x = rig()
        x.rummy.applyState(finished())
        var showsBoard by mutableStateOf(false)
        setContent {
            AingTheme(dark = false) {
                GamesRummyResultView(x.rummy, USER, ME, reduceMotion = false, onRules = {}, onBack = {}, now = now, modifier = Modifier.fillMaxSize(), showsBoard = showsBoard, onShowBoard = { showsBoard = it })
            }
        }
        onNodeWithTag(GamesRummyResultTags.FINAL_BOARD).assertDoesNotExist()
        onNodeWithTag(GamesRummyResultTags.BOARD_TOGGLE).performClick()
        waitForIdle()
        assertTrue(showsBoard)
        onNodeWithTag(GamesRummyResultTags.FINAL_BOARD).assertExists()
        onNodeWithTag(GamesRummyResultTags.row(1)).assertDoesNotExist()
        onNodeWithTag(GamesRummyResultTags.BOARD_RANKS).performClick()
        waitForIdle()
        assertFalse(showsBoard)
        onNodeWithTag(GamesRummyResultTags.FINAL_BOARD).assertDoesNotExist()
        onNodeWithTag(GamesRummyResultTags.row(1)).assertExists()
        x.h.close()
    }

    @Test
    fun finalBoardSaysSoWhenEmpty() = runDesktopComposeUiTest(734, 372) {
        val x = rig()
        x.rummy.applyState(finished(table = "[]", layout = "[]"))
        setContent { AingTheme(dark = false) { GamesRummyFinalBoard(x.rummy.match!!, true, {}, {}, Modifier.fillMaxSize()) } }
        onNodeWithText(RummyPhoneText.emptyBoard).assertExists()
        x.h.close()
    }

    /** 최종 판은 판 화면과 같은 보기다 — 폭 맞춤으로 시작해 세로로 밀고 · [전체 보기]로 높이 맞춤 · 배치는 서버 값 그대로 · 타일을 집지 않는다. */
    @Test
    fun finalBoardUsesTheSameViewAsTheMatch() = runDesktopComposeUiTest(734, 372) {
        val x = rig()
        x.rummy.applyState(finished())
        val model = GamesRummyMatchModel()
        val match = x.rummy.match!!
        setContent { AingTheme(dark = false) { GamesRummyFinalBoard(match, true, {}, {}, Modifier.fillMaxSize(), model) } }
        waitForIdle()
        val table = RummyCanvasSize(634.0, 372.0)
        assertEquals(table, model.viewport.viewport, "판 칸이 오른쪽 열 100 을 뺀 값이 아니다")
        assertEquals(GamesRummyViewport.defaultScale(table), model.viewport.scale, 0.0001, "기본이 폭 맞춤이 아니다")
        assertEquals(0.634, model.viewport.scale, 0.001)
        val logical = model.viewport.transform.toScreen(RummyCanvasPoint(80.0, 40.0))
        assertEquals(80 * 0.634, logical.x, 0.1, "서버 배치가 아니다")
        onNodeWithContentDescription(RummyPhoneText.zoomOut).assertExists()
        onNodeWithTag(GamesRummyResultTags.BOARD_INPUT).performTouchInput {
            down(Offset(300f * density, 300f * density))
            moveBy(Offset(0f, -60f * density))
            up()
        }
        waitForIdle()
        assertTrue(model.viewport.origin.y > 0, "세로로 안 밀린다")
        assertNull(model.drag, "읽기 전용 판에서 타일을 집었다")
        onNodeWithTag(GamesRummyResultTags.BOARD_ZOOM).performClick()
        waitForIdle()
        assertTrue(model.viewport.isFullView, "[전체 보기]가 높이 맞춤이 아니다")
        assertEquals(372.0 / 640.0, model.viewport.scale, 0.001)
        onNodeWithContentDescription(RummyPhoneText.zoomIn).assertExists()
        x.h.close()
    }

    /** 전환 중 세로 크기로 불려도 안전한 그림이다 — 돌아가는 동안 [등수]로 빠질 수 있다. */
    @Test
    fun finalBoardDrawsTheSafePictureOnAPortraitFrame() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        x.rummy.applyState(finished())
        var ranks = 0
        setContent { AingTheme(dark = false) { GamesRummyFinalBoard(x.rummy.match!!, true, { ranks += 1 }, {}, Modifier.fillMaxSize()) } }
        onNodeWithTag(GamesRummyMatchTags.ROTATING).assertExists()
        onNodeWithTag(GamesRummyResultTags.BOARD_INPUT).assertDoesNotExist()
        onNodeWithTag(GamesRummyMatchTags.BACK).performClick()
        assertEquals(1, ranks)
        x.h.close()
    }

    @Test
    fun toLobbyDismissesTheResult() = runComposeUiTest {
        val x = rig()
        x.rummy.applyState(finished())
        setContent {
            AingTheme(dark = false) { GamesRummyResultView(x.rummy, USER, ME, reduceMotion = false, onRules = {}, onBack = {}, now = now, modifier = Modifier.fillMaxSize()) }
        }
        assertEquals(RummyPhase.finished, x.rummy.phase)
        onNodeWithTag(GamesRummyResultTags.TO_LOBBY).performClick()
        waitForIdle()
        assertEquals(RummyPhase.lobby, x.rummy.phase)
        assertNull(x.rummy.match)
        x.h.close()
    }

    /** [한 판 더] 는 판돈·공개 여부를 맞춘 뒤 결과를 접는다(만들기·초대 요청은 스토어 시험 RummyStoreResultTest 가 잰다). */
    @Test
    fun playAgainCarriesStakeAndPublic() = runComposeUiTest {
        val x = rig()
        x.rummy.applyState(finished())
        setContent {
            AingTheme(dark = false) { GamesRummyResultView(x.rummy, USER, ME, reduceMotion = false, onRules = {}, onBack = {}, now = now, modifier = Modifier.fillMaxSize()) }
        }
        assertEquals(3L, x.rummy.selectedStake)
        assertFalse(x.rummy.createPublic)
        onNodeWithTag(GamesRummyResultTags.PLAY_AGAIN).performClick()
        waitForIdle()
        assertEquals(5L, x.rummy.selectedStake)
        assertTrue(x.rummy.createPublic)
        assertEquals(RummyPhase.lobby, x.rummy.phase)
        x.h.close()
    }

    @Test
    fun headerRulesAndBackAreSeparate() = runComposeUiTest {
        val x = rig()
        x.rummy.applyState(finished())
        var rules = 0
        var back = 0
        setContent {
            AingTheme(dark = false) {
                GamesRummyResultView(x.rummy, USER, ME, reduceMotion = false, onRules = { rules += 1 }, onBack = { back += 1 }, now = now, modifier = Modifier.fillMaxSize())
            }
        }
        onNodeWithTag(GamesRummyResultTags.RULES).performClick()
        onNodeWithContentDescription("뒤로").performClick()
        waitForIdle()
        assertEquals(1, rules)
        assertEquals(1, back)
        // 뒤로는 화면을 떠나는 일 — 결과를 스스로 접지 않는다(껍데기 판단을 지난다).
        assertEquals(RummyPhase.finished, x.rummy.phase)
        x.h.close()
    }

    /** 규칙 시트: 표의 글자와 예시 타일. 조커 예시는 두 줄(조커 · 끝과 점수)에 있다. */
    @Test
    fun rulesSheetShowsTextAndExampleTiles() = runComposeUiTest {
        setContent { AingTheme(dark = false) { GamesRummyRulesSheet(onDismiss = {}) } }
        waitForIdle()
        for (rule in RummyPhoneText.ruleList) onNodeWithText(rule.title).assertExists()
        onNodeWithText("되돌리고 1장", substring = true).assertExists()
        onNodeWithText("3명 +N·0·−N", substring = true).assertExists()
        onAllNodesWithContentDescription("조커").assertCountEquals(2)
        onAllNodesWithContentDescription("검정 3").assertCountEquals(1)
    }

    /** 방장 방 닫기: 표의 글자 · [방 닫기] 를 고르면 떠난다. 없으면: 방장이 나가도 손님이 빈 방에 남는 줄 모르고 지나간다. */
    @Test
    fun hostLeavingAsksThenLeaves() = runComposeUiTest {
        val x = rig()
        x.rummy.applyState(room())
        x.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        val back = GamesRummyBackState()
        var left = 0
        setContent { AingTheme(dark = false) { GamesRummyScreen(x.games, USER, ME, back = back, onLeave = { left += 1 }) } }
        back.handleBack(x.games) { left += 1 }
        waitForIdle()
        assertEquals(RummyCloseDecision.confirmCloseRoom, back.asking)
        val copy = assertNotNull(RummyPhoneText.exit(RummyCloseDecision.confirmCloseRoom))
        onNodeWithText(copy.detail).assertExists()
        assertEquals(0, left)
        onNodeWithTag(GamesRummyTags.EXIT_CONFIRM).performClick()
        // 방장은 닫힌 뒤에야 화면을 내린다(iOS dba0c647 — 못 닿으면 방에 남는다).
        waitForIdle()
        assertEquals(0, left, "닫히기 전에 화면을 내렸다")
        x.h.testScope.testScheduler.advanceUntilIdle()
        waitForIdle()
        assertEquals(1, left)
        assertNull(back.asking)
        onNodeWithText(copy.detail).assertDoesNotExist()
        x.h.close()
    }

    /** 판 중 확인: 기권 문구 그대로. [기권하고 나가기] 로 떠난다. */
    @Test
    fun forfeitConfirmLeaves() = runComposeUiTest {
        var kept = 0
        var confirmed = 0
        setContent {
            AingTheme(dark = false) { GamesRummyExitDialog(RummyCloseDecision.confirmForfeit, onKeep = { kept += 1 }, onConfirm = { confirmed += 1 }) }
        }
        onNodeWithText("나가면 기권돼 꼴찌가 되고 판돈을 잃어요.").assertExists()
        onNodeWithTag(GamesRummyTags.EXIT_CONFIRM).performClick()
        waitForIdle()
        assertEquals(1, confirmed)
        assertEquals(0, kept)
    }

    /** 묻지 않는 판단은 대화상자가 서지 않는다. */
    @Test
    fun exitDialogIsSilentForUnaskedDecisions() = runComposeUiTest {
        setContent { AingTheme(dark = false) { GamesRummyExitDialog(RummyCloseDecision.close, onKeep = {}, onConfirm = {}) } }
        onNodeWithTag(GamesRummyTags.EXIT_CONFIRM).assertDoesNotExist()
    }
}
