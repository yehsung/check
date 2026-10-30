// 원본: 없음(새 코드) — xplat-w1/briefs/shell.md §4-3(c1 의 창은 FlyoutPageHost 만 그린다 · 높이는 c1 이 잰 내용 높이를
//       FlyoutRequest.contentHeightDip 로 넘긴다) · FlyoutPlacer.MAX_HEIGHT_DIP(700 — 배너 높이 예산과 같은 상한, ⚠️5)
package com.yehsung.aingcheck.desktop.shell.flyout

import androidx.compose.runtime.Composable
import androidx.compose.ui.awt.ComposePanel
import androidx.compose.ui.layout.Layout
import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacer
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import kotlin.math.max
import kotlin.math.min

object FlyoutComposeContent {
    /** 플라이아웃 안 Compose 판. 내용 높이(DIP)를 잴 때마다 [onContentHeightDip] 로 알린다(창 크기는 컨트롤러가 정한다). */
    fun create(
        host: FlyoutPageHost,
        nav: FlyoutNavigator,
        widthDip: () -> Double,
        onContentHeightDip: (Double) -> Unit,
    ): ComposePanel = ComposePanel().apply {
        setContent { Measured(onContentHeightDip) { host.Content(nav, widthDip()) } }
    }

    /**
     * 내용을 상한(700 DIP) 안에서 제 키대로 재고 그 키를 알린다. 창이 더 작으면 창 크기로 자른다.
     * 무한 높이로 재지 않는다 — 세로 스크롤 화면은 무한 높이에서 터진다.
     */
    @Composable
    private fun Measured(onContentHeightDip: (Double) -> Unit, content: @Composable () -> Unit) {
        Layout(content = content) { measurables, constraints ->
            val capPx = (FlyoutPlacer.MAX_HEIGHT_DIP * density).toInt()
            val child = constraints.copy(minHeight = 0, maxHeight = max(capPx, constraints.minHeight))
            val placeables = measurables.map { it.measure(child) }
            val natural = placeables.maxOfOrNull { it.height } ?: 0
            onContentHeightDip(natural / density.toDouble())
            val w = constraints.maxWidth
            val h = min(natural, constraints.maxHeight).coerceAtLeast(constraints.minHeight)
            layout(w, h) { placeables.forEach { it.place(0, 0) } }
        }
    }
}
