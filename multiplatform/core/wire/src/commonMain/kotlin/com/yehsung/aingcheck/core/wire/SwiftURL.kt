// 원본: Swift Foundation `URL(string:)`(macOS 14·iOS 17 이후 — encodingInvalidCharacters 기본 참) · 서비스의 `avatarUrl.flatMap { URL(string: $0) }` 10곳 @ 1b8260d
package com.yehsung.aingcheck.core.wire

/**
 * Swift `URL` 의 Kotlin 꼴 — 서비스가 서버 글자(아바타 주소)를 **URL 로 거르는** 규칙을 한 곳에 둔다(검증 지적: Kotlin 이 글자를 그대로
 * 들고 있어 `""` 가 null 이 아니고 공백이 퍼센트 인코딩되지 않았다).
 *
 * 규칙(swift-foundation 의 RFC 3986 파서 실측 — 골든 wire/rules `url-*` 가 표로 잠근다):
 *  · 빈 글자 → null.
 *  · `:`·`/`·`?`·`#` 중 처음 오는 것이 `:` 이면 그 앞이 scheme 이다. 비었으면 빈 scheme, ALPHA *(ALPHA/DIGIT/+/-/.) 가 아니면 null
 *    (앞 공백·BOM 이 붙은 주소가 null 인 까닭).
 *  · `//` 뒤는 authority: 마지막 `@` 앞이 userinfo(잘못된 글자는 인코딩), 호스트는 `[...]`(unreserved·sub-delims·`:` 만) 또는
 *    reg-name(unreserved·sub-delims·올바른 %XX 만 — 다른 글자가 있으면 **null**, 인코딩하지 않는다), `:` 뒤 포트는 숫자만(비어도 된다).
 *  · 경로·쿼리·조각은 허용 글자(pchar + `/`, 쿼리·조각은 `?` 도) 밖의 글자를 UTF-8 %XX(대문자)로 바꾼다. 올바른 %XX 는 그대로,
 *    짝이 안 맞는 `%` 는 `%25`. 조각 안의 `#` 도 인코딩한다.
 *  · 알려진 갈림: 아스키가 아닌 호스트(Apple 은 IDNA punycode 로 바꾼다 — 여기선 null). 골든 knownDivergence 로 잠근다.
 */
class SwiftURL private constructor(val absoluteString: String) {
    override fun equals(other: Any?): Boolean = other is SwiftURL && other.absoluteString == absoluteString
    override fun hashCode(): Int = absoluteString.hashCode()
    override fun toString(): String = absoluteString

