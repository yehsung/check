// 원본: Sources/CheckCore/MenuBarStatusFormatter.swift @ a63fea2 (상태 우선순위: 동기화 대기 > 근무 중 > 오프, 시:분 표기,
//       툴팁 상태 글자 = localizedStatus "근무중"·"근무종료"·"동기화 대기" 그대로 — G §8-13)
//       · Sources/check/CheckMenuView.swift:1160-1166 @ a63fea2 (빨간 점 = 새 버전·안 읽은 메시지·받은 신청·미해결 신고, 이미지에 굽는다)
//       · 설계 D§3-2·§4-2(아이콘 안 숫자 = 경과 시, 24px 이상은 15분 눈금 4칸, 오프 = 회색 아잉이 얼굴, 대기 = 주황 '!')
//
// 트레이 아이콘을 **순수 함수**(상태 → ARGB 래스터)로 그린다(D§3-2). 글꼴을 쓰지 않는다 — OS 마다 기본 글꼴이 달라
// 맥·Linux CI·Windows 러너의 골든이 갈린다. 숫자는 코드 안 선분 글꼴, 모양은 부호 거리 함수(SDF)로 정의하고
// 픽셀마다 4×4 표본으로 덮임을 센다. 쓰는 연산은 사칙·sqrt·floor·min·max·abs 뿐이라(IEEE 754, JVM 17+ strict)
// 어느 JVM 에서나 비트로 같다. 크기마다 따로 그리고 늘려 쓰지 않는다(NOTIFYICONDATA hIcon 문서: 늘리면 흐려진다).
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** 작업 표시줄 밝음·어두움(HKCU\…\Themes\Personalize\SystemUsesLightTheme). */
enum class TaskbarTheme { LIGHT, DARK }

sealed interface TrayIconStatus {
    data class Working(val elapsedSeconds: Int) : TrayIconStatus
    data object Off : TrayIconStatus
    data object Pending : TrayIconStatus

    companion object {
        /** 맥 MenuBarStatusFormatter.title 과 같은 우선순위: 동기화 대기가 먼저다(큐에 근무 조작이 남은 사실이 시계보다 급하다). */
        fun of(isWorking: Boolean, elapsedSeconds: Int, pendingSync: Boolean): TrayIconStatus = when {
            pendingSync -> Pending
            isWorking -> Working(elapsedSeconds)
            else -> Off
        }

        /**
         * 핀 조정 ⑩: 트레이가 읽는 근무 값은 core/rules `WorkStatusSnapshot` 그대로(조립 지점이 DesktopWorkSnapshot 에서 옮긴다).
         * 아이콘 숫자는 Int 초면 충분하다(68년) — 넘치면 Int 최대로 접는다.
         */
        fun of(snapshot: WorkStatusSnapshot): TrayIconStatus = of(
            isWorking = snapshot.isWorking,
            elapsedSeconds = snapshot.elapsedSeconds.coerceIn(0L, Int.MAX_VALUE.toLong()).toInt(),
            pendingSync = snapshot.pendingSync,
        )
    }
}

data class TrayIconSpec(
    val status: TrayIconStatus,
    /** 새 버전·안 읽은 메시지·받은 신청·미해결 신고(맥과 같은 조건, 사유마다 모양을 가르지 않는다). */
    val redDot: Boolean,
    val theme: TaskbarTheme,
    /** SM_CXSMICON(현재 배율의 작은 아이콘 크기, 물리 픽셀). */
    val sizePx: Int,
) {
    init {
        require(sizePx in 8..256) { "트레이 아이콘 크기 $sizePx 가 범위 밖이다" }
    }
}

object TrayTooltip {
    /**
     * NIF_SHOWTIP 기본 툴팁(127자 상한). 분은 아이콘에 없으므로 툴팁이 시:분을 말한다(D§4-2).
     * 상태 글자는 맥 `WorkStatusSnapshot.localizedStatus`(Sources/CheckCore/MenuBarStatusFormatter.swift) **그대로** —
     * "근무중"·"근무종료"·"동기화 대기"(띄어쓰기까지, G §8-13). 글자도 시:분도 core/rules 이식본에 맡긴다(W1-f2: 판정 두 벌 제거) —
     * 시험이 맥 소스의 글자와 대조한다.
     */
    fun text(status: TrayIconStatus): String = when (status) {
        TrayIconStatus.Pending -> "아잉체크 · ${WorkStatusSnapshot(WorkStatus.offWork, 0, pendingSync = true).localizedStatus}"
        TrayIconStatus.Off -> "아잉체크 · ${WorkStatus.offWork.localizedStatus}"
        is TrayIconStatus.Working -> "아잉체크 · ${WorkStatus.working.localizedStatus} ${hhmm(status.elapsedSeconds)}"
    }

