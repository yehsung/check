// 원본: Sources/CheckMobileKit/App/MobileRootView.swift:66-78 @ 3bd04bd (scenePhase .active → appDidBecomeActive · .background → appDidEnterBackground)
// 원본: Sources/CheckMobileKit/Games/GamesStore.swift @ 3bd04bd (자리 API appDidBecomeActive · appDidEnterBackground)
//
// 프로세스 수명(ProcessLifecycleOwner ON_START·ON_STOP — AppLifecycle)을 게임 탭 스토어의 자리 API 로 옮긴다(E§5.1).
//  · ON_STOP(iOS .background): GamesStore.appDidEnterBackground — 미니게임 판은 **끝**(타이밍 바·플래피는 기록 없이, **테트리스는 여기까지의 점수로
//    확정 제출**), 오목·체스·1:1 테트리스는 **가림**(폴링만 멈춘다 — 판은 계속 흐른다).
//  · ON_START(iOS .active): GamesStore.appDidBecomeActive — 같은 토큰으로 제출 재시도 · 따라잡기.
//  · ON_PAUSE(iOS .inactive)는 여기 오지 않는다 — 알림창 내리기·다중 창에서 판을 끝내지 않는다(미니게임 화면이 초점 상실로 **얼리기만** 한다, G §8-2).
// 조립(K11)이 한 번 붙인다: GamesLifecycleBridge(gamesStore).attach(container.lifecycle) — assembly.md.
package com.yehsung.aingcheck.android.screens.games.hub

import com.yehsung.aingcheck.android.lifecycle.AppLifecycle
import com.yehsung.aingcheck.core.stores.games.GamesStore

class GamesLifecycleBridge(private val store: GamesStore) {
    private var lastForeground: Boolean? = null

    /** 프로세스 수명에 붙는다(AppLifecycle 은 붙는 순간 지금 값을 한 번 준다 — 처음 값이 뒤(false)면 아무것도 끝내지 않는다: 열린 판이 없다). */
    fun attach(lifecycle: AppLifecycle) {
        lifecycle.addListener(::onForegroundChanged)
    }

    /** 앞/뒤가 **바뀔 때만** 자리 API 를 부른다(같은 값이 두 번 와도 판을 두 번 끝내지 않는다). */
    fun onForegroundChanged(isForeground: Boolean) {
        if (lastForeground == isForeground) return
        val first = lastForeground == null
        lastForeground = isForeground
        if (isForeground) store.appDidBecomeActive() else if (!first) store.appDidEnterBackground()
    }
}
