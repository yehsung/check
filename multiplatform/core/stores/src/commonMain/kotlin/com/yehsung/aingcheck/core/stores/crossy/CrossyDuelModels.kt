// 원본: Sources/CheckCore/CrossyDuelStore.swift:20-220(화면 값 타입) · CrossyDuelStoreRanking.swift:7-55(순위 값) ·
//       CrossyDuelNoticeText.swift(문구 한 곳) @ e4995a3a — Android 판 8(아이폰 1.0.18 맞추기)
package com.yehsung.aingcheck.core.stores.crossy

import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.stores.tetris.DuelShortfallText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.CrossyDuelRPCStatus

/** 네트워크·세션·루비 미러를 빌리는 곳 — 오목·체스·리버시와 같은 문(Swift `typealias CrossyDuelStoreHost = GomokuStoreHost`). */
typealias CrossyDuelStoreHost = GomokuStoreHost

/** 화면 흐름. **신청(보냄·받음)은 phase 가 아니라** lobby 위의 outgoing·incoming 이다. */
enum class CrossyDuelPhase { lobby, ready, countdown, playing, finished }

/** 흐름과 따로 서는 상태 — 이 기기가 지금 대결을 할 수 있는가. */
enum class CrossyDuelAvailability { available, updateRequired, serverMissing }

enum class CrossyDuelStake(val rawValue: Int) { three(3), five(5), ten(10) }

/** 판이 끝난 사유(서버 `end_reason` 글자). 모르는 글자는 unknown. */
enum class CrossyDuelEndReason(val rawValue: String) {
    goal("goal"), timeCap("time_cap"), resign("resign"), disconnect("disconnect"), noShow("no_show"), abandoned("abandoned"),
    void("void"), unknown("unknown");

    companion object {
        fun of(raw: String): CrossyDuelEndReason = entries.firstOrNull { it.rawValue == raw } ?: unknown
    }
}

/** **내 기준** 결과. */
enum class CrossyDuelOutcome { win, loss, draw }

/** 로비 상대 한 사람. */
data class CrossyDuelUser(
    val id: String,
    val displayName: String,
    val avatarURL: String? = null,
    val characterID: String? = null,
    val isWorking: Boolean = false,
    /** 서버 `capable` — 상대 앱이 1:1 길건너를 안다. null 은 불가로 읽는다. */
    val isCapable: Boolean = true,
    val inMatch: Boolean = false,
    val isFocused: Boolean = false,
) {
    val canBeChallenged: Boolean get() = isCapable && !inMatch && !isFocused
}

/** 내 전적(가벼운 로비는 덮지 않는다 — v1.1 CS-4). */
data class CrossyDuelRecord(val wins: Int, val losses: Int, val draws: Int)

/** 신청 한 건(받은 것 · 보낸 것 같은 모양). [expiresAt] = 기기 시계로 보정한 만료 시각. */
data class CrossyDuelInvite(val id: String, val peer: CrossyDuelUser, val stake: Int, val expiresAt: SwiftDate)

/** 바깥(앱)에 알릴 일 — 지금은 판 시작 하나. */
data class CrossyDuelAttention(val kind: Kind, val matchID: String, val opponentName: String) {
    enum class Kind { matchStarted }
}

/** 내 판 상태(서버 응답으로만 바뀐다). 시각은 기기 시계로 보정한 [SwiftDate]. */
data class CrossyDuelMatchState(
    val id: String,
    val stake: Int,
    val seed: Long? = null,
    val opponent: CrossyDuelUser,
    val acceptedAt: SwiftDate? = null,
    val readyDeadline: SwiftDate? = null,
    val startAt: SwiftDate? = null,
    val endAt: SwiftDate? = null,
    val graceEndAt: SwiftDate? = null,
    val meReady: Boolean = false,
    val opponentReady: Boolean = false,
    /** 서버가 아는 내 점수(내 막대는 로컬 엔진 점수 — 이 값은 재개 기준). */
    val myServerScore: Int = 0,
    val opponentScore: Int = 0,
    val opponentDeaths: Int = 0,
    val opponentLastSeenAt: SwiftDate? = null,
    /** 잘라 둔 보고 간격(ms — [1000, 5000]). */
    val reportMs: Int = 2000,
    /** 잘라 둔 하트비트 간격(ms — [reportMs, 5000]). */
    val heartbeatMs: Int = 3000,
    val isFinished: Boolean = false,
    val outcome: CrossyDuelOutcome? = null,
    val endReason: CrossyDuelEndReason? = null,
    /** 끝난 판의 굳은 점수(내 관점). */
    val finalMyScore: Int? = null,
    val finalOpponentScore: Int? = null,
    /** 내 루비 증감(이기면 `DuelFee.winnerNet`). */
    val rubyDelta: Int? = null,
    val finishedAt: SwiftDate? = null,
)

