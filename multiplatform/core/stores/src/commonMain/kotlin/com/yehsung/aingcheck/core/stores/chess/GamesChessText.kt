// 원본: Sources/CheckMobileKit/Games/GamesChessText.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.chess.ChessClock
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessPieceKind
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.stores.gomoku.roundHalfAwayFromZero
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.ceil
import kotlin.math.floor

// 1:1 체스 **폰 화면 문구**. 오목 짝은 W2-e 의 `GomokuPhoneText` 이고 이 파일은 그 규약을 그대로 따른다.
//  · **맥과 같은 뜻이면 같은 문장이다**(출처는 맥 `ChessText`). 폰에서 처음 쓴 줄만 `// 폰` 으로 적는다.
//  · 거절·실패 한 줄은 **코어 `ChessNoticeText` 를 그대로 부른다**(status → 문구 변환을 두 벌로 만들지 않는다).
//  · 진단 어휘는 쓰지 않는다 — 사용자가 **할 수 있는 일**을 말한다.
// ── 돈이 갈리는 자리 넷 ── ① FIDE 6.9(깃발인데 메이트할 기물이 없으면 무승부) ② 신청만 한 상태에서는 0원도 안 움직인다(빠지는 순간은 수락)
// ③ 한 사람 한 판(양방향) ④ 로봇 판은 로그인을 안 본다.
//
// 빌린 글자 둘: `MobileLoadText.retry`(폰 공용 부품 — 아직 Kotlin 자리 없음)와 `GomokuPhoneText.stakeCaption`(W2-e 몫)은 같은 글자를
// 여기 둔다 — 병합 뒤 조정자가 그 표로 접는다(GamesChessTextTest 가 손으로 적은 글자로 못 박는다).

/** 1:1 체스 폰 화면 문구. 맥 `ChessText` 와 같은 자리. */
object ChessPhoneText {

    // MARK: 머리

    const val title: String = "1:1 체스"
    const val rulesButton: String = "규칙"
    const val rulesTitle: String = "체스 규칙"
    const val close: String = "닫기"

    private val defaultIncrementMs: Long = (ChessClock.incrementSeconds * 1000).toLong()

    /** 머리글 캡션. 시간 수치는 **서버가 말한 값**에서 만든다(2026-10-12 에 5분 → **10분**이 됐다 — 그 사고를 피하는 자리). */
    fun subtitle(initialMs: Long = ChessClock.initialMs.toLong(), incrementMs: Long = defaultIncrementMs): String =
        "FIDE 규칙 · 백 선공 · ${clockPhrase(initialMs, incrementMs)}"

    /** "10분 + 한 수 3초" — 시계 한 조각(규칙 시트와 머리글이 같이 쓴다). */
    fun clockPhrase(initialMs: Long = ChessClock.initialMs.toLong(), incrementMs: Long = defaultIncrementMs): String {
        val minutes = maxOf(1L, initialMs / 60_000)
        val increment = maxOf(0L, incrementMs / 1_000)
        return "${minutes}분 + 한 수 ${increment}초"
    }

    /** 서버가 신청 만료를 안 말해 줬을 때의 값(초). 로비 응답의 `invite_ttl_seconds` 가 오면 **그 값을 써라**(폴백이다). */
    const val inviteTtlSecondsFallback: Int = 60

    // MARK: 로비

    const val lobbyTitle: String = "상대 고르기"
    const val lobbyCaption: String = "근무 중이 아니어도 신청하고 받을 수 있어요"
    const val emptyUsers: String = "지금 대결할 수 있는 사람이 없어요"
    const val loadingUsers: String = "상대 목록을 불러오고 있어요"
    /** 폰: 절마다 "무엇을 못 불러왔나" + 공용 [다시 시도]로 말한다(`MobileLoadText` 규칙). */
    const val usersLoadFailed: String = "상대 목록을 불러오지 못했어요"
    /** Swift `MobileLoadText.retry` 와 같은 글자(파일 머리말 — 병합 뒤 접는다). */
    const val reloadUsers: String = "다시 시도"
    const val challenge: String = "도전"
    const val needsUpdate: String = "앱 업데이트가 필요해요"
    const val inMatchButton: String = "대국 중"
    const val working: String = "근무 중"
    const val notWorking: String = "근무 안 함"

    const val recordTitle: String = "전적"
    const val myRubyTitle: String = "내 루비"
    fun peopleCount(count: Int): String = "${count}명"
    fun liveCount(count: Int): String = "${count}판"

    /**
     * 게임 탭 **카드** 부제. INV-GamesChessText-13d20812 이식: 시간 수치를 싣지 않는다 — 카드는 로비를 아직 안 읽었을 수 있고 10-12 에
     * 5분 → 10분으로 늘어난 값이라 박아 두면 그 자리가 곧 거짓이 된다.
     */
    const val cardSubtitle: String = "FIDE 규칙 · 백 선공 · 로봇과도 둬요"
    /** 카드 칩 — 받은 신청. 체스 서버는 받은 신청을 **한 번에 하나만** 말해 준다라 수를 세지 않는다. */
    const val incomingChip: String = "받은 신청 1건"
    const val outgoingLine: String = "보낸 신청을 기다리고 있어요"
    const val idleLine: String = "상대를 골라 대결을 신청해요"

    /**
     * 상대 행 상태 칩. 우선순위: 대국 중 > 업데이트 필요 > 근무 중/근무 안 함.
     * INV-GamesChessText-4886e6ea 이식: `inMatch` 는 **어느 게임인지 말하지 않는다**(서버가 오목 판까지 보고 하나로 접어 준다) — 그래서
     * "오목 중"이라고 적지 않는다(지어내면 체스 판을 두는 사람이 오목 중으로 보인다).
     */
    fun status(user: ChessUser): String = when {
        user.inMatch -> inMatchButton
        !user.isCapable -> needsUpdate
        user.isWorking -> working
        else -> notWorking
    }

    /** 비활성 [도전] 버튼의 글자 — **짧게** 말한다. */
    const val needsUpdateButton: String = "업데이트 필요"

    /** 상대 한 줄이 쓰는 **두 자리** — 이름 아래 회색 부제와 오른쪽 버튼 글자. */
    data class OpponentRow(val subtitle: String, val buttonTitle: String)

