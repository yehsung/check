// 원본: Sources/CheckMobileKit/Games/GamesRummyMatch.swift:1 @ ios-1017-cube d5c9eeff · 맥 Sources/check/RummyPanelMatch.swift:247 (RummyMatchView) · Sources/check/RummyTableCanvas.swift:192 · Sources/check/RummyRackView.swift:90 @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §10
//
// 아잉 큐브 판(**가로 화면**) — 왼쪽 열(뒤로 · 규칙 · 자리 카드) | 가운데(판 · 상태 줄 · 받침대) | 오른쪽 열(판돈 · 더미 · 반응 · 전체 보기 · 동작 버튼). 칸 자리는 GamesRummyMatchLayout 한 곳에서 나온다. 입력: [onBack] 은 [나가기](껍데기가 기권 확인을 띄운다).
// 말풍선은 껍데기 층(GamesRummyReactionLayer)이 그린다 — 이 뷰는 자리 앵커만 단다(왼쪽 열 카드). 탭 막대 숨김은 셸 몫(TabBarPolicy.rummyMatch) · 시스템 뒤로는 껍데기의 뒤로 판단이 받는다.
// 방향은 이 뷰가 정하지 않는다(core GamesRummyOrientation.kt). 전환 중 세로 크기로 불리면 칸을 세우지 않고 안내만 그린다.
// 다른 기기 판(isEngagedInCurrentMatch 거짓)은 안내 카드만 얹는다 — 입력은 막지 않는다(맥과 같다).
//
// ── 입력 ──
// **화면 전체에 pointerInput 하나**([rummyTouchInput])다. 그림 층(판 · 받침대)은 손을 안 받고, 그 위에 빈 층 하나, 다시 그 위에 버튼들(양옆 열 · 판 위 배지)이 있어 버튼은 입력 층보다 먼저 눌린다.
// 시작 자리를 GamesRummyHitTester 로 가르고 나머지는 GamesRummyTouchMachine(순수)이 정한다. 그려지는 자리와 재는 자리가 같은 값에서 나온다.
//
// ── 성능 ──
// 이 본문은 손이 움직여도 다시 돌지 않는다 — 보기 · 손가락 자리를 조립 단계에서 읽지 않는다(층 · 그리기 단계만, 판 위 조작은 파생값만). 시간은 잎의 고리, 잠깐 떴다 사라지는 표시는 열쇠가 안 바뀌는 효과다(맥 0.3.69 재생성 고리 금지).
// 모션(설계서 §7 · 값은 GamesRummyMotion): 뽑기 비행 · 정렬 시차는 받침대가, 판 변화는 판 칸이 그린다. 이 뷰는 사건을 넘긴다. 동작 줄이기면 모두 꺼진다.
//
// VoiceOver 몫: 끌기 대안(타일 고르기 → 판에 놓기)은 이번 범위 밖이다(설계서 §4). 라벨(면 · 장수 · 차례 · 남은 초)과 [완료 · 뽑기 · 되돌리기 · 나가기] 버튼 동작은 있다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasPoint
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasRect
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyRackLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSort
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.rules.rummy.rackMelds
import com.yehsung.aingcheck.core.stores.rummy.RummyEditorKey
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.isEngagedInCurrentMatch
import com.yehsung.aingcheck.core.stores.rummy.sortRack
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.ui.theme.AingMotion
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay

/** 판 화면 꼬리표(시험 · 계측). */
object GamesRummyMatchTags {
    const val INPUT: String = "rummy.match.input"
    const val BOARD: String = "rummy.match.board"
    const val BOARD_LAYER: String = "rummy.match.boardLayer"
    const val BOARD_MOTION: String = "rummy.match.boardMotion"
    const val RACK: String = "rummy.match.rack"
    const val RACK_REFUSED: String = "rummy.match.rackRefused"
    const val STATUS: String = "rummy.match.status"
    const val BACK: String = "rummy.match.back"
    const val RULES: String = "rummy.match.rules"
    const val SUBMIT: String = "rummy.match.submit"
    const val DRAW: String = "rummy.match.draw"
    const val UNDO: String = "rummy.match.undo"
    const val SORT_NUMBER: String = "rummy.match.sortNumber"
    const val SORT_COLOR: String = "rummy.match.sortColor"
    const val ZOOM: String = "rummy.match.zoom"
    const val OFFSCREEN_LEFT: String = "rummy.match.offscreenLeft"
    const val OFFSCREEN_RIGHT: String = "rummy.match.offscreenRight"
    const val OFFSCREEN_UP: String = "rummy.match.offscreenUp"
    const val OFFSCREEN_DOWN: String = "rummy.match.offscreenDown"
    const val ROTATING: String = "rummy.match.rotating"
    const val INFO: String = "rummy.match.info"
    const val MY_SEAT: String = "rummy.match.mySeat"
    const val LAST_EVENT: String = "rummy.match.lastEvent"
    const val WARNING: String = "rummy.match.warning"
    const val ELSEWHERE: String = "rummy.match.elsewhere"
    const val TURN_BADGE: String = "rummy.match.turnBadge"

