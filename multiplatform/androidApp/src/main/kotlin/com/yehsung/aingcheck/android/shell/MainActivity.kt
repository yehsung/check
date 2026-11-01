// 단일 Activity(E§1.1). 매니페스트 launchMode = singleTask(E-U16):
//   딥링크 → 프로세스 죽음 → 런처 아이콘 순서에서도 같은 작업의 이 인스턴스가 onNewIntent 로 받는다(Activity 1개).
//   표준 모드에서는 작업 뿌리 Intent(VIEW)와 런처 Intent(MAIN)가 달라 시스템이 인스턴스를 하나 더 쌓았다(W0-f 실측).
// Intent 처리:
//   - onCreate: 저장 상태가 없을 때만 getIntent() 를 연다. 저장 상태가 있으면(회전·프로세스 죽음 복원) 화면은 이미 복원된 스택이다 —
//     같은 딥링크를 다시 열지 않는다.
//   - onNewIntent: 새 라우트를 연다. 런처(MAIN)·모르는 모양이면 아무것도 바꾸지 않는다(복원된 화면 그대로).
//   - 최근 앱(기록)에서 다시 띄운 작업 뿌리 Intent(FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)는 extra 째 다시 온다 — 수락은 버리고
//     화면만 연다(판돈이 걸린 respond 가 두 번 실리지 않게, G §8-13). 처리한 Intent 는 setIntent 로 라우트·수락 extra 를 지운다.
//   - 확성기 알림 탭(증표가 맞은 표식)은 라우터로 보내지 않고 푸시 조정자의 handleResponse(open)로 — 대화가 아니라 그 확성기 배너(Swift
//     PushCoordinator.handleResponse @ a6791165). 자리표시 셸(조립 화면 없음)이면 그 대화를 연다.
// 시스템 막대 글자색: androidx.activity 1.13 enableEdgeToEdge 는 **창의 첫 호출이 준 설정**을 숨은 View(EdgeToEdge$enableEdgeToEdge$1$2)에 물려 구성 변경마다 다시 돌리고, 둘째 호출부터는 그 View 를 갈지 않는다.
//   그래서 첫 호출이 기본값(OS 다크를 따른다)이면 configChanges 로 직접 받는 회전 · 다크 전환 때마다 글자가 OS 쪽으로 굳는다(앱 다크 · OS 라이트 = 검은 바탕에 검은 글자).
//   Activity.onConfigurationChanged 는 뷰 나무로 내려가기 **전**에 불려 거기서 고쳐도 덮인다. 답은 첫 호출부터 [barStyle] 하나를 쓰는 것이다 — 값을 잡지 않고 돌 때마다 묻는다.
package com.yehsung.aingcheck.android.shell

import android.content.Intent
import android.content.res.Configuration
import android.Manifest
import android.annotation.SuppressLint
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import com.yehsung.aingcheck.android.routing.RouteTargets
import androidx.lifecycle.lifecycleScope
import com.yehsung.aingcheck.android.screens.games.hub.GamesKeepScreenOn
import com.yehsung.aingcheck.android.screens.games.rummy.RummyOrientationDriver
import com.yehsung.aingcheck.feature.phone.push.PhonePushAction
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import android.content.res.Resources
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.material3.Surface
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.yehsung.aingcheck.android.app.AingApplication
import com.yehsung.aingcheck.android.routing.RouteIntents
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow

class MainActivity : ComponentActivity(), SystemBarIconHost {
    /** 열 라우트. 버퍼가 있어 화면이 그려지기 전에 온 요청도 잃지 않는다. */
    private val requests = Channel<RouteRequest>(Channel.BUFFERED)

    /** 이 창에 단 화면 꺼짐 방지 싱크를 푸는 일(스토어는 앱 수명이라 Activity 가 끝나면 풀어야 한다). */
    private var releaseKeepScreenOn: (() -> Unit)? = null
    private val container get() = (application as AingApplication).container

    /** 흰 글자를 쥔 화면 수([holdLightSystemBarIcons]). */
    private var lightIconHolds = 0

