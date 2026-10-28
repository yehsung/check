// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (renderGolden 의 world · referenceCell) — 설계 F §6 T1 모션 · T2 칸 고르기
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.PoseSample
import com.yehsung.aingcheck.character.math.Quat
import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.character.parity.GoldenReplay
import com.yehsung.aingcheck.character.parity.WorldCompare
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.player.WakeKind
import com.yehsung.aingcheck.character.pose.PoseImpostor
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * T1: 재생기 공개 API(play · beginSleep · wake · setFacing · setEyesClosed · swapCharacter)로 골든 240장의 순간을 다시 밟아
 * 맥이 녹화한 노드 world(wrapper · facing · character)와 맞댄다(scale ≤ 1e-4 · 각 ≤ 0.05° · 위치 ≤ 1e-4).
 * T2: 그 world 로 Kotlin 이 고른 칸 = Swift 참조 칸(골든 `referenceCell`). 동점 경계 예외 목록은 비어 있다.
 */
class MotionAndCellParityTest {
    private val lib = RepoBake.library
    private val goldens = RepoBake.goldens.entries

    @Test
    fun T1_골든_240장의_노드_world_가_맥_녹화와_같다() {
        assertEquals(240, goldens.size)
        val bad = ArrayList<String>()
        var worst = 0.0
        for (g in goldens) {
            val chain = GoldenReplay.replay(lib, g).chain
            for ((name, mine, mac) in listOf(Triple("wrapper", chain.wrapper, g.wrapper), Triple("facing", chain.facing, g.facing), Triple("character", chain.character, g.character))) {
                val d = WorldCompare.diff(mine, mac)
                worst = maxOf(worst, d.angleDeg)
                if (!d.within()) bad += "${g.id} $name $d"
            }
        }
        assertTrue(bad.isEmpty(), "T1 어긋남 ${bad.size}건:\n" + bad.take(20).joinToString("\n"))
        println("T1: 240장 × 3노드, 최악 각 ${"%.2e".format(worst)}°")
    }

    @Test
    fun T2_칸_고르기가_Swift_참조와_같다() {
        val bad = ArrayList<String>()
        for (g in goldens) {
            val frame = GoldenReplay.plan(lib, g)
            if (frame.placement.cell.id != g.referenceCellId) bad += "${g.id}: ${frame.placement.cell.id} ≠ ${g.referenceCellId}"
            else if (abs(frame.placement.angleDeg - g.referenceAngleDeg) > 1e-3) bad += "${g.id}: 각 ${frame.placement.angleDeg} ≠ ${g.referenceAngleDeg}"
            // 시선 방향(요 · 기울기)도 맥이 낸 값과 같다.
            val (yaw, tilt) = com.yehsung.aingcheck.character.math.Angles.yawTilt(frame.placement.viewDirection)
            if (abs(yaw - g.viewYawDeg) > 1e-3 || abs(tilt - g.viewTiltDeg) > 1e-3) bad += "${g.id}: 시선 ($yaw, $tilt) ≠ (${g.viewYawDeg}, ${g.viewTiltDeg})"
        }
        assertTrue(bad.isEmpty(), "T2 어긋남 ${bad.size}건:\n" + bad.take(20).joinToString("\n"))
    }

    @Test
    fun 판_깊이_0_의_칸_사각형은_굽기가_적은_quad_와_같다() {
        // 정합 판을 윤곽 깊이(r²/d)로 옮겨 쓰므로 칸 사각형을 다시 낸다 — 깊이 0 이면 굽기 값과 같아야 계산이 맞다.
        var worst = 0.0
        for (id in lib.bakedIds) {
            val f = lib.finish(id)!!
            for (tier in listOf("S", "L", "U")) {
                val t = f.bake.tier(tier)!!
                for (c in f.cells(tier)!!.cells) {
                    val q = PoseImpostor.cellQuadAtDepth(c, lib.camera, f.bake.quadHalfUnits, 0.0, t.viewportWidth.toDouble(), t.viewportHeight.toDouble())
                    for (k in 0 until 4) worst = maxOf(worst, abs(q[k].x - c.quad[k].x), abs(q[k].y - c.quad[k].y))
                }
            }
        }
        assertTrue(worst < 2e-3, "칸 사각형 재계산 오차 $worst px(굽기는 소수 셋째 자리로 적었다)")
    }

