// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 3bd04bd (NowTab — 경로 · 주간 목표 시트 · 위젯 탭 딥링크는 탭 자체)
//
// 지금 탭 진입 함수(조립 K11 이 NavGraph 의 자리표시 줄을 이것으로 바꾼다 — assembly.md). aingcheck://now(위젯 탭)는 탭 자체라 쌓는 화면이 없다.
package com.yehsung.aingcheck.android.screens.now

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.ui.screens.session.kit.SheetHeader
import com.yehsung.aingcheck.ui.theme.AingDimens

/**
 * 지금 탭 뿌리(Dest.NowHome). [openRoute] 는 다른 탭 화면을 연다(말 걸기 → 메시지 탭 대화 — 셸의 ShellNavigator.open).
 * [work] 는 폰 근무 문(W2-f NowStorePhoneWork — 없으면 버튼 줄 없음). [characterID] 는 나 탭이 아는 착용 캐릭터.
 */
@Composable
fun NowHomeEntry(
    store: NowStore,
    work: NowWorkActions?,
    characterID: String?,
    open: (Any) -> Unit,
    openRoute: (AingRoute) -> Unit,
    modifier: Modifier = Modifier,
) {
    NowScreen(
        store = store,
        work = work,
        characterID = characterID,
        onTalk = { peer -> AingRoute.safeId(peer)?.let { openRoute(AingRoute.Message(it)) } },
        onEditGoal = { open(Dest.TeamGoalSheet) },
        modifier = modifier,
    )
}

/** 주간 목표 시트(Dest.TeamGoalSheet). 저장하면 닫는다. */
@Composable
fun TeamGoalSheetEntry(store: NowStore, dismiss: () -> Unit) {
    NowGoalSheet(store, onClose = dismiss)
}

/** 팀 합류 시트(Dest.TeamJoinSheet) — 무소속 카드와 같은 한 벌을 시트로. 팀이 정해지면 스토어가 지금 탭을 다시 그린다. */
@Composable
fun TeamJoinSheetEntry(store: NowStore, dismiss: () -> Unit) {
    Column {
        SheetHeader(NowText.noTeamTitle, dismiss, closeLabel = NowText.close)
        Box(Modifier.padding(horizontal = AingDimens.sideMargin)) { NowTeamJoinSection(store.teamJoin) }
    }
}
