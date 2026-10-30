// 원본: Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift @ 3bd04bd
// 원본: Sources/check/MiniGamePanel.swift:466-604 @ 3bd04bd (정지 카드·카운트다운·5분 상한 — Android ON_PAUSE 몫, G §8-2. 전이 표는 core MiniGamePauseState)
//
// 미니게임 화면(SPEC-ios §3.5): 머리 줄(최고 · 오늘 순위 · 안내) · 캔버스(논리 292×302 를 폭에 **등비 확대**) · (테트리스만) 버튼 줄 · 오늘 순위.
//  · 캔버스 어디든 **누르는 순간** = 행동(손을 뗄 때 발화하면 점프 게임엔 그 지연이 곧 낙차다).
//  · 프레임 상한은 화면 주사율을 core `MiniGameFrameRate` 에 넣은 값이다([MiniGameFrameLoop]).
//  · 햅틱 네 채널: 판에 먹힌 탭(가볍게) · 하드드롭(단단하게) · 줄소거(묵직하게) · 게임오버·완주(한 번). 이동·소프트드롭 걸음에는 없다
//    (L1 소프트드롭이 초당 56회, L5 는 213회 — 진동기가 낼 수 있는 속도가 아니다).
//  · 앱이 background 로 가거나 화면을 떠나면 판은 끝 — 스토어·허브가 한다(`GamesMiniGameHub.appDidEnterBackground`·`closeScreen`).
//    기존 두 게임은 제출하지 않고, **테트리스는 여기까지의 점수로 확정 제출한다.**
//  · Android 만의 몫(G §8-2): 앱이 산 채로 **초점을 잃으면**(멀티 창 ON_PAUSE) 판을 얼린다 — 전이는 맥과 한 벌(core MiniGamePauseState).
//    얼린 동안 캔버스를 가린다(판을 들여다보며 다음 기둥을 외우는 것이 순위표 앞에서 이득이면 안 된다). 누적 5분이면 그 판을 끝낸다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameCanvas
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisLayout
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameBoard
import com.yehsung.aingcheck.core.stores.minigame.MiniGamePauseState
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import com.yehsung.aingcheck.core.stores.games.MobileLoadKnowledge
import com.yehsung.aingcheck.ui.games.minigame.kit.ChampionRow
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.InlineNotice
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadFailureRow
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadingRow
import com.yehsung.aingcheck.ui.games.minigame.kit.NoticeKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonName
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.RankBadge
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 화면 테스트 꼬리표(시험·계측이 캔버스를 찾는다). */
object MiniGameScreenTags {
    const val CANVAS: String = "minigame.canvas"
    const val HOLD: String = "minigame.tetris.hold"
    const val ROTATE: String = "minigame.tetris.rotate"
    const val HARD_DROP: String = "minigame.tetris.hardDrop"
}

/**
 * 미니게임 화면 하나. 열림·닫힘은 허브가 쥔다([GamesStore.miniGames] `openScreen`·`closeScreen` — 이 화면이 나타나고 사라질 때 한 번씩).
 *
 * @param refreshHz 이 화면이 선 디스플레이의 주사율(Android 셸이 `Display.refreshRate` 를 읽어 넘긴다 — 바뀌면 루프가 새 간격으로 다시 선다).
 * @param windowFocused 앱이 산 채로 초점을 가졌는가(Android ON_PAUSE·ON_RESUME). 거짓이 되면 진행 중인 판을 얼린다(G §8-2).
 * @param myUserID 순위 '나' 행 고르기(폰 세션 — Swift `context.session.session?.userID.lowercased()`).
 * @param pauseToggleSerial 바깥 정지 토글(공용 패치 11 — 데스크톱 창의 ESC). 값이 **바뀔 때마다** 한 번 [MiniGamePauseState.toggled]
 *   (맥 ESC 와 같은 전이 — 판 중이면 정지, 정지면 3-2-1, 카운트다운이면 다시 정지). 기본 0 이고 안 바꾸면 아무 일도 없다.
 * @param onFrozenChanged 판이 얼었는가(정지 카드 · 3-2-1)가 바뀔 때. 껍데기가 얼어 있는 동안 조작 키를 막는 데 쓴다. 기본 {}.
 */
