// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (renderGolden — 같은 엔진 · 같은 시각 순서를 재생기 API 로 다시 밟는다)
package com.yehsung.aingcheck.character.parity

import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.player.WakeKind
import com.yehsung.aingcheck.character.pose.NodeChain
import com.yehsung.aingcheck.character.pose.PoseImpostor
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.ImageDiff
import com.yehsung.aingcheck.character.render.ImageMetrics
import com.yehsung.aingcheck.character.render.ImpostorFrame
import com.yehsung.aingcheck.character.render.ImpostorRenderer
import com.yehsung.aingcheck.character.render.RasterFactory
import com.yehsung.aingcheck.character.render.RgbaImage
import kotlin.math.ceil
import kotlin.math.floor

/**
 * 골든 한 장을 **재생기 공개 API 로** 다시 밟는다(모양 말고 결과 — 행렬을 시험 쪽에서 다시 짓지 않는다):
 *  - 리액션: `play(name)` 을 T0 에, 자세는 T0 + 표본/480
 *  - 졸기: `beginSleep()`, 깨기: 졸기 끝까지 기다린 뒤 `wake(startled|quiet)` (맥 순서: sinkSteps = ⌈2.0·480⌉ + 2, 그다음 칸에서 깨운다)
 *  - 깜빡임: `setEyesClosed(true)`, idle 은 표본 480(1.0s)
 *  - 바라보기: `setFacing(±1)`, 살랑 위상: 캐릭터를 단 시각 S 와 T0 사이를 위상 초로 둔다
 */
object GoldenReplay {
    const val HZ = 480

    class Replayed(val player: CharacterPlayer, val now: Double) {
        val chain: NodeChain get() = player.chain(now)
    }

    fun replay(library: BakeLibrary, g: Golden): Replayed {
        val serverId = BakeLibrary.FOLDER_IDS.getValue(g.finishFolder)
        val attach = 10.0
        val player = CharacterPlayer(library, initialCharacterId = serverId, now = 0.0)
        player.swapCharacter(serverId, attach)          // idle 위상 0 = attach
        val phaseSteps = roundHalfAway(g.swayPhaseS * HZ)
        val t0 = attach + phaseSteps / HZ.toDouble()
        val dir = when { g.facingDeg > 0 -> 1; g.facingDeg < 0 -> -1; else -> 0 }
        when (g.reaction) {
            "idle" -> {}
            "blink" -> player.setEyesClosed(true)
            "drowsy" -> check(player.beginSleep(t0)) { "졸기 시작 실패" }
            "wake", "quietRise" -> {
                val sinkSeconds = library.motion.reaction(CharacterPlayer.DROWSY)?.motionDurationS ?: error("drowsy 표 없음")
                val sinkSteps = ceil(sinkSeconds * HZ).toInt() + 2
                val ts = t0 - (sinkSteps + 1) / HZ.toDouble()
                check(player.beginSleep(ts)) { "졸기 시작 실패" }
                player.wrapperPose(t0) // 끝 자세를 쥐게(맥: 그 칸까지 시계를 민다)
                check(player.wake(if (g.reaction == "wake") WakeKind.startled else WakeKind.quiet, t0)) { "깨기 실패" }
            }
            else -> check(player.play(g.reaction, t0)) { "리액션 ${g.reaction} 재생 실패" }
        }
        player.setFacing(dir, moving = false, now = t0)
        return Replayed(player, t0 + g.sampleIndex / HZ.toDouble())
    }

    /** Swift `.rounded()`(0.5 는 0 에서 먼 쪽). */
    fun roundHalfAway(x: Double): Int = if (x >= 0) floor(x + 0.5).toInt() else -floor(-x + 0.5).toInt()

