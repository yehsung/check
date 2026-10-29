// 원본: Sources/CheckMobileKit/Me/MeFeedbackView.swift @ 3bd04bd (제보 화면 — 딥링크 feedback/<id> 는 MeStore.open(MeRoute.Feedback) 이 가리킨다)
//
// 제보 껍데기(Android). 딥링크·알림이 가리킨 제보는 라우터(W2-f)가 MeStore.open(MeRoute.Feedback(id)) 로 스토어에 적고 이 화면이 펼친다
// (목적지 인자 reportId 는 내비 복원용으로만 들고, 스토어를 다시 가리키지 않는다 — 두 번 가리키면 같은 화면이 한 칸 더 쌓인다).
package com.yehsung.aingcheck.android.screens.me

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.ui.screens.me.FeedbackScreen

@Composable
fun FeedbackRouteScreen(store: MeStore, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    FeedbackScreen(store, scope, modifier)
}
