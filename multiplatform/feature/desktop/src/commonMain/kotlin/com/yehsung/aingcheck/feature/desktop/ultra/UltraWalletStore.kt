// 원본: Sources/check/WorkTimerStorePoke.swift 240-365(울트라 재화 지갑) · Sources/check/WorkTimerStore.swift 4069-4087(로그아웃 비우기) @ a90d8623
// 데스크톱 울트라 지갑(W2-g4). 잔량·미션·스트릭은 **서버가 준 값만** 적는다 — 클라는 잔량을 만들지 않는다(조정자 메모).
package com.yehsung.aingcheck.feature.desktop.ultra

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraChargedSink
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraWalletTrigger
import com.yehsung.aingcheck.feature.desktop.ultra.net.MissionProgress
import com.yehsung.aingcheck.feature.desktop.ultra.net.UltraWalletResponse
import com.yehsung.aingcheck.feature.desktop.ultra.net.syncUltraWallet
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.LapGrant
import com.yehsung.aingcheck.feature.desktop.work.LapWalletJudgment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** 화면이 읽는 지갑 값(Swift `ultraBalance`…`missionNotice`). 전부 서버 응답에서 온다. */
data class UltraWalletState(
    /** null = 아직 모른다(배지 "—"). 실패해도 지우지 않는다(U2). */
    val balance: Long? = null,
    val balanceCap: Long? = null,
    val unlimited: Boolean = false,
    /** 진단 깃발 — 실패해도 잔량은 그대로다. invalid(비로그인·프로필 없음)는 실패가 아니다. */
    val failed: Boolean = false,
    val missions: List<MissionProgress> = emptyList(),
    val missionsLoaded: Boolean = false,
    val streakDays: Int = 0,
    val streakIncludesToday: Boolean = false,
    /** granted_now 를 받은 호출이 남기는 **지속 증거**(연출은 2초면 사라진다). */
    val missionNotice: String? = null,
    /** 서버가 준 3시간 목표(근무 쪽 랩 계산이 읽는다). */
    val missionTargetSeconds: Long? = null,
)

/**
 * U4 — 지갑 박자에 얹히는 다른 조회(주간 근무 보상 · 도전 미션). **새 타이머 없이 같은 박자**에 묻는다.
 * Swift `refreshWeeklyWork(.walletCadence)` + `achievementsReason(forWallet:)`(panelOpen·periodic·signIn 만, missionCandidate 는 아님) —
 * 어느 이유에 무엇을 얹을지는 받는 쪽(주간·미션 갈래)이 정한다. 여기서는 **실제로 발사한 이유**만 넘긴다.
 */
fun interface UltraWalletCadence {
    fun onWalletCadence(reason: UltraSyncReason)

    companion object {
        val NONE: UltraWalletCadence = UltraWalletCadence { }
    }
}

/**
 * [UltraWalletTrigger] 구현 — 호출 지점 넷(★U1): signIn(로그인·저장 세션 활성화) · panelOpen(찌르기·울트라·미션 화면) ·
 * missionCandidate(랩 임계 · 울트라 발사 성공) · periodic(폴링 박자, 근무 중 300초 스로틀).
 *
 * - [sync] 는 결과를 기다리지 않는다(Swift `Task { await performSyncUltraWallet }`). 화면은 [state] 를 따라온다.
 * - Periodic 은 **여기서** 거른다: 근무 중(`startedAt != null`)이 아니면 0건, 직전 발사에서 300초 안이면 0건.
 *   폴링 박자(W2-g2)는 매 tick `sync(Periodic)` 을 불러도 된다.
 * - 스탬프는 **발사 시점**에 찍는다(성공에만 찍으면 서버가 죽은 동안 매 tick 이 재시도한다). 이유를 가리지 않는다 —
 *   signIn·panelOpen 발사도 periodic 스로틀을 300초 미룬다(Swift 와 같다).
 * - 스레드: UI 스레드 하나(Swift `@MainActor`). [scope] 는 그 디스패처여야 한다.
 */
