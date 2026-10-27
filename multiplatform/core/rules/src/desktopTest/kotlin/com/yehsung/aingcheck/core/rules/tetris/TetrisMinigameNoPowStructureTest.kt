// 원본: 없음 — G §2-3 W1-a ③ "런타임 pow 호출 0(구조 시험). 중력은 비트 표를 쓴다" · G §8-14(pow 비트가 Darwin↔JVM, aarch64↔amd64 에서 갈린다).
package com.yehsung.aingcheck.core.rules.tetris

import com.yehsung.aingcheck.testkit.structure.StructureRules
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 결정적 게임 규칙(core/rules 의 tetris · minigame · minigame/crossy main 소스)은 libm 초월함수를 부르지 않는다 —
 * `pow` · `exp` · `ln`/`log` · 삼각함수 · `Math.`/`StrictMath.` 의 그것들. JVM `Math.pow` 는 aarch64·amd64 끼리도 비트가 다르다(W0-b C-X1).
 * 테트리스 중력은 [TetrisGame.GRAVITY_SECONDS_BITS] 표, 플래피 easeOut 은 곱셈(이산 등급)이다. 주석은 걷고 본다(설명에 pow 를 적어도 된다).
 */
class TetrisMinigameNoPowStructureTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다" })

    companion object {
        private const val NAMES = "pow|exp|expm1|ln|ln1p|log|log2|log10|sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|cbrt|hypot"

        /**
         * 맨 이름 호출(`pow(`·`exp(`) — 앞이 `.`(남의 메서드: 길건너 `lane.log(under:)`)이거나 `fun `(선언)이면 뺀다 ·
         * 확장 `x.pow(` · 완전한 이름 `kotlin.math.…(` · `Math.…` · `StrictMath`.
         */
        val TRANSCENDENTAL = Regex(
            """(?<![A-Za-z0-9_.])(?<!fun )(?:$NAMES)\s*\(""" +
                """|\.\s*pow\s*\(|\bkotlin\s*\.\s*math\s*\.\s*(?:$NAMES)\b|\bMath\s*\.\s*(?:$NAMES)\b|\bStrictMath\b""",
        )

        /** 주석을 걷은 코드에서 찾은 자리("상대 경로:줄 줄 글자"). */
        fun violations(relPath: String, raw: String): List<String> {
            val code = StructureRules.stripComments(raw)
            return TRANSCENDENTAL.findAll(code).map { m ->
                val line = code.substring(0, m.range.first).count { it == '\n' } + 1
                "$relPath:$line  ${raw.lines().getOrElse(line - 1) { "" }.trim()}"
            }.toList()
        }
    }

    private fun ruleSources(): List<File> {
        val base = File(mpRoot, "core/rules/src")
        return base.walkTopDown()
            .filter { it.isFile && it.name.endsWith(".kt") }
            .filter { f ->
                val rel = f.relativeTo(base).invariantSeparatorsPath
                val sourceSet = rel.substringBefore('/')
                !(sourceSet == "test" || sourceSet.endsWith("Test")) &&
                    (rel.contains("/com/yehsung/aingcheck/core/rules/tetris/") || rel.contains("/com/yehsung/aingcheck/core/rules/minigame/"))
            }
            .sortedBy { it.path }
            .toList()
    }

    @Test
    fun deterministicRulesCallNoTranscendentalFunctions() {
        val files = ruleSources()
        assertTrue(files.size >= 8, "훑은 규칙 소스가 너무 적다(${files.size}) — 경로가 바뀌었나: ${files.map { it.name }}")
        assertTrue(files.any { it.name == "TetrisGame.kt" } && files.any { it.name == "FlappyGame.kt" } && files.any { it.name == "CrossyGame.kt" })
        val found = files.flatMap { violations(it.relativeTo(mpRoot).invariantSeparatorsPath, it.readText()) }
        assertEquals(emptyList(), found, "결정적 규칙이 libm 초월함수를 부른다 — 비트 표나 곱셈으로 바꾼다:\n${found.joinToString("\n")}")
        println("AINGCHECK-NO-POW files=${files.size} violations=0")
    }

    /** 대조: 심은 호출은 잡히고, 주석·이름 일부(`powerUp(`·`exponent`)는 잡히지 않는다. */
    @Test
    fun plantedCallsAreCaughtAndCommentsAreNot() {
        assertEquals(1, violations("x.kt", "val a = kotlin.math.pow(x, 3.0)\n").size)
        assertEquals(1, violations("x.kt", "val a = x.pow(3)\n").size)
        assertEquals(1, violations("x.kt", "val a = Math.pow(x, 3.0)\n").size)
        assertEquals(1, violations("x.kt", "val a = StrictMath.cbrt(x)\n").size)
        assertEquals(1, violations("x.kt", "val e = exp(1.0)\n").size)
        assertEquals(0, violations("x.kt", "// pow(x, 3) 대신 곱셈\n/* Math.pow */ val y = powerUp(x) + exponent\n").size)
        assertEquals(0, violations("x.kt", "val q = 1 - progress\nval eased = 1 - q * q * q\n").size)
        assertEquals(0, violations("x.kt", "fun log(under: Double) = 1\nval m = lane.log(player.x)\n").size)
        assertEquals(1, violations("x.kt", "val m = log(x, 2.0)\n").size)
    }
}
