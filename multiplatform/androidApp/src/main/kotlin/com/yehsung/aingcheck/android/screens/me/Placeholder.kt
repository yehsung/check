// 자리표시 — 나 탭(E§3.2). 주인: W3-b(상점·뽑기는 W4-c — screens/shop). 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.me

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.shell.PlaceholderLink
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

private const val OWNER = "W3-b 나"

@Composable
fun MeHomePlaceholder(open: (Any) -> Unit) = PlaceholderScreen(
    "나", OWNER, detail = AingRoute.Me.url,
    links = listOf(
        PlaceholderLink("상점") { open(Dest.Shop) },
        PlaceholderLink("캐릭터") { open(Dest.CharacterPicker) },
        PlaceholderLink("프로필") { open(Dest.Profile) },
        PlaceholderLink("제보") { open(Dest.Feedback()) },
        PlaceholderLink("잔디") { open(Dest.GrassDetail("work")) },
        PlaceholderLink("설정") { open(Dest.Settings) },
    ),
)

@Composable
fun CharacterPickerPlaceholder() = PlaceholderScreen("캐릭터 고르기", OWNER)

@Composable
fun ProfilePlaceholder() = PlaceholderScreen("프로필", OWNER, detail = "사진 · 별명 · 상태메시지 40자")

@Composable
fun FeedbackPlaceholder(reportId: String?) = PlaceholderScreen("제보", OWNER, detail = AingRoute.Feedback(reportId).url)

@Composable
fun GrassDetailPlaceholder(axis: String) = PlaceholderScreen("잔디 상세", OWNER, detail = "axis=$axis")
