// OS 배선(OsWiring) 시험 — 단축키 → 근무 토글(맥 WorkShortcut.swift:331-406 · canToggle 은 매개) + OS 예약 조합 거름(W-13 #3) ·
// 플라이아웃 열림 = appDidBecomeActive(기기 재등록 1시간 스로틀, 실행·로그인과 같은 register_device) · 자동 실행 StartupTask(W-13 #6) ·
// 종료 kv flush(W-13 #2). 픽스처는 합성뿐(MockEngine 녹음 — WiringTestRig).
@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring.os

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyRegistrationResult
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.desktop.pages.desktopsettings.HotkeyRegistrationStatus
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy
import com.yehsung.aingcheck.desktop.platform.windows.login.StartupTaskLoginItem
import com.yehsung.aingcheck.desktop.platform.windows.login.StartupTaskPort
import com.yehsung.aingcheck.desktop.platform.windows.login.StartupTaskState
import com.yehsung.aingcheck.desktop.platform.windows.store.FileDesktopKeyValueStore
import com.yehsung.aingcheck.desktop.wiring.MemoryPrefs
import com.yehsung.aingcheck.desktop.wiring.OsDeps
import com.yehsung.aingcheck.desktop.wiring.OsWiring
import com.yehsung.aingcheck.desktop.wiring.WindowsDeviceRegistration
import com.yehsung.aingcheck.desktop.wiring.WiringTestRig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.queue.DesktopWorkQueue
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.minutes
import kotlin.time.ExperimentalTime

class OsWiringTest {
    private class FakeHotkeys : HotkeyService {
        val registered = mutableListOf<HotkeyChord>()
        val live = mutableMapOf<HotkeyChord, () -> Unit>()
        override fun register(chord: HotkeyChord, onPressed: () -> Unit): HotkeyRegistrationResult {
            registered += chord
            live[chord] = onPressed
            return HotkeyRegistrationResult.Registered(Registration { live.remove(chord) })
        }
        fun press(chord: HotkeyChord) = live.getValue(chord).invoke()
    }

    /** StartupTask 한 개(합성). DisabledByUser 면 RequestEnableAsync 가 되살리지 못한다(Windows 규칙). */
    private class FakeStartupTask(var state: Int) : StartupTaskPort {
        val calls = mutableListOf<String>()
        override fun state(): Int = state
        override fun requestEnable(): Int {
            calls += "enable"
            if (state == StartupTaskState.DISABLED) state = StartupTaskState.ENABLED
            return state
        }
        override fun disable() {
            calls += "disable"
            if (state == StartupTaskState.ENABLED) state = StartupTaskState.DISABLED
        }
    }

    private class Rig(
        val test: TestScope,
        val chord: MutableStateFlow<HotkeyChord?> = MutableStateFlow(HotkeyPolicy.DEFAULT),
        var allowed: Boolean = true,
        startup: Int = StartupTaskState.ENABLED,
        launchDefault: Boolean = true,
    ) {
        val wiringRig = WiringTestRig(test)
        val hotkeys = FakeHotkeys()
        val task = FakeStartupTask(startup)
        val launch = MutableStateFlow(launchDefault)
        val flyout = MutableStateFlow(false)
        val statuses = mutableListOf<HotkeyRegistrationStatus>()
        var toggles = 0
        var rejections = 0
        var actives = 0
        val dispatcher = StandardTestDispatcher(test.testScheduler)
        val os = OsWiring(
            OsDeps(
                hotkeys = hotkeys,
                hotkeyChord = chord,
                noteHotkeyStatus = { statuses += it },
                canToggleWork = { allowed },
                toggleWork = { toggles++ },
                onHotkeyRejected = { rejections++ },
                loginItem = StartupTaskLoginItem(task),
                launchAtLogin = launch,
                reflectLaunchAtLogin = { launch.value = it },
                flyoutOpen = flyout,
                appDidBecomeActive = { actives++ },
                kv = InMemoryDesktopKeyValueStore(),
                registerContext = dispatcher,
                ioContext = dispatcher,
            ),
        )

        fun close() {
            os.stop()
            wiringRig.close()
        }
    }

    private inline fun Rig.use(block: (Rig) -> Unit) {
        try {
            block(this)
        } finally {
            close()
        }
    }

