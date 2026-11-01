// 원본: Sources/check/RummyPanelLobby.swift:128 (RummyLobbyView.joinables) · :220 (RummyPeopleColumn) · :348 (RummyPersonRow) · :401 (RummyRankList) · :516 (RummyTableCard) · :776 (RummyJoinRow) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §5
//
// 아잉 큐브 **로비·방·순위 판단** — 화면은 받아 그리기만 한다(GamesTetrisLobby.kt 와 같은 자리). 맥 뷰 안의 계산을 값으로 빼서 시험이 표로 잰다.
// 버튼을 끄는 판단은 "서버가 어차피 거절할 것"만 본다(구버전 · 게임 중 · 집중 · 가득 참 · 루비 부족). 나머지 거절은 서버 문구(`notice`)가 말한다.
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyLobbyUser
import com.yehsung.aingcheck.core.wire.games.RummyRanking
import com.yehsung.aingcheck.core.wire.games.RummyRankingMe
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.core.wire.games.RummyRoomSeat
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import kotlin.math.ceil

/** 로비 탭(맥 `RummyLobbyTab`). */
enum class GamesRummyLobbyTab {
    people, ranking;

    val title: String
        get() = when (this) {
            people -> RummyPhoneText.usersTab
            ranking -> RummyPhoneText.rankTab
        }
}

/** 받은 초대 또는 공개 방 한 장(맥 `RummyJoinable`). */
data class RummyJoinable(val room: RummyRoom, val isInvite: Boolean) {
    val id: SwiftUUID get() = room.id
}

/** 사람 줄의 상태 칩. 서열은 [GamesRummyLobbyPlan.status] 한 곳. */
enum class GamesRummyPersonStatus {
    outdated, inMatch, focus, working, resting;

    val text: String
        get() = when (this) {
            outdated -> RummyLobbyPhoneText.statusOutdated
            inMatch -> RummyLobbyPhoneText.statusInMatch
            focus -> RummyLobbyPhoneText.statusFocus
            working -> RummyLobbyPhoneText.statusWorking
            resting -> RummyLobbyPhoneText.statusResting
        }
}

/** 사람 줄 오른쪽(맥 `RummyPersonRow.Action`). */
sealed interface GamesRummyPersonAction {
    data object Hidden : GamesRummyPersonAction

    data class Invite(val enabled: Boolean) : GamesRummyPersonAction

    data class Tag(val text: String) : GamesRummyPersonAction
}

/** 로비 문구 표에 없는 글자(맥 `RummyPersonRow.status`·`RummyRankList`, 폰 관례). */
object RummyLobbyPhoneText {
    const val statusOutdated: String = "업데이트 필요"
    const val statusInMatch: String = "게임 중"
    const val statusFocus: String = "집중"
    const val statusWorking: String = "근무 중"
    const val statusResting: String = "쉬는 중"
    const val joinTitleMixed: String = "받은 초대 · 공개 방"
    const val myRubyTitle: String = "내 루비"
    const val unknownNumber: String = "—"
    const val rankingLoading: String = "순위를 불러오는 중…"
    const val rankingFailed: String = "순위를 불러오지 못했어요"

    fun sectionCount(title: String, count: Int): String = "$title $count"

    fun myRank(me: RummyRankingMe): String = "내 순위 ${RummyPhoneText.rank(me.rank)} · ${RummyPhoneText.record(me.games, me.wins)}"

    fun rankRowAccessibility(rank: Long?, name: String, games: Long?, wins: Long?, isMe: Boolean): String =
        (if (isMe) "나, " else "") + "${RummyPhoneText.rank(rank)}, $name, ${RummyPhoneText.record(games, wins)}"
}

/**
 * 입구 판단의 재료. 화면이 지금 값을 모아 넘긴다.
 * @param block 다른 게임 판이 흐른다(`GamesStore.rummyEntryBlock`). 방 화면은 이미 앉아 있어 null 이다.
 * @param balance 루비 잔액. null = 모른다(막지 않는다 — 맥 0.3.29 규칙).
 */
data class GamesRummyEntry(
    val availability: RummyAvailability,
    val duelsLocked: Boolean,
    val block: GamesBusyGame?,
    val isWorking: Boolean,
    val balance: Long?,
) {
    /** 입구가 열려 있다(요청이 도는 중인지는 따로 본다). */
    val isOpen: Boolean get() = availability == RummyAvailability.available && !duelsLocked && block == null

    fun affordable(stake: Long?): Boolean = balance == null || stake == null || stake <= balance

    /** [탁자 열기]. */
    fun canOpenTable(stake: Long): Boolean = isOpen && !isWorking && affordable(stake)
}

