// 원본: Sources/CheckMobileKit/Me/MeText.swift @ 1b8260d
// (iOS 전용 문장 — 푸시 권한 머리 줄 `PushAuthorizationStatus.meTitle/meDetail` · 화면 모드 · 위젯 안내 — 은 플랫폼 권한 상태·테마가 다른 갈래 몫이라
//  옮기지 않는다: 푸시 권한은 W2-f(Android 알림 권한은 provisional/ephemeral 이 없다), 화면 모드는 ui 테마(AingAppearanceMode — W3-b).)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.achievements.AchievementNoticeText
import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeAvailability
import com.yehsung.aingcheck.core.rules.gacha.GachaOddsRow
import com.yehsung.aingcheck.core.rules.gacha.GachaPullResult
import com.yehsung.aingcheck.core.rules.gacha.GachaText
import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WeeklyRetro
import com.yehsung.aingcheck.core.rules.insights.WorkDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WorkInsightsWeekWindow
import com.yehsung.aingcheck.core.rules.insights.WorkRhythmHeatmap
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.text.TextNormalization
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkGauge
import com.yehsung.aingcheck.core.session.AccountDeletionFailure
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.AppLinks
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.FeedbackReport
import com.yehsung.aingcheck.core.wire.models.FeedbackStatus
import com.yehsung.aingcheck.core.wire.models.FeedbackText
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal

/** 무대 기분(Swift `CharacterMood` — ui 의 `CharacterMood` 와 같은 네 갈래, 화면 갈래가 1:1 로 잇는다). */
enum class MeStageMood { working, lost, off, plain }

/**
 * 나 탭 문구와 순수 규칙(플랫폼 무관 — 공용 시험이 값으로 잰다). 맥과 뜻이 같은 문장·규칙은 **맥 것을 그대로** 옮겼다.
 */
object MeText {
    // MARK: 공통

    const val loading = "불러오는 중…"
    const val meFallbackName = "나"
    const val retry = "다시 시도"
    const val noTeam = "팀 없음"

    // MARK: 기록 (맥 InsightsPanel · InsightsEmptyMessage · GoalPercentFormatter)

    const val recordsTitle = "기록"
    const val retroTitle = "지난주 회고"
    const val metGoalChip = "목표 달성"
    const val noRetro = "지난주 근무 기록이 없어요"
    const val recordsFailed = "기록을 불러오지 못했어요"
    const val heatmapTitle = "지난주 근무 리듬"
    const val workGrassTitle = "최근 12주 근무"
    const val tokenGrassTitle = "최근 12주 AI 토큰"
    val dayNames: List<String> = listOf("월", "화", "수", "목", "금", "토", "일")

    /** 맥 `InsightsEmptyMessage.text` 와 같은 갈림. null 이면 본문(회고·잔디·히트맵)을 그린다. */
    fun recordsPlaceholder(hasLoaded: Boolean, hasFailed: Boolean, totalSeconds: Long, hasTokenGrass: Boolean): String? {
        if (!hasLoaded) return if (hasFailed) recordsFailed else loading
        if (totalSeconds == 0L && !hasTokenGrass) return if (hasFailed) recordsFailed else noRetro
        return null
    }

    fun retroTotal(retro: WeeklyRetro): String = "지난주 ${MenuBarStatusFormatter.hoursMinutes(retro.totalSeconds)}"

    fun retroGoalLine(retro: WeeklyRetro): String {
        val goalText = MenuBarStatusFormatter.hoursMinutes(retro.goalSeconds)
        if (retro.metGoal) return "목표 $goalText 달성 — 잘하셨어요"
        val percent = shortfallPercent(retro.totalSeconds, retro.goalSeconds)
        val remain = maxOf(0L, retro.goalSeconds - retro.totalSeconds)
        return "목표 $goalText 중 $percent% · ${MenuBarStatusFormatter.hoursMinutes(remain)} 부족"
    }

    fun retroDeltaLine(retro: WeeklyRetro): String? {
        if (retro.previousWeekSeconds <= 0) return null
        val delta = retro.deltaSeconds
        if (delta == 0L) return "전주와 같아요"
        val sign = if (delta > 0) "+" else "-"
        return "전주 대비 $sign${MenuBarStatusFormatter.hoursMinutes(kotlin.math.abs(delta))}"
    }

    fun retroDetailLine(retro: WeeklyRetro): String {
        val parts = mutableListOf("세션 ${retro.sessionCount}회")
        val day = retro.busiestDayIndex
        if (day != null && day >= 0 && day < dayNames.size && retro.busiestDaySeconds > 0) {
            parts += "가장 많이 일한 날 ${dayNames[day]}요일 ${MenuBarStatusFormatter.hoursMinutes(retro.busiestDaySeconds)}"
        }
        return parts.joinToString(" · ")
    }

    fun retroProgress(retro: WeeklyRetro): Double {
        val goal = maxOf(1L, retro.goalSeconds)
        return minOf(1.0, maxOf(0.0, retro.totalSeconds.toDouble() / goal.toDouble()))
    }

    /** "가장 활발한 시간: 화요일 14시". */
    fun peakLine(heatmap: WorkRhythmHeatmap): String? {
        val peak = heatmap.peakSlot ?: return null
        if (peak.first < 0 || peak.first >= dayNames.size) return null
        return "가장 활발한 시간: ${dayNames[peak.first]}요일 ${peak.second}시"
    }

    /** 맥 `GoalPercentFormatter.percent` — Swift `.rounded()`(0.5 는 0 에서 먼 쪽). */
    fun percent(workedSeconds: Long, goalSeconds: Long): Int {
        val worked = maxOf(0L, workedSeconds)
        val goal = maxOf(1L, goalSeconds)
        val raw = roundedHalfAwayFromZero(worked.toDouble() / goal.toDouble() * 100).toInt()
        return minOf(999, maxOf(0, raw))
    }

