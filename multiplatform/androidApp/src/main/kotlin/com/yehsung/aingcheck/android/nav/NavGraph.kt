// 원본: 없음 — Android 조립(K11). W3-a 패치 02: 세션·지금·메시지 목적지를 W3-a 진입 함수로(W3aScreenDeps 가 있을 때 — 없으면 자리표시 그대로).
// 조립 파일(K11): 목적지 → 화면. W1 동안 W1-g, 그 뒤로는 조정자만 고친다 — 화면 갈래는 자기 화면 파일만 내고,
// 조정자가 여기서 자리표시 한 줄을 그 화면으로 바꾼다.
//
// 구조(W0-f E-U16 실측): NavController 하나 + 탭별 중첩 그래프 + saveState/restoreState. 프로세스 죽음 뒤에도 탭별 스택이 돌아온다.
// **목적지에 navDeepLink 를 달지 않는다**: NavController 가 NEW_TASK 딥링크를 받으면 CLEAR_TASK 로 작업을 다시 세워(flags 0x1000c000)
// 작업 뿌리 Intent 가 VIEW 가 되고, 그 뒤 프로세스가 죽은 채 런처 아이콘을 누르면 Activity 가 둘이 된다(W0-f 실측 instances=2).
// 딥링크는 셸이 AingRoute 로 풀어 [ShellNavigator.open] 으로 연다(MainActivity 는 singleTask — 매니페스트).
package com.yehsung.aingcheck.android.nav

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.window.DialogProperties
import com.yehsung.aingcheck.android.screens.account.AccountDeletionRouteScreen
import com.yehsung.aingcheck.android.screens.games.chess.ChessDestination
import com.yehsung.aingcheck.android.screens.games.gomoku.GomokuDestination
import com.yehsung.aingcheck.android.screens.games.hub.GamesHubRoute
import com.yehsung.aingcheck.android.screens.games.minigame.MiniGameRoute
import com.yehsung.aingcheck.android.screens.games.tetris.TetrisDuelRoute
import com.yehsung.aingcheck.android.screens.me.CharacterPickerRouteScreen
import com.yehsung.aingcheck.android.screens.me.FeedbackRouteScreen
import com.yehsung.aingcheck.android.screens.me.GrassDetailRouteScreen
import com.yehsung.aingcheck.android.screens.me.MeDestinations
import com.yehsung.aingcheck.android.screens.me.MeHomeRouteScreen
import com.yehsung.aingcheck.android.screens.me.ProfileRouteScreen
import com.yehsung.aingcheck.android.screens.rankings.RankingsRouteScreen
import com.yehsung.aingcheck.android.screens.settings.BlockedPeopleRouteScreen
import com.yehsung.aingcheck.android.screens.settings.NotificationPrimerRouteScreen
import com.yehsung.aingcheck.android.screens.settings.SettingsRouteScreen
import com.yehsung.aingcheck.android.screens.shop.GachaMachineRoute
import com.yehsung.aingcheck.android.screens.shop.GachaOddsRoute
import com.yehsung.aingcheck.android.screens.shop.MissionsRoute
import com.yehsung.aingcheck.android.screens.shop.ShopRoute
import com.yehsung.aingcheck.android.screens.stage.AingStage
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameSafety
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFacts
import com.yehsung.aingcheck.ui.screens.me.MeHomeRules
import com.yehsung.aingcheck.ui.screens.messages.MessagesBlockConfirmSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesReportSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesReportTarget
import com.yehsung.aingcheck.ui.screens.rankings.RankingsScreenRules
import com.yehsung.aingcheck.ui.shop.MeCakeGiftReopenRow
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.dialog
import androidx.navigation.compose.navigation
import androidx.navigation.toRoute
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.android.screens.messages.BlockConfirmEntry
import com.yehsung.aingcheck.android.screens.messages.ConversationEntry
import com.yehsung.aingcheck.android.screens.messages.MegaphoneSheetEntry
import com.yehsung.aingcheck.android.screens.messages.MessagesListEntry
import com.yehsung.aingcheck.android.screens.messages.NewConversationSheetEntry
import com.yehsung.aingcheck.android.screens.messages.ReportSheetEntry
import com.yehsung.aingcheck.android.screens.now.NowHomeEntry
import com.yehsung.aingcheck.android.screens.now.TeamGoalSheetEntry
import com.yehsung.aingcheck.android.screens.now.TeamJoinSheetEntry
import com.yehsung.aingcheck.android.screens.session.PasswordResetEntry
import com.yehsung.aingcheck.android.screens.session.SignUpEntry
import com.yehsung.aingcheck.android.screens.session.SignedOutEntry
import com.yehsung.aingcheck.android.screens.session.W3aScreenDeps
import com.yehsung.aingcheck.android.screens.account.AccountDeletionPlaceholder
import com.yehsung.aingcheck.android.screens.games.ChessPlaceholder
import com.yehsung.aingcheck.android.screens.games.GamesHomePlaceholder
import com.yehsung.aingcheck.android.screens.games.GomokuPlaceholder
import com.yehsung.aingcheck.android.screens.games.MiniGamePlaceholder
import com.yehsung.aingcheck.android.screens.games.StakeSheetPlaceholder
import com.yehsung.aingcheck.android.screens.games.TetrisDuelPlaceholder
import com.yehsung.aingcheck.android.screens.me.CharacterPickerPlaceholder
import com.yehsung.aingcheck.android.screens.me.FeedbackPlaceholder
import com.yehsung.aingcheck.android.screens.me.GrassDetailPlaceholder
import com.yehsung.aingcheck.android.screens.me.MeHomePlaceholder
import com.yehsung.aingcheck.android.screens.me.ProfilePlaceholder
import com.yehsung.aingcheck.android.screens.messages.BlockConfirmPlaceholder
import com.yehsung.aingcheck.android.screens.messages.ConversationPlaceholder
import com.yehsung.aingcheck.android.screens.messages.MegaphoneSheetPlaceholder
import com.yehsung.aingcheck.android.screens.messages.MessagesListPlaceholder
import com.yehsung.aingcheck.android.screens.messages.NewConversationSheetPlaceholder
import com.yehsung.aingcheck.android.screens.messages.ReportSheetPlaceholder
import com.yehsung.aingcheck.android.screens.now.NowHomePlaceholder
import com.yehsung.aingcheck.android.screens.now.TeamGoalSheetPlaceholder
import com.yehsung.aingcheck.android.screens.now.TeamJoinSheetPlaceholder
import com.yehsung.aingcheck.android.screens.rankings.RankingsHomePlaceholder
import com.yehsung.aingcheck.android.screens.session.LoginPlaceholder
import com.yehsung.aingcheck.android.screens.session.PasswordResetPlaceholder
import com.yehsung.aingcheck.android.screens.session.SignUpPlaceholder
import com.yehsung.aingcheck.android.screens.settings.BlockedPeoplePlaceholder
import com.yehsung.aingcheck.android.screens.settings.NotificationPrimerPlaceholder
import com.yehsung.aingcheck.android.screens.settings.SettingsPlaceholder
import com.yehsung.aingcheck.android.screens.shop.GachaMachinePlaceholder
import com.yehsung.aingcheck.android.screens.shop.GachaOddsSheetPlaceholder
import com.yehsung.aingcheck.android.screens.shop.ShopPlaceholder

