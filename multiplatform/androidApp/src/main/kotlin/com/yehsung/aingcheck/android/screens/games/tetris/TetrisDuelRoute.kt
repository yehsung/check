// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift:197-218 @ 3bd04bd (화면 수명 · scenePhase 를 대결 판에 넘김)
//
// 1:1 테트리스 화면의 Android 껍데기(본문은 ui/games/tetris GamesTetrisDuelScreen). 셸이 Dest.TetrisDuel 자리에 둔다(assembly.md).
// 앱 앞/뒤(프로세스 수명 — AppLifecycle.isForeground)를 판에 넘긴다: 뒤로 가면 눌린 것을 놓는다(판은 멎지 않고 15초 침묵에 진다 — 화면의 경고 줄이 말한다).
// 판돈 대결 신청·수락 진입은 **duelsEnabled** 가 켜진 빌드에서만 보인다(G §8-17 1) — 깃발은 스토어가 문맥(appConfig)으로 읽는다(이 껍데기는 BuildConfig 를
// 직접 읽지 않는다 — 원천은 조립의 AndroidAppConfig 한 곳).
package com.yehsung.aingcheck.android.screens.games.tetris

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yehsung.aingcheck.android.lifecycle.AppLifecycle
import com.yehsung.aingcheck.android.screens.games.minigame.rememberDisplayRefreshHz
import com.yehsung.aingcheck.android.screens.games.minigame.rememberReduceMotion
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.ui.games.tetris.GamesTetrisDuelScreen

@Composable
fun TetrisDuelRoute(
    store: GamesStore,
    lifecycle: AppLifecycle,
    myUserID: String?,
    meName: String?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val foreground by lifecycle.isForeground.collectAsStateWithLifecycle()
    GamesTetrisDuelScreen(
        store = store,
        myUserID = myUserID,
        refreshHz = rememberDisplayRefreshHz(),
        modifier = modifier,
        onBack = onBack,
        appActive = foreground,
        reduceMotion = rememberReduceMotion(),
        meName = meName,
    )
}
