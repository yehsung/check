// 원본: Sources/check/RummyTileView.swift:76-215 (RummyTileMark · RummyTileView · RummyJokerFace · RummyTileBack) @ 1a5eeca6
//
// 아잉 큐브 타일 그림. **우리 그림이다** — 상표 게임의 타일 모양·조커 그림(별·웃는 얼굴)·서체를 따라 하지 않는다.
//   · 몸체 = 밝은 크림-라벤더 그라데이션, 둥근 모서리, 아래 베벨(입체 '큐브').
//   · 숫자 = 굵은 글자, **밝은 타일 위 진한 4색**(값은 core RummyTilePalette). 다크 모드에서도 같다(실물 타일이다 — 테마 토큰이 아니다).
//   · 숫자 아래 **작은** 모양 표식 A● B▲ C■ D◆ — 색약 보조(색만으로 가르지 않는다). 글리프가 아니라 도형으로 그린다.
//   · 조커 = 아잉이 얼굴 + 네 색 점(어느 색이든 된다).
//   · 크기: 모든 치수가 [RummyTileSize] 에서 나온다 — 받침대 · 결과/규칙 · 판(캔버스 배율). 글자는 시스템 글자 크기를 따르지 않는다(타일이 크기를 쥔다).
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyCanvasSize
import com.yehsung.aingcheck.core.rules.rummy.RummyTilePalette
import com.yehsung.aingcheck.core.rules.rummy.RummyTileSize
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.ui.games.minigame.canvasFont
import com.yehsung.aingcheck.ui.games.minigame.kit.TNUM

/** 팔레트 값(0xRRGGBB) → 색. */
internal fun rummyColor(rgb: Int): Color = Color(0xFF000000L or rgb.toLong())

/** 타일 한 장. [highlighted] = 이번 차례에 낸 타일(노란 링) · [dimmed] = 끌려 나간 자리(흐리게). */
@Composable
fun GamesRummyTile(
    face: RummyFace,
    size: RummyTileSize,
    modifier: Modifier = Modifier,
    highlighted: Boolean = false,
    dimmed: Boolean = false,
) {
    val name = RummyTilePalette.accessibilityName(face)
    val tile = size
    Box(
        modifier
            .size(size.size.width.dp, size.size.height.dp)
            .then(if (dimmed) Modifier.alpha(0.28f) else Modifier)
            .clearAndSetSemantics { contentDescription = name }
            .drawBehind { drawTileBody(tile, highlighted) },
        contentAlignment = Alignment.TopCenter,
    ) {
        val color = face.color
        val number = face.number
        if (color != null && number != null) TileNumber(number, color, size) else JokerFace(size)
    }
}

