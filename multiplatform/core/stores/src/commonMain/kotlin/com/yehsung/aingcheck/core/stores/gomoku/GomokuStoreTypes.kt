// 원본: Sources/CheckCore/GomokuStore.swift:22-537(화면 값 타입 · 관전·순위 값 · GomokuWatchRuntime · 주의 · 채팅 · 화면이 본 판 · 문구 표) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuTapRefusal
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.GomokuRPCStatus

// 화면 값 타입(설계서 §6.3 선언 그대로 — 화면 갈래 W4-a 가 이 선언만 믿고 짠다). Swift 는 GomokuStore.swift 한 파일이지만 Kotlin 은
// 타입 몫을 이 파일로 뗐다(스토어 본문 GomokuStore.kt 가 2천 줄을 넘지 않게 — C§2.3 "한 파일 하나"의 예외, 원본 줄 구간을 머리에 적는다).
// GomokuEndReason · GomokuOutcome · GomokuTapRefusal 는 **W1-b rules/renju/GomokuMatchTypes.kt** 것을 쓴다(AI 판 규칙이 쓰므로 rules 에 있다 —
// 같은 이름을 여기 다시 만들면 AI 판과 서버 판이 다른 열거를 든다).
// 숫자 규칙(C§2.5): 금액·와이어 카운터·시각은 Long, 판 좌표·기록 수(≤225)·연속 횟수처럼 범위가 정해진 값은 Int.

/** 판돈(서버 CHECK 가 3·5·10 으로 묶었다). */
enum class GomokuStake(val rawValue: Long) {
    three(3), five(5), ten(10);

