// 원본: Sources/CheckCore/TodoSync.swift:244-482(전송 계층 · 시계·타이머 · 엔진) @ 1b8260d
package com.yehsung.aingcheck.core.stores.now.todo

import com.yehsung.aingcheck.core.rules.todo.TodoSyncRequest
import com.yehsung.aingcheck.core.rules.todo.TodoSyncResponse
import com.yehsung.aingcheck.core.rules.todo.TodoSyncRules
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// ---------------------------------------------------------------- 전송 계층(주입)

/** 전송이 던지는 분류(Swift `TodoSyncTransportError`). 이 밖의 오류는 전부 "일시 실패"(pending 유지 · 다음 기회에 재시도)로 읽는다. */
class TodoSyncTransportException(val kind: Kind) : Exception(kind.name) {
    enum class Kind {
        /** 서버에 `todo_sync` 가 아직 없다(HTTP 404 / PGRST202). 조용히 멈추고 pending 을 둔다. */
        functionMissing,

        /** 지금 세션이 요청한 계정이 아니다(전환 중). 보내지 않는다 — 앞 계정의 할 일이 새 계정에 올라가면 안 된다. */
        accountMismatch,
    }
}

/**
 * `todo_sync` 를 부르는 방법(Swift `TodoSyncTransport`). **여기를 갈아 끼우면 엔진은 그대로다** — 프로덕션은 PostgREST(세션 갱신 포함 —
 * `NowTodoSyncTransport`), 시험은 가짜.
 * 규약: `userID` 계정으로만 보낸다(지금 세션이 다르면 accountMismatch) · `{"status":"unauthorized"}` 는 세션을 갱신해 다시 시도 · 함수가 없으면 functionMissing.
 */
fun interface TodoSyncTransport {
    suspend fun todoSync(userID: String, request: TodoSyncRequest): TodoSyncResponse
}

// ---------------------------------------------------------------- 시계·타이머(주입)

/** 취소 가능한 예약 하나. */
fun interface TodoSyncCancellable {
    fun cancel()
}

/** 디바운스·주기 타이머. 시험은 손으로 시간을 미는 구현을 꽂는다(실제 1.5초·5분을 기다리지 않는다). */
fun interface TodoSyncScheduler {
    fun schedule(afterSeconds: Double, action: () -> Unit): TodoSyncCancellable
}

/** 프로덕션 타이머(코루틴 delay — Swift `TodoSyncTaskScheduler`). 취소한 예약은 끝내 쏘지 않는다. */
class TodoSyncCoroutineScheduler(private val scope: CoroutineScope) : TodoSyncScheduler {
    override fun schedule(afterSeconds: Double, action: () -> Unit): TodoSyncCancellable {
        val job = scope.launch {
            delay((afterSeconds * 1000).toLong())
            action()
        }
        return TodoSyncCancellable { job.cancel() }
    }
}

// ---------------------------------------------------------------- 엔진

/** 왜 맞추는가(진단·스로틀 판정용). */
enum class TodoSyncReason { launch, login, boardOpened, edit, periodic, wake }

/** 마지막 시도의 결말(진단 · 시험 판정 지점). 사용자 화면에는 띄우지 않는다 — 동기화는 조용한 기능이다. */
sealed interface TodoSyncOutcome {
    data object synced : TodoSyncOutcome

    /** 서버에 함수가 아직 없다(404/PGRST202). pending 유지. */
    data object serverMissing : TodoSyncOutcome

    /** 네트워크·세션·디코드 실패. pending 유지. */
    data object failed : TodoSyncOutcome

    /** 서버가 ok 가 아닌 응답을 줬다(unauthorized·invalid·too_many 등). pending 유지. */
    data class refused(val status: String?) : TodoSyncOutcome

    /** 응답이 왔지만 그 사이 계정(파일)이 바뀌어 버렸다. */
    data object discardedStale : TodoSyncOutcome
}

/**
 * 할 일 동기화 엔진(Swift `TodoSync`). **한 번에 하나만 돈다** — 도는 중에 또 부르면 끝난 뒤 한 번 더 돈다(몇 번을 불러도 한 번).
 * 계정 전환 뒤 늦은 응답을 버리는 세대 판정은 스토어의 [TodoListStore.applySync] 한 곳에만 둔다(두 곳에 두면 한쪽을 지워도 초록이다).
 */
