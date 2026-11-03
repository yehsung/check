// 원본: Tests/checkTests/ChatMarkdownTests.swift @ 12624739(맥 0.3.74 — 해석 · 미리보기 · 꼬리표 스위트) + wt-phone-1017 99bd480d(호스트 퍼센트 인코딩 시험).
// 판 7 Android 이식: 맥 표의 입력과 기대를 **그대로** 옮겨 같은 출력을 잰다. 맥이 그린 글자(`ChatMarkdownText.attributed` 의 characters)는
// 여기서 조각 목록을 이은 글(ChatMarkdownPieces.drawn)로 잰다 — 두 기기가 같은 조각 함수를 쓰기 때문이다. 픽셀 · 글꼴 크기 시험은 ui 몫이다.
package com.yehsung.aingcheck.core.rules.text

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 줄 하나의 (글자, 굵게, 링크) — 표의 기대값 모양. */
internal data class CMRun(val text: String, val bold: Boolean, val link: String?)

internal fun cmRuns(line: ChatMarkdownLine): List<CMRun> = line.spans.map { CMRun(it.text, it.isBold, it.link?.absoluteString) }

internal fun cr(text: String, bold: Boolean = false, link: String? = null) = CMRun(text, bold, link)

/** 한 줄짜리 본문을 해석한 조각들. */
internal fun cmInline(body: String): List<CMRun> {
    val lines = ChatMarkdown.parse(body)
    assertEquals(1, lines.size, "\"$body\" 가 한 줄로 해석되지 않았다(${lines.size}줄)")
    return cmRuns(lines.first())
}

/** 해석이 그리는 글자 전부(줄 사이는 "\n"). 꼬리표는 없다. */
internal fun cmVisible(body: String): String = ChatMarkdown.parse(body).joinToString("\n") { it.text }

/** 말풍선이 그리는 글자(꼬리표 포함) — 맥 `String(ChatMarkdownText.attributed(body).characters)` 자리. */
internal fun cmDrawn(body: String): String = ChatMarkdownPieces.drawn(ChatMarkdownPieces.pieces(body))

/** 원문 줄들 — 해석과 같은 자르기(Swift `isNewline`). */
internal fun cmRows(body: String): List<String> {
    val out = ArrayList<String>()
    val current = StringBuilder()
    for (cluster in Graphemes.clusters(body)) {
        if (SwiftChar.isNewline(cluster)) {
            out += current.toString()
            current.clear()
        } else {
            current.append(cluster)
        }
    }
    out += current.toString()
    return out
}

/** 받는 세 문법의 기호(빠져도 되는 글자). 이것과 공백을 뺀 나머지가 **내용 글자**다. */
private val CM_SYNTAX = setOf("#", "*", "[", "]", "(", ")")

private fun cmContent(text: String): Map<String, Int> {
    val bag = HashMap<String, Int>()
    for (cluster in Graphemes.clusters(text)) if (!SwiftChar.whiteSpace(cluster) && cluster !in CM_SYNTAX) bag[cluster] = (bag[cluster] ?: 0) + 1
    return bag
}

/** [needle] 의 글자가 [haystack] 에 **같은 차례로** 다 들어 있는가(그래핌 단위). */
private fun cmIsSubsequence(needle: String, haystack: String): Boolean {
    val hay = Graphemes.clusters(haystack)
    var cursor = 0
    for (char in Graphemes.clusters(needle)) {
        while (cursor < hay.size && hay[cursor] != char) cursor++
        if (cursor >= hay.size) return false
        cursor++
    }
    return true
}

/** 시드 고정 난수(SplitMix64) — Swift 시험 · 맥 실측 탐침과 같은 생성기. 범위는 단순 나머지(탐침과 같은 몫)다. */
internal class CMRandom(seed: Long) {
    private var state: ULong = seed.toULong()
    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    fun below(n: Int): Int = (next() % n.toULong()).toInt()
}

internal val CM_FUZZ_TOKENS = listOf(
    "*", "**", "_", "__", "~", "~~", "`", "``", "```", "[", "]", "(", ")", "](", "#", "## ", "> ", "- ", "1. ",
    " ", "\n", "\n", "가", "나", "a", "b", "7", ".", ":", "/", "!", "ㅋ", "🎉",
    "https://a.co", "http://b.io/x_y", "javascript:", "file:", "snake_case",
)

