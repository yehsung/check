// 원본: Tests/checkTests/V0369RummyV2LobbyTests.swift · V0369RummyPanelRenderTests.swift 의 뜻(사람 정렬 · 한 목록 · 줄 오른쪽 · 시작 조건) — 픽셀 대신 값으로 잰다 @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyLobbyUser
import com.yehsung.aingcheck.core.wire.games.RummyPeer
import com.yehsung.aingcheck.core.wire.games.RummyRPCStatus
import com.yehsung.aingcheck.core.wire.games.RummyRankRow
import com.yehsung.aingcheck.core.wire.games.RummyRanking
import com.yehsung.aingcheck.core.wire.games.RummyRankingMe
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.core.wire.games.RummyRoomSeat
import com.yehsung.aingcheck.core.wire.games.RummySeatState
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private fun id(n: Int): SwiftUUID = SwiftUUID.parse("7e7e0000-0000-4000-8000-${n.toString().padStart(12, '0')}")!!

private fun user(n: Int, capable: Boolean? = true, inMatch: Boolean? = false, focus: Boolean? = false, working: Boolean? = false) =
    RummyLobbyUser(id = id(n), displayName = "사람$n", capable = capable, inMatch = inMatch, focusMode = focus, isWorking = working)

private fun seat(n: Int, state: RummySeatState, no: Long? = null) = RummyRoomSeat(userId = id(n), displayName = "사람$n", state = state, seatNo = no)

private fun room(n: Int, stake: Long = 5, max: Long = 4, seats: List<RummyRoomSeat> = listOf(seat(100 + n, RummySeatState.joined, 0))) =
    RummyRoom(id = id(n), host = RummyPeer(id(100 + n), "방장$n"), stake = stake, maxSeats = max, seats = seats)

private fun entry(
    availability: RummyAvailability = RummyAvailability.available, locked: Boolean = false, block: GamesBusyGame? = null, working: Boolean = false, balance: Long? = 100,
) = GamesRummyEntry(availability, locked, block, working, balance)

class GamesRummyLobbyPlanTest {
    // MARK: 사람 정렬

    @Test
    fun peopleSplitsIntoThreeAndKeepsServerOrder() {
        // 없으면: 바쁜 사람이 [초대] 가능 칸에 섞이거나, 근무 중 → 이름의 서버 순서가 화면에서 뒤집힌다.
        val users = listOf(user(3), user(1, inMatch = true), user(2, capable = false), user(5), user(4, focus = true), user(6, capable = false, inMatch = true))
        val people = GamesRummyLobbyPlan.people(users)
        assertEquals(listOf(id(3), id(5)), people.ready.map { it.id })
        assertEquals(listOf(id(1), id(4)), people.busy.map { it.id })
        // 구버전은 게임 중이어도 접힌 칸에만 있다 — 두 칸에 두 번 서지 않는다.
        assertEquals(listOf(id(2), id(6)), people.outdated.map { it.id })
        assertEquals(users.size, people.ready.size + people.busy.size + people.outdated.size)
    }

    @Test
    fun statusFollowsTheChipOrder() {
        assertEquals(GamesRummyPersonStatus.outdated, GamesRummyLobbyPlan.status(user(1, capable = false, inMatch = true, focus = true, working = true)))
        assertEquals(GamesRummyPersonStatus.inMatch, GamesRummyLobbyPlan.status(user(1, inMatch = true, focus = true, working = true)))
        assertEquals(GamesRummyPersonStatus.focus, GamesRummyLobbyPlan.status(user(1, focus = true, working = true)))
        assertEquals(GamesRummyPersonStatus.working, GamesRummyLobbyPlan.status(user(1, working = true)))
        assertEquals(GamesRummyPersonStatus.resting, GamesRummyLobbyPlan.status(user(1)))
    }

    // MARK: 받은 초대 + 공개 방

