// 원본: Sources/CheckMobileKit/Me/MeBlockedPeopleView.swift @ 3bd04bd (나 → 설정 → 차단한 사람 — 목록·해제는 메시지 스토어가 쥔다)
//
// 차단한 사람 껍데기(Android). 메시지 스토어(c.messages — W3-a 화면과 같은 한 벌)를 받아 공용 화면에 넘긴다.
package com.yehsung.aingcheck.android.screens.settings

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.ui.screens.settingscommon.BlockedPeopleScreen

@Composable
fun BlockedPeopleRouteScreen(messages: MessagesStore?, modifier: Modifier = Modifier) {
    BlockedPeopleScreen(messages, modifier)
}
