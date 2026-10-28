// 원본: Sources/CheckCore/CheckTodoModel.swift:505-743(TodoListStore) · Sources/CheckCore/TodoSync.swift:236-242(TodoSyncOutgoing) @ 1b8260d
package com.yehsung.aingcheck.core.stores.now.todo

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.rules.todo.TodoFile
import com.yehsung.aingcheck.core.rules.todo.TodoFileSyncState
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRequest
import com.yehsung.aingcheck.core.rules.todo.TodoSyncResult
import com.yehsung.aingcheck.core.rules.todo.TodoSyncWireItem
import kotlinx.coroutines.CancellationException
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** 보낸 요청 한 건의 스냅샷(Swift `TodoSyncOutgoing`). 응답을 합칠 때 같이 넘긴다. */
data class TodoSyncOutgoing(
    /** 찍을 때의 [TodoListStore.fileGeneration](계정 전환 뒤 늦은 응답을 버리는 기준). */
    val fileGeneration: Int,
    val request: TodoSyncRequest,
    /** id → 보낸 updatedAtMs. */
    val sent: Map<String, Long>,
)

/**
 * 할 일 목록의 이 기기 사본의 유일한 소유자(Swift `TodoListStore`). 메모리가 곧 진실이고 디스크는 그 사본이다 — 이 방향을 고정했기 때문에
 * 저장 실패를 조용히 삼켜도 안전하다(다음 변경에서 파일 전체가 다시 쓰인다).
 *
 * 서버와 맞추는 일은 [TodoSync] 가 한다. 스토어는 **두 문만** 연다:
 * ① [makeSyncRequest] — 보낼 항목의 스냅샷(보낸 updatedAtMs 와 파일 세대까지 같이 찍는다)
 * ② [applySync] — 응답 병합. 찍을 때의 파일 세대가 **지금과 다르면 아무것도 하지 않는다**(세대 가드는 여기 하나다).
 *
 * id 는 소문자 uuid 글자, 시각은 1970 기준 초(정수 ms 격자 — INV-CheckTodoModel-f1b4dd4f, W1-c 규칙).
 */
