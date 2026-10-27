// 원본: Sources/CheckCore/ChessRules.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.chess

// FIDE 표준 체스 룰 — 국면 · 합법 수 생성 · 적용 · 판정. 순수 · 결정적.
//
// 합격선은 perft 다(Swift 머리 주석): 캐슬링 경유 칸, 앙파상으로 열리는 왕, 승격 네 갈래는 글로 읽으면 다 맞아 보이고 수를 세면 갈린다.
// 골든 `chess/perft`(공표 여섯 국면 + 종국 잎 셋, 깊이별 노드 수 + divide)가 이 파일의 계약이다 — 숫자가 틀리면 **엔진이 틀린 것이다**.
// perft 가 못 잡는 50수 · 3회 동형 반복 · 불충분 기물은 골든 `chess/outcome` 이 잡는다.
//
// 내부 표현(1바이트 칸 코드 · 미리 깐 이동표 · 원시 수)은 이 패키지 밖으로 새지 않는다(internal).
//
// Swift 와 다른 점(값 의미): Swift 의 `ChessPosition` · `ChessEngine` 은 값 타입이다. Kotlin 의 [ChessPosition] 은 참조라
// 복사는 [ChessPosition.copy] 로만 하고, 엔진은 국면의 칸을 언제나 복사해서 쓴다(들어온 국면을 고치지 않는다).
// Swift `Int`(64비트) 카운터는 Kotlin `Int` 다 — 파서 한계(10,000)·엔진 한계(1e9)가 둘 다 32비트 안이라 판정이 같다.

// MARK: - 공개 타입

/** 말 색. 백 선수. */
enum class ChessColor(val rawValue: String) {
    white("white"),
    black("black");

    val opponent: ChessColor get() = if (this == white) black else white

