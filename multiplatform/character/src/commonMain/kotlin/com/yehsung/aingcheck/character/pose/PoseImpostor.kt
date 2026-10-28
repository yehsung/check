// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (BakeSelector.nearest · BakeMath.viewDirection · Baker.renderCell 의 4점) — 설계 F §2.1 C · §5.1 PoseImpostor
package com.yehsung.aingcheck.character.pose

import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.bake.SceneCamera
import com.yehsung.aingcheck.character.math.Angles
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Mat3
import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.math.Vec3
import kotlin.math.abs
import kotlin.math.acos

/**
 * 가장 가까운 칸(각 거리). 굽기의 골든 "Swift 참조 칸"과 같은 규칙: 내적 최대, 동점(1e-15 안)은 **번호가 작은 칸**.
 * 번호 = [BakeCell.canonicalOrder] 순서(파일 순서가 그것이다 — T0 가 잰다). Swift 는 2° 상자 후보 거르기로 빨리 찾지만
 * 상자 안 후보가 정확하다고 증명된 최적화일 뿐 답은 전수와 같다(칸 ≤ 600 내적 — 마이크로초).
 */
class CellSelector(val cells: List<BakeCell>) {
    private val dirs = cells.map { it.direction }

    data class Pick(val index: Int, val cell: BakeCell, val angleDeg: Double)

    fun nearest(n: Vec3): Pick {
        require(cells.isNotEmpty()) { "칸이 없다" }
        var best = -1
        var bestDot = -2.0
        for (i in dirs.indices) {
            val d = n dot dirs[i]
            if (d > bestDot + 1e-15 || (abs(d - bestDot) <= 1e-15 && i < best)) {
                bestDot = d; best = i
            }
        }
        return Pick(best, cells[best], Angles.deg(acos(bestDot.coerceIn(-1.0, 1.0))))
    }
}

/** 한 프레임의 칸 정합 결과: 고른 칸과 칸 픽셀(칸 rect 원점 기준 연속 좌표) → 뷰포트 픽셀 호모그래피. */
data class ImpostorPlacement(
    val cell: BakeCell,
    val angleDeg: Double,
    /** 칸 국소 픽셀 → 뷰포트 픽셀. */
    val cellToViewport: Homography,
    /** 뷰포트 위 네 점(TL · TR · BR · BL) — 히트 상자 · 다시 그릴지 판단에 쓴다. */
    val viewportQuad: List<Vec2>,
    /** 몸 국소에서 본 실제 시선 방향(단위). */
    val viewDirection: Vec3,
)

object PoseImpostor {
    /**
     * 몸 world 변환 + 카메라 위치 → 칸 고르기 방향 n = normalize(B₃⁻¹ · d), d = normalize(카메라 − 피벗)(설계 F §3.2-2,
     * BakeMath.viewDirection). B₃ 는 크기까지 든 3×3 이라 찌부·늘림이 시선 기울기로 바뀐다(hit 찌부 → τ 26.3°).
     */
    fun viewDirection(body: Mat4, cameraPosition: Vec3): Vec3 {
        val p = body.translation
        val d = (cameraPosition - p).normalized()
        return (body.upper3().inverse() * d).normalized()
    }

    /**
     * 몸 국소 네 점: 피벗 ± h·r ± h·u, r = normalize(up × n), u = n × r — 굽기 `renderCell` 과 같은 순서(TL · TR · BR · BL).
     * 굽는 쪽은 n = 칸 방향, 런타임은 n = 실제 시선(탐침 `quadPoints` 와 같다: 두 평면 모두 "시선에 수직인 판").
     */
    fun localQuad(n: Vec3, halfUnits: Double, depth: Double = 0.0): List<Vec3> {
        val r = (Vec3.UP cross n).normalized()
        val u = n cross r
        val c = n * depth
        return listOf(-1.0 to 1.0, 1.0 to 1.0, 1.0 to -1.0, -1.0 to -1.0).map { (sx, sy) -> c + r * (sx * halfUnits) + u * (sy * halfUnits) }
    }