object GamesRummyLobbyPlan {
    /** 사람 탭의 세 무리. 서버 정렬을 그대로 지키며 나눈다 — 무리 안에서 다시 줄 세우지 않는다. */
    data class People(val ready: List<RummyLobbyUser>, val busy: List<RummyLobbyUser>, val outdated: List<RummyLobbyUser>)

    /** 판돈 기본값(로비 응답이 오기 전). */
    val defaultStakes: List<Long> = listOf(3L, 5L, 10L)

    fun people(users: List<RummyLobbyUser>): People = People(
        ready = users.filter { it.capable != false && it.inMatch != true && it.focusMode != true },
        busy = users.filter { it.capable != false && (it.inMatch == true || it.focusMode == true) },
        outdated = users.filter { it.capable == false },
    )

    /** 상태 칩: 구버전 > 게임 중 > 집중 > 근무 중 > 쉬는 중. */
    fun status(user: RummyLobbyUser): GamesRummyPersonStatus = when {
        user.capable == false -> GamesRummyPersonStatus.outdated
        user.inMatch == true -> GamesRummyPersonStatus.inMatch
        user.focusMode == true -> GamesRummyPersonStatus.focus
        user.isWorking == true -> GamesRummyPersonStatus.working
        else -> GamesRummyPersonStatus.resting
    }

    /**
     * 받은 초대 + 공개 방 한 목록(초대 먼저 · 서버 순서 · 같은 방은 한 번 · 지금 앉은 방은 뺀다).
     * 폴링이 30초라 수명이 지난 방이 남아 있을 수 있어 [isExpired] 로 거른다(없는 방에 [참가]를 세우지 않게).
     * 잠긴 빌드는 앉을 수 없으니 공개 방을 세우지 않는다 — 받은 초대는 [거절]을 위해 남긴다.
     */
    fun joinables(lobby: RummyLobby?, myRoomId: SwiftUUID?, duelsLocked: Boolean = false, isExpired: (RummyRoom) -> Boolean = { false }): List<RummyJoinable> {
        val invites = (lobby?.invites ?: emptyList()).filter { it.id != myRoomId && !isExpired(it) }
        val invited = invites.map { it.id }.toSet()
        val rooms = if (duelsLocked) {
            emptyList()
        } else {
            (lobby?.publicRooms ?: emptyList()).filter { it.id != myRoomId && it.id !in invited && !isExpired(it) }
        }
        return invites.map { RummyJoinable(it, isInvite = true) } + rooms.map { RummyJoinable(it, isInvite = false) }
    }

    /** 목록 머리. 어느 쪽만 있으면 그 이름, 둘 다면 함께. */
    fun joinTitle(items: List<RummyJoinable>): String {
        val hasInvite = items.any { it.isInvite }
        val hasRoom = items.any { !it.isInvite }
        return when {
            hasInvite && hasRoom -> RummyLobbyPhoneText.joinTitleMixed
            hasInvite -> RummyPhoneText.invitesTitle
            else -> RummyPhoneText.publicRoomsTitle
        }
    }

    fun joinedSeats(room: RummyRoom?): List<RummyRoomSeat> = (room?.seats ?: emptyList()).filter { it.state == RummySeatState.joined }

    fun maxSeats(room: RummyRoom): Int = (room.maxSeats ?: 4L).toInt()

    fun isFull(room: RummyRoom): Boolean = joinedSeats(room).size >= maxSeats(room)

    /** 카드 둘째 칩 — 초대는 앉은 수, 공개 방은 빈자리. */
    fun joinSeatChip(item: RummyJoinable): String {
        val joined = joinedSeats(item.room).size
        val max = maxSeats(item.room)
        return if (item.isInvite) RummyPhoneText.seats(joined, max) else RummyPhoneText.freeSeats(maxOf(0, max - joined))
    }

    /** [참가]·[앉기]. 이미 방에 앉았으면 못 앉는다(서버 `already_in_room`). */
    fun canJoin(item: RummyJoinable, myRoom: RummyRoom?, entry: GamesRummyEntry): Boolean =
        myRoom == null && entry.isOpen && !entry.isWorking && !isFull(item.room) && entry.affordable(item.room.stake)

