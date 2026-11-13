// 원본: Sources/CheckCore/MahjongStore.swift @ e4995a3a(아잉 마작 4인 판 스토어 — 표면 · 공용 관용구 · 폴링 · 초인종) — Android 판 8
//
// 규약(맥 · 폰과 같다): ① 서버 권위 — 낙관적 그림 없음(연습판은 엔진이 권위) ② 서버 시계 보정 ③ 창(화면)이 탁자를 보일 때만 폴링
// ④ 늦은 응답 버리기(가드 (a)~(i)) ⑤ 문구는 MahjongNoticeText 한 곳 ⑥ 초인종 합치기 ⑮ 이 기기가 연 판(GameDeviceLedger)에서만
// 알림 · 깨우기 · 보조 자동 보내기. `match` 는 서버 방(forming) · 판 전용, 연습판은 `practice` 칸에만 산다 — 화면은 `table` 한 길.
// 판 · 로비 · 울기 · 연습판 몸통은 MahjongStoreLobby · Game · Call · Practice.kt.
//
// Kotlin 이식(길건너 · 알까기 스토어와 같다): `@MainActor` = [scope] 한 곳 · `Task {}` = scope.launch · `@Observable` = mutableStateOf ·
// `weak var host` = 강한 참조(세대로 늦은 응답을 버린다). 버림 · 울기 움직임(MahjongMotion)은 맥 탁자 전용이라 옮기지 않았다(폰 탁자는 안 쓴다).
package com.yehsung.aingcheck.core.stores.mahjong

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClock
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.stores.games.GameDeviceLedger
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.stores.tetris.DISTANT_PAST
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.cancellation.CancellationException
import kotlin.random.Random

/** 호스트(네트워크 · 세션 · 루비 미러) — 오목 계약을 그대로 빌린다. */
typealias MahjongStoreHost = GomokuStoreHost

/** 화면 단계. 연습 탁자를 보이는 동안은 playing(연습판이 끝났으면 finished). */
enum class MahjongPhase { lobby, room, playing, finished }

enum class MahjongAvailability { available, updateRequired, serverMissing }

enum class MahjongStake(val rawValue: Int) {
    three(3), five(5), ten(10);

