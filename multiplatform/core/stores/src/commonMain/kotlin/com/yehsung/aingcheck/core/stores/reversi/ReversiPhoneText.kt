// 원본: Sources/CheckMobileKit/Games/GamesReversiText.swift @ ios-1017-int 879c9952(카드 절 1/4 · 판 갈래 2/4 · 로비 갈래 3/4 전부)
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.reversi.ReversiPoint
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.rules.reversi.ReversiScore

// 폰 아잉 뒤집기(판 7 — 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)") 화면 문구 표. **글자는 iOS 1.0.17 `ReversiPhoneText` 와 한 글자도 다르지 않다.**
//
// ── 어디까지가 이 표의 몫인가 ── 안내·결과 사유는 코어 [ReversiNoticeText] 가 쥔다(신청·취소·수락·착수·기권 응답 · 패스 · 자동 착수 · 관전 · 배포 창).
// 이 표는 **화면에 붙는 글자**(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다. 게임 이름 글자는 [ReversiNoticeText.gameName] 한 곳이다.
// ── 상표 ── 게임 이름은 '아잉 뒤집기'뿐이다. '리버시'는 **규칙 설명**으로만 쓴다(부제 · 규칙 마지막 줄 — 맥 `ReversiText.subtitle` 과 같은 자리).
// ── 빌린 글자 ── 체스·오목 표와 같은 문장은 그 표를 부른다(같은 말 한 곳 — iOS 가 같은 자리에서 같은 표를 부른다).
// 레인 규약(iOS 그대로): 키를 더할 때는 **자기 절 끝**에만 더한다.

/** 폰 아잉 뒤집기 화면 문구 표(iOS `ReversiPhoneText`). */
object ReversiPhoneText {

    // MARK: - 공용 · 게임 탭 카드 (배선 갈래 1/4)

    const val title: String = ReversiNoticeText.gameName

    /** 게임 탭 카드 부제 · 로비 머리글 부제(맥 `ReversiText.subtitle` 과 같은 한 줄 — 규칙 · 선공 · 한 수 시간). */
    const val subtitle: String = "리버시 규칙 · 흑 선공 · 한 수 30초"
    const val cardSubtitle: String = subtitle

    /** 게임 탭 카드의 화면 읽기 힌트(막히지 않았을 때). */
    const val cardOpenHint: String = "${ReversiNoticeText.gameName} 대결 화면을 열어요"

    /** 카드 칩: 받은 신청이 있다(몇 건인지는 칩이 말한다 — 탭 배지와 같은 수). */
    fun incomingChip(count: Int): String = "받은 신청 ${count}건"

    /** 카드 보조 줄: 보낸 신청의 답을 기다린다. */
    const val outgoingLine: String = "보낸 신청의 답을 기다리고 있어요"

    /** 칩도 보조 줄 재료도 없을 때의 카드 한 줄(= 할 일을 말한다). AI 연습이 있다는 것도 함께 말한다. */
    const val idleLine: String = "사람을 골라 신청하거나 로봇과 연습해 보세요"

    const val recordTitle: String = "내 전적"

    fun record(wins: Int, losses: Int, draws: Int): String = "${wins}승 ${losses}패 ${draws}무"

    fun record(record: ReversiRecord?): String = if (record == null) record(0, 0, 0) else record(record.wins, record.losses, record.draws)

    // MARK: - 판 · 결과 · 로봇 연습 (판 갈래 2/4)
    //
    // 맥 `ReversiText` 의 대국·결과·AI 절과 같은 사실을 같은 말로. 폰에서 달라진 자리(iOS 와 같다): 연습 상대 이름이 '로봇' · 끝난 까닭의 '상대'는 로봇 판에서
    // '로봇' · 호버 툴팁이 없어 시계 규칙을 판 밑 한 줄로 말한다.

    const val me: String = "나"

    /** 별명을 모르는 상대(탈퇴·익명화·옛 응답). */
    const val opponentFallbackName: String = "상대"
    const val myTurn: String = "내 차례예요"
    const val opponentTurn: String = "상대 차례예요"

