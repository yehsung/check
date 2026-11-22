// 원본: Sources/CheckMobileKit/Games/GamesDuelRooms.swift @ 9774e23b(폰 1.0.19 — 맥 0.3.83 DuelRoomsLobby 의 폰 짝 · 대표 #d_xygj8oZRFlfH 1번)
//
// 로비에 끼우는 '기다리는 방' 절. 맥은 로비 왼쪽 열 탭 [방 | 상대 고르기]지만 폰 로비는 세로 한 줄이라 **절**로 둔다 — 받은 · 보낸 신청(시간이
// 흐르는 것) 바로 아래, 상대 고르기 위. 문이 닫혀 있으면(서버 문 · 함수 없음) 절이 아예 없다. 상태 · 판정은 전부 코어 DuelRoomStore.
// 부르는 자리: 로비가 보이는 동안 처음 한 번 + 문이 열려 있으면 15초마다 목록 · [방 만들기] · [닫기] · [참가].
package com.yehsung.aingcheck.ui.games.rooms

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.rooms.DuelRoomStore
import com.yehsung.aingcheck.core.stores.rooms.DuelRoomsRules
import com.yehsung.aingcheck.core.wire.rooms.DuelRoom
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomGame
import com.yehsung.aingcheck.core.wire.rooms.DuelRoomText
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionHeader
import com.yehsung.aingcheck.ui.games.minigame.kit.SectionTrailing
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.games.minigame.kit.rowTitleStyle
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

object DuelRoomsTags {
    const val SECTION = "duel-rooms-section"
    const val CREATE = "duel-rooms-create"
    const val CREATE_SUBMIT = "duel-rooms-create-submit"
    const val MY_ROOM = "duel-rooms-my-room"
    const val CLOSE = "duel-rooms-close"
    fun stake(stake: Long) = "duel-rooms-stake:$stake"
    fun join(roomID: String) = "duel-rooms-join:$roomID"
}

/**
 * 로비에 끼우는 '기다리는 방' 절. [store] 가 없거나(Windows v1 동결 · 시험) 문이 열려 있지 않으면 빈 자리다(처음 한 번은 묻는다).
 * 머리는 로비의 다른 절과 같은 여백(padded) — 위 간격은 머리가 준다.
 */
@Composable
fun GamesDuelRoomsSection(store: DuelRoomStore?, game: DuelRoomGame) {
    if (store == null) return
    // 처음 한 번 묻고, 문이 열려 있는 동안 15초마다 목록을 다시 읽는다(화면이 사라지면 작업이 끝난다).
    LaunchedEffect(store, game) {
        store.refresh(game)
        while (isActive && store.doorOpen == true) {
            store.sleep(DuelRoomsRules.refreshSeconds)
            store.refresh(game)
        }
    }
    if (store.doorOpen != true) return
    var creating by remember(game) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val colors = AingTheme.colors
    val rubyArt = rememberRubyArt(13f)
    val rooms = store.rooms(game)
    Column(Modifier.testTag(DuelRoomsTags.SECTION)) {
        SectionHeader(DuelRoomText.roomsTitle, trailing = if (rooms.isEmpty()) SectionTrailing.None else SectionTrailing.Label("${rooms.size}"), padded = true)
        InsetGroup {
            val mine = store.myOpenRoom(game)
            val other = store.myOpenRoomOtherThan(game)
            when {
                mine != null -> GroupRow(Modifier.testTag(DuelRoomsTags.MY_ROOM), isHighlighted = true) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(DuelRoomText.myRoomTitle, style = rowTitleStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.label)
                            RubyIcon(rubyArt, size = 13.dp)
                            Text(DuelRoomText.stakeLine(mine.stake), style = rowSubtitleStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.label)
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            CircularProgressIndicator(Modifier.size(12.dp), strokeWidth = 1.5.dp)
                            Text("${DuelRoomText.waiting(store.waitedSeconds(mine))} · ${DuelRoomText.myRoomHint}", style = rowSubtitleStyle(), color = colors.label2)
                        }
                    }
                    Spacer(Modifier.width(6.dp))
                    PillButton(DuelRoomText.closeRoom, Modifier.testTag(DuelRoomsTags.CLOSE), kind = PillKind.Gray, size = PillSize.Sm, enabled = !store.isBusy) {
                        scope.launch { store.closeMyRoom() }
                    }
                }
                other?.game != null -> GroupRow {
                    AingIcon(sf("door.left.hand.open", AppIcon.Groups), null, size = 18.dp, tint = colors.accent)
                    Text(DuelRoomText.otherGameRoom(other.game!!), style = rowSubtitleStyle(), color = colors.label2, modifier = Modifier.weight(1f).padding(start = 8.dp))
                    PillButton(DuelRoomText.closeRoom, Modifier.testTag(DuelRoomsTags.CLOSE), kind = PillKind.Gray, size = PillSize.Sm, enabled = !store.isBusy) {
                        scope.launch { store.closeMyRoom() }
                    }
                }
                creating -> CreateRow(store, game, onDone = { creating = false })
                else -> GroupRow {
                    PillButton(DuelRoomText.create, Modifier.testTag(DuelRoomsTags.CREATE), kind = PillKind.Filled, icon = AppIcon.Add, fillsWidth = true, enabled = !store.isBusy) {
                        creating = true
                    }
                }
            }
            store.notice?.let { notice ->
                GroupRow(minHeight = 36.dp) { Text(notice, style = rowSubtitleStyle(), color = colors.pending) }
            }
            if (rooms.isEmpty()) {
                GroupRow(dividerInset = null, minHeight = 44.dp) {
                    Text(if (game in store.loadedGames) DuelRoomText.emptyRooms else DuelRoomText.loading, style = rowSubtitleStyle(), color = colors.label2)
                }
            } else {
                rooms.forEachIndexed { index, room -> RoomRow(store, game, room, isLast = index == rooms.size - 1) }
            }
        }
    }
}

