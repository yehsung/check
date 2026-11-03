// 원본: Sources/CheckCore/ReversiStore.swift:394-1889(스토어 본문) @ 12624739
package com.yehsung.aingcheck.core.stores.reversi

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.reversiCancel
import com.yehsung.aingcheck.core.net.reversiChallenge
import com.yehsung.aingcheck.core.net.reversiLobby
import com.yehsung.aingcheck.core.net.reversiMove
import com.yehsung.aingcheck.core.net.reversiResign
import com.yehsung.aingcheck.core.net.reversiRespond
import com.yehsung.aingcheck.core.net.reversiState
import com.yehsung.aingcheck.core.rules.ai.ReversiAIGame
import com.yehsung.aingcheck.core.rules.reversi.ReversiFlipAnimation
import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.rules.reversi.ReversiScore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.gomoku.CallResult
import com.yehsung.aingcheck.core.stores.gomoku.distantPast
import com.yehsung.aingcheck.core.stores.gomoku.isSchemaMissing
import com.yehsung.aingcheck.core.stores.gomoku.notice
import com.yehsung.aingcheck.core.stores.gomoku.performDuelCall
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiIllegalReason
import com.yehsung.aingcheck.core.wire.games.ReversiInviteRow
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyMatchRow
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyMe
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyUserRow
import com.yehsung.aingcheck.core.wire.games.ReversiMatchRow
import com.yehsung.aingcheck.core.wire.games.ReversiMatchStatus
import com.yehsung.aingcheck.core.wire.games.ReversiPeerRow
import com.yehsung.aingcheck.core.wire.games.ReversiPlayerRow
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.wire.games.ReversiRPCStatus
import com.yehsung.aingcheck.core.wire.games.ReversiStatePayload
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.jvm.JvmName
import kotlin.math.abs

// 아잉 뒤집기(내부 이름 reversi) 1:1 대결 스토어 — 화면 상태 · 서버 동기화 · 안전망 폴링 · RPC 호출. Swift `ReversiStore` 의 몸통을 그대로 옮겼다
// (같은 이름 · 같은 순서 — 머리말 ①~⑪ 은 Swift 원본 그대로 지킨다):
//  ① **서버가 권위다.** 판(64자 문자열)·차례·시계·결과·루비는 RPC 응답으로만 바뀐다. 낙관적 착수·낙관적 차감 없음.
//  ② **시각은 서버 시계로 보정한다**(`server_now_ms` 와의 차이).
//  ③ **폴링은 창(화면)이 보일 때만** 돈다. 주기 판정은 [pollTick] 한 곳 + 보낸 신청은 5초마다 `reversi_state(outgoing.id)`.
//  ④ **늦게 온 응답은 버린다** — 세대(reset·watch·ai) · 같은 판 `move_count` 감소 무시 · 끝난 판 뒤 진행 응답 무시 · 다른 진행 판이 있을 때 끝난 판
//     무시 · 접은 판 · 같은 판 조회 합치기 · `outgoingRevision` · [visibleIncomingInvites] 는 `match?.id` 와 같은 id 를 뺀다 · 같은 id 를 판으로 든
//     동안 온 신청 단계 응답 무시 · `writeRevision`(쓰기 응답보다 먼저 나간 로비는 잔액·진행 판 id 를 덮지 않는다) · 로비 조회 합치기(`lobbyAgain`).
//  ⑤ **사용자 문구는 [ReversiNoticeText] 한 곳**. ⑥ 초 단위 값은 잎만 읽는다([remainingSeconds] 는 순수 계산).
//  ⑦ **합법 수는 서버 `legal_moves` 로만**(내 차례일 때만 온다). **AI 판은 로컬 규칙**이 권위다. ⑧ 입력은 한 단(칸 하나).
//  ⑨ **시계는 서버 응답마다 통째로 덮는다**(마감 하나, 표시값 30초 — 서버 유예 2초 미포함).
//  ⑩ 자동 착수 장치(30초 넘기면 서버가 합법 수 중 무작위로 둔다 · `myAutoStreak` · 연속 3이면 패). ⑪ 받은 신청은 로비 `me.incoming` 이 통째로 준다.
//
// ── Android 에서 갈리는 곳 ──
//  · **§8-17 #1(판돈 대결 Android 빌드 깃발)** — 체스·오목과 같다: [duelsLocked] 이면 [challenge]·[respond](accept = true) 가 RPC 를 내지 않고
//    안내 한 줄([ReversiNoticeText.updateMine])만 남긴다. 받은 신청은 서버 사실([incoming]) 그대로 두되 [visibleIncomingInvites] 를 비우고
//    [incomingFoldedNotice] 로 접는다. AI 연습 · 관전 · 순위 · 이미 선 판(같은 계정 다른 기기에서 수락한 판)은 깃발과 무관하다.
//  · **'이 기기가 연 판' 장부(Swift `GameDeviceLedger`)는 옮기지 않았다** — Android 오목·체스 스토어에도 없다(같은 수준으로 둔다). 그래서 판 시작의
//    창 띄우기·말풍선은 같은 계정의 다른 기기가 연 판에서도 선다(Android 체스와 같은 동작). 장부를 이식하는 날 [noteMatchProgress] 첫 줄에 건다.
//  · 서버 `reversi_android_min_build` 가 닫혀 있으면(2147483647) 상대 능력이 false 로 오고 신청은 `target_outdated` 로 돌아온다 — 원문 처리
//    ([ReversiNoticeText.targetOutdated] · 로비 재조회)로 깨지지 않는다. 로비·순위·관전은 부르는 사람 능력을 보지 않는다.
//  · 뒤집기 그림 값([flip])은 판정이 아니라 그림이다 — 이 값이 서 있든 없든 판·합법 수·시계는 같다. 창이 보일 때만 선다.

