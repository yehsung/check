// 원본: Sources/CheckCore/GachaMachine/GachaMachinePieces.swift @ 3bd04bd
//
// 기계 부품 그리기(DrawScope — 설계 좌표 1 = 1dp). SwiftUI 뷰 조각을 Compose 그리기 함수로 옮겼다.
// 이식 차이: SwiftUI `.blur` · `.shadow` 는 그리지 않는다(Compose blur 는 Android 12 미만에서 꺼져 기기마다 갈린다 — CharacterPortrait 와
// 같은 판단). 캡슐은 처음 한 번 그림으로 굽는다(Swift `GachaCapsuleSprites` 와 같은 뜻 — ImageRenderer 대신 CanvasDrawScope).
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Canvas
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

// MARK: - 그리기 도우미

/** 그림을 [rect](설계 좌표)에 맞춰 부드럽게. 정수 칸으로 반올림하지 않는다(변환으로 놓는다). */
internal fun DrawScope.drawImageIn(
    image: ImageBitmap,
    rect: Rect,
    alpha: Float = 1f,
    colorFilter: ColorFilter? = null,
    blendMode: BlendMode = BlendMode.SrcOver,
) {
    if (rect.width <= 0f || rect.height <= 0f) return
    withTransform({
        translate(rect.left, rect.top)
        scale(rect.width / image.width, rect.height / image.height, Offset.Zero)
    }) {
        drawImage(
            image, IntOffset.Zero, IntSize(image.width, image.height), IntOffset.Zero, IntSize(image.width, image.height),
            alpha = alpha, colorFilter = colorFilter, blendMode = blendMode, filterQuality = FilterQuality.High,
        )
    }
}

internal fun rectCentered(c: Offset, w: Float, h: Float = w): Rect = Rect(c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2)

/** SwiftUI `.brightness(b)` — RGB 에 b 를 더한다. */
internal fun brightnessFilter(b: Float): ColorFilter? = if (abs(b) < 1e-4f) null else ColorFilter.colorMatrix(
    ColorMatrix(floatArrayOf(1f, 0f, 0f, 0f, b * 255f, 0f, 1f, 0f, 0f, b * 255f, 0f, 0f, 1f, 0f, b * 255f, 0f, 0f, 0f, 1f, 0f)),
)

/** SwiftUI `.saturation(s)` + `.brightness(b)`(채도 먼저). */
internal fun saturationBrightnessFilter(saturation: Float, brightness: Float): ColorFilter? {
    if (abs(saturation - 1f) < 1e-4f && abs(brightness) < 1e-4f) return null
    val m = ColorMatrix().apply { setToSaturation(saturation) }
    val v = m.values
    for (row in 0 until 3) v[row * 5 + 4] += brightness * 255f
    return ColorFilter.colorMatrix(ColorMatrix(v))
}

/** 흰 하이라이트만 남기는 칠(SwiftUI `.brightness(-0.42).contrast(5.5)` — c' = (c − 0.42 − 0.5)·5.5 + 0.5). */
private val highlightFilter: ColorFilter = run {
    val k = 5.5f
    val off = ((-0.42f - 0.5f) * k + 0.5f) * 255f
    ColorFilter.colorMatrix(ColorMatrix(floatArrayOf(k, 0f, 0f, 0f, off, 0f, k, 0f, 0f, off, 0f, 0f, k, 0f, off, 0f, 0f, 0f, 1f, 0f)))
}

// MARK: - 도형

/** 반원(위/아래) 경로 — 지름 [d], 왼쪽 위 0,0. */
internal fun halfDisc(d: Float, upper: Boolean, origin: Offset = Offset.Zero): Path = Path().apply {
    val r = d / 2
    val c = Offset(origin.x + r, origin.y + r)
    moveTo(c.x - r, c.y)
    arcTo(Rect(c, r), if (upper) 180f else 0f, 180f, false)
    close()
}

/** 조각(작은 결정) 꼭짓점(단위 좌표). */
internal val shardPoints: List<Offset> = listOf(
    Offset(0.50f, 0.00f), Offset(0.86f, 0.30f), Offset(0.78f, 0.76f),
    Offset(0.50f, 1.00f), Offset(0.20f, 0.74f), Offset(0.14f, 0.28f),
)

