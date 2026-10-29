// 원본: 없음(구조 시험) — xplat-w1/briefs/shell.md §5: shell/** 에서 JNA 는 shell/flyout/native/** 만, AWT TrayIcon·SystemTray 0건
//       (트레이는 Shell_NotifyIcon 직접 — 설계 D §3-1, AWT 트레이는 NOTIFYICON_VERSION_4 콜백·풍선 클릭을 못 준다).
package com.yehsung.aingcheck.desktop.shell.flyout

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

class ShellStructureTest {
    internal object ShellRules {
        private val JNA = Regex("""\bcom\.sun\.jna\b""")
        private val AWT_TRAY = Regex("""\b(?:java\.awt\.TrayIcon|SystemTray|TrayIcon)\b""")

        fun strip(code: String): String =
            code.replace(Regex("""/\*[\s\S]*?\*/"""), "").lines().joinToString("\n") { it.replace(Regex("""//.*$"""), "") }

        /** [rel] = shell/ 아래 경로(…/shell/tray/X.kt 꼴). */
        fun check(rel: String, code: String): List<String> {
            val c = strip(code)
            val out = mutableListOf<String>()
            if (!rel.contains("/shell/flyout/native/") && JNA.containsMatchIn(c)) out += "JNA $rel"
            if (AWT_TRAY.containsMatchIn(c)) out += "AWT_TRAY $rel"
            return out
        }
    }

    private fun shellFiles(): List<Pair<String, String>> {
        val mp = System.getProperty("aingcheck.mpRoot") ?: fail("aingcheck.mpRoot 시스템 속성이 없다")
        val root = File(mp, "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/shell")
        return root.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }
            .map { "/" + it.relativeTo(File(mp)).invariantSeparatorsPath to it.readText() }.toList()
    }

    @Test
    fun jnaOnlyUnderFlyoutNativeAndNoAwtTray() {
        val files = shellFiles()
        assertTrue(files.size >= 10, "shell/** 파일을 못 봤다: ${files.map { it.first }}")
        assertTrue(files.any { it.first.contains("/shell/flyout/native/") && it.second.contains("com.sun.jna") }, "native 폴더 확인(빈 검사가 아니다)")
        assertEquals(emptyList(), files.flatMap { (p, c) -> ShellRules.check(p, c) })
    }

    @Test
    fun plantedLinesAreCaught() {
        assertEquals(listOf("JNA /x/shell/tray/A.kt"), ShellRules.check("/x/shell/tray/A.kt", "import com.sun.jna.Native\n"))
        assertEquals(emptyList(), ShellRules.check("/x/shell/flyout/native/A.kt", "import com.sun.jna.Native\n"))
        assertEquals(listOf("AWT_TRAY /x/shell/flyout/native/A.kt"), ShellRules.check("/x/shell/flyout/native/A.kt", "val t = java.awt.SystemTray.getSystemTray()"))
        assertEquals(emptyList(), ShellRules.check("/x/shell/tray/A.kt", "// import com.sun.jna.Native — 주석은 세지 않는다\n"))
    }
}
