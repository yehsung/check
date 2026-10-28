// 원본: 없음 (설계 F §6 T1 지표 — world 4×4 를 크기 · 회전 · 위치로 나눠 잰다)
package com.yehsung.aingcheck.character.parity

import com.yehsung.aingcheck.character.math.Angles
import com.yehsung.aingcheck.character.math.Mat3
import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.math.Quat
import kotlin.math.abs

/** 두 world 변환의 차이: 크기(열 길이) · 회전(정규화한 열의 각, 도) · 위치(모델 단위). */
data class WorldDiff(val scale: Double, val angleDeg: Double, val position: Double) {
    /** T1 문턱(F §6): scale ≤ 1e-4 · 각 ≤ 0.05° · 위치 ≤ 1e-4 단위. */
    fun within(scaleTol: Double = 1e-4, angleTolDeg: Double = 0.05, positionTol: Double = 1e-4): Boolean =
        scale <= scaleTol && angleDeg <= angleTolDeg && position <= positionTol
}

object WorldCompare {
    fun diff(a: Mat4, b: Mat4): WorldDiff {
        var sc = 0.0
        for (c in 0 until 3) sc = maxOf(sc, abs(a.column(c).length - b.column(c).length))
        fun rot(m: Mat4) = Quat.fromMat3(Mat3.fromColumns(m.column(0).normalized(), m.column(1).normalized(), m.column(2).normalized()))
        return WorldDiff(sc, Angles.deg(Quat.angleBetween(rot(a), rot(b))), (a.translation - b.translation).length)
    }
}
