package com.yehsung.aingcheck.desktop.overlay.engine

/*
 * 리액션 표·중재 규칙 한 파일(공용 패치 요청 ① — 8차 뒤 character/…/player/ReactionRules.kt 로 그대로 옮길 수 있게).
 * 출처: Sources/check/CheckOverlayReactions.swift :15-116(ReactionKind) · :178-212(상수) · :915-958(request).
 * Android StageDirector 와 지금은 두 벌이다 — 옮길 때 이 파일을 정본으로.
 */

/** 맥 `ReactionKind`. motionName = assets/aing-bake/motion.json `reactions[].name`(CharacterPlayer.play 의 키). */
sealed class ReactionKind(val motionName: String) {
    data object Hit : ReactionKind("hit")
    data object CommuteStart : ReactionKind("commuteStart")
    data object CommuteEnd : ReactionKind("commuteEnd")
    data object Milestone : ReactionKind("milestone")
    data class Greeting(val name: String) : ReactionKind("greeting")
    data object Drowsy : ReactionKind("drowsy")
    data object Wake : ReactionKind("wake")
    data class Poked(val bubbleText: String) : ReactionKind("poked")
    data class UltraPoked(val bubbleText: String) : ReactionKind("ultraPoked")
    data object GoalAchieved : ReactionKind("goalAchieved")
    data object UltraCharged : ReactionKind("ultraCharged")
    data class RubyReward(val amount: Int) : ReactionKind("rubyReward")

    val priority: Int get() = ReactionRules.priority(this)
    val duration: Double get() = ReactionRules.duration(this)
    val isReward: Boolean get() = this is GoalAchieved || this is UltraCharged || this is RubyReward
}

object ReactionRules {
    const val HIT_COOLDOWN_S = 0.6

    // 말풍선 초(맥 :186-204)
    const val HIT_BUBBLE_S = 1.2
    const val COMMUTE_START_BUBBLE_S = 5.0
    const val COMMUTE_END_BUBBLE_S = 2.0
    const val GREETING_BUBBLE_S = 3.0
    const val WAKE_BUBBLE_S = 2.5
    const val POKED_BUBBLE_S = 6.0
    const val ULTRA_POKED_BUBBLE_S = 5.0
    const val GOAL_BUBBLE_S = 4.0
    const val ULTRA_CHARGED_BUBBLE_S = 3.2

    /** 출근 문구 오버라이드 수명(맥 :396 commuteStartOverrideLifetime) — 규약 7. */
    const val COMMUTE_START_OVERRIDE_LIFETIME_S = 10.0

    const val HIT_TEXT = "아얏!"
    const val COMMUTE_START_TEXT = "오늘도 화이팅!"
    const val COMMUTE_END_TEXT = "수고했어!"
    const val WAKE_TEXT = "깜빡 졸았다!"
    const val GOAL_TEXT = "주간 목표 달성!"
    /** 3시간 랩 보상 — 서버 ruby_mission_grant() 와 짝인 상수(둘 다 3). */
    const val MISSION_REWARD_TEXT = "루비 +3!"
    fun greetingText(name: String): String = "${name}님 출근!"
    fun rubyRewardText(amount: Int): String = "루비 +${maxOf(0, amount)}!"

    /**
     * 규약 2 — 울트라만 4. 보상(goal·ultraCharged·ruby)은 3(2 면 마일스톤 중 도착한 보상이 조용히 거부된다,
     * 4 는 전체화면 점거 자리). 울트라 > hit/출퇴근/화들짝/찌름·보상 > 마일스톤 > 인사 > 졸기.
     */
    fun priority(kind: ReactionKind): Int = when (kind) {
        is ReactionKind.UltraPoked -> 4
        ReactionKind.Hit, ReactionKind.CommuteStart, ReactionKind.CommuteEnd, ReactionKind.Wake, is ReactionKind.Poked -> 3
        ReactionKind.GoalAchieved, ReactionKind.UltraCharged, is ReactionKind.RubyReward -> 3
        ReactionKind.Milestone -> 2
        is ReactionKind.Greeting -> 1
        ReactionKind.Drowsy -> 0
    }

