// 원본: CheckOverlayWindow.swift :2011-2100 자리(check.overlayOffset 저장·불러오기) — 계산은 b1 OverlayGeometry, 저장과 모니터 읽기는 b2
//       (OverlayContracts.kt OverlayPlacement 주석 "저장·불러오기(DesktopKeyValueStore)는 b2" · MonitorInfo "b2 가 EnumDisplayMonitors 로")
package com.yehsung.aingcheck.desktop.overlay.surface

import com.sun.jna.Native
import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.sun.jna.platform.win32.WinUser
import com.sun.jna.ptr.IntByReference
import com.yehsung.aingcheck.desktop.overlay.engine.MonitorInfo
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPlacement
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.desktop.platform.windows.jna.ShcoreX
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore

/** 창 자리 기억. 값 = "모니터키\trx\try"(모니터 키에 탭이 없다 — \\.\DISPLAYn). 깨진 값은 없는 것으로. */
class OverlayPlacementStore(private val kv: DesktopKeyValueStore) {
    fun load(): OverlayPlacement? {
        val raw = kv.getString(KEY) ?: return null
        val parts = raw.split('\t')
        if (parts.size != 3 || parts[0].isEmpty()) return null
        val rx = parts[1].toDoubleOrNull()?.takeIf { it.isFinite() } ?: return null
        val ry = parts[2].toDoubleOrNull()?.takeIf { it.isFinite() } ?: return null
        return OverlayPlacement(parts[0], rx, ry)
    }

    fun save(p: OverlayPlacement?) {
        if (p == null || p.monitorKey.contains('\t') || !p.rx.isFinite() || !p.ry.isFinite()) {
            kv.putString(KEY, null)
            return
        }
        kv.putString(KEY, "${p.monitorKey}\t${p.rx}\t${p.ry}")
    }

    companion object {
        const val KEY = "overlay.placement"
    }
}

/**
 * 모니터 목록(EnumDisplayMonitors + GetMonitorInfo + GetDpiForMonitor). 사각형은 그 모니터 배율로 나눈 DIP.
 * 배율이 다른 모니터가 섞이면 DIP 가상 좌표가 이어지지 않는다 — 판정은 VM 묶음(다중 모니터 빼기/복원).
 */
object WindowsMonitors {
    private const val MONITORINFOF_PRIMARY = 1
    private const val MDT_EFFECTIVE_DPI = 0

    fun list(): List<MonitorInfo> {
        val out = ArrayList<MonitorInfo>()
        val proc = WinUser.MONITORENUMPROC { hMonitor, _, _, _ ->
            val mi = WinUser.MONITORINFOEX()
            if (User32.INSTANCE.GetMonitorInfo(hMonitor, mi).booleanValue()) {
                val scale = scaleOf(hMonitor)
                out += MonitorInfo(
                    key = Native.toString(mi.szDevice),
                    bounds = mi.rcMonitor.toDip(scale),
                    work = mi.rcWork.toDip(scale),
                    primary = (mi.dwFlags and MONITORINFOF_PRIMARY) != 0,
                )
            }
            1
        }
        User32.INSTANCE.EnumDisplayMonitors(null, null, proc, WinDef.LPARAM(0))
        return out
    }

    fun scaleOf(hMonitor: WinUser.HMONITOR): Double = runCatching {
        val x = IntByReference(0)
        val y = IntByReference(0)
        if (ShcoreX.INSTANCE.GetDpiForMonitor(hMonitor, MDT_EFFECTIVE_DPI, x, y) == 0 && x.value > 0) x.value / 96.0 else 1.0
    }.getOrDefault(1.0)

    private fun WinDef.RECT.toDip(scale: Double) =
        OverlayRect(left / scale, top / scale, (right - left) / scale, (bottom - top) / scale)
}
