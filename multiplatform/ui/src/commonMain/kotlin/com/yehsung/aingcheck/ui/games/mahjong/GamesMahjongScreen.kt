// 원본: Sources/CheckMobileKit/Games/GamesMahjongScreen.swift @ 928d5562(폰 1.0.18 — 로비(세로) · 판(가로) 한 입구) — Android 판 8
//
// 입구 하나: 판(루비 판 · 연습판 — 가로, GamesMahjongTableView) 또는 로비(세로). 고르기는 GamesMahjongScreenRule 한 곳.
// 로비 = 머리(전적 · [혼자 연습] · [규칙]) · 내 방(자리 넷 · [시작] · [나가기]) 또는 [방 만들기] · 받은 초대 · 공개 방 · 사람([초대]) · 순위.
// 상태 · 판정은 전부 코어 MahjongStore 다. 이 파일은 그리기와 누름만 한다. 수명은 GamesStore.mahjongScreenDidAppear/Disappear.
// Android 판돈 깃발(G §8-17 #1): 꺼진 빌드는 [방 만들기] · [참가] · [초대] · [시작]을 그리지 않는다(스토어도 막는다). 연습 · 규칙 · 순위는 연다.
package com.yehsung.aingcheck.ui.games.mahjong

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.rules.mahjong.MahjongFormat
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileFace
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileSize
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTiles
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongPhoneText
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongRulesText
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongScoreCell
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongScreenRule
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongText
import com.yehsung.aingcheck.core.stores.mahjong.MahjongAvailability
import com.yehsung.aingcheck.core.stores.mahjong.MahjongLobbyUser
import com.yehsung.aingcheck.core.stores.mahjong.MahjongMatchStatus
import com.yehsung.aingcheck.core.stores.mahjong.MahjongNoticeText
import com.yehsung.aingcheck.core.stores.mahjong.MahjongPhase
import com.yehsung.aingcheck.core.stores.mahjong.MahjongRoom
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStake
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStateMatch
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStore
import com.yehsung.aingcheck.core.stores.mahjong.createRoom
import com.yehsung.aingcheck.core.stores.mahjong.decline
import com.yehsung.aingcheck.core.stores.mahjong.handleSignal
import com.yehsung.aingcheck.core.stores.mahjong.invite
import com.yehsung.aingcheck.core.stores.mahjong.join
import com.yehsung.aingcheck.core.stores.mahjong.leaveRoom
import com.yehsung.aingcheck.core.stores.mahjong.loadRanking
import com.yehsung.aingcheck.core.stores.mahjong.showPractice
import com.yehsung.aingcheck.core.stores.mahjong.start
import com.yehsung.aingcheck.core.stores.mahjong.startPractice
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesSheet
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.InlineNotice
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.NoticeKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonName
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.StakeLine
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

object MahjongLobbyTags {
    const val LOBBY = "mahjong.lobby"
    const val PRACTICE = "mahjong.practiceButton"
    const val RULES = "mahjong.rulesButton"
    const val CREATE = "mahjong.createButton"
    const val CREATE_SEND = "mahjong.create.send"
    const val PRACTICE_START = "mahjong.practice.start"
    const val START = "mahjong.room.start"
    const val LEAVE = "mahjong.room.leave"
    fun invite(userID: String) = "mahjong.invite.$userID"
    fun join(roomID: String) = "mahjong.join.$roomID"
    fun decline(roomID: String) = "mahjong.decline.$roomID"
}

private enum class MahjongSheet { createRoom, practice, rules }

