// 원본: Sources/CheckMobileKit/Games/GamesMahjongTable.swift @ 928d5562(폰 1.0.18 판 화면 — 가로) — Android 판 8
//
// 맥 · 아이폰 판 화면의 약속을 그대로 지킨다:
//  · 단추 · 버릴 수 있는 패는 `store.myDecision` 에 있는 것만 — 클라 판정으로 켜지 않는다. 판 · 부 · 점수는 늘 서버 값.
//  · 숨은 정보는 서버가 이미 걷었다 — 남의 손은 뒷면 수뿐. 남의 시계는 그리지 않는다.
//  · 펠트(강 바람개비 · 상대 손 띠 · 가운데 판)는 펠트 좌표 884×502 를 통째로 줄여 그린다(GamesMahjongFeltGeometry).
//  · 폰에서 다른 것: 두 번 눌러 버리기(한 번 = 들기 · 미리보기) · 움직임 없음 · 반응 보내기 없음 · 패 그림 선택지 시트 없음.
// 배치(가로): 왼쪽 열(정보 · [규칙] [나가기] · 왼쪽 상대 · 내 카드) | 가운데(맞은편 상대 띠 · 펠트) | 오른쪽 열(오른쪽 상대 · 보조 · 동작) · 맨 아래 손패.
package com.yehsung.aingcheck.ui.games.mahjong

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClaimKind
import com.yehsung.aingcheck.core.rules.mahjong.MahjongClock
import com.yehsung.aingcheck.core.rules.mahjong.MahjongCompass
import com.yehsung.aingcheck.core.rules.mahjong.MahjongDecision
import com.yehsung.aingcheck.core.rules.mahjong.MahjongHand
import com.yehsung.aingcheck.core.rules.mahjong.MahjongSeatCompass
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTile
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileArtModel
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileFace
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileSize
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileState
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTiles
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongPhoneAids
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongPhoneText
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongText
import com.yehsung.aingcheck.core.stores.mahjong.MahjongMatchStatus
import com.yehsung.aingcheck.core.stores.mahjong.MahjongNoticeText
import com.yehsung.aingcheck.core.stores.mahjong.MahjongRoomBand
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStatePayload
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStateSeat
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStore
import com.yehsung.aingcheck.core.stores.mahjong.MahjongVisibleTiles
import com.yehsung.aingcheck.core.stores.mahjong.ankan
import com.yehsung.aingcheck.core.stores.mahjong.armRiichi
import com.yehsung.aingcheck.core.stores.mahjong.call
import com.yehsung.aingcheck.core.stores.mahjong.cancelRiichi
import com.yehsung.aingcheck.core.stores.mahjong.comeBack
import com.yehsung.aingcheck.core.stores.mahjong.declareKyuushu
import com.yehsung.aingcheck.core.stores.mahjong.declareTsumo
import com.yehsung.aingcheck.core.stores.mahjong.discard
import com.yehsung.aingcheck.core.stores.mahjong.endPractice
import com.yehsung.aingcheck.core.stores.mahjong.kakan
import com.yehsung.aingcheck.core.stores.mahjong.leaveTable
import com.yehsung.aingcheck.core.stores.mahjong.passCall
import com.yehsung.aingcheck.core.stores.mahjong.showRoom
import com.yehsung.aingcheck.core.stores.mahjong.start
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.ceil

object MahjongTableTags {
    const val TABLE = "mahjong.table"
    const val HAND = "mahjong.hand"
    fun handTile(id: Int) = "mahjong.hand.$id"
    fun action(name: String) = "mahjong.action.$name"
    const val LEAVE = "mahjong.leave"
    const val RULES = "mahjong.rules"
}

/** 판 색(펠트 · 칸 — 맥 `MahjongFeltStyle` 과 같은 중간 톤). 판 화면은 늘 어둡다. */
object GamesMahjongPalette {
    val background = Color(0.10f, 0.12f, 0.14f)
    val panel = Color(0.16f, 0.19f, 0.22f)
    val felt = Color(0.24f, 0.39f, 0.36f)
    val rim = Color(0.32f, 0.46f, 0.44f)
    val board = Color(0.31f, 0.45f, 0.43f)
    val boardRim = Color(0.44f, 0.58f, 0.56f)
    val glyph = Color(0.86f, 0.84f, 0.80f)
    val secondary = Color.White.copy(alpha = 0.62f)
    val accent = Color(0.33f, 0.67f, 1.0f)
}

/** 주기마다 바뀌는 값(Swift `TimelineView(.periodic)` 자리) — 읽는 자리가 다시 그려진다. */
@Composable
internal fun rememberTick(periodMs: Long): Int {
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(periodMs) {
        while (true) {
            delay(periodMs)
            tick += 1
        }
    }
    return tick
}

