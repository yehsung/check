// 원본: Sources/CheckCore/GachaMachine/GachaMachineEffects.swift @ 3bd04bd
//
// 금(균열) · 새는 빛 · 터지는 빛 · 손잡이 힌트 호. SwiftUI Canvas 를 Compose DrawScope 로 옮겼다(설계 좌표).
// 이식 차이: `.blur` 층은 그리지 않고 넓은 반투명 획 · 방사형 그라데이션으로 대신한다(기기마다 같은 픽셀). 불투명도는 [GachaFade] 로만.
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.sin

// MARK: - 금(균열)

/** 금 하나: 단위 좌표(캡슐 반지름 = 1, 중심 0,0) 꺾은선 + [첫 톡 뒤, 두 번째 톡 뒤] 보이는 비율. */
class GCrack(val pts: List<Offset>, val len: List<Double>)

object GCracks {
    fun make(seed: ULong): List<GCrack> {
        val r = GRandom(seed xor 0xC0FFEEuL)
        fun walk(from: Offset, heading: Double, steps: Int, lo: Double, hi: Double, wiggle: Double): List<Offset> {
            val pts = mutableListOf(from)
            var p = from
            var side = r.sign()
            repeat(steps) {
                side = -side
                val a = heading + side * r.range(wiggle * 0.4, wiggle)
                val l = r.range(lo, hi)
                p = Offset((p.x + cos(a) * l).toFloat(), (p.y + sin(a) * l).toFloat())
                pts += p
            }
            return pts
        }
        val x0 = r.range(-0.28, 0.12)
        val up = -PI / 2 + r.range(-0.25, 0.25)
        val a = walk(Offset(x0.toFloat(), 0.04f), up, 6, 0.14, 0.19, 0.65)
        val bHeading = (if (a[2].x < 0) -0.35 else -2.8) + r.range(-0.2, 0.2)
        val b = walk(a[2], bHeading, 4, 0.12, 0.17, 0.6)
        val cStart = Offset((x0 + r.range(0.18, 0.34)).toFloat(), 0.07f)
        val c = walk(cStart, PI / 2 + r.range(-0.4, 0.4), 4, 0.13, 0.18, 0.7)
        val dHeading = if (a[4].x < 0) -2.6 else -0.5
        val d = walk(a[4], dHeading, 3, 0.10, 0.14, 0.6)
        val eStart = Offset((x0 - r.range(0.25, 0.4)).toFloat(), 0.06f)
        val e = walk(eStart, PI / 2 + 0.5, 3, 0.12, 0.16, 0.6)
        return listOf(
            GCrack(a, listOf(0.55, 1.0)),
            GCrack(c, listOf(0.35, 1.0)),
            GCrack(b, listOf(0.0, 1.0)),
            GCrack(d, listOf(0.0, 1.0)),
            GCrack(e, listOf(0.0, 0.9)),
        )
    }

    /** 탭 시각들로 금 하나의 지금 비율. */
    fun progress(crack: GCrack, tapTimes: List<Double>, now: Double): Double {
        if (tapTimes.isEmpty()) return 0.0
        val n = min(tapTimes.size, 2)
        val target = crack.len[n - 1]
        val prev = if (n >= 2) crack.len[n - 2] else 0.0
        val t = now - tapTimes[n - 1]
        return GMath.lerp(prev, target, GMath.easeOutCubic(t / 0.14))
    }

    fun partial(pts: List<Offset>, frac: Double): List<Offset> {
        if (frac <= 0 || pts.size <= 1) return emptyList()
        val lens = (1 until pts.size).map { i -> hypot((pts[i].x - pts[i - 1].x).toDouble(), (pts[i].y - pts[i - 1].y).toDouble()) }
        var remain = lens.sum() * min(1.0, frac)
        val out = mutableListOf(pts[0])
        for (i in 1 until pts.size) {
            if (remain >= lens[i - 1]) {
                out += pts[i]; remain -= lens[i - 1]
            } else {
                out += GMath.lerp(pts[i - 1], pts[i], remain / lens[i - 1]); break
            }
        }
        return out
    }
}

