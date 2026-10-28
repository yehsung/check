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

    /** 왼쪽 절반 알파 [left] · 오른쪽 절반 [right] 인 w×h 그림(직선 알파, 흰색). */
    private fun halves(w: Int, h: Int, left: Int, right: Int): RgbaImage {
        val px = ByteArray(w * h * 4)
        for (y in 0 until h) for (x in 0 until w) {
            val o = (y * w + x) * 4
            px[o] = 0xFF.toByte(); px[o + 1] = 0xFF.toByte(); px[o + 2] = 0xFF.toByte()
            px[o + 3] = (if (x < w / 2) left else right).toByte()
        }
        return RgbaImage(w, h, px, false)
    }

    @Test
    fun 마스크_임계값_아래_알파는_투명으로_본다() {
        // V0316CharacterCoreTests.마스크_임계값_아래_알파는_투명으로_본다 이식(알파 20 · 200, 임계 32 · 8).
        val atlas = halves(8, 8, 20, 200)
        val low = assertNotNull(SpriteAlphaMask.of(atlas, threshold = 32))
        assertFalse(low.isOpaque(0.1, 0.5), "알파 20 은 임계값 32 아래라 투명")
        assertTrue(low.isOpaque(0.9, 0.5))
        val permissive = assertNotNull(SpriteAlphaMask.of(atlas, threshold = 8))
        assertTrue(permissive.isOpaque(0.1, 0.5), "임계값을 낮추면 알파 20 도 몸이다")
        // 기본 임계(32 — SpriteAlphaMask.swift:32 · F §5.3)의 양쪽: 32 는 투명(`alpha > threshold`), 33 은 불투명.
        val edge = assertNotNull(SpriteAlphaMask.of(halves(8, 8, 32, 33)))
        assertFalse(edge.isOpaque(0.1, 0.5), "알파 32 = 임계 — 투명")
        assertTrue(edge.isOpaque(0.9, 0.5), "알파 33 — 불투명")
    }

    /** frontIdle(가로 100×80) 과 걷기 프레임(세로 60×100 · 정사각 90×90)의 크기가 다른 합성 스프라이트. 왼쪽 절반 알파 20 · 오른쪽 33. */
    private fun syntheticSprite(): SpriteRuntime {
        val json = """
            {"id": "w5atest", "displayName": "시험", "kind": "sprite",
             "atlas": {"file": "atlas.png", "width": 400, "height": 100, "states": {
               "frontIdle": {"frames": [{"x": 0, "y": 0, "w": 100, "h": 80}], "durationsMs": [1000], "loop": true},
               "sideIdle": {"frames": [{"x": 100, "y": 0, "w": 100, "h": 80}], "durationsMs": [1000], "loop": true},
               "sideWalk": {"frames": [{"x": 200, "y": 0, "w": 60, "h": 100}, {"x": 300, "y": 0, "w": 90, "h": 90}], "durationsMs": [140, 140], "loop": true}
             }},
             "portrait": {"neutral": "portrait-neutral.png", "negative": "portrait-negative.png"}, "pixelArt": false}
        """.trimIndent()
        val manifest = CharacterManifest.decode(json)
        // 프레임마다 왼쪽 절반 알파 20 · 오른쪽 절반 33(프레임 국소 기준).
        val w = 400; val h = 100
        val px = ByteArray(w * h * 4)
        for (state in manifest.atlas!!.states.values) for (f in state.frames) {
            for (y in f.y.toInt() until (f.y + f.h).toInt()) for (x in f.x.toInt() until (f.x + f.w).toInt()) {
                val o = (y * w + x) * 4
                px[o + 3] = (if (x - f.x < f.w / 2) 20 else 33).toByte()
            }
        }
        val atlas = RgbaImage(w, h, px, false)
        return assertNotNull(SpriteRuntime.make(manifest, w, h, SpriteAlphaMask.of(atlas, manifest.atlas!!.states)))
    }

    @Test
    fun 걷는_동안_평면_크기는_frontIdle_첫_프레임_그대로다() {
        // INV-SpriteCharacterNode-0d867c0f: 부르는 자리(CharacterFrames.compute)가 현재 프레임 크기로 평면을 다시 재면 걷는 동안
        // 캐릭터가 커졌다 작아진다. 저장소 스프라이트 6종은 프레임 크기가 모두 같아 이 결함을 못 드러내므로 합성 매니페스트로 잰다.
        val rt = syntheticSprite()
        val p = CharacterPlayer(RepoBake.library, spriteFor = { if (it == "w5atest") rt else null }, initialCharacterId = "w5atest")
        val front = assertNotNull(CharacterFrames.compute(p, 1.0, 280.0, 340.0)) as CharacterFrame.Sprite
        assertEquals(com.yehsung.aingcheck.character.bake.PixelRect(0, 0, 100, 80), front.frameRect)
        p.setFacing(1, moving = true, now = 2.0)
        assertEquals(CharacterManifest.StateKey.sideWalk, rt.stateKey)
        val seen = HashSet<com.yehsung.aingcheck.character.bake.PixelRect>()
        for (k in 0 until 6) {
            val now = 2.0 + k * 0.07
            p.setFacing(1, moving = true, now = now)
            p.tickSprite(now)
            // 사슬 시각(idle 부유 · 살랑)은 1.0 에 묶어 둔다 — 바뀌는 것은 스프라이트 프레임뿐이어야 평면 크기만 잰다.
            val f = assertNotNull(CharacterFrames.compute(p, 1.0, 280.0, 340.0)) as CharacterFrame.Sprite
            seen += f.frameRect
            for (i in 0 until 4) {
                assertEquals(front.viewportQuad[i].x, f.viewportQuad[i].x, 1e-9, "걷기 프레임 ${f.frameRect} 에서 평면이 바뀌었다")
                assertEquals(front.viewportQuad[i].y, f.viewportQuad[i].y, 1e-9)
            }
        }
        assertEquals(setOf(com.yehsung.aingcheck.character.bake.PixelRect(200, 0, 60, 100), com.yehsung.aingcheck.character.bake.PixelRect(300, 0, 90, 90)), seen, "걷기 두 프레임을 모두 탔다")
    }

    @Test
    fun 스프라이트_클릭은_현재_프레임의_알파_임계로_가른다() {
        val rt = syntheticSprite()
        val p = CharacterPlayer(RepoBake.library, spriteFor = { if (it == "w5atest") rt else null }, initialCharacterId = "w5atest")
        val f = assertNotNull(CharacterFrames.compute(p, 1.0, 280.0, 340.0)) as CharacterFrame.Sprite
        fun at(u: Double, v: Double): Vec2 = f.planeToViewport.map(Vec2(u, v))
        // 평면 왼쪽 1/4 = 알파 20(임계 32 아래 — 몸이 아니다), 오른쪽 3/4 = 알파 33(몸).
        assertFalse(CharacterFrames.hitTest(f, at(0.25, 0.5), 24.0) { error("구운 마감 아님") }, "알파 20")
        assertTrue(CharacterFrames.hitTest(f, at(0.75, 0.5), 24.0) { error("구운 마감 아님") }, "알파 33")
        // 미러(왼쪽을 보면 좌우가 바뀐다 — atlasUV 를 거친다).
        p.setFacing(-1, moving = false, now = 2.0)
        val m = assertNotNull(CharacterFrames.compute(p, 2.0, 280.0, 340.0)) as CharacterFrame.Sprite
        assertTrue(m.mirrored)
        assertTrue(CharacterFrames.hitTest(m, m.planeToViewport.map(Vec2(0.25, 0.5)), 24.0) { error("구운 마감 아님") }, "미러: 평면 왼쪽 = 그림 오른쪽(알파 33)")
        assertFalse(CharacterFrames.hitTest(m, m.planeToViewport.map(Vec2(0.75, 0.5)), 24.0) { error("구운 마감 아님") }, "미러: 평면 오른쪽 = 그림 왼쪽(알파 20)")
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
    fun 평면_크기는_최장변을_목표_길이로_맞춘다() {
        // 시바 frontIdle 567×516(가로가 길다) → 너비 = 1.9210, 높이 = 1.9210 × 516/567. 세로가 긴 프레임은 높이가 목표 길이.
        val (w, h) = SpritePlane.planeSize(runtime("shiba").manifest)!!
        assertEquals(SpritePlane.TARGET_EXTENT, w, 1e-12)
        assertEquals(SpritePlane.TARGET_EXTENT * 516 / 567, h, 1e-12)
        val (tw, th) = SpritePlane.planeSize(CharacterManifest.Rect(0, 0, 60, 100))
        assertEquals(SpritePlane.TARGET_EXTENT * 60 / 100, tw, 1e-12); assertEquals(SpritePlane.TARGET_EXTENT, th, 1e-12)
        // 걷는 동안 평면이 그대로인지(INV-SpriteCharacterNode-0d867c0f)는 부르는 자리에서 잰다: 걷는_동안_평면_크기는_frontIdle_첫_프레임_그대로다.
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
