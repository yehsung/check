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
import com.yehsung.aingcheck.ui.games.minigame.kit.InlineNotice
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.LoadingRow
import com.yehsung.aingcheck.ui.games.minigame.kit.NoticeKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonName
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
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
            JoinSection(rummy, joinables, myRoom, entry)
            Summary(rummy, balance)
            GamesRummyLobbyPlan.storeNotice(rummy.notice, warnings)?.let { InlineNotice(it, Modifier.padding(top = AingDimens.rowSpacing), NoticeKind.Info) }
            warnings.forEach { InlineNotice(it, Modifier.padding(top = AingDimens.rowSpacing), NoticeKind.Warning) }
            // 잠긴 빌드는 탁자를 열 수 없다(요청 0건은 스토어도 같은 깃발로 막는다). 방이 잡힌 틈(로비 응답이 먼저 왔다)에도 세우지 않는다.
            if (!rummy.duelsLocked && myRoom == null) NewTableCard(rummy, myUserID, me, entry)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(top = AingDimens.rowSpacing)) {
                GamesRummyLobbyTab.entries.forEachIndexed { index, value ->
                    SegmentedButton(
                        selected = tab == value,
                        onClick = { tab = value },
                        shape = SegmentedButtonDefaults.itemShape(index, GamesRummyLobbyTab.entries.size),
                        modifier = Modifier.testTag(GamesRummyLobbyTags.tab(value)),
                        icon = {},
                    ) { Text(value.title, style = MaterialTheme.typography.labelLarge) }
                }
            }
            when (tab) {
                GamesRummyLobbyTab.people -> GamesRummyPeopleSection(rummy, myRoom, RummyExitPolicy.amHost(rummy.match), entry, Modifier.padding(top = AingDimens.rowSpacing))
                GamesRummyLobbyTab.ranking -> GamesRummyRankingSection(rummy, myUserID)
            }
        }
    }
}

/** 머리 줄 오른쪽 규칙 단추(로비·방 공용). */
@Composable
internal fun GamesRummyRulesButton(onRules: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier.heightIn(min = AingDimens.minimumTarget).clickable(role = Role.Button, onClick = onRules)
            .semantics { contentDescription = RummyPhoneText.rulesTitle },
        contentAlignment = Alignment.Center,
    ) { AingIcon(AppIcon.MenuBook, contentDescription = null, size = 22.dp, tint = AingTheme.colors.accent) }
}

// MARK: 받은 초대 + 공개 방

@Composable
private fun JoinSection(rummy: RummyStore, joinables: List<RummyJoinable>, myRoom: RummyRoom?, entry: GamesRummyEntry) {
    val colors = AingTheme.colors
    if (joinables.isEmpty()) {
        // 잠긴 빌드는 앉을 수 없으니 "생기면 여기에 떠요" 도 말하지 않는다.
        if (rummy.duelsLocked) return
        Text(
            RummyPhoneText.joinEmpty, style = rowSubtitleStyle(), color = colors.label2,
            modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space2),
        )
        return
    }
    SectionHeader(GamesRummyLobbyPlan.joinTitle(joinables), padded = true)
    InsetGroup {
        joinables.forEachIndexed { index, item -> JoinRow(rummy, item, myRoom, entry, isLast = index == joinables.size - 1) }
    }
}