    @Test
    fun joinablesPutInvitesFirstOnceAndSkipMyRoom() {
        val lobby = RummyLobby(status = RummyRPCStatus.ok, invites = listOf(room(1), room(2)), publicRooms = listOf(room(3), room(1), room(4)))
        // ★ 기준선: 앉은 방이 없으면 넷이 다 선다.
        assertEquals(listOf(id(1), id(2), id(3), id(4)), GamesRummyLobbyPlan.joinables(lobby, null).map { it.id })
        assertEquals(listOf(true, true, false, false), GamesRummyLobbyPlan.joinables(lobby, null).map { it.isInvite })
        // 지금 앉은 방은 양쪽 모두에서 빠진다.
        assertEquals(listOf(id(2), id(3), id(4)), GamesRummyLobbyPlan.joinables(lobby, id(1)).map { it.id })
        assertEquals(listOf(id(1), id(2), id(4)), GamesRummyLobbyPlan.joinables(lobby, id(3)).map { it.id })
        assertTrue(GamesRummyLobbyPlan.joinables(null, null).isEmpty())
    }

    @Test
    fun joinablesDropExpiredRoomsAndLockedBuildsKeepOnlyInvites() {
        val lobby = RummyLobby(status = RummyRPCStatus.ok, invites = listOf(room(1), room(2)), publicRooms = listOf(room(3)))
        assertEquals(listOf(id(2), id(3)), GamesRummyLobbyPlan.joinables(lobby, null) { it.id == id(1) }.map { it.id })
        // 잠긴 빌드: 공개 방은 앉을 수 없으니 안 선다. 받은 초대는 [거절]을 위해 남는다.
        assertEquals(listOf(id(1), id(2)), GamesRummyLobbyPlan.joinables(lobby, null, duelsLocked = true).map { it.id })
    }

    @Test
    fun joinTitleNamesWhatIsInTheList() {
        val invite = RummyJoinable(room(1), isInvite = true)
        val open = RummyJoinable(room(2), isInvite = false)
        assertEquals(RummyPhoneText.invitesTitle, GamesRummyLobbyPlan.joinTitle(listOf(invite)))
        assertEquals(RummyPhoneText.publicRoomsTitle, GamesRummyLobbyPlan.joinTitle(listOf(open)))
        assertEquals(RummyLobbyPhoneText.joinTitleMixed, GamesRummyLobbyPlan.joinTitle(listOf(invite, open)))
    }

    @Test
    fun joinChipSaysSeatsForInvitesAndFreeForPublic() {
        val seats = listOf(seat(1, RummySeatState.joined, 0), seat(2, RummySeatState.joined, 1), seat(3, RummySeatState.invited))
        assertEquals("2/4명", GamesRummyLobbyPlan.joinSeatChip(RummyJoinable(room(1, seats = seats), isInvite = true)))
        assertEquals("빈자리 2", GamesRummyLobbyPlan.joinSeatChip(RummyJoinable(room(1, seats = seats), isInvite = false)))
    }

    @Test
    fun canJoinTurnsOffOnlyForWhatTheServerWouldRefuse() {
        val item = RummyJoinable(room(1, stake = 5), isInvite = true)
        // ★ 기준선.
        assertTrue(GamesRummyLobbyPlan.canJoin(item, null, entry()))
        assertTrue(GamesRummyLobbyPlan.canJoin(item, null, entry(balance = 5)), "딱 맞는 잔액은 앉을 수 있다")
        assertTrue(GamesRummyLobbyPlan.canJoin(item, null, entry(balance = null)), "잔액을 모르면 막지 않는다")
        assertFalse(GamesRummyLobbyPlan.canJoin(item, null, entry(balance = 4)), "루비 부족")
        assertFalse(GamesRummyLobbyPlan.canJoin(item, room(9), entry()), "이미 방에 앉았다")
        assertFalse(GamesRummyLobbyPlan.canJoin(item, null, entry(block = GamesBusyGame.chess)), "다른 게임 중")
        assertFalse(GamesRummyLobbyPlan.canJoin(item, null, entry(locked = true)), "잠긴 빌드")
        assertFalse(GamesRummyLobbyPlan.canJoin(item, null, entry(working = true)), "도는 요청")
        assertFalse(GamesRummyLobbyPlan.canJoin(item, null, entry(availability = RummyAvailability.updateRequired)))
        val full = (0 until 4).map { seat(it + 10, RummySeatState.joined, it.toLong()) }
        assertFalse(GamesRummyLobbyPlan.canJoin(RummyJoinable(room(1, seats = full), isInvite = false), null, entry()), "가득 참")
    }

