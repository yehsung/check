// 원본: 없음(W1-c 구조 시험 — ART 의 java.util.regex(ICU)가 `\d`·`\s`·`\w` 를 유니코드 전체로 받는 갈림 · G §8-16 ② `Character.getType` 금지 ·
//       6차 c-fold: 날짜 파서를 foundation 한 자리로 모았으니 foundation·wire·net 기기 소스까지 잰다)
package com.yehsung.aingcheck.core.rules.text

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 데스크톱 JDK 시험만으로는 안 보이는 Android 갈림을 **소스 모양**으로 막는다.
 *
 *  ① core 바닥(rules · foundation · wire · net)의 기기에서 도는 소스(commonMain · androidMain)의 문자열 리터럴에 정규식 축약
 *     `\d \D \s \S \w \W \b \B` 금지. foundation·wire·net 은 6차 c-fold 에서 더했다 — 날짜 파서가 foundation(`time/IcuInternetDate`)
 *     한 자리로 모였고, wire `SwiftISO8601` 가 옛 정규식(`\d`)을 되살리면 여기서 빨개진다.
 *     JDK 의 java.util.regex 는 이것들을 ASCII 로 읽지만 ART 의 java.util.regex 는 ICU 라 Nd · White_Space · 유니코드 글자 전체를 받는다
 *     (W1-c 날짜 파서에서 에뮬레이터 API 36 실측 — `0.١٢` 가 소수부로 잡혀 터졌다). 숫자는 `[0-9]`, 공백은 명시 집합으로 적는다.
 *  ② W1-c 패키지(gacha · weekly · achievements · insights · todo · text · character · ailimit · token · format)에서 `Character.getType` 에
 *     기대는 Char 판정(isDigit · isLetter · isLetterOrDigit · isWhitespace · 인자 없는 trim · digitToInt) 금지 — G §8-16 ②: JDK 21 = Unicode 15.0,
 *     ART 는 API 마다 다르다. 번들 표(TextScalars)나 ASCII 비교로 쓴다. 날짜 파서 한 벌 — foundation 세 파일([FOUNDATION_DATE_PARSER])과
 *     wire 입구([WIRE_DATE_ENTRY])도 같다(6차 c-fold 검증 지적으로 입구를 더했다).
 *
 * 주석은 걷고 본다(주석에 `\d` 를 설명으로 적는 것은 괜찮다 — 기억 source-contract-tests-need-comment-stripping).
 */
class PlatformUnicodeStructureTest {
    private val moduleDir: File = File(System.getProperty("user.dir"))

    private fun mainSources(dir: File = moduleDir): List<File> {
        val roots = listOf("src/commonMain/kotlin", "src/androidMain/kotlin").map { File(dir, it) }
        assertTrue(File(dir, "src/commonMain/kotlin").isDirectory, "${dir.name} commonMain 을 못 찾았다(user.dir=$moduleDir)")
        return roots.filter { it.isDirectory }.flatMap { root -> root.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.toList() }
    }

    /** core/rules 옆 모듈(foundation · wire · net)의 기기 소스 — rules 가 기대는 바닥이고 날짜 파서가 여기 있다. */
    private fun lowerModuleSources(): List<File> = LOWER_MODULES.flatMap { mainSources(File(moduleDir.parentFile, it)) }