    /** 1:1 판의 내 마감 + 서버 유예가 지났다 — 서버가 합법 수 가운데 하나를 대신 두는 중이다(폰이 정한 것이 아니다). */
    const val mySettling: String = "시간이 지나 자동으로 놓이는 중이에요"
    const val opponentSettling: String = "상대 시간이 지나 자동으로 놓이는 중이에요"

    fun stoneName(color: ReversiColor): String = if (color == ReversiColor.black) "흑" else "백"

    /** 카드의 돌 수 줄 "흑 · 12개". */
    fun discLine(color: ReversiColor, count: Int): String = "${stoneName(color)} · ${count}개"

    /** 판 위 돌 수 한 줄 "흑 2 · 백 2 · 빈칸 60". */
    fun counts(counts: ReversiCounts): String = "흑 ${counts.black} · 백 ${counts.white} · 빈칸 ${counts.empty}"

    /** 연달아 자동으로 놓인 횟수(카드 꼬리). 0 이면 말하지 않는다. */
    fun autoStreak(streak: Int, limit: Int): String? = if (streak > 0) "자동 $streak/$limit" else null

    /** 한 번 더 놓치면 지는 순간(빨강 한 줄). 맥 `ReversiText.autoStreakWarning` 과 같은 말. */
    fun autoStreakWarning(streak: Int, limit: Int): String? = if (limit > 1 && streak == limit - 1) "한 번 더 시간이 지나면 져요" else null

    /** 판 위 회색 점이 말하는 것을 글자로도(폰엔 툴팁이 없다). */
    fun autoPlacedCount(count: Int): String = "시간이 지나 자동으로 놓인 돌 ${count}개 · 회색 점"

    /**
     * 판 밑 시계 규칙 한 줄. **숫자는 서버가 말한 값**(로비 `turn_seconds` · 판의 `auto_abandon_streak`)에서 만든다.
     * 1:1 은 앱을 나가도 서버 시계가 흐르고, 로봇 판은 화면을 떠나면 사람 시계가 멈춘다(**정반대 사실** — 한 줄이 둘을 가른다).
     */
    fun clockLine(isAI: Boolean, turnSeconds: Int, lossStreak: Int): String {
        val rule = "한 수 ${turnSeconds}초가 지나면 자동으로 놓이고 ${lossStreak}번 이어지면 져요"
        return (if (isAI) "화면을 떠나거나 앱을 나가면 내 시계가 멈춰요" else "앱을 나가도 차례 시간은 흘러요") + " · " + rule
    }

    /** 남은 초("12초") — 올림(Swift `.rounded(.up)`). */
    fun remaining(seconds: Double): String = "${kotlin.math.ceil(maxOf(0.0, seconds)).toInt()}초"
    fun clockAccessibility(seconds: Double): String = "남은 시간 ${remaining(seconds)}"

    const val movesTitle: String = "수 기록"
    const val noMoves: String = "아직 둔 수가 없어요"

    /** 수 기록의 패스 칸. */
    const val pass: String = "넘김"

    /** 칸 표기("d3"). 범위 밖이면 "—". */
    fun coordinate(idx: Int?): String {
        if (idx == null) return "—"
        return ReversiPoint.of(idx)?.coord ?: "—"
    }

    /** 수 한 칸 글자: 돌이면 "d3"(자동이면 "d3 · 자동"), 패스면 "넘김". */
    fun plyText(ply: ReversiPly): String = when (ply.kind) {
        ReversiPly.Kind.pass -> pass
        ReversiPly.Kind.stone -> if (ply.auto) "${coordinate(ply.idx)} · 자동" else coordinate(ply.idx)
    }

    const val resign: String = "기권"
    const val resignConfirmTitle: String = "기권하면 건 루비를 잃어요"
    const val resignConfirmMessage: String = "지금 기권하면 이 판은 상대가 이겨요."
    const val resignNow: String = "기권하기"
    const val keepPlaying: String = "계속 두기"
    const val backToLobby: String = "로비로"

    fun outcomeTitle(outcome: ReversiMatchOutcome?): String = when (outcome) {
        ReversiMatchOutcome.won -> "이겼어요"
        ReversiMatchOutcome.lost -> "졌어요"
        ReversiMatchOutcome.draw -> "무승부예요"
        null -> "대국이 끝났어요"
    }

