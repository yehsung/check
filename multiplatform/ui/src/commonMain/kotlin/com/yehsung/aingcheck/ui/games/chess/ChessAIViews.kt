// 원본: Sources/CheckMobileKit/Games/GamesChessAIViews.swift @ 3bd04bd
//
// 폰 "로봇과 두기"(체스 AI) — **비로그인 사용자의 유일한 체스 길**이다(색 고르기(백/흑) → 바로 시작. 판돈 없음, 순위에 안 들어감).
//  ① [ChessRobotEntry] — 로비 안 입구.  ② [ChessRobotScreen] — 색 고르기 → 판 → 결과(화면 안 덮개 — iOS fullScreenCover 자리, 체스 화면은 그대로 남는다).
// 규칙·판·시계·AI 는 전부 코어(`ChessStoreAI`)이고, 이 파일은 코어가 세운 값을 옮기기만 한다. 문구는 전부 `ChessPhoneText`.
//
// INV-GamesChessAIViews-06502fa3 이식: **로그인을 보지 않는다** — `ChessStoreAI` 는 서버를 한 번도 안 탄다. 입구·화면 어디에도 세션 조건이 없다(숨기면 그 길이 막힌다).
// INV-GamesChessAIViews-4ed609af 이식: **판 방향은 한 값만 지난다** — [ChessRobotBoardInput.whiteAtBottom] 한 줄에서 나와 [ChessBoard] 로 넘어간다. 이 파일에 화면 좌표를
//   계산하는 자리가 없다(흑으로 두는 사람만 틀어지는 꼴을 막는다).
// INV-GamesChessAIViews-88a27613 이식: **합법 수는 스토어가 쥔 한 칸만 읽는다**(`selection.targets` — 로봇 판은 로컬 규칙, 1:1 은 서버. 화면은 어느 쪽인지 모른다).
//   이 파일은 `ChessRules` 를 부르지 않는다.
// INV-GamesChessAIViews-5a631bc4 이식: **승격은 2단** — 코어 `promotion` 이 섰을 때만 시트를 띄우고, 닫는 길은 시트의 `cancelPromotion()` 하나다(ChessSheets.kt).
// INV-GamesChessAIViews-b3533fc5 이식: **결과 문구는 로봇 판 표**(`robotEndReason`)를 쓴다 — 1인칭 표는 루비·"상대"를 말해 없는 루비 변화를 말하게 된다.
// INV-GamesChessAIViews-42bea0cc 이식: **애니메이션은 판 주인이 붙인다** — 로봇 수는 서버를 안 타 즉시 미끄러진다. 화면은 같은 [ChessFlightTracker] 로 값을 판에
//   넘기기만 한다(스토어를 건드리지 않는다).
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.stores.chess.ChessEndReason
import com.yehsung.aingcheck.core.stores.chess.ChessMatchOutcome
import com.yehsung.aingcheck.core.stores.chess.ChessMatchState
import com.yehsung.aingcheck.core.stores.chess.ChessPhase
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessPromotionPrompt
import com.yehsung.aingcheck.core.stores.chess.ChessSelection
import com.yehsung.aingcheck.core.stores.chess.ChessServerClock
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.chess.GamesChessCheckMark
import com.yehsung.aingcheck.core.stores.chess.canStartAIMatch
import com.yehsung.aingcheck.core.stores.chess.isAIMatch
import com.yehsung.aingcheck.core.stores.chess.isAIThinking
import com.yehsung.aingcheck.core.stores.chess.restartAIMatch
import com.yehsung.aingcheck.core.stores.chess.startAIMatch
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BarIcon
import com.yehsung.aingcheck.ui.games.gomoku.BoardButton
import com.yehsung.aingcheck.ui.games.gomoku.BoardButtonKind
import com.yehsung.aingcheck.ui.games.gomoku.BoardGroup
import com.yehsung.aingcheck.ui.games.gomoku.BoardNotice
import com.yehsung.aingcheck.ui.games.gomoku.BoardPortrait
import com.yehsung.aingcheck.ui.games.gomoku.BoardRow
import com.yehsung.aingcheck.ui.games.gomoku.BoardText
import com.yehsung.aingcheck.ui.games.gomoku.rememberTicker
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 판 한 번을 그리는 값 묶음 — **판 인자가 여기서 한 번 만들어진다**. 판을 읽을 수 없으면(FEN 결함) null. */
data class ChessRobotBoardInput(
    val position: ChessPosition,
    /** INV-GamesChessAIViews-44168c41 이식: 이 레인에서 **판 방향을 아는 유일한 값** — 내 색이 아래다(흑을 고르면 false). */
    val whiteAtBottom: Boolean,
    val selection: ChessSquare?,
    val legalTargets: Set<ChessSquare>,
    val lastMove: ChessMove?,
    val isMyTurn: Boolean,
    val checkSquare: ChessSquare?,
) {
    companion object {
        fun of(match: ChessMatchState, selection: ChessSelection?): ChessRobotBoardInput? {
            val position = match.position ?: return null
            return ChessRobotBoardInput(
                position = position, whiteAtBottom = match.myColor == ChessColor.white,
                selection = selection?.from, legalTargets = selection?.targets ?: emptySet(), lastMove = match.lastMove, isMyTurn = match.isMyTurn,
                checkSquare = GamesChessCheckMark.square(match.isInCheck, match.isFinished, match.turn, position),
            )
        }
    }
}

