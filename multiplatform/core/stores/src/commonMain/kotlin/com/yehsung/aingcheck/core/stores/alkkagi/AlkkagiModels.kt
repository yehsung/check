// 원본: Sources/CheckCore/AlkkagiOnlineStore.swift:20-117(화면 값 타입) · AlkkagiOnlineStoreRanking.swift(순위 값) ·
//       AlkkagiOnlineStoreWatch.swift(관전 값) · AlkkagiNoticeText.swift(문구 한 곳) · AlkkagiOnlineWire.swift:453-503(canonicalGame · shotReplayGame)
//       @ e4995a3a — Android 판 8(아이폰 1.0.18 맞추기)
package com.yehsung.aingcheck.core.stores.alkkagi

import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiVector
import com.yehsung.aingcheck.core.stores.tetris.DuelShortfallText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.AlkkagiLobbyUserWire
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchPhase
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchResult
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchWire
import com.yehsung.aingcheck.core.wire.games.AlkkagiPeer
import com.yehsung.aingcheck.core.wire.games.AlkkagiPlayerWire
import com.yehsung.aingcheck.core.wire.games.AlkkagiRPCStatus
import com.yehsung.aingcheck.core.wire.games.AlkkagiShotWire
import com.yehsung.aingcheck.core.wire.games.AlkkagiStoneWire
import com.yehsung.aingcheck.core.wire.games.AlkkagiVectorWire
import com.yehsung.aingcheck.core.wire.games.AlkkagiWatchStateWire

/** 이 기기가 지금 대결을 할 수 있는가. serverMissing = '곧 열려요'(서버 옛판 · PGRST202 · 문 닫힘). */
enum class AlkkagiAvailability { available, updateRequired, serverMissing }

enum class AlkkagiStake(val rawValue: Int) { three(3), five(5), ten(10) }

/** 판이 끝난 사유(서버 `finish_reason`). 모르는 글자는 unknown. */
enum class AlkkagiEndReason(val rawValue: String) {
    ringOut("ring_out"), timeout("timeout"), resign("resign"), abandoned("abandoned"), void("void"), unknown("unknown");

    companion object {
        fun of(raw: String): AlkkagiEndReason = entries.firstOrNull { it.rawValue == raw } ?: unknown
    }
}

enum class AlkkagiOutcome { win, loss, draw }

/** 로비 상대 한 사람. */
data class AlkkagiLobbyUser(
    val id: String,
    val displayName: String,
    val avatarURL: String? = null,
    val characterID: String? = null,
    val isWorking: Boolean = false,
    val inMatch: Boolean = false,
    /** 서버 `capable` — 상대 앱이 1:1 알까기 v2 를 안다. */
    val isCapable: Boolean = true,
    val isFocused: Boolean = false,
) {
    /** [도전] 이 설 수 있는 사람. 보낸 신청이 있어도 켜고 서버 `already_pending` 에 맡긴다. */
    val canBeChallenged: Boolean get() = isCapable && !inMatch && !isFocused

    companion object {
        fun of(w: AlkkagiLobbyUserWire) = AlkkagiLobbyUser(w.id, w.displayName, w.avatarURL, w.characterID, w.isWorking, w.inMatch, w.isCapable, w.isFocused)
    }
}

/** 내 전적(가벼운 로비는 덮지 않는다 — `record` null). */
data class AlkkagiRecord(val wins: Int, val losses: Int, val draws: Int) {
    val points: Int get() = wins - losses
}

/** 로비 "지금 대결 중" 한 판. */
data class AlkkagiLiveMatch(
    val id: String,
    val black: AlkkagiPeer,
    val white: AlkkagiPeer,
    val stake: Int? = null,
    val shotCount: Int = 0,
    val watchers: Int = 0,
    val acceptedAt: SwiftDate? = null,
)

/** 바깥(앱)에 알릴 일 — 판 시작 · 내 차례. */
data class AlkkagiAttention(val kind: Kind, val matchID: String, val opponentName: String) {
    enum class Kind { matchStarted, myTurn }
}

data class AlkkagiRankEntry(
    val rank: Int,
    val id: String,
    val displayName: String,
    val avatarURL: String? = null,
    val characterID: String? = null,
    val wins: Int = 0,
    val losses: Int = 0,
    val draws: Int = 0,
    val points: Int = wins - losses,
)