@Composable
fun GamesMiniGameScreen(
    store: GamesStore,
    kind: MiniGameKind,
    refreshHz: Int,
    art: MiniGameArt,
    myUserID: String?,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    windowFocused: Boolean = true,
    reduceMotion: Boolean = false,
    pauseToggleSerial: Int = 0,
    onFrozenChanged: (Boolean) -> Unit = {},
) {
    val hub = store.miniGames
    DisposableEffect(kind) {
        hub.openScreen(kind)
        onDispose { hub.closeScreen(kind) }
    }
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().background(colors.background)) {
        GamesHeaderBar(kind.title, onBack = onBack)
        BoxWithConstraints(Modifier.fillMaxSize().padding(horizontal = AingDimens.sideMargin)) {
            // 캔버스는 **폭이 정한다**(좌우 16 여백 안 폭 × 302/292). 아래 순위 스크롤과 높이를 나눠 갖게 두면 비율 맞춤이 캔버스를 좁혀
            // 양옆에 빈 띠가 생긴다(데모 스크린샷 실측).
            val width = maxWidth
            Column(Modifier.fillMaxSize().padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing)) {
                MiniGameHeader(store, kind)
                val controller = hub.controller
                if (controller != null && controller.kind == kind) {
                    MiniGamePlaySurface(
                        store, controller, refreshHz, art, windowFocused, reduceMotion,
                        Modifier.width(width).aspectRatio((MiniGameCanvas.logicalWidth / MiniGameCanvas.logicalHeight).toFloat()),
                        pauseToggleSerial, onFrozenChanged,
                    )
                    // 테트리스만 버튼 줄이 붙는다 — 끌기로 표현할 수 없는 셋(홀드 · 반시계 회전 · 즉시 내리기)이다.
                    if (kind == MiniGameKind.tetris) TetrisControls(controller, width)
                } else {
                    Box(
                        Modifier.width(width).aspectRatio((MiniGameCanvas.logicalWidth / MiniGameCanvas.logicalHeight).toFloat())
                            .clip(RoundedCornerShape(14.dp)).background(GamesCanvasColors.panel),
                    )
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = AingDimens.space6)) {
                    if (!hub.isPublic) InlineNotice(GamesMiniGameText.privateNotice, Modifier.padding(bottom = AingDimens.space2), NoticeKind.Info)
                    MiniGameRankings(store, kind, myUserID)
                }
            }
        }
    }
}

// MARK: 머리 줄

@Composable
private fun MiniGameHeader(store: GamesStore, kind: MiniGameKind) {
    val hub = store.miniGames
    val colors = AingTheme.colors
    val best = hub.best(kind)
    val board = hub.boards[kind] ?: GamesMiniGameBoard()
    val rank = hub.myRank(kind)
    val rankLine = GamesMiniGameText.rankLine(rank, board.knowsPlayerCount)
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            // 트로피는 금(순위 메달 색) — 앰버는 연결 끊김·대기 전용이다.
            AingIcon(AppIcon.TrophyFill, contentDescription = null, size = 18.dp, tint = colors.gold)
            Spacer(Modifier.width(6.dp))
            Text(GamesMiniGameText.bestLine(best), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM), color = colors.label)
            Spacer(Modifier.weight(1f))
            // 오늘 순위 한 줄. 순위표를 모르면(불러오는 중·실패) 그리지 않는다 — 실패는 아래 순위 카드가 말한다.
            if (rank != null) {
                Row(
                    Modifier.semantics(mergeDescendants = true) { contentDescription = rankLine ?: "오늘 ${rank}위" },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("오늘", style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                    RankBadge(rank)
                }
            } else if (rankLine != null) {
                Text(rankLine, style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = TNUM), color = colors.label2)
            }
        }
        // 제출 실패·판 끝남은 조용히 삼키지 않는다(삼키면 "잘 놀았는데 순위표에 없다"가 된다).
        val notice = hub.submitNotice
        if (notice != null) Text(notice, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.danger)
    }
}