class UltraWalletStore(
    private val host: SessionHost,
    private val workState: DesktopWorkState,
    /** 랩 판정(W2-g6 구현 — 근무 갈래). 응답을 [LapGrant] 로 옮겨 부른다. */
    private val lapJudgment: LapWalletJudgment,
    /** ★U3 연출 — granted_now 일 때만. */
    private val chargedSink: UltraChargedSink,
    private val scope: CoroutineScope,
    private val clock: () -> SwiftDate,
    private val cadence: UltraWalletCadence = UltraWalletCadence.NONE,
    /** 시작 값(시험·골든의 prior). 앱은 비워 둔다 — 서버가 말하기 전엔 모른다. */
    initial: UltraWalletState = UltraWalletState(),
) : UltraWalletTrigger {
    private val _state = MutableStateFlow(initial)
    val state: StateFlow<UltraWalletState> = _state.asStateFlow()

    /** 마지막 **발사** 시각(Swift `lastUltraWalletSyncAt`). 실패해도 남는다. */
    var lastSyncAt: SwiftDate? = null
        private set

    override fun sync(reason: UltraSyncReason) {
        if (reason == UltraSyncReason.Periodic && !isPeriodicDue(clock())) return
        fire(reason)
    }

    /** Swift `syncUltraWalletIfDue(now:)` 의 판정(부수효과 없음). */
    fun isPeriodicDue(now: SwiftDate): Boolean {
        if (workState.snapshot.value.startedAt == null) return false
        val last = lastSyncAt ?: return true
        return now.timeIntervalSince(last) >= THROTTLE_SECONDS
    }

    private fun fire(reason: UltraSyncReason): Job? {
        val job = if (host.session != null) {
            val generation = host.sessionGeneration
            lastSyncAt = clock()
            scope.launch { perform(generation) }
        } else {
            null
        }
        cadence.onWalletCadence(reason)
        return job
    }

    private suspend fun perform(generation: Int) {
        val response = try {
            host.withSessionRetry { s -> host.service.syncUltraWallet(s.accessToken) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (host.classifyAuthError(e) == AuthErrorDisposition.cancelled) return
            if (generation != host.sessionGeneration) return
            // U2 실패는 **잔량을 지우지 않는다** — 진단 깃발만.
            _state.update { it.copy(failed = true) }
            return
        }
        if (generation != host.sessionGeneration) return
        apply(response)
    }

    /** 응답 반영(순수 상태 전이 — 네트워크 없음). Swift `applyUltraWallet`. 골든 `desktop-ultra/wallet-apply` 가 이 함수를 잰다. */
    fun apply(response: UltraWalletResponse) {
        if (!response.isOK) {
            // status invalid = 비로그인/프로필 없음. **서버 오류가 아니다** → failed=false(U2).
            _state.update { it.copy(failed = false) }
            return
        }
        val work3h = MissionProgress.Kind.TODAY_THREE_HOURS.raw
        val target = response.missions.firstOrNull { it.key == work3h }?.targetSeconds?.takeIf { it > 0 }
        _state.update { s ->
            s.copy(
                failed = false,
                balance = maxOf(0L, response.balance),
                balanceCap = response.balanceCap ?: s.balanceCap,
                // 무제한은 서버 값 그대로. null 은 무제한 아님(U3).
                unlimited = response.isUnlimited,
                missions = MissionProgress.rows(response),
                missionsLoaded = true,
                streakDays = response.streakDays,
                streakIncludesToday = response.streakIncludesToday,
                missionTargetSeconds = target ?: s.missionTargetSeconds,
            )
        }
        // ★U3 granted_now 가 **유일한** 연출 트리거다(claimed 는 5분마다 참이라 트리거가 아니다).
        if (response.missions.none { it.grantedNow }) return
        val outcome = lapJudgment.judge(response.missions.map { LapGrant(it.grantedNow, it.lapsGranted) }, response.streakDays)
        if (!outcome.celebrate) return
        _state.update { it.copy(missionNotice = missionNotice(outcome.lapsToday, response.rubyMissionGrant)) }
        chargedSink.onUltraCharged()
    }

    /** 잔량 대입(음수는 0). 지갑 응답 전용 — 구매 응답은 [setBalanceFromPurchase]. */
    fun applyBalance(value: Long) {
        _state.update { it.copy(balance = maxOf(0L, value)) }
    }

    /** buy_ultra 응답의 ultra_balance(Swift `self.ultraBalance = ultra` — 음수 접기 없음, 서버값 그대로 U5). */
    fun setBalanceFromPurchase(value: Long) {
        _state.update { it.copy(balance = value) }
    }

    /** 미션 안내를 화면이 지운다(Swift `missionNotice = nil`). */
    fun clearMissionNotice() {
        _state.update { it.copy(missionNotice = null) }
    }

    /** 로그아웃(Swift WorkTimerStore.swift 4069-4087). */
    fun reset() {
        _state.value = UltraWalletState()
        lastSyncAt = null
    }

    companion object {
        /** `.periodic` 스로틀(초). 15초 폴링에 그냥 얹으면 사용자당 하루 수천 왕복이 된다. */
        const val THROTTLE_SECONDS: Double = 300.0

        /** 옛 서버(rubyMissionGrant 없음)일 때의 랩당 루비. */
        const val DEFAULT_RUBY_PER_LAP: Long = 3

        /**
         * 지속 증거 문구. lapsToday 0(랩 이전 서버)과 1 은 같은 문장이다 — "오늘 0개"는 받은 사람에게 거짓말이다.
         * 경계는 2(1·3 만 재면 `>= 3` 뮤턴트가 산다 — Swift V0239 시험 주석).
         */
        fun missionNotice(lapsToday: Int, rubyMissionGrant: Long?): String {
            val perLap = rubyMissionGrant ?: DEFAULT_RUBY_PER_LAP
            return if (lapsToday >= 2) "3시간 채웠어요 — 루비 +${perLap * lapsToday} (오늘 ${lapsToday}번)"
            else "3시간 채웠어요 — 루비 +$perLap"
        }
    }
}
