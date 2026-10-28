// 원본: Sources/CheckMobileKit/Rankings/RankingsStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.rankings

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchMiniGameBoard
import com.yehsung.aingcheck.core.net.fetchMiniGameYesterdayWinner
import com.yehsung.aingcheck.core.net.fetchTeamLeaderboard
import com.yehsung.aingcheck.core.net.fetchTokenBoard
import com.yehsung.aingcheck.core.net.fetchTokenUsageSettings
import com.yehsung.aingcheck.core.rules.insights.TeamLeagueWeekNavigator
import com.yehsung.aingcheck.core.rules.insights.TokenBoardMonthNavigator
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import com.yehsung.aingcheck.core.wire.models.MiniGameWinner
import com.yehsung.aingcheck.core.wire.models.TeamLeaderboardEntry
import com.yehsung.aingcheck.core.wire.models.TeamLeagueDisplay
import com.yehsung.aingcheck.core.wire.models.TokenBoardEntry
import com.yehsung.aingcheck.core.wire.models.TokenUsageDayKey
import com.yehsung.aingcheck.core.wire.models.TokenUsageMonthKey
import com.yehsung.aingcheck.core.wire.models.leagueDisplay
import com.yehsung.aingcheck.core.wire.models.sortedByAverageDescending
import com.yehsung.aingcheck.core.wire.models.sortedByTotalDescending
import com.yehsung.aingcheck.core.wire.models.sortedForMiniGameBoard
import com.yehsung.aingcheck.core.wire.models.toTokenBoardEntries
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * 한 판(리그·토큰·미니게임)의 불러오기 상태. 맥의 `…Loaded / …Loading / …Failed` 세 깃발과 같은 뜻이다 —
 * "로드 전"·"진행 중"·"실패"를 가르지 않으면 빈 목록 자리에 엉뚱한 문구가 뜬다.
 */
data class RankingsLoadState(
    /** 한 번이라도 성공했다(빈 목록이어도). */
    val hasLoaded: Boolean = false,
    val isLoading: Boolean = false,
    /** 마지막 조회가 실패로 끝났다. */
    val hasFailed: Boolean = false,
    /** 마지막 성공 시각(스토어 시계). 신선도 판정에 쓴다. */
    val loadedAt: SwiftDate? = null,
)

/**
 * 순위 탭 스토어(SPEC-ios §3.4) — 팀 리그(`team_weekly_leaderboard`) · AI 토큰(`token_usage_board`, 달 넘기기) ·
 * 미니게임(`minigame_board` + `minigame_yesterday_winner`). 전부 **읽기**다(C§4 #13 — 폰 금지 호출 0).
 *
 * **공유 Codex 비율은 서버값만 쓴다**(G §2-3 W2-b ③ · 기억 `shared-codex-split-lives-only-in-the-server`): 토큰 보드 행의
 * `codex_effective`(계정 우선 규칙으로 서버가 나눈 몫) · `codex_account_month`(이미 나눈 내 몫) · `total` 을 **그대로** 그린다. 이 스토어는
 * 비율을 다시 재지 않는다(`TokenRowDisplayRule.accountShareRatio` · `scaledAccountBucket` 은 데스크톱 로컬 스캐너 몫 — 여기서 부르지 않는다,
 * 구조 시험 RankingsServerShareTest). 정렬도 서버 `total` 로만 한다.
 *
 * 수명: 생성(네트워크 없음) · [appDidBecomeActive](탭이 보이면 낡은 판을 다시 읽는다) · [appDidEnterBackground] · [reset] · [badgeCount] 0.
 * 탭 화면이 [tabDidAppear]/[tabDidDisappear] 를 부른다. **보이지 않는 탭은 서버를 두드리지 않는다.** 주기 폴링은 없다.
 *
 * 늦은 응답 가드(맥 performLoad… 관용): 세대(로그아웃) · 요청 순번(같은 판을 연달아 부르면 마지막 것만) · 보고 있는 주/달/게임 종류.
 */
