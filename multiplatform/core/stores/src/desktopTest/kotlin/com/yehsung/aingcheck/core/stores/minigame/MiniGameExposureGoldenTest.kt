// 원본: 없음 — G §2-3 W2-e ④ "미니게임 표시 깃발: 해당 골든이 초록인 빌드에서만 켠다(B§10-5)" 의 잠금 시험.
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.structure.StructureRules
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 미니게임 표시 깃발([MiniGameExposure])이 **골든 대조와 짝**인지 잰다. 깃발이 켜진 게임마다 증거 골든 전부가
 *  ① `_manifest.json` 에 있고(Swift 가 낸 계약 골든) ② 게이트가 돌리는 Kotlin 시험 소스(commonTest·desktopTest·androidHostTest·test)의
 *     주석 밖 코드에서 **켜진 시험**이 `Golden.load("<이름>")` 로 대조한다 — `@Test` 함수(또는 켜진 `@Test` 가 있는 클래스의 칸) 안이고,
 *     그 함수·둘러싼 클래스 어디에도 `@Ignore`·`@Disabled` 가 없을 때만 센다(검증 지적 V08: 증거 시험 클래스를 통째로 `@Ignore` 해도
 *     깃발이 켜진 채 초록이었다 — gate-fast 는 카나리아 말고는 건너뜀을 세지 않는다).
 *  ③ 증거 목록 자체가 잠겨 있다 — 게임마다 **그 게임 골든 폴더 전부**(1:1 대결 `duel*` 은 판돈 깃발 몫이라 뺀다)이고, 글자 표로도 잠근다
 *     (검증 지적 V07: 테트리스 증거를 `tetris/fixtures` 하나로 줄여도 초록이었다).
 * ①②③ 이 서면 그 대조 시험(W1-a)이 이 시험과 같은 게이트에서 돌므로 "깃발이 켜진 빌드 = 그 골든이 초록인 빌드" 다. 하나라도 빠지면 빨강이다.
 */
class MiniGameExposureGoldenTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다" })
    private val gateSourceSets = setOf("commonTest", "desktopTest", "androidHostTest", "test")

    /** 게임 → 골든 폴더(`contract/golden/<폴더>/…`). 서버 어휘(rawValue)와 폴더 이름이 다른 게임이 있다(timing_bar ↔ timing-bar). */
    private val goldenArea = mapOf(
        MiniGameKind.timingBar to "timing-bar",
        MiniGameKind.flappy to "flappy",
        MiniGameKind.tetris to "tetris",
        MiniGameKind.crossy to "crossy",
    )

    private fun manifestNames(): Set<String> =
        Json.parseToJsonElement(RepoFiles.readText("contract/golden/_manifest.json")).jsonObject["goldens"]!!.jsonArray
            .map { it.jsonObject["golden"]!!.jsonPrimitive.content }.toSet()

    /** 게이트 소스셋의 시험 파일에서 **켜진 시험이 대조하는** 골든 이름. */
    private fun consumedNames(): Set<String> {
        val out = mutableSetOf<String>()
        for (f in StructureRules.collect(mpRoot)) {
            if (!f.relPath.endsWith(".kt")) continue
            val parts = f.relPath.split('/')
            val src = parts.indexOf("src")
            if (src < 0 || src + 1 >= parts.size || parts[src + 1] !in gateSourceSets) continue
            for (load in GoldenLoadScan.loads(f.code)) if (load.counted) out += load.name
        }
        return out
    }

    /** 문제 목록(빈 목록이면 깃발과 골든이 짝이다). 보이는 게임만 본다 — 숨긴 게임의 증거는 아직 요구하지 않는다. */
    private fun problems(evidence: Map<MiniGameKind, List<String>>, listed: Set<String>, consumed: Set<String>): List<String> =
        MiniGameExposure.visibleKinds(evidence).flatMap { kind ->
            evidence[kind].orEmpty().flatMap { name ->
                listOfNotNull(
                    if (name !in listed) "${kind.rawValue}: 증거 골든 '$name' 이 _manifest.json 에 없다" else null,
                    if (name !in consumed) "${kind.rawValue}: 증거 골든 '$name' 을 대조하는 켜진 Kotlin 시험이 없다(@Test 밖 · @Ignore·@Disabled)" else null,
                )
            }
        }

    @Test
    fun everyVisibleGameHasGreenGoldenEvidence() {
        val listed = manifestNames()
        val consumed = consumedNames()
        val problems = problems(MiniGameExposure.evidenceGoldens, listed, consumed)
        assertEquals(emptyList(), problems, problems.joinToString("\n"))
        assertEquals(listOf(MiniGameKind.timingBar, MiniGameKind.flappy, MiniGameKind.tetris), MiniGameExposure.visible,
            "이 빌드에 보이는 게임 — 폰 노출 규칙 ∩ 증거(길건너는 폰 1.0.15 때 W4-b 가 연다)")
    }

    /**
     * ★ 증거 목록이 줄지 않는다. 게임마다 증거 = 그 게임 골든 폴더의 골든 **전부**(`_manifest.json` 기준 — Swift 가 낸 것) 중 1:1 대결
     * (`duel*` — 판돈 대결은 §8-17 #1 `duelsEnabled` 가 따로 막는다)을 뺀 것. 폴더에 골든이 늘면 증거도 늘어야 하고, 증거에서 빼면 빨강이다.
     * 글자 표로도 잠근다(폴더 규칙이 같이 바뀌는 실수까지 — 바꾸려면 설계 결정이 필요하다).
     */
    @Test
    fun theEvidenceListIsTheWholeGameGoldenFolder() {
        assertEquals(MiniGameKind.entries.toSet(), MiniGameExposure.evidenceGoldens.keys, "증거 표에 빠진 게임")
        assertEquals(MiniGameKind.entries.toSet(), goldenArea.keys, "골든 폴더 표에 빠진 게임")
        val listed = manifestNames()
        for (kind in MiniGameKind.entries) {
            val area = goldenArea.getValue(kind)
            val folder = listed.filter { it.startsWith("$area/") && !it.removePrefix("$area/").startsWith("duel") }.toSortedSet()
            assertTrue(folder.isNotEmpty(), "${kind.rawValue}: 골든 폴더 '$area' 가 _manifest 에 없다")
            assertEquals(folder, MiniGameExposure.evidenceGoldens.getValue(kind).toSortedSet(),
                "${kind.rawValue}: 증거 목록이 골든 폴더 전부가 아니다")
        }
        assertEquals(
            mapOf(
                MiniGameKind.timingBar to listOf("timing-bar/rules", "timing-bar/scripted"),
                MiniGameKind.flappy to listOf("flappy/rules", "flappy/scripted"),
                MiniGameKind.tetris to listOf("tetris/rules", "tetris/scripted", "tetris/bags", "tetris/garbage-holes", "tetris/fixtures"),
                MiniGameKind.crossy to listOf("crossy/rules", "crossy/lanes", "crossy/scripted"),
            ),
            MiniGameExposure.evidenceGoldens,
            "증거 목록 글자 표",
        )
    }

    /** 대조(기준선이 다른 입력): 증거가 빠진 게임은 깃발이 내려가고, 목록에 없는·대조 안 된 골든을 증거로 적으면 빨강이다. */
    @Test
    fun missingEvidenceTurnsTheFlagOffOrFailsTheLock() {
        val listed = manifestNames()
        val consumed = consumedNames()
        val withoutTetris = MiniGameExposure.evidenceGoldens - MiniGameKind.tetris
        assertEquals(listOf(MiniGameKind.timingBar, MiniGameKind.flappy), MiniGameExposure.visibleKinds(withoutTetris),
            "증거가 없는 게임은 보이지 않는다")
        val ghost = MiniGameExposure.evidenceGoldens + (MiniGameKind.flappy to listOf("flappy/rules", "flappy/ghost"))
        val found = problems(ghost, listed, consumed)
        assertTrue(found.any { "flappy/ghost" in it && "_manifest" in it }, "목록에 없는 증거를 못 잡았다: $found")
        assertTrue(found.any { "flappy/ghost" in it && "Kotlin 시험" in it }, "대조 안 된 증거를 못 잡았다: $found")
        assertTrue(consumed.containsAll(listOf("tetris/scripted", "flappy/scripted", "timing-bar/scripted")),
            "소비 스캔이 비었다(정규식·소스셋 범위 확인)")
        // 꺼진 시험은 증거가 아니다: 같은 소비 집합에서 테트리스 증거 하나를 빼면(= 그 시험이 @Ignore 로 꺼졌을 때와 같다) 빨강이다.
        val off = problems(MiniGameExposure.evidenceGoldens, listed, consumed - "tetris/bags")
        assertTrue(off.any { "tetris/bags" in it && "켜진 Kotlin 시험" in it }, "꺼진 증거 시험을 못 잡았다: $off")
    }

    /**
     * 소비 스캐너 자기 시험(기준선이 다른 입력 — 같은 소스에서 주석 하나만 다르다): `@Test` 함수 안의 `Golden.load` 만 세고, 함수·클래스의
     * `@Ignore`(kotlin.test·JUnit4) · `@Disabled`(JUnit5) 는 빼고, 문자열 안 중괄호에 속지 않는다.
     */
    @Test
    fun theConsumerScanCountsOnlyLiveTests() {
        // 견본 소스에는 `Golden.load(` 를 글자 그대로 적지 않는다 — testkit GoldenCoverageTest 가 게이트 시험 소스의 그 글자를 소비로 세어
        // '목록 밖' 이름(x/…)으로 빨개진다. 견본은 `LOAD(` 로 적고 스캔 직전에 바꾼다.
        fun counted(src: String): List<String> =
            GoldenLoadScan.loads(StructureRules.stripComments(src.replace("LOAD(", "Golden" + ".load("))).filter { it.counted }.map { it.name }
        val live = """
            class A {
                private val brace = "{ not a block"
                @Test
                fun a() {
                    val g = LOAD("x/live")
                }
            }
        """.trimIndent()
        assertEquals(listOf("x/live"), counted(live), "기준선: 켜진 @Test 안의 load 는 센다")
        assertEquals(emptyList(), counted(live.replace("@Test", "@Ignore\n    @Test")), "함수 @Ignore")
        assertEquals(emptyList(), counted(live.replace("@Test", "@kotlin.test.Ignore @Test")), "함수 @kotlin.test.Ignore")
        assertEquals(emptyList(), counted("@kotlin.test.Ignore\n$live"), "클래스 @kotlin.test.Ignore(V08)")
        assertEquals(emptyList(), counted("@org.junit.Ignore(\"이유\")\n$live"), "클래스 @org.junit.Ignore")
        assertEquals(emptyList(), counted(live.replace("@Test", "@Disabled @Test")), "함수 @Disabled")
        assertEquals(emptyList(), counted(live.replace("@Test", "")), "@Test 가 아닌 함수의 load 는 대조가 아니다")
        assertEquals(emptyList(), counted("// @Test\n" + live.replace("@Test", "")), "주석 속 @Test 는 시험이 아니다")
        val expressionBody = """
            class B {
                @Test
                fun b() = runTest {
                    fun helper() = LOAD("x/expr")
                    helper()
                }
            }
        """.trimIndent()
        assertEquals(listOf("x/expr"), counted(expressionBody), "식 몸통(= runTest { … }) · 안쪽 도우미 함수")
        val property = """
            class C {
                private val golden = LOAD("x/prop")
                @Test
                fun c() { golden.cases }
            }
        """.trimIndent()
        assertEquals(listOf("x/prop"), counted(property), "켜진 @Test 가 있는 클래스의 칸")
        assertEquals(emptyList(), counted(property.replace("@Test", "@Ignore @Test")), "켜진 @Test 가 하나도 없는 클래스의 칸")
        val nested = """
            class D {
                @Test fun d() { LOAD("x/outer") }
                @Ignore
                class Inner {
                    @Test fun e() { LOAD("x/inner") }
                }
            }
        """.trimIndent()
        assertEquals(listOf("x/outer"), counted(nested), "꺼진 안쪽 클래스만 빠진다")
    }
}