data class AlkkagiMyRank(val rank: Int?, val wins: Int = 0, val losses: Int = 0, val draws: Int = 0, val points: Int = wins - losses) {
    fun matches(record: AlkkagiRecord?): Boolean = record != null && record.wins == wins && record.losses == losses && record.draws == draws
}

data class AlkkagiRankingBoard(val entries: List<AlkkagiRankEntry>, val me: AlkkagiMyRank?, val recordSince: SwiftDate? = null)

/** 관전 판 — 와이어 값 그대로(Swift `AlkkagiWatchState` 와 칸이 같다). */
typealias AlkkagiWatchState = AlkkagiWatchStateWire

val AlkkagiWatchStateWire.isFinished: Boolean get() = phase == AlkkagiMatchPhase.finished
val AlkkagiWatchStateWire.endReason: AlkkagiEndReason? get() = finishReason?.let(AlkkagiEndReason::of)

/** 받은 · 보낸 신청 — 와이어 값 그대로(Swift `AlkkagiInvite`). */
typealias AlkkagiInvite = com.yehsung.aingcheck.core.wire.games.AlkkagiInviteWire

/** 내 판 — 와이어 값 그대로(Swift `AlkkagiMatch`). */
typealias AlkkagiMatch = AlkkagiMatchWire

// MARK: - 와이어 → 규칙(판 값)

fun AlkkagiPlayerWire.rules(): AlkkagiGame.Player = if (this == AlkkagiPlayerWire.black) AlkkagiGame.Player.black else AlkkagiGame.Player.white
fun AlkkagiGame.Player.wire(): AlkkagiPlayerWire = if (this == AlkkagiGame.Player.black) AlkkagiPlayerWire.black else AlkkagiPlayerWire.white
fun AlkkagiVectorWire.rules(): AlkkagiVector = AlkkagiVector(x, y)

/** 돌 한 알(와이어 → 규칙). id 가 Int 범위 밖이면 규칙의 restore 가 거른다(-1). */
fun AlkkagiStoneWire.rules(): AlkkagiGame.Stone = AlkkagiGame.Stone(
    if (id in 0L..Int.MAX_VALUE.toLong()) id.toInt() else -1, owner.rules(), position.rules(), velocity.rules(), isOut, isPlaced,
)

private fun Long.toIntOrMinus(): Int = if (this in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) toInt() else -1

/**
 * 서버 스냅숏 → 판 값(Swift `AlkkagiMatch.canonicalGame(serverNowMs:)`). 모양이 틀리면 null — 그 응답은 버린다.
 * 놓기(placing) 판은 내 돌 다섯만 실려 오고(남의 배치는 숨긴다) 내가 준비했으면 다 놓였어야 한다.
 */
fun AlkkagiMatchWire.canonicalGame(serverNowMs: Double? = null): AlkkagiGame? {
    if (revision < 0 || chatSeq < 0) return null
    deadlineMs?.let { if (!it.isFinite()) return null }
    val myColor = this.myColor.rules()
    val gamePhase = when (phase) {
        AlkkagiMatchPhase.placing -> {
            if (placementRevision < 1 || stones.size != 5 || !stones.all { it.owner.rules() == myColor && !it.isOut } ||
                (myReady && !stones.all { it.isPlaced }) || shot != null || result != null
            ) return null
            AlkkagiGame.Phase.placing
        }
        AlkkagiMatchPhase.aiming -> AlkkagiGame.Phase.aiming
        AlkkagiMatchPhase.rolling -> AlkkagiGame.Phase.rolling
        AlkkagiMatchPhase.finished -> AlkkagiGame.Phase.finished
        AlkkagiMatchPhase.unknown -> return null
    }
    val gameResult: AlkkagiGame.Result? = when (result) {
        AlkkagiMatchResult.black -> AlkkagiGame.Result.Winner(AlkkagiGame.Player.black)
        AlkkagiMatchResult.white -> AlkkagiGame.Result.Winner(AlkkagiGame.Player.white)
        AlkkagiMatchResult.draw -> AlkkagiGame.Result.Draw
        AlkkagiMatchResult.unknown -> return null
        null -> null
    }
    var remaining = AlkkagiGame.turnDuration
    val referenceMs = if (phase == AlkkagiMatchPhase.rolling) shot?.startedAtMs else serverNowMs
    if (referenceMs != null) {
        if (!referenceMs.isFinite()) return null
        deadlineMs?.let { remaining = maxOf(0.0, minOf(remaining, (it - referenceMs) / 1000)) }
    }
    return AlkkagiGame.restore(
        stones.map { it.rules() }, if (phase == AlkkagiMatchPhase.placing) myColor else currentPlayer.rules(), gamePhase,
        remaining, remaining, gameResult, shotCount.toIntOrMinus(),
    )
}

