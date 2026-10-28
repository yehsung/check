// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (BakeCamera.project — 앱 카메라 `addFramingCamera` 의 world 변환 · fov)
package com.yehsung.aingcheck.character.bake

import com.yehsung.aingcheck.character.bake.BakeJson.dbl
import com.yehsung.aingcheck.character.bake.BakeJson.doubles
import com.yehsung.aingcheck.character.bake.BakeJson.int
import com.yehsung.aingcheck.character.bake.BakeJson.obj
import com.yehsung.aingcheck.character.bake.BakeJson.req
import com.yehsung.aingcheck.character.bake.BakeJson.str
import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.math.Vec3
import kotlin.math.PI
import kotlin.math.tan

/**
 * 굽기가 내보낸 카메라(camera.json). Kotlin 은 bbox 에서 다시 계산하지 않는다(F §3.2-6).
 * world → 화면 픽셀(위-왼쪽 원점, 연속 좌표: 픽셀 i 는 [i, i+1)). fov 는 **세로 기준**(F §1.2 실측).
 */
class SceneCamera(
    val world: Mat4,
    val fovDeg: Double,
    val verticalFov: Boolean,
    /** 몸 bbox(모델 단위) — 후광 판 크기(몸 높이 × 2)와 몸 중심. */
    val bodyMin: Vec3,
    val bodyMax: Vec3,
    /** 모델 최장변 e(리액션 진폭 단위). */
    val extent: Double,
) {
    private val view: Mat4 = world.inverse()
    val position: Vec3 get() = world.translation

    /** 세계 점 → 뷰포트 픽셀. 카메라 뒤(−z ≥ 0)의 점은 의미가 없다 — 호출부는 몸이 늘 앞에 있다. */
    fun project(p: Vec3, viewportWidth: Double, viewportHeight: Double): Vec2 {
        val c = view.transformPoint(p)
        val f = 1 / tan(fovDeg * PI / 360)
        val aspect = viewportWidth / viewportHeight
        val fx = if (verticalFov) f / aspect else f
        val fy = if (verticalFov) f else f * aspect
        val nx = fx * c.x / -c.z
        val ny = fy * c.y / -c.z
        return Vec2((nx + 1) / 2 * viewportWidth, (1 - (ny + 1) / 2) * viewportHeight)
    }

    /** 카메라 국소 z(앞이 음수). 입자 앞뒤 가르기 · 카메라 뒤 판정에 쓴다. */
    fun viewZ(p: Vec3): Double = view.transformPoint(p).z

    companion object {
        const val FIELD_OF_VIEW_DEG = 40.0

        /**
         * 맥 `addFramingCamera(to:)` 그대로: 씬 루트 bbox 의 최장변(x · y) e, 거리 = e / (2·tan(fov/2)) × 1.4,
         * 위치 = (cx, cy + 0.55e, maxZ + 거리), 바라보는 점 = (cx, cy − 0.16e, cz), 위 = 세계 y.
         * 구운 아잉이는 굽기가 내보낸 camera.json 을 쓰고(시험이 이 식과 맞댄다), **스프라이트는 이 식으로** 자기 평면 bbox 에서 짓는다 —
         * 스프라이트 씬은 깊이가 0 이라 카메라가 아잉보다 0.73 단위 가깝다(같은 카메라를 쓰면 맥보다 작게 그린다).
         */
        fun framing(min: Vec3, max: Vec3, fovDeg: Double = FIELD_OF_VIEW_DEG): SceneCamera {
            val cx = (min.x + max.x) / 2; val cy = (min.y + max.y) / 2; val cz = (min.z + max.z) / 2
            val e = maxOf(max.x - min.x, max.y - min.y)
            val distance = e / (2 * tan(fovDeg / 2 * PI / 180)) * 1.4
            val position = Vec3(cx, cy + e * 0.55, max.z + distance)
            val target = Vec3(cx, cy - e * 0.16, cz)
            val forward = (target - position).normalized()
            val right = (forward cross Vec3.UP).normalized()
            val up = right cross forward
            val back = -forward
            val world = Mat4(
                doubleArrayOf(
                    right.x, right.y, right.z, 0.0, up.x, up.y, up.z, 0.0, back.x, back.y, back.z, 0.0,
                    position.x, position.y, position.z, 1.0,
                ),
            )
            return SceneCamera(world, fovDeg, verticalFov = true, bodyMin = min, bodyMax = max, extent = e)
        }

        fun decode(text: String): SceneCamera {
            val o = BakeJson.parse(text)
            if (o.req("format").int() != 1) throw BakeFormatException("camera 형식")
            val axis = o.req("fovAxis").str()
            val box = o.req("bodyBox").obj()
            val mn = box.req("min").doubles(); val mx = box.req("max").doubles()
            return SceneCamera(
                world = Mat4.of(o.req("worldTransform").doubles().also { if (it.size != 16) throw BakeFormatException("worldTransform 16칸") }),
                fovDeg = o.req("fovDeg").dbl(),
                verticalFov = axis == "vertical",
                bodyMin = Vec3(mn[0], mn[1], mn[2]),
                bodyMax = Vec3(mx[0], mx[1], mx[2]),
                extent = o.req("extent").dbl(),
            )
        }
    }
}