internal fun cmFuzzBodies(seed: Long, count: Int, tokens: List<String> = CM_FUZZ_TOKENS): List<String> {
    val random = CMRandom(seed)
    return List(count) {
        val length = 1 + random.below(40)
        buildString { repeat(length) { append(tokens[random.below(tokens.size)]) } }
    }
}

// ---------------------------------------------------------------- ① 해석 — 값으로 잰다

class ChatMarkdownParserTest {

    @Test
    fun headingsStepUpAndHashtagsAreText() {
        val kinds = ChatMarkdown.parse("# 하나\n## 둘\n### 셋\n#### 넷").map { it.kind }
        assertEquals(
            listOf(ChatMarkdownLineKind.heading(1), ChatMarkdownLineKind.heading(2), ChatMarkdownLineKind.heading(3), ChatMarkdownLineKind.heading(4)),
            kinds,
        )
        assertEquals("둘", ChatMarkdown.parse("## 둘").first().text, "제목 기호가 글자에 남았다")
        // 크기 단계: ### 이하는 3에서 멈춘다(그리는 쪽이 단계별 글꼴을 고른다 — ui 시험이 글꼴 크기를 잰다).
        assertEquals(listOf(1, 2, 3, 3, 3, 3, 0), listOf(1, 2, 3, 4, 5, 6).map { ChatMarkdownPieces.headingStep(ChatMarkdownLineKind.heading(it)) } +
            ChatMarkdownPieces.headingStep(ChatMarkdownLineKind.paragraph))
        // 대조군: 기호 뒤 공백이 없거나 내용이 없으면 제목이 아니다 — 글자 그대로다.
        for (body in listOf("#해시태그", "##", "## ", "####### 일곱")) {
            val line = ChatMarkdown.parse(body).first()
            assertTrue(line.kind == ChatMarkdownLineKind.paragraph || line.kind == ChatMarkdownLineKind.blank, "\"$body\" 가 ${line.kind} 로 해석됐다")
            if (line.kind == ChatMarkdownLineKind.paragraph) assertEquals(body, line.text, "\"$body\" 의 글자가 바뀌었다")
        }
    }

    @Test
    fun onlyBoldAndLinksAreInlineSyntax() {
        val table: List<Pair<String, List<CMRun>>> = listOf(
            "**굵게**" to listOf(cr("굵게", true)),
            "앞 **굵게** 뒤" to listOf(cr("앞 "), cr("굵게", true), cr(" 뒤")),
            "이건**중요**해" to listOf(cr("이건"), cr("중요", true), cr("해")),
            "**\"인용\"** 과 **(중요)**" to listOf(cr("\"인용\"", true), cr(" 과 "), cr("(중요)", true)),
            "***둘 다***" to listOf(cr("*둘 다*", true)),
            "[글](https://a.com)" to listOf(cr("글", link = "https://a.com")),
            "[**굵은 글**](https://a.com/x?y=1)" to listOf(cr("굵은 글", true, "https://a.com/x?y=1")),
            "https://a.com 보세요" to listOf(cr("https://a.com", link = "https://a.com"), cr(" 보세요")),
            "**https://a.com**" to listOf(cr("https://a.com", true, "https://a.com")),
            "**[글](https://a.com)** 봐" to listOf(cr("글", true, "https://a.com"), cr(" 봐")),
        )
        for ((body, expected) in table) assertEquals(expected, cmInline(body), "\"$body\"")
    }

    /** ★ 받지 않는 문법은 입력한 글자 그대로다(대표 결정 "제목·굵게·링크만 — 나머지 문법은 기호 그대로"). 그린 조각도 꾸밈 없는 한 덩어리다. */
    @Test
    fun unsupportedSyntaxStaysAsTyped() {
        val bodies = listOf(
            "*기울임*", "_기울임_", "__굵게 아님__", "~~취소~~", "`코드`", "``a`b``", "```let x```", "```swift", "- 사과", "* 배", "+ 감",
            "  - 안쪽", "1. 하나", "12) 열둘", "> 인용", ">> 겹 인용", "    들여쓴 줄", "*a* _b_ ~~c~~ `d`",
        )
        for (body in bodies) {
            val lines = ChatMarkdown.parse(body)
            assertEquals(listOf<ChatMarkdownLineKind>(ChatMarkdownLineKind.paragraph), lines.map { it.kind }, "\"$body\"")
            assertEquals(body, cmVisible(body), "\"$body\"")
            assertTrue(lines.flatMap { it.spans }.all { !it.isBold && it.link == null }, "\"$body\" 에 굵게·링크가 생겼다")
            val pieces = ChatMarkdownPieces.pieces(body)
            assertEquals(1, pieces.size, "\"$body\" 의 말풍선 조각이 ${pieces.size} 덩어리로 갈렸다 — 꾸밈이 붙었다")
            assertEquals(ChatMarkdownPiece(ChatMarkdownPiece.Kind.span, body, ChatMarkdownLineKind.paragraph, false, null), pieces.single())
        }
    }

