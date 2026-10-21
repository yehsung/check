// 자리표시 — 순위 탭(E§3.2). 주인: W3-b. 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.rankings

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RankingsBoard
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

@Composable
fun RankingsHomePlaceholder(board: String) = PlaceholderScreen(
    "순위", "W3-b 순위", detail = RankingsBoard.fromRaw(board)?.let { AingRoute.Rankings(it).url } ?: "board=$board",
)
