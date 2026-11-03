// 원본: Sources/CheckCore/ReversiStore.swift:33-392(호스트 · 화면 값 타입 · ReversiNoticeText) · ReversiStoreAI.swift:61-64(ReversiUser.reversiAI) ·
//       ReversiStoreWatch.swift:7-78(ReversiSpectating) · ReversiStoreRanking.swift:6-57(순위 값) @ 12624739
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.reversi.ReversiScore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiIllegalReason
import com.yehsung.aingcheck.core.wire.games.ReversiMatchStatus
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.wire.games.ReversiRPCStatus
import com.yehsung.aingcheck.core.wire.games.ReversiResult

// 아잉 뒤집기(내부 이름 reversi) 스토어의 값 타입과 문구 표. 스토어 본문은 ReversiStore.kt, AI 연습 갈래는 ReversiStoreAI.kt,
// 관전·순위 갈래는 ReversiStoreWatch.kt 다. Swift 값 타입(struct · `var` 칸)은 Kotlin data class(`val` + copy)로 옮겼다.
// 숫자 눈금: 판돈·수 번호·연속 횟수·관전자 수·전적은 Swift 처럼 Int, 루비 잔액은 호스트 미러와 같은 Long 이다.

/** 네트워크·세션·루비 미러를 빌리는 곳. 오목·체스와 멤버가 같아 그 문을 그대로 쓴다(Swift `typealias ReversiStoreHost = GomokuStoreHost`). */
typealias ReversiStoreHost = GomokuStoreHost

/** 화면 단계. 관전은 phase 가 아니라 `spectating != null` 이다. */
enum class ReversiPhase { lobby, playing, result }

/**
 * 이 앱·서버 조합에서 아잉 뒤집기를 쓸 수 있는가. 로비 ok → [available] · `unsupported_client` → [updateRequired] ·
 * PGRST202(앱이 db push 보다 먼저 나간 창) → [serverMissing].
 */
enum class ReversiAvailability { available, updateRequired, serverMissing }

/** 판돈(루비). 승자 2× · 수수료 0 · 무승부 각자 환불(DEC:19). 판정은 서버가 한다 — 스토어는 서버가 준 잔액만 옮긴다. */
enum class ReversiStake(val rawValue: Int) {
    three(3), five(5), ten(10);