    /**
     * 상대 한 줄의 두 자리를 **한 함수**가 고른다.
     * INV-GamesChessText-42afd1fd 이식: 둘을 같이 낸다 — 자리마다 따로 고르면 **같은 문장이 한 줄에 두 번** 나온다(헤드리스 실측).
     * INV-GamesChessText-a83e830d 이식: 옛 서열(`inMatch > capable > 근무`)이 **근무 축을 덮었다** — 그래서 축을 **자리로 가른다**(부제는 늘
     * 근무 축, 버튼은 막힌 까닭).
     * INV-GamesChessText-a996dd13 이식: 둘이 겹치는 갈래(대국 중 + 옛 버전)에서는 버튼이 못 말한 축을 부제 꼬리로 보낸다.
     */
    fun opponentRow(user: ChessUser): OpponentRow {
        val work = if (user.isWorking) working else notWorking
        // 옛 버전이 먼저다: 상대가 앱을 올릴 때까지 신청이 서버에서 거절되는, 가장 오래 가는 막힘이다.
        if (!user.isCapable) return OpponentRow(if (user.inMatch) "$work · $inMatchButton" else work, needsUpdateButton)
        if (user.inMatch) return OpponentRow(work, inMatchButton)
        return OpponentRow(work, challenge)
    }

    /** 상대 행 부제. 대국 중이면 누구와 두는지(로비의 대결 중 목록에서 찾는다). */
    fun opponentStatus(user: ChessUser, liveMatches: List<ChessLiveMatch>): String {
        if (user.inMatch) {
            val partner = liveMatches.firstOrNull { it.a.id == user.id || it.b.id == user.id }
                ?.let { if (it.a.id == user.id) it.b.displayName else it.a.displayName }
            return partner?.let { "대국 중 · $it${withParticle(it)}" } ?: inMatchButton
        }
        if (!user.isCapable) return needsUpdate
        return if (user.isWorking) working else notWorking
    }

    // MARK: 한 사람 한 판 — 양방향
    // INV-GamesChessText-4d0378ed 이식: 한 사람 한 판 — **양방향**(인수인계 §6-7). 체스 중인 사람은 오목·테트리스를 신청·수락하지 못하고
    // 그 반대도 같다. 폰은 탭 하나에 입구를 같이 띄우므로 막힌 상태를 모든 입구가 말해야 한다.

    /**
     * 내가 지금 두고 있는 게임. **양방향으로 쓴다**.
     * INV-GamesChessText-fb2c0f87 이식: **1.0.11 부터 셋이다**(테트리스). "반대쪽 게임"(이진 뒤집기)은 지웠다 — 셋에서는 반대쪽이 하나로
     * 정해지지 않아 틀린 안내를 했다. 그래서 문구 함수가 **두는 판(playing)과 막힌 입구(blocked)를 둘 다** 받는다.
     */
    enum class BusyGame(val rawValue: String) {
        gomoku("gomoku"), chess("chess"), tetris("tetris");

        /** 게임 이름("오목" · "체스" · "1:1 테트리스"). */
        val gameName: String
            get() = when (this) {
                gomoku -> "오목"
                chess -> "체스"
                tetris -> "1:1 테트리스"
            }

        /** 진행 중인 판을 가리키는 말. 셋 다 받침으로 끝나므로 뒤에 "이" 를 붙인다. */
        val matchNoun: String
            get() = when (this) {
                gomoku -> "오목 판"
                chess -> "체스 판"
                tetris -> "테트리스 대결"
            }
    }

    /** 다른 판을 두는 중이라 입구가 막혔다(테트리스는 '둔다'고 하지 않는다). */
    fun busyTitle(playing: BusyGame): String = when (playing) {
        BusyGame.gomoku, BusyGame.chess -> "${playing.gameName}${objectParticle(playing.gameName)} 두는 중이에요"
        BusyGame.tetris -> "${playing.gameName} 대결 중이에요"
    }

    /**
     * 그 아래 한 줄 — 언제 풀리는지 말한다.
     * INV-GamesChessText-174d4b8d 이식: [blocked] 가 **막힌 입구**다(지어내지 않는다) — 게임이 셋이 된 뒤로는 두는 판만 알고는 이 문장을 쓸 수
     * 없다(오목을 두는 중에 막히는 입구가 체스·테트리스 **둘**이고 각 카드는 자기 이름을 말해야 한다).
     */
    fun busyHint(playing: BusyGame, blocked: BusyGame): String {
        val name = blocked.gameName
        return "${playing.matchNoun}이 끝나면 $name${objectParticle(name)} 신청할 수 있어요"
    }

    /**
     * 1:1 입구(도전·수락)를 막는 사유 한 줄. 두는 판이 없으면 null.
     * INV-GamesChessText-d7f81945 이식: **양방향**이다 — 화면은 이 함수 하나만 묻고 스스로 판단을 만들지 않는다(클라 게이트는 짝으로 있다).
     */
    fun entryBlock(playing: BusyGame?): String? = playing?.let(::busyTitle)

    /** 막힌 입구의 **둘째 줄**(언제 풀리는지). [entryBlock] 과 **짝으로** 쓴다(폰엔 호버 툴팁이 없다). */
    fun entryBlockHint(playing: BusyGame?, blocked: BusyGame): String? = playing?.let { busyHint(it, blocked) }

    /**
     * 막힌 입구에 세우는 안내 **한 칸 두 줄**(제목 + 언제 풀리는지).
     * INV-GamesChessText-d4652dde 이식: 표가 줄바꿈까지 쥔다 — 화면에서 조립하면 그 조립이 시험이 못 보는 자리에 남아 한 화면만 둘째 줄을
     * 빠뜨려도 아무도 모른다(통합에서 실제로 그렇게 줄었다).
     * INV-GamesChessText-cb9206f9 이식: **양방향이 같은 꼴이다** — `.gomoku`·`.chess` 가 같은 두 줄을 낸다.
     */
    fun entryBlockNotice(playing: BusyGame?, blocked: BusyGame): String? {
        if (playing == null) return null
        return busyTitle(playing) + "\n" + busyHint(playing, blocked)
    }

    /** 게임 탭 체스 카드의 보이스오버 힌트(막히지 않았을 때). */
    const val cardOpenHint: String = "체스 대결 화면을 열어요"

    /**
     * 로봇 판을 두는 중이라 **신청**이 막혔다(받은 신청은 막지 않고 묻는다).
     * INV-GamesChessText-6e13dbb8 이식: 서버는 이 판을 볼 수 없다(로봇 판은 서버에 행이 없다) — 이 줄은 **클라만 할 수 있는 말**이고,
     * 없으면 비활성 알약만 남아 "왜 안 눌리지"가 된다.
     */
    const val blockedByRobot: String = "로봇 판을 끝내면 1:1 대결을 신청할 수 있어요"

