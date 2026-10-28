// 원본: Sources/CheckCore/ChessMoveFlight.swift · Sources/CheckCore/ChessStore.swift:684-689(flight · flightGeneration) · :904-955(windowDidHide · windowOcclusionDidChange 의 clearFlight) · :1270-1341(beginFlight · clearFlight) @ 3bd04bd
//
// 체스 말이 **움직이는 동안**을 담는 값(v0.3.44)과, 그 값을 판마다 세우고 거두는 화면 쪽 주인([ChessFlightTracker]).
//
// 0.3.43 의 판은 멈춘 국면 하나를 그려 말이 순간이동하고 잡힌 말이 그 프레임에 사라졌다("따라가기가 ux가 너무 별로야" — 사용자). 그래서 애니메이션을
// **(시작 시각, 길이, 움직이는 말들)을 담은 순수 값**으로 두고, 어떤 프레임이든 `now` 하나로 결정한다(중간 프레임을 밖에서 재현할 수 있어야 잰다).
// 시각·이징·칸 셈만 있다 — 화면 좌표·뒤집기는 [com.yehsung.aingcheck.core.stores.chess.ChessPhoneBoardGeometry], 색은 판 그림.
//
// Kotlin 몫: Swift 는 이 값을 `ChessStore.flight` 에 두고 세 깔때기(1:1 `applyState` · 로봇 `commitAIGame` · 관전 `applyWatch`)가 `beginFlight` 를 불렀다.
// Kotlin 스토어(W2-d)는 그림 전용 칸을 옮기지 않았으므로(C§3.2 — 판·합법 수·시계는 이 값과 무관하게 바이트까지 같다) 화면이 판 하나마다
// [ChessFlightTracker] 를 들고 같은 깔때기 판정(거절 다섯 · 세대 꼬리표 · 거두는 자리)을 그대로 진다. 놓은 말 꼬리표 거두기(c83d5450)는 판정이라
// 스토어 `notePlyAdvanced` 에 남았다.
package com.yehsung.aingcheck.ui.games.chess

import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessPiece
import com.yehsung.aingcheck.core.rules.chess.ChessPieceKind
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.abs

