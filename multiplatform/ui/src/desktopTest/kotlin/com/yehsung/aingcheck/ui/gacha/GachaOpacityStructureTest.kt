// 원본: 없음 — G §2-3 W4-c ④ "불투명도에 이징을 쓰지 않는다(구조 시험)" · ⑤ "화면 코드에 확률 숫자 상수 0". 기억 easing-must-not-drive-opacity ·
// source-contract-tests-need-comment-stripping(주석은 걷어 내고 본다).
//
// 이 갈래의 화면 소스(ui …/{shop,gacha,missions,weekly} · androidApp …/screens/shop)를 읽어 잰다:
//  O1 불투명도 자리 — `alpha = …` · `.alpha(…)` · `copy(alpha = …)` · `GPalette.hex(색, 불투명도)` 의 식과, 그 식이 부르는 **같은 파일의 지역 값**
//     (val 이름 → 오른쪽 식, 네 겹까지)에 이징 이름이 0 이어야 한다: smooth · ease… · spring · exp · pow · ring · ringCos · bezier ·
//     moveProgress · moveEasing · ambient(움직임 봉투 — 직선 판 ambientLinear 만 된다) · recede(움직임 물러남 — 직선 판 recedeFade 만 된다) ·
//     animate…AsState · FastOutSlowIn 같은 Compose 곡선.
//  O2 Compose 애니메이션 사양 — 맨 `tween(` 은 LinearEasing 을 적는다(진행도는 직선, 곡선은 위치에만 손으로 건다). 맨 `spring(` · `keyframes(` ·
//     `animate…AsState(` 는 쓰지 않는다.
//  P1 확률 숫자 상수 0 — 글자 상수에 "숫자%" 가 없다. 확률 · odds · percent 를 말하는 줄에 크기(dp · sp) 아닌 숫자 상수가 없다.
// 각 규칙은 심은 위반으로 빨강이 되는 것을 같은 시험에서 확인한다.
package com.yehsung.aingcheck.ui.gacha