/** 카드 한 장: 방장 얼굴 · "OO님이 불렀어요"/"OO님의 공개 탁자" · 판돈 · 자리 · 앉은 사람 · [거절][참가] 또는 [앉기]. */
@Composable
private fun JoinRow(rummy: RummyStore, item: RummyJoinable, myRoom: RummyRoom?, entry: GamesRummyEntry, isLast: Boolean) {
    val colors = AingTheme.colors
    val room = item.room
    val hostName = room.host?.displayName ?: "?"
    val shortOfRuby = !entry.affordable(room.stake)
    val canJoin = GamesRummyLobbyPlan.canJoin(item, myRoom, entry)
    GroupRow(dividerInset = if (isLast) null else AingDimens.cardPadding, isHighlighted = item.isInvite) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
                PersonAvatar(hostName, room.host?.id?.lowercased ?: hostName, 36.dp, url = room.host?.avatarUrl, characterHint = room.host?.character)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        if (item.isInvite) RummyPhoneText.called(hostName) else RummyPhoneText.publicTable(hostName),
                        style = rowTitleStyle(), color = colors.label, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        AingChip(RummyPhoneText.stake(room.stake), tint = colors.pending)
                        AingChip(GamesRummyLobbyPlan.joinSeatChip(item), tint = if (item.isInvite) colors.label2 else colors.working)
                        JoinedFaces(room)
                    }
                }
            }
            if (shortOfRuby && !entry.duelsLocked) Text(RummyPhoneText.insufficient, style = rowSubtitleStyle(), color = colors.danger)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (item.isInvite) {
                    // [거절] 은 판돈이 움직이지 않아 깃발·다른 게임과 무관하다.
                    PillButton(
                        RummyPhoneText.decline, Modifier.weight(1f).testTag(GamesRummyLobbyTags.decline(room.id)), kind = PillKind.Gray, size = PillSize.Sm, fillsWidth = true,
                        enabled = !entry.isWorking,
                    ) { rummy.decline(room.id) }
                }
                if (!entry.duelsLocked) {
                    PillButton(
                        if (item.isInvite) RummyPhoneText.join else RummyPhoneText.take,
                        Modifier.weight(1f).testTag(GamesRummyLobbyTags.join(room.id)), kind = PillKind.Tinted, size = PillSize.Sm, fillsWidth = true,
                        enabled = canJoin,
                    ) { rummy.join(room.id) }
                }
            }
        }
    }
}

/** 앉은 사람 얼굴(겹쳐 놓는다). */
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
private fun NewTableCard(rummy: RummyStore, myUserID: String?, me: RummySeatFace, entry: GamesRummyEntry) {
    val colors = AingTheme.colors
    val stakes = rummy.lobby?.stakes ?: GamesRummyLobbyPlan.defaultStakes
    val selected = rummy.selectedStake
    InsetGroup(Modifier.padding(top = AingDimens.rowSpacing)) {
        Column(Modifier.padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
                PersonAvatar(me.name, myUserID ?: me.name, 36.dp, url = me.avatarUrl, characterHint = me.characterId)
                Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(RummyPhoneText.newTable, style = rowTitleStyle(), color = colors.label)
                    Text(RummyPhoneText.newTableHint, style = rowSubtitleStyle(), color = colors.label2)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                stakes.forEach { stake ->
                    StakeChip(stake, stake == selected, entry.affordable(stake), !entry.isWorking, Modifier.weight(1f)) { rummy.selectedStake = stake }
                }
            }
            Text(RummyPhoneText.stakeCaption(selected), style = rowSubtitleStyle().copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM), color = colors.label2)
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
            Text(RummyPhoneText.createHint, style = rowSubtitleStyle(), color = colors.label2)
            // 못 여는 까닭을 단추 위에 세운다(단추만 흐리면 왜인지 모른다). 잔액을 모르면 막지 않는다.
            if (!entry.affordable(selected)) Text(RummyPhoneText.insufficient, style = rowSubtitleStyle(), color = colors.danger)
            PillButton(
                RummyPhoneText.openTable, Modifier.testTag(GamesRummyLobbyTags.OPEN_TABLE), kind = PillKind.Filled, icon = AppIcon.Add, fillsWidth = true,
                enabled = entry.canOpenTable(selected),
            ) { rummy.createRoom() }
        }
    }
}

/** 판돈 칸 하나 — 고르기만 한다. 모자라면 흐린 가격 + 비활성. */
@Composable
private fun StakeChip(stake: Long, isSelected: Boolean, affordable: Boolean, notBusy: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(AingDimens.tileRadius)
    Box(
        modifier.heightIn(min = AingDimens.minimumTarget + 4.dp).clip(shape).background(if (isSelected) colors.accentTint else colors.fill, shape)
            .then(if (isSelected) Modifier.border(2.dp, colors.accent, shape) else Modifier)
            .clickable(enabled = affordable && notBusy, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = RummyPhoneText.stake(stake)
                stateDescription = if (affordable) "" else RummyPhoneText.insufficient
                selected = isSelected
            }
            .testTag(GamesRummyLobbyTags.stake(stake)),
        contentAlignment = Alignment.Center,
    ) {
        RubyPrice(stake, isShort = !affordable, art = rememberRubyArt(17f), gemSize = 17.dp, fontSize = 17f)
    }
}