private fun polygon(points: List<Offset>, rect: Rect): Path = Path().apply {
    points.forEachIndexed { i, p ->
        val x = rect.left + p.x * rect.width
        val y = rect.top + p.y * rect.height
        if (i == 0) moveTo(x, y) else lineTo(x, y)
    }
    close()
}

/** 결정 하나(중심 [c], 크기 [size]). [outline] 이 있으면 바깥 테(밝은 바탕에서 결정이 묻히지 않게). */
internal fun DrawScope.drawShardGem(c: Offset, size: Float, outline: Color? = null, rotation: Float = 0f) {
    val rect = Rect(c.x - size * 0.4f, c.y - size / 2, c.x + size * 0.4f, c.y + size / 2)
    rotate(rotation, c) {
        val shape = polygon(shardPoints, rect)
        if (outline != null) drawPath(shape, outline, style = Stroke(max(1.2f, size * 0.11f), join = StrokeJoin.Round))
        drawPath(
            shape,
            Brush.linearGradient(
                listOf(GPalette.hex(0xE2D4FF), GPalette.hex(0xA98AFA), GPalette.hex(0x6E4DE0)),
                start = Offset(rect.right, rect.top), end = Offset(rect.left, rect.bottom),
            ),
        )
        val q = shardPoints
        val facet = polygon(listOf(q[0], q[5], q[4], q[3], Offset(0.47f, 0.50f)), rect)
        drawPath(facet, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.95f), GPalette.hex(0xD9C8FF, 0.85f)), rect.top, rect.bottom))
        drawPath(shape, Color.White.copy(alpha = 0.9f), style = Stroke(max(0.7f, size * 0.045f), join = StrokeJoin.Round))
    }
}

// MARK: - 캡슐

/** 그림 캡슐에서 위 반쪽이 끝나는 높이(이음매 띠 위쪽, 0…1). */
internal const val CAPSULE_SPLIT = 0.50f

/**
 * 캡슐 반쪽을 (0,0)–(d,d) 에 그린다. 그림이 있으면 흰 캡슐을 물들이고(곱하기 + 흰 하이라이트 되살리기), 없으면 벡터로.
 * 황금은 금 캡슐 그림 그대로, 무지개는 흰 캡슐에 **위 → 아래 일곱 빛**을 곱한다.
 */
internal fun DrawScope.drawCapsuleHalf(upper: Boolean, d: Float, tint: Color, rare: GRare?, art: GachaMachineArt) {
    val split = d * CAPSULE_SPLIT
    val clip = if (upper) Rect(-1f, -1f, d + 1f, split) else Rect(-1f, split, d + 1f, d + 1f)
    clipRect(clip.left, clip.top, clip.right, clip.bottom) {
        val full = Rect(0f, 0f, d, d)
        val gold = art.goldCapsule
        val white = art.capsule
        when {
            rare == GRare.Gold && gold != null -> drawImageIn(gold, full)
            rare == GRare.Rainbow && white != null -> {
                drawImageIn(white, full)
                // 흰 캡슐 × 일곱 빛(그림 알파 안에서만 — Modulate 는 바탕 알파를 곱한다).
                drawRect(Brush.verticalGradient(GRare.spectrum, 0f, d), blendMode = BlendMode.Modulate)
                drawImageIn(white, full, alpha = if (upper) 0.9f else 0.75f, colorFilter = highlightFilter, blendMode = BlendMode.Screen)
            }
            rare == null && white != null -> {
                drawImageIn(white, full, colorFilter = ColorFilter.tint(tint, BlendMode.Modulate))
                drawImageIn(white, full, alpha = if (upper) 0.9f else 0.75f, colorFilter = highlightFilter, blendMode = BlendMode.Screen)
            }
            else -> drawVectorCapsuleHalf(upper, d, if (rare == GRare.Gold) GPalette.gold else tint, if (rare == GRare.Rainbow) GRare.spectrum else null)
        }
    }
}

