// 원본: Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift:76-83 @ 3bd04bd (onAppear: 주사율 읽기 · openScreen / onDisappear: closeScreen)
//
// 미니게임 화면의 Android 껍데기(§8-4 — 본문은 ui/games/minigame GamesMiniGameScreen). 셸이 Dest.MiniGame(game) 자리에 둔다(assembly.md).
// 이 껍데기가 Android 에서만 아는 넷을 모아 넘긴다: ① 디스플레이 주사율 ② **장면 수명**(Activity ON_PAUSE·ON_RESUME + 창 초점 — iOS .inactive·.active 축. 판을 그 자리에서 얼리고 돌아오면
// 상한을 잰다, iOS MobileRootView.swift:73-75 @ de5c153b. 알림 창 · 전원 메뉴는 ON_PAUSE 없이 창 초점만 거둔다) ③ 시스템 '동작 줄이기'(애니메이터 배율 0) ④ 미니게임 그림.
package com.yehsung.aingcheck.android.screens.games.minigame

import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.yehsung.aingcheck.android.screens.games.hub.GamesRoutes
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.ui.games.minigame.GamesMiniGameScreen
import com.yehsung.aingcheck.ui.games.minigame.rememberMiniGameArt
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop

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
    MiniGameSceneLifecycle(store)
    GamesMiniGameScreen(
        store = store,
        kind = kind,
        refreshHz = rememberDisplayRefreshHz(),
        art = rememberMiniGameArt(),
        myUserID = myUserID,
        modifier = modifier,
        onBack = onBack,
        reduceMotion = rememberReduceMotion(),
        isPhone = true,
    )
}

/**
 * ON_PAUSE(iOS .inactive — 앱 전환 · 잠금 · 다중 창) → 판을 **그 자리에서** 얼리고 임시 항목을 적는다 · ON_RESUME → 상한을 재고 토큰을 챙긴다(풀지는 않는다).
 * 관찰자가 스토어를 바로 부른다 — 값으로 넘겨 다음 합성을 기다리면 멈춘 Activity 에는 그 프레임이 안 오고, 프로세스 ON_STOP 은 700ms 늦어 그 사이 앱을 쓸어 올려 죽이면 점수가 사라진다.
 * 창 초점도 같은 두 문이다(iOS .inactive 의 '알림 센터 내리기'): 알림 창 · 전원 메뉴 · 시스템 대화상자는 Activity 를 RESUMED 로 둔 채 입력만 가져가, 판이 사람 없이 흘러 끝난다. 그 Activity 는 멈추지 않아 프레임이 계속 오므로 스냅숏 흐름으로 충분하다.
 * 앱 안 대화상자도 별도 창이라 함께 언다 — 판 위에 창이 떠서 조작을 못 하는 것은 같다. 첫 값은 변화가 아니다.
 */
@Composable
private fun MiniGameSceneLifecycle(store: GamesStore) {
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner, store) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> store.sceneWillResignActive()
                Lifecycle.Event.ON_RESUME -> store.sceneDidComeForward()
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    val window = LocalWindowInfo.current
    LaunchedEffect(window, store) {
        snapshotFlow { window.isWindowFocused }.drop(1).distinctUntilChanged().collect { focused ->
            if (focused) store.sceneDidComeForward() else store.sceneWillResignActive()
        }
    }
}

/** 시스템 '동작 줄이기'(애니메이터 배율 0 = 애니메이션 끔). 흔들림·튀어 오름 같은 장식만 끈다 — 규칙·속도는 그대로다. */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }.getOrDefault(false)
    }
}