    /**
     * 칸 렌더의 wrapper 회전(굽기 `BakeMath.cellRotation`): 몸 국소 칸 방향이 원점→카메라 방향 d0 와 겹치고 몸 위 축이 화면에서 기울지 않게.
     */
    fun cellRotation(cell: BakeCell, cameraDirection: Vec3): Mat3 {
        val n = cell.direction
        val rl = (Vec3.UP cross n).normalized(); val ul = n cross rl
        val rw = (Vec3.UP cross cameraDirection).normalized(); val uw = cameraDirection cross rw
        val w = Mat3.fromColumns(rw, uw, cameraDirection); val l = Mat3.fromColumns(rl, ul, n)
        return w * l.transpose()
    }

    /**
     * 칸 픽셀 사각형을 판 깊이 [depth](시선 쪽, 몸 국소 단위)에서 다시 낸다. depth = 0 이면 굽기가 적은 `quad` 와 같다(시험이 잰다).
     * 칸 원점(렌더 안 잘라 낸 위치) = 피벗 투영 − `pivot`.
     */
    fun cellQuadAtDepth(cell: BakeCell, camera: SceneCamera, halfUnits: Double, depth: Double, tierWidth: Double, tierHeight: Double): List<Vec2> {
        val d0 = camera.position.normalized()
        val r = cellRotation(cell, d0)
        val pivot = camera.project(Vec3.ZERO, tierWidth, tierHeight)
        val ox = pivot.x - cell.pivot.x; val oy = pivot.y - cell.pivot.y
        return localQuad(cell.direction, halfUnits, depth).map { local ->
            val p = camera.project(r * local, tierWidth, tierHeight)
            Vec2(p.x - ox, p.y - oy)
        }
    }

    /**
     * 칸을 골라 정합한다.
     * @param body 몸(캐릭터 노드) world.
     * @param viewportWidth · viewportHeight 그릴 뷰포트(픽셀). 칸 단의 뷰포트와 같은 종횡비일 필요는 없다 — 투영을 그 뷰포트로 한다.
     */
    /** 판 깊이 설정: [depth] 가 0 이 아니면 칸 사각형을 그 깊이에서 다시 낸다(칸 단 뷰포트가 필요하다). */
    data class Plane(val depth: Double = 0.0, val tierWidth: Double = 0.0, val tierHeight: Double = 0.0)

    /**
     * 정합 판의 깊이(설계 F §2.1 C 의 "피벗을 지나 n 에 수직인 평면"을 시선 쪽으로 옮긴 것): 반지름 r 인 몸을 거리 d 에서 보면
     * 윤곽(limb)은 중심보다 r²/d 앞에 있다. 그 평면에 정합하면 크기가 바뀌는 리액션(울트라 충전 1.22배 · 찌부)에서 원근 차이를 판이 흡수한다.
     * r = 몸 bbox x 반폭(0.96), d = 카메라 ~ 피벗 거리(4.55) → 약 0.20 모델 단위.
     * 골든 240장 실측(데스크톱 Skia, 오염 · 후광 지연 제외 168장): 피벗 판 대비 평균 IoU 0.9966 → 0.9970, 최악(울트라 충전 정점) 0.9759 → 0.9896.
     */
    fun limbDepth(camera: SceneCamera): Double {
        val r = (camera.bodyMax.x - camera.bodyMin.x) / 2
        val d = camera.position.length
        return r * r / d
    }

    fun place(
        body: Mat4,
        camera: SceneCamera,
        selector: CellSelector,
        halfUnits: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        plane: Plane = Plane(),
    ): ImpostorPlacement? {
        val n = viewDirection(body, camera.position)
        val pick = selector.nearest(n)
        return placeWith(pick.cell, body, camera, halfUnits, viewportWidth, viewportHeight, plane)
    }

    /** 칸을 정해 두고 정합만(음성 대조 · 시험 — "틀린 칸"을 일부러 넣을 때도 같은 길). */
    fun placeWith(
        cell: BakeCell,
        body: Mat4,
        camera: SceneCamera,
        halfUnits: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        plane: Plane = Plane(),
    ): ImpostorPlacement? {
        val n = viewDirection(body, camera.position)
        val dst = localQuad(n, halfUnits, plane.depth).map { camera.project(body.transformPoint(it), viewportWidth, viewportHeight) }
        val src = if (plane.depth == 0.0) cell.quad else cellQuadAtDepth(cell, camera, halfUnits, plane.depth, plane.tierWidth, plane.tierHeight)
        val h = Homography.fromQuads(src, dst) ?: return null
        return ImpostorPlacement(cell, Angles.angleDeg(n, cell.direction), h, dst, n)
    }
}
