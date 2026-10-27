package com.aingcheck.games.core

import org.junit.Assert.*
import org.junit.Test

/** Oracle is executed Swift code, not a second Kotlin implementation. */
class SwiftParityTest {
    @Test fun deterministicTracesMatchSwift() {
        val resource = requireNotNull(javaClass.getResourceAsStream("/swift-trace.tsv"))
        val rows = resource.bufferedReader().use { it.readLines() }.map { it.split('\t') }
        rows.groupBy { it[0] to it[1].toLong() }.forEach { (key, trace) ->
            val (kind, seed) = key
            val game: Game = if (kind == "timing") TimingGame(seed) else FlappyGame(seed)
            val byFrame = trace.associateBy { it[2].toInt() }
            for (frame in 0..byFrame.keys.max()) {
                when (game) {
                    is TimingGame -> if (frame % 37 == 0) game.tap()
                    is FlappyGame -> {
                        if (!game.playing) game.tap()
                        else if (game.phase == FlappyGame.Phase.RUNNING) {
                            val pipe = game.pipes.firstOrNull { it.x + 44 >= FlappyGame.BIRD_X - 12 }
                            val target = pipe?.centerAt(game.elapsed + 0.2) ?: FlappyGame.HEIGHT / 2
                            if (game.velocity > 0 && game.birdY > target) game.tap()
                        }
                    }
                }
                game.step(1.0 / 60)
                val row = byFrame[frame] ?: continue
                val label = "$kind seed=$seed frame=$frame"
                when (game) {
                    is TimingGame -> {
                        assertEquals(label, row[3].toInt(), game.round)
                        assertEquals(label, row[4].toInt(), game.score)
                        assertEquals(label, row[5].toDouble(), game.marker, 1e-9)
                        assertEquals(label, row[6].toDouble(), game.targetCenter, 1e-9)
                        assertEquals(label, row[7].toDouble(), game.targetWidth, 1e-9)
                        assertEquals(label, row[8].toBoolean(), game.playing)
                        assertEquals(label, row[9].toBoolean(), game.finished)
                    }
                    is FlappyGame -> {
                        assertEquals(label, row[3].toInt(), game.score)
                        assertEquals(label, row[4].toDouble(), game.birdY, 1e-9)
                        assertEquals(label, row[5].toDouble(), game.velocity, 1e-9)
                        assertEquals(label, row[6].toDouble(), game.elapsed, 1e-9)
                        assertEquals(label, row[7].toDouble(), game.pipes.first().x, 1e-9)
                        assertEquals(label, row[8].toDouble(), game.pipes.first().centerAt(game.elapsed), 1e-9)
                        assertEquals(label, row[9].toBoolean(), game.playing)
                        assertEquals(label, row[10].toBoolean(), game.finished)
                    }
                }
            }
        }
    }
}
