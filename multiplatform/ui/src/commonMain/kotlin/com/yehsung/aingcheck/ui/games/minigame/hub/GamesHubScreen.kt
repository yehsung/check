// 원본: Sources/CheckMobileKit/Games/GamesTab.swift @ 3bd04bd (게임 탭 — 타일 · 오목/체스/1:1 테트리스 카드 · 오늘 내 순위 · 지금 대결 중)
// 원본: Sources/CheckMobileKit/Games/GamesComponents.swift:233-414 @ 3bd04bd (GamesLiveMatchRow — 허브 쪽 몫: 관전 입구 없이 관전자 수만)
//
// 게임 탭 첫 화면(SPEC-ios §3.5 · w15 시안 B 07): 큰 제목 + 상품 부제 · 오른쪽 위 루비 유리 알약(→ 상점) · 미니게임 타일(2열 격자) ·
// 1:1 오목·체스·테트리스 카드 · 오늘 내 순위 · 지금 대결 중(오목 — 로비를 이미 알 때만, 새 조회를 더하지 않는다).
// **길건너 아잉이는 없다**(G §8-18 7 — iOS 1.0.14 바닥: phoneCases 가 거르고, 그 위에서 미니게임 표시 깃발 MiniGameExposure 가 좁힌다).
// 경로(쌓기·딥링크)는 셸(K11 조립)이 쥔다 — 이 화면은 [onOpen] 으로 목적지를 넘기기만 한다. 대국 중 화면 꺼짐 방지는 화면이 쓰지 않는다
// (주인은 스토어 하나 — GamesStore.installIdleTimerSink, Android 싱크는 screens/games/hub GamesKeepScreenOn).
package com.yehsung.aingcheck.ui.games.minigame.hub

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessRecord
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GamesText
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuLiveMatch
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameBoard
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisDuelCard
import com.yehsung.aingcheck.core.stores.tetris.TetrisPhoneText
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.ui.components.RubyBalanceChip
import com.yehsung.aingcheck.ui.components.RubyChipStyle
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.minigame.kit.AingChip
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.RankBadge
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.StakeLine
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.WatcherBadge
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/**
 * 오목·체스 카드가 읽는 사실 중 게임 탭 문(GamesContext 의 GamesGomokuLink·GamesBoardGameLink)에 **없는** 것들(W2-d 스토어 값).
 * 조립(K11)이 [of] 로 진짜 스토어를 건넨다. 시험·스냅숏은 손으로 채운다.
 */
interface GamesHubBoardFacts {
    val gomokuRecord: GomokuRecord?
    val gomokuHasOutgoing: Boolean

    /** 받은함 조회가 실패했고 아는 받은 신청이 없다(Swift `gomoku.inboxLoadFailed && gomoku.incoming.isEmpty`). */
    val gomokuInboxFailedEmpty: Boolean

    /** 지금 대결 중(오목 로비가 이미 아는 것 — 허브는 새 조회를 더하지 않는다). */
    val gomokuLiveMatches: List<GomokuLiveMatch>
    val chessRecord: ChessRecord?
    val chessHasIncoming: Boolean
    val chessHasOutgoing: Boolean

    /** 당겨서 새로고침의 오목·체스 몫(Swift `gomoku.loadInbox()` · `chess.refreshLobby()`). */
    suspend fun refreshBoardGames()

    companion object {
        /** 진짜 스토어 둘(W2-d)을 잇는다. */
        fun of(gomoku: com.yehsung.aingcheck.core.stores.gomoku.GomokuStore, chess: com.yehsung.aingcheck.core.stores.chess.ChessStore): GamesHubBoardFacts =
            object : GamesHubBoardFacts {
                override val gomokuRecord: GomokuRecord? get() = gomoku.record
                override val gomokuHasOutgoing: Boolean get() = gomoku.outgoing != null
                override val gomokuInboxFailedEmpty: Boolean get() = gomoku.inboxLoadFailed && gomoku.incoming.isEmpty()
                override val gomokuLiveMatches: List<GomokuLiveMatch> get() = gomoku.liveMatches
                override val chessRecord: ChessRecord? get() = chess.record
                override val chessHasIncoming: Boolean get() = chess.visibleIncoming != null
                override val chessHasOutgoing: Boolean get() = chess.outgoing != null
                override suspend fun refreshBoardGames() {
                    gomoku.loadInbox()
                    chess.refreshLobby()
                }
            }
    }
}