@Composable
fun GamesMahjongScreen(
    store: GamesStore,
    mahjong: MahjongStore,
    myName: String?,
    myCharacter: String?,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
) {
    DisposableEffect(store) {
        store.mahjongScreenDidAppear()
        onDispose { store.mahjongScreenDidDisappear() }
    }
    var sheet by remember { mutableStateOf<MahjongSheet?>(null) }
    LaunchedEffect(mahjong.phase) {
        if (mahjong.phase == MahjongPhase.playing && (sheet == MahjongSheet.createRoom || sheet == MahjongSheet.practice)) sheet = null
    }
    val colors = AingTheme.colors
    when (GamesMahjongScreenRule.of(mahjong, store.mahjongDismissedMatchID)) {
        GamesMahjongScreenRule.table -> GamesMahjongTableView(
            store, mahjong, myName, myCharacter, onRules = { sheet = MahjongSheet.rules },
            onLeaveTable = { onBack?.invoke() }, modifier = modifier,
        )
        GamesMahjongScreenRule.lobby -> Column(modifier.fillMaxSize().background(colors.background)) {
            GamesHeaderBar(GamesMahjongText.title, onBack = onBack)
            Lobby(store, mahjong, onCreate = { sheet = MahjongSheet.createRoom }, onPractice = { sheet = MahjongSheet.practice }, onRules = { sheet = MahjongSheet.rules })
        }
        GamesMahjongScreenRule.unavailable -> Column(modifier.fillMaxSize().background(colors.background)) {
            GamesHeaderBar(GamesMahjongText.title, onBack = onBack)
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    if (mahjong.availability == MahjongAvailability.updateRequired) GamesMahjongText.updateRequired else GamesMahjongText.unavailable,
                    style = MaterialTheme.typography.titleMedium, color = colors.label,
                )
            }
        }
    }
    when (sheet) {
        MahjongSheet.createRoom -> CreateRoomSheet(store, mahjong) { sheet = null }
        MahjongSheet.practice -> PracticeSheet(mahjong) { sheet = null }
        MahjongSheet.rules -> RulesSheet { sheet = null }
        null -> Unit
    }
}

@Composable
private fun Lobby(store: GamesStore, mahjong: MahjongStore, onCreate: () -> Unit, onPractice: () -> Unit, onRules: () -> Unit) {
    val colors = AingTheme.colors
    val blockedBy = store.mahjongEntryBlock
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin)
            .padding(top = AingDimens.space2, bottom = AingDimens.space6).testTag(MahjongLobbyTags.LOBBY),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        Text(GamesMahjongText.subtitle, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin))
        mahjong.notice?.let { InlineNotice(it, kind = NoticeKind.Info) }
        GamesBusyText.entryBlockNotice(blockedBy, GamesBusyGame.mahjong)?.let { InlineNotice(it, kind = NoticeKind.Warning) }
        Header(mahjong, onPractice, onRules)
        SectionHeader(GamesMahjongPhoneText.roomTitle, padded = true)
        InsetGroup { RoomCard(store, mahjong, blockedBy, onCreate, onPractice) }
        val invites = mahjong.visibleInvites
        if (invites.isNotEmpty()) {
            SectionHeader(GamesMahjongText.invitesTitle, padded = true)
            invites.forEach { room -> InsetGroup { JoinCard(store, mahjong, room, invited = true, blockedBy = blockedBy) } }
        }
        val rooms = mahjong.publicRooms.filter { room -> invites.none { it.id == room.id } }
        if (rooms.isNotEmpty()) {
            SectionHeader(GamesMahjongText.publicRoomsTitle, padded = true)
            rooms.forEach { room -> InsetGroup { JoinCard(store, mahjong, room, invited = false, blockedBy = blockedBy) } }
        }
        SectionHeader(GamesMahjongText.usersTab, padded = true)
        InsetGroup { Users(store, mahjong, onCreate) }
        Ranking(mahjong)
    }
}

/** 전적 한 줄 · [혼자 연습] · [규칙]. */
@Composable
private fun Header(mahjong: MahjongStore, onPractice: () -> Unit, onRules: () -> Unit) {
    val colors = AingTheme.colors
    InsetGroup {
        Column(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(GamesMahjongText.record(mahjong.record?.avgRank, mahjong.record?.games ?: 0), style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = TNUM), color = colors.label)
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PillButton(
                    if (mahjong.practice != null) GamesMahjongText.practiceViewButton else GamesMahjongText.practice,
                    Modifier.weight(1f).testTag(MahjongLobbyTags.PRACTICE), kind = PillKind.Tinted, fillsWidth = true,
                ) { if (mahjong.practice != null) mahjong.showPractice() else onPractice() }
                PillButton(GamesMahjongText.rules, Modifier.weight(1f).testTag(MahjongLobbyTags.RULES), kind = PillKind.Gray, fillsWidth = true, onClick = onRules)
            }
            Text(GamesMahjongPhoneText.practiceHelp, style = MaterialTheme.typography.labelSmall, color = colors.label3)
        }
    }
}

