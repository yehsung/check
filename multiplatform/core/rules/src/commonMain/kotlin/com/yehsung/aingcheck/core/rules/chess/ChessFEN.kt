// 원본: Sources/CheckCore/ChessFEN.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.chess

// FEN 양방향(파싱 · 생성)과 **동형 반복 키**.
//
// 파서가 깐깐한 까닭(Swift 머리 주석): FEN 은 서버·AI·화면 사이를 오가는 유일한 국면 표현이다. **체스판으로 성립하는 국면**만 받는다 —
//  · 8줄 · 줄마다 정확히 8칸 · 왕은 양쪽에 하나씩 · 끝 줄에 폰 없음
//  · 배치는 **정규형**(빈 칸 수를 쪼개 적은 줄 "44" · "332" 는 거절 — 한 판이 여러 글자열이 되면 서버 원문과 앱 FEN 이 바이트로 어긋난다)
//  · 반수·수 번호는 정규형 10진수이고 **한 판에서 나올 수 있는 값**(hasReachableCounters)
//  · 캐슬링 권리는 킹이 제자리 + 그 귀퉁이에 룩이 있을 때만 · 앙파상 칸은 차례와 맞는 줄 + 잡힐 폰이 뒤에 + 지나간 칸이 빔
//  · 차례가 **아닌** 쪽이 체크인 국면은 거절
// 골든 `chess/fen`(Swift 가 받은·거절한 FEN 과 그 정규형·반복 키·판정)이 이 파서를 잰다.
//
// ⚠️ 알려진 차이(공백 가르기): Swift 는 글자(Character = 확장 그래핌)를 돌며 첫 스칼라가 White_Space 인 글자를 가른다.
//   Kotlin 은 코드 포인트를 돈다. 둘이 갈리는 입력은 **공백 바로 뒤에 결합 부호가 붙은 FEN**(Swift 는 그 묶음을 통째 구분자로 삼는다)과
//   Prepend 글자 바로 뒤의 공백뿐이다 — 정규 FEN 에는 없는 글자들이라 골든에 넣지 않았다(차이를 메우려면 유니코드 판에 기대는
//   그래핌 경계가 필요하다 — §8-16 ② 가 피한 그 의존이다).

/** Swift `Character.isWhitespace`(첫 스칼라의 유니코드 White_Space 속성) — 이 목록은 유니코드 판이 바뀌어도 고정이다. */
internal fun isSwiftWhitespace(code: Int): Boolean = when (code) {
    in 0x09..0x0D, 0x20, 0x85, 0xA0, 0x1680, in 0x2000..0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 -> true
    else -> false
}

/** Swift `fen.split(whereSeparator: { $0.isWhitespace })`(빈 조각은 버린다). 공백 글자는 전부 BMP 라 UTF-16 한 칸씩 본다. */
private fun splitOnWhitespace(text: String): List<String> {
    val out = ArrayList<String>()
    val current = StringBuilder()
    for (ch in text) {
        if (isSwiftWhitespace(ch.code)) {
            if (current.isNotEmpty()) { out.add(current.toString()); current.setLength(0) }
        } else {
            current.append(ch)
        }
    }
    if (current.isNotEmpty()) out.add(current.toString())
    return out
}

/**
 * Swift `ChessPosition(fen:)`. 칸은 6개(배치 · 차례 · 캐슬링 · 앙파상 · 반수 · 수 번호)이고, 뒤 두 칸은 생략해도 받는다(0 과 1).
 * 칸은 **공백 아무것**으로 가른다(스페이스·탭·CR·LF — 윈도 줄끝 FEN 이 '성립하지 않는 국면'과 같은 null 이 되지 않게).
 */
