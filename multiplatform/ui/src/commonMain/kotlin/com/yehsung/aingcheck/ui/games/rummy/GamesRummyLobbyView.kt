// 원본: Sources/check/RummyPanelLobby.swift:128 (RummyLobbyView) · :220 (RummyPeopleColumn) · :321 (RummyOutdatedFold) · :348 (RummyPersonRow) · :516 (RummyTableCard 의 새 탁자) · :770 (RummyJoinRow · RummyJoinCard) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §5
//
// 폰 로비 — 맥 두 열을 한 줄기 스크롤로 편다(체스·테트리스 로비 관례). 위에서 아래로: 받은 초대 + 공개 방 · 내 전적과 루비 · 안내 · 새 탁자(판돈 · 공개 여부) · [사람 | 순위].
// 받은 초대가 맨 위다 — 스크롤을 내려야 보이는 자리에 두면 그 사이 방이 찬다.
// [초대] 는 방이 없어도 살아 있다: 고른 판돈·공개 여부로 탁자를 열고 그 사람을 줄 세워 차례로 부른다(`RummyStore.inviteQueued` → RummyInviteQueue).
// 판단은 전부 core/stores `GamesRummyLobbyPlan` 이 쥐고 이 화면은 받아 그린다. 판돈 깃발이 꺼진 빌드는 입구(탁자 · 참가 · 초대)를 그리지 않는다 — 거절 · 순위 · 전적은 그대로다.
// availability 안내는 껍데기(GamesRummyScreen)가 이 뷰 대신 그린다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyExitPolicy
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyEntry
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyLobbyPlan
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyLobbyTab
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyPersonAction
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyPersonStatus
import com.yehsung.aingcheck.core.stores.rummy.RummyJoinable
import com.yehsung.aingcheck.core.stores.rummy.RummyLobbyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.reloadLobby
import com.yehsung.aingcheck.core.stores.rummy.createRoom
import com.yehsung.aingcheck.core.stores.rummy.decline
import com.yehsung.aingcheck.core.stores.rummy.join
import com.yehsung.aingcheck.core.stores.rummy.myRoom
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyLobbyUser
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.ui.components.RubyPrice
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.kit.AingChip
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesSheet
import com.yehsung.aingcheck.ui.games.minigame.kit.InlineNotice
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadFailureRow
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadingRow
import com.yehsung.aingcheck.ui.games.minigame.kit.NoticeKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonName
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 로비 꼬리표(시험·계측). */
object GamesRummyLobbyTags {
    const val OPEN_TABLE: String = "rummy.lobby.openTable"
    const val INVITE_SHEET: String = "rummy.lobby.inviteSheet"
    const val OPEN_AND_CALL: String = "rummy.lobby.openAndCall"
    const val PUBLIC: String = "rummy.lobby.public"
    const val OUTDATED_FOLD: String = "rummy.lobby.outdatedFold"
    const val RULES: String = "rummy.lobby.rules"

    fun tab(value: GamesRummyLobbyTab): String = "rummy.lobby.tab.${value.name}"
    fun stake(value: Long): String = "rummy.lobby.stake.$value"
    fun person(id: SwiftUUID): String = "rummy.lobby.person.${id.lowercased}"
    fun invite(id: SwiftUUID): String = "rummy.lobby.invite.${id.lowercased}"
    fun join(id: SwiftUUID): String = "rummy.lobby.join.${id.lowercased}"
    fun decline(id: SwiftUUID): String = "rummy.lobby.decline.${id.lowercased}"
}