    /**
     * 끝난 까닭 한 줄(**내 기준**). 끝 사유 여섯 갈래를 빠짐없이 말한다(`else` 로 접지 않는다 — 돈이 갈리는 문장이다).
     * [opponent] 는 주어 낱말이다(1:1 '상대' · 로봇 판 '로봇'). [lossStreak] 는 그 판의 서버 값(자동 착수 연속 패 횟수).
     */
    fun endReason(reason: ReversiEndReason?, outcome: ReversiMatchOutcome?, opponent: String, lossStreak: Int): String {
        if (reason == null) return ""
        return when (reason) {
            ReversiEndReason.wipeout -> if (outcome == ReversiMatchOutcome.lost) "내 돌이 모두 뒤집혔어요" else "$opponent 돌을 모두 뒤집었어요"
            ReversiEndReason.boardFull -> "판이 가득 찼어요"
            ReversiEndReason.noMoves -> "둘 다 둘 곳이 없어요"
            ReversiEndReason.resign -> if (outcome == ReversiMatchOutcome.won) "$opponent${subjectParticle(opponent)} 기권했어요" else "기권했어요"
            ReversiEndReason.abandoned ->
                if (outcome == ReversiMatchOutcome.won) "$opponent 시간이 ${lossStreak}번 이어서 지났어요" else "시간이 ${lossStreak}번 이어서 지나 졌어요"
            ReversiEndReason.unknown -> "대국이 끝났어요"
        }
    }

    /** 자연 종료 점수 줄 — **흑 : 백 고정**(내 색 먼저가 아니다). 빈칸이 있으면 판 위 돌 수를 괄호로 함께(빈칸은 이긴 쪽 점수다). */
    fun scoreLine(score: ReversiScore, counts: ReversiCounts): String {
        val main = "흑 : 백  ${score.black} : ${score.white}"
        if (counts.empty <= 0) return main
        return "$main (판 위 ${counts.black} : ${counts.white})"
    }

    /** 기권·자리 비움 판(점수 없음) — 점수 줄 대신 판 위 돌 수만. */
    fun boardOnlyLine(counts: ReversiCounts): String = "판 위 흑 ${counts.black} : 백 ${counts.white}"

    /** 루비 변화(+5 / −5 / ±0). */
    fun rubyDelta(delta: Int): String = when {
        delta > 0 -> "+$delta"
        delta < 0 -> "−${-delta}"
        else -> "±0"
    }

    fun rubyDeltaAccessibility(text: String): String = "루비 $text"

    /** 무승부 판의 루비 — 건 판돈이 그대로 돌아왔다. */
    fun drawRefund(stake: Int): String = "판돈 $stake 루비를 돌려받았어요"

    /** " · 이기면 +5"(내비 부제 판돈 줄 꼬리 — 순이익). */
    fun stakeGainSuffix(stake: Int): String = " · 이기면 +${DuelFee.winnerNet(stake)}"

    /** 판 전체 화면 읽기 한 줄(돌 수 · 차례 · 둘 수 있는 칸 수). */
    fun boardAccessibility(counts: ReversiCounts, turn: ReversiColor?, legalCount: Int): String {
        var text = "$title 판, ${counts(counts)}"
        if (turn != null) text += ", ${stoneName(turn)} 차례"
        if (legalCount > 0) text += ", 둘 수 있는 칸 ${legalCount}곳"
        return text
    }

    /** 칸 하나의 화면 읽기("d3, 흑 돌, 마지막 수" · "c4, 빈칸, 둘 수 있어요"). 칸 이름이 먼저다 — 판을 훑는 사람은 이름으로 찾는다. */
    fun cellAccessibility(idx: Int, stone: ReversiColor?, isLegal: Boolean, isLast: Boolean, isAuto: Boolean): String {
        val parts = mutableListOf(coordinate(idx))
        if (stone != null) {
            parts += "${stoneName(stone)} 돌"
            if (isLast) parts += "마지막 수"
            if (isAuto) parts += "자동으로 놓임"
        } else {
            parts += "빈칸"
            if (isLegal) parts += "둘 수 있어요"
        }
        return parts.joinToString(", ")
    }

