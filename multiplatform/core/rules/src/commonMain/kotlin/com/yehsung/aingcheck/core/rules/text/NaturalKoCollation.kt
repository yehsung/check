// 원본: String.localizedStandardCompare — Sources/CheckCore/SupabaseWorkModels.swift:281,603,1556,3116 · GomokuStore.swift · ChessStore.swift ·
//       TetrisDuelStore.swift · CheckMobileKit/Messages/MessagesRules.swift 의 이름 정렬 @ 1b8260d (C§2.5 · C-X5)
package com.yehsung.aingcheck.core.rules.text

/**
 * 이름 정렬 비교기(Swift `localizedStandardCompare` 를 ko_KR 로캘로 — 사용자 기기 로캘). 기기 Collator 를 쓰지 않는다:
 * JDK `java.text.Collator` 는 CLDR 한국어 규칙·숫자 모드가 없고, ART 의 ICU 는 API 마다 판이 달라 같은 답을 보장하지 못한다.
 * 그래서 Swift 가 단일 스칼라를 줄 세운 순위표(`sort/collation-table` → [CollationTable])를 번들하고 UCA 처럼 단계별로 견준다.
 *
 * Foundation 정의(골든 spec): `compare(_:options: [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering], locale:)`.
 * C-X5 실측으로 정한 단계:
 *  1. 1차·2차(ICU secondary — 대소문자·너비 무시, 악센트는 센다) · 숫자 모드(Nd 덩어리 = 값, 앞 0 무시)
 *  2. 같으면 3차(대소문자·너비·호환 꼴 — 소문자가 먼저)
 *  3. 그래도 같으면 원문 UTF-16 비교. 단 ASCII 숫자 덩어리는 값으로 견주고, 값이 같으면 **긴 쪽(앞 0 이 많은 쪽)이 뒤**
 *     (Foundation forcedOrdering 의 마지막 판정 — "02" > "2", "é" < "é", "１" > "1").
 *
 * 다르게 두는 것(골든 `sort/natural-ko` 가 갈래를 잠근다):
 *  - **한자**: ko 규칙은 한자를 읽기 음절 옆(2차)에 둔다(漢 ≈ 한). 읽기표를 번들하지 않아 한자는 한글 뒤 · 라틴 앞에 코드포인트 순으로 선다.
 *  - **Foundation 의 반대칭 깨짐**: '간' / '가나' 처럼 종성 음절과 '같은 초·중성 + 음절' 을 양쪽으로 비교하면 Foundation 은 둘 다 1 을 낸다.
 *    그런 쌍은 일관된 답이 없어 Kotlin 은 자모 순서(초성 < 중성 < 종성 — 사전순)만 지킨다.
 *  - 레퍼토리 밖 글자(태국·아랍 문자 등)는 모든 순위 뒤 코드포인트 순.
 */
object NaturalKoCollation : Comparator<String> {
    private class Weights(val primary: Int, val secondary: Int, val tertiary: Int)

    private class Table(
        val weights: Map<Int, Weights>,
        val ignorable: Set<Int>,
        val primaryIgnorable: Map<Int, Int>,
        val latinA: Int,
        val zero: Int,
        val maxPrimary: Int,
    )

    private val table: Table by lazy { parse(CollationTable.ORDER, CollationTable.IGNORABLE, CollationTable.PRIMARY_IGNORABLE) }

    /** 번들 순위표를 단계별 가중치로 푼다(표식 P·S·T·I — 앞 글자와의 경계 단계). */
    private fun parse(order: String, ignorable: String, primaryIgnorable: String): Table {
        val weights = HashMap<Int, Weights>(4096)
        var p = 0
        var s = 0
        var t = 0
        for (token in order.split(' ')) {
            if (token.isEmpty()) continue
            when (token[0]) {
                'P' -> { p += 1; s = 1; t = 1 }
                'S' -> { s += 1; t = 1 }
                'T' -> { t += 1 }
                'I' -> {}
                else -> error("CollationTable 표식을 모른다: $token")
            }
            check(p > 0) { "CollationTable 첫 토큰이 P 가 아니다" }
            weights[token.substring(1).toInt(16)] = Weights(p, s, t)
        }
        val ignorableSet = ignorable.split(' ').filter { it.isNotEmpty() }.map { it.toInt(16) }.toSet()
        val marks = HashMap<Int, Int>()
        primaryIgnorable.split(' ').filter { it.isNotEmpty() }.forEachIndexed { index, hex -> marks[hex.toInt(16)] = index }
        val latinA = weights['a'.code]?.primary ?: error("CollationTable 에 'a' 가 없다")
        val zero = weights['0'.code]?.primary ?: error("CollationTable 에 '0' 이 없다")
        return Table(weights, ignorableSet, marks, latinA, zero, p)
    }

