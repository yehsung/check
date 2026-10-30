// 원본: 없음(새 시험 자식) — overlay.md §5 OverlayChildProbeWindowsTest(30프레임 갱신 → 닫기 → 종료 코드 0 · 그 클래스 창 0개)
package com.yehsung.aingcheck.desktop.overlay.surface.runner

import com.yehsung.aingcheck.desktop.overlay.surface.WindowsOverlaySurface
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import kotlin.system.exitProcess

/** 자식 JVM 입구. `frames <클래스 이름> <n>` — n 프레임을 올리고 닫은 뒤 그 클래스 창 수를 찍는다. 인자는 ASCII 만. */
object OverlayChildProbe {
    @JvmStatic
    fun main(args: Array<String>) {
        if (args.size != 3 || args[0] != "frames") {
            System.err.println("usage: frames <class> <n>")
            exitProcess(64)
        }
        val cls = args[1]
        val n = args[2].toInt()
        var presented = 0
        var firstError = 0
        val thread = Win32MessageThread.start(className = "$cls.Msg", threadName = "overlay-child")
        try {
            val surface = WindowsOverlaySurface(thread, cls)
            try {
                for (i in 0 until n) {
                    val r = surface.present(OverlayRunnerKit.halfOpaque(40 + i * 5), 300 + i, 260)
                    if (r.ok) presented++ else if (firstError == 0) firstError = r.errorCode
                    Thread.sleep(33)
                }
                println("during=${OverlayRunnerKit.countWindowsOfClass(cls)}")
            } finally {
                surface.close()
            }
        } finally {
            thread.close()
        }
        val after = OverlayRunnerKit.countWindowsOfClass(cls)
        println("presented=$presented firstError=$firstError windowsAfterClose=$after")
        System.out.flush()
        exitProcess(if (presented == n && after == 0) 0 else 3)
    }
}
