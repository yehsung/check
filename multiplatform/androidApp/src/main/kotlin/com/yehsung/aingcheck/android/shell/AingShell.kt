// 원본: Sources/CheckMobileKit/App/MobileRootView.swift:51-64(루트 단계 분기) · AingRoute.swift(AingTab) @ ios-1011(988609b)
// 루트 단계: 실행 중 → 업데이트 필요 → 로그인 → 탭(E§3). 탭 막대는 지금·메시지·순위·게임·나.
// edge-to-edge 는 끌 수 없다(API 36, E§1.3) — Scaffold 가 막대·제스처 영역 인셋을 나눠 준다.
// 라우트(딥링크·알림)는 로그인 전이면 기다렸다가 탭 단계가 되면 연다(iOS "실행 복원 중이면 끝날 때까지 기다린다").
package com.yehsung.aingcheck.android.shell

import androidx.compose.runtime.CompositionLocalProvider
import com.yehsung.aingcheck.android.nav.AppScreens
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.nav.NavRequests
import com.yehsung.aingcheck.android.routing.RouteTargets
import com.yehsung.aingcheck.android.screens.session.LaunchEntry
import com.yehsung.aingcheck.android.screens.session.UpdateRequiredEntry
import com.yehsung.aingcheck.android.screens.shop.CakeGiftSheetRoute
import com.yehsung.aingcheck.android.screens.stage.AingStage
import com.yehsung.aingcheck.android.screens.stage.StageAssets
import com.yehsung.aingcheck.android.screens.stage.StageClock
import com.yehsung.aingcheck.android.screens.stage.StageHandle
import com.yehsung.aingcheck.android.widget.rankingsMood
import com.yehsung.aingcheck.ui.screens.session.kit.rememberPortrait
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.ui.screens.session.kit.LocalAppUserCharacters
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenArt
import com.yehsung.aingcheck.ui.shop.LiveCharacterPreview
import com.yehsung.aingcheck.ui.shop.LocalLiveCharacterPreview
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.ui.components.LocalModalPresence
import com.yehsung.aingcheck.ui.components.ModalPresence
import com.yehsung.aingcheck.feature.phone.app.syncMegaphoneBannerDeferral
import com.yehsung.aingcheck.feature.phone.messages.MegaphoneBannerPhoneRules
import kotlinx.coroutines.delay
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.yehsung.aingcheck.android.nav.CurrentDest
import com.yehsung.aingcheck.android.nav.RoutePlans
import com.yehsung.aingcheck.android.nav.SessionNavHost
import com.yehsung.aingcheck.android.nav.ShellNavigator
import com.yehsung.aingcheck.android.nav.ShellTabBarRules
import com.yehsung.aingcheck.android.nav.TabsNavHost
import com.yehsung.aingcheck.android.routing.AingRoute
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
 * @param app 조립(K11) 화면 의존 한 벌. null 이면 자리표시 셸(셸 시험 — 탭 · 딥링크 · 단계만 잰다).
 */
@Composable
fun AingShell(
    phase: ShellPhase,
    requests: Flow<RouteRequest>,
    onVisibleRoute: (AingRoute?) -> Unit,
    onAccept: (AingRoute) -> Unit,
    app: AppScreens? = null,
) {
    if (app != null) {
        AssembledShell(phase, requests, onVisibleRoute, onAccept, app)
        return
    }
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
                    // 자리표시 셸에는 나 탭 얼굴 원천(앱 모델)이 없다 — 사람 기호로 접는다. 배지도 없다.
                    AingTabBar(
                        selected = { tab -> destination?.hierarchy?.any { it.hasRoute(RoutePlans.graphOf(tab)::class) } == true },
                        badge = { 0 },
                        meFace = null,
                        onSelect = { tab -> navigator.selectTab(tab) },
                    )
                },
            ) { padding ->
                TabsNavHost(navController, Modifier.padding(padding))
            }
        }
    }
}

/** 세션 단계(W2-a) → 셸 단계. 다른 실행이 가드를 쥐었으면 실행 중 화면에 머문다(세션을 시작하지 않는다). */
object ShellPhases {
    fun of(phase: SessionPhase): ShellPhase = when (phase) {
        SessionPhase.Launching, SessionPhase.AnotherInstanceRunning -> ShellPhase.LAUNCHING
        is SessionPhase.NeedsUpdate -> ShellPhase.NEEDS_UPDATE
        SessionPhase.SignedOut -> ShellPhase.SIGNED_OUT
        SessionPhase.SignedIn -> ShellPhase.SIGNED_IN
    }
}

/**
 * 조립 셸(K11, 7차): 단계 화면은 W3-a 진입 함수, 탭은 화면 갈래 진입 함수(NavGraph), 이동은 폰 라우터 한 문(W2-f §3).
 * 딥링크 · 알림은 앱 모델의 handleOpenRoute 로 넘긴다(실행 복원 중이면 붙잡았다가 로그인되면 연다 — 로그아웃으로 끝나면 버린다).
 */
