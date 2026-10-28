// 원본: Sources/check/MiniGamePanel.swift:466-604(CheckMiniGameWindowView.PauseState — 맥 미니게임 창의 일시정지) @ 1b8260d
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind

/**
 * 미니게임 **자동 일시정지** 상태(G §8-2 — "창이 키를 잃으면 일시정지, 5분 상한 유지. `PauseState` 전이 표를 W2-e 골든으로,
 * W4-b(Windows 창 포커스·Android ON_PAUSE)에 같은 전이"). 맥 0.3.62 의 허브 화면 상태를 순수 값으로 옮겼다 — 골든 `pause/transitions`
 * 가 Swift 와 같은 전이를 잰다.
 *
 * 왜 화면(허브)이 정지의 주인인가: 정지 중에는 판을 못 들여다보게 캔버스를 통째로 가려야 하는데(순위표가 걸린 게임에서 멈춰 놓고 다음 기둥을
 * 외우는 것이 이득이면 안 된다), 그 스크림을 게임마다 그리면 두 벌이 된다. 게임은 [isFrozen] 한 값만 읽는다.
 *
 * Android 몫(W4-b 가 배선한다): 폰은 background 가 곧 `endRound()`(테트리스 확정 · 나머지 버림 — `GamesPlayController`)라 이 표를 쓰는 곳은
 * **창이 키를 잃는** 자리(데스크톱 플라이아웃 · Android 멀티 창 ON_PAUSE 처럼 앱이 살아 있는 채로 초점을 잃는 경우)다. 전이는 맥과 한 벌이다.
 * 맥의 ESC 판정(`escaped(eventWindow:gameWindow:isPlaying:)`)은 NSWindow 객체 대조라 옮기지 않는다 — 그 규칙 한 벌인 [toggled] 를 쓴다.
 */
sealed interface MiniGamePauseState {
    data object None : MiniGamePauseState
    data object Paused : MiniGamePauseState

    /** 재개 카운트다운(3 → 2 → 1). 이 동안에도 판은 **얼어 있다** — 안 그러면 정지로 얻은 리듬 이점이 남는다. */
    data class Resuming(val remaining: Int) : MiniGamePauseState

    /** 판이 얼어 있는가(= `MiniGameHost.isPaused`). 카운트다운 중에도 참이다. */
    val isFrozen: Boolean get() = this != None

    /**
     * 정지 카드(이어하기·그만두기)가 떠 있는가. **화면이 실제로 이 값으로 분기한다** — 시험만 부르고 화면은 [countdown] == null 로 따로
     * 판정하면, 상태가 하나 더 생기는 날 시험은 초록인 채 화면만 갈린다.
     */
    val showsCard: Boolean get() = this == Paused

    /** 카운트다운 숫자(아니면 null). */
    val countdown: Int? get() = (this as? Resuming)?.remaining

    /**
     * [일시정지] 버튼과 ESC(뒤로) 가 공유하는 전이. **진행 중일 때만** 정지할 수 있다 — 시작 전·결과 화면에서 얼리면 클릭이 안 먹는 화면이 된다.
     */
    fun toggled(isPlaying: Boolean): MiniGamePauseState = when (this) {
        None -> if (isPlaying) Paused else None
        Paused -> Resuming(COUNTDOWN_START)
        is Resuming -> Paused          // 카운트다운 중 ESC 는 다시 정지(취소)
    }

    /**
     * **창이 키를 잃었을 때**의 전이(0.3.62 — 실사용 제보 "테트리스 일시정지하고 다른 창을 클릭하면 아예 끝나버려요"의 수리). [toggled] 를
     * 재사용하지 않는 이유는 **방향이 하나**라는 것이다 — 키 상실은 언제나 '얼린다'이고 절대 풀지 않는다. [toggled] 를 그대로 쓰면 이미 정지해 둔
     * 판이 키를 잃는 순간 `Resuming` 으로 **풀려** 안 보이는 창에서 3-2-1 이 흐른다.
     *
     * null 은 "아무 일도 하지 않는다"다(지금 상태를 그대로 둔다). 두 자리에서 돌려준다:
     *   · **판이 도는 중이 아니다** — 시작 전·결과 화면에서 얼리면 클릭이 안 먹는 창이 된다.
     *   · **이미 `Paused` 다** — 여기서 또 얼리면 수신처가 정지 감시를 새로 걸고, 그 시계는 1초 수면부터 다시 시작한다. 1초 안에 키를 잃었다
     *     되찾기를 반복하면 누적이 영영 안 올라 5분 상한이 통째로 무력해진다 — 그 상한은 순위 공정성의 보루다.
     */
    fun resigningKey(isPlaying: Boolean): MiniGamePauseState? {
        if (!isPlaying) return null
        return when (this) {
            Paused -> null
            // 카운트다운 중이면 **취소하고 다시 언다.** 안 그러면 안 보이는 창에서 3-2-1 이 흘러 판이 저절로 풀린다.
            None, is Resuming -> Paused
        }
    }

    /** 카운트다운 한 걸음(1초). 3 → 2 → 1 → None. */
    fun steppedDown(): MiniGamePauseState {
        val resuming = this as? Resuming ?: return this
        return if (resuming.remaining <= 1) None else Resuming(resuming.remaining - 1)
    }

    companion object {
        /** 카운트다운 시작값. 3-2-1 이 있어야 정지 직전 화면을 보고 손을 맞춰 두는 이득이 사라진다. */
        const val COUNTDOWN_START: Int = 3

        /**
         * **정지 상한(초).** 넘으면 판을 그 점수로 확정하고 끝낸다(무효가 아니다).
         * 서버는 정지를 **모른다** — 라운드 토큰 만료를 실시간 경과로만 재고 유효기간은 30분이다. 클라가 판 시작 때 토큰을 최대 12분 묵은 것까지
         * 재사용하고 테트리스 한 판이 최장 9분쯤이므로 남는 여유가 **9분 안팎**이다. 5분에서 잘라 그 시점 점수를 확정하면 잃는 것은 "이어서 더 할
         * 기회"뿐이다. 설정 스위치가 아니라 게임 상수다(2026-09-15 '자동 종료는 사용자 스위치로 주지 않는다'). 누적으로 잰다 — 회당이면
         * 정지·재개를 반복해 벽시계를 무한히 늘릴 수 있다.
         */
        const val PAUSE_LIMIT_SECONDS: Int = 5 * 60

        /**
         * **정지 상한을 이 게임에 거는가.** 기준은 게임 이름이 아니라 **"접었을 때 기록이 남는가"** 다 — 상한이 하는 일은 판을 접는 것 하나이고,
         * 접는 결과가 게임마다 다르기 때문이다. 기록이 남는 게임에서 상한은 **점수를 건진다**. 기록이 안 남는 게임에서는 같은 동작이 **판을 없앤다**.
         *   · 테트리스·플래피·길건너 — `interrupt()` 가 결과를 확정한다 → 기록이 남는다.
         *   · 타이밍 바 — `interrupt()` 가 판을 무효로 되돌린다 → 남는 것이 없다(상한을 걸면 이어서 끝낼 기회만 사라진다).
         * **게임이 늘면 여기서 멈춰 서서 그 게임의 `interrupt()` 를 읽어라.** 기본 가지를 두지 않는 이유다.
         */
        fun quittingKeepsTheScore(kind: MiniGameKind): Boolean = when (kind) {
            MiniGameKind.tetris, MiniGameKind.flappy, MiniGameKind.crossy -> true
            MiniGameKind.timingBar -> false
        }
    }
}