private data class Chair(val id: String, val name: String, val avatarURL: String?, val character: String?, val tag: String, val joined: Boolean)

/** 내 방(앉은 forming 방 — 판 state 가 먼저, 없으면 로비 me.room) 또는 [방 만들기]. */
@Composable
private fun RoomCard(store: GamesStore, mahjong: MahjongStore, blockedBy: GamesBusyGame?, onCreate: () -> Unit, onPractice: () -> Unit) {
    val colors = AingTheme.colors
    val forming = mahjong.match?.match?.takeIf { it.matchStatus == MahjongMatchStatus.forming }
    if (forming == null && mahjong.lobbyRoom == null) {
        Column(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(GamesMahjongPhoneText.roomEmpty, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            if (mahjong.duelsEnabled) {
                PillButton(
                    GamesMahjongText.createTitle, Modifier.testTag(MahjongLobbyTags.CREATE), kind = PillKind.Filled, icon = AppIcon.Add, fillsWidth = true,
                    enabled = !mahjong.isWorking && blockedBy == null && mahjong.availability == MahjongAvailability.available, onClick = onCreate,
                )
            }
        }
        return
    }
    val lobbyRoom = mahjong.lobbyRoom
    val stake = forming?.stake ?: lobbyRoom?.stake ?: 0
    val format = forming?.formatKind ?: lobbyRoom?.formatKind
    val isPublic = forming?.isPublic ?: lobbyRoom?.isPublic ?: false
    val chairs = chairs(mahjong, forming)
    val joined = chairs.count { it.joined }
    val expiresMs = forming?.roomExpiresMs ?: lobbyRoom?.expiresAtMs
    Column(Modifier.fillMaxWidth().padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            GamesMahjongChip(GamesMahjongText.format(format), colors.accent)
            GamesMahjongChip(if (isPublic) GamesMahjongText.publicOn else GamesMahjongText.publicOff, colors.label2)
            GamesMahjongChip(GamesMahjongText.seats(joined), if (joined == 4) colors.working else colors.label2)
            Spacer(Modifier.weight(1f))
            if (expiresMs != null) {
                rememberTick(1000)
                val left = ((expiresMs / 1_000 + mahjong.serverClockOffset) - mahjong.clock().timeIntervalSince1970).toInt()
                Text("남은 ${GamesMahjongText.remaining(maxOf(0, left))}", style = TextStyle(fontSize = 12.sp, fontFeatureSettings = TNUM), color = colors.label2)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            StakeLine(stake, prefix = GamesMahjongText.stakeLabel)
            Text(" · " + GamesMahjongText.split(stake), style = rowSubtitleStyle(), color = colors.label2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Column {
            for (index in 0 until 4) {
                val chair = chairs.getOrNull(index)
                Row(Modifier.fillMaxWidth().height(40.dp).alpha(if (chair == null || chair.joined) 1f else 0.6f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (chair != null) {
                        PersonAvatar(chair.name, chair.id, 30.dp, url = chair.avatarURL, characterHint = chair.character)
                        PersonName(chair.name, Modifier.weight(1f))
                        Text(chair.tag, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = if (chair.joined) colors.working else colors.label2)
                    } else {
                        Box(Modifier.size(30.dp).clip(CircleShape).border(1.dp, colors.label3, CircleShape))
                        Text(GamesMahjongText.emptySeat, style = MaterialTheme.typography.bodyMedium, color = colors.label3)
                    }
                }
            }
        }
        Text(
            if (joined == 4) (if (mahjong.isHost) MahjongNoticeText.fourGathered else GamesMahjongText.waitingHost) else GamesMahjongText.needFour,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = if (joined == 4) colors.working else colors.label,
        )
        Text(GamesMahjongText.unseenDrop, style = MaterialTheme.typography.labelSmall, color = colors.label2)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (mahjong.isHost && mahjong.duelsEnabled) {
                PillButton(
                    GamesMahjongText.start, Modifier.weight(1f).testTag(MahjongLobbyTags.START), kind = PillKind.Filled, fillsWidth = true,
                    enabled = mahjong.canStart && !mahjong.isWorking && blockedBy == null,
                ) { mahjong.scope.launch { mahjong.start() } }
            }
            PillButton(
                if (mahjong.practice != null) GamesMahjongText.practiceViewButton else GamesMahjongText.practice, Modifier.weight(1f), kind = PillKind.Tinted, fillsWidth = true,
            ) { if (mahjong.practice != null) mahjong.showPractice() else onPractice() }
            PillButton(GamesMahjongText.leave, Modifier.weight(1f).testTag(MahjongLobbyTags.LEAVE), kind = PillKind.Destructive, fillsWidth = true, enabled = !mahjong.isWorking) {
                mahjong.scope.launch { mahjong.leaveRoom() }
            }
        }
    }
}

private fun chairs(mahjong: MahjongStore, forming: MahjongStateMatch?): List<Chair> {
    val list = mutableListOf<Chair>()
    val members = mahjong.match?.members
    val lobbyRoom = mahjong.lobbyRoom
    if (forming != null && members != null) {
        members.forEachIndexed { index, member ->
            if (member.state != "joined" && member.state != "invited") return@forEachIndexed
            list += Chair(
                member.user?.id ?: "member-$index", member.user?.displayName ?: "?", member.user?.avatarUrl, member.user?.character,
                if (member.isHost == true) GamesMahjongText.hostTag else if (member.state == "joined") GamesMahjongText.joinedTag else GamesMahjongText.invitedTag,
                member.state == "joined",
            )
        }
    } else if (lobbyRoom != null) {
        (lobbyRoom.seats ?: emptyList()).forEachIndexed { index, seat ->
            val isHost = seat.user?.id?.lowercase() != null && seat.user?.id?.lowercase() == lobbyRoom.host?.id?.lowercase()
            list += Chair(
                seat.user?.id ?: "seat-$index", seat.user?.displayName ?: "?", seat.user?.avatarUrl, seat.user?.character,
                if (isHost) GamesMahjongText.hostTag else if (seat.isJoined) GamesMahjongText.joinedTag else GamesMahjongText.invitedTag, seat.isJoined,
            )
        }
    }
    return list.filter { it.joined } + list.filter { !it.joined }
}

/** 받은 초대 · 공개 방. */
@Composable
private fun JoinCard(store: GamesStore, mahjong: MahjongStore, room: MahjongRoom, invited: Boolean, blockedBy: GamesBusyGame?) {
    val colors = AingTheme.colors
    val name = room.host?.displayName ?: "?"
    val balance = store.rubyBalance ?: mahjong.rubyBalance?.toLong()
    val short = room.stake?.let { need -> balance?.let { it < need } ?: false } ?: false
    Column(Modifier.padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            PersonAvatar(name, room.host?.id ?: room.id.lowercased, 40.dp, url = room.host?.avatarUrl, characterHint = room.host?.character)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                PersonName(if (invited) GamesMahjongText.inviteFrom(name) else GamesMahjongText.roomOf(name))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    GamesMahjongChip(GamesMahjongText.format(room.formatKind), colors.accent)
                    GamesMahjongChip(GamesMahjongText.seats(room.joinedCount), colors.label2)
                    room.stake?.let { StakeLine(it, prefix = GamesMahjongText.stakeLabel) }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (invited) {
                PillButton(GamesMahjongText.decline, Modifier.weight(1f).testTag(MahjongLobbyTags.decline(room.id.lowercased)), kind = PillKind.Gray, fillsWidth = true, enabled = !mahjong.isWorking) {
                    mahjong.scope.launch { mahjong.decline(room.id) }
                }
            }
            if (mahjong.duelsEnabled) {
                PillButton(
                    GamesMahjongText.join, Modifier.weight(1f).testTag(MahjongLobbyTags.join(room.id.lowercased)), kind = PillKind.Filled, fillsWidth = true,
                    enabled = !mahjong.isWorking && blockedBy == null && !short && !store.hasLiveMahjongSeat,
                ) { mahjong.scope.launch { mahjong.join(room.id) } }
            }
        }
        if (short) Text(SharedText.shortfallNotice(room.stake?.toLong(), store.rubyBalance), style = MaterialTheme.typography.labelSmall, color = colors.label2)
    }
}

@Composable
private fun Users(store: GamesStore, mahjong: MahjongStore, onCreate: () -> Unit) {
    val colors = AingTheme.colors
    val users = mahjong.visibleUsers
    if (users.isEmpty()) {
        GroupRow(dividerInset = null) {
            Text(if (mahjong.users.isEmpty() && mahjong.record == null) GamesMahjongText.loadingUsers else GamesMahjongText.emptyUsers, style = MaterialTheme.typography.bodySmall, color = colors.label2)
        }
        return
    }
    users.forEachIndexed { offset, user -> UserRow(store, mahjong, user, offset == users.size - 1, onCreate) }
}

@Composable
private fun UserRow(store: GamesStore, mahjong: MahjongStore, user: MahjongLobbyUser, isLast: Boolean, onCreate: () -> Unit) {
    val colors = AingTheme.colors
    val locked = user.inMatch == true || user.capable == false || user.focusMode == true
    val id = user.id.lowercased
    val isMember = (mahjong.match?.members?.any { it.user?.id?.lowercase() == id } ?: false) ||
        (mahjong.lobbyRoom?.seats?.any { it.user?.id?.lowercase() == id } ?: false)
    val balance = store.rubyBalance ?: mahjong.rubyBalance?.toLong()
    val short = balance?.let { it < mahjong.selectedStake.rawValue } ?: false
    val inRoom = mahjong.match?.match?.matchStatus == MahjongMatchStatus.forming || mahjong.lobbyRoom != null
    GroupRow(dividerInset = if (isLast) null else AingDimens.cardPadding + 36.dp + AingDimens.space3, minHeight = 56.dp) {
        PersonAvatar(user.displayName ?: "?", id, 36.dp, working = user.isWorking == true, url = user.avatarUrl, characterHint = user.character)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            PersonName(user.displayName ?: "?")
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (user.inMatch == true) GamesMahjongChip(GamesMahjongText.inMatchChip, colors.pending)
                if (user.capable == false) GamesMahjongChip(GamesMahjongText.outdatedChip, colors.danger)
                if (user.focusMode == true) GamesMahjongChip(GamesMahjongText.focusChip, colors.label2)
                if (user.isWorking == true && !locked) GamesMahjongChip(GamesMahjongText.workingChip, colors.working)
            }
        }
        if (isMember) {
            GamesMahjongChip(GamesMahjongText.invited, colors.label2)
        } else if (mahjong.duelsEnabled) {
            val enabled = !locked && !short && !mahjong.isWorking && !(inRoom && !mahjong.isHost) && store.mahjongEntryBlock == null
            PillButton(
                if (locked) GamesMahjongText.lockedLabel else GamesMahjongText.invite, Modifier.testTag(MahjongLobbyTags.invite(id)),
                kind = if (locked) PillKind.Gray else PillKind.Tinted, size = PillSize.Sm, icon = if (locked) AppIcon.Lock else null, enabled = enabled,
            ) { if (inRoom) mahjong.scope.launch { mahjong.invite(user.id) } else onCreate() }
        }
    }
}

