// 원본: Sources/CheckCore/ReversiRules.swift(값 타입 — ReversiColor · ReversiBoard · ReversiCounts · ReversiResult · ReversiEndKind · ReversiEndReason ·
//   ReversiIllegalReason · ReversiPly) · Sources/CheckCore/ReversiWire.swift:373-398(ReversiMatchStatus · ReversiPly 디코드) @ 12624739
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingErrorKind
import com.yehsung.aingcheck.core.wire.json.SwiftDecodingException
import com.yehsung.aingcheck.core.wire.json.SwiftRawEnumSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftRawValued
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

// 아잉 뒤집기(내부 이름 reversi — 리버시 규칙의 1:1 미니게임) 의 **와이어에 실리는 값 타입**.
//
// Swift 는 이 타입들을 규칙 파일(ReversiRules.swift)에 두고 와이어 응답이 그대로 디코드한다(판 문자열 → `ReversiBoard`).
// Kotlin 은 모듈 방향이 rules → wire 라 와이어가 규칙을 볼 수 없다 — 아잉 큐브(`RummyFace` · `RummyPoint`)와 같은 선례대로
// **값 타입은 여기(wire/games)에 두고** 판정(합법 수 · 뒤집기 · 끝 · 점수)은 core/rules …/reversi 가 한다.
// 그래서 와이어 디코드가 Swift 와 같은 자리에서 던진다: 판이 64자 '.bw' 가 아니면 응답 전체가 실패한다(판의 권위).
//
// ── 표기(rules.md V-01~V-03) ──
// 칸은 정수 idx(0~63) 하나다: idx = row*8 + col, row 0 = 1행(위), col 0 = a열(왼쪽). 판 문자열은 64자 '.bw'(빈칸 '.', '-' 금지),
// 칸 순서 = idx 순서. 안 표현은 비트보드(ULong 둘, 비트 i = 칸 i)다.
//
// ── 숫자 타입 ──
// 칸 · 수 번호 · 돌 수처럼 규칙과 맞대는 값은 `Int`(Swift `Int`, 값 범위가 작다), 판돈 · 루비 · 시각처럼 다른 1:1 와이어가 `Long` 으로
// 옮긴 값은 `Long`(ReversiWire.kt)이다.

/** Swift `ReversiColor` — 돌 색. 와이어 값 `"black"`·`"white"`. 모르는 글자는 던진다(Swift 합성 Codable). */
@Serializable(with = ReversiColor.Serializer::class)
enum class ReversiColor(override val rawValue: String) : SwiftRawValued {
    black("black"), white("white");

    val opponent: ReversiColor get() = if (this == black) white else black

    /** 판 문자열의 칸 글자: 흑 `b` · 백 `w`. */
    val cell: Char get() = if (this == black) 'b' else 'w'

    object Serializer : SwiftRawEnumSerializer<ReversiColor>("ReversiColor", entries, null)