    @Test
    fun 단축키_누름은_canToggle_참일_때만_근무를_토글한다() = runTest(timeout = 1.minutes) {
        Rig(this).use { r ->
            r.os.start(r.wiringRig.scope); runCurrent()
            assertEquals(HotkeyRegistrationStatus.ACTIVE, r.statuses.last())
            // 음성 대조 먼저(거부는 연타 가드 시각을 남기지 않는다): 로그아웃·팀 없음·canSync 거짓이면 토글 0, 거부 알림 1.
            r.allowed = false
            r.hotkeys.press(HotkeyPolicy.DEFAULT)
            assertEquals(0, r.toggles)
            assertEquals(1, r.rejections)
            r.allowed = true
            r.hotkeys.press(HotkeyPolicy.DEFAULT)
            assertEquals(1, r.toggles)
            assertEquals(1, r.rejections)
        }
    }

    @Test
    fun OS_예약_조합은_등록_시도_0이고_겹쳐요로_보인다() = runTest(timeout = 1.minutes) {
        val ctrlAltDel = HotkeyChord(ctrl = true, alt = true, shift = false, win = false, keyCode = HotkeyPolicy.VK_DELETE)
        Rig(this, chord = MutableStateFlow(ctrlAltDel)).use { r ->
            r.os.start(r.wiringRig.scope); runCurrent()
            assertTrue(r.hotkeys.registered.isEmpty(), "RegisterHotKey 를 부르지도 않는다 — ${r.hotkeys.registered}")
            assertEquals(HotkeyRegistrationStatus.CONFLICT, r.statuses.last())
            // 음성 대조: 예약이 아닌 조합으로 바꾸면 등록된다.
            r.chord.value = HotkeyPolicy.DEFAULT; runCurrent()
            assertEquals(listOf(HotkeyPolicy.DEFAULT), r.hotkeys.registered)
            assertEquals(HotkeyRegistrationStatus.ACTIVE, r.statuses.last())
        }
    }

    @Test
    fun 단축키_끔이면_등록_0() = runTest(timeout = 1.minutes) {
        Rig(this, chord = MutableStateFlow(null)).use { r ->
            r.os.start(r.wiringRig.scope); runCurrent()
            assertTrue(r.hotkeys.registered.isEmpty())
            assertEquals(HotkeyRegistrationStatus.OFF, r.statuses.last())
            assertEquals(0, r.wiringRig.requests.size, "단축키 배선은 서버를 치지 않는다")
        }
    }

    @Test
    fun 플라이아웃이_열리는_순간마다_appDidBecomeActive_한_번() = runTest(timeout = 1.minutes) {
        Rig(this).use { r ->
            r.os.start(r.wiringRig.scope); runCurrent()
            assertEquals(0, r.actives, "닫힌 채 시작 = 0")
            r.flyout.value = true; runCurrent()
            assertEquals(1, r.actives)
            r.flyout.value = false; runCurrent()
            assertEquals(1, r.actives, "닫힘은 세지 않는다")
            r.flyout.value = true; runCurrent()
            assertEquals(2, r.actives)
        }
    }