    // INV-GamesChessText-6fd8c0c9 이식: 로봇 판 중 받은 신청은 막지 않고 **묻는다** — 막으면 60초 TTL 안에 루비가 걸린 진짜 대결을 놓치고,
    // 안 물으면 1:1 판이 서는 순간 코어가 로봇 판을 버려 두던 판이 확인도 없이 사라진다. 첫 줄이 "사라진다"를, 둘째 줄이 "잃는 루비는 없다"를 말한다.
    const val acceptEndsRobotTitle: String = "로봇 판을 끝내고 수락할까요?"
    const val acceptEndsRobotMessage: String = "두던 로봇 판은 저장되지 않아요. 순위·루비와 상관없는 판이라 잃는 루비는 없어요."
    const val acceptEndsRobotConfirm: String = "끝내고 수락"
    const val acceptEndsRobotCancel: String = "그냥 두기"

    /**
     * 로봇과 두기 입구를 막는 사유 한 줄.
     * INV-GamesChessText-6c18bfab 이식: **로그인은 사유가 아니다** — `ChessStoreAI` 는 서버를 한 번도 안 타므로 비로그인 사용자도 둔다. 그래서
     * 이 함수는 [signedIn] **값을 보지 않는다**(받기만 한다 — 부르는 자리가 로그인으로 가르려 할 때 여기로 오게 하려고).
     */
    @Suppress("UNUSED_PARAMETER")
    fun robotEntryBlock(signedIn: Boolean, playing: BusyGame?): String? = playing?.let(::busyTitle)

    /**
     * 로봇 입구가 막힌 **까닭**. 코어 게이트(`canStartAIMatch`)의 조건을 사용자가 **할 수 있는 일**로 묶는다.
     * INV-GamesChessText-02c200e0 이식: 게이트 깃발 하나로 문구를 고르면 **보낸 신청만 있는 사람**에게 "체스를 두는 중이에요"라고 말한다 —
     * 게이트는 **그대로 두고** 가르는 것은 **문구뿐**이다.
     */
    enum class RobotBlock(val rawValue: String) {
        /** 판이 떠 있다(1:1 이든 로봇이든). 끝나야 풀린다. */
        playing("playing"),
        /** 보낸 신청이 답을 기다린다 — **판은 없다**. 취소하면 바로 풀린다. */
        outgoingInvite("outgoingInvite"),
        /** 요청이 오가는 중(한 틱). 곧 풀린다. */
        busy("busy"),
    }

    /** 막힌 사유 한 줄(머리). */
    fun robotEntryBlock(reason: RobotBlock): String = when (reason) {
        RobotBlock.playing -> busyTitle(BusyGame.chess)
        RobotBlock.outgoingInvite -> "신청에 답을 기다리는 중이에요"
        RobotBlock.busy -> "요청을 보내는 중이에요"
    }

    /** 그 **둘째 줄** — 언제·어떻게 풀리는지. */
    fun robotEntryBlockHint(reason: RobotBlock): String = when (reason) {
        RobotBlock.playing -> "두던 판이 끝나면 로봇과 둘 수 있어요"
        RobotBlock.outgoingInvite -> "보낸 신청을 취소하면 로봇과 둘 수 있어요"
        RobotBlock.busy -> "잠시 뒤에 다시 눌러 보세요"
    }

    /** 입구에 세우는 **한 칸 두 줄**. */
    fun robotEntryBlockNotice(reason: RobotBlock): String = robotEntryBlock(reason) + "\n" + robotEntryBlockHint(reason)

    // MARK: 판돈
    // INV-GamesChessText-d08cc645 이식: 판돈 — **빠지는 순간은 수락이다**(신청은 0원도 움직이지 않는다).

    const val stakeTitle: String = "판돈"
    /** 고를 수 있는 판돈 셋(3 · 5 · 10). 집합의 주인은 서버다. */
    val stakes: List<Long> = ChessStake.entries.map { it.rawValue }
    /** "5 · 이기면 +5" — 꼬리 숫자는 **순이익**(`DuelFee.winnerNet`, v0.3.64 부터 수수료 0). */
    fun stakeLine(stake: Long): String = "$stake · 이기면 +${net(stake)}"
    fun stakeGainSuffix(stake: Long): String = " · 이기면 +${net(stake)}"
    /** "이기면 +5" — 판돈 칸 아래 줄(앞 가운뎃점이 없다). */
    fun stakeGain(stake: Long): String = "이기면 +${net(stake)}"
    fun stakePromptTitle(name: String): String = "${name}님에게 신청"
    const val stakePromptCaption: String = "판돈을 고르세요"
    fun stakePromptChosen(stake: Long): String = "판돈 ${stakeLine(stake)}"
    fun challengeWithStake(stake: Long): String = "$stake 걸고 도전하기"
    /** 루비가 모자라 못 고르는 판돈의 이유 한 줄. 정본은 앱의 다른 화면과 **같은 말**이다. */
    val stakeShortfall: String = SharedText.shortfallNotice(null, null)
    /** 판돈이 **언제** 빠지는지 — 오목과 같은 문장(`GomokuPhoneText.stakeCaption` 과 같은 글자 — 파일 머리말). */
    const val stakeCaption: String = "수락하는 순간 두 사람 모두 걸고, 이기면 판돈만큼 더 받아요"

    /**
     * INV-GamesChessText-4be05f79 이식: 신청만 한 상태를 말하는 줄. "신청하면 빠져요"로 적으면 **거짓**이다 — 신청은 0원도 움직이지 않고,
     * 응답이 없으면 그대로 사라진다. 이 문장과 그 시험이 그 거짓말이 돌아오는 길을 막는다.
     */
    fun stakeNotHeldYet(ttlSeconds: Int = inviteTtlSecondsFallback): String =
        "신청만 해서는 루비가 빠지지 않아요 · ${ttlSeconds}초 안에 응답이 없으면 신청이 사라져요"

    /** 무승부로 끝난 판의 루비. **`timeout_insufficient` 도 무승부다**(FIDE 6.9). */
    const val stakeRefundOnDraw: String = "건 루비는 돌려받아요"

    private fun net(stake: Long): Long = DuelFee.winnerNet(stake.toInt()).toLong()

    // MARK: 신청

