// 원본: Tests/checkTests/V0369RummyPanelRenderTests.swift · V0370RummyBoardFeelTests.swift 의 뜻 — 픽셀 대신 상호작용으로 잰다(끌어 놓으면 스토어 편집기가 바뀐다 · 빈 펠트는 보기만 바꾼다 · 핀치 중 한 손가락 금지).
//
// 판단은 값 시험(GamesRummyBoardGeometryTest · GamesRummyMatchInputTest)이 잰다. 여기는 **화면이 그 문에 닿는가**를 잰다: 입력 층 하나 · 버튼이 먼저 눌림 · 0.5초 · 두 손가락.
// 호스트 없는 스토어 — 네트워크 0. 내 자리는 my_seat_no 로 안다(코어 규약). 스냅숏 png 는 없다(값 · 상호작용만).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyRackGeometry
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSort
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
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
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val MATCH = "7e7e0000-0000-4000-8000-000000000068"
private const val USER = "7e7e0000-0000-4000-8000-0000000000a1"
private const val PEER = "7e7e0000-0000-4000-8000-0000000000b2"
private val ME = RummySeatFace("나", null, null)
private const val NOW_SECONDS = 1_800_000_000.0

@OptIn(ExperimentalTestApi::class)
class GamesRummyMatchInteractionTest {
    private class Rig(val h: UiGamesHarness, val rummy: RummyStore, val model: GamesRummyMatchModel) {
        val context: GamesRummyTouchContext get() = assertNotNull(model.currentContext, "화면이 재료를 안 넣었다")

        fun tileID(face: String): Int {
            val editor = assertNotNull(rummy.editor)
            return editor.rack.firstOrNull { it.face.text == face }?.id ?: editor.melds.flatten().first { it.face.text == face }.id
        }

        fun rackPoint(face: String): RummyCanvasPoint {
            val frame = context.rack.frame(assertNotNull(assertNotNull(rummy.editor).rackLayout.slot(tileID(face))))
            return RummyCanvasPoint(frame.midX + context.layout.rack.x, frame.midY + context.layout.rack.y)
        }

        /** 지금 보기로 논리 좌표 → 판 화면 좌표. */
        fun screen(x: Double, y: Double): RummyCanvasPoint {
            val local = model.viewport.transform.toScreen(RummyCanvasPoint(x, y))
            return RummyCanvasPoint(local.x + context.layout.table.x, local.y + context.layout.table.y)
        }

        fun finger(pointer: RummyCanvasPoint) = RummyCanvasPoint(pointer.x, pointer.y + GamesRummyGestureRules.fingerLift)
    }

