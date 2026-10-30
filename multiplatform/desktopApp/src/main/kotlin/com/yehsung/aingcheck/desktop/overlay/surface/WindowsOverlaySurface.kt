// 원본: CheckOverlayWindow.swift :2211-2250 makePanel · :2250-2300 CharacterHitTestingView(눌림·끌기·놓기 → 컨트롤러) ·
//       :779-853 withinBody(울트라 중엔 몸 판정 거짓 · 말풍선 특례) — Windows 는 픽셀 알파가 판정이라 특례·히트스루 토글이 없다(D §9-1)
//       설계 D §9-4(울트라 두 창: 흐림 창은 LWA_ALPHA + TRANSPARENT 로 클릭 통과) · W-3 #10
//
// 창 둘(캐릭터 · 울트라 흐림)은 [thread](Win32MessageThread) 위에서 만들고 다룬다 — 그 스레드의 GetMessage 루프가 두 창의 메시지도 돌린다.
// 포인터 사건은 메시지 스레드에서 [OverlaySurfaceListener] 로 바로 나간다: 받는 쪽(조립 P3)은 짧게 엔진 실행기로 넘긴다.
// 좌표: 창 픽셀 ↔ DIP 는 이 창의 GetDpiForWindow 배율 하나로 바꾼다(혼합 배율 다중 모니터 판정은 VM 묶음).
package com.yehsung.aingcheck.desktop.overlay.surface

import com.sun.jna.platform.win32.User32
import com.sun.jna.platform.win32.WinDef
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPoint
import com.yehsung.aingcheck.desktop.overlay.engine.PointerKind
import com.yehsung.aingcheck.desktop.overlay.render.ComposedOverlay
import com.yehsung.aingcheck.desktop.overlay.win32.CaptureExclusion
import com.yehsung.aingcheck.desktop.overlay.win32.LayeredBitmap
import com.yehsung.aingcheck.desktop.overlay.win32.LayeredUpdate
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayUser32
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayWin32
import com.yehsung.aingcheck.desktop.overlay.win32.OverlayWindowClass
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread

/** 창이 받은 포인터 한 번. [ptDip] 는 가상 데스크톱 DIP, [target] 은 그 자리의 마지막 프레임 알파·말풍선으로 고른 값. */
fun interface OverlaySurfaceListener {
    fun onPointer(kind: PointerKind, ptDip: OverlayPoint, target: HitTarget)
}

/** 화면 픽셀 사각형(가상 데스크톱). */
data class ScreenRectPx(val x: Int, val y: Int, val width: Int, val height: Int)

