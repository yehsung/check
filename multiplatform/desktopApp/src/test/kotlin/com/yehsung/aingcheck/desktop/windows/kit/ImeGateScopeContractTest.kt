// 원본: 없음(배선 계약) — games.md §5 W4-d · §6 위험 ①(오목 창엔 채팅 칸 — 판 게임 둘은 IME 를 떼지 않는다) ·
//       MiniGamePanel.swift:153-156(한글 입력 상태에서 Z·X·C 가 'ㅋ'·'ㅌ'·'ㅊ') (W4-d)
package com.yehsung.aingcheck.desktop.windows.kit

import java.io.File
import java.nio.file.Path
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.io.TempDir

/**
 * ★ 주석을 걷은 소스에서 `ImeGate.detach(` 를 센다. 부를 수 있는 자리는 windows/games/minigame · windows/games/tetris 뿐,
 * gomoku·chess(와 그 밖 모든 창)은 0회. minigame·tetris 폴더가 생기면(W4-e 병합 뒤) 각 1회 이상이어야 한다.
 */
class ImeGateScopeContractTest {
    @Test
    fun realTreeCallsDetachOnlyFromMiniGameAndTetris() {
        val report = ImeGateScan.scan(KitGoldens.windowsMainRoot())
        assertEquals(emptyList(), report.violations, "IME 를 떼면 안 되는 창에서 ImeGate.detach 호출")
        for (dir in ImeGateScan.REQUIRED) {
            if (report.filesUnder(dir) > 0) assertTrue(report.callsUnder(dir) >= 1, "$dir 창이 ImeGate.detach 를 안 부른다")
        }
        assertEquals(0, report.callsUnder("games/gomoku"))
        assertEquals(0, report.callsUnder("games/chess"))
    }

    @Test
    fun scannerFlagsGomokuAndChessCalls(@TempDir tmp: Path) {
        val root = tmp.toFile()
        write(root, "games/gomoku/GomokuWindow.kt", "fun a(w: java.awt.Window) { ImeGate.detach(w) }")
        write(root, "games/chess/ChessWindow.kt", "fun a(w: java.awt.Window) { ImeGate . detach (w) }")
        write(root, "gacha/GachaWindow.kt", "fun a(w: java.awt.Window) { ImeGate.detach(w) }")
        write(root, "games/minigame/MiniGameWindow.kt", "fun a(w: java.awt.Window) { ImeGate.detach(w) }")
        val r = ImeGateScan.scan(root)
        assertEquals(listOf("gacha/GachaWindow.kt", "games/chess/ChessWindow.kt", "games/gomoku/GomokuWindow.kt"), r.violations)
        assertEquals(1, r.callsUnder("games/minigame"))
    }

    @Test
    fun commentsAndStringsDoNotCount(@TempDir tmp: Path) {
        val root = tmp.toFile()
        write(root, "games/gomoku/GomokuWindow.kt", """
            // ImeGate.detach(w) 는 부르지 않는다
            /* ImeGate.detach(w)
               /* 중첩 */ ImeGate.detach(w) */
            /** [ImeGate.detach] 금지 */
            val s = "ImeGate.detach(w)"
            val u = "http://x" // ImeGate.detach(w)
        """.trimIndent())
        write(root, "games/tetris/TetrisDuelWindow.kt", "val u = \"a//b\"; fun a(w: java.awt.Window) { ImeGate.detach(w) }")
        val r = ImeGateScan.scan(root)
        assertEquals(emptyList(), r.violations)
        assertEquals(0, r.callsUnder("games/gomoku"))
        assertEquals(1, r.callsUnder("games/tetris"))
    }

    @Test
    fun aliasImportIsAViolationAnywhereOutsideAllowed(@TempDir tmp: Path) {
        val root = tmp.toFile()
        write(root, "games/chess/ChessWindow.kt", "import com.yehsung.aingcheck.desktop.windows.kit.ImeGate as G\nfun a(w: java.awt.Window) { G.detach(w) }")
        assertEquals(listOf("games/chess/ChessWindow.kt"), ImeGateScan.scan(root).violations)
    }

    private fun write(root: File, rel: String, text: String) {
        val f = File(root, rel)
        f.parentFile.mkdirs()
        f.writeText(text)
    }
}

/** 소스 스캐너(시험 전용). */
object ImeGateScan {
    val ALLOWED = listOf("games/minigame", "games/tetris")
    val REQUIRED = ALLOWED
    private val call = Regex("""\bImeGate\s*\.\s*detach\s*\(""")
    private val alias = Regex("""\bimport\s+[\w.]*\bImeGate\b(\s+as\b|\s*\.\s*detach\b)""")

    data class Report(val calls: Map<String, Int>, val aliased: Set<String>) {
        val violations: List<String>
            get() = calls.keys.union(aliased).filter { rel ->
                ((calls[rel] ?: 0) > 0 || rel in aliased) && ALLOWED.none { rel.startsWith("$it/") }
            }.sorted()

        fun callsUnder(dir: String): Int = calls.filterKeys { it.startsWith("$dir/") }.values.sum()
        fun filesUnder(dir: String): Int = calls.keys.count { it.startsWith("$dir/") }
    }

    fun scan(root: File): Report {
        val calls = sortedMapOf<String, Int>()
        val aliased = mutableSetOf<String>()
        if (!root.isDirectory) return Report(calls, aliased)
        root.walkTopDown().filter { it.isFile && it.extension == "kt" }.forEach { f ->
            val rel = f.relativeTo(root).invariantSeparatorsPath
            val code = stripComments(f.readText())
            calls[rel] = call.findAll(code).count()
            if (alias.containsMatchIn(code)) aliased += rel
        }
        return Report(calls, aliased)
    }

    /** Kotlin 주석(//, 중첩 가능한 /* */)과 문자열·문자 리터럴 내용을 걷는다. 원시 문자열(""") 포함. */
    fun stripComments(src: String): String {
        val out = StringBuilder(src.length)
        var i = 0
        var depth = 0
        while (i < src.length) {
            val c = src[i]
            val n = if (i + 1 < src.length) src[i + 1] else '\u0000'
            when {
                depth > 0 && c == '*' && n == '/' -> { depth--; i += 2 }
                depth > 0 && c == '/' && n == '*' -> { depth++; i += 2 }
                depth > 0 -> i++
                c == '/' && n == '*' -> { depth = 1; i += 2 }
                c == '/' && n == '/' -> { while (i < src.length && src[i] != '\n') i++ }
                src.startsWith("\"\"\"", i) -> {
                    val end = src.indexOf("\"\"\"", i + 3)
                    out.append("\"\"")
                    i = if (end < 0) src.length else end + 3
                }
                c == '"' || c == '\'' -> {
                    i++
                    while (i < src.length && src[i] != c && src[i] != '\n') { if (src[i] == '\\') i++; i++ }
                    i++
                    out.append(c).append(c)
                }
                else -> { out.append(c); i++ }
            }
        }
        return out.toString()
    }
}
