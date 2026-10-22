// 원본: 없음 — 디자인 규칙 구조 시험.
//
// 디자인 규칙을 ui 모듈과 두 앱(androidApp·desktopApp)의 main 소스로 잰다(주석은 걷어 내고 본다 — 기억 source-contract-tests-need-comment-stripping):
//  D1 동적 색 금지: dynamicLightColorScheme·dynamicDarkColorScheme 를 부르는 자리 0(아잉체크 고정 색 — 주요색 iOS 파랑, G §8-12·§8-15).
//  D2 불투명도 이징 금지: fadeIn·fadeOut·Crossfade 는 AingMotion.fade 를 인자로 받는다. AnimatedVisibility 는 enter·exit 를 적는다
//     (기본값이 spring+fade 라 흐려짐이 이징을 탄다 — 기억 easing-must-not-drive-opacity).
//  D3 짧은 글자 그라데이션 금지: 글자 붓(TextStyle·SpanStyle 의 brush)은 AingTextPaint.kt 안에서만 건다(기억 short-text-kills-gradients).
//  D4 M3 기준 색 금지(G §8-15): MaterialTheme 은 colorScheme 을 적어 부르고, light·darkColorScheme 은 AingColorScheme.kt 에서만 만든다.
//     인자 없는 MaterialTheme { } 은 M3 기준 보라(#6750A4)로 단추·스위치·탭을 칠한다 — Android 셸이 그렇게 떠 있었다(xplat/int-c 에서 고침).
//  D5 앱 셸 색 리터럴 금지(G §8-15): androidApp·desktopApp 의 시험 아닌 소스는 색을 손으로 만들지 않는다 — Color(…)·Color.rgb/argb/parseColor 같은
//     만들기 호출·Color.<이름>(Transparent·Unspecified 빼고)·ARGB 정수(0xFF……) 를 금지한다. 색은 AingTheme.colors·MaterialTheme.colorScheme 로 받는다.
//     허용 목록은 Windows 트레이 아이콘(TrayIconRenderer — §8-15 가 지정한 브랜드 자리 PURPLE, Compose 밖 AWT 그림) 하나다.
//     D4 만으로는 셸이 테마 안에서 Color(0xFF6750A4) 를 박아 넣는 결함이 386건 초록으로 살아남았다(xplat/int-c 검증 V8).
// 각 규칙은 심은 위반으로 빨강이 되는 것을 같은 시험에서 확인한다.
package com.yehsung.aingcheck.ui.theme

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesignRulesStructureTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private val uiRoot = File(mpRoot, "ui/src")

    /** [srcRoot] 아래 시험 아닌 소스셋(main·debug·release·stub·commonMain·…)의 .kt 전부 — 경로는 [labelRoot] 기준. */
    private fun mainSources(srcRoot: File, labelRoot: File = srcRoot): List<Pair<String, String>> =
        srcRoot.listFiles().orEmpty()
            .filter { it.isDirectory && !it.name.endsWith("Test") && it.name != "test" }
            .flatMap { set -> set.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.toList() }
            .map { it.relativeTo(labelRoot).invariantSeparatorsPath to SwiftStyleComments.strip(it.readText()) }

    @Test
    fun uiMainFollowsDesignRules() {
        val files = mainSources(uiRoot)
        assertTrue(files.size >= 15, "ui main 소스를 ${files.size}개만 읽었다")
        val violations = files.flatMap { (path, code) -> DesignRules.check(path, code) }
        assertTrue(violations.isEmpty(), "디자인 규칙 위반:\n" + violations.joinToString("\n"))
    }

    /** 앱 셸도 같은 규칙: 셸이 테마를 감싸는 자리(MainActivity·데스크톱 창)가 M3 기준 보라로 뜨지 않고(D4) 색을 손으로 박지 않는다(D5). */
    @Test
    fun appMainFollowsDesignRules() {
        val android = mainSources(File(mpRoot, "androidApp/src"), mpRoot)
        val desktop = mainSources(File(mpRoot, "desktopApp/src"), mpRoot)
        assertTrue(android.size >= 20 && desktop.size >= 20, "앱 main 소스를 Android ${android.size}개 · 데스크톱 ${desktop.size}개만 읽었다")
        assertTrue(android.any { it.first.endsWith("/shell/MainActivity.kt") }, "Android 셸(MainActivity)을 못 읽었다")
        assertTrue(android.any { it.first.endsWith("/shell/AingShell.kt") }, "Android 탭 막대(AingShell)를 못 읽었다")
        assertTrue(desktop.any { it.first == DesignRules.TRAY_ICON_FILE }, "D5 허용 목록의 트레이 아이콘 파일(${DesignRules.TRAY_ICON_FILE})이 없다 — 옮겼으면 허용 목록도 옮긴다")
        val violations = (android + desktop).flatMap { (path, code) -> DesignRules.check(path, code) }
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
        assertEquals(listOf("D4"), rules("MaterialTheme {\n Surface { Shell() }\n}"))
        assertEquals(listOf("D4"), rules("MaterialTheme(typography = t, shapes = s) { Shell() }"))
        assertEquals(listOf("D4"), rules("val s = lightColorScheme()"))
        assertEquals(listOf("D4"), rules("val s = darkColorScheme(primary = p)"))
        // D5 — 앱 셸(androidApp·desktopApp)에서 손으로 만든 색. 검증 V8 의 결함(탭 점을 M3 기준 보라로)이 첫 줄이다.
        val shell = "androidApp/src/main/kotlin/x/Planted.kt"
        val desktop = "desktopApp/src/main/kotlin/x/Planted.kt"
        assertEquals(listOf("D5"), rules("Box(Modifier.size(10.dp).background(Color(0xFF6750A4), CircleShape))", shell))
        assertEquals(listOf("D5"), rules("val c = androidx.compose.ui.graphics.Color(red = 103, green = 80, blue = 164)", shell))
        assertEquals(listOf("D5"), rules("val c = Color(0.40f, 0.31f, 0.64f)", "androidApp/src/debug/kotlin/x/Planted.kt"))
        assertEquals(listOf("D5"), rules("paint.color = android.graphics.Color.parseColor(\"#6750A4\")", shell))
        assertEquals(listOf("D5"), rules("val c = Color.Magenta", shell))
        assertEquals(listOf("D5"), rules("g.color = java.awt.Color(0x6750A4)", desktop))
        assertEquals(listOf("D5"), rules("internal const val INK = 0xFF6750A4.toInt()", desktop))
        // 허용되는 꼴.
        assertEquals(emptyList(), rules("Box(Modifier.size(10.dp).background(LocalContentColor.current, CircleShape))", shell))
        assertEquals(emptyList(), rules("val c = MaterialTheme.colorScheme.secondary; val t = Color.Transparent; val u = Color.Unspecified", shell))
        assertEquals(emptyList(), rules("val elapsed = (now - last) and 0xFFFFFFFFL; const val WS_POPUP = 0x80000000.toInt()", desktop))
        assertEquals(emptyList(), rules("internal const val PURPLE = 0xFF6E4FD8.toInt()", DesignRules.TRAY_ICON_FILE))
        assertEquals(emptyList(), rules("Box(Modifier.background(Color(0xFF6750A4)))"), "D5 는 앱 셸만 잰다 — ui 의 색 정의(AingPalette)는 팔레트 계약 시험이 잰다")
        assertEquals(emptyList(), rules("val e = fadeIn(AingMotion.fade(150)) + slideInVertically(AingMotion.move())"))
        assertEquals(emptyList(), rules("AnimatedVisibility(v, enter = fadeIn(AingMotion.fade()), exit = fadeOut(AingMotion.fade())) { }"))
        assertEquals(emptyList(), rules("Crossfade(s, animationSpec = AingMotion.fade()) { }"))
        assertEquals(emptyList(), rules("Modifier.background(brush = Brush.verticalGradient(c))"))
        assertEquals(emptyList(), rules("fun withBrush(style: TextStyle, brush: Brush) = style.copy(brush = brush)", "commonMain/kotlin/com/yehsung/aingcheck/ui/theme/AingTextPaint.kt"))
        assertEquals(emptyList(), rules("MaterialTheme(colorScheme = AingColorScheme.of(dark), typography = t) { content() }"))
        assertEquals(emptyList(), rules("val c = MaterialTheme.colorScheme.primary"))
        assertEquals(emptyList(), rules("val s = lightColorScheme(primary = p)", "commonMain/kotlin/com/yehsung/aingcheck/ui/theme/AingColorScheme.kt"))
        // 주석 속 문형은 세지 않는다.
        assertEquals(emptyList(), DesignRules.check("commonMain/x.kt", SwiftStyleComments.strip("// fadeIn() 금지 — dynamicDarkColorScheme 도\nval a = 1")))
    }
}

