// 원본: Sources/check/CheckMenuView.swift @ a90d8623 — 535-560(로그인 · 무소속 · 메인 분기) · 965-1085(오른쪽 레일) · 6583-(TeamlessPanel)
// 원본: multiplatform/androidApp/…/screens/{session/SessionEntries.kt, messages/MessagesEntries.kt, me/MeHomeRouteScreen.kt,
//       rankings/RankingsRouteScreen.kt, settings/SettingsRouteScreen.kt, account/AccountDeletionRouteScreen.kt} (얇은 껍데기 선례)
//
// W3-c0 — 플라이아웃 페이지 호스트(핀 shellapi.FlyoutPageHost 의 구현). c1 의 창은 이것만 그린다. 화면 본문은 ui/screens(공용 한 벌)를
// 그대로 부르고, 여기는 ① 라우트 → 페이지(SharedRouter) ② 레일 ③ 페이지 수명(SharedPageLifecycle — visible && route 한 식)
// ④ 로그아웃 확인 · 무소속 합류 · 대화 Enter(⑥)만 더한다.
//
// ⚠️ 창이 숨으면(visible=false) 페이지를 **그리지 않는다** — 화면 안 DisposableEffect(목록·대화·제보의 DidAppear/DidDisappear)도 같이
//    닫혀야 숨은 창 뒤에서 읽음이 올라가지 않는다. 수명 고리는 프레임과 무관하게 흐름(follow)으로 돈다(숨은 창은 프레임을 안 그린다).
// ⚠️ 배너는 여기 겹쳐 쌓지 않는다(shell.md §2 ⑤ — W3-c2). 색은 AingTheme 토큰만(D5 — desktopApp main 색 리터럴 금지).
// int-w3(W-14 #2·#9): 뿌리에서 차단 문구 판을 맥으로 준다(LocalBlockReportPlatform — 공용 20, 맥 WorkTimerStoreBlocks.swift:126 `.mac`:
// Windows 엔 '나' 탭이 없어 길 안내가 '설정 → 차단한 사람'). 로그인·프로필·캐릭터의 기기 문구도 Windows 판(LocalDesktopWording). 업데이트 필요 화면의 [업데이트] 목적지는 Store 제품 페이지
// (SharedPagesDeps.updateDestination = StoreUpdateDestination.windows — 생성 상수 STORE_PRODUCT_ID, 비면 AppLinks = 단추 숨김).
package com.yehsung.aingcheck.desktop.pages.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.clearText
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.rules.text.BlockReportPlatform
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.session.reset.PasswordResetStore
import com.yehsung.aingcheck.core.session.signup.SignUpStore
import com.yehsung.aingcheck.core.session.team.TeamJoinStore
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.deleteAccount
import com.yehsung.aingcheck.core.stores.me.settingsDidAppear
import com.yehsung.aingcheck.core.stores.me.settingsDidDisappear
import com.yehsung.aingcheck.core.stores.me.signOut
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.desktop.pages.onboarding.FirstRunOnboarding
import com.yehsung.aingcheck.desktop.shell.update.StoreUpdateDestination
import com.yehsung.aingcheck.desktop.shellapi.Entry
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoutes
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.SfSymbols
import com.yehsung.aingcheck.ui.missions.MeMissionsScreen
import com.yehsung.aingcheck.ui.screens.me.CharacterPickerScreen
import com.yehsung.aingcheck.ui.screens.me.FeedbackScreen
import com.yehsung.aingcheck.ui.screens.me.GrassDetailScreen
import com.yehsung.aingcheck.ui.screens.me.MeHomeScreen
import com.yehsung.aingcheck.ui.screens.me.ProfileScreen
import com.yehsung.aingcheck.ui.screens.messages.ConversationScreen
import com.yehsung.aingcheck.ui.screens.messages.LocalBlockReportPlatform
import com.yehsung.aingcheck.ui.screens.messages.MessagesListScreen
import com.yehsung.aingcheck.ui.screens.messages.MessagesMegaphoneSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesNewConversationSheet
import com.yehsung.aingcheck.ui.screens.rankings.RankingsBoardRestore
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.screens.rankings.RankingsScreen
import com.yehsung.aingcheck.ui.screens.session.LaunchScreen
import com.yehsung.aingcheck.ui.screens.session.LocalDesktopWording
import com.yehsung.aingcheck.ui.screens.session.LoginScreen
import com.yehsung.aingcheck.ui.screens.session.PasswordResetScreen
import com.yehsung.aingcheck.ui.screens.session.SessionGraphemes
import com.yehsung.aingcheck.ui.screens.session.SignUpScreen
import com.yehsung.aingcheck.ui.screens.session.TeamJoinFields
import com.yehsung.aingcheck.ui.screens.session.UpdateRequiredScreen
import com.yehsung.aingcheck.ui.screens.session.kit.isComposing
import com.yehsung.aingcheck.ui.screens.settingscommon.AccountDeletionScreen
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
import com.yehsung.aingcheck.ui.screens.settingscommon.BlockedPeopleScreen
import com.yehsung.aingcheck.ui.screens.settingscommon.SettingsActions
import com.yehsung.aingcheck.ui.screens.settingscommon.SettingsScreen
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch

