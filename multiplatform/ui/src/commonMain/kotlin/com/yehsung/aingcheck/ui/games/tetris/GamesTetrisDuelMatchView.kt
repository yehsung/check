// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelMatch.swift:326-973 @ 3bd04bd (대결 화면 · 잎 셋 · 조작 버튼)
//
// 준비 → 카운트다운 → 판 → 결과 한 화면. 로비가 `tetris.phase != lobby` 일 때 이 뷰를 그린다. 판정(표 · 손가락)은 core/stores
// `GamesTetrisDuelMatch.kt`(W2-e — GamesTetrisDuelChrome · GamesTetrisDuelTouch)이고 이 뷰는 배치만 한다.
// 탭 막대 숨김은 셸 몫(조립 — assembly.md: 판이 흐르는 동안 하단 탭 막대를 숨긴다. 판 시간이 단조 시계로 흘러 탭을 잘못 눌러 나가면 **안 보이는 채로
// 조각이 계속 떨어진다** — 판돈이 걸린 판이다).
package com.yehsung.aingcheck.ui.games.tetris

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisLayout
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelChrome
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelTone
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelTouch
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelMatchState
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelNoticeText
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelOpponentBoard
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisPhoneText
import com.yehsung.aingcheck.core.stores.tetris.countdownSeconds
import com.yehsung.aingcheck.core.stores.tetris.hardDrop
import com.yehsung.aingcheck.core.stores.tetris.hold
import com.yehsung.aingcheck.core.stores.tetris.matchElapsedSeconds
import com.yehsung.aingcheck.core.stores.tetris.moveLeftOneCell
import com.yehsung.aingcheck.core.stores.tetris.moveRightOneCell
import com.yehsung.aingcheck.core.stores.tetris.opponentSilenceSeconds
import com.yehsung.aingcheck.core.stores.tetris.releaseAllKeys
import com.yehsung.aingcheck.core.stores.tetris.rotate
import com.yehsung.aingcheck.core.stores.tetris.softDropOneCell
import com.yehsung.aingcheck.core.stores.tetris.tick
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterPortrait
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberPortraitArt
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.GamesCanvasColors
import com.yehsung.aingcheck.ui.games.minigame.GamesOverlayCard
import com.yehsung.aingcheck.ui.games.minigame.MiniGameFrameLoop
import com.yehsung.aingcheck.ui.games.minigame.TetrisControlButton
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.WatcherBadge
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 판 구동기가 아직 없을 때(시드를 받기 전) 그릴 빈 판 — 맥 창과 같은 자리표시다. */
private val placeholderGame: TetrisGame by lazy { TetrisGame(0uL) }

/** 캐릭터 초상(번들에 없는 캐릭터는 아잉으로 접는다 — 폰 CharacterPortrait 와 같은 접기). */
@Composable
internal fun GamesPortrait(characterID: String?, mood: CharacterMood, size: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) {
    val id = characterID?.takeIf { it in CharacterArt.portraitIds } ?: "aing"
    CharacterPortrait(rememberPortraitArt(id, mood.expression), mood, size, modifier)
}

/**
 * 대결 화면. 배치(위에서 아래로): 머리 띠(판돈 · 관전자 · 경과 · 가속 · 기권) → 상대 줄(미니 판 + 숫자) → **내 판** → 경고 줄 → 조작 셋 또는 결과 카드.
 *
 * INV-GamesTetrisDuelMatch-34a556a2 이식: 경고 줄(★ P7) → 조작 셋 또는 결과 카드. 판은 남은 세로를 **aspect-fit** 으로 먹으므로(아래 boardBox 의
 *   weight + aspectRatio) 작은 화면에서도 조작 줄·경고 줄은 **언제나 화면 안**이다(체스가 데인 자리: 큰 글자에서 아래 버튼이 잘렸다).
 */
