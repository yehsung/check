// 원본: 없음(새 시험) — 설계 D5(색은 테마 토큰만) · overlay.md §5 b2 OverlayColorLiteralTest(overlay/** 에 `Color(0x` 0건)
//       기억 source-contract-tests-need-comment-stripping(주석·문자열 속 글자는 세지 않는다)
package com.yehsung.aingcheck.desktop.overlay.render

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class OverlayColorLiteralTest {
    private val pkg = "com/yehsung/aingcheck/desktop/overlay"

    private fun overlayRoots(): List<File> {
        val module = File(System.getProperty("user.dir"))
        return listOf("src/main/kotlin", "src/test/kotlin").map { File(module, "$it/$pkg") }.filter { it.isDirectory }
    }

    @Test
    fun overlaySourcesHaveNoColorLiterals() {
        val roots = overlayRoots()
        assertTrue(roots.isNotEmpty(), "overlay 소스 폴더를 못 찾았다(user.dir=${System.getProperty("user.dir")})")
        val files = roots.flatMap { r -> r.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList() }
        assertTrue(files.size >= 5, "overlay 소스가 너무 적다: ${files.size}")
        val hits = files.flatMap { f -> colorLiterals(f.readText()).map { "${f.relativeTo(roots.first().parentFile)}:$it" } }
        assertEquals(emptyList(), hits, "overlay/** 의 색은 AingColors 토큰으로(D5)")
    }

    @Test
    fun scannerSeesCodeButNotCommentsOrStrings() {
        assertEquals(1, colorLiterals("val c = Color(0xFF112233)\n").size)
        assertEquals(1, colorLiterals("val c = Color (0xff112233)\n").size)
        assertEquals(0, colorLiterals("// Color(0xFF112233)\n/* Color(0x1) */ val s = \"Color(0x2)\"\n").size)
    }

    companion object {
        private val LITERAL = Regex("""\bColor\s*\(\s*0[xX]""")

        /** 주석·문자열을 걷어 낸 뒤 `Color(0x` 가 있는 줄 번호들. */
        fun colorLiterals(src: String): List<Int> {
            val code = stripCommentsAndStrings(src)
            return code.lines().mapIndexedNotNull { i, line -> if (LITERAL.containsMatchIn(line)) i + 1 else null }
        }

        private fun stripCommentsAndStrings(src: String): String {
            val out = StringBuilder(src.length)
            var i = 0
            while (i < src.length) {
                val c = src[i]
                val n = if (i + 1 < src.length) src[i + 1] else '\u0000'
                when {
                    c == '/' && n == '/' -> { while (i < src.length && src[i] != '\n') i++ }
                    c == '/' && n == '*' -> {
                        i += 2
                        while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) { if (src[i] == '\n') out.append('\n'); i++ }
                        i += 2
                    }
                    c == '\'' -> {
                        // 글자 리터럴('"' · '\'' · '\u0000') — 안의 따옴표가 문자열 시작으로 읽히지 않게 통째로 건너뛴다.
                        i++
                        while (i < src.length && src[i] != '\'' && src[i] != '\n') i += if (src[i] == '\\') 2 else 1
                        i++
                        out.append("''")
                    }
                    c == '"' -> {
                        val triple = src.startsWith("\"\"\"", i)
                        i += if (triple) 3 else 1
                        while (i < src.length) {
                            if (triple && src.startsWith("\"\"\"", i)) { i += 3; break }
                            if (!triple && src[i] == '\\') { i += 2; continue }
                            if (!triple && src[i] == '"') { i++; break }
                            if (src[i] == '\n') out.append('\n')
                            i++
                        }
                        out.append("\"\"")
                    }
                    else -> { out.append(c); i++ }
                }
            }
            return out.toString()
        }
    }
}
