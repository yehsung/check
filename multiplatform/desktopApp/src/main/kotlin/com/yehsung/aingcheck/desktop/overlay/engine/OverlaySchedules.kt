package com.yehsung.aingcheck.desktop.overlay.engine

import com.yehsung.aingcheck.core.rules.insights.DrowsyWindow
import kotlin.random.Random

/** 컨트롤러 상수(맥 CheckOverlayController :65-145). */
object OverlayTimings {
    /** 작별 숨김 마감 = commuteEnd 0.4 + 0.15(맥 farewellHideDeadline :76). */
    val FAREWELL_HIDE_S: Double = ReactionRules.duration(ReactionKind.CommuteEnd) + 0.15
    const val NUDGE_AUTO_START_TEXT = "일하는 것 같아서 근무 시작했어요!"
    const val NUDGE_AUTO_START_BUBBLE_S = 8.0
    const val FIRST_ARRIVAL_TEXT = "오늘 1등 출근이에요!"
    const val FIRST_ARRIVAL_BUBBLE_S = 6.0
    const val BLINK_MIN_S = 3.0
    const val BLINK_MAX_S = 7.0
    const val UPDATE_BUBBLE_TEXT = "새 업데이트가 있어요!"
    const val UPDATE_BUBBLE_S = 6.0
    /** 숨김 중 찌름·보상·메시지를 잠깐 보여 주는 길이(맥 pokePeekSeconds :124). */
    const val PEEK_S = 8.0
    /** 메시지·대결 말풍선 펌프 주기(맥 messageBubbleTickSeconds :136). */
    const val PUMP_TICK_S = 1.0
    /** 규약 2 — ReactionKind.UltraPoked.duration 과 같아야 한다(맥 ultraSeconds :140). */
    const val ULTRA_S = 5.0
    /** 감시 유예(맥 ultraWatchdogGrace :145) — 마감 = 시작 + 5 + 1. */
    const val ULTRA_WATCHDOG_GRACE_S = 1.0
}

/**
 * 졸기·낮잠·깜빡 간격 뽑기(난수 주입). 맥 DrowsyWindow.nextInterval/nextNapDuration(CheckCore/MilestoneTracker.swift:38-45)
 * 의 Kotlin 몫 — core 의 DrowsyWindow 상수만 쓴다.
 * ⚠️ 규약 12 — 설계 F §1.3 의 "졸기 23–05시" 는 코드와 다르다: 맥은 DrowsyWindow.contains 를 **안 쓴다**. 시간창 없음.
 */
object OverlaySchedules {
    fun nextDrowsyInterval(rng: Random): Double = rng.nextDouble(DrowsyWindow.minInterval, DrowsyWindow.maxInterval)
    fun nextNapDuration(rng: Random): Double = rng.nextDouble(DrowsyWindow.minNapSeconds, DrowsyWindow.maxNapSeconds)
    fun nextBlinkInterval(rng: Random): Double = rng.nextDouble(OverlayTimings.BLINK_MIN_S, OverlayTimings.BLINK_MAX_S)
}

/**
 * 팀원 출근 인사 감지기(맥 TeammateGreetingDetector — CheckOverlayReactions.swift :118-165).
 * 첫 로드는 시드만(인사 폭탄 금지) · offWork→working 전이만(새로 나타난 근무자 제외) · 멤버당 10분 · 자기 제외.
 */
class TeammateGreetingDetector {
    companion object { const val COOLDOWN_S = 10 * 60.0 }

    private val lastWorking = HashMap<String, Boolean>()
    private val lastGreetedAt = HashMap<String, Double>()
    private var seeded = false

    fun reset() { lastWorking.clear(); lastGreetedAt.clear(); seeded = false }

    fun detect(members: List<TeamPresence>, selfId: String?, now: Double): List<String> {
        try {
            if (!seeded) { seeded = true; return emptyList() }
            val out = ArrayList<String>()
            for (m in members) {
                if (m.id == selfId) continue
                if (lastWorking[m.id] != false || !m.working) continue
                val last = lastGreetedAt[m.id]
                if (last != null && now - last < COOLDOWN_S) continue
                out += m.name
                lastGreetedAt[m.id] = now
            }
            return out
        } finally {
            for (m in members) lastWorking[m.id] = m.working
        }
    }
}
