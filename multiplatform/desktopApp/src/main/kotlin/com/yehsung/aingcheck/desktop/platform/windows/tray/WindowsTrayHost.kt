// 원본: 없음(새 코드) — 설계 D§3-1(Compose Tray 대신 Shell_NotifyIcon 직접: 한 번 클릭·아이콘 자리·키보드·TaskbarCreated),
//       W0-e 실측(NOTIFYICONDATAW 976B, NIM_ADD → SETVERSION v4 → GetRect → DELETE, arm64 러너는 OOBE 화면이 덮으면 0x80004005)
//
// - 모든 Shell_NotifyIcon 호출은 메시지 스레드에서 한다(콜백 창과 같은 스레드).
// - Explorer 가 다시 뜨면(TaskbarCreated 방송) 보이던 아이콘을 다시 붙인다(D§2-2). 그 메시지를 못 받는 message-only 창은 쓰지 않는다.
// - 로그인 직후처럼 작업 표시줄이 아직 없으면 NIM_ADD 가 실패한다 — 붙을 때까지 [retryIntervalMillis] 간격으로
//   [retryWindowMillis] 동안 다시 해 보고, 그 뒤로는 TaskbarCreated 를 기다린다(메시지 스레드를 재우지 않는다).
// - 클릭 리스너는 [events] 실행기에서 부른다(화면 쪽은 EDT 실행기를 넘긴다 — 메시지 스레드에서 오래 일하지 않는다, D§2-2).
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.sun.jna.Native
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.desktop.platform.windows.jna.NOTIFYICONDATAW
import com.yehsung.aingcheck.desktop.platform.windows.jna.NOTIFYICONIDENTIFIER
import com.yehsung.aingcheck.desktop.platform.windows.jna.Shell32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.User32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/** 마지막 트레이 조작의 결과(진단·시험용). */
data class TrayStatus(
    val wanted: Boolean,
    val added: Boolean,
    val versionSet: Boolean,
    val addAttempts: Int,
    val lastError: Int,
    /** TaskbarCreated 를 받아 다시 붙인 횟수. */
    val reattached: Int,
)

/** 화면 좌표 사각형(물리 픽셀). */
data class ScreenRect(val left: Int, val top: Int, val right: Int, val bottom: Int)

