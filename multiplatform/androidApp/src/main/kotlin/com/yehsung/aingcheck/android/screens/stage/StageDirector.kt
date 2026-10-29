// 원본: Sources/check/CheckOverlayReactions.swift @ 3bd04bd (ReactionEngine.request — 우선순위 거절 · hit 쿨다운 0.6s · 상태 만료는 리액션 길이(벽시계). 무대가 쓰는 hit · greeting 둘만 부분 이식)
// 원본: Sources/check/CheckOverlayWindow.swift @ 3bd04bd (startBlinkScheduler — 표시 중 3~7초마다 engine.blink())
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.player.CharacterFrames
import com.yehsung.aingcheck.character.player.CharacterPlayer
import kotlin.random.Random

/** 무대 탭 결과(시험 · 접근성 · 호출부 진동). */
enum class TapOutcome {
    /** 몸에 맞았고 hit 를 걸었다. */
    hit,
    /** 몸 밖(투영 상자 + 여백 밖이거나 칸 알파 ≤ 32). */
    missed,
    /** 지난 hit 로부터 0.6s 안(맥 hitCooldown). */
    cooldown,
    /** 같거나 높은 우선순위 리액션이 아직 살아 있다(맥 `kind.priority <= active.priority`). */
    busy,
    /** 묶음에 트랙이 없다 · 정지 중 — 모션 없이 거절(재생기 `play` 가 false). */
    noMotion,
}

/**
 * 살아 있는 미리보기 한 칸의 연출 감독(시계를 읽지 않는다 — 모든 호출이 단조 `now` 초를 받는다).
 * 재생기(W5-a [CharacterPlayer])가 노드 일을, 이 감독이 맥 `ReactionEngine` 가운데 무대가 쓰는 몫을 쥔다:
 *  - 탭 → 몸 판정(F §5.3: 투영 상자 + 여백 → 칸 알파 > 32) → hit. 쿨다운 0.6s, 살아 있는 리액션보다 우선순위가 높을 때만(인사 1 < hit 3).
 *  - 공개 → 인사 한 번([StagePolicy.REVEAL_REACTION]). 맥은 바쁘면 버리지만 무대의 공개 반응은 잃으면 안 되는 단 한 번이라
 *    바쁘면 **미뤄 두었다가** 리액션이 끝난 첫 틱에 건다(맥과 다른 점 — 의도).
 *  - 깜빡임: 3~7초 무작위 간격으로 `player.blink` (재생기가 리액션 · 정지 · 스프라이트를 거른다).
 */
