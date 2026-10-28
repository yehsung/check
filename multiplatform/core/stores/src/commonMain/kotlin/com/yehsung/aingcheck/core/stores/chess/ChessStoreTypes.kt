// 원본: Sources/CheckCore/ChessStore.swift:36-551(호스트 · 화면 값 타입 · 입력 2단 · 탭 거절 · 주의 · 문구 표) · Sources/CheckCore/ChessDrag.swift:13-43·65-75(ChessPendingDrop · ChessBoardPointer.Grab) @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.chess.ChessClock
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessPiece
import com.yehsung.aingcheck.core.rules.chess.ChessPieceKind
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ChessRPCStatus

// 체스 화면 값 타입. Swift 는 ChessStore.swift 한 파일이지만 스토어 본문(ChessStore.kt)과 갈랐다(오목과 같은 까닭 — 원본 줄 구간을 머리에 적는다).
// 숫자 규칙(C§2.5): 금액·와이어 카운터·시각(ms)은 Long, 칸·수 번호(ply)처럼 범위가 정해진 값은 Int.
// `ChessPosition` 은 W1-b 의 가변 참조다 — 이 값들에 넣은 국면은 **고치지 않는다**(새 국면은 `ChessRules.apply`·`fromFen` 이 새로 만든다).

/**
 * 체스 스토어가 네트워크·세션·루비 미러를 빌리는 곳. 오목(`GomokuStoreHost`)과 **멤버가 같아 그 문을 그대로 요구한다** — 같은 소유자가
 * 두 게임의 호스트이므로 멤버를 베껴 적은 두 번째 문을 두면 한쪽이 언젠가 빠진다. 체스가 읽을 멤버가 늘어나는 날 갈라라.
 */
typealias ChessStoreHost = GomokuStoreHost

enum class ChessStake(val rawValue: Long) {
    three(3), five(5), ten(10);

    companion object {
        fun fromRawValue(raw: Long?): ChessStake? = entries.firstOrNull { it.rawValue == raw }
    }
}

data class ChessUser(
    /** user uuid 소문자. */
    val id: String,
    val displayName: String,
    val avatarURL: String?,
    val characterID: String?,
    val isWorking: Boolean,
    /** 상대 앱이 체스를 아는 버전인가(서버 `chess_capable`). **모르면 불가**다. */
    val isCapable: Boolean,
    /** 지금 대국 중인가. 서버는 **오목 판까지** 본다(B8 — 한 사람은 한 판만). */
    val inMatch: Boolean,
    /** 소속 센터의 **화면 글자**. 서버 어휘 → 글자 변환은 경계 둘(`peerUser`·`user(from:)`)뿐이다. */
    val center: String? = null,
) {
    val isChessAI: Boolean get() = id == chessAI.id

    companion object {
        /** AI 상대(화면 값). 캐릭터는 **로봇**이다(A6 — id `robot`): 체스를 두는 상대가 기기라는 것을 그림이 말한다. */
        val chessAI: ChessUser = ChessUser(
            id = "ai", displayName = "로봇", avatarURL = null, characterID = "robot",
            isWorking = true, isCapable = true, inMatch = false,
        )
    }
}

data class ChessRecord(val wins: Long, val losses: Long, val draws: Long)

data class ChessInvite(
    /** match id. */
    val id: String,
    val peer: ChessUser,
    val stake: Long,
    /** 기기 시계로 보정된 만료 시각. */
    val expiresAt: SwiftDate,
)

/**
 * 판이 끝난 사유. 서버 `chess_matches.end_reason` CHECK 의 열 글자 그대로다. `timeout` 과 `timeoutInsufficient` 가 **갈려 있는 것이
 * 계약이다**: 앞은 패배, 뒤는 FIDE 6.9 무승부다.
 */
