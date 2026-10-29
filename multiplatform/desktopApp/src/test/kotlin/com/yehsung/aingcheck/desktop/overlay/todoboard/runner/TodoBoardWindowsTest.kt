// 원본: Tests/checkTests/CheckTodoBoardWindowTests.swift:121-176(패널이 키를 받고 화면 공유에서 빠진다) @ ef9fab11 · overlay.md §5 b3 러너 몫
// Windows 러너에서만. 시험 JVM 은 java.awt.headless=true 라 창은 **자식 JVM**(headless=false)이 만들고 값만 찍는다.
package com.yehsung.aingcheck.desktop.overlay.todoboard.runner

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinUser
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardActions
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardSections
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardView
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardViewState
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardWindow
import com.yehsung.aingcheck.desktop.overlay.todoboard.win32.BoardWin32
import com.yehsung.aingcheck.desktop.platform.windows.runner.RunnerSupport
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import javax.swing.SwingUtilities
import kotlin.system.exitProcess
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

@EnabledOnOs(OS.WINDOWS)
class TodoBoardWindowsTest {
    @Test
    fun boardIsAToolTopmostCaptureExcludedWindowThatComesToTheForeground() {
        val unlock = RunnerSupport.inputInjectionAllowed()
        val r = runBoardChild(listOf(if (unlock) "unlock" else "plain"))
        println("[TodoBoardWindowsTest] child stdout:\n${r.second}")
        assertEquals(0, r.first, "자식 JVM 실패:\n${r.second}\n${r.third}")
        val v = r.second.lines().filter { '=' in it }.associate { it.substringBefore('=').trim() to it.substringAfter('=').trim() }
        val ex = Integer.decode(v.getValue("exstyle"))
        assertTrue(ex and BoardWin32.WS_EX_TOOLWINDOW != 0, "도구 창(작업 표시줄·Alt+Tab 에 안 뜸): exstyle=$ex")
        assertTrue(ex and BoardWin32.WS_EX_TOPMOST != 0, "맨 위: exstyle=$ex")
        assertTrue(ex and BoardWin32.WS_EX_APPWINDOW == 0, "APPWINDOW 없음: exstyle=$ex")
        assertTrue(ex and BoardWin32.WS_EX_NOACTIVATE == 0, "보드는 활성화된다(글자를 받는다, D §9-5): exstyle=$ex")
        assertEquals("true", v["visible"])
        assertEquals("true", v["hidden"], "hide 뒤엔 안 보인다(파괴하지 않음)")
        val affinityError = v.getValue("affinityError").toInt()
        if (affinityError == 0) {
            assertEquals(BoardWin32.WDA_EXCLUDEFROMCAPTURE, Integer.decode(v.getValue("affinity")), "화면 공유에서 뺀다")
        } else {
            // W-3 #10: 러너에 DWM 합성이 없으면 오류 코드만 남기고 VM 묶음으로 넘긴다.
            println("[TodoBoardWindowsTest] SetWindowDisplayAffinity 실패 GetLastError=$affinityError — VM 묶음에서 확인")
        }
        if (unlock) assertEquals("true", v["foreground"], "보이면 전경이 된다") else println("[TodoBoardWindowsTest] 입력 주입 금지 — 전경 판정 기록만: ${v["foreground"]}")
    }

    /** 같은 JDK·classpath 로 [TodoBoardChildProbe] 를 headless=false 로 띄운다(RunnerSupport.runChild 와 같은 @인자 파일 방식). */
    private fun runBoardChild(args: List<String>): Triple<Int, String, String> {
        val javaExe = ProcessHandle.current().info().command().orElseThrow { IllegalStateException("java 경로를 모른다") }
        val argFile = Files.createTempFile("aingcheck-board-cp", ".args")
        val cp = System.getProperty("java.class.path").replace("\\", "\\\\").replace("\"", "\\\"")
        Files.writeString(argFile, "-cp\n\"" + cp + "\"\n")
        try {
            val cmd = listOf(javaExe, "-Djava.awt.headless=false", "-Dstdout.encoding=UTF-8", "-Dstderr.encoding=UTF-8", "@" + argFile.toAbsolutePath()) +
                listOf(TodoBoardChildProbe::class.java.name) + args
            val p = ProcessBuilder(cmd).redirectInput(ProcessBuilder.Redirect.from(File("NUL"))).start()
            val out = p.inputStream.bufferedReader().readText()
            val err = p.errorStream.bufferedReader().readText()
            if (!p.waitFor(90, TimeUnit.SECONDS)) {
                p.destroyForcibly()
                fail("자식 JVM 이 90초 안에 끝나지 않았다")
            }
            return Triple(p.exitValue(), out.trim(), err.trim())
        } finally {
            Files.deleteIfExists(argFile)
        }
    }
}

private interface ProbeUser32 : Library {
    fun keybd_event(bVk: Byte, bScan: Byte, dwFlags: Int, dwExtraInfo: com.sun.jna.platform.win32.BaseTSD.ULONG_PTR?)

    companion object {
        val INSTANCE: ProbeUser32 by lazy { Native.load("user32", ProbeUser32::class.java) }
    }
}

/** 자식 JVM: 보드 창을 띄우고 값을 찍고 닫는다. `unlock` 이면 Alt 를 한 번 눌러 전경 잠금을 푼다(캐릭터 클릭 직후를 흉내 — CI 만). */
object TodoBoardChildProbe {
    @JvmStatic
    fun main(args: Array<String>) {
        val code = try {
            run(args.firstOrNull() == "unlock"); 0
        } catch (t: Throwable) {
            t.printStackTrace(); 1
        }
        exitProcess(code)
    }

    private fun run(unlock: Boolean) {
        val state = TodoBoardViewState(TodoBoardSections(emptyList(), emptyList()), "20260921", draft = "")
        lateinit var board: TodoBoardWindow
        SwingUtilities.invokeAndWait {
            board = TodoBoardWindow(content = { TodoBoardView(state, TodoBoardActions(), cornerRadiusDp = 0) })
        }
        if (unlock) {
            val vkMenu = 0x12.toByte()
            ProbeUser32.INSTANCE.keybd_event(vkMenu, 0, 0, null)
            ProbeUser32.INSTANCE.keybd_event(vkMenu, 0, 0x0002, null)
        }
        SwingUtilities.invokeAndWait { board.show(OverlayRect(120.0, 120.0, 300.0, 400.0)) }
        val hwnd = requireNotNull(board.hwnd)
        val u = User32.INSTANCE
        RunnerSupport.waitUntil(10_000, "보드 창이 보인다") { u.IsWindowVisible(hwnd) }
        var foreground = false
        val deadline = System.nanoTime() + 3_000_000_000L
        while (System.nanoTime() < deadline && !foreground) {
            foreground = u.GetForegroundWindow() == hwnd
            if (!foreground) Thread.sleep(50)
        }
        println("exstyle=0x" + Integer.toHexString(u.GetWindowLong(hwnd, WinUser.GWL_EXSTYLE)))
        println("affinityError=" + (board.lastApplied?.affinityError ?: -2))
        println("affinity=0x" + Integer.toHexString(BoardWin32.displayAffinity(hwnd) ?: -1))
        println("visible=" + u.IsWindowVisible(hwnd))
        println("foreground=$foreground")
        SwingUtilities.invokeAndWait { board.hide() }
        RunnerSupport.waitUntil(5_000, "숨김") { !u.IsWindowVisible(hwnd) }
        println("hidden=" + !u.IsWindowVisible(hwnd))
        SwingUtilities.invokeAndWait { board.dispose() }
    }
}
