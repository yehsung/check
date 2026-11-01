// 원본: Sources/check/RummyPanelLobby.swift:516 (RummyTableCard) · :684 (RummyTableStage) · :724 (RummyTableChairView) · Sources/check/RummyPanel.swift:505 (RummyCountdownLeaf) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §5
//
// 폰 방 — 둘러앉은 탁자를 세로로 옮겼다: 위 의자 → [왼 의자 · 펠트 · 오른 의자] → 아래 의자(나). 탁자 가운데는 판돈 × 인원 = 상금과 등수 분배다.
// 그 아래 [나가기] · [N명으로 시작](방장, 2명 이상), 방장이면 초대할 사람 절(로비와 같은 부품).
// [나가기]와 머리 줄 뒤로는 **같은 길**이다(`onBack` → 껍데기의 뒤로 판단): 손님은 묻지 않고 나가고, 방장은 "방이 닫혀요" 확인을 지난다.
// 남은 시간은 **잎이 읽는다**(스토어는 매초 아무것도 대입하지 않는다 — 머리말 ⑦). 효과 키는 스토어 하나이고 효과 안에서 키를 쓰지 않는다(맥 0.3.69 재생성 고리).
package com.yehsung.aingcheck.ui.games.rummy

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
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyTableStage
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

/** 방 — 의자 넷(`RummyTableSeating.chairs`) · 방장 [시작] · 초대 줄 · 시작 남은 시간(`rummy.roomRemaining`). */
@Composable
fun GamesRummyRoomView(
    rummy: RummyStore,
    myUserID: String?,
    me: RummySeatFace,
    onRules: () -> Unit,
    onBack: () -> Unit,
    now: () -> SwiftDate,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    val room = rummy.myRoom
    val amHost = RummyExitPolicy.amHost(rummy.match)
    val entry = GamesRummyEntry(rummy.availability, rummy.duelsLocked, block = null, rummy.isWorking, rummy.rubyBalance)
    val warnings = GamesRummyLobbyPlan.entryWarnings(null, rummy.duelsLocked)
    val chairs = RummyTableSeating.chairs(room, me, myUserID?.let { SwiftUUID.parse(it) })
    Column(modifier) {
        GamesHeaderBar(RummyPhoneText.myRoomTitle, onBack = onBack) { GamesRummyRulesButton(onRules) }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin)
                .padding(top = AingDimens.space2, bottom = AingDimens.space6),
            verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
        ) {
            InsetGroup {
                Column(Modifier.padding(AingDimens.cardPadding), verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        AingChip(RummyPhoneText.stake(room?.stake), tint = colors.pending)
                        val isPublic = room?.isPublic == true
                        AingChip(if (isPublic) RummyPhoneText.publicOn else RummyPhoneText.publicOff, tint = if (isPublic) colors.working else colors.label2)
                        Spacer(Modifier.weight(1f))
                        GamesRummyReactionButton(rummy, now)
                    }
                    RoomCountdown(rummy, now)
                    RoomStage(chairs, room, inviteHint = amHost)
                    Text(
                        GamesRummyRoomPlan.hint(amHost), style = rowSubtitleStyle(), color = colors.label2, textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            GamesRummyLobbyPlan.storeNotice(rummy.notice, warnings)?.let { InlineNotice(it, kind = NoticeKind.Info) }
            warnings.forEach { InlineNotice(it, kind = NoticeKind.Warning) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PillButton(
                    RummyPhoneText.leave, Modifier.weight(if (amHost) 2f else 1f).testTag(GamesRummyRoomTags.LEAVE), kind = PillKind.Destructive, fillsWidth = true,
                    enabled = !rummy.isWorking, onClick = onBack,
                )
                if (amHost) {
                    PillButton(
                        GamesRummyRoomPlan.startTitle(room), Modifier.weight(3f).testTag(GamesRummyRoomTags.START), kind = PillKind.Filled, fillsWidth = true,
                        enabled = GamesRummyRoomPlan.canStart(room, amHost, entry),
                    ) { rummy.startGame() }
                }
            }
            // 초대는 방장 몫이다. 손님에게 누를 수 없는 사람 목록을 세우지 않는다.
            if (amHost && !rummy.duelsLocked) GamesRummyPeopleSection(rummy, room, amHost, entry)
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
    val tint = if (GamesRummyRoomPlan.isUrgent(seconds)) colors.danger else colors.accent
    Row(
        Modifier.heightIn(min = 24.dp).background(tint.copy(alpha = 0.12f), CircleShape).padding(horizontal = 10.dp).testTag(GamesRummyRoomTags.COUNTDOWN),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        AingIcon(AppIcon.HourglassEmpty, contentDescription = null, size = 13.dp, tint = tint)
        Text(RummyPhoneText.closesIn(seconds), style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = tint)
    }
}

/** 둘러앉은 탁자 — 위 → 왼·펠트·오른 → 아래(나). */
@Composable
private fun RoomStage(chairs: List<RummyTableChair>, room: RummyRoom?, inviteHint: Boolean) {
    BoxWithConstraints(Modifier.fillMaxWidth().testTag(GamesRummyRoomTags.STAGE)) {
        val chairWidth = GamesRummyTableStage.chairWidth(maxWidth.value).dp
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            RoomChair(chairs, GamesRummyTableStage.TOP, chairWidth, inviteHint)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GamesRummyTableStage.GAP.dp)) {
                RoomChair(chairs, GamesRummyTableStage.LEFT, chairWidth, inviteHint)
                TableFelt(room, Modifier.weight(1f).height(112.dp))
                RoomChair(chairs, GamesRummyTableStage.RIGHT, chairWidth, inviteHint)
            }
            RoomChair(chairs, GamesRummyTableStage.BOTTOM, chairWidth, inviteHint)
        }
    }
}

