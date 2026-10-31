// 원본: Sources/check/RummyPanelLobby.swift:56 (RummyInviteQueue) · :475 (RummyTableSeating) · Sources/check/RummyPanelResult.swift:41 (rematchInvitees) ·
//       Sources/check/RummyExitFlow.swift:35 (RummyExitPolicy · RummyCloseDecision) · :208 (RummyUpdateDecision) @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyMatchSeat
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.core.wire.games.RummyRoomSeat
import com.yehsung.aingcheck.core.wire.games.RummySeatState

// 아잉 큐브 로비·이탈의 순수 판단 — 맥 화면 파일(SwiftUI)에 있던 표들. 스토어·창에 기대는 갈래(leaveForExit · 창 닫기 덮개 · pump 를 미는 View 수식어)는
// 화면·스토어 단계 몫이다. 이탈 표(사용자 10-30 "창 닫거나 나가버리면 바로 기권"):
//
// | 행동                | 판(active, 내 자리 playing)  | 방(forming)                          | 그 밖(로비·결과·관전) |
// |--------------------|-----------------------------|--------------------------------------|----------------------|
// | 창 닫기              | "닫으면 기권돼요" 확인 → 기권  | 손님 = 그냥 나감 · 방장 = "방이 닫혀요" 확인 | 그냥 닫힘             |
// | 앱 종료 · 로그아웃    | 기권 후(최대 2초)             | 나간 뒤(최대 2초)                       | 즉시                  |
//
// **위 표는 이 기기가 손댄 판(engaged — 설계서 v2 §6)에만 선다.** 놀던 기기는 그냥 닫히고 rummy_leave 를 보내지 않는다.

/** Swift `RummyStore.Phase`(RummyStore.swift:71). 스토어 단계가 이 값을 쓴다. */
enum class RummyPhase { lobby, room, playing, finished }

/** 창 닫기 판단. */
enum class RummyCloseDecision {
    /** 그냥 닫는다(이탈할 판·방이 없다). */
    close,

    /** 손님이 방에서 닫는다 — 묻지 않고 나간다. */
    leaveRoom,

    /** 판 중 — "닫으면 기권돼요" 확인. */
    confirmForfeit,

    /** 방장이 방에서 닫는다 — "방이 닫혀요" 확인. */
    confirmCloseRoom,
}

/** [지금 업데이트] 판단. 업데이트는 앱을 끄고 새로 켠다 — 이 기기가 쥔 판이면 앱 종료와 같은 이탈이다. */
enum class RummyUpdateDecision {
    /** 쥔 판·방이 없다(또는 놀던 기기다) — 곧바로 업데이트. */
    proceed,

    /** 판 중(내 자리 playing) — "업데이트하면 지금 판이 기권돼요" 확인. */
    confirmForfeit,

    /** 방(forming) — "업데이트하면 방에서 나가요" 확인. */
    confirmLeaveRoom,
}

object RummyExitPolicy {
    /** 창 닫기(사람이 누른 닫기만). 순수 판단 — 시험이 표로 잰다. [engaged] = 이 기기가 그 판에 손댔다(§6). */
    fun closeDecision(phase: RummyPhase, mySeatState: RummySeatState?, amHost: Boolean, engaged: Boolean = true): RummyCloseDecision {
        if (!engaged) return RummyCloseDecision.close
        return when (phase) {
            RummyPhase.playing -> if (mySeatState == RummySeatState.playing) RummyCloseDecision.confirmForfeit else RummyCloseDecision.close
            RummyPhase.room -> if (amHost) RummyCloseDecision.confirmCloseRoom else RummyCloseDecision.leaveRoom
            RummyPhase.lobby, RummyPhase.finished -> RummyCloseDecision.close
        }
    }

    /** 앱 종료·로그아웃 앞에 rummy_leave 를 보낼 판·방이 있는가. 이미 기권한 관전자는 보낼 것이 없다. */
    fun needsExitLeave(phase: RummyPhase, mySeatState: RummySeatState?, engaged: Boolean = true): Boolean {
        if (!engaged) return false
        return when (phase) {
            RummyPhase.room -> true
            RummyPhase.playing -> mySeatState == RummySeatState.playing
            RummyPhase.lobby, RummyPhase.finished -> false
        }
    }

    /** 내 자리. Swift `mySeat(_ store:)` — 스토어 대신 판 값을 받는다. */
    fun mySeat(match: RummyMatchState?): RummyMatchSeat? {
        val mine = match?.mySeatNo ?: return null
        return match.seats?.firstOrNull { it.seatNo == mine }
    }

