// 원본: Sources/CheckCore/MiniGameEngine.swift:194-230 @ 3bd04bd (MiniGameFrameRate 머리 주석의 "주사율별 목표 fps (전수 확인, k = 프레임당 vsync 수)" 표)
//
// W4-b 완료 기준 ②(G §2-3): **프레임 간격 선택 표 시험** — F§5.4 "간격은 vsync 정수배로 고른다" · 기억 game-frame-rate-judder.
// 간격 규칙 자체(주사율 → 목표 fps → 최소 간격)는 core MiniGameFrameRate 이고 0~500Hz 전수 골든(framerate/fps)이 이미 잰다. 이 시험이 재는 것은
// **화면 쪽 페이서**(MiniGameFramePacer — vsync 마다 오는 프레임 중 어느 것에 틱을 내나)가 그 간격을 받아 실제로 **k vsync 마다 고르게** 틱을 내는가다:
// 주사율마다 2초치 vsync 시각(실제 기기처럼 ±10µs 흔들림)을 흘려, 틱 사이 vsync 수가 **전부 k** 인지(한 번이라도 k+1 이면 그 장이 늘어진 저더다) 본다.
// 기대값(목표 fps · k)은 Swift 머리 주석의 손으로 쓴 표를 그대로 옮긴 것이다(구현에서 다시 계산하지 않는다).
//
// F§5.4 의 표(활성 30 · 유휴 6)는 캐릭터 재생기(W5-a FramePacer)의 목표다. 게임 루프의 목표는 60(Swift MiniGameFrameRate — 정본)이고, 원칙(vsync 정수배)은 같다.
package com.yehsung.aingcheck.ui.games.minigame