@Composable
private fun AssembledShell(
    phase: ShellPhase,
    requests: Flow<RouteRequest>,
    onVisibleRoute: (AingRoute?) -> Unit,
    onAccept: (AingRoute) -> Unit,
    app: AppScreens,
) {
    val phone = app.phone
    LaunchedEffect(requests) {
        requests.collect { request ->
            // [수락]은 푸시 조정자가 세션을 기다렸다가 응답 · 화면 열기를 한다(onAccept → handleResponse). 화면만 여는 링크는 라우터 한 문.
            if (request.accept) onAccept(request.route) else phone.handleOpenRoute(RouteTargets.target(request.route))
        }
    }
    CompositionLocalProvider(
        LocalScreenArt provides app.screenArt,
        LocalAppUserCharacters provides phone.characters.directory,
        // W5-c 살아 있는 미리보기(고르기 머리 · 선물 받은 뒤 그림 — W4-c §5).
        LocalLiveCharacterPreview provides shellLivePreview(),
    ) {
        when (phase) {
            ShellPhase.LAUNCHING -> LaunchEntry()
            ShellPhase.NEEDS_UPDATE -> UpdateRequiredEntry((phone.session.phase as? SessionPhase.NeedsUpdate)?.minBuild ?: 0L, app.currentBuild)
            ShellPhase.SIGNED_OUT -> {
                LaunchedEffect(Unit) { onVisibleRoute(null) }
                SessionNavHost(rememberNavController(), screens = app.w3a)
            }
            ShellPhase.SIGNED_IN -> SignedInTabs(onVisibleRoute, app)
        }
    }
}

@Composable
private fun SignedInTabs(onVisibleRoute: (AingRoute?) -> Unit, app: AppScreens) {
    val phone = app.phone
    val navController = rememberNavController()
    val navigator = remember(navController) { ShellNavigator(navController) }
    val entry by navController.currentBackStackEntryAsState()
    val destination = entry?.destination
    var screenHidesTabBar by remember { mutableStateOf(false) }
    LaunchedEffect(entry) { onVisibleRoute(entry?.let { RoutePlans.routeOf(CurrentDest.of(it)) }) }
    // 폰 라우터의 이동 요청(딥링크 · 알림 · 허브 · 나 탭 고리)을 차례로 옮긴다. 일련번호가 바뀔 때마다 깬다(같은 요청이 다시 와도).
    val serial = phone.router.requestSerial
    LaunchedEffect(serial) { phone.router.drainRequests().forEach { NavRequests.apply(it, navController, navigator) } }
    // 알림 권한 설명 시트(W2-f §3): 푸시 시스템이 띄우라고 하면 대화상자 목적지로, 내리라고 하면 닫는다.
    val primer by app.primerVisible.collectAsState()
    LaunchedEffect(primer) {
        val showing = navController.currentDestination?.hasRoute(Dest.NotificationPrimerSheet::class) == true
        if (primer && !showing) navController.navigate(Dest.NotificationPrimerSheet)
        if (!primer && showing) navController.popBackStack()
    }
    // 탭 막대 숨김 표는 한 자리(ShellTabBarRules — iOS TabBarPolicy 화면 전부 + 뽑기 기계). 오목·체스 판은 화면이 알리고(W4-a),
    // 그 알림은 위에 대화상자가 떠도 살아 있게 표 밖에서도 한 번 더 본다.
    val play = ShellTabBarRules.Play(tetrisMatch = phone.games.tetris.match != null, boardScreenHides = screenHidesTabBar)
    val hideTabBar = screenHidesTabBar || ShellTabBarRules.hidesTabBar(destination, play)
    // 확성기 배너 미룸(iOS MegaphoneBannerModalProbe): 대화상자 목적지(시트 · 알림 권한 설명)나 화면 안에서 직접 띄운 시트·대화상자
    // (ModalBottomSheet · AlertDialog — 액티비티 위 별도 창, LocalModalPresence 로 센다)가 떠 있으면 배너가 그 밑에 깔린다 — 미룬다.
    // 창 수가 바뀌면 바로 맞추고, 그 밖의 미룸 판정(목적지 · 대결 화면 · 미니게임 판)은 다시 보기 고리가 1초마다 맞춘다(배너가 떠 있거나 기다릴 때만).
    val modals = remember(phone) { ModalPresence(onChange = { phone.syncMegaphoneBannerDeferral() }) }
    phone.megaphoneModalProbe = ShellMegaphoneDeferral.modalProbe({ navController.currentDestination?.navigatorName }, modals)
    val banner = phone.megaphoneBanner
    val pollKey = MegaphoneBannerPhoneRules.deferralPollKey(banner.current?.megaphoneID, banner.queue.size)
    LaunchedEffect(pollKey, destination, phone.games.isAnyMatchScreenVisible) {
        phone.syncMegaphoneBannerDeferral()
        while (pollKey != null) {
            delay((MegaphoneBannerPhoneRules.deferralPollSeconds * 1000).toLong())
            phone.syncMegaphoneBannerDeferral()
        }
    }
    CompositionLocalProvider(LocalModalPresence provides modals) {
    Box(Modifier.fillMaxSize()) {
    Scaffold(
        bottomBar = {
            if (!hideTabBar) {
                AingTabBar(
                    selected = { tab -> destination?.hierarchy?.any { it.hasRoute(RoutePlans.graphOf(tab)::class) } == true },
                    badge = { tab -> phone.badges.badge(RouteTargets.tab(tab)) ?: 0 },
                    meFace = rememberMeTabFace(app),
                    onSelect = { tab ->
                        navigator.selectTab(tab)
                        phone.tabDidChange(RouteTargets.tab(tab))
                    },
                )
            }
        },
    ) { padding ->
        // 뽑기 기계처럼 배경을 막대 뒤까지 까는 목적지는 셸 여백을 받지 않는다(ShellSystemBarRules — 내용 inset 은 그 화면이 스스로 단다).
        // 여백은 화면마다 입는다(NavGraph.shellScreen) — 여기서 꼭대기 목적지로 가르면 전환 동안 나가는 화면이 튄다.
        TabsNavHost(navController, shellBars = padding, app = app, onTabBarHidden = { screenHidesTabBar = it })
    }
    // 확성기 배너 — 어느 탭이든 위에서 내려온다(iOS TabView .overlay(alignment: .top)). 카드만 손을 받는다.
    MegaphoneBannerOverlay(banner, modifier = Modifier.align(Alignment.TopCenter))
    }
    // 생일 선물 고르기 창 — 어느 탭에 있든 뜬다(W4-c §4, 스토어가 대국 · 관전 중엔 스스로 안 띄운다).
    CakeGiftSheetRoute(phone.me)
    }
}

