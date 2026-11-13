// 원본: Sources/CheckMobileKit/Games/GamesMahjongResult.swift @ 928d5562(폰 1.0.18 국 결과 · 판 결과) — Android 판 8
//
// 판 · 부 · 점수는 늘 서버 값이다. 국 결과는 확인 단추 없이 서버 시각으로 넘어간다(다음 국까지 N초). 더블론이면 화료자마다 넘긴다.
// 판 결과: 등수 · 최종 점수 · 루비 순수익(payout − stake) · [한 판 더] · [로비로]. 연습판은 루비 줄 없이 [다시 하기].
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileFace
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileSize
import com.yehsung.aingcheck.core.rules.mahjong.MahjongTileState
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongResultPaging
import com.yehsung.aingcheck.core.stores.mahjong.GamesMahjongText
import com.yehsung.aingcheck.core.stores.mahjong.MahjongHandResult
import com.yehsung.aingcheck.core.stores.mahjong.MahjongNoticeText
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStatePayload
import com.yehsung.aingcheck.core.stores.mahjong.MahjongStore
import com.yehsung.aingcheck.core.stores.mahjong.MahjongWinResult
import com.yehsung.aingcheck.core.stores.mahjong.createRoom
import com.yehsung.aingcheck.core.stores.mahjong.endPractice
import com.yehsung.aingcheck.core.stores.mahjong.restartPractice
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch
import kotlin.math.ceil

object MahjongResultTags {
    const val HAND = "mahjong.result.hand"
    const val MATCH = "mahjong.result.match"
    const val LOBBY = "mahjong.result.toLobby"
    const val REMATCH = "mahjong.result.rematch"
    const val AGAIN = "mahjong.result.practiceAgain"
    const val END = "mahjong.result.practiceEnd"
}

private fun seatName(payload: MahjongStatePayload, seatNo: Int?): String {
    val seat = seatNo?.let { n -> payload.seats?.firstOrNull { it.seatNo == n } } ?: return "?"
    if (seat.deleted == true) return GamesMahjongText.deletedChip
    return if (seatNo == payload.mySeat) "나" else seat.user?.displayName ?: "?"
}

