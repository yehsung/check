// 원본: Sources/CheckMobileKit/Me/MeStoreRecords.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchMySessions
import com.yehsung.aingcheck.core.net.fetchMyTokenDaily
import com.yehsung.aingcheck.core.net.fetchTeamStatuses
import com.yehsung.aingcheck.core.net.fetchTokenBoard
import com.yehsung.aingcheck.core.net.fetchTokenUsageSettings
import com.yehsung.aingcheck.core.rules.insights.RetroWeekKey
import com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid
import com.yehsung.aingcheck.core.rules.insights.TokenDailyMerge
import com.yehsung.aingcheck.core.rules.insights.TokenDailyRowFacts
import com.yehsung.aingcheck.core.rules.insights.WeeklyRetro
import com.yehsung.aingcheck.core.rules.insights.WorkDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WorkInsightsComputation
import com.yehsung.aingcheck.core.rules.insights.WorkRhythmHeatmap
import com.yehsung.aingcheck.core.rules.insights.WorkSessionTimes
import com.yehsung.aingcheck.core.rules.token.TokenRowDisplayRule
import com.yehsung.aingcheck.core.rules.token.TokenRowServerValue
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MemberPresence
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.TokenBoardRow
import com.yehsung.aingcheck.core.wire.models.TokenUsageDailyRow
import com.yehsung.aingcheck.core.wire.models.TokenUsageMonthKey
import com.yehsung.aingcheck.core.wire.models.WorkSessionRow
import com.yehsung.aingcheck.core.wire.models.toTokenBoardEntries
import kotlinx.coroutines.withContext

// 기록(지난주 회고 · 12주 근무 잔디 · 12주 AI 토큰 잔디 · 지난주 근무 리듬) — 계산은 전부 코어(rules insights) 그대로, 폰은 **읽기 GET** 만:
// 내 완료 세션(work_sessions) · 내 일별 토큰(token_usage_device_daily) · 토큰 설정(profiles — 수집 여부만) · 팀 상태(진행 중 세션 시작 시각만).

