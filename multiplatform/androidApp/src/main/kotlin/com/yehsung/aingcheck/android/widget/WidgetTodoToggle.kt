// 원본: Sources/CheckWidgetsKit/WidgetTodoToggle.swift @ 3bd04bd (위젯 체크 본문 — 순서 계약)
// 원본: Sources/CheckWidgetsKit/Shared/WidgetSharedData.swift @ 3bd04bd (위젯이 앱과 나눠 보는 읽기 창구 · 60초 토큰 규칙)
//
// 위젯 할 일 체크(③ — 순서가 계약이다, SPEC-ios §4 · R5 · E§7.1):
//  1. 할 일 파일을 **조정 구간 안에서**(core/stores NowTodoFileAccess — 앱의 다시 읽기·편집과 같은 경로별 잠금) 코어 TodoListStore 로 열어 완료를
//     뒤집는다(앱과 같은 규칙: 정수 ms · 1ms 밀어 올리기 · pending 에 넣기 · 붙잡기 풀기). 파일에 쌓인 보낼 것 전부를 한 요청(상한 500)에 싣는다.
//  2. 위젯 스냅숏의 그 줄 체크 표시만 고친다 — 위젯은 스냅숏만 그리므로, 이걸 안 하면 체크가 앱을 열 때까지 안 보인다.
//  3. **토큰 갱신은 절대 하지 않는다.** 금고의 access token 이 60초 이상 유효할 때만 `todo_sync` 를 **한 번** 보낸다(재시도·401 갱신 없음).
//     아니면 pending 이 파일에 남아 앱이 active 가 될 때 올린다. refresh token 은 읽지도 않는다(갱신 주체는 앱 세션 스토어 하나 — C§4 #4).
//  4. 응답이 오면 다시 조정 구간에서 **그 순간의 파일**을 열어 코어 병합(applySync — 보낸 스냅숏 비교)으로 합친다.
// Android 판 차이: 위젯은 앱과 **같은 프로세스**의 다른 스레드에서 돈다(Glance ActionCallback) — 조정은 NSFileCoordinator 가 아니라 프로세스 안
// 경로별 잠금이다(NowTodoFileAccess, W2-b). 스냅숏 형식·파일은 W2-f 위젯 쓰기 창구 몫이라 [WidgetSnapshotTodoPatcher] 문으로만 고친다.
package com.yehsung.aingcheck.android.widget

import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.net.JWTClaims
import com.yehsung.aingcheck.core.net.isMissingDeviceFunction
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRejection
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRequest
import com.yehsung.aingcheck.core.rules.todo.TodoSyncResponse
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRules
import com.yehsung.aingcheck.core.rules.todo.TodoSyncWireItem
import com.yehsung.aingcheck.core.session.SessionPrefsKeys
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import com.yehsung.aingcheck.core.stores.now.NowTodoFileAccess
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileSystem
import com.yehsung.aingcheck.core.stores.now.todo.TodoListStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncOutgoing
import kotlinx.coroutines.CancellationException
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.todoSync
import com.yehsung.aingcheck.core.wire.models.TodoSyncRequest as WireTodoSyncRequest
import com.yehsung.aingcheck.core.wire.models.TodoSyncResponse as WireTodoSyncResponse
import com.yehsung.aingcheck.core.wire.models.TodoSyncWireItem as WireTodoSyncItem

/** 위젯 스냅숏에서 할 일 한 줄의 체크 표시만 바꾸는 문(순서·생성 시각은 그대로 — 앱이 다음에 새로 쓴다). 구현은 W2-f 스냅숏 창구(조립이 꽂는다). */
fun interface WidgetSnapshotTodoPatcher {
    fun patchTodo(id: String, isCompleted: Boolean)
}

/**
 * 위젯이 앱과 나눠 보는 것 — **읽기 전용 창구**(Swift `WidgetSharedData`). 토큰은 access token 만 읽는다(refresh token 을 읽는 문이 없다).
 */
interface WidgetSharedData {
    /** 로그인한 사용자(로그아웃이면 null). */
    val signedInUserID: String?

    val files: TodoFileSystem

    /** 이 사용자의 할 일 파일(로그아웃이면 null). */
    val todoFilePath: String?

    val snapshot: WidgetSnapshotTodoPatcher

    /** 지금 바로 쓸 수 있는 access token(만료까지 60초 이상 남았을 때만). exp 를 못 읽으면 null — 모르면 쓰지 않는다. */
    fun usableAccessToken(nowSeconds: Double): String?

    companion object {
        /** 인텐트가 access token 을 쓸 수 있는 최소 남은 시간(초). */
        const val MINIMUM_TOKEN_VALIDITY_SECONDS: Double = 60.0
    }
}

