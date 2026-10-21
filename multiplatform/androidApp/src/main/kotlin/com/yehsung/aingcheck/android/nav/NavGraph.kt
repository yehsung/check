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

/** 로그인 뒤 탭 다섯(시작 = 지금). */
@Composable
fun TabsNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
    val open: (Any) -> Unit = { navController.navigate(it) }
    NavHost(navController, startDestination = Dest.NowGraph, modifier = modifier) {
        nowGraph(open)
        messagesGraph(open)
        rankingsGraph()
        gamesGraph(open)
        meGraph(open)
        dialog<Dest.NotificationPrimerSheet> { NotificationPrimerPlaceholder() }
    }
}

/** 로그인 전 단계(로그인 · 가입 · 재설정). */
@Composable
fun SessionNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
    val open: (Any) -> Unit = { navController.navigate(it) }
    NavHost(navController, startDestination = Dest.SessionGraph, modifier = modifier) {
        navigation<Dest.SessionGraph>(startDestination = Dest.Login) {
            composable<Dest.Login> { LoginPlaceholder(open) }
            composable<Dest.SignUp> { SignUpPlaceholder() }
            composable<Dest.PasswordReset> { PasswordResetPlaceholder() }
        }
    }
}

private fun NavGraphBuilder.nowGraph(open: (Any) -> Unit) =
    navigation<Dest.NowGraph>(startDestination = Dest.NowHome) {
        composable<Dest.NowHome> { NowHomePlaceholder(open) }
        dialog<Dest.TeamGoalSheet> { TeamGoalSheetPlaceholder() }
        dialog<Dest.TeamJoinSheet> { TeamJoinSheetPlaceholder() }
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

/** 탭 막대와 라우트 열기. 탭마다 자기 백스택을 지킨다(saveState/restoreState). */
class ShellNavigator(private val nav: NavHostController) {
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