/** 화면이 프레임마다 읽는 값 하나([CrossyDuelStore.raceSnapshot]). */
data class CrossyDuelRaceSnapshot(
    val myScore: Int,
    val opponentScore: Int,
    val goal: Int,
    val myDeaths: Int,
    val opponentDeaths: Int,
    /** 카운트다운 남은 초(카운트다운이 아니면 null). */
    val countdown: Double? = null,
    /** 판 남은 초(시작 전이면 null). */
    val remaining: Double? = null,
    /** 부활까지 남은 초(죽어 있지 않으면 null). */
    val respawnIn: Double? = null,
    val shielded: Boolean = false,
    /** 3분 얼림 · 100 도달 · 끝난 판 — 입력이 먹지 않는다. */
    val frozen: Boolean = false,
    /** 얼었고 서버 결과를 기다린다. */
    val waitingForResult: Boolean = false,
    /** 상대 last_seen 이 8초 넘음(프레임이 켜져 있으면 프레임 수신 시각과 max). */
    val opponentQuiet: Boolean = false,
)

// MARK: - 순위

/** 순위표 한 줄. 순위는 **서버가 매긴 값**이다. */
data class CrossyDuelRankEntry(
    val id: String,
    val rank: Int,
    val user: CrossyDuelUser,
    val wins: Int,
    val losses: Int,
    val draws: Int,
    /** 승점 = 승 − 패(서버 값). */
    val points: Int,
)

/** 내 순위(0판이면 rank null). */
data class CrossyDuelMyRank(val rank: Int?, val wins: Int, val losses: Int, val draws: Int, val points: Int)

/** 순위표 한 벌. */
data class CrossyDuelRankingBoard(val entries: List<CrossyDuelRankEntry>, val me: CrossyDuelMyRank?, val recordSince: SwiftDate?)

// MARK: - 문구(한 곳)

/** 1:1 길건너 사용자 문구 — **코어 한 곳**. 공용 status 줄은 테트리스 글자 그대로이고 게임 이름만 바꿨다. 진단 어휘 금지. */
object CrossyDuelNoticeText {
    const val gameName = "1:1 길건너"

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
    const val targetOutdated = "상대 앱이 1:1 길건너를 아직 몰라요"
    const val unavailable = "1:1 길건너는 곧 열려요"
    const val otherDevice = "다른 기기에서 대결 중이에요"

    /** 신청 결과. 근무 조건은 없다 — 클라가 근무를 보고 미리 막는 선게이트를 만들지 마라. */
    fun challenge(status: CrossyDuelRPCStatus, need: Long? = null, have: Long? = null): String = when (status) {
        CrossyDuelRPCStatus.ok -> "신청을 보냈어요"
        CrossyDuelRPCStatus.invalid -> "신청할 수 없는 상대예요"
        CrossyDuelRPCStatus.blackout -> "지금은 조용한 기간이라 신청할 수 없어요"
        CrossyDuelRPCStatus.targetFocused -> "상대가 집중 모드라 신청할 수 없어요"
        CrossyDuelRPCStatus.targetOutdated -> targetOutdated
        CrossyDuelRPCStatus.busy -> busy
        CrossyDuelRPCStatus.targetBusy -> targetBusy
        CrossyDuelRPCStatus.alreadyPending -> "이미 보낸 신청이 있어요"
        CrossyDuelRPCStatus.insufficient -> DuelShortfallText.shortfallNotice(need, have)
        else -> common(status)
    }

