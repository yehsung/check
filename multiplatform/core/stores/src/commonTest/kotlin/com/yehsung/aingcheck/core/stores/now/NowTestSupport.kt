// 원본: Tests/CheckMobileKitTests/NowTestSupport.swift(손으로 미는 타이머 · 가짜 todo_sync 서버 · 지금 탭 시나리오 서버) @ 1b8260d
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.rules.todo.TodoSyncWireItem
import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileSystem
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncCancellable
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncScheduler
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/** 메모리 파일 시스템(경로 → 바이트). 쓰기 실패를 흉내 내려면 [failWrites] 를 켠다. */
class InMemoryTodoFileSystem : TodoFileSystem {
    val contents: MutableMap<String, ByteArray> = LinkedHashMap()
    var failWrites: Boolean = false
    var writeCount: Int = 0
        private set

    override fun read(path: String): ByteArray? = contents[path]?.copyOf()

    override fun writeAtomically(path: String, bytes: ByteArray) {
        if (failWrites) throw IllegalStateException("쓰기 실패(흉내)")
        writeCount += 1
        contents[path] = bytes.copyOf()
    }

    override fun move(from: String, to: String) {
        val bytes = contents.remove(from) ?: return
        contents[to] = bytes
    }

    fun text(path: String): String? = contents[path]?.decodeToString()
}

/** 손으로 미는 타이머(디바운스 1.5초 · 주기 60초·5분 · 되돌리기 5초를 기다리지 않는다 — Swift `NowManualScheduler`). */
class ManualScheduler : TodoSyncScheduler {
    private class Item(val due: Double, val seq: Int, val action: () -> Unit) : TodoSyncCancellable {
        var cancelled = false
        override fun cancel() {
            cancelled = true
        }
    }

    var elapsed: Double = 0.0
        private set
    private val items = ArrayList<Item>()
    private var seq = 0

    override fun schedule(afterSeconds: Double, action: () -> Unit): TodoSyncCancellable {
        seq += 1
        return Item(elapsed + afterSeconds, seq, action).also { items += it }
    }

    /** 시간을 민다(그 사이 만기인 예약을 순서대로 실행 — 실행 중 새로 건 예약도 창 안이면 돈다). */
    fun advance(seconds: Double) {
        val target = elapsed + seconds
        while (true) {
            items.removeAll { it.cancelled }
            val next = items.filter { it.due <= target + 1e-9 }.minWithOrNull(compareBy({ it.due }, { it.seq })) ?: break
            items.remove(next)
            elapsed = maxOf(elapsed, next.due)
            next.action()
        }
        elapsed = target
    }

    val liveCount: Int get() = items.count { !it.cancelled }
}

/** 시험 서버의 `todo_sync`(LWW · 전체를 돌려준다 — Swift `NowFakeTodoServer`). */
class FakeTodoServer {
    private val rows = LinkedHashMap<String, JsonObject>()
    var calls: Int = 0
        private set
    var changeIDs: List<String> = emptyList()
        private set
    var watermarkMs: Long = 1_789_621_500_000
    var failure: Reply? = null

    fun seed(item: JsonObject) {
        val id = item["id"]!!.jsonPrimitive.content.lowercase()
        rows[id] = item
    }

    fun row(id: String): JsonObject? = rows[id.lowercase()]

    fun respond(r: RecordedRequest): Reply {
        calls += 1
        failure?.let { return it }
        val body = SwiftJson.parse(r.bodyText) as JsonObject
        val changes = (body["p_changes"] as? JsonArray ?: JsonArray(emptyList())).map { it as JsonObject }
        val since = body["p_since_ms"]?.takeIf { it !is JsonNull }
        changeIDs = changes.mapNotNull { it["id"]?.jsonPrimitive?.content?.lowercase() }
        for (change in changes) {
            val id = change["id"]?.jsonPrimitive?.content?.lowercase() ?: continue
            val incoming = change["updated_at_ms"]?.jsonPrimitive?.longOrNull ?: 0
            val existing = rows[id]?.get("updated_at_ms")?.jsonPrimitive?.longOrNull
            if (existing == null || incoming > existing) rows[id] = change
        }
        watermarkMs += 1000
        val out = JsonObject(linkedMapOf(
            "status" to JsonPrimitive("ok"),
            "items" to JsonArray(rows.values.toList()),
            "watermark_ms" to JsonPrimitive(watermarkMs),
            "rejected" to JsonArray(emptyList()),
            "full" to JsonPrimitive(since == null),
        ))
        return Reply.Json(out.toString())
    }

