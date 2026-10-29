// 원본: Sources/CheckMobileKit/Now/NowModels.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.stores.messages.MessagesTime
import com.yehsung.aingcheck.core.stores.messages.MobileLoadText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.MemberPresence
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.core.wire.models.swiftInt
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.toLocalDateTime

// 지금 탭의 값·순수 계산·문구(SPEC-ios §3.2). 화면 없이 값으로 검증한다.

/** 지금 탭 문구. 맥과 뜻이 같은 문장은 맥 글자 그대로 옮겼다. */
object NowText {
    const val title = "지금"

    const val workingOnMac = "맥에서 근무 중"
    const val workingOnPhone = "폰에서 근무 중"
    const val workingOnWindows = "윈도우에서 근무 중"
    const val working = "근무 중"
    const val notWorking = "근무 안 함"
    fun sessionSince(time: String): String = "이번 세션 ${time}부터"
    const val offSubtitle = "오늘 누적"
    const val staleSubtitle = "연결 끊김 · 마지막 신호에서 멈췄어요"
    const val weekPrefix = "이번 주"
    fun goalSuffix(hours: Int): String = "/ ${hours}시간"
    const val connectionLost = "연결 끊김"
    const val todayLabel = "오늘 누적"
    const val noTeamTitle = "팀에 속해 있지 않아요"
    const val noTeamBody = "팀 코드로 합류하거나 새 팀을 만들면 근무 시간과 주간 목표가 여기에 보여요"
    const val loadFailed = "지금 상태를 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요"
    const val networkFailed = MobileLoadText.checkConnection

    const val goalEdit = "주간 목표 수정"
    const val goalSheetTitle = "주간 목표"
    const val goalStepperLabel = "1인당 주간 목표"
    const val goalExplain = "팀 전체의 1인당 목표가 함께 바뀌어요. 팀원 누구나 바꿀 수 있어요."
    const val goalSave = "목표 저장"
    const val goalSaved = "주간 목표 변경됨"
    const val goalFailed = "목표 변경 실패"
    const val close = "닫기"

    const val todoTitle = "오늘 할 일"
    const val todoPlaceholder = "할 일 추가"
    const val todoEditPlaceholder = "할 일 수정"
    const val todoAdd = "추가"
    const val todoEmptyTitle = "오늘 할 일이 비어 있어요"
    const val todoEmptyHint = "위 칸에 적고 완료를 누르면 추가돼요"
    const val todoDeleted = "삭제됨"
    const val todoUndo = "되돌리기"
    const val todoMarkDone = "완료로 표시"
    const val todoMarkUndone = "완료 취소"
    const val todoDelete = "삭제"
    const val todoEdit = "수정"
    fun todoOldSection(count: Int): String = "오래된 항목 ($count)"
    const val todoOldTitle = "오래된 항목"
    fun todoRemaining(count: Int): String = "남은 ${count}개"
    fun todoCounter(current: Int): String = "$current/${TodoRules.maxTitleLength}"

    const val statusUnavailableTitle = "내 상태를 불러오지 못했어요"
    const val workingUnavailable = "근무 중인 사람을 불러오지 못했어요"
    const val retry = MobileLoadText.retry

    /** 머리글. 모를 때(null)는 숫자를 숨긴다 — 불러오지 못했는데 "0"이면 아무도 일하지 않는다는 말이 된다. */
    fun workingTitle(count: Int?): String = if (count == null) "지금 근무 중" else "지금 근무 중 $count"
    const val ourTeam = "우리 팀"
    const val otherTeams = "다른 팀"
    const val workingEmpty = "지금 근무 중인 사람이 없어요"
    fun peopleCount(count: Int): String = "${count}명"
    const val workingFooter = "근무는 맥이나 이 탭 맨 위 버튼으로 시작하고 끝내요"
    const val workingFooterMacOnly = "근무 시작과 종료는 맥 앱에서 해요"
    fun staleLastSeen(relative: String?): String = if (relative == null) connectionLost else "$connectionLost · 마지막 확인 $relative"
    fun talkTo(name: String): String = "${name}에게 말 걸기"

    fun expandedSubtitle(date: String, teamName: String?): String = if (teamName.isNullOrEmpty()) date else "$date · $teamName"
    fun collapsedSubtitle(clock: String, percent: Int): String = "$clock · 이번 주 $percent%"