/** 쏜 수의 재생 판(그림 전용 — 그 시계와 결과는 서버 스냅숏을 바꾸지 않는다). */
val AlkkagiMatchWire.shotReplayGame: AlkkagiGame? get() = shot?.let { replay(it, shotCount) }

/** 관전 판의 쏜 수 재생. */
val AlkkagiWatchStateWire.shotReplayGame: AlkkagiGame? get() = shot?.let { replay(it, shotCount) }

internal fun replay(shot: AlkkagiShotWire, shotCount: Long): AlkkagiGame? {
    if (shotCount <= 0 || shot.id.isEmpty() || shot.steps < 0 || !shot.startedAtMs.isFinite()) return null
    val shooter = shot.initialStones.firstOrNull { it.id == shot.stoneID }?.owner?.rules() ?: return null
    val game = AlkkagiGame.restore(shot.initialStones.map { it.rules() }, shooter, AlkkagiGame.Phase.aiming, shotCount = (shotCount - 1).toIntOrMinus()) ?: return null
    if (!game.shoot(shot.stoneID.toIntOrMinus(), shot.pull.rules())) return null
    return game
}

// MARK: - 문구(한 곳)

/** 1:1 알까기 사용자 문구 — **코어 한 곳**(길건너 문구 꼴 · 게임 이름만 다르다). 진단 어휘 금지. */
object AlkkagiNoticeText {
    const val gameName = "1:1 알까기"
    const val tryAgain = "잠시 후 다시 시도해 주세요"
    const val checkConnection = "연결을 확인하고 다시 시도해 주세요"
    const val updateMine = "앱을 업데이트해야 대결할 수 있어요"
    const val signInAgain = "다시 로그인해 주세요"
    const val inviteTimedOut = "상대가 응답하지 않았어요"
    const val inviteDeclined = "상대가 신청을 받지 않았어요"
    const val finishedInvite = "이미 끝난 신청이에요"
    const val finishedMatch = "이미 끝난 대결이에요"
    const val busy = "이미 진행 중인 대결이 있어요"
    const val targetBusy = "상대가 다른 대결 중이에요"
    const val targetOutdated = "상대 앱이 1:1 알까기를 아직 몰라요"
    const val unavailable = "1:1 알까기는 곧 열려요"
    const val notYourTurn = "상대 차례예요"
    const val resign = "기권"
    const val confirmResign = "기권하기"
    const val keepPlaying = "계속하기"
    const val resignWarning = "기권하면 판돈을 잃어요"
    const val resignHelp = "기권하면 이번 판은 져요"
    const val chatTooLong = "대화는 100자까지 보낼 수 있어요."

    fun challenge(status: AlkkagiRPCStatus, need: Long? = null, have: Long? = null, doorOpen: Boolean? = null): String = when {
        status == AlkkagiRPCStatus.ok -> "신청을 보냈어요"
        status == AlkkagiRPCStatus.invalid -> "신청할 수 없는 상대예요"
        status == AlkkagiRPCStatus.blackout -> "지금은 조용한 기간이라 신청할 수 없어요"
        status == AlkkagiRPCStatus.targetFocused -> "상대가 집중 모드라 신청할 수 없어요"
        status == AlkkagiRPCStatus.targetOutdated -> targetOutdated
        status == AlkkagiRPCStatus.busy -> busy
        status == AlkkagiRPCStatus.targetBusy -> targetBusy
        status == AlkkagiRPCStatus.alreadyPending -> "이미 보낸 신청이 있어요"
        status == AlkkagiRPCStatus.insufficient -> DuelShortfallText.shortfallNotice(need, have)
        status == AlkkagiRPCStatus.unsupportedClient && doorOpen == false -> unavailable
        else -> common(status)
    }

