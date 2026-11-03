// 원본: Sources/CheckCore/ChatMarkdown.swift @ 12624739(맥 0.3.74) + wt-phone-1017 99bd480d(호스트 퍼센트 인코딩은 링크가 아니다 — 1.0.17 검토 수리,
//       맥 다음 판에도 실린다). 판 7 Android 이식.
//
// 채팅 마크다운 해석기 — 대표 결정 "제목·굵게·링크만". 받는 것 셋: 줄 머리 `# ` · `## ` · `### ` 제목 · `**굵게**` · 링크(`[글](주소)` 와 맨
// http·https 주소). 나머지 문법(`*기울임*` · `~~취소~~` · `` `코드` `` · 글머리 · 번호 · 인용)은 **입력한 글자 그대로** 보인다.
// 여기는 해석만 한다(순수 함수). 그리는 것은 화면 갈래(ui ChatBubbleMarkdown)이고, 한 줄 자리(대화 목록 · 확성기 배너 · 신고 인용 · TalkBack)는
// [ChatMarkdown.plainPreview] 를 쓴다.
//
// ## 지키는 규약 넷(맥 머리 주석 그대로 — ChatMarkdownTest 가 하나씩 잰다)
//  ① 글자 보존: 빠지는 것은 제목 `#` 과 그 뒤 공백 · 짝이 맞은 `**` · 링크의 `[` `](주소)` 뿐이다. 닫히지 않은 `**` 는 원문 글자 그대로.
//  ② 한 번의 줄바꿈은 줄바꿈이다: 원문 한 줄 = 해석한 한 줄.
//  ③ 링크는 http·https 만: `javascript:` · `intent:` · `file:` · `content:` · 사용자 정의 스킴은 글자로만 남는다.
//  ④ 채팅 손버릇을 깨지 않는다: `-_-` · `>_<` · `*^^*` · `2*3*4` · `#해시태그` · `- 항목` · `> 인용` 은 그대로 글자다.
//
// ## Swift 와 같은 답을 내려고 하는 일(Kotlin/JVM 에서 갈릴 수 있는 곳 — 사례는 ChatMarkdownSwiftParityTest 가 못 박는다)
//  · 글자 단위는 Swift `Character`(확장 그래핌)다 — UTF-16 칸으로 훑으면 `#́ 제목`(결합 문자가 붙은 `#`)이 제목이 되고,
//    `)́` 의 닫는 괄호가 링크를 닫는다. [Graphemes.clusters] 로 자른다.
//  · `String ==` · `hasPrefix` · `contains` 는 Swift 에서 글자(그래핌) 단위 · 정준 동치다: `"www.a.com;"`(그리스 물음표)는 `"www.a.com;"` 와 같고,
//    `"https://́a.com"` 은 `"://"` 를 품지 않는다. [swiftEquals] · 그래핌 비교 함수가 그 몫이다.
//  · `URL(string:)` 은 Foundation 의 RFC 3986 파서다(macOS 14+ — 경로 · 질의 · 조각의 잘못된 글자를 퍼센트 인코딩한다). 주소는 ASCII 만 받으므로
//    그 동작을 [ChatURL] 이 글자 하나하나 맞춰 옮긴다(맥 실측 2026-11-03: 경로 `|` → `%7C`, 호스트 `|` → URL 없음, `[::1]` → 호스트 `::1`).
//    `java.net.URI` 는 쓰지 않는다 — 잘못된 글자에서 예외를 던지고(Foundation 은 인코딩한다) 대괄호 호스트 규칙이 다르다.
package com.yehsung.aingcheck.core.rules.text

/** 한 줄의 종류. **원문 한 줄 = 하나다**(규약 ②). */
sealed interface ChatMarkdownLineKind {
    data object paragraph : ChatMarkdownLineKind

    /** `# ` · `## ` · `### `(넷~여섯 개도 받는다 — 크기는 그리는 쪽이 3단계에서 멈춘다). */
    data class heading(val level: Int) : ChatMarkdownLineKind

    /** 빈 줄(공백만 있는 줄 포함 — 문단 간격). */
    data object blank : ChatMarkdownLineKind
}