    companion object {
        /** Swift `URL(string:)?` — 못 만들면 null. */
        fun parse(text: String?): SwiftURL? = text?.let { build(it) }?.let(::SwiftURL)

        private const val UNRESERVED_MARKS = "-._~"
        private const val SUB_DELIMS = "!$&'()*+,;="

        private fun isAlpha(c: Char) = c in 'a'..'z' || c in 'A'..'Z'
        private fun isDigit(c: Char) = c in '0'..'9'
        private fun isHex(c: Char) = isDigit(c) || c in 'a'..'f' || c in 'A'..'F'
        private fun isUnreserved(c: Char) = isAlpha(c) || isDigit(c) || c in UNRESERVED_MARKS
        private fun isSubDelim(c: Char) = c in SUB_DELIMS
        private fun isPchar(c: Char) = isUnreserved(c) || isSubDelim(c) || c == ':' || c == '@'

        private fun build(s: String): String? {
            if (s.isEmpty()) return null
            val out = StringBuilder()
            var rest = s
            val firstSpecial = s.indexOfFirst { it == ':' || it == '/' || it == '?' || it == '#' }
            if (firstSpecial >= 0 && s[firstSpecial] == ':') {
                val scheme = s.substring(0, firstSpecial)
                if (scheme.isNotEmpty() && !(isAlpha(scheme[0]) && scheme.all { isAlpha(it) || isDigit(it) || it in "+-." })) return null
                out.append(scheme).append(':')
                rest = s.substring(firstSpecial + 1)
            }
            if (rest.startsWith("//")) {
                val afterSlashes = rest.substring(2)
                val end = afterSlashes.indexOfFirst { it == '/' || it == '?' || it == '#' }.let { if (it < 0) afterSlashes.length else it }
                val authority = authority(afterSlashes.substring(0, end)) ?: return null
                out.append("//").append(authority)
                rest = afterSlashes.substring(end)
            }
            val queryAt = rest.indexOf('?').let { if (it < 0) Int.MAX_VALUE else it }
            val fragmentAt = rest.indexOf('#').let { if (it < 0) Int.MAX_VALUE else it }
            val pathEnd = minOf(queryAt, fragmentAt, rest.length)
            out.append(encode(rest.substring(0, pathEnd)) { isPchar(it) || it == '/' })
            rest = rest.substring(pathEnd)
            if (rest.startsWith("?")) {
                val qEnd = rest.indexOf('#').let { if (it < 0) rest.length else it }
                out.append('?').append(encode(rest.substring(1, qEnd)) { isPchar(it) || it == '/' || it == '?' })
                rest = rest.substring(qEnd)
            }
            if (rest.startsWith("#")) {
                out.append('#').append(encode(rest.substring(1)) { isPchar(it) || it == '/' || it == '?' })
            }
            return out.toString()
        }

        private fun authority(a: String): String? {
            val at = a.lastIndexOf('@')
            val userinfo = if (at >= 0) a.substring(0, at) else null
            val hostPort = if (at >= 0) a.substring(at + 1) else a
            val host: String
            val port: String?
            if (hostPort.startsWith("[")) {
                val close = hostPort.indexOf(']')
                if (close < 0) return null
                host = hostPort.substring(0, close + 1)
                if (!host.substring(1, host.length - 1).all { isUnreserved(it) || isSubDelim(it) || it == ':' }) return null
                val tail = hostPort.substring(close + 1)
                port = when {
                    tail.isEmpty() -> null
                    tail.startsWith(":") -> tail.substring(1)
                    else -> return null
                }
            } else {
                val colon = hostPort.lastIndexOf(':')
                host = if (colon >= 0) hostPort.substring(0, colon) else hostPort
                port = if (colon >= 0) hostPort.substring(colon + 1) else null
                if (!validRegName(host)) return null
            }
            if (port != null && !port.all(::isDigit)) return null
            val out = StringBuilder()
            if (userinfo != null) out.append(encode(userinfo) { isUnreserved(it) || isSubDelim(it) || it == ':' }).append('@')
            out.append(host)
            if (port != null) out.append(':').append(port)
            return out.toString()
        }

        private fun validRegName(host: String): Boolean {
            var i = 0
            while (i < host.length) {
                val c = host[i]
                when {
                    c == '%' -> {
                        if (i + 2 >= host.length || !isHex(host[i + 1]) || !isHex(host[i + 2])) return false
                        i += 3
                        continue
                    }
                    isUnreserved(c) || isSubDelim(c) -> Unit
                    else -> return false
                }
                i++
            }
            return true
        }

        /** 허용 밖 글자를 UTF-8 %XX 로. 올바른 %XX 는 그대로, 짝 없는 `%` 는 %25. */
        private fun encode(part: String, allowed: (Char) -> Boolean): String {
            val out = StringBuilder()
            var i = 0
            while (i < part.length) {
                val c = part[i]
                if (c == '%' && i + 2 < part.length && isHex(part[i + 1]) && isHex(part[i + 2])) {
                    out.append(part, i, i + 3)
                    i += 3
                    continue
                }
                if (c.code < 0x80 && c != '%' && allowed(c)) {
                    out.append(c)
                    i++
                    continue
                }
                val cpLen = if (c.isHighSurrogate() && i + 1 < part.length && part[i + 1].isLowSurrogate()) 2 else 1
                for (b in part.substring(i, i + cpLen).encodeToByteArray()) {
                    val v = b.toInt() and 0xFF
                    out.append('%').append(HEX[v shr 4]).append(HEX[v and 0xF])
                }
                i += cpLen
            }
            return out.toString()
        }

        private const val HEX = "0123456789ABCDEF"
    }
}
