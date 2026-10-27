// 원본: Tests/checkTests/GoldenExport/games-board/GoldenExportGamesBoardChess.swift(골든 생성기) · Tests/checkTests/ChessPerftTests.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.chess

import com.yehsung.aingcheck.core.rules.renju.asArray
import com.yehsung.aingcheck.core.rules.renju.asObject
import com.yehsung.aingcheck.core.rules.renju.bitsOf
import com.yehsung.aingcheck.core.rules.renju.bool
import com.yehsung.aingcheck.core.rules.renju.cpsText
import com.yehsung.aingcheck.core.rules.renju.intValue
import com.yehsung.aingcheck.core.rules.renju.optBool
import com.yehsung.aingcheck.core.rules.renju.optInt
import com.yehsung.aingcheck.core.rules.renju.optString
import com.yehsung.aingcheck.core.rules.renju.optStringValue
import com.yehsung.aingcheck.core.rules.renju.optStrings
import com.yehsung.aingcheck.core.rules.renju.strings
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.GoldenFnv1a64
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 체스 규칙이 Swift 와 비트로 같다(C§5.1 E8). 숫자가 틀리면 **엔진이 틀린 것이다** — 기대값을 고치지 말고 divide 로 갈린 첫 수를 좁힌다.
 *  · chess/perft    공표 여섯 + 잎 셋의 깊이별 노드 수 · divide(깊이 2)
 *  · chess/fen      FEN 받기·거절 · 정규형 왕복 · 반복 키 · 판정 · 기물 판정 · 글자 경계 알려진 차이(정확한 목록 잠금)
 *  · chess/moves    합법 수 **생성 순서** · SAN · 효과 · 둔 뒤 FEN
 *  · chess/notation SAN·UCI 읽기 표 · 수순 재생 · 반복 장부
 *  · chess/outcome  손으로 놓은 국면(엔진 가드) · 반복 표 판정 · 시계(FIDE 6.9)
 */
class ChessGoldenTest {
    private fun fail(golden: GoldenFile, case: JsonObject, detail: String): Nothing = fail(golden.failure(case.string("id"), detail))

    private companion object {
        /**
         * Swift(확장 그래핌의 첫 스칼라로 공백을 본다)와 Kotlin(코드 포인트)이 갈리는 FEN — **정확히** 이 줄들(골든 knownDivergence 와도 같아야 한다).
         * 공백 스칼라 바로 뒤에 결합 글자(Extend · ZWJ · SpacingMark)가 붙은 입력만이다. 늘거나 줄면 빨강 — 늘면 Kotlin 이 다른 입력에서도 갈린 것이고,
         * 줄면 차이가 메워진 것이니 목록과 ChessFEN.kt 머리 주석을 같이 고친다(G §8-16 ① 의 잠금 꼴).
         */
        val knownFenDivergence = setOf("grapheme-00", "grapheme-01", "grapheme-02", "grapheme-03", "grapheme-04", "grapheme-05", "grapheme-06")

        /** SAN 쪽 같은 차이(국면 case id → 입력). Swift 는 수를 찾고 Kotlin 은 null 이다. */
        val knownSanDivergence = setOf(
            "san-grapheme" to "Nf3 \u0301", "san-grapheme" to " \u0301Nf3", "san-grapheme" to "e4\u00A0\u0301", "san-grapheme" to "e4 \u200D",
            "san-grapheme-castling" to "O-O \u0903",
        )
    }

    private fun outcomeLabel(outcome: ChessOutcome?): String? = when (outcome) {
        null -> null
        is ChessOutcome.Checkmate -> "checkmate:${outcome.winner.rawValue}"
        ChessOutcome.Stalemate -> "stalemate"
        ChessOutcome.InsufficientMaterial -> "insufficientMaterial"
        ChessOutcome.FiftyMoveRule -> "fiftyMoveRule"
        ChessOutcome.ThreefoldRepetition -> "threefoldRepetition"
    }

