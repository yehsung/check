// 원본: Sources/CheckCore/MiniGameEngine.swift @ 1b8260d
// 옮긴 것: MiniGameKind · MiniGameCanvas · MiniGameFrameRate · MiniGameInput · MiniGameRandom(= foundation SplitMix64) ·
//          MiniGameStage 의 규칙 몫(id · 이름 · 별 수 · 경계표 · 고르기). 그리기(무대 색 · Backdrop · Projection · Effects ·
//          FrameProbe)와 화면 배선(MiniGameHost — W4-b)은 옮기지 않는다(C§3.2 "—" 행).
package com.yehsung.aingcheck.core.rules.minigame

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame

/** 게임 규칙의 결정적 난수(Swift `MiniGameRandom` — 같은 알고리즘 한 벌을 foundation 이 든다, C§3.2 F-1). */
typealias MiniGameRandom = SplitMix64

/** 미니게임 종류. [rawValue] 는 서버 표 `minigame_scores.game` 의 값과 같다(변경 금지 — 서버 check 제약과 짝). */
enum class MiniGameKind(val rawValue: String) {
    timingBar("timing_bar"),
    flappy("flappy"),

    /** v0.3.38. **맨 뒤에 더한다** — [entries] 순서가 곧 화면 순서라 사이에 끼우면 기존 두 게임의 자리가 밀린다. */
    tetris("tetris"),

    /** v0.3.67 "길건너 아잉이". 테트리스와 같은 이유로 맨 뒤다. 폰에는 아직 없다([phoneCases] 가 거른다). */
    crossy("crossy"),
    ;

    val id: String get() = rawValue

    /** 패널 선택 칩·순위표 제목에 쓰는 이름. */
    val title: String
        get() = when (this) {
            timingBar -> "타이밍 바"
            flappy -> "플래피 아잉"
            tetris -> "테트리스"
            crossy -> "길건너 아잉이"
        }

    /** 종류 칩·시작 카드의 SF Symbol 이름(Material Symbols 대응은 ui 의 SfSymbols 표가 한다). */
    val icon: String
        get() = when (this) {
            timingBar -> "metronome.fill"
            flappy -> "bird.fill"
            tetris -> "square.grid.2x2.fill"
            crossy -> "figure.walk"
        }

    /**
     * 한 판에서 나올 수 있는 최대 점수(클라·서버 동일 — 서버 check 제약 상한). 초과는 업로드하지 않는다.
     *
     * INV-MiniGameEngine-6af97b9b 이식: 테트리스 값은 [com.yehsung.aingcheck.core.rules.tetris.TetrisGame.maxScore] 와
     * 글자 하나까지 같아야 한다 — 업로드 게이트가 초과분을 클램프가 아니라 조용히 버린다. 시험
     * `MiniGameEngineGoldenTest.kindTableMatchesSwift` 가 두 값을 골든(Swift 값)과 함께 묶는다.
     */
    val maxScore: Int
        get() = when (this) {
            timingBar -> 1000
            flappy -> 999
            tetris -> 100_000_000
            crossy -> 5000
        }

    /**
     * 들고 있는 라운드 토큰을 다시 써도 되는 나이(초). 이 나이를 넘기면 새로 받는다.
     *
     * INV-MiniGameEngine-01974aa4 이식: 게임별로 다르다(여유 = 서버 TTL 30분 − 재사용 나이 − 최장 판). 타이밍 바·플래피 20분 ·
     * 테트리스 12분(최장 판 8.7분) · 길건너 2분(끝이 정해지지 않은 판 — 판 도중 갈아 끼우기 [roundTokenMidRunRefreshSeconds] 와 짝).
     */
    val roundTokenReuseSeconds: Double
        get() = when (this) {
            timingBar, flappy -> 20.0 * 60
            tetris -> 12.0 * 60
            crossy -> 2.0 * 60
        }

    /** 판이 도는 도중에 토큰을 갈아 끼우는 나이(초). null 이면 갈아 끼우지 않는다(길건너만 20분). */
    val roundTokenMidRunRefreshSeconds: Double?
        get() = when (this) {
            timingBar, flappy, tetris -> null
            crossy -> 20.0 * 60
        }

    /** 한 줄 규칙 설명(시작 오버레이). */
    val howToPlay: String
        get() = when (this) {
            timingBar -> "움직이는 마커가 밝은 구간에 들어올 때 멈춰 · 10라운드"
            flappy -> "눌러서 점프 · 기둥 사이를 지나갈수록 +1"
            tetris -> "줄을 채워 지워 · 쌓여서 꼭대기에 닿으면 끝"
            crossy -> "한 칸씩 뛰어 앞으로 · 차 · 강 · 기차를 피해"
        }