// MARK: 사람 (로비 · 방 공용)

/** 사람 탭: 초대 가능 → 바쁜 사람(흐리게) → '업데이트가 필요한 사람 N명' 접기. 서버 순서를 지킨다. 방 화면도 초대 줄로 같은 절을 쓴다. */
@Composable
internal fun GamesRummyPeopleSection(rummy: RummyStore, room: RummyRoom?, amHost: Boolean, entry: GamesRummyEntry, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val lobby = rummy.lobby
    val users = lobby?.users ?: emptyList()
    val people = GamesRummyLobbyPlan.people(users)
    var expanded by remember { mutableStateOf(false) }
    val calling = rummy.callingPeerIDs
    val stake = rummy.selectedStake
    val rows: @Composable (List<RummyLobbyUser>, Boolean) -> Unit = { list, dimmed ->
        InsetGroup {
            list.forEachIndexed { index, user ->
                PersonRow(
                    user, GamesRummyLobbyPlan.personAction(user, room, amHost, calling, entry, stake),
                    onInvite = { rummy.inviteQueued(user.id) }, dimmed = dimmed, isLast = index == list.size - 1,
                )
            }
        }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        Text(
            RummyPhoneText.peopleCaption(inRoom = room != null, amHost = amHost), style = rowSubtitleStyle(), color = colors.label2,
            modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin),
        )
        if (users.isEmpty()) {
            InsetGroup {
                GroupRow(dividerInset = null) {
                    if (lobby == null) {
                        LoadingRow(RummyPhoneText.loadingUsers)
                    } else {
                        Text(RummyPhoneText.emptyUsers, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                    }
                }
            }
        } else {
            if (people.ready.isNotEmpty()) {
                PeopleHeader(RummyLobbyPhoneText.sectionCount(RummyPhoneText.readyHeader, people.ready.size), colors.working)
                rows(people.ready, false)
            }
            if (people.busy.isNotEmpty()) {
                PeopleHeader(RummyLobbyPhoneText.sectionCount(RummyPhoneText.busyHeader, people.busy.size), colors.label2)
                rows(people.busy, true)
            }
            if (people.outdated.isNotEmpty()) {
                OutdatedFold(people.outdated.size, expanded) { expanded = !expanded }
                if (expanded) rows(people.outdated, true)
            }
        }
    }
}

@Composable
private fun PeopleHeader(title: String, tint: Color) {
    Row(
        Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(6.dp).background(tint, CircleShape))
        Text(title, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = tint)
    }
}

/** '업데이트가 필요한 사람 N명' 접힌 줄. 눌러야 펼친다. */
@Composable
private fun OutdatedFold(count: Int, expanded: Boolean, onToggle: () -> Unit) {
    val colors = AingTheme.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = AingDimens.minimumTarget).clip(RoundedCornerShape(AingDimens.innerRadius)).background(colors.pendingTint)
            .clickable(role = Role.Button, onClick = onToggle).padding(horizontal = 12.dp, vertical = 8.dp).testTag(GamesRummyLobbyTags.OUTDATED_FOLD),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        AingIcon(AppIcon.ArrowCircleUp, contentDescription = null, size = 16.dp, tint = colors.pending)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(RummyPhoneText.outdatedFold(count, expanded), style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.pending)
            Text(RummyPhoneText.outdatedHint, style = MaterialTheme.typography.labelSmall, color = colors.label2)
        }
        AingIcon(if (expanded) AppIcon.ExpandLess else AppIcon.ExpandMore, contentDescription = null, size = 18.dp, tint = colors.pending)
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
            Text(status.text, style = rowSubtitleStyle(), color = statusTint(status), maxLines = 1)
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

@Composable
private fun statusTint(status: GamesRummyPersonStatus): Color {
    val colors = AingTheme.colors
    return when (status) {
        GamesRummyPersonStatus.outdated -> colors.pending
        GamesRummyPersonStatus.inMatch -> colors.accent
        GamesRummyPersonStatus.focus -> colors.aiToken
        GamesRummyPersonStatus.working -> colors.working
        GamesRummyPersonStatus.resting -> colors.label2
    }
}