/** 로그인 뒤 탭 다섯(시작 = 지금). [screens] 가 있으면 W3-a 화면(지금 · 메시지)을, 없으면 자리표시를 그린다. */
@Composable
fun TabsNavHost(
    navController: NavHostController,
    modifier: Modifier = Modifier,
    screens: W3aScreenDeps? = null,
    app: AppScreens? = null,
    onTabBarHidden: (Boolean) -> Unit = {},
) {
    val open: (Any) -> Unit = { navController.navigate(it) }
    val back: () -> Unit = { navController.popBackStack() }
    val toMessagesList: () -> Unit = { navController.popBackStack(Dest.MessagesList, inclusive = false) }
    val openRoute: (AingRoute) -> Unit = { ShellNavigator(navController).open(it) }
    NavHost(navController, startDestination = Dest.NowGraph, modifier = modifier) {
        val w3a = screens ?: app?.w3a
        if (w3a == null) nowGraph(open) else nowGraph(w3a, open, back, openRoute)
        if (w3a == null) messagesGraph(open) else messagesGraph(w3a, open, back, toMessagesList)
        if (app == null) {
            rankingsGraph()
            gamesGraph(open)
            meGraph(open)
            dialog<Dest.NotificationPrimerSheet> { NotificationPrimerPlaceholder() }
        } else {
            // 7차 조립(K11): 순위 · 게임 · 나 탭과 설명 시트를 화면 갈래 진입 함수로(assembly-all §1).
            val navigator = ShellNavigator(navController)
            rankingsGraph(app)
            gamesGraph(app, navController, navigator, open, onTabBarHidden)
            meGraph(app, navController, open)
            dialog<Dest.NotificationPrimerSheet> {
                NotificationPrimerRouteScreen(app.primerContent, app.primerPort)
                DisposableEffect(Unit) { onDispose { app.phone.push.primerDidDisappear() } } // 끌어내림 · 뒤로가기 포함
            }
        }
    }
}

