// 원본: Tests/checkTests/CheckTodoBoardWindowTests.swift:242-465(열기·닫기·재배치·삭제 되돌리기·초안) · :604-683(재배치 계약) ·
//       Tests/checkTests/TodoBoardIntegrationTests.swift(스토어 왕복) @ ef9fab11
// 픽스처는 합성만: 메모리 파일 시스템 · 손으로 미는 시계와 타이머 · 가짜 창 표면.
package com.yehsung.aingcheck.desktop.overlay.todoboard

import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileSystem
import com.yehsung.aingcheck.core.stores.now.todo.TodoListStore
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.swing.SwingUtilities
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class MemoryTodoFiles : TodoFileSystem {
    val files = HashMap<String, ByteArray>()
    override fun read(path: String): ByteArray? = files[path]
    override fun writeAtomically(path: String, bytes: ByteArray) { files[path] = bytes }
    override fun move(from: String, to: String) { files.remove(from)?.let { files[to] = it } }
}

/** 창 대신 호출만 적는다. */
internal class FakeBoardSurface : TodoBoardSurface {
    val calls = ArrayList<String>()
    var frame: OverlayRect? = null
    var visible = false
    override var hasWindow: Boolean = false
    override fun show(frame: OverlayRect) { hasWindow = true; this.frame = frame; visible = true; calls += "show" }
    override fun move(frame: OverlayRect) { this.frame = frame; calls += "move" }
    override fun hide() { visible = false; calls += "hide" }
}

/** 손으로 미는 타이머. */
internal class ManualTimer : BoardTimer {
    private class Entry(val due: Double, val action: () -> Unit) { var cancelled = false }
    private val entries = ArrayList<Entry>()
    var now = 0.0
    val pending: Int get() = entries.count { !it.cancelled }
    override fun after(seconds: Double, action: () -> Unit): BoardTimerHandle {
        val e = Entry(now + seconds, action)
        entries += e
        return BoardTimerHandle { e.cancelled = true }
    }
    fun advance(seconds: Double) {
        now += seconds
        val due = entries.filter { !it.cancelled && it.due <= now }
        entries.removeAll(due.toSet())
        due.forEach { it.action() }
    }
}

internal class BoardFixture(undoSeconds: Double = TodoRules.undoSeconds, val timer: BoardTimer = ManualTimer()) {
    var clock = 1_790_000_000.0 // 합성 시각(2026-09)
    private var n = 0
    val files = MemoryTodoFiles()
    val store = TodoListStore("/synthetic/todos.json", files, { clock }, { "00000000-0000-4000-8000-" + (++n).toString().padStart(12, '0') })
    val surface = FakeBoardSurface()
    var enabled = true
    val controller = TodoBoardController(store, surface, timer, { enabled }, undoSeconds)
    val manual: ManualTimer get() = timer as ManualTimer

    fun add(title: String): String = requireNotNull(store.add(title)).id
}

class TodoBoardControllerTest {
    private val work = OverlayRect(0.0, 0.0, 1440.0, 900.0)
    private val anchor = OverlayRect(1200.0, 130.0, 140.0, 170.0)

    @Test
    fun openCloseAreIdempotentAndTrackIsBoardOpen() {
        val f = BoardFixture()
        var opened = 0
        f.controller.onOpened = { opened += 1 }
        assertFalse(f.controller.isOpen())
        f.controller.toggle(anchor, work)
        assertTrue(f.controller.isOpen())
        assertEquals(TodoBoardAnchor.frame(anchor, work), f.surface.frame)
        f.controller.open(anchor, work) // 멱등 — 열림 통지는 한 번
        assertEquals(1, opened)
        f.controller.toggle(anchor, work)
        assertFalse(f.controller.isOpen())
        assertFalse(f.surface.visible)
        f.controller.close()
        f.controller.close()
        assertFalse(f.controller.isOpen())
        f.controller.toggle(anchor, work)
        assertEquals(2, opened, "닫혔다가 열린 순간에만 알린다")
    }

    @Test
    fun keepsWindowAndDraftAcrossClose() {
        val f = BoardFixture()
        f.controller.open(anchor, work)
        f.controller.setDraft("우유 사기")
        f.controller.close()
        assertTrue(f.surface.hasWindow, "닫을 때 창을 파괴하지 않는다")
        assertEquals("우유 사기", f.controller.ui.draft)
        f.controller.open(anchor, work)
        assertEquals("우유 사기", f.controller.ui.draft)
    }

    @Test
    fun repositionIsNoOpWhileClosedAndNeverCreatesTheWindow() {
        val f = BoardFixture()
        f.controller.reposition(anchor, work)
        assertFalse(f.surface.hasWindow)
        assertTrue(f.surface.calls.isEmpty())
        f.controller.open(anchor, work)
        f.controller.close()
        f.surface.calls.clear()
        f.controller.reposition(anchor.withOrigin(10.0, 10.0), work)
        assertTrue(f.surface.calls.isEmpty(), "닫힌 보드는 옮기지 않는다")
    }

