// 자리표시 — 상점·뽑기(E§3.2 · §9.4). 주인: W4-c. 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.shop

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.shell.PlaceholderLink
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

private const val OWNER = "W4-c 상점"

@Composable
fun ShopPlaceholder(open: (Any) -> Unit) = PlaceholderScreen(
    "상점", OWNER, detail = AingRoute.Shop.url,
    links = listOf(PlaceholderLink("확률 보기") { open(Dest.GachaOddsSheet) }, PlaceholderLink("뽑기 기계") { open(Dest.GachaMachine) }),
)

@Composable
fun GachaOddsSheetPlaceholder() = PlaceholderScreen("확률 보기", OWNER, detail = "서버 shop_state.gacha.odds 순서 그대로")

@Composable
fun GachaMachinePlaceholder() = PlaceholderScreen("뽑기 기계", OWNER)
