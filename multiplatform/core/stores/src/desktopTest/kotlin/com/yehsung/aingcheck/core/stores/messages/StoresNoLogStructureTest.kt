// 원본: 없음 — INV 셋("이 모듈엔 로그가 없다 — 신고 본문 · 메시지 본문은 사람이 쓴 문장이다")을 주석이 아니라 시험으로 강제한다(검증 지적).
//   INV-MessagesRules-6c27a9b4 · INV-MessagesBlockStore-ca3a6fda · INV-MessagesBlockRules-6d651a0c 강제.
// 기억 source-contract-tests-need-comment-stripping: 주석은 걷고 본다(규약 설명에 'print' 가 나온다).
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.testkit.structure.StructureRules
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class StoresNoLogStructureTest {
    /** 로그로 새는 길(표준 출력 · 안드로이드 Log · 로거 라이브러리 · 스택 찍기). */
    private val forbidden = listOf(
        Regex("""\bprintln\s*\("""), Regex("""(?<![\w.])print\s*\("""), Regex("""\bSystem\s*\.\s*(out|err)\b"""),
        Regex("""\bLog\s*\.\s*[a-z]+\s*\("""), Regex("""\bandroid\.util\.Log\b"""), Regex("""\bLogger\b"""),
        Regex("""\bprintStackTrace\s*\("""), Regex("""\b(Napier|KotlinLogging|Timber)\b"""), Regex("""\bjava\.util\.logging\b"""),
    )

    @Test
    fun storePackagesOfThisLaneHaveNoLogging() {
        val root = System.getProperty("aingcheck.repoRoot") ?: error("aingcheck.repoRoot 가 없다 — Gradle 시험 작업으로 돌린다")
        val src = File(root, "multiplatform/core/stores/src")
        val packages = listOf("messages", "now", "rankings", "characters")
        val files = src.listFiles { f -> f.isDirectory && f.name.endsWith("Main") }.orEmpty()
            .flatMap { set -> packages.map { File(set, "kotlin/com/yehsung/aingcheck/core/stores/$it") } }
            .filter { it.isDirectory }
            .flatMap { dir -> dir.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.toList() }
            .sortedBy { it.path }
        assertTrue(files.size >= 20, "갈래 소스를 못 찾았다(${files.size}): $src")
        assertTrue(files.any { it.name == "MessagesBlockStore.kt" } && files.any { it.name == "TodoListStore.kt" })
        val hits = ArrayList<String>()
        for (file in files) {
            val code = StructureRules.stripComments(file.readText(Charsets.UTF_8))
            for (rule in forbidden) {
                rule.find(code)?.let { hits += "${file.relativeTo(src)}: ${it.value}" }
            }
        }
        assertEquals(emptyList(), hits, "메시지·지금·순위·캐릭터 스토어에 로그가 생겼다 — 신고·메시지·할 일 본문이 로그로 샌다")
    }

    /** 대조(검사가 공허하지 않다): 같은 규칙이 심은 로그 한 줄을 잡는다. 주석 속 글자는 잡지 않는다. */
    @Test
    fun ruleCatchesPlantedLogAndIgnoresComments() {
        val planted = "fun x(body: String) {\n    println(body)\n}\n"
        val commented = "// println(body) 같은 줄을 두지 않는다\nfun y() = 1\n"
        assertTrue(forbidden.any { it.containsMatchIn(StructureRules.stripComments(planted)) })
        assertTrue(forbidden.none { it.containsMatchIn(StructureRules.stripComments(commented)) })
        assertTrue(forbidden.any { it.containsMatchIn("Log.d(\"t\", body)") })
        assertTrue(forbidden.none { it.containsMatchIn("val v = blueprint(x)") }, "다른 낱말 속 print 를 로그로 잡았다")
    }
}