    const val incomingTitle: String = "받은 신청"
    const val outgoingTitle: String = "보낸 신청"
    const val noIncoming: String = "받은 신청이 없어요"
    const val loadingIncoming: String = "받은 신청을 불러오고 있어요"
    /** 폰: 받은 신청을 불러오지 못했다(빈 목록을 "없어요"로 말하지 않는다). */
    const val incomingLoadFailed: String = "받은 신청을 불러오지 못했어요"
    const val accept: String = "수락"
    const val decline: String = "거절"
    const val cancel: String = "취소"
    fun incomingTitle(name: String): String = "${name}님의 신청"
    fun outgoingTitle(name: String): String = "${name}님에게 신청했어요"

    /**
     * 받은 신청 절 머리의 오른쪽 한 줄. INV-GamesChessText-8f911127 이식: **초를 박지 않는다** — 서버가 `invite_ttl_seconds` 로 말하고 로비가
     * 그 값을 넘긴다(상수를 베끼면 서버가 TTL 을 바꾼 날 화면만 옛 숫자다).
     */
    fun inviteTtlHint(ttlSeconds: Int = inviteTtlSecondsFallback): String = "${ttlSeconds}초 안에 응답하세요"

    /** 남은 초("42초") — Swift `Int(max(0, s).rounded(.up))`. */
    fun remaining(seconds: Double): String = "${ceil(maxOf(0.0, seconds)).toLong()}초"
    /** "42초 남음". */
    fun remainingPhrase(seconds: Double): String = "${remaining(seconds)} 남음"

    // MARK: 대국

    const val myTurn: String = "내 차례예요"
    const val opponentTurn: String = "상대 차례예요"
    const val inCheck: String = "체크! 왕을 피하세요"
    const val opponentInCheck: String = "상대가 체크예요"
    /** 폰: 앱을 나가도 차례 시간은 서버에서 흐른다(1:1 만. 로봇 판은 [robotClockPauses]). */
    const val clockRunsInBackground: String = "앱을 나가도 차례 시간은 흘러요"
    const val movesTitle: String = "기보"
    const val noMoves: String = "아직 둔 수가 없어요"
    const val resign: String = "기권"
    const val resignConfirmTitle: String = "기권하면 건 루비를 잃어요"
    const val resignConfirmMessage: String = "지금 기권하면 이 판은 상대가 이겨요."
    const val resignNow: String = "기권하기"
    const val keepPlaying: String = "계속 두기"
    const val backToLobby: String = "로비로"
    const val playAgain: String = "다시 두기"
    const val rematch: String = "같은 판돈으로 다시 신청"
    /** 폰: 나 카드의 이름. */
    const val me: String = "나"
    /** 별명을 모르는 상대(탈퇴·익명화·옛 응답). */
    const val opponentFallbackName: String = "상대"
    fun resultOpponent(name: String): String = "상대 · $name"

    /** 상태줄 한 줄. `isInCheck` 는 "**차례인 쪽**이 체크인가"이므로 내 차례의 체크는 내가, 상대 차례의 체크는 상대가 피해야 한다. */
    fun statusLine(isMyTurn: Boolean, isInCheck: Boolean): String {
        if (isMyTurn) return if (isInCheck) inCheck else myTurn
        return if (isInCheck) opponentInCheck else opponentTurn
    }

    fun stoneName(color: ChessColor): String = if (color == ChessColor.white) "백" else "흑"
    fun stoneShort(color: ChessColor): String = stoneName(color)
    /** 상대 카드 부제 "흑 · 근무 중". */
    fun playerSubtitle(color: ChessColor, isWorking: Boolean): String = stoneName(color) + " · " + (if (isWorking) working else notWorking)

    /** 시계 글자 — `mm:ss`, 10초 아래는 `s.d`(소수 한 자리 — Swift `String(format: "%.1f")`). */
    fun clock(seconds: Double): String {
        val clamped = maxOf(0.0, seconds)
        if (clamped < 10) return formatOneDecimal(clamped)
        val whole = floor(clamped).toLong()
        return "${whole / 60}:${(whole % 60).toString().padStart(2, '0')}"
    }

    fun clockAccessibility(seconds: Double): String {
        val whole = roundHalfAwayFromZero(maxOf(0.0, seconds))
        if (whole >= 60) return "남은 시간 ${whole / 60}분 ${whole % 60}초"
        return "남은 시간 ${whole}초"
    }

    /** 시계가 **둘** 있는 화면(1:1 대국)의 보이스오버. 색을 안 붙이면 두 카드가 같은 말을 읽는다. */
    fun clockAccessibility(seconds: Double, color: ChessColor): String {
        val whole = roundHalfAwayFromZero(maxOf(0.0, seconds))
        val side = stoneName(color)
        if (whole >= 60) return "$side 남은 시간 ${whole / 60}분 ${whole % 60}초"
        return "$side 남은 시간 ${whole}초"
    }

    /** 수 번호 줄("24수 진행"). */
    fun plyLine(ply: Int): String = "${ply}수 진행"

    /** 깃발이 떨어지고 **유예 예산까지** 지났다 — 서버가 정산하는 중이다(폰이 판정한 것이 아니다). 결과를 지어내지 않는다. */
    const val flagSettling: String = "시간이 다 됐어요 · 결과를 확인하고 있어요"
    /** 서버 FEN 을 읽지 못해 판을 그릴 수 없다(결과·루비는 그대로 보여 준다). */
    const val unreadableBoard: String = "판을 그릴 수 없어요 · 결과는 그대로 보여요"

    /** 무승부로 끝난 판에서 **돌려받은 액수**를 말한다(±0 만 그리면 "걸었다가 그대로"인지 "잃었는지"를 못 가른다). */
    fun drawRefund(stake: Long): String = "판돈 $stake 루비를 돌려받았어요"

    /** 판 전체를 읽는 보이스오버 한 줄(64칸을 하나씩 읽히면 못 쓴다). */
    fun boardAccessibility(ply: Int, turn: ChessColor?, inCheck: Boolean): String {
        var text = "체스판, ${ply}수 진행"
        if (turn != null) text += ", ${stoneName(turn)} 차례"
        if (inCheck) text += ", 체크"
        return text
    }

    // MARK: 승격
    // INV-GamesChessText-7bc677cb 이식: 승격은 **2단** — 넷이 같은 칸으로 갈 때만 묻는다(고르기 전에는 수가 나가지 않는다).

    const val promotionTitle: String = "승격할 말을 고르세요"
    const val promotionCaption: String = "폰이 맨 끝 줄에 닿았어요 · 바꿀 말을 고르면 그 수를 둬요"
    /** 승격 창을 닫는다. [취소] 가 아니라 **무엇이 되는지**를 말한다. */
    const val promotionCancel: String = "다른 수 두기"