/** 데스크톱 문구(맥·폰 문구가 '폰'을 말하는 자리만 — 나머지는 공용 문구를 그대로). */
object SharedText {
    const val teamlessBody = "소속된 팀이 없어요. 팀 코드를 입력해 합류하세요."
    // W-13 #8 · W-12 15시 사용자 결정: 데스크톱 자기 호칭은 'PC'.
    const val signOutConfirmMessage = "이 PC에서만 로그아웃돼요. 폰은 그대로예요."
    /** 공용 설정 맨 위 한 줄 — Windows 전용 설정(자동 실행·단축키·AI 사용 기록 동의·이용약관)으로 간다. */
    const val desktopSettingsEntry = "PC 설정"
    const val desktopSettingsEntryDetail = "자동 실행 · 단축키 · AI 사용 기록 · 이용약관"
    const val signOutCancel = "취소"
    const val pendingTitle = "준비 중이에요"
    const val pendingBody = "다음 업데이트에서 열려요."
    const val anotherInstance = "아잉체크가 이미 실행 중이에요. 작업 표시줄의 아이콘을 눌러 주세요."
    /**
     * 업데이트 필요 화면 단추(목적지가 Store 제품 페이지일 때만). 폰 'App Store 열기'(MobileSessionStore.swift:790) · 'Play 스토어 열기' 자리 —
     * 공용 SessionText.updateButton(WINDOWS) 는 목적지가 없던 때의 null 이라 여기 둔다(core 는 이 갈래 밖).
     */
    const val storeUpdateButton = "Microsoft Store 열기"
}

/** 조립(AppGraph — 조정자)이 넘기는 것. 스토어는 조립이 하나씩 만든다(이 호스트는 만들지 않는다). */
class SharedPagesDeps(
    val session: SessionStore,
    val sessionContext: SessionContext,
    val messages: MessagesStore,
    val rankings: RankingsStore,
    val me: MeStore,
    val appearance: AppearanceStore,
    val config: DesktopAppConfig,
    /** 이 빌드 번호(ClientIdentity.build) — 업데이트 필요 화면의 두 줄. */
    val currentBuild: Long,
    /** 순위 내 행 얼굴(조립이 나 스토어에서 만든다 — RankingsScreenRules.myFace). */
    val rankingsFace: () -> RankingsMyFace,
    /** 확성기 루비 미러(오목·상점과 한 칸 — 조립). */
    val rubyBalance: () -> Long? = { null },
    /** 미니게임 창(W4-e). null 이면 레일 칸을 숨긴다. */
    val openMiniGame: (() -> Unit)? = null,
    /** 링크 열기(조립: Desktop.browse). */
    val openUrl: (String) -> Unit = {},
    /** 팀 코드 공유(데스크톱엔 공유 시트가 없다 — 조립: 클립보드). */
    val share: (String) -> Unit = {},
    /** int-w2: 3차 페이지·상점·미션(PagesWiring.routePages). 없으면 그 라우트는 '준비 중'(공용 화면은 그대로). */
    val routePages: RoutePages = RoutePages.NONE,
    /** 첫 실행 화면(PagesWiring.firstRun). pending 동안 [SharedRouter.showsFirstRun] 이면 페이지·레일 대신 이것을 전체 폭으로 그린다. */
    val firstRun: FirstRunOnboarding? = null,
    /**
     * 업데이트 필요 화면 [업데이트]의 목적지(W-12 · W-13 #7). 기본 = 이 빌드의 Store 제품 페이지(생성 상수) — 상수가 비었거나 꼴이 틀리면
     * AppLinks.updateDestination(WINDOWS)(= null → 단추 숨김). 껍데기 덮개(ShellUpdatePage)는 이 값으로 대신한다.
     */
    val updateDestination: String? = StoreUpdateDestination.windows,
)

