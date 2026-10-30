package com.yehsung.aingcheck.desktop.overlay.engine

import com.yehsung.aingcheck.core.rules.text.AingStickerText
import java.text.BreakIterator

/*
 * 말풍선 문구 판정 한 벌 — 맥 OverlayMessageBubble(CheckOverlayWindow.swift :2386-2697) · 찌름/대결/울트라 문구(:1074 · :1266-1700).
 * 폭은 BubbleTextMeasure(b2 = 번들 Pretendard)로 잰다 — 맥 SF Rounded 와 inline/도착 경계가 다를 수 있다(W-3 #8, 수용).
 */
object BubbleForm {
    /** 이름 글자 상한(맥 nameLimit 6). */
    const val NAME_LIMIT = 6
    /** 폭으로 못 보는 것(빈 글리프·결합 문자 폭탄)을 막는 안전망(맥 inlineGraphemeCeiling 40). */
    const val INLINE_GRAPHEME_CEILING = 40
    const val ARRIVAL_ICON = "✉️"
    const val ARRIVAL_SUFFIX = "님 메시지 도착!"

    sealed interface Form {
        val text: String
        data class Inline(override val text: String) : Form
        data class Arrival(override val text: String) : Form
    }

    /**
     * ★ 규약 9 — 메시지 말풍선 글자 변환(AingStickerText.preview)은 호출부가 아니라 **이 함수 안**에서(맥 messageBubbleText :1158).
     */
    fun messageBubble(name: String, body: String, m: BubbleTextMeasure): Form = of(name, AingStickerText.preview(body), m)

    /**
     * 규칙 ①~④(맥 measuredForm :2565): ① 잉크 0 → 도착 ② 40 글자소 초과 → 도착 ③ 캡슐(2줄·낱말 한 줄)에 안 맞음 → 도착
     * ④ 결과가 도착 안내 꼴과 같으면(위장) → 도착. 줄바꿈은 공백으로 접는다.
     */
    fun of(name: String, body: String, m: BubbleTextMeasure): Form {
        val shortName = clippedName(name, m)
        val flat = flattened(body)
        val arrival = Form.Arrival(arrivalText(shortName))
        if (m.width(inkOnly(flat)) <= 0.0) return arrival // ①
        if (graphemeCount(flat) > INLINE_GRAPHEME_CEILING) return arrival // ②
        val spoken = "${shortName}님: $flat"
        if (!fitsCapsule(spoken, m)) return arrival // ③
        if (isArrival(spoken)) return arrival // ④
        return Form.Inline(spoken)
    }

    fun arrivalText(clippedName: String): String = "$ARRIVAL_ICON ${clippedName}$ARRIVAL_SUFFIX"

    fun isArrival(text: String): Boolean = text.startsWith("$ARRIVAL_ICON ") && text.endsWith(ARRIVAL_SUFFIX)

    /** 2줄 안 + 한글 낱말 하나가 한 줄 폭 안(맥 fitsCapsule :2483 — 맥의 두 줄바꿈 전략은 Windows 측정기 하나로). */
    fun fitsCapsule(text: String, m: BubbleTextMeasure): Boolean {
        if (m.lineCount(text, BubbleMetrics.TEXT_WIDTH) > BubbleMetrics.LINE_LIMIT) return false
        return cjkWordsFitOneLine(text, m)
    }

    fun cjkWordsFitOneLine(text: String, m: BubbleTextMeasure): Boolean =
        splitOnWhitespace(text).filter { it.any(::isCjk) }.all { m.width(it) <= BubbleMetrics.TEXT_WIDTH }

    /** Swift `split(whereSeparator: isWhitespace)` — 유니코드 공백(NBSP·전각 공백 포함)으로 나누고 빈 조각은 버린다. */
    private fun splitOnWhitespace(text: String): List<String> {
        val out = ArrayList<String>()
        val cur = StringBuilder()
        for (c in text) {
            if (c.isWhitespace() || c == '\u00A0' || c == '\u3000') {
                if (cur.isNotEmpty()) { out += cur.toString(); cur.clear() }
            } else cur.append(c)
        }
        if (cur.isNotEmpty()) out += cur.toString()
        return out
    }

