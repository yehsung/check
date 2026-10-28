// 원본: Sources/CheckMobileKit/Push/PushPermissionPrimerView.swift @ 3bd04bd ([알림 켜기] → coordinator.primerAllow() · [나중에] → primerLater())
//
// 알림 설명 시트 껍데기(Android). 권한 요청 · '나중에 = 7일 쉼'은 W2-f 푸시 조정자(PhonePushCoordinator.primerAllow · primerLater)가 하고,
// 글자 · 종류 표도 W2-f(PhonePushText · PhonePushKind)의 것이다 — 조립이 [content] 와 [port] 를 그것으로 채운다(assembly.md). 이 화면은 그리기와 누름만.
package com.yehsung.aingcheck.android.screens.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationPrimerContent
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationPrimerSheet
import kotlinx.coroutines.launch

/** 설명 시트의 동작 문(조립이 W2-f PhonePushCoordinator 로 잇는다). */
interface NotificationPrimerPort {
    val isRequesting: Boolean
    suspend fun allow()
    fun later()
}

@Composable
fun NotificationPrimerRouteScreen(content: NotificationPrimerContent, port: NotificationPrimerPort, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    NotificationPrimerSheet(
        content = content,
        isRequesting = port.isRequesting,
        onAllow = { scope.launch { port.allow() } },
        onLater = { port.later() },
        modifier = modifier,
    )
}