    fun rackTile(face: String): String = "rummy.match.rackTile.$face"

    fun seat(seatNo: Long?): String = "rummy.match.seat.$seatNo"
}

/** 칸 사각형 그대로 놓는다(판 화면 좌표 · dp). */
internal fun Modifier.atRect(rect: RummyCanvasRect): Modifier = offset(rect.x.dp, rect.y.dp).size(rect.width.dp, rect.height.dp)

/** 기기 가로 방향(Android 조립이 화면 회전 값을 넣는다). 시험 · 데스크톱 렌더는 null — 뒤집힘이 없다. */
val LocalGamesRummyLandscapeSide = compositionLocalOf<GamesRummyLandscapeSide?> { null }

/** 판(가로). [onBack] 은 [나가기](껍데기가 기권 확인을 띄운다) · [onReaction] 은 [반응](고르개는 껍데기가 쥔다). [model] 은 시험이 넣어 재는 자리다. */
@Composable
fun GamesRummyMatchView(
    rummy: RummyStore,
    myUserID: String?,
    me: RummySeatFace,
    reduceMotion: Boolean,
    onRules: () -> Unit,
    onBack: () -> Unit,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
    model: GamesRummyMatchModel = remember { GamesRummyMatchModel() },
    onReaction: () -> Unit = {},
) {
    val match = rummy.match ?: return
    BoxWithConstraints(modifier.background(AingTheme.colors.background).clipToBounds()) {
        val size = RummyCanvasSize(maxWidth.value.toDouble(), maxHeight.value.toDouble())
        // 기기가 돌면 쥔 것을 거둔다(손 자리가 새 칸에서 다른 것을 가리킨다). 칸은 값이라 어느 크기로 불려도 안 깨진다.
        SideEffect { model.screenSizeChanged(size) }
        // 왼쪽 가로 ↔ 오른쪽 가로는 크기가 같아 위 값이 안 깨어난다.
        val side = LocalGamesRummyLandscapeSide.current
        LaunchedEffect(side) { if (side != null) model.landscapeSideChanged(side) }
        // 판이 바뀌면(내 차례 끝 · 남의 확정) 끄는 중이던 타일을 거두고 손을 뗄 때까지 무시한다 — 낡은 id 로 놓지 않게. 같은 차례에 seq 만 오른 것(남의 기권)은 안 거둔다.
        LaunchedEffect(match.seq) { model.boardChanged(rummy.editor, rummy.match?.let(RummyEditorKey::of)) }
        if (GamesRummyMatchLayout.canStand(size)) {
            GamesRummyMatchContent(rummy, match, size, reduceMotion, onRules, onBack, onReaction, now, model)
        } else {
            GamesRummyRotatingView(onBack)
        }
    }
}

