// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: xplat-w1/briefs/shell.md §4 1~3 + pins.md E 조정 ⑦(갈래 폴더가 아니라 조정자 자리 shellapi/).
// c1(창·OS)·c0(감싸기·레일·라우터)·W5-b(말풍선)가 같은 라우트 판정을 쓴다. 바꿀 일은 coordinator_patches 로.
package com.yehsung.aingcheck.desktop.shellapi

import androidx.compose.runtime.Composable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 대화에 어디서 들어왔나(뒤로 가기 판정). */
enum class Entry { MESSAGES, OVERLAY, NOTIFICATION }

sealed interface FlyoutRoute {
    data object Home : FlyoutRoute
    data object Messages : FlyoutRoute
    data class Conversation(val peerId: String, val from: Entry) : FlyoutRoute
    /** board = RankingsBoard.raw. */
    data class Rankings(val board: String) : FlyoutRoute
    data object Records : FlyoutRoute
    /** 내 기록의 잔디 상세(W-6 #3). axis = MeGrassAxis.name("work"·"token") — 모르는 값은 c0 이 work 로 읽는다. */
    data class Grass(val axis: String) : FlyoutRoute
    data object Missions : FlyoutRoute
    data object Settings : FlyoutRoute
    data object Profile : FlyoutRoute
    data object Characters : FlyoutRoute
    data object Feedback : FlyoutRoute
    data object Blocked : FlyoutRoute
    data object AccountDeletion : FlyoutRoute
    data object PinToTaskbar : FlyoutRoute
    data object Shop : FlyoutRoute

    // c2~c4 자리(다음 웨이브 — c0 은 '준비 중' 자리표시로 둔다)
    data object PokeList : FlyoutRoute
    data object Ultra : FlyoutRoute
    data object AiTokens : FlyoutRoute
    data object AiLimits : FlyoutRoute
    data object Devices : FlyoutRoute
    data object DesktopSettings : FlyoutRoute
}

/** 판정 공유(규약 3) — c1(알림 클릭)·W5-b(말풍선)·c0(목록)이 **이 함수만** 부른다. */
object FlyoutRoutes {
    /** sender null → PokeList(poke 깃발 꺼짐이면 Messages), 있으면 그 대화. */
    fun forMessageArrival(senderId: String?, pokeEnabled: Boolean, from: Entry = Entry.NOTIFICATION): FlyoutRoute =
        when {
            senderId == null -> if (pokeEnabled) FlyoutRoute.PokeList else FlyoutRoute.Messages
            else -> FlyoutRoute.Conversation(senderId, from)
        }

    /** Home 은 뒤가 없다. 목록에서 온 대화 → Messages, OVERLAY·NOTIFICATION 에서 온 대화 → Home, 잔디 상세 → 내 기록, 나머지 → Home. */
    fun backOf(route: FlyoutRoute): FlyoutRoute? = when (route) {
        FlyoutRoute.Home -> null
        is FlyoutRoute.Conversation -> if (route.from == Entry.MESSAGES) FlyoutRoute.Messages else FlyoutRoute.Home
        is FlyoutRoute.Grass -> FlyoutRoute.Records
        else -> FlyoutRoute.Home
    }
}

/** 열기 문(판정 공유) — 구현은 c1, c0 은 받아 쓴다. 페이지 활성 = `visible && route 가 그 페이지`. */
interface FlyoutNavigator {
    val visible: StateFlow<Boolean>
    val route: StateFlow<FlyoutRoute>
    fun open(route: FlyoutRoute? = null)
    fun navigate(route: FlyoutRoute)
    fun back()
    fun hide()
}

/** 페이지 호스트(값만) — c1 의 창은 이것만 그리고, c0 이 구현한다. */
fun interface FlyoutPageHost {
    @Composable
    fun Content(nav: FlyoutNavigator, widthDip: Double)
}

/** 최소 구현(시험·조립 전). 창은 없다 — 상태만 옮긴다. back() 은 FlyoutRoutes.backOf 를 따른다(없으면 숨김). */
class InMemoryFlyoutNavigator(initial: FlyoutRoute = FlyoutRoute.Home) : FlyoutNavigator {
    private val visibleState = MutableStateFlow(false)
    private val routeState = MutableStateFlow(initial)
    override val visible: StateFlow<Boolean> = visibleState.asStateFlow()
    override val route: StateFlow<FlyoutRoute> = routeState.asStateFlow()

    override fun open(route: FlyoutRoute?) {
        if (route != null) routeState.value = route
        visibleState.value = true
    }

    override fun navigate(route: FlyoutRoute) {
        routeState.value = route
    }

    override fun back() {
        val prev = FlyoutRoutes.backOf(routeState.value)
        if (prev == null) hide() else routeState.value = prev
    }

    override fun hide() {
        visibleState.value = false
    }
}
