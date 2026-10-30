// 원본: Sources/check/CheckTodoBoardAppearance.swift 주석 표(:136-160 대비 · :262-266 blurAlpha 스텝 · :300 surfaceAlpha) · :222 clamped ·
//       :406-427 복원 검증 · :436-453 조작 · CheckTodoBoardWindow.swift :105-182 누적기 · :741 조합 · CheckTodoBoardView.swift :132-139 그림자 세기
package com.yehsung.aingcheck.desktop.overlay.todoboard

import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TodoBoardAppearanceTest {
    private fun a(op: Double) = TodoBoardAppearance(op)

    @Test
    fun railAndDefaultsMatchTheMacConstants() {
        assertEquals(0.20, TodoBoardAppearance.MIN_OPACITY)
        assertEquals(0.95, TodoBoardAppearance.MAX_OPACITY)
        assertEquals(0.55, TodoBoardAppearance.DEFAULT_OPACITY)
        assertEquals(0.05, TodoBoardAppearance.STEP)
        assertEquals(0.52, TodoBoardAppearance.BLUR_KNEE)
        assertEquals(TodoBoardAppearance.DEFAULT_OPACITY, TodoBoardTint.OPACITY)
        assertEquals("check.todoBoardOpacity", TodoBoardAppearanceStore.DEFAULTS_KEY, "맥 UserDefaults 키 이름 그대로")
        // 출고값: 블러 온전 · 표면 배율 1 · 그림자 꺼짐 = 도입 전과 같은 그림(맥 :175).
        val d = TodoBoardAppearance()
        assertEquals(1.0, d.blurAlpha); assertEquals(1.0, d.surfaceAlpha); assertFalse(d.needsTextShadow); assertEquals("55%", d.percentLabel)
    }

    @Test
    fun blurAlphaStepsFollowTheMacTable() {
        // 맥 :262 — 0.52→1.000, 0.50→0.908, 0.45→0.691, 0.40→0.494, 0.35→0.321, 0.30→0.175, 0.25→0.062, 0.20→0.000
        val table = listOf(0.95 to 1.0, 0.55 to 1.0, 0.52 to 1.0, 0.50 to 0.908, 0.45 to 0.691, 0.40 to 0.494, 0.35 to 0.321, 0.30 to 0.175, 0.25 to 0.062, 0.20 to 0.0)
        for ((op, blur) in table) assertEquals(blur, a(op).blurAlpha, 0.0006, "blurAlpha($op)")
        assertEquals(0.995, a(0.519).blurAlpha, 0.001, "무릎점에서 튀지 않는다(:256)")
    }

    @Test
    fun surfaceAlphaFollowsTheMacTable() {
        val table = listOf(0.20 to 0.364, 0.50 to 0.909, 0.52 to 0.945, 0.55 to 1.0, 0.95 to 1.0)
        for ((op, s) in table) assertEquals(s, a(op).surfaceAlpha, 0.0006, "surfaceAlpha($op)")
    }

    @Test
    fun contrastWithFullBlurAndWithTheFinalCurveMatchesTheMacTables() {
        // 블러 온전(:139): 0.45→4.06 0.50→4.46 0.52→4.63 0.55→4.91 0.62→5.63 0.95→10.98
        for ((op, r) in listOf(0.45 to 4.06, 0.50 to 4.46, 0.52 to 4.63, 0.55 to 4.91, 0.62 to 5.63, 0.95 to 10.98)) {
            assertEquals(r, TodoBoardAppearance.textContrast(tintAlpha = op, blurAlpha = 1.0), 0.015, "블러 온전 대비($op)")
        }
        // 최종 곡선(:146): op → 본문 · 보조
        val curve = listOf(
            Triple(0.55, 4.91, 3.43), Triple(0.52, 4.63, 3.27), Triple(0.50, 4.26, 3.05), Triple(0.45, 3.45, 2.58),
            Triple(0.40, 2.80, 2.19), Triple(0.35, 2.31, 1.88), Triple(0.30, 1.92, 1.63), Triple(0.25, 1.63, 1.44), Triple(0.20, 1.43, 1.30),
        )
        for ((op, body, secondary) in curve) {
            assertEquals(body, a(op).textContrast(), 0.015, "본문 대비($op)")
            assertEquals(secondary, a(op).textContrast(TodoBoardTint.SECONDARY_TEXT_ALPHA), 0.015, "보조 대비($op)")
        }
        assertTrue(a(0.55).textContrast() >= TodoBoardContrast.AA_BODY_TEXT, "출고값은 본문 AA")
        assertTrue(a(0.55).textContrast(TodoBoardTint.SECONDARY_TEXT_ALPHA) >= TodoBoardContrast.AA_LARGE_TEXT, "출고값 보조는 큰 글자 3:1")
        assertEquals(TodoBoardTint.HUD_OVER_WHITE_LEVEL, TodoBoardTint.materialLevel(1.0), 0.0005, "순백 위 재질 0.713(:32)")
        // 재질 겹을 흰 → 검정 두 겹(토큰만)으로 낸 합성이 회색 0.283 한 겹과 같다.
        for (blur in listOf(0.0, 0.3, 0.691, 1.0)) for (bd in listOf(0.0, 0.12, 0.5, 1.0)) {
            val (w, k) = TodoBoardTint.materialLayerAlphas(blur)
            assertEquals(TodoBoardTint.materialLevel(bd, blur), (1 - k) * (w + (1 - w) * bd), 1e-12, "두 겹 합성(blur=$blur, 바탕=$bd)")
        }
    }

    @Test
    fun clampedSnapsToTheRailAndTheMilliGrid() {
        assertEquals(0.55, TodoBoardAppearance.clamped(Double.NaN))
        assertEquals(0.95, TodoBoardAppearance.clamped(Double.POSITIVE_INFINITY))
        assertEquals(0.20, TodoBoardAppearance.clamped(Double.NEGATIVE_INFINITY))
        assertEquals(0.20, TodoBoardAppearance.clamped(0.0))
        assertEquals(0.333, TodoBoardAppearance.clamped(0.33333))
        // 15번 올리면 정확히 끝값(먼지가 쌓이지 않는다 — :219).
        var v = 0.20
        repeat(15) { v = TodoBoardAppearance.clamped(v + TodoBoardAppearance.STEP) }
        assertEquals(0.95, v)
        assertEquals("20%", a(0.20).percentLabel); assertEquals("95%", a(0.95).percentLabel); assertEquals("33%", a(0.334).percentLabel)
    }

    @Test
    fun textShadowOnlyBelowTheKneeWithARampFromTheDefault() {
        assertEquals(0.0, TodoBoardTextShadow.strength(a(0.55)))
        assertEquals(0.0, TodoBoardTextShadow.strength(a(0.52)), "무릎점은 켜지지 않는다(<)")
        assertEquals(0.5, TodoBoardTextShadow.strength(a(0.50)), 1e-9, "램프 (0.55−0.50)/0.10 = 0.5")
        assertEquals(1.0, TodoBoardTextShadow.strength(a(0.45)), 1e-9)
        assertEquals(0.5, TodoBoardTextShadow.strength(a(0.519)), 1e-9, "하한 0.5")
        assertEquals(1.0, TodoBoardTextShadow.strength(a(0.20)), 1e-9)
    }

    private class MapKv : DesktopKeyValueStore {
        val m = HashMap<String, String>()
        var writes = 0
        override fun getString(key: String): String? = m[key]
        override fun putString(key: String, value: String?) { writes += 1; if (value == null) m.remove(key) else m[key] = value }
        override fun keys(prefix: String): List<String> = m.keys.filter { it.startsWith(prefix) }.sorted()
    }

    @Test
    fun storeRestoreValidatesInsteadOfClamping() {
        for ((raw, expected) in listOf(null to 0.55, "0.3" to 0.3, " 0.3 " to 0.3, "0" to 0.55, "1.5" to 0.55, "55" to 0.55, "abc" to 0.55, "NaN" to 0.55, "Infinity" to 0.55, "0.2" to 0.2, "0.95" to 0.95, "0.33333" to 0.333)) {
            val kv = MapKv().apply { raw?.let { m[TodoBoardAppearanceStore.DEFAULTS_KEY] = it } }
            assertEquals(expected, TodoBoardAppearanceStore(kv).appearance.opacity, "복원($raw)")
        }
    }

    @Test
    fun storeWritesAndNotifiesOnlyOnRealChanges() {
        val kv = MapKv()
        val s = TodoBoardAppearanceStore(kv)
        val seen = ArrayList<Double>()
        val remove = s.addListener { seen += it.opacity }
        s.setOpacity(0.55) // 같은 값
        s.setOpacity(Double.NaN) // 무시(리셋 아님)
        s.nudge(Double.POSITIVE_INFINITY) // 무시
        assertEquals(0, kv.writes); assertTrue(seen.isEmpty())
        s.setOpacity(0.4)
        s.nudge(-TodoBoardAppearance.STEP)
        s.setOpacity(-3.0) // 끝에 붙는다
        s.setOpacity(0.1) // 이미 끝
        assertEquals(listOf(0.4, 0.35, 0.2), seen)
        assertEquals("0.2", kv.m[TodoBoardAppearanceStore.DEFAULTS_KEY])
        assertEquals(0.2, TodoBoardAppearanceStore(kv).appearance.opacity, "다시 읽어도 같은 값")
        remove(); s.setOpacity(0.9)
        assertEquals(3, seen.size, "떼어 낸 뒤엔 알리지 않는다")
    }

    @Test
    fun scrollGestureMatchesTheMacAccumulator() {
        assertEquals(15.0, TodoBoardScrollOpacityGesture.RAIL_STEPS, 1e-9)
        assertEquals(32.0, TodoBoardScrollOpacityGesture.STEP_DISTANCE, 1e-9, "240 / 7.5")
        assertEquals(8.0, TodoBoardScrollOpacityGesture.MAX_STEPS_PER_EVENT, "7.5 반올림(Swift .rounded)")
        val g = TodoBoardScrollOpacityGesture()
        fun precise(dy: Double, inverted: Boolean = false, momentum: Boolean = false) = g.steps(TodoBoardScrollSample(dy, isPrecise = true, isInverted = inverted, isMomentum = momentum))
        assertEquals(0, precise(20.0)); assertEquals(1, precise(20.0), "20+20=40 → 1칸, 잔여 8")
        assertEquals(0, precise(0.0, momentum = true))
        assertEquals(0, precise(30.0), "관성이 잔여를 털었다(남았으면 8+30 = 한 칸)")
        assertEquals(0, precise(-10.0), "방향이 바뀌면 잔여를 버린다")
        assertEquals(-1, precise(-30.0))
        assertEquals(0, precise(500.0, momentum = true), "관성은 버리고 잔여도 턴다")
        assertEquals(1, precise(-40.0, inverted = true), "뒤집힌 장치는 물리 방향으로")
        assertEquals(8, precise(1e6), "한 이벤트 한도")
        assertEquals(0, precise(20.0), "한도에 걸리면 잔여 0")
        assertEquals(0, precise(Double.NaN)); assertEquals(0, precise(0.0))
        assertEquals(1, g.steps(TodoBoardScrollSample(0.5, isPrecise = false)), "걸림쇠 휠 = 한 이벤트 한 칸")
        assertEquals(-1, g.steps(TodoBoardScrollSample(-300.0, isPrecise = false)))
        g.reset()
    }

    @Test
    fun windowsWheelMappingAndModifierCombination() {
        // 걸림쇠 한 칸 위로(AWT 회전 −1) = 더 진하게 한 칸.
        val up = TodoBoardScrollSample.fromWheelRotation(-1.0)
        assertFalse(up.isPrecise); assertTrue(up.deltaY > 0)
        assertEquals(1, TodoBoardScrollOpacityGesture().steps(up))
        assertEquals(-1, TodoBoardScrollOpacityGesture().steps(TodoBoardScrollSample.fromWheelRotation(3.0)))
        val tp = TodoBoardScrollSample.fromWheelRotation(-0.4)
        assertTrue(tp.isPrecise)
        val g = TodoBoardScrollOpacityGesture()
        assertEquals(0, g.steps(tp)); assertEquals(1, g.steps(tp), "16+16 = 32pt → 1칸")
        assertTrue(TodoBoardScrollOpacityGesture.adjustsOpacity(alt = true, ctrl = false, shift = false, meta = false))
        for ((ctrl, shift, meta) in listOf(Triple(true, false, false), Triple(false, true, false), Triple(false, false, true))) {
            assertFalse(TodoBoardScrollOpacityGesture.adjustsOpacity(true, ctrl, shift, meta), "Alt 에 다른 조합이 섞이면 물러난다")
        }
        assertFalse(TodoBoardScrollOpacityGesture.adjustsOpacity(false, false, false, false))
    }
}