class WindowsTrayHost(
    private val thread: Win32MessageThread,
    private val iconId: Int = 1,
    private val callbackMessage: Int = Win32.WM_APP_TRAY,
    private val events: Executor = Executor { it.run() },
    private val retryIntervalMillis: Long = 1_000,
    private val retryWindowMillis: Long = 60_000,
) : TrayHost, AutoCloseable {
    // ---- 메시지 스레드 전용 상태 ----
    private var data: NOTIFYICONDATAW? = null
    private var hIcon: WinDef.HICON? = null
    private var wanted = false
    private var added = false
    private var versionSet = false
    private var attempts = 0
    private var lastError = 0
    private var reattached = 0
    private var retryDeadline = 0L

    private val clickListeners = CopyOnWriteArrayList<(TrayClick, Int, Int) -> Unit>()
    private val scheduler: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "aingcheck-tray-retry").apply { isDaemon = true }
    }
    private val registrations = listOf(
        thread.addHandler(callbackMessage) { _, _, wParam, lParam ->
            val ev = TrayCallbackDecoder.decode(wParam.toLong(), lParam.toLong())
            if (ev != null && ev.iconId == iconId) {
                for (l in clickListeners) events.execute { l(ev.click, ev.screenX, ev.screenY) }
            }
            WinDef.LRESULT(0)
        },
        thread.addHandler(thread.taskbarCreatedMessage) { _, _, _, _ ->
            onTaskbarCreated()
            null // 다른 처리기·DefWindowProc 도 받게 둔다(방송 메시지)
        },
    )

    init {
        // 콜백 메시지는 Explorer 가 보낸다 — 관리자로 돌 때도 받게 연다(보통 프로세스에서는 해가 없다).
        thread.call { hwnd -> runCatching { User32X.INSTANCE.ChangeWindowMessageFilterEx(hwnd, callbackMessage, Win32.MSGFLT_ALLOW, null) } }
    }

    override fun show(icon: RasterImage, tooltip: String) {
        thread.call { hwnd ->
            wanted = true
            replaceIcon(icon)
            val d = data ?: NOTIFYICONDATAW().also { data = it }
            d.cbSize = d.size()
            d.hWnd = hwnd
            d.uID = iconId
            d.uFlags = Win32.NIF_MESSAGE or Win32.NIF_ICON or Win32.NIF_TIP or Win32.NIF_SHOWTIP
            d.uCallbackMessage = callbackMessage
            d.hIcon = hIcon
            d.setTip(tooltip)
            if (added) modify() else {
                retryDeadline = System.nanoTime() + retryWindowMillis * 1_000_000
                tryAdd()
            }
        }
    }

    override fun update(icon: RasterImage, tooltip: String) {
        thread.call {
            val d = data ?: return@call
            replaceIcon(icon)
            d.hIcon = hIcon
            d.setTip(tooltip)
            if (added) modify()
        }
    }

    override fun remove() {
        thread.call {
            wanted = false
            val d = data
            if (added && d != null) {
                if (!Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_DELETE, d)) lastError = Native.getLastError()
            }
            added = false
            versionSet = false
            hIcon?.let { User32.INSTANCE.DestroyIcon(it) }
            hIcon = null
        }
    }

    override fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit): Registration {
        clickListeners += listener
        return Registration { clickListeners -= listener }
    }

    fun status(): TrayStatus = thread.call { TrayStatus(wanted, added, versionSet, attempts, lastError, reattached) }

    /**
     * 아이콘 자리(Shell_NotifyIconGetRect). 플라이아웃 배치의 입력. 아이콘이 없거나 실패면 null.
     * 숨김(넘침) 상태에서 무엇을 돌려주는지는 미확인(D-E02, VM).
     */
    fun iconRect(): ScreenRect? = thread.call { hwnd ->
        if (!added) return@call null
        val id = NOTIFYICONIDENTIFIER()
        id.cbSize = id.size()
        id.hWnd = hwnd
        id.uID = iconId
        val r = WinDef.RECT()
        if (Shell32X.INSTANCE.Shell_NotifyIconGetRect(id, r) == 0) ScreenRect(r.left, r.top, r.right, r.bottom) else null
    }

    private fun replaceIcon(icon: RasterImage) {
        val next = IconFactory.create(icon)
        hIcon?.let { User32.INSTANCE.DestroyIcon(it) }
        hIcon = next
    }

    private fun modify() {
        val d = data ?: return
        if (!Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_MODIFY, d)) lastError = Native.getLastError()
    }

    /** 메시지 스레드에서. 실패하면 재시도 창 안에서만 다음 시도를 예약한다. */
    private fun tryAdd() {
        val d = data ?: return
        if (!wanted || added) return
        attempts++
        if (Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_ADD, d)) {
            added = true
            lastError = 0
            d.uVersion = Win32.NOTIFYICON_VERSION_4
            versionSet = Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_SETVERSION, d)
            if (!versionSet) lastError = Native.getLastError()
            return
        }
        lastError = Native.getLastError()
        if (System.nanoTime() < retryDeadline) {
            scheduler.schedule({ thread.post { tryAdd() } }, retryIntervalMillis, TimeUnit.MILLISECONDS)
        }
    }

    /** Explorer 재시작: 보이던 아이콘을 다시 붙인다. 아이콘이 아직 살아 있으면(재시작이 아닌 방송) NIM_ADD 가 실패하므로 MODIFY 로 확인한다. */
    private fun onTaskbarCreated() {
        if (!wanted) return
        val d = data ?: return
        if (Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_ADD, d)) {
            added = true
            d.uVersion = Win32.NOTIFYICON_VERSION_4
            versionSet = Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_SETVERSION, d)
            reattached++
        } else if (Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_MODIFY, d)) {
            added = true
            reattached++
        } else {
            added = false
            lastError = Native.getLastError()
            retryDeadline = System.nanoTime() + retryWindowMillis * 1_000_000
            tryAdd()
        }
    }

    override fun close() {
        runCatching { if (thread.isAlive) remove() }
        registrations.forEach { it.close() }
        scheduler.shutdownNow()
    }
}
