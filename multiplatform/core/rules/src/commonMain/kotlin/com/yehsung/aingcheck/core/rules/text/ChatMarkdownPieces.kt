// 원본: wt-phone-1017 2ad01732 Sources/CheckCore/ChatMarkdownPieces.swift(맥 ChatMarkdownText.pieces · copyLinks · ChatBubbleTextView.copyText 를
//       맥·폰 한 벌로 옮긴 것 — 맥 0.3.74 의 같은 규칙) · Sources/check/ChatBubbleTextView.swift:112-139 @ 12624739. 판 7 Android 이식.
//
// 해석(ChatMarkdown.parse)은 줄과 조각을 돌려준다. 그리는 쪽은 그 줄들을 **그릴 조각 목록 하나**로 옮겨 글꼴 · 색만 입힌다
// (Android 말풍선 — ui ChatBubbleMarkdown). 무엇을 그리는가(글자 · 제목 단계 · 굵게 · 링크 · 호스트 꼬리표)는 여기 한 곳이 정한다 —
// 꼬리표는 "보이는 글과 여는 곳이 다른 링크"를 알리는 안전장치라 한 기기만 빠뜨리면 안 된다.
//
// 복사도 같다(대표 결정 "받은 말풍선도 드래그" · 맥 검토 P2): 고른 구간에 `[글](주소)` 링크가 걸치면 호스트 꼬리표 대신 **실제 주소**를 담고,
// 글자는 서식 없이 담는다([ChatMarkdownCopy.text]). 고른 것이 없는 [복사]는 **원문**이다(마크다운 기호 · 이모티콘 토큰 그대로).
package com.yehsung.aingcheck.core.rules.text

/** 말풍선이 그리는 조각 하나. 이어 붙이면 말풍선에 보이는 글자 전부다. */
data class ChatMarkdownPiece(
    val kind: Kind,
    val text: String,
    /** 이 조각이 놓인 줄의 종류(크기를 정하는 값). 줄 사이 "\n" 은 본문이다. */
    val line: ChatMarkdownLineKind,
    /** 굵게 그리는가. 제목 줄의 조각은 언제나 굵다. 꼬리표 · 줄바꿈은 굵지 않다. */
    val isBold: Boolean,
    /** 누르면 열 주소(http·https 뿐). 꼬리표 · 줄바꿈은 null. */
    val link: ChatLink?,
) {
    enum class Kind {
        /** 해석 조각(본문 · 굵게 · 링크). */
        span,

        /** 줄 사이 "\n". */
        lineBreak,

        /** `[글](주소)` 뒤에 붙이는 실제 호스트 " (호스트)" — 링크가 아니다(누르는 자리는 글 그대로다). */
        disclosure,
    }

    /** 크기 단계: 0 = 본문, 1 = `#`, 2 = `##`, 3 = `###` 이하(`####`~`######` 도 3 — 크기는 3단계에서 멈춘다). */
    val headingStep: Int get() = ChatMarkdownPieces.headingStep(line)
}

object ChatMarkdownPieces {
    /** 줄 종류 → 크기 단계([ChatMarkdownPiece.headingStep]). */
    fun headingStep(kind: ChatMarkdownLineKind): Int =
        if (kind is ChatMarkdownLineKind.heading) kind.level.coerceIn(1, 3) else 0

    /** 본문 → 그릴 조각들. **이모티콘 폴백은 부르는 쪽이 먼저 거친다**([AingStickerText.preview] → 여기). */
    fun pieces(body: String): List<ChatMarkdownPiece> {
        val out = ArrayList<ChatMarkdownPiece>()
        for ((index, line) in ChatMarkdown.parse(body).withIndex()) {
            if (index > 0) out += ChatMarkdownPiece(ChatMarkdownPiece.Kind.lineBreak, "\n", ChatMarkdownLineKind.paragraph, false, null)
            val isHeading = line.kind is ChatMarkdownLineKind.heading
            val disclosures = ChatMarkdown.linkDisclosures(line)
            for ((spanIndex, span) in line.spans.withIndex()) {
                out += ChatMarkdownPiece(ChatMarkdownPiece.Kind.span, span.text, line.kind, isHeading || span.isBold, span.link)
                disclosures[spanIndex]?.let { host ->
                    out += ChatMarkdownPiece(ChatMarkdownPiece.Kind.disclosure, " ($host)", line.kind, false, null)
                }
            }
        }
        return out
    }

    /** 한 줄에 그리는 쪽이 **덧붙이는** 글자 수(호스트 꼬리표 " (호스트)" — Swift `String.count` 눈금). */
    fun addedCharacters(line: ChatMarkdownLine): Int = ChatMarkdown.linkDisclosures(line).values.sumOf { Graphemes.count(it) + 3 }

