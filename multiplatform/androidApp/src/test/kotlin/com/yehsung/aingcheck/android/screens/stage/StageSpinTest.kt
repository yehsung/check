// 원본: 없음 (Android 전용 — G §8-19 #6② 공개 한 바퀴 · F §8 B. 맥은 SceneKit 이 몸을 돌린다 — 무대는 L 쉬는 행 + S 스핀 칸을 잇는다)
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.player.CharacterFrame
import org.junit.AfterClass
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.math.abs
import kotlin.random.Random
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 공개 한 바퀴의 칸 고르기와 데움(Robolectric 네이티브 BitmapFactory 로 진짜 페이지를 디코드). 공개 화면 크기 맥 골든 대조는 기기 시험(StageDeviceTest ④).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class StageSpinTest {
    companion object {
        private val assets = StageAssets(StageBundleFiles.Files(StageBundleFiles.bundle()))
        private val library: BakeLibrary by lazy { assets.libraryOrNull()!! }

        @JvmStatic @AfterClass
        fun trim() { assets.trim() }
    }

    /** 공개 화면 크기(L 단 뷰포트 = 틀 1.5배). */
    private val w = StageFraming.FRAME_WIDTH * 1.5
    private val h = StageFraming.FRAME_HEIGHT * 1.5

    private fun frames(d: StageDirector, t0: Double, hz: Double = 240.0): List<CharacterFrame.Impostor> =
        (0..(0.62 * hz).toInt()).map { d.frame(t0 + it / hz, w, h) as CharacterFrame.Impostor }

    @Test
    fun 한_바퀴는_등을_S_스핀_칸으로_그리고_평소와_끝은_L() {
        for (id in library.bakedIds) {
            val d = StageDirector(library, library.finish(id)!!, 0.0, Random(1))
            assertEquals("L", (d.frame(5.0, w, h) as CharacterFrame.Impostor).frame.tier.name, "$id 평소")
            assertTrue(d.reveal(5.5))
            val fs = frames(d, 5.5)
            val spin = fs.filter { it.frame.tier.name == StagePolicy.SPIN_TIER }
            assertTrue(spin.all { it.frame.placement.cell.group == BakeCell.Group.spin }, "$id: S 는 스핀 행만")
            assertTrue(fs.filter { it.frame.tier.name == "L" }.all { abs(it.frame.placement.cell.yawDeg) <= StagePolicy.PREWARM_YAW_DEG }, "$id: 한 바퀴 동안 L 은 데운 칸만")
            val yaws = spin.map { it.frame.placement.cell.yawDeg }.toSet()
            // 한 바퀴 = 요 10° 칸을 등(±180)까지 고루 지난다 — 앞모습이 미끄러지는 것(L ±49° 에 멈춤)과 갈린다.
            assertTrue(yaws.any { abs(it) >= 170 } && yaws.size >= 24, "$id: 스핀 칸 요 ${yaws.sorted()}")
            assertTrue(fs.maxOf { it.frame.placement.angleDeg } < 8.0, "$id: 고른 칸과 시선이 8° 넘게 어긋난 장")
            assertEquals("L", (d.frame(6.3, w, h) as CharacterFrame.Impostor).frame.tier.name, "$id 끝")
        }
    }

    @Test
    fun 스핀을_끄면_앞모습이_미끄러진다_기준선() {
        // 다른 입력(스핀 끔)이면 등 쪽 칸이 하나도 없다 — 위 판정이 늘 초록인 판정이 아님(기억 comparison-baseline-must-differ).
        val d = StageDirector(library, library.finish(library.bakedIds.first())!!, 0.0, Random(1))
        d.spinEnabled = false
        assertTrue(d.reveal(5.5))
        val fs = frames(d, 5.5)
        assertTrue(fs.all { it.frame.tier.name == "L" && abs(it.frame.placement.cell.yawDeg) <= 49 })
        assertTrue(fs.maxOf { it.frame.placement.angleDeg } > 90.0, "스핀 없이도 시선이 맞는다?")
    }

    @Test
    fun 데움은_페이지를_하나씩_풀고_한_바퀴가_고를_칸을_다_덮는다() {
        for (id in library.bakedIds) {
            val store = assets.acquire(library.finish(id)!!)!!
            try {
                val d0 = StageDirector(library, store.finish, 0.0, Random(0))
                val cells = d0.spinPrewarmCells()
                val pages = cells.map { it.page }.toSet()
                println("AINGCHECK-SPIN-PREWARM $id cells=${cells.size} tilts=${cells.map { it.tiltDeg }.toSortedSet()} pages=$pages")
                assertTrue(cells.isNotEmpty() && cells.all { it.group == BakeCell.Group.spin })
                val before = store.pageDecodes
                assertTrue(store.prewarmSpin(cells))
                assertEquals(pages.size, store.pageDecodes - before, "$id: 스핀 페이지마다 한 번(한 번에 하나)")
                assertTrue(store.prewarmSpin(cells), "두 번째 데움은 할 일이 없다")
                val warm = store.pageDecodes
                // 데움을 정한 재생(위상 0.3s 간격 · 120Hz)과 다른 위상(0.17s 어긋남)과 다른 표본(240Hz)으로 한 바퀴를 그려도 페이지를 풀지 않는다.
                for (k in 0 until 86) {
                    val d = StageDirector(library, store.finish, 0.0, Random(k))
                    val t0 = 10.17 + k * 0.17
                    assertTrue(d.reveal(t0))
                    for (f in frames(d, t0)) synchronized(store.lock) { store.cellArt(f.frame.placement.cell, f.frame.closedEyes) }
                }
                assertEquals(warm, store.pageDecodes, "$id: 한 바퀴 그리기 중 페이지 디코드 — 데움이 칸을 다 덮지 못한다")
            } finally {
                assets.release(store)
            }
        }
    }
}
