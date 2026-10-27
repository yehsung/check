// 원본: Sources/CheckCore/ChessNotation.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.chess

// 수 표기 — UCI(`e2e4` · `e7e8q`)와 SAN(`Nbd2` · `exd6` · `O-O` · `Qh4e1` · `e8=Q#`).
//
// UCI 는 기계 사이의 표기(서버·AI·실시간), SAN 은 사람이 읽는 표기(기보). 번역은 **한 군데**여야 한다.
// SAN 파싱은 생성에 기댄다: 합법 수 전부의 SAN(과 과다 명시형)을 만들어 **같은 것 하나**를 찾는다 — 파서를 따로 쓰면 "엔진이 만드는 SAN"과
// "엔진이 읽는 SAN"이 두 규칙이 된다. 골든 `chess/moves`(합법 수 · SAN · 효과)와 `chess/notation`(SAN·UCI 읽기 표 · 수순 재생)이 잰다.
//
// ⚠️ 알려진 차이(SAN 정규화): Swift 는 글자(확장 그래핌)를 돌며 기호·공백 글자를 걷는다. 결합 글자가 **공백 스칼라** 바로 뒤에 붙은 입력
//   (`"Nf3 ́"` 같은)은 Swift 가 그 묶음을 통째로 걷어 수를 찾고 Kotlin 은 결합 글자를 남겨 null 이다. 기호(`+` 등) 뒤 결합 부호는
//   두 쪽 다 null 이라 같다. 골든 `chess/notation` 의 san-grapheme* 셋째 칸(knownDivergence)으로 **정확한 목록을 잠갔다**
//   (ChessGoldenTest.knownSanDivergence — 늘거나 줄면 빨강).

/** UCI 문자열. 승격은 소문자 한 글자(`e7e8q`). */
val ChessMove.uci: String
    get() {
        val text = StringBuilder(from.notation).append(to.notation)
        val promotion = promotion
        if (promotion != null) text.append(promotion.fenLetter.lowercaseChar())
        return text.toString()
    }

/**
 * Swift `ChessMove(uci:)`. 4글자 또는 5글자(승격)만 받고, 승격 글자는 소문자 q·r·b·n 뿐이다 — `e7e8k` 는 **모양 단계에서** 막는다.
 * ASCII 밖 글자가 하나라도 있으면 Swift 도 칸·승격 판정에서 null 이다(칸은 ASCII 스칼라 둘, 승격은 ASCII 글자 하나) — 먼저 걸러 같게 한다.
 */
fun ChessMove.Companion.fromUci(uci: String): ChessMove? {
    if (uci.any { it.code > 0x7F }) return null
    if (uci.length != 4 && uci.length != 5) return null
    val from = ChessSquare.parse(uci.substring(0, 2)) ?: return null
    val to = ChessSquare.parse(uci.substring(2, 4)) ?: return null
    var promotion: ChessPieceKind? = null
    if (uci.length == 5) {
        val letter = uci[4]
        val kind = ChessPieceKind.fromFenLetter(letter) ?: return null
        if (kind !in ChessPieceKind.promotionChoices || !letter.isLowerCase()) return null
        promotion = kind
    }
    return ChessMove(from, to, promotion)
}

/** 수의 SAN. 합법 수가 아니면 null. 동형 중복 해소는 **파일 → 랭크 → 둘 다**(FIDE C.10). 폰이 잡을 때는 언제나 출발 파일(`exd5`). */
fun ChessRules.san(move: ChessMove, position: ChessPosition): String? = san(move, position, legalMoves(position))

/**
 * 합법 수 목록을 **이미 들고 있을 때** 쓰는 길. 목록은 **합법성 확인에만** 쓴다 — 동형 중복 해소는 판에서 직접 센다
 * (부분 목록을 넘기면 경쟁자가 안 보여 `Nbd2` 대신 `Nd2` 가 조용히 나오던 결함).
 */
fun ChessRules.san(move: ChessMove, position: ChessPosition, legalMoves: List<ChessMove>): String? {
    if (move !in legalMoves) return null
    val effect = effect(move, position) ?: return null
    val text = StringBuilder()

    if (effect.isCastling) {
        text.append(if (move.to.file > move.from.file) "O-O" else "O-O-O")
    } else if (effect.piece.kind == ChessPieceKind.pawn) {
        text.append(if (effect.captured == null) move.to.notation else "${fileLetter(move.from.file)}x${move.to.notation}")
        val promotion = move.promotion
        if (promotion != null) text.append('=').append(promotion.fenLetter)
    } else {
        text.append(effect.piece.kind.fenLetter)
        text.append(disambiguation(move, effect.piece, position))
        if (effect.captured != null) text.append('x')
        text.append(move.to.notation)
    }

    if (isInCheck(effect.after)) {
        text.append(if (ChessRules.legalMoves(effect.after).isEmpty()) "#" else "+")
    }
    return text.toString()
}