suspend fun MeStore.loadRecords() {
    if (!context.sessionStore.isSignedIn) return
    val userID = context.sessionStore.userID ?: return
    val serial = nextSerial("records")
    val generation = context.generation
    val now = context.clock.now()
    // 주가 바뀐 뒤의 옛 계산은 '지난주'가 아니다 — 조회를 시작하는 순간 버린다.
    val key = recordsWeekKey
    if (key != null && key != RetroWeekKey.current(now.timeIntervalSince1970)) discardRecords()
    recordsState.isLoading = true
    recordsState.hasFailed = false
    try {
        val service = context.service
        val since = MeText.insightsWindowStart(now)
        // 팀(목표 시간·진행 중 세션 조회)을 아직 모르면 먼저 읽는다 — 멤버십보다 기록이 먼저 오면 목표가 기본값(60시간)으로 굳는다.
        if (context.sessionStore.profile?.teamID == null) {
            context.sessionStore.refreshProfile()
            if (generation != context.generation || !isCurrent("records", serial)) return
        }
        val teamID = context.sessionStore.profile?.teamID
        val goalSeconds = (context.sessionStore.profile?.teamGoalHours ?: TeamWeeklyGoal.defaultGoalHours) * 3600
        val rows = try {
            context.withSessionRetry { s -> service.fetchMySessions(s.accessToken, s.userID, since) }
        } catch (e: Throwable) {
            if (generation != context.generation || !isCurrent("records", serial)) return
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            recordsState.hasFailed = true
            return
        }
        if (generation != context.generation || !isCurrent("records", serial)) return

        // 토큰 설정(독립 실패 — 못 읽으면 지난 값, 처음이면 수집 중으로 본다). 공개 여부는 설정 스위치와 같은 칸이다 — 떠 있는 사이
        // 사용자가 스위치를 바꿨으면 옮기지 않는다(rankme-verify R1).
        val privacyStamp = privacyReadStamp("token")
        val settings = attempt { s -> service.fetchTokenUsageSettings(s.accessToken, s.userID) }.getOrNull()
        if (generation != context.generation || !isCurrent("records", serial)) return
        if (settings != null && canApplyPrivacyRead("token", privacyStamp)) {
            // focus_mode 는 읽기만 하고 버린다 — 폰은 집중 모드를 건드리지 않는다(R9).
            tokenUsagePublic = settings.isPublic
            tokenUsagePublicLoaded = true
        }
        val collects = settings?.collects ?: showsTokenGrid

        var tokenRows: List<TokenUsageDailyRow>? = null
        if (collects) {
            tokenRows = attempt { s -> service.fetchMyTokenDaily(s.accessToken, s.userID, TokenDailyGrid.dayString(since.timeIntervalSince1970)) }
                .getOrNull()
            if (generation != context.generation || !isCurrent("records", serial)) return
        }

        // 공유 Codex 계정 비율(v0.3.36). 저장본 복구를 먼저 한다 — 첫 프레임에 부푼 잔디가 떴다가 내려앉지 않게.
        if (tokenShareRatio == null) tokenShareRatio = storedTokenShareRatio()
        refreshTokenShareRatio(tokenRows, collects, now, generation)
        if (generation != context.generation || !isCurrent("records", serial)) return

        // 진행 중인 내 세션의 시작 시각. **신호가 신선할 때만** 얹는다(끊긴 세션을 now 까지 세면 부풀린다). 팀이 없으면 진행 중 세션도 없다.
        var ongoingStart: SwiftDate? = null
        if (teamID != null) {
            val statuses = attempt { s -> service.fetchTeamStatuses(s.accessToken, teamID, now) }.getOrNull()
            if (generation != context.generation || !isCurrent("records", serial)) return
            val mine = statuses?.firstOrNull { it.id == userID }
            if (mine != null && mine.presence(now) == MemberPresence.ActiveWorking) ongoingStart = mine.currentSessionStartedAt
        }

        val input = MeRecordsInput(
            rows = rows, tokenRows = tokenRows, collects = collects, now = now, goalSeconds = goalSeconds,
            ongoingStart = ongoingStart, previousTokenGrid = tokenGrid, accountShareRatio = tokenShareRatio ?: 1.0,
        )
        // 세션이 많은 계정(수천 행)에서 메인을 막지 않게 계산은 밖에서.
        val output = withContext(computeContext) { MeRecordsOutput.compute(input) }
        if (generation != context.generation || !isCurrent("records", serial)) return
        if (heatmap != output.insights.heatmap) heatmap = output.insights.heatmap
        if (retro != output.insights.retro) retro = output.insights.retro
        if (dailyGrid != output.insights.dailyGrid) dailyGrid = output.insights.dailyGrid
        if (tokenGrid != output.tokenGrid) tokenGrid = output.tokenGrid
        showsTokenGrid = collects
        recordsWeekKey = RetroWeekKey.current(now.timeIntervalSince1970)
        recordsState.hasLoaded = true
        recordsState.hasFailed = false
        recordsState.loadedAt = context.clock.now()
        // 위젯의 토큰 줄은 이 잔디에서 나온다 — 리밋보다 늦게 도착한 토큰 값을 여기서 한 번 민다.
        aiLimits.pushToWidget()
    } finally {
        if (isCurrent("records", serial)) recordsState.isLoading = false
    }
}

/**
 * 보드에서 공유 Codex 계정 비율을 한 번 읽어 [MeStore.tokenShareRatio] 를 갱신한다(v0.3.36). **아무것도 비우지 않는다**.
 * 게이트(하나라도 걸리면 왕복 0건): 수집 꺼짐 · 일별 조회 실패 · 이번 달 버킷 합 0 · 월초 유예(KST 1~3일) · 300초 스로틀 · 떠 있는 왕복.
 * 비율은 이 로드의 산출물이 아니라 **계정 단위 캐시**라 순번 가드를 두지 않는다(늦게 온 응답을 버리면 도장만 남아 300초 넘게 부푼다).
 */