    @Test
    fun boldAndLinksStillWorkBesideUnsupportedSymbols() {
        assertEquals(listOf(cr("- "), cr("자료", true), cr(" 정리")), cmInline("- **자료** 정리"))
        assertEquals(listOf(cr("> "), cr("글", link = "https://a.com"), cr(" 봐")), cmInline("> [글](https://a.com) 봐"))
        assertEquals(listOf(cr("1. "), cr("https://a.com", link = "https://a.com")), cmInline("1. https://a.com"))
        assertEquals(listOf(cr("`"), cr("x", true), cr("`")), cmInline("`**x**`"))
        assertEquals(listOf(cr("`"), cr("https://a.com", link = "https://a.com"), cr("`")), cmInline("`https://a.com`"))
        assertEquals(listOf(cr("*a "), cr("b", true), cr(" c*")), cmInline("*a **b** c*"))

        val fence = ChatMarkdown.parse("```swift\n**x** [글](https://a.com)\n\n_y_\n```")
        assertEquals(
            listOf(ChatMarkdownLineKind.paragraph, ChatMarkdownLineKind.paragraph, ChatMarkdownLineKind.blank, ChatMarkdownLineKind.paragraph,
                ChatMarkdownLineKind.paragraph),
            fence.map { it.kind },
        )
        assertEquals(listOf("```swift", "x 글", "", "_y_", "```"), fence.map { it.text })
        assertEquals(listOf(cr("x", true), cr(" "), cr("글", link = "https://a.com")), cmRuns(fence[1]))
        assertEquals("```\n```", cmVisible("```\n```"))
    }

    @Test
    fun italicAndStrikeSpotsAreTextButBoldThereWorks() {
        assertEquals(listOf(cr("이건 _기울임_ 이다")), cmInline("이건 _기울임_ 이다"))
        assertEquals(listOf(cr("이건 ~~취소~~ 됐어")), cmInline("이건 ~~취소~~ 됐어"))
        assertEquals(listOf(cr("*진짜* 좋아 *진짜*")), cmInline("*진짜* 좋아 *진짜*"))
        assertEquals(listOf(cr("이건 "), cr("굵게", true), cr(" 이다")), cmInline("이건 **굵게** 이다"))
        assertEquals(listOf(cr("진짜", true), cr(" 좋아 "), cr("진짜", true)), cmInline("**진짜** 좋아 **진짜**"))
    }

    /** 링크는 http·https 만이다. 그 밖 스킴은 링크가 아니고, `[글](주소)` 모양이면 원문 글자 그대로다(Android 쪽 위험 스킴 intent · content 도). */
    @Test
    fun unopenableLinksStayAsTyped() {
        val bodies = listOf(
            "[글](javascript:alert(1))", "[글](file:///etc/passwd)", "[글](check://open/settings)", "[글](mailto:a@b.com)", "[글](ftp://a.com/x)",
            "[글](https://a.com/한글)", "[](https://a.com)", "[https://bank.com](https://evil.com)",
            // Android 갈래: 인텐트 · 콘텐츠 제공자 · 앱 스킴은 브라우저가 아니라 앱을 연다 — 링크가 되면 안 된다.
            "[글](intent://scan/#Intent;scheme=zxing;package=com.x;end)", "[글](content://com.android.contacts/contacts)",
            "[글](market://details?id=x)", "[글](tel:01012345678)", "[글](sms:010)", "[글](data:text/html,<b>x</b>)",
            "[글](aingcheck://message/x)", "[글](HTTPS:evil.com)", "[글](//evil.com)",
        )
        for (body in bodies) {
            val lines = ChatMarkdown.parse(body)
            assertEquals(1, lines.size)
            assertTrue(lines.first().spans.all { it.link == null }, "\"$body\" 가 링크가 됐다: ${lines.first().spans.mapNotNull { it.link }}")
            assertEquals(body, lines.first().text, "\"$body\" 의 원문이 바뀌었다")
        }
    }

