// 원본: Tests/checkTests/V0369RummyV2LobbyTests.swift:233 (closeDecisionTable · inviteQueueSteps · rematchInvitees · tableSeating) · Tests/checkTests/V0369RummyV2EngagedTests.swift:405 (updateDecisionTable) @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyMatchSeat
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.core.wire.games.RummyPeer
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.core.wire.games.RummyRoomSeat
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private fun lxId(n: Int): SwiftUUID = SwiftUUID.parse("00000000-0000-4000-8000-${n.toString().padStart(12, '0')}")!!

private val uMe = lxId(1)

private fun seat(id: SwiftUUID, no: Long?, state: RummySeatState) = RummyMatchSeat(seatNo = no, userId = id, state = state)

private fun match(status: RummyMatchStatus?, host: SwiftUUID?, mine: Long?, seats: List<RummyMatchSeat>) =
    RummyMatchState(id = lxId(100), status = status, hostId = host, mySeatNo = mine, seats = seats)

class RummyLobbyPolicyTest {
    private val P = RummyExitPolicy

    @Test
    fun closeDecisionTable() {
        assertEquals(RummyCloseDecision.confirmForfeit, P.closeDecision(RummyPhase.playing, RummySeatState.playing, false))
        assertEquals(RummyCloseDecision.confirmForfeit, P.closeDecision(RummyPhase.playing, RummySeatState.playing, true))
        assertEquals(RummyCloseDecision.close, P.closeDecision(RummyPhase.playing, RummySeatState.forfeit, false), "기권한 관전자에게 또 묻는다")
        assertEquals(RummyCloseDecision.close, P.closeDecision(RummyPhase.playing, null, false))
        assertEquals(RummyCloseDecision.leaveRoom, P.closeDecision(RummyPhase.room, RummySeatState.joined, false))
        assertEquals(RummyCloseDecision.confirmCloseRoom, P.closeDecision(RummyPhase.room, RummySeatState.joined, true))
        assertEquals(RummyCloseDecision.close, P.closeDecision(RummyPhase.lobby, null, false))
        assertEquals(RummyCloseDecision.close, P.closeDecision(RummyPhase.finished, RummySeatState.done, true))
        // 앱 종료·로그아웃: 보낼 것이 있는 것은 방 · 판(내 자리가 아직 playing)뿐.
        assertTrue(P.needsExitLeave(RummyPhase.room, RummySeatState.joined))
        assertTrue(P.needsExitLeave(RummyPhase.playing, RummySeatState.playing))
        assertFalse(P.needsExitLeave(RummyPhase.playing, RummySeatState.forfeit))
        assertFalse(P.needsExitLeave(RummyPhase.lobby, null))
        assertFalse(P.needsExitLeave(RummyPhase.finished, RummySeatState.done))
    }

    @Test
    fun updateDecisionTable() {
        assertEquals(RummyUpdateDecision.confirmForfeit, P.updateDecision(RummyPhase.playing, RummySeatState.playing, true))
        assertEquals(RummyUpdateDecision.proceed, P.updateDecision(RummyPhase.playing, RummySeatState.forfeit, true))
        assertEquals(RummyUpdateDecision.proceed, P.updateDecision(RummyPhase.playing, RummySeatState.playing, false))
        assertEquals(RummyUpdateDecision.confirmLeaveRoom, P.updateDecision(RummyPhase.room, RummySeatState.joined, true))
        assertEquals(RummyUpdateDecision.proceed, P.updateDecision(RummyPhase.room, RummySeatState.joined, false))
        assertEquals(RummyUpdateDecision.proceed, P.updateDecision(RummyPhase.lobby, null, true))
        assertEquals(RummyUpdateDecision.proceed, P.updateDecision(RummyPhase.finished, RummySeatState.done, true))
        assertEquals(RummyCloseDecision.close, P.closeDecision(RummyPhase.playing, RummySeatState.playing, false, engaged = false))
        assertFalse(P.needsExitLeave(RummyPhase.room, RummySeatState.joined, engaged = false))
    }