/**
 * 누를 수 있는 주소(Swift `URL` 자리). **[ChatMarkdown.openableLink] 를 지난 http·https 만** 만들어진다(생성자는 모듈 안쪽).
 * [absoluteString] 은 Foundation `URL.absoluteString` 과 같은 글자다(경로 · 질의 · 조각의 잘못된 글자는 퍼센트 인코딩 — 브라우저에 넘기는 글자).
 * [host] 는 Foundation `host(percentEncoded: true)` 와 같다(대괄호 호스트는 괄호 안쪽 · 대소문자는 원문 그대로 · `%` 는 없다).
 * 같음은 Swift `URL ==` 처럼 [absoluteString] 으로 잰다.
 */
class ChatLink internal constructor(val absoluteString: String, val host: String) {
    override fun equals(other: Any?): Boolean = other is ChatLink && other.absoluteString == absoluteString
    override fun hashCode(): Int = absoluteString.hashCode()
    override fun toString(): String = absoluteString
}

/** 같은 굵기 · 같은 링크로 이어지는 글자 한 덩어리. */
data class ChatMarkdownSpan(
    val text: String,
    /** `**굵게**` 안의 글자. 제목 줄은 이 값과 상관없이 그리는 쪽이 굵게 그린다. */
    val isBold: Boolean = false,
    /** 누르면 열 주소. **http·https 뿐이다**([ChatMarkdown.openableLink] 를 지난 것만 여기 온다). */
    val link: ChatLink? = null,
)

/** 해석한 한 줄. */
data class ChatMarkdownLine(val kind: ChatMarkdownLineKind, val spans: List<ChatMarkdownSpan> = emptyList()) {
    /** 이 줄의 해석 글자(조각들). 그리는 쪽이 덧붙이는 것은 링크 호스트 꼬리표 하나뿐이다([ChatMarkdown.linkDisclosures]). */
    val text: String get() = spans.joinToString("") { it.text }
}

object ChatMarkdown {
    // ---------------------------------------------------------------- 줄 — 제목만 줄 머리 기호다

    /**
     * 본문 → 줄들. 줄바꿈은 Swift `Character.isNewline` 전부로 자른다(`"\r\n"` 은 한 글자 · `\u000B` `\u000C` `\u0085` ` ` ` ` 도 줄바꿈).
     * 빈 말풍선은 생기지 않는다: 공백 아닌 글자가 있는 줄은 해석 글자도 비지 않는다.
     */
    fun parse(body: String): List<ChatMarkdownLine> {
        val clusters = Graphemes.clusters(body)
        val out = ArrayList<ChatMarkdownLine>()
        var start = 0
        for (index in clusters.indices) {
            if (SwiftChar.isNewline(clusters[index])) {
                out += line(clusters.subList(start, index))
                start = index + 1
            }
        }
        out += line(clusters.subList(start, clusters.size))
        return out
    }

    /** 한 줄. 줄 머리 `#` 은 **뒤에 공백이 있어야** 제목이다(규약 ④ — `#해시태그`). */
    internal fun line(chars: List<String>): ChatMarkdownLine {
        if (chars.all(SwiftChar::whiteSpace)) return ChatMarkdownLine(ChatMarkdownLineKind.blank)
        val parser = ChatInlineParser(chars)
        val hashes = chars.takeWhile { it == "#" }.size
        if (hashes in 1..6) {
            val start = contentStart(chars, hashes)
            if (start != null) return ChatMarkdownLine(ChatMarkdownLineKind.heading(hashes), parser.spans(start, chars.size))
        }
        return ChatMarkdownLine(ChatMarkdownLineKind.paragraph, parser.spans(0, chars.size))
    }

    /** [after] 자리부터 공백(` ` · 탭)이 **한 칸 이상** 있고 그 뒤에 글자가 있으면 그 글자 자리. 아니면 null(기호가 아니다). */
    internal fun contentStart(chars: List<String>, after: Int): Int? {
        var index = after
        while (index < chars.size && (chars[index] == " " || chars[index] == "\t")) index++
        if (index <= after || index >= chars.size) return null
        return index
    }

    // ---------------------------------------------------------------- 링크 — http·https 만(규약 ③)

