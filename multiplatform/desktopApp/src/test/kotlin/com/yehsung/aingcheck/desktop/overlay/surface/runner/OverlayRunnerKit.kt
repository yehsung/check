// 원본: 없음(새 시험 도우미) — overlay.md §5 Windows 러너 몫 · platform/windows/runner/RunnerSupport(자식 JVM @인자 파일 · 입력 주입 허용 조건)
package com.yehsung.aingcheck.desktop.overlay.surface.runner

import com.sun.jna.Native
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.yehsung.aingcheck.desktop.overlay.render.ComposedOverlay
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayUser32
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayWin32
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayWindowClass
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

object OverlayRunnerKit {
    const val W = 280
    const val H = 340

    /**
     * 합성 프레임(굽기 자산 0): 왼쪽 절반 알파 0, 오른쪽 절반 불투명(프리멀티 RGBA). [shade] 로 프레임마다 색을 바꾼다.
     * 왼쪽 = 뒤 창으로 통과해야 할 자리, 오른쪽 = 오버레이가 받아야 할 자리.
     */
    fun halfOpaque(shade: Int = 200): ComposedOverlay {
        val px = ByteArray(W * H * 4)
        for (y in 0 until H) for (x in W / 2 until W) {
            val i = (y * W + x) * 4
            px[i] = shade.toByte(); px[i + 1] = 80; px[i + 2] = 40; px[i + 3] = 255.toByte()
        }
        return ComposedOverlay(W, H, px)
    }

    fun windowFromPoint(x: Int, y: Int): WinDef.HWND? = OverlayUser32.INSTANCE.WindowFromPoint(WinDef.POINT.ByValue(x, y))

    fun same(a: WinDef.HWND?, b: WinDef.HWND?): Boolean = a != null && b != null && a.pointer == b.pointer

    fun className(h: WinDef.HWND?): String {
        if (h == null) return "<null>"
        val buf = CharArray(256)
        val n = User32.INSTANCE.GetClassName(h, buf, buf.size)
        return String(buf, 0, n)
    }

    /** 이 데스크톱의 최상위 창 중 클래스 이름이 [name] 인 것의 수. */
    fun countWindowsOfClass(name: String): Int {
        val n = AtomicInteger(0)
        User32.INSTANCE.EnumWindows({ h, _ -> if (className(h) == name) n.incrementAndGet(); true }, null)
        return n.get()
    }

    /** 뒤 창: 보통(레이어드 아님) 맨 위 도구 창. 왼쪽 단추 눌림 수를 센다. */
    class BackWindow(private val thread: Win32MessageThread, name: String, x: Int, y: Int, w: Int, h: Int) : AutoCloseable {
        val clicks = AtomicInteger(0)
        private val cls = OverlayWindowClass(name, blackBackground = true)
        val hwnd: WinDef.HWND = thread.call { _ ->
            cls.create(OverlayWin32.WS_EX_TOOLWINDOW or OverlayWin32.WS_EX_TOPMOST, x, y, w, h) { _, msg, _, _ ->
                if (msg == OverlayWin32.WM_LBUTTONDOWN) clicks.incrementAndGet()
                null
            }.also { OverlayWindowClass.showNoActivate(it) }
        }

        override fun close() {
            thread.call { _ -> cls.destroy(hwnd); cls.close() }
        }
    }

    /** 커서를 옮기고 왼쪽 단추를 누르고 뗀다(입력 주입 — CI·시험 VM 에서만 부른다). */
    fun clickAt(x: Int, y: Int) {
        check(User32.INSTANCE.SetCursorPos(x.toLong(), y.toLong())) { "SetCursorPos 실패 err=${Native.getLastError()}" }
        Thread.sleep(80)
        for (flag in intArrayOf(0x0002 /* LEFTDOWN */, 0x0004 /* LEFTUP */)) {
            val input = WinUser.INPUT()
            input.type = WinDef.DWORD(WinUser.INPUT.INPUT_MOUSE.toLong())
            input.input.setType("mi")
            input.input.mi.dwFlags = WinDef.DWORD(flag.toLong())
            val sent = User32.INSTANCE.SendInput(WinDef.DWORD(1), arrayOf(input), input.size())
            check(sent.toInt() == 1) { "SendInput 실패 err=${Native.getLastError()}" }
            Thread.sleep(40)
        }
    }

    data class ChildResult(val exitCode: Int, val stdout: String, val stderr: String)

    /** 같은 JDK·classpath 로 [OverlayChildProbe] 를 띄운다(classpath 는 @인자 파일 — 32K 명령줄 한계). */
    fun runChild(args: List<String>, timeoutSeconds: Long = 90): ChildResult {
        val javaExe = ProcessHandle.current().info().command().orElseThrow { IllegalStateException("java 경로를 모른다") }
        val argFile = Files.createTempFile("aingcheck-overlay-cp", ".args")
        val cp = System.getProperty("java.class.path").replace("\\", "\\\\").replace("\"", "\\\"")
        Files.writeString(argFile, "-cp\n\"" + cp + "\"\n")
        try {
            val cmd = listOf(javaExe, "-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8", "@" + argFile.toAbsolutePath(), OverlayChildProbe::class.java.name) + args
            val p = ProcessBuilder(cmd).redirectInput(ProcessBuilder.Redirect.from(File(if (File.separatorChar == '\\') "NUL" else "/dev/null"))).start()
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            if (!p.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
                p.destroyForcibly()
                error("자식 JVM 이 ${timeoutSeconds}초 안에 끝나지 않았다")
            }
            return ChildResult(p.exitValue(), out.trim(), err.trim())
        } finally {
            Files.deleteIfExists(argFile)
        }
    }
}
