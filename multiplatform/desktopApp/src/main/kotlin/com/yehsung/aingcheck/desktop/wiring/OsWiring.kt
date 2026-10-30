// 원본: 없음(조립 — int-w2 배선 os-work). 근거: W3-d notes_for_next(단축키·자동 실행·kv flush) · W-13 #2·#3·#4·#6.
//   - 단축키 → 근무 토글: Sources/check/WorkShortcut.swift:331-406(WorkShortcutCoordinator — 알약과 같은 조건 canToggleWorkByShortcut,
//     같은 동작 store.toggle()) · CheckApp.swift 의 등록 상태 → 설정 줄.
//   - 자동 실행: CheckApp.swift:222-241(기본 켬 · 사용자가 끈 것 존중 · 실제 상태로 스위치 맞춤).
//   - 플라이아웃 열림 = 맥 appDidBecomeActive 짝: 기기 재등록(1시간 스로틀은 SessionStore.appDidBecomeActive 가 — 실행·로그인과 같은
//     register_device RPC, WindowsDeviceRegistration) · 맥 팝오버 .task 의 넛지 설정 다시 읽기.
//   - kv 종료 flush: FileDesktopKeyValueStore.close()(남은 묶음 쓰기 → 뒤의 put 은 바로 쓰기).
// AppGraph 는 [OsWiring] 하나만 만들고 start(scope) → (앱 수명) → stop() → flushKeyValueStore() 순서로 부른다(조립 줄은 보고 notes).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.desktop.pages.desktopsettings.HotkeyRegistrationStatus
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy
import com.yehsung.aingcheck.desktop.wiring.os.LoginItemBinding
import com.yehsung.aingcheck.desktop.wiring.os.LoginItemStatus
import com.yehsung.aingcheck.desktop.wiring.os.WorkHotkeyBinding
import com.yehsung.aingcheck.desktop.wiring.os.WorkHotkeyStatus
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlin.coroutines.CoroutineContext

/**
 * OS 배선의 의존 묶음. 설정 흐름은 [DesktopSettingsStore] 의 것 그대로([fromSettings] 가 맞춰 준다).
 * [canToggleWork] 는 pages 몫 순수 함수(맥 canToggleWorkByShortcut — 로그인 && 팀 && canSync, W-13 #4)를 조립이 넘긴다.
 * [flyoutOpen] 은 껍데기 플라이아웃 nav.visible.
 */
data class OsDeps(
    val hotkeys: HotkeyService,
    /** null = 단축키 끔. */
    val hotkeyChord: Flow<HotkeyChord?>,
    val hotkeyRecording: Flow<Boolean> = flowOf(false),
    val noteHotkeyStatus: (HotkeyRegistrationStatus) -> Unit = {},
    val canToggleWork: () -> Boolean,
    val toggleWork: () -> Unit,
    /** 막힌 누름 알림(맥 NSSound.beep — 앱은 Toolkit beep). */
    val onHotkeyRejected: () -> Unit = {},
    /** MSIX = StartupTaskLoginItem · MSI = RunKeyLoginItem · 개발 실행 = null(WindowsPlatform.loginItemKind). */
    val loginItem: LoginItem?,
    val launchAtLogin: Flow<Boolean> = flowOf(true),
    /** 적용 뒤 실제 상태로 스위치를 맞춘다(DesktopSettingsStore.reflectLaunchAtLoginActual). */
    val reflectLaunchAtLogin: (Boolean) -> Unit = {},
    val flyoutOpen: Flow<Boolean>,
    /** 맥 appDidBecomeActive 짝 — 앱은 SessionStore.appDidBecomeActive(1시간 스로틀 기기 재등록 + 못 한 로그아웃 정리). */
    val appDidBecomeActive: () -> Unit,
    /** 플라이아웃이 열린 순간 덧붙일 일(앱은 DesktopSettingsStore.reloadNudge). */
    val onFlyoutOpened: () -> Unit = {},
    val kv: DesktopKeyValueStore,
    /** RegisterHotKey 왕복 자리(앱 = IO, 시험 = 시험 디스패처). */
    val registerContext: CoroutineContext = Dispatchers.IO,
    /** 레지스트리·WinRT 자리(앱 = IO, 시험 = 시험 디스패처). */
    val ioContext: CoroutineContext = Dispatchers.IO,
) {
    companion object {
        /** 설정 저장소의 흐름·적용 문을 OS 배선 칸에 맞춘다(나머지 칸은 조립이 채운다). */
        fun fromSettings(
            settings: DesktopSettingsStore,
            hotkeys: HotkeyService,
            canToggleWork: () -> Boolean,
            toggleWork: () -> Unit,
            onHotkeyRejected: () -> Unit,
            loginItem: LoginItem?,
            flyoutOpen: Flow<Boolean>,
            appDidBecomeActive: () -> Unit,
            kv: DesktopKeyValueStore,
        ): OsDeps = OsDeps(
            hotkeys = hotkeys,
            hotkeyChord = settings.hotkey.map { if (it.enabled) it.chord else null },
            hotkeyRecording = settings.hotkeyRecording,
            noteHotkeyStatus = settings::noteHotkeyStatus,
            canToggleWork = canToggleWork,
            toggleWork = toggleWork,
            onHotkeyRejected = onHotkeyRejected,
            loginItem = loginItem,
            launchAtLogin = settings.launchAtLogin,
            reflectLaunchAtLogin = settings::reflectLaunchAtLoginActual,
            flyoutOpen = flyoutOpen,
            appDidBecomeActive = appDidBecomeActive,
            onFlyoutOpened = settings::reloadNudge,
            kv = kv,
        )
    }
}