// MARK: 판(UI 루프) + 정지

/**
 * 캔버스 + 정지(Android 초점 상실). 정지는 이 화면의 상태다(맥 `CheckMiniGameWindowView.PauseState` 와 같은 주인 — 게임은 얼었는가만 읽는다).
 * 전이는 core [MiniGamePauseState] 한 벌: 초점 상실 → `resigningKey`(언제나 얼린다 · 이미 정지면 그대로) · [이어하기] → `toggled`(3-2-1) ·
 * 1초마다 `steppedDown`. **누적** 정지가 [MiniGamePauseState.PAUSE_LIMIT_SECONDS] 를 넘으면 그 판을 끝낸다(허브 `appDidEnterBackground` 와 같은
 * 출구 — 테트리스는 확정 제출, 나머지는 기록 없이). 상한은 순위 공정성의 보루라 사용자 스위치가 아니다.
 */
@Composable
private fun MiniGamePlaySurface(
    store: GamesStore,
    controller: GamesPlayController,
    refreshHz: Int,
    art: MiniGameArt,
    windowFocused: Boolean,
    reduceMotion: Boolean,
    modifier: Modifier,
    pauseToggleSerial: Int = 0,
    onFrozenChanged: (Boolean) -> Unit = {},
) {
    var pause by remember(controller) { mutableStateOf<MiniGamePauseState>(MiniGamePauseState.None) }
    var pausedSeconds by remember(controller) { mutableStateOf(0) }
    val playing = controller.isPlaying
    // 새 판(또는 판이 끝남)에서 누적을 비운다 — 누적은 **판마다** 잰다.
    LaunchedEffect(controller, playing) { if (!playing) { pausedSeconds = 0; pause = MiniGamePauseState.None } }
    LaunchedEffect(windowFocused) {
        if (!windowFocused) pause.resigningKey(controller.isPlaying)?.let { pause = it }
    }
    // 바깥 정지 토글(공용 패치 11): 판이 설 때의 값을 기준으로, 바뀔 때마다 한 번 맥 ESC 전이. 기본 0 그대로면 들어오지 않는다.
    val seenToggle = remember(controller) { intArrayOf(pauseToggleSerial) }
    LaunchedEffect(controller, pauseToggleSerial) {
        if (pauseToggleSerial != seenToggle[0]) {
            seenToggle[0] = pauseToggleSerial
            pause = pause.toggled(controller.isPlaying)
        }
    }
    // 얼었는가를 밖에 알린다(바뀔 때 · 화면이 사라지면 풀림으로).
    val frozen = pause.isFrozen
    val reportFrozen by rememberUpdatedState(onFrozenChanged)
    LaunchedEffect(frozen) { reportFrozen(frozen) }
    DisposableEffect(Unit) { onDispose { reportFrozen(false) } }
    // 카운트다운 한 걸음 = 1초.
    LaunchedEffect(pause) {
        if (pause.countdown != null) {
            delay(1000)
            pause = pause.steppedDown()
        }
    }
    // 정지 누적(초). 얼어 있는 동안만 센다.
    LaunchedEffect(pause.isFrozen, controller) {
        while (pause.isFrozen) {
            delay(1000)
            pausedSeconds += 1
            if (pausedSeconds >= MiniGamePauseState.PAUSE_LIMIT_SECONDS) {
                pause = MiniGamePauseState.None
                store.miniGames.appDidEnterBackground()
                break
            }
        }
    }
    Box(modifier) {
        GamesMiniGameCanvasHost(controller, store.miniGames.best(controller.kind), refreshHz, art, Modifier.fillMaxSize(), reduceMotion, frozen = pause.isFrozen)
        if (pause.isFrozen) MiniGamePauseOverlay(pause, onResume = { pause = pause.toggled(controller.isPlaying) })
    }
}

