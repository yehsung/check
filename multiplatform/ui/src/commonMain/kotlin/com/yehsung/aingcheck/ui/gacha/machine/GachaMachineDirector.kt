// 원본: Sources/CheckCore/GachaMachine/GachaMachineDirector.swift @ 3bd04bd
//
// 기계의 감독(상태 + 시간표). 화면은 `now` 를 받아 그림만 그리고, 상태는 전부 여기서 바뀐다.
//
// 시간에 기대는 전이(자동 회전 끝 → 커밋, 실패 2.4초 → 처음으로, [한 번 더] 0.42초 → 자동 회전, 장면이 멎는 순간)는 **시계(clock)와
// [GachaMachineDirector.advance]** 로 일어난다. 앱에서는 감독이 다음 할 일 시각에 스스로 깨어 advance 를 부르고, 시험은 시계를 손으로
// 넘기며 같은 함수를 부른다 — 상태 기계를 화면 없이 몬다.
//
// 이식 차이(Kotlin): 시각은 Date 대신 **초(Double, 단조 시계)**다. `pull` 은 호출부가 준 코루틴 범위에서 돈다(Swift `Task { @MainActor }`).
// 씨앗 · 반전 확률 주사위는 주입한다(시험이 프레임을 재현한다 — Swift 는 UInt64.random · Double.random).
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

// MARK: - 수학 도우미

object GMath {
    fun clamp01(x: Double): Double = min(1.0, max(0.0, x))
    fun lerp(a: Double, b: Double, t: Double): Double = a + (b - a) * t
    fun lerp(a: Offset, b: Offset, t: Double): Offset = Offset(lerp(a.x.toDouble(), b.x.toDouble(), t).toFloat(), lerp(a.y.toDouble(), b.y.toDouble(), t).toFloat())

    /** a…b 구간에서 0→1 로 부드럽게(smoothstep — **움직임 전용**, 불투명도는 [GachaFade]). */
    fun smooth(a: Double, b: Double, x: Double): Double {
        val t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t)
    }

    /** a…b 구간에서 0→1 로 곧게(선형). */
    fun ramp(a: Double, b: Double, x: Double): Double = clamp01((x - a) / (b - a))
    fun easeOutCubic(t: Double): Double { val u = 1 - clamp01(t); return 1 - u * u * u }
    fun easeInCubic(t: Double): Double { val u = clamp01(t); return u * u * u }
    fun easeInOutCubic(t: Double): Double {
        val u = clamp01(t); return if (u < 0.5) 4 * u * u * u else 1 - (-2 * u + 2).pow(3) / 2
    }

    fun easeOutBack(t: Double, s: Double = 1.7): Double {
        val u = clamp01(t) - 1; return 1 + (s + 1) * u * u * u + s * u * u
    }

    /** 감쇠 스프링 계단 응답: t<0 → 0, 이후 1 로 수렴(ζ<1 이면 넘쳤다 돌아온다). */
    fun spring(t: Double, zeta: Double, freq: Double): Double {
        if (t <= 0) return 0.0
        val w = 2 * PI * freq
        val z = min(zeta, 0.999)
        val wd = w * sqrt(1 - z * z)
        return 1 - exp(-z * w * t) * (cos(wd * t) + z / sqrt(1 - z * z) * sin(wd * t))
    }

    /** 감쇠 사인: 쳤을 때의 떨림. */
    fun ring(t: Double, freq: Double, decay: Double): Double {
        if (t < 0) return 0.0
        return exp(-decay * t) * sin(2 * PI * freq * t)
    }

    fun ringCos(t: Double, freq: Double, decay: Double): Double {
        if (t < 0) return 0.0
        return exp(-decay * t) * cos(2 * PI * freq * t)
    }

    fun bezier(p0: Offset, c: Offset, p1: Offset, t: Double): Offset {
        val u = 1 - t
        return Offset(
            (u * u * p0.x + 2 * u * t * c.x + t * t * p1.x).toFloat(),
            (u * u * p0.y + 2 * u * t * c.y + t * t * p1.y).toFloat(),
        )
    }

    /** `1 - smooth(a, b, x)` 를 0…x 로 적분한 값 — 잦아드는 회전(속도 × 봉투)의 각도. x ≥ b 면 상수. */
    fun fadeIntegral(a: Double, b: Double, x: Double): Double {
        if (x <= a) return max(0.0, x)
        val w = b - a
        val u = clamp01((x - a) / w)
        return a + w * u - w * (u * u * u - u * u * u * u / 2)
    }
}

/** 시드 고정 난수(연출 모양을 뽑기마다 바꾸되, 정지 화면은 재현 가능하게). Swift `GRandom`(SplitMix64) 그대로. */
class GRandom(seed: ULong) {
    private var state: ULong = seed + 0x9E3779B97F4A7C15uL

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    fun unit(): Double = (next() shr 11).toDouble() / (1uL shl 53).toDouble()
    fun range(a: Double, b: Double): Double = a + (b - a) * unit()
    fun sign(): Double = if (unit() < 0.5) -1.0 else 1.0
}

