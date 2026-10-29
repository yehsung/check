// 원본: Sources/CheckMobileKit/App/MobileAppModel.swift · MobileRootView.swift @ ios-1014 (앱 모델 한 벌 → 탭 화면 · 이동 요청)
// 조립 파일(K11, 7차): 폰 앱 모델(W2-f PhoneAppModel) 하나를 화면 갈래(W3-a · W3-b · W4-a · W4-b · W4-c · W5-c) 진입 함수가 받는 값으로 푼다.
// 스토어를 새로 만들지 않는다 — 세션 · 지금 · 메시지 · 순위 · 나 · 게임 스토어와 루비 칸은 전부 앱 모델의 한 벌이다(§8-18 4 "같은 루비 칸").
// NavGraph · AingShell 은 이 값이 null 이면 자리표시를 그린다(셸 시험이 화면 없이 탭 · 딥링크만 잰다).
package com.yehsung.aingcheck.android.nav

import androidx.navigation.NavHostController
import com.yehsung.aingcheck.android.lifecycle.AppLifecycle
import com.yehsung.aingcheck.android.routing.RouteTargets
import com.yehsung.aingcheck.android.screens.account.AndroidAccountCleanup
import com.yehsung.aingcheck.android.screens.games.chess.ChessRoute
import com.yehsung.aingcheck.android.screens.games.gomoku.GomokuRoute
import com.yehsung.aingcheck.android.screens.me.MeDestinations
import com.yehsung.aingcheck.android.screens.now.NowWorkActions
import com.yehsung.aingcheck.android.screens.session.W3aScreenDeps
import com.yehsung.aingcheck.android.screens.settings.NotificationPrimerPort
import com.yehsung.aingcheck.android.screens.settings.PushPrefsSaves
import com.yehsung.aingcheck.android.screens.settings.PushSettingsPort
import com.yehsung.aingcheck.android.screens.settings.SessionPushSettingsPort
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.now.NowWorkOrigin
import com.yehsung.aingcheck.feature.phone.app.PhoneAppModel
import com.yehsung.aingcheck.feature.phone.push.PhonePushAuthorization
import com.yehsung.aingcheck.feature.phone.push.PhonePushKind
import com.yehsung.aingcheck.feature.phone.push.PhonePushText
import com.yehsung.aingcheck.feature.phone.routing.PhoneNavRequest
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import com.yehsung.aingcheck.ui.screens.settingscommon.NotificationPrimerContent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * 화면 갈래 진입 함수의 의존 한 벌(앱에 하나 — AppContainer 가 만든다. 계측 시험은 스텁 서버의 앱 모델로 같은 것을 만든다).
 *
 * @param accountCleanup 계정 삭제 뒤 이 기기 정리(알림 서랍 · FCM 토큰 · 위젯 — W3-b).
 * @param screenArt 그림 캐시(초상 · 이모티콘 · 사진 — 앱에 하나, W3-a §4).
 */