    // 로봇 연습(맥 'AI와 두기' 와 같은 단계: 돌 색 고르기 → 곧바로 판 → 결과에서 같은 색으로 다시).
    val aiName: String get() = ReversiUser.reversiAI.displayName
    const val aiButton: String = "로봇과 연습하기"
    const val aiButtonHelp: String = "루비·전적 없이 로봇과 둬요"
    const val aiPromptTitle: String = "어느 돌로 둘까요"
    const val aiPromptCaption: String = "고르면 바로 시작해요"
    const val aiPlayBlack: String = "흑 · 먼저 둬요"
    const val aiPlayWhite: String = "백 · 나중에 둬요"
    const val aiPlayRandom: String = "무작위"
    const val aiNoRecord: String = "로봇과 둔 판은 루비·전적·순위에 남지 않아요"
    const val aiStakeChip: String = "로봇과 연습 · 기록 없음"
    const val aiThinking: String = "로봇이 생각 중이에요"
    const val aiThinkingShort: String = "생각 중"
    const val aiResignConfirmTitle: String = "기권하면 이 판은 로봇이 이겨요"
    const val aiRematch: String = "같은 색으로 다시 두기"
    const val aiOpponentLine: String = "상대 · 로봇"
    fun opponentLine(name: String): String = "상대 · $name"

    /** 로봇 연습 입구가 닫힌 까닭(맥은 버튼만 흐린다 — 폰엔 툴팁이 없어 **언제 풀리는지**를 글자로 말한다). */
    enum class AIBlock {
        /** 1:1 판이 서 있다(같은 계정 다른 기기의 판 포함). */
        playing,

        /** 보낸 신청이 떠 있다 — 수락되는 순간 1:1 이 연습 판을 이긴다. */
        outgoingInvite,

        /** 요청이 오가는 중. */
        busy,
    }

    fun aiBlock(reason: AIBlock): String = when (reason) {
        AIBlock.playing -> "두고 있는 판이 끝나면 연습할 수 있어요"
        AIBlock.outgoingInvite -> "보낸 신청을 취소하면 연습할 수 있어요"
        AIBlock.busy -> "잠시 후 다시 눌러 주세요"
    }

    /** 받침 고르기(이/가). 끝 글자에 받침이 있으면 "이", 없으면 "가"(한글이 아니면 "가"). */
    private fun subjectParticle(word: String): String {
        val last = word.lastOrNull()?.code ?: return "가"
        if (last !in 0xAC00..0xD7A3) return "가"
        return if ((last - 0xAC00) % 28 == 0) "가" else "이"
    }

    // MARK: - 로비 · 신청 · 받기 · 관전 · 순위 · 규칙 (로비 갈래 3/4)
    //
    // 숫자(한 수 초 · 신청 유효 초 · 연속 자동 패 횟수)는 **로비 응답 값**을 받는다 — 상수를 베끼면 서버가 바꾼 날 화면만 옛 숫자를 말한다.
    // 폰엔 호버 툴팁이 없다 — 막힌 버튼은 **왜**를, 아래 한 줄은 **언제 풀리는지**를 글자로 말한다.

    /** 로비 머리 한 줄. 한 수 시간은 서버가 말한 값(응답 전에는 30). 30초면 카드 부제([subtitle])와 같은 글자다. */
    fun lobbySubtitle(turnSeconds: Int): String = "리버시 규칙 · 흑 선공 · 한 수 ${maxOf(1, turnSeconds)}초"

    const val lobbyTitle: String = "상대 고르기"
    const val lobbyCaption: String = "근무 중이 아니어도 신청하고 받을 수 있어요"
    const val emptyUsers: String = "지금 대결할 수 있는 사람이 없어요"
    const val loadingUsers: String = "상대 목록을 불러오고 있어요"
    fun peopleCount(count: Int): String = "${count}명"
    const val myRubyTitle: String = "내 루비"

    /** 값을 아직 모르는 숫자 칸(루비 잔액 미러가 비었다). 관전 이름 자리의 [watchUnknownName](em dash)과 **다른 글리프**다. */
    const val unknownNumber: String = "–"

    /** 한 줄 안에서 토막을 잇는 머리("· 루비가 모자라요"). */
    const val bulletPrefix: String = "· "

    /** 고른 칸의 접근성 값. */
    const val selected: String = "선택됨"

