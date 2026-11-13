// 원본: Sources/CheckCore/AlkkagiOnlineStore.swift(스토어) · AlkkagiOnlineStoreRanking.swift · AlkkagiOnlineStoreWatch.swift ·
//       AlkkagiOnlineLive.swift(운영 서비스) @ e4995a3a — Android 판 8(아이폰 1.0.18 맞추기)
//
// 1:1 알까기 대결 스토어 — **서버 스냅숏이 권위**다. 이 스토어는 판을 진행시키지 않고 프레임 루프도 없다(쏜 수는 화면이 재생만 한다).
// 규약(맥 · 폰과 같다 — 메모리 duel-store-alert-doorbell-rules 다섯 규칙):
//  ① 말풍선 문 = 창이 안 보이거나 가려졌을 때만 `onAttention` · `onInviteArrived`([attentionDoorIsOpen])
//  ② `windowDidShow` 는 열린 채 가려진 창의 가림 기록을 지우지 않는다
//  ③ 도는 조회에 온 부름은 깃발로 합쳐 끝난 뒤 한 바퀴 더(합친 부름이 사람 목록을 원하면 그 바퀴는 전체 로비)
//  ④ 폴링 걸음 조회는 취소 밖([outsidePolling]) · 걸음 사이 창 보임 · 가림 · 취소 가드
//  ⑤ 조회 엔진은 부른 쪽의 작업이 아니다(독립 작업 — 부른 쪽이 취소돼도 합친 부름까지 끝까지 돈다)
// 폴링: 판 중 3초 박자 그대로 판 상태만 · 판 밖 보낸 신청 5초 · 전체 로비 30초 · 순위 60초 · 메뉴 가벼운 로비 30초 · 관전 2초.
// Kotlin 이식: Swift `@MainActor` = [scope] 한 곳 · `Task {}` = launch · `@Observable` = mutableStateOf. uuid 는 소문자 글자로 견준다.
// Android 판돈 깃발(G §8-17 #1): `duelsEnabled` 가 꺼진 빌드는 신청 · 수락 요청을 내지 않는다(테트리스 · 길건너와 같다).
package com.yehsung.aingcheck.core.stores.alkkagi

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiVector
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.stores.tetris.DISTANT_PAST
import com.yehsung.aingcheck.core.stores.tetris.StoreNaturalCollation
import com.yehsung.aingcheck.core.stores.tetris.clampedInt
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.AlkkagiCall
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchPhase
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchResult
import com.yehsung.aingcheck.core.wire.games.AlkkagiPeer
import com.yehsung.aingcheck.core.wire.games.AlkkagiPlayerWire
import com.yehsung.aingcheck.core.wire.games.AlkkagiRPCStatus
import com.yehsung.aingcheck.core.wire.games.AlkkagiResponse
import com.yehsung.aingcheck.core.wire.games.AlkkagiWire
import com.yehsung.aingcheck.core.wire.games.AlkkagiChatMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException
import kotlin.coroutines.coroutineContext
import kotlin.random.Random

/** 서비스 실패 갈래(Swift `AlkkagiServiceError`). */
sealed class AlkkagiServiceError(message: String) : Exception(message) {
    data object Unavailable : AlkkagiServiceError("unavailable")
    data object NotSignedIn : AlkkagiServiceError("notSignedIn")
    data object ServerMissing : AlkkagiServiceError("serverMissing")
    data object InvalidResponse : AlkkagiServiceError("invalidResponse")
}

/** 알까기 RPC 한 번(시험은 스텁을 끼운다). 취소된 응답은 [CancellationException] 으로 던진다. */
fun interface AlkkagiServing {
    suspend fun call(call: AlkkagiCall): AlkkagiResponse
}

/** 운영 서비스 — 세션 복구 · 공용 `duelRPC`(교착 한 번 다시). 세대가 밀린 응답은 취소로 접는다. */
class AlkkagiLiveService(private val host: GomokuStoreHost, private val generation: () -> Int) : AlkkagiServing {
    override suspend fun call(call: AlkkagiCall): AlkkagiResponse {
        val userID = host.session?.userID ?: throw AlkkagiServiceError.Unavailable
        val sessionGeneration = host.sessionGeneration
        val reset = generation()
        val service = host.service
        val body = service.encode(com.yehsung.aingcheck.core.wire.games.AlkkagiParameters.serializer(), call.parameters)
        fun stale() = host.sessionGeneration != sessionGeneration || host.session?.userID != userID || generation() != reset
        try {
            val response = host.withSessionRetry { session ->
                if (stale()) throw CancellationException("stale")
                service.duelRPC(call.rpcName, body, session.accessToken, AlkkagiResponse.serializer(), true)
            }
            if (stale()) throw CancellationException("stale")
            return response
        } catch (e: Exception) {
            if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
            if (stale()) throw CancellationException("stale")
            if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) throw AlkkagiServiceError.ServerMissing
            if (host.classifyAuthError(e) == AuthErrorDisposition.cancelled) throw CancellationException("cancelled")
            if (e == SupabaseWorkServiceError.SessionExpired) throw AlkkagiServiceError.NotSignedIn
            throw e
        }
    }
}

/** uuid 글자를 견줄 열쇠(소문자 · 모양이 틀리면 null). */
internal fun uuidKey(text: String?): String? = text?.let { SwiftUUID.parse(it)?.lowercased }

/** 동작 한 번의 action_id(uuid v4 소문자). */
internal fun randomUUIDString(random: Random = Random.Default): String {
    val b = ByteArray(16).also { random.nextBytes(it) }
    b[6] = ((b[6].toInt() and 0x0f) or 0x40).toByte()
    b[8] = ((b[8].toInt() and 0x3f) or 0x80).toByte()
    val hex = b.joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
    return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}"
}

