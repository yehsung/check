// 원본: CheckOverlayWindow.swift :2009-2036 reposition(저장 자리 또는 visibleFrame 오른쪽 위 24) · :1702-1706 ultraPanelFrame(화면 frame 전체) ·
//       :1779 덮기 · :1938 원래 프레임 복원 · :1963 ultraScreenFrame(패널 중심이 든 화면) · :817-822(울트라 중엔 몸 판정 거짓 = 클릭 통과)
//       설계 D §9-4(울트라: 전체 픽셀을 매 프레임 올리지 않는다) · overlay.md I-3(FrameIntent 는 seq 가 바뀔 때 한 번만 적용)
//
// 엔진의 그릴 값(OverlayView) → 창 자리·크기(OverlayGeometry, DIP) → 화면 픽셀 → 표면. 엔진 실행기(OverlayWiring 소비 코루틴) 한 줄에서만 부른다.
package com.yehsung.aingcheck.desktop.overlay.assembly

import com.yehsung.aingcheck.desktop.overlay.engine.FrameIntent
import com.yehsung.aingcheck.desktop.overlay.engine.MonitorInfo
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayGeometry
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayInputs
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayMode
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPlacement
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import com.yehsung.aingcheck.desktop.overlay.engine.PointerOutcome
import com.yehsung.aingcheck.desktop.overlay.render.ComposedOverlay
import com.yehsung.aingcheck.desktop.wiring.OverlayPresenter
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** 화면 쪽 문(앱 = [WindowsSurfacePort], 시험 = 가짜). 좌표는 화면 픽셀, 모니터는 DIP. */
interface OverlaySurfacePort : AutoCloseable {
    fun monitors(): List<MonitorInfo>
    /** 픽셀/DIP(창 배율 하나 — WindowsOverlaySurface 와 같은 규칙). */
    fun dpiScale(): Double
    fun present(frame: ComposedOverlay, xPx: Int, yPx: Int): Boolean
    fun moveTo(xPx: Int, yPx: Int)
    fun hide()
    /** 창 전체 클릭 통과(울트라 동안 — 맥 :817-822). */
    fun setClickThrough(enabled: Boolean)
    override fun close() {}
}

/** 한 프레임 합성(앱 = OverlayCompositor + 캐릭터 층, 시험 = 합성 도형). */
fun interface OverlayFrameComposer {
    fun compose(view: OverlayView, widthPx: Int, heightPx: Int, scale: Double, now: Double): ComposedOverlay
}

/** 픽셀 사각형(가상 데스크톱). */
data class PxBox(val x: Int, val y: Int, val width: Int, val height: Int)

object OverlayFramePlacement {
    /** 모니터를 하나도 못 읽었을 때의 작업 영역(엔진 currentFrame 과 같은 값). */
    val FALLBACK_WORK = OverlayRect(0.0, 0.0, 1920.0, 1080.0)

    fun primaryWork(monitors: List<MonitorInfo>): OverlayRect =
        monitors.firstOrNull { it.primary }?.work ?: monitors.firstOrNull()?.work ?: FALLBACK_WORK

    /**
     * 울트라 창(DIP). 맥은 패널을 화면 frame 전체로 키운다(:1706). Windows 는 그 전체를 매 프레임 올리지 않고(D §9-4 — 2560×1440 이면
     * 14.7MB/프레임) **화면 높이 전체 · 캐릭터 창 비율(140:170)** 의 가운데 띠만 그린다 — 캐릭터 크기는 뷰 높이로 정해져 맥과 같다.
     */
    fun ultraFrame(screen: OverlayRect): OverlayRect {
        val h = screen.height
        val w = min(screen.width, h * OverlayGeometry.PANEL_WIDTH / OverlayGeometry.PANEL_HEIGHT)
        return OverlayRect(screen.left + (screen.width - w) / 2, screen.top, w, h)
    }

    /** DIP 사각형 → 픽셀(왼쪽 위는 반올림, 크기는 끝점 반올림의 차 — 이웃 창과 틈이 안 생기게). 최소 1px. */
    fun toPx(rect: OverlayRect, scale: Double): PxBox {
        fun r(v: Double) = floor(v * scale + 0.5).toInt()
        val x = r(rect.left)
        val y = r(rect.top)
        return PxBox(x, y, max(1, r(rect.left + rect.width) - x), max(1, r(rect.top + rect.height) - y))
    }