    /** 머리 두 칸 왼쪽(내 전적)의 화면 읽기 — 제목과 값이 한 요소로 합쳐지므로 무슨 전적인지 말한다. */
    fun myRecordAccessibility(record: ReversiRecord?): String = "내 $title 전적 ${record(record)}"

    // 상대 한 줄.
    const val challenge: String = "도전"
    const val working: String = "근무 중"
    const val notWorking: String = "근무 안 함"

    /** 막힌 [도전] 자리 글자 — **짧게**(알약 안에서 꺾이면 줄 높이가 는다). 뜻은 아래 [lockLegend] 한 줄이 풀어 말한다. */
    const val needsUpdateButton: String = "업데이트 필요"

    /** 상대가 지금 1:1 판을 두는 중(서버 `game__busy_users` — 어느 게임인지는 말하지 않는다). */
    const val inMatchButton: String = "대결 중"
    const val focusButton: String = "집중 모드"

    /** [도전] 의 화면 읽기 힌트 — 누르면 **바로 신청이 나가지 않는다**(판돈 시트가 먼저다). */
    fun challengeHint(name: String): String = "${name}님에게 판돈을 골라 신청해요"

    /** 상대를 지금 신청할 수 없는 까닭. **서열**: 옛 버전(상대가 앱을 올릴 때까지 가장 오래 간다) > 대결 중 > 집중. */
    enum class Lock {
        /** 상대 앱이 아잉 뒤집기를 모른다(서버 `reversi_capable` 거짓 · **모르면 거짓**). 서버 `reversi_android_min_build` 가 닫힌 동안 안드로이드 상대가 이 갈래다. */
        outdated,

        /** 상대가 1:1 판을 두는 중(서버 `game__busy_users`). */
        inMatch,

        /** 상대가 집중 모드(서버 `target_focused`). */
        focus,
    }

    /** 그 사람에게 걸린 까닭 전부(서열 순). 비었으면 신청할 수 있는 상대다. */
    fun locks(user: ReversiUser): List<Lock> = buildList {
        if (!user.isCapable) add(Lock.outdated)
        if (user.inMatch) add(Lock.inMatch)
        if (user.focusMode) add(Lock.focus)
    }

    /** 상대 한 줄이 쓰는 **두 자리** — 이름 아래 회색 부제와 오른쪽 버튼 글자. */
    data class OpponentRow(val subtitle: String, val buttonTitle: String)

    /** 상대 한 줄의 두 자리를 **한 함수**가 고른다. 부제는 늘 **근무 축**으로 시작하고, 버튼은 서열 첫 까닭을 말한다. 버튼이 못 말한 까닭은 부제 꼬리로 보낸다. */
    fun opponentRow(user: ReversiUser): OpponentRow {
        val work = if (user.isWorking) working else notWorking
        val locks = locks(user)
        val first = locks.firstOrNull() ?: return OpponentRow(work, challenge)
        val tail = locks.drop(1).map(::lockButton)
        return OpponentRow((listOf(work) + tail).joinToString(" · "), lockButton(first))
    }

    fun lockButton(lock: Lock): String = when (lock) {
        Lock.outdated -> needsUpdateButton
        Lock.inMatch -> inMatchButton
        Lock.focus -> focusButton
    }

    /** 목록 아래 풀이 한 줄(그 까닭이 목록에 **있을 때만** 선다). 버튼 글자 + 왜 · 언제 풀리는지. 옛 버전 문장은 코어 거절 문구와 같다. */
    fun lockLegend(lock: Lock): String = when (lock) {
        Lock.outdated -> "$needsUpdateButton · ${ReversiNoticeText.targetOutdated} — 상대가 앱을 올리면 신청할 수 있어요"
        Lock.inMatch -> "$inMatchButton · 다른 1:1 판을 두는 중이에요 — 판이 끝나면 신청할 수 있어요"
        Lock.focus -> "$focusButton · 상대가 집중 중이에요 — 집중이 끝나면 신청할 수 있어요"
    }

    /** 지금 목록에 있는 까닭의 풀이 줄(서열 순 · 중복 없음). */
    fun lockLegends(users: List<ReversiUser>): List<String> {
        val present = users.flatMap(::locks).toSet()
        return Lock.entries.filter { it in present }.map(::lockLegend)
    }