    @Test
    fun noShorthandRegexClassesInDeviceSources() {
        val rules = mainSources()
        assertTrue(rules.size >= 40, "core/rules 기기 소스가 너무 적다(${rules.size}) — 경로가 바뀌었으면 시험이 헛돈다")
        val lower = lowerModuleSources()
        val lowerPaths = lower.map { it.invariantSeparatorsPath }
        for (must in FOUNDATION_DATE_PARSER + WIRE_DATE_ENTRY) {
            assertTrue(lowerPaths.any { it.endsWith(must) }, "날짜 파서 자리 $must 를 못 찾았다 — 옮겼으면 이 목록부터 고친다(시험이 헛돈다)")
        }
        val files = rules + lower
        val offenders = ArrayList<String>()
        var literals = 0
        for (file in files) {
            for (literal in stringLiterals(stripComments(file.readText()))) {
                literals++
                val escapes = if (literal.raw) RAW_SHORTHAND else ESCAPED_SHORTHAND
                escapes.find(literal.body)?.let { offenders += "${file.relativeTo(moduleDir)}:${literal.line}: ${it.value} in ${literal.body.take(80)}" }
            }
        }
        println("AINGCHECK-W1C structure regex files=${files.size}(rules ${rules.size} · foundation·wire·net ${lower.size}) literals=$literals offenders=${offenders.size}")
        if (offenders.isNotEmpty()) {
            fail("정규식 축약 클래스는 ART(ICU)에서 유니코드 전체를 받는다 — [0-9] · 명시 집합으로 적는다:\n" + offenders.joinToString("\n"))
        }
    }

    @Test
    fun noCharacterGetTypePredicatesInW1cPackages() {
        val w1c = mainSources().filter { file ->
            val path = file.invariantSeparatorsPath
            W1C_PACKAGES.any { "/com/yehsung/aingcheck/core/rules/$it/" in path }
        }
        assertTrue(w1c.size >= 30, "W1-c 패키지 소스가 너무 적다(${w1c.size})")
        // 날짜 파서 한 벌 = foundation 세 파일 + wire 의 입구(SwiftDate — Swift parseDate). 입구에 getType 판정이 끼면 파서를 모은 뜻이 없다.
        val dateParser = FOUNDATION_DATE_PARSER + WIRE_DATE_ENTRY
        val parser = lowerModuleSources().filter { file -> dateParser.any { file.invariantSeparatorsPath.endsWith(it) } }
        assertEquals(dateParser.size, parser.size, "날짜 파서 파일을 다 못 찾았다: ${parser.map { it.name }}")
        val files = w1c + parser
        val offenders = ArrayList<String>()
        for (file in files) {
            val code = blankStrings(stripComments(file.readText()))
            for ((index, line) in code.lines().withIndex()) {
                GET_TYPE_PREDICATES.find(line)?.let { offenders += "${file.relativeTo(moduleDir)}:${index + 1}: ${it.value.trim()}" }
            }
        }
        println("AINGCHECK-W1C structure getType files=${files.size} offenders=${offenders.size}")
        if (offenders.isNotEmpty()) {
            fail("Character.getType 에 기대는 판정은 JDK · ART 판마다 답이 다르다(G §8-16 ②) — TextScalars 번들 표나 ASCII 비교로 쓴다:\n" + offenders.joinToString("\n"))
        }
    }

    /** 걸러 내는 규칙 자체가 살아 있는지(항상 참인 단언이 되지 않게) — 심은 줄은 잡고, 주석 · 명시 집합 · 글자 리터럴은 놓는다. */
    @Test
    fun scannerCatchesPlantedLinesAndIgnoresComments() {
        val planted = listOf(
            "// 주석의 \\d 는 괜찮다",
            "/* 블록 주석 \\s 도 /* 겹친 \\w */ 괜찮다 */",
            "private val A = Regex(\"\"\"^([0-9]{4})-\\d{2}$\"\"\")",
            "private val B = Regex(\"^\\\\s*x$\")",
            "private val C = \"[0-9]+\"",
            "val d = c.isDigit()",
            "val e = \"isDigit() 는 글자일 뿐 \\\\\\\\d 는 역슬래시 글자\"",
            "val f = raw.trim()",
            "val g = raw.trim { it == ' ' }",
            "val h = \"${'$'}{if (x) \"\\\\D\" else \"a\"}\"",
            "val i = '\"'; val j = \"\\\\w\"",
            "val k = '\\''; val l = \"x\".isLetter()",
        ).joinToString("\n")
        val literals = stringLiterals(stripComments(planted))
        val hits = literals.mapNotNull { (if (it.raw) RAW_SHORTHAND else ESCAPED_SHORTHAND).find(it.body)?.value }.sorted()
        assertTrue(hits == listOf("\\\\D", "\\\\s", "\\\\w", "\\d"), "정규식 축약 감지가 어긋났다: $hits (literals=${literals.map { it.body }})")
        val predicateHits = blankStrings(stripComments(planted)).lines().mapNotNull { GET_TYPE_PREDICATES.find(it)?.value?.trim() }
        assertTrue(predicateHits == listOf(".isDigit(", ".trim()", ".isLetter("), "getType 판정 감지가 어긋났다: $predicateHits")
    }

