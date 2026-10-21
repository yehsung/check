// 원본: Sources/CheckMobileKit/App/MobileRootView.swift:66-78(scenePhase) @ ios-1011(988609b) — E§5.1 수명 대응
// iOS .active ↔ ProcessLifecycleOwner ON_START, .background ↔ ON_STOP. .inactive(알림창 내리기·다중 창)는 ON_PAUSE 인데 끊지 않는다 —
// 그래서 여기서는 ON_START/ON_STOP 만 사건으로 낸다. 실시간 끊기·폴링 멈춤·테트리스 점수 확정은 듣는 쪽(W2·W4)이 한다.
package com.yehsung.aingcheck.android.lifecycle

import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow

enum class AppLifecycleEvent {
    /** 앱이 앞으로(iOS scenePhase .active). */
    FOREGROUND,
    /** 앱이 뒤로(iOS .background). */
    BACKGROUND,
}

class AppLifecycle {
    private val foreground = MutableStateFlow(false)
    private val events = MutableSharedFlow<AppLifecycleEvent>(extraBufferCapacity = 8, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    private val listeners = mutableListOf<(Boolean) -> Unit>()

    val isForeground: StateFlow<Boolean> = foreground.asStateFlow()
    val changes: SharedFlow<AppLifecycleEvent> = events.asSharedFlow()

    /** 같은 스레드(메인)에서 바로 알고 싶은 쪽(VisibleRoute 등). */
    fun addListener(listener: (Boolean) -> Unit) {
        listeners += listener
        listener(foreground.value)
    }

    /** 프로세스 수명에 붙인다(ProcessLifecycleOwner.get().lifecycle — 메인 스레드). */
    fun attach(lifecycle: Lifecycle) {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) = update(true)
            override fun onStop(owner: LifecycleOwner) = update(false)
        })
    }

    internal fun update(isForeground: Boolean) {
        if (foreground.value == isForeground) return
        foreground.value = isForeground
        listeners.forEach { it(isForeground) }
        events.tryEmit(if (isForeground) AppLifecycleEvent.FOREGROUND else AppLifecycleEvent.BACKGROUND)
    }
}