class AlkkagiOnlineStore(
    val scope: CoroutineScope,
    service: AlkkagiServing? = null,
    val clock: () -> SwiftDate,
    pollSeconds: Double = 3.0,
    val collation: Collation = StoreNaturalCollation,
    var logger: Logger? = null,
) {
    companion object {
        const val outgoingPollSeconds: Double = 5.0
        const val lobbyPollSeconds: Double = 30.0
        const val menuLobbyThrottleSeconds: Double = 30.0
        const val rankingPollSeconds: Double = 60.0
        const val watchPollSeconds: Double = 2.0
        internal const val TAG = "alkkagi"

        /** 로비 순서: (가능 ∧ 근무) 0 · 가능 1 · 대결 중 2 · 그 밖 3, 같으면 이름 · id. */
        fun sortedForLobby(users: List<AlkkagiLobbyUser>, collation: Collation = StoreNaturalCollation): List<AlkkagiLobbyUser> {
            fun rank(u: AlkkagiLobbyUser): Int = if (u.canBeChallenged) (if (u.isWorking) 0 else 1) else (if (u.inMatch) 2 else 3)
            return users.sortedWith { l, r ->
                val a = rank(l)
                val b = rank(r)
                if (a != b) return@sortedWith a.compareTo(b)
                val byName = collation.compare(l.displayName, r.displayName)
                if (byName != 0) return@sortedWith byName
                l.id.compareTo(r.id)
            }
        }

        /** 조준 중이고 내 차례인 상태(내 차례 말풍선은 이 상태로 **들어설 때**만 운다). */
        fun isMyAim(match: AlkkagiMatch): Boolean = match.phase == AlkkagiMatchPhase.aiming && match.currentPlayer == match.myColor
    }

    var service: AlkkagiServing? = service
        private set
    /** 루비 미러를 빌리는 곳([attach] 가 채운다). null 이면 스토어 값만 바꾼다. 판돈 깃발도 여기서 읽는다. */
    var host: GomokuStoreHost? = null
        private set
    private val pollSeconds: Double = if (pollSeconds.isFinite() && pollSeconds > 0) pollSeconds else 3.0

    /** 운영 배선 — 세션 복구 · 공용 duelRPC 서비스를 물리고 루비 미러를 빌린다. */
    fun attach(host: GomokuStoreHost) {
        reset()
        this.host = host
        service = AlkkagiLiveService(host) { resetGeneration }
    }

    // MARK: 화면 상태

    var users: List<AlkkagiLobbyUser> by mutableStateOf(emptyList())
        internal set
    var incoming: List<AlkkagiInvite> by mutableStateOf(emptyList())
        internal set
    var outgoing: AlkkagiInvite? by mutableStateOf(null)
        internal set
    var me: AlkkagiPeer? by mutableStateOf(null)
        internal set
    private val stateCell = mutableStateOf<AlkkagiMatch?>(null)
    /** 내 판. 바뀌면 관전자 수 칩 값도 따라간다. */
    var state: AlkkagiMatch?
        get() = stateCell.value
        internal set(value) {
            stateCell.value = value
            val count = (value?.watchers ?: 0).clampedInt()
            if (spectatorCount != count) spectatorCount = count
        }
    var chat: List<AlkkagiChatMessage> by mutableStateOf(emptyList())
        private set
    var notice: String? by mutableStateOf(null)
        internal set
    var isBusy: Boolean by mutableStateOf(false)
        internal set
    var isLoading: Boolean by mutableStateOf(false)
        private set
    var isSendingChat: Boolean by mutableStateOf(false)
        private set
    var isWindowVisible: Boolean by mutableStateOf(false)
        internal set
    var isWindowOccluded: Boolean by mutableStateOf(false)
        internal set
    var availability: AlkkagiAvailability by mutableStateOf(AlkkagiAvailability.available)
        internal set
    var record: AlkkagiRecord? by mutableStateOf(null)
        internal set
    var rubyBalance: Long? by mutableStateOf(null)
        internal set
    var liveMatches: List<AlkkagiLiveMatch> by mutableStateOf(emptyList())
        internal set
    var hasLoadedLobby: Boolean by mutableStateOf(false)
        internal set
    var lobbyLoadFailed: Boolean by mutableStateOf(false)
        internal set
    var ranking: AlkkagiRankingBoard? by mutableStateOf(null)
        internal set
    var rankingUnavailable: Boolean by mutableStateOf(false)
        internal set
    var watched: AlkkagiWatchState? by mutableStateOf(null)
        internal set
    var spectatorCount: Int by mutableIntStateOf(0)
        internal set

    var rankingEnabled: Boolean = false
    var spectatorFeaturesEnabled: Boolean = false
    var selectedStake: AlkkagiStake by mutableStateOf(AlkkagiStake.three)

    private val hiddenCell = mutableStateOf<Set<String>>(emptySet())
    var hiddenPeerIDs: Set<String>
        get() = hiddenCell.value
        set(value) {
            val old = hiddenCell.value
            if (value == old) return
            hiddenCell.value = value
            users = users.filter { !isPeerHidden(it.id) }
            incoming = incoming.filter { !isPeerHidden(it.opponent.id) }
            outgoing?.let { if (isPeerHidden(it.opponent.id)) outgoing = null }
            scheduleInviteExpiry()
            if (isAvailable) requestSync()
        }

    var presentWindow: (() -> Unit)? = null
    var dismissWindow: (() -> Unit)? = null
    var onInviteArrived: ((AlkkagiInvite) -> Unit)? = null
    var onAttention: ((AlkkagiAttention) -> Unit)? = null
    var onMatchFinished: (() -> Unit)? = null
    var requestAttention: (() -> Unit)? = null

    /** 판 밖 걸음 간격 상한(초). 시험은 크게 재우고 [pollTick] 을 직접 밟는다. */
    var outsidePollStepSeconds: Double = 1.0
    var lastLobbyRequestAt: SwiftDate = DISTANT_PAST
    var lastOutgoingRequestAt: SwiftDate = DISTANT_PAST
    var lastMenuLobbyAt: SwiftDate = DISTANT_PAST
    var lastRankingRequestAt: SwiftDate = DISTANT_PAST

    private var rubyServerNowMs: Double? = null
    internal var rankingInFlight = false
    internal var watchMatchID: String? = null
    internal var watchGeneration = 0
    internal var watchJob: Job? = null
    var resetGeneration: Int = 0
        private set
    private var syncJob: Job? = null
    private var pollJob: Job? = null
    private var pollToken = 0
    private var deadlineJob: Job? = null
    private var inviteExpiryJob: Job? = null
    private var pendingLobby = false
    private var pendingUsers = false
    private var pendingMatch = false
    private var pendingOutgoingID: String? = null
    private var focusMatchID: String? = null
    private var matchGeneration = 0
    private var muteGeneration = 0
    private var requestSequence = 0
    private var lobbySequence = 0
    private var clockSequence = 0
    private var seenInviteIDs: Set<String> = emptySet()
    private var seenFinishedMatchIDs: Set<String> = emptySet()
    private var dismissedMatchIDs: Set<String> = emptySet()
    private var refreshedDeadline: String? = null
    private var announcedMatchIDs: Set<String> = emptySet()
    private var eventNotice: String? = null
    private var outgoingRevision = 0
    private var serverClockOffsetMs: Double? = null
    /** 서버와 맞물렸다(첫 성공 응답 뒤 참). 판 진행 문 — 화면 상태는 [availability]. */
    private var isAvailable = false
    private var serverMissing = false

    private fun log(message: String) {
        logger?.log(LogLevel.INFO, TAG, message)
    }

    // MARK: 계산 칸

    val match: AlkkagiMatch? get() = state

    /** G §8-17 #1(Android): 이 빌드가 판돈 대결의 **신청 · 수락**을 내는가. 호스트가 없으면(시험 스텁) 참 — 스텁 시험이 막히지 않게. */
    val duelsEnabled: Boolean get() = host?.appConfig?.duelsEnabled ?: (service != null)

    val visibleUsers: List<AlkkagiLobbyUser>
        get() = sortedForLobby(if (hiddenPeerIDs.isEmpty()) users else users.filter { !isPeerHidden(it.id) }, collation)

    /** 차단 거울을 거르고 **지금 내 판과 같은 id 를 뺀** 받은 신청. 시계를 읽지 않는다. */
    val visibleIncomingInvites: List<AlkkagiInvite>
        get() {
            val matchID = state?.id?.lowercase()
            return incoming.filter { !isPeerHidden(it.opponent.id) && (matchID == null || it.id.lowercase() != matchID) }
        }

    val visibleIncoming: AlkkagiInvite? get() = visibleIncomingInvites.firstOrNull()

    /** 확성기 배너를 미룬다(진행 판 — 배치 · 조준 · 굴림). */
    val defersMegaphoneBanner: Boolean
        get() = when (state?.phase) {
            AlkkagiMatchPhase.placing, AlkkagiMatchPhase.aiming, AlkkagiMatchPhase.rolling -> true
            else -> false
        }

    /** 끝난 내 판의 결과(내 기준). */
    val outcome: AlkkagiOutcome?
        get() {
            val s = state ?: return null
            if (s.phase != AlkkagiMatchPhase.finished) return null
            return when (s.result) {
                AlkkagiMatchResult.draw -> AlkkagiOutcome.draw
                AlkkagiMatchResult.black -> if (s.myColor == AlkkagiPlayerWire.black) AlkkagiOutcome.win else AlkkagiOutcome.loss
                AlkkagiMatchResult.white -> if (s.myColor == AlkkagiPlayerWire.white) AlkkagiOutcome.win else AlkkagiOutcome.loss
                else -> null
            }
        }

    val endReason: AlkkagiEndReason?
        get() {
            val s = state ?: return null
            if (s.phase != AlkkagiMatchPhase.finished) return null
            return s.finishReason?.let(AlkkagiEndReason::of)
        }

    /** 내 루비 증감: 승 winnerNet · 패 −판돈 · 무 0 · 옛 판(판돈 null) null. */
    val rubyDelta: Int?
        get() {
            val stake = state?.stake?.clampedInt() ?: return null
            return when (outcome ?: return null) {
                AlkkagiOutcome.win -> DuelFee.winnerNet(stake)
                AlkkagiOutcome.loss -> -stake
                AlkkagiOutcome.draw -> 0
            }
        }

    /** 놓친 차례 경고 값(내가 1번 이상 놓쳤고 판이 진행 중일 때). */
    val missedTurnWarning: Pair<Int, Int>?
        get() {
            val s = state ?: return null
            if (s.phase == AlkkagiMatchPhase.finished) return null
            val mine = s.myMissedTurns?.clampedInt() ?: return null
            if (mine < 1) return null
            return mine to (s.forfeitAfter?.clampedInt() ?: 3)
        }

    /** 말풍선 문(규칙 ①) — 창이 안 보이거나 가려졌다. */
    val attentionDoorIsOpen: Boolean get() = !(isWindowVisible && !isWindowOccluded)

    val estimatedServerNowMs: Double
        get() {
            val now = clock().timeIntervalSince1970 * 1000 + (serverClockOffsetMs ?: 0.0)
            return if (now.isFinite()) now else 0.0
        }

    val remainingSeconds: Double
        get() {
            val s = state ?: return 0.0
            val deadline = s.deadlineMs ?: return 0.0
            if (s.phase == AlkkagiMatchPhase.finished || !deadline.isFinite()) return 0.0
            if (s.phase == AlkkagiMatchPhase.rolling) {
                val shot = s.shot ?: return 0.0
                if (!shot.startedAtMs.isFinite()) return 0.0
                return maxOf(0.0, (deadline - shot.startedAtMs) / 1000)
            }
            return maxOf(0.0, (deadline - estimatedServerNowMs) / 1000)
        }

    val isMyTurn: Boolean
        get() {
            val s = state ?: return false
            return when (s.phase) {
                AlkkagiMatchPhase.placing -> !s.myReady
                AlkkagiMatchPhase.aiming -> s.currentPlayer == s.myColor
                else -> false
            }
        }

    val canPlace: Boolean get() = canAct && isMyTurn && state?.phase == AlkkagiMatchPhase.placing
    val canShoot: Boolean get() = canAct && isMyTurn && state?.phase == AlkkagiMatchPhase.aiming

    private val canAct: Boolean
        get() {
            if (service == null || !isAvailable || serverMissing || isBusy || serverClockOffsetMs == null) return false
            val deadline = state?.deadlineMs ?: return false
            return deadline > estimatedServerNowMs
        }

    private val hasLiveMatch: Boolean get() = state?.let { it.phase != AlkkagiMatchPhase.finished } ?: false

    private fun isPeerHidden(id: String): Boolean = hiddenPeerIDs.any { it.equals(id, ignoreCase = true) }

    // MARK: - 동작

    /** 판돈을 걸고 신청한다. 보낸 신청이 있어도 막지 않는다(서버 `already_pending`). 근무 조건은 없다. */
    suspend fun challenge(opponentID: String, stake: AlkkagiStake) {
        if (selectedStake != stake) selectedStake = stake
        if (!duelsEnabled) return
        val opponent = uuidKey(opponentID) ?: return
        if (isBusy || !isAvailable || availability != AlkkagiAvailability.available || state != null || isPeerHidden(opponentID)) return
        if (opponent == uuidKey(me?.id)) return
        if (users.firstOrNull { uuidKey(it.id) == opponent }?.canBeChallenged == false) return
        val generation = resetGeneration
        val response = act(AlkkagiCall.Challenge(opponent, stake.rawValue.toLong(), randomUUIDString()))
        if (generation != resetGeneration) return
        when (response?.status ?: return) {
            AlkkagiRPCStatus.ok -> lastOutgoingRequestAt = clock()
            AlkkagiRPCStatus.alreadyPending, AlkkagiRPCStatus.busy, AlkkagiRPCStatus.targetBusy, AlkkagiRPCStatus.targetOutdated,
            AlkkagiRPCStatus.targetFocused,
            -> refreshLobby()
            else -> Unit
        }
    }

    /** 끝난 판을 떠나 로비로(결과 카드 [로비로]). */
    fun backToLobby() {
        val generation = resetGeneration
        scope.launch {
            if (generation != resetGeneration) return@launch
            if (state?.phase == AlkkagiMatchPhase.finished) leaveFinishedMatch() else if (state == null) refreshLobby()
            if (generation != resetGeneration) return@launch
            refreshRanking()
        }
    }

    /** 서버 잔액을 스토어 · 앱 미러로 옮긴다. 이미 옮긴 잔액보다 먼저 서버가 만든 응답의 잔액은 버린다. */
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

    /** 받은 신청에 응답한다. 떠나지 않은 끝난 판은 응답을 막지 않는다 — 수락이면 그 끝난 판을 먼저 떠난다. */
    suspend fun respond(inviteID: String, accept: Boolean) {
        if (accept && !duelsEnabled) return
        val id = uuidKey(inviteID) ?: return
        if (isBusy || !isAvailable || availability != AlkkagiAvailability.available) return
        if (!(state?.let { it.phase == AlkkagiMatchPhase.finished } ?: true)) return
        if (incoming.none { uuidKey(it.id) == id }) return
        val generation = resetGeneration
        if (accept && state?.phase == AlkkagiMatchPhase.finished) {
            leaveFinishedMatch()
            if (generation != resetGeneration || isBusy) return
        }
        val invite = incoming.firstOrNull { uuidKey(it.id) == id } ?: return
        if (invite.expiresAtMs <= estimatedServerNowMs) {
            refreshLobby()
            return
        }
        val response = act(AlkkagiCall.Respond(id, accept, randomUUIDString()))
        if (generation != resetGeneration) return
        when (response?.status ?: return) {
            AlkkagiRPCStatus.ok, AlkkagiRPCStatus.notFound, AlkkagiRPCStatus.notPending, AlkkagiRPCStatus.expired, AlkkagiRPCStatus.invalid,
            AlkkagiRPCStatus.forbidden,
            -> if (incoming.any { uuidKey(it.id) == id }) {
                incoming = incoming.filter { uuidKey(it.id) != id }
                scheduleInviteExpiry()
            }
            else -> Unit
        }
    }

    /** 보낸 신청 취소. not_pending · expired · stale 은 수락과 엇갈렸다는 뜻일 수 있다 — 전체 로비를 다시 읽는다. */
    suspend fun cancelChallenge() {
        val sent = outgoing ?: return
        val id = uuidKey(sent.id) ?: return
        if (isBusy) return
        val generation = resetGeneration
        val response = act(AlkkagiCall.Cancel(id, randomUUIDString()))
        if (generation != resetGeneration) return
        val status = response?.status ?: return
        when (status) {
            AlkkagiRPCStatus.ok, AlkkagiRPCStatus.notFound, AlkkagiRPCStatus.notPending, AlkkagiRPCStatus.expired ->
                if (uuidKey(outgoing?.id) == id) {
                    outgoing = null
                    scheduleInviteExpiry()
                }
            else -> Unit
        }
        when (status) {
            AlkkagiRPCStatus.notPending, AlkkagiRPCStatus.expired, AlkkagiRPCStatus.stale -> refreshLobby()
            else -> Unit
        }
    }

    suspend fun place(stoneID: Int, position: AlkkagiVector) {
        val s = state ?: return
        val id = uuidKey(s.id) ?: return
        if (!canPlace || s.canonicalGame()?.canPlace(stoneID, position) != true) return
        act(AlkkagiCall.Place(id, s.placementRevision, stoneID.toLong(), position.x, position.y, randomUUIDString()))
    }

    suspend fun confirmPlacement() {
        val s = state ?: return
        val id = uuidKey(s.id) ?: return
        if (!canPlace) return
        val own = s.stones.filter { it.owner == s.myColor }
        if (own.size != 5 || !own.all { it.isPlaced && !it.isOut }) return
        act(AlkkagiCall.Ready(id, s.placementRevision, randomUUIDString()))
    }

    suspend fun shoot(stoneID: Int, pull: AlkkagiVector, actionID: String? = null) {
        val s = state ?: return
        val id = uuidKey(s.id) ?: return
        if (!canShoot) return
        val game = s.canonicalGame() ?: return
        if (!game.shoot(stoneID, pull)) return
        act(AlkkagiCall.Shoot(id, s.revision, stoneID.toLong(), pull.x, pull.y, actionID ?: randomUUIDString()))
    }

    suspend fun resign() {
        val s = state ?: return
        if (isBusy || s.phase == AlkkagiMatchPhase.finished) return
        val id = uuidKey(s.id) ?: return
        act(AlkkagiCall.Resign(id, s.revision, randomUUIDString()))
    }

    suspend fun sendChat(body: String) {
        val text = body.trim()
        val s = state ?: return
        if (isSendingChat || !isAvailable || s.muted) return
        val id = uuidKey(s.id) ?: return
        if (text.isEmpty() || text.codePointCount() > 100) {
            notice = AlkkagiNoticeText.chatTooLong
            return
        }
        val generation = resetGeneration
        isSendingChat = true
        try {
            perform(AlkkagiCall.ChatSend(id, text, randomUUIDString()))
        } finally {
            if (generation == resetGeneration) isSendingChat = false
        }
    }

    suspend fun setMuted(muted: Boolean) {
        val s = state ?: return
        if (isBusy || s.muted == muted) return
        val id = uuidKey(s.id) ?: return
        muteGeneration += 1
        val generation = resetGeneration
        val response = act(AlkkagiCall.ChatMute(id, muted, randomUUIDString()))
        if (generation == resetGeneration && response?.status == AlkkagiRPCStatus.ok && uuidKey(state?.id) == id) {
            state = state?.copy(muted = muted)
        }
    }

    suspend fun leaveFinishedMatch() {
        val s = state ?: return
        if (isBusy || s.phase != AlkkagiMatchPhase.finished) return
        val id = uuidKey(s.id) ?: return
        val generation = resetGeneration
        val response = act(AlkkagiCall.Leave(id, s.revision, randomUUIDString()))
        if (generation != resetGeneration || response?.status != AlkkagiRPCStatus.ok || uuidKey(state?.id) != id) return
        dismissedMatchIDs = dismissedMatchIDs + id
        clearMatch()
        refreshLobby()
    }

    suspend fun refreshLobby() = synchronize(lobby = true, match = false, users = true)
    suspend fun refreshLightLobby() = synchronize(lobby = true, match = false, users = false)
    suspend fun refreshMatch() = synchronize(lobby = false, match = true)

    /** 바깥 경로 → 가벼운 로비. 스로틀 30초. */
    fun refreshLobbyIfStale() {
        if (service == null) return
        val now = clock()
        if (now.timeIntervalSince(lastMenuLobbyAt) < menuLobbyThrottleSeconds) return
        lastMenuLobbyAt = now
        pendingLobby = true
        startSyncIfNeeded()
    }

    fun handleSignal() = requestSync()
    fun realtimeDidJoin() = requestSync()
    fun systemDidWake() = requestSync()

    fun openWindow(focusMatchID: String? = null) {
        this.focusMatchID = uuidKey(focusMatchID)
        requestSync()
        presentWindow?.invoke()
    }

    /** 창이 보이기 시작했다. 열린 채 가려진 창을 다시 부른 길이면 가림 기록을 그대로 둔다(규칙 ②). */
    fun windowDidShow() {
        val reshownWhileOccluded = isWindowVisible && isWindowOccluded
        if (!isWindowVisible) isWindowVisible = true
        if (!reshownWhileOccluded && isWindowOccluded) isWindowOccluded = false
        if (isWindowOccluded) return
        startPolling()
        scheduleDeadlineRefresh()
        requestSync()
        if (rankingEnabled && !hasLiveMatch && clock().timeIntervalSince(lastRankingRequestAt) >= 1) scope.launch { refreshRanking() }
    }

    fun windowDidHide() {
        isWindowVisible = false
        isWindowOccluded = false
        stopPolling()
        scheduleDeadlineRefresh()
    }

    fun windowDidClose() {
        windowDidHide()
        stopWatching()
        if (state?.phase == AlkkagiMatchPhase.finished) {
            val generation = resetGeneration
            scope.launch { if (generation == resetGeneration) leaveFinishedMatch() }
        }
    }

    fun windowOcclusionDidChange(visible: Boolean) {
        isWindowOccluded = !visible
        if (visible && isWindowVisible) {
            startPolling()
            scheduleDeadlineRefresh()
            requestSync()
        } else {
            stopPolling()
            scheduleDeadlineRefresh()
        }
    }

    /** 계정 상태를 비운다(주입한 서비스 · 호스트는 남긴다). */
    fun reset() {
        resetGeneration += 1
        matchGeneration += 1
        muteGeneration += 1
        syncJob?.cancel()
        syncJob = null
        stopPolling()
        inviteExpiryJob?.cancel()
        inviteExpiryJob = null
        lastLobbyRequestAt = DISTANT_PAST
        lastOutgoingRequestAt = DISTANT_PAST
        lastMenuLobbyAt = DISTANT_PAST
        lastRankingRequestAt = DISTANT_PAST
        pendingLobby = false
        pendingUsers = false
        pendingMatch = false
        pendingOutgoingID = null
        eventNotice = null
        outgoingRevision = 0
        focusMatchID = null
        users = emptyList()
        incoming = emptyList()
        outgoing = null
        me = null
        state = null
        chat = emptyList()
        notice = null
        isBusy = false
        isLoading = false
        isSendingChat = false
        serverMissing = false
        isAvailable = false
        availability = AlkkagiAvailability.available
        record = null
        rubyBalance = null
        rubyServerNowMs = null
        liveMatches = emptyList()
        hasLoadedLobby = false
        lobbyLoadFailed = false
        ranking = null
        rankingUnavailable = false
        rankingInFlight = false
        stopWatching()
        selectedStake = AlkkagiStake.three
        announcedMatchIDs = emptySet()
        hiddenCell.value = emptySet()
        isWindowVisible = false
        isWindowOccluded = false
        serverClockOffsetMs = null
        seenInviteIDs = emptySet()
        seenFinishedMatchIDs = emptySet()
        dismissedMatchIDs = emptySet()
        refreshedDeadline = null
        requestSequence = 0
        lobbySequence = 0
        clockSequence = 0
        dismissWindow?.invoke()
    }

    // MARK: - 요청

    private class RequestContext(val generation: Int, val matchGeneration: Int, val muteGeneration: Int, val sequence: Int, val sentAtMs: Double, val outgoingRevision: Int)

    private suspend fun act(call: AlkkagiCall): AlkkagiResponse? {
        if (isBusy || service == null) return null
        val generation = resetGeneration
        isBusy = true
        notice = null
        try {
            return perform(call)
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    private suspend fun perform(call: AlkkagiCall): AlkkagiResponse? {
        val service = service ?: return null
        requestSequence += 1
        val context = RequestContext(resetGeneration, matchGeneration, muteGeneration, requestSequence, clock().timeIntervalSince1970 * 1000, outgoingRevision)
        val response = try {
            service.call(call)
        } catch (e: CancellationException) {
            if (!coroutineContext.isActive) throw e
            return null
        } catch (e: Exception) {
            if (context.generation != resetGeneration) return null
            when (e) {
                AlkkagiServiceError.ServerMissing -> {
                    serverMissing = true
                    isAvailable = false
                    availability = AlkkagiAvailability.serverMissing
                    notice = AlkkagiNoticeText.unavailable
                }
                AlkkagiServiceError.NotSignedIn -> {
                    reset()
                    return null
                }
                AlkkagiServiceError.Unavailable -> {
                    isAvailable = false
                    notice = AlkkagiNoticeText.signInAgain
                }
                else -> notice = AlkkagiNoticeText.checkConnection
            }
            noteLobbyFailed(call)
            return null
        }
        if (context.generation != resetGeneration) return null
        // 응답 protocol 이 요청보다 낮으면 서버가 옛판이다 — '곧 열려요'.
        if (response.protocolVersion < AlkkagiWire.protocolVersion || !response.serverNowMs.isFinite()) {
            isAvailable = false
            availability = AlkkagiAvailability.serverMissing
            notice = AlkkagiNoticeText.unavailable
            noteLobbyFailed(call)
            return null
        }
        if (context.sequence >= clockSequence) {
            val receivedAtMs = clock().timeIntervalSince1970 * 1000
            val midpoint = context.sentAtMs / 2 + receivedAtMs / 2
            val offset = response.serverNowMs - midpoint
            if (midpoint.isFinite() && offset.isFinite()) {
                serverClockOffsetMs = offset
                clockSequence = context.sequence
            }
        }
        if (response.status == AlkkagiRPCStatus.notSignedIn) {
            reset()
            return null
        }
        if (response.status == AlkkagiRPCStatus.unsupportedClient || response.status == AlkkagiRPCStatus.unknown) {
            // 문이 닫혔으면(door_open false) 내 앱 탓이 아니다 — '곧 열려요'. 그 밖은 업데이트.
            isAvailable = false
            availability = if (response.doorOpen == false) AlkkagiAvailability.serverMissing else AlkkagiAvailability.updateRequired
            notice = if (availability == AlkkagiAvailability.serverMissing) AlkkagiNoticeText.unavailable else AlkkagiNoticeText.updateMine
            noteLobbyFailed(call)
            return null
        }
        val st = response.state
        if (st != null && st.canonicalGame() == null) {
            isAvailable = false
            notice = AlkkagiNoticeText.tryAgain
            return null
        }
        serverMissing = false
        isAvailable = true
        if (call is AlkkagiCall.Lobby && response.status == AlkkagiRPCStatus.ok) {
            availability = if (response.doorOpen == false) AlkkagiAvailability.serverMissing else AlkkagiAvailability.available
        }
        applyRuby(response.rubyBalance ?: response.state?.rubyBalance, response.serverNowMs)
        eventNotice = null
        apply(response, call, context)
        if (context.generation != resetGeneration) return null
        val event = eventNotice
        if (event != null) {
            notice = event
            eventNotice = null
        } else {
            noticeUpdate(call, response)?.let { notice = it.text }
        }
        return response
    }

    private fun apply(response: AlkkagiResponse, call: AlkkagiCall, context: RequestContext) {
        // 판 · 신청이 서버에서 사라졌다 — 내 판이면 내리고 로비로.
        if (response.status == AlkkagiRPCStatus.notFound) uuidKey(call.parameters.pMatchID)?.let { dropMatchOrInvite(it) }
        val doorOpen = attentionDoorIsOpen
        if (context.sequence >= lobbySequence) {
            response.me?.let { me = it }
            // 가벼운 로비(users [] · record null · matches [])는 사람 · 전적 · 대결 중을 **덮지 않는다**.
            if (call is AlkkagiCall.Lobby && call.users && response.status == AlkkagiRPCStatus.ok) {
                response.users?.let { rows -> users = rows.map(AlkkagiLobbyUser::of).filter { !isPeerHidden(it.id) } }
                response.record?.let {
                    val fresh = AlkkagiRecord(it.wins.clampedInt(), it.losses.clampedInt(), it.draws.clampedInt())
                    if (record != fresh) record = fresh
                }
                response.matches?.let { rows ->
                    val fresh = rows.map {
                        AlkkagiLiveMatch(
                            it.id, it.black, it.white, it.stake?.clampedInt(), it.shotCount.clampedInt(), it.watchers.clampedInt(),
                            it.acceptedAtMs?.takeIf { ms -> ms.isFinite() && ms > 0 }?.let { ms -> SwiftDate(ms / 1000) },
                        )
                    }
                    if (liveMatches != fresh) liveMatches = fresh
                }
                if (!hasLoadedLobby) hasLoadedLobby = true
                if (lobbyLoadFailed) lobbyLoadFailed = false
            }
            response.incoming?.let { rows ->
                val fresh = rows.filter { !isPeerHidden(it.opponent.id) }
                if (call is AlkkagiCall.Lobby) {
                    incoming = fresh
                } else {
                    // 한 판의 응답은 그 신청 하나만 싣는다 — 다른 받은 신청 카드를 지우지 않게 고쳐 넣기만.
                    val merged = incoming.toMutableList()
                    for (invite in fresh) {
                        val index = merged.indexOfFirst { it.id.equals(invite.id, ignoreCase = true) }
                        if (index >= 0) merged[index] = invite else merged.add(0, invite)
                    }
                    if (incoming != merged) incoming = merged
                }
                for (invite in fresh) {
                    val key = invite.id.lowercase()
                    if (key in seenInviteIDs) continue
                    seenInviteIDs = seenInviteIDs + key
                    if (doorOpen && invite.expiresAtMs > estimatedServerNowMs) onInviteArrived?.invoke(invite)
                    if (context.generation != resetGeneration) return
                }
            }
            val predates = context.outgoingRevision < outgoingRevision
            val sent = outgoing
            if (call is AlkkagiCall.Lobby) {
                if (response.status == AlkkagiRPCStatus.ok) noteOutgoing(response.outgoing, response, predates)
            } else if (call is AlkkagiCall.State && response.status == AlkkagiRPCStatus.ok && sent != null && uuidKey(sent.id) == uuidKey(call.matchID)) {
                // 보낸 신청 확인 걸음(5초) — 대기면 outgoing 이 실려 오고, 끝났으면 빠진다.
                noteOutgoing(response.outgoing, response, predates)
            } else if (response.incoming != null || response.outgoing != null) {
                if (call is AlkkagiCall.Challenge && response.outgoing != null) outgoingRevision += 1
                outgoing = response.outgoing
            }
            lobbySequence = context.sequence
            outgoing?.let { if (isPeerHidden(it.opponent.id)) outgoing = null }
            scheduleInviteExpiry()
        }
        var next = response.state ?: return
        val id = uuidKey(next.id) ?: return
        if (id in dismissedMatchIDs || next.canonicalGame() == null) return
        uuidKey(call.parameters.pMatchID)?.let { if (it != id) return }
        me?.let { m ->
            val ownID = if (next.myColor == AlkkagiPlayerWire.black) next.black.id else next.white.id
            val own = uuidKey(ownID) ?: return
            val meID = uuidKey(m.id) ?: return
            if (own != meID) return
        }
        val sameMatch = uuidKey(state?.id) == id
        if (!sameMatch && context.matchGeneration != matchGeneration) return
        val old = if (sameMatch) state else null
        val messages = LinkedHashMap<Long, AlkkagiChatMessage>()
        if (sameMatch) for (m in chat) if (m.seq !in messages) messages[m.seq] = m
        for (message in next.chat) {
            if (message.seq > 0 && message.seq <= next.chatSeq && message.sentAtMs.isFinite() && message.body.codePointCount() <= 100) {
                if (message.seq !in messages) messages[message.seq] = message
            }
        }
        chat = messages.values.sortedBy { it.seq }
        if (old != null && old.revision > next.revision) next = old
        next = next.copy(chatSeq = maxOf(next.chatSeq, response.state?.chatSeq ?: 0, old?.chatSeq ?: 0), chat = chat)
        if (context.muteGeneration != muteGeneration && old != null) next = next.copy(muted = old.muted)
        if (!sameMatch) matchGeneration += 1
        val wasMyAim = old?.let(::isMyAim) ?: false
        state = next
        focusMatchID = null
        if (next.phase == AlkkagiMatchPhase.finished && id !in seenFinishedMatchIDs) {
            seenFinishedMatchIDs = seenFinishedMatchIDs + id
            onMatchFinished?.invoke()
            if (context.generation != resetGeneration) return
            // 내 판이 끝나는 것을 지켜봤다 — 전적은 로비에만 있으니 한 번 다시 읽고 순위도.
            if (old != null && old.phase != AlkkagiMatchPhase.finished) noteOwnMatchFinished()
        }
        if (next.phase != AlkkagiMatchPhase.finished && id !in announcedMatchIDs) {
            announcedMatchIDs = announcedMatchIDs + id
            // 판이 처음 섰다 — 서버는 두 사람의 다른 알까기 대기 신청을 전부 닫았다. 로컬 카드 · 보낸 신청도 걷고 관전은 내린다.
            if (incoming.isNotEmpty()) incoming = emptyList()
            if (outgoing != null) outgoing = null
            scheduleInviteExpiry()
            stopWatching()
            presentWindow?.invoke()
            if (context.generation != resetGeneration) return
            requestAttention?.invoke()
            if (context.generation != resetGeneration) return
            if (doorOpen) {
                val opponent = if (next.myColor == AlkkagiPlayerWire.black) next.white else next.black
                onAttention?.invoke(AlkkagiAttention(AlkkagiAttention.Kind.matchStarted, next.id, opponent.displayName))
                if (context.generation != resetGeneration) return
            }
        } else if (sameMatch && isMyAim(next) && !wasMyAim && doorOpen) {
            // 내 차례 — '조준 · 내 차례'로 **들어설 때** 한 번. 이름은 상대가 쏴서 넘어왔을 때만.
            val opponent = if (next.myColor == AlkkagiPlayerWire.black) next.white else next.black
            val shooter = next.shot?.let { shot -> shot.initialStones.firstOrNull { it.id == shot.stoneID }?.owner }
            val myOpponentColor = if (next.myColor == AlkkagiPlayerWire.black) AlkkagiPlayerWire.white else AlkkagiPlayerWire.black
            val byOpponentShot = shooter == myOpponentColor && (next.shotCount > (old?.shotCount ?: next.shotCount) || old?.phase == AlkkagiMatchPhase.rolling)
            onAttention?.invoke(AlkkagiAttention(AlkkagiAttention.Kind.myTurn, next.id, if (byOpponentShot) opponent.displayName else ""))
            if (context.generation != resetGeneration) return
        }
        scheduleDeadlineRefresh()
    }

    /** 로비 · 보낸 신청 확인 응답의 `outgoing` 을 옮긴다. 들고 있던 보낸 신청이 빠졌고 판으로 이어지지 않았으면 안내 한 줄. */
    private fun noteOutgoing(fresh: AlkkagiInvite?, response: AlkkagiResponse, predates: Boolean) {
        if (predates && fresh == null) return
        val gone = outgoing
        if (gone != null && (fresh == null || !fresh.id.equals(gone.id, ignoreCase = true))) {
            val becameMatch = listOf(response.state?.id, state?.id).any { it?.equals(gone.id, ignoreCase = true) == true }
            if (!becameMatch) eventNotice = if (gone.expiresAtMs > estimatedServerNowMs) AlkkagiNoticeText.inviteDeclined else AlkkagiNoticeText.inviteTimedOut
        }
        if (outgoing != fresh) outgoing = fresh
    }

    private fun dropMatchOrInvite(id: String) {
        if (uuidKey(state?.id) == id) {
            clearMatch()
            eventNotice = AlkkagiNoticeText.finishedMatch
            pendingLobby = true
            pendingUsers = true
            startSyncIfNeeded()
        }
        if (uuidKey(outgoing?.id) == id) outgoing = null
        if (incoming.any { uuidKey(it.id) == id }) incoming = incoming.filter { uuidKey(it.id) != id }
    }

    private fun clearMatch() {
        matchGeneration += 1
        state = null
        chat = emptyList()
        focusMatchID = null
        deadlineJob?.cancel()
        deadlineJob = null
    }

    private fun noteOwnMatchFinished() {
        pendingLobby = true
        pendingUsers = pendingUsers || !attentionDoorIsOpen
        startSyncIfNeeded()
        lastRankingRequestAt = DISTANT_PAST
        if (rankingEnabled) scope.launch { refreshRanking() }
    }

    private class NoticeSet(val text: String?)

    /** 응답 → 안내 줄(null = 그대로 둔다). 배경 조회의 ok 는 안내를 지우지 않는다. */
    private fun noticeUpdate(call: AlkkagiCall, response: AlkkagiResponse): NoticeSet? {
        val status = response.status
        return when (call) {
            is AlkkagiCall.Challenge -> NoticeSet(AlkkagiNoticeText.challenge(status, response.need, response.have, response.doorOpen))
            is AlkkagiCall.Cancel -> NoticeSet(AlkkagiNoticeText.cancel(status))
            is AlkkagiCall.Respond -> NoticeSet(AlkkagiNoticeText.respond(call.accept, status, response.side, response.need, response.have, response.doorOpen))
            is AlkkagiCall.Resign -> NoticeSet(AlkkagiNoticeText.resign(status))
            is AlkkagiCall.State -> {
                if (uuidKey(state?.id) != uuidKey(call.matchID) && status == AlkkagiRPCStatus.ok) return null
                if (status == AlkkagiRPCStatus.notFound && state == null && outgoing == null) return null
                NoticeSet(AlkkagiNoticeText.move(status))
            }
            is AlkkagiCall.Place, is AlkkagiCall.Ready, is AlkkagiCall.Shoot, is AlkkagiCall.Leave, is AlkkagiCall.ChatSend, is AlkkagiCall.ChatMute ->
                NoticeSet(AlkkagiNoticeText.move(status))
            is AlkkagiCall.Lobby, AlkkagiCall.Ranking, is AlkkagiCall.Watch, is AlkkagiCall.WatchLive ->
                if (status == AlkkagiRPCStatus.ok) null else NoticeSet(AlkkagiNoticeText.common(status))
        }
    }

    private fun noteLobbyFailed(call: AlkkagiCall) {
        if (call is AlkkagiCall.Lobby && call.users && !lobbyLoadFailed) lobbyLoadFailed = true
    }

    // MARK: - 폴링(창이 보이고 안 가려졌을 때만 — 규칙 ④)

    private suspend fun outsidePolling(body: suspend (AlkkagiOnlineStore) -> Unit) {
        scope.launch { body(this@AlkkagiOnlineStore) }.join()
    }

    /** 안전망 한 걸음. 판 중엔 판 상태만, 판 밖엔 보낸 신청 5초 · 전체 로비 30초 · 순위 60초. 걸음 사이마다 창 · 취소를 다시 본다. */
    suspend fun pollTick(now: SwiftDate) {
        if (service == null || !isWindowVisible || isWindowOccluded || !coroutineContext.isActive) return
        if (hasLiveMatch) {
            outsidePolling { it.synchronize(lobby = false, match = true) }
            return
        }
        val sent = outgoing
        val sentID = uuidKey(sent?.id)
        if (sentID != null && now.timeIntervalSince(lastOutgoingRequestAt) >= outgoingPollSeconds) {
            lastOutgoingRequestAt = now
            outsidePolling { it.synchronize(lobby = false, match = false, outgoing = sentID) }
        }
        if (!isWindowVisible || isWindowOccluded || !coroutineContext.isActive) return
        if (now.timeIntervalSince(lastLobbyRequestAt) >= lobbyPollSeconds) {
            lastLobbyRequestAt = now
            outsidePolling { it.refreshLobby() }
        }
        if (!isWindowVisible || isWindowOccluded || !coroutineContext.isActive) return
        if (rankingEnabled && now.timeIntervalSince(lastRankingRequestAt) >= rankingPollSeconds) outsidePolling { it.refreshRanking() }
    }

    private fun requestSync() {
        if (service == null) return
        pendingLobby = true
        pendingUsers = pendingUsers || (isWindowVisible && !isWindowOccluded)
        pendingMatch = true
        startSyncIfNeeded()
    }

    /** 조회를 직렬 엔진에 싣고 끝날 때까지 기다린다. 엔진은 부른 쪽의 작업이 아니다(규칙 ⑤) — 도는 중 온 부름은 한 바퀴 더(규칙 ③). */
    private suspend fun synchronize(lobby: Boolean, match: Boolean, users: Boolean = false, outgoing: String? = null) {
        if (service == null) return
        pendingLobby = pendingLobby || lobby
        pendingUsers = pendingUsers || users
        pendingMatch = pendingMatch || match
        if (outgoing != null) pendingOutgoingID = outgoing
        startSyncIfNeeded()
        syncJob?.join()
    }

    private fun startSyncIfNeeded() {
        if (syncJob != null) return
        val generation = resetGeneration
        syncJob = scope.launch {
            if (generation != resetGeneration) return@launch
            isLoading = true
            try {
                while (generation == resetGeneration && isActive) {
                    val lobby = pendingLobby
                    val users = pendingUsers
                    val match = pendingMatch
                    val outgoingID = pendingOutgoingID
                    pendingLobby = false
                    pendingUsers = false
                    pendingMatch = false
                    pendingOutgoingID = null
                    if (!lobby && !match && outgoingID == null) return@launch
                    if (lobby) {
                        if (users) lastLobbyRequestAt = clock()
                        perform(AlkkagiCall.Lobby(users))
                    }
                    if (generation != resetGeneration || !isActive) return@launch
                    if (outgoingID != null && uuidKey(outgoing?.id) == outgoingID) {
                        lastOutgoingRequestAt = clock()
                        perform(AlkkagiCall.State(outgoingID, 0))
                    }
                    if (generation != resetGeneration || !isActive) return@launch
                    val focus = focusMatchID
                    val isInvite = focus?.let { f -> incoming.any { uuidKey(it.id) == f } || uuidKey(outgoing?.id) == f } ?: false
                    val stateID = uuidKey(state?.id)
                    val id = if (isInvite) stateID else focus ?: stateID
                    if (match && id != null) {
                        val since = if (stateID == id) state?.chatSeq ?: 0 else 0
                        perform(AlkkagiCall.State(id, since))
                    }
                }
            } finally {
                if (generation == resetGeneration) {
                    isLoading = false
                    syncJob = null
                }
            }
        }
    }

    private val pollStepSeconds: Double
        get() = if (hasLiveMatch) pollSeconds else minOf(pollSeconds, maxOf(0.001, outsidePollStepSeconds))

    private fun startPolling() {
        if (pollJob != null || service == null || !isWindowVisible || isWindowOccluded) return
        val generation = resetGeneration
        pollToken += 1
        val token = pollToken
        pollJob = scope.launch {
            while (isActive) {
                delay(delayMillis(pollStepSeconds))
                if (generation != resetGeneration || token != pollToken) return@launch
                if (!isWindowVisible || isWindowOccluded) {
                    pollJob = null
                    return@launch
                }
                pollTick(clock())
            }
        }
    }

    /** 받은 신청 배지도 창이 닫힌 동안 만료된다(폴링 없이). */
    private fun scheduleInviteExpiry() {
        inviteExpiryJob?.cancel()
        inviteExpiryJob = null
        val now = estimatedServerNowMs
        if (incoming.any { !it.expiresAtMs.isFinite() || it.expiresAtMs <= now }) incoming = incoming.filter { it.expiresAtMs.isFinite() && it.expiresAtMs > now }
        val sent = outgoing
        if (sent != null && (!sent.expiresAtMs.isFinite() || sent.expiresAtMs <= now)) {
            // 보낸 신청이 응답 없이 만료됐다.
            outgoing = null
            eventNotice = AlkkagiNoticeText.inviteTimedOut
            notice = AlkkagiNoticeText.inviteTimedOut
        }
        val deadlines = incoming.map { it.expiresAtMs } + listOfNotNull(outgoing?.expiresAtMs)
        val deadline = deadlines.minOrNull() ?: return
        val seconds = maxOf(0.0, (deadline - now) / 1000)
        if (!seconds.isFinite()) return
        val generation = resetGeneration
        inviteExpiryJob = scope.launch {
            delay(delayMillis(seconds))
            if (generation != resetGeneration) return@launch
            scheduleInviteExpiry()
            eventNotice = null
        }
    }

    private fun stopPolling() {
        pollToken += 1
        pollJob?.cancel()
        pollJob = null
        deadlineJob?.cancel()
        deadlineJob = null
    }

    private val deadlineKey: String?
        get() {
            val s = state ?: return null
            val deadline = s.deadlineMs ?: return null
            if (s.phase == AlkkagiMatchPhase.finished) return null
            return "${s.id.lowercase()}:${s.revision}:$deadline"
        }

    /** 마감 맞춤 새로고침 시각 — 굴림은 쏘기 재생 끝, 조준은 마감 + 판정 유예, 배치는 마감 그대로. */
    private val refreshDeadlineMs: Double?
        get() {
            val s = state ?: return null
            val shot = s.shot
            if (s.phase == AlkkagiMatchPhase.rolling && shot != null) return shot.startedAtMs + shot.duration * 1000
            val deadline = s.deadlineMs ?: return null
            val grace = s.graceMs
            if (s.phase == AlkkagiMatchPhase.aiming && grace != null && grace.isFinite() && grace > 0) return deadline + grace
            return deadline
        }

    /** 굴림 끝 새로고침은 창이 숨거나 가려져도 한 번 한다(누군가 서버를 불러야 다음 차례가 열린다). */
    private val refreshesWhileHidden: Boolean get() = state?.phase == AlkkagiMatchPhase.rolling

    private fun refreshExpiredDeadline() {
        if (!((isWindowVisible && !isWindowOccluded) || refreshesWhileHidden)) return
        val key = deadlineKey ?: return
        if (key == refreshedDeadline) return
        refreshedDeadline = key
        requestSync()
    }

    private fun scheduleDeadlineRefresh() {
        deadlineJob?.cancel()
        deadlineJob = null
        if (!((isWindowVisible && !isWindowOccluded) || refreshesWhileHidden)) return
        val deadline = refreshDeadlineMs ?: return
        if (!deadline.isFinite()) return
        val key = deadlineKey ?: return
        if (key == refreshedDeadline) return
        val seconds = maxOf(0.0, (deadline - estimatedServerNowMs) / 1000)
        if (!seconds.isFinite()) return
        val generation = resetGeneration
        deadlineJob = scope.launch {
            delay(delayMillis(seconds))
            if (generation != resetGeneration || deadlineKey != key) return@launch
            refreshExpiredDeadline()
        }
    }

    // MARK: - 순위

    /** 순위표 한 번(60초 주기). 주 스위치가 꺼져 있으면 아무것도 안 한다. 실패는 안내 줄로 새지 않는다. */
    suspend fun refreshRanking() {
        val service = service ?: return
        if (!rankingEnabled || rankingInFlight) return
        rankingInFlight = true
        val generation = resetGeneration
        try {
            lastRankingRequestAt = clock()
            val response = try {
                service.call(AlkkagiCall.Ranking)
            } catch (e: CancellationException) {
                if (!coroutineContext.isActive) throw e
                return
            } catch (e: Exception) {
                if (generation == resetGeneration && e == AlkkagiServiceError.ServerMissing && !rankingUnavailable) rankingUnavailable = true
                return
            }
            if (generation != resetGeneration) return
            applyRanking(response)
        } finally {
            if (generation == resetGeneration) rankingInFlight = false
        }
    }

    fun applyRanking(response: AlkkagiResponse) {
        if (response.status != AlkkagiRPCStatus.ok) return
        val board = response.ranking ?: return
        val mapped = AlkkagiRankingBoard(
            board.entries.map {
                AlkkagiRankEntry(it.rank.clampedInt(), it.id, it.displayName, it.avatarURL, it.characterID, it.wins.clampedInt(), it.losses.clampedInt(), it.draws.clampedInt(), it.points.clampedInt())
            },
            board.me?.let { AlkkagiMyRank(it.rank?.clampedInt(), it.wins.clampedInt(), it.losses.clampedInt(), it.draws.clampedInt(), it.points.clampedInt()) },
            board.recordSinceMs?.takeIf { it > 0 && it.isFinite() }?.let { SwiftDate(it / 1000) },
        )
        if (rankingUnavailable) rankingUnavailable = false
        if (ranking != mapped) ranking = mapped
    }

    // MARK: - 관전(주 스위치 spectatorFeaturesEnabled · 2초 · 끝난 판은 결과까지 두고 걸음 멈춤)

    fun watch(matchID: String) {
        val id = uuidKey(matchID) ?: return
        if (!spectatorFeaturesEnabled || hasLiveMatch) return
        if (watchMatchID != id) {
            watchGeneration += 1
            watchJob?.cancel()
            watchJob = null
            if (watched != null) watched = null
        }
        watchMatchID = id
        startWatchPolling()
    }

    fun stopWatching() {
        watchGeneration += 1
        watchJob?.cancel()
        watchJob = null
        watchMatchID = null
        if (watched != null) watched = null
    }

    internal fun applyWatch(response: AlkkagiResponse, matchID: String, generation: Int) {
        if (generation != watchGeneration || watchMatchID != matchID) return
        when (response.status) {
            AlkkagiRPCStatus.ok -> {
                val next = response.watch ?: return
                if (uuidKey(next.id) != matchID) return
                val old = watched
                if (old != null && old.id.equals(next.id, ignoreCase = true) && old.revision > next.revision) return
                if (watched != next) watched = next
            }
            AlkkagiRPCStatus.notFound -> stopWatching()
            else -> Unit
        }
    }

    private fun startWatchPolling() {
        if (watchJob != null) return
        val service = service ?: return
        val matchID = watchMatchID ?: return
        val generation = watchGeneration
        val reset = resetGeneration
        watchJob = scope.launch {
            var isFirst = true
            while (isActive) {
                if (!isFirst) delay(delayMillis(watchPollSeconds))
                if (reset != resetGeneration || generation != watchGeneration || !spectatorFeaturesEnabled) return@launch
                val rests = !isFirst && !(isWindowVisible && !isWindowOccluded)
                isFirst = false
                if (rests) continue
                val response = try {
                    service.call(AlkkagiCall.WatchLive(matchID))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (e == AlkkagiServiceError.ServerMissing) {
                        if (reset == resetGeneration && generation == watchGeneration) stopWatching()
                        return@launch
                    }
                    continue
                }
                if (reset != resetGeneration) return@launch
                applyWatch(response, matchID, generation)
                if (generation == watchGeneration && watched?.isFinished == true) {
                    watchJob = null
                    return@launch
                }
            }
        }
    }
}

/** 유니코드 스칼라 수(Swift `unicodeScalars.count`). */
internal fun String.codePointCount(): Int {
    var count = 0
    var i = 0
    while (i < length) {
        val c = this[i]
        i += if (c.isHighSurrogate() && i + 1 < length && this[i + 1].isLowSurrogate()) 2 else 1
        count += 1
    }
    return count
}
