// 원본: Sources/CheckMobileKit/Components/ContributionGrid.swift @ a63fea2 (ContributionGridCanvas)
// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift @ a63fea2 (ContributionLevels.opacity · ContributionGridLayout · ContributionAxis)
//
// 12주 잔디(주 열 × 요일 7행). **기록이 없어도 늘 격자를 그린다**(빈 칸 = fill 트랙). 칸 크기는 받은 폭에 맞춘다(상한 13).
// 값 → 단계(0…4) 계산은 기록 규칙(W1-c rules/insights) 몫이다 — 이 부품은 단계만 받아 그린다.
package com.yehsung.aingcheck.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.max
import kotlin.math.min

/** 잔디 색축. */
enum class ContributionAxis {
    /** 근무(초록 — workingDot 사다리). */
    Work,
    /** AI 토큰(보라 — aiToken 사다리). */
    Token,
    ;

    fun tint(colors: AingColors): Color = when (this) {
        Work -> colors.workingDot
        Token -> colors.aiToken
    }
}

object ContributionLevels {
    const val LEVELS = 4

    /** 칸 불투명도(시안 .30 · .55 · .78 · 1). 0단계는 트랙(fill)이라 0. */
    fun opacity(level: Int): Float = when {
        level <= 0 -> 0f
        level == 1 -> 0.30f
        level == 2 -> 0.55f
        level == 3 -> 0.78f
        else -> 1f
    }
}

object ContributionGridLayout {
    const val ROWS = 7
    /** 이번 주 + 지난 12주(코어 WorkDailyGrid.defaultWeeks 와 같아야 한다). */
    const val DEFAULT_WEEKS = 13
    /** 칸 사이 틈(시안 2.5). */
    const val SPACING = 2.5f
    /** 칸 상한. */
    const val MAXIMUM_CELL = 13f

    /** 폭 [width] 에 [columns] 열을 넣을 때의 칸 한 변(상한 [maximum], 0 이상). */
    fun cellSize(width: Float, columns: Int, spacing: Float = SPACING, maximum: Float = MAXIMUM_CELL): Float {
        if (columns <= 0 || width <= 0f) return 0f
        val raw = (width - spacing * (columns - 1)) / columns
        return max(0f, min(maximum, raw))
    }

    fun gridSize(cell: Float, columns: Int, rows: Int = ROWS, spacing: Float = SPACING): Pair<Float, Float> {
        if (columns <= 0 || rows <= 0) return 0f to 0f
        return (cell * columns + spacing * (columns - 1)) to (cell * rows + spacing * (rows - 1))
    }
}

/**
 * 격자 그림만(제목·문구 없음). [levels] = 주 × 요일(0=월…6=일)의 단계, null = 미래(빈 테두리 칸).
 * [dimmed] 면 값이 있어도 트랙만(불러오는 중·실패 자리).
 */
@Composable
fun ContributionGridCanvas(
    levels: List<List<Int?>>,
    axis: ContributionAxis,
    modifier: Modifier = Modifier,
    dimmed: Boolean = false,
) {
    val colors = AingTheme.colors
    val columns = levels.size
    BoxWithConstraints(modifier) {
        val widthDp = if (constraints.hasBoundedWidth) maxWidth.value else columns * 12f
        val cell = ContributionGridLayout.cellSize(widthDp, columns)
        val (w, h) = ContributionGridLayout.gridSize(cell, columns)
        Canvas(Modifier.size(w.dp, h.dp)) {
            if (columns == 0) return@Canvas
            val c = cell * density
            val gap = ContributionGridLayout.SPACING * density
            val radius = max(1.5f, cell * 0.22f) * density
            val tint = axis.tint(colors)
            for (week in 0 until columns) {
                for (weekday in 0 until ContributionGridLayout.ROWS) {
                    val topLeft = Offset(week * (c + gap), weekday * (c + gap))
                    val level = levels[week].getOrElse(weekday) { 0 }
                    if (level == null) {
                        val half = 0.5f * density
                        drawRoundRect(
                            colors.separator,
                            topLeft = topLeft + Offset(half, half),
                            size = Size(c - 2 * half, c - 2 * half),
                            cornerRadius = CornerRadius(radius),
                            style = Stroke(width = 1f * density),
                        )
                    } else if (level <= 0 || dimmed) {
                        drawRoundRect(colors.fill, topLeft, Size(c, c), CornerRadius(radius))
                    } else {
                        drawRoundRect(tint.copy(alpha = tint.alpha * ContributionLevels.opacity(level)), topLeft, Size(c, c), CornerRadius(radius))
                    }
                }
            }
        }
    }
}

/** 시험·미리보기용 격자 크기(dp). */
fun contributionGridSizeDp(widthDp: Float, columns: Int): Pair<Dp, Dp> {
    val cell = ContributionGridLayout.cellSize(widthDp, columns)
    val (w, h) = ContributionGridLayout.gridSize(cell, columns)
    return w.dp to h.dp
}