/** 정지 가림막: 캔버스를 통째로 가린다(판을 들여다보는 이득이 없게) · 정지 카드([이어하기]) 또는 3-2-1. */
@Composable
private fun MiniGamePauseOverlay(pause: MiniGamePauseState, onResume: () -> Unit) {
    Box(
        Modifier.fillMaxSize().clip(RoundedCornerShape(14.dp)).background(GamesCanvasColors.panel.copy(alpha = 0.96f)),
        contentAlignment = Alignment.Center,
    ) {
        val countdown = pause.countdown
        if (pause.showsCard) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                AingIcon(AppIcon.PauseCircleFill, contentDescription = null, size = 36.dp, tint = GamesCanvasColors.primaryText)
                Text("일시정지", style = MaterialTheme.typography.titleMedium, color = GamesCanvasColors.primaryText)
                PillButton("이어하기", kind = PillKind.Filled, onClick = onResume)
            }
        } else if (countdown != null) {
            Text(countdown.toString(), style = MaterialTheme.typography.displayLarge.copy(fontWeight = FontWeight.ExtraBold), color = GamesCanvasColors.primaryText)
        }
    }
}

/**
 * **UI 루프** — 프레임 루프 · 손가락 · 그림 · 햅틱 · 보이스오버. 미니게임 화면이 쓰는 것과 같은 것이고 시험(대본 재생)이 이것을 통째로 몬다.
 *
 * INV-GamesMiniGameScreen-99a8a013 이식: **테트리스는 진행 중일 때만 다르다** — 한 번의 끌기가 여러 칸을 만들고 행동도 셋(좌·우·소프트드롭)이라
 *   래치로는 표현이 안 된다. 그때만 구동기의 제스처 트래커로 넘긴다. 시작 화면에서는 테트리스도 래치가 판을 켠다(트래커로만 받으면 0.25초를
 *   넘겨 천천히 뗀 사람에게 시작이 안 되고, 그건 '고장'으로 읽힌다). 갈래는 아래 [canvasGesture] 의 `isPlaying` 이다.
 * INV-GamesMiniGameScreen-48c66a1e 이식: 손가락 입력(`pointerInput`)은 **이 자리 하나**에 걸고, 게임 종류·진행 여부 갈래는 **핸들러 안**에 둔다 —
 *   종류로 수정자 자체를 갈라 붙이면 노드 정체성이 갈려 진행 중인 접촉이 끊긴다(Compose 는 키가 바뀌면 포인터 입력 코루틴을 다시 띄운다 —
 *   그래서 키는 구동기 하나다).
 */
@Composable
fun GamesMiniGameCanvasHost(
    controller: GamesPlayController,
    bestScore: Long,
    refreshHz: Int,
    art: MiniGameArt,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = false,
    frozen: Boolean = false,
) {
    val density = LocalDensity.current.density
    val kind = controller.kind
    MiniGameFrameLoop(running = controller.isPlaying && !frozen, refreshHz = refreshHz) { nanos ->
        controller.tick(MiniGameFramePacer.tickDate(nanos))
    }
    MiniGameHaptics(controller)
    val shape = RoundedCornerShape(14.dp)
    BoxWithConstraints(
        modifier
            .clip(shape)
            .background(GamesCanvasColors.panel)
            .border(1.dp, AingTheme.colors.separator, shape)
            .testTag(MiniGameScreenTags.CANVAS)
            .canvasGesture(controller, density, frozen)
            .canvasSemantics(controller),
    ) {
        // 한 칸 문턱은 **화면 셀 폭**이다(논리 13 × 배율) — 폭이 정해질 때마다 건넨다.
        val widthDp = maxWidth.value.toDouble()
        LaunchedEffect(controller, widthDp) { controller.updateCellWidth(TetrisLayout.cell * widthDp / TetrisLayout.logicalSize.width) }
        when (kind) {
            MiniGameKind.timingBar -> GamesTimingBarCanvas(controller.timing, bestScore, reduceMotion, Modifier.fillMaxSize())
            MiniGameKind.flappy -> GamesFlappyCanvas(controller.flappy, bestScore, reduceMotion, art, Modifier.fillMaxSize())
            MiniGameKind.tetris -> GamesTetrisCanvas(controller.tetris, bestScore, reduceMotion, Modifier.fillMaxSize())
            // 길건너 아잉이(v0.3.67)는 폰에 아직 없다 — phoneCases 가 거르므로 이 화면이 crossy 로 열리지 않는다(G §8-18 7).
            MiniGameKind.crossy -> Unit
        }
    }
}

