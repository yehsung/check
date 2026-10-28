// 원본: Sources/check/GoldAingFinish.swift @ 1b8260d (haloPose · haloCell · haloCellTransform) — 설계 F §6 T4 후광 배치
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.math.Angles
import com.yehsung.aingcheck.character.parity.GoldenReplay
import com.yehsung.aingcheck.character.pose.HaloLayer
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import kotlin.math.hypot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * T4: 골든 160장(금 · 무지개)의 후광 칸 · 판 네 꼭짓점을 맥 순수 함수 결과(golden `halo.quadPx`)와 맞댄다 — 꼭짓점 ≤ 0.5px.
 * (SceneKit 이 실제로 세운 판과의 차이 `sceneKitQuadMaxDiffPx` 는 맥 제약의 지연이라 T3 갈래 [haloLag] 로 따로 다룬다.)
 */
class HaloPlacementTest {
    private val lib = RepoBake.library

    @Test
    fun T4_후광_칸과_꼭짓점이_맥_순수_함수와_같다() {
        val halos = RepoBake.goldens.entries.filter { it.haloQuad != null }
        assertEquals(160, halos.size)
        var worst = 0.0
        val bad = ArrayList<String>()
        for (g in halos) {
            val frame = GoldenReplay.plan(lib, g)
            val halo = frame.halo ?: run { bad += "${g.id}: 후광 없음"; null } ?: continue
            if (halo.cell != g.haloCell) bad += "${g.id}: 칸 ${halo.cell} ≠ ${g.haloCell}"
            val d = halo.quad.indices.maxOf { hypot(halo.quad[it].x - g.haloQuad!![it].x, halo.quad[it].y - g.haloQuad!![it].y) }
            worst = maxOf(worst, d)
            if (d > 0.5) bad += "${g.id}: 꼭짓점 ${"%.3f".format(d)}px"
        }
        assertTrue(bad.isEmpty(), "T4 실패 ${bad.size}건:\n" + bad.take(20).joinToString("\n"))
        println("T4: 160장 최악 꼭짓점 ${"%.4f".format(worst)}px")
    }

    @Test
    fun 후광_칸_고르기_규칙() {
        val halo = lib.finish(CharacterCatalog.goldAingID)!!.bake.halo!!
        fun cell(deg: Double) = HaloLayer.cell(Angles.rad(deg), halo)
        // 쉬는 자세 띠(±9.02°) 안은 그 자세 칸.
        assertEquals(0, cell(8.9)); assertEquals(0, cell(-9.0))
        assertEquals(1, cell(9.1), "띠 밖은 가장 가까운 칸(10°)")
        assertEquals(4, cell(48.9)); assertEquals(4, cell(31.1))
        assertEquals(5, cell(49.1))
        assertEquals(32, cell(-40.0)); assertEquals(32, cell(-48.0))
        // 360° 감기.
        assertEquals(18, cell(-176.0)); assertEquals(19, cell(-174.0)); assertEquals(18, cell(184.0)); assertEquals(0, cell(720.0))
        // 반올림(Swift .rounded() = 0.5 는 0 에서 먼 쪽 — Kotlin roundToInt 는 +∞ 쪽이라 음수 .5 에서 갈린다).
        assertEquals(18, HaloLayer.nearestCell(-175.0, halo)); assertEquals(18, HaloLayer.nearestCell(175.0, halo))
        assertEquals(35, HaloLayer.nearestCell(-5.0, halo), "−0.5 → −1 → 35(roundToInt 면 0)")
        assertEquals(1, HaloLayer.nearestCell(5.0, halo))
        assertEquals(0, HaloLayer.cell(Double.NaN, halo))
    }
}