    /** 맥 titleDuration 그대로(항상 HH:MM, 초 내림, 음수 0) — core/rules `MenuBarStatusFormatter.titleDuration` 위임, 계산 없음. */
    fun hhmm(seconds: Int): String = MenuBarStatusFormatter.titleDuration(seconds.toLong())
}

object TrayIconRenderer {
    /** 픽셀 한 변의 표본 수(4×4 = 16 표본). */
    const val SUPERSAMPLE = 4

    /** 빨간 점 중심(크기 대비). 시험이 이 자리를 잰다. */
    const val DOT_CENTER_X = 0.79
    const val DOT_CENTER_Y = 0.21

    /** 눈금(15분 4칸)을 그리기 시작하는 크기(D§4-2: 150% = 24px 이상). */
    const val TICKS_MIN_SIZE = 24

    /** 배율(%) → SM_CXSMICON. Windows 는 16px 을 배율로 키운 값을 쓴다(100·125·150·175·200 → 16·20·24·28·32). */
    fun sizeForScalePercent(scalePercent: Int): Int {
        require(scalePercent in 100..500) { "배율 $scalePercent% 가 범위 밖이다" }
        return (16 * scalePercent + 50) / 100
    }

    // 색(ARGB, 직선 알파). 보라는 브랜드 자리다(G §8-15 — 앱 주요색은 iOS 파랑이지만 트레이 아이콘은 브랜드 보라 그대로).
    // 흰 숫자 대비를 위해 브랜드 라벤더(0x9979E6)보다 진하다.
    internal const val PURPLE = 0xFF6E4FD8.toInt()
    internal const val ORANGE = 0xFFE8590C.toInt()
    internal const val WHITE = 0xFFFFFFFF.toInt()
    internal const val RED = 0xFFE5484D.toInt()
    internal const val FACE_ON_LIGHT = 0xFF5F6368.toInt()
    internal const val FACE_ON_DARK = 0xFFC4C7CC.toInt()
    internal const val EYES_ON_LIGHT = 0xFFFFFFFF.toInt()
    internal const val EYES_ON_DARK = 0xFF202124.toInt()
    /** 빨간 점 둘레 고리 = 작업 표시줄 바탕색(점을 아이콘과 떼어 보이게). */
    internal const val TASKBAR_LIGHT = 0xFFF3F3F3.toInt()
    internal const val TASKBAR_DARK = 0xFF202020.toInt()

    fun render(spec: TrayIconSpec): RasterImage {
        val n = spec.sizePx
        val canvas = Canvas(n)
        val s = n.toDouble()
        when (val st = spec.status) {
            is TrayIconStatus.Working -> {
                canvas.fill(PURPLE, roundedSquare(s))
                val total = max(0, st.elapsedSeconds)
                val hours = min(99, total / 3600)
                val minutes = (total % 3600) / 60
                val ticks = n >= TICKS_MIN_SIZE
                drawText(canvas, hours.toString(), s, ticks)
                if (ticks) drawTicks(canvas, s, minutes)
            }
            TrayIconStatus.Off -> {
                val face = if (spec.theme == TaskbarTheme.LIGHT) FACE_ON_LIGHT else FACE_ON_DARK
                val eyes = if (spec.theme == TaskbarTheme.LIGHT) EYES_ON_LIGHT else EYES_ON_DARK
                val r = s * 0.44
                canvas.fill(face, circle(s / 2, s / 2, r))
                val eyeR = max(0.75, s * 0.075)
                canvas.fill(eyes, circle(s * 0.36, s * 0.45, eyeR))
                canvas.fill(eyes, circle(s * 0.64, s * 0.45, eyeR))
                // 입: 짧은 가로선(아잉이 얼굴을 1비트에 가깝게 줄인 모양)
                canvas.fill(eyes, capsule(s * 0.40, s * 0.66, s * 0.60, s * 0.66, max(0.5, s * 0.045)))
            }
            TrayIconStatus.Pending -> {
                canvas.fill(ORANGE, roundedSquare(s))
                drawText(canvas, "!", s, ticks = false)
            }
        }
        if (spec.redDot) {
            val ring = if (spec.theme == TaskbarTheme.LIGHT) TASKBAR_LIGHT else TASKBAR_DARK
            val cx = s * DOT_CENTER_X
            val cy = s * DOT_CENTER_Y
            val r = max(2.0, s * 0.13)
            canvas.fill(ring, circle(cx, cy, r + max(0.75, s * 0.05)))
            canvas.fill(RED, circle(cx, cy, r))
        }
        return canvas.toRaster()
    }