/** 로봇 판 입구·화면이 읽는 **유일한 판정 표**(오목 `GomokuPhoneMatchChrome` 와 같은 자리). */
data class ChessRobotChrome(
    val stage: Stage,
    val canStart: Boolean,
    val blockReason: String?,
    val blocked: ChessPhoneText.RobotBlock?,
    val board: ChessRobotBoardInput?,
    val humanColor: ChessColor?,
    val opponent: ChessUser?,
    val promotion: ChessPromotionPrompt?,
    val isRobotThinking: Boolean,
    val isInCheck: Boolean,
    val plyCount: Int,
    /** INV-GamesChessAIViews-a0bfb663 이식: 둘 차례인 쪽(끝난 판은 null) — **시계의 `running` 이 아니다**(로봇 판 로컬 시계는 화면이 안 보이면 멈춰 `running` 이 사라진다). */
    val turn: ChessColor?,
    val clock: ChessServerClock?,
    val outcome: ChessMatchOutcome?,
    val endReason: ChessEndReason?,
    val canResign: Boolean,
    val canRestart: Boolean,
    val notice: String?,
    val matchStake: Long?,
) {
    enum class Stage { colorPick, playing, result }

    /** 판 아래 한 줄 — 로봇 차례면 "로봇이 생각 중이에요", 아니면 상태 한 줄(체크 포함). */
    val statusLine: String get() = if (isRobotThinking) ChessPhoneText.robotThinking else ChessPhoneText.statusLine(board?.isMyTurn == true, isInCheck)

    /** 결과 이유 — **로봇 판 표**. */
    val endReasonLine: String get() = ChessPhoneText.robotEndReason(endReason, outcome)

    companion object {
        /**
         * INV-GamesChessAIViews-e7a70429 이식: **로봇 판은 로그인을 보지 않는다** — 기본값도 값으로 잰다(시험 ChessRobotChromeTest 가 세션 없는 스토어로 입구·판·수를 되묻는다).
         */
        const val REQUIRES_SIGN_IN: Boolean = false
        /** 판돈 없음 — 걸린 루비가 0 이고 신청·정산 왕복이 아예 없다. */
        const val STAKE: Long = 0
        /** 순위에 안 들어간다 — 로봇 판은 서버에 없다. */
        const val ENTERS_RANKING: Boolean = false

        fun of(store: ChessStore): ChessRobotChrome {
            // 로봇 판만 본다(1:1 판이 열려 있으면 그 판은 이 화면의 것이 아니다 — 코어가 로봇 판을 이미 버렸다).
            val match = if (store.isAIMatch) store.match else null
            val blocked = blockReason(store)
            return ChessRobotChrome(
                stage = when {
                    match == null -> Stage.colorPick
                    match.isFinished -> Stage.result
                    else -> Stage.playing
                },
                canStart = store.canStartAIMatch,
                // INV-GamesChessAIViews-c5f93688 이식: 로그인은 사유가 **아니다**(최악의 값으로 되물어도 null — 판·보낸 신청·오가는 요청만 막는다).
                blockReason = blocked?.let(ChessPhoneText::robotEntryBlockNotice),
                blocked = blocked,
                board = match?.let { ChessRobotBoardInput.of(it, store.selection) },
                humanColor = match?.myColor,
                opponent = match?.opponent,
                promotion = if (match != null) store.promotion else null,
                isRobotThinking = match != null && store.isAIThinking,
                isInCheck = match?.isInCheck ?: false,
                plyCount = match?.plyCount ?: 0,
                turn = match?.turn,
                clock = match?.clock,
                outcome = match?.outcome,
                endReason = match?.endReason,
                canResign = match != null && !match.isFinished,
                canRestart = match?.isFinished == true,
                notice = store.notice,
                matchStake = match?.stake,
            )
        }

        /**
         * 입구가 막힌 **까닭 하나**(열려 있으면 null).
         * INV-GamesChessAIViews-edd44be4 이식: 게이트를 **다시 세지 않는다** — 열렸는지는 코어 `canStartAIMatch` 하나가 답하고(베끼면 클라 게이트가 짝으로 갈린다),
         *   이 함수는 닫혔을 때 **무엇을 말할지**만 고른다.
         * INV-GamesChessAIViews-884be21e 이식: 서열 — 판 > 보낸 신청 > 오가는 요청. 보낸 신청은 취소로 당장 풀 수 있는 막힘이라 다른 말을 들어야 한다.
         * INV-GamesChessAIViews-7963ac6f 이식: **까닭으로 갈린다** — 보낸 신청만 있는 사람에게 "체스를 두는 중이에요"라고 말하면 두고 있지 않은 판을 두고 있다고 듣는다.
         */
        fun blockReason(store: ChessStore): ChessPhoneText.RobotBlock? {
            if (store.canStartAIMatch) return null
            if (store.match != null || store.activeMatchID != null || store.phase != ChessPhase.lobby) return ChessPhoneText.RobotBlock.playing
            if (store.outgoing != null) return ChessPhoneText.RobotBlock.outgoingInvite
            return ChessPhoneText.RobotBlock.busy
        }
    }
}

