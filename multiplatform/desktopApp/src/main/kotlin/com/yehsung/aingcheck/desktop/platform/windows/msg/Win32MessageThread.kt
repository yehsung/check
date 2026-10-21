// 원본: 없음(새 코드) — 설계 D§2-2(Win32 메시지 스레드와 숨은 창), W0-e 탐침 Smoke.onWindowThread 의 창 만들기
//
// - 전용 스레드 하나가 **보이지 않는 최상위 창**(WS_POPUP + WS_EX_TOOLWINDOW, ShowWindow 를 한 번도 부르지 않음)을 만들고
//   GetMessage 루프를 돈다. 트레이 콜백·WM_HOTKEY·WM_INPUT·TaskbarCreated 를 이 창이 받는다.
// - **message-only 창(HWND_MESSAGE)을 쓰지 않는다**: 방송 메시지를 못 받는다 → TaskbarCreated(Explorer 재시작)를 놓치면
//   트레이 아이콘이 영영 사라진다(D§2-2, learn.microsoft.com window-features).
// - RegisterHotKey 는 창을 만든 스레드에서만 된다 → 등록·해제는 [call]·[post] 로 이 스레드에 넘긴다.
// - 이 스레드의 처리기는 짧게 끝낸다. 화면(Compose/EDT)으로 가는 일은 각 서비스가 받은 실행기로 넘긴다.
package com.yehsung.aingcheck.desktop.platform.windows.msg

import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.jna.User32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/** 숨은 창이 받은 메시지 하나를 다룬다. null 을 돌려주면 다음 처리기 → DefWindowProc 로 넘어간다. */
fun interface MessageHandler {
    fun handle(hwnd: WinDef.HWND, message: Int, wParam: WinDef.WPARAM, lParam: WinDef.LPARAM): WinDef.LRESULT?
}