enum class ChessEndReason(val rawValue: String) {
    checkmate("checkmate"),
    resign("resign"),
    timeout("timeout"),
    timeoutInsufficient("timeout_insufficient"),
    stalemate("stalemate"),
    fiftyMove("fifty_move"),
    threefold("threefold"),
    insufficientMaterial("insufficient_material"),
    agreement("agreement"),
    /** 계정 삭제로 둘 수 없게 된 판. **기권과 뜻이 다르다**. */
    abandoned("abandoned");

    /** 이 사유가 무승부인가. **서버 CHECK 의 여섯과 같은 집합**이다. */
    val isDraw: Boolean
        get() = when (this) {
            stalemate, fiftyMove, threefold, insufficientMaterial, agreement, timeoutInsufficient -> true
            checkmate, resign, timeout, abandoned -> false
        }

    companion object {
        fun fromRawValue(raw: String?): ChessEndReason? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** **내 기준** 결과. `ChessRules.outcome` 의 `ChessOutcome`(판이 어떻게 끝났나)과 **다른 축**이다. */
enum class ChessMatchOutcome { won, lost, draw }

enum class ChessPhase { lobby, playing, result }

/** 수 기록 한 줄(화면 기보 · 왕복 검산 재료). [seq] 가 곧 id 다. */
data class ChessMoveRecord(
    val seq: Int,
    val color: ChessColor,
    val move: ChessMove,
    /** 서버가 만든 SAN. **앱이 다시 만들지 않는다**. */
    val san: String,
    /** 그 수를 둔 **뒤**의 FEN. */
    val fen: String,
    /** 그 수를 둔 뒤 **그 사람의** 남은 ms(피셔 가산 포함). */
    val msLeft: Long,
    /** 그 수에 쓴 ms. */
    val msSpent: Long,
) {
    val id: Int get() = seq
}

/**
 * 서버가 말한 시계 네 값 + **클라 보간**(10분 + 한 수 3초 가산, A3).
 * INV-ChessStore-7729ffb6 이식: **이 값은 표시용이고 권위가 아니다.** 서버 응답이 올 때마다 `applyState` 가 네 칸을 통째로 덮어쓴다 —
 * '서버 값보다 적으면 유지' 같은 보정을 넣으면 깨어난 뒤 화면 시계가 서버보다 많이 남은 채로 굳고 사용자는 남았다고 믿는 시간에 깃발이 떨어진다.
 * 깃발 판정도 여기서 하지 않는다(서버가 한다).
 */
data class ChessServerClock(
    val whiteMsLeft: Long,
    val blackMsLeft: Long,
    /** 한 수 가산(ms, 3000). 서버 상수를 베끼지 않고 응답에서 받는다. */
    val incrementMs: Long,
    /** 차례가 시작된 시각(기기 시계 보정 후). 시계가 흐르지 않으면 null. */
    val turnStartedAt: SwiftDate?,
    /** 지금 시간이 흐르는 쪽. 끝난 판·멈춘 시계는 null. */
    val running: ChessColor?,
) {
    fun msLeft(color: ChessColor): Long = if (color == ChessColor.white) whiteMsLeft else blackMsLeft

    /** 보간하지 않은 남은 초 — **음수가 될 수 있다**. 되묻기 판정이 이것을 쓴다. */
    fun rawRemainingSeconds(color: ChessColor, now: SwiftDate): Double {
        val stored = msLeft(color).toDouble() / 1000
        val started = turnStartedAt
        if (running != color || started == null) return stored
        return stored - now.timeIntervalSince(started)
    }

    /** 화면에 그릴 남은 초(0 아래로 안 간다). **잎만 부른다**. */
    fun remainingSeconds(color: ChessColor, now: SwiftDate): Double {
        val raw = rawRemainingSeconds(color, now)
        return if (raw > 0.0) raw else 0.0
    }

    /** 차례 마감(기기 시계). 시계가 멈춰 있으면 null. 서버 `deadline_ms` 와 **같은 값**이라 그 키를 읽지 않는다. */
    val deadline: SwiftDate?
        get() {
            val running = running ?: return null
            val started = turnStartedAt ?: return null
            return started.addingTimeInterval(msLeft(running).toDouble() / 1000)
        }

    companion object {
        /** 서버 값을 받기 전의 자리표시(멈춘 시계). 시작 시간은 `ChessClock.initialMs` 한 곳에서 온다. */
        val initial: ChessServerClock = ChessServerClock(
            whiteMsLeft = ChessClock.initialMs.toLong(), blackMsLeft = ChessClock.initialMs.toLong(), incrementMs = 3_000,
            turnStartedAt = null, running = null,
        )
    }
}

/** 대국 한 판의 화면 상태. */
data class ChessMatchState(
    val id: String,
    val stake: Long,
    val myColor: ChessColor,
    val opponent: ChessUser,
    /** 서버 `match.fen` 그대로(권위, B5). */
    val fen: String,
    /** 그 FEN 을 읽은 국면. **null 이면 판을 그릴 수 없다**(서버 FEN 이 파서를 통과하지 못했다). 결과·루비는 그래도 보여 준다. */
    val position: ChessPosition?,
    val plyCount: Int,
    /** 끝나면 null. */
    val turn: ChessColor?,
    val lastMove: ChessMove?,
    val moves: List<ChessMoveRecord>,
    val clock: ChessServerClock,
    /** 차례인 쪽이 체크인가. 끝난 판은 false. */
    val isInCheck: Boolean,
    /** **서버가 준** 합법 수(내 차례일 때만 채워진다). AI 판에서는 로컬 `ChessRules` 가 채운다. */
    val legalMoves: List<ChessMove>,
    val isFinished: Boolean,
    val outcome: ChessMatchOutcome?,
    val endReason: ChessEndReason?,
    /** 이 판으로 내 루비가 변한 양(승 +`DuelFee.winnerNet` · 패 −stake · 무 0). */
    val rubyDelta: Long?,
    /** 무승부를 제안한 사람의 uuid. */
    val drawOfferBy: String?,
    /** 내가 제안했는가(= 상대의 응답을 기다린다). */
    val drawOfferedByMe: Boolean,
    /** 서버가 말한 **남은 유예 예산**(ms, 판·사람당 1회). 응답에 그 칸이 없으면 null. */
    val whiteGraceMs: Long? = null,
    val blackGraceMs: Long? = null,
) {
    /** 상대가 제안했는가(= 내가 받거나 거절한다). */
    val drawOfferedByOpponent: Boolean get() = drawOfferBy != null && !drawOfferedByMe

    /** 지금 내 차례인가(진행 중 + 차례가 내 색). */
    val isMyTurn: Boolean get() = !isFinished && turn == myColor

    /**
     * 차례쪽 깃발이 떨어지고 **유예까지** 지났는가. 끝난 판은 false.
     * INV-ChessStore-314c15a9 이식: 서버 유예는 **판·사람당 1회 예산**이고 행의 `white_grace_ms`/`black_grace_ms` 에서 깎여 없어진다 —
     * 로비의 전역 `grace_ms` 만 쓰면 예산을 이미 다 쓴 판은 서버에서 벌써 끝났는데 앱은 최대 2초를 더 기다린다. [graceSeconds] 는
     * **그 두 칸이 없을 때만**(옛 서버) 쓰는 폴백이다. 부등호도 서버와 **같다**(`v_over > v_grace`).
     */
    fun isFlagOverdue(now: SwiftDate, graceSeconds: Double): Boolean {
        val turn = turn
        if (isFinished || turn == null) return false
        val budget = graceSecondsLeft(turn) ?: graceSeconds
        return -clock.rawRemainingSeconds(turn, now) > budget
    }

    /** 그 사람에게 **남은** 유예 예산(초). 서버가 그 칸을 안 줬으면 null. */
    fun graceSecondsLeft(color: ChessColor): Double? {
        val ms = (if (color == ChessColor.white) whiteGraceMs else blackGraceMs) ?: return null
        val seconds = ms.toDouble() / 1000
        return if (seconds > 0.0) seconds else 0.0
    }
}

/** 로비 "지금 대결 중" 한 건(관전 입구). **판 내용이 없다**. a/b 는 uuid 오름차순이고 **색이 아니다**. */
data class ChessLiveMatch(
    val id: String,
    val a: ChessUser,
    val b: ChessUser,
    val stake: ChessStake,
    val startedAt: SwiftDate,
    /** 0.3.64 — 이 판을 보고 있는 관전자 수. 서버가 안 싣는 창에서는 0. */
    val watchers: Long = 0,
)

/** 고른 말과 그 말이 갈 수 있는 칸. **스토어가 든다**(뷰 상태가 아니다 — 머리말 ⑧). */
data class ChessSelection(val from: ChessSquare, val targets: Set<ChessSquare>)

/** 폰이 8랭크(흑은 1랭크)에 닿아 **네 말 중 하나를 골라야 하는** 단계. 고르기 전에는 수가 나가지 않는다. */
data class ChessPromotionPrompt(val from: ChessSquare, val to: ChessSquare) {
    /** 고를 수 있는 말(Q R B N — `ChessPieceKind.promotionChoices` 순서 그대로). */
    val choices: List<ChessPieceKind> get() = ChessPieceKind.promotionChoices
}

/** 판을 눌렀는데 수가 안 나간 **이유**. rawValue 는 **로그 어휘**다. 거절을 무음 가드에 뭉쳐 두지 않는다. */
enum class ChessTapRefusal(val rawValue: String) {
    notYourTurn("not-your-turn"),
    busy("busy"),
    /** 빈 칸을 처음 눌렀다(고를 말이 없다). */
    emptySquare("empty-square"),
    /** 상대 말을 눌렀다(고를 수 없다). */
    notMyPiece("not-my-piece"),
    /** 고른 말이 갈 수 없는 칸이다. */
    illegalTarget("illegal-target"),
    finished("finished"),
    signedOut("signed-out"),
    /** 들고 있는 판이 없다. **말하지 않는다**(로그만). */
    noMatch("no-match"),
    /** 서버가 준 FEN 을 읽을 수 없어 판정할 수 없다(서버 버그 — 사용자에게는 일반 안내). */
    unreadableBoard("unreadable-board"),
}

/** 창이 안 보이는 사람에게 "지금 둘 차례" 를 알리는 한 건. 같은 (판 id, ply) 에는 한 번만 만든다. */
data class ChessAttention(val kind: Kind, val matchID: String, val opponentName: String, val plyCount: Int) {
    enum class Kind { matchStarted, myTurn }
}

/**
 * **끌어 놓은 말이 답을 기다리는 동안** 도착 칸에 머물게 하는 꼬리표(ChessDrag.swift). 1:1 판은 서버가 권위라 놓는 순간 판을 바꾸지 않는다 —
 * 이 값 하나만 세워 화면이 "출발 칸을 비우고 도착 칸에 그린다". 이 값이 남으면 **유령 말**이 된다 — `ChessStore.pendingDrop` 이 읽을 때마다
 * 판·수 번호·차례·출발 칸의 말을 다시 맞춰 본다.
 */
data class ChessPendingDrop(
    val matchID: String,
    /** 놓을 때의 수 번호(= 그때의 `plyCount`). */
    val ply: Int,
    val from: ChessSquare,
    val to: ChessSquare,
    /** 놓은 말(수를 **두기 전**의 말 — 승격하는 폰은 고르는 동안 폰으로 서 있다). */
    val piece: ChessPiece,
)

/**
 * 누른 칸에서 끌기가 될 수 있는가(Swift `ChessBoardPointer.Grab`). 포인터 해석기 자체(`ChessBoardPointer`)는 화면 갈래(W4-a) 몫이고 —
 * C§3.2 "ChessDrag 옮기지 않음, 순수 계산은 앱 갈래가 필요하면 가져간다" — 스토어 문 `grab(at:)` 이 돌려주는 이 셋만 여기 둔다.
 */
enum class ChessDragGrab {
    /** 지금 끌 수 있는 내 말. */
    movable,
    /** 내 말인데 지금은 못 끈다(내 차례가 아니다 · 보내는 중이다 · 갈 곳이 없다). 뗄 때 한 번 탭 거절이 난다. */
    stuck,
    /** 빈 칸 · 상대 말. */
    none,
}

/**
 * 체스 안내 한 줄의 **유일한 출처**. 진단 어휘(서버·상태·동기화·프로토콜)는 쓰지 않는다 — 사용자가 **할 수 있는 일**을 말한다.
 */
object ChessNoticeText {
    const val tryAgain: String = "잠시 후 다시 시도해 주세요"
    const val checkConnection: String = "연결을 확인하고 다시 시도해 주세요"
    const val updateMine: String = "앱을 업데이트해야 대결할 수 있어요"
    const val signInAgain: String = "다시 로그인해 주세요"
    const val notYourTurn: String = "상대 차례예요"
    const val inviteTimedOut: String = "상대가 응답하지 않았어요"
    /** 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대국을 시작함). */
    const val inviteDeclined: String = "상대가 신청을 받지 않았어요"
    const val finishedInvite: String = "이미 끝난 신청이에요"
    const val finishedMatch: String = "이미 끝난 대국이에요"
    /** 고른 말이 갈 수 없는 칸이다. */
    const val cannotMove: String = "둘 수 없는 자리예요"
    /** 앞 착수·기권이 아직 왕복 중이라 잠긴 동안 또 눌렀다. */
    const val sending: String = "보내는 중이에요"
    const val busy: String = "이미 진행 중인 대국이 있어요"
    const val targetBusy: String = "상대가 다른 대국 중이에요"
    /** 서버가 내 수를 거절했다(합법 수가 아니다). 판을 다시 받아 그린다. */
    const val illegalMove: String = "지금은 둘 수 없는 수예요"
    /** 시계 밀림으로 수를 못 받았다(`retry`). **시간패가 아니다** — 다시 누르면 된다. */
    const val moveNotCounted: String = "다시 한 번 눌러 주세요"

    // 무승부 제안(체스에만 있는 왕복).
    const val drawOffered: String = "무승부를 제안했어요"
    const val drawOfferPending: String = "상대가 먼저 무승부를 제안했어요"
    const val drawDeclinedByMe: String = "무승부 제안을 거절했어요"
    const val drawOfferGone: String = "무승부 제안이 사라졌어요"

    // 관전.
    const val watchGone: String = "지금은 볼 수 없는 판이에요"
    /** 서버에 체스가 아직 없다(PGRST202). status 가 아니라 throw 로 오는 실패다. */
    const val unavailable: String = "체스는 곧 열려요"

    /** 신청 결과. v0.3.44 서버는 근무 조건이 없다 — 클라가 근무를 보고 미리 막는 선게이트를 만들지 마라. */
    fun challenge(status: ChessRPCStatus, need: Long? = null, have: Long? = null): String = when (status) {
        ChessRPCStatus.ok -> "신청을 보냈어요"
        ChessRPCStatus.invalid -> "신청할 수 없는 상대예요"
        ChessRPCStatus.blackout -> "지금은 조용한 기간이라 신청할 수 없어요"
        ChessRPCStatus.targetFocused -> "상대가 집중 모드라 신청할 수 없어요"
        ChessRPCStatus.targetOutdated -> "상대가 앱을 업데이트해야 해요"
        ChessRPCStatus.busy -> busy
        ChessRPCStatus.targetBusy -> targetBusy
        ChessRPCStatus.alreadyPending -> "이미 보낸 신청이 있어요"
        ChessRPCStatus.insufficient -> SharedText.shortfallNotice(need, have)
        else -> common(status)
    }

    fun cancel(status: ChessRPCStatus): String = when (status) {
        ChessRPCStatus.ok -> "신청을 취소했어요"
        ChessRPCStatus.notFound, ChessRPCStatus.notPending, ChessRPCStatus.expired -> finishedInvite
        else -> common(status)
    }

    /** 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(null). */
    fun respond(accept: Boolean, status: ChessRPCStatus, side: String? = null, need: Long? = null, have: Long? = null): String? =
        when (status) {
            ChessRPCStatus.ok -> if (accept) null else "신청을 거절했어요"
            ChessRPCStatus.notFound, ChessRPCStatus.notPending -> finishedInvite
            ChessRPCStatus.expired -> "신청 시간이 지났어요"
            ChessRPCStatus.invalid -> "받을 수 없는 신청이에요"
            ChessRPCStatus.busy -> busy
            ChessRPCStatus.targetBusy -> targetBusy
            ChessRPCStatus.insufficient -> if (side == "challenger") "상대의 루비가 모자라요" else SharedText.shortfallNotice(need, have)
            else -> common(status)
        }

    /** 착수 결과. **성공과 `stale` 은 말하지 않는다**(null). */
    fun move(status: ChessRPCStatus): String? = when (status) {
        ChessRPCStatus.ok, ChessRPCStatus.stale -> null
        ChessRPCStatus.illegal -> illegalMove
        ChessRPCStatus.retry -> moveNotCounted
        ChessRPCStatus.notYourTurn -> notYourTurn
        ChessRPCStatus.notActive, ChessRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    /** 기권 결과. 성공은 결과 화면이 말한다(null). 서버는 기권보다 **깃발을 먼저** 신고한다. */
    fun resign(status: ChessRPCStatus): String? = when (status) {
        ChessRPCStatus.ok -> null
        ChessRPCStatus.notActive, ChessRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    /** 무승부 제안 결과. */
    fun offerDraw(status: ChessRPCStatus): String? = when (status) {
        ChessRPCStatus.ok -> drawOffered
        ChessRPCStatus.offerPending -> drawOfferPending
        ChessRPCStatus.notActive, ChessRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    /** 무승부 응답 결과. **수락 성공은 결과 화면이 말한다**(null). */
    fun respondDraw(accept: Boolean, status: ChessRPCStatus): String? = when (status) {
        ChessRPCStatus.ok -> if (accept) null else drawDeclinedByMe
        ChessRPCStatus.noOffer -> drawOfferGone
        ChessRPCStatus.notActive, ChessRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    /** 탭 거절 한 줄. null 이면 **말할 것이 없다**. 나머지는 전부 이미 있는 문구를 **다시 쓴다**. */
    fun tapRefusal(refusal: ChessTapRefusal): String? = when (refusal) {
        ChessTapRefusal.notYourTurn -> notYourTurn
        ChessTapRefusal.busy -> sending
        ChessTapRefusal.emptySquare -> null // 빈 칸을 헛누른 것 — 혼내지 않는다
        ChessTapRefusal.notMyPiece -> null // 상대 말을 눌러 본 것 — 같은 이유로 조용하다
        ChessTapRefusal.illegalTarget -> cannotMove
        ChessTapRefusal.finished -> finishedMatch
        ChessTapRefusal.signedOut -> signInAgain
        ChessTapRefusal.noMatch -> null
        ChessTapRefusal.unreadableBoard -> tryAgain
    }

    private fun common(status: ChessRPCStatus): String = when (status) {
        ChessRPCStatus.unsupportedClient -> updateMine
        ChessRPCStatus.unauthorized -> signInAgain
        else -> tryAgain
    }
}
