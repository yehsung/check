// 원본: 없음 — 판 7 Android 이식의 Swift 대조 시험. 기대값은 맥에서 **실제로 돌린** Swift 탐침의 출력이다(2026-11-03 · Darwin 27 ·
// Swift 6.4.2 · wt-phone-1017 의 Sources/CheckCore/ChatMarkdown.swift + ChatMarkdownPieces.swift 를 그대로 컴파일 — 저장소 밖 작업 사본에서).
//
// 왜 따로 있나: 해석기의 "모양"은 맥 표를 옮긴 ChatMarkdownTest 가 잰다. 여기는 **Swift Foundation 과 Kotlin/JVM 이 갈릴 수 있는 곳**을 못 박는다.
//  ① URL — Foundation `URL(string:)`(RFC 3986 · 잘못된 글자는 퍼센트 인코딩) 대 Kotlin 손 파서(ChatURL). ASCII 0x21~0x7E 한 글자씩을
//     호스트 · 경로 · 질의 · 조각 · 대괄호 호스트에 넣어 본 표(실측 475칸)에서 갈림이 없다는 것을 아래 표가 대표로 잰다.
//  ② 글자 단위 — Swift `Character`(그래핌) · `String ==`(정준 동치) · 글자 단위 hasPrefix/contains 대 Kotlin UTF-16.
//  ③ 무작위 본문 두 묶음(각 3천 개 — 시드 고정)을 해석 · 그린 글 · 미리보기 · 복사 표시까지 한 줄로 이어 FNV-1a 64 지문을 낸다.
//     Swift 탐침이 같은 생성기(SplitMix64 + 나머지)로 같은 본문을 만들어 낸 지문과 같아야 한다 — 하나라도 갈리면 빨강이다.
//  ④ 복사 글 — 본문 여덟의 모든 구간(서로게이트 짝을 가르는 구간은 뺀다 — Swift 는 String 으로 옮길 때 U+FFFD 로 바꾼다) 2,561칸 지문.
// 탐침을 다시 돌리는 법(저장소 밖): ChatMarkdown.swift · ChatMarkdownPieces.swift 의 `package` 를 떼고 main.swift(모드 url · parse · digest · copy)와
// swiftc 로 묶는다. 이 파일의 표가 바뀌면 탐침 출력부터 다시 뜬다 — 손으로 기대값을 고치지 않는다.
package com.yehsung.aingcheck.core.rules.text

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChatMarkdownSwiftParityTest {

    /** (원문, Foundation absoluteString, host(percentEncoded: true)) — 열 수 있는 주소. */
    private val openable = listOf(
        Triple("https://a.com", "https://a.com", "a.com"),
        Triple("HTTPS://A.COM", "HTTPS://A.COM", "A.COM"),
        Triple("https://a.com/x|y", "https://a.com/x%7Cy", "a.com"),
        Triple("https://a.com/{x}", "https://a.com/%7Bx%7D", "a.com"),
        Triple("https://a.com/x\\y", "https://a.com/x%5Cy", "a.com"),
        Triple("https://a.com/x^y", "https://a.com/x%5Ey", "a.com"),
        Triple("https://a.com/x`y", "https://a.com/x%60y", "a.com"),
        Triple("https://a.com/x\"y", "https://a.com/x%22y", "a.com"),
        Triple("https://a.com/x<y>", "https://a.com/x%3Cy%3E", "a.com"),
        Triple("https://a.com/x[1]", "https://a.com/x%5B1%5D", "a.com"),
        Triple("https://a.com/%zz", "https://a.com/%25zz", "a.com"),
        Triple("https://a.com/%4", "https://a.com/%254", "a.com"),
        Triple("https://a.com/%41", "https://a.com/%41", "a.com"),
        Triple("https://a.com/x%7cy", "https://a.com/x%7cy", "a.com"),
        Triple("https://a.com/a%2", "https://a.com/a%252", "a.com"),
        Triple("https://a.com/x%", "https://a.com/x%25", "a.com"),
        Triple("https://a.com/#a#b", "https://a.com/#a%23b", "a.com"),
        Triple("https://a.com/?q=[1]", "https://a.com/?q=%5B1%5D", "a.com"),
        Triple("https://a.com/?q=|", "https://a.com/?q=%7C", "a.com"),
        Triple("https://a.com/#|", "https://a.com/#%7C", "a.com"),
        Triple("https://a.com#[x]", "https://a.com#%5Bx%5D", "a.com"),
        Triple("https://a.com/?x!\$&'()*+,;=:@/?", "https://a.com/?x!\$&'()*+,;=:@/?", "a.com"),
        Triple("https://a.com/#x!\$&'()*+,;=:@/?", "https://a.com/#x!\$&'()*+,;=:@/?", "a.com"),
        Triple("https://a!b.com", "https://a!b.com", "a!b.com"),
        Triple("https://a(b).com", "https://a(b).com", "a(b).com"),
        Triple("https://a_b.com", "https://a_b.com", "a_b.com"),
        Triple("https://a~b.com", "https://a~b.com", "a~b.com"),
        Triple("https://a.com:80", "https://a.com:80", "a.com"),
        Triple("https://a.com:", "https://a.com:", "a.com"),
        Triple("https://a.com:99999", "https://a.com:99999", "a.com"),
        Triple("https://[::1]/x", "https://[::1]/x", "::1"),
        Triple("https://[::1]:8080", "https://[::1]:8080", "::1"),
        Triple("https://[::1]:/", "https://[::1]:/", "::1"),
        Triple("https://[a.com]/", "https://[a.com]/", "a.com"),
        Triple("https://[v1.x]/", "https://[v1.x]/", "v1.x"),
        Triple("https://[1::2::3]/", "https://[1::2::3]/", "1::2::3"),
        Triple("https://[a:80]:80/", "https://[a:80]:80/", "a:80"),
        Triple("https://127.0.0.1/", "https://127.0.0.1/", "127.0.0.1"),
        Triple("https://a.com?x", "https://a.com?x", "a.com"),
        Triple("https://a.com/../x", "https://a.com/../x", "a.com"),
        Triple("https://a..com", "https://a..com", "a..com"),
        Triple("https://-a.com", "https://-a.com", "-a.com"),
        Triple("https://xn--nver-53d.com/", "https://xn--nver-53d.com/", "xn--nver-53d.com"),
        Triple("http://b.io/x_y_z", "http://b.io/x_y_z", "b.io"),
        Triple("https://a.com:99999999999999999999", "https://a.com:99999999999999999999", "a.com"),
        Triple("https://a.com:/x", "https://a.com:/x", "a.com"),
        Triple("https://a.com:?q", "https://a.com:?q", "a.com"),
        // 인코딩 갈래(잘못된 글자가 하나라도 있으면 주소를 조각에서 다시 짓는다): 빈 포트 `:` 가 빠지고 · 포트는 정수 · 그 조각의 `%` 는 모두 `%25`.
        Triple("https://a.com:/x|y", "https://a.com/x%7Cy", "a.com"),
        Triple("https://a.com://x|", "https://a.com//x%7C", "a.com"),
        Triple("https://a.com:?q|", "https://a.com?q%7C", "a.com"),
        Triple("https://a.com:80//x|", "https://a.com:80//x%7C", "a.com"),
        Triple("https://a.com:080/x|", "https://a.com:80/x%7C", "a.com"),
        Triple("https://a.com:0000000000000000000000001/x|", "https://a.com:1/x%7C", "a.com"),
        Triple("https://a.com:9223372036854775808/x|", "https://a.com/x%7C", "a.com"),
        Triple("https://[::1]:080/x|", "https://[::1]:80/x%7C", "::1"),
        Triple("https://[::1]:/x|", "https://[::1]/x%7C", "::1"),
        Triple("HTTPS://A.COM:/x|", "HTTPS://A.COM/x%7C", "A.COM"),
        Triple("https://a.com/%41|", "https://a.com/%2541%7C", "a.com"),
        Triple("https://a.com/%zz%41", "https://a.com/%25zz%2541", "a.com"),
        Triple("https://a.com/%41?q=|", "https://a.com/%41?q=%7C", "a.com"),
        Triple("https://a.com/x|#%41", "https://a.com/x%7C#%41", "a.com"),
        Triple("https://a.com/x|#a:b@c/?d#e", "https://a.com/x%7C#a:b@c/?d%23e", "a.com"),
        Triple("https://a.com/x|?", "https://a.com/x%7C?", "a.com"),
        Triple("https://a.com?#|", "https://a.com?#%7C", "a.com"),
        Triple("https://=https://\\(@'www", "https://=https//%5C(@'www", "=https"),
    )

    /** 열 수 없는 주소 — Foundation 이 URL 을 안 세우거나(nil) · 호스트가 없거나 · 사용자 정보 · 호스트 `%` · 스킴. */
    private val notOpenable = listOf(
        "https://a|b.com", "https://a{b.com", "https://a\\b.com", "https://a\"b.com", "https://a^b.com", "https://a`b.com", "https://a<b.com",
        "https://a%b.com", "https://a.com]/", "https://a.com[/", "https://a.com:-1", "https://a.com:8a", "https://a.com:80:90", "https://:80",
        "https://[::1%25en0]/", "https://[fe80::1%en0]/", "https://[a%41]/", "https://[]/", "https://[::1]x/", "https://[::1]:x/",
        "https://[[a]]/", "https://[a]b]/", "https://[a|b]/", "https://[a\\b]/", "https://[a^b]/",
        "https://a@b@c.com", "https://@evil.com", "https://user:@a.com", "https://:p@a.com", "https://a.com:443@",
        "https://n%D0%B0ver.com", "https://%61.com", "https://a.com%2F",
        "https:a.com", "https:/a.com", "https:///a.com", "https://", "http://",
        "javascript:alert(1)", "file:///etc/passwd", "check://open", "mailto:a@b.com", "ftp://a.com/x", "intent://a.com/#Intent;end",
        "content://media/external/images", "1https://a.com", "+https://a.com",
    )

    @Test
    fun urlBehaviourMatchesFoundation() {
        for ((raw, absolute, host) in openable) {
            val link = ChatMarkdown.openableLink(raw)
            assertEquals(absolute, link?.absoluteString, "absoluteString($raw)")
            assertEquals(host, link?.host, "host($raw)")
            assertTrue(ChatMarkdown.isOpenable(raw), "isOpenable($raw)")
            // 여는 문은 absoluteString 을 다시 묻는다 — 인코딩한 글자도 같은 답(멱등)이어야 한다.
            assertEquals(absolute, ChatMarkdown.openableLink(absolute)?.absoluteString, "다시 연 absoluteString($raw)")
        }
        for (raw in notOpenable) {
            assertNull(ChatMarkdown.openableLink(raw), "openableLink($raw)")
        }
    }

    /** 맥 실측 출력 그대로(본문 → 해석 줄 · 그린 글 · 미리보기). 갈리기 쉬운 곳만 골랐다. */
    private data class Case(val body: String, val lines: List<Pair<ChatMarkdownLineKind, List<CMRun>>>, val drawn: String, val preview: String)

    private val p = ChatMarkdownLineKind.paragraph

    private val cases = listOf(
        // 글자 단위 contains("://") · hasPrefix("www.") — 결합 문자가 붙은 `/` · `.` 는 그 글자가 아니다 → 주소 흉내가 아니다(링크 + 꼬리표).
        Case("[a://\u0301b](https://evil.com)", listOf(p to listOf(cr("a://\u0301b", link = "https://evil.com"))), "a://\u0301b (evil.com)", "a://\u0301b"),
        Case("[www.\u0301a.com](https://evil.com)", listOf(p to listOf(cr("www.\u0301a.com", link = "https://evil.com"))), "www.\u0301a.com (evil.com)",
            "www.\u0301a.com"),
        // String == 는 정준 동치: U+037E(그리스 물음표) ≡ ";" → 같은 주소 · 꼬리표 없음.
        Case("[www.a.com\u037E](https://www.a.com;)", listOf(p to listOf(cr("www.a.com\u037E", link = "https://www.a.com;"))), "www.a.com\u037E",
            "www.a.com\u037E"),
        // 켈빈 기호 K 는 소문자로 k.
        Case("[\u212Aa.com](https://ka.com)", listOf(p to listOf(cr("\u212Aa.com", link = "https://ka.com"))), "\u212Aa.com", "\u212Aa.com"),
        // 글자 단위 hasSuffix("/") — `/\u0301` 은 빗금이 아니다 → 다른 주소 → 주소 흉내(원문).
        Case("[www.a.com/\u0301](https://www.a.com)", listOf(p to listOf(cr("[www.a.com/\u0301](https://www.a.com)"))),
            "[www.a.com/\u0301](https://www.a.com)", "[www.a.com/\u0301](https://www.a.com)"),
        Case("[https://\u0301a.com](https://a.com)", listOf(p to listOf(cr("https://\u0301a.com", link = "https://a.com"))), "https://\u0301a.com (a.com)",
            "https://\u0301a.com"),
        // 공백 다듬기는 CharacterSet.whitespaces(U+3000 · U+200B 포함).
        Case("[\u3000https://a.com\u3000](https://a.com)", listOf(p to listOf(cr("\u3000https://a.com\u3000", link = "https://a.com"))),
            "\u3000https://a.com\u3000", "https://a.com"),
        Case("https://a.co\u200B", listOf(p to listOf(cr("https://a.co", link = "https://a.co"), cr("\u200B"))), "https://a.co\u200B", "https://a.co"),
        Case("**\u200B**", listOf(p to listOf(cr("\u200B", true))), "\u200B", ""),
        // 인코딩된 absoluteString 이 글과 달라 맨 주소에도 꼬리표가 붙는다(맥과 같은 결과 — 경로의 `|` 는 브라우저로 `%7C` 가 간다).
        Case("https://a.com/x|y 봐", listOf(p to listOf(cr("https://a.com/x|y", link = "https://a.com/x%7Cy"), cr(" 봐"))),
            "https://a.com/x|y (a.com) 봐", "https://a.com/x|y 봐"),
        Case("https://a.com/%zz", listOf(p to listOf(cr("https://a.com/%zz", link = "https://a.com/%25zz"))), "https://a.com/%zz (a.com)",
            "https://a.com/%zz"),
        Case("[여기](https://[::1]:8080/x)", listOf(p to listOf(cr("여기", link = "https://[::1]:8080/x"))), "여기 (::1)", "여기"),
        Case("[a.com](https://A.COM/)", listOf(p to listOf(cr("a.com", link = "https://A.COM/"))), "a.com", "a.com"),
        // 그래핌: 결합 문자가 붙은 `#` · 공백은 기호가 아니다.
        Case("#\u0301 제목", listOf(p to listOf(cr("#\u0301 제목"))), "#\u0301 제목", "#\u0301 제목"),
        Case("## \u0301제목", listOf(p to listOf(cr("## \u0301제목"))), "## \u0301제목", "## \u0301제목"),
        Case(" \u0301", listOf(ChatMarkdownLineKind.blank to emptyList()), "", ""),
        Case("https://a.com\u0301", listOf(p to listOf(cr("https://a.co", link = "https://a.co"), cr("m\u0301"))), "https://a.com\u0301",
            "https://a.com\u0301"),
        Case("[글](https://a.com)\u0301", listOf(p to listOf(cr("[글]("), cr("https://a.com", link = "https://a.com"), cr(")\u0301"))),
            "[글](https://a.com)\u0301", "[글](https://a.com)\u0301"),
        Case("\u0301[글](https://a.com)", listOf(p to listOf(cr("\u0301"), cr("글", link = "https://a.com"))), "\u0301글 (a.com)", "\u0301글"),
        Case("*\u0301*굵게**", listOf(p to listOf(cr("*\u0301*굵게**"))), "*\u0301*굵게**", "*\u0301*굵게**"),
        // 줄바꿈 일곱 갈래.
        Case("x\ry\u2028z\u2029w\u0085v\u000Bq\u000Cr", "xyzwvqr".map { p to listOf(cr(it.toString())) }, "x\ny\nz\nw\nv\nq\nr", "x y z w v q r"),
        Case("\t# 제목", listOf(p to listOf(cr("\t# 제목"))), "\t# 제목", "# 제목"),
        Case("#\t제목", listOf(ChatMarkdownLineKind.heading(1) to listOf(cr("제목"))), "제목", "제목"),
        Case("# \t", listOf(p to listOf(cr("# \t"))), "# \t", "#"),
        Case("[글](<https://a.com>)", listOf(p to listOf(cr("[글](<https://a.com>)"))), "[글](<https://a.com>)", "[글](<https://a.com>)"),
        Case("[a.com](https://a.com)[b](https://a.com)", listOf(p to listOf(cr("a.com", link = "https://a.com"), cr("b", link = "https://a.com"))),
            "a.comb (a.com)", "a.comb"),
        Case("[](https://a.com) [x](https://a.com)", listOf(p to listOf(cr("[](https://a.com) "), cr("x", link = "https://a.com"))),
            "[](https://a.com) x (a.com)", "[](https://a.com) x"),
        Case("**bold** and [link **inner**](https://a.com) end",
            listOf(p to listOf(cr("bold", true), cr(" and "), cr("link ", link = "https://a.com"), cr("inner", true, "https://a.com"), cr(" end"))),
            "bold and link inner (a.com) end", "bold and link inner end"),
    )

    @Test
    fun graphemeAndEquivalenceCasesMatchSwift() {
        for (case in cases) {
            val lines = ChatMarkdown.parse(case.body)
            assertEquals(case.lines.map { it.first }, lines.map { it.kind }, "줄 종류(${case.body})")
            assertEquals(case.lines.map { it.second }, lines.map(::cmRuns), "조각(${case.body})")
            assertEquals(case.drawn, cmDrawn(case.body), "그린 글(${case.body})")
            assertEquals(case.preview, ChatMarkdown.plainPreview(case.body), "미리보기(${case.body})")
        }
    }

    // ---------------------------------------------------------------- 지문 — 무작위 본문 두 묶음 · 복사 구간

    private fun fnv(text: String, start: ULong = 0xcbf29ce484222325uL): ULong {
        var hash = start
        for (byte in text.encodeToByteArray()) {
            hash = hash xor (byte.toInt() and 0xFF).toULong()
            hash *= 0x100000001b3uL
        }
        return hash
    }

    private fun kind(kind: ChatMarkdownLineKind): String = when (kind) {
        ChatMarkdownLineKind.paragraph -> "p"
        ChatMarkdownLineKind.blank -> "b"
        is ChatMarkdownLineKind.heading -> "h${kind.level}"
    }

    private data class Fingerprint(val hash: String, val linked: Int, val bold: Int, val headings: Int, val disclosures: Int)

    /** 탐침 `digest` 모드와 글자 하나까지 같은 직렬화(줄 종류 · 조각 · 그린 글 · 미리보기 · 복사 표시). */
    private fun fingerprint(tokens: List<String>, seed: Long, count: Int): Fingerprint {
        val random = CMRandom(seed)
        var hash = 0xcbf29ce484222325uL
        var linked = 0
        var bold = 0
        var headings = 0
        var disclosures = 0
        repeat(count) {
            val length = 1 + random.below(40)
            val body = buildString { repeat(length) { append(tokens[random.below(tokens.size)]) } }
            val line = StringBuilder()
            for (l in ChatMarkdown.parse(body)) {
                line.append(kind(l.kind)).append('\u0001')
                for (s in l.spans) {
                    line.append(s.text).append('\u0002').append(if (s.isBold) "B" else "-").append('\u0002').append(s.link?.absoluteString ?: "").append('\u0003')
                    if (s.link != null) linked++
                    if (s.isBold) bold++
                }
                if (l.kind is ChatMarkdownLineKind.heading) headings++
                disclosures += ChatMarkdown.linkDisclosures(l).size
                line.append('\u0004')
            }
            val pieces = ChatMarkdownPieces.pieces(body)
            line.append(ChatMarkdownPieces.drawn(pieces)).append('\u0005').append(ChatMarkdown.plainPreview(body)).append('\u0006')
            val links = ChatMarkdownPieces.copyLinks(pieces)
            line.append(links.keys.sorted().joinToString(",") { "$it=${links.getValue(it).absoluteString}" }).append('\u0007')
            hash = fnv(line.toString(), hash)
        }
        return Fingerprint(hash.toString(16).padStart(16, '0'), linked, bold, headings, disclosures)
    }

    @Test
    fun randomCorpusFingerprintMatchesSwift() {
        val tokens = listOf(
            "*", "**", "_", "__", "~", "~~", "`", "``", "```", "[", "]", "(", ")", "](", "#", "## ", "> ", "- ", "1. ",
            " ", "\n", "\n", "가", "나", "a", "b", "7", ".", ":", "/", "!", "ㅋ", "🎉",
            "https://a.co", "http://b.io/x_y", "javascript:", "file:", "snake_case",
            "|", "%", "%41", "@", "{", "\\", "^", "'", "\"", "<", "?", "#", "=", "H", "HTTPS://", "www.", "\t", "\r\n", "\u200B", "\u0301",
            "\u00E9", "e\u0301", "\u037E", "[::1]", "x.com", "\u3000", "](https://", "https://", "intent://x", "[a](", "](https://a.co/x)",
        )
        // Swift 탐침: `probe digest tokens.json 3405691582 3000` → 244cdfbc62405f69 linked=2497 bold=108 headings=82 disclosures=632
        assertEquals(Fingerprint("244cdfbc62405f69", 2497, 108, 82, 632), fingerprint(tokens, 3405691582L, 3000))
    }

    @Test
    fun boldAndLinkHeavyCorpusFingerprintMatchesSwift() {
        val tokens = listOf(
            "**", "**", "**", "*", " ", " ", "가", "a", "# ", "### ", "\n", "[글](https://x.com/**)", "[a.com](https://a.com/)",
            "[www.a.com](https://www.a.com)", "https://a.com/**x", "[여기](https://evil.example/login)", "https://a.com", "[", "](", ")",
            "[b](https://x.com)", "H", "ttps://q.io", "_", "~~", "\u0301", "x",
        )
        // Swift 탐침: `probe digest tokens2.json 77 3000` → a1da1140ae824085 linked=13361 bold=4896 headings=351 disclosures=7157
        assertEquals(Fingerprint("a1da1140ae824085", 13361, 4896, 351, 7157), fingerprint(tokens, 77L, 3000))
    }

    @Test
    fun copyTextOverEveryRangeMatchesSwift() {
        val bodies = listOf(
            "**굵게** [자료](https://a.example/doc) 끝",
            "[a.example](https://a.example/doc) 봐",
            "https://a.example/doc 봐",
            "[가](https://a.example)와 [나](https://b.example)",
            "**[굵은 링크](https://a.example/x)**",
            "줄 하나\n[둘](https://b.example/y)",
            "## 제목 [링크 **굵게**](https://a.com/x|y)\n본문 https://b.com/%zz 끝",
            "[a](https://a.com)[b](https://a.com) [c.com](https://c.com/) 🎉",
        )
        var hash = 0xcbf29ce484222325uL
        var cuts = 0
        for (body in bodies) {
            val pieces = ChatMarkdownPieces.pieces(body)
            val drawn = ChatMarkdownPieces.drawn(pieces)
            val line = StringBuilder(body).append('\u0001').append(drawn).append('\u0002')
            for (start in 0 until drawn.length) {
                for (end in start + 1..drawn.length) {
                    if (drawn[start].isLowSurrogate() || (end < drawn.length && drawn[end].isLowSurrogate())) continue
                    line.append("$start,$end,${ChatMarkdownCopy.text(pieces, start, end)}").append('\u0003')
                    cuts++
                }
            }
            hash = fnv(line.toString(), hash)
        }
        // Swift 탐침 `probe copy` 출력(서로게이트를 가르는 구간 제외)의 지문.
        assertEquals("84e71e614126f158" to 2561, hash.toString(16).padStart(16, '0') to cuts)
    }
}