    private fun timeoutLabel(ruling: ChessTimeoutRuling): String = when (ruling) {
        is ChessTimeoutRuling.Loss -> "loss:${ruling.flagged.rawValue}"
        ChessTimeoutRuling.DrawByInsufficientMaterial -> "draw"
    }

    /** BMP 글자 → 골든의 코드 포인트 16진 목록(소문자, 4자리, 공백 구분 — 생성기 cps 와 같은 꼴). 목록의 입력은 전부 BMP 다. */
    private fun cpsOf(text: String): String {
        require(text.none { it.isSurrogate() }) { "BMP 밖 글자는 이 도우미가 다루지 않는다: $text" }
        return text.map { it.code.toString(16).padStart(4, '0') }.joinToString(" ")
    }

    private fun fnvText(text: String): String {
        val hasher = GoldenFnv1a64()
        for (byte in text.encodeToByteArray()) hasher.add((byte.toInt() and 0xFF).toULong())
        return Golden.hex64Text(hasher.value)
    }

    /** 생성기 `summary(_:)` 와 같은 칸을 같은 이름으로 대조한다. */
    private fun expectSummary(golden: GoldenFile, case: JsonObject, position: ChessPosition) {
        val id = case.string("id")
        fun check(key: String, want: Any?, got: Any?) {
            if (want != got) fail(golden.failure(id, "$key: Swift $want · Kotlin $got (FEN ${position.fen})"))
        }
        check("fen", case.optString("fen"), position.fen)
        check("boardFEN", case.optString("boardFEN"), position.boardFEN)
        check("side", case.optString("side"), position.sideToMove.rawValue)
        check("castling", case.optString("castling"), position.castlingRights.fenText)
        check("enPassant", case.optString("enPassant"), position.enPassantTarget?.notation)
        check("halfmove", case.optInt("halfmove"), position.halfmoveClock)
        check("fullmove", case.optInt("fullmove"), position.fullmoveNumber)
        check("repetitionKey", case.optString("repetitionKey"), position.repetitionKey)
        check("inCheck", case.optBool("inCheck"), ChessRules.isInCheck(position))
        check("legal", case.optInt("legal"), ChessRules.legalMoves(position).size)
        check("outcome", case.optString("outcome"), outcomeLabel(ChessRules.outcome(position)))
        check("insufficient", case.optBool("insufficient"), ChessRules.hasInsufficientMaterial(position))
        check("noMatingWhite", case.optBool("noMatingWhite"), ChessRules.hasNoMatingMaterial(position, ChessColor.white))
        check("noMatingBlack", case.optBool("noMatingBlack"), ChessRules.hasNoMatingMaterial(position, ChessColor.black))
        check("legalEnPassant", case.optBool("legalEnPassant"), ChessRules.hasLegalEnPassantCapture(position))
        check("kings", case.array("kings").optStrings(), listOf(ChessColor.white, ChessColor.black).map { position.kingSquare(it)?.notation })
        check("ascii", case.optString("ascii"), fnvText(position.asciiBoard))
    }

    // MARK: perft