    /** 말 이름. 여섯 종 전부 있다(기보·보이스오버가 킹·폰도 부른다). */
    fun pieceName(kind: ChessPieceKind): String = when (kind) {
        ChessPieceKind.queen -> "퀸"
        ChessPieceKind.rook -> "룩"
        ChessPieceKind.bishop -> "비숍"
        ChessPieceKind.knight -> "나이트"
        ChessPieceKind.pawn -> "폰"
        ChessPieceKind.king -> "킹"
    }

    /** 고를 수 있는 넷의 이름. 순서는 `ChessPieceKind.promotionChoices` 가 쥔다. */
    val promotionChoiceNames: List<String> get() = ChessPieceKind.promotionChoices.map(::pieceName)

    // MARK: 무승부 제안·응답

    const val offerDraw: String = "무승부 제안"
    const val drawOfferedByMe: String = "무승부를 제안했어요 · 상대의 응답을 기다려요"
    const val drawOfferedByOpponent: String = "상대가 무승부를 제안했어요"
    const val acceptDraw: String = "무승부 수락"
    const val declineDraw: String = "거절"

    // MARK: 결과
    // INV-GamesChessText-64b3fe14 이식: 결과 — **사유 열 갈래를 빠짐없이**(`else` 로 접지 않는다).

    fun outcomeTitle(outcome: ChessMatchOutcome?): String = when (outcome) {
        ChessMatchOutcome.won -> "이겼어요"
        ChessMatchOutcome.lost -> "졌어요"
        ChessMatchOutcome.draw -> "무승부예요"
        null -> "대국이 끝났어요"
    }

    /**
     * 끝난 이유 한 줄(**내 기준** 축). 열 갈래를 모두 말한다 — 접으면 `abandoned` 가 "대국이 끝났어요"가 되어 남는 사람이 왜 2배를 받았는지 모른다.
     * INV-GamesChessText-53795d68 이식: 무승부 여섯(`isDraw`)은 **전부 문구에 '무승부'가 있다** — 특히 `timeoutInsufficient` 는 `timeout` 과
     * **다른 문장**이어야 한다(FIDE 6.9). 그 iff 를 시험이 양방향으로 못 박는다.
     */
    fun endReason(reason: ChessEndReason?, outcome: ChessMatchOutcome?): String {
        if (reason == null) return unknownEndReason(outcome)
        val won = outcome == ChessMatchOutcome.won
        return when (reason) {
            ChessEndReason.checkmate -> if (won) "체크메이트로 이겼어요" else "체크메이트를 당했어요"
            ChessEndReason.resign -> if (won) "상대가 기권했어요" else "기권했어요"
            ChessEndReason.timeout -> if (won) "상대 시간이 다 됐어요" else "시간이 다 됐어요"
            ChessEndReason.timeoutInsufficient -> "시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요"
            ChessEndReason.stalemate -> "둘 수 있는 수가 없어요 · 스테일메이트 무승부"
            ChessEndReason.fiftyMove -> "50수 동안 잡기도 폰 이동도 없었어요 · 무승부"
            ChessEndReason.threefold -> "같은 국면이 세 번 나왔어요 · 무승부"
            ChessEndReason.insufficientMaterial -> "메이트할 기물이 없어요 · 무승부"
            ChessEndReason.agreement -> "무승부에 합의했어요"
            ChessEndReason.abandoned -> if (won) "상대가 더 둘 수 없게 됐어요" else "더 둘 수 없게 됐어요"
        }
    }

    /** 사유를 **모르는** 판의 한 줄. **절대 빈 문자열을 내지 않는다** — 무승부는 무승부라고만, 나머지는 끝났다고만 말한다. */
    fun unknownEndReason(outcome: ChessMatchOutcome?): String = if (outcome == ChessMatchOutcome.draw) "무승부로 끝났어요" else "판이 끝났어요"

    /**
     * **관전** 결과 한 줄 — 3인칭이다(주어가 '흑'·'백'). [endReason] 은 '내 기준' 축이라 남의 판에 쓰면 언제나 패자 쪽 문장이 나온다.
     * [winner] 가 null(무승부·승자 모름)이면 승패를 가르는 주어를 쓰지 않는다.
     */
    fun watchEndReason(reason: ChessEndReason?, winner: ChessColor?): String {
        if (reason == null) return unknownEndReason(if (winner == null) ChessMatchOutcome.draw else null)
        val loser = winner?.opponent?.let(::stoneName)
        return when (reason) {
            ChessEndReason.checkmate -> loser?.let { "${it}이 체크메이트를 당했어요" } ?: "체크메이트"
            ChessEndReason.resign -> loser?.let { "${it}이 기권했어요" } ?: "기권으로 끝났어요"
            ChessEndReason.timeout -> loser?.let { "${it}의 시간이 다 됐어요" } ?: "시간이 다 됐어요"
            ChessEndReason.timeoutInsufficient -> "시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요"
            ChessEndReason.stalemate -> "둘 수 있는 수가 없어요 · 스테일메이트 무승부"
            ChessEndReason.fiftyMove -> "50수 동안 잡기도 폰 이동도 없었어요 · 무승부"
            ChessEndReason.threefold -> "같은 국면이 세 번 나왔어요 · 무승부"
            ChessEndReason.insufficientMaterial -> "메이트할 기물이 없어요 · 무승부"
            ChessEndReason.agreement -> "무승부에 합의했어요"
            ChessEndReason.abandoned -> loser?.let { "${it}이 더 둘 수 없게 됐어요" } ?: "더 둘 수 없게 됐어요"
        }
    }

    /** 루비 변화(+10 / −10 / ±0). 음수 기호는 앱의 다른 화면과 같은 '−'(U+2212). */
    fun rubyDelta(delta: Long): String = when {
        delta > 0 -> "+$delta"
        delta < 0 -> "−${-delta}"
        else -> "±0"
    }

    /** 결과 카드의 루비 줄 꼬리. 무승부면 **돌려받는다**고 말한다. 로봇 판은 이 줄을 쓰지 않는다. */
    fun rubyResultCaption(outcome: ChessMatchOutcome?): String? = if (outcome == ChessMatchOutcome.draw) stakeRefundOnDraw else null

    // MARK: 로봇과 두기
    // INV-GamesChessText-5fe675a9 이식: 로봇과 두기 — 판돈 없음 · 순위 없음 · **로그인 없음**.