/** Android 판: 앱과 같은 설정 저장소·금고·할 일 폴더(같은 프로세스 — App Group 이 필요 없다). */
class AndroidWidgetSharedData(
    private val prefs: KeyValueStore,
    private val vault: TokenVault,
    private val storage: NowTodoStorage,
    override val snapshot: WidgetSnapshotTodoPatcher,
) : WidgetSharedData {
    override val signedInUserID: String?
        get() = prefs.getString(SessionPrefsKeys.userID)?.takeIf { it.isNotEmpty() }

    override val files: TodoFileSystem get() = storage.files

    override val todoFilePath: String? get() = signedInUserID?.let(storage::todoFilePath)

    override fun usableAccessToken(nowSeconds: Double): String? {
        if (signedInUserID == null) return null
        val token = vault.read(SessionVaultKeys.accessToken)?.takeIf { it.isNotEmpty() } ?: return null
        val expiry = JWTClaims.expiry(token) ?: return null
        return if (expiry.timeIntervalSince1970 - nowSeconds >= WidgetSharedData.MINIMUM_TOKEN_VALIDITY_SECONDS) token else null
    }
}

object WidgetTodoToggle {
    /** access token 과 요청 → 응답(프로덕션은 [serviceSync] — `todo_sync` 한 번, 시험은 기록기). */
    fun interface Sync {
        suspend fun sync(accessToken: String, request: TodoSyncRequest): TodoSyncResponse
    }

    sealed interface Outcome {
        /** 로그아웃(할 일 파일 없음). */
        data object SignedOut : Outcome

        /** 그 id 가 목록에 없다(다른 기기에서 지웠고 스냅숏이 낡았다). */
        data object NotFound : Outcome

        /** 파일에는 저장했고 서버에는 못 보냈다(앱이 다음에 올린다). */
        data class SavedLocally(val reason: SkipReason) : Outcome

        data object Synced : Outcome
    }

    sealed interface SkipReason {
        /** 토큰이 없거나 60초 안에 만료된다 — 갱신하지 않고 앱에 맡긴다. */
        data object TokenUnusable : SkipReason
        data object ServerMissing : SkipReason
        data object Failed : SkipReason
        data class Refused(val status: String?) : SkipReason
    }

    private val UUID_RE = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

    suspend fun run(todoID: String, shared: WidgetSharedData, nowSeconds: () -> Double, sync: Sync): Outcome {
        val path = shared.todoFilePath ?: return Outcome.SignedOut
        if (!UUID_RE.matches(todoID)) return Outcome.NotFound
        val id = todoID.lowercase()

        // 1. 조정 구간 안에서 뒤집고, 보낼 것 전부를 한 요청에 싣는다.
        var outgoing: TodoSyncOutgoing? = null
        var isDone: Boolean? = null
        NowTodoFileAccess.coordinated(path) {
            val list = TodoListStore(path, shared.files, nowSeconds)
            if (list.items.none { it.id == id && it.deletedAt == null }) return@coordinated
            list.toggleDone(id)
            isDone = list.items.firstOrNull { it.id == id }?.isDone
            val pending = list.pendingIDs.sortedBy { it.uppercase() }
            outgoing = list.makeSyncRequest(pending.take(TodoSyncRules.batchLimit))
        }
        val done = isDone ?: return Outcome.NotFound
        val request = outgoing ?: return Outcome.NotFound

        // 2. 스냅숏의 그 줄만.
        shared.snapshot.patchTodo(id, done)

        // 3. 토큰 갱신 없이, 쓸 수 있는 토큰이 있을 때만 한 번.
        val token = shared.usableAccessToken(nowSeconds()) ?: return Outcome.SavedLocally(SkipReason.TokenUnusable)
        val response = try {
            sync.sync(token, request.request)
        } catch (error: Throwable) {
            if (error is CancellationException) throw error
            return Outcome.SavedLocally(if (isMissingDeviceFunction(error)) SkipReason.ServerMissing else SkipReason.Failed)
        }
        val result = response.mergeableResult() ?: return Outcome.SavedLocally(SkipReason.Refused(response.status))

        // 4. 그 순간의 파일에 병합(새로 연 목록의 세대 0 = 보낼 때의 세대 0 — 병합 문은 코어 applySync 하나).
        NowTodoFileAccess.coordinated(path) {
            TodoListStore(path, shared.files, nowSeconds).applySync(result, request)
        }
        return Outcome.Synced
    }

    /**
     * 프로덕션 전송: 서비스의 `todo_sync` **한 번**(세션 재시도 문 `withSessionRetry` 를 지나지 않는다 — 401 이어도 갱신하지 않는다).
     * 전선 두 벌(core/wire ↔ core/rules) 잇기는 NowTodoSupport 와 같은 칸 옮김이다(c-fold 후보 — 두 벌 위험 보고).
     */
    fun serviceSync(service: SupabaseWorkService): Sync = Sync { token, request ->
        service.todoSync(token, request.toWire()).toRules()
    }

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
}
