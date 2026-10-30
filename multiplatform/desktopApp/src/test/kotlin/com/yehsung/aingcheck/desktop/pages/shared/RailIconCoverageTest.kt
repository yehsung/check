// 원본: 없음 — W3-c0 unresolved "ui SfSymbols: house.fill 매핑 없음 — 레일 '홈' 칸이 글자만 나온다"의 수리 그물(공용 패치 10 뒤).
// 레일 칸은 SF 이름으로 아이콘을 찾는다(SharedFlyoutPageHost — SfSymbols.icon(slot.sfName)?.let { AingIcon … }) — 대응이 없으면 조용히 글자만 남는다.
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.icons.SfSymbols
import kotlin.test.Test
import kotlin.test.assertEquals

class RailIconCoverageTest {
    @Test
    fun everyRailSlotHasAnIcon() {
        val missing = RailSlot.entries.filter { SfSymbols.icon(it.sfName) == null }.map { "${it.name}(${it.sfName})" }
        assertEquals(emptyList(), missing, "아이콘 없이 글자만 나오는 레일 칸")
        assertEquals(AppIcon.HomeFill, SfSymbols.icon(RailSlot.HOME.sfName), "홈 칸 = 집 아이콘")
    }
}
