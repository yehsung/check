// 원본: 없음 (설계 F §5.3 그리기 순서 — 노드 사슬 → 칸 → H → 후광 → 입자 뒤층 → 몸 칸(+감은 눈 패치) → 입자 앞층)
package com.yehsung.aingcheck.character.render

import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakeTier
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.pose.HaloLayer
import com.yehsung.aingcheck.character.pose.ImpostorPlacement
import com.yehsung.aingcheck.character.pose.PoseImpostor

/** 구운 아잉이 한 프레임(순수 기하 — 그림은 아직 없다). */
data class ImpostorFrame(
    val finish: BakedFinish,
    val tier: BakeTier,
    val placement: ImpostorPlacement,
    val closedEyes: Boolean,
    /** 후광(금 · 무지개만). 몸보다 먼저 그린다. */
    val halo: HaloLayer.Placement?,
    val viewportWidth: Double,
    val viewportHeight: Double,
)

object ImpostorRenderer {
    /**
     * 단 고르기(F §3.3): 화면 위 몸 크기(px)에 맞는 가장 작은 단, 없으면 가장 큰 단. 실린 단만 본다(Android 기본 묶음 = L 뿐).
     * @param bodyPx 이 뷰포트에서 몸이 차지할 대략의 높이(px). 오버레이 2x ≈ 178, 3x ≈ 266.
     */
    fun chooseTier(finish: BakedFinish, bodyPx: Double, allowUltra: Boolean = false): BakeTier? {
        val tiers = finish.availableTiers().filter { allowUltra || it.name != "U" }.sortedBy { it.bodyPxMedian }
        if (tiers.isEmpty()) return null
        return tiers.firstOrNull { it.bodyPxMedian >= bodyPx * 0.98 } ?: tiers.last()
    }

    /** 몸 world → 프레임. 감은 눈인데 패치 칸이 없는 단이면 뜬 눈으로 그린다(깜빡임 한 번 빠지는 것이 몸이 사라지는 것보다 낫다). */
    fun plan(
        library: BakeLibrary,
        finish: BakedFinish,
        tier: BakeTier,
        body: Mat4,
        closedEyes: Boolean,
        viewportWidth: Double,
        viewportHeight: Double,
    ): ImpostorFrame? {
        val selector = (if (closedEyes) finish.selector(tier.name, true) else null) ?: finish.selector(tier.name, false) ?: return null
        val closed = closedEyes && finish.selector(tier.name, true) != null
        val plane = PoseImpostor.Plane(PoseImpostor.limbDepth(library.camera), tier.viewportWidth.toDouble(), tier.viewportHeight.toDouble())
        val placement = PoseImpostor.place(body, library.camera, selector, finish.bake.quadHalfUnits, viewportWidth, viewportHeight, plane) ?: return null
        val halo = finish.bake.halo?.let { HaloLayer.place(body, library.camera, it, viewportWidth, viewportHeight) }
        return ImpostorFrame(finish, tier, placement, closed, halo, viewportWidth, viewportHeight)
    }

    /** 그림 네 모서리 → 사각형(TL · TR · BR · BL) 호모그래피. */
    fun imageToQuad(width: Int, height: Int, quad: List<Vec2>): Homography? = Homography.fromQuads(
        listOf(Vec2(0.0, 0.0), Vec2(width.toDouble(), 0.0), Vec2(width.toDouble(), height.toDouble()), Vec2(0.0, height.toDouble())),
        quad,
    )

    /** 후광 → 몸 칸 순으로 그린다(입자는 [com.yehsung.aingcheck.character.player.ParticleField] 가 앞뒤로 따로). */
    fun draw(canvas: QuadCanvas, frame: ImpostorFrame, store: BakeImageStore, drawHalo: Boolean = true) {
        if (drawHalo) drawHalo(canvas, frame, store)
        drawBody(canvas, frame, store)
    }

    fun drawHalo(canvas: QuadCanvas, frame: ImpostorFrame, store: BakeImageStore) {
        val halo = frame.halo ?: return
        val image = store.haloImage(halo.cell) ?: return
        val h = imageToQuad(image.width, image.height, halo.quad) ?: return
        canvas.drawImageQuad(image, BakeImageStore.full(image), h)
    }

    fun drawBody(canvas: QuadCanvas, frame: ImpostorFrame, store: BakeImageStore) {
        val image = store.cellImage(frame.placement.cell, frame.closedEyes)
        canvas.drawImageQuad(image, BakeImageStore.full(image), frame.placement.cellToViewport)
    }
}