    const val workStart = "근무 시작"
    const val workStop = "근무 종료"
    const val workStopConfirmTitle = "근무를 끝낼까요?"
    fun workStopConfirmMessage(origin: NowWorkOrigin): String = when (origin) {
        NowWorkOrigin.mac -> "맥에서 연 근무도 지금 끝나요. 지금까지의 시간은 그대로 기록돼요."
        NowWorkOrigin.windows -> "윈도우에서 연 근무도 지금 끝나요. 지금까지의 시간은 그대로 기록돼요."
        NowWorkOrigin.phone, NowWorkOrigin.unknown -> "지금까지의 시간은 그대로 기록돼요."
    }
    const val workStarted = "근무를 시작했어요"
    const val workStopped = "근무를 끝냈어요"
    const val alreadyWorking = "이미 근무 중이에요"
    const val alreadyWorkingOnMac = "이미 맥에서 근무 중이에요"
    const val alreadyStopped = "이미 근무가 끝나 있어요"
    const val workChanged = "근무 상태가 바뀌었어요. 다시 확인해 주세요"
    const val startFailed = "근무를 시작하지 못했어요. 잠시 후 다시 시도해 주세요"
    const val stopFailed = "근무를 끝내지 못했어요. 잠시 후 다시 시도해 주세요"
    const val workUnavailable = "지금은 폰에서 근무를 시작할 수 없어요"
    const val workNeedsTeam = "팀에 들어가면 근무를 시작할 수 있어요"
    fun phoneWorkCaption(checkAfterSeconds: Int?): String =
        "폰을 잠가도 근무는 이어져요 · ${NowFormat.hoursMinutesText(checkAfterSeconds ?: 9_000)} 동안 앱을 안 열면 확인 알림을 보내요"
    const val macWorkCaption = "맥에서 연 근무예요 · 여기서 끝낼 수도 있어요"
    const val pushOffWarning = "알림이 꺼져 있어 확인 알림 없이 근무가 끝날 수 있어요"
    fun idleClosed(time: String?): String =
        if (time == null) "앱을 오래 열지 않아 근무를 끝냈어요" else "앱을 오래 열지 않아 ${time}에 근무를 끝냈어요"
}

/**
 * 내 열린 근무를 어디서 열었는가(서버 `work_phone_*` 응답의 origin). 팀 상태 GET 에는 이 칸이 없다.
 * `windows` — 서버(B M3 ③)가 Windows 앱이 연 근무에 싣는 값(G §8-1 D:675 · §8-7 W2-f, 조정자 패치 W2-f 0003). 옛 iOS 는 모르는 값을
 * `.mac` 으로 접지만 Android 는 제 갈래로 읽는다. 이 빌드가 모르는 값은 W2-f `PhoneWorkController.originOf` 가 mac 으로 접는다.
 */
enum class NowWorkOrigin(val rawValue: String) {
    phone("phone"), mac("mac"), windows("windows"),

    /** 아직 모른다(생존 신호 응답 전) — "근무 중"으로만 말한다. */
    unknown("unknown"),
}

/** 폰 RPC 가 알려 준 내 열린 세션(시작 · touch 응답). 값은 폰 근무 갈래(W2-f `NowStorePhoneWork`)가 채운다. */
data class NowPhoneSession(
    /** 열린 행 id(소문자). */
    val id: String,
    val origin: NowWorkOrigin,
    val checkAt: SwiftDate? = null,
    val checkAfterSeconds: Int? = null,
)

/** `fetchOwnMembership` 의 결과(주 팀 하나). */
data class NowMembership(val teamID: String, val teamName: String, val goalHours: Int, val role: String)