    /**
     * 조각 위치 → 복사에 담을 실제 주소. 같은 주소로 이어진 링크 조각들이 한 링크이고([ChatMarkdown.linkDisclosures] 와 같은 묶음),
     * 그 글이 주소 자체가 아니면(`[자료](https://a.example/doc)` · `[a.example](https://a.example/doc)`) 글 조각들과 바로 뒤 꼬리표에 표시한다.
     * 맨 주소 · `[https://a.com/](https://a.com)` 처럼 글이 곧 주소인 링크는 표시하지 않는다(보이는 글자가 이미 주소다).
     */
    fun copyLinks(pieces: List<ChatMarkdownPiece>): Map<Int, ChatLink> {
        val result = LinkedHashMap<Int, ChatLink>()
        var index = 0
        while (index < pieces.size) {
            val url = pieces[index].link
            if (pieces[index].kind != ChatMarkdownPiece.Kind.span || url == null) {
                index++
                continue
            }
            var end = index
            val label = StringBuilder()
            while (end < pieces.size && pieces[end].kind == ChatMarkdownPiece.Kind.span && pieces[end].link == url) {
                label.append(pieces[end].text)
                end++
            }
            if (!ChatMarkdown.swiftEquals(ChatMarkdown.comparableAddress(label.toString()), ChatMarkdown.comparableAddress(url.absoluteString))) {
                for (spot in index until end) result[spot] = url
                if (end < pieces.size && pieces[end].kind == ChatMarkdownPiece.Kind.disclosure) result[end] = url
            }
            index = end
        }
        return result
    }

    /** 조각들을 이어 붙인 글(말풍선에 보이는 글자 전부). */
    fun drawn(pieces: List<ChatMarkdownPiece>): String = pieces.joinToString("") { it.text }
}

/** 고른 글 · [복사] 글(Swift `ChatMarkdownCopy`). 구간은 [ChatMarkdownPieces.drawn] 의 UTF-16 자리(Swift `NSRange` 와 같은 눈금)다. */
object ChatMarkdownCopy {
    /**
     * 그린 글자의 한 구간 `[start, end)` → 복사할 글자(서식 없음). 보이는 글자 그대로이되 **`[글](주소)` 링크만 다르다**: 글이 주소와 다른 링크
     * ([ChatMarkdownPieces.copyLinks] 가 표시한 조각)는 고른 글 뒤에 ` (실제 주소)` 를 한 번 담고, 꼬리표 글자는 그 자리로 갈음한다.
     * 꼬리표만 골라도 주소를 담는다. 맨 주소(글 = 주소)는 보이는 그대로다.
     */
    fun text(pieces: List<ChatMarkdownPiece>, start: Int, end: Int): String {
        val links = ChatMarkdownPieces.copyLinks(pieces)
        val out = StringBuilder()
        var pending: ChatLink? = null
        fun flush() {
            val url = pending ?: return
            out.append(if (out.isEmpty()) "" else " ").append("(").append(url.absoluteString).append(")")
            pending = null
        }
        var offset = 0
        for ((index, piece) in pieces.withIndex()) {
            val pieceStart = offset
            val pieceEnd = offset + piece.text.length
            offset = pieceEnd
            val from = maxOf(start, pieceStart)
            val to = minOf(end, pieceEnd)
            if (from >= to) continue
            val url = links[index]
            if (piece.kind == ChatMarkdownPiece.Kind.disclosure) {
                // 꼬리표 " (호스트)" — 글자 대신 실제 주소. 고른 것이 꼬리표에서 시작했으면 그 주소를 여기서 집는다.
                if (pending == null) pending = url
                flush()
                continue
            }
            if (pending != url) flush()
            out.append(piece.text, from - pieceStart, to - pieceStart)
            if (url != null) pending = url
        }
        flush()
        return out.toString()
    }

    /** 고른 구간들 → 복사할 글자(여러 구간이면 줄바꿈으로 잇는다). 빈 구간 · 글자 밖 구간은 버리고, 남는 것이 없으면 null(아무것도 안 골랐다). */
    fun text(pieces: List<ChatMarkdownPiece>, ranges: List<IntRange>): String? {
        val total = ChatMarkdownPieces.drawn(pieces).length
        val parts = ranges
            .filter { !it.isEmpty() && it.first >= 0 && it.last + 1 <= total }
            .map { text(pieces, it.first, it.last + 1) }
        return if (parts.isEmpty()) null else parts.joinToString("\n")
    }

    /**
     * 말풍선 메뉴 [복사]가 담을 글자 — 고른 글자가 있으면 그것, 없으면 **원문**(마크다운 기호 · 이모티콘 토큰 그대로 — 붙여넣어 다시 보내면 같은 꾸밈 ·
     * 같은 그림이 된다). 폰 길게 누르기 메뉴의 [복사]는 고르는 길이 없어 언제나 원문이다.
     */
    fun menuText(selection: String?, raw: String): String = selection ?: raw
}
