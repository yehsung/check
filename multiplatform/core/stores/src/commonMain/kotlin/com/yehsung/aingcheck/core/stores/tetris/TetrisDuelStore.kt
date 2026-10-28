// 원본: Sources/CheckCore/TetrisDuelStore.swift:426-1602(스토어) @ 1b8260d
package com.yehsung.aingcheck.core.stores.tetris

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.tetrisCancel
import com.yehsung.aingcheck.core.net.tetrisChallenge
import com.yehsung.aingcheck.core.net.tetrisLobby
import com.yehsung.aingcheck.core.net.tetrisResign
import com.yehsung.aingcheck.core.net.tetrisRespond
import com.yehsung.aingcheck.core.net.tetrisState
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelBoard
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelSession
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyMatchRow
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyMe
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.core.wire.games.TetrisInviteRow
import com.yehsung.aingcheck.core.wire.games.TetrisPeerRow
import com.yehsung.aingcheck.core.wire.games.TetrisPlayerRow
import com.yehsung.aingcheck.core.wire.games.TetrisRPCStatus
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import com.yehsung.aingcheck.core.wire.games.TetrisUserRow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.abs
import kotlin.time.TimeSource

// 1:1 테트리스 대결 스토어(v0.3.60) — 화면 상태 · 서버 동기화 · 판 구동 · 보고 루프 · RPC 호출. 맥·폰 공용(코어).
//
// 본은 `ChessStore` 다. **같은 규약을 그대로 베끼고**(아래 ①~⑥) 테트리스에서 달라지는 자리만 바꿨다.
//
// ── 베낀 규약 ──
//  ① **서버가 권위다.** 판 상태(시작 시각·상대 판·공격 누계)·결과·루비는 RPC 응답으로만 바뀐다. 낙관적 차감은 없다.
//  ② **시각은 서버 시계로 보정한다**(`noteServerNow` · `deviceDate`). 단 판 시계는 벽시계가 아니라 **단조 시계**다(⑦).
//  ③ **판 밖 폴링은 창이 보일 때만 돈다**(보낸 신청 5초 · 로비 30초 — 체스와 같다). 판 중에는 보고 루프가 그 일을 한다.
//  ④ **늦게 온 응답은 버린다.** 세대 두 개(`resetGeneration` + `host.sessionGeneration`)가 로그아웃·계정 전환 뒤의 응답을,
//     판 세대(`duelGeneration`)가 판이 바뀐 뒤의 보고 응답을, 서버 seq(나·상대)가 같은 판의 옛 스냅숏을 버린다.
//  ⑤ **사용자 문구는 `TetrisDuelNoticeText` 한 곳에만 있다.**
//  ⑥ **신호는 합친다**(`requestSync` — 도는 중 온 신호는 뒤따르는 한 번).
//
// ── 테트리스에서 새로 생긴 자리 ──
//  ⑦ **판은 스토어가 든다**(`duel` — `TetrisDuelSession`). 화면 상태에 두면 창이 가려지거나 최소화될 때 판이 멈춘다.
//     설계 D10: 판 시간은 화면 프레임이 아니라 **단조 시계**(`uptime`)로 흐르고, 스토어의 판 루프(`gameLoopStepSeconds`)가
//     창과 무관하게 `advance` 를 부른다. 창이 보이면 화면의 프레임 루프가 `tick()` 을 더 자주 부를 뿐이다(같은 시각이면 멱등).
//     `duel` 은 **관찰 대상이 아니다** — 프레임마다 바뀌는 값이라 관찰하면 그 값을 읽는 모든 화면이 매 걸음 무효화된다.
//  ⑧ **보고 루프**(설계 §4.1). 1초 하트비트 · 공격 누계 증가와 탑아웃은 곧바로(최소 간격 0.25초) · 한 번에 하나만 나간다.
//  ⑨ **준비 = 첫 보고**. 창이 화면에 떠 있을 때만 낸다(`isWindowVisible`) — 서버가 30초 뒤 무승부(no_show)로 판돈을 돌려준다(D4).
//
// ── Kotlin 이식 ──
//  · Swift `@MainActor` 한 스레드 규약 그대로 — 이 스토어는 [scope](앱은 메인 디스패처, 시험은 시험 디스패처) 한 곳에서만 돈다.
//  · Swift `Task {}` = [scope] `launch`. Swift `@Observable` var = Compose `mutableStateOf`. `@ObservationIgnored` = 일반 필드.
//  · Swift `weak var host` 는 강한 참조다(공용 코드에 약참조가 없다) — 로그아웃은 [reset] 이 세대로 늦은 응답을 버린다.
//  · G §8-17 #1: 판돈 대결의 **신청·수락**은 `host.appConfig.duelsEnabled` 가 켜진 빌드에서만 나간다([duelsEnabled]).

/** 스토어 호출 하나의 결과(Swift `Result<T, Error>`). null 이 따로 "버린 결과(세션 없음·세대가 밀림·취소)" 다. */
sealed interface DuelCall<out T> {
    data class Success<T>(val value: T) : DuelCall<T>
    data class Failure(val error: Exception) : DuelCall<Nothing>
}

/** NaturalKoCollation(W1-c — Swift `localizedStandardCompare` 대응)을 foundation [Collation] 으로. 조립 지점이 다른 것을 넣을 수 있다. */
object StoreNaturalCollation : Collation {
    override fun compare(a: String, b: String): Int = NaturalKoCollation.compare(a, b)
}

/** 초(Double) → 지연 ms. 무한·아주 큰 값은 [Long.MAX_VALUE] — `delay(Long.MAX_VALUE)` 는 예약 없이 영원히 기다린다(시험의 '재운 루프'). */
internal fun delayMillis(seconds: Double): Long {
    if (seconds.isNaN() || seconds <= 0) return 0
    if (!seconds.isFinite() || seconds >= Long.MAX_VALUE / 1000.0) return Long.MAX_VALUE
    return (seconds * 1000).toLong().coerceAtLeast(1)
}

