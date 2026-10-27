// 원본: Sources/CheckCore/TodoSync.swift @ 1b8260d (전선 모양 · 합칠 결과 · 배치 규칙 — 엔진 TodoSync(@MainActor · 전송 · 스케줄러 주입)와
//       조정자는 지금/할 일 스토어 갈래(W2)가 이 규칙 위에 옮긴다)
package com.yehsung.aingcheck.core.rules.todo

import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.SwiftValue
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** uuid 글자(Swift `UUID(uuidString:)` 가 받는 꼴) → 소문자. 아니면 null. */
internal fun normalizedUUID(text: String?): String? {
    if (text == null || !UUID_RE.matches(text)) return null
    return text.lowercase()
}

private val UUID_RE = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

/** 서버 JSON 과 글자 단위로 같은 한 줄(snake_case 고정 — 서비스 공용 인코더를 쓰지 않는다). 칸마다 try?(틀리면 null). */
data class TodoSyncWireItem(
    val id: String?,
    val title: String?,
    val createdAtMs: Long?,
    val updatedAtMs: Long?,
    val completedAtMs: Long?,
    val deletedAtMs: Long?,
    val originDayKey: String?,
) {
    /** 받은 줄 → 항목(id 가 uuid 이고 제목 · 만든/고친 ms · 원래 날이 있을 때만). */
    fun todoItem(): TodoItem? {
        val id = normalizedUUID(id) ?: return null
        val title = title ?: return null
        val created = createdAtMs ?: return null
        val updated = updatedAtMs ?: return null
        val origin = originDayKey ?: return null
        return TodoItem(id, title, TodoRules.date(created), TodoRules.date(updated), completedAtMs?.let(TodoRules::date),
            deletedAtMs?.let(TodoRules::date), origin)
    }

    /** 본문 JSON(키 일곱을 언제나 싣는다 — null 도). */
    fun json(): JsonObject = JsonObject(linkedMapOf(
        "completed_at_ms" to num(completedAtMs), "created_at_ms" to num(createdAtMs), "deleted_at_ms" to num(deletedAtMs),
        "id" to str(id), "origin_day_key" to str(originDayKey), "title" to str(title), "updated_at_ms" to num(updatedAtMs),
    ))

    companion object {
        fun of(item: TodoItem): TodoSyncWireItem = TodoSyncWireItem(
            item.id.lowercase(), item.title, TodoRules.milliseconds(item.createdAt), TodoRules.milliseconds(item.updatedAt),
            item.completedAt?.let(TodoRules::milliseconds), item.deletedAt?.let(TodoRules::milliseconds), item.originDayKey,
        )

        fun decode(element: JsonElement): TodoSyncWireItem {
            val o = SwiftValue.obj(element)
            fun s(key: String) = tryOrNull { o[key]?.takeIf { it !is JsonNull }?.let(SwiftValue::string) }
            fun i(key: String) = tryOrNull { o[key]?.takeIf { it !is JsonNull }?.let(SwiftValue::int) }
            return TodoSyncWireItem(s("id"), s("title"), i("created_at_ms"), i("updated_at_ms"), i("completed_at_ms"), i("deleted_at_ms"), s("origin_day_key"))
        }

        private fun num(v: Long?): JsonElement = v?.let { JsonPrimitive(it) } ?: JsonNull
        private fun str(v: String?): JsonElement = v?.let { JsonPrimitive(it) } ?: JsonNull
    }
}

private inline fun <T> tryOrNull(block: () -> T): T? = try { block() } catch (e: SwiftDecodingError) { null }

/** `todo_sync(p_changes, p_since_ms)` 본문 — **p_since_ms 는 null 이어도 싣는다**(C§4 #10 — 키 집합이 늘 같아야 함수 해석이 안 갈린다). */
data class TodoSyncRequest(val changes: List<TodoSyncWireItem>, val sinceMs: Long?) {
    fun rpcBody(): JsonObject = JsonObject(linkedMapOf(
        "p_changes" to JsonArray(changes.map { it.json() }),
        "p_since_ms" to (sinceMs?.let { JsonPrimitive(it) } ?: JsonNull),
    ))

    fun changesJSON(): JsonArray = JsonArray(changes.map { it.json() })
}

data class TodoSyncRejection(val id: String?, val reason: String?)

/** `todo_sync` 응답 — 칸마다 try?. 최상위가 객체가 아니면 [SwiftDecodingError]. */
data class TodoSyncResponse(
    val status: String?,
    val items: List<TodoSyncWireItem>? = null,
    val watermarkMs: Long? = null,
    val rejected: List<TodoSyncRejection>? = null,
    val full: Boolean? = null,
    val max: Long? = null,
) {
    /** status 'ok' 이고 items · watermark 가 있을 때만. full 은 **모든 행을 읽었을 때만** 참(못 읽은 행이 있으면 full 병합을 끈다). */
    fun mergeableResult(): TodoSyncResult? {
        if (status != "ok") return null
        val items = items ?: return null
        val watermark = watermarkMs ?: return null
        val decoded = items.mapNotNull { it.todoItem() }
        val everyRowRead = decoded.size == items.size
        return TodoSyncResult(
            items = decoded,
            rejectedIDs = (rejected ?: emptyList()).mapNotNull { normalizedUUID(it.id) }.toSet(),
            full = (full ?: false) && everyRowRead,
            watermarkMs = watermark,
        )
    }

    companion object {
        fun decode(element: JsonElement): TodoSyncResponse {
            val o = SwiftValue.obj(element)
            fun present(key: String) = o[key]?.takeIf { it !is JsonNull }
            return TodoSyncResponse(
                status = tryOrNull { present("status")?.let(SwiftValue::string) },
                // [T] 디코드가 원소 하나 때문에 실패하면 배열 전체가 null(Swift try? decodeIfPresent([T])).
                items = tryOrNull { present("items")?.let { SwiftValue.array(it).map(TodoSyncWireItem::decode) } },
                watermarkMs = tryOrNull { present("watermark_ms")?.let(SwiftValue::int) },
                rejected = tryOrNull { present("rejected")?.let { e -> SwiftValue.array(e).map { r ->
                    val ro = SwiftValue.obj(r)
                    TodoSyncRejection(tryOrNull { ro["id"]?.takeIf { it !is JsonNull }?.let(SwiftValue::string) },
                        tryOrNull { ro["reason"]?.takeIf { it !is JsonNull }?.let(SwiftValue::string) })
                } } },
                full = tryOrNull { present("full")?.let(SwiftValue::bool) },
                max = tryOrNull { present("max")?.let(SwiftValue::int) },
            )
        }
    }
}

data class TodoSyncResult(val items: List<TodoItem>, val rejectedIDs: Set<String>, val full: Boolean, val watermarkMs: Long)

/** 엔진의 상수와 배치 규칙(엔진 자체는 W2). */
object TodoSyncRules {
    const val debounceSeconds = 1.5
    const val periodicSeconds = 300.0
    const val batchLimit = 500
    const val serverMissingCooldownSeconds = 300.0

    /** 보낼 id 를 대문자 uuid 글자 순으로 500 개씩. 비면 빈 묶음 하나(watermark 만 묻는다). */
    fun batches(pendingIDs: Collection<String>): List<List<String>> {
        val sorted = pendingIDs.sortedBy { it.uppercase() }
        if (sorted.isEmpty()) return listOf(emptyList())
        return sorted.chunked(batchLimit)
    }
}
