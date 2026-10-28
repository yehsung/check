// 원본: Sources/CheckCore/SessionRefreshCoordinator.swift @ 1b8260d
package com.yehsung.aingcheck.core.session.refresh

import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async

/**
 * 세션 갱신의 **단일 주체**(C§4 #4 · Swift `SessionRefreshCoordinator`). refresh token 회전을 부르는 곳이 둘 이상이면 GoTrue 의
 * reuse-detection 이 한쪽을 무효로 만들고, 그 결과가 **근무 중 강제 로그아웃**이다. 프로세스에 하나 — 세션 스토어가 쥔다.
 *
 * 설계상 중요한 두 가지(Swift 그대로)
 * ① **refresh token 을 인자로 받지 않는다.** 호출 시점에 [refresh] 의 `tokenProvider` 로 읽는다. 인자로 받으면 '동시 호출'은 막아도
 *    '낡은 토큰의 순차 재사용'을 못 막는다(앞선 갱신이 끝난 뒤 도착한 두 번째 호출이 이미 회전된 옛 토큰을 들고 온다).
 * ② **결과를 스토어에 쓰는 책임도 여기 하나다**(`apply` 는 성공 때 정확히 한 번). 두 주체가 각자 쓰면 늦게 끝난 쪽이 낡은 토큰으로 되돌린다.
 *
 * Kotlin 몫
 * - 합류할 갱신은 [scope] 에 띄운 [Deferred] 다(Swift 의 구조 밖 `Task` 자리) — 기다리던 호출이 취소돼도 갱신 자체는 끝까지 가고
 *   합류한 다른 호출이 그 결과를 받는다. 갱신을 **띄운** 호출이 취소돼도 슬롯은 갱신이 끝날 때까지 남는다([refresh] 의 catch).
 * - **한 디스패처 규약**(Swift `@MainActor` 자리): 이 객체와 [scope] 는 세션 스토어의 디스패처(앱 = 메인 하나, 시험 = runTest 한 줄)에서만
 *   움직인다. 슬롯 확인·생성 사이에 중단점이 없으므로 그 한 줄 위에서 원자적이다. 잠금을 두지 않는 것은 [invalidate] 가 로그아웃의
 *   **동기** 정리 순서(세대 올리기 → 조정자 끊기 → 로컬 비우기, C§4 #7) 한가운데에서 불리기 때문이다.
 */
class SessionRefreshCoordinator(private val scope: CoroutineScope) {
    /** 진행 중인 갱신. 있으면 새로 만들지 않고 그 결과를 함께 기다린다(합류). */
    private var inFlight: Deferred<SupabaseSession>? = null

    /** 그 갱신이 속한 세션 세대. 로그아웃·계정 전환으로 세대가 바뀌면 합류하지 않는다(앞 계정의 결과를 새 계정에 쓰지 않게). */
    private var inFlightGeneration = -1

    /**
     * 이 조정자를 **실제로 통과한** 갱신 횟수(성공만). 이 수가 늘지 않는데 세션이 갱신됐다면 누군가 조정자를 우회한 것이다 —
     * 그게 곧 회전 경합의 조건이다(갱신 주체가 둘이 되기 전까지는 증상이 없다).
     */
    var completedRefreshCount: Int = 0
        private set

    /** 진행 중인 갱신이 있는가(진단·시험). */
    val hasInFlight: Boolean get() = inFlight != null

    /**
     * 갱신을 1회로 접는다. 같은 세대의 동시 호출은 전부 같은 [Deferred] 를 기다린다.
     *
     * @param generation 호출 시점의 세션 세대.
     * @param tokenProvider **호출 시점에** refresh token 을 읽는다(위 ①). null 이면 [SupabaseWorkServiceError.SessionExpired].
     * @param refresh 실제 갱신(서비스 호출 — 주입이라 시험이 요청 수를 센다).
     * @param apply 결과를 스토어에 반영(위 ②). 성공 때 **정확히 한 번**.
     */
    suspend fun refresh(
        generation: Int,
        tokenProvider: () -> String?,
        refresh: suspend (String) -> SupabaseSession,
        apply: (SupabaseSession) -> Unit,
    ): SupabaseSession {
        val joined = inFlight
        if (joined != null && inFlightGeneration == generation) {
            return joined.await()
        }
        val token = tokenProvider() ?: throw SupabaseWorkServiceError.SessionExpired
        val task = scope.async {
            val session = refresh(token)
            apply(session)
            completedRefreshCount += 1
            session
        }
        inFlight = task
        inFlightGeneration = generation
        // INV-SessionRefreshCoordinator-af534e47 이식: 슬롯은 스코프 끝(finally·defer)에 맡기지 않고 **성공·실패 두 갈래에서 명시적으로**,
        //   그것도 '지금 슬롯이 이 갱신일 때만' 비운다. 스코프 끝에 맡기면 기다리는 동안 합류한 호출이 끝나도 슬롯이 안 비고, 빠져나가는
        //   순서에 따라 성공한 갱신의 슬롯을 실패한 호출이 지우는 창이 생긴다.
        try {
            val session = task.await()
            clearIfCurrent(task)
            return session
        } catch (error: Throwable) {
            // 실패 갈래는 둘이다. 갱신 자체가 끝났으면(실패·취소) 지금 비운다. 그런데 **갱신을 띄운 이 호출만** 취소됐으면(화면 이탈 =
            //   viewModelScope 취소) 갱신은 아직 떠 있다. Swift `try await task.value` 는 부른 쪽이 취소돼도 Task 가 끝날 때까지 돌아오지
            //   않으므로 슬롯이 갱신 끝까지 남는다. 여기서 바로 비우면 같은 세대의 다음 호출(실시간 강제 갱신·다른 스토어의 401)이 아직 회전
            //   전인 refresh token 으로 두 번째 grant 를 보낸다. 갱신 주체가 둘이 되는 것이다(C§4 #4 — 재사용 감지 → 강제 로그아웃).
            //   그래서 그 갈래는 갱신이 **끝나는 순간에** 비운다(완료 고리는 [scope] 의 한 디스패처에서 돈다 — 위 규약).
            if (task.isCompleted) clearIfCurrent(task) else task.invokeOnCompletion { clearIfCurrent(task) }
            throw error
        }
    }

    /**
     * 로그아웃·계정 전환 때 부른다. 진행 중 갱신의 결과가 새 세션에 합류하지 않게 슬롯을 끊는다. 갱신 자체는 취소하지 않는다 —
     * 서버 쪽 회전은 이미 일어났을 수 있고, 중요한 것은 '그 결과를 쓰지 않는 것'이다(스토어의 apply 가 세대로 한 번 더 거른다).
     */
    fun invalidate() {
        inFlight = null
        inFlightGeneration = -1
    }

    private fun clearIfCurrent(task: Deferred<SupabaseSession>) {
        if (inFlight === task) {
            inFlight = null
            inFlightGeneration = -1
        }
    }
}
