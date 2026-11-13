// 원본: Sources/CheckCore/CrossyDuelStore.swift:222-1463(스토어) @ e4995a3a — Android 판 8(아이폰 1.0.18 맞추기)
//
// 1:1 길건너 대결 스토어 — 화면 상태 · 서버 동기화 · 판 구동 · 보고 루프 · RPC 호출(SPEC v1.3 §8.3, TetrisDuelStore 규약).
// 판 갈래는 CrossyDuelStoreGame.kt, 프레임은 CrossyDuelStoreFrames.kt, 순위는 CrossyDuelStoreRanking.kt.
//
// 규약(맥·폰과 같다 — 메모리 duel-store-alert-doorbell-rules 다섯 규칙 처음부터):
//  · 서버가 권위 · 서버 시계 보정 · 판 밖 폴링은 창이 보이고 안 가려졌을 때만 · 늦은 응답 버리기(두 세대 + 판 세대 + seq) · 신호 합치기 ·
//    한 판 한 기기(서버 `my_device` → 없으면 장부).
//  · 말풍선 문 = `isWindowVisible && !isWindowOccluded` · `windowDidShow` 는 가림 기록을 안 지움 · `lobbyAgain` 합치기 ·
//    폴링 걸음은 [outsidePolling] + 걸음 사이 가드 · 취소로 접힌 조회는 [handOffLobby].
//  · 판 시계 = 단조 시계([uptime]). 벽시계([clock])는 로비 스로틀 · 장부 · 서버 시각 환산에만.
//  · 사용자 문구는 [CrossyDuelNoticeText] 한 곳에만.
//
// Kotlin 이식(테트리스 Kotlin 스토어와 같다): Swift `@MainActor` = [scope] 한 곳 · `Task {}` = [scope] launch · `@Observable` = mutableStateOf ·
// `weak var host` = 강한 참조(세대로 늦은 응답을 버린다).
package com.yehsung.aingcheck.core.stores.crossy

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.crossyDuelCancel
import com.yehsung.aingcheck.core.net.crossyDuelChallenge
import com.yehsung.aingcheck.core.net.crossyDuelLobby
import com.yehsung.aingcheck.core.net.crossyDuelResign
import com.yehsung.aingcheck.core.net.crossyDuelRespond
import com.yehsung.aingcheck.core.net.crossyDuelState
import com.yehsung.aingcheck.core.rules.crossy.CrossyDuelSession
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.stores.games.GameDeviceLedger
import com.yehsung.aingcheck.core.stores.tetris.DISTANT_PAST
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.stores.tetris.StoreNaturalCollation
import com.yehsung.aingcheck.core.stores.tetris.clampedInt
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.CrossyDuelInviteRow
import com.yehsung.aingcheck.core.wire.games.CrossyDuelLobbyMe
import com.yehsung.aingcheck.core.wire.games.CrossyDuelLobbyResponse
import com.yehsung.aingcheck.core.wire.games.CrossyDuelPeerRow
import com.yehsung.aingcheck.core.wire.games.CrossyDuelRPCStatus
import com.yehsung.aingcheck.core.wire.games.CrossyDuelStatePayload
import com.yehsung.aingcheck.core.wire.games.CrossyDuelUserRow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException
import kotlin.coroutines.coroutineContext
import kotlin.math.abs
import kotlin.random.Random
import kotlin.time.TimeSource

