// W-13 #6: MSIX 는 StartupTask(끄면 Disable), MSI 는 Run 키 — pfn 가드(패키지 신원이 있으면 Run 키 금지). 맥 CheckApp.swift:222-241.
package com.yehsung.aingcheck.desktop.platform.windows.login

import com.yehsung.aingcheck.desktop.platform.windows.LoginItemKind
import com.yehsung.aingcheck.desktop.platform.windows.WindowsPlatform
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StartupTaskLoginItemTest {
    private class Port(var s: Int) : StartupTaskPort {
        val calls = mutableListOf<String>()
        override fun state() = s
        override fun requestEnable(): Int {
            calls += "enable"
            if (s == StartupTaskState.DISABLED) s = StartupTaskState.ENABLED
            return s
        }
        override fun disable() {
            calls += "disable"
            if (s == StartupTaskState.ENABLED) s = StartupTaskState.DISABLED
        }
    }

    @Test
    fun pfn_이_있으면_실행_파일이_있어도_Run_키가_아니다() {
        assertEquals(LoginItemKind.STARTUP_TASK, WindowsPlatform.loginItemKind("Aing.Check_8wekyb3d8bbwe", "C:\\Program Files\\aing\\aing.exe"))
        assertEquals(LoginItemKind.STARTUP_TASK, WindowsPlatform.loginItemKind("Aing.Check_8wekyb3d8bbwe", null))
        // 음성 대조: 신원이 없으면 Run 키, 둘 다 없으면 없음.
        assertEquals(LoginItemKind.RUN_KEY, WindowsPlatform.loginItemKind(null, "C:\\aing.exe"))
        assertEquals(LoginItemKind.NONE, WindowsPlatform.loginItemKind(null, null))
    }

    @Test
    fun 상태_다섯_칸() {
        assertTrue(StartupTask(StartupTaskState.ENABLED).isEnabled())
        assertTrue(StartupTask(StartupTaskState.ENABLED_BY_POLICY).isEnabled())
        assertFalse(StartupTask(StartupTaskState.DISABLED).isEnabled())
        assertTrue(StartupTask(StartupTaskState.DISABLED_BY_USER).userDisabled())
        assertTrue(StartupTask(StartupTaskState.DISABLED_BY_POLICY).userDisabled())
        assertFalse(StartupTask(StartupTaskState.DISABLED).userDisabled())
    }

    private fun StartupTask(state: Int) = StartupTaskLoginItem(Port(state))

    @Test
    fun 끄기는_Enabled_일_때만_Disable__정책_켜짐은_못_끈다() {
        val p = Port(StartupTaskState.ENABLED)
        assertTrue(StartupTaskLoginItem(p).setEnabled(false))
        assertEquals(listOf("disable"), p.calls)
        val policy = Port(StartupTaskState.ENABLED_BY_POLICY)
        assertFalse(StartupTaskLoginItem(policy).setEnabled(false))
        assertTrue(policy.calls.isEmpty())
    }

    @Test
    fun 켜기는_Disabled_일_때만_RequestEnable__사용자가_끈_것은_되살리지_않는다() {
        val p = Port(StartupTaskState.DISABLED)
        assertTrue(StartupTaskLoginItem(p).setEnabled(true))
        assertEquals(listOf("enable"), p.calls)
        val user = Port(StartupTaskState.DISABLED_BY_USER)
        assertFalse(StartupTaskLoginItem(user).setEnabled(true))
        assertTrue(user.calls.isEmpty(), "작업 관리자에서 끈 것은 손대지 않는다")
    }

    /** 매니페스트 TaskId 와 코드 상수가 갈리면 GetAsync 가 다른 작업을 찾는다(조용히 FAILED). */
    @Test
    fun 매니페스트_TaskId_와_같다() {
        val template = listOf(Path.of("packaging/AppxManifest.template.xml"), Path.of("desktopApp/packaging/AppxManifest.template.xml"))
            .first { Files.exists(it) }
        val ids = Regex("""<desktop:StartupTask\s+TaskId="([^"]+)"""").findAll(Files.readString(template)).map { it.groupValues[1] }.toList()
        assertEquals(listOf(StartupTaskLoginItem.TASK_ID), ids)
    }
}
