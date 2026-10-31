// 원본: Sources/CheckCore/RummyNoticeText.swift:1 @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.wire.games.RummyRPCStatus
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.core.wire.games.RummyTurnReason

/**
 * 아잉 큐브 안내 한 줄의 **유일한 출처**(설계서 §4.3 문구표 — 이 표 밖에서 문구를 만들지 마라). 진단 어휘(서버·상태·동기화·seq)는 쓰지 않는다.
 * 화면·말풍선·배너가 모두 여기서 문구를 가져간다. 맥과 폰이 같은 서버 응답을 같은 말로 옮겨야 하므로 코어 표를 그대로 옮겼다(TetrisDuelNoticeText 선례 — 스토어 모듈).
 * 골든 `rummy/notice`(status × 동작 전부)가 글자 계약이다. 화면 고정 글자는 화면 단계 몫이다.
 */
object RummyNoticeText {
    /** 어느 동작의 응답인가(같은 status 라도 동작마다 말이 다른 자리 — invalid 등). */
    enum class Action(val rawValue: String) {
        lobby("lobby"), create("create"), invite("invite"), join("join"), decline("decline"), leave("leave"),
        start("start"), state("state"), draft("draft"), play("play"), draw("draw"), ranking("ranking"),
    }

    const val tryAgain: String = "잠시 후 다시 시도해 주세요"
    const val checkConnection: String = "연결을 확인하고 다시 시도해 주세요"
    const val updateRequired: String = "앱을 업데이트해 주세요"
    const val signInAgain: String = "다시 로그인해 주세요"

    /** 서버에 아잉 큐브가 아직 없다(PGRST202 — 배포 중간 창). */
    const val unavailable: String = "아잉 큐브는 곧 열려요"
    const val invited: String = "초대를 보냈어요"
    const val roomClosed: String = "방이 닫혔어요"

    /** 시작 검사에서 **내가** 빠졌다. */
    const val droppedFromRoom: String = "루비가 모자라거나 다른 게임 중이라 방에서 빠졌어요"
    const val turnPassed: String = "차례가 이미 넘어갔어요"

    /** 완료·뽑기가 stale 인데 차례는 아직 내 것이다(남의 기권 등으로 판의 seq 가 올랐다 — 시간은 남아 있다). */
    const val tableChanged: String = "판이 바뀌었어요. 확인하고 다시 눌러 주세요"
    const val finishedMatch: String = "이미 끝난 판이에요"

    /** 말풍선 — 창이 안 보일 때 내 차례가 왔다(설계서 §5). */
    const val myTurnAttention: String = "아잉 큐브 — 내 차례예요"

    /** 말풍선 — 창이 안 보일 때 판이 시작됐다(내 차례가 아니면). */
    const val matchStartedAttention: String = "아잉 큐브가 시작됐어요"

    /** 초대 말풍선·배너 한 줄(설계서 §5): "OO님이 아잉 큐브에 초대했어요 · 판돈 N". */
    fun invitation(room: RummyRoom): String {
        val name = room.host?.displayName?.takeIf { it.isNotEmpty() } ?: "친구"
        val stake = room.stake ?: return "${name}님이 아잉 큐브에 초대했어요"
        return "${name}님이 아잉 큐브에 초대했어요 · 판돈 $stake"
    }

    /** 첫 등록 진행 표시("첫 등록 18/30점"). */
    fun initialProgress(points: Int): String = "첫 등록 $points/30점"

