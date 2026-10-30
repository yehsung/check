// 원본: Sources/check/CheckMiniGameWindow.swift:1-367(①★202 앱 테마 고정 ②225-232 주사율 ③247 닫기 = 판 끝 ④267 키 상실 = 일시정지만) ·
//       MiniGamePanel.swift:146-460(MiniGameSpaceKey 키 표) (W4-e — 허브는 미니게임 창 안. 공용 세로 화면을 창에 그대로, W-3 #2)
package com.yehsung.aingcheck.desktop.windows.games.minigame

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.windows.kit.GameKey
import com.yehsung.aingcheck.desktop.windows.kit.GameStroke
import com.yehsung.aingcheck.ui.games.minigame.GamesMiniGameScreen
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFacts
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubScreen
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 게임 창 바탕 — 앱 테마 고정(★202: 창마다 시스템을 따로 따르지 않고 앱이 정한 밝음·어두움을 받는다) + 바탕색. */
@Composable
fun GameWindowFrame(dark: Boolean, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    AingTheme(dark = dark) {
        Box(modifier.fillMaxSize().background(AingTheme.colors.background), content = content)
    }
}

/**
 * 미니게임 창 본문 — 허브 ↔ 게임 화면. 판 게임 목적지(오목·체스·테트리스 대결)는 각자 창이라 [onOpenBoard] 로 넘긴다
 * (맥 CheckMenuView.swift:970-980 게임 레일 = 창 열기). 길건너는 허브가 노출 목록(MiniGameExposure.visible)으로 이미 뺀다(W-3 #1).
 */
@Composable
fun MiniGameWindowContent(
    store: GamesStore,
    state: MiniGameWindowState,
    facts: GamesHubBoardFacts,
    art: MiniGameArt,
    myUserID: String?,
    now: () -> SwiftDate,
    dark: Boolean,
    reduceMotion: Boolean,
    onOpenBoard: (GamesDestination) -> Unit,
    onOpenShop: () -> Unit,
    onOpenRankings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GameWindowFrame(dark, modifier) {
        when (val route = state.route) {
            MiniGameWindowRoute.Hub -> GamesHubScreen(
                store, facts, art, now,
                onOpen = { destination ->
                    when (destination) {
                        is GamesDestination.MiniGame -> state.show(destination.kind)
                        GamesDestination.Gomoku, GamesDestination.Chess, GamesDestination.TetrisDuel -> onOpenBoard(destination)
                    }
                },
                onOpenShop = onOpenShop,
                onOpenRankings = onOpenRankings,
                modifier = Modifier.fillMaxSize(),
            )
            is MiniGameWindowRoute.Game -> GamesMiniGameScreen(
                store, route.kind, state.refreshHz, art, myUserID, Modifier.fillMaxSize(),
                onBack = state::backToHub, windowFocused = state.windowFocused, reduceMotion = reduceMotion,
                pauseToggleSerial = state.pauseToggleSerial, onFrozenChanged = { state.frozen = it },
            )
            is MiniGameWindowRoute.Closed -> Unit
        }
    }
}

/**
 * 솔로 테트리스 키 → 컨트롤러(공용 패치 4 — GamesPlayController setLeft/Right/SoftDropHeld·releaseAllKeys). 누름/뗌을 그대로 넘기고
 * DAS·ARR 은 게임 시계(tick)가 한다 — 대결 창 [com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelKeys] 와 같은 표.
 * ⚠️뗌은 게이트보다 먼저(★433) 여기까지 온다. 키 상실(PauseIfPlaying)은 MiniGameWindowState 가 releaseAllKeys 로 놓는다.
 */
object SoloTetrisKeys {
    fun apply(controller: GamesPlayController, stroke: GameStroke) {
        when (stroke.key) {
            GameKey.MoveLeft -> controller.setLeftHeld(stroke.down)
            GameKey.MoveRight -> controller.setRightHeld(stroke.down)
            GameKey.SoftDrop -> controller.setSoftDropHeld(stroke.down)
            GameKey.RotateCW -> if (stroke.down) controller.rotate(clockwise = true)
            GameKey.RotateCCW -> if (stroke.down) controller.rotate(clockwise = false)
            GameKey.Hold -> if (stroke.down) controller.hold()
        }
    }

    /** 스페이스 = action(맥 MiniGamePanel: 테트리스 판 중이면 하드드롭, 아니면 시작 — 컨트롤러 tap 은 폰 탭이라 판 중엔 회전이다). 다른 게임은 탭. */
    fun action(controller: GamesPlayController) {
        if (controller.kind == MiniGameKind.tetris && controller.isPlaying) controller.hardDrop() else controller.tap()
    }
}