@Composable
private fun GamesRummyMatchContent(
    rummy: RummyStore,
    match: RummyMatchState,
    size: RummyCanvasSize,
    reduceMotion: Boolean,
    onRules: () -> Unit,
    onBack: () -> Unit,
    onReaction: () -> Unit,
    now: () -> SwiftDate,
    model: GamesRummyMatchModel,
) {
    val editor = rummy.editor
    val isMyTurn = rummy.isMyTurn && editor != null
    val otherDraft = rummy.otherDraft
    val isWorking = rummy.isWorking
    val scene = remember(match, editor, isMyTurn, otherDraft) { GamesRummyBoardScene.make(match, editor, isMyTurn, otherDraft) }
    // 장부(engagedMatchIDs)는 관찰 값이 아니다 — 판 · 작업이 바뀔 때 다시 본다. 첫 쓰기는 작업 전송 디바운스(0.25초) 뒤라 한 번 더 본다. 효과 안에서 열쇠를 안 쓴다.
    var engaged by remember(match.id) { mutableStateOf(rummy.isEngagedInCurrentMatch) }
    LaunchedEffect(match, editor) {
        engaged = rummy.isEngagedInCurrentMatch
        if (!engaged) {
            delay(400)
            engaged = rummy.isEngagedInCurrentMatch
        }
    }
    val turnKey = RummyEditorKey.of(match)
    val rows = model.rackRows(editor?.rackLayout?.rowCount ?: RummyRackLayout.baseRows, turnKey.text)
    val layout = GamesRummyMatchLayout(size, rows)
    val context = GamesRummyTouchContext(layout, model.viewportUntracked(), scene, editor, isMyTurn, isMyTurn && !isWorking, turnKey)
    SideEffect { model.sync(context) }
    val cue = rememberGamesRummyTurnCue(if (isMyTurn && match.status == RummyMatchStatus.active) turnKey.text else null, reduceMotion) { rummy.isEngagedInCurrentMatch }
    val fresh = rememberGamesRummyFreshDraw(rummy)
    val flight = rememberGamesRummyDrawFlight(rummy, reduceMotion)
    val sorting = rememberGamesRummySortMotion(rummy, reduceMotion)
    val mine = GamesRummySeats.mine(match)
    val line = GamesRummyStatusLine.make(rummy.notice, isMyTurn, editor, GamesRummySeats.turnSeat(match)?.displayName, mine?.state, mine?.timeoutStreak, engaged)
    val plan = gamesRummyPlanLine(editor, isMyTurn)
    val tail = GamesRummyStatusTail.make(match, isMyTurn, otherDraft != null, line)
    Box(Modifier.fillMaxSize()) {
        // 그림 층 — 손을 안 받는다.
        GamesRummyTablePane(model, scene, context.editable, Modifier.atRect(layout.table).testTag(GamesRummyMatchTags.BOARD), reduceMotion = reduceMotion)
        Box(Modifier.atRect(layout.table)) {
            // 묶음은 위부터 깔린다 — 안내가 타일을 덜 가리게 아래쪽에.
            if (!engaged && editor != null) GamesRummyElsewhereCard(Modifier.align(Alignment.BottomCenter).padding(bottom = GamesRummyMatchLayout.elsewhereCardBottom.dp))
            AnimatedVisibility(
                cue.badgeShown && isMyTurn,
                modifier = Modifier.align(Alignment.Center),
                enter = fadeIn(AingMotion.fade(AingMotion.SHORT_MS)) + scaleIn(AingMotion.move(AingMotion.MEDIUM_MS), initialScale = 0.85f),
                exit = fadeOut(AingMotion.fade(AingMotion.MEDIUM_MS)),
            ) { GamesRummyTurnBadge() }
        }
        GamesRummyStatusRow(line, plan?.first, plan?.second == true, tail, Modifier.atRect(layout.status))
        GamesRummyRackPane(
            model = model,
            tiles = editor?.rack ?: emptyList(),
            layout = context.rackLayout,
            geometry = context.rack,
            rackMelds = editor?.rackMelds ?: emptyList(),
            turnGlow = if (isMyTurn && engaged) cue.glow else null,
            freshIDs = fresh,
            reduceMotion = reduceMotion,
            modifier = Modifier.atRect(layout.rack).testTag(GamesRummyMatchTags.RACK),
            flight = flight,
            flightOrigin = layout.drawOrigin,
            stagger = sorting.stagger,
        )
        // 입력 층 — 화면 전체. 아래 버튼 층이 이 층보다 먼저 눌린다.
        Box(Modifier.matchParentSize().testTag(GamesRummyMatchTags.INPUT).rummyTouchInput(model, rummy))
        // 버튼 층.
        GamesRummyNavButtons(onBack, onRules, Modifier.atRect(layout.nav))
        GamesRummySeatColumn(rummy, match, layout, now)
        GamesRummyMatchInfo(match, Modifier.atRect(layout.info))
        GamesRummyToolRow(model, onReaction, Modifier.atRect(layout.tools))
        GamesRummyTableControls(
            model,
            scene.layout.frames,
            reduceMotion,
            Modifier.atRect(layout.table),
            badgeLift = if (engaged) 0.0 else GamesRummyMatchLayout.elsewhereCardBottom + GamesRummyMatchLayout.elsewhereCardHeight,
        )
        GamesRummyActionColumn(rummy, match, editor, isMyTurn, layout, model.locksActions, now, sorting::sort)
        // 손에 든 타일 — 맨 위.
        GamesRummyFloatingBlock(model, Modifier.fillMaxSize())
    }
    GamesRummyEdgePanner(model)
    GamesRummyInputCues(model)
}

