// 원본: 없음 — RoundedCornerShape(28) 은 28dp 가 아니라 **28%** 다(Int 겹쳐 싣기). 시트 높이 390 이면 모서리 110dp 라 왼쪽 위 닫기 단추가 잘려 나갔다.
package com.yehsung.aingcheck.ui.theme

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.unit.Density
import kotlin.test.Test
import kotlin.test.assertEquals

class AingShapesTest {
    /** 큰 칸과 작은 칸에서 모서리가 같아야 dp 다(퍼센트면 칸 크기를 따라간다). */
    @Test
    fun cornersAreDpNotPercent() {
        val density = Density(1f)
        for (size in listOf(Size(393f, 390f), Size(100f, 100f))) {
            assertEquals(28f, AingShapes.extraLarge.topStart.toPx(size, density))
            assertEquals(8f, AingShapes.extraSmall.topStart.toPx(size, density))
        }
    }
}