    @Test
    fun amHostComparesMySeatToHostId() {
        val seats = listOf(seat(lxId(2), 0, RummySeatState.joined), seat(uMe, 1, RummySeatState.joined))
        assertTrue(P.amHost(match(RummyMatchStatus.forming, uMe, 1, seats)))
        assertFalse(P.amHost(match(RummyMatchStatus.forming, lxId(2), 1, seats)))
        assertFalse(P.amHost(match(RummyMatchStatus.forming, null, 1, seats)))
        assertFalse(P.amHost(match(RummyMatchStatus.forming, uMe, null, seats)), "내 자리를 모르면 방장이 아니다")
        assertFalse(P.amHost(null))
        assertEquals(uMe, P.mySeat(match(RummyMatchStatus.active, uMe, 1, seats))?.userId)
        assertNull(P.mySeat(match(RummyMatchStatus.active, uMe, 7, seats)))
    }

    @Test
    fun inviteQueueSteps() {
        val a = lxId(20)
        val b = lxId(21)
        val q = RummyInviteQueue
        assertEquals(RummyInviteQueue.Step.Wait, q.step(emptyList(), false, RummyMatchStatus.forming, true, emptySet()))
        assertEquals(RummyInviteQueue.Step.Wait, q.step(listOf(a), true, null, false, emptySet()), "방 만들기가 떠 있는데 줄을 버렸다")
        assertEquals(RummyInviteQueue.Step.Drop, q.step(listOf(a), false, null, false, emptySet()), "만들기가 거절됐는데 줄이 남아 다음 방에서 엉뚱하게 초대한다")
        assertEquals(RummyInviteQueue.Step.Drop, q.step(listOf(a), false, RummyMatchStatus.active, true, emptySet()))
        assertEquals(RummyInviteQueue.Step.Drop, q.step(listOf(a), false, RummyMatchStatus.forming, false, emptySet()))
        assertEquals(RummyInviteQueue.Step.Skip(a), q.step(listOf(a, b), false, RummyMatchStatus.forming, true, setOf(a)))
        assertEquals(RummyInviteQueue.Step.Invite(a), q.step(listOf(a, b), false, RummyMatchStatus.forming, true, emptySet()))
    }

    private class FakeHost(override var match: RummyMatchState? = null, override var isWorking: Boolean = false) : RummyInviteQueueHost {
        var creates = 0
        val invited = ArrayList<SwiftUUID>()

        override fun createRoom() {
            creates += 1
        }

        override fun invite(userId: SwiftUUID) {
            invited.add(userId)
        }
    }