    /** 조작 안내(하단 스트립·시작 카드). **게임별이다** — 앞 두 게임만 [Companion.controlHint] 를 쓴다. */
    val controlHint: String
        get() = when (this) {
            timingBar, flappy -> Companion.controlHint
            tetris -> "← → 이동 · ↑ 회전 · ↓ 소프트드롭 · 스페이스 하드드롭 · C 홀드"
            crossy -> "↑↓←→ · WASD 로 뛰기 · 클릭·스페이스 앞으로"
        }

    /** 폰에서 보이는 게임인가 — [phoneCases] 의 한 줄 판정. */
    val isPhoneSupported: Boolean get() = this in phoneCases

    companion object {
        /**
         * 타이밍 바·플래피가 공유하는 조작 안내.
         *
         * INV-MiniGameEngine-a21f650a 이식: 이 **정적** 값은 그 두 게임의 시작/다시 카드 문구 전용이다. 다른 자리에서 쓰면 테트리스·
         * 길건너에도 "클릭 또는 스페이스"가 나가 경고 없이 잘못된 안내가 된다 — 인스턴스 [controlHint](`kind.controlHint`)를 써라.
         */
        const val controlHint: String = "클릭 또는 스페이스"

        /** 맥에서 고를 수 있는 게임 — 전부다. */
        val macCases: List<MiniGameKind> = entries.toList()

        /**
         * 폰에서 **보이는** 게임.
         *
         * INV-MiniGameEngine-e50f8752 이식: 플립은 한 줄이 아니다. 여기에 종류를 더하기 전에 ① 서버 마이그레이션이 실서버에 있고
         * ② 딥링크(`AingRoute.MiniGame`)를 같이 넓히고 ③ 폰 화면·조작이 붙어 있어야 한다. 길건너(v0.3.67)는 아직 빠진다(폰 1.0.15 와
         * 같이 — G §8-16, W4-b). 모르는 값을 접지 않으려고 [entries] 는 그대로 둔다(저장값 복원·서버 응답 매핑은 전부를 안다).
         */
        val phoneCases: List<MiniGameKind> = listOf(timingBar, flappy, tetris)

        /** 서버·저장값 rawValue → 종류. 모르면 null(조용히 기본값으로 접지 않는다). */
        fun fromRawValue(raw: String): MiniGameKind? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 논리 좌표 크기(Swift `CGSize` 의 규칙 몫). */
data class MiniGameSize(val width: Double, val height: Double)

/** 논리 좌표 점(Swift `CGPoint` 의 규칙 몫). */
data class MiniGamePoint(val x: Double, val y: Double)

/** 게임 논리 좌표계. 규칙은 언제나 이 크기 안에서 계산하고, 화면은 실제 캔버스에 비율 유지로 맞춘다. */
object MiniGameCanvas {
    const val logicalWidth: Double = 292.0
    const val logicalHeight: Double = 302.0

    /** 게임들이 공유하는 논리 판 크기. */
    val logicalSize: MiniGameSize get() = MiniGameSize(logicalWidth, logicalHeight)

    /** 실제 캔버스 크기에서 논리 좌표를 그릴 배율과 원점(가운데 정렬). 배율은 짧은 축이 정한다. */
    fun transform(size: MiniGameSize, logicalSize: MiniGameSize): Pair<Double, MiniGamePoint> {
        val scale = swiftMin(size.width / logicalSize.width, size.height / logicalSize.height)
        val origin = MiniGamePoint(
            x = (size.width - logicalSize.width * scale) / 2,
            y = (size.height - logicalSize.height * scale) / 2,
        )
        return scale to origin
    }
}

/**
 * 게임 루프가 요구할 프레임 간격을 화면 주사율에서 뽑는다(C§5.1 E6 — 0~500Hz 전수 골든 `framerate/fps`).
 * 규칙 ①~④는 Swift 머리 주석 그대로다: ① 60 이하면 그 값 ② 60 초과면 60 이상 약수 중 가장 작은 것(상한 120 안)
 * ③ 없으면 아래쪽에서 가장 가까운 약수 ④ 그것도 바닥(40) 밑이면 60.
 */
object MiniGameFrameRate {
    const val baselineFPS: Int = 60
    const val maxFPS: Int = 120
    const val minFPS: Int = 40
    const val minPlausibleHz: Int = 24

    /** 요구 간격에서 뺄 여유 — vsync 한 틱의 1%. */
    const val vsyncHeadroom: Double = 0.01

    fun targetFPS(forRefreshRate: Int): Int {
        val hz = forRefreshRate
        if (hz < minPlausibleHz) return baselineFPS
        if (hz <= baselineFPS) return hz
        var above: Int? = null
        var below = 0
        for (divisor in 1..minOf(hz, maxFPS)) {
            if (hz % divisor != 0) continue
            if (divisor >= baselineFPS) {
                if (above == null) above = divisor
            } else {
                below = divisor
            }
        }
        if (above != null) return above
        return if (below >= minFPS) below else baselineFPS
    }

    /** 프레임 루프 상한에 그대로 넘길 값(초). */
    fun minimumInterval(forRefreshRate: Int): Double {
        val hz = forRefreshRate
        val fps = targetFPS(hz)
        if (hz < minPlausibleHz || hz % fps != 0) return 1.0 / fps.toDouble()
        val vsyncsPerFrame = (hz / fps).toDouble()
        return (vsyncsPerFrame - vsyncHeadroom) / hz.toDouble()
    }
}

/**
 * 화면이 게임에 건네는 입력. 클릭·스페이스는 [actionCount] 카운터로, 테트리스 이동·소프트드롭은 눌림, 회전·홀드는 카운터,
 * 길건너 뛰기는 **누른 순서의 꼬리**([recentHops])와 총 횟수([hopCount]) 한 쌍이다.
 *
 * Swift 는 값 타입의 `mutating func recordHop` 이다. Kotlin 은 불변 값으로 두고 [recordHop] 이 **새 값**을 돌려준다
 * (Compose 상태로 그대로 흘릴 수 있게 — 뜻은 같다).
 */
data class MiniGameInput(
    val actionCount: Int = 0,
    val moveLeftHeld: Boolean = false,
    val moveRightHeld: Boolean = false,
    val softDropHeld: Boolean = false,
    val rotateClockwiseCount: Int = 0,
    val rotateCounterClockwiseCount: Int = 0,
    val holdCount: Int = 0,
    /** 뛰기 키가 눌린 총 횟수(늘기만 한다 — Swift `&+=` 처럼 넘치면 감긴다). */
    val hopCount: Int = 0,
    /** 최근 뛰기 키들 — 누른 순서, 길이는 [recentHopLimit] 까지(오래된 것부터 버린다). */
    val recentHops: List<CrossyGame.Direction> = emptyList(),
) {
    /** 뛰기 한 번을 적은 새 값. */
    fun recordHop(direction: CrossyGame.Direction): MiniGameInput {
        val tail = (recentHops + direction).let { if (it.size > recentHopLimit) it.drop(it.size - recentHopLimit) else it }
        return copy(hopCount = hopCount + 1, recentHops = tail)
    }

    /** [since] 이후에 눌린 뛰기들 — 누른 순서. 꼬리보다 많이 밀렸으면 꼬리만큼(가장 최근 것들)만 준다. */
    fun hops(since: Int): List<CrossyGame.Direction> {
        val missed = hopCount - since
        if (missed <= 0) return emptyList()
        return recentHops.takeLast(minOf(missed, recentHops.size))
    }

    companion object {
        const val recentHopLimit: Int = 8
    }
}

/**
 * 점수·라운드가 오르면 바뀌는 무대 — **규칙 몫만**(id · 이름 · 별 수 · 고르기). 색은 그림의 것이라 ui(W4-b)가 옮긴다.
 * 규칙은 무대를 모른다(난이도와 값이 겹치지 않는다).
 */
enum class MiniGameStage(val id: Int, val stageName: String, val starCount: Int) {
    dawn(0, "새벽", 18),
    day(1, "한낮", 0),
    dusk(2, "노을", 10),
    night(3, "밤", 46),
    aurora(4, "오로라", 60),
    ;

    /** 오로라 커튼을 그리는 무대인가. */
    val hasAuroraBands: Boolean get() = id == 4

    companion object {
        /** 순서대로. 인덱스 = id. */
        val all: List<MiniGameStage> = entries.toList()

        /** 플래피 무대 경계(점수) — 움직이는 기둥이 시작되는 15와 겹치지 않는다. */
        val flappyThresholds: List<Int> = listOf(0, 6, 13, 22, 34)

        /** 테트리스 무대 경계 — advance(고정한 조각 + 지운 줄) 기준. 레벨 경계와 겹치지 않는다. */
        val tetrisThresholds: List<Int> = listOf(0, 30, 110, 290, 650)

        fun forFlappyScore(score: Int): MiniGameStage {
            val s = maxOf(0, score)
            var index = 0
            for ((i, threshold) in flappyThresholds.withIndex()) if (s >= threshold) index = i
            return all[minOf(index, all.size - 1)]
        }

        /** 타이밍 바 — 2라운드마다 한 단계. 라운드 0(시작 전)은 새벽. */
        fun forTimingRound(round: Int): MiniGameStage {
            val index = maxOf(0, minOf(all.size - 1, (maxOf(1, round) - 1) / 2))
            return all[index]
        }

        /** 그 advance 의 무대. 줄 수를 넘기지 마라(advance = 고정한 조각 수 + 지운 줄 수). */
        fun forTetrisAdvance(advance: Int): MiniGameStage {
            val value = maxOf(0, advance)
            var index = 0
            for ((i, threshold) in tetrisThresholds.withIndex()) if (value >= threshold) index = i
            return all[minOf(index, all.size - 1)]
        }
    }
}