    /** 실물 SessionStore + WindowsDeviceRegistration: 실행·로그인과 같은 register_device, 1시간 스로틀. */
    @Test
    fun 플라이아웃_열림_기기_재등록은_1시간_스로틀_로그아웃이면_0() = runTest(timeout = 1.minutes) {
        val rig = WiringTestRig(this)
        rig.answer = { path ->
            when {
                path.endsWith("/rpc/register_device") ->
                    """{"status":"ok","device_id":"${WiringTestRig.DEVICE}","push_prefs":{"message":true,"gomoku_invite":true,"feedback_reply":true}}"""
                path.endsWith("/rpc/unregister_device") -> """{"status":"ok"}"""
                path.endsWith("/rpc/take_pokes") -> "[]"
                else -> null
            }
        }
        val store = SessionStore(
            service = rig.service,
            vault = InMemoryTokenVault(),
            prefs = MemoryPrefs(),
            appInfo = AppInfo(ClientIdentity(ClientPlatform.WINDOWS, 7L, "0.1.0"), "Windows 11"),
            installationIdentity = object : InstallationIdentity { override fun installationId(): String = WiringTestRig.INSTALLATION },
            clock = rig.sessionClock,
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire(): Boolean = true
                override fun release() {}
            },
            parentScope = rig.scope,
            newCleanupID = { "cleanup-1" },
            deviceRegistration = WindowsDeviceRegistration,
        )
        val flyout = MutableStateFlow(false)
        val os = OsWiring(
            OsDeps(
                hotkeys = FakeHotkeys(), hotkeyChord = flowOf(null), canToggleWork = { false }, toggleWork = {},
                loginItem = null, flyoutOpen = flyout, appDidBecomeActive = store::appDidBecomeActive,
                kv = InMemoryDesktopKeyValueStore(),
                registerContext = StandardTestDispatcher(testScheduler), ioContext = StandardTestDispatcher(testScheduler),
            ),
        )
        try {
            os.start(rig.scope); runCurrent()
            // 깃발 꺼짐(로그아웃): 열어도 register_device 0.
            flyout.value = true; runCurrent(); flyout.value = false; runCurrent()
            advanceTimeBy(1_000); runCurrent()
            assertEquals(0, rig.count("/rpc/register_device"), "로그아웃이면 0 — ${rig.requests}")

            store.adoptSignedInSession(SupabaseSession("tok-${WiringTestRig.USER}", "ref-${WiringTestRig.USER}", WiringTestRig.USER), "os@aing.example")
            advanceTimeBy(1_000); runCurrent()
            assertEquals(1, rig.count("/rpc/register_device"), "로그인 = 등록 1")
            flyout.value = true; runCurrent(); flyout.value = false; runCurrent()
            advanceTimeBy(1_000); runCurrent()
            assertEquals(1, rig.count("/rpc/register_device"), "1시간 안에 열기 = 스로틀 — ${rig.requests}")
            advanceTimeBy(61 * 60_000L); runCurrent()
            flyout.value = true; runCurrent()
            advanceTimeBy(1_000); runCurrent()
            assertEquals(2, rig.count("/rpc/register_device"), "1시간 넘어 열기 = 맥 appDidBecomeActive 와 같은 재등록")
            assertTrue(rig.requests.none { it.contains("register_device_fcm") })
        } finally {
            os.stop()
            rig.close()
        }
    }

    @Test
    fun 자동_실행_MSIX_끄면_StartupTask_Disable__켜면_그대로() = runTest(timeout = 1.minutes) {
        Rig(this, startup = StartupTaskState.ENABLED, launchDefault = true).use { r ->
            r.os.start(r.wiringRig.scope); runCurrent()
            assertEquals(LoginItemStatus.ON, r.os.loginItem.status.value)
            assertTrue(r.task.calls.isEmpty(), "이미 켜져 있으면 손대지 않는다 — ${r.task.calls}")
            r.launch.value = false; runCurrent()
            assertEquals(listOf("disable"), r.task.calls)
            assertEquals(LoginItemStatus.OFF, r.os.loginItem.status.value)
            r.launch.value = true; runCurrent()
            assertEquals(listOf("disable", "enable"), r.task.calls)
            assertEquals(LoginItemStatus.ON, r.os.loginItem.status.value)
        }
    }

    @Test
    fun 작업_관리자에서_끈_StartupTask_는_되살리지_않고_스위치만_맞춘다__메아리로_다시_끄지_않는다() = runTest(timeout = 1.minutes) {
        Rig(this, startup = StartupTaskState.DISABLED_BY_USER, launchDefault = true).use { r ->
            r.os.start(r.wiringRig.scope); runCurrent()
            assertEquals(LoginItemStatus.BLOCKED_BY_SYSTEM, r.os.loginItem.status.value)
            assertFalse(r.launch.value, "스위치가 거짓말하지 않게 실제(꺼짐)로")
            runCurrent()
            assertTrue(r.task.calls.isEmpty(), "되살리기도, 메아리 끔 적용도 없다 — ${r.task.calls}")
            // 사용자가 다시 켜면 다시 판정한다(같은 값이어도 메아리가 아니면).
            r.launch.value = true; runCurrent()
            assertEquals(LoginItemStatus.BLOCKED_BY_SYSTEM, r.os.loginItem.status.value)
        }
    }

    @Test
    fun 종료_kv_flush_는_묶음_창을_기다리지_않고_디스크에_쓴다() = runTest(timeout = 1.minutes) {
        val dir = Files.createTempDirectory("os-kv")
        val kv = FileDesktopKeyValueStore(dir.resolve("prefs.json"), debounceMillis = 60_000)
        val os = OsWiring(
            OsDeps(
                hotkeys = FakeHotkeys(), hotkeyChord = flowOf(null), canToggleWork = { false }, toggleWork = {},
                loginItem = null, flyoutOpen = flowOf(false), appDidBecomeActive = {}, kv = kv,
            ),
        )
        try {
            kv.putString("check.overlay.position", "1,2")
            assertTrue(kv.isDirty)
            os.flushKeyValueStore()
            assertFalse(kv.isDirty)
            assertTrue(Files.readString(dir.resolve("prefs.json")).contains("check.overlay.position"))
            // 닫힌 뒤의 늦은 put 도 바로 쓴다(근무 큐든 아니든).
            kv.putString(DesktopWorkQueue.pendingWorkQueueKey, "[]")
            assertFalse(kv.isDirty)
        } finally {
            kv.close()
            dir.toFile().deleteRecursively()
        }
    }
}