fun ChessPosition.Companion.fromFen(fen: String): ChessPosition? {
    val fields = splitOnWhitespace(fen)
    if (fields.size < 4 || fields.size > 6) return null

    val cells = ByteArray(64)
    val rows = fields[0].split('/')
    if (rows.size != 8) return null
    for ((rowIndex, row) in rows.withIndex()) {
        val rank = 7 - rowIndex // FEN 은 8번째 줄부터 적는다
        var file = 0
        var previousWasEmptyCount = false
        for (character in row) {
            // 빈 칸 수는 ASCII '1'…'8' 만이다.
            val ascii = character.code
            if (ascii in 0x31..0x38) {
                // 숫자 **이어쓰기**는 거절한다("44" · "332" · "11111111").
                if (previousWasEmptyCount) return null
                previousWasEmptyCount = true
                file += ascii - 0x30
                continue
            }
            previousWasEmptyCount = false
            val piece = ChessPiece.fromFenCharacter(character) ?: return null
            if (file >= 8) return null
            cells[rank * 8 + file] = ChessCode.code(piece).toByte()
            file += 1
        }
        if (file != 8) return null
    }

    // 왕은 양쪽에 하나씩. 끝 줄의 폰은 승격을 빼먹은 국면이라 체스판이 아니다.
    val kings = intArrayOf(0, 0)
    for (index in 0 until 64) {
        val cell = cells[index].toInt()
        if (cell == ChessCode.empty) continue
        if ((cell and ChessCode.kindMask) == ChessCode.king) kings[if ((cell and ChessCode.blackBit) == 0) 0 else 1] += 1
        if ((cell and ChessCode.kindMask) == ChessCode.pawn && (index < 8 || index >= 56)) return null
    }
    if (kings[0] != 1 || kings[1] != 1) return null

    val sideToMove = when (fields[1]) {
        "w" -> ChessColor.white
        "b" -> ChessColor.black
        else -> return null
    }

    val rights = ChessCastlingRights.parse(fields[2]) ?: return null
    val homes = listOf(
        CastlingHome(ChessCastlingRights.whiteKingside, 4, 7, ChessColor.white),
        CastlingHome(ChessCastlingRights.whiteQueenside, 4, 0, ChessColor.white),
        CastlingHome(ChessCastlingRights.blackKingside, 60, 63, ChessColor.black),
        CastlingHome(ChessCastlingRights.blackQueenside, 60, 56, ChessColor.black),
    )
    for (home in homes) {
        if (!rights.contains(home.right)) continue
        val colorBit = if (home.color == ChessColor.black) ChessCode.blackBit else 0
        if (cells[home.king].toInt() != (ChessCode.king or colorBit) || cells[home.corner].toInt() != (ChessCode.rook or colorBit)) {
            return null
        }
    }

    var enPassantTarget: ChessSquare? = null
    if (fields[3] != "-") {
        val target = ChessSquare.parse(fields[3]) ?: return null
        // 직전 두 칸 전진이 있었어야 한다: 칸이 비고, 잡힐 폰이 뒤에 있고, 출발 칸이 비어 있다.
        val expectedRank = if (sideToMove == ChessColor.white) 5 else 2
        val victim = if (sideToMove == ChessColor.white) target.index - 8 else target.index + 8
        val origin = if (sideToMove == ChessColor.white) target.index + 8 else target.index - 8
        val victimCode = ChessCode.pawn or (if (sideToMove == ChessColor.white) ChessCode.blackBit else 0)
        if (target.rank != expectedRank ||
            cells[target.index].toInt() != ChessCode.empty ||
            cells[victim].toInt() != victimCode ||
            cells[origin].toInt() != ChessCode.empty
        ) return null
        enPassantTarget = target
    }

    val halfmoveClock = fenCounter(if (fields.size >= 5) fields[4] else "0") ?: return null
    val fullmoveNumber = fenCounter(if (fields.size >= 6) fields[5] else "1") ?: return null

    val position = ChessPosition(cells, sideToMove, rights, enPassantTarget, halfmoveClock, fullmoveNumber)

    // 카운터도 **배치와 똑같이** 본다(거짓 반수 · Int 넘침).
    if (!position.hasReachableCounters) return null

    // 차례가 아닌 쪽이 체크면 그 수는 애초에 둘 수 없었던 수다.
    if (ChessRules.isInCheck(position, sideToMove.opponent)) return null
    return position
}

private class CastlingHome(val right: ChessCastlingRights, val king: Int, val corner: Int, val color: ChessColor)

/**
 * 반수·수 번호 칸. **정규형 10진수만**(부호·앞자리 0·빈 칸 거절). Swift 는 10글자까지 Int(64비트)로 읽고 뒤에서 한계로 거절한다 —
 * Kotlin 은 Int(32비트)를 넘는 값을 여기서 null 로 접는다(그런 값은 어차피 `hasReachableCounters` 에서 거절된다 — 결과가 같다).
 */
