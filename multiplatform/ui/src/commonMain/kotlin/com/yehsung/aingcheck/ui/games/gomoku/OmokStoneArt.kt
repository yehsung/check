// 원본: Sources/CheckCore/OmokStoneSkin.swift(OmokStoneArt — dice · cat · pixel · glossBody · dropShadow · hash) @ e4995a3a
// 원본: Sources/CheckMobileKit/Games/GamesGomokuBoardCanvas.swift(drawStone 의 스킨 갈래 — 반투명은 층 하나) @ 928d5562
//
// 오목알 스킨 그림(판 8). 맥 · 폰의 CoreGraphics 식을 Compose DrawScope 로 옮긴다 — 좌표는 둘 다 y 가 아래로 자라고 빛은 왼쪽 위다.
// 대표 원칙(3차): 몸 바탕은 흑 = 짙은 무채색 · 백 = 밝은 무채색만, 색은 눈 · 테처럼 작은 곳만(섞인 판에서도 흑백이 갈린다).
// 고양이 귀의 둥근 끝(CG `copy(strokingWithWidth:)` 합집합)은 같은 붓의 둥근 선 긋기로 그린다 — 칠한 넓이가 같다.
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import com.yehsung.aingcheck.core.rules.achievements.OmokStoneSkin
import kotlin.math.floor
import kotlin.math.sin

object OmokStoneArt {
    /** 돌 하나를 스킨으로 그린다. [opacity] < 1(미리보기)이면 투명 층 하나로 묶어 그림자 · 몸이 겹쳐 진해지지 않게 한다. */
    fun draw(scope: DrawScope, skin: OmokStoneSkin, c: Offset, r: Float, black: Boolean, seed: Int, opacity: Float = 1f) = with(scope) {
        if (opacity < 1f) {
            val bounds = Rect(c.x - r * 1.6f, c.y - r * 1.6f, c.x + r * 1.6f, c.y + r * 1.6f)
            drawContext.canvas.saveLayer(bounds, Paint().apply { alpha = opacity })
            drawSkin(skin, c, r, black, seed)
            drawContext.canvas.restore()
        } else {
            drawSkin(skin, c, r, black, seed)
        }
    }

    private fun DrawScope.drawSkin(skin: OmokStoneSkin, c: Offset, r: Float, black: Boolean, seed: Int) = when (skin) {
        OmokStoneSkin.dice -> dice(c, r, black, seed)
        OmokStoneSkin.cat -> cat(c, r, black)
        OmokStoneSkin.pixel -> pixel(c, r, black)
    }

    private fun w(v: Float, a: Float = 1f): Color = Color(v, v, v, a)
    private fun h(hex: Int, a: Float = 1f): Color = Color(((hex shr 16) and 255) / 255f, ((hex shr 8) and 255) / 255f, (hex and 255) / 255f, a)

    /** 맥 `hash(a, b)` — sin 식 그대로(돌 번호마다 주사위 눈이 갈린다). */
    internal fun hash(a: Int, b: Int): Double {
        val v = sin(a.toDouble() * 127.1 + b.toDouble() * 311.7) * 43758.5453
        return v - floor(v)
    }

    private fun DrawScope.dropShadow(p: Path, dx: Float, dy: Float, a: Float) {
        translate(dx, dy) { drawPath(p, w(0f, a)) }
    }

    /** 맥 `glossBody` — 빛 쪽 방사 칠(흑 0.42→0.05 · 백 1.0→0.80) + 백은 옅은 테. */
    private fun DrawScope.glossBody(p: Path, c: Offset, r: Float, black: Boolean, extraStroke: (DrawScope.(Brush) -> Unit)? = null) {
        val hl = Offset(c.x - r * 0.35f, c.y - r * 0.4f)
        val brush = if (black) Brush.radialGradient(listOf(w(0.42f), w(0.05f)), center = hl, radius = r * 1.5f)
        else Brush.radialGradient(listOf(w(1.0f), w(0.80f)), center = hl, radius = r * 1.6f)
        drawPath(p, brush)
        extraStroke?.invoke(this, brush)
        if (!black) drawPath(p, w(0f, 0.22f), style = Stroke(0.8f * density))
    }

    private fun rectAround(c: Offset, rx: Float, ry: Float): Rect = Rect(c.x - rx, c.y - ry, c.x + rx, c.y + ry)

    private fun DrawScope.dice(c: Offset, r: Float, black: Boolean, i: Int) {
        val half = r * 0.86f
        val cr = r * 0.30f
        val p = Path().apply { addRoundRect(RoundRect(rectAround(c, half, half), CornerRadius(cr))) }
        dropShadow(p, r * 0.06f, r * 0.14f, 0.25f)
        glossBody(p, c, r, black)
        val inner = Path().apply { addRoundRect(RoundRect(rectAround(c, half * 0.86f, half * 0.86f), CornerRadius(cr * 0.8f))) }
        drawPath(inner, if (black) w(1f, 0.10f) else w(0f, 0.06f), style = Stroke(r * 0.03f))
        val face = 1 + (hash(i, 3) * 6).toInt() % 6
        val u = half * 0.50f
        val spots: List<List<Pair<Float, Float>>> = listOf(
            emptyList(), listOf(0f to 0f), listOf(-1f to -1f, 1f to 1f), listOf(-1f to -1f, 0f to 0f, 1f to 1f),
            listOf(-1f to -1f, 1f to -1f, -1f to 1f, 1f to 1f), listOf(-1f to -1f, 1f to -1f, 0f to 0f, -1f to 1f, 1f to 1f),
            listOf(-1f to -1f, 1f to -1f, -1f to 0f, 1f to 0f, -1f to 1f, 1f to 1f),
        )
        val pr = r * (if (face == 1) 0.24f else 0.145f)
        for ((sx, sy) in spots[face]) drawCircle(if (black) w(0.96f) else w(0.08f), pr, Offset(c.x + sx * u, c.y + sy * u))
    }

