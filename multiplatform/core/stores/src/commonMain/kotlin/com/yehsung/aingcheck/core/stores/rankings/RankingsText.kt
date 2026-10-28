// 원본: Sources/CheckMobileKit/Rankings/RankingsText.swift · Sources/CheckCore/SupabaseWorkModels.swift:248-258(TeamLeaderboardEntry.isPastWeek) ·
//       Sources/CheckCore/SupabaseWorkModels.swift:504-565(TokenBoardEntry.toolUsageLabel · detailTooltip) ·
//       Sources/CheckMobileKit/Components/MobileComponentRules.swift:1-33(MobileLoadKnowledge) @ 1b8260d
package com.yehsung.aingcheck.core.stores.rankings

import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.rules.insights.TeamLeagueWeekNavigator
import com.yehsung.aingcheck.core.rules.insights.TokenBoardMonthNavigator
import com.yehsung.aingcheck.core.stores.messages.MobileLoadText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import com.yehsung.aingcheck.core.wire.models.TeamLeaderboardEntry
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.TokenBoardEntry

/** 순위 탭 세그먼트(Swift `AingRoute.RankingsBoard` — 라우트 타입은 앱 셸 몫이라 스토어는 같은 세 값만 든다). */
enum class RankingsBoard(val rawValue: String) {
    league("league"), tokens("tokens"), minigame("minigame");