    /**
     * 누를 수 있는 주소면 [ChatLink], 아니면 null. **링크를 만드는 모든 길이 이 한 함수를 지난다**(맨 주소 · `[글](주소)`).
     * 공백 · 제어 문자 · 비ASCII 가 섞인 주소는 받지 않는다(보이는 글자와 여는 주소가 달라지는 자동 인코딩을 거치지 않는다).
     * 호스트의 퍼센트 인코딩은 [ChatURL] 이 막는다(`n%D0%B0ver.com` 은 키릴 문자 호스트다 — 1.0.17 검토).
     */
    fun openableLink(raw: String): ChatLink? {
        if (raw.isEmpty() || raw.any { it.code <= 0x20 || it.code >= 0x7F }) return null
        return ChatURL.openable(raw)
    }

    /**
     * 열어도 되는 주소인가 — **여는 자리에서 한 번 더** 묻는 문(Swift `isOpenable(_ url:)`). 말풍선이 링크를 누를 때 · TalkBack 동작이 열 때
     * 이 함수를 지난다(해석이 이미 걸렀어도 다시 본다 — 두 겹이어야 한쪽이 풀린 날에도 `javascript:` · `intent:` 가 안 열린다).
     * 스킴 http·https · 호스트가 있고 · 호스트에 `%` 가 없고 · 사용자 정보(`…@`)가 없다.
     */
    fun isOpenable(address: String): Boolean = openableLink(address) != null

    /**
     * `[https://은행.com](https://딴곳.com)` 처럼 **글이 주소 흉내를 내는데 실제 주소와 다르면** 링크로 만들지 않는다.
     * `contains("://")` · `hasPrefix("www.")` 는 Swift 처럼 글자(그래핌) 단위다.
     */
    internal fun isDisguisedAddress(label: String, destination: String): Boolean {
        val shown = TextScalars.trimmingWhitespaces(label).lowercase()
        val clusters = Graphemes.clusters(shown)
        if (!clustersContain(clusters, COLON_SLASH_SLASH) && !clustersStartWith(clusters, WWW_DOT)) return false
        // 스킴 · 끝 빗금만 다른 것은 같은 주소다.
        return !swiftEquals(comparableAddress(shown), comparableAddress(destination))
    }

    /** 주소 비교용 모양: 소문자 · 앞뒤 공백 없음 · `http(s)://` 없음 · 끝 `/` 없음(모두 Swift 처럼 글자 단위). */
    fun comparableAddress(text: String): String {
        var clusters = Graphemes.clusters(TextScalars.trimmingWhitespaces(text).lowercase())
        for (scheme in SCHEMES) {
            if (clustersStartWith(clusters, scheme)) {
                clusters = clusters.subList(scheme.size, clusters.size)
                break
            }
        }
        if (clusters.lastOrNull() == "/") clusters = clusters.subList(0, clusters.size - 1)
        return clusters.joinToString("")
    }

    /**
     * `[글](주소)` 링크 뒤에 **실제로 열리는 곳의 호스트**를 붙여 보인다(말풍선에는 주소를 볼 길이 없다). 글이 주소 그 자체이거나 호스트와 같을 때만
     * 생략한다. 반환: 줄의 조각 위치 → 그 조각 뒤에 붙일 호스트(한 링크가 여러 조각이면 마지막 조각 뒤 한 번).
     */
    fun linkDisclosures(line: ChatMarkdownLine): Map<Int, String> {
        val result = LinkedHashMap<Int, String>()
        val label = StringBuilder()
        for ((index, span) in line.spans.withIndex()) {
            val url = span.link
            if (url == null) {
                label.clear()
                continue
            }
            label.append(span.text)
            val nextLink = line.spans.getOrNull(index + 1)?.link
            if (nextLink == url) continue
            disclosedHost(label.toString(), url)?.let { result[index] = it }
            label.clear()
        }
        return result
    }

    /** 한 링크의 글과 주소 → 따로 보일 호스트(null = 글이 이미 그것을 말한다). 호스트는 **인코딩된 그대로** 읽는다(풀면 닮은꼴이 진짜처럼 찍힌다). */
    fun disclosedHost(label: String, url: ChatLink): String? {
        val host = url.host.lowercase()
        if (host.isEmpty()) return null
        val shown = comparableAddress(label)
        if (swiftEquals(shown, comparableAddress(url.absoluteString)) || swiftEquals(shown, host)) return null
        return host
    }

    // ---------------------------------------------------------------- 한 줄 미리보기

