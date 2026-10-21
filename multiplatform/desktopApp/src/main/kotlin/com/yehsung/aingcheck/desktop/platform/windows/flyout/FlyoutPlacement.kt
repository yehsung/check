// 원본: Sources/check/CheckWindowAnchor.swift 머리 @ a63fea2 (맥: 위 모서리 고정, 아래로 자람) · Sources/check/CheckApp.swift:44-48 @ a63fea2 (폭 414)
//       · 설계 D§3-3(크기·자라는 방향·위치 계산은 순수 함수·12 DIP 여백·표 시험 축) · D§13-4(ScreenSpace 한 곳)
//
// Windows 는 맥 계약을 뒤집는다: **작업 표시줄 쪽 모서리 고정, 반대쪽으로 자란다**(아래 작업 표시줄이면 아래가 고정되고 위로 자란다).
// D§3-3 은 1차 계산을 CalculatePopupWindowPosition 에 맡기라고 했지만, 그 함수는 **실제 연결된 모니터**만 보므로 배율 6 × 가장자리 4 ×
// 자동 숨김 × 음수 좌표 표를 맥에서 잴 수 없다. 그래서 같은 뜻(작업 영역 안, 아이콘 사각형 제외, 작업 표시줄 쪽 정렬)을
// 이 순수 함수가 직접 하고, 실제 화면 확인은 VM(D-E04)이 한다.
//
// 규칙(전부 물리 픽셀, 변환은 ScreenSpace 만):
//  1. 쓸 수 있는 영역 = 작업 영역. 자동 숨김이면 작업 영역이 모니터 전체라, 튀어나올 작업 표시줄 띠를 그 가장자리에서 뺀다
//     (띠 두께 = 보고된 작업 표시줄 두께, 8 DIP 보다 얇게 보고되면(숨은 상태) 48 DIP).
//  2. 여백 12 DIP 안으로 넣는다.
//  3. 크기: 폭 414 DIP(영역보다 넓으면 영역 폭), 높이 = min(내용, 700 DIP, 영역 높이 − 24 DIP).
//  4. 자리: 아래/위 작업 표시줄 = 그 쪽 모서리에 붙이고 가로는 기준점 가운데. 왼/오른 작업 표시줄 = 그 쪽 모서리에 붙이고
//     세로는 기준점 위로 자란다(Windows 10 세로 작업 표시줄의 알림 영역은 아래 끝에 있다). 영역 밖으로 나가면 영역 안으로 민다.
//  5. 아이콘 사각형(넘침 영역에 있으면 작업 영역 안이다)과 겹치면 작업 표시줄 반대쪽으로 비켜선다. 자리가 없으면 겹친 채 알린다.
package com.yehsung.aingcheck.desktop.platform.windows.flyout

import kotlin.math.max
import kotlin.math.min

data class PxPoint(val x: Int, val y: Int)

data class PxRect(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val width: Int get() = right - left
    val height: Int get() = bottom - top

    fun intersects(o: PxRect): Boolean = left < o.right && o.left < right && top < o.bottom && o.top < bottom
    fun contains(o: PxRect): Boolean = o.left >= left && o.top >= top && o.right <= right && o.bottom <= bottom
    fun translate(dx: Int, dy: Int) = PxRect(left + dx, top + dy, right + dx, bottom + dy)
    fun inset(d: Int) = PxRect(left + d, top + d, right - d, bottom - d)
}

enum class TaskbarEdge { LEFT, TOP, RIGHT, BOTTOM }

data class TaskbarInfo(val edge: TaskbarEdge, val rect: PxRect, val autoHide: Boolean)

data class FlyoutRequest(
    /** 클릭 기준점(NIN_SELECT 의 wParam) 또는 키보드로 고른 아이콘의 왼쪽 위. */
    val anchor: PxPoint,
    /** Shell_NotifyIconGetRect(없으면 null). */
    val iconRect: PxRect?,
    val monitor: PxRect,
    val workArea: PxRect,
    val taskbar: TaskbarInfo,
    /** 모니터 배율(GetDpiForMonitor / 96). */
    val scale: Double,
    val contentHeightDip: Double,
    val widthDip: Double = FlyoutPlacer.WIDTH_DIP,
)

data class FlyoutPlacement(
    val rect: PxRect,
    /** 실제로 쓴 높이(DIP) — 상한에 걸렸으면 내용이 스크롤된다. */
    val heightDip: Double,
    val maxHeightDip: Double,
    /** 아이콘 사각형과 끝내 겹쳤나(자리가 모자랄 때만). */
    val overlapsIcon: Boolean,
)

