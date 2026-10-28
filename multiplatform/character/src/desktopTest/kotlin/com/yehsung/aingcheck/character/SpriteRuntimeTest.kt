// 원본: Tests/checkTests/V0316CharacterCoreTests.swift · V0316OverlaySpriteTests.swift @ 1b8260d (SpriteRuntime · SpriteAlphaMask · SpriteCharacterNode 규약을 Kotlin 판에 맞댄다)
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.player.CharacterFrames
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.player.ResolvedCharacter
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.RgbaImage
import com.yehsung.aingcheck.character.sprite.SpriteAlphaMask
import com.yehsung.aingcheck.character.sprite.SpritePlane
import com.yehsung.aingcheck.character.sprite.SpriteRuntime
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SpriteRuntimeTest {
    private val charactersDir = File(RepoBake.repoRoot, "Sources/check/Characters")

    private fun runtime(id: String): SpriteRuntime {
        val manifest = CharacterManifest.decode(File(charactersDir, "$id/manifest.json").readText())
        val atlas = PlatformRaster.decodeRaw(File(charactersDir, "$id/${manifest.atlas!!.file}").readBytes())
        return assertNotNull(SpriteRuntime.make(manifest, atlas.width, atlas.height, SpriteAlphaMask.of(atlas, manifest.atlas!!.states)))
    }

    /** 위 절반만 불투명한 4×4 비대칭 그림(INV-SpriteAlphaMask-67fc2c0d — 대칭 그림으로는 두 UV 규약이 구별되지 않는다). */
    private fun topHalfOpaque(): RgbaImage {
        val px = ByteArray(4 * 4 * 4)
        for (y in 0 until 2) for (x in 0 until 4) px[(y * 4 + x) * 4 + 3] = 0xFF.toByte()
        return RgbaImage(4, 4, px, false)
    }

    @Test
    fun UV_규약은_py_가_v_곱하기_높이이고_뒤집지_않는다() {
        val mask = assertNotNull(SpriteAlphaMask.of(topHalfOpaque()))
        assertTrue(mask.isOpaque(0.5, 0.172), "v 작음 = 그림 위쪽 = 불투명")
        assertFalse(mask.isOpaque(0.5, 0.828), "v 큼 = 그림 아래쪽 = 투명")
        assertTrue(mask.isOpaque(-3.0, -1.0), "범위 밖은 가장자리로 물린다")
        assertFalse(mask.isOpaque(Double.NaN, 0.1))
    }

    @Test
    fun 매니페스트와_그림_크기가_다르면_런타임이_없다() {
        val manifest = CharacterManifest.decode(File(charactersDir, "shiba/manifest.json").readText())
        val atlas = PlatformRaster.decodeRaw(File(charactersDir, "shiba/atlas.png").readBytes())
        assertNull(SpriteRuntime.make(manifest, atlas.width + 1, atlas.height, SpriteAlphaMask.of(atlas)))
        assertNull(SpriteAlphaMask.of(topHalfOpaque(), manifest.atlas!!.states), "프레임이 그림 밖이면 마스크가 없다")
    }

    @Test
    fun 같은_상태_재요청은_프레임을_되돌리지_않고_없는_상태는_frontIdle_로_접는다() {
        val rt = runtime("shiba")
        rt.setState(CharacterManifest.StateKey.sideWalk, mirrored = false, now = 0.0)
        assertTrue(rt.tick(0.15))
        assertEquals(1, rt.frameIndex)
        rt.setState(CharacterManifest.StateKey.sideWalk, mirrored = false, now = 0.2) // 드래그가 같은 방향을 다시 준다
        assertEquals(1, rt.frameIndex, "no-op 가드 — 0 으로 리셋되면 영원히 첫 프레임")
        assertFalse(rt.tick(0.2))
        rt.setState("noSuchState", mirrored = true, now = 1.0)
        assertEquals(CharacterManifest.StateKey.frontIdle, rt.stateKey, "폴백은 접힌 결과값")
        assertTrue(rt.mirrored)
    }

    @Test
    fun 평면_크기는_frontIdle_첫_프레임으로_한_번만() {
        val m = runtime("shiba").manifest
        val (w, h) = SpritePlane.planeSize(m)!!
        assertEquals(SpritePlane.TARGET_EXTENT, w, 1e-12)
        assertEquals(SpritePlane.TARGET_EXTENT * 516 / 567, h, 1e-12)
        // INV-SpriteCharacterNode-0d867c0f: 걷기 프레임으로 바꿔도 평면 크기는 그대로 — 그리기는 frontIdle 크기 판을 쓴다.
        val walk = m.atlas!!.states.getValue(CharacterManifest.StateKey.sideWalk).frames[1]
        assertEquals(SpritePlane.planeSize(m), SpritePlane.planeSize(m.atlas!!.states.getValue(CharacterManifest.StateKey.frontIdle).frames[0]))
        assertTrue(walk.w > 0)
    }

    @Test
    fun 미러는_좌우_꼭짓점을_바꾸고_atlasUV_와_같은_식이다() {
        val f = CharacterManifest.Rect(100, 20, 50, 40)
        val normal = SpritePlane.frameCorners(f, mirrored = false)
        val mirror = SpritePlane.frameCorners(f, mirrored = true)
        assertEquals(Vec2(100.0, 20.0), normal[0]); assertEquals(Vec2(150.0, 20.0), mirror[0])
        // atlasUV(planeUV) × 크기 = 같은 꼭짓점.
        val uv = SpritePlane.atlasUV(0.0, 0.0, f, mirrored = true, atlasWidth = 400, atlasHeight = 100)
        assertEquals(Vec2(150.0 / 400, 20.0 / 100), uv)
    }

    @Test
    fun 스프라이트_재생기_평면판_트랙_걷기_멈춤_클릭() {
        val shiba = runtime("shiba")
        val p = CharacterPlayer(RepoBake.library, spriteFor = { if (it == "shiba") shiba else null }, initialCharacterId = "shiba")
        val c = p.character
        assertTrue(c is ResolvedCharacter.Sprite)
        assertEquals(0.0, p.facingDegrees(), "스프라이트는 facing 을 돌리지 않는다")
        // 평면판 트랙: commuteStart 동안 x · y 회전이 없다.
        assertTrue(p.play("commuteStart", 1.0))
        for (k in 0..60) {
            val q = p.wrapperPose(1.0 + k * 0.01).rotation
            assertTrue(kotlin.math.abs(q.x) < 1e-6 && kotlin.math.abs(q.y) < 1e-6, "평면판 $k")
        }
        // 걷기: 왼쪽으로 끌면 sideWalk + 미러, 0.18s 동안 이동이 없으면 sideIdle.
        p.setFacing(-1, moving = true, now = 2.0)
        assertEquals(CharacterManifest.StateKey.sideWalk, shiba.stateKey); assertTrue(shiba.mirrored)
        p.setFacing(-1, moving = true, now = 2.1) // 같은 방향 — 스탬프만
        p.tickSprite(2.25) // 0.15s 뒤 — 아직 걷는다(프레임만 진행할 수 있다)
        assertTrue(p.walking)
        assertTrue(p.tickSprite(2.4), "0.3s 이동 없음 → 멈춤")
        assertEquals(CharacterManifest.StateKey.sideIdle, shiba.stateKey)
        assertFalse(p.walking)

        // 그리기 · 클릭: 평면 투영 사각형, 몸 중심은 맞고 구석은 아니다.
        p.setFacing(0, moving = false, now = 3.0)
        val frame = assertNotNull(CharacterFrames.compute(p, 5.0, 280.0, 340.0)) as CharacterFrame.Sprite
        assertEquals(PixelRectOf(shiba.currentFrame), frame.frameRect)
        val center = Vec2(frame.viewportQuad.sumOf { it.x } / 4, frame.viewportQuad.sumOf { it.y } / 4 + 20)
        assertTrue(CharacterFrames.hitTest(frame, center, 24.0) { error("구운 마감 아님") })
        assertFalse(CharacterFrames.hitTest(frame, Vec2(1.0, 1.0), 24.0) { error("구운 마감 아님") })
        val surface = PlatformRaster.newSurface(280, 340)
        try {
            surface.clear()
            val atlas = PlatformRaster.decodeStraight(File(charactersDir, "shiba/atlas.png").readBytes())
            CharacterFrames.draw(surface, frame, { error("구운 마감 아님") }, { atlas })
            val img = surface.readPixels()
            val opaque = (0 until img.width * img.height).count { (img.px[it * 4 + 3].toInt() and 0xFF) > 200 }
            assertTrue(opaque > 5000, "스프라이트가 그려졌다: $opaque")
            atlas.close()
        } finally {
            surface.close()
        }
    }

    private fun PixelRectOf(r: CharacterManifest.Rect) = com.yehsung.aingcheck.character.bake.PixelRect(r.x.toInt(), r.y.toInt(), r.w.toInt(), r.h.toInt())
}
