// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (BakeMath — 칸 방향 · 요/기울기 · 시선 방향) + simd 꼴 연산
package com.yehsung.aingcheck.character.math

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** 3차원 벡터(double). 재생기의 기하는 전부 double 로 잰다(맥 굽기 쪽 BakeMath 와 같은 정밀도). */
data class Vec3(val x: Double, val y: Double, val z: Double) {
    operator fun plus(o: Vec3) = Vec3(x + o.x, y + o.y, z + o.z)
    operator fun minus(o: Vec3) = Vec3(x - o.x, y - o.y, z - o.z)
    operator fun times(s: Double) = Vec3(x * s, y * s, z * s)
    operator fun unaryMinus() = Vec3(-x, -y, -z)
    infix fun dot(o: Vec3) = x * o.x + y * o.y + z * o.z
    infix fun cross(o: Vec3) = Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    val length: Double get() = sqrt(this dot this)
    fun normalized(): Vec3 {
        val l = length
        return if (l > 0) Vec3(x / l, y / l, z / l) else this
    }

    companion object {
        val ZERO = Vec3(0.0, 0.0, 0.0)
        val UP = Vec3(0.0, 1.0, 0.0)
    }
}

/** 2차원 점(화면 픽셀 — 위-왼쪽 원점, 연속 좌표: 픽셀 i 는 [i, i+1)). */
data class Vec2(val x: Double, val y: Double)

/**
 * 4×4 행렬, **열 우선** 16칸(`m[col * 4 + row]`) — 골든 `world` · camera.json `worldTransform` 과 같은 배치.
 * SceneKit 노드 변환 = 이동 · 회전 · 크기(열벡터 규약).
 */
class Mat4(val m: DoubleArray) {
    init {
        require(m.size == 16) { "Mat4 는 16칸이다: ${m.size}" }
    }

    operator fun get(row: Int, col: Int): Double = m[col * 4 + row]

    operator fun times(o: Mat4): Mat4 {
        val r = DoubleArray(16)
        for (c in 0 until 4) for (row in 0 until 4) {
            var s = 0.0
            for (k in 0 until 4) s += this[row, k] * o[k, c]
            r[c * 4 + row] = s
        }
        return Mat4(r)
    }

    fun transformPoint(p: Vec3): Vec3 {
        val w = this[3, 0] * p.x + this[3, 1] * p.y + this[3, 2] * p.z + this[3, 3]
        val x = this[0, 0] * p.x + this[0, 1] * p.y + this[0, 2] * p.z + this[0, 3]
        val y = this[1, 0] * p.x + this[1, 1] * p.y + this[1, 2] * p.z + this[1, 3]
        val z = this[2, 0] * p.x + this[2, 1] * p.y + this[2, 2] * p.z + this[2, 3]
        return if (w == 1.0 || w == 0.0) Vec3(x, y, z) else Vec3(x / w, y / w, z / w)
    }

    fun column(c: Int): Vec3 = Vec3(m[c * 4], m[c * 4 + 1], m[c * 4 + 2])
    val translation: Vec3 get() = column(3)

    /** 왼쪽 위 3×3. */
    fun upper3(): Mat3 = Mat3.fromColumns(column(0), column(1), column(2))

    /** 일반 역행렬(가우스-조르당, 부분 피벗). 특이면 예외. */
    fun inverse(): Mat4 {
        val a = Array(4) { r -> DoubleArray(8) { c -> if (c < 4) this[r, c] else if (c - 4 == r) 1.0 else 0.0 } }
        for (col in 0 until 4) {
            var p = col
            for (r in col + 1 until 4) if (abs(a[r][col]) > abs(a[p][col])) p = r
            require(abs(a[p][col]) > 1e-300) { "특이 행렬" }
            val t = a[p]; a[p] = a[col]; a[col] = t
            val d = a[col][col]
            for (k in 0 until 8) a[col][k] /= d
            for (r in 0 until 4) if (r != col) {
                val f = a[r][col]
                if (f != 0.0) for (k in 0 until 8) a[r][k] -= f * a[col][k]
            }
        }
        val out = DoubleArray(16)
        for (r in 0 until 4) for (c in 0 until 4) out[c * 4 + r] = a[r][c + 4]
        return Mat4(out)
    }

    fun toList(): List<Double> = m.toList()

    companion object {
        val IDENTITY = Mat4(doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0))

        fun of(columnMajor: List<Double>): Mat4 = Mat4(columnMajor.toDoubleArray())