@Composable
fun GamesTetrisDuelMatchView(
    store: GamesStore,
    refreshHz: Int,
    appActive: Boolean,
    reduceMotion: Boolean,
    meName: String?,
    modifier: Modifier = Modifier,
) {
    val tetris = store.tetris
    val match = tetris.match ?: return
    val chrome = GamesTetrisDuelChrome(match, tetris.phase, tetris.myStats, tetris.notice, tetris.connectionTrouble, playingElsewhere = tetris.playingElsewhere)
    /** 판 위 한 손가락 — 터치마다 다시 그려지지 않게 상태가 아닌 참조로 든다. */
    val touch = remember { GamesTetrisDuelTouch() }
    var confirmsResign by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    // 화면을 떠나면 눌린 것을 놓고 손가락 상태를 비운다. **기권이 아니다** — 판은 서버에서 계속 흐른다(수명은 로비의 tetrisScreenDidDisappear 가 쥔다).
    DisposableEffect(tetris) {
        onDispose {
            touch.reset()
            tetris.releaseAllKeys()
        }
    }
    // 앱이 뒤로: 판은 멎지만(그래서 경고 줄이 있다) 눌린 것은 놓는다 — 돌아왔을 때 유령 입력이 남지 않게.
    LaunchedEffect(appActive) {
        if (!appActive) {
            touch.reset()
            tetris.releaseAllKeys()
        }
    }
    LaunchedEffect(match.id) {
        confirmsResign = false
        touch.reset()
    }
    val colors = AingTheme.colors
    Column(
        modifier.fillMaxSize().background(colors.background).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space2),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        TopStrip(tetris, chrome) { confirmsResign = true }
        OpponentRow(tetris, match, chrome)
        BoardBox(tetris, chrome, touch, refreshHz, reduceMotion, Modifier.weight(1f).fillMaxWidth())
        if (chrome.showsLeaveWarning) WarningRow(chrome, meName)
        chrome.notice?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.fillMaxWidth()) }
        val result = chrome.result
        if (result != null) ResultCard(result) { tetris.backToLobby() } else Controls(tetris, chrome)
    }
    // 확인은 **불투명 대화상자**로 — 기권만 확인을 받는다(판돈을 잃는다). 조작 버튼에는 확인을 넣지 않는다(계약 ⑥).
    if (confirmsResign) {
        AlertDialog(
            onDismissRequest = { confirmsResign = false },
            title = { Text(TetrisPhoneText.resignConfirmTitle) },
            text = { Text(TetrisPhoneText.resignWarning) },
            confirmButton = {
                TextButton(onClick = {
                    confirmsResign = false
                    scope.launch { tetris.resign() }
                }) { Text(TetrisPhoneText.confirmResign, color = colors.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmsResign = false }) { Text(TetrisPhoneText.keepPlaying) } },
            containerColor = colors.surface,
        )
    }
}

// MARK: 머리 띠

/** 판돈 · 관전자 수 · 경과(잎) · 가속 칩 · [기권]. 좁은 화면에서 가속 칩이 **짧은 꼴로 접힌다**(보이스오버는 접히기 전 문장을 읽는다). */
@Composable
private fun TopStrip(tetris: TetrisDuelStore, chrome: GamesTetrisDuelChrome, onResign: () -> Unit) {
    val colors = AingTheme.colors
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val narrow = maxWidth < 360.dp
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            StripChip(colors.label, Modifier.semantics(mergeDescendants = true) { contentDescription = "${TetrisPhoneText.stakeTitle} ${chrome.stakeLine}" }) {
                RubyIcon(rememberRubyArt(13f), size = 13.dp)
                Text(chrome.stakeLine, style = stripText(), color = colors.label, maxLines = 1)
            }
            // 내 판을 보고 있는 사람 수(0.3.65 — 대국자 본인 화면: 판돈 칩 줄에 같이). 0 이면 서지 않는다.
            WatcherBadge(tetris.spectatorCount, style = stripText())
            ElapsedLeaf(tetris, chrome.stage)
            if (chrome.showsSpeedUp) {
                val full = TetrisPhoneText.speedUp + " · " + TetrisPhoneText.speedLevel(chrome.speedLevel)
                StripChip(colors.pending, Modifier.semantics(mergeDescendants = true) { contentDescription = TetrisPhoneText.speedUp + " " + TetrisPhoneText.speedLevel(chrome.speedLevel) }) {
                    AingIcon(AppIcon.CrueltyFreeFill, contentDescription = null, size = 14.dp, tint = colors.pending)
                    Text(if (narrow) TetrisPhoneText.speedLevel(chrome.speedLevel) else full, style = stripText(), color = colors.pending, maxLines = 1)
                }
            }
            Spacer(Modifier.weight(1f))
            if (chrome.canResign) {
                // INV-GamesTetrisDuelMatch-ed2ded05 이식: **줄이 깨지지 않는다** — [기권]은 무게(weight)를 받지 않고 제 폭을 지킨다(가운데 Spacer 가 먼저 줄고,
                //   그다음 가속 칩이 짧은 꼴로 접힌다). 안 걸면 작은 화면에서 칩이 넷일 때 이 버튼부터 좁혀져 "기 / 권" 두 줄로 쪼개진다.
                PillButton(TetrisPhoneText.resign, kind = PillKind.Destructive, size = PillSize.Sm, icon = AppIcon.Flag, onClick = onResign)
            }
        }
    }
}

