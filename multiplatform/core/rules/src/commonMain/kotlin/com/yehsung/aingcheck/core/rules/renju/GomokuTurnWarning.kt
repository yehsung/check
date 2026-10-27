// 원본: Sources/CheckCore/GomokuTurnWarning.swift @ 1b8260d (규칙 몫 — C§3.2 A-3)
package com.yehsung.aingcheck.core.rules.renju

// 0.3.51 — 오목 **내 차례 마지막 3초**에 판 안쪽 가장자리가 빨갛게 빛난다(맥·폰 한 벌). 판정(순수 계산)과 그림 상수를 한 곳에 둔다.
//
// 이 파일에 옮긴 것: 문턱 · 세기 · 그림 상수(숫자만). 옮기지 않은 것:
//  · `watchesMyClock(_ match: GomokuMatchState?)` 의 **서명** — `GomokuMatchState` 는 스토어 값(GomokuStore.swift, W2-d)이라
//    rules 가 기댈 수 없다. 판정식은 [watchesMyClock] 에 원시 인자로 옮겼고, 스토어 갈래가 자기 값으로 부른다.
//  · `drawEdgeGlow(into:side:intensity:)`(SwiftUI GraphicsContext 그림) — 화면 갈래(W4-a)가 Compose 로 다시 그린다(C§3.2 "그리기는 옮기지 않음").
//
// 지키는 약속(Swift 머리 주석 그대로): 내 차례에만 선다 · null(마감 없음)은 **언제나 꺼짐**(`?: 0` 으로 베끼지 않는다) ·
// 0초에도 켜진 채다 · 매초 값을 스토어에 두지 않는다(세기는 잎 뷰가 그 순간의 남은 초로 계산한다).

/** 내 차례 마지막 몇 초의 판 테두리 경고 — 판정과 그림 상수. 시계를 읽지 않는다(남은 초는 부르는 쪽이 넘긴다). */
object GomokuTurnWarning {
    /** 경고가 서는 남은 시간(초, **이하**). 링 숫자는 올림이라 "3초"가 보이는 순간과 정확히 같다. */
    const val lowTimeSeconds: Double = 3.0
    /** 3초 순간의 세기(옅게 시작). 0초에 [maximumIntensity] 까지 곧게 오른다. */
    const val minimumIntensity: Double = 0.55
    const val maximumIntensity: Double = 1.0

    /**
     * 이 판에서 경고가 **설 수 있는가** — 끝나지 않았고, 내 차례이고, 마감이 돈다(Swift `watchesMyClock` 의 판정식).
     * 판이 없으면 부르는 쪽이 false 로 접는다(Swift 는 `match == nil` 이면 false). [deadline] 은 마감 유무만 본다.
     * 1:1 판은 상대 차례에도 마감이 돈다 — 그때 꺼지는 갈래(`turn == myColor`)는 골든 `renju/inputs` 의 turnWatches 전수 표가 잰다.
     */
    fun watchesMyClock(isFinished: Boolean, deadline: Double?, turn: GomokuColor?, myColor: GomokuColor): Boolean {
        if (isFinished || deadline == null || turn == null) return false
        return turn == myColor
    }

    /** 남은 초가 경고 구간인가. null(마감 없음) · NaN · 무한대는 꺼짐이고, 3.0 이하(0 포함)는 켜짐이다. */
    fun isActive(remaining: Double?): Boolean {
        if (remaining == null || !remaining.isFinite()) return false
        return remaining <= lowTimeSeconds
    }

    /** 빛의 세기(0…1). 꺼짐이면 0, 3초에 [minimumIntensity], 0초(와 그 아래)에 [maximumIntensity]. */
    fun intensity(remaining: Double?): Double {
        if (!isActive(remaining) || remaining == null) return 0.0
        val left = swiftMin(1.0, swiftMax(0.0, remaining / lowTimeSeconds))
        return minimumIntensity + (maximumIntensity - minimumIntensity) * (1 - left)
    }

    // MARK: 그림 상수(그리는 법은 화면 갈래)

    /** 빛의 색(sRGB). 금수 X·마지막 수 점보다 **파랑이 많은 진홍**이다(렌더 검증이 서로를 헷갈리지 않게). */
    const val tintRed: Double = 0.90
    const val tintGreen: Double = 0.06
    const val tintBlue: Double = 0.30
    /** 빛이 들어오는 깊이(판 한 변의 비율). 가장자리 돌에 닿지 않는다. */
    const val depthRatio: Double = 0.024
    /** 판 모서리 둥글기(판 그림과 같은 값 — side × 0.025). */
    const val cornerRatio: Double = 0.025
    /** 겹 수와 가장 바깥 겹의 불투명도(세기 1 일 때). 안쪽 겹일수록 제곱으로 옅어진다. */
    const val layerCount: Int = 8
    const val peakOpacity: Double = 0.7
}

/** Swift `Swift.max(x, y)` = `y >= x ? y : x` — `-0.0`·NaN 에서 [kotlin.comparisons.maxOf] 와 다르다(비트 동일을 위해 식 그대로). */
internal fun swiftMax(x: Double, y: Double): Double = if (y >= x) y else x

/** Swift `Swift.min(x, y)` = `y < x ? y : x`. */
internal fun swiftMin(x: Double, y: Double): Double = if (y < x) y else x