/**
 * 시험 소스(주석을 걷은 코드)에서 `Golden.load("<이름>")` 가 놓인 자리를 찾고, 그 자리가 **켜진 시험**인지 가른다.
 * 문자열·글자 리터럴 속 괄호는 가려서 센다. 선언(`class`·`object`·`interface`·`fun`)의 몸통은 첫 `{`(매개변수 괄호 밖)에서 짝 `}` 까지다 —
 * 식 몸통 `= runTest { … }` 은 그 람다가 몸통이다. 주석(@…)은 선언 키워드 앞, 앞 문장 경계(`{` `}` `;`) 뒤의 글자에서 읽는다.
 */
internal object GoldenLoadScan {
    data class Load(val name: String, val counted: Boolean)

    private val loadCall = Regex("""\bGolden\s*\.\s*load\s*\(\s*"([^"\\]+)"\s*\)""")
    private val declaration = Regex("""\b(class|object|interface|fun)\b""")
    private val ignored = Regex("""@(?:kotlin\.test\.|org\.junit\.(?:jupiter\.api\.)?)?(?:Ignore|Disabled)\b""")
    private val testMark = Regex("""@(?:kotlin\.test\.|org\.junit\.(?:jupiter\.api\.)?)?Test\b""")

    private class Decl(val kind: String, val open: Int, val close: Int, val annotations: String)