@Composable
private fun stripText() = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM)

@Composable
private fun StripChip(tint: Color, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Row(
        modifier.heightIn(min = 28.dp).background(AingTheme.colors.fill, CircleShape).padding(horizontal = AingDimens.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) { content() }
}

/** 경과 시계(잎 — 시간을 읽는 **유일한** 자리 셋 중 하나). 화면이 안 보이거나 판이 아니면 멈춘다. */
@Composable
private fun ElapsedLeaf(tetris: TetrisDuelStore, stage: GamesTetrisDuelChrome.Stage) {
    val colors = AingTheme.colors
    val live = tetris.isWindowVisible && stage == GamesTetrisDuelChrome.Stage.playing
    var elapsed by remember { mutableStateOf(GamesTetrisDuelChrome.elapsedSeconds(stage, tetris.matchElapsedSeconds(), tetris.duel?.simulated)) }
    LaunchedEffect(live, stage) {
        elapsed = GamesTetrisDuelChrome.elapsedSeconds(stage, tetris.matchElapsedSeconds(), tetris.duel?.simulated)
        while (live) {
            delay(500)
            elapsed = GamesTetrisDuelChrome.elapsedSeconds(stage, tetris.matchElapsedSeconds(), tetris.duel?.simulated)
        }
    }
    StripChip(colors.label, Modifier.semantics(mergeDescendants = true) { contentDescription = "${TetrisPhoneText.elapsedTitle} ${TetrisPhoneText.clock(elapsed)}" }) {
        AingIcon(AppIcon.Timer, contentDescription = null, size = 14.dp, tint = colors.label)
        Text(TetrisPhoneText.clock(elapsed), style = stripText().copy(fontWeight = FontWeight.Bold), color = colors.label)
    }
}

// MARK: 상대 줄 (미니 판은 위쪽 상대 줄 안 — P11: 내 판 옆에 세우면 캔버스가 좁아져 제스처 한 칸 문턱이 바뀐다)

@Composable
private fun OpponentRow(tetris: TetrisDuelStore, match: TetrisDuelMatchState, chrome: GamesTetrisDuelChrome) {
    val colors = AingTheme.colors
    val (_, miniHeight) = TetrisMiniBoardLayout.boardSize(GamesTetrisDuelChrome.miniBoardCell)
    Row(Modifier.fillMaxWidth().heightIn(min = miniHeight.dp), horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
        Box(contentAlignment = Alignment.Center) {
            GamesTetrisDuelMiniBoard(match.opponentBoard.cells)
            if (chrome.opponentToppedOut) ToppedOutBadge()
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AingDimens.space1)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                GamesPortrait(match.opponent.characterID, if (match.opponent.isWorking) CharacterMood.Working else CharacterMood.Off, 26.dp)
                Text(chrome.opponentName, style = rowTitleStyle(), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            PresenceLeaf(tetris, match.opponentBoard, chrome.stage)
            Spacer(Modifier.weight(1f, fill = false))
            Stat(TetrisPhoneText.linesTitle, chrome.opponentLines, colors.label)
            Stat(TetrisPhoneText.attackTitle, chrome.opponentAttack, colors.working)
            Stat(TetrisPhoneText.incomingLinesTitle, chrome.opponentPending, if (chrome.opponentPending > 0) colors.danger else colors.label2)
        }
    }
}

@Composable
internal fun ToppedOutBadge() {
    Text(
        TetrisPhoneText.toppedOutTitle,
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
        color = AingTheme.colors.danger,
        modifier = Modifier.background(Color.Black.copy(alpha = 0.7f), CircleShape).padding(horizontal = 4.dp, vertical = 2.dp),
        maxLines = 1,
    )
}

/** 숫자 한 줄(제목 왼쪽 · 값 오른쪽). */
@Composable
internal fun Stat(title: String, value: Int, tint: Color) {
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { }, verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = AingTheme.colors.label2)
        Spacer(Modifier.weight(1f))
        Text(value.toString(), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TNUM), color = tint)
    }
}

