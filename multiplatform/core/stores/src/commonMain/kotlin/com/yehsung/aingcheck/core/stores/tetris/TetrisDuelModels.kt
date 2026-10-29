// 원본: Sources/CheckCore/TetrisDuelStore.swift:30-424(호스트 · 화면 값 타입 · 문구 표) @ 1b8260d
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelCell
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.TetrisRPCStatus

// 1:1 테트리스 대결 스토어의 **값 타입**(v0.3.60). 맥·폰 공용(코어). 스토어 본체는 TetrisDuelStore.kt.

/**
 * 테트리스 스토어가 네트워크·세션·루비 미러를 빌리는 곳(Swift `TetrisDuelStoreHost = GomokuStoreHost`).
 *
 * Swift 는 오목 호스트 프로토콜을 그대로 쓴다(같은 소유자가 세 게임의 호스트). Kotlin 은 W2-a 의 [SessionHost] 를 넓힌다 —
 * 오목·체스 쪽(W2-d)이 같은 꼴을 만들면 조립 지점(K11)이 한 객체로 셋을 다 구현한다. 테트리스 스토어가 읽지 않는
 * `realtimeState` 는 여기 두지 않는다(Swift 주석 "멤버는 실제로 읽는 것만").
 *
 * [appConfig] 는 G §8-17 #1 의 앱 구성 계약이다 — 판돈 대결의 **신청·수락**은 `appConfig.duelsEnabled` 로만 가른다.
 */
interface TetrisDuelStoreHost : SessionHost {
    /** 루비 미러(서버 응답으로만 바뀐다 — 오목·체스·상점과 한 칸). */
    var rubyBalance: Long?

    /** 앱 구성(빌드 깃발). 스토어는 이 자리로만 읽는다(W2-a `SessionContext.appConfig` 와 같은 값). */
    val appConfig: AppConfig
}

/** 판돈(서버 CHECK 3·5·10). */
enum class TetrisDuelStake(val rawValue: Int) {
    three(3), five(5), ten(10);

    companion object {
        fun fromRawValue(raw: Int): TetrisDuelStake? = entries.firstOrNull { it.rawValue == raw }
    }
}

data class TetrisDuelUser(
    /** user uuid 소문자. */
    val id: String,
    val displayName: String,
    val avatarURL: String?,
    val characterID: String?,
    val isWorking: Boolean,
    /** 상대 앱이 테트리스 대결을 아는 버전인가(서버 `tetris_capable`). **모르면 불가**다. */
    val isCapable: Boolean,
    /** 오목·체스·테트리스 중 하나라도 진행 중인가(서버가 세 게임을 함께 본다 — 한 사람은 한 판만). */
    val inMatch: Boolean,
    /** 집중 모드(서버가 `target_focused` 로 신청을 막는다). */
    val isFocused: Boolean = false,
) {
    /**
     * [신청] 을 켤 수 있는가 — 서버가 어차피 거절할 상대(구버전 · 대결 중 · 집중)만 끈다.
     * **근무 여부는 보지 않는다**(D1 — 오목·체스처럼 근무 조건이 없다. 클라 근무 선게이트를 만들지 마라).
     */
    val canBeChallenged: Boolean get() = isCapable && !inMatch && !isFocused
}

data class TetrisDuelRecord(val wins: Int, val losses: Int, val draws: Int)

data class TetrisDuelInvite(
    /** match id. */
    val id: String,
    val peer: TetrisDuelUser,
    val stake: Int,
    /** 기기 시계로 보정된 만료 시각. */
    val expiresAt: SwiftDate,
)

/** 판이 끝난 사유. 서버 `tetris_matches.end_reason` CHECK 의 여섯 글자 그대로다(결과 문구는 전수 when). */
enum class TetrisDuelEndReason(val rawValue: String) {
    /** 꼭대기까지 쌓였다(진 사람이 스스로 신고한 탑아웃 — 서버가 믿는 몇 안 되는 주장, D9). */
    topout("topout"),
    resign("resign"),
    /** 보고가 15초 끊겼다(서버 시계로 잰 침묵). 둘 다 끊기면 무승부다. */
    disconnect("disconnect"),
    /** 판 상한 480초 — 무승부·환불. */
    timeCap("time_cap"),
    /** 수락 뒤 30초 안에 둘 다 준비하지 않았다 — 무승부·환불(전적에서 빠진다). */
    noShow("no_show"),
    /** 계정 삭제로 떠난 사람의 패. */
    abandoned("abandoned");