    /**
     * 글자만 들어가는 한 줄 자리의 문구 — 받는 세 문법의 기호만 벗기고 줄바꿈은 공백 하나로.
     * ★ **이모티콘 규칙이 먼저다**([AingStickerText.preview]) — 토큰 본문은 "아잉이 기쁨"으로 바뀐 뒤에 여기를 지난다.
     * 평범한 한 줄 본문은 **글자 하나도** 바뀌지 않는다(앞뒤 공백만 걷는다).
     */
    fun plainPreview(body: String): String =
        parse(AingStickerText.preview(body))
            .map { TextScalars.trimmingWhitespaces(it.text) }
            .filter { it.isNotEmpty() }
            .joinToString(" ")

    // ---------------------------------------------------------------- Swift 글자 비교

    private val COLON_SLASH_SLASH = listOf(":", "/", "/")
    private val WWW_DOT = listOf("w", "w", "w", ".")
    private val SCHEMES = listOf(listOf("h", "t", "t", "p", "s", ":", "/", "/"), listOf("h", "t", "t", "p", ":", "/", "/"))

    /** Swift `String ==` — 정준 동치(NFC 로 접은 뒤 같다). */
    internal fun swiftEquals(a: String, b: String): Boolean = a == b || TextNormalization.nfc(a) == TextNormalization.nfc(b)

    /** 글자(그래핌) 단위 hasPrefix. 비교 대상(`www.` · `https://`)의 글자는 정준 동치 짝이 없는 ASCII 라 글자 그대로 견준다. */
    private fun clustersStartWith(clusters: List<String>, prefix: List<String>): Boolean =
        clusters.size >= prefix.size && prefix.indices.all { clusters[it] == prefix[it] }

    /** 글자(그래핌) 단위 contains. */
    private fun clustersContain(clusters: List<String>, needle: List<String>): Boolean =
        (0..clusters.size - needle.size).any { start -> needle.indices.all { clusters[start + it] == needle[it] } }
}

/** Swift `Character` 성질(이 해석기가 쓰는 몫). 글자 하나 = 그래핌 하나(문자열). */
internal object SwiftChar {
    private fun first(cluster: String): Int = if (cluster.isEmpty()) -1 else cluster.codePointArray()[0]

    /** `Character.isWhitespace` — 첫 스칼라의 White_Space 속성. */
    fun whiteSpace(cluster: String): Boolean = first(cluster).let { it >= 0 && TextScalars.isWhiteSpaceProperty(it) }

    /** `Character.isNewline` — 첫 스칼라가 LF~CR · NEL · LS · PS(`"\r\n"` 도). */
    fun isNewline(cluster: String): Boolean = when (first(cluster)) {
        in 0x0A..0x0D, 0x85, 0x2028, 0x2029 -> true
        else -> false
    }

    /** `Character.asciiValue` — `"\r\n"` 은 LF, 스칼라 하나짜리 ASCII 만 값이 있다. */
    fun asciiValue(cluster: String): Int? {
        if (cluster == "\r\n") return 0x0A
        if (cluster.length != 1 || cluster[0].code >= 0x80) return null
        return cluster[0].code
    }

    /** 영문 · 숫자인 ASCII 글자인가(Swift `isASCII && (isLetter || isNumber)`). */
    fun isASCIIAlphanumeric(cluster: String): Boolean {
        val value = asciiValue(cluster) ?: return false
        return value in 0x30..0x39 || value in 0x41..0x5A || value in 0x61..0x7A
    }
}

/**
 * 한 줄 안의 꾸밈(Swift `ChatInlineParser`). 글자 배열 위를 왼쪽부터 한 번 훑고, 여는 기호를 만나면 **같은 줄 안에서** 닫는 짝을 찾는다.
 * 짝이 없으면 그 기호는 글자다(규약 ①). 우선순위: 링크 → 맨 주소 → 굵게(주소 안의 `*` 를 굵게 짝으로 쓰지 않는다).
 */
internal class ChatInlineParser(private val chars: List<String>) {