private fun fenCounter(text: String): Int? {
    if (text.isEmpty() || text.length > 10) return null
    for (character in text) if (character.code < 0x30 || character.code > 0x39) return null
    if (text != "0" && text.startsWith("0")) return null
    val value = text.toLong()
    return if (value > Int.MAX_VALUE) null else value.toInt()
}

/** FEN 6칸 전체. */
val ChessPosition.fen: String
    get() {
        val enPassantText = enPassantTarget?.notation ?: "-"
        return "$boardFEN ${if (sideToMove == ChessColor.white) "w" else "b"} ${castlingRights.fenText} $enPassantText " +
            "$halfmoveClock $fullmoveNumber"
    }

/** FEN 첫 칸(배치만). */
val ChessPosition.boardFEN: String
    get() {
        val text = StringBuilder()
        for (rowIndex in 0 until 8) {
            val rank = 7 - rowIndex
            var empties = 0
            for (file in 0 until 8) {
                val piece = ChessCode.piece(cells[rank * 8 + file].toInt())
                if (piece != null) {
                    if (empties > 0) { text.append(empties); empties = 0 }
                    text.append(piece.fenCharacter)
                } else {
                    empties += 1
                }
            }
            if (empties > 0) text.append(empties)
            if (rank > 0) text.append('/')
        }
        return text.toString()
    }

/**
 * 동형 반복(FIDE 9.2)의 국면 동일성 키 — 해시가 아니라 정규 문자열이라 충돌이 없다.
 * 담는 것: 배치 + 차례 + 캐슬링 권리 + **앙파상 가능성**(실제로 잡을 수 있을 때만 칸 이름). 빼는 것: 50수 카운터와 수 번호.
 */
val ChessPosition.repetitionKey: String
    get() {
        val enPassantText = if (ChessRules.hasLegalEnPassantCapture(this)) (enPassantTarget?.notation ?: "-") else "-"
        return "$boardFEN ${if (sideToMove == ChessColor.white) "w" else "b"} ${castlingRights.fenText} $enPassantText"
    }

/** 사람이 읽는 판(수 세기가 갈렸을 때 divide 와 함께 찍는 자리). */
val ChessPosition.asciiBoard: String
    get() {
        val lines = ArrayList<String>(9)
        for (rowIndex in 0 until 8) {
            val rank = 7 - rowIndex
            val line = StringBuilder("${rank + 1} ")
            for (file in 0 until 8) {
                line.append(ChessCode.piece(cells[rank * 8 + file].toInt())?.fenCharacter ?: '.')
                line.append(' ')
            }
            lines.add(line.toString())
        }
        lines.add("  a b c d e f g h")
        return lines.joinToString("\n")
    }

/**
 * 한 판의 동형 반복 장부. 호출자가 수를 둘 때마다 국면을 넣으면 [ChessRules.outcome] 에 그대로 건넬 표가 된다.
 * 되돌릴 수 없는 수에서도 **비우지 않는다**(FIDE 는 '같은 국면이 세 번'만 요구한다 — 비우지 않아도 결과가 같다).
 * Swift 값 타입 → Kotlin 은 [copy] 로 복사한다.
 */
class ChessRepetitionLedger private constructor(private val counts: HashMap<String, Int>) {
    constructor() : this(HashMap())

    fun copy(): ChessRepetitionLedger = ChessRepetitionLedger(HashMap(counts))

    /** 이 국면이 나왔다고 적는다. **판의 시작 국면도 넣어야 한다**. */
    fun record(position: ChessPosition) {
        val key = position.repetitionKey
        counts[key] = (counts[key] ?: 0) + 1
    }

    fun count(position: ChessPosition): Int = counts[position.repetitionKey] ?: 0

    /** [ChessRules.outcome] 에 넘기는 표(사본). */
    val repetitionCounts: Map<String, Int> get() = HashMap(counts)

    override fun equals(other: Any?): Boolean = other is ChessRepetitionLedger && other.counts == counts
    override fun hashCode(): Int = counts.hashCode()
}