    @Test
    fun inviteQueueDrainsThroughHost() {
        val a = lxId(20)
        val b = lxId(21)
        val c = lxId(22)
        // 세션이 없으면 만들기가 안 떠난다 → 그 자리에서 줄을 버린다(눌러 둔 사람이 다음 방에 끌려가지 않게).
        val idle = FakeHost()
        val dropped = RummyInviteQueue()
        dropped.invite(a, idle)
        assertEquals(1, idle.creates)
        assertTrue(dropped.pending.isEmpty())

        // 만드는 중이면 줄에 선다 — 두 사람째는 또 만들지 않고, 같은 사람은 한 번만.
        val host = FakeHost(isWorking = true)
        val queue = RummyInviteQueue()
        queue.invite(a, host)
        queue.invite(b, host)
        queue.invite(b, host)
        assertEquals(listOf(a, b), queue.pending)
        assertEquals(1, host.creates)
        // 방이 섰다(내가 방장) — 앉은 a 는 건너뛰고 b 를 부른 뒤 일이 끝나길 기다린다.
        host.isWorking = false
        host.match = match(RummyMatchStatus.forming, uMe, 0, listOf(seat(uMe, 0, RummySeatState.joined), seat(a, null, RummySeatState.invited)))
        queue.pump(host)
        assertEquals(listOf(b), host.invited)
        assertTrue(queue.pending.isEmpty())

        // 내 방이면 바로 초대. 남의 방이면 아무것도 안 한다.
        queue.invite(c, host)
        assertEquals(listOf(b, c), host.invited)
        val guest = FakeHost(match = match(RummyMatchStatus.forming, lxId(9), 0, listOf(seat(uMe, 0, RummySeatState.joined))))
        queue.invite(c, guest)
        assertTrue(guest.invited.isEmpty())
        // 판 중엔 줄도 안 선다.
        val playing = FakeHost(match = match(RummyMatchStatus.active, uMe, 0, listOf(seat(uMe, 0, RummySeatState.playing))))
        queue.invite(c, playing)
        assertTrue(queue.pending.isEmpty())
        assertEquals(0, playing.creates)

        // 한 판 더 — 탁자를 열고 지난 판 사람들을 세운다.
        val again = FakeHost(isWorking = true)
        val rematch = RummyInviteQueue()
        rematch.createAndInvite(listOf(a, b), again)
        assertEquals(1, again.creates)
        assertEquals(listOf(a, b), rematch.pending)
        // 만들기가 거절되면 줄을 버린다.
        again.isWorking = false
        rematch.pump(again)
        assertTrue(rematch.pending.isEmpty())
    }

    @Test
    fun rematchInvitees() {
        val finished = match(
            RummyMatchStatus.finished,
            uMe,
            0,
            listOf(
                seat(lxId(3), 2, RummySeatState.done),
                seat(uMe, 0, RummySeatState.done),
                seat(lxId(4), 3, RummySeatState.forfeit),
                seat(lxId(2), 1, RummySeatState.done),
            ),
        )
        assertEquals(listOf(lxId(2), lxId(3)), P.rematchInvitees(finished))
    }

    @Test
    fun tableSeating() {
        val me = RummySeatFace("영식", null, "shiba")
        fun roomSeat(id: SwiftUUID, name: String, state: RummySeatState, no: Long?) = RummyRoomSeat(userId = id, displayName = name, state = state, seatNo = no)
        val room = RummyRoom(
            id = lxId(50),
            host = RummyPeer(id = lxId(2)),
            seats = listOf(
                roomSeat(lxId(2), "민수", RummySeatState.joined, 0),
                roomSeat(uMe, "영식", RummySeatState.joined, 2),
                roomSeat(lxId(3), "준호", RummySeatState.joined, 3),
                roomSeat(lxId(4), "서연", RummySeatState.invited, null),
            ),
        )
        val chairs = RummyTableSeating.chairs(room, me, uMe)
        assertEquals(listOf("영식", "준호", "민수", "서연"), chairs.map { it.name })
        assertTrue(chairs[0].isMe)
        assertEquals(2L, chairs[0].seatNo)
        assertEquals("나", chairs[0].tag)
        assertTrue(chairs[2].isHost)
        assertEquals("방장", chairs[2].tag)
        assertEquals("참가함", chairs[1].tag)
        assertTrue(chairs[3].dimmed)
        assertNull(chairs[3].seatNo, "초대 중 자리에 반응 앵커가 붙는다")
        assertEquals("초대함", chairs[3].tag)
        // 내가 방장이면 두 꼬리표.
        val mine = RummyTableSeating.chairs(room.copy(host = RummyPeer(id = uMe)), me, uMe)
        assertEquals("나 · 방장", mine[0].tag)
        val empty = RummyTableSeating.chairs(null, me, uMe)
        assertEquals(
            listOf(RummyTableChair.Kind.person, RummyTableChair.Kind.empty, RummyTableChair.Kind.empty, RummyTableChair.Kind.empty),
            empty.map { it.kind },
        )
        assertEquals("shiba", empty[0].character)
    }
}