private fun DrawScope.drawVectorCapsuleHalf(upper: Boolean, d: Float, tint: Color, spectrum: List<Color>?) {
    val disc = halfDisc(d, upper)
    if (spectrum != null) {
        drawPath(disc, Brush.verticalGradient(spectrum, 0f, d), alpha = if (upper) 0.85f else 1f)
    } else {
        val stops = if (upper) listOf(tint.copy(alpha = 0.55f), tint.copy(alpha = 0.85f)) else listOf(tint, tint.copy(alpha = 0.75f))
        val top = if (upper) 0f else d / 2
        drawPath(disc, Brush.verticalGradient(stops, top, top + d / 2))
    }
    drawPath(
        disc,
        Brush.radialGradient(
            listOf(Color.White.copy(alpha = if (upper) 0.65f else 0.35f), Color.Transparent),
            center = Offset(d * 0.36f, d * (if (upper) 0.30f else 0.55f)), radius = d * 0.45f,
        ),
    )
    if (upper) {
        rotate(-28f, Offset(d * 0.32f, d * 0.22f)) {
            drawOval(Color.White.copy(alpha = 0.8f), Offset(d * 0.32f - d * 0.15f, d * 0.22f - d * 0.06f), Size(d * 0.30f, d * 0.12f))
        }
    } else {
        clipPath(disc) { drawRect(Color.Black.copy(alpha = 0.10f), Offset(0f, d * 0.50f), Size(d, d * 0.06f)) }
    }
    drawPath(disc, Color.Black.copy(alpha = 0.10f), style = Stroke(1f))
}

/** 캡슐 한 알(두 반쪽) — (0,0)–(d,d). */
internal fun DrawScope.drawCapsuleBall(d: Float, top: Color, bottom: Color, rare: GRare?, art: GachaMachineArt) {
    drawCapsuleHalf(true, d, top, rare, art)
    drawCapsuleHalf(false, d, bottom, rare, art)
}

/**
 * 미리 구운 캡슐 그림. 물들인 캡슐은 반쪽마다 합성이 들어 매 프레임 그리면 비싸다(돔 19알 × 2) — 처음 한 번 구워 두고 이후엔 평범한
 * 그림으로 그린다. 같은 그림 묶음이면 다시 굽지 않는다(호출부가 remember 로 쥔다).
 */
class GachaCapsuleSprites(art: GachaMachineArt) {
    val domeBalls: List<ImageBitmap>
    val heroTop: List<ImageBitmap>
    val heroBottom: List<ImageBitmap>
    val goldTop: ImageBitmap
    val goldBottom: ImageBitmap
    val rainbowTop: ImageBitmap
    val rainbowBottom: ImageBitmap

    init {
        val pairs = GPalette.capsulePairs
        domeBalls = pairs.map { (t, b) -> bake(DOME_SIZE) { drawCapsuleBall(DOME_SIZE, t, b, null, art) } }
        heroTop = pairs.map { (t, _) -> bake(HERO_SIZE) { drawCapsuleHalf(true, HERO_SIZE, t, null, art) } }
        heroBottom = pairs.map { (_, b) -> bake(HERO_SIZE) { drawCapsuleHalf(false, HERO_SIZE, b, null, art) } }
        goldTop = bake(HERO_SIZE) { drawCapsuleHalf(true, HERO_SIZE, GPalette.gold, GRare.Gold, art) }
        goldBottom = bake(HERO_SIZE) { drawCapsuleHalf(false, HERO_SIZE, GPalette.gold, GRare.Gold, art) }
        rainbowTop = bake(HERO_SIZE) { drawCapsuleHalf(true, HERO_SIZE, Color.White, GRare.Rainbow, art) }
        rainbowBottom = bake(HERO_SIZE) { drawCapsuleHalf(false, HERO_SIZE, Color.White, GRare.Rainbow, art) }
    }

    fun heroHalf(upper: Boolean, pair: Int, rare: GRare?): ImageBitmap = when (rare) {
        GRare.Gold -> if (upper) goldTop else goldBottom
        GRare.Rainbow -> if (upper) rainbowTop else rainbowBottom
        null -> if (upper) heroTop[pair] else heroBottom[pair]
    }

    companion object {
        const val HERO_SIZE = 128f
        const val DOME_SIZE = 36f
        /** 굽는 배율(Swift ImageRenderer.scale = 3). */
        const val SCALE = 3f

        private fun bake(d: Float, block: DrawScope.() -> Unit): ImageBitmap {
            val side = (d * SCALE).toInt()
            val bitmap = ImageBitmap(side, side)
            CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, Canvas(bitmap), Size(side.toFloat(), side.toFloat())) {
                withTransform({ scale(SCALE, SCALE, Offset.Zero) }) { block() }
            }
            return bitmap
        }
    }
}