    /** 미달 문맥에서 100 으로 반올림돼 "100% · 18분 부족"이 되지 않게 99 로 묶는다. */
    fun shortfallPercent(workedSeconds: Long, goalSeconds: Long): Int = minOf(99, percent(workedSeconds, goalSeconds))

    /** 개인 기록 조회 창의 시작: min(회고 비교선 = 그 전주 월요일, 잔디 = 12주 전 월요일). */
    fun insightsWindowStart(now: SwiftDate): SwiftDate {
        val seconds = now.timeIntervalSince1970
        val retroStart = WorkInsightsWeekWindow.lastWeek(seconds).previousStart
        val gridStart = WorkDailyGrid.windowStart(seconds, WorkDailyGrid.defaultWeeks)
        return SwiftDate(minOf(retroStart, gridStart))
    }

    // MARK: 잔디 · 히트맵 격자 (맥 ContributionGridView · WorkRhythmHeatmapGrid 의 순수 함수)

    const val gridLevels = 4

    /** 0 이면 0단계, 분모의 1/levels 마다 한 단계 올림(올림 나눗셈), 상한 levels. */
    fun gridLevel(value: Long, denominator: Long, levels: Int = gridLevels): Int {
        if (value <= 0 || levels <= 0) return 0
        if (denominator <= 0) return levels
        return minOf(levels.toLong(), (value * levels + denominator - 1) / denominator).toInt()
    }

    fun gridOpacity(level: Int, levels: Int = gridLevels): Double {
        if (level <= 0 || levels <= 0) return 0.0
        return 0.20 + 0.80 * minOf(level, levels).toDouble() / levels.toDouble()
    }

    fun heatmapIntensity(seconds: Long): Double {
        if (seconds <= 0) return 0.0
        return minOf(1.0, maxOf(0.0, seconds.toDouble() / 3_600))
    }

    /** 주 열마다 그 주 일요일의 달이 앞 열과 다르면 그 달, 같으면 null. */
    fun monthLabels(weekStart: SwiftDate, weeks: Int): List<Int?> {
        if (weeks <= 0) return emptyList()
        fun monthOfSunday(week: Int): Int =
            KstCalendar.localDate(KstCalendar.addDays(weekStart.timeIntervalSince1970, week * WorkRhythmHeatmap.DAY_COUNT + WorkRhythmHeatmap.DAY_COUNT - 1))
                .month.ordinal + 1
        var previous = monthOfSunday(-1)
        return (0 until weeks).map { week ->
            val current = monthOfSunday(week)
            val label = if (current != previous) current else null
            previous = current
            label
        }
    }

    fun workGrassAccessibility(grid: WorkDailyGrid): String {
        val days = grid.seconds.flatten().count { it > 0 }
        return "$workGrassTitle, 근무한 날 ${days}일, 합계 ${MenuBarStatusFormatter.hoursMinutes(grid.totalSeconds)}"
    }

    fun tokenGrassAccessibility(grid: TokenDailyGrid): String {
        val days = grid.tokens.flatten().count { it > 0 }
        return "$tokenGrassTitle, 쓴 날 ${days}일, 합계 ${TokenNumberFormatter.compactKorean(grid.totalTokens)} 토큰"
    }

    // MARK: 잔디 상세 화면

    const val grassDetailTitle = "잔디 기록"
    const val grassOpenRow = "잔디 자세히 보기"
    const val grassOpenHint = "칸마다 그 날 기록을 봐요"
    const val grassAxisWork = "근무"
    const val grassAxisToken = "AI 토큰"
    const val grassStepBack = "하루 전"
    const val grassStepForward = "하루 뒤"

    fun grassScale(axis: MeGrassAxis): String = when (axis) {
        MeGrassAxis.work -> "가장 진한 칸 = 하루 8시간"
        MeGrassAxis.token -> "가장 진한 칸 = 하루 5천만 토큰"
    }

    /** "9월 3일 (목)" — 맥 `ContributionGridView.dateText` 와 같은 표기. 날짜 오프셋은 주 × 7 + 요일. */
    fun grassDetailDate(weekStart: SwiftDate, week: Int, weekday: Int): String {
        val parts = grassDayParts(weekStart, week, weekday)
        val name = dayNames.getOrElse(weekday) { "" }
        return "${parts.first}월 ${parts.second}일 ($name)"
    }

    fun grassWeekAccessibility(weekStart: SwiftDate, week: Int): String {
        val parts = grassDayParts(weekStart, week, 0)
        return "${parts.first}월 ${parts.second}일 주"
    }

    fun grassCellAccessibility(weekStart: SwiftDate, week: Int, weekday: Int, workSeconds: Long, tokens: Long, showsToken: Boolean): String {
        val parts = mutableListOf<String>()
        val day = grassDayParts(weekStart, week, weekday)
        val name = dayNames.getOrElse(weekday) { "" }
        parts += "${day.first}월 ${day.second}일 ${name}요일"
        parts += grassWorkPhrase(workSeconds)
        if (showsToken) parts += grassTokenPhrase(tokens)
        return parts.joinToString(", ")
    }

    fun grassValueLine(workSeconds: Long, tokens: Long, showsToken: Boolean): String {
        val parts = mutableListOf(grassWorkPhrase(workSeconds))
        if (showsToken) parts += grassTokenPhrase(tokens)
        return parts.joinToString(" · ")
    }