    const val robotButton: String = "로봇과 두기"
    const val robotButtonHelp: String = "루비·순위 없이 로봇과 연습해요"
    const val robotPromptTitle: String = "어느 색으로 둘까요"
    const val robotPromptCaption: String = "색을 고르면 바로 시작해요"
    const val robotPlayWhite: String = "백 · 먼저 둬요"
    const val robotPlayBlack: String = "흑 · 나중에 둬요"
    /** 사용자 결정 둘(루비 안 걸기 · 기록 안 남기기)을 시작 전에 한 번, 대국 중에 한 번 더 말한다. */
    const val robotNoRecord: String = "루비·전적·순위에 들어가지 않아요"

    /**
     * INV-GamesChessText-41c6acc3 이식: 로봇 판은 서버를 한 번도 안 탄다 — 비로그인 사용자도 둔다. 입구에 이 줄을 두면 로그인을 요구하는 화면이
     * 돌아올 때 **글자부터** 어긋나 눈에 띈다.
     */
    const val robotNoSignIn: String = "로그인하지 않아도 둘 수 있어요"
    const val robotOpponentLine: String = "상대 · 로봇"
    const val robotName: String = "로봇"
    const val robotThinking: String = "로봇이 생각 중이에요"
    const val robotThinkingShort: String = "생각 중"
    const val robotResignConfirmTitle: String = "기권하면 이 판은 로봇이 이겨요"
    const val robotRematch: String = "같은 색으로 다시 두기"
    /** 폰: 1:1 의 [clockRunsInBackground] 와 **정반대 사실**이다 — 로봇 판 시계는 화면을 떠나면 멈춘다. */
    const val robotClockPauses: String = "화면을 떠나거나 앱을 나가면 시계가 멈춰요"

    /** 로봇 판 결과 이유. 여기도 **열 갈래 전부**다. */
    fun robotEndReason(reason: ChessEndReason?, outcome: ChessMatchOutcome?): String {
        if (reason == null) return unknownEndReason(outcome)
        val won = outcome == ChessMatchOutcome.won
        return when (reason) {
            ChessEndReason.checkmate -> if (won) "체크메이트로 이겼어요" else "체크메이트를 당했어요"
            ChessEndReason.resign -> if (won) "로봇이 기권했어요" else "기권했어요"
            ChessEndReason.timeout -> if (won) "로봇의 시간이 다 됐어요" else "시간이 다 됐어요"
            ChessEndReason.timeoutInsufficient -> "시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요"
            ChessEndReason.stalemate -> "둘 수 있는 수가 없어요 · 스테일메이트 무승부"
            ChessEndReason.fiftyMove -> "50수 동안 잡기도 폰 이동도 없었어요 · 무승부"
            ChessEndReason.threefold -> "같은 국면이 세 번 나왔어요 · 무승부"
            ChessEndReason.insufficientMaterial -> "메이트할 기물이 없어요 · 무승부"
            ChessEndReason.agreement -> "무승부에 합의했어요"
            ChessEndReason.abandoned -> "더 둘 수 없게 됐어요"
        }
    }

    // MARK: 관전 (채팅 없음 · 3분 꼬리)

    const val liveTitle: String = "지금 대결 중"
    const val noLiveMatches: String = "지금 대결 중인 판이 없어요"
    /** 폰: 로비를 불러오지 못했다(대결 중 목록은 로비 응답에 실린다). */
    const val liveLoadFailed: String = "대결 중인 판을 불러오지 못했어요"
    const val watch: String = "관전"
    const val watchTitle: String = "관전 중"
    const val watchLoading: String = "판을 불러오고 있어요"
    const val leaveWatch: String = "나가기"
    const val myMatch: String = "내 판"

    /** INV-GamesChessText-cc284a6c 이식: 관전에 **없는 것**을 미리 말한다 — 대화를 찾는 사람이 없는 기능을 기다리지 않게. */
    const val watchCaption: String = "판만 보여 줘요 · 대화는 없어요"
    /** 끝난 판이 보이는 꼬리(분). 서버가 그 뒤로는 `not_found` 를 준다. */
    const val watchTailMinutes: Int = 3
    const val watchTailCaption: String = "끝난 판은 ${watchTailMinutes}분 동안만 볼 수 있어요"
    /** 꼬리가 지나 판이 사라졌다. 코어 문구를 그대로 쓴다. */
    const val watchGone: String = ChessNoticeText.watchGone
    fun watchPly(ply: Int): String = "${ply}수"

    /** [관전] 칩의 보이스오버 힌트. */
    const val watchChipHint: String = "이 판을 지켜봐요"
    /** 서버에 관전이 아직 없으면 칩 대신 서는 캡션(**짧게** — 이름 줄이 낱글자로 꺾이지 않게). */
    const val watchSoonCaption: String = "곧 열려요"
    /** 끝난 판인데 서버가 두 사람 행을 못 채웠다(진행형으로 말하면 거짓말이 된다). */
    const val playersUnknown: String = "대국자를 불러오지 못했어요"
    /** 끝난 관전 판 머리글 — 이긴 색이 있으면 "흑 승리". */
    fun endedWin(winner: ChessColor): String = "${stoneName(winner)} 승리"
    const val endedDraw: String = "무승부로 끝났어요"
    /** 진행 중 관전 머리글 — "관전 중 · 백 차례". */
    fun watchingTurn(turn: ChessColor): String = "$watchTitle · ${stoneName(turn)} 차례"
    /** 이름을 모르는 자리(코어 경계가 이름을 모를 때 빈 문자열을 넣으므로 `?:` 로는 못 접는다). */
    const val unknownName: String = "—"

    /**
     * 판돈을 아직 모른다. INV-GamesChessText-d864ff99 이식: **액수 자리만** 비운다(관전자에게 "이기면 +N" 접미사를 붙이지 않는다 —
     * 관전자는 한 푼도 받지 않는다).
     */
    const val stakeUnknown: String = "$stakeTitle —"
    const val leaveWatchHint: String = "로비로 돌아가요"

    /** 판 부품이 **스스로** 내는 한 줄. */
    fun boardAccessibility(position: ChessPosition, whiteAtBottom: Boolean): String =
        "체스판, ${stoneName(if (whiteAtBottom) ChessColor.white else ChessColor.black)}이 아래, ${stoneName(position.sideToMove)} 차례"

