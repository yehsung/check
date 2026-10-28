// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (몸 클릭 hitTest — 투영 bbox + 12pt 거르기 :1398-1430, 스프라이트는 atlasUV 를 거친 알파) + 설계 F §5.3
package com.yehsung.aingcheck.character.player

import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.bake.SceneCamera
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.DrawableImage
import com.yehsung.aingcheck.character.render.ImpostorFrame
import com.yehsung.aingcheck.character.render.ImpostorRenderer
import com.yehsung.aingcheck.character.render.QuadCanvas
import com.yehsung.aingcheck.character.sprite.SpritePlane
import com.yehsung.aingcheck.character.sprite.SpriteRuntime

/** 한 프레임에 그릴 것(순수 기하). */
sealed interface CharacterFrame {
    val characterId: String
    val viewportQuad: List<Vec2>

    class Impostor(val frame: ImpostorFrame) : CharacterFrame {
        override val characterId: String get() = frame.finish.characterId
        override val viewportQuad: List<Vec2> get() = frame.placement.viewportQuad
    }

    class Sprite(
        override val characterId: String,
        val runtime: SpriteRuntime,
        val frameRect: PixelRect,
        val mirrored: Boolean,
        override val viewportQuad: List<Vec2>,
        /** 아틀라스 픽셀 → 뷰포트(미러 포함). 그리기. */
        val atlasToViewport: Homography,
        /** 평면 UV(0..1, TL 원점) → 뷰포트. 히트(atlasUV 를 거치려고). */
        val planeToViewport: Homography,
        val pixelArt: Boolean,
    ) : CharacterFrame
}

object CharacterFrames {
    /** 오버레이 2x(280×340) 뷰포트에서 몸 높이(px) — 단 고르기의 기준(S 단 bodyPxMedian). */
    const val REFERENCE_BODY_PX = 178.0
    const val REFERENCE_VIEWPORT_HEIGHT = 340.0

    /**
     * 플레이어 상태 → 프레임. 뷰포트가 크면(같은 구도를 크게) 큰 단을 고른다: 몸 px ≈ 178 × 높이/340.
     * @param tierName 단을 직접 고를 때(시험 · 울트라). null 이면 몸 크기로.
     */
    fun compute(player: CharacterPlayer, now: Double, viewportWidth: Double, viewportHeight: Double, tierName: String? = null): CharacterFrame? {
        val chain = player.chain(now)
        return when (val c = player.character) {
            is ResolvedCharacter.Baked -> {
                val finish: BakedFinish = c.finish
                val tier = tierName?.let { finish.bake.tier(it)?.takeIf { t -> finish.cells(t.name) != null } }
                    ?: ImpostorRenderer.chooseTier(finish, REFERENCE_BODY_PX * viewportHeight / REFERENCE_VIEWPORT_HEIGHT)
                    ?: return null
                val f = ImpostorRenderer.plan(player.library, finish, tier, chain.character, player.eyesClosedAt(now), viewportWidth, viewportHeight)
                    ?: return null
                CharacterFrame.Impostor(f)
            }
            is ResolvedCharacter.Sprite -> {
                val rt = c.runtime
                val size = SpritePlane.planeSize(rt.manifest) ?: return null
                // 스프라이트 씬의 카메라는 그 평면 bbox 로 지은 맥 `addFramingCamera` 다(아잉 camera.json 이 아니다 — 깊이 0 이라 더 가깝다).
                val camera = SceneCamera.framing(Vec3(-size.first / 2, -size.second / 2, 0.0), Vec3(size.first / 2, size.second / 2, 0.0))
                val quad = SpritePlane.localCorners(size).map { camera.project(chain.character.transformPoint(it), viewportWidth, viewportHeight) }
                val frame = rt.currentFrame
                val rect = PixelRect(frame.x.toInt(), frame.y.toInt(), frame.w.toInt(), frame.h.toInt())
                val atlasH = Homography.fromQuads(SpritePlane.frameCorners(frame, rt.mirrored), quad) ?: return null
                val planeH = Homography.fromQuads(UNIT_SQUARE, quad) ?: return null
                CharacterFrame.Sprite(c.id, rt, rect, rt.mirrored, quad, atlasH, planeH, c.pixelArt)
            }
        }
    }

    private val UNIT_SQUARE = listOf(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(1.0, 1.0), Vec2(0.0, 1.0))

    /**
     * 그린다. 구운 아잉이는 [storeFor] 의 칸 · 후광, 스프라이트는 [spriteAtlas] 의 아틀라스(직선 알파 PNG/WebP 를 플랫폼이 곱한 그림).
     */
    fun draw(
        canvas: QuadCanvas,
        frame: CharacterFrame,
        storeFor: (BakedFinish) -> BakeImageStore,
        spriteAtlas: (String) -> DrawableImage?,
        drawHalo: Boolean = true,
    ) {
        when (frame) {
            is CharacterFrame.Impostor -> ImpostorRenderer.draw(canvas, frame.frame, storeFor(frame.frame.finish), drawHalo)
            is CharacterFrame.Sprite -> {
                val atlas = spriteAtlas(frame.characterId) ?: return
                canvas.drawImageQuad(atlas, frame.frameRect, frame.atlasToViewport, linear = !frame.pixelArt)
            }
        }
    }

    /**
     * 몸 클릭 판정(F §5.3). 투영 사각형 bbox + [marginPx](맥 12pt × 배율)로 먼저 거르고, 통과하면 H⁻¹ 로 칸(스프라이트는 평면 UV → atlasUV)을
     * 찾아 알파 > 32 인지 본다. 후광은 몸이 아니라 빠진다.
     */
    fun hitTest(frame: CharacterFrame, point: Vec2, marginPx: Double, storeFor: (BakedFinish) -> BakeImageStore): Boolean {
        val q = frame.viewportQuad
        if (point.x < q.minOf { it.x } - marginPx || point.x > q.maxOf { it.x } + marginPx ||
            point.y < q.minOf { it.y } - marginPx || point.y > q.maxOf { it.y } + marginPx
        ) return false
        return when (frame) {
            is CharacterFrame.Impostor -> {
                val f = frame.frame
                val inv = f.placement.cellToViewport.inverse()
                if (inv.denominator(point) <= 0) return false
                val p = inv.map(point)
                val mask = storeFor(f.finish).cellMask(f.placement.cell, f.closedEyes)
                mask.isOpaque(kotlin.math.floor(p.x).toInt(), kotlin.math.floor(p.y).toInt())
            }
            is CharacterFrame.Sprite -> {
                val inv = frame.planeToViewport.inverse()
                if (inv.denominator(point) <= 0) return false
                val uv = inv.map(point)
                if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1) return false
                // ★ atlasUV 를 반드시 거친다 — runtime.isOpaque 가 현재 프레임 · 미러를 먹인다(INV-SpriteAlphaMask-67fc2c0d 규약 그대로).
                frame.runtime.isOpaque(uv.x, uv.y)
            }
        }
    }
}
