// 원본: Sources/CheckMobileKit/Games/GamesMahjongTileArt.swift @ 928d5562(폰 1.0.18 패 그림) — Android 판 8
//
// 그리기 식(몸체 · 뒷면 · 통 · 삭 · 1삭 새싹 · 글자 · 모서리 글자)은 아이폰(= 맥 `MahjongTileArt` 글자 그대로)을 옮겼다 — 배치는 코어
// [MahjongTileArtModel](순수 값). 다른 것은 굽는 자리뿐이다: 아이폰은 비트맵을 구워 캐시하고, 여기는 Canvas 에 바로 그린다(글자 배치만 캐시).
// 패는 원래 크기(46×62 등) 좌표로 그리고 표시 사각형에 맞춰 변환한다. 받은 팔레트(Storage)는 쓰지 않는다 — 코드 팔레트(고른 'A 지금 그대로').
// 1삭은 고른 그림(새싹)만 옮겼다 — 다른 선택지(아잉 얼굴 · 대나무)는 화면이 쓰지 않는다.
package com.yehsung.aingcheck.ui.games.mahjong

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileArtModel
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileArtStyle
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileFace
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileInk
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileLayout
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTilePalette
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileSize
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileState
import kotlin.math.max

/** "#RRGGBB" → 색(틀리면 회색). */
internal fun mahjongColor(hex: String, alpha: Float = 1f): Color {
    val rgb = MahjongTilePalette.rgb(hex) ?: Triple(0.5, 0.5, 0.5)
    return Color(rgb.first.toFloat(), rgb.second.toFloat(), rgb.third.toFloat(), alpha)
}

/** 회전을 반영한 원래 크기. */
internal fun mahjongImageSize(size: MahjongTileSize, rotation: Int): Size =
    if (rotation % 2 == 0) Size(size.width, size.height) else Size(size.height, size.width)

/** 패 그리개 — 글자 배치를 캐시한다(한 화면 하나). */
class MahjongTilePainter internal constructor(private val measurer: TextMeasurer, private val density: Density) {
    private val palette = MahjongTilePalette.code(MahjongTileArtStyle.chosen.backScheme)
    private val glyphs = HashMap<String, TextLayoutResult>()

    private fun glyph(text: String, height: Float, color: Color, serif: Boolean): TextLayoutResult {
        val key = "$text|${(height * 10).toInt()}|${color.value}|$serif"
        return glyphs.getOrPut(key) {
            if (glyphs.size > 400) glyphs.clear()
            val fontSize = with(density) { height.toSp() }
            measurer.measure(
                text,
                style = TextStyle(
                    color = color, fontSize = fontSize, lineHeight = fontSize, fontWeight = FontWeight.Bold,
                    fontFamily = if (serif) FontFamily.Serif else FontFamily.Default,
                ),
                softWrap = false,
            )
        }
    }

    /** 패 한 장을 [rect](회전 반영 사각형)에 그린다. */
    fun draw(
        scope: DrawScope,
        face: MahjongTileFace,
        size: MahjongTileSize,
        rect: Rect,
        state: MahjongTileState = MahjongTileState.normal,
        rotation: Int = 0,
        cornerLabels: Boolean = true,
    ) {
        val rot = ((rotation % 4) + 4) % 4
        val w = size.width
        val h = size.height
        val natural = mahjongImageSize(size, rot)
        val corners = cornerLabels && !size.isSimplified
        scope.withTransform({
            translate(rect.left, rect.top)
            scale(rect.width / natural.width, rect.height / natural.height, Offset.Zero)
            when (rot) {
                1 -> { translate(h, 0f); rotate(90f, Offset.Zero) }
                2 -> { translate(w, h); rotate(180f, Offset.Zero) }
                3 -> { translate(0f, w); rotate(-90f, Offset.Zero) }
                else -> Unit
            }
        }) {
            val alpha = when (state) {
                MahjongTileState.taken -> 0.42f
                MahjongTileState.disabled -> 0.38f
                else -> 1f
            }
            val layered = alpha < 1f
            if (layered) drawContext.canvas.saveLayer(Rect(0f, 0f, w, h), Paint().apply { this.alpha = alpha })
            drawNatural(this, face, size, state, corners)
            if (layered) drawContext.canvas.restore()
        }
    }

