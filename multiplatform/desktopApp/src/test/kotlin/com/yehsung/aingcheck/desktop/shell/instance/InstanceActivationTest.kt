// 원본: 설계 D-windows-platform §2-5 · W-3 #5 — 두 번째 실행은 플라이아웃을 연다(★4 open 한 문, 라우트는 그대로).
package com.yehsung.aingcheck.desktop.shell.instance

import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class InstanceActivationTest {
    @Test
    fun signalOpensCurrentRouteOnce() {
        var signal: (() -> Unit)? = null
        var closed = 0
        val nav = InMemoryFlyoutNavigator(FlyoutRoute.Records)
        val reg = InstanceActivation.bind({ cb -> signal = cb; Registration { closed++ } }, nav)
        assertEquals(false, nav.visible.value)
        signal!!()
        assertTrue(nav.visible.value)
        assertEquals(FlyoutRoute.Records, nav.route.value)
        reg.close()
        assertEquals(1, closed)
    }
}