object FlyoutPlacer {
    const val WIDTH_DIP = 414.0
    const val NARROW_WIDTH_DIP = 340.0
    const val MARGIN_DIP = 12.0
    const val MAX_HEIGHT_DIP = 700.0
    const val HEIGHT_RESERVE_DIP = 24.0
    const val DEFAULT_TASKBAR_DIP = 48.0
    const val HIDDEN_TASKBAR_THRESHOLD_DIP = 8.0

    /** 1의 영역(여백 전). */
    fun usableArea(req: FlyoutRequest): PxRect {
        val wa = req.workArea
        if (!req.taskbar.autoHide) return wa
        val tb = req.taskbar.rect
        val reported = when (req.taskbar.edge) {
            TaskbarEdge.TOP, TaskbarEdge.BOTTOM -> tb.height
            TaskbarEdge.LEFT, TaskbarEdge.RIGHT -> tb.width
        }
        val band = if (reported < ScreenSpace.dipToPx(HIDDEN_TASKBAR_THRESHOLD_DIP, req.scale)) {
            ScreenSpace.dipToPx(DEFAULT_TASKBAR_DIP, req.scale)
        } else {
            reported
        }
        return when (req.taskbar.edge) {
            TaskbarEdge.BOTTOM -> wa.copy(bottom = min(wa.bottom, req.monitor.bottom - band))
            TaskbarEdge.TOP -> wa.copy(top = max(wa.top, req.monitor.top + band))
            TaskbarEdge.LEFT -> wa.copy(left = max(wa.left, req.monitor.left + band))
            TaskbarEdge.RIGHT -> wa.copy(right = min(wa.right, req.monitor.right - band))
        }
    }

    fun place(req: FlyoutRequest): FlyoutPlacement {
        require(req.scale > 0) { "배율 ${req.scale}" }
        val area = usableArea(req)
        val m = ScreenSpace.dipToPx(MARGIN_DIP, req.scale)
        val b = area.inset(m)
        require(b.width > 0 && b.height > 0) { "작업 영역이 여백보다 작다: $area" }

        val width = min(ScreenSpace.dipToPx(req.widthDip, req.scale), b.width)
        val maxHeightDip = min(MAX_HEIGHT_DIP, ScreenSpace.pxToDip(area.height, req.scale) - HEIGHT_RESERVE_DIP)
        val heightDip = max(1.0, min(req.contentHeightDip, maxHeightDip))
        val height = min(ScreenSpace.dipToPx(heightDip, req.scale), b.height)

        fun clampX(x: Int) = min(max(x, b.left), b.right - width)
        fun clampY(y: Int) = min(max(y, b.top), b.bottom - height)

        var rect = when (req.taskbar.edge) {
            TaskbarEdge.BOTTOM -> {
                val left = clampX(req.anchor.x - width / 2)
                PxRect(left, b.bottom - height, left + width, b.bottom)
            }
            TaskbarEdge.TOP -> {
                val left = clampX(req.anchor.x - width / 2)
                PxRect(left, b.top, left + width, b.top + height)
            }
            TaskbarEdge.LEFT -> {
                val top = clampY(req.anchor.y - height)
                PxRect(b.left, top, b.left + width, top + height)
            }
            TaskbarEdge.RIGHT -> {
                val top = clampY(req.anchor.y - height)
                PxRect(b.right - width, top, b.right, top + height)
            }
        }

        var overlaps = false
        val icon = req.iconRect
        if (icon != null && rect.intersects(icon)) {
            // 작업 표시줄 반대쪽으로 비켜선다(고정 모서리를 아이콘 너머로 옮긴다).
            val moved = when (req.taskbar.edge) {
                TaskbarEdge.BOTTOM -> {
                    val bottom = icon.top - m
                    rect.copy(top = bottom - height, bottom = bottom)
                }
                TaskbarEdge.TOP -> {
                    val top = icon.bottom + m
                    rect.copy(top = top, bottom = top + height)
                }
                TaskbarEdge.LEFT -> {
                    val left = icon.right + m
                    rect.copy(left = left, right = left + width)
                }
                TaskbarEdge.RIGHT -> {
                    val right = icon.left - m
                    rect.copy(left = right - width, right = right)
                }
            }
            if (b.contains(moved) && !moved.intersects(icon)) rect = moved else overlaps = true
        }
        return FlyoutPlacement(rect, heightDip, maxHeightDip, overlaps)
    }
}
