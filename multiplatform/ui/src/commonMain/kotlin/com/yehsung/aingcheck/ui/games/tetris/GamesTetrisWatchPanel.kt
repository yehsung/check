// 원본: Sources/CheckMobileKit/Games/GamesTetrisWatch.swift:248-524 @ 3bd04bd (관전 판 · 관전 판 한 장 · 로비 행의 관전 입구)
// 원본: Sources/CheckMobileKit/Games/GamesComponents.swift:370-405 @ 3bd04bd (관전 입구 게이트 · '곧 열려요' 캡션 — 테트리스 입구가 같은 계약을 진다)
//
// 테트리스 관전 — "지금 대결 중" 절이 **그 자리에서** 이 모양으로 바뀐다(자리 계약 — 새 화면을 밀면 로비 화면이 사라져 폴링이 죽는다).
// 그래서 제 스크롤도 떠 있는 아래 막대도 두지 않는다. **입력이 하나도 없다**(판정은 core GamesTetrisWatchPlan · Status · Budget).
package com.yehsung.aingcheck.ui.games.tetris

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.tetris.TetrisDuelCell
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisWatchBudget
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisWatchPlan
import com.yehsung.aingcheck.core.stores.tetris.GamesTetrisWatchStatus
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelLiveMatch
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelNoticeText
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisPhoneText
import com.yehsung.aingcheck.core.stores.tetris.TetrisSpectateSide
import com.yehsung.aingcheck.core.stores.tetris.TetrisSpectateState
import com.yehsung.aingcheck.core.stores.tetris.isMine
import com.yehsung.aingcheck.core.stores.tetris.leaveWatch
import com.yehsung.aingcheck.core.stores.tetris.startWatching
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.StakeLine
import com.yehsung.aingcheck.ui.games.minigame.kit.WatcherBadge
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/**
 * 관전 판. 위에서부터: 절 머리(+오른쪽 [나가기]) · 두 판 나란히(+ 각 판 아래 이름·숫자) · 상태 상자 · 판돈·관전자 수 · 캡션.
 * [viewportHeight] 는 로비 스크롤의 **보이는 높이**(칸 변 예산의 세로 몫 — 0 이면 아직 모른다, 그때는 폭만으로 고른다).
 */
@Composable
fun GamesTetrisWatchPanel(store: TetrisDuelStore, watch: TetrisSpectateState, viewportHeight: Dp = 0.dp) {
    val colors = AingTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        // 문은 **하나**다 — leaveWatch() 가 관전을 내리고 로비를 다시 읽는다(stopWatching() 을 부르면 낡은 목록으로 돌아온다).
        SectionHeader(TetrisPhoneText.watchTitle, trailing = SectionTrailing.Action(TetrisPhoneText.leaveWatch) { store.leaveWatch() }, padded = true)
        // INV-GamesTetrisWatch-fd449050 이식: 판 칸 변을 **제안 높이**로 정하지 않는다(스크롤 안에서는 제안 높이를 그대로 먹어 절이 세로로 늘어진다) —
        //   폭은 이 절의 제약에서, 세로는 부르는 쪽이 잰 **보이는 높이**에서 와서 예산 표(GamesTetrisWatchBudget.cell) 한 곳이 칸 변을 고른다.
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            val cell = GamesTetrisWatchBudget.cell(maxWidth.value.toDouble(), viewportHeight.value.toDouble())
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(GamesTetrisWatchBudget.columnGap.dp)) {
                WatchSide(watch.a, cell, Modifier.weight(1f))
                WatchSide(watch.b, cell, Modifier.weight(1f))
            }
        }
        StatusBox(watch)
        InsetGroup {
            GroupRow(dividerInset = null) {
                // 판돈 **액수만**(관전자는 이 판에서 한 푼도 얻지 못한다 — 접미사를 붙이지 않는다) + 관전자 수.
                val stake = watch.stake
                if (stake != null) StakeLine(stake, prefix = TetrisPhoneText.stakeTitle)
                else Text(TetrisPhoneText.watchStakeUnknown, style = rowSubtitleStyle(), color = colors.label2)
                Spacer(Modifier.weight(1f))
                WatcherBadge(store.spectatorCount)
            }
        }
        // 카드 밑 작은 줄: 입력이 없다는 사실 + 끝난 판의 3분 꼬리.
        Column(
            Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space1).semantics(mergeDescendants = true) { },
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(TetrisPhoneText.watchCaption, style = rowSubtitleStyle(), color = colors.label2)
            if (watch.isFinished) Text(TetrisPhoneText.watchTailCaption, style = rowSubtitleStyle(), color = colors.label2)
        }
    }
}

