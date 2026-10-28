// 원본: Sources/CheckCore/GomokuStore.swift:538-2415(스토어 본문) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.gomokuCancel
import com.yehsung.aingcheck.core.net.gomokuChallenge
import com.yehsung.aingcheck.core.net.gomokuChatMute
import com.yehsung.aingcheck.core.net.gomokuChatSend
import com.yehsung.aingcheck.core.net.gomokuInbox
import com.yehsung.aingcheck.core.net.gomokuLeave
import com.yehsung.aingcheck.core.net.gomokuLobby
import com.yehsung.aingcheck.core.net.gomokuMove
import com.yehsung.aingcheck.core.net.gomokuRespond
import com.yehsung.aingcheck.core.net.gomokuResign
import com.yehsung.aingcheck.core.net.gomokuState
import com.yehsung.aingcheck.core.rules.ai.GomokuAIGame
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuJudgement
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuRules
import com.yehsung.aingcheck.core.rules.renju.GomokuTapRefusal
import com.yehsung.aingcheck.core.rules.renju.GomokuTurnWarning
import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.MessageBody
import com.yehsung.aingcheck.core.wire.MessageBodyValidation
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.GomokuChatBody
import com.yehsung.aingcheck.core.wire.games.GomokuChatKind
import com.yehsung.aingcheck.core.wire.games.GomokuChatRow
import com.yehsung.aingcheck.core.wire.games.GomokuInboxResponse
import com.yehsung.aingcheck.core.wire.games.GomokuInviteRow
import com.yehsung.aingcheck.core.wire.games.GomokuLobbyMatchRow
import com.yehsung.aingcheck.core.wire.games.GomokuLobbyResponse
import com.yehsung.aingcheck.core.wire.games.GomokuRPCStatus
import com.yehsung.aingcheck.core.wire.games.GomokuStatePayload
import com.yehsung.aingcheck.core.wire.games.GomokuUserRow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException
import kotlin.jvm.JvmName
import kotlin.math.abs

// 1:1 오목 대결 스토어(v0.3.27) — 화면 상태 · 서버 동기화 · 안전망 폴링 · RPC 호출.
//
// ── 이 파일이 지키는 규칙(Swift 머리 주석 그대로) ──
//  ① **서버가 권위다.** 대국 판·차례·마감·결과·루비는 전부 RPC 응답으로만 바뀐다. 낙관적 착수·낙관적 차감은 없다.
//  ② **시각은 서버 시계로 보정한다.** 마감·신청 만료는 서버 epoch ms 로 오고, 같은 응답의 server_now_ms 와의 차이로 기기 시계 어긋남을 지운다.
//  ③ **폴링은 창이 보일 때만 돈다**(무료 플랜 예산). 창이 안 보이면 받은 신청은 신호·따라잡기·근무 시작·깨어남에서만 본다.
//  ④ **늦게 온 응답은 버린다.** 로그아웃·계정 전환(host.sessionGeneration)과 이 스토어의 reset(resetGeneration) 두 세대를 모두 대조한다.
//     채팅에는 세대가 하나 더 있다(chatGeneration).
//  ⑤ **사용자 문구는 GomokuNoticeText 한 곳에만 있다.**
//  ⑥ **초 단위 값은 화면의 잎만 읽는다.** remainingSeconds(now) 는 순수 계산이고, 이 스토어는 매초 아무것도 대입하지 않는다.
//
// Kotlin 몫(C§2.4): Swift `@MainActor @Observable` → 한 스레드 디스패처의 [scope] + `mutableStateOf`. `@ObservationIgnored` → 보통 var.
// `Task { }` → `scope.launch`, `Task.sleep` → `delay`(시험은 가상 시간). 벽시계는 호스트가 준다(구조 시험 R2).
//
// ── §8-17 #1(판돈 대결 Android 빌드 깃발) ──
// 앱 구성 `duelsEnabled` 가 꺼진 빌드는 **신청·수락 진입을 스토어에서 막는다**: `challenge`·`respond(accept = true)`·`rematch`(1:1) 는
// RPC 를 한 건도 내지 않고 안내 한 줄만 남긴다. 받은 신청은 서버 사실(`incoming`) 그대로 두되 배너·점(`bannerInvite`·`pendingIncomingInvites`)
// 에서 빼고 [incomingFoldedNotice] 한 줄("앱을 업데이트해야 대결할 수 있어요")로 접는다. AI 대국·관전·순위·진행 중 판(다른 기기에서 수락한 판)은
// 깃발과 무관하다. 깃발은 [GomokuStoreHost.appConfig] 한 문으로만 읽는다.

/** 공용 호출 결과(Swift `Result<T, any Error>`). null(버린 결과)과 구별된다. */
internal sealed interface CallResult<out T> {
    data class Success<T>(val value: T) : CallResult<T>
    data class Failure(val error: Throwable) : CallResult<Nothing>
}

/** 서버에 함수가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창). */
internal fun isSchemaMissing(error: Throwable): Boolean = error == SupabaseWorkServiceError.DatabaseSchemaMissing

/**
 * 공용 호출 관용구(Swift `perform`): 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조. null = 버린 결과(세션 없음·세대가 밀림·취소).
 * 호출부는 null 이면 **아무것도 바꾸지 않는다.** [currentGeneration] 은 그 스토어의 resetGeneration 을 읽는다.
 */
internal suspend fun <T> performDuelCall(
    host: GomokuStoreHost?,
    currentGeneration: () -> Int,
    operation: suspend (SupabaseWorkService, String) -> T,
): CallResult<T>? {
    if (host == null || host.session == null) return null
    val sessionGeneration = host.sessionGeneration
    val generation = currentGeneration()
    val service = host.service
    return try {
        val value = host.withSessionRetry { session -> operation(service, session.accessToken) }
        if (host.sessionGeneration != sessionGeneration || generation != currentGeneration()) null else CallResult.Success(value)
    } catch (error: Exception) {
        // 이 코루틴 자신이 취소됐으면 취소를 다시 던진다(구조적 동시성 — Swift `case .cancelled: return nil` 의 Kotlin 몫).
        if (error is CancellationException) currentCoroutineContext().ensureActive()
        when {
            host.sessionGeneration != sessionGeneration || generation != currentGeneration() -> null
            host.classifyAuthError(error) == AuthErrorDisposition.cancelled -> null
            else -> CallResult.Failure(error)
        }
    }
}