@Composable
private fun TileNumber(number: Long, color: Long, size: RummyTileSize) {
    val ink = rummyColor(RummyTilePalette.ink(color))
    // dp → sp: 시스템 글자 크기를 무시한다(타일 안에 들어가야 한다).
    val font = with(LocalDensity.current) { size.numberFont.dp.toSp() }
    val line = with(LocalDensity.current) { (size.numberFont * 1.12).dp.toSp() }
    Column(
        Modifier.padding(top = size.topPadding.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(size.stackSpacing.dp),
    ) {
        Text(
            number.toString(),
            style = TextStyle(fontFamily = canvasFont(), fontSize = font, lineHeight = line, fontWeight = FontWeight.Black, fontFeatureSettings = TNUM),
            color = ink,
            maxLines = 1,
            softWrap = false,
        )
        Canvas(Modifier.size(size.markSize.dp)) { drawTileMark(color.toInt(), ink) }
    }
}

/** 조커 — 아잉이 얼굴 + 네 색 점. 그림을 못 읽으면 보라 원 안의 '아잉' 글자(상표 게임 조커 그림 금지). */
@Composable
private fun JokerFace(size: RummyTileSize) {
    val side = size.size.width * 0.8
    val dot = maxOf(2.4, size.size.width * 0.11)
    val art = LocalGamesRummyArt.current?.joker
    Column(
        Modifier.padding(top = size.topPadding.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy((size.stackSpacing * 1.4).dp),
    ) {
        if (art != null) {
            Image(art, contentDescription = null, modifier = Modifier.size(side.dp), filterQuality = FilterQuality.High)
        } else {
            val font = with(LocalDensity.current) { (side * 0.3).dp.toSp() }
            Box(Modifier.size(side.dp).background(rummyColor(RummyTilePalette.jokerFallback), CircleShape), contentAlignment = Alignment.Center) {
                Text("아잉", style = TextStyle(fontFamily = canvasFont(), fontSize = font, fontWeight = FontWeight.Black), color = Color.White, maxLines = 1, softWrap = false)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(maxOf(1.0, dot * 0.38).dp)) {
            for (index in RummyTilePalette.inks.indices) {
                Box(Modifier.size(dot.dp).background(rummyColor(RummyTilePalette.inks[index]), CircleShape))
            }
        }
    }
}

/** 엎어 놓은 타일 뒷면(상대 장수 표시용) — 라벤더 몸체 위 작은 분홍 점. 우리 그림. */
@Composable
fun GamesRummyTileBack(size: RummyCanvasSize = RummyCanvasSize(12.0, 17.0), modifier: Modifier = Modifier) {
    Canvas(modifier.size(size.width.dp, size.height.dp).clearAndSetSemantics { }) {
        val corner = CornerRadius(this.size.width * 0.25f)
        drawRoundRect(Color.Black.copy(alpha = 0.3f), topLeft = Offset(0f, 0.6f * density), size = this.size, cornerRadius = corner)
        drawRoundRect(Brush.verticalGradient(listOf(Color(0.62f, 0.56f, 0.98f), Color(0.42f, 0.35f, 0.86f))), cornerRadius = corner)
        drawRoundRect(Color.White.copy(alpha = 0.55f), cornerRadius = corner, style = Stroke(0.7f * density))
        drawCircle(Color(1.0f, 0.55f, 0.80f), radius = this.size.width * 0.16f)
    }
}

// MARK: - 그리기

private fun DrawScope.drawTileBody(tile: RummyTileSize, highlighted: Boolean) {
    val corner = CornerRadius(tile.corner.toFloat() * density)
    val bevel = tile.bevel.toFloat() * density
    // 그림자 — 흐림 없이 한 겹(판 타일이 100장 넘어도 층을 만들지 않는다).
    drawRoundRect(Color.Black.copy(alpha = 0.28f), topLeft = Offset(0f, 1f * density), size = size, cornerRadius = corner)
    drawRoundRect(rummyColor(RummyTilePalette.bevel), cornerRadius = corner)
    val bodySize = Size(size.width, (size.height - bevel).coerceAtLeast(1f))
    drawRoundRect(
        Brush.verticalGradient(listOf(rummyColor(RummyTilePalette.bodyTop), rummyColor(RummyTilePalette.bodyBottom)), endY = bodySize.height),
        size = bodySize,
        cornerRadius = corner,
    )
    drawRoundRect(Color.White.copy(alpha = 0.9f), size = bodySize, cornerRadius = corner, style = Stroke(0.8f * density))
    if (highlighted) {
        val ring = 2.5f * density
        drawRoundRect(
            rummyColor(RummyTilePalette.highlight),
            topLeft = Offset(-ring / 2, -ring / 2),
            size = Size(size.width + ring, size.height + ring),
            cornerRadius = CornerRadius(corner.x + ring / 2),
            style = Stroke(ring),
        )
    }
}

/** 색약 보조 표식 — A● B▲ C■ D◆. */
private fun DrawScope.drawTileMark(colorIndex: Int, ink: Color) {
    val w = size.width
    val h = size.height
    when (colorIndex) {
        0 -> drawCircle(ink)
        1 -> drawPath(Path().apply { moveTo(w / 2, 0f); lineTo(w, h); lineTo(0f, h); close() }, ink)
        2 -> drawRect(ink, topLeft = Offset(w * 0.06f, h * 0.06f), size = Size(w * 0.88f, h * 0.88f))
        else -> drawPath(Path().apply { moveTo(w / 2, 0f); lineTo(w, h / 2); lineTo(w / 2, h); lineTo(0f, h / 2); close() }, ink)
    }
}
