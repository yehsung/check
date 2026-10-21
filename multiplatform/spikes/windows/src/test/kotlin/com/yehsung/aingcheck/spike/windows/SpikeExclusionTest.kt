package com.yehsung.aingcheck.spike.windows

import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 구조 시험(G §8-3): 탐침은 출시 빌드에 들어가지 않는다.
 * - multiplatform/ 아래 spikes/ 밖의 Gradle 스크립트가 spikes 를 가리키지 않는다(include·project·srcDir 무엇이든).
 * - spikes/ 밖의 Kotlin 소스가 탐침 패키지를 import 하지 않는다.
 * 주석은 걷어 내고 본다(기억 source-contract-tests-need-comment-stripping).
 */
class SpikeExclusionTest {
    companion object {
        private val blockComment = Regex("/\\*.*?\\*/", RegexOption.DOT_MATCHES_ALL)
        private val lineComment = Regex("//[^\n]*")

        fun stripComments(src: String): String = lineComment.replace(blockComment.replace(src, ""), "")

        fun violations(repoRoot: File): List<String> {
            val mp = File(repoRoot, "multiplatform")
            val spikes = File(mp, "spikes").canonicalFile
            if (!mp.isDirectory) return emptyList()
            return mp.walkTopDown()
                .onEnter { dir -> dir.canonicalFile != spikes && dir.name != "build" && dir.name != ".gradle" }
                .filter { it.isFile }
                .mapNotNull { f ->
                    val code = stripComments(f.readText())
                    when {
                        f.name.endsWith(".gradle.kts") && code.contains("spikes") -> "${f.relativeTo(repoRoot)}: spikes 참조"
                        f.name.endsWith(".kt") && code.contains("com.yehsung.aingcheck.spike") -> "${f.relativeTo(repoRoot)}: 탐침 패키지 참조"
                        else -> null
                    }
                }
                .toList()
        }
    }

    @Test
    fun releaseBuildDoesNotReachSpikes() {
        val root = File(System.getProperty("spike.repoRoot") ?: error("spike.repoRoot 가 없다"))
        // 뿌리를 잘못 잡으면 빈 목록으로 초록이 난다 — 자기 자신이 보이는지 먼저 본다.
        assertTrue(File(root, "multiplatform/spikes/windows/settings.gradle.kts").isFile, "repoRoot 오설정: $root")
        assertEquals(emptyList(), violations(root))
    }

    @Test
    fun plantedIncludeIsCaught() {
        val root = Files.createTempDirectory("aingspike-excl").toFile()
        try {
            File(root, "multiplatform/spikes/windows").mkdirs()
            File(root, "multiplatform/spikes/windows/build.gradle.kts").writeText("// 자기 자신은 세지 않는다: spikes\n")
            val settings = File(root, "multiplatform/settings.gradle.kts")
            settings.writeText("// include(\":spikes:windows\") 는 주석이라 괜찮다\ninclude(\":core\")\n")
            File(root, "multiplatform/desktopApp/src").mkdirs()
            File(root, "multiplatform/desktopApp/src/A.kt").writeText("/* com.yehsung.aingcheck.spike 주석 */ package a\n")
            assertEquals(emptyList(), violations(root))
            settings.appendText("include(\":spikes:windows\")\n")
            File(root, "multiplatform/desktopApp/src/B.kt").writeText("import com.yehsung.aingcheck.spike.windows.Smoke\n")
            assertEquals(2, violations(root).size, violations(root).toString())
        } finally {
            root.deleteRecursively()
        }
    }
}