class GomokuStore(
    /** 스토어가 일을 띄우는 범위(앱은 `Dispatchers.Main.immediate` 한 줄기, 시험은 시험 디스패처 — C§2.4). */
    val scope: CoroutineScope,
    host: GomokuStoreHost? = null,
) {
    companion object {
        /** 상대 차례의 대국 상태 안전망 조회 주기(초) — 실시간 구독 중. */
        const val statePollSecondsWhileSubscribed: Double = 3.0
        /** 같은 조회 — 미구독(킬스위치·재연결 중). 신호가 없으니 더 촘촘하다. */
        const val statePollSecondsUnsubscribed: Double = 1.5
        /** 내 대기 신청이 있을 때 받은 쪽의 응답을 보는 주기(초). */
        const val outgoingInboxPollSeconds: Double = 5.0
        /** 결과 화면의 끝난 판 **끝인사** 안전망 조회 주기(초) — 구독 중. 주 경로는 초인종(`syncOnce`)이다. */
        const val finishedChatPollSecondsWhileSubscribed: Double = 10.0
        /** 같은 조회 — 미구독. */
        const val finishedChatPollSecondsUnsubscribed: Double = 5.0
        /** 그 안전망을 돌리는 길이(초) — 서버 `gomoku_chat_grace_seconds()`(120) 에 여유를 얹었다. */
        const val finishedChatWindowSeconds: Double = 130.0
        /** 로비 목록 재조회 주기(초). */
        const val lobbyPollSeconds: Double = 30.0
        /** 팝오버를 열 때 받은 신청을 보는 스로틀(초). */
        const val menuInboxThrottleSeconds: Double = 60.0
        /** 연속 자동 착수 몇 번에 판을 잃는가의 **폴백**(서버가 로비 `auto_abandon_streak` 로 말하면 그 값). */
        const val autoPlaceLossStreak: Int = 3
        /** 서버가 턴 제한에 더하는 네트워크 유예(초). 서버 `gomoku_turn_grace_seconds()` 와 같은 값. */
        const val turnGraceSeconds: Double = 2.0
        /** 창 열기와 창 표시가 같은 조회를 두 번 쏘지 않게 하는 간격(초). */
        const val reloadDedupeSeconds: Double = 1.0
        /** 서버 시계 오프셋을 다시 재는 문턱(초). */
        const val serverClockToleranceSeconds: Double = 0.25
        /** 같은 신청을 다시 읽었을 때 만료가 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초). */
        const val inviteExpiryToleranceSeconds: Double = 1.0
        /** 같은 차례를 다시 읽었을 때 마감이 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초). */
        const val deadlineToleranceSeconds: Double = 0.5
        /** 관전 중 판 재조회 주기(초, 0.3.41). */
        const val watchPollSeconds: Double = 2.0
        /** 로비를 보고 있는 동안 순위표 재조회 주기(초, 0.3.41). */
        const val rankingPollSeconds: Double = 60.0
        /** throw 실패(5xx·오프라인)가 이만큼 연속되면 관전을 내리고 연결 안내를 남긴다(GomokuStoreWatch.swift). */
        const val watchFailureLimit: Int = 3

        internal const val LOG_TAG: String = "gomoku"

        /** 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다(관찰자를 깨우지 않게). */
        fun steadyInvite(fresh: GomokuInvite, previous: GomokuInvite?): GomokuInvite {
            if (previous == null || previous.id != fresh.id || previous.stake != fresh.stake || previous.peer != fresh.peer ||
                abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) >= inviteExpiryToleranceSeconds
            ) return fresh
            return previous
        }

        /** 판이 **막 끝났는가**(v0.3.64) — 새 판이 끝났고, 같은 판의 끝난 모양을 이미 들고 있던 게 아니다. */
        fun matchJustFinished(old: GomokuMatchState?, new: GomokuMatchState?): Boolean {
            if (new == null || !new.isFinished) return false
            return !(old?.id == new.id && old.isFinished)
        }

        /** 판 상태 변화 한 줄(없으면 null). 수·차례·끝남·판 교체만 본다. */
        fun matchTransitionLine(old: GomokuMatchState?, new: GomokuMatchState?): String? {
            fun turn(m: GomokuMatchState?): String = m?.turn?.rawValue ?: "none"
            fun moves(m: GomokuMatchState?): String = m?.moveCount?.toString() ?: "-"
            fun finished(m: GomokuMatchState?): Boolean = m?.isFinished ?: false
            val sameMatch = old?.id == new?.id
            if (sameMatch && moves(old) == moves(new) && turn(old) == turn(new) && finished(old) == finished(new)) return null
            return "state moves=${moves(old)}→${moves(new)} turn=${turn(old)}→${turn(new)} " +
                "finished=${finished(new)} sameMatch=$sameMatch"
        }

        /** 서버 사람 행 → GomokuUser(로비). `capable` 이 null 이면 **불가**다. */
        fun user(from: GomokuUserRow): GomokuUser? {
            val id = from.userId?.lowercase()
            if (id.isNullOrEmpty()) return null
            return GomokuUser(
                id = id,
                displayName = from.displayName ?: "",
                avatarURL = from.avatarUrl,
                characterID = from.character,
                isWorking = from.isWorking ?: false,
                isCapable = from.capable ?: false,
                inMatch = from.inMatch ?: false,
                center = CenterLabel.display(from.center),
            )
        }

        /**
         * 로비 정렬: 도전할 수 있는 사람(근무 중·가능·대국 아님) → 근무 중·가능(대국 중) → 근무 중 → 나머지, 그 안은 이름순
         * (Swift `localizedStandardCompare` = W1-c [NaturalKoCollation]). 같으면 들어온 순서(안정 정렬 — Swift 의 offset 비교).
         */
        fun sortedForLobby(users: List<GomokuUser>): List<GomokuUser> {
            fun rank(user: GomokuUser): Int = when {
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
    var host: GomokuStoreHost? = host
        private set

    /** 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다. */
    fun attach(host: GomokuStoreHost) {
        this.host = host
    }

    // MARK: 화면 상태 — 전부 public set(렌더 시험이 직접 채운다)

    var phase: GomokuPhase by mutableStateOf(GomokuPhase.lobby)
    var users: List<GomokuUser> by mutableStateOf(emptyList())
    var record: GomokuRecord? by mutableStateOf(null)
    var selectedStake: GomokuStake by mutableStateOf(GomokuStake.three)
    var incoming: List<GomokuInvite> by mutableStateOf(emptyList())
    var outgoing: GomokuInvite? by mutableStateOf(null)

    private var matchCell by mutableStateOf<GomokuMatchState?>(null)

    /** 지금 판. 대입마다 Swift `didSet` 몫([matchDidChange])이 돈다 — 같은 값을 다시 넣어도 돈다(Swift 와 같다). */
    var match: GomokuMatchState?
        get() = matchCell
        set(value) {
            val old = matchCell
            matchCell = value
            matchDidChange(old, value)
        }

    /** 지금 AI 대국(로컬 판). 서버 판과 섞이지 않는다 — GomokuStoreAI.kt 머리 주석. */
    var aiGame: GomokuAIGame? by mutableStateOf(null)
        internal set
    /** AI 갈래 장부(선택기·작업·세대). 관찰 대상이 아니다. */
    val aiRuntime: GomokuAIRuntime = GomokuAIRuntime()
    /** 탭 순간 화면이 본 판과 스토어 판이 달랐던 횟수(진단·시험 지점). */
    var tapDivergenceCount: Int = 0
        private set
    /** 사용자 어휘 안내 한 줄. */
    var notice: String? by mutableStateOf(null)
    var isBusy: Boolean by mutableStateOf(false)
    var isWindowVisible: Boolean by mutableStateOf(false)
    var isRulesVisible: Boolean by mutableStateOf(false)
    /** 서버 응답으로만 갱신(host 에도 반영). */
    var rubyBalance: Long? by mutableStateOf(null)
    /** 한 수 제한(초). 서버 로비 응답이 말해 주면 그 값, 아니면 설계값 30. */
    var turnSeconds: Long by mutableStateOf(30L)
    /** 마지막 상대 목록 조회가 실패했다. 빈 목록을 "상대가 없다"로 보여 주지 않기 위한 값이다. */
    var lobbyLoadFailed: Boolean by mutableStateOf(false)
    /** 이번 로그인에서 상대 목록을 한 번이라도 받았다. */
    var hasLoadedLobby: Boolean by mutableStateOf(false)
    /** 마지막 받은함 조회가 실패했다(오프라인·5xx·거절 응답). 빈 `incoming` 을 "받은 신청이 없다"로 보여 주지 않기 위한 값이다. */
    var inboxLoadFailed: Boolean by mutableStateOf(false)
    /** 이번 로그인에서 받은함을 한 번이라도 받았다. */
    var hasLoadedInbox: Boolean by mutableStateOf(false)
    /** 로비 "지금 대결 중" 목록. **서버 순서를 그대로 쓴다**(accepted_at desc). 옛 서버(키 없음)면 빈 배열. */
    var liveMatches: List<GomokuLiveMatch> by mutableStateOf(emptyList())

    // MARK: 관전 · 순위 (0.3.41) — 저장 칸만 여기, 로직은 GomokuStoreWatch.kt · GomokuStoreRanking.kt

    /**
     * **순위 적재·관전 폴링의 주 스위치. 기본 false.** 이 스토어는 폰도 그대로 쓰는 공용 타입이라, 창 표시·pollTick 에 순위·관전 조회를 무조건
     * 얹으면 그리지도 않는 폰이 `gomoku_ranking` 을 1분마다 당긴다(무료 플랜 예산). 켜는 곳은 배선(조립 지점)뿐이다.
     */
    var spectatorFeaturesEnabled: Boolean by mutableStateOf(false)
    /** 지금 관전 중인 판. null 이 아니면 로비 자리에 관전 화면이 선다(`phase` 는 lobby 그대로). */
    var spectating: GomokuSpectateState? by mutableStateOf(null)
    /** 마지막으로 받은 순위표. 실패해도 들고 있던 값은 지우지 않는다. */
    var ranking: GomokuRankingBoard? by mutableStateOf(null)
    /** 마지막 순위 조회가 실패했다(5xx·오프라인). **안내줄(notice)로 새지 않는다**. */
    var rankingLoadFailed: Boolean by mutableStateOf(false)
    /** 이번 로그인에서 순위를 한 번이라도 받았다(실패로 접힌 `rankingUnavailable` 도 "받은 것"으로 센다). */
    var hasLoadedRanking: Boolean by mutableStateOf(false)
    /** 서버에 순위 함수가 아직 없다(PGRST202). 화면은 "순위는 곧 열려요"로 접는다. */
    var rankingUnavailable: Boolean by mutableStateOf(false)

    /**
     * 서버에 `gomoku_watch` 가 없다. **관전 입구를 잠그는 신호는 이것뿐이다.**
     * INV-GomokuStore-8e7c75a1 이식: `rankingUnavailable` 과 **따로** 둔다 — 한 깃발이 "순위표가 없다"와 "관전이 없다"를 겸업하다 한쪽을
     * 좁히는 순간 [관전] 칩 게이트가 신호를 잃었다(2026-10-01 실측 — 누를 때마다 404 무한 반복). 세우는 곳은 `noteWatchFailure` 의
     * databaseSchemaMissing 갈래 **하나**(조건 없음), 내리는 곳은 관전이 실제로 성공한 순간(`applyWatch` ok)과 `reset` 이다.
     */
    var watchUnavailable: Boolean by mutableStateOf(false)

    /**
     * 서버에 `gomoku_watch_live`(관전 + 관전자 수)가 아직 없다 — 이 로그인 동안 옛 `gomoku_watch` 로 접어 쓴다.
     * INV-GomokuStore-ee57e6e5 이식: 바로 위 [watchUnavailable] 과 **절대 같은 깃발을 쓰지 않는다** — 저 깃발은 관전 입구를 통째로 잠근다.
     * 관전자 수가 없는 것과 관전을 못 하는 것은 **다른 사실**이다. 세우는 곳은 `watchFetch` 의 PGRST202 갈래 하나, 내리는 곳은 `reset` 하나다.
     */
    var spectatorCountUnavailable: Boolean by mutableStateOf(false)

    /**
     * 지금 보고 있는 판(관전) 또는 내가 두고 있는 판의 **관전자 수**. 0 이면 화면은 아무것도 그리지 않는다. 한 칸인 까닭: 관전과 대국은
     * 동시에 설 수 없다. 세우는 곳은 `applyWatch`·`applyState` 둘이고, 0 으로 되돌리는 곳은 `stopWatching`·`match` 대입·`reset` 이다.
     */
    var spectatorCount: Long by mutableStateOf(0L)
    /** 관전·순위 장부(요청 시각·in-flight·세대). 관찰 대상이 아니다. */
    val watchRuntime: GomokuWatchRuntime = GomokuWatchRuntime()

    /** 관전 중인가(로비 자리에 관전 화면이 서 있다). */
    val isSpectating: Boolean get() = spectating != null

    /** 순위·관전 조회가 **지금** 나가도 되는가 — 주 스위치 + 창이 보이고 안 가려짐 + 세션. 두 폴링 분기가 이 한 술어를 쓴다. */
    val canPollSpectatorFeatures: Boolean
        get() = spectatorFeaturesEnabled && isWindowVisible && !isWindowOccluded && host?.session != null

    // MARK: 자동 착수 (v0.3.28) — 시간 초과는 패배가 아니라 **무작위 대리 착수**다

    /** 내가 **연속으로** 자동 착수당한 횟수. 직접 한 수라도 두면 0으로 돌아간다(서버가 센다). */
    var myAutoStreak: Int by mutableStateOf(0)
    var opponentAutoStreak: Int by mutableStateOf(0)
    /** 판을 잃는 연속 횟수. **서버가 말한 값**(로비 `auto_abandon_streak`)이고, 아직 못 받았으면 폴백이다. */
    var autoAbandonStreak: Int by mutableStateOf(autoPlaceLossStreak)

    /** 지금 내 연속 횟수에 대한 경고 한 줄(없으면 null). **서버가 말한 임계값으로 판정한다**. */
    val autoStreakWarning: String? get() = GomokuNoticeText.autoStreakWarning(myAutoStreak, lossStreak = autoAbandonStreak)

    // MARK: 채팅 상태 (v0.3.28) — **`isBusy` 를 쓰지 않는다**

    /** 지금 판의 대화(오래된 것 → 최신). 판이 바뀌면 비운다. */
    var chat: List<GomokuChatMessage> by mutableStateOf(emptyList())
    /** 판의 채팅 발급 번호 = **다음 요청의 since**. 서버가 말한 값이고 역행하지 않는다. */
    var chatSeq: Long by mutableStateOf(0L)
    /** **내가** 이 판 채팅을 껐다. 서버가 아는 판 상태다(내 화면 설정이 아니다). */
    var isMuted: Boolean by mutableStateOf(false)
    /** **상대가** 껐다. */
    var isOpponentMuted: Boolean by mutableStateOf(false)
    /** 상대 앱이 채팅을 받을 수 있는 버전인가(서버 `chat_capable`). **모르면 받을 수 있다고 본다**. */
    var opponentChatCapable: Boolean by mutableStateOf(true)
    /** 입력칸의 글. 비우는 자리는 **전송 성공**과 판이 바뀔 때 둘뿐이다. */
    var chatDraft: String by mutableStateOf("")
    /** 채팅 전용 안내 한 줄(실패만). */
    var chatNotice: String? by mutableStateOf(null)
    /** **`isBusy` 와 별개다.** 채팅 왕복이 착수·기권 버튼을 잠그면 한 수 30초짜리 판에서 그건 곧 패배다. */
    var isSendingChat: Boolean by mutableStateOf(false)
    /** 한 줄 상한. 서버가 `chat_max_len` 을 말해 주면 그 값으로 간다. */
    var chatMaxLength: Long by mutableStateOf(GomokuChatBody.maxLength)

    /** 지금 입력칸에 있는 글의 길이(코드포인트 — 서버 `char_length` 와 같은 눈금). */
    val chatDraftLength: Int get() = MessageBody.length(chatDraft, RulesWireTextRules)

    /** 지금 채팅을 보낼 수 있는가. **시계를 읽지 않는다**(끝난 판의 인사 유예는 서버가 잰다). */
    val canSendChatNow: Boolean
        get() {
            if (isSendingChat || match == null) return false
            return GomokuChatBody.validate(chatDraft, RulesWireTextRules, chatMaxLength) is MessageBodyValidation.Ok
        }

    // MARK: §8-17 #1 — 판돈 대결 진입 깃발

    /** 이 빌드의 앱 구성. 호스트가 없으면(미리보기) 기본값(깃발 꺼짐). */
    val appConfig: AppConfig get() = host?.appConfig ?: AppConfig()

    /** 판돈 대결의 신청·수락 진입이 이 빌드에서 잠겼는가(`duelsEnabled` 꺼짐). AI 대국·관전·순위는 이 값을 보지 않는다. */
    val duelsLocked: Boolean get() = !appConfig.duelsEnabled

    /** 잠긴 빌드에서 받은 신청을 접는 한 줄(받은 신청이 있을 때만). 화면은 수락·거절 단추 대신 이 줄을 그린다. */
    val incomingFoldedNotice: String?
        get() = if (duelsLocked && visibleIncoming.isNotEmpty()) GomokuNoticeText.updateMine else null

    /**
     * 만료되지 않은 받은 신청 전부(만료가 이른 것부터). **시계를 읽지 않는다** — 만료된 신청은 스토어가 만료 시각에 걷어낸다.
     * 잠긴 빌드에서는 비어 있다 — 수락할 수 없는 신청으로 배너·점이 서지 않게(§8-17 #1, 접힌 줄은 [incomingFoldedNotice]).
     */
    val pendingIncomingInvites: List<GomokuInvite>
        get() {
            if (duelsLocked) return emptyList()
            return visibleIncoming.sortedWith { lhs, rhs ->
                if (lhs.expiresAt != rhs.expiresAt) lhs.expiresAt.compareTo(rhs.expiresAt) else lhs.id.compareTo(rhs.id)
            }
        }

    /** 배너·말풍선이 쓰는 대표 신청(만료 안 된 받은 신청 중 가장 오래된 것). **시계를 읽지 않는다**. 잠긴 빌드에서는 null. */
    val bannerInvite: GomokuInvite?
        get() {
            if (duelsLocked) return null
            var best: GomokuInvite? = null
            for (invite in visibleIncoming) {
                val current = best
                if (current == null || invite.expiresAt < current.expiresAt) best = invite
            }
            return best
        }

    // MARK: 차단으로 걷어낸 상대

    /** 이 기기에서 방금 차단해 **화면에서 걷어낸** 상대들(소유자가 채운다). 코어 목록(`users`·`incoming`)은 서버가 답한 그대로 둔다. */
    var hiddenPeerIDs: Set<String> by mutableStateOf(emptySet())

    /** 로비 상대 목록(화면용) — 차단으로 걷어낸 사람을 뺀다. */
    val visibleUsers: List<GomokuUser>
        get() = if (hiddenPeerIDs.isEmpty()) users else users.filter { it.id !in hiddenPeerIDs }

    /** 받은 신청(화면용) — 차단으로 걷어낸 사람이 보낸 것을 뺀다. */
    val visibleIncoming: List<GomokuInvite>
        get() = if (hiddenPeerIDs.isEmpty()) incoming else incoming.filter { it.peer.id !in hiddenPeerIDs }

    // MARK: 화면 갈래가 조립 지점에서 물리는 문

    /** 창(화면) 띄우기. */
    var presentWindow: (() -> Unit)? = null
    /** 새 받은 신청(처음 본 id 한 번). 잠긴 빌드에서는 부르지 않는다(§8-17 #1 — 수락할 수 없는 배너를 세우지 않는다). */
    var onInviteArrived: ((GomokuInvite) -> Unit)? = null
    /** 창 닫기. reset() 이 부른다 — 로그아웃한 뒤 앞 계정의 판이 떠 있으면 안 된다. */
    var dismissWindow: (() -> Unit)? = null
    /** 판이 막 시작됐다 — 앱이 앞에 없으면 사용자의 주의를 끈다. */
    var requestAttention: (() -> Unit)? = null
    /** 창이 안 보이는 동안 차례가 나에게 왔다(같은 판 id·기록 수에 한 번). */
    var onAttention: ((GomokuAttention) -> Unit)? = null
    /** v0.3.64: 내 1:1 판이 끝난 것을 **처음 본** 순간 한 번 부른다(일일 미션 재조회 고리). AI 판은 부르지 않는다. */
    var onMatchFinished: (() -> Unit)? = null

    // MARK: 내부 장부 (관찰 대상 아님)

    /** 이 스토어의 '지금'. 시험이 갈아 끼운다. 기본은 호스트의 시계다(벽시계는 조립 지점에서만 — 구조 시험 R2). */
    var clock: () -> SwiftDate = { this.host?.now() ?: SwiftDate.fromReferenceDate(0.0) }
    /** 폴링 루프의 한 걸음(초). */
    var pollStepSeconds: Double = 0.5
    /** 서버 시계 − 기기 시계(초). server_now_ms 가 올 때마다 갱신한다. */
    var serverClockOffset: Double = 0.0
        private set
    private var hasServerClockOffset = false
    var resetGeneration: Int = 0
        private set
    /** 창이 가려졌다. **폴링만** 이 값을 본다. */
    var isWindowOccluded: Boolean = false
        internal set
    var stateInFlightID: String? = null
        private set
    private var pendingStateID: String? = null
    private var attentionKey: String? = null
    /** 결과 화면을 한 번이라도 세운 끝난 판(받은함 last_finished 로 같은 결과를 다시 세우지 않는다). */
    var shownResultIDs: Set<String> = emptySet()
        private set
    /** 보낸 신청을 이 기기에서 새로 세울 때마다 오른다. 그보다 **먼저** 나간 받은함 응답이 방금 보낸 신청을 지우지 않게 한다. */
    private var outgoingRevision = 0
    private var inboxRequestOutgoingRevision = 0
    /** 서버가 말한 내 진행 중 대국 id(로비·인박스·상태 응답). */
    var activeMatchID: String? = null
        private set
    /** onInviteArrived 를 이미 부른 받은 신청 id. */
    var seenInviteIDs: Set<String> = emptySet()
        private set
    /** [로비로] 로 접은 끝난 판. 늦게 온 그 판의 상태 응답이 사용자를 결과 화면으로 끌고 가지 않게 한다. */
    var dismissedMatchIDs: Set<String> = emptySet()
        private set
    /** 이 기기에서 이미 "나갔다"고 서버에 말한 판. */
    var leftMatchIDs: Set<String> = emptySet()
        private set
    var pollTask: Job? = null
        private set
    private var pollToken = 0
    var syncTask: Job? = null
        private set
    private var syncPendingTrailing = false
    private var expiryTask: Job? = null
    private var stateInFlight = false
    private var stateAgain = false
    private var inboxInFlight = false
    private var inboxAgain = false
    private var lobbyInFlight = false
    var lastStateRequestAt: SwiftDate = distantPast
    var lastInboxRequestAt: SwiftDate = distantPast
    var lastLobbyRequestAt: SwiftDate = distantPast
    private var lastMenuInboxAt: SwiftDate = distantPast
    private var inviteTTLSeconds: Double = 60.0
    /** 지금 들고 있는 대화가 **어느 판의 것인가**. 다른 판의 상태가 오면 이 값이 달라 대화를 비운다. */
    var chatMatchID: String? = null
        private set
    /** 채팅을 **처음부터 다시 받아야 한다**(구멍 · 음소거 뒤집힘). 내리는 것은 그 전체를 실어 온 응답이다. */
    private var chatWantsFull = false
    /** 음소거 토글마다 오른다. 토글 **전에** 나간 조회의 응답을 통째로 버리기 위한 세대다. */
    var chatGeneration: Int = 0
        private set
    /** 끝인사 안전망(`pollTick`)이 보는 창: 결과 화면이 선 판과 그 조회를 그만둘 시각. */
    var finishedChatWatch: Pair<String, SwiftDate>? = null
        private set
    private var lastOpponent: GomokuUser? = null
    private var lastStake: Long? = null

    private fun log(message: String) = host.notice(LOG_TAG, message)

    private fun launch(block: suspend CoroutineScope.() -> Unit): Job = scope.launch(block = block)

    // MARK: - match 대입(Swift didSet)

    private fun matchDidChange(oldValue: GomokuMatchState?, newValue: GomokuMatchState?) {
        // 수·차례·끝남이 바뀔 때만 한 줄 남긴다(v0.3.31 진단). 같은 값을 다시 넣는 되맞춤은 조용하다.
        matchTransitionLine(oldValue, newValue)?.let(::log)
        if (matchJustFinished(oldValue, newValue) && !isAIMatch) onMatchFinished?.invoke()
        // AI 판은 `match` 가 그 판 id 를 들고 있는 동안만 산다 — 1:1 판이 열리거나 판이 내려가면 버린다(GomokuStoreAI.kt).
        val game = aiGame
        if (game != null && match?.id != game.id) discardAIGame()
        // 내 판이 섰으면(끝난 판 포함) 관전은 내려간다. 세대를 올려 나가 있던 관전 응답도 함께 버린다.
        if (match != null && spectating != null) {
            spectating = null
            watchRuntime.bumpWatchGeneration()
        }
        // 판이 내려갔다 — 남의 숫자가 로비 화면에 남지 않게 여기서 0 으로 돌린다.
        if (match == null && spectatorCount != 0L) spectatorCount = 0
    }

    // MARK: - 창

    /** 상태 로드 시작 + presentWindow. [focusMatchID] 는 말풍선·배너에서 온 경로의 대상이다. */
    fun openWindow(focusMatchID: String?) {
        if (host?.session != null) {
            val focus = focusMatchID?.lowercase()
            // 곧 이어질 windowDidShow 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다.
            val now = clock()
            lastLobbyRequestAt = now
            lastInboxRequestAt = now
            launch { refreshLobby() }
            launch {
                loadInbox()
                val current = match
                if (focus != null && focus != current?.id && incoming.none { it.id == focus }) {
                    refreshMatch(focus)
                } else if (current != null && !current.isFinished) {
                    refreshMatch(current.id)
                }
            }
        }
        presentWindow?.invoke()
    }

    /** 창이 실제로 보이기 시작했다. 폴링 시작·로비/인박스 재조회. */
    fun windowDidShow() {
        if (!isWindowVisible) isWindowVisible = true
        // 막 앞으로 올라온 창이다. 숨기기 전의 가림 기록이 남아 폴링을 영영 막지 않게 지운다.
        isWindowOccluded = false
        resumeAIClockIfVisible()
        startPolling()
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastLobbyRequestAt) >= reloadDedupeSeconds) launch { refreshLobby() }
        if (now.timeIntervalSince(lastInboxRequestAt) >= reloadDedupeSeconds) launch { loadInbox() }
        // 관전·순위(0.3.41): 관전 중이면 즉시 한 번, 로비면 순위를 같은 1초 규칙으로.
        spectatorWindowDidShow(now)
    }

    /** 창이 가려졌다·닫혔다. 폴링만 멈춘다 — **대국은 계속된다**(시간은 서버에서 흐른다). */
    fun windowDidHide() {
        if (isWindowVisible) isWindowVisible = false
        isWindowOccluded = false
        stopPolling()
        pauseAIClock()
        // 결과 화면인 채로 창을 닫았다 = 그 판에서 나간 것이다. **진행 중이면 부르지 않는다**.
        val current = match
        if (current != null && current.isFinished) leaveMatch(current.id)
        // 끝난 판을 관전한 채 닫았다 = 그 판에서 나간 것이다. **진행 중인 관전은 남긴다**(최소화에서도 오는 통지).
        if (spectating?.isFinished == true) stopWatching()
    }

    /**
     * 창을 **정말 닫았다**(폰은 탭을 옮기는 것이 '닫기'다). 최소화·가려짐은 이 문을 지나지 않는다.
     * INV-GomokuStore-3b89d982 이식: `windowDidHide` 와 갈라 둔다 — 그 통지는 최소화도 부른다. 거기서 진행 중인 관전을 내리면 최소화만 해도
     * 남의 판이 로비로 떨어지고, 반대로 닫기에서 남기면 다시 열었을 때 남의 진행 중인 판이 서 있다. 관전만 내린다(요청 없음).
     * **끝난 내 판도 여기서 내린다**(0.3.50) — 진행 중인 판은 건드리지 않는다(닫기는 기권이 아니다).
     */
    fun windowDidClose() {
        if (spectating != null) stopWatching()
        if (match?.isFinished == true) foldFinishedMatch()
    }

    /** 창의 가림 상태가 바뀌었다. **폴링만** 멈추고 되살린다(`isWindowVisible` 은 건드리지 않는다). */
    fun windowOcclusionDidChange(visible: Boolean) {
        isWindowOccluded = !visible
        if (visible) {
            resumeAIClockIfVisible()
            startPolling()
        } else {
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
            when (val result = perform { service, token -> service.gomokuLobby(token) }) {
                null -> Unit
                is CallResult.Success -> applyLobby(result.value)
                is CallResult.Failure -> {
                    log("lobby request failed")
                    // 빈 목록을 "대결할 사람이 없다"로 믿게 하지 않는다.
                    if (!lobbyLoadFailed) lobbyLoadFailed = true
                }
            }
        } finally {
            if (generation == resetGeneration) lobbyInFlight = false
        }
    }

    fun applyLobby(response: GomokuLobbyResponse) {
        if (response.status != GomokuRPCStatus.ok) {
            log("lobby refused status=${response.status.rawValue}")
            if (response.status == GomokuRPCStatus.unsupportedClient) setNotice(GomokuNoticeText.updateMine)
            return
        }
        noteServerNow(response.serverNowMs)
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (!hasLoadedLobby) hasLoadedLobby = true
        val seconds = response.turnSeconds
        if (seconds != null && seconds > 0 && turnSeconds != seconds) turnSeconds = seconds
        // 1 이하는 받지 않는다 — 임계값이 1이면 경고 조건(streak == 0)이 판 시작부터 참이 되어 매 판 뜬다.
        val streak = response.autoAbandonStreak
        if (streak != null && streak > 1 && autoAbandonStreak.toLong() != streak) autoAbandonStreak = streak.toInt()
        val ttl = response.inviteTtlSeconds
        if (ttl != null && ttl > 0) inviteTTLSeconds = ttl.toDouble()
        val me = response.me
        if (me != null) {
            applyRuby(me.rubyBalance)
            val newRecord = GomokuRecord(me.wins ?: 0, me.losses ?: 0, me.draws ?: 0)
            if (record != newRecord) record = newRecord
            activeMatchID = me.activeMatchId?.lowercase()
        }
        val rows = response.users
        if (rows != null) {
            val mapped = sortedForLobby(rows.mapNotNull(::user))
            if (users != mapped) users = mapped
        }
        // **서버 순서 그대로**(accepted_at desc). 키가 아예 없으면(옛 서버) 들고 있던 목록을 지우지 않는다.
        val matchRows = response.matches
        if (matchRows != null) {
            val live = matchRows.mapNotNull(::liveMatch)
            if (liveMatches != live) liveMatches = live
        }
        val active = activeMatchID
        if (active != null && match?.id != active) launch { refreshMatch(active) }
    }

    /** 받은·보낸 신청과 진행 중 대국 id 를 읽는다. 도는 중에 또 불리면 **뒤따르는 한 번으로 합친다**. */
    suspend fun loadInbox() {
        if (host?.session == null) return
        if (inboxInFlight) {
            inboxAgain = true
            return
        }
        inboxInFlight = true
        val generation = resetGeneration
        do {
            inboxAgain = false
            lastInboxRequestAt = clock()
            inboxRequestOutgoingRevision = outgoingRevision
            val result = perform { service, token -> service.gomokuInbox(token) }
            if (generation != resetGeneration) return
            when (result) {
                is CallResult.Success -> {
                    applyInbox(result.value)
                    if (generation != resetGeneration) return
                }
                is CallResult.Failure -> {
                    log("inbox request failed")
                    if (!inboxLoadFailed) inboxLoadFailed = true
                }
                null -> Unit
            }
        } while (inboxAgain)
        inboxInFlight = false
    }

    suspend fun applyInbox(response: GomokuInboxResponse) {
        if (response.status != GomokuRPCStatus.ok) {
            log("inbox refused status=${response.status.rawValue}")
            if (response.status == GomokuRPCStatus.unsupportedClient) setNotice(GomokuNoticeText.updateMine)
            // 거절 응답도 받은 신청을 **모르는** 채다 — 빈 목록을 사실로 그리지 않게 실패로 적는다.
            if (!inboxLoadFailed) inboxLoadFailed = true
            return
        }
        if (inboxLoadFailed) inboxLoadFailed = false
        if (!hasLoadedInbox) hasLoadedInbox = true
        noteServerNow(response.serverNowMs)
        applyRuby(response.rubyBalance)
        val now = clock()
        val previousIncoming = incoming
        val received = (response.incoming ?: emptyList())
            .mapNotNull { row -> invite(row, row.challenger, null) }
            .filter { it.expiresAt > now }
            .map { fresh -> steadyInvite(fresh, previousIncoming.firstOrNull { it.id == fresh.id }) }
        if (incoming != received) incoming = received
        val previousOutgoing = outgoing
        val active = response.activeMatchId?.lowercase()
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        val predatesOutgoing = inboxRequestOutgoingRevision < outgoingRevision
        var sent = response.outgoing
            ?.let { row ->
                invite(row, row.opponent, if (outgoing?.id == row.matchId?.lowercase()) outgoing?.peer else null)
            }
            ?.let { if (it.expiresAt > now) it else null }
            ?.let { fresh -> steadyInvite(fresh, previousOutgoing) }
        if (sent == null && predatesOutgoing) sent = previousOutgoing
        if (outgoing != sent) outgoing = sent
        // 진행 중 대국이 있으면 거절 안내를 하지 않는다 — 내가 다른 신청을 수락해 서버가 보낸 신청을 거둔 것이지 상대가 거절한 게 아니다.
        val inMatch = active != null || match?.let { !it.isFinished } == true
        if (previousOutgoing != null && sent?.id != previousOutgoing.id && previousOutgoing.id != active && !predatesOutgoing && !inMatch) {
            // 보낸 신청이 받은함에서 사라졌고 판으로 이어지지도 않았다 = 거절·취소. 만료 시각이 지났으면 만료 안내와 같은 말을 한다.
            setNotice(if (previousOutgoing.expiresAt > now) GomokuNoticeText.inviteDeclined else GomokuNoticeText.inviteTimedOut)
        }
        announceNewInvites()
        scheduleInviteExpiry()

        activeMatchID = active
        val current = match
        val finished = response.lastFinished?.matchId?.lowercase()
        if (active != null) {
            if (current?.id != active || current.isFinished) refreshMatch(active)
        } else if (current != null && !current.isFinished) {
            // 로컬은 진행 중인데 서버엔 진행 중 대국이 없다 = 그 사이 끝났다. 결과를 받아 온다.
            refreshMatch(current.id)
        } else if (current == null && phase == GomokuPhase.lobby &&
            // 관전 중(C20)에는 세우지 않는다 — 세우면 결과 카드가 관전 위로 튀어나온다. [나가기]의 받은함 조회가 그때 세운다.
            spectating == null &&
            !finished.isNullOrEmpty() && finished !in dismissedMatchIDs && finished !in shownResultIDs
        ) {
            // 앱을 다시 켜는 사이 끝난 판(최근 10분)의 결과를 한 번 세운다.
            shownResultIDs = shownResultIDs + finished
            refreshMatch(finished)
        }
    }

    /** 지금 대국(없으면 서버가 말한 진행 중 대국)을 다시 읽는다. */
    suspend fun refreshMatch() {
        refreshMatch(match?.id ?: activeMatchID)
    }

    /**
     * 한 판의 상태를 읽는다. 같은 판을 들고 있으면 `since_seq` 로 **새 수만** 받고, 기록이 이어지지 않으면 처음부터 한 번 더 받는다.
     * 도는 중에 또 불리면 뒤따르는 한 번으로 합친다. 도는 중에 **다른 판** id 가 들어오면 기억했다가 지금 판이 끝난 뒤 그 판을 한 번 읽는다.
     */
    suspend fun refreshMatch(id: String?) {
        // AI 판 id 는 서버에 없다 — 어느 경로로 와도 여기서 막는다.
        val requested = id?.lowercase()
        if (requested.isNullOrEmpty() || GomokuAIGame.isAIMatchID(requested) || host?.session == null) return
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
            var forceChatFull = false
            do {
                stateAgain = false
                val current = match
                val since = if (!forceFull && current?.id == matchID) current.moveCount else 0
                // 전체 재요청 표시는 **요청을 띄울 때 본다**(내리는 것은 그것을 실어 온 응답이다).
                val wantsChatFull = forceChatFull || chatWantsFull
                val sinceChat = if (!wantsChatFull && chatMatchID == matchID) chatSeq else 0L
                val requestChatGeneration = chatGeneration
                lastStateRequestAt = clock()
                val result = perform { service, token -> service.gomokuState(token, matchID, since.toLong(), sinceChat) }
                if (generation != resetGeneration) return
                forceFull = false
                forceChatFull = false
                if (result !is CallResult.Success) continue
                val response = result.value
                when (response.status) {
                    GomokuRPCStatus.ok -> {
                        val outcome = applyState(response.state, since, sinceChat, requestChatGeneration)
                        if (outcome == StateApplyOutcome.needsFull && since > 0) {
                            forceFull = true
                            stateAgain = true
                        }
                        // 채팅 구멍·음소거 뒤집힘은 착수와 **따로** 센다.
                        if (chatWantsFull && sinceChat > 0) {
                            forceChatFull = true
                            stateAgain = true
                        }
                    }
                    GomokuRPCStatus.notFound -> {
                        if (match?.id == matchID) clearMatch()
                        if (activeMatchID == matchID) activeMatchID = null
                    }
                    GomokuRPCStatus.unsupportedClient -> setNotice(GomokuNoticeText.updateMine)
                    else -> log("state refused status=${response.status.rawValue}")
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

    private class MoveRecord(val seq: Int, val color: GomokuColor, val point: GomokuPoint?, val auto: Boolean)

    /**
     * 서버 상태 묶음을 화면 상태로 옮긴다. 판은 수 기록에서 다시 쌓는다(서버가 board 문자열을 실어 주면 그것이 권위다). 기록이 이어지지 않으면
     * `needsFull` 을 돌려 처음부터 다시 받게 한다 — 구멍 난 판을 그리면 이미 돌이 있는 자리를 비어 있다고 보여 준다.
     */
    fun applyState(
        payload: GomokuStatePayload,
        requestedSince: Int = 0,
        requestedSinceChat: Long = 0,
        chatGeneration: Int? = null,
        blackPassedHint: Boolean? = null,
    ): StateApplyOutcome {
        val row = payload.match ?: return StateApplyOutcome.ignored
        val id = row.id?.lowercase()
        if (id.isNullOrEmpty()) return StateApplyOutcome.ignored
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance)
        val status = row.status ?: ""
        if (status != "active" && status != "finished") {
            // 아직 시작 전(pending)이거나 시작하지 못하고 끝난 신청 — 판이 아니다.
            if (match?.id == id) clearMatch()
            if (activeMatchID == id) activeMatchID = null
            return StateApplyOutcome.applied
        }
        val isFinished = status == "finished"
        if (isFinished && id in dismissedMatchIDs && match?.id != id) return StateApplyOutcome.ignored
        // 진행 중인 **다른** 1:1 판을 들고 있으면 끝난 판의 늦은 응답은 버린다(0.3.50 — 끝인사 조회 뒤 수락한 새 판을 되돌리지 않게).
        val held = match
        if (isFinished && !isAIMatch && held != null && held.id != id && !held.isFinished) return StateApplyOutcome.ignored

        val myID = host?.session?.userID?.lowercase()
        var myColor = GomokuColor.fromRawValue(payload.myColor ?: "")
        if (myColor == null && myID != null) {
            if (row.black?.lowercase() == myID) myColor = GomokuColor.black
            else if (row.white?.lowercase() == myID) myColor = GomokuColor.white
        }
        if (myColor == null) return StateApplyOutcome.ignored

        val base = if (match?.id == id) match else null
        // 같은 판을 진행 중으로 들고 있는데 기록 수가 **줄어든** 응답은 착수보다 먼저 읽힌 옛 스냅숏이 늦게 온 것이다. 끝남은 예외다.
        val serverCount = row.moveCount?.toInt()
        if (base != null && !base.isFinished && !isFinished && serverCount != null && serverCount < base.moveCount) {
            return StateApplyOutcome.ignored
        }
        // 같은 판을 이미 끝남으로 들고 있으면 진행 중 응답은 전부 끝나기 전에 읽힌 옛 스냅숏이다. 판은 두되 채팅은 옮긴다.
        if (base != null && base.isFinished && !isFinished) {
            applyChat(payload, id, requestedSinceChat, chatGeneration)
            return StateApplyOutcome.ignored
        }
        val tolerateGaps = requestedSince == 0
        // `auto` 가 없는 응답(옛 서버)은 **사람이 둔 수**로 읽는다.
        val records = (payload.moves ?: emptyList()).mapNotNull { move ->
            val seq = move.seq?.toInt() ?: return@mapNotNull null
            val color = GomokuColor.fromRawValue(move.color ?: "") ?: return@mapNotNull null
            val auto = move.auto ?: false
            if (move.kind == "pass" || move.x == null || move.y == null) return@mapNotNull MoveRecord(seq, color, null, auto)
            val point = GomokuPoint.at(move.x?.toInt() ?: -1, move.y?.toInt() ?: -1) ?: return@mapNotNull null
            MoveRecord(seq, color, point, auto)
        }.sortedBy { it.seq }

        var board: GomokuBoard
        var lastMove: GomokuPoint?
        var appliedCount: Int
        var lastRecordIsBlackPass: Boolean? = null
        val autoPoints: MutableSet<GomokuPoint>
        var lastMoveWasAuto: Boolean
        val rebuild = base == null || records.firstOrNull()?.seq == 1
        if (rebuild || base == null) {
            board = GomokuBoard()
            lastMove = null
            appliedCount = 0
            autoPoints = LinkedHashSet()
            lastMoveWasAuto = false
        } else {
            // 값 의미: 들고 있는 판은 고치지 않는다 — 사본에 쌓는다.
            board = base.board.copy()
            lastMove = base.lastMove
            appliedCount = base.moveCount
            autoPoints = LinkedHashSet(base.autoPoints)
            lastMoveWasAuto = base.lastMoveWasAuto
        }
        for (record in records) {
            if (record.seq <= appliedCount) continue
            if (record.seq != appliedCount + 1 && !tolerateGaps) return StateApplyOutcome.needsFull
            val point = record.point
            if (point != null) {
                board[point] = record.color
                lastMove = point
                lastRecordIsBlackPass = false
                // 같은 자리를 두 번 쓰는 길은 없지만, 다시 받은 기록이 사람 수라고 말하면 그 말을 따른다.
                if (record.auto) autoPoints.add(point) else autoPoints.remove(point)
            } else {
                lastRecordIsBlackPass = record.color == GomokuColor.black
            }
            lastMoveWasAuto = record.auto
            appliedCount = record.seq
        }
        val serverBoard = row.board?.let { GomokuBoard.fromServerString(it) }
        if (serverBoard != null) {
            board = serverBoard
            if (serverCount != null) appliedCount = serverCount
        } else if (serverCount != null && serverCount != appliedCount) {
            if (!tolerateGaps) return StateApplyOutcome.needsFull
            appliedCount = serverCount
        }

        val blackPassed = when {
            blackPassedHint == true -> true
            lastRecordIsBlackPass != null -> lastRecordIsBlackPass
            else -> base?.blackPassed ?: false
        }

        val turn = if (isFinished) null else GomokuColor.fromRawValue(row.turn ?: "")
        var deadline = if (isFinished) null else deviceDate(row.deadlineMs)
        val kept = base?.deadline
        val fresh = deadline
        if (base != null && kept != null && fresh != null && base.moveCount == appliedCount && base.turn == turn &&
            abs(fresh.timeIntervalSince(kept)) < deadlineToleranceSeconds
        ) {
            // 같은 차례를 다시 읽었다 — 보정 오차만큼 다른 마감으로 갈면 창 루트가 조회마다 다시 그려진다.
            deadline = kept
        }
        val outcome = when (row.result) {
            "draw" -> GomokuOutcome.draw
            "black_win" -> if (myColor == GomokuColor.black) GomokuOutcome.won else GomokuOutcome.lost
            "white_win" -> if (myColor == GomokuColor.white) GomokuOutcome.won else GomokuOutcome.lost
            else -> null
        }
        val stake = row.stake ?: base?.stake ?: 0L
        // v0.3.54~: 승자 순이익은 서버 `duel_fee` 와 같은 식(`DuelFee` — v0.3.64 수수료 0). 서버는 상금 금액을 응답에 안 싣는다 —
        // 이 숫자는 클라 계산이고 잔량 칩(서버 값)과 같은 말을 해야 한다.
        val rubyDelta = when (outcome) {
            GomokuOutcome.won -> DuelFee.winnerNet(stake.toInt()).toLong()
            GomokuOutcome.lost -> -stake
            GomokuOutcome.draw -> 0L
            null -> null
        }
        val opponentID = (if (myColor == GomokuColor.black) row.white else row.black)?.lowercase()
        val opponent = peerUser(payload.opponent, working = true, capable = true, inMatch = !isFinished)
            ?: base?.opponent
            ?: users.firstOrNull { it.id == opponentID }
            ?: GomokuUser(
                id = opponentID ?: "", displayName = "", avatarURL = null, characterID = null,
                isWorking = true, isCapable = true, inMatch = !isFinished,
            )

        val next = GomokuMatchState(
            id = id, stake = stake, myColor = myColor, opponent = opponent, board = board, lastMove = lastMove,
            moveCount = appliedCount, turn = turn, deadline = deadline, isFinished = isFinished, outcome = outcome,
            endReason = row.endReason?.let { GomokuEndReason.fromRawValue(it) }, rubyDelta = rubyDelta,
            blackPassed = blackPassed, autoPoints = autoPoints.toSet(), lastMoveWasAuto = lastMoveWasAuto,
        )
        val justFinished = isFinished && base?.isFinished == false
        val previous = match
        val windowWasVisible = isWindowVisible
        if (match != next) match = next
        // 내 판을 보고 있는 사람 수. **`match` 대입 뒤**에 세운다 — 그 대입이 판이 바뀌는 길목에서 0 으로 되돌린다.
        val watchers = nonNegative(payload.watchers)
        if (spectatorCount != watchers) spectatorCount = watchers
        val nextPhase = if (isFinished) GomokuPhase.result else GomokuPhase.playing
        if (phase != nextPhase) phase = nextPhase
        // 채팅은 판을 옮긴 **뒤에** 옮긴다 — 순서가 바뀌면 방금 비운 대화 위에 옛 판의 줄이 다시 붙는다.
        applyChat(payload, id, requestedSinceChat, chatGeneration)
        // 연속 횟수는 **서버가 센다**. 키가 없는 응답이면 들고 있던 값을 둔다.
        payload.myAutoStreak?.toInt()?.let { if (myAutoStreak != it) myAutoStreak = it }
        payload.opponentAutoStreak?.toInt()?.let { if (opponentAutoStreak != it) opponentAutoStreak = it }
        activeMatchID = if (isFinished) null else id
        if (!isFinished) {
            // 내 신청이 수락됐거나 내가 수락한 판이다 — 대기 카드를 걷는다.
            if (outgoing?.id == id) outgoing = null
            if (incoming.any { it.id == id }) incoming = incoming.filter { it.id != id }
        } else {
            shownResultIDs = shownResultIDs + id
            // 끝인사 안전망의 끝을 **판마다 한 번만** 적는다. 서버가 끝난 시각을 말해 주면 거기서 세고, 없으면 지금부터 센다.
            if (finishedChatWatch?.first != id) {
                val finishedAt = deviceDate(row.finishedMs) ?: clock()
                finishedChatWatch = id to finishedAt.addingTimeInterval(finishedChatWindowSeconds)
            }
        }
        lastOpponent = opponent
        lastStake = stake
        if (!isFinished) {
            // 새 판이 열렸다 — 로비에서 남긴 안내는 대국 상태줄에서 "내 차례예요"를 가린다(v0.3.30).
            if (previous?.id != id || previous.isFinished) setNotice(null)
            noteMatchProgress(previous, next, windowWasVisible)
        }
        if (justFinished) {
            // 전적은 로비 응답에만 있다. 판이 끝난 순간 한 번 다시 읽는다.
            launch { refreshLobby() }
            // 순위도 같은 순간 바뀐다(0.3.41).
            noteOwnMatchFinishedForRanking()
        }
        return StateApplyOutcome.applied
    }

    // MARK: - 동작

    suspend fun challenge(userID: String) {
        challenge(userID, peerHint = null)
    }

    private suspend fun challenge(userID: String, peerHint: GomokuUser?) {
        if (isBusy || host?.session == null) return
        // §8-17 #1: 깃발이 꺼진 빌드는 신청 RPC 를 한 건도 내지 않는다.
        if (duelsLocked) {
            setNotice(GomokuNoticeText.updateMine)
            return
        }
        val target = userID.lowercase()
        val stake = selectedStake.rawValue
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            when (val result = perform { service, token -> service.gomokuChallenge(token, target, stake) }) {
                null -> return
                is CallResult.Failure -> setNotice(GomokuNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(GomokuNoticeText.challenge(response.status, response.need, response.have))
                    if (response.status != GomokuRPCStatus.ok) log("challenge refused status=${response.status.rawValue}")
                    when (response.status) {
                        GomokuRPCStatus.ok -> {
                            val id = response.matchId?.lowercase() ?: return
                            val peer = users.firstOrNull { it.id == target }
                                ?: peerHint
                                ?: GomokuUser(
                                    id = target, displayName = "", avatarURL = null, characterID = null,
                                    isWorking = true, isCapable = true, inMatch = false,
                                )
                            val expiresAt = deviceDate(response.inviteExpiresMs) ?: clock().addingTimeInterval(inviteTTLSeconds)
                            outgoingRevision += 1
                            outgoing = GomokuInvite(id, peer, stake, expiresAt)
                            scheduleInviteExpiry()
                        }
                        GomokuRPCStatus.alreadyPending, GomokuRPCStatus.busy -> loadInbox()
                        // 목록의 칩이 틀렸다는 뜻이다 — 다시 읽어 행을 사실에 맞춘다.
                        GomokuRPCStatus.targetNotWorking, GomokuRPCStatus.targetBusy, GomokuRPCStatus.targetOutdated -> refreshLobby()
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
            when (val result = perform { service, token -> service.gomokuCancel(token, id) }) {
                null -> return
                is CallResult.Failure -> setNotice(GomokuNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(GomokuNoticeText.cancel(response.status))
                    when (response.status) {
                        GomokuRPCStatus.ok, GomokuRPCStatus.notFound, GomokuRPCStatus.notPending, GomokuRPCStatus.expired -> {
                            if (outgoing?.id == id) {
                                outgoing = null
                                scheduleInviteExpiry()
                            }
                            // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 진행 중 판을 찾아 온다.
                            if (response.status == GomokuRPCStatus.notPending) loadInbox()
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
            setNotice(GomokuNoticeText.updateMine)
            return
        }
        val id = inviteID.lowercase()
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            // 채팅 세대 캡처는 조회 경로(refreshMatch)와 **같은 시점**이다 — 요청을 띄우기 직전.
            val requestChatGeneration = chatGeneration
            when (val result = perform { service, token -> service.gomokuRespond(token, id, accept) }) {
                null -> return
                is CallResult.Failure -> setNotice(GomokuNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(GomokuNoticeText.respond(accept, response.status, response.side, response.need, response.have))
                    if (response.status != GomokuRPCStatus.ok) log("respond refused status=${response.status.rawValue}")
                    when (response.status) {
                        GomokuRPCStatus.ok -> {
                            removeIncoming(id)
                            if (!accept) return
                            // 수락하는 순간 서버가 두 참가자의 **다른 대기 신청을 전부 취소한다** — 로컬 카드를 그대로 두면 엉뚱한 안내가 뜬다.
                            if (outgoing != null) outgoing = null
                            if (incoming.isNotEmpty()) incoming = emptyList()
                            val state = response.state
                            if (state != null) applyState(state, chatGeneration = requestChatGeneration) else refreshMatch(id)
                            // 판을 못 받아 온 경우에만 여기서 창을 띄워 받은 신청이 어떻게 됐는지 보게 한다.
                            if (match?.id != id && !isWindowVisible) presentWindow?.invoke()
                        }
                        GomokuRPCStatus.notFound, GomokuRPCStatus.notPending, GomokuRPCStatus.expired -> removeIncoming(id)
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    suspend fun place(point: GomokuPoint, seen: GomokuSeenTurn? = null) {
        // 화면이 본 판과 다르면 먼저 적는다 — 판정은 아래 가드가 **스토어 값으로** 한다(진단만, 동작 무변경).
        if (seen != null && seen.differs(match)) noteTapDivergence(seen, point)
        // **거절은 전부 이유를 남긴다**(v0.3.28). 보는 순서는 0.3.27 그대로다.
        if (isBusy) return refuseTap(GomokuTapRefusal.busy, point)
        val current = match ?: return refuseTap(GomokuTapRefusal.noMatch, point)
        if (current.isFinished) return refuseTap(GomokuTapRefusal.finished, point)
        if (current.turn != current.myColor) return refuseTap(GomokuTapRefusal.notYourTurn, point)
        if (current.board[point] != null) return refuseTap(GomokuTapRefusal.occupied, point)
        // 흑 금수는 서버에 보내기 전에 막는다(헛왕복 절감). 판정은 서버 gomoku_judge 와 같은 규범·같은 예산이다.
        if (current.myColor == GomokuColor.black) {
            val verdict = GomokuRules.judge(current.board, point, GomokuColor.black)
            if (verdict is GomokuJudgement.Forbidden) return refuseTap(GomokuTapRefusal.forbidden, point, verdict.reason)
        }
        // AI 판은 위 거절 가드를 **같이** 지난 뒤 로컬 판에 둔다 — 서버로는 안 나간다(로그인 여부도 안 본다).
        if (isAIMatch) {
            val refusal = placeInAIMatch(point)
            if (refusal != null) refuseTap(refusal.kind, point, refusal.reason)
            return
        }
        if (host?.session == null) return refuseTap(GomokuTapRefusal.signedOut, point)
        val id = current.id
        val expected = current.moveCount
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            // 세대 캡처는 조회 경로와 **같은 시점**이다(요청 직전) — 채팅은 버리고 착수 결과는 받는다.
            val requestChatGeneration = chatGeneration
            when (val result = perform { service, token -> service.gomokuMove(token, id, expected.toLong(), point.x.toLong(), point.y.toLong()) }) {
                null -> return
                is CallResult.Failure -> setNotice(GomokuNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(GomokuNoticeText.move(response.status, response.reason))
                    if (response.status != GomokuRPCStatus.ok) log("move refused status=${response.status.rawValue}")
                    if (response.status == GomokuRPCStatus.notFound) {
                        if (match?.id == id) clearMatch()
                        return
                    }
                    // 판이 바뀌었거나(stale) 내 판단이 서버와 갈린 경우는 **언제나** 다시 읽는다.
                    var needsRefresh = when (response.status) {
                        GomokuRPCStatus.stale, GomokuRPCStatus.notYourTurn, GomokuRPCStatus.notActive, GomokuRPCStatus.invalid -> true
                        else -> false
                    }
                    val state = response.state
                    if (state != null) {
                        // 세대는 **채팅 부분만** 거른다 — 판·기록 수·차례는 세대와 무관하게 받는다.
                        val outcome = applyState(
                            state, requestedSince = expected, chatGeneration = requestChatGeneration,
                            blackPassedHint = response.blackPassed,
                        )
                        if (outcome == StateApplyOutcome.needsFull) needsRefresh = true
                    } else if (response.status == GomokuRPCStatus.ok || response.status == GomokuRPCStatus.timeout ||
                        response.status == GomokuRPCStatus.autoPlaced
                    ) {
                        // 상태를 안 실어 준 성공·시간 경과는 판을 다시 읽어야 한다(자동 착수는 **남의 수까지** 바꾼다).
                        needsRefresh = true
                    }
                    if (needsRefresh) refreshMatch(id)
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
            val requestChatGeneration = chatGeneration
            when (val result = perform { service, token -> service.gomokuResign(token, id) }) {
                null -> return
                is CallResult.Failure -> setNotice(GomokuNoticeText.checkConnection)
                is CallResult.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance)
                    setNotice(GomokuNoticeText.resign(response.status))
                    val state = response.state
                    if (state != null) applyState(state, chatGeneration = requestChatGeneration)
                    if (response.status != GomokuRPCStatus.ok || state == null) refreshMatch(id)
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /** 결과 화면에서 로비로. **진행 중인 판에서는 아무것도 하지 않는다**(빠져나가는 길은 기권뿐이다). */
    fun backToLobby() {
        if (!foldFinishedMatch() || host?.session == null) return
        launch {
            refreshLobby()
            loadInbox()
        }
    }

    /**
     * 끝난 판을 내리고 화면을 로비로 돌린다 — [로비로] 와 '결과 화면인 채로 창 닫기'(`windowDidClose`)가 같이 쓴다.
     * 진행 중인 판이면 false — 아무것도 안 바꾼다.
     */
    private fun foldFinishedMatch(): Boolean {
        // 끝난 AI 판이면 판만 내리고 나머지는 아래 1:1 길을 그대로 탄다(진행 중이면 아래 가드가 막는다).
        if (isAIMatch) backToLobbyFromAIMatch()
        val current = match
        if (current != null) {
            if (!current.isFinished) return false
            dismissedMatchIDs = dismissedMatchIDs + current.id
            // 결과 화면을 떠났다 = 그 판에서 나간 것이다. 둘 다 나가면 서버가 그 판 채팅을 즉시 지운다.
            leaveMatch(current.id)
            lastOpponent = current.opponent
            lastStake = current.stake
            match = null
        }
        if (phase != GomokuPhase.lobby) phase = GomokuPhase.lobby
        clearMatchScopedState()
        setNotice(null)
        return true
    }

    /** 같은 상대·같은 판돈으로 다시 신청. */
    suspend fun rematch() {
        // AI 판의 "다시"는 신청이 아니라 새 로컬 판이다.
        if (isAIMatch) {
            restartAIMatch()
            return
        }
        val current = match
        if (current != null && !current.isFinished) return
        val opponent = current?.opponent ?: lastOpponent ?: return
        // §8-17 #1: 깃발이 꺼진 빌드는 1:1 다시 신청도 진입이다 — 판을 내리지 않고 안내만 남긴다(RPC 0).
        if (duelsLocked) {
            setNotice(GomokuNoticeText.updateMine)
            return
        }
        val stake = GomokuStake.fromRawValue(current?.stake ?: lastStake ?: selectedStake.rawValue)
        if (stake != null && selectedStake != stake) selectedStake = stake
        if (current != null) {
            dismissedMatchIDs = dismissedMatchIDs + current.id
            match = null
        }
        if (phase != GomokuPhase.lobby) phase = GomokuPhase.lobby
        clearMatchScopedState()
        challenge(opponent.id, peerHint = opponent)
    }

    // MARK: - 신호 · 계기

    /** 실시간 'gomoku' 신호. 직렬화된 재조회 — 도는 중이면 뒤따르는 한 번으로 합친다. */
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

    /** 신호 한 번의 조회: 진행 중 판이 있으면 그 판(since_seq), 아니면 인박스. */
    suspend fun syncOnce() {
        val current = match
        if (current != null && !current.isFinished && !isAIMatch) {
            refreshMatch(current.id)
        } else {
            // 결과 화면에 아직 서 있는 끝난 판이면 이 초인종은 **상대의 끝인사**일 수 있다(2026-10-13 신고).
            // 읽을 판은 **받은함보다 먼저** 정한다 — 받은함이 방금 세운 끝난 판을 곧바로 한 번 더 읽지 않게.
            val farewellID = farewellMatchID(clock())
            loadInbox()
            if (farewellID != null && match?.id == farewellID) refreshMatch(farewellID)
        }
    }

    /** 끝인사를 읽어 올 판 — 결과 화면에 서 있는 끝난 1:1 판이고, 서버가 아직 말을 받는 시간 안이며, 내가 상대 말을 끄지 않았다. */
    private fun farewellMatchID(now: SwiftDate): String? {
        val current = match ?: return null
        val watch = finishedChatWatch ?: return null
        if (!current.isFinished || isAIMatch || isMuted || watch.first != current.id || now >= watch.second) return null
        return current.id
    }

    /** 조인 직후·깨어남의 따라잡기: 인박스 한 번 + 진행 중 판이면 그 판의 놓친 수. */
    suspend fun catchUp() {
        // 소켓이 끊겨 있던 동안의 끝인사도 놓친 초인종이다(`syncOnce` 와 같은 이유 · 같은 순서).
        val farewellID = farewellMatchID(clock())
        loadInbox()
        val current = match
        if (current != null && !current.isFinished) {
            refreshMatch(current.id)
        } else if (farewellID != null && match?.id == farewellID) {
            refreshMatch(farewellID)
        }
    }

    /** 실시간 조인 성공 직후. */
    fun realtimeDidJoin() {
        if (host?.session == null) return
        launch { catchUp() }
    }

    /** 깨어남(결합 게이트가 열린 뒤). */
    fun systemDidWake() {
        if (host?.session == null) return
        launch { catchUp() }
    }

    /** 근무 시작(v0.3.30 뒤로는 신선도 보강이다 — 주 경로는 소켓 신호·팝오버 열기). */
    fun workDidStart() {
        if (host?.session == null) return
        launch { loadInbox() }
    }

    /** 팝오버 열림(60초 스로틀). v0.3.30 부터 **근무 밖에서도** 신청이 온다. */
    fun refreshInboxIfStale() {
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastMenuInboxAt) < menuInboxThrottleSeconds) return
        lastMenuInboxAt = now
        launch { loadInbox() }
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
     * 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다.**
     *  · 진행 중 판이 상대 차례면(또는 표시 마감 + 유예가 지났으면) 구독 중 3초 / 미구독 1.5초마다 상태.
     *  · 결과 화면의 끝난 판이면 끝난 뒤 130초 동안 구독 중 10초 / 미구독 5초마다 상태(상대의 끝인사).
     *  · 내 대기 신청이 있으면 5초마다 인박스. · 로비를 보고 있으면 30초마다 목록.
     */
    suspend fun pollTick(now: SwiftDate) {
        if (!isWindowVisible || isWindowOccluded || host?.session == null) return
        val current = match
        val farewellID = farewellMatchID(now)
        if (current != null && !current.isFinished && !isAIMatch) {
            val waiting = current.turn != current.myColor
            val overdue = current.deadline?.let { now.timeIntervalSince(it) > turnGraceSeconds } ?: false
            if (waiting || overdue) {
                val subscribed = host?.realtimeState?.isSubscribed ?: false
                val interval = if (subscribed) statePollSecondsWhileSubscribed else statePollSecondsUnsubscribed
                if (now.timeIntervalSince(lastStateRequestAt) >= interval) refreshMatch(current.id)
            }
        } else if (farewellID != null) {
            // 끝인사 안전망: 초인종을 놓쳐도 결과 화면의 대화가 멈춰 서지 않게 한다. 그 시간이 지나면 서버가 말을 안 받으므로 그친다.
            val subscribed = host?.realtimeState?.isSubscribed ?: false
            val interval = if (subscribed) finishedChatPollSecondsWhileSubscribed else finishedChatPollSecondsUnsubscribed
            if (now.timeIntervalSince(lastStateRequestAt) >= interval) refreshMatch(farewellID)
        }
        if (!isWindowVisible) return
        if (outgoing != null && now.timeIntervalSince(lastInboxRequestAt) >= outgoingInboxPollSeconds) loadInbox()
        if (!isWindowVisible) return
        if (phase == GomokuPhase.lobby && now.timeIntervalSince(lastLobbyRequestAt) >= lobbyPollSeconds) refreshLobby()
        // 관전·순위(0.3.41): 관전 중이면 2초마다 판, 로비면 60초마다 순위.
        if (!isWindowVisible) return
        pollSpectatorFeatures(now)
    }

    // MARK: - 초 단위 값 (잎 전용)

    /** 대국 창의 남은 시간(초, 0 이상). 잎이 now 를 넘겨 부른다. */
    fun remainingSeconds(now: SwiftDate): Double? {
        val current = match ?: return null
        val deadline = current.deadline ?: return null
        if (current.isFinished) return null
        val left = deadline.timeIntervalSince(now)
        return if (left > 0.0) left else 0.0
    }

    /** 차례 경고(마지막 3초)가 설 수 있는 판인가 — W1-b `watchesMyClock` 의 판 몫(판이 없으면 false — Swift `match == nil` 갈래). */
    fun watchesMyClock(): Boolean = GomokuTurnWarning.watchesMyClock(match)

    // MARK: - 리셋

    /** 로그아웃·계정 전환. 창을 닫고 오목 상태를 전부 비운다 — 남기면 다음 사람이 앞 사람의 판·신청·루비를 본다. */
    fun reset() {
        // 나가기는 **세대를 올리기 전에** 쏜다(best-effort — 로그아웃 경로에서는 이미 session 이 없어 아무것도 안 나간다).
        val current = match
        if (current != null && current.isFinished) leaveMatch(current.id)
        resetGeneration += 1
        stopPolling()
        discardAIGame()
        syncTask?.cancel()
        syncTask = null
        syncPendingTrailing = false
        expiryTask?.cancel()
        expiryTask = null
        stateInFlight = false
        stateAgain = false
        inboxInFlight = false
        inboxAgain = false
        lobbyInFlight = false
        if (phase != GomokuPhase.lobby) phase = GomokuPhase.lobby
        if (users.isNotEmpty()) users = emptyList()
        if (record != null) record = null
        if (selectedStake != GomokuStake.three) selectedStake = GomokuStake.three
        if (incoming.isNotEmpty()) incoming = emptyList()
        // 차단으로 걷어낸 상대도 계정에 묶인다.
        if (hiddenPeerIDs.isNotEmpty()) hiddenPeerIDs = emptySet()
        if (outgoing != null) outgoing = null
        if (match != null) match = null
        if (notice != null) notice = null
        if (isBusy) isBusy = false
        if (isSendingChat) isSendingChat = false
        clearMatchScopedState()
        if (isWindowVisible) isWindowVisible = false
        if (isRulesVisible) isRulesVisible = false
        if (rubyBalance != null) rubyBalance = null
        if (turnSeconds != 30L) turnSeconds = 30L
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (hasLoadedLobby) hasLoadedLobby = false
        if (inboxLoadFailed) inboxLoadFailed = false
        if (hasLoadedInbox) hasLoadedInbox = false
        if (liveMatches.isNotEmpty()) liveMatches = emptyList()
        // 관전·순위도 계정에 묶인다. 주 스위치는 배선 값이라 안 건드린다.
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
        if (autoAbandonStreak != autoPlaceLossStreak) autoAbandonStreak = autoPlaceLossStreak
        serverClockOffset = 0.0
        hasServerClockOffset = false
        isWindowOccluded = false
        stateInFlightID = null
        pendingStateID = null
        attentionKey = null
        shownResultIDs = emptySet()
        outgoingRevision = 0
        inboxRequestOutgoingRevision = 0
        activeMatchID = null
        seenInviteIDs = emptySet()
        dismissedMatchIDs = emptySet()
        leftMatchIDs = emptySet()
        finishedChatWatch = null
        lastStateRequestAt = distantPast
        lastInboxRequestAt = distantPast
        lastLobbyRequestAt = distantPast
        lastMenuInboxAt = distantPast
        inviteTTLSeconds = 60.0
        lastOpponent = null
        lastStake = null
        dismissWindow?.invoke()
    }

    // MARK: - 채팅 동작

    /** 입력칸의 글을 보낸다. 판정은 `canSendChatNow` 와 같은 한 벌이고 길이 초과만은 **여기서 말한다**. */
    fun sendChatDraft() {
        val current = match
        if (isSendingChat || current == null) return
        when (val verdict = GomokuChatBody.validate(chatDraft, RulesWireTextRules, chatMaxLength)) {
            // 빈 입력은 말없이 무시한다. 여기서 안내를 띄우면 ↩ 를 한 번 헛친 사람이 혼난다.
            MessageBodyValidation.Empty -> return
            is MessageBodyValidation.TooLong -> setChatNotice(GomokuNoticeText.chatTooLong(verdict.maxLength))
            // 보내는 것은 **정규화된 값**이다 — NFD 로 들어온 한글은 서버가 다르게 센다.
            is MessageBodyValidation.Ok -> sendChat(GomokuChatKind.text, verdict.text, current.id, clearsDraft = true)
        }
    }

    /** 빠른 문구 한 건. 서버로 가는 것은 **코드**이고, 쓰다 만 초안은 건드리지 않는다. */
    fun sendQuick(phrase: GomokuQuickPhrase) {
        val current = match
        if (isSendingChat || current == null) return
        sendChat(GomokuChatKind.quick, phrase.rawValue, current.id, clearsDraft = false)
    }

    /** 이 판 채팅 끄기·켜기. 음소거는 내 화면 설정이 아니라 **서버가 아는 판 상태**라 상대 화면에도 뜬다. */
    fun setChatMuted(muted: Boolean) {
        val current = match
        if (isSendingChat || current == null || GomokuAIGame.isAIMatchID(current.id) || host?.session == null) return
        val id = current.id
        isSendingChat = true
        setChatNotice(null)
        val generation = resetGeneration
        launch {
            try {
                when (val result = perform { service, token -> service.gomokuChatMute(token, id, muted) }) {
                    null -> return@launch
                    is CallResult.Failure -> setChatNotice(GomokuNoticeText.checkConnection)
                    is CallResult.Success -> {
                        val response = result.value
                        noteServerNow(response.serverNowMs)
                        setChatNotice(GomokuNoticeText.chatMute(response.status))
                        if (response.status != GomokuRPCStatus.ok) {
                            log("chat mute refused status=${response.status.rawValue}")
                            return@launch
                        }
                        // 요청한 값이 아니라 **서버가 적용했다고 말한 값**을 쓴다.
                        val applied = response.muted ?: muted
                        if (isMuted != applied) isMuted = applied
                        // **기준선(`chatSeq`)은 내리지 않는다** — 대신 세대를 올려 토글 전에 나간 응답을 통째로 버리고, 전체 재요청은 표시로 건다.
                        chatGeneration += 1
                        chatWantsFull = true
                        if (chat.isNotEmpty()) chat = emptyList()
                        refreshMatch(id)
                    }
                }
            } finally {
                if (generation == resetGeneration) isSendingChat = false
            }
        }
    }

    /** 채팅 한 줄 보내기의 공통 몸통. **`isBusy` 를 세우지 않는다**(착수·기권을 잠그지 않는다). */
    private fun sendChat(kind: GomokuChatKind, body: String, id: String, clearsDraft: Boolean) {
        if (host?.session == null || GomokuAIGame.isAIMatchID(id)) return
        isSendingChat = true
        setChatNotice(null)
        val generation = resetGeneration
        launch {
            try {
                when (val result = perform { service, token -> service.gomokuChatSend(token, id, kind, body) }) {
                    null -> return@launch
                    is CallResult.Failure -> setChatNotice(GomokuNoticeText.checkConnection)
                    is CallResult.Success -> {
                        val response = result.value
                        noteServerNow(response.serverNowMs)
                        val limit = response.chatMaxLen
                        if (limit != null && limit > 0 && chatMaxLength != limit) chatMaxLength = limit
                        // 보낸 사람이 **여기서** 안다: 상대가 껐다 / 상대가 못 받는 버전이다. 조용히 삼키지 않는다.
                        response.opponentMuted?.let { if (isOpponentMuted != it) isOpponentMuted = it }
                        response.chatCapable?.let { if (opponentChatCapable != it) opponentChatCapable = it }
                        setChatNotice(GomokuNoticeText.chat(response.status))
                        if (response.status != GomokuRPCStatus.ok) {
                            // **자동 재전송은 없고 초안도 비우지 않는다.**
                            log("chat refused status=${response.status.rawValue}")
                            return@launch
                        }
                        if (clearsDraft && match?.id == id) chatDraft = ""
                        // 낙관 삽입을 하지 않는다. 왕복 사이에 그 판을 떠났으면 읽지 않는다.
                        if (match?.id != id) return@launch
                        refreshMatch(id)
                    }
                }
            } finally {
                if (generation == resetGeneration) isSendingChat = false
            }
        }
    }

    // MARK: - 내부

    /**
     * 상태 응답의 채팅 부분을 옮긴다. 늦게 온 응답 방어를 착수와 **같은 겹으로** 얹는다: 판이 바뀌면 비운다 · 음소거 토글 **뒤에** 도착한 응답은
     * 세대가 달라 통째로 버린다 · 서버 발급 번호가 **역행하면 통째로 버린다** · 음소거가 뒤집혀 오면 비우고 전체 재요청 · 구멍이 나면 처음부터.
     */
    private fun applyChat(payload: GomokuStatePayload, id: String, requestedSince: Long, generation: Int?) {
        if (chatMatchID != id) clearMatchScopedState(id)
        // 이 요청이 나간 **뒤에** 음소거를 토글했다 — 채팅 부분만 통째로 버린다(null = 세대를 안 넘긴 자리 — 시험의 직접 주입뿐).
        if (generation != null && generation != chatGeneration) return
        val serverSeq = payload.chatSeq
        if (serverSeq != null && serverSeq < chatSeq) return
        // 상한·상대 상태는 **두 방어(세대·역행)를 지난 뒤에만** 받는다.
        val limit = payload.chatMaxLen
        if (limit != null && limit > 0 && chatMaxLength != limit) chatMaxLength = limit
        payload.chatCapable?.let { if (opponentChatCapable != it) opponentChatCapable = it }
        var mutedFlipped = false
        val muted = payload.myMuted
        if (muted != null && isMuted != muted) {
            isMuted = muted
            mutedFlipped = true
        }
        payload.opponentMuted?.let { if (isOpponentMuted != it) isOpponentMuted = it }
        if (mutedFlipped) {
            if (chat.isNotEmpty()) chat = emptyList()
            if (requestedSince > 0 || payload.chat == null) chatWantsFull = true
        }
        // 채팅 키가 아예 없는 응답(채팅을 모르는 서버·쓰기 RPC 가 싣는 state 묶음)은 **지우지 않고 그냥 둔다**.
        val rows = payload.chat ?: return
        // 표시는 **전체를 실어 온 응답**이 내린다.
        if (requestedSince == 0L) chatWantsFull = false
        var lastSeq = chat.lastOrNull()?.seq ?: 0L
        val appended = ArrayList<GomokuChatMessage>()
        for (message in rows.mapNotNull(::chatMessage).sortedBy { it.seq }) {
            if (message.seq <= lastSeq) continue
            // 내가 껐으면 상대 줄이 서버에서 빠져 번호가 건너뛴다 — 그건 구멍이 아니라 음소거의 모습이다.
            if (message.seq != lastSeq + 1 && requestedSince > 0 && !isMuted) {
                chatWantsFull = true
                return
            }
            appended.add(message)
            lastSeq = message.seq
        }
        if (appended.isNotEmpty()) chat = chat + appended
        val nextSeq = maxOf(payload.chatSeq ?: 0L, lastSeq)
        if (nextSeq > chatSeq) chatSeq = nextSeq
    }

    /** 서버 채팅 행 → 화면 값. 빠른 문구는 코드를 문구로 편다. 모르는 코드는 줄을 **지우지 않고** 한 문장으로 접는다. */
    private fun chatMessage(row: GomokuChatRow): GomokuChatMessage? {
        val seq = row.seq ?: return null
        if (seq < 1) return null
        val isQuick = row.kind == GomokuChatKind.quick.rawValue
        val quick = if (isQuick) GomokuQuickPhrase.fromRawValue(row.body ?: "") else null
        val body = if (isQuick) (quick?.text ?: GomokuNoticeText.chatUnknownQuick) else (row.body ?: "")
        if (body.isEmpty()) return null
        return GomokuChatMessage(seq = seq, isMine = row.mine ?: false, sentAt = deviceDate(row.createdMs) ?: clock(), quick = quick, body = body)
    }

    /**
     * **한 판에만 속하는 것**을 전부 비운다(판이 바뀌었다 · 로비로 나갔다 · 로그아웃했다): 대화 · 초안 · 음소거 표시 · 자동 착수 연속 횟수.
     */
    private fun clearMatchScopedState(id: String? = null) {
        chatMatchID = id
        chatWantsFull = false
        if (chat.isNotEmpty()) chat = emptyList()
        if (chatSeq != 0L) chatSeq = 0
        if (isMuted) isMuted = false
        if (isOpponentMuted) isOpponentMuted = false
        if (!opponentChatCapable) opponentChatCapable = true
        if (chatDraft.isNotEmpty()) chatDraft = ""
        if (chatNotice != null) chatNotice = null
        if (chatMaxLength != GomokuChatBody.maxLength) chatMaxLength = GomokuChatBody.maxLength
        if (myAutoStreak != 0) myAutoStreak = 0
        if (opponentAutoStreak != 0) opponentAutoStreak = 0
    }

    // 칸 `chatNotice` 의 JVM 세터(setChatNotice)와 이름이 겹친다 — Swift 이름을 지키고 JVM 이름만 바꾼다.
    @JvmName("setChatNoticeIfChanged")
    private fun setChatNotice(text: String?) {
        if (chatNotice != text) chatNotice = text
    }

    /** 공용 호출 관용구(Swift `perform`). 관전·순위 확장이 같은 관용구로 부른다. */
    internal suspend fun <T> perform(operation: suspend (SupabaseWorkService, String) -> T): CallResult<T>? =
        performDuelCall(host, { resetGeneration }, operation)

    /**
     * **끝난 판에서 나간다**(결과 화면을 떠났다 · 결과 화면인 채로 창을 닫았다 · 로그아웃했다). 실패해도 안내하지 않는다.
     * **진행 중인 판에서는 절대 부르지 않는다**(부르는 쪽 셋이 전부 `isFinished` 를 먼저 본다). 멱등이지만 **판마다 한 번만** 부른다.
     */
    private fun leaveMatch(rawID: String) {
        val id = rawID.lowercase()
        if (id.isEmpty() || GomokuAIGame.isAIMatchID(id) || id in leftMatchIDs || host?.session == null) return
        leftMatchIDs = leftMatchIDs + id
        launch {
            val result = perform { service, token -> service.gomokuLeave(token, id) }
            if (result !is CallResult.Success) return@launch
            val response = result.value
            noteServerNow(response.serverNowMs)
            if (response.status == GomokuRPCStatus.ok) {
                if (response.bothLeft == true) log("left match, chat purged")
            } else {
                log("leave refused status=${response.status.rawValue}")
            }
        }
    }

    /** 안내줄 한 문. 관전 확장이 not_found·준비 중 안내를 여기로 흘린다(순위 실패는 절대 부르지 않는다). */
    // 칸 `notice` 의 JVM 세터(setNotice)와 이름이 겹친다 — Swift 이름을 지키고 JVM 이름만 바꾼다.
    @JvmName("setNoticeIfChanged")
    fun setNotice(text: String?) {
        if (notice != text) notice = text
    }

    /**
     * 착수 거절 하나를 **두 곳**에 남긴다: 상태줄 한 줄(`notice`)과 진단 한 줄. 진단 줄에는 **좌표와 사유만** 싣는다
     * (`tap refused reason=occupied point=D10 turn=white mine=white busy=false`).
     */
    private fun refuseTap(refusal: GomokuTapRefusal, point: GomokuPoint, reason: GomokuForbiddenReason? = null) {
        GomokuNoticeText.tapRefusal(refusal, reason)?.let(::setNotice)
        log(
            "tap refused reason=${refusal.rawValue} point=${point.notation} turn=${match?.turn?.rawValue ?: "none"} " +
                "mine=${match?.myColor?.rawValue ?: "none"} busy=${if (isBusy) "true" else "false"}",
        )
    }

    /** 탭 순간 화면과 스토어가 다른 판을 보고 있었다 — 한 줄(이름·판 내용 없음). */
    private fun noteTapDivergence(seen: GomokuSeenTurn, point: GomokuPoint) {
        tapDivergenceCount += 1
        log(
            "tap diverged point=${point.notation} sameMatch=${if (seen.matchID == match?.id) "true" else "false"} " +
                "view=(moves=${seen.moveCount} turn=${seen.turn?.rawValue ?: "none"}) " +
                "store=(moves=${match?.moveCount ?: -1} turn=${match?.turn?.rawValue ?: "none"})",
        )
    }

    private fun applyRuby(value: Long?) {
        if (value == null) return
        if (rubyBalance != value) rubyBalance = value
        val host = host
        if (host != null && host.rubyBalance != value) host.rubyBalance = value
    }

    private fun clearMatch() {
        if (match != null) match = null
        if (phase != GomokuPhase.lobby) phase = GomokuPhase.lobby
        clearMatchScopedState()
    }

    private fun removeIncoming(id: String) {
        if (incoming.any { it.id == id }) incoming = incoming.filter { it.id != id }
    }

    /**
     * 판 진행을 사람에게 알린다(applyState 가 진행 중 판을 옮긴 직후). 진행 중 판으로 **처음 넘어가면** 창을 띄우고 주의를 끈다 —
     * 신청자는 상대가 수락한 순간을 모르면 흑 30초를 흘려 판돈을 잃는다. 창이 안 보이는 동안 차례가 나에게 오면 말풍선 문을 연다.
     */
    private fun noteMatchProgress(previous: GomokuMatchState?, next: GomokuMatchState, windowWasVisible: Boolean) {
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
            GomokuAttention(
                kind = if (started) GomokuAttention.Kind.matchStarted else GomokuAttention.Kind.myTurn,
                matchID = next.id, opponentName = next.opponent.displayName, moveCount = next.moveCount,
            ),
        )
    }

    /** server_now_ms 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로 받고, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만 간다. */
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

    private fun invite(row: GomokuInviteRow, peerRow: GomokuUserRow?, fallbackPeer: GomokuUser?): GomokuInvite? {
        val id = row.matchId?.lowercase()
        if (id.isNullOrEmpty()) return null
        val stake = row.stake ?: return null
        val expiresAt = deviceDate(row.inviteExpiresMs) ?: return null
        val peer = peerUser(peerRow, working = true, capable = true, inMatch = false) ?: fallbackPeer ?: return null
        return GomokuInvite(id, peer, stake, expiresAt)
    }

    /** 로비 "지금 대결 중" 한 줄 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**. */
    fun liveMatch(row: GomokuLobbyMatchRow): GomokuLiveMatch? {
        val id = row.matchId?.lowercase()
        if (id.isNullOrEmpty()) return null
        val a = peerUser(row.a, working = true, capable = true, inMatch = true) ?: return null
        val b = peerUser(row.b, working = true, capable = true, inMatch = true) ?: return null
        // 판돈은 서버 CHECK 가 3·5·10 으로 묶어 둔 값이다. 서버가 그 표를 넓히는 날 이 줄이 먼저 막는다.
        val stake = GomokuStake.fromRawValue(row.stake) ?: return null
        val startedAt = deviceDate(row.startedMs) ?: return null
        // 안 싣는 서버면 0 — 카드는 그냥 눈 아이콘을 안 그린다(없는 숫자를 지어내지 않는다).
        return GomokuLiveMatch(id, a, b, stake, startedAt, watchers = nonNegative(row.watchers))
    }

    /**
     * 사람 행 → GomokuUser. 행에 없는 칸(근무·가능·대국 중)은 로비 목록에서 빌리고, 거기에도 없으면 문맥 기본값이다.
     * 서버 어휘 → 화면 글자(CenterLabel)는 **이 함수와 [user] 두 곳뿐**이다.
     */
    fun peerUser(row: GomokuUserRow?, working: Boolean, capable: Boolean, inMatch: Boolean): GomokuUser? {
        if (row == null) return null
        val id = row.userId?.lowercase()
        if (id.isNullOrEmpty()) return null
        val known = users.firstOrNull { it.id == id }
        return GomokuUser(
            id = id,
            displayName = row.displayName ?: known?.displayName ?: "",
            avatarURL = row.avatarUrl ?: known?.avatarURL,
            characterID = row.character ?: known?.characterID,
            isWorking = row.isWorking ?: known?.isWorking ?: working,
            isCapable = row.capable ?: known?.isCapable ?: capable,
            inMatch = row.inMatch ?: inMatch,
            center = CenterLabel.display(row.center) ?: known?.center,
        )
    }

    private fun announceNewInvites() {
        for (invite in incoming.sortedBy { it.expiresAt }) {
            if (invite.id in seenInviteIDs) continue
            seenInviteIDs = seenInviteIDs + invite.id
            // §8-17 #1: 잠긴 빌드는 수락 배너를 세우지 않는다(본 것으로만 적는다).
            if (!duelsLocked) onInviteArrived?.invoke(invite)
        }
    }

    /** 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다(배너가 시계를 읽지 않게 하는 장치). */
    fun scheduleInviteExpiry() {
        expiryTask?.cancel()
        expiryTask = null
        val dates = incoming.map { it.expiresAt } + listOfNotNull(outgoing?.expiresAt)
        val earliest = dates.minOrNull() ?: return
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
        val alive = incoming.filter { it.expiresAt > now }
        if (alive != incoming) incoming = alive
        val sent = outgoing
        if (sent != null && sent.expiresAt <= now) {
            outgoing = null
            setNotice(GomokuNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }
}

/**
 * 차례 경고(내 차례 마지막 3초)가 이 판에서 **설 수 있는가**(Swift `GomokuTurnWarning.watchesMyClock(_ match:)` — 부르는 꼴도 같다).
 * 판정식은 W1-b [GomokuTurnWarning.watchesMyClock] 원시 인자 서명이고, **판이 없으면 스토어가 false** 로 접는다(W1-b 머리말의 약속).
 */
fun GomokuTurnWarning.watchesMyClock(match: GomokuMatchState?): Boolean {
    if (match == null) return false
    return GomokuTurnWarning.watchesMyClock(
        isFinished = match.isFinished,
        deadline = match.deadline?.timeIntervalSince1970,
        turn = match.turn,
        myColor = match.myColor,
    )
}