@Composable
private fun Ranking(mahjong: MahjongStore) {
    val colors = AingTheme.colors
    LaunchedEffect(mahjong) { mahjong.loadRanking() }
    SectionHeader(GamesMahjongPhoneText.rankingTitle, trailing = SectionTrailing.Label(GamesMahjongText.rankHeader), padded = true)
    InsetGroup {
        val me = mahjong.ranking?.me
        if (me != null && me.rank == null && me.gamesUntilRanked > 0) {
            Text(
                "${me.gamesUntilRanked}${GamesMahjongText.gamesUntilRanked}", style = MaterialTheme.typography.bodySmall, color = colors.label2,
                modifier = Modifier.fillMaxWidth().padding(horizontal = AingDimens.cardPadding).padding(top = 10.dp),
            )
        }
        val rows = mahjong.ranking?.rows ?: emptyList()
        if (rows.isNotEmpty()) {
            val shown = rows.take(20)
            shown.forEachIndexed { offset, row ->
                GroupRow(dividerInset = if (offset == shown.size - 1) null else AingDimens.cardPadding, minHeight = 48.dp) {
                    Text(GamesMahjongText.rank(row.rank), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = colors.label, modifier = Modifier.width(36.dp))
                    PersonAvatar(row.displayName ?: "?", row.userId ?: "$offset", 28.dp, url = row.avatarUrl, characterHint = row.character)
                    PersonName(row.displayName ?: "?", Modifier.weight(1f), center = row.center)
                    Text(GamesMahjongText.avgRank(row.avgRank), style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM), color = colors.label2)
                }
            }
        } else {
            GroupRow(dividerInset = null) {
                Text(
                    if (mahjong.rankingUnavailable) GamesMahjongText.unavailable else if (mahjong.ranking == null) GamesMahjongText.loadingUsers else GamesMahjongText.emptyRanking,
                    style = MaterialTheme.typography.bodySmall, color = colors.label2,
                )
            }
        }
    }
}

