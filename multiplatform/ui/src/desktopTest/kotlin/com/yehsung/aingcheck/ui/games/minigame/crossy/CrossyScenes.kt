// 원본: 없음 — 길건너 시험 장면(합성 픽스처: 시드 + 결정적 '안전한 걸음' 운전수). 운영 데이터 0.
package com.yehsung.aingcheck.ui.games.minigame.crossy

import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame

/**
 * 시드에서 판을 열고, 매 판단 자리(뛰는 중 아님)마다 [lookahead] 프레임 앞을 미리 굴려 **죽지 않는 첫 수**(앞 · 그대로 · 왼 · 오른 · 뒤)를 고른다.
 * 엔진 사본(`copy()`)으로만 미리 보므로 결정적이다 — 같은 시드면 언제나 같은 장면. [until] 이 참이 되면 그 판을 돌려준다.
 * [holdBefore] 가 참인 동안은 앞으로 가지 않는다(기찻길 앞에서 기차를 기다리는 장면).
 */
object CrossyScenes {
    const val DT: Double = 1.0 / 64.0

    fun drive(
        seed: ULong,
        maxFrames: Int = 64 * 60,
        lookahead: Int = 40,
        holdBefore: (CrossyGame) -> Boolean = { false },
        until: (CrossyGame) -> Boolean,
    ): CrossyGame? {
        val g = CrossyGame(seed)
        g.action()
        repeat(maxFrames) {
            if (g.phase != CrossyGame.Phase.Running) return null
            if (g.hop == null && until(g)) return g
            if (g.hop == null) {
                val forwardAllowed = !holdBefore(g)
                val candidates = listOfNotNull(
                    CrossyGame.Direction.forward.takeIf { forwardAllowed }, null,
                    CrossyGame.Direction.left, CrossyGame.Direction.right, CrossyGame.Direction.back,
                )
                val pick = candidates.firstOrNull { safe(g, it, lookahead) }
                if (pick != null) g.input(pick)
            }
            g.step(DT)
        }
        return null
    }

    /** 이 수(null = 그대로)를 두고 [frames] 프레임 굴려도 살아 있는가. */
    private fun safe(g: CrossyGame, direction: CrossyGame.Direction?, frames: Int): Boolean {
        val trial = g.copy()
        if (direction != null) trial.input(direction)
        repeat(frames) {
            trial.step(DT)
            if (trial.death != null) return false
        }
        return true
    }

    /** 여러 시드 중 처음 성공한 장면(시드 목록이 고정이라 결정적이다). */
    fun first(seeds: Iterable<ULong>, holdBefore: (CrossyGame) -> Boolean = { false }, until: (CrossyGame) -> Boolean): CrossyGame =
        seeds.firstNotNullOfOrNull { drive(it, holdBefore = holdBefore, until = until) } ?: error("장면을 못 만들었다")

    fun step(g: CrossyGame, frames: Int): CrossyGame = g.copy().also { c -> repeat(frames) { c.step(DT) } }

    val seeds: List<ULong> = (1uL..40uL).toList()

    fun start(seed: ULong = 7uL): CrossyGame = CrossyGame(seed)

    /** 찻길 위(차가 보이는 줄에 서 있다). */
    fun road(): CrossyGame = first(seeds) { g ->
        g.lane(g.player.row)?.kind == CrossyGame.LaneKind.road && g.lanes.any { it.kind == CrossyGame.LaneKind.road && it.row > g.player.row && it.movers.isNotEmpty() }
    }

    /** 강 위(통나무를 타고 있다). */
    fun river(): CrossyGame = first(seeds) { g -> g.player.riding && g.lane(g.player.row)?.kind == CrossyGame.LaneKind.river }

    /** 기찻길 바로 앞에서 기차가 지나간다(경고등 · 기차가 판 안에 걸쳤다). */
    fun rail(): CrossyGame = first(
        seeds,
        holdBefore = { g -> g.lane(g.player.row + 1)?.kind == CrossyGame.LaneKind.rail },
    ) { g ->
        val next = g.lane(g.player.row + 1)
        val train = next?.train
        next?.kind == CrossyGame.LaneKind.rail && train != null && train.x < 6.0 && train.maxX > 2.0
    }

    /** 끝(결과 카드): 시작 뒤 손을 놓아 '놓쳤어요' 로 끝난 판. */
    fun end(seed: ULong = 7uL): CrossyGame {
        val g = CrossyGame(seed)
        g.action()
        var frames = 0
        while (g.phase != CrossyGame.Phase.Result && frames < 64 * 30) {
            g.step(DT)
            frames += 1
        }
        check(g.phase == CrossyGame.Phase.Result) { "끝 장면이 결과에 들지 않았다" }
        return g
    }
}
