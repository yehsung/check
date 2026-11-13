// 원본: Sources/CheckCore/MahjongNoticeText.swift @ e4995a3a(아잉 마작 안내 문구 표 — 사용자 어휘 유일 출처) — Android 판 8
//
// 진단 어휘(서버 · 상태 · 동기화 · seq · 프로토콜)는 쓰지 않는다 — 사용자가 할 수 있는 일을 말한다.
package com.yehsung.aingcheck.core.stores.mahjong

import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.mahjong.MahjongYaku

object MahjongNoticeText {
    /** 어느 동작의 응답인가(같은 status 라도 동작마다 말이 다른 자리). */
    enum class Action { lobby, create, invite, join, decline, leave, start, state, act, call, back, react, ranking }

    /** 게임 이름(카드 ① 답 "아잉 마작"). */
    const val gameName = "아잉 마작"

    const val tryAgain = "잠시 후 다시 시도해 주세요"
    const val checkConnection = "연결을 확인하고 다시 시도해 주세요"
    const val updateRequired = "앱을 업데이트해 주세요"
    const val signInAgain = "다시 로그인해 주세요"
    const val unavailable = "${gameName}은 곧 열려요"
    const val invited = "초대를 보냈어요"
    const val roomClosed = "방이 닫혔어요"
    const val turnPassed = "차례가 이미 넘어갔어요"
    const val finishedMatch = "이미 끝난 판이에요"
    const val notAnOption = "지금은 낼 수 없는 패예요"

    const val timeoutDiscarded = "시간이 지나 방금 뽑은 패를 버렸어요"
    const val timeoutPassed = "시간이 지나 넘겼어요"

    const val away = "자리 비움 — 차례가 오면 저절로 버려요 · 손패를 누르면 돌아와요"
    const val backTooFast = "잠시 뒤에 다시 눌러 주세요"

    const val droppedAtStart = "판이 시작될 때 방에서 빠졌어요"
    const val fourGathered = "4명이 모였어요"

    const val practiceClosed = "루비 판이 시작돼 연습판을 닫았어요"
    const val practiceIdleCallHint = "[넘기기]를 누르면 계속돼요"
    const val practiceMe = "나"
    fun practiceBotName(number: Int): String = "로봇 $number"

    const val myTurnAttention = "$gameName — 내 차례예요"
    const val matchStartedAttention = "$gameName 판이 시작됐어요"
    const val awayAttention = "$gameName — 자리 비움이 됐어요 · 차례가 오면 저절로 버려요"
    const val closedWhilePlaying = "창을 닫아도 판은 계속돼요 — 차례가 오면 자동으로 처리돼요"

    /** 모르는 역 id(규칙 2판의 새 역). */
    const val newYaku = "새 역"

    fun yakuName(id: String): String = MahjongYaku.of(id)?.koreanName ?: newYaku

    fun attention(attention: MahjongAttention): String = when (attention.kind) {
        MahjongAttention.Kind.matchStarted -> matchStartedAttention
        MahjongAttention.Kind.myTurn -> myTurnAttention
        MahjongAttention.Kind.away -> awayAttention
        MahjongAttention.Kind.closedWhilePlaying -> closedWhilePlaying
    }

    /** 방장 화면 — `seats_dropped{reasons}` 원문 값들 → 한 줄. */
    fun droppedOthers(reasons: List<String>): String {
        val kinds = reasons.toSet()
        if (kinds == setOf("insufficient")) return "루비가 모자란 사람이 빠졌어요"
        if (kinds == setOf("unseen")) return "자리를 비운 사람이 빠졌어요"
        if (kinds == setOf("outdated")) return "앱 업데이트가 필요한 사람이 빠졌어요"
        if ("outdated" in kinds) return "방에서 빠진 사람이 있어요"
        return "자리를 비웠거나 루비가 모자란 사람이 빠졌어요"
    }

    /** RPC 거절 한 줄. null = 말하지 않는다(성공 · stale(결정 동작) · window_closed · too_early · 반응 쿨다운). */
    fun status(status: MahjongRPCStatus, action: Action, need: Int? = null, have: Int? = null): String? = when (status) {
        MahjongRPCStatus.ok -> null
        MahjongRPCStatus.busy -> "이미 다른 게임 중이에요"
        MahjongRPCStatus.targetBusy -> "상대가 다른 게임 중이에요"
        MahjongRPCStatus.targetOutdated -> "상대 앱이 ${gameName}을 아직 몰라요"
        MahjongRPCStatus.targetFocused -> "상대가 집중 모드예요"
        MahjongRPCStatus.insufficient -> SharedText.shortfallNotice(need?.toLong(), have?.toLong())
        MahjongRPCStatus.roomFull -> "방이 가득 찼어요"
        MahjongRPCStatus.roomClosed -> roomClosed
        MahjongRPCStatus.notEnoughPlayers -> "4명이 모여야 시작할 수 있어요"
        MahjongRPCStatus.seatsDropped -> droppedOthers(emptyList())
        MahjongRPCStatus.unsupportedClient -> updateRequired
        MahjongRPCStatus.outdated -> updateRequired
        MahjongRPCStatus.unauthorized -> signInAgain
        MahjongRPCStatus.alreadyInRoom -> "이미 들어가 있는 방이 있어요"
        MahjongRPCStatus.notHost -> "방장만 할 수 있어요"
        MahjongRPCStatus.blackout -> "지금은 조용한 기간이라 초대할 수 없어요"
        MahjongRPCStatus.tooManyInvites -> "한 번에 6명까지 초대할 수 있어요"
        MahjongRPCStatus.alreadyInvited -> "이미 초대한 사람이에요"
        MahjongRPCStatus.notInvited -> "초대받지 않은 방이에요"
        MahjongRPCStatus.notFound -> when (action) {
            Action.act, Action.call, Action.back, Action.react, Action.state -> finishedMatch
            else -> roomClosed
        }
        MahjongRPCStatus.notYourTurn -> turnPassed
        MahjongRPCStatus.stale -> when (action) {
            Action.act, Action.call, Action.back -> null
            else -> tryAgain
        }
        MahjongRPCStatus.notActive -> finishedMatch
        MahjongRPCStatus.illegal -> notAnOption
        MahjongRPCStatus.windowClosed, MahjongRPCStatus.tooEarly -> null
        MahjongRPCStatus.tooFast -> if (action == Action.back) backTooFast else null
        MahjongRPCStatus.invalid -> when (action) {
            Action.create -> "고를 수 없는 판돈이에요"
            Action.invite -> "초대할 수 없는 사람이에요"
            Action.join -> "참가할 수 없는 방이에요"
            else -> tryAgain
        }
        MahjongRPCStatus.unknown -> tryAgain
    }
}