    // 판돈(★ 빠지는 순간은 **수락**이다 — 신청만으로는 0원도 안 움직인다).
    const val stakeTitle: String = "판돈"

    /** "5 · 이기면 +5" — 꼬리 숫자는 **순이익**(결과 카드의 루비 변화와 같은 숫자). */
    fun stakeLine(stake: Int): String = "$stake · 이기면 +${DuelFee.winnerNet(stake)}"

    /** 판돈 칸 아래 줄 "이기면 +5"(꼬리 [stakeGainSuffix] 와 달리 앞 가운뎃점이 없다). */
    fun stakeGain(stake: Int): String = "이기면 +${DuelFee.winnerNet(stake)}"
    fun stakePromptTitle(name: String): String = "${name}님에게 신청"
    const val stakePromptCaption: String = "판돈을 고르세요"
    fun stakePromptChosen(stake: Int): String = "판돈 ${stakeLine(stake)}"
    fun challengeWithStake(stake: Int): String = "$stake 걸고 도전하기"

    /** 루비가 모자라 못 고르는 판돈의 까닭 — 앱의 다른 화면과 **같은 말**(한 곳). */
    val stakeShortfall: String get() = SharedText.shortfallNotice(null, null)

    /** 판돈이 **언제** 빠지는지 — 오목·체스·테트리스와 같은 문장(주어가 '수락'). */
    const val stakeCaption: String = GomokuPhoneText.stakeCaption

    /** 신청만 한 상태를 말하는 줄 — 체스와 같은 문장 한 곳. 초는 로비 응답 값. */
    fun stakeNotHeldYet(ttlSeconds: Int): String = ChessPhoneText.stakeNotHeldYet(ttlSeconds)
    fun stakeOptionAccessibility(stake: Int): String = "판돈 루비 $stake"

    // 받은 신청 · 보낸 신청(60초 — 로비 응답 `invite_ttl_seconds`).
    const val incomingTitle: String = "받은 신청"
    const val outgoingTitle: String = "보낸 신청"
    fun incomingTitle(name: String): String = "${name}님의 신청"
    fun outgoingTitle(name: String): String = "${name}님에게 신청했어요"
    const val accept: String = "수락"
    const val decline: String = "거절"
    const val cancel: String = "취소"

    /** 받은 신청 절 머리 오른쪽 — 초는 로비 응답 값. */
    fun inviteTtlHint(ttlSeconds: Int): String = "${ttlSeconds}초 안에 응답하세요"

    /** "42초 남음"(받은·보낸 신청 부제 — 잎만 부른다). */
    fun remainingPhrase(seconds: Double): String = "${remaining(seconds)} 남음"

    /** 받은 신청 [수락] 이 두던 **로봇 판을 끝낸다** — 먼저 묻는다(체스와 같은 확인 · 같은 문장 한 곳). */
    const val acceptEndsRobotTitle: String = ChessPhoneText.acceptEndsRobotTitle
    const val acceptEndsRobotMessage: String = ChessPhoneText.acceptEndsRobotMessage
    const val acceptEndsRobotConfirm: String = ChessPhoneText.acceptEndsRobotConfirm
    const val acceptEndsRobotCancel: String = ChessPhoneText.acceptEndsRobotCancel

    /** 판(로봇 연습 · 끝난 판) 화면 위 받은 신청 띠 — 로비가 가려진 동안에도 60초 신청을 놓치지 않게. */
    fun bannerTitle(name: String): String = "${name}님이 $title 대결을 신청했어요"

    /** 띠에 다 못 실은 나머지 신청 수. */
    fun incomingMore(count: Int): String = "외 ${count}건"

    // 지금 대결 중 · 관전.
    const val liveTitle: String = "지금 대결 중"
    const val noLive: String = "지금 대결 중인 판이 없어요"
    fun liveCount(count: Int): String = "${count}판"

    /** "민트별 · 달토끼" — a/b 는 uuid 순서다(색이 아니다 — 색은 관전 응답이 말한다). */
    fun livePair(live: ReversiLiveMatch): String = live.a.displayName + " · " + live.b.displayName

