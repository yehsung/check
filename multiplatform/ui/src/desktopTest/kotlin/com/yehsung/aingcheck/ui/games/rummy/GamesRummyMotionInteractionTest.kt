// 원본: Tests/checkTests/V0370RummyBoardFeelTests.swift 의 뜻 · ios-1017 설계서 §7 — 픽셀 대신 타일 자리로 잰다: 사건 직후엔 아직 옮겨 가는 중이고 · 시간이 지나면 제자리다 · 동작 줄이기면 바로 제자리다.
// 판 화면과 말풍선 층이 **같은 앵커**를 지나는지도 여기서 잰다(상대 반응 → 상대 카드 아래).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.unit.DpRect
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasRect
import com.yehsung.aingcheck.core.rules.rummy.RummyRackGeometry
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.test.TestScope
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

private const val MATCH = "7e7e0000-0000-4000-8000-000000000070"
private const val USER = "7e7e0000-0000-4000-8000-0000000000a1"
private const val PEER = "7e7e0000-0000-4000-8000-0000000000b2"
private val ME = RummySeatFace("나", null, null)
private const val NOW_SECONDS = 1_800_000_000.0

@OptIn(ExperimentalTestApi::class)
class GamesRummyMotionInteractionTest {
    private class Rig(val h: UiGamesHarness, val rummy: RummyStore, val model: GamesRummyMatchModel) {
        val context: GamesRummyTouchContext get() = assertNotNull(model.currentContext, "화면이 재료를 안 넣었다")

        /** 지금 편집기가 말하는 그 타일의 자리(판 화면 좌표). */
        fun slotFrame(face: String): RummyCanvasRect {
            val editor = assertNotNull(rummy.editor)
            val id = editor.rack.first { it.face.text == face }.id
            val frame = context.rack.frame(assertNotNull(editor.rackLayout.slot(id)))
            return RummyCanvasRect(frame.x + context.layout.rack.x, frame.y + context.layout.rack.y, frame.width, frame.height)
        }
    }