/**
 * 캔버스 위 한 번의 접촉. 갈래는 **'진행 중인가'** 이지 종류가 아니다 — 시작 화면에서는 테트리스도 래치가 판을 켠다.
 *
 * 다 쓴 접촉 표시([swallowed])는 불리언이 아니라 **접촉 id** 다 — 끝(up)이 늘 오지 않는다(시스템 제스처·전화 수신으로 취소). 참인 채 남으면
 * 그다음 멀쩡한 탭의 회전이 대신 삼켜진다. 들어오는 길은 둘: ① 시작 래치가 판을 켠 그 접촉(안 삼키면 한 번의 탭이 시작과 회전을 둘 다 하고,
 * 그 손가락이 한 칸 폭 이상 흔들리면 새 판 첫 조각이 곧장 옆으로 간다) ② 그 접촉으로 끌던 도중에 판이 끝난 경우(같은 손가락이 새 판을 켜면
 * 트래커에 남은 앞 끌기의 축 잠금으로 첫 조각이 튄다).
 */
private fun Modifier.canvasGesture(controller: GamesPlayController, density: Float, frozen: Boolean): Modifier = pointerInput(controller, frozen) {
    if (frozen) return@pointerInput
    fun toPoints(px: Float): Double = px / density.toDouble()
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val start = MiniGamePoint(toPoints(down.position.x), toPoints(down.position.y))
        val startMillis = down.uptimeMillis
        fun date(millis: Long): SwiftDate = SwiftDate.fromReferenceDate(millis / 1000.0)
        val isTetris = controller.kind == MiniGameKind.tetris
        var swallowed = false
        var playContact = false
        // 첫 변화(= 누름) — 래치 또는 트래커.
        if (isTetris && controller.isPlaying) {
            playContact = true
            controller.canvasDragChanged(start, MiniGameSize(0.0, 0.0), date(startMillis))
        } else {
            val wasPlaying = controller.isPlaying
            controller.tap()
            if (isTetris && !wasPlaying && controller.isPlaying) swallowed = true
        }
        down.consume()
        var lastTranslation = MiniGameSize(0.0, 0.0)
        var lastMillis = startMillis
        while (true) {
            val event = awaitPointerEvent()
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            lastTranslation = MiniGameSize(toPoints(change.position.x) - start.x, toPoints(change.position.y) - start.y)
            lastMillis = change.uptimeMillis
            if (!change.pressed) break
            change.consume()
            if (!isTetris || swallowed) continue
            if (!controller.isPlaying) {
                // 이 접촉이 끌던 판이 방금 끝났다(상한·탑아웃) — 같은 손가락이 새 판을 켜면 안 된다.
                if (playContact) swallowed = true
                continue
            }
            playContact = true
            controller.canvasDragChanged(start, lastTranslation, date(lastMillis))
        }
        // 끝(뗌) — 테트리스만: 다 쓴 접촉이 아니고 판이 진행 중이면 탭 판정(시계 회전).
        if (isTetris && !swallowed && controller.isPlaying) controller.canvasDragEnded(lastTranslation, date(lastMillis))
    }
}