    companion object {
        fun wire(item: TodoSyncWireItem): JsonObject = item.json()
    }
}

/**
 * 지금 탭 시나리오 서버(Swift `NowStubServer`): 팀 상태(GET 넷) · 멤버십 · 디렉터리 · 목표 · 할 일. 기준 시각은 데모 시각
 * 2026-09-17 05:05:00Z(14:05 KST, 목요일) — 하네스 시계와 같다. 나는 하네스의 로그인 사용자([StoreHarness.ME]).
 */
class NowStubServer {
    val todo = FakeTodoServer()
    val overrides = LinkedHashMap<String, Reply?>()
    var goalHours = 40

    /** `todo_sync` 를 붙잡는 문. 서버 처리(LWW 기록)는 요청이 **들어온 순간** 하고, 응답만 기다린다. */
    var todoGate: kotlinx.coroutines.CompletableDeferred<Unit>? = null

    fun override(key: String, reply: Reply?) {
        if (reply == null) overrides.remove(key) else overrides[key] = reply
    }

    fun route(r: RecordedRequest): Reply? {
        val key = key(r)
        overrides[key]?.let { return it }
        return when (key) {
            "memberships" -> Reply.Json("""[{"team_id":"$TEAM","role":"member","teams":{"name":"지금팀","weekly_goal_hours":$goalHours}}]""")
            "work_statuses" -> Reply.Json(STATUSES)
            "work_sessions.active" -> Reply.Json(ACTIVE_SESSIONS)
            "work_sessions.weekly" -> Reply.Json(WEEKLY_SESSIONS)
            "work_status_devices" -> Reply.Json("[]")
            "rpc.app_user_directory" -> Reply.Json(DIRECTORY)
            "rpc.set_team_weekly_goal" -> {
                val body = SwiftJson.parse(r.bodyText) as JsonObject
                val hours = body.values.firstNotNullOfOrNull { it.jsonPrimitive.longOrNull }?.toInt() ?: 0
                goalHours = hours
                Reply.Json("""[{"weekly_goal_hours":$hours}]""")
            }
            "rpc.todo_sync" -> todo.respond(r).let { reply -> todoGate?.let { Reply.Gate(it, reply) } ?: reply }
            else -> null
        }
    }