    private fun state(
        seq: Long = 1,
        turnSeat: Long = 0,
        rack: String = """["D9","C3","A4","C1","C2"]""",
        layout: String = "[[100,50],[800,50]]",
        reactions: String = "[]",
    ): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$MATCH","status":"active","host_id":"$USER","stake":3,"seat_count":2,"seq":$seq,"pool_count":50,""" +
            """"seats":[{"seat_no":0,"user_id":"$USER","display_name":"나","state":"playing","rack_count":5,"initial_done":true},""" +
            """{"seat_no":1,"user_id":"$PEER","display_name":"비","state":"playing","rack_count":9,"initial_done":true}],""" +
            """"my_seat_no":0,"my_rack":$rack,"my_initial_done":true,"table":[["A1","A2","A3"],["B4","B5","B6","B7"]],"table_layout":$layout,""" +
            """"turn_seat_no":$turnSeat,"reactions":$reactions}""",
    )

    private fun rig(): Rig {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = true)) { null }
        val rummy = RummyStore(h.storeScope).also {
            it.clock = { SwiftDate(NOW_SECONDS) }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.heartbeatEnabled = false
            it.deadlineWakeEnabled = false
            it.rackHalfColumns = RummyRackGeometry.phoneHalfColumns
        }
        rummy.applyState(state())
        rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        return Rig(h, rummy, GamesRummyMatchModel())
    }

    private fun DesktopComposeUiTest.show(x: Rig, reduceMotion: Boolean) {
        setContent {
            AingTheme(dark = false) {
                GamesRummyMatchView(
                    x.rummy, USER, ME, reduceMotion = reduceMotion, onRules = {}, onBack = {},
                    now = { SwiftDate(NOW_SECONDS) }, modifier = Modifier.fillMaxSize(), model = x.model,
                )
            }
        }
        waitForIdle()
    }

    private fun DesktopComposeUiTest.tileBounds(face: String): DpRect = onNodeWithTag(GamesRummyMatchTags.rackTile(face), useUnmergedTree = true).getBoundsInRoot()

    private fun DesktopComposeUiTest.assertSeated(x: Rig, face: String) {
        val bounds = tileBounds(face)
        val frame = x.slotFrame(face)
        assertTrue(abs(bounds.left.value - frame.x) < 1.0 && abs(bounds.top.value - frame.y) < 1.0, "$face 가 제자리가 아니다: $bounds / $frame")
    }

    /** 기준선 대조: 정렬로 **움직이는 타일**이 있어야 이 시험이 뜻이 있다. */
    private fun movedBySort(x: Rig, before: Map<String, RummyCanvasRect>): List<String> =
        before.keys.filter { x.slotFrame(it) != before[it] }

    private val rackFaces = listOf("D9", "C3", "A4", "C1", "C2")

    // MARK: 정렬

    @Test
    fun sortingSlidesThenSettles() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x, reduceMotion = false)
        val before = rackFaces.associateWith { x.slotFrame(it) }
        mainClock.autoAdvance = false
        onNodeWithTag(GamesRummyMatchTags.SORT_NUMBER).performClick()
        mainClock.advanceTimeByFrame()
        val moved = movedBySort(x, before)
        assertTrue(moved.isNotEmpty(), "정렬해도 아무도 안 움직인다 — 시험 판이 틀렸다")
        val still = moved.filter { face ->
            val frame = x.slotFrame(face)
            val at = tileBounds(face)
            abs(at.left.value - frame.x) > 1.0 || abs(at.top.value - frame.y) > 1.0
        }
        assertTrue(still.isNotEmpty(), "정렬이 미끄러지지 않고 곧바로 제자리다")
        mainClock.advanceTimeBy(2_000)
        moved.forEach { assertSeated(x, it) }
        x.h.close()
    }

    @Test
    fun sortingWithReducedMotionIsAtOnce() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x, reduceMotion = true)
        onNodeWithTag(GamesRummyMatchTags.SORT_NUMBER).performClick()
        waitForIdle()
        rackFaces.forEach { assertSeated(x, it) }
        x.h.close()
    }

    // MARK: 뽑기

    @Test
    fun aDrawnTileFliesInFromTheDrawButton() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x, reduceMotion = false)
        mainClock.autoAdvance = false
        val drawn = """["D9","C3","A4","C1","C2","B2"]"""
        runOnIdle { x.rummy.applyState(state(seq = 2, turnSeat = 1, rack = drawn)) }
        waitForIdle()
        mainClock.advanceTimeByFrame()
        assertEquals(1, x.rummy.lastDraw?.serial, "뽑기 사건이 안 났다 — 시험 판이 틀렸다")
        val layout = x.context.layout
        val at = tileBounds("B2")
        val centerY = (at.top.value + at.bottom.value) / 2.0
        assertTrue(centerY > layout.rack.maxY, "받침대 아래 [뽑기] 자리에서 출발하지 않았다: $centerY / ${layout.rack}")
        mainClock.advanceTimeBy(2_000)
        assertSeated(x, "B2")
        x.h.close()
    }

    @Test
    fun aDrawWithReducedMotionLandsAtOnce() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x, reduceMotion = true)
        val drawn = """["D9","C3","A4","C1","C2","B2"]"""
        runOnIdle { x.rummy.applyState(state(seq = 2, turnSeat = 1, rack = drawn)) }
        waitForIdle()
        assertEquals(1, x.rummy.lastDraw?.serial)
        assertSeated(x, "B2")
        x.h.close()
    }

    // MARK: 판 변화

    @Test
    fun aMovedMeldShowsTheMotionLayerThenClearsIt() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x, reduceMotion = false)
        onNodeWithTag(GamesRummyMatchTags.BOARD_MOTION).assertDoesNotExist()
        mainClock.autoAdvance = false
        runOnIdle { x.rummy.applyState(state(seq = 2, turnSeat = 1, layout = "[[100,50],[400,200]]")) }
        waitForIdle()
        mainClock.advanceTimeByFrame()
        onNodeWithTag(GamesRummyMatchTags.BOARD_MOTION, useUnmergedTree = true).assertExists()
        mainClock.advanceTimeBy(2_000)
        onNodeWithTag(GamesRummyMatchTags.BOARD_MOTION, useUnmergedTree = true).assertDoesNotExist()
        x.h.close()
    }

    @Test
    fun aMovedMeldWithReducedMotionHasNoMotionLayer() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x, reduceMotion = true)
        runOnIdle { x.rummy.applyState(state(seq = 2, turnSeat = 1, layout = "[[100,50],[400,200]]")) }
        waitForIdle()
        onNodeWithTag(GamesRummyMatchTags.BOARD_MOTION, useUnmergedTree = true).assertDoesNotExist()
        x.h.close()
    }

    // MARK: 말풍선 자리

    /** 판 화면이 단 앵커를 층이 읽는다 — 상대 반응은 상대 줄 아래에 선다. 없으면: 앵커를 안 달아 말풍선이 조용히 사라진다. */
    @Test
    fun anOpponentReactionStandsBelowTheOpponentRow() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        val anchors = GamesRummyReactionAnchors()
        setContent {
            AingTheme(dark = false) {
                CompositionLocalProvider(LocalGamesRummyReactionAnchors provides anchors) {
                    Box(Modifier.fillMaxSize()) {
                        GamesRummyMatchView(
                            x.rummy, USER, ME, reduceMotion = true, onRules = {}, onBack = {},
                            now = { SwiftDate(NOW_SECONDS) }, modifier = Modifier.fillMaxSize(), model = x.model,
                        )
                        GamesRummyReactionLayer(x.rummy, true, { SwiftDate(NOW_SECONDS) }, Modifier.fillMaxSize())
                    }
                }
            }
        }
        waitForIdle()
        val reactions = """[{"seat_no":1,"key":"joy","at_ms":1800000000000}]"""
        runOnIdle { x.rummy.applyState(state(seq = 2, reactions = reactions)) }
        waitForIdle()
        val bounds = onNodeWithTag(GamesRummyReactionTags.bubble(1)).getBoundsInRoot()
        assertTrue(bounds.top.value >= x.context.layout.opponents.y + 30, "말풍선이 상대 줄을 가린다: $bounds")
        x.h.close()
    }
}