/** 로비 — 받은 초대 · 공개 방 · 사람 · 판돈 · 순위 탭. 다른 게임 판 막기는 [store] 의 `rummyEntryBlock`. */
@Composable
fun GamesRummyLobbyView(
    store: GamesStore,
    rummy: RummyStore,
    myUserID: String?,
    me: RummySeatFace,
    onRules: () -> Unit,
    onBack: () -> Unit,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
) {
    var tab by remember { mutableStateOf(GamesRummyLobbyTab.people) }
    // 방 없이 누른 [초대]의 판돈 시트 대상.
    var inviteTarget by remember { mutableStateOf<RummyLobbyUser?>(null) }
    val block = store.rummyEntryBlock
    val balance = store.rubyBalance ?: rummy.rubyBalance
    val entry = GamesRummyEntry(rummy.availability, rummy.duelsLocked, block, rummy.isWorking, balance)
    val myRoom = rummy.myRoom
    val warnings = GamesRummyLobbyPlan.entryWarnings(GamesBusyText.entryBlockNotice(block, GamesBusyGame.rummy), rummy.duelsLocked)
    val date = now()
    val joinables = GamesRummyLobbyPlan.joinables(rummy.lobby, myRoom?.id, rummy.duelsLocked) { room ->
        rummy.deviceDate(room.expiresAtMs)?.let { it <= date } ?: false
    }
    Column(modifier) {
        GamesHeaderBar(RummyPhoneText.title, onBack = onBack) { GamesRummyRulesButton(onRules, Modifier.testTag(GamesRummyLobbyTags.RULES)) }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin)
                .padding(top = AingDimens.space2, bottom = AingDimens.space6),
        ) {
            // ★ 탭이 **위**다. 큐브 로비는 받은 초대 · 공개 방 · 새 탁자가 더 있어서 절 아래에 두면 [순위]가 첫 화면에서 안 보인다(iOS 실화면).
            Summary(rummy, balance)
            val storeNotice = GamesRummyLobbyPlan.storeNotice(rummy.notice, warnings)
            if (storeNotice != null) {
                InlineNotice(storeNotice, Modifier.padding(top = AingDimens.rowSpacing), NoticeKind.Warning)
            } else {
                // 스스로 나온 사실을 말하는 줄이라 경고가 아니다.
                store.rummyLeftByTabNotice?.let { InlineNotice(it, Modifier.padding(top = AingDimens.rowSpacing), NoticeKind.Info) }
            }
            warnings.forEach { InlineNotice(it, Modifier.padding(top = AingDimens.rowSpacing), NoticeKind.Warning) }
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(top = AingDimens.rowSpacing)) {
                GamesRummyLobbyTab.entries.forEachIndexed { index, value ->
                    SegmentedButton(
                        selected = tab == value,
                        onClick = { tab = value },
                        shape = SegmentedButtonDefaults.itemShape(index, GamesRummyLobbyTab.entries.size),
                        modifier = Modifier.testTag(GamesRummyLobbyTags.tab(value)),
                        icon = {},
                    ) { Text(GamesRummyLobbyPlan.tabTitle(value, rummy.lobby?.invites?.size ?: 0), style = MaterialTheme.typography.labelLarge, maxLines = 1) }
                }
            }
            when (tab) {
                GamesRummyLobbyTab.people -> {
                    JoinSection(rummy, joinables, myRoom, entry)
                    // 잠긴 빌드는 탁자를 열 수 없다(요청 0건은 스토어도 같은 깃발로 막는다). 방이 잡힌 틈(로비 응답이 먼저 왔다)에도 세우지 않는다.
                    if (!rummy.duelsLocked && myRoom == null) NewTableCard(rummy, joinables.isEmpty(), entry)
                    GamesRummyPeopleSection(rummy, myRoom, RummyExitPolicy.amHost(rummy.match), entry, Modifier.padding(top = AingDimens.space3)) { user ->
                        // 방이 없으면 판돈을 고르는 시트를 먼저 연다(설계서 §5). 방이 있으면 줄이 곧바로 부른다.
                        if (myRoom == null) inviteTarget = user else rummy.inviteQueued(user.id)
                    }
                }
                GamesRummyLobbyTab.ranking -> GamesRummyRankingSection(rummy, myUserID)
            }
        }
    }
    val target = inviteTarget
    if (target != null && myRoom == null) InviteSheet(rummy, target, entry, onDismiss = { inviteTarget = null })
}