    companion object {
        fun fromRaw(raw: String): RankingsBoard? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * 행이 **스스로** 과거 주인지 판정한다(Swift `TeamLeaderboardEntry.isPastWeek(now:)`). 서버 `week_start` 를 모르면(옛 서버) 이번 주로 본다 —
 * 틀릴 때 덜 나쁜 쪽이 이번 주다. 경계는 KST 월요일(같은 달력).
 */
fun TeamLeaderboardEntry.isPastWeek(now: SwiftDate): Boolean {
    val key = weekStart ?: return false
    val start = TeamLeagueWeekNavigator.date(key) ?: return false
    return start < TeamWeeklyGoal.koreanWeekStart(now).timeIntervalSince1970
}

/** 토큰 보드 행의 글자(와이어 `TokenBoardEntry` 는 숫자만 든다 — 글자는 숫자 표기 규칙(W1-c)을 쓰는 이 층에서 만든다). */
object TokenBoardText {
    /**
     * 이름 밑 캡션 한 줄: "누가 어떤 AI 를 얼마나 썼는지". 0 이 아닌 쪽만 ` · ` 로 잇는다 — 둘 다 0 이면 **null**(줄 자체를 그리지 않는다).
     * Codex 는 `codexEffective`(서버가 계정 우선 규칙으로 계산한 값)를 쓴다 — 굵은 총합(`total`)이 서버에서 같은 규칙으로 계산되므로.
     */
    // INV-SupabaseWorkModels-bf12f84b 이식: 안티그래비티는 이 줄에 넣지 않는다(v0.3.12) — ① 폭(캡션 자리 121pt 에 세 이름이 안 든다)
    //   ② 계약(순위판 RPC 에 안티그래비티 내역 칸이 없다 — 잔차로만 안다). 그래서 "캡션 합 == 굵은 총합"은 안티그래비티가 0 일 때만 성립하고,
    //   그 차이를 설명하는 자리는 폭 제한이 없는 [detailTooltip] 하나다(세 값 합 == 총합). 시험 RankingsTokenCaptionTest.
    fun toolUsageLabel(entry: TokenBoardEntry): String? {
        val parts = ArrayList<String>(2)
        if (entry.claudeTotal > 0) parts += "Claude ${TokenNumberFormatter.compactKorean(entry.claudeTotal)}"
        if (entry.codexEffective > 0) parts += "Codex ${TokenNumberFormatter.compactKorean(entry.codexEffective)}"
        return if (parts.isEmpty()) null else parts.joinToString(" · ")
    }

    /** 툴팁(길게 누르기 · 보이스오버 자세히): 정확한 값. 0 인 종류는 줄을 만들지 않는다. 안티그래비티는 잔차로 여기만 선다. */
    fun detailTooltip(entry: TokenBoardEntry): String {
        val parts = ArrayList<String>(3)
        if (entry.claudeTotal > 0) parts += "Claude ${TokenNumberFormatter.grouped(entry.claudeTotal)}"
        if (entry.codexEffective > 0) parts += "Codex ${TokenNumberFormatter.grouped(entry.codexEffective)}"
        if (entry.antigravityEffective > 0) parts += "안티그래비티 ${TokenNumberFormatter.grouped(entry.antigravityEffective)}"
        return parts.joinToString(" · ")
    }
}

/** 조회 결과를 화면에 **사실로 말해도 되는가**(Swift `MobileLoadKnowledge` — 탭 공통). */
object MobileLoadKnowledge {
    enum class Placeholder { rows, empty, failed, loading }

    /** 개수(0 포함)를 안다. */
    fun knowsCount(hasRows: Boolean, hasLoaded: Boolean, lastFailed: Boolean): Boolean = hasRows || (hasLoaded && !lastFailed)

    fun placeholder(hasRows: Boolean, hasLoaded: Boolean, lastFailed: Boolean): Placeholder = when {
        hasRows -> Placeholder.rows
        knowsCount(hasRows, hasLoaded, lastFailed) -> Placeholder.empty
        lastFailed -> Placeholder.failed
        else -> Placeholder.loading
    }
}

/** 순위 탭 문구와 순수 서식. 맥과 뜻이 같은 문장은 **맥 문장 그대로** 옮겼다. */
object RankingsText {
    fun segmentTitle(board: RankingsBoard): String = when (board) {
        RankingsBoard.league -> "팀 리그"
        RankingsBoard.tokens -> "AI 토큰"
        RankingsBoard.minigame -> "미니게임"
    }

    fun boardSubtitle(board: RankingsBoard): String = when (board) {
        RankingsBoard.league -> "이번 주 · 월요일 0시에 새로 시작해요"
        RankingsBoard.tokens -> "이번 달 · 1일에 새로 시작해요"
        RankingsBoard.minigame -> "오늘 · 자정에 마감해요"
    }

    const val loading = "불러오는 중…"
    const val retry = MobileLoadText.retry

    // ---------------------------------------------------------------- 팀 리그

    fun leagueTitle(weekKey: String, now: SwiftDate): String = "팀별 ${TeamLeagueWeekNavigator.displayTitle(weekKey, now.timeIntervalSince1970)}"
    fun leagueWeekName(weekKey: String, now: SwiftDate): String = TeamLeagueWeekNavigator.displayTitle(weekKey, now.timeIntervalSince1970)
    const val leagueCaption = "1인당 평균 근무시간 순이에요"
    const val leagueFilteredOut = "아직 이번 주 근무한 팀이 없어요"
    const val leagueFailed = "리그를 불러오지 못했어요"
    const val myTeamChip = "우리 팀"

    fun leagueAverage(entry: TeamLeaderboardEntry): String = "평균 ${MenuBarStatusFormatter.hoursMinutes(entry.averageSeconds)}"

    /** "각자 목표 40시간 · 총 51시간 12분 · 4명 · 2명 근무중". 과거 주는 마지막 조각이 참여 인원으로 갈린다('근무중' 조각이 사라진다). */
    fun leagueCaption(entry: TeamLeaderboardEntry, now: SwiftDate): String {
        val total = MenuBarStatusFormatter.hoursMinutes(entry.totalSeconds)
        if (!entry.isPastWeek(now)) {
            return "각자 목표 ${entry.weeklyGoalHours}시간 · 총 $total · ${entry.memberCount}명 · ${entry.workingCount}명 근무중"
        }
        return "각자 목표 ${entry.weeklyGoalHours}시간 · 총 $total · ${leagueParticipation(entry)}"
    }

    /** "5명 중 4명 참여" · participantCount 가 없으면 "5명 중 참여 인원 모름"(workingCount 로 대신하지 않는다). */
    fun leagueParticipation(entry: TeamLeaderboardEntry): String =
        entry.participantCount?.let { "${entry.memberCount}명 중 ${it}명 참여" } ?: "${entry.memberCount}명 중 참여 인원 모름"

    const val leagueAverageHint = "1인당 평균"

    fun leagueValue(entry: TeamLeaderboardEntry): String =
        if (entry.averageSeconds > 0) MenuBarStatusFormatter.hoursMinutes(entry.averageSeconds) else noValue

    fun leaguePercentText(entry: TeamLeaderboardEntry): String = if (entry.averageSeconds > 0) "${leaguePercent(entry)}%" else noValue

    fun leagueMembers(entry: TeamLeaderboardEntry): String = "${entry.memberCount}명"

    fun leagueWorking(entry: TeamLeaderboardEntry): String {
        if (entry.workingCount > 0) return "${entry.workingCount}명 근무 중"
        return if (entry.totalSeconds > 0) "근무 중 없음" else "이번 주 기록 없음"
    }

    fun leagueGoal(entry: TeamLeaderboardEntry): String = "목표 ${entry.weeklyGoalHours}시간"

    /** 부제 한 줄. 과거 주는 '근무 중' 조각을 **아예 뺀다**(값이 0 인지 따지지 않고 주 판정으로 끊는다). */
    fun leagueSubtitle(entry: TeamLeaderboardEntry, now: SwiftDate): String {
        if (!entry.isPastWeek(now)) return listOf(leagueMembers(entry), leagueWorking(entry), leagueGoal(entry)).joinToString(" · ")
        return listOf(leagueParticipation(entry), leagueGoal(entry)).joinToString(" · ")
    }

    enum class LeagueBarKind { done, gauge, accent }

    fun leagueBarKind(entry: TeamLeaderboardEntry, isMyTeam: Boolean): LeagueBarKind = when {
        entry.goal.isComplete -> LeagueBarKind.done
        isMyTeam -> LeagueBarKind.gauge
        else -> LeagueBarKind.accent
    }

    const val noValue = "—"

    /** 게이지 퍼센트(0~100 클램프된 진행률을 반올림 — Swift `rounded()` 는 0 에서 먼 쪽). */
    fun leaguePercent(entry: TeamLeaderboardEntry): Int = roundedHalfAwayFromZero(entry.goal.progress * 100).toInt()

    /** 빈 목록 문구(맥 `LeaderboardEmptyMessage.text` 와 같은 갈림 + 폰의 진행중·실패 구분). */
    fun leagueEmpty(hasLoaded: Boolean, isLoading: Boolean, hasFailed: Boolean, unfilteredCount: Int, isPastWeek: Boolean = false): String {
        if (!isPastWeek) {
            if (unfilteredCount > 0) return leagueFilteredOut
            if (hasFailed) return leagueFailed
            if (!hasLoaded || isLoading) return loading
            return leagueFilteredOut
        }
        if (isLoading) return loading
        if (hasFailed) return leaguePastFailed
        if (!hasLoaded) return loading
        return leaguePastFilteredOut
    }

    const val leaguePastFilteredOut = "그 주엔 근무한 팀이 없었어요"
    const val leaguePastFailed = "순위를 불러오지 못했어요"
    fun leagueFailedText(isPastWeek: Boolean): String = if (isPastWeek) leaguePastFailed else leagueFailed
    const val leagueWeekBasis = "인원은 그 주 기준이에요"
    const val leagueMyTeamMissing = "그 주엔 아직 우리 팀이 없었어요"

    fun leagueWeekNote(isPastWeek: Boolean, myTeamMissing: Boolean): String? {
        if (!isPastWeek) return null
        return if (myTeamMissing) leagueMyTeamMissing else leagueWeekBasis
    }

    const val previousWeek = "이전 주"
    const val nextWeek = "다음 주"
    const val noEarlierWeek = "6주 전까지만 볼 수 있어요"
    const val noLaterWeek = "이번 주가 가장 최근이에요"
    const val noLaterMonth = "이번 달이 가장 최근이에요"

    // ---------------------------------------------------------------- AI 토큰

    fun tokenTitle(month: String, now: SwiftDate): String = "${TokenBoardMonthNavigator.displayTitle(month, now.timeIntervalSince1970)} AI 토큰 소모량"

    const val tokenNoUploads = "아직 이번 달 소모량을 올린 사용자가 없어요"
    const val tokenNoPastRecords = "이 달에는 기록이 없어요"
    const val tokenFailed = "순위를 불러오지 못했어요"
    const val meChip = "나"
    const val privateChip = "비공개"
    const val previousMonth = "이전 달"
    const val nextMonth = "다음 달"

    fun tokenEmpty(hasLoaded: Boolean, isLoading: Boolean, hasFailed: Boolean, isCurrentMonth: Boolean): String {
        if (!hasLoaded) return if (hasFailed && !isLoading) tokenFailed else loading
        return if (isCurrentMonth) tokenNoUploads else tokenNoPastRecords
    }

    fun tokenTotal(entry: TokenBoardEntry): String = "${TokenNumberFormatter.grouped(entry.total)} 토큰"

    /** 행 오른쪽 끝 큰 숫자 — **억/만 한 단위 체계**(이름 밑 도구 줄과 같은 축약). */
    fun tokenTotalCompact(entry: TokenBoardEntry): String = TokenNumberFormatter.compactKorean(entry.total)

    fun tokenTodayCompact(entry: TokenBoardEntry, todayKey: String): String =
        "오늘 +${TokenNumberFormatter.compactKorean(entry.todayDelta(todayKey))}"

    /** 비교 막대 길이(1등 = 1). 1등이 0 이면 전부 0. */
    fun tokenBarFraction(total: Long, top: Long): Double {
        if (top <= 0) return 0.0
        return minOf(1.0, maxOf(0.0, total.toDouble() / top.toDouble()))
    }

    fun tokenToday(entry: TokenBoardEntry, todayKey: String): String = "오늘 +${TokenNumberFormatter.grouped(entry.todayDelta(todayKey))} 토큰"

    // ---------------------------------------------------------------- 미니게임

    const val miniGameRankTitle = "오늘 순위"
    const val miniGameEmpty = "아직 기록이 없어요 — 첫 기록의 주인공이 되세요"
    const val miniGameFailed = "순위를 불러오지 못했어요"
    const val yesterdayChampion = "어제 1등"

    /** 자정 상품(루비). 맥 `rubyPrizes` · 서버 `ruby_prize_amounts()` 와 **짝인 상수**(2026-10-22 사용자 결정 20·10·5). */
    val rubyPrizes: List<Int> = listOf(20, 10, 5)

    /** 자정 상품 정족수(맥 `prizeQuorum` · 서버 `minigame_prize_quorum()` 과 짝). */
    const val prizeQuorum = 5
    val prizeCaption: String get() = "자정에 1·2·3등에게 루비 ${rubyPrizes[0]}·${rubyPrizes[1]}·${rubyPrizes[2]}"
    val awardedChip: String get() = "루비 +${rubyPrizes[0]} 받음"

    fun quorumCaption(players: Int): String {
        if (players >= prizeQuorum) return "오늘 ${players}명 참여 · 지급 조건 충족"
        if (players == 0) return "오늘은 아직 아무도 안 했어요 · ${prizeQuorum}명부터 지급"
        return "오늘 ${players}명 참여 · ${prizeQuorum}명부터 지급"
    }

    /** "953점" — 자리수 구분 없이(만점 "1,000점" 방지). */
    fun score(value: Long): String = "${value}점"

    fun miniGameEmptyText(hasLoaded: Boolean, hasFailed: Boolean): String {
        if (hasFailed && !hasLoaded) return miniGameFailed
        if (!hasLoaded) return loading
        return miniGameEmpty
    }

    fun miniGameRowAccessibility(rank: Int, entry: MiniGameBoardEntry, isMe: Boolean): String {
        val parts = arrayListOf("${rank}위", entry.name)
        entry.center?.let { parts += "${it}센터" }
        parts += score(entry.bestScore)
        if (isMe) parts += meChip
        return parts.joinToString(", ")
    }

    fun tokenRowAccessibility(rank: Int, entry: TokenBoardEntry, isMe: Boolean, isPrivate: Boolean, todayKey: String?): String {
        val parts = arrayListOf("${rank}위", entry.name)
        if (isMe) parts += meChip
        if (isPrivate) parts += privateChip
        parts += tokenTotal(entry)
        TokenBoardText.toolUsageLabel(entry)?.let { parts += it }
        if (todayKey != null) parts += tokenToday(entry, todayKey)
        return parts.joinToString(", ")
    }

    /** 행 보이스오버 한 줄. **주 이름은 넣지 않는다**(보조 줄이 한 번만 한다). */
    fun leagueRowAccessibility(rank: Int, entry: TeamLeaderboardEntry, isMyTeam: Boolean, now: SwiftDate): String {
        val parts = arrayListOf("${rank}위", entry.name)
        if (isMyTeam) parts += myTeamChip
        parts += leagueAverage(entry)
        parts += "목표 대비 ${leaguePercent(entry)}%"
        parts += leagueCaption(entry, now)
        return parts.joinToString(", ")
    }
}
