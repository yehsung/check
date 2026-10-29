// 원본: Sources/check/CheckMiniGameWindow.swift:217-300 · CheckGomokuWindow.swift:274-380(★314) · CheckChessWindow.swift ★360-371 ·
//       CheckTetrisDuelWindow.swift:1-40·268-277 · CheckGachaWindow.swift:58-75 · CheckCakeGiftWindow.swift:361-376 (W4-d)
package com.yehsung.aingcheck.desktop.windows.kit

import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind.CakeGift
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind.Chess
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind.Gacha
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind.Gomoku
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind.MiniGame
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind.TetrisDuel
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.DidClose
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.DidHide
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.DidShow
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.EndRound
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.MachineActive
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.MachineInactive
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.Occlusion
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.PauseIfPlaying
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice.ReadRefreshRate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GameWindowEventsTableTest {
    private val boardGames = listOf(Gomoku, Chess, TetrisDuel)

    private fun row(kind: GameWindowKind, e: WindowEvent) = GameWindowEvents.notices(kind, e)

    @Test
    fun tableMatchesGolden() {
        val sb = StringBuilder()
        sb.append("# GameWindowEvents.notices(kind, event) — 6 kind × 9 event(Visibility 는 참·거짓 둘 = 10열). '-' = 통지 없음\n")
        for (kind in GameWindowKind.entries) {
            for (e in WindowEvent.TABLE) {
                val n = row(kind, e)
                sb.append(kind.name).append(" | ").append(GameWindowEvents.label(e)).append(" | ")
                sb.append(if (n.isEmpty()) "-" else n.joinToString(", ") { GameWindowEvents.label(it) }).append('\n')
            }
        }
        assertEquals(60, sb.lines().count { it.contains(" | ") })
        KitGoldens.assertText("window-events.golden.txt", sb.toString())
    }

    /** 규칙 1(★314): 최소화는 닫기가 아니다 — 어떤 창도 Minimized 에 DidClose 를 내지 않는다. */
    @Test
    fun rule1_minimizeNeverCloses() {
        for (kind in GameWindowKind.entries) {
            assertFalse(DidClose in row(kind, WindowEvent.Minimized), "$kind Minimized")
        }
        for (kind in boardGames) assertEquals(listOf(DidHide), row(kind, WindowEvent.Minimized), "$kind")
    }

    /** 규칙 2(:302-320): 대결 창 닫기 = DidHide 뒤 DidClose — 사용자 닫기·프로그램 닫기(로그아웃) 둘 다. */
    @Test
    fun rule2_boardGameCloseIsHideThenClose() {
        for (kind in boardGames) {
            assertEquals(listOf(DidHide, DidClose), row(kind, WindowEvent.UserClosed), "$kind UserClosed")
            assertEquals(listOf(DidHide, DidClose), row(kind, WindowEvent.AppClosed), "$kind AppClosed")
        }
    }

    /** 규칙 3: 대결 셋은 키 상실·키 얻음에 아무것도 안 한다(windowDidResignKey 없음이 계약 — 상대 시간 인질 금지). */
    @Test
    fun rule3_boardGamesIgnoreFocus() {
        for (kind in boardGames) {
            assertEquals(emptyList(), row(kind, WindowEvent.FocusLost), "$kind FocusLost")
            assertEquals(emptyList(), row(kind, WindowEvent.FocusGained), "$kind FocusGained")
        }
    }

    /** 규칙 4(0.3.62): 미니게임 키 상실 = 일시정지만, 판을 끝내는 것은 사용자 닫기뿐. EndRound 는 다른 어디에도 없다. */
    @Test
    fun rule4_miniGamePausesOnFocusLossAndEndsOnlyOnUserClose() {
        assertEquals(listOf(PauseIfPlaying), row(MiniGame, WindowEvent.FocusLost))
        assertEquals(listOf(EndRound), row(MiniGame, WindowEvent.UserClosed))
        for (kind in GameWindowKind.entries) for (e in WindowEvent.TABLE) {
            if (kind == MiniGame && e == WindowEvent.UserClosed) continue
            assertFalse(EndRound in row(kind, e), "$kind $e 에 EndRound")
        }
    }

    /** 규칙 5: Visibility 는 Occlusion 으로만 — isWindowVisible(DidShow·DidHide)을 건드리지 않는다. */
    @Test
    fun rule5_visibilityIsOcclusionOnly() {
        for (kind in GameWindowKind.entries) for (v in listOf(true, false)) {
            val n = row(kind, WindowEvent.Visibility(v))
            assertFalse(DidShow in n || DidHide in n || DidClose in n, "$kind Visibility($v)")
            if (kind in boardGames) assertEquals(listOf(Occlusion(v)), n)
        }
    }

    /** 규칙 6(⑤ :276): 화면 이동에 주사율을 다시 읽는 창은 미니게임·테트리스 대결뿐. 미니게임은 창이 선 뒤에도 읽는다(② :225-233). */
    @Test
    fun rule6_refreshRateOnlyForRealtimeWindows() {
        for (kind in GameWindowKind.entries) {
            assertEquals(kind == MiniGame || kind == TetrisDuel, ReadRefreshRate in row(kind, WindowEvent.ScreenChanged), "$kind")
        }
        assertTrue(ReadRefreshRate in row(MiniGame, WindowEvent.Shown))
    }

    /** 규칙 7: 케이크 선물은 사용자 닫기만 알린다(cakeGiftDidClose) — 프로그램 닫기는 조용하다. */
    @Test
    fun rule7_cakeGiftOnlyUserClose() {
        for (e in WindowEvent.TABLE) {
            assertEquals(if (e == WindowEvent.UserClosed) listOf(DidClose) else emptyList(), row(CakeGift, e), "$e")
        }
    }

    /** 규칙 8(applyOcclusion guard isOpen): 닫힌 창의 가림 통지는 무시한다 — 모든 창. */
    @Test
    fun rule8_visibilityOnClosedWindowIsIgnored() {
        val closed = WindowPresence(open = false)
        for (kind in GameWindowKind.entries) for (v in listOf(true, false)) {
            assertEquals(emptyList(), GameWindowEvents.notices(kind, WindowEvent.Visibility(v), closed), "$kind")
        }
    }

    /** 규칙 9: 뽑기 isActive = 열림 ∧ ¬최소화 ∧ ¬가림 — 상태를 아는 판정이 기계 통지를 그 값으로 정한다. */
    @Test
    fun rule9_gachaMachineFollowsIsActive() {
        val open = WindowPresence(open = true)
        assertEquals(listOf(MachineActive), GameWindowEvents.notices(Gacha, WindowEvent.Shown, WindowPresence()))
        assertEquals(listOf(MachineInactive), GameWindowEvents.notices(Gacha, WindowEvent.Minimized, open))
        // 최소화된 채 잠금이 풀려도 기계는 깨어나지 않는다.
        assertEquals(listOf(MachineInactive), GameWindowEvents.notices(Gacha, WindowEvent.Visibility(true), open.copy(minimized = true)))
        // 가려진 채 되살려도 깨어나지 않는다.
        assertEquals(listOf(MachineInactive), GameWindowEvents.notices(Gacha, WindowEvent.Restored, open.copy(minimized = true, occluded = true)))
        assertEquals(listOf(MachineActive), GameWindowEvents.notices(Gacha, WindowEvent.Restored, open.copy(minimized = true)))
        assertEquals(listOf(MachineInactive), GameWindowEvents.notices(Gacha, WindowEvent.UserClosed, open))
        // isActive 진리표.
        for (o in listOf(true, false)) for (m in listOf(true, false)) for (c in listOf(true, false)) {
            assertEquals(o && !m && !c, WindowPresence(o, m, c).isActive, "open=$o min=$m occ=$c")
        }
        // 다른 창에는 Machine* 가 없다.
        for (kind in GameWindowKind.entries.filter { it != Gacha }) for (e in WindowEvent.TABLE) {
            val n = row(kind, e)
            assertFalse(MachineActive in n || MachineInactive in n, "$kind $e")
        }
    }
}