    /** 판정 이유 한 줄(설계서 §4.3). 통과(ok)·모름(unknown)은 null — 부르는 쪽이 [tryAgain] 으로 메운다. */
    fun reason(reason: RummyTurnReason, initialPoints: Int?): String? = when (reason) {
        RummyTurnReason.ok, RummyTurnReason.unknown -> null
        RummyTurnReason.malformed -> "타일 모양이 이상해요. 되돌리고 다시 놓아 주세요."
        RummyTurnReason.jokerNotReused -> "가져온 조커는 이번 차례에 판에 써야 해요."
        RummyTurnReason.tableTileRemoved -> "판에 있던 타일은 내 랙으로 가져올 수 없어요."
        RummyTurnReason.tileNotOwned -> "내 랙에 없는 타일이에요."
        RummyTurnReason.noTilePlayed -> "내 타일을 1개 이상 내야 해요."
        RummyTurnReason.invalidMeld -> "맞지 않는 묶음이 있어요."
        RummyTurnReason.initialTableTouched -> "첫 등록 차례에는 판에 있던 묶음을 건드릴 수 없어요."
        RummyTurnReason.initialUnder30 ->
            if (initialPoints == null) "첫 등록은 30점 이상이어야 해요." else "첫 등록은 30점 이상이어야 해요(지금 ${initialPoints}점)."
    }

    /** RPC 거절 한 줄(설계서 §4.3 상태 문구 + 동작별 보충). ok 는 부르지 않는다. */
    fun status(status: RummyRPCStatus, action: Action): String = when (status) {
        RummyRPCStatus.busy -> "이미 다른 게임 중이에요"
        RummyRPCStatus.targetBusy -> "상대가 다른 게임 중이에요"
        RummyRPCStatus.targetOutdated -> "상대 앱이 아잉 큐브를 아직 몰라요"
        RummyRPCStatus.targetFocused -> "상대가 집중 모드예요"
        RummyRPCStatus.insufficient -> "루비가 모자라요"
        RummyRPCStatus.roomFull -> "방이 가득 찼어요"
        RummyRPCStatus.roomClosed -> roomClosed
        RummyRPCStatus.notEnoughPlayers -> "2명 이상 모여야 시작할 수 있어요"
        RummyRPCStatus.seatsDropped -> "루비가 모자라거나 다른 게임 중인 사람이 빠졌어요"
        RummyRPCStatus.unsupportedClient -> updateRequired
        RummyRPCStatus.unauthorized -> signInAgain
        RummyRPCStatus.alreadyInRoom -> "이미 들어가 있는 방이 있어요"
        RummyRPCStatus.notHost -> "방장만 할 수 있어요"
        RummyRPCStatus.blackout -> "지금은 조용한 기간이라 초대할 수 없어요"
        RummyRPCStatus.tooManyInvites -> "한 번에 6명까지 초대할 수 있어요"
        RummyRPCStatus.alreadyInvited -> "이미 초대한 사람이에요"
        RummyRPCStatus.notInvited -> "초대받지 않은 방이에요"
        RummyRPCStatus.notFound -> if (action == Action.play || action == Action.draw) finishedMatch else roomClosed
        RummyRPCStatus.notYourTurn -> turnPassed
        // 차례 동작의 stale 만 "차례가 넘어갔다" 쪽이다. 시작의 stale 은 지갑 키 경합(30_room.sql) — 다시 시도.
        RummyRPCStatus.stale -> when (action) {
            Action.play, Action.draw, Action.draft -> turnPassed
            else -> tryAgain
        }
        RummyRPCStatus.notActive -> finishedMatch
        RummyRPCStatus.malformed -> reason(RummyTurnReason.malformed, null) ?: tryAgain
        RummyRPCStatus.invalid -> when (action) {
            Action.create -> "고를 수 없는 판돈이에요"
            Action.invite -> "초대할 수 없는 사람이에요"
            Action.join -> "참가할 수 없는 방이에요"
            else -> tryAgain
        }
        // v2 반응 쿨다운 — 화면은 이 문구를 띄우지 않는다(조용히 버린다). 표를 빠짐없이 두려고만 있다.
        RummyRPCStatus.tooFast -> "조금 천천히 보내 주세요"
        RummyRPCStatus.ok, RummyRPCStatus.rejected, RummyRPCStatus.unknown -> tryAgain
    }
}