/** 판 화면. 세로로 불렸으면(기기가 돌기를 기다리는 동안) 돌리라는 안내만. */
@Composable
fun GamesMahjongTableView(
    store: GamesStore,
    mahjong: MahjongStore,
    myName: String?,
    myCharacter: String?,
    onRules: () -> Unit,
    onLeaveTable: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var confirmingLeave by remember { mutableStateOf(false) }
    BoxWithConstraints(modifier.fillMaxSize().background(GamesMahjongPalette.background).testTag(MahjongTableTags.TABLE)) {
        val payload = mahjong.table
        if (payload != null) {
            if (maxWidth > maxHeight) {
                TableContent(store, mahjong, payload, maxWidth.value, maxHeight.value, myName, myCharacter, onRules, onLeave = {
                    if (mahjong.isPractice) mahjong.endPractice() else confirmingLeave = true
                })
            } else {
                RotatingNotice()
            }
        }
    }
    if (confirmingLeave) {
        AlertDialog(
            onDismissRequest = { confirmingLeave = false },
            title = { Text(GamesMahjongPhoneText.leaveTitle) },
            text = { Text(GamesMahjongPhoneText.leaveDetail) },
            confirmButton = {
                TextButton(onClick = {
                    confirmingLeave = false
                    if (mahjong.isPractice) {
                        mahjong.endPractice()
                    } else {
                        mahjong.scope.launch { mahjong.leaveTable() }
                        onLeaveTable()
                    }
                }) { Text(GamesMahjongPhoneText.leaveConfirm, color = AingTheme.colors.danger) }
            },
            dismissButton = { TextButton(onClick = { confirmingLeave = false }) { Text(GamesMahjongPhoneText.stay) } },
        )
    }
}

@Composable
private fun RotatingNotice() {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        CircularProgressIndicator(color = GamesMahjongPalette.accent)
        Spacer(Modifier.height(12.dp))
        Text(GamesMahjongPhoneText.rotating, style = MaterialTheme.typography.bodySmall, color = GamesMahjongPalette.secondary)
    }
}

@Composable
private fun Place(rect: Rect, content: @Composable () -> Unit) {
    Box(Modifier.offset(rect.left.dp, rect.top.dp).size(maxOf(0f, rect.width).dp, maxOf(0f, rect.height).dp)) { content() }
}

@Composable
private fun TableContent(
    store: GamesStore, mahjong: MahjongStore, payload: MahjongStatePayload, width: Float, height: Float,
    myName: String?, myCharacter: String?, onRules: () -> Unit, onLeave: () -> Unit,
) {
    val layout = GamesMahjongTableLayout(width, height)
    val mySeat = payload.mySeat ?: 0
    fun seat(compass: MahjongCompass): MahjongStateSeat? {
        val number = MahjongSeatCompass.seat(compass, mySeat)
        return payload.seats?.firstOrNull { it.seatNo == number }
    }
    Box(Modifier.fillMaxSize()) {
        Place(layout.info) { InfoBox(mahjong, payload) }
        Place(layout.chrome) {
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                SmallButton(GamesMahjongText.rules, GamesMahjongPalette.secondary, Modifier.weight(0.4f).testTag(MahjongTableTags.RULES), onRules)
                SmallButton(
                    if (mahjong.isPractice) GamesMahjongText.practiceEnd else GamesMahjongText.leave, AingTheme.colors.danger,
                    Modifier.weight(0.6f).testTag(MahjongTableTags.LEAVE), onLeave,
                )
            }
        }
        seat(MahjongCompass.left)?.let { Place(layout.leftSeat) { SeatCard(mahjong, payload, it, mine = false) } }
        seat(MahjongCompass.top)?.let { Place(layout.topSeat) { SeatCard(mahjong, payload, it, mine = false, compact = true) } }
        seat(MahjongCompass.right)?.let { Place(layout.rightSeat) { SeatCard(mahjong, payload, it, mine = false) } }
        seat(MahjongCompass.bottom)?.let { Place(layout.mySeat) { SeatCard(mahjong, payload, it, mine = true, myName = myName, myCharacter = myCharacter) } }
        Place(layout.felt) { FeltView(mahjong, payload, layout.feltScale) }
        Place(layout.aids) { AidsRow(mahjong) }
        Place(layout.actions) { ActionsView(mahjong, payload) }
        Place(layout.hand) { HandView(mahjong, payload, layout.handTileHeight) }
        val felt = layout.felt
        if (payload.match?.matchStatus == MahjongMatchStatus.finished) {
            val w = minOf(width - 32, 520f)
            Place(Rect((width - w) / 2, 12f, (width - w) / 2 + w, height - 12f)) { GamesMahjongMatchResultCard(store, mahjong, payload) }
        } else if (payload.match?.phase == "hand_end") {
            payload.lastHand?.let { result ->
                Place(Rect(felt.left - 20, felt.top - 5, felt.right + 20, felt.bottom + 5)) { GamesMahjongHandResultCard(mahjong, payload, result) }
            }
        }
        mahjong.roomBand?.let { band ->
            val w = minOf(felt.width, 420f)
            Place(Rect(felt.center.x - w / 2, felt.top + 6, felt.center.x + w / 2, felt.top + 38)) { RoomBand(mahjong, band) }
        }
    }
}