/** 게임 탭 꼬리표(시험·계측). */
object GamesHubTags {
    fun tile(kind: MiniGameKind): String = "games.hub.tile.${kind.rawValue}"
    fun rankRow(kind: MiniGameKind): String = "games.hub.rank.${kind.rawValue}"
    const val GOMOKU: String = "games.hub.gomoku"
    const val CHESS: String = "games.hub.chess"
    const val TETRIS_DUEL: String = "games.hub.tetrisDuel"
}

/** 이 빌드 게임 탭에 서는 미니게임(폰 노출 규칙 ∩ 표시 깃발 — 길건너는 없다). 타일·오늘 내 순위·새로고침이 **같은 한 목록**을 본다. */
val hubMiniGames: List<MiniGameKind> get() = MiniGameExposure.visible

@Composable
fun GamesHubScreen(
    store: GamesStore,
    facts: GamesHubBoardFacts,
    art: MiniGameArt,
    now: () -> SwiftDate,
    onOpen: (GamesDestination) -> Unit,
    onOpenShop: () -> Unit,
    onOpenRankings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LaunchedEffect(store) { store.hubDidAppear() }
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().background(colors.background).verticalScroll(rememberScrollState())) {
        Row(
            Modifier.fillMaxWidth().padding(start = AingDimens.titleMargin, end = AingDimens.sideMargin, top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(GamesText.tabTitle, style = MaterialTheme.typography.headlineLarge, color = colors.label, modifier = Modifier.weight(1f))
            RubyBalanceChip(store.rubyBalance, rememberRubyArt(22f), style = RubyChipStyle.Toolbar, onClick = onOpenShop)
        }
        Column(Modifier.padding(horizontal = AingDimens.sideMargin).padding(bottom = 24.dp)) {
            Text(
                GamesMiniGameText.prizeCaption, style = MaterialTheme.typography.bodyMedium, color = colors.label2,
                modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin),
            )
            MiniGameTiles(store, art, onOpen, Modifier.padding(top = 14.dp))
            GomokuCard(store, facts, onOpen, Modifier.padding(top = 12.dp))
            ChessCard(store, facts, onOpen, Modifier.padding(top = 12.dp))
            TetrisDuelCard(store, onOpen, Modifier.padding(top = 12.dp))
            TodayRanks(store, art, onOpen, onOpenRankings)
            LiveMatches(facts, now)
        }
    }
}

// MARK: 미니게임 타일

