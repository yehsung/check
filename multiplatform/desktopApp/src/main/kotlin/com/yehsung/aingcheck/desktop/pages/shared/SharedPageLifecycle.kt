// 원본: multiplatform/androidApp/…/screens/{me/MeHomeRouteScreen.kt, rankings/RankingsRouteScreen.kt} (DisposableEffect{ tabDidAppear / onDispose tabDidDisappear })
// 원본: Sources/check/WorkTimerStoreMessages.swift @ a90d8623 — 760-783(팝오버 열기 = 메시지 새로고침 계기 · isMessagePanelVisible)
//
// W3-c0 — 플라이아웃 가시성 ↔ 페이지 수명. 폰은 화면이 구성에서 빠질 때 onDispose 가 부르지만, 플라이아웃 창은 **미리 만들어 숨긴다**
// (W3-c1) — 숨김은 구성 해제가 아니다. 그래서 페이지 활성은 핀(shellapi FlyoutNavigator)의 한 식으로만 정한다:
//     활성 페이지 = visible ? (그 순간의 페이지) : 없음
// 바뀔 때만 앞 페이지 disappear → 뒤 페이지 appear 를 부른다. 같은 열쇠(SharedPageKey)로 다시 들어오면 아무것도 부르지 않는다(중복 0).
//
// 플라이아웃 자체가 보이는가(visible)는 데스크톱의 '앱 활성'이다 — 메시지 스토어의 읽음 처리는 "앱이 active 이고 그 대화가 떠 있을 때만"
// (MessagesStore ②)이라, 숨기면 appDidEnterBackground 를 불러 숨은 창 뒤에서 읽음이 올라가지 않게 한다.
package com.yehsung.aingcheck.desktop.pages.shared

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged

/** 한 페이지의 수명 고리(없으면 그 페이지는 스스로 — 화면 안 DisposableEffect — 처리한다). */
class PageHooks(val appear: () -> Unit, val disappear: () -> Unit)

class SharedPageLifecycle(
    private val hooksFor: (SharedPageKey) -> PageHooks?,
    /** 플라이아웃이 보이기 시작/멈췄다(앱 활성). 페이지 appear 앞·disappear 뒤에 부른다. */
    private val onFlyoutActive: (Boolean) -> Unit = {},
) {
    private var activeKey: SharedPageKey? = null
    private var flyoutActive = false

    /** 지금 활성인 페이지 열쇠(시험이 읽는다). */
    val active: SharedPageKey? get() = activeKey

    fun update(visible: Boolean, page: SharedPage) {
        val nextKey = if (visible) SharedRouter.keyOf(page) else null
        if (visible && !flyoutActive) {
            flyoutActive = true
            onFlyoutActive(true)
        }
        if (nextKey != activeKey) {
            activeKey?.let { hooksFor(it)?.disappear?.invoke() }
            activeKey = nextKey
            nextKey?.let { hooksFor(it)?.appear?.invoke() }
        }
        if (!visible && flyoutActive) {
            flyoutActive = false
            onFlyoutActive(false)
        }
    }

    /** [visible]·[page] 흐름을 따라간다(돌아가는 동안). 끝날 때(구성 해제·로그아웃 조립 해제) 활성 페이지를 닫는다. */
    suspend fun follow(visible: Flow<Boolean>, page: Flow<SharedPage>) {
        try {
            combine(visible, page) { v, p -> v to p }.distinctUntilChanged().collect { (v, p) -> update(v, p) }
        } finally {
            update(false, SharedPage.Launching)
        }
    }
}
