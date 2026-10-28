// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (spawnZzzBurst · ReactionActions.makeZNode, :1531-1557 · :2081-2099) — 굽기가 녹화한 tracks/zzz.f32 를 재생한다
package com.yehsung.aingcheck.character.player

import com.yehsung.aingcheck.character.bake.MotionLibrary
import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.bake.SceneCamera
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.character.render.DrawableImage
import com.yehsung.aingcheck.character.render.QuadCanvas
import kotlin.math.floor

/**
 * 💤 버스트 한 번(Z 3개). 트랙 배치 `float32le[count][3][4]` = 위치 xyz(extent 단위, 컨테이너 국소) · 불투명도(−1 = 노드 제거).
 * 컨테이너는 씬 루트의 (0.3e, 0.25e, 0.1e) — 몸을 따라가지 않는다(F §1.3). 졸기 동안 3.5초마다 한 번(엔진 몫 — 이 층은 한 버스트만 안다).
 */
class ZzzTrack(private val data: FloatArray, val sampleHz: Int, val container: Vec3, val zScaleExtent: Double) {
    val count: Int = data.size / 12

    init {
        require(data.size % 12 == 0 && count > 0) { "zzz 트랙 배치가 아니다(${data.size})" }
    }

    /** 노드 k(0..2)의 시각 t 상태: (컨테이너 국소 위치(extent 단위), 불투명도). 제거됐으면 null. */
    fun node(k: Int, t: Double): Pair<Vec3, Double>? {
        val i = floor(t * sampleHz).toInt()
        if (i < 0 || i >= count) return null
        val o = (i * 3 + k) * 4
        val opacity = data[o + 3].toDouble()
        if (opacity < 0) return null
        return Vec3(data[o].toDouble(), data[o + 1].toDouble(), data[o + 2].toDouble()) to opacity
    }

    val durationS: Double get() = count.toDouble() / sampleHz

    companion object {
        fun of(motion: MotionLibrary, bytes: ByteArray): ZzzTrack {
            require(bytes.size % 4 == 0)
            val floats = FloatArray(bytes.size / 4) { i ->
                val b = i * 4
                Float.fromBits(
                    (bytes[b].toInt() and 0xFF) or ((bytes[b + 1].toInt() and 0xFF) shl 8) or
                        ((bytes[b + 2].toInt() and 0xFF) shl 16) or ((bytes[b + 3].toInt() and 0xFF) shl 24),
                )
            }
            val t = ZzzTrack(floats, motion.sampleHz, motion.zzzContainerExtent, motion.zzzScaleExtent)
            require(t.count == motion.zzzCount) { "zzz 표본 ${t.count} ≠ 메타 ${motion.zzzCount}" }
            return t
        }
    }
}

/**
 * 💤 글리프 판 놓기: 글리프 그림(512², 프리멀티)의 위-왼쪽이 Z 노드 국소 [imageTopLeftLocal], 픽셀 하나 = [unitsPerPixel] 국소 단위.
 * 이 값은 굽기 보고(`reports.glyph`)에만 있고 자산 묶음에는 아직 없다 — 굽기가 motion.json 에 싣기 전까지 앱은 💤 를 그리지 않는다.
 */
data class GlyphPlacement(val imageTopLeftLocal: Vec2, val unitsPerPixel: Double)

object ZzzLayer {
    /** 버스트 시작 t 초 뒤 💤 를 그린다. 판은 카메라 정렬(정면 정사영으로 구운 글리프). */
    fun draw(
        canvas: QuadCanvas,
        track: ZzzTrack,
        t: Double,
        extent: Double,
        glyph: DrawableImage,
        placement: GlyphPlacement,
        camera: SceneCamera,
        viewportWidth: Double,
        viewportHeight: Double,
    ) {
        val right = camera.world.column(0).normalized(); val up = camera.world.column(1).normalized()
        val scale = track.zScaleExtent * extent
        for (k in 0 until 3) {
            val (local, opacity) = track.node(k, t) ?: continue
            if (opacity <= 0) continue
            val origin = (track.container + local) * extent
            val w = glyph.width * placement.unitsPerPixel * scale
            val h = glyph.height * placement.unitsPerPixel * scale
            val tl = origin + right * (placement.imageTopLeftLocal.x * scale) + up * (placement.imageTopLeftLocal.y * scale)
            val corners = listOf(tl, tl + right * w, tl + right * w - up * h, tl - up * h)
                .map { camera.project(it, viewportWidth, viewportHeight) }
            val hmg = Homography.fromQuads(
                listOf(Vec2(0.0, 0.0), Vec2(glyph.width.toDouble(), 0.0), Vec2(glyph.width.toDouble(), glyph.height.toDouble()), Vec2(0.0, glyph.height.toDouble())),
                corners,
            ) ?: continue
            canvas.drawImageQuad(glyph, PixelRect(0, 0, glyph.width, glyph.height), hmg, alpha = opacity.toFloat())
        }
    }
}