@OptIn(ExperimentalCoroutinesApi::class)
class SharedFlyoutPageHost(private val deps: SharedPagesDeps) : FlyoutPageHost {

    /** 소속 읽기가 끝났는가(계정이 바뀌면 거짓부터). SharedRouter.isTeamless 의 [teamKnown]. */
    private val teamKnown: Flow<Boolean> = deps.session.profileFlow.map { it?.userID }.distinctUntilChanged().transformLatest {
        emit(false)
        deps.session.pendingProfileRefresh?.join()
        emit(true)
    }

    /** 지금 페이지(세션 단계 · 소속 · 라우트 · 깃발). 수명과 그리기가 같은 흐름을 본다. */
    fun pages(nav: FlyoutNavigator): Flow<SharedPage> =
        combine(nav.route, deps.session.phaseFlow, deps.session.profileFlow, teamKnown) { route, phase, profile, known ->
            SharedRouter.resolve(phase, profile, known, route, deps.config, deps.routePages.runtimeShown)
        }.distinctUntilChanged()

    /** 페이지 수명 고리(화면 안에서 스스로 하지 않는 것만 — 목록·대화·제보·차단 목록은 화면이 DisposableEffect 로 한다). */
    fun hooks(key: SharedPageKey): PageHooks? = when (key) {
        SharedPageKey.RANKINGS -> PageHooks({ deps.rankings.tabDidAppear() }, { deps.rankings.tabDidDisappear() })
        // 잔디 상세는 폰에서 나 탭 안의 화면 — 같은 수명(바로 열려도 기록을 읽는다).
        SharedPageKey.RECORDS, SharedPageKey.GRASS -> PageHooks({ deps.me.tabDidAppear() }, { deps.me.tabDidDisappear() })
        SharedPageKey.SETTINGS -> PageHooks({ deps.me.settingsDidAppear() }, { deps.me.settingsDidDisappear() })
        else -> null
    }

    fun lifecycle(): SharedPageLifecycle = SharedPageLifecycle(::hooks) { active ->
        if (active) deps.messages.appDidBecomeActive(MESSAGE_MENU_REFRESH_THROTTLE_SECONDS) else deps.messages.appDidEnterBackground()
    }

    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        val lifecycle = remember(nav) { lifecycle() }
        val pageFlow = remember(nav) { pages(nav) }
        LaunchedEffect(nav, lifecycle) { lifecycle.follow(nav.visible, pageFlow) }

