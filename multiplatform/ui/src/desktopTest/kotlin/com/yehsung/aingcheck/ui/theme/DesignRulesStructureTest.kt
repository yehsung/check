// 원본: 없음 — 디자인 규칙 구조 시험.
//
// 디자인 규칙을 ui 모듈 main 소스로 잰다(주석은 걷어 내고 본다 — 기억 source-contract-tests-need-comment-stripping):
//  D1 동적 색 금지: dynamicLightColorScheme·dynamicDarkColorScheme 를 부르는 자리 0(브랜드 보라 유지, G §8-12).
//  D2 불투명도 이징 금지: fadeIn·fadeOut·Crossfade 는 AingMotion.fade 를 인자로 받는다. AnimatedVisibility 는 enter·exit 를 적는다
//     (기본값이 spring+fade 라 흐려짐이 이징을 탄다 — 기억 easing-must-not-drive-opacity).
//  D3 짧은 글자 그라데이션 금지: 글자 붓(TextStyle·SpanStyle 의 brush)은 AingTextPaint.kt 안에서만 건다(기억 short-text-kills-gradients).
// 각 규칙은 심은 위반으로 빨강이 되는 것을 같은 시험에서 확인한다.
package com.yehsung.aingcheck.ui.theme

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesignRulesStructureTest {
    private val uiRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")), "ui/src")

    private fun mainSources(): List<Pair<String, String>> =
        uiRoot.listFiles().orEmpty()
            .filter { it.isDirectory && !it.name.endsWith("Test") && it.name != "test" }
            .flatMap { set -> set.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.toList() }
            .map { it.relativeTo(uiRoot).invariantSeparatorsPath to SwiftStyleComments.strip(it.readText()) }

    @Test
    fun uiMainFollowsDesignRules() {
        val files = mainSources()
        assertTrue(files.size >= 15, "ui main 소스를 ${files.size}개만 읽었다")
        val violations = files.flatMap { (path, code) -> DesignRules.check(path, code) }
        assertTrue(violations.isEmpty(), "디자인 규칙 위반:\n" + violations.joinToString("\n"))
    }

    @Test
    fun plantedViolationsAreCaught() {
        fun rules(code: String, path: String = "commonMain/kotlin/x/Planted.kt") = DesignRules.check(path, code).map { it.substringBefore(' ') }
        assertEquals(listOf("D1"), rules("val s = dynamicDarkColorScheme(context)"))
        assertEquals(listOf("D2"), rules("AnimatedVisibility(visible) { Text(\"a\") }"))
        assertEquals(listOf("D2"), rules("val e = fadeIn()"))
        assertEquals(listOf("D2"), rules("val e = fadeOut(tween(200, easing = FastOutSlowInEasing))"))
        assertEquals(listOf("D2"), rules("Crossfade(targetState = s) { }"))
        assertEquals(listOf("D3"), rules("Text(t, style = TextStyle(brush = Brush.horizontalGradient(c)))"))
        assertEquals(listOf("D3"), rules("val s = style.copy(brush = b)"))
        assertEquals(listOf("D3"), rules("withStyle(SpanStyle(brush = b)) { append(t) }"))
        // 허용되는 꼴.
        assertEquals(emptyList(), rules("val e = fadeIn(AingMotion.fade(150)) + slideInVertically(AingMotion.move())"))
        assertEquals(emptyList(), rules("AnimatedVisibility(v, enter = fadeIn(AingMotion.fade()), exit = fadeOut(AingMotion.fade())) { }"))
        assertEquals(emptyList(), rules("Crossfade(s, animationSpec = AingMotion.fade()) { }"))
        assertEquals(emptyList(), rules("Modifier.background(brush = Brush.verticalGradient(c))"))
        assertEquals(emptyList(), rules("fun withBrush(style: TextStyle, brush: Brush) = style.copy(brush = brush)", "commonMain/kotlin/com/yehsung/aingcheck/ui/theme/AingTextPaint.kt"))
        // 주석 속 문형은 세지 않는다.
        assertEquals(emptyList(), DesignRules.check("commonMain/x.kt", SwiftStyleComments.strip("// fadeIn() 금지 — dynamicDarkColorScheme 도\nval a = 1")))
    }
}

internal object DesignRules {
    private const val TEXT_PAINT_FILE = "/com/yehsung/aingcheck/ui/theme/AingTextPaint.kt"

    fun check(path: String, code: String): List<String> {
        val out = mutableListOf<String>()
        fun line(offset: Int) = code.substring(0, offset).count { it == '\n' } + 1
        Regex("""\bdynamic(?:Light|Dark)?ColorScheme\s*\(""").findAll(code).forEach { out += "D1 $path:${line(it.range.first)} 동적 색" }
        for (call in listOf("fadeIn", "fadeOut", "Crossfade")) {
            Regex("""\b$call\s*\(""").findAll(code).forEach { m ->
                val args = argsAt(code, m.range.last)
                if (!args.contains("AingMotion.fade")) out += "D2 $path:${line(m.range.first)} $call 에 AingMotion.fade 없음"
            }
        }
        Regex("""\bAnimatedVisibility\s*\(""").findAll(code).forEach { m ->
            val args = argsAt(code, m.range.last)
            if (!Regex("""\benter\s*=""").containsMatchIn(args) || !Regex("""\bexit\s*=""").containsMatchIn(args)) {
                out += "D2 $path:${line(m.range.first)} AnimatedVisibility 기본 enter·exit(이징 낀 흐려짐)"
            }
        }
        if (!path.endsWith(TEXT_PAINT_FILE)) {
            for (ctor in listOf("TextStyle", "SpanStyle", "copy")) {
                Regex("""(?:\b|\.)$ctor\s*\(""").findAll(code).forEach { m ->
                    val args = argsAt(code, m.range.last)
                    if (Regex("""\bbrush\s*=""").containsMatchIn(args)) out += "D3 $path:${line(m.range.first)} 글자 붓은 AingTextPaint 로만"
                }
            }
        }
        return out
    }

    /** 여는 괄호([open]) 뒤 짝 괄호까지의 인자 글자. */
    private fun argsAt(code: String, open: Int): String {
        var depth = 0
        for (i in open until code.length) {
            when (code[i]) {
                '(' -> depth++
                ')' -> { depth--; if (depth == 0) return code.substring(open + 1, i) }
            }
        }
        return code.substring(open + 1)
    }
}

/** Kotlin 주석 걷어 내기(문자열은 남긴다). */
internal object SwiftStyleComments {
    fun strip(src: String): String = SwiftPalette.stripComments(src)
}