/**
 * 로그인 전 단계(로그인 · 가입 · 재설정). [screens] 가 있으면 W3-a 로그인 흐름 — 로그인 화면이 가입 · 인증코드 · 재설정을 자기 스택에 쌓는다
 * (쳐 둔 이메일을 들고 가야 해서 — SignedOutEntry). Dest.SignUp · PasswordReset 은 딥링크·데모로 바로 열 때만 쓴다.
 */
@Composable
fun SessionNavHost(navController: NavHostController, modifier: Modifier = Modifier, screens: W3aScreenDeps? = null) {
    val open: (Any) -> Unit = { navController.navigate(it) }
    NavHost(navController, startDestination = Dest.SessionGraph, modifier = modifier) {
        navigation<Dest.SessionGraph>(startDestination = Dest.Login) {
            composable<Dest.Login> { if (screens == null) LoginPlaceholder(open) else SignedOutEntry(screens.session) }
            composable<Dest.SignUp> { if (screens == null) SignUpPlaceholder() else SignUpEntry(screens.session, createTeam = false, confirmEmail = null) }
            composable<Dest.PasswordReset> {
                if (screens == null) PasswordResetPlaceholder() else PasswordResetEntry(screens.session, screens.session.storedEmail ?: "")
            }
        }
    }
}

private fun NavGraphBuilder.nowGraph(open: (Any) -> Unit) =
    navigation<Dest.NowGraph>(startDestination = Dest.NowHome) {
        composable<Dest.NowHome> { NowHomePlaceholder(open) }
        dialog<Dest.TeamGoalSheet> { TeamGoalSheetPlaceholder() }
        dialog<Dest.TeamJoinSheet> { TeamJoinSheetPlaceholder() }
    }

private fun NavGraphBuilder.nowGraph(screens: W3aScreenDeps, open: (Any) -> Unit, back: () -> Unit, openRoute: (AingRoute) -> Unit) =
    navigation<Dest.NowGraph>(startDestination = Dest.NowHome) {
        composable<Dest.NowHome> { NowHomeEntry(screens.now, screens.nowWork, screens.characterID(), open, openRoute) }
        dialog<Dest.TeamGoalSheet> { TeamGoalSheetEntry(screens.now, back) }
        dialog<Dest.TeamJoinSheet> { TeamJoinSheetEntry(screens.now, back) }
    }