    @Test
    fun repositionNeverShowsOrFocusesAndSkipsRedundantMoves() {
        val f = BoardFixture()
        f.controller.open(anchor, work)
        f.surface.calls.clear()
        f.controller.reposition(anchor, work) // 같은 자리
        assertEquals(0, f.controller.repositionAppliedCount)
        f.controller.reposition(anchor.withOrigin(1100.0, 200.0), work)
        f.controller.reposition(anchor.withOrigin(1100.0, 200.0), work)
        assertEquals(1, f.controller.repositionAppliedCount)
        assertEquals(listOf("move"), f.surface.calls, "재배치는 move 만 — show(초점)를 부르지 않는다")
        assertEquals(TodoBoardAnchor.frame(anchor.withOrigin(1100.0, 200.0), work), f.surface.frame)
    }

    @Test
    fun boardActuallyFlipsWhenDraggedToTheEdgeAndFacingFollows() {
        val f = BoardFixture()
        f.controller.open(anchor, work)
        assertEquals(-1, f.controller.facing(), "보드가 왼쪽 — 왼쪽을 본다")
        f.controller.reposition(OverlayRect(20.0, 130.0, 140.0, 170.0), work)
        assertEquals(170.0, f.surface.frame!!.left)
        assertEquals(1, f.controller.facing(), "오른쪽으로 뒤집히면 오른쪽을 본다")
        f.controller.close()
        assertEquals(0, f.controller.facing(), "닫히면 정면")
    }

    @Test
    fun deleteKeepsRowUntilUndoWindowClosesAndUndoRestoresIt() {
        val f = BoardFixture()
        val id = f.add("빨래")
        f.controller.requestDelete(id)
        assertEquals(id, f.controller.ui.pendingDeleteID)
        assertNull(f.store.items.single().deletedAt, "유예 중엔 store 를 건드리지 않는다")
        assertEquals(listOf(id), f.controller.sections().active.map { it.id })
        f.controller.undoDelete(id)
        assertNull(f.controller.ui.pendingDeleteID)
        assertEquals(0, f.manual.pending, "되돌리면 타이머도 끈다")
        f.manual.advance(10.0)
        assertNull(f.store.items.single().deletedAt)
    }

    @Test
    fun undoTimerConfirmsDeleteWithNoOnePushingIt() {
        val f = BoardFixture()
        val id = f.add("빨래")
        f.controller.requestDelete(id)
        f.manual.advance(TodoRules.undoSeconds - 0.1)
        assertNull(f.store.items.single().deletedAt)
        f.manual.advance(0.2)
        assertNotNull(f.store.items.single().deletedAt, "5초가 지나면 확정")
        assertNull(f.controller.ui.pendingDeleteID)
        assertTrue(f.controller.sections().active.isEmpty())
    }

    @Test
    fun realSwingTimerWakesByItselfAndConfirmsTheDelete() {
        // 주입 지점이 없으면 '타이머가 스스로 깨어나 확정하는가'를 못 본다(맥 undoSeconds 주석) — 실제 EDT 타이머를 짧게.
        val f = BoardFixture(undoSeconds = 0.05, timer = SwingBoardTimer)
        lateinit var id: String
        SwingUtilities.invokeAndWait {
            id = f.add("빨래")
            f.controller.requestDelete(id)
        }
        val done = CountDownLatch(1)
        val deadline = System.nanoTime() + 3_000_000_000L
        while (System.nanoTime() < deadline) {
            var deleted = false
            SwingUtilities.invokeAndWait { deleted = f.store.items.single().deletedAt != null }
            if (deleted) { done.countDown(); break }
            Thread.sleep(20)
        }
        assertTrue(done.await(0, TimeUnit.MILLISECONDS), "실제 타이머가 3초 안에 삭제를 확정하지 않았다")
    }

    @Test
    fun closeConfirmsPendingDeleteImmediately() {
        val f = BoardFixture()
        val id = f.add("빨래")
        f.controller.open(anchor, work)
        f.controller.requestDelete(id)
        f.controller.close()
        assertNotNull(f.store.items.single().deletedAt)
        assertNull(f.controller.ui.pendingDeleteID)
        assertEquals(0, f.manual.pending)
    }

    @Test
    fun secondDeleteConfirmsTheFirstPendingOne() {
        val f = BoardFixture()
        val a = f.add("하나")
        val b = f.add("둘")
        f.controller.requestDelete(a)
        f.controller.requestDelete(b)
        assertNotNull(f.store.items.first { it.id == a }.deletedAt)
        assertNull(f.store.items.first { it.id == b }.deletedAt)
        assertEquals(b, f.controller.ui.pendingDeleteID)
        assertEquals(1, f.manual.pending, "타이머는 하나")
    }