/** 한 자리: 판 · 이름 · 숫자 셋. 탑아웃한 쪽은 흐리게(서버가 말한 사실 — GamesTetrisWatchPlan.dims). 이름은 판정 겹 한 곳이 고른다. */
@Composable
private fun WatchSide(side: TetrisSpectateSide, cell: Double, modifier: Modifier) {
    val colors = AingTheme.colors
    val dimmed = GamesTetrisWatchPlan.dims(side)
    val name = GamesTetrisWatchStatus.displayName(side)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        Box(
            Modifier.fillMaxWidth().alpha(if (dimmed) 0.55f else 1f)
                .clearAndSetSemantics { contentDescription = TetrisPhoneText.watchBoardAccessibility(name, side.lines, side.pending) },
            contentAlignment = Alignment.Center,
        ) {
            WatchBoard(side.cells, cell)
            if (dimmed) ToppedOutBadge()
        }
        Column(Modifier.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                GamesPortrait(side.user?.characterID, CharacterMood.Plain, 22.dp)
                Text(name, style = rowTitleStyle(), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Stat(TetrisPhoneText.linesTitle, side.lines, colors.label)
            Stat(TetrisPhoneText.attackTitle, side.attackSent, colors.working)
            Stat(TetrisPhoneText.incomingLinesTitle, side.pending, if (side.pending > 0) colors.danger else colors.label2)
        }
    }
}

/** 관전 판 한 장 — 그림은 painter 한 벌(drawMiniBoard). cells 가 null 이면 **빈 우물**(망가진 판 때문에 화면이 서지 않는 일이 없게). */
@Composable
private fun WatchBoard(cells: List<List<TetrisDuelCell>>?, cell: Double) {
    GamesTetrisDuelMiniBoard(cells ?: emptyList(), cell = cell)
}

/** 상태 상자 — 진행 중은 초록 · 끝은 청회색 · 모름은 회색. **빨강은 쓰지 않는다**(관전자에게 결과를 지어내는 색이다). */
@Composable
private fun StatusBox(watch: TetrisSpectateState) {
    val colors = AingTheme.colors
    val kind = GamesTetrisWatchStatus.kind(watch)
    val tint = when (kind) {
        GamesTetrisWatchStatus.Kind.loading -> colors.label2
        GamesTetrisWatchStatus.Kind.live -> colors.working
        GamesTetrisWatchStatus.Kind.ended -> colors.offWork
    }
    val icon = when (kind) {
        GamesTetrisWatchStatus.Kind.loading -> AppIcon.HourglassEmpty
        GamesTetrisWatchStatus.Kind.live -> AppIcon.Visibility
        GamesTetrisWatchStatus.Kind.ended -> AppIcon.SportsScore
    }
    Column(
        Modifier.fillMaxWidth().background(tint.copy(alpha = 0.12f), RoundedCornerShape(AingDimens.innerRadius)).padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics(mergeDescendants = true) { },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AingIcon(icon, contentDescription = null, size = 16.dp, tint = tint)
            Text(GamesTetrisWatchStatus.headline(watch), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label)
        }
        GamesTetrisWatchStatus.detail(watch)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2) }
    }
}

/**
 * 로비 "지금 대결 중" 한 줄의 오른쪽 끝: **관전자 수** + [관전] 입구. 판정은 GamesTetrisWatchPlan.entry **하나**다(뷰가 깃발을 다시 읽지 않는다).
 * INV-GamesComponents-407e1efc 이식: 입구 게이트는 **관전 전용 깃발**(watchUnavailable — 관전 404 에 조건 없이 선다)이고 순위 깃발이 아니다 — 그 판정이
 *   GamesTetrisWatchPlan.entry 한 곳에 있어(.soon) 이 입구가 깃발을 겸업하지 않는다. 겸업하면 순위를 받아 둔 사용자에게 게이트가 영영 열려 같은 카드를
 *   눌러 404 를 무한히 낸다.
 * INV-GamesComponents-b397ecd3 이식: 서버에 관전이 아직 없으면 또렷한 칩을 흐려만 두지 않는다 — 칩을 빼고 **그 자리에 이유를 짧은 글자**로 둔다
 *   ('곧 열려요' — 보이스오버는 온전한 문장 TetrisDuelNoticeText.unavailable 을 읽는다). 폰엔 호버 툴팁이 없다.
 */
@Composable
fun GamesTetrisWatchEntry(store: TetrisDuelStore, live: TetrisDuelLiveMatch) {
    if (!GamesTetrisWatchPlan.hasTrailingContent(store, live)) return
    val colors = AingTheme.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        WatcherBadge(live.watchers)
        when (GamesTetrisWatchPlan.entry(store, store.isMine(live))) {
            GamesTetrisWatchPlan.Entry.absent -> Unit
            // 수락 직후·로비 주기 사이에 내 판이 잠깐 목록에 보이는 틈 — 비워 두면 "왜 내 판만 칩이 없나"로 읽힌다.
            GamesTetrisWatchPlan.Entry.myMatch -> Text(TetrisPhoneText.myMatch, style = rowSubtitleStyle(), color = colors.label2)
            GamesTetrisWatchPlan.Entry.soon -> Text(
                TetrisPhoneText.watchSoonCaption, style = rowSubtitleStyle(), color = colors.label2,
                modifier = Modifier.clearAndSetSemantics { contentDescription = TetrisDuelNoticeText.unavailable },
            )
            GamesTetrisWatchPlan.Entry.chip -> PillButton(TetrisPhoneText.watchChip, kind = PillKind.Tinted, size = PillSize.Sm) { store.startWatching(live.id) }
        }
    }
}
