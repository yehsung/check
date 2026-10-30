// 원본: Sources/check/CheckApp.swift:222-241 @ a63fea2 (로그인 자동 실행은 기본값 — 매 실행마다 판단해 사라졌으면 되살린다,
//       사용자가 끈 것은 두 갈래 모두 존중: 앱 토글 = 설정 값, 시스템에서 끈 것 = .requiresApproval → Windows 는 작업 관리자
//       StartupApproved 표시(RunKeyLoginItem 이 되살리지 않는다), 실패는 삼키지 않고 다음 실행에서 다시)
//       · W-9 #3(launchAtLogin 은 W3-c4 DesktopSettingsStore 흐름, 적용은 W3-d) · 설계 D§5-5(MSIX 는 StartupTask — loginItem null)
package com.yehsung.aingcheck.desktop.wiring.os

import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem
import com.yehsung.aingcheck.desktop.platform.windows.login.RunKeyLoginItem
import com.yehsung.aingcheck.desktop.platform.windows.login.StartupTaskLoginItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.coroutines.CoroutineContext

/** 설정 화면 상태 한 줄. */
enum class LoginItemStatus {
    /** 켜져 있다(Run 값이 우리 명령이고 작업 관리자에서 끄지 않았다). */
    ON,
    /** 꺼져 있다(사용자가 앱에서 껐다). */
    OFF,
    /** 켜려 했지만 작업 관리자 '시작 앱'에서 사용자가 껐다 — 되살리지 않는다(거기서 켜 달라고 안내). */
    BLOCKED_BY_SYSTEM,
    /** 켜려 했지만 레지스트리 쓰기가 안 됐다 — 다음 실행·다음 설정 변경에서 다시. */
    FAILED,
    /** 자동 실행 길이 없다(패키지 신원도 실행 파일 경로도 없는 개발 실행 — loginItem null). MSIX 는 이제 StartupTask 로 관리한다(W-13 #6). */
    UNMANAGED,
}

/**
 * [launchAtLogin] 흐름(첫 값 포함 — 앱 시작마다 되살림)을 [loginItem] 에 적용한다. 같은 값은 다시 쓰지 않지만 [reapply] 로 다시 판정한다.
 * [ioContext] 는 레지스트리 자리(앱 = IO, 시험 = 시험 디스패처).
 */
class LoginItemBinding(
    private val loginItem: LoginItem?,
    private val launchAtLogin: Flow<Boolean>,
    private val ioContext: CoroutineContext = Dispatchers.IO,
    /** 작업 관리자 '시작 앱'에서 사용자가 껐나(K3 LoginItem 에 없는 칸 — RunKeyLoginItem.userDisabled). */
    /** 적용 한 번이 끝났다(UI 줄기) — 조립이 설정 스위치를 실제 상태에 맞춘다(DesktopSettingsStore.reflectLaunchAtLoginActual). */
    private val onApplied: (want: Boolean, status: LoginItemStatus) -> Unit = { _, _ -> },
    private val disabledBySystem: () -> Boolean = {
        when (loginItem) {
            is RunKeyLoginItem -> loginItem.userDisabled() == true
            // MSIX(W-13 #6): StartupTask 가 DisabledByUser·DisabledByPolicy 면 앱이 되살릴 수 없다 — 같은 안내.
            is StartupTaskLoginItem -> loginItem.userDisabled()
            else -> false
        }
    },
) : AutoCloseable {
    private val state = MutableStateFlow(if (loginItem == null) LoginItemStatus.UNMANAGED else LoginItemStatus.OFF)
    val status: StateFlow<LoginItemStatus> = state.asStateFlow()
    private val retry = MutableStateFlow(0)
    private var job: Job? = null

    fun start(scope: CoroutineScope): Job {
        job?.cancel()
        return scope.launch {
            if (loginItem == null) return@launch
            combine(launchAtLogin, retry) { want, n -> want to n }
                .distinctUntilChanged()
                .collect { (want, _) ->
                    val next = withContext(ioContext) { apply(loginItem, want) }
                    state.value = next
                    onApplied(want, next)
                }
        }.also { job = it }
    }

    fun reapply() {
        retry.value += 1
    }

    private fun apply(item: LoginItem, want: Boolean): LoginItemStatus {
        runCatching { item.setEnabled(want) }
        val now = runCatching { item.isEnabled() }.getOrNull()
        return when {
            !want -> if (now == true) LoginItemStatus.FAILED else LoginItemStatus.OFF
            now == true -> LoginItemStatus.ON
            runCatching(disabledBySystem).getOrDefault(false) -> LoginItemStatus.BLOCKED_BY_SYSTEM
            else -> LoginItemStatus.FAILED
        }
    }

    override fun close() {
        job?.cancel()
        job = null
    }
}