/** 상대 상태 한 줄 — 준비 · 대결 중 · 대결 끝 · 꼭대기 · **상대 연결 확인 중**(침묵 초를 읽는 자리가 여기뿐이다). */
@Composable
private fun PresenceLeaf(tetris: TetrisDuelStore, board: TetrisDuelOpponentBoard, stage: GamesTetrisDuelChrome.Stage) {
    val colors = AingTheme.colors
    var silent by remember { mutableStateOf(false) }
    val live = tetris.isWindowVisible && stage != GamesTetrisDuelChrome.Stage.finished
    LaunchedEffect(live, board.ready, stage) {
        while (true) {
            silent = GamesTetrisDuelChrome.opponentIsSilent(tetris.opponentSilenceSeconds(), board.ready, stage)
            if (!live) break
            delay(1000)
        }
    }
    Text(
        if (silent) TetrisPhoneText.opponentSilent else GamesTetrisDuelChrome.opponentStatus(board, stage),
        style = MaterialTheme.typography.labelSmall, color = if (silent) colors.pending else colors.label2, maxLines = 1,
    )
}

// MARK: 내 판

/**
 * 판 상자 — 남은 세로를 **aspect-fit** 으로 먹는다(292:302). 한 칸 문턱은 그려진 배율에서 그때 다시 센다(한 출처).
 *
 * INV-GamesTetrisDuelMatch-b4e92b88 이식: 판을 읽는 **유일한** 자리(계약 ①). 프레임마다 tetris.tick() 을 불러 판을 지금까지 미는데, 판 루프가
 *   0.05초마다 같은 일을 하므로 이 틱이 없어도 판은 흐른다(화면이 숨으면 이쪽이 멈춘다 — 계약 ②).
 * INV-GamesTetrisDuelMatch-2338c933 이식: 손가락 입력은 **이 자리 하나**에 걸고, '입력을 받는가' 갈래는 핸들러 **안**에 둔다 — 수정자 자체를 갈라
 *   붙이면 노드가 갈려 진행 중인 끌기가 통째로 끊긴다(키는 스토어 하나다).
 */