    /** 0 인 날은 코어가 이미 "근무 없음"이라 답하므로 접두어를 또 붙이지 않는다. */
    private fun grassWorkPhrase(seconds: Long): String {
        val text = WorkDailyGrid.tooltipValueText(seconds)
        return if (seconds > 0) "근무 $text" else text
    }

    private fun grassTokenPhrase(tokens: Long): String {
        val text = TokenDailyGrid.tooltipValueText(tokens)
        return if (tokens > 0) "AI $text" else text
    }

    /** weekStart 에서 (주 × 7 + 요일)일 뒤의 KST (달, 일). */
    private fun grassDayParts(weekStart: SwiftDate, week: Int, weekday: Int): Pair<Int, Int> {
        val date = KstCalendar.localDate(KstCalendar.addDays(weekStart.timeIntervalSince1970, week * WorkRhythmHeatmap.DAY_COUNT + weekday))
        return (date.month.ordinal + 1) to date.day
    }

    // MARK: 무대 · 기록 카드

    const val changeCharacter = "캐릭터 바꾸기"

    fun stageStatus(mood: MeStageMood): String? = when (mood) {
        MeStageMood.working -> "근무 중"
        MeStageMood.lost -> "연결 끊김"
        MeStageMood.off -> "근무 안 함"
        MeStageMood.plain -> null
    }

    /** 내 근무 상태 → 무대 기분. 모르면 null(지어내지 않는다). */
    fun stageMood(isWorking: Boolean?, isStale: Boolean): MeStageMood? {
        if (isWorking == null) return null
        if (!isWorking) return MeStageMood.off
        return if (isStale) MeStageMood.lost else MeStageMood.working
    }

    fun wearing(name: String): String = "$name $equipped"

    fun retroHeadline(retro: WeeklyRetro): String = MenuBarStatusFormatter.hoursMinutes(retro.totalSeconds)

    fun retroSummaryLine(retro: WeeklyRetro): String =
        listOfNotNull(retroDeltaLine(retro), "세션 ${retro.sessionCount}회").joinToString(" · ")

    fun retroChip(retro: WeeklyRetro): String =
        if (retro.metGoal) metGoalChip else "목표의 ${shortfallPercent(retro.totalSeconds, retro.goalSeconds)}%"

    fun rhythmCaption(heatmap: WorkRhythmHeatmap): String = peakLine(heatmap) ?: noRetro

    /** 근무 리듬 칸 농도 단계(0…4) — 잔디와 같은 사다리. 한 칸 3600초가 가장 진하다. */
    fun rhythmLevel(seconds: Long): Int {
        if (seconds <= 0) return 0
        return gridLevel(minOf(seconds, 3_600L), 3_600L)
    }

    // MARK: 이번 주 근무 보상 (칸 값은 서버가 말한다, 여기는 말투만)

    const val weeklyTitle = "이번 주 근무"
    const val weeklyDoneTitle = "이번 주 근무 완료"
    const val weeklyRule = "월요일 0시에 새로 세요"
    const val weeklyGrantSuffix = "받음"
    const val weeklyLoadFailed = "이번 주 근무를 불러오지 못했어요"

    fun weeklyHours(seconds: Long): String = MenuBarStatusFormatter.hoursMinutes(seconds)

    fun weeklyQuestTitle(hours: Long): String = "$weeklyTitle · ${hours}시간 달성하기"

    fun weeklyHeadline(gauge: WeeklyWorkGauge?): String {
        if (gauge == null) return weeklyTitle
        return if (gauge.isComplete) weeklyDoneTitle else weeklyQuestTitle(gauge.questHours)
    }

    fun weeklyGaugeValue(worked: Long, gauge: WeeklyWorkGauge): String =
        if (gauge.isComplete) weeklyHours(worked) else "${weeklyHours(worked)} / ${gauge.questHours}시간"

    /** 진행 중 "+50", 완료 "+270 받았어요" — **장부에 들어간 합**만. 완료인데 하나도 안 들어왔으면 null. */
    fun weeklyGaugeGem(gauge: WeeklyWorkGauge): String? {
        if (gauge.isComplete) return if (gauge.claimedTotal > 0) "+${gauge.claimedTotal} 받았어요" else null
        return weeklyRubyGain(gauge.reward)
    }

    fun weeklyTierHours(hours: Long): String = "${hours}h"

    fun weeklyRubyGain(ruby: Long): String = "+$ruby"

    fun weeklyTierAccessibility(hours: Long, ruby: Long, claimed: Boolean, claimable: Boolean = false): String {
        val tail = if (claimed) ", 받음" else if (claimable) ", $claimableMark" else ""
        return "${hours}시간 루비 ${ruby}개$tail"
    }

    const val claimableMark = "받을 수 있어요"

    fun weeklyGaugeAccessibility(worked: Long, gauge: WeeklyWorkGauge): String {
        val value = weeklyGaugeValue(worked, gauge)
        if (gauge.isComplete) return if (gauge.claimedTotal > 0) "$value, 루비 ${gauge.claimedTotal}개 받았어요" else value
        return "$value, 달성하면 루비 ${gauge.reward}개"
    }

    // MARK: 도전 미션 · 받기 (맥 AchievementCopy · MissionCopy · MissionPanelCopy 와 같은 낱말)
    // INV-MeText-c82ced4e 이식: **제목 · 보조 문장 · 보상 · 목표 · 순서는 서버가 말한다**(응답의 title · detail · reward · target · sort).
    //   그래서 이 절에는 미션 제목이 한 줄도 없고 50 · 20 · 10 같은 숫자도 없다 — 서버가 미션을 더하거나 값을 바꿔도 앱을 다시 낼 필요가
    //   없고, 화면이 서버와 다른 숫자를 약속하지 않는다. 여기 있는 것은 **말투**뿐이다.