class WindowsOverlaySurface(
    private val thread: Win32MessageThread,
    val className: String = DEFAULT_CLASS_NAME,
    private val listener: OverlaySurfaceListener = OverlaySurfaceListener { _, _, _ -> },
    /** 이 창의 WM_DPICHANGED(캐릭터가 있는 모니터의 배율 — 보조 모니터 포함) → OverlaySurfaces.displayChanges. */
    private val dpiRelay: OverlayWindowDpiRelay? = null,
) : AutoCloseable {
    private val overlayClass = OverlayWindowClass(className)
    private val dimClass = OverlayWindowClass("$className$DIM_SUFFIX", blackBackground = true)
    private val bitmap = LayeredBitmap()

    val hwnd: WinDef.HWND
    /** 만들 때 한 번 건 캡처 제외의 결과(W-3 #10 — 실패면 오류 코드만 남긴다). */
    val captureExclusion: CaptureExclusion

    @Volatile private var last: ComposedOverlay? = null
    @Volatile private var originX = 0
    @Volatile private var originY = 0
    @Volatile private var shown = false
    @Volatile private var dragging = false
    @Volatile private var lastClientX = 0
    @Volatile private var lastClientY = 0
    @Volatile var dimHwnd: WinDef.HWND? = null
        private set
    @Volatile private var closed = false

    init {
        val (h, ce) = thread.call { _ ->
            val w = overlayClass.create(OverlayWin32.OVERLAY_EX_STYLE, 0, 0, 1, 1, ::handle)
            w to OverlayWindowClass.excludeFromCapture(w)
        }
        hwnd = h
        captureExclusion = ce
    }

    /** 이 창의 배율(DPI/96). */
    fun dpiScale(): Double = thread.call { _ -> OverlayWindowClass.dpiScale(hwnd) }

    fun exStyle(): Int = thread.call { _ -> OverlayWindowClass.exStyle(hwnd) }

    /**
     * 한 프레임을 화면 [xPx],[yPx] 에 올린다. 첫 성공 뒤 비활성으로 보인다(레이어드 창은 그 전엔 안 그려진다).
     * 실패하면 창은 그대로 두고 결과(오류 코드)만 돌려준다.
     */
    fun present(frame: ComposedOverlay, xPx: Int, yPx: Int): LayeredUpdate {
        val bgra = frame.toBgraPremultiplied()
        return thread.call { _ ->
            val r = bitmap.present(hwnd, bgra, frame.width, frame.height, xPx, yPx)
            if (r.ok) {
                last = frame
                originX = xPx
                originY = yPx
                if (!shown) {
                    OverlayWindowClass.showNoActivate(hwnd)
                    shown = true
                }
            }
            r
        }
    }

    /** 내용은 두고 자리만 옮긴다(드래그 중 매 이동). */
    fun moveTo(xPx: Int, yPx: Int) = thread.call { _ ->
        User32.INSTANCE.SetWindowPos(
            hwnd, null, xPx, yPx, 0, 0,
            OverlayWin32.SWP_NOSIZE or OverlayWin32.SWP_NOZORDER or OverlayWin32.SWP_NOACTIVATE,
        )
        originX = xPx
        originY = yPx
    }

    fun hide() = thread.call { _ ->
        OverlayWindowClass.hide(hwnd)
        shown = false
    }

    fun show() = thread.call { _ ->
        if (last != null) {
            OverlayWindowClass.showNoActivate(hwnd)
            shown = true
        }
    }

    val isShown: Boolean get() = shown

    /**
     * 창 전체 클릭 통과(WS_EX_TRANSPARENT) — 울트라 동안(맥 :817-822 몸 판정 거짓 → ignoresMouseEvents)과 엿보기·작별 인사 동안(맥 :729
     * updateHitThrough 의 shouldBeVisible 가드 — 판정은 OverlaySurfacePresenter.clickThroughFor). 끄면 다시 알파가 판정이다.
     * 바꾼 뒤의 GWL_EXSTYLE 을 돌려준다.
     */
    fun setClickThrough(enabled: Boolean): Int = thread.call { _ ->
        val cur = OverlayWindowClass.exStyle(hwnd)
        val next = if (enabled) cur or OverlayWin32.WS_EX_TRANSPARENT else cur and OverlayWin32.WS_EX_TRANSPARENT.inv()
        if (next != cur) User32.INSTANCE.SetWindowLong(hwnd, OverlayWin32.GWL_EXSTYLE, next)
        if (enabled && dragging) dragging = false
        OverlayWindowClass.exStyle(hwnd)
    }

    /**
     * 울트라 흐림 창(D §9-4) — [bounds](모니터 전체)를 상수 알파 [alpha] 로 덮고 클릭은 늘 통과시킨다.
     * 캐릭터 창은 그 위로 다시 올린다.
     */
    fun showUltraDim(bounds: ScreenRectPx, alpha: Int) = thread.call { _ ->
        val d = dimHwnd ?: dimClass.create(OverlayWin32.ULTRA_DIM_EX_STYLE, bounds.x, bounds.y, bounds.width, bounds.height) { _, _, _, _ -> null }
            .also {
                dimHwnd = it
                OverlayWindowClass.excludeFromCapture(it)
            }
        User32.INSTANCE.SetWindowPos(d, null, bounds.x, bounds.y, bounds.width, bounds.height, OverlayWin32.SWP_NOZORDER or OverlayWin32.SWP_NOACTIVATE)
        User32.INSTANCE.SetLayeredWindowAttributes(d, 0, alpha.coerceIn(0, 255).toByte(), OverlayWin32.LWA_ALPHA)
        OverlayWindowClass.showNoActivate(d)
        if (shown) OverlayWindowClass.showNoActivate(hwnd)
    }

    fun hideUltraDim() = thread.call { _ -> dimHwnd?.let { OverlayWindowClass.hide(it) } }

    private fun handle(h: WinDef.HWND, msg: Int, wParam: WinDef.WPARAM, lParam: WinDef.LPARAM): WinDef.LRESULT? {
        dpiRelay?.handle(msg)?.let { return it }
        when (msg) {
            // 눌러도 활성화하지 않는다(맥 nonactivatingPanel) — 사용자가 치던 창의 포커스를 뺏지 않는다.
            OverlayWin32.WM_MOUSEACTIVATE -> return WinDef.LRESULT(OverlayWin32.MA_NOACTIVATE.toLong())
            OverlayWin32.WM_LBUTTONDOWN -> {
                OverlayUser32.INSTANCE.SetCapture(h)
                dragging = true
                emit(PointerKind.DOWN, lParam.toLong())
                return WinDef.LRESULT(0)
            }
            OverlayWin32.WM_MOUSEMOVE -> {
                if (dragging && (wParam.toLong() and OverlayWin32.MK_LBUTTON.toLong()) != 0L) emit(PointerKind.DRAG, lParam.toLong())
                return WinDef.LRESULT(0)
            }
            OverlayWin32.WM_LBUTTONUP -> {
                if (dragging) {
                    dragging = false // ReleaseCapture 가 곧바로 WM_CAPTURECHANGED 를 부르기 전에 내린다
                    OverlayUser32.INSTANCE.ReleaseCapture()
                    emit(PointerKind.UP, lParam.toLong())
                }
                return WinDef.LRESULT(0)
            }
            OverlayWin32.WM_CAPTURECHANGED -> {
                // 다른 창이 캡처를 가져갔다(Alt+Tab 등) — 끌기를 마지막 자리에서 끝낸다(엔진이 반쯤 끈 상태로 남지 않게).
                if (dragging) {
                    dragging = false
                    emitClient(PointerKind.UP, lastClientX, lastClientY)
                }
                return WinDef.LRESULT(0)
            }
        }
        return null
    }

    private fun emit(kind: PointerKind, lParam: Long) =
        emitClient(kind, OverlayWin32.loWordSigned(lParam), OverlayWin32.hiWordSigned(lParam))

    private fun emitClient(kind: PointerKind, cx: Int, cy: Int) {
        lastClientX = cx
        lastClientY = cy
        val target = last?.hitTarget(cx, cy) ?: HitTarget.None
        val scale = OverlayWindowClass.dpiScale(hwnd)
        val pt = OverlayPoint((originX + cx) / scale, (originY + cy) / scale)
        runCatching { listener.onPointer(kind, pt, target) }
    }

    override fun close() {
        if (closed) return
        closed = true
        if (!thread.isAlive) return
        runCatching {
            thread.call { _ ->
                dimHwnd?.let { dimClass.destroy(it) }
                dimHwnd = null
                overlayClass.destroy(hwnd)
                bitmap.close()
                dimClass.close()
                overlayClass.close()
            }
        }
    }

    companion object {
        /** 앱의 캐릭터 창 클래스 이름. 시험은 고유 이름을 쓴다(창 0개 확인이 남의 창을 세지 않게). */
        const val DEFAULT_CLASS_NAME = "AingCheck.Overlay"
        const val DIM_SUFFIX = ".UltraDim"
    }
}
