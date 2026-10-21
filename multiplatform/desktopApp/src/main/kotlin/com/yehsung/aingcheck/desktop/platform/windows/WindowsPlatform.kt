// 원본: 없음(새 코드) — 설계 D§2-1(각 OS 기능은 인터페이스 뒤에) · A§2-1(Windows 전용 코드는 desktopApp platform/windows, 실행 중 OS 를 보고 고른다)
// Windows OS 층을 한 번에 짓는다. 앱 조립(AppGraph)이 이것을 [com.yehsung.aingcheck.desktop.DesktopPlatform] 으로 받는다.
// 이 클래스는 **창을 보이지 않는다**: 숨은 메시지 창만 만들고, 트레이 아이콘은 껍데기(W3-c1)가 show 를 부를 때 붙는다.
package com.yehsung.aingcheck.desktop.platform.windows

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.desktop.DesktopPlatform
import com.yehsung.aingcheck.desktop.platform.windows.env.WindowsEnvironment
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.WindowsHotkeyService
import com.yehsung.aingcheck.desktop.platform.windows.identity.RegistryMachineIdentitySource
import com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsInstallationIdentity
import com.yehsung.aingcheck.desktop.platform.windows.input.WindowsIdleSource
import com.yehsung.aingcheck.desktop.platform.windows.instance.WindowsSingleInstanceGuard
import com.yehsung.aingcheck.desktop.platform.windows.login.RunKeyLoginItem
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.platform.windows.paths.PackageIdentity
import com.yehsung.aingcheck.desktop.platform.windows.paths.WindowsAppPaths
import com.yehsung.aingcheck.desktop.platform.windows.power.DesktopPowerEvents
import com.yehsung.aingcheck.desktop.platform.windows.tray.WindowsTrayHost
import com.yehsung.aingcheck.desktop.platform.windows.vault.DpapiProtector
import com.yehsung.aingcheck.desktop.platform.windows.vault.FileTokenVault
import java.nio.file.Path
import java.util.concurrent.Executor
import kotlin.time.Clock

object HostOs {
    fun isWindows(osName: String? = System.getProperty("os.name")): Boolean = osName?.startsWith("Windows", ignoreCase = true) == true
}

class WindowsPlatform private constructor(
    val messageThread: Win32MessageThread,
    override val paths: WindowsAppPaths,
    val environment: WindowsEnvironment,
    override val tokenVault: TokenVault,
    override val installationIdentity: WindowsInstallationIdentity,
    override val singleInstance: WindowsSingleInstanceGuard,
    override val tray: WindowsTrayHost,
    override val hotkeys: WindowsHotkeyService,
    override val idle: WindowsIdleSource,
    val desktopEvents: DesktopPowerEvents,
    override val loginItem: RunKeyLoginItem?,
) : DesktopPlatform, AutoCloseable {
    override val env: EnvReader get() = environment
    override val power get() = desktopEvents
    override val session: SessionEvents get() = desktopEvents.sessionEvents

    override fun close() {
        runCatching { idle.close() }
        runCatching { hotkeys.close() }
        runCatching { tray.close() }
        runCatching { messageThread.close() }
        runCatching { singleInstance.release() }
    }

    companion object {
        /**
         * [guard] 는 Main 이 먼저 잡은 것을 넘긴다(세션 시작 전 필수 — 못 잡았으면 여기까지 오지 않는다).
         * [events] 는 화면 쪽 실행기(EDT). [executable] 은 Run 키 자동 실행에 쓸 런처 경로(MSIX 면 null — StartupTask 가 맡는다).
         */
        fun create(
            guard: WindowsSingleInstanceGuard,
            clock: Clock,
            events: Executor,
            executable: String?,
            env: WindowsEnvironment = WindowsEnvironment.system(),
        ): WindowsPlatform {
            val (pfn, _) = PackageIdentity.currentFamilyName()
            val paths = WindowsAppPaths.fromEnvironment(env, pfn)
            val vault = FileTokenVault(Path.of(paths.vaultDir), DpapiProtector())
            val identity = WindowsInstallationIdentity(RegistryMachineIdentitySource(), Path.of(paths.installationIdFile))
            val thread = Win32MessageThread.start()
            val tray = WindowsTrayHost(thread, events = events)
            val hotkeys = WindowsHotkeyService(thread, events)
            val idle = WindowsIdleSource(thread, clock, events).also { it.start() }
            val power = DesktopPowerEvents().also { it.install() }
            val login = if (pfn == null && executable != null) RunKeyLoginItem(executable) else null
            return WindowsPlatform(thread, paths, env, vault, identity, guard, tray, hotkeys, idle, power, login)
        }
    }
}
