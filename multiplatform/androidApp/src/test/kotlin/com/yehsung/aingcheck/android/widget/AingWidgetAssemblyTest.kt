// 원본: 없음 — 7차 조립(K11) 위젯 배선 시험. 앱이 쓴 W2-f 스냅숏 파일을 위젯 얼굴이 읽는지(필드 1:1 옮기기 · 로그아웃 = 파일 없음)와
// 순위 '나' 행의 스냅숏 표정(Swift RankingsTab.myCharacterMood 의 둘째 갈래)을 잰다.
package com.yehsung.aingcheck.android.widget

import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshot
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshotCodec
import com.yehsung.aingcheck.ui.components.CharacterMood
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36])
class AingWidgetAssemblyTest {
    private val app get() = ApplicationProvider.getApplicationContext<AingApplication>()
    private val generated = SwiftDate(1_789_621_200.0)

    private fun snapshot(status: WidgetSnapshot.WorkState?, working: Boolean = true) = WidgetSnapshot(
        generatedAt = generated,
        me = WidgetSnapshot.Me(working, SwiftDate(generated.timeIntervalSince1970 - 3_600), 3_600, 36_000, 40, status),
        working = listOf(WidgetSnapshot.WorkingPerson("민트", "busan", true, SwiftDate(generated.timeIntervalSince1970 - 600), "cat")),
        todosPreview = listOf(WidgetSnapshot.TodoPreview("a0000000-0000-4000-8000-000000000001", "리뷰", false, 2)),
        characterID = "fox",
    )

    @After
    fun reset() {
        AingWidgetRuntime.faces = AingWidgetFaces.SignedOut
        AingWidgetRuntime.toggleTodo = null
        app.container.widgetFile.remove()
    }

    @Test
    fun snapshotMovesFieldForField() {
        val s = snapshot(WidgetSnapshot.WorkState.disconnected)
        val input = s.toAingWidgetInput()
        assertEquals(generated, input.generatedAt)
        assertEquals(AingWidgetInput.WorkState.disconnected, input.me?.status)
        assertEquals(AingWidgetInput.Me(true, s.me!!.sessionStartedAt, 3_600, 36_000, 40, AingWidgetInput.WorkState.disconnected), input.me)
        assertEquals(listOf(AingWidgetInput.Person("민트", "busan", true, s.working[0].startedAt, "cat")), input.working)
        assertEquals(listOf(AingWidgetInput.Todo("a0000000-0000-4000-8000-000000000001", "리뷰", false, 2)), input.todosPreview)
        assertEquals("fox", input.characterID)
        assertNull(snapshot(null).toAingWidgetInput().me?.status)
    }

    @Test
    fun installedFacesReadTheAppSnapshotFileAndFoldToSignedOutWithoutIt() {
        val c = app.container
        c.widgetFile.writeAtomically(WidgetSnapshotCodec.encode(snapshot(WidgetSnapshot.WorkState.disconnected)))
        c.installWidgetRuntime()
        assertNotNull("체크가 배선되지 않았다", AingWidgetRuntime.toggleTodo)
        val nowMillis = ((generated.timeIntervalSince1970 + 120) * 1000).toLong()
        val today = AingWidgetRuntime.faces.myToday(nowMillis)
        assertTrue("스냅숏이 있는데 로그아웃 얼굴: $today", today is MyTodayFace.Me)
        today as MyTodayFace.Me
        assertEquals("fox", today.characterId)
        assertEquals(WidgetTone.Lost, today.tone)
        val todos = AingWidgetRuntime.faces.todos(nowMillis)
        assertTrue("$todos", todos is TodosFace.Rows && todos.rows.map { it.title } == listOf("리뷰"))

        c.widgetFile.remove()
        assertEquals(MyTodayFace.SignedOut, AingWidgetRuntime.faces.myToday(nowMillis))
        assertTrue(AingWidgetRuntime.faces.todos(nowMillis) is TodosFace.SignedOut)
    }

    @Test
    fun rankingsMoodReadsTheSnapshotState() {
        assertEquals(CharacterMood.Working, snapshot(WidgetSnapshot.WorkState.working).rankingsMood())
        assertEquals(CharacterMood.Lost, snapshot(WidgetSnapshot.WorkState.disconnected).rankingsMood())
        assertEquals(CharacterMood.Off, snapshot(null, working = false).rankingsMood())
        // 옛 스냅숏(상태 없음 · working 깃발만) → 근무 중
        assertEquals(CharacterMood.Working, snapshot(null).rankingsMood())
        assertNull(snapshot(null).copy(me = null).rankingsMood())
    }
}