class AppScreens(
    val phone: PhoneAppModel,
    val appearance: AppearanceStore,
    val prefs: KeyValueStore,
    val lifecycle: AppLifecycle,
    val currentBuild: Long,
    val accountCleanup: AndroidAccountCleanup,
    val screenArt: ScreenArt,
    /** 알림 권한 설명 시트를 띄울 때(W2-f AndroidPushSystem.isPrimerVisible). */
    val primerVisible: StateFlow<Boolean> = MutableStateFlow(false),
) {
    /** W3-a 화면(세션 · 지금 · 메시지). 착용 캐릭터 · 루비는 나 탭 스토어(같은 루비 칸)에서 읽는다. */
    val w3a: W3aScreenDeps = W3aScreenDeps(
        session = phone.session,
        messages = phone.messages,
        now = phone.now,
        nowWork = PhoneNowWork(phone),
        characterID = { phone.me.equippedServerID },
        rubyBalance = { phone.me.rubyBalance },
        currentBuild = currentBuild,
    )

    /** 설정 화면의 서버 선호값 문(세션 스토어의 기기 등록 응답 · savePushPrefs — 푸시 조정자와 같은 원천). */
    val pushSettings: PushSettingsPort = SessionPushSettingsPort(phone.session)

    /** 알림 종류 저장 줄 — 세션 자리에서 돈다(설정 화면을 떠나도 저장이 끝나 세션 값이 서버를 따른다 — iOS 비구조 Task 와 같다). */
    val pushPrefsSaves: PushPrefsSaves = PushPrefsSaves(pushSettings, phone.session.scope)

    /** 알림 권한 설명 시트(글자는 W2-f 한 벌). */
    val primerContent: NotificationPrimerContent = NotificationPrimerContent(
        title = PhonePushText.primerTitle,
        body = PhonePushText.primerBody,
        macNote = PhonePushText.primerMacNote,
        settingsNote = PhonePushText.primerSettingsNote,
        allow = PhonePushText.primerAllow,
        later = PhonePushText.primerLater,
        kinds = PhonePushKind.entries.map { NotificationPrimerContent.Kind(it.rawValue, it.settingTitle, it.settingDetail) },
    )

    val primerPort: NotificationPrimerPort = object : NotificationPrimerPort {
        override val isRequesting: Boolean get() = phone.push.isRequestingAuthorization
        override suspend fun allow() = phone.push.primerAllow()
        override fun later() = phone.push.primerLater()
    }

    /** 내 근무 상태(지금 탭 내 카드 — 없으면 null). 나 탭 무대 · 순위 내 얼굴 · 대국 내 얼굴이 같은 판정을 쓴다. */
    fun myMood(): CharacterMood? = phone.now.myCard(phone.environment.clock.now())?.let { card ->
        if (card.isWorking) (if (card.isStale) CharacterMood.Lost else CharacterMood.Working) else CharacterMood.Off
    }

    /** 대국 화면의 내 얼굴(W4-a §4). 로그인 전이면 모름. */
    fun boardGameMe(): BoardGameMe =
        if (!phone.session.isSignedIn) BoardGameMe.unknown
        else BoardGameMe(name = phone.me.displayName, characterID = phone.me.equippedServerID, mood = myMood() ?: CharacterMood.Off)
}

/** 지금 탭 근무 버튼 문(W2-f PhoneWorkController 를 그대로 옮긴다 — 화면은 판정을 다시 적지 않는다). */
class PhoneNowWork(private val phone: PhoneAppModel) : NowWorkActions {
    override val showsWorkControl: Boolean get() = phone.work.showsWorkControl
    override val showsDisabledWorkControlForNoTeam: Boolean get() = phone.work.showsDisabledWorkControlForNoTeam
    override val isMyWorkOpen: Boolean get() = phone.work.isMyWorkOpen
    override val myWorkOrigin: NowWorkOrigin get() = phone.work.myWorkOrigin
    override val isPushDenied: Boolean get() = phone.push.authorization == PhonePushAuthorization.denied
    override suspend fun clockIn() = phone.work.clockIn()
    override suspend fun clockOut() = phone.work.clockOut()
}

/**
 * 폰 라우터의 이동 요청(W2-f §3 표)을 NavController 로 옮긴다. 딥링크 · 알림 · 허브 카드가 모두 이 한 문을 지난다
 * (셸이 router.open 을 직접 부르지 않는다 — PhoneSourceContractTest).
 */
object NavRequests {
    fun apply(request: PhoneNavRequest, nav: NavHostController, navigator: ShellNavigator) {
        when (request) {
            is PhoneNavRequest.Open -> RouteTargets.route(request.target)?.let(navigator::open)
            is PhoneNavRequest.PresentGames -> {
                navigator.popToRoot(com.yehsung.aingcheck.android.routing.AingTab.GAMES)
                val dest: Any? = when (val d = request.destination) {
                    GamesDestination.Gomoku -> GomokuRoute.lobby()
                    GamesDestination.Chess -> ChessRoute.lobby()
                    GamesDestination.TetrisDuel -> Dest.TetrisDuel
                    is GamesDestination.MiniGame -> RouteTargets.miniGame(d.kind)?.let { Dest.MiniGame(it.raw) }
                }
                dest?.let { nav.navigate(it) { launchSingleTop = true } }
            }
            is PhoneNavRequest.PushMe -> {
                navigator.selectTab(com.yehsung.aingcheck.android.routing.AingTab.ME)
                MeDestinations.dest(request.destination)?.let { nav.navigate(it) }
            }
            is PhoneNavRequest.PopToRoot -> navigator.popToRoot(RouteTargets.tab(request.tab))
        }
    }
}

/** 탭 뿌리로(탭 막대 다시 누름 · PopToRoot). */
fun ShellNavigator.popToRoot(tab: com.yehsung.aingcheck.android.routing.AingTab) {
    selectTab(tab)
    val root = RoutePlans.defaultRoot(tab)
    nav.popBackStack(root, inclusive = false)
}