    /** 절 소제목(맥 0.3.64 가 "도전 미션"을 "누적 미션"으로 바꿨다 — 사용자 결정 2026-10-22). */
    const val missionsTitle = "누적 미션"
    const val missionsLoadFailed = "미션을 불러오지 못했어요"
    const val missionsPageTitle = "미션"

    /**
     * 루트 [미션] 줄의 보조 글자 — 화면 안 **세 묶음을 순서대로** 가리킨다(일일 → 이번 주 → 누적). 제목을 그대로 이으면 한 줄에 안 들어가
     * 보조 글자가 통째로 버려진다.
     * INV-MeText-41d68f47 이식: 1.0.12 까지는 `이번 주 근무 · 도전 미션` 이었다 — 1.0.13 에 일일이 생기고 「도전 미션」이 「누적 미션」으로
     *   개명됐다(맥 0.3.64 와 같은 낱말). 시험이 세 제목의 머리 낱말이 여기 다 있는지 되묻는다.
     */
    const val missionsRowDetail = "일일 · 이번 주 · 누적 미션"
    const val missionsEmpty = "받을 수 있는 미션이 아직 없어요"
    const val claimButton = "받기"
    const val claimAllButton = "전부 받기"
    const val claimedMark = weeklyGrantSuffix

    /** 받기가 실패한 **그 줄** 안의 문장(코어 `AchievementNoticeText.claimFailedRow` — 맥과 한 글자도 다르지 않다). */
    const val claimFailed = AchievementNoticeText.claimFailedRow

    fun missionProgress(mission: AchievementStatus.Mission): String = "${mission.progress}/${mission.target}"

    /** 보상 숫자 "+50"(루비 보석은 화면이 그린다 — 💎 이모지를 쓰지 않는다). 0 이면 null(칩 없음). */
    fun missionReward(ruby: Long): String? = if (ruby > 0) weeklyRubyGain(ruby) else null

    fun claimAmount(ruby: Long): String = weeklyRubyGain(maxOf(0L, ruby))

    fun claimPendingHint(count: Int): String? = if (count > 0) "받을 보상 ${count}개" else null

    fun claimAccessibility(amount: Long): String = "$claimButton, 루비 ${maxOf(0L, amount)}개"

    fun claimAllAccessibility(amount: Long): String = "$claimAllButton, 루비 ${maxOf(0L, amount)}개"

    fun missionAccessibility(mission: AchievementStatus.Mission): String = when (mission.state) {
        AchievementStatus.RowState.inProgress -> {
            val progress = "${mission.title}, ${missionProgress(mission)}"
            if (mission.reward > 0) "$progress, 달성하면 루비 ${mission.reward}개" else progress
        }
        AchievementStatus.RowState.claimable -> "${mission.title}, 달성했어요"
        AchievementStatus.RowState.claimed ->
            if (mission.reward > 0) "${mission.title}, 루비 ${mission.reward}개 받았어요" else "${mission.title}, $claimedMark"
    }

    /** 줄 아이콘(SF Symbol 이름 — Android 는 ui `SfSymbols` 표가 Material 기호로 잇는다). **키 앞부분으로 고른다**. 모르는 키는 별. */
    fun missionIcon(key: String): String {
        val table = listOf(
            "phone" to "iphone",
            "todo" to "checklist",
            "gomoku" to "circle.grid.3x3.fill",
            "chess" to "checkerboard.rectangle",
            "minigame" to "gamecontroller.fill",
            "team" to "person.3.fill",
            "poke" to "hand.point.right.fill",
            "ultra" to "bolt.fill",
            "streak" to "flame.fill",
        )
        return table.firstOrNull { key.startsWith(it.first) }?.second ?: missionFallbackIcon
    }

    const val missionFallbackIcon = "star.fill"

    // MARK: 일일 미션 (v0.3.64 서버 daily — 맥 DailyMissionCopy 와 같은 낱말)
    // INV-MeText-e2371c31 이식: 여기에도 **제목 · 보상 숫자가 없다**. 일일 줄의 제목("… 한 판 하기")과 5 는 서버 `daily_mission_defs()` 가
    //   말한다(게임 이름이 바뀌면 서버가 바꾼다). 이 절에 있는 것은 묶음 이름 · 안내 한 줄 · 아이콘 표뿐이다.

    const val dailyMissionsTitle = "일일 미션"
    const val dailyMissionsResetNote = "자정에 초기화 · 안 받으면 사라져요"

    /**
     * 일일 줄 아이콘 — **게임 이름으로 고른다**. 미니게임은 코어 `MiniGameKind.icon`(길건너 아잉이 줄도 서버가 주면 그대로 선다 — 폰은 거르지
     * 않는다), 1:1 셋은 맥 입구 기호. 모르는 게임은 별.
     */
    fun dailyMissionIcon(game: String): String {
        MiniGameKind.entries.firstOrNull { it.rawValue == game }?.let { return it.icon }
        val table = listOf(
            "gomoku" to "circle.grid.3x3.fill",
            "chess" to "checkerboard.rectangle",
            "tetris_duel" to "rectangle.split.2x1.fill",
        )
        return table.firstOrNull { it.first == game }?.second ?: missionFallbackIcon
    }

    // MARK: 메뉴 그룹

    const val profileMenuDetail = "사진 · 별명"
    const val feedbackMenuDetail = "버그 · 요청"
    const val settingsMenuDetail = "알림 · 화면 모드"

    // MARK: 캐릭터 · 상점 (맥 ShopText · WorkTimerStore 상점 문구)