        val visible by nav.visible.collectAsState()
        val page by pageFlow.collectAsState(SharedPage.Launching)
        val firstRunPending by (deps.firstRun?.pending ?: NO_FIRST_RUN).collectAsState()
        AingTheme(deps.appearance.mode) {
            CompositionLocalProvider(LocalBlockReportPlatform provides BlockReportPlatform.mac, LocalDesktopWording provides true) {
                val colors = AingTheme.colors
                val firstRun = deps.firstRun
                if (visible && firstRun != null && SharedRouter.showsFirstRun(firstRunPending, page)) {
                    Box(Modifier.width(widthDip.dp).fillMaxHeight().background(colors.background)) { firstRun.Content(nav, widthDip) }
                } else {
                    val slots = SharedRail.slots(page, deps.config, deps.openMiniGame != null)
                    val railShown = visible && slots.isNotEmpty()
                    Row(Modifier.width(widthDip.dp).fillMaxHeight().background(colors.background)) {
                        Box(Modifier.weight(1f).fillMaxHeight()) {
                            if (visible) PageBody(page, nav, RouteBodyWidth.of(widthDip, railShown))
                        }
                        if (railShown) Rail(slots, page, nav)
                    }
                }
            }
        }
    }

    @Composable
    private fun PageBody(page: SharedPage, nav: FlyoutNavigator, bodyWidthDip: Double) {
        val scope = rememberCoroutineScope()
        val fill = Modifier.fillMaxSize()
        // 3차 페이지·상점·미션: 레일 옆 본문 폭으로(맥 CheckMenuView.swift 421-429 — RoutePages 주석).
        val routed = deps.routePages.hostFor(page)
        if (routed != null) {
            routed.Content(nav, bodyWidthDip)
            return
        }
        when (page) {
            SharedPage.Launching -> LaunchScreen(fill)
            is SharedPage.NeedsUpdate -> {
                val destination = deps.updateDestination
                UpdateRequiredScreen(
                    minBuild = page.minBuild,
                    currentBuild = deps.currentBuild,
                    body = SessionText.updateBody(ClientPlatform.WINDOWS),
                    buttonTitle = destination?.let { SessionText.updateButton(ClientPlatform.WINDOWS) ?: SharedText.storeUpdateButton },
                    onOpenStore = { destination?.let(deps.openUrl) },
                    modifier = fill,
                )
            }
            SharedPage.SignedOut -> SignedOutStack(fill)
            SharedPage.AnotherInstance -> CenteredNote(SharedText.anotherInstance, null, fill)
            SharedPage.Teamless -> TeamlessPage(fill)
            SharedPage.Messages -> MessagesPage(nav, fill)
            is SharedPage.Conversation -> ConversationPage(page.peerId, nav, fill)
            is SharedPage.Rankings -> {
                LaunchedEffect(page.board) {
                    val target = RankingsBoardRestore.boardToApply(page.board, null)
                    if (target != null && deps.rankings.board != target) deps.rankings.open(target)
                }
                RankingsScreen(
                    store = deps.rankings,
                    me = deps.rankingsFace(),
                    scope = scope,
                    onSelectBoard = { board -> nav.navigate(FlyoutRoute.Rankings(board.rawValue)) },
                    modifier = fill,
                )
            }
            SharedPage.Records -> MeHomeScreen(deps.me, presence = null, open = { nav.navigate(SharedRouter.routeOf(it)) }, scope = scope, modifier = fill)
            is SharedPage.Grass -> GrassDetailScreen(deps.me, initialAxis = page.axis, scope = scope, modifier = fill)
            SharedPage.Missions -> MeMissionsScreen(deps.me, onBack = null, modifier = fill)
            SharedPage.Settings -> SettingsPage(nav, fill)
            SharedPage.Profile -> ProfileScreen(deps.me, scope, onPickPhoto = {}, openCharacters = { nav.navigate(FlyoutRoute.Characters) }, modifier = fill)
            SharedPage.Characters -> CharacterPickerScreen(deps.me, openShop = { nav.navigate(FlyoutRoute.Shop) }, openGachaMachine = {}, modifier = fill)
            SharedPage.Feedback -> FeedbackScreen(deps.me, scope, fill)
            SharedPage.Blocked -> BlockedPeopleScreen(deps.messages, fill)
            SharedPage.AccountDeletion -> AccountDeletionScreen(
                store = deps.me,
                onDelete = { scope.launch { if (deps.me.deleteAccount()) nav.navigate(FlyoutRoute.Home) } },
                onClose = { nav.back() },
                modifier = fill,
            )
            SharedPage.Home, SharedPage.PokeList, SharedPage.Ultra, SharedPage.AiTokens, SharedPage.AiLimits, SharedPage.Devices,
            SharedPage.DesktopSettings, is SharedPage.Pending -> CenteredNote(SharedText.pendingTitle, SharedText.pendingBody, fill)
        }
    }

    /** 로그아웃 단계: 로그인 + 그 위에 쌓이는 가입 · 재설정(폰 SignedOutEntry 와 같은 자기 스택 — 지금 친 이메일을 들고 간다). */
    @Composable
    private fun SignedOutStack(modifier: Modifier) {
        var stack by remember { mutableStateOf(listOf<SignedOutStep>()) }
        when (val top = stack.lastOrNull()) {
            null -> LoginScreen(
                deps.session,
                onSignUp = { stack = stack + SignedOutStep.SignUp(null) },
                onPasswordReset = { email -> stack = stack + SignedOutStep.Reset(email) },
                onConfirmExit = { email -> stack = stack + SignedOutStep.SignUp(email) },
                modifier = modifier,
            )
            is SignedOutStep.SignUp -> {
                val store = remember(top) { SignUpStore(deps.session, false) }
                Column(modifier) {
                    BackRow { stack = stack.dropLast(1) }
                    SignUpScreen(store, top.confirmEmail, Modifier.weight(1f))
                }
            }
            is SignedOutStep.Reset -> {
                val store = remember(top) { PasswordResetStore(deps.session, top.email, SessionGraphemes) }
                Column(modifier) {
                    BackRow { stack = stack.dropLast(1) }
                    PasswordResetScreen(store, Modifier.weight(1f))
                }
            }
        }
    }

    @Composable
    private fun TeamlessPage(modifier: Modifier) {
        val colors = AingTheme.colors
        val scope = rememberCoroutineScope()
        val store = remember(deps.sessionContext) { TeamJoinStore(deps.sessionContext) }
        DisposableEffect(store) {
            // 팀이 정해지면 소속을 서버에서 다시 읽는다(역할을 지어내지 않는다 — TeamJoinStore 주석).
            store.onTeamSettled = { scope.launch { deps.session.refreshProfile() } }
            onDispose {
                store.onTeamSettled = null
                store.cancelPendingWork()
            }
        }
        val notice by store.noticeFlow.collectAsState()
        val submitting by store.isSubmittingFlow.collectAsState()
        Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(SharedText.teamlessBody, style = MaterialTheme.typography.bodyMedium, color = colors.label)
            TeamJoinFields(store.form, onSubmit = { store.submit() })
            notice?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.danger) }
            Button(onClick = { store.submit() }, enabled = !submitting, modifier = Modifier.fillMaxWidth()) { Text(store.primaryTitle) }
        }
    }

    @Composable
    private fun MessagesPage(nav: FlyoutNavigator, modifier: Modifier) {
        var sheet by remember { mutableStateOf<MessagesSheet?>(null) }
        MessagesListScreen(
            store = deps.messages,
            // ③ 대화로 가는 길은 FlyoutRoutes 하나 — 목록에서 연 대화의 뒤로 = 목록.
            onOpen = { peer -> nav.navigate(FlyoutRoutes.forMessageArrival(peer, deps.config.poke, Entry.MESSAGES)) },
            onNewConversation = { sheet = MessagesSheet.NewConversation },
            onMegaphone = { sheet = MessagesSheet.Megaphone },
            modifier = modifier,
        )
        when (sheet) {
            MessagesSheet.NewConversation -> MessagesNewConversationSheet(deps.messages, onSelect = { peer ->
                sheet = null
                nav.navigate(FlyoutRoutes.forMessageArrival(peer, deps.config.poke, Entry.MESSAGES))
            }, onClose = { sheet = null })
            MessagesSheet.Megaphone -> MessagesMegaphoneSheet(deps.messages, deps.rubyBalance(), onClose = { sheet = null })
            null -> Unit
        }
    }

    /** 대화 + ⑥ Enter 가드. 입력칸 상태를 여기서 쥐어 조합 여부를 읽는다(화면은 넘겨받은 상태를 쓴다). */
    @Composable
    private fun ConversationPage(peerId: String, nav: FlyoutNavigator, modifier: Modifier) {
        val field = remember(peerId) { TextFieldState() }
        val messages = deps.messages
        ConversationScreen(
            store = messages,
            peerID = peerId,
            onBack = { nav.back() },
            onLeave = { nav.navigate(FlyoutRoute.Messages) },
            modifier = modifier.onPreviewKeyEvent { event ->
                val enter = event.type == KeyEventType.KeyDown && (event.key == Key.Enter || event.key == Key.NumPadEnter)
                DesktopEnterKey.handle(enter, event.isShiftPressed, field.isComposing, field.text.toString(), messages.isSending) { text ->
                    messages.setDraft(text, peerId)
                    if (messages.sendDraft(peerId, isComposing = false)) field.clearText()
                }
            },
            composerState = field,
        )
    }

    @Composable
    private fun SettingsPage(nav: FlyoutNavigator, modifier: Modifier) {
        val scope = rememberCoroutineScope()
        var confirmingSignOut by remember { mutableStateOf(false) }
        val actions = remember(nav) {
            object : SettingsActions {
                override fun openBlockedPeople() = nav.navigate(FlyoutRoute.Blocked)
                override fun openAccountDeletion() = nav.navigate(FlyoutRoute.AccountDeletion)
                override fun confirmSignOut() {
                    confirmingSignOut = true
                }
                override fun openUrl(url: String) = deps.openUrl(url)
                override fun share(text: String) = deps.share(text)
            }
        }
        Column(modifier) {
            if (deps.routePages.desktopSettings != null) DesktopSettingsEntryRow { nav.navigate(FlyoutRoute.DesktopSettings) }
            SettingsScreen(deps.me, deps.appearance, actions, Modifier.weight(1f))
        }
        if (confirmingSignOut) {
            AlertDialog(
                onDismissRequest = { confirmingSignOut = false },
                title = { Text(MeText.signOutConfirmTitle) },
                text = { Text(SharedText.signOutConfirmMessage) },
                confirmButton = {
                    TextButton(onClick = {
                        confirmingSignOut = false
                        // 로그아웃 흐름: 스토어가 세션을 닫고(단계 → SignedOut) 라우터는 홈으로 — 다음 로그인은 홈에서 시작한다.
                        scope.launch {
                            deps.me.signOut()
                            nav.navigate(FlyoutRoute.Home)
                        }
                    }) { Text(MeText.signOut) }
                },
                dismissButton = { TextButton(onClick = { confirmingSignOut = false }) { Text(SharedText.signOutCancel) } },
            )
        }
    }

    @Composable
    private fun Rail(slots: List<RailSlot>, page: SharedPage, nav: FlyoutNavigator) {
        val colors = AingTheme.colors
        Column(
            Modifier.width(RAIL_WIDTH.dp).fillMaxHeight().background(colors.surface).padding(vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            for (slot in slots) {
                val active = SharedRail.isActive(slot, page)
                val tint = if (active) colors.accent else colors.label2
                Column(
                    Modifier
                        .width((RAIL_WIDTH - 8).dp)
                        .background(if (active) colors.accentTint else colors.surface, RoundedCornerShape(10.dp))
                        .clickable {
                            val route = SharedRail.route(slot)
                            if (route == null) deps.openMiniGame?.invoke() else nav.navigate(route)
                        }
                        .padding(vertical = 6.dp)
                        .semantics { contentDescription = slot.label },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    SfSymbols.icon(slot.sfName)?.let { AingIcon(it, contentDescription = null, size = 20.dp, tint = tint) }
                    Text(slot.label, style = MaterialTheme.typography.labelSmall, color = tint, textAlign = TextAlign.Center, maxLines = 1)
                }
            }
        }
    }

    /** 공용 설정 위 'PC 설정 ›' 한 줄(맥은 설정 창이 따로 — 데스크톱은 플라이아웃 안 하위 화면). */
    @Composable
    private fun DesktopSettingsEntryRow(onClick: () -> Unit) {
        val colors = AingTheme.colors
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)
                .background(colors.surface, RoundedCornerShape(10.dp))
                .clickable(onClick = onClick)
                .padding(horizontal = 12.dp, vertical = 10.dp)
                .semantics { contentDescription = SharedText.desktopSettingsEntry },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(SharedText.desktopSettingsEntry, style = MaterialTheme.typography.bodyMedium, color = colors.label)
                Text(SharedText.desktopSettingsEntryDetail, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
            Text("›", style = MaterialTheme.typography.titleMedium, color = colors.label2)
        }
    }

    @Composable
    private fun BackRow(onBack: () -> Unit) {
        val colors = AingTheme.colors
        TextButton(onClick = onBack, modifier = Modifier.padding(start = 4.dp)) { Text("‹ 뒤로", color = colors.accent) }
    }

    @Composable
    private fun CenteredNote(title: String, body: String?, modifier: Modifier) {
        val colors = AingTheme.colors
        Column(
            modifier.padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = colors.label, textAlign = TextAlign.Center)
            body?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2, textAlign = TextAlign.Center) }
        }
    }

    private sealed interface SignedOutStep {
        data class SignUp(val confirmEmail: String?) : SignedOutStep
        data class Reset(val email: String) : SignedOutStep
    }

    private enum class MessagesSheet { NewConversation, Megaphone }

    companion object {
        /** 레일 폭(DIP). 플라이아웃 414 에서 페이지가 350 남짓 — 공용 화면의 좁은 폭(340) 위다. */
        const val RAIL_WIDTH = 64
    }

    /** 세션 단계 흐름이 로그인인가(배경 갱신 조립용). */
    fun signedInFlow(): Flow<Boolean> = deps.session.phaseFlow.map { it == SessionPhase.SignedIn }
}

private val NO_FIRST_RUN: StateFlow<Boolean> = MutableStateFlow(false)

/** 플라이아웃 열기의 메시지 요약 스로틀 — 맥 팝오버 `messageMenuRefreshThrottleSeconds`(60초, W3-c0 · 공용 패치 9). */
internal const val MESSAGE_MENU_REFRESH_THROTTLE_SECONDS: Double = 60.0