    /** "1분 35초째"(체스와 같은 말 한 곳). */
    fun elapsedPhrase(seconds: Double): String = ChessPhoneText.elapsedPhrase(seconds)
    const val watch: String = "관전"
    const val watchChipHint: String = "이 판을 지켜봐요"
    const val myMatch: String = "내 판"

    /** 서버에 관전이 아직 없다(PGRST202) — 칩 대신 글자(화면 읽기는 코어 문장 [ReversiNoticeText.unavailable]). */
    const val watchSoonCaption: String = "곧 열려요"
    const val watchTitle: String = "관전 중"
    const val leaveWatch: String = "나가기"
    const val leaveWatchHint: String = "로비로 돌아가요"
    const val watchLoading: String = "판을 불러오고 있어요"

    /** 끝난 판인데 대국자를 하나도 모른다(진행형으로 말하면 거짓말이다 — 폴링이 이미 멈췄다). */
    const val playersUnknown: String = "대국자를 불러오지 못했어요"

    /** 이름을 모르는 자리(코어 경계가 null 이 아니라 빈 문자열을 넣는다). */
    const val watchUnknownName: String = "—"
    const val stakeUnknown: String = "$stakeTitle —"
    fun watchingTurn(turn: ReversiColor): String = "$watchTitle · ${stoneName(turn)} 차례"

    /** 끝난 관전 판 머리 — **3인칭**("구름빵(흑) 승리"). 이름을 모르면 색만("흑 승리"). */
    fun watchEndedWin(winner: ReversiColor, name: String?): String {
        val trimmed = name?.trim().orEmpty()
        return if (trimmed.isEmpty()) "${stoneName(winner)} 승리" else "$trimmed(${stoneName(winner)}) 승리"
    }

    const val watchEndedDraw: String = "무승부로 끝났어요"

    /** **관전** 끝난 까닭 — 3인칭(주어가 '흑'·'백'). 내 기준 [endReason] 을 남의 판에 쓰면 자기모순이 된다(맥 `ReversiText.watchEndReason` 과 같은 표). */
    fun watchEndReason(reason: ReversiEndReason?, winner: ReversiColor?, lossStreak: Int): String {
        if (reason == null) return ""
        val loser = winner?.let { stoneName(it.opponent) }
        return when (reason) {
            ReversiEndReason.wipeout -> loser?.let { "$it 돌이 모두 뒤집혔어요" } ?: "한쪽 돌이 모두 뒤집혔어요"
            ReversiEndReason.boardFull -> "판이 가득 찼어요"
            ReversiEndReason.noMoves -> "둘 다 둘 곳이 없어요"
            ReversiEndReason.resign -> loser?.let { "$it${subjectParticle(it)} 기권했어요" } ?: "기권으로 끝났어요"
            ReversiEndReason.abandoned -> loser?.let { "$it 시간이 ${lossStreak}번 이어서 지났어요" } ?: "시간이 ${lossStreak}번 이어서 지나 끝났어요"
            ReversiEndReason.unknown -> "대국이 끝났어요"
        }
    }

    const val watchCaption: String = "판만 보여 줘요 · 관전자는 둘 수 없어요"

    /** 서버 `reversi_watch_tail_seconds()`(180초) — 끝난 판은 그 안에서만 관전 응답이 온다. */
    const val watchTailCaption: String = "끝난 판은 3분 동안만 볼 수 있어요"
    fun watchMoves(count: Int): String = "${maxOf(0, count)}수"

    // 순위(승점 = 승 − 패 · 서버 순서 그대로 · 0판은 안 낀다).
    const val rankTitle: String = "$title 순위"
    const val rankCaption: String = "승점 = 승 − 패"
    const val rankZeroGamesNote: String = "한 판도 두지 않으면 순위에 들어가지 않아요"
    const val myRankTitle: String = "내 순위"
    const val outOfRank: String = "순위 밖"
    const val noRanking: String = "아직 전적이 없어요"
    const val noRankingHint: String = "첫 판이 끝나면 순위가 올라와요"

    /** 서버에 순위가 아직 없다(PGRST202) — 실패가 아니라 '곧'. */
    const val rankingUnavailable: String = "순위는 곧 열려요"
    const val rankLoading: String = "순위를 불러오고 있어요"

