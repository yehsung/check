// 원본: Sources/check/RummyPanel.swift:21 (RummyText) · Sources/check/RummyPanelLobby.swift:15 (RummyLobbyText) · Sources/check/RummyPanelMatch.swift:204 (RummyMatchText) ·
//       Sources/check/RummyPanelResult.swift:11 (RummyResultText) · Sources/check/RummyRackCues.swift:43 (RummyCueText) · Sources/check/RummyExitFlow.swift:133 (RummyExitText) · Sources/check/RummyInviteBanner.swift:13 (RummyInviteText) @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.rules.rummy.initialPlanPoints
import com.yehsung.aingcheck.core.wire.games.RummyEndReason
import com.yehsung.aingcheck.core.wire.games.RummyLastEvent
import com.yehsung.aingcheck.core.wire.games.RummyTurnReason

/**
 * 아잉 큐브 **폰** 화면 문구 표(화면 고정 글자 — 서버 응답 문구는 [RummyNoticeText] 한 곳).
 *
 * 맥 표를 터치 기준으로 다시 썼다. 맥과 다른 자리:
 * ① 창이 없다 — "창을 닫으면"은 "나가면"이다([exit]).
 * ② 시간 초과는 손 안 댐이든 틀림이든 **되돌리고 1장**이다(사용자 10-30 결정 · 서버 v3). 판 끝 안내도 같은 뜻으로 적는다.
 * ③ 등수 분배 규칙 줄은 받는 몫이 아니라 **순이익**으로 적는다(2명 +N·−N · 3명 +N·0·−N · 4명 +2N·0·−N·−N — 설계서 §6). 실제 분배는 서버 `rummy_payouts` 가 정한다.
 * 사용자 글자에 상표 게임 이름을 쓰지 않는다(글자는 '아잉 큐브').
 */
object RummyPhoneText {
    // MARK: - 공용

    const val title: String = "아잉 큐브"
    const val subtitle: String = "2~4명이 숫자 타일로 묶음을 만들어 랙을 먼저 비우는 게임"
    const val close: String = "닫기"
    const val leave: String = "나가기"
    const val forfeit: String = "기권"
    const val updateRequired: String = RummyNoticeText.updateRequired
    const val serverMissing: String = "아잉 큐브를 아직 열 수 없어요"

    /** 스토어 availability → 머리 없는 안내 한 줄. 쓸 수 있으면 null. */
    fun unavailable(availability: RummyAvailability): String? = when (availability) {
        RummyAvailability.available -> null
        RummyAvailability.updateRequired -> updateRequired
        RummyAvailability.serverMissing -> serverMissing
    }

    // MARK: - 게임 탭 카드

    /** 카드 부제(맥 초대 배너 부제와 같은 한 줄). */
    const val cardSubtitle: String = "2~4인 · 등수별 분배"
    const val cardOpenHint: String = "아잉 큐브 화면을 열어요"
    const val inRoomChip: String = "방에 앉아 있어요"
    const val idleLine: String = "사람을 불러 탁자를 열어요"
    const val recordTitle: String = "내 전적"

    fun incomingChip(count: Int): String = "받은 초대 ${count}건"

    fun record(games: Long?, wins: Long?): String = "판 수 ${games ?: 0} · 1등 ${wins ?: 0}"

    // MARK: - 로비

    const val usersTab: String = "사람"
    const val rankTab: String = "순위"
    const val publicRoomsTitle: String = "공개 방"
    const val noPublicRooms: String = "지금 열린 공개 방이 없어요"
    const val peopleCaptionNoRoom: String = "[초대]를 누르면 탁자가 열리고 바로 불러요"
    const val peopleCaptionHost: String = "초대할 사람을 골라요"
    const val peopleCaptionGuest: String = "방장만 초대할 수 있어요"
    const val emptyUsers: String = "함께할 사람이 아직 없어요"
    const val loadingUsers: String = "사람 목록을 불러오는 중…"
    const val join: String = "참가"
    const val decline: String = "거절"
    const val invite: String = "초대"
    const val invited: String = "초대함"
    const val joined: String = "참가함"
    const val createTitle: String = "방 만들기"
    const val createButton: String = "방 만들기"
    const val stakeLabel: String = "판돈"
    const val publicLabel: String = "공개 방"
    const val publicOn: String = "누구나 참가"
    const val publicOff: String = "초대한 사람만"
    const val createHint: String = "판돈은 시작할 때 모두에게서 걷고, 등수대로 나눠 가져요."
    const val invitesTitle: String = "받은 초대"
    const val noInvites: String = "받은 초대가 없어요"
    const val insufficient: String = "루비가 모자라요"
    const val newTable: String = "새 탁자"
    const val myTable: String = "내 탁자"
    const val newTableHint: String = "[초대]를 누르거나 탁자를 열어요"
    const val openTable: String = "탁자 열기"
    const val readyHeader: String = "초대 가능"
    const val busyHeader: String = "지금은 바빠요"
    const val calling: String = "부르는 중"
    const val waitingAnswer: String = "답 기다리는 중"
    const val seated: String = "앉음"
    const val me: String = "나"
    const val take: String = "앉기"
    const val joinEmpty: String = "받은 초대나 열린 공개 탁자가 생기면 여기에 떠요"
    const val outdatedHint: String = "새 버전이면 같이 할 수 있어요"

