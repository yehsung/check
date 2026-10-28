// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (ReactionKind 우선순위·길이 · scaleKeyframe 곡선) + Sources/check/CheckCharacter3DView.swift @ 1b8260d (addIdleAnimations 부유·살랑) — 굽기(AingBakeSuite)가 motion.json · tracks/*.f32 로 녹화한 것을 읽는다
package com.yehsung.aingcheck.character.bake

import com.yehsung.aingcheck.character.bake.BakeJson.arr
import com.yehsung.aingcheck.character.bake.BakeJson.bool
import com.yehsung.aingcheck.character.bake.BakeJson.dbl
import com.yehsung.aingcheck.character.bake.BakeJson.doubles
import com.yehsung.aingcheck.character.bake.BakeJson.int
import com.yehsung.aingcheck.character.bake.BakeJson.obj
import com.yehsung.aingcheck.character.bake.BakeJson.opt
import com.yehsung.aingcheck.character.bake.BakeJson.req
import com.yehsung.aingcheck.character.bake.BakeJson.str
import com.yehsung.aingcheck.character.math.Quat
import com.yehsung.aingcheck.character.math.Vec3
import kotlin.math.floor
import kotlin.math.pow

/**
 * SceneKit 이징 곡선(굽기가 실측으로 확정 — F §3.2-4, motion.json `curves`). 입력 t ∈ [0, 1].
 * 앱의 `scaleKeyframe` 곡선(keyframe*)은 따로다(`CheckOverlayReactions.swift:2111-2132`).
 */
enum class MotionCurve(val curveName: String) {
    linear("linear"),
    easeInEaseOut("easeInEaseOut"),
    easeIn("easeIn"),
    easeOut("easeOut"),
    keyframeEaseOut("keyframeEaseOut"),
    keyframeEaseInEaseOut("keyframeEaseInEaseOut"),
    ;

    fun apply(t0: Double): Double {
        val t = t0.coerceIn(0.0, 1.0)
        return when (this) {
            linear -> t
            easeInEaseOut -> t * t * (3 - 2 * t)
            easeIn -> 2 * t * t - t * t * t
            easeOut -> 1 - (1 - t) * (1 - t) * (1 + t)
            keyframeEaseOut -> 1 - (1 - t) * (1 - t)
            keyframeEaseInEaseOut -> if (t < 0.5) 2 * t * t else 1 - (-2 * t + 2).pow(2) / 2
        }
    }

    companion object {
        fun named(name: String): MotionCurve? = entries.firstOrNull { it.curveName == name }
    }
}

/** wrapper 한 표본: 크기 · 회전 · 위치(위치 단위는 [MotionTrack.positionUnits]). */
data class PoseSample(val scale: Vec3, val rotation: Quat, val position: Vec3) {
    companion object {
        val IDENTITY = PoseSample(Vec3(1.0, 1.0, 1.0), Quat.IDENTITY, Vec3.ZERO)
    }
}

/**
 * 480Hz 녹화 트랙 하나(`float32le[count][10]` = scale xyz · quat xyzw · position xyz). 표본 사이는 위치·크기 선형, 회전 slerp.
 * 끝 뒤는 마지막 표본(대부분 단위 — drowsySink 만 끝 자세를 쥔다).
 */
class MotionTrack(
    val name: String,
    val variant: String,
    val sampleHz: Int,
    /** "extent"(모델 최장변 배수 — 재생할 캐릭터의 extent 를 곱한다) · "model"(모델 단위 그대로). */
    val positionUnits: String,
    private val data: FloatArray,
    val holdsEnd: Boolean,
) {
    val count: Int = data.size / 10
    val durationS: Double get() = (count - 1).toDouble() / sampleHz

    init {
        require(data.size % 10 == 0 && count >= 1) { "트랙 $name: 10칸 표본이 아니다(${data.size})" }
    }

    fun sampleAt(index: Int): PoseSample {
        val i = index.coerceIn(0, count - 1) * 10
        return PoseSample(
            Vec3(data[i].toDouble(), data[i + 1].toDouble(), data[i + 2].toDouble()),
            Quat(data[i + 3].toDouble(), data[i + 4].toDouble(), data[i + 5].toDouble(), data[i + 6].toDouble()),
            Vec3(data[i + 7].toDouble(), data[i + 8].toDouble(), data[i + 9].toDouble()),
        )
    }

    /** 시각 t(초, 트랙 시작 기준) → 자세. 음수는 첫 표본. */
    fun sample(t: Double): PoseSample {
        if (!(t > 0)) return sampleAt(0)
        val x = t * sampleHz
        val k = floor(x).toInt()
        if (k >= count - 1) return sampleAt(count - 1)
        val f = x - k
        val a = sampleAt(k); val b = sampleAt(k + 1)
        if (f == 0.0) return a
        return PoseSample(
            a.scale + (b.scale - a.scale) * f,
            Quat.slerp(a.rotation, b.rotation, f),
            a.position + (b.position - a.position) * f,
        )
    }

    companion object {
        /** 리틀엔디언 float32 바이트 → 트랙. */
        fun fromBytes(name: String, variant: String, sampleHz: Int, positionUnits: String, bytes: ByteArray, holdsEnd: Boolean): MotionTrack {
            require(bytes.size % 4 == 0) { "트랙 $name: 4바이트 배수가 아니다" }
            val floats = FloatArray(bytes.size / 4) { i ->
                val b = i * 4
                Float.fromBits(
                    (bytes[b].toInt() and 0xFF) or ((bytes[b + 1].toInt() and 0xFF) shl 8) or
                        ((bytes[b + 2].toInt() and 0xFF) shl 16) or ((bytes[b + 3].toInt() and 0xFF) shl 24),
                )
            }
            return MotionTrack(name, variant, sampleHz, positionUnits, floats, holdsEnd)
        }
    }
}