    const val shopLede = "루비는 미니게임 순위 상품과 근무 미션으로 모여요. 산 캐릭터는 계속 가져요."
    const val buyShort = "사기"
    const val previewCaption = "근무 중이면 웃고, 쉬면 시무룩해요"
    const val previewWorking = "근무 중"
    const val previewOff = "근무 안 함"

    fun previewTitle(name: String): String = "$name 미리 보기"

    fun ownedCount(owned: Int, total: Int): String = "${maxOf(0, owned)}/${maxOf(0, total)} ${MeText.owned}"

    fun remainingAfterPurchase(price: Long, balance: Long): String = "사고 나면 루비 ${maxOf(0L, balance - price)}개 남아요"

    const val charactersTitle = "캐릭터"
    const val shopTitle = "상점"
    const val pickerTitle = "캐릭터 고르기"
    const val pickerCaption = "맥·PC 오버레이, 맥 메뉴바와 울트라 찌르기에 나오는 내 캐릭터예요."
    /** Windows 판(ui LocalDesktopWording) — 사용자 답 "Windows 전용 문구 두기". */
    const val pickerCaptionDesktop = "오버레이와 울트라 찌르기에 나오는 내 캐릭터예요."
    const val alreadyOwned = "이미 갖고 있어요"
    const val pickSomething = "살 것을 골라 주세요"
    const val bought = "샀어요!"
    const val buyFailed = "구매 실패"
    const val buyAction = "구매하기"
    const val owned = "보유"
    const val equipped = "착용 중"
    const val equippedLoadFailed = "착용 정보를 불러오지 못했어요"
    const val headerLoadFailed = "프로필을 불러오지 못했어요"
    const val characterSaved = "캐릭터를 바꿨어요"
    const val characterSaveFailed = "캐릭터 저장 실패"
    const val characterNotOwned = "안 산 캐릭터예요 — 상점에서 살 수 있어요"
    const val goToShop = "상점 가기"
    const val shopFailed = "상점을 불러오지 못했어요"

    fun cardPrice(owned: Boolean, price: Long?): String {
        if (owned) return MeText.owned
        if (price == null) return "—"
        return "${maxOf(0L, price)}"
    }

    fun lockedCharacter(name: String): String = "$name${particle(name, "은", "는")} 아직 없어요 — 상점에서 살 수 있어요"

    fun purchaseConfirmTitle(name: String): String = "$name${particle(name, "을", "를")} 살까요?"

    /** 받침에 따라 조사를 고른다("유령을" · "여우를"). 마지막 스칼라가 한글 음절이 아니면 받침 없는 쪽. */
    fun particle(word: String, withFinal: String, withoutFinal: String): String {
        if (word.isEmpty()) return withoutFinal
        val last = lastScalar(word)
        if (last !in 0xAC00..0xD7A3) return withoutFinal
        return if ((last - 0xAC00) % 28 == 0) withoutFinal else withFinal
    }

    fun purchaseConfirmMessage(price: Long, balance: Long): String = "루비 ${price}개를 써요 · 남는 루비 ${maxOf(0L, balance - price)}개"

    // MARK: 캐릭터 뽑기 (문구 본체는 코어 GachaText — 여기는 폰 화면이 더 쓰는 줄만)

    fun gachaLede(price: Long): String = "루비 ${maxOf(0L, price)}개로 캐릭터 하나를 뽑아요"

    const val gachaPullBusy = "앞 뽑기 결과를 받는 중이에요"
    const val gachaLastResult = "방금 뽑은 결과"

    /** 뽑기 결과 줄(머리말 · 둘째 줄 · 희귀 마감). 문구는 코어 `GachaText` 그대로. */
    fun gachaResultLines(result: GachaPullResult, name: String): Triple<String, String?, CharacterManifest.Finish> = Triple(
        GachaText.rareHeadline(result.kind) ?: GachaText.headline(result, name),
        GachaText.detail(result, name),
        CharacterManifest.Finish.of(result.characterID),
    )

    /** 확률 시트 한 줄을 강조하는가 — **희귀 둘 다** 참이다(`isGold` 로 가르면 무지개가 평범한 줄이 된다). */
    fun gachaOddsEmphasized(row: GachaOddsRow): Boolean = row.finish.isRare

    fun gachaAcquirePhrase(shardCost: Long?): String {
        if (shardCost == null || shardCost <= 0) return GachaText.gachaOnlyHint
        return "뽑기 또는 ${GachaText.shardCost(shardCost)}로 얻을 수 있어요"
    }

    fun gachaOnlyNotice(name: String, shardCost: Long?): String = "$name${particle(name, "은", "는")} ${gachaAcquirePhrase(shardCost)}"

    fun lockedGachaCharacter(name: String, shardCost: Long?): String =
        "$name${particle(name, "은", "는")} 아직 없어요 — ${gachaAcquirePhrase(shardCost)}"

    const val gachaCharacterNotOwned = "아직 없는 캐릭터예요 — 뽑기나 조각 교환으로 얻을 수 있어요"

    fun gachaTileStatus(shardCost: Long?): String {
        if (shardCost == null || shardCost <= 0) return GachaText.gachaOnly
        return "${GachaText.pullButton} · 조각 $shardCost"
    }

    fun gachaTileAccessibility(name: String, shardCost: Long?): String = "$name, ${gachaAcquirePhrase(shardCost)}"

    const val gachaOddsColumnName = "캐릭터"
    const val gachaOddsColumnPrice = "상점가"
    const val gachaOddsColumnPercent = "확률"

    fun gachaExchangeEntry(shards: Long?): String {
        if (shards == null) return GachaText.exchangeTitle
        return "${GachaText.shards(maxOf(0L, shards))} · ${GachaText.exchangeButton}"
    }

