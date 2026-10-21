// 자리표시 — 설정(E§3.2 · §6.5 두 겹 스위치). 주인: W3-b. 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.settings

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.shell.PlaceholderLink
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

private const val OWNER = "W3-b 설정"

@Composable
fun SettingsPlaceholder(open: (Any) -> Unit) = PlaceholderScreen(
    "설정", OWNER, detail = AingRoute.Settings.url,
    links = listOf(
        PlaceholderLink("알림 켜기 안내") { open(Dest.NotificationPrimerSheet) },
        PlaceholderLink("차단한 사람") { open(Dest.BlockedPeople) },
        PlaceholderLink("계정 삭제") { open(Dest.AccountDeletion) },
    ),
)

@Composable
fun BlockedPeoplePlaceholder() = PlaceholderScreen("차단한 사람", OWNER)

@Composable
fun NotificationPrimerPlaceholder() = PlaceholderScreen("알림 켜기 안내", OWNER, detail = "설명 시트 먼저 · 나중에 = 7일 쉼")
