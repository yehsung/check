// 원본: Sources/check/RummyPanel.swift:269 (RummyPanel — 단계 고르기 · 덮개) · Sources/check/RummyExitFlow.swift (이탈 표) · Sources/check/CheckRummyWindow.swift (창 수명 — 폰은 화면 수명) @ 1a5eeca6 · Sources/CheckMobileKit/Games/GamesRummyScreen.swift @ ios-1017-cube 61d75d8c · 폰 배치는 ios-1017 설계서 §3 · §10
//
// 폰 아잉 큐브 **화면 하나** — 로비 · 방 · 판 · 결과를 한 화면이 갈아 끼운다(테트리스 화면과 같은 구조). 이 파일은 껍데기다: 단계 고르기 · 수명 · 뒤로 가기 · 규칙 시트 · 나가기 확인 ·
// 그림 공급만 쥔다. 뷰는 파일마다 따로 있다.
// 수명은 **직접 코어를 부르지 않는다** — 나타남 → GamesStore.rummyScreenDidAppear(), 사라짐 → …DidDisappear() 뿐이다(폴링 문·끝난 판 접기의 주인은 스토어). 앱 앞/뒤도 게임 탭 스토어가 나른다.
// 화면 꺼짐 방지는 화면이 쓰지 않는다(주인은 GamesStore.wantsIdleTimerDisabled — 코어 `isHoldingMatch`).
// 판만 가로다. 방향도 이 화면이 정하지 않는다 — GamesStore.rummyInterfaceOrientation 이 상태에서 계산하고, 이 화면의 수명(DisposableEffect)이 그 재료다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import com.yehsung.aingcheck.core.stores.rummy.RummyAvailability
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.closeDecision
import com.yehsung.aingcheck.core.stores.rummy.confirmBack
import com.yehsung.aingcheck.core.stores.rummy.requestBack
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.games.minigame.kit.EmptyState
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 화면 꼬리표(시험·계측). */
object GamesRummyTags {
    const val UNAVAILABLE: String = "rummy.unavailable"
    const val LOBBY: String = "rummy.lobby"
    const val ROOM: String = "rummy.room"
    const val MATCH: String = "rummy.match"
    const val RESULT: String = "rummy.result"
    const val RULES: String = "rummy.rules"
    const val EXIT_CONFIRM: String = "rummy.exit.confirm"
    const val EXIT_KEEP: String = "rummy.exit.keep"
}

/**
 * 뒤로 가기 판단 — 시스템 뒤로와 화면 [나가기]가 **같은 한 곳**을 지난다(스토어 `requestBack`·`confirmBack`). Android 조립의 `BackHandler` 가 [handleBack] 을 부른다.
 * 표: 놀던 기기·로비·결과 = 그냥 나감 · 손님 방 = 묻지 않고 나감(스토어가 나가기를 띄운다) · 판 중 = 기권 확인 · 방장 방 = 방 닫힘 확인.
 */
@Stable
class GamesRummyBackState {
    /** 묻는 중인 판단(없으면 null). */
    var asking: RummyCloseDecision? by mutableStateOf(null)
        private set

    /** 판 화면의 [반응] 고르개가 떠 있다. 뒤로 한 번은 이것부터 닫는다 — 기권 확인으로 넘어가면 안 된다. */
    var reactionPicking: Boolean by mutableStateOf(false)

    /** 뒤로 한 번. 고르개 · 확인이 떠 있으면 그것을 닫는다(계속하기). */
    fun handleBack(rummy: RummyStore, leave: () -> Unit) {
        if (reactionPicking) {
            reactionPicking = false
            return
        }
        if (asking != null) {
            asking = null
            return
        }
        when (val decision = rummy.requestBack()) {
            RummyCloseDecision.close, RummyCloseDecision.leaveRoom -> leave()
            RummyCloseDecision.confirmForfeit, RummyCloseDecision.confirmCloseRoom -> asking = decision
        }
    }

    /** 확인을 골랐다. 묻던 사이 판단이 바뀌었으면 스토어가 지금 판단으로 다시 묻게 한다("루비는 그대로예요"를 읽고 누른 버튼이 기권이 되면 안 된다). */
    fun confirm(rummy: RummyStore, leave: () -> Unit) {
        val asked = asking ?: return
        val again = rummy.confirmBack(asked)
        asking = again
        if (again == null) leave()
    }

    fun keep() {
        asking = null
    }

    /** 묻는 동안 판이 끝나거나(결과) 시작되면 질문을 지금 판단에 맞춘다. */
    fun sync(rummy: RummyStore) {
        val asked = asking ?: return
        val now = rummy.closeDecision
        asking = when (now) {
            RummyCloseDecision.close, RummyCloseDecision.leaveRoom -> null
            RummyCloseDecision.confirmForfeit, RummyCloseDecision.confirmCloseRoom -> if (now == asked) asked else now
        }
    }
}

@Composable
fun rememberGamesRummyBackState(): GamesRummyBackState = remember { GamesRummyBackState() }

