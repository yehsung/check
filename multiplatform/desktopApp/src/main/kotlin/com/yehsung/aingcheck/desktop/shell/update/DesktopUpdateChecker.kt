// W3-c5(shell/update) — 새 버전·서버 공지 조회 한 곳. 결과는 조정자 핀 [DesktopUpdateState] 하나로만 낸다:
// 빨간 점(c1)·배너(c2)는 `updateAvailable` 만, 공지 카드는 `notice` 만 읽는다. 새 버전 판정(latestBuild > currentBuild)은 핀 한 줄뿐이다.
// 원본: CheckUpdateCheck.swift 44-64(주기) · 126-134(공지 콜백) · 311-405(checkServerNow·startServerWatch·handleWake) ·
//       WorkTimerStore.swift 1010-1044(applyAppNotice·dismissAppNotice — 닫음 표식 기기별·계정 무관) · CheckApp.swift 202-215(배선).
// 맥 판의 GitHub 폴백·DMG·`app_latest_release`·semver 비교는 옮기지 않는다(Windows 는 빌드 번호 하나로 비교).
package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.desktop.shellapi.DesktopUpdateState
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 조회 주기(CheckUpdateCheck.swift 48 · 77-79 · 160-162). 밀리초.
 * ① 실행 5초 뒤 1회 — 자동 실행 직후 네트워크 연결·세션 복구와 겹치지 않게.
 * ② 이후 300초마다 — 릴리스는 하루 한두 번, 요청은 jsonb 한 줄.
 * ③ 깨어나면 10초 뒤 — 깨어난 순간엔 네트워크가 아직 없다. 연달아 깨면 마지막 한 번만.
 * ④ 플라이아웃을 열면 마지막 **시도** 뒤 60초가 지났을 때만(맥 팝오버 열기 스로틀). 주기·깨어남은 이 스로틀을 받지 않는다.
 */
data class UpdatePollSchedule(
    val initialDelayMillis: Long = 5_000,
    val intervalMillis: Long = 300_000,
    val wakeSettleMillis: Long = 10_000,
    val openThrottleMillis: Long = 60_000,
) {
    companion object {
        val DEFAULT: UpdatePollSchedule = UpdatePollSchedule()
    }
}

/**
 * 새 버전·공지 조회기. 앱 조립(AppGraph)이 실행당 하나 만들고 [startWatch] 한 번, 전원 사건은 [attach] 로 잇는다.
 *
 * ★1 조회 한 번 = 릴리스 뒤 공지, **같은 작업 안에서**(새 타이머 없음). 한쪽의 실패가 다른 쪽을 막지 않는다(각자 삼킨다).
 * ★2 재진입 가드: 조회가 떠 있으면 새로 치지 않고 그 결과를 기다린다(주기·깨어남·열기가 겹쳐도 요청 1회).
 * ★3 스탬프는 시도 시점(성공·실패 무관). 실패는 조용히 — 사용자 방해 금지, 다음 주기가 다시 판정한다.
 * ★4 맥은 주기 잠을 "멈추는 시계(.suspending)"로 자서 잠든 동안 주기가 흐르지 않는다. JVM `delay` 는 그 구분이 없으므로
 *    잠들면(SLEEP) 주기를 멈추고, 깨면(WAKE) 주기를 **settle 뒤 첫 조회**로 다시 시작한다 — 깨는 즉시 네트워크 없이 헛조회가
 *    나가거나 매달린 요청이 깨어남 조회를 삼키는 일이 없다.
 * ⚠️5 공지 조회가 **던지면** 떠 있던 카드를 그대로 둔다. null(공지 없음)은 결과라 카드를 내린다.
 * ⚠️6 닫은 공지 id 는 기기별·계정 무관으로 남는다(`check.notice.dismissed.<id>` — 맥 키와 같다). 같은 id 는 다시 안 뜨고 새 id 는 뜬다.
 */