    /** 관전 판 전체를 한 요소로 읽는다(말 수 · 마지막 수 · 수 번호 · 상태). 관전은 입력이 없다. */
    fun boardAccessibility(watch: ChessSpectateState): String {
        val parts = mutableListOf("체스판")
        val position = watch.position
        if (position != null) {
            var white = 0
            var black = 0
            for (index in 0 until 64) {
                val square = ChessSquare.of(index) ?: continue
                val piece = position[square] ?: continue
                if (piece.color == ChessColor.white) white += 1 else black += 1
            }
            parts.add("백 ${white}개")
            parts.add("흑 ${black}개")
        }
        watch.lastMove?.let { parts.add("마지막 수 ${it.from.notation}${it.to.notation}") }
        parts.add(watchPly(watch.plyCount))
        parts.add(GamesChessWatchStatus.headline(watch))
        return parts.joinToString(", ")
    }

    /** "민트별 · 달토끼". */
    fun livePair(live: ChessLiveMatch): String = live.a.displayName + " · " + live.b.displayName

    /** 대결이 시작된 뒤 흐른 시간을 말로("35초째" · "1분 35초째" · "1시간 2분째"). */
    fun elapsedPhrase(seconds: Double): String {
        val total = maxOf(0.0, seconds).toLong()
        if (total < 60) return "${total}초째"
        if (total < 3600) return "${total / 60}분 ${total % 60}초째"
        return "${total / 3600}시간 ${(total % 3600) / 60}분째"
    }

    // MARK: 순위
    // INV-GamesChessText-391fe2c7 이식: 순위 — 행은 **승점만 띄우지 않는다**(사용자 지시).

    const val rankTitle: String = "체스 순위"
    const val rankCaption: String = "승점 = 승 − 패"
    /** 0판인 사람은 순위판에 안 낀다(서버가 아예 안 준다). */
    const val rankZeroGamesNote: String = "한 판도 두지 않으면 순위에 들어가지 않아요"
    const val myRankTitle: String = "내 순위"
    const val outOfRank: String = "순위 밖"
    const val noRanking: String = "아직 전적이 없어요"
    const val noRankingHint: String = "첫 판이 끝나면 순위가 올라와요"
    /** 서버에 체스 순위가 아직 없다(PGRST202). **실패가 아니라 '곧'** 이다. */
    const val rankingUnavailable: String = "순위는 곧 열려요"
    const val rankingLoadFailed: String = "순위를 불러오지 못했어요"
    /** 실패 줄 **아래** 한 줄 — 원인이 둘(연결·구버전 거절)인데 화면이 가릴 수 없으므로 단정하지 않는다. */
    const val rankingLoadFailedHint: String = "계속 안 되면 앱을 업데이트해 주세요"
    /** 접힌 상태에서 보여 주는 행 수. 폰 */
    const val rankCollapsedRows: Int = 5
    /** 펼쳤을 때의 상한. 폰 */
    const val rankRowLimit: Int = 100
    fun rankSeeAll(total: Int): String = "전체 보기 · ${peopleCount(total)}"
    const val rankCollapse: String = "접기"

    /** 전적 기준시각이 있으면 "10월 1일부터". 시간대는 **KST 로 못 박는다**(컷은 서버가 정한 KST 자정 — 기기 시간대면 하루 밀린다). */
    fun rankSince(date: SwiftDate): String {
        val day = KstCalendar.localDate(date.timeIntervalSince1970)
        return "${day.month.ordinal + 1}월 ${day.day}일부터"
    }

    /** 컷이 없다(응답 `record_since_ms` 가 null) — 기간이 통째다. 폰 */
    const val rankWholePeriod: String = "전체 기간"

    /** 승점의 부호 있는 짧은 꼴("+9" · "−3" · "0"). */
    fun signedPoints(points: Long): String = when {
        points > 0 -> "+$points"
        points < 0 -> "−${-points}"
        else -> "0"
    }

    /** "승점 +4". */
    fun points(points: Long): String = "승점 ${signedPoints(points)}"

    /** "6승 2패 1무" — INV-GamesChessText-1cdb3c4e 이식: **승점만 띄우지 않는다**(사용자 지시). 0 도 지우지 않는다. */
    fun record(wins: Long, losses: Long, draws: Long): String = "${wins}승 ${losses}패 ${draws}무"

    fun record(record: ChessRecord?): String {
        if (record == null) return "0승 0패 0무"
        return record(record.wins, record.losses, record.draws)
    }

    /** 목록 밖 내 순위 한 줄 — "12위 · 승점 +4 · 6승 2패 1무"(0판이면 "순위 밖 · 0승 0패 0무"). 폰 */
    fun myRankLine(mine: ChessMyRank): String {
        val record = record(mine.wins, mine.losses, mine.draws)
        val rank = mine.rank ?: return "$outOfRank · $record"
        return "${rank}위 · ${points(mine.points)} · $record"
    }

    /**
     * 순위 한 행의 보이스오버 — "3위, 민트별, 서울센터, 승점 +4, 6승 2패 1무".
     * INV-GamesChessText-b6cda290 이식: 행은 `순위 · 아바타 · 이름 · 승점 · 승 · 패 · 무` 를 **다 말한다** — 이 라벨에서 전적을 지우면 눈이 아닌
     * 사람에게 금지된 '승점만' 상태가 된다.
     */
    fun rankRowAccessibility(entry: ChessRankEntry, isMe: Boolean): String {
        val parts = mutableListOf("${entry.rank}위")
        if (isMe) parts.add(me)
        parts.add(entry.user.displayName)
        val center = entry.user.center
        if (!center.isNullOrEmpty()) parts.add("${center}센터")
        parts.add(points(entry.points))
        parts.add(record(entry.wins, entry.losses, entry.draws))
        return parts.joinToString(", ")
    }

    // MARK: 보이스오버·토막
    // INV-GamesChessText-b9f29873 이식: 보이스오버·토막 — **화면이 제 글자를 적지 않게**(폰 뷰는 시험이 못 본다).

    /** 값을 아직 모르는 숫자 칸. [unknownName](em dash)과 **다른 글리프**다. */
    const val unknownNumber: String = "–"
    const val bulletPrefix: String = "· "
    const val selected: String = "선택됨"
    fun myRecordAccessibility(record: ChessRecord?): String = "내 체스 전적 ${record(record)}"
    /** [도전] 버튼의 보이스오버 힌트 — 누르면 **바로 신청이 나가지 않는다**(판돈 시트가 먼저다). */
    fun challengeHint(name: String): String = "${name}님에게 판돈을 골라 신청해요"
    fun remainingAccessibility(seconds: Double): String = "남은 시간 ${remaining(seconds)}"
    fun stakeOptionAccessibility(stake: Long): String = "판돈 루비 $stake"
    fun rubyDeltaAccessibility(text: String): String = "루비 $text"