/** 머리 줄 오른쪽 규칙 단추(로비·방 공용). */
@Composable
internal fun GamesRummyRulesButton(onRules: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier.size(AingDimens.minimumTarget).clickable(role = Role.Button, onClick = onRules)
            .semantics { contentDescription = RummyPhoneText.rulesTitle },
        contentAlignment = Alignment.Center,
    ) { AingIcon(AppIcon.MenuBook, contentDescription = null, size = 22.dp, tint = AingTheme.colors.accent) }
}

// MARK: 받은 초대 + 공개 방

/** [사람] 탭 맨 위 — 받은 초대가 이 화면에서 가장 급한 사실이다(폰엔 맥의 전역 배너가 없다). 없으면 새 탁자 아래 한 줄이 말한다. */
@Composable
private fun JoinSection(rummy: RummyStore, joinables: List<RummyJoinable>, myRoom: RummyRoom?, entry: GamesRummyEntry) {
    if (joinables.isEmpty()) return
    SectionHeader(RummyLobbyPhoneText.joinHeader, trailing = SectionTrailing.Label(RummyLobbyPhoneText.places(joinables.size)), padded = true)
    InsetGroup {
        joinables.forEachIndexed { index, item -> JoinRow(rummy, item, myRoom, entry, isLast = index == joinables.size - 1) }
    }
}

/**
 * 한 줄: 방장 얼굴 · "OO님이 불렀어요"/"OO님의 공개 탁자" · 판돈 · 자리 · 앉은 사람.
 * 초대는 버튼 둘을 아래 줄에(판돈이 걸린 수락·거절이라 크게), 공개 방은 사람 줄처럼 한 줄에 [앉기](세 칸이 다 큰 버튼이면 첫 화면이 이 절로 찬다). 큰 글자에서는 쌓는다.
 */
@Composable
private fun JoinRow(rummy: RummyStore, item: RummyJoinable, myRoom: RummyRoom?, entry: GamesRummyEntry, isLast: Boolean) {
    val room = item.room
    val hostName = room.host?.displayName ?: "?"
    val canJoin = GamesRummyLobbyPlan.canJoin(item, myRoom, entry)
    val stacked = LocalDensity.current.fontScale >= 1.3f
    val joinButton: @Composable (Modifier, PillKind, PillSize, Boolean) -> Unit = { modifier, kind, size, fills ->
        // 잠긴 빌드는 [거절]만 남긴다.
        if (!entry.duelsLocked) {
            PillButton(
                if (item.isInvite) RummyPhoneText.join else RummyPhoneText.take,
                modifier.testTag(GamesRummyLobbyTags.join(room.id)), kind = kind, size = size, fillsWidth = fills,
                enabled = canJoin,
            ) { rummy.join(room.id) }
        }
    }
    GroupRow(dividerInset = if (isLast) null else AingDimens.cardPadding, isHighlighted = item.isInvite) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
                PersonAvatar(hostName, room.host?.id?.lowercased ?: hostName, 36.dp, url = room.host?.avatarUrl, characterHint = room.host?.character)
                JoinInfo(item, GamesRummyLobbyPlan.joinBlockText(item, myRoom, entry), entry, hostName, Modifier.weight(1f))
                if (!stacked) {
                    JoinedFaces(room)
                    if (!item.isInvite) joinButton(Modifier, PillKind.Tinted, PillSize.Sm, false)
                }
            }
            if (item.isInvite) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    // [거절] 은 판돈이 움직이지 않아 깃발·다른 게임과 무관하다.
                    PillButton(
                        RummyPhoneText.decline, Modifier.weight(1f).testTag(GamesRummyLobbyTags.decline(room.id)), kind = PillKind.Gray, fillsWidth = true,
                        enabled = !entry.isWorking,
                    ) { rummy.decline(room.id) }
                    joinButton(Modifier.weight(1f), PillKind.Filled, PillSize.Md, true)
                }
            } else if (stacked) {
                joinButton(Modifier, PillKind.Tinted, PillSize.Md, true)
            }
        }
    }
}