    /** 비교 단위 하나(UCA 의 collation element). 숫자 덩어리는 [number] 에 앞 0 을 뗀 자릿수 글자가 든다. */
    private class Element(val primary: Long, val number: String?, val secondary: Int, val tertiary: Int)

    private const val SHIFT = 21

    private fun isHan(cp: Int): Boolean =
        cp in 0x4E00..0x9FFF || cp in 0x3400..0x4DBF || cp in 0xF900..0xFAFF || cp in 0x20000..0x3FFFF

    /** 십진 숫자(Nd)의 값 — 유니코드는 숫자 열 벌을 0~9 차례로 잇달아 둔다(구간 시작이 언제나 0). */
    private fun digitValue(cp: Int): Int = (cp - TextScalars.rangeStartOf(cp)) % 10

    private fun elements(text: String): List<Element> {
        val t = table
        val cps = TextNormalization.nfc(text).codePointArray()
        val out = ArrayList<Element>(cps.size + 2)
        var i = 0
        while (i < cps.size) {
            val cp = cps[i]
            if (TextScalars.generalCategory(cp) == "Nd") {
                // ICU 숫자 모드: 이어지는 Nd 는 숫자 벌이 달라도 한 덩어리다("１007" = 1007 — C-X5 실측).
                val digits = StringBuilder()
                while (i < cps.size && TextScalars.generalCategory(cps[i]) == "Nd") {
                    digits.append('0' + digitValue(cps[i]))
                    i++
                }
                val stripped = digits.toString().trimStart('0').ifEmpty { "0" }
                out += Element(t.zero.toLong() shl SHIFT, stripped, 1, 1)
                continue
            }
            i++
            if (cp in 0xAC00..0xD7A3) {
                // 한글 음절 → 정준 분해(초성 · 중성 · 종성) — 표에는 자모가 있다.
                val index = cp - 0xAC00
                add(out, 0x1100 + index / (21 * 28), t)
                add(out, 0x1161 + (index % (21 * 28)) / 28, t)
                val trailing = index % 28
                if (trailing != 0) add(out, 0x11A7 + trailing, t)
                continue
            }
            add(out, cp, t)
        }
        return out
    }

    private fun add(out: MutableList<Element>, cp: Int, t: Table) {
        if (cp in t.ignorable) return
        t.primaryIgnorable[cp]?.let { rank ->
            out += Element(0L, null, 1_000_000 + rank, 1)
            return
        }
        val w = t.weights[cp]
        out += when {
            w != null -> Element(w.primary.toLong() shl SHIFT, null, w.secondary, w.tertiary)
            isHan(cp) -> Element(((t.latinA - 1).toLong() shl SHIFT) + cp, null, 1, 1)
            else -> Element(((t.maxPrimary + 1).toLong() shl SHIFT) + cp, null, 1, 1)
        }
    }

    private fun comparePrimary(a: Element, b: Element): Int {
        if (a.primary != b.primary) return a.primary.compareTo(b.primary)
        val x = a.number
        val y = b.number
        if (x != null && y != null) {
            if (x.length != y.length) return x.length.compareTo(y.length)
            return x.compareTo(y)
        }
        return 0
    }

    /** 1·2단계(대소문자·너비 무시). 0 이면 3단계로. */
    private fun compareSecondaryStrength(a: List<Element>, b: List<Element>): Int {
        val pa = a.filter { it.primary != 0L }
        val pb = b.filter { it.primary != 0L }
        for (k in 0 until minOf(pa.size, pb.size)) {
            val c = comparePrimary(pa[k], pb[k])
            if (c != 0) return c
        }
        if (pa.size != pb.size) return pa.size.compareTo(pb.size)
        for (k in 0 until minOf(a.size, b.size)) {
            if (a[k].secondary != b[k].secondary) return a[k].secondary.compareTo(b[k].secondary)
        }
        return a.size.compareTo(b.size)
    }