class CrossyDuelStore(
    host: CrossyDuelStoreHost? = null,
    /** 이 스토어의 일이 도는 곳(Swift `@MainActor`). 앱은 메인, 시험은 시험 디스패처. */
    val scope: CoroutineScope,
    /** 벽시계(로비 스로틀 · 장부 · 서버 시각 환산). 조립 지점이 넣는다. */
    var clock: () -> SwiftDate,
    val collation: Collation = StoreNaturalCollation,
    var logger: Logger? = null,
) {
    var host: CrossyDuelStoreHost? = host
        private set

    fun attach(host: CrossyDuelStoreHost) {
        this.host = host
    }

    companion object {
        const val outgoingPollSeconds: Double = 5.0
        const val lobbyPollSeconds: Double = 30.0
        const val menuLobbyThrottleSeconds: Double = 30.0
        const val rankingPollSeconds: Double = 60.0
        /** 상대 침묵 표시 문턱(초, v1.1 CC-19). */
        const val opponentQuietSeconds: Double = 8.0
        /** 판 루프 한 걸음(초). */
        const val gameLoopSeconds: Double = 0.05
        const val reloadDedupeSeconds: Double = 1.0
        const val serverClockToleranceSeconds: Double = 0.25
        const val inviteExpiryToleranceSeconds: Double = 1.0
        /** 보고가 이만큼 연달아 실패하면 `connectionTrouble`. 55P03 은 세지 않는다(§3.1 CC-21). */
        const val reportFailureLimit: Int = 2
        internal const val TAG: String = "crossy-duel"

        /** 가벼운 로비 응답인가 — 전적 셋이 모두 null(서버는 가벼운 로비에서만 null 을 준다 — 0 이 아니다). */
        fun isLightLobby(response: CrossyDuelLobbyResponse): Boolean {
            val me = response.me ?: return response.users?.isEmpty() ?: true
            return me.wins == null && me.losses == null && me.draws == null
        }

        /** state 의 규칙 값이 이 앱의 엔진 기대값(100 · 180)과 같은가. 키가 없으면(옛 응답) 같다고 본다. */
        fun rulesMatch(goal: Long?, maxDurationSeconds: Long?): Boolean =
            (goal ?: CrossyDuelSession.EXPECTED_GOAL.toLong()) == CrossyDuelSession.EXPECTED_GOAL.toLong() &&
                (maxDurationSeconds ?: CrossyDuelSession.EXPECTED_MAX_DURATION_SECONDS.toLong()) == CrossyDuelSession.EXPECTED_MAX_DURATION_SECONDS.toLong()

        /** 서버 `result`·`winner` → 내 기준 결과(무승부 사유는 result 'draw'). */
        fun outcome(result: String?, winner: String?, myID: String?): CrossyDuelOutcome? {
            if (result == "draw") return CrossyDuelOutcome.draw
            val w = winner?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
            myID ?: return null
            return if (w == myID) CrossyDuelOutcome.win else CrossyDuelOutcome.loss
        }

        fun steadyInvite(fresh: CrossyDuelInvite, previous: CrossyDuelInvite?): CrossyDuelInvite {
            if (previous == null || previous.id != fresh.id || previous.stake != fresh.stake || previous.peer != fresh.peer ||
                abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) >= inviteExpiryToleranceSeconds
            ) return fresh
            return previous
        }

        fun matchJustFinished(old: CrossyDuelMatchState?, new: CrossyDuelMatchState?): Boolean {
            if (new == null || !new.isFinished) return false
            return !(old?.id == new.id && old.isFinished)
        }

        fun matchTransitionLine(old: CrossyDuelMatchState?, new: CrossyDuelMatchState?): String? {
            fun finished(m: CrossyDuelMatchState?) = m?.isFinished ?: false
            fun started(m: CrossyDuelMatchState?) = m?.startAt != null
            fun ready(m: CrossyDuelMatchState?) = m?.meReady ?: false
            val sameMatch = old?.id == new?.id
            if (sameMatch && finished(old) == finished(new) && started(old) == started(new) && ready(old) == ready(new)) return null
            return "state ready=${ready(new)} started=${started(new)} finished=${finished(new)} " +
                "reason=${new?.endReason?.rawValue ?: "none"} sameMatch=$sameMatch"
        }

        /** 서버 사람 행 → 화면 값(로비). `capable` 이 null 이면 **불가**다. */
        fun user(row: CrossyDuelUserRow): CrossyDuelUser? {
            val id = row.id?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
            return CrossyDuelUser(
                id = id, displayName = row.displayName ?: "", avatarURL = row.avatarUrl, characterID = row.character,
                isWorking = row.isWorking ?: false, isCapable = row.capable ?: false, inMatch = row.inMatch ?: false,
                isFocused = row.focusMode ?: false,
            )
        }

        /** 로비 정렬: 서버 정렬과 같은 규칙(working desc → capable desc → 이름 → 원래 순서)의 되맞춤. */
        fun sortedForLobby(users: List<CrossyDuelUser>, collation: Collation = StoreNaturalCollation): List<CrossyDuelUser> {
            fun rank(u: CrossyDuelUser): Int = when {
                u.isWorking && u.isCapable && !u.inMatch -> 0
                u.isWorking && u.isCapable -> 1
                u.isWorking -> 2
                else -> 3
            }
            return users.withIndex().sortedWith { l, r ->
                val a = rank(l.value)
                val b = rank(r.value)
                if (a != b) return@sortedWith a.compareTo(b)
                val order = collation.compare(l.value.displayName, r.value.displayName)
                if (order != 0) return@sortedWith order
                l.index.compareTo(r.index)
            }.map { it.value }
        }
    }

    // MARK: 화면 상태 (관찰 대상)

    var phase: CrossyDuelPhase by mutableStateOf(CrossyDuelPhase.lobby)
        internal set
    var availability: CrossyDuelAvailability by mutableStateOf(CrossyDuelAvailability.available)
        internal set
    var users: List<CrossyDuelUser> by mutableStateOf(emptyList())
        internal set
    var record: CrossyDuelRecord? by mutableStateOf(null)
        internal set
    /** 받은 신청(최신이 앞). 화면은 [visibleIncomingInvites]·[visibleIncoming] 을 읽는다. */
    var incoming: List<CrossyDuelInvite> by mutableStateOf(emptyList())
        internal set
    var outgoing: CrossyDuelInvite? by mutableStateOf(null)
        internal set

    private val matchState = mutableStateOf<CrossyDuelMatchState?>(null)
    var match: CrossyDuelMatchState?
        get() = matchState.value
        internal set(value) {
            val old = matchState.value
            matchState.value = value
            matchTransitionLine(old, value)?.let { logNotice(it) }
            if (matchJustFinished(old, value)) onMatchFinished?.invoke()
        }

    private val noticeState = mutableStateOf<String?>(null)
    /** 안내줄 한 줄. 쓰는 문은 [setNotice] 하나. */
    val notice: String? get() = noticeState.value
    var isBusy: Boolean by mutableStateOf(false)
        internal set
    var isWindowVisible: Boolean by mutableStateOf(false)
        internal set
    /** 창이 완전히 가려졌다(판은 계속 흐른다 — 폴링과 말풍선 문만 본다). */
    var isWindowOccluded: Boolean by mutableStateOf(false)
        internal set
    var rubyBalance: Long? by mutableStateOf(null)
        internal set
    var hasLoadedLobby: Boolean by mutableStateOf(false)
        internal set
    var lobbyLoadFailed: Boolean by mutableStateOf(false)
        internal set
    /** 보고가 연달아 실패하는 중(판 화면의 "연결 확인 중"). */
    var connectionTrouble: Boolean by mutableStateOf(false)
        internal set
    /** 진행 중인 내 판을 같은 계정의 다른 기기가 두고 있다. */
    var playingElsewhere: Boolean by mutableStateOf(false)
        internal set
    var ranking: CrossyDuelRankingBoard? by mutableStateOf(null)
        internal set
    /** 서버에 `crossy_duel_ranking` 이 아직 없다(PGRST202). */
    var rankingUnavailable: Boolean by mutableStateOf(false)
        internal set

    /** 순위 적재의 주 스위치. 기본 false — 켜는 곳은 앱 배선 한 줄. */
    var rankingEnabled: Boolean = false
    var selectedStake: CrossyDuelStake by mutableStateOf(CrossyDuelStake.three)
    /** 차단으로 걷어낸 상대(소유자가 채운다). */
    var hiddenPeerIDs: Set<String> by mutableStateOf(emptySet())

    val visibleUsers: List<CrossyDuelUser>
        get() = if (hiddenPeerIDs.isEmpty()) users else users.filter { it.id !in hiddenPeerIDs }

    /** 받은 신청 전부(화면용) — 차단 거울 + 지금 내 판과 같은 id 는 뺀다. */
    val visibleIncomingInvites: List<CrossyDuelInvite>
        get() {
            val matchID = match?.id
            return incoming.filter { it.peer.id !in hiddenPeerIDs && it.id != matchID }
        }

    /** 배너가 읽는 받은 신청 하나(가장 최근). **시계를 읽지 않는다** — 만료는 스토어 타이머가 걷는다. */
    val visibleIncoming: CrossyDuelInvite? get() = visibleIncomingInvites.firstOrNull()

    /**
     * G §8-17 #1(Android): 이 빌드가 판돈 대결의 **신청·수락**을 내는가(앱 구성 깃발 `duelsEnabled`, 기본 꺼짐 — 테트리스 Kotlin 스토어와 같다).
     * 호스트가 없으면 false. 거절 · 취소 · 기권 · 순위는 판돈이 새로 걸리지 않아 막지 않는다.
     */
    val duelsEnabled: Boolean get() = host?.appConfig?.duelsEnabled ?: false

    /** 확성기 배너를 미룬다(카운트다운 · 판 중). */
    val defersMegaphoneBanner: Boolean get() = phase == CrossyDuelPhase.countdown || phase == CrossyDuelPhase.playing

    /** 화면 켜짐 붙들기(카운트다운 · 판 중이고 이 기기가 연 판). */
    val holdsActivity: Boolean
        get() = (phase == CrossyDuelPhase.countdown || phase == CrossyDuelPhase.playing) && !playingElsewhere

    // MARK: 판 (관찰 대상 아님)

    /** 내 판 구동기. **관찰 대상이 아니다** — 화면은 프레임 루프 안에서 [raceSnapshot] 으로 읽는다. */
    var duel: CrossyDuelSession? = null
        internal set
    /** '이 기기가 연 판' 장부(앱 배선이 `defaults` 를 넣는다). */
    val deviceLedger = GameDeviceLedger(game = "crossy_duel", ttlSeconds = 3600.0)
    var duelMatchID: String? = null
        internal set
    var duelGeneration: Int = 0
        internal set
    internal var gameLoopJob: Job? = null
    internal var gameLoopToken = 0
    /** 판 루프의 한 걸음(초). 창과 무관하게 돈다. 시험은 크게 재우고 [tick] 을 직접 부른다. */
    var gameLoopStepSeconds: Double = gameLoopSeconds
    /** 지금 나가 있는 보고(마지막 것). 시험이 join 으로 기다린다. */
    var reportJob: Job? = null
        internal set
    var reportInFlight: Boolean = false
        internal set
    var reportInFlightKind: CrossyDuelSession.ReportKind? = null
        internal set
    var reportSentAt: Double? = null
        internal set
    var reportTicket: Int = 0
        internal set
    var reportFailureStreak: Int = 0
        internal set
    var heldMySeq: Long = 0
        internal set
    var heldOpponentSeq: Long = 0
        internal set
    /** 상대 침묵 재료: 응답의 `server_now_ms − opponent.last_seen_ms`(초)와 그 응답을 받은 단조 시각. */
    var opponentSilenceAtReceipt: Double? = null
        internal set
    var opponentSilenceReceivedAt: Double? = null
        internal set
    /** 서버가 `other_device` 로 돌려보내 **물러난** 판. */
    var yieldedMatchIDs: Set<String> = emptySet()
        internal set
    internal var lastHoldingActivity = false

    private val monotonic = TimeSource.Monotonic.markNow()

    /** **단조 시계**(초). 판 시계 · 보고 간격 · [raceSnapshot] 기본값. */
    var uptime: () -> Double = { monotonic.elapsedNow().inWholeNanoseconds / 1e9 }

    // MARK: 판 표시 프레임 (관찰 대상 아님 — 로직은 CrossyDuelStoreFrames.kt)

    var frameLink: CrossyDuelFrameLink? = null
        internal set
    var frameLinkMatchID: String? = null
        internal set
    var frameChannel: CrossyDuelFrameChannel? = null
        internal set
    internal var frameChannelResolved = false
    /** 프레임 소켓을 만드는 문. **조립 지점이 넣는다**(리얼타임 킬스위치 · 시험 프로세스 판정 포함). 기본은 null(시험 · 미리보기 — 대체 길). */
    var makeFrameChannel: () -> CrossyDuelFrameChannel? = { null }
    /** 재시도 지터(full jitter). 시험은 `{ it }` 로 결정적으로 만든다. */
    var frameJitter: (Double) -> Double = { ceiling -> if (ceiling <= 0) 0.0 else Random.nextDouble(0.0, ceiling) }
    /** 프레임 소켓에 connect 를 시켰고 아직 disconnect 를 안 시켰다(닫기의 기준). */
    var frameSocketOpen: Boolean = false
        internal set
    var frameSocketTopic: String? = null
        internal set
    var frameSocketToken: String? = null
        internal set
    internal var frameConnectTicket = 0
    internal var loggedFramesConfirmed: Boolean? = null

    // MARK: 내부 장부 (관찰 대상 아님)

    var pollStepSeconds: Double = 0.5
    var serverClockOffset: Double = 0.0
        private set
    private var hasServerClockOffset = false
    /** 루비 잔액을 마지막으로 옮긴 응답의 `server_now_ms`(늦은 응답 가드). */
    private var rubyServerNowMs: Double? = null
    var resetGeneration: Int = 0
        private set
    var stateInFlightID: String? = null
        private set
    private var pendingStateID: String? = null
    internal var stateInFlight = false
    private var stateAgain = false
    private var lobbyInFlight = false
    private var lobbyAgain = false
    private var lobbyAgainWantsUsers = false
    internal var rankingInFlight = false
    /** 서버가 말한 내 진행 중 대결 id. */
    var activeMatchID: String? = null
        private set
    var seenInviteIDs: Set<String> = emptySet()
        private set
    private var announcedMatchIDs: Set<String> = emptySet()
    /** [로비로] 로 접은 끝난 판. */
    var dismissedMatchIDs: Set<String> = emptySet()
        private set
    var pollJob: Job? = null
        private set
    private var pollToken = 0
    private var expiryJob: Job? = null
    var lastStateRequestAt: SwiftDate = DISTANT_PAST
    var lastLobbyRequestAt: SwiftDate = DISTANT_PAST
    var lastOutgoingRequestAt: SwiftDate = DISTANT_PAST
    var lastMenuLobbyAt: SwiftDate = DISTANT_PAST
    var lastRankingRequestAt: SwiftDate = DISTANT_PAST
    var syncJob: Job? = null
        private set
    private var syncPendingTrailing = false
    var inviteTTLSeconds: Double = 60.0
        private set
    private var outgoingRevision = 0
    private var lobbyRequestOutgoingRevision = 0

    // MARK: UI · 앱 배선 문

    var presentWindow: (() -> Unit)? = null
    var dismissWindow: (() -> Unit)? = null
    var requestAttention: (() -> Unit)? = null
    var onInviteArrived: ((CrossyDuelInvite) -> Unit)? = null
    /** matchStarted 만. */
    var onAttention: ((CrossyDuelAttention) -> Unit)? = null
    /** 내 판이 끝난 것을 처음 본 순간 한 번(미션 꼬리). */
    var onMatchFinished: (() -> Unit)? = null
    /** [holdsActivity] 가 바뀔 때. */
    var onHoldingActivityChange: ((Boolean) -> Unit)? = null

    internal fun logNotice(message: String) {
        logger?.log(LogLevel.INFO, TAG, message)
    }

    // MARK: - 창

    /** 창을 띄우고 로비(사람 목록까지)·판을 읽는다. [focusMatchID] 는 배너에서 온 경로의 대상이다. */
    fun openWindow(focusMatchID: String?) {
        if (host?.session != null) {
            val focus = focusMatchID?.lowercase()
            // 곧 이어질 windowDidShow 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다.
            lastLobbyRequestAt = clock()
            scope.launch {
                refreshLobby()
                if (focus != null && focus != match?.id && incoming.none { it.id == focus }) refreshMatch(focus)
            }
        }
        presentWindow?.invoke()
    }

    /** 창이 실제로 보이기 시작했다. 폴링 시작 · 로비 재조회 · **준비 보고의 문이 열린다**. */
    fun windowDidShow() {
        // 열린 채 가려진 창을 다시 부르는 길이면 가림 기록을 **그대로 둔다**(규칙 ②).
        val reshownWhileOccluded = isWindowVisible && isWindowOccluded
        if (!isWindowVisible) isWindowVisible = true
        if (!reshownWhileOccluded && isWindowOccluded) isWindowOccluded = false
        startPolling()
        if (duel != null) tick()
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastLobbyRequestAt) >= reloadDedupeSeconds) scope.launch { refreshLobby() }
        if (rankingEnabled && phase == CrossyDuelPhase.lobby && now.timeIntervalSince(lastRankingRequestAt) >= reloadDedupeSeconds) {
            scope.launch { refreshRanking() }
        }
    }

    /** 창이 숨었다. 폴링만 멈춘다 — **판은 계속 흐른다**. */
    fun windowDidHide() {
        if (isWindowVisible) isWindowVisible = false
        if (isWindowOccluded) isWindowOccluded = false
        stopPolling()
    }

    /** 창을 **정말 닫았다**. **닫기는 기권이 아니다** — 진행 중 판은 그대로 흐른다. 끝난 판은 여기서 접는다. */
    fun windowDidClose() {
        if (isWindowVisible) isWindowVisible = false
        if (isWindowOccluded) isWindowOccluded = false
        stopPolling()
        foldFinishedMatch()
    }

    /** 창의 가림 상태가 바뀌었다. 폴링을 멈추고 되살린다. */
    fun windowOcclusionDidChange(visible: Boolean) {
        if (isWindowOccluded != !visible) isWindowOccluded = !visible
        if (visible) startPolling() else stopPolling()
    }

    // MARK: - 조회

    /** 창 경로 → 사람 목록까지. */
    suspend fun refreshLobby() = loadLobby(true)

    /** 바깥 신호 경로 → 가벼운 로비(`me` 만, v1.1 CS-4). */
    suspend fun refreshLightLobby() = loadLobby(false)

    /**
     * 로비를 읽는다. 도는 중에 또 불리면 끝난 뒤 **한 번 더** 읽는다(`lobbyAgain` — 규칙 ③). 합친 부름 중 하나라도 사람 목록을
     * 원했으면 그 한 바퀴는 전체 로비다. 나르던 작업이 취소돼 조회가 접히면 합쳐진 부름은 취소 밖으로 넘긴다([handOffLobby] — 규칙 ⑤).
     */
    suspend fun loadLobby(wantsUsers: Boolean) {
        if (host?.session == null) return
        if (lobbyInFlight) {
            lobbyAgain = true
            if (wantsUsers) lobbyAgainWantsUsers = true
            return
        }
        lobbyInFlight = true
        val generation = resetGeneration
        val sessionGeneration = host?.sessionGeneration
        var owed = false
        var users = wantsUsers
        var full = users
        var completed = false
        try {
            do {
                if (owed) users = lobbyAgainWantsUsers
                lobbyAgain = false
                lobbyAgainWantsUsers = false
                if (users) lastLobbyRequestAt = clock()
                lobbyRequestOutgoingRevision = outgoingRevision
                full = users
                val wanted = full
                val result = perform { service, token -> service.crossyDuelLobby(token, wanted) }
                if (result == null) {
                    completed = !(coroutineContext[Job]?.isCancelled ?: false)
                    return
                }
                when (result) {
                    is DuelCall.Success -> applyLobby(result.value)
                    is DuelCall.Failure -> {
                        if (isSchemaMissing(result.error)) {
                            logNotice("lobby unavailable — crossy duel functions missing on server")
                            noteServerMissing()
                        } else {
                            logNotice("lobby request failed")
                        }
                        if (!lobbyLoadFailed) lobbyLoadFailed = true
                    }
                }
                owed = true
            } while (lobbyAgain && generation == resetGeneration)
            completed = true
        } finally {
            val handOff = !completed && (owed || lobbyAgain)
            val handOffUsers = lobbyAgainWantsUsers || (!owed && full)
            if (generation == resetGeneration) lobbyInFlight = false
            if (handOff) handOffLobby(handOffUsers, generation, sessionGeneration)
        }
    }

    /** 로비를 나르던 작업 자체가 취소돼 조회가 접혔는데 합쳐진 부름이 남았다 — 그 한 번을 **취소 밖** 작업으로 낸다(규칙 ⑤). */
    private fun handOffLobby(users: Boolean, generation: Int, sessionGeneration: Int?) {
        scope.launch {
            if (generation != resetGeneration || host?.sessionGeneration != sessionGeneration || lobbyInFlight) return@launch
            loadLobby(users)
        }
    }

    /** 로비 응답을 옮긴다. **가벼운 응답**은 `users`·`record` 를 덮지 않는다(v1.1 CS-4). */
    suspend fun applyLobby(response: CrossyDuelLobbyResponse) {
        if (response.status != CrossyDuelRPCStatus.ok) {
            logNotice("lobby refused status=${response.status.rawValue}")
            when (response.status) {
                CrossyDuelRPCStatus.unsupportedClient -> noteUpdateRequired()
                CrossyDuelRPCStatus.notSignedIn -> setNotice(CrossyDuelNoticeText.signInAgain)
                else -> Unit
            }
            if (!lobbyLoadFailed) lobbyLoadFailed = true
            return
        }
        noteServerNow(response.serverNowMs)
        if (availability != CrossyDuelAvailability.available) availability = CrossyDuelAvailability.available
        if (lobbyLoadFailed) lobbyLoadFailed = false
        val light = isLightLobby(response)
        if (!light) {
            if (!hasLoadedLobby) hasLoadedLobby = true
            response.users?.let { rows ->
                val mapped = sortedForLobby(rows.mapNotNull(::user), collation)
                if (users != mapped) users = mapped
            }
        }
        val me = response.me
        if (me != null) {
            applyRuby(me.rubyBalance, response.serverNowMs)
            if (!light) {
                val fresh = CrossyDuelRecord((me.wins ?: 0).clampedInt(), (me.losses ?: 0).clampedInt(), (me.draws ?: 0).clampedInt())
                if (record != fresh) record = fresh
            }
            // ★ 신청을 옮기기 **전에** 적는다 — 보낸 신청이 판으로 이어졌는지(becameMatch)를 이 값으로 가른다.
            activeMatchID = me.activeMatchId?.lowercase()
        }
        applyLobbyInvites(me)
        val active = activeMatchID
        if (active != null && (match?.id != active || match?.isFinished == true)) refreshMatch(active)
    }

    /** 로비 `me` 의 신청 둘(받은 것 배열 · 보낸 것 하나)을 화면 값으로 옮긴다. */
    private fun applyLobbyInvites(me: CrossyDuelLobbyMe?) {
        val rows = me?.incoming
        if (rows != null) {
            val fresh = mutableListOf<CrossyDuelInvite>()
            for (row in rows) {
                val invite = invite(row, row.from) ?: continue
                // 지금 내 판으로 이어진 신청은 되살리지 않는다(늦은 로비).
                if (invite.id == match?.id) continue
                fresh.add(steadyInvite(invite, incoming.firstOrNull { it.id == invite.id }))
            }
            if (incoming != fresh) incoming = fresh
            for (invite in fresh) {
                if (invite.id in seenInviteIDs) continue
                seenInviteIDs = seenInviteIDs + invite.id
                if (invite.peer.id in hiddenPeerIDs) continue
                onInviteArrived?.invoke(invite)
            }
        } else if (me != null && incoming.isNotEmpty()) {
            incoming = emptyList()
        }

        val serverOutgoing = me?.outgoing?.let { invite(it, it.to) }
        val predatesOutgoing = lobbyRequestOutgoingRevision < outgoingRevision
        val gone = outgoing
        if (gone != null && serverOutgoing?.id != gone.id && !predatesOutgoing) {
            val becameMatch = gone.id == activeMatchID || gone.id == match?.id
            if (!becameMatch) {
                setNotice(if (gone.expiresAt > clock()) CrossyDuelNoticeText.inviteDeclined else CrossyDuelNoticeText.inviteTimedOut)
            }
            outgoing = null
        }
        if (serverOutgoing != null && serverOutgoing.id != match?.id &&
            (!predatesOutgoing || outgoing == null || outgoing?.id == serverOutgoing.id)
        ) {
            val steady = steadyInvite(serverOutgoing, outgoing)
            if (outgoing != steady) outgoing = steady
        }
        scheduleInviteExpiry()
    }

    suspend fun refreshMatch() = refreshMatch(match?.id ?: activeMatchID)

    /** 한 판(또는 신청)의 상태를 읽는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다. 다른 판 id 는 기억했다가 그다음에 읽는다. */
    suspend fun refreshMatch(rawID: String?) {
        val requested = rawID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return
        if (host?.session == null) return
        if (stateInFlight) {
            if (requested == stateInFlightID) stateAgain = true else pendingStateID = requested
            return
        }
        stateInFlight = true
        val generation = resetGeneration
        try {
            var nextID: String? = requested
            while (nextID != null) {
                val id: String = nextID
                nextID = null
                stateInFlightID = id
                do {
                    stateAgain = false
                    lastStateRequestAt = clock()
                    if (outgoing?.id == id) lastOutgoingRequestAt = lastStateRequestAt
                    val result = perform { service, token -> service.crossyDuelState(token, id) }
                    if (generation != resetGeneration) return
                    when (result) {
                        is DuelCall.Success -> {
                            val response = result.value
                            noteServerNow(response.serverNowMs)
                            when (response.status) {
                                CrossyDuelRPCStatus.ok -> response.state?.let { applyState(it, uptime()) }
                                CrossyDuelRPCStatus.notFound -> dropMatchOrInvite(id)
                                CrossyDuelRPCStatus.unsupportedClient -> noteUpdateRequired()
                                else -> logNotice("state refused status=${response.status.rawValue}")
                            }
                        }
                        is DuelCall.Failure -> if (isSchemaMissing(result.error)) noteServerMissing()
                        null -> Unit
                    }
                } while (stateAgain)
                pendingStateID?.let {
                    pendingStateID = null
                    nextID = it
                }
            }
        } finally {
            if (generation == resetGeneration) {
                stateInFlightID = null
                stateInFlight = false
            }
        }
    }

    enum class StateApplyOutcome { applied, ignored }

    /**
     * 판 상태를 옮긴다 — **판과 신청을 한 경로로 가르는 유일한 깔때기**(보고 · 상태 조회 · 수락 · 기권 응답이 전부 여기로 온다).
     * 늦은 응답 가드: [로비로] 로 접은 끝난 판 · 이미 끝남으로 든 판의 진행 중 응답 · 다른 진행 판을 들고 있을 때의 남의 판 ·
     * 같은 판의 내 seq·상대 seq 감소 스냅숏 · 모르는 status. 판정·루비는 **서버 값만** 옮긴다(프레임은 이 함수를 지나지 않는다).
     * @param receivedAt 이 응답을 **받은** 단조 시각. null 이면 지금.
     */
    fun applyState(payload: CrossyDuelStatePayload, receivedAt: Double? = null): StateApplyOutcome {
        val id = payload.matchId?.lowercase()?.takeIf { it.isNotEmpty() } ?: return StateApplyOutcome.ignored
        val received = receivedAt ?: uptime()
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance, payload.serverNowMs)
        val status = payload.status ?: ""
        when (status) {
            "pending" -> {
                if (match?.id == id) return StateApplyOutcome.ignored
                if (incoming.none { it.id == id } && outgoing?.id != id) scope.launch { refreshLightLobby() }
                return StateApplyOutcome.applied
            }
            "active", "finished" -> Unit
            "declined", "cancelled", "expired" -> {
                dropMatchOrInvite(id, if (status == "expired") CrossyDuelNoticeText.inviteTimedOut else CrossyDuelNoticeText.inviteDeclined)
                return StateApplyOutcome.applied
            }
            else -> {
                logNotice("state ignored — unknown status=$status")
                return StateApplyOutcome.ignored
            }
        }

        val isFinished = status == "finished"
        if (isFinished && id in dismissedMatchIDs && match?.id != id) return StateApplyOutcome.ignored
        val current = match
        if (current != null && current.id != id && !current.isFinished) return StateApplyOutcome.ignored
        val base = if (current?.id == id) current else null
        if (base != null && base.isFinished && !isFinished) return StateApplyOutcome.ignored
        // 규칙 값 두 출처 금지(§8.1 CC-17): 진행 중 판의 goal·상한이 이 앱의 엔진과 다르면 두지 않는다.
        if (!isFinished && !rulesMatch(payload.goal, payload.maxDurationSeconds)) {
            logNotice("state ignored — rules differ goal=${payload.goal ?: -1} max=${payload.maxDurationSeconds ?: -1}")
            noteUpdateRequired()
            return StateApplyOutcome.ignored
        }
        val mySeq = payload.me?.seq ?: 0
        val opponentSeq = payload.opponent?.seq ?: 0
        if (base != null && !isFinished && (mySeq < heldMySeq || opponentSeq < heldOpponentSeq)) return StateApplyOutcome.ignored
        if (base == null) {
            heldMySeq = 0
            heldOpponentSeq = 0
            opponentSilenceAtReceipt = null
            opponentSilenceReceivedAt = null
        }
        heldMySeq = maxOf(heldMySeq, mySeq)
        heldOpponentSeq = maxOf(heldOpponentSeq, opponentSeq)
        val serverNow = payload.serverNowMs
        val seen = payload.opponent?.lastSeenMs
        if (serverNow != null && seen != null && serverNow.isFinite() && seen.isFinite()) {
            opponentSilenceAtReceipt = maxOf(0.0, (serverNow - seen) / 1000)
            opponentSilenceReceivedAt = received
        }

        val myID = host?.session?.userID?.lowercase()
        val opponentRow = payload.opponent
        val opponentID = opponentRow?.id?.lowercase() ?: base?.opponent?.id ?: ""
        val opponent = peerUser(opponentRow?.id, opponentRow?.displayName, opponentRow?.avatarUrl, opponentRow?.character, !isFinished)
            ?: base?.opponent
            ?: CrossyDuelUser(id = opponentID, displayName = "", inMatch = !isFinished)
        val outcome = if (isFinished) outcome(payload.result, payload.winner, myID) else null
        val stake = payload.stake?.clampedInt() ?: base?.stake ?: 0
        val rubyDelta = outcome?.let {
            when (it) {
                CrossyDuelOutcome.win -> DuelFee.winnerNet(stake)
                CrossyDuelOutcome.loss -> -stake
                CrossyDuelOutcome.draw -> 0
            }
        }
        val intervals = CrossyDuelSession.clampedIntervals(payload.reportMs?.clampedInt(), payload.heartbeatMs?.clampedInt())
        val next = CrossyDuelMatchState(
            id = id, stake = stake, seed = payload.seed ?: base?.seed, opponent = opponent,
            acceptedAt = deviceDate(payload.acceptedAtMs) ?: base?.acceptedAt,
            readyDeadline = deviceDate(payload.readyDeadlineMs) ?: base?.readyDeadline,
            // 시작 시각은 한 번 정해지면 사라지지 않는다(옛 응답의 null 이 지우지 못하게).
            startAt = deviceDate(payload.startAtMs) ?: base?.startAt,
            endAt = deviceDate(payload.endAtMs) ?: base?.endAt,
            graceEndAt = deviceDate(payload.graceEndMs) ?: base?.graceEndAt,
            meReady = (payload.me?.ready ?: false) || (base?.meReady ?: false),
            opponentReady = (payload.opponent?.ready ?: false) || (base?.opponentReady ?: false),
            myServerScore = maxOf((payload.me?.score ?: 0).clampedInt(), if (isFinished) 0 else (base?.myServerScore ?: 0)),
            opponentScore = if (isFinished) {
                payload.opponent?.score?.clampedInt() ?: base?.opponentScore ?: 0
            } else {
                maxOf((payload.opponent?.score ?: 0).clampedInt(), base?.opponentScore ?: 0)
            },
            opponentDeaths = maxOf((payload.opponent?.deaths ?: 0).clampedInt(), if (isFinished) 0 else (base?.opponentDeaths ?: 0)),
            opponentLastSeenAt = deviceDate(payload.opponent?.lastSeenMs) ?: base?.opponentLastSeenAt,
            reportMs = intervals.first, heartbeatMs = intervals.second,
            isFinished = isFinished, outcome = outcome,
            endReason = payload.endReason?.let(CrossyDuelEndReason::of),
            finalMyScore = if (isFinished) payload.final?.me?.clampedInt() else null,
            finalOpponentScore = if (isFinished) payload.final?.opponent?.clampedInt() else null,
            rubyDelta = rubyDelta,
            finishedAt = deviceDate(payload.finishedAtMs) ?: base?.finishedAt,
        )

        // 한 판 한 기기: 서버 `my_device` 가 권위, 없으면 장부. 끝난 판의 기록은 걷는다.
        if (isFinished) {
            dropOwnership(id)
        } else {
            when (payload.myDevice) {
                "this" -> if (id !in yieldedMatchIDs) noteOwnsMatch(id)
                "other" -> dropOwnership(id)
                else -> Unit
            }
        }
        val plays = !isFinished && playsMatch(id, payload.myDevice)
        val wasElsewhere = playingElsewhere
        val elsewhere = !isFinished && !plays

        if (isFinished) {
            if (duelMatchID == id) {
                duel?.freeze()
                // ★ 끝난 판 가지에서 **바로** 프레임 소켓을 닫는다(닫기 누락 = 연결 누수). 장부는 남긴다.
                finishFrames()
            } else {
                discardDuel()
            }
            stopGameLoop()
        } else if (plays) {
            prepareDuel(id, payload)
            if (duelMatchID == id) {
                val startMs = payload.startAtMs
                if (startMs != null && serverNow != null) duel?.syncStart(startMs, serverNow, received)
                duel?.adoptServerSeq(mySeq.clampedInt())
                // ok/stale 응답의 me.score 가 로컬 엔진보다 크면 그 줄로 다시 세운다(CC-22).
                val score = payload.me?.score
                if (score != null && duel?.catchUp(score.clampedInt(), (payload.me?.deaths ?: 0).clampedInt()) == true) {
                    logNotice("duel caught up to server score=$score")
                }
                noteServerFrames(payload.frames, intervals.first, payload.checkpointMs?.clampedInt(), id, opponentID, received)
                startGameLoop()
            }
        } else {
            discardDuel()
        }
        if (playingElsewhere != elsewhere) playingElsewhere = elsewhere

        val justFinished = isFinished && base?.isFinished == false
        val previous = match
        // 말풍선 문은 **보이고 안 가려진** 창만 닫는다(규칙 ①).
        val windowWasVisible = isWindowVisible && !isWindowOccluded
        if (!isFinished && (previous?.id != id || previous.isFinished)) {
            // 판이 서는 순간 서버는 두 사람의 다른 길건너 대기 신청을 전부 닫았다(검토 RV-C-4).
            if (incoming.isNotEmpty()) incoming = emptyList()
        } else if (incoming.any { it.id == id }) {
            incoming = incoming.filter { it.id != id }
        }
        if (outgoing?.id == id) outgoing = null
        if (match != next) match = next
        activeMatchID = if (isFinished) null else id
        refreshPhase()
        if (elsewhere) {
            setNotice(CrossyDuelNoticeText.otherDevice)
        } else {
            if (wasElsewhere && notice == CrossyDuelNoticeText.otherDevice) setNotice(null)
            if (!isFinished && (previous?.id != id || previous.isFinished || wasElsewhere)) {
                setNotice(null)
                noteMatchStarted(next, windowWasVisible)
            }
        }
        if (justFinished) {
            // 전적은 로비 응답에만 있다. 끝난 순간 한 번 다시 읽는다(창이 보이면 사람 목록까지).
            scope.launch { loadLobby(isWindowVisible) }
            noteOwnMatchFinishedForRanking()
        }
        return StateApplyOutcome.applied
    }

    // MARK: - 동작

    /** 신청. 판돈은 고른 값을 그대로 받는다. */
    suspend fun challenge(userID: String, stake: CrossyDuelStake) {
        if (!duelsEnabled) return
        if (isBusy || host?.session == null) return
        val target = userID.lowercase()
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            val result = perform { service, token -> service.crossyDuelChallenge(token, target, stake.rawValue.toLong()) } ?: return
            when (result) {
                is DuelCall.Failure -> noteActionFailure(result.error)
                is DuelCall.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    setNotice(CrossyDuelNoticeText.challenge(response.status, response.need, response.have))
                    if (response.status != CrossyDuelRPCStatus.ok) logNotice("challenge refused status=${response.status.rawValue}")
                    when (response.status) {
                        CrossyDuelRPCStatus.ok -> {
                            val id = response.matchId?.lowercase() ?: return
                            noteOwnsMatch(id)
                            val peer = users.firstOrNull { it.id == target } ?: CrossyDuelUser(id = target, displayName = "")
                            val expiresAt = deviceDate(response.expiresAtMs) ?: clock().addingTimeInterval(inviteTTLSeconds)
                            outgoingRevision += 1
                            outgoing = CrossyDuelInvite(id, peer, stake.rawValue, expiresAt)
                            lastOutgoingRequestAt = clock()
                            scheduleInviteExpiry()
                        }
                        CrossyDuelRPCStatus.unsupportedClient -> noteUpdateRequired()
                        CrossyDuelRPCStatus.alreadyPending, CrossyDuelRPCStatus.busy, CrossyDuelRPCStatus.targetBusy,
                        CrossyDuelRPCStatus.targetOutdated, CrossyDuelRPCStatus.targetFocused,
                        -> refreshLobby() // 목록의 칩이 틀렸다는 뜻 — 다시 읽어 행을 사실에 맞춘다
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    suspend fun cancelChallenge() {
        val invite = outgoing
        if (isBusy || invite == null || host?.session == null) return
        val id = invite.id
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            val result = perform { service, token -> service.crossyDuelCancel(token, id) } ?: return
            when (result) {
                is DuelCall.Failure -> noteActionFailure(result.error)
                is DuelCall.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    setNotice(CrossyDuelNoticeText.cancel(response.status))
                    when (response.status) {
                        CrossyDuelRPCStatus.ok, CrossyDuelRPCStatus.notFound, CrossyDuelRPCStatus.notPending, CrossyDuelRPCStatus.expired -> {
                            if (outgoing?.id == id) {
                                outgoing = null
                                scheduleInviteExpiry()
                            }
                            // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 진행 중 판을 찾아 온다.
                            if (response.status == CrossyDuelRPCStatus.notPending) refreshLobby()
                        }
                        CrossyDuelRPCStatus.unsupportedClient -> noteUpdateRequired()
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    suspend fun respond(inviteID: String, accept: Boolean) {
        if (accept && !duelsEnabled) return
        if (isBusy || host?.session == null) return
        val id = inviteID.lowercase()
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            val result = perform { service, token -> service.crossyDuelRespond(token, id, accept) } ?: return
            when (result) {
                is DuelCall.Failure -> noteActionFailure(result.error)
                is DuelCall.Success -> {
                    val response = result.value
                    val receivedAt = uptime()
                    noteServerNow(response.serverNowMs)
                    setNotice(CrossyDuelNoticeText.respond(accept, response.status, response.side, response.need, response.have))
                    if (response.status != CrossyDuelRPCStatus.ok) logNotice("respond refused status=${response.status.rawValue}")
                    when (response.status) {
                        CrossyDuelRPCStatus.ok -> {
                            incoming = incoming.filter { it.id != id }
                            if (!accept || response.accepted == false) {
                                scheduleInviteExpiry()
                                return
                            }
                            // 이 기기가 수락했다 — 이 기기가 둔다. 상태를 옮기기 **전에** 적는다.
                            noteOwnsMatch(id)
                            if (incoming.isNotEmpty()) incoming = emptyList()
                            if (outgoing != null) outgoing = null
                            scheduleInviteExpiry()
                            val state = response.state
                            if (state != null) applyState(state, receivedAt) else refreshMatch(id)
                            if (match?.id != id && !isWindowVisible) presentWindow?.invoke()
                        }
                        CrossyDuelRPCStatus.notFound, CrossyDuelRPCStatus.notPending, CrossyDuelRPCStatus.expired, CrossyDuelRPCStatus.invalid -> {
                            incoming = incoming.filter { it.id != id }
                            scheduleInviteExpiry()
                        }
                        CrossyDuelRPCStatus.unsupportedClient -> noteUpdateRequired()
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /** 기권(확인은 화면이 받는다). 카운트다운·준비 중에도 된다. */
    suspend fun resign() {
        val current = match
        if (isBusy || current == null || current.isFinished || host?.session == null) return
        // 판정 기다림(100 도달 · 3분 얼림) 중 기권은 보내지 않는다 — 점수로 이긴 판을 넘기지 않게. 결과는 곧 온다.
        if (raceSnapshot()?.waitingForResult == true) return
        val id = current.id
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            val result = perform { service, token -> service.crossyDuelResign(token, id) } ?: return
            when (result) {
                is DuelCall.Failure -> noteActionFailure(result.error)
                is DuelCall.Success -> {
                    val response = result.value
                    val receivedAt = uptime()
                    noteServerNow(response.serverNowMs)
                    setNotice(CrossyDuelNoticeText.resign(response.status))
                    if (response.status == CrossyDuelRPCStatus.unsupportedClient) noteUpdateRequired()
                    if (response.status == CrossyDuelRPCStatus.otherDevice) yieldMatchToOtherDevice(id)
                    val state = response.state
                    if (state != null) applyState(state, receivedAt) else refreshMatch(id)
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /** 결과 화면 [로비로]. **진행 중인 판에서는 아무것도 안 한다** — 빠져나가는 길은 기권뿐이다. */
    fun backToLobby() {
        if (!foldFinishedMatch() || host?.session == null) return
        scope.launch {
            refreshLobby()
            refreshRanking()
        }
    }

    /** 끝난 판을 내리고 화면을 로비로 돌린다. 끝난 판을 들고 있지 않으면 false. */
    private fun foldFinishedMatch(): Boolean {
        val current = match
        if (current == null || !current.isFinished) return false
        dismissedMatchIDs = dismissedMatchIDs + current.id
        clearMatch()
        setNotice(null)
        return true
    }

    // MARK: - 신호 · 계기

    /** 초인종 신호. 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다. */
    fun handleSignal() = requestSync()

    fun requestSync() {
        if (host?.session == null) return
        if (syncJob != null) {
            syncPendingTrailing = true
            return
        }
        val generation = resetGeneration
        syncJob = scope.launch {
            do {
                syncPendingTrailing = false
                syncOnce()
            } while (syncPendingTrailing && generation == resetGeneration)
            if (generation == resetGeneration) syncJob = null
        }
    }

    /** 신호 한 번의 조회: 진행 중 판이 있으면 그 판의 상태, 아니면 로비(창이 보이면 사람 목록까지 · 아니면 가벼운 로비). */
    suspend fun syncOnce() {
        val current = match
        if (current != null && !current.isFinished) refreshMatch(current.id) else loadLobby(isWindowVisible)
    }

    fun realtimeDidJoin() {
        if (host?.session == null) return
        scope.launch { loadLobby(isWindowVisible) }
    }

    fun systemDidWake() {
        if (host?.session == null) return
        scope.launch { loadLobby(isWindowVisible) }
    }

    /** 바깥 경로 → 가벼운 로비. 스로틀 30초. */
    fun refreshLobbyIfStale() {
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastMenuLobbyAt) < menuLobbyThrottleSeconds) return
        lastMenuLobbyAt = now
        scope.launch { refreshLightLobby() }
    }

    // MARK: - 폴링 (창이 보이고 안 가려졌을 때만 · 판 밖)

    fun startPolling() {
        if (pollJob != null || !isWindowVisible || isWindowOccluded) return
        pollToken += 1
        val token = pollToken
        pollJob = scope.launch {
            while (true) {
                delay(delayMillis(pollStepSeconds))
                if (!isActive || token != pollToken || !isWindowVisible || isWindowOccluded) {
                    if (token == pollToken) pollJob = null
                    return@launch
                }
                pollTick(clock())
            }
        }
    }

    fun stopPolling() {
        pollToken += 1
        pollJob?.cancel()
        pollJob = null
    }

    /** 폴링 한 걸음의 조회를 **폴링 작업의 취소 밖에서** 돌리고 끝날 때까지 기다린다(규칙 ④). */
    private suspend fun outsidePolling(body: suspend (CrossyDuelStore) -> Unit) {
        scope.launch { body(this@CrossyDuelStore) }.join()
    }

    /**
     * 안전망 한 걸음. **창이 안 보이거나 가려졌으면 아무것도 하지 않는다.** 걸음 사이사이 창 보임 · 가림 · 취소를 다시 본다(규칙 ④).
     * 보낸 신청 5초 · 로비 30초 · 순위 60초(주 스위치). **판 중에는 조회하지 않는다** — 보고 응답이 판 상태를 가져온다.
     */
    suspend fun pollTick(now: SwiftDate) {
        if (!isWindowVisible || isWindowOccluded || host?.session == null) return
        val sent = outgoing
        if (sent != null && now.timeIntervalSince(lastOutgoingRequestAt) >= outgoingPollSeconds) {
            val id = sent.id
            outsidePolling { it.refreshMatch(id) }
        }
        if (!isWindowVisible || isWindowOccluded || !coroutineContext.isActive) return
        if (phase == CrossyDuelPhase.lobby && now.timeIntervalSince(lastLobbyRequestAt) >= lobbyPollSeconds) {
            outsidePolling { it.refreshLobby() }
        }
        if (!isWindowVisible || isWindowOccluded || !coroutineContext.isActive) return
        if (rankingEnabled && phase == CrossyDuelPhase.lobby && now.timeIntervalSince(lastRankingRequestAt) >= rankingPollSeconds) {
            refreshRanking()
        }
    }

    // MARK: - 리셋

    /** 로그아웃 · 계정 전환. 판·신청·목록을 비운다. **배선 값**(`rankingEnabled` · 시계 · 주기 · UI 문)은 건드리지 않는다. */
    fun reset() {
        resetGeneration += 1
        stopPolling()
        discardDuel()
        expiryJob?.cancel()
        expiryJob = null
        syncJob?.cancel()
        syncJob = null
        syncPendingTrailing = false
        stateInFlight = false
        stateAgain = false
        lobbyInFlight = false
        lobbyAgain = false
        lobbyAgainWantsUsers = false
        rankingInFlight = false
        stateInFlightID = null
        pendingStateID = null
        if (phase != CrossyDuelPhase.lobby) phase = CrossyDuelPhase.lobby
        if (availability != CrossyDuelAvailability.available) availability = CrossyDuelAvailability.available
        if (users.isNotEmpty()) users = emptyList()
        if (record != null) record = null
        if (incoming.isNotEmpty()) incoming = emptyList()
        if (outgoing != null) outgoing = null
        if (match != null) match = null
        if (notice != null) noticeState.value = null
        if (isBusy) isBusy = false
        if (isWindowVisible) isWindowVisible = false
        if (isWindowOccluded) isWindowOccluded = false
        if (rubyBalance != null) rubyBalance = null
        if (hiddenPeerIDs.isNotEmpty()) hiddenPeerIDs = emptySet()
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (hasLoadedLobby) hasLoadedLobby = false
        if (connectionTrouble) connectionTrouble = false
        if (playingElsewhere) playingElsewhere = false
        if (ranking != null) ranking = null
        if (rankingUnavailable) rankingUnavailable = false
        yieldedMatchIDs = emptySet()
        heldMySeq = 0
        heldOpponentSeq = 0
        opponentSilenceAtReceipt = null
        opponentSilenceReceivedAt = null
        serverClockOffset = 0.0
        hasServerClockOffset = false
        rubyServerNowMs = null
        activeMatchID = null
        seenInviteIDs = emptySet()
        announcedMatchIDs = emptySet()
        dismissedMatchIDs = emptySet()
        outgoingRevision = 0
        lobbyRequestOutgoingRevision = 0
        lastStateRequestAt = DISTANT_PAST
        lastLobbyRequestAt = DISTANT_PAST
        lastOutgoingRequestAt = DISTANT_PAST
        lastMenuLobbyAt = DISTANT_PAST
        lastRankingRequestAt = DISTANT_PAST
        inviteTTLSeconds = 60.0
        syncHoldingActivity()
        dismissWindow?.invoke()
    }

    // MARK: - 내부

    /**
     * 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조.
     * null = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 null 이면 **아무것도 바꾸지 않는다.**
     */
    suspend fun <T> perform(operation: suspend (SupabaseWorkService, String) -> T): DuelCall<T>? {
        val host = host ?: return null
        if (host.session == null) return null
        val sessionGeneration = host.sessionGeneration
        val generation = resetGeneration
        val service = host.service
        return try {
            val value = host.withSessionRetry { session -> operation(service, session.accessToken) }
            if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) null else DuelCall.Success(value)
        } catch (e: Exception) {
            if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
            if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) return null
            if (host.classifyAuthError(e) == AuthErrorDisposition.cancelled) return null
            DuelCall.Failure(e)
        }
    }

    /** 서버에 길건너 RPC 가 아직 없다(PGRST202). */
    fun isSchemaMissing(error: Throwable): Boolean = error == SupabaseWorkServiceError.DatabaseSchemaMissing

    private fun noteActionFailure(error: Throwable) {
        if (isSchemaMissing(error)) noteServerMissing() else setNotice(CrossyDuelNoticeText.checkConnection)
    }

    internal fun noteServerMissing() {
        if (availability != CrossyDuelAvailability.serverMissing) availability = CrossyDuelAvailability.serverMissing
        setNotice(CrossyDuelNoticeText.unavailable)
    }

    internal fun noteUpdateRequired() {
        if (availability != CrossyDuelAvailability.updateRequired) availability = CrossyDuelAvailability.updateRequired
        setNotice(CrossyDuelNoticeText.updateMine)
    }

    /** 로비 신청 행 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**. */
    private fun invite(row: CrossyDuelInviteRow, peerRow: CrossyDuelPeerRow?): CrossyDuelInvite? {
        val id = row.matchId?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        val stake = row.stake ?: return null
        val expiresAt = deviceDate(row.expiresAtMs) ?: return null
        val peer = peerUser(peerRow?.id, peerRow?.displayName, peerRow?.avatarUrl, peerRow?.character, false) ?: return null
        return CrossyDuelInvite(id, peer, stake.clampedInt(), expiresAt)
    }

    /** 그 id 가 판이었으면 판을 내리고, 신청이었으면 신청 카드를 걷는다(안내가 있으면 한 줄 — 보낸 신청만). */
    private fun dropMatchOrInvite(id: String, notice: String? = null) {
        dropOwnership(id)
        if (match?.id == id) clearMatch()
        if (activeMatchID == id) activeMatchID = null
        if (incoming.any { it.id == id }) {
            incoming = incoming.filter { it.id != id }
            scheduleInviteExpiry()
        }
        if (outgoing?.id == id) {
            outgoing = null
            if (notice != null) setNotice(notice)
            scheduleInviteExpiry()
        }
    }

    /** 안내줄 한 문. */
    fun setNotice(text: String?) {
        if (notice != text) noticeState.value = text
    }

    /** 서버 잔액을 스토어 · 앱 미러로 옮긴다. 이미 옮긴 잔액보다 **먼저** 서버가 만든 응답의 잔액은 버린다(105 를 95 로 되감지 않게). */
    internal fun applyRuby(value: Long?, serverNowMs: Double?) {
        value ?: return
        if (serverNowMs != null && serverNowMs.isFinite() && serverNowMs > 0) {
            val last = rubyServerNowMs
            if (last != null && serverNowMs < last) return
            rubyServerNowMs = serverNowMs
        }
        if (rubyBalance != value) rubyBalance = value
        val h = host
        if (h != null && h.rubyBalance != value) h.rubyBalance = value
    }

    /** 판을 내린다(판 구동기 · 판 루프 · 보고 · 프레임까지). */
    fun clearMatch() {
        if (match != null) match = null
        if (playingElsewhere) playingElsewhere = false
        discardDuel()
        refreshPhase()
    }

    /** 진행 중 판으로 **처음** 넘어갔다 — 창을 띄우고 주의를 끈다. 창이 안 보였거나 가려졌으면 말풍선 문도 연다(판 id 마다 한 번). */
    private fun noteMatchStarted(next: CrossyDuelMatchState, windowWasVisible: Boolean) {
        if (next.id in announcedMatchIDs) return
        announcedMatchIDs = announcedMatchIDs + next.id
        presentWindow?.invoke()
        requestAttention?.invoke()
        if (windowWasVisible) return
        onAttention?.invoke(CrossyDuelAttention(CrossyDuelAttention.Kind.matchStarted, next.id, next.opponent.displayName))
    }

    /** `server_now_ms` 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만. */
    fun noteServerNow(milliseconds: Double?) {
        if (milliseconds == null || milliseconds <= 0) return
        val measured = milliseconds / 1000 - clock().timeIntervalSince1970
        if (hasServerClockOffset && abs(measured - serverClockOffset) < serverClockToleranceSeconds) return
        serverClockOffset = measured
        hasServerClockOffset = true
    }

    /** 서버 epoch 밀리초 → 기기 시계의 같은 순간. */
    fun deviceDate(milliseconds: Double?): SwiftDate? {
        if (milliseconds == null || milliseconds <= 0) return null
        return SwiftDate(milliseconds / 1000 - serverClockOffset)
    }

    /** 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다(배너가 시계를 읽지 않게 하는 장치). */
    fun scheduleInviteExpiry() {
        expiryJob?.cancel()
        expiryJob = null
        val dates = incoming.map { it.expiresAt } + listOfNotNull(outgoing?.expiresAt)
        val earliest = dates.minOrNull() ?: return
        val wait = maxOf(0.0, earliest.timeIntervalSince(clock())) + 0.25
        val generation = resetGeneration
        expiryJob = scope.launch {
            delay(delayMillis(wait))
            if (generation != resetGeneration) return@launch
            expiryJob = null
            pruneExpiredInvites(clock())
        }
    }

    fun pruneExpiredInvites(now: SwiftDate) {
        if (incoming.any { it.expiresAt <= now }) incoming = incoming.filter { it.expiresAt > now }
        val sent = outgoing
        if (sent != null && sent.expiresAt <= now) {
            outgoing = null
            setNotice(CrossyDuelNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /** 사람 조각 → 화면 값. 행에 없는 칸은 로비 목록에서 빌린다. */
    fun peerUser(rawID: String?, displayName: String?, avatarURL: String?, character: String?, inMatch: Boolean): CrossyDuelUser? {
        val id = rawID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        val known = users.firstOrNull { it.id == id }
        return CrossyDuelUser(
            id = id,
            displayName = displayName ?: known?.displayName ?: "",
            avatarURL = avatarURL ?: known?.avatarURL,
            characterID = character ?: known?.characterID,
            isWorking = known?.isWorking ?: false,
            isCapable = known?.isCapable ?: true,
            inMatch = inMatch,
            isFocused = known?.isFocused ?: false,
        )
    }
}