    fun spans(start: Int, end: Int, isBold: Boolean = false, link: ChatLink? = null, allowsLinks: Boolean = true): List<ChatMarkdownSpan> {
        val out = ArrayList<ChatMarkdownSpan>()
        val plain = StringBuilder()
        fun flush() {
            if (plain.isEmpty()) return
            out += ChatMarkdownSpan(plain.toString(), isBold, link)
            plain.clear()
        }

        var index = start
        while (index < end) {
            val char = chars[index]

            if (allowsLinks && char == "[") {
                val shape = linkShape(index, end)
                if (shape != null) {
                    val label = join(shape.labelStart, shape.labelEnd)
                    val url = if (shape.labelEnd > shape.labelStart) ChatMarkdown.openableLink(shape.destination) else null
                    if (url != null && !ChatMarkdown.isDisguisedAddress(label, shape.destination)) {
                        flush()
                        out += spans(shape.labelStart, shape.labelEnd, isBold, url, allowsLinks = false)
                    } else {
                        // 모양은 링크인데 열 수 없는 주소 · 빈 글 · 주소 흉내 글 — **통째로 원문 글자**다(안쪽을 따로 해석하지 않는다).
                        for (i in index until shape.next) plain.append(chars[i])
                    }
                    index = shape.next
                    continue
                }
            }

            if (allowsLinks && (char == "h" || char == "H")) {
                val urlEnd = bareURLEnd(index, end)
                if (urlEnd != null) {
                    val raw = join(index, urlEnd)
                    val url = ChatMarkdown.openableLink(raw)
                    if (url != null) {
                        flush()
                        out += ChatMarkdownSpan(raw, isBold, url)
                        index = urlEnd
                        continue
                    }
                }
            }

            if (char == "*") {
                val close = boldClose(index, end, allowsLinks)
                if (close != null) {
                    flush()
                    out += spans(index + 2, close, isBold = true, link = link, allowsLinks = allowsLinks)
                    index = close + 2
                    continue
                }
            }

            plain.append(char)
            index++
        }
        flush()
        return out
    }

    private fun join(start: Int, end: Int): String {
        val sb = StringBuilder()
        for (i in start until end) sb.append(chars[i])
        return sb.toString()
    }

    // ---------------------------------------------------------------- 링크

    class LinkShape(val labelStart: Int, val labelEnd: Int, val destination: String, val next: Int)

    /**
     * `[글](주소)` 모양이면 (글 자리, 주소 글자, 다음 자리). 글 안에 `[` 가 또 있거나 · `](` 가 아니거나 · 주소에 공백이 있거나 ·
     * 괄호가 안 닫히면 null(모양이 아니다 — `[` 는 글자로 남는다). 주소 안 괄호는 짝을 센다(`https://ko.wikipedia.org/wiki/Foo_(bar)`).
     */
    fun linkShape(index: Int, end: Int): LinkShape? {
        var close = index + 1
        while (close < end && chars[close] != "]") {
            if (chars[close] == "[") return null
            close++
        }
        if (close + 1 >= end || chars[close + 1] != "(") return null
        val destinationStart = close + 2
        var depth = 0
        var cursor = destinationStart
        while (cursor < end) {
            val char = chars[cursor]
            if (SwiftChar.whiteSpace(char)) return null
            if (char == "(") {
                depth++
            } else if (char == ")") {
                if (depth == 0) break
                depth--
            }
            cursor++
        }
        if (cursor >= end || cursor <= destinationStart) return null
        return LinkShape(index + 1, close, join(destinationStart, cursor), cursor + 1)
    }

    /**
     * 맨 주소(`http://` · `https://` 로 시작)의 끝 자리. 아니면 null.
     *  · 앞 글자가 영문 · 숫자면 단어 한가운데라 주소가 아니다(`xhttps://…`). 한글 뒤는 받는다(`여기https://…`).
     *  · 주소는 ASCII 에서 멈춘다(`https://a.com에서` 의 `에서` 는 주소가 아니다).
     *  · 꼬리 문장부호는 주소가 아니다(`…a.com.` · `(https://a.com)` 의 짝 없는 닫는 괄호 · `**https://a.com**` · `https://a.com~~`).
     */
    fun bareURLEnd(index: Int, end: Int): Int? {
        if (index > 0 && SwiftChar.isASCIIAlphanumeric(chars[index - 1])) return null
        val schemeLength = when {
            hasPrefixIgnoringCase("https://", index, end) -> 8
            hasPrefixIgnoringCase("http://", index, end) -> 7
            else -> return null
        }
        val bodyStart = index + schemeLength
        var cursor = bodyStart
        while (cursor < end && isURLCharacter(chars[cursor])) cursor++
        while (cursor > bodyStart) {
            val last = chars[cursor - 1]
            if (last.length == 1 && last[0] in TRAILING_PUNCTUATION) {
                cursor--
            } else if (last == ")" && count("(", index, cursor) < count(")", index, cursor)) {
                cursor--
            } else if (last == "]" && count("[", index, cursor) < count("]", index, cursor)) {
                cursor--
            } else {
                break
            }
        }
        return if (cursor > bodyStart) cursor else null
    }