    /** 접힌 상태의 행 수 · 펼쳤을 때 상한(서버는 100행까지 준다). */
    const val rankCollapsedRows: Int = 5
    const val rankRowLimit: Int = 100
    fun rankSeeAll(total: Int): String = "전체 보기 · ${peopleCount(total)}"
    const val rankCollapse: String = "접기"

    /** 전적 컷이 있으면 머리 오른쪽 "10월 1일부터" — **KST 로 못 박는다**(체스 표와 같은 까닭 · 같은 함수). */
    fun rankSince(date: SwiftDate): String = ChessPhoneText.rankSince(date)

    /** 컷이 없다(`record_since_ms` null) — 기간이 통째다. */
    const val rankWholePeriod: String = "전체 기간"

    /** 승점의 부호 있는 짧은 꼴("+9" · "−3" · "0"). */
    fun signedPoints(points: Int): String = when {
        points > 0 -> "+$points"
        points < 0 -> "−${-points}"
        else -> "0"
    }

    fun points(points: Int): String = "승점 ${signedPoints(points)}"

    /** 목록 밖 내 순위 한 줄 — "12위 · 승점 +4 · 6승 2패 1무"(0판이면 "순위 밖 · 0승 0패 0무"). */
    fun myRankLine(mine: ReversiMyRank): String {
        val record = record(mine.wins, mine.losses, mine.draws)
        val rank = mine.rank ?: return "$outOfRank · $record"
        return "${rank}위 · ${points(mine.points)} · $record"
    }

    /** 순위 한 행의 화면 읽기 — "3위, 나, 민트별, 서울센터, 승점 +4, 6승 2패 1무"(승점만 말하지 않는다 — 사용자 지시). */
    fun rankRowAccessibility(entry: ReversiRankEntry, isMe: Boolean): String {
        val parts = mutableListOf("${entry.rank}위")
        if (isMe) parts += me
        parts += entry.user.displayName
        val center = entry.user.center
        if (!center.isNullOrEmpty()) parts += "${center}센터"
        parts += points(entry.points)
        parts += record(entry.wins, entry.losses, entry.draws)
        return parts.joinToString(", ")
    }

    // 규칙 시트(맥 `ReversiRulesOverlayLines` 의 여덟 줄 + 폰이 글자로 말해야 하는 두 줄 — 툴팁이 없다).
    const val rulesTitle: String = "$title 규칙"
    const val rulesExamplesTitle: String = "그림으로 보기"

    /** 규칙 줄(순서 고정). 숫자 셋은 **로비 응답 값**(한 수 초 · 연속 자동 패 · 신청 유효 초). 9번·10번은 폰 몫이다. */
    fun rules(turnSeconds: Int, lossStreak: Int, inviteTtlSeconds: Int): List<String> = listOf(
        "흑이 먼저 둬요. 가운데 네 칸에 흑 둘·백 둘을 엇갈려 놓고 시작해요.",
        "상대 돌을 내 돌 사이에 끼우도록 두면 끼인 돌이 모두 내 색으로 뒤집혀요. 가로·세로·대각선 여러 줄이 한 번에 뒤집힐 수 있어요.",
        "하나도 못 뒤집는 칸에는 둘 수 없어요. 둘 수 있는 칸은 점으로 보여요.",
        "둘 곳이 없으면 차례가 저절로 넘어가요. 둘 곳이 있으면 넘길 수 없어요.",
        "둘 다 둘 곳이 없으면 끝나요. 돌이 많은 쪽이 이기고, 남은 빈칸은 이긴 쪽 점수에 더해요. 같으면 32 : 32 무승부예요.",
        "한 수에 ${maxOf(1, turnSeconds)}초. 넘기면 둘 수 있는 칸 가운데 하나에 저절로 놓여요. 연달아 ${maxOf(1, lossStreak)}번 저절로 놓이면 져요.",
        "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고, 무승부면 건 판돈을 돌려받아요.",
        "신청은 ${maxOf(1, inviteTtlSeconds)}초 안에 답이 없으면 사라지고, 신청만으로는 루비가 빠지지 않아요.",
        "1:1 은 앱을 나가도 차례 시간이 흘러요. 로봇과 둔 판은 루비·전적·순위에 남지 않아요.",
        "리버시와 같은 규칙이에요. 리버시를 알면 따로 배울 것이 없어요.",
    )
}
