// 원본: Sources/check/RummyPanelLobby.swift:516 (RummyTableCard) · :684 (RummyTableStage) · :724 (RummyTableChairView) · Sources/check/RummyPanel.swift:505 (RummyCountdownLeaf) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §5
//
// 폰 방 — 둘러앉은 탁자를 세로로 옮겼다(iOS GamesRummyRoom.swift): 의자가 탁자 네 변에 걸터앉고, 탁자 가운데는 상금 · 식 · 등수 분배다.
// 그 아래 [N명으로 시작](방장, 2명 이상) · [나가기], 방장이면 부를 사람 절(로비와 같은 부품).
// [나가기]와 머리 줄 뒤로는 **같은 길**이다(`onBack` → 껍데기의 뒤로 판단): 손님은 묻지 않고 나가고, 방장은 "방이 닫혀요" 확인을 지난다.
// 남은 시간은 **잎이 읽는다**(스토어는 매초 아무것도 대입하지 않는다 — 머리말 ⑦). 효과 키는 스토어 하나이고 효과 안에서 키를 쓰지 않는다(맥 0.3.69 재생성 고리).
package com.yehsung.aingcheck.ui.games.rummy

import com.yehsung.aingcheck.ui.games.minigame.kit.PillSize
import kotlinx.coroutines.launch
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonName
import com.yehsung.aingcheck.ui.games.minigame.kit.GroupRow
import com.yehsung.aingcheck.core.stores.rummy.RummyNoticeText
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyRoomStageLayout
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.draw.drawBehind
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.clickable
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyExitPolicy
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.rules.rummy.RummyTableChair
import com.yehsung.aingcheck.core.rules.rummy.RummyTableSeating
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyEntry
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyLobbyPlan
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyRoomPlan
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.myRoom
import com.yehsung.aingcheck.core.stores.rummy.startGame
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.kit.AingChip
import com.yehsung.aingcheck.ui.games.minigame.kit.GamesHeaderBar
import com.yehsung.aingcheck.ui.games.minigame.kit.InlineNotice
import com.yehsung.aingcheck.ui.games.minigame.kit.InsetGroup
import com.yehsung.aingcheck.ui.games.minigame.kit.NoticeKind
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.games.minigame.kit.rowSubtitleStyle
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay

/** 방 꼬리표(시험·계측). */
object GamesRummyRoomTags {
    const val STAGE: String = "rummy.room.stage"
    const val COUNTDOWN: String = "rummy.room.countdown"
    const val START: String = "rummy.room.start"
    const val LEAVE: String = "rummy.room.leave"

    /** 의자 넷 — 순서는 `RummyTableSeating.chairs`([아래, 왼, 위, 오른]). */
    fun chair(index: Int): String = "rummy.room.chair.$index"
}

// 탁자 그림 고유 색(맥 RummyTableStyle) — 펠트는 두 테마 모두 짙어서 탁자 위 글자는 흰색으로 고정한다.
private val potRuby = Color(1.0f, 0.42f, 0.72f)
private val rimPink = Color(1.0f, 0.50f, 0.80f)
private val rimViolet = Color(0.62f, 0.42f, 1.0f)