class OsWiring(private val deps: OsDeps) {
    val workHotkey = WorkHotkeyBinding(
        service = deps.hotkeys,
        chord = deps.hotkeyChord,
        recording = deps.hotkeyRecording,
        canToggle = deps.canToggleWork,
        toggle = deps.toggleWork,
        onRejected = deps.onHotkeyRejected,
        registerContext = deps.registerContext,
    )

    /**
     * 바인딩이 받는 '사용자 뜻'. 설정 흐름에서 오되, 적용 결과를 스위치에 되비춘 값(메아리)은 거른다 — 안 거르면 작업 관리자에서 끈
     * Run 값을 앱이 다시 지우고(끔 적용) 다음 실행에서 또 쓰는 되먹임이 돈다. null = 첫 값 전(아무것도 적용하지 않는다).
     */
    private val launchIntent = MutableStateFlow<Boolean?>(null)
    private var launchEcho: Boolean? = null

    val loginItem = LoginItemBinding(
        loginItem = deps.loginItem,
        launchAtLogin = launchIntent.filterNotNull(),
        ioContext = deps.ioContext,
        onApplied = { want, status -> reflectLaunch(want, status) },
    )

    private val jobs = mutableListOf<Job>()
    private var scope: CoroutineScope? = null

    /** 앱 시작(로그인 전이어도 된다). 멱등. */
    fun start(scope: CoroutineScope) {
        if (this.scope != null) return
        this.scope = scope
        jobs += workHotkey.start(scope)
        jobs += scope.launch { workHotkey.status.collect { deps.noteHotkeyStatus(registrationStatus(it)) } }
        jobs += scope.launch {
            deps.launchAtLogin.collect { v ->
                val echo = launchEcho
                launchEcho = null
                if (echo != null && echo == v) return@collect
                if (launchIntent.value == v) loginItem.reapply() else launchIntent.value = v
            }
        }
        jobs += loginItem.start(scope)
        jobs += scope.launch {
            var wasOpen = false
            deps.flyoutOpen.collect { open ->
                if (open && !wasOpen) {
                    runCatching { deps.appDidBecomeActive() }
                    runCatching { deps.onFlyoutOpened() }
                }
                wasOpen = open
            }
        }
    }

    /** 설정 창을 열 때 — 겹치던 앱이 키를 놓았거나 작업 관리자에서 다시 켰을 수 있다. */
    fun reapply() {
        workHotkey.reapply()
        loginItem.reapply()
    }

    private fun reflectLaunch(want: Boolean, status: LoginItemStatus) {
        val actual = when (status) {
            LoginItemStatus.ON -> true
            LoginItemStatus.OFF, LoginItemStatus.BLOCKED_BY_SYSTEM -> false
            // 쓰기 실패: 켜려다 못 했으면 꺼짐, 끄려다 못 했으면 켜짐(LoginItemBinding.apply 의 FAILED 두 갈래).
            LoginItemStatus.FAILED -> !want
            LoginItemStatus.UNMANAGED -> return
        }
        if (actual == want) return
        launchEcho = actual
        deps.reflectLaunchAtLogin(actual)
    }

    /** 수명 끝(종료 단계 [STEP_OS_STOP]). 단축키 등록을 푼다. */
    fun stop() {
        jobs.forEach { it.cancel() }
        jobs.clear()
        workHotkey.close()
        loginItem.close()
        scope = null
    }

    /** 종료 단계 [STEP_KV_FLUSH] — 근무 마무리·토큰 캐시·오버레이 자리 저장이 모두 kv 에 쓴 **뒤**. 뒤의 늦은 put 은 바로 쓰기. */
    fun flushKeyValueStore() {
        (deps.kv as? AutoCloseable)?.let { runCatching { it.close() } }
    }

    val isStarted: Boolean get() = scope != null

    companion object {
        const val STEP_OS_STOP = "os.stop"
        const val STEP_KV_FLUSH = "kv.flush"

        /** 설정 화면 줄(맥 WorkShortcutStatus). OS 가 쥔 조합(W-13 #3)은 맥 시스템 단축키 대조(.conflict)와 같은 '겹쳐요'. */
        fun registrationStatus(s: WorkHotkeyStatus): HotkeyRegistrationStatus = when (s) {
            is WorkHotkeyStatus.Active -> HotkeyRegistrationStatus.ACTIVE
            WorkHotkeyStatus.Off -> HotkeyRegistrationStatus.OFF
            WorkHotkeyStatus.Paused -> HotkeyRegistrationStatus.PAUSED
            is WorkHotkeyStatus.Conflict -> HotkeyRegistrationStatus.CONFLICT
            is WorkHotkeyStatus.Invalid -> when (s.reason) {
                HotkeyPolicy.Rejection.RESERVED_KEY, HotkeyPolicy.Rejection.WIN_KEY_RESERVED -> HotkeyRegistrationStatus.CONFLICT
                else -> HotkeyRegistrationStatus.FAILED
            }
            is WorkHotkeyStatus.Failed -> HotkeyRegistrationStatus.FAILED
        }
    }
}
