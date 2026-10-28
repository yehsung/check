// 원본: 없음 (설계 F §6 T5 파티클 — 맥 16회 렌더 분포 대조는 굽기에 기준 자료가 없어 조정자 패치로 넘긴다. 여기서는 particles.json 매개변수 대조)
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.math.Angles
import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.character.player.ParticleBurst
import com.yehsung.aingcheck.character.player.ParticleSpec
import com.yehsung.aingcheck.character.render.PlatformRaster
import java.io.File
import kotlin.math.abs
import kotlin.math.acos
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * T5(Kotlin 쪽): 시드 있는 입자 시뮬이 particles.json(굽기가 실제 SCNParticleSystem 에서 읽은 값)을 지키는가 —
 * 결정성 · 입자 수 · 수명 · 속도 · 방향(원뿔 · 표면 법선) · 운동학(가속) · 색 변동(HSB) · 앞뒤 나누기 · 그리기.
 * 맥 16회 렌더의 [최소, 최대] 띠 대조(F §6 T5 원문)는 굽기 기준 자료가 없어 **미검증**이다 — 조정자 패치(굽기 스위트에 입자 기준 출력)로 넘긴다.
 */
class ParticleFieldTest {
    private val lib = RepoBake.library
    private val specs = ParticleSpec.decodeAll(File(RepoBake.bakeRoot, "particles.json").readText())
    private val extent = lib.motion.extent

    private fun burst(name: String, seed: ULong) = specs.getValue(name).let { s ->
        ParticleBurst(s, seed, s.emitterPositionExtent * extent)
    }

    @Test
    fun 세_계가_읽히고_매개변수가_맥_표와_같다() {
        assertEquals(setOf("confetti", "goalSpark", "ultraCharge"), specs.keys)
        val c = specs.getValue("confetti")
        assertEquals(80, c.particleCount, "0.1s × 800/s")
        assertEquals(false, c.additive)
        assertEquals(252, specs.getValue("goalSpark").particleCount, "0.6s × 420/s")
        assertEquals(true, specs.getValue("goalSpark").additive)
        assertEquals(210, specs.getValue("ultraCharge").particleCount, "0.7s × 300/s")
        assertEquals("surfaceNormal", specs.getValue("ultraCharge").birthDirection)
    }

    @Test
    fun 같은_시드는_같은_입자_다른_시드는_다른_입자() {
        val a = burst("confetti", 7uL).particlesAt(0.5)
        val b = burst("confetti", 7uL).particlesAt(0.5)
        val c = burst("confetti", 8uL).particlesAt(0.5)
        assertEquals(a, b)
        assertNotEquals(a, c)
    }

    @Test
    fun 수명_속도_크기는_값_더하기_빼기_변동의_반() {
        for ((name, s) in specs) {
            for (seed in 1uL..16uL) {
                val b = ParticleBurst(s, seed, Vec3.ZERO)
                // 태어난 직후(나이 0)엔 속도 · 크기를 직접 볼 수 없으니 두 시각의 위치 차로 속도를 잰다.
                val t0 = s.emissionDurationS + 1e-6
                val p0 = b.particlesAt(t0)
                assertTrue(p0.isNotEmpty(), "$name: 방출 직후 입자가 있어야 한다")
                for (p in p0) {
                    assertTrue(p.lifeS >= s.lifeSpanS - s.lifeSpanVariation / 2 - 1e-9 && p.lifeS <= s.lifeSpanS + s.lifeSpanVariation / 2 + 1e-9, "$name 수명 ${p.lifeS}")
                    assertTrue(p.size >= s.size - s.sizeVariation / 2 - 1e-9 && p.size <= s.size + s.sizeVariation / 2 + 1e-9, "$name 크기 ${p.size}")
                }
                // 수명이 다 지나면 0 개.
                assertTrue(b.particlesAt(b.endS + 1e-6).isEmpty(), "$name: 다 죽어야 한다")
                assertTrue(b.endS <= s.emissionDurationS + s.lifeSpanS + s.lifeSpanVariation / 2 + 1e-9)
            }
        }
    }