    @Test
    fun bareAddressesLinkOnlyForHttp() {
        val table: List<Pair<String, List<CMRun>>> = listOf(
            "주소는 https://a.com/x." to listOf(cr("주소는 "), cr("https://a.com/x", link = "https://a.com/x"), cr(".")),
            "(https://a.com)" to listOf(cr("("), cr("https://a.com", link = "https://a.com"), cr(")")),
            "https://ko.wikipedia.org/wiki/Foo_(bar)" to
                listOf(cr("https://ko.wikipedia.org/wiki/Foo_(bar)", link = "https://ko.wikipedia.org/wiki/Foo_(bar)")),
            "https://a.com에서 봐요" to listOf(cr("https://a.com", link = "https://a.com"), cr("에서 봐요")),
            "여기https://a.com" to listOf(cr("여기"), cr("https://a.com", link = "https://a.com")),
            "HTTPS://A.COM" to listOf(cr("HTTPS://A.COM", link = "HTTPS://A.COM")),
            "[https://a.com](https://a.com)" to listOf(cr("https://a.com", link = "https://a.com")),
            "http://b.io/x_y_z" to listOf(cr("http://b.io/x_y_z", link = "http://b.io/x_y_z")),
            "https://a.com~~ 봐줘~~" to listOf(cr("https://a.com", link = "https://a.com"), cr("~~ 봐줘~~")),
        )
        for ((body, expected) in table) assertEquals(expected, cmInline(body), "\"$body\"")
        for (body in listOf("javascript:alert(1)", "file:///etc/passwd", "xhttps://a.com", "https://", "http:// a.com", "www.a.com", "check://open",
            "intent://x#Intent;end", "content://a/b")) {
            assertTrue(ChatMarkdown.parse(body).flatMap { it.spans }.all { it.link == null }, "\"$body\" 가 링크가 됐다")
            assertEquals(body, cmVisible(body), "\"$body\" 의 글자가 바뀌었다")
        }
        // 여는 문의 두 번째 검사(말풍선이 누를 때 묻는 자리).
        assertTrue(ChatMarkdown.isOpenable("https://a.com"))
        assertTrue(ChatMarkdown.isOpenable("HTTP://a.com/x"))
        for (raw in listOf("javascript:alert(1)", "file:///etc/passwd", "check://open", "mailto:a@b.com", "https://", "intent://a.com/#Intent;end",
            "content://media/external", "JAVASCRIPT:alert(1)", " https://a.com", "https://a.com\n", "")) {
            assertFalse(ChatMarkdown.isOpenable(raw), "$raw 를 열 수 있다고 한다")
        }
    }

    @Test
    fun addressesWithUserInfoAreNotLinks() {
        for (body in listOf(
            "https://naver.com:443@evil.com", "https://www.google.com:search@evil.com/login", "https://@evil.com",
            "http://a:b@c.com/x", "봐 https://naver.com@evil.com 여기", "**https://naver.com@evil.com**",
            "[naver.com](https://naver.com:443@evil.com)", "[여기](https://user@evil.com)",
        )) {
            val spans = ChatMarkdown.parse(body).flatMap { it.spans }
            assertTrue(spans.all { it.link == null }, "\"$body\" 가 링크가 됐다: ${spans.mapNotNull { it.link }}")
            if (!body.startsWith("**")) assertEquals(body, cmVisible(body), "\"$body\" 의 글자가 바뀌었다")
        }
        for (raw in listOf("https://naver.com:443@evil.com", "https://@evil.com", "https://:p@evil.com", "https://u:@evil.com")) {
            assertFalse(ChatMarkdown.isOpenable(raw), "$raw 를 열 수 있다고 한다")
        }
        val table: List<Pair<String, List<CMRun>>> = listOf(
            "https://a.com/x@y" to listOf(cr("https://a.com/x@y", link = "https://a.com/x@y")),
            "https://a.com/?to=a@b.com" to listOf(cr("https://a.com/?to=a@b.com", link = "https://a.com/?to=a@b.com")),
            "[안내](https://a.com/u/a@b)" to listOf(cr("안내", link = "https://a.com/u/a@b")),
            "https://evil.com" to listOf(cr("https://evil.com", link = "https://evil.com")),
        )
        for ((body, expected) in table) assertEquals(expected, cmInline(body), "\"$body\"")
    }