// MARK: - 배치(설계 좌표 380×460)

object GLayout {
    val size = Size(380f, 460f)
    const val midX = 190f

    /** 몸통 그림(720×614 px)을 폭 260pt 로: k = 260/720. */
    const val bodyK = 260f / 720f
    val bodyOrigin = Offset(60f, 183f)
    val bodySize = Size(260f, 614f * bodyK)

    val domeCenter = Offset(190f, 138f)
    const val domeR = 96f
    val capRect = Rect(142f, 12.5f, 142f + 96f, 12.5f + 39.2f)

    /** 손잡이 소켓 중심(그림 358,222 px). */
    val knobCenter = Offset(60f + 358f * bodyK, 183f + 222f * bodyK)
    const val knobR = 31f
    const val notchR = 41f

    /** 배출구 안쪽(그림 x233–490, y333–535 px). */
    val chuteRect = Rect(60f + 233f * bodyK, 183f + 333f * bodyK, 60f + 490f * bodyK, 183f + 535f * bodyK)
    val chuteInside: Offset get() = Offset(chuteRect.center.x, chuteRect.center.y + 6f)
    val tray = Offset(190f, 392f)

    /** 배출구 덮개(그림 x229–490, y329–424 px). 경첩은 위 가장자리다. */
    val flapArt = Rect(229f, 329f, 229f + 261f, 329f + 95f)
    val flapRect: Rect
        get() = Rect(
            bodyOrigin.x + flapArt.left * bodyK, bodyOrigin.y + flapArt.top * bodyK,
            bodyOrigin.x + flapArt.right * bodyK, bodyOrigin.y + flapArt.bottom * bodyK,
        )
    const val flapCorner = 26f * bodyK

    val stageCenter = Offset(190f, 196f)
    const val capsuleSmall = 36f
    const val capsuleBig = 112f

    val shardChip = Offset(54f, 24f)
    val rubyChip = Offset(322f, 24f)
    const val hintY = 436f
}

// MARK: - 시간표

data class GDropTimes(val emerge0: Double, val emerge1: Double, val land: Double, val jump0: Double, val jump1: Double, val total: Double) {
    companion object {
        val normal = GDropTimes(0.02, 0.26, 0.24, 0.44, 0.88, 0.94)
        val gold = GDropTimes(0.40, 0.66, 0.64, 0.86, 1.34, 1.40)

        /** 동작 줄이기: 배출구에서 미끄러져 나와(튀지 않음) 잠깐 머문 뒤 바로 공개로 넘어간다. */
        val reduced = GDropTimes(0.0, 0.35, 0.35, 0.85, 0.85, 0.85)
    }
}

object GTiming {
    const val minShake = 0.70
    const val kickEvery = 0.55
    const val autoTurn = 0.95
    const val goldBuild = 0.80
    const val failHold = 2.4
    const val againDelay = 0.42
    const val badgeAt = 0.36
    const val nameAt = 0.50
    const val dupCondense0 = 1.25
    const val dupCondense1 = 1.80
    const val dupFly1 = 2.35
    const val goldTitleAt = 0.85
    const val goldSubAt = 1.20

    fun buttonsAt(kind: GachaRevealKind): Double = when (kind) {
        GachaRevealKind.New -> 0.95
        GachaRevealKind.Duplicate -> 2.25
        GachaRevealKind.Gold, GachaRevealKind.Rainbow -> 2.40
    }

    /** 조각 칩이 올라가는 때(공개 기준). 조각을 안 받았으면 null. */
    fun shardLandAt(outcome: GachaRevealOutcome, reduced: Boolean): Double? = when (outcome.kind) {
        GachaRevealKind.Duplicate -> if (reduced) Reduced.dupSwap else dupFly1
        GachaRevealKind.Gold, GachaRevealKind.Rainbow -> if (outcome.shardsGained > 0) (if (reduced) Reduced.nameAt + 0.6 else goldSubAt + 0.2) else null
        GachaRevealKind.New -> null
    }

    /** 공개 뒤 한 번 일어나는 움직임이 모두 끝나는 때. */
    fun revealOneShotEnd(kind: GachaRevealKind): Double = when (kind) {
        GachaRevealKind.New -> 1.6
        GachaRevealKind.Duplicate -> 3.9
        GachaRevealKind.Gold, GachaRevealKind.Rainbow -> 2.9
    }

    /** 동작 줄이기(흔들기·튀기·입자 없음 — 떨어짐 → 겹쳐 바뀌는 공개). */
    object Reduced {
        const val badgeAt = 0.15
        const val nameAt = 0.20
        const val fade = 0.35
        const val dupSwap = 1.0
        fun buttonsAt(kind: GachaRevealKind): Double = when (kind) {
            GachaRevealKind.New -> 0.6
            GachaRevealKind.Duplicate -> 1.35
            GachaRevealKind.Gold, GachaRevealKind.Rainbow -> 1.0
        }

