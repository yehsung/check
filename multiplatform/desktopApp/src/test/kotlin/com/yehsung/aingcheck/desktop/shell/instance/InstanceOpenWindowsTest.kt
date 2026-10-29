// 원본: 없음(새 시험) — 설계 D-windows-platform §2-5 · W-3 #5: 두 번째 프로세스가 "열어 달라"를 보내면 첫 실행이 open() 을 **한 번** 부른다.
//       신호 보내기는 기존 자식 탐침(RunnerSupport.runChild "signal" — W1-f 소유, 읽기만)을 쓴다: 진짜 다른 프로세스다.
package com.yehsung.aingcheck.desktop.shell.instance

import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.platform.windows.runner.RunnerSupport
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@EnabledOnOs(OS.WINDOWS)
class InstanceOpenWindowsTest {
    private class CountingNav : FlyoutNavigator {
        val opens = AtomicInteger(0)
        override val visible: StateFlow<Boolean> = MutableStateFlow(false)
        override val route: StateFlow<FlyoutRoute> = MutableStateFlow(FlyoutRoute.Home)
        override fun open(route: FlyoutRoute?) { opens.incrementAndGet() }
        override fun navigate(route: FlyoutRoute) {}
        override fun back() {}
        override fun hide() {}
    }

    @Test
    fun secondProcessSignalOpensFlyoutOnce() {
        val cls = RunnerSupport.unique("AingCheck.ShellInstanceTest")
        val thread = Win32MessageThread.start(className = cls)
        try {
            val nav = CountingNav()
            val reg = InstanceActivation.bindWindows(thread, nav, Executor { it.run() })
            val r = RunnerSupport.runChild(listOf("signal", cls))
            assertEquals(0, r.exitCode, r.stderr)
            assertTrue(r.stdout.contains("sent=true"), r.stdout)
            RunnerSupport.waitUntil(5_000, "open() 1회") { nav.opens.get() >= 1 }
            Thread.sleep(300)
            assertEquals(1, nav.opens.get(), "신호 하나에 open 하나")
            reg.close()
        } finally {
            thread.close()
        }
    }
}