class StageDirector(
    val library: BakeLibrary,
    val finish: BakedFinish,
    now: Double,
    private val random: Random = Random.Default,
) {
    val player: CharacterPlayer = CharacterPlayer(library, initialCharacterId = finish.characterId, now = now)

    /** 맥 `activeKind` · `activeUntil`(벽시계 만료 — 트랙 길이가 아니라 리액션 길이 durationS). */
    var activeReaction: String? = null
        private set
    private var activeUntil = Double.NEGATIVE_INFINITY
    private var lastHitAt = Double.NEGATIVE_INFINITY
    private var pendingReveal = false
    private var nextBlinkAt: Double = now + nextBlinkInterval()
    private var lastNow = now

    /** 받아들인 탭 · 공개 수(시험 · 진단). */
    var hits: Int = 0
        private set
    var reveals: Int = 0
        private set

    val isSuspended: Boolean get() = player.isSuspended

    private fun nextBlinkInterval(): Double {
        val r = StagePolicy.BLINK_INTERVAL_S
        return r.start + random.nextDouble() * (r.endInclusive - r.start)
    }

    /** 시각은 앞으로만 간다(재생기 상태 접기가 단조 시각을 요구한다 — 탭 시각과 프레임 시각이 엇갈려도 뒤로 묻지 않게). */
    fun monotonic(now: Double): Double {
        if (now > lastNow) lastNow = now
        return lastNow
    }

    private fun expire(now: Double) {
        if (activeReaction != null && now >= activeUntil) activeReaction = null
    }

    /** 맥 request 의 우선순위 판정: 살아 있는 리액션이 있으면 더 높은 우선순위만 받는다. */
    private fun admits(name: String, now: Double): Boolean {
        expire(now)
        val active = activeReaction ?: return true
        val want = library.motion.reaction(name)?.priority ?: return false
        val have = library.motion.reaction(active)?.priority ?: return true
        return want > have
    }

    private fun start(name: String, now: Double): Boolean {
        if (!player.play(name, now)) return false
        activeReaction = name
        activeUntil = now + (library.motion.reaction(name)?.durationS ?: 0.0)
        return true
    }

    /**
     * 탭. [point] = 뷰포트 픽셀(틀 원점 기준), [frame] = 지금 그린 프레임, [marginPx] = 12pt 를 이 뷰포트 픽셀로 바꾼 값,
     * [store] = 그 마감의 칸 그림(몸 판정 — 호출부가 [StageStore.lock] 을 잡는다).
     * 맥 순서 그대로: 쿨다운 → 우선순위 → 재생.
     */
    fun tap(point: Vec2, frame: CharacterFrame?, marginPx: Double, store: StageStore, now0: Double): TapOutcome {
        val now = monotonic(now0)
        if (frame == null || !store.hitTest(frame, point, marginPx)) return TapOutcome.missed
        if (now - lastHitAt < library.motion.engine.hitCooldownS) return TapOutcome.cooldown
        if (!admits(StagePolicy.TAP_REACTION, now)) return TapOutcome.busy
        if (!start(StagePolicy.TAP_REACTION, now)) return TapOutcome.noMotion
        lastHitAt = now
        hits++
        return TapOutcome.hit
    }

    /** 뽑기 결과 공개. 바쁘면 미룬다. 걸었으면 true. */
    fun reveal(now0: Double): Boolean {
        val now = monotonic(now0)
        pendingReveal = true
        return flushReveal(now)
    }

    private fun flushReveal(now: Double): Boolean {
        if (!pendingReveal || player.isSuspended) return false
        if (!admits(StagePolicy.REVEAL_REACTION, now)) return false
        pendingReveal = false
        if (!start(StagePolicy.REVEAL_REACTION, now)) return false
        reveals++
        return true
    }

    val hasPendingReveal: Boolean get() = pendingReveal

    /**
     * 프레임마다: 깜빡임 일정 · 미뤄 둔 공개. 깜빡임은 보이는 동안만 센다(정지 중엔 일정만 미룬다 — 재개 순간 몰아 깜빡이지 않게).
     * @return 이 틱에 무엇인가 새로 걸었으면 true(활성 fps 로 올릴 신호).
     */
    fun tick(now0: Double): Boolean {
        val now = monotonic(now0)
        expire(now)
        var changed = flushReveal(now)
        if (now >= nextBlinkAt) {
            if (!player.isSuspended && player.blink(now)) changed = true
            nextBlinkAt = now + nextBlinkInterval()
        }
        return changed
    }

    /** 다음 깜빡임 시각(시험). */
    val nextBlinkTime: Double get() = nextBlinkAt

    /** 지금 그릴 프레임(뷰포트 = 틀 × 배율). 칸은 몸 px 로 고른다 — Android 묶음은 L 단뿐이라 언제나 L. */
    fun frame(now0: Double, viewportWidth: Double, viewportHeight: Double): CharacterFrame? =
        CharacterFrames.compute(player, monotonic(now0), viewportWidth, viewportHeight)

    /** 맥 fps 정책(F §5.4): 리액션 + 0.1s · 깜빡임 동안 활성 30, 나머지 유휴 6. */
    fun targetFps(now0: Double): Double {
        val now = monotonic(now0)
        val e = library.motion.engine
        return if (player.isActive(now) || pendingReveal) e.activeFPS else e.idleFPS
    }

    /** 화면에서 사라짐 · 돌아옴(ON_PAUSE · ON_RESUME). 재개 때 정지 중 만료된 리액션은 재생기가 걷는다. 깜빡임 일정은 재개 시각부터 다시. */
    fun setSuspended(value: Boolean, now0: Double) {
        val now = monotonic(now0)
        player.setSuspended(value, now)
        if (!value) {
            expire(now)
            nextBlinkAt = now + nextBlinkInterval()
        }
    }
}
