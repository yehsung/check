// 원본: Sources/CheckMobileKit/Games/GamesSystemIdleTimer.swift @ 3bd04bd (UIApplication.isIdleTimerDisabled 대입 — 부르는 곳은 GamesStore 하나)
//
// 대국·미니게임 중 화면 꺼짐 방지의 **Android 대입**(E§4.4 · W4-b ③). 판정(언제 켜나)은 스토어 하나가 쥔다 — GamesStore.wantsIdleTimerDisabled
// (앱 active · 로그인 · 끝나지 않은 미니게임 판[타이밍 바 제외] · 1:1 판). 화면(Composable)은 이 값을 쓰지 않는다(Swift 와 같은 주인).
// 조립(K11)이 Activity 를 세울 때마다 그 창으로 이 싱크를 단다: GamesKeepScreenOn.install(gamesStore, activity.window) — assembly.md. 스토어는 앱 수명이고 창은 Activity 수명이다.
package com.yehsung.aingcheck.android.screens.games.hub

import android.view.Window
import android.view.WindowManager
import com.yehsung.aingcheck.core.stores.games.GamesStore

object GamesKeepScreenOn {
    /**
     * 싱크를 단다(뒤의 호출이 앞을 갈아 끼운다 — 새 Activity 의 창이 플래그를 받는다). 지금 값을 곧바로 한 번 넘기고, 이후 값이 바뀔 때마다 스토어가 다시 넘긴다.
     * 창 플래그는 메인 스레드에서 바뀌어야 한다 — 스토어의 일은 조립이 준 메인 범위에서 돈다.
     * @return 이 싱크를 푸는 일. Activity onDestroy 가 부른다 — 죽은 창을 쥐지 않게.
     */
    fun install(store: GamesStore, window: Window): () -> Unit {
        val sink: (Boolean) -> Unit = { disabled -> apply(window, disabled) }
        store.installIdleTimerSink(sink)
        return { store.uninstallIdleTimerSink(sink) }
    }

    /** 창에 대입한다(Swift `GamesSystemIdleTimer.apply(disabled:)` — 같은 값이면 건드리지 않는다). */
    fun apply(window: Window, disabled: Boolean) {
        val on = (window.attributes.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0
        if (on == disabled) return
        if (disabled) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