class DesktopUpdateChecker(
    private val rpc: UpdateRpc,
    currentBuild: Long,
    /** 기기 단위 저장소(사용자 id 를 섞지 않는다 — ⚠️6). */
    private val deviceStore: DesktopKeyValueStore,
    private val scope: CoroutineScope,
    private val monotonic: MonotonicClock,
    private val schedule: UpdatePollSchedule = UpdatePollSchedule.DEFAULT,
) {
    private val _state = MutableStateFlow(DesktopUpdateState(currentBuild = currentBuild))

    /** 점·배너·공지 카드가 읽는 유일한 값. */
    val state: StateFlow<DesktopUpdateState> = _state.asStateFlow()

    private val lock = Any()
    private var inFlight: Deferred<Unit>? = null
    private var lastAttemptNanos: Long? = null
    private var watching = false
    private var loopJob: Job? = null

    /** 서버 감시를 켠다(멱등). ① 5초 뒤 첫 조회, 이후 ② 300초마다. */
    fun startWatch() {
        synchronized(lock) {
            if (watching) return
            watching = true
            loopJob = launchLoop(schedule.initialDelayMillis)
        }
    }

    /** 서버 감시를 끈다(주기·깨어남 대기). 이미 떠 있던 조회 1건은 끝까지 간다. */
    fun stopWatch() {
        synchronized(lock) {
            watching = false
            loopJob?.cancel()
            loopJob = null
        }
    }

    /** 전원 사건(★4). 감시가 꺼져 있으면 아무것도 안 한다(맥: 깨어남 구독은 startServerWatch 가 건다). */
    fun onPowerEvent(event: PowerEvent) {
        synchronized(lock) {
            if (!watching) return
            loopJob?.cancel()
            loopJob = when (event) {
                PowerEvent.SLEEP -> null
                // ③ 연달아 깨면 앞의 대기를 취소하므로 마지막 한 번만 친다.
                PowerEvent.WAKE -> launchLoop(schedule.wakeSettleMillis)
            }
        }
    }

    /** 앱 조립이 `platform.power` 를 잇는 손잡이. */
    fun attach(power: PowerEvents): Registration = power.addListener(::onPowerEvent)

    /** ④ 플라이아웃이 열렸다(c1 이 부른다) — 60초 스로틀. */
    fun onFlyoutOpened(): Job = scope.launch { checkNow(minimumIntervalMillis = schedule.openThrottleMillis) }

    /**
     * 1회 조회해 반영한다(★1·★2·★3). [minimumIntervalMillis] 가 0 보다 크면 마지막 시도 뒤 그만큼 안 지났을 때 조용히 돌아간다.
     */
    suspend fun checkNow(minimumIntervalMillis: Long = 0) {
        val job: Deferred<Unit> = synchronized(lock) {
            inFlight ?: run {
                val now = monotonic.elapsedNanos()
                val last = lastAttemptNanos
                if (minimumIntervalMillis > 0 && last != null && now - last < minimumIntervalMillis * NANOS_PER_MILLI) return
                lastAttemptNanos = now
                scope.async(start = CoroutineStart.LAZY) { fetchOnce() }.also { created ->
                    inFlight = created
                    created.invokeOnCompletion { synchronized(lock) { if (inFlight === created) inFlight = null } }
                }
            }
        }
        job.start()
        job.await()
    }

    /** 보이는 공지를 닫는다(⚠️6). 보이는 공지가 없으면 아무것도 안 한다(키를 남기지 않는다). */
    fun dismissNotice() {
        val visible = _state.value.notice ?: return
        deviceStore.putBoolean(noticeDismissedKey(visible.id), true)
        _state.update { if (it.notice?.id == visible.id) it.copy(notice = null) else it }
    }

    private fun launchLoop(firstDelayMillis: Long): Job = scope.launch {
        var wait = firstDelayMillis
        while (isActive) {
            delay(wait)
            checkNow()
            wait = schedule.intervalMillis
        }
    }

    private suspend fun fetchOnce() {
        try {
            applyRelease(rpc.clientRelease())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // ★3 모름 — 상태를 바꾸지 않는다.
        }
        try {
            applyNotice(rpc.currentNotice())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // ⚠️5 던졌다 — 떠 있던 카드를 그대로 둔다.
        }
    }

    /**
     * 서버가 "ok" 면 그 값을 그대로 싣는다(되돌린 릴리스도 따른다 — 판정은 핀의 `updateAvailable` 한 줄).
     * 그 밖의 상태(`unknown_platform` — 서버에 Windows 줄이 아직 없다)는 "알려진 새 버전 없음"이다.
     */
    internal fun applyRelease(release: ClientReleaseResponse) {
        _state.update { s ->
            if (release.status == STATUS_OK) {
                s.copy(
                    latestBuild = release.latestBuild,
                    latestVersion = release.latestVersion,
                    notes = release.notes,
                    downloadUrl = release.downloadUrl,
                )
            } else {
                s.copy(latestBuild = null, latestVersion = null, notes = null, downloadUrl = null)
            }
        }
    }

    /** 공지 결과 반영(맥 applyAppNotice). 닫은 id 는 여기서 걸러진다. */
    internal fun applyNotice(notice: AppNotice?) {
        val visible = notice?.takeUnless { deviceStore.getBoolean(noticeDismissedKey(it.id)) == true }
        _state.update { if (it.notice == visible) it else it.copy(notice = visible) }
    }

    companion object {
        const val STATUS_OK: String = "ok"
        private const val NANOS_PER_MILLI = 1_000_000L

        /** 맥 `WorkTimerStore.noticeDismissedKey` 와 같은 키(기기별 · 계정 무관). */
        fun noticeDismissedKey(id: String): String = "check.notice.dismissed.$id"
    }
}