@Composable
private fun CreateRow(store: DuelRoomStore, game: DuelRoomGame, onDone: () -> Unit) {
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    val rubyArt = rememberRubyArt(13f)
    GroupRow {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(DuelRoomText.createTitle, style = rowTitleStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.label, modifier = Modifier.weight(1f))
                Box(
                    Modifier.size(32.dp).clickable(role = Role.Button, onClick = onDone).semantics { contentDescription = DuelRoomText.createClose },
                    contentAlignment = Alignment.Center,
                ) { AingIcon(sf("xmark", AppIcon.Close), null, size = 14.dp, tint = colors.label2) }
            }
            Text(DuelRoomText.createHint, style = rowSubtitleStyle(), color = colors.label2)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(DuelRoomText.stakeLabel, style = rowSubtitleStyle(), color = colors.label2)
                for (stake in store.stakes) {
                    val affordable = DuelRoomsRules.affordable(stake, store.rubyBalance)
                    val selected = store.selectedStake == stake
                    val shape = RoundedCornerShape(9.dp)
                    Row(
                        Modifier
                            .height(34.dp)
                            .background(if (selected) colors.accentTint else colors.fill, shape)
                            .border(1.5.dp, if (selected) colors.accent else Color.Transparent, shape)
                            .clickable(enabled = affordable, role = Role.Button) { store.selectedStake = stake }
                            .semantics { this.selected = selected }
                            .padding(horizontal = 12.dp)
                            .testTag(DuelRoomsTags.stake(stake)),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        RubyIcon(rubyArt, size = 12.dp)
                        Text("$stake", style = rowTitleStyle().copy(fontWeight = FontWeight.SemiBold), color = if (affordable) colors.label else colors.label3)
                    }
                }
            }
            PillButton(
                DuelRoomText.createButton, Modifier.testTag(DuelRoomsTags.CREATE_SUBMIT), kind = PillKind.Filled, fillsWidth = true,
                enabled = !store.isBusy && DuelRoomsRules.affordable(store.selectedStake, store.rubyBalance),
            ) {
                scope.launch {
                    store.open(game, store.selectedStake)
                    if (store.myOpenRoom(game) != null) onDone()
                }
            }
        }
    }
}

@Composable
private fun RoomRow(store: DuelRoomStore, game: DuelRoomGame, room: DuelRoom, isLast: Boolean) {
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    val rubyArt = rememberRubyArt(13f)
    val name = room.host?.displayName ?: "사용자"
    val affordable = DuelRoomsRules.affordable(room.stake, store.rubyBalance)
    GroupRow(dividerInset = if (isLast) null else AingDimens.cardPadding + 40.dp + 12.dp, minHeight = 60.dp) {
        PersonAvatar(name, room.host?.userID ?: room.id, 40.dp, url = room.host?.avatarURL, characterHint = room.host?.character)
        Column(Modifier.weight(1f).padding(start = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, style = rowTitleStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                RubyIcon(rubyArt, size = 12.dp)
                Text("${room.stake} · ${DuelRoomText.waiting(store.waitedSeconds(room))}", style = rowSubtitleStyle(), color = colors.label2, maxLines = 1)
            }
        }
        Spacer(Modifier.width(8.dp))
        PillButton(
            if (affordable) DuelRoomText.join else DuelRoomText.notEnough,
            Modifier.testTag(DuelRoomsTags.join(room.id)).semantics { contentDescription = "${name}님 방에 ${DuelRoomText.join}" },
            kind = PillKind.Tinted, size = PillSize.Sm, enabled = DuelRoomsRules.canJoin(room, store, game),
        ) { scope.launch { store.join(room) } }
    }
}
