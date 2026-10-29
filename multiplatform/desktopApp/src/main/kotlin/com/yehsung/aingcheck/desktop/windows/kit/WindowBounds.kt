// 원본: Sources/check/CheckMiniGameWindow.swift:160-176(setFrameUsingName 복원 · 없으면 화면 중앙) · ★342(재생성 때 자동저장 이름 놓기)
//       (W4-d 창 공통 부품 — games.md §4. 맥 NSWindow 자동저장의 Windows 짝: 저장은 pins C 의 DesktopKeyValueStore)
package com.yehsung.aingcheck.desktop.windows.kit

import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlin.math.roundToInt

/**
 * 저장된 창 자리를 지금 모니터 배치에 맞춰 되살린다(물리 픽셀).
 * ① 저장값 없음 → 첫(주) 작업 영역 가운데, 기본 크기.
 * ② 저장값의 제목줄 띠(위 [minVisiblePx])가 어느 작업 영역 안에 [minVisiblePx] 이상 걸쳐 있으면 그대로(크기는 그 영역 안으로 줄인다).
 * ③ 아니면(모니터 분리·화면 밖) → 주 작업 영역 가운데로 옮긴다. 크기는 저장값을 지키되 영역을 넘지 않는다.
 * 작업 영역이 없으면(헤드리스) 원점에 기본 크기.
 */
object WindowBoundsRule {
    fun restore(saved: PxRect?, workAreas: List<PxRect>, defaultSizePx: Pair<Int, Int>, minVisiblePx: Int = 48): PxRect {
        val primary = workAreas.firstOrNull() ?: return PxRect(0, 0, defaultSizePx.first, defaultSizePx.second)
        if (saved == null || saved.width <= 0 || saved.height <= 0) {
            return centered(primary, defaultSizePx.first, defaultSizePx.second)
        }
        val home = workAreas.firstOrNull { titleBarReachable(saved, it, minVisiblePx) }
        if (home != null) {
            val w = saved.width.coerceAtMost(home.width)
            val h = saved.height.coerceAtMost(home.height)
            // 줄였으면 영역 안으로 당긴다(오른쪽·아래로 삐져나가지 않게).
            val left = saved.left.coerceIn(home.left, home.right - w).takeIf { w != saved.width } ?: saved.left
            val top = saved.top.coerceIn(home.top, home.bottom - h).takeIf { h != saved.height } ?: saved.top
            return PxRect(left, top, left + w, top + h)
        }
        return centered(primary, saved.width, saved.height)
    }

    /** dp → 물리 픽셀(배율 1.0·1.5 …). 창 기본 크기는 [GameWindowKind] 의 dp 를 이걸로 바꿔 넘긴다. */
    fun sizePx(widthDp: Int, heightDp: Int, scale: Double): Pair<Int, Int> =
        (widthDp * scale).roundToInt() to (heightDp * scale).roundToInt()

    private fun titleBarReachable(r: PxRect, wa: PxRect, minVisible: Int): Boolean {
        val overlapW = minOf(r.right, wa.right) - maxOf(r.left, wa.left)
        return overlapW >= minVisible && r.top >= wa.top && r.top <= wa.bottom - minVisible
    }

    private fun centered(area: PxRect, width: Int, height: Int): PxRect {
        val w = width.coerceAtMost(area.width)
        val h = height.coerceAtMost(area.height)
        val left = area.left + (area.width - w) / 2
        val top = area.top + (area.height - h) / 2
        return PxRect(left, top, left + w, top + h)
    }
}

/** 창 자리 저장소. 키 = 맥 자동저장 이름([GameWindowKind.boundsKey]). */
interface WindowBoundsStore {
    fun load(key: String): PxRect?
    fun save(key: String, rect: PxRect)
}

/** pins C 의 [DesktopKeyValueStore] 위의 구현. 값 = "left,top,right,bottom". 깨진 값·빈 사각형은 없음으로 읽는다. */
class KeyValueWindowBoundsStore(
    private val kv: DesktopKeyValueStore,
    private val prefix: String = "windowBounds.",
) : WindowBoundsStore {
    override fun load(key: String): PxRect? {
        val raw = kv.getString(prefix + key) ?: return null
        val parts = raw.split(',').map { it.trim().toIntOrNull() ?: return null }
        if (parts.size != 4) return null
        val r = PxRect(parts[0], parts[1], parts[2], parts[3])
        return r.takeIf { it.width > 0 && it.height > 0 }
    }

    override fun save(key: String, rect: PxRect) {
        if (rect.width <= 0 || rect.height <= 0) return
        kv.putString(prefix + key, "${rect.left},${rect.top},${rect.right},${rect.bottom}")
    }
}
