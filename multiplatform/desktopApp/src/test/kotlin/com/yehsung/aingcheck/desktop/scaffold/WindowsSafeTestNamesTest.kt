// 맥에서 초록인 시험 이름이 Windows 러너에서 컴파일을 깬다(int-w3 mp-ci 41048831429 — 역따옴표 이름의 `"` 가 클래스 파일 이름
// `…Test$<이름>$1.class` 에 들어가 InvalidPathException). 맥·리눅스 게이트가 먼저 잡도록 저장소 안 코틀린 시험 이름을 센다.
package com.yehsung.aingcheck.desktop.scaffold

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WindowsSafeTestNamesTest {
    /** Windows 파일 이름 금지 글자(< > : " / \ | ? *). 역따옴표 함수 이름은 람다·지역 클래스 파일 이름에 그대로 실린다. */
    private val illegal = Regex("""[<>:"/\\|?*]""")
    /** 선언 줄만(주석·KDoc 안의 글은 뺀다): 줄머리 들여쓰기 · 주석 줄(`*`·`//`) 아님 · 이름 뒤 `(`. */
    private val backtickFun = Regex("""(?m)^[ \t]*(?:@[\w.]+(?:\([^)\n]*\))?[ \t]+)*(?:(?:private|internal|public|override|suspend)[ \t]+)*fun[ \t]+`([^`\n]+)`[ \t]*\(""")
    private val testDir = Regex("""/src/[A-Za-z]*[Tt]est/""")

    private fun multiplatformRoot(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "settings.gradle.kts").isFile) dir = dir.parentFile
        return requireNotNull(dir) { "multiplatform 뿌리를 못 찾았다" }
    }

    @Test
    fun backtickTestNamesUseOnlyWindowsSafeCharacters() {
        val root = multiplatformRoot()
        val sources = root.walkTopDown()
            .onEnter { it.name != "build" && it.name != ".gradle" }
            .filter { it.isFile && it.extension == "kt" && testDir.containsMatchIn(it.invariantSeparatorsPath) }
            .toList()
        assertTrue(sources.size > 100, "시험 소스를 거의 못 읽었다(${sources.size}) — 뿌리 찾기가 헛돈다")
        val offenders = sources.flatMap { f ->
            backtickFun.findAll(f.readText()).map { it.groupValues[1] }.filter { illegal.containsMatchIn(it) }
                .map { "${f.relativeTo(root).invariantSeparatorsPath}: $it" }.toList()
        }
        assertEquals(emptyList(), offenders, "Windows 에서 클래스 파일을 못 쓰는 시험 이름")
    }
}
