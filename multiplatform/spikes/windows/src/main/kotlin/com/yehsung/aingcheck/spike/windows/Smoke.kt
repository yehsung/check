package com.yehsung.aingcheck.spike.windows

import com.sun.jna.Memory
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.WString
import com.sun.jna.platform.win32.Crypt32Util
import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinCrypt
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.IntByReference
import java.util.concurrent.atomic.AtomicReference

/**
 * G §2-3 W0-e ①(A-X14·D-E24): 러너·VM 에서 JNA Win32 호출이 실제로 되는지.
 * 각 검사는 "불렀다"가 아니라 결과를 잰다: 단축키는 같은 조합을 두 번 등록해 겹침 실패 코드까지, DPAPI 는 틀린 엔트로피의 실패까지.
 */
object Smoke {
    const val MOD_ALT = 0x1
    const val MOD_CONTROL = 0x2
    const val MOD_SHIFT = 0x4
    const val MOD_NOREPEAT = 0x4000
    const val VK_SPACE = 0x20
    const val ERROR_HOTKEY_ALREADY_REGISTERED = 1409
    const val WS_POPUP = 0x80000000.toInt()
    const val WS_EX_TOOLWINDOW = 0x00000080

    fun run(): List<Check> {
        val checks = mutableListOf<Check>()
        checks += session()
        checks += lastInput()
        checks += dpapi()
        checks += windowThreadChecks()
        return checks
    }

    /** A-X14·D-E24: 대화형 세션인가. 판정은 기록용(required=false) — 결과가 "VM 전용 태그" 여부를 정한다. */
    fun session(): Check = guard("session", required = false) {
        val k = Kernel32X.INSTANCE
        val u = User32X.INSTANCE
        val pid = k.GetCurrentProcessId()
        val sid = IntByReference()
        val sidOk = k.ProcessIdToSessionId(pid, sid)
        val console = k.WTSGetActiveConsoleSessionId()
        val winsta = u.GetProcessWindowStation()
        val flags = USEROBJECTFLAGS()
        val flagsOk = u.GetUserObjectInformationW(winsta, User32X.UOI_FLAGS, flags.pointer, flags.size(), IntByReference())
        flags.read()
        val winstaName = objectName(winsta)
        val desktopName = objectName(u.GetThreadDesktop(k.GetCurrentThreadId()))
        val visible = flagsOk && (flags.dwFlags and User32X.WSF_VISIBLE) != 0
        val interactive = visible && sidOk && sid.value != 0
        Check(
            "session", ok = sidOk && flagsOk, required = false,
            detail = linkedMapOf(
                "processSessionId" to (if (sidOk) sid.value else null),
                "activeConsoleSessionId" to console.toLong().and(0xFFFFFFFFL),
                "windowStation" to winstaName,
                "windowStationVisible" to visible,
                "desktop" to desktopName,
                "interactive" to interactive,
                "user" to System.getProperty("user.name"),
            ),
        )
    }

    private fun objectName(h: Pointer?): String? {
        if (h == null) return null
        val buf = Memory(512)
        buf.clear()
        val ok = User32X.INSTANCE.GetUserObjectInformationW(h, User32X.UOI_NAME, buf, 512, IntByReference())
        return if (ok) buf.getWideString(0) else "error:${Native.getLastError()}"
    }

    /** GetLastInputInfo: 호출 성공 + 틱 값 기록. 세션 0 이면 dwTime 이 0 이거나 움직이지 않는다(기록). */
    fun lastInput(): Check = guard("getLastInputInfo") {
        val lii = WinUser.LASTINPUTINFO()
        lii.cbSize = lii.size()
        val ok = User32.INSTANCE.GetLastInputInfo(lii)
        val err = if (ok) 0 else Native.getLastError()
        val tick = Kernel32.INSTANCE.GetTickCount()
        val dwTime = lii.dwTime.toLong() and 0xFFFFFFFFL
        val tickU = tick.toLong() and 0xFFFFFFFFL
        Check(
            "getLastInputInfo", ok = ok,
            detail = linkedMapOf(
                "cbSize" to lii.cbSize,
                "dwTime" to dwTime,
                "tickCount" to tickU,
                "idleMs" to (if (ok) ((tickU - dwTime) and 0xFFFFFFFFL) else null),
                "lastError" to err,
            ),
        )
    }

