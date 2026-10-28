// 원본: Tests/checkTests/V0330TodoMergeTests.swift:17-122(TodoSyncV0330Server — 서버 todo_sync 모형) ·
//       V0330TodoSyncEngineTests.swift:17-147(가짜 전송 · 손으로 미는 타이머 · 문) @ 1b8260d
package com.yehsung.aingcheck.core.stores.now.todo

import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRejection
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRequest
import com.yehsung.aingcheck.core.rules.todo.TodoSyncResponse
import com.yehsung.aingcheck.core.rules.todo.TodoSyncWireItem
import com.yehsung.aingcheck.core.stores.now.InMemoryTodoFileSystem
import kotlinx.coroutines.CompletableDeferred

const val TODO_BASE_MS: Long = 1_726_500_000_000
const val USER_A = "11111111-1111-4111-8111-111111111111"
const val USER_B = "22222222-2222-4222-8222-222222222222"

/** KST 벽시계 → 1970 기준 초(Swift 시험의 `kst(y, m, d, h, mi)`). */
fun kst(year: Int, month: Int, day: Int, hour: Int, minute: Int): Double =
    KstCalendar.date(year, month, day)!! + hour * 3600.0 + minute * 60.0

fun msDate(ms: Long): Double = TodoRules.date(ms)

/** 정수 ms 격자 위의 항목 하나(Swift 시험의 `TodoItem(id: UUID(), …)` / `row(_:updated:deleted:)`). */
fun todoRow(id: String, title: String, updatedMs: Long, createdMs: Long = TODO_BASE_MS, completedMs: Long? = null, deletedMs: Long? = null, origin: String = "20260916") =
    TodoItem(id, title, msDate(createdMs), msDate(updatedMs), completedMs?.let(::msDate), deletedMs?.let(::msDate), origin)

fun uuid(n: Int): String = "00000000-0000-4000-8000-" + n.toString().padStart(12, '0')

/**
 * 서버 `todo_sync` 모형(Swift `TodoSyncV0330Server`): 계정별 행 · LWW(들어온 값 > 기존 값일 때만) · 검증 거절(invalid) · 자리 상한(quota) ·
 * 미래 시각 접기(+5분 넘으면 now) · full(since 없음 · 80일보다 오래됨 · 미래) · 증분은 since − 60초 겹침 창 + 이번에 받은 id.
 */
class TodoServerModel(var nowMs: Long) {
    private class Row(val item: TodoSyncWireItem, val serverUpdatedMs: Long)

    private val rows = LinkedHashMap<String, LinkedHashMap<String, Row>>()
    var quota = 5000
    var callCount = 0
        private set

    fun respond(userID: String, request: TodoSyncRequest): TodoSyncResponse {
        callCount += 1
        val now = nowMs
        if (request.changes.size > 500) return TodoSyncResponse(status = "too_many", max = 500)
        val table = rows.getOrPut(userID) { LinkedHashMap() }
        val rejected = ArrayList<TodoSyncRejection>()
        val validIDs = ArrayList<String>()
        for (change in request.changes) {
            val rawID = change.id
            val title = change.title
            val created = change.createdAtMs
            val updated = change.updatedAtMs
            val day = change.originDayKey
            val ok = rawID != null && UUID_RE.matches(rawID) && title != null && !isBlank(title) &&
                title.scalarCount() <= 1000 && created != null && created >= 0 && updated != null && updated >= 0 &&
                (change.completedAtMs ?: 0) >= 0 && (change.deletedAtMs ?: 0) >= 0 &&
                day != null && day.length == 8 && day.all { it in '0'..'9' }
            if (!ok) {
                rejected += TodoSyncRejection(rawID, "invalid")
                continue
            }
            val id = rawID!!.lowercase()
            fun clamp(v: Long?): Long? = v?.let { if (it > now + 300_000) now else it }
            val incoming = TodoSyncWireItem(id, title, clamp(created), clamp(updated), clamp(change.completedAtMs), clamp(change.deletedAtMs), day)
            if (table[id] == null && table.size >= quota) {
                rejected += TodoSyncRejection(rawID, "quota")
                continue
            }
            validIDs += id
            val existing = table[id]
            if (existing != null && (incoming.updatedAtMs ?: 0) <= (existing.item.updatedAtMs ?: 0)) continue
            table[id] = Row(incoming, now)
        }
        val eightyDays = 80L * 86_400_000
        val since = request.sinceMs
        val full = since == null || since < now - eightyDays || since > now
        val picked = LinkedHashMap<String, Row>()
        if (full) {
            picked.putAll(table)
        } else {
            for ((id, row) in table) if (row.serverUpdatedMs >= since!! - 60_000) picked[id] = row
            for (id in validIDs) table[id]?.let { picked[id] = it }
        }
        return TodoSyncResponse(
            status = "ok",
            items = picked.keys.sorted().mapNotNull { picked[it]?.item },
            watermarkMs = now,
            rejected = rejected,
            full = full,
        )
    }

    /** 서버가 들고 있는 이 사용자의 할 일(로컬 모양, id 순). */
    fun items(userID: String): List<TodoItem> =
        (rows[userID] ?: emptyMap<String, Row>()).values.mapNotNull { it.item.todoItem() }.sortedBy { it.id.uppercase() }

    /** 다른 기기가 직접 쓴 것처럼 행을 넣는다. */
    fun seed(userID: String, item: TodoItem) {
        val wire = TodoSyncWireItem.of(item)
        rows.getOrPut(userID) { LinkedHashMap() }[wire.id!!] = Row(wire, nowMs)
    }

    private fun isBlank(title: String): Boolean = title.scalarList().all { c ->
        c in 0x09..0x0D || c == 0x20 || c == 0x85 || c == 0xA0 || c == 0x1680 || c == 0x180E || c in 0x2000..0x200B ||
            c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF
    }

    private fun String.scalarList(): List<Int> {
        val out = ArrayList<Int>()
        var i = 0
        while (i < length) {
            val c = this[i]
            if (c.isHighSurrogate() && i + 1 < length && this[i + 1].isLowSurrogate()) {
                out += 0x10000 + ((c.code - 0xD800) shl 10) + (this[i + 1].code - 0xDC00)
                i += 2
            } else {
                out += c.code
                i += 1
            }
        }
        return out
    }

    private fun String.scalarCount(): Int = scalarList().size

    companion object {
        private val UUID_RE = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
    }
}

/** 가짜 전송(Swift `TodoSyncV0330Transport`). 부를 때마다 기록하고 [respond] 로 답한다. [gate] 가 있으면 응답 전에 기다린다. */
class RecordingTransport(var respond: suspend (String, TodoSyncRequest) -> TodoSyncResponse) : TodoSyncTransport {
    val requests = ArrayList<Pair<String, TodoSyncRequest>>()

    /** 다음 요청들이 기다릴 문. null 이면 곧바로 답한다. 문에 걸린 수는 [arrivals]. */
    var gate: CompletableDeferred<Unit>? = null
    var arrivals = 0
        private set

    override suspend fun todoSync(userID: String, request: TodoSyncRequest): TodoSyncResponse {
        requests += userID to request
        gate?.let {
            arrivals += 1
            it.await()
        }
        return respond(userID, request)
    }

    companion object {
        fun of(server: TodoServerModel) = RecordingTransport { userID, request -> server.respond(userID, request) }
    }
}

/** 메모리 파일 위의 목록 하나(경로 · 시계 주입). */
fun memoryList(files: InMemoryTodoFileSystem = InMemoryTodoFileSystem(), path: String = "/mem/todos.local.json", clock: () -> Double): TodoListStore =
    TodoListStore(path, files, clock)
