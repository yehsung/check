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
 * T4: 골든 160장(금 · 무지개)의 후광 칸 · 판 네 꼭짓점.
 *  ① 맥 순수 함수 결과(golden `halo.quadPx` — 굽기가 Swift `haloPose · haloCell · haloCellTransform` 으로 낸 값)와 꼭짓점 ≤ 0.5px.
 *  ② F §6 T4 원문 기준(SceneKit 칸 노드 **presentation** 투영): 골든이 적은 `sceneKitQuadMaxDiffPx`(= 순수 함수 판과 presentation 판의
 *     최대 꼭짓점 차) 로 삼각부등식 구간 [sk − d, sk + d] 을 낸다(d = ① 의 Kotlin ↔ 순수 함수 차). presentation 이 순수 함수와 같은 장은
 *     Kotlin 도 0.5px 안이어야 하고, 넘는 장(맥 제약이 이징 액션 중 옛 부모 사슬을 보는 지연 — `GoldAingFinish.swift` ⚠ 알려진 한계)은
 *     **장 수 · 리액션 · 칸 어긋남을 잠근다**. 지연을 재현하지 않는 것은 설계 판단 대기(보고)다 — 늘거나 줄면 빨갛다.
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
    fun T4_SceneKit_presentation_대비_지연_장을_잠근다() {
        val halos = RepoBake.goldens.entries.filter { it.haloQuad != null }
        val matches = ArrayList<String>(); val lagged = ArrayList<Pair<String, String>>()
        val bad = ArrayList<String>()
        var worstMatch = 0.0
        for (g in halos) {
            val halo = GoldenReplay.plan(lib, g).halo!!
            val d = halo.quad.indices.maxOf { hypot(halo.quad[it].x - g.haloQuad!![it].x, halo.quad[it].y - g.haloQuad!![it].y) }
            val sk = g.haloSceneKitMaxDiffPx ?: run { bad += "${g.id}: sceneKitQuadMaxDiffPx 없음"; continue }
            val lo = sk - d; val hi = sk + d
            when {
                hi <= 0.5 -> { matches += g.id; worstMatch = maxOf(worstMatch, hi) }
                lo > 0.5 -> lagged += g.id to g.reaction
                else -> bad += "${g.id}: presentation 대비 [${"%.4f".format(lo)}, ${"%.4f".format(hi)}]px 가 0.5px 를 걸친다"
            }
            if (g.haloSceneKitCell != g.haloCell && lo <= 0.5) bad += "${g.id}: SceneKit 칸 ${g.haloSceneKitCell} ≠ 순수 함수 칸 ${g.haloCell} 인데 판이 0.5px 안"
        }
        assertTrue(bad.isEmpty(), bad.joinToString("\n"))
        val reactions = lagged.map { it.second }.toSortedSet()
        val over2 = halos.count { (it.haloSceneKitMaxDiffPx ?: 0.0) > 2.0 }
        val cellMismatch = halos.count { it.haloSceneKitCell != it.haloCell }
        println("T4(presentation): 0.5px 안 ${matches.size}장(최악 ${"%.4f".format(worstMatch)}px) · 맥 지연 ${lagged.size}장(> 2px $over2 · 칸 어긋남 $cellMismatch) · 리액션 $reactions")
        assertEquals(112, matches.size, "presentation 과 0.5px 안인 장")
        assertEquals(48, lagged.size, "맥 후광 지연 장(늘면 재생기 · 골든이 어긋났다, 줄면 맥이 고쳐졌다 — 잠금을 다시 본다)")
        assertEquals(
            mapOf("goalAchieved" to 12, "hit" to 12, "poked" to 12, "ultraPoked" to 12),
            lagged.groupingBy { it.second }.eachCount().toSortedMap(),
            "지연은 이징 액션 리액션 넷에서만, 리액션마다 장 수 그대로",
        )
        assertEquals(37, over2, "2px 넘는 지연 장(T3 haloLag 갈래의 원천)")
        assertEquals(3, cellMismatch, "SceneKit 이 다른 칸을 켠 장(모두 지연 장 — 위 bad 가 잰다)")
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