    fun outdatedFold(count: Int, expanded: Boolean): String =
        if (expanded) "업데이트가 필요한 사람 ${count}명 접기" else "업데이트가 필요한 사람 ${count}명"

    fun called(name: String): String = "${name}님이 불렀어요"

    fun publicTable(name: String): String = "${name}님의 공개 탁자"

    fun freeSeats(count: Int): String = "빈자리 $count"

    fun roomOf(name: String): String = "${name}님의 방"

    fun inviteFrom(name: String): String = "${name}님이 초대했어요"

    fun seats(joined: Int, max: Int): String = "$joined/${max}명"

    fun stake(stake: Long?): String = "판돈 ${stake ?: 0}"

    fun stakeCaption(stake: Long): String = "판돈 $stake · 끝나면 등수대로 · 한 차례 60초"

    /** 로비 사람 목록 머리 — 방이 없으면 방장이 되는 법, 내가 방장이면 고르라는 말, 남의 방이면 못 한다는 말. */
    fun peopleCaption(inRoom: Boolean, amHost: Boolean): String = when {
        !inRoom -> peopleCaptionNoRoom
        amHost -> peopleCaptionHost
        else -> peopleCaptionGuest
    }

    // MARK: - 방

    const val myRoomTitle: String = "내 방"
    const val start: String = "시작"
    const val emptySeat: String = "빈자리"
    const val hostTag: String = "방장"
    const val invitedTag: String = "초대 중"
    const val joinedTag: String = "참가"
    const val startHintHost: String = "2명 이상 모이면 시작할 수 있어요"
    const val startHintGuest: String = "방장이 시작하기를 기다리고 있어요"

    fun pot(stake: Long, players: Int): String = "$stake × ${players}명 = ${stake * players}"

    fun startWith(players: Int): String = "${players}명으로 시작"

    fun closesIn(seconds: Int): String = "${clock(seconds)} 뒤 닫혀요"

    // MARK: - 순위

    const val rankHeader: String = "1등 많은 순"
    const val emptyRanking: String = "아직 끝난 판이 없어요"

    // MARK: - 판

    const val undo: String = "되돌리기"
    const val sortNumber: String = "777"
    const val sortColor: String = "789"
    const val draw: String = "뽑기"
    const val pass: String = "넘기기"
    const val submit: String = "완료"
    const val beforeInitial: String = "등록 전"
    const val myTurn: String = "내 차례예요 — 타일을 끌어 판에 놓으세요"
    const val myTurnBadge: String = "내 차례"
    const val remainingTiles: String = "남은 타일"
    const val poolLabel: String = "더미에 남은 타일"
    const val zoomIn: String = "판 확대"
    const val zoomOut: String = "전체 보기"
    const val rules: String = "규칙"
    const val reactionButton: String = "반응"
    const val otherDevice: String = "다른 기기에서 하는 판이에요"
    const val otherDeviceDetail: String = "이 폰에서 타일을 옮기면 이 폰이 판을 이어 받아요."
    const val readOnlyBoard: String = "최종 판"

    fun rackCount(count: Long?): String = "${count ?: 0}장"

    fun pool(count: Long?): String = "더미 ${count ?: 0}장"

    fun placing(name: String): String = "${name}님이 놓는 중"

    fun turnOf(name: String): String = "${name}님 차례예요"

    fun matchPot(stake: Long?, seats: Long?): String = "판돈 ${stake ?: 0} × ${seats ?: 0}명"

    fun seconds(value: Int): String = "${value}초"

    fun clock(seconds: Int): String {
        val whole = maxOf(0, seconds)
        return "${whole / 60}:${(whole % 60).toString().padStart(2, '0')}"
    }

    fun timeouts(streak: Long): String = "시간 초과 $streak/3"

    /** 화면 밖 묶음 배지의 보이스오버(배지 글자는 "◀ 2"). */
    fun offscreenLeft(count: Int): String = "왼쪽에 안 보이는 묶음 ${count}개, 눌러서 밀어요"