/**
 * 로비 안 [로봇과 두기] 입구(로비에만 — 대국 중에 새 판을 열 길을 두지 않는다).
 * INV-GamesChessAIViews-2d341bf4 이식: **로그인을 보지 않는다** — 비활성은 코어 `canStartAIMatch` 하나로만 갈린다(1:1 판·보낸 신청이 떠 있을 때). 로봇 판이 이미
 *   있으면 입구는 그 판을 다시 연다(색 고르기를 건너뛴다 — 화면이 단계를 고른다).
 */
@Composable
internal fun ChessRobotEntry(chess: ChessStore, onOpen: () -> Unit) {
    val colors = AingTheme.colors
    val chrome = ChessRobotChrome.of(chess)
    val opens = chrome.canStart || chess.isAIMatch
    BoardGroup(Modifier.testTag(ChessScreenTags.robotEntry).let { if (opens) it.clickable(onClick = onOpen) else it }.semantics(mergeDescendants = true) {}) {
        BoardRow(minHeight = AingDimens.rowHeightTwoLine) {
            BoardPortrait(ChessUser.chessAI.characterID, CharacterMood.Plain, 36.dp, stoneIsBlack = null, modifier = Modifier.alpha(if (opens) 1f else 0.5f))
            Column(Modifier.weight(1f)) {
                Text(ChessPhoneText.robotButton, style = BoardText.rowTitle(), color = if (opens) colors.label else colors.label2)
                Text(chrome.blockReason ?: ChessPhoneText.robotButtonHelp, style = BoardText.rowSubtitle(), color = colors.label2)
            }
            if (opens) AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 18.dp, tint = colors.label3)
        }
    }
}