    companion object {
        fun of(raw: Int?): ReversiStake? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** AI 수 선택기. 판과 둘 색을 받아 한 칸(idx)을 돌려준다. null = 둘 곳 없음 — 호출자가 무작위 대타를 둔다. 시험이 결정적 가짜로 갈아 끼운다. */
typealias ReversiAIMoveChooser = suspend (ReversiBoard, ReversiColor) -> Int?

/** 사람 한 명(로비 상대 목록 · 신청 상대 · 판의 두 사람 · 순위 줄 공용). */
data class ReversiUser(
    /** user uuid 소문자. */
    val id: String,
    val displayName: String,
    val avatarURL: String? = null,
    val characterID: String? = null,
    /** 소속 센터의 **화면 글자**. 서버 어휘 → 글자 변환은 스토어 경계에서 한 번만 한다. */
    val center: String? = null,
    val isWorking: Boolean = false,
    /** 상대 앱이 아잉 뒤집기를 아는 버전인가(서버 `reversi_capable`). **모르면 불가**다. */
    val isCapable: Boolean = true,
    /** 지금 어떤 1:1 판이든 두는 중인가(서버 `game__busy_users` — 한 사람은 한 판만). */
    val inMatch: Boolean = false,
    /** 집중 모드 — 신청할 수 없다(`target_focused`). */
    val focusMode: Boolean = false,
) {
    companion object {
        /** AI 상대(화면 값). id 는 uuid 가 아니라 서버 어떤 사람과도 겹치지 않는다(체스 로봇과 같은 얼굴). */
        val reversiAI: ReversiUser = ReversiUser(id = "ai", displayName = "로봇", characterID = "robot", isWorking = true, isCapable = true)
    }
}

/** 받은 신청 한 건(로비 `me.incoming` 한 줄). */
data class ReversiInvite(
    /** match id 소문자. */
    val id: String,
    val peer: ReversiUser,
    val stake: Int,
    /** 기기 시계로 보정한 만료 시각. */
    val expiresAt: SwiftDate,
)

/** 보낸 신청(한 사람당 하나 — 서버 부분 유니크 인덱스). */
data class ReversiOutgoing(
    val id: String,
    val peer: ReversiUser,
    val stake: Int,
    val expiresAt: SwiftDate,
)

/** 로비 "지금 대결 중" 한 줄. **서버 순서 그대로**(최근 순) — 다시 정렬하지 않는다. a/b 는 uuid 오름차순(색이 아니다). */
data class ReversiLiveMatch(
    val id: String,
    val a: ReversiUser,
    val b: ReversiUser,
    val stake: Int,
    val startedAt: SwiftDate,
    /** 관전자 수. 안 싣는 서버면 0(카드는 눈 아이콘을 안 그린다). */
    val watchers: Int = 0,
)

/** 내 전적(로비 `me` 의 wins·losses·draws — 순위표와 같은 서버 함수). */
data class ReversiRecord(val wins: Int, val losses: Int, val draws: Int)

/** 내 기준 판 결과. */
enum class ReversiMatchOutcome { won, lost, draw }

/**
 * 화면이 안 보이는 사람에게 "판이 섰다 / 지금 둘 차례" 를 알리는 한 건. 같은 (판 id, move_count) 에는 한 번만 만든다.
 * 받는 쪽은 `attention.moveCount == match.moveCount` 로 낡은 "내 차례"를 버린다.
 */
data class ReversiAttention(val kind: Kind, val matchID: String, val opponentName: String, val moveCount: Int) {
    enum class Kind { matchStarted, myTurn }
}

/** 내 판 한 판(1:1 또는 AI). 1:1 은 서버 state 를 옮긴 값이고, AI 판은 `ReversiAIGame` 을 옮긴 값이다([isAI]). */
data class ReversiMatchState(
    /** match id 소문자. AI 판은 `"ai-"` 머리말(`ReversiAIGame.isAIMatchID`). */
    val id: String,
    val isAI: Boolean = false,
    val status: ReversiMatchStatus = ReversiMatchStatus.active,
    val stake: Int,
    val myColor: ReversiColor,
    val opponent: ReversiUser,
    val blackUser: ReversiUser? = null,
    val whiteUser: ReversiUser? = null,
    /** **판의 권위**(서버 64자 문자열). */
    val board: ReversiBoard = ReversiBoard.start,
    /** 패스 포함 기록 수 = 마지막 seq. 다음 착수의 `p_expected_seq`. */
    val moveCount: Int = 0,
    /** 지금 둘 색. 끝났으면 null. */
    val turn: ReversiColor? = ReversiColor.black,
    val turnStartedAt: SwiftDate? = null,
    /** 지금 차례의 표시 마감(차례 시작 + 30초, 서버 유예 미포함). 끝났거나 AI 차례·멈춘 AI 시계면 null. */
    val deadline: SwiftDate? = null,
    /** 서버 `legal_moves`(내 차례일 때만 온다, 오름차순). AI 판은 로컬 규칙으로 채운다. */
    val legalMoves: List<Int> = emptyList(),
    /** 수 기록(패스 줄 포함, seq 순). */
    val plies: List<ReversiPly> = emptyList(),
    /** 마지막 **돌** 수의 칸(패스는 건너뛴다). 빨간 점 자리. */
    val lastStoneIdx: Int? = null,
    /** 시간 초과 자동 착수로 놓인 돌의 칸(회색 점). */
    val autoStones: Set<Int> = emptySet(),
    /** 판 위 실제 돌 수(늘). */
    val counts: ReversiCounts = board.counts,
    /** WOF 점수 — 자연 종료만(기권·abandoned 는 null, V-15). */
    val score: ReversiScore? = null,
    val result: ReversiResult? = null,
    val endReason: ReversiEndReason? = null,
    /** 이긴 색. 끝났는데 null 이면 무승부다. */
    val winner: ReversiColor? = null,
    val myAutoStreak: Int = 0,
    val opponentAutoStreak: Int = 0,
    /** 이 수만큼 연달아 자동 착수되면 패(서버 값, 기본 3). */
    val autoAbandonStreak: Int = 3,
    /** 지금 이 판을 보는 사람 수. */
    val watchers: Int = 0,
) {
    val isFinished: Boolean get() = status == ReversiMatchStatus.finished
    val isMyTurn: Boolean get() = !isFinished && turn == myColor

    /** 내 기준 결과(끝난 판만). */
    val outcome: ReversiMatchOutcome?
        get() {
            if (!isFinished) return null
            val result = result ?: return null
            val winner = result.winner ?: return ReversiMatchOutcome.draw
            return if (winner == myColor) ReversiMatchOutcome.won else ReversiMatchOutcome.lost
        }
}

/** 지금 보고 있는 남의 판. 첫 ok 응답 전에는 로비 카드에서 빌린 얼굴·판돈만 있다. */
data class ReversiSpectating(
    val id: String,
    /** 로비 카드에서 빌린 두 얼굴(a·b 순서, **색 모름**). 씨앗을 못 찾았으면 비어 있다. */
    val faces: List<ReversiUser> = emptyList(),
    /** 판돈. 씨앗이 없으면 null 이고 응답의 `match.stake` 가 채운다. */
    val stake: Int? = null,
    /** 서버가 말한 흑·백. **첫 ok 응답 전에는 null** — 이 둘이 서기 전에는 색 배지를 그리지 않는다. */
    val blackUser: ReversiUser? = null,
    val whiteUser: ReversiUser? = null,
    val board: ReversiBoard = ReversiBoard.start,
    val moveCount: Int = 0,
    /** 내가 반영한 마지막 수 번호. 다음 요청의 `p_since_seq` 다. */
    val appliedSeq: Int = 0,
    val plies: List<ReversiPly> = emptyList(),
    val lastStoneIdx: Int? = null,
    val autoStones: Set<Int> = emptySet(),
    /** 끝나면 null. */
    val turn: ReversiColor? = null,
    val turnStartedAt: SwiftDate? = null,
    /** 표시 마감(차례 시작 + 30초). 끝났으면 null. */
    val deadline: SwiftDate? = null,
    val counts: ReversiCounts = board.counts,
    val score: ReversiScore? = null,
    val result: ReversiResult? = null,
    val endReason: ReversiEndReason? = null,
    /** 이긴 색. 끝났는데 null 이면 무승부다. */
    val winner: ReversiColor? = null,
    val blackAutoStreak: Int = 0,
    val whiteAutoStreak: Int = 0,
    val startedAt: SwiftDate? = null,
    val isFinished: Boolean = false,
    /** 관전자 수(watch_live 만 채운다). */
    val watchers: Int = 0,
)

/** 순위표 한 줄. 순위·순서는 **서버 값 그대로**(재정렬 금지). */
data class ReversiRankEntry(
    val id: String,
    /** 서버가 매긴 순위(동률은 같은 숫자, 다음은 건너뛴다 — rank()). */
    val rank: Int,
    val user: ReversiUser,
    val wins: Int,
    val losses: Int,
    val draws: Int,
    /** 승점 = 승 − 패. 서버 값 그대로. */
    val points: Int,
)

/** 내 순위 한 줄. [rank] 는 **0판이면 null**(순위 밖) — 전적은 그래도 있다. */
data class ReversiMyRank(val rank: Int?, val wins: Int, val losses: Int, val draws: Int, val points: Int)

/** 순위표 전체. **[entries] 는 서버 순서 그대로**. [recordSince] 는 전적 컷(없으면 null — 캡션을 안 단다). */
data class ReversiRanking(val entries: List<ReversiRankEntry>, val me: ReversiMyRank?, val recordSince: SwiftDate?)

// MARK: - 문구 표 (사용자 어휘 — 이 표 밖에서 문구를 만들지 마라, §5.6)

/**
 * 아잉 뒤집기 안내 한 줄의 **유일한 출처**(Swift `ReversiNoticeText` 글자 그대로). 게임 이름 글자도 여기 한 곳이다.
 * 진단 어휘(서버·상태·동기화·프로토콜)는 쓰지 않는다 — 사용자가 **할 수 있는 일**을 말한다.
 * 공용 거절은 `ChessNoticeText` 의 같은 줄을 글자 그대로 쓰고 게임 이름만 바꾼다.
 */
object ReversiNoticeText {
    /** 게임 이름(정확히 16바이트 — Release 바이트 검사의 경계, §5.6). 상표 낱말은 쓰지 않는다 — '리버시'는 규칙 설명으로만. */
    const val gameName: String = "아잉 뒤집기"

    const val tryAgain: String = "잠시 후 다시 시도해 주세요"
    const val checkConnection: String = "연결을 확인하고 다시 시도해 주세요"

    /** 내 앱이 옛 버전이다(`unsupported_client` · Availability `updateRequired`). */
    const val updateRequired: String = "앱을 업데이트해 주세요"
    const val signInAgain: String = "다시 로그인해 주세요"
    const val notYourTurn: String = "상대 차례예요"
    const val inviteTimedOut: String = "상대가 응답하지 않았어요"

    /** 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대국을 시작함 — 사용자에게는 모두 같은 뜻이다). */
    const val inviteDeclined: String = "상대가 신청을 받지 않았어요"
    const val finishedInvite: String = "이미 끝난 신청이에요"
    const val finishedMatch: String = "이미 끝난 대국이에요"

    /** 앞 착수·기권이 아직 왕복 중이라 잠긴 동안 또 눌렀다. */
    const val sending: String = "보내는 중이에요"
    const val busy: String = "이미 진행 중인 대국이 있어요"
    const val targetBusy: String = "상대가 다른 대국 중이에요"

    /** 상대 앱이 리버시 RPC 를 모른다(`target_outdated`). 서버 `reversi_android_min_build` 가 닫혀 있는 동안 안드로이드 상대가 이 갈래다. */
    const val targetOutdated: String = "상대 앱이 ${gameName}를 아직 몰라요"

    // 둘 수 없는 칸(`illegal{reason}` · 로컬 거절 공용).
    const val occupied: String = "이미 돌이 있는 칸이에요"
    const val noFlip: String = "뒤집을 돌이 없는 칸이에요"
    const val outOfRange: String = "둘 수 없는 칸이에요"

    // 시간 초과 · 패스.
    /** 내 차례가 30초를 넘겨 서버가 대신 뒀다(`auto_placed`). */
    const val autoPlaced: String = "시간이 지나 자동으로 놓였어요"

    /** 내가 둘 곳이 없어 상대에게 넘어갔다. */
    const val myPass: String = "둘 곳이 없어 차례가 넘어가요"

    /** 상대가 둘 곳이 없어 내 차례가 이어진다. */
    fun opponentPassed(name: String): String = "${name}님이 둘 곳이 없어 내 차례가 이어져요"

    // 관전 · 배포 창.
    /** 볼 수 없는 판(끝난 지 오래됐거나 숨김 격리). 서버는 있다/없다를 가르지 않는다. */
    const val watchGone: String = "지금은 볼 수 없는 판이에요"

    /** 서버에 아잉 뒤집기가 아직 없다(PGRST202 — 배포 중간 창). */
    const val unavailable: String = "${gameName}는 곧 열려요"

    /**
     * 판돈 대결 깃발(G §8-17 #1 `duelsEnabled`)이 꺼진 Android 빌드의 신청·수락 거절 한 줄. **새 글자가 아니다** — 오목·체스·테트리스가 같은
     * 자리에서 쓰는 `ChessNoticeText.updateMine` 과 한 글자도 다르지 않다(맥·아이폰에는 이 깃발이 없어 Swift 표에는 없다).
     */
    const val updateMine: String = "앱을 업데이트해야 대결할 수 있어요"

    /** 불법 수 까닭 → 문구. */
    fun illegal(reason: ReversiIllegalReason): String = when (reason) {
        ReversiIllegalReason.occupied -> occupied
        ReversiIllegalReason.noFlip -> noFlip
        ReversiIllegalReason.outOfRange -> outOfRange
    }

    /** 신청 결과. 서버는 근무 조건이 없다 — 클라가 근무를 보고 미리 막는 선게이트를 만들지 마라. */
    fun challenge(status: ReversiRPCStatus, need: Long? = null, have: Long? = null): String = when (status) {
        ReversiRPCStatus.ok -> "신청을 보냈어요"
        ReversiRPCStatus.invalid -> "신청할 수 없는 상대예요"
        ReversiRPCStatus.blackout -> "지금은 조용한 기간이라 신청할 수 없어요"
        ReversiRPCStatus.targetFocused -> "상대가 집중 모드라 신청할 수 없어요"
        ReversiRPCStatus.targetOutdated -> targetOutdated
        ReversiRPCStatus.busy -> busy
        ReversiRPCStatus.targetBusy -> targetBusy
        ReversiRPCStatus.alreadyPending -> "이미 보낸 신청이 있어요"
        ReversiRPCStatus.insufficient -> SharedText.shortfallNotice(need, have)
        else -> common(status)
    }

    fun cancel(status: ReversiRPCStatus): String = when (status) {
        ReversiRPCStatus.ok -> "신청을 취소했어요"
        ReversiRPCStatus.notFound, ReversiRPCStatus.notPending, ReversiRPCStatus.expired -> finishedInvite
        else -> common(status)
    }

    /** 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(null). */
    fun respond(accept: Boolean, status: ReversiRPCStatus, side: String? = null, need: Long? = null, have: Long? = null): String? =
        when (status) {
            ReversiRPCStatus.ok -> if (accept) null else "신청을 거절했어요"
            ReversiRPCStatus.notFound, ReversiRPCStatus.notPending -> finishedInvite
            ReversiRPCStatus.expired -> "신청 시간이 지났어요"
            ReversiRPCStatus.invalid -> "받을 수 없는 신청이에요"
            ReversiRPCStatus.busy -> busy
            ReversiRPCStatus.targetBusy -> targetBusy
            ReversiRPCStatus.insufficient -> if (side == "challenger") "상대의 루비가 모자라요" else SharedText.shortfallNotice(need, have)
            else -> common(status)
        }

    /** 착수 결과. **성공과 `stale` 은 말하지 않는다**(null) — 실려 온 state 로 화면이 답한다. */
    fun move(status: ReversiRPCStatus, reason: ReversiIllegalReason? = null): String? = when (status) {
        ReversiRPCStatus.ok, ReversiRPCStatus.stale -> null
        ReversiRPCStatus.illegal -> reason?.let(::illegal) ?: outOfRange
        ReversiRPCStatus.autoPlaced -> autoPlaced
        ReversiRPCStatus.notYourTurn -> notYourTurn
        ReversiRPCStatus.notActive, ReversiRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    /** 기권 결과. 성공은 결과 화면이 말한다(null). */
    fun resign(status: ReversiRPCStatus): String? = when (status) {
        ReversiRPCStatus.ok -> null
        ReversiRPCStatus.notActive, ReversiRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    private fun common(status: ReversiRPCStatus): String = when (status) {
        ReversiRPCStatus.unsupportedClient -> updateRequired
        ReversiRPCStatus.unauthorized -> signInAgain
        else -> tryAgain
    }
}
