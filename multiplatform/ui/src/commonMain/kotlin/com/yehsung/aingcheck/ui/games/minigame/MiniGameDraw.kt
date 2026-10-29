// 원본: Sources/CheckCore/MiniGameEngine.swift @ 3bd04bd (MiniGameBackdrop · MiniGameProjection · MiniGameEffects — 그리기 몫)
//
// 세 게임 캔버스(+ 1:1 테트리스 판)가 같이 쓰는 그리기. Swift `GraphicsContext` 함수를 Compose `DrawScope` 로 옮겼다 — 순서·수치 그대로.
//
// 지키는 금지(Swift 머리말 그대로):
//  · **필터(blur) 금지** — 60Hz 에서 캔버스 전체를 흐리면 통합 GPU 에서 프레임이 깨진다. 부드러운 빛은 전부 radialGradient 다.
//  · 별·능선의 자리는 고정 시드다(프레임마다 새로 뽑으면 배경이 끓는다). 능선 봉우리는 시드별 한 번만 계산한다.
//  · 이펙트는 상태를 갖지 않는다 — 진행도(0…1)는 부르는 쪽이 자기 시계(판 시계)에서 계산해 넘긴다(같은 판을 재현할 수 있어야 한다).
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import com.yehsung.aingcheck.core.rules.minigame.MiniGameCanvas
import com.yehsung.aingcheck.core.rules.minigame.MiniGameRandom
import com.yehsung.aingcheck.core.rules.minigame.MiniGameRect
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.minigame.MiniGameStage
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * 논리 좌표 → 실제 픽셀. core `MiniGameCanvas.transform` 한 번을 들고 다니는 얇은 껍데기다(세 게임이 같은 것을 쓴다 — 각자 만들면 같은 판을
 * 서로 다른 식으로 투영한다). [scale] 은 **픽셀/논리 단위**다(글자 크기는 [scaleDp] = 밀도로 나눈 값으로 곱한다).
 */
class MiniGameProjection(container: Size, logicalSize: MiniGameSize = MiniGameCanvas.logicalSize, density: Float = 1f) {
    val scale: Float
    val origin: Offset

    /** 글자·여백에 곱할 배율(dp/논리 단위) — Swift 의 `scale`(pt/논리 단위)과 같은 뜻. */
    val scaleDp: Float

    init {
        val (s, o) = MiniGameCanvas.transform(MiniGameSize(container.width.toDouble(), container.height.toDouble()), logicalSize)
        scale = s.toFloat()
        origin = Offset(o.x.toFloat(), o.y.toFloat())
        scaleDp = scale / max(density, 0.0001f)
    }

    fun x(value: Double): Float = origin.x + (value * scale).toFloat()
    fun y(value: Double): Float = origin.y + (value * scale).toFloat()
    fun point(px: Double, py: Double): Offset = Offset(x(px), y(py))
    fun rect(rx: Double, ry: Double, rw: Double, rh: Double): Rect = Rect(x(rx), y(ry), x(rx) + (rw * scale).toFloat(), y(ry) + (rh * scale).toFloat())
    fun rect(r: MiniGameRect): Rect = rect(r.minX, r.minY, r.maxX - r.minX, r.maxY - r.minY)
}

/** 사각형 안쪽으로 줄인다(음수면 넓힌다) — Swift `insetBy(dx:dy:)`. */
internal fun Rect.insetBy(dx: Float, dy: Float): Rect = Rect(left + dx, top + dy, right - dx, bottom - dy)

/** 논리 사각형을 줄인다 — Swift `CGRect.insetBy`. */
internal fun MiniGameRect.insetBy(dx: Double, dy: Double): MiniGameRect = MiniGameRect(minX + dx, minY + dy, (maxX - minX) - 2 * dx, (maxY - minY) - 2 * dy)

/**
 * 캔버스 바닥을 칠하는 공용 배경. 그리는 순서: 하늘 그라디언트 → (오로라) 커튼 → 별 → 지평선 광원 → 먼 능선 → 가까운 언덕.
 * 이 금지(blur)는 DrawScope 안의 필터를 향한 것이지 글자층의 그림자를 향한 것이 아니다(맥 실측: 허브 캔버스 래퍼 그림자 0.85 vs 0.86ms/frame).
 */
object MiniGameBackdrop {
    /** 별·능선의 자리를 정하는 고정 시드. */
    val seed: ULong = 0x5EEDB00CuL

    private val peakCache: Map<ULong, List<Double>> by lazy {
        listOf(seed + 11uL, seed + 23uL).associateWith { s -> peaksFor(s) }
    }

    private fun peaksFor(s: ULong): List<Double> {
        val rng = MiniGameRandom(s)
        return List(24) { rng.uniform(0.45, 1.0) }
    }

    private fun cachedPeaks(s: ULong): List<Double> = peakCache[s] ?: peaksFor(s)