    /** 호스트를 퍼센트 인코딩한 주소는 링크가 아니다(1.0.17 검토 critical·major — wt-phone-1017 99bd480d 와 같은 표). 경로 · 질의의 인코딩은 링크다. */
    @Test
    fun percentEncodedHostsAreNotLinks() {
        val disguised = listOf(
            "[naver.com](https://n%D0%B0ver.com)", "[apple.com](https://%D0%B0pple.com/login)",
            "[애플 로그인](https://%D0%B0%D1%80%D1%80%D3%8F%D0%B5.com/id)",
            "확인 https://naver.com%2E%65%76%69%6C%2E%63%6F%6D/login", "https://naver.com%2Eevil.com",
            "https://%D0%B0pple.com/login", "**https://naver.com%2Eevil.com**",
        )
        for (body in disguised) {
            val spans = ChatMarkdown.parse(body).flatMap { it.spans }
            assertTrue(spans.all { it.link == null }, "\"$body\" 가 링크가 됐다: ${spans.mapNotNull { it.link }}")
            if (!body.startsWith("**")) assertEquals(body, cmVisible(body))
        }
        for (raw in listOf("https://n%D0%B0ver.com", "https://%D0%B0pple.com/login", "https://%D0%B0%D1%80%D1%80%D3%8F%D0%B5.com/id",
            "https://naver.com%2E%65%76%69%6C%2E%63%6F%6D/login", "https://naver.com%2Eevil.com")) {
            assertFalse(ChatMarkdown.isOpenable(raw), "$raw 를 열 수 있다고 한다")
        }
        val table: List<Pair<String, List<CMRun>>> = listOf(
            "https://ko.wikipedia.org/wiki/%ED%95%9C%EA%B8%80" to
                listOf(cr("https://ko.wikipedia.org/wiki/%ED%95%9C%EA%B8%80", link = "https://ko.wikipedia.org/wiki/%ED%95%9C%EA%B8%80")),
            "[문서](https://a.com/%ED%95%9C?q=%20)" to listOf(cr("문서", link = "https://a.com/%ED%95%9C?q=%20")),
            "https://naver.com" to listOf(cr("https://naver.com", link = "https://naver.com")),
        )
        for ((body, expected) in table) assertEquals(expected, cmInline(body), "\"$body\"")
        assertTrue(ChatMarkdown.isOpenable("https://ko.wikipedia.org/wiki/%ED%95%9C"))
    }

    @Test
    fun boldCloserIsNeverSearchedInsideLinks() {
        val table: List<Pair<String, List<CMRun>>> = listOf(
            "**a [글](https://x.com/**) b**" to listOf(cr("a ", true), cr("글", true, "https://x.com/**"), cr(" b", true)),
            "**[글](https://x.com/**)**" to listOf(cr("글", true, "https://x.com/**")),
            "**굵게 https://a.com/**x** 끝**" to listOf(cr("굵게 ", true), cr("https://a.com/**x", true, "https://a.com/**x"), cr(" 끝**")),
            "**a [글](javascript:x**) b**" to listOf(cr("a [글](javascript:x**) b", true)),
            "**a [글 b** c" to listOf(cr("a [글 b", true), cr(" c")),
            "**[글](https://x.com)** 끝" to listOf(cr("글", true, "https://x.com"), cr(" 끝")),
            "**https://a.com**" to listOf(cr("https://a.com", true, "https://a.com")),
            "**a https://x.com/** b" to listOf(cr("a ", true), cr("https://x.com/", true, "https://x.com/"), cr(" b")),
        )
        for ((body, expected) in table) assertEquals(expected, cmInline(body), "\"$body\"")
    }