@Composable
private fun JoinInfo(item: RummyJoinable, blockText: String?, entry: GamesRummyEntry, hostName: String, modifier: Modifier) {
    val colors = AingTheme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            if (item.isInvite) RummyPhoneText.called(hostName) else RummyPhoneText.publicTable(hostName),
            style = rowTitleStyle(), color = colors.label, maxLines = 2, overflow = TextOverflow.Ellipsis,
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            RubyPrice(item.room.stake ?: 0L, isShort = false, art = rememberRubyArt(14f), gemSize = 14.dp, fontSize = 13f)
            Text("· ${GamesRummyLobbyPlan.joinSeatChip(item)}", style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label2, maxLines = 1)
        }
        if (blockText != null && !entry.duelsLocked) Text(blockText, style = rowSubtitleStyle(), color = colors.danger)
    }
}

/** 앉은 사람 얼굴(겹쳐 놓는다). 꾸밈이다 — 인원은 줄 글자가 말한다. */
@Composable
private fun JoinedFaces(room: RummyRoom) {
    Row(horizontalArrangement = Arrangement.spacedBy((-6).dp)) {
        GamesRummyLobbyPlan.joinedSeats(room).take(4).forEach { seat ->
            PersonAvatar(seat.displayName ?: "?", seat.userId.lowercased, 22.dp, url = seat.avatarUrl, characterHint = seat.character)
        }
    }
}

// MARK: 내 전적 · 내 루비

@Composable
private fun Summary(rummy: RummyStore, balance: Long?) {
    val colors = AingTheme.colors
    val mine = rummy.lobby?.me
    InsetGroup(Modifier.padding(top = AingDimens.rowSpacing)) {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
            Column(Modifier.weight(1f).padding(horizontal = AingDimens.cardPadding, vertical = 12.dp).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(RummyPhoneText.recordTitle, style = rowSubtitleStyle(), color = colors.label2)
                Text(RummyPhoneText.record(mine?.games, mine?.wins), style = rowTitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label)
            }
            Box(Modifier.width(AingDimens.hairline).fillMaxHeight().background(colors.separator))
            Column(Modifier.weight(1f).padding(horizontal = AingDimens.cardPadding, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(RummyLobbyPhoneText.myRubyTitle, style = rowSubtitleStyle(), color = colors.label2)
                if (balance != null) {
                    RubyPrice(balance, isShort = false, art = rememberRubyArt(17f), fontSize = 17f)
                } else {
                    Text(RummyLobbyPhoneText.unknownNumber, style = rowTitleStyle(), color = colors.label)
                }
            }
        }
    }
}

// MARK: 새 탁자

@Composable
private fun NewTableCard(rummy: RummyStore, joinIsEmpty: Boolean, entry: GamesRummyEntry) {
    val colors = AingTheme.colors
    val selected = rummy.selectedStake
    SectionHeader(RummyPhoneText.newTable, padded = true)
    InsetGroup {
        Column(Modifier.padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            GamesRummyTableOptions(rummy, entry, tileFill = colors.fill)
            StakeShortLine(selected, entry)
            PillButton(
                RummyPhoneText.openTable, Modifier.testTag(GamesRummyLobbyTags.OPEN_TABLE), kind = PillKind.Filled, icon = AppIcon.Add, fillsWidth = true,
                enabled = entry.canOpenTable(selected),
            ) { rummy.createRoom() }
        }
    }
    // 아직 모르거나 못 받았는데 "없어요" 쪽으로 말하지 않는다.
    if (joinIsEmpty && rummy.lobby != null && !rummy.lobbyLoadFailed) {
        Text(
            RummyPhoneText.joinEmpty, style = rowSubtitleStyle(), color = colors.label2,
            modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space2),
        )
    }
}

