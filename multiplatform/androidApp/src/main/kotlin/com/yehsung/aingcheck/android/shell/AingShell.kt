// 원본: Sources/CheckMobileKit/App/MobileRootView.swift:51-64(루트 단계 분기) · AingRoute.swift(AingTab) @ ios-1011(988609b)
// 루트 단계: 실행 중 → 업데이트 필요 → 로그인 → 탭(E§3). 탭 막대는 지금·메시지·순위·게임·나.
// edge-to-edge 는 끌 수 없다(API 36, E§1.3) — Scaffold 가 막대·제스처 영역 인셋을 나눠 준다.
// 라우트(딥링크·알림)는 로그인 전이면 기다렸다가 탭 단계가 되면 연다(iOS "실행 복원 중이면 끝날 때까지 기다린다").
package com.yehsung.aingcheck.android.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.yehsung.aingcheck.android.nav.CurrentDest
import com.yehsung.aingcheck.android.nav.RoutePlans
import com.yehsung.aingcheck.android.nav.SessionNavHost
import com.yehsung.aingcheck.android.nav.ShellNavigator
import com.yehsung.aingcheck.android.nav.TabsNavHost
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.android.screens.session.LaunchPlaceholder
import com.yehsung.aingcheck.android.screens.session.UpdateRequiredPlaceholder
import kotlinx.coroutines.flow.Flow

/** 루트 단계(iOS MobileRootView 의 분기). 원천은 세션 스토어(W2-a). */
enum class ShellPhase {
    LAUNCHING,
    NEEDS_UPDATE,
    SIGNED_OUT,
    SIGNED_IN,
}

/**
 * @param requests 열 라우트(딥링크·알림). 한 번씩 소비된다.
 * @param onVisibleRoute 지금 화면의 라우트(푸시 숨김 판정 — VisibleRoute).
 * @param onAccept 수락 증표가 맞은 신청 [수락](오목·체스 스토어가 respond 를 부른다 — W2-d).
 */
@Composable
fun AingShell(
    phase: ShellPhase,
    requests: Flow<RouteRequest>,
    onVisibleRoute: (AingRoute?) -> Unit,
    onAccept: (AingRoute) -> Unit,
) {
    // 로그인 전에 온 라우트는 탭 단계까지 기다린다. 프로세스 죽음 뒤에도 남도록 URL 글자로 저장한다(수락은 싣지 않는다 — 한 번만).
    var pendingUrl by rememberSaveable { mutableStateOf<String?>(null) }
    var pendingAccept by remember { mutableStateOf(false) }

    LaunchedEffect(requests) {
        requests.collect { request ->
            pendingUrl = request.route.url
            pendingAccept = request.accept
        }
    }

    when (phase) {
        ShellPhase.LAUNCHING -> LaunchPlaceholder()
        ShellPhase.NEEDS_UPDATE -> UpdateRequiredPlaceholder()
        ShellPhase.SIGNED_OUT -> {
            LaunchedEffect(Unit) { onVisibleRoute(null) }
            SessionNavHost(rememberNavController())
        }
        ShellPhase.SIGNED_IN -> {
            val navController = rememberNavController()
            val navigator = remember(navController) { ShellNavigator(navController) }
            val entry by navController.currentBackStackEntryAsState()
            val destination = entry?.destination
            LaunchedEffect(entry) { onVisibleRoute(entry?.let { RoutePlans.routeOf(CurrentDest.of(it)) }) }
            LaunchedEffect(pendingUrl) {
                val route = pendingUrl?.let(AingRoute::parse) ?: return@LaunchedEffect
                navigator.open(route)
                if (pendingAccept) onAccept(route)
                pendingUrl = null
                pendingAccept = false
            }
            Scaffold(
                bottomBar = {
                    NavigationBar(modifier = Modifier.testTag("tab-bar")) {
                        AingTab.entries.forEach { tab ->
                            val graph = RoutePlans.graphOf(tab)
                            val selected = destination?.hierarchy?.any { it.hasRoute(graph::class) } == true
                            NavigationBarItem(
                                selected = selected,
                                onClick = { navigator.selectTab(tab) },
                                // 탭 기호(Material Symbols 대응표)는 W1-e 몫 — 그때까지 점 하나. 색은 NavigationBarItem 이 내려 주는 기호 색
                                // (선택 = onSecondaryContainer = iOS tabSelected 파랑 · 안 선택 = onSurfaceVariant 회색). 파랑은 '선택'만 뜻한다(G §8-15) —
                                // primary 로 칠하면 안 고른 탭 다섯 개에도 파란 점이 찍힌다(ShellTabColorsTest).
                                icon = { Box(Modifier.size(10.dp).background(LocalContentColor.current, CircleShape)) },
                                label = { Text(tab.title) },
                                modifier = Modifier.testTag("tab:${tab.name.lowercase()}"),
                            )
                        }
                    }
                },
            ) { padding ->
                TabsNavHost(navController, Modifier.padding(padding))
            }
        }
    }
}
