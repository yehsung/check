// 원본: 없음 — ChessMoveFlight(값) · ChessFlightTracker(주인) 의 이식 시험. Swift 원본 시험(Tests/checkTests/ChessMoveFlightTests 류)과 같은 숫자를 손으로 적은 표로 잰다.
package com.yehsung.aingcheck.ui.games.chess

import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.fromFen
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessPiece
import com.yehsung.aingcheck.core.rules.chess.ChessPieceKind
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ChessMoveFlightTest {
    // 기준 시각은 0(2001-01-01) — 큰 절대 시각에서는 Double 뺄셈이 경계를 흐린다(0.2 가 0.2000000477 이 된다). 의미(열린 경계 · 늦은 흐려짐)를 잰다.
    private val t0 = SwiftDate.fromReferenceDate(0.0)
    private fun sq(n: String) = ChessSquare.parse(n)!!
    private fun mv(a: String, b: String) = ChessMove(sq(a), sq(b))
    private fun pos(fen: String): ChessPosition = requireNotNull(ChessPosition.fromFen(fen)) { fen }
    private fun at(seconds: Double) = t0.addingTimeInterval(seconds)

    private val start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    private val afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"

    @Test
    fun plainMoveSlidesOnePieceWithDistanceTimedLength() {
        val f = assertNotNull(ChessMoveFlight.make(mv("e2", "e4"), pos(start), pos(afterE4), "m", 1, 1, t0))
        assertEquals(1, f.sliders.size)
        assertNull(f.knockout)
        // 두 칸 = 0.15 + 0.025 × 2 = 0.20, 잡기가 없으면 지연·밀림 길이 0 → 전체 = 미끄러짐.
        assertTrue(abs(f.slideDuration - 0.20) < 1e-12)
        assertEquals(0.0, f.knockoutDelay)
        assertTrue(abs(f.duration - 0.20) < 1e-12)
        assertTrue(abs(ChessMoveFlight.slideSeconds(1) - 0.175) < 1e-12)
        assertTrue(abs(ChessMoveFlight.slideSeconds(6) - 0.30) < 1e-12)
        assertTrue(abs(ChessMoveFlight.slideSeconds(7) - 0.30) < 1e-12)
        assertEquals(setOf(sq("e4")), f.frame(at(0.1))!!.hidden)
    }

    @Test
    fun finishedBoundaryIsOpenAndFrameUsesTheSamePredicate() {
        val f = ChessMoveFlight.make(mv("e2", "e4"), pos(start), pos(afterE4), "m", 1, 1, t0)!!
        // 정확히 끝 시각에는 아직 끝나지 않았다(> 경계) — 마지막 프레임(t=1)이 한 번은 그려진다.
        val last = assertNotNull(f.frame(at(f.duration)))
        assertEquals(1.0, last.moving.single().t)
        assertNull(f.frame(at(f.duration + 1e-6)))
        assertEquals(f.isFinished(at(f.duration + 1e-6)), f.frame(at(f.duration + 1e-6)) == null)
        // easeOut(0.5) = 0.875 — 선형과 갈린다.
        assertEquals(0.875, ChessMoveFlight.easeOut(0.5))
        assertEquals(0.0, ChessMoveFlight.clamp01(Double.NaN))
    }

    @Test
    fun captureKnocksTheVictimAlongTheMoverPathAndFadesLate() {
        // 백 퀸 d1 → d7 잡기(흑 폰). 여섯 칸 → 0.30 뚜껑.
        val before = pos("4k3/3p4/8/8/8/8/8/3QK3 w - - 0 1")
        val after = pos("4k3/3Q4/8/8/8/8/8/4K3 b - - 0 1")
        val f = assertNotNull(ChessMoveFlight.make(mv("d1", "d7"), before, after, "m", 1, 1, t0))
        val k = assertNotNull(f.knockout)
        assertEquals(sq("d7"), k.square)
        assertEquals(0.0, k.pushFile)
        assertEquals(1.0, k.pushRank)
        assertTrue(abs(f.knockoutDelay - 0.45 * 0.30) < 1e-12)
        assertTrue(abs(f.duration - (0.45 * 0.30 + 0.22)) < 1e-12, "잡힌 말은 잡는 말이 도착한 뒤에도 밀려난다(max)")
        // 날 진행도 0.35 까지 불투명도 1 — 밀림의 72.5% 가 불투명한 채로 끝난다.
        val atFadeStart = f.frame(at(f.knockoutDelay + 0.22 * 0.35))!!.leaving!!
        assertTrue(abs(atFadeStart.opacity - 1.0) < 1e-9, "불투명도가 이징으로 먼저 깎였다: ${atFadeStart.opacity}")
        assertTrue(atFadeStart.rankOffset > 0.55 * 0.70, "밀림 오프셋 ${atFadeStart.rankOffset}")
        val half = f.frame(at(f.knockoutDelay + 0.11))!!.leaving!!
        assertTrue(abs(half.rankOffset - 0.55 * 0.875) < 1e-9)
        assertTrue(half.opacity > 0.7, "절반에서 불투명도 ${half.opacity}")
        // 지연 전에도 잡힌 말 값을 낸다(안 내면 수가 시작하는 그 프레임에 사라진다).
        assertNotNull(f.frame(at(0.01))!!.leaving)
    }

    @Test
    fun enPassantVictimStandsOnThePassedSquareAndOwnPieceIsNeverAVictim() {
        val before = pos("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
        val after = pos("4k3/8/3P4/8/8/8/8/4K3 b - - 0 1")
        val f = assertNotNull(ChessMoveFlight.make(mv("e5", "d6"), before, after, "m", 1, 1, t0))
        assertEquals(sq("d5"), f.knockout!!.square, "앙파상 잡힌 말은 도착 칸이 아니라 지나친 칸")
        assertTrue(sq("d5") !in f.frame(at(0.05))!!.hidden)
        // 망가진 국면: 지나친 칸에 **내 편** 폰 — 잡힌 말로 세지 않는다.
        val broken = pos("4k3/8/8/3PP3/8/8/8/4K3 w - - 0 1")
        val g = assertNotNull(ChessMoveFlight.make(mv("e5", "d6"), broken, after, "m", 1, 1, t0))
        assertNull(g.knockout)
    }

    @Test
    fun castlingSlidesTheRookFirstAndTheKingLastAndDropsAMissingRook() {
        val before = pos("4k3/8/8/8/8/8/8/4K2R w K - 0 1")
        val after = pos("4k3/8/8/8/8/8/8/5RK1 b - - 1 1")
        val f = assertNotNull(ChessMoveFlight.make(mv("e1", "g1"), before, after, "m", 1, 1, t0))
        assertEquals(listOf(ChessPieceKind.rook, ChessPieceKind.king), f.sliders.map { it.piece.kind }, "왕이 마지막(위에 그려진다)")
        assertEquals(sq("h1"), f.sliders[0].from)
        assertEquals(sq("f1"), f.sliders[0].to)
        val noRook = pos("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        val g = assertNotNull(ChessMoveFlight.make(mv("e1", "g1"), noRook, after, "m", 1, 1, t0))
        assertEquals(listOf(ChessPieceKind.king), g.sliders.map { it.piece.kind })
        assertNull(ChessMoveFlight.make(mv("e1", "e1"), before, after, "m", 1, 1, t0), "제자리 수는 애니메이션이 아니다")
    }

    @Test
    fun landedCopyDropsOnlyTheMover() {
        val before = pos("4k3/3p4/8/8/8/8/8/3QK3 w - - 0 1")
        val after = pos("4k3/3Q4/8/8/8/8/8/4K3 b - - 0 1")
        val f = ChessMoveFlight.make(mv("d1", "d7"), before, after, "m", 1, 1, t0)!!
        val l = assertNotNull(f.withMoverLanded())
        assertTrue(l.sliders.isEmpty())
        assertEquals(0.0, l.knockoutDelay)
        assertEquals(sq("d7"), l.landed)
        val plain = ChessMoveFlight.make(mv("e2", "e4"), pos(start), pos(afterE4), "m", 1, 1, t0)!!
        assertNull(plain.withMoverLanded(), "남는 것이 없으면 null")
    }

    @Test
    fun trackerRejectsTheFiveCasesAndOnlyBumpsTheTagAfterADerivation() {
        val tracker = ChessFlightTracker()
        val s = pos(start)
        val e4 = pos(afterE4)
        // 첫 적재(이전 국면 없음) — 애니메이션 아님.
        assertNull(tracker.observe("m", 0, s, null, windowVisible = true, windowOccluded = false, now = t0))
        // ① 창이 안 보인다 — 판은 나아갔지만 값이 안 선다.
        assertNull(tracker.observe("m", 1, e4, mv("e2", "e4"), windowVisible = false, windowOccluded = false, now = t0))
        assertEquals(0, tracker.generation)
        // ③ 두 수가 한꺼번에(따라잡기) — 안 선다.
        val afterE5 = pos("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        val afterNf3 = pos("rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2")
        assertNull(tracker.observe("m", 3, afterNf3, mv("g1", "f3"), windowVisible = true, windowOccluded = false, now = t0))
        // ② 다른 판 — 화면 전환이지 애니메이션이 아니다.
        assertNull(tracker.observe("other", 4, afterE5, mv("e7", "e5"), windowVisible = true, windowOccluded = false, now = t0))
        // ⑤ 파생이 null(수와 국면이 안 맞는다 — 도착 칸이 빈 국면): 꼬리표가 오르지 않는다.
        tracker.observe("m2", 0, s, null, windowVisible = true, windowOccluded = false, now = t0)
        assertNull(tracker.observe("m2", 1, s, mv("e2", "e4"), windowVisible = true, windowOccluded = false, now = t0))
        assertEquals(0, tracker.generation, "파생이 실패했는데 꼬리표가 올랐다")
        // 정상 — 한 수 나아감.
        tracker.observe("m3", 0, s, null, windowVisible = true, windowOccluded = false, now = t0)
        val f = assertNotNull(tracker.observe("m3", 1, e4, mv("e2", "e4"), windowVisible = true, windowOccluded = false, now = t0))
        assertEquals(1, tracker.generation)
        assertEquals(1, f.generation)
        // 같은 판·같은 수의 다시 그리기(폴링)는 같은 값을 돌려준다(다시 세우지 않는다).
        assertEquals(f, tracker.observe("m3", 1, e4, mv("e2", "e4"), windowVisible = true, windowOccluded = false, now = t0.addingTimeInterval(1.0)))
        // 다음 수가 꼬리표를 민다 — 옛 꼬리표의 거두기는 새 값을 지우지 못한다.
        val g = assertNotNull(tracker.observe("m3", 2, afterE5, mv("e7", "e5"), windowVisible = true, windowOccluded = false, now = t0))
        assertEquals(2, g.generation)
        tracker.expire(1)
        assertEquals(g, tracker.flight, "옛 꼬리표의 거두기가 새 애니메이션을 지웠다")
        tracker.expire(2)
        assertNull(tracker.flight)
        // 창이 숨거나 가려지면 거둔다(clear).
        tracker.observe("m3", 3, afterNf3, mv("g1", "f3"), windowVisible = true, windowOccluded = false, now = t0)
        assertNotNull(tracker.flight)
        tracker.clear()
        assertNull(tracker.flight)
    }

    @Suppress("unused")
    private val keep = ChessPiece(ChessColor.white, ChessPieceKind.pawn)
}