    /**
     * 배경 한 장. [rect] 는 픽셀, 길이 상수(파장 · 간격 · 별 반지름)는 Swift 의 pt 값이라 [density] 를 곱한다.
     * @param scroll 가로 스크롤(**pt** — 판의 `scrolled` 그대로). 0 이면 정지 배경(타이밍 바·테트리스). 층마다 다른 배속으로 패럴랙스를 만든다.
     * @param terrain 능선·언덕을 그릴지(타이밍 바·테트리스는 false — 하늘만).
     */
    fun draw(scope: DrawScope, rect: Rect, stage: MiniGameStage, scroll: Float = 0f, terrain: Boolean = true, reduceMotion: Boolean = false, density: Float = 1f) {
        val paint = stage.paint
        val d = density
        // 1) 하늘
        scope.drawRect(
            brush = Brush.verticalGradient(listOf(paint.skyTop, paint.skyBottom), startY = rect.top, endY = rect.bottom),
            topLeft = rect.topLeft,
            size = rect.size,
        )

        // 2) 오로라 커튼 — 마지막 무대의 표식. 아주 느리게 흐른다(reduceMotion 이면 정지).
        if (stage.hasAuroraBands) {
            val drift = if (reduceMotion) 0f else scroll * 0.04f
            for (band in 0 until 3) {
                val path = Path()
                val baseY = rect.top + rect.height * (0.12f + 0.09f * band)
                val amplitude = rect.height * 0.05f
                val phase = drift / 90f + band * 1.3f
                path.moveTo(rect.left, baseY)
                var x = rect.left
                while (x <= rect.right) {
                    val y = baseY + sin((x / (70f * d) + phase).toDouble()).toFloat() * amplitude
                    path.lineTo(x, y)
                    x += 8f * d
                }
                path.lineTo(rect.right, baseY + rect.height * 0.14f)
                path.lineTo(rect.left, baseY + rect.height * 0.14f)
                path.close()
                scope.drawPath(
                    path,
                    brush = Brush.verticalGradient(
                        listOf(paint.glow.copy(alpha = 0.20f - 0.05f * band), Color.Transparent),
                        startY = baseY, endY = baseY + rect.height * 0.14f,
                    ),
                )
            }
        }

        // 3) 별 — 자리는 고정, 밝기만 아주 약하게 흔든다.
        if (stage.starCount > 0) {
            val rng = MiniGameRandom(seed)
            for (index in 0 until stage.starCount) {
                val x = rect.left + rng.unit().toFloat() * rect.width
                val y = rect.top + rng.unit().toFloat() * rect.height * 0.72f
                val base = 0.7 + rng.unit() * 0.6
                val twinkle = if (reduceMotion) 1.0 else 0.75 + 0.25 * abs(sin(scroll.toDouble() / 40 + index))
                val r = (base * twinkle).toFloat() * d
                scope.drawCircle(Color.White.copy(alpha = (0.35 + 0.45 * twinkle).toFloat()), radius = r, center = Offset(x, y))
            }
        }

        // 4) 지평선 광원 — 하늘 아래쪽에서 번지는 빛(그라디언트로만).
        val horizonY = rect.top + rect.height * 0.70f
        val glowRect = Rect(
            rect.left - rect.width * 0.2f, horizonY - rect.height * 0.30f,
            rect.left - rect.width * 0.2f + rect.width * 1.4f, horizonY - rect.height * 0.30f + rect.height * 0.60f,
        )
        MiniGameEffects.glow(scope, glowRect, paint.glow, 0.22f)

        if (!terrain) return

        // 5) 먼 능선(느린 층) · 6) 가까운 언덕(빠른 층)
        ridge(scope, rect, paint.far.copy(alpha = paint.far.alpha * 0.95f), rect.top + rect.height * 0.72f, rect.height * 0.13f, 96f, scroll * 0.16f, seed + 11uL, d)
        ridge(scope, rect, paint.near, rect.top + rect.height * 0.88f, rect.height * 0.09f, 150f, scroll * 0.38f, seed + 23uL, d)
    }