    /** [intent] 가 가리키는 창 프레임(DIP). [current] 는 지금 창(울트라가 덮을 모니터 고르기 — 맥 ultraScreenFrame). */
    fun resolve(intent: FrameIntent, current: OverlayRect?, saved: OverlayPlacement?, monitors: List<MonitorInfo>): OverlayRect {
        val primary = primaryWork(monitors)
        return when (intent) {
            is FrameIntent.Default -> OverlayGeometry.restore(saved, monitors, primary)
            is FrameIntent.UltraCover -> {
                val cur = current ?: OverlayGeometry.restore(saved, monitors, primary)
                val screen = OverlayGeometry.monitorNear(cur.center, cur, monitors)?.bounds ?: primary
                ultraFrame(screen)
            }
            // 엔진이 이미 canRestore 로 걸렀다(규약 13) — 여기서는 그대로.
            is FrameIntent.Restore -> intent.frame
        }
    }
}

/**
 * I-3 발표자. **FrameIntent 는 seq 가 바뀔 때 한 번만** 적용한다(모니터 다시 읽기 · 엔진에 onMonitors/onSurfaceFrame 되먹이기 · 클릭 통과).
 * 숨김이면 창을 내리고, 그리기 정지(잠금·잠자기)면 마지막 그림을 둔다(맥 렌더 정지 — 창은 그대로).
 */
class OverlaySurfacePresenter(
    private val port: OverlaySurfacePort,
    private val composer: OverlayFrameComposer,
    private val savedPlacement: () -> OverlayPlacement?,
) : OverlayPresenter {
    private var feedback: OverlayInputs? = null
    private var appliedSeq: Int? = null

    /** 지금 창 프레임(DIP). */
    var frameDip: OverlayRect? = null
        private set
    var clickThrough: Boolean = false
        private set
    var shown: Boolean = false
        private set
    /** 진단·시험: 적용한 지시 수. */
    var intentsApplied: Int = 0
        private set

    /** 엔진에 자리를 되먹인다(OverlayWiring 이 director 를 만든 뒤 한 번). */
    fun bind(director: OverlayInputs) {
        feedback = director
        frameDip?.let { director.onSurfaceFrame(it) }
    }

    /** 모니터 구성이 바뀌었다(WM_DISPLAYCHANGE) — 다음 프레임에 지금 지시를 다시 적용한다. */
    fun invalidateMonitors() { appliedSeq = null }

    override fun present(view: OverlayView, now: Double) {
        if (appliedSeq != view.frame.seq) apply(view.frame)
        if (view.mode == OverlayMode.Hidden) {
            if (shown) { port.hide(); shown = false }
            return
        }
        if (view.renderSuspended) return
        val frame = frameDip ?: return
        val scale = port.dpiScale()
        val px = OverlayFramePlacement.toPx(frame, scale)
        val composed = composer.compose(view, px.width, px.height, scale, now)
        if (port.present(composed, px.x, px.y)) shown = true
    }

    /** 끌기(엔진이 조인 새 왼쪽 위, DIP) — 내용은 두고 자리만. 자리 저장은 OverlayWiring 이 한다. */
    fun onPointerOutcome(outcome: PointerOutcome) {
        val to = outcome.moveTo ?: return
        val cur = frameDip ?: return
        val next = cur.withOrigin(to.x, to.y)
        frameDip = next
        val px = OverlayFramePlacement.toPx(next, port.dpiScale())
        port.moveTo(px.x, px.y)
    }

    private fun apply(intent: FrameIntent) {
        val monitors = port.monitors()
        feedback?.onMonitors(monitors)
        val rect = OverlayFramePlacement.resolve(intent, frameDip, savedPlacement(), monitors)
        val through = intent is FrameIntent.UltraCover
        if (through != clickThrough) {
            port.setClickThrough(through)
            clickThrough = through
        }
        frameDip = rect
        feedback?.onSurfaceFrame(rect)
        appliedSeq = intent.seq
        intentsApplied += 1
    }
}