    fun offscreenRight(count: Int): String = "오른쪽에 안 보이는 묶음 ${count}개, 눌러서 밀어요"

    /**
     * 내 차례 상태 줄(알림 notice 가 없을 때). 첫 등록 전에는 진행 점수(판 묶음을 건드렸으면 그 이유),
     * 첫 등록 뒤 판을 바꿨는데 [완료]가 꺼져 있으면 꺼진 이유, 아니면 끌어 놓으라는 말.
     */
    fun myTurnStatus(editor: RummyTurnEditor): String {
        val reason = editor.reason
        if (!editor.initialDone) {
            if (reason == RummyTurnReason.initialTableTouched) RummyNoticeText.reason(reason, null)?.let { return it }
            return RummyNoticeText.initialProgress(editor.initialPoints)
        }
        if (reason != RummyTurnReason.ok && editor.isChanged) RummyNoticeText.reason(reason, editor.initialPoints)?.let { return it }
        return myTurn
    }

    /** 받침대 첫 등록 합 한 줄(맥 RummyCueText.plan). 판에 놓은 묶음이 있으면 합을 함께 적는다. */
    fun plan(table: Int, rack: Int): String =
        if (table > 0) "랙 묶음 $rack + 판 $table = ${table + rack} / 30" else "랙 묶음 합 $rack / 30"

    /** 첫 등록 합 표시(첫 등록 뒤 · 랙 묶음이 없으면 null). */
    fun planLine(editor: RummyTurnEditor): String? {
        val planned = editor.initialPlanPoints ?: return null
        return if (planned.rack > 0) plan(planned.table, planned.rack) else null
    }

    fun meldPoints(points: Int): String = "$points"

    /** 직전 행동 한 줄. 모르는 종류·이름 없음은 null. */
    fun lastEvent(event: RummyLastEvent?, name: String?): String? {
        val kind = event?.kind ?: return null
        if (name == null) return null
        return when (kind) {
            "play" -> "${name}님이 ${event.count ?: 0}장 냈어요"
            "draw" -> "${name}님이 1장 뽑았어요"
            "pass" -> "${name}님이 넘겼어요"
            "timeout_play" -> "${name}님 시간 초과 — 놓던 판으로 확정"
            // v3: 바꿨는데 틀린 시간 초과도 되돌리고 1장 — 서버가 count 1 을 보낸다(옛 판 기록이면 그 장수 그대로).
            "timeout_penalty" -> "${name}님 시간 초과 — 되돌리고 ${event.count ?: 1}장 뽑음"
            "timeout_draw" -> "${name}님 시간 초과 — 1장 뽑음"
            "forfeit" -> "${name}님이 기권했어요"
            else -> null
        }
    }

    // MARK: - 결과

    const val resultTitle: String = "결과"
    const val playAgain: String = "한 판 더"
    const val finalBoard: String = "최종 판 보기"
    const val ranks: String = "등수"
    const val emptyBoard: String = "판에 놓인 묶음이 없어요"
    const val toLobby: String = "나가기"

    fun rank(rank: Long?): String = rank?.let { "${it}등" } ?: "—"

    fun score(score: Long?): String = when {
        score == null -> "점수 —"
        score > 0 -> "점수 +$score"
        else -> "점수 $score"
    }

    fun net(value: Long): String = when {
        value > 0 -> "+$value"
        value < 0 -> "−${-value}"
        else -> "0"
    }

    /**
     * 시작 전 안내 표(받는 몫 — 2인 [2,0] · 3인 [2,1,0] · 4인 [3,1,0,0] × 판돈). 안내 글자 전용이다 — 실제 분배는 서버 `rummy_payouts` 가 정하고
     * 결과 화면은 서버 값(`payout`)만 쓴다.
     */
    val splitTable: Map<Long, List<Long>> = mapOf(2L to listOf(2L, 0L), 3L to listOf(2L, 1L, 0L), 4L to listOf(3L, 1L, 0L, 0L))

    fun split(seatCount: Long?, stake: Long?): String {
        val shares = seatCount?.let { splitTable[it] } ?: return ""
        val value = stake ?: return ""
        return shares.withIndex().filter { it.value > 0 }.joinToString(" · ") { "${it.index + 1}등 ${it.value * value}" }
    }

    fun endReason(reason: RummyEndReason?, winner: String?): String = when (reason) {
        RummyEndReason.rackEmpty -> winner?.let { "${it}님이 랙을 비웠어요" } ?: "랙을 비운 사람이 나왔어요"
        RummyEndReason.blocked -> "더미가 비고 모두 넘겨서 끝났어요"
        RummyEndReason.lastStanding -> winner?.let { "${it}님 혼자 남아 끝났어요" } ?: "혼자 남아 끝났어요"
        RummyEndReason.unknown, null -> "판이 끝났어요"
    }