@Composable
private fun BoardBox(
    tetris: TetrisDuelStore,
    chrome: GamesTetrisDuelChrome,
    touch: GamesTetrisDuelTouch,
    refreshHz: Int,
    reduceMotion: Boolean,
    modifier: Modifier,
) {
    val density = LocalDensity.current.density
    var frame by remember { mutableIntStateOf(0) }
    val live = tetris.isWindowVisible && (chrome.stage == GamesTetrisDuelChrome.Stage.countdown || chrome.stage == GamesTetrisDuelChrome.Stage.playing)
    MiniGameFrameLoop(running = live, refreshHz = refreshHz) {
        tetris.tick()
        frame += 1
    }
    val accepts by androidx.compose.runtime.rememberUpdatedState(chrome.acceptsInput)
    Box(modifier, contentAlignment = Alignment.Center) {
        BoxWithConstraints(
            Modifier.aspectRatio((TetrisLayout.logicalSize.width / TetrisLayout.logicalSize.height).toFloat(), matchHeightConstraintsFirst = true)
                .wrapContentSize()
                .clip(RoundedCornerShape(14.dp))
                .background(GamesCanvasColors.panel)
                .testTag(TetrisDuelTags.BOARD)
                .pointerInput(tetris) {
                    fun pt(px: Float): Double = px / density.toDouble()
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        // 솔로와 달리 **시작 래치가 없다**(대결 판은 서버가 켠다) — 탭은 회전뿐이다.
                        val start = MiniGamePoint(pt(down.position.x), pt(down.position.y))
                        fun date(ms: Long) = SwiftDate.fromReferenceDate(ms / 1000.0)
                        if (accepts) touch.changed(start, MiniGameSize(0.0, 0.0), date(down.uptimeMillis), tetris)
                        var translation = MiniGameSize(0.0, 0.0)
                        var lastMs = down.uptimeMillis
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            translation = MiniGameSize(pt(change.position.x) - start.x, pt(change.position.y) - start.y)
                            lastMs = change.uptimeMillis
                            if (!change.pressed) break
                            change.consume()
                            if (accepts) touch.changed(start, translation, date(lastMs), tetris)
                        }
                        if (accepts) touch.ended(translation, date(lastMs), tetris) else touch.reset()
                    }
                }
                .semantics {
                    contentDescription = GamesTetrisDuelChrome.boardAccessibility(tetris.myStats?.lines ?: 0, tetris.myStats?.pendingGarbage ?: 0)
                    role = Role.Button
                    // 기본 동작은 **시계 회전**(탭과 같다). 판 어디든 겨냥하라는 뜻이 아니므로 직접 조작은 걸지 않는다.
                    onClick { if (accepts) tetris.rotate(clockwise = true); true }
                    if (accepts) {
                        customActions = listOf(
                            CustomAccessibilityAction(GamesMiniGameText.tetrisMoveLeft) { tetris.moveLeftOneCell(); true },
                            CustomAccessibilityAction(GamesMiniGameText.tetrisMoveRight) { tetris.moveRightOneCell(); true },
                            CustomAccessibilityAction(GamesMiniGameText.tetrisSoftDrop) { tetris.softDropOneCell(); true },
                        )
                    }
                },
        ) {
            // 한 칸 문턱 = 논리 셀 13 × 그려진 배율(dp).
            val scale = minOf(maxWidth.value / TetrisLayout.logicalSize.width.toFloat(), maxHeight.value / TetrisLayout.logicalSize.height.toFloat())
            LaunchedEffect(scale) { touch.updateCellWidth(TetrisLayout.cell * scale) }
            @Suppress("UNUSED_EXPRESSION") frame
            val game = tetris.duel?.game ?: placeholderGame
            GamesTetrisDuelCanvas(game, reduceMotion, Modifier.fillMaxSize(), frame)
            if (chrome.showsBoardOverlay) BoardOverlay(tetris, chrome, frame)
        }
    }
}