/**
 * 입력 층 — 화면 전체에 하나. 8 넘게 움직이면 한 장 · 8 안에서 0.5초면 묶음째 · 두 손가락은 핀치만(핀치 중 한 손가락 끌기 금지) · 끄는 중 두 번째 손가락은 무시.
 * 시스템이 거둔 손(소비된 채 떨어진 up)은 놓기가 아니다 — 끌던 타일이 엉뚱한 자리에 놓이면 안 된다.
 */
private fun Modifier.rummyTouchInput(model: GamesRummyMatchModel, rummy: RummyStore): Modifier =
    pointerInput(model, rummy) {
        fun point(at: Offset): RummyCanvasPoint = RummyCanvasPoint(at.x.toDouble() / density, at.y.toDouble() / density)
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            val opened = model.currentContext ?: return@awaitEachGesture
            model.touchDown(point(down.position), opened)
            down.consume()
            val holdAt = down.uptimeMillis + GamesRummyGestureRules.liftDelayMillis
            var lastUptime = down.uptimeMillis
            var holdTried = false
            var finished = false
            var pinching = false
            var pinchRefused = false
            var magnification = 1.0
            var anchor = RummyCanvasPoint(0.0, 0.0)
            try {
                while (true) {
                    val event = if (model.machine.isAwaitingHold && !holdTried) {
                        withTimeoutOrNull((holdAt - lastUptime).coerceAtLeast(1L)) { awaitPointerEvent() }
                    } else {
                        awaitPointerEvent()
                    }
                    val context = model.currentContext ?: opened
                    if (event == null) {
                        holdTried = true
                        model.holdElapsed(context)
                        continue
                    }
                    lastUptime = event.changes.firstOrNull()?.uptimeMillis ?: lastUptime
                    val pressed = event.changes.count { it.pressed }
                    if (pressed >= 2 && !pinching && !pinchRefused) {
                        if (model.beginPinch()) {
                            pinching = true
                            magnification = 1.0
                            anchor = context.inTable(point(event.calculateCentroid(useCurrent = true)))
                        } else {
                            pinchRefused = true
                        }
                    }
                    if (pinching && pressed < 2) {
                        model.pinchEnded()
                        pinching = false
                    }
                    if (pinching) {
                        magnification *= event.calculateZoom().toDouble()
                        model.pinch(magnification, anchor)
                        event.changes.forEach { it.consume() }
                        continue
                    }
                    val change = event.changes.firstOrNull { it.id == down.id }
                    if (change == null) {
                        model.touchVanished()
                        finished = true
                        break
                    }
                    if (!change.pressed) {
                        if (change.isConsumed) {
                            model.touchVanished()
                        } else {
                            GamesRummyMatchModel.apply(model.touchUp(point(change.position), context), rummy)
                            change.consume()
                        }
                        finished = true
                        break
                    }
                    if (change.positionChanged()) model.touchMoved(point(change.position), context)
                    event.changes.forEach { it.consume() }
                }
            } finally {
                // 뗌 없이 끝났다(입력 층이 죽었다) — 끌던 타일을 공중에 남기지 않는다.
                if (!finished) model.touchVanished()
            }
        }
    }

/** 자동 밀기 — [GamesRummyMatchModel.isEdgePanning] 이 참인 동안만 프레임이 돈다. 끝에 닿거나 손이 비키면 멎는다. 끌기 기능이라 동작 줄이기여도 켠다. */
@Composable
private fun GamesRummyEdgePanner(model: GamesRummyMatchModel) {
    val edging = model.isEdgePanning
    LaunchedEffect(model, edging) {
        if (!edging) return@LaunchedEffect
        var last = -1L
        while (true) {
            val frame = withFrameNanos { it }
            if (last >= 0) model.edgeTick((frame - last) / 1_000_000_000.0)
            last = frame
        }
    }
}

/** 묶음째 집음 · 거절 햅틱과 거절 표시 0.6초. 값이 바뀔 때만 돈다 — 효과 안에서 열쇠(일련번호)를 쓰지 않는다. */
@Composable
private fun GamesRummyInputCues(model: GamesRummyMatchModel) {
    val haptics = LocalHapticFeedback.current
    val liftSerial = model.liftSerial
    val refuseSerial = model.refuseSerial
    LaunchedEffect(liftSerial) { if (liftSerial > 0) haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }
    LaunchedEffect(refuseSerial) {
        if (refuseSerial > 0) {
            haptics.performHapticFeedback(HapticFeedbackType.Reject)
            delay(GAMES_RUMMY_REFUSED_FLASH_MILLIS)
            model.clearRefusedFlash()
        }
    }
}