class Win32MessageThread private constructor(
    /** 창 클래스 이름. 두 번째 실행이 첫 실행을 찾는 열쇠(D§2-5)라 앱은 [DEFAULT_CLASS_NAME] 을 쓰고, 시험은 고유 이름을 쓴다. */
    val className: String,
    private val threadName: String,
) : AutoCloseable {
    private val handlers = ConcurrentHashMap<Int, CopyOnWriteArrayList<MessageHandler>>()
    private val invokeQueue = ConcurrentLinkedQueue<Runnable>()
    private val ready = CountDownLatch(1)
    private val finished = CountDownLatch(1)

    @Volatile private var startError: Throwable? = null
    @Volatile private var hwndOrNull: WinDef.HWND? = null
    @Volatile private var closed = false
    @Volatile private var thread: Thread? = null

    /** RegisterWindowMessage("TaskbarCreated") — Explorer 가 다시 떴을 때 모든 최상위 창에 방송된다. */
    @Volatile var taskbarCreatedMessage: Int = 0
        private set

    // 콜백이 GC 되면 창 프로시저가 사라진 주소를 부른다 — 스레드가 사는 동안 필드로 붙잡는다.
    private val windowProc = WinUser.WindowProc { hwnd, msg, wParam, lParam -> dispatch(hwnd, msg, wParam, lParam) }
    private var windowClass: WinUser.WNDCLASSEX? = null

    val hwnd: WinDef.HWND
        get() = hwndOrNull ?: throw IllegalStateException("메시지 스레드가 준비되지 않았다")

    val isOnThread: Boolean
        get() = Thread.currentThread() === thread

    val isAlive: Boolean
        get() = !closed && thread?.isAlive == true

    private fun start(startTimeoutMillis: Long) {
        val t = Thread({ run() }, threadName)
        t.isDaemon = true
        thread = t
        t.start()
        if (!ready.await(startTimeoutMillis, TimeUnit.MILLISECONDS)) {
            throw IllegalStateException("메시지 스레드가 ${startTimeoutMillis}ms 안에 창을 만들지 못했다")
        }
        startError?.let { throw IllegalStateException("메시지 스레드 시작 실패: ${it.message}", it) }
    }

    private fun run() {
        val u = User32.INSTANCE
        val hInst = Kernel32.INSTANCE.GetModuleHandle(null)
        var hwnd: WinDef.HWND? = null
        try {
            val wc = WinUser.WNDCLASSEX()
            wc.hInstance = hInst
            wc.lpfnWndProc = windowProc
            wc.lpszClassName = className
            windowClass = wc
            val atom = u.RegisterClassEx(wc)
            if (atom == null || atom.toInt() == 0) {
                throw IllegalStateException("RegisterClassEx('$className') 실패: ${Kernel32.INSTANCE.GetLastError()}")
            }
            hwnd = u.CreateWindowEx(Win32.WS_EX_TOOLWINDOW, className, "AingCheck", Win32.WS_POPUP, 0, 0, 0, 0, null, null, hInst, null)
                ?: throw IllegalStateException("CreateWindowEx 실패: ${Kernel32.INSTANCE.GetLastError()}")
            taskbarCreatedMessage = u.RegisterWindowMessage("TaskbarCreated")
            // 높은 무결성(관리자)으로 돌 때도 Explorer(보통 무결성)의 방송을 받게 연다. 낮은 쪽 프로세스에서는 해가 없다.
            runCatching { User32X.INSTANCE.ChangeWindowMessageFilterEx(hwnd, taskbarCreatedMessage, Win32.MSGFLT_ALLOW, null) }
            hwndOrNull = hwnd
        } catch (t: Throwable) {
            startError = t
            ready.countDown()
            finished.countDown()
            runCatching { u.UnregisterClass(className, hInst) }
            return
        }
        ready.countDown()
        try {
            val msg = WinUser.MSG()
            while (true) {
                val r = u.GetMessage(msg, null, 0, 0)
                if (r == 0 || r == -1) break
                u.TranslateMessage(msg)
                u.DispatchMessage(msg)
            }
        } finally {
            closed = true
            failPending()
            runCatching { u.UnregisterClass(className, hInst) }
            java.lang.ref.Reference.reachabilityFence(windowProc)
            java.lang.ref.Reference.reachabilityFence(windowClass)
            finished.countDown()
        }
    }

    private fun dispatch(hwnd: WinDef.HWND, msg: Int, wParam: WinDef.WPARAM, lParam: WinDef.LPARAM): WinDef.LRESULT {
        try {
            when (msg) {
                Win32.WM_APP_INVOKE -> {
                    drainInvokes()
                    return WinDef.LRESULT(0)
                }
                Win32.WM_CLOSE -> {
                    User32.INSTANCE.DestroyWindow(hwnd)
                    return WinDef.LRESULT(0)
                }
                Win32.WM_DESTROY -> {
                    hwndOrNull = null
                    User32X.INSTANCE.PostQuitMessage(0)
                    return WinDef.LRESULT(0)
                }
            }
            handlers[msg]?.forEach { h ->
                val r = h.handle(hwnd, msg, wParam, lParam)
                if (r != null) return r
            }
        } catch (t: Throwable) {
            // 창 프로시저 밖으로 예외를 내보내면 JNA 가 기본 처리기로 찍고 메시지를 잃는다 — 여기서 삼키고 기록만 한다.
            System.err.println("aingcheck-win32: 메시지 0x${Integer.toHexString(msg)} 처리 중 예외: $t")
        }
        return User32.INSTANCE.DefWindowProc(hwnd, msg, wParam, lParam)
    }

    private fun drainInvokes() {
        while (true) {
            val r = invokeQueue.poll() ?: return
            r.run()
        }
    }

    private fun failPending() {
        while (true) {
            val r = invokeQueue.poll() ?: return
            r.run() // 각 Runnable 은 closed 를 보고 실패로 끝난다
        }
    }

    /** [message] 를 받으면 [handler] 를 이 스레드에서 부른다. */
    fun addHandler(message: Int, handler: MessageHandler): Registration {
        val list = handlers.computeIfAbsent(message) { CopyOnWriteArrayList() }
        list += handler
        return Registration { list -= handler }
    }

    /** [block] 을 이 스레드에서 돌리고 결과를 기다린다. 이 스레드 위에서 부르면 바로 돈다. */
    fun <T> call(timeoutMillis: Long = 5_000, block: (WinDef.HWND) -> T): T {
        if (isOnThread) return block(hwnd)
        check(isAlive) { "메시지 스레드가 닫혔다" }
        val future = CompletableFuture<T>()
        invokeQueue += Runnable {
            if (closed) {
                future.completeExceptionally(IllegalStateException("메시지 스레드가 닫혔다"))
            } else {
                try {
                    future.complete(block(hwnd))
                } catch (t: Throwable) {
                    future.completeExceptionally(t)
                }
            }
        }
        wake()
        try {
            return future.get(timeoutMillis, TimeUnit.MILLISECONDS)
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        } catch (e: TimeoutException) {
            throw IllegalStateException("메시지 스레드가 ${timeoutMillis}ms 안에 답하지 않았다", e)
        }
    }

    /** [block] 을 이 스레드에 넘기고 기다리지 않는다. 닫힌 뒤면 버린다. */
    fun post(block: (WinDef.HWND) -> Unit) {
        if (!isAlive) return
        invokeQueue += Runnable { if (!closed) block(hwnd) }
        wake()
    }

    private fun wake() {
        val h = hwndOrNull ?: return
        User32X.INSTANCE.PostMessageW(h, Win32.WM_APP_INVOKE, WinDef.WPARAM(0), WinDef.LPARAM(0))
    }

    override fun close() {
        val h = hwndOrNull
        if (h != null && isAlive) {
            User32X.INSTANCE.PostMessageW(h, Win32.WM_CLOSE, WinDef.WPARAM(0), WinDef.LPARAM(0))
        }
        finished.await(5, TimeUnit.SECONDS)
        closed = true
    }

    companion object {
        /** 앱의 숨은 창 클래스 이름 — 두 번째 실행이 FindWindow 로 첫 실행을 찾는다(D§2-5). */
        const val DEFAULT_CLASS_NAME = "AingCheck.MessageWindow"

        fun start(
            className: String = DEFAULT_CLASS_NAME,
            threadName: String = "aingcheck-win32",
            startTimeoutMillis: Long = 10_000,
        ): Win32MessageThread = Win32MessageThread(className, threadName).also { it.start(startTimeoutMillis) }
    }
}