private fun crackPaths(cracks: List<GCrack>, tapTimes: List<Double>, now: Double, c: Offset, r: Float): List<Path> =
    cracks.mapNotNull { cr ->
        val pts = GCracks.partial(cr.pts, GCracks.progress(cr, tapTimes, now))
        if (pts.size < 2) null else Path().apply {
            pts.forEachIndexed { i, p -> if (i == 0) moveTo(c.x + p.x * r, c.y + p.y * r) else lineTo(c.x + p.x * r, c.y + p.y * r) }
        }
    }

/** 캡슐 표면의 금 + 새어 나오는 빛(캡슐 위에 얹는다, 원으로 잘림). 캡슐 중심 [c] · 지름 [d]. */
internal fun DrawScope.drawCrackOverlay(cracks: List<GCrack>, tapTimes: List<Double>, now: Double, glow: Double, rare: GRare?, c: Offset, d: Float) {
    val r = d / 2
    clipPath(Path().apply { addOval(Rect(c, r - 1f)) }) {
        val paths = crackPaths(cracks, tapTimes, now, c, r)
        if (paths.isEmpty()) return@clipPath
        val light = rare?.light ?: Color.White
        val glowColor = rare?.primary ?: GPalette.hex(0xFFF6D8)
        val round = { w: Float -> Stroke(w, cap = StrokeCap.Round, join = StrokeJoin.Round) }
        // 어두운 가장자리
        for (p in paths) drawPath(p, GPalette.plum.copy(alpha = 0.45f), style = round(2.6f))
        // 번지는 빛(넓고 옅게 + 좁고 밝게 — 원문 흐림 층의 자리)
        for (p in paths) drawPath(p, glowColor.copy(alpha = GachaFade.f(0.25 + 0.15 * glow)), style = round((8 + 9 * glow).toFloat()))
        for (p in paths) drawPath(p, Color.White.copy(alpha = GachaFade.f(0.6 + 0.3 * glow)), style = round((3.5 + 2.5 * glow).toFloat()))
        // 밝은 심
        for (p in paths) drawPath(p, light.copy(alpha = 0.95f), style = round((1.4 + 0.6 * glow).toFloat()))
    }
}

/** 캡슐 뒤에서 금 사이로 뻗는 빛줄기 + 둥근 후광(캡슐보다 먼저 그린다). 캡슐 중심 [c] · 지름 [capsuleD] · 회전 [rotation](도). */
internal fun DrawScope.drawLeakLight(
    cracks: List<GCrack>,
    tapTimes: List<Double>,
    now: Double,
    intensity: Double,
    halo: Double,
    rare: GRare?,
    c: Offset,
    capsuleD: Float,
    rotation: Float,
    blend: BlendMode,
) {
    val r = capsuleD / 2
    val col = rare?.primary ?: GPalette.hex(0xFFF8E4)
    if (halo > 0) {
        val hr = r * (1.25f + 0.35f * halo.toFloat()) + 14f
        drawCircle(
            Brush.radialGradient(listOf(col.copy(alpha = GachaFade.f(0.85 * halo)), col.copy(alpha = 0f)), center = c, radius = hr),
            hr, c, blendMode = blend,
        )
    }
    if (intensity <= 0) return
    val rot = rotation * PI / 180
    cracks.forEachIndexed { ci, cr ->
        val pts = GCracks.partial(cr.pts, GCracks.progress(cr, tapTimes, now))
        pts.forEachIndexed { i, p0 ->
            if (i == 0) return@forEachIndexed
            // 캡슐과 함께 돈다
            val px = p0.x * cos(rot) - p0.y * sin(rot)
            val py = p0.x * sin(rot) + p0.y * cos(rot)
            val rayCol = if (rare == GRare.Rainbow) rare.ray(ci * 3 + i, 14) else col
            val dist = hypot(px, py)
            if (dist <= 0.25) return@forEachIndexed
            val a = atan2(py, px)
            val len = r * (1.1 + 1.1 * min(1.6, intensity)) * (0.7 + 0.3 * ((i * 37) % 5) / 4.0)
            val w = 0.08 + 0.05 * min(1.6, intensity)
            val o = Offset((c.x + px * r * 0.9).toFloat(), (c.y + py * r * 0.9).toFloat())
            val path = Path().apply {
                moveTo(o.x, o.y)
                lineTo((o.x + cos(a - w) * len).toFloat(), (o.y + sin(a - w) * len).toFloat())
                lineTo((o.x + cos(a + w) * len).toFloat(), (o.y + sin(a + w) * len).toFloat())
                close()
            }
            drawPath(
                path,
                Brush.radialGradient(listOf(rayCol.copy(alpha = GachaFade.f(0.75 * intensity)), rayCol.copy(alpha = 0f)), center = o, radius = len.toFloat()),
                blendMode = blend,
            )
        }
    }
}

