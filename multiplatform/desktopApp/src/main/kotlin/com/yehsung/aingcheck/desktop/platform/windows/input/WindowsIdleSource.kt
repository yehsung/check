// 원본: Sources/check/CheckWorkNudge.swift:72-77 @ a63fea2 (의미 있는 입력만) · Sources/check/WorkTimerStore.swift:2277-2299 @ a63fea2
//       (관측값은 단조 증가만, 미래 시각은 보내지 않는다) · 설계 D§5-1
//
// 전역 입력 **시각**(내용 아님). 숨은 창에 RegisterRawInputDevices(키보드·마우스, RIDEV_INPUTSINK — 앞에 없어도 받음)를 건다.
// 저수준 훅(WH_*_LL)은 쓰지 않는다: 콜백이 늦으면 시스템이 훅을 조용히 떼고, 백신이 키로거 꼴로 의심한다(D§5-1).
// Raw Input 등록이 실패하면 GetLastInputInfo 로 떨어진다 — 종류를 가르지 못하므로 [mode] 가 LAST_INPUT_INFO 이고
// 어느 종류를 물어도 "아무 입력" 시각을 돌려준다(진단 input_kind=any, 의미 차이는 D§5-1 에 적었다).
// 1000Hz 마우스 이동의 비용(D-E05)은 VM 에서 잰다. 이동 건은 분류 직후 버리고 리스너에만 알린다.
package com.yehsung.aingcheck.desktop.platform.windows.input

import com.sun.jna.Memory
import com.sun.jna.Native
import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.IntByReference
import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.foundation.platform.desktop.InputKind
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.jna.RAWINPUTDEVICE
import com.yehsung.aingcheck.desktop.platform.windows.jna.User32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import java.util.EnumMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executor
import kotlin.time.Clock
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Instant