/** 트랙 메타(motion.json `tracks.<이름>`) — 바이트는 [MotionLibrary.loadTrack] 이 따로 읽는다(Android 기본 묶음은 트랙 2개만 싣는다). */
data class TrackInfo(
    val name: String,
    val file: String,
    val variant: String,
    val sampleHz: Int,
    val count: Int,
    val positionUnits: String,
    val holdsEnd: Boolean,
)

/** 리액션 표(`ReactionKind` 에서 읽어 냄 — 우선순위 · 길이 · 말풍선 초 · 트랙 · 현재 자세에서 단위로 가는 보간). */
data class ReactionSpec(
    val name: String,
    val priority: Int?,
    val durationS: Double?,
    val motionDurationS: Double?,
    val track: String?,
    val bubbleSeconds: Double?,
    val holdsEnd: Boolean,
    val toIdentitySeconds: Double?,
    val toIdentityCurve: MotionCurve?,
)

/** 엔진 상수(fps · 깜빡임 · 드래그 각 · 걷기 멈춤 …). */
data class EngineConstants(
    val activeFPS: Double,
    val idleFPS: Double,
    val blinkSeconds: Double,
    val dragFacingDeg: Double,
    val fpsResetAfterS: Double,
    val hitCooldownS: Double,
    val spriteTickIntervalS: Double,
    val walkStopTimeoutS: Double,
    val zzzIntervalS: Double,
)

/** idle 부유 · 살랑 — 공식으로 계산한다(Android 기본 묶음엔 idle 트랙이 없다; 공식 오차 ≤ 1e-6 는 굽기가 쟀다). */
data class IdleSpec(
    val bobAmplitudeModel: Double,
    val bobHalfPeriodS: Double,
    val swayAmplitudeRad: Double,
    val swaySegmentsS: List<Double>,
    val cycleS: Double,
) {
    /** 시각 t(초, idle 시작 기준) → (부유 y 모델 단위, 살랑 y 회전 라디안). 굽기 `idleFormula` 와 같은 식. */
    fun evaluate(t: Double): Pair<Double, Double> {
        val ease = MotionCurve.easeInEaseOut
        val period = 2 * bobHalfPeriodS
        val b = t.mod(period)
        val bob = if (b < bobHalfPeriodS) bobAmplitudeModel * ease.apply(b / bobHalfPeriodS)
        else bobAmplitudeModel * (1 - ease.apply((b - bobHalfPeriodS) / bobHalfPeriodS))
        val s = t.mod(cycleS)
        val a = swayAmplitudeRad
        val s0 = swaySegmentsS[0]; val s1 = swaySegmentsS[1]
        val sway = when {
            s < s0 -> a * ease.apply(s / s0)
            s < s0 + s1 -> a - 2 * a * ease.apply((s - s0) / s1)
            else -> -a + a * ease.apply((s - s0 - s1) / swaySegmentsS[2])
        }
        return bob to sway
    }
}

/** 방출구 위치 · 보상 흡수 오므리기(F §3.2-5, motion.json `emitters`). */
data class EmitterSpec(val name: String, val reaction: String?, val positionExtent: Vec3, val removedAtS: Double?)