/** 방 — 판돈 · 공개 여부 · 남은 시간(`rummy.roomRemaining`) · 의자 넷(`RummyTableSeating.chairs`) · 안내 · 방장 [시작] · [나가기] · 부를 사람. [block]·[balance] 는 껍데기가 넘긴다(다른 게임 판 · 잔액). */
@Composable
fun GamesRummyRoomView(
    rummy: RummyStore,
    myUserID: String?,
    me: RummySeatFace,
    onRules: () -> Unit,
    onBack: () -> Unit,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
    block: GamesBusyGame? = null,
    balance: Long? = rummy.rubyBalance,
) {
    val colors = AingTheme.colors
    val room = rummy.myRoom
    val amHost = RummyExitPolicy.amHost(rummy.match)
    val entry = GamesRummyEntry(rummy.availability, rummy.duelsLocked, block, rummy.isWorking, balance)
    val warnings = GamesRummyLobbyPlan.entryWarnings(GamesBusyText.entryBlockNotice(block, GamesBusyGame.rummy), rummy.duelsLocked)
    val chairs = RummyTableSeating.chairs(room, me, myUserID?.let { SwiftUUID.parse(it) })
    val scope = rememberCoroutineScope()
    val people = remember { BringIntoViewRequester() }
    Column(modifier) {
        GamesHeaderBar(RummyPhoneText.myRoomTitle, onBack = onBack) { GamesRummyRulesButton(onRules) }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin)
                .padding(top = AingDimens.space2, bottom = AingDimens.space6),
        ) {
            RoomHeader(rummy, room, now)
            RoomStage(chairs, room, inviteHint = amHost, Modifier.padding(top = AingDimens.space3)) { scope.launch { people.bringIntoView() } }
            RoomHint(rummy, room, amHost, entry, warnings)
            Column(Modifier.padding(top = AingDimens.rowSpacing), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                if (amHost) {
                    PillButton(
                        GamesRummyRoomPlan.startTitle(room), Modifier.testTag(GamesRummyRoomTags.START), kind = PillKind.Filled, size = PillSize.Lg, icon = AppIcon.PlayArrowFill, fillsWidth = true,
                        enabled = GamesRummyRoomPlan.canStart(room, amHost, entry),
                    ) { rummy.startGame() }
                }
                PillButton(
                    RummyPhoneText.leave, Modifier.testTag(GamesRummyRoomTags.LEAVE), kind = PillKind.Gray, icon = AppIcon.Logout, fillsWidth = true,
                    enabled = !rummy.isWorking, onClick = onBack,
                )
            }
            // 초대는 방장 몫이다. 손님에게 누를 수 없는 사람 목록을 세우지 않는다.
            if (amHost && !rummy.duelsLocked) {
                GamesRummyPeopleSection(
                    rummy, room, amHost, entry, Modifier.padding(top = AingDimens.space3).bringIntoViewRequester(people),
                ) { user -> rummy.inviteQueued(user.id) }
            }
        }
    }
}

/** 판돈 · 공개 여부 · 닫히기까지. 좁으면(320 · 큰 글자) 남은 시간이 아래 줄로 내려간다. */
@Composable
private fun RoomHeader(rummy: RummyStore, room: RummyRoom?, now: () -> SwiftDate) {
    val colors = AingTheme.colors
    val isPublic = room?.isPublic == true
    FlowRow(
        Modifier.fillMaxWidth().padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space2),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        AingChip(RummyPhoneText.stake(room?.stake), tint = colors.pending)
        AingChip(if (isPublic) RummyPhoneText.publicOn else RummyPhoneText.publicOff, tint = if (isPublic) colors.working else colors.label2)
        Spacer(Modifier.weight(1f))
        RoomCountdown(rummy, now)
    }
}

/** 서버 말 → 다른 게임 · 잠금 → 기다리는 까닭. '초대를 보냈어요' 만 좋은 소식이다 — 나머지 서버 말은 전부 거절·실패다. */
@Composable
private fun RoomHint(rummy: RummyStore, room: RummyRoom?, amHost: Boolean, entry: GamesRummyEntry, warnings: List<String>) {
    val notice = GamesRummyLobbyPlan.storeNotice(rummy.notice, warnings)
    val top = Modifier.padding(top = AingDimens.rowSpacing)
    when {
        notice != null -> InlineNotice(notice, top, if (notice == RummyNoticeText.invited) NoticeKind.Info else NoticeKind.Warning)
        warnings.isNotEmpty() -> warnings.forEach { InlineNotice(it, top, NoticeKind.Warning) }
        else -> GamesRummyRoomPlan.hint(amHost, room, entry)?.let {
            Text(
                it, style = rowSubtitleStyle(), color = AingTheme.colors.label2,
                modifier = top.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin),
            )
        }
    }
}