    fun exchangeConfirmTitle(name: String, cost: Long): String = "$name${particle(name, "을", "를")} ${GachaText.shardCost(cost)}로 교환할까요?"

    fun exchangeConfirmMessage(cost: Long, shards: Long): String = "남는 조각 ${maxOf(0L, shards - cost)}개"

    const val exchangeAction = "교환하기"

    /** 교환 줄을 눌렀지만 못 바꿀 때의 한 줄. 바꿀 수 있으면 null. */
    fun exchangeBlocked(availability: GachaExchangeAvailability): String? = when (availability) {
        GachaExchangeAvailability.owned -> GachaText.alreadyOwned
        is GachaExchangeAvailability.short -> GachaText.shardShortfall(availability.missing)
        is GachaExchangeAvailability.unknownShards -> "조각 수를 아직 몰라요 — 상점을 다시 열어 주세요"
        GachaExchangeAvailability.notExchangeable -> GachaText.notExchangeable
        is GachaExchangeAvailability.available -> null
    }

    fun exchangeRowAccessibility(name: String, availability: GachaExchangeAvailability): String = when (availability) {
        GachaExchangeAvailability.owned -> "$name, ${GachaText.owned}"
        is GachaExchangeAvailability.available -> "$name, ${GachaText.shardCost(availability.costValue)}, 교환할 수 있어요"
        is GachaExchangeAvailability.short ->
            "$name, ${GachaText.shardCost(availability.costValue)}, ${GachaText.shardShortfall(availability.missing)}"
        is GachaExchangeAvailability.unknownShards -> "$name, ${GachaText.shardCost(availability.costValue)}"
        GachaExchangeAvailability.notExchangeable -> "$name, ${GachaText.notExchangeable}"
    }

    // MARK: 프로필 (맥 WorkTimerStore.updateDisplayName · CheckSettingsView 별명)

    const val profileTitle = "프로필"
    const val displayNameLabel = "별명"
    const val displayNameHelp = "팀 목록과 순위판에 보이는 이름이에요. 한 번 바꾸면 일주일 동안 다시 못 바꿔요."
    const val displayNameSave = "저장"
    const val displayNameEmpty = "별명을 입력해 주세요"
    const val displayNameTaken = "이미 쓰고 있는 별명이에요"
    const val displayNameInvalid = "지금은 별명을 바꿀 수 없어요"
    const val displayNameNetwork = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    const val displayNameSaved = "별명을 바꿨어요"
    const val avatarChange = "사진 바꾸기"
    const val avatarSaved = "프로필 사진 변경됨"
    const val avatarFailed = "사진 업로드 실패"
    const val avatarUnreadable = "사진을 읽지 못했어요 — 다른 사진을 골라 주세요"
    const val avatarUploading = "올리는 중…"
    const val avatarRoleNote = "사진과 별명은 메시지·순위에서 다른 사람에게 보여요. 사진이 없으면 착용 캐릭터가 대신 보여요."
    const val characterRoleTitle = "내 화면에는 캐릭터가 나와요"
    const val characterRoleNote = "지금·나 탭, 맥 메뉴바와 맥·PC 오버레이에서 착용 캐릭터가 나를 대신해요."
    /** Windows 판(ui LocalDesktopWording) — 사용자 답 "Windows 전용 문구 두기". */
    const val characterRoleNoteDesktop = "내 기록과 오버레이에서 착용 캐릭터가 나를 대신해요."

    /** 서버 쿨타임(7일). */
    const val displayNameCooldownSeconds: Double = 7.0 * 24 * 3600

    fun displayNameTooLong(maxLength: Long): String = "별명은 ${maxLength}자까지 쓸 수 있어요"

    /**
     * 맥 `normalizedDisplayName` — 서버 normalize_display_name() 의 거울(NFC · 제어/서식 문자 제거(ZWJ 유지) · 연속 공백 1칸 · 앞뒤 공백 제거).
     * 범주는 rules 의 번들 범위 표(§8-16 ② — `Character.getType` 을 쓰지 않는다)로 가른다.
     */
    fun normalizedDisplayName(raw: String): String {
        val composed = TextNormalization.nfc(raw)
        val kept = StringBuilder()
        var i = 0
        while (i < composed.length) {
            val cp = codePointAt(composed, i)
            val width = if (cp >= 0x10000) 2 else 1
            val category = TextScalars.generalCategory(cp)
            if (cp == 0x200D || (category != "Cc" && category != "Cf")) kept.appendRange(composed, i, i + width)
            i += width
        }
        // 공백(White_Space 속성)으로 자르고 빈 조각을 버린 뒤 한 칸으로 잇는다(Swift split(whereSeparator: isWhitespace)).
        val pieces = mutableListOf<String>()
        val current = StringBuilder()
        var j = 0
        val text = kept.toString()
        while (j < text.length) {
            val cp = codePointAt(text, j)
            val width = if (cp >= 0x10000) 2 else 1
            if (TextScalars.isWhiteSpaceProperty(cp)) {
                if (current.isNotEmpty()) {
                    pieces += current.toString()
                    current.clear()
                }
            } else {
                current.appendRange(text, j, j + width)
            }
            j += width
        }
        if (current.isNotEmpty()) pieces += current.toString()
        return pieces.joinToString(" ")
    }

    /** 서버가 세는 길이(코드포인트). */
    fun displayNameLength(raw: String): Int = scalarCount(normalizedDisplayName(raw))

    /** '마지막 변경 + 7일'이 속한 KST 날짜의 00:00. */
    fun displayNameUnlockDate(changedAt: SwiftDate): SwiftDate =
        TeamWeeklyGoal.koreanDayStart(changedAt.addingTimeInterval(displayNameCooldownSeconds))