    companion object {
        fun fromRawValue(raw: Long?): GomokuStake? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * 사람 한 명(화면 값). [center] 는 소속 센터의 **화면 글자**("서울"/"부산") — 서버 어휘가 아니다. 경계 둘(`peerUser` · `user(from:)`)에서
 * `CenterLabel.display` 를 **한 번만** 지나 들어온다(변환이 두 벌이 되면 한쪽이 언젠가 틀린다). 모르는 값은 null = 배지 없음.
 */
data class GomokuUser(
    /** user uuid 소문자 문자열. */
    val id: String,
    val displayName: String,
    val avatarURL: String?,
    val characterID: String?,
    val isWorking: Boolean,
    /** 상대 앱이 오목을 아는 버전. */
    val isCapable: Boolean,
    val inMatch: Boolean,
    val center: String? = null,
) {
    /** 이 사람이 AI 상대인가(Swift `GomokuUser.isGomokuAI` — GomokuAIGame.swift:303). */
    val isGomokuAI: Boolean get() = id == gomokuAI.id

    companion object {
        /** AI 상대(Swift `GomokuUser.gomokuAI` — GomokuAIGame.swift:297). id 는 uuid 가 아니라 서버 어떤 사람과도 겹치지 않는다. */
        val gomokuAI: GomokuUser = GomokuUser(
            id = "ai", displayName = "AI", avatarURL = null, characterID = null,
            isWorking = true, isCapable = true, inMatch = false,
        )
    }
}

data class GomokuRecord(val wins: Long, val losses: Long, val draws: Long)

data class GomokuInvite(
    /** match id. */
    val id: String,
    /** 받은 신청이면 신청자, 보낸 신청이면 상대. */
    val peer: GomokuUser,
    val stake: Long,
    /** 기기 시계로 보정된 시각. */
    val expiresAt: SwiftDate,
)

/**
 * 대국 한 판의 화면 상태. **[board] 는 값으로 다룬다** — Kotlin `GomokuBoard` 는 가변 참조라 이 값에 넣은 판을 다시 고치지 않는다
 * (고칠 판은 언제나 `copy()` 로 만든다 — W1-b 머리말의 값 의미 규약).
 */
data class GomokuMatchState(
    val id: String,
    val stake: Long,
    val myColor: GomokuColor,
    val opponent: GomokuUser,
    val board: GomokuBoard,
    val lastMove: GomokuPoint?,
    val moveCount: Int,
    /** 끝나면 null. */
    val turn: GomokuColor?,
    /** 차례 마감(기기 시계로 보정), 끝나면 null. */
    val deadline: SwiftDate?,
    val isFinished: Boolean,
    val outcome: GomokuOutcome?,
    val endReason: GomokuEndReason?,
    /** 이 판으로 내 루비가 변한 양(승 +`DuelFee.winnerNet` · 패 −stake · 무 0). */
    val rubyDelta: Long?,
    /** 직전에 흑 자동 패스가 있었다. */
    val blackPassed: Boolean,
    /** 0.3.28 — 시간이 지나 **서버가 대신 놓은** 자리들(뷰가 작은 회색 점으로 구분해 그린다). */
    val autoPoints: Set<GomokuPoint> = emptySet(),
    /** 마지막 수가 자동으로 놓인 것인가(상태줄·툴팁이 "시간이 지나 자동으로 놓인 수"를 말할 근거). */
    val lastMoveWasAuto: Boolean = false,
) {
    /** 자동 착수가 연속 3번 놓여 끝난 판인가. **저장 칸이 아니라 [endReason] 에서 파생된다**(0.3.28 — 사실의 출처는 하나). */
    val endedByAbandon: Boolean get() = endReason == GomokuEndReason.abandoned
}

/**
 * 로비 "지금 대결 중" 한 건. **판 내용을 들고 있지 않다** — 누구와 누가, 얼마를 걸고, 언제 시작했는지뿐이다.
 * a/b 는 서버가 uuid 로 고정한 좌우 순서 그대로다(조회마다 자리가 바뀌면 같은 판이 다른 판으로 보인다).
 */
data class GomokuLiveMatch(
    val id: String,
    val a: GomokuUser,
    val b: GomokuUser,
    val stake: GomokuStake,
    /** 기기 시계로 보정된 시작 시각(서버 `started_ms` = accepted_at). */
    val startedAt: SwiftDate,
    /**
     * 0.3.64 — 이 판을 보고 있는 관전자 수. 서버가 안 싣는 창에서는 0 이고 화면은 0 이면 아무것도 그리지 않는다.
     * INV-GomokuStore-9b73cba5 이식: Swift 는 "기본값이 붙은 `let` 은 멤버와이즈 이니셜라이저에서 빠진다"는 함정을 막으려 `var` 로 뒀다 —
     * Kotlin 생성자 기본값은 그런 함정이 없지만 같은 뜻을 지킨다: `liveMatch(from:)` 이 **언제나** 이 값을 넘긴다(빠지면 모든 카드가 조용히 0).
     */
    val watchers: Long = 0,
)

enum class GomokuPhase { lobby, playing, result }

/**
 * 관전 중인 남의 판 하나. `phase` 는 `lobby` 그대로이고 **이 값이 null 이 아닌 것**이 관전 중이다(`match == null && phase == lobby`).
 *
 * **흑·백을 추측하지 않는다.** 로비 카드의 a/b 는 uuid 순서라 색을 모른다 — 첫 ok 응답 전에는 [faces] 두 얼굴만(색 배지 없이) 그리고,
 * [black]/[white] 는 서버 `black_user`/`white_user` 로만 확정한다. 판 문자열은 서버 `board` 가 권위이고 `moves` 는 마지막 수·자동 착수 점용이다.
 */
data class GomokuSpectateState(
    /** match id 소문자. */
    val id: String,
    /** 로비 카드에서 빌린 두 얼굴(a·b 순서, 색 모름). 씨앗을 못 찾았으면 비어 있다. */
    val faces: List<GomokuUser> = emptyList(),
    /** 판돈. 씨앗이 없으면 null 이고 응답의 `match.stake` 가 채운다. */
    val stake: Long? = null,
    /** 서버가 말한 흑·백. **첫 ok 응답 전에는 null**. */
    val black: GomokuUser? = null,
    val white: GomokuUser? = null,
    val board: GomokuBoard = GomokuBoard(),
    val lastMove: GomokuPoint? = null,
    val moveCount: Int = 0,
    /** 내가 반영한 마지막 수 번호. 다음 요청의 `p_since_seq` 다(구멍이 나면 확장이 0 으로 되돌린다). */
    val appliedSeq: Int = 0,
    /** 끝나면 null. */
    val turn: GomokuColor? = null,
    /** 차례 마감(기기 시계로 보정). 끝나면 null. 마감이 지나도 **"졌다"가 아니다**. */
    val deadline: SwiftDate? = null,
    val startedAt: SwiftDate? = null,
    /** 시간이 지나 서버가 대신 놓은 자리들(회색 점). */
    val autoPoints: Set<GomokuPoint> = emptySet(),
    val lastMoveWasAuto: Boolean = false,
    val isFinished: Boolean = false,
    /** 이긴 색. 끝났는데 null 이면 무승부다. */
    val winner: GomokuColor? = null,
    val endReason: GomokuEndReason? = null,
    val blackAutoStreak: Int = 0,
    val whiteAutoStreak: Int = 0,
) {
    /** 서버 응답을 한 번이라도 반영했는가(= 흑·백이 확정됐는가). 그 전에는 로딩 화면이다. */
    val hasServerState: Boolean get() = black != null && white != null
}

/** 순위표 한 줄(화면 값). [user] 는 `GomokuStore.user(from:)` 로 만든다 — CenterLabel 변환점을 늘리지 않는다. */
data class GomokuRankEntry(
    val id: String,
    /** 서버가 매긴 순위(동률은 같은 숫자, 다음은 건너뛴다 — rank()). */
    val rank: Long,
    val user: GomokuUser,
    val wins: Long,
    val losses: Long,
    val draws: Long,
    /** 승점 = 승 − 패. 서버 값 그대로. */
    val points: Long,
)

/** 내 순위 한 줄. [rank] 는 0판이면 null(순위 밖) — 전적은 그래도 있다. */
data class GomokuMyRank(val rank: Long?, val wins: Long, val losses: Long, val draws: Long, val points: Long)

/** 순위표 전체. **[entries] 는 서버 순서 그대로**(재정렬 금지). [recordSince] 가 없으면 화면은 "M월 d일부터" 캡션을 안 단다. */
data class GomokuRankingBoard(val entries: List<GomokuRankEntry>, val me: GomokuMyRank?, val recordSince: SwiftDate?)

/**
 * 관전·순위 갈래의 관찰 대상이 아닌 장부. [watchGeneration] 은 **관전 세대**다: `startWatching`(판 전환)·`stopWatching`·`reset`·
 * 내 판이 열려 관전이 내려갈 때 오른다. 세대가 다른 응답은 버린다 — `resetGeneration` 만 보면 창을 닫은 뒤 늦게 온 응답이 관전을 되살리고,
 * A 판을 나가 B 판을 보는 사이 A 의 늦은 응답이 B 판을 한 틱 덮는다.
 */
class GomokuWatchRuntime {
    var lastWatchRequestAt: SwiftDate = distantPast
    var watchInFlight: Boolean = false
    /** 조회 중에 또 조회할 이유가 생겼다 — 끝나면 한 번 더 돈다. */
    var watchAgain: Boolean = false
    /** 다음 조회 한 번을 `p_since_seq = 0` 으로 띄운다(수 번호에 구멍). 내리는 것은 그 전체를 실어 온 응답이다. */
    var watchWantsFull: Boolean = false
    /** 관전 세대. 올리는 문은 [bumpWatchGeneration] 하나다. */
    var watchGeneration: Int = 0
        private set
    /** 연속 실패 횟수(throw 경로 — 5xx·오프라인). 문턱을 넘으면 관전을 내리고 안내 한 줄을 남긴다. */
    var watchFailureStreak: Int = 0
    var lastRankingRequestAt: SwiftDate = distantPast
    var rankingInFlight: Boolean = false

    fun bumpWatchGeneration(): Int {
        watchGeneration += 1
        return watchGeneration
    }

    /** 전부 초기값으로 + 세대 한 번 올림(로그아웃·계정 전환). 이름이 `reset` 이 아닌 이유는 Swift 소스 계약 시험 때문이다(원문 그대로 둔다). */
    fun clear() {
        lastWatchRequestAt = distantPast
        watchInFlight = false
        watchAgain = false
        watchWantsFull = false
        watchFailureStreak = 0
        lastRankingRequestAt = distantPast
        rankingInFlight = false
        bumpWatchGeneration()
    }
}

/** 창이 안 보이는 사람에게 "지금 둘 차례"를 알리는 한 건(같은 (판 id, move_count) 에는 한 번만 만든다). */
data class GomokuAttention(
    val kind: Kind,
    val matchID: String,
    val opponentName: String,
    /** 이 알림을 만든 순간의 기록 수. 말풍선을 띄우기 직전 판이 이미 넘어갔는지 대조한다. */
    val moveCount: Int,
) {
    enum class Kind {
        /** 판이 막 시작됐고 내가 먼저 둔다(흑). */
        matchStarted,
        /** 상대가 뒀고 이제 내 차례다. */
        myTurn,
    }
}

/**
 * 빠른 문구 여덟. **코드는 서버와 나누고 한국어 문구는 앱만 갖는다** — 서버가 코드를 넓히는 날 옛 앱이 모르는 코드는 받는 쪽에서
 * [GomokuNoticeText.chatUnknownQuick] 한 줄로 접는다(소실은 오배달보다 나쁘다).
 */
enum class GomokuQuickPhrase(val rawValue: String) {
    hi("hi"), gg("gg"), nice("nice"), hurry("hurry"), sorry("sorry"), think("think"), oops("oops"), rematch("rematch");

    val text: String
        get() = when (this) {
            hi -> "안녕하세요"
            gg -> "잘 뒀어요"
            nice -> "좋은 수네요"
            hurry -> "한 수 부탁해요"
            sorry -> "미안해요"
            think -> "생각 중이에요"
            oops -> "실수했어요"
            rematch -> "한 판 더 할까요?"
        }

    companion object {
        fun fromRawValue(raw: String?): GomokuQuickPhrase? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 대국 채팅 한 줄(화면 값). [seq] 가 곧 id 다 — 서버가 판마다 1부터 매기는 번호. */
data class GomokuChatMessage(
    val seq: Long,
    /** 서버가 판정한다(앱이 sender 를 내 id 와 대조하지 않는다). */
    val isMine: Boolean,
    /** 기기 시계로 보정된 시각. */
    val sentAt: SwiftDate,
    /** 빠른 문구면 그 코드, 자유 입력이면 null. */
    val quick: GomokuQuickPhrase?,
    /** 화면에 그대로 그리는 글(빠른 문구면 `quick.text`). */
    val body: String,
) {
    val id: Long get() = seq
}

/**
 * 판을 누른 **그 순간 화면이 그리고 있던** 판의 요약(v0.3.31 진단). 착수 판정은 언제나 스토어 값으로 하고, 이 값은 **로그에만** 쓴다.
 */
data class GomokuSeenTurn(val matchID: String, val moveCount: Int, val turn: GomokuColor?) {
    constructor(match: GomokuMatchState) : this(match.id, match.moveCount, match.turn)

    /** 스토어 판과 다른가. 스토어에 판이 없으면 다르다. */
    fun differs(match: GomokuMatchState?): Boolean {
        if (match == null) return true
        return matchID != match.id || moveCount != match.moveCount || turn != match.turn
    }
}

/**
 * 오목 안내 한 줄의 **유일한 출처**. status → 문구 변환이 여러 곳에 흩어지면 같은 거절이 화면마다 다른 말을 한다.
 * 진단 어휘(서버·상태·동기화·토큰 등)는 쓰지 않는다 — 사용자가 할 수 있는 일을 말한다.
 */
object GomokuNoticeText {
    const val tryAgain: String = "잠시 후 다시 시도해 주세요"
    const val checkConnection: String = "연결을 확인하고 다시 시도해 주세요"
    const val updateMine: String = "앱을 업데이트해야 대결할 수 있어요"
    const val signInAgain: String = "다시 로그인해 주세요"
    const val notYourTurn: String = "상대 차례예요"
    const val inviteTimedOut: String = "상대가 응답하지 않았어요"
    /** 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대국을 시작함 — 사용자에게는 모두 같은 뜻이다). */
    const val inviteDeclined: String = "상대가 신청을 받지 않았어요"
    /** 착수·기권을 눌렀는데 그 전에 시간이 넘어 판이 이미 끝났다. */
    const val timedOut: String = "시간이 지나 대국이 끝났어요"
    const val finishedInvite: String = "이미 끝난 신청이에요"
    const val finishedMatch: String = "이미 끝난 대국이에요"
    const val cannotPlace: String = "둘 수 없는 자리예요"
    /** 앞 착수·기권이 아직 왕복 중이라 잠긴 동안 또 눌렀다. **지금 무슨 일이 일어나는지**를 말한다. */
    const val sending: String = "보내는 중이에요"
    /** 이미 돌이 있는 교차점을 눌렀다. */
    const val occupied: String = "이미 돌이 놓인 자리예요"
    const val busy: String = "이미 진행 중인 대국이 있어요"
    const val targetBusy: String = "상대가 다른 대국 중이에요"

    // 채팅(v0.3.28). 아래 셋은 안내가 아니라 **상태 표시**다 — 그 조건이 참인 동안 서 있다.
    const val chatMutedByMe: String = "상대 말을 껐어요"
    const val chatMutedByOpponent: String = "상대가 채팅을 껐어요"
    const val chatOpponentOutdated: String = "상대는 옛 버전이라 채팅을 못 받아요"
    /** 앱이 모르는 빠른 문구 코드(서버가 표를 넓힌 날). 그 줄을 지우는 대신 이렇게 남긴다. */
    const val chatUnknownQuick: String = "앱을 업데이트하면 볼 수 있는 문구예요"
    /** 보낼 수 없는 글과 도배를 **한 문장으로** 접는다. 숫자도 카운트다운도 두지 않는다. */
    const val chatBlocked: String = "지금은 채팅을 보낼 수 없어요. 잠시 후 다시 시도해 주세요"

    /** 길이 초과. 숫자는 **서버가 알려 준 상한이 있으면 그것**을 쓴다. */
    fun chatTooLong(maxLength: Long): String = "채팅은 ${maxLength}자까지예요"

    // 자동 착수(v0.3.28). 시간이 지나면 **지는 게 아니라 서버가 대신 놓는다**.
    const val autoPlaced: String = "시간이 지나 자동으로 놓였어요"
    const val autoPlacedStone: String = "시간이 지나 자동으로 놓인 수"

    // 관전(0.3.41).
    /** gomoku_watch 가 not_found — 판이 끝난 지 오래됐거나 볼 수 없는 판이다. */
    const val watchGone: String = "지금은 볼 수 없는 판이에요"
    /** 서버에 아직 관전·순위가 없다(PGRST202). */
    const val watchUnavailable: String = "관전은 곧 열려요"

    /**
     * 자동 착수 연속 경고. **한 번 남았을 때만** 말한다. [lossStreak] 기본값은 **폴백 상수**다 — 서버가 말한 임계값을 따르려면 스토어의
     * `autoStreakWarning`(인자 없는 계산 프로퍼티)을 읽어라.
     */
    fun autoStreakWarning(streak: Int, lossStreak: Int = GomokuStore.autoPlaceLossStreak): String? {
        if (streak != lossStreak - 1) return null
        return "한 번 더 놓치면 집니다"
    }

    /** 자리 비움으로 끝난 판의 결과 한 줄. 이긴 쪽과 진 쪽이 다른 문장을 본다. */
    fun abandoned(outcome: GomokuOutcome?): String = if (outcome == GomokuOutcome.won) "상대가 자리를 비웠어요" else "자리를 비워 졌어요"

    /** 금수 사유별 문구. 상태줄과 호버 이유가 같은 말을 한다. */
    fun forbidden(reason: GomokuForbiddenReason): String = when (reason) {
        GomokuForbiddenReason.doubleThree -> "3-3 금수라 둘 수 없어요"
        GomokuForbiddenReason.doubleFour -> "4-4 금수라 둘 수 없어요"
        GomokuForbiddenReason.overline -> "장목 금수라 둘 수 없어요"
        GomokuForbiddenReason.budget -> "판정할 수 없는 자리예요"
    }

    /** 탭 거절 한 줄. `null` 이면 **말할 것이 없다** — `noMatch` 는 판이 없다는 뜻이라 볼 화면도 없다. */
    fun tapRefusal(refusal: GomokuTapRefusal, reason: GomokuForbiddenReason? = null): String? = when (refusal) {
        GomokuTapRefusal.notYourTurn -> notYourTurn
        GomokuTapRefusal.busy -> sending
        GomokuTapRefusal.occupied -> occupied
        GomokuTapRefusal.finished -> finishedMatch
        GomokuTapRefusal.signedOut -> signInAgain
        GomokuTapRefusal.noMatch -> null
        GomokuTapRefusal.forbidden -> reason?.let(::forbidden) ?: cannotPlace
    }

    /**
     * 신청(gomoku_challenge) 결과. v0.3.30 부터 서버는 `not_working`·`target_not_working` 을 내지 않는다 — 두 문구는 배포 중간 창의 옛 서버가
     * 그 status 를 줄 때만 쓰인다(클라가 먼저 근무를 보고 막는 선게이트로 되살리지 마라).
     */
    fun challenge(status: GomokuRPCStatus, need: Long? = null, have: Long? = null): String = when (status) {
        GomokuRPCStatus.ok -> "신청을 보냈어요"
        GomokuRPCStatus.invalid -> "신청할 수 없는 상대예요"
        GomokuRPCStatus.blackout -> "지금은 조용한 기간이라 신청할 수 없어요"
        GomokuRPCStatus.notWorking -> "근무 중일 때만 신청할 수 있어요"
        GomokuRPCStatus.targetNotWorking -> "상대가 근무 중이 아니에요"
        GomokuRPCStatus.targetFocused -> "상대가 집중 모드라 신청할 수 없어요"
        GomokuRPCStatus.targetOutdated -> "상대가 앱을 업데이트해야 해요"
        GomokuRPCStatus.busy -> busy
        GomokuRPCStatus.targetBusy -> targetBusy
        GomokuRPCStatus.alreadyPending -> "이미 보낸 신청이 있어요"
        GomokuRPCStatus.insufficient -> SharedText.shortfallNotice(need, have)
        else -> common(status)
    }

    /** 신청 취소(gomoku_cancel) 결과. */
    fun cancel(status: GomokuRPCStatus): String = when (status) {
        GomokuRPCStatus.ok -> "신청을 취소했어요"
        GomokuRPCStatus.notFound, GomokuRPCStatus.notPending, GomokuRPCStatus.expired -> finishedInvite
        else -> common(status)
    }

    /** 수락·거절(gomoku_respond) 결과. 수락 성공은 판이 곧바로 열리므로 말하지 않는다(null). */
    fun respond(accept: Boolean, status: GomokuRPCStatus, side: String? = null, need: Long? = null, have: Long? = null): String? =
        when (status) {
            GomokuRPCStatus.ok -> if (accept) null else "신청을 거절했어요"
            GomokuRPCStatus.notFound, GomokuRPCStatus.notPending -> finishedInvite
            GomokuRPCStatus.expired -> "신청 시간이 지났어요"
            GomokuRPCStatus.notWorking -> "근무 중일 때만 수락할 수 있어요"
            GomokuRPCStatus.targetNotWorking -> "상대가 근무를 끝냈어요"
            GomokuRPCStatus.busy -> busy
            GomokuRPCStatus.targetBusy -> targetBusy
            GomokuRPCStatus.insufficient -> if (side == "challenger") "상대의 루비가 모자라요" else SharedText.shortfallNotice(need, have)
            else -> common(status)
        }

    /** 착수(gomoku_move) 결과. 성공·판이 바뀐 경우(stale — 곧바로 다시 불러온다)는 말하지 않는다(null). */
    fun move(status: GomokuRPCStatus, reason: String? = null): String? = when (status) {
        GomokuRPCStatus.ok, GomokuRPCStatus.stale -> null
        // 내 차례가 지나 서버가 대신 놓았다. 판은 함께 온 state 가 말하고, 이 줄은 **왜** 그렇게 됐는지를 말한다.
        GomokuRPCStatus.autoPlaced -> autoPlaced
        GomokuRPCStatus.forbidden -> GomokuForbiddenReason.fromServerReason(reason)?.let(::forbidden) ?: cannotPlace
        GomokuRPCStatus.timeout -> timedOut
        GomokuRPCStatus.notYourTurn -> notYourTurn
        GomokuRPCStatus.notActive, GomokuRPCStatus.notFound -> finishedMatch
        GomokuRPCStatus.invalid -> cannotPlace
        else -> common(status)
    }

    /** 기권(gomoku_resign) 결과. 성공은 결과 화면이 말한다(null). 서버는 기권보다 시간 초과를 먼저 정산한다. */
    fun resign(status: GomokuRPCStatus): String? = when (status) {
        GomokuRPCStatus.ok -> null
        GomokuRPCStatus.timeout -> timedOut
        GomokuRPCStatus.notActive, GomokuRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    /** 채팅 전송 결과. **성공은 말하지 않는다**. `flood` 를 `invalid` 와 같은 줄로 접는 것이 계약이다(이름만 다른 쿨타임 금지). */
    fun chat(status: GomokuRPCStatus): String? = when (status) {
        GomokuRPCStatus.ok -> null
        GomokuRPCStatus.invalid, GomokuRPCStatus.flood -> chatBlocked
        GomokuRPCStatus.notActive, GomokuRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    /** 음소거 전환 결과. 성공은 토글과 대화 자리의 한 줄이 이미 말한다(null). */
    fun chatMute(status: GomokuRPCStatus): String? = when (status) {
        GomokuRPCStatus.ok -> null
        GomokuRPCStatus.notFound, GomokuRPCStatus.notActive -> finishedMatch
        else -> common(status)
    }

    private fun common(status: GomokuRPCStatus): String = when (status) {
        GomokuRPCStatus.unsupportedClient -> updateMine
        GomokuRPCStatus.unauthorized -> signInAgain
        else -> tryAgain
    }
}