    private fun compareTertiary(a: List<Element>, b: List<Element>): Int {
        for (k in 0 until minOf(a.size, b.size)) {
            if (a[k].tertiary != b[k].tertiary) return a[k].tertiary.compareTo(b[k].tertiary)
        }
        return a.size.compareTo(b.size)
    }

    /**
     * 남은 꼬리의 마지막 판정(ICU 로 같은 글자 — 정준 동치 · 호환 자모 · 전각 숫자): **정준 분해한 꼴**의 UTF-16 을 먼저 견주고,
     * 그것도 같으면 원문 UTF-16(C-X5 실측 — "ㄱㅏ" > "가"(분해 1100 1161) · "e\u0301" < "é"(분해가 같아 원문) · "１" > "1").
     */
    private fun compareLiteral(a: String, b: String): Int {
        val byDecomposed = compareUnits(platformNfd(a), platformNfd(b))
        return if (byDecomposed != 0) byDecomposed else compareUnits(a, b)
    }

    private fun compareUnits(a: String, b: String): Int {
        for (k in 0 until minOf(a.length, b.length)) {
            if (a[k] != b[k]) return a[k].compareTo(b[k]).coerceIn(-1, 1)
        }
        return a.length.compareTo(b.length).coerceIn(-1, 1)
    }

    /**
     * -1 · 0 · 1. 같은 글이면 0, 아니면 언제나 0 이 아니다(forcedOrdering).
     *
     * C-X5 실측으로 맞춘 Foundation 의 두 겹:
     *  ① 앞에서부터 UTF-16 을 훑는다. 두 쪽이 다 **ASCII 숫자**면 덩어리 값을 견주고(다르면 끝), 값이 같고 자릿수가 다르면 그 차이를
     *     마지막 판정 후보로 적어 두고 지나간다("02" > "2"). 글자가 같으면 지나가고, 처음 다른 자리에서 멈춘다.
     *     ("1000１" / "1000ㄱ" 은 ASCII 1000 이 여기서 같다고 지나간 뒤 "１" / "ㄱ" 만 ②로 간다 — 그래서 1000 과 １ 이 한 덩어리가 아니다.)
     *  ② 남은 꼬리를 ICU 처럼 견준다: 1·2단계(대소문자·너비 무시, 숫자 모드 — Nd 는 벌이 달라도 한 덩어리) → 3단계 → ①의 후보 → 원문 비교.
     */
    override fun compare(a: String, b: String): Int {
        if (a == b) return 0
        var i = 0
        var j = 0
        var forced = 0
        while (i < a.length && j < b.length) {
            val ca = a[i]
            val cb = b[j]
            if (ca in '0'..'9' && cb in '0'..'9') {
                var ie = i
                while (ie < a.length && a[ie] in '0'..'9') ie++
                var je = j
                while (je < b.length && b[je] in '0'..'9') je++
                val ra = a.substring(i, ie).trimStart('0').ifEmpty { "0" }
                val rb = b.substring(j, je).trimStart('0').ifEmpty { "0" }
                if (ra.length != rb.length) return ra.length.compareTo(rb.length).coerceIn(-1, 1)
                val byValue = ra.compareTo(rb)
                if (byValue != 0) return byValue.coerceIn(-1, 1)
                if (forced == 0 && ie - i != je - j) forced = (ie - i).compareTo(je - j).coerceIn(-1, 1)
                i = ie
                j = je
                continue
            }
            if (ca != cb) break
            i++
            j++
        }
        // 서로게이트 짝 한가운데서 멈췄으면 짝 앞으로 물린다(두 쪽이 그 앞까지 같았다).
        if (i > 0 && j > 0 && i < a.length && a[i].isLowSurrogate() && a[i - 1].isHighSurrogate()) {
            i--
            j--
        }
        val restA = a.substring(i)
        val restB = b.substring(j)
        if (restA.isEmpty() && restB.isEmpty()) return forced
        val ea = elements(restA)
        val eb = elements(restB)
        val secondary = compareSecondaryStrength(ea, eb)
        if (secondary != 0) return secondary.coerceIn(-1, 1)
        val tertiary = compareTertiary(ea, eb)
        if (tertiary != 0) return tertiary.coerceIn(-1, 1)
        if (forced != 0) return forced
        return compareLiteral(restA, restB)
    }
}
