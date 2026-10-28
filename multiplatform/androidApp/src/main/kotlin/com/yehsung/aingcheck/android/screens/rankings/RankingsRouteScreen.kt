// 원본: Sources/CheckMobileKit/Rankings/RankingsTab.swift @ 3bd04bd (onAppear consumeRoute · tabDidAppear/Disappear · 세그먼트 바꾸기)
//
// 순위 탭 껍데기(Android). 공용 화면(ui …/screens/rankings RankingsScreen)을 감싸 두 가지를 더한다:
//  ① 딥링크·프로세스 죽음 복원(⑥): 목적지 인자(Dest.RankingsHome.board — 딥링크 `aingcheck://rankings/<board>` 가 정한 판)는 NavController 저장 상태로
//     프로세스 죽음 뒤에도 돌아오지만 스토어는 새로 만들어져 기본(팀 리그)이다. 사용자가 고른 판은 rememberSaveable 에 적는다. 다시 그릴 때
//     RankingsBoardRestore 가 고른 판(저장 선택 → 인자)을 스토어에 건다.
//  ② 탭 수명: 보이면 tabDidAppear(낡은 판 다시 읽기) · 사라지면 tabDidDisappear — 보이지 않는 탭은 서버를 두드리지 않는다.
// 조립(K11)은 NavGraph 의 RankingsHomePlaceholder 줄을 이 화면으로 바꾼다(assembly.md).
package com.yehsung.aingcheck.android.screens.rankings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.ui.screens.rankings.RankingsBoardRestore
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.screens.rankings.RankingsScreen

/**
 * @param boardArg 목적지 인자(RankingsBoard.raw — `league` · `tokens` · `minigame`).
 * @param me 내 행 얼굴(조립이 나 탭·지금 탭·위젯 스냅숏에서 만든다 — RankingsScreenRules.myFace).
 */
@Composable
fun RankingsRouteScreen(store: RankingsStore, boardArg: String, me: RankingsMyFace, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    // 사용자가 고른 판(프로세스 죽음 뒤에도 남는다). null = 아직 안 골랐다 → 인자(딥링크)가 정한다.
    var saved by rememberSaveable { mutableStateOf<String?>(null) }
    val target = RankingsBoardRestore.boardToApply(boardArg, saved)
    LaunchedEffect(target) {
        if (target != null && store.board != target) store.open(target)
    }
    DisposableEffect(store) {
        store.tabDidAppear()
        onDispose { store.tabDidDisappear() }
    }
    RankingsScreen(
        store = store,
        me = me,
        scope = scope,
        onSelectBoard = { board ->
            saved = board.rawValue
            store.select(board)
        },
        modifier = modifier,
    )
}
