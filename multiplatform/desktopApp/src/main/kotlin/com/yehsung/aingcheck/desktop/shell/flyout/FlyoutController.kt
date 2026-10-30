// 원본: Sources/check/CheckApp.swift:176-201 @ a90d8623 (★3 말풍선/알림 클릭 → 대화, ★4 presentMenuPopover 한 문)
//       · 설계 D-windows-platform §3-3(미리 만들어 숨김 · 작업 표시줄 쪽 배치 · 비활성화로 닫기 · Esc · 300ms 토글 가드)
//       · xplat-w1/briefs/shell.md §4-2·3(FlyoutNavigator 구현은 c1 · 높이는 c1 이 잰 내용 높이를 FlyoutRequest.contentHeightDip 로)
//
// ★4 프로그램으로 여는 문은 하나: 트레이 클릭·알림 클릭·두 번째 실행·오른쪽 메뉴가 모두 [open] 을 부른다.
// 창(OS)은 [FlyoutSurface] 뒤에 숨긴다 — 이 클래스는 맥 JVM 에서 가짜 표면으로 전부 잰다.
package com.yehsung.aingcheck.desktop.shell.flyout

import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacement
import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacer
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxPoint
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.platform.windows.flyout.ScreenFacts
import com.yehsung.aingcheck.desktop.platform.windows.flyout.TaskbarEdge
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoutes
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 플라이아웃 창 한 장(Windows 구현 = FlyoutWindow). 좌표는 물리 픽셀. */
interface FlyoutSurface {
    fun show(placement: FlyoutPlacement)
    fun hide()
}

/** 화면 사실(TaskbarProbe::probe). [near] 가 있으면 그 점의 모니터. */
fun interface FlyoutScreen {
    fun facts(near: PxPoint?): ScreenFacts?
}

/** 트레이 아이콘 자리(WindowsTrayHost.iconRect). 없으면 null. */
fun interface FlyoutIconLocator {
    fun iconRect(): PxRect?
}

object FlyoutAnchors {
    /** 기준점이 없을 때(두 번째 실행·알림): 알림 영역이 있는 작업 표시줄 끝(아래·위 = 오른쪽 끝, 왼·오른 = 아래 끝). */
    fun fallback(facts: ScreenFacts): PxPoint {
        val tb = facts.taskbar.rect
        return when (facts.taskbar.edge) {
            TaskbarEdge.BOTTOM, TaskbarEdge.TOP -> PxPoint(tb.right - 1, (tb.top + tb.bottom) / 2)
            TaskbarEdge.LEFT, TaskbarEdge.RIGHT -> PxPoint((tb.left + tb.right) / 2, tb.bottom - 1)
        }
    }

    fun center(r: PxRect): PxPoint = PxPoint((r.left + r.right) / 2, (r.top + r.bottom) / 2)
}

class FlyoutController(
    private val surface: FlyoutSurface,
    private val screen: FlyoutScreen,
    private val icon: FlyoutIconLocator = FlyoutIconLocator { null },
    /** 단조 밀리초(System.nanoTime / 1e6). */
    private val clock: () -> Long,
    private val guard: FlyoutToggleGuard = FlyoutToggleGuard(),
    initial: FlyoutRoute = FlyoutRoute.Home,
    initialContentHeightDip: Double = DEFAULT_CONTENT_HEIGHT_DIP,
    /** 원하는 폭(DIP). 로그인·무소속은 FlyoutPlacer.NARROW_WIDTH_DIP(340) — 조립이 세션 단계로 고른다. */
    private val requestedWidthDip: () -> Double = { FlyoutPlacer.WIDTH_DIP },
) : FlyoutNavigator {
    private val visibleState = MutableStateFlow(false)
    private val routeState = MutableStateFlow(initial)
    override val visible: StateFlow<Boolean> = visibleState.asStateFlow()
    override val route: StateFlow<FlyoutRoute> = routeState.asStateFlow()

    private var contentHeightDip = initialContentHeightDip
    private var lastClick: PxPoint? = null

    /** 마지막으로 올린 자리(창 크기·폭 DIP 를 c0 에 넘길 때 쓴다). */
    var placement: FlyoutPlacement? = null
        private set

    /** 실제로 쓴 폭(DIP — 작업 영역이 좁으면 원한 폭보다 작다). c0 의 FlyoutPageHost.Content(widthDip) 로 간다. */
    var widthDip: Double = FlyoutPlacer.WIDTH_DIP
        private set

    /** ★4 한 문. route 가 있으면 그 화면으로 가서 연다. 이미 열려 있으면 화면만 바꾼다. */
    override fun open(route: FlyoutRoute?) {
        if (route != null) routeState.value = route
        if (visibleState.value) return
        val placed = place() ?: return
        placement = placed
        surface.show(placed)
        visibleState.value = true
    }

    override fun navigate(route: FlyoutRoute) {
        routeState.value = route
    }

    /** 뒤 = FlyoutRoutes.backOf(★3: 알림·말풍선에서 온 대화의 뒤로 = 홈). Home 에서 뒤로 = 닫기. */
    override fun back() {
        val prev = FlyoutRoutes.backOf(routeState.value)
        if (prev == null) hide() else routeState.value = prev
    }

    override fun hide() {
        if (!visibleState.value) return
        surface.hide()
        visibleState.value = false
    }

    /** 트레이 왼쪽 클릭(NIN_SELECT·NIN_KEYSELECT). 열려 있으면 닫고, 비활성화로 닫힌 지 300ms 안이면 무시한다. */
    fun onTrayPrimaryClick(screenX: Int, screenY: Int) {
        val now = clock()
        if (visibleState.value) {
            hide()
            return
        }
        if (guard.shouldIgnoreClick(now)) return
        lastClick = PxPoint(screenX, screenY)
        open()
    }

    /** 창이 비활성화됐다(WM_ACTIVATE WA_INACTIVE — 바깥 클릭·다른 창). 닫고 시각을 가드에 남긴다. */
    fun onDeactivated() {
        if (!visibleState.value) return
        guard.markClosedByDeactivation(clock())
        hide()
    }

    /** Esc. 닫기만 한다(가드는 비활성화 때만). */
    fun onEscape() = hide()

    /** c0 이 그린 내용 높이(DIP). 열려 있으면 자리를 다시 잰다(작업 표시줄 쪽 모서리 고정, 반대쪽으로 자람). */
    fun onContentHeight(heightDip: Double) {
        if (heightDip <= 0.0 || heightDip == contentHeightDip) return
        contentHeightDip = heightDip
        if (!visibleState.value) return
        val placed = place() ?: return
        if (placed != placement) {
            placement = placed
            surface.show(placed)
        }
    }

    private fun place(): FlyoutPlacement? {
        val iconRect = icon.iconRect()
        val near = lastClick ?: iconRect?.let(FlyoutAnchors::center)
        val facts = screen.facts(near) ?: return null
        val anchor = near ?: FlyoutAnchors.fallback(facts)
        val placed = FlyoutPlacer.place(facts.request(anchor, iconRect, contentHeightDip, requestedWidthDip()))
        widthDip = placed.rect.width / facts.scale
        return placed
    }

    companion object {
        /** 첫 측정 전 높이(로그인 화면 정도). 첫 프레임 뒤 onContentHeight 가 바로잡는다. */
        const val DEFAULT_CONTENT_HEIGHT_DIP = 560.0
    }
}
