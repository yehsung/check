package com.aingcheck.games.core

import org.junit.Assert.*
import org.junit.Test

class GameTest {
    @Test fun timingScoreEdgesAndWave() {
        assertEquals(100, TimingGame.scoreAt(0.0))
        assertEquals(85, TimingGame.scoreAt(0.5))
        assertEquals(70, TimingGame.scoreAt(1.0))
        assertEquals(0, TimingGame.scoreAt(1.00001))
        assertEquals(1.0, TimingGame.position(0.55, 1.1), 1e-12)
        assertEquals(0.0, TimingGame.position(1.1, 1.1), 1e-12)
    }
    @Test fun timingCompletesOnlyAfterTenResults() {
        val game = TimingGame(42)
        game.tap()
        repeat(10) { i ->
            assertEquals(i + 1, game.round)
            game.tap()
            val count = game.scores.size
            game.tap() // holding the result must not consume another round
            assertEquals(count, game.scores.size)
            repeat(20) { game.step(1.0 / 30) }
        }
        assertTrue(game.finished)
        assertEquals(10, game.scores.size)
        assertTrue(game.score in 0..1000)
        game.tap()
        assertEquals(1, game.round)
        assertEquals(0, game.score)
    }
    @Test fun timingClampsStallsAndIgnoresInvalidTime() {
        val a = TimingGame(7); val b = TimingGame(7)
        a.tap(); b.tap()
        a.step(10.0); b.step(1.0 / 30)
        assertEquals(a.marker, b.marker, 1e-12)
        a.step(Double.NaN); a.step(-1.0)
        assertEquals(a.marker, b.marker, 1e-12)
    }
    @Test fun splitMixMatchesReference() {
        val rng = GameRandom(0)
        assertEquals("e220a8397b1dcdaf", rng.next().toULong().toString(16))
        assertEquals("6e789e6aa1b965f4", rng.next().toULong().toString(16))
    }
    @Test fun flappyFallsAndCannotRestartDuringDeathHold() {
        val game = FlappyGame(42)
        game.tap()
        repeat(180) { game.step(1.0 / 60) }
        assertTrue(game.finished)
        assertEquals(0, game.score)
        game.tap()
        assertTrue(game.playing)
        assertEquals(3, game.pipes.size)
        assertEquals(-317.0, game.velocity, 0.0)
    }
    @Test fun flappyDifficultyCaps() {
        assertEquals(132.0, FlappyGame.gap(0), 0.0)
        assertEquals(96.0, FlappyGame.gap(999), 0.0)
        assertEquals(230.0, FlappyGame.speed(999), 0.0)
        assertEquals(115.0, FlappyGame.spacing(999), 0.0)
    }
    @Test fun staleRoundAndDuplicateSubmissionAreRejected() {
        val gate = RoundGate()
        val old = gate.begin(GameKind.TIMING)
        gate.cancel()
        assertFalse(gate.accept(old, "old-token"))
        val current = gate.begin(GameKind.FLAPPY)
        assertTrue(gate.accept(current, "new-token"))
        assertNull(gate.consume(GameKind.TIMING))
        assertEquals("new-token", gate.consume(GameKind.FLAPPY))
        assertNull(gate.consume(GameKind.FLAPPY))
    }
}
