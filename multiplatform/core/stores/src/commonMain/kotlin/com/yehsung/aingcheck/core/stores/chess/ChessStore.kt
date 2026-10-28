// 원본: Sources/CheckCore/ChessStore.swift:553-2354(스토어 본문) @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.chessCancel
import com.yehsung.aingcheck.core.net.chessChallenge
import com.yehsung.aingcheck.core.net.chessLobby
import com.yehsung.aingcheck.core.net.chessMove
import com.yehsung.aingcheck.core.net.chessOfferDraw
import com.yehsung.aingcheck.core.net.chessResign
import com.yehsung.aingcheck.core.net.chessRespond
import com.yehsung.aingcheck.core.net.chessRespondDraw
import com.yehsung.aingcheck.core.net.chessState
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessPieceKind
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.rules.chess.fromFen
import com.yehsung.aingcheck.core.rules.chess.fromUci
import com.yehsung.aingcheck.core.rules.chess.uci
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.gomoku.CallResult
import com.yehsung.aingcheck.core.stores.gomoku.distantPast
import com.yehsung.aingcheck.core.stores.gomoku.isSchemaMissing
import com.yehsung.aingcheck.core.stores.gomoku.nonNegative
import com.yehsung.aingcheck.core.stores.gomoku.notice
import com.yehsung.aingcheck.core.stores.gomoku.performDuelCall
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ChessLobbyMatchRow
import com.yehsung.aingcheck.core.wire.games.ChessLobbyMe
import com.yehsung.aingcheck.core.wire.games.ChessLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ChessMatchRow
import com.yehsung.aingcheck.core.wire.games.ChessMoveRow
import com.yehsung.aingcheck.core.wire.games.ChessRPCStatus
import com.yehsung.aingcheck.core.wire.games.ChessStatePayload
import com.yehsung.aingcheck.core.wire.games.ChessUserRow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.jvm.JvmName
import kotlin.math.abs

// 1:1 체스 대결 스토어(v0.3.44) — 화면 상태 · 서버 동기화 · 안전망 폴링 · RPC 호출. 본은 `GomokuStore` 다(같은 규약 ①~⑥).
//
// INV-ChessStore-5f69d4b5 이식: ① **서버가 권위다** — 체스에서 한 겹 더, **"둘 수 있는 칸"도 서버가 준 `legal_moves` 로만 그린다**(⑦).
//  ② 시각은 서버 시계로 보정한다. ③ 폴링은 창이 보일 때만. ④ 늦게 온 응답은 버린다(세대 셋: resetGeneration · 관전 세대 · AI 세대).
//  ⑤ 사용자 문구는 `ChessNoticeText` 한 곳. ⑥ 초 단위 값은 잎만 읽는다.
//  ⑦ **합법 수의 주인이 서버다.** 1:1 판의 하이라이트는 `legal_moves` 를 걸러 그린다. **AI 판은 정반대다** — 로컬 `ChessRules` 가 만든다.
//  ⑧ **입력이 2단**이다(말 고르기 → 도착 칸, 승격이면 한 단 더). 그 상태(`selection`·`promotion`)를 **스토어가** 든다.
//  ⑨ **시계는 클라가 보간한다** — 그리고 서버 응답이 올 때마다 통째로 덮어쓴다(`ChessServerClock` 머리말).
//  ⑩ **자동 착수 장치가 없다**(B4 — 시간 소진 = 패배). ⑪ **별도 받은함 RPC 가 없다** — 로비 `me` 의 두 id 로 알고 `chess_state` 로 채운다.
//
// 옮기지 않은 것 — 애니메이션(`flight` · `ChessMoveFlight` · `beginFlight` 의 그림 몫 · `clearFlight`): C§3.2 "ChessMoveFlight 옮기지 않음"
// (그림 전용 — 이 값이 서 있든 없든 판·합법 수·시계는 바이트까지 같다). 화면 갈래(W4-a)가 Compose 애니메이션으로 다시 낸다.
// 다만 `beginFlight` 안의 **놓은 말 꼬리표 거두기**(`takePendingDrop`)는 판정이라 그대로 옮겼다([notePlyAdvanced]).
// INV-ChessStore-8d22c388 해당 없음: 애니메이션 값(`flight`)에 입력 잠금을 걸지 말라는 규약 — Kotlin 스토어에는 `flight` 칸이 없다(그림 갈래 몫).
// INV-ChessStore-5a7613eb 해당 없음: 애니메이션 꼬리표(`flightGeneration`)로 늦게 깬 옛 Task 를 거르는 규약 — 같은 이유로 칸이 없다.
// INV-ChessStore-635cb077 해당 없음: `windowDidHide` 에서 날던 수를 거두는 규약 — 애니메이션은 화면 갈래가 창 수명과 함께 거둔다.
// INV-ChessStore-221d2393 해당 없음: 가림에서 날던 수를 거두는 규약(60~78Hz 그리기) — 같은 이유.
// INV-ChessStore-9ad35999 해당 없음: 애니메이션 꼬리표는 파생이 성공한 뒤에 올린다 — 같은 이유. 꼬리표 거두기 순서(c83d5450)는 [notePlyAdvanced] 가 지킨다.
//
// ── §8-17 #1(판돈 대결 Android 빌드 깃발) ── `duelsEnabled` 가 꺼진 빌드는 `challenge`·`respond(accept = true)` 가 RPC 를 내지 않고
// 안내 한 줄만 남긴다. 받은 신청은 서버 사실(`incoming`) 그대로 두되 [visibleIncoming] 을 비우고 [incomingFoldedNotice] 로 접는다.
// 로봇 판·관전·순위·무승부 왕복(이미 선 판)은 깃발과 무관하다.

