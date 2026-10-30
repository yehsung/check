// 원본: Sources/check/WorkTimerStorePoke.swift 834-860(서버 집중값 적용 자리) · 1012-1234(단계 순환·PATCH 직렬화·만료·서버값 합치기)
//       · Sources/check/WorkTimerStore.swift 4062-4065(로그아웃 비우기) @ a90d8623
package com.yehsung.aingcheck.feature.desktop.focus

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.fetchTokenUsageSettings
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.focus.net.updateFocusMode
import com.yehsung.aingcheck.feature.desktop.socialapi.FocusModeReader
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 집중 모드(찌르기 수신 거부) 2단 — 끔 → 3시간 → 계속 → 끔.
 *
 * - ★F1 켜짐/꺼짐 **판정**은 서버(profiles.focus_mode), **만료**는 클라(이 기기 기록). 서버로 옮기지 않는다.
 * - ★F5 PATCH 는 한 번에 하나. 날아가는 동안 바뀐 의도는 끝난 뒤 **마지막 의도** 하나로 보낸다(연타 세 번 → 2건 이하).
 * - ★F6 만료 PATCH 가 실패하면 원복하지 않는다(기록은 남긴다). 60초 뒤 [evaluateFocusStageExpiry] 가 다시 보낸다.
 * - ★F7 사용자가 누른 PATCH 가 실패하면 서버가 확인한 값으로 원복하고 안내한다. 취소는 무시한다.
 * - ★F8 [focusStage]·[focusStageFace] 는 부수효과가 없다.
 * - [isFocusOn] 은 토스트 억제(D §14 B2)가 읽는다.
 * - 스레드: UI 스레드 하나(Swift `@MainActor`). [scope] 는 그 디스패처.
 */