    /**
     * 막대 글자색의 한 곳 — 파일 머리말. 돌 때마다 지금 값을 묻는다(화면 모드 · OS 다크 · 흰 글자를 쥔 화면). 막대 칠은 투명이라 auto 여도 칠이 달라지지 않는다.
     * 판정은 Compose 쪽 AingTheme 과 같다(AingAppearanceMode.isDark · isSystemInDarkTheme = uiMode).
     */
    private val barStyle: SystemBarStyle = SystemBarStyle.auto(TRANSPARENT_SCRIM, TRANSPARENT_SCRIM) { resources -> barsAreDark(resources) }

    private fun barsAreDark(resources: Resources): Boolean {
        val systemDark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        return lightIconHolds > 0 || container.appearance.mode.isDark(systemDark)
    }

    private fun applySystemBars() {
        enableEdgeToEdge(statusBarStyle = barStyle, navigationBarStyle = barStyle)
        // auto 는 내비 막대 강제 대비를 켠다. 끈다 — 숨은 View 가 다시 켜므로 구성 변경 뒤에도 끈다(setContent 의 LaunchedEffect).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) window.isNavigationBarContrastEnforced = false
    }

    override fun holdLightSystemBarIcons(): () -> Unit {
        lightIconHolds += 1
        applySystemBars()
        var released = false
        return {
            if (!released) {
                released = true
                lightIconHolds -= 1
                applySystemBars()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        applySystemBars()
        super.onCreate(savedInstanceState)
        logIntent("onCreate", intent, restored = savedInstanceState != null)
        if (savedInstanceState == null) route(intent)
        val c = container
        // 조립 셸(K11): 화면 켜짐(대국 · 1:1 판 — W4-b §3)과 알림 권한 창(W2-f §3)을 이 Activity 에 단다. 자리표시 셸(셸 시험)은 null.
        val screens = c.shellScreens
        if (screens != null) {
            releaseKeepScreenOn = GamesKeepScreenOn.install(screens.phone.games, window)
            // 아잉 큐브 판 화면만 가로 — 답은 스토어 계산값, 옮기는 자리는 여기 하나다(RummyOrientationDriver).
            RummyOrientationDriver.install(screens.phone.games, lifecycleScope, ::applyRummyOrientation)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) c.pushSystem.permissionRequester = permissionRequester
        }
        setContent {
            val phase by c.shellPhase.collectAsStateWithLifecycle()
            // 흐름 하나를 붙잡아 둔다 — 다시 그릴 때마다 새로 만들면 수집이 끊겼다 다시 붙으며 받은 요청을 흘릴 수 있다.
            val requestFlow = remember { requests.receiveAsFlow() }
            // 아잉체크 테마(M3 뼈대 + iOS 파랑 주요색, G §8-15). 인자 없는 MaterialTheme 은 M3 기준 보라(#6750A4)로 칠한다(DesignRules D4).
            // 화면 모드(W3-b 조정자 패치 0002): 저장값(기본 다크 — iOS 와 같은 키)을 따른다. 상태 막대 글자색도 같은 판정으로 맞춘다([barStyle]) —
            // enableEdgeToEdge 기본값은 OS 설정을 따라 앱이 다크로 고정된 낮에 검은 글자가 검은 바탕에 앉는다.
            // 모드를 고르면 구성 변경이 없으니 여기서 다시 칠하고, 구성 변경 뒤엔 숨은 View 가 켠 내비 강제 대비를 여기서 다시 끈다(그 View 다음 프레임이다).
            val mode = c.appearance.mode
            val dark = mode.isDark(isSystemInDarkTheme())
            val configuration = LocalConfiguration.current
            LaunchedEffect(dark, configuration) { applySystemBars() }
            AingTheme(mode = mode) {
                Surface {
                    AingShell(
                        phase = phase,
                        requests = requestFlow,
                        onVisibleRoute = c.visibleRoute::setRoute,
                        onAccept = { route ->
                            // 증표가 맞은 수락의 기록(기기 시나리오 E-U16 이 읽는다). 조립 셸이면 푸시 조정자가 응답 · 화면 열기를 한다(W2-f §3) —
                            // 판돈 깃발이 꺼진 빌드는 코어가 수락 RPC 를 내지 않고 그 신청 화면만 연다(§8-17 #1).
                            c.pendingInviteAccept.value = route
                            if (screens != null) {
                                c.mainScope.launch {
                                    RouteTargets.acceptContent(route)?.let { screens.phone.push.handleResponse(it, PhonePushAction.acceptInvite) }
                                }
                            }
                        },
                        app = screens,
                    )
                }
            }
        }
    }

    private fun applyRummyOrientation(orientation: GamesRummyInterfaceOrientation) {
        requestedOrientation = RummyOrientationDriver.activityOrientation(orientation, resources.configuration.smallestScreenWidthDp)
    }

    /** 구성이 바뀌어도 다시 만들어지지 않는다(매니페스트 configChanges — 화면은 Compose 가 다시 잰다). 접었다 펴면 폰 ↔ 큰 화면이 바뀌니 값을 다시 옮긴다. 같은 값이면 시스템이 아무 일도 안 한다. */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        container.shellScreens?.let { applyRummyOrientation(it.phone.games.rummyInterfaceOrientation) }
    }