/** 주인공 캡슐 한 알(구운 두 반쪽)을 [rect] 에. */
internal fun DrawScope.drawHeroBall(sprites: GachaCapsuleSprites, rect: Rect, pair: Int, rare: GRare?, alpha: Float = 1f, colorFilter: ColorFilter? = null) {
    drawImageIn(sprites.heroHalf(true, pair, rare), rect, alpha, colorFilter)
    drawImageIn(sprites.heroHalf(false, pair, rare), rect, alpha, colorFilter)
}

// MARK: - 돔 속 캡슐

internal class GDomeCapsule(
    /** 돔 중심 기준. */
    val p: Offset,
    val d: Float,
    val rot: Double,
    val pair: Int,
    val phase: Double,
    val freq: Double,
    /** 덜컹 방향(크기 포함). */
    val kickX: Double,
    val kickY: Double,
    /** 덜컹 회전(도). */
    val spin: Double,
    /** 위로 튀는 정도 0…1. */
    val lift: Double,
)

internal object GDome {
    val capsules: List<GDomeCapsule> = run {
        val r = GRandom(42uL)
        val out = mutableListOf<GDomeCapsule>()
        val rows: List<Pair<Double, List<Double>>> = listOf(
            40.0 to listOf(-58.0, -29.0, 0.0, 29.0, 58.0),
            15.0 to listOf(-72.0, -43.5, -14.5, 14.5, 43.5, 72.0),
            -11.0 to listOf(-58.0, -29.0, 0.0, 29.0, 58.0),
            -37.0 to listOf(-40.0, -8.0, 26.0, 55.0),
        )
        val pairs = GPalette.capsulePairs
        rows.forEachIndexed { ri, (y, xs) ->
            for (x in xs) {
                val pi = (r.next() % pairs.size.toULong()).toInt()
                val depth = ri / 3.0 // 0 바닥 … 1 위
                // Swift 인자 평가 순서 그대로(난수 소비 순서가 모양을 정한다).
                val px = x + r.range(-3.0, 3.0)
                val py = y + r.range(-2.5, 2.5)
                val d = r.range(29.0, 33.0)
                val rot = r.range(-180.0, 180.0)
                val phase = r.range(0.0, 2 * PI)
                val freq = r.range(0.45, 0.8)
                val kx = r.range(6.0, 13.0) * r.sign()
                val ky = r.range(10.0, 22.0) * (0.45 + depth)
                val spin = r.range(50.0, 140.0) * r.sign()
                out += GDomeCapsule(Offset(px.toFloat(), py.toFloat()), d.toFloat(), rot, pi, phase, freq, kx, ky, spin, 0.4 + 0.6 * depth)
            }
        }
        // 뒤(위) 줄부터 그려 앞줄이 덮게
        out.sortedBy { it.p.y }
    }
}

/**
 * 유리 돔(벡터 유리) + 안의 캡슐. 중심 [GLayout.domeCenter].
 * [ambient] 잔잔한 들썩임 · 유리 광택의 크기(0 이면 멈춘 그림). [still] 동작 줄이기: 덜컹에 캡슐이 튀지 않는다.
 */