    /** 방장인가 — 판 state 의 방장 id 와 내 자리의 사람 id. */
    fun amHost(match: RummyMatchState?): Boolean {
        val hostId = match?.hostId ?: return false
        val seat = mySeat(match) ?: return false
        return seat.userId == hostId
    }

    /** 앱 업데이트([지금 업데이트]) 판단. 순수 판단 — 시험이 표로 잰다. */
    fun updateDecision(phase: RummyPhase, mySeatState: RummySeatState?, engaged: Boolean): RummyUpdateDecision {
        if (!engaged) return RummyUpdateDecision.proceed
        return when (phase) {
            RummyPhase.playing -> if (mySeatState == RummySeatState.playing) RummyUpdateDecision.confirmForfeit else RummyUpdateDecision.proceed
            RummyPhase.room -> RummyUpdateDecision.confirmLeaveRoom
            RummyPhase.lobby, RummyPhase.finished -> RummyUpdateDecision.proceed
        }
    }

    /** 결과 [한 판 더] 가 부를 사람 — 나 말고, 기권하지 않은 사람(자리 순). Swift `RummyResultView.rematchInvitees`. */
    fun rematchInvitees(match: RummyMatchState): List<SwiftUUID> =
        (match.seats ?: emptyList())
            .filter { it.seatNo != match.mySeatNo && it.state != RummySeatState.forfeit }
            .sortedBy { it.seatNo ?: 9L }
            .map { it.userId }
}

// MARK: - 초대 줄(방 없이 [초대] · 한 판 더)

/** 초대 줄이 스토어에서 보는 것 — Swift 는 RummyStore 를 바로 받는다. 스토어 단계가 이 다리를 놓는다. */
interface RummyInviteQueueHost {
    val match: RummyMatchState?
    val isWorking: Boolean

    fun createRoom()

    fun invite(userId: SwiftUUID)
}

/**
 * 방이 없을 때 누른 [초대] · 결과의 [한 판 더] 가 남긴 '부를 사람' 줄. 방이 서면(내가 방장) 한 사람씩 invite 를 보낸다.
 * 스토어 동작은 한 번에 하나(isWorking)라 끝날 때마다(isWorking 이 내려갈 때) 다음 사람을 부른다.
 */
class RummyInviteQueue {
    var pending: List<SwiftUUID> = emptyList()
        private set

    sealed interface Step {
        data object Wait : Step

        data class Invite(val userId: SwiftUUID) : Step

        data class Skip(val userId: SwiftUUID) : Step

        data object Drop : Step
    }

    /** 사람 행 [초대]. 내 방이면 바로 초대, 방이 없으면 탁자를 열고 줄에 세운다. */
    fun invite(userId: SwiftUUID, store: RummyInviteQueueHost) {
        if (store.match?.status == RummyMatchStatus.forming) {
            if (RummyExitPolicy.amHost(store.match)) store.invite(userId)
            return
        }
        if (store.match != null || userId in pending) return
        pending = pending + userId
        if (pending.size == 1) store.createRoom()
        pump(store)
    }

    /** 결과 [한 판 더] — 탁자를 열고(판돈·공개 여부는 호출자가 이미 맞췄다) 지난 판 사람들을 줄에 세운다. */
    fun createAndInvite(userIds: List<SwiftUUID>, store: RummyInviteQueueHost) {
        pending = userIds
        store.createRoom()
        if (pending.isNotEmpty()) pump(store)
    }

    fun pump(store: RummyInviteQueueHost) {
        while (true) {
            val seated = (store.match?.seats ?: emptyList()).map { it.userId }.toSet()
            when (val next = step(pending, store.isWorking, store.match?.status, RummyExitPolicy.amHost(store.match), seated)) {
                Step.Wait -> return
                Step.Drop -> {
                    pending = emptyList()
                    return
                }
                is Step.Skip -> pending = pending.filter { it != next.userId }
                is Step.Invite -> {
                    pending = pending.filter { it != next.userId }
                    store.invite(next.userId)
                    return
                }
            }
        }
    }