    @Test
    fun perftCountsAndDivideMatchSwift() {
        val golden = Golden.load("chess/perft")
        var nodes = 0L
        var leaves = 0
        for (case in golden.cases) {
            val position = ChessPosition.fromFen(case.string("fen")) ?: fail(golden, case, "FEN 을 못 읽었다")
            if (case.string("id") == "edges") {
                assertEquals(case.int("depth0"), ChessRules.perft(position, 0), "깊이 0 은 1")
                assertEquals(case.int("depthMinus1"), ChessRules.perft(position, -1), "음수는 0")
                assertEquals(case.int("divide0"), ChessRules.perftDivide(position, 0).size)
                val divide1 = case.array("divide1").map { it.asArray().let { row -> row[0].optStringValue() to row[1].intValue() } }
                assertEquals(divide1, ChessRules.perftDivide(position, 1).map { it.move.uci to it.nodes })
                continue
            }
            for ((index, element) in case.array("counts").withIndex()) {
                val want = element.intValue()
                val got = ChessRules.perft(position, index + 1)
                if (got != want) {
                    val divide = ChessRules.perftDivide(position, index + 1).joinToString("\n") { "  ${it.move.uci} ${it.nodes}" }
                    fail(golden, case, "${case.string("label")} 깊이 ${index + 1}: Kotlin $got · Swift $want (차 ${got - want})\n${position.asciiBoard}\n$divide")
                }
                nodes += got
            }
            val divide = case.array("divide2").map { it.asArray().let { row -> row[0].optStringValue() to row[1].intValue() } }
            assertEquals(divide, ChessRules.perftDivide(position, 2).map { it.move.uci to it.nodes }, golden.failure(case.string("id"), "divide 깊이 2"))
            assertEquals(case.optString("outcome"), outcomeLabel(ChessRules.outcome(position)), golden.failure(case.string("id"), "판정"))
            if (case.array("counts").first().intValue() == 0) leaves++
        }
        assertEquals(10, golden.cases.size, "공표 여섯 + 잎 셋 + 경계")
        assertEquals(2, leaves, "합법 수가 0 인 잎 둘(메이트·스테일메이트)")
        assertTrue(nodes > 400_000, "센 노드가 $nodes 개뿐이다")
    }

    // MARK: fen

    @Test
    fun fenParsingCanonicalFormAndSummaryMatchSwift() {
        val golden = Golden.load("chess/fen")
        var accepted = 0
        var rejected = 0
        val diverged = HashSet<String>()
        for (case in golden.cases) {
            val input = cpsText(case.string("input"))
            val position = ChessPosition.fromFen(input)
            val divergence = case.optString("knownDivergence")
            if (divergence != null) {
                // 알려진 차이 줄: Swift 는 받고 Kotlin 은 거절해야 한다. 같아지면(차이가 메워지면) 목록에서 빼야 하므로 빨강.
                if (!case.bool("parsed")) fail(golden, case, "knownDivergence($divergence) 줄인데 Swift 도 거절했다 — 생성기 목록을 다시 본다")
                if (position != null) fail(golden, case, "knownDivergence($divergence) 인데 Kotlin 이 받았다 — 차이가 메워졌으면 목록·ChessFEN.kt 주석을 고친다")
                diverged.add(case.string("id"))
                continue
            }
            if (!case.bool("parsed")) {
                if (position != null) fail(golden, case, "Swift 는 거절했는데 Kotlin 이 받았다: '$input' → ${position.fen}")
                rejected++
                continue
            }
            if (position == null) fail(golden, case, "Swift 는 받았는데 Kotlin 이 거절했다: '$input'")
            expectSummary(golden, case, position)
            // 왕복: 정규 FEN 을 다시 읽으면 같은 국면.
            assertEquals(position, ChessPosition.fromFen(position.fen), "정규 FEN 왕복(${case.string("id")})")
            accepted++
        }
        assertTrue(accepted > 250 && rejected > 40, "받음 $accepted · 거절 $rejected — 두 갈래를 다 재야 한다")
        assertEquals(knownFenDivergence, diverged, "FEN 글자 경계 알려진 차이 목록(골든 knownDivergence 와 Kotlin 목록이 정확히 같아야 한다)")
        val graphemeRows = golden.cases.count { it.string("id").startsWith("grapheme-") }
        assertTrue(graphemeRows > diverged.size, "같아야 하는 글자 경계 줄도 있어야 한다(경계가 넓어지지 않았음을 잰다): $graphemeRows")
    }

    // MARK: moves