/** 고른 판돈이 잔액을 넘으면 왜 막혔는지 · 어떻게 풀리는지 말한다(단추만 흐리면 왜인지 모른다). 잔액을 모르면 막지 않는다. */
@Composable
private fun StakeShortLine(stake: Long, entry: GamesRummyEntry) {
    val balance = entry.balance
    if (balance != null && !entry.affordable(stake)) {
        Text(RummyLobbyPhoneText.stakeShort(stake, balance), style = rowSubtitleStyle(), color = AingTheme.colors.danger)
    }
}

/** 판돈 칸 셋 + 공개 여부 — 로비 새 탁자 카드와 [초대] 시트가 **같은 값**(`selectedStake` · `createPublic`)을 고친다. 값이 코어에 있는 까닭: [한 판 더]도, 방 없이 [초대]도 그 값으로 방을 만든다. */
@Composable
private fun GamesRummyTableOptions(rummy: RummyStore, entry: GamesRummyEntry, tileFill: Color) {
    val colors = AingTheme.colors
    val stakes = rummy.lobby?.stakes?.takeIf { it.isNotEmpty() } ?: GamesRummyLobbyPlan.defaultStakes
    val selected = rummy.selectedStake
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            stakes.forEach { stake ->
                StakeChip(stake, stake == selected, entry.affordable(stake), !entry.isWorking, tileFill, Modifier.weight(1f)) { rummy.selectedStake = stake }
            }
        }
        Text(RummyPhoneText.stakeCaption(selected), style = rowSubtitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label2)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(RummyPhoneText.publicLabel, style = rowTitleStyle(), color = colors.label)
                Text(if (rummy.createPublic) RummyPhoneText.publicOn else RummyPhoneText.publicOff, style = rowSubtitleStyle(), color = colors.label2)
            }
            Switch(
                checked = rummy.createPublic,
                onCheckedChange = { rummy.createPublic = it },
                modifier = Modifier.testTag(GamesRummyLobbyTags.PUBLIC),
                enabled = !entry.isWorking,
            )
        }
    }
}

/** 판돈 칸 하나. **모자란 판돈도 고를 수는 있다**(왜 안 되는지 카드가 말한다) — 막으면 고른 값이 이미 모자란 창에서 빠져나올 말이 없다. */
@Composable
private fun StakeChip(stake: Long, isSelected: Boolean, affordable: Boolean, notBusy: Boolean, fill: Color, modifier: Modifier, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.innerRadius)
    Box(
        modifier.heightIn(min = 48.dp).clip(shape).background(if (isSelected) colors.accentTint else fill, shape)
            .then(if (isSelected) Modifier.border(2.dp, colors.accent, shape) else Modifier)
            .clickable(enabled = notBusy, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = RummyPhoneText.stake(stake)
                stateDescription = if (affordable) "" else RummyPhoneText.insufficient
                selected = isSelected
            }
            .testTag(GamesRummyLobbyTags.stake(stake)),
        contentAlignment = Alignment.Center,
    ) {
        RubyPrice(stake, isShort = !affordable, art = rememberRubyArt(18f), gemSize = 18.dp, fontSize = 17f)
    }
}