class WindowsIdleSource(
    private val thread: Win32MessageThread,
    private val clock: Clock,
    private val events: Executor = Executor { it.run() },
) : IdleSource, AutoCloseable {
    enum class Mode { NOT_STARTED, RAW_INPUT, LAST_INPUT_INFO }

    @Volatile var mode: Mode = Mode.NOT_STARTED
        private set

    /** Raw Input 등록이 실패했을 때의 Win32 오류 코드(진단). */
    @Volatile var registrationError: Int = 0
        private set

    private val latest = EnumMap<InputKind, Instant>(InputKind::class.java)
    private val lock = Any()
    private val listeners = CopyOnWriteArrayList<(InputKind, Instant) -> Unit>()
    private var handler: Registration? = null

    /** 메시지 스레드에서 Raw Input 을 등록한다. 실패하면 GetLastInputInfo 모드로 내려간다. 멱등. */
    fun start(): Mode {
        if (mode != Mode.NOT_STARTED) return mode
        handler = thread.addHandler(Win32.WM_INPUT) { _, _, _, lParam ->
            onRawInput(lParam.toPointer())
            null // RIM_INPUT 정리를 위해 DefWindowProc 까지 간다(WM_INPUT 문서)
        }
        val ok = thread.call { hwnd ->
            val devices = devices(hwnd, Win32.RIDEV_INPUTSINK)
            val r = User32X.INSTANCE.RegisterRawInputDevices(devices, devices.size, devices[0].size())
            if (!r) registrationError = Native.getLastError()
            r
        }
        mode = if (ok) Mode.RAW_INPUT else Mode.LAST_INPUT_INFO
        if (!ok) {
            handler?.close()
            handler = null
        }
        return mode
    }

    /**
     * OS 가 실제로 이 프로세스에 등록해 둔 Raw Input 장치(용도 페이지·용도·깃발) — 등록 성공을 OS 쪽에서 다시 확인하는 길.
     * 메시지 스레드에서 GetRegisteredRawInputDevices 를 부른다.
     */
    fun registeredDevices(): List<Triple<Int, Int, Int>> = thread.call {
        val count = IntByReference(0)
        val size = RAWINPUTDEVICE().size()
        User32X.INSTANCE.GetRegisteredRawInputDevices(null, count, size)
        if (count.value <= 0) return@call emptyList()
        @Suppress("UNCHECKED_CAST")
        val arr = RAWINPUTDEVICE().toArray(count.value) as Array<RAWINPUTDEVICE>
        val n = User32X.INSTANCE.GetRegisteredRawInputDevices(arr, count, size)
        if (n <= 0) return@call emptyList()
        (0 until n).map { i ->
            arr[i].read()
            Triple(arr[i].usUsagePage.toInt() and 0xFFFF, arr[i].usUsage.toInt() and 0xFFFF, arr[i].dwFlags)
        }
    }

    private fun devices(hwnd: com.sun.jna.platform.win32.WinDef.HWND?, flags: Int): Array<RAWINPUTDEVICE> {
        @Suppress("UNCHECKED_CAST")
        val arr = RAWINPUTDEVICE().toArray(2) as Array<RAWINPUTDEVICE>
        arr[0].usUsagePage = Win32.HID_USAGE_PAGE_GENERIC.toShort()
        arr[0].usUsage = Win32.HID_USAGE_GENERIC_KEYBOARD.toShort()
        arr[0].dwFlags = flags
        arr[0].hwndTarget = hwnd
        arr[1].usUsagePage = Win32.HID_USAGE_PAGE_GENERIC.toShort()
        arr[1].usUsage = Win32.HID_USAGE_GENERIC_MOUSE.toShort()
        arr[1].dwFlags = flags
        arr[1].hwndTarget = hwnd
        arr.forEach { it.write() }
        return arr
    }

    private fun onRawInput(hRawInput: com.sun.jna.Pointer?) {
        val size = IntByReference(0)
        val headerSize = Win32.rawInputHeaderSize()
        User32X.INSTANCE.GetRawInputData(hRawInput, Win32.RID_INPUT, null, size, headerSize)
        val n = size.value
        if (n <= 0 || n > 4096) return
        val mem = Memory(n.toLong())
        val got = User32X.INSTANCE.GetRawInputData(hRawInput, Win32.RID_INPUT, mem, size, headerSize)
        if (got <= 0) return
        val kind = RawInputClassifier.classify(mem.getByteArray(0, got), Native.POINTER_SIZE) ?: return
        record(kind, clock.now())
    }

    /** 관측 한 건. 종류별로 단조 증가만 한다(늦게 처리된 앞 시각이 뒤 시각을 덮지 않는다). */
    internal fun record(kind: InputKind, at: Instant) {
        synchronized(lock) {
            val prev = latest[kind]
            if (prev == null || at > prev) latest[kind] = at
        }
        for (l in listeners) events.execute { l(kind, at) }
    }

    override fun lastInput(kinds: Set<InputKind>): Instant? {
        val now = clock.now()
        val seen = when (mode) {
            Mode.LAST_INPUT_INFO -> lastInputInfoInstant(now)
            else -> synchronized(lock) { kinds.mapNotNull { latest[it] }.maxOrNull() }
        } ?: return null
        // 미래 시각은 보내지 않는다(맥 WorkTimerStore.swift:2277-2299).
        return if (seen > now) now else seen
    }

    override fun addListener(listener: (kind: InputKind, at: Instant) -> Unit): Registration {
        listeners += listener
        return Registration { listeners -= listener }
    }

    private fun lastInputInfoInstant(now: Instant): Instant? {
        val lii = WinUser.LASTINPUTINFO()
        lii.cbSize = lii.size()
        if (!User32.INSTANCE.GetLastInputInfo(lii)) return null
        return LastInputTicks.toInstant(now, Kernel32.INSTANCE.GetTickCount().toLong(), lii.dwTime.toLong())
    }

    override fun close() {
        if (mode == Mode.RAW_INPUT && thread.isAlive) {
            thread.call {
                val devices = devices(null, Win32.RIDEV_REMOVE)
                User32X.INSTANCE.RegisterRawInputDevices(devices, devices.size, devices[0].size())
            }
        }
        handler?.close()
        handler = null
        listeners.clear()
    }
}

/** GetLastInputInfo 의 틱(부호 없는 32비트 ms, 49.7일마다 감김) → 시각. 순수 함수. */
object LastInputTicks {
    fun toInstant(now: Instant, tickNow: Long, lastInputTick: Long): Instant {
        val elapsed = (tickNow - lastInputTick) and 0xFFFFFFFFL
        return now - elapsed.milliseconds
    }
}
