// 원본: Sources/CheckMobileKit/Games/GamesAlkkagiText.swift @ 928d5562(폰 1.0.18 — 1:1 알까기 폰 문구) — Android 판 8
//
// 맥 0.3.82 `AlkkagiText` 와 같은 글자다 — 폰에서 다른 것은 손짓 안내뿐이다(끌기 · 놓기). 게임 이름 · 판정 · 끝난 까닭 문구는
// 코어 [AlkkagiNoticeText] 한 곳. 낱말은 '대결' · '신청'(대전 · 초대 금지). 루비는 글자로 "루비 N", 그림은 루비 아이콘.
package com.yehsung.aingcheck.core.stores.alkkagi

import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.stores.tetris.DuelShortfallText
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchPhase
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchResult
import com.yehsung.aingcheck.core.wire.games.AlkkagiStoneWire
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

object AlkkagiPhoneText {
    val title: String = AlkkagiNoticeText.gameName
    const val entrySymbol = "circle.hexagongrid.fill"
    const val cardSubtitle = "숨겨 놓기 30초 · 흑 선공 · 한 수 30초"
    const val cardOpenHint = "1:1 알까기 로비를 열어요"

    const val lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    const val usersTitle = "상대 고르기"
    const val emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    const val loadingUsers = "상대 목록을 불러오고 있어요"
    val usersLoadFailed: String = AlkkagiNoticeText.checkConnection
    const val reloadUsers = "다시 시도"
    const val challenge = "도전"
    const val needsUpdate = "앱 업데이트 필요"
    const val inMatch = "대결 중"
    const val working = "근무 중"
    const val focused = "집중 모드"
    const val available = "대결할 수 있어요"
    val unavailable: String = AlkkagiNoticeText.unavailable
    const val stakeTitle = "판돈"
    fun stakeLine(stake: Int): String = "$stake · 이기면 +${DuelFee.winnerNet(stake)}"
    fun stakeGainSuffix(stake: Int): String = " · 이기면 +${DuelFee.winnerNet(stake)}"
    fun stakePromptTitle(name: String): String = "${name}님에게 신청"
    const val stakePromptCaption = "판돈을 고르세요"
    fun challengeWithStake(stake: Int): String = "$stake 걸고 도전하기"
    val stakeShortfall: String = DuelShortfallText.shortfallNotice(null, null)
    const val incomingTitle = "받은 신청"
    fun incomingFrom(name: String): String = "${displayName(name)}님의 신청"
    const val outgoingTitle = "보낸 신청"
    fun outgoingTo(name: String): String = "${displayName(name)}님에게 보낸 신청"
    const val accept = "수락"
    const val decline = "거절"
    const val cancel = "취소"
    fun remaining(seconds: Int): String = "${max(0, seconds)}초 남음"
    const val recordTitle = "내 전적"
    const val liveTitle = "지금 대결 중"
    const val noLive = "지금 진행 중인 대결이 없어요"
    const val watch = "관전"
    const val leaveWatch = "나가기"
    fun liveLine(match: AlkkagiLiveMatch): String = "${displayName(match.black.displayName)} vs ${displayName(match.white.displayName)}"
    fun liveDetail(match: AlkkagiLiveMatch): String {
        val parts = mutableListOf<String>()
        match.stake?.let { parts += "$stakeTitle $it" }
        parts += "${match.shotCount}수"
        if (match.watchers > 0) parts += "${match.watchers}명 관전"
        return parts.joinToString(" · ")
    }
    const val rankTitle = "알까기 순위"
    const val rankHelp = "승점 = 승 − 패"
    const val rankLoading = "순위를 불러오고 있어요"
    const val rankEmpty = "아직 순위가 없어요"
    const val rankSoon = "순위는 곧 열려요"
    fun record(record: AlkkagiRecord?): String = record?.let { "${it.wins}승 ${it.losses}패 ${it.draws}무" } ?: "0승 0패 0무"
    fun points(value: Int): String = "승점 ${if (value >= 0) "+" else ""}$value"