    // ---------- 모양(SDF: 음수 = 안쪽) ----------

    internal fun interface Shape {
        fun sd(x: Double, y: Double): Double
    }

    private fun roundedSquare(s: Double): Shape {
        val inset = max(0.5, s * 0.04)
        val half = s / 2 - inset
        val radius = s * 0.22
        val c = s / 2
        return Shape { x, y ->
            val qx = abs(x - c) - (half - radius)
            val qy = abs(y - c) - (half - radius)
            val ox = max(qx, 0.0)
            val oy = max(qy, 0.0)
            sqrt(ox * ox + oy * oy) + min(max(qx, qy), 0.0) - radius
        }
    }

    internal fun circle(cx: Double, cy: Double, r: Double) = Shape { x, y ->
        val dx = x - cx
        val dy = y - cy
        sqrt(dx * dx + dy * dy) - r
    }

    internal fun capsule(ax: Double, ay: Double, bx: Double, by: Double, halfWidth: Double) = Shape { x, y ->
        segmentDistance(x, y, ax, ay, bx, by) - halfWidth
    }

    private fun segmentDistance(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double): Double {
        val vx = bx - ax
        val vy = by - ay
        val wx = px - ax
        val wy = py - ay
        val len2 = vx * vx + vy * vy
        val t = if (len2 == 0.0) 0.0 else min(1.0, max(0.0, (wx * vx + wy * vy) / len2))
        val dx = wx - t * vx
        val dy = wy - t * vy
        return sqrt(dx * dx + dy * dy)
    }

    private fun union(shapes: List<Shape>) = Shape { x, y ->
        var d = Double.POSITIVE_INFINITY
        for (sh in shapes) d = min(d, sh.sd(x, y))
        d
    }

    // ---------- 선분 글꼴 ----------

    /** 0..1 상자(x 오른쪽, y 아래) 위의 선분 목록. 칠 분절 꼴에 1·7·! 만 손을 봤다. */
    internal val GLYPHS: Map<Char, List<DoubleArray>> = run {
        val a = 0.0 to 0.0
        val b = 1.0 to 0.0
        val c = 0.0 to 0.5
        val d = 1.0 to 0.5
        val e = 0.0 to 1.0
        val f = 1.0 to 1.0
        fun seg(p: Pair<Double, Double>, q: Pair<Double, Double>) = doubleArrayOf(p.first, p.second, q.first, q.second)
        mapOf(
            '0' to listOf(seg(a, b), seg(b, f), seg(f, e), seg(e, a)),
            '1' to listOf(seg(0.62 to 0.0, 0.62 to 1.0), seg(0.22 to 0.28, 0.62 to 0.0)),
            '2' to listOf(seg(a, b), seg(b, d), seg(d, c), seg(c, e), seg(e, f)),
            '3' to listOf(seg(a, b), seg(b, f), seg(f, e), seg(c, d)),
            '4' to listOf(seg(a, c), seg(c, d), seg(b, f)),
            '5' to listOf(seg(b, a), seg(a, c), seg(c, d), seg(d, f), seg(f, e)),
            '6' to listOf(seg(b, a), seg(a, e), seg(e, f), seg(f, d), seg(d, c)),
            '7' to listOf(seg(a, b), seg(b, 0.42 to 1.0)),
            '8' to listOf(seg(a, b), seg(b, f), seg(f, e), seg(e, a), seg(c, d)),
            '9' to listOf(seg(d, c), seg(c, a), seg(a, b), seg(b, f), seg(f, e)),
            '!' to listOf(seg(0.5 to 0.0, 0.5 to 0.58)),
        )
    }