    private fun DrawScope.cat(c: Offset, r: Float, black: Boolean) {
        val bc = Offset(c.x, c.y + r * 0.09f)
        val br = r * 0.88f
        val body = Path().apply { addOval(Rect(bc.x - br, bc.y - br, bc.x + br, bc.y + br)) }
        val ears = ArrayList<Path>()
        val inner = ArrayList<Path>()
        var shape = body
        for (s in listOf(-1f, 1f)) {
            val tri = Path().apply {
                moveTo(bc.x + s * r * 0.24f, bc.y - r * 0.70f)
                lineTo(bc.x + s * r * 0.70f, bc.y - r * 1.06f)
                lineTo(bc.x + s * r * 0.84f, bc.y - r * 0.32f)
                close()
            }
            ears += tri
            shape = Path().apply { op(shape, tri, PathOperation.Union) }
            inner += Path().apply {
                moveTo(bc.x + s * r * 0.38f, bc.y - r * 0.66f)
                lineTo(bc.x + s * r * 0.67f, bc.y - r * 0.92f)
                lineTo(bc.x + s * r * 0.75f, bc.y - r * 0.48f)
                close()
            }
        }
        val round = Stroke(r * 0.14f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        // 그림자 — 몸 + 귀(둥근 끝까지).
        translate(r * 0.06f, r * 0.14f) {
            drawPath(shape, w(0f, 0.25f))
            for (e in ears) drawPath(e, w(0f, 0.25f), style = round)
        }
        glossBody(shape, c, r, black) { brush -> for (e in ears) drawPath(e, brush, style = round) }
        for (e in inner) drawPath(e, if (black) h(0x4B3542) else h(0xF4B6C6))
        for (s in listOf(-1f, 1f)) {
            val e = Offset(bc.x + s * r * 0.36f, bc.y - r * 0.12f)
            drawOval(if (black) h(0xF2CF3A) else h(0x4F9FE6), topLeft = Offset(e.x - r * 0.17f, e.y - r * 0.19f), size = Size(r * 0.34f, r * 0.38f))
            drawOval(w(0.04f), topLeft = Offset(e.x - r * 0.055f, e.y - r * 0.16f), size = Size(r * 0.11f, r * 0.32f))
            drawCircle(w(1f, 0.95f), r * 0.045f, Offset(e.x - r * 0.06f, e.y - r * 0.08f))
            // 수염
            val whisker = if (black) w(0.78f, 0.85f) else w(0.40f, 0.8f)
            for (k in 0 until 2) {
                val y0 = bc.y + r * (0.20f + 0.11f * k)
                drawLine(
                    whisker, Offset(bc.x + s * r * 0.42f, y0), Offset(bc.x + s * r * 0.86f, y0 - r * (0.10f - 0.12f * k)),
                    strokeWidth = r * 0.03f, cap = StrokeCap.Round,
                )
            }
        }
        // 코 · 입(ω)
        val n = Offset(bc.x, bc.y + r * 0.16f)
        drawPath(
            Path().apply {
                moveTo(n.x - r * 0.08f, n.y - r * 0.05f)
                lineTo(n.x + r * 0.08f, n.y - r * 0.05f)
                lineTo(n.x, n.y + r * 0.05f)
                close()
            },
            if (black) h(0xE38AA6) else h(0xF08AA8),
        )
        val mouth = if (black) w(0.75f) else w(0.25f)
        for (dx in listOf(-0.07f, 0.07f)) {
            val ac = Offset(n.x + r * dx, n.y + r * 0.08f)
            val rr = r * 0.07f
            // CG addArc(0 → π, clockwise: false) 는 y 아래 좌표에서 아래쪽 반원 — Compose drawArc 0° → 180° 시계 방향과 같다.
            drawArc(mouth, startAngle = 0f, sweepAngle = 180f, useCenter = false, topLeft = Offset(ac.x - rr, ac.y - rr), size = Size(rr * 2, rr * 2),
                style = Stroke(r * 0.035f, cap = StrokeCap.Round))
        }
    }

    private fun DrawScope.pixel(c: Offset, r: Float, black: Boolean) {
        val n = 9
        val cell = 2 * r / n
        fun inside(x: Int, y: Int): Pair<Float, Float>? {
            val dx = (x + 0.5f) / n * 2 - 1
            val dy = (y + 0.5f) / n * 2 - 1
            return if (dx * dx + dy * dy <= 1f) dx to dy else null
        }
        for (y in 0 until n) for (x in 0 until n) {
            if (inside(x, y) == null) continue
            drawRect(w(0f, 0.22f), topLeft = Offset(c.x - r + x * cell + cell * 0.5f, c.y - r + y * cell + cell * 0.9f), size = Size(cell, cell))
        }
        for (y in 0 until n) for (x in 0 until n) {
            val (dx, dy) = inside(x, y) ?: continue
            val edge = dx * dx + dy * dy > 0.62f
            val lit = (dx + 0.35f) * (dx + 0.35f) + (dy + 0.40f) * (dy + 0.40f) < 0.10f
            val col = if (black) (if (lit) h(0x8C86A8) else if (edge) h(0x15131E) else h(0x2C2838))
            else (if (lit) w(1f) else if (edge) h(0xB9B6C8) else h(0xEDEBF5))
            drawRect(col, topLeft = Offset(c.x - r + x * cell, c.y - r + y * cell), size = Size(cell + 0.5f, cell + 0.5f))
        }
    }
}