    /** DPAPI 왕복 + 짝(틀린 엔트로피는 실패해야 한다). 짝이 없으면 "복호화가 늘 원문을 돌려주는" 결함을 못 잡는다. */
    fun dpapi(): Check = guard("dpapi") {
        val plain = "aing-check DPAPI 왕복 시험 · ${System.nanoTime()}".toByteArray(Charsets.UTF_8)
        val entropy = "aing-check.v1|spike".toByteArray(Charsets.UTF_8)
        val flags = WinCrypt.CRYPTPROTECT_UI_FORBIDDEN
        val sealed = Crypt32Util.cryptProtectData(plain, entropy, flags, "aingspike", null)
        val back = Crypt32Util.cryptUnprotectData(sealed, entropy, flags, null)
        val roundTrip = back.contentEquals(plain)
        val differs = !sealed.contentEquals(plain) && sealed.size > plain.size
        var wrongEntropyRejected = false
        var wrongEntropyError: String? = null
        try {
            Crypt32Util.cryptUnprotectData(sealed, "aing-check.v1|other".toByteArray(), flags, null)
        } catch (e: Exception) {
            wrongEntropyRejected = true
            wrongEntropyError = e.message
        }
        Check(
            "dpapi", ok = roundTrip && differs && wrongEntropyRejected,
            detail = linkedMapOf(
                "plainBytes" to plain.size,
                "sealedBytes" to sealed.size,
                "roundTrip" to roundTrip,
                "ciphertextDiffers" to differs,
                "wrongEntropyRejected" to wrongEntropyRejected,
                "wrongEntropyError" to wrongEntropyError,
            ),
        )
    }

    /**
     * 숨은 최상위 창(WS_POPUP·WS_EX_TOOLWINDOW, ShowWindow 하지 않음)을 전용 스레드에서 만들고
     * 같은 스레드에서 단축키·트레이를 다룬다(D §2-2: RegisterHotKey 는 창을 만든 스레드에서만).
     */
    fun windowThreadChecks(): List<Check> {
        val result = AtomicReference<List<Check>>()
        val t = Thread({
            result.set(
                try {
                    onWindowThread()
                } catch (e: Throwable) {
                    listOf(Check("windowThread", ok = false, detail = mapOf("error" to e.toString())))
                },
            )
        }, "aingspike-win32")
        t.isDaemon = true
        t.start()
        t.join(30_000)
        return result.get() ?: listOf(Check("windowThread", ok = false, detail = mapOf("error" to "30초 안에 끝나지 않았다")))
    }

    private fun onWindowThread(): List<Check> {
        val u = User32.INSTANCE
        val hInst = Kernel32.INSTANCE.GetModuleHandle(null)
        val className = "AingSpikeHidden${ProcessHandle.current().pid()}"
        val proc = WinUser.WindowProc { hwnd, msg, wParam, lParam -> u.DefWindowProc(hwnd, msg, wParam, lParam) }
        val wc = WinUser.WNDCLASSEX()
        wc.hInstance = hInst
        wc.lpfnWndProc = proc
        wc.lpszClassName = className
        val atom = u.RegisterClassEx(wc)
        val hwnd = u.CreateWindowEx(WS_EX_TOOLWINDOW, className, "AingSpike", WS_POPUP, 0, 0, 0, 0, null, null, hInst, null)
        val windowCheck = Check(
            "hiddenWindow", ok = hwnd != null,
            detail = linkedMapOf(
                "atom" to atom?.toInt(),
                "hwnd" to (hwnd != null),
                "visible" to (hwnd != null && u.IsWindowVisible(hwnd)),
                "lastError" to (if (hwnd == null) Native.getLastError() else 0),
                "taskbarCreatedMsg" to User32X.INSTANCE.RegisterWindowMessageW(WString("TaskbarCreated")),
            ),
        )
        if (hwnd == null) return listOf(windowCheck)
        try {
            return listOf(windowCheck, hotkey(hwnd), notifyIcon(hwnd))
        } finally {
            u.DestroyWindow(hwnd)
            u.UnregisterClass(className, hInst)
            // 콜백이 GC 되지 않게 끝까지 붙잡는다.
            java.lang.ref.Reference.reachabilityFence(proc)
            java.lang.ref.Reference.reachabilityFence(wc)
        }
    }

