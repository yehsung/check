// 원본: 없음 (iOS 는 초상만 — 결정 #2 '살아 있는 아잉이 미리보기 하나'(G §5-3 · §8-12) · F §8 B · §8-17 #7 케이크 접기 · §8-19 #6② 공개 한 바퀴. Swift 짝이 없는 Android 전용 규칙)
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.core.rules.character.CharacterCatalog

/** 무대가 이 캐릭터를 어떻게 그리나. */
sealed interface StageMode {
    /**
     * 구운 아잉이를 살려 그린다. [drawnId] = 실제로 그릴 마감(서버 id). 케이크 둘은 굽지 않아 **아잉으로 접힌다**([folded] — G §8-17 #7,
     * 오버레이·미리보기 공통 결정). 접힌 사실은 접근성 글에만 남기고 그림은 아잉 그대로다.
     */
    data class Live(val drawnId: String, val folded: Boolean) : StageMode

    /**
     * 초상(iOS 와 같은 무대 그림). 스프라이트 6종(여우 · 시바 …)과 이 빌드가 모르는 id. Android 기본 묶음에는 스프라이트 아틀라스가 없다
     * (6장 6.3MB — 묶음 예산 4.5MB 밖, ui Sync 도 아틀라스를 싣지 않는다). 모르는 id 를 아잉으로 접는 맥 규칙은 오버레이(남의 캐릭터)
     * 몫이고, 나 탭 무대에서 내가 입은 캐릭터를 다른 캐릭터로 바꿔 보이면 안 된다.
     */
    data object Portrait : StageMode
}

object StagePolicy {
    /** 탭하면 맥 오버레이 몸 클릭과 같은 반응(F §1.3 hit — 찌부 0.52s, 쿨다운 0.6s). */
    const val TAP_REACTION = "hit"

    /**
     * 뽑기 결과 공개 뒤 한 번 하는 반응 = **한 바퀴**(사용자 결정 G §8-19 #6② — 첫 판부터). 맥에서 몸이 y 360° 도는 리액션은
     * 근무 시작(commuteStart — 폴짝 + y 360°, 0.6s · 우선 3)뿐이다(goalAchieved 는 720°). 등이 보이는 각은 Android 기본 묶음
     * (config.json bundles.androidDefault)에 함께 실은 **S 단 스핀 행**(요 10° × 기울기 4° · 세 마감 × 페이지 셋 + cells-S)으로 그린다 — [StageSpin].
     */
    const val REVEAL_REACTION = "commuteStart"

    /** 무대가 평소 그리는 단(L 쉬는 행). 재생기 단 고르기를 쓰지 않는다 — cells-S 가 실려 있어 작은 틀에선 S 를 고르는데 S 쉬는 행 페이지는 없다. */
    const val STAGE_TIER = "L"

    /** 한 바퀴의 등 쪽 칸을 고르는 단(S 스핀 행만 실린다). */
    const val SPIN_TIER = "S"

    /** 데움이 굽는 L 쉬는 행 칸의 |요| 한계(살랑 ±8° · hit · 한 바퀴 앞뒤가 닿는 정면 근처). 한 바퀴 동안 L 은 이 칸만 쓴다. */
    const val PREWARM_YAW_DEG = 9

    /** 깜빡임 간격(초) — 맥 `CheckOverlayController.blinkIntervalRange`(3…7). */
    val BLINK_INTERVAL_S: ClosedFloatingPointRange<Double> = 3.0..7.0

    /** 몸 클릭 거르기 여백(pt) — 맥 hitTest 투영 bbox + 12pt(F §5.3). 280×340 틀(2x)에서는 24px. */
    const val TAP_MARGIN_POINTS = 12.0

    /**
     * 착용 id → 무대 모드. [bakedIds] = 실린 구운 마감(서버 id — `BakeLibrary.bakedIds`). 자산을 못 읽었으면 빈 집합 → 전부 초상.
     */
    fun mode(characterId: String?, bakedIds: Set<String>): StageMode {
        val id = characterId?.trim().orEmpty()
        if (id in bakedIds) return StageMode.Live(id, folded = false)
        if (CharacterCatalog.isCakeAing(id) && CharacterCatalog.builtInAingID in bakedIds) {
            return StageMode.Live(CharacterCatalog.builtInAingID, folded = true)
        }
        return StageMode.Portrait
    }
}

/**
 * 무대 틀: 맥 오버레이 280×340 틀(140×170pt 2x — 골든 · T3 와 같은 구도)을 무대 그림 칸(iOS 132pt 정사각) 안에 **초상과 같은 비율**로 앉힌다.
 * 투영은 뷰포트 크기에 선형이라 틀을 [Placement.scale] 배로 키워 그리는 것 = 같은 그림을 키운 것(칸은 몸 px 로 고른다 — L 단).
 */
object StageFraming {
    const val FRAME_WIDTH = 280.0
    const val FRAME_HEIGHT = 340.0

    /** 280×340 틀에서 정면 idle 몸 알파 상자(골든 072-aing-idle-t0691 실측 (42, 49)–(233, 226)): 폭 · 가운데 x · 바닥. */
    const val BODY_WIDTH = 191.0
    const val BODY_CENTER_X = 137.5
    const val BODY_BOTTOM = 226.0

    /** iOS 무대 초상(aing-neutral.png 192px) 알파 상자 x 14–178 · y 바닥 173 → 그림 칸 대비 몸 폭 · 바닥. */
    const val ART_BODY_WIDTH = 164.0 / 192.0
    const val ART_BODY_BOTTOM = 173.0 / 192.0

    /** 틀 놓기: 틀 좌표 (x, y) → 화면 (originX + x·scale, originY + y·scale). */
    data class Placement(val scale: Double, val originX: Double, val originY: Double) {
        val viewportWidth: Double get() = FRAME_WIDTH * scale
        val viewportHeight: Double get() = FRAME_HEIGHT * scale
    }

    /** 그림 칸(왼쪽 위 · 한 변, px) → 틀 놓기. 몸 폭 = 칸 × 164/192, 몸 바닥 = 칸 위 + 칸 × 173/192, 가로 가운데. */
    fun place(artLeft: Double, artTop: Double, artSide: Double): Placement {
        require(artSide > 0) { "그림 칸 한 변은 양수: $artSide" }
        val scale = artSide * ART_BODY_WIDTH / BODY_WIDTH
        return Placement(
            scale = scale,
            originX = artLeft + artSide / 2 - BODY_CENTER_X * scale,
            originY = artTop + artSide * ART_BODY_BOTTOM - BODY_BOTTOM * scale,
        )
    }
}