    @Test
    fun legalMoveOrderSanAndEffectsMatchSwift() {
        val golden = Golden.load("chess/moves")
        var compared = 0
        for (case in golden.cases) {
            val position = ChessPosition.fromFen(case.string("fen")) ?: fail(golden, case, "FEN")
            val before = position.copy()
            val legal = ChessRules.legalMoves(position)
            val want = case.array("moves")
            assertEquals(want.size, legal.size, golden.failure(case.string("id"), "합법 수 개수 — Kotlin ${legal.map { it.uci }}"))
            for ((index, element) in want.withIndex()) {
                val row = element.asObject()
                val move = legal[index]
                if (row.string("uci") != move.uci) fail(golden, case, "${index}번째 수: Swift ${row.string("uci")} · Kotlin ${move.uci} — 생성 순서")
                val effect = ChessRules.effect(move, position) ?: fail(golden, case, "${move.uci} effect 가 null")
                val flags = (if (effect.isEnPassant) "e" else "") + (if (effect.isDoublePawnPush) "d" else "") +
                    (if (effect.isCastling) "c" else "") + (if (effect.isPromotion) "p" else "")
                val got = listOf(
                    ChessRules.san(move, position), effect.piece.fenCharacter.toString(), effect.captured?.fenCharacter?.toString(),
                    effect.capturedSquare?.notation, effect.rookMove?.uci, flags, effect.after.fen,
                )
                val expected = listOf(
                    row.optString("san"), row.optString("piece"), row.optString("captured"), row.optString("capturedSquare"),
                    row.optString("rook"), row.optString("flags"), row.optString("after"),
                )
                if (got != expected) fail(golden, case, "${move.uci}: Swift $expected · Kotlin $got")
                assertEquals(move, ChessRules.move(row.string("san"), position), "SAN 되읽기 ${row.string("san")}")
                compared++
            }
            assertEquals(before, position, "규칙 함수가 들어온 국면을 고쳤다(${case.string("id")})")
        }
        assertTrue(compared > 1_500, "대조한 수가 $compared 개뿐이다")
    }

    // MARK: notation

    @Test
    fun sanUciReplayAndLedgerMatchSwift() {
        val golden = Golden.load("chess/notation")
        val sanDiverged = HashSet<Pair<String, String>>()
        var san = 0
        var nulls = 0
        var lines = 0
        for (case in golden.cases) {
            when (case.string("kind")) {
                "san" -> {
                    val position = ChessPosition.fromFen(case.string("fen")) ?: fail(golden, case, "FEN")
                    for (element in case.array("entries")) {
                        val row = element.asArray()
                        val input = cpsText(row[0].optStringValue()!!)
                        val want = row[1].optStringValue()
                        val got = ChessRules.move(input, position)?.uci
                        val divergence = if (row.size > 2) row[2].optStringValue() else null
                        if (divergence != null) {
                            // 알려진 차이 줄: Swift 는 수, Kotlin 은 null. 같아지면 목록에서 빼야 하므로 빨강.
                            if (want == null) fail(golden, case, "SAN '$input': knownDivergence($divergence) 인데 Swift 도 null 이다")
                            if (got != null) fail(golden, case, "SAN '$input': knownDivergence($divergence) 인데 Kotlin 이 $got 를 찾았다 — 차이가 메워졌으면 목록·ChessNotation.kt 주석을 고친다")
                            sanDiverged.add(case.string("id") to row[0].optStringValue()!!)
                            continue
                        }
                        if (got != want) fail(golden, case, "SAN '$input': Swift $want · Kotlin $got")
                        san++
                        if (want == null) nulls++
                    }
                }
                "uci" -> for (element in case.array("entries")) {
                    val row = element.asArray()
                    val input = cpsText(row[0].optStringValue()!!)
                    assertEquals(row[1].optStringValue(), ChessMove.fromUci(input)?.uci, golden.failure(case.string("id"), "UCI '$input'"))
                }
                "line" -> {
                    val start = ChessPosition.fromFen(case.string("fen")) ?: fail(golden, case, "FEN")
                    val uci = case.array("uci").strings()
                    val trail = ChessRules.replay(uci, start)
                    val wantTrail = if (case["trail"] is kotlinx.serialization.json.JsonNull) null else case.array("trail").strings()
                    assertEquals(wantTrail, trail?.map { it.fen }, golden.failure(case.string("id"), "replay"))
                    val wantSan = if (case["san"] is kotlinx.serialization.json.JsonNull) null else case.array("san").strings()
                    assertEquals(wantSan, ChessRules.sanLine(uci, start), golden.failure(case.string("id"), "sanLine"))
                    if (trail != null) {
                        val ledger = ChessRepetitionLedger()
                        for ((index, position) in trail.withIndex()) {
                            ledger.record(position)
                            val row = case.array("ledger")[index].asObject()
                            assertEquals(row.int("count"), ledger.count(position), golden.failure(case.string("id"), "장부 ${index}번째 count"))
                            assertEquals(row.optString("outcome"), outcomeLabel(ChessRules.outcome(position, ledger.repetitionCounts)),
                                golden.failure(case.string("id"), "장부 ${index}번째 판정"))
                        }
                    }
                    lines++
                }
                else -> fail(golden, case, "모르는 kind")
            }
        }
        assertTrue(san > 300 && nulls > 30 && nulls < san, "SAN 표 $san 줄 · null $nulls — 받음과 거절을 다 재야 한다")
        val expectedSan = knownSanDivergence.map { (id, text) -> id to cpsOf(text) }.toSet()
        assertEquals(expectedSan, sanDiverged, "SAN 글자 경계 알려진 차이 목록(골든 knownDivergence 와 Kotlin 목록이 정확히 같아야 한다)")
        assertTrue(lines >= 7)
    }