    // MARK: 조사

    /** 받침이 있으면 "을", 없으면(한글이 아니어도) "를". */
    fun objectParticle(word: String): String {
        val scalar = lastScalar(word) ?: return "를"
        if (scalar !in 0xAC00..0xD7A3) return "를"
        return if ((scalar - 0xAC00) % 28 == 0) "를" else "을"
    }

    /** 받침이 있으면 "과", 없으면 "와". */
    fun withParticle(name: String): String {
        val scalar = lastScalar(name) ?: return "와"
        if (scalar !in 0xAC00..0xD7A3) return "와"
        return if ((scalar - 0xAC00) % 28 == 0) "와" else "과"
    }

    /** 마지막 유니코드 스칼라(Swift `unicodeScalars.last`). */
    private fun lastScalar(text: String): Int? {
        if (text.isEmpty()) return null
        val last = text[text.length - 1]
        if (last.isLowSurrogate() && text.length >= 2 && text[text.length - 2].isHighSurrogate()) {
            val high = text[text.length - 2]
            return ((high.code - 0xD800) shl 10) + (last.code - 0xDC00) + 0x10000
        }
        return last.code
    }
}

/** 파일 이름(`GamesChessText`)으로 부르는 쪽도 같은 표를 가리키게 둔 별칭(Swift 와 같다). */
typealias GamesChessText = ChessPhoneText

/**
 * 규칙 보기 시트의 한 줄. 맥 `ChessRulesOverlay.lines`(FIDE 요약) + 폰의 **시계·판돈** 두 줄.
 */
data class ChessPhoneRuleLine(val title: String, val detail: String) {
    val id: String get() = title

    companion object {
        /**
         * 규칙 줄 전부. 시간 수치는 **서버가 말한 값**에서 만든다.
         * INV-GamesChessText-430221f8 이식: 마지막 둘이 돈이 갈리는 자리다 — "시간" 줄은 **FIDE 6.9 예외**를, "판돈" 줄은 루비가 빠지는 순간이
         * **수락**이라고 말한다. 둘 중 하나가 빠지면 돌려받은 루비를 잃은 것으로 읽거나 신청만으로 루비가 빠졌다고 믿는다.
         */
        fun all(
            initialMs: Long = ChessClock.initialMs.toLong(),
            incrementMs: Long = (ChessClock.incrementSeconds * 1000).toLong(),
            inviteTtlSeconds: Int = ChessPhoneText.inviteTtlSecondsFallback,
        ): List<ChessPhoneRuleLine> = listOf(
            ChessPhoneRuleLine("기본", "백이 먼저 둬요. 왕을 잡히지 않게 두면서 상대 왕을 피할 수 없게 만들면(체크메이트) 이겨요."),
            ChessPhoneRuleLine("캐슬링", "왕과 룩이 한 번도 움직이지 않았고 사이가 비어 있으면 왕을 두 칸 옮겨 룩과 자리를 바꿔요."),
            ChessPhoneRuleLine("앙파상", "상대 폰이 두 칸 전진해 내 폰 옆에 섰다면, 바로 다음 수에 한 칸 지나간 자리로 잡을 수 있어요."),
            ChessPhoneRuleLine("승격", "폰이 맨 끝 줄에 닿으면 퀸·룩·비숍·나이트 중 하나로 바꿔요."),
            ChessPhoneRuleLine(
                "무승부",
                "둘 곳이 없는데 체크가 아니면(스테일메이트), 50수 동안 잡기·폰 이동이 없으면, 같은 국면이 세 번 나오면, " +
                    "메이트할 기물이 없으면, 또는 두 사람이 합의하면 무승부예요.",
            ),
            ChessPhoneRuleLine(
                "시간",
                "${ChessPhoneText.clockPhrase(initialMs, incrementMs)}예요. 시간을 다 쓰면 지는데, 상대에게 메이트할 기물이 없으면 무승부예요.",
            ),
            ChessPhoneRuleLine("판돈", "${ChessPhoneText.stakeCaption}. ${ChessPhoneText.stakeNotHeldYet(inviteTtlSeconds)}."),
            ChessPhoneRuleLine(
                "한 사람 한 판",
                // INV-GamesChessText-869daee5 이식: 게임이 셋이다(1.0.11 — 1:1 테트리스). 셋을 다 말해야 한다 — 이름이 빠진 게임은 사용자가
                // "그건 되겠지" 하고 눌렀다가 서버 거절을 받는 동안 **두던 판의 시계를 쓴다**.
                "체스·오목·1:1 테트리스는 한 번에 한 판만 할 수 있어요. 한 판을 하는 중에는 다른 쪽을 신청하거나 수락할 수 없어요.",
            ),
        )
    }
}

/**
 * Swift `String(format: "%.1f", x)`(0 ≤ x < 10) — **정확한 이진 값**을 소수 첫째 자리에서 가장 가까운 쪽으로, 딱 반이면 짝수 쪽으로(Darwin printf).
 * JVM `String.format` 은 반을 위로 올려(HALF_UP) 2.25 를 "2.3" 으로 쓴다(Darwin 은 "2.2") — 그래서 비트로 직접 셈한다.
 */
internal fun formatOneDecimal(x: Double): String {
    if (x == 0.0 || !x.isFinite() || x < 0) return "0.0"
    val bits = x.toRawBits()
    val exponentBits = ((bits ushr 52) and 0x7FF).toInt()
    val fraction = bits and 0xFFFFFFFFFFFFFL
    val mantissa = if (exponentBits == 0) fraction else fraction or (1L shl 52)
    val exponent = if (exponentBits == 0) -1074 else exponentBits - 1075
    // x = mantissa · 2^exponent. x < 10 이라 exponent < 0 이다. 10x = 10·mantissa · 2^exponent(10·mantissa < 2^57 — Long 에 든다).
    val shift = -exponent
    val tenM = 10 * mantissa
    var tenths: Long
    if (shift >= 62) {
        tenths = 0 // x < 2^-5 — 0.1 의 반보다 작다
    } else {
        tenths = tenM ushr shift
        val remainder = tenM - (tenths shl shift)
        val half = 1L shl (shift - 1)
        if (remainder > half || (remainder == half && tenths % 2 == 1L)) tenths += 1
    }
    return "${tenths / 10}.${tenths % 10}"
}