    @Test
    fun brokenSyntaxStaysAsTyped() {
        for (body in listOf(
            "**열고 안 닫음", "안 열고 닫음**", "** 앞에 공백**", "**뒤에 공백 **", "`홀로 선 백틱", "a ` b", "~~열림", "x * 앞에 공백 *",
            "2 * 3 = 6", "[글](https://a.com", "[글] (https://a.com)", "**", "****", "``", "***", "_", "[", "](", "> ", "- ",
        )) {
            assertEquals(body, cmVisible(body), "\"$body\"")
            assertTrue(ChatMarkdown.parse(body).flatMap { it.spans }.none { it.isBold }, "\"$body\" 에 굵게가 생겼다")
        }
    }

    @Test
    fun chatHabitsStayAsTyped() {
        for (body in listOf(
            "snake_case_name", "foo_bar_", "a_b_c 그리고 x_y", "ㅎㅎ~~고마워~~", "안녕~~ 반가워~~", "-_-", ">_<", ">ㅅ<", "#해시태그", "+1 동의",
            "1.5배", "고마워요 *^^*", "*^^* 고마워요 *^^*", "^_^ 좋아 ^_^", "-_- 아 진짜 -_-", ">_< 헐 >_<", "^__^ 좋아 ^__^", "*_* 와 *_*",
            "*.* 와 *.*", "*^_^* 굿 *^_^*", "(*´▽`*)", "2*3*4", "x*2 와 y*3", "시*발 진짜 시*발", "_진짜_ 좋아 _진짜_", "~~진짜~~ 좋아 ~~진짜~~",
            "ㅋㅋ `진짜` ㅋㅋ `진짜`",
        )) {
            val lines = ChatMarkdown.parse(body)
            assertEquals(listOf<ChatMarkdownLineKind>(ChatMarkdownLineKind.paragraph), lines.map { it.kind }, "\"$body\"")
            assertEquals(body, cmVisible(body), "\"$body\"")
            assertTrue(lines.flatMap { it.spans }.none { it.isBold }, "\"$body\" 에 굵게가 생겼다")
        }
    }

    @Test
    fun randomEmoticonBodiesStayAsTyped() {
        val tokens = listOf(
            "^_^", "^^", "-_-", "-_-;;", ">_<", "*^^*", "*^_^*", "*.*", "*_*", "^__^", "ㅠ_ㅠ", "T_T",
            "2*3", "3*4=12", "시*발", "좋아", "고마워", "ㅋㅋ", "진짜", "ㅎㅎ~~", "snake_case", "!", "?",
        )
        val random = CMRandom(0x5EED0FE3)
        var paired = 0
        repeat(1_000) {
            val count = 1 + random.below(10)
            val body = List(count) { tokens[random.below(tokens.size)] }.joinToString(" ")
            if (body.count { it == '*' || it == '_' } >= 4) paired++
            assertEquals(body, cmVisible(body))
            assertTrue(ChatMarkdown.parse(body).flatMap { it.spans }.none { it.isBold }, "$body 에 굵게가 생겼다")
        }
        assertTrue(paired > 300, "기호 넷 이상인 본문이 ${paired}개뿐이다")
    }

    @Test
    fun singleNewlineIsANewline() {
        val lines = ChatMarkdown.parse("첫 줄\n둘째 줄\n\n넷째 줄")
        assertEquals(
            listOf(ChatMarkdownLineKind.paragraph, ChatMarkdownLineKind.paragraph, ChatMarkdownLineKind.blank, ChatMarkdownLineKind.paragraph),
            lines.map { it.kind },
        )
        assertEquals(listOf("첫 줄", "둘째 줄", "", "넷째 줄"), lines.map { it.text })
        assertEquals(listOf("가", "나"), ChatMarkdown.parse("가\r\n나").map { it.text }, "\\r\\n 이 줄을 안 나눴다")
        assertEquals("첫 줄\n둘째 줄\n\n넷째 줄", cmDrawn("첫 줄\n**둘째** 줄\n\n넷째 줄"))
        assertEquals("안녕\n반가워", cmDrawn("안녕\n반가워"))
    }

    @Test
    fun listsQuotesAndFencesAreDrawnAsTyped() {
        val body = "- 사과\n* 배\n+ 감\n  - 안쪽\n1. 하나\n12) 열둘\n> 인용 **굵게**\n```\n코드\n```"
        assertEquals(List<ChatMarkdownLineKind>(10) { ChatMarkdownLineKind.paragraph }, ChatMarkdown.parse(body).map { it.kind })
        assertEquals("- 사과\n* 배\n+ 감\n  - 안쪽\n1. 하나\n12) 열둘\n> 인용 굵게\n```\n코드\n```", cmDrawn(body))
    }

