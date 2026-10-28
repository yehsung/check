// 원본: Sources/CheckMobileKit/Me/MeTab.swift @ 3bd04bd (MeTab — 탭 수명 · 하위 화면 목적지 · navigationDestination 표)
//
// 나 탭 껍데기(Android). 공용 루트(ui …/screens/me MeHomeScreen)를 감싸 탭 수명(tabDidAppear/Disappear)과 하위 화면 목적지(MeDestination → Dest)를 잇는다.
// 무대 자리([stage])는 W5-c 살아 있는 미리보기(androidApp …/screens/stage)가 채운다 — 크기 계약은 ui MeStageSpec(칸 138×144 dp).
// 조립(K11)은 NavGraph 의 MeHomePlaceholder 줄을 이 화면으로 바꾸고 [open] 에 NavController.navigate(MeDestinations.dest(it)) 를 넘긴다(assembly.md).
package com.yehsung.aingcheck.android.screens.me

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeStageMood
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.ui.screens.me.MeHomeScreen
import com.yehsung.aingcheck.ui.screens.me.MeStageContent
import com.yehsung.aingcheck.ui.screens.me.MeStageDefaults

@Composable
fun MeHomeRouteScreen(
    store: MeStore,
    presence: MeStageMood?,
    open: (MeDestination) -> Unit,
    modifier: Modifier = Modifier,
    stage: MeStageContent = MeStageDefaults.Static,
    cakeGiftRow: @Composable () -> Unit = {},
) {
    val scope = rememberCoroutineScope()
    DisposableEffect(store) {
        store.tabDidAppear()
        onDispose { store.tabDidDisappear() }
    }
    MeHomeScreen(store, presence, open, scope, modifier, stage = stage, cakeGiftRow = cakeGiftRow)
}

/** 나 탭 하위 화면(MeDestination) → 내비 목적지(Dest). 목적지가 아직 없는 화면은 null(보고 — 조립이 Dest 를 더한다). */
object MeDestinations {
    fun dest(destination: MeDestination): Any? = when (destination) {
        MeDestination.Shop -> Dest.Shop
        MeDestination.Characters -> Dest.CharacterPicker
        MeDestination.Profile -> Dest.Profile
        MeDestination.Feedback -> Dest.Feedback()
        MeDestination.Settings -> Dest.Settings
        MeDestination.Blocked -> Dest.BlockedPeople
        is MeDestination.Grass -> Dest.GrassDetail(destination.axis.name)
        // v1.0.13 「미션」 화면(W4-c ui/missions)은 Dest 에 자리가 없다 — 조립이 Dest.Missions 를 더하고 여기를 잇는다(assembly.md).
        MeDestination.Missions -> null
    }
}