    // MARK: - 나가기 확인

    /** 나가기 확인 글자 한 벌. */
    data class ExitCopy(val title: String, val detail: String, val confirm: String)

    const val keepPlaying: String = "계속하기"

    /** 스토어 판단 → 확인 글자. 묻지 않는 판단(그냥 닫기 · 손님 나가기)은 null. */
    fun exit(decision: RummyCloseDecision): ExitCopy? = when (decision) {
        RummyCloseDecision.confirmForfeit -> ExitCopy("나갈까요?", "나가면 기권돼요. 판돈은 판 끝에 등수대로 정산돼요.", "기권하고 나가기")
        RummyCloseDecision.confirmCloseRoom -> ExitCopy("방을 닫을까요?", "방장이 나가면 방이 닫히고 모두 로비로 돌아가요. 루비는 그대로예요.", "방 닫기")
        RummyCloseDecision.close, RummyCloseDecision.leaveRoom -> null
    }

    // MARK: - 규칙

    /** 규칙 한 줄. [example] = 예시 타일 면 글자("A7"·"J"). */
    data class Rule(val title: String, val detail: String, val example: List<String> = emptyList())

    const val rulesTitle: String = "아잉 큐브 규칙"

    val ruleList: List<Rule> = listOf(
        Rule("그룹", "같은 숫자, 서로 다른 색 3~4장.", listOf("A7", "B7", "C7")),
        Rule("런", "같은 색으로 이어지는 숫자 3장 이상(13 다음 1로는 안 이어져요).", listOf("C3", "C4", "C5", "C6")),
        Rule("첫 등록", "내 랙의 타일만으로 만든 새 묶음 합이 30점 이상이어야 해요. 그 전엔 판 묶음을 건드릴 수 없어요.", listOf("B10", "C10", "D10")),
        Rule("조커", "아잉이 타일은 어떤 숫자·색으로도 쓰여요. 판의 조커를 가져오면 이번 차례에 판에 다시 써야 해요.", listOf("A5", "J", "A7")),
        Rule("판 조작", "첫 등록 뒤엔 판의 묶음을 나누고 합치고 옮겨도 돼요. 끝날 때 모든 묶음이 맞고 내 타일을 1장 이상 냈어야 해요. 판에 있던 타일은 랙으로 가져올 수 없어요."),
        Rule(
            "조작",
            "끌면 한 장이에요. 0.5초 길게 눌렀다 끌면 덩어리째 집어요(판에선 누른 타일에서 가까운 끝까지, 가운데를 누르면 묶음 전체). " +
                "묶음 왼쪽 손잡이를 끌면 묶음째 옮겨요. 묶음 끝 가까이 놓으면 붙고, 묶음 위에 놓으면 맞는 자리에 끼워져요. 묶음 가운데를 빼면 둘로 나뉘어요.",
        ),
        Rule("판 보기", "빈 펠트를 끌면 판을 옆으로 밀어요. 두 손가락으로 벌리거나 오므리면 크기가 바뀌고, [전체 보기]로 한눈에 봐요. 가장자리 숫자는 그쪽에 안 보이는 묶음 수예요."),
        Rule("받침대", "타일 사이에 놓으면 끼워 넣고 오른쪽을 밀어요. 딱 붙여 놓은 맞는 묶음엔 밑줄과 점수가 떠요. 777·789로 정렬해 두면 새로 뽑은 타일도 그 정렬 자리로 들어가요."),
        Rule("시간 60초", "시간이 지나면 놓던 판이 맞으면 그대로 확정돼요. 틀렸거나 아무것도 안 놓았으면 되돌리고 1장 뽑아요. 시간 초과가 3번 이어지면 기권이에요."),
        Rule("끝과 점수", "누군가 랙을 비우면 끝나요(더미가 비고 모두 넘겨도 끝). 남은 타일 합만큼 잃고(아잉이 30점), 이긴 사람이 그만큼 얻어요.", listOf("D12", "J")),
        Rule("등수 분배", "판돈이 N이면 2명 +N·−N · 3명 +N·0·−N · 4명 +2N·0·−N·−N. 기권은 꼴찌예요. 새로 생기는 루비는 없어요."),
        Rule("나가면", "판 중에 나가면 바로 기권이에요. 앱을 내리는 것만으로는 기권이 아니지만 90초 안에 돌아오지 않으면 기권돼요. 남은 사람끼리 계속해요."),
    )
}