    /** 200자 경계(서버 상한 · MessageBody.maxLength). 상한 길이 본문도 해석되고, 기호뿐인 상한 본문도 글자를 잃지 않는다. */
    @Test
    fun twoHundredCharacterBodiesKeepTheirCharacters() {
        val max = MessageBody.maxLength
        val heading = "## " + "가".repeat(max - 3)
        val line = ChatMarkdown.parse(heading).first()
        assertEquals(ChatMarkdownLineKind.heading(2), line.kind)
        assertEquals(max - 3, Graphemes.count(line.text))
        for (unit in listOf("*", "`", "_", "~", "[", "**a", "*a ", "[a](", "`a", "~~a", "https://a.co/", "- ", "> ", "1. ", "```\n")) {
            val body = unit.repeat(max).take(max)
            val visible = cmVisible(body)
            assertTrue(cmIsSubsequence(visible, body), "\"$unit\" × 200 이 글자를 지어냈다")
            assertEquals(cmContent(body), cmContent(visible), "\"$unit\" × 200 에서 내용 글자가 빠졌다")
            if ("**" !in body && "](" !in body && !body.startsWith("#")) assertEquals(body, visible, "\"$unit\" × 200 의 글자가 바뀌었다")
        }
    }

    /**
     * ★ 글자 보존 — 무작위 3천 개(시드 고정). 어떤 입력에서도: ⓐ 그린 글자는 원문의 부분 수열 ⓑ `](` 가 없는 입력은 내용 글자 개수가 같다
     * ⓒ 링크는 전부 http·https ⓓ `**` · `](` · 줄 머리 `#` 이 없는 입력은 글자 하나 안 바뀐다 ⓔ 공백 아닌 글자가 있는 줄은 비지 않는다.
     */
    @Test
    fun randomBodiesOnlyLoseAcceptedSymbols() {
        var checkedContent = 0
        var checkedExact = 0
        var linked = 0
        for (body in cmFuzzBodies(0x0C4EC4ED, 3_000)) {
            val lines = ChatMarkdown.parse(body)
            val rows = cmRows(body)
            val visible = lines.joinToString("\n") { it.text }
            assertTrue(cmIsSubsequence(visible, body), "글자를 지어냈다: $body → $visible")
            if ("](" !in body) {
                checkedContent++
                assertEquals(cmContent(body), cmContent(visible), "내용 글자가 빠졌다: $body → $visible")
            }
            if ("**" !in body && "](" !in body && rows.none { it.startsWith("#") }) {
                checkedExact++
                val expected = rows.joinToString("\n") { row -> if (Graphemes.clusters(row).all(SwiftChar::whiteSpace)) "" else row }
                assertEquals(expected, visible, "받지 않는 기호가 바뀌었다: $body")
            }
            assertEquals(rows.size, lines.size, "원문 ${rows.size}줄이 ${lines.size}줄이 됐다: $body")
            for ((row, line) in rows.zip(lines)) {
                if (Graphemes.clusters(row).any { !SwiftChar.whiteSpace(it) }) {
                    assertTrue(line.text.isNotEmpty() && line.kind != ChatMarkdownLineKind.blank, "글자 있는 줄이 비었다: $row")
                }
            }
            for (link in lines.flatMap { it.spans }.mapNotNull { it.link }) {
                linked++
                assertTrue(ChatMarkdown.isOpenable(link.absoluteString), "열 수 없는 링크가 생겼다: $link ← $body")
            }
        }
        assertTrue(checkedContent > 1_000, "내용 비교를 한 입력이 ${checkedContent}개뿐이다")
        assertTrue(checkedExact > 500, "글자 그대로 비교를 한 입력이 ${checkedExact}개뿐이다")
        assertTrue(linked > 100, "링크가 ${linked}개뿐이다 — 링크 갈래를 안 지났다")
    }
}

// ---------------------------------------------------------------- ② 한 줄 미리보기