/**
 * 아잉 큐브 화면.
 *
 * 수명 효과는 **스토어 하나에만** 묶는다(값이 흔들리는 상태를 키로 걸지 않는다) — 다시 서면 rummyScreenDidDisappear 가 돌아 폴링이 끊기고 끝난 판이 접힌다.
 *
 * @param art 그림 저장소(앱에 하나). 시험·스냅숏은 기본값(망 0 · 번들만).
 * @param me 내 얼굴(탁자 의자 · 내 자리). 게임 탭이 이미 아는 값 — 새 조회 없음.
 * @param back 뒤로 가기 판단. Android 조립이 같은 값을 `BackHandler` 에 건다.
 * @param onLeave 화면을 떠난다(내비 pop). 뒤로 판단을 **지난 뒤에만** 부른다.
 */
@Composable
fun GamesRummyScreen(
    store: GamesStore,
    myUserID: String?,
    me: RummySeatFace,
    modifier: Modifier = Modifier,
    art: GamesRummyArt = remember { GamesRummyArt() },
    back: GamesRummyBackState = rememberGamesRummyBackState(),
    onLeave: () -> Unit = {},
    reduceMotion: Boolean = false,
) {
    DisposableEffect(store) {
        store.rummyScreenDidAppear()
        onDispose { store.rummyScreenDidDisappear() }
    }
    LaunchedEffect(art) {
        art.prepare()
        art.refreshIfNeeded()
    }
    val rummy = store.context.rummy ?: return
    val now: () -> SwiftDate = { rummy.clock() }
    val goBack: () -> Unit = { back.handleBack(rummy, onLeave) }
    val showRules: () -> Unit = { rummy.rulesShown = true }
    LaunchedEffect(rummy.phase, rummy.match?.status) {
        back.sync(rummy)
        if (rummy.phase != RummyPhase.playing) back.reactionPicking = false
    }
    val anchors = remember { GamesRummyReactionAnchors() }
    // 가로일 때 카메라 구멍을 피한다 — 셸 여백(시스템 막대 몫)에는 컷아웃이 안 든다.
    val cutout = if (store.rummyInterfaceOrientation == GamesRummyInterfaceOrientation.landscape) Modifier.windowInsetsPadding(WindowInsets.displayCutout.only(WindowInsetsSides.Horizontal)) else Modifier
    CompositionLocalProvider(LocalGamesRummyArt provides art, LocalGamesRummyReactionAnchors provides anchors) {
        Box(modifier.fillMaxSize().background(AingTheme.colors.background).then(cutout)) {
            val unavailable = RummyPhoneText.unavailable(rummy.availability)
            when {
                unavailable != null -> Column(Modifier.fillMaxSize().testTag(GamesRummyTags.UNAVAILABLE)) {
                    GamesHeaderBar(RummyPhoneText.title, onBack = goBack)
                    EmptyState(
                        if (rummy.availability == RummyAvailability.updateRequired) AppIcon.ArrowCircleUp else null,
                        unavailable,
                        Modifier.padding(horizontal = AingDimens.sideMargin),
                    )
                }
                rummy.phase == RummyPhase.lobby ->
                    GamesRummyLobbyView(store, rummy, myUserID, me, onRules = showRules, onBack = goBack, now = now, modifier = Modifier.fillMaxSize().testTag(GamesRummyTags.LOBBY))
                rummy.phase == RummyPhase.room ->
                    GamesRummyRoomView(rummy, myUserID, me, onRules = showRules, onBack = goBack, now = now, block = store.rummyEntryBlock, balance = store.rubyBalance ?: rummy.rubyBalance, modifier = Modifier.fillMaxSize().testTag(GamesRummyTags.ROOM))
                rummy.phase == RummyPhase.playing ->
                    GamesRummyMatchView(rummy, myUserID, me, reduceMotion, onRules = showRules, onBack = goBack, now = now, modifier = Modifier.fillMaxSize().testTag(GamesRummyTags.MATCH), onReaction = { back.reactionPicking = true })
                else ->
                    GamesRummyResultView(rummy, myUserID, me, reduceMotion, onRules = showRules, onBack = goBack, now = now, block = store.rummyEntryBlock, modifier = Modifier.fillMaxSize().testTag(GamesRummyTags.RESULT), showsBoard = store.isRummyFinalBoardShown, onShowBoard = store::setRummyFinalBoardShown)
            }
            // 말풍선은 방·판·결과 위에 함께 뜬다(앵커는 자리를 그리는 뷰가 단다).
            if (rummy.phase != RummyPhase.lobby) GamesRummyReactionLayer(rummy, reduceMotion, now, Modifier.fillMaxSize())
            if (back.reactionPicking && rummy.phase == RummyPhase.playing) GamesRummyReactionPanel(rummy, now, onClose = { back.reactionPicking = false })
        }
        if (rummy.rulesShown) GamesRummyRulesSheet(onDismiss = { rummy.rulesShown = false })
        back.asking?.let { decision ->
            GamesRummyExitDialog(decision, onKeep = { back.keep() }, onConfirm = { back.confirm(rummy, onLeave) })
        }
    }
}
