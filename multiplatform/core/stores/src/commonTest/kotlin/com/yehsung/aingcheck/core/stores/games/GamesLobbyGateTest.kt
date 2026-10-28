// 원본: Tests/CheckMobileKitTests/GamesChessWiringTests.swift:372-480(체스 입구 게이트 · 로봇 판 가드) ·
//       Tests/CheckMobileKitTests/MessagesBlockReportTests.swift:319-338(오목 로비 차단 거르기) ·
//       Tests/CheckMobileKitTests/GamesTetrisLobbyTests.swift:152-192(테트리스 로비 차단 거르기) @ 1b8260d
// (판돈 대결 빌드 깃발 duelsEnabled 짝은 원본 없음 — G §8-17 #1 의 Android 몫)
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreTest
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class GamesLobbyGateTest {
    /** 체스 스토어 사실의 가짜(W2-d `ChessStore` 자리). 기본은 아무것도 없는 로비다. */
    private class Facts(
        override var hasOutgoing: Boolean = false,
        override var hasMatch: Boolean = false,
        override var isBusy: Boolean = false,
    ) : GamesChessGateFacts

    /** 오목·체스 로비 목록의 가짜(W2-d 스토어 자리 — 사용자 타입은 그쪽 것이라 여기서는 짝만 든다). */
    private data class Peer(val id: String, val name: String)

    private class Roster(override val lobbyUsers: List<Peer>) : GamesLobbyRoster<Peer> {
        override fun lobbyUserID(user: Peer): String = user.id
    }

    private val stakes = listOf(3, 5, 10)

    /**
     * ★ 로봇 판을 두는 중에는 1:1 체스 신청이 **나갈 길이 없다**. 1:1 판이 서는 순간 코어가 로봇 판을 버린다(문구도 확인도 없이 두던 판이
     * 사라진다) — 서버 `chess__busy` 는 로봇 판을 못 본다(행이 없다). 코어 `challenge` 에도 가드가 없어(Swift 기준선) 막는 자리는 이 게이트 둘이다.
     * 기준선(다른 입력): 같은 사람·같은 깃발에 판이 없으면 열린다.
     */
    @Test
    fun aRobotGameClosesEveryPathThatWouldDiscardIt() {
        val free = Facts()
        assertTrue(GamesChessChallengeGate.isEnabled(userIsCapable = true, userInMatch = false, store = free, blockedBy = null, duelsEnabled = true),
            "기준선: 판이 없으면 [도전]이 열린다")
        for (stake in stakes) assertEquals(stake, GamesChessStakeSend.sendable(stake, free, balance = 100, blockedBy = null, duelsEnabled = true))

        val robot = Facts(hasMatch = true)
        assertFalse(GamesChessChallengeGate.isEnabled(true, false, robot, null, duelsEnabled = true),
            "로봇 판 중인데 [도전]이 열려 있다 — 누르면 두던 판이 말없이 사라진다")
        for (stake in stakes) {
            assertNull(GamesChessStakeSend.sendable(stake, robot, balance = 100, blockedBy = null, duelsEnabled = true),
                "로봇 판 중인데 판돈 $stake 신청이 나갈 수 있다(게이트가 열린 뒤 로봇 판을 시작한 틈)")
        }
    }

    /** 체스 [도전] 게이트: 다른 게임 판 · 상대 대국 중 · 구버전(capable 모름 = 불가) · 보낸 신청 · 내 판 · 바쁨을 하나씩 막는다(나머지는 기준선 그대로). */
    @Test
    fun theChessChallengeGateRefusesEveryBlockedCase() {
        fun gate(capable: Boolean = true, inMatch: Boolean = false, facts: Facts = Facts(), blockedBy: GamesBusyGame? = null) =
            GamesChessChallengeGate.isEnabled(capable, inMatch, facts, blockedBy, duelsEnabled = true)
        assertTrue(gate(), "근무 안 함이어도 신청할 수 있어야 한다(맥 게이트와 같다 — 근무 축은 인자에 없다)")
        assertFalse(gate(blockedBy = GamesBusyGame.gomoku), "오목 판이 흐르는데 체스 [도전]이 열려 있다")
        assertFalse(gate(blockedBy = GamesBusyGame.tetris), "테트리스 판이 흐르는데 체스 [도전]이 열려 있다")
        assertFalse(gate(inMatch = true), "상대가 대국 중")
        assertFalse(gate(capable = false), "상대 앱이 체스를 모른다(capable null 도 불가로 읽는다 — W2-d user(from:))")
        assertFalse(gate(facts = Facts(hasOutgoing = true)), "보낸 신청이 떠 있으면 막는다")
        assertFalse(gate(facts = Facts(hasMatch = true)), "내 판(1:1·로봇)")
        assertFalse(gate(facts = Facts(isBusy = true)), "요청이 나가 있다")
    }

    /**
     * ★ G §8-17 #1: 판돈 대결의 **신청** 진입은 앱 구성 깃발 `duelsEnabled` 가 켜진 빌드에서만 선다. 짝으로 잰다 — 같은 사람·같은 스토어·같은
     * 판돈에 깃발만 다르다: 꺼짐 → [도전] 닫힘 · 판돈 셋 다 null(요청이 나갈 문이 없다) / 켜짐 → 열림 · 고른 판돈 그대로.
     */
    @Test
    fun theChessEntrancesOpenOnlyWhenTheBuildEnablesDuels() {
        for (enabled in listOf(false, true)) {
            val facts = Facts()
            assertEquals(enabled, GamesChessChallengeGate.isEnabled(true, false, facts, null, duelsEnabled = enabled), "[도전] enabled=$enabled")
            for (stake in stakes) {
                assertEquals(if (enabled) stake else null, GamesChessStakeSend.sendable(stake, facts, 100, null, duelsEnabled = enabled),
                    "판돈 $stake enabled=$enabled")
            }
        }
    }

    /** 판돈 시트의 마지막 문: 안 골랐으면 null · 잔액이 모자라면 null(모르면 막지 않는다) · 바쁨·다른 게임·보낸 신청이 각각 막는다. */
    @Test
    fun theChessStakeSendIsTheLastDoor() {
        val facts = Facts()
        assertNull(GamesChessStakeSend.sendable(null, facts, 100, null, duelsEnabled = true), "판돈을 안 고르면 낼 수 없다")
        assertEquals(10, GamesChessStakeSend.sendable(10, facts, null, null, duelsEnabled = true), "잔액을 모르면 막지 않는다")
        assertEquals(10, GamesChessStakeSend.sendable(10, facts, 10, null, duelsEnabled = true), "딱 맞는 잔액")
        assertNull(GamesChessStakeSend.sendable(10, facts, 9, null, duelsEnabled = true), "잔액 9 로 판돈 10")
        assertNull(GamesChessStakeSend.sendable(3, Facts(isBusy = true), 100, null, duelsEnabled = true))
        assertNull(GamesChessStakeSend.sendable(3, facts, 100, GamesBusyGame.tetris, duelsEnabled = true))
        assertNull(GamesChessStakeSend.sendable(3, Facts(hasOutgoing = true), 100, null, duelsEnabled = true))
        assertNull(GamesChessStakeSelection.toggled(5, 5), "고른 판돈을 다시 누르면 해제")
        assertEquals(10, GamesChessStakeSelection.toggled(3, 10))
        assertEquals(5, GamesChessStakeSelection.toggled(null, 5))
        assertTrue(GamesChessStakeSelection.affordable(10, null))
        assertFalse(GamesChessStakeSelection.affordable(10, 9))
        assertTrue(GamesChessStakeSelection.affordable(5, 5))
    }

    /**
     * 차단 확인 시트가 "오목 신청에서 서로 보이지 않아요" 라고 약속한다 — 메시지 탭에서 차단한 사람은 오목·체스·테트리스 로비 목록에서 곧바로
     * 빠진다. 거르는 곳은 화면이 읽는 이 자리 하나다: 코어 목록은 서버가 답한 그대로 두고(차단이 실패하면 그대로 돌아온다), 순서는 다시
     * 정렬하지 않는다. 기준선(다른 입력): 차단 목록이 비면 코어 목록 그대로다.
     */
    @Test
    fun blockedPeersLeaveTheGomokuAndChessLobbies() = runTest {
        val h = StoreHarness(this, route = { null })
        val games = GamesStore(h.context)
        // 순서는 일부러 정렬되지 않은 서버 순서다 — 거르는 자리가 다시 정렬하면 빨개진다.
        val gomoku = Roster(listOf(Peer("p-c", "가람"), Peer("p-a", "소라"), Peer("p-b", "도윤")))
        val chess = Roster(listOf(Peer("p-c", "가람"), Peer("p-a", "소라")))
        assertSame(gomoku.lobbyUsers, games.gomokuLobbyUsers(gomoku), "기준선: 거를 것이 없으면 코어 목록 그대로")
        assertSame(chess.lobbyUsers, games.chessLobbyUsers(chess))

        h.hiddenBlocked = setOf("p-a")
        assertEquals(listOf("p-c", "p-b"), games.gomokuLobbyUsers(gomoku).map { it.id }, "차단했는데 오목 로비에 [도전] 버튼과 함께 서 있다(순서는 그대로)")
        assertEquals(listOf("p-c"), games.chessLobbyUsers(chess).map { it.id }, "차단했는데 체스 로비에 서 있다")
        assertEquals(3, gomoku.lobbyUsers.size, "코어 목록은 서버가 답한 그대로")
        h.hiddenBlocked = setOf("p-b", "p-c", "p-a")
        assertTrue(games.gomokuLobbyUsers(gomoku).isEmpty())
    }

    @Test
    fun blockedPeersLeaveTheTetrisLobby() = runTest {
        val route: (RecordedRequest) -> Reply? = { r -> if (r.rpcName == "tetris_lobby") TetrisDuelStoreTest.lobby(incoming = false) else null }
        val h = StoreHarness(this, AppConfig(duelsEnabled = true), route = route)
        h.signIn()
        h.tetris.refreshLobby()
        runCurrent()
        val games = GamesStore(h.context)
        assertEquals(listOf(TetrisDuelStoreTest.PEER), games.tetrisLobbyUsers.map { it.id }, "기준선: 로비 상대가 선다")
        h.hiddenBlocked = setOf(TetrisDuelStoreTest.PEER)
        assertTrue(games.tetrisLobbyUsers.isEmpty(), "차단한 사람이 테트리스 로비에 남았다")
        assertEquals(1, h.tetris.users.size, "코어 목록은 그대로")
    }
}