internal suspend fun MeStore.refreshTokenShareRatio(tokenRows: List<TokenUsageDailyRow>?, collects: Boolean, now: SwiftDate, generation: Int) {
    if (!collects || tokenRows == null) return
    // 달은 이 호출의 시계로 뽑는다 — 분자(보드 p_month)와 분모(버킷 접두어)가 같은 순간의 같은 키여야 한다.
    val month = TokenUsageMonthKey.current(now)
    val bucketSum = TokenDailyMerge.accountBucketSum(MeRecords.facts(tokenRows), month)
    if (bucketSum <= 0) return
    // 월초 유예 — 새 달의 지분비는 0 부터 다시 쌓여 첫 며칠은 잡음이다. 직전에 잰 비율을 그대로 쓴다.
    if (TokenRowDisplayRule.shareRatioMonthIsYoung(now.timeIntervalSince1970)) return
    val last = lastTokenBoardFetchAt
    if (last != null && now.timeIntervalSince(last) < 300) return
    if (isFetchingTokenBoard) return
    isFetchingTokenBoard = true
    try {
        val service = context.service
        val result = attempt { s -> service.fetchTokenBoard(s.accessToken, month) }
        if (generation != context.generation) return
        val rows: List<TokenBoardRow> = result.getOrElse { e ->
            // 취소는 실패가 아니다 — 도장을 안 찍는다(탭을 떠나는 흔한 동작이 300초 동안 잠기지 않게).
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            // 네트워크·5xx: 조용히 캐시를 지킨다. 끝난 시도이므로 도장을 찍는다 → 300초 뒤 재시도.
            lastTokenBoardFetchAt = context.clock.now()
            return
        }
        // 응답이 오는 사이 월말 자정을 넘겼으면 다른 달의 비율이다 — 쓸 수 없는 왕복이라 도장도 안 찍는다.
        if (month != TokenUsageMonthKey.current(context.clock.now())) return
        lastTokenBoardFetchAt = context.clock.now()
        val userID = context.sessionStore.userID ?: return
        val mine = rows.toTokenBoardEntries().firstOrNull { it.userID == userID } ?: return // 내 행 없음 → 캐시 유지.
        // INV-MeStoreRecords-58baa2b2 이식: 이 가드를 통과해야만 codexAccountShare 를 쓴다. 옛 RPC(codex_effective 없음)면 엔트리의 값이
        //   폐기된 max(로컬, 계정) 증폭기라 그걸로 비율을 만들면 잔디를 되부풀린다 → 캐시 유지.
        val server = TokenRowServerValue.of(
            mine.userID, month, mine.total, mine.claudeTotal, mine.codexEffective, mine.antigravityEffective,
            mine.codexAccountMonth, mine.hasServerCodexEffective, now.timeIntervalSince1970,
        ) ?: return
        // share == null(옛 표가 이긴 행)이면 캐시 유지. share == 0 은 null 과 다르다(진짜 몫 0).
        val share = server.codexAccountShare ?: return
        // 몫이 분모를 넘었다 = 분자와 분모가 다른 스냅샷이다 — 클램프의 '안전 착지'는 캐시가 없는 첫 로드에서만 안전하다.
        if (share > bucketSum && tokenShareRatio != null) return
        val ratio = TokenRowDisplayRule.accountShareRatio(share, bucketSum)
        tokenShareRatio = ratio
        persistTokenShareRatio(ratio)
    } finally {
        isFetchingTokenBoard = false
    }
}

/** 계정별 키(같은 폰에서 계정을 바꿔도 앞 사람의 비율을 물려받지 않게). */
internal val MeStore.tokenShareRatioKey: String? get() = context.sessionStore.userID?.let { "aing.me.codexShareRatio.$it" }

internal fun MeStore.storedTokenShareRatio(): Double? {
    val key = tokenShareRatioKey ?: return null
    return context.keyValueStore.getString(key)?.toDoubleOrNull()
}

internal fun MeStore.persistTokenShareRatio(ratio: Double) {
    val key = tokenShareRatioKey ?: return
    context.keyValueStore.putString(key, ratio.toString())
}