@Composable
private fun InfoBox(mahjong: MahjongStore, payload: MahjongStatePayload) {
    val match = payload.match
    val ruby = rememberRubyArt(10f)
    Column(
        Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp)).background(GamesMahjongPalette.panel).padding(horizontal = 8.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(GamesMahjongText.roundName(match?.round, match?.handNo), style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.ExtraBold), color = Color.White)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            if (mahjong.isPractice) {
                Text(GamesMahjongText.practiceTitle, fontSize = 11.sp, color = AingTheme.colors.working, maxLines = 1)
            } else {
                RubyIcon(ruby, size = 10.dp)
                Text("${match?.stake ?: 0}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
            Text(
                "· " + GamesMahjongText.format(match?.formatKind) + (if (match?.extension == true) " · 연장" else ""),
                fontSize = 11.sp, color = GamesMahjongPalette.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun SmallButton(title: String, tint: Color, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier.fillMaxHeight().clip(CircleShape).border(1.dp, tint.copy(alpha = 0.7f), CircleShape).clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = tint, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// MARK: - 자리 카드

@Composable
private fun SeatCard(
    mahjong: MahjongStore, payload: MahjongStatePayload, seat: MahjongStateSeat, mine: Boolean, compact: Boolean = false,
    myName: String? = null, myCharacter: String? = null,
) {
    val isTurn = payload.match?.phase == "turn" && payload.match?.turnSeat == seat.seatNo
    val isBot = mahjong.isPractice && seat.seatNo != payload.mySeat
    val name = when {
        seat.deleted == true -> GamesMahjongText.deletedChip
        mine -> myName ?: seat.user?.displayName ?: "나"
        else -> seat.user?.displayName ?: "?"
    }
    val id = seat.user?.userId ?: "seat-${seat.seatNo}"
    val character = if (mine) myCharacter ?: seat.user?.character else seat.user?.character
    val shape = RoundedCornerShape(10.dp)
    Box(
        Modifier.fillMaxSize().clip(shape).background(GamesMahjongPalette.panel)
            .border(if (isTurn) 2.dp else 1.dp, if (isTurn) GamesMahjongPalette.accent else Color.White.copy(alpha = 0.10f), shape)
            .alpha(if (seat.deleted == true) 0.55f else 1f).semantics(mergeDescendants = true) { },
    ) {
        when {
            compact -> Row(Modifier.fillMaxSize().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PersonAvatar(name, id, 22.dp, url = seat.user?.avatarUrl, characterHint = character)
                Text(name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Score(seat, 15)
                Chips(seat)
            }
            mine -> Row(Modifier.fillMaxSize().padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(46.dp), contentAlignment = Alignment.Center) {
                    ClockRing(mahjong, 44.dp)
                    PersonAvatar(name, id, 34.dp, url = seat.user?.avatarUrl, characterHint = character)
                }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Score(seat, 17)
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) { Chips(seat) }
                }
            }
            else -> BoxWithConstraints(Modifier.fillMaxSize()) {
                if (maxHeight >= 120.dp) {
                    Column(Modifier.fillMaxSize().padding(6.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterVertically)) {
                        PersonAvatar(name, id, 30.dp, url = seat.user?.avatarUrl, characterHint = character)
                        Text(name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (isBot) Text(GamesMahjongText.practiceBotTag, fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = AingTheme.colors.working)
                        Score(seat, 16)
                        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) { Chips(seat) }
                    }
                } else {
                    // 낮은 칸(오른쪽 상대 — 96dp): 아바타 · 이름을 한 줄로 접어 점수 · 칩이 칸 안에 들게 한다(아이폰은 칸 밖으로 넘쳐 보조 단추에 겹쳤다).
                    Column(Modifier.fillMaxSize().padding(horizontal = 6.dp, vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            PersonAvatar(name, id, 24.dp, url = seat.user?.avatarUrl, characterHint = character)
                            Text(name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Score(seat, 16)
                        Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) { Chips(seat) }
                    }
                }
            }
        }
    }
}

/** 점수(넘치면 글자를 0.6배까지 줄인다 — 아이폰 `minimumScaleFactor(0.6)`). */
@Composable
private fun Score(seat: MahjongStateSeat, size: Int) {
    var scale by remember(seat.score) { mutableStateOf(1f) }
    Text(
        GamesMahjongText.score(seat.score), style = TextStyle(fontSize = (size * scale).sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TNUM),
        color = Color.White, maxLines = 1, softWrap = false,
        onTextLayout = { if (it.didOverflowWidth && scale > 0.6f) scale = maxOf(0.6f, scale - 0.1f) },
    )
}

@Composable
private fun Chips(seat: MahjongStateSeat) {
    GamesMahjongChip(GamesMahjongText.wind(seat.wind), GamesMahjongPalette.secondary)
    if (seat.isDealer == true) GamesMahjongChip(GamesMahjongText.dealerChip, AingTheme.colors.pending)
    if (seat.riichi == true) GamesMahjongChip(GamesMahjongText.riichiChip, GamesMahjongPalette.accent)
    if (seat.away == true) GamesMahjongChip(GamesMahjongText.autoChip, AingTheme.colors.danger)
}

/** 작은 칩(글자 + 색). */
@Composable
fun GamesMahjongChip(text: String, tint: Color, modifier: Modifier = Modifier) {
    Text(
        text, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = tint, maxLines = 1,
        modifier = modifier.clip(CircleShape).background(tint.copy(alpha = 0.14f)).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

// MARK: - 내 시계(맥 `MahjongMyClock` 과 같은 판정)

internal object GamesMahjongMyClock {
    data class Window(val started: com.yehsung.aingcheck.core.wire.SwiftDate, val bankMs: Int, val isCall: Boolean)

    fun window(store: MahjongStore): Window? {
        // '넉넉히' 연습판은 결정 시계 칸이 0 이다 — 링 · 막대 · 경고를 모두 숨긴다.
        if (store.isPractice && store.practice?.timed == false) return null
        return when (val d = store.myDecision) {
            is MahjongDecision.Turn -> {
                // 리치 자동 쯔모기리 차례(고를 것이 없다)는 시계를 그리지 않는다.
                val nb = d.notBeforeMs
                if (nb != null && d.deadlineMs <= nb) return null
                val started = store.localDate(d.startedMs) ?: return null
                Window(started, d.bankMs, false)
            }
            is MahjongDecision.Call -> {
                if (d.answered != null) return null
                val started = store.localDate(d.startedMs) ?: return null
                Window(started, d.bankMs, true)
            }
            null -> null
        }
    }
}

/** 내 카드 링 — 5초를 줄이고, 다 쓰면 주황 "예비 N". */
@Composable
private fun ClockRing(store: MahjongStore, diameter: Dp) {
    val window = GamesMahjongMyClock.window(store) ?: return
    rememberTick(500)
    val left = MahjongClock.remaining(window.started, window.bankMs, store.clock())
    val inBank = left.baseLeft <= 0
    val fraction = (if (inBank) left.bankLeft / maxOf(1.0, MahjongClock.bankFullMs / 1000.0) else left.baseLeft / (MahjongClock.baseMs / 1000.0)).coerceIn(0.0, 1.0)
    val pending = AingTheme.colors.pending
    Box(Modifier.size(diameter), contentAlignment = Alignment.BottomCenter) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = 3.dp.toPx()
            drawCircle(Color.White.copy(alpha = 0.12f), radius = size.minDimension / 2 - stroke / 2, style = Stroke(stroke))
            drawArc(
                if (inBank) pending else GamesMahjongPalette.accent, -90f, (360 * fraction).toFloat(), false,
                topLeft = Offset(stroke / 2, stroke / 2), size = Size(size.width - stroke, size.height - stroke), style = Stroke(stroke, cap = StrokeCap.Round),
            )
        }
        if (inBank) {
            Text(
                "${GamesMahjongText.reserve} ${ceil(left.bankLeft).toInt()}", fontSize = 8.sp, fontWeight = FontWeight.ExtraBold, color = Color.White,
                modifier = Modifier.offset(y = 6.dp).clip(CircleShape).background(pending).padding(horizontal = 3.dp),
            )
        }
    }
}

// MARK: - 펠트

/** 펠트 — 강 · 상대 손 띠 · 가운데 판을 펠트 좌표 그대로 그리고 scale 로 줄인다. 입력 없음. */
@Composable
private fun FeltView(store: MahjongStore, payload: MahjongStatePayload, scale: Float) {
    val mySeat = payload.mySeat ?: 0
    val lastDiscarder = payload.events?.lastOrNull { it.kind == "discard" }?.seat
    val tiles = remember(payload, scale) {
        val out = mutableListOf<GamesMahjongStripTile>()
        for (compass in MahjongCompass.entries) {
            val number = MahjongSeatCompass.seat(compass, mySeat)
            val seat = payload.seats?.firstOrNull { it.seatNo == number } ?: continue
            out += GamesMahjongFeltGeometry.river(seat.discards ?: emptyList(), compass, highlightLast = lastDiscarder == seat.seatNo)
            if (compass != MahjongCompass.bottom) out += GamesMahjongFeltGeometry.handStrip(seat.handCount ?: 0, seat.melds ?: emptyList(), compass)
        }
        out
    }
    val accessibility = (payload.seats ?: emptyList()).joinToString(", ") { seat ->
        "${if (seat.seatNo == mySeat) "나" else seat.user?.displayName ?: "?"} 버림패 ${seat.discards?.size ?: 0}장"
    }
    val feltW = GamesMahjongFeltLayout.felt.width
    val feltH = GamesMahjongFeltLayout.felt.height
    Box(Modifier.size((feltW * scale).dp, (feltH * scale).dp)) {
        Canvas(Modifier.fillMaxSize()) {
            val r = 18 * scale * density
            drawRoundRect(GamesMahjongPalette.felt, cornerRadius = CornerRadius(r))
            drawRoundRect(GamesMahjongPalette.rim, topLeft = Offset(1.dp.toPx(), 1.dp.toPx()), size = Size(size.width - 2.dp.toPx(), size.height - 2.dp.toPx()), cornerRadius = CornerRadius(r), style = Stroke(2.dp.toPx()))
        }
        val density = androidx.compose.ui.platform.LocalDensity.current.density
        GamesMahjongTileStrip(
            tiles.map { t -> GamesMahjongScaledTile(t, Rect(t.rect.left * scale * density, t.rect.top * scale * density, t.rect.right * scale * density, t.rect.bottom * scale * density)) },
            Modifier.fillMaxSize(), cornerLabels = store.aids.cornerLabels, accessibilityText = accessibility,
        )
        val c = GamesMahjongFeltLayout.center
        Box(Modifier.offset((c.left * scale).dp, (c.top * scale).dp).size((GamesMahjongFeltLayout.centerSide * scale).dp)) {
            CenterBoard(payload, scale)
        }
    }
}

/** 가운데 판 — 국 이름 · 본장 · 공탁 · 남은 패 · 도라 5칸 · 네 변의 바람 · 리치봉 · 차례 빛줄. */
@Composable
private fun CenterBoard(payload: MahjongStatePayload, scale: Float) {
    val match = payload.match
    val mySeat = payload.mySeat ?: 0
    val side = GamesMahjongFeltLayout.centerSide * scale
    val shape = RoundedCornerShape(10.dp)
    Box(Modifier.fillMaxSize().clip(shape).background(GamesMahjongPalette.board).border(1.5.dp, GamesMahjongPalette.boardRim, shape), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(GamesMahjongText.roundName(match?.round, match?.handNo), fontSize = 14.sp, fontWeight = FontWeight.ExtraBold, color = GamesMahjongPalette.glyph, maxLines = 1)
            Text(GamesMahjongText.honba(match?.honba, match?.kyotaku), fontSize = 8.sp, fontWeight = FontWeight.SemiBold, color = GamesMahjongPalette.glyph, maxLines = 1)
            Text(GamesMahjongText.wall(match?.wallRemaining), style = TextStyle(fontSize = 8.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM), color = GamesMahjongPalette.glyph, maxLines = 1)
            val open = match?.doraIndicators ?: emptyList()
            val tw = MahjongTileSize.smallMeld.width * scale * 0.95f
            val th = MahjongTileSize.smallMeld.height * scale * 0.95f
            val density = androidx.compose.ui.platform.LocalDensity.current.density
            val dora = (0 until 5).map { index ->
                val face = if (index < open.size) MahjongTileFace.of(open[index]) else MahjongTileFace.Back
                GamesMahjongScaledTile(
                    GamesMahjongStripTile(face, MahjongTileSize.smallMeld, originX = 0f, originY = 0f),
                    Rect(index * (tw + 1.5f) * density, 0f, (index * (tw + 1.5f) + tw) * density, th * density),
                )
            }
            GamesMahjongTileStrip(dora, Modifier.padding(top = 1.dp).size(((tw + 1.5f) * 5).dp, th.dp), cornerLabels = false, accessibilityText = "도라 표시패 ${open.size}장")
        }
        for (compass in MahjongCompass.entries) Edge(payload, compass, side, mySeat)
    }
}

@Composable
private fun Edge(payload: MahjongStatePayload, compass: MahjongCompass, side: Float, mySeat: Int) {
    val number = MahjongSeatCompass.seat(compass, mySeat)
    val seat = payload.seats?.firstOrNull { it.seatNo == number }
    val isTurn = payload.match?.phase == "turn" && payload.match?.turnSeat == number
    val angle = 90f * MahjongTileArtModel.rotation(compass)
    val pending = AingTheme.colors.pending
    val danger = AingTheme.colors.danger
    Box(Modifier.size(side.dp).rotate(angle)) {
        if (isTurn) Box(Modifier.align(Alignment.BottomCenter).offset(y = (-1).dp).width((side * 0.9f).dp).height(3.dp).clip(CircleShape).background(GamesMahjongPalette.accent))
        if (seat?.wind != null) {
            Text(
                GamesMahjongText.windGlyphs[windIndex(seat.wind)], fontSize = 9.sp, fontWeight = FontWeight.ExtraBold,
                color = if (seat.isDealer == true) pending else GamesMahjongPalette.glyph,
                modifier = Modifier.align(Alignment.BottomStart).offset(x = 4.dp, y = (-1).dp),
            )
        }
        if (seat?.riichi == true) {
            Box(Modifier.align(Alignment.BottomCenter).offset(x = (side * 0.2f).dp, y = (-5).dp).width((side * 0.32f).dp).height(3.5.dp).clip(CircleShape).background(Color(0.92f, 0.90f, 0.86f)), contentAlignment = Alignment.Center) {
                Box(Modifier.size(2.5.dp).clip(CircleShape).background(danger))
            }
        }
    }
}

private fun windIndex(wire: String?): Int = when (wire) {
    "S" -> 1
    "W" -> 2
    "N" -> 3
    else -> 0
}

// MARK: - 손

/** 손패(id 순) · 쯔모패(띄움) · 부로(오른쪽 끝). 두 번 눌러 버리기가 폰 기본이다(한 번 = 들기 · 미리보기). */
@Composable
private fun HandView(store: MahjongStore, payload: MahjongStatePayload, tileHeight: Float) {
    var selected by remember { mutableStateOf<MahjongTile?>(null) }
    LaunchedEffect(store.decisionKey) { selected = null }
    val turn = store.myDecision as? MahjongDecision.Turn
    val isAway = payload.myAway != null || payload.mySeatRow?.away == true
    val allowed: Set<MahjongTile>? = turn?.let { (if (store.riichiArmed) it.riichi else it.discard).toSet() }
    val tileW = tileHeight * MahjongTileSize.hand.width / MahjongTileSize.hand.height
    val hand = (payload.myHand ?: emptyList()).sorted()
    val drawn = payload.myDrawn
    val painter = rememberMahjongTilePainter()
    fun tap(tile: MahjongTile, can: Boolean) {
        if (isAway) {
            store.scope.launch { store.comeBack() }
            return
        }
        if (!can || store.isWorking) return
        if (GamesMahjongPhoneAids.twoTap(store) && selected != tile) {
            selected = tile
            return
        }
        selected = null
        store.scope.launch { store.discard(tile) }
    }
    Column(Modifier.fillMaxSize().testTag(MahjongTableTags.HAND), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        StatusLine(store, payload, selected, Modifier.height(16.dp))
        Row(Modifier.height(tileHeight.dp).fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
            @Composable
            fun TileButton(tile: MahjongTile) {
                val can = allowed?.contains(tile) ?: false
                val state = if (allowed == null || tile in allowed) MahjongTileState.normal else MahjongTileState.disabled
                GamesMahjongTileView(
                    MahjongTileFace.of(tile),
                    Modifier.offset(y = if (selected == tile) (-6).dp else 0.dp).testTag(MahjongTableTags.handTile(tile.id))
                        .clickable(role = Role.Button) { tap(tile, can) },
                    size = MahjongTileSize.hand, state = state, cornerLabels = store.aids.cornerLabels, display = DpSize(tileW.dp, tileHeight.dp), painter = painter,
                )
            }
            hand.forEach { TileButton(it) }
            if (drawn != null) {
                Spacer(Modifier.width(8.dp))
                TileButton(drawn)
            }
            Spacer(Modifier.weight(1f).width(6.dp))
            Melds(store, payload, tileHeight * 0.74f)
        }
    }
}

@Composable
private fun Melds(store: MahjongStore, payload: MahjongStatePayload, tileHeight: Float) {
    val melds = payload.mySeatRow?.melds ?: emptyList()
    if (melds.isEmpty()) return
    val w = tileHeight * MahjongTileSize.meld.width / MahjongTileSize.meld.height
    val painter = rememberMahjongTilePainter()
    Row(Modifier.semantics { contentDescription = "내 울음 ${melds.size}" }, horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.Bottom) {
        for (meld in melds.reversed()) {
            Row(verticalAlignment = Alignment.Bottom) {
                meld.tiles.forEachIndexed { index, tile ->
                    val closedEnd = meld.type == "ankan" && (index == 0 || index == meld.tiles.size - 1)
                    val sideways = meld.called != null && tile == meld.called
                    GamesMahjongTileView(
                        if (closedEnd) MahjongTileFace.Back else MahjongTileFace.of(tile), size = MahjongTileSize.meld, rotation = if (sideways) 1 else 0,
                        cornerLabels = false, display = if (sideways) DpSize(tileHeight.dp, w.dp) else DpSize(w.dp, tileHeight.dp), painter = painter,
                    )
                }
            }
        }
    }
}

/** 상태 줄: 자리 비움 · 알림 · 리치 무장 · 들어 올린 패 미리보기 · 쿠이카에 · 기다리는 패 · 후리텐. */
@Composable
private fun StatusLine(store: MahjongStore, payload: MahjongStatePayload, preview: MahjongTile?, modifier: Modifier) {
    val colors = AingTheme.colors
    val turn = store.myDecision as? MahjongDecision.Turn
    // 연습판은 서버 문과 상관없다 — 로비가 남긴 '곧 열려요'는 판 위에 띄우지 않는다.
    val tableNotice = store.notice?.takeIf { it != MahjongNoticeText.practiceIdleCallHint && !(store.isPractice && it == MahjongNoticeText.unavailable) }
    val away = payload.myAway != null || payload.mySeatRow?.away == true
    val line = when {
        away -> MahjongNoticeText.away
        tableNotice != null -> tableNotice
        store.riichiArmed -> GamesMahjongText.riichiArmedHint
        preview != null && turn != null && preview in turn.discard -> previewLine(payload, preview)
        turn != null && payload.mySeatRow?.riichi != true && payload.mySeatRow?.melds?.isNotEmpty() == true &&
            turn.discard.size < (payload.myHand ?: emptyList()).size + (if (payload.myDrawn != null) 1 else 0) -> GamesMahjongText.kuikaeHint
        !payload.myWaits.isNullOrEmpty() -> "${GamesMahjongText.waitsTitle} " + payload.myWaits!!.joinToString(" · ") {
            "${MahjongTileArtModel.koreanName(it)}×${MahjongVisibleTiles.unseen(it, payload)}"
        }
        turn != null && GamesMahjongPhoneAids.twoTap(store) -> GamesMahjongPhoneText.twoTapHint
        else -> " "
    }
    val color = when {
        payload.myAway != null || tableNotice != null -> colors.pending
        store.riichiArmed -> GamesMahjongPalette.accent
        else -> Color.White
    }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (!payload.myFuriten.isNullOrEmpty()) GamesMahjongChip(GamesMahjongText.furitenChip, colors.danger)
        Text(line, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** "이 패를 버리면 → 텐파이 · 3만×2" — 내 손으로만(샹텐 숫자는 보이지 않는다). */
private fun previewLine(payload: MahjongStatePayload, tile: MahjongTile): String {
    val all = ((payload.myHand ?: emptyList()) + listOfNotNull(payload.myDrawn)).toMutableList()
    all.remove(tile)
    val melds = payload.mySeatRow?.melds?.size ?: 0
    val waits = MahjongHand.waits(MahjongTiles.counts34(all), melds)
    if (waits.isEmpty()) return "이 패를 버리면 → 아직 텐파이 아님 · 한 번 더 누르면 버려요"
    return "이 패를 버리면 → 텐파이 · " + waits.joinToString(" · ") { "${MahjongTileArtModel.koreanName(it)}×${MahjongVisibleTiles.unseen(it, payload)}" }
}

// MARK: - 보조 · 동작

@Composable
private fun AidsRow(store: MahjongStore) {
    var open by remember { mutableStateOf(false) }
    val aids = store.aids
    val on = listOf(aids.autoWin, aids.noCalls, aids.tsumogiri).count { it }
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier.fillMaxSize().clip(CircleShape).border(1.dp, Color.White.copy(alpha = 0.2f), CircleShape).clickable(role = Role.Button) { open = true },
            contentAlignment = Alignment.Center,
        ) {
            Text(if (on > 0) "${GamesMahjongPhoneText.aidsTitle} $on" else GamesMahjongPhoneText.aidsTitle, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = GamesMahjongPalette.secondary)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            @Composable
            fun Toggle(title: String, value: Boolean, set: (Boolean) -> Unit) {
                DropdownMenuItem(
                    text = { Text(title) },
                    trailingIcon = { Switch(checked = value, onCheckedChange = set) },
                    onClick = { set(!value) },
                )
            }
            Toggle(GamesMahjongText.aidAutoWin, aids.autoWin) { store.aids = store.aids.copy(autoWin = it) }
            Toggle(GamesMahjongText.aidNoCalls, aids.noCalls) { store.aids = store.aids.copy(noCalls = it) }
            Toggle(GamesMahjongText.aidTsumogiri, aids.tsumogiri) { store.aids = store.aids.copy(tsumogiri = it) }
            Toggle(GamesMahjongPhoneText.aidTwoTap, aids.twoClickDiscard) { store.aids = store.aids.copy(twoClickDiscard = it) }
            Toggle(GamesMahjongPhoneText.aidCorner, aids.cornerLabels) { store.aids = store.aids.copy(cornerLabels = it) }
        }
    }
}

private sealed interface CallButtonPlan {
    data object None : CallButtonPlan
    data class Send(val tiles: List<MahjongTile>) : CallButtonPlan
    data class Choose(val options: List<List<MahjongTile>>) : CallButtonPlan
}

private fun plan(kind: MahjongClaimKind, call: MahjongDecision.Call): CallButtonPlan {
    val options = MahjongStore.options(kind, call)
    return when (options.size) {
        0 -> CallButtonPlan.None
        1 -> CallButtonPlan.Send(options[0])
        else -> CallButtonPlan.Choose(options)
    }
}

/** 동작 열: 자리 비움 = [돌아왔어요] · 내 차례 = [쯔모][리치][깡][구종구패] · 울기 = [론] [퐁][깡][치] [넘기기](+ 내 시계 막대). */
@Composable
private fun ActionsView(store: MahjongStore, payload: MahjongStatePayload) {
    var choiceKind by remember { mutableStateOf<MahjongClaimKind?>(null) }
    var kanOpen by remember { mutableStateOf(false) }
    LaunchedEffect(store.decisionKey) {
        choiceKind = null
        kanOpen = false
    }
    val isAway = payload.myAway != null || payload.mySeatRow?.away == true
    val busy = store.isWorking || store.isAnsweringCall
    val colors = AingTheme.colors
    @Composable
    fun Button(title: String, tint: Color, filled: Boolean = true, height: Dp = 36.dp, enabled: Boolean = true, tag: String = title, action: () -> Unit) {
        val on = !busy && enabled
        Box(
            Modifier.fillMaxWidth().height(height).clip(CircleShape).background(if (filled) tint else Color.Transparent)
                .border(1.dp, if (filled) Color.Transparent else tint.copy(alpha = 0.8f), CircleShape)
                .clickable(enabled = on, role = Role.Button, onClick = action).alpha(if (on) 1f else 0.5f).testTag(MahjongTableTags.action(tag)),
            contentAlignment = Alignment.Center,
        ) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = if (filled) Color.White else tint, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    @Composable
    fun CallTilesButton(title: String?, tiles: List<MahjongTile>, action: () -> Unit) {
        val painter = rememberMahjongTilePainter()
        Row(
            Modifier.fillMaxWidth().height(36.dp).clip(CircleShape).background(colors.working).clickable(enabled = !busy, role = Role.Button, onClick = action)
                .alpha(if (busy) 0.5f else 1f).semantics { contentDescription = (listOf(title ?: GamesMahjongText.chi) + tiles.map { MahjongTileFace.of(it).spokenName }).joinToString(" ") },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterHorizontally),
        ) {
            if (title != null) Text(title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
            tiles.forEach { GamesMahjongTileView(MahjongTileFace.of(it), size = MahjongTileSize.smallMeld, cornerLabels = false, display = DpSize(17.dp, 23.dp), painter = painter) }
        }
    }
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (isAway) {
            Text(GamesMahjongText.awayHint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.pending)
            rememberTick(500)
            val ready = store.localDate(payload.myAway?.backReadyMs)
            val wait = ready?.let { ceil(it.timeIntervalSince(store.clock())).toInt() } ?: 0
            Button(if (wait > 0) GamesMahjongText.backIn(wait) else GamesMahjongText.comeBack, colors.pending, height = 48.dp, enabled = wait <= 0, tag = "comeBack") {
                store.scope.launch { store.comeBack() }
            }
            return@Column
        }
        when (val d = store.myDecision) {
            is MahjongDecision.Turn -> {
                val kans: List<Pair<List<MahjongTile>, Boolean>> = d.ankan.map { it to true } + d.kakan.map { listOf(it) to false }
                if (kanOpen && kans.size > 1) {
                    kans.forEach { (tiles, isAnkan) ->
                        Button("${GamesMahjongText.kan} ${MahjongTileArtModel.koreanName(tiles[0].kind)}", colors.working) {
                            kanOpen = false
                            store.scope.launch { if (isAnkan) store.ankan(tiles) else store.kakan(tiles[0]) }
                        }
                    }
                    Button(GamesMahjongText.cancel, GamesMahjongPalette.secondary, filled = false) { kanOpen = false }
                } else {
                    if (d.tsumo) Button(GamesMahjongText.tsumo, colors.pending, tag = "tsumo") { store.scope.launch { store.declareTsumo() } }
                    if (d.riichi.isNotEmpty()) {
                        if (store.riichiArmed) Button(GamesMahjongText.cancel, GamesMahjongPalette.accent, filled = false, tag = "riichiCancel") { store.cancelRiichi() }
                        else Button(GamesMahjongText.riichi, GamesMahjongPalette.accent, tag = "riichi") { store.armRiichi() }
                    }
                    if (kans.isNotEmpty()) {
                        Button(if (kans.size > 1) GamesMahjongText.kanMore else GamesMahjongText.kan, colors.working, tag = "kan") {
                            if (kans.size > 1) {
                                kanOpen = true
                            } else {
                                val (tiles, isAnkan) = kans[0]
                                store.scope.launch { if (isAnkan) store.ankan(tiles) else store.kakan(tiles[0]) }
                            }
                        }
                    }
                    if (d.kyuushu) Button(GamesMahjongText.kyuushu, GamesMahjongPalette.secondary, filled = false, tag = "kyuushu") { store.scope.launch { store.declareKyuushu() } }
                }
            }
            is MahjongDecision.Call -> if (d.answered == null) {
                if (store.notice == MahjongNoticeText.practiceIdleCallHint) {
                    Text(MahjongNoticeText.practiceIdleCallHint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.pending, maxLines = 2)
                } else {
                    CallClockBar(store, Modifier.fillMaxWidth().height(4.dp))
                }
                val kind = choiceKind
                val choose = kind?.let { plan(it, d) } as? CallButtonPlan.Choose
                if (kind != null && choose != null) {
                    choose.options.forEach { pair ->
                        CallTilesButton(null, pair) {
                            choiceKind = null
                            store.scope.launch { store.call(kind, pair) }
                        }
                    }
                    Button(GamesMahjongText.cancel, GamesMahjongPalette.secondary, filled = false) { choiceKind = null }
                } else {
                    if (d.ron) Button(GamesMahjongText.ron, colors.pending, tag = "ron") { store.scope.launch { store.call(MahjongClaimKind.ron, emptyList()) } }
                    when (val p = plan(MahjongClaimKind.pon, d)) {
                        is CallButtonPlan.Send -> Button(GamesMahjongText.pon, colors.working, tag = "pon") { store.scope.launch { store.call(MahjongClaimKind.pon, p.tiles) } }
                        is CallButtonPlan.Choose -> Button("${GamesMahjongText.pon} ▸", colors.working, tag = "pon") { choiceKind = MahjongClaimKind.pon }
                        CallButtonPlan.None -> Unit
                    }
                    when (val p = plan(MahjongClaimKind.minkan, d)) {
                        is CallButtonPlan.Send -> Button(GamesMahjongText.kan, colors.working, tag = "minkan") { store.scope.launch { store.call(MahjongClaimKind.minkan, p.tiles) } }
                        is CallButtonPlan.Choose -> Button("${GamesMahjongText.kan} ▸", colors.working, tag = "minkan") { choiceKind = MahjongClaimKind.minkan }
                        CallButtonPlan.None -> Unit
                    }
                    when (val p = plan(MahjongClaimKind.chi, d)) {
                        is CallButtonPlan.Send -> CallTilesButton(GamesMahjongText.chi, p.tiles) { store.scope.launch { store.call(MahjongClaimKind.chi, p.tiles) } }
                        is CallButtonPlan.Choose -> Button("${GamesMahjongText.chi} ▸", colors.working, tag = "chi") { choiceKind = MahjongClaimKind.chi }
                        CallButtonPlan.None -> Unit
                    }
                    Button(GamesMahjongText.pass, GamesMahjongPalette.secondary, filled = false, tag = "pass") { store.scope.launch { store.passCall() } }
                }
            }
            null -> Unit
        }
    }
}

/** 울기 프롬프트 위 얇은 막대(내 시계). */
@Composable
private fun CallClockBar(store: MahjongStore, modifier: Modifier) {
    val window = GamesMahjongMyClock.window(store) ?: return
    rememberTick(250)
    val left = MahjongClock.remaining(window.started, window.bankMs, store.clock())
    val inBank = left.baseLeft <= 0
    val fraction = (if (inBank) left.bankLeft / (MahjongClock.bankFullMs / 1000.0) else left.baseLeft / (MahjongClock.baseMs / 1000.0)).coerceIn(0.0, 1.0)
    val pending = AingTheme.colors.pending
    Canvas(modifier) {
        drawRoundRect(Color.White.copy(alpha = 0.12f), cornerRadius = CornerRadius(size.height / 2))
        drawRoundRect(if (inBank) pending else GamesMahjongPalette.accent, size = Size(size.width * fraction.toFloat(), size.height), cornerRadius = CornerRadius(size.height / 2))
    }
}

// MARK: - 방 띠

/** 연습 중 "방 3/4 · 남은 7:12 · [방 보기]" — 넷째가 앉으면 "4명이 모였어요 [시작]"(방장). */
@Composable
private fun RoomBand(store: MahjongStore, band: MahjongRoomBand) {
    val colors = AingTheme.colors
    rememberTick(1000)
    Row(
        Modifier.fillMaxSize().clip(CircleShape).background(GamesMahjongPalette.panel)
            .border(if (band.readyToStart) 2.dp else 1.dp, if (band.readyToStart) colors.working else GamesMahjongPalette.accent.copy(alpha = 0.6f), CircleShape)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (band.readyToStart) {
            Text(GamesMahjongText.roomBandReady, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = colors.working)
        } else {
            val seconds = maxOf(0, band.expiresAt.timeIntervalSince(store.clock()).toInt())
            Text(GamesMahjongText.roomBand(band.joined, seconds), style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = TNUM), color = Color.White)
        }
        Spacer(Modifier.weight(1f))
        if (band.readyToStart && store.isHost) {
            Text(
                GamesMahjongText.start, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = if (store.canStart && !store.isWorking) GamesMahjongPalette.accent else GamesMahjongPalette.secondary,
                modifier = Modifier.clickable(enabled = store.canStart && !store.isWorking, role = Role.Button) { store.scope.launch { store.start() } },
            )
        }
        Text(GamesMahjongText.roomViewButton, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = GamesMahjongPalette.accent, modifier = Modifier.clickable(role = Role.Button) { store.showRoom() })
    }
}

internal fun centered(text: String) = TextAlign.Center
