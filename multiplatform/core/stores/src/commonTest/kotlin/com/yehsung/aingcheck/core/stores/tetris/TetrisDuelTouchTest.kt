// 원본: Tests/CheckMobileKitTests/GamesTetrisDuelMatchTests.swift:96-199(손가락 → 조각 · 결과 숫자) ·
//       Tests/CheckMobileKitTests/GamesTetrisLobbyTests.swift:105-115 · 610-618(판돈 고르기 · 못 쓰는 기기 안내) @ 1b8260d
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelSession
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 판 위 한 손가락([GamesTetrisDuelTouch])을 손가락 좌표부터 엔진 상태까지 실제로 구동한다 — 재는 것은 "함수를 불렀나" 가 아니라
 * **조각이 몇 칸 갔나 · 회전했나** 다. 시계 둘을 고정한다(단조 시계가 고정이라 입력 사이에 중력이 끼지 않는다).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TetrisDuelTouchTest {
    private val base = 10_000.0
    private val wall = SwiftDate(1_800_000_000.0)

    private fun opponent() = TetrisDuelUser("00000000-0000-0000-0000-000000000011", "테트라이벌", null, null, true, true, true)

    /** 빈 판 + 떨어지는 T 하나(이동·회전을 재기에 넉넉하다). */
    private fun freeGame() = TetrisGame(
        seed = 7uL, board = TetrisGame.emptyBoard(),
        active = TetrisGame.ActivePiece(piece = TetrisGame.Piece.t, column = 4, row = 24),
        next = listOf(TetrisGame.Piece.i, TetrisGame.Piece.o, TetrisGame.Piece.s, TetrisGame.Piece.z, TetrisGame.Piece.l),
    )

    /** 판이 흐르는 스토어(호스트 없음 — 요청 0). 판 루프·폴링은 재운다 — 이 시험이 tick 을 직접 부른다. */
    private fun TestScope.playingStore(game: TetrisGame = freeGame()): TetrisDuelStore {
        val store = TetrisDuelStore(host = null, scope = backgroundScope, clock = { wall })
        store.gameLoopStepSeconds = Double.POSITIVE_INFINITY
        store.pollStepSeconds = Double.POSITIVE_INFINITY
        store.uptime = { base }
        val state = TetrisDuelMatchState(
            "7e7e0000-0000-4000-8000-000000000011", 5, 7, opponent(), wall.addingTimeInterval(-6.0), null, null, null, true,
            TetrisDuelOpponentBoard.empty, false, null, null, null, null,
        )
        store.match = state
        store.duel = TetrisDuelSession(seed = 7, startedGame = game, startAt = base, simulated = 0.0)
        store.duelMatchID = state.id
        store.phase = TetrisDuelPhase.playing
        store.syncStats()
        return store
    }

    /** 떨어지는 조각의 가장 왼쪽 열(이동을 재는 자리). */
    private fun column(store: TetrisDuelStore): Int? = store.duel?.game?.active?.cells?.minOf { it.column }

    private fun row(store: TetrisDuelStore): Int? = store.duel?.game?.active?.row

    @Test
    fun oneDragCellMovesThePieceOneCell() = runTest {
        val store = playingStore()
        val touch = GamesTetrisDuelTouch(cellWidth = 20.0)
        val start = MiniGamePoint(100.0, 300.0)
        val before = assertNotNull(column(store))

        touch.changed(start, MiniGameSize(20.0, 0.0), wall, store)
        assertEquals(before + 1, column(store), "한 칸 끌었는데 조각이 한 칸 안 갔다")
        // 같은 끌기를 세 칸까지 이어 간다 — 누적 이동이라 새로 생긴 두 칸만 더 가야 한다.
        touch.changed(start, MiniGameSize(60.0, 0.0), wall, store)
        assertEquals(before + 3, column(store), "누적 60pt(세 칸)")
        // 손가락을 되돌리면 조각도 돌아온다(가로는 환불한다 — 손가락 위치가 곧 조각 위치).
        touch.changed(start, MiniGameSize(0.0, 0.0), wall, store)
        assertEquals(before, column(store), "손가락을 되돌렸는데 조각이 안 돌아왔다")
    }

    /** ★ 걸음 하나 뒤에 키가 눌린 채 남지 않는다 — `setLeftHeld` 로 흉내 내면 다음 틱마다 자동 반복이 조각을 계속 민다(P9). */
    @Test
    fun aGestureStepDoesNotLeaveAKeyHeld() = runTest {
        val store = playingStore()
        val touch = GamesTetrisDuelTouch(cellWidth = 20.0)
        touch.changed(MiniGamePoint(0.0, 0.0), MiniGameSize(20.0, 0.0), wall, store)
        val after = assertNotNull(column(store))
        store.tick(base + 0.5)          // DAS 0.167초의 세 배
        assertEquals(after, column(store), "걸음 하나 뒤에 키가 눌린 채 남았다")
    }

    /** 아래로 끌기 한 칸 = 한 칸 내려가고 1점(소프트드롭). */
    @Test
    fun aDownDragIsASoftDropOfOnePoint() = runTest {
        val store = playingStore()
        val touch = GamesTetrisDuelTouch(cellWidth = 20.0)
        val rowBefore = assertNotNull(row(store))
        val scoreBefore = store.duel!!.game.score
        touch.changed(MiniGamePoint(0.0, 0.0), MiniGameSize(0.0, 20.0), wall, store)
        assertEquals(rowBefore + 1, row(store), "아래로 한 칸 끌었는데 조각이 안 내려갔다")
        assertEquals(scoreBefore + 1, store.duel!!.game.score, "소프트드롭 한 칸이 1점이 아니다")
    }

    /** 톡 누르기는 **시계 회전**이다 · 0.25초를 넘겨 뗐으면 아무 일도 안 난다(애매한 입력을 아무 동작으로도 확정하지 않는다). */
    @Test
    fun aTapRotatesClockwiseButASlowReleaseDoesNothing() = runTest {
        val store = playingStore()
        val touch = GamesTetrisDuelTouch(cellWidth = 20.0)
        val before = assertNotNull(store.duel?.game?.active?.rotation)
        touch.changed(MiniGamePoint(0.0, 0.0), MiniGameSize(2.0, 2.0), wall, store)
        assertTrue(touch.ended(MiniGameSize(2.0, 2.0), wall.addingTimeInterval(0.1), store), "탭으로 안 읽혔다")
        assertEquals(before.clockwise, store.duel?.game?.active?.rotation, "탭이 시계 회전을 안 했다")

        val slow = playingStore()
        val slowTouch = GamesTetrisDuelTouch(cellWidth = 20.0)
        val slowBefore = assertNotNull(slow.duel?.game?.active?.rotation)
        slowTouch.changed(MiniGamePoint(0.0, 0.0), MiniGameSize(2.0, 0.0), wall, slow)
        assertFalse(slowTouch.ended(MiniGameSize(2.0, 0.0), wall.addingTimeInterval(0.4), slow), "0.4초 만에 뗀 손가락이 탭이다")
        assertEquals(slowBefore, slow.duel?.game?.active?.rotation, "0.4초 만에 뗀 손가락이 회전했다")
        // 새 끌기의 시작 시각은 새 시작점에서 다시 잡는다 — 앞 끌기의 시각으로 재면 빠른 탭이 느린 탭이 된다.
        slowTouch.changed(MiniGamePoint(5.0, 5.0), MiniGameSize(1.0, 1.0), wall.addingTimeInterval(5.0), slow)
        assertTrue(slowTouch.ended(MiniGameSize(1.0, 1.0), wall.addingTimeInterval(5.1), slow), "새 끌기의 시작 시각을 새로 잡지 않았다")
        assertNotEquals(slowBefore, slow.duel?.game?.active?.rotation)
    }

    /** 판돈 고르기: 고른 판돈을 다시 누르면 해제 · 잔액을 모르면 막지 않는다 · 모자라면 막는다. */
    @Test
    fun stakeSelectionTogglesAndOnlyBlocksAKnownShortfall() {
        assertEquals(TetrisDuelStake.five, GamesTetrisStakeSelection.toggled(null, TetrisDuelStake.five))
        assertNull(GamesTetrisStakeSelection.toggled(TetrisDuelStake.five, TetrisDuelStake.five))
        assertEquals(TetrisDuelStake.ten, GamesTetrisStakeSelection.toggled(TetrisDuelStake.five, TetrisDuelStake.ten))
        assertTrue(GamesTetrisStakeSelection.affordable(TetrisDuelStake.ten, null))
        assertFalse(GamesTetrisStakeSelection.affordable(TetrisDuelStake.ten, 9))
        assertTrue(GamesTetrisStakeSelection.affordable(TetrisDuelStake.five, 5))
    }

    /** 못 쓰는 기기·서버는 **코어 문구**로 말한다(맥과 같은 말) — 쓸 수 있으면 안내가 서지 않는다 · 두 갈래는 글자도 아이콘도 다르다. */
    @Test
    fun anUnavailableDuelSpeaksTheCoreCopy() {
        assertNull(GamesTetrisDuelUnavailable.title(TetrisDuelAvailability.available), "쓸 수 있는데 안내가 섰다")
        assertEquals(TetrisDuelNoticeText.updateMine, GamesTetrisDuelUnavailable.title(TetrisDuelAvailability.updateRequired))
        assertEquals(TetrisDuelNoticeText.unavailable, GamesTetrisDuelUnavailable.title(TetrisDuelAvailability.serverMissing))
        assertEquals("앱을 업데이트해야 대결할 수 있어요", TetrisDuelNoticeText.updateMine)
        assertEquals("1:1 테트리스는 곧 열려요", TetrisDuelNoticeText.unavailable)
        assertEquals("arrow.up.circle", GamesTetrisDuelUnavailable.icon(TetrisDuelAvailability.updateRequired))
        assertEquals("clock", GamesTetrisDuelUnavailable.icon(TetrisDuelAvailability.serverMissing))
    }

    /** 모자란 루비 문구(맥 스토어·오목·체스·테트리스가 같은 문장 — Swift V0317ShopTests:111-116): 모르면·모자라지 않으면 일반 문장. */
    @Test
    fun theShortfallSentenceCountsTheMissingRubies() {
        assertEquals("루비 18개 더 필요해요", DuelShortfallText.shortfallNotice(30, 12))
        assertEquals("루비가 모자라요", DuelShortfallText.shortfallNotice(null, 12))
        assertEquals("루비가 모자라요", DuelShortfallText.shortfallNotice(30, null))
        assertEquals("루비가 모자라요", DuelShortfallText.shortfallNotice(10, 30))
        assertEquals("루비가 모자라요", DuelShortfallText.shortfallNotice(10, 10))
        assertEquals("루비 1개 더 필요해요", DuelShortfallText.shortfallNotice(10, 9))
        assertEquals(DuelShortfallText.shortfallNotice(null, null), TetrisPhoneText.stakeShortfall)
    }
}
