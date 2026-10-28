// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (spawnZzzBurst · ReactionActions.makeZNode — Z 노드 셋의 SCNAction 식) — 굽기가 녹화한 tracks/zzz.f32 를 맥 식과 맞댄다
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.character.player.ZzzTrack
import kotlin.math.abs
import kotlin.math.min
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 💤 버스트 트랙(`tracks/zzz.f32`)을 재생기([ZzzTrack])로 읽어 **맥 액션 식**(구현과 독립)과 맞댄다. Z 노드 k(0..2):
 * 국소 시작 (0.04k, 0, 0)e · 불투명도 0 → `wait(0.5k)` → `group(fadeIn 0.3, moveBy((0.06, 0.32, 0)e, 1.6))` → `fadeOut 0.4` →
 * `removeFromParentNode` (선형 시간). 컨테이너는 씬 루트 (0.3, 0.25, 0.1)e · Z 크기 0.12e.
 * 글리프 판 놓기(GlyphPlacement)는 굽기 자산에 아직 없어 앱이 💤 를 그리지 않는다 — 굽기 수정 뒤 따로 잰다.
 */
class ZzzTrackTest {
    private val lib = RepoBake.library
    private val motion = lib.motion

    private fun track(): ZzzTrack = ZzzTrack.of(motion, RepoBake.files.read(motion.zzzFile!!)!!)

    /** 맥 식: 시각 t 의 (국소 위치(e 단위), 불투명도), 제거됐으면 null. */
    private fun mac(k: Int, t: Double): Pair<Vec3, Double>? {
        val u = t - 0.5 * k
        return when {
            u < 0 -> Vec3(0.04 * k, 0.0, 0.0) to 0.0
            u < 1.6 -> Vec3(0.04 * k + 0.06 * u / 1.6, 0.32 * u / 1.6, 0.0) to min(1.0, u / 0.3)
            u < 2.0 -> Vec3(0.04 * k + 0.06, 0.32, 0.0) to 1 - (u - 1.6) / 0.4
            else -> null
        }
    }

    @Test
    fun 표본_수와_컨테이너가_굽기_메타와_같다() {
        val z = track()
        assertEquals(motion.zzzCount, z.count)
        assertEquals(1489, z.count, "480Hz × 3.1s + 1")
        assertEquals(480, z.sampleHz)
        assertEquals(Vec3(0.3, 0.25, 0.1), z.container)
        assertEquals(0.12, z.zScaleExtent)
        assertEquals(3.5, motion.engine.zzzIntervalS, "졸기 동안 3.5초마다 한 버스트(엔진 몫)")
    }

    @Test
    fun Z_노드_셋의_위치_불투명도_제거가_맥_식과_같다() {
        val z = track()
        var worstPos = 0.0; var worstOpacity = 0.0
        val firstRemoved = IntArray(3) { -1 }
        val bad = ArrayList<String>()
        for (i in 0 until z.count) {
            // 표본 i 는 시각 i/480 의 값이다. 표본 사이(i + 0.5)에서 물어 floor 경계 흔들림 없이 그 표본을 읽는다.
            val tSample = i / 480.0
            val tAsk = (i + 0.5) / 480.0
            for (k in 0 until 3) {
                val mine = z.node(k, tAsk)
                val expected = mac(k, tSample)
                if (expected == null) {
                    if (mine != null && bad.size < 10) bad += "노드 $k 표본 $i: 맥은 제거했는데 남아 있다(불투명도 ${mine.second})"
                    if (firstRemoved[k] < 0) firstRemoved[k] = i
                    continue
                }
                if (mine == null) { if (bad.size < 10) bad += "노드 $k 표본 $i: 맥은 살아 있는데 제거됐다"; continue }
                worstPos = maxOf(worstPos, (mine.first - expected.first).length)
                worstOpacity = maxOf(worstOpacity, abs(mine.second - expected.second))
            }
        }
        assertTrue(bad.isEmpty(), bad.joinToString("\n"))
        println("💤: 위치 최악 ${"%.2e".format(worstPos)}e · 불투명도 최악 ${"%.2e".format(worstOpacity)} · 제거 표본 ${firstRemoved.toList()}")
        assertTrue(worstPos < 1e-5, "위치 $worstPos")
        assertTrue(worstOpacity < 1e-5, "불투명도 $worstOpacity")
        assertEquals(listOf(960, 1200, 1440), firstRemoved.toList(), "노드 k 는 2.0 + 0.5k 초에 제거된다")
        // 트랙 밖은 없다(버스트가 끝났다 — 컨테이너 3초에 제거).
        for (k in 0 until 3) {
            assertNull(z.node(k, -0.001))
            assertNull(z.node(k, z.durationS + 0.01))
        }
    }
}