    // MARK: outcome

    @Test
    fun builtPositionsRepetitionAndClockMatchSwift() {
        val golden = Golden.load("chess/outcome")
        val kinds = HashMap<String, Int>()
        for (case in golden.cases) {
            val kind = case.string("kind")
            kinds[kind] = (kinds[kind] ?: 0) + 1
            when (kind) {
                "built" -> {
                    val position = ChessPosition.empty
                    for (text in case.array("pieces").strings()) {
                        position[ChessSquare.parse(text.substring(0, 2))!!] = ChessPiece.fromFenCharacter(text.last())!!
                    }
                    position.sideToMove = ChessColor.fromRawValue(case.string("side"))!!
                    position.castlingRights = ChessCastlingRights(case.int("castlingBits"))
                    position.enPassantTarget = case.optString("enPassant")?.let { ChessSquare.parse(it) }
                    position.halfmoveClock = case.int("halfmove")
                    position.fullmoveNumber = case.int("fullmove")
                    expectSummary(golden, case, position)
                    val id = case.string("id")
                    assertEquals(case.bool("inCheckWhite"), ChessRules.isInCheck(position, ChessColor.white), golden.failure(id, "inCheckWhite"))
                    assertEquals(case.bool("inCheckBlack"), ChessRules.isInCheck(position, ChessColor.black), golden.failure(id, "inCheckBlack"))
                    assertEquals(case.array("moves").strings(), ChessRules.legalMoves(position).map { it.uci }, golden.failure(id, "합법 수"))
                    assertEquals(case.int("perft1"), ChessRules.perft(position, 1), golden.failure(id, "perft1"))
                    assertEquals(case.int("perft2"), ChessRules.perft(position, 2), golden.failure(id, "perft2"))
                    assertEquals(case.string("timeoutWhite"), timeoutLabel(ChessRules.timeoutRuling(position, ChessColor.white)), golden.failure(id, "timeoutWhite"))
                    assertEquals(case.string("timeoutBlack"), timeoutLabel(ChessRules.timeoutRuling(position, ChessColor.black)), golden.failure(id, "timeoutBlack"))
                    assertEquals(case.bool("reachable"), position.hasReachableCounters, golden.failure(id, "hasReachableCounters"))
                    assertEquals(case.array("pieces").strings().sortedBy { ChessSquare.parse(it.substring(0, 2))!!.index },
                        position.pieces.map { it.square.notation + it.piece.fenCharacter }, golden.failure(id, "pieces"))
                }
                "repetition" -> {
                    val position = ChessPosition.fromFen(case.string("fen")) ?: fail(golden, case, "FEN")
                    val count = case.int("count")
                    assertEquals(case.optString("outcome"), outcomeLabel(ChessRules.outcome(position, mapOf(position.repetitionKey to count))),
                        golden.failure(case.string("id"), "반복 키 판정"))
                    assertEquals(case.optString("outcomeOtherKey"), outcomeLabel(ChessRules.outcome(position, mapOf(position.fen to count))),
                        golden.failure(case.string("id"), "다른 키 판정"))
                }
                "clock" -> {
                    val clock = ChessClock(Golden.bits(case.string("whiteBits")), Golden.bits(case.string("blackBits")), Golden.bits(case.string("incrementBits")))
                    for (element in case.array("rows")) {
                        val row = element.asObject()
                        val color = ChessColor.fromRawValue(row.string("color"))!!
                        val elapsed = Golden.bits(row.string("elapsedBits"))
                        val step = clock.afterMove(color, elapsed)
                        val (label, white, black) = when (step) {
                            is ChessClockStep.Ticked -> Triple("ticked", bitsOf(step.clock.whiteSeconds), bitsOf(step.clock.blackSeconds))
                            ChessClockStep.Flagged -> Triple("flagged", null, null)
                            ChessClockStep.InvalidElapsed -> Triple("invalid", null, null)
                        }
                        val detail = "${color.rawValue} elapsed ${row.string("elapsedBits")}"
                        assertEquals(row.string("step"), label, golden.failure(case.string("id"), detail))
                        assertEquals(row.optString("whiteBits"), white, golden.failure(case.string("id"), "$detail 백 시계"))
                        assertEquals(row.optString("blackBits"), black, golden.failure(case.string("id"), "$detail 흑 시계"))
                        assertEquals(row.optBool("hasFlagged"), clock.hasFlagged(color, elapsed), golden.failure(case.string("id"), "$detail hasFlagged"))
                    }
                }
                "clockConstants" -> {
                    assertEquals(case.string("initialSecondsBits"), bitsOf(ChessClock.initialSeconds))
                    assertEquals(case.string("incrementSecondsBits"), bitsOf(ChessClock.incrementSeconds))
                    // INV-ChessRules-b65c9524: 서버 chess_initial_ms() 와 같은 600000 — Swift 값과 대조한다.
                    assertEquals(case.int("initialMs"), ChessClock.initialMs)
                    assertEquals(case.int("maxFullmoveNumber"), ChessPosition.maxFullmoveNumber)
                    assertEquals(case.int("maxCountableCounter"), ChessPosition.maxCountableCounter)
                    val clock = ChessClock()
                    assertEquals(ChessClock.initialSeconds, clock.whiteSeconds)
                    assertEquals(ChessClock.incrementSeconds, clock.incrementSeconds)
                }
                else -> fail(golden, case, "모르는 kind")
            }
        }
        for (kind in listOf("built", "repetition", "clock", "clockConstants")) assertTrue((kinds[kind] ?: 0) > 0, "표 '$kind' 가 비었다")
    }

    /** Kotlin 은 참조라 값 의미를 사본으로 지킨다: 규칙 함수·사본이 원본 국면을 바꾸지 않는다. */
    @Test
    fun positionsAreNotAliased() {
        val position = ChessPosition.standard
        val after = ChessRules.apply(ChessMove.fromUci("e2e4")!!, position)
        assertNotNull(after)
        assertEquals(ChessPosition.standard, position, "apply 가 들어온 국면을 고쳤다")
        val copy = position.copy()
        copy[ChessSquare.parse("e2")!!] = null
        assertEquals(ChessPiece(ChessColor.white, ChessPieceKind.pawn), position[ChessSquare.parse("e2")!!])
        assertNull(copy[ChessSquare.parse("e2")!!])
        val empty1 = ChessPosition.empty
        empty1[ChessSquare.parse("a1")!!] = ChessPiece(ChessColor.white, ChessPieceKind.king)
        assertNull(ChessPosition.empty[ChessSquare.parse("a1")!!], "ChessPosition.empty 가 공유 가변 값이다")
    }
}