/** 방이 닫히기까지 남은 시간 — 이 잎만 매초 읽는다. 곧 닫히면 빨강. */
@Composable
private fun RoomCountdown(rummy: RummyStore, now: () -> SwiftDate) {
    var remaining by remember { mutableStateOf(rummy.roomRemaining(now())) }
    LaunchedEffect(rummy) {
        while (true) {
            remaining = rummy.roomRemaining(now())
            delay(1000)
        }
    }
    val left = remaining ?: return
    val colors = AingTheme.colors
    val seconds = GamesRummyRoomPlan.countdownSeconds(left)
    val tint = if (GamesRummyRoomPlan.isUrgent(seconds)) colors.danger else colors.label2
    Row(
        Modifier.heightIn(min = 22.dp).testTag(GamesRummyRoomTags.COUNTDOWN),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        AingIcon(AppIcon.HourglassEmpty, contentDescription = null, size = 13.dp, tint = tint)
        Text(RummyPhoneText.closesIn(seconds), style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM), color = tint, maxLines = 1, softWrap = false)
    }
}

/** 둘러앉은 탁자. 칸은 `GamesRummyRoomStageLayout` 이 낸다 — 의자가 탁자 네 변에 걸터앉는다. 큰 글자에서는 그림에 글자가 안 들어가(의자 88) 줄로 푼다. */
@Composable
private fun RoomStage(chairs: List<RummyTableChair>, room: RummyRoom?, inviteHint: Boolean, modifier: Modifier = Modifier, onInviteTap: () -> Unit) {
    if (LocalDensity.current.fontScale >= 1.3f) {
        Column(modifier.testTag(GamesRummyRoomTags.STAGE), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
            PotText(room, onFelt = false, Modifier.fillMaxWidth())
            val visible = chairs.filter { it.kind == RummyTableChair.Kind.person }
            InsetGroup { visible.forEachIndexed { index, chair -> SeatRow(chair, chairs.indexOf(chair), isLast = index == visible.size - 1) } }
        }
        return
    }
    BoxWithConstraints(modifier.fillMaxWidth().testTag(GamesRummyRoomTags.STAGE)) {
        val layout = GamesRummyRoomStageLayout(maxWidth.value.toDouble())
        Box(Modifier.fillMaxWidth().height(layout.height.dp)) {
            GamesRummyTableSurface(Modifier.atRect(layout.table), cornerRadius = 44.dp)
            PotText(room, onFelt = true, Modifier.atRect(layout.center))
            for (index in 0 until minOf(chairs.size, 4)) {
                RoomChair(chairs[index], index, inviteHint, onInviteTap, Modifier.atRect(layout.chair(index)))
            }
        }
    }
}

/** 상금(판돈 × 인원) + 등수 분배(순수익). 펠트는 라이트·다크 모두 어둡다. */
@Composable
private fun PotText(room: RummyRoom?, onFelt: Boolean, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val primary = if (onFelt) Color.White else colors.label
    val secondary = if (onFelt) Color.White.copy(alpha = 0.82f) else colors.label2
    Column(
        modifier.semantics(mergeDescendants = true) { },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            RubyIcon(rememberRubyArt(17f), size = 17.dp)
            Text(
                GamesRummyRoomPlan.potTotal(room).toString(),
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black, fontFeatureSettings = TNUM), color = primary, maxLines = 1, softWrap = false,
            )
        }
        val small = MaterialTheme.typography.labelSmall.copy(fontFeatureSettings = TNUM)
        Text(GamesRummyRoomPlan.potFormula(room), style = small.copy(fontWeight = FontWeight.SemiBold), color = secondary, maxLines = 1, softWrap = false)
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            GamesRummyRoomPlan.splitLines(room).forEach { Text(it, style = small, color = secondary, maxLines = 1, softWrap = false) }
        }
    }
}