/** 방 없이 누른 [초대]의 판돈 시트(폰 체스·테트리스 시트와 같은 모양). 판돈은 **시작할 때** 걷는다 — 여기서 빠지지 않는다. 처음부터 판돈이 골라져 있다: 로비 새 탁자 카드에 늘 보이는 코어의 한 값이다. */
@Composable
private fun InviteSheet(rummy: RummyStore, target: RummyLobbyUser, entry: GamesRummyEntry, onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    val name = target.displayName ?: "?"
    val stake = rummy.selectedStake
    GamesSheet(onDismiss = onDismiss) {
        Column(Modifier.fillMaxWidth().testTag(GamesRummyLobbyTags.INVITE_SHEET)) {
            GamesHeaderBar(RummyLobbyPhoneText.inviteSheetTitle, subtitle = RummyLobbyPhoneText.inviteSheetPrompt(name), onBack = onDismiss, backIcon = AppIcon.Close)
            Column(
                Modifier.fillMaxWidth().weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space2, bottom = AingDimens.space4),
                verticalArrangement = Arrangement.spacedBy(AingDimens.space4),
            ) {
                InsetGroup {
                    GroupRow(dividerInset = null, minHeight = 64.dp) {
                        PersonAvatar(name, target.id.lowercased, 44.dp, working = target.isWorking == true, url = target.avatarUrl, characterHint = target.character)
                        Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                            PersonName(name)
                            Text(RummyPhoneText.createHint, style = rowSubtitleStyle(), color = colors.label2)
                        }
                    }
                }
                Column(Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
                    GamesRummyTableOptions(rummy, entry, tileFill = colors.surface)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(RummyLobbyPhoneText.myRubyTitle, style = rowSubtitleStyle(), color = colors.label2)
                        val balance = entry.balance
                        if (balance != null) {
                            RubyPrice(balance, isShort = false, art = rememberRubyArt(14f), gemSize = 14.dp, fontSize = 13f)
                        } else {
                            Text(RummyLobbyPhoneText.unknownNumber, style = rowSubtitleStyle(), color = colors.label2)
                        }
                    }
                    StakeShortLine(stake, entry)
                }
            }
            PillButton(
                RummyLobbyPhoneText.openAndCall(stake),
                Modifier.padding(horizontal = AingDimens.sideMargin).padding(bottom = AingDimens.space3).testTag(GamesRummyLobbyTags.OPEN_AND_CALL),
                kind = PillKind.Filled, size = PillSize.Lg, fillsWidth = true,
                enabled = entry.canOpenTable(stake) && rummy.match == null,
            ) {
                onDismiss()
                rummy.inviteQueued(target.id)
            }
        }
    }
}

// MARK: 사람 (로비 · 방 공용)

/** 사람 절: 초대 가능 → 바쁜 사람(흐리게) → '업데이트가 필요한 사람 N명' 접기. 서버 순서를 지킨다. 로비 [사람] 탭과 방(방장)이 함께 쓴다. [onInvite] 는 부르는 쪽이 정한다(방 없는 로비는 시트, 방은 곧바로). */
@Composable
internal fun GamesRummyPeopleSection(rummy: RummyStore, room: RummyRoom?, amHost: Boolean, entry: GamesRummyEntry, modifier: Modifier = Modifier, onInvite: (RummyLobbyUser) -> Unit) {
    val colors = AingTheme.colors
    val lobby = rummy.lobby
    val users = lobby?.users ?: emptyList()
    val people = GamesRummyLobbyPlan.people(users)
    var expanded by remember { mutableStateOf(false) }
    val calling = rummy.callingPeerIDs
    val rows: @Composable (List<RummyLobbyUser>, Boolean) -> Unit = { list, dimmed ->
        list.forEachIndexed { index, user ->
            PersonRow(
                user, GamesRummyLobbyPlan.personAction(user, room, amHost, calling, entry),
                onInvite = { onInvite(user) }, dimmed = dimmed, isLast = index == list.size - 1,
            )
        }
    }
    Column(modifier) {
        Text(
            RummyPhoneText.peopleCaption(inRoom = room != null, amHost = amHost), style = rowSubtitleStyle(), color = colors.label2,
            modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin),
        )
        if (users.isEmpty()) {
            InsetGroup(Modifier.padding(top = AingDimens.space2)) {
                GroupRow(dividerInset = null) {
                    when {
                        lobby != null -> Text(RummyPhoneText.emptyUsers, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                        // 영영 도는 표시로 숨기지 않는다.
                        rummy.lobbyLoadFailed -> LoadFailureRow(RummyLobbyPhoneText.usersLoadFailed, Modifier.weight(1f)) { rummy.reloadLobby() }
                        else -> LoadingRow(RummyPhoneText.loadingUsers)
                    }
                }
            }
        } else {
            if (people.ready.isNotEmpty()) {
                SectionHeader(
                    if (room == null) RummyPhoneText.readyHeader else RummyPhoneText.peopleHeader,
                    trailing = SectionTrailing.Label(RummyLobbyPhoneText.people(people.ready.size)), padded = true,
                )
                InsetGroup { rows(people.ready, false) }
            }
            if (people.busy.isNotEmpty()) {
                SectionHeader(RummyPhoneText.busyHeader, trailing = SectionTrailing.Label(RummyLobbyPhoneText.people(people.busy.size)), padded = true)
                InsetGroup { rows(people.busy, true) }
            }
            if (people.outdated.isNotEmpty()) {
                InsetGroup(Modifier.padding(top = AingDimens.space4)) {
                    OutdatedFold(people.outdated.size, expanded) { expanded = !expanded }
                    if (expanded) rows(people.outdated, true)
                }
            }
        }
    }
}

