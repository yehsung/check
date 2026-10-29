// 원본: Sources/CheckMobileKit/Now/NowTab.swift @ 3bd04bd (TimelineView(.periodic) — 1초 · 1분마다 다시 센다)
//
// 화면 시각. 시각은 스토어 시계에서만 읽는다(구조 시험 R2 — 벽시계는 조립 지점에서만 만든다). 이 함수는 [everySeconds] 마다 다시 그리게만 한다.
// 스냅숏·계측 시험은 [LocalScreenTicking] 을 꺼 멈춘 시계로 그린다(무한 타이머가 있으면 Compose 시험의 '쉼'이 오지 않는다).
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.delay

@Composable
fun rememberNow(clock: SessionClock, everySeconds: Int): SwiftDate {
    val ticking = LocalScreenTicking.current
    var tick by remember { mutableIntStateOf(0) }
    if (ticking) {
        LaunchedEffect(everySeconds) {
            while (true) {
                delay(everySeconds * 1_000L)
                tick += 1
            }
        }
    }
    // 읽어서 구독한다(값은 버린다 — 시각은 언제나 시계에서).
    check(tick >= 0)
    return clock.now()
}
