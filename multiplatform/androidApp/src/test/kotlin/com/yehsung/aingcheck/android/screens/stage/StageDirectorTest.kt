// 원본: Sources/check/CheckOverlayReactions.swift @ 3bd04bd (ReactionEngine.request — hit 쿨다운 0.6s · 우선순위 거절 · 상태 만료 = 리액션 길이) · Sources/check/CheckOverlayWindow.swift @ 3bd04bd (깜빡임 3~7초)
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import org.junit.AfterClass
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.random.Random
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 무대 감독(탭 → hit · 공개 → 인사 · 깜빡임 · fps · 정지). 몸 판정은 진짜 칸 알파(L 단 페이지를 Robolectric 네이티브 BitmapFactory 로 디코드)로 잰다.
 * 틀은 맥 오버레이 280×340(골든과 같은 구도) 그대로.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class StageDirectorTest {
    companion object {
        private val files = StageBundleFiles.Files(StageBundleFiles.bundle())
        private val library: BakeLibrary by lazy { BakeLibrary.load(files) }
        private val stores = HashMap<String, BakeImageStore>()
        fun store(id: String): BakeImageStore = stores.getOrPut(id) { BakeImageStore(library.finish(id)!!, files, PlatformRaster) }

        @JvmStatic @AfterClass
        fun closeStores() { stores.values.forEach { it.close() }; stores.clear() }
    }

    private val w = StageFraming.FRAME_WIDTH
    private val h = StageFraming.FRAME_HEIGHT
    private val margin = StagePolicy.TAP_MARGIN_POINTS * 2
    private val bodyCenter = Vec2(137.5, 137.5)

    private fun director(id: String = CharacterCatalog.builtInAingID, now: Double = 10.0, seed: Int = 7) =
        StageDirector(library, library.finish(id)!!, now, Random(seed))

    private fun StageDirector.tapAt(p: Vec2, now: Double): TapOutcome = tap(p, frame(now, w, h), margin, { store(it.characterId) }, now)

    @Test
    fun 몸을_두드리면_hit_쿨다운_뒤에_다시() {
        val d = director()
        assertEquals(TapOutcome.hit, d.tapAt(bodyCenter, 11.0))
        assertEquals(StagePolicy.TAP_REACTION, d.player.activeReaction)
        assertEquals(StagePolicy.TAP_REACTION, d.activeReaction)
        assertEquals(TapOutcome.cooldown, d.tapAt(bodyCenter, 11.3), "0.6s 안 두 번째 탭")
        assertEquals(TapOutcome.cooldown, d.tapAt(bodyCenter, 11.59))
        assertEquals(TapOutcome.hit, d.tapAt(bodyCenter, 11.61), "쿨다운 · 상태(0.6s)가 끝나면 다시 받는다")
        assertEquals(2, d.hits)
    }

    @Test
    fun hit_는_몸을_실제로_찌부러뜨린다() {
        val d = director()
        val idle = d.frame(11.0, w, h) as CharacterFrame.Impostor
        d.tapAt(bodyCenter, 11.0)
        // hit 정점(0.08s easeOut 끝): 크기 (1.28, 0.62) — 투영 사각형이 넓고 낮아진다.
        val squash = d.frame(11.0 + 0.08, w, h) as CharacterFrame.Impostor
        fun width(f: CharacterFrame) = f.viewportQuad.maxOf { it.x } - f.viewportQuad.minOf { it.x }
        fun height(f: CharacterFrame) = f.viewportQuad.maxOf { it.y } - f.viewportQuad.minOf { it.y }
        println("AINGCHECK-W5C-HIT idle ${"%.1f".format(width(idle))}×${"%.1f".format(height(idle))} → peak ${"%.1f".format(width(squash))}×${"%.1f".format(height(squash))}")
        assertTrue(width(squash) > width(idle) * 1.15, "찌부 정점 폭")
        assertTrue(height(squash) < height(idle) * 0.8, "찌부 정점 높이")
        // 끝나면 다시 쉬는 자세(트랙 0.525s 뒤 단위) — 같은 시각 두드리지 않은 무대(다른 감독, 같은 idle 위상)와 같은 사각형이다.
        val after = d.frame(11.0 + 0.7, w, h)!!
        val untouched = director().frame(11.0 + 0.7, w, h)!!
        for (i in 0 until 4) {
            assertTrue(kotlin.math.abs(after.viewportQuad[i].x - untouched.viewportQuad[i].x) < 1e-6 &&
                kotlin.math.abs(after.viewportQuad[i].y - untouched.viewportQuad[i].y) < 1e-6, "hit 뒤 꼭짓점 $i")
        }
        assertNull(d.player.activeReaction)
    }

    @Test
    fun 몸_밖은_빗나간다_상자_안이어도_알파가_없으면() {
        val d = director()
        val f = d.frame(11.0, w, h)!!
        assertEquals(TapOutcome.missed, d.tapAt(Vec2(3.0, 3.0), 11.0), "틀 구석")
        // 투영 사각형 왼쪽 위 꼭짓점 바로 안 — 상자 거르기는 통과하지만 칸 알파가 0 이다(맥 :1414 상자 + 칸 알파 > 32).
        val corner = f.viewportQuad[0]
        val inside = Vec2(corner.x + 4, corner.y + 4)
        assertTrue(inside.x >= f.viewportQuad.minOf { it.x } && inside.y >= f.viewportQuad.minOf { it.y })
        assertEquals(TapOutcome.missed, d.tapAt(inside, 11.0))
        assertEquals(0, d.hits)
        assertNull(d.activeReaction)
    }

    @Test
    fun 공개는_인사_한_번_바쁘면_미뤘다가_건다() {
        val d = director()
        assertTrue(d.reveal(20.0))
        assertEquals(StagePolicy.REVEAL_REACTION, d.player.activeReaction)
        // 인사(우선 1) 중 탭(우선 3)은 끼어든다 — 맥 request 규칙.
        assertEquals(TapOutcome.hit, d.tapAt(bodyCenter, 20.3))
        // hit 중 공개: 맥이라면 버리지만 무대는 미룬다.
        assertFalse(d.reveal(20.4))
        assertTrue(d.hasPendingReveal)
        assertFalse(d.tick(20.8), "hit 상태(0.6s) 안")
        assertEquals(StagePolicy.TAP_REACTION, d.activeReaction)
        assertTrue(d.tick(20.91), "hit 상태가 끝난 첫 틱에 건다")
        assertEquals(StagePolicy.REVEAL_REACTION, d.player.activeReaction)
        assertFalse(d.hasPendingReveal)
        assertEquals(2, d.reveals)
        // 인사 중 두 번째 공개(같은 우선순위) → 미뤘다가 인사가 끝나면 한 번 더.
        assertFalse(d.reveal(21.0))
        assertTrue(d.tick(21.92))
        assertEquals(3, d.reveals)
    }

    @Test
    fun 깜빡임은_3에서_7초_간격_리액션_중엔_물러난다() {
        val d = director(now = 0.0, seed = 42)
        var t = 0.0
        val gaps = ArrayList<Double>()
        var last = 0.0
        repeat(40) {
            val next = d.nextBlinkTime
            assertTrue(next - last in 3.0..7.0, "간격 ${next - last}")
            gaps += next - last
            t = next
            d.tick(t)
            assertTrue(d.player.isBlinking(t + 0.05), "깜빡이는 중")
            assertFalse(d.player.isBlinking(t + 0.13), "0.12s 뒤 눈을 뜬다")
            last = t
        }
        assertTrue(gaps.max() - gaps.min() > 1.0, "간격이 무작위다: $gaps")
        // 리액션 중엔 깜빡이지 않는다(재생기 가드) — 그래도 다음 일정은 잡는다.
        val due = d.nextBlinkTime
        d.tapAt(bodyCenter, due - 0.1)
        d.tick(due)
        assertFalse(d.player.isBlinking(due + 0.01))
        assertTrue(d.nextBlinkTime > due)
    }

    @Test
    fun fps_는_유휴_6_활성_30_정지_중엔_시계가_멈춘다() {
        val d = director()
        assertEquals(6.0, d.targetFps(11.0))
        d.tapAt(bodyCenter, 11.0)
        assertEquals(30.0, d.targetFps(11.1))
        assertEquals(30.0, d.targetFps(11.0 + 0.525 + 0.05), "모션 끝 + 0.1s 까지")
        assertEquals(6.0, d.targetFps(11.0 + 0.525 + 0.15))
        // 정지: 장면 시계가 멈추고 탭도 모션을 걸지 않는다.
        d.setSuspended(true, 12.0)
        val frozen = d.player.sceneTime(12.0)
        assertEquals(frozen, d.player.sceneTime(30.0))
        assertEquals(TapOutcome.noMotion, d.tapAt(bodyCenter, 30.0))
        d.setSuspended(false, 30.0)
        assertEquals(TapOutcome.hit, d.tapAt(bodyCenter, 30.1))
        assertTrue(d.nextBlinkTime >= 33.0, "재개 시각부터 다시 센다")
    }

    @Test
    fun 무지개도_황금도_같은_규칙() {
        for (id in listOf(CharacterCatalog.goldAingID, CharacterCatalog.rainbowAingID)) {
            val d = director(id)
            val f = d.frame(11.0, w, h) as CharacterFrame.Impostor
            assertNotNull(f.frame.halo, "$id 후광")
            assertEquals("L", f.frame.tier.name)
            assertEquals(TapOutcome.hit, d.tapAt(bodyCenter, 11.0), id)
        }
    }
}