class ChatMarkdownPreviewTest {
    @Test
    fun previewStripsOnlyTheThreeSyntaxesAndFoldsNewlines() {
        assertEquals("제목 굵게 와 글 그리고 `코드`", ChatMarkdown.plainPreview("## 제목\n**굵게** 와 [글](https://a.com) 그리고 `코드`"))
        assertEquals("- 사과 - 배 > 인용", ChatMarkdown.plainPreview("- 사과\n- 배\n\n> 인용"))
        assertEquals("```swift let a = 1 ```", ChatMarkdown.plainPreview("```swift\nlet a = 1\n```"))
        assertEquals("1. 하나 2. 둘", ChatMarkdown.plainPreview("1. 하나\n2. 둘"))
        assertEquals("*기울임* _밑줄_ ~~취소~~", ChatMarkdown.plainPreview("*기울임* _밑줄_ ~~취소~~"))
        assertEquals("[글](javascript:alert(1))", ChatMarkdown.plainPreview("[글](javascript:alert(1))"))
    }

    @Test
    fun plainBodiesAreUnchanged() {
        for (body in listOf(
            "화이팅", "오늘 고생했어요", "점심 드셨어요?", "고마워요 :)", "👍🏻🎉🇰🇷", "snake_case", "-_-", "2 * 3 = 6", "https://a.com",
            "*기울임*", "`코드`", "- 항목", "> 인용", "~~취소~~",
        )) assertEquals(body, ChatMarkdown.plainPreview(body))
    }

    @Test
    fun stickerTokensReadAsNames() {
        for (sticker in AingSticker.entries) assertEquals("아잉이 ${sticker.label}", ChatMarkdown.plainPreview(sticker.token))
        assertEquals("아잉이 놀람", ChatMarkdown.plainPreview("  [아잉:놀람]\n"))
        assertEquals("", ChatMarkdown.plainPreview(""))
    }
}

// ---------------------------------------------------------------- ③ 호스트 꼬리표

class ChatMarkdownLinkDisclosureTest {
    @Test
    fun linksWhoseLabelDiffersShowTheRealHost() {
        assertEquals("naver.com (evil.example)", cmDrawn("[naver.com](https://evil.example)"))
        assertEquals("여기 (evil.example)", cmDrawn("[여기](https://evil.example/login)"))
        assertTrue(cmDrawn("[https:/​/good.com](https://evil.com)").endsWith(" (evil.com)"))
        assertTrue(cmDrawn("[https：//good.com](https://evil.com)").endsWith(" (evil.com)"))
        assertTrue(cmDrawn("[‮moc.doog//:sptth](https://evil.com)").endsWith(" (evil.com)"))
        // 붙인 호스트는 링크가 아니다 — 누르는 자리는 글 그대로다.
        val pieces = ChatMarkdownPieces.pieces("[여기](https://evil.example)")
        assertEquals(listOf("여기"), pieces.filter { it.link != null }.map { it.text })
        assertEquals(ChatMarkdownPiece.Kind.disclosure, pieces.last().kind)
        assertNull(pieces.last().link)
    }

    @Test
    fun labelsThatAlreadySayTheAddressGetNoTag() {
        assertEquals("https://a.com/x 보세요", cmDrawn("https://a.com/x 보세요"))
        assertEquals("naver.com", cmDrawn("[naver.com](https://naver.com)"))
        assertEquals("https://a.com/", cmDrawn("[https://a.com/](https://a.com)"))
        assertEquals("www.naver.com", cmDrawn("[www.naver.com](https://www.naver.com)"))
    }

    @Test
    fun sameAddressWithWwwLabelIsALink() {
        val spans = ChatMarkdown.parse("[www.naver.com](https://www.naver.com)").first().spans
        assertEquals(listOf("https://www.naver.com"), spans.mapNotNull { it.link?.absoluteString })
        assertTrue(ChatMarkdown.parse("[https://bank.com](https://evil.com)").first().spans.all { it.link == null })
    }

    @Test
    fun twoLinksEachGetTheirOwnTag() {
        val shown = cmDrawn("[가](https://a.example) 와 [나](https://b.example)")
        assertEquals("가 (a.example) 와 나 (b.example)", shown)
        assertEquals(2, shown.split("(a.example)").size)
    }

    @Test
    fun addedCharactersCountTheTag() {
        val line = assertNotNull(ChatMarkdown.parse("[여기](https://a-very-long-host-name.example)").firstOrNull())
        assertEquals(" (a-very-long-host-name.example)".length, ChatMarkdownPieces.addedCharacters(line))
        assertEquals(0, ChatMarkdownPieces.addedCharacters(ChatMarkdown.parse("https://a.com").first()))
    }
}