@Composable
fun GamesMahjongHandResultCard(store: MahjongStore, payload: MahjongStatePayload, result: MahjongHandResult) {
    val nextHand = store.localDate(payload.match?.nextHandMs)
    rememberTick(500)
    val now = store.clock()
    val shape = RoundedCornerShape(14.dp)
    val pending = AingTheme.colors.pending
    Column(
        Modifier.fillMaxSize().clip(shape).background(GamesMahjongPalette.panel).border(2.dp, pending.copy(alpha = 0.6f), shape)
            .verticalScroll(rememberScrollState()).padding(12.dp).testTag(MahjongResultTags.HAND),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        val wins = result.wins ?: emptyList()
        if (wins.isNotEmpty()) {
            val index = GamesMahjongResultPaging.index(wins.size, nextHand, now)
            WinContent(payload, wins[index], index, wins.size)
        } else {
            DrawContent(payload, result)
        }
        Deltas(payload, result)
        if (nextHand != null) {
            Text(
                GamesMahjongText.nextHand(maxOf(0, ceil(nextHand.timeIntervalSince(now)).toInt())), style = TextStyle(fontSize = 12.sp, fontFeatureSettings = TNUM),
                color = GamesMahjongPalette.secondary, textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun WinContent(payload: MahjongStatePayload, win: MahjongWinResult, index: Int, count: Int) {
    val pending = AingTheme.colors.pending
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            if (win.fromSeat == null) "${seatName(payload, win.seat)} 쯔모" else "${seatName(payload, win.seat)} 론 ← ${seatName(payload, win.fromSeat)}",
            fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
        if (count > 1) GamesMahjongChip("${index + 1}/$count", GamesMahjongPalette.accent)
        Spacer(Modifier.weight(1f))
        Text(scoreLine(win), style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM), color = pending, maxLines = 1)
    }
    HandRow(win)
    val yaku = win.yaku ?: emptyList()
    yaku.chunked(2).forEach { pair ->
        Row(Modifier.fillMaxWidth()) {
            pair.forEach { item ->
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(MahjongNoticeText.yakuName(item.id), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    Text(if ((win.yakuman ?: 0) > 0) "역만" else "${item.han}판", style = TextStyle(fontSize = 13.sp, fontFeatureSettings = TNUM), color = GamesMahjongPalette.secondary)
                }
            }
            if (pair.size == 1) Spacer(Modifier.weight(1f))
        }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        val style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        if ((win.dora ?: 0) > 0) Text("도라 ${win.dora ?: 0}", style = style, color = GamesMahjongPalette.secondary)
        if ((win.aka ?: 0) > 0) Text("적도라 ${win.aka ?: 0}", style = style, color = GamesMahjongPalette.secondary)
        win.uraIndicators?.let { ura ->
            Text("뒷도라 ${win.ura ?: 0}", style = style, color = GamesMahjongPalette.secondary)
            val painter = rememberMahjongTilePainter()
            Row(horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                ura.forEach { GamesMahjongTileView(MahjongTileFace.of(it), size = MahjongTileSize.smallMeld, cornerLabels = false, display = DpSize(15.dp, 20.dp), painter = painter) }
            }
        }
        win.pao?.seat?.let { Text("책임 지불 ${seatName(payload, it)}", style = style, color = GamesMahjongPalette.secondary) }
    }
}

private fun scoreLine(win: MahjongWinResult): String {
    val parts = mutableListOf<String>()
    val yakuman = win.yakuman ?: 0
    if (yakuman > 0) {
        parts += if (yakuman > 1) "${yakuman}배 역만" else "역만"
    } else {
        parts += "${win.han ?: 0}판 ${win.fu ?: 0}부"
        GamesMahjongText.limitName(win.limit)?.let { parts += it }
    }
    parts += "${GamesMahjongText.grouped(win.total ?: 0)}점"
    return parts.joinToString(" · ")
}

/** 화료자 손 + 화료패(띄움) + 부로. */
@Composable
private fun HandRow(win: MahjongWinResult) {
    val hand = (win.hand ?: emptyList()).sorted().toMutableList()
    win.winTile?.let { hand.remove(it) }
    val painter = rememberMahjongTilePainter()
    val w = 22.dp
    val h = 30.dp
    Row(Modifier.semantics { contentDescription = "화료 손 ${win.hand?.size ?: 0}장" }, verticalAlignment = Alignment.Bottom) {
        hand.forEach { GamesMahjongTileView(MahjongTileFace.of(it), size = MahjongTileSize.result, cornerLabels = false, display = DpSize(w, h), painter = painter) }
        win.winTile?.let {
            Spacer(Modifier.width(6.dp))
            GamesMahjongTileView(MahjongTileFace.of(it), size = MahjongTileSize.result, state = MahjongTileState.highlighted, cornerLabels = false, display = DpSize(w, h), painter = painter)
        }
        (win.melds ?: emptyList()).forEach { meld ->
            Spacer(Modifier.width(6.dp))
            meld.tiles.forEach { GamesMahjongTileView(MahjongTileFace.of(it), size = MahjongTileSize.meld, cornerLabels = false, display = DpSize(w * 0.8f, h * 0.8f), painter = painter) }
        }
    }
}

@Composable
private fun DrawContent(payload: MahjongStatePayload, result: MahjongHandResult) {
    val reason = if (result.kind == "abortive") result.reason else if (!result.nagashi.isNullOrEmpty()) "nagashi" else result.reason ?: "exhaustive"
    Text(GamesMahjongText.handEnd(reason), fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
    val tenpai = result.tenpai ?: emptyList()
    if (tenpai.isEmpty()) {
        Text("모두 노텐", fontSize = 13.sp, color = GamesMahjongPalette.secondary)
    } else {
        val painter = rememberMahjongTilePainter()
        tenpai.forEach { row ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("${seatName(payload, row.seat)} 텐파이", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White, modifier = Modifier.width(90.dp), maxLines = 1)
                Row {
                    (row.hand ?: emptyList()).sorted().forEach { GamesMahjongTileView(MahjongTileFace.of(it), size = MahjongTileSize.smallMeld, cornerLabels = false, display = DpSize(15.dp, 20.dp), painter = painter) }
                }
            }
        }
    }
}

/** 점수 이동(자리마다 ±). */
@Composable
private fun Deltas(payload: MahjongStatePayload, result: MahjongHandResult) {
    val deltas = result.deltas ?: emptyList()
    val after = result.scoresAfter ?: emptyList()
    val colors = AingTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (seatNo in 0 until 4) {
            val delta = deltas.getOrNull(seatNo) ?: 0
            Column(
                Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).background(Color.White.copy(alpha = 0.06f)).padding(vertical = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                Text(seatName(payload, seatNo), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    GamesMahjongText.delta(delta), style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TNUM),
                    color = if (delta > 0) colors.working else if (delta < 0) colors.danger else GamesMahjongPalette.secondary,
                )
                Text(GamesMahjongText.score(after.getOrNull(seatNo)), style = TextStyle(fontSize = 11.sp, fontFeatureSettings = TNUM), color = GamesMahjongPalette.secondary)
            }
        }
    }
}