    /** 재생 길이(초). 규약 2: ultraPoked 5.0 = 모션 총길이 = OverlayTimings.ULTRA_S. */
    fun duration(kind: ReactionKind): Double = when (kind) {
        ReactionKind.Hit -> 0.6
        ReactionKind.CommuteStart -> 0.6
        ReactionKind.CommuteEnd -> 0.4
        ReactionKind.Milestone -> 1.6
        is ReactionKind.Greeting -> 1.0
        ReactionKind.Wake -> 0.4
        is ReactionKind.Poked -> 2.5
        is ReactionKind.UltraPoked -> 5.0
        ReactionKind.GoalAchieved -> 2.2
        ReactionKind.UltraCharged, is ReactionKind.RubyReward -> 2.0
        ReactionKind.Drowsy -> 2.0
    }

    /** 말풍선 초(없으면 null — 마일스톤은 말이 없다, 졸기는 지속 상태). motion.json bubbleSeconds 와 같아야 한다. */
    fun bubbleSeconds(kind: ReactionKind): Double? = when (kind) {
        ReactionKind.Hit -> HIT_BUBBLE_S
        ReactionKind.CommuteStart -> COMMUTE_START_BUBBLE_S
        ReactionKind.CommuteEnd -> COMMUTE_END_BUBBLE_S
        ReactionKind.Milestone -> null
        is ReactionKind.Greeting -> GREETING_BUBBLE_S
        ReactionKind.Drowsy -> null
        ReactionKind.Wake -> WAKE_BUBBLE_S
        is ReactionKind.Poked -> POKED_BUBBLE_S
        is ReactionKind.UltraPoked -> ULTRA_POKED_BUBBLE_S
        ReactionKind.GoalAchieved -> GOAL_BUBBLE_S
        ReactionKind.UltraCharged, is ReactionKind.RubyReward -> ULTRA_CHARGED_BUBBLE_S
    }

    /** perform(:1040-1098) 의 파티클 대응. */
    fun particle(kind: ReactionKind): ParticleCue? = when (kind) {
        ReactionKind.Milestone -> ParticleCue.CONFETTI
        ReactionKind.GoalAchieved -> ParticleCue.GOAL_SPARKS
        ReactionKind.UltraCharged, is ReactionKind.RubyReward -> ParticleCue.ULTRA_CHARGE
        else -> null
    }

    /** 자는 중 들어온 요청의 가지(규약 1). */
    enum class SleepBranch { IGNORE, STARTLE, END_SLEEP_THEN_PLAY }

    /**
     * ⚠️ 규약 1 — 자는 중 goalAchieved·ultraCharged·rubyReward 는 **endSleep 뒤 재생** 가지다(무시 가지에 넣으면
     * 보상 통지 증발 — 서버는 재화를 이미 올렸다). drowsy·greeting 만 무시, hit·wake 는 쿨다운 무관 화들짝.
     */
    fun sleepBranch(kind: ReactionKind): SleepBranch = when (kind) {
        ReactionKind.Drowsy, is ReactionKind.Greeting -> SleepBranch.IGNORE
        ReactionKind.Wake, ReactionKind.Hit -> SleepBranch.STARTLE
        ReactionKind.CommuteStart, ReactionKind.CommuteEnd, ReactionKind.Milestone, is ReactionKind.Poked,
        is ReactionKind.UltraPoked, ReactionKind.GoalAchieved, ReactionKind.UltraCharged, is ReactionKind.RubyReward,
        -> SleepBranch.END_SLEEP_THEN_PLAY
    }

    /**
     * 규약 3 — 재생 중(active)에 들어온 요청(incoming)이 이길 수 있나.
     * 더 높으면 이긴다. ≤ 이면 예외 넷만: commuteEnd→commuteStart 재시작 · 진행 중 poked 는 어떤 ≤ 요청에도 양보 ·
     * 울트라 재수신은 자기에게만 · 보상(goal·ultraCharged·ruby)은 **동순위(3)에만** 양보.
     */
    fun incomingWins(active: ReactionKind, incoming: ReactionKind): Boolean {
        if (incoming.priority > active.priority) return true
        val commuteRestart = active == ReactionKind.CommuteEnd && incoming == ReactionKind.CommuteStart
        val activeIsPoked = active is ReactionKind.Poked
        val ultraRestart = active is ReactionKind.UltraPoked && incoming is ReactionKind.UltraPoked
        val sameRank = incoming.priority == active.priority
        val activeIsReward = active.isReward && sameRank
        return commuteRestart || activeIsPoked || ultraRestart || activeIsReward
    }
}