    /** 기본 조합(Ctrl+Alt+Shift+Space, D §6)을 등록 → 같은 조합 두 번째 등록은 1409 로 실패해야 한다 → 해제. */
    fun hotkey(hwnd: WinDef.HWND): Check {
        val u = User32.INSTANCE
        val mods = MOD_CONTROL or MOD_ALT or MOD_SHIFT or MOD_NOREPEAT
        val first = u.RegisterHotKey(hwnd, 0xA101, mods, VK_SPACE)
        val firstErr = if (first) 0 else Native.getLastError()
        val second = u.RegisterHotKey(hwnd, 0xA102, mods, VK_SPACE)
        val secondErr = if (second) 0 else Native.getLastError()
        val unregSecond = if (second) u.UnregisterHotKey(hwnd.pointer, 0xA102) else true
        val unreg = if (first) u.UnregisterHotKey(hwnd.pointer, 0xA101) else false
        val conflictDetected = !second && secondErr == ERROR_HOTKEY_ALREADY_REGISTERED
        return Check(
            "registerHotKey", ok = first && conflictDetected && unreg && unregSecond,
            detail = linkedMapOf(
                "combo" to "Ctrl+Alt+Shift+Space|NOREPEAT",
                "firstRegistered" to first,
                "firstError" to firstErr,
                "duplicateRegistered" to second,
                "duplicateError" to secondErr,
                "conflictDetected" to conflictDetected,
                "unregistered" to unreg,
            ),
        )
    }

    /** Shell_NotifyIcon v4: 추가 → 버전 설정 → 위치 조회(기록) → 삭제. 구조체 크기 976 도 단언한다. */
    fun notifyIcon(hwnd: WinDef.HWND): Check {
        val s = Shell32X.INSTANCE
        val data = NOTIFYICONDATAW()
        val size = data.size()
        data.cbSize = size
        data.hWnd = hwnd
        data.uID = 1
        data.uFlags = Shell32X.NIF_MESSAGE or Shell32X.NIF_ICON or Shell32X.NIF_TIP or Shell32X.NIF_SHOWTIP
        data.uCallbackMessage = 0x8001 // WM_APP + 1
        data.hIcon = User32X.INSTANCE.LoadIconW(null, Pointer(User32X.IDI_APPLICATION))
        data.setTip("aing-check spike")
        val sizeOk = Native.POINTER_SIZE != 8 || size == NOTIFYICONDATAW.EXPECTED_SIZE_64
        val added = s.Shell_NotifyIconW(Shell32X.NIM_ADD, data)
        val addErr = if (added) 0 else Native.getLastError()
        var versionSet = false
        var rectHr: Int? = null
        var rect: List<Int>? = null
        var deleted = false
        if (added) {
            data.uVersion = Shell32X.NOTIFYICON_VERSION_4
            versionSet = s.Shell_NotifyIconW(Shell32X.NIM_SETVERSION, data)
            val id = NOTIFYICONIDENTIFIER()
            id.cbSize = id.size()
            id.hWnd = hwnd
            id.uID = 1
            val r = WinDef.RECT()
            rectHr = s.Shell_NotifyIconGetRect(id, r)
            if (rectHr == 0) rect = listOf(r.left, r.top, r.right, r.bottom)
            deleted = s.Shell_NotifyIconW(Shell32X.NIM_DELETE, data)
        }
        return Check(
            "shellNotifyIcon", ok = sizeOk && added && versionSet && deleted,
            detail = linkedMapOf(
                "structSize" to size,
                "structSizeOk" to sizeOk,
                "iconLoaded" to (data.hIcon != null),
                "added" to added,
                "addError" to addErr,
                "versionSet" to versionSet,
                "getRectHresult" to rectHr?.let { "0x" + Integer.toHexString(it) },
                "rect" to rect,
                "deleted" to deleted,
            ),
        )
    }

    private fun guard(id: String, required: Boolean = true, body: () -> Check): Check =
        try {
            body()
        } catch (e: Throwable) {
            Check(id, ok = false, required = required, detail = mapOf("error" to e.toString()))
        }
}