/** '업데이트가 필요한 사람 N명' 접힌 줄. 눌러야 펼친다. */
@Composable
private fun OutdatedFold(count: Int, expanded: Boolean, onToggle: () -> Unit) {
    val colors = AingTheme.colors
    GroupRow(
        Modifier.clickable(role = Role.Button, onClick = onToggle).testTag(GamesRummyLobbyTags.OUTDATED_FOLD),
        dividerInset = if (expanded) AingDimens.cardPadding else null,
    ) {
        AingIcon(AppIcon.ArrowCircleUp, contentDescription = null, size = 20.dp, tint = colors.pending)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(RummyPhoneText.outdatedFold(count, expanded), style = rowTitleStyle(), color = colors.label)
            Text(RummyPhoneText.outdatedHint, style = rowSubtitleStyle(), color = colors.label2)
        }
        AingIcon(if (expanded) AppIcon.ExpandLess else AppIcon.ExpandMore, contentDescription = null, size = 18.dp, tint = colors.label3Text)
    }
}

/** 사람 한 줄: 얼굴(근무 중 점) · 이름 · 상태 · 오른쪽 [초대] 또는 '부르는 중'·'초대함'·'참가함'. 큰 글자에서는 단추를 글 아래로 내린다. */
@Composable
private fun PersonRow(user: RummyLobbyUser, action: GamesRummyPersonAction, onInvite: () -> Unit, dimmed: Boolean, isLast: Boolean) {
    val colors = AingTheme.colors
    val name = user.displayName ?: "?"
    val status = GamesRummyLobbyPlan.status(user)
    val stacked = LocalDensity.current.fontScale >= 1.3f
    val face: @Composable () -> Unit = {
        PersonAvatar(name, user.id.lowercased, 36.dp, working = user.isWorking == true, url = user.avatarUrl, characterHint = user.character)
    }
    val info: @Composable (Modifier) -> Unit = { m ->
        Column(m.semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            PersonName(name)
            Text(status.text, style = rowSubtitleStyle(), color = if (status == GamesRummyPersonStatus.outdated) colors.pending else colors.label2, maxLines = 1)
        }
    }
    val trailing: @Composable () -> Unit = {
        when (action) {
            GamesRummyPersonAction.Hidden -> Unit
            is GamesRummyPersonAction.Invite -> PillButton(
                RummyPhoneText.invite, Modifier.testTag(GamesRummyLobbyTags.invite(user.id)), kind = PillKind.Tinted, size = PillSize.Sm, icon = AppIcon.SendFill,
                enabled = action.enabled, onClick = onInvite,
            )
            is GamesRummyPersonAction.Tag -> AingChip(action.text, tint = colors.working)
        }
    }
    GroupRow(
        modifier = Modifier.alpha(if (dimmed) 0.55f else 1f).testTag(GamesRummyLobbyTags.person(user.id)),
        dividerInset = if (isLast) null else AingDimens.cardPadding + 36.dp + AingDimens.space3,
        minHeight = 56.dp,
    ) {
        if (stacked) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space3), verticalAlignment = Alignment.CenterVertically) {
                    face()
                    info(Modifier.weight(1f))
                }
                trailing()
            }
        } else {
            face()
            info(Modifier.weight(1f))
            trailing()
        }
    }
}