/** 화면에 그릴 회고 — 목표선은 **지금** 팀 목표를 따른다(목표가 계산 뒤에 확정·변경돼도 회고가 옛 목표에 굳지 않게). */
val MeStore.retroForDisplay: WeeklyRetro?
    get() {
        val retro = retro ?: return null
        val hours = context.sessionStore.profile?.teamGoalHours ?: return retro
        val goalSeconds = hours * 3600
        return if (retro.goalSeconds == goalSeconds) retro else retro.withGoal(goalSeconds)
    }

/** 본문 대신 보일 자리 문구(null 이면 본문). */
val MeStore.recordsPlaceholder: String?
    get() = MeText.recordsPlaceholder(
        hasLoaded = recordsState.hasLoaded,
        hasFailed = recordsState.hasFailed,
        totalSeconds = heatmap.totalSeconds + dailyGrid.totalSeconds,
        hasTokenGrass = showsTokenGrid && tokenGrid.totalTokens > 0,
    )

internal fun MeStore.discardRecords() {
    recordsWeekKey = null
    heatmap = WorkRhythmHeatmap.empty
    retro = null
    dailyGrid = WorkDailyGrid.empty
    tokenGrid = TokenDailyGrid.empty
    recordsState.hasLoaded = false
    recordsState.loadedAt = null
    // 배너도 내린다(맥 discardInsightsIfWeekRolledOver, WorkTimerStoreInsights.swift 194-196) — 보여 줄 회고가 없다.
    // 이번 주 키는 소비하지 않는다: 재계산이 성공하면 evaluateRetroBanner 가 새 회고로 다시 판정한다.
    showsRetroBanner = false
}

/** 기록 계산 입력(메인 밖으로 넘긴다 — 전부 불변 값). */
internal data class MeRecordsInput(
    val rows: List<WorkSessionRow>,
    val tokenRows: List<TokenUsageDailyRow>?,
    val collects: Boolean,
    val now: SwiftDate,
    val goalSeconds: Long,
    val ongoingStart: SwiftDate?,
    val previousTokenGrid: TokenDailyGrid,
    /** 서버 **계정 버킷**에만 곱하는 공유 Codex 계정 비율. 1.0 이면 항등. */
    val accountShareRatio: Double,
)

internal data class MeRecordsOutput(val insights: WorkInsightsComputation, val tokenGrid: TokenDailyGrid) {
    companion object {
        fun compute(input: MeRecordsInput): MeRecordsOutput {
            val now = input.now.timeIntervalSince1970
            val insights = WorkInsightsComputation.build(
                MeRecords.sessions(input.rows), now, input.goalSeconds, input.ongoingStart?.timeIntervalSince1970,
            )
            val tokenRows = input.tokenRows
            val grid = when {
                !input.collects -> TokenDailyGrid.empty
                // 폰에는 로컬 스캐너가 없다 — 서버 일별 합만. 공유 비율은 **계정 버킷에만** 곱한다.
                tokenRows != null -> TokenDailyGrid.build(
                    TokenDailyMerge.merged(TokenDailyMerge.serverTotals(MeRecords.facts(tokenRows), input.accountShareRatio), emptyMap()), now,
                )
                // 서버 조회 실패: 직전 잔디를 물려준다(주가 바뀌었으면 loadRecords 가 이미 비웠다).
                else -> TokenDailyGrid.build(emptyMap(), now).overlaying(input.previousTokenGrid)
            }
            return MeRecordsOutput(insights, grid)
        }
    }
}

/** 와이어 행 → 규칙 사실(rules 는 wire 에 기대지 않는다 — 칸 이름 그대로 옮긴다). */
internal object MeRecords {
    fun sessions(rows: List<WorkSessionRow>): List<WorkSessionTimes> = rows.map { WorkSessionTimes(it.startedAt, it.endedAt) }

    fun facts(rows: List<TokenUsageDailyRow>): List<TokenDailyRowFacts> =
        rows.map { TokenDailyRowFacts(it.day, it.claudeTotal, it.codexTotal, it.codexAccount, it.codexUtcTotal) }
}
