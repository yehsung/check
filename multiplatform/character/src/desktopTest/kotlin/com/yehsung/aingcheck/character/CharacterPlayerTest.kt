// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (setDragFacing 가드 · runReaction 의 정지 중 거절 · reconcileAfterResume · 몸 클릭 판정) — 설계 F §5.2 경계 API · §5.4 프레임 정책
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.bake.PoseSample
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.player.CharacterFrames
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.player.FramePacer
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class CharacterPlayerTest {
    private val lib = RepoBake.library

    @Test
    fun 리액션은_단위로_스냅한_뒤_재생하고_끝나면_단위다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.builtInAingID)
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(0.0))
        assertTrue(p.play("hit", 1.0))
        assertEquals("hit", p.activeReaction)
        assertNotEquals(PoseSample.IDENTITY, p.wrapperPose(1.1))
        // 다른 리액션이 끼어들면 그 자리에서 단위로 스냅 → 새 트랙 첫 표본(= 단위 근처)부터.
        assertTrue(p.play("greeting", 1.2))
        val first = p.wrapperPose(1.2)
        assertTrue((first.position).length < 1e-6 && abs(first.scale.y - 1) < 1e-6)
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(1.2 + lib.track("greeting")!!.durationS + 0.01))
        assertEquals(null, p.activeReaction)
        assertFalse(p.play("no-such-reaction", 3.0))
        assertFalse(p.play("wake", 3.0), "깨기는 wake() 로만")
    }

    @Test
    fun 졸기는_끝_자세를_쥐고_감은_눈이다() {
        val p = CharacterPlayer(lib)
        assertTrue(p.beginSleep(0.0))
        val end = p.wrapperPose(5.0)
        val sleep = lib.motion.sleepPose
        assertTrue(abs(end.position.y - sleep.position.y * lib.motion.extent) < 1e-4)
        assertEquals(end, p.wrapperPose(50.0), "몇 초가 지나도 같은 자세")
        assertTrue(p.eyesClosed && p.sleeping)
        assertEquals(null, p.reactionEndsAt(), "끝 자세를 쥔 졸기는 활성 fps 를 붙들지 않는다")
        p.interrupt(51.0)
        assertFalse(p.eyesClosed); assertFalse(p.sleeping)
    }

    @Test
    fun 바라보기는_즉시_스냅이고_같은_값은_무시한다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.goldAingID)
        p.setFacing(1, moving = false, now = 0.0)
        assertEquals(40.0, p.facingDegrees())
        p.setFacing(-1, moving = false, now = 0.1)
        assertEquals(-40.0, p.facingDegrees())
        p.setFacing(5, moving = false, now = 0.2)
        assertEquals(40.0, p.facingDegrees(), "방향은 −1 · 0 · +1 로 접힌다")
        p.setFacing(0, moving = true, now = 0.3)
        assertFalse(p.walking, "정면을 보며 걷지는 않는다")
    }

    @Test
    fun 정지_중에는_리액션을_걸지_않고_재개하면_벽시계로_만료된_잔여를_걷는다() {
        val p = CharacterPlayer(lib)
        p.setSuspended(true, 0.0)
        assertFalse(p.play("hit", 0.5), "정지 중엔 모션을 걸지 않는다(맥 runReaction)")
        p.setSuspended(false, 1.0)
        assertTrue(p.play("poked", 1.0))
        p.setSuspended(true, 1.2)
        val frozen = p.wrapperPose(1.2)
        assertEquals(frozen, p.wrapperPose(30.0), "정지 동안 장면 시계가 멈춘다")
        p.setSuspended(false, 30.0) // 찔림 2.5s 는 벽시계로 이미 지났다 → 잔여를 걷는다
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(30.0))

        // 아직 안 지났으면 이어서 재생(0.x초 잔여).
        assertTrue(p.play("poked", 40.0))
        p.setSuspended(true, 40.5)
        p.setSuspended(false, 41.0)
        assertNotEquals(PoseSample.IDENTITY, p.wrapperPose(41.0))
    }

    @Test
    fun 캐릭터를_바꾸면_idle_위상이_0_으로_돌아간다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.builtInAingID, now = 0.0)
        val atFive = p.chain(5.0).character
        p.swapCharacter(CharacterCatalog.rainbowAingID, 5.0)
        assertEquals(0.0, p.idleTime(5.0))
        val (bob, sway) = lib.motion.idle.evaluate(0.0)
        assertEquals(0.0, bob); assertEquals(0.0, sway)
        assertNotEquals(atFive.translation, p.chain(5.0).character.translation)
    }

    @Test
    fun 프레임_간격은_vsync_정수배다() {
        // F §5.4 표: 활성 30 기준.
        val table = mapOf(60.0 to 2, 75.0 to 3, 90.0 to 3, 100.0 to 3, 120.0 to 4, 144.0 to 5, 165.0 to 6, 240.0 to 8)
        for ((hz, n) in table) assertEquals(n, FramePacer.vsyncInterval(hz, 30.0), "${hz}Hz")
        assertEquals(10, FramePacer.vsyncInterval(60.0, 6.0))
        assertTrue(FramePacer.vsyncInterval(75.0, 6.0) in 12..13)
        assertTrue(FramePacer.isActive(1.0, reactionEndsAt = 0.95, resetAfterS = 0.1, blinking = false, walking = false))
        assertFalse(FramePacer.isActive(1.06, reactionEndsAt = 0.95, resetAfterS = 0.1, blinking = false, walking = false))
        val q = listOf(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(1.0, 1.0), Vec2(0.0, 1.0))
        assertFalse(FramePacer.needsRedraw("a", q, "a", q.map { Vec2(it.x + 0.2, it.y) }))
        assertTrue(FramePacer.needsRedraw("a", q, "a", q.map { Vec2(it.x + 0.3, it.y) }))
        assertTrue(FramePacer.needsRedraw("a", q, "b", q))
    }

    @Test
    fun 몸_클릭은_칸_알파로_가르고_후광은_빠진다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.goldAingID)
        val frame = assertNotNull(CharacterFrames.compute(p, 1.0, 280.0, 340.0)) as CharacterFrame.Impostor
        assertEquals("S", frame.frame.tier.name)
        val store = BakeImageStore(frame.frame.finish, RepoBake.files, PlatformRaster)
        try {
            val stores = { _: com.yehsung.aingcheck.character.bake.BakedFinish -> store }
            val pivot = lib.camera.project(p.chain(1.0).character.translation, 280.0, 340.0)
            assertTrue(CharacterFrames.hitTest(frame, pivot, 24.0, stores), "몸 중심")
            assertFalse(CharacterFrames.hitTest(frame, Vec2(2.0, 2.0), 24.0, stores), "구석은 상자 밖")
            // 후광 판 안이지만 몸 밖인 점: 후광 사각형 위 변 가운데 근처.
            val h = frame.frame.halo!!.quad
            val haloTop = Vec2((h[0].x + h[1].x) / 2, (h[0].y + h[1].y) / 2 + 10)
            assertFalse(CharacterFrames.hitTest(frame, haloTop, 24.0, stores), "후광은 몸이 아니다")
            // 상자 + 여백 안이어도 알파가 32 이하면 아니다: 몸 상자 왼쪽 위 모서리 바로 안.
            val q = frame.viewportQuad
            val corner = Vec2(q.minOf { it.x } + 1, q.minOf { it.y } + 1)
            assertFalse(CharacterFrames.hitTest(frame, corner, 24.0, stores), "투명 여백")
        } finally {
            store.close()
        }
    }

    @Test
    fun 단은_몸_크기로_고르고_없는_단은_있는_단으로() {
        val f = lib.finish(CharacterCatalog.builtInAingID)!!
        assertEquals("S", com.yehsung.aingcheck.character.render.ImpostorRenderer.chooseTier(f, 170.0)!!.name)
        assertEquals("L", com.yehsung.aingcheck.character.render.ImpostorRenderer.chooseTier(f, 250.0)!!.name)
        assertEquals("L", com.yehsung.aingcheck.character.render.ImpostorRenderer.chooseTier(f, 900.0)!!.name, "U 는 울트라 전용")
        assertEquals("U", com.yehsung.aingcheck.character.render.ImpostorRenderer.chooseTier(f, 700.0, allowUltra = true)!!.name)
    }
}
