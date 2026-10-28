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

    /** 이웃 두 표본 사이 자세(구현과 독립): 위치 · 크기 = (1−f)·a + f·b, 회전 = 짧은 호 이등분을 거듭한 slerp(f ∈ {¼, ½, ¾}). */
    private fun between(a: PoseSample, b: PoseSample, f: Double): PoseSample {
        val qb = if (a.rotation.dot(b.rotation) < 0) -b.rotation else b.rotation
        fun mid(p: Quat, q: Quat) = Quat(p.x + q.x, p.y + q.y, p.z + q.z, p.w + q.w).normalized()
        val half = mid(a.rotation, qb)
        val rot = when (f) {
            0.5 -> half
            0.25 -> mid(a.rotation, half)
            0.75 -> mid(half, qb)
            else -> error("f = ¼ · ½ · ¾ 만")
        }
        fun lerp(p: Vec3, q: Vec3) = Vec3(p.x * (1 - f) + q.x * f, p.y * (1 - f) + q.y * f, p.z * (1 - f) + q.z * f)
        return PoseSample(lerp(a.scale, b.scale), rot, lerp(a.position, b.position))
    }

    private fun closeEnough(mine: PoseSample, expected: PoseSample): String? {
        val dp = (mine.position - expected.position).length
        val ds = (mine.scale - expected.scale).length
        val da = Quat.angleBetween(mine.rotation, expected.rotation)
        // 위치 · 크기는 같은 식이라 1e-9, 회전은 짧은 각에서 쓰는 정규화 선형 보간과 참 slerp 의 차(θ³ 차수, 표본 간 ≤ 2.7°)까지 1e-5 rad.
        return if (dp > 1e-9 || ds > 1e-9 || da > 1e-5) "위치 ${"%.2e".format(dp)} · 크기 ${"%.2e".format(ds)} · 각 ${"%.2e".format(da)}rad" else null
    }

    @Test
    fun T1_표본_사이_시각은_이웃_두_표본의_보간이다() {
        // 골든(T1 · T3)은 표본 격자 시각(k/480)만 묻는다. 기기는 vsync 시각에 그리므로 언제나 표본 사이를 탄다 — 그 보간을 따로 잰다.
        val bad = ArrayList<String>()
        var checked = 0
        for (name in lib.motion.tracks.keys.sorted()) {
            val track = lib.track(name) ?: continue
            for (k in 0 until track.count - 1) {
                val a = track.sampleAt(k); val b = track.sampleAt(k + 1)
                for (f in doubleArrayOf(0.25, 0.5, 0.75)) {
                    val why = closeEnough(track.sample((k + f) / track.sampleHz), between(a, b, f))
                    if (why != null && bad.size < 20) bad += "$name k=$k f=$f: $why"
                    checked++
                }
            }
        }
        assertTrue(checked > 30_000, "잰 시각 $checked")
        assertTrue(bad.isEmpty(), "트랙 보간 어긋남:\n" + bad.joinToString("\n"))

        // 공개 API 로: play 한 뒤 반 표본 어긋난 벽시계 시각의 wrapper 자세(위치는 extent 배).
        val extent = lib.motion.extent
        for (reaction in listOf("hit", "poked", "greeting", "goalAchieved", "drowsy")) {
            val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.builtInAingID)
            val t0 = 2.0
            assertTrue(p.play(reaction, t0))
            val track = lib.track(lib.motion.reaction(reaction)!!.track!!)!!
            val scale = if (track.positionUnits == "extent") extent else 1.0
            for (k in 0 until track.count - 1) {
                val e = between(track.sampleAt(k), track.sampleAt(k + 1), 0.5)
                val expected = PoseSample(e.scale, e.rotation, e.position * scale)
                val why = closeEnough(p.wrapperPose(t0 + (k + 0.5) / track.sampleHz), expected)
                if (why != null && bad.size < 20) bad += "$reaction(재생기) k=$k: $why"
            }
        }
        assertTrue(bad.isEmpty(), "재생기 보간 어긋남:\n" + bad.joinToString("\n"))
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