        fun translation(t: Vec3): Mat4 = Mat4(doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, t.x, t.y, t.z, 1.0))

        fun rotationY(radians: Double): Mat4 {
            val c = cos(radians); val s = sin(radians)
            return Mat4(doubleArrayOf(c, 0.0, -s, 0.0, 0.0, 1.0, 0.0, 0.0, s, 0.0, c, 0.0, 0.0, 0.0, 0.0, 1.0))
        }

        /** SceneKit 노드 꼴: 이동 · 회전(쿼터니언) · 크기. */
        fun trs(translation: Vec3, rotation: Quat, scale: Vec3): Mat4 {
            val r = rotation.toMat3()
            val c0 = r.column(0) * scale.x
            val c1 = r.column(1) * scale.y
            val c2 = r.column(2) * scale.z
            return Mat4(
                doubleArrayOf(
                    c0.x, c0.y, c0.z, 0.0,
                    c1.x, c1.y, c1.z, 0.0,
                    c2.x, c2.y, c2.z, 0.0,
                    translation.x, translation.y, translation.z, 1.0,
                ),
            )
        }

        fun fromRotation(r: Mat3, translation: Vec3 = Vec3.ZERO): Mat4 {
            val c0 = r.column(0); val c1 = r.column(1); val c2 = r.column(2)
            return Mat4(
                doubleArrayOf(
                    c0.x, c0.y, c0.z, 0.0, c1.x, c1.y, c1.z, 0.0, c2.x, c2.y, c2.z, 0.0,
                    translation.x, translation.y, translation.z, 1.0,
                ),
            )
        }
    }
}

/** 3×3 행렬, 열 우선 9칸. */
class Mat3(val m: DoubleArray) {
    operator fun get(row: Int, col: Int): Double = m[col * 3 + row]
    fun column(c: Int): Vec3 = Vec3(m[c * 3], m[c * 3 + 1], m[c * 3 + 2])

    operator fun times(v: Vec3): Vec3 = Vec3(
        this[0, 0] * v.x + this[0, 1] * v.y + this[0, 2] * v.z,
        this[1, 0] * v.x + this[1, 1] * v.y + this[1, 2] * v.z,
        this[2, 0] * v.x + this[2, 1] * v.y + this[2, 2] * v.z,
    )

    operator fun times(o: Mat3): Mat3 {
        val r = DoubleArray(9)
        for (c in 0 until 3) for (row in 0 until 3) {
            var s = 0.0
            for (k in 0 until 3) s += this[row, k] * o[k, c]
            r[c * 3 + row] = s
        }
        return Mat3(r)
    }

    fun transpose(): Mat3 = Mat3(DoubleArray(9) { i -> val c = i / 3; val r = i % 3; this[c, r] })

    fun determinant(): Double =
        this[0, 0] * (this[1, 1] * this[2, 2] - this[1, 2] * this[2, 1]) -
            this[0, 1] * (this[1, 0] * this[2, 2] - this[1, 2] * this[2, 0]) +
            this[0, 2] * (this[1, 0] * this[2, 1] - this[1, 1] * this[2, 0])

    fun inverse(): Mat3 {
        val d = determinant()
        require(abs(d) > 1e-300) { "특이 행렬" }
        val inv = DoubleArray(9)
        // 여인수 전치 / 행렬식. inv[row, col] 을 열 우선으로.
        fun set(r: Int, c: Int, v: Double) { inv[c * 3 + r] = v / d }
        set(0, 0, this[1, 1] * this[2, 2] - this[1, 2] * this[2, 1])
        set(0, 1, this[0, 2] * this[2, 1] - this[0, 1] * this[2, 2])
        set(0, 2, this[0, 1] * this[1, 2] - this[0, 2] * this[1, 1])
        set(1, 0, this[1, 2] * this[2, 0] - this[1, 0] * this[2, 2])
        set(1, 1, this[0, 0] * this[2, 2] - this[0, 2] * this[2, 0])
        set(1, 2, this[0, 2] * this[1, 0] - this[0, 0] * this[1, 2])
        set(2, 0, this[1, 0] * this[2, 1] - this[1, 1] * this[2, 0])
        set(2, 1, this[0, 1] * this[2, 0] - this[0, 0] * this[2, 1])
        set(2, 2, this[0, 0] * this[1, 1] - this[0, 1] * this[1, 0])
        return Mat3(inv)
    }

    companion object {
        fun fromColumns(c0: Vec3, c1: Vec3, c2: Vec3) = Mat3(doubleArrayOf(c0.x, c0.y, c0.z, c1.x, c1.y, c1.z, c2.x, c2.y, c2.z))
    }
}