    private fun drawText(canvas: Canvas, text: String, s: Double, ticks: Boolean) {
        val boxH = if (ticks) s * 0.46 else s * 0.54
        val glyphW = boxH * 0.56
        val gap = boxH * 0.24
        val half = max(0.6, s * 0.06)
        val totalW = text.length * glyphW + (text.length - 1) * gap
        val left = (s - totalW) / 2
        val top = if (ticks) s * 0.17 else (s - boxH) / 2
        val shapes = mutableListOf<Shape>()
        text.forEachIndexed { i, ch ->
            val ox = left + i * (glyphW + gap)
            val glyph = GLYPHS[ch] ?: error("글꼴에 '$ch' 가 없다")
            for (sg in glyph) {
                shapes += capsule(ox + sg[0] * glyphW, top + sg[1] * boxH, ox + sg[2] * glyphW, top + sg[3] * boxH, half)
            }
            if (ch == '!') shapes += circle(ox + 0.5 * glyphW, top + 0.94 * boxH, half * 1.1)
        }
        canvas.fill(WHITE, union(shapes))
    }

    /** 15분 눈금 4칸: 지금 들어선 사분(0~14분 = 1칸 … 45~59분 = 4칸)까지 밝게, 나머지는 흐리게. */
    private fun drawTicks(canvas: Canvas, s: Double, minutes: Int) {
        val lit = minutes / 15 + 1
        val y = s * 0.80
        val span = s * 0.60
        val left = (s - span) / 2
        val step = span / 4
        val half = max(0.6, s * 0.035)
        val gap = max(1.0, s * 0.04)
        for (i in 0 until 4) {
            // 둥근 끝(반폭)까지 칸 안에 넣고 칸 사이에 틈을 남긴다 — 틈이 없으면 네 칸이 한 줄로 붙어 보인다.
            val x0 = left + i * step + half + gap / 2
            val x1 = left + (i + 1) * step - half - gap / 2
            val color = if (i < lit) WHITE else 0x66FFFFFF
            canvas.fill(color, capsule(x0, y, x1, y, half))
        }
    }

    // ---------- 래스터 ----------

    /** 직선 알파 RGBA(0..1) 를 픽셀마다 들고 "위에 덮기"로 합성한다. 마지막에만 8비트로 자른다. */
    internal class Canvas(private val n: Int) {
        private val a = DoubleArray(n * n)
        private val r = DoubleArray(n * n)
        private val g = DoubleArray(n * n)
        private val b = DoubleArray(n * n)

        fun fill(argb: Int, shape: Shape) {
            val sa = ((argb ushr 24) and 0xFF) / 255.0
            val sr = ((argb ushr 16) and 0xFF) / 255.0
            val sg = ((argb ushr 8) and 0xFF) / 255.0
            val sb = (argb and 0xFF) / 255.0
            val ss = SUPERSAMPLE
            for (py in 0 until n) {
                for (px in 0 until n) {
                    var hits = 0
                    for (j in 0 until ss) {
                        val y = py + (j + 0.5) / ss
                        for (i in 0 until ss) {
                            val x = px + (i + 0.5) / ss
                            if (shape.sd(x, y) <= 0.0) hits++
                        }
                    }
                    if (hits == 0) continue
                    val cov = sa * hits / (ss * ss)
                    val k = py * n + px
                    val da = a[k]
                    val outA = cov + da * (1 - cov)
                    r[k] = (sr * cov + r[k] * da * (1 - cov)) / outA
                    g[k] = (sg * cov + g[k] * da * (1 - cov)) / outA
                    b[k] = (sb * cov + b[k] * da * (1 - cov)) / outA
                    a[k] = outA
                }
            }
        }

        fun toRaster(): RasterImage {
            val out = IntArray(n * n)
            for (k in out.indices) {
                val a8 = q(a[k])
                out[k] = if (a8 == 0) 0 else (a8 shl 24) or (q(r[k]) shl 16) or (q(g[k]) shl 8) or q(b[k])
            }
            return RasterImage(n, n, out)
        }

        private fun q(v: Double): Int = min(255, max(0, floor(v * 255 + 0.5).toInt()))
    }
}