    private fun state(
        turnSeat: Long = 0,
        table: String = """[["A1","A2","A3"],["B4","B5","B6","B7"]]""",
        layout: String = "[[100,50],[800,50]]",
        rack: String = """["A4","C1","C2","C3","D9"]""",
    ): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$MATCH","status":"active","host_id":"$USER","stake":3,"seat_count":2,"seq":1,"pool_count":50,""" +
            """"seats":[{"seat_no":0,"user_id":"$USER","display_name":"나","state":"playing","rack_count":5,"initial_done":true},""" +
            """{"seat_no":1,"user_id":"$PEER","display_name":"비","state":"playing","rack_count":9,"initial_done":true}],""" +
            """"my_seat_no":0,"my_rack":$rack,"my_initial_done":true,"table":$table,"table_layout":$layout,"turn_seat_no":$turnSeat}""",
    )

    private fun rig(initial: RummyMatchState = state(), engaged: Boolean = true): Rig {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = true)) { null }
        val rummy = RummyStore(h.storeScope).also {
            it.clock = { SwiftDate(NOW_SECONDS) }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.heartbeatEnabled = false
            it.deadlineWakeEnabled = false
            it.rackHalfColumns = RummyRackGeometry.phoneHalfColumns
        }
        rummy.applyState(initial)
        if (engaged) rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        return Rig(h, rummy, GamesRummyMatchModel())
    }

    private fun DesktopComposeUiTest.show(x: Rig, onBack: () -> Unit = {}, onRules: () -> Unit = {}, fontScale: Float? = null) {
        setContent {
            AingTheme(dark = false) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                    GamesRummyMatchView(
                        x.rummy, USER, ME, reduceMotion = true, onRules = onRules, onBack = onBack,
                        now = { SwiftDate(NOW_SECONDS) }, modifier = Modifier.fillMaxSize(), model = x.model,
                    )
                }
            }
        }
        waitForIdle()
    }

    private fun DesktopComposeUiTest.drag(from: RummyCanvasPoint, to: RummyCanvasPoint) {
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput {
            val d = density
            down(Offset((from.x * d).toFloat(), (from.y * d).toFloat()))
            moveTo(Offset(((from.x + to.x) / 2 * d).toFloat(), ((from.y + to.y) / 2 * d).toFloat()))
            moveTo(Offset((to.x * d).toFloat(), (to.y * d).toFloat()))
            up()
        }
        waitForIdle()
    }

    // MARK: 끌어 놓기

    @Test
    fun droppingARackTileChangesTheStoreEditor() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val a4 = x.tileID("A4")
        drag(x.rackPoint("A4"), x.finger(x.screen(100.0 + 120 - 6, 78.0)))
        val editor = assertNotNull(x.rummy.editor)
        assertEquals(listOf("A1", "A2", "A3", "A4"), editor.melds[0].map { it.face.text })
        assertTrue(editor.rack.none { it.id == a4 })
        assertNull(x.model.drag, "놓았는데 손에 남았다")
        x.h.close()
    }

    @Test
    fun droppingOnFeltMakesANewMeldInThatPlace() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        drag(x.rackPoint("D9"), x.finger(x.screen(300.0, 300.0)))
        val editor = assertNotNull(x.rummy.editor)
        assertEquals(3, editor.melds.size)
        assertEquals(listOf("D9"), editor.melds[2].map { it.face.text })
        x.h.close()
    }

    /** 8 안에서 0.5초 버티면 묶음째 — 끌면 덩어리가 통째로 간다. 기준선: 안 버티면 한 장이다. */
    @Test
    fun holdingHalfASecondLiftsTheChain() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val start = x.rackPoint("C2")
        val target = x.finger(x.screen(300.0, 300.0))
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput { down(Offset((start.x * density).toFloat(), (start.y * density).toFloat())) }
        waitForIdle()
        assertNull(x.model.lift, "누르자마자 집혔다")
        mainClock.advanceTimeBy(GamesRummyGestureRules.liftDelayMillis + 100)
        waitForIdle()
        assertEquals(listOf("C1", "C2", "C3").map(x::tileID), x.model.lift?.ids, "0.5초를 버텼는데 안 집혔다")
        assertEquals(1, x.model.liftSerial)
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput {
            moveTo(Offset((target.x * density).toFloat(), (target.y * density).toFloat()))
            up()
        }
        waitForIdle()
        assertEquals(listOf("C1", "C2", "C3"), assertNotNull(x.rummy.editor).melds.last().map { it.face.text })
        x.h.close()
    }

    @Test
    fun aQuickDragTakesOneTile() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        drag(x.rackPoint("C2"), x.finger(x.screen(300.0, 300.0)))
        assertEquals(listOf("C2"), assertNotNull(x.rummy.editor).melds.last().map { it.face.text })
        assertEquals(0, x.model.liftSerial)
        x.h.close()
    }

    /** 판 출신을 받침대에 놓으면 빨간 표시 후 제자리(R-14). */
    @Test
    fun boardTileOnTheRackIsRefusedAndStays() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val before = assertNotNull(x.rummy.editor).copy()
        val rackCenter = RummyCanvasPoint(x.context.layout.rack.midX, x.context.layout.rack.midY)
        drag(x.screen(160.0, 78.0), x.finger(rackCenter))
        assertEquals(before, x.rummy.editor, "판 타일이 받침대로 갔다")
        assertEquals(1, x.model.refuseSerial)
        onNodeWithTag(GamesRummyMatchTags.RACK_REFUSED).assertExists()
        mainClock.advanceTimeBy(700)
        waitForIdle()
        assertFalse(x.model.refusedFlash, "빨간 표시가 안 꺼졌다")
        onNodeWithTag(GamesRummyMatchTags.RACK_REFUSED).assertDoesNotExist()
        x.h.close()
    }

    /** 내 차례가 아니면 받침대 재배치만 — 판에 놓아도 아무 일도 없고 판 타일은 펠트다. */
    @Test
    fun notMyTurnOnlyRearrangesTheRack() = runDesktopComposeUiTest(393, 759) {
        val x = rig(state(turnSeat = 1))
        show(x)
        val before = assertNotNull(x.rummy.editor).copy()
        drag(x.rackPoint("D9"), x.finger(x.screen(300.0, 300.0)))
        assertEquals(before, x.rummy.editor, "남의 차례에 판으로 나갔다")
        val rackRow2 = x.context.rack.frame(RummyRackSlot(1, 12))
        drag(x.rackPoint("D9"), x.finger(RummyCanvasPoint(rackRow2.midX, x.context.layout.rack.y + rackRow2.midY)))
        assertEquals(1, assertNotNull(x.rummy.editor).rackLayout.slot(x.tileID("D9"))?.row, "받침대 안 재배치가 안 됐다")
        x.h.close()
    }

    // MARK: 판 밀기 · 핀치

    @Test
    fun draggingFeltMovesOnlyTheOffset() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val editor = assertNotNull(x.rummy.editor).copy()
        val scale = x.model.viewport.scale
        val origin = x.model.viewport.origin
        val start = x.screen(300.0, 300.0)
        drag(start, RummyCanvasPoint(start.x - 80, start.y))
        assertEquals(editor, x.rummy.editor, "판을 밀었는데 편집기가 바뀌었다")
        assertEquals(scale, x.model.viewport.scale, "배율이 저절로 바뀌었다")
        assertEquals(origin.x + 80 / scale, x.model.viewport.origin.x, 0.5, "손을 따라 안 밀렸다")
        x.h.close()
    }

    /** 두 손가락은 핀치만 — 편집기를 안 건드리고 배율만 바뀐다 · 떼면 또렷하게 다시 그린다 · 다음 손은 새로 분류된다. */
    @Test
    fun twoFingersOnlyPinch() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val editor = assertNotNull(x.rummy.editor).copy()
        val before = x.model.viewport.scale
        val a = x.screen(200.0, 350.0)
        val b = x.screen(320.0, 350.0)
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput {
            val d = density
            down(0, Offset((a.x * d).toFloat(), (a.y * d).toFloat()))
            down(1, Offset((b.x * d).toFloat(), (b.y * d).toFloat()))
            moveTo(1, Offset(((b.x + 40) * d).toFloat(), (b.y * d).toFloat()))
            moveTo(1, Offset(((b.x + 80) * d).toFloat(), (b.y * d).toFloat()))
        }
        waitForIdle()
        assertTrue(x.model.viewport.scale > before, "핀치가 안 먹었다")
        assertEquals(before, x.model.renderScale, "핀치 중에 판 층을 다시 그린다")
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput {
            up(1)
            up(0)
        }
        waitForIdle()
        assertEquals(editor, x.rummy.editor)
        assertEquals(x.model.viewport.scale, x.model.renderScale, "떼었는데 또렷하게 안 그린다")
        assertTrue(x.model.machine.isIdle, "핀치 뒤 다음 손이 막힌다")
        x.h.close()
    }

    /** 핀치 중 한 손가락 끌기 금지: 타일을 누르던 손가락이 핀치가 되면 그 손가락을 끌어도 타일이 안 움직인다. */
    @Test
    fun oneFingerCannotDragDuringAPinch() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val editor = assertNotNull(x.rummy.editor).copy()
        val tile = x.rackPoint("D9")
        val felt = x.screen(300.0, 300.0)
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput {
            val d = density
            down(0, Offset((tile.x * d).toFloat(), (tile.y * d).toFloat()))
            down(1, Offset((felt.x * d).toFloat(), (felt.y * d).toFloat()))
            moveTo(0, Offset((felt.x * d).toFloat(), ((felt.y - 80) * d).toFloat()))
        }
        waitForIdle()
        assertNull(x.model.drag, "핀치 중에 타일이 집혔다")
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput {
            up(1)
            moveBy(0, Offset(0f, -40f))
            up(0)
        }
        waitForIdle()
        assertEquals(editor, x.rummy.editor, "핀치 끝에 타일이 놓였다")
        assertTrue(x.model.machine.isIdle)
        x.h.close()
    }

    /** 끄는 중 두 번째 손가락은 무시 — 끌기가 이어지고 배율은 그대로다. */
    @Test
    fun secondFingerDuringADragIsIgnored() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val scale = x.model.viewport.scale
        val start = x.rackPoint("D9")
        val mid = x.finger(x.screen(300.0, 250.0))
        val end = x.finger(x.screen(300.0, 300.0))
        val other = x.screen(100.0, 400.0)
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput {
            val d = density
            down(0, Offset((start.x * d).toFloat(), (start.y * d).toFloat()))
            moveTo(0, Offset((mid.x * d).toFloat(), (mid.y * d).toFloat()))
            down(1, Offset((other.x * d).toFloat(), (other.y * d).toFloat()))
            moveTo(1, Offset(((other.x + 60) * d).toFloat(), (other.y * d).toFloat()))
            moveTo(0, Offset((end.x * d).toFloat(), (end.y * d).toFloat()))
            up(1)
            up(0)
        }
        waitForIdle()
        assertEquals(scale, x.model.viewport.scale, "끄는 중에 핀치가 먹었다")
        assertEquals(listOf("D9"), assertNotNull(x.rummy.editor).melds.last().map { it.face.text }, "끌기가 끊겼다")
        x.h.close()
    }

    // MARK: 버튼이 입력 층보다 먼저

    @Test
    fun buttonsAreAboveTheInputLayer() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        var back = 0
        var rules = 0
        show(x, onBack = { back += 1 }, onRules = { rules += 1 })
        onNodeWithTag(GamesRummyMatchTags.BACK).performClick()
        assertEquals(1, back)
        onNodeWithTag(GamesRummyMatchTags.RULES).performClick()
        assertEquals(1, rules)
        onNodeWithTag(GamesRummyMatchTags.SORT_COLOR).performClick()
        waitForIdle()
        assertEquals(RummyRackSort.color, x.rummy.rackSortMode)
        // 손은 안 닿았다(입력 층이 같이 받았으면 분류가 돌았다).
        assertTrue(x.model.machine.isIdle)
        x.h.close()
    }

    /** [되돌리기]는 놓은 뒤에만 켜지고, 누르면 처음 판으로 돌아간다. */
    @Test
    fun undoComesAliveAfterAMove() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val start = assertNotNull(x.rummy.editor).copy()
        onNodeWithTag(GamesRummyMatchTags.UNDO).performClick()
        waitForIdle()
        assertEquals(start, x.rummy.editor, "할 것이 없는데 눌렸다")
        drag(x.rackPoint("D9"), x.finger(x.screen(300.0, 300.0)))
        assertNotEquals(start.melds, assertNotNull(x.rummy.editor).melds)
        onNodeWithTag(GamesRummyMatchTags.UNDO).performClick()
        waitForIdle()
        assertEquals(start.melds, assertNotNull(x.rummy.editor).melds, "되돌아가지 않았다")
        x.h.close()
    }

    @Test
    fun zoomToggleSwitchesFullViewAndBack() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val base = x.model.viewport.scale
        assertFalse(x.model.viewport.isFullView)
        onNodeWithTag(GamesRummyMatchTags.ZOOM).performClick()
        waitForIdle()
        assertTrue(x.model.viewport.isFullView)
        assertEquals(x.model.viewport.scale, x.model.renderScale)
        onNodeWithTag(GamesRummyMatchTags.ZOOM).performClick()
        waitForIdle()
        assertEquals(base, x.model.viewport.scale, 0.0001)
        x.h.close()
    }

    /** 화면 밖 묶음 배지: 그쪽 수를 말하고, 누르면 그쪽으로 민다 · 다 보이면 사라진다. 판 변화로 배율이 안 바뀐다. */
    @Test
    fun offscreenBadgeRevealsTheMeld() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        val scale = x.model.viewport.scale
        onNodeWithContentDescription(RummyPhoneText.offscreenRight(1)).assertExists()
        onNodeWithTag(GamesRummyMatchTags.OFFSCREEN_LEFT).assertDoesNotExist()
        onNodeWithTag(GamesRummyMatchTags.OFFSCREEN_RIGHT).performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyMatchTags.OFFSCREEN_RIGHT).assertDoesNotExist()
        onNodeWithContentDescription(RummyPhoneText.offscreenLeft(1)).assertExists()
        assertEquals(scale, x.model.viewport.scale, "미는데 배율이 바뀌었다")
        // 놓아도 배율은 그대로다(맥 교훈).
        drag(x.rackPoint("D9"), x.finger(x.screen(800.0, 300.0)))
        assertEquals(scale, x.model.viewport.scale, "판 변화로 배율이 저절로 바뀌었다")
        x.h.close()
    }

    // MARK: 안내

    /** 놀던 기기: 안내 카드만 얹고 입력은 안 막는다. 손댄 기기엔 카드가 없다. */
    @Test
    fun otherDeviceCardDoesNotBlockInput() = runDesktopComposeUiTest(393, 759) {
        val x = rig(engaged = false)
        show(x)
        onNodeWithText(RummyPhoneText.otherDevice).assertExists()
        drag(x.rackPoint("D9"), x.finger(x.screen(300.0, 300.0)))
        assertEquals(listOf("D9"), assertNotNull(x.rummy.editor).melds.last().map { it.face.text }, "카드가 입력을 막았다")
        x.h.close()
    }

    @Test
    fun engagedDeviceSeesNoCard() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x)
        onNodeWithTag(GamesRummyMatchTags.ELSEWHERE).assertDoesNotExist()
        x.h.close()
    }

    @Test
    fun seatsAndStatusSpeakTheStore() = runDesktopComposeUiTest(393, 759) {
        val x = rig(state(turnSeat = 1))
        show(x)
        onNodeWithContentDescription(GamesRummyMatchText.seatSummary("비", 9, true, emptyList())).assertExists()
        onNodeWithTag(GamesRummyMatchTags.STATUS).assertExists()
        // 상태 줄과 판 아래 줄이 같은 글자를 쓴다(맥과 같다).
        assertTrue(onAllNodesWithText(RummyPhoneText.turnOf("비"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        onNodeWithText(RummyPhoneText.pool(50), useUnmergedTree = true).assertExists()
        // 받침대는 면 이름으로 읽힌다.
        onNodeWithContentDescription("주황 9").assertExists()
        x.h.close()
    }

    // MARK: 폭 · 큰 글자

    /** 좁은 폭 · 큰 글자에서 동작 줄 버튼이 화면 안이고 서로 안 겹친다. */
    private fun DesktopComposeUiTest.assertActionsFit(width: Double, height: Double) {
        val tags = listOf(GamesRummyMatchTags.SUBMIT, GamesRummyMatchTags.DRAW, GamesRummyMatchTags.UNDO, GamesRummyMatchTags.SORT_NUMBER, GamesRummyMatchTags.SORT_COLOR)
        val rects = tags.map { onNodeWithTag(it).fetchSemanticsNode().boundsInRoot }
        for ((index, rect) in rects.withIndex()) {
            assertTrue(rect.left >= -0.5f && rect.right <= width + 0.5 && rect.bottom <= height + 0.5, "${tags[index]} 화면 밖 $rect")
            assertTrue(rect.height >= 20f, "${tags[index]} 납작하다 $rect")
            for (other in rects.drop(index + 1)) assertFalse(rect.overlaps(other), "${tags[index]} 겹침 $rect $other")
        }
    }

    @Test
    fun narrowPhoneKeepsTheActionsOnScreen() = runDesktopComposeUiTest(320, 548) {
        val x = rig()
        show(x)
        assertActionsFit(320.0, 548.0)
        x.h.close()
    }

    @Test
    fun bigTextSplitsActionsAndKeepsThemOnScreen() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        show(x, fontScale = 2f)
        assertActionsFit(393.0, 759.0)
        val submit = onNodeWithTag(GamesRummyMatchTags.SUBMIT).fetchSemanticsNode().boundsInRoot
        val draw = onNodeWithTag(GamesRummyMatchTags.DRAW).fetchSemanticsNode().boundsInRoot
        assertTrue(draw.top >= submit.bottom, "큰 글자인데 한 줄이다")
        x.h.close()
    }

    // MARK: 100장

    /** 판 타일 100장 — 그리는 데 터지지 않고, 밀어도 판 층 배율이 그대로다(층만 옮긴다). */
    @Test
    fun aHundredTilesPanWithoutRedrawInputs() = runDesktopComposeUiTest(393, 759) {
        val sets = (0 until 26).map { index ->
            val color = "ABCD"[index % 4]
            val start = index % 9 + 1
            (start until start + 4).joinToString(",", "[", "]") { "\"$color$it\"" }
        }
        val points = sets.indices.map { index -> "[${(index % 6) * 170},${(index / 6) * 80}]" }
        val x = rig(state(table = sets.joinToString(",", "[", "]"), layout = points.joinToString(",", "[", "]")))
        show(x)
        assertEquals(104, x.context.scene.tileCount)
        val render = x.model.renderScale
        val start = x.screen(300.0, 600.0)
        drag(start, RummyCanvasPoint(start.x - 100, start.y))
        assertTrue(x.model.viewport.origin.x > 0)
        assertEquals(render, x.model.renderScale, "밀었는데 판 층을 다시 그린다")
        x.h.close()
    }

    /** 칸 크기 값이 받침대 줄 수를 따른다 — 넘치면 판이 줄어든다(재료 값). */
    @Test
    fun threeRowRackShrinksTheBoard() = runDesktopComposeUiTest(393, 759) {
        val rack = ((1..13).map { "\"A$it\"" } + (1..10).map { "\"B$it\"" }).joinToString(",", "[", "]")
        val x = rig(state(rack = rack))
        show(x)
        assertEquals(3, x.context.layout.rackRows, "23장인데 3줄이 아니다")
        val size = RummyCanvasSize(x.context.layout.table.width, x.context.layout.table.height)
        assertEquals(size, x.model.viewport.viewport, "보기가 칸 크기를 안 따른다")
        x.h.close()
    }
}