    fun displayNameCooldownMessage(availableAt: SwiftDate): String {
        val date = KstCalendar.localDate(availableAt.timeIntervalSince1970)
        return "일주일에 한 번만 바꿀 수 있어요 · ${date.month.ordinal + 1}월 ${date.day}일부터"
    }

    // MARK: 제보 (와이어 FeedbackText 를 그대로 쓰고, 폰만의 문장만 여기)

    const val feedbackTitle = "제보"
    const val feedbackReplyBadge = "새 답장"
    const val feedbackKindLabel = "종류"

    /** "앱 0.1.0 (1) · Android 15 정보가 함께 전송돼요". 진단 줄은 폰에서 싣지 않는다. */
    fun feedbackAutoAttach(appVersion: String, osVersion: String): String = "${feedbackVersionLine(appVersion, osVersion)} 정보가 함께 전송돼요"

    /**
     * "앱 0.1.0 (1) · Android 15" — 서버에 싣는 앱 버전 값은 "Android 0.1.0 (1)"(맥 제보와 가르는 머리말)이라 운영체제 줄과 플랫폼 이름이
     * 겹친다. **보여 줄 때만** 앞의 플랫폼 이름을 "앱 " 으로 바꾼다(보내는 값은 그대로). 운영체제 값이 없으면 앱 버전만.
     */
    fun feedbackVersionLine(appVersion: String, osVersion: String?): String {
        val prefix = listOf("Android ", "Windows ", "iOS ").firstOrNull { appVersion.startsWith(it) }
        val app = if (prefix != null) "앱 ${appVersion.removePrefix(prefix)}" else appVersion
        if (osVersion.isNullOrEmpty()) return app
        return "$app · $osVersion"
    }

    /** 제보 상태 칩의 뜻 색 갈래(초록 금지 — 초록은 근무·달성 전용). */
    enum class FeedbackStatusTone { pending, accent, neutral }

    fun feedbackStatusTone(status: FeedbackStatus): FeedbackStatusTone = when (status) {
        FeedbackStatus.Open -> FeedbackStatusTone.pending
        FeedbackStatus.InProgress -> FeedbackStatusTone.accent
        FeedbackStatus.Done, FeedbackStatus.Held, is FeedbackStatus.Other -> FeedbackStatusTone.neutral
    }

    /** 맥 `FeedbackFailure.notice` 와 같은 갈림(원문 서버 예외는 절대 보여 주지 않는다). */
    fun feedbackFailure(error: Throwable, fallback: String, schemaMissing: String? = null): String {
        val serviceError = error as? SupabaseWorkServiceError ?: return fallback
        return when (serviceError) {
            is SupabaseWorkServiceError.AuthMessage -> {
                val upper = serviceError.text.uppercase()
                when {
                    upper.contains("FEEDBACK_RATE_LIMIT") -> FeedbackText.rateLimited
                    upper.contains("FEEDBACK_FORBIDDEN") -> FeedbackText.forbidden
                    else -> fallback
                }
            }
            is SupabaseWorkServiceError.RateLimited -> FeedbackText.rateLimited
            SupabaseWorkServiceError.DatabaseSchemaMissing -> schemaMissing ?: fallback
            else -> fallback
        }
    }

    /** 맥 `sortedForFeedbackList`: 미해결 먼저 → 최신순(모르면 뒤) → id. */
    fun sortedFeedback(reports: List<FeedbackReport>): List<FeedbackReport> = reports.sortedWith { lhs, rhs ->
        if (lhs.status.isOpen != rhs.status.isOpen) return@sortedWith if (lhs.status.isOpen) -1 else 1
        val l = lhs.createdAt
        val r = rhs.createdAt
        when {
            l != null && r != null && l != r -> return@sortedWith if (l > r) -1 else 1
            l == null && r != null -> return@sortedWith 1
            l != null && r == null -> return@sortedWith -1
        }
        lhs.id.compareTo(rhs.id)
    }

    // MARK: 설정 (맥 CheckSettingsView "내 정보")

    const val settingsTitle = "설정"
    const val privacySection = "공개 설정"
    const val tokenPublicTitle = "AI 토큰 사용량 공개"
    const val tokenPublicDetail = "끄면 AI 토큰 순위판에서 내 사용량이 다른 사람에게 보이지 않아요."
    const val miniGamePublicTitle = "미니게임 순위 공개"
    const val miniGamePublicDetail = "끄면 내 최고기록이 순위표에 안 보이고 올라가지도 않아요."
    const val privacySaveFailed = "공개 설정을 저장하지 못했어요 — 잠시 뒤 다시 시도해 주세요"
    const val privacyLoadFailed = "공개 설정을 불러오지 못했어요"
    const val safetySection = "안전"
    const val pushSection = "알림"

    /** 종류별 토글 아래 한 줄. [kindRaw] 는 푸시 종류의 전선 이름(`message` · `gomoku_invite` · `feedback_reply` · `work_check`). */
    fun pushDetail(kindRaw: String): String? = when (kindRaw) {
        "message" -> "누가 메시지를 보내면 알려 줘요."
        "gomoku_invite" -> "1:1 오목 대결 신청이 오면 알려 줘요."
        "feedback_reply" -> "보낸 제보에 답장이 오면 알려 줘요."
        "work_check" -> "폰으로 연 근무를 2시간 30분 넘게 확인하지 않으면 한 번 물어봐요."
        else -> null
    }

    const val pushPrefsUnknown = "알림 종류 설정을 아직 못 읽었어요 — 잠시 뒤 다시 열어 주세요"
    const val openSystemSettings = "설정 앱에서 켜기"