class FocusModeController(
    private val host: SessionHost,
    store: DesktopKeyValueStore,
    private val scope: CoroutineScope,
    private val clock: () -> SwiftDate,
    /** 안내 한 줄(Swift `pokeNotice`). */
    private val onNotice: (String) -> Unit = {},
) : FocusModeReader {
    private val records = FocusStageRecords(store)

    private val _focusMode = MutableStateFlow(false)
    /** 화면·토스트가 읽는 켜짐 값(서버 값 + 이 기기의 의도). */
    val focusMode: StateFlow<Boolean> = _focusMode.asStateFlow()
    override val isFocusOn: Boolean get() = _focusMode.value

    private val _revision = MutableStateFlow(0)
    /** 기록이 바뀔 때마다 오른다(화면이 단계를 다시 그리는 눈금 — Swift `focusStageRevision`). */
    val revision: StateFlow<Int> = _revision.asStateFlow()

    /** 서버가 확인한 값(null = 아직 모른다). */
    var serverValue: Boolean? = null
        private set

    /** 날아가는 PATCH 의 값(null = 없음). */
    var patchInFlight: Boolean? = null
        private set

    var expiryRetryAt: SwiftDate? = null
        private set

    /** 사용자 의도 번호 — 서버 GET 이 떠난 뒤 의도가 바뀌었으면 그 GET 은 늦은 값이다. */
    var intentSerial: Int = 0
        private set

    private var serverLoaded = false

    /** 날아가는 서버값 GET(폴링 박자마다 불려도 겹쳐 보내지 않는다 — Swift 는 tick 을 await 해 저절로 하나였다). */
    private var serverLoadJob: Job? = null

    private fun setFocus(value: Boolean) {
        if (_focusMode.value != value) _focusMode.value = value
    }

    private fun writeRecord(record: FocusStageRecord?, userID: String) {
        if (records.write(record, userID)) _revision.value = _revision.value + 1
    }

    fun record(userID: String): FocusStageRecord? = records.read(userID)

    // ---- 읽기(부수효과 없음, F8) ----

    fun focusStage(now: SwiftDate): FocusStage {
        val userID = host.session?.userID
        if (!_focusMode.value || userID == null) return FocusStage.OFF
        return FocusStagePolicy.stage(true, records.read(userID)) { now }
    }

    fun focusStageFace(now: SwiftDate): FocusStageFace {
        val userID = host.session?.userID
        if (!_focusMode.value || userID == null) return FocusStageFace.OFF
        return FocusStageFace.of(true, records.read(userID), now)
    }

    // ---- 사용자 의도 ----

    /** 단추 한 번: 끔 → 3시간 → 계속 → 끔. */
    fun cycleFocusStage() {
        val now = clock()
        when (focusStage(now)) {
            FocusStage.OFF -> commit(FocusStage.TIMED, now)
            FocusStage.TIMED -> commit(FocusStage.ALWAYS, now)
            FocusStage.ALWAYS -> commit(FocusStage.OFF, now)
        }
    }

    /** 켜기/끄기 직접(켜기는 ALWAYS). 세션이 없으면 값만 바꾼다. */
    fun setFocusMode(enabled: Boolean) {
        if (_focusMode.value == enabled) return
        if (host.session == null) {
            _focusMode.value = enabled
            return
        }
        commit(if (enabled) FocusStage.ALWAYS else FocusStage.OFF, clock())
    }

    private fun commit(target: FocusStage, now: SwiftDate) {
        val userID = host.session?.userID ?: return
        intentSerial += 1
        expiryRetryAt = null
        val record = when (target) {
            FocusStage.OFF -> null
            FocusStage.TIMED -> FocusStageRecord(FocusStage.TIMED, now.addingTimeInterval(FocusStagePolicy.TIMED_DURATION_SECONDS))
            FocusStage.ALWAYS -> FocusStageRecord(FocusStage.ALWAYS, null)
        }
        writeRecord(record, userID)
        setFocus(target != FocusStage.OFF)
        reconcileWithServer()
    }

    // ---- 서버 맞추기(F5) ----

    /** 날아가는 PATCH 가 없을 때만 지금 의도를 보낸다. 이미 같으면 보내지 않는다(끔이면 기록을 비운다). */
    fun reconcileWithServer(): Job? {
        if (patchInFlight != null) return null
        val session = host.session ?: return null
        val userID = session.userID
        val desired = _focusMode.value
        if (serverValue == desired) {
            if (!desired) settleOff(userID)
            return null
        }
        patchInFlight = desired
        val generation = host.sessionGeneration
        return scope.launch {
            var succeeded = false
            var cancelled = false
            try {
                host.withSessionRetry { s -> host.service.updateFocusMode(s.accessToken, s.userID, desired) }
                succeeded = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (host.classifyAuthError(e) == AuthErrorDisposition.cancelled) cancelled = true
            }
            if (generation != host.sessionGeneration) return@launch
            patchInFlight = null
            finishPatch(desired, succeeded, cancelled, userID)
        }
    }

    private fun finishPatch(sent: Boolean, succeeded: Boolean, cancelled: Boolean, userID: String) {
        if (succeeded) {
            serverValue = sent
        } else if (_focusMode.value == sent) {
            // F6 만료 PATCH 실패 — 원복하지 않고 기록을 남긴 채 60초 뒤 다시.
            val record = records.read(userID)
            if (!sent && record != null && FocusStagePolicy.isExpired(record, clock)) {
                expiryRetryAt = clock().addingTimeInterval(FocusStagePolicy.EXPIRY_RETRY_SECONDS)
                return
            }
            if (cancelled) return
            // F7 사용자가 누른 PATCH 실패 — 서버가 확인한 값으로 원복 + 안내.
            val restored = serverValue ?: !sent
            setFocus(restored)
            if (!restored) writeRecord(null, userID)
            onNotice(FocusStagePolicy.CHANGE_FAILED_NOTICE)
            return
        }
        reconcileWithServer()
    }

    private fun settleOff(userID: String) {
        expiryRetryAt = null
        writeRecord(null, userID)
    }

    /** 폴링 박자의 '집중 만료' 단계(P10 — 메시지 만료 → 표시 만료 → **집중 만료** → 지갑 periodic). */
    fun evaluateFocusStageExpiry(now: SwiftDate) {
        if (!_focusMode.value && expiryRetryAt == null) return
        val userID = host.session?.userID ?: return
        val record = records.read(userID) ?: return
        if (!FocusStagePolicy.isExpired(record) { now }) return
        if (_focusMode.value) {
            intentSerial += 1
            _focusMode.value = false
            reconcileWithServer()
        } else {
            val retryAt = expiryRetryAt
            if (retryAt != null && now >= retryAt && patchInFlight == null) {
                expiryRetryAt = null
                reconcileWithServer()
            }
        }
    }

    // ---- 서버 값 받기 ----

    /**
     * 로그인 박자와 **폴링 박자마다**(Swift localExpiryTick → loadTokenUsagePrivacyIfNeeded 394-411·841) — profiles 의
     * focus_mode 를 읽어 합친다(토큰 공개·수집 칸은 버린다: W2-h 몫).
     * ★F11 성공했을 때만 '받았다'를 세운다 — 실패는 조용히, 다음 박자에 다시(오프라인으로 켠 앱이 끝난 1단을
     * 서버에서 끄지 못한 채 다음 로그인까지 가지 않게). 받은 뒤엔 같은 세션에서 다시 묻지 않고, 날아가는 중엔 겹쳐 보내지 않는다.
     */
    fun loadServerFocusMode(): Job? {
        if (serverLoaded || host.session == null) return null
        if (serverLoadJob?.isActive == true) return null
        val generation = host.sessionGeneration
        val intentAtRequest = intentSerial
        return scope.launch {
            val settings = try {
                host.withSessionRetry { s -> host.service.fetchTokenUsageSettings(s.accessToken, s.userID) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                return@launch
            }
            if (generation != host.sessionGeneration) return@launch
            serverLoaded = true
            applyServerFocusMode(settings.focusMode, intentAtRequest)
        }.also { serverLoadJob = it }
    }

    /**
     * 서버 값과 이 기기 기록을 합친다(Swift `applyServerFocusMode`).
     * 서버 꺼짐 → 기록을 지운다. 서버 켜짐 + 앱이 꺼진 동안 끝난 1단 → **곧바로** 끔 PATCH(재시작 만료).
     * ★F4 서버 켜짐 + 기록 없음 → 켜짐(단계는 ALWAYS 로 읽힌다).
     */
    fun applyServerFocusMode(serverOn: Boolean, intentSerialAtRequest: Int) {
        val userID = host.session?.userID ?: return
        if (patchInFlight != null) return
        if (intentSerial != intentSerialAtRequest && serverValue != null) return
        serverValue = serverOn
        if (!serverOn) {
            setFocus(false)
            settleOff(userID)
            return
        }
        val record = records.read(userID)
        if (record != null && FocusStagePolicy.isExpired(record, clock)) {
            if (expiryRetryAt != null) {
                evaluateFocusStageExpiry(clock())
                return
            }
            setFocus(false)
            reconcileWithServer()
            return
        }
        setFocus(true)
    }

    /** 로그아웃(기록은 사용자별 키라 남긴다 — 같은 사람이 다시 들어오면 단계가 이어진다). */
    fun reset() {
        _focusMode.value = false
        serverValue = null
        patchInFlight = null
        expiryRetryAt = null
        serverLoaded = false
        // 떠난 세션의 GET 은 세대 가드가 버린다 — 새 세션의 첫 GET 을 그것이 막지 않게 잊는다.
        serverLoadJob = null
    }
}