// MARK: - 터지는 빛(빛줄기 · 고리 · 심) — 별/반짝이 모양 없음

/**
 * [t] 터진 뒤 시간(음수면 아무것도). [rare] 희귀 공개면 그 빛깔 · 긴 빛줄기 · 고리 넷. [spin] 빛줄기 회전 각(라디안).
 * [reduced] 동작 줄이기: 빛줄기 · 고리 없이 가운데 빛만 은은하게 켠다.
 */
internal fun DrawScope.drawLightBurst(t: Double, rare: GRare?, c: Offset, dark: Boolean, spin: Double, reduced: Boolean = false) {
    if (t < 0) return
    val gold = rare != null
    val blend = if (gold) BlendMode.Plus else BlendMode.SrcOver
    if (!reduced) {
        // 빛줄기: 확 켜졌다가 은은하게 남는다(불투명도는 직선 — 원문은 easeOut 켜짐 · smooth 잦아듦).
        val rays = GachaFade.rise(0.0, if (gold) 0.35 else 0.18, t) * GMath.lerp(1.0, if (gold) 0.75 else 0.55, GachaFade.rise(0.25, 1.4, t))
        val n = if (gold) 18 else 12
        val rot = spin + 0.2
        val big = (if (gold) 330.0 else 250.0) * GMath.lerp(0.55, 1.0, GMath.easeOutCubic(t / 0.6))
        for (i in 0 until n) {
            val longRay = i % 2 == 0
            val a = i.toDouble() / n * 2 * PI + rot
            val len = big * (if (longRay) 1.0 else 0.68)
            val half = (if (gold) 0.075 else 0.065) * (if (longRay) 1.0 else 0.7)
            val path = Path().apply {
                moveTo(c.x, c.y)
                lineTo((c.x + cos(a - half) * len).toFloat(), (c.y + sin(a - half) * len).toFloat())
                lineTo((c.x + cos(a + half) * len).toFloat(), (c.y + sin(a + half) * len).toFloat())
                close()
            }
            val alpha = (if (dark) 0.55 else 0.75) * rays * (if (longRay) 1.0 else 0.75)
            val rayCol = rare?.ray(i, n) ?: Color.White
            drawPath(
                path,
                Brush.radialGradient(
                    0f to rayCol.copy(alpha = GachaFade.f(alpha)),
                    (10f / len.toFloat()) to rayCol.copy(alpha = GachaFade.f(alpha)),
                    1f to rayCol.copy(alpha = 0f),
                    center = c, radius = len.toFloat(),
                ),
                blendMode = blend,
            )
        }
    }
    // 심 광채
    val core = if (reduced) GachaFade.rise(0.0, 0.35, t) * (if (gold) 0.75 else 0.6)
    else GMath.lerp(1.0, if (gold) 0.7 else 0.55, GachaFade.rise(0.1, 1.0, t))
    val coreR = ((if (gold) 120.0 else 95.0) * (if (reduced) 1.0 else GMath.lerp(0.6, 1.0, GMath.easeOutCubic(t / 0.4)))).toFloat() + 10f
    val coreCol = rare?.core ?: Color.White
    drawCircle(
        Brush.radialGradient(
            0f to coreCol.copy(alpha = GachaFade.f(0.95 * core)),
            0.5f to coreCol.copy(alpha = GachaFade.f(0.35 * core)),
            1f to coreCol.copy(alpha = 0f),
            center = c, radius = coreR,
        ),
        coreR, c, blendMode = blend,
    )
    if (reduced) return
    // 퍼지는 빛 고리
    val starts = if (gold) listOf(0.0, 0.30, 0.60, 0.95) else listOf(0.0, 0.13)
    val dur = if (gold) 1.6 else 0.85
    starts.forEachIndexed { k, s ->
        val tau = t - s
        if (tau <= 0 || tau >= dur) return@forEachIndexed
        val p = tau / dur
        val rr = GMath.lerp(50.0, if (gold) 420.0 else 300.0, GMath.easeOutCubic(p)).toFloat()
        val w = ((if (gold) 18.0 else 12.0) * (1 - p) + 1.5).toFloat()
        // 원문 pow(1−p, 1.6) 의 자리 — 직선으로 잦아든다.
        val a = (if (gold) 0.85 else 0.75) * GachaFade.fall(0.0, 1.0, p)
        val col = rare?.ring(k) ?: Color.White
        drawCircle(col.copy(alpha = GachaFade.f(a * 0.45)), rr, c, style = Stroke(w * 1.8f), blendMode = blend)
        drawCircle(col.copy(alpha = GachaFade.f(a)), rr, c, style = Stroke(w), blendMode = blend)
    }
}