class ReversiStore(
    /** 스토어가 일을 띄우는 범위(앱은 메인 한 줄기, 시험은 시험 디스패처). */
    val scope: CoroutineScope,
    host: ReversiStoreHost? = null,
) {
    companion object {
        /** 상대 차례 상태 조회 주기(초) — 실시간 구독 중 + 마감이 가깝거나(10초 안) 마감을 모를 때. 오목과 같은 눈금이다. */
        const val statePollSecondsNearDeadline: Double = 3.0
        /** 같은 조회 — 구독 중 + 마감까지 여유가 있을 때. 수는 초인종으로 바로 오고 이 조회는 신호를 놓쳤을 때의 그물이다. */
        const val statePollSecondsCalm: Double = 10.0
        /** 남은 시간이 이 안으로 들어오면 [statePollSecondsNearDeadline] 로 돌아간다(시간 초과 자동 착수를 빨리 본다). */
        const val statePollNearDeadlineSeconds: Double = 10.0
        /** 같은 조회 — 미구독(킬스위치·재연결 중). 신호가 없으니 더 촘촘하다. */
        const val statePollSecondsUnsubscribed: Double = 1.5
        /** 보낸 신청이 떠 있을 때 그 판의 상태를 보는 주기(초). 수락 순간 흑 시계가 돈다 — 초인종을 놓치면 첫 수가 자동 착수가 된다. */
        const val outgoingPollSeconds: Double = 5.0
        const val lobbyPollSeconds: Double = 30.0
        /** 허브·팝오버를 열 때 로비를 다시 읽는 스로틀(초). 신청 TTL(60초)보다 짧다. */
        const val menuLobbyThrottleSeconds: Double = 30.0
        const val watchPollSeconds: Double = 2.0
        const val rankingPollSeconds: Double = 60.0
        const val reloadDedupeSeconds: Double = 1.0
        const val serverClockToleranceSeconds: Double = 0.25
        const val inviteExpiryToleranceSeconds: Double = 1.0
        /** throw 실패(5xx·오프라인)가 이만큼 연속되면 관전을 내리고 연결 안내를 남긴다. */
        const val watchFailureLimit: Int = 3

        internal const val LOG_TAG: String = "reversi"

        /** 지금 상대 차례 상태를 물을 주기. 미구독은 언제나 촘촘하고, 구독 중에는 마감이 멀 때만 늦춘다(오목 규칙 그대로). */
        fun statePollSeconds(subscribed: Boolean, deadline: SwiftDate?, now: SwiftDate): Double {
            if (!subscribed) return statePollSecondsUnsubscribed
            if (deadline == null || deadline.timeIntervalSince(now) <= statePollNearDeadlineSeconds) return statePollSecondsNearDeadline
            return statePollSecondsCalm
        }

        /** 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다(관찰자를 헛되게 깨우지 않게). */
        fun steadyInvite(fresh: ReversiInvite, previous: ReversiInvite?): ReversiInvite {
            if (previous == null || previous.id != fresh.id || previous.stake != fresh.stake || previous.peer != fresh.peer ||
                abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) >= inviteExpiryToleranceSeconds
            ) return fresh
            return previous
        }

        fun steadyOutgoing(fresh: ReversiOutgoing, previous: ReversiOutgoing?): ReversiOutgoing {
            if (previous == null || previous.id != fresh.id || previous.stake != fresh.stake || previous.peer != fresh.peer ||
                abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) >= inviteExpiryToleranceSeconds
            ) return fresh
            return previous
        }

        /** 로컬 거절 문구의 까닭(서버 목록 밖 칸). 규칙상 둘 수 있는 칸이어도 서버가 안 줬으면 "둘 수 없는 칸"이다(⑦). */
        fun localRefusal(board: com.yehsung.aingcheck.core.wire.games.ReversiBoard, color: ReversiColor, idx: Int): ReversiIllegalReason {
            if (idx !in 0 until 64) return ReversiIllegalReason.outOfRange
            if (board[idx] != null) return ReversiIllegalReason.occupied
            if (ReversiRules.flips(board, color, idx).isEmpty()) return ReversiIllegalReason.noFlip
            return ReversiIllegalReason.outOfRange
        }

        /** 로비 사람 행 → ReversiUser. `capable` 이 null 이면 **불가**다. */
        fun user(from: ReversiLobbyUserRow): ReversiUser? {
            val id = from.id?.lowercase()
            if (id.isNullOrEmpty()) return null
            return ReversiUser(
                id = id, displayName = from.displayName ?: "", avatarURL = from.avatarUrl, characterID = from.character,
                center = CenterLabel.display(from.center), isWorking = from.isWorking ?: false,
                isCapable = from.capable ?: false, inMatch = from.inMatch ?: false, focusMode = from.focusMode ?: false,
            )
        }

        /**
         * 로비 정렬: 신청할 수 있는 사람(근무·가능·한가·집중 아님) → 근무 중·가능 → 근무 중 → 나머지, 그 안은 **서버 순서**(안정 정렬).
         * 서버 정렬(working desc → capable desc → 이름 → id)과 같은 줄기라 재정렬이 아니라 되맞춤이다.
         */
        fun sortedForLobby(users: List<ReversiUser>): List<ReversiUser> {
            fun rank(user: ReversiUser): Int = when {
                user.isWorking && user.isCapable && !user.inMatch && !user.focusMode -> 0
                user.isWorking && user.isCapable -> 1
                user.isWorking -> 2
                else -> 3
            }
            return users.sortedBy(::rank)
        }

        /** 판이 **막 끝났는가** — 새 판이 끝났고, 같은 판의 끝난 모양을 이미 들고 있던 게 아니다. */
        fun matchJustFinished(old: ReversiMatchState?, new: ReversiMatchState?): Boolean {
            if (new == null || !new.isFinished) return false
            return !(old?.id == new.id && old.isFinished)
        }

        /** 판 상태 변화 한 줄(없으면 null). 수·차례·끝남·판 교체만 본다 — 시계·루비는 이 줄을 만들지 않는다. */
        fun matchTransitionLine(old: ReversiMatchState?, new: ReversiMatchState?): String? {
            fun turn(m: ReversiMatchState?): String = m?.turn?.rawValue ?: "none"
            fun count(m: ReversiMatchState?): String = m?.moveCount?.toString() ?: "-"
            fun finished(m: ReversiMatchState?): Boolean = m?.isFinished ?: false
            val sameMatch = old?.id == new?.id
            if (sameMatch && count(old) == count(new) && turn(old) == turn(new) && finished(old) == finished(new)) return null
            return "state moves=${count(old)}→${count(new)} turn=${turn(old)}→${turn(new)} " +
                "finished=${finished(new)} sameMatch=$sameMatch ai=${new?.isAI ?: false}"
        }
    }

    /** 네트워크·세션·루비 미러를 빌리는 곳. null 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다. */
    var host: ReversiStoreHost? = host
        private set

    /** 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다. */
    fun attach(host: ReversiStoreHost) {
        this.host = host
    }

    // MARK: 화면 상태

    var phase: ReversiPhase by mutableStateOf(ReversiPhase.lobby)
        internal set
    var availability: ReversiAvailability by mutableStateOf(ReversiAvailability.available)
        internal set

    private var matchCell by mutableStateOf<ReversiMatchState?>(null)

    /** 1:1 또는 AI 판([ReversiMatchState.isAI]). 대입마다 Swift `didSet` 몫([matchDidChange])이 돈다. */
    var match: ReversiMatchState?
        get() = matchCell
        internal set(value) {
            val old = matchCell
            matchCell = value
            matchDidChange(old, value)
        }

    var users: List<ReversiUser> by mutableStateOf(emptyList())
        internal set
    /** 로비 "지금 대결 중" 목록. **서버 순서 그대로**. */
    var liveMatches: List<ReversiLiveMatch> by mutableStateOf(emptyList())
        internal set
    /** 받은 신청(서버가 여럿을 준다 — 최신이 앞). 화면은 [visibleIncomingInvites]·[visibleIncoming] 을 읽는다. */
    var incoming: List<ReversiInvite> by mutableStateOf(emptyList())
        internal set
    var outgoing: ReversiOutgoing? by mutableStateOf(null)
        internal set
    var record: ReversiRecord? by mutableStateOf(null)
        internal set
    /** 서버 응답으로만 갱신(host 에도 반영). */
    var rubyBalance: Long? by mutableStateOf(null)
        internal set
    var notice: String? by mutableStateOf(null)
        internal set
    /** 요청 비행 중(버튼 잠금). */
    var isBusy: Boolean by mutableStateOf(false)
        internal set
    /** 지금 판 위에서 뒤집히는 중인 수(그림 전용 — 입력·판정은 이 값을 보지 않는다). */
    var flip: ReversiFlipAnimation? by mutableStateOf(null)
        internal set
    var spectating: ReversiSpectating? by mutableStateOf(null)
        internal set
    /** 내 판 관전자 수(관전 중이면 보는 판의 수 — 둘은 동시에 서지 않는다). */
    var spectatorCount: Int by mutableStateOf(0)
        internal set
    var ranking: ReversiRanking? by mutableStateOf(null)
        internal set
    /** 서버에 `reversi_ranking` 이 아직 없다(PGRST202). 아래 둘과 **서로 다른 깃발**이다. */
    var rankingUnavailable: Boolean by mutableStateOf(false)
        internal set
    /** 서버에 `reversi_watch` 가 없다(관전 잠금은 이 깃발 하나로만). */
    var watchUnavailable: Boolean by mutableStateOf(false)
        internal set
    /** 서버에 `reversi_watch_live` 가 없어 `reversi_watch` 로 접었다(관전자 수만 못 센다). */
    var spectatorCountUnavailable: Boolean by mutableStateOf(false)
        internal set
    /** 창(폰은 화면)이 보이는가. 30초 링 잎(`paused: !isWindowVisible`)이 읽는다. 시험이 심는다(Swift `package internal(set)` 과 같은 몫). */
    var isWindowVisible: Boolean by mutableStateOf(false)

    /** 로비를 한 번이라도 받았다(화면의 첫 로딩 문구 — Kotlin 체스 스토어와 같은 칸). */
    var hasLoadedLobby: Boolean by mutableStateOf(false)
        internal set
    /** 마지막 로비 조회가 실패했다(화면의 다시 시도 줄). 다음 ok 가 내린다. */
    var lobbyLoadFailed: Boolean by mutableStateOf(false)
        internal set
    /** 순위표를 한 번이라도 받았다(PGRST202 도 "받은 것"으로 센다 — 로딩 문구가 영영 남지 않게). */
    var hasLoadedRanking: Boolean by mutableStateOf(false)
        internal set
    var rankingLoadFailed: Boolean by mutableStateOf(false)
        internal set

    var selectedStake: ReversiStake by mutableStateOf(ReversiStake.three)
    var isRulesVisible: Boolean by mutableStateOf(false)
    /** 차단 거울(조립이 메시지 탭의 차단 목록으로 채운다). 소문자 uuid. */
    var hiddenPeerIDs: Set<String> by mutableStateOf(emptySet())
    /** 순위 적재 스위치. 기본 false — 켜는 곳은 조립뿐(폰은 켠다). */
    var rankingEnabled: Boolean by mutableStateOf(false)
    /** 관전 폴링·관전자 수 스위치. 기본 false — 켜는 곳은 조립뿐(폰은 켠다). **순위와 따로**다. */
    var spectatorFeaturesEnabled: Boolean by mutableStateOf(false)

    // MARK: §8-17 #1 — 판돈 대결 진입 깃발

    val appConfig: AppConfig get() = host?.appConfig ?: AppConfig()

    /** 판돈 대결의 신청·수락 진입이 이 빌드에서 잠겼는가. AI 연습·관전·순위는 이 값을 보지 않는다. */
    val duelsLocked: Boolean get() = !appConfig.duelsEnabled

    /** 잠긴 빌드에서 받은 신청을 접는 한 줄(받은 신청이 있을 때만 — 차단한 사람의 신청은 세지 않는다). */
    val incomingFoldedNotice: String?
        get() {
            if (!duelsLocked) return null
            val matchID = match?.id
            if (incoming.none { it.peer.id !in hiddenPeerIDs && it.id != matchID }) return null
            return ReversiNoticeText.updateMine
        }

    // MARK: 계산 칸

    /** 차단 거울만 거른 상대 목록. */
    val visibleUsers: List<ReversiUser>
        get() = if (hiddenPeerIDs.isEmpty()) users else users.filter { it.id !in hiddenPeerIDs }

    /**
     * 차단 거울을 거르고 **지금 내 판과 같은 id 를 뺀** 받은 신청(수락 뒤 늦게 온 옛 로비 응답이 되살리지 못하게). **시계를 읽지 않는다** — 만료는
     * 스토어 타이머가 [incoming] 에서 걷는다. 잠긴 빌드(§8-17 #1)에서는 비어 있다(접힌 줄은 [incomingFoldedNotice]).
     */
    val visibleIncomingInvites: List<ReversiInvite>
        get() {
            if (duelsLocked) return emptyList()
            val matchID = match?.id
            if (hiddenPeerIDs.isEmpty() && matchID == null) return incoming
            return incoming.filter { it.peer.id !in hiddenPeerIDs && it.id != matchID }
        }

    /** 배너·카드가 읽는 첫 신청. */
    val visibleIncoming: ReversiInvite? get() = visibleIncomingInvites.firstOrNull()

    /** 둘 수 있는 칸. 1:1 은 서버 `legal_moves`(내 차례만) · AI 판은 로컬 규칙(사람 차례만). */
    val legalTargets: Set<Int>
        get() {
            val current = match ?: return emptySet()
            if (!current.isMyTurn) return emptySet()
            if (current.isAI) return ReversiRules.legalMoves(current.board, current.myColor).toSet()
            return current.legalMoves.toSet()
        }

    /** 대국 중이면 확성기 배너를 미룬다(맥 배선 몫 — 폰은 화면으로만 가른다: GamesStore.isAnyMatchScreenVisible 머리말). */
    val defersMegaphoneBanner: Boolean get() = phase == ReversiPhase.playing

    /** 서버가 말해 준 유예(초). */
    val graceSeconds: Double get() = maxOf(0.0, graceMs.toDouble() / 1000)

    // MARK: 문 (조립 · 게임 탭 스토어가 채운다)

    var presentWindow: (() -> Unit)? = null
    var dismissWindow: (() -> Unit)? = null
    var requestAttention: (() -> Unit)? = null
    /** 새 받은 신청(처음 본 id 한 번). 잠긴 빌드에서는 부르지 않는다(§8-17 #1). */
    var onInviteArrived: ((ReversiInvite) -> Unit)? = null
    /** 창이 안 보일 때 판 시작·내 차례(키 id#move_count 로 한 번). */
    var onAttention: ((ReversiAttention) -> Unit)? = null
    /** 1:1 판이 끝났다(AI 판 제외) — 미션 새로 고침 꼬리. */
    var onMatchFinished: (() -> Unit)? = null

    // MARK: 내부 장부 (관찰 대상 아님)

    /** 이 스토어의 '지금'. 시험이 갈아 끼운다(기본은 호스트의 시계 — 구조 시험 R2). */
    var clock: () -> SwiftDate = { this.host?.now() ?: SwiftDate.fromReferenceDate(0.0) }
    /** 폴링 루프의 한 걸음(초). 주기 판정은 [pollTick] 이 하고 이 값은 그 판정을 얼마나 자주 묻는지다(시험은 재운다). */
    var pollStepSeconds: Double = 0.5
    /** 서버 시계 − 기기 시계(초). */
    var serverClockOffset: Double = 0.0
        private set
    private var hasServerClockOffset = false
    var resetGeneration: Int = 0
        private set
    /** 창이 가려졌다(폰은 앱이 background). **폴링·AI 시계만** 이 값을 본다. */
    var isWindowOccluded: Boolean = false
        internal set
    var stateInFlightID: String? = null
        private set
    private var pendingStateID: String? = null
    private var stateInFlight = false
    private var stateAgain = false
    private var lobbyInFlight = false
    /** 로비 조회가 도는 중에 또 불렸다 — 끝난 뒤 **한 번 더** 읽는다(앞 조회는 그 뒤에 생긴 신청·수락을 모른다). */
    private var lobbyAgain = false
    /** 마지막으로 "내 차례가 왔다" 를 본 (판 id#move_count). 같은 차례에 말풍선이 두 번 뜨지 않게 한다. */
    private var attentionKey: String? = null
    /** 서버가 말한 내 진행 중 대국 id(로비 `me.active_match_id`). 시험이 심는다. */
    var activeMatchID: String? = null
        internal set
    var seenInviteIDs: Set<String> = emptySet()
        private set
    /** 이 기기에서 이미 답한 받은 신청(수락·거절·끝남). 답보다 먼저 나간 로비 응답이 늦게 와도 되살리지 않는다. */
    var answeredInviteIDs: Set<String> = emptySet()
        private set
    /** [로비로] 로 접은 끝난 판. 늦게 온 그 판의 상태가 사용자를 결과 화면으로 끌고 가지 않게 한다. */
    var dismissedMatchIDs: Set<String> = emptySet()
        private set
    var pollTask: Job? = null
        private set
    private var pollToken = 0
    private var expiryTask: Job? = null
    var lastStateRequestAt: SwiftDate = distantPast
    var lastLobbyRequestAt: SwiftDate = distantPast
    var lastOutgoingRequestAt: SwiftDate = distantPast
    /** 허브 열기 계기의 마지막 조회 시각(스로틀). */
    var lastMenuLobbyAt: SwiftDate = distantPast
    /** 신호 재조회 직렬화(도는 중이면 뒤따르는 한 번으로 합친다). */
    var syncTask: Job? = null
        private set
    private var syncPendingTrailing = false
    /** 이 기기에서 보낸 신청을 새로 세울 때마다 오른다. 그보다 **먼저** 나간 로비 응답이 방금 보낸 신청을 지우지 않게 한다. */
    var outgoingRevision: Int = 0
        private set
    private var lobbyRequestOutgoingRevision = 0
    /** 쓰기 RPC 응답을 받을 때마다 오른다. 그보다 **먼저** 나간 로비 응답은 잔액·진행 판 id 를 덮지 않는다. */
    var writeRevision: Int = 0
        private set
    /** 서버가 말한 숫자(로비 응답이 덮는다 — 상수를 베끼지 않는다). */
    var inviteTTLSeconds: Double = 60.0
        private set
    var turnSeconds: Int = 30
        private set
    var graceMs: Long = 2_000L
        private set
    var autoAbandonStreak: Int = 3
        private set
    /** 지금 서 있는 패스 안내(다음 수가 오면 걷는다 — 그 밖의 안내는 건드리지 않는다). */
    private var passNotice: String? = null
    private var flipToken = 0
    private var flipTask: Job? = null

    /** 지금 AI 대국(로컬 판이 권위 — ReversiStoreAI.kt). [match] 가 이 id 를 들고 있는 동안만 산다. */
    var aiGame: ReversiAIGame? by mutableStateOf(null)
        internal set
    /** AI 갈래 장부(선택기·작업·세대). */
    val aiRuntime: ReversiAIRuntime = ReversiAIRuntime()
    /** 관전·순위 장부(요청 시각·in-flight·세대). */
    val watchRuntime: ReversiWatchRuntime = ReversiWatchRuntime()

    internal fun log(message: String) = host.notice(LOG_TAG, message)

    internal fun launch(block: suspend CoroutineScope.() -> Unit): Job = scope.launch(block = block)

    // MARK: - match 대입(Swift didSet)

    private fun matchDidChange(oldValue: ReversiMatchState?, newValue: ReversiMatchState?) {
        matchTransitionLine(oldValue, newValue)?.let(::log)
        // 1:1 판이 끝난 것을 **처음 본** 순간 한 번. AI 판은 부르지 않는다.
        if (matchJustFinished(oldValue, newValue) && newValue?.isAI == false) onMatchFinished?.invoke()
        // AI 판은 `match` 가 그 id 를 들고 있는 동안만 산다 — 1:1 판이 열리거나 판이 내려가면 버린다(1:1 이 이긴다).
        val game = aiGame
        if (game != null && newValue?.id != game.id) discardAIGame()
        // 내 판이 섰으면(끝난 판 포함) 관전은 내려간다. 세대를 올려 나가 있던 관전 응답도 함께 버린다.
        if (newValue != null && spectating != null) {
            spectating = null
            watchRuntime.bumpWatchGeneration()
        }
        // 판이 내려갔다 — 남의 관전자 수가 로비 화면에 남지 않게 0 으로 돌린다.
        if (newValue == null && spectatorCount != 0) spectatorCount = 0
        // 다른 판의 뒤집기 그림은 새 판 위에 남기지 않는다.
        val current = flip
        if (current != null && current.matchID != newValue?.id) clearFlip()
    }

    // MARK: - 창 (폰은 화면 수명 — GamesStore 가 부른다)

    /** 창을 띄우고 로비·판을 읽는다. [focusMatchID] 는 배너·말풍선에서 온 경로의 대상이다. */
    fun openWindow(focusMatchID: String?) {
        if (host?.session != null) {
            val focus = focusMatchID?.lowercase()
            // 곧 이어질 windowDidShow 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다.
            lastLobbyRequestAt = clock()
            launch {
                refreshLobby()
                val current = match
                if (!focus.isNullOrEmpty() && focus != current?.id) {
                    refreshMatch(focus)
                } else if (current != null && !current.isFinished && !current.isAI) {
                    refreshMatch(current.id)
                }
            }
        }
        presentWindow?.invoke()
    }

    /** 창이 실제로 보이기 시작했다. 폴링 시작 · 로비 재조회 · AI 시계 재개. */
    fun windowDidShow() {
        // 열린 채 가려진 창을 다시 부르는 길이면 가림 기록을 **그대로 둔다**(Swift 0.3.74 통합 수리 — 오목·체스·테트리스와 같다).
        val reshownWhileOccluded = isWindowVisible && isWindowOccluded
        if (!isWindowVisible) isWindowVisible = true
        if (!reshownWhileOccluded) isWindowOccluded = false
        resumeAIClockIfVisible()
        startPolling()
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastLobbyRequestAt) >= reloadDedupeSeconds) launch { refreshLobby() }
        val current = match
        if (current != null && !current.isFinished && !current.isAI && now.timeIntervalSince(lastStateRequestAt) >= reloadDedupeSeconds) {
            // 창이 안 보이는 동안 시계는 서버에서 흘렀다 — 올라온 순간 한 번 당겨 마감을 새로 받는다(⑨).
            launch { refreshMatch(current.id) }
        }
        spectatorWindowDidShow(now)
    }

    /** 창이 가려졌다·닫혔다. 폴링만 멈춘다 — **1:1 대국은 계속된다**(시간은 서버에서 흐른다). AI 판은 사람 시계를 멈춘다. */
    fun windowDidHide() {
        if (isWindowVisible) isWindowVisible = false
        isWindowOccluded = false
        clearFlip()
        stopPolling()
        pauseAIClock()
        // 끝난 판을 관전한 채 닫았다 = 그 판에서 나간 것이다. 진행 중인 관전은 남긴다.
        if (spectating?.isFinished == true) stopWatching()
    }

    /** 창을 **정말 닫았다**. 관전을 내리고 끝난 내 판을 접는다. 진행 중인 판은 건드리지 않는다 — 닫기는 기권이 아니다. */
    fun windowDidClose() {
        if (spectating != null) stopWatching()
        clearFlip()
        foldFinishedMatch()
    }

    /** 창의 가림 상태가 바뀌었다(폰: 앱이 background ↔ active). **폴링·AI 시계만** 멈추고 되살린다. */
    fun windowOcclusionDidChange(visible: Boolean) {
        isWindowOccluded = !visible
        if (visible) {
            resumeAIClockIfVisible()
            startPolling()
        } else {
            clearFlip()
            pauseAIClock()
            stopPolling()
        }
    }

    // MARK: - 조회

    /** 로비를 읽는다. 도는 중에 또 불리면 끝난 뒤 **한 번 더** 읽는다(`lobbyAgain`). 합친 한 바퀴에는 진행 판 꼬리까지 들어간다. */
    suspend fun refreshLobby() {
        if (host?.session == null) return
        if (lobbyInFlight) {
            lobbyAgain = true
            return
        }
        lobbyInFlight = true
        val generation = resetGeneration
        try {
            do {
                lobbyAgain = false
                lastLobbyRequestAt = clock()
                val revision = outgoingRevision
                val writes = writeRevision
                val result = perform { service, token -> service.reversiLobby(token) } ?: return
                when (result) {
                    is CallResult.Success -> {
                        val response = result.value
                        lobbyRequestOutgoingRevision = revision
                        applyLobby(response, predatesWrite = writes != writeRevision)
                        // 서버가 진행 중이라 말하는 판을 들고 있지 않다(다른 기기에서 수락 · 재시작) — 그 판을 읽어 세운다.
                        // 쓰기보다 먼저 나간 응답이라 `activeMatchID` 를 안 덮었어도, 그 순간 판이 서 있었다는 사실은 쓴다(VR-01).
                        val active = activeMatchID ?: response.me?.activeMatchId?.lowercase()
                        if (response.status == ReversiRPCStatus.ok && active != null && (match?.id != active || match?.isFinished == true)) {
                            refreshMatch(active)
                        }
                    }
                    is CallResult.Failure -> {
                        if (isSchemaMissing(result.error)) {
                            log("lobby unavailable — reversi functions missing on server")
                            noteServerMissing()
                        } else {
                            log("lobby request failed")
                        }
                        if (!lobbyLoadFailed) lobbyLoadFailed = true
                    }
                }
            } while (lobbyAgain && generation == resetGeneration)
        } finally {
            if (generation == resetGeneration) lobbyInFlight = false
        }
    }

    /** 로비 응답을 화면 상태로 옮긴다(받은 신청은 통째로 갈아 끼운다). 시험이 픽스처 원문을 이 문으로 넣는다. */
    fun applyLobby(response: ReversiLobbyResponse) = applyLobby(response, predatesWrite = false)

    /**
     * [predatesWrite] — 이 응답은 그 뒤에 받은 쓰기 응답보다 **먼저** 나갔다(`writeRevision`). 잔액·진행 판 id 는 쓰기 응답이 더 새 사실이라
     * 덮지 않는다. 나머지(사람·대결 중·신청)는 그대로 옮긴다 — 신청은 `answeredInviteIDs`·`outgoingRevision` 이 따로 지킨다.
     */
    private fun applyLobby(response: ReversiLobbyResponse, predatesWrite: Boolean) {
        if (response.status != ReversiRPCStatus.ok) {
            log("lobby refused status=${response.status.rawValue}")
            when (response.status) {
                ReversiRPCStatus.unsupportedClient -> noteUpdateRequired()
                ReversiRPCStatus.unauthorized -> setNotice(ReversiNoticeText.signInAgain)
                else -> Unit
            }
            if (!lobbyLoadFailed) lobbyLoadFailed = true
            return
        }
        noteServerNow(response.serverNowMs)
        if (availability != ReversiAvailability.available) availability = ReversiAvailability.available
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (!hasLoadedLobby) hasLoadedLobby = true
        response.turnSeconds?.let { if (it > 0) turnSeconds = it.toInt() }
        response.turnGraceSeconds?.let { if (it >= 0) graceMs = it * 1000 }
        response.inviteTtlSeconds?.let { if (it > 0) inviteTTLSeconds = it.toDouble() }
        response.autoAbandonStreak?.let { if (it > 0) autoAbandonStreak = it.toInt() }
        val me = response.me
        if (me != null) {
            if (!predatesWrite) applyRuby(me.rubyBalance)
            val fresh = ReversiRecord(wins = (me.wins ?: 0).toInt(), losses = (me.losses ?: 0).toInt(), draws = (me.draws ?: 0).toInt())
            if (record != fresh) record = fresh
            // ★ 신청을 옮기기 **전에** 적는다 — 보낸 신청이 판으로 이어졌는지(becameMatch)를 이 값으로 가른다.
            if (!predatesWrite) activeMatchID = me.activeMatchId?.lowercase()
        }
        response.users?.let { rows ->
            val mapped = sortedForLobby(rows.mapNotNull(::user))
            if (users != mapped) users = mapped
        }
        // **서버 순서 그대로**. 키가 아예 없으면(옛 서버) 들고 있던 목록을 지우지 않는다.
        response.matches?.let { rows ->
            val live = rows.mapNotNull(::liveMatch)
            if (liveMatches != live) liveMatches = live
        }
        applyLobbyInvites(me)
    }

    /** 로비 `me` 의 신청 둘(받은 것 배열 · 보낸 것 하나)을 화면 값으로 옮긴다. */
    private fun applyLobbyInvites(me: ReversiLobbyMe?) {
        // 이 응답이 읽힌 순간 서 있던 진행 판 — `predatesWrite` 라 `activeMatchID` 에 안 옮겼어도 "보낸 신청이 판이 됐다"는 판정엔 쓴다(VR-01).
        val respondedActive = me?.activeMatchId?.lowercase()
        // 받은 신청 — 서버 목록이 권위다(서버가 만료·숨김·차단을 이미 걸렀다). 이 기기가 이미 답한 신청만 뺀다.
        val rows = me?.incoming
        if (rows != null) {
            val fresh = ArrayList<ReversiInvite>()
            for (row in rows) {
                val invite = invite(row, row.from) ?: continue
                if (invite.id in answeredInviteIDs || fresh.any { it.id == invite.id }) continue
                fresh += steadyInvite(invite, incoming.firstOrNull { it.id == invite.id })
            }
            if (incoming != fresh) incoming = fresh.toList()
            for (invite in fresh) {
                if (invite.id in seenInviteIDs || invite.id == match?.id) continue
                seenInviteIDs = seenInviteIDs + invite.id
                if (invite.peer.id in hiddenPeerIDs) continue
                // §8-17 #1: 잠긴 빌드는 배너를 세우지 않는다(본 것으로만 적는다).
                if (!duelsLocked) onInviteArrived?.invoke(invite)
            }
        } else if (me != null && incoming.isNotEmpty()) {
            incoming = emptyList()
        }

        // 보낸 신청.
        val serverOutgoing: ReversiOutgoing? = me?.outgoing?.let { row ->
            invite(row, row.to)?.let { ReversiOutgoing(it.id, it.peer, it.stake, it.expiresAt) }
        }
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        val predatesOutgoing = lobbyRequestOutgoingRevision < outgoingRevision
        val gone = outgoing
        if (gone != null && serverOutgoing?.id != gone.id && !predatesOutgoing) {
            // 판으로 이어졌으면(= 수락) 거절 안내를 하지 않는다 — 진행 중 판이 있으면 서버가 내 다른 신청을 거둔 것이다.
            val becameMatch = gone.id == activeMatchID || gone.id == match?.id || gone.id == respondedActive
            if (!becameMatch) {
                setNotice(if (gone.expiresAt > clock()) ReversiNoticeText.inviteDeclined else ReversiNoticeText.inviteTimedOut)
            }
            outgoing = null
        }
        // 방금 세운 신청보다 먼저 나간 응답은 **다른** 신청으로 덮지 않는다.
        if (serverOutgoing != null && serverOutgoing.id != match?.id &&
            (!predatesOutgoing || outgoing == null || outgoing?.id == serverOutgoing.id)
        ) {
            val steady = steadyOutgoing(serverOutgoing, outgoing)
            if (outgoing != steady) outgoing = steady
        }
        scheduleInviteExpiry()
    }

    suspend fun refreshMatch() {
        refreshMatch(match?.id ?: activeMatchID)
    }

    /**
     * 한 판(또는 신청)의 상태를 읽는다. 같은 판을 들고 있으면 `p_since_seq` 로 **새 수만** 받고, 수 번호가 이어지지 않으면 처음부터 한 번 더
     * 받는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합치고, **다른 판** id 는 기억했다가 지금 판이 끝난 뒤 한 번 읽는다.
     */
    suspend fun refreshMatch(id: String?) {
        // AI 판 id 는 서버에 없다 — 어느 경로로 와도 **여기서** 막는다(열기·로비·폴링·신호가 전부 이 문을 지난다).
        val requested = id?.lowercase()
        if (requested.isNullOrEmpty() || ReversiAIGame.isAIMatchID(requested) || host?.session == null) return
        if (stateInFlight) {
            if (requested == stateInFlightID) stateAgain = true else pendingStateID = requested
            return
        }
        stateInFlight = true
        val generation = resetGeneration
        var nextID: String? = requested
        while (nextID != null) {
            val matchID: String = nextID
            nextID = null
            stateInFlightID = matchID
            var forceFull = false
            do {
                stateAgain = false
                val current = match
                val since = if (!forceFull && current?.id == matchID) current.moveCount else 0
                forceFull = false
                lastStateRequestAt = clock()
                if (outgoing?.id == matchID) lastOutgoingRequestAt = lastStateRequestAt
                val result = perform { service, token -> service.reversiState(token, matchID, since.toLong()) }
                if (generation != resetGeneration) return
                when (result) {
                    is CallResult.Success -> {
                        val response = result.value
                        when (response.status) {
                            ReversiRPCStatus.ok -> {
                                val state = response.state
                                if (state != null && applyState(state, since) == StateApplyOutcome.needsFull && since > 0) {
                                    forceFull = true
                                    stateAgain = true
                                }
                            }
                            ReversiRPCStatus.notFound -> dropMatchOrInvite(matchID)
                            ReversiRPCStatus.unsupportedClient -> noteUpdateRequired()
                            ReversiRPCStatus.unauthorized -> setNotice(ReversiNoticeText.signInAgain)
                            else -> log("state refused status=${response.status.rawValue}")
                        }
                    }
                    is CallResult.Failure -> if (isSchemaMissing(result.error)) noteServerMissing()
                    null -> Unit
                }
            } while (stateAgain)
            val pending = pendingStateID
            if (pending != null) {
                pendingStateID = null
                nextID = pending
            }
        }
        stateInFlightID = null
        stateInFlight = false
    }

    // MARK: 픽스처 문 — 시험은 서버 픽스처 원문을 이 두 문으로 넣는다

    enum class StateApplyOutcome { applied, needsFull, ignored }

    /**
     * 서버 state 를 화면 상태로 옮긴다. **대국과 신청을 한 경로로 가른다**: `pending` 은 신청, `active`/`finished` 는 판, 그 밖(declined·
     * cancelled·expired)은 둘 다 아니다. 관전 모양(내 색 없음)은 무시한다 — 관전은 `applyWatch` 하나다.
     *
     * 쓰기 RPC 응답(state 전체)은 `requestedSince = 0` 으로 다시 짓고, 아니면 seq 로 이어 붙이며 틈이 보이면 [StateApplyOutcome.needsFull].
     * 판 자체는 서버 64자 문자열이 권위라 기록에 구멍이 나도 판은 맞다 — 구멍 난 기록을 그리지 않을 뿐이다.
     */
    fun applyState(payload: ReversiStatePayload, requestedSince: Int = 0): StateApplyOutcome {
        val row = payload.match ?: return StateApplyOutcome.ignored
        val id = row.id?.lowercase()
        if (id.isNullOrEmpty()) return StateApplyOutcome.ignored
        val status = row.matchStatus
        when (status) {
            ReversiMatchStatus.pending, ReversiMatchStatus.declined, ReversiMatchStatus.cancelled, ReversiMatchStatus.expired ->
                // ④ 같은 id 를 판(진행·끝남)으로 들고 있거나 접었다 — 신청 단계의 응답은 그 판보다 먼저 읽힌 옛 스냅숏이다.
                if (match?.id == id || id in dismissedMatchIDs) return StateApplyOutcome.ignored
            ReversiMatchStatus.active, ReversiMatchStatus.finished, ReversiMatchStatus.unknown -> Unit
        }
        when (status) {
            ReversiMatchStatus.pending -> {
                noteServerNow(payload.serverNowMs)
                applyRuby(payload.rubyBalance)
                applyInvite(row, payload, id)
                return StateApplyOutcome.applied
            }
            ReversiMatchStatus.active, ReversiMatchStatus.finished -> Unit
            ReversiMatchStatus.declined, ReversiMatchStatus.cancelled, ReversiMatchStatus.expired -> {
                noteServerNow(payload.serverNowMs)
                applyRuby(payload.rubyBalance)
                // 시작하지 못하고 끝난 신청 — 판도 아니고 살아 있는 신청도 아니다.
                dropMatchOrInvite(id, if (status == ReversiMatchStatus.expired) ReversiNoticeText.inviteTimedOut else ReversiNoticeText.inviteDeclined)
                return StateApplyOutcome.applied
            }
            ReversiMatchStatus.unknown -> {
                log("state with unknown status ignored")
                return StateApplyOutcome.ignored
            }
        }

        val isFinished = status == ReversiMatchStatus.finished
        // ④ 접은 끝난 판 — 늦게 온 그 판의 상태가 결과 화면을 되살리지 않는다.
        if (isFinished && id in dismissedMatchIDs && match?.id != id) return StateApplyOutcome.ignored
        // ④ 다른 판을 두는 중인데 끝난 판 응답이 왔다 — 지난 판의 늦은 응답이다(두던 판을 지우지 않는다).
        val held = match
        if (isFinished && held != null && held.id != id && !held.isFinished) return StateApplyOutcome.ignored

        // 관전 모양(내 색 없음)은 대국 화면으로 옮기지 않는다. 흑·백 uuid 로 내 색을 지어내지 않는다.
        val myColor = payload.myColor ?: return StateApplyOutcome.ignored

        val base = if (held?.id == id) held else null
        val serverCount = row.moveCount
        // ④ 같은 판을 진행 중으로 들고 있는데 **수 번호가 줄어든** 응답은 착수보다 먼저 읽힌 옛 스냅숏이다.
        if (base != null && !base.isFinished && !isFinished && serverCount != null && serverCount < base.moveCount) return StateApplyOutcome.ignored
        // ④ 같은 판을 이미 끝남으로 들고 있으면 진행 중 응답은 전부 끝나기 전에 읽힌 옛 스냅숏이다.
        if (base != null && base.isFinished && !isFinished) return StateApplyOutcome.ignored

        val records = (payload.moves ?: emptyList()).filter { it.seq >= 1 }.sortedBy { it.seq }
        val rebuild = base == null || records.firstOrNull()?.seq == 1 || requestedSince == 0
        val merged = if (rebuild) ArrayList() else ArrayList(base?.plies ?: emptyList())
        var applied = if (rebuild) 0 else (base?.moveCount ?: 0)
        for (record in records) {
            if (record.seq <= applied) continue
            if (record.seq != applied + 1 && !rebuild) return StateApplyOutcome.needsFull
            merged += record
            applied = record.seq
        }
        val moveCount = serverCount ?: applied
        if (moveCount != applied && !rebuild) return StateApplyOutcome.needsFull

        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance)

        val board = row.board ?: base?.board ?: com.yehsung.aingcheck.core.wire.games.ReversiBoard.start
        val turn = if (isFinished) null else row.turn
        val turnStartedAt = deviceDate(row.turnStartedMs)
        val deadline = if (isFinished) null else (deviceDate(row.deadlineMs) ?: turnStartedAt?.addingTimeInterval(turnSeconds.toDouble()))
        // **서버가 준 것만** 쓴다(⑦). 상대 차례·끝난 판은 [] 라 착수가 전부 막힌다.
        val legal = if (isFinished || turn != myColor) emptyList() else (payload.legalMoves ?: emptyList()).filter { it in 0 until 64 }.distinct().sorted()
        val blackID = row.black?.lowercase()
        val whiteID = row.white?.lowercase()
        val opponentID = if (myColor == ReversiColor.black) whiteID else blackID
        val opponent = playerUser(payload.opponent, inMatch = !isFinished)
            ?: base?.opponent
            ?: users.firstOrNull { it.id == opponentID }
            ?: ReversiUser(id = opponentID ?: "", displayName = "", inMatch = !isFinished)
        val blackUser = playerUser(payload.blackUser, inMatch = !isFinished) ?: base?.blackUser
        val whiteUser = playerUser(payload.whiteUser, inMatch = !isFinished) ?: base?.whiteUser
        val result = row.result
        var winner: ReversiColor? = result?.winner
        if (winner == null) {
            val winnerID = row.winner?.lowercase()
            if (winnerID != null) winner = if (winnerID == blackID) ReversiColor.black else if (winnerID == whiteID) ReversiColor.white else null
        }
        val scoreRow = row.score
        val score: ReversiScore? =
            if (scoreRow?.black != null && scoreRow.white != null && result != null) ReversiScore(scoreRow.black!!, scoreRow.white!!, result) else null
        val myStreak = (payload.myAutoStreak ?: (if (myColor == ReversiColor.black) payload.blackAutoStreak else payload.whiteAutoStreak) ?: 0L).toInt()
        val opponentStreak = (payload.opponentAutoStreak ?: (if (myColor == ReversiColor.black) payload.whiteAutoStreak else payload.blackAutoStreak) ?: 0L).toInt()

        val next = ReversiMatchState(
            id = id, isAI = false, status = status, stake = (row.stake ?: base?.stake?.toLong() ?: 0L).toInt(), myColor = myColor,
            opponent = opponent, blackUser = blackUser, whiteUser = whiteUser, board = board, moveCount = moveCount,
            turn = turn, turnStartedAt = turnStartedAt, deadline = deadline, legalMoves = legal, plies = merged.toList(),
            lastStoneIdx = merged.lastOrNull { it.kind == ReversiPly.Kind.stone }?.idx,
            autoStones = merged.mapNotNullTo(LinkedHashSet()) { if (it.kind == ReversiPly.Kind.stone && it.auto) it.idx else null },
            counts = row.discs ?: board.counts, score = score, result = if (isFinished) result else null,
            endReason = if (isFinished) row.endReason else null, winner = if (isFinished) winner else null,
            myAutoStreak = myStreak, opponentAutoStreak = opponentStreak,
            autoAbandonStreak = payload.autoAbandonStreak?.toInt() ?: autoAbandonStreak,
            watchers = maxOf(0L, payload.watchers ?: 0L).toInt(),
        )

        val justFinished = isFinished && base?.isFinished == false
        val previous = match
        // 말풍선 문은 **보이고 안 가려진** 창만 닫는다 — 가려진 창은 화면이 말하지 못하고 폴링도 멈춰 있다.
        val windowWasVisible = isWindowVisible && !isWindowOccluded
        // 이 판이 신청이었으면 카드를 걷는다(수락된 쪽·내가 수락한 쪽 모두).
        if (incoming.any { it.id == id }) {
            incoming = incoming.filter { it.id != id }
            scheduleInviteExpiry()
        }
        if (outgoing?.id == id) {
            outgoing = null
            scheduleInviteExpiry()
        }
        if (match != next) match = next
        // 내 판 관전자 수 — **`match` 대입 뒤**에 세운다(그 대입이 판이 바뀌는 길목에서 0 으로 되돌린다).
        if (spectatorCount != next.watchers) spectatorCount = next.watchers
        noteBoardProgress(previous, next)
        val nextPhase = if (isFinished) ReversiPhase.result else ReversiPhase.playing
        if (phase != nextPhase) phase = nextPhase
        activeMatchID = if (isFinished) null else id
        if (!isFinished) {
            // 새 판이 열렸다 — 로비에서 남긴 안내("신청을 보냈어요")가 대국 상태줄을 가리지 않게 한다.
            if (previous?.id != id || previous.isFinished) setNotice(null)
            noteMatchProgress(previous, next, windowWasVisible)
        }
        if (justFinished) {
            // 전적은 로비 응답에만 있다. 끝난 순간 한 번 다시 읽어 결과 화면 뒤 로비가 옛 전적을 보이지 않게 한다.
            launch { refreshLobby() }
            noteOwnMatchFinishedForRanking()
        }
        return StateApplyOutcome.applied
    }

    // MARK: - 동작

    /** [selectedStake] 로 신청한다. 서버는 근무 조건이 없다 — 근무를 보고 미리 막지 않는다. */
    suspend fun challenge(userID: String) {
        if (isBusy || host?.session == null) return
        // §8-17 #1: 깃발이 꺼진 빌드는 신청 RPC 를 한 건도 내지 않는다.
        if (duelsLocked) {
            setNotice(ReversiNoticeText.updateMine)
            return
        }
        val target = userID.lowercase()
        val stake = selectedStake.rawValue
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.reversiChallenge(token, target, stake.toLong()) }) {
                null -> return
                is CallResult.Failure -> noteActionFailure(result.error)
                is CallResult.Success -> {
                    val response = result.value
                    writeRevision += 1 // 이 응답보다 먼저 나간 로비는 잔액·진행 판 id 를 덮지 않는다
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    if (response.status == ReversiRPCStatus.unsupportedClient) {
                        noteUpdateRequired()
                        return
                    }
                    setNotice(ReversiNoticeText.challenge(response.status, response.need, response.have))
                    if (response.status != ReversiRPCStatus.ok) log("challenge refused status=${response.status.rawValue}")
                    when (response.status) {
                        ReversiRPCStatus.ok -> {
                            val id = response.matchId?.lowercase()
                            if (id.isNullOrEmpty()) return
                            val peer = users.firstOrNull { it.id == target } ?: ReversiUser(id = target, displayName = "")
                            val expiresAt = deviceDate(response.inviteExpiresMs) ?: clock().addingTimeInterval(inviteTTLSeconds)
                            outgoingRevision += 1
                            outgoing = ReversiOutgoing(id, peer, stake, expiresAt)
                            lastOutgoingRequestAt = clock()
                            scheduleInviteExpiry()
                        }
                        // 목록의 칩이 틀렸다는 뜻이다 — 다시 읽어 행을 사실에 맞춘다.
                        ReversiRPCStatus.alreadyPending, ReversiRPCStatus.busy, ReversiRPCStatus.targetBusy,
                        ReversiRPCStatus.targetOutdated, ReversiRPCStatus.targetFocused -> refreshLobby()
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
            when (val result = perform { service, token -> service.reversiCancel(token, id) }) {
                null -> return
                is CallResult.Failure -> noteActionFailure(result.error)
                is CallResult.Success -> {
                    val response = result.value
                    writeRevision += 1
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    if (response.status == ReversiRPCStatus.unsupportedClient) {
                        noteUpdateRequired()
                        return
                    }
                    setNotice(ReversiNoticeText.cancel(response.status))
                    when (response.status) {
                        ReversiRPCStatus.ok, ReversiRPCStatus.notFound, ReversiRPCStatus.notPending, ReversiRPCStatus.expired -> {
                            if (outgoing?.id == id) {
                                outgoing = null
                                scheduleInviteExpiry()
                            }
                            // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 실려 온 판이 진행 중이면 그 판을 세운다.
                            if (response.status == ReversiRPCStatus.notPending) {
                                val state = response.state
                                if (state != null && state.match?.matchStatus == ReversiMatchStatus.active) applyState(state) else refreshLobby()
                            }
                        }
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    suspend fun respond(inviteID: String, accept: Boolean) {
        if (isBusy || host?.session == null) return
        // §8-17 #1: 깃발이 꺼진 빌드는 수락 RPC 를 내지 않는다(거절은 루비가 움직이지 않는 답이라 막지 않는다).
        if (accept && duelsLocked) {
            setNotice(ReversiNoticeText.updateMine)
            return
        }
        val id = inviteID.lowercase()
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.reversiRespond(token, id, accept) }) {
                null -> return
                is CallResult.Failure -> noteActionFailure(result.error)
                is CallResult.Success -> {
                    val response = result.value
                    writeRevision += 1
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    if (response.status == ReversiRPCStatus.unsupportedClient) {
                        noteUpdateRequired()
                        return
                    }
                    setNotice(ReversiNoticeText.respond(accept, response.status, response.side, response.need, response.have))
                    if (response.status != ReversiRPCStatus.ok) log("respond refused status=${response.status.rawValue}")
                    when (response.status) {
                        ReversiRPCStatus.ok -> {
                            forgetIncoming(id)
                            if (!accept || response.accepted == false) return
                            // 수락하는 순간 서버가 두 참가자의 **다른 대기 신청을 전부 거둔다**.
                            if (outgoing != null) {
                                outgoing = null
                                scheduleInviteExpiry()
                            }
                            val state = response.state
                            if (state != null) applyState(state) else refreshMatch(id)
                            if (match?.id != id && !isWindowVisible) presentWindow?.invoke()
                        }
                        ReversiRPCStatus.notPending -> {
                            forgetIncoming(id)
                            // 다른 기기(같은 계정)가 먼저 수락했으면 판이 실려 온다.
                            val state = response.state
                            if (state != null && state.match?.matchStatus == ReversiMatchStatus.active) applyState(state)
                        }
                        ReversiRPCStatus.notFound, ReversiRPCStatus.expired, ReversiRPCStatus.invalid -> forgetIncoming(id)
                        // busy · target_busy · insufficient — 신청은 아직 살아 있다(나중에 받을 수 있다).
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /** 한 칸에 둔다. 1:1 은 서버, AI 판은 로컬. **[legalTargets] 밖이면 요청 없이 문구만**(합법 수는 서버 목록만, ⑦). */
    suspend fun place(idx: Int) {
        if (isBusy) {
            setNotice(ReversiNoticeText.sending)
            return
        }
        val current = match ?: return
        if (current.isFinished) return
        if (!current.isMyTurn) {
            setNotice(ReversiNoticeText.notYourTurn)
            return
        }
        if (idx !in legalTargets) {
            setNotice(ReversiNoticeText.illegal(localRefusal(current.board, current.myColor, idx)))
            return
        }
        // AI 판은 위 거절 가드를 **같이** 지난 뒤 로컬 판에 둔다 — 서버로는 안 나간다(로그인 여부도 안 본다).
        if (current.isAI) {
            placeInAIMatch(idx)
            return
        }
        if (host?.session == null) {
            setNotice(ReversiNoticeText.signInAgain)
            return
        }
        val id = current.id
        val expected = current.moveCount
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.reversiMove(token, id, expected.toLong(), idx.toLong()) }) {
                null -> return
                is CallResult.Failure -> noteActionFailure(result.error)
                is CallResult.Success -> {
                    val response = result.value
                    writeRevision += 1
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    if (response.status == ReversiRPCStatus.unsupportedClient) {
                        noteUpdateRequired()
                        return
                    }
                    setNotice(ReversiNoticeText.move(response.status, response.illegalReason))
                    if (response.status != ReversiRPCStatus.ok) log("move refused status=${response.status.rawValue}")
                    if (response.status == ReversiRPCStatus.notFound) {
                        if (match?.id == id) clearMatch()
                        return
                    }
                    // 쓰기 응답의 state 는 수 기록 전체다(§3.4) — 처음부터 다시 짓는다. stale 도 이 한 줄로 맞춘다(문구 없음).
                    val state = response.state
                    if (state != null) {
                        if (applyState(state, requestedSince = 0) == StateApplyOutcome.needsFull) refreshMatch(id)
                    } else {
                        when (response.status) {
                            ReversiRPCStatus.ok, ReversiRPCStatus.stale, ReversiRPCStatus.notYourTurn, ReversiRPCStatus.notActive,
                            ReversiRPCStatus.illegal, ReversiRPCStatus.autoPlaced -> refreshMatch(id) // 상태를 안 실어 준 응답(모르는 모양은 되묻는다)
                            else -> Unit
                        }
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    suspend fun resign() {
        val held = match
        if (held != null && held.isAI) {
            resignAIMatch()
            return
        }
        if (isBusy || held == null || held.isFinished || host?.session == null) return
        val id = held.id
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.reversiResign(token, id) }) {
                null -> return
                is CallResult.Failure -> noteActionFailure(result.error)
                is CallResult.Success -> {
                    val response = result.value
                    writeRevision += 1
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    if (response.status == ReversiRPCStatus.unsupportedClient) {
                        noteUpdateRequired()
                        return
                    }
                    setNotice(ReversiNoticeText.resign(response.status))
                    if (response.status == ReversiRPCStatus.notFound) {
                        if (match?.id == id) clearMatch()
                        return
                    }
                    val state = response.state
                    if (state != null) applyState(state) else refreshMatch(id)
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /** 결과 화면 [로비로]. **진행 중인 판에서는 아무것도 안 한다** — 빠져나가는 길은 기권뿐이다. */
    fun backToLobby() {
        val wasAI = match?.isAI == true
        if (!foldFinishedMatch()) return
        if (wasAI || host?.session == null) return
        launch {
            refreshLobby()
            refreshRanking()
        }
    }

    /** 끝난 판을 내리고 화면을 로비로 돌린다. 요청은 쏘지 않는다. 끝난 판을 들고 있지 않으면 false. */
    internal fun foldFinishedMatch(): Boolean {
        val current = match ?: return false
        if (!current.isFinished) return false
        if (!current.isAI) dismissedMatchIDs = dismissedMatchIDs + current.id
        match = null // 대입이 AI 판을 버린다
        if (phase != ReversiPhase.lobby) phase = ReversiPhase.lobby
        clearFlip()
        setNotice(null)
        return true
    }

    /** 지금 차례(내 것이든 상대 것이든)의 남은 초 — 표시값 30초 기준, 서버 유예 미포함. 마감이 없으면 null. 잎이 `now` 를 넘겨 부르는 **순수 계산**이다(⑥). */
    fun remainingSeconds(now: SwiftDate): Double? {
        val current = match ?: return null
        if (current.isFinished) return null
        val deadline = current.deadline ?: return null
        return maxOf(0.0, deadline.timeIntervalSince(now))
    }

    // MARK: - 신호 · 계기 (화면 밖에서 아는 유일한 길)

    /** 실시간 초인종(`'reversi'` → [com.yehsung.aingcheck.core.net.realtime.RealtimeEffect.ReversiSignal]). 직렬화된 재조회. */
    fun handleSignal() {
        requestSync()
    }

    fun requestSync() {
        if (host?.session == null) return
        if (syncTask != null) {
            syncPendingTrailing = true
            return
        }
        val generation = resetGeneration
        syncTask = launch {
            do {
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 조회가 도는 동안 도착한 신호를 지운다.
                syncPendingTrailing = false
                syncOnce()
            } while (syncPendingTrailing && generation == resetGeneration)
            if (generation == resetGeneration) syncTask = null
        }
    }

    /** 신호 한 번의 조회: 진행 중 1:1 판이 있으면 그 판, 아니면 로비(받은·보낸 신청 + 진행 중 판 id). AI 판 동안 온 신호는 로비로 본다. */
    suspend fun syncOnce() {
        val current = match
        if (current != null && !current.isFinished && !current.isAI) refreshMatch(current.id) else refreshLobby()
    }

    /** 조인 직후·깨어남의 따라잡기: 로비 한 번(+ 그 응답이 가리키는 판). 진행 중 판만 읽으면 그 사이 온 신청을 모른다. */
    suspend fun catchUp() {
        refreshLobby()
    }

    fun realtimeDidJoin() {
        if (host?.session == null) return
        launch { catchUp() }
    }

    fun systemDidWake() {
        if (host?.session == null) return
        launch { catchUp() }
    }

    /** 허브 열림·앱 깨어남(30초 스로틀). 탭 배지·카드 칩의 신선도가 이 계기와 소켓 신호에 달려 있다. */
    fun refreshLobbyIfStale() {
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastMenuLobbyAt) < menuLobbyThrottleSeconds) return
        lastMenuLobbyAt = now
        launch { refreshLobby() }
    }

    // MARK: - 폴링 (창이 보일 때만)

    fun startPolling() {
        if (pollTask != null || !isWindowVisible || isWindowOccluded) return
        pollToken += 1
        val token = pollToken
        pollTask = launch {
            while (true) {
                delay((pollStepSeconds * 1000).toLong())
                if (!isActive || token != pollToken || !isWindowVisible || isWindowOccluded) {
                    if (token == pollToken) pollTask = null
                    return@launch
                }
                pollTick(clock())
            }
        }
    }

    fun stopPolling() {
        pollToken += 1
        pollTask?.cancel()
        pollTask = null
    }

    /**
     * 폴링 한 걸음의 조회를 **폴링 작업의 취소 밖에서** 돌리고 끝날 때까지 기다린다. 화면을 떠나는(가림) 순간 `stopPolling` 의 취소가 날던 조회에
     * 닿으면, 그 조회에 합쳐진 초인종 조회(`stateAgain`·`lobbyAgain`)까지 같이 죽는다. 폴링은 멈추고 날던 조회만 끝까지 간다(로그아웃은 세대 가드가
     * 버린다). 날던 조회가 끝난 뒤 남은 걸음은 걸음 사이 가드가 막는다(Swift 적대 재검증 VR-04).
     */
    private suspend fun outsidePolling(body: suspend () -> Unit) {
        scope.launch { body() }.join()
    }

    /**
     * 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다**(③).
     *  · 진행 중 1:1 판이 상대 차례거나 내 마감 + 유예가 지났으면 [statePollSeconds] 마다 상태(서버가 자동 착수를 정산한다)
     *  · 보낸 신청이 있으면 5초마다 그 판의 상태 · 로비를 보고 있으면 30초마다 목록 · 관전 2초 / 순위 60초
     * **분기 사이사이 창 보임 · 가림 · 취소를 다시 본다** — 기다리는 중에 화면이 내려가거나 가려질 수 있다.
     */
    suspend fun pollTick(now: SwiftDate) {
        if (!isWindowVisible || isWindowOccluded || host?.session == null) return
        val current = match
        if (current != null && !current.isFinished && !current.isAI) {
            val waiting = !current.isMyTurn
            val overdue = current.deadline?.let { now >= it.addingTimeInterval(graceSeconds) } ?: false
            if (waiting || overdue) {
                val subscribed = host?.realtimeState?.isSubscribed ?: false
                if (now.timeIntervalSince(lastStateRequestAt) >= statePollSeconds(subscribed, current.deadline, now)) {
                    val id = current.id
                    outsidePolling { refreshMatch(id) }
                }
            }
        }
        if (!stillPolling()) return
        val sent = outgoing
        if (sent != null && now.timeIntervalSince(lastOutgoingRequestAt) >= outgoingPollSeconds) {
            val id = sent.id
            outsidePolling { refreshMatch(id) }
        }
        if (!stillPolling()) return
        if (phase == ReversiPhase.lobby && now.timeIntervalSince(lastLobbyRequestAt) >= lobbyPollSeconds) outsidePolling { refreshLobby() }
        if (!stillPolling()) return
        pollSpectatorFeatures(now)
    }

    private suspend fun stillPolling(): Boolean = isWindowVisible && !isWindowOccluded && currentCoroutineContext().isActive

    // MARK: - 리셋

    /** 로그아웃·계정 전환. 세대를 올리고 화면 상태를 처음으로 돌린다 — 남기면 다음 사람이 앞 사람의 판·신청·루비를 본다. 배선 값(스위치·문·시계)은 건드리지 않는다. */
    fun reset() {
        resetGeneration += 1
        stopPolling()
        discardAIGame()
        clearFlip()
        expiryTask?.cancel()
        expiryTask = null
        // 신호 재조회도 끊는다 — 앞 계정의 따라잡기가 다음 사람의 화면에 신청·판을 세우면 안 된다.
        syncTask?.cancel()
        syncTask = null
        syncPendingTrailing = false
        stateInFlight = false
        stateAgain = false
        lobbyInFlight = false
        lobbyAgain = false
        stateInFlightID = null
        pendingStateID = null
        if (phase != ReversiPhase.lobby) phase = ReversiPhase.lobby
        if (availability != ReversiAvailability.available) availability = ReversiAvailability.available
        if (users.isNotEmpty()) users = emptyList()
        if (liveMatches.isNotEmpty()) liveMatches = emptyList()
        if (record != null) record = null
        if (selectedStake != ReversiStake.three) selectedStake = ReversiStake.three
        if (incoming.isNotEmpty()) incoming = emptyList()
        if (outgoing != null) outgoing = null
        if (match != null) match = null
        if (notice != null) notice = null
        if (isBusy) isBusy = false
        if (isWindowVisible) isWindowVisible = false
        if (isRulesVisible) isRulesVisible = false
        if (rubyBalance != null) rubyBalance = null
        if (hiddenPeerIDs.isNotEmpty()) hiddenPeerIDs = emptySet()
        if (spectating != null) spectating = null
        if (ranking != null) ranking = null
        if (rankingUnavailable) rankingUnavailable = false
        if (watchUnavailable) watchUnavailable = false
        if (spectatorCountUnavailable) spectatorCountUnavailable = false
        if (spectatorCount != 0) spectatorCount = 0
        if (hasLoadedLobby) hasLoadedLobby = false
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (hasLoadedRanking) hasLoadedRanking = false
        if (rankingLoadFailed) rankingLoadFailed = false
        watchRuntime.clear()
        serverClockOffset = 0.0
        hasServerClockOffset = false
        isWindowOccluded = false
        attentionKey = null
        activeMatchID = null
        seenInviteIDs = emptySet()
        answeredInviteIDs = emptySet()
        dismissedMatchIDs = emptySet()
        outgoingRevision = 0
        lobbyRequestOutgoingRevision = 0
        writeRevision = 0
        lastStateRequestAt = distantPast
        lastLobbyRequestAt = distantPast
        lastOutgoingRequestAt = distantPast
        lastMenuLobbyAt = distantPast
        inviteTTLSeconds = 60.0
        turnSeconds = 30
        graceMs = 2_000L
        autoAbandonStreak = 3
        passNotice = null
        dismissWindow?.invoke()
    }

    // MARK: - 내부

    /** 공용 호출 관용구(Swift `perform`). 관전·순위 확장이 같은 관용구로 부른다. null = 버린 결과 — 호출부는 아무것도 바꾸지 않는다. */
    internal suspend fun <T> perform(operation: suspend (SupabaseWorkService, String) -> T): CallResult<T>? =
        performDuelCall(host, { resetGeneration }, operation)

    /** 쓰기 동작이 throw 로 실패했다(5xx·오프라인·PGRST202). */
    private fun noteActionFailure(error: Throwable) {
        if (isSchemaMissing(error)) noteServerMissing() else setNotice(ReversiNoticeText.checkConnection)
    }

    /** Availability `serverMissing` — 서버에 아잉 뒤집기가 아직 없다. */
    fun noteServerMissing() {
        if (availability != ReversiAvailability.serverMissing) availability = ReversiAvailability.serverMissing
        setNotice(ReversiNoticeText.unavailable)
    }

    /** Availability `updateRequired` — 내 앱이 옛 버전이다. */
    fun noteUpdateRequired() {
        if (availability != ReversiAvailability.updateRequired) availability = ReversiAvailability.updateRequired
        setNotice(ReversiNoticeText.updateRequired)
    }

    /** 안내줄 한 문. */
    // 칸 `notice` 의 JVM 세터(setNotice)와 이름이 겹친다 — Swift 이름을 지키고 JVM 이름만 바꾼다(체스 스토어와 같은 꼴).
    @JvmName("setNoticeIfChanged")
    fun setNotice(text: String?) {
        if (notice != text) notice = text
        if (text != passNotice) passNotice = null
    }

    private fun applyRuby(value: Long?) {
        if (value == null) return
        if (rubyBalance != value) rubyBalance = value
        val host = host
        if (host != null && host.rubyBalance != value) host.rubyBalance = value
    }

    fun clearMatch() {
        if (match != null) match = null
        if (phase != ReversiPhase.lobby) phase = ReversiPhase.lobby
        clearFlip()
    }

    /** 받은 신청 하나를 이 기기에서 답한 것으로 적고 카드를 걷는다. */
    private fun forgetIncoming(id: String) {
        answeredInviteIDs = answeredInviteIDs + id
        if (incoming.any { it.id == id }) {
            incoming = incoming.filter { it.id != id }
            scheduleInviteExpiry()
        }
    }

    /** 신청 한 건을 세운다(`pending` 상태 응답). 받은 것인지 보낸 것인지는 **내가 challenger 인가**로 가른다. */
    private fun applyInvite(row: ReversiMatchRow, payload: ReversiStatePayload, id: String) {
        val myID = host?.session?.userID?.lowercase() ?: return
        val stake = row.stake?.toInt() ?: return
        val expiresAt = deviceDate(row.inviteExpiresMs) ?: return
        val peer = playerUser(payload.opponent, inMatch = false) ?: return
        if (row.challenger?.lowercase() == myID) {
            val steady = steadyOutgoing(ReversiOutgoing(id, peer, stake, expiresAt), outgoing)
            if (outgoing != steady) outgoing = steady
        } else if (id !in answeredInviteIDs) {
            val invite = ReversiInvite(id, peer, stake, expiresAt)
            val list = incoming.toMutableList()
            val index = list.indexOfFirst { it.id == id }
            if (index >= 0) list[index] = steadyInvite(invite, list[index]) else list.add(0, invite)
            if (incoming != list) incoming = list.toList()
            if (id !in seenInviteIDs) {
                seenInviteIDs = seenInviteIDs + id
                if (peer.id !in hiddenPeerIDs && !duelsLocked) onInviteArrived?.invoke(invite)
            }
        }
        if (match?.id == id) clearMatch()
        scheduleInviteExpiry()
    }

    /** 그 id 가 판이었으면 판을 내리고, 신청이었으면 신청 카드를 걷는다(보낸 신청이면 안내 한 줄). */
    private fun dropMatchOrInvite(id: String, notice: String? = null) {
        if (match?.id == id) clearMatch()
        if (activeMatchID == id) activeMatchID = null
        if (incoming.any { it.id == id }) incoming = incoming.filter { it.id != id }
        if (outgoing?.id == id) {
            outgoing = null
            if (notice != null) setNotice(notice)
        }
        scheduleInviteExpiry()
    }

    /** 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다(배너가 시계를 읽지 않게 하는 장치). */
    fun scheduleInviteExpiry() {
        expiryTask?.cancel()
        expiryTask = null
        val earliest = (incoming.map { it.expiresAt } + listOfNotNull(outgoing?.expiresAt)).minOrNull() ?: return
        val left = earliest.timeIntervalSince(clock())
        val delaySeconds = (if (left > 0.0) left else 0.0) + 0.25
        val generation = resetGeneration
        expiryTask = launch {
            delay((delaySeconds * 1000).toLong())
            if (generation != resetGeneration) return@launch
            expiryTask = null
            pruneExpiredInvites(clock())
        }
    }

    /** 만료된 신청을 [incoming]·[outgoing] 에서 걷는다(관찰을 깨는 대입 — 배지·칩이 곧바로 꺼진다). */
    fun pruneExpiredInvites(now: SwiftDate) {
        val alive = incoming.filter { it.expiresAt > now }
        if (alive.size != incoming.size) incoming = alive
        val sent = outgoing
        if (sent != null && sent.expiresAt <= now) {
            outgoing = null
            setNotice(ReversiNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /**
     * 판 진행을 사람에게 알린다(진행 중 판을 옮긴 직후). 판이 없거나 끝난 판에서 **진행 중 판으로 처음 넘어가면** 창을 띄우고 주의를 끈다. 창이 안
     * 보이는 동안 차례가 나에게 오면 말풍선 문을 연다. 같은 (판 id, move_count) 에는 한 번뿐이다.
     * Swift 는 첫 줄에서 '이 기기가 연 판'(`ownsMatch`)만 통과시킨다 — Android 는 장부가 없어(오목·체스와 같은 수준) 모든 판이 지난다(머리말).
     */
    private fun noteMatchProgress(previous: ReversiMatchState?, next: ReversiMatchState, windowWasVisible: Boolean) {
        val started = previous == null || previous.isFinished || previous.id != next.id
        if (started) {
            presentWindow?.invoke()
            requestAttention?.invoke()
        }
        if (next.turn != next.myColor) return
        val arrived = started || previous?.turn != next.myColor || previous.moveCount != next.moveCount
        val key = "${next.id}#${next.moveCount}"
        if (!arrived || attentionKey == key) return
        attentionKey = key
        if (windowWasVisible) return
        onAttention?.invoke(
            ReversiAttention(
                kind = if (started) ReversiAttention.Kind.matchStarted else ReversiAttention.Kind.myTurn,
                matchID = next.id, opponentName = next.opponent.displayName, moveCount = next.moveCount,
            ),
        )
    }

    /** 판이 나아갔다 — 뒤집기 그림과 패스 안내를 정한다(1:1 [applyState] · AI `commitAIGame` 두 깔때기가 같이 지난다). */
    internal fun noteBoardProgress(previous: ReversiMatchState?, next: ReversiMatchState) {
        val sameMatch = previous?.id == next.id
        val advanced = !sameMatch || previous?.moveCount != next.moveCount
        if (!advanced) return
        // 뒤집기: 창이 보이고 안 가려졌을 때만. 돌 한 수(+ 패스)일 때만 선다.
        val made = if (isWindowVisible && !isWindowOccluded) {
            ReversiFlipAnimation.make(previous?.id, previous?.moveCount ?: 0, next.id, next.moveCount, next.plies, clock().timeIntervalSince1970)
        } else {
            null
        }
        if (made != null) beginFlip(made) else clearFlip()
        // 패스 안내: 이번에 새로 온 기록에 패스 줄이 있으면 그 사실을 한 줄로(판 화면은 패스를 그리지 않는다).
        if (!sameMatch || previous == null) return
        val fresh = next.plies.filter { it.seq > previous.moveCount }
        val text: String? = when {
            !next.isFinished && next.turn == next.myColor &&
                fresh.any { it.kind == ReversiPly.Kind.pass && it.color == next.myColor.opponent } ->
                ReversiNoticeText.opponentPassed(next.opponent.displayName)
            !next.isFinished && fresh.any { it.kind == ReversiPly.Kind.pass && it.color == next.myColor } -> ReversiNoticeText.myPass
            else -> null
        }
        if (text != null) {
            setNotice(text)
            passNotice = text
        } else {
            val shown = passNotice
            if (shown != null && notice == shown) setNotice(null) // 지난 패스 안내는 다음 수가 오면 걷는다
        }
    }

    internal fun beginFlip(made: ReversiFlipAnimation) {
        flipToken += 1
        val token = flipToken
        flipTask?.cancel()
        flip = made
        val millis = ((made.duration + 0.05) * 1000).toLong()
        flipTask = launch {
            delay(millis)
            if (token != flipToken) return@launch
            flipTask = null
            if (flip != null) flip = null
        }
    }

    internal fun clearFlip() {
        flipToken += 1
        flipTask?.cancel()
        flipTask = null
        if (flip != null) flip = null
    }

    /** `server_now_ms` 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로 받고, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만 간다. */
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

    /** 로비 신청 행 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**. */
    private fun invite(row: ReversiInviteRow, peerRow: ReversiPeerRow?): ReversiInvite? {
        val id = row.matchId?.lowercase()
        if (id.isNullOrEmpty()) return null
        val stake = row.stake?.toInt() ?: return null
        val expiresAt = deviceDate(row.expiresAtMs) ?: return null
        val peer = peerUser(peerRow, inMatch = false) ?: return null
        return ReversiInvite(id, peer, stake, expiresAt)
    }

    /** state 사람 행(`user_id`) → ReversiUser. 행에 없는 칸은 로비 목록에서 빌린다. 서버 어휘 → 화면 글자(센터)는 이 함수 · [peerUser] · [user] 세 곳뿐이다. */
    fun playerUser(row: ReversiPlayerRow?, inMatch: Boolean): ReversiUser? {
        if (row == null) return null
        val id = row.userId?.lowercase()
        if (id.isNullOrEmpty()) return null
        val known = users.firstOrNull { it.id == id }
        return ReversiUser(
            id = id, displayName = row.displayName ?: known?.displayName ?: "",
            avatarURL = row.avatarUrl ?: known?.avatarURL, characterID = row.character ?: known?.characterID,
            center = CenterLabel.display(row.center) ?: known?.center,
            isWorking = known?.isWorking ?: false, isCapable = known?.isCapable ?: true,
            inMatch = inMatch, focusMode = known?.focusMode ?: false,
        )
    }

    /** 로비 PEER 행(`id`) → ReversiUser. 행에 없는 칸은 로비 목록에서 빌린다. */
    fun peerUser(row: ReversiPeerRow?, inMatch: Boolean): ReversiUser? {
        if (row == null) return null
        val id = row.id?.lowercase()
        if (id.isNullOrEmpty()) return null
        val known = users.firstOrNull { it.id == id }
        return ReversiUser(
            id = id, displayName = row.displayName ?: known?.displayName ?: "",
            avatarURL = row.avatarUrl ?: known?.avatarURL, characterID = row.character ?: known?.characterID,
            center = known?.center, isWorking = known?.isWorking ?: false, isCapable = known?.isCapable ?: true,
            inMatch = inMatch, focusMode = known?.focusMode ?: false,
        )
    }

    /** 로비 "지금 대결 중" 한 줄 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**. */
    fun liveMatch(row: ReversiLobbyMatchRow): ReversiLiveMatch? {
        val id = row.id?.lowercase()
        if (id.isNullOrEmpty()) return null
        val a = peerUser(row.a, inMatch = true) ?: return null
        val b = peerUser(row.b, inMatch = true) ?: return null
        val stake = row.stake?.toInt() ?: return null
        val startedAt = deviceDate(row.startedAtMs) ?: return null
        // 안 싣는 서버면 0 — 카드는 그냥 눈 아이콘을 안 그린다(없는 숫자를 지어내지 않는다).
        return ReversiLiveMatch(id, a, b, stake, startedAt, watchers = maxOf(0L, row.watchers ?: 0L).toInt())
    }
}