internal fun DrawScope.drawDome(
    now: Double,
    kicks: List<Double>,
    commitTime: Double?,
    sprites: GachaCapsuleSprites,
    ambient: Double,
    /** 유리 광택의 세기(직선 봉투 — [GachaMachineDirector.ambientLinear]). */
    glint: Double,
    still: Boolean,
    theme: GachaMachineTheme,
) {
    val r = GLayout.domeR
    val c = GLayout.domeCenter
    val t = now
    // 유리 뒷면
    drawCircle(
        Brush.radialGradient(listOf(theme.glassBack.first, theme.glassBack.second), center = Offset(c.x - r + 2 * r * 0.42f, c.y - r + 2 * r * 0.38f), radius = r),
        radius = r, center = c,
    )
    drawCircle(Brush.verticalGradient(listOf(Color.Transparent, theme.glassTint), c.y - r, c.y + r), radius = r, center = c)
    // 캡슐
    clipPath(Path().apply { addOval(Rect(c, r - 3f)) }) {
        for (cap in GDome.capsules) {
            var dx = ambient * 0.7 * sin(2 * PI * cap.freq * t + cap.phase)
            var dy = ambient * 0.9 * sin(2 * PI * cap.freq * 1.3 * t + cap.phase * 1.7)
            var rot = ambient * 3.0 * sin(2 * PI * cap.freq * 0.8 * t + cap.phase)
            if (commitTime != null && !still) {
                val tc = now - commitTime
                kicks.forEachIndexed { k, kt ->
                    val tau = tc - kt
                    if (tau < 0 || tau >= 1.8) return@forEachIndexed
                    val amp = if (k == 0) 1.0 else 0.6
                    val f = 2.2 + cap.freq
                    dx += amp * cap.kickX * GMath.ring(tau, f, 3.0)
                    // 위로 튀었다 떨어진다
                    dy -= amp * cap.kickY * cap.lift * abs(GMath.ring(tau, f * 0.75, 3.4))
                    rot += amp * cap.spin * GMath.ring(tau, 0.9, 2.2)
                }
            }
            val center = Offset((c.x + cap.p.x + dx).toFloat(), (c.y + cap.p.y + dy).toFloat())
            rotate((cap.rot + rot).toFloat(), center) {
                drawImageIn(sprites.domeBalls[cap.pair], rectCentered(center, cap.d))
            }
        }
    }
    // 유리 앞면 반사
    drawCircle(Color.White.copy(alpha = if (theme.dark) 0.6f else 0.9f), radius = r - 1.25f, center = c, style = Stroke(2.5f))
    drawCircle(GPalette.hex(0xA98DF0, 0.45f), radius = r + 0.5f, center = c, style = Stroke(1f))
    val inner = r - 12f
    // SwiftUI trim(0.56…0.70)은 3시 방향에서 시계 방향으로 잰다.
    drawArc(
        Color.White.copy(alpha = if (theme.dark) 0.6f else 0.85f), 360f * 0.56f, 360f * 0.14f, false,
        Offset(c.x - inner, c.y - inner), Size(inner * 2, inner * 2), style = Stroke(7f, cap = StrokeCap.Round),
    )
    drawArc(
        Color.White.copy(alpha = if (theme.dark) 0.5f else 0.75f), 360f * 0.73f, 360f * 0.03f, false,
        Offset(c.x - inner, c.y - inner), Size(inner * 2, inner * 2), style = Stroke(5f, cap = StrokeCap.Round),
    )
    val spot = Offset(c.x - r + r * 1.62f, c.y - r + r * 0.62f)
    rotate(30f, spot) { drawOval(Color.White.copy(alpha = if (theme.dark) 0.4f else 0.55f), Offset(spot.x - 7f, spot.y - 4.5f), Size(14f, 9f)) }
    // 가끔 지나가는 유리 광택(잦아들면 안 보인다)
    if (glint > 0.01) {
        val cycle = 4.2
        val p = (((t % cycle) + cycle) % cycle) / 1.1
        if (p < 1) {
            val x = GMath.lerp(-0.6, 1.6, GMath.easeInOutCubic(p))
            val start = Offset((c.x - r + 2 * r * (x - 0.25)).toFloat(), c.y - r)
            val end = Offset((c.x - r + 2 * r * (x + 0.05)).toFloat(), c.y - r + 2 * r * 0.3f)
            clipPath(Path().apply { addOval(Rect(c, r)) }) {
                drawRect(
                    Brush.linearGradient(listOf(Color.Transparent, Color.White.copy(alpha = GachaFade.f(0.35 * glint)), Color.Transparent), start, end),
                    Offset(c.x - r, c.y - r), Size(2 * r, 2 * r),
                )
            }
        }
    }
}

// MARK: - 기계 몸통 · 손잡이 · 뚜껑

