// 원본: Sources/check/CheckTetrisDuelWindow.swift:1-40(키 상실해도 판 계속 — 상대 시간 인질 금지 · 전용 키 게이트 "키가 향한 창 === 이 창") ·
//       :268-277 · ★364 · ★433(뗌 먼저) (W4-e — 공용 세로 화면 GamesTetrisDuelScreen 을 창에 그대로, W-3 #2)
package com.yehsung.aingcheck.desktop.windows.games.tetris

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelPhase
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.hardDrop
import com.yehsung.aingcheck.core.stores.tetris.hold
import com.yehsung.aingcheck.core.stores.tetris.rotate
import com.yehsung.aingcheck.core.stores.tetris.setLeftHeld
import com.yehsung.aingcheck.core.stores.tetris.setRightHeld
import com.yehsung.aingcheck.core.stores.tetris.setSoftDropHeld
import com.yehsung.aingcheck.desktop.windows.games.minigame.BoardGameNoticeSink
import com.yehsung.aingcheck.desktop.windows.games.minigame.BoardWindowDoors
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowFrame
import com.yehsung.aingcheck.desktop.windows.kit.GameKey
import com.yehsung.aingcheck.desktop.windows.kit.GameStroke
import com.yehsung.aingcheck.desktop.windows.kit.ImeGate
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice
import com.yehsung.aingcheck.ui.games.tetris.GamesTetrisDuelScreen

class TetrisDuelWindowDoors(private val store: TetrisDuelStore) : BoardWindowDoors {
    override fun windowDidShow() = store.windowDidShow()
    override fun windowDidHide() = store.windowDidHide()
    override fun windowDidClose() = store.windowDidClose()
    override fun windowOcclusionDidChange(visible: Boolean) = store.windowOcclusionDidChange(visible)
}

/** 대결 창은 IME 를 뗀다(E17 — 한글 2벌식 상태에서도 Z/X·스페이스가 물리 키로 먹게). 판 게임 둘(오목·체스)은 떼지 않는다(채팅 칸). */
object TetrisDuelIme {
    fun detach(window: java.awt.Window) = ImeGate.detach(window)
}

/** 테트리스 대결 창 상태 — 주사율만 쥔다. 키 상실은 판에 아무 일도 하지 않는다(표의 FocusLost = 빈 통지 — 상대 시간 인질 금지). */
class TetrisDuelWindowState(private val doors: BoardWindowDoors, private val probeHz: () -> Int = { 60 }) {
    var refreshHz: Int by mutableStateOf(60)
        private set

    fun apply(notices: List<StoreNotice>) = BoardGameNoticeSink.apply(doors, notices, readRefreshRate = { refreshHz = probeHz() })
}

/** 대결 키가 가는 곳(실제는 [TetrisDuelKeys.input] — 대결 스토어, 시험은 기록기). [live] = 판 입력을 받는 흐름(카운트다운·판 중). */
interface TetrisDuelInput {
    val live: Boolean
    fun stroke(stroke: GameStroke)
    fun hardDrop()
}

/**
 * 대결 키 → 대결 스토어. 누름/뗌을 그대로 넘긴다(대결 스토어엔 setLeft/Right/SoftDropHeld 가 있다 — TetrisDuelStoreGame.kt:182-227).
 * 게이트(키가 향한 창 === 이 창 ∧ 판 흐름 · 수정키 · 반복)는 kit GameKeyMap.stroke 가 이미 걸렀다 — ⚠️뗌은 게이트보다 먼저(★433) 여기까지 온다.
 */
object TetrisDuelKeys {
    /** 판 입력을 받는 흐름 — 카운트다운에도 삼킨다(시작 직전 스페이스가 초점 단추를 누르지 않게. 입력 자체는 스토어가 버린다 — CheckTetrisDuelWindow.swift:535-539). */
    fun isLive(store: TetrisDuelStore): Boolean = store.phase == TetrisDuelPhase.playing || store.phase == TetrisDuelPhase.countdown

    fun input(store: TetrisDuelStore): TetrisDuelInput = object : TetrisDuelInput {
        override val live: Boolean get() = isLive(store)
        override fun stroke(stroke: GameStroke) = apply(store, stroke)
        override fun hardDrop() = action(store)
    }

    fun apply(store: TetrisDuelStore, stroke: GameStroke) {
        when (stroke.key) {
            GameKey.MoveLeft -> store.setLeftHeld(stroke.down)
            GameKey.MoveRight -> store.setRightHeld(stroke.down)
            GameKey.SoftDrop -> store.setSoftDropHeld(stroke.down)
            GameKey.RotateCW -> if (stroke.down) store.rotate(clockwise = true)
            GameKey.RotateCCW -> if (stroke.down) store.rotate(clockwise = false)
            GameKey.Hold -> if (stroke.down) store.hold()
        }
    }

    /** 스페이스 = 하드드롭. */
    fun action(store: TetrisDuelStore) = store.hardDrop()
}

@Composable
fun TetrisDuelWindowContent(
    games: GamesStore,
    state: TetrisDuelWindowState,
    myUserID: String?,
    meName: String?,
    dark: Boolean,
    reduceMotion: Boolean,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    appActive: Boolean = true,
) {
    GameWindowFrame(dark, modifier) {
        GamesTetrisDuelScreen(
            games, myUserID, state.refreshHz, Modifier.fillMaxSize(),
            onBack = onBack, appActive = appActive, reduceMotion = reduceMotion, meName = meName,
        )
    }
}