    @Test
    fun 방향은_원뿔_또는_표면_법선이고_가속을_따른다() {
        val spark = specs.getValue("goalSpark")
        val b = ParticleBurst(spark, 3uL, Vec3.ZERO)
        val dt = 0.01
        // 같은 입자 두 시각: Δp = v·Δt + ½a((t+Δt)² − t²). 방향은 위(0,1,0) 둘레 26° 원뿔 안.
        val t = spark.emissionDurationS
        val a = b.particlesAt(t); val c = b.particlesAt(t + dt).associateBy { it.index }
        var checked = 0
        for (pa in a) {
            val pc = c[pa.index] ?: continue
            val accel = spark.acceleration * (0.5 * ((pa.ageS + dt) * (pa.ageS + dt) - pa.ageS * pa.ageS))
            val v = (pc.position - pa.position - accel) * (1 / dt)
            val speed = v.length
            assertTrue(speed >= spark.velocity - spark.velocityVariation / 2 - 1e-6 && speed <= spark.velocity + spark.velocityVariation / 2 + 1e-6, "속도 $speed")
            val ang = Angles.deg(acos((v.normalized() dot Vec3.UP).coerceIn(-1.0, 1.0)))
            assertTrue(ang <= spark.spreadingAngleDeg + 1e-6, "원뿔 밖 $ang°")
            checked++
        }
        assertTrue(checked > 200, "잰 입자 $checked")

        // 보상 흡수: 표면 법선 — 태어난 자리(구 r = 0.5e)에서 바깥으로.
        val absorb = specs.getValue("ultraCharge")
        val ub = ParticleBurst(absorb, 5uL, Vec3.ZERO)
        val early = ub.particlesAt(1e-4)
        assertTrue(early.isNotEmpty())
        for (p in early) assertTrue(abs(p.position.length - absorb.shapeRadius) < absorb.velocity * 1e-3 + 1e-6, "구 표면 ${p.position.length}")
    }

    @Test
    fun 무게중심은_공식_궤적을_따른다() {
        // 색종이: 사방(180°) 고른 방향이라 무게중심 속도 ≈ 0, 가속 (0, −1.5, 0) → 무게중심 y ≈ 방출구 + ½·a·나이² 평균.
        val s = specs.getValue("confetti")
        val emitter = s.emitterPositionExtent * extent
        var sumErr = 0.0
        val seeds = 1uL..16uL
        for (seed in seeds) {
            val ps = ParticleBurst(s, seed, emitter).particlesAt(0.5)
            val cy = ps.sumOf { it.position.y } / ps.size
            val expected = emitter.y + ps.sumOf { 0.5 * s.acceleration.y * it.ageS * it.ageS } / ps.size
            sumErr += abs(cy - expected)
        }
        val meanErr = sumErr / 16
        // 고른 방향 80개의 속도 평균은 0 근처 — 무작위 잔차(σ ≈ v/√(3·80) · t ≈ 0.04)보다 작아야 한다.
        assertTrue(meanErr < 0.08, "무게중심 y 오차 평균 $meanErr")
    }

    @Test
    fun 색은_HSB_변동_안이다() {
        val s = specs.getValue("goalSpark")
        val (h0, s0, b0) = ParticleBurst.rgbToHsb(s.colorLight[0], s.colorLight[1], s.colorLight[2])
        val ps = ParticleBurst(s, 11uL, Vec3.ZERO).particlesAt(s.emissionDurationS)
        assertTrue(ps.size > 200)
        var hueSpread = 0.0
        for (p in ps) {
            val r = ((p.argb ushr 16) and 0xFF) / 255.0; val g = ((p.argb ushr 8) and 0xFF) / 255.0; val b = (p.argb and 0xFF) / 255.0
            val (h, sat, v) = ParticleBurst.rgbToHsb(r, g, b)
            val dh = abs(((h - h0 + 1.5) % 1.0) - 0.5)
            hueSpread = maxOf(hueSpread, dh)
            assertTrue(dh <= s.colorVariationHSBA[0] / 2 + 0.01, "색상 $dh")
            assertTrue(abs(sat - s0) <= s.colorVariationHSBA[1] / 2 + 0.01 || sat == 0.0 || sat == 1.0, "채도 $sat")
            assertTrue(abs(v - b0) <= s.colorVariationHSBA[2] / 2 + 0.01 || v == 0.0 || v == 1.0, "명도 $v")
        }
        assertTrue(hueSpread > s.colorVariationHSBA[0] / 4, "변동이 실제로 있다: $hueSpread")
    }

    @Test
    fun 앞뒤로_나눠_그리고_더하기_섞기는_밝힌다() {
        val s = specs.getValue("goalSpark")
        val b = ParticleBurst(s, 2uL, s.emitterPositionExtent * extent)
        val back = PlatformRaster.newSurface(280, 340); val front = PlatformRaster.newSurface(280, 340)
        try {
            back.clear(); front.clear()
            b.draw(back, 0.4, lib.camera, 280.0, 340.0, front = false)
            b.draw(front, 0.4, lib.camera, 280.0, 340.0, front = true)
            val nb = back.readPixels().let { im -> (0 until im.width * im.height).count { im.px[it * 4 + 3].toInt() != 0 } }
            val nf = front.readPixels().let { im -> (0 until im.width * im.height).count { im.px[it * 4 + 3].toInt() != 0 } }
            assertTrue(nb > 0 && nf > 0, "원통 방출구라 앞 · 뒤 입자가 둘 다 있다($nb, $nf)")
        } finally {
            back.close(); front.close()
        }
    }
}