/** 탁자 가운데 — 판돈 × 인원 = 상금 · 등수 분배. 판 화면과 같은 천(`GamesRummyFeltPaint`). */
@Composable
private fun TableFelt(room: RummyRoom?, modifier: Modifier) {
    val shape = RoundedCornerShape(percent = 50)
    Box(modifier.clip(shape).border(3.dp, Brush.linearGradient(listOf(rimPink, rimViolet)), shape), contentAlignment = Alignment.Center) {
        GamesRummyFeltPaint(Modifier.fillMaxSize())
        Column(Modifier.padding(horizontal = 6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                Modifier.background(Color.Black.copy(alpha = 0.25f), CircleShape).border(1.dp, potRuby.copy(alpha = 0.8f), CircleShape).padding(horizontal = 8.dp, vertical = 3.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                RubyIcon(rememberRubyArt(13f), size = 13.dp)
                Text(
                    GamesRummyRoomPlan.potLine(room), style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM),
                    // 좁은 폰에서 잘리지 않게 두 줄까지 허용한다.
                    color = Color.White, textAlign = TextAlign.Center, maxLines = 2,
                )
            }
            Text(
                GamesRummyRoomPlan.splitLine(room), style = MaterialTheme.typography.labelSmall.copy(fontFeatureSettings = TNUM), color = Color.White.copy(alpha = 0.78f),
                textAlign = TextAlign.Center, maxLines = 2,
            )
        }
    }
}

/** 의자 하나. 사람이면 얼굴(방장 왕관 · 나 테두리) · 이름 · 꼬리표, 비었으면 점선 원. 반응 말풍선은 이 얼굴 위에 선다. */
@Composable
private fun RoomChair(chairs: List<RummyTableChair>, index: Int, width: Dp, inviteHint: Boolean) {
    val chair = chairs.getOrNull(index) ?: RummyTableChair.empty
    val colors = AingTheme.colors
    val anchors = LocalGamesRummyReactionAnchors.current
    Column(
        Modifier.width(width).testTag(GamesRummyRoomTags.chair(index)).semantics(mergeDescendants = true) { },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        when (chair.kind) {
            RummyTableChair.Kind.person -> {
                val name = chair.name ?: "?"
                Box(contentAlignment = Alignment.TopCenter) {
                    PersonAvatar(
                        name, chair.userId?.lowercased ?: name, 46.dp,
                        Modifier.alpha(if (chair.dimmed) 0.5f else 1f)
                            .then(if (chair.isMe) Modifier.border(2.5.dp, colors.accent, CircleShape) else Modifier)
                            .rummyReactionAnchor(anchors, chair.seatNo),
                        url = chair.avatarUrl, characterHint = chair.character,
                    )
                    if (chair.isHost) {
                        AingIcon(AppIcon.CrownFill, contentDescription = null, modifier = Modifier.offset(y = (-10).dp), size = 14.dp, tint = colors.pending)
                    }
                }
                Text(
                    name, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.label,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                chair.tag?.let { tag ->
                    Text(
                        tag, style = MaterialTheme.typography.labelSmall,
                        color = if (chair.dimmed) colors.label2 else if (chair.isHost) colors.pending else colors.working,
                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            RummyTableChair.Kind.empty -> {
                val tint = if (inviteHint) colors.accent else colors.label3
                Box(Modifier.size(46.dp), contentAlignment = Alignment.Center) {
                    Canvas(Modifier.fillMaxSize()) {
                        val dash = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))
                        drawCircle(tint, style = Stroke(width = 1.5.dp.toPx(), pathEffect = dash))
                    }
                    AingIcon(AppIcon.Add, contentDescription = null, size = 16.dp, tint = tint)
                }
                Text(
                    if (inviteHint) RummyPhoneText.invite else RummyPhoneText.emptySeat,
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = colors.label2, maxLines = 1,
                )
            }
        }
    }
}