private const val GAMES_RUMMY_REFUSED_FLASH_MILLIS: Long = 600L

/** 내 차례 표시 값. */
private class GamesRummyTurnCue(val glow: GamesRummyTurnGlowPhase, val badgeShown: Boolean)

/**
 * 내 차례가 새로 왔으면 받침대 테두리를 한 번 크게 빛내고(0.8초 뒤 은은하게) 판 가운데 '내 차례' 배지를 1.3초 띄운다 · 햅틱 한 번. 동작 줄이기면 펄스 · 배지 없이 은은한 테두리만.
 * 소리 · 알림 없음(사용자 결정). 차례 정체성([key])이 열쇠라 같은 차례에 다시 안 울린다.
 * 놀던 기기에는 안 낸다(다른 기기에서 하는 판 — 차례마다 이 폰이 울리면 안 된다). 열쇠는 이미 지났으니 그 차례 중에 손대어 이어 받아도 배지가 뒤늦게 뜨지 않는다.
 */
@Composable
private fun rememberGamesRummyTurnCue(key: String?, reduceMotion: Boolean, engaged: () -> Boolean): GamesRummyTurnCue {
    val haptics = LocalHapticFeedback.current
    var glow by remember { mutableStateOf(GamesRummyTurnGlowPhase.steady) }
    var badge by remember { mutableStateOf(false) }
    LaunchedEffect(key) {
        badge = false
        glow = GamesRummyTurnGlowPhase.steady
        if (key == null || !engaged()) return@LaunchedEffect
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        if (reduceMotion) return@LaunchedEffect
        glow = GamesRummyTurnGlowPhase.pulse
        badge = true
        delay(800)
        glow = GamesRummyTurnGlowPhase.steady
        delay(500)
        badge = false
    }
    return GamesRummyTurnCue(glow, badge)
}

/** 날아오는 뽑기. 사건이 오면 정해진 시간 뒤 닫는다 — 효과는 사건 번호에만 묶이고 그 번호를 쓰지 않는다. 돌아왔을 때 옛 뽑기를 다시 날리지 않는다. */
@Composable
private fun rememberGamesRummyDrawFlight(rummy: RummyStore, reduceMotion: Boolean): GamesRummyRackFlight? {
    val event = rummy.lastDraw
    val serial = event?.serial
    var done by remember { mutableStateOf(serial) }
    LaunchedEffect(serial) {
        if (serial == null || serial == done) return@LaunchedEffect
        delay(GamesRummyRackMotion.flightMillis)
        done = serial
    }
    return GamesRummyRackMotion.flight(event, done, reduceMotion)
}

/** 정렬 시차 — 정렬 직전에 정하고 잠깐 뒤 비운다(안 비우면 끼워 넣기 미리보기까지 늦는다). */
@Stable
private class GamesRummySortMotion(private val rummy: RummyStore) {
    var stagger: Map<Int, Long> by mutableStateOf(emptyMap())
    var serial: Int by mutableStateOf(0)
    var reduceMotion: Boolean = false

    fun sort(mode: RummyRackSort) {
        val editor = rummy.editor
        stagger = if (!reduceMotion && editor != null) GamesRummyRackMotion.sortStagger(editor, mode) else emptyMap()
        serial += 1
        rummy.sortRack(mode)
    }
}

@Composable
private fun rememberGamesRummySortMotion(rummy: RummyStore, reduceMotion: Boolean): GamesRummySortMotion {
    val motion = remember(rummy) { GamesRummySortMotion(rummy) }
    motion.reduceMotion = reduceMotion
    LaunchedEffect(motion, motion.serial) {
        if (motion.serial == 0) return@LaunchedEffect
        delay(GamesRummyRackMotion.staggerClearMillis)
        motion.stagger = emptyMap()
    }
    return motion
}

/** 방금 뽑은 타일(3초 빛남). 돌아왔을 때 옛 뽑기를 다시 빛내지 않는다. */
@Composable
private fun rememberGamesRummyFreshDraw(rummy: RummyStore): Set<Int> {
    val event = rummy.lastDraw
    val seen = remember { event?.serial }
    var fresh by remember { mutableStateOf(emptySet<Int>()) }
    LaunchedEffect(event?.serial) {
        if (event == null || event.serial == seen) return@LaunchedEffect
        fresh = event.tiles.map { it.tileID }.toSet()
        delay(3_000)
        fresh = emptySet()
    }
    return fresh
}