/** 판 위 덮개 — 준비(남은 초 잎) · 카운트다운(3·2·1) · 탑아웃 · 결과(어둡게만). */
@Composable
private fun BoardOverlay(tetris: TetrisDuelStore, chrome: GamesTetrisDuelChrome, frame: Int) {
    val colors = AingTheme.colors
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        when (chrome.stage) {
            // 같은 계정의 다른 기기가 두는 판(Swift 75c31cd2 `case .waiting where chrome.playingElsewhere`) — 이 폰에는 판이 없다(코어가
            // 구동기를 안 만든다). 기다리라는 말 대신 사실을 말한다(색은 카드 기본 accent — iOS 와 같은 자리). 기다림 잎보다 **먼저** 고른다.
            // 기호: iOS 는 `macbook.and.iphone` — 이 워크트리의 Swift 원문(SfSymbolCoverageTest 의 기준)에는 아직 없어 대응표에 있는
            // `desktopcomputer` 로 둔다(main 병합 때 대응표에 넣고 바꾼다).
            GamesTetrisDuelChrome.Stage.waiting -> if (chrome.playingElsewhere) {
                GamesOverlayCard(
                    TetrisDuelNoticeText.otherDevice, TetrisPhoneText.otherDeviceSubtitle, TetrisPhoneText.otherDeviceAction,
                    icon = "desktopcomputer", scale = 0.9f,
                )
            } else WaitLeaf(tetris) { seconds ->
                GamesOverlayCard(
                    TetrisPhoneText.waitingTitle, TetrisPhoneText.waitingSubtitle(seconds), TetrisPhoneText.waitingAction,
                    icon = "hourglass", tint = colors.pending, scale = 0.9f,
                )
            }
            GamesTetrisDuelChrome.Stage.countdown -> {
                @Suppress("UNUSED_EXPRESSION") frame
                val digit = GamesTetrisDuelChrome.countdownDigit(tetris.countdownSeconds())
                Column(
                    Modifier.clearAndSetSemantics { contentDescription = "${TetrisPhoneText.startingSoon} $digit" },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(digit.toString(), style = MaterialTheme.typography.displayLarge.copy(fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TNUM), color = GamesCanvasColors.primaryText)
                    Text(TetrisPhoneText.startingSoon, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = GamesCanvasColors.secondaryText)
                }
            }
            // 탑아웃 — 내 판은 끝났고 서버 응답을 기다리는 중이다(입력도 이때 끊긴다).
            GamesTetrisDuelChrome.Stage.playing -> GamesOverlayCard(
                TetrisPhoneText.toppedOutTitle, TetrisPhoneText.toppedOutSubtitle, TetrisPhoneText.playingNow,
                icon = "exclamationmark.triangle.fill", tint = colors.danger, scale = 0.9f,
            )
            // 결과는 **아래 카드**가 말한다(판은 그대로 보인다 — 마지막 판이 눈에 남아야 한다). 여기는 판을 어둡게만 덮는다.
            GamesTetrisDuelChrome.Stage.finished -> Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)))
        }
    }
}

/** 준비 마감까지 남은 초를 1초마다 센다(덮개 카드 한 장만 다시 그린다). */
@Composable
private fun WaitLeaf(tetris: TetrisDuelStore, content: @Composable (Int) -> Unit) {
    var seconds by remember { mutableIntStateOf(GamesTetrisDuelChrome.readySecondsLeft(tetris.match?.readyDeadline, tetris.clock())) }
    LaunchedEffect(tetris.isWindowVisible) {
        while (true) {
            seconds = GamesTetrisDuelChrome.readySecondsLeft(tetris.match?.readyDeadline, tetris.clock())
            if (!tetris.isWindowVisible) break
            delay(1000)
        }
    }
    content(seconds)
}

// MARK: 경고 줄 (★ P7 — 판 위에 늘 있다)

/** 내 이름 + ★ "판 중에 앱을 나가면 져요" + 연결 확인 중. 경고가 **먼저** 자리를 가진다(이름은 줄어든다). */
@Composable
private fun WarningRow(chrome: GamesTetrisDuelChrome, meName: String?) {
    // INV-GamesTetrisDuelMatch-c3f95f39 이식: 경고 줄은 판 위에 **늘** 있다(끝난 판에서만 내린다 — chrome.showsLeaveWarning). 폰은 앱을 나가면 판이 멎어
    //   15초 침묵으로 진다 — 화면이 그 사실을 말하는 것이 유일한 방어다.
    // INV-GamesTetrisDuelMatch-c9f35847 이식: 경고가 **먼저** 자리를 가진다 — 이름은 남는 폭만 받고(weight + 줄임표) 경고 글자는 줄지 않는다.
    val colors = AingTheme.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        Text(
            meName?.let { it + " · " + TetrisPhoneText.me } ?: TetrisPhoneText.me,
            style = MaterialTheme.typography.labelSmall, color = colors.label2, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f, fill = false),
        )
        Spacer(Modifier.weight(0.01f))
        if (chrome.connectionTrouble) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                AingIcon(AppIcon.SignalWifiBad, contentDescription = null, size = 12.dp, tint = colors.danger)
                Text(TetrisPhoneText.connectionTrouble, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = colors.danger, maxLines = 1)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            AingIcon(AppIcon.WarningFill, contentDescription = null, size = 13.dp, tint = colors.pending)
            Text(TetrisPhoneText.leaveWarning, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.pending)
        }
    }
}