/**
 * 보이스오버(TalkBack). 기본 동작: 진행 중이면 시계 회전, 시작 전·결과면 새 판(구동기가 가른다).
 * 테트리스에는 **직접 조작을 걸지 않는다**(셀이 15~18 인 판에서 눈 없이 겨냥하라는 뜻이라 실질 조작이 불가능하다) — 버튼이 없는 조작만 액션으로 낸다.
 */
private fun Modifier.canvasSemantics(controller: GamesPlayController): Modifier = semantics {
    contentDescription = GamesMiniGameText.canvasAccessibility(controller.kind)
    stateDescription = accessibilityValue(controller)
    role = Role.Button
    onClick { controller.tap(); true }
    if (controller.kind == MiniGameKind.tetris && controller.isPlaying) {
        customActions = listOf(
            CustomAccessibilityAction(GamesMiniGameText.tetrisMoveLeft) { controller.moveLeftOneCell(); true },
            CustomAccessibilityAction(GamesMiniGameText.tetrisMoveRight) { controller.moveRightOneCell(); true },
            CustomAccessibilityAction(GamesMiniGameText.tetrisSoftDrop) { controller.softDropOneCell(); true },
        )
    }
}

/** 보이스오버 값. 테트리스는 **느린 값만**(점수·레벨·줄) — 조각 자리를 넣으면 읽는 동안 값이 계속 바뀐다. */
internal fun accessibilityValue(controller: GamesPlayController): String = when (controller.kind) {
    MiniGameKind.timingBar -> {
        val phase = controller.timing.phase
        if (phase is TimingBarGame.Phase.Finished) "총점 ${phase.total}"
        else if (controller.isPlaying) "라운드 ${maxOf(1, controller.timing.round)}, 총점 ${controller.timing.total}"
        else GamesMiniGameText.startAction
    }
    MiniGameKind.flappy ->
        if (controller.flappy.phase == FlappyGame.Phase.Result || controller.isPlaying) "${controller.flappy.score}점" else GamesMiniGameText.startAction
    MiniGameKind.tetris -> {
        val game = controller.tetris
        if (game.phase == TetrisGame.Phase.Ready) GamesMiniGameText.startAction
        else GamesMiniGameText.tetrisValue(game.score, game.scoreLevel, game.lines)
    }
    MiniGameKind.crossy -> GamesMiniGameText.startAction
}

/** 햅틱 네 채널(serial 이 오를 때만 — 처음 값은 기준이다). */
@Composable
private fun MiniGameHaptics(controller: GamesPlayController) {
    val haptics = LocalHapticFeedback.current
    SerialHaptic(controller.tapSerial) { haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }
    SerialHaptic(controller.hardDropSerial) { haptics.performHapticFeedback(HapticFeedbackType.ContextClick) }
    SerialHaptic(controller.lineClearSerial) { haptics.performHapticFeedback(HapticFeedbackType.LongPress) }
    SerialHaptic(controller.gameOverSerial) { haptics.performHapticFeedback(HapticFeedbackType.Reject) }
}

@Composable
private fun SerialHaptic(serial: Int, fire: () -> Unit) {
    val initial = remember { serial }
    val action by rememberUpdatedState(fire)
    LaunchedEffect(serial) { if (serial != initial) action() }
}

// MARK: 테트리스 — 버튼 줄

/**
 * 캔버스와 같은 폭 W. [홀드][반시계][즉시 내리기] — 간격 8·16 을 뺀 쓸 폭을 26 : 30 : 44 로 나눈다.
 * **확인 대화상자를 넣지 마라**(즉시 내리기에도): L15 부터 20G 라 조각이 스폰과 같은 틱에 접지하고 락딜레이가 0.16초다 — 확인창 한 번이 그 예산 전부다.
 */