/** 셸의 확성기 배너 미룸 판정 한 자리(AingShell 이 쓰고 ShellMegaphoneDeferralTest 가 같은 함수를 잰다). */
internal object ShellMegaphoneDeferral {
    /** 대화상자 목적지 **또는** 화면 안 시트·대화상자가 하나라도 떠 있으면 참. [navigatorName] = 지금 목적지의 navigator 이름. */
    fun modalProbe(navigatorName: () -> String?, modals: ModalPresence): () -> Boolean =
        { navigatorName() == "dialog" || modals.isPresented }
}

/**
 * 셸이 꽂는 살아 있는 미리보기(W5-c — 고르기 머리 · 케이크 시트 · 뽑기 공개 자리). **공개 번호 0 = 아직 공개 없음 → 열쇠 없음**:
 * 0 을 열쇠로 넘기면 고르기 머리 · 케이크 시트(둘 다 revealSerial 기본 0)가 처음 열릴 때마다 한 바퀴 돈다. iOS 는 그 두 자리가 정지 초상
 * (MeCakeGiftViews `CharacterPortrait(framed: false)`)이라 열 때 돌지 않는다. 1 이상(뽑기 결과)만 새 값마다 한 바퀴.
 * [assets] · [clock] · [handle] 은 시험이 넘긴다(AingStageComposeTest).
 */
internal fun shellLivePreview(assets: StageAssets? = null, clock: StageClock = StageClock.System, handle: StageHandle? = null): LiveCharacterPreview =
    LiveCharacterPreview { id, size, m, serial ->
        AingStage(id, null, m, artSize = size, revealKey = serial.takeIf { it > 0 }, assets = assets ?: StageAssets.of(LocalContext.current), clock = clock, handle = handle)
    }

/** '나' 탭 얼굴(iOS meLabel — CharacterTabIcon(displayedCharacterID, displayedMood)). 그림을 아직 못 읽었으면 art = null → 사람 기호. */
@Composable
private fun rememberMeTabFace(app: AppScreens): MeTabFace {
    val p = app.phone
    val snapshot = p.widgets.current
    val face = ShellTabFace.of(
        equippedLoaded = p.me.equippedLoaded,
        equippedCharacterID = p.me.equippedServerID,
        snapshotCharacterID = snapshot?.characterID,
        nowCard = p.now.myCard(p.environment.clock.now()),
        snapshotMood = snapshot?.rankingsMood(),
    )
    val id = face.characterID ?: DEFAULT_CHARACTER
    val art = rememberPortrait(id, face.mood.expression)
    return MeTabFace(art, face.mood, id)
}

private const val DEFAULT_CHARACTER = "aing"