        fun oneShotEnd(kind: GachaRevealKind): Double = buttonsAt(kind) + 0.5
    }

    /** 잔잔한 움직임은 마지막 일 뒤 이만큼 이어지다 잦아든다. 잦아든 뒤엔 매 프레임 그리지 않는다. */
    const val ambientGrace = 6.0
    const val ambientFade = 0.8
    const val revealAmbientGrace = 2.5
}

// MARK: - 단계

sealed interface GPhase {
    val key: Int

    data object Idle : GPhase { override val key = 0 }

    /** 한 바퀴 뒤(t = 커밋 후 시간). */
    data class Shaking(val t: Double, val pending: Boolean) : GPhase { override val key = 1 }
    data class Dropping(val t: Double) : GPhase { override val key = 2 }
    data class Tapping(val taps: Int) : GPhase { override val key = 3 }

    /** 희귀(황금 · 무지개)만: 터지기 전 모으기. */
    data class Building(val t: Double) : GPhase { override val key = 4 }
    data class Reveal(val t: Double) : GPhase { override val key = 5 }
    data class Failed(val t: Double) : GPhase { override val key = 6 }

    companion object {
        const val REVEAL_KEY = 5
    }
}

/** 시간에서 파생되는 '박자' — 바뀌는 순간 햅틱을 낸다. */
data class GBeats(
    val phaseKey: Int = 0,
    val kicks: Int = 0,
    val landed: Boolean = false,
    val shardLanded: Boolean = false,
    /** 자동 회전 중에 지난 톱니 수(-1 = 자동 회전 아님). */
    val autoNotch: Int = -1,
)

// MARK: - 호스트 값(화면이 매 그리기마다 넘긴다)

data class GachaMachineEnv(
    val balance: Long,
    val cost: Long,
    val shards: Long,
    val art: GachaMachineArt,
    val teaseChance: Double,
    val haptics: GachaMachineHaptics,
    val pull: suspend () -> GachaRevealOutcome,
    val onAgain: () -> Unit = {},
    val onClose: () -> Unit = {},
    /** 호스트가 막은 이유(업데이트 필요 · 서버에 뽑기 없음 …). 있으면 손잡이가 안 돌고 이 줄이 뜬다. */
    val blockedReason: String? = null,
    /** [한 번 더] 를 받을까. */
    val againEnabled: Boolean = true,
    val isActive: Boolean = true,
    val reduceMotion: Boolean = false,
) {
    val canPay: Boolean get() = balance >= cost
    val canPull: Boolean get() = canPay && blockedReason == null
}

// MARK: - 감독

/**
 * @param clock 단조 시계(초). 앱 = 프레임 시계와 같은 축, 시험 = 손으로 넘기는 값.
 * @param scope `pull` 과 스스로 깨어나기를 띄우는 범위(화면의 범위 — 화면이 사라지면 깨우기가 끊긴다. 서버 일은 호스트 스토어의 일이다).
 * @param seedSource 판마다 연출 모양(캡슐 색 · 금)을 고르는 씨앗.
 * @param random 반전(tease) 주사위 0…1.
 */