/** 내 상태 카드 한 장의 값(시각 `now` 기준 — 화면이 1초마다 다시 만든다). */
data class NowMyCard(
    val isWorking: Boolean,
    val isStale: Boolean,
    val sessionStartedAt: SwiftDate?,
    val todaySeconds: Int,
    val weekSeconds: Int,
    val goalHours: Int,
    val origin: NowWorkOrigin = NowWorkOrigin.unknown,
) {
    val goalSeconds: Int get() = maxOf(1, goalHours) * 3600

    val stateText: String
        get() {
            if (!isWorking) return NowText.notWorking
            return when (origin) {
                NowWorkOrigin.phone -> NowText.workingOnPhone
                NowWorkOrigin.mac -> NowText.workingOnMac
                NowWorkOrigin.windows -> NowText.workingOnWindows
                NowWorkOrigin.unknown -> NowText.working
            }
        }
    val progress: Double get() = TeamWeeklyGoal(weekSeconds.toLong(), goalSeconds.toLong()).progress
    val isGoalComplete: Boolean get() = weekSeconds >= goalSeconds
    val percent: Int get() = NowFormat.percent(weekSeconds, goalSeconds)

    /** "이번 주 24.8시간 · 목표 40시간 · 62%". */
    val weekLine: String get() = "이번 주 ${NowFormat.hoursOneDecimal(weekSeconds)}시간 · 목표 ${goalHours}시간 · $percent%"
}

/** "지금 근무 중" 한 줄. 우리 팀은 경과 시간이 있고, 다른 팀은 근무 여부만 있다. */
data class NowWorkingPerson(
    val id: String,
    val name: String,
    val avatarURL: SwiftURL?,
    /** 센터 서버값(표시는 `CenterLabel` 한 곳). */
    val center: String?,
    val isTeammate: Boolean,
    val startedAt: SwiftDate?,
    val elapsedSeconds: Int?,
    val isStale: Boolean,
    val lastSeenAt: SwiftDate? = null,
    /** 상태메시지 — 이미 `StatusMessage.display` 를 지난 값(null = 줄을 그리지 않는다). */
    val statusMessage: String? = null,
)

/**
 * 폰이 세는 오늘·이번 주(서버 세션 시각 기준). **오늘은 KST 자정으로 자른다.**
 * 신호 끊김 판정 시각 `presenceAt` 은 화면 시각 `now` 와 따로 받는다(스토어가 고른다 — `NowStore.presenceJudgedAt`).
 */
object NowTimeMath {
    fun todaySeconds(member: TeamMemberStatus, fetchedAt: SwiftDate, now: SwiftDate, presenceAt: SwiftDate? = null): Int {
        val dayStart = TeamWeeklyGoal.koreanDayStart(now)
        val closed = if (TeamWeeklyGoal.koreanDayStart(fetchedAt) == dayStart) member.todayDurationSeconds else 0L
        return (maxOf(0L, closed) + currentContribution(member, dayStart, now, presenceAt)).toInt()
    }

    fun weekSeconds(member: TeamMemberStatus, fetchedAt: SwiftDate, now: SwiftDate, presenceAt: SwiftDate? = null): Int {
        val weekStart = TeamWeeklyGoal.koreanWeekStart(now)
        val closed = if (TeamWeeklyGoal.koreanWeekStart(fetchedAt) == weekStart) member.weeklyDurationSeconds else 0L
        return (maxOf(0L, closed) + currentContribution(member, weekStart, now, presenceAt)).toInt()
    }

    /** 진행 세션의 [windowStart, 끝] 기여. 끝은 살아 있으면 now, 신호가 끊겼으면 마지막 신호. */
    fun currentContribution(member: TeamMemberStatus, windowStart: SwiftDate, now: SwiftDate, presenceAt: SwiftDate? = null): Long {
        val started = member.currentSessionStartedAt
        if (member.status != WorkStatus.working || started == null) return 0
        val end = if (isStale(member, presenceAt ?: now)) member.lastSeenAt ?: member.updatedAt ?: started else now
        return maxOf(0L, swiftInt(minOf(end, now).timeIntervalSince(maxOf(started, windowStart))))
    }

    /** 진행 세션 경과(초). 끊겼으면 마지막 신호에서 멈춘 값, 아니면 now 까지. */
    fun elapsedSeconds(member: TeamMemberStatus, now: SwiftDate, presenceAt: SwiftDate? = null): Int {
        val started = member.currentSessionStartedAt
        if (member.status != WorkStatus.working || started == null) return 0
        val presence = member.presence(presenceAt ?: now)
        if (presence is MemberPresence.StaleWorking) return presence.frozenDurationSeconds.toInt()
        return maxOf(0L, swiftInt(now.timeIntervalSince(started))).toInt()
    }

