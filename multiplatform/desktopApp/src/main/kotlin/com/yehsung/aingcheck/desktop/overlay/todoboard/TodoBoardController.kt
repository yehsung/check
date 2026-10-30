// 원본: Sources/check/CheckTodoBoardWindow.swift:206-237(TodoBoardUIState) · :258-307(루트 뷰의 목록 나누기) ·
//       :310-560(컨트롤러·열기/토글) · :660-668(close) · :764-928(재배치·입력 상태·삭제 되돌리기·계정 전환·하루 키) ·
//       Sources/check/CheckApp.swift:611-661(TodoBoardWiring.connect·faceTheBoard) · :692-720(TodoDisableWatcher) ·
//       Sources/check/TodoSyncCoordinator.swift:48(syncProtectedIDs 배선) @ ef9fab11
package com.yehsung.aingcheck.desktop.overlay.todoboard

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.stores.now.todo.TodoListStore
import com.yehsung.aingcheck.desktop.overlay.engine.BoardHost
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect

/**
 * 보드 창 표면(Windows 는 [TodoBoardWindow], 시험은 가짜). 컨트롤러는 창을 모르고 이 문으로만 부른다.
 * 창은 **처음 [show] 할 때 만든다** — 근무 내내 안 열 수도 있는 창이라 앱 시작 때 만들지 않는다(맥 지연 생성).
 */
interface TodoBoardSurface {
    /** 창이 만들어졌나(맥 hasPanel). 닫힌 보드의 위치를 묻다가 창을 만들어 버리지 않게 따로 연다. */
    val hasWindow: Boolean

    /** [frame] 에 띄우고 앞으로 가져온다(멱등). Windows 는 활성화되는 창이다(D §9-5 — NOACTIVATE 창에서는 글자를 못 친다). */
    fun show(frame: OverlayRect)

    /** 위치만 옮긴다. **보이기·초점은 건드리지 않는다**(맥 repositionNeverShowsOrFocusesThePanel). */
    fun move(frame: OverlayRect)

    /** 숨긴다. **파괴하지 않는다** — 다시 만들면 한 프레임 빈 창이 스치고 초점이 튄다(맥 주석). */
    fun hide()
}

/** 한 번 울리는 타이머(되돌리기 5초). 시험은 손으로 미는 가짜, 앱은 [SwingBoardTimer](UI 스레드에서 울린다). */
fun interface BoardTimer {
    fun after(seconds: Double, action: () -> Unit): BoardTimerHandle
}

fun interface BoardTimerHandle {
    fun cancel()
}

/** EDT(= Compose 데스크톱 UI 스레드)에서 울리는 타이머. 화면이 없어도 돈다(javax.swing.Timer 는 헤드리스 무관). */
object SwingBoardTimer : BoardTimer {
    override fun after(seconds: Double, action: () -> Unit): BoardTimerHandle {
        val t = javax.swing.Timer((seconds * 1000).toInt().coerceAtLeast(0)) { action() }
        t.isRepeats = false
        t.start()
        return BoardTimerHandle { t.stop() }
    }
}

/** 보드 입력 상태(맥 TodoBoardUIState) — 컨트롤러가 소유. 창을 숨겨도, 뷰가 다시 만들어져도 남는다. */
class TodoBoardUiState(todayKey: String) {
    /** 입력칸 초안. */
    var draft: String by mutableStateOf("")
        internal set
    /** 인라인 수정 중인 항목. null 이면 수정 중 아님. */
    var editingID: String? by mutableStateOf(null)
        internal set
    /** '삭제됨 [되돌리기]' 로 자리를 지키는 항목(아직 store 에서 안 지웠다). */
    var pendingDeleteID: String? by mutableStateOf(null)
        internal set
    /** 하단 '오래된 항목 (N)' 펼침. */
    var isOldSectionExpanded: Boolean by mutableStateOf(false)
        internal set
    /** 보드가 기준으로 삼는 KST 하루 키(열 때·손댈 때 갱신 — 자정 넘김 반영). */
    var todayKey: String by mutableStateOf(todayKey)
        internal set
}

/** 보드에 그릴 두 무리(맥 루트 뷰): 오늘 목록과 '오래된 항목'. */
data class TodoBoardSections(val active: List<TodoItem>, val old: List<TodoItem>) {
    val isEntirelyEmpty: Boolean get() = active.isEmpty() && old.isEmpty()

    companion object {
        fun of(items: List<TodoItem>, todayKey: String): TodoBoardSections {
            val active = ArrayList<TodoItem>()
            val old = ArrayList<TodoItem>()
            for (item in TodoRules.visible(items, todayKey)) {
                if (TodoRules.isOld(item, todayKey)) old += item else active += item
            }
            return TodoBoardSections(active, old)
        }
    }
}

