// 원본: Sources/check/WorkShortcut.swift:196-212 @ a63fea2 (WorkShortcutStatus active·off·paused·conflict·failed)
//       · :331-406 (WorkShortcutCoordinator.apply — 끔이면 풀기, 기록 중이면 내림, 겹치면 걸지 않음, 아니면 등록 / handlePress —
//         1.5초 연타 가드, 실제로 토글한 누름만 시각을 남김, 알약이 막히는 조건이면 거부 알림)
//       · W-9 #3·#4(설정은 W3-c4 DesktopSettingsStore 의 흐름, 적용은 W3-d · 기본 Ctrl+Alt+Shift+Space · 겹치면 맥처럼 안내)
//
// 맥과 다른 곳: 맥은 Carbon 이 겹침을 알려 주지 않아 시스템 단축키 목록과 대조(.conflict)하고, 다른 앱과의 겹침은 모른다.
// Windows RegisterHotKey 는 다른 앱·시스템과 겹치면 실패(보통 1409)를 돌려준다 → 그것을 [WorkHotkeyStatus.Conflict] 로 낸다.
// 조합 규칙 위반은 [WorkHotkeyStatus.Invalid](등록 시도 0 — WindowsHotkeyService 는 규칙 위반에 예외를 던진다).
package com.yehsung.aingcheck.desktop.wiring.os

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyRegistrationResult
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.CoroutineContext

/** 설정 화면이 상태 한 줄을 고르는 값(맥 WorkShortcutStatus). */
sealed interface WorkHotkeyStatus {
    /** 등록돼 있다 — 누르면 근무가 토글된다. */
    data class Active(val chord: HotkeyChord) : WorkHotkeyStatus
    /** 사용자가 껐다(설정 흐름이 null). */
    data object Off : WorkHotkeyStatus
    /** 설정에서 새 조합을 기록하는 중이라 내렸다. */
    data object Paused : WorkHotkeyStatus
    /** 조합 규칙 위반(Win 키·수식키 하나·IME 키 등). 걸지 않았다. */
    data class Invalid(val chord: HotkeyChord, val reason: HotkeyPolicy.Rejection) : WorkHotkeyStatus
    /** 다른 앱·시스템이 이미 쥐고 있다(Win32 오류 코드, 보통 1409). 맥 '겹쳐요' 안내 자리. */
    data class Conflict(val chord: HotkeyChord, val systemErrorCode: Int) : WorkHotkeyStatus
    /** 그 밖의 실패(메시지 스레드가 닫힘 등). */
    data class Failed(val chord: HotkeyChord, val message: String) : WorkHotkeyStatus
}

/**
 * 설정 흐름 → 전역 단축키 등록 ↔ 누름 → 근무 토글을 잇는 단 하나의 지점(맥 WorkShortcutCoordinator).
 * - [chord]: 설정의 조합. null = 끔. (W3-c4 DesktopSettingsStore 가 오기 전엔 조정자가 `flowOf(HotkeyPolicy.DEFAULT)` 를 넣는다.)
 * - [recording]: 설정 화면이 새 조합을 받는 중.
 * - [canToggle]·[toggle]: 플라이아웃 근무 알약과 **같은 조건·같은 동작**(맥 canToggleWorkByShortcut · store.toggle()). 누름 콜백은
 *   [HotkeyService] 가 받은 실행기(앱 = EDT)에서 오므로 UI 줄기에서 돈다.
 * - [onRejected]: 막힌 누름 알림(맥 NSSound.beep → Windows 는 조정자가 MessageBeep 등).
 * - [registerContext]: 등록·해제 자리(메시지 스레드 왕복이 막힐 수 있다 — 앱 = IO, 시험 = 시험 디스패처).
 */
class WorkHotkeyBinding(
    private val service: HotkeyService,
    private val chord: Flow<HotkeyChord?>,
    private val recording: Flow<Boolean> = flowOf(false),
    private val canToggle: () -> Boolean,
    private val toggle: () -> Unit,
    private val onRejected: () -> Unit = {},
    private val monotonicMillis: () -> Long = { System.nanoTime() / 1_000_000 },
    private val registerContext: CoroutineContext = Dispatchers.IO,
) : AutoCloseable {
    private val state = MutableStateFlow<WorkHotkeyStatus>(WorkHotkeyStatus.Off)
    val status: StateFlow<WorkHotkeyStatus> = state.asStateFlow()

    /** 다시 판정 요청(설정 창을 열 때 — 겹치던 앱이 키를 놓았을 수 있다). */
    private val retry = MutableStateFlow(0)

    @Volatile private var current: Registration? = null
    @Volatile private var lastToggledAt: Long? = null
    @Volatile private var closed = false
    private var job: Job? = null

    fun start(scope: CoroutineScope): Job {
        job?.cancel()
        return scope.launch {
            combine(chord, recording, retry) { c, r, n -> Triple(c, r, n) }
                .distinctUntilChanged()
                .collect { (c, r, _) -> withContext(registerContext) { apply(c, r) } }
        }.also { job = it }
    }

    fun reapply() {
        retry.value += 1
    }

    /** 맥 apply(): 늘 먼저 푼다(같은 조합을 다시 걸 때 자기 자신과 겹치지 않게). */
    private fun apply(c: HotkeyChord?, recording: Boolean) {
        release()
        val next: WorkHotkeyStatus = when {
            c == null -> WorkHotkeyStatus.Off
            recording -> WorkHotkeyStatus.Paused
            else -> when (val v = HotkeyPolicy.validate(c)) {
                is HotkeyPolicy.Verdict.Rejected -> WorkHotkeyStatus.Invalid(c, v.reason)
                HotkeyPolicy.Verdict.Ok -> try {
                    when (val r = service.register(c) { handlePress() }) {
                        is HotkeyRegistrationResult.Registered -> {
                            if (closed) {
                                // close 와 엇갈린 늦은 등록 — 남기지 않는다.
                                runCatching { r.registration.close() }
                                return
                            }
                            current = r.registration
                            WorkHotkeyStatus.Active(c)
                        }
                        is HotkeyRegistrationResult.Conflict -> WorkHotkeyStatus.Conflict(c, r.systemErrorCode)
                    }
                } catch (t: Throwable) {
                    WorkHotkeyStatus.Failed(c, t.message ?: t.toString())
                }
            }
        }
        if (state.value != next) state.value = next
    }

    private fun release() {
        val r = current ?: return
        current = null
        runCatching { r.close() }
    }

    /** 전역 단축키가 눌렸다(맥 handlePress). */
    fun handlePress() {
        val now = monotonicMillis()
        val last = lastToggledAt
        if (last != null && now - last in 0 until REPEAT_GUARD_MILLIS) return
        if (!canToggle()) {
            onRejected()
            return
        }
        toggle()
        lastToggledAt = now
    }

    override fun close() {
        closed = true
        job?.cancel()
        job = null
        release()
        state.value = WorkHotkeyStatus.Off
    }

    companion object {
        /** 맥 repeatGuardSeconds 1.5. */
        const val REPEAT_GUARD_MILLIS = 1_500L
    }
}
