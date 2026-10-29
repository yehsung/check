// 원본: Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift:76-83 @ 3bd04bd (onAppear: 주사율 읽기 · openScreen / onDisappear: closeScreen)
//
// 미니게임 화면의 Android 껍데기(§8-4 — 본문은 ui/games/minigame GamesMiniGameScreen). 셸이 Dest.MiniGame(game) 자리에 둔다(assembly.md).
// 이 껍데기가 Android 에서만 아는 넷을 모아 넘긴다: ① 디스플레이 주사율 ② **초점**(Activity ON_PAUSE·ON_RESUME — 멀티 창에서 앱이 산 채로 초점을
// 잃으면 판을 얼린다, G §8-2) ③ 시스템 '동작 줄이기'(애니메이터 배율 0) ④ 미니게임 그림.
package com.yehsung.aingcheck.android.screens.games.minigame

import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.yehsung.aingcheck.android.screens.games.hub.GamesRoutes
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.ui.games.minigame.GamesMiniGameScreen
import com.yehsung.aingcheck.ui.games.minigame.rememberMiniGameArt

/**
 * 미니게임 화면(셸 목적지 Dest.MiniGame). 라우트 글자가 이 빌드에 **보이지 않는** 게임이면(모르는 글자 · 표시 깃발 밖) 화면을 세우지 않고 [onBack] 으로
 * 돌아간다(허브가 연 적 없는 게임을 딥링크가 열지 않게 — GamesStore.routeStep 과 같은 규칙).
 */
@Composable
fun MiniGameRoute(store: GamesStore, game: String, myUserID: String?, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val kind = GamesRoutes.miniGameKind(game)?.takeIf { MiniGameExposure.isVisible(it) }
    if (kind == null) {
        LaunchedEffect(game) { onBack() }
        return
    }
    GamesMiniGameScreen(
        store = store,
        kind = kind,
        refreshHz = rememberDisplayRefreshHz(),
        art = rememberMiniGameArt(),
        myUserID = myUserID,
        modifier = modifier,
        onBack = onBack,
        windowFocused = rememberWindowFocused(),
        reduceMotion = rememberReduceMotion(),
    )
}

/** Activity 가 ON_RESUME 상태인가(멀티 창에서 다른 앱이 초점을 가져가면 ON_PAUSE). iOS .inactive 와 같은 축 — 판을 끝내지 않고 얼리기만 한다. */
@Composable
fun rememberWindowFocused(): Boolean {
    val owner = LocalLifecycleOwner.current
    var focused by remember(owner) { mutableStateOf(owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(owner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> focused = true
                Lifecycle.Event.ON_PAUSE -> focused = false
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    return focused
}

/** 시스템 '동작 줄이기'(애니메이터 배율 0 = 애니메이션 끔). 흔들림·튀어 오름 같은 장식만 끈다 — 규칙·속도는 그대로다. */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }.getOrDefault(false)
    }
}