/**
 * 할 일 보드 컨트롤러(맥 CheckTodoBoardController + TodoBoardWiring 의 보드 쪽) — overlay 계약 I-6 [BoardHost] 구현.
 *
 * - 엔진(b1)은 캐릭터 클릭에 [toggle], 드래그 중·끝에 [reposition] 을 부르고, 열려 있으면 졸지 않는다.
 * - 열림 의도 [isBoardOpen] 이 헤드리스 검증 지점이다(실제 창 표시 여부는 OS 가 흔든다).
 * - [store] 의 `syncProtectedIDs` 를 이 보드가 댄다(맥 TodoSyncCoordinator:48 — 편집 중·되돌리기 창의 줄은 서버 병합을 미룬다).
 */
class TodoBoardController(
    private val store: TodoListStore,
    private val surface: TodoBoardSurface,
    private val timer: BoardTimer = SwingBoardTimer,
    /** 설정의 할 일 켜짐(맥 isTodoEnabled). 꺼져 있으면 엔진은 클릭을 때리기로 돌린다. */
    private val enabled: () -> Boolean = { true },
    /** 되돌리기 유예(초). 앱은 언제나 [TodoRules.undoSeconds](5). 시험만 짧게 준다. */
    val undoSeconds: Double = TodoRules.undoSeconds,
) : BoardHost {
    val ui = TodoBoardUiState(store.todayKey)

    /** 표시 의도. */
    var isBoardOpen: Boolean by mutableStateOf(false)
        private set

    /** 마지막으로 놓은 보드 자리(DIP). 닫혀도 남는다(창이 남듯이). */
    var boardFrame: OverlayRect? = null
        private set
    private var anchorFrame: OverlayRect? = null

    /** 실제로 창을 옮긴 횟수(헤드리스 검증 지점 — 같은 자리 재통지는 세지 않는다). */
    var repositionAppliedCount: Int = 0
        private set

    /** 닫혀 있다가 **열린 순간에만** 부른다(v0.3.30: 보드를 열 때 서버와 맞춘다). */
    var onOpened: (() -> Unit)? = null

    private var undoHandle: BoardTimerHandle? = null

    init {
        store.syncProtectedIDs = { syncProtectedIDs }
    }

    // ───────────────────────── BoardHost(I-6) ─────────────────────────

    override fun isEnabled(): Boolean = enabled()

    override fun isOpen(): Boolean = isBoardOpen

    /** 캐릭터 클릭 진입점. 열려 있으면 닫고, 닫혀 있으면 그 자리에 연다. */
    override fun toggle(anchor: OverlayRect, work: OverlayRect) {
        if (isBoardOpen) close() else open(anchor, work)
    }

    /** 앵커 옆에 띄운다(멱등 — 이미 열려 있으면 자리만 다시 잡는다). */
    fun open(anchor: OverlayRect, work: OverlayRect) {
        syncTodayKey()
        val wasOpen = isBoardOpen
        val frame = TodoBoardAnchor.frame(anchor, work)
        anchorFrame = anchor
        boardFrame = frame
        surface.show(frame)
        isBoardOpen = true
        if (!wasOpen) onOpened?.invoke()
    }

    /** 캐릭터가 움직였다. 닫혀 있으면 아무것도 안 한다(창도 안 만든다). 같은 자리면 창을 건드리지 않는다. */
    override fun reposition(anchor: OverlayRect, work: OverlayRect) {
        if (!isBoardOpen || !surface.hasWindow) return
        anchorFrame = anchor
        val target = TodoBoardAnchor.frame(anchor, work)
        if (target == boardFrame) return
        repositionAppliedCount += 1
        boardFrame = target
        surface.move(target)
    }

    /** 닫는다 — 되돌리기 대기 중인 삭제는 **지금 확정**한다(맥 todoBoardCloseConfirmsPendingDeleteImmediately). */
    override fun close() {
        commitPendingDelete()
        if (surface.hasWindow) surface.hide()
        isBoardOpen = false
    }

    /** 열린 보드 쪽(−1·1), 닫혔으면 0(맥 faceTheBoard). */
    override fun facing(): Int {
        val board = boardFrame
        val anchor = anchorFrame
        if (!isBoardOpen || board == null || anchor == null) return 0
        return TodoBoardAnchor.facing(board, anchor)
    }

    /** 할 일 스위치가 바뀌었다(맥 TodoDisableWatcher) — 끄는 순간 열린 보드를 놓아준다(안 하면 클릭이 때리기로 가 보드가 갇힌다). */
    fun enabledDidChange() {
        if (!enabled() && isBoardOpen) close()
    }

    /** 보드 창이 다른 앱에 활성을 넘겼다(D §9-5 '바깥을 누르면 닫힌다'). 창 표면이 부른다. */
    fun onDeactivated() {
        if (isBoardOpen) close()
    }

    // ───────────────────────── 보여 줄 값 ─────────────────────────

    /** 지금 그릴 두 무리(Compose 상태를 읽으므로 뷰 안에서 부르면 바뀔 때 다시 그린다). */
    fun sections(): TodoBoardSections = TodoBoardSections.of(store.items, ui.todayKey)

    // ───────────────────────── 입력 상태 ─────────────────────────

    /**
     * 초안을 바꾼다. **100자를 넘기는 입력은 통째로 거부한다** — 자르지 않는다(맥 setDraft).
     * 짧아지는 방향(글자 수 감소 · 코드 포인트 불증가)은 언제나 허용 — 어떤 경로로 넘겨 들어왔어도 지워서 빠져나온다.
     */
    fun setDraft(text: String) {
        val current = ui.draft
        val shrinking = TodoDraftInput.graphemes(text) < TodoDraftInput.graphemes(current) &&
            TodoDraftInput.codePoints(text) <= TodoDraftInput.codePoints(current)
        if (!TodoRules.titleFitsLimits(text) && !shrinking) return
        if (ui.draft != text) ui.draft = text
    }

    /** 입력칸 Enter. 성공했을 때만 초안을 비운다(공백만 친 입력을 store 가 거절하면 친 것이 남는다). */
    fun submitDraft() {
        syncTodayKey()
        if (store.add(ui.draft) == null) return
        setDraft("")
    }

    fun toggleDone(id: String) {
        syncTodayKey()
        store.toggleDone(id)
    }

    fun beginEdit(id: String) {
        if (ui.editingID != id) ui.editingID = id
        // 다른 줄을 고치다 넘어왔다면 그 줄의 보호는 여기서 끝난다.
        store.syncProtectionDidEnd()
    }

    /** 인라인 수정 Enter. 저장 여부는 store 규칙에 맡기고, 수정 모드는 어느 쪽이든 닫는다. */
    fun commitEdit(id: String, rawTitle: String) {
        syncTodayKey()
        store.rename(id, rawTitle)
        cancelEdit()
    }

    /** 수정 모드 종료(Esc·커밋 후 공용). 원래 제목은 store 가 들고 있어 되돌릴 것이 없다. */
    fun cancelEdit() {
        if (ui.editingID != null) ui.editingID = null
        store.syncProtectionDidEnd()
    }

    fun toggleOldSection() {
        ui.isOldSectionExpanded = !ui.isOldSectionExpanded
    }

    // ───────────────────────── 삭제 · 되돌리기(5초) ─────────────────────────

    /**
     * 삭제 요청. **store 를 아직 건드리지 않는다** — 지우면 목록에서 빠져 '삭제됨 [되돌리기]' 행이 설 자리가 없다.
     * 다른 항목이 대기 중이면 그것을 먼저 확정한다(타이머는 하나, 되돌리기 줄도 하나).
     */
    fun requestDelete(id: String) {
        val pending = ui.pendingDeleteID
        if (pending != null && pending != id) commitPendingDelete()
        syncTodayKey()
        if (ui.pendingDeleteID != id) ui.pendingDeleteID = id
        undoHandle?.cancel()
        undoHandle = timer.after(undoSeconds) {
            undoHandle = null
            commitPendingDelete()
        }
    }

    /**
     * 되돌리기. 유예 중이면 타이머만 끄면 원상복구. 대기 중이 아니면 **방금 확정된 직후의 늦은 클릭**이라
     * store 에 되살리기를 부탁한다(조용히 물러나면 "눌렀는데 안 돌아왔다"가 된다).
     */
    fun undoDelete(id: String) {
        if (ui.pendingDeleteID == id) {
            undoHandle?.cancel()
            undoHandle = null
            ui.pendingDeleteID = null
            store.syncProtectionDidEnd()
            return
        }
        store.undoDelete(id)
    }

    /** 대기 중인 삭제를 지금 확정(멱등). 타이머 만료·보드 닫기·다른 항목 삭제가 모두 여기로 모인다. */
    fun commitPendingDelete() {
        undoHandle?.cancel()
        undoHandle = null
        val id = ui.pendingDeleteID ?: return
        ui.pendingDeleteID = null
        store.delete(id)
        store.syncProtectionDidEnd()
    }

    // ───────────────────────── 서버 동기화 · 계정 ─────────────────────────

    /** 지금 서버 병합을 미뤄야 하는 줄: 편집 중인 줄과 '삭제됨 [되돌리기]' 줄. */
    val syncProtectedIDs: Set<String>
        get() = buildSet {
            ui.editingID?.let(::add)
            ui.pendingDeleteID?.let(::add)
        }

    /**
     * 계정이 바뀌었다. 되돌리기 창의 삭제는 **지금 파일(앞 계정)에** 확정하고, 편집·초안은 버린다
     * (다음 사람이 앞 사람이 적다 만 글을 보면 안 된다). 보드 자체는 닫지 않는다.
     */
    fun resetForAccountSwitch() {
        commitPendingDelete()
        if (ui.editingID != null) ui.editingID = null
        if (ui.draft.isNotEmpty()) ui.draft = ""
    }

    /** store 의 하루 키로 맞춘다(같으면 대입하지 않는다 — 같은 값 재대입도 다시 그리게 한다). */
    private fun syncTodayKey() {
        val key = store.todayKey
        if (ui.todayKey != key) ui.todayKey = key
    }
}
