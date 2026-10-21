// 원본: Sources/check/CheckApp.swift:133-137·242-250·458-477 @ a63fea2 (--autostart 면 창을 열지 않음, 종료 절차) — 시험은 새 코드:
//       G K11(조립 지점) · K4(ClientIdentity) · K6(device_id = 'win:' + 신원) · 설계 D§2-4(JNA DLL 을 %TEMP% 에 풀지 않음)·D§3-2·E11
package com.yehsung.aingcheck.desktop.platform.windows.app

import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.foundation.platform.desktop.AppPaths
import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyRegistrationResult
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.desktop.AppGraph
import com.yehsung.aingcheck.desktop.DesktopPlatform
import com.yehsung.aingcheck.desktop.LaunchOptions
import com.yehsung.aingcheck.desktop.platform.windows.HostOs
import com.yehsung.aingcheck.desktop.platform.windows.jna.JnaBootstrap
import com.yehsung.aingcheck.desktop.platform.windows.login.StartupApproved
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarThemeProbe
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Instant

/** 조립 지점(K11) 뼈대와 Main 의 순수 몫. */
class AppAssemblyTest {
    private class FakePlatform(private val id: String?) : DesktopPlatform {
        override val paths = object : AppPaths {
            override val dataDir = "D"; override val cacheDir = "C"; override val logDir = "L"; override val userHome = "H"
        }
        override val env = object : EnvReader { override fun get(name: String): String? = null }
        override val tokenVault: TokenVault = InMemoryTokenVault()
        override val installationIdentity = object : InstallationIdentity { override fun installationId(): String? = id }
        override val singleInstance = object : SingleInstanceGuard { override fun tryAcquire() = true; override fun release() {} }
        override val tray = object : TrayHost {
            override fun show(icon: RasterImage, tooltip: String) {}
            override fun update(icon: RasterImage, tooltip: String) {}
            override fun remove() {}
            override fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit) = Registration {}
        }
        override val hotkeys = object : HotkeyService {
            override fun register(chord: HotkeyChord, onPressed: () -> Unit) = HotkeyRegistrationResult.Conflict(0)
        }
        override val idle = object : IdleSource {
            override fun lastInput(kinds: Set<InputKind>): Instant? = null
            override fun addListener(listener: (kind: InputKind, at: Instant) -> Unit) = Registration {}
        }
        override val power = object : PowerEvents { override fun addListener(listener: (PowerEvent) -> Unit) = Registration {} }
        override val session = object : SessionEvents { override fun addListener(listener: (SessionEvent) -> Unit) = Registration {} }
        override val loginItem: LoginItem? = null
    }

    @Test
    fun deviceIdIsWinPrefixedOnlyWhenIdentityIsConfirmed() {
        assertEquals("win:43c6f224-3251-5e0a-b887-c5ccf28a2f96", AppGraph(FakePlatform("43C6F224-3251-5E0A-B887-C5CCF28A2F96")).deviceId)
        // 신원이 없으면 device_id 도 없다 → 기기 단위 쓰기 0(G §5-1 #6).
        assertNull(AppGraph(FakePlatform(null)).deviceId)
    }

    @Test
    fun clientIdentityComesFromGeneratedBuildIdentity() {
        val g = AppGraph(FakePlatform(null))
        assertEquals("windows", g.clientIdentity.platform.wire)
    }

    @Test
    fun launchOptions() {
        assertEquals(LaunchOptions(autostart = true, selfcheck = false, unknown = emptyList()), LaunchOptions.parse(arrayOf("--autostart")))
        assertEquals(LaunchOptions(autostart = false, selfcheck = true, unknown = listOf("--x")), LaunchOptions.parse(arrayOf("--selfcheck", "--x")))
        assertEquals(LaunchOptions(autostart = false, selfcheck = false, unknown = emptyList()), LaunchOptions.parse(emptyArray()))
    }

    @Test
    fun hostOsDetection() {
        assertTrue(HostOs.isWindows("Windows 11"))
        assertTrue(HostOs.isWindows("Windows Server 2025"))
        assertFalse(HostOs.isWindows("Mac OS X"))
        assertFalse(HostOs.isWindows("Linux"))
        assertFalse(HostOs.isWindows(null))
    }

    @Test
    fun jnaBootstrapOnlyWhenTheDllShipsWithThePackage() {
        val dir = "C:\\Program Files\\AingCheck\\app\\resources"
        val dll = File(dir, "jnidispatch.dll").path
        assertEquals(
            mapOf("jna.boot.library.path" to dir, "jna.nounpack" to "true", "jna.nosys" to "true"),
            JnaBootstrap.decide(dir) { it == dll },
        )
        // DLL 이 없는데 nounpack 을 켜면 JNA 가 아예 못 뜬다 → 아무것도 바꾸지 않는다.
        assertEquals(emptyMap(), JnaBootstrap.decide(dir) { false })
        assertEquals(emptyMap(), JnaBootstrap.decide(null) { true })
    }

    @Test
    fun startupApprovedKnownShapes() {
        assertEquals(false, StartupApproved.disabledByUser(byteArrayOf(0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        assertEquals(true, StartupApproved.disabledByUser(byteArrayOf(0x03, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)))
        assertEquals(false, StartupApproved.disabledByUser(byteArrayOf(0x06)))
        assertEquals(true, StartupApproved.disabledByUser(byteArrayOf(0x07)))
        assertNull(StartupApproved.disabledByUser(null))
        assertNull(StartupApproved.disabledByUser(byteArrayOf()))
        assertNull(StartupApproved.disabledByUser(byteArrayOf(0x09)), "모르는 꼴은 '건드리지 않음'으로")
    }

    @Test
    fun taskbarThemeRegistryValue() {
        assertEquals(TaskbarTheme.LIGHT, TaskbarThemeProbe.fromRegistryValue(1))
        assertEquals(TaskbarTheme.DARK, TaskbarThemeProbe.fromRegistryValue(0))
        assertEquals(TaskbarTheme.DARK, TaskbarThemeProbe.fromRegistryValue(null))
    }
}