@OptIn(ExperimentalUuidApi::class)
class TodoListStore(
    filePath: String,
    private val files: TodoFileSystem,
    /** 지금(1970 기준 초). */
    private val clock: () -> Double,
    private val newID: () -> String = { Uuid.random().toString().lowercase() },
) {
    var items: List<TodoItem> by mutableStateOf(emptyList())
        private set

    /** 아직 서버에 확정되지 않은 항목 id(파일의 `sync.pendingIDs`). */
    var pendingIDs: Set<String> by mutableStateOf(emptySet())
        private set

    /** 서버가 거절해 붙잡아 둔 항목 id(부록 B-3). 언제나 [items] 의 id 이고 [pendingIDs] 와 겹치지 않는다. */
    var heldRejectedIDs: Set<String> by mutableStateOf(emptySet())
        private set

    /** 마지막으로 맞춘 서버 시각(epoch ms). null = 다음 요청은 전체를 받는다. */
    var watermarkMs: Long? by mutableStateOf(null)
        private set

    /** 지금 쓰는 파일. **계정이 바뀌면 바뀐다**([switchFile]). */
    var filePath: String by mutableStateOf(filePath)
        private set

    /** 파일을 바꿀 때마다 오른다. 동기화 응답이 "찍을 때의 세대"를 들고 와 이 값과 견준다. */
    var fileGeneration: Int = 0
        private set

    /** 사용자가 목록을 고쳤다(추가·완료·수정·삭제·되돌리기). 동기화가 1.5초 디바운스를 건다. 병합·다시 읽기는 부르지 않는다. */
    var onLocalChange: (() -> Unit)? = null

    /** [items] 가 바뀌었다(사용자 · 병합 · 다시 읽기 — Swift 의 관찰 자리). 위젯 스냅숏 쓰기가 건다. */
    var onItemsChanged: (() -> Unit)? = null

    /** 지금 서버 반영을 미뤄야 하는 id(편집 중인 줄 · 삭제 되돌리기 창). 지금 탭이 채운다. */
    var syncProtectedIDs: () -> Set<String> = { emptySet() }

    /** 보호 때문에 반영을 미룬 id. 보호가 풀리면 한 번 더 맞춘다([syncProtectionDidEnd]). */
    private var deferredSyncIDs: Set<String> = emptySet()

    init {
        // 복원은 생성에서 끝낸다(화면이 열릴 때 읽으면 첫 프레임이 빈 목록으로 한 번 깜빡인다).
        reload()
    }

    /** 오늘의 KST dayKey. 화면은 이 값 하나로 이월 배지·완료 노출을 판정한다. */
    val todayKey: String get() = TodoRules.dayKey(clock())

    /** 다른 계정의 파일로 갈아탄다. 세대를 **먼저** 올린다 — 진행 중이던 요청의 응답은 이 순간부터 전부 버려진다. */
    fun switchFile(path: String) {
        fileGeneration += 1
        if (filePath != path) filePath = path
        reload()
    }

    /**
     * 디스크에서 다시 읽는다. 손상 파일은 **백업으로 옮기고** 빈 목록으로 출발한다(그냥 덮어쓰면 사용자가 적어 둔 문장이 영원히 사라진다).
     * 읽으면서 셋을 정리한다: 시각을 ms 격자에 올리고(1세대), 90일 지난 완료·삭제를 빼고, 빠진 id 를 보낼 목록·붙잡기에서도 뺀다.
     * 그중 하나라도 바뀌었거나 옛 세대 파일이면 곧바로 2세대로 다시 쓴다.
     */
    fun reload() {
        val now = clock()
        val loaded = try {
            TodoFileStore.load(files, filePath)
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            try {
                files.move(filePath, TodoFileStore.corruptedBackupPath(filePath, now))
            } catch (moveError: Throwable) {
                if (moveError is CancellationException) throw moveError
            }
            TodoFile(items = emptyList(), sync = TodoFileSyncState(null, emptyList()))
        }
        val normalized = loaded.items.map { it.withMillisecondTimes() }
        val kept = TodoRules.pruned(normalized, now)
        val keptIDs = kept.map { it.id }.toSet()
        val pending = loaded.sync.pendingIDs.toSet().intersect(keptIDs)
        // 붙잡기는 정리된 줄에서 빠지고, 보낼 것과 겹치면 보낼 것이 이긴다(다시 고친 값 — 병합 ⓪ 과 같은 규칙).
        val held = loaded.sync.heldRejectedIDs.toSet().intersect(keptIDs) - pending
        assignItems(kept)
        if (pendingIDs != pending) pendingIDs = pending
        if (heldRejectedIDs != held) heldRejectedIDs = held
        if (watermarkMs != loaded.sync.watermarkMs) watermarkMs = loaded.sync.watermarkMs
        deferredSyncIDs = emptySet()
        val rewrite = kept.size != loaded.items.size ||
            normalized != loaded.items ||
            pending.size != loaded.sync.pendingIDs.size ||
            held.size != loaded.sync.heldRejectedIDs.size ||
            loaded.version < TodoFile.CURRENT_VERSION
        if (rewrite) persist()
    }

    /**
     * 새 항목을 목록 맨 앞에 넣는다. 빈 제목과 상한 초과(글자 100 · 코드 포인트 1000)는 **아무 일도 하지 않고 null** 이다 —
     * 초과는 잘라서 저장하지 않는다(붙여넣기 경로를 위해 여기서도 거절한다).
     */
    fun add(rawTitle: String): TodoItem? {
        val title = TodoRules.normalizedTitle(rawTitle)
        if (title.isEmpty() || !TodoRules.titleFitsLimits(title)) return null
        val now = TodoRules.normalizedTime(clock())
        val item = TodoItem(newID(), title, now, now, null, null, TodoRules.dayKey(now))
        assignItems(listOf(item) + items)
        didChangeLocally(item.id)
        return item
    }

    /** 완료/완료취소를 뒤집는다. **originDayKey 는 절대 건드리지 않는다**(이월 배지의 기준). */
    fun toggleDone(id: String) {
        val index = items.indexOfFirst { it.id == id }
        if (index < 0) return
        val now = TodoRules.normalizedTime(clock())
        val old = items[index]
        val next = old.copy(completedAt = if (old.completedAt == null) now else null, updatedAt = nextUpdatedAt(now, old.updatedAt))
        replace(index, next)
        didChangeLocally(id)
    }

    /** 인라인 수정 커밋. 정규화 후 빈 제목/상한 초과는 무시한다. 내용이 그대로면 updatedAt 도 건드리지 않는다. */
    fun rename(id: String, rawTitle: String) {
        val index = items.indexOfFirst { it.id == id }
        if (index < 0) return
        val title = TodoRules.normalizedTitle(rawTitle)
        if (title.isEmpty() || !TodoRules.titleFitsLimits(title)) return
        val old = items[index]
        if (old.title == title) return
        replace(index, old.copy(title = title, updatedAt = nextUpdatedAt(TodoRules.normalizedTime(clock()), old.updatedAt)))
        didChangeLocally(id)
    }

    /**
     * 삭제는 톰스톤이다(배열에서 빼지 않는다). 5초 되돌리기 창 동안 그 자리에 남아 있어야 하고, 다른 기기에 "지웠다"를 전하려면
     * 지운 사실이 행으로 남아 있어야 한다. 실제 제거는 90일 뒤 정리가 한다.
     */
    fun delete(id: String) {
        val index = items.indexOfFirst { it.id == id }
        if (index < 0 || items[index].deletedAt != null) return
        val now = TodoRules.normalizedTime(clock())
        val old = items[index]
        replace(index, old.copy(deletedAt = now, updatedAt = nextUpdatedAt(now, old.updatedAt)))
        didChangeLocally(id)
    }

    /** 되돌리기. 톰스톤만 벗기므로 제목·완료 상태·만든 날이 삭제 직전 그대로 돌아온다. */
    fun undoDelete(id: String) {
        val index = items.indexOfFirst { it.id == id }
        if (index < 0 || items[index].deletedAt == null) return
        val old = items[index]
        replace(index, old.copy(deletedAt = null, updatedAt = nextUpdatedAt(TodoRules.normalizedTime(clock()), old.updatedAt)))
        didChangeLocally(id)
    }

    /**
     * 고친 시각. **이전 값보다 반드시 1ms 이상 크다.** 서버 LWW 는 "들어온 값 > 기존 값"일 때만 덮으므로, 같은 ms 안의 두 번째 수정이나
     * 시계가 뒤로 간 뒤의 수정은 이미 올라간 옛 값에 져서 조용히 사라진다.
     */
    private fun nextUpdatedAt(now: Double, previous: Double): Double {
        val floor = TodoRules.milliseconds(previous) + 1
        return if (TodoRules.milliseconds(now) >= floor) now else TodoRules.date(floor)
    }

    /**
     * 사용자 변경 공통 꼬리: 보낼 목록에 넣고 → 저장하고 → 동기화에 알린다(순서가 곧 계약 — 저장 전에 알리면 디바운스 전에 앱이 죽었을 때
     * pending 이 파일에 없다). 거절돼 붙잡혀 있던 줄이면 여기서 **풀린다**(부록 B-3).
     */
    private fun didChangeLocally(id: String) {
        pendingIDs = pendingIDs + id
        if (id in heldRejectedIDs) heldRejectedIDs = heldRejectedIDs - id
        persist()
        onLocalChange?.invoke()
    }

    // ---------------------------------------------------------------- 동기화 문

    /** 보낼 스냅샷. 넘긴 id 중 **아직 pending 이고 로컬에 있는 것만** 싣는다. `sent` 는 싣는 순간의 updatedAtMs. */
    fun makeSyncRequest(ids: List<String>): TodoSyncOutgoing {
        val byID = LinkedHashMap<String, TodoItem>()
        for (item in items) if (item.id !in byID) byID[item.id] = item
        val seen = HashSet<String>()
        val changes = ids.mapNotNull { id -> if (id in pendingIDs && seen.add(id)) byID[id] else null }
        val sent = LinkedHashMap<String, Long>()
        for (item in changes) if (item.id !in sent) sent[item.id] = item.updatedAtMs
        return TodoSyncOutgoing(fileGeneration, TodoSyncRequest(changes.map(TodoSyncWireItem::of), watermarkMs), sent)
    }

    /**
     * 서버 응답을 합치고 watermark 를 올린 뒤 파일에 쓴다. 찍을 때의 파일 세대가 지금과 다르면 **false 이고 아무것도 바꾸지 않는다** —
     * 이 함수가 늦은 응답을 막는 유일한 문이다.
     */
    fun applySync(result: TodoSyncResult, outgoing: TodoSyncOutgoing): Boolean {
        if (outgoing.fileGeneration != fileGeneration) return false
        val merged = TodoRules.mergedSync(
            local = items,
            pending = pendingIDs,
            sent = outgoing.sent,
            server = result.items,
            rejected = result.rejectedIDs,
            full = result.full,
            held = heldRejectedIDs,
            protected = syncProtectedIDs(),
        )
        // 서버에서 온 오래된 톰스톤도 로컬 90일 정리를 똑같이 거친다. 정리된 id 는 보낼 목록·붙잡기에서도 뺀다(명세 A4-9 · B-3).
        val kept = TodoRules.pruned(merged.items, clock())
        val keptIDs = kept.map { it.id }.toSet()
        val pending = merged.pending.intersect(keptIDs)
        val held = merged.heldRejectedIDs.intersect(keptIDs)
        assignItems(kept)
        if (pendingIDs != pending) pendingIDs = pending
        if (heldRejectedIDs != held) heldRejectedIDs = held
        if (watermarkMs != result.watermarkMs) watermarkMs = result.watermarkMs
        deferredSyncIDs = deferredSyncIDs + merged.deferredIDs
        persist()
        return true
    }

    /** 보호(편집·되돌리기 창)가 끝났다. 그동안 미룬 id 가 있으면 한 번 더 맞추게 알린다. */
    fun syncProtectionDidEnd() {
        val released = deferredSyncIDs - syncProtectedIDs()
        if (released.isEmpty()) return
        deferredSyncIDs = deferredSyncIDs - released
        onLocalChange?.invoke()
    }

    private fun replace(index: Int, item: TodoItem) {
        if (items[index] == item) return
        assignItems(items.toMutableList().also { it[index] = item })
    }

    private fun assignItems(next: List<TodoItem>) {
        if (items == next) return
        items = next
        onItemsChanged?.invoke()
    }

    /** 변경마다 전체를 다시 쓴다. 실패는 삼킨다 — 메모리가 진실이므로 다음 변경에서 통째로 재시도된다. */
    private fun persist() {
        val sync = TodoFileSyncState(
            watermarkMs = watermarkMs,
            pendingIDs = pendingIDs.sortedBy { it.uppercase() },
            heldRejectedIDs = heldRejectedIDs.sortedBy { it.uppercase() },
        )
        try {
            TodoFileStore.save(files, TodoFile(items = items, sync = sync), filePath)
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
        }
    }
}
