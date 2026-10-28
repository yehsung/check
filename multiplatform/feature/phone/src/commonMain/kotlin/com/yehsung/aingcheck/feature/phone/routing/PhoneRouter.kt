// 원본: Sources/CheckMobileKit/Routing/MobileRouter.swift @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.routing

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesRouter
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.messages.MessagesRouterLink

/** 탭 다섯(Swift `AingTab` — 순서가 곧 탭 막대 순서). Android 셸의 `AingTab` 과 1:1 이다(조립의 변환이 빠짐없는 when 으로 잇는다). */
enum class PhoneTab { now, messages, rankings, games, me }

/**
 * 셸(Android NavGraph — 조립 K11)에게 내는 **이동 요청** 하나. Swift 는 라우터가 탭별 `NavigationPath` 를 직접 쥐었지만, Android 는 탭별
 * 백스택을 NavController 가 쥔다 — 그래서 스토어·푸시가 낸 이동은 요청으로 쌓고 셸이 꺼내 목적지로 옮긴다([PhoneRouter.drainRequests]).
 */
sealed interface PhoneNavRequest {
    /** 그 탭으로 가서 쌓인 화면을 비우고 [target] 을 연다(Swift `router.open(route)`). */
    data class Open(val target: PhoneRouteTarget) : PhoneNavRequest

    /** 게임 탭을 고르고 · 쌓인 화면을 비우고 · [destination] 을 쌓는다(W2-e [GamesRouter.present]). */
    data class PresentGames(val destination: GamesDestination) : PhoneNavRequest

    /** 나 탭에 하위 화면을 한 칸 쌓는다(Swift `router.push(_:on: .me)`). */
    data class PushMe(val destination: MeDestination) : PhoneNavRequest

    /** 그 탭 경로를 뿌리로(Swift `router.popToRoot(_:)`). */
    data class PopToRoot(val tab: PhoneTab) : PhoneNavRequest
}

/**
 * 탭 선택 · 이동 요청 · 지금 보이는 대화(SPEC-ios §3 · SPEC-ios-build §1-7). 스토어가 화면 이동을 부탁하는 **유일한 문**이다:
 * 게임 탭(W2-e [GamesRouter]) · 메시지 탭(W2-b [MessagesRouterLink] — 보이는 대화) · 나 탭(W2-c MeLinks 의 pushMe · popMeToRoot) ·
 * 푸시 조정자([com.yehsung.aingcheck.feature.phone.push.PhonePushCoordinator] — [수락] 뒤 대국 열기).
 *
 * - [open] 은 **탭을 고르고** 요청을 쌓는다. 요청은 쌓인 순서대로 셸이 한 번 꺼내 간다(꺼내면 비워진다 — 같은 링크를 두 번 여는 일이 없다).
 * - [requestSerial] 은 요청이 쌓일 때마다 +1 — 같은 요청이 다시 와도 관찰자가 깨어나게 한다(Swift `routeSerial`).
 * - [visibleConversationPeerID] 는 메시지 대화 화면이 나타남·사라짐에 맞춰 적는다(푸시 조정자가 앞에 있을 때 그 대화 알림을 숨기는 데 읽는다).
 */
class PhoneRouter : GamesRouter, MessagesRouterLink {
    var selectedTab: PhoneTab by mutableStateOf(PhoneTab.now)

    /** 요청이 쌓일 때마다 +1. */
    var requestSerial: Int by mutableStateOf(0)
        private set

    private val pending = ArrayList<PhoneNavRequest>()

    /** 마지막으로 연 대상(진단·시험). */
    var lastOpenedTarget: PhoneRouteTarget? = null
        private set

    /** 지금 화면에 떠 있는 대화의 상대(메시지 탭이 적는다). 앱이 background 면 null 로 본다(읽는 쪽이 앱 활성도 함께 본다). */
    override var visibleConversationPeerID: String? by mutableStateOf(null)

    /** 아직 셸이 꺼내 가지 않은 요청(시험·진단 — 꺼내지 않는다). */
    val pendingRequests: List<PhoneNavRequest> get() = pending.toList()

    /** 대상을 연다: 탭을 고르고, 셸이 그 탭 경로를 비운 뒤 대상을 쌓도록 요청한다. */
    fun open(target: PhoneRouteTarget) {
        selectedTab = target.tab
        lastOpenedTarget = target
        enqueue(PhoneNavRequest.Open(target))
    }

    /** W2-e: 게임 탭을 고르고 · 쌓인 화면을 비우고 · 목적지를 쌓는다. */
    override fun present(destination: GamesDestination) {
        selectedTab = PhoneTab.games
        enqueue(PhoneNavRequest.PresentGames(destination))
    }

    /** 나 탭에 하위 화면을 한 칸 쌓는다. */
    fun pushMe(destination: MeDestination) {
        enqueue(PhoneNavRequest.PushMe(destination))
    }

    fun popToRoot(tab: PhoneTab) {
        enqueue(PhoneNavRequest.PopToRoot(tab))
    }

    /** 셸이 쌓인 요청을 꺼낸다(꺼내면 비운다). */
    fun drainRequests(): List<PhoneNavRequest> {
        if (pending.isEmpty()) return emptyList()
        val out = pending.toList()
        pending.clear()
        return out
    }

    /** 로그아웃(세대 교체). 선택 탭은 "지금"으로, 남은 요청·보이는 대화는 비운다. */
    fun reset() {
        selectedTab = PhoneTab.now
        pending.clear()
        visibleConversationPeerID = null
        lastOpenedTarget = null
    }

    private fun enqueue(request: PhoneNavRequest) {
        pending += request
        requestSerial += 1
    }
}

/**
 * 탭 배지 합성(SPEC-ios §3: 메시지 = 안 읽은 수, 게임 = 받은 오목 신청 수, 나 = 받을 보상 수). 값은 각 탭 스토어가 센다. 음수는 0 으로 접는다.
 * 앱 아이콘 배지(= 메시지 + 게임)는 푸시 조정자가 [appBadgeTotal] 을 읽는다.
 */
class PhoneBadges(messages: Int, games: Int, missions: Int = 0) {
    val messages: Int = maxOf(0, messages)
    val games: Int = maxOf(0, games)

    /** 나 탭 — 지금 받을 수 있는 보상 수(도전 미션 + 이번 주 근무 단계 · `MeStore.missionClaimableCount`). */
    val missions: Int = maxOf(0, missions)

    /** 탭 막대에 그릴 숫자. 0 이면 null(배지 없음). 지금 · 순위는 배지가 없다. */
    fun badge(tab: PhoneTab): Int? = when (tab) {
        PhoneTab.messages -> messages.takeIf { it > 0 }
        PhoneTab.games -> games.takeIf { it > 0 }
        PhoneTab.me -> missions.takeIf { it > 0 }
        PhoneTab.now, PhoneTab.rankings -> null
    }

    /**
     * 앱 아이콘(홈 화면)의 숫자. **미션은 더하지 않는다**(v0.3.58) — 받을 보상은 사람을 홈 화면에서 부를 일이 아니고, 더하면 앱을 안 열어도
     * 아이콘에 숫자가 붙은 채로 남는다. 미션은 **탭 막대 배지**로만 말한다.
     */
    val appBadgeTotal: Int get() = messages + games

    override fun equals(other: Any?): Boolean =
        other is PhoneBadges && other.messages == messages && other.games == games && other.missions == missions

    override fun hashCode(): Int = (messages * 31 + games) * 31 + missions

    override fun toString(): String = "PhoneBadges(messages=$messages, games=$games, missions=$missions)"
}