internal object DesignRules {
    private const val TEXT_PAINT_FILE = "/com/yehsung/aingcheck/ui/theme/AingTextPaint.kt"
    private const val COLOR_SCHEME_FILE = "/com/yehsung/aingcheck/ui/theme/AingColorScheme.kt"

    /** D5 허용 목록(mpRoot 기준 경로): Windows 트레이 아이콘 — G §8-15 의 브랜드 자리(PURPLE). */
    const val TRAY_ICON_FILE = "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/platform/windows/tray/TrayIconRenderer.kt"
    private val APP_ROOTS = listOf("androidApp/src/", "desktopApp/src/")
    private val D5_PATTERNS = listOf(
        // 만들기: Color(…) — Compose·AWT·완전 이름(androidx.compose.ui.graphics.Color(…)) 모두. LocalContentColor( 같은 이름 꼬리는 \b 로 뺀다.
        Regex("""\bColor\s*\("""),
        // 만들기 함수: Color.rgb · Color.argb · Color.parseColor · Color.valueOf · Color.hsv · Color.hsl …
        Regex("""\bColor\.[a-z]\w*\s*\("""),
        // 이름 붙은 색: Color.Red · Color.Magenta · AWT Color.MAGENTA … (빈 색 Transparent·Unspecified 는 색을 칠하지 않는다)
        Regex("""\bColor\.(?!Transparent\b|Unspecified\b)[A-Z]\w*"""),
        // ARGB 정수(불투명 0xFF + RGB 여섯 자리). L 꼬리(Long 마스크 0xFFFFFFFFL)는 색이 아니다.
        Regex("""\b0[xX][fF]{2}[0-9a-fA-F]{6}(?![0-9a-fA-F_lL])"""),
    )

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
        Regex("""\bMaterialTheme\s*([({])""").findAll(code).forEach { m ->
            val bare = m.groupValues[1] == "{"
            if (bare || !Regex("""\bcolorScheme\s*=""").containsMatchIn(argsAt(code, m.range.last))) {
                out += "D4 $path:${line(m.range.first)} MaterialTheme 에 colorScheme 없음(M3 기준 보라 — AingTheme 으로 감싼다)"
            }
        }
        if (!path.endsWith(COLOR_SCHEME_FILE)) {
            Regex("""\b(?:light|dark)ColorScheme\s*\(""").findAll(code).forEach {
                out += "D4 $path:${line(it.range.first)} M3 색 체계는 AingColorScheme.kt 에서만 만든다"
            }
        }
        if (APP_ROOTS.any(path::startsWith) && path != TRAY_ICON_FILE) {
            // 한 줄에 여러 문형이 걸려도(Color(0xFF……)) 위반은 줄마다 하나로 센다.
            val lines = D5_PATTERNS.flatMap { p -> p.findAll(code).map { line(it.range.first) }.toList() }.toSortedSet()
            lines.forEach { out += "D5 $path:$it 앱 셸이 색을 손으로 만든다(AingTheme.colors·MaterialTheme.colorScheme 로 받는다 — G §8-15)" }
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
