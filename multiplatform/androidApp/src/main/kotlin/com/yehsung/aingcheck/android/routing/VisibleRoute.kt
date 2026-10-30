// 지금 화면에 떠 있는 라우트(푸시 숨김 판정용 — E§6.4 "앞 + 보고 있는 대화면 게시 안 함").
// 셸(NavGraph)이 목적지가 바뀔 때마다 적고, 푸시 서비스가 읽는다. 앱이 뒤로 가면 null 로 읽힌다.
package com.yehsung.aingcheck.android.routing

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class VisibleRoute {
    private val onScreen = MutableStateFlow<AingRoute?>(null)
    private val foreground = MutableStateFlow(false)

    /** 화면의 라우트(앞·뒤 상관없이 마지막으로 그린 것). */
    val route: StateFlow<AingRoute?> = onScreen.asStateFlow()

    fun setRoute(route: AingRoute?) {
        onScreen.value = route
    }

    fun setForeground(isForeground: Boolean) {
        foreground.value = isForeground
    }

    /** 사용자가 지금 **보고 있는** 라우트: 앱이 앞일 때만 값이 있다. */
    fun viewing(): AingRoute? = if (foreground.value) onScreen.value else null

    /**
     * 앱이 앞인가(화면과 상관없이). 앞이어도 라우트로 나타낼 수 없는 화면(미션 · 프로필 · 뽑기 · nav 대화상자 …)에서는 [viewing] 이 null 이라
     * '앞/뒤'를 viewing 으로 읽으면 안 된다 — 확성기 푸시 판정(Swift `isAppActive`)은 이 값을 본다.
     */
    fun isForeground(): Boolean = foreground.value
}