    fun loads(code: String): List<Load> {
        val masked = maskLiterals(code)
        val decls = declarations(masked)
        // 리터럴 안의 글자(예: 시험이 문자열로 든 견본 소스)는 호출이 아니다 — 가린 자리에서 'G' 가 지워졌으면 뺀다.
        return loadCall.findAll(code).filter { masked[it.range.first] == 'G' }.map { m ->
            val at = m.range.first
            val around = decls.filter { at in it.open..it.close }.sortedBy { it.open }
            Load(m.groupValues[1], isLive(at, around, decls))
        }.toList()
    }

    private fun isLive(at: Int, around: List<Decl>, all: List<Decl>): Boolean {
        if (around.any { ignored.containsMatchIn(it.annotations) }) return false
        val outerFun = around.firstOrNull { it.kind == "fun" }
        if (outerFun != null) return testMark.containsMatchIn(outerFun.annotations)
        // 함수 밖(클래스 칸 초기화): 그 클래스 바로 안에 켜진 @Test 함수가 하나라도 있어야 대조다.
        val owner = around.lastOrNull() ?: return false
        return all.any { d ->
            d.kind == "fun" && d.open > owner.open && d.close < owner.close &&
                all.none { o -> o !== owner && o.open < d.open && o.close > d.close && o.open > owner.open } &&
                testMark.containsMatchIn(d.annotations) && !ignored.containsMatchIn(d.annotations)
        }
    }

    private fun declarations(s: String): List<Decl> {
        val out = mutableListOf<Decl>()
        for (m in declaration.findAll(s)) {
            val start = m.range.first
            if (start > 0 && (s[start - 1].isLetterOrDigit() || s[start - 1] in "_.@:")) continue
            val open = bodyStart(s, m.range.last + 1) ?: continue
            val close = matching(s, open) ?: continue
            val boundary = maxOf(s.lastIndexOf('{', start - 1), s.lastIndexOf('}', start - 1), s.lastIndexOf(';', start - 1))
            out += Decl(m.groupValues[1], open, close, s.substring(boundary + 1, start))
        }
        return out
    }

    /** 선언 키워드 뒤 첫 `{`(괄호 밖). 그 전에 다른 선언이 시작되면 몸통이 없다. */
    private fun bodyStart(s: String, from: Int): Int? {
        var depth = 0
        var i = from
        while (i < s.length) {
            when (s[i]) {
                '(' -> depth++
                ')' -> depth--
                '{' -> if (depth == 0) return i
                '}' -> if (depth == 0) return null
                else -> if (depth == 0 && i > from && declaration.matchesAt(s, i) && !s[i - 1].isLetterOrDigit()) return null
            }
            i++
        }
        return null
    }

    private fun matching(s: String, open: Int): Int? {
        var depth = 0
        for (i in open until s.length) {
            when (s[i]) {
                '{' -> depth++
                '}' -> if (--depth == 0) return i
            }
        }
        return null
    }

    /** 문자열("…"·"""…""")·글자('…') 리터럴 안을 공백으로 가린다(길이·줄 위치는 그대로). */
    private fun maskLiterals(src: String): String {
        val out = StringBuilder(src)
        var i = 0
        val n = src.length
        while (i < n) {
            val c = src[i]
            when {
                c == '"' && src.startsWith("\"\"\"", i) -> {
                    val end = src.indexOf("\"\"\"", i + 3).let { if (it < 0) n else it }
                    for (k in i + 3 until end) if (src[k] != '\n') out.setCharAt(k, ' ')
                    i = minOf(n, end + 3)
                }
                c == '"' -> {
                    var k = i + 1
                    while (k < n && src[k] != '"' && src[k] != '\n') {
                        if (src[k] == '\\') { out.setCharAt(k, ' '); k++ }
                        if (k < n) out.setCharAt(k, ' ')
                        k++
                    }
                    i = k + 1
                }
                c == '\'' -> {
                    var close = src.indexOf('\'', i + 1)
                    // '\'' — 첫 닫는 따옴표가 가려진 따옴표다.
                    if (close == i + 2 && src[i + 1] == '\\') close = src.indexOf('\'', close + 1)
                    if (close in (i + 1)..(i + 8) && !src.substring(i + 1, close).contains('\n')) {
                        for (k in i + 1 until close) out.setCharAt(k, ' ')
                        i = close + 1
                    } else {
                        i++
                    }
                }
                else -> i++
            }
        }
        return out.toString()
    }
}