class GachaMachineDirector(
    var clock: () -> Double,
    private val scope: CoroutineScope,
    private val seedSource: () -> ULong = { Random.nextLong().toULong().coerceAtLeast(1uL) },
    private val random: () -> Double = { Random.nextDouble() },
) {
    var env: GachaMachineEnv? = null
        private set

    /** 앱: 다음 할 일 시각에 스스로 깨어난다. 시험은 끄고 advance 를 손으로 부른다. */
    var autoSchedule = true
    private var wakeJob: Job? = null

    // 손잡이
    var angle by mutableStateOf(0.0)
    var dragging by mutableStateOf(false)
    private var pointerAngle: Double? = null
    private var dragMoved = false
    var lastNotch by mutableStateOf(0)
    var tickTime by mutableStateOf<Double?>(null)
    var releaseAngle by mutableStateOf(0.0)
    var releaseTime by mutableStateOf<Double?>(null)
    var refuseTime by mutableStateOf<Double?>(null)
    var autoTurnStart by mutableStateOf<Double?>(null)
    var autoTurnFrom by mutableStateOf(0.0)
    var autoTurnDuration by mutableStateOf(0.0)
    var touchedHandle by mutableStateOf(false)

    // 뽑기
    var commitTime by mutableStateOf<Double?>(null)
    var result by mutableStateOf<GachaRevealOutcome?>(null)
    /** 결과가 올 때마다 1 오르는 공개 번호(공개 자리의 살아 있는 미리보기가 새 값마다 한 바퀴 돈다 — `MeLiveOrPortrait(revealSerial)`). */
    var revealSerial: Int = 0
        private set
    var dropStart by mutableStateOf<Double?>(null)
    private var skipWhenReady = false
    var tease by mutableStateOf(false)
    var tapTimes by mutableStateOf<List<Double>>(emptyList())
    var burstTime by mutableStateOf<Double?>(null)
    var failTime by mutableStateOf<Double?>(null)
    var failText by mutableStateOf("")
    var seed by mutableStateOf(7uL)
    var returnTime by mutableStateOf<Double?>(null)
    var outgoing by mutableStateOf<GachaRevealOutcome?>(null)
    var outgoingTime by mutableStateOf<Double?>(null)
    var againAt by mutableStateOf<Double?>(null)
    var arrivedAt by mutableStateOf<Double?>(null)
    var pressing by mutableStateOf(false)

    /** 다시 보이기 시작한 순간의 박자(멈춘 동안 지나간 박자로 햅틱을 몰아 내지 않는다). */
    private var resyncBase: GBeats? = null
    private var wasActive = true

    /** 안 보이기 시작한 때(보이면 null). */
    var hiddenSince: Double? = null
        private set

    /** 이번 판이 동작 줄이기로 도는가(커밋 순간의 설정을 쥔다). */
    var reduced by mutableStateOf(false)

    /** 마지막으로 무슨 일이 있었던 때. */
    var lastEvent by mutableStateOf(clock())

    /** 지금 매 프레임 그려야 하는가(아니면 프레임 시계를 멈춘다). */
    var framesWanted by mutableStateOf(true)

    /** pull 이 돌고 있는가(돌고 있으면 새 판을 못 시작한다 — 두 번 깎이지 않게). */
    var pullInFlight by mutableStateOf(false)
        private set

    /** 지금까지 부른 pull 횟수(시험이 "한 판에 한 번"을 잰다). */
    var pullCount = 0
        private set
    var pullJob: Job? = null
        private set

    /** 판 번호 — 판이 바뀐 뒤 늦게 온 결과는 버린다. */
    private var turn = 0

    val isGold: Boolean get() = result?.kind == GachaRevealKind.Gold

    /** 희귀 공개(황금 · 무지개)인가. 시간표 · 반전 · 어둠 · 섬광이 이 값으로 갈린다. */
    val isRare: Boolean get() = result?.kind?.isRare == true

    /** 희귀 공개의 빛깔(평범하면 null). */
    val rare: GRare? get() = result?.let { GRare.of(it.kind) }
    val drop: GDropTimes get() = if (reduced) GDropTimes.reduced else if (isRare && !tease) GDropTimes.gold else GDropTimes.normal
    val goldBuild: Double get() = if (isRare && !reduced) GTiming.goldBuild else 0.0

    // MARK: 단계 판정(순수)

    fun phase(now: Double): GPhase {
        val commit = commitTime ?: return GPhase.Idle
        failTime?.let { return GPhase.Failed(now - it) }
        val tc = now - commit
        val ds = dropStart
        if (ds == null || now < ds) return GPhase.Shaking(tc, result == null)
        val td = now - ds
        if (td < drop.total) return GPhase.Dropping(td)
        val b = burstTime
        if (b == null || now < b) return GPhase.Tapping(tapTimes.size)
        val tb = now - b
        if (tb < goldBuild) return GPhase.Building(tb)
        return GPhase.Reveal(tb - goldBuild)
    }

    fun buttonsAt(kind: GachaRevealKind): Double = if (reduced) GTiming.Reduced.buttonsAt(kind) else GTiming.buttonsAt(kind)

    /** 공개가 자리 잡았는가(버튼이 떴다) — [한 번 더] 는 이때부터만 받는다. */
    fun revealSettled(now: Double): Boolean {
        val ph = phase(now) as? GPhase.Reveal ?: return false
        val r = result ?: return false
        return ph.t >= buttonsAt(r.kind)
    }

    /** 루비가 나간(나가는 중인) 판의 결과를 사용자가 아직 못 봤다 — 왕복 중 · 공개 전 · 안 보이는 동안 공개가 자리 잡음. */
    fun hasUnrevealedTurn(now: Double): Boolean {
        if (pullInFlight) return true
        if (commitTime == null || failTime != null) return false
        val r = result ?: return false
        val b = burstTime ?: return true
        val settledAt = b + goldBuild + buttonsAt(r.kind)
        if (now < settledAt) return true
        hiddenSince?.let { return settledAt > it }
        return false
    }

    /** 덜컹 시각들(커밋 0 + 기다리는 동안 kickEvery 마다). */
    fun kickTimes(now: Double): List<Double> {
        val commit = commitTime ?: return emptyList()
        val tc = now - commit
        var end = tc
        dropStart?.let { end = min(end, it - commit) }
        failTime?.let { end = min(end, it - commit) }
        val out = mutableListOf(0.0)
        var k = GTiming.minShake * 0.78
        while (k < end - 0.02) { out += k; k += GTiming.kickEvery }
        return out
    }

    fun beats(now: Double): GBeats {
        val ph = phase(now)
        var landed = false
        dropStart?.let { landed = now - it >= drop.land }
        var shardLanded = false
        val r = result
        if (ph is GPhase.Reveal && r != null) {
            GTiming.shardLandAt(r, reduced)?.let { shardLanded = ph.t >= it }
        }
        val notch = if (autoTurnStart != null) (knobAngle(now) / 45).toInt() else -1
        return GBeats(ph.key, kickTimes(now).size, landed, shardLanded, notch)
    }

    // MARK: 손잡이 각도(표시)

    fun autoTurnProgress(now: Double): Double? {
        val s = autoTurnStart ?: return null
        return min(1.0, max(0.0, (now - s) / max(0.01, autoTurnDuration)))
    }

    fun knobAngle(now: Double): Double {
        if (commitTime != null) return 360.0
        var a = angle
        val p = autoTurnProgress(now)
        val rt = releaseTime
        if (p != null) {
            // 손으로 돌리듯: 천천히 시작해 붙었다가 끝에서 살짝 늦춘다
            val e = if (p < 0.5) 2 * p * p else 1 - (-2 * p + 2).pow(2) / 2
            a = autoTurnFrom + (360 - autoTurnFrom) * e
        } else if (!dragging && rt != null) {
            val t = now - rt
            // 동작 줄이기: 튕기지 않고 미끄러져 돌아온다
            val k = if (env?.reduceMotion == true) GMath.easeOutCubic(t / 0.35) else GMath.spring(t, 0.62, 1.8)
            a = releaseAngle * (1 - k)
        }
        val rf = refuseTime
        if (rf != null && env?.reduceMotion != true) a += 9 * GMath.ring(now - rf, 5.5, 5.0)
        return a
    }

    fun knobPop(now: Double): Double {
        val tt = tickTime ?: return 1.0
        if (env?.reduceMotion == true) return 1.0
        val t = now - tt
        if (t >= 0.2) return 1.0
        return 1 + 0.075 * sin(PI * min(1.0, t / 0.17))
    }

    val dropPair: Int get() = (GRandom(seed).next() % GPalette.capsulePairs.size.toULong()).toInt()

    // MARK: 잔잔한 움직임의 봉투(1 → 0 으로 잦아든다)

    /** 이 단계의 잔잔한 움직임 크기. 0 이면 정지 화면이다. */
    fun ambient(now: Double): Double {
        if (reduced || env?.reduceMotion == true) return 0.0
        return when (val ph = phase(now)) {
            is GPhase.Reveal -> {
                val r = result ?: return 0.0
                val end = GTiming.revealOneShotEnd(r.kind) + GTiming.revealAmbientGrace
                1 - GMath.smooth(end, end + GTiming.ambientFade, ph.t)
            }
            GPhase.Idle, is GPhase.Tapping -> {
                val s = now - lastEvent
                1 - GMath.smooth(GTiming.ambientGrace, GTiming.ambientGrace + GTiming.ambientFade, s)
            }
            else -> 1.0
        }
    }

    /**
     * [ambient] 의 **직선** 판 — 불투명도에 거는 자리(유리 광택 · 힌트 호의 흐르는 토막 · 금 캡슐 숨결)만 이것을 쓴다([GachaFade]).
     * 끝점(잦아들기 시작 · 다 잦아듦)은 같고 그 사이만 곧게 내린다.
     */
    fun ambientLinear(now: Double): Double {
        if (reduced || env?.reduceMotion == true) return 0.0
        return when (val ph = phase(now)) {
            is GPhase.Reveal -> {
                val r = result ?: return 0.0
                val end = GTiming.revealOneShotEnd(r.kind) + GTiming.revealAmbientGrace
                GachaFade.fall(end, end + GTiming.ambientFade, ph.t)
            }
            GPhase.Idle, is GPhase.Tapping -> GachaFade.fall(GTiming.ambientGrace, GTiming.ambientGrace + GTiming.ambientFade, now - lastEvent)
            else -> 1.0
        }
    }

    // MARK: 언제 멎는가

    /** 지금 상태 그대로 두면 화면이 더는 안 바뀌기 시작하는 시각. null = 계속 그려야 한다(기다림 · 떨어짐 …). */
    fun quietAt(now: Double): Double? {
        if (dragging || autoTurnStart != null || againAt != null || pressing) return null
        var t = Double.NEGATIVE_INFINITY
        fun upTo(d: Double?) { if (d != null && d > t) t = d }
        val reduce = env?.reduceMotion == true
        when (phase(now)) {
            GPhase.Idle -> {
                upTo(releaseTime?.plus(1.6))
                upTo(refuseTime?.plus(1.4))
                upTo(tickTime?.plus(0.25))
                upTo(returnTime?.plus(0.6))
                upTo(outgoingTime?.plus(0.4))
                if (!reduce) upTo(lastEvent + GTiming.ambientGrace + GTiming.ambientFade)
            }
            is GPhase.Tapping -> {
                tapTimes.lastOrNull()?.let { upTo(it + 1.2) }
                dropStart?.let { upTo(it + drop.total + 1.2) }
                if (!reduce && !reduced) upTo(lastEvent + GTiming.ambientGrace + GTiming.ambientFade)
            }
            is GPhase.Reveal -> {
                val r = result ?: return null
                val b = burstTime ?: return null
                val start = b + goldBuild
                if (reduced || reduce) {
                    upTo(start + GTiming.Reduced.oneShotEnd(r.kind))
                } else {
                    upTo(start + GTiming.revealOneShotEnd(r.kind) + GTiming.revealAmbientGrace + GTiming.ambientFade)
                }
            }
            is GPhase.Shaking, is GPhase.Dropping, is GPhase.Building, is GPhase.Failed -> return null
        }
        return t + 0.05
    }

    // MARK: 시간 전이

    /** 시계가 [now] 에 왔을 때 할 일을 한다(자동 회전 끝 → 커밋, 실패 → 처음으로, [한 번 더] → 자동 회전, 멎기). */
    fun advance(now: Double) {
        // 안 보이는 기계는 저절로 돌지 않는다 — 호스트가 isActive 를 내렸으면 커밋 전 예약을 거둔다.
        if (env?.isActive == false) cancelPendingTurn(now)
        val s = autoTurnStart
        if (s != null && now >= s + autoTurnDuration) {
            autoTurnStart = null
            angle = 360.0
            commit(now)
        }
        val a = againAt
        if (a != null && now >= a) {
            againAt = null
            autoTurn(now)
        }
        val f = failTime
        if (f != null && now >= f + GTiming.failHold) resetPull(now)
        val quiet = quietAt(now)
        val want = quiet?.let { now < it } ?: true
        if (framesWanted != want) framesWanted = want
        reschedule(now)
    }

    /** 다음에 깨어날 시각. */
    fun nextWake(now: Double): Double? {
        val candidates = mutableListOf<Double>()
        autoTurnStart?.let { candidates += it + autoTurnDuration }
        againAt?.let { candidates += it }
        failTime?.let { candidates += it + GTiming.failHold }
        if (framesWanted) candidates += quietAt(now) ?: (now + 0.5)
        return candidates.minOrNull()
    }

    private fun reschedule(now: Double) {
        wakeJob?.cancel()
        wakeJob = null
        if (!autoSchedule) return
        val wake = nextWake(now) ?: return
        val delayMs = max(1L, ((wake - now) * 1000).toLong())
        wakeJob = scope.launch {
            delay(delayMs)
            advance(clock())
        }
    }

    /** 무슨 일이 생겼다 — 다시 그리기 시작하고 다음 깨어날 때를 잡는다. */
    fun touched(now: Double) {
        lastEvent = now
        if (!framesWanted) framesWanted = true
        reschedule(now)
    }

    /** 화면이 사라질 때. 돌고 있는 pull 은 끊지 않는다(서버 일은 호스트 몫이다) — 깨우기만 멈춘다. */
    fun stop() {
        wakeJob?.cancel()
        wakeJob = null
    }

    /** 안 보이게 됐다. **커밋 전** 예약(자동 회전 · [한 번 더])을 거둔다 — 안 보이는 동안 손잡이가 저절로 마저 돌아 루비를 쓰지 않게. */
    fun cancelPendingTurn(now: Double) {
        if (autoTurnStart == null && againAt == null) return
        if (autoTurnStart != null) {
            val shown = knobAngle(now)
            autoTurnStart = null
            if (shown > 0.5) { releaseAngle = shown; releaseTime = now }
            angle = 0.0
            lastNotch = 0
        }
        againAt = null
        touched(now)
    }

    // MARK: 리셋

    fun resetPull(now: Double = clock()) {
        turn += 1
        commitTime = null; result = null; dropStart = null; skipWhenReady = false
        tease = false; tapTimes = emptyList(); burstTime = null; failTime = null; reduced = false
        angle = 0.0; lastNotch = 0; releaseTime = null; tickTime = null; dragging = false
        autoTurnStart = null; againAt = null; arrivedAt = null
        pointerAngle = null
        touched(now)
    }

    // MARK: 호스트 값 · 박자

    /** 화면이 그릴 때마다 넘기는 호스트 값. */
    fun update(env: GachaMachineEnv) {
        val resumed = env.isActive && !wasActive
        if (!env.isActive && wasActive) hiddenSince = clock()
        if (env.isActive) hiddenSince = null
        wasActive = env.isActive
        this.env = env
        if (resumed) resyncBase = beats(clock())
    }

    /** 박자가 바뀐 순간의 햅틱(덜컹 · 툭 · 짠 · 조각 · 자동 회전 톱니). 결과 알림 문장은 화면이 낸다(톡백 liveRegion). */
    fun emitBeats(old: GBeats, new: GBeats, now: Double) {
        var previous = old
        resyncBase?.let { previous = it; resyncBase = null }
        val env = env ?: return
        if (!env.isActive) return
        val h = env.haptics
        if (new.kicks > previous.kicks && new.kicks > 1 && !reduced) h.play(GachaMachineHapticEvent.Rumble)
        if (new.landed && !previous.landed) h.play(GachaMachineHapticEvent.Land)
        if (new.phaseKey == GPhase.REVEAL_KEY && previous.phaseKey != new.phaseKey) {
            h.play(if (isRare) GachaMachineHapticEvent.GoldReveal else GachaMachineHapticEvent.Reveal)
        }
        if (new.shardLanded && !previous.shardLanded) h.play(GachaMachineHapticEvent.Shard)
        if (previous.autoNotch >= 0 && new.autoNotch > previous.autoNotch) {
            tickTime = now
            if (new.autoNotch < 8) h.play(GachaMachineHapticEvent.Ratchet)
        }
    }

    // MARK: 동작

    fun dragChanged(location: Offset, translation: Offset) {
        val env = env ?: return
        val now = clock()
        if (commitTime != null || autoTurnStart != null || againAt != null) return
        touchedHandle = true
        if (!env.canPull) {
            if (!dragging) { dragging = true; refuse(now) }
            return
        }
        if (!dragging) {
            val shown = max(0.0, knobAngle(now))
            dragging = true
            dragMoved = false
            angle = shown
            releaseTime = null
            lastNotch = (shown / 45).toInt()
            pointerAngle = null
            touched(now)
        }
        if (hypot(translation.x.toDouble(), translation.y.toDouble()) > 3) dragMoved = true
        val c = GLayout.knobCenter
        val dx = (location.x - c.x).toDouble()
        val dy = (location.y - c.y).toDouble()
        if (hypot(dx, dy) <= 9) return
        val a = atan2(dy, dx) * 180 / PI
        val pa = pointerAngle
        if (pa == null) { pointerAngle = a; return }
        var delta = a - pa
        while (delta > 180) delta -= 360
        while (delta < -180) delta += 360
        pointerAngle = a
        if (!dragMoved || delta <= 0) return // 톱니: 앞으로만
        angle = min(360.0, angle + min(delta, 60.0))
        notchCheck(now)
        if (angle >= 350) { angle = 360.0; commit(now) }
    }

    fun dragEnded() {
        val now = clock()
        if (!dragging) return
        dragging = false
        val env = env
        if (env == null || !env.canPull || commitTime != null) { touched(now); return }
        if (!dragMoved) { autoTurn(now); return }
        if (angle > 0.5) {
            releaseAngle = angle; releaseTime = now
            angle = 0.0; lastNotch = 0
        }
        touched(now)
    }

    /** 손잡이 끌기가 **취소됐다**. 놓은 것과 달리 클릭으로 치지 않는다(저절로 돌지 않는다 — 루비가 안 나간다). */
    fun dragCancelled() {
        val now = clock()
        if (!dragging) return
        dragging = false
        pointerAngle = null
        if (commitTime == null && angle > 0.5) {
            releaseAngle = angle; releaseTime = now
            angle = 0.0; lastNotch = 0
        }
        touched(now)
    }

    private fun notchCheck(now: Double) {
        val n = (angle / 45).toInt()
        if (n > lastNotch) {
            lastNotch = n; tickTime = now
            if (n < 8) env?.haptics?.play(GachaMachineHapticEvent.Ratchet)
        }
    }

    fun refuse(now: Double) {
        refuseTime = now
        env?.haptics?.play(GachaMachineHapticEvent.Refuse)
        touched(now)
    }

    /** 손잡이 클릭(끌지 않음) · 접근성 동작 → 저절로 한 바퀴. 끝나는 순간(advance) 커밋한다. */
    fun autoTurn(now: Double = clock()) {
        if (commitTime != null || autoTurnStart != null || pullInFlight) return
        val env = env
        if (env == null || !env.canPull) { refuse(now); return }
        val start = max(0.0, knobAngle(now))
        touchedHandle = true
        releaseTime = null
        angle = start
        lastNotch = (start / 45).toInt()
        autoTurnFrom = start
        var duration = max(0.15, GTiming.autoTurn * (360 - start) / 360)
        if (env.reduceMotion) duration = min(duration, 0.45)
        autoTurnDuration = duration
        autoTurnStart = now
        touched(now)
    }

    /** 한 바퀴를 다 돌렸다 → pull 을 **한 번** 부른다. */
    fun commit(now: Double = clock()) {
        if (commitTime != null || pullInFlight) return
        val env = env
        if (env == null || !env.canPull) { refuse(now); angle = 0.0; return }
        commitTime = now
        reduced = env.reduceMotion
        seed = seedSource()
        angle = 360.0
        dragging = false
        autoTurnStart = null
        result = null; dropStart = null; tapTimes = emptyList(); burstTime = null; failTime = null
        tease = false; skipWhenReady = false; arrivedAt = null
        outgoing = null
        returnTime = null
        env.haptics.play(GachaMachineHapticEvent.Commit)
        touched(now)
        turn += 1
        val myTurn = turn
        val pull = env.pull
        pullInFlight = true
        pullCount += 1
        pullJob = scope.launch {
            try {
                val r = pull()
                pullInFlight = false
                if (turn != myTurn || commitTime == null) return@launch
                arrive(r, clock())
            } catch (e: CancellationException) {
                pullInFlight = false
                throw e
            } catch (e: Throwable) {
                pullInFlight = false
                if (turn != myTurn || commitTime == null) return@launch
                fail((e as? GachaRevealFailure)?.message ?: GachaMachineText.pullFailed, clock())
            }
        }
    }

    fun arrive(r: GachaRevealOutcome, now: Double) {
        result = r
        revealSerial++
        arrivedAt = now
        val teaseChance = env?.teaseChance ?: 0.0
        tease = !reduced && r.kind.isRare && random() < teaseChance
        val commit = commitTime ?: return
        val earliest = commit + GTiming.minShake
        val ds = if (skipWhenReady) now - drop.total else max(now, earliest)
        dropStart = ds
        // 톡톡 없이 떨어짐 → 겹쳐 바뀌는 공개
        if (reduced) burstTime = ds + drop.total
        touched(now)
    }

    fun fail(message: String, now: Double) {
        failTime = now
        failText = message
        env?.haptics?.play(GachaMachineHapticEvent.Refuse)
        touched(now)
    }

    /** 화면 아무 데나 누름: 자동 구간은 빨리 감기, 톡톡 구간은 톡. */
    fun press(now: Double = clock()) {
        when (val ph = phase(now)) {
            is GPhase.Shaking -> {
                if (ph.pending) skipWhenReady = true else dropStart = now - drop.total
                val ds = dropStart
                if (reduced && ds != null && !ph.pending) burstTime = ds + drop.total
            }
            is GPhase.Dropping -> {
                dropStart = now - drop.total
                if (reduced) burstTime = now
            }
            is GPhase.Tapping -> crackTap(ph.taps, now)
            is GPhase.Building -> burstTime = now - GTiming.goldBuild
            is GPhase.Reveal -> {
                val r = result ?: return
                val b = burstTime ?: return
                val target = buttonsAt(r.kind) + if (r.kind == GachaRevealKind.Duplicate && !reduced) 0.15 else 0.0
                if (ph.t < target - 0.05) burstTime = b - (target - ph.t)
            }
            else -> return
        }
        touched(now)
    }

    /** 누름이 끝났다(누르는 동안엔 멎지 않는다). */
    fun pressEnded() {
        pressing = false
        touched(clock())
    }

    private fun crackTap(n: Int, now: Double) {
        if (n >= 3) return
        val last = tapTimes.lastOrNull()
        if (last != null && now - last < 0.11) return
        tapTimes = tapTimes + now
        val k = tapTimes.size
        env?.haptics?.play(GachaMachineHapticEvent.Tap(k))
        if (k == 2 && tease) env?.haptics?.play(GachaMachineHapticEvent.GoldFlip)
        if (k >= 3) burstTime = now
    }

    fun skipTaps(now: Double = clock()) {
        if (phase(now) !is GPhase.Tapping) return
        burstTime = if (isRare) now - goldBuild else now
        touched(now)
    }

    /** [한 번 더]. 공개가 자리 잡은 뒤에만 받는다 — 0.42초 뒤 손잡이가 저절로 돈다(그때 pull). */
    fun again(now: Double = clock()) {
        if (!revealSettled(now) || pullInFlight || againAt != null) return
        val env = env
        if (env == null || !env.canPull || !env.againEnabled) { refuse(now); return }
        outgoing = result
        outgoingTime = now
        resetPull(now)
        returnTime = now
        env.onAgain()
        againAt = now + GTiming.againDelay
        touched(now)
    }

    companion object {
        /** 배출구 덮개(0 닫힘 … 1 활짝, 음수 = 안쪽으로 살짝 넘어감). 떨어지는 단계 밖에서는 늘 0. */
        fun flapOpen(td: Double, drop: GDropTimes, reduced: Boolean): Double {
            val opened = GMath.easeOutCubic(GMath.ramp(drop.emerge0 - 0.05, drop.emerge0 + 0.07, td))
            val closeStart = drop.emerge1 - 0.02
            if (td < closeStart) return opened
            val tau = td - closeStart
            if (reduced) return 1 - GMath.smooth(0.0, 0.25, tau)
            if (tau < 0.12) return 1 - GMath.easeInCubic(tau / 0.12)
            return -0.16 * GMath.ring(tau - 0.12, 4.0, 9.0)
        }
    }
}
