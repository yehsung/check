// 원본: Sources/check/GoldAingFinish.swift @ 1b8260d (haloPose · haloCell · haloCellTransform · makeHaloNode, :447-596)
package com.yehsung.aingcheck.character.pose

import com.yehsung.aingcheck.character.bake.BakeHalo
import com.yehsung.aingcheck.character.bake.SceneCamera
import com.yehsung.aingcheck.character.math.Angles
import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.math.Vec3
import kotlin.math.IEEErem
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin

/**
 * 후광(금 · 무지개) — 굽지 않고 기존 칸 PNG 36장을 몸 뒤 2D 판으로 쓴다(F §3.6). 맥 제약 블록의 순수 함수를 그대로 옮겼다.
 * 판은 언제나 몸 중심(표식 노드 = 캐릭터 노드 · 몸 bbox 중심)에 화면 정렬로 서고, 몸의 롤만큼 화면 안에서 기운다.
 * 히트 판정에서는 빠진다(몸이 아니다 — `GoldAingFinish.swift:44-47`).
 */
object HaloLayer {
    /** 카메라 기준 몸 자세(라디안). 카메라 기준 회전 = Rz(roll) · Rx(tilt) · Ry(yaw). */
    data class Pose(val yaw: Double, val roll: Double, val tilt: Double)

    /** 이 프레임 후광: 고른 칸 번호와 판 네 꼭짓점의 뷰포트 픽셀(TL · TR · BR · BL — 판 국소 (−½,+½) (+½,+½) (+½,−½) (−½,−½)). */
    data class Placement(val cell: Int, val pose: Pose, val quad: List<Vec2>, val sideUnits: Double)

    private fun axis(m: Mat4, c: Int): Vec3 = m.column(c).normalized()

    /** `haloPose(camera:body:)`: camera = 빌보드 결과(축 = 화면 오른쪽 · 위 · 카메라 쪽), body = 표식 노드 world. */
    fun pose(camera: Mat4, body: Mat4): Pose {
        val right = axis(camera, 0); val up = axis(camera, 1); val toward = axis(camera, 2)
        val bodyUp = axis(body, 1); val bodyForward = axis(body, 2)
        val u = Vec3(bodyUp dot right, bodyUp dot up, bodyUp dot toward)
        val f = Vec3(bodyForward dot right, bodyForward dot up, bodyForward dot toward)
        val roll = atan2(-u.x, u.y)
        val tilt = asin(u.z.coerceIn(-1.0, 1.0))
        val cr = cos(roll); val sr = sin(roll)
        val unrolled = Vec3(f.x * cr + f.y * sr, -f.x * sr + f.y * cr, f.z)
        val ct = cos(tilt); val st = sin(tilt)
        val level = Vec3(unrolled.x, unrolled.y * ct + unrolled.z * st, -unrolled.y * st + unrolled.z * ct)
        return Pose(atan2(level.x, level.z), roll, tilt)
    }

    /**
     * 몸 요(라디안) → 칸(0…35). 360° 로 감고 가장 가까운 칸 — 단 쉬는 자세(0° · ±40°) 둘레 ±restBand 안은 그 자세의 칸
     * (살랑이 칸 경계를 넘나들어 정면 후광이 3.6초마다 튀던 것을 막는 규칙 — `haloCell(yaw:)`).
     */
    fun cell(yaw: Double, halo: BakeHalo): Int {
        if (!yaw.isFinite()) return 0
        val degrees = Angles.deg(yaw).IEEErem(360.0) // Swift remainder(_, 360) 와 같은 IEEE 나머지 — (−180, 180]
        val band = halo.restBandDeg; val side = halo.sideRestDeg
        if (abs(degrees) <= band) return 0
        if (abs(degrees - side) <= band) return nearestCell(side, halo)
        if (abs(degrees + side) <= band) return nearestCell(-side, halo)
        return nearestCell(degrees, halo)
    }

    /** 도 → 가장 가까운 칸. Swift `.rounded()` = 0.5 는 0 에서 먼 쪽(`schoolbook`) — Kotlin `roundToInt` 는 +∞ 쪽이라 음수 .5 에서 갈린다. */
    internal fun nearestCell(degrees: Double, halo: BakeHalo): Int {
        val count = 360 / halo.yawStepDeg
        val x = degrees / halo.yawStepDeg
        val r = if (x >= 0) floor(x + 0.5) else -floor(-x + 0.5)
        val k = r.toInt() % count
        return if (k < 0) k + count else k
    }

    /**
     * 칸 판의 이 프레임 world(`haloCellTransform`) — 빌보드의 **방향만** 쓰고 위치 · 크기는 표식(anchor)에서 잰다.
     * 고른 칸이 아니면 맥은 크기를 1e-5 로 접지만, 런타임은 고른 칸 하나만 그리므로 접은 판은 만들지 않는다.
     */
    fun cellTransform(billboard: Mat4, anchor: Mat4, pose: Pose): Mat4 {
        val right = axis(billboard, 0); val up = axis(billboard, 1); val toward = axis(billboard, 2)
        val scale = Vec3(anchor.column(0).length, anchor.column(1).length, anchor.column(2).length)
        val c = cos(pose.roll); val s = sin(pose.roll)
        val rolledRight = right * c + up * s
        val rolledUp = up * c - right * s
        val p = anchor.translation
        val c0 = rolledRight * scale.x; val c1 = rolledUp * scale.y; val c2 = toward * scale.z
        return Mat4(doubleArrayOf(c0.x, c0.y, c0.z, 0.0, c1.x, c1.y, c1.z, 0.0, c2.x, c2.y, c2.z, 0.0, p.x, p.y, p.z, 1.0))
    }

    /**
     * 몸(캐릭터 노드) world → 후광 판의 칸 · 네 꼭짓점(뷰포트 픽셀).
     * 표식 노드 = 캐릭터의 자식, 위치 = 몸 bbox 중심(`centerUnits`), 판 한 변 = 몸 높이 × sideOverBodyHeight.
     */
    fun place(body: Mat4, camera: SceneCamera, halo: BakeHalo, viewportWidth: Double, viewportHeight: Double): Placement {
        val center = Vec3(halo.centerUnits[0], halo.centerUnits[1], halo.centerUnits[2])
        val anchor = body * Mat4.translation(center)
        val p = pose(camera.world, anchor)
        val index = cell(p.yaw, halo)
        val m = cellTransform(camera.world, anchor, p)
        val side = (camera.bodyMax.y - camera.bodyMin.y) * halo.sideOverBodyHeight
        val half = side / 2
        val quad = listOf(-half to half, half to half, half to -half, -half to -half).map { (x, y) ->
            camera.project(m.transformPoint(Vec3(x, y, 0.0)), viewportWidth, viewportHeight)
        }
        return Placement(index, p, quad, side)
    }
}
