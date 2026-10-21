// 원본: 없음 — 그림 검사(Material Symbols 벡터, 출처는 ui/snapshots/icons/material-symbols-source.tsv)
//
// 아이콘 전부(AppIcon.entries — 862be0f 기준 159개)를 실제로 그린다: 칸마다 잉크가 있고(빈 벡터·잘못 옮긴 좌표면 0), 칸을 넘치지 않고(좌표가 뒤집히면 칸 밖),
// 채움 1 은 채움 0 보다 잉크가 많거나 같다(채움 파일을 뒤바꿔 실으면 잡힌다 — 모양이 같은 기호는 같을 수 있다).
package com.yehsung.aingcheck.ui.icons

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import kotlin.test.Test
import kotlin.test.assertTrue

class AppIconRenderTest {
    private val cell = 32
    private val columns = 16

    @Test
    fun everyIconDrawsInkInsideItsCell() {
        val icons = AppIcon.entries
        val rows = (icons.size + columns - 1) / columns
        val img = DesktopSnapshots.render(columns * cell, rows * cell) {
            Box(Modifier.size((columns * cell).dp, (rows * cell).dp).background(Color.White)) {
                icons.forEachIndexed { i, icon ->
                    AingIcon(icon, contentDescription = null, size = 24.dp, tint = Color.Black,
                        modifier = Modifier.offset(((i % columns) * cell + 4).dp, ((i / columns) * cell + 4).dp))
                }
            }
        }
        val scale = DesktopSnapshots.DENSITY.toInt()
        fun ink(i: Int, inset: Int): Int {
            val x0 = (i % columns) * cell * scale
            val y0 = (i / columns) * cell * scale
            var n = 0
            for (y in y0 + inset * scale until y0 + (cell - inset) * scale) for (x in x0 + inset * scale until x0 + (cell - inset) * scale) {
                val c = img.argb[y * img.width + x]
                val lum = ((c shr 16) and 0xFF) + ((c shr 8) and 0xFF) + (c and 0xFF)
                if (lum < 3 * 128) n++
            }
            return n
        }
        val empty = icons.indices.filter { ink(it, 4) < 20 }.map { icons[it] }
        assertTrue(empty.isEmpty(), "그려지지 않은 아이콘: $empty")
        // 24dp 그림 칸(여백 4) 밖으로 번진 잉크가 없다: 칸 전체 잉크 = 그림 칸 잉크.
        val spilled = icons.indices.filter { ink(it, 0) != ink(it, 4) }.map { icons[it] }
        assertTrue(spilled.isEmpty(), "칸 밖으로 그려진 아이콘(좌표 변환 결함): $spilled")
        val byName = icons.groupBy { it.materialName }
        val inverted = byName.values.filter { it.size == 2 }.filter { pair ->
            val outline = pair.first { !it.filled }
            val filled = pair.first { it.filled }
            ink(icons.indexOf(filled), 4) < ink(icons.indexOf(outline), 4)
        }.map { it.first().materialName }
        assertTrue(inverted.isEmpty(), "채움 1 이 채움 0 보다 잉크가 적다(파일 뒤바뀜): $inverted")
    }
}
