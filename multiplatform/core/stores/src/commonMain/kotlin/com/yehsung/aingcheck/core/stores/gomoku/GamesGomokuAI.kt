// 원본: Sources/CheckMobileKit/Games/GamesGomokuAI.swift:1-140(GamesGomokuAIThinker) · :139-161(GomokuPhoneMatchChrome 의 판정 몫) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.ai.GomokuAI
import com.yehsung.aingcheck.core.rules.ai.GomokuAIGame
import com.yehsung.aingcheck.core.rules.ai.GomokuAISearchLimits
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.milliseconds

// 폰 AI 오목 — **규칙·판·서버 차단은 전부 코어**(`GomokuStoreAI` · W1-b `GomokuAIGame` · `GomokuAI`)이고, 이 파일은 폰이 코어에 끼우는
// 선택기(`GamesGomokuAIThinker`)만 옮긴다. 코어 스토어의 AI 수 선택기 자리(`GomokuStore.aiMoveChooser`)에 끼우며, 폰에만 있는 수명을
// 하나 더 안다: **오목 화면이 보이고 앱이 active 일 때만 생각한다.** 화면을 떠나거나 앱이 background 로 가면 도는 탐색을 취소하고
// (엔진의 `isCancelled`), 돌아오면 **처음부터 다시** 생각한다. 떠나서 끊긴 탐색의 결과는 **버린다**(덜 생각한 수를 두지 않는다).
// 코어가 자기 작업을 취소하면(기권 뒤 새 판 · 1:1 판이 열림 · 로그아웃) 붙잡은 호출은 곧바로 풀린다 — 코어는 그 결과를 이미 버린다.
//
// `GomokuPhoneMatchChrome`(대국·결과 화면의 판 종류별 표)은 **판정 몫만** 옮겼다(판 종류 가르기 · 판돈 줄 · 대화 서랍 — 글자와 무관). 같은 표의
// 글자 몫(기권 확인 · 시계 줄 · 다시 두기 · 대기 줄 · 상대 부제 · 끝난 이유 · 상대 줄)은 전부 W2-e `GomokuPhoneText`(GamesText.swift)에서 오므로
// W2-e 병합 뒤 이 타입에 더한다(INV 표식 없음 — 보고 참조).

/**
 * 대국·결과 화면이 **판 종류**(사람 · AI)에 따라 세우는 것(Swift `GomokuPhoneMatchChrome` 의 판정 몫). 뷰는 이 표만 읽는다.
 * AI 판에서 서지 않는 것: 판돈 줄(내비 부제 · 결과 루비 변화 — 걸린 루비가 없다) · 대화 서랍(상대가 사람이 아니다 → 서랍 머리의 신고·차단 메뉴도
 * 함께 없다). 맥 AI 판(`GomokuMatchSide.isAI` 갈래)과 같은 목록이다.
 */
data class GomokuPhoneMatchChrome(val isAI: Boolean) {
    /** 판 id 머리말로 가른다(코어 서버 차단과 **같은 판정** — `GomokuAIGame.isAIMatchID`). */
    constructor(match: GomokuMatchState) : this(GomokuAIGame.isAIMatchID(match.id))

    /** 판돈 줄(내비 부제)과 결과 루비 변화. */
    val showsStake: Boolean get() = !isAI

    /** 대화 서랍(신고·차단 메뉴가 그 머리에 있다). */
    val showsChatDrawer: Boolean get() = !isAI
}

/** 폰 AI 수 선택기. 코어 `GomokuStore.aiMoveChooser` 에 [chooser] 를 끼운다. 한 스레드(메인)에서만 부른다(Swift `@MainActor`). */
class GamesGomokuAIThinker {
    /** 엔진 한 번: 판 · 둘 색 · 한도 · 취소 문 → 수. 시험이 결정적 가짜로 갈아 끼운다. */
    fun interface Engine {
        fun choose(board: GomokuBoard, color: GomokuColor, limits: GomokuAISearchLimits, isCancelled: () -> Boolean): GomokuPoint?
    }

    companion object {
        /** 폰 한도 — **맥 기본값과 같은 1.5초 · 깊이 64**. 폰 CPU 가 느리면 기다림이 길어지는 게 아니라 깊이가 얕아진다. */
        val phoneLimits: GomokuAISearchLimits = GomokuAISearchLimits(timeBudget = 1500.milliseconds, maxDepth = 64)

        /** 진짜 엔진. */
        val realEngine: Engine = Engine { board, color, limits, isCancelled ->
            GomokuAI.bestMove(board = board, toMove = color, limits = limits, isCancelled = isCancelled)
        }
    }