    fun cancel(status: AlkkagiRPCStatus): String = when (status) {
        AlkkagiRPCStatus.ok -> "신청을 취소했어요"
        AlkkagiRPCStatus.notFound, AlkkagiRPCStatus.notPending, AlkkagiRPCStatus.expired, AlkkagiRPCStatus.stale, AlkkagiRPCStatus.forbidden -> finishedInvite
        else -> common(status)
    }

    fun respond(accept: Boolean, status: AlkkagiRPCStatus, side: String? = null, need: Long? = null, have: Long? = null, doorOpen: Boolean? = null): String? = when {
        status == AlkkagiRPCStatus.ok -> if (accept) null else "신청을 거절했어요"
        status == AlkkagiRPCStatus.notFound || status == AlkkagiRPCStatus.notPending -> finishedInvite
        status == AlkkagiRPCStatus.expired -> "신청 시간이 지났어요"
        status == AlkkagiRPCStatus.invalid || status == AlkkagiRPCStatus.forbidden -> "받을 수 없는 신청이에요"
        status == AlkkagiRPCStatus.busy -> busy
        status == AlkkagiRPCStatus.targetBusy -> targetBusy
        status == AlkkagiRPCStatus.targetOutdated -> targetOutdated
        status == AlkkagiRPCStatus.insufficient -> if (side == "challenger") "상대의 루비가 모자라요" else DuelShortfallText.shortfallNotice(need, have)
        status == AlkkagiRPCStatus.unsupportedClient && doorOpen == false -> unavailable
        else -> common(status)
    }

    fun move(status: AlkkagiRPCStatus): String? = when (status) {
        AlkkagiRPCStatus.ok, AlkkagiRPCStatus.stale -> null
        AlkkagiRPCStatus.forbidden -> notYourTurn
        AlkkagiRPCStatus.notActive, AlkkagiRPCStatus.notFound -> finishedMatch
        AlkkagiRPCStatus.rateLimited -> tryAgain
        else -> common(status)
    }

    fun resign(status: AlkkagiRPCStatus): String? = when (status) {
        AlkkagiRPCStatus.ok -> null
        AlkkagiRPCStatus.notActive, AlkkagiRPCStatus.notFound -> finishedMatch
        else -> common(status)
    }

    fun endReason(reason: AlkkagiEndReason?, outcome: AlkkagiOutcome?): String {
        reason ?: return ""
        return when (reason) {
            AlkkagiEndReason.ringOut -> when (outcome) {
                AlkkagiOutcome.win -> "상대 돌을 모두 판 밖으로 밀어냈어요"
                AlkkagiOutcome.loss -> "내 돌이 모두 판 밖으로 나갔어요"
                else -> "마지막 돌이 함께 나가 무승부예요"
            }
            AlkkagiEndReason.timeout -> if (outcome == AlkkagiOutcome.win) "상대가 차례를 세 번 넘겼어요" else "차례를 세 번 넘겨 졌어요"
            AlkkagiEndReason.resign -> if (outcome == AlkkagiOutcome.win) "상대가 기권했어요" else "기권했어요"
            AlkkagiEndReason.abandoned -> if (outcome == AlkkagiOutcome.win) "상대가 떠났어요" else "대결을 떠났어요"
            AlkkagiEndReason.void -> "판이 무효가 되어 판돈을 돌려받았어요"
            AlkkagiEndReason.unknown -> ""
        }
    }

    fun missedTurn(mine: Int, forfeitAfter: Int): String? {
        val left = forfeitAfter - mine
        if (mine < 1 || left < 1) return null
        return when (left) {
            1 -> "시간이 지나 차례가 넘어갔어요 · 한 번 더 넘기면 져요"
            2 -> "시간이 지나 차례가 넘어갔어요 · 두 번 더 넘기면 져요"
            else -> "시간이 지나 차례가 넘어갔어요 · ${left}번 더 넘기면 져요"
        }
    }

    fun common(status: AlkkagiRPCStatus): String = when (status) {
        AlkkagiRPCStatus.unsupportedClient -> updateMine
        AlkkagiRPCStatus.notSignedIn -> signInAgain
        else -> tryAgain
    }
}