    fun isCjk(c: Char): Boolean = when (c.code) {
        in 0x1100..0x11FF, in 0x3130..0x318F, in 0xA960..0xA97F, in 0xAC00..0xD7A3, in 0xD7B0..0xD7FF -> true
        in 0x3040..0x30FF, in 0x31F0..0x31FF -> true
        in 0x3400..0x4DBF, in 0x4E00..0x9FFF, in 0xF900..0xFAFF -> true
        else -> false
    }

    /** 이름은 6자 + 폭 예산("가"×6+"…") 둘 다 — 넓은 라틴 이름은 6자 전에 잘린다(맥 clippedName :2586). */
    fun clippedName(name: String, m: BubbleTextMeasure): String {
        val budget = m.width("가".repeat(NAME_LIMIT) + "…")
        var limit = minOf(graphemeCount(name), NAME_LIMIT)
        while (limit > 0) {
            val candidate = clipped(name, limit)
            if (m.width(candidate) <= budget) return candidate
            limit -= 1
        }
        return if (name.isEmpty()) name else "…"
    }

    /** 맥 clippedForBubble(:1165) — 글자소 단위로 자르고 "…". */
    fun clipped(text: String, limit: Int): String {
        if (limit <= 0) return text
        val g = graphemes(text)
        return if (g.size <= limit) text else g.take(limit).joinToString("") + "…"
    }

    fun flattened(body: String): String =
        body.split(Regex("[\\n\\r\\u000B\\u000C\\u0085\\u2028\\u2029]+")).filter { it.isNotEmpty() }.joinToString(" ")

    fun inkOnly(text: String): String = text.filterNot { it.isWhitespace() }

    fun graphemes(text: String): List<String> {
        if (text.isEmpty()) return emptyList()
        val it = BreakIterator.getCharacterInstance()
        it.setText(text)
        val out = ArrayList<String>()
        var start = it.first()
        var end = it.next()
        while (end != BreakIterator.DONE) {
            out += text.substring(start, end)
            start = end
            end = it.next()
        }
        return out
    }

    fun graphemeCount(text: String): Int = graphemes(text).size

    // ── 찌름·울트라(맥 :1074 · :1698) ──

    fun pokeText(names: List<String>): String {
        val first = names.firstOrNull() ?: return ""
        return if (names.size == 1) "${first}님이 콕 찔렀어요!" else "${first}님 외 ${names.size - 1}명이 콕 찔렀어요!"
    }

    fun ultraText(name: String, otherCount: Int): String =
        if (otherCount > 0) "${name}님의 울트라 찌르기! (외 ${otherCount}명)" else "${name}님의 울트라 찌르기!"

    // ── 대결(맥 :1266 · :1350 · :1422 · :1497 · :1563 · :1638 — 세 벌을 하나로) ──

    private fun gameLabel(game: DuelGame): String = when (game) {
        DuelGame.GOMOKU -> "오목"
        DuelGame.CHESS -> "체스"
        DuelGame.TETRIS -> "테트리스"
    }

    fun duelInviteText(game: DuelGame, peerName: String, stake: Int, m: BubbleTextMeasure): String {
        val shortName = clippedName(peerName, m)
        val label = gameLabel(game)
        val full = "${shortName}님이 $label 대결을 신청했어요 · 루비 $stake"
        if (fitsCapsule(full, m)) return full
        val short = "${shortName}님의 $label 신청 · 루비 $stake"
        if (fitsCapsule(short, m)) return short
        return "$label 대결 신청 · 루비 $stake"
    }

    fun duelAttentionText(a: DuelAttention, m: BubbleTextMeasure): String {
        val name = clippedName(a.opponentName, m)
        return when (a.game) {
            DuelGame.GOMOKU, DuelGame.CHESS -> {
                val chess = if (a.game == DuelGame.CHESS) "체스 " else ""
                when (a.kind) {
                    DuelAttentionKind.MATCH_STARTED -> "${chess}대국이 시작됐어요 · 내 차례예요"
                    DuelAttentionKind.MY_TURN -> {
                        val full = "${name}님이 뒀어요 · ${chess}내 차례예요"
                        if (name.isNotEmpty() && fitsCapsule(full, m)) full else "상대가 뒀어요 · ${chess}내 차례예요"
                    }
                }
            }
            DuelGame.TETRIS -> {
                val full = "${name}님과 테트리스 대결이 시작됐어요"
                if (name.isNotEmpty() && fitsCapsule(full, m)) full else "테트리스 대결이 시작됐어요"
            }
        }
    }
}