    companion object {
        fun fromRawValue(raw: String): ChessColor? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 말 종류. */
enum class ChessPieceKind(val rawValue: String) {
    pawn("pawn"),
    knight("knight"),
    bishop("bishop"),
    rook("rook"),
    queen("queen"),
    king("king");

    /** FEN 글자(백 기준 대문자). SAN 의 말 글자도 이것이다 — 폰만 글자가 없다. */
    val fenLetter: Char
        get() = when (this) {
            pawn -> 'P'
            knight -> 'N'
            bishop -> 'B'
            rook -> 'R'
            queen -> 'Q'
            king -> 'K'
        }

    /** SAN 에서 앞에 붙는 글자. 폰은 null(`e4` 는 `Pe4` 가 아니다). */
    val sanLetter: Char? get() = if (this == pawn) null else fenLetter

    companion object {
        fun fromRawValue(raw: String): ChessPieceKind? = entries.firstOrNull { it.rawValue == raw }

        /** Swift `ChessPieceKind(fenLetter:)` — 대소문자 둘 다. 모르는 글자는 null. */
        fun fromFenLetter(letter: Char): ChessPieceKind? = when (letter) {
            'P', 'p' -> pawn
            'N', 'n' -> knight
            'B', 'b' -> bishop
            'R', 'r' -> rook
            'Q', 'q' -> queen
            'K', 'k' -> king
            else -> null
        }

        /** 승격으로 고를 수 있는 넷(FIDE 3.7e). 이 목록이 생성기의 유일한 근거다. */
        val promotionChoices: List<ChessPieceKind> = listOf(queen, rook, bishop, knight)
    }
}

data class ChessPiece(val color: ChessColor, val kind: ChessPieceKind) {
    /** FEN 글자. 백은 대문자, 흑은 소문자. */
    val fenCharacter: Char get() = if (color == ChessColor.white) kind.fenLetter else kind.fenLetter.lowercaseChar()

    companion object {
        /** Swift `ChessPiece(fenCharacter:)`. 말 글자 열두 개만 받는다(그 밖은 null). */
        fun fromFenCharacter(character: Char): ChessPiece? {
            val kind = ChessPieceKind.fromFenLetter(character) ?: return null
            return ChessPiece(if (character.isUpperCase()) ChessColor.white else ChessColor.black, kind)
        }
    }
}

/** 칸. index 0 = a1, 7 = h1, 56 = a8, 63 = h8. **이 타입의 값은 언제나 판 안이다**(실패 가능 생성자 셋 → [of]·[at]·[parse]). */
class ChessSquare private constructor(val index: Int) : Comparable<ChessSquare> {
    val file: Int get() = index and 7
    val rank: Int get() = index shr 3

    val notation: String get() = "${('a'.code + file).toChar()}${rank + 1}"

    /** 칸 색. 불충분 기물의 '같은 색 비숍'을 재는 자리라 계산을 한 곳에만 둔다. */
    val isLightSquare: Boolean get() = (file + rank) % 2 == 1

    override fun compareTo(other: ChessSquare): Int = index.compareTo(other.index)
    override fun equals(other: Any?): Boolean = other is ChessSquare && other.index == index
    override fun hashCode(): Int = index
    override fun toString(): String = notation

    companion object {
        private val ALL = Array(64) { ChessSquare(it) }

        /** Swift `ChessSquare(index:)`. */
        fun of(index: Int): ChessSquare? = if (index in 0 until 64) ALL[index] else null

        /** Swift `ChessSquare(file:rank:)`. */
        fun at(file: Int, rank: Int): ChessSquare? =
            if (file in 0 until 8 && rank in 0 until 8) ALL[rank * 8 + file] else null

        /** Swift `ChessSquare(_ notation:)`. 정규형 `^[a-h][1-8]$` **만** 받는다(스칼라 두 개). */
        fun parse(notation: String): ChessSquare? {
            if (notation.length != 2) return null // BMP 밖 스칼라는 두 칸을 차지하므로 길이 2 는 스칼라 둘 또는 대리 쌍 하나다.
            val a = notation[0].code
            val b = notation[1].code
            if (a < 0x61 || a > 0x68) return null // a…h
            if (b < 0x31 || b > 0x38) return null // 1…8
            return at(a - 0x61, b - 0x31)
        }
    }
}

/** 수. 캐슬링은 **킹의 두 칸 이동**으로 적는다(e1g1). 승격이 아닌 수의 [promotion] 은 null 이어야 한다. */
data class ChessMove(val from: ChessSquare, val to: ChessSquare, val promotion: ChessPieceKind? = null) {
    override fun toString(): String = uci

    /** UCI 파서([fromUci])가 붙는 자리(ChessNotation.kt). */
    companion object
}

/** 캐슬링 권리 넷. [rawValue] 비트는 FEN 글자 순서(K Q k q)와 같다 — 엔진이 이 비트를 그대로 들고 다닌다. */
class ChessCastlingRights(val rawValue: Int) {
    fun contains(other: ChessCastlingRights): Boolean = (rawValue and other.rawValue) == other.rawValue
    operator fun plus(other: ChessCastlingRights): ChessCastlingRights = ChessCastlingRights(rawValue or other.rawValue)
    val isEmpty: Boolean get() = rawValue == 0

    /** FEN 3번째 칸. 비면 "-". */
    val fenText: String
        get() {
            val text = StringBuilder()
            if (contains(whiteKingside)) text.append('K')
            if (contains(whiteQueenside)) text.append('Q')
            if (contains(blackKingside)) text.append('k')
            if (contains(blackQueenside)) text.append('q')
            return if (text.isEmpty()) "-" else text.toString()
        }

    override fun equals(other: Any?): Boolean = other is ChessCastlingRights && other.rawValue == rawValue
    override fun hashCode(): Int = rawValue
    override fun toString(): String = fenText

    companion object {
        val none = ChessCastlingRights(0)
        val whiteKingside = ChessCastlingRights(1)
        val whiteQueenside = ChessCastlingRights(2)
        val blackKingside = ChessCastlingRights(4)
        val blackQueenside = ChessCastlingRights(8)
        val all = ChessCastlingRights(15)

        fun kingside(color: ChessColor): ChessCastlingRights = if (color == ChessColor.white) whiteKingside else blackKingside
        fun queenside(color: ChessColor): ChessCastlingRights = if (color == ChessColor.white) whiteQueenside else blackQueenside

        /**
         * FEN 글자열을 읽는다. 중복 글자·모르는 글자·**빈 칸**은 null — '권리 없음'은 `-` 로만 적는다(빈 값이 [] 로 통과하면
         * 둘 수 있는 캐슬링이 조용히 사라진다). Swift 는 Character 를 돈다 — 결합 부호가 붙은 글자는 어느 쪽이든 모르는 글자라 null.
         */
        fun parse(fen: String): ChessCastlingRights? {
            if (fen == "-") return none
            if (fen.isEmpty()) return null
            var rights = 0
            for (character in fen) {
                val bit = when (character) {
                    'K' -> 1
                    'Q' -> 2
                    'k' -> 4
                    'q' -> 8
                    else -> return null
                }
                if (rights and bit != 0) return null
                rights = rights or bit
            }
            return ChessCastlingRights(rights)
        }
    }
}

/** [ChessPosition.pieces] 의 한 줄(Swift 튜플 `(square:, piece:)`). */
data class ChessPlacedPiece(val square: ChessSquare, val piece: ChessPiece)

/**
 * 국면. Swift 처럼 같음·해시가 있지만 **반복 판정에는 [repetitionKey] 를 써라** — 50수 카운터와 수 번호는 동형 반복 판정에 들지 않는다.
 * 칸은 `subscript` 로만 읽고 쓴다(비트 배치는 패키지 밖으로 새지 않는다).
 */
class ChessPosition internal constructor(
    internal val cells: ByteArray,
    var sideToMove: ChessColor,
    var castlingRights: ChessCastlingRights,
    /** 앙파상으로 **잡을 수 있는 칸**(직전 두 칸 전진이 지나간 칸). 두 칸 전진 바로 다음 수에만 값이 있다. */
    var enPassantTarget: ChessSquare?,
    /** 50수 규칙의 반수 카운터. 폰 이동·잡기에서 0 으로 돌아간다. */
    var halfmoveClock: Int,
    var fullmoveNumber: Int,
) {
    fun copy(): ChessPosition =
        ChessPosition(cells.copyOf(), sideToMove, castlingRights, enPassantTarget, halfmoveClock, fullmoveNumber)

    operator fun get(square: ChessSquare): ChessPiece? = ChessCode.piece(cells[square.index].toInt())

    operator fun set(square: ChessSquare, piece: ChessPiece?) {
        cells[square.index] = (if (piece == null) ChessCode.empty else ChessCode.code(piece)).toByte()
    }

    /** 그 색 왕이 선 칸. 없으면 null(검증을 거치지 않은 국면). */
    fun kingSquare(color: ChessColor): ChessSquare? {
        val wanted = ChessCode.king or (if (color == ChessColor.black) ChessCode.blackBit else 0)
        for (index in 0 until 64) if (cells[index].toInt() == wanted) return ChessSquare.of(index)
        return null
    }

    /** 판에 있는 말 전부(칸 순서 a1→h8). */
    val pieces: List<ChessPlacedPiece>
        get() = (0 until 64).mapNotNull { index ->
            val piece = ChessCode.piece(cells[index].toInt()) ?: return@mapNotNull null
            ChessPlacedPiece(ChessSquare.of(index)!!, piece)
        }

    /** 카운터가 엔진이 **더해도 넘치지 않는** 범위인가(손으로 짠 판의 마지막 그물). */
    internal val hasCountableCounters: Boolean
        get() = halfmoveClock in 0..maxCountableCounter && fullmoveNumber in 1..maxCountableCounter

    /**
     * 카운터가 **한 판에서 실제로 나올 수 있는 값**인가(파서가 보는 자리). ① 반수는 지금까지 둔 반수를 넘을 수 없다 ② 앙파상 칸이 있으면
     * 반수는 0 이다. 거짓 반수는 **불법 무승부를 합법으로** 만든다.
     */
    val hasReachableCounters: Boolean
        get() {
            if (halfmoveClock < 0 || fullmoveNumber < 1 || fullmoveNumber > maxFullmoveNumber) return false
            val playedHalfmoves = (fullmoveNumber - 1) * 2 + (if (sideToMove == ChessColor.white) 0 else 1)
            if (halfmoveClock > playedHalfmoves) return false
            if (enPassantTarget != null && halfmoveClock != 0) return false
            return true
        }

    override fun equals(other: Any?): Boolean =
        other is ChessPosition && other.cells.contentEquals(cells) && other.sideToMove == sideToMove &&
            other.castlingRights == castlingRights && other.enPassantTarget == enPassantTarget &&
            other.halfmoveClock == halfmoveClock && other.fullmoveNumber == fullmoveNumber

    override fun hashCode(): Int {
        var h = cells.contentHashCode()
        h = 31 * h + sideToMove.hashCode()
        h = 31 * h + castlingRights.hashCode()
        h = 31 * h + (enPassantTarget?.hashCode() ?: -1)
        h = 31 * h + halfmoveClock
        h = 31 * h + fullmoveNumber
        return h
    }

    override fun toString(): String = "ChessPosition($fen)"

    companion object {
        /** FEN 이 받아 주는 수 번호의 위쪽 한계(넘침 방지 — 이론상 가장 긴 대국보다 넉넉하다). */
        const val maxFullmoveNumber: Int = 10_000

        /** 엔진이 셀 수 있는 카운터의 위쪽 한계. */
        internal const val maxCountableCounter: Int = 1_000_000_000

        /** 빈 판(백 차례 · 권리 없음). **검증을 거치지 않는다**(왕이 없을 수도 있다). 부를 때마다 새 값이다(가변 참조라). */
        val empty: ChessPosition
            get() = ChessPosition(ByteArray(64), ChessColor.white, ChessCastlingRights.none, null, 0, 1)

        private val standardTemplate: ChessPosition =
            fromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
                ?: error("초기 배치 FEN 을 못 읽었다 — 파서가 깨졌다")

        /** 초기 배치. 부를 때마다 새 값이다. */
        val standard: ChessPosition get() = standardTemplate.copy()
    }
}

/** 끝난 판의 결과(Swift 연관값 열거 → sealed). null(아직 안 끝남)은 [ChessRules.outcome] 의 반환값으로 말한다. */
sealed interface ChessOutcome {
    data class Checkmate(override val winner: ChessColor) : ChessOutcome
    data object Stalemate : ChessOutcome
    /** 불충분 기물(FIDE 5.2.2 의 '사국'). 기준은 [ChessRules.hasInsufficientMaterial] 하나다. */
    data object InsufficientMaterial : ChessOutcome
    data object FiftyMoveRule : ChessOutcome
    data object ThreefoldRepetition : ChessOutcome

    val isDraw: Boolean get() = this !is Checkmate
    val winner: ChessColor? get() = null
}

/**
 * 수 하나가 판에 남기는 것 전부. **앙파상은 도착 칸이 아닌 칸의 폰을 집어가고, 캐슬링은 룩도 함께 움직인다**.
 */
data class ChessMoveEffect(
    val move: ChessMove,
    val piece: ChessPiece,
    val captured: ChessPiece?,
    val capturedSquare: ChessSquare?,
    /** 캐슬링일 때 룩이 간 길. */
    val rookMove: ChessMove?,
    val isEnPassant: Boolean,
    val isDoublePawnPush: Boolean,
    val isCastling: Boolean,
    val isPromotion: Boolean,
    val after: ChessPosition,
)

/** [ChessRules.perftDivide] 의 한 줄(Swift 튜플 `(move:, nodes:)`). */
data class ChessPerftDivideRow(val move: ChessMove, val nodes: Int)

// MARK: - 규칙

object ChessRules {
    /**
     * 합법 수 전부. 순서는 **결정적이다**(칸 a1→h8 · 방향 고정 순서 · 승격은 Q R B N) — AI 의 수 정렬과 서버 재현이 같은 순서를 믿는다.
     * 왕이 없는(검증 안 된) 국면이면 빈 목록이다.
     */
    fun legalMoves(position: ChessPosition): List<ChessMove> {
        val engine = ChessEngine.create(position) ?: return emptyList()
        return engine.legalRawMoves().map { it.move }
    }

    /** 차례인 쪽이 체크인가. */
    fun isInCheck(position: ChessPosition): Boolean = isInCheck(position, position.sideToMove)

    fun isInCheck(position: ChessPosition, color: ChessColor): Boolean {
        val engine = ChessEngine.create(position) ?: return false
        return engine.isAttacked(engine.kings[if (color == ChessColor.white) 0 else 1], byBlack = color == ChessColor.white)
    }

    /** 수를 적용한 국면. **합법 수가 아니면 null** — 서버 검증이 이 null 하나로 끝나야 한다. */
    fun apply(move: ChessMove, position: ChessPosition): ChessPosition? {
        val engine = ChessEngine.create(position) ?: return null
        val raw = engine.matchingLegalMove(move) ?: return null
        engine.make(raw)
        return engine.position
    }

    /** 수가 판에 남기는 것 전부(불법이면 null). */
    fun effect(move: ChessMove, position: ChessPosition): ChessMoveEffect? {
        val engine = ChessEngine.create(position) ?: return null
        val raw = engine.matchingLegalMove(move) ?: return null
        val moved = ChessCode.piece(engine.cells[raw.from].toInt())!!
        val undo = engine.make(raw)
        return ChessMoveEffect(
            move = raw.move,
            piece = moved,
            captured = ChessCode.piece(undo.captured),
            capturedSquare = if (undo.captured == ChessCode.empty) null else ChessSquare.of(undo.capturedSquare),
            rookMove = if (undo.rookFrom < 0) null else ChessMove(ChessSquare.of(undo.rookFrom)!!, ChessSquare.of(undo.rookTo)!!),
            isEnPassant = raw.flags and ChessRawMove.enPassant != 0,
            isDoublePawnPush = raw.flags and ChessRawMove.doublePush != 0,
            isCastling = raw.flags and ChessRawMove.castling != 0,
            isPromotion = raw.promotion != 0,
            after = engine.position,
        )
    }

    /**
     * 판정. `repetitionCounts` 는 **`repetitionKey` → 그 국면이 이 판에서 나온 횟수**(지금 국면 포함)다. 안 넘기면 반복은 보지 않는다.
     * 순서가 규칙이다: 수가 없으면 체크메이트/스테일메이트가 **먼저**(FIDE 9.3) → 사국 → 50수 → 3회 반복.
     * 체스판으로 **성립하지 않는 판은 판정이 없다**(null) — 그 가드가 없으면 왕 없는 판이 거짓 스테일메이트(무승부)가 된다.
     */
    fun outcome(position: ChessPosition, repetitionCounts: Map<String, Int> = emptyMap()): ChessOutcome? {
        if (ChessEngine.create(position) == null) return null
        if (legalMoves(position).isEmpty()) {
            return if (isInCheck(position)) ChessOutcome.Checkmate(position.sideToMove.opponent) else ChessOutcome.Stalemate
        }
        if (hasInsufficientMaterial(position)) return ChessOutcome.InsufficientMaterial
        if (position.halfmoveClock >= 100) return ChessOutcome.FiftyMoveRule
        if ((repetitionCounts[position.repetitionKey] ?: 0) >= 3) return ChessOutcome.ThreefoldRepetition
        return null
    }

    /**
     * 불충분 기물 — FIDE 5.2.2 의 사국. ① 폰·룩·퀸이 없고 작은 말이 아예 없다 ② 작은 말이 판 전체에 하나 ③ 나이트가 없고 비숍이
     * **전부 한 색 칸**에 있다(개수·소속을 묻지 않는다). 나이트 둘은 들어가지 않는다(메이트가 나오는 자리가 있다).
     */
    fun hasInsufficientMaterial(position: ChessPosition): Boolean {
        var knights = 0
        var lightBishops = 0
        var darkBishops = 0
        for (index in 0 until 64) {
            val cell = position.cells[index].toInt()
            if (cell == ChessCode.empty) continue
            when (cell and ChessCode.kindMask) {
                ChessCode.king -> continue
                ChessCode.knight -> knights += 1
                ChessCode.bishop -> if (ChessSquare.of(index)!!.isLightSquare) lightBishops += 1 else darkBishops += 1
                else -> return false // 폰·룩·퀸이 하나라도 있으면 사국이 아니다
            }
        }
        if (knights + lightBishops + darkBishops <= 1) return true
        return knights == 0 && (lightBishops == 0 || darkBishops == 0)
    }

    /**
     * `color` 쪽 기물로 **메이트가 나올 수 없는가**(시간패의 FIDE 6.9 판정이 묻는 질문 — 한쪽 기물만 본다).
     * 맨 왕 · 왕+나이트 하나 · 왕+한 색 칸 비숍만이면 true.
     */
    fun hasNoMatingMaterial(position: ChessPosition, color: ChessColor): Boolean {
        val mine = if (color == ChessColor.black) ChessCode.blackBit else 0
        var knights = 0
        var lightBishops = 0
        var darkBishops = 0
        for (index in 0 until 64) {
            val cell = position.cells[index].toInt()
            if (cell == ChessCode.empty || (cell and ChessCode.blackBit) != mine) continue
            when (cell and ChessCode.kindMask) {
                ChessCode.king -> continue
                ChessCode.knight -> knights += 1
                ChessCode.bishop -> if (ChessSquare.of(index)!!.isLightSquare) lightBishops += 1 else darkBishops += 1
                else -> return false
            }
        }
        if (knights + lightBishops + darkBishops == 0) return true
        if (knights == 1 && lightBishops + darkBishops == 0) return true
        return knights == 0 && (lightBishops == 0 || darkBishops == 0)
    }

    /** 지금 **실제로** 앙파상으로 잡을 수 있는가(FIDE 9.2 의 '가능성'). */
    fun hasLegalEnPassantCapture(position: ChessPosition): Boolean {
        val target = position.enPassantTarget ?: return false
        val engine = ChessEngine.create(position) ?: return false
        return engine.legalRawMoves().any { it.flags and ChessRawMove.enPassant != 0 && it.to == target.index }
    }

    /** 수 세기. depth 0 은 1(국면 자신), **음수는 0**이다. */
    fun perft(position: ChessPosition, depth: Int): Int {
        if (depth < 0) return 0
        if (depth == 0) return 1
        val engine = ChessEngine.create(position) ?: return 0
        val buffer = ArrayList<ChessRawMove>(64 * maxOf(depth, 1))
        return engine.perft(depth, buffer)
    }

    /** 첫 수별 하위 노드 수(UCI 사전 순). perft 가 어긋났을 때 어느 수에서 갈렸는지 좁히는 표준 도구다. */
    fun perftDivide(position: ChessPosition, depth: Int): List<ChessPerftDivideRow> {
        if (depth <= 0) return emptyList()
        val engine = ChessEngine.create(position) ?: return emptyList()
        val buffer = ArrayList<ChessRawMove>(64 * maxOf(depth, 1))
        val rows = ArrayList<ChessPerftDivideRow>()
        for (raw in engine.legalRawMoves()) {
            val undo = engine.make(raw)
            rows.add(ChessPerftDivideRow(raw.move, if (depth == 1) 1 else engine.perft(depth - 1, buffer)))
            engine.unmake(undo)
        }
        return rows.sortedWith { a, b -> a.move.uci.compareTo(b.move.uci) }
    }

    /** 깃발이 떨어진 판의 판정(FIDE 6.9). `flagged` 는 시간을 다 쓴 쪽이다. */
    fun timeoutRuling(position: ChessPosition, flagged: ChessColor): ChessTimeoutRuling =
        if (hasNoMatingMaterial(position, flagged.opponent)) ChessTimeoutRuling.DrawByInsufficientMaterial
        else ChessTimeoutRuling.Loss(flagged)
}

// MARK: - 시계 (10분 + 한 수 3초 가산 — 사용자 확정)

/**
 * 한 수를 둔 뒤의 시계 — **세 갈래**다. 하나의 null 로 '시간패'와 '성립하지 않는 입력'을 둘 다 말하면 음수 elapsed 한 번이
 * 사람을 시간패로 끝낸다(음수는 서버 시계 밀림·재시도로 평범하게 나온다).
 */
sealed interface ChessClockStep {
    /** 시간이 남았다 — 가산이 붙은 시계. */
    data class Ticked(override val clock: ChessClock) : ChessClockStep
    /** 남은 시간을 넘겨 썼다. 결과는 기물까지 봐야 갈린다 → [ChessRules.timeoutRuling]. */
    data object Flagged : ChessClockStep
    /** elapsed 가 초 단위 시간이 아니다(음수 · NaN · 무한). **시간패가 아니다**. */
    data object InvalidElapsed : ChessClockStep

    /** 시간이 남았을 때의 시계(그 밖에는 null). */
    val clock: ChessClock? get() = null
}

/** 깃발이 떨어졌을 때의 결과 — **FIDE 6.9**. 상대가 어떤 수순으로도 메이트할 수 없으면 무승부다. */
sealed interface ChessTimeoutRuling {
    /** 깃발이 떨어진 쪽의 패. */
    data class Loss(val flagged: ChessColor) : ChessTimeoutRuling
    /** 상대가 메이트할 기물이 없다 — 무승부. */
    data object DrawByInsufficientMaterial : ChessTimeoutRuling

    val isDraw: Boolean get() = this == DrawByInsufficientMaterial
    val winner: ChessColor? get() = (this as? Loss)?.flagged?.opponent
}

/**
 * 1:1 체스 시계. 단위는 **초**다. 시간패는 시계가 판정하므로 [ChessOutcome] 에 없다(판정 주체가 다르다).
 */
data class ChessClock(var whiteSeconds: Double, var blackSeconds: Double, val incrementSeconds: Double) {
    /** Swift `ChessClock(initialSeconds:incrementSeconds:)`. */
    constructor(
        initialSeconds: Double = ChessClock.initialSeconds,
        incrementSeconds: Double = ChessClock.incrementSeconds,
    ) : this(initialSeconds, initialSeconds, incrementSeconds)

    fun remaining(color: ChessColor): Double = if (color == ChessColor.white) whiteSeconds else blackSeconds

    /**
     * `elapsed` 초를 쓰고 수를 둔 뒤의 시계. 넘겨 썼으면 Flagged, elapsed 가 시간이 아니면 InvalidElapsed.
     * 가산을 먼저 더하지 않는다(가산은 수를 **둔 뒤에만** 붙는다 — 먼저 더하면 시간패가 가려진다).
     */
    fun afterMove(color: ChessColor, elapsed: Double): ChessClockStep {
        if (!elapsed.isFinite() || elapsed < 0) return ChessClockStep.InvalidElapsed
        if (elapsed > remaining(color)) return ChessClockStep.Flagged
        val next = copy()
        val left = remaining(color) - elapsed + incrementSeconds
        if (color == ChessColor.white) next.whiteSeconds = left else next.blackSeconds = left
        return ChessClockStep.Ticked(next)
    }

    /** 아직 두지 않은 쪽이 `elapsed` 초를 썼을 때 시간패인가. **null 은 '성립하지 않는 입력'**. [afterMove] 와 같은 답을 한다. */
    fun hasFlagged(color: ChessColor, elapsed: Double): Boolean? {
        if (!elapsed.isFinite() || elapsed < 0) return null
        return elapsed > remaining(color)
    }

    companion object {
        // INV-ChessRules-b65c9524 이식: 서버 `chess_initial_ms()` 와 같은 숫자여야 한다(600 × 1000 = 600000). 한쪽만 고치면 로비를 읽기 전의
        //   캡션·로봇 판 시계가 서버와 갈린다 — Swift `V0348ChessClockTenMinuteTests` 가 마이그레이션과 대조하고, Kotlin 은 골든
        //   `chess/outcome` 의 clock.initialMs(Swift 값)와 대조한다(ChessOutcomeGoldenTest).
        /** 기본 설정(사용자 확정): **10분** + 한 수 3초 가산. */
        const val initialSeconds: Double = 600.0
        const val incrementSeconds: Double = 3.0

        /** 같은 값의 ms 판(서버와 같은 단위). Swift `Int(initialSeconds * 1000)`(0 쪽 버림). */
        val initialMs: Int get() = (initialSeconds * 1000).toInt()
    }
}

// MARK: - 내부 표현

/** 칸 값: 0 빈칸, 하위 3비트 종류(1 폰 · 2 나이트 · 3 비숍 · 4 룩 · 5 퀸 · 6 킹), 비트 3 색(0 백 · 8 흑). */
internal object ChessCode {
    const val empty = 0
    const val pawn = 1
    const val knight = 2
    const val bishop = 3
    const val rook = 4
    const val queen = 5
    const val king = 6
    const val blackBit = 8
    const val kindMask = 7

    val promotionCodes: IntArray = intArrayOf(queen, rook, bishop, knight)

    fun code(kind: ChessPieceKind): Int = when (kind) {
        ChessPieceKind.pawn -> pawn
        ChessPieceKind.knight -> knight
        ChessPieceKind.bishop -> bishop
        ChessPieceKind.rook -> rook
        ChessPieceKind.queen -> queen
        ChessPieceKind.king -> king
    }

    fun code(piece: ChessPiece): Int = code(piece.kind) or (if (piece.color == ChessColor.black) blackBit else 0)

    fun kind(cell: Int): ChessPieceKind? = when (cell and kindMask) {
        pawn -> ChessPieceKind.pawn
        knight -> ChessPieceKind.knight
        bishop -> ChessPieceKind.bishop
        rook -> ChessPieceKind.rook
        queen -> ChessPieceKind.queen
        king -> ChessPieceKind.king
        else -> null
    }

    fun piece(cell: Int): ChessPiece? {
        if (cell == empty) return null
        val kind = kind(cell) ?: return null
        return ChessPiece(if ((cell and blackBit) == 0) ChessColor.white else ChessColor.black, kind)
    }
}

/** 미리 깐 이동표. 판 경계를 **표에서 미리 뺐다**. */
internal object ChessTables {
    /** 칸당 최대 8칸, 뒤는 -1 로 끝난다. */
    val knight: IntArray = hops(arrayOf(1 to 2, 2 to 1, 2 to -1, 1 to -2, -1 to -2, -2 to -1, -2 to 1, -1 to 2))
    val king: IntArray = hops(arrayOf(0 to 1, 1 to 1, 1 to 0, 1 to -1, 0 to -1, -1 to -1, -1 to 0, -1 to 1))

    /** 방향 0…3 직선(룩·퀸), 4…7 대각(비숍·퀸). **공격 판정이 이 순서를 믿는다**. */
    val rayDeltas: Array<Pair<Int, Int>> = arrayOf(0 to 1, 0 to -1, 1 to 0, -1 to 0, 1 to 1, 1 to -1, -1 to 1, -1 to -1)

    /** `rays[(square * 8 + direction) * 7 + step]`. 각 줄은 -1 로 끝난다. */
    val rays: IntArray = IntArray(64 * 8 * 7) { -1 }.also { table ->
        for (square in 0 until 64) {
            val file = square and 7
            val rank = square shr 3
            for ((direction, delta) in rayDeltas.withIndex()) {
                var step = 0
                var nextFile = file + delta.first
                var nextRank = rank + delta.second
                while (nextFile in 0 until 8 && nextRank in 0 until 8) {
                    table[(square * 8 + direction) * 7 + step] = nextRank * 8 + nextFile
                    step += 1
                    nextFile += delta.first
                    nextRank += delta.second
                }
            }
        }
    }

    /** 폰이 잡는 두 쪽(파일 증감). */
    val pawnCaptureSides: IntArray = intArrayOf(-1, 1)

    private fun hops(deltas: Array<Pair<Int, Int>>): IntArray {
        val table = IntArray(64 * 8) { -1 }
        for (square in 0 until 64) {
            val file = square and 7
            val rank = square shr 3
            var slot = 0
            for (delta in deltas) {
                val nextFile = file + delta.first
                val nextRank = rank + delta.second
                if (nextFile !in 0 until 8 || nextRank !in 0 until 8) continue
                table[square * 8 + slot] = nextRank * 8 + nextFile
                slot += 1
            }
        }
        return table
    }
}

/** 엔진 안에서 도는 수. 공개 [ChessMove] 로는 담을 수 없는 것(두 칸 전진·앙파상·캐슬링 표시)을 비트로 들고 다닌다. */
internal data class ChessRawMove(val from: Int, val to: Int, val promotion: Int, val flags: Int) {
    val move: ChessMove
        get() = ChessMove(ChessSquare.of(from)!!, ChessSquare.of(to)!!, if (promotion == 0) null else ChessCode.kind(promotion))

    companion object {
        const val doublePush = 1
        const val enPassant = 2
        const val castling = 4
    }
}

/** 되돌리기표. */
internal class ChessUndo(
    val move: ChessRawMove,
    var captured: Int,
    var capturedSquare: Int,
    val castling: Int,
    val enPassant: Int,
    val halfmove: Int,
    val fullmove: Int,
    var rookFrom: Int,
    var rookTo: Int,
)

// MARK: - 엔진

/** Swift `struct ChessEngine` — 제자리 make/unmake. [create] 가 실패 가능 생성자다. */
internal class ChessEngine private constructor(
    val cells: ByteArray,
    /** 0 백 · 1 흑. */
    var side: Int,
    var castling: Int,
    /** 앙파상 칸(없으면 -1). */
    var enPassant: Int,
    var halfmove: Int,
    var fullmove: Int,
    /** [백 왕 칸, 흑 왕 칸]. */
    val kings: IntArray,
) {
    val position: ChessPosition
        get() = ChessPosition(
            cells.copyOf(),
            if (side == 0) ChessColor.white else ChessColor.black,
            ChessCastlingRights(castling),
            if (enPassant >= 0) ChessSquare.of(enPassant) else null,
            halfmove,
            fullmove,
        )

    // MARK: 공격 판정

    /** `square` 가 `byBlack` 쪽 말에게 공격받는가. 캐슬링의 경유 칸 검사도 이 함수 하나로 한다. */
    fun isAttacked(square: Int, byBlack: Boolean): Boolean {
        val attacker = if (byBlack) ChessCode.blackBit else 0
        val file = square and 7
        val rank = square shr 3

        // 폰: 흑 폰은 아래로 잡으므로 square 의 **윗** 줄에, 백 폰은 아랫 줄에 있다.
        val pawnRank = rank + (if (byBlack) 1 else -1)
        if (pawnRank in 0 until 8) {
            val wanted = ChessCode.pawn or attacker
            if (file > 0 && cells[pawnRank * 8 + file - 1].toInt() == wanted) return true
            if (file < 7 && cells[pawnRank * 8 + file + 1].toInt() == wanted) return true
        }

        val wantedKnight = ChessCode.knight or attacker
        for (slot in 0 until 8) {
            val target = ChessTables.knight[square * 8 + slot]
            if (target < 0) break
            if (cells[target].toInt() == wantedKnight) return true
        }

        val wantedKing = ChessCode.king or attacker
        for (slot in 0 until 8) {
            val target = ChessTables.king[square * 8 + slot]
            if (target < 0) break
            if (cells[target].toInt() == wantedKing) return true
        }

        for (direction in 0 until 8) {
            val slider = if (direction < 4) ChessCode.rook else ChessCode.bishop
            val base = (square * 8 + direction) * 7
            for (step in 0 until 7) {
                val target = ChessTables.rays[base + step]
                if (target < 0) break
                val occupant = cells[target].toInt()
                if (occupant == ChessCode.empty) continue
                if ((occupant and ChessCode.blackBit) == attacker) {
                    val kind = occupant and ChessCode.kindMask
                    if (kind == slider || kind == ChessCode.queen) return true
                }
                break // 말에 막혔다 — 이 줄은 끝
            }
        }
        return false
    }

    // MARK: 생성

    /** 유사 합법 수(자기 왕이 열리는지는 아직 안 본다). */
    fun generate(moves: MutableList<ChessRawMove>) {
        val me = if (side == 0) 0 else ChessCode.blackBit
        for (square in 0 until 64) {
            val cell = cells[square].toInt()
            if (cell == ChessCode.empty || (cell and ChessCode.blackBit) != me) continue
            when (cell and ChessCode.kindMask) {
                ChessCode.pawn -> generatePawn(square, me, moves)
                ChessCode.knight -> generateHops(square, ChessTables.knight, me, moves)
                ChessCode.bishop -> generateRays(square, 4, 8, me, moves)
                ChessCode.rook -> generateRays(square, 0, 4, me, moves)
                ChessCode.queen -> generateRays(square, 0, 8, me, moves)
                ChessCode.king -> {
                    generateHops(square, ChessTables.king, me, moves)
                    generateCastles(square, moves)
                }
                else -> Unit
            }
        }
    }

    private fun generateHops(square: Int, table: IntArray, me: Int, moves: MutableList<ChessRawMove>) {
        for (slot in 0 until 8) {
            val target = table[square * 8 + slot]
            if (target < 0) break
            val occupant = cells[target].toInt()
            if (occupant != ChessCode.empty) {
                if ((occupant and ChessCode.blackBit) == me) continue
                // **상대 왕은 집어가지 못한다**(손으로 짠 판에서 왕이 사라져 거짓 무승부가 되는 자리).
                if ((occupant and ChessCode.kindMask) == ChessCode.king) continue
            }
            moves.add(ChessRawMove(square, target, 0, 0))
        }
    }

    private fun generateRays(square: Int, firstDirection: Int, endDirection: Int, me: Int, moves: MutableList<ChessRawMove>) {
        for (direction in firstDirection until endDirection) {
            val base = (square * 8 + direction) * 7
            for (step in 0 until 7) {
                val target = ChessTables.rays[base + step]
                if (target < 0) break
                val occupant = cells[target].toInt()
                if (occupant == ChessCode.empty) {
                    moves.add(ChessRawMove(square, target, 0, 0))
                    continue
                }
                // 상대 왕은 집어가지 못한다 — 줄은 그 칸에서 막히고 잡기만 빠진다.
                if ((occupant and ChessCode.blackBit) != me && (occupant and ChessCode.kindMask) != ChessCode.king) {
                    moves.add(ChessRawMove(square, target, 0, 0))
                }
                break
            }
        }
    }

    private fun generatePawn(square: Int, me: Int, moves: MutableList<ChessRawMove>) {
        val isBlack = me != 0
        val forward = if (isBlack) -8 else 8
        val startRank = if (isBlack) 6 else 1
        val rankBeforePromotion = if (isBlack) 1 else 6
        val rank = square shr 3
        val file = square and 7
        val one = square + forward
        // 끝 줄의 폰은 FEN 검증이 막는다. 손으로 짠 판에서만 올 수 있어 여기서 한 번 더 본다.
        if (one < 0 || one >= 64) return

        if (cells[one].toInt() == ChessCode.empty) {
            if (rank == rankBeforePromotion) {
                for (promotion in ChessCode.promotionCodes) moves.add(ChessRawMove(square, one, promotion, 0))
            } else {
                moves.add(ChessRawMove(square, one, 0, 0))
                val two = one + forward
                if (rank == startRank && cells[two].toInt() == ChessCode.empty) {
                    moves.add(ChessRawMove(square, two, 0, ChessRawMove.doublePush))
                }
            }
        }

        for (delta in ChessTables.pawnCaptureSides) {
            val nextFile = file + delta
            if (nextFile < 0 || nextFile >= 8) continue
            val target = one + delta
            val occupant = cells[target].toInt()
            if (occupant != ChessCode.empty) {
                if ((occupant and ChessCode.blackBit) == me) continue
                if ((occupant and ChessCode.kindMask) == ChessCode.king) continue
                if (rank == rankBeforePromotion) {
                    for (promotion in ChessCode.promotionCodes) moves.add(ChessRawMove(square, target, promotion, 0))
                } else {
                    moves.add(ChessRawMove(square, target, 0, 0))
                }
            } else if (target == enPassant) {
                // 잡힐 폰이 실제로 뒤에 있는지 다시 본다(enPassantTarget 은 공개 var 라 한 줄로 위조된다).
                val victim = if (isBlack) target + 8 else target - 8
                if (victim < 0 || victim >= 64 ||
                    cells[victim].toInt() != (ChessCode.pawn or (if (isBlack) 0 else ChessCode.blackBit))
                ) continue
                moves.add(ChessRawMove(square, target, 0, ChessRawMove.enPassant))
            }
        }
    }

    /**
     * 캐슬링. 다섯 조건을 **모두** 본다: 권리 · 룩이 제자리 · 사이가 비었다 · 출발·경유·도착 칸이 공격받지 않는다.
     * b1/b8 이 공격받아도 긴 쪽 캐슬링은 **된다**(킹이 지나지 않는 칸).
     */
    private fun generateCastles(square: Int, moves: MutableList<ChessRawMove>) {
        val isBlack = side == 1
        val home = if (isBlack) 60 else 4
        if (square != home) return
        val rookCode = ChessCode.rook or (if (isBlack) ChessCode.blackBit else 0)
        val kingsideBit = if (isBlack) ChessCastlingRights.blackKingside.rawValue else ChessCastlingRights.whiteKingside.rawValue
        val queensideBit = if (isBlack) ChessCastlingRights.blackQueenside.rawValue else ChessCastlingRights.whiteQueenside.rawValue
        val attackedByBlack = !isBlack

        if (castling and kingsideBit != 0 &&
            cells[home + 1].toInt() == ChessCode.empty && cells[home + 2].toInt() == ChessCode.empty &&
            cells[home + 3].toInt() == rookCode &&
            !isAttacked(home, attackedByBlack) &&
            !isAttacked(home + 1, attackedByBlack) &&
            !isAttacked(home + 2, attackedByBlack)
        ) {
            moves.add(ChessRawMove(home, home + 2, 0, ChessRawMove.castling))
        }
        if (castling and queensideBit != 0 &&
            cells[home - 1].toInt() == ChessCode.empty && cells[home - 2].toInt() == ChessCode.empty &&
            cells[home - 3].toInt() == ChessCode.empty &&
            cells[home - 4].toInt() == rookCode &&
            !isAttacked(home, attackedByBlack) &&
            !isAttacked(home - 1, attackedByBlack) &&
            !isAttacked(home - 2, attackedByBlack)
        ) {
            moves.add(ChessRawMove(home, home - 2, 0, ChessRawMove.castling))
        }
    }

    // MARK: 두기 · 되돌리기

    fun make(move: ChessRawMove): ChessUndo {
        val piece = cells[move.from].toInt()
        val kind = piece and ChessCode.kindMask
        val moverIsBlack = (piece and ChessCode.blackBit) != 0
        val undo = ChessUndo(
            move = move, captured = cells[move.to].toInt(), capturedSquare = move.to,
            castling = castling, enPassant = enPassant, halfmove = halfmove, fullmove = fullmove, rookFrom = -1, rookTo = -1,
        )

        // 앙파상은 **도착 칸이 아닌** 칸의 폰을 집어간다.
        if (move.flags and ChessRawMove.enPassant != 0) {
            val victim = if (moverIsBlack) move.to + 8 else move.to - 8
            undo.captured = cells[victim].toInt()
            undo.capturedSquare = victim
            cells[victim] = ChessCode.empty.toByte()
        }

        cells[move.to] = (if (move.promotion == 0) piece else (move.promotion or (piece and ChessCode.blackBit))).toByte()
        cells[move.from] = ChessCode.empty.toByte()

        if (kind == ChessCode.king) {
            kings[if (moverIsBlack) 1 else 0] = move.to
            if (move.flags and ChessRawMove.castling != 0) {
                val kingside = move.to > move.from
                val rookFrom = if (kingside) move.from + 3 else move.from - 4
                val rookTo = if (kingside) move.from + 1 else move.from - 1
                cells[rookTo] = cells[rookFrom]
                cells[rookFrom] = ChessCode.empty.toByte()
                undo.rookFrom = rookFrom
                undo.rookTo = rookTo
            }
        }

        // 권리 소멸: 킹이 움직였거나(그 색 둘), 네 귀퉁이 칸이 **비거나 잡혔다**.
        if (kind == ChessCode.king) {
            val both = if (moverIsBlack) {
                ChessCastlingRights.blackKingside.rawValue or ChessCastlingRights.blackQueenside.rawValue
            } else {
                ChessCastlingRights.whiteKingside.rawValue or ChessCastlingRights.whiteQueenside.rawValue
            }
            castling = castling and both.inv()
        }
        castling = castling and cornerRight(move.from).inv()
        castling = castling and cornerRight(move.to).inv()

        enPassant = if (move.flags and ChessRawMove.doublePush != 0) (move.from + move.to) / 2 else -1
        halfmove = if (kind == ChessCode.pawn || undo.captured != ChessCode.empty) 0 else halfmove + 1
        if (moverIsBlack) fullmove += 1
        side = side xor 1
        return undo
    }

    fun unmake(undo: ChessUndo) {
        side = side xor 1
        val move = undo.move
        val placed = cells[move.to].toInt()
        val piece = if (move.promotion == 0) placed else (ChessCode.pawn or (placed and ChessCode.blackBit))
        cells[move.from] = piece.toByte()
        // 앙파상이면 도착 칸은 비고 희생 폰이 제자리로 — 잡은 칸이 도착 칸과 같을 때도 한 벌로 맞는다.
        cells[move.to] = ChessCode.empty.toByte()
        cells[undo.capturedSquare] = undo.captured.toByte()

        if ((piece and ChessCode.kindMask) == ChessCode.king) {
            kings[if ((piece and ChessCode.blackBit) != 0) 1 else 0] = move.from
            if (undo.rookFrom >= 0) {
                cells[undo.rookFrom] = cells[undo.rookTo]
                cells[undo.rookTo] = ChessCode.empty.toByte()
            }
        }

        castling = undo.castling
        enPassant = undo.enPassant
        halfmove = undo.halfmove
        fullmove = undo.fullmove
    }

    // MARK: 왕 안전 · 핀

    /** 왕과 적 장거리 말 사이에 **혼자** 끼어 있는 내 말들의 비트 마스크(핀). Swift UInt64 → Long 비트. */
    fun pinnedMask(kingSquare: Int, moverIsBlack: Boolean): Long {
        val me = if (moverIsBlack) ChessCode.blackBit else 0
        var mask = 0L
        for (direction in 0 until 8) {
            val slider = if (direction < 4) ChessCode.rook else ChessCode.bishop
            val base = (kingSquare * 8 + direction) * 7
            var own = -1
            for (step in 0 until 7) {
                val target = ChessTables.rays[base + step]
                if (target < 0) break
                val occupant = cells[target].toInt()
                if (occupant == ChessCode.empty) continue
                if (own < 0) {
                    // 적 말이 먼저 나오면 핀이 아니다.
                    if ((occupant and ChessCode.blackBit) == me) { own = target; continue }
                    break
                }
                if ((occupant and ChessCode.blackBit) != me) {
                    val kind = occupant and ChessCode.kindMask
                    if (kind == slider || kind == ChessCode.queen) mask = mask or (1L shl own)
                }
                break
            }
        }
        return mask
    }

    /** 두고 나서 "내 왕이 열렸는가"를 **다시 봐야 하는** 수인가 — 왕 자신의 수 · 핀 된 말의 수 · 체크 중의 수 · **앙파상**. */
    fun needsKingSafetyCheck(move: ChessRawMove, kingSquare: Int, pins: Long, inCheck: Boolean): Boolean =
        inCheck ||
            move.from == kingSquare ||
            (pins and (1L shl move.from)) != 0L ||
            (move.flags and ChessRawMove.enPassant) != 0

    // MARK: 합법 수 · 수 세기

    /** 유사 합법 수에서 자기 왕이 열리는 것을 걸러낸 결과. */
    fun legalRawMoves(): List<ChessRawMove> {
        val pseudo = ArrayList<ChessRawMove>(48)
        generate(pseudo)
        val moverIndex = side
        val kingSquare = kings[moverIndex]
        val byBlack = moverIndex == 0
        val inCheck = isAttacked(kingSquare, byBlack)
        val pins = pinnedMask(kingSquare, moverIndex == 1)
        val legal = ArrayList<ChessRawMove>(pseudo.size)
        for (move in pseudo) {
            if (!needsKingSafetyCheck(move, kingSquare, pins, inCheck)) {
                legal.add(move)
                continue
            }
            val undo = make(move)
            if (!isAttacked(kings[moverIndex], byBlack)) legal.add(move)
            unmake(undo)
        }
        return legal
    }

    /** 공개 [ChessMove] 와 짝이 맞는 합법 수. 승격 말까지 같아야 맞는다. */
    fun matchingLegalMove(move: ChessMove): ChessRawMove? {
        val promotion = move.promotion?.let { ChessCode.code(it) } ?: 0
        return legalRawMoves().firstOrNull { it.from == move.from.index && it.to == move.to.index && it.promotion == promotion }
    }

    /** 수 세기. 노드마다 배열을 새로 만들지 않도록 **한 버퍼를 창으로 나눠** 쓴다. */
    fun perft(depth: Int, buffer: ArrayList<ChessRawMove>): Int {
        val start = buffer.size
        generate(buffer)
        val end = buffer.size
        val moverIndex = side
        val kingSquare = kings[moverIndex]
        val byBlack = moverIndex == 0
        val inCheck = isAttacked(kingSquare, byBlack)
        val pins = pinnedMask(kingSquare, moverIndex == 1)
        var total = 0
        var index = start
        while (index < end) {
            val move = buffer[index]
            val verify = needsKingSafetyCheck(move, kingSquare, pins, inCheck)
            val undo = make(move)
            if (!verify || !isAttacked(kings[moverIndex], byBlack)) {
                total += if (depth == 1) 1 else perft(depth - 1, buffer)
            }
            unmake(undo)
            index += 1
        }
        buffer.subList(start, buffer.size).clear()
        return total
    }

    companion object {
        /**
         * 왕이 양쪽에 **하나씩 있어야** 엔진이 선다(없으면 null). 카운터도 같은 자리에서 본다(더하면 넘치는 값으로는 돌지 않는다).
         * 국면의 칸은 **복사**한다(Swift 의 값 복사와 같은 뜻 — 들어온 국면을 고치지 않는다).
         */
        fun create(position: ChessPosition): ChessEngine? {
            if (!position.hasCountableCounters) return null
            val cells = position.cells.copyOf()
            val found = intArrayOf(-1, -1)
            for (square in 0 until 64) {
                val cell = cells[square].toInt()
                if ((cell and ChessCode.kindMask) != ChessCode.king) continue
                val index = if ((cell and ChessCode.blackBit) == 0) 0 else 1
                if (found[index] >= 0) return null // 왕이 둘이면 판정이 뜻을 잃는다
                found[index] = square
            }
            if (found[0] < 0 || found[1] < 0) return null
            return ChessEngine(
                cells = cells,
                side = if (position.sideToMove == ChessColor.white) 0 else 1,
                castling = position.castlingRights.rawValue,
                enPassant = position.enPassantTarget?.index ?: -1,
                halfmove = position.halfmoveClock,
                fullmove = position.fullmoveNumber,
                kings = found,
            )
        }

        private fun cornerRight(square: Int): Int = when (square) {
            0 -> ChessCastlingRights.whiteQueenside.rawValue
            7 -> ChessCastlingRights.whiteKingside.rawValue
            56 -> ChessCastlingRights.blackQueenside.rawValue
            63 -> ChessCastlingRights.blackKingside.rawValue
            else -> 0
        }
    }
}
