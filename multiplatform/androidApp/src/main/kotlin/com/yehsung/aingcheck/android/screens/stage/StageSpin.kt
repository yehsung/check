// 원본: 없음 (Android 전용 — 사용자 결정 G §8-19 #6② '뽑기 공개 = 한 바퀴' · F §8 B. 맥은 SceneKit 이 몸을 그대로 돌린다(commuteStart y 360°) — 무대는 구운 칸을 잇는다)
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakeTier
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.pose.CellSelector
import com.yehsung.aingcheck.character.pose.HaloLayer
import com.yehsung.aingcheck.character.pose.ImpostorPlacement
import com.yehsung.aingcheck.character.pose.PoseImpostor
import com.yehsung.aingcheck.character.render.ImpostorFrame
import kotlin.math.abs

/**
 * 무대의 한 바퀴(공개 반응 [StagePolicy.REVEAL_REACTION]). Android 기본 묶음(config.json bundles.androidDefault)은 L 단 쉬는 행
 * (요 −49…+49° · 기울기 13°)과 **S 단 스핀 행**(요 10° × 기울기 4° — 페이지 셋 + cells-S)만 싣는다. S 쉬는 행 · 띠 행 · 패치 페이지는 없다.
 * 한 바퀴 동안 칸은 **데운 칸 가운데 시선에 가장 가까운 칸**이다:
 *  - L: 데움이 굽는 정면 근처 쉬는 행(|요| ≤ [StagePolicy.PREWARM_YAW_DEG]) — 그 밖의 L 칸을 고르면 그리는 중에 20MB 페이지를 푼다.
 *  - S: 한 바퀴가 닿는 기울기 행의 스핀 칸 전부([prewarmCells]) — 등이 보이는 각을 L 화면 크기로 키워 그린다(공개 화면 크기 대조 — StageDeviceTest).
 * 같으면 L(더 고운 칸). 눈은 뜬다(리액션 중엔 깜빡임이 물러난다 · 스핀 칸엔 감은 눈 패치가 없다).
 */
class StageSpin(private val library: BakeLibrary, private val finish: BakedFinish) {
    private val lTier: BakeTier? = finish.bake.tier(StagePolicy.STAGE_TIER)
    private val sTier: BakeTier? = finish.bake.tier(StagePolicy.SPIN_TIER)
    private val lSelector: CellSelector? = finish.cells(StagePolicy.STAGE_TIER)?.cells.orEmpty()
        .filter { abs(it.yawDeg) <= StagePolicy.PREWARM_YAW_DEG }.takeIf { it.isNotEmpty() }?.let(::CellSelector)
    private val spinCells: List<BakeCell> = finish.cells(StagePolicy.SPIN_TIER)?.cells.orEmpty().filter { it.group == BakeCell.Group.spin }

    /**
     * 한 바퀴가 고를 수 있는 스핀 칸 = 닿는 기울기 행 전부(요는 360° 를 다 돈다). 행은 재생으로 정한다: 살랑 위상 [PHASES] 곳(0.3s 간격 —
     * 살랑 한 주기 14.4s 를 덮는다)에서 한 바퀴를 [SAMPLE_HZ] 로 재생해 스핀 칸 전부를 후보로 둔 같은 규칙이 고른 칸의 기울기(폴짝이 시선 기울기를
     * 13° → 6~10° 로 낮춘다 — 맥 골든 참조 칸 S:±170:6 · S:±30:10). 그리기 규칙은 이 집합 안에서만 고르므로 한 바퀴 동안 페이지를 풀 일이 없다.
     */
    val prewarmCells: List<BakeCell> by lazy {
        val all = spinCells.takeIf { it.isNotEmpty() }?.let(::CellSelector) ?: return@lazy emptyList()
        val duration = library.motion.reaction(StagePolicy.REVEAL_REACTION)?.durationS ?: return@lazy emptyList()
        val tilts = HashSet<Double>()
        for (k in 0 until PHASES) {
            val p = CharacterPlayer(library, initialCharacterId = finish.characterId, now = 0.0)
            val t0 = 10.0 + k * 0.3
            if (!p.play(StagePolicy.REVEAL_REACTION, t0)) return@lazy emptyList()
            for (i in 0..(duration * SAMPLE_HZ).toInt()) {
                val f = plan(p.chain(t0 + i / SAMPLE_HZ).character, 280.0, 340.0, all) ?: continue
                if (f.tier.name == StagePolicy.SPIN_TIER) tilts += f.placement.cell.tiltDeg
            }
        }
        spinCells.filter { it.tiltDeg in tilts }
    }

    private val spinSelector: CellSelector? by lazy { prewarmCells.takeIf { it.isNotEmpty() }?.let(::CellSelector) }

    /** 몸 world → 한 바퀴 프레임(데운 L 칸 · 데운 스핀 칸 중 가까운 칸). */
    fun plan(body: Mat4, viewportWidth: Double, viewportHeight: Double): ImpostorFrame? = plan(body, viewportWidth, viewportHeight, spinSelector)

    private fun plan(body: Mat4, w: Double, h: Double, spin: CellSelector?): ImpostorFrame? {
        val l = place(lTier, lSelector, body, w, h)
        val s = place(sTier, spin, body, w, h)
        val best = when {
            l == null -> s
            s == null -> l
            s.second.angleDeg < l.second.angleDeg -> s
            else -> l
        } ?: return null
        val halo = finish.bake.halo?.let { HaloLayer.place(body, library.camera, it, w, h) }
        return ImpostorFrame(finish, best.first, best.second, closedEyes = false, halo = halo, viewportWidth = w, viewportHeight = h)
    }

    private fun place(tier: BakeTier?, selector: CellSelector?, body: Mat4, w: Double, h: Double): Pair<BakeTier, ImpostorPlacement>? {
        if (tier == null || selector == null) return null
        val plane = PoseImpostor.Plane(PoseImpostor.limbDepth(library.camera), tier.viewportWidth.toDouble(), tier.viewportHeight.toDouble())
        return PoseImpostor.place(body, library.camera, selector, finish.bake.quadHalfUnits, w, h, plane)?.let { tier to it }
    }

    companion object {
        const val PHASES = 50
        const val SAMPLE_HZ = 120.0
    }
}
