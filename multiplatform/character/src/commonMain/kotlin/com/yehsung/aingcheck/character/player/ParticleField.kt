// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (ReactionActions.confettiSystem · goalSparkSystem · ultraChargeSystem · emitConfetti/GoalSparks/UltraCharge, :1477-1525 · :1985-2076) — 굽기가 particles.json 으로 읽어 낸 매개변수를 쓴다(F §3.7)
package com.yehsung.aingcheck.character.player

import com.yehsung.aingcheck.character.bake.BakeFormatException
import com.yehsung.aingcheck.character.bake.BakeJson
import com.yehsung.aingcheck.character.bake.BakeJson.dbl
import com.yehsung.aingcheck.character.bake.BakeJson.doubles
import com.yehsung.aingcheck.character.bake.BakeJson.int
import com.yehsung.aingcheck.character.bake.BakeJson.obj
import com.yehsung.aingcheck.character.bake.BakeJson.opt
import com.yehsung.aingcheck.character.bake.BakeJson.req
import com.yehsung.aingcheck.character.bake.BakeJson.str
import com.yehsung.aingcheck.character.bake.SceneCamera
import com.yehsung.aingcheck.character.math.Angles
import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.character.render.QuadCanvas
import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 입자 계 하나의 매개변수(particles.json `systems.<이름>`). 단위는 모델 단위 · 초 · 도/초(F-6 실측: 각속도는 도/초,
 * colorVariation 은 (색상, 채도, 명도, 알파) 순서, 기본 입자 그림 nil = 딱딱한 사각형).
 * **변동(variation)은 값 ± variation/2 의 고른 분포**로 읽는다(F-6 색 변동 실측 폭 ≈ variation 과 맞는 해석 — 스칼라 변동은 맥 대조 미확인).
 */
data class ParticleSpec(
    val name: String,
    val birthRate: Double,
    val emissionDurationS: Double,
    val lifeSpanS: Double,
    val lifeSpanVariation: Double,
    val size: Double,
    val sizeVariation: Double,
    val velocity: Double,
    val velocityVariation: Double,
    val acceleration: Vec3,
    val spreadingAngleDeg: Double,
    val emittingDirection: Vec3,
    /** random · constant · surfaceNormal. */
    val birthDirection: String,
    /** sphere · cylinder. */
    val shapeType: String,
    val shapeRadius: Double,
    val shapeHeight: Double,
    val emitterPositionExtent: Vec3,
    val additive: Boolean,
    /** sRGB 0..1 (aqua · darkAqua). */
    val colorLight: List<Double>,
    val colorDark: List<Double>,
    val colorVariationHSBA: List<Double>,
    val angleDeg: Double,
    val angleVariationDeg: Double,
    val angularVelocityDegS: Double,
    val angularVelocityVariationDegS: Double,
) {
    val particleCount: Int get() = floor(birthRate * emissionDurationS + 1e-9).toInt()

    companion object {
        fun decodeAll(text: String): Map<String, ParticleSpec> {
            val o = BakeJson.parse(text)
            if (o.req("format").int() != 1) throw BakeFormatException("particles 형식")
            return o.req("systems").obj().mapValues { (name, v) ->
                val s = v.obj()
                val shape = s.req("emitterShape").obj()
                val color = s.req("colorSRGB").obj()
                fun v3(key: String) = s.req(key).doubles().let { Vec3(it[0], it[1], it[2]) }
                ParticleSpec(
                    name = name,
                    birthRate = s.req("birthRate").dbl(),
                    emissionDurationS = s.req("emissionDurationS").dbl(),
                    lifeSpanS = s.req("lifeSpanS").dbl(),
                    lifeSpanVariation = s.req("lifeSpanVariation").dbl(),
                    size = s.req("size").dbl(),
                    sizeVariation = s.req("sizeVariation").dbl(),
                    velocity = s.req("velocity").dbl(),
                    velocityVariation = s.req("velocityVariation").dbl(),
                    acceleration = v3("acceleration"),
                    spreadingAngleDeg = s.req("spreadingAngleDeg").dbl(),
                    emittingDirection = v3("emittingDirection"),
                    birthDirection = s.req("birthDirection").str(),
                    shapeType = shape.req("type").str(),
                    shapeRadius = shape.req("radius").dbl(),
                    shapeHeight = shape.opt("height")?.dbl() ?: 0.0,
                    emitterPositionExtent = v3("emitterPositionExtent"),
                    additive = s.req("blendMode").str() == "additive",
                    colorLight = color.req("aqua").doubles(),
                    colorDark = color.req("darkAqua").doubles(),
                    colorVariationHSBA = s.req("colorVariation").doubles(),
                    angleDeg = s.req("angle").dbl(),
                    angleVariationDeg = s.req("angleVariation").dbl(),
                    angularVelocityDegS = s.req("angularVelocity").dbl(),
                    angularVelocityVariationDegS = s.req("angularVelocityVariation").dbl(),
                )
            }
        }
    }
}

