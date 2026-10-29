// 원본: 없음(시험 도우미) — 합성 화면(1920×1080 · 아래 작업 표시줄 48px · 100%), 실제 화면을 읽지 않는다.
package com.yehsung.aingcheck.desktop.shell.flyout

import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacement
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.platform.windows.flyout.ScreenFacts
import com.yehsung.aingcheck.desktop.platform.windows.flyout.TaskbarEdge
import com.yehsung.aingcheck.desktop.platform.windows.flyout.TaskbarInfo

internal class FakeSurface : FlyoutSurface {
    val shown = mutableListOf<FlyoutPlacement>()
    var hides = 0
    override fun show(placement: FlyoutPlacement) { shown += placement }
    override fun hide() { hides++ }
}

internal object SyntheticScreen {
    val facts = ScreenFacts(
        monitor = PxRect(0, 0, 1920, 1080),
        workArea = PxRect(0, 0, 1920, 1032),
        taskbar = TaskbarInfo(TaskbarEdge.BOTTOM, PxRect(0, 1032, 1920, 1080), autoHide = false),
        dpi = 96,
    )
}

internal class FakeClock(var now: Long = 0L) {
    fun read(): Long = now
}