// MARK: - 손잡이 힌트 화살표(돌아가는 빛이 흐르는 호)

internal fun DrawScope.drawHintArc(now: Double, c: Offset, radius: Float, opacity: Double, flow: Double) {
    if (opacity <= 0.01) return
    val a0 = -40.0
    val a1 = 62.0
    val box = Rect(c, radius)
    drawArc(Color.White.copy(alpha = GachaFade.f(0.55 * opacity)), a0.toFloat(), (a1 - a0).toFloat(), false, box.topLeft, box.size, style = Stroke(3f, cap = StrokeCap.Round))
    // 흐르는 밝은 토막
    if (flow > 0.01) {
        val p = ((now % 1.5) + 1.5) % 1.5 / 1.5
        val head = GMath.lerp(a0 * PI / 180, a1 * PI / 180 + 0.5, GMath.easeInOutCubic(p))
        val tail = head - 0.7
        val h = min(head, a1 * PI / 180)
        val tl = maxOf(tail, a0 * PI / 180)
        if (h > tl) {
            drawArc(
                Color.White.copy(alpha = GachaFade.f(opacity * flow)), (tl * 180 / PI).toFloat(), ((h - tl) * 180 / PI).toFloat(), false,
                box.topLeft, box.size, style = Stroke(3.6f, cap = StrokeCap.Round),
            )
        }
    }
    // 화살촉
    val a1r = a1 * PI / 180
    val tip = Offset((c.x + cos(a1r) * radius).toFloat(), (c.y + sin(a1r) * radius).toFloat())
    val dir = a1r + PI / 2
    val s = 7.0
    val head3 = Path().apply {
        moveTo((tip.x + cos(dir) * s).toFloat(), (tip.y + sin(dir) * s).toFloat())
        lineTo((tip.x + cos(dir + 2.45) * s).toFloat(), (tip.y + sin(dir + 2.45) * s).toFloat())
        lineTo((tip.x + cos(dir - 2.45) * s).toFloat(), (tip.y + sin(dir - 2.45) * s).toFloat())
        close()
    }
    drawPath(head3, Color.White.copy(alpha = GachaFade.f(0.9 * opacity)))
}

/** 무대 밖까지 덮는 판(설계 좌표 — 무대 둘레 [bleed] 만큼). */
internal fun bleedRect(bleed: Float = 900f): Rect = Rect(-bleed, -bleed, GLayout.size.width + bleed, GLayout.size.height + bleed)

internal fun Rect.sizeOf(): Size = Size(width, height)