/** 쿼터니언(x, y, z, w). 트랙 파일의 회전 칸 그대로. */
data class Quat(val x: Double, val y: Double, val z: Double, val w: Double) {
    fun dot(o: Quat) = x * o.x + y * o.y + z * o.z + w * o.w
    operator fun unaryMinus() = Quat(-x, -y, -z, -w)

    fun normalized(): Quat {
        val l = sqrt(x * x + y * y + z * z + w * w)
        return if (l > 0) Quat(x / l, y / l, z / l, w / l) else IDENTITY
    }

    fun toMat3(): Mat3 {
        val q = normalized()
        val xx = q.x * q.x; val yy = q.y * q.y; val zz = q.z * q.z
        val xy = q.x * q.y; val xz = q.x * q.z; val yz = q.y * q.z
        val wx = q.w * q.x; val wy = q.w * q.y; val wz = q.w * q.z
        return Mat3(
            doubleArrayOf(
                1 - 2 * (yy + zz), 2 * (xy + wz), 2 * (xz - wy),
                2 * (xy - wz), 1 - 2 * (xx + zz), 2 * (yz + wx),
                2 * (xz + wy), 2 * (yz - wx), 1 - 2 * (xx + yy),
            ),
        )
    }

    companion object {
        val IDENTITY = Quat(0.0, 0.0, 0.0, 1.0)

        /** 구면 선형 보간(짧은 호). 표본 간격 2.08ms 라 사이 각이 작다. */
        fun slerp(a: Quat, b0: Quat, t: Double): Quat {
            var b = b0
            var d = a.dot(b)
            if (d < 0) { b = -b; d = -d }
            if (d > 0.9995) {
                return Quat(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t).normalized()
            }
            val theta = acos(d.coerceIn(-1.0, 1.0))
            val s = sin(theta)
            val wa = sin((1 - t) * theta) / s
            val wb = sin(t * theta) / s
            return Quat(a.x * wa + b.x * wb, a.y * wa + b.y * wb, a.z * wa + b.z * wb, a.w * wa + b.w * wb)
        }

        fun axisAngle(axis: Vec3, radians: Double): Quat {
            val n = axis.normalized()
            val s = sin(radians / 2)
            return Quat(n.x * s, n.y * s, n.z * s, cos(radians / 2))
        }

        /** 회전 행렬(정규직교) → 쿼터니언. */
        fun fromMat3(r: Mat3): Quat {
            val trace = r[0, 0] + r[1, 1] + r[2, 2]
            return if (trace > 0) {
                val s = sqrt(trace + 1.0) * 2
                Quat((r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s, 0.25 * s)
            } else if (r[0, 0] > r[1, 1] && r[0, 0] > r[2, 2]) {
                val s = sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
                Quat(0.25 * s, (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s, (r[2, 1] - r[1, 2]) / s)
            } else if (r[1, 1] > r[2, 2]) {
                val s = sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
                Quat((r[0, 1] + r[1, 0]) / s, 0.25 * s, (r[1, 2] + r[2, 1]) / s, (r[0, 2] - r[2, 0]) / s)
            } else {
                val s = sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
                Quat((r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s, 0.25 * s, (r[1, 0] - r[0, 1]) / s)
            }.normalized()
        }

        /** 두 회전 사이 각(라디안). */
        fun angleBetween(a: Quat, b: Quat): Double = 2 * acos(abs(a.normalized().dot(b.normalized())).coerceAtMost(1.0))
    }
}

/** 각도 보조. */
object Angles {
    fun rad(deg: Double) = deg * PI / 180
    fun deg(rad: Double) = rad * 180 / PI

    /** 몸 국소에서 본 카메라 방향(칸 키 → 단위벡터). ψ + = 얼굴이 화면 오른쪽(후광 칸과 같은 부호) — BakeMath.cellDirection. */
    fun cellDirection(yawDeg: Double, tiltDeg: Double): Vec3 {
        val y = rad(yawDeg); val t = rad(tiltDeg)
        return Vec3(-sin(y) * cos(t), sin(t), cos(y) * cos(t))
    }

    /** 단위벡터 → (ψ, τ) 도 — BakeMath.yawTilt. */
    fun yawTilt(n: Vec3): Pair<Double, Double> = deg(-atan2(n.x, n.z)) to deg(asin(n.y.coerceIn(-1.0, 1.0)))

    fun angleDeg(a: Vec3, b: Vec3): Double = deg(acos((a dot b).coerceIn(-1.0, 1.0)))
}