/** 로봇과 두는 한 판(덮개). 색을 고르면 **바로 시작**(걸 것이 없어 확인 단계가 없다). 판돈 줄·순위·기보·무승부 제안·대화는 없다. */
@Composable
internal fun BoxScope.ChessRobotScreen(chess: ChessStore, state: ChessScreenState, onClose: () -> Unit) {
    val colors = AingTheme.colors
    val chrome = ChessRobotChrome.of(chess)
    // INV-GamesChessAIViews-9c961f34 이식: 창 가시성(`isWindowVisible`)을 **여기서 켜지 않는다** — 체스 화면 수명 훅(게임 탭 스토어)의 것이다. 이 덮개는 체스 화면 안이라
    //   그 깃발이 그대로 켜져 있고, 로봇 수 애니메이션·로컬 시계가 같은 깃발을 본다.
    Column(Modifier.matchParentSize().background(colors.background).testTag(ChessScreenTags.robotScreen)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            BarIcon(AppIcon.Close, ChessPhoneText.close, "chess-robot-close", onClick = onClose)
            Text(ChessPhoneText.robotButton, style = BoardText.headline(), color = colors.label, modifier = Modifier.weight(1f).semantics { heading() },
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            androidx.compose.foundation.layout.Spacer(Modifier.size(AingDimens.minimumTarget))
        }
        when (chrome.stage) {
            ChessRobotChrome.Stage.colorPick -> RobotColorPick(chess, chrome)
            ChessRobotChrome.Stage.playing, ChessRobotChrome.Stage.result -> RobotMatch(chess, chrome, state)
        }
    }
}

@Composable
private fun RobotColorPick(chess: ChessStore, chrome: ChessRobotChrome) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2, bottom = AingDimens.space4),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing)) {
        BoardGroup {
            BoardRow(minHeight = AingDimens.rowHeightTwoLine) {
                BoardPortrait(ChessUser.chessAI.characterID, CharacterMood.Plain, 44.dp, stoneIsBlack = null)
                Column(Modifier.weight(1f)) {
                    Text(ChessPhoneText.robotPromptTitle, style = BoardText.rowTitle(), color = colors.label)
                    Text(ChessPhoneText.robotPromptCaption, style = BoardText.rowSubtitle(), color = colors.label2)
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (color in listOf(ChessColor.white, ChessColor.black)) {
                Column(
                    Modifier.weight(1f).defaultMinSize(minHeight = 96.dp).background(colors.surface, RoundedCornerShape(AingDimens.tileRadius))
                        .clickable(enabled = chrome.canStart) { chess.startAIMatch(color) }.padding(vertical = 14.dp, horizontal = 8.dp)
                        .testTag("chess-robot-${color.rawValue}"),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ChessColorDot(color, 30.dp)
                    Text(if (color == ChessColor.white) ChessPhoneText.robotPlayWhite else ChessPhoneText.robotPlayBlack,
                        style = BoardText.subheadline().copy(fontWeight = FontWeight.SemiBold), color = if (chrome.canStart) colors.label else colors.label2)
                }
            }
        }
        chrome.blockReason?.let { BoardNotice(it) }
        chrome.notice?.let { BoardNotice(it) }
        // INV-GamesChessAIViews-faf1534b 이식: 로그인 없이 둘 수 있다는 사실을 **글자로** 둔다 — 누가 이 화면을 로그인 뒤로 옮기면 문구부터 어긋나 눈에 띈다.
        FootNote(ChessPhoneText.robotNoSignIn, AppIcon.HowToReg)
        FootNote(ChessPhoneText.robotNoRecord, AppIcon.Memory)
    }
}

@Composable
private fun RobotMatch(chess: ChessStore, chrome: ChessRobotChrome, state: ChessScreenState) {
    val colors = AingTheme.colors
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val side = ChessMatchChrome.side(maxWidth, maxHeight, AingDimens.sideMargin, isLargeText = false, isAccessibilitySize = false)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space1, bottom = AingDimens.space4),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            if (chrome.stage == ChessRobotChrome.Stage.result) {
                BoardGroup(Modifier.semantics(mergeDescendants = true) {}) {
                    BoardRow(minHeight = AingDimens.rowHeightTwoLine) {
                        Column(Modifier.weight(1f)) {
                            Text(ChessPhoneText.outcomeTitle(chrome.outcome), style = BoardText.title3(), color = colors.label)
                            Text(chrome.endReasonLine, style = BoardText.rowSubtitle(), color = colors.label2)
                            Text(ChessPhoneText.robotOpponentLine, style = BoardText.caption(), color = colors.label2)
                        }
                    }
                }
            }
            RobotPlayerCard(chess, chrome, isMe = false)
            chrome.board?.let { board ->
                val match = chess.match
                @Suppress("UNUSED_VARIABLE") val version = state.flightVersion
                val flight = if (match != null) state.matchFlight.observe(match.id, match.plyCount, match.position, match.lastMove, chess.isWindowVisible, chess.isWindowOccluded, chess.clock()) else null
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    ChessBoard(
                        position = board.position, flight = flight, whiteAtBottom = board.whiteAtBottom, selection = board.selection, legalTargets = board.legalTargets,
                        lastMove = board.lastMove?.let { it.from to it.to }, checkSquare = board.checkSquare,
                        onTapSquare = { square -> chess.scope.launch { chess.tap(square) } }, side = side,
                        onFlightFinished = { generation -> state.matchFlight.expire(generation); state.flightVersion += 1 },
                        accessibility = ChessPhoneText.boardAccessibility(chrome.plyCount, chrome.turn, chrome.isInCheck),
                        testTag = "chess-robot-board",
                    )
                }
            }
            RobotPlayerCard(chess, chrome, isMe = true)
            if (chrome.stage == ChessRobotChrome.Stage.playing) {
                Text(chrome.statusLine, style = BoardText.rowSubtitle().copy(fontWeight = if (chrome.isInCheck) FontWeight.SemiBold else FontWeight.Normal),
                    color = if (chrome.isInCheck) colors.danger else colors.label2)
            }
            FootNote(ChessPhoneText.robotNoRecord, AppIcon.Memory)
            // 1:1 의 "앱을 나가도 차례 시간은 흘러요"와 **정반대 사실**이다 — 로봇 판 시계는 떠나면 멈춘다.
            FootNote(ChessPhoneText.robotClockPauses, AppIcon.PauseCircle)
            chrome.notice?.let { BoardNotice(it) }
            if (chrome.canResign) {
                BoardButton(ChessPhoneText.resign, kind = BoardButtonKind.Destructive, fillsWidth = true) { state.confirmsResign = true }
            }
            if (chrome.canRestart) {
                BoardButton(ChessPhoneText.robotRematch, kind = BoardButtonKind.Filled, fillsWidth = true) { chess.restartAIMatch() }
                BoardButton(ChessPhoneText.backToLobby, kind = BoardButtonKind.Gray, fillsWidth = true) { chess.backToLobby(); state.robotScreenOpen = false }
            }
        }
    }
}

