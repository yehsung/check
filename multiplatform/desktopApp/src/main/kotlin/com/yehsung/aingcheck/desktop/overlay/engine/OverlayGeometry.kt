package com.yehsung.aingcheck.desktop.overlay.engine

/*
 * 자리 계산(순수) — 맥 CheckOverlayWindow.swift :2011-2100(reposition·saveOffset·currentScreen) · :2177-2208(overlayFrame·clampedOrigin)
 * · :1706-1713(울트라 canRestore). 맥은 왼쪽 아래 원점이라 "maxY − 높이 − 여백" 이 Windows 에선 "top + 여백" 이다.
 */
object OverlayGeometry {
    /** 캐릭터 창 크기(DIP) — 맥 panelSize 140×170. */
    const val PANEL_WIDTH = 140.0
    const val PANEL_HEIGHT = 170.0
    /** 기본 자리 여백(오른쪽 위) — 맥 edgeMargin 24. */
    const val EDGE_MARGIN = 24.0

    /** 저장 자리가 없을 때: 작업 영역 오른쪽 위에서 24 안쪽. */
    fun defaultFrame(work: OverlayRect, width: Double = PANEL_WIDTH, height: Double = PANEL_HEIGHT): OverlayRect =
        OverlayRect(work.right - width - EDGE_MARGIN, work.top + EDGE_MARGIN, width, height)

    /** 창이 작업 영역 밖으로 못 나가게(맥 clampedOrigin :2202 — 창이 더 크면 왼쪽 위에 붙인다). */
    fun clampedOrigin(x: Double, y: Double, width: Double, height: Double, work: OverlayRect): OverlayPoint {
        val maxX = maxOf(work.left, work.right - width)
        val maxY = maxOf(work.top, work.bottom - height)
        return OverlayPoint(minOf(maxOf(x, work.left), maxX), minOf(maxOf(y, work.top), maxY))
    }

    /** 점이 든 모니터, 없으면 창과 가장 많이 겹치는 모니터, 그것도 없으면 주 모니터(맥 currentScreen :2064). */
    fun monitorNear(point: OverlayPoint, frame: OverlayRect?, monitors: List<MonitorInfo>): MonitorInfo? {
        monitors.firstOrNull { it.bounds.contains(point) }?.let { return it }
        if (frame != null) {
            var best: MonitorInfo? = null
            var bestArea = -1.0
            for (m in monitors) {
                val area = m.bounds.intersectionArea(frame)
                if (area > bestArea) { bestArea = area; best = m }
            }
            if (best != null) return best
        }
        return monitors.firstOrNull { it.primary } ?: monitors.firstOrNull()
    }

    /** 드래그 끝 저장할 자리(맥 saveOffset :2043 — [오른쪽 여백, 위 여백] + 모니터 키). */
    fun capture(frame: OverlayRect, monitors: List<MonitorInfo>): OverlayPlacement? {
        val m = monitorNear(frame.center, frame, monitors) ?: return null
        return OverlayPlacement(m.key, m.work.right - frame.right, frame.top - m.work.top)
    }

    /**
     * 저장 자리 → 창 프레임(맥 overlayFrame(offset:) :2185). 저장한 모니터가 빠졌으면 주 모니터 작업 영역에 같은 여백으로,
     * 그래도 작업 영역 안으로 조인다. saved 가 없으면 기본 자리.
     */
    fun restore(
        saved: OverlayPlacement?,
        monitors: List<MonitorInfo>,
        primaryWork: OverlayRect,
        width: Double = PANEL_WIDTH,
        height: Double = PANEL_HEIGHT,
    ): OverlayRect {
        val work = saved?.let { s -> monitors.firstOrNull { it.key == s.monitorKey }?.work } ?: primaryWork
        if (saved == null) return defaultFrame(work, width, height)
        val x = work.right - saved.rx - width
        val y = work.top + saved.ry
        val o = clampedOrigin(x, y, width, height, work)
        return OverlayRect(o.x, o.y, width, height)
    }

    /** 규약 13 — 울트라 끝: 원래 프레임이 어느 모니터와도 안 겹치면 복원하지 않는다(기본 자리로). */
    fun canRestore(frame: OverlayRect, monitors: List<MonitorInfo>): Boolean = monitors.any { it.bounds.intersects(frame) }
}

/**
 * 드래그 방향 히스테리시스(맥 DragFacingHysteresis :2303) — 기준점에서 3 DIP 넘게 가야 방향이 바뀐다(손떨림 무시).
 */
class DragFacingHysteresis {
    companion object { const val THRESHOLD = 3.0 }

    private var referenceX: Double? = null
    var direction: Int = 0
        private set

    fun begin(x: Double) { referenceX = x; direction = 0 }

    fun reset() { referenceX = null; direction = 0 }

    fun update(x: Double): Int {
        val ref = referenceX ?: run { referenceX = x; return direction }
        val dx = x - ref
        if (dx > THRESHOLD) { direction = 1; referenceX = x } else if (dx < -THRESHOLD) { direction = -1; referenceX = x }
        return direction
    }
}

/** 드래그 문턱(맥 dragThreshold 4) — 이 거리 이하로 움직이고 떼면 클릭이다. */
object DragRules {
    const val THRESHOLD_DIP = 4.0
    fun isDrag(dx: Double, dy: Double): Boolean = kotlin.math.hypot(dx, dy) > THRESHOLD_DIP
}
