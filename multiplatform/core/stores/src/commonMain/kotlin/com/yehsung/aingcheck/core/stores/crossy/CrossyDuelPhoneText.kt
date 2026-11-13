// 원본: Sources/CheckMobileKit/Games/GamesCrossyDuelText.swift @ 928d5562(폰 1.0.18 — 1:1 길건너 폰 문구 · 겹 고르기) — Android 판 8
//
// 맥 0.3.78 `CrossyDuelText` 와 같은 글자다 — 폰에서 다른 것은 조작 안내뿐이다(키 대신 쓸기 · 탭).
// 판정 · 끝난 까닭 문구는 코어 [CrossyDuelNoticeText] 한 곳에서 받는다.
package com.yehsung.aingcheck.core.stores.crossy

import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.stores.tetris.DuelShortfallText
import kotlin.math.ceil
import kotlin.math.max

object CrossyDuelPhoneText {
    val title: String = CrossyDuelNoticeText.gameName
    const val cardSubtitle = "100점에 먼저 닿으면 이겨요"
    const val cardOpenHint = "1:1 길건너 로비를 열어요"
    const val lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    const val usersTitle = "상대 고르기"
    const val emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    const val loadingUsers = "상대 목록을 불러오고 있어요"
    val usersLoadFailed: String = CrossyDuelNoticeText.checkConnection
    const val reloadUsers = "다시 시도"
    const val challenge = "신청"
    const val needsUpdate = "앱 업데이트 필요"
    const val inMatch = "대결 중"
    const val working = "근무 중"
    const val focused = "집중 모드"
    const val available = "대결할 수 있어요"
    const val stakeTitle = "판돈"
    fun stakeLine(stake: Int): String = "$stake · 이기면 +${DuelFee.winnerNet(stake)}"
    fun stakeGainSuffix(stake: Int): String = " · 이기면 +${DuelFee.winnerNet(stake)}"
    fun stakePromptTitle(name: String): String = "${name}님에게 신청"
    const val stakePromptCaption = "판돈을 고르세요"
    fun challengeWithStake(stake: Int): String = "$stake 걸고 신청하기"
    val stakeShortfall: String = DuelShortfallText.shortfallNotice(null, null)
    const val incomingTitle = "받은 신청"
    fun incomingFrom(name: String): String = "${name}님의 신청"
    const val outgoingTitle = "보낸 신청"
    fun outgoingTo(name: String): String = "${name}님에게 보낸 신청"
    const val accept = "수락"
    const val decline = "거절"
    const val cancel = "취소"
    const val recordTitle = "내 전적"
    const val howTitle = "이렇게 겨뤄요"
    val howLines: List<String> = listOf(
        "두 사람이 같은 길을 달려요",
        "죽으면 3초 뒤 그 줄에서 다시 서요",
        "3분이 지나면 점수가 높은 쪽이 이겨요",
    )
    const val rankTitle = "순위"
    const val rankLoading = "순위를 불러오고 있어요"
    const val rankEmpty = "아직 순위가 없어요"
    const val rankHelp = "승점 = 승 − 패"
    fun record(record: CrossyDuelRecord?): String = record?.let { "${it.wins}승 ${it.losses}패 ${it.draws}무" } ?: "—"
    fun points(value: Int): String = "승점 ${if (value >= 0) "+" else ""}$value"
    fun remaining(seconds: Int): String = "${max(0, seconds)}초 남음"