    // MARK: 사람 줄 오른쪽

    private fun action(u: RummyLobbyUser, room: RummyRoom? = null, amHost: Boolean = false, calling: List<SwiftUUID> = emptyList(), e: GamesRummyEntry = entry(), stake: Long = 5) =
        GamesRummyLobbyPlan.personAction(u, room, amHost, calling, e, stake)

    @Test
    fun withoutARoomInviteOpensATableUnlessTheServerWouldRefuse() {
        // ★ 기준선: 방이 없어도 [초대]는 살아 있다.
        assertEquals(GamesRummyPersonAction.Invite(true), action(user(1)))
        assertEquals(GamesRummyPersonAction.Invite(false), action(user(1, inMatch = true)))
        assertEquals(GamesRummyPersonAction.Invite(false), action(user(1, focus = true)))
        assertEquals(GamesRummyPersonAction.Invite(false), action(user(1), e = entry(working = true)))
        assertEquals(GamesRummyPersonAction.Invite(false), action(user(1), e = entry(block = GamesBusyGame.tetris)))
        // 고른 판돈을 낼 수 없으면 탁자가 안 열린다.
        assertEquals(GamesRummyPersonAction.Invite(false), action(user(1), e = entry(balance = 4)))
        assertEquals(GamesRummyPersonAction.Hidden, action(user(1, capable = false)))
        assertEquals(GamesRummyPersonAction.Hidden, action(user(1), e = entry(availability = RummyAvailability.serverMissing)))
    }

    @Test
    fun inMyRoomTheRowShowsSeatState() {
        val mine = room(1, seats = listOf(seat(1, RummySeatState.joined, 0), seat(2, RummySeatState.joined, 1), seat(3, RummySeatState.invited)))
        assertEquals(GamesRummyPersonAction.Tag(RummyPhoneText.joined), action(user(2), mine, amHost = true))
        assertEquals(GamesRummyPersonAction.Tag(RummyPhoneText.invited), action(user(3), mine, amHost = true))
        assertEquals(GamesRummyPersonAction.Invite(true), action(user(4), mine, amHost = true))
        // 방이 있으면 판돈은 이미 정해졌다 — 내 잔액은 초대를 막지 않는다.
        assertEquals(GamesRummyPersonAction.Invite(true), action(user(4), mine, amHost = true, e = entry(balance = 0)))
        // 구버전은 접힌 칸에서 흐린 [초대]다(서버 target_outdated 를 받을 일이 없게).
        assertEquals(GamesRummyPersonAction.Invite(false), action(user(4, capable = false), mine, amHost = true))
        assertEquals(GamesRummyPersonAction.Hidden, action(user(4), mine, amHost = false), "손님은 초대할 수 없다")
        val full = room(1, seats = (0 until 4).map { seat(it + 10, RummySeatState.joined, it.toLong()) })
        assertEquals(GamesRummyPersonAction.Invite(false), action(user(4), full, amHost = true), "가득 참")
    }

    @Test
    fun callingBeatsEverythingAndLockedBuildsHideInvite() {
        // 줄에 선 사람은 어떤 상태든 '부르는 중'이다(누른 것이 받아졌다는 표시).
        assertEquals(GamesRummyPersonAction.Tag(RummyPhoneText.calling), action(user(1, inMatch = true), calling = listOf(id(1))))
        assertEquals(GamesRummyPersonAction.Hidden, action(user(1), e = entry(locked = true)))
        assertEquals(GamesRummyPersonAction.Hidden, action(user(1), room(1), amHost = true, e = entry(locked = true)))
    }

    // MARK: 입구

    @Test
    fun openTableNeedsMoneyAndAFreeEntry() {
        assertTrue(entry().canOpenTable(10))
        assertTrue(entry(balance = null).canOpenTable(10))
        assertFalse(entry(balance = 9).canOpenTable(10))
        assertTrue(entry(balance = 9).canOpenTable(5), "낮은 판돈으로는 열린다")
        assertFalse(entry(block = GamesBusyGame.gomoku).canOpenTable(3))
        assertFalse(entry(locked = true).canOpenTable(3))
        assertFalse(entry(working = true).canOpenTable(3))
        assertFalse(entry(availability = RummyAvailability.updateRequired).canOpenTable(3))
    }

