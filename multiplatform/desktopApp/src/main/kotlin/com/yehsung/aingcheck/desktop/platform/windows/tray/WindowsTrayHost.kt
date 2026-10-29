// 원본: 없음(새 코드) — 설계 D§3-1(Compose Tray 대신 Shell_NotifyIcon 직접: 한 번 클릭·아이콘 자리·키보드·TaskbarCreated),
//       W0-e 실측(NOTIFYICONDATAW 976B, NIM_ADD → SETVERSION v4 → GetRect → DELETE, arm64 러너는 OOBE 화면이 덮으면 0x80004005)
//
// - 모든 Shell_NotifyIcon 호출은 메시지 스레드에서 한다(콜백 창과 같은 스레드).
// - Explorer 가 다시 뜨면(TaskbarCreated 방송) 보이던 아이콘을 다시 붙인다(D§2-2). 그 메시지를 못 받는 message-only 창은 쓰지 않는다.
// - 로그인 직후처럼 작업 표시줄이 아직 없으면 NIM_ADD 가 실패한다 — 붙을 때까지 [retryIntervalMillis] 간격으로
//   [retryWindowMillis] 동안 다시 해 보고, 그 뒤로는 TaskbarCreated 를 기다린다(메시지 스레드를 재우지 않는다).
// - 클릭 리스너는 [events] 실행기에서 부른다(화면 쪽은 EDT 실행기를 넘긴다 — 메시지 스레드에서 오래 일하지 않는다, D§2-2).
// - 풍선(핀 조정 ⑨ BalloonNotifier, W1-f2): 트레이 아이콘의 NIM_MODIFY + NIF_INFO. 아이콘 갱신용 구조체와 **따로** 채운다 —
//   같은 구조체에 NIF_INFO 를 켜 두면 다음 update()(분마다)가 같은 풍선을 다시 띄운다. 클릭은 같은 콜백 메시지의
//   NIN_BALLOONUSERCLICK(0x405)로 오고, 그 사건엔 어느 풍선인지가 없어서 마지막으로 띄운 종류를 넘긴다.
// - 테마(W1-f2): WM_SETTINGCHANGE("ImmersiveColorSet") 에서만 [themeReader] 를 다시 읽고, 바뀌었을 때만 [events] 로 알린다.
//   그래서 콜백 창은 방송을 받는 보통 창이어야 한다(message-only 창은 WM_SETTINGCHANGE 방송도 못 받는다).
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.sun.jna.Native
import com.sun.jna.Pointer
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
import com.yehsung.aingcheck.desktop.shellapi.BalloonNotifier
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
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
    /** update·show 가 부른 NIM_MODIFY 횟수. */
    val modifyCalls: Int = 0,
    /**
     * 마지막 NIM_MODIFY 의 BOOL(아직 안 불렀으면 null). Shell_NotifyIcon 은 실패해도 GetLastError 를 늘 채우지 않아
     * [lastError] 만으로는 갱신 실패를 놓친다(R2 검증 지적) — 반환값 그대로를 남긴다.
     */
    val lastModifyOk: Boolean? = null,
    /** showBalloon 이 부른 NIM_MODIFY(NIF_INFO) 횟수 — 아이콘이 없거나 본문이 비어 부르지 않은 것은 세지 않는다. */
    val balloonCalls: Int = 0,
    /** 마지막 풍선 NIM_MODIFY 의 BOOL(아직이면 null). */
    val lastBalloonOk: Boolean? = null,
    /** 마지막 풍선의 uFlags·dwInfoFlags(시험이 NIF_INFO 가 아이콘 갱신으로 새지 않았는지 대조한다). */
    val lastBalloonFlags: Int = 0,
    val lastBalloonInfoFlags: Int = 0,
    /** 마지막 아이콘 NIM_ADD·MODIFY 가 쓴 uFlags — NIF_INFO 가 켜져 있으면 풍선이 분마다 다시 뜬다. */
    val lastIconFlags: Int = 0,
    /** 구조체에 실제로 들어간(잘린) 풍선 제목·본문. */
    val lastBalloonTitle: String? = null,
    val lastBalloonBody: String? = null,
    /** 레지스트리 테마를 다시 읽은 횟수(ImmersiveColorSet 일 때만 는다). */
    val themeReads: Int = 0,
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
    /** 작업 표시줄 테마 읽기(기본 = 레지스트리). 시험은 합성 값을 넘긴다. */
    private val themeReader: () -> TaskbarTheme = TaskbarThemeProbe::current,
) : TrayHost, BalloonNotifier, AutoCloseable {
    // ---- 메시지 스레드 전용 상태 ----
    private var data: NOTIFYICONDATAW? = null
    private var hIcon: WinDef.HICON? = null
    private var wanted = false
    private var added = false
    private var versionSet = false
    private var attempts = 0
    private var lastError = 0
    private var reattached = 0
    private var modifyCalls = 0
    private var lastModifyOk: Boolean? = null
    private var retryDeadline = 0L
    private var balloonCalls = 0
    private var lastBalloonOk: Boolean? = null
    private var lastBalloonFlags = 0
    private var lastBalloonInfoFlags = 0
    private var lastBalloonTitle: String? = null
    private var lastBalloonBody: String? = null
    /** 마지막으로 띄운 풍선 종류 — NIN_BALLOONUSERCLICK 에는 어느 풍선인지가 없다. 아이콘을 지우면 잊는다. */
    private var lastBalloonKind: NotifyKind? = null
    private val themeTracker = TaskbarThemeTracker(themeReader())

    @Volatile private var balloonClickHandler: ((NotifyKind) -> Unit)? = null
    private val themeListeners = CopyOnWriteArrayList<(TaskbarTheme) -> Unit>()

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
            val balloon = TrayCallbackDecoder.decodeBalloon(lParam.toLong())
            if (balloon != null && balloon.iconId == iconId && balloon.kind == BalloonEventKind.USER_CLICKED) {
                val kind = lastBalloonKind
                val handler = balloonClickHandler
                if (kind != null && handler != null) events.execute { handler(kind) }
            }
            WinDef.LRESULT(0)
        },
        thread.addHandler(TrayBalloonWin32.WM_SETTINGCHANGE) { _, _, _, lParam ->
            val area = settingArea(lParam)
            val changed = themeTracker.onSettingChange(area, themeReader)
            if (changed != null) for (l in themeListeners) events.execute { l(changed) }
            null // 방송 메시지 — DefWindowProc 도 받게 둔다
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
            d.uFlags = ICON_FLAGS
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
            lastBalloonKind = null
            hIcon?.let { User32.INSTANCE.DestroyIcon(it) }
            hIcon = null
        }
    }

    override fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit): Registration {
        clickListeners += listener
        return Registration { clickListeners -= listener }
    }

    /**
     * 핀 BalloonNotifier: 트레이 아이콘의 풍선을 띄운다. 아이콘이 셸에 없거나(아직 NIM_ADD 전·삭제 뒤) 본문이 비면 false.
     * 반환 = NIM_MODIFY(NIF_INFO) 의 BOOL. 집중 지원·조용한 시간에 실제로 보였는지는 OS 가 알려 주지 않는다(VM D-E14).
     */
    override fun showBalloon(title: String, body: String, kind: NotifyKind, respectQuietTime: Boolean): Boolean {
        val plan = BalloonPlanner.plan(title, body, kind, respectQuietTime) ?: return false
        return thread.call { hwnd ->
            val icon = data
            if (!added || icon == null) return@call false
            val b = NOTIFYICONDATAW()
            b.cbSize = b.size()
            b.hWnd = hwnd
            b.uID = iconId
            b.uFlags = plan.uFlags
            b.dwInfoFlags = plan.dwInfoFlags
            val t = NOTIFYICONDATAW.clipUtf16(plan.title, TrayBalloonWin32.MAX_TITLE_CHARS)
            val m = NOTIFYICONDATAW.clipUtf16(plan.body, TrayBalloonWin32.MAX_BODY_CHARS)
            t.toCharArray().copyInto(b.szInfoTitle)
            m.toCharArray().copyInto(b.szInfo)
            balloonCalls++
            val ok = Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_MODIFY, b)
            lastBalloonOk = ok
            lastBalloonFlags = plan.uFlags
            lastBalloonInfoFlags = plan.dwInfoFlags
            lastBalloonTitle = t
            lastBalloonBody = m
            if (ok) lastBalloonKind = kind else lastError = Native.getLastError()
            ok
        }
    }

    /** 핀 BalloonNotifier: 풍선 클릭(NIN_BALLOONUSERCLICK) → 마지막으로 띄운 풍선 종류. [events] 실행기에서 부른다. 다시 부르면 바꾼다. */
    override fun setOnBalloonClick(handler: (NotifyKind) -> Unit) {
        balloonClickHandler = handler
    }

    /** 지금 아는 작업 표시줄 테마(만들 때 한 번 읽고, ImmersiveColorSet 변경 때 다시 읽는다). */
    fun currentTheme(): TaskbarTheme = thread.call { themeTracker.current }

    /** 테마가 실제로 바뀌었을 때만 [events] 실행기에서 부른다(아이콘을 새 테마로 다시 그리는 것은 부르는 쪽). */
    fun addThemeListener(listener: (TaskbarTheme) -> Unit): Registration {
        themeListeners += listener
        return Registration { themeListeners -= listener }
    }

    fun status(): TrayStatus = thread.call {
        TrayStatus(
            wanted, added, versionSet, attempts, lastError, reattached, modifyCalls, lastModifyOk,
            balloonCalls = balloonCalls,
            lastBalloonOk = lastBalloonOk,
            lastBalloonFlags = lastBalloonFlags,
            lastBalloonInfoFlags = lastBalloonInfoFlags,
            lastIconFlags = data?.uFlags ?: 0,
            lastBalloonTitle = lastBalloonTitle,
            lastBalloonBody = lastBalloonBody,
            themeReads = themeTracker.reads,
        )
    }

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
        modifyCalls++
        val ok = Shell32X.INSTANCE.Shell_NotifyIconW(Win32.NIM_MODIFY, d)
        lastModifyOk = ok
        if (!ok) lastError = Native.getLastError()
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

    /** WM_SETTINGCHANGE 의 lParam = 설정 영역 이름(UTF-16, NUL 끝) 또는 0. 읽기 실패는 '영역 미상'(테마 아님). */
    private fun settingArea(lParam: WinDef.LPARAM): String? {
        val p = lParam.toLong()
        if (p == 0L) return null
        return runCatching { Pointer(p).getWideString(0) }.getOrNull()
    }

    override fun close() {
        runCatching { if (thread.isAlive) remove() }
        registrations.forEach { it.close() }
        scheduler.shutdownNow()
    }

    companion object {
        /** 아이콘 추가·갱신 구조체의 uFlags — 풍선 비트(NIF_INFO·NIF_REALTIME)는 절대 넣지 않는다. */
        const val ICON_FLAGS = Win32.NIF_MESSAGE or Win32.NIF_ICON or Win32.NIF_TIP or Win32.NIF_SHOWTIP
    }
}