import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GachaOpacityStructureTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))

    private fun sources(): List<Pair<String, String>> {
        val roots = listOf("shop", "gacha", "missions", "weekly").map { File(mpRoot, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/$it") } +
            File(mpRoot, "androidApp/src/main/kotlin/com/yehsung/aingcheck/android/screens/shop")
        return roots.filter { it.isDirectory }.flatMap { root ->
            root.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.map { it.relativeTo(mpRoot).invariantSeparatorsPath to SwiftStyleComments.strip(it.readText()) }.toList()
        }
    }

    @Test
    fun screenSourcesFollowOpacityAndOddsRules() {
        val files = sources()
        assertTrue(files.size >= 15, "이 갈래 화면 소스를 ${files.size}개만 읽었다")
        assertTrue(files.any { it.first.endsWith("/gacha/machine/GachaMachineStage.kt") }, "기계 무대 소스를 못 읽었다")
        val violations = files.flatMap { (path, code) -> W4cDesignRules.check(path, code) }
        assertTrue(violations.isEmpty(), "W4-c 디자인 규칙 위반:\n" + violations.joinToString("\n"))
        // 불투명도 자리를 실제로 세었다(빈 규칙이 아니다) — 기계 무대만 해도 수십 자리다.
        val sinks = files.sumOf { (_, code) -> W4cDesignRules.opacitySinks(code).size }
        assertTrue(sinks >= 60, "불투명도 자리를 $sinks 개만 찾았다 — 찾는 식이 낡았다")
    }

    @Test
    fun plantedViolationsAreCaught() {
        fun rules(code: String) = W4cDesignRules.check("ui/src/commonMain/kotlin/x/Planted.kt", code).map { it.substringBefore(' ') }
        // O1 — 식 안의 이징
        assertEquals(listOf("O1"), rules("drawRect(c, alpha = GMath.smooth(0.0, 1.0, t).toFloat())"))
        assertEquals(listOf("O1"), rules("Modifier.alpha(easeOutCubic(k))"))
        assertEquals(listOf("O1"), rules("val c = color.copy(alpha = 0.95f * kotlin.math.exp(-4.5 * t).toFloat())"))
        assertEquals(listOf("O1"), rules("val s = GPalette.hex(0x2A1460, (1 - p).pow(1.6).toFloat())"))
        assertEquals(listOf("O1"), rules("graphicsLayer { alpha = (1 - 0.76 * recede).toFloat() }"))
        assertEquals(listOf("O1"), rules("drawCircle(c.copy(alpha = GachaFade.f(0.35 * d.ambient(now))), 4f, p)"))
        // O1 — 지역 값을 지나 들어온 이징(이름만 보면 놓친다)
        assertEquals(listOf("O1"), rules("val k = GMath.smooth(0.1, 0.4, arrive)\nval a = k * 0.5\nBox(Modifier.alpha(GachaFade.f(a)))"))
        // O2 — 애니메이션 사양
        assertEquals(listOf("O2"), rules("clock.animateTo(1f, tween(900))"))
        assertEquals(listOf("O2"), rules("val a by animateFloatAsState(if (v) 1f else 0f)"))
        assertEquals(listOf("O2"), rules("anim.animateTo(1f, spring(dampingRatio = 0.6f))"))
        // P1 — 확률 숫자
        assertEquals(listOf("P1"), rules("Text(\"황금 아잉이 3%\")"))
        assertEquals(listOf("P1"), rules("val goldOddsPercent = 3.0"))
        assertEquals(listOf("P1"), rules("if (row.percent > 5) emphasize()"))
        // 허용되는 꼴
        assertEquals(emptyList(), rules("drawRect(c, alpha = GachaFade.f(GachaFade.rise(0.0, 0.3, t)))"))
        assertEquals(emptyList(), rules("Modifier.alpha(GachaFade.f((1 - recedeFade) * (if (d.dragging) 0.5 else 1.0)))"))
        assertEquals(emptyList(), rules("val flicker = 0.78 + 0.22 * sin(2 * PI * 6 * td)\ndrawRect(b, alpha = GachaFade.f(0.55 * flicker))"))
        assertEquals(emptyList(), rules("clock.animateTo(1f, tween(MeAchievementLayout.BURST_MS, easing = LinearEasing))"))
        assertEquals(emptyList(), rules("val scale = 1 + 0.15 * GMath.easeOutCubic(t)\nwithTransform({ scale(scale) }) { }"))
        assertEquals(emptyList(), rules("AingIcon(AppIcon.Percent, contentDescription = null, size = 18.dp, tint = c.accent)"))
        assertEquals(emptyList(), rules("Text(row.percentText, modifier = Modifier.widthIn(min = 48.dp))"))
        assertEquals(emptyList(), rules("val k = GMath.spring(rt - delay, 0.42, 1.6)"))
        assertEquals(emptyList(), rules("fun spring(t: Double, zeta: Double, freq: Double): Double = t"))
        assertEquals(emptyList(), rules("Text(MeText.gachaOddsColumnName, modifier = Modifier.weight(1f))"))
    }
}

/** W4-c 화면 규칙(O1 · O2 · P1). 입력은 주석을 걷어 낸 소스다. */
internal object W4cDesignRules {
    private val easingTokens = listOf(
        Regex("""\bsmooth\s*\("""), Regex("""\bease\w*\s*\(""", RegexOption.IGNORE_CASE), Regex("""\bspring\s*\("""), Regex("""\bexp\s*\("""),
        Regex("""\bpow\s*\("""), Regex("""\bring(Cos)?\s*\("""), Regex("""\bbezier\s*\("""), Regex("""\bmoveProgress\b"""), Regex("""\bmoveEasing\b"""),
        Regex("""\bambient\s*\("""), Regex("""\brecede\b"""), Regex("""\banimate\w*AsState\b"""), Regex("""FastOutSlowIn|LinearOutSlowIn|FastOutLinearIn|CubicBezierEasing"""),
        Regex("""\bEasing\b"""),
    )

    private val sinkStarts = listOf(
        Regex("""\balpha\s*=\s*"""),            // alpha = … (이름 붙은 인자 · graphicsLayer 안 대입)
        Regex("""\.alpha\s*\("""),              // Modifier.alpha(…)
    )
    private val hexCall = Regex("""\bhex\s*\(""")

    fun check(path: String, code: String): List<String> {
        val out = mutableListOf<String>()
        fun line(offset: Int) = code.substring(0, offset).count { it == '\n' } + 1
        val scopes = Scopes(code)
        for ((offset, expr) in opacitySinks(code)) {
            val bad = taint(expr, offset, scopes, depth = 0, seen = HashSet())
            if (bad != null) out += "O1 $path:${line(offset)} 불투명도 식에 이징($bad): ${expr.trim().take(90)}"
        }
        Regex("""(?<![\w.])tween\s*\(""").findAll(code).forEach { m ->
            if (!argsAt(code, m.range.last).contains("LinearEasing")) out += "O2 $path:${line(m.range.first)} tween 에 LinearEasing 없음(진행도는 직선)"
        }
        Regex("""(?<!fun )(?<![\w.])(spring|keyframes)\s*\(|\banimate\w*AsState\s*\(""").findAll(code).forEach { m ->
            out += "O2 $path:${line(m.range.first)} 곡선 애니메이션 사양(${m.value.trim()})"
        }
        // P1 ① 글자 상수의 "숫자%"
        Regex(""""(?:[^"\\\n]|\\.)*"""").findAll(code).forEach { m ->
            if (Regex("""\d\s*%""").containsMatchIn(m.value)) out += "P1 $path:${line(m.range.first)} 글자에 확률 숫자: ${m.value}"
        }
        // P1 ② 확률을 말하는 줄의 숫자 상수(크기 dp · sp 는 뺀다)
        code.lines().forEachIndexed { i, text ->
            if (!Regex("""odds|percent|확률""", RegexOption.IGNORE_CASE).containsMatchIn(text)) return@forEachIndexed
            val stripped = text.replace(Regex(""""(?:[^"\\]|\\.)*""""), "\"\"").replace(Regex("""\d+(\.\d+)?\s*\.\s*(dp|sp)\b"""), "").replace(Regex("""\bweight\(\s*\d+(\.\d+)?f?\s*\)"""), "")
            if (Regex("""(?<![\w.])\d+(\.\d+)?[fFL]?(?![\w])""").containsMatchIn(stripped)) out += "P1 $path:${i + 1} 확률 줄에 숫자 상수: ${text.trim().take(90)}"
        }
        return out
    }

    /** 불투명도 자리(위치, 식). */
    fun opacitySinks(code: String): List<Pair<Int, String>> {
        val out = mutableListOf<Pair<Int, String>>()
        for (start in sinkStarts) {
            start.findAll(code).forEach { m ->
                val from = m.range.last + 1
                val expr = if (m.value.trimEnd().endsWith("(")) argsAt(code, m.range.last) else argument(code, from)
                out += m.range.first to expr
            }
        }
        hexCall.findAll(code).forEach { m ->
            val args = splitTopLevel(argsAt(code, m.range.last))
            if (args.size >= 2) out += m.range.first to args[1]
        }
        return out
    }

    /**
     * 이름 → 선언(위치, 오른쪽 식) 표와 함수 몸통 구간. 이름은 **보이는 자리**에서만 푼다: 같은 함수 몸통 안 · 그 자리보다 앞에 선언된 값,
     * 그리고 어느 함수에도 들지 않은 값(파일 · 클래스 몸통). 다른 함수의 같은 이름(a · p · e …)으로 물들지 않게.
     */
    private class Scopes(code: String) {
        val decls = HashMap<String, MutableList<Pair<Int, String>>>()
        val functions = mutableListOf<IntRange>()

        init {
            Regex("""\bva[lr]\s+([A-Za-z_]\w*)(\s*:\s*[^=\n]+)?\s*=\s*""").findAll(code).forEach { m ->
                decls.getOrPut(m.groupValues[1]) { mutableListOf() } += m.range.first to argument(code, m.range.last + 1)
            }
            // 구조 분해(val (a, b, c) = …) — 오른쪽 식을 이름마다 건다.
            Regex("""\bval\s*\(([^)]*)\)\s*=\s*""").findAll(code).forEach { m ->
                val rhs = argument(code, m.range.last + 1)
                m.groupValues[1].split(',').map { it.trim() }.filter { it.isNotEmpty() }.forEach { decls.getOrPut(it) { mutableListOf() } += m.range.first to rhs }
            }
            Regex("""\bfun\b""").findAll(code).forEach { m ->
                // 서명의 괄호를 지나 몸통({ … } 또는 = …)을 찾는다.
                var i = code.indexOf('(', m.range.last)
                if (i < 0) return@forEach
                var depth = 0
                while (i < code.length) {
                    if (code[i] == '(') depth++ else if (code[i] == ')') { depth--; if (depth == 0) break }
                    i++
                }
                var j = i + 1
                while (j < code.length && code[j] != '{' && code[j] != '=' && code[j] != '\n') j++
                if (j < code.length && code[j] == '{') {
                    var d = 0
                    var k = j
                    while (k < code.length) {
                        if (code[k] == '{') d++ else if (code[k] == '}') { d--; if (d == 0) break }
                        k++
                    }
                    functions += m.range.first..k
                } else if (j < code.length && code[j] == '=') {
                    functions += m.range.first..(j + 1 + argument(code, j + 1).length)
                }
            }
        }

        /** [at] 자리에서 보이는 [name] 의 선언들. */
        fun visible(name: String, at: Int): List<Pair<Int, String>> {
            val enclosing = functions.filter { at in it }.minByOrNull { it.last - it.first }
            return decls[name].orEmpty().filter { (pos, _) ->
                if (enclosing != null && pos in enclosing) pos < at else functions.none { pos in it }
            }
        }
    }

    /** 식이 이징에 물들었으면 그 낱말을, 아니면 null. 식이 부르는 (그 자리에서 보이는) 지역 값을 따라간다(네 겹까지). */
    private fun taint(expr: String, at: Int, scopes: Scopes, depth: Int, seen: MutableSet<String>): String? {
        easingTokens.firstOrNull { it.containsMatchIn(expr) }?.let { return it.find(expr)?.value?.trim() }
        if (depth >= 4) return null
        for (id in Regex("""(?<![\w.])[A-Za-z_]\w*""").findAll(expr).map { it.value }.toSet()) {
            if (!seen.add(id)) continue
            for ((pos, rhs) in scopes.visible(id, at)) taint(rhs, pos, scopes, depth + 1, seen)?.let { return "$id ← $it" }
        }
        return null
    }

    /** [from] 부터 한 인자 · 한 문장(깊이 0 의 `,` · `)` · `}` · 줄바꿈까지). */
    private fun argument(code: String, from: Int): String {
        var depth = 0
        var i = from
        while (i < code.length) {
            when (code[i]) {
                '(', '[', '{' -> depth++
                ')', ']', '}' -> { if (depth == 0) return code.substring(from, i); depth-- }
                ',' -> if (depth == 0) return code.substring(from, i)
                '\n' -> if (depth == 0) return code.substring(from, i)
            }
            i++
        }
        return code.substring(from)
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

    private fun splitTopLevel(args: String): List<String> {
        val out = mutableListOf<String>()
        var depth = 0
        var start = 0
        args.forEachIndexed { i, ch ->
            when (ch) {
                '(', '[', '{' -> depth++
                ')', ']', '}' -> depth--
                ',' -> if (depth == 0) { out += args.substring(start, i); start = i + 1 }
            }
        }
        out += args.substring(start)
        return out.map { it.trim() }.filter { it.isNotEmpty() }
    }
}
