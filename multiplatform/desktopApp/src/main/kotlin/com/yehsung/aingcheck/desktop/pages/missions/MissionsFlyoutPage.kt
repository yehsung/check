// 원본: Sources/check/CheckMenuView.swift(미션 = 팝오버 패널 — 레일 [미션]) · 0.3.64 미션 화면
//       (W4-f — 조정자 결정 W-3 #3: 미션은 플라이아웃 페이지. 라우트는 shellapi FlyoutRoute.Missions. 화면은 공용 ui 그대로)
package com.yehsung.aingcheck.desktop.pages.missions

import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.ui.missions.MeMissionsScreen

/**
 * 미션 페이지. 받기 · 당겨 새로 고침 · 주간 게이지는 화면 안(공용 ui). 뒤로 = 플라이아웃 뒤로.
 * @param reduceMotion 시스템 '애니메이션 줄이기'(SPI_GETCLIENTAREAANIMATION — 값은 조립 지점이 넘긴다).
 */
class MissionsFlyoutPage(
    private val store: MeStore,
    private val reduceMotion: () -> Boolean = { false },
) : FlyoutPageHost {
    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        MeMissionsScreen(
            store = store,
            onBack = { nav.back() },
            modifier = Modifier.width(widthDip.dp).fillMaxHeight(),
            reduceMotion = reduceMotion(),
        )
    }

    companion object {
        val route: FlyoutRoute = FlyoutRoute.Missions
    }
}