@Composable
private fun TetrisControls(controller: GamesPlayController, width: Dp) {
    val usable = (width - AingDimens.space2 - AingDimens.space4).coerceAtLeast(0.dp)
    Row(Modifier.width(width)) {
        TetrisControlButton(
            GamesMiniGameText.tetrisHold, AppIcon.FilterNone, usable * 0.26f, isSpent = controller.tetris.holdUsed,
            firesOnTouchDown = true, tag = MiniGameScreenTags.HOLD, spentValue = GamesMiniGameText.tetrisHoldSpent,
        ) { controller.hold() }
        // 죽은 간격이다 — 버튼 쪽으로 넓히지 마라.
        Spacer(Modifier.width(AingDimens.space2))
        TetrisControlButton(
            GamesMiniGameText.tetrisRotateCounterClockwise, AppIcon.RotateLeft, usable * 0.30f, firesOnTouchDown = true, tag = MiniGameScreenTags.ROTATE,
        ) { controller.rotate(clockwise = false) }
        Spacer(Modifier.width(AingDimens.space4))
        TetrisControlButton(
            GamesMiniGameText.tetrisHardDrop, AppIcon.VerticalAlignBottom, usable * 0.44f, firesOnTouchDown = false, tag = MiniGameScreenTags.HARD_DROP,
        ) { controller.hardDrop() }
    }
}

/**
 * 조작 버튼 한 개 — 아이콘 위 + 글자 아래 · 높이 48 · **틴트**(채운 버튼은 화면당 하나라는 규약 — 하나도 채우지 않는다). 눌림은 **색만**.
 * 발화 시점이 둘: 홀드·반시계는 **터치-다운**(20G 구간에서는 뗌을 기다릴 여유가 없다), 즉시 내리기만 **터치-업 안쪽**(끌어 빼면 취소 —
 * 잘못 누르면 그 판이 끝난다). 소진(홀드를 이미 씀)은 채움을 빼고 글자를 한 단계 내린다 — **비활성으로 만들지 않는다**(조각마다 꺼졌다 켜져
 * 보이스오버가 버튼을 목록에서 뺐다 넣었다 한다).
 */
@Composable
internal fun TetrisControlButton(
    title: String,
    icon: AppIcon,
    width: Dp,
    firesOnTouchDown: Boolean,
    tag: String,
    isSpent: Boolean = false,
    spentValue: String? = null,
    action: () -> Unit,
) {
    val colors = AingTheme.colors
    var pressed by remember { mutableStateOf(false) }
    val onAction by rememberUpdatedState(action)
    val ink = if (isSpent) colors.label2 else colors.accent
    val press = if (firesOnTouchDown) {
        // INV-GamesMiniGameScreen-e292b3f8 이식: 눌림은 **접촉 하나**에 묶는다(불리언 래치가 아니다) — 끝(up/cancel)이 오지 않아도 다음 접촉은 새 id 라
        //   늘 통과한다. 래치가 굳어 버튼이 화면을 떠날 때까지 죽는 길(홈 끌어 올리기·전화 수신)을 막는다. 남는 것은 눌린 색뿐이다.
        Modifier.pointerInput(Unit) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                pressed = true
                onAction()
                down.consume()
                try {
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!change.pressed) break
                    }
                } finally {
                    pressed = false
                }
            }
        }
    } else {
        Modifier.clickable(role = Role.Button) { onAction() }
    }
    Column(
        Modifier
            .width(width)
            .height(48.dp)
            .clip(CircleShape)
            .background(if (isSpent) androidx.compose.ui.graphics.Color.Transparent else colors.accentTint)
            .then(if (isSpent) Modifier.border(1.dp, colors.separator, CircleShape) else Modifier)
            .alpha(if (pressed) 0.75f else 1f)
            .testTag(tag)
            .semantics {
                contentDescription = title
                role = Role.Button
                if (isSpent && spentValue != null) stateDescription = spentValue
                onClick { onAction(); true }
            }
            .then(press),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        AingIcon(icon, contentDescription = null, size = 17.dp, tint = ink)
        Text(title, style = MaterialTheme.typography.labelSmall, color = ink, maxLines = 1)
    }
}