    companion object {
        /**
         * 다음 할 일 — 순수 판단(시험이 표로 잰다).
         *  · 일하는 중이면 기다린다(방 만들기·앞 초대가 떠 있다).
         *  · 방이 없으면(만들기가 거절됐다) · 방이 forming 이 아니면 · 내가 방장이 아니면 줄을 버린다.
         *  · 이미 자리가 있는 사람(초대 중·참가)은 건너뛴다.
         */
        fun step(pending: List<SwiftUUID>, isWorking: Boolean, roomStatus: RummyMatchStatus?, amHost: Boolean, seated: Set<SwiftUUID>): Step {
            val first = pending.firstOrNull() ?: return Step.Wait
            if (isWorking) return Step.Wait
            if (roomStatus != RummyMatchStatus.forming || !amHost) return Step.Drop
            return if (first in seated) Step.Skip(first) else Step.Invite(first)
        }
    }
}

// MARK: - 탁자 의자

/** 탁자 의자 글자(맥 `RummyLobbyText` · `RummyText` 가운데 의자가 쓰는 넷 — 정본 글자 그대로). */
object RummyTableSeatingText {
    const val me: String = "나"
    const val waitingAnswer: String = "답 기다리는 중"
    const val seated: String = "앉음"
    const val hostTag: String = "방장"
}

/** 내 얼굴(맥 `ChessPlayerFace` 가운데 의자가 쓰는 칸). */
data class RummySeatFace(val name: String, val avatarUrl: String?, val characterId: String?)

/** 탁자 의자 하나. */
data class RummyTableChair(
    val kind: Kind,
    val userId: SwiftUUID? = null,
    val name: String? = null,
    val avatarUrl: String? = null,
    val character: String? = null,
    val seatNo: Long? = null,
    val tag: String? = null,
    val isHost: Boolean = false,
    val isMe: Boolean = false,
    val dimmed: Boolean = false,
) {
    enum class Kind { person, empty }

    companion object {
        val empty = RummyTableChair(Kind.empty)
    }
}

object RummyTableSeating {
    /**
     * 의자 넷 = [아래(나), 왼, 위, 오른]. 방이면 나를 아래, 앉은 사람을 내 다음 자리부터 시계 방향으로, 그다음 초대 중,
     * 나머지는 빈 의자. 방이 없으면 나만 아래에 앉는다.
     */
    fun chairs(room: RummyRoom?, me: RummySeatFace, myUserId: SwiftUUID?): List<RummyTableChair> {
        if (room == null) {
            val mine = RummyTableChair(
                kind = RummyTableChair.Kind.person,
                userId = myUserId,
                name = me.name,
                avatarUrl = me.avatarUrl,
                character = me.characterId,
                tag = RummyTableSeatingText.me,
                isMe = true,
            )
            return listOf(mine, RummyTableChair.empty, RummyTableChair.empty, RummyTableChair.empty)
        }
        val seats = room.seats ?: emptyList()
        val hostId = room.host?.id
        val joined = seats.filter { it.state == RummySeatState.joined }
        val mineSeat = joined.firstOrNull { it.userId == myUserId }
        val mySeatNo = mineSeat?.seatNo ?: 0L
        fun relative(seat: RummyRoomSeat): Long = (((seat.seatNo ?: 9L) - mySeatNo) % 4 + 4) % 4
        fun chair(seat: RummyRoomSeat): RummyTableChair {
            val isMe = seat.userId == myUserId
            val isHost = seat.userId == hostId
            val tag = when {
                seat.state == RummySeatState.invited -> RummyTableSeatingText.waitingAnswer
                isMe -> if (isHost) "${RummyTableSeatingText.me} · ${RummyTableSeatingText.hostTag}" else RummyTableSeatingText.me
                else -> if (isHost) RummyTableSeatingText.hostTag else RummyTableSeatingText.seated
            }
            return RummyTableChair(
                kind = RummyTableChair.Kind.person,
                userId = seat.userId,
                name = seat.displayName ?: "?",
                avatarUrl = seat.avatarUrl,
                character = seat.character,
                seatNo = if (seat.state == RummySeatState.joined) seat.seatNo else null,
                tag = tag,
                isHost = isHost,
                isMe = isMe,
                dimmed = seat.state == RummySeatState.invited,
            )
        }
        val bottom = mineSeat?.let { chair(it) } ?: RummyTableChair.empty
        val others = joined.filter { it.userId != myUserId }.sortedBy { relative(it) } + seats.filter { it.state == RummySeatState.invited }
        val around = others.take(3).map { chair(it) }.toMutableList()
        while (around.size < 3) around.add(RummyTableChair.empty)
        return listOf(bottom) + around
    }
}
