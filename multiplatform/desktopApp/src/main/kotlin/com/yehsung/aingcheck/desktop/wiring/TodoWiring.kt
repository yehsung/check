// 원본: Sources/check/CheckApp.swift:260-290(wireTodoBoard — 계정별 목록 파일 · TodoSyncWiring.live) ·
//       Sources/check/TodoSyncCoordinator.swift:42-93(start · accountMayHaveChanged · 깨어남) ·
//       Sources/check/WorkTimerStoreTodoSync.swift:16-85(전송 · 조립 함수) @ 1b8260d
// 안드로이드 같은 자리: core/stores …/now/NowStore.kt:160-205(TodoListStore · TodoSync · NowTodoSyncTransport 조립).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.now.NowTodoSyncTransport
import com.yehsung.aingcheck.core.stores.now.todo.TodoListStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoSync
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncCoroutineScheduler
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncReason
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncScheduler
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncTransport
import com.yehsung.aingcheck.desktop.todo.DesktopTodoFileSystem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import java.nio.file.Path

/**
 * 할 일 배선의 재료. 앱 조립(AppGraph)이 채우고 시험은 가짜를 넣는다 — **기본값으로 실제 폴더·OS 사건에 붙지 않는다**
 * (맥 WorkTimerStoreTodoSync.swift:79-85: 기본값을 두면 시험이 실제 할 일 파일을 열어 아무도 조립을 시험하지 않았다).
 */
class TodoWiringDeps(
    /** 앱 데이터 폴더(Windows `%LOCALAPPDATA%\aing-check` — AppPaths.dataDir). 목록 파일은 그 아래 `todos.<계정>.json`. */
    val dataDir: Path,
    /** `todo_sync` 전송. 앱은 [TodoWiring.sessionTransport]. */
    val transport: TodoSyncTransport,
    /** 지금 세션 사용자(관찰 — 앱은 `sessionStore.sessionFlow.map { it?.userID }`). 계정 전환·로그아웃을 이 흐름으로 알아챈다. */
    val accountIds: Flow<String?>,
    /** 지금 세션 사용자(읽기 — 앱은 `{ sessionStore.session?.userID }`). 목록을 처음 열 파일을 정한다(맥 CheckApp.swift:279). */
    val currentUserID: () -> String?,
    /** 지금(1970 기준 초) — 엔진의 정리(90일)·함수 없음 5분 판정. */
    val clock: () -> Double,
    /** 파일 자리. 손상 격리 보고를 받으려면 [DesktopTodoFileSystem.onQuarantine] 를 채워 넣는다. */
    val files: DesktopTodoFileSystem = DesktopTodoFileSystem(),
    /** 깨어남(맥 NSWorkspace.didWakeNotification). null 이면 구독하지 않는다. */
    val power: PowerEvents? = null,
    /** 깨어난 뒤 망 준비를 기다리는 문(근무 배선과 같은 AppSeams.networkReadiness). null 이면 바로 맞춘다(맥과 같음). */
    val wakeNetworkReady: (suspend () -> Unit)? = null,
    /**
     * 파일을 갈아 끼우기 **직전**에 동기로 부른다(맥 TodoSyncCoordinator.swift:74-76 `board?.resetForAccountSwitch()` — 되돌리기 창의 삭제는
     * 앞 계정 파일에 확정하고 편집·초안은 버린다). 앱은 보드 컨트롤러의 resetForAccountSwitch. 같은 UI 줄기에서 불린다.
     */
    val beforeAccountSwitch: () -> Unit = {},
    /** 디바운스·주기 타이머(시험이 바꿔 끼울 수 있다). 기본은 코어 [TodoSyncCoroutineScheduler](이 배선의 스코프 위 delay). */
    val scheduler: ((CoroutineScope) -> TodoSyncScheduler)? = null,
)

/**
 * 데스크톱 할 일 목록 + 서버 동기화 한 벌(맥 `wireTodoBoard` + `TodoSyncCoordinator` 의 몫). 만드는 자리가 둘이면 두 엔진이 같은 파일을
 * 번갈아 써 한쪽 pending 이 지워진다 — 앱 조립에서 **한 번만** 만든다.
 *
 * 맞추는 때(맥 명세 A4-5): 실행·로그인 직후([start]·계정 흐름) · 보드 열 때([onBoardOpened]) · 고친 뒤 1.5초(목록의 onLocalChange) ·
 * 로그인 중 5분마다(엔진 주기) · 깨어날 때([power] WAKE). 로그아웃 상태(`todos.local.json`)는 맞추지 않는다(엔진: userID == null → 무동작).
 *
 * 줄기: [scope] 는 UI 한 줄기(앱 = Swing EDT, 시험 = 시험 디스패처). 목록·엔진은 이 줄기에서만 만진다 — OS 사건(깨어남)은 이 줄기로 옮겨 부른다.
 * [scope] 아래에 자기 자식 줄기를 두고 [close] 가 그것만 거둔다(타이머·진행 중 요청까지).
 */