    var engine: Engine = realEngine
    var limits: GomokuAISearchLimits = phoneLimits
    /** 탐색을 돌리는 디스패처(Swift `Task.detached` — 메인 밖). 시험은 시험 디스패처를 넣는다. */
    var searchDispatcher: CoroutineDispatcher = Dispatchers.Default
    /** 이 판·색의 수가 아직 필요한가(코어 AI 판이 그 판에서 AI 차례로 멈춰 있는가). 필요 없으면 **다시 생각하지 않는다**. */
    var isStillNeeded: (GomokuBoard, GomokuColor) -> Boolean = { _, _ -> true }

    /** 생각해도 되는가(오목 화면이 보이고 앱이 active). 화면 수명 사건마다 [setAllowed] 로 적는다. */
    var isAllowed: Boolean = false
        private set
    /** 도는 엔진(한 번에 하나 — 코어가 AI 차례마다 선택기를 한 번 부른다). */
    private var running: Deferred<GomokuPoint?>? = null
    /** 허락을 기다리는 선택기 호출. */
    private val waiters = LinkedHashMap<Long, CompletableDeferred<Unit>>()
    private var nextWaiterID = 0L

    /** 엔진을 띄운 횟수(진단·시험 지점). */
    var searchesStarted: Int = 0
        private set
    /** 화면을 떠나거나 background 로 가서 끊은 탐색 수(진단·시험 지점). */
    var searchesInterrupted: Int = 0
        private set

    val isSearching: Boolean get() = running != null
    /** 허락을 기다리며 붙잡힌 선택기 호출 수. */
    val waitingCount: Int get() = waiters.size

    /** 코어 스토어에 끼울 선택기. */
    val chooser: GomokuAIMoveChooser get() = { board, color -> choose(board, color) }

    /** 허락을 바꾼다. 거두면 도는 엔진을 취소하고, 주면 기다리던 호출을 깨운다. */
    fun setAllowed(allowed: Boolean) {
        if (allowed == isAllowed) return
        isAllowed = allowed
        if (allowed) {
            val pending = waiters.values.toList()
            waiters.clear()
            for (gate in pending) gate.complete(Unit)
        } else {
            running?.cancel()
        }
    }

    /**
     * 선택기 한 번. 허락이 있을 때만 엔진을 띄우고, 떠나서 끊긴 탐색은 버린 뒤 돌아오면 다시 생각한다. 부른 쪽(코어의 AI 수 작업)이 취소되면
     * 취소가 그대로 올라간다 — 코어는 그 결과를 버린다(Swift 는 nil).
     */
    suspend fun choose(board: GomokuBoard, color: GomokuColor): GomokuPoint? {
        while (currentCoroutineContext().isActive) {
            if (!isStillNeeded(board, color)) return null
            if (!isAllowed) {
                waitUntilAllowed()
                continue
            }
            val engine = engine
            val limits = limits
            val outcome = coroutineScope {
                // 메인 밖에서 돈다 — 코어 기본 선택기와 같은 수법. 엔진이 보는 취소는 이 작업의 취소다.
                val search = async(searchDispatcher) {
                    val job = coroutineContext[Job]
                    engine.choose(board, color, limits) { job?.isActive == false }
                }
                running = search
                searchesStarted += 1
                try {
                    Result.success(search.await())
                } catch (cancelled: CancellationException) {
                    // 부른 쪽이 취소됐으면 그대로 올린다. 떠나서 끊긴 탐색이면(search 만 취소됨) 덜 생각한 수다 — 버린다.
                    currentCoroutineContext().ensureActiveOrThrow(cancelled)
                    Result.failure(cancelled)
                } finally {
                    if (running === search) running = null
                }
            }
            if (outcome.isSuccess) return outcome.getOrNull()
            searchesInterrupted += 1
        }
        return null
    }

    private suspend fun waitUntilAllowed() {
        if (isAllowed) return
        val id = nextWaiterID++
        val gate = CompletableDeferred<Unit>()
        waiters[id] = gate
        try {
            gate.await()
        } finally {
            waiters.remove(id)
        }
    }
}

/** 이 문맥이 살아 있으면 돌아가고, 아니면 받은 취소를 던진다. */
private fun kotlin.coroutines.CoroutineContext.ensureActiveOrThrow(cancelled: CancellationException) {
    if (!isActive) throw cancelled
}
