// 원본: Sources/CheckMobileKit/Games/GamesMiniGamePause.swift:14-30 @ de5c153b
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind

/**
 * 폰 미니게임 일시정지의 **게임별 표**(전이는 [MiniGamePauseState], 시계·임시 항목은 [GamesMiniGameHub]).
 *
 * | 게임 | 앱 내림 | [그만두기]·뒤로 | 5분 상한 | 임시 항목 |
 * | 테트리스·길건너 | 자동 정지 | 여기까지 확정 | 있음, 넘으면 확정 | 있음 |
 * | 플래피·타이밍 바 | 자동 정지 | 버림 | 없음 | 없음 |
 *
 * 맥 표([MiniGamePauseState.quittingKeepsTheScore])와 **플래피만 다르다**: 맥은 접어도 그 점수가 남고, 폰은 사용자 답으로 버린다(2026-11-01 "지금처럼 버림").
 * 그래서 코어 규칙에 두지 않았다.
 */
object GamesMiniGamePausePolicy {
    /**
     * 판을 접었을 때 그 점수가 남는가. `GamesPlayController.endRound()` 의 갈래와 같아야 한다(시험이 엔진을 돌려 맞춰 본다).
     * **게임이 늘면 여기서 멈춰 서서 그 게임의 `endRound()` 갈래를 정해라.** 기본 가지를 두지 않는 이유다.
     */
    fun quittingKeepsTheScore(kind: MiniGameKind): Boolean = when (kind) {
        MiniGameKind.tetris, MiniGameKind.crossy -> true
        MiniGameKind.timingBar, MiniGameKind.flappy -> false
    }

    /**
     * 5분 상한을 거는가. 맥과 같은 원칙이다 — 상한이 하는 일은 판을 접는 것이므로, **접어도 기록이 남는 게임에만** 건다.
     * 안 남는 게임에 걸면 점수를 건지는 장치가 아니라 판을 없애는 장치가 된다. 상한이 없는 판은 토큰이 30분에 늙으면 끝낼 때 `GamesMiniGameText.submitTokenDead` 로 끝난다(허브 `recordScore`).
     */
    fun capApplies(kind: MiniGameKind): Boolean = quittingKeepsTheScore(kind)
}