    companion object {
        /** Swift `ReversiColor(rawValue:)`. */
        fun of(raw: String?): ReversiColor? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * Swift `ReversiBoard` — 8×8 판 한 장. 와이어(Codable)는 64자 문자열 하나다.
 * [black]·[white] 는 안 표현(비트 i = idx i)이다 — 규칙 코어(core/rules …/reversi)가 노드마다 할당 없이 계산하려고 연다.
 * 두 색이 한 칸에 겹치면 만들 수 없다(Swift `assert` 자리 — 규칙이 늘 서로소로 만든다).
 */
@Serializable(with = ReversiBoard.Serializer::class)
data class ReversiBoard(val black: ULong, val white: ULong) {
    init {
        require(black and white == 0uL) { "ReversiBoard: 흑·백이 한 칸에 겹쳤다" }
    }

    /** 64자 '.bw' 문자열(idx 순서). */
    val string: String
        get() {
            val chars = CharArray(CELLS) { '.' }
            for (idx in 0 until CELLS) {
                val bit = 1uL shl idx
                if (black and bit != 0uL) chars[idx] = 'b' else if (white and bit != 0uL) chars[idx] = 'w'
            }
            return chars.concatToString()
        }

    override fun toString(): String = string

    /** 그 칸의 돌. null = 빈칸 또는 범위 밖(0~63 이 아님). */
    operator fun get(idx: Int): ReversiColor? {
        if (idx !in 0 until CELLS) return null
        val bit = 1uL shl idx
        if (black and bit != 0uL) return ReversiColor.black
        if (white and bit != 0uL) return ReversiColor.white
        return null
    }

    /** 판 위 실제 돌 수(V-12). */
    val counts: ReversiCounts
        get() {
            val b = black.countOneBits()
            val w = white.countOneBits()
            return ReversiCounts(black = b.toLong(), white = w.toLong(), empty = (CELLS - b - w).toLong())
        }

    object Serializer : KSerializer<ReversiBoard> {
        override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("ReversiBoard", PrimitiveKind.STRING)

        override fun deserialize(decoder: Decoder): ReversiBoard {
            val d = SwiftDecoding.single(decoder)
            val raw = d.decodeString()
            return fromString(raw)
                ?: throw SwiftDecodingException(SwiftDecodingErrorKind.dataCorrupted, d.path, "판은 64자 '.bw' 문자열이어야 한다(받은 길이 ${raw.length})")
        }

        override fun serialize(encoder: Encoder, value: ReversiBoard) = encoder.encodeString(value.string)
    }

    companion object {
        const val CELLS: Int = 64

        /** 시작 배치(V-04): 백 d4(27)·e5(36), 흑 e4(28)·d5(35). 흑이 먼저 둔다. */
        val start: ReversiBoard = ReversiBoard(black = (1uL shl 28) or (1uL shl 35), white = (1uL shl 27) or (1uL shl 36))

        /** Swift `ReversiBoard(string:)` — 길이·글자가 하나라도 어긋나면 null(대문자 · '-' · 공백 · 다른 글자도 받지 않는다). */
        fun fromString(string: String): ReversiBoard? {
            if (string.length != CELLS) return null
            var black = 0uL
            var white = 0uL
            for ((index, ch) in string.withIndex()) {
                when (ch) {
                    '.' -> Unit
                    'b' -> black = black or (1uL shl index)
                    'w' -> white = white or (1uL shl index)
                    else -> return null
                }
            }
            return ReversiBoard(black, white)
        }
    }
}

/** Swift `ReversiCounts` — 판 위 돌 수(와이어 `discs` 칸 `{black, white, empty}`). 세 칸 모두 필수다(Swift 합성 Codable). */
@Serializable
data class ReversiCounts(
    @SerialName("black") val black: Long,
    @SerialName("white") val white: Long,
    @SerialName("empty") val empty: Long,
)

/** Swift `ReversiResult` — 결과(색 기준). 와이어 `black_win`·`white_win`·`draw`. 모르는 글자는 던진다. */
@Serializable(with = ReversiResult.Serializer::class)
enum class ReversiResult(override val rawValue: String) : SwiftRawValued {
    blackWin("black_win"), whiteWin("white_win"), draw("draw");

    /** 이긴 색. 무승부면 null. */
    val winner: ReversiColor?
        get() = when (this) {
            blackWin -> ReversiColor.black
            whiteWin -> ReversiColor.white
            draw -> null
        }

    object Serializer : SwiftRawEnumSerializer<ReversiResult>("ReversiResult", entries, null)

    companion object {
        /** Swift `ReversiResult(winner:)` — 그 색의 승리. */
        fun of(winner: ReversiColor): ReversiResult = if (winner == ReversiColor.black) blackWin else whiteWin

        fun of(raw: String?): ReversiResult? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** Swift `ReversiEndKind` — 판이 스스로 끝난 까닭(V-10). 분류 순서: 전멸 → 판 가득 → 둘 다 둘 곳 없음. */
@Serializable(with = ReversiEndKind.Serializer::class)
enum class ReversiEndKind(override val rawValue: String) : SwiftRawValued {
    boardFull("board_full"), wipeout("wipeout"), noMoves("no_moves");

    object Serializer : SwiftRawEnumSerializer<ReversiEndKind>("ReversiEndKind", entries, null)
}

/**
 * Swift `ReversiEndReason` — 판이 끝난 까닭(와이어·AI 판 공용). 자연 종료 셋 + 기권·시간 초과 연속 패. 모르는 값은 [unknown] 으로 읽는다
 * (서버가 어휘를 넓혀도 옛 앱의 디코드가 통째로 깨지지 않게).
 */
@Serializable(with = ReversiEndReason.Serializer::class)
enum class ReversiEndReason(override val rawValue: String) : SwiftRawValued {
    boardFull("board_full"), wipeout("wipeout"), noMoves("no_moves"), resign("resign"), abandoned("abandoned"), unknown("unknown");

    object Serializer : SwiftRawEnumSerializer<ReversiEndReason>("ReversiEndReason", entries, unknown)

    companion object {
        /** Swift `ReversiEndReason(_ kind:)` — 자연 종료 분류 → 끝난 까닭. */
        fun of(kind: ReversiEndKind): ReversiEndReason = when (kind) {
            ReversiEndKind.boardFull -> boardFull
            ReversiEndKind.wipeout -> wipeout
            ReversiEndKind.noMoves -> noMoves
        }
    }
}

/** Swift `ReversiIllegalReason` — 불법 수의 까닭(V-06). 판정 순서: 범위 밖 → 이미 돌 → 끼울 돌 없음. */
@Serializable(with = ReversiIllegalReason.Serializer::class)
enum class ReversiIllegalReason(override val rawValue: String) : SwiftRawValued {
    outOfRange("out_of_range"), occupied("occupied"), noFlip("no_flip");

    object Serializer : SwiftRawEnumSerializer<ReversiIllegalReason>("ReversiIllegalReason", entries, null)

    companion object {
        /** Swift `ReversiIllegalReason(rawValue:)` — 모르는 글자는 null. */
        fun of(raw: String?): ReversiIllegalReason? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * Swift `ReversiPly` — 수 기록 한 줄(와이어 `reversi_moves` 행 · AI 판 공용). 패스는 `kind == pass`, `idx == null`, `flipped == []`, `auto == false`.
 * 와이어 모양: `{seq, color, kind:"stone"|"pass", idx:0..63|null, flipped:[…], auto, at_ms}`. `at_ms` 는 화면이 쓰지 않아 읽지 않는다.
 * `flipped`·`auto` 가 빠지면 []·거짓으로 읽는다(pass 행의 모양). seq·color·kind 는 필수다.
 */
@Serializable(with = ReversiPly.Serializer::class)
data class ReversiPly(
    /** 1 부터(패스 포함 기록 번호 — 서버 move_count 와 같은 눈금). */
    val seq: Long,
    val color: ReversiColor,
    val kind: Kind,
    val idx: Long?,
    val flipped: List<Long>,
    /** 시간 초과 자동 착수만 참. 패스 줄은 늘 거짓. */
    val auto: Boolean,
) {
    /** Swift `ReversiPly.Kind`. 와이어 `stone`·`pass`. */
    @Serializable(with = Kind.Serializer::class)
    enum class Kind(override val rawValue: String) : SwiftRawValued {
        stone("stone"), pass("pass");

        object Serializer : SwiftRawEnumSerializer<Kind>("ReversiPly.Kind", entries, null)
    }

    object Serializer : SwiftDecodableSerializer<ReversiPly>("ReversiPly") {
        override fun deserialize(decoder: Decoder): ReversiPly {
            val c = SwiftDecoding.keyed(decoder)
            return ReversiPly(
                // Swift Int 는 64비트다 — 골든의 'big'(2^32) 변형이 그대로 읽혀야 맥 · 폰과 같다(판 8 골든). 화면 · 엔진은 0…64 범위로 접어 쓴다.
                seq = c.long("seq"),
                color = c.decode("color", ReversiColor.serializer()),
                kind = c.decode("kind", Kind.serializer()),
                idx = c.longIfPresent("idx"),
                flipped = c.decodeIfPresent("flipped", ListSerializer(Long.serializer())) ?: emptyList(),
                auto = c.boolIfPresent("auto") ?: false,
            )
        }
    }
}

/** Swift `ReversiMatchStatus` — 판 행의 status. 와이어 글자는 String 으로 받고 여기서 접는다 — 모르는 값은 [unknown]. */
enum class ReversiMatchStatus(override val rawValue: String) : SwiftRawValued {
    pending("pending"), declined("declined"), cancelled("cancelled"), expired("expired"), active("active"), finished("finished"), unknown("unknown");

    companion object {
        /** Swift `ReversiMatchStatus(wire:)`. */
        fun wire(raw: String?): ReversiMatchStatus = entries.firstOrNull { it.rawValue == raw } ?: unknown
    }
}