class TodoSync(
    val list: TodoListStore,
    private val transport: TodoSyncTransport,
    private val scheduler: TodoSyncScheduler,
    private val scope: CoroutineScope,
    /** 지금(1970 기준 초). */
    private val clock: () -> Double,
) {
    /** 동기화 대상 계정. null = 로그아웃(`todos.local.json`) — 맞추지 않는다. */
    var userID: String? = null
        private set
    var isRunning: Boolean = false
        private set
    var lastOutcome: TodoSyncOutcome? = null
        private set

    /** 전송을 실제로 부른 횟수(진단). */
    var transportCallCount: Int = 0
        private set

    /** 지금 도는 작업(시험이 끝나기를 기다리는 문). */
    var runTask: Job? = null
        private set

    private var rerunRequested = false
    private var debounce: TodoSyncCancellable? = null
    private var periodic: TodoSyncCancellable? = null
    private var serverMissingAt: Double? = null

    /** 지금 파일 그대로 이 계정으로 맞추기 시작한다(실행 직후 — 파일은 이미 그 계정 것으로 열려 있다). */
    fun activate(userID: String?, reason: TodoSyncReason = TodoSyncReason.launch) {
        this.userID = normalizedUserID(userID)
        restartTimers()
        requestSync(reason)
    }

    /** 계정이 바뀌었다. 예약을 전부 거두고 → 파일을 바꾸고(세대가 올라 진행 중 응답은 버려진다) → 새 계정이면 곧바로 맞춘다. */
    fun switchAccount(userID: String?, filePath: String) {
        debounce?.cancel()
        debounce = null
        rerunRequested = false
        serverMissingAt = null
        this.userID = normalizedUserID(userID)
        list.switchFile(filePath)
        restartTimers()
        requestSync(TodoSyncReason.login)
    }

    /** 사용자가 고쳤다 — 1.5초 디바운스. */
    fun noteLocalChange() {
        if (userID == null) return
        debounce?.cancel()
        debounce = scheduler.schedule(TodoSyncRules.debounceSeconds) {
            debounce = null
            requestSync(TodoSyncReason.edit)
        }
    }

    /** 맞춰 달라. 로그아웃이면 아무것도 안 한다. 도는 중이면 끝난 뒤 한 번 더. 함수 없음을 본 뒤 5분은 고칠 때·보드 열 때 다시 치지 않는다. */
    fun requestSync(reason: TodoSyncReason) {
        if (userID == null) return
        val missingAt = serverMissingAt
        if ((reason == TodoSyncReason.edit || reason == TodoSyncReason.boardOpened) && missingAt != null &&
            clock() - missingAt < TodoSyncRules.serverMissingCooldownSeconds
        ) {
            return
        }
        if (isRunning) {
            rerunRequested = true
            return
        }
        isRunning = true
        val job = scope.launch(start = CoroutineStart.LAZY) { drain() }
        runTask = job
        job.start()
    }

    private suspend fun drain() {
        try {
            do {
                rerunRequested = false
                runOnce()
            } while (rerunRequested && userID != null)
        } finally {
            isRunning = false
        }
    }

    private fun restartTimers() {
        periodic?.cancel()
        periodic = null
        if (userID == null) {
            debounce?.cancel()
            debounce = null
            return
        }
        armPeriodic()
    }

    private fun armPeriodic() {
        periodic = scheduler.schedule(TodoSyncRules.periodicSeconds) {
            if (userID != null) {
                requestSync(TodoSyncReason.periodic)
                armPeriodic()
            }
        }
    }

    /**
     * 한 바퀴: pending 을 500개씩 나눠(없으면 빈 요청 하나 — 받기만) 차례로 보내고 합친다. 어느 요청이든 실패하면 **거기서 멈춘다**
     * (pending 은 파일에 그대로 남아 다음 기회에 다시 실린다). 계정 전환은 응답을 기다리는 동안에만 끼어들 수 있다 — 그 경우 [TodoListStore.applySync]
     * 가 세대 불일치로 false 를 돌려주고 여기서 멈추므로, 남은 묶음을 새 계정 파일에서 찍어 앞 계정으로 보내는 일은 없다.
     */
    private suspend fun runOnce() {
        val userID = userID ?: return
        for (batch in TodoSyncRules.batches(list.pendingIDs)) {
            val outgoing = list.makeSyncRequest(batch)
            transportCallCount += 1
            val response = try {
                transport.todoSync(userID, outgoing.request)
            } catch (error: TodoSyncTransportException) {
                if (error.kind == TodoSyncTransportException.Kind.functionMissing) {
                    serverMissingAt = clock()
                    lastOutcome = TodoSyncOutcome.serverMissing
                } else {
                    lastOutcome = TodoSyncOutcome.failed
                }
                return
            } catch (error: CancellationException) {
                // 이 작업이 취소됐으면(스코프 종료) 그대로 올려 보낸다. 요청만 취소로 끝났으면 일시 실패다(Swift URLError.cancelled).
                if (runTask?.isCancelled == true) throw error
                lastOutcome = TodoSyncOutcome.failed
                return
            } catch (error: Throwable) {
                lastOutcome = TodoSyncOutcome.failed
                return
            }
            val result = response.mergeableResult()
            if (result == null) {
                lastOutcome = TodoSyncOutcome.refused(response.status)
                return
            }
            if (!list.applySync(result, outgoing)) {
                lastOutcome = TodoSyncOutcome.discardedStale
                return
            }
        }
        serverMissingAt = null
        lastOutcome = TodoSyncOutcome.synced
    }

    private fun normalizedUserID(userID: String?): String? = if (userID.isNullOrEmpty()) null else userID

    companion object {
        /** 고친 뒤 이만큼 조용하면 보낸다. */
        const val debounceSeconds: Double = TodoSyncRules.debounceSeconds

        /** 로그인 중 이 간격으로 맞춘다(다른 기기의 변경을 받으려고). */
        const val periodicSeconds: Double = TodoSyncRules.periodicSeconds
    }
}