/** 입자 하나의 순간 상태(세계 좌표 · 모델 단위). */
data class Particle(val index: Int, val position: Vec3, val size: Double, val angleDeg: Double, val argb: Int, val ageS: Double, val lifeS: Double)

/**
 * 시드 있는 입자 버스트 하나(F §3.7 — 무작위라 픽셀 동치는 대상이 아니다; 분포가 같으면 된다). 계는 씬 루트에 붙어 몸을 따라가지 않는다.
 * 같은 (계, 시드)면 언제나 같은 입자(결정적). 입자 i 의 출생 = i / birthRate, 궤적 = p₀ + v₀τ + ½aτ²(감쇠 0).
 */
class ParticleBurst(
    val spec: ParticleSpec,
    seed: ULong,
    /** 방출구 세계 위치(모델 단위) = emitterPositionExtent × extent. */
    val emitter: Vec3,
    darkAppearance: Boolean = false,
    /** 방출구 크기 곡선(보상 흡수의 오므리기 — 시각 → 배율). 없으면 1. */
    private val emitterScaleAt: (Double) -> Double = { 1.0 },
) {
    private data class Seeded(val birth: Double, val local: Vec3, val dir: Vec3, val speed: Double, val life: Double, val size: Double, val angle: Double, val spin: Double, val argb: Int)

    private val particles: List<Seeded>

    init {
        val rng = SplitMix64(seed)
        val base = if (darkAppearance) spec.colorDark else spec.colorLight
        particles = List(spec.particleCount) { i ->
            val birth = i / spec.birthRate
            val (local, normal) = birthPoint(rng)
            // surfaceNormal = 태어난 자리의 바깥 법선. constant · random 은 emittingDirection 둘레 spreadingAngle 원뿔(random 은 180° = 온 구).
            val dir = if (spec.birthDirection == "surfaceNormal") normal else cone(spec.emittingDirection.normalized(), spec.spreadingAngleDeg, rng)
            Seeded(
                birth = birth,
                local = local,
                dir = dir,
                speed = vary(spec.velocity, spec.velocityVariation, rng),
                life = max(0.0, vary(spec.lifeSpanS, spec.lifeSpanVariation, rng)),
                size = max(0.0, vary(spec.size, spec.sizeVariation, rng)),
                angle = vary(spec.angleDeg, spec.angleVariationDeg, rng),
                spin = vary(spec.angularVelocityDegS, spec.angularVelocityVariationDegS, rng),
                argb = varyColor(base, spec.colorVariationHSBA, rng),
            )
        }
    }

    private fun vary(v: Double, variation: Double, rng: SplitMix64): Double = if (variation == 0.0) v else v + (rng.unit() - 0.5) * variation

    /** 방출구 모양 표면의 한 점과 바깥 법선(birthLocation = surface). */
    private fun birthPoint(rng: SplitMix64): Pair<Vec3, Vec3> = when (spec.shapeType) {
        "cylinder" -> {
            val a = rng.unit() * 2 * PI
            val n = Vec3(cos(a), 0.0, sin(a))
            val y = (rng.unit() - 0.5) * spec.shapeHeight
            Vec3(n.x * spec.shapeRadius, y, n.z * spec.shapeRadius) to n
        }
        else -> {
            val n = uniformSphere(rng)
            n * spec.shapeRadius to n
        }
    }

    private fun uniformSphere(rng: SplitMix64): Vec3 {
        val z = rng.unit() * 2 - 1
        val a = rng.unit() * 2 * PI
        val r = sqrt(max(0.0, 1 - z * z))
        return Vec3(r * cos(a), z, r * sin(a))
    }

    /** 축 [axis] 둘레 반각 [halfAngleDeg] 원뿔 안 고른 방향(180° = 온 구). */
    private fun cone(axis: Vec3, halfAngleDeg: Double, rng: SplitMix64): Vec3 {
        val cosMax = cos(Angles.rad(halfAngleDeg.coerceIn(0.0, 180.0)))
        val z = 1 - rng.unit() * (1 - cosMax)
        val a = rng.unit() * 2 * PI
        val r = sqrt(max(0.0, 1 - z * z))
        val t = (if (kotlin.math.abs(axis.y) < 0.9) Vec3.UP else Vec3(1.0, 0.0, 0.0)).cross(axis).normalized()
        val b = axis.cross(t)
        return (t * (r * cos(a)) + b * (r * sin(a)) + axis * z).normalized()
    }

    /** 색 변동: HSB 각 성분 ± variation/2(색상은 감고, 채도 · 명도는 0..1 로 물린다). 알파 변동 0. */
    private fun varyColor(rgba: List<Double>, v: List<Double>, rng: SplitMix64): Int {
        val (h, s, b) = rgbToHsb(rgba[0], rgba[1], rgba[2])
        val nh = (h + (rng.unit() - 0.5) * v[0]).let { it - floor(it) }
        val ns = (s + (rng.unit() - 0.5) * v[1]).coerceIn(0.0, 1.0)
        val nb = (b + (rng.unit() - 0.5) * v[2]).coerceIn(0.0, 1.0)
        val na = (rgba[3] + (rng.unit() - 0.5) * v[3]).coerceIn(0.0, 1.0)
        val (r, g, bl) = hsbToRgb(nh, ns, nb)
        fun c(x: Double) = (x * 255 + 0.5).toInt().coerceIn(0, 255)
        return (c(na) shl 24) or (c(r) shl 16) or (c(g) shl 8) or c(bl)
    }

    /** 시각 t(버스트 시작 기준 초)에 살아 있는 입자. */
    fun particlesAt(t: Double): List<Particle> {
        val out = ArrayList<Particle>()
        val a = spec.acceleration
        for ((index, p) in particles.withIndex()) {
            val age = t - p.birth
            if (age < 0 || age >= p.life) continue
            val scale = emitterScaleAt(p.birth)
            val start = emitter + p.local * scale
            val pos = start + p.dir * (p.speed * age) + a * (0.5 * age * age)
            out += Particle(index, pos, p.size, p.angle + p.spin * age, p.argb, age, p.life)
        }
        return out
    }

    /** 마지막 입자가 죽는 시각(이 뒤로 0 개). */
    val endS: Double get() = particles.maxOfOrNull { it.birth + it.life } ?: 0.0

    /**
     * 그린다 — 몸 앞뒤로 나눠(F §3.7: 입자 z 로 근사, 몸 피벗 평면 뒤면 몸보다 먼저). [front] 가 참이면 앞층만.
     * 사각형은 카메라를 향한 판(빌보드), 한 변 = size, 각 = angle.
     */
    fun draw(canvas: QuadCanvas, t: Double, camera: SceneCamera, viewportWidth: Double, viewportHeight: Double, front: Boolean) {
        val pivotZ = camera.viewZ(Vec3.ZERO)
        val right = camera.world.column(0).normalized(); val up = camera.world.column(1).normalized()
        for (p in particlesAt(t)) {
            val z = camera.viewZ(p.position)
            val inFront = z > pivotZ
            if (inFront != front) continue
            val half = p.size / 2
            val c = cos(Angles.rad(p.angleDeg)); val s = sin(Angles.rad(p.angleDeg))
            val r = right * c + up * s; val u = up * c - right * s
            val quad = listOf(-1.0 to 1.0, 1.0 to 1.0, 1.0 to -1.0, -1.0 to -1.0).map { (sx, sy) ->
                camera.project(p.position + r * (sx * half) + u * (sy * half), viewportWidth, viewportHeight)
            }
            canvas.fillQuad(quad, p.argb, spec.additive)
        }
    }

    companion object {
        fun rgbToHsb(r: Double, g: Double, b: Double): Triple<Double, Double, Double> {
            val mx = max(r, max(g, b)); val mn = min(r, min(g, b)); val d = mx - mn
            val h = when {
                d == 0.0 -> 0.0
                mx == r -> ((g - b) / d).let { if (it < 0) it + 6 else it } / 6
                mx == g -> ((b - r) / d + 2) / 6
                else -> ((r - g) / d + 4) / 6
            }
            val s = if (mx == 0.0) 0.0 else d / mx
            return Triple(h, s, mx)
        }

        fun hsbToRgb(h: Double, s: Double, v: Double): Triple<Double, Double, Double> {
            val i = floor(h * 6).toInt()
            val f = h * 6 - i
            val p = v * (1 - s); val q = v * (1 - f * s); val t = v * (1 - (1 - f) * s)
            return when (((i % 6) + 6) % 6) {
                0 -> Triple(v, t, p); 1 -> Triple(q, v, p); 2 -> Triple(p, v, t)
                3 -> Triple(p, q, v); 4 -> Triple(t, p, v); else -> Triple(v, p, q)
            }
        }
    }
}