    companion object {
        fun of(raw: Int): MahjongStake? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 보조 — 기기 로컬 설정(`mahjong.aids`). 자동으로 보내는 것은 이 기기가 연 판에서만. 저장값에 없는 칸은 기본값. */
@Serializable
data class MahjongAids(
    /** 쯔모/론 선택지가 오면 바로 보낸다. */
    val autoWin: Boolean = false,
    /** 론 아닌 울기 프롬프트는 바로 패스(국마다 꺼짐). */
    val noCalls: Boolean = false,
    /** 쯔모 · 론 · 암깡 · 가깡 · 리치 선택지가 없으면 뽑은 패를 버린다(결정 시작 + 0.5~1.0초 뒤). */
    val tsumogiri: Boolean = false,
    /** 두 번 눌러 버리기. */
    val twoClickDiscard: Boolean = false,
    /** 패 귀퉁이 글자. */
    val cornerLabels: Boolean = true,
)

/** 창 밖 알림 한 건 — 모두 이 기기가 연 판에서만. `key` 가 같으면 다시 띄우지 않는다. */
data class MahjongAttention(val kind: Kind, val matchID: String, val handIndex: Int, val key: String, val opponentName: String? = null) {
    enum class Kind { matchStarted, myTurn, away, closedWhilePlaying }
}

/** 결정 정체성. 이것이 바뀌거나 결정이 없어지는 순간 2단 입력을 모두 접고 비행 잠금을 푼다. */
data class MahjongDecisionKey(val matchID: String, val handIndex: Int, val kind: String, val anchor: Int, val startedMs: Double) {
    companion object {
        fun of(payload: MahjongStatePayload?): MahjongDecisionKey? {
            val match = payload?.match ?: return null
            val decision = payload.myDecision ?: return null
            val hand = match.handIndex ?: 0
            return when (decision) {
                is MahjongDecision.Turn -> MahjongDecisionKey(match.id, hand, decision.kind, decision.decisionSeq, decision.startedMs)
                is MahjongDecision.Call -> MahjongDecisionKey(match.id, hand, decision.kind, decision.windowId, decision.startedMs)
            }
        }
    }
}

/** 연습판(혼자 + 봇 셋). `match` 와 따로 산다. 엔진 · 세대 · 연습 시계 · 멈춤 여부를 쥔다. 바꿀 때는 copy() 로 새 값을 만들어 넣는다. */
data class MahjongPracticeSession(
    val matchID: String,
    val format: MahjongFormat,
    /** '실전처럼 5+20'(꺼짐 = 넉넉히). */
    val timed: Boolean,
    /** 사람 자리(0~3). */
    val humanSeat: Int,
    var generation: Int,
    /** 엔진 `payload(for: 사람 자리)` — 화면은 `MahjongStore.table` 로 이것을 그린다. */
    var payload: MahjongStatePayload,
    var isPaused: Boolean = false,
) {
    /** 판 권위. 패산 · 남의 손은 이 안에만 있다(화면은 payload 만 본다). */
    internal var engine: MahjongTableEngine? = null
    internal var humanAnchor: String? = null
    internal var humanStartedAt: SwiftDate? = null
    internal var bankMs: Int = MahjongClock.bankFullMs
    internal var bankHandIndex: Int = -1
    internal var callPromptAt: SwiftDate? = null
    internal var hintShown: Boolean = false
    internal var windowID: Int? = null
    internal var claimReadyAt: SwiftDate? = null
    internal var aidDueAt: SwiftDate? = null
    internal var pausedAt: SwiftDate? = null
    internal var roomHold: Boolean = false

    /** 몸통 칸까지 옮긴 사본(data class copy 는 생성자 칸만 옮긴다). */
    internal fun duplicate(): MahjongPracticeSession = copy().also {
        it.engine = engine
        it.humanAnchor = humanAnchor
        it.humanStartedAt = humanStartedAt
        it.bankMs = bankMs
        it.bankHandIndex = bankHandIndex
        it.callPromptAt = callPromptAt
        it.hintShown = hintShown
        it.windowID = windowID
        it.claimReadyAt = claimReadyAt
        it.aidDueAt = aidDueAt
        it.pausedAt = pausedAt
        it.roomHold = roomHold
    }
}

/** 연습 중 위 띠 "방 3/4 · 남은 7:12 · [방 보기]". */
data class MahjongRoomBand(val roomID: String, val joined: Int, val expiresAt: SwiftDate, val readyToStart: Boolean)

class MahjongStore(
    host: MahjongStoreHost? = null,
    /** 이 스토어의 일이 도는 곳(Swift `@MainActor`). */
    val scope: CoroutineScope,
    /** 기기 시계(시험이 갈아 끼운다). */
    var clock: () -> SwiftDate,
    /** 봇 결정을 돌리는 곳(Swift `Task.detached`). 시험은 바꿔 끼울 수 있다. */
    val botContext: CoroutineContext = Dispatchers.Default,
) {
    var host: MahjongStoreHost? = host
        private set

    fun attach(host: MahjongStoreHost) {
        this.host = host
    }

    companion object {
        const val lobbyPollSeconds = 30.0
        const val roomPollSeconds = 10.0
        const val statePollSecondsSubscribed = 5.0
        const val statePollSecondsUnsubscribed = 1.5
        const val rankingPollSeconds = 60.0
        const val roomCheckSeconds = 30.0
        const val menuLobbyThrottleSeconds = 30.0
        const val wakeRetrySeconds = 1.0
        const val wakeRetryLimit = 2
        const val wakeSlackMs = 100.0
        const val beatJitterMs = 150.0
        const val defaultGraceMs = 1_000.0
        const val eventTailLimit = 80
        const val aidsDefaultsKey = "mahjong.aids"
        /** 사람 자리에 로그인 사용자가 없을 때 쓰는 id. */
        const val practiceHumanID = "${MahjongStatePayload.practiceIDPrefix}me"
        const val practiceIdleCallPassSeconds = 30.0
        const val practiceIdleCallHintSeconds = 5.0

        fun statePollSeconds(subscribed: Boolean): Double = if (subscribed) statePollSecondsSubscribed else statePollSecondsUnsubscribed

        /** 국 결과 쉬는 시간(초) = 7 + 4 × (화료자 − 1). */
        fun practiceHandRestSeconds(winners: Int): Double = 7 + 4 * maxOf(winners - 1, 0).toDouble()

        /** forming 방의 joined 수. */
        fun joinedCount(payload: MahjongStatePayload?): Int = payload?.members?.count { it.state == "joined" } ?: 0

        /** 울기 창 열쇠("판#창번호"). */
        fun windowKey(matchID: String, windowID: Int): String = "$matchID#$windowID"

        /** 사건 꼬리를 seq 로 이어 붙인다(겹치면 새 것, seq 순, 최근 80). */
        fun mergedEvents(held: List<MahjongEvent>, arriving: List<MahjongEvent>): List<MahjongEvent> {
            val bySeq = LinkedHashMap<Int, MahjongEvent>()
            for (e in held) bySeq[e.seq] = e
            for (e in arriving) bySeq[e.seq] = e
            return bySeq.values.sortedBy { it.seq }.takeLast(eventTailLimit)
        }

        /** 종류별 조합 목록(서버가 준 것 그대로). */
        fun options(kind: com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind, call: MahjongDecision.Call): List<List<com.yehsung.aingcheck.core.rules.mahjong.MahjongTile>> =
            when (kind) {
                com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind.ron -> if (call.ron) listOf(emptyList()) else emptyList()
                com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind.pon -> call.pon
                com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind.minkan -> call.minkan
                com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind.chi -> call.chi
            }

        /** 이 state 에 내가 앉아 있는가 — forming 은 joined 멤버(또는 방장), active · finished 는 내 자리. */
        fun isParticipant(payload: MahjongStatePayload, me: String): Boolean {
            val match = payload.match ?: return false
            return when (match.matchStatus) {
                MahjongMatchStatus.forming -> match.host?.id?.lowercase() == me ||
                    (payload.members?.any { it.user?.id?.lowercase() == me && it.state == "joined" } ?: false)
                MahjongMatchStatus.active, MahjongMatchStatus.finished -> payload.mySeat != null
                else -> true
            }
        }

        /** 사람 결정의 정체성(시계 칸 제외). */
        fun practiceAnchor(decision: MahjongDecision?, handIndex: Int): String? = when (decision) {
            is MahjongDecision.Turn -> "$handIndex#turn#${decision.decisionSeq}"
            is MahjongDecision.Call -> "$handIndex#call#${decision.windowId}"
            null -> null
        }

        private val aidsJson = Json { ignoreUnknownKeys = true }
    }

    // MARK: 화면 상태

    var phase by mutableStateOf(MahjongPhase.lobby)
        internal set
    var availability by mutableStateOf(MahjongAvailability.available)
        internal set
    private var matchCell by mutableStateOf<MahjongStatePayload?>(null)
    /** 서버 방(forming) · 판 전용 — 연습판은 여기 안 든다. 바뀔 때마다 [matchDidChange]. */
    var match: MahjongStatePayload?
        get() = matchCell
        internal set(value) {
            val old = matchCell
            matchCell = value
            matchDidChange(old)
        }
    /** 연습판 — `match` 와 따로. */
    var practice by mutableStateOf<MahjongPracticeSession?>(null)
        internal set
    /** 화면이 연습 탁자를 고른 상태. */
    var showsPractice by mutableStateOf(false)
        internal set
    var users by mutableStateOf<List<MahjongLobbyUser>>(emptyList())
        internal set
    var invites by mutableStateOf<List<MahjongRoom>>(emptyList())
        internal set
    var publicRooms by mutableStateOf<List<MahjongRoom>>(emptyList())
        internal set
    var record by mutableStateOf<MahjongRecord?>(null)
        internal set
    var rubyBalance by mutableStateOf<Int?>(null)
        internal set
    var ranking by mutableStateOf<MahjongRankingResponse?>(null)
        internal set
    var rankingUnavailable by mutableStateOf(false)
        internal set
    private var noticeCell by mutableStateOf<String?>(null)
    val notice: String? get() = noticeCell
    /** 방 · 차례 동작 비행 중(단추 잠금). */
    var isWorking by mutableStateOf(false)
        internal set
    /** 울기 답 비행 중 — isWorking 과 따로(패스가 막히지 않게). */
    var isAnsweringCall by mutableStateOf(false)
        internal set
    var riichiArmed by mutableStateOf(false)
        internal set
    var chiChoicesOpen by mutableStateOf(false)
        internal set
    var kanChoicesOpen by mutableStateOf(false)
        internal set
    var isWindowVisible by mutableStateOf(false)
        internal set
    var isWindowOccluded by mutableStateOf(false)
        internal set

    var selectedStake by mutableStateOf(MahjongStake.three)
    var selectedFormat by mutableStateOf(MahjongFormat.tonpuu)
    var selectedPublic by mutableStateOf(false)
    /** 연습판 '실전처럼 5+20'(기본 꺼짐 = 넉넉히). */
    var practiceTimed by mutableStateOf(false)
    private var aidsCell by mutableStateOf(MahjongAids())
    /** 보조 — 바뀌면 [aidsDefaults] 에 저장한다. */
    var aids: MahjongAids
        get() = aidsCell
        set(value) {
            aidsCell = value
            saveAids()
        }
    /** 숨김 · 차단 거울(사람 uuid). */
    var hiddenPeerIDs by mutableStateOf<Set<SwiftUUID>>(emptySet())
        private set
    var rankingEnabled by mutableStateOf(false)
    /** 판돈 대결 스위치(꺼지면 만들기 · 참가 · 초대를 막는다 — 연습판은 늘 된다). */
    val duelsEnabled: Boolean get() = host?.appConfig?.duelsEnabled ?: true

    // MARK: 콜백 · 장부

    /** 이 기기가 연 판 장부. 앱 배선이 `defaults` 를 넣는다. */
    var deviceLedger = GameDeviceLedger("mahjong", 6 * 3_600.0)
    var presentWindow: (() -> Unit)? = null
    var dismissWindow: (() -> Unit)? = null
    var requestAttention: (() -> Unit)? = null
    var onInviteArrived: ((MahjongRoom) -> Unit)? = null
    var onAttention: ((MahjongAttention) -> Unit)? = null
    /** 루비 판이 끝난 것을 처음 본 순간 한 번(연습판 · 무효 판 제외). */
    var onMatchFinished: (() -> Unit)? = null
    /** 화면 켜 두기 신호(맥 App Nap 붙들기 자리). 값이 바뀔 때만 부른다. */
    var onHoldingActivityChange: ((Boolean) -> Unit)? = null
    var isHoldingActivity = false
        private set
    /** 보조 설정을 둘 곳(null 이면 이 값 안에만 산다). 넣는 순간 읽어 온다. */
    var aidsDefaults: KeyValueStore? = null
        set(value) {
            field = value
            loadAids()
        }

    // MARK: 동기화 장부

    /** 기기 시계 − 서버 시계(초). */
    var serverClockOffset: Double = 0.0
        internal set
    internal var writeRevision = 0
    /** 로비가 말한 내 forming 방(내가 앉은 방은 받은 초대 목록에서 뺀다). */
    var lobbyRoom by mutableStateOf<MahjongRoom?>(null)
        internal set
    internal var activeMatchID: String? = null
    internal val answeredWindowIDs = mutableSetOf<String>()
    internal val answeredWindowAnswers = mutableMapOf<String, String>()
    internal val dismissedMatchIDs = mutableSetOf<String>()
    internal val deliveredAttentionKeys = mutableSetOf<String>()
    internal val seenInviteIDs = mutableSetOf<SwiftUUID>()
    internal var lastLobbyRequestAt: SwiftDate = DISTANT_PAST
    internal var lastStateRequestAt: SwiftDate = DISTANT_PAST
    internal var resetGeneration = 0
    internal var pollJob: Job? = null
    internal var wakeJob: Job? = null
    /** 연습판 장부(봇 결정 주입 · 세대 · 작업). 시험이 보여 주는 시간 · 패산 · 자리를 고정한다. */
    val practiceRuntime = MahjongPracticeRuntime()

    internal var lobbyInFlight = false
    internal var lobbyAgain = false
    internal var stateInFlight = false
    internal var stateAgain = false
    internal var stateInFlightID: String? = null
    internal var pendingStateID: String? = null
    internal var syncJob: Job? = null
    internal var syncPendingTrailing = false
    internal var pollToken = 0
    /** 폴링 루프의 걸음 간격(초). */
    var pollStepSeconds: Double = 0.5
    /** 깨우기 · 보조 자동 보내기 · 연습 시계를 실제 타이머로 돌린다(시험은 끄고 직접 밟는다). */
    var timersEnabled = true
    internal var requestTicket = 0
    internal var appliedTicket = 0
    internal var lastMenuLobbyAt: SwiftDate = DISTANT_PAST
    internal var lastRankingRequestAt: SwiftDate = DISTANT_PAST
    internal var lastRoomCheckAt: SwiftDate = DISTANT_PAST
    internal var wakeFiredKey: String? = null
    internal var wakeFiredCount = 0
    internal var wakeFiredAt: SwiftDate = DISTANT_PAST
    internal var wakeScheduledKey: String? = null
    internal var actionToken = 0
    internal var callToken = 0
    /** 요청 마감 상하한(초 — `min(8, max(2, …))`). 시험이 줄인다. */
    var requestDeadlineFloor: Double = 2.0
    var requestDeadlineCeiling: Double = 8.0
    /** 보조 쯔모기리 지연(결정 시작 + 이 값 초 — 0.5~1.0 무작위). 시험이 고정한다. */
    var aidJitter: () -> Double = { Random.nextDouble(0.5, 1.0) }
    internal val aidHandledKeys = mutableSetOf<MahjongDecisionKey>()
    internal var aidJob: Job? = null
    internal var noCallsHandKey: String? = null
    internal val timeoutNoticeKeys = mutableSetOf<String>()

    // MARK: 계산 속성

    /** '창이 말할 수 있다' = 보이고 가려지지 않았다. 알림 · 폴링 · 연습판 멈춤이 모두 이것만 읽는다. */
    val isWindowShowingTable: Boolean get() = isWindowVisible && !isWindowOccluded

    /** 그릴 판 — 그리는 길은 하나(연습판도 루비 판도). */
    val table: MahjongStatePayload? get() = if (showsPractice) practice?.payload else match

    /** 연습 중 위 띠 — 연습 탁자를 보이는 동안 서버 방이 forming 일 때만. */
    val roomBand: MahjongRoomBand?
        get() {
            val room = match?.match ?: return null
            if (!showsPractice || room.matchStatus != MahjongMatchStatus.forming) return null
            val joined = joinedCount(match)
            return MahjongRoomBand(room.id, joined, localDate(room.roomExpiresMs) ?: clock(), joined >= 4)
        }

    val visibleUsers: List<MahjongLobbyUser> get() = users.filter { it.id !in hiddenPeerIDs }

    /** 차단 거울 + 내가 앉은 방을 뺀 받은 초대. */
    val visibleInvites: List<MahjongRoom>
        get() {
            val seated = seatedRoomID
            return invites.filter { room ->
                if (seated != null && room.id == seated) return@filter false
                val hostID = room.host?.id?.let(SwiftUUID::parse)
                !(hostID != null && hostID in hiddenPeerIDs)
            }
        }

    /** 받은 초대가 있다 — 점 · 배너가 모두 이것 하나(모든 기기). */
    val hasIncomingInvite: Boolean get() = visibleInvites.isNotEmpty()

    /** 내 자리가 비움이고 이 기기가 연 판이다. */
    val hasAwaySeatHere: Boolean
        get() {
            val payload = match ?: return false
            val current = payload.match ?: return false
            if (current.matchStatus != MahjongMatchStatus.active) return false
            val away = payload.myAway != null || payload.mySeatRow?.away == true
            return away && ownsMatch(current.id)
        }

    /** 단추는 이것만 그린다(루비 판은 서버, 연습판은 엔진). */
    val myDecision: MahjongDecision? get() = table?.myDecision

    val decisionKey: MahjongDecisionKey? get() = MahjongDecisionKey.of(table)

    val isPractice: Boolean get() = showsPractice && practice != null

    /** 서버 방의 방장인가(연습 중에도 `match` 로 잰다). */
    val isHost: Boolean
        get() {
            val me = host?.session?.userID?.lowercase() ?: return false
            val room = match ?: return false
            room.match?.host?.id?.lowercase()?.let { return it == me }
            return room.members?.any { it.isHost == true && it.user?.id?.lowercase() == me } ?: false
        }

    /** 방장 && forming 방에 넷이 앉았다. */
    val canStart: Boolean get() = isHost && match?.match?.matchStatus == MahjongMatchStatus.forming && joinedCount(match) == 4

    /** 확성기 배너를 미룬다 — 판을 두는 중(연습판이거나 이 기기가 연 판). */
    val defersMegaphoneBanner: Boolean
        get() {
            if (phase != MahjongPhase.playing) return false
            if (isPractice) return true
            val id = match?.match?.id ?: return false
            return ownsMatch(id)
        }

    // MARK: 숨김 거울 · 보조 저장

    fun setHiddenPeers(ids: Set<SwiftUUID>) {
        if (hiddenPeerIDs != ids) hiddenPeerIDs = ids
    }

    private fun saveAids() {
        val store = aidsDefaults ?: return
        store.putString(aidsDefaultsKey, aidsJson.encodeToString(MahjongAids.serializer(), aids))
    }

    private fun loadAids() {
        val text = aidsDefaults?.getString(aidsDefaultsKey) ?: return
        val stored = try {
            aidsJson.decodeFromString(MahjongAids.serializer(), text)
        } catch (_: Exception) {
            return
        }
        if (stored != aids) aidsCell = stored
    }

    // MARK: 장부 도우미

    private fun nowSeconds(): Double = clock().timeIntervalSince1970

    /** 이 기기가 이 판(방)을 열었는가. */
    fun ownsMatch(matchID: String): Boolean = deviceLedger.owns(matchID, host?.session?.userID, nowSeconds())

    internal fun noteOwnsMatch(matchID: String) {
        deviceLedger.note(matchID, host?.session?.userID, nowSeconds())
        syncHoldingActivity()
    }

    internal fun dropOwnership(matchID: String) {
        deviceLedger.drop(matchID, host?.session?.userID, nowSeconds())
        syncHoldingActivity()
    }

    /** 화면을 붙들어야 하는가 — 이 기기가 연 방 · 판(forming · active)이 있는 동안. 연습판은 뺀다. */
    val holdsActivity: Boolean
        get() {
            val header = match?.match ?: return false
            if (header.matchStatus != MahjongMatchStatus.forming && header.matchStatus != MahjongMatchStatus.active) return false
            return ownsMatch(header.id)
        }

    internal fun syncHoldingActivity() {
        val holding = holdsActivity
        if (holding == isHoldingActivity) return
        isHoldingActivity = holding
        onHoldingActivityChange?.invoke(holding)
    }

    // MARK: 창(폰은 화면)

    /** 창(화면)을 연다. `focusMatchID` 가 있으면 그 판 · 방을 먼저 읽는다. */
    fun openWindow(focusMatchID: String?) {
        presentWindow?.invoke()
        if (host?.session == null) return
        val focus = focusMatchID?.lowercase()
        scope.launch {
            if (focus != null && !focus.startsWith(MahjongStatePayload.practiceIDPrefix)) {
                refreshMatch(focus)
            } else {
                val current = match?.match
                if (current != null && !current.matchStatus.isTerminal) refreshMatch(current.id)
            }
            refreshLobby()
        }
    }

    /** 창(화면)이 실제로 보이기 시작했다. 열린 채 가려진 창을 다시 부르는 길이면 가림 기록을 그대로 둔다. */
    fun windowDidShow() {
        val reshownWhileOccluded = isWindowVisible && isWindowOccluded
        if (!isWindowVisible) isWindowVisible = true
        if (!reshownWhileOccluded && isWindowOccluded) isWindowOccluded = false
        tableVisibilityDidChange()
    }

    /** 창이 가려졌다 · 닫혔다. 폴링 · 연습판만 멈춘다 — 루비 판은 계속된다. */
    fun windowDidHide() {
        if (isWindowVisible) isWindowVisible = false
        if (isWindowOccluded) isWindowOccluded = false
        tableVisibilityDidChange()
    }

    /** 창의 가림 상태가 바뀌었다(폰: 앱이 뒤로 · 앞으로). */
    fun windowOcclusionDidChange(visible: Boolean) {
        if (isWindowOccluded == visible) isWindowOccluded = !visible
        tableVisibilityDidChange()
    }

    /** 창을 정말 닫았다. 사람 닫기 + 이 기기가 연 판이 진행 중이면 닫기 안내를 판마다 한 번. */
    fun windowDidClose(byUser: Boolean) {
        val current = match?.match ?: return
        if (!byUser || current.matchStatus != MahjongMatchStatus.active || !ownsMatch(current.id)) return
        deliverAttention(MahjongAttention(MahjongAttention.Kind.closedWhilePlaying, current.id, current.handIndex ?: 0, "${current.id}#closed"))
    }

    internal fun tableVisibilityDidChange() {
        if (isWindowShowingTable) startPolling() else stopPolling()
        syncPracticePause()
    }

    internal fun deliverAttention(attention: MahjongAttention) {
        if (!deliveredAttentionKeys.add(attention.key)) return
        onAttention?.invoke(attention)
    }

    /** 로그아웃 · 계정 바뀜. 화면 · 장부 밖 기록을 모두 비우고 나가 있던 응답을 버린다. */
    fun reset() {
        resetGeneration += 1
        pollJob?.cancel()
        pollJob = null
        wakeJob?.cancel()
        wakeJob = null
        syncJob?.cancel()
        syncJob = null
        syncPendingTrailing = false
        aidJob?.cancel()
        aidJob = null
        pollToken += 1
        lobbyInFlight = false
        lobbyAgain = false
        stateInFlight = false
        stateAgain = false
        stateInFlightID = null
        pendingStateID = null
        requestTicket = 0
        appliedTicket = 0
        lastMenuLobbyAt = DISTANT_PAST
        lastRankingRequestAt = DISTANT_PAST
        lastRoomCheckAt = DISTANT_PAST
        wakeFiredKey = null
        wakeFiredCount = 0
        wakeFiredAt = DISTANT_PAST
        wakeScheduledKey = null
        actionToken += 1
        callToken += 1
        aidHandledKeys.clear()
        noCallsHandKey = null
        timeoutNoticeKeys.clear()
        discardPracticeGame()
        showsPractice = false
        match = null
        users = emptyList()
        invites = emptyList()
        publicRooms = emptyList()
        record = null
        rubyBalance = null
        ranking = null
        rankingUnavailable = false
        noticeCell = null
        isWorking = false
        isAnsweringCall = false
        foldTwoStageInputs()
        availability = MahjongAvailability.available
        lobbyRoom = null
        activeMatchID = null
        answeredWindowIDs.clear()
        answeredWindowAnswers.clear()
        dismissedMatchIDs.clear()
        deliveredAttentionKeys.clear()
        seenInviteIDs.clear()
        lastLobbyRequestAt = DISTANT_PAST
        lastStateRequestAt = DISTANT_PAST
        writeRevision = 0
        serverClockOffset = 0.0
        recomputePhase()
        syncHoldingActivity()
    }

    // MARK: 공용 도우미

    /** 서버 epoch ms → 기기 시각. */
    fun localDate(serverMs: Double?): SwiftDate? = serverMs?.let { SwiftDate(it / 1_000 + serverClockOffset) }

    internal fun noteServerClock(serverNowMs: Double?) {
        serverNowMs ?: return
        serverClockOffset = clock().timeIntervalSince1970 - serverNowMs / 1_000
    }

    /** 내가 앉은 forming 방 id(받은 초대에서 뺀다). */
    internal val seatedRoomID: SwiftUUID?
        get() {
            val room = match?.match
            if (room != null && room.matchStatus == MahjongMatchStatus.forming) SwiftUUID.parse(room.id)?.let { return it }
            return lobbyRoom?.id
        }

    /** 2단 입력(리치 무장 · 치 조합 · 깡 후보)을 모두 접는다. */
    internal fun foldTwoStageInputs() {
        if (riichiArmed) riichiArmed = false
        if (chiChoicesOpen) chiChoicesOpen = false
        if (kanChoicesOpen) kanChoicesOpen = false
    }

    internal fun recomputePhase() {
        val p = practice
        val next = if (showsPractice && p != null) {
            if (p.payload.match?.matchStatus == MahjongMatchStatus.finished) MahjongPhase.finished else MahjongPhase.playing
        } else {
            when (match?.match?.matchStatus) {
                MahjongMatchStatus.forming -> MahjongPhase.room
                MahjongMatchStatus.active -> MahjongPhase.playing
                MahjongMatchStatus.finished -> MahjongPhase.finished
                else -> MahjongPhase.lobby
            }
        }
        if (phase != next) phase = next
    }

    // MARK: 공용 호출 관용구

    /** 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조. null = 버린 결과. */
    internal suspend fun <T> perform(operation: suspend (SupabaseWorkService, String) -> T): DuelCall<T>? {
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

    /** 요청 마감: `seconds` 안에 안 끝나면 그 요청을 취소하고 null. 서버는 이미 처리했을 수 있다 — 다음 state 가 진실이다. */
    internal suspend fun performWithin(seconds: Double, operation: suspend (SupabaseWorkService, String) -> MahjongActionResponse): DuelCall<MahjongActionResponse>? {
        var result: DuelCall<MahjongActionResponse>? = null
        val request = scope.launch { result = perform(operation) }
        val timer = scope.launch {
            delay(delayMillis(maxOf(0.0, seconds)))
            request.cancel()
        }
        request.join()
        timer.cancel()
        return result
    }

    /** act · call · back 의 요청 마감(초) — `min(천장, max(바닥, 내 deadline_ms − 지금 + grace_ms))`. */
    internal fun requestDeadlineSeconds(deadlineMs: Double?): Double {
        val grace = match?.match?.graceMs?.toDouble() ?: defaultGraceMs
        val deadline = localDate(deadlineMs?.let { it + grace }) ?: return requestDeadlineCeiling
        return minOf(requestDeadlineCeiling, maxOf(requestDeadlineFloor, deadline.timeIntervalSince(clock())))
    }

    internal fun isSchemaMissing(error: Throwable): Boolean = error == SupabaseWorkServiceError.DatabaseSchemaMissing

    internal fun noteActionFailure(error: Throwable) {
        if (isSchemaMissing(error)) noteServerMissing() else setNotice(MahjongNoticeText.checkConnection)
    }

    internal fun noteServerMissing() {
        if (availability != MahjongAvailability.serverMissing) availability = MahjongAvailability.serverMissing
        setNotice(MahjongNoticeText.unavailable)
    }

    internal fun noteUpdateRequired() {
        if (availability != MahjongAvailability.updateRequired) availability = MahjongAvailability.updateRequired
        setNotice(MahjongNoticeText.updateRequired)
    }

    /** 안내줄 한 문. */
    fun setNotice(text: String?) {
        if (noticeCell != text) noticeCell = text
    }

    /** 잔액 한 문 — 호스트 루비 미러도 같이. */
    internal fun applyRuby(value: Int?) {
        value ?: return
        if (rubyBalance != value) rubyBalance = value
        val h = host ?: return
        if (h.rubyBalance != value.toLong()) h.rubyBalance = value.toLong()
    }

    internal fun issueTicket(): Int {
        requestTicket += 1
        return requestTicket
    }

    internal val myUserID: String? get() = host?.session?.userID?.lowercase()

    // MARK: 초인종 · 계기

    /** 직렬화된 재조회 — 도는 중이면 뒤따르는 한 번으로 합친다. */
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

    /** 신호 한 번의 조회: 서버 `match`(방 포함)가 끝나지 않았으면 그 판, 아니면 로비. */
    internal suspend fun syncOnce() {
        val current = match?.match
        if (current != null && !current.matchStatus.isTerminal) refreshMatch(current.id) else refreshLobby()
    }

    // MARK: 폴링

    internal fun startPolling() {
        if (pollJob != null || !isWindowShowingTable || host?.session == null) return
        pollToken += 1
        val token = pollToken
        pollJob = scope.launch {
            while (true) {
                delay(delayMillis(pollStepSeconds))
                if (token != pollToken || !isWindowShowingTable) {
                    if (token == pollToken) pollJob = null
                    return@launch
                }
                pollTick(clock())
            }
        }
    }

    internal fun stopPolling() {
        pollToken += 1
        pollJob?.cancel()
        pollJob = null
    }

    /** 폴링 걸음의 조회를 폴링 작업의 취소 밖에서 돌리고 끝날 때까지 기다린다. */
    internal suspend fun outsidePolling(body: suspend (MahjongStore) -> Unit) {
        scope.launch { body(this@MahjongStore) }.join()
    }
}

/** 연습판 장부(봇 결정 주입 · 세대 · 봇/걸음/시계 작업). */
class MahjongPracticeRuntime {
    /** 봇 한 수 계산(순수) — 셋째 인자는 '이 계산이 취소됐나'. */
    fun interface Decide {
        fun decide(view: MahjongStatePayload, seed: ULong, isCancelled: () -> Boolean): MahjongBotMove
    }

    companion object {
        /** 기본 봇: 실제 시계 + 계산 상한 200ms. 취소되면 마감이 지났다고 말해 2단 보기를 접는다. */
        val standardDecide = Decide { view, seed, isCancelled ->
            val deadline = kotlin.time.TimeSource.Monotonic.markNow() + MahjongBot.computeBudget
            MahjongBot.decide(view, com.yehsung.aingcheck.core.rules.ai.SeededSwiftRandom(seed), pastDeadline = { isCancelled() || deadline.hasPassedNow() })
        }
    }

    var decide: Decide = standardDecide
    /** 보여 주는 시간 배율. 시험은 0. */
    var delayScale: Double = 1.0
    /** 패산(0~135 순열). 시험은 고정한다. */
    var makeWall: () -> List<Int> = { (0 until 136).shuffled() }
    /** 사람 자리(0~3) — "내 자리는 무작위예요". */
    var pickHumanSeat: () -> Int = { Random.nextInt(4) }
    var nextSeed: () -> ULong = { Random.nextLong().toULong() }
    /** 창 · 쯔모 멈춤(초) — 서버 멈춤과 같은 꼴. */
    var pauseSeconds: () -> Double = { Random.nextDouble(0.5, 1.0) }

    var generation = 0
        private set
    var botCalls = 0
        private set
    var droppedBotMoves = 0
        internal set
    internal var botJob: Job? = null
    internal var stepJob: Job? = null
    internal var clockJob: Job? = null

    internal fun bump(): Int {
        generation += 1
        return generation
    }

    internal fun noteBotCall() {
        botCalls += 1
    }

    internal fun cancelTasks() {
        botJob?.cancel()
        botJob = null
        stepJob?.cancel()
        stepJob = null
        clockJob?.cancel()
        clockJob = null
    }
}