// MARK: - 시트

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> Segmented(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, (value, label) ->
            SegmentedButton(selected = selected == value, onClick = { onSelect(value) }, shape = SegmentedButtonDefaults.itemShape(index, options.size), icon = {}) { Text(label) }
        }
    }
}

@Composable
private fun SheetTitle(title: String, onClose: () -> Unit) {
    GamesHeaderBar(title, subtitle = GamesMahjongText.title, onBack = onClose, backIcon = AppIcon.Close)
}

@Composable
private fun CreateRoomSheet(store: GamesStore, mahjong: MahjongStore, onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    GamesSheet(onDismiss) {
        SheetTitle(GamesMahjongText.createTitle, onDismiss)
        Column(Modifier.padding(AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(AingDimens.space4)) {
            Choice(GamesMahjongText.stakeLabel) {
                Segmented(MahjongStake.entries.map { it to "루비 ${it.rawValue}" }, mahjong.selectedStake) { mahjong.selectedStake = it }
            }
            Choice(GamesMahjongText.formatLabel) {
                Segmented(listOf(MahjongFormat.tonpuu to GamesMahjongText.format(MahjongFormat.tonpuu), MahjongFormat.hanchan to GamesMahjongText.format(MahjongFormat.hanchan)), mahjong.selectedFormat) { mahjong.selectedFormat = it }
                Text(GamesMahjongText.formatDetail(mahjong.selectedFormat), style = MaterialTheme.typography.labelSmall, color = colors.label2)
            }
            Choice(GamesMahjongText.publicLabel) {
                Segmented(listOf(false to GamesMahjongText.publicOff, true to GamesMahjongText.publicOn), mahjong.selectedPublic) { mahjong.selectedPublic = it }
            }
            Text(GamesMahjongText.split(mahjong.selectedStake.rawValue) + " · " + GamesMahjongText.createHint, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            PillButton(
                GamesMahjongText.createButton, Modifier.testTag(MahjongLobbyTags.CREATE_SEND), kind = PillKind.Filled, size = PillSize.Lg, fillsWidth = true,
                enabled = !mahjong.isWorking && store.mahjongEntryBlock == null && mahjong.duelsEnabled,
            ) {
                onDismiss()
                mahjong.scope.launch { mahjong.createRoom() }
            }
        }
    }
}

@Composable
private fun Choice(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = AingTheme.colors.label2)
        content()
    }
}

