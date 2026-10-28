// 원본: Sources/CheckMobileKit/Now/NowTodoSupport.swift @ 1b8260d (+ NowModels.swift:412-421 NowTodoRow)
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.net.isMissingDeviceFunction
import com.yehsung.aingcheck.core.net.todoSync
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRejection
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRequest
import com.yehsung.aingcheck.core.rules.todo.TodoSyncResponse
import com.yehsung.aingcheck.core.rules.todo.TodoSyncWireItem
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileSystem
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncCancellable
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncScheduler
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncTransport
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncTransportException
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.models.TodoSyncRequest as WireTodoSyncRequest
import com.yehsung.aingcheck.core.wire.models.TodoSyncResponse as WireTodoSyncResponse
import com.yehsung.aingcheck.core.wire.models.TodoSyncWireItem as WireTodoSyncItem

// 지금 탭 할 일의 배선 부품: 전송(`todo_sync` ↔ 폰 세션) · 멈출 수 있는 타이머 · 파일 자리 · 파일 조정.
// 엔진(`TodoListStore` · `TodoSync`)은 core/stores …/now/todo, 규칙(`TodoRules` · 전선)은 W1-c core/rules …/todo 를 그대로 쓴다 — 여기는 폰에 맞춘 꽂는 자리만 있다.

/**
 * 할 일 파일이 사는 폴더(Swift `AingSharedStorage.todoFileURL(userID:)` — iOS 는 App Group, Android 는 앱 전용 폴더).
 * 위젯(W2-f)도 **같은 자리 · 같은 [NowTodoFileAccess]** 로 이 파일을 고친다. 조립(K11)이 폴더와 파일 시스템을 넘긴다.
 */
class NowTodoStorage(val directory: String, val files: TodoFileSystem) {
    /** 사용자별 할 일 파일(`todos.<uid>.json`, 로그인 전은 `todos.local.json`). */
    fun todoFilePath(userID: String?): String = TodoFileStore.path(directory, userID)
}

/**
 * 폰 전송: 폰 세션으로 PostgREST `todo_sync` 를 부른다. 관용구는 맥 전송과 같다 — **세션 가드 → 세대 캡처 → 401 재시도 → 세대 가드.**
 * - HTTP 200 의 `{"status":"unauthorized"}` 도 세션 만료로 접어 세션 조정자 경유 갱신 1회를 탄다.
 * - 함수가 없는 서버(404 · PGRST202)는 functionMissing — 엔진이 조용히 멈추고 pending 을 둔다.
 * - 요청한 계정이 지금 세션이 아니면 보내지 않는다(accountMismatch) — 앞 계정의 할 일이 새 계정 토큰으로 올라가면 안 된다.
 */
class NowTodoSyncTransport(private val context: SessionContext) : TodoSyncTransport {
    override suspend fun todoSync(userID: String, request: TodoSyncRequest): TodoSyncResponse {
        val current = context.sessionStore.session
        if (!context.sessionStore.isSignedIn || current == null || current.userID != userID) {
            throw TodoSyncTransportException(TodoSyncTransportException.Kind.accountMismatch)
        }
        val generation = context.generation
        val service = context.service
        val response = try {
            context.withSessionRetry { session ->
                val reply = service.todoSync(session.accessToken, request.toWire())
                if (reply.status == "unauthorized") throw SupabaseWorkServiceError.SessionExpired
                reply.toRules()
            }
        } catch (error: Throwable) {
            if (isMissingDeviceFunction(error)) throw TodoSyncTransportException(TodoSyncTransportException.Kind.functionMissing)
            throw error
        }
        if (generation != context.generation) throw TodoSyncTransportException(TodoSyncTransportException.Kind.accountMismatch)
        return response
    }
}