    // 판
    const val me = "나"
    const val opponentTitle = "상대"
    fun deathsLine(me: Int, opponent: Int): String = "죽은 횟수 나 $me · 상대 $opponent"
    fun goalLine(goal: Int): String = "${goal}점 먼저"
    const val waitingTitle = "상대를 기다리는 중"
    fun waitingSubtitle(seconds: Int): String = "${seconds}초 안에 둘 다 들어오면 시작해요"
    const val otherDeviceSubtitle = "신청하거나 수락한 기기에서만 할 수 있어요"
    /** 폰 조작 안내 — 혼자 하는 길건너와 같은 손짓이다. */
    const val touchLine = "쓸어서 그 방향으로 한 칸 · 탭하면 앞으로 한 칸"
    const val goalWaiting = "100점! 판정 기다리는 중"
    const val timeWaiting = "시간 끝! 판정 기다리는 중"
    const val opponentQuiet = "상대 연결 확인 중"
    const val resign = "기권"
    const val confirmResign = "기권하기"
    const val keepPlaying = "계속하기"
    const val resignWarning = "기권하면 판돈을 잃어요"
    const val backToLobby = "로비로"
    const val forwardAction = "앞으로"
    fun outcomeTitle(outcome: CrossyDuelOutcome?): String = when (outcome) {
        CrossyDuelOutcome.win -> "이겼어요"
        CrossyDuelOutcome.loss -> "졌어요"
        CrossyDuelOutcome.draw -> "비겼어요"
        null -> "대결이 끝났어요"
    }
    fun finalScoreLine(me: Int, opponent: Int): String = "나 $me : 상대 $opponent"
    fun rubyLine(delta: Int): String = if (delta > 0) "+$delta" else if (delta < 0) "$delta" else "±0"

    /** "m:ss"(올림 — Swift `rounded(.up)`). */
    fun clock(seconds: Double): String {
        val total = max(0, ceil(seconds).toInt())
        return "${total / 60}:${(total % 60).toString().padStart(2, '0')}"
    }

    fun countdownDigit(seconds: Double): String = max(1, ceil(seconds).toInt()).toString()

    /** 결과 루비 변화 — 서버 값이 있으면 그것, 없으면 판돈 규칙. */
    fun rubyDelta(match: CrossyDuelMatchState): Int {
        match.rubyDelta?.let { return it }
        return when (match.outcome) {
            CrossyDuelOutcome.win -> DuelFee.winnerNet(match.stake)
            CrossyDuelOutcome.loss -> -match.stake
            else -> 0
        }
    }

    /** 로비 상대 줄의 아래 줄 · 신청 가능 여부. */
    data class UserStatus(val subtitle: String, val canChallenge: Boolean)

    fun userStatus(user: CrossyDuelUser): UserStatus = when {
        !user.isCapable -> UserStatus(needsUpdate, false)
        user.inMatch -> UserStatus(inMatch, false)
        user.isFocused -> UserStatus(focused, false)
        else -> UserStatus(if (user.isWorking) working else available, true)
    }
}

/** 캔버스 위 겹 하나(우선순위: 결과 > 판정 기다림 > 부활 카운트 > 시작 카운트다운). */
sealed interface CrossyDuelPhoneOverlay {
    data class Result(val outcome: CrossyDuelOutcome?) : CrossyDuelPhoneOverlay
    data class Waiting(val goal: Boolean) : CrossyDuelPhoneOverlay
    data class Respawn(val digit: String) : CrossyDuelPhoneOverlay
    data class Countdown(val digit: String) : CrossyDuelPhoneOverlay

    companion object {
        fun resolve(phase: CrossyDuelPhase, isFinished: Boolean, outcome: CrossyDuelOutcome?, snapshot: CrossyDuelRaceSnapshot?): CrossyDuelPhoneOverlay? {
            if (isFinished || phase == CrossyDuelPhase.finished) return Result(outcome)
            if (snapshot == null || !(phase == CrossyDuelPhase.countdown || phase == CrossyDuelPhase.playing)) return null
            val reachedGoal = snapshot.myScore >= snapshot.goal
            val timeUp = phase == CrossyDuelPhase.playing && (snapshot.remaining?.let { it <= 0 } ?: false)
            if (snapshot.waitingForResult || snapshot.frozen || reachedGoal || timeUp) return Waiting(reachedGoal)
            snapshot.respawnIn?.let { if (it > 0) return Respawn(CrossyDuelPhoneText.countdownDigit(it)) }
            snapshot.countdown?.let { if (it > 0) return Countdown(CrossyDuelPhoneText.countdownDigit(it)) }
            return null
        }
    }
}