/** 의자 하나 — 카드 바탕 위 얼굴(방장 왕관) · 이름 · 꼬리표, 빈자리는 점선 카드. 반응 말풍선은 이 칸 위에 선다. */
@Composable
private fun RoomChair(chair: RummyTableChair, index: Int, inviteHint: Boolean, onInviteTap: () -> Unit, modifier: Modifier) {
    val colors = AingTheme.colors
    val anchors = LocalGamesRummyReactionAnchors.current
    val shape = RoundedCornerShape(AingDimens.innerRadius)
    when (chair.kind) {
        RummyTableChair.Kind.person -> {
            val name = chair.name ?: "?"
            Column(
                modifier.rummyReactionAnchor(anchors, chair.seatNo).testTag(GamesRummyRoomTags.chair(index))
                    .background(colors.surface, shape)
                    .border(if (chair.isMe) 1.5.dp else AingDimens.hairline, if (chair.isMe) colors.accent else colors.separator, shape)
                    .padding(horizontal = 4.dp)
                    .semantics(mergeDescendants = true) { },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically),
            ) {
                Box(contentAlignment = Alignment.TopCenter) {
                    PersonAvatar(name, chair.userId?.lowercased ?: name, 40.dp, Modifier.alpha(if (chair.dimmed) 0.5f else 1f), url = chair.avatarUrl, characterHint = chair.character)
                    if (chair.isHost) AingIcon(AppIcon.CrownFill, contentDescription = null, modifier = Modifier.offset(y = (-9).dp), size = 12.dp, tint = colors.gold)
                }
                Text(name, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                chair.tag?.let { tag ->
                    Text(
                        tag, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold),
                        color = if (chair.dimmed) colors.label2 else if (chair.isHost) colors.pending else colors.working,
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        RummyTableChair.Kind.empty -> {
            // 빈 의자. 방장이면 눌러서 아래 '부를 사람'으로 간다 — [초대]라고 적어 놓고 안 눌리면 고장으로 읽힌다. 손님의 빈자리엔 [+]가 없다.
            val tint = if (inviteHint) colors.accent else colors.label2
            Column(
                modifier.testTag(GamesRummyRoomTags.chair(index))
                    .background(colors.surface, shape)
                    .then(if (inviteHint) Modifier.clip(shape).clickable(role = Role.Button, onClick = onInviteTap) else Modifier)
                    .drawBehind {
                        val dash = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))
                        val radius = CornerRadius(AingDimens.innerRadius.toPx())
                        drawRoundRect(tint.copy(alpha = 0.7f), cornerRadius = radius, style = Stroke(width = 1.5.dp.toPx(), pathEffect = dash))
                    },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
            ) {
                if (inviteHint) AingIcon(AppIcon.Add, contentDescription = null, size = 16.dp, tint = tint)
                Text(
                    if (inviteHint) RummyPhoneText.invite else RummyPhoneText.emptySeat,
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = tint, maxLines = 1,
                )
            }
        }
    }
}

/** 큰 글자의 자리 한 줄. */
@Composable
private fun SeatRow(chair: RummyTableChair, index: Int, isLast: Boolean) {
    val colors = AingTheme.colors
    val name = chair.name ?: "?"
    val anchors = LocalGamesRummyReactionAnchors.current
    GroupRow(Modifier.rummyReactionAnchor(anchors, chair.seatNo).testTag(GamesRummyRoomTags.chair(index)), dividerInset = if (isLast) null else AingDimens.cardPadding) {
        PersonAvatar(name, chair.userId?.lowercased ?: name, 36.dp, Modifier.alpha(if (chair.dimmed) 0.5f else 1f), url = chair.avatarUrl, characterHint = chair.character)
        Column(Modifier.weight(1f).semantics(mergeDescendants = true) { }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            PersonName(name)
            chair.tag?.let { Text(it, style = rowSubtitleStyle(), color = colors.label2) }
        }
    }
}
