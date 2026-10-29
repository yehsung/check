// 원본: Sources/check/WorkTimerStore.swift @ a90d8623 — 3335-3345(로그인·실행 직후 안 읽은 메시지 요약 1회 — "근무 밖에서 쌓인 메시지가
//       팝오버를 열기 전에도 메뉴바 점으로 뜨는 근거")
// 원본: Sources/check/WorkTimerStoreMessages.swift @ a90d8623 — 60(messageMenuRefreshThrottleSeconds = 60) · Sources/check/WorkTimerStorePoke.swift 24
//       (pokePollIntervalSecondsWhileSubscribed = 60 — 소켓이 조용히 죽은 경우의 안전망 주기)
//
// W-3 #13 — 플라이아웃이 닫힌 동안에도 안 읽음 점(트레이 빨간 점 — W3-c1 TrayDotReasons.unreadMessages)이 서야 한다. 폰 스토어의 갱신은
// 탭 수명에 묶여 있어(listDidAppear) 닫힌 플라이아웃에선 아무도 부르지 않는다. 그래서 **로그인 동안** 요약을 맥 주기(60초)로 받는다.
//  - 로그인 직후 1회 + 60초마다 1회. 요약만(includeHistory=false) — 이력은 스토어가 "낡음"으로 적어 화면이 설 때 받는다(MessagesStore ④).
//  - 로그아웃(참 → 거짓)에서 멈추고 [onSignedOut] 을 1회 부른다(조립이 messages.reset() — 앞 사람의 점이 다음 사람에게 남지 않게, ⑤).
//  - 실시간 소켓(W2-g2)이 붙으면 그 신호가 먼저 갚는다. 이 주기는 안전망이다 — 겹치면 스토어가 뒤따르는 한 번으로 합친다(③).
// ⚠️ 신청·메시지 점은 근무 여부를 보지 않는다(shell.md §2 ⑥) — 이 갱신에 근무 조건을 붙이지 마라.
package com.yehsung.aingcheck.desktop.pages.shared

import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

class MessagesBackgroundRefresh(
    /** 로그인 여부(조립: session.phaseFlow.map { it == SessionPhase.SignedIn }). */
    private val signedIn: Flow<Boolean>,
    /** 요약 1회(조립: { messages.requestActivityRefresh() } — 스스로 로그인을 확인하고 겹치면 합친다). */
    private val refresh: () -> Unit,
    /** 로그인 → 로그아웃 전이 1회(조립: { messages.reset() }). 처음부터 로그아웃이면 부르지 않는다. */
    private val onSignedOut: () -> Unit = {},
    private val intervalMillis: Long = INTERVAL_SECONDS * 1000,
) {
    fun start(scope: CoroutineScope): Job = scope.launch {
        var wasSignedIn = false
        signedIn.distinctUntilChanged().collectLatest { on ->
            if (!on) {
                if (wasSignedIn) onSignedOut()
                wasSignedIn = false
                return@collectLatest
            }
            wasSignedIn = true
            while (true) {
                refresh()
                delay(intervalMillis)
            }
        }
    }

    companion object {
        /** 맥 messageMenuRefreshThrottleSeconds · pokePollIntervalSecondsWhileSubscribed 와 같은 눈금(60초). */
        const val INTERVAL_SECONDS: Long = 60
    }
}

/** 안 읽음 점(≥1) 흐름 — W3-c1 트레이 점 사유가 읽는다. [badgeCount] 는 스냅숏 상태(MessagesStore.badgeCount)를 읽는 함수. */
object MessagesUnreadDot {
    fun flow(badgeCount: () -> Int): Flow<Boolean> = snapshotFlow { badgeCount() > 0 }.distinctUntilChanged()
}