    const val practiceButton = "연습하기"
    const val practiceHelp = "루비·전적 없이 한 폰에서 둘이 번갈아 연습해요"
    const val practiceTitle = "알까기 연습"
    const val practiceSubtitle = "연습 판 · 루비·전적에 남지 않아요"
    const val practiceRestart = "새 판"

    const val rulesTitle = "이렇게 겨뤄요"
    val rulesLines: List<String> = listOf(
        "돌 다섯 개를 내 쪽에 숨겨 놓아요 — 30초, 둘 다 놓으면 함께 보여요",
        "흑이 먼저 쏴요 — 흑백은 수락할 때 정해져요",
        "내 돌을 당겼다 놓으면 반대쪽으로 날아가요 — 한 수 30초",
        "판 밖으로 나간 돌은 빠져요 — 상대 돌을 모두 밀어내면 이겨요(마지막 돌이 함께 나가면 무승부)",
        "차례를 세 번 연달아 넘기면 져요 · 이기면 판돈만큼 더 받아요",
    )

    const val myTurn = "내 차례예요"
    fun opponentTurn(name: String): String = "${displayName(name)}님 차례예요"
    const val waitBusy = "잠시만 기다려 주세요"
    const val rolling = "돌이 멈추면 차례가 바뀌어요"
    const val placingHelpOnline = "30초 동안 동시에 숨겨 놓아요. 둘 다 준비하거나 시간이 끝날 때까지 상대 돌은 보이지 않아요."
    const val placingHelpPractice = "내 영역에 돌 5개를 놓거나 옮겨 주세요. 시간이 끝나면 남은 돌은 자동으로 놓여요."
    const val placingReadyWaiting = "준비 완료 · 상대를 기다리고 있어요"
    fun placingMine(player: AlkkagiGame.Player): String = "${stoneTitle(player)} 숨겨 놓는 중 · 내 영역을 눌러 주세요"
    fun placingPractice(player: AlkkagiGame.Player): String = "${stoneTitle(player)} 놓는 중 · 내 영역을 눌러 놓아요"
    fun aimHint(player: AlkkagiGame.Player): String = "${stoneTitle(player)} 차례 — 내 돌을 눌러 뒤로 당겨 보세요"
    const val aimRelease = "놓으면 날아가요 · 돌 위로 되돌리면 취소"
    const val firstShotHint = "첫 수는 힘이 60%까지예요 — 돌을 뒤로 당겨 보세요"
    const val firstShotRelease = "첫 수는 힘 60%까지 · 놓으면 날아가요 · 돌 위로 되돌리면 취소"
    const val placementInvalid = "내 영역 안에서 돌이 겹치지 않게 놓아 주세요"
    fun placementDone(placed: Int): String = "배치 완료 ($placed/5)"
    const val readyDone = "준비 완료"
    fun power(value: Double): String = "힘 ${floor(min(1.0, max(0.0, value)) * 100).toInt()}%"
    fun stonesLeft(count: Int): String = "돌 ${count}개"
    fun shots(count: Int): String = "${count}수"
    fun missedLine(missed: Int, forfeitAfter: Int): String = "넘긴 차례 $missed/$forfeitAfter"
    val resign: String = AlkkagiNoticeText.resign
    val confirmResign: String = AlkkagiNoticeText.confirmResign
    val keepPlaying: String = AlkkagiNoticeText.keepPlaying
    fun resignWarning(stake: Int?): String = if (stake == null) AlkkagiNoticeText.resignHelp else AlkkagiNoticeText.resignWarning
    const val backToLobby = "로비로"
    const val leaveKeepsMatch = "화면을 나가도 대결은 계속돼요"
    fun outcomeTitle(outcome: AlkkagiOutcome?): String = when (outcome) {
        AlkkagiOutcome.win -> "이겼어요"
        AlkkagiOutcome.loss -> "졌어요"
        AlkkagiOutcome.draw -> "무승부예요"
        null -> "대결이 끝났어요"
    }
    /** 승 +N · 패 −N · 무 "0 · 판돈을 돌려받았어요". */
    fun rubyLine(delta: Int): String = if (delta > 0) "+$delta" else if (delta < 0) "−${-delta}" else "0 · 판돈을 돌려받았어요"
    fun practiceResult(result: AlkkagiGame.Result?): String = when (result) {
        is AlkkagiGame.Result.Winner -> "${stoneTitle(result.player)} 승리!"
        AlkkagiGame.Result.Draw -> "멋진 한 판, 무승부!"
        null -> "한 판 끝!"
    }