class RankingsStore(
    val context: SessionContext,
    parentScope: CoroutineScope,
    /** 이름 비교(Swift `localizedStandardCompare`). */
    private val collation: Collation,
) {
    val scope: CoroutineScope = CoroutineScope(parentScope.coroutineContext + SupervisorJob(parentScope.coroutineContext[Job]))

    var board: RankingsBoard by mutableStateOf(RankingsBoard.league)
        private set
    var isTabVisible: Boolean by mutableStateOf(false)
        private set

    // ---------------------------------------------------------------- 팀 리그

    /** 서버가 준 전체 목록(1인당 평균 내림차순). 표시 목록은 [leagueDisplay]. */
    var league: List<TeamLeaderboardEntry> by mutableStateOf(emptyList())
        private set
    var leagueState: RankingsLoadState by mutableStateOf(RankingsLoadState())
        private set

    /** 보고 있는 주(KST 월요일 'YYYY-MM-DD'). **오프셋이 아니라 절대 키다.** */
    var leagueWeekKey: String by mutableStateOf("")
        private set

    /** 서버가 `p_week_offset` 을 아는가. **조회마다 다시 판정한다.** */
    var leagueWeekOffsetSupported: Boolean by mutableStateOf(true)
        private set

    /** **그 주를 고른 시점의 '이번 주'** — 사용자가 고른 과거 주와 '이번 주 자체가 옮겨 간 것'을 가르는 유일한 값. */
    private var leagueWeekAnchor: String = ""

    // ---------------------------------------------------------------- AI 토큰

    /** 보고 있는 달(KST 'YYYY-MM'). 기본은 이번 달. */
    var tokenMonth: String by mutableStateOf("")
        private set
    var tokenBoard: List<TokenBoardEntry> by mutableStateOf(emptyList())
        private set
    var tokenState: RankingsLoadState by mutableStateOf(RankingsLoadState())
        private set

    /** 내 토큰 사용량 공개 여부(내 행 "비공개" 칩). null = 모른다. */
    var myTokenUsagePublic: Boolean? by mutableStateOf(null)
        private set

    // ---------------------------------------------------------------- 미니게임

    var miniGameKind: MiniGameKind by mutableStateOf(MiniGameKind.timingBar)
        private set
    var miniGameBoard: List<MiniGameBoardEntry> by mutableStateOf(emptyList())
        private set
    var miniGameWinner: MiniGameWinner? by mutableStateOf(null)
        private set
    var miniGameState: RankingsLoadState by mutableStateOf(RankingsLoadState())
        private set

    private var leagueSerial = 0
    private var tokenSerial = 0
    private var miniGameSerial = 0

    /** 사용자가 달을 옮기지 않았으면 true — 앱을 켜 둔 채 달이 바뀌면 새 달로 따라간다. */
    private var tokenMonthFollowsCurrent = true

    /** 나 탭이 공개 설정 저장 성공을 알린 횟수 — 토큰 판 조회가 떠날 때 찍고, 도착했을 때 달라졌으면 그 응답의 공개 여부는 저장 전 값이다. */
    private var privacyNoteSerial = 0
    private val inflight = ArrayList<Job>()

    init {
        // 주입 시계만 쓴다 — 시험이 일요일 23:59 에서 시작한다.
        val now = context.clock.now()
        tokenMonth = TokenUsageMonthKey.current(now)
        val currentWeek = TeamLeagueWeekNavigator.currentKey(now.timeIntervalSince1970)
        leagueWeekKey = currentWeek
        leagueWeekAnchor = currentWeek
    }

    private fun nowSeconds(): Double = context.clock.now().timeIntervalSince1970

    // ---------------------------------------------------------------- 자리 API

    fun appDidBecomeActive() {
        if (!isTabVisible) return
        refreshIfStale()
    }

    fun appDidEnterBackground() {}

    fun reset() {
        for (task in inflight) task.cancel()
        inflight.clear()
        leagueSerial += 1
        tokenSerial += 1
        miniGameSerial += 1
        league = emptyList()
        leagueState = RankingsLoadState()
        leagueWeekKey = TeamLeagueWeekNavigator.currentKey(nowSeconds())
        leagueWeekAnchor = leagueWeekKey
        // 접힌 채 물려주면 db push 가 끝난 뒤에도 다음 계정이 화살표를 못 본다.
        leagueWeekOffsetSupported = true
        tokenMonth = TokenUsageMonthKey.current(context.clock.now())
        tokenMonthFollowsCurrent = true
        tokenBoard = emptyList()
        tokenState = RankingsLoadState()
        myTokenUsagePublic = null
        miniGameBoard = emptyList()
        miniGameWinner = null
        miniGameState = RankingsLoadState()
        board = RankingsBoard.league
        miniGameKind = MiniGameKind.timingBar
    }

    val badgeCount: Int get() = 0

    // ---------------------------------------------------------------- 화면 사건

    fun tabDidAppear() {
        isTabVisible = true
        // 여는 길은 전부 이번 주로 떨어뜨린다(탭 진입 · 보드 전환 · 재진입).
        syncLeagueWeekToCurrent()
        refreshIfStale()
    }

    fun tabDidDisappear() {
        isTabVisible = false
    }

    /** 딥링크(`aingcheck://rankings/<board>`). */
    fun open(target: RankingsBoard) = select(target)

    fun select(target: RankingsBoard) {
        if (board == target) {
            // 이미 리그인 채로 다시 고르는 딥링크도 명시적 "리그를 열어라"다.
            if (target == RankingsBoard.league) syncLeagueWeekToCurrent()
            refreshIfStale()
            return
        }
        board = target
        if (target == RankingsBoard.league) syncLeagueWeekToCurrent()
        refreshIfStale()
    }

    /** 당겨서 새로고침 · [다시 시도] — 지금 세그먼트를 신선도와 무관하게 다시 읽는다. */
    suspend fun refresh() {
        when (board) {
            RankingsBoard.league -> loadLeague()
            RankingsBoard.tokens -> loadTokens()
            RankingsBoard.minigame -> loadMiniGame()
        }
    }

    /** 지금 세그먼트가 한 번도 안 읽혔거나 낡았으면 다시 읽는다(작업 발사 — 화면 사건에서 부른다). */
    fun refreshIfStale() {
        if (!context.sessionStore.isSignedIn) return
        rollTokenMonthIfNeeded()
        // ① 롤오버가 먼저다 — 뒤집으면 아래 가드가 갱신을 영영 막는다.
        rollLeagueWeekIfNeeded()
        val state = when (board) {
            RankingsBoard.league -> {
                // ② 과거 주는 종료된 기록만 세므로 다시 물어도 같은 표다 — 주기 갱신은 이번 주에만. 단 **아직 못 읽은 주는 예외**.
                if (!(TeamLeagueWeekNavigator.isCurrentWeek(leagueWeekKey, nowSeconds()) || leagueState.hasFailed || !leagueState.hasLoaded)) return
                leagueState
            }
            RankingsBoard.tokens -> tokenState
            RankingsBoard.minigame -> miniGameState
        }
        if (state.isLoading) return
        val loadedAt = state.loadedAt
        if (loadedAt != null && context.clock.now().timeIntervalSince(loadedAt) < staleSeconds && !state.hasFailed) return
        launch { refresh() }
    }

    // ---------------------------------------------------------------- 팀 리그

    val myTeamID: String? get() = context.sessionStore.profile?.teamID

    /** 표시 목록 + 문구가 필요한 사실 둘(계산값이라 [league] 와 어긋날 수 없다). */
    val leagueDisplayPage: TeamLeagueDisplay get() = league.leagueDisplay(myTeamID, collation)

    val leagueDisplay: List<TeamLeaderboardEntry> get() = leagueDisplayPage.entries

    /** 머리글·행·문구 함수가 **같은 '지금'** 을 본다. */
    val leagueNow: SwiftDate get() = context.clock.now()

    val leagueTitle: String get() = RankingsText.leagueTitle(leagueWeekKey, leagueNow)
    val leagueWeekName: String get() = RankingsText.leagueWeekName(leagueWeekKey, leagueNow)
    val isLeaguePastWeek: Boolean get() = !TeamLeagueWeekNavigator.isCurrentWeek(leagueWeekKey, leagueNow.timeIntervalSince1970)
    val canStepLeagueWeekBack: Boolean get() = TeamLeagueWeekNavigator.canStepBack(leagueWeekKey, leagueNow.timeIntervalSince1970)
    val canStepLeagueWeekForward: Boolean get() = TeamLeagueWeekNavigator.canStepForward(leagueWeekKey, leagueNow.timeIntervalSince1970)
    val showsLeagueWeekNavigation: Boolean get() = leagueWeekOffsetSupported

    /** 보던 주를 이번 주로 되돌린다. **요청은 부르는 쪽이 낸다.** */
    private fun syncLeagueWeekToCurrent() {
        val current = TeamLeagueWeekNavigator.currentKey(nowSeconds())
        leagueWeekAnchor = current
        if (leagueWeekKey == current) return
        leagueSerial += 1
        leagueWeekKey = current
        league = emptyList()
        leagueState = RankingsLoadState()
    }

    /** 주 롤오버 되돌림(열어 둔 채 월요일 0시를 넘긴 경우). 판정은 **앵커**다. */
    private fun rollLeagueWeekIfNeeded() {
        if (leagueWeekAnchor == TeamLeagueWeekNavigator.currentKey(nowSeconds())) return
        syncLeagueWeekToCurrent()
    }

    /** 주 이동(`-1` = ◂ 과거 · `+1` = ▸ 현재 쪽). 값이 안 바뀌면 요청도 없다. */
    fun stepLeagueWeek(delta: Int) {
        if (!leagueWeekOffsetSupported) return
        val keyBeforeRoll = leagueWeekKey
        rollLeagueWeekIfNeeded()
        val snapped = leagueWeekKey != keyBeforeRoll
        val next = TeamLeagueWeekNavigator.step(leagueWeekKey, delta, nowSeconds())
        if (next == leagueWeekKey) {
            // 스냅이 행을 비웠으므로 채워 줄 사람이 여기밖에 없다(폰 리그엔 주기 타이머가 없다).
            if (snapped) {
                leagueState = leagueState.copy(isLoading = true)
                launch { loadLeague() }
            }
            return
        }
        leagueSerial += 1
        leagueWeekKey = next
        league = emptyList()
        leagueState = RankingsLoadState(isLoading = true)
        launch { loadLeague() }
    }

    suspend fun loadLeague() {
        if (!context.sessionStore.isSignedIn) return
        rollLeagueWeekIfNeeded()
        leagueSerial += 1
        val serial = leagueSerial
        val weekKey = leagueWeekKey
        val weekOffset = TeamLeagueWeekNavigator.offset(weekKey, nowSeconds())
        val generation = context.generation
        leagueState = leagueState.copy(isLoading = true, hasFailed = false)
        try {
            val service = context.service
            val page = context.withSessionRetry { session -> service.fetchTeamLeaderboard(session.accessToken, weekOffset.toLong()) }
            if (generation != context.generation || serial != leagueSerial) return
            val sorted = page.entries.sortedByAverageDescending(collation)
            val now = context.clock.now()
            // ── ① 옛 서버(p_week_offset 모름) ── 돌아온 행은 **이번 주**다. 추가 요청도 내지 않는다.
            if (!page.supportsWeekOffset) {
                leagueWeekOffsetSupported = false
                val current = TeamLeagueWeekNavigator.currentKey(now.timeIntervalSince1970)
                leagueWeekAnchor = current
                leagueWeekKey = current
                league = sorted
                leagueState = leagueState.copy(hasLoaded = true, hasFailed = false, loadedAt = now)
                return
            }
            leagueWeekOffsetSupported = true
            // ── ② 늦은 응답: 기다리는 사이 주를 옮겼으면 화면엔 안 꽂는다.
            if (weekKey != leagueWeekKey) return
            // ── ③ 서버가 답한 주를 따른다(조회 중 월요일 0시를 넘긴 경우의 유일한 어긋남).
            val answered = page.serverWeekStart ?: weekKey
            if (answered != leagueWeekKey) {
                leagueWeekKey = answered
                if (answered == TeamLeagueWeekNavigator.currentKey(now.timeIntervalSince1970)) leagueWeekAnchor = answered
            }
            if (league != sorted) league = sorted
            leagueState = leagueState.copy(hasLoaded = true, hasFailed = false, loadedAt = now)
        } catch (error: Throwable) {
            if (generation != context.generation || serial != leagueSerial || weekKey != leagueWeekKey) return
            if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return
            leagueState = leagueState.copy(hasFailed = true)
        } finally {
            // 순번만 본다 — 여기에 주 키를 넣으면 '서버 주 채택' 갈래에서 "불러오는 중"이 영영 남는다(맥이 두 번 고친 결함).
            if (serial == leagueSerial) leagueState = leagueState.copy(isLoading = false)
        }
    }

    // ---------------------------------------------------------------- AI 토큰

    val myUserID: String? get() = context.sessionStore.userID

    /** 오늘(KST) 키 — 행의 "오늘 +N" 판정. */
    val todayKey: String get() = TokenUsageDayKey.current(context.clock.now())

    val isCurrentTokenMonth: Boolean get() = !TokenBoardMonthNavigator.canStepForward(tokenMonth, nowSeconds())

    val tokenTitle: String get() = RankingsText.tokenTitle(tokenMonth, context.clock.now())

    /** 달 이동(-1 과거 · +1 미래). 미래는 이번 달로 막힌다 — 값이 그대로면 요청도 없다. */
    fun stepTokenMonth(delta: Int) {
        val now = context.clock.now()
        val next = TokenBoardMonthNavigator.step(tokenMonth, delta, now.timeIntervalSince1970)
        if (next == tokenMonth) return
        tokenSerial += 1
        tokenMonth = next
        tokenMonthFollowsCurrent = next == TokenUsageMonthKey.current(now)
        // 이전 달 행이 '이번 달인 척' 남지 않게 비우고 로드 전으로 되돌린다.
        tokenBoard = emptyList()
        tokenState = RankingsLoadState(isLoading = true)
        launch { loadTokens() }
    }

    suspend fun loadTokens() {
        if (!context.sessionStore.isSignedIn) return
        rollTokenMonthIfNeeded()
        tokenSerial += 1
        val serial = tokenSerial
        val month = tokenMonth
        val generation = context.generation
        val privacyStamp = privacyNoteSerial
        tokenState = tokenState.copy(isLoading = true, hasFailed = false)
        val service = context.service
        try {
            coroutineScope {
                // 공개 여부는 독립 실패(못 읽으면 칩만 안 그린다). GET 한 번 — focus_mode 칸도 딸려 오지만 읽기만 하고 버린다(PATCH 금지).
                val privacy = async {
                    runCatching {
                        context.withSessionRetry { session -> service.fetchTokenUsageSettings(session.accessToken, session.userID).isPublic }
                    }.getOrNull()
                }
                val rows = try {
                    context.withSessionRetry { session -> service.fetchTokenBoard(session.accessToken, month) }
                } catch (error: Throwable) {
                    privacy.await()
                    if (generation != context.generation || serial != tokenSerial || month != tokenMonth) return@coroutineScope
                    if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return@coroutineScope
                    tokenState = tokenState.copy(hasFailed = true)
                    return@coroutineScope
                }
                val isPublic = privacy.await()
                if (generation != context.generation || serial != tokenSerial || month != tokenMonth) return@coroutineScope
                // 서버 행 그대로(공유 Codex 몫 · 총합은 서버가 나눈 값) — 정렬도 서버 total 로만.
                val entries = rows.toTokenBoardEntries().sortedByTotalDescending(collation)
                if (tokenBoard != entries) tokenBoard = entries
                // 조회가 떠 있는 사이 나 탭 저장이 끝났으면(칩이 이미 새 값) 옛 공개 여부로 되돌리지 않는다.
                if (isPublic != null && privacyStamp == privacyNoteSerial) myTokenUsagePublic = isPublic
                tokenState = tokenState.copy(hasLoaded = true, hasFailed = false, loadedAt = context.clock.now())
            }
        } finally {
            if (serial == tokenSerial) tokenState = tokenState.copy(isLoading = false)
        }
    }

    /** 나 탭에서 공개 설정을 바꿨다(서버 저장 성공 뒤) — 내 행 "비공개" 칩을 바로 맞춘다. */
    fun noteTokenUsagePublic(isPublic: Boolean) {
        privacyNoteSerial += 1
        myTokenUsagePublic = isPublic
    }

    private fun rollTokenMonthIfNeeded() {
        val current = TokenUsageMonthKey.current(context.clock.now())
        if (!tokenMonthFollowsCurrent || tokenMonth == current) return
        tokenMonth = current
        tokenBoard = emptyList()
        tokenState = RankingsLoadState()
    }

    // ---------------------------------------------------------------- 미니게임

    fun select(kind: MiniGameKind) {
        if (kind == miniGameKind) return
        miniGameKind = kind
        miniGameSerial += 1
        miniGameBoard = emptyList()
        miniGameWinner = null
        miniGameState = RankingsLoadState(isLoading = true)
        launch { loadMiniGame() }
    }

    /** 내 오늘 순위(1부터). 없으면 null. */
    val myMiniGameRank: Int?
        get() {
            val me = myUserID ?: return null
            val index = miniGameBoard.indexOfFirst { it.userID == me }
            return if (index >= 0) index + 1 else null
        }

    val miniGamePlayers: Int get() = miniGameBoard.size

    /** 오늘 한 사람 수를 **안다**(실패로 0 인 값을 "아무도 안 했다"로 말하지 않는다). */
    val knowsMiniGamePlayerCount: Boolean
        get() = MobileLoadKnowledge.knowsCount(miniGameBoard.isNotEmpty(), miniGameState.hasLoaded, miniGameState.hasFailed)

    /** 오늘 순위 + 어제 1등. 두 조회는 **독립 실패**. 함수가 없는 서버(PGRST202)는 실패가 아니라 "아직 없음"으로 조용히 접는다. */
    suspend fun loadMiniGame() {
        if (!context.sessionStore.isSignedIn) return
        miniGameSerial += 1
        val serial = miniGameSerial
        val kind = miniGameKind
        val generation = context.generation
        miniGameState = miniGameState.copy(isLoading = true, hasFailed = false)
        val service = context.service
        try {
            try {
                val entries = context.withSessionRetry { session -> service.fetchMiniGameBoard(session.accessToken, kind.rawValue, null) }
                if (generation != context.generation || serial != miniGameSerial || kind != miniGameKind) return
                val sorted = entries.sortedForMiniGameBoard(collation)
                if (miniGameBoard != sorted) miniGameBoard = sorted
                miniGameState = miniGameState.copy(hasLoaded = true, hasFailed = false, loadedAt = context.clock.now())
            } catch (error: Throwable) {
                if (generation != context.generation || serial != miniGameSerial || kind != miniGameKind) return
                if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return
                miniGameState = if (error == SupabaseWorkServiceError.DatabaseSchemaMissing) {
                    miniGameState.copy(hasLoaded = true, loadedAt = context.clock.now())
                } else {
                    miniGameState.copy(hasFailed = true)
                }
                return
            }
            val winner = runCatching {
                context.withSessionRetry { session -> service.fetchMiniGameYesterdayWinner(session.accessToken, kind.rawValue) }
            }.getOrNull()
            if (generation != context.generation || serial != miniGameSerial || kind != miniGameKind) return
            if (miniGameWinner != winner) miniGameWinner = winner
        } finally {
            if (serial == miniGameSerial) miniGameState = miniGameState.copy(isLoading = false)
        }
    }

    // ---------------------------------------------------------------- 내부

    private fun launch(body: suspend () -> Unit) {
        inflight.removeAll { it.isCancelled || it.isCompleted }
        inflight += scope.launch { body() }
        if (inflight.size > 8) repeat(inflight.size - 8) { inflight.removeAt(0) }
    }

    companion object {
        /** 이만큼 지난 판은 탭 표시·active 때 다시 읽는다. */
        const val staleSeconds: Double = 30.0
    }
}