class TetrisDuelStore(
    host: TetrisDuelStoreHost? = null,
    /** 이 스토어의 일이 도는 곳(Swift `@MainActor`). 앱은 메인, 시험은 시험 디스패처. */
    val scope: CoroutineScope,
    /**
     * 이 스토어의 벽시계 '지금'(서버 시각 보정·신청 만료 — Swift `clock = { Date() }`). 벽시계는 조립 지점이 넣는다
     * (구조 시험 — 시스템 벽시계는 조립 지점 밖 금지). 폰 조립은 `{ sessionStore.clock.now() }`, 시험은 가상 시계.
     */
    var clock: () -> SwiftDate,
    /** 로비 이름 정렬(Swift `localizedStandardCompare`). */
    val collation: Collation = StoreNaturalCollation,
    var logger: Logger? = null,
) {
    /** 네트워크·세션·루비 미러를 빌리는 곳. null 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다. */
    var host: TetrisDuelStoreHost? = host
        private set

    /** 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다. */
    fun attach(host: TetrisDuelStoreHost) {
        this.host = host
    }

    companion object {
        /** 보낸 신청이 떠 있을 때 그 판의 상태를 보는 주기(초) — 체스와 같다. 조회 하나가 수락·거절·만료를 다 말한다. */
        const val outgoingPollSeconds: Double = 5.0

        /** 로비 목록 재조회 주기(초). */
        const val lobbyPollSeconds: Double = 30.0

        /** 팝오버를 열 때 로비를 다시 읽는 스로틀(초). 신청 TTL(60초)보다 짧다. */
        const val menuLobbyThrottleSeconds: Double = 30.0

        /** 로비를 보고 있는 동안 순위표 재조회 주기(초). */
        const val rankingPollSeconds: Double = 60.0

        /** 창 열기와 창 표시가 같은 조회를 두 번 쏘지 않게 하는 간격(초). */
        const val reloadDedupeSeconds: Double = 1.0

        /** 서버 시계 오프셋을 다시 재는 문턱(초). */
        const val serverClockToleranceSeconds: Double = 0.25

        /** 같은 신청을 다시 읽었을 때 만료가 이만큼 안쪽으로만 다르면 기존 값을 쓴다(초). */
        const val inviteExpiryToleranceSeconds: Double = 1.0

        /** 보고가 이만큼 연달아 실패하면 `connectionTrouble` 을 세운다(화면: "연결 확인 중"). */
        const val reportFailureLimit: Int = 2

        /** 관전 중 남의 판을 다시 읽는 주기(초). 서버 보고가 1초라 2초면 충분하다. */
        const val watchPollSeconds: Double = 2.0

        /** 관전 조회가 이만큼 연달아 실패하면 관전을 내리고 안내 한 줄을 남긴다(빈 화면이 영영 폴링하지 않게). */
        const val watchFailureLimit: Int = 3

        /**
         * 나가 있는 보고가 이만큼(단조 시계 초) 답이 없으면 **버리고** 새 보고를 낸다(리뷰 RV2).
         * 왜: 보고는 한 번에 하나라 멎은 요청 하나가 하트비트를 전부 막는다. 세션 요청 타임아웃(15초)은 서버 침묵 판정
         * (`tetris_silence_ms` 15초)과 같아서, 그대로 두면 망이 이미 돌아왔어도 그 15초로 연결 끊김 패가 난다.
         * 3초면 침묵 창 15초 안에 다섯 번을 시도한다. 보고 값은 전부 누계이고 서버 seq 가 옛 보고를 stale 로 버리므로
         * 버린 보고가 늦게 닿아도 안전하다(그 답은 `reportTicket` 으로 버린다). 버린 보고는 실패 한 번으로 센다.
         */
        const val reportStallSeconds: Double = 3.0

        internal const val TAG: String = "tetris-duel"

        /** 같은 신청을 다시 읽었을 때 만료가 문턱 안쪽으로만 다르면 기존 값을 그대로 쓴다(관찰자를 헛되게 깨우지 않게). */
        fun steadyInvite(fresh: TetrisDuelInvite, previous: TetrisDuelInvite?): TetrisDuelInvite {
            if (previous == null || previous.id != fresh.id || previous.stake != fresh.stake || previous.peer != fresh.peer ||
                abs(previous.expiresAt.timeIntervalSince(fresh.expiresAt)) >= inviteExpiryToleranceSeconds
            ) return fresh
            return previous
        }

        /** 상대 행 → 판 스냅숏. 글자판이 깨졌으면 **들고 있던 판을 그대로** 둔다(깨진 판을 그리지 않는다). */
        fun opponentBoard(row: TetrisPlayerRow?, previous: TetrisDuelOpponentBoard?): TetrisDuelOpponentBoard {
            val decoded = row?.board?.let { TetrisDuelBoard.decode(it) }
            return TetrisDuelOpponentBoard(
                cells = decoded ?: previous?.cells ?: TetrisDuelOpponentBoard.emptyCells,
                hasBoard = decoded != null || previous?.hasBoard == true,
                lines = row?.lines?.clampedInt() ?: previous?.lines ?: 0,
                attackSent = maxOf(row?.garbageSent?.clampedInt() ?: 0, previous?.attackSent ?: 0),
                pending = row?.pending?.clampedInt() ?: previous?.pending ?: 0,
                toppedOut = (row?.toppedOut ?: false) || (previous?.toppedOut ?: false),
                ready = (row?.ready ?: false) || (previous?.ready ?: false),
            )
        }

        /** 판이 **막 끝났는가**(v0.3.64) — 새 판이 끝났고, 같은 판의 끝난 모양을 이미 들고 있던 게 아니다. 순수 함수라 시험이 값으로 잰다. */
        fun matchJustFinished(old: TetrisDuelMatchState?, new: TetrisDuelMatchState?): Boolean {
            if (new == null || !new.isFinished) return false
            return !(old?.id == new.id && old.isFinished)
        }

        /** 판 상태 변화 한 줄(없으면 null). 판 교체·끝남·시작 시각·준비만 본다 — 상대 판·루비는 이 줄을 만들지 않는다. */
        fun matchTransitionLine(old: TetrisDuelMatchState?, new: TetrisDuelMatchState?): String? {
            fun finished(m: TetrisDuelMatchState?) = m?.isFinished ?: false
            fun started(m: TetrisDuelMatchState?) = m?.startAt != null
            fun ready(m: TetrisDuelMatchState?) = m?.meReady ?: false
            val sameMatch = old?.id == new?.id
            if (sameMatch && finished(old) == finished(new) && started(old) == started(new) && ready(old) == ready(new)) return null
            return "state ready=${ready(new)} started=${started(new)} finished=${finished(new)} " +
                "reason=${new?.endReason?.rawValue ?: "none"} sameMatch=$sameMatch"
        }

        /** 서버 사람 행 → 화면 값(로비). `capable` 이 null 이면 **불가**다. */
        fun user(row: TetrisUserRow): TetrisDuelUser? {
            val id = row.id?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
            return TetrisDuelUser(
                id = id,
                displayName = row.displayName ?: "",
                avatarURL = row.avatarUrl,
                characterID = row.character,
                isWorking = row.isWorking ?: false,
                isCapable = row.capable ?: false,
                inMatch = row.inMatch ?: false,
                isFocused = row.focusMode ?: false,
            )
        }

        /**
         * 로비 정렬: 도전할 수 있는 근무자 → 근무 중·가능(대결 중) → 근무 중 → 나머지, 그 안은 이름순.
         * **서버 정렬과 같은 규칙**이라 재정렬이 아니라 되맞춤이다(서버는 working desc → capable desc → 이름 → id).
         */
        fun sortedForLobby(users: List<TetrisDuelUser>, collation: Collation): List<TetrisDuelUser> {
            fun rank(user: TetrisDuelUser): Int = when {
                user.isWorking && user.isCapable && !user.inMatch -> 0
                user.isWorking && user.isCapable -> 1
                user.isWorking -> 2
                else -> 3
            }
            return users.withIndex().sortedWith { l, r ->
                val lr = rank(l.value)
                val rr = rank(r.value)
                if (lr != rr) return@sortedWith lr.compareTo(rr)
                val order = collation.compare(l.value.displayName, r.value.displayName)
                if (order != 0) return@sortedWith order
                l.index.compareTo(r.index)
            }.map { it.value }
        }
    }

    // MARK: 화면 상태 (관찰 대상 — Compose 스냅숏)

    var phase: TetrisDuelPhase by mutableStateOf(TetrisDuelPhase.lobby)
    var availability: TetrisDuelAvailability by mutableStateOf(TetrisDuelAvailability.available)
    var users: List<TetrisDuelUser> by mutableStateOf(emptyList())
    var record: TetrisDuelRecord? by mutableStateOf(null)

    /** 받은 신청(서버가 여럿을 준다 — 최신이 앞). 화면은 [visibleIncomingInvites]·[visibleIncoming] 을 읽는다. */
    var incoming: List<TetrisDuelInvite> by mutableStateOf(emptyList())

    /** 보낸 신청(부분 유니크 인덱스로 한 사람당 하나뿐이다). */
    var outgoing: TetrisDuelInvite? by mutableStateOf(null)

    private val matchState = mutableStateOf<TetrisDuelMatchState?>(null)
    var match: TetrisDuelMatchState?
        get() = matchState.value
        set(value) {
            val old = matchState.value
            matchState.value = value
            matchTransitionLine(old, value)?.let { logNotice(it) }
            // 내 판이 섰으면(끝난 판 포함) 관전은 내려간다. 세대를 올려 나가 있던 관전 응답도 함께 버린다.
            // INV-TetrisDuelStore-6dba3deb 이식: 바깥에 알리기(`onMatchFinished`)보다 **먼저** 둔다 — 그 콜백은 조회를 띄우므로,
            // 관전을 내리기 전에 부르면 "내 판이 끝났는데 관전도 켜져 있는" 한 틱을 바깥이 보게 된다.
            if (value != null && spectating != null) dropSpectating()
            if (matchJustFinished(old, value)) onMatchFinished?.invoke()
        }

    /** 내 판의 숫자들(조각이 굳을 때만 바뀐다). 판이 없으면 null. */
    var myStats: TetrisDuelMyStats? by mutableStateOf(null)
    var notice: String? by mutableStateOf(null)
    var isBusy: Boolean by mutableStateOf(false)
    var isWindowVisible: Boolean by mutableStateOf(false)

    /** 서버 응답으로만 갱신(host 에도 반영). */
    var rubyBalance: Int? by mutableStateOf(null)
    var lobbyLoadFailed: Boolean by mutableStateOf(false)
    var hasLoadedLobby: Boolean by mutableStateOf(false)

    /** 로비 "지금 대결 중" 목록(서버 순서 그대로). */
    var liveMatches: List<TetrisDuelLiveMatch> by mutableStateOf(emptyList())

    /** 보고가 연달아 실패하는 중(판 화면의 "연결 확인 중"). 다음 성공이 내린다. */
    var connectionTrouble: Boolean by mutableStateOf(false)

    // 순위(로직은 TetrisDuelStoreGame.kt 의 순위 절).
    /** **순위 적재의 주 스위치. 기본 false.** 공용 스토어라 그리지도 않는 기기가 순위를 당기지 않게 한다. */
    var rankingEnabled: Boolean by mutableStateOf(false)
    var ranking: TetrisDuelRankingBoard? by mutableStateOf(null)
    var rankingLoadFailed: Boolean by mutableStateOf(false)
    var hasLoadedRanking: Boolean by mutableStateOf(false)

    /** 서버에 `tetris_ranking` 이 아직 없다(PGRST202). */
    var rankingUnavailable: Boolean by mutableStateOf(false)

    // 관전(로직은 TetrisDuelStoreWatch.kt).
    /**
     * **관전의 주 스위치. 기본 false.** 공용 스토어라 관전을 그리지도 않는 기기가 `tetris_watch` 를 2초마다 당기지
     * 않게 한다. 꺼져 있으면 진입(`startWatching`)·조회(`refreshWatch`)·폴링(`pollWatch`)이 **한 번도** 안 돈다.
     * 켜는 곳은 배선 한 줄이다(`rankingEnabled` 와 **따로** 둔다 — 순위 없이 관전만 여는 날이 온다).
     */
    var spectatorFeaturesEnabled: Boolean by mutableStateOf(false)

    /** 관전 중인 남의 판(null = 관전 중 아님). */
    var spectating: TetrisSpectateState? by mutableStateOf(null)

    /**
     * 지금 이 판을 보고 있는 사람 수. **한 칸을 둘이 나눠 쓴다** — 대국 중이면 내 판의 수(`tetris_state`·`tetris_report` 응답),
     * 관전 중이면 보는 판의 수(`tetris_watch_live`). 관전·대국이 내려가면 0 이다.
     */
    var spectatorCount: Int by mutableStateOf(0)

    /** 서버에 `tetris_watch` 가 아직 없다(PGRST202). **관전 입구를 잠그는 신호는 이것뿐이다.** */
    var watchUnavailable: Boolean by mutableStateOf(false)

    /**
     * 서버에 `tetris_watch_live` 만 없다 → 관전자 수 칸을 접었다(관전 자체는 멀쩡하다).
     * INV-TetrisDuelStore-e61f589a 이식: [watchUnavailable] 과 **반드시 따로** 둔다 — 겸업시키면 "관전자 수가 없다" 는 이유로
     * 관전 입구가 통째로 잠긴다(체스가 `rankingUnavailable` 겸업으로 데인 자리). 화면은 이 깃발이 서면 눈 아이콘을 안 그린다.
     */
    var spectatorCountUnavailable: Boolean by mutableStateOf(false)

    /** 관전 장부(요청 시각·in-flight·세대). 관찰 대상이 아니다. */
    val watchRuntime: TetrisWatchRuntime = TetrisWatchRuntime()

    /** 차단으로 걷어낸 상대(소유자가 채운다). 코어 목록은 서버 답 그대로 두고 화면이 읽는 파생값만 거른다. */
    var hiddenPeerIDs: Set<String> by mutableStateOf(emptySet())

    /** 로비 상대 목록(화면용). */
    val visibleUsers: List<TetrisDuelUser>
        get() = if (hiddenPeerIDs.isEmpty()) users else users.filter { it.id !in hiddenPeerIDs }

    /** 받은 신청 전부(화면용 — 차단한 사람이 보낸 것은 뺀다). */
    val visibleIncomingInvites: List<TetrisDuelInvite>
        get() = if (hiddenPeerIDs.isEmpty()) incoming else incoming.filter { it.peer.id !in hiddenPeerIDs }

    /** 배너·메뉴바 점이 읽는 받은 신청 하나(가장 최근). **스토어가 만료를 걷은 값만** 읽는다 — 시각과 비교하지 마라. */
    val visibleIncoming: TetrisDuelInvite? get() = visibleIncomingInvites.firstOrNull()

    /**
     * G §8-17 #1: 이 빌드가 판돈 대결의 **신청·수락**을 내는가(앱 구성 깃발 `duelsEnabled`, 기본 꺼짐). 호스트가 없으면 false.
     * 꺼진 빌드는 [challenge]·[respond](수락)가 요청을 내지 않고, 화면 게이트(`GamesTetrisDuelChallengeGate` ·
     * `GamesTetrisDuelStakeSend` · `GamesTetrisDuelAcceptGate`)가 입구를 세우지 않는다. 거절·취소·관전·순위는 깃발과 무관하다.
     */
    val duelsEnabled: Boolean get() = host?.appConfig?.duelsEnabled ?: false

    // MARK: UI 트랙이 앱에서 물리는 문

    var presentWindow: (() -> Unit)? = null
    var dismissWindow: (() -> Unit)? = null
    var onInviteArrived: ((TetrisDuelInvite) -> Unit)? = null
    var requestAttention: (() -> Unit)? = null
    var onAttention: ((TetrisDuelAttention) -> Unit)? = null

    /**
     * v0.3.64: 내 1:1 판이 끝난 것을 **처음 본** 순간(결과를 받은 순간) 한 번 부른다 — 같은 판을 다시 받아도(폴링 · 받은함) 또 안 부른다.
     * 폰은 여기서 일일 미션 진행을 한 번 묻는다(새 타이머 없이 이벤트로).
     */
    var onMatchFinished: (() -> Unit)? = null

    // MARK: 판 (관찰 대상 아님 — 머리말 ⑦)

    /** 내 판 구동기. **관찰 대상이 아니다** — 화면은 프레임 루프 안에서 읽는다. 입력은 이 스토어의 입력 문으로만 넣는다. */
    var duel: TetrisDuelSession? = null
        internal set

    /** `duel` 이 어느 판의 것인가. */
    var duelMatchID: String? = null
        internal set

    /** 판 구동기를 갈아 끼울 때마다 오른다 — 앞 판에 나간 보고의 응답이 새 판을 건드리지 못하게 한다. */
    var duelGeneration: Int = 0
        internal set
    var gameLoopJob: Job? = null
        internal set
    internal var gameLoopToken: Int = 0

    /** 지금 나가 있는 보고(한 번에 하나). 시험이 `reportJob?.join()` 으로 기다린다. */
    var reportJob: Job? = null
        internal set
    var reportInFlight: Boolean = false
        internal set

    /** 나가 있는 보고를 낸 단조 시각(멎음 판정 — [reportStallSeconds]). 나가 있는 보고가 없으면 null. */
    var reportSentAt: Double? = null
        internal set

    /** 보고를 낼 때마다 오른다 — 멎어서 버린 보고의 늦은 답이 그 뒤에 낸 보고의 자리를 건드리지 못하게 한다. */
    var reportTicket: Int = 0
        internal set
    var reportFailureStreak: Int = 0
        internal set

    /** 서버가 말한 내 seq·상대 seq 의 최댓값(같은 판의 옛 스냅숏을 버리는 기준 — 머리말 ④). */
    var heldMySeq: Int = 0
        internal set
    var heldOpponentSeq: Int = 0
        internal set

    /** 서버가 말한 상대 공격 누계의 최댓값. 판 시작 전에 온 공격은 시작 뒤 `tick` 이 이 값으로 다시 넣는다. */
    var opponentAttackTotal: Int = 0
        internal set

    /** 상대의 마지막 보고 시각(기기 시계 보정). "상대 연결 확인 중" 표시 재료. */
    var opponentLastSeenAt: SwiftDate? = null
        internal set

    // MARK: 내부 장부 (관찰 대상 아님)

    private val monotonic = TimeSource.Monotonic.markNow()

    /** **단조 시계**(초). 판 시계·보고 간격은 이것만 쓴다 — 사용자가 시계를 돌려도 판이 건너뛰거나 멈추지 않는다. */
    var uptime: () -> Double = { monotonic.elapsedNow().inWholeNanoseconds / 1e9 }

    /** 판 밖 폴링 루프의 한 걸음(초). */
    var pollStepSeconds: Double = 0.5

    /** 판 루프의 한 걸음(초). 창과 무관하게 돈다(D10). 시험은 무한으로 재우고 `tick(now)` 을 직접 부른다. */
    var gameLoopStepSeconds: Double = 0.05

    var serverClockOffset: Double = 0.0
        private set
    private var hasServerClockOffset = false
    var resetGeneration: Int = 0
        private set

    /** 창이 완전히 가려졌다. **폴링만** 이 값을 본다(판은 계속 흐른다). */
    var isWindowOccluded: Boolean = false
        private set
    var stateInFlightID: String? = null
        private set
    private var pendingStateID: String? = null
    private var stateInFlight = false
    private var stateAgain = false
    private var lobbyInFlight = false
    internal var rankingInFlight = false

    /** 서버가 말한 내 진행 중 대결 id. */
    var activeMatchID: String? = null
        private set
    var seenInviteIDs: Set<String> = emptySet()
        private set

    /** "대결이 시작됐어요" 를 이미 알린 판 id. */
    private var announcedMatchIDs: MutableSet<String> = mutableSetOf()

    /** [로비로] 로 접은 끝난 판. 늦게 온 그 판의 상태가 사용자를 결과 화면으로 끌고 가지 않게 한다. */
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

    /** 신호 재조회 직렬화(도는 중이면 뒤따르는 한 번으로 합친다). */
    var syncJob: Job? = null
        private set
    private var syncPendingTrailing = false

    /** 신청 만료(초) — 응답이 만료를 안 실어 준 드문 경우의 기본값(서버 `tetris_invite_ttl_seconds()`). */
    var inviteTTLSeconds: Double = 60.0
        private set

    /** 이 기기에서 보낸 신청을 새로 세울 때마다 오른다. 그보다 **먼저** 나간 로비 응답이 방금 보낸 신청을 지우지 않게 한다. */
    private var outgoingRevision = 0
    private var lobbyRequestOutgoingRevision = 0

    internal fun logNotice(message: String) {
        logger?.log(LogLevel.INFO, TAG, message)
    }

    // MARK: - 창

    /** 창을 띄우고 로비·판을 읽는다. `focusMatchID` 는 배너·말풍선에서 온 경로의 대상이다. */
    fun openWindow(focusMatchID: String?) {
        if (host?.session != null) {
            val focus = focusMatchID?.lowercase()
            // 곧 이어질 windowDidShow 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다.
            lastLobbyRequestAt = clock()
            scope.launch {
                refreshLobby()
                if (focus != null && focus != match?.id && incoming.none { it.id == focus }) {
                    refreshMatch(focus)
                }
            }
        }
        presentWindow?.invoke()
    }

    /** 창이 실제로 보이기 시작했다. 폴링 시작 · 로비 재조회 · **준비 보고의 문이 열린다**(머리말 ⑨). */
    fun windowDidShow() {
        if (!isWindowVisible) isWindowVisible = true
        isWindowOccluded = false
        startPolling()
        // 준비를 기다리던 판이면 지금 곧바로 낸다(다음 판 루프 걸음을 기다리지 않는다).
        if (duel != null) tick()
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastLobbyRequestAt) >= reloadDedupeSeconds) {
            scope.launch { refreshLobby() }
        }
        if (rankingEnabled && phase == TetrisDuelPhase.lobby && now.timeIntervalSince(lastRankingRequestAt) >= reloadDedupeSeconds) {
            scope.launch { loadRanking() }
        }
        spectatorWindowDidShow(now)
    }

    /** 창이 숨었다·최소화됐다. 폴링만 멈춘다 — **판은 계속 흐른다**(D10). 눌린 키는 놓는다(숨은 창은 keyUp 을 못 받는다). */
    fun windowDidHide() {
        if (isWindowVisible) isWindowVisible = false
        isWindowOccluded = false
        releaseAllKeys()
        stopPolling()
    }

    /**
     * 창을 **정말 닫았다**. **닫기는 기권이 아니다** — 진행 중 판은 그대로 흐르고 다시 열면 이어진다.
     * 끝난 판은 여기서 접는다(다음에 창을 열면 결과가 아니라 로비가 선다 — 체스 0.3.50 과 같다).
     */
    fun windowDidClose() {
        releaseAllKeys()
        // 창을 정말 닫았으면 관전에서 나간 것이다(요청은 쏘지 않는다 — 테트리스에 `leave` RPC 는 없다).
        if (spectating != null) stopWatching()
        foldFinishedMatch()
    }

    /** 창의 가림 상태가 바뀌었다. **폴링만** 멈추고 되살린다 — `isWindowVisible` 은 건드리지 않는다. */
    fun windowOcclusionDidChange(visible: Boolean) {
        isWindowOccluded = !visible
        if (visible) {
            startPolling()
        } else {
            releaseAllKeys()
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
            val result = perform { service, token -> service.tetrisLobby(token) } ?: return
            when (result) {
                is DuelCall.Success -> applyLobby(result.value)
                is DuelCall.Failure -> {
                    if (isSchemaMissing(result.error)) {
                        logNotice("lobby unavailable — tetris functions missing on server")
                        noteServerMissing()
                    } else {
                        logNotice("lobby request failed")
                    }
                    // 빈 목록을 "대결할 사람이 없다" 로 믿게 하지 않는다.
                    if (!lobbyLoadFailed) lobbyLoadFailed = true
                }
            }
        } finally {
            if (generation == resetGeneration) lobbyInFlight = false
        }
    }

    suspend fun applyLobby(response: TetrisLobbyResponse) {
        if (response.status != TetrisRPCStatus.ok) {
            logNotice("lobby refused status=${response.status.rawValue}")
            when (response.status) {
                TetrisRPCStatus.unsupportedClient -> noteUpdateRequired()
                TetrisRPCStatus.notSignedIn -> setNotice(TetrisDuelNoticeText.signInAgain)
                else -> Unit
            }
            if (!lobbyLoadFailed) lobbyLoadFailed = true
            return
        }
        noteServerNow(response.serverNowMs)
        if (availability != TetrisDuelAvailability.available) availability = TetrisDuelAvailability.available
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (!hasLoadedLobby) hasLoadedLobby = true
        response.users?.let { rows ->
            val mapped = sortedForLobby(rows.mapNotNull(::user), collation)
            if (users != mapped) users = mapped
        }
        response.me?.let { me ->
            applyRuby(me.rubyBalance?.clampedInt())
            val fresh = TetrisDuelRecord(
                wins = me.wins?.clampedInt() ?: 0, losses = me.losses?.clampedInt() ?: 0, draws = me.draws?.clampedInt() ?: 0,
            )
            if (record != fresh) record = fresh
            // INV-TetrisDuelStore-56265b14 이식: 신청을 옮기기 **전에** 적는다 — 보낸 신청이 판으로 이어졌는지(becameMatch)를 이 값으로 가른다.
            activeMatchID = me.activeMatchId?.lowercase()
        }
        // **서버 순서 그대로**. 키가 아예 없으면(옛 서버) 들고 있던 목록을 지우지 않는다.
        response.matches?.let { rows ->
            val live = rows.mapNotNull(::liveMatch)
            if (liveMatches != live) liveMatches = live
        }
        applyLobbyInvites(response.me)
        val active = activeMatchID
        if (active != null && (match?.id != active || match?.isFinished == true)) {
            refreshMatch(active)
        }
    }

    /** 로비 `me` 의 신청 둘(받은 것 배열 · 보낸 것 하나)을 화면 값으로 옮긴다. */
    private fun applyLobbyInvites(me: TetrisLobbyMe?) {
        // 받은 신청 — 서버 목록이 권위다(서버가 만료·숨김·차단을 이미 걸렀다).
        val rows = me?.incoming
        if (rows != null) {
            val fresh = mutableListOf<TetrisDuelInvite>()
            for (row in rows) {
                val invite = invite(row, row.from) ?: continue
                fresh += steadyInvite(invite, incoming.firstOrNull { it.id == invite.id })
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

        // 보낸 신청.
        val serverOutgoing = me?.outgoing?.let { invite(it, it.to) }
        // 이 응답은 방금 이 기기가 세운 보낸 신청보다 먼저 나갔다 — 그 신청이 없다고 해도 사실이 아니다.
        val predatesOutgoing = lobbyRequestOutgoingRevision < outgoingRevision
        val gone = outgoing
        if (gone != null && serverOutgoing?.id != gone.id && !predatesOutgoing) {
            // 판으로 이어졌으면(= 수락) 거절 안내를 하지 않는다 — 진행 중 판이 있으면 서버가 내 다른 신청을 거둔 것이다.
            val becameMatch = gone.id == activeMatchID || gone.id == match?.id
            if (!becameMatch) {
                setNotice(if (gone.expiresAt > clock()) TetrisDuelNoticeText.inviteDeclined else TetrisDuelNoticeText.inviteTimedOut)
            }
            outgoing = null
        }
        // 방금 세운 신청보다 먼저 나간 응답은 **다른** 신청으로 덮지 않는다(그 응답의 보낸 신청은 이미 지나간 것이다).
        if (serverOutgoing != null && serverOutgoing.id != match?.id &&
            (!predatesOutgoing || outgoing == null || outgoing?.id == serverOutgoing.id)
        ) {
            val steady = steadyInvite(serverOutgoing, outgoing)
            if (outgoing != steady) outgoing = steady
        }
        scheduleInviteExpiry()
    }

    suspend fun refreshMatch() {
        refreshMatch(match?.id ?: activeMatchID)
    }

    /**
     * 한 판(또는 신청)의 상태를 읽는다. 도는 중에 또 불리면 뒤따르는 한 번으로 합친다.
     * 도는 중에 **다른 판** id 가 들어오면 기억했다가 지금 것을 끝낸 뒤 그 판을 한 번 읽는다(막 수락된 판을 놓치지 않게).
     */
    suspend fun refreshMatch(rawID: String?) {
        val requested = rawID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return
        if (host?.session == null) return
        if (stateInFlight) {
            if (requested == stateInFlightID) stateAgain = true else pendingStateID = requested
            return
        }
        stateInFlight = true
        val generation = resetGeneration
        var nextID: String? = requested
        while (nextID != null) {
            val id: String = nextID
            nextID = null
            stateInFlightID = id
            do {
                stateAgain = false
                lastStateRequestAt = clock()
                if (outgoing?.id == id) lastOutgoingRequestAt = lastStateRequestAt
                val result = perform { service, token -> service.tetrisState(token, id) }
                if (generation != resetGeneration) return
                when (result) {
                    is DuelCall.Success -> {
                        val response = result.value
                        noteServerNow(response.serverNowMs)
                        when (response.status) {
                            TetrisRPCStatus.ok -> response.state?.let { applyState(it, uptime()) }
                            TetrisRPCStatus.notFound -> dropMatchOrInvite(id)
                            TetrisRPCStatus.unsupportedClient -> noteUpdateRequired()
                            else -> logNotice("state refused status=${response.status.rawValue}")
                        }
                    }
                    is DuelCall.Failure -> if (isSchemaMissing(result.error)) noteServerMissing()
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

    enum class StateApplyOutcome { applied, ignored }

    /**
     * 서버 상태 묶음을 화면 상태로 옮긴다 — **판과 신청을 한 경로로 가르는 유일한 깔때기**다
     * (보고 응답 · 상태 조회 · 수락 · 기권이 전부 여기로 온다).
     *
     * @param receivedAt 이 응답을 **받은** 단조 시각(판 시작 시각을 단조 시계로 옮기는 기준). null 이면 지금.
     *
     * 늦은 응답 가드 넷(머리말 ④):
     *  (a) [로비로] 로 접은 끝난 판의 상태는 무시한다.
     *  (b) 이미 끝남으로 든 판에 진행 중 응답이 오면 무시한다(끝나기 전에 읽힌 옛 스냅숏).
     *  (c) 같은 판을 진행 중으로 들고 있는데 **내 seq 나 상대 seq 가 들고 있는 값보다 작으면** 옛 스냅숏이다 —
     *      옮기면 상대 판이 한 박자 전으로 되돌아간다. (끝난 응답은 예외 — 되돌릴 수 없는 사실이다.)
     *  (d) 모르는 status 는 아무것도 바꾸지 않는다(서버가 어휘를 넓히는 날 진행 중 판을 내려 버리지 않게).
     */
    fun applyState(payload: TetrisStatePayload, receivedAt: Double? = null): StateApplyOutcome {
        val id = payload.matchId?.lowercase()?.takeIf { it.isNotEmpty() } ?: return StateApplyOutcome.ignored
        noteServerNow(payload.serverNowMs)
        applyRuby(payload.rubyBalance?.clampedInt())
        val status = payload.status ?: ""
        when (status) {
            "pending" -> {
                // 신청은 로비가 통째로 준다(상대·판돈·만료). 상태로는 카드를 세우지 않는다 — 들고 있지 않은 신청이면 로비를 다시 읽는다.
                if (match?.id == id) return StateApplyOutcome.ignored       // 진행 중으로 든 판의 옛 스냅숏
                if (incoming.none { it.id == id } && outgoing?.id != id) {
                    scope.launch { refreshLobby() }
                }
                return StateApplyOutcome.applied
            }
            "active", "finished" -> Unit
            "declined", "cancelled", "expired" -> {
                dropMatchOrInvite(
                    id,
                    if (status == "expired") TetrisDuelNoticeText.inviteTimedOut else TetrisDuelNoticeText.inviteDeclined,
                )
                return StateApplyOutcome.applied
            }
            else -> {
                logNotice("state ignored — unknown status=$status")
                return StateApplyOutcome.ignored
            }
        }

        val isFinished = status == "finished"
        if (isFinished && id in dismissedMatchIDs && match?.id != id) return StateApplyOutcome.ignored
        // 다른 판을 **진행 중으로** 들고 있으면 이 응답은 지나간 판의 늦은 것이다(한 사람은 한 판만 — 서버 게이트).
        // 받으면 살아 있는 판 구동기가 버려지고 화면이 옛 판으로 넘어간다(오목이 같은 자리를 막는다).
        val current = match
        if (current != null && current.id != id && !current.isFinished) return StateApplyOutcome.ignored
        val base = if (match?.id == id) match else null
        if (base != null && base.isFinished && !isFinished) return StateApplyOutcome.ignored
        val mySeq = payload.me?.seq?.clampedInt() ?: 0
        val opponentSeq = payload.opponent?.seq?.clampedInt() ?: 0
        if (base != null && !isFinished && (mySeq < heldMySeq || opponentSeq < heldOpponentSeq)) {
            return StateApplyOutcome.ignored
        }
        if (base == null) {
            // 다른 판으로 넘어간다 — 앞 판의 장부를 비운다.
            heldMySeq = 0
            heldOpponentSeq = 0
            opponentAttackTotal = 0
            opponentLastSeenAt = null
        }
        heldMySeq = maxOf(heldMySeq, mySeq)
        heldOpponentSeq = maxOf(heldOpponentSeq, opponentSeq)
        opponentAttackTotal = maxOf(opponentAttackTotal, payload.opponent?.garbageSent?.clampedInt() ?: 0)
        deviceDate(payload.opponent?.lastSeenMs)?.let { opponentLastSeenAt = it }

        val myID = host?.session?.userID?.lowercase()
        val opponentRow = payload.opponent
        val opponentID = opponentRow?.id?.lowercase() ?: base?.opponent?.id ?: ""
        val opponent = peerUser(opponentRow?.id, opponentRow?.displayName, opponentRow?.avatarUrl, opponentRow?.character, !isFinished)
            ?: base?.opponent
            ?: TetrisDuelUser(
                id = opponentID, displayName = "", avatarURL = null, characterID = null,
                isWorking = false, isCapable = true, inMatch = !isFinished,
            )
        val winner = payload.winner?.lowercase()
        val outcome: TetrisDuelOutcome? = when {
            !isFinished -> null
            payload.result == "draw" -> TetrisDuelOutcome.draw
            winner != null && myID != null && winner == myID -> TetrisDuelOutcome.won
            winner != null && winner.isNotEmpty() -> TetrisDuelOutcome.lost
            else -> null
        }
        val stake = payload.stake?.clampedInt() ?: base?.stake ?: 0
        val rubyDelta = outcome?.let {
            when (it) {
                // 승자 순이익 = 판돈 − 수수료(서버 `duel_fee` 와 같은 식). 무승부 환불엔 수수료가 없다.
                TetrisDuelOutcome.won -> DuelFee.winnerNet(stake)
                TetrisDuelOutcome.lost -> -stake
                TetrisDuelOutcome.draw -> 0
            }
        }
        val next = TetrisDuelMatchState(
            id = id, stake = stake, seed = payload.seed ?: base?.seed, opponent = opponent,
            acceptedAt = deviceDate(payload.acceptedAtMs) ?: base?.acceptedAt,
            readyDeadline = deviceDate(payload.readyDeadlineMs) ?: base?.readyDeadline,
            // 시작 시각은 한 번 정해지면 사라지지 않는다(옛 응답의 null 이 지우지 못하게).
            startAt = deviceDate(payload.startAtMs) ?: base?.startAt,
            maxEnd = deviceDate(payload.maxEndMs) ?: base?.maxEnd,
            meReady = (payload.me?.ready ?: false) || (base?.meReady ?: false),
            opponentBoard = opponentBoard(opponentRow, base?.opponentBoard),
            isFinished = isFinished, outcome = outcome,
            endReason = payload.endReason?.let { TetrisDuelEndReason.fromRawValue(it) },
            rubyDelta = rubyDelta,
            finishedAt = deviceDate(payload.finishedAtMs) ?: base?.finishedAt,
        )

        // 판 구동기.
        if (isFinished) {
            if (duelMatchID == id) duel?.finish() else discardDuel()
            stopGameLoop()
        } else {
            prepareDuel(id, next.seed, payload.me, payload.startAtMs)
            if (duelMatchID == id) {
                val startMs = payload.startAtMs
                val serverNow = payload.serverNowMs
                if (startMs != null && serverNow != null) {
                    duel?.syncStart(startMs, serverNow, receivedAt ?: uptime())
                }
                duel?.adoptServerSeq(mySeq)
                duel?.absorbOpponentAttack(opponentAttackTotal)
                startGameLoop()
            }
        }

        val justFinished = isFinished && base?.isFinished == false
        val previous = match
        val windowWasVisible = isWindowVisible
        // 이 판이 신청이었으면 카드를 걷는다(수락된 쪽·내가 수락한 쪽 모두).
        if (incoming.any { it.id == id }) incoming = incoming.filter { it.id != id }
        if (outgoing?.id == id) outgoing = null
        if (match != next) match = next
        // 내 판을 보고 있는 사람 수. **`match` 대입 뒤**에 적는다 — 그 setter 가 관전을 내리며 수를 0 으로 되돌린다.
        // 옛 서버는 이 칸을 안 싣는다 → 0(화면은 0 이면 아무것도 그리지 않는다).
        val watchers = maxOf(0, payload.watchers?.clampedInt() ?: 0)
        if (spectatorCount != watchers) spectatorCount = watchers
        activeMatchID = if (isFinished) null else id
        refreshPhase()
        syncStats()
        if (!isFinished && (previous?.id != id || previous.isFinished)) {
            // 새 판이 열렸다 — 로비에서 남긴 안내("신청을 보냈어요")는 판 상태줄을 가린다.
            setNotice(null)
            noteMatchStarted(next, windowWasVisible)
        }
        if (justFinished) {
            // 전적은 로비 응답에만 있다. 끝난 순간 한 번 다시 읽어 결과 뒤 로비가 옛 전적을 보이지 않게 한다.
            scope.launch { refreshLobby() }
            noteOwnMatchFinishedForRanking()
        }
        return StateApplyOutcome.applied
    }

    // MARK: - 동작

    /**
     * 신청. 판돈은 **고른 값을 그대로** 받는다 — 판돈 창은 처음에 아무것도 안 고른 채로 열린다(체스와 같다).
     * G §8-17 #1: [duelsEnabled] 가 꺼진 빌드는 요청을 내지 않는다(서버 변경 없이 클라 빌드로만 가른다).
     */
    suspend fun challenge(userID: String, stake: TetrisDuelStake) {
        if (!duelsEnabled) return
        if (isBusy || host?.session == null) return
        val target = userID.lowercase()
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            val result = perform { service, token -> service.tetrisChallenge(token, target, stake.rawValue.toLong()) } ?: return
            when (result) {
                is DuelCall.Failure -> noteActionFailure(result.error)
                is DuelCall.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance?.clampedInt())
                    setNotice(TetrisDuelNoticeText.challenge(response.status, response.need?.clampedInt(), response.have?.clampedInt()))
                    if (response.status != TetrisRPCStatus.ok) logNotice("challenge refused status=${response.status.rawValue}")
                    when (response.status) {
                        TetrisRPCStatus.ok -> {
                            val id = response.matchId?.lowercase() ?: return
                            val peer = users.firstOrNull { it.id == target } ?: TetrisDuelUser(
                                id = target, displayName = "", avatarURL = null, characterID = null,
                                isWorking = false, isCapable = true, inMatch = false,
                            )
                            val expiresAt = deviceDate(response.expiresAtMs) ?: clock().addingTimeInterval(inviteTTLSeconds)
                            outgoingRevision += 1
                            outgoing = TetrisDuelInvite(id = id, peer = peer, stake = stake.rawValue, expiresAt = expiresAt)
                            lastOutgoingRequestAt = clock()
                            scheduleInviteExpiry()
                        }
                        TetrisRPCStatus.unsupportedClient -> noteUpdateRequired()
                        TetrisRPCStatus.alreadyPending, TetrisRPCStatus.busy, TetrisRPCStatus.targetBusy,
                        TetrisRPCStatus.targetOutdated, TetrisRPCStatus.targetFocused,
                        -> refreshLobby()   // 목록의 칩이 틀렸다는 뜻이다 — 다시 읽어 행을 사실에 맞춘다
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
            val result = perform { service, token -> service.tetrisCancel(token, id) } ?: return
            when (result) {
                is DuelCall.Failure -> noteActionFailure(result.error)
                is DuelCall.Success -> {
                    val response = result.value
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance?.clampedInt())
                    setNotice(TetrisDuelNoticeText.cancel(response.status))
                    when (response.status) {
                        TetrisRPCStatus.ok, TetrisRPCStatus.notFound, TetrisRPCStatus.notPending, TetrisRPCStatus.expired -> {
                            if (outgoing?.id == id) {
                                outgoing = null
                                scheduleInviteExpiry()
                            }
                            // not_pending 은 취소보다 수락이 먼저 닿았다는 뜻일 수 있다 — 진행 중 판을 찾아 온다.
                            if (response.status == TetrisRPCStatus.notPending) refreshLobby()
                        }
                        TetrisRPCStatus.unsupportedClient -> noteUpdateRequired()
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /**
     * 수락·거절. G §8-17 #1: [duelsEnabled] 가 꺼진 빌드는 **수락** 요청을 내지 않는다(거절은 판돈이 움직이지 않아 막지 않는다).
     */
    suspend fun respond(inviteID: String, accept: Boolean) {
        if (accept && !duelsEnabled) return
        if (isBusy || host?.session == null) return
        val id = inviteID.lowercase()
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            val result = perform { service, token -> service.tetrisRespond(token, id, accept) } ?: return
            when (result) {
                is DuelCall.Failure -> noteActionFailure(result.error)
                is DuelCall.Success -> {
                    val response = result.value
                    val receivedAt = uptime()
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance?.clampedInt())
                    setNotice(TetrisDuelNoticeText.respond(accept, response.status, response.side, response.need?.clampedInt(), response.have?.clampedInt()))
                    if (response.status != TetrisRPCStatus.ok) logNotice("respond refused status=${response.status.rawValue}")
                    when (response.status) {
                        TetrisRPCStatus.ok -> {
                            incoming = incoming.filter { it.id != id }
                            if (accept) {
                                // 수락하는 순간 서버가 두 사람의 **다른 테트리스 대기 신청을 전부** 닫는다 — 로컬 카드도 함께 걷는다.
                                if (incoming.isNotEmpty()) incoming = emptyList()
                                if (outgoing != null) outgoing = null
                                scheduleInviteExpiry()
                                val state = response.state
                                if (state != null) applyState(state, receivedAt) else refreshMatch(id)
                                if (match?.id != id && !isWindowVisible) presentWindow?.invoke()
                            }
                        }
                        TetrisRPCStatus.notFound, TetrisRPCStatus.notPending, TetrisRPCStatus.expired, TetrisRPCStatus.invalid -> {
                            incoming = incoming.filter { it.id != id }
                            scheduleInviteExpiry()
                        }
                        TetrisRPCStatus.unsupportedClient -> noteUpdateRequired()
                        else -> Unit
                    }
                }
            }
        } finally {
            if (generation == resetGeneration) isBusy = false
        }
    }

    /** 기권(확인은 화면이 받는다). 카운트다운·준비 중에도 된다. 서버가 상대 승 `resign` 으로 정산한다. */
    suspend fun resign() {
        val current = match
        if (isBusy || current == null || current.isFinished || host?.session == null) return
        val id = current.id
        isBusy = true
        setNotice(null)
        val generation = resetGeneration
        try {
            val result = perform { service, token -> service.tetrisResign(token, id) } ?: return
            when (result) {
                is DuelCall.Failure -> noteActionFailure(result.error)
                is DuelCall.Success -> {
                    val response = result.value
                    val receivedAt = uptime()
                    noteServerNow(response.serverNowMs)
                    applyRuby(response.rubyBalance?.clampedInt())
                    setNotice(TetrisDuelNoticeText.resign(response.status))
                    if (response.status == TetrisRPCStatus.unsupportedClient) noteUpdateRequired()
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
            loadRanking()
        }
    }

    /** 끝난 판을 내리고 화면을 로비로 돌린다. 끝난 판을 들고 있지 않으면 false — 아무것도 안 바꾼다. */
    private fun foldFinishedMatch(): Boolean {
        val current = match
        if (current == null || !current.isFinished) return false
        dismissedMatchIDs = dismissedMatchIDs + current.id
        clearMatch()
        setNotice(null)
        return true
    }

    // MARK: - 신호 · 계기 (창 밖에서 아는 길)

    /** 실시간 'tetris' 초인종. 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다. */
    fun handleSignal() {
        requestSync()
    }

    fun requestSync() {
        if (host?.session == null) return
        if (syncJob != null) {
            syncPendingTrailing = true
            return
        }
        val generation = resetGeneration
        syncJob = scope.launch {
            do {
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 조회가 도는 동안 도착한 신호를 지운다.
                syncPendingTrailing = false
                syncOnce()
            } while (syncPendingTrailing && generation == resetGeneration)
            if (generation == resetGeneration) syncJob = null
        }
    }

    /** 신호 한 번의 조회: 진행 중 판이 있으면 그 판의 상태(상대 공격·시작 시각·정산), 아니면 로비(신청 · 진행 중 판 id). */
    suspend fun syncOnce() {
        val current = match
        if (current != null && !current.isFinished) refreshMatch(current.id) else refreshLobby()
    }

    /** 조인 직후·깨어남의 따라잡기: 로비 한 번(+ 그 응답이 가리키는 판). 진행 중 판만 읽으면 그 사이 온 신청을 모른다. */
    suspend fun catchUp() {
        refreshLobby()
    }

    /** 실시간 조인 성공 직후. */
    fun realtimeDidJoin() {
        if (host?.session == null) return
        scope.launch { catchUp() }
    }

    /** 깨어남(앱이 다시 active). 소켓이 끊겼던 사이에 온 신청을 한 번 따라잡는다. */
    fun systemDidWake() {
        if (host?.session == null) return
        scope.launch { catchUp() }
    }

    /** 팝오버·허브 열림(30초 스로틀). 받은 신청 칩의 신선도가 이 계기와 소켓 신호에 달려 있다. */
    fun refreshLobbyIfStale() {
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastMenuLobbyAt) < menuLobbyThrottleSeconds) return
        lastMenuLobbyAt = now
        scope.launch { refreshLobby() }
    }

    // MARK: - 폴링 (창이 보일 때만 · 판 밖)

    fun startPolling() {
        if (pollJob != null || !isWindowVisible || isWindowOccluded) return
        pollToken += 1
        val token = pollToken
        pollJob = scope.launch {
            while (true) {
                delay(delayMillis(pollStepSeconds))
                if (token != pollToken || !isWindowVisible || isWindowOccluded) {
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

    /**
     * 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다.**
     *  · 보낸 신청이 있으면 5초마다 그 판의 상태(수락·거절·만료를 한 조회가 다 말한다)
     *  · 로비를 보고 있으면 30초마다 목록 · 순위는 60초(주 스위치)
     * **판 중에는 조회하지 않는다** — 1초 보고가 상대 판과 판 상태를 함께 받아 온다(같은 일을 두 번 하지 않는다).
     */
    suspend fun pollTick(now: SwiftDate) {
        if (!isWindowVisible || isWindowOccluded || host?.session == null) return
        val sent = outgoing
        if (sent != null && now.timeIntervalSince(lastOutgoingRequestAt) >= outgoingPollSeconds) {
            refreshMatch(sent.id)
        }
        if (!isWindowVisible) return
        if (phase == TetrisDuelPhase.lobby && now.timeIntervalSince(lastLobbyRequestAt) >= lobbyPollSeconds) {
            refreshLobby()
        }
        if (!isWindowVisible) return
        // 관전 중이면 이 걸음은 관전이 가져간다(순위는 돌리지 않는다 — 돌아올 때 로비가 한 번 읽는다).
        if (pollWatch(now)) return
        if (!isWindowVisible) return
        if (rankingEnabled && phase == TetrisDuelPhase.lobby && now.timeIntervalSince(lastRankingRequestAt) >= rankingPollSeconds) {
            loadRanking()
        }
    }

    // MARK: - 리셋

    /**
     * 로그아웃·계정 전환. 창을 닫고 상태를 전부 비운다 — 남기면 다음 사람이 앞 사람의 판·신청·루비를 본다.
     * **배선 값**(`rankingEnabled` · `spectatorFeaturesEnabled` · 시계 · 주기 · UI 문)은 건드리지 않는다.
     */
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
        rankingInFlight = false
        stateInFlightID = null
        pendingStateID = null
        if (phase != TetrisDuelPhase.lobby) phase = TetrisDuelPhase.lobby
        if (availability != TetrisDuelAvailability.available) availability = TetrisDuelAvailability.available
        if (users.isNotEmpty()) users = emptyList()
        if (record != null) record = null
        if (incoming.isNotEmpty()) incoming = emptyList()
        if (outgoing != null) outgoing = null
        if (match != null) match = null
        if (myStats != null) myStats = null
        if (notice != null) notice = null
        if (isBusy) isBusy = false
        if (isWindowVisible) isWindowVisible = false
        if (rubyBalance != null) rubyBalance = null
        if (hiddenPeerIDs.isNotEmpty()) hiddenPeerIDs = emptySet()
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (hasLoadedLobby) hasLoadedLobby = false
        if (liveMatches.isNotEmpty()) liveMatches = emptyList()
        if (connectionTrouble) connectionTrouble = false
        if (ranking != null) ranking = null
        if (rankingLoadFailed) rankingLoadFailed = false
        if (hasLoadedRanking) hasLoadedRanking = false
        if (rankingUnavailable) rankingUnavailable = false
        // 관전. **배선 값인 `spectatorFeaturesEnabled` 는 건드리지 않는다**(끄면 재로그인 뒤 관전이 영영 안 열린다).
        if (spectating != null) spectating = null
        if (spectatorCount != 0) spectatorCount = 0
        if (watchUnavailable) watchUnavailable = false
        if (spectatorCountUnavailable) spectatorCountUnavailable = false
        watchRuntime.clear()
        serverClockOffset = 0.0
        hasServerClockOffset = false
        isWindowOccluded = false
        activeMatchID = null
        seenInviteIDs = emptySet()
        announcedMatchIDs = mutableSetOf()
        dismissedMatchIDs = emptySet()
        outgoingRevision = 0
        lobbyRequestOutgoingRevision = 0
        lastStateRequestAt = DISTANT_PAST
        lastLobbyRequestAt = DISTANT_PAST
        lastOutgoingRequestAt = DISTANT_PAST
        lastMenuLobbyAt = DISTANT_PAST
        lastRankingRequestAt = DISTANT_PAST
        inviteTTLSeconds = 60.0
        dismissWindow?.invoke()
    }

    // MARK: - 내부

    /**
     * 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조.
     * null = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 null 이면 **아무것도 바꾸지 않는다.**
     * 코루틴 취소(전송 실패가 아닌 [CancellationException])는 삼키지 않고 다시 던진다(C§2.4).
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

    /** 서버에 테트리스 RPC 가 아직 없다(PGRST202). */
    fun isSchemaMissing(error: Throwable): Boolean = error == SupabaseWorkServiceError.DatabaseSchemaMissing

    /** 쓰기 동작이 throw 로 실패했다(5xx·오프라인·PGRST202). */
    private fun noteActionFailure(error: Throwable) {
        if (isSchemaMissing(error)) noteServerMissing() else setNotice(TetrisDuelNoticeText.checkConnection)
    }

    internal fun noteServerMissing() {
        if (availability != TetrisDuelAvailability.serverMissing) availability = TetrisDuelAvailability.serverMissing
        setNotice(TetrisDuelNoticeText.unavailable)
    }

    internal fun noteUpdateRequired() {
        if (availability != TetrisDuelAvailability.updateRequired) availability = TetrisDuelAvailability.updateRequired
        setNotice(TetrisDuelNoticeText.updateMine)
    }

    /** 로비 신청 행 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**. */
    private fun invite(row: TetrisInviteRow, peerRow: TetrisPeerRow?): TetrisDuelInvite? {
        val id = row.matchId?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        val stake = row.stake?.clampedInt() ?: return null
        val expiresAt = deviceDate(row.expiresAtMs) ?: return null
        val peer = peerUser(peerRow?.id, peerRow?.displayName, peerRow?.avatarUrl, peerRow?.character, false) ?: return null
        return TetrisDuelInvite(id = id, peer = peer, stake = stake, expiresAt = expiresAt)
    }

    /** 그 id 가 판이었으면 판을 내리고, 신청이었으면 신청 카드를 걷는다(안내가 있으면 한 줄 — 보낸 신청만). */
    private fun dropMatchOrInvite(id: String, noticeText: String? = null) {
        if (match?.id == id) clearMatch()
        if (activeMatchID == id) activeMatchID = null
        if (incoming.any { it.id == id }) {
            incoming = incoming.filter { it.id != id }
            scheduleInviteExpiry()
        }
        if (outgoing?.id == id) {
            outgoing = null
            if (noticeText != null) setNotice(noticeText)
            scheduleInviteExpiry()
        }
    }

    /** 안내줄 한 문(JVM 이름은 [notice] 의 setter 와 겹치지 않게 따로 둔다). */
    @kotlin.jvm.JvmName("updateNotice")
    fun setNotice(text: String?) {
        if (notice != text) notice = text
    }

    internal fun applyRuby(value: Int?) {
        if (value == null) return
        if (rubyBalance != value) rubyBalance = value
        val host = host ?: return
        if (host.rubyBalance != value) host.rubyBalance = value
    }

    /** 판을 내린다(판 구동기·판 루프·보고까지). */
    fun clearMatch() {
        if (match != null) match = null
        // 대국이 내려갔다 — 관전자 수는 내 판의 것이었다.
        if (spectatorCount != 0 && spectating == null) spectatorCount = 0
        discardDuel()
        refreshPhase()
        syncStats()
    }

    /** 진행 중 판으로 **처음** 넘어갔다 — 창을 띄우고 주의를 끈다. 창이 안 보였으면 말풍선 문도 연다(판 id 마다 한 번). */
    private fun noteMatchStarted(next: TetrisDuelMatchState, windowWasVisible: Boolean) {
        if (next.id in announcedMatchIDs) return
        announcedMatchIDs.add(next.id)
        presentWindow?.invoke()
        requestAttention?.invoke()
        if (windowWasVisible) return
        onAttention?.invoke(TetrisDuelAttention(TetrisDuelAttention.Kind.matchStarted, next.id, next.opponent.displayName))
    }

    /** `server_now_ms` 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만. */
    fun noteServerNow(milliseconds: Double?) {
        if (milliseconds == null || !(milliseconds > 0)) return
        val measured = milliseconds / 1000 - clock().timeIntervalSince1970
        if (hasServerClockOffset && abs(measured - serverClockOffset) < serverClockToleranceSeconds) return
        serverClockOffset = measured
        hasServerClockOffset = true
    }

    /** 서버 epoch 밀리초 → 기기 시계의 같은 순간. */
    fun deviceDate(milliseconds: Double?): SwiftDate? {
        if (milliseconds == null || !(milliseconds > 0)) return null
        return SwiftDate(milliseconds / 1000 - serverClockOffset)
    }

    /** 가장 이른 만료 시각에 한 번 깨어나 만료된 신청을 걷는다(배너가 시계를 읽지 않게 하는 장치). */
    fun scheduleInviteExpiry() {
        expiryJob?.cancel()
        expiryJob = null
        val dates = incoming.map { it.expiresAt } + listOfNotNull(outgoing?.expiresAt)
        val earliest = dates.minOrNull() ?: return
        val delaySeconds = maxOf(0.0, earliest.timeIntervalSince(clock())) + 0.25
        val generation = resetGeneration
        expiryJob = scope.launch {
            delay(delayMillis(delaySeconds))
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
            setNotice(TetrisDuelNoticeText.inviteTimedOut)
        }
        scheduleInviteExpiry()
    }

    /** 사람 조각 → 화면 값. 행에 없는 칸은 로비 목록에서 빌린다. */
    fun peerUser(rawID: String?, displayName: String?, avatarURL: String?, character: String?, inMatch: Boolean): TetrisDuelUser? {
        val id = rawID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        val known = users.firstOrNull { it.id == id }
        return TetrisDuelUser(
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

    /** 로비 "지금 대결 중" 한 줄 → 화면 값. 하나라도 모르면 **그 카드를 만들지 않는다**. */
    fun liveMatch(row: TetrisLobbyMatchRow): TetrisDuelLiveMatch? {
        val id = row.id?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
        val a = peerUser(row.a?.id, row.a?.displayName, row.a?.avatarUrl, row.a?.character, true) ?: return null
        val b = peerUser(row.b?.id, row.b?.displayName, row.b?.avatarUrl, row.b?.character, true) ?: return null
        // 판돈은 서버 CHECK 가 3·5·10 으로 묶은 값이다. 서버가 그 표를 넓히는 날 이 줄이 먼저 막는다.
        val stake = row.stake?.let { s -> TetrisDuelStake.fromRawValue(s.clampedInt()) } ?: return null
        val startedAt = deviceDate(row.startedAtMs) ?: return null
        return TetrisDuelLiveMatch(id = id, a = a, b = b, stake = stake, startedAt = startedAt,
            watchers = maxOf(0, row.watchers?.clampedInt() ?: 0))
    }
}

/** Swift `Date.distantPast`(0001-01-01 00:00:00 UTC — 2001 기준 −63,114,076,800초). */
val DISTANT_PAST: SwiftDate = SwiftDate.fromReferenceDate(-63_114_076_800.0)
