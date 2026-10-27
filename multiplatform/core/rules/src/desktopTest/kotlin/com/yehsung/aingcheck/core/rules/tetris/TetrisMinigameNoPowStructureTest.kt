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
 *
 * 훑는 범위 밖(다른 패키지의 도우미)이 초월함수를 감싸 부르면 위 시험은 못 본다(검증 지적) — 그래서 규칙 소스가 **밖에서 들여오는 것**을
 * 목록으로 잠그고([ALLOWED_FOREIGN_IMPORTS] — 늘거나 줄면 빨강), 들여온 앱 심볼의 패키지 소스도 같은 검사로 (이어서) 훑는다.
 */
class TetrisMinigameNoPowStructureTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다" })

    companion object {
        /**
         * tetris · minigame 패키지 main 소스가 밖에서 들여오는 것 전부. 새 의존을 들이면 여기서 먼저 빨개진다 — 그 의존이 결정적인지
         * (초월함수·플랫폼 수학을 안 부르는지) 보고 목록에 더한다. 앱 심볼(com.yehsung.aingcheck.…)은 아래 시험이 그 패키지 소스까지 훑는다.
         */
        val ALLOWED_FOREIGN_IMPORTS: Set<String> = setOf(
            "com.yehsung.aingcheck.core.foundation.rng.SplitMix64",
            "kotlin.math.abs",
            "kotlin.math.floor",
            "kotlin.math.truncate",
        )

        private val OWN_PACKAGES = listOf("com.yehsung.aingcheck.core.rules.tetris", "com.yehsung.aingcheck.core.rules.minigame")

        private fun isOwn(fqn: String): Boolean = OWN_PACKAGES.any { fqn == it || fqn.startsWith("$it.") }

        private val IMPORT = Regex("""(?m)^\s*import\s+([A-Za-z0-9_.*]+)(?:\s+as\s+[A-Za-z0-9_]+)?\s*$""")

        /** 주석을 걷은 코드의 import 대상(별칭은 떼고 대상만). */
        fun imports(raw: String): List<String> = IMPORT.findAll(StructureRules.stripComments(raw)).map { it.groupValues[1] }.toList()

        /** import 없이 완전한 이름으로 부르는 앱 심볼(`com.yehsung.aingcheck.x.y(`) — 목록을 우회하는 길이라 막는다. */
        private val QUALIFIED_APP = Regex("""\bcom\s*\.\s*yehsung\s*\.\s*aingcheck\s*\.[A-Za-z0-9_.]+""")

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

    /** 앱 심볼 FQN → 그 패키지의 main 소스 파일들(core/x 모듈은 core/x, 그 밖은 첫 마디 모듈). 못 찾으면 빈 목록. */
    private fun packageSources(fqn: String): List<File> {
        val parts = fqn.removePrefix("com.yehsung.aingcheck.").split('.')
        val pkg = parts.dropLast(1)
        val module = if (pkg.firstOrNull() == "core" && pkg.size >= 2) "core/${pkg[1]}" else pkg.firstOrNull() ?: return emptyList()
        val src = File(mpRoot, "$module/src")
        if (!src.isDirectory) return emptyList()
        val pkgPath = "com/yehsung/aingcheck/" + pkg.joinToString("/")
        return src.listFiles().orEmpty()
            .filter { it.isDirectory && !(it.name == "test" || it.name.endsWith("Test")) }
            .flatMap { File(it, "kotlin/$pkgPath").listFiles().orEmpty().filter { f -> f.isFile && f.name.endsWith(".kt") } }
            .sortedBy { it.path }
    }

    @Test
    fun foreignDependenciesAreLockedAndAlsoFreeOfTranscendentals() {
        val files = ruleSources()
        val foreign = sortedSetOf<String>()
        val qualified = mutableListOf<String>()
        for (f in files) {
            val raw = f.readText()
            imports(raw).filterNot { isOwn(it) }.forEach { foreign += it }
            val code = StructureRules.stripComments(raw).lines().filterNot { it.trimStart().startsWith("import ") || it.trimStart().startsWith("package ") }
            code.forEachIndexed { i, line ->
                QUALIFIED_APP.findAll(line).map { it.value.replace(Regex("""\s"""), "") }.filterNot { isOwn(it) }
                    .forEach { qualified += "${f.name}:${i + 1} $it" }
            }
        }
        assertEquals(emptyList(), qualified, "규칙 소스가 import 없이 완전한 이름으로 바깥 앱 심볼을 부른다(목록 우회)")
        assertEquals(ALLOWED_FOREIGN_IMPORTS, foreign.toSet(), "규칙 소스가 밖에서 들여오는 목록이 바뀌었다 — 결정적인지 보고 ALLOWED_FOREIGN_IMPORTS 를 고친다")
        // 들여온 앱 심볼의 패키지 소스를 이어서 훑는다(그 소스가 또 들여오는 앱 심볼까지).
        val queue = ArrayDeque(foreign.filter { it.startsWith("com.yehsung.aingcheck.") })
        val scanned = LinkedHashSet<String>()
        val found = mutableListOf<String>()
        while (queue.isNotEmpty()) {
            val fqn = queue.removeFirst()
            val sources = packageSources(fqn)
            assertTrue(sources.isNotEmpty(), "들여온 앱 심볼 $fqn 의 소스를 못 찾았다 — 훑지 못하면 초록이 거짓이 된다")
            for (src in sources) {
                val rel = src.relativeTo(mpRoot).invariantSeparatorsPath
                if (!scanned.add(rel)) continue
                val raw = src.readText()
                found += violations(rel, raw)
                imports(raw).filter { it.startsWith("com.yehsung.aingcheck.") && !isOwn(it) }.forEach { queue.addLast(it) }
            }
        }
        assertEquals(emptyList(), found, "규칙이 들여온 의존 소스가 libm 초월함수를 부른다:\n${found.joinToString("\n")}")
        assertTrue(scanned.isNotEmpty(), "의존 소스를 하나도 훑지 않았다")
        println("AINGCHECK-NO-POW-DEPS foreign=${foreign.size} scanned=${scanned.joinToString(",")} violations=0")
    }

    /** 대조: 목록 비교 · 의존 훑기가 실제로 잡는다(기준선이 다른 입력). */
    @Test
    fun importListingCatchesNewDependenciesAndAliases() {
        val sample = "package x\n\nimport kotlin.math.pow as pw\nimport com.yehsung.aingcheck.core.foundation.rng.SplitMix64\n" +
            "// import kotlin.math.exp\nimport kotlin.math.*\nval a = 1\n"
        assertEquals(listOf("kotlin.math.pow", "com.yehsung.aingcheck.core.foundation.rng.SplitMix64", "kotlin.math.*"), imports(sample))
        assertTrue(packageSources("com.yehsung.aingcheck.core.foundation.rng.SplitMix64").any { it.name == "SplitMix64.kt" })
        assertEquals(1, QUALIFIED_APP.findAll("val r = com.yehsung.aingcheck.core.foundation.math.Fast.cube(x)").count())
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