    /**
     * 화면 모드 절의 머리만 여기 둔다. 나머지 — Swift `MeText.swift:850-866`(appearanceWidgetNote · appearanceTitle 시스템/라이트/다크 ·
     * appearanceSymbol)와 `MeStoreSettings.swift:164-172`(appearanceMode · selectAppearance — 기기 설정, reset 이 안 건드리고 서버 요청 없음) —
     * 는 ui 의 `AingAppearanceMode` 에 기대므로(의존 방향 ui → core:stores) **W3-b(설정 화면)가 ui 쪽에 옮긴다**. 위젯 안내의 "아이폰 설정"은
     * Android 글자로 다시 정한다.
     */
    const val appearanceSection = "화면 모드"
    const val teamSection = "팀"
    const val inviteCodeTitle = "팀 코드"
    const val inviteCodeShare = "팀 코드 공유"
    const val inviteCodeMissing = "팀 코드를 아직 못 읽었어요"

    /** 앱 표시 이름(Swift `CheckMobileIdentifiers.appDisplayName` — 홈 화면 이름과 같은 글자). */
    const val appDisplayName = "아잉체크"

    fun inviteShareMessage(teamName: String?, code: String): String {
        val team = teamName?.let { "「$it」 " } ?: ""
        return "$appDisplayName ${team}팀 코드: $code\n맥·PC 앱에서 가입할 때 이 코드를 입력하면 같은 팀이 돼요."
    }

    const val accountSection = "계정"
    const val signOut = "로그아웃"
    const val signOutConfirmTitle = "로그아웃할까요?"
    const val signOutConfirmMessage = "이 폰에서만 로그아웃돼요. 맥·PC 앱은 그대로예요."
    const val signingOut = "로그아웃하는 중…"

    // MARK: 계정 삭제

    const val privacyPolicy = "개인정보 처리방침"

    /** 주소는 세션 층 [AppLinks] 한 곳(INV-MobileSessionStore-f754b3e3)에서 온다 — 여기 글자로 다시 적지 않는다. */
    val privacyPolicyURL: String get() = AppLinks.privacyPolicy

    const val deleteAccount = "계정 삭제"
    const val deleteAccountTitle = "계정을 지울까요?"
    const val deleteAccountLede = "이 계정의 모든 것이 서버에서 지워져요."
    val deleteAccountItems: List<String> = listOf("근무 기록", "메시지", "할 일", "캐릭터와 루비", "순위 기록")
    const val deleteAccountIrreversible = "되돌릴 수 없어요. 맥·PC 앱도 같이 로그아웃돼요."
    const val deleteAccountFeedbackNote = "보낸 제보는 작성자 없이 내용만 남아요."
    const val deleteAccountPasswordPrompt = "비밀번호 확인"
    const val deleteAccountPasswordHelp = "본인 확인을 위해 비밀번호를 다시 입력해 주세요."
    const val deleteAccountConfirm = "영구 삭제"
    const val deletingAccount = "지우는 중…"

    /** 실패 이유 → 문장(세션 스토어는 갈래만 돌려준다). 원문 서버 예외는 싣지 않는다. */
    fun deleteAccountFailure(reason: AccountDeletionFailure): String = when (reason) {
        AccountDeletionFailure.NotSignedIn -> SessionText.signInAgain
        AccountDeletionFailure.AlreadyRunning -> deletingAccount
        AccountDeletionFailure.PasswordRequired -> "비밀번호를 입력해 주세요"
        AccountDeletionFailure.EmailUnknown -> "로그인 이메일을 알 수 없어요 — 로그아웃한 뒤 다시 로그인해서 시도해 주세요"
        AccountDeletionFailure.WrongPassword -> "비밀번호가 맞지 않아요"
        is AccountDeletionFailure.ReauthRejected -> reason.message
        AccountDeletionFailure.Network -> SessionText.network
        AccountDeletionFailure.ServerNotReady -> "계정 삭제가 아직 서버에 준비되지 않았어요 — 잠시 뒤 다시 시도하거나 제보로 알려 주세요"
        AccountDeletionFailure.Rejected -> "계정을 지우지 못했어요 — 잠시 뒤 다시 시도해 주세요"
    }

    /** 설정 맨 아래 한 줄: "아잉체크 Android 0.1.0 (1)"(Swift "아잉체크 iOS …" 자리 — 플랫폼 이름은 앱 정보에서). */
    fun versionLine(appInfo: AppInfo): String = "$appDisplayName ${appInfo.platformLabel} ${appInfo.version} (${appInfo.build})"

    // MARK: 글자 도우미

    /** 유니코드 스칼라 수(Swift `unicodeScalars.count`). */
    fun scalarCount(text: String): Int {
        var count = 0
        var i = 0
        while (i < text.length) {
            val cp = codePointAt(text, i)
            i += if (cp >= 0x10000) 2 else 1
            count += 1
        }
        return count
    }

    private fun codePointAt(text: String, index: Int): Int {
        val high = text[index]
        if (high.isHighSurrogate() && index + 1 < text.length && text[index + 1].isLowSurrogate()) {
            return 0x10000 + ((high.code - 0xD800) shl 10) + (text[index + 1].code - 0xDC00)
        }
        return high.code
    }

    private fun lastScalar(text: String): Int {
        val low = text[text.length - 1]
        if (low.isLowSurrogate() && text.length >= 2 && text[text.length - 2].isHighSurrogate()) {
            return 0x10000 + ((text[text.length - 2].code - 0xD800) shl 10) + (low.code - 0xDC00)
        }
        return low.code
    }
}