@Composable
private fun MiniGameTiles(store: GamesStore, art: MiniGameArt, onOpen: (GamesDestination) -> Unit, modifier: Modifier) {
    val fontScale = LocalDensity.current.fontScale
    val kinds = store.miniGames.visibleKinds
    // 큰 글자: 한 열(반 폭 타일에서는 "오늘 최고 874점 · 3위"가 낱글자로 꺾인다). 보통은 2열 격자 — 셋째 타일은 다음 줄 왼쪽.
    val columns = if (fontScale >= 1.3f) 1 else 2
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        kinds.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { kind -> MiniGameTile(store, kind, art, onOpen, Modifier.weight(1f)) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun MiniGameTile(store: GamesStore, kind: MiniGameKind, art: MiniGameArt, onOpen: (GamesDestination) -> Unit, modifier: Modifier) {
    val hub = store.miniGames
    val colors = AingTheme.colors
    val line = GamesText.todayLine(hub.myTodayBest(kind), hub.myRank(kind), hub.boards[kind] ?: GamesMiniGameBoard())
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    Column(
        modifier.clip(shape).background(colors.surface, shape)
            .clickable(role = Role.Button, onClickLabel = "${kind.title} 게임을 열어요") { onOpen(GamesDestination.MiniGame(kind)) }
            .semantics(mergeDescendants = true) { }
            .testTag(GamesHubTags.tile(kind)),
    ) {
        MiniGameTileArt(kind, art, Modifier.fillMaxWidth().height(112.dp))
        Column(Modifier.padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 13.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(kind.title, style = rowTitleStyle(), color = colors.label)
            Text(line, style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label2)
        }
    }
}

// MARK: 1:1 카드 셋 — 같은 모양(썸네일 60 · 제목 · 부제 · 칩 + 보조 한 줄 · 꺾쇠)

@Composable
private fun BoardGameCard(
    title: String,
    subtitle: String,
    chip: String?,
    detail: String?,
    blocked: Boolean,
    openHint: String,
    tag: String,
    modifier: Modifier,
    thumbnail: @Composable () -> Unit,
    onClick: () -> Unit,
) {
    val colors = AingTheme.colors
    InsetGroup(
        modifier.alpha(if (blocked) 0.55f else 1f)
            .clickable(enabled = !blocked, role = Role.Button, onClickLabel = openHint, onClick = onClick)
            .semantics(mergeDescendants = true) { }
            .testTag(tag),
    ) {
        Row(Modifier.padding(horizontal = AingDimens.cardPadding, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            thumbnail()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(title, style = rowTitleStyle(), color = colors.label)
                Text(subtitle, style = rowSubtitleStyle(), color = colors.label2)
                if (chip != null || detail != null) {
                    Row(Modifier.padding(top = 3.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (chip != null) AingChip(chip)
                        if (detail != null) Text(detail, style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label2)
                    }
                }
            }
            AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 18.dp, tint = colors.label3)
        }
    }
}

private fun gomokuRecordLine(record: GomokuRecord?): String? = record?.let { GomokuPhoneText.recordTitle + " " + "${it.wins}승 ${it.losses}패 ${it.draws}무" }

@Composable
private fun GomokuCard(store: GamesStore, facts: GamesHubBoardFacts, onOpen: (GamesDestination) -> Unit, modifier: Modifier) {
    val incoming = store.badgeCount
    val gomoku = store.context.gomoku
    // INV-GamesTab-805914bf 이식: 한 사람 한 판(B8) — **이 방향은 클라밖에 막는 데가 없다.** 서버의 오목 게이트는 체스·테트리스를 모르므로 다른 판이 흐르는 동안
    //   이 카드를 열어 두면 오목 로비의 [수락]으로 오목이 시작되고 판돈이 걸린 판이 조용히 시간패한다. 화면을 **아예 열지 않는 것**이 그 수락을 막는 유일한
    //   길이다(카드 비활성). 딥링크로 들어오는 같은 길은 GamesStore.routeStep 이 막는다 — 두 입구가 짝이다.
    val blockedBy = store.gomokuEntryBlock
    // AI 판은 받은 신청을 가리지 않는다 — 규칙과 까닭은 GamesText.hubShowsActiveMatch.
    val active = GamesText.hubShowsActiveMatch(store.hasActiveGomokuMatch, gomoku.isAIMatch, incoming)
    val line = GamesText.gomokuLine(incoming, active, facts.gomokuHasOutgoing, facts.gomokuInboxFailedEmpty)
    val chip = when {
        blockedBy != null -> GamesBusyText.entryBlock(blockedBy)
        active -> GamesText.activeMatchChip
        incoming > 0 -> GamesText.incomingChip(incoming)
        else -> null
    }
    val record = gomokuRecordLine(facts.gomokuRecord)
    // 칩이 없을 때: 보낸 신청 대기·받은함 실패는 그 한 줄이 먼저, 아니면 전적(모르면 안내 한 줄).
    val detail = when {
        blockedBy != null -> GamesBusyText.entryBlockHint(blockedBy, GamesBusyGame.gomoku)
        chip != null -> record
        facts.gomokuHasOutgoing || facts.gomokuInboxFailedEmpty -> line
        else -> record ?: line
    }
    BoardGameCard(
        GomokuPhoneText.title, GamesText.gomokuCardSubtitle, chip, detail, blockedBy != null,
        if (blockedBy == null) "오목 대결 화면을 열어요" else GamesBusyText.entryBlockHint(blockedBy, GamesBusyGame.gomoku) ?: "",
        GamesHubTags.GOMOKU, modifier, { GamesWoodThumbnail() },
    ) { onOpen(GamesDestination.Gomoku) }
}

@Composable
private fun ChessCard(store: GamesStore, facts: GamesHubBoardFacts, onOpen: (GamesDestination) -> Unit, modifier: Modifier) {
    // INV-GamesTab-fc7ae480 이식: 막는 방향은 **양쪽이다** — 오목(·테트리스) 판이 흐르면 이 카드가 막히고, 체스 판이 흐르면 위 오목 카드가 막힌다.
    //   한 방향만 막으면 막히지 않은 쪽으로 들어가 다른 판을 시간패한다(판정 = GamesStore.chessEntryBlock 하나).
    val blockedBy = store.chessEntryBlock
    val incoming = facts.chessHasIncoming
    // 로봇 판은 사람의 신청을 가리지 않는다 — 오목 카드와 같은 규칙.
    val active = GamesText.hubShowsActiveMatch(store.hasActiveChessMatch, store.chess.isAIMatch, if (incoming) 1 else 0)
    val chip = when {
        blockedBy != null -> GamesBusyText.entryBlock(blockedBy)
        active -> GamesText.activeMatchChip
        incoming -> ChessPhoneText.incomingChip
        else -> null
    }
    val record = facts.chessRecord?.let { ChessPhoneText.recordTitle + " " + ChessPhoneText.record(it) }
    val detail = when {
        blockedBy != null -> GamesBusyText.entryBlockHint(blockedBy, GamesBusyGame.chess)
        chip != null -> record
        facts.chessHasOutgoing -> ChessPhoneText.outgoingLine
        else -> record ?: ChessPhoneText.idleLine
    }
    BoardGameCard(
        ChessPhoneText.title, ChessPhoneText.cardSubtitle, chip, detail, blockedBy != null,
        if (blockedBy == null) ChessPhoneText.cardOpenHint else GamesBusyText.entryBlockHint(blockedBy, GamesBusyGame.chess) ?: "",
        GamesHubTags.CHESS, modifier, { GamesChessTabThumbnail() },
    ) { onOpen(GamesDestination.Chess) }
}

@Composable
private fun TetrisDuelCard(store: GamesStore, onOpen: (GamesDestination) -> Unit, modifier: Modifier) {
    // INV-GamesTab-21bc525f 이식: 막는 방향은 **삼각이다**(P3) — 오목·체스 판이 흐르면 이 카드가 막히고, 테트리스 판이 흐르면 위 두 카드가 막힌다. 오목 쪽 서버
    //   게이트는 남을 모르므로 안 막은 입구로 들어가면 흐르던 테트리스 판이 15초 침묵으로 **판돈째 진다**(서버 D5). 판정 = GamesStore.tetrisEntryBlock.
    // INV-GamesTab-0a89f10e 이식: 칩과 보조 줄의 **서열은 GamesTetrisDuelCard 한 곳**이다(차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본 한 줄) —
    //   여기서 삼항으로 다시 고르지 않는다(서열이 두 벌이 되어 한쪽만 고쳐진 채 초록으로 남는다).
    // INV-GamesTab-6bd4e9f1 이식: 막혔을 때 **두 자리를 다 그린다**(칩 = 왜 · 보조 줄 = 언제 풀리는지) — 폰엔 호버 툴팁이 없어 한 자리만 그리면 기다릴 끝을
    //   모른다. GamesTetrisDuelCard.chip·detail 이 막힘에 둘 다 값을 준다(BoardGameCard 는 둘 다 그린다).
    val blockedBy = store.tetrisEntryBlock
    BoardGameCard(
        TetrisPhoneText.title, TetrisPhoneText.cardSubtitle, GamesTetrisDuelCard.chip(store), GamesTetrisDuelCard.detail(store), blockedBy != null,
        if (blockedBy == null) TetrisPhoneText.cardOpenHint else GamesBusyText.entryBlockHint(blockedBy, GamesBusyGame.tetris) ?: "",
        GamesHubTags.TETRIS_DUEL, modifier, { GamesTetrisDuelTabThumbnail() },
    ) { onOpen(GamesDestination.TetrisDuel) }
}

// MARK: 오늘 내 순위

@Composable
private fun TodayRanks(store: GamesStore, art: MiniGameArt, onOpen: (GamesDestination) -> Unit, onOpenRankings: () -> Unit) {
    val hub = store.miniGames
    val colors = AingTheme.colors
    val kinds = store.miniGames.visibleKinds
    SectionHeader(GamesText.todayRankTitle, trailing = SectionTrailing.Action(GamesText.seeAllRankings, onOpenRankings), padded = true)
    InsetGroup {
        kinds.forEachIndexed { index, kind ->
            val board = hub.boards[kind] ?: GamesMiniGameBoard()
            val rank = hub.myRank(kind)
            GroupRow(
                dividerInset = if (index == kinds.size - 1) null else AingDimens.cardPadding + 30.dp + AingDimens.space3,
                modifier = Modifier.clickable(role = Role.Button) { onOpen(GamesDestination.MiniGame(kind)) }
                    .semantics(mergeDescendants = true) { }.testTag(GamesHubTags.rankRow(kind)),
            ) {
                GamesGameIconSquare(kind, art)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(kind.title, style = rowTitleStyle(), color = colors.label)
                    Text(GamesText.hubRankSubtitle(board), style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label2)
                }
                if (rank != null) Box(Modifier.semantics { contentDescription = "내 순위 ${rank}위" }) { RankBadge(rank) }
            }
        }
    }
}

// MARK: 지금 대결 중(오목)

@Composable
private fun LiveMatches(facts: GamesHubBoardFacts, now: () -> SwiftDate) {
    val lives = facts.gomokuLiveMatches
    if (lives.isEmpty()) return
    SectionHeader(GomokuPhoneText.liveTitle, trailing = SectionTrailing.Label(GomokuPhoneText.liveCount(lives.size)), padded = true)
    InsetGroup {
        lives.forEachIndexed { index, live -> HubLiveMatchRow(live, now, isLast = index == lives.size - 1) }
    }
}

/**
 * "지금 대결 중" 한 줄(허브): 두 얼굴 vs · 이름 둘 · 판돈 · 경과 · 오른쪽 끝 관전자 수. 허브에는 [관전] 입구가 **없다**(관전은 오목 로비 자리에만
 * 서므로 허브에서 누르면 아무 일도 안 일어난 것처럼 보인다 — 입구는 오목 로비 하나).
 * INV-GamesComponents-836dfabe 이식: 관전자 수는 **주 스위치와 무관**하다 — 그 값은 로비 응답이 실어 온 사실(live.watchers)이고 관전에 들어갈 수
 *   있는가와는 다른 축이다. 그래서 허브(입구 없음)에서도 보인다.
 * INV-GamesComponents-4a509409 이식: 큰 글자 갈래와 좁은 폭 갈래가 겹쳐도 싸우지 않는다 — 두 갈래의 접힌 꼴이 **같은 한 꼴**(아래 stacked)이다.
 *   큰 글자(글자 배율 1.3 이상)면 곧장 접는다.
 */
@Composable
private fun HubLiveMatchRow(live: GomokuLiveMatch, now: () -> SwiftDate, isLast: Boolean) {
    val colors = AingTheme.colors
    val stacked = LocalDensity.current.fontScale >= 1.3f
    val elapsed = GomokuPhoneText.elapsedPhrase(now().timeIntervalSince(live.startedAt))
    val texts: @Composable () -> Unit = {
        Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(live.a.displayName + " · " + live.b.displayName, style = rowTitleStyle(), color = colors.label)
            Row(verticalAlignment = Alignment.CenterVertically) {
                StakeLine(live.stake.rawValue.toInt(), prefix = GomokuPhoneText.stakeTitle)
                Text(" · $elapsed", style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label2)
            }
        }
    }
    val faces: @Composable () -> Unit = {
        Row(Modifier.clearAndSetSemantics { }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PersonAvatar(live.a.displayName, live.a.id, 30.dp)
            Text("vs", style = MaterialTheme.typography.bodySmall, color = colors.label2)
            PersonAvatar(live.b.displayName, live.b.id, 30.dp)
        }
    }
    GroupRow(dividerInset = if (isLast) null else AingDimens.cardPadding) {
        if (stacked) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                faces()
                texts()
                WatcherBadge(live.watchers.toInt())
            }
        } else {
            faces()
            Box(Modifier.weight(1f)) { texts() }
            WatcherBadge(live.watchers.toInt())
        }
    }
}

/** 시험용: 오목·체스 사실을 손으로 채운 꼴. */
data class GamesHubBoardFactsSnapshot(
    override val gomokuRecord: GomokuRecord? = null,
    override val gomokuHasOutgoing: Boolean = false,
    override val gomokuInboxFailedEmpty: Boolean = false,
    override val gomokuLiveMatches: List<GomokuLiveMatch> = emptyList(),
    override val chessRecord: ChessRecord? = null,
    override val chessHasIncoming: Boolean = false,
    override val chessHasOutgoing: Boolean = false,
) : GamesHubBoardFacts {
    override suspend fun refreshBoardGames() = Unit
}
