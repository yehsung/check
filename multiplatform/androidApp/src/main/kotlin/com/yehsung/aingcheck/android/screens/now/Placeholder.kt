// 자리표시 — 지금 탭(E§3.2). 주인: W3-a. 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.now

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.shell.PlaceholderLink
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

private const val OWNER = "W3-a 지금"

@Composable
fun NowHomePlaceholder(open: (Any) -> Unit) = PlaceholderScreen(
    "지금", OWNER, detail = AingRoute.Now.url,
    links = listOf(PlaceholderLink("주간 목표") { open(Dest.TeamGoalSheet) }, PlaceholderLink("팀 합류") { open(Dest.TeamJoinSheet) }),
)

@Composable
fun TeamGoalSheetPlaceholder() = PlaceholderScreen("주간 목표 시트", OWNER)

@Composable
fun TeamJoinSheetPlaceholder() = PlaceholderScreen("팀 합류 시트", OWNER)