@Composable
private fun PracticeSheet(mahjong: MahjongStore, onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    var format by remember { mutableStateOf(MahjongFormat.tonpuu) }
    GamesSheet(onDismiss) {
        SheetTitle(GamesMahjongText.practiceTitle, onDismiss)
        Column(Modifier.padding(AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(AingDimens.space4)) {
            Choice(GamesMahjongText.formatLabel) {
                Segmented(listOf(MahjongFormat.tonpuu to GamesMahjongText.format(MahjongFormat.tonpuu), MahjongFormat.hanchan to GamesMahjongText.format(MahjongFormat.hanchan)), format) { format = it }
            }
            Choice(GamesMahjongText.practiceTimeLabel) {
                Segmented(listOf(false to GamesMahjongText.practiceTimedOff, true to GamesMahjongText.practiceTimedOn), mahjong.practiceTimed) { mahjong.practiceTimed = it }
            }
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(GamesMahjongText.practiceSeatNote, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                Text(GamesMahjongText.practiceNoRuby, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
            PillButton(GamesMahjongText.practiceStart, Modifier.testTag(MahjongLobbyTags.PRACTICE_START), kind = PillKind.Filled, size = PillSize.Lg, fillsWidth = true) {
                onDismiss()
                mahjong.startPractice(format, mahjong.practiceTimed)
            }
        }
    }
}

@Composable
private fun RulesSheet(onDismiss: () -> Unit) {
    val colors = AingTheme.colors
    var tab by remember { mutableIntStateOf(0) }
    GamesSheet(onDismiss) {
        SheetTitle(GamesMahjongText.rules, onDismiss)
        Box(Modifier.padding(horizontal = AingDimens.sideMargin).padding(bottom = AingDimens.space2)) {
            Segmented(listOf(0 to GamesMahjongText.rules, 1 to GamesMahjongText.yaku, 2 to GamesMahjongText.scoreTable), tab) { tab = it }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
            when (tab) {
                0 -> {
                    val painter = rememberMahjongTilePainter()
                    GamesMahjongRulesText.rules.forEach { line ->
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(line.title, style = MaterialTheme.typography.titleSmall, color = colors.label)
                            Text(line.detail, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                            val tiles = if (line.example.isNotEmpty()) MahjongTiles.parse(line.example) else null
                            if (tiles != null) {
                                Row {
                                    tiles.forEach { GamesMahjongTileView(MahjongTileFace.of(it), size = MahjongTileSize.discard, cornerLabels = false, display = DpSize(22.dp, 29.dp), painter = painter) }
                                }
                            }
                        }
                    }
                    Text(GamesMahjongRulesText.footer, style = MaterialTheme.typography.labelSmall, color = colors.label3)
                }
                1 -> {
                    GamesMahjongRulesText.yakuTable.forEach { row ->
                        Row(Modifier.fillMaxWidth()) {
                            Text(row.yaku.koreanName, style = MaterialTheme.typography.bodyMedium, color = colors.label, modifier = Modifier.weight(1f))
                            Text(row.open?.let { "${row.closed}판 · 울면 ${it}판" } ?: "${row.closed}판 · 멘젠만", style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = TNUM), color = colors.label2)
                        }
                    }
                    Text(GamesMahjongText.yaku + " — 역만", style = MaterialTheme.typography.titleSmall, color = colors.label, modifier = Modifier.padding(top = 8.dp))
                    Text(GamesMahjongRulesText.yakumanList.joinToString(" · ") { it.koreanName }, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                }
                else -> {
                    Row(Modifier.fillMaxWidth()) {
                        Text("부 \\ 판", style = MaterialTheme.typography.labelMedium, color = colors.label, modifier = Modifier.width(56.dp))
                        GamesMahjongRulesText.hanColumns.forEach { Text("${it}판", style = MaterialTheme.typography.labelMedium, color = colors.label, modifier = Modifier.weight(1f)) }
                    }
                    GamesMahjongRulesText.fuRows.forEach { fu ->
                        Row(Modifier.fillMaxWidth()) {
                            Text("${fu}부", style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = TNUM), color = colors.label, modifier = Modifier.width(56.dp))
                            GamesMahjongRulesText.hanColumns.forEach { han ->
                                Text(GamesMahjongScoreCell.text(han, fu), style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = TNUM), color = colors.label2, modifier = Modifier.weight(1f))
                            }
                        }
                    }
                    Text(GamesMahjongScoreCell.caption, style = MaterialTheme.typography.labelSmall, color = colors.label3, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
    }
}