@Composable
private fun RobotPlayerCard(chess: ChessStore, chrome: ChessRobotChrome, isMe: Boolean) {
    val colors = AingTheme.colors
    val human = chrome.humanColor ?: ChessColor.white
    val color = if (isMe) human else human.opponent
    // INV-GamesChessAIViews-94164c17 이식: 차례는 `turn` 으로 읽는다 — 시계의 `running` 은 화면이 안 보이면 null 이 되어 테두리가 사라진다.
    val isTurn = chrome.turn == color
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    Row(
        Modifier.fillMaxWidth().background(colors.surface, shape).border(2.dp, if (isTurn) colors.workingDot else Color.Transparent, shape).padding(horizontal = 14.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isMe) Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { ChessColorDot(color, 32.dp) }
        else BoardPortrait(chrome.opponent?.characterID, CharacterMood.Plain, 44.dp, stoneIsBlack = null)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) {}) {
            Text(if (isMe) ChessPhoneText.me else (chrome.opponent?.displayName ?: ChessPhoneText.robotName), style = BoardText.rowTitle(), color = colors.label)
            Text(ChessPhoneText.stoneName(color), style = BoardText.rowSubtitle(), color = colors.label2)
        }
        val clock = chrome.clock
        if (!isMe && chrome.isRobotThinking) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.semantics { contentDescription = ChessPhoneText.robotThinking }) {
                AingIcon(AppIcon.MoreHoriz, contentDescription = null, size = 14.dp, tint = colors.accent)
                Text(ChessPhoneText.robotThinkingShort, style = BoardText.caption().copy(fontWeight = FontWeight.Bold), color = colors.accent)
            }
        } else if (clock != null) {
            val tick = rememberTicker(running = clock.running != null)
            val remaining = tick.let { clock.remainingSeconds(color, chess.clock()) }
            Text(ChessPhoneText.clock(remaining), style = BoardText.digits(BoardText.rowTitle()), color = if (remaining <= 10 && isTurn) colors.danger else colors.label,
                modifier = Modifier.semantics { contentDescription = ChessPhoneText.clockAccessibility(remaining) })
        }
    }
}

@Composable
private fun FootNote(text: String, icon: AppIcon) {
    val colors = AingTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        AingIcon(icon, contentDescription = null, size = 15.dp, tint = colors.accent)
        Text(text, style = BoardText.rowSubtitle(), color = colors.label2)
    }
}