private fun NavGraphBuilder.messagesGraph(screens: W3aScreenDeps, open: (Any) -> Unit, back: () -> Unit, toList: () -> Unit) =
    navigation<Dest.MessagesGraph>(startDestination = Dest.MessagesList) {
        composable<Dest.MessagesList> { MessagesListEntry(screens.messages, open) }
        composable<Dest.Conversation> { ConversationEntry(screens.messages, it.toRoute<Dest.Conversation>().peerId, back, toList) }
        dialog<Dest.NewConversationSheet> { NewConversationSheetEntry(screens.messages, open, back) }
        dialog<Dest.MegaphoneSheet> { MegaphoneSheetEntry(screens.messages, screens.rubyBalance(), back) }
        dialog<Dest.ReportSheet> { ReportSheetEntry(screens.messages, it.toRoute<Dest.ReportSheet>().subjectId, back, toList) }
        dialog<Dest.BlockConfirm> { BlockConfirmEntry(screens.messages, it.toRoute<Dest.BlockConfirm>().peerId, back, toList) }
    }

private fun NavGraphBuilder.messagesGraph(open: (Any) -> Unit) =
    navigation<Dest.MessagesGraph>(startDestination = Dest.MessagesList) {
        composable<Dest.MessagesList> { MessagesListPlaceholder(open) }
        composable<Dest.Conversation> { ConversationPlaceholder(it.toRoute<Dest.Conversation>().peerId, open) }
        dialog<Dest.NewConversationSheet> { NewConversationSheetPlaceholder() }
        dialog<Dest.MegaphoneSheet> { MegaphoneSheetPlaceholder() }
        dialog<Dest.ReportSheet> { ReportSheetPlaceholder(it.toRoute<Dest.ReportSheet>().subjectId) }
        dialog<Dest.BlockConfirm> { BlockConfirmPlaceholder(it.toRoute<Dest.BlockConfirm>().peerId) }
    }

private fun NavGraphBuilder.rankingsGraph() =
    navigation<Dest.RankingsGraph>(startDestination = Dest.RankingsHome()) {
        composable<Dest.RankingsHome> { RankingsHomePlaceholder(it.toRoute<Dest.RankingsHome>().board) }
    }

private fun NavGraphBuilder.gamesGraph(open: (Any) -> Unit) =
    navigation<Dest.GamesGraph>(startDestination = Dest.GamesHome) {
        composable<Dest.GamesHome> { GamesHomePlaceholder(open) }
        composable<Dest.MiniGame> { MiniGamePlaceholder(it.toRoute<Dest.MiniGame>().game) }
        composable<Dest.Gomoku> { GomokuPlaceholder(it.toRoute<Dest.Gomoku>(), open) }
        composable<Dest.Chess> { ChessPlaceholder(it.toRoute<Dest.Chess>(), open) }
        composable<Dest.TetrisDuel> { TetrisDuelPlaceholder(open) }
        dialog<Dest.StakeSheet> { StakeSheetPlaceholder(it.toRoute<Dest.StakeSheet>().game) }
    }

private fun NavGraphBuilder.meGraph(open: (Any) -> Unit) =
    navigation<Dest.MeGraph>(startDestination = Dest.MeHome) {
        composable<Dest.MeHome> { MeHomePlaceholder(open) }
        composable<Dest.Shop> { ShopPlaceholder(open) }
        dialog<Dest.GachaOddsSheet> { GachaOddsSheetPlaceholder() }
        composable<Dest.GachaMachine> { GachaMachinePlaceholder() }
        composable<Dest.CharacterPicker> { CharacterPickerPlaceholder() }
        composable<Dest.Profile> { ProfilePlaceholder() }
        composable<Dest.Feedback> { FeedbackPlaceholder(it.toRoute<Dest.Feedback>().reportId) }
        composable<Dest.Settings> { SettingsPlaceholder(open) }
        composable<Dest.BlockedPeople> { BlockedPeoplePlaceholder() }
        composable<Dest.AccountDeletion> { AccountDeletionPlaceholder() }
        composable<Dest.GrassDetail> { GrassDetailPlaceholder(it.toRoute<Dest.GrassDetail>().axis) }
    }