    private fun drawNatural(s: DrawScope, face: MahjongTileFace, size: MahjongTileSize, state: MahjongTileState, corners: Boolean) {
        val w = size.width
        val h = size.height
        val radius = w * 0.14f
        val layout = MahjongTileArtModel.layout(face)
        if (layout.isBack) {
            drawBack(s, w, h, radius)
        } else {
            drawBody(s, w, h, radius)
            drawFace(s, layout, Rect(w * 0.10f, h * 0.10f, w * 0.90f, h * 0.84f), size)
            if (corners) {
                MahjongTileArtStyle.chosen.cornerLabel.label(layout, face)?.let { drawCorner(s, it, w, h) }
            }
            if (state == MahjongTileState.tsumogiri) {
                s.drawRoundRect(Color(0f, 0f, 0f, 0.16f), Offset(0.5f, 0.5f), Size(w - 1, h - 1), CornerRadius(radius))
            }
        }
        if (state == MahjongTileState.highlighted) {
            s.drawRoundRect(Color(0.33f, 0.67f, 1.0f), Offset(1f, 1f), Size(w - 2, h - 2), CornerRadius(radius), style = Stroke(2f))
        }
    }

    /** 몸체: 베벨(아래 8%) 위에 크림-라벤더 그라데이션, 가는 테두리. */
    private fun drawBody(s: DrawScope, w: Float, h: Float, radius: Float) {
        s.drawRoundRect(mahjongColor(palette.bevel), Offset.Zero, Size(w, h), CornerRadius(radius))
        val top = h * 0.92f
        s.drawRoundRect(
            Brush.verticalGradient(listOf(mahjongColor(palette.bodyTop), mahjongColor(palette.bodyBottom)), 0f, top),
            Offset.Zero, Size(w, top), CornerRadius(radius),
        )
        s.drawRoundRect(mahjongColor("#8E84B4"), Offset(0.5f, 0.5f), Size(w - 1, h - 1), CornerRadius(radius), style = Stroke(1f))
    }

    /** 뒷면: 남색 그라데이션 + 분홍 테두리 + 가운데 작은 고리. */
    private fun drawBack(s: DrawScope, w: Float, h: Float, radius: Float) {
        s.drawRoundRect(
            Brush.verticalGradient(listOf(mahjongColor(palette.backTop), mahjongColor(palette.backBottom)), 0f, h),
            Offset.Zero, Size(w, h), CornerRadius(radius),
        )
        val rim = max(1f, w * 0.07f)
        s.drawRoundRect(mahjongColor(palette.backRim), Offset(rim / 2, rim / 2), Size(w - rim, h - rim), CornerRadius(radius), style = Stroke(rim))
        val ring = w * 0.16f
        s.drawCircle(mahjongColor(palette.backRim, 0.8f), ring, Offset(w / 2, h / 2), style = Stroke(max(1f, w * 0.05f)))
    }

    private fun drawFace(s: DrawScope, layout: MahjongTileLayout, face: Rect, size: MahjongTileSize) {
        fun point(x: Double, y: Double) = Offset(face.left + face.width * x.toFloat(), face.top + face.height * y.toFloat())
        val bodyTop = mahjongColor(palette.bodyTop)
        // 통 — 바깥 고리 + 몸체색 틈 + 가운데 점.
        for (pip in layout.pips) {
            val c = point(pip.center.x, pip.center.y)
            val r = face.width * pip.radius.toFloat()
            val ink = mahjongColor(palette.hex(pip.ink))
            s.drawCircle(ink, r, c)
            s.drawCircle(bodyTop, r * 0.64f, c)
            s.drawCircle(ink, r * 0.34f, c)
        }
        // 삭 — 둥근 막대 + 가운데 마디 줄. 작은 크기는 막대를 가늘게.
        val stickWidth = face.width * (if (size.isSimplified) 0.08f else 0.115f)
        for (stick in layout.sticks) {
            val c = point(stick.center.x, stick.center.y)
            val length = face.height * stick.length.toFloat()
            val left = c.x - stickWidth / 2
            s.drawRoundRect(mahjongColor(palette.hex(stick.ink)), Offset(left, c.y - length / 2), Size(stickWidth, length), CornerRadius(stickWidth / 2))
            s.drawRect(bodyTop, Offset(left, c.y - max(0.5f, length * 0.04f)), Size(stickWidth, max(1f, length * 0.08f)))
        }
        if (layout.sprout) drawSprout(s, face)
        if (layout.hakuFrame) {
            val fx = face.width * 0.16f
            val fy = face.height * 0.12f
            val frame = Rect(face.left + fx, face.top + fy, face.right - fx, face.bottom - fy)
            s.drawRoundRect(
                mahjongColor(palette.hex(MahjongTileInk.lavender)), frame.topLeft, frame.size, CornerRadius(frame.width * 0.2f),
                style = Stroke(max(1f, face.width * 0.09f)),
            )
        }
        for (g in layout.glyphs) {
            val layoutResult = glyph(g.text, face.height * g.size.toFloat(), mahjongColor(palette.hex(g.ink)), serif = true)
            val c = point(g.center.x, g.center.y)
            s.drawText(layoutResult, topLeft = Offset(c.x - layoutResult.size.width / 2f, c.y - layoutResult.size.height / 2f))
        }
        if (layout.goldDot) {
            val r = face.width * 0.09f
            s.drawCircle(mahjongColor(palette.hex(MahjongTileInk.gold)), r, Offset(face.right - r * 0.6f, face.top + r * 0.4f))
        }
    }