internal fun DrawScope.drawMachineBody(art: GachaMachineArt) {
    val rect = Rect(GLayout.bodyOrigin, GLayout.bodySize)
    val body = art.body
    if (body != null) {
        drawImageIn(body, rect)
        return
    }
    val k = GLayout.bodyK
    val o = GLayout.bodyOrigin
    fun r(x: Float, y: Float, w: Float, h: Float) = Rect(o.x + x * k, o.y + y * k, o.x + (x + w) * k, o.y + (y + h) * k)
    val main = r(8f, 70f, 704f, 490f)
    drawRoundRect(Brush.verticalGradient(listOf(GPalette.hex(0xDCCBFF), GPalette.hex(0xB9A0F7)), main.top, main.bottom), main.topLeft, main.size, CornerRadius(40f))
    val neck = r(100f, 2f, 515f, 86f)
    drawRoundRect(Brush.verticalGradient(listOf(Color.White, GPalette.hex(0xE9E1FF)), neck.top, neck.bottom), neck.topLeft, neck.size, CornerRadius(neck.height / 2))
    val socket = r(265f, 129f, 186f, 186f)
    drawOval(GPalette.hex(0xB8A0F2), socket.topLeft, socket.size)
    val frame = r(218f, 318f, 282f, 237f)
    drawRoundRect(GPalette.hex(0xA88EEA), frame.topLeft, frame.size, CornerRadius(14f))
    val chute = r(233f, 333f, 257f, 202f)
    drawRoundRect(Brush.verticalGradient(listOf(GPalette.hex(0x2C1F57), GPalette.hex(0x5A44A0)), chute.top, chute.bottom), chute.topLeft, chute.size, CornerRadius(11f))
}

internal fun DrawScope.drawCap(art: GachaMachineArt) {
    val rect = GLayout.capRect
    val cap = art.cap
    if (cap != null) {
        drawImageIn(cap, rect)
        return
    }
    val c = rect.center
    val pill = Rect(c.x - 44f, c.y + 9f - 10f, c.x + 44f, c.y + 9f + 10f)
    drawRoundRect(Brush.verticalGradient(listOf(GPalette.hex(0xE3D6FF), GPalette.hex(0xBCA3F6)), pill.top, pill.bottom), pill.topLeft, pill.size, CornerRadius(10f))
    drawCircle(Brush.verticalGradient(listOf(GPalette.hex(0xE8DDFF), GPalette.hex(0xB79CF5)), c.y - 19f, c.y + 3f), 11f, Offset(c.x, c.y - 8f))
}

/** 손잡이를 중심 [GLayout.knobCenter] 에, [angle] 도 돌려 [scale] 배로. */
internal fun DrawScope.drawKnob(art: GachaMachineArt, angle: Float, scale: Float, saturation: Float, alpha: Float) {
    val c = GLayout.knobCenter
    val d = GLayout.knobR * 2
    val knob = art.knob
    withTransform({
        rotate(angle, c)
        scale(scale, scale, c)
    }) {
        if (knob != null) {
            drawImageIn(knob, rectCentered(c, d), alpha, saturationBrightnessFilter(saturation, 0f))
        } else {
            drawCircle(Brush.radialGradient(listOf(Color.White, GPalette.hex(0xEDE6FF)), center = Offset(c.x - d / 2, c.y - d / 2), radius = d), d / 2, c, alpha)
            drawCircle(GPalette.hex(0xB49BF5), d / 2 - 2.5f, c, alpha, style = Stroke(5f))
            val bar = rectCentered(c, d * 0.9f, d * 0.26f)
            drawRoundRect(Brush.verticalGradient(listOf(GPalette.hex(0xCDB8FF), GPalette.hex(0xA587F2)), bar.top, bar.bottom), bar.topLeft, bar.size, CornerRadius(bar.height / 2), alpha = alpha)
            drawCircle(Color.White, d * 0.12f, c, alpha)
        }
    }
}

/** 손잡이 둘레 톱니 점 여덟(켜진 수 [lit] · 빛 [alpha]). */
internal fun DrawScope.drawNotchRing(lit: Int, alpha: Float) {
    val c = GLayout.knobCenter
    for (i in 0 until 8) {
        val a = (-90 + 45.0 * (i + 1)) * PI / 180
        val on = i < lit
        val p = Offset((c.x + cos(a) * GLayout.notchR).toFloat(), (c.y + sin(a) * GLayout.notchR).toFloat())
        if (on) {
            drawCircle(GPalette.hex(0x8E6BFF, 0.35f * alpha), 6f, p)
            drawCircle(Color.White, 3.5f, p, alpha = max(0.42f, alpha))
        } else {
            drawCircle(Color.White.copy(alpha = 0.42f), 2.75f, p)
        }
    }
}