    @Test
    fun 맥_프레이밍_카메라_식이_굽기_카메라와_같다() {
        // 스프라이트는 이 식(addFramingCamera)으로 자기 카메라를 짓는다 — 아잉 bbox 를 넣으면 굽기가 내보낸 camera.json 이 나와야 식이 맞다.
        val baked = lib.camera
        val framed = com.yehsung.aingcheck.character.bake.SceneCamera.framing(baked.bodyMin, baked.bodyMax)
        assertTrue((framed.position - baked.position).length < 2e-6, "위치 ${framed.position} ≠ ${baked.position}")
        val d = WorldCompare.diff(framed.world, baked.world)
        assertTrue(d.angleDeg < 0.05, "방향 ${d.angleDeg}°")
        assertTrue(abs(framed.extent - baked.extent) < 1e-5)
        // 같은 점의 투영도 0.1px 안.
        for (p in listOf(Vec3(0.0, 0.0, 0.0), Vec3(0.8, 0.6, 0.3), Vec3(-0.9, -0.8, -0.5))) {
            val a = framed.project(p, 280.0, 340.0); val b = baked.project(p, 280.0, 340.0)
            assertTrue(kotlin.math.hypot(a.x - b.x, a.y - b.y) < 0.1, "투영 $p")
        }
    }

    @Test
    fun 끊기와_졸다가_깨기는_현재_자세에서_단위로_간다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.builtInAingID)
        val poked = lib.track("poked")!!
        val peak = (0 until poked.count).maxBy { Quat.angleBetween(poked.sampleAt(it).rotation, Quat.IDENTITY) }
        val tPeak = peak / 480.0
        assertTrue(p.play("poked", 0.0))
        val mid = p.wrapperPose(tPeak)
        assertTrue(Quat.angleBetween(mid.rotation, Quat.IDENTITY) > 1.0, "찔림 정점은 단위가 아니다")
        p.interrupt(tPeak)
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(tPeak))
        assertEquals(null, p.activeReaction)

        // 가라앉는 도중(1.0s)에 깨우면 그 자세에서 출발 — 첫 순간은 연속, 0.15s + 되튀기 뒤 단위.
        assertTrue(p.beginSleep(10.0))
        assertTrue(p.eyesClosed && p.sleeping)
        val before = p.wrapperPose(11.0)
        assertTrue(p.wake(WakeKind.startled, 11.0))
        assertTrue(!p.eyesClosed && !p.sleeping)
        val at0 = p.wrapperPose(11.0)
        assertTrue(Quat.angleBetween(before.rotation, at0.rotation) < 1e-6, "깨는 순간 각이 튀면 안 된다")
        assertTrue((before.position - at0.position).length < 1e-9)
        val wakeBounce = lib.track("wakeBounce")!!
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(11.0 + 0.15 + wakeBounce.durationS + 0.01))

        // 조용한 기상: 0.9s smoothstep, 되튀기 없음.
        assertTrue(p.beginSleep(20.0))
        p.wrapperPose(23.0) // 끝 자세를 쥔다
        assertTrue(p.wake(WakeKind.quiet, 23.0))
        val half = p.wrapperPose(23.45)
        val sleep = lib.motion.sleepPose
        val expectedHalfPosY = sleep.position.y * lib.motion.extent * 0.5 // smoothstep(0.5) = 0.5
        assertTrue(abs(half.position.y - expectedHalfPosY) < 1e-4, "조용한 기상 중간 위치 ${half.position.y} ≠ $expectedHalfPosY")
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(23.91))
    }

    @Test
    fun 스프라이트는_평면판_트랙을_고르고_facing_을_돌리지_않는다() {
        // 평면판(.flat)이 있는 리액션은 그 트랙(x · y 회전 0), 없는 리액션은 3D 트랙 그대로(F §1.3 '같음').
        val flat = lib.track("commuteStart.flat")!!
        for (k in 0 until flat.count) {
            val q = flat.sampleAt(k).rotation
            assertTrue(abs(q.x) < 1e-6 && abs(q.y) < 1e-6, "평면판은 z 회전뿐 $k")
        }
        val three = lib.track("commuteStart")!!
        assertTrue((0 until three.count).any { abs(three.sampleAt(it).rotation.y) > 0.1 }, "3D commuteStart 는 y 스핀이 있다(대조군)")
        assertTrue(lib.motion.tracks.keys.containsAll(listOf("commuteStart.flat", "commuteEnd.flat", "poked.flat", "goalAchieved.flat", "drowsySink.flat")))
        assertTrue(BakeLibrary.FOLDERS.isNotEmpty())
        assertEquals(Vec3(1.0, 1.0, 1.0), PoseSample.IDENTITY.scale)
    }
}