    companion object {
        const val TEAM = "team-now"
        val ME = StoreHarness.ME
        const val MINT = "u-mint"
        const val LIME = "u-lime"
        const val BORI = "u-bori"
        const val JADU = "u-jadu"
        const val CORAL = "u-coral"
        const val MORAE = "u-morae"
        const val HANEUL = "u-haneul"

        fun key(r: RecordedRequest): String {
            r.rpcName?.let { return "rpc.$it" }
            val table = r.path.removePrefix("/rest/v1/")
            if (table == "work_sessions") return if (r.query.any { it.second == "is.null" }) "work_sessions.active" else "work_sessions.weekly"
            return table
        }

        val STATUSES = """
            [{"user_id":"$ME","status":"working","updated_at":"2026-09-17T05:04:40Z","last_seen_at":"2026-09-17T05:04:40Z","profiles":{"display_name":"나","avatar_url":null}},
             {"user_id":"u-mint","status":"working","updated_at":"2026-09-17T05:04:10Z","last_seen_at":"2026-09-17T05:04:10Z","profiles":{"display_name":"민트","avatar_url":null}},
             {"user_id":"u-lime","status":"working","updated_at":"2026-09-17T05:04:55Z","last_seen_at":"2026-09-17T05:04:55Z","profiles":{"display_name":"라임","avatar_url":"https://x.invalid/lime.jpg"}},
             {"user_id":"u-bori","status":"working","updated_at":"2026-09-17T04:52:00Z","last_seen_at":"2026-09-17T04:52:00Z","profiles":{"display_name":"보리","avatar_url":null}},
             {"user_id":"u-jadu","status":"offWork","updated_at":"2026-09-17T02:10:00Z","last_seen_at":"2026-09-17T02:10:00Z","profiles":{"display_name":"자두","avatar_url":null}}]
        """.trimIndent()

        val ACTIVE_SESSIONS = """
            [{"id":"s1","user_id":"$ME","started_at":"2026-09-17T01:20:00Z","ended_at":null},
             {"id":"s2","user_id":"u-mint","started_at":"2026-09-17T00:55:00Z","ended_at":null},
             {"id":"s3","user_id":"u-lime","started_at":"2026-09-17T03:30:00Z","ended_at":null},
             {"id":"s4","user_id":"u-bori","started_at":"2026-09-17T02:00:00Z","ended_at":null}]
        """.trimIndent()

        /** 나: 월 7:40 · 화 7:30 · 수 4:28 · 오늘 새벽 1:25 → 끝난 세션 21.05시간 + 진행 3:45 = 24.8시간(89,280초), 오늘 5:10:00. */
        val WEEKLY_SESSIONS = """
            [{"user_id":"$ME","started_at":"2026-09-14T00:30:00Z","ended_at":"2026-09-14T08:10:00Z"},
             {"user_id":"$ME","started_at":"2026-09-15T00:50:00Z","ended_at":"2026-09-15T08:20:00Z"},
             {"user_id":"$ME","started_at":"2026-09-16T01:00:00Z","ended_at":"2026-09-16T05:28:00Z"},
             {"user_id":"$ME","started_at":"2026-09-16T23:40:00Z","ended_at":"2026-09-17T01:05:00Z"},
             {"user_id":"u-mint","started_at":"2026-09-15T00:00:00Z","ended_at":"2026-09-15T09:00:00Z"}]
        """.trimIndent()

        val DIRECTORY = """
            [{"user_id":"u-mint","display_name":"민트","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul"},
             {"user_id":"u-lime","display_name":"라임","avatar_url":null,"is_working":true,"message_capable":true,"center":null},
             {"user_id":"u-bori","display_name":"보리","avatar_url":null,"is_working":true,"message_capable":true,"center":"busan"},
             {"user_id":"u-coral","display_name":"코랄","avatar_url":null,"is_working":true,"message_capable":true,"center":"busan"},
             {"user_id":"u-morae","display_name":"모래","avatar_url":"https://x.invalid/morae.jpg","is_working":true,"message_capable":true,"center":"seoul"},
             {"user_id":"u-haneul","display_name":"하늘","avatar_url":null,"is_working":true,"message_capable":true,"center":null},
             {"user_id":"u-jadu","display_name":"자두","avatar_url":null,"is_working":false,"message_capable":true,"center":"seoul"},
             {"user_id":"u-gureum","display_name":"구름","avatar_url":null,"is_working":false,"message_capable":true,"center":"seoul"}]
        """.trimIndent()

        /** 쉬는 사용자의 팀 상태(근무 안 함 · 세션 없음). */
        val IDLE_STATUSES = """
            [{"user_id":"$ME","status":"offWork","updated_at":"2026-09-17T03:00:00Z","last_seen_at":"2026-09-17T03:00:00Z","profiles":{"display_name":"나","avatar_url":null}}]
        """.trimIndent()

        /** 나 · 민트가 근무 중이고 마지막 신호가 [meSeen](맥은 30초마다 하트비트). */
        fun statuses(meSeen: String, mintSeen: String? = null): String {
            val mint = mintSeen ?: meSeen
            return """
                [{"user_id":"$ME","status":"working","updated_at":"$meSeen","last_seen_at":"$meSeen","profiles":{"display_name":"나","avatar_url":null}},
                 {"user_id":"u-mint","status":"working","updated_at":"$mint","last_seen_at":"$mint","profiles":{"display_name":"민트","avatar_url":null}}]
            """.trimIndent()
        }
    }
}

/** 위젯 쓰기 창구 흉내(쓰기는 W2-f) — 언제 쓰라고 했는지만 센다. */
class RecordingWidgetSink : NowWidgetSink {
    val writes = ArrayList<Boolean>()
    val touches = ArrayList<com.yehsung.aingcheck.core.wire.SwiftDate>()
    override fun write(deferWhileRefreshing: Boolean) {
        writes += deferWhileRefreshing
    }

    override fun touch(at: com.yehsung.aingcheck.core.wire.SwiftDate) {
        touches += at
    }
}