    /**
     * 사람 줄 오른쪽. 방이 없으면 [초대](= 탁자 열고 부르기), 내 방(방장)이면 [초대]·'초대함'·'참가함', 남의 방이면 없음.
     * 잠긴 빌드는 초대 진입을 세우지 않는다. [stake] 는 방 없이 부를 때 열 탁자의 판돈이다.
     */
    fun personAction(user: RummyLobbyUser, room: RummyRoom?, amHost: Boolean, calling: List<SwiftUUID>, entry: GamesRummyEntry, stake: Long): GamesRummyPersonAction {
        if (user.id in calling) return GamesRummyPersonAction.Tag(RummyPhoneText.calling)
        if (entry.duelsLocked) return GamesRummyPersonAction.Hidden
        val free = user.capable != false && user.inMatch != true && user.focusMode != true && !entry.isWorking && entry.block == null
        if (room == null) {
            if (entry.availability != RummyAvailability.available || user.capable == false) return GamesRummyPersonAction.Hidden
            return GamesRummyPersonAction.Invite(free && entry.affordable(stake))
        }
        if (!amHost) return GamesRummyPersonAction.Hidden
        when (room.seats?.firstOrNull { it.userId == user.id }?.state) {
            RummySeatState.joined -> return GamesRummyPersonAction.Tag(RummyPhoneText.joined)
            RummySeatState.invited -> return GamesRummyPersonAction.Tag(RummyPhoneText.invited)
            else -> Unit
        }
        return GamesRummyPersonAction.Invite(free && !isFull(room))
    }

    /** 입구를 막는 안내(칸마다 한 줄). 받은 초대를 접는 한 줄(`incomingFoldedNotice`)도 같은 글자라 잠금 한 줄로 합친다. */
    fun entryWarnings(blockNotice: String?, duelsLocked: Boolean): List<String> =
        listOfNotNull(blockNotice, if (duelsLocked) RummyNoticeText.updateRequired else null)

    /** 스토어 안내줄 — 입구 안내와 같은 글자면 두 번 세우지 않는다. */
    fun storeNotice(notice: String?, warnings: List<String>): String? = notice?.takeIf { it !in warnings }
}

object GamesRummyRoomPlan {
    /** [시작] 은 방장 · 2명 이상 · 도는 요청 없음 · 입구 열림(판돈이 움직이는 순간이다). */
    fun canStart(room: RummyRoom?, amHost: Boolean, entry: GamesRummyEntry): Boolean =
        amHost && GamesRummyLobbyPlan.joinedSeats(room).size >= 2 && entry.isOpen && !entry.isWorking

    fun startTitle(room: RummyRoom?): String {
        val joined = GamesRummyLobbyPlan.joinedSeats(room).size
        return if (joined >= 2) RummyPhoneText.startWith(joined) else RummyPhoneText.start
    }

    /** 판돈 × 인원 = 상금. 비어 보여도 1명(방장)은 앉아 있다. */
    fun potLine(room: RummyRoom?): String = RummyPhoneText.pot(room?.stake ?: 0L, maxOf(GamesRummyLobbyPlan.joinedSeats(room).size, 1))

    /** 등수 분배 안내. 혼자 앉아 있으면 2명 기준으로 미리 보여 준다. */
    fun splitLine(room: RummyRoom?): String =
        RummyPhoneText.split(maxOf(GamesRummyLobbyPlan.joinedSeats(room).size, 2).toLong(), room?.stake ?: 0L)

    fun hint(amHost: Boolean): String = if (amHost) RummyPhoneText.startHintHost else RummyPhoneText.startHintGuest

    /** 남은 초를 올림해 정수로(맥 `left.rounded(.up)`). */
    fun countdownSeconds(remaining: Double): Int = maxOf(0, ceil(remaining).toInt())

    /** 곧 닫힌다(맥 `urgentBelow: 60`). */
    fun isUrgent(seconds: Int): Boolean = seconds < 60
}

/** 둘러앉은 탁자의 폭 계산(dp). 의자 넷 = [아래(나), 왼, 위, 오른] — `RummyTableSeating.chairs` 순서. */
object GamesRummyTableStage {
    const val BOTTOM: Int = 0
    const val LEFT: Int = 1
    const val TOP: Int = 2
    const val RIGHT: Int = 3
    const val GAP: Float = 4f
    private const val MIN_CHAIR: Float = 72f
    private const val MAX_CHAIR: Float = 100f

    fun chairWidth(stageWidth: Float): Float = (stageWidth * 0.27f).coerceIn(MIN_CHAIR, MAX_CHAIR)

    /** 왼·오른 의자 사이 펠트 폭. */
    fun feltWidth(stageWidth: Float): Float = stageWidth - (chairWidth(stageWidth) + GAP) * 2
}

object GamesRummyRankingPlan {
    enum class Content { rows, empty, loading, failed }

    /** @param attempted 이 탭이 적재를 한 번 해 봤다. 응답이 없는데 해 봤으면 실패다(순위 스위치가 꺼진 조립도 여기로 온다 — 영영 도는 표시로 숨기지 않는다). */
    fun content(ranking: RummyRanking?, attempted: Boolean): Content = when {
        ranking == null -> if (attempted) Content.failed else Content.loading
        ranking.rows.isNullOrEmpty() -> Content.empty
        else -> Content.rows
    }

    fun isMe(rowId: SwiftUUID, myUserID: String?): Boolean = rowId.lowercased == myUserID?.lowercase()
}
