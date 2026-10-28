// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (ReactionActions.wake · drowsyRise 의 rotateTo(0,0,0) — SceneKit eulerAngles 성분별 선형 보간)
package com.yehsung.aingcheck.character.math

import kotlin.math.asin
import kotlin.math.atan2

/**
 * SceneKit `eulerAngles`(x = pitch, y = yaw, z = roll). 회전 = Rx(pitch) · Ry(yaw) · Rz(roll)
 * (문서: "first roll, then yaw, then pitch" — 고정 축 기준 적용 순서).
 *
 * 쓰는 자리는 "현재 자세 → 단위" 보간(wake 0.15s easeOut · 조용한 기상 0.9s smoothstep)뿐이고, 그 출발 자세는 졸기 끝(3D = x 축 하나,
 * 평면판 = z 축 하나)이라 축 순서가 결과를 바꾸지 않는다. 여러 축이 섞인 자세에서 출발하는 일은 엔진 규약상 없다(굽기 toIdentityCheck).
 */
object SceneKitEuler {
    fun fromQuat(q: Quat): Vec3 {
        val r = q.toMat3()
        val yaw = asin(r[0, 2].coerceIn(-1.0, 1.0))
        val pitch = atan2(-r[1, 2], r[2, 2])
        val roll = atan2(-r[0, 1], r[0, 0])
        return Vec3(pitch, yaw, roll)
    }

    fun toQuat(e: Vec3): Quat {
        val qx = Quat.axisAngle(Vec3(1.0, 0.0, 0.0), e.x)
        val qy = Quat.axisAngle(Vec3(0.0, 1.0, 0.0), e.y)
        val qz = Quat.axisAngle(Vec3(0.0, 0.0, 1.0), e.z)
        return (qx * qy * qz).normalized()
    }
}

/** 쿼터니언 곱(해밀턴). `(a * b)` 의 회전 = 먼저 b, 그다음 a. */
operator fun Quat.times(o: Quat): Quat = Quat(
    w * o.x + x * o.w + y * o.z - z * o.y,
    w * o.y - x * o.z + y * o.w + z * o.x,
    w * o.z + x * o.y - y * o.x + z * o.w,
    w * o.w - x * o.x - y * o.y - z * o.z,
)