    /** 능선 한 층(코사인 보간 — 봉우리 사이가 각지지 않게). 파형은 시드 고정 난수로 흔들어 반복이 눈에 띄지 않게 한다. */
    private fun ridge(scope: DrawScope, rect: Rect, color: Color, baseline: Float, amplitude: Float, wavelengthPt: Float, offsetPt: Float, seed: ULong, d: Float) {
        // Swift 는 pt 좌표에서 돈다 — 같은 파형이 나오게 pt 로 걷고 픽셀로 옮긴다(x 픽셀 = pt × d).
        val peaks = cachedPeaks(seed)
        val path = Path()
        path.moveTo(rect.left, rect.bottom)
        val leftPt = rect.left / d
        val rightPt = rect.right / d
        var xPt = leftPt
        val shift = offsetPt % (wavelengthPt * peaks.size)
        while (xPt <= rightPt + wavelengthPt) {
            val world = xPt + shift
            val index = floor(world / wavelengthPt).toInt()
            val local = world / wavelengthPt - index
            val a = peaks[((index % peaks.size) + peaks.size) % peaks.size]
            val b = peaks[(((index + 1) % peaks.size) + peaks.size) % peaks.size]
            val t = (1 - cos(local.toDouble() * PI)) / 2
            val height = a + (b - a) * t
            path.lineTo(xPt * d, (baseline - amplitude * height).toFloat())
            xPt += 6f
        }
        path.lineTo((rightPt + wavelengthPt) * d, rect.bottom)
        path.close()
        scope.drawPath(path, color)
    }
}

/** 순간 이펙트. 전부 상태가 없다 — 진행도는 부르는 쪽 시계에서 온다. */
object MiniGameEffects {
    /** 타원 안에서 가운데가 밝고 가장자리로 사라지는 후광(blur 대신 쓰는 유일한 수단). */
    fun glow(scope: DrawScope, rect: Rect, color: Color, opacity: Float) {
        if (rect.width <= 0f || rect.height <= 0f) return
        scope.drawOval(
            brush = Brush.radialGradient(
                listOf(color.copy(alpha = color.alpha * opacity), Color.Transparent),
                center = rect.center,
                radius = rect.width / 2,
            ),
            topLeft = rect.topLeft,
            size = rect.size,
        )
    }

    /** 중심에서 퍼지는 링. progress 0 → 반지름 0·불투명, 1 → 최대 반지름·투명. */
    fun ring(scope: DrawScope, center: Offset, progress: Double, maxRadius: Float, color: Color, lineWidth: Float = 2f) {
        val p = min(max(progress, 0.0), 1.0)
        if (p >= 1) return
        val eased = 1 - (1 - p).pow(2)
        val radius = maxRadius * eased.toFloat()
        if (radius <= 0.5f) return
        scope.drawCircle(color.copy(alpha = color.alpha * (1 - p).toFloat()), radius = radius, center = center, style = Stroke(lineWidth))
    }

    /** 방사형 파편. 방향은 시드로 고정한다(같은 사건이면 같은 그림). [angleFrom]~[angleTo] 는 화면 좌표 라디안(0 = 앞, π/2 = 아래). */
    fun sparks(
        scope: DrawScope,
        center: Offset,
        progress: Double,
        count: Int,
        maxRadius: Float,
        color: Color,
        seed: ULong,
        dotRadius: Float = 2f,
        angleFrom: Double = 0.0,
        angleTo: Double = PI * 2,
    ) {
        val p = min(max(progress, 0.0), 1.0)
        if (p >= 1) return
        val rng = MiniGameRandom(seed)
        val eased = 1 - (1 - p).pow(2)
        repeat(count) {
            val angle = rng.uniform(angleFrom, angleTo)
            val reach = maxRadius * rng.uniform(0.55, 1.0).toFloat() * eased.toFloat()
            val x = center.x + cos(angle).toFloat() * reach
            val y = center.y + sin(angle).toFloat() * reach
            val r = dotRadius * (1 - p).toFloat()
            if (r > 0.2f) scope.drawCircle(color.copy(alpha = color.alpha * (1 - p).toFloat()), radius = r, center = Offset(x, y))
        }
    }

    /** 아래로 퍼지는 공기 아치(점프 임팩트). 링과 달리 방향이 있다. */
    fun arch(scope: DrawScope, center: Offset, progress: Double, halfWidth: Float, depth: Float, color: Color, lineWidth: Float = 2f) {
        val p = min(max(progress, 0.0), 1.0)
        if (p >= 1) return
        val eased = 1 - (1 - p).pow(2)
        val grow = (0.35 + 0.65 * eased).toFloat()
        val hw = halfWidth * grow
        if (hw <= 0.5f) return
        val path = Path()
        path.moveTo(center.x - hw, center.y)
        path.quadraticTo(center.x, center.y + depth * grow * 2, center.x + hw, center.y)
        scope.drawPath(path, color.copy(alpha = color.alpha * 0.85f * (1 - p).toFloat()), style = Stroke(lineWidth))
    }

    /** 캔버스 아래쪽에서 위로 번지는 빛(무대 전환·신기록의 한 방). */
    fun flare(scope: DrawScope, rect: Rect, progress: Double, color: Color) {
        val p = min(max(progress, 0.0), 1.0)
        if (p >= 1) return
        scope.drawRect(
            brush = Brush.verticalGradient(listOf(color.copy(alpha = 0.35f * (1 - p).toFloat()), Color.Transparent), startY = rect.bottom, endY = rect.top),
            topLeft = rect.topLeft,
            size = rect.size,
        )
    }
}