    private fun hasPrefixIgnoringCase(prefix: String, index: Int, end: Int): Boolean {
        if (index + prefix.length > end) return false
        for (offset in prefix.indices) if (chars[index + offset].lowercase() != prefix[offset].toString()) return false
        return true
    }

    private fun count(char: String, start: Int, end: Int): Int {
        var n = 0
        for (i in start until end) if (chars[i] == char) n++
        return n
    }

    // ---------------------------------------------------------------- 굵게

    /**
     * [index] 의 `**` 를 닫는 `**` 의 자리. 짝이 없으면 null — 그 `*` 는 글자다(규약 ①).
     *  · 여는 `**` 바로 뒤가 공백이면 여는 기호가 아니다. 닫는 `**` 바로 앞이 공백이면 닫는 기호가 아니다.
     *  · 단어 안에서도 켜진다(`이건**중요**해`). `*` 가 셋 이상 이어진 닫는 묶음은 마지막 둘이 짝이다(`***둘 다***` → 굵은 `*둘 다*`).
     *  · 닫는 짝은 **링크 밖에서만** 찾는다(사이에 든 링크 모양 · 맨 주소는 건너뛴다 — [linkSkip]).
     */
    fun boldClose(index: Int, end: Int, allowsLinks: Boolean = true): Int? {
        val first = index + 2
        if (first >= end || chars[index + 1] != "*" || SwiftChar.whiteSpace(chars[first])) return null
        var cursor = first
        while (cursor < end) {
            if (allowsLinks) {
                val next = linkSkip(cursor, end)
                if (next != null) {
                    cursor = next
                    continue
                }
            }
            // 여는 `**` 바로 뒤 글자(first)는 닫는 묶음의 시작이 아니다(`****` 는 글자 · `***둘 다***` 의 셋째 `*` 는 안쪽 글자).
            if (cursor <= first || chars[cursor] != "*") {
                cursor++
                continue
            }
            val run = runLength(cursor, end)
            if (run >= 2 && !SwiftChar.whiteSpace(chars[cursor - 1])) return cursor + run - 2
            cursor += run
        }
        return null
    }

    /** [index] 에서 링크가 시작하면 그 링크가 끝난 자리(링크 모양은 열 수 있든 없든 · 맨 주소는 링크가 될 때만). 아니면 null. */
    private fun linkSkip(index: Int, end: Int): Int? {
        val char = chars[index]
        if (char == "[") linkShape(index, end)?.let { return it.next }
        if (char == "h" || char == "H") {
            val urlEnd = bareURLEnd(index, end)
            if (urlEnd != null && ChatMarkdown.openableLink(join(index, urlEnd)) != null) return urlEnd
        }
        return null
    }

    private fun runLength(index: Int, end: Int): Int {
        var cursor = index
        while (cursor < end && chars[cursor] == chars[index]) cursor++
        return cursor - index
    }

    companion object {
        private const val TRAILING_PUNCTUATION = ".,;:!?'\"*_~"

        /** 주소 글자: ASCII 0x21~0x7E 중 `<` `>` `"` `` ` `` 가 아닌 것(스칼라 하나짜리 글자만). */
        fun isURLCharacter(char: String): Boolean {
            val value = SwiftChar.asciiValue(char) ?: return false
            if (value <= 0x20 || value >= 0x7F) return false
            return char[0] !in "<>\"`"
        }
    }
}