    @Test
    fun lateUndoAfterTheTimerFiredAsksTheStoreToRestore() {
        val f = BoardFixture()
        val id = f.add("빨래")
        f.controller.requestDelete(id)
        f.manual.advance(TodoRules.undoSeconds + 1)
        assertNotNull(f.store.items.single().deletedAt)
        f.controller.undoDelete(id)
        assertNull(f.store.items.single().deletedAt, "늦은 되돌리기도 되살린다")
    }

    @Test
    fun blocksOverlongDraftInsteadOfTruncating() {
        val f = BoardFixture()
        val full = "가".repeat(TodoRules.maxTitleLength)
        f.controller.setDraft(full)
        f.controller.setDraft(full + "나")
        assertEquals(full, f.controller.ui.draft)
        f.controller.setDraft(full.dropLast(1))
        assertEquals(full.dropLast(1), f.controller.ui.draft, "줄이는 방향은 언제나 허용")
    }

    @Test
    fun addCompleteEditCancelRoundTripThroughTheStore() {
        val f = BoardFixture()
        f.controller.open(anchor, work)
        f.controller.setDraft("   ")
        f.controller.submitDraft()
        assertTrue(f.store.items.isEmpty())
        assertEquals("   ", f.controller.ui.draft, "store 가 거절하면 친 것이 남는다")
        f.controller.setDraft("우유 사기")
        f.controller.submitDraft()
        val id = f.store.items.single().id
        assertEquals("우유 사기", f.store.items.single().title)
        assertEquals("", f.controller.ui.draft)

        f.controller.toggleDone(id)
        assertTrue(f.store.items.single().isDone)
        f.controller.toggleDone(id)
        assertFalse(f.store.items.single().isDone)

        f.controller.beginEdit(id)
        assertEquals(setOf(id), f.controller.syncProtectedIDs)
        assertEquals(setOf(id), f.store.syncProtectedIDs(), "보드가 store 의 병합 보호를 댄다")
        f.controller.cancelEdit()
        assertNull(f.controller.ui.editingID)
        assertEquals("우유 사기", f.store.items.single().title)

        f.controller.beginEdit(id)
        f.controller.commitEdit(id, "두부 사기")
        assertEquals("두부 사기", f.store.items.single().title)
        assertNull(f.controller.ui.editingID, "커밋 뒤 수정 모드는 닫힌다")
        f.controller.beginEdit(id)
        f.controller.commitEdit(id, "  ")
        assertEquals("두부 사기", f.store.items.single().title, "빈 제목은 store 가 거절")
        assertNull(f.controller.ui.editingID, "거절돼도 수정 모드는 닫힌다")
        assertTrue(f.files.files.isNotEmpty(), "변경은 파일로 간다")
    }

    @Test
    fun accountSwitchConfirmsPendingDeleteAndDropsDraftAndEdit() {
        val f = BoardFixture()
        val id = f.add("빨래")
        val other = f.add("설거지")
        f.controller.setDraft("앞 사람 초안")
        f.controller.beginEdit(other)
        f.controller.requestDelete(id)
        f.controller.resetForAccountSwitch()
        assertNotNull(f.store.items.first { it.id == id }.deletedAt)
        assertEquals("", f.controller.ui.draft)
        assertNull(f.controller.ui.editingID)
    }

    @Test
    fun disablingTodoClosesTheOpenBoard() {
        val f = BoardFixture()
        f.controller.open(anchor, work)
        f.enabled = false
        assertFalse(f.controller.isEnabled())
        f.controller.enabledDidChange()
        assertFalse(f.controller.isOpen())
    }

    @Test
    fun deactivationClosesTheBoard() {
        val f = BoardFixture()
        f.controller.open(anchor, work)
        f.controller.onDeactivated()
        assertFalse(f.controller.isOpen())
        assertFalse(f.surface.visible)
    }

    @Test
    fun oldSectionToggleAndSplit() {
        val f = BoardFixture()
        val oldId = f.add("오래된 일")
        f.clock += 8 * 86_400.0 // 7일 넘게 이월
        val newId = f.add("새 일")
        f.controller.open(anchor, work) // 하루 키 갱신
        val s = f.controller.sections()
        assertEquals(listOf(newId), s.active.map { it.id })
        assertEquals(listOf(oldId), s.old.map { it.id })
        assertFalse(f.controller.ui.isOldSectionExpanded)
        f.controller.toggleOldSection()
        assertTrue(f.controller.ui.isOldSectionExpanded)
    }
}