    /** 이 골든의 S 단 프레임(280×340). */
    fun plan(library: BakeLibrary, g: Golden, body: Mat4 = replay(library, g).chain.character): ImpostorFrame {
        val finish = library.finish(BakeLibrary.FOLDER_IDS.getValue(g.finishFolder)) ?: error("마감 없음 ${g.finishFolder}")
        val tier = finish.bake.tier("S") ?: error("S 단 없음")
        return ImpostorRenderer.plan(library, finish, tier, body, g.eyesClosed, 280.0, 340.0) ?: error("정합 실패 ${g.id}")
    }

    /** 프레임 → 래스터(투명 바탕). */
    fun render(raster: RasterFactory, frame: ImpostorFrame, store: BakeImageStore, drawHalo: Boolean = true): RgbaImage {
        val surface = raster.newSurface(frame.viewportWidth.toInt(), frame.viewportHeight.toInt())
        try {
            surface.clear()
            ImpostorRenderer.draw(surface, frame, store, drawHalo)
            return surface.readPixels()
        } finally {
            surface.close()
        }
    }

    fun diff(rendered: RgbaImage, golden: RgbaImage): ImageDiff = ImageMetrics.diff(rendered, golden)

    /**
     * 골든 한 장의 판정(T3 · T7 공용): 재생기로 다시 밟아 S 단 280×340 을 그리고(후광 → 몸), 골든과 맞댄다.
     * 음성 대조로 같은 자세에 요 격자 두 칸 옆 칸을 넣어 같은 판을 다시 잰다.
     * @param golden 골든 바이트를 곱하지 않고 디코드해 프리멀티로 읽은 것.
     */
    fun verdict(library: BakeLibrary, raster: RasterFactory, store: BakeImageStore, g: Golden, golden: RgbaImage): ParityRules.Verdict {
        val body = replay(library, g).chain.character
        val frame = plan(library, g, body)
        val ours = render(raster, frame, store)
        val oursBody = render(raster, frame, store, drawHalo = false)
        val wrong = wrongCell(frame.finish, frame)
        val plane = PoseImpostor.Plane(PoseImpostor.limbDepth(library.camera), frame.tier.viewportWidth.toDouble(), frame.tier.viewportHeight.toDouble())
        val wp = PoseImpostor.placeWith(wrong, body, library.camera, frame.finish.bake.quadHalfUnits, frame.viewportWidth, frame.viewportHeight, plane)
            ?: error("틀린 칸 정합 실패 ${g.id}")
        val wf = frame.copy(placement = wp)
        val wrongImg = render(raster, wf, store)
        val wrongBody = render(raster, wf, store, drawHalo = false)
        return ParityRules.Verdict(
            golden = g,
            cls = ParityRules.classify(g, golden),
            band = ParityRules.band(g, frame.placement.cell),
            cellId = frame.placement.cell.id,
            composite = diff(ours, golden),
            bodyMean = ParityRules.bodyRegionMean(ours, golden, oursBody),
            wrongCellId = wrong.id,
            wrongComposite = diff(wrongImg, golden),
            wrongBodyMean = ParityRules.bodyRegionMean(wrongImg, golden, wrongBody),
        )
    }

    /**
     * 음성 대조용 "틀린 칸"(F §6 시험 규율): 같은 기울기 줄에서 요가 **격자 두 칸 옆**인 칸. 줄 끝이면 반대쪽.
     */
    fun wrongCell(finish: BakedFinish, frame: ImpostorFrame): com.yehsung.aingcheck.character.bake.BakeCell {
        val cells = finish.cells(frame.tier.name)!!.cells.filter { it.group == frame.placement.cell.group && it.tiltDeg == frame.placement.cell.tiltDeg && (!frame.closedEyes || it.closedPatch != null) }
            .sortedBy { it.yawDeg }
        val i = cells.indexOfFirst { it.id == frame.placement.cell.id }
        return cells.getOrNull(i + 2) ?: cells.getOrNull(i - 2) ?: error("두 칸 옆이 없다: ${frame.placement.cell.id}")
    }
}