/**
 * Foundation `URL(string:)` + `ChatMarkdown.isOpenable` 의 몫을 **ASCII 주소에 한해** 옮긴 것(맥 Darwin 27 실측 2026-11-03 — 표는
 * ChatMarkdownSwiftParityTest). 열 수 있는 주소일 때만 값을 낸다.
 *
 *  · 스킴: `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"` 가 아니면 상대 주소(스킴 없음) — 열 수 없다. 대소문자 무관 http·https 만.
 *  · `//` 가 없으면 호스트가 없다(`https:a.com` · `https:/a.com`). 권한부는 첫 `/` `?` `#` 앞까지.
 *  · 권한부에 `@` 가 있으면 사용자 정보다(Foundation: user 가 nil 이 아니거나 URL 이 없다) — 열 수 없다.
 *  · 대괄호 호스트 `[…]`: 안쪽은 unreserved · sub-delims · `:` 만(그 밖은 URL 없음), `%` 는 `%25` 로 인코딩되어 호스트에 `%` 가 남는다 — 열 수 없다.
 *    호스트 값은 괄호 안쪽(`[::1]` → `::1` · `[a.com]` → `a.com`). 괄호 뒤는 끝이거나 `:숫자*`.
 *  · 보통 호스트: unreserved · sub-delims · 올바른 `%XX` 만(그 밖 · 외톨이 `%` 는 URL 없음). `%XX` 가 있으면 열 수 없다(1.0.17 검토).
 *    포트는 숫자뿐(비어도 된다 · 자리 수 제한 없음).
 *  · 경로 · 질의 · 조각: 잘못된 글자(`"` `<` `>` `[` `\` `]` `^` `` ` `` `{` `|` `}` · 외톨이 `%` · 조각 안의 `#`)가 **하나도 없으면** 원문 그대로가
 *    absoluteString 이다. 하나라도 있으면 Foundation 은 주소를 조각에서 다시 짓는다("인코딩 갈래" — 맥 실측):
 *      - 잘못된 글자가 있는 조각(경로 · 질의 · 조각 각각)만 인코딩한다. 그 조각 안의 `%` 는 **올바른 `%41` 까지** `%2541` 로 바뀐다.
 *        잘못된 글자가 없는 조각은 그대로다(`/%41?q=|` → `/%41?q=%7C`).
 *      - 포트는 정수로 다시 쓴다: 빈 포트는 `:` 째 빠지고(`a.com:/x|` → `a.com/x%7C`) · 앞 0 은 지워지고(`:080` → `:80`) · Int64 를 넘으면 빠진다.
 *      - 스킴 · 호스트(대괄호 포함)의 대소문자는 원문 그대로 · 빈 질의 `?` · 빈 조각 `#` 표시도 남는다.
 */
internal object ChatURL {
    private const val SUB_DELIMS = "!$&'()*+,;="
    private const val ENCODED_IN_TAIL = "\"<>[\\]^`{|}"

    private fun isAlpha(c: Char) = c in 'a'..'z' || c in 'A'..'Z'
    private fun isDigit(c: Char) = c in '0'..'9'
    private fun isHex(c: Char) = isDigit(c) || c in 'a'..'f' || c in 'A'..'F'
    private fun isUnreserved(c: Char) = isAlpha(c) || isDigit(c) || c == '-' || c == '.' || c == '_' || c == '~'
    private fun isSubDelim(c: Char) = c in SUB_DELIMS

    /** 권한부를 가른 것. [hostPart] 는 원문의 호스트 글자(대괄호 포함), [host] 는 Foundation `host(percentEncoded: true)`, [port] 는 `:` 뒤 숫자(없으면 null). */
    private class Authority(val hostPart: String, val host: String, val port: String?)

    /** [raw] 는 ASCII 0x21~0x7E 뿐이다(부르는 쪽 [ChatMarkdown.openableLink] 가 거른다). */
    fun openable(raw: String): ChatLink? {
        val colon = raw.indexOf(':')
        if (colon <= 0) return null
        val scheme = raw.substring(0, colon)
        if (!isAlpha(scheme[0]) || !scheme.all { isAlpha(it) || isDigit(it) || it == '+' || it == '-' || it == '.' }) return null
        val lower = scheme.lowercase()
        if (lower != "http" && lower != "https") return null
        val rest = raw.substring(colon + 1)
        if (!rest.startsWith("//")) return null
        val afterSlashes = rest.substring(2)
        val authorityEnd = afterSlashes.indexOfFirst { it == '/' || it == '?' || it == '#' }.let { if (it < 0) afterSlashes.length else it }
        val authorityText = afterSlashes.substring(0, authorityEnd)
        if ('@' in authorityText) return null
        val authority = authority(authorityText) ?: return null
        if (authority.host.isEmpty() || '%' in authority.host) return null
        return ChatLink(absoluteString(raw, scheme, authority, afterSlashes.substring(authorityEnd)), authority.host)
    }