    private companion object {
        /** 막대 칠(투명 — ARGB 0). 색은 테마가 칠한 바탕이 비쳐 보인다(D5: 셸은 색을 손으로 만들지 않는다). */
        const val TRANSPARENT_SCRIM: Int = 0
    }

    /** 알림 권한 창(API 33+). 등록은 STARTED 전(필드 초기화)이어야 한다. */
    private var pendingPermission: CancellableContinuation<Boolean>? = null
    // lint InvalidFragmentVersionForActivityResult 는 FragmentActivity 의 옛 onRequestPermissionsResult 결함 경고다. 이 Activity 는
    // ComponentActivity(Fragment 없음)라 해당 없다 — 옛 fragment 는 Firebase 의존이 끌고 온 전이 의존일 뿐이다.
    @SuppressLint("InvalidFragmentVersionForActivityResult")
    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        pendingPermission?.takeIf { it.isActive }?.resume(granted)
        pendingPermission = null
    }
    private val permissionRequester: suspend () -> Boolean = {
        suspendCancellableCoroutine { cont ->
            pendingPermission = cont
            permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    override fun onDestroy() {
        releaseKeepScreenOn?.invoke()
        releaseKeepScreenOn = null
        if (container.pushSystem.permissionRequester === permissionRequester) container.pushSystem.permissionRequester = null
        pendingPermission?.takeIf { it.isActive }?.resume(false)
        pendingPermission = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        logIntent("onNewIntent", intent, restored = false)
        route(intent)
    }

    private fun route(intent: Intent?) {
        val incoming = RouteIntents.read(intent) ?: return
        // 증표는 수락을 요청한 Intent 에서만 꺼낸다(처음 쓸 때 만들어 저장한다 — 화면만 여는 딥링크에 디스크 쓰기를 붙이지 않는다).
        // 기록에서 다시 온 Intent 의 수락을 버리는 문은 parse 한 곳이다(시험이 그 한 곳을 잰다 — 겹문으로 가리지 않는다).
        val proof = if (incoming.acceptExtra || incoming.megaphoneIdExtra != null) container.routeProof.value() else null
        val request = RouteIntents.parse(incoming, expectedProof = proof)
        if (intent != null && (incoming.routeExtra != null || incoming.acceptExtra || incoming.proofExtra != null || incoming.megaphoneIdExtra != null)) {
            setIntent(RouteIntents.consumed(intent))
        }
        // 기기 시나리오(E-U16 · §8-13)가 읽는 한 줄. 증표는 있었는지(참·거짓)만 싣는다 — 값은 싣지 않는다.
        container.logger.log(
            LogLevel.INFO, "AingShell",
            "route accept=${request?.accept} history=${incoming.launchedFromHistory} proof=${incoming.proofExtra != null} opened=${request != null}" +
                " megaphone=${request?.megaphone != null}",
        )
        val megaphone = request?.let(RouteTargets::megaphoneTapContent)
        val screens = container.shellScreens
        if (megaphone != null && screens != null) {
            container.mainScope.launch { screens.phone.push.handleResponse(megaphone, PhonePushAction.open) }
            return
        }
        request?.let { requests.trySend(it) }
    }

    /** 작업·인스턴스 시험(E-U16 기기 시나리오)이 읽는 한 줄. 라우트 id 만 싣는다(본문·토큰 없음). */
    private fun logIntent(where: String, intent: Intent?, restored: Boolean) {
        container.logger.log(
            LogLevel.INFO, "AingShell",
            "$where restored=$restored task=$taskId action=${intent?.action} instance=${System.identityHashCode(this)}",
        )
    }
}