/** motion.json 전체(트랙 바이트 빼고). */
class MotionLibrary(
    val sampleHz: Int,
    val extent: Double,
    val curves: List<String>,
    val reactions: List<ReactionSpec>,
    val tracks: Map<String, TrackInfo>,
    val engine: EngineConstants,
    val idle: IdleSpec,
    /** 졸기 끝 자세(drowsySink 마지막 표본). 위치는 extent 단위. */
    val sleepPose: PoseSample,
    val emitters: List<EmitterSpec>,
    /** 보상 흡수 방출구 크기(1 → 0.12, 0.7s easeIn) 480Hz 표본. */
    val ultraChargeCollapse: List<Double>,
    val ultraChargeCollapseHz: Int,
    val zzzFile: String?,
    val zzzCount: Int,
    val zzzContainerExtent: Vec3,
    val zzzScaleExtent: Double,
) {
    fun reaction(name: String): ReactionSpec? = reactions.firstOrNull { it.name == name }

    companion object {
        fun decode(text: String): MotionLibrary {
            val o = BakeJson.parse(text)
            if (o.req("format").int() != 1) throw BakeFormatException("motion 형식")
            val curves = o.req("curves").arr().map { it.obj().req("name").str() }
            val reactions = o.req("reactions").arr().map { r ->
                val ro = r.obj()
                val toId = ro.opt("toIdentity")?.obj()
                ReactionSpec(
                    name = ro.req("name").str(),
                    priority = ro.opt("priority")?.int(),
                    durationS = ro.opt("durationS")?.dbl(),
                    motionDurationS = ro.opt("motionDurationS")?.dbl(),
                    track = ro.opt("track")?.str(),
                    bubbleSeconds = ro.opt("bubbleSeconds")?.dbl(),
                    holdsEnd = ro.opt("holdsEnd")?.bool() ?: false,
                    toIdentitySeconds = toId?.req("seconds")?.dbl(),
                    toIdentityCurve = toId?.req("curve")?.str()?.let { MotionCurve.named(it) ?: throw BakeFormatException("모르는 곡선 $it") },
                )
            }
            val tracks = o.req("tracks").obj().mapValues { (name, v) ->
                val t = v.obj()
                if (t.req("layout").str() != "float32le[count][10] = scale xyz, quaternion xyzw, position xyz") throw BakeFormatException("트랙 $name 배치")
                TrackInfo(
                    name = name,
                    file = t.req("file").str(),
                    variant = t.req("variant").str(),
                    sampleHz = t.req("sampleHz").int(),
                    count = t.req("count").int(),
                    positionUnits = t.req("positionUnits").str(),
                    holdsEnd = t.opt("holdsEnd")?.bool() ?: false,
                )
            }
            val e = o.req("engine").obj()
            val engine = EngineConstants(
                activeFPS = e.req("activeFPS").dbl(), idleFPS = e.req("idleFPS").dbl(), blinkSeconds = e.req("blinkSeconds").dbl(),
                dragFacingDeg = e.req("dragFacingDeg").dbl(), fpsResetAfterS = e.req("fpsResetAfterS").dbl(),
                hitCooldownS = e.req("hitCooldownS").dbl(), spriteTickIntervalS = e.req("spriteTickIntervalS").dbl(),
                walkStopTimeoutS = e.req("walkStopTimeoutS").dbl(), zzzIntervalS = e.req("zzzIntervalS").dbl(),
            )
            val idleObj = o.req("tracks").obj().req("idle").obj()
            val bob = idleObj.req("bob").obj(); val sway = idleObj.req("sway").obj()
            val idle = IdleSpec(
                bobAmplitudeModel = bob.req("amplitudeModel").dbl(),
                bobHalfPeriodS = bob.req("halfPeriodS").dbl(),
                swayAmplitudeRad = sway.req("amplitudeRad").dbl(),
                swaySegmentsS = sway.req("segmentsS").doubles().also { if (it.size != 3) throw BakeFormatException("살랑 구간 셋") },
                cycleS = idleObj.req("cycleS").dbl(),
            )
            val sp = o.req("sleepPose").obj()
            val q = sp.req("quaternion").doubles(); val s = sp.req("scale").doubles(); val p = sp.req("positionExtent").doubles()
            val sleep = PoseSample(Vec3(s[0], s[1], s[2]), Quat(q[0], q[1], q[2], q[3]), Vec3(p[0], p[1], p[2]))
            val emittersObj = o.req("emitters").obj()
            val emitters = emittersObj.entries.filter { it.key.startsWith("check.") }.map { (name, v) ->
                val eo = v.obj()
                val pe = eo.req("positionExtent").doubles()
                EmitterSpec(name, eo.opt("reaction")?.str(), Vec3(pe[0], pe[1], pe[2]), eo.opt("removedAtS")?.dbl())
            }
            val collapse = emittersObj.opt("ultraChargeCollapse")?.obj()
            val zzz = o.opt("zzz")?.obj()
            return MotionLibrary(
                sampleHz = o.req("sampleHz").int(),
                extent = o.req("extent").dbl(),
                curves = curves,
                reactions = reactions,
                tracks = tracks,
                engine = engine,
                idle = idle,
                sleepPose = sleep,
                emitters = emitters,
                ultraChargeCollapse = collapse?.req("scale")?.doubles() ?: emptyList(),
                ultraChargeCollapseHz = collapse?.req("sampleHz")?.int() ?: 0,
                zzzFile = zzz?.req("file")?.str(),
                zzzCount = zzz?.req("count")?.int() ?: 0,
                zzzContainerExtent = zzz?.req("containerPositionExtent")?.doubles()?.let { Vec3(it[0], it[1], it[2]) } ?: Vec3.ZERO,
                zzzScaleExtent = zzz?.req("zScaleExtent")?.dbl() ?: 0.0,
            )
        }
    }
}