// ---------- 7차 조립(K11) — 순위(W3-b) · 게임(W4-a · W4-b) · 나(W3-b · W4-c · W5-c) ----------

private fun NavGraphBuilder.rankingsGraph(app: AppScreens) =
    navigation<Dest.RankingsGraph>(startDestination = Dest.RankingsHome()) {
        composable<Dest.RankingsHome> {
            val p = app.phone
            val me = RankingsScreenRules.myFace(
                meEquippedLoaded = p.me.equippedLoaded,
                meEquippedCharacterID = p.me.equippedServerID,
                snapshotCharacterID = null,
                nowCard = p.now.myCard(p.environment.clock.now()),
                snapshotMood = null,
            )
            RankingsRouteScreen(store = p.rankings, boardArg = it.toRoute<Dest.RankingsHome>().board, me = me)
        }
    }

private fun NavGraphBuilder.gamesGraph(
    app: AppScreens,
    nav: NavHostController,
    navigator: ShellNavigator,
    open: (Any) -> Unit,
    onTabBarHidden: (Boolean) -> Unit,
) = navigation<Dest.GamesGraph>(startDestination = Dest.GamesHome) {
    val p = app.phone
    // 대국 화면은 두 겹 쌓지 않는다(W4-a §1 끝 — 알림 · 딥링크 · 허브 카드 모두).
    val openGame: (Any) -> Unit = { d -> if (d is Dest.Gomoku || d is Dest.Chess) nav.navigate(d) { launchSingleTop = true } else open(d) }
    composable<Dest.GamesHome> {
        GamesHubRoute(
            store = p.games,
            facts = remember { GamesHubBoardFacts.of(p.gomoku, p.chess) },
            now = { p.environment.clock.now() },
            open = openGame,
            onOpenShop = { open(Dest.Shop) },
            onOpenRankings = { navigator.selectTab(AingTab.RANKINGS) },
        )
    }
    composable<Dest.MiniGame> {
        // 길건너 · 모르는 글자 → onBack(§8-18 7 — 화면 없음).
        MiniGameRoute(store = p.games, game = it.toRoute<Dest.MiniGame>().game, myUserID = p.session.userID, onBack = { nav.popBackStack() })
    }
    composable<Dest.Gomoku> {
        GomokuDestination(
            dest = it.toRoute<Dest.Gomoku>(),
            games = p.games,
            gomoku = p.gomoku,
            me = app.boardGameMe(),
            onLeave = { nav.popBackStack() },
            safety = BoardGameSafety(
                block = { peerID -> p.messages.blockPeer(peerID) }, // 확인 덮개를 지난 뒤에만 불린다
                reportSheet = { target, onSent, onClose ->
                    MessagesReportSheet(p.messages, MessagesReportTarget(target.peerID, target.peerName), onSent, onClose)
                },
                blockConfirmSheet = { peerName, onConfirm, onClose -> MessagesBlockConfirmSheet(peerName, onConfirm, onClose) },
            ),
            onTabBarHidden = onTabBarHidden,
        )
    }
    composable<Dest.Chess> {
        ChessDestination(
            dest = it.toRoute<Dest.Chess>(),
            games = p.games,
            chess = p.chess,
            me = app.boardGameMe(),
            onLeave = { nav.popBackStack() },
            onTabBarHidden = onTabBarHidden,
        )
    }
    composable<Dest.TetrisDuel> {
        TetrisDuelRoute(
            store = p.games,
            lifecycle = app.lifecycle,
            myUserID = p.session.userID,
            meName = p.me.displayName,
            onBack = { nav.popBackStack() },
        )
    }
    dialog<Dest.StakeSheet> { StakeSheetPlaceholder(it.toRoute<Dest.StakeSheet>().game) }
}