class TodoWiring(private val deps: TodoWiringDeps, scope: CoroutineScope) {
    private val job = SupervisorJob(scope.coroutineContext[Job])
    private val own = CoroutineScope(scope.coroutineContext + job)

    /** 할 일 목록(오버레이 보드가 그린다). 처음엔 **지금 세션 계정 파일**로 연다(맥 CheckApp.swift:279 defaultURL(store.session?.userID)). */
    val list: TodoListStore = TodoListStore(pathFor(deps.currentUserID()), deps.files, deps.clock)

    /** 동기화 엔진(진단·시험 판정 지점: lastOutcome · transportCallCount · runTask). */
    val sync: TodoSync = TodoSync(
        list = list,
        transport = deps.transport,
        scheduler = deps.scheduler?.invoke(own) ?: TodoSyncCoroutineScheduler(own),
        scope = own,
        clock = deps.clock,
    )

    private var started = false
    private var closed = false
    private var lastUserID: String? = null
    private var accountJob: Job? = null
    private var wakeRegistration: Registration? = null

    val isStarted: Boolean get() = started && !closed

    /** 지금 동기화 대상 계정(null = 로그아웃 — 맞추지 않음). */
    val activeUserID: String? get() = sync.userID

    /**
     * 배선을 건다(멱등 — 맥 TodoSyncCoordinator.start). 목록을 만든 뒤 세션이 바뀌었으면(실행 직후 복구·로그아웃) 그 계정 파일로 바꿔 열고,
     * 아니면 지금 파일 그대로 맞추기 시작한다. 그다음부터 계정 흐름을 본다.
     */
    fun start() {
        if (started || closed) return
        started = true
        list.onLocalChange = { sync.noteLocalChange() }
        wakeRegistration = deps.power?.addListener { event ->
            if (event != PowerEvent.WAKE) return@addListener
            // OS 줄기에서 온다 — UI 줄기로 옮겨 부른다. 망 준비를 기다리는 동안 닫히면 그대로 취소된다.
            own.launch {
                deps.wakeNetworkReady?.invoke()
                requestSync(TodoSyncReason.wake)
            }
        }
        val current = normalized(deps.currentUserID())
        lastUserID = current
        val expected = pathFor(current)
        if (list.filePath != expected) {
            deps.beforeAccountSwitch()
            sync.switchAccount(current, expected)
        } else {
            sync.activate(current, TodoSyncReason.launch)
        }
        accountJob = own.launch { deps.accountIds.collect { accountMayHaveChanged(it) } }
    }

    /**
     * 세션 사용자가 바뀌었는지 보고, 바뀌었으면 보드 입력 상태를 정리하고 파일·동기화 대상을 바꾼다(맥 accountMayHaveChanged).
     * 로그아웃(null)이면 `todos.local.json` 으로 바꾸고 타이머를 전부 거둔다 — 이후 서버 요청 0.
     */
    fun accountMayHaveChanged(userID: String?) {
        if (!started || closed) return
        val current = normalized(userID)
        if (current == lastUserID) return
        lastUserID = current
        deps.beforeAccountSwitch()
        sync.switchAccount(current, pathFor(current))
    }

    /** 맞춰 달라(깨어남·보드 열기·설정 등 바깥 입구). 시작 전·닫힌 뒤·로그아웃이면 아무것도 안 한다. */
    fun requestSync(reason: TodoSyncReason) {
        if (!started || closed) return
        sync.requestSync(reason)
    }

    /** 보드를 열었다(맥 v0.3.30 — 보드를 열 때 서버와 맞춘다). OverlaySurfacesConfig.onBoardOpened 에 꽂는다. */
    fun onBoardOpened() = requestSync(TodoSyncReason.boardOpened)

    /** 내린다(종료 순서). 계정 흐름·깨어남 구독·디바운스·주기 타이머·진행 중 요청을 거둔다. 파일은 고칠 때마다 이미 쓰였다. 멱등. */
    fun close() {
        if (closed) return
        closed = true
        accountJob?.cancel()
        accountJob = null
        wakeRegistration?.close()
        wakeRegistration = null
        list.onLocalChange = null
        job.cancel()
    }

    private fun pathFor(userID: String?): String = DesktopTodoFileSystem.path(deps.dataDir, normalized(userID))

    private fun normalized(userID: String?): String? = if (userID.isNullOrEmpty()) null else userID

    companion object {
        /** 종료 순서 이름(AppWirings.shutdownSteps 에 넣을 때). */
        const val STEP_TODO_STOP = "todo.stop"

        /**
         * 프로덕션 전송 = 안드로이드와 **같은 한 벌**(core NowTodoSyncTransport — 맥 WorkTimerStoreTodoSyncTransport 의 네 걸음:
         * 세션 가드 → 세대 캡처 → withSessionRetry(`{"status":"unauthorized"}` 도 SessionExpired 로 접어 한 번 갱신) → 세대 가드,
         * PGRST202·본문 없는 404 → functionMissing, 다른 계정 → accountMismatch). 데스크톱에 다시 적으면 규칙이 두 곳이 된다.
         */
        fun sessionTransport(context: SessionContext): TodoSyncTransport = NowTodoSyncTransport(context)
    }
}