    @Test
    fun warningsFoldTheLockLineAndDoNotRepeatTheStoreNotice() {
        assertEquals(emptyList(), GamesRummyLobbyPlan.entryWarnings(null, duelsLocked = false))
        assertEquals(listOf(RummyNoticeText.updateRequired), GamesRummyLobbyPlan.entryWarnings(null, duelsLocked = true))
        assertEquals(listOf("막힘"), GamesRummyLobbyPlan.entryWarnings("막힘", duelsLocked = false))
        // 잠긴 빌드의 스토어 안내는 같은 글자다 — 두 줄로 서면 같은 말이 두 번이다.
        val warnings = GamesRummyLobbyPlan.entryWarnings(null, duelsLocked = true)
        assertEquals(null, GamesRummyLobbyPlan.storeNotice(RummyNoticeText.updateRequired, warnings))
        assertEquals("초대를 보냈어요", GamesRummyLobbyPlan.storeNotice("초대를 보냈어요", warnings))
        assertEquals(null, GamesRummyLobbyPlan.storeNotice(null, warnings))
    }

    // MARK: 방

    private fun roomOf(joined: Int, invited: Int = 0, stake: Long = 5): RummyRoom = room(
        1, stake = stake,
        seats = (0 until joined).map { seat(it + 10, RummySeatState.joined, it.toLong()) } + (0 until invited).map { seat(it + 20, RummySeatState.invited) },
    )

    @Test
    fun startNeedsTheHostAndTwoSeated() {
        // ★ 기준선.
        assertTrue(GamesRummyRoomPlan.canStart(roomOf(2), amHost = true, entry()))
        assertTrue(GamesRummyRoomPlan.canStart(roomOf(4), amHost = true, entry()))
        assertFalse(GamesRummyRoomPlan.canStart(roomOf(1), amHost = true, entry()), "혼자")
        assertFalse(GamesRummyRoomPlan.canStart(roomOf(1, invited = 3), amHost = true, entry()), "초대 중은 앉은 사람이 아니다")
        assertFalse(GamesRummyRoomPlan.canStart(roomOf(2), amHost = false, entry()), "손님")
        assertFalse(GamesRummyRoomPlan.canStart(roomOf(2), amHost = true, entry(working = true)))
        assertFalse(GamesRummyRoomPlan.canStart(roomOf(2), amHost = true, entry(locked = true)), "판돈이 움직이는 순간 — 잠긴 빌드")
        assertFalse(GamesRummyRoomPlan.canStart(null, amHost = true, entry()))
    }

    @Test
    fun startTitleNeverSaysStartWithOne() {
        assertEquals(RummyPhoneText.start, GamesRummyRoomPlan.startTitle(roomOf(1)))
        assertEquals("3명으로 시작", GamesRummyRoomPlan.startTitle(roomOf(3)))
    }

    @Test
    fun potIsStakeTimesSeatedAndSplitFollowsTheUserTable() {
        assertEquals("5 × 3명 = 15", GamesRummyRoomPlan.potLine(roomOf(3)))
        // 혼자 앉아도 0명이 아니다. 초대 중은 세지 않는다.
        assertEquals("10 × 1명 = 10", GamesRummyRoomPlan.potLine(roomOf(1, invited = 2, stake = 10)))
        assertEquals("1등 10", GamesRummyRoomPlan.splitLine(roomOf(1)), "혼자면 2명 기준으로 미리 보여 준다")
        assertEquals("1등 10", GamesRummyRoomPlan.splitLine(roomOf(2)))
        assertEquals("1등 10 · 2등 5", GamesRummyRoomPlan.splitLine(roomOf(3)))
        assertEquals("1등 15 · 2등 5", GamesRummyRoomPlan.splitLine(roomOf(4)))
    }