// MARK: 조작 셋 · 결과 카드

/**
 * [홀드][반대로][바로 내리기] — 솔로와 **같은 셋**이고 쓸 폭을 26 : 30 : 44 로 나눈다. 확인 대화상자는 없다(계약 ⑥). 판이 살아 있지 않으면 눌려도
 * 아무 일이 없다(화면 가드 + 코어 isLive).
 * INV-GamesTetrisDuelMatch-f8806f2c 이식: Swift 는 솔로 버튼이 그 파일의 private 이라 같은 계약을 한 벌 더 적었다. Kotlin 은 **솔로 버튼 그 한 벌**
 *   (minigame TetrisControlButton — 터치-다운 둘 · 터치-업 하나 · 눌림은 색만 · 접촉 id 래치)을 그대로 쓴다 — 두 벌이 갈릴 자리가 없다.
 */
@Composable
private fun Controls(tetris: TetrisDuelStore, chrome: GamesTetrisDuelChrome) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val usable = (maxWidth - AingDimens.space2 - AingDimens.space4).coerceAtLeast(0.dp)
        Row {
            TetrisControlButton(
                TetrisPhoneText.holdButton, AppIcon.FilterNone, usable * 0.26f, firesOnTouchDown = true, tag = "tetris.duel.hold",
                isSpent = tetris.duel?.game?.holdUsed ?: false, spentValue = TetrisPhoneText.holdSpent,
            ) { if (chrome.acceptsInput) tetris.hold() }
            Spacer(Modifier.width(AingDimens.space2))
            TetrisControlButton(TetrisPhoneText.rotateCounterButton, AppIcon.RotateLeft, usable * 0.30f, firesOnTouchDown = true, tag = "tetris.duel.rotate") {
                if (chrome.acceptsInput) tetris.rotate(clockwise = false)
            }
            Spacer(Modifier.width(AingDimens.space4))
            TetrisControlButton(TetrisPhoneText.hardDropButton, AppIcon.VerticalAlignBottom, usable * 0.44f, firesOnTouchDown = false, tag = "tetris.duel.hardDrop") {
                if (chrome.acceptsInput) tetris.hardDrop()
            }
        }
    }
}

/** 승/패/무 · 사유 · 루비 증감 · [로비로]. 판은 **그대로 위에 남는다**(마지막 판이 보인다). */
@Composable
private fun ResultCard(result: GamesTetrisDuelChrome.Result, onLobby: () -> Unit) {
    val colors = AingTheme.colors
    val tint = when (result.tone) {
        GamesTetrisDuelTone.good -> colors.working
        GamesTetrisDuelTone.bad -> colors.danger
        GamesTetrisDuelTone.warn -> colors.pending
        GamesTetrisDuelTone.quiet -> colors.label2
    }
    val icon = when (result.tone) {
        GamesTetrisDuelTone.good -> AppIcon.TrophyFill
        GamesTetrisDuelTone.bad -> AppIcon.CancelFill
        GamesTetrisDuelTone.warn -> AppIcon.HourglassEmpty
        GamesTetrisDuelTone.quiet -> AppIcon.Equal
    }
    InsetGroup {
        Column(Modifier.padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                AingIcon(icon, contentDescription = null, size = 22.dp, tint = tint)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(result.title, style = MaterialTheme.typography.titleLarge, color = tint)
                    if (result.reason.isNotEmpty()) Text(result.reason, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                }
                Row(
                    Modifier.semantics(mergeDescendants = true) { contentDescription = "루비 ${result.rubyDeltaText}" },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    RubyIcon(rememberRubyArt(20f), size = 20.dp, modifier = Modifier.alpha(if (result.rubyDelta < 0) 0.5f else 1f))
                    Text(
                        result.rubyDeltaText,
                        style = MaterialTheme.typography.titleLarge.copy(fontFeatureSettings = TNUM),
                        color = if (result.rubyDelta > 0) colors.working else if (result.rubyDelta < 0) colors.danger else colors.label,
                    )
                }
            }
            PillButton(TetrisPhoneText.backToLobby, kind = PillKind.Gray, fillsWidth = true, onClick = onLobby)
        }
    }
}