    private data class Literal(val body: String, val raw: Boolean, val line: Int)

    companion object {
        val W1C_PACKAGES = listOf("gacha", "weekly", "achievements", "insights", "todo", "text", "character", "ailimit", "token", "format")

        /** core/rules 와 같은 판정을 받는 바닥 모듈(core/ 아래 이름). */
        val LOWER_MODULES = listOf("foundation", "wire", "net")

        /** 날짜 파서 한 벌(c-fold) — 숫자는 Swift 표의 Nd([DecimalDigits]), 달력은 Foundation 그레고리력. */
        val FOUNDATION_DATE_PARSER = listOf(
            "core/foundation/src/commonMain/kotlin/com/yehsung/aingcheck/core/foundation/time/IcuInternetDate.kt",
            "core/foundation/src/commonMain/kotlin/com/yehsung/aingcheck/core/foundation/time/FoundationGregorian.kt",
            "core/foundation/src/commonMain/kotlin/com/yehsung/aingcheck/core/foundation/text/DecimalDigits.kt",
        )

        /** wire 의 날짜 입구(Swift parseDate) — 옛 정규식이 살던 자리. */
        val WIRE_DATE_ENTRY = listOf("core/wire/src/commonMain/kotlin/com/yehsung/aingcheck/core/wire/SwiftDate.kt")

        /** 원시 문자열(`"""…"""`) 안의 `\d` 꼴(앞 역슬래시가 짝수 개일 때만 — `\\d` 는 글자 역슬래시 + d). */
        private val RAW_SHORTHAND = Regex("""(?<!\\)(?:\\\\)*\\[dDsSwWbB]""")

        /** 보통 문자열(`"…"`) 안의 `\\d` 꼴(Kotlin 이스케이프를 풀면 `\d`). */
        private val ESCAPED_SHORTHAND = Regex("""(?<!\\)(?:\\\\\\\\)*\\\\[dDsSwWbB]""")

        private val GET_TYPE_PREDICATES = Regex("""\.(isDigit|isLetter|isLetterOrDigit|isWhitespace|digitToInt|digitToIntOrNull)\(|\.trim(Start|End)?\(\)""")

        /**
         * Kotlin 소스를 조각으로 가른다 — 코드 · 주석(`//` · 겹칠 수 있는 `/* */`) · 문자열(`"…"` · `"""…"""`, 템플릿 `${…}` 안의 문자열까지) · 글자(`'…'`).
         * 문자열 조각은 리터럴 몸(따옴표 안)을 들고, 템플릿 식은 코드로 다시 가른다.
         */
        private sealed interface Piece {
            data class Code(val text: String) : Piece
            data class Comment(val text: String) : Piece
            data class Str(val body: String, val raw: Boolean, val line: Int, val text: String) : Piece
        }

        private class Lexer(val src: String) {
            var i = 0
            var line = 1
            val pieces = ArrayList<Piece>()
            /** 템플릿 `${…}` 안에서 만난 문자열(겉 문자열 조각의 글자에 이미 들어 있으므로 다시 잇지 않고, 리터럴 검사에만 쓴다). */
            val nested = ArrayList<Piece.Str>()
            private val code = StringBuilder()

            private fun flushCode() { if (code.isNotEmpty()) { pieces += Piece.Code(code.toString()); code.setLength(0) } }

            private fun advance(n: Int): String {
                val s = src.substring(i, minOf(i + n, src.length))
                line += s.count { it == '\n' }
                i += s.length
                return s
            }

            fun run(stopAtBrace: Boolean = false): List<Piece> {
                var depth = 0
                while (i < src.length) {
                    when {
                        src.startsWith("//", i) -> { flushCode(); val end = src.indexOf('\n', i).let { if (it < 0) src.length else it }; pieces += Piece.Comment(advance(end - i)) }
                        src.startsWith("/*", i) -> { flushCode(); pieces += Piece.Comment(blockComment()) }
                        src.startsWith("\"\"\"", i) -> { flushCode(); string(raw = true) }
                        src[i] == '"' -> { flushCode(); string(raw = false) }
                        src[i] == '\'' -> { code.append(charLiteral()) }
                        stopAtBrace && src[i] == '{' -> { depth++; code.append(advance(1)) }
                        stopAtBrace && src[i] == '}' -> { if (depth == 0) { flushCode(); return pieces }; depth--; code.append(advance(1)) }
                        else -> code.append(advance(1))
                    }
                }
                flushCode()
                return pieces
            }

            private fun blockComment(): String {
                val start = i
                var nest = 0
                while (i < src.length) {
                    if (src.startsWith("/*", i)) { nest++; advance(2) }
                    else if (src.startsWith("*/", i)) { nest--; advance(2); if (nest == 0) break }
                    else advance(1)
                }
                return src.substring(start, i)
            }

            private fun charLiteral(): String {
                val start = i
                advance(1)
                if (i < src.length && src[i] == '\\') advance(2) else advance(1)
                while (i < src.length && src[i] != '\'' && src[i] != '\n') advance(1)
                if (i < src.length && src[i] == '\'') advance(1)
                return src.substring(start, i)
            }

            private fun string(raw: Boolean) {
                val startLine = line
                val start = i
                advance(if (raw) 3 else 1)
                val body = StringBuilder()
                while (i < src.length) {
                    if (raw && src.startsWith("\"\"\"", i)) {
                        // 원시 문자열은 """ 뒤에 따옴표가 더 붙으면 앞의 것은 몸이다.
                        var q = 3
                        while (i + q < src.length && src[i + q] == '"') q++
                        body.append("\"".repeat(q - 3)); advance(q); break
                    }
                    if (!raw && src[i] == '"') { advance(1); break }
                    if (!raw && src[i] == '\n') break
                    if (!raw && src[i] == '\\') { body.append(advance(2)); continue }
                    if (src.startsWith("\${", i)) {
                        // 템플릿 식은 몸에 넣지 않는다(자리표만) — 그 안의 문자열은 nested 로 따로 잰다.
                        advance(2)
                        val inner = Lexer(src).also { it.i = i; it.line = line }
                        inner.run(stopAtBrace = true)
                        nested += inner.pieces.filterIsInstance<Piece.Str>()
                        nested += inner.nested
                        line = inner.line; i = inner.i
                        if (i < src.length) advance(1)
                        body.append("\${…}")
                        continue
                    }
                    body.append(advance(1))
                }
                pieces += Piece.Str(body.toString(), raw, startLine, src.substring(start, i))
            }
        }

        private fun lex(src: String): List<Piece> = Lexer(src).run()

        /** 주석을 공백으로 바꾼 소스(줄 수 그대로). */
        private fun stripComments(src: String): String = lex(src).joinToString("") { piece ->
            when (piece) {
                is Piece.Comment -> piece.text.map { if (it == '\n') '\n' else ' ' }.joinToString("")
                is Piece.Code -> piece.text
                is Piece.Str -> piece.text
            }
        }

        private fun stringLiterals(code: String): List<Literal> {
            val lexer = Lexer(code)
            val top = lexer.run().filterIsInstance<Piece.Str>()
            return (top + lexer.nested).map { Literal(it.body, it.raw, it.line) }
        }

        /** 문자열 리터럴 속을 비운다(글자 안의 "isDigit()" 같은 낱말을 코드로 오인하지 않게). 줄 수 그대로. */
        private fun blankStrings(code: String): String = lex(code).joinToString("") { piece ->
            when (piece) {
                is Piece.Comment -> piece.text.map { if (it == '\n') '\n' else ' ' }.joinToString("")
                is Piece.Code -> piece.text
                is Piece.Str -> piece.text.map { if (it == '\n') '\n' else ' ' }.joinToString("")
            }
        }
    }
}