private fun NavGraphBuilder.meGraph(app: AppScreens, nav: NavHostController, open: (Any) -> Unit) =
    navigation<Dest.MeGraph>(startDestination = Dest.MeHome) {
        val p = app.phone
        val back: () -> Unit = { nav.popBackStack() }
        composable<Dest.MeHome> {
            MeHomeRouteScreen(
                store = p.me,
                presence = MeHomeRules.presence(p.now.myCard(p.environment.clock.now())),
                open = { d -> MeDestinations.dest(d)?.let(open) },
                // W5-c 무대 칸(나 탭 132 · 근무 상태 발밑 빛) — 크기는 MeStageSpec 이 modifier 에 이미 걸었다.
                stage = { spec, m -> AingStage(spec.characterId, spec.mood, m, artSize = spec.artSize) },
                cakeGiftRow = { MeCakeGiftReopenRow(p.me) },
            )
        }
        composable<Dest.Shop> { ShopRoute(p.me, onBack = back, onOpenMachine = { open(Dest.GachaMachine) }) }
        dialog<Dest.GachaOddsSheet>(dialogProperties = DialogProperties(usePlatformDefaultWidth = false)) { GachaOddsRoute(p.me, back) }
        composable<Dest.GachaMachine> { GachaMachineRoute(p.me, back) }
        composable<Dest.CharacterPicker> {
            // W3-b 고르기 화면 한 벌에 W4-c 상점 · 뽑기 단추를 넘긴다(겹치는 목적지 하나로). 머리 그림 = W5-c 무대(92 · 발밑 빛 회색).
            CharacterPickerRouteScreen(
                store = p.me,
                openShop = { open(Dest.Shop) },
                openGachaMachine = { open(Dest.GachaMachine) },
                hero = { spec, m -> AingStage(spec.characterId, null, m, artSize = spec.artSize) },
            )
        }
        composable<Dest.Profile> { ProfileRouteScreen(p.me, openCharacters = { open(Dest.CharacterPicker) }) }
        composable<Dest.Feedback> { FeedbackRouteScreen(p.me) }
        composable<Dest.Settings> {
            SettingsRouteScreen(
                store = p.me,
                appearance = app.appearance,
                push = app.pushSettings,
                prefs = app.prefs,
                openBlockedPeople = { open(Dest.BlockedPeople) },
                openAccountDeletion = { open(Dest.AccountDeletion) },
            )
        }
        composable<Dest.BlockedPeople> { BlockedPeopleRouteScreen(p.messages) }
        composable<Dest.AccountDeletion> { AccountDeletionRouteScreen(p.me, app.accountCleanup, onClose = back) }
        composable<Dest.GrassDetail> { GrassDetailRouteScreen(p.me, it.toRoute<Dest.GrassDetail>().axis) }
        composable<Dest.Missions> { MissionsRoute(p.me, back) }
    }

/** 탭 막대와 라우트 열기. 탭마다 자기 백스택을 지킨다(saveState/restoreState). */
class ShellNavigator(val nav: NavHostController) {
    /** 탭 막대: 그 탭의 저장된 스택으로 돌아간다. */
    fun selectTab(tab: AingTab) {
        nav.navigate(RoutePlans.graphOf(tab)) {
            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    /** 라우트 열기(딥링크·알림·위젯): 그 탭을 뿌리부터 다시 세우고 자식 목적지를 쌓는다. */
    fun open(route: AingRoute) {
        val plan = RoutePlans.plan(route)
        val graph = RoutePlans.graphOf(plan.tab)
        nav.navigate(graph) {
            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
            launchSingleTop = true
            restoreState = false
        }
        if (plan.root != RoutePlans.defaultRoot(plan.tab)) {
            // 뿌리 인자가 기본과 다르다(순위 세그먼트): 탭 그래프 안을 비우고 뿌리를 갈아 끼운다.
            nav.navigate(plan.root) { popUpTo(graph) { inclusive = false } }
        }
        plan.children.forEach { nav.navigate(it) }
    }
}