    /** 1삭 — 우리 모양: 굵은 대 한 마디 + 잎 둘 + 빨간 점(새싹). */
    private fun drawSprout(s: DrawScope, face: Rect) {
        val green = mahjongColor(palette.hex(MahjongTileInk.green))
        val stemWidth = face.width * 0.16f
        val stemTop = face.top + face.height * 0.42f
        val stemHeight = face.height * 0.52f
        val stemLeft = face.center.x - stemWidth / 2
        s.drawRoundRect(green, Offset(stemLeft, stemTop), Size(stemWidth, stemHeight), CornerRadius(stemWidth / 2))
        s.drawRect(mahjongColor(palette.bodyTop), Offset(stemLeft, stemTop + stemHeight / 2), Size(stemWidth, max(1f, face.height * 0.035f)))
        for (side in listOf(-1f, 1f)) {
            val cx = face.center.x + side * face.width * 0.2f
            val cy = face.top + face.height * 0.36f
            s.rotate(side * -0.55f * (180f / kotlin.math.PI.toFloat()), Offset(cx, cy)) {
                drawOval(green, Offset(cx - face.width * 0.2f, cy - face.height * 0.075f), Size(face.width * 0.4f, face.height * 0.15f))
            }
        }
        val r = face.width * 0.1f
        s.drawCircle(mahjongColor(palette.hex(MahjongTileInk.red)), r, Offset(face.center.x, face.top + face.height * 0.18f))
    }

    /** 모서리 보조 글자(수패 1~9 · 자패 동남서북백발중). */
    private fun drawCorner(s: DrawScope, label: String, w: Float, h: Float) {
        val layoutResult = glyph(label, h * 0.15f, mahjongColor(palette.ink, 0.72f), serif = false)
        s.drawText(layoutResult, topLeft = Offset(w * 0.07f, h * 0.04f - layoutResult.size.height * 0.12f))
    }
}

@Composable
fun rememberMahjongTilePainter(): MahjongTilePainter {
    val measurer = rememberTextMeasurer(cacheSize = 64)
    val density = androidx.compose.ui.platform.LocalDensity.current
    return remember(measurer, density) { MahjongTilePainter(measurer, density) }
}

/** 패 한 장(손패 · 결과 · 작은 조각). [display] 를 주면 그 크기로 그린다. */
@Composable
fun GamesMahjongTileView(
    face: MahjongTileFace,
    modifier: Modifier = Modifier,
    size: MahjongTileSize = MahjongTileSize.hand,
    state: MahjongTileState = MahjongTileState.normal,
    rotation: Int = 0,
    cornerLabels: Boolean = true,
    display: DpSize? = null,
    painter: MahjongTilePainter = rememberMahjongTilePainter(),
) {
    val natural = mahjongImageSize(size, rotation)
    val frame = display ?: DpSize(natural.width.dp, natural.height.dp)
    Canvas(modifier.size(frame).semantics { contentDescription = face.spokenName }) {
        painter.draw(this, face, size, Rect(Offset.Zero, this.size), state, rotation, cornerLabels)
    }
}

/** 띠 한 장(Canvas 하나) — 패마다 사각형에 그린다. 좌표는 이 Canvas 안 px. */
data class GamesMahjongScaledTile(val tile: GamesMahjongStripTile, val rect: Rect)

@Composable
fun GamesMahjongTileStrip(tiles: List<GamesMahjongScaledTile>, modifier: Modifier, cornerLabels: Boolean = true, accessibilityText: String = "") {
    val painter = rememberMahjongTilePainter()
    Canvas(modifier.semantics { contentDescription = accessibilityText }) {
        for (item in tiles) painter.draw(this, item.tile.face, item.tile.size, item.rect, item.tile.state, item.tile.rotation, cornerLabels)
    }
}

/** dp 크기 → Dp 쌍. */
internal fun dpSize(width: Dp, height: Dp) = DpSize(width, height)
