// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (renderGolden — 같은 엔진 · 같은 시각 순서를 재생기 API 로 다시 밟는다)
package com.yehsung.aingcheck.character.parity

import com.yehsung.aingcheck.character.bake.BakeCell
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

    /** T7 부분집합(골든 번호, 기기 S 단): 아잉 12(네 무리 · 감은 눈 2) · 황금 5 · 무지개 3 — 전부 [GoldenClass.clean](데스크톱 T3 가 잰다). */
    val T7_SUBSET: Set<Int> = setOf(0, 6, 12, 18, 27, 30, 36, 54, 60, 66, 72, 78, 86, 92, 134, 152, 158, 166, 214, 232)

    /**
     * T7-L 부분집합(골든 번호, 기기 L 단 — Android 기본 묶음이 싣는 단): 참조 칸이 쉬는 행인 깨끗한 장 14 — 세 마감 · 강체(idle · 깨기 · 조용한 기상) ·
     * 찌부(hit · 울트라 충전 1.22배) · 감은 눈(졸기 · 깜빡임). 다시 구운 골든(조정자 패치 02)에서도 깨끗하다(입자 창 밖). 데스크톱 T3-L 이 같은 판정을 잰다.
     */
    val T7_L_SUBSET: Set<Int> = setOf(3, 51, 54, 72, 78, 84, 133, 143, 152, 158, 163, 214, 231, 232)

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

    /**
     * 이 골든의 프레임(280×340). [tierName] 기본은 골든과 같은 S 단, "L" 이면 Android 기본 묶음이 싣는 L 단을 **같은 280×340 몸 크기로** 그린다
     * (L 은 쉬는 행 57칸뿐 — 쉬는 행 골든만 맞댄다).
     */
    fun plan(library: BakeLibrary, g: Golden, body: Mat4 = replay(library, g).chain.character, tierName: String = "S"): ImpostorFrame {
        val finish = library.finish(BakeLibrary.FOLDER_IDS.getValue(g.finishFolder)) ?: error("마감 없음 ${g.finishFolder}")
        val tier = finish.bake.tier(tierName) ?: error("$tierName 단 없음")
        return ImpostorRenderer.plan(library, finish, tier, body, g.eyesClosed, 280.0, 340.0) ?: error("정합 실패 ${g.id}")
    }

    /**
     * 골든이 적은 Swift 참조 칸(S 단, 골든 쪽 사실 — `referenceCell`). 판정 무리는 이 칸으로 가른다: 재생기가 고른 칸으로 가르면
     * 칸 고르기 결함이 무리를 바꿔 스스로 문턱을 고른다(T2 가 둘이 같음을 따로 잰다).
     */
    fun referenceCell(library: BakeLibrary, g: Golden): BakeCell {
        val finish = library.finish(BakeLibrary.FOLDER_IDS.getValue(g.finishFolder)) ?: error("마감 없음 ${g.finishFolder}")
        return finish.cells("S")?.cell(g.referenceCellId) ?: error("참조 칸 ${g.referenceCellId} 이 S 단에 없다")
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
    fun verdict(library: BakeLibrary, raster: RasterFactory, store: BakeImageStore, g: Golden, golden: RgbaImage, tierName: String = "S"): ParityRules.Verdict {
        val body = replay(library, g).chain.character
        val frame = plan(library, g, body, tierName)
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
            band = ParityRules.band(g, referenceCell(library, g)),
            tier = frame.tier.name,
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
    fun wrongCell(finish: BakedFinish, frame: ImpostorFrame): BakeCell {
        val cells = finish.cells(frame.tier.name)!!.cells.filter { it.group == frame.placement.cell.group && it.tiltDeg == frame.placement.cell.tiltDeg && (!frame.closedEyes || it.closedPatch != null) }
            .sortedBy { it.yawDeg }
        val i = cells.indexOfFirst { it.id == frame.placement.cell.id }
        return cells.getOrNull(i + 2) ?: cells.getOrNull(i - 2) ?: error("두 칸 옆이 없다: ${frame.placement.cell.id}")
    }
}