/*
 * 전선 두 벌 잇기: 서비스(W1-d core/net)는 core/wire 의 `TodoSyncRequest`·`TodoSyncResponse` 를, 병합 규칙(W1-c core/rules)은 같은 모양의
 * rules 타입을 쓴다(둘 다 Swift `TodoSync.swift` 의 같은 구조체 — c-fold 후보). 여기서 칸을 그대로 옮긴다(값 변환 없음).
 */
private fun TodoSyncRequest.toWire(): WireTodoSyncRequest = WireTodoSyncRequest(
    changes.map { WireTodoSyncItem(it.id, it.title, it.createdAtMs, it.updatedAtMs, it.completedAtMs, it.deletedAtMs, it.originDayKey) },
    sinceMs,
)

private fun WireTodoSyncResponse.toRules(): TodoSyncResponse = TodoSyncResponse(
    status = status,
    items = items?.map { TodoSyncWireItem(it.id, it.title, it.createdAtMs, it.updatedAtMs, it.completedAtMs, it.deletedAtMs, it.originDayKey) },
    watermarkMs = watermarkMs,
    rejected = rejected?.map { TodoSyncRejection(it.id, it.reason) },
    full = full,
    max = max,
)

/**
 * 엔진의 디바운스(1.5초)·주기(5분) 예약을 **앱이 background 인 동안 막는다**(SPEC-ios §3: background 로 가면 멈춘다).
 * 엔진에는 "멈춤" 문이 없다. 계정을 비우는 `activate(null)` 로 멈추면 background 직전에 띄운 마지막 전송까지 첫 줄에서 돌아간다.
 * 그래서 예약만 가로막는다: 멈춘 동안 깨어난 예약은 버린다 — 주기 사슬은 끊기고, active 로 돌아오면 스토어가 다시 건다.
 */
class NowPausableScheduler(private val base: TodoSyncScheduler) : TodoSyncScheduler {
    var isPaused: Boolean = false
        private set

    /** 멈춘 동안 버린 예약 수(시험). */
    var droppedCount: Int = 0
        private set

    fun pause() {
        isPaused = true
    }

    fun resume() {
        isPaused = false
    }

    override fun schedule(afterSeconds: Double, action: () -> Unit): TodoSyncCancellable =
        base.schedule(afterSeconds) {
            if (isPaused) {
                droppedCount += 1
            } else {
                action()
            }
        }
}

/**
 * 앱 쪽 할 일 파일 접근을 **위젯 동작과 같은 조정 구간**에 넣는다(Swift `NowTodoFileAccess` — iOS 는 NSFileCoordinator).
 * Android 위젯(Glance 동작)은 앱과 **같은 프로세스**의 다른 스레드에서 돈다 — 그래서 조정은 프로세스 안의 경로별 잠금이다. 위젯의 체크(W2-f)도
 * 반드시 이 문으로 읽고-고치고-쓴다. 앱의 다시 읽기·사용자 변경을 같은 경로의 잠금 안에서 하면 둘이 직렬화된다(앱이 위젯 쓰기 사이에 끼어
 * 읽은 옛 목록으로 위젯의 체크를 덮지 않게). 동기화 응답 병합(`applySync`)은 엔진 안이라 여기로 감싸지 않는다(Swift 와 같은 남은 위험).
 */
object NowTodoFileAccess {
    fun <T> coordinated(path: String, body: () -> T): T = withTodoFileLock(path, body)
}

/** 경로별 프로세스 잠금(JVM `synchronized` — Android·데스크톱 actual). */
internal expect fun <T> withTodoFileLock(path: String, body: () -> T): T

/** 할 일 한 줄의 화면 값(Swift `NowTodoRow`). */
data class NowTodoRow(
    val id: String,
    val title: String,
    val isDone: Boolean,
    /** "어제" · "3일 전"(오늘 만든 것은 null). */
    val carryBadge: String?,
    val carryOverDays: Int,
)

/** 지금 탭 할 일 목록(오늘 · 7일 넘게 이월된 미완료는 '오래된 항목'으로 따로). */
data class NowTodoRows(val main: List<NowTodoRow>, val old: List<NowTodoRow>)