    /** 이 사유는 **언제나** 무승부인가(서버 CHECK). `disconnect` 는 둘 다 가능하므로 여기 없다. */
    val isAlwaysDraw: Boolean
        get() = when (this) {
            timeCap, noShow -> true
            topout, resign, disconnect, abandoned -> false
        }

    companion object {
        fun fromRawValue(raw: String): TetrisDuelEndReason? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** **내 기준** 결과. */
enum class TetrisDuelOutcome { won, lost, draw }

/**
 * 화면 흐름. **신청(보냄·받음)은 phase 가 아니라** `.lobby` 위의 `outgoing`·`incoming` 이다(체스와 같다).
 *  · ready     — 수락됐고 서버가 아직 판 시작을 안 정했다(둘 다 준비 전). 내 준비 보고가 나가는 단계다.
 *  · countdown — 서버가 `start_at`(둘째 준비 + 3초)을 정했고 아직 그 시각 전이다.
 *  · playing   — 판 시계가 0을 넘었다.
 *  · finished  — 서버가 판을 닫았다(결과 화면).
 */
enum class TetrisDuelPhase { lobby, ready, countdown, playing, finished }

/** 흐름과 **따로** 서는 상태 — 이 기기가 지금 대결을 할 수 있는가. */
enum class TetrisDuelAvailability {
    available,

    /** 서버가 `unsupported_client` 를 냈다(이 앱의 프로토콜이 낮다 — 같은 계정의 옛 두 번째 기기 겹). */
    updateRequired,

    /** 서버에 테트리스 RPC 가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창). */
    serverMissing,
}

/** 상대 판 스냅숏(보고가 올 때만 바뀐다 — 하트비트마다 오르는 seq·last_seen 은 **여기 없다**, 관찰자가 매초 깨지 않게). */
data class TetrisDuelOpponentBoard(
    /** 20행 × 10칸(행 0 = 보이는 판 맨 위). 아직 보고가 없으면 전부 빈 칸이다. */
    val cells: List<List<TetrisDuelCell>>,
    /** 판을 한 번이라도 받았는가(빈 판과 "아직 모름" 을 가른다). */
    val hasBoard: Boolean,
    val lines: Int,
    /** 상대가 보낸 공격 누계(서버가 상한으로 자른 값). */
    val attackSent: Int,
    /** 상대 판에 아직 안 들어간 대기 방해 줄. */
    val pending: Int,
    val toppedOut: Boolean,
    val ready: Boolean,
) {
    companion object {
        val emptyCells: List<List<TetrisDuelCell>> =
            List(TetrisGame.visibleRows) { List(TetrisGame.columns) { TetrisDuelCell.Empty } }

        val empty: TetrisDuelOpponentBoard = TetrisDuelOpponentBoard(
            cells = emptyCells, hasBoard = false, lines = 0, attackSent = 0, pending = 0, toppedOut = false, ready = false,
        )
    }
}

/** 대결 한 판의 화면 상태(서버 응답이 바꾸는 값만). */
data class TetrisDuelMatchState(
    val id: String,
    val stake: Int,
    /** 서버 시드. 진행 중 판이면 언제나 있다(수락 때 뽑는다). */
    val seed: Long?,
    val opponent: TetrisDuelUser,
    val acceptedAt: SwiftDate?,
    /** 준비 마감(수락 + 30초). 화면의 "상대를 기다리는 중 n초" 가 읽는다. */
    val readyDeadline: SwiftDate?,
    /** 판 시작(기기 시계 보정 — **표시용**). 판 시계는 단조 시계로 따로 잰다(`duel.startAt`). */
    val startAt: SwiftDate?,
    /** 판 상한(start_at + 480초). */
    val maxEnd: SwiftDate?,
    /** 서버가 내 준비를 받았는가. */
    val meReady: Boolean,
    val opponentBoard: TetrisDuelOpponentBoard,
    val isFinished: Boolean,
    val outcome: TetrisDuelOutcome?,
    val endReason: TetrisDuelEndReason?,
    /** 이 판으로 내 루비가 변한 양(승 +(stake−수수료) · `DuelFee.winnerNet`, 패 −stake, 무 0). */
    val rubyDelta: Int?,
    val finishedAt: SwiftDate?,
)

/** 내 판의 숫자들(조각이 굳을 때만 바뀐다 — 관찰 가능). 판 칸·떨어지는 조각은 `duel.game` 을 직접 읽는다. */
data class TetrisDuelMyStats(
    val lines: Int,
    /** 보낸 공격 누계(상쇄 뒤). */
    val attackSent: Int,
    /** 들어올 방해 줄(대기열 합 — 우물 왼쪽 미터). */
    val pendingGarbage: Int,
    /** 가속 바닥(1 이면 아직 가속 전 — "속도 올라가는 중" 은 `> 1`). */
    val levelFloor: Int,
    val toppedOut: Boolean,
)

/** 로비 "지금 대결 중" 한 건. a/b 는 uuid 오름차순이다. */
data class TetrisDuelLiveMatch(
    val id: String,
    val a: TetrisDuelUser,
    val b: TetrisDuelUser,
    val stake: TetrisDuelStake,
    val startedAt: SwiftDate,
    /** 지금 이 판을 보고 있는 사람 수(v0.3.64). 옛 서버는 안 싣는다 → 0. **0 이면 화면에 아무것도 그리지 않는다.** */
    val watchers: Int = 0,
)

/** 창이 안 보이는 사람에게 "대결이 시작됐어요" 를 알리는 한 건(판 id 마다 한 번). 차례가 없는 게임이라 체스의 `myTurn` 대응물은 없다. */
data class TetrisDuelAttention(val kind: Kind, val matchID: String, val opponentName: String) {
    enum class Kind { matchStarted }
}

data class TetrisDuelRankEntry(
    val id: String,
    /** 서버가 매긴 순위(동률은 같은 숫자 — rank()). */
    val rank: Int,
    val user: TetrisDuelUser,
    val wins: Int,
    val losses: Int,
    val draws: Int,
    /** 승점 = 승 − 패(서버 값). */
    val points: Int,
)

data class TetrisDuelMyRank(
    /** 0판이면 null(순위 밖). */
    val rank: Int?,
    val wins: Int,
    val losses: Int,
    val draws: Int,
    val points: Int,
)

/** 순위표. **`entries` 는 서버 순서 그대로**(재정렬 금지). */
data class TetrisDuelRankingBoard(
    val entries: List<TetrisDuelRankEntry>,
    val me: TetrisDuelMyRank?,
    val recordSince: SwiftDate?,
)

/** 모자란 루비 문구(Swift `CheckCoreShared.shortfallNotice` — 맥 스토어·오목·체스·테트리스가 같은 문장을 쓴다). */
object DuelShortfallText {
    fun shortfallNotice(need: Long?, have: Long?): String {
        if (need == null || have == null || need <= have) return "루비가 모자라요"
        return "루비 ${need - have}개 더 필요해요"
    }
}

/** 테트리스 대결 안내 한 줄의 **유일한 출처**. 진단 어휘(서버·상태·동기화)는 쓰지 않는다. */
object TetrisDuelNoticeText {
    const val tryAgain: String = "잠시 후 다시 시도해 주세요"
    const val checkConnection: String = "연결을 확인하고 다시 시도해 주세요"
    const val updateMine: String = "앱을 업데이트해야 대결할 수 있어요"
    const val signInAgain: String = "다시 로그인해 주세요"
    const val inviteTimedOut: String = "상대가 응답하지 않았어요"

    /** 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대결을 시작함 — 사용자에게는 모두 같은 뜻이다). */
    const val inviteDeclined: String = "상대가 신청을 받지 않았어요"
    const val finishedInvite: String = "이미 끝난 신청이에요"
    const val finishedMatch: String = "이미 끝난 대결이에요"
    const val busy: String = "이미 진행 중인 대결이 있어요"
    const val targetBusy: String = "상대가 다른 대결 중이에요"

    /** 서버에 테트리스 대결이 아직 없다(PGRST202 — 배포 중간 창). */
    const val unavailable: String = "1:1 테트리스는 곧 열려요"

    /** 관전 — 볼 수 없는 판(끝난 지 3분이 넘었거나 숨김 격리). 서버는 있다/없다를 가르지 않는다. */
    const val watchGone: String = "지금은 볼 수 없는 판이에요"

    /** 신청 결과. 근무 조건은 없다(D1) — 클라가 근무를 보고 미리 막는 선게이트를 만들지 마라. */
    fun challenge(status: TetrisRPCStatus, need: Long? = null, have: Long? = null): String = when (status) {
        TetrisRPCStatus.ok -> "신청을 보냈어요"
        TetrisRPCStatus.invalid -> "신청할 수 없는 상대예요"
        TetrisRPCStatus.blackout -> "지금은 조용한 기간이라 신청할 수 없어요"
        TetrisRPCStatus.targetFocused -> "상대가 집중 모드라 신청할 수 없어요"
        TetrisRPCStatus.targetOutdated -> "상대가 앱을 업데이트해야 해요"
        TetrisRPCStatus.busy -> busy
        TetrisRPCStatus.targetBusy -> targetBusy
        TetrisRPCStatus.alreadyPending -> "이미 보낸 신청이 있어요"
        TetrisRPCStatus.insufficient -> DuelShortfallText.shortfallNotice(need, have)
        else -> common(status)
    }

    fun cancel(status: TetrisRPCStatus): String = when (status) {
        TetrisRPCStatus.ok -> "신청을 취소했어요"
        TetrisRPCStatus.notFound, TetrisRPCStatus.notPending, TetrisRPCStatus.expired -> finishedInvite
        else -> common(status)
    }

    /** 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(null). */
    fun respond(accept: Boolean, status: TetrisRPCStatus, side: String? = null, need: Long? = null, have: Long? = null): String? =
        when (status) {
            TetrisRPCStatus.ok -> if (accept) null else "신청을 거절했어요"
            TetrisRPCStatus.notFound, TetrisRPCStatus.notPending -> finishedInvite
            TetrisRPCStatus.expired -> "신청 시간이 지났어요"
            TetrisRPCStatus.invalid -> "받을 수 없는 신청이에요"
            TetrisRPCStatus.busy -> busy
            TetrisRPCStatus.targetBusy -> targetBusy
            TetrisRPCStatus.insufficient ->
                if (side == "challenger") "상대의 루비가 모자라요" else DuelShortfallText.shortfallNotice(need, have)
            else -> common(status)
        }

    /** 기권 결과. 성공은 결과 화면이 말한다(null). 시간 판정이 먼저라 이미 끝났어야 할 판은 `not_active` 가 온다. */
    fun resign(status: TetrisRPCStatus): String? = when (status) {
        TetrisRPCStatus.ok -> null
        TetrisRPCStatus.notActive, TetrisRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    /** 결과 카드의 사유 한 줄(**내 기준** — 승자면 주어가 "상대"). 사유를 모르면 빈 문자열. */
    fun endReason(reason: TetrisDuelEndReason?, outcome: TetrisDuelOutcome?): String = when (reason) {
        null -> ""
        TetrisDuelEndReason.topout -> if (outcome == TetrisDuelOutcome.won) "상대가 꼭대기까지 쌓였어요" else "꼭대기까지 쌓였어요"
        TetrisDuelEndReason.resign -> if (outcome == TetrisDuelOutcome.won) "상대가 기권했어요" else "기권했어요"
        TetrisDuelEndReason.disconnect -> when (outcome) {
            TetrisDuelOutcome.won -> "상대 연결이 끊겼어요"
            TetrisDuelOutcome.lost -> "연결이 끊겼어요"
            TetrisDuelOutcome.draw, null -> "둘 다 연결이 끊겼어요"
        }
        TetrisDuelEndReason.timeCap -> "시간 초과 — 판돈을 돌려받았어요"
        TetrisDuelEndReason.noShow -> "대결이 시작되지 않아 판돈을 돌려받았어요"
        TetrisDuelEndReason.abandoned -> if (outcome == TetrisDuelOutcome.won) "상대가 더 할 수 없게 됐어요" else "대결을 떠났어요"
    }

    fun common(status: TetrisRPCStatus): String = when (status) {
        TetrisRPCStatus.unsupportedClient -> updateMine
        TetrisRPCStatus.notSignedIn -> signInAgain
        else -> tryAgain
    }
}

/** 서버 정수(Long) → 화면 정수. Swift `Int`(64비트)는 화면 값에서 32비트를 넘지 않는다 — 넘으면 끝으로 자른다(조용히 감기지 않게). */
internal fun Long.clampedInt(): Int = coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
