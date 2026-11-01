// 원본: Tests/checkTests/V0369RummyPanelRenderTests.swift · V0370RummyBoardFeelTests.swift 의 뜻 — 픽셀 대신 상호작용으로 잰다(끌어 놓으면 스토어 편집기가 바뀐다 · 빈 펠트는 보기만 바꾼다 · 핀치 중 한 손가락 금지).
//
// 판단은 값 시험(GamesRummyBoardGeometryTest · GamesRummyMatchInputTest · GamesRummyLandscapeTest)이 잰다. 여기는 **화면이 그 문에 닿는가**를 잰다: 입력 층 하나 · 버튼이 먼저 눌림 · 0.5초 · 두 손가락.
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

        fun finger(pointer: RummyCanvasPoint) = context.layout.finger(pointer)
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
    fun droppingARackTileChangesTheStoreEditor() = runDesktopComposeUiTest(734, 372) {
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
    fun droppingOnFeltMakesANewMeldInThatPlace() = runDesktopComposeUiTest(734, 372) {
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
    fun holdingHalfASecondLiftsTheChain() = runDesktopComposeUiTest(734, 372) {
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
    fun aQuickDragTakesOneTile() = runDesktopComposeUiTest(734, 372) {
        val x = rig()
        show(x)
        drag(x.rackPoint("C2"), x.finger(x.screen(300.0, 300.0)))
        assertEquals(listOf("C2"), assertNotNull(x.rummy.editor).melds.last().map { it.face.text })
        assertEquals(0, x.model.liftSerial)
        x.h.close()
    }

    /** 판 출신을 받침대에 놓으면 빨간 표시 후 제자리(R-14). */
    @Test
    fun boardTileOnTheRackIsRefusedAndStays() = runDesktopComposeUiTest(734, 372) {
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
    fun notMyTurnOnlyRearrangesTheRack() = runDesktopComposeUiTest(734, 372) {
        val x = rig(state(turnSeat = 1))
        show(x)
        val before = assertNotNull(x.rummy.editor).copy()
        drag(x.rackPoint("D9"), x.finger(x.screen(300.0, 300.0)))
        assertEquals(before, x.rummy.editor, "남의 차례에 판으로 나갔다")
        val rackRow2 = x.context.rack.frame(RummyRackSlot(1, 12))
        drag(x.rackPoint("D9"), x.finger(RummyCanvasPoint(x.context.layout.rack.x + rackRow2.midX, x.context.layout.rack.y + rackRow2.midY)))
        assertEquals(1, assertNotNull(x.rummy.editor).rackLayout.slot(x.tileID("D9"))?.row, "받침대 안 재배치가 안 됐다")
        x.h.close()
    }

    // MARK: 판 밀기 · 핀치

    @Test
    fun draggingFeltMovesOnlyTheOffset() = runDesktopComposeUiTest(734, 372) {
        val x = rig()
        show(x)
        val editor = assertNotNull(x.rummy.editor).copy()
        val scale = x.model.viewport.scale
        val origin = x.model.viewport.origin
        val start = x.screen(300.0, 300.0)
        drag(start, RummyCanvasPoint(start.x, start.y - 80))
        assertEquals(editor, x.rummy.editor, "판을 밀었는데 편집기가 바뀌었다")
        assertEquals(scale, x.model.viewport.scale, "배율이 저절로 바뀌었다")
        assertEquals(origin.y + 80 / scale, x.model.viewport.origin.y, 0.5, "손을 따라 안 밀렸다")
        x.h.close()
    }

    /** 두 손가락은 핀치만 — 편집기를 안 건드리고 배율만 바뀐다 · 떼면 또렷하게 다시 그린다 · 다음 손은 새로 분류된다. */
    @Test
    fun twoFingersOnlyPinch() = runDesktopComposeUiTest(734, 372) {
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
    fun oneFingerCannotDragDuringAPinch() = runDesktopComposeUiTest(734, 372) {
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
    fun secondFingerDuringADragIsIgnored() = runDesktopComposeUiTest(734, 372) {
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
    fun buttonsAreAboveTheInputLayer() = runDesktopComposeUiTest(734, 372) {
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
    fun undoComesAliveAfterAMove() = runDesktopComposeUiTest(734, 372) {
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
    fun zoomToggleSwitchesFullViewAndBack() = runDesktopComposeUiTest(734, 372) {
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

    /** 화면 밖 묶음 배지: 그쪽 수를 말하고, 누르면 그쪽으로 민다 · 다 보이면 사라진다. 판 변화로 배율이 안 바뀐다. 기본 보기(폭 맞춤)에서는 위아래가 쓰인다. */
    @Test
    fun offscreenBadgeRevealsTheMeld() = runDesktopComposeUiTest(734, 372) {
        val x = rig(state(layout = "[[100,50],[300,560]]"))
        show(x)
        val scale = x.model.viewport.scale
        onNodeWithContentDescription(RummyPhoneText.offscreenDown(1)).assertExists()
        onNodeWithTag(GamesRummyMatchTags.OFFSCREEN_UP).assertDoesNotExist()
        onNodeWithTag(GamesRummyMatchTags.OFFSCREEN_LEFT).assertDoesNotExist()
        onNodeWithTag(GamesRummyMatchTags.OFFSCREEN_RIGHT).assertDoesNotExist()
        onNodeWithTag(GamesRummyMatchTags.OFFSCREEN_DOWN).performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyMatchTags.OFFSCREEN_DOWN).assertDoesNotExist()
        assertEquals(scale, x.model.viewport.scale, "미는데 배율이 바뀌었다")
        // 놓아도 배율은 그대로다(맥 교훈).
        drag(x.rackPoint("D9"), x.finger(x.screen(800.0, 500.0)))
        assertEquals(scale, x.model.viewport.scale, "판 변화로 배율이 저절로 바뀌었다")
        // 위로 가려진 묶음은 위쪽 배지다.
        onNodeWithContentDescription(RummyPhoneText.offscreenUp(1)).assertExists()
        x.h.close()
    }

    // MARK: 안내

    /** 놀던 기기: 안내 카드만 얹고 입력은 안 막는다. 손댄 기기엔 카드가 없다. */
    @Test
    fun otherDeviceCardDoesNotBlockInput() = runDesktopComposeUiTest(734, 372) {
        val x = rig(engaged = false)
        show(x)
        onNodeWithText(RummyPhoneText.otherDevice).assertExists()
        drag(x.rackPoint("D9"), x.finger(x.screen(300.0, 300.0)))
        assertEquals(listOf("D9"), assertNotNull(x.rummy.editor).melds.last().map { it.face.text }, "카드가 입력을 막았다")
        x.h.close()
    }

    @Test
    fun engagedDeviceSeesNoCard() = runDesktopComposeUiTest(734, 372) {
        val x = rig()
        show(x)
        onNodeWithTag(GamesRummyMatchTags.ELSEWHERE).assertDoesNotExist()
        x.h.close()
    }

    @Test
    fun seatsAndStatusSpeakTheStore() = runDesktopComposeUiTest(734, 372) {
        val x = rig(state(turnSeat = 1))
        show(x)
        onNodeWithContentDescription(GamesRummyMatchText.seatSummary("비", 9, true, emptyList())).assertExists()
        onNodeWithTag(GamesRummyMatchTags.STATUS).assertExists()
        // 손댄 기기는 상태 글자가 90초 규칙을 말하고 '누구 차례'는 꼬리가 말한다.
        onNodeWithText(RummyPhoneText.backgroundWarning, useUnmergedTree = true).assertExists()
        assertTrue(onAllNodesWithText(RummyPhoneText.turnOf("비"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        onNodeWithText(RummyPhoneText.pool(50), useUnmergedTree = true).assertExists()
        // 받침대는 면 이름으로 읽힌다.
        onNodeWithContentDescription("주황 9").assertExists()
        x.h.close()
    }

    // MARK: 크기 · 큰 글자

    /** 칸마다 실제 그린 자리가 화면 안이고 서로 안 겹치며, 글자가 칸 안에 든다. */
    private fun DesktopComposeUiTest.assertColumnsFit(width: Double, height: Double) {
        val tags = listOf(
            GamesRummyMatchTags.BACK, GamesRummyMatchTags.RULES, GamesRummyMatchTags.INFO, GamesRummyMatchTags.ZOOM,
            GamesRummyMatchTags.SUBMIT, GamesRummyMatchTags.DRAW, GamesRummyMatchTags.UNDO, GamesRummyMatchTags.SORT_NUMBER, GamesRummyMatchTags.SORT_COLOR,
            GamesRummyMatchTags.MY_SEAT, GamesRummyMatchTags.seat(1),
        )
        val rects = tags.map { onNodeWithTag(it, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot }
        for ((index, rect) in rects.withIndex()) {
            assertTrue(rect.left >= -0.5f && rect.right <= width + 0.5 && rect.top >= -0.5f && rect.bottom <= height + 0.5, "${tags[index]} 화면 밖 $rect")
            assertTrue(rect.height >= 20f, "${tags[index]} 납작하다 $rect")
            for (other in rects.drop(index + 1)) assertFalse(rect.overlaps(other), "${tags[index]} 겹침 $rect $other")
        }
    }

    @Test
    fun smallPhoneKeepsTheColumnsOnScreen() = runDesktopComposeUiTest(667, 354) {
        val x = rig()
        show(x)
        assertColumnsFit(667.0, 354.0)
        x.h.close()
    }

    @Test
    fun lowAndroidPhoneKeepsTheColumnsOnScreen() = runDesktopComposeUiTest(640, 312) {
        val x = rig()
        show(x)
        assertColumnsFit(640.0, 312.0)
        x.h.close()
    }

    /** 큰 글자에서 스크롤 없이 칸 안이다 — 칸은 값이고 글자 배율을 칸마다 자른다. 버튼 글자가 버튼 밖으로 안 넘친다. */
    @Test
    fun bigTextStaysInsideTheCells() = runDesktopComposeUiTest(667, 354) {
        val x = rig()
        show(x, fontScale = 2f)
        assertColumnsFit(667.0, 354.0)
        val button = onNodeWithTag(GamesRummyMatchTags.UNDO).fetchSemanticsNode().boundsInRoot
        val label = onNodeWithText(RummyPhoneText.undo, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue(label.left >= button.left - 0.5f && label.right <= button.right + 0.5f && label.bottom <= button.bottom + 0.5f, "글자가 버튼 밖 $label / $button")
        x.h.close()
    }

    /** 세로 크기로 불린 한 프레임: 칸을 세우지 않고 안내 + [나가기]만 그린다(크래시 · 깨진 칸 없음). 돌아오면 판이 선다. */
    @Test
    fun aPortraitFrameDrawsTheSafePicture() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        var back = 0
        show(x, onBack = { back += 1 })
        onNodeWithTag(GamesRummyMatchTags.ROTATING).assertExists()
        onNodeWithTag(GamesRummyMatchTags.INPUT).assertDoesNotExist()
        onNodeWithTag(GamesRummyMatchTags.BACK).performClick()
        assertEquals(1, back, "돌아가는 동안 [나가기]가 안 닿는다")
        x.h.close()
    }

    /** 끄는 동안 동작 버튼이 잠긴다 — 다른 손가락의 [되돌리기] 가 쥔 묶음 번호를 낡게 만들면 안 된다. */
    @Test
    fun actionsLockWhileATileIsHeld() = runDesktopComposeUiTest(734, 372) {
        val x = rig()
        show(x)
        val a4 = x.tileID("A4")
        drag(x.rackPoint("A4"), x.finger(x.screen(100.0 + 120 - 6, 78.0)))
        assertEquals(4, assertNotNull(x.rummy.editor).melds[0].size)
        val start = x.rackPoint("C1")
        val undo = x.context.layout.undo
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput { down(0, Offset((start.x * density).toFloat(), (start.y * density).toFloat())) }
        waitForIdle()
        assertTrue(x.model.locksActions)
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput {
            down(1, Offset((undo.midX * density).toFloat(), ((undo.y + undo.height / 2) * density).toFloat()))
            up(1)
        }
        waitForIdle()
        assertEquals(4, assertNotNull(x.rummy.editor).melds[0].size, "쥔 동안 [되돌리기]가 먹었다")
        onNodeWithTag(GamesRummyMatchTags.INPUT).performTouchInput { up(0) }
        waitForIdle()
        assertFalse(x.model.locksActions)
        onNodeWithTag(GamesRummyMatchTags.UNDO).performClick()
        waitForIdle()
        assertEquals(3, assertNotNull(x.rummy.editor).melds[0].size, "손을 뗐는데 [되돌리기]가 죽었다")
        assertTrue(assertNotNull(x.rummy.editor).rack.any { it.id == a4 })
        x.h.close()
    }

    // MARK: 100장

    /** 판 타일 100장 — 그리는 데 터지지 않고, 밀어도 판 층 배율이 그대로다(층만 옮긴다). */
    @Test
    fun aHundredTilesPanWithoutRedrawInputs() = runDesktopComposeUiTest(734, 372) {
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
        val start = x.screen(500.0, 420.0)
        drag(start, RummyCanvasPoint(start.x, start.y - 100))
        assertTrue(x.model.viewport.origin.y > 0)
        assertEquals(render, x.model.renderScale, "밀었는데 판 층을 다시 그린다")
        x.h.close()
    }

    /** 받침대가 3줄이어도 칸은 그대로다(타일이 2/줄로 준다) — 판 칸이 안 흔들린다. */
    @Test
    fun threeRowRackKeepsTheBoardSize() = runDesktopComposeUiTest(734, 372) {
        val rack = ((1..13).map { "\"A$it\"" } + (1..13).map { "\"B$it\"" } + (1..8).map { "\"C$it\"" }).joinToString(",", "[", "]")
        val x = rig(state(rack = rack))
        show(x)
        assertEquals(3, x.context.layout.rackRows, "34장인데 3줄이 아니다")
        val two = GamesRummyMatchLayout(RummyCanvasSize(734.0, 372.0), 2)
        assertEquals(two.table, x.context.layout.table, "줄이 늘었다고 판이 줄었다")
        assertEquals(two.rack, x.context.layout.rack)
        assertEquals(RummyCanvasSize(two.table.width, two.table.height), x.model.viewport.viewport, "보기가 칸 크기를 안 따른다")
        x.h.close()
    }
}