    fun isStale(member: TeamMemberStatus, now: SwiftDate): Boolean = member.presence(now) is MemberPresence.StaleWorking
}

/** 우리 팀 상태를 화면이 어떻게 그릴지(loading 스피너 · failed "불러오지 못했어요" · loaded). */
enum class NowLoadState { loading, failed, loaded }

object NowFormat {
    private fun pad2(n: Int): String = n.toString().padStart(2, '0')

    /** 시·분·초 "3:25:07". */
    fun clock(seconds: Int): String {
        val s = maxOf(0, seconds)
        return "${s / 3600}:${pad2((s % 3600) / 60)}:${pad2(s % 60)}"
    }

    /** 시:분 "2:05". */
    fun hoursMinutes(seconds: Int): String {
        val s = maxOf(0, seconds)
        return "${s / 3600}:${pad2((s % 3600) / 60)}"
    }

    /** 소수 한 자리 시간 "24.8". **내림**이다. */
    fun hoursOneDecimal(seconds: Int): String {
        val tenths = maxOf(0, seconds) * 10 / 3600
        return "${tenths / 10}.${tenths % 10}"
    }

    /** 목표 퍼센트(맥 `GoalPercentFormatter.percent` — 반올림 · 0~999). */
    fun percent(workedSeconds: Int, goalSeconds: Int): Int {
        val worked = maxOf(0, workedSeconds)
        val goal = maxOf(1, goalSeconds)
        val raw = com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero(worked.toDouble() / goal.toDouble() * 100).toInt()
        return minOf(999, maxOf(0, raw))
    }

    /** "24시간 48분" · "48분" · "3시간"(내림). */
    fun hoursMinutesText(seconds: Int): String {
        val s = maxOf(0, seconds)
        val hours = s / 3600
        val minutes = (s % 3600) / 60
        if (hours == 0) return "${minutes}분"
        if (minutes == 0) return "${hours}시간"
        return "${hours}시간 ${minutes}분"
    }

    /** 시각 "10:20"(KST 24시간). */
    fun clockTime(date: SwiftDate): String {
        val t = MessagesTime.instant(date.timeIntervalSince1970).toLocalDateTime(MessagesTime.kst)
        return "${t.hour}:${pad2(t.minute)}"
    }

    /** 머리 날짜 "9월 17일 목요일"(KST). */
    fun longDate(date: SwiftDate): String {
        val d = MessagesTime.localDate(date.timeIntervalSince1970, MessagesTime.kst)
        val weekdays = listOf("일", "월", "화", "수", "목", "금", "토")
        val weekday = weekdays[d.dayOfWeek.isoDayNumber % 7] + "요일"
        return "${d.month.ordinal + 1}월 ${d.day}일 $weekday"
    }

    /** VoiceOver 용 "3시간 25분". */
    fun spokenDuration(seconds: Int): String {
        val s = maxOf(0, seconds)
        val hours = s / 3600
        val minutes = (s % 3600) / 60
        if (hours == 0) return "${minutes}분"
        return "${hours}시간 ${minutes}분"
    }
}

/** 할 일 입력(맥 `TodoDraftInput` 과 같은 규칙). */
object NowTodoDraft {
    /** 새 입력을 반영할지. 지우는 방향은 늘 통과, 늘리는 방향은 100자(코드 포인트 1000)까지 — 넘으면 **변경을 되돌린다**. */
    fun accepted(current: String, proposed: String): String {
        if (Graphemes.count(proposed) <= Graphemes.count(current) && codePoints(proposed) <= codePoints(current)) return proposed
        return if (TodoRules.titleFitsLimits(proposed)) proposed else current
    }

    /** 카운터 "92/100". 90자 전에는 null. */
    fun counterText(text: String): String? {
        val count = Graphemes.count(text)
        if (count < TodoRules.counterVisibleFrom) return null
        return NowText.todoCounter(count)
    }

    private fun codePoints(text: String): Int {
        var n = 0
        var i = 0
        while (i < text.length) {
            if (text[i].isHighSurrogate() && i + 1 < text.length && text[i + 1].isLowSurrogate()) i += 2 else i += 1
            n += 1
        }
        return n
    }
}