@Composable
fun GamesMahjongMatchResultCard(store: GamesStore, mahjong: MahjongStore, payload: MahjongStatePayload) {
    val seats = (payload.seats ?: emptyList()).sortedWith(compareBy({ it.finalRank ?: 9 }, { it.seatNo }))
    val stake = payload.match?.stake ?: 0
    val colors = AingTheme.colors
    val ruby = rememberRubyArt(13f)
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier.fillMaxSize().clip(shape).background(GamesMahjongPalette.panel).border(1.dp, Color.White.copy(alpha = 0.15f), shape).padding(14.dp)
            .testTag(MahjongResultTags.MATCH),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("판 결과", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
            Spacer(Modifier.weight(1f))
            Text(GamesMahjongText.matchEnd(payload.match?.endReason), fontSize = 12.sp, color = GamesMahjongPalette.secondary, maxLines = 2, textAlign = TextAlign.End)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            seats.forEach { seat ->
                val mine = seat.seatNo == payload.mySeat
                Row(
                    Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(10.dp))
                        .background(if (mine) GamesMahjongPalette.accent.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.06f)).padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(GamesMahjongText.rank(seat.finalRank), style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.ExtraBold, fontFeatureSettings = TNUM), color = Color.White, modifier = Modifier.width(40.dp), textAlign = TextAlign.Center)
                    val id = seat.user?.userId ?: "seat-${seat.seatNo}"
                    PersonAvatar(seat.user?.displayName ?: "?", id, 30.dp, url = seat.user?.avatarUrl, characterHint = seat.user?.character)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(if (mine) "나" else seat.user?.displayName ?: "?", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (seat.deleted == true) GamesMahjongChip(GamesMahjongText.deletedChip, colors.danger)
                        }
                        Text("${GamesMahjongText.grouped(seat.finalScore ?: seat.score ?: 0)}점", style = TextStyle(fontSize = 12.sp, fontFeatureSettings = TNUM), color = GamesMahjongPalette.secondary)
                    }
                    if (!mahjong.isPractice && payload.match?.isVoid != true) {
                        val net = (seat.payout ?: 0) - stake
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            RubyIcon(ruby, size = 13.dp)
                            Text(
                                GamesMahjongText.net(net), style = TextStyle(fontSize = 17.sp, fontFeatureSettings = TNUM),
                                color = if (net > 0) colors.working else if (net < 0) colors.danger else GamesMahjongPalette.secondary,
                            )
                        }
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (mahjong.isPractice) {
                PillButton(GamesMahjongText.practiceEnd, Modifier.weight(1f).testTag(MahjongResultTags.END), kind = PillKind.Gray, fillsWidth = true) { mahjong.endPractice() }
                PillButton(GamesMahjongText.practiceAgain, Modifier.weight(1f).testTag(MahjongResultTags.AGAIN), kind = PillKind.Filled, fillsWidth = true) { mahjong.restartPractice() }
            } else {
                PillButton(GamesMahjongText.toLobby, Modifier.weight(1f).testTag(MahjongResultTags.LOBBY), kind = PillKind.Gray, fillsWidth = true) {
                    store.mahjongDismissedMatchID = payload.match?.id
                }
                PillButton(
                    GamesMahjongText.rematch, Modifier.weight(1f).testTag(MahjongResultTags.REMATCH), kind = PillKind.Filled, fillsWidth = true,
                    enabled = !mahjong.isWorking && store.mahjongEntryBlock == null && mahjong.duelsEnabled,
                ) {
                    store.mahjongDismissedMatchID = payload.match?.id
                    mahjong.scope.launch { mahjong.createRoom() }
                }
            }
        }
    }
}