    @Test
    fun countdownRoundsUpAndUrgesUnderAMinute() {
        assertEquals(600, GamesRummyRoomPlan.countdownSeconds(599.2))
        assertEquals(0, GamesRummyRoomPlan.countdownSeconds(-3.0))
        assertEquals("10:00 뒤 닫혀요", RummyPhoneText.closesIn(GamesRummyRoomPlan.countdownSeconds(599.2)))
        assertTrue(GamesRummyRoomPlan.isUrgent(59))
        assertFalse(GamesRummyRoomPlan.isUrgent(60))
    }

    @Test
    fun tableStageFitsEveryPhoneWidth() {
        // 카드 안쪽 폭: 320·393·430 기기에서 좌우 여백을 뺀 값. 없으면: 작은 폰에서 펠트가 상금 글자보다 좁아진다.
        for (stage in listOf(256f, 329f, 366f)) {
            val chair = GamesRummyTableStage.chairWidth(stage)
            val felt = GamesRummyTableStage.feltWidth(stage)
            assertTrue(chair >= 72f, "의자 $chair @ $stage")
            assertTrue(felt >= 100f, "펠트 $felt @ $stage")
            assertEquals(stage, chair * 2 + felt + GamesRummyTableStage.GAP * 2, 0.01f)
        }
        assertEquals(setOf(0, 1, 2, 3), setOf(GamesRummyTableStage.BOTTOM, GamesRummyTableStage.LEFT, GamesRummyTableStage.TOP, GamesRummyTableStage.RIGHT))
    }

    // MARK: 순위

    @Test
    fun rankingContentSaysLoadingOnlyBeforeTheFirstAttempt() {
        val rows = RummyRanking(RummyRPCStatus.ok, rows = listOf(RummyRankRow(id(1), rank = 1)))
        assertEquals(GamesRummyRankingPlan.Content.loading, GamesRummyRankingPlan.content(null, attempted = false))
        // 영영 도는 표시로 남지 않는다(순위 스위치가 꺼진 조립 · 실패).
        assertEquals(GamesRummyRankingPlan.Content.failed, GamesRummyRankingPlan.content(null, attempted = true))
        assertEquals(GamesRummyRankingPlan.Content.empty, GamesRummyRankingPlan.content(RummyRanking(RummyRPCStatus.ok, rows = emptyList()), attempted = true))
        assertEquals(GamesRummyRankingPlan.Content.empty, GamesRummyRankingPlan.content(RummyRanking(RummyRPCStatus.ok), attempted = false))
        assertEquals(GamesRummyRankingPlan.Content.rows, GamesRummyRankingPlan.content(rows, attempted = false))
    }

    @Test
    fun rankingLinesAndMyRow() {
        assertEquals("내 순위 3등 · 판 수 7 · 1등 2", RummyLobbyPhoneText.myRank(RummyRankingMe(games = 7, wins = 2, rank = 3)))
        assertEquals("내 순위 — · 판 수 0 · 1등 0", RummyLobbyPhoneText.myRank(RummyRankingMe()))
        assertTrue(GamesRummyRankingPlan.isMe(id(1), id(1).lowercased.uppercase()))
        assertFalse(GamesRummyRankingPlan.isMe(id(1), id(2).lowercased))
        assertFalse(GamesRummyRankingPlan.isMe(id(1), null))
    }

    // MARK: 글자

    @Test
    fun newWordsStayOffMacVocabulary() {
        val lines = GamesRummyPersonStatus.entries.map { it.text } + GamesRummyLobbyTab.entries.map { it.title } + listOf(
            RummyLobbyPhoneText.joinTitleMixed, RummyLobbyPhoneText.myRubyTitle, RummyLobbyPhoneText.rankingLoading, RummyLobbyPhoneText.rankingFailed,
            RummyPhoneText.peopleCaptionNoRoom, RummyPhoneText.peopleCaptionHost, RummyPhoneText.peopleCaptionGuest, RummyPhoneText.startHintHost, RummyPhoneText.startHintGuest,
        )
        val banned = listOf("창", "마우스", "클릭", "호버", "⌥", "트랙패드", "커서", "메뉴바", "루미")
        for (line in lines) for (word in banned) assertFalse(word in line, "\"$line\" 에 \"$word\"")
    }
}