/** 판 위에서 **움직이는 중인 수 하나**. 순수 값 — `now` 하나면 어느 프레임이든 결정적이다. */
data class ChessMoveFlight(
    val matchID: String,
    val ply: Int,
    /** 세대 — 같은 수가 두 번 들어와도 다시 돌지 않게 하는 꼬리표(주인이 올린다). */
    val generation: Int,
    val move: ChessMove,
    val sliders: List<Slider>,
    val knockout: Knockout?,
    val startedAt: SwiftDate,
    val slideDuration: Double,
    val knockoutDelay: Double,
    val knockoutDuration: Double,
    /** 끌어 놓아 이미 도착 칸에 서 있는 말의 칸(v0.3.48). 폰은 탭 2단이라 늘 null 이지만 프레임은 그 칸을 실어 보낸다. */
    val landed: ChessSquare? = null,
) {
    /** 미끄러지는 말. 캐슬링은 둘(왕·룩), 그 밖에는 하나. 승격하는 폰은 **폰으로** 미끄러진다(도착해서 퀸이 된다). */
    data class Slider(val piece: ChessPiece, val from: ChessSquare, val to: ChessSquare)

    /**
     * 판에서 빠지는 말.
     * INV-ChessMoveFlight-9cf10b78 이식: [square] 는 잡힌 말이 서 있던 칸 — **앙파상이면 도착 칸이 아니다**(지나친 폰이 선 칸이다).
     * INV-ChessMoveFlight-eff8277a 이식: 밀려나는 방향은 **판 좌표**(file/rank)로 담는다 — 화면 좌표로 담으면 흑으로 두는 사람(뒤집힌 판)에게 엉뚱한 쪽으로
     *   밀려난다. 뒤집기는 `ChessPhoneBoardGeometry.offset` 하나가 쥔다.
     */
    data class Knockout(val piece: ChessPiece, val square: ChessSquare, val pushFile: Double, val pushRank: Double)

    /**
     * 전체 길이.
     * INV-ChessMoveFlight-caa909cb 이식: 잡는 수는 **잡는 말이 도착한 뒤에도** 잡힌 말이 계속 밀려난다 — 그래서 `max` 다(`slideDuration` 하나로 끊으면
     *   밀림이 중간에 잘려 그 자리에서 사라진 것처럼 보인다).
     */
    val duration: Double get() = maxOf(slideDuration, knockoutDelay + knockoutDuration)

    fun slideProgress(now: SwiftDate): Double {
        val elapsed = now.timeIntervalSince(startedAt)
        if (slideDuration <= 0) return if (elapsed >= 0) 1.0 else 0.0
        return clamp01(elapsed / slideDuration)
    }

    fun knockoutProgress(now: SwiftDate): Double {
        val elapsed = now.timeIntervalSince(startedAt) - knockoutDelay
        if (knockoutDuration <= 0) return if (elapsed >= 0) 1.0 else 0.0
        return clamp01(elapsed / knockoutDuration)
    }

    /**
     * 다 끝났는가(주인이 이걸로 값을 거둔다).
     * INV-ChessMoveFlight-28d5f9a9 이식: 경계는 **열려 있다**(`>`) — 잡기 없는 수는 `duration == slideDuration` 이라 닫으면 t 가 1 인 마지막 프레임이 한 번도
     *   안 그려지고 말이 도착 칸 직전에서 순간이동한다.
     */
    fun isFinished(now: SwiftDate): Boolean = now.timeIntervalSince(startedAt) > duration

    /**
     * 이 시각의 프레임. 다 끝났으면 null(멈춘 판을 그린다).
     * INV-ChessMoveFlight-9b82e8a3 이식: null 조건은 [isFinished] 를 **그대로 부른다** — 두 판정을 따로 적으면 한쪽만 고쳐져 "끝났는데 안 거둬 계속 도는"
     *   또는 "거뒀는데 마지막 프레임이 안 그려진" 상태가 된다.
     */
    fun frame(now: SwiftDate): ChessFlightFrame? {
        if (isFinished(now)) return null
        val slide = easeOut(slideProgress(now))
        val moving = sliders.map { ChessFlightFrame.Moving(it.piece, it.from, it.to, slide) }
        val leaving = knockout?.let { knock ->
            // 잡힌 말은 멈춘 배치(after)에 **없다** — 지연이 지나기 전에도 값을 낸다(안 내면 수가 시작하는 그 프레임에 사라진다).
            val raw = knockoutProgress(now)
            val eased = easeOut(raw)
            ChessFlightFrame.Leaving(
                piece = knock.piece,
                square = knock.square,
                fileOffset = knock.pushFile * KNOCKOUT_PUSH_CELLS * eased,
                rankOffset = knock.pushRank * KNOCKOUT_PUSH_CELLS * eased,
                scale = 1 - (1 - KNOCKOUT_MIN_SCALE) * eased,
                // INV-ChessMoveFlight-6a5bd6dd 이식: **먼저 밀려나고 나중에 흐려진다.** 오프셋·비율은 `eased` 로, 불투명도는 **날 진행도**(raw)로 깎는다 —
                //   같은 `eased` 로 깎으면 easeOut 이 움직임의 87.5% 를 앞 절반에 몰아 밀림이 절반 갔을 때 불투명도가 이미 0.19 가 된다(잡힌 말이 그 자리에서
                //   사라진다 — 고치려는 증상). 날 진행도면 불투명도 1 인 창이 raw ≤ 0.35 = 77ms 이고 밀림의 72.5% 가 불투명한 채로 끝난다.
                //   (기억 easing-must-not-drive-opacity 와 같은 규칙.)
                opacity = minOf(1.0, (1 - clamp01(raw)) / (1 - KNOCKOUT_FADE_START)),
            )
        }
        return ChessFlightFrame(moving = moving, leaving = leaving, hidden = sliders.map { it.to }.toSet(), landed = landed)
    }

    /**
     * 움직인 말이 **이미 도착 칸에 서 있을 때**(끌어 놓았다) 쓰는 사본 — 그 말 하나만 미끄러짐에서 뺀다. 남는 것이 없으면(잡기도 캐슬링도 아닌 수) null.
     * 시간 둘이 달라진다: 잡힘 지연 0(잡는 말은 이미 도착했다) · 미끄러질 말이 없으면 미끄러짐 길이 0.
     */
    fun withMoverLanded(): ChessMoveFlight? {
        val rest = sliders.filterNot { it.from == move.from && it.to == move.to }
        if (rest.size >= sliders.size) return this
        if (rest.isEmpty() && knockout == null) return null
        return copy(sliders = rest, slideDuration = if (rest.isEmpty()) 0.0 else slideDuration, knockoutDelay = 0.0, landed = move.to)
    }

    companion object {
        /** 거리에 무관한 바닥값(한 칸 폰 전진도 0.15s 는 미끄러져야 "놓였다"로 보인다). */
        const val SLIDE_SECONDS_BASE: Double = 0.15
        /** 칸당 더하는 값(룩이 판을 가로지르는데 폰 한 칸과 같은 길이면 총알처럼 보인다). */
        const val SLIDE_SECONDS_PER_SQUARE: Double = 0.025
        /** 뚜껑(0.3s 를 넘으면 차례가 느리게 느껴진다 — 블리츠에서 수마다 쌓인다). */
        const val SLIDE_SECONDS_CAP: Double = 0.30
        /** 잡는 말이 **절반쯤 왔을 때** 잡힌 말이 밀리기 시작한다. */
        const val KNOCKOUT_DELAY_FRACTION: Double = 0.45
        const val KNOCKOUT_SECONDS: Double = 0.22
        const val KNOCKOUT_PUSH_CELLS: Double = 0.55
        const val KNOCKOUT_MIN_SCALE: Double = 0.55
        const val KNOCKOUT_FADE_START: Double = 0.35

        /** 체비셰프 거리로 정한 미끄러짐 길이(한 칸 0.175 · 두 칸 0.20 · 여섯 칸부터 0.30). */
        fun slideSeconds(distance: Int): Double = minOf(SLIDE_SECONDS_CAP, SLIDE_SECONDS_BASE + SLIDE_SECONDS_PER_SQUARE * maxOf(0, distance))

        /** 0 아래·1 위를 자른다(음수·지난 시각이 들어와도 판이 안 깨진다). NaN 은 0. */
        fun clamp01(value: Double): Double = if (value.isNaN()) 0.0 else minOf(1.0, maxOf(0.0, value))

        /** easeOutCubic — `easeOut(0.5) == 0.875`. */
        fun easeOut(t: Double): Double {
            val inverse = 1 - clamp01(t)
            return 1 - inverse * inverse * inverse
        }

        /** 수 하나를 보고 애니메이션을 만든다. 못 만들면 null — 그러면 판은 바로 바뀐다(안전한 폴백). [after] 는 단언용(도착 칸이 비면 안 만든다). */
        fun make(move: ChessMove, before: ChessPosition, after: ChessPosition, matchID: String, ply: Int, generation: Int, startedAt: SwiftDate): ChessMoveFlight? {
            val mover = before[move.from] ?: return null
            // 제자리 수는 애니메이션이 아니다(거리 0 → 밀림 방향 NaN, 자기 칸의 말을 잡힌 말로 센다).
            if (move.from == move.to) return null
            if (after[move.to] == null) return null
            val deltaFile = move.to.file - move.from.file
            val deltaRank = move.to.rank - move.from.rank
            val distance = maxOf(abs(deltaFile), abs(deltaRank))

            // 잡힘 판정 — 도착 칸을 **먼저** 본다(안 그러면 폰의 보통 잡기를 앙파상으로 읽는다).
            var victim: Pair<ChessPiece, ChessSquare>? = null
            val captured = before[move.to]
            if (captured != null) {
                victim = captured to move.to
            } else if (mover.kind == ChessPieceKind.pawn && move.from.file != move.to.file) {
                val passed = ChessSquare.at(move.to.file, move.from.rank)
                val passedPiece = passed?.let { before[it] }
                // INV-ChessMoveFlight-f5a7f6a6 이식: **색을 본다.** 이 갈래의 칸은 `hidden` 에 안 들어간다(도착 칸이 아니다) — 거기 선 말이 **내 편**인데 잡힌 말로
                //   세면 그 말이 멈춘 배치에 서 있는 채로 동시에 밀려나며 흐려진다(같은 말이 둘로 보인다). 서버 FEN 과 파서가 갈린 응답에서만 일을 한다.
                if (passed != null && passedPiece != null && passedPiece.color != mover.color) victim = passedPiece to passed
            }
            val knockout = victim?.let { (piece, square) ->
                // 최대 성분을 ±1 로 정규화 — 잡은 말이 온 방향을 그대로 **잇는다**(나이트는 (±0.5, ±1) 류).
                Knockout(piece, square, deltaFile.toDouble() / distance, deltaRank.toDouble() / distance)
            }

            // 캐슬링 — 왕이 두 칸 가면 룩도 같이 미끄러진다(수는 왕의 두 칸 이동으로만 적힌다 — e1g1).
            val sliders = mutableListOf<Slider>()
            if (mover.kind == ChessPieceKind.king && abs(deltaFile) == 2) {
                val rank = move.from.rank
                val rookFrom = ChessSquare.at(if (deltaFile > 0) 7 else 0, rank)
                val rookTo = ChessSquare.at(if (deltaFile > 0) 5 else 3, rank)
                // INV-ChessMoveFlight-5bb3c8e5 이식: 그 칸에 **그 색 룩이 실제로 있는지** 본다. 없으면(망가진 국면) 룩 조각만 빼고 왕만 미끄러뜨린다 —
                //   여기서 null 로 떨어지면 외통으로 끝난 판의 캐슬링이 통째로 순간이동한다.
                val rook = ChessPiece(mover.color, ChessPieceKind.rook)
                if (rookFrom != null && rookTo != null && before[rookFrom] == rook) sliders.add(Slider(rook, rookFrom, rookTo))
            }
            // INV-ChessMoveFlight-570f4fa5 이식: 왕을 **마지막**에 둔다 — 배열 뒤가 위에 그려지므로 캐슬링에서 둘이 스치는 구간에 왕이 룩 위에 온다.
            sliders.add(Slider(mover, move.from, move.to))

            val slide = slideSeconds(distance)
            return ChessMoveFlight(
                matchID = matchID, ply = ply, generation = generation, move = move, sliders = sliders, knockout = knockout, startedAt = startedAt,
                slideDuration = slide,
                // 잡기가 없으면 둘 다 0 — 안 그러면 잡지도 않은 수가 0.22s 더 돌아 프레임 루프가 쓸데없이 깨어 있다.
                knockoutDelay = if (knockout == null) 0.0 else KNOCKOUT_DELAY_FRACTION * slide,
                knockoutDuration = if (knockout == null) 0.0 else KNOCKOUT_SECONDS,
            )
        }
    }
}