/**
 * SAN 을 수로 읽는다. 합법 수가 아니거나 **모호하면** null. 받아 주는 흔들림: 체크·평가 기호(`+ # ! ?`), 승격의 `=` 생략,
 * `0-0` 캐슬링, `e.p.` 꼬리, 앞뒤 공백·줄끝, **과다 명시**(`Qd1d2` · `Qdd2` · `Q1d2` · `Qd1-d2` · 잡기의 `x` 생략 · 폰의 장형 `e2e4`).
 */
fun ChessRules.move(san: String, position: ChessPosition): ChessMove? {
    val wanted = normalizedSAN(san)
    if (wanted.isEmpty()) return null
    val legal = ChessRules.legalMoves(position)
    var found: ChessMove? = null
    for (candidate in legal) {
        val text = this.san(candidate, position, legal) ?: continue
        if (wanted !in spellings(candidate, text, position)) continue
        if (found != null) return null // 모호: 합법 수 둘이 같은 표기
        found = candidate
    }
    return found
}

/** 이 수를 가리키는 표기 전부(정규형) — 생성한 SAN 에 과다 명시형을 더한 것. */
private fun spellings(move: ChessMove, canonical: String, position: ChessPosition): Set<String> {
    val out = HashSet<String>()
    out.add(normalizedSAN(canonical))
    // 캐슬링엔 과다 명시형이 없다.
    val piece = position[move.from] ?: return out
    if (canonical.startsWith("O")) return out
    val captures = canonical.contains("x")
    val promotion = move.promotion?.fenLetter?.toString() ?: ""
    val fileText = fileLetter(move.from.file).toString()
    val heads: List<String> = if (piece.kind == ChessPieceKind.pawn) {
        // 폰이 잡을 때 출발 파일은 PGN 이 **요구한다**(`exd5`).
        if (captures) listOf(fileText, move.from.notation) else listOf("", move.from.notation)
    } else {
        val letter = piece.kind.fenLetter.toString()
        listOf("", fileText, (move.from.rank + 1).toString(), move.from.notation).map { letter + it }
    }
    for (head in heads) {
        out.add(normalizedSAN(head + move.to.notation + promotion))
        if (captures) out.add(normalizedSAN(head + "x" + move.to.notation + promotion))
    }
    return out
}

/** 한 수순을 차례로 적용하며 **거쳐 간 국면 전부**를 낸다(시작·끝 포함). 하나라도 불법이면 null. */
fun ChessRules.replay(uciLine: List<String>, from: ChessPosition): List<ChessPosition>? {
    val trail = ArrayList<ChessPosition>(uciLine.size + 1)
    trail.add(from)
    var current = from
    for (text in uciLine) {
        val move = ChessMove.fromUci(text) ?: return null
        val next = apply(move, current) ?: return null
        current = next
        trail.add(current)
    }
    return trail
}

/** 수순의 SAN 기보(기록·보고용). 하나라도 불법이면 null. */
fun ChessRules.sanLine(uciLine: List<String>, from: ChessPosition): List<String>? {
    var current = from
    val line = ArrayList<String>(uciLine.size)
    for (text in uciLine) {
        val move = ChessMove.fromUci(text) ?: return null
        val notation = san(move, current, legalMoves(current)) ?: return null
        val next = apply(move, current) ?: return null
        line.add(notation)
        current = next
    }
    return line
}

/** 동형 중복 해소. 경쟁자는 **판에서 직접** 센다. 겹칠 말이 판에 아예 없으면 수 생성을 하지 않는다. */
private fun disambiguation(move: ChessMove, piece: ChessPiece, position: ChessPosition): String {
    val code = ChessCode.code(piece)
    var hasTwin = false
    for (index in 0 until 64) {
        if (index != move.from.index && position.cells[index].toInt() == code) {
            hasTwin = true
            break
        }
    }
    if (!hasTwin) return ""

    val rivals = ChessRules.legalMoves(position).filter { it != move && it.to == move.to && position[it.from] == piece }
    if (rivals.isEmpty()) return ""
    if (rivals.none { it.from.file == move.from.file }) return fileLetter(move.from.file).toString()
    if (rivals.none { it.from.rank == move.from.rank }) return (move.from.rank + 1).toString()
    return move.from.notation
}

private fun fileLetter(file: Int): Char = ('a'.code + file).toChar()

/**
 * 비교용 정규형. `0` 은 SAN 어디에도 쓰이지 않으므로 통째로 `O` 로 바꿔도 캐슬링만 맞는다. 공백은 종류를 가리지 않고 걷는다(CR 포함),
 * `-` 도 걷는다(장형 `Qd1-d2` — 캐슬링은 양쪽이 이 함수를 지난 뒤 비교하므로 `OO`·`OOO` 로 여전히 갈린다).
 */
private fun normalizedSAN(text: String): String {
    var out = text.replace("e.p.", "")
    out = out.replace("=", "")
    out = out.replace("0", "O")
    val result = StringBuilder(out.length)
    for (ch in out) {
        if (ch == '+' || ch == '#' || ch == '!' || ch == '?' || ch == '-') continue
        if (isSwiftWhitespace(ch.code)) continue
        result.append(ch)
    }
    return result.toString()
}