class ChessStore(
    /** 스토어가 일을 띄우는 범위(앱은 메인 한 줄기, 시험은 시험 디스패처). */
    val scope: CoroutineScope,
    host: ChessStoreHost? = null,
) {
    companion object {
        /**
         * INV-ChessStore-666904c1 이식: **주기의 하한(= 가장 잦은 주기의 상한)**. 무료 플랜 예산이라 어떤 분기도 이보다 짧게 두지 마라 —
         * 하한이 지키는 것은 **분당 속도**(1초 주기 = 사람당 60회/분)이고 0.5초 루프에서 이보다 짧으면 루프의 매 걸음이 요청이 된다.
         * 아래 두 상수는 전부 이 하한을 지나 나온다([statePollSeconds]).
         */
        const val statePollFloorSeconds: Double = 1.0
        /** 상대 차례의 상태 조회 주기(초) — 실시간 구독 중. **오목의 3초보다 촘촘하다**(빠른 수 교환). */
        const val statePollSecondsWhileSubscribed: Double = 1.5
        /** 같은 조회 — 미구독. 신호가 없으니 하한까지 당긴다. */
        const val statePollSecondsUnsubscribed: Double = 1.0

        /** 지금 쓸 상태 조회 주기. **하한을 지나서만 나온다** — 상수를 잘못 줄여도 여기서 막힌다. */
        fun statePollSeconds(subscribed: Boolean): Double =
            maxOf(statePollFloorSeconds, if (subscribed) statePollSecondsWhileSubscribed else statePollSecondsUnsubscribed)

        /** 보낸 신청이 떠 있을 때 그 판의 상태를 보는 주기(초). 조회 하나가 수락·거절·만료를 다 알려 준다(⑪). */
        const val outgoingPollSeconds: Double = 5.0
        const val lobbyPollSeconds: Double = 30.0
        /** 팝오버를 열 때 로비를 다시 읽는 **스로틀**(초). 신청 TTL 이 60초이므로 그보다 짧다. */
        const val menuLobbyThrottleSeconds: Double = 30.0
        const val watchPollSeconds: Double = 2.0
        const val rankingPollSeconds: Double = 60.0
        const val reloadDedupeSeconds: Double = 1.0
        const val serverClockToleranceSeconds: Double = 0.25
        const val inviteExpiryToleranceSeconds: Double = 1.0
        /** 깃발이 떨어진 뒤 이만큼 더 기다렸다가 조회로 신고한다(초). 서버가 말해 주면 인스턴스의 `graceSeconds` 가 그 값을 든다. */
        const val flagGraceSeconds: Double = 2.0
        /** throw 실패(5xx·오프라인)가 이만큼 연속되면 관전을 내리고 연결 안내를 남긴다. */
        const val watchFailureLimit: Int = 3

        internal const val LOG_TAG: String = "chess"

        /** 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다. */
        fun steadyInvite(fresh: ChessInvite, previous: ChessInvite?): ChessInvite {
            if (previous == null || previous.id != fresh.id || previous.stake != fresh.stake || previous.peer != fresh.peer ||
                abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) >= inviteExpiryToleranceSeconds
            ) return fresh
            return previous
        }

        /** 서버 수 기록 → 화면 값(seq 오름차순). 하나라도 모양이 어긋나면 **그 줄만** 버린다. */
        fun moveRecords(rows: List<ChessMoveRow>?): List<ChessMoveRecord> = (rows ?: emptyList()).mapNotNull { row ->
            val seq = row.seq?.toInt() ?: return@mapNotNull null
            if (seq < 1) return@mapNotNull null
            val color = ChessColor.fromRawValue(row.color ?: "") ?: return@mapNotNull null
            val from = row.from?.let { ChessSquare.of(it.toInt()) } ?: return@mapNotNull null
            val to = row.to?.let { ChessSquare.of(it.toInt()) } ?: return@mapNotNull null
            val promotion = row.promo?.let { text ->
                val letter = text.firstOrNull() ?: return@let null
                val kind = ChessPieceKind.fromFenLetter(letter) ?: return@let null
                if (kind in ChessPieceKind.promotionChoices) kind else null
            }
            ChessMoveRecord(
                seq = seq, color = color, move = ChessMove(from, to, promotion),
                san = row.san ?: "", fen = row.fen ?: "", msLeft = row.msLeft ?: 0, msSpent = row.msSpent ?: 0,
            )
        }.sortedBy { it.seq }

        /** 판이 **막 끝났는가**(v0.3.64). */
        fun matchJustFinished(old: ChessMatchState?, new: ChessMatchState?): Boolean {
            if (new == null || !new.isFinished) return false
            return !(old?.id == new.id && old.isFinished)
        }

        /** 판 상태 변화 한 줄(없으면 null). 수·차례·끝남·판 교체만 본다. */
        fun matchTransitionLine(old: ChessMatchState?, new: ChessMatchState?): String? {
            fun turn(m: ChessMatchState?): String = m?.turn?.rawValue ?: "none"
            fun ply(m: ChessMatchState?): String = m?.plyCount?.toString() ?: "-"
            fun finished(m: ChessMatchState?): Boolean = m?.isFinished ?: false
            val sameMatch = old?.id == new?.id
            if (sameMatch && ply(old) == ply(new) && turn(old) == turn(new) && finished(old) == finished(new)) return null
            return "state ply=${ply(old)}→${ply(new)} turn=${turn(old)}→${turn(new)} finished=${finished(new)} sameMatch=$sameMatch"
        }

        /** 서버 사람 행 → ChessUser(로비). `capable` 이 null 이면 **불가**다. */
        fun user(from: ChessUserRow): ChessUser? {
            val id = from.userId?.lowercase()
            if (id.isNullOrEmpty()) return null
            return ChessUser(
                id = id, displayName = from.displayName ?: "", avatarURL = from.avatarUrl, characterID = from.character,
                isWorking = from.isWorking ?: false, isCapable = from.capable ?: false, inMatch = from.inMatch ?: false,
                center = CenterLabel.display(from.center),
            )
        }

        /** 로비 정렬: 도전할 수 있는 사람 → 근무 중·가능(대국 중) → 근무 중 → 나머지, 그 안은 이름순(서버 정렬과 같은 규칙 — 되맞춤). */
        fun sortedForLobby(users: List<ChessUser>): List<ChessUser> {
            fun rank(user: ChessUser): Int = when {
                user.isWorking && user.isCapable && !user.inMatch -> 0
                user.isWorking && user.isCapable -> 1
                user.isWorking -> 2
                else -> 3
            }
            return users.sortedWith { lhs, rhs ->
                val l = rank(lhs)
                val r = rank(rhs)
                if (l != r) l.compareTo(r) else NaturalKoCollation.compare(lhs.displayName, rhs.displayName)
            }
        }
    }

    /** 네트워크·세션·루비 미러를 빌리는 곳. null 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다. */
    var host: ChessStoreHost? = host
        private set

    fun attach(host: ChessStoreHost) {
        this.host = host
    }

    // MARK: 화면 상태

    var phase: ChessPhase by mutableStateOf(ChessPhase.lobby)
    var users: List<ChessUser> by mutableStateOf(emptyList())
    var record: ChessRecord? by mutableStateOf(null)
    var selectedStake: ChessStake by mutableStateOf(ChessStake.three)
    /** 받은 신청(서버가 한 번에 하나만 말해 준다 — 로비 `me.incoming_match_id`). */
    var incoming: ChessInvite? by mutableStateOf(null)
    /** 보낸 신청(부분 유니크 인덱스로 한 사람당 하나뿐이다). */
    var outgoing: ChessInvite? by mutableStateOf(null)

    private var matchCell by mutableStateOf<ChessMatchState?>(null)

    /** 지금 판. 대입마다 Swift `didSet` 몫([matchDidChange])이 돈다. */
    var match: ChessMatchState?
        get() = matchCell
        set(value) {
            val old = matchCell
            matchCell = value
            matchDidChange(old, value)
        }

    /** 지금 AI 대국(로컬 판이 권위 — ChessStoreAI.kt). */
    var aiGame: ChessAIGame? by mutableStateOf(null)
        internal set
    /** AI 갈래 장부(선택기·작업·세대). 관찰 대상이 아니다. */
    val aiRuntime: ChessAIRuntime = ChessAIRuntime()

    /** 고른 말과 갈 수 있는 칸(⑧). */
    var selection: ChessSelection? by mutableStateOf(null)
        internal set
    /** 승격 고르기 단계(⑧). */
    var promotion: ChessPromotionPrompt? by mutableStateOf(null)
        internal set

    // MARK: 끌어서 두기 (v0.3.48)

    /**
     * 지금 **끌고 있는 말의 출발 칸**(없으면 null). 끄는 **위치는 여기 없다**(움직일 때마다 스토어를 쓰면 화면 전체가 다시 그려진다).
     * 뷰와 스토어가 함께 쥐는 **걸쇠**다: 끄는 중에 판이 바뀌면 스토어가 이 값을 내리고 그 뒤 `placeDrop` 은 수를 내지 않는다.
     */
    var dragOrigin: ChessSquare? by mutableStateOf(null)
        private set

    /**
     * 끌어 놓은 수의 꼬리표 **원본**. INV-ChessStore-10a8b029 이식: **화면은 이 값을 읽지 않는다** — [pendingDrop] 을 읽는다.
     * 따로 드러낸 까닭은 시험이다("지워서 없는 것"과 "남아 있는데 없는 것으로 읽히는 것"을 가른다).
     */
    var pendingDropRecord: ChessPendingDrop? by mutableStateOf(null)
        private set

    /**
     * 끌어 놓은 말이 **지금** 도착 칸에 머물러야 하는가. INV-ChessStore-2bbcb1b8 이식: **읽는 자리에서 자기 치유한다.** 원본이 남아 있어도
     * 같은 판 · 수 번호가 놓을 때 그대로 · 아직 내 차례 · 출발 칸에 **그 말이 그대로** — 넷 중 하나라도 어긋나면 **없는 것으로 읽힌다**
     * (판에 없는 말이 그려진 채 남는 것이 이 기능의 최악의 버그다).
     */
    val pendingDrop: ChessPendingDrop?
        get() {
            val record = pendingDropRecord ?: return null
            val current = match ?: return null
            if (current.id != record.matchID || current.plyCount != record.ply || !current.isMyTurn ||
                current.position?.get(record.from) != record.piece
            ) return null
            return record
        }

    var notice: String? by mutableStateOf(null)
    var isBusy: Boolean by mutableStateOf(false)
    var isWindowVisible: Boolean by mutableStateOf(false)
    var isRulesVisible: Boolean by mutableStateOf(false)
    /** 서버 응답으로만 갱신(host 에도 반영). */
    var rubyBalance: Long? by mutableStateOf(null)
    /** 서버가 말한 시작 시간·가산·유예(ms). 화면 캡션이 이 값을 읽는다 — 상수를 베끼지 않는다. 로비 응답이 오면 덮인다. */
    var initialMs: Long by mutableStateOf(ChessServerClock.initial.whiteMsLeft)
    var incrementMs: Long by mutableStateOf(3_000L)
    var graceMs: Long by mutableStateOf(2_000L)
    var lobbyLoadFailed: Boolean by mutableStateOf(false)
    var hasLoadedLobby: Boolean by mutableStateOf(false)
    /** 로비 "지금 대결 중" 목록. **서버 순서 그대로**. */
    var liveMatches: List<ChessLiveMatch> by mutableStateOf(emptyList())

    // MARK: 관전 · 순위 — 저장 칸만 여기, 로직은 ChessStoreWatch.kt · ChessStoreRanking.kt

    /**
     * **순위 적재·관전 폴링의 주 스위치. 기본 false.** 켜는 곳은 배선(조립 지점)뿐이다.
     * INV-ChessStore-855a012d 이식: 오목은 이 술어([canPollSpectatorFeatures])를 **뒤늦게** 모았고 그 사이 깃발 겸업 사고가 났다 — 체스는
     * 처음부터 한 술어로 모은다.
     */
    var spectatorFeaturesEnabled: Boolean by mutableStateOf(false)
    var spectating: ChessSpectateState? by mutableStateOf(null)
    var ranking: ChessRankingBoard? by mutableStateOf(null)
    var rankingLoadFailed: Boolean by mutableStateOf(false)
    var hasLoadedRanking: Boolean by mutableStateOf(false)
    /** 서버에 `chess_ranking` 이 아직 없다(PGRST202). */
    var rankingUnavailable: Boolean by mutableStateOf(false)

    /**
     * 서버에 `chess_watch` 가 아직 없다. **관전 입구를 잠그는 신호는 이것뿐이다.**
     * INV-ChessStore-74a0d7f8 이식: `rankingUnavailable` 과 **따로** 둔다 — 한 깃발이 두 소비자를 겸업하다 한쪽을 좁히는 순간 [관전] 칩
     * 게이트가 조용히 죽었다(오목 2026-10-01). 게이트와 신호는 짝으로 움직인다.
     */
    var watchUnavailable: Boolean by mutableStateOf(false)

    /**
     * 서버에 `chess_watch_live` 가 아직 없다 — 이 로그인 동안 옛 `chess_watch` 로 접어 쓴다.
     * INV-ChessStore-871a1b00 이식: [watchUnavailable] 과 **절대 같은 깃발을 쓰지 마라** — 저 깃발은 관전 입구를 통째로 잠근다.
     * 관전자 수가 없는 것과 관전을 못 하는 것은 **다른 사실**이다. 세우는 곳은 `watchFetch` 의 PGRST202 갈래 하나, 내리는 곳은 `reset` 하나.
     */
    var spectatorCountUnavailable: Boolean by mutableStateOf(false)
    /** 지금 보고 있는 판(관전) 또는 내가 두고 있는 판의 **관전자 수**. 한 칸인 까닭은 관전과 대국이 동시에 설 수 없어서다. */
    var spectatorCount: Long by mutableStateOf(0L)
    /** 관전·순위 장부. 관찰 대상이 아니다. */
    val watchRuntime: ChessWatchRuntime = ChessWatchRuntime()

    val isSpectating: Boolean get() = spectating != null

    /** 순위·관전 조회가 **지금** 나가도 되는가 — 주 스위치 + 창이 보이고 안 가려짐 + 세션. */
    val canPollSpectatorFeatures: Boolean
        get() = spectatorFeaturesEnabled && isWindowVisible && !isWindowOccluded && host?.session != null

    // MARK: §8-17 #1 — 판돈 대결 진입 깃발

    val appConfig: AppConfig get() = host?.appConfig ?: AppConfig()

    /** 판돈 대결의 신청·수락 진입이 이 빌드에서 잠겼는가. 로봇 판·관전·순위는 이 값을 보지 않는다. */
    val duelsLocked: Boolean get() = !appConfig.duelsEnabled

    /** 잠긴 빌드에서 받은 신청을 접는 한 줄(받은 신청이 있을 때만 — 차단한 사람의 신청은 세지 않는다). */
    val incomingFoldedNotice: String?
        get() {
            val invite = incoming ?: return null
            if (!duelsLocked || invite.peer.id in hiddenPeerIDs) return null
            return ChessNoticeText.updateMine
        }

    // MARK: 화면 갈래가 조립 지점에서 물리는 문

    var presentWindow: (() -> Unit)? = null
    var dismissWindow: (() -> Unit)? = null
    /** 새 받은 신청(처음 본 id 한 번). 잠긴 빌드에서는 부르지 않는다(§8-17 #1). */
    var onInviteArrived: ((ChessInvite) -> Unit)? = null
    var requestAttention: (() -> Unit)? = null
    var onAttention: ((ChessAttention) -> Unit)? = null
    /** v0.3.64: 내 1:1 판이 끝난 것을 **처음 본** 순간 한 번 부른다. AI(로봇) 판은 부르지 않는다. */
    var onMatchFinished: (() -> Unit)? = null

    // MARK: 내부 장부 (관찰 대상 아님)

    /** 이 스토어의 '지금'. 시험이 갈아 끼운다(기본은 호스트의 시계 — 구조 시험 R2). */
    var clock: () -> SwiftDate = { this.host?.now() ?: SwiftDate.fromReferenceDate(0.0) }
    var pollStepSeconds: Double = 0.5
    var serverClockOffset: Double = 0.0
        private set
    private var hasServerClockOffset = false
    var resetGeneration: Int = 0
        private set
    var isWindowOccluded: Boolean = false
        internal set
    var stateInFlightID: String? = null
        private set
    private var pendingStateID: String? = null
    private var stateInFlight = false
    private var stateAgain = false
    private var lobbyInFlight = false
    private var attentionKey: String? = null
    var shownResultIDs: Set<String> = emptySet()
        private set
    /** 서버가 말한 내 진행 중 대국 id. */
    var activeMatchID: String? = null
        private set
    var seenInviteIDs: Set<String> = emptySet()
        private set
    var dismissedMatchIDs: Set<String> = emptySet()
        private set
    var pollTask: Job? = null
        private set
    private var pollToken = 0
    private var expiryTask: Job? = null
    var lastStateRequestAt: SwiftDate = distantPast
    var lastLobbyRequestAt: SwiftDate = distantPast
    /** 신호 재조회 직렬화(오목 `syncTask` 와 같은 규약). */
    var syncTask: Job? = null
        private set
    private var syncPendingTrailing = false
    var lastMenuLobbyAt: SwiftDate = distantPast
    var lastOutgoingRequestAt: SwiftDate = distantPast

    /**
     * 서버가 말한 신청 만료(초) — 로비 응답의 `invite_ttl_seconds` 가 오면 그 값이고, 없으면 60이다.
     * INV-ChessStore-fce33e7e 이식: **읽기를 연 까닭** — 화면이 "1분 안에 응답하세요"·규칙 시트의 TTL 줄을 그린다. 상수를 박아 두면 서버가
     * `chess_invite_ttl_seconds()` 를 바꾼 날 화면만 옛 숫자를 말한다. 쓰기는 코어만 한다(`applyLobby` · `reset`).
     */
    var inviteTTLSeconds: Double = 60.0
        private set
    private var outgoingRevision = 0
    private var lobbyRequestOutgoingRevision = 0
    /** 차단으로 걷어낸 상대(소유자가 채운다). **코어 목록은 서버 답 그대로 두고** 화면이 읽는 파생값만 거른다. */
    var hiddenPeerIDs: Set<String> by mutableStateOf(emptySet())

    /** 로비 상대 목록(화면용). */
    val visibleUsers: List<ChessUser>
        get() = if (hiddenPeerIDs.isEmpty()) users else users.filter { it.id !in hiddenPeerIDs }

    /** 받은 신청(화면용 — 차단한 사람이 보낸 것은 뺀다). 잠긴 빌드에서는 null(§8-17 #1 — 접힌 줄은 [incomingFoldedNotice]). */
    val visibleIncoming: ChessInvite?
        get() {
            val invite = incoming ?: return null
            if (invite.peer.id in hiddenPeerIDs || duelsLocked) return null
            return invite
        }

    /** 지금 서버가 말해 준 유예(초). */
    val graceSeconds: Double get() = maxOf(0.0, graceMs.toDouble() / 1000)

    internal fun log(message: String) = host.notice(LOG_TAG, message)

    private fun launch(block: suspend CoroutineScope.() -> Unit): Job = scope.launch(block = block)

    // MARK: - match 대입(Swift didSet)

    private fun matchDidChange(oldValue: ChessMatchState?, newValue: ChessMatchState?) {
        matchTransitionLine(oldValue, newValue)?.let(::log)
        if (matchJustFinished(oldValue, newValue) && !isAIMatch) onMatchFinished?.invoke()
        // 판이 바뀌면 입력 2단은 통째로 접는다(⑧ — 앞 판의 선택이 새 판의 칸을 가리키면 그게 사고다).
        if (oldValue?.id != newValue?.id || oldValue?.plyCount != newValue?.plyCount) {
            if (selection != null) selection = null
            if (promotion != null) promotion = null
        }
        // 끌던 말은 판·수 번호가 바뀌거나 **내 차례가 아니게 되면** 놓는다. 시계·무승부 제안처럼 판의 다른 칸만 바뀐 갱신은 건드리지 않는다.
        if (dragOrigin != null &&
            (oldValue?.id != newValue?.id || oldValue?.plyCount != newValue?.plyCount || newValue?.isMyTurn != true)
        ) {
            dragOrigin = null
        }
        // 놓은 말의 꼬리표는 **판이 갈리면** 여기서 지운다. 수 번호만 오른 것은 지우지 않는다(곧이어 [notePlyAdvanced] 가 가린다).
        if (pendingDropRecord != null && oldValue?.id != newValue?.id) pendingDropRecord = null
        // AI 판은 `match` 가 그 id 를 들고 있는 동안만 산다.
        val game = aiGame
        if (game != null && newValue?.id != game.id) discardAIGame()
        // 내 판이 섰으면(끝난 판 포함) 관전은 내려간다.
        if (newValue != null && spectating != null) {
            spectating = null
            watchRuntime.bumpWatchGeneration()
        }
        if (newValue == null && spectatorCount != 0L) spectatorCount = 0
    }

    // MARK: - 창

    /** 창을 띄우고 로비·판을 읽는다. [focusMatchID] 는 배너·말풍선에서 온 경로의 대상이다. */
    fun openWindow(focusMatchID: String?) {
        if (host?.session != null) {
            val focus = focusMatchID?.lowercase()
            // 곧 이어질 windowDidShow 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다.
            lastLobbyRequestAt = clock()
            launch {
                refreshLobby()
                val current = match
                if (focus != null && focus != current?.id) {
                    refreshMatch(focus)
                } else if (current != null && !current.isFinished) {
                    refreshMatch(current.id)
                }
            }
        }
        presentWindow?.invoke()
    }

    /** 창이 실제로 보이기 시작했다. 폴링 시작 · 로비 재조회 · AI 시계 재개. */
    fun windowDidShow() {
        if (!isWindowVisible) isWindowVisible = true
        isWindowOccluded = false
        resumeAIClockIfVisible()
        startPolling()
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastLobbyRequestAt) >= reloadDedupeSeconds) launch { refreshLobby() }
        val current = match
        if (current != null && !current.isFinished && !isAIMatch && now.timeIntervalSince(lastStateRequestAt) >= reloadDedupeSeconds) {
            // 창이 안 보이는 동안 시계는 서버에서 흘렀다 — 올라온 순간 한 번 당겨 보간 기준선을 새로 받는다(⑨).
            launch { refreshMatch(current.id) }
        }
        spectatorWindowDidShow(now)
    }

    /**
     * 창이 가려졌다·닫혔다·최소화됐다. 폴링만 멈춘다 — **대국은 계속된다**.
     * INV-ChessStore-be04d6b9 이식: **최소화도 이 문을 지난다.** 그래서 "그만 본다"는 뜻은 [windowDidClose] 로 갈라 뒀다(합치면 최소화만 해도
     * 남의 판 관전이 로비로 떨어진다).
     */
    fun windowDidHide() {
        if (isWindowVisible) isWindowVisible = false
        isWindowOccluded = false
        // 끌던 말·놓은 말도 창과 함께 내려간다 — 안 보이는 판에서 뗀 마우스가 수를 내면 안 된다.
        cancelDrag()
        clearPendingDrop()
        stopPolling()
        pauseAIClock()
        // 끝난 판을 관전한 채 닫았다 = 그 판에서 나간 것이다. **진행 중인 관전은 남긴다**.
        if (spectating?.isFinished == true) stopWatching()
    }

    /**
     * 창을 **정말 닫았다**. 관전을 내린다(요청은 쏘지 않는다 — 체스에는 `chess_leave` 가 없다). **끝난 내 판도 여기서 내린다**(0.3.50).
     * **진행 중인 판은 건드리지 않는다** — 닫기는 기권이 아니다(시계는 서버에서 흐른다).
     */
    fun windowDidClose() {
        if (spectating != null) stopWatching()
        cancelDrag()
        clearPendingDrop()
        foldFinishedMatch()
    }

    /** 창의 가림 상태가 바뀌었다. **폴링·AI 시계만** 멈추고 되살린다. */
    fun windowOcclusionDidChange(visible: Boolean) {
        isWindowOccluded = !visible
        if (visible) {
            resumeAIClockIfVisible()
            startPolling()
        } else {
            // 끌던 말을 놓는다 — 가려진 판 위에서 뗀 마우스는 사용자가 **보지 못한 채** 둔 수다.
            // INV-ChessStore-da22ecb3 이식: 놓은 말([pendingDrop])은 여기서 지우지 않는다 — 가림 통지는 틀릴 수 있고, 보이는 창에서 답을
            // 기다리던 말이 출발 칸으로 튀었다가 답과 함께 다시 미끄러지면 안 된다.
            cancelDrag()
            pauseAIClock()
            stopPolling()
        }
    }

    // MARK: - 조회

    suspend fun refreshLobby() {
        if (host?.session == null || lobbyInFlight) return
        lobbyInFlight = true
        val generation = resetGeneration
        try {
            lastLobbyRequestAt = clock()
            lobbyRequestOutgoingRevision = outgoingRevision
            when (val result = perform { service, token -> service.chessLobby(token) }) {
                null -> Unit
                is CallResult.Success -> applyLobby(result.value)
                is CallResult.Failure -> {
                    if (isSchemaMissing(result.error)) {
                        log("lobby unavailable — chess functions missing on server")
                        setNotice(ChessNoticeText.unavailable)
                    } else {
                        log("lobby request failed")
                    }
                    if (!lobbyLoadFailed) lobbyLoadFailed = true
                }
            }
        } finally {
            if (generation == resetGeneration) lobbyInFlight = false
        }
    }

    suspend fun applyLobby(response: ChessLobbyResponse) {
        if (response.status != ChessRPCStatus.ok) {
            log("lobby refused status=${response.status.rawValue}")
            if (response.status == ChessRPCStatus.unsupportedClient) setNotice(ChessNoticeText.updateMine)
            if (!lobbyLoadFailed) lobbyLoadFailed = true
            return
        }
        noteServerNow(response.serverNowMs)
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (!hasLoadedLobby) hasLoadedLobby = true
        response.initialMs?.let { if (it > 0 && initialMs != it) initialMs = it }
        response.incrementMs?.let { if (it >= 0 && incrementMs != it) incrementMs = it }
        response.graceMs?.let { if (it >= 0 && graceMs != it) graceMs = it }
        response.inviteTtlSeconds?.let { if (it > 0) inviteTTLSeconds = it.toDouble() }
        val me = response.me
        if (me != null) {
            applyRuby(me.rubyBalance)
            val fresh = ChessRecord(me.wins ?: 0, me.losses ?: 0, me.draws ?: 0)
            if (record != fresh) record = fresh
            activeMatchID = me.activeMatchId?.lowercase()
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
        applyLobbyInvites(response.me)
        val active = activeMatchID
        if (active != null && (match?.id != active || match?.isFinished == true)) refreshMatch(active)
    }

    /**
     * 로비 `me` 의 두 신청 id 를 화면 값으로 옮긴다(⑪). 서버는 id 만 준다 — 상대·판돈·만료는 그 id 로 `chess_state` 를 한 번 더 불러야 안다.
     * 그래서 **id 가 새로 생겼을 때만** 조회하고, 들고 있는 신청과 같은 id 면 아무 요청도 내지 않는다(무료 플랜).
     */
    private suspend fun applyLobbyInvites(me: ChessLobbyMe?) {
        val incomingID = me?.incomingMatchId?.lowercase()
        val outgoingID = me?.outgoingMatchId?.lowercase()
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        val predatesOutgoing = lobbyRequestOutgoingRevision < outgoingRevision
        val gone = outgoing
        if (gone != null && outgoingID != gone.id && !predatesOutgoing) {
            // 판으로 이어졌으면(= 수락) 아래 refreshMatch 가 판을 세우고, 그때는 거절 안내를 하지 않는다.
            val becameMatch = gone.id == activeMatchID || gone.id == match?.id
            if (!becameMatch) setNotice(if (gone.expiresAt > clock()) ChessNoticeText.inviteDeclined else ChessNoticeText.inviteTimedOut)
            outgoing = null
            scheduleInviteExpiry()
        }
        if (incoming != null && incomingID != incoming?.id) {
            incoming = null
            scheduleInviteExpiry()
        }
        for (id in listOfNotNull(incomingID, outgoingID)) {
            if (id == incoming?.id || id == outgoing?.id || id == match?.id) continue
            refreshMatch(id)
        }
    }

    suspend fun refreshMatch() {
        refreshMatch(match?.id ?: activeMatchID)
    }

    /**
     * 한 판(또는 신청)의 상태를 읽는다. 같은 판을 들고 있으면 `p_since_seq` 로 **새 수만** 받고, 수 번호가 이어지지 않으면 처음부터 한 번 더
     * 받는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다. 다른 판 id 가 들어오면 기억했다가 지금 판이 끝난 뒤 그 판을 한 번 읽는다.
     */
    suspend fun refreshMatch(id: String?) {
        // AI 판 id 는 서버에 없다 — 어느 경로로 와도 **여기서** 막는다.
        val requested = id?.lowercase()
        if (requested.isNullOrEmpty() || ChessAIGame.isAIMatchID(requested) || host?.session == null) return
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
                val since = if (!forceFull && current?.id == matchID) current.plyCount else 0
                forceFull = false
                lastStateRequestAt = clock()
                if (outgoing?.id == matchID) lastOutgoingRequestAt = lastStateRequestAt
                val result = perform { service, token -> service.chessState(token, matchID, since.toLong()) }
                if (generation != resetGeneration) return
                when (result) {
                    is CallResult.Success -> {
                        val response = result.value
                        when (response.status) {
                            ChessRPCStatus.ok -> {
                                if (applyState(response.state, since) == StateApplyOutcome.needsFull && since > 0) {
                                    forceFull = true
                                    stateAgain = true
                                }
                            }
                            ChessRPCStatus.notFound -> dropMatchOrInvite(matchID)
                            ChessRPCStatus.unsupportedClient -> setNotice(ChessNoticeText.updateMine)
                            else -> log("state refused status=${response.status.rawValue}")
                        }
                    }
                    is CallResult.Failure -> if (isSchemaMissing(result.error)) setNotice(ChessNoticeText.unavailable)
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

    enum class StateApplyOutcome { applied, needsFull, ignored }

    /**
     * 서버 상태 묶음을 화면 상태로 옮긴다. **대국과 신청을 한 경로로 가른다**(⑪): `pending` 은 신청이고 `active`/`finished` 는 판이며 그 밖은
     * 둘 다 아니다. 수 기록은 `p_since_seq` 뒤만 오므로 이어 붙이고, 번호가 이어지지 않으면 `needsFull`. 판 자체는 `match.fen` 이 권위다.
     */
    fun applyState(payload: ChessStatePayload, requestedSince: Int = 0): StateApplyOutcome {
        val row = payload.match ?: return StateApplyOutcome.ignored
        val id = row.id?.lowercase()
        if (id.isNullOrEmpty()) return StateApplyOutcome.ignored
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance)
        when (val status = row.status ?: "") {
            "pending" -> {
                applyInvite(row, payload, id)
                return StateApplyOutcome.applied
            }
            "active", "finished" -> Unit
            else -> {
                // 시작하지 못하고 끝난 신청(declined·cancelled·expired) — 판도 아니고 살아 있는 신청도 아니다.
                dropMatchOrInvite(id, if (status == "expired") ChessNoticeText.inviteTimedOut else ChessNoticeText.inviteDeclined)
                return StateApplyOutcome.applied
            }
        }

        val isFinished = row.status == "finished"
        if (isFinished && id in dismissedMatchIDs && match?.id != id) return StateApplyOutcome.ignored

        val myID = host?.session?.userID?.lowercase()
        var myColor = ChessColor.fromRawValue(payload.myColor ?: "")
        if (myColor == null && myID != null) {
            if (row.black?.lowercase() == myID) myColor = ChessColor.black
            else if (row.white?.lowercase() == myID) myColor = ChessColor.white
        }
        if (myColor == null) return StateApplyOutcome.ignored

        val base = if (match?.id == id) match else null
        val rowPly = row.plyCount?.toInt()
        // 같은 판을 진행 중으로 들고 있는데 **수 번호가 줄어든** 응답은 옛 스냅숏이 늦게 온 것이다. 끝난 응답은 예외다.
        if (base != null && !base.isFinished && !isFinished && rowPly != null && rowPly < base.plyCount) return StateApplyOutcome.ignored
        // 같은 판을 이미 끝남으로 들고 있으면 진행 중 응답은 전부 끝나기 전에 읽힌 옛 스냅숏이다.
        if (base != null && base.isFinished && !isFinished) return StateApplyOutcome.ignored

        val records = moveRecords(payload.moves)
        val rebuild = base == null || records.firstOrNull()?.seq == 1 || requestedSince == 0
        val merged = if (rebuild) ArrayList() else ArrayList(base?.moves ?: emptyList())
        var applied = if (rebuild) 0 else (base?.plyCount ?: 0)
        for (record in records) {
            if (record.seq <= applied) continue
            if (record.seq != applied + 1 && !rebuild) return StateApplyOutcome.needsFull
            merged.add(record)
            applied = record.seq
        }
        val serverPly = rowPly ?: applied
        if (serverPly != applied && !rebuild) return StateApplyOutcome.needsFull

        val fen = row.fen ?: base?.fen ?: ""
        val position = ChessPosition.fromFen(fen)
        if (position == null) {
            // 서버가 자기 FEN 을 파싱해 응답을 만들므로 여기 오면 **서버와 앱의 파서가 갈린 것**이다. 판은 못 그려도 결과·루비는 보여 준다.
            log("state fen rejected by parser")
        }
        val turn = if (isFinished) null else ChessColor.fromRawValue(row.turn ?: "")
        // INV-ChessStore-bbc205ef 이식: 서버 값으로 **통째로 덮어쓴다**(⑨). 들고 있던 값과 섞지 마라.
        val clockValue = ChessServerClock(
            whiteMsLeft = row.whiteMsLeft ?: base?.clock?.whiteMsLeft ?: initialMs,
            blackMsLeft = row.blackMsLeft ?: base?.clock?.blackMsLeft ?: initialMs,
            incrementMs = row.incrementMs ?: incrementMs,
            turnStartedAt = if (isFinished) null else deviceDate(row.turnStartedMs),
            running = turn,
        )
        val outcome = when (row.result) {
            "draw" -> ChessMatchOutcome.draw
            "white_win" -> if (myColor == ChessColor.white) ChessMatchOutcome.won else ChessMatchOutcome.lost
            "black_win" -> if (myColor == ChessColor.black) ChessMatchOutcome.won else ChessMatchOutcome.lost
            else -> null
        }
        val stake = row.stake ?: base?.stake ?: 0L
        val rubyDelta = when (outcome) {
            // 승자 순이익 = 판돈 − 수수료(`DuelFee` — v0.3.64 수수료 0). 무승부 환불엔 수수료가 없다.
            ChessMatchOutcome.won -> DuelFee.winnerNet(stake.toInt()).toLong()
            ChessMatchOutcome.lost -> -stake
            ChessMatchOutcome.draw -> 0L
            null -> null
        }
        val opponentID = (if (myColor == ChessColor.white) row.black else row.white)?.lowercase()
        val opponent = peerUser(payload.opponent, inMatch = !isFinished)
            ?: base?.opponent
            ?: users.firstOrNull { it.id == opponentID }
            ?: ChessUser(
                id = opponentID ?: "", displayName = "", avatarURL = null, characterID = null,
                isWorking = true, isCapable = true, inMatch = !isFinished,
            )
        // **서버가 준 것만** 쓴다(⑦). 끝난 판·상대 차례는 null 이라 빈 배열이 되고, 그러면 선택·착수가 전부 막힌다.
        val legal = if (position == null) emptyList() else (payload.legalMoves ?: emptyList()).mapNotNull { ChessMove.fromUci(it) }
        val offerBy = row.drawOfferBy?.lowercase()

        val next = ChessMatchState(
            id = id, stake = stake, myColor = myColor, opponent = opponent, fen = fen, position = position,
            plyCount = serverPly, turn = turn, lastMove = merged.lastOrNull()?.move, moves = merged.toList(), clock = clockValue,
            isInCheck = payload.inCheck ?: false, legalMoves = legal, isFinished = isFinished,
            outcome = outcome, endReason = ChessEndReason.fromRawValue(row.endReason),
            rubyDelta = rubyDelta, drawOfferBy = offerBy,
            drawOfferedByMe = offerBy != null && offerBy == myID,
            // 유예는 **행마다** 실려 온다(판·사람당 1회 예산에서 깎인 잔량). 깃발 되묻기가 이 값을 읽는다.
            whiteGraceMs = row.whiteGraceMs ?: base?.whiteGraceMs,
            blackGraceMs = row.blackGraceMs ?: base?.blackGraceMs,
        )

        val justFinished = isFinished && base?.isFinished == false
        val previous = match
        val windowWasVisible = isWindowVisible
        // 이 판이 신청이었으면 카드를 걷는다(수락된 쪽·내가 수락한 쪽 모두).
        if (incoming?.id == id) incoming = null
        if (outgoing?.id == id) outgoing = null
        if (match != next) match = next
        // 내 판을 보고 있는 사람 수. **`match` 대입 뒤**에 세운다 — 그 대입이 판이 바뀌는 길목에서 0 으로 되돌린다.
        val watchers = nonNegative(payload.watchers)
        if (spectatorCount != watchers) spectatorCount = watchers
        // 한 수 나아갔다(1:1 깔때기). 이전 판은 `base` 가 아니라 **`previous`** 로 잰다.
        notePlyAdvanced(id, previous?.id, previous?.plyCount, serverPly, next.lastMove)
        val nextPhase = if (isFinished) ChessPhase.result else ChessPhase.playing
        if (phase != nextPhase) phase = nextPhase
        activeMatchID = if (isFinished) null else id
        if (isFinished) shownResultIDs = shownResultIDs + id
        if (!isFinished) {
            // 새 판이 열렸다 — 로비에서 남긴 안내("신청을 보냈어요")는 대국 상태줄을 가린다.
            if (previous?.id != id || previous.isFinished) setNotice(null)
            noteMatchProgress(previous, next, windowWasVisible)
        }
        if (justFinished) {
            // 전적은 로비 응답에만 있다. 끝난 순간 한 번 다시 읽는다.
            launch { refreshLobby() }
            // 순위도 같은 순간 바뀐다.
            noteOwnMatchFinishedForRanking()
        }
        return StateApplyOutcome.applied
    }

    /**
     * 판이 나아갔을 때 **놓은 말 꼬리표**를 거둔다(Swift `beginFlight` 의 꼬리표 몫 · `takePendingDrop`). 1:1 `applyState` 와 로봇 `commitAIGame`
     * 두 깔때기가 부른다(관전 깔때기는 남의 판이라 꼬리표를 건드리지 않는다 — 판 id 가 다르다).
     * INV-ChessStore-c83d5450 이식: 꼬리표는 애니메이션 거절(창 가림·판 다름·수 번호)보다 **먼저** 거둔다 — 그림을 안 만드는 길에서도 판은
     * 나아갔고, 그때 꼬리표가 남으면 다음에 같은 칸을 지나는 수가 끌어 놓은 수로 읽힌다(Kotlin 스토어에는 그림 거절이 없으니 언제나 거둔다).
     * 돌려주는 값 = 방금 나아간 수가 **끌어 놓은 그 수**인가(화면 갈래가 애니메이션에서 그 말만 빼는 근거 — 같은 판 · 정확히 한 수 · 출발·도착 칸).
     */
    internal fun notePlyAdvanced(matchID: String, previousMatchID: String?, previousPly: Int?, nextPly: Int, move: ChessMove?): Boolean {
        val pending = pendingDropRecord ?: return false
        // 남의 판(관전 깔때기)은 내 꼬리표를 건드리지 않는다. 판이 갈렸다면 `match` 대입이 이미 지웠다.
        if (pending.matchID != matchID) return false
        // 수 번호가 그대로인 응답(폴링 · 시계 · 무승부 제안)은 아직 답이 아니다 — 계속 기다린다.
        if (nextPly == pending.ply) return false
        // 판이 나아갔다. 맞든 아니든 이 꼬리표의 일은 끝났다.
        pendingDropRecord = null
        return previousMatchID == matchID && previousPly == pending.ply && nextPly == pending.ply + 1 &&
            move?.from == pending.from && move.to == pending.to
    }

    // MARK: - 입력 2단 (⑧)

    /** 고른 말이 그 칸으로 갈 수 있는 합법 수들(승격이면 넷). **들고 있는 `legalMoves` 에서만** 찾는다. */
    fun legalMoves(from: ChessSquare, to: ChessSquare): List<ChessMove> =
        (match?.legalMoves ?: emptyList()).filter { it.from == from && it.to == to }

    /** 그 말이 갈 수 있는 칸 전부. */
    fun targets(from: ChessSquare): Set<ChessSquare> =
        (match?.legalMoves ?: emptyList()).filter { it.from == from }.map { it.to }.toSet()

    /**
     * 판을 한 번 누른 결과 — **화면의 유일한 입구**. 거절은 전부 이유를 남긴다. 순서가 계약이다: 왕복 중 → 판 없음 → 끝난 판 → 읽을 수 없는 판 →
     * 내 차례 아님 → (고른 말이 있으면) 도착 칸 → 내 말 고르기.
     */
    suspend fun tap(square: ChessSquare) {
        if (isBusy) return refuseTap(ChessTapRefusal.busy, square)
        val current = match ?: return refuseTap(ChessTapRefusal.noMatch, square)
        if (current.isFinished) return refuseTap(ChessTapRefusal.finished, square)
        if (current.position == null) return refuseTap(ChessTapRefusal.unreadableBoard, square)
        if (!current.isMyTurn) return refuseTap(ChessTapRefusal.notYourTurn, square)

        // 승격을 고르는 중이면 판 탭은 그 단계를 취소한다(다른 수를 고르려는 뜻이다).
        // INV-ChessStore-b9259ed5 이식: 꼬리표는 **승격을 실제로 접을 때만** 지운다 — 승격이 아닌 꼬리표는 "놓았고 곧 보낼 수"다. 화면은
        // `placeDrop` 을 그 자리에서 부르고 왕복(`finishDrop`)은 따로 넘기므로, 그 틈에 온 탭이 꼬리표를 지우면 놓은 수가 조용히 사라진다.
        if (promotion != null) {
            promotion = null
            clearPendingDrop()
        }

        val selected = selection
        if (selected != null && selected.from != square) {
            if (square in selected.targets) {
                commit(selected.from, square)
                return
            }
            // 갈 수 없는 칸이다. 거기에 **내 말**이 있으면 고르기를 옮긴다(체스 UI 의 관례) — 아니면 거절한다.
            val piece = current.position[square]
            if (piece != null && piece.color == current.myColor) {
                select(square)
                return
            }
            return refuseTap(ChessTapRefusal.illegalTarget, square)
        }
        if (selection?.from == square) {
            selection = null // 같은 칸을 다시 누르면 고르기 해제
            return
        }
        val piece = current.position[square] ?: return refuseTap(ChessTapRefusal.emptySquare, square)
        if (piece.color != current.myColor) return refuseTap(ChessTapRefusal.notMyPiece, square)
        select(square)
    }

    /** 승격 창에서 말을 골랐다 — 그 수를 보낸다. 끌어 놓은 폰이었다면 답이 무엇이든 꼬리표의 일은 끝났다. */
    suspend fun choosePromotion(kind: ChessPieceKind) {
        val prompt = promotion ?: return
        promotion = null
        send(ChessMove(prompt.from, prompt.to, kind))
        clearPendingDrop()
    }

    /** 승격 창을 닫았다(고르기는 남는다). 끌어 놓은 폰은 출발 칸으로 돌아간다. */
    fun cancelPromotion() {
        if (promotion != null) promotion = null
        clearPendingDrop()
    }

    /** 고르기를 세운다. 갈 수 있는 칸이 없으면 **세우지 않는다**(움직일 수 없는 말을 고른 채로 두면 다음 탭이 혼난다). */
    private fun select(square: ChessSquare) {
        val targets = targets(square)
        if (targets.isEmpty()) {
            selection = null
            refuseTap(ChessTapRefusal.illegalTarget, square)
            return
        }
        selection = ChessSelection(square, targets)
    }

    /** 도착 칸이 정해졌다. 승격이면 한 단 더 묻고, 아니면 곧바로 보낸다. */
    private suspend fun commit(from: ChessSquare, to: ChessSquare) {
        val candidates = legalMoves(from, to)
        if (candidates.isEmpty()) return refuseTap(ChessTapRefusal.illegalTarget, to)
        selection = null
        if (candidates.size > 1 || candidates.any { it.promotion != null }) {
            // 같은 칸으로 가는 합법 수가 여럿 = 승격 네 갈래다.
            promotion = ChessPromotionPrompt(from, to)
            return
        }
        send(candidates[0])
    }

    /** 한 수를 서버(또는 AI 판)로 보낸다. */
    suspend fun send(move: ChessMove) {
        val current = match
        if (isBusy || current == null || current.isFinished) return
        // AI 판은 위 거절 가드를 **같이** 지난 뒤 로컬 판에 둔다 — 서버로는 안 나간다(로그인 여부도 안 본다).
        if (isAIMatch) {
            moveInAIMatch(move)?.let { refuseTap(it, move.to) }
            return
        }
        if (host?.session == null) return refuseTap(ChessTapRefusal.signedOut, move.to)
        val id = current.id
        val expected = current.plyCount
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.chessMove(token, id, expected.toLong(), move.uci) }) {
                null -> return
                is CallResult.Failure ->
                    setNotice(if (isSchemaMissing(result.error)) ChessNoticeText.unavailable else ChessNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(ChessNoticeText.move(response.status))
                    if (response.status != ChessRPCStatus.ok) log("move refused status=${response.status.rawValue}")
                    if (response.status == ChessRPCStatus.notFound) {
                        if (match?.id == id) clearMatch()
                        return
                    }
                    // 내 판단이 서버와 갈렸다 — **언제나** 다시 읽는다.
                    var needsRefresh = when (response.status) {
                        ChessRPCStatus.stale, ChessRPCStatus.notYourTurn, ChessRPCStatus.notActive, ChessRPCStatus.illegal,
                        ChessRPCStatus.retry -> true
                        else -> false
                    }
                    val state = response.state
                    if (state != null) {
                        if (applyState(state, expected) == StateApplyOutcome.needsFull) needsRefresh = true
                    } else if (response.status == ChessRPCStatus.ok) {
                        needsRefresh = true // 상태를 안 실어 준 성공(서버 계약상 없지만 모르는 모양은 되묻는다)
                    }
                    // 서버가 거절한 수가 **끌어 놓은 수**였다면 놓은 말은 여기서 출발 칸으로 돌아간다 — 재조회를 기다리지 않는다.
                    if (response.status != ChessRPCStatus.ok) clearPendingDrop()
                    if (needsRefresh) refreshMatch(id)
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    // MARK: - 끌어서 두기 (v0.3.48) — 문은 넷: grab · beginDrag · placeDrop(동기) · finishDrop(왕복). drop 은 뒤 둘을 이은 것.

    /** 그 칸을 눌렀을 때 **끌기가 될 수 있는가**. 순수 조회다 — 문구도 로그도 상태 변화도 없다. */
    fun grab(square: ChessSquare): ChessDragGrab {
        val current = match ?: return ChessDragGrab.none
        val piece = current.position?.get(square) ?: return ChessDragGrab.none
        if (piece.color != current.myColor) return ChessDragGrab.none
        if (isBusy || !current.isMyTurn || targets(square).isEmpty()) return ChessDragGrab.stuck
        return ChessDragGrab.movable
    }

    /**
     * 말을 **끌기 시작한다**. 되면 그 말이 `selection` 이 되고 true. 거절 사다리는 [tap] 과 **같은 순서**다. `tap` 과 갈리는 곳은 하나다:
     * **이미 고른 말**을 끌면 해제하지 않고 그대로 끈다.
     */
    fun beginDrag(square: ChessSquare): Boolean {
        if (isBusy) { refuseTap(ChessTapRefusal.busy, square); return false }
        val current = match ?: run { refuseTap(ChessTapRefusal.noMatch, square); return false }
        if (current.isFinished) { refuseTap(ChessTapRefusal.finished, square); return false }
        val position = current.position ?: run { refuseTap(ChessTapRefusal.unreadableBoard, square); return false }
        if (!current.isMyTurn) { refuseTap(ChessTapRefusal.notYourTurn, square); return false }

        // INV-ChessStore-302e3f87 이식: 꼬리표는 **승격을 접을 때만** 지운다([tap] 과 같은 까닭) — 놓은 직후, 왕복이 시작되기 전의 틈에
        // 다른 말을 집는 끌기가 앞 수의 꼬리표를 지우면 그 수는 서버로 나가지 못한다.
        if (promotion != null) {
            promotion = null
            clearPendingDrop()
        }

        val piece = position[square] ?: run { refuseTap(ChessTapRefusal.emptySquare, square); return false }
        if (piece.color != current.myColor) { refuseTap(ChessTapRefusal.notMyPiece, square); return false }
        // 갈 곳 없는 말은 `select` 가 거절한다(탭과 같은 길).
        if (selection?.from != square) select(square)
        if (selection?.from != square) return false
        dragOrigin = square
        return true
    }

    /** 끌기를 거둔다(말을 제자리에). **고르기는 남는다**. */
    fun cancelDrag() {
        if (dragOrigin != null) dragOrigin = null
    }

    /**
     * 끌던 말을 **놓았다** — 놓기의 **동기 구간**. [target] 이 null 이면 판 밖이다. 보낼 수가 정해지면 그 수를 돌려준다(승격이면 null).
     * INV-ChessStore-4156426a 이식: **부른 그 자리에서 끝난다**(suspend 가 아니다) — 뗀 그 틱에 [pendingDrop] 이 서야 한다(미루면 한 장이
     * "끄는 말은 사라졌고 놓은 말은 아직 없는" 판으로 그려진다).
     * INV-ChessStore-89d91eb9 이식: **스스로 다시 검사한다** — 화면이 취소를 놓쳐도 수가 안 나가야 한다(탭과 같은 사다리 + 걸쇠·고르기가
     * **그 칸 그대로**인지). 걸쇠가 내려가 있으면 조용히 버린다.
     */
    fun placeDrop(from: ChessSquare, target: ChessSquare?): ChessMove? {
        val spot = target ?: from
        if (isBusy) { cancelDrag(); refuseTap(ChessTapRefusal.busy, spot); return null }
        // 앞서 놓은 수가 아직 보내기를 기다린다 — 그 틈에 두 번째 놓기가 꼬리표를 덮으면 두 수가 함께 사라진다. 왕복 중과 똑같이 거절한다.
        if (pendingDrop != null) { cancelDrag(); refuseTap(ChessTapRefusal.busy, spot); return null }
        val current = match ?: run { cancelDrag(); refuseTap(ChessTapRefusal.noMatch, spot); return null }
        if (current.isFinished) { cancelDrag(); refuseTap(ChessTapRefusal.finished, spot); return null }
        val position = current.position ?: run { cancelDrag(); refuseTap(ChessTapRefusal.unreadableBoard, spot); return null }
        if (!current.isMyTurn) { cancelDrag(); refuseTap(ChessTapRefusal.notYourTurn, spot); return null }

        // 걸쇠와 고르기. 둘 중 하나라도 그 칸이 아니면 이 놓기는 **이미 거둔 끌기**의 것이다.
        val selected = selection
        val piece = position[from]
        if (dragOrigin != from || selected == null || selected.from != from || piece == null || piece.color != current.myColor) {
            cancelDrag()
            log("drop ignored reason=drag-revoked square=${from.notation}")
            return null
        }
        // 놓았으니 끌기는 끝났다(어느 갈래로 가든).
        dragOrigin = null

        if (target == null) return null // 판 밖 — 조용히 돌아간다
        if (target == from) return null // 출발 칸에 도로 놓았다 — 수 없음
        val candidates = if (target in selected.targets) legalMoves(from, target) else emptyList()
        if (candidates.isEmpty()) {
            refuseTap(ChessTapRefusal.illegalTarget, target)
            return null
        }

        pendingDropRecord = ChessPendingDrop(current.id, current.plyCount, from, target, piece)
        selection = null
        if (candidates.size > 1 || candidates.any { it.promotion != null }) {
            // 승격 — 고르는 동안 폰은 도착 칸에 머문다(취소하면 `cancelPromotion` 이 꼬리표를 지운다).
            promotion = ChessPromotionPrompt(from, target)
            return null
        }
        return candidates[0]
    }

    /** [placeDrop] 이 돌려준 수를 보낸다. 답이 무엇이든 **남은 꼬리표를 걷는다**. */
    suspend fun finishDrop(move: ChessMove) {
        // 놓은 뒤 이 줄에 오기 전에 판이 바뀌었으면(읽는 자리가 이미 없는 것으로 읽는다) 보내지 않는다.
        val pending = pendingDrop
        if (pending == null || pending.from != move.from || pending.to != move.to) {
            clearPendingDrop()
            return
        }
        send(move)
        if (pendingDropRecord == pending) pendingDropRecord = null
    }

    /** 놓기 전체(동기 구간 + 왕복). 화면은 둘을 **따로** 부른다. */
    suspend fun drop(from: ChessSquare, target: ChessSquare?) {
        val move = placeDrop(from, target) ?: return
        finishDrop(move)
    }

    /** 놓은 말의 꼬리표를 지운다(말은 판이 말하는 자리로 돌아간다). */
    private fun clearPendingDrop() {
        if (pendingDropRecord != null) pendingDropRecord = null
    }

    // MARK: - 동작

    suspend fun challenge(userID: String) {
        if (isBusy || host?.session == null) return
        // §8-17 #1: 깃발이 꺼진 빌드는 신청 RPC 를 한 건도 내지 않는다.
        if (duelsLocked) {
            setNotice(ChessNoticeText.updateMine)
            return
        }
        val target = userID.lowercase()
        val stake = selectedStake.rawValue
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.chessChallenge(token, target, stake) }) {
                null -> return
                is CallResult.Failure ->
                    setNotice(if (isSchemaMissing(result.error)) ChessNoticeText.unavailable else ChessNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(ChessNoticeText.challenge(response.status, response.need, response.have))
                    if (response.status != ChessRPCStatus.ok) log("challenge refused status=${response.status.rawValue}")
                    when (response.status) {
                        ChessRPCStatus.ok -> {
                            val id = response.matchId?.lowercase() ?: return
                            val peer = users.firstOrNull { it.id == target }
                                ?: ChessUser(
                                    id = target, displayName = "", avatarURL = null, characterID = null,
                                    isWorking = true, isCapable = true, inMatch = false,
                                )
                            val expiresAt = deviceDate(response.inviteExpiresMs) ?: clock().addingTimeInterval(inviteTTLSeconds)
                            outgoingRevision += 1
                            outgoing = ChessInvite(id, peer, stake, expiresAt)
                            lastOutgoingRequestAt = clock()
                            scheduleInviteExpiry()
                        }
                        ChessRPCStatus.alreadyPending, ChessRPCStatus.busy -> refreshLobby()
                        // 목록의 칩이 틀렸다는 뜻이다 — 다시 읽어 행을 사실에 맞춘다.
                        ChessRPCStatus.targetBusy, ChessRPCStatus.targetOutdated, ChessRPCStatus.targetFocused -> refreshLobby()
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
            when (val result = perform { service, token -> service.chessCancel(token, id) }) {
                null -> return
                is CallResult.Failure ->
                    setNotice(if (isSchemaMissing(result.error)) ChessNoticeText.unavailable else ChessNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(ChessNoticeText.cancel(response.status))
                    when (response.status) {
                        ChessRPCStatus.ok, ChessRPCStatus.notFound, ChessRPCStatus.notPending, ChessRPCStatus.expired -> {
                            if (outgoing?.id == id) {
                                outgoing = null
                                scheduleInviteExpiry()
                            }
                            // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 진행 중 판을 찾아 온다.
                            if (response.status == ChessRPCStatus.notPending) refreshLobby()
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
            setNotice(ChessNoticeText.updateMine)
            return
        }
        val id = inviteID.lowercase()
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.chessRespond(token, id, accept) }) {
                null -> return
                is CallResult.Failure ->
                    setNotice(if (isSchemaMissing(result.error)) ChessNoticeText.unavailable else ChessNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(ChessNoticeText.respond(accept, response.status, response.side, response.need, response.have))
                    if (response.status != ChessRPCStatus.ok) log("respond refused status=${response.status.rawValue}")
                    when (response.status) {
                        ChessRPCStatus.ok -> {
                            if (incoming?.id == id) incoming = null
                            if (!accept) return
                            // 수락하는 순간 서버가 두 참가자의 **다른 대기 신청을 전부 거둔다**.
                            if (outgoing != null) outgoing = null
                            val state = response.state
                            if (state != null) applyState(state) else refreshMatch(id)
                            // 판이 열리면 `applyState` 가 창을 띄운다(경로와 무관하게 한 곳에서 알린다).
                            if (match?.id != id && !isWindowVisible) presentWindow?.invoke()
                        }
                        ChessRPCStatus.notFound, ChessRPCStatus.notPending, ChessRPCStatus.expired, ChessRPCStatus.invalid ->
                            if (incoming?.id == id) incoming = null
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    suspend fun resign() {
        if (isAIMatch) {
            resignAIMatch()
            return
        }
        val current = match
        if (isBusy || current == null || current.isFinished || host?.session == null) return
        val id = current.id
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.chessResign(token, id) }) {
                null -> return
                is CallResult.Failure ->
                    setNotice(if (isSchemaMissing(result.error)) ChessNoticeText.unavailable else ChessNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(ChessNoticeText.resign(response.status))
                    val state = response.state
                    if (state != null) applyState(state) else refreshMatch(id)
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /** 무승부 제안(체스에만 있는 왕복). AI 판에는 없다. 이미 선 판의 왕복이라 판돈 깃발과 무관하다. */
    suspend fun offerDraw() {
        val current = match
        if (isBusy || current == null || current.isFinished || isAIMatch || host?.session == null) return
        val id = current.id
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.chessOfferDraw(token, id) }) {
                null -> return
                is CallResult.Failure ->
                    setNotice(if (isSchemaMissing(result.error)) ChessNoticeText.unavailable else ChessNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(ChessNoticeText.offerDraw(response.status))
                    val state = response.state
                    if (state != null) applyState(state) else refreshMatch(id)
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /** 상대의 무승부 제안에 답한다. 수락이면 서버가 각자에게 판돈을 돌려주고 판을 `agreement` 로 닫는다. */
    suspend fun respondDraw(accept: Boolean) {
        val current = match
        if (isBusy || current == null || current.isFinished || isAIMatch || host?.session == null) return
        val id = current.id
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.chessRespondDraw(token, id, accept) }) {
                null -> return
                is CallResult.Failure ->
                    setNotice(if (isSchemaMissing(result.error)) ChessNoticeText.unavailable else ChessNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(ChessNoticeText.respondDraw(accept, response.status))
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
        if (!foldFinishedMatch() || host?.session == null) return
        launch {
            refreshLobby()
            loadRanking()
        }
    }

    /** 끝난 판을 내리고 화면을 로비로 돌린다. 요청은 쏘지 않는다. 끝난 판을 들고 있지 않으면 false. */
    private fun foldFinishedMatch(): Boolean {
        val current = match ?: return false
        if (!current.isFinished) return false
        dismissedMatchIDs = dismissedMatchIDs + current.id
        match = null // AI 판이면 대입이 AI 판을 버린다
        if (phase != ChessPhase.lobby) phase = ChessPhase.lobby
        cancelDrag()
        clearPendingDrop()
        setNotice(null)
        return true
    }

    // MARK: - 신호 · 계기 (창 밖에서 아는 유일한 길)
    //
    // INV-ChessStore-ff6ba08d 이식: 폴링은 `isWindowVisible` 을 요구한다(③). 그래서 체스 창이 닫혀 있으면 체스 요청이 **한 건도** 나가지
    // 않는다 — 아래 계기들이 없으면 (가) 받은 신청을 알 길이 전혀 없고(신청자는 "상대가 응답하지 않았어요"를 본다) (나) 진행 중 판에서 창을
    // 닫으면 "내 차례예요"가 한 번도 안 와 10분 시계가 그대로 흘러 판돈을 잃는다. 계기 하나로 모으는 것은 `refreshLobby()` 다.

    /** 실시간 'chess' 신호. 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다. */
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
                syncPendingTrailing = false
                syncOnce()
            } while (syncPendingTrailing && generation == resetGeneration)
            if (generation == resetGeneration) syncTask = null
        }
    }

    /** 신호 한 번의 조회: 진행 중 1:1 판이 있으면 그 판, 아니면 로비(신청 둘 + 진행 중 판 id). */
    suspend fun syncOnce() {
        val current = match
        if (current != null && !current.isFinished && !isAIMatch) refreshMatch(current.id) else refreshLobby()
    }

    /** 조인 직후·깨어남의 따라잡기: 로비 한 번(+ 그 응답이 가리키는 판). **`syncOnce` 가 아니다** — 그 사이 온 신청을 영영 모른다. */
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

    /** 팝오버 열림(30초 스로틀). */
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
     * 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다**. 진행 중 내 판이 상대 차례거나 깃발+유예가 지났으면 [statePollSeconds] 마다 상태 ·
     * 보낸 신청이 있으면 5초마다 그 판의 상태 · 로비를 보고 있으면 30초마다 목록 · 관전 2초 / 순위 60초. 분기 사이사이 `isWindowVisible` 을
     * 다시 본다 — 기다리는 중에 창이 내려갈 수 있다.
     */
    suspend fun pollTick(now: SwiftDate) {
        if (!isWindowVisible || isWindowOccluded || host?.session == null) return
        val current = match
        if (current != null && !current.isFinished && !isAIMatch) {
            val waiting = current.turn != current.myColor
            val overdue = current.isFlagOverdue(now, graceSeconds)
            if (waiting || overdue) {
                val subscribed = host?.realtimeState?.isSubscribed ?: false
                if (now.timeIntervalSince(lastStateRequestAt) >= statePollSeconds(subscribed)) refreshMatch(current.id)
            }
        }
        if (!isWindowVisible) return
        val sent = outgoing
        if (sent != null && now.timeIntervalSince(lastOutgoingRequestAt) >= outgoingPollSeconds) refreshMatch(sent.id)
        if (!isWindowVisible) return
        if (phase == ChessPhase.lobby && now.timeIntervalSince(lastLobbyRequestAt) >= lobbyPollSeconds) refreshLobby()
        if (!isWindowVisible) return
        pollSpectatorFeatures(now)
    }

    // MARK: - 초 단위 값 (잎 전용 — ⑥)

    /** 한쪽의 남은 시간(초). 잎이 `now` 를 넘겨 부르는 **순수 계산**이다. AI 판도 같은 문을 쓴다. */
    fun remainingSeconds(color: ChessColor, now: SwiftDate): Double? = match?.clock?.remainingSeconds(color, now)

    /** 내 시계 · 상대 시계 둘. */
    fun remainingSecondsPair(now: SwiftDate): Pair<Double, Double>? {
        val current = match ?: return null
        return current.clock.remainingSeconds(current.myColor, now) to current.clock.remainingSeconds(current.myColor.opponent, now)
    }

    // MARK: - 리셋

    /** 로그아웃·계정 전환. 창을 닫고 체스 상태를 전부 비운다. */
    fun reset() {
        resetGeneration += 1
        stopPolling()
        discardAIGame()
        expiryTask?.cancel()
        expiryTask = null
        // 신호 재조회도 끊는다 — 앞 계정의 따라잡기가 다음 사람의 화면에 신청·판을 세우면 안 된다.
        syncTask?.cancel()
        syncTask = null
        syncPendingTrailing = false
        stateInFlight = false
        stateAgain = false
        lobbyInFlight = false
        stateInFlightID = null
        pendingStateID = null
        if (phase != ChessPhase.lobby) phase = ChessPhase.lobby
        if (users.isNotEmpty()) users = emptyList()
        if (record != null) record = null
        if (selectedStake != ChessStake.three) selectedStake = ChessStake.three
        if (incoming != null) incoming = null
        if (outgoing != null) outgoing = null
        if (match != null) match = null
        if (selection != null) selection = null
        if (promotion != null) promotion = null
        cancelDrag()
        clearPendingDrop()
        if (notice != null) notice = null
        if (isBusy) isBusy = false
        if (isWindowVisible) isWindowVisible = false
        if (isRulesVisible) isRulesVisible = false
        if (rubyBalance != null) rubyBalance = null
        if (hiddenPeerIDs.isNotEmpty()) hiddenPeerIDs = emptySet()
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (hasLoadedLobby) hasLoadedLobby = false
        if (liveMatches.isNotEmpty()) liveMatches = emptyList()
        if (spectating != null) spectating = null
        if (ranking != null) ranking = null
        if (rankingLoadFailed) rankingLoadFailed = false
        if (hasLoadedRanking) hasLoadedRanking = false
        if (rankingUnavailable) rankingUnavailable = false
        if (watchUnavailable) watchUnavailable = false
        // 접힘도 로그아웃까지만 기억한다 — 다음 로그인은 서버가 올라왔을 수 있다(최악이 404 한 번).
        if (spectatorCountUnavailable) spectatorCountUnavailable = false
        if (spectatorCount != 0L) spectatorCount = 0
        watchRuntime.clear()
        val defaultInitial = ChessServerClock.initial.whiteMsLeft
        if (initialMs != defaultInitial) initialMs = defaultInitial
        if (incrementMs != 3_000L) incrementMs = 3_000L
        if (graceMs != 2_000L) graceMs = 2_000L
        serverClockOffset = 0.0
        hasServerClockOffset = false
        isWindowOccluded = false
        attentionKey = null
        shownResultIDs = emptySet()
        activeMatchID = null
        seenInviteIDs = emptySet()
        dismissedMatchIDs = emptySet()
        outgoingRevision = 0
        lobbyRequestOutgoingRevision = 0
        lastStateRequestAt = distantPast
        lastLobbyRequestAt = distantPast
        lastOutgoingRequestAt = distantPast
        lastMenuLobbyAt = distantPast
        inviteTTLSeconds = 60.0
        dismissWindow?.invoke()
    }

    // MARK: - 내부

    /** 공용 호출 관용구(Swift `perform`). 관전·순위 확장이 같은 관용구로 부른다. */
    internal suspend fun <T> perform(operation: suspend (SupabaseWorkService, String) -> T): CallResult<T>? =
        performDuelCall(host, { resetGeneration }, operation)

    /** 신청 한 건을 세운다(`pending` 상태 응답). 받은 것인지 보낸 것인지는 **내가 challenger 인가**로 가른다. */
    private fun applyInvite(row: ChessMatchRow, payload: ChessStatePayload, id: String) {
        val myID = host?.session?.userID?.lowercase() ?: return
        val stake = row.stake ?: return
        val expiresAt = deviceDate(row.inviteExpiresMs) ?: return
        val peer = peerUser(payload.opponent, inMatch = false) ?: return
        val invite = ChessInvite(id, peer, stake, expiresAt)
        if (row.challenger?.lowercase() == myID) {
            outgoing = steadyInvite(invite, outgoing)
        } else {
            val fresh = steadyInvite(invite, incoming)
            if (incoming != fresh) incoming = fresh
            if (id !in seenInviteIDs) {
                seenInviteIDs = seenInviteIDs + id
                // §8-17 #1: 잠긴 빌드는 수락 배너를 세우지 않는다(본 것으로만 적는다).
                if (!duelsLocked) onInviteArrived?.invoke(fresh)
            }
        }
        if (match?.id == id) clearMatch()
        scheduleInviteExpiry()
    }

    /** 그 id 가 판이었으면 판을 내리고, 신청이었으면 신청 카드를 걷는다(안내가 있으면 한 줄). */
    private fun dropMatchOrInvite(id: String, notice: String? = null) {
        if (match?.id == id) clearMatch()
        if (activeMatchID == id) activeMatchID = null
        if (incoming?.id == id) {
            incoming = null
            scheduleInviteExpiry()
        }
        if (outgoing?.id == id) {
            outgoing = null
            if (notice != null) setNotice(notice)
            scheduleInviteExpiry()
        }
    }

    /** 안내줄 한 문. 관전 확장이 not_found·준비 중 안내를 여기로 흘린다(순위 실패는 절대 부르지 않는다). */
    // 칸 `notice` 의 JVM 세터(setNotice)와 이름이 겹친다 — Swift 이름을 지키고 JVM 이름만 바꾼다.
    @JvmName("setNoticeIfChanged")
    fun setNotice(text: String?) {
        if (notice != text) notice = text
    }

    /** 탭 거절 하나를 **두 곳**에 남긴다: 상태줄 한 줄과 진단 한 줄(칸 이름과 사유만 — 닉네임·판 내용·판 id·토큰 금지). */
    internal fun refuseTap(refusal: ChessTapRefusal, square: ChessSquare) {
        ChessNoticeText.tapRefusal(refusal)?.let(::setNotice)
        log(
            "tap refused reason=${refusal.rawValue} square=${square.notation} turn=${match?.turn?.rawValue ?: "none"} " +
                "mine=${match?.myColor?.rawValue ?: "none"} busy=${if (isBusy) "true" else "false"}",
        )
    }

    private fun applyRuby(value: Long?) {
        if (value == null) return
        if (rubyBalance != value) rubyBalance = value
        val host = host
        if (host != null && host.rubyBalance != value) host.rubyBalance = value
    }

    fun clearMatch() {
        if (match != null) match = null
        if (phase != ChessPhase.lobby) phase = ChessPhase.lobby
        if (selection != null) selection = null
        if (promotion != null) promotion = null
        cancelDrag()
        clearPendingDrop()
    }

    /** 판 진행을 사람에게 알린다(진행 중 판을 옮긴 직후). 같은 (판 id, ply) 에는 말풍선 한 번뿐이다. */
    private fun noteMatchProgress(previous: ChessMatchState?, next: ChessMatchState, windowWasVisible: Boolean) {
        val started = previous == null || previous.isFinished || previous.id != next.id
        if (started) {
            presentWindow?.invoke()
            requestAttention?.invoke()
        }
        if (next.turn != next.myColor) return
        val arrived = started || previous?.turn != next.myColor || previous.plyCount != next.plyCount
        val key = "${next.id}#${next.plyCount}"
        if (!arrived || attentionKey == key) return
        attentionKey = key
        if (windowWasVisible) return
        onAttention?.invoke(
            ChessAttention(
                kind = if (started) ChessAttention.Kind.matchStarted else ChessAttention.Kind.myTurn,
                matchID = next.id, opponentName = next.opponent.displayName, plyCount = next.plyCount,
            ),
        )
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

    /** 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다. */
    fun scheduleInviteExpiry() {
        expiryTask?.cancel()
        expiryTask = null
        val earliest = listOfNotNull(incoming?.expiresAt, outgoing?.expiresAt).minOrNull() ?: return
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

    fun pruneExpiredInvites(now: SwiftDate) {
        val invite = incoming
        if (invite != null && invite.expiresAt <= now) incoming = null
        val sent = outgoing
        if (sent != null && sent.expiresAt <= now) {
            outgoing = null
            setNotice(ChessNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /** 사람 행 → ChessUser(상대·관전의 두 사람). 행에 없는 칸은 로비 목록에서 빌린다. 서버 어휘 → 화면 글자는 **이 함수와 [user] 두 곳뿐**이다. */
    fun peerUser(row: ChessUserRow?, inMatch: Boolean): ChessUser? {
        if (row == null) return null
        val id = row.userId?.lowercase()
        if (id.isNullOrEmpty()) return null
        val known = users.firstOrNull { it.id == id }
        return ChessUser(
            id = id,
            displayName = row.displayName ?: known?.displayName ?: "",
            avatarURL = row.avatarUrl ?: known?.avatarURL,
            characterID = row.character ?: known?.characterID,
            isWorking = row.isWorking ?: known?.isWorking ?: true,
            isCapable = row.capable ?: known?.isCapable ?: true,
            inMatch = row.inMatch ?: inMatch,
            center = CenterLabel.display(row.center) ?: known?.center,
        )
    }

    /** 로비 "지금 대결 중" 한 줄 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**. */
    fun liveMatch(row: ChessLobbyMatchRow): ChessLiveMatch? {
        val id = row.matchId?.lowercase()
        if (id.isNullOrEmpty()) return null
        val a = peerUser(row.a, inMatch = true) ?: return null
        val b = peerUser(row.b, inMatch = true) ?: return null
        val stake = ChessStake.fromRawValue(row.stake) ?: return null
        val startedAt = deviceDate(row.startedMs) ?: return null
        // 안 싣는 서버면 0 — 카드는 그냥 눈 아이콘을 안 그린다(없는 숫자를 지어내지 않는다).
        return ChessLiveMatch(id, a, b, stake, startedAt, watchers = nonNegative(row.watchers))
    }
}