/** 그릴 **한 장**. 판 그림은 이것만 보고 그린다 — 시각·이징·칸 셈이 하나도 그림에 없다. */
data class ChessFlightFrame(
    val moving: List<Moving>,
    val leaving: Leaving?,
    /** 멈춘 배치에서 **그리지 않을** 칸 = 날고 있는 말의 도착 칸(안 빼면 말이 둘로 보인다). 잡힌 칸은 안 들어간다. */
    val hidden: Set<ChessSquare>,
    /** 끌어 놓아 이미 도착한 말의 칸 — 숨기는 칸이 아니라 **그리는 순서만 바뀌는** 칸(맨 위). */
    val landed: ChessSquare? = null,
) {
    /** [t] 는 **이징이 이미 들어간** 0…1. 그림은 두 칸을 선형 보간한다. */
    data class Moving(val piece: ChessPiece, val from: ChessSquare, val to: ChessSquare, val t: Double)

    /** 칸 단위 오프셋(화면 오프셋이 아니다 — 뒤집기는 기하가 입힌다). */
    data class Leaving(val piece: ChessPiece, val square: ChessSquare, val fileOffset: Double, val rankOffset: Double, val scale: Double, val opacity: Double)
}

/**
 * 판 하나의 애니메이션 주인(Swift `ChessStore.flight` · `flightGeneration` · `flightTask` · `beginFlight` · `clearFlight` 의 화면 몫).
 * 판이 바뀔 때마다 [observe] 를 부르면 세 깔때기의 `beginFlight` 와 같은 판정으로 값을 세운다. 거두기는 [clear] 와 [expire].
 *
 * INV-ChessStore-8d22c388 이식: 여기에 **입력 잠금을 걸지 마라.** 말이 날고 있는 동안에도 스토어의 `match.position` 과 `legalMoves` 는 이미 새 것이다 —
 *   이 값은 그림만 읽고, 판의 탭은 이 값을 한 번도 보지 않는다(ChessBoard 의 탭 처리기는 [flight] 를 모른다). 0.2초를 막으면 시간에 쫓겨 빠르게 두는
 *   사람의 수가 씹힌다.
 */
