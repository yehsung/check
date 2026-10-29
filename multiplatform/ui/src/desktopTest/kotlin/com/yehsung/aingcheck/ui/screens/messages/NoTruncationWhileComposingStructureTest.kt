// 원본: 없음 — G §2-3 W3-a ④ "조합 중 자르기 0" · E§8.2 ④(글자 수 상한: 조합 중에는 자르지 않고 카운터만 빨갛게, [보내기]/[저장]에서 막는다).
//
// W3-a 화면 소스(ui …/screens/{session,messages,profile} · androidApp …/screens/{session,now,messages} 의 시험 아닌 소스)를 주석을 걷고 읽어
// 입력칸 글을 **자르거나 덮는 꼴**을 찾는다(기억 source-contract-tests-need-comment-stripping).
//   T1 입력 변환 금지: InputTransformation · maxLength — 키 입력마다 글을 고치는 자리는 조합 중에도 돈다.
//   T2 값·콜백 입력칸 금지: BasicTextField(value = …) · onValueChange · TextField( · OutlinedTextField( — 상태 기반(TextFieldState)만(E§8.2 ①).
//   T3 덮어쓰기는 조합 가드 뒤에서만: setTextAndPlaceCursorAtEnd( · .edit { 를 부르는 줄 앞 8줄 안에 조합 판정(isComposing ·
//      ComposerInputRules.externalDraft · TeamFieldRules.normalizedCodeToWrite)이 있어야 한다.
//   T4 칸 글을 잘라 쓰지 않는다: .text(.toString()).take( · substring( · dropLast( · removeRange(.
// 각 규칙은 심은 위반으로 빨강이 되는 것을 같은 시험에서 확인한다.
package com.yehsung.aingcheck.ui.screens.messages

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class NoTruncationWhileComposingStructureTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))

    /** 이 갈래 화면의 시험 아닌 소스 전부(경로는 mpRoot 기준). */
    private fun screenSources(): List<Pair<String, String>> {
        val roots = listOf(
            "ui/src" to listOf("com/yehsung/aingcheck/ui/screens/session", "com/yehsung/aingcheck/ui/screens/messages", "com/yehsung/aingcheck/ui/screens/profile"),
            "androidApp/src" to listOf(
                "com/yehsung/aingcheck/android/screens/session", "com/yehsung/aingcheck/android/screens/now", "com/yehsung/aingcheck/android/screens/messages",
            ),
        )
        val out = mutableListOf<Pair<String, String>>()
        for ((srcRoot, packages) in roots) {
            val sets = File(mpRoot, srcRoot).listFiles().orEmpty().filter { it.isDirectory && !it.name.endsWith("Test") && it.name != "test" }
            for (set in sets) for (pkg in packages) {
                val dir = File(set, "kotlin/$pkg")
                if (!dir.isDirectory) continue
                dir.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.forEach { f ->
                    out += f.relativeTo(mpRoot).invariantSeparatorsPath to stripComments(f.readText())
                }
            }
        }
        return out.sortedBy { it.first }
    }

    @Test
    fun screensNeverCutTextWhileComposing() {
        val files = screenSources()
        assertTrue(files.size >= 15, "W3-a 화면 소스를 ${files.size}개만 읽었다 — 경로가 바뀌었나")
        assertTrue(files.any { it.first.endsWith("ui/screens/messages/MessageComposer.kt") }, "입력줄 소스를 못 읽었다")
        val violations = files.flatMap { (path, code) -> check(path, code) }
        assertTrue(violations.isEmpty(), "조합 중 자르기·덮어쓰기 위반:\n" + violations.joinToString("\n"))
        // 실제로 덮어쓰는 자리가 있고(가드가 빈 규칙이 아니다) 모두 가드 뒤에 있다.
        val writes = files.sumOf { (_, code) -> WRITE.findAll(code).count() }
        assertTrue(writes >= 2, "덮어쓰기 자리를 $writes 곳만 찾았다 — T3 가 아무것도 재지 않는다")
        println("AINGCHECK-NO-TRUNCATION files=${files.size} guardedWrites=$writes violations=0")
    }

    @Test
    fun plantedViolationsAreCaught() {
        val p = "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/Planted.kt"
        assertEquals(listOf("T1"), rules(p, "BasicTextField(state, inputTransformation = InputTransformation.maxLength(200))"))
        assertEquals(listOf("T1"), rules(p, "val t = InputTransformation { }"))
        assertEquals(listOf("T2"), rules(p, "BasicTextField(value = text, onValueChange = { text = it.take(200) })"))
        assertEquals(listOf("T2"), rules(p, "OutlinedTextField(value, {})"))
        assertEquals(listOf("T3"), rules(p, "fun f(state: TextFieldState) {\n  state.setTextAndPlaceCursorAtEnd(\"x\")\n}"))
        assertEquals(emptyList(), rules(p, "fun f(state: TextFieldState) {\n  if (!state.isComposing) state.setTextAndPlaceCursorAtEnd(\"x\")\n}"))
        assertEquals(listOf("T3"), rules(p, "fun f(state: TextFieldState) {\n  state.edit { replace(0, 1, \"\") }\n}"))
        assertEquals(listOf("T4"), rules(p, "store.setDraft(state.text.toString().take(200), peer)"))
        assertEquals(listOf("T4"), rules(p, "val cut = field.text.substring(0, 40)"))
        // 주석 속 문형은 위반이 아니다(주석을 걷고 본다).
        assertEquals(emptyList(), rules(p, "// InputTransformation.maxLength(200) 은 쓰지 않는다\nval ok = 1"))
    }

    /** 걸린 규칙 이름(같은 규칙이 한 줄에 여러 번 걸려도 하나로). */
    private fun rules(path: String, code: String): List<String> = check(path, stripComments(code)).map { it.substringBefore(' ') }.distinct()

    private fun check(path: String, code: String): List<String> {
        val out = mutableListOf<String>()
        fun line(offset: Int) = code.substring(0, offset).count { it == '\n' } + 1
        Regex("""\bInputTransformation\b|\bmaxLength\s*\(""").findAll(code).forEach { out += "T1 $path:${line(it.range.first)} 입력 변환(조합 중에도 글을 고친다)" }
        Regex("""\bBasicTextField\s*\(\s*value\s*=|\bonValueChange\b|(?<![A-Za-z])(?:Outlined)?TextField\s*\(""").findAll(code)
            .forEach { out += "T2 $path:${line(it.range.first)} 값·콜백 입력칸(상태 기반 TextFieldState 만)" }
        val lines = code.lines()
        WRITE.findAll(code).forEach { m ->
            val at = line(m.range.first)
            val window = lines.subList(maxOf(0, at - 9), at).joinToString("\n")
            if (!GUARD.containsMatchIn(window)) out += "T3 $path:$at 조합 가드 없이 입력칸을 덮는다"
        }
        Regex("""\.text(?:\.toString\(\))?\.(?:take|substring|dropLast|removeRange)\s*\(""").findAll(code)
            .forEach { out += "T4 $path:${line(it.range.first)} 입력칸 글을 잘라 쓴다" }
        return out
    }

    private companion object {
        val WRITE = Regex("""\.setTextAndPlaceCursorAtEnd\s*\(|\.edit\s*\{""")
        val GUARD = Regex("""\bisComposing\b|\bexternalDraft\s*\(|\bnormalizedCodeToWrite\s*\(""")

        /** `//` 줄 주석 · `/* */` 묶음 주석을 걷는다(글자 리터럴 안의 // 는 그대로 — 단순 상태기계). */
        fun stripComments(src: String): String {
            val out = StringBuilder(src.length)
            var i = 0
            var inString = false
            while (i < src.length) {
                val c = src[i]
                if (inString) {
                    out.append(c)
                    if (c == '\\' && i + 1 < src.length) { out.append(src[i + 1]); i += 2; continue }
                    if (c == '"') inString = false
                    i++
                    continue
                }
                if (c == '"') { inString = true; out.append(c); i++; continue }
                if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
                    while (i < src.length && src[i] != '\n') i++
                    continue
                }
                if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
                    i += 2
                    while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) { if (src[i] == '\n') out.append('\n'); i++ }
                    i += 2
                    continue
                }
                out.append(c)
                i++
            }
            return out.toString()
        }
    }
}
