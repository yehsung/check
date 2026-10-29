// 원본: Sources/CheckMobileKit/Games/GamesTab.swift:48-76 @ 3bd04bd (navigationDestination — 게임 탭이 쌓는 목적지 넷)
//
// 게임 탭 첫 화면의 Android 껍데기(§8-4 — 화면 본문은 ui/games/minigame/hub). 목적지 고르기는 셸(NavGraph — 조립 K11)이 하고,
// 이 파일은 ① 게임 목적지 → 내비게이션 목적지 옮김 ② 첫 화면 Composable 을 준다. 배선은 assembly.md 대로 조정자가 NavGraph 에 잇는다.
package com.yehsung.aingcheck.android.screens.games.hub

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.GameSection
import com.yehsung.aingcheck.android.routing.AingMiniGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFacts
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubScreen
import com.yehsung.aingcheck.ui.games.minigame.rememberMiniGameArt

/** 게임 목적지 ↔ 셸 목적지. */
object GamesRoutes {
    /**
     * 게임 탭이 쌓는 목적지 → 셸 내비게이션 목적지.
     * INV-GamesTab-99042ff7 이식: **빠짐없는 when** 이다(else 가지가 없다) — 목적지를 더하면 이 함수가 컴파일을 막는다(Swift 는 iOS 빌드가 통째로 안
     *   섰고, 맥 swift build 는 그 파일을 보지 않아 그물이 빌드 스크립트 하나뿐이었다). Kotlin 은 컴파일러가 그물이다.
     * 미니게임 목적지가 셸 목적지를 못 얻으면(길건너처럼 폰 라우트 글자가 없는 종류) null — 셸은 쌓지 않는다.
     */
    fun destination(destination: GamesDestination): Any? = when (destination) {
        is GamesDestination.MiniGame -> miniGameRaw(destination.kind)?.let { Dest.MiniGame(it) }
        GamesDestination.Gomoku -> Dest.Gomoku(GameSection.LOBBY.raw)
        GamesDestination.Chess -> Dest.Chess(GameSection.LOBBY.raw)
        GamesDestination.TetrisDuel -> Dest.TetrisDuel
    }

    /**
     * 미니게임 종류 → 라우트 글자(AingMiniGame.raw). 길건너 아잉이는 **null**(폰 1.0.14 바닥 — 화면도 라우트 글자도 없다, G §8-18 7).
     * 빠짐없는 when — 종류를 더하면 여기서 멈춘다(모르는 값을 플래피로 오배달하지 않게).
     */
    fun miniGameRaw(kind: MiniGameKind): String? = when (kind) {
        MiniGameKind.timingBar -> AingMiniGame.TIMING.raw
        MiniGameKind.flappy -> AingMiniGame.FLAPPY.raw
        MiniGameKind.tetris -> AingMiniGame.TETRIS.raw
        MiniGameKind.crossy -> null
    }

    /** 라우트 글자 → 미니게임 종류(모르면 null). AingMiniGame 를 빠짐없이 가른다. */
    fun miniGameKind(raw: String): MiniGameKind? = when (AingMiniGame.fromRaw(raw)) {
        AingMiniGame.TIMING -> MiniGameKind.timingBar
        AingMiniGame.FLAPPY -> MiniGameKind.flappy
        AingMiniGame.TETRIS -> MiniGameKind.tetris
        null -> null
    }
}

/** 게임 탭 첫 화면(셸이 Dest.GamesHome 자리에 둔다). [open] 은 셸 내비게이션(목적지가 없으면 부르지 않는다). */
@Composable
fun GamesHubRoute(
    store: GamesStore,
    facts: GamesHubBoardFacts,
    now: () -> SwiftDate,
    open: (Any) -> Unit,
    onOpenShop: () -> Unit,
    onOpenRankings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GamesHubScreen(
        store = store,
        facts = facts,
        art = rememberMiniGameArt(),
        now = now,
        onOpen = { destination -> GamesRoutes.destination(destination)?.let(open) },
        onOpenShop = onOpenShop,
        onOpenRankings = onOpenRankings,
        modifier = modifier,
    )
}