class ChessFlightTracker {
    /** 지금 움직이는 수(없으면 null). 그림만 읽는다. */
    var flight: ChessMoveFlight? = null
        private set

    /**
     * 애니메이션 꼬리표. **늦게 깬 옛 거두기가 새 애니메이션을 지우지 못하게** 하는 유일한 장치다.
     * INV-ChessStore-5a7613eb 이식: 앞 거두기 작업을 끊어도(Swift `try? await Task.sleep` 은 취소를 삼키고 다음 줄로 내려간다) 그 작업이 몸통을 한 번 더 돌 수
     *   있다 — [expire] 는 **꼬리표가 같을 때만** 거둔다. 작업의 취소 여부를 같이 보지 않는 것도 일부러다(두 벌이면 꼬리표 비교가 죽은 가드가 된다).
     */
    var generation: Int = 0
        private set

    private var seenMatchID: String? = null
    private var seenPly: Int? = null
    private var seenPosition: ChessPosition? = null

    /**
     * 판이 바뀌었는지 보고(같은 판 · 같은 수 번호면 아무것도 안 한다) 바뀌었으면 `beginFlight` 판정으로 값을 세운다. 돌려주는 값 = 지금 [flight].
     * 거절 다섯 — **전부 필요하다**: ① 창이 안 보이거나 가려졌다(보이지도 않는 판 때문에 프레임 루프가 깨면 배터리를 먹는다) ② 판이 다르다(화면 전환이지
     * 애니메이션이 아니다) ③ 수 번호가 정확히 1 늘지 않았다(첫 적재 · 따라잡기 · 같은 수의 폴링) ④ 수나 전·후 국면이 없다 ⑤ 파생이 null.
     */
    fun observe(
        matchID: String?, ply: Int, position: ChessPosition?, move: ChessMove?,
        windowVisible: Boolean, windowOccluded: Boolean, now: SwiftDate, landed: Boolean = false,
    ): ChessMoveFlight? {
        if (matchID == seenMatchID && ply == seenPly) return flight
        val previousMatchID = seenMatchID
        val previousPly = seenPly
        val previousPosition = seenPosition
        seenMatchID = matchID
        seenPly = ply
        seenPosition = position
        if (matchID == null) { clear(); return null }
        if (!windowVisible || windowOccluded) return flight
        if (previousMatchID == null || previousMatchID != matchID) return flight
        if (previousPly == null || ply != previousPly + 1) return flight
        if (move == null || previousPosition == null || position == null) return flight
        // INV-ChessStore-9ad35999 이식: 꼬리표는 **파생이 성공한 뒤에** 올린다 — 먼저 올리면 파생이 null 인 수 하나가 돌고 있는 애니메이션의 거두기를 꼬리표만으로
        //   무력화해(그 거두기는 옛 세대가 된다) 그 애니메이션이 영영 거둬지지 않는다(프레임 루프가 계속 돈다).
        val next = generation + 1
        var made = ChessMoveFlight.make(move, previousPosition, position, matchID, ply, next, now) ?: return flight
        if (landed) {
            val rest = made.withMoverLanded()
            if (rest == null) {
                // 움직일 것이 하나도 안 남았다 — 앞 수의 꼬리가 돌고 있었다면 거둔다(그 꼬리가 숨기던 칸에 내 말이 놓였을 수 있다).
                clear()
                return null
            }
            made = rest
        }
        generation = next
        flight = made
        return flight
    }

    /** 다 끝난 애니메이션을 거둔다 — **꼬리표가 같을 때만**(INV-ChessStore-5a7613eb). */
    fun expire(generation: Int) {
        if (this.generation != generation) return
        flight = null
    }

    /**
     * 애니메이션을 거둔다. 거두는 자리: 창 숨김 · 창 가림 · 판 내림(로비로 · 초기화) · 관전 종료.
     * INV-ChessStore-635cb077 이식: 창이 숨으면 **꼭 거둔다** — 안 거두면 0.3초 안에 다시 연 사람에게 끝나던 수의 토막이 다시 미끄러진다.
     * INV-ChessStore-221d2393 이식: 창이 가려질 때도 거둔다(거두는 자리 일곱 번째) — 가려진 판은 그려지지 않으니 날던 수는 보여 줄 사람이 없고, 그대로 두면
     *   꼬리만큼 가림 뒤에서 프레임을 요구한다.
     */
    fun clear() {
        flight = null
    }
}