import kotlin.math.roundToLong
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MiniGameFramePacerTableTest {
    /** (주사율, 목표 fps, k) — Swift 머리 주석 표. */
    private val uniform: List<Triple<Int, Int, Int>> = listOf(
        // 화면이 줄 수 있는 그대로(k=1)
        Triple(24, 24, 1), Triple(25, 25, 1), Triple(30, 30, 1), Triple(48, 48, 1), Triple(50, 50, 1), Triple(59, 59, 1), Triple(60, 60, 1),
        // 60 위 · 상한 안(k=1)
        Triple(72, 72, 1), Triple(75, 75, 1), Triple(85, 85, 1), Triple(90, 90, 1), Triple(100, 100, 1), Triple(119, 119, 1),
        // 60 위 · 나눠서
        Triple(120, 60, 2), Triple(144, 72, 2), Triple(160, 80, 2), Triple(170, 85, 2), Triple(180, 60, 3), Triple(200, 100, 2),
        Triple(240, 60, 4), Triple(360, 60, 6), Triple(480, 60, 8),
        // 상한이 실제로 거는 곳 — 165 의 약수 중 60 이상은 자기 자신뿐이고 그것은 상한(120) 밖이라 아래쪽 55(3 vsync 씩 완전히 고르다)
        Triple(165, 55, 3),
    )

    /** 바닥이 거는 곳(저더 감수 — 60 폴백) · 화면이 없거나 값이 이상. */
    private val fallback: List<Int> = listOf(121, 125, 127, 143, 155, 169, 175, 187, 209)
    private val implausible: List<Int> = listOf(0, -1, 1, 7)

    /** 결정적 흔들림(±10µs) — 같은 표가 언제나 같은 결과를 낸다. */
    private fun jitterNanos(i: Int): Long = (((i * 2654435761L) ushr 7) % 21L) * 1_000L - 10_000L

    /** [hz] 화면의 vsync 시각 [count] 개(나노초). 첫 vsync 는 흔들지 않는다. */
    private fun vsyncs(hz: Int, count: Int, jitter: Boolean): List<Long> =
        (0 until count).map { i -> (i * 1_000_000_000.0 / hz).roundToLong() + if (jitter && i > 0) jitterNanos(i) else 0L }

    /** 틱이 선 vsync 번호들. */
    private fun ticks(hz: Int, stamps: List<Long>): List<Int> {
        val pacer = MiniGameFramePacer(hz)
        return stamps.indices.filter { pacer.shouldTick(stamps[it]) }
    }

    @Test
    fun everyRefreshRateTicksOnEveryKthVsyncWithoutJudder() {
        for ((hz, fps, k) in uniform) {
            val pacer = MiniGameFramePacer(hz)
            assertEquals(fps, pacer.targetFPS, "$hz Hz 의 목표 fps")
            assertEquals(k, pacer.vsyncsPerTick, "$hz Hz 의 틱당 vsync 수")
            for (jitter in listOf(false, true)) {
                val stamps = vsyncs(hz, hz * 2 + 1, jitter)
                val gaps = ticks(hz, stamps).zipWithNext { a, b -> b - a }
                assertTrue(gaps.isNotEmpty(), "$hz Hz: 틱이 없다")
                assertEquals(setOf(k), gaps.toSet(), "$hz Hz(흔들림 $jitter): 틱 사이 vsync 수가 전부 $k 여야 한다 — 다른 값은 늘어진 장(저더)")
                // 2초에 목표 fps × 2 장(첫 틱 포함 +1).
                assertEquals(fps * 2 + 1, ticks(hz, stamps).size, "$hz Hz(흔들림 $jitter): 2초 틱 수")
            }
        }
    }

    @Test
    fun fallbackRatesTickEvenlyBetweenFortyAndSixty() {
        // 폴백 주사율(121 · 125 …)에서 Swift(TimelineView — 이상 시각을 누적하는 스케줄)는 60fps 를 요구하고 저더를 감수한다. Compose 에는 그
        // 스케줄러가 없어 이 페이서는 **직전 틱 기준**으로 고른다 — 그래서 저더 대신 1/60 초 이상인 첫 vsync 마다 **고르게** 선다(40~60fps).
        // Swift 바닥(minFPS 40 — "그 아래는 슬라이드쇼")보다 위다. 이 이탈은 보고에 적는다(나눠떨어지는 주사율에서는 Swift 와 같은 k).
        for (hz in fallback) {
            val pacer = MiniGameFramePacer(hz)
            assertEquals(60, pacer.targetFPS, "$hz Hz: 바닥 아래라 60 폴백")
            assertNull(pacer.vsyncsPerTick, "$hz Hz: 나눠떨어지지 않는다")
            val stamps = vsyncs(hz, hz * 2 + 1, jitter = false)
            val picked = ticks(hz, stamps)
            val gaps = picked.zipWithNext { a, b -> b - a }.toSet()
            assertEquals(1, gaps.size, "$hz Hz: 틱 간격이 고르다 — $gaps")
            val fps = hz.toDouble() / gaps.single()
            assertTrue(fps in 40.0..60.0, "$hz Hz: ${fps}fps — 바닥 40 · 상한 60 사이")
            val minGapNanos = picked.zipWithNext { a, b -> stamps[b] - stamps[a] }.min()
            assertTrue(minGapNanos >= pacer.minimumIntervalNanos, "$hz Hz: 최소 간격보다 촘촘한 틱")
        }
        for (hz in implausible) {
            assertEquals(60, MiniGameFramePacer(hz).targetFPS, "$hz Hz: 잘못 읽은 값 → 60")
            assertNull(MiniGameFramePacer(hz).vsyncsPerTick)
        }
    }

    @Test
    fun resetStartsANewBaselineAtTheNextVsync() {
        // 판이 멈췄다 다시 돌 때(정지 · 결과 → 새 판): 첫 vsync 가 곧바로 틱이다 — 멈춘 구간이 다음 틱을 늦추지 않는다.
        val pacer = MiniGameFramePacer(120)
        assertTrue(pacer.shouldTick(0L))
        assertTrue(!pacer.shouldTick(8_333_333L))
        pacer.reset()
        assertTrue(pacer.shouldTick(8_333_334L), "리셋 뒤 첫 vsync 는 틱")
    }

    @Test
    fun tickDateKeepsTheFrameClockDifferences() {
        // 틱 시각은 프레임 시계 그대로(축이 하나) — 두 틱의 차가 프레임 시각의 차다(1/64 초는 이진수로 정확하다).
        val a = MiniGameFramePacer.tickDate(1_000_000_000L)
        val b = MiniGameFramePacer.tickDate(1_015_625_000L)
        assertEquals(1.0 / 64, b.timeIntervalSince(a))
    }
}