    const val watchLoading = "판을 불러오고 있어요"
    const val watchPlacing = "두 사람이 돌을 숨겨 놓는 중이에요"
    const val watchRolling = "돌이 멈추면 차례가 바뀌어요"
    fun stoneName(player: AlkkagiGame.Player): String = if (player == AlkkagiGame.Player.black) "흑" else "백"
    fun stoneTitle(player: AlkkagiGame.Player): String = if (player == AlkkagiGame.Player.black) "흑돌" else "백돌"
    fun watchTurn(player: AlkkagiGame.Player): String = "${stoneName(player)} 차례"
    fun watchOutcome(result: AlkkagiMatchResult?): String = when (result) {
        AlkkagiMatchResult.black -> "흑 승리"
        AlkkagiMatchResult.white -> "백 승리"
        AlkkagiMatchResult.draw -> "무승부로 끝났어요"
        else -> "대결이 끝났어요"
    }
    fun watchEndReason(reason: AlkkagiEndReason?, result: AlkkagiMatchResult?): String {
        val loser = when (result) {
            AlkkagiMatchResult.black -> "백"
            AlkkagiMatchResult.white -> "흑"
            else -> null
        }
        return when (reason) {
            AlkkagiEndReason.ringOut -> loser?.let { "$it 돌이 모두 판 밖으로 나갔어요" } ?: "마지막 돌이 함께 나가 무승부예요"
            AlkkagiEndReason.timeout -> loser?.let { "${it}이 차례를 세 번 넘겼어요" } ?: ""
            AlkkagiEndReason.resign -> loser?.let { "${it}이 기권했어요" } ?: ""
            AlkkagiEndReason.abandoned -> loser?.let { "${it}이 대결을 떠났어요" } ?: ""
            AlkkagiEndReason.void -> "판이 무효가 되어 판돈을 돌려줬어요"
            else -> ""
        }
    }
    fun watchHeadline(watch: AlkkagiWatchState): String = when (watch.phase) {
        AlkkagiMatchPhase.placing -> watchPlacing
        AlkkagiMatchPhase.rolling -> watchRolling
        AlkkagiMatchPhase.aiming -> watchTurn(watch.currentPlayer.rules())
        AlkkagiMatchPhase.finished -> watchOutcome(watch.result)
        AlkkagiMatchPhase.unknown -> watchLoading
    }
    /** 판 위에 남은 돌 수(나간 돌만 뺀다 — 숨긴 배치 중에도 다섯). */
    fun remaining(stones: List<AlkkagiStoneWire>, player: AlkkagiGame.Player): Int =
        max(0, 5 - stones.count { it.owner.rules() == player && it.isOut })

    const val someone = "누군가"
    fun displayName(name: String?): String = (name ?: "").trim().ifEmpty { someone }

    data class UserStatus(val subtitle: String, val canChallenge: Boolean)

    fun userStatus(user: AlkkagiLobbyUser): UserStatus = when {
        !user.isCapable -> UserStatus(needsUpdate, false)
        user.inMatch -> UserStatus(inMatch, false)
        user.isFocused -> UserStatus(focused, false)
        else -> UserStatus(if (user.isWorking) working else available, true)
    }
}