// MARK: 오늘 순위

@Composable
private fun MiniGameRankings(store: GamesStore, kind: MiniGameKind, myUserID: String?) {
    val hub = store.miniGames
    val colors = AingTheme.colors
    val state = hub.boards[kind] ?: GamesMiniGameBoard()
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    // 정족수 줄은 사람 수를 알 때만 — 불러오지 못했거나 불러오는 중이면 "아무도 안 했어요"라고 말하지 않는다.
    SectionHeader(
        GamesMiniGameText.rankTitle,
        trailing = if (state.knowsPlayerCount) SectionTrailing.Label(GamesMiniGameText.quorumCaption(state.entries.size)) else SectionTrailing.None,
        modifier = Modifier.padding(start = AingDimens.titleMargin - AingDimens.sideMargin, end = AingDimens.titleMargin - AingDimens.sideMargin, top = 4.dp, bottom = 8.dp),
    )
    // 어제 1등은 **자기 그룹**(순위 탭과 같은 꼴) — '오늘 순위' 첫 행처럼 읽히지 않게 떼어 둔다.
    state.yesterdayWinner?.let { winner ->
        ChampionRow(
            GamesMiniGameText.yesterdayChampion, winner.name, winner.center, GamesMiniGameText.score(winner.score),
            if (winner.awarded) GamesMiniGameText.rubyPrizes[0] else null, Modifier.padding(bottom = 12.dp),
        )
    }
    InsetGroup {
        if (state.entries.isEmpty()) {
            GroupRow(dividerInset = null) {
                when (state.placeholder) {
                    MobileLoadKnowledge.Placeholder.failed ->
                        LoadFailureRow(GamesMiniGameText.failedCaption, isRetrying = state.loading) {
                            scope.launch { hub.loadBoard(kind, withWinner = true) }
                        }
                    MobileLoadKnowledge.Placeholder.loading -> LoadingRow(GamesMiniGameText.loadingCaption)
                    MobileLoadKnowledge.Placeholder.empty, MobileLoadKnowledge.Placeholder.rows ->
                        Text(GamesMiniGameText.emptyBoard, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                }
            }
        } else {
            state.entries.forEachIndexed { index, entry ->
                MiniGameRankRow(index + 1, entry, entry.userID == myUserID, index == state.entries.size - 1)
            }
        }
    }
    Text(
        GamesMiniGameText.prizeCaption, style = rowSubtitleStyle(), color = colors.label2,
        modifier = Modifier.padding(start = AingDimens.titleMargin - AingDimens.sideMargin, top = AingDimens.space2),
    )
}

/** 오늘 순위 한 줄(순위 탭과 같은 꼴): 등수 원 · 얼굴 · 이름(+ 센터 · '나') · 점수. 내 행 = 파랑 6%. */
@Composable
private fun MiniGameRankRow(rank: Int, entry: MiniGameBoardEntry, isMe: Boolean, isLast: Boolean) {
    val colors = AingTheme.colors
    GroupRow(
        dividerInset = if (isLast) null else AingDimens.cardPadding + 24.dp + AingDimens.space3 + 30.dp + AingDimens.space3,
        minHeight = 48.dp,
        padding = androidx.compose.foundation.layout.PaddingValues(horizontal = AingDimens.cardPadding, vertical = 7.dp),
        isHighlighted = isMe,
        modifier = Modifier.semantics(mergeDescendants = true) { },
    ) {
        RankBadge(rank)
        PersonAvatar(entry.name, entry.userID, 30.dp)
        PersonName(entry.name, Modifier.weight(1f), center = entry.center, isMe = isMe)
        Text(GamesMiniGameText.score(entry.bestScore), style = MaterialTheme.typography.titleSmall.copy(fontFeatureSettings = TNUM), color = colors.label)
    }
}
