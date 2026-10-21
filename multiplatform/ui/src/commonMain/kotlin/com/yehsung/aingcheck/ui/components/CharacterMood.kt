// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift @ 862be0f (PresenceStatus · CharacterMood)
//
// 캐릭터 초상의 기분 = 근무 상태(맥 헤더 문법). 그리는 쪽(초상·무대·탭 아이콘)이 같은 규칙을 쓰도록 한 곳에 둔다.
package com.yehsung.aingcheck.ui.components

import androidx.compose.ui.graphics.Color
import com.yehsung.aingcheck.ui.theme.AingColors
import kotlin.math.max
import kotlin.math.roundToLong

/** 사람 점·캐릭터 링이 말하는 근무 상태(뜻 색 한 벌). */
enum class PresenceStatus { Working, Pending, Off }

/** 초상 표정(그림 파일 이름 꼬리 — portrait-neutral / portrait-negative). */
enum class CharacterExpression(val fileSuffix: String) { Neutral("neutral"), Negative("negative") }

enum class CharacterMood {
    /** 근무 중 — 웃는 얼굴 + 초록 링 + 발광. */
    Working,
    /** 연결 끊김 — 웃는 얼굴 + 앰버 링. */
    Lost,
    /** 근무 안 함 — 시무룩 + 청회색 링. */
    Off,
    /** 상태 없음(상점 미리보기 · 고르기) — 웃는 얼굴 · 링 없음 · 받침(surface2). */
    Plain,
    ;

    val expression: CharacterExpression get() = if (this == Off) CharacterExpression.Negative else CharacterExpression.Neutral

    /** 링 색 뜻(null = 링 없음). */
    val ring: PresenceStatus?
        get() = when (this) {
            Working -> PresenceStatus.Working
            Lost -> PresenceStatus.Pending
            Off -> PresenceStatus.Off
            Plain -> null
        }

    /** 받침 원 색. */
    fun backing(colors: AingColors): Color = when (this) {
        Working -> colors.workingTint
        Lost -> colors.pendingTint
        Off -> colors.fill
        Plain -> colors.surface2
    }

    companion object {
        /** 그림과 링 사이 틈(dp). 시안 2px. */
        const val RING_GAP = 2f

        /**
         * 링 두께(dp) — 시안 `max(2, 지름 × 0.04)`, Swift `.rounded(.toNearestOrEven)`.
         * Swift CGFloat 는 64비트라 곱도 Double 로 한다(Float 곱은 62.5×0.04 를 2.4999… 로 만들어 다른 쪽으로 간다).
         * Kotlin `roundToInt` 는 .5 를 위로 올린다 — 짝수 반올림으로 맞춘다(지름 62.5 에서 갈린다: 짝수 2 · 올림 3).
         */
        fun ringWidth(diameter: Float): Float = max(2.0, roundHalfEven(diameter.toDouble() * 0.04)).toFloat()

        internal fun roundHalfEven(x: Double): Double {
            val floor = kotlin.math.floor(x)
            val diff = x - floor
            return when {
                diff > 0.5 -> floor + 1.0
                diff < 0.5 -> floor
                else -> if ((floor.roundToLong() and 1L) == 0L) floor else floor + 1.0
            }
        }
    }
}

/** 링 색(뜻 색 점 계열). */
fun PresenceStatus.dotColor(colors: AingColors): Color = when (this) {
    PresenceStatus.Working -> colors.workingDot
    PresenceStatus.Pending -> colors.pendingDot
    PresenceStatus.Off -> colors.offWorkDot
}