    fun cancel(status: CrossyDuelRPCStatus): String = when (status) {
        CrossyDuelRPCStatus.ok -> "신청을 취소했어요"
        CrossyDuelRPCStatus.notFound, CrossyDuelRPCStatus.notPending, CrossyDuelRPCStatus.expired -> finishedInvite
        else -> common(status)
    }

    /** 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(null). */
    fun respond(accept: Boolean, status: CrossyDuelRPCStatus, side: String? = null, need: Long? = null, have: Long? = null): String? = when (status) {
        CrossyDuelRPCStatus.ok -> if (accept) null else "신청을 거절했어요"
        CrossyDuelRPCStatus.notFound, CrossyDuelRPCStatus.notPending -> finishedInvite
        CrossyDuelRPCStatus.expired -> "신청 시간이 지났어요"
        CrossyDuelRPCStatus.invalid -> "받을 수 없는 신청이에요"
        CrossyDuelRPCStatus.busy -> busy
        CrossyDuelRPCStatus.targetBusy -> targetBusy
        CrossyDuelRPCStatus.insufficient -> if (side == "challenger") "상대의 루비가 모자라요" else DuelShortfallText.shortfallNotice(need, have)
        else -> common(status)
    }

    /** 기권 결과. 성공은 결과 화면이 말한다(null). */
    fun resign(status: CrossyDuelRPCStatus): String? = when (status) {
        CrossyDuelRPCStatus.ok -> null
        CrossyDuelRPCStatus.notActive, CrossyDuelRPCStatus.notFound -> finishedMatch
        CrossyDuelRPCStatus.otherDevice -> otherDevice
        else -> common(status)
    }

    /** 결과 카드의 사유 한 줄(**내 기준**). 사유를 모르면 빈 문자열. */
    fun endReason(reason: CrossyDuelEndReason?, outcome: CrossyDuelOutcome?, meReady: Boolean? = null, opponentReady: Boolean? = null): String {
        reason ?: return ""
        return when (reason) {
            CrossyDuelEndReason.goal -> when (outcome) {
                CrossyDuelOutcome.win -> "먼저 100점에 닿았어요"
                CrossyDuelOutcome.loss -> "상대가 먼저 100점에 닿았어요"
                else -> "동시에 100점 — 비겼어요"
            }
            CrossyDuelEndReason.timeCap -> when (outcome) {
                CrossyDuelOutcome.win -> "3분 끝 — 점수가 더 높아요"
                CrossyDuelOutcome.loss -> "3분 끝 — 상대 점수가 더 높아요"
                else -> "3분 끝 — 점수가 같아 비겼어요"
            }
            CrossyDuelEndReason.resign -> if (outcome == CrossyDuelOutcome.win) "상대가 기권했어요" else "기권했어요"
            CrossyDuelEndReason.disconnect -> when (outcome) {
                CrossyDuelOutcome.win -> "상대 연결이 끊겼어요"
                CrossyDuelOutcome.loss -> "연결이 끊겨 이번 판은 졌어요"
                else -> "둘 다 연결이 끊겨 비겼어요"
            }
            CrossyDuelEndReason.noShow -> {
                val me = meReady ?: false
                val them = opponentReady ?: false
                when {
                    me && !them -> "상대가 준비하지 않아 판돈을 돌려받았어요"
                    !me && them -> "준비하지 않아 판이 열리지 않았어요 · 판돈은 돌려받았어요"
                    else -> "둘 다 준비하지 않아 판돈을 돌려받았어요"
                }
            }
            CrossyDuelEndReason.abandoned -> if (outcome == CrossyDuelOutcome.win) "상대가 떠났어요" else "대결을 떠났어요"
            CrossyDuelEndReason.void -> "판이 무효가 되어 판돈을 돌려받았어요"
            CrossyDuelEndReason.unknown -> ""
        }
    }

    fun common(status: CrossyDuelRPCStatus): String = when (status) {
        CrossyDuelRPCStatus.unsupportedClient -> updateMine
        CrossyDuelRPCStatus.notSignedIn -> signInAgain
        else -> tryAgain
    }
}