    /** 권한부 → 호스트 · 포트. URL 이 서지 않는 권한부면 null. */
    private fun authority(text: String): Authority? {
        if (text.startsWith("[")) {
            val close = text.indexOf(']')
            if (close < 0) return null
            val inside = text.substring(1, close)
            if (!inside.all { isUnreserved(it) || isSubDelim(it) || it == ':' || it == '%' }) return null
            val port = port(text.substring(close + 1)) ?: return null
            // `%` 는 Foundation 이 `%25` 로 인코딩해 호스트에 `%` 를 남긴다 — 부르는 쪽이 열 수 없다고 본다.
            return Authority(text.substring(0, close + 1), inside, port.ifEmpty { null }?.drop(1))
        }
        val portStart = text.indexOf(':')
        val host = if (portStart < 0) text else text.substring(0, portStart)
        val port = if (portStart < 0) "" else port(text.substring(portStart)) ?: return null
        var i = 0
        while (i < host.length) {
            val c = host[i]
            if (c == '%') {
                if (i + 2 >= host.length || !isHex(host[i + 1]) || !isHex(host[i + 2])) return null
                i += 3
                continue
            }
            if (!isUnreserved(c) && !isSubDelim(c)) return null
            i++
        }
        return Authority(host, host, port.ifEmpty { null }?.drop(1))
    }

    /** 호스트 뒤 꼬리: 비었거나 `:` + 숫자* — 그 꼬리를 그대로 돌려준다. 아니면 null. */
    private fun port(tail: String): String? {
        if (tail.isEmpty()) return tail
        if (tail[0] != ':' || !tail.substring(1).all(::isDigit)) return null
        return tail
    }

    /** 조각 하나에 잘못된 글자가 있는가(외톨이 `%` 포함 · 조각이면 `#` 도). */
    private fun needsEncoding(component: String, isFragment: Boolean): Boolean {
        for ((i, c) in component.withIndex()) {
            if (c in ENCODED_IN_TAIL || (isFragment && c == '#')) return true
            if (c == '%' && (i + 2 >= component.length || !isHex(component[i + 1]) || !isHex(component[i + 2]))) return true
        }
        return false
    }

    /** 인코딩 갈래의 조각: 잘못된 글자와 **모든** `%` 를 대문자 `%XX` 로. */
    private fun encodeAll(component: String, isFragment: Boolean): String {
        val out = StringBuilder(component.length + 8)
        for (c in component) {
            if (c in ENCODED_IN_TAIL || c == '%' || (isFragment && c == '#')) out.append(percent(c)) else out.append(c)
        }
        return out.toString()
    }

    /** Foundation `URL.absoluteString` — 잘못된 글자가 없으면 원문, 있으면 조각에서 다시 짓는다(머리 주석). */
    private fun absoluteString(raw: String, scheme: String, authority: Authority, tail: String): String {
        val hash = tail.indexOf('#')
        val beforeFragment = if (hash < 0) tail else tail.substring(0, hash)
        val fragment = if (hash < 0) null else tail.substring(hash + 1)
        val question = beforeFragment.indexOf('?')
        val path = if (question < 0) beforeFragment else beforeFragment.substring(0, question)
        val query = if (question < 0) null else beforeFragment.substring(question + 1)
        val pathBad = needsEncoding(path, isFragment = false)
        val queryBad = query != null && needsEncoding(query, isFragment = false)
        val fragmentBad = fragment != null && needsEncoding(fragment, isFragment = true)
        if (!pathBad && !queryBad && !fragmentBad) return raw
        val out = StringBuilder(raw.length + 16)
        out.append(scheme).append("://").append(authority.hostPart)
        authority.port?.toLongOrNull()?.let { out.append(':').append(it) }
        out.append(if (pathBad) encodeAll(path, false) else path)
        if (query != null) out.append('?').append(if (queryBad) encodeAll(query, false) else query)
        if (fragment != null) out.append('#').append(if (fragmentBad) encodeAll(fragment, true) else fragment)
        return out.toString()
    }

    private fun percent(c: Char): String {
        val hex = "0123456789ABCDEF"
        return "%" + hex[c.code shr 4] + hex[c.code and 0xF]
    }
}
