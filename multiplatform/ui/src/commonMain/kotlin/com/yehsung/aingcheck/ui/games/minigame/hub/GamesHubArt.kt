// 원본: Sources/CheckMobileKit/Games/GamesTab.swift @ 3bd04bd (GamesTileArt · GamesGameIconSquare · GamesChessTabThumbnail · GamesTetrisDuelTabThumbnail · gamesHex)
// 원본: Sources/CheckMobileKit/Games/GamesComponents.swift @ 3bd04bd (GamesWoodThumbnail — 오목 카드 썸네일)
// 원본: Sources/CheckMobileKit/Games/GamesGomokuBoardCanvas.swift:19-21·128-143 @ 3bd04bd (나무·선 색 · 돌 그리기 — 썸네일이 쓰는 몫만)
//
// 게임 탭 그림(시안 px 색 — 뜻 색이 아니라 무대 그림 전용이다). 캔버스 무대처럼 밤 톤이라 라이트·다크와 무관하게 같다.
// 조각 색·우물 잉크는 **판과 같은 표**(core TetrisPalette)에서 온다 — 타일만 다른 색이면 열고 나서 다른 게임처럼 보인다.
package com.yehsung.aingcheck.ui.games.minigame.hub

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisPalette
import com.yehsung.aingcheck.ui.games.minigame.FlappyAingImage
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.tetris.TetrisDuelPalette
import com.yehsung.aingcheck.ui.games.tetris.TetrisPaletteColors
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon

/** 시안 px 색(무대 그림 전용 — 뜻 색이 아니다). */
internal fun gamesHex(value: Long): Color =
    Color(((value shr 16) and 0xFF) / 255f, ((value shr 8) and 0xFF) / 255f, (value and 0xFF) / 255f)

private val tileStars: List<Pair<Float, Float>> = listOf(
    0.12f to 14f, 0.30f to 26f, 0.52f to 10f, 0.70f to 22f, 0.86f to 12f, 0.22f to 88f, 0.78f to 92f, 0.92f to 70f,
)

/** 미니게임 타일 그림(시안 `.b-art-timing` · `.b-art-flappy` · 테트리스). 접근성에서 숨긴다(타일 글자가 말한다). */
@Composable
fun MiniGameTileArt(kind: MiniGameKind, art: MiniGameArt, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.clipToBounds().clearAndSetSemantics { }) {
        val w = maxWidth
        when (kind) {
            MiniGameKind.timingBar -> Canvas(Modifier.fillMaxSize()) { drawTimingTile(this) }
            MiniGameKind.flappy -> {
                Canvas(Modifier.fillMaxSize()) { drawFlappyTile(this) }
                FlappyAingImage(art.flappySide, 52.dp, Modifier.offset(w * 0.24f, 34.dp))
            }
            MiniGameKind.tetris -> Canvas(Modifier.fillMaxSize()) { drawTetrisTile(this) }
            // 길건너 아잉이(v0.3.67)는 폰 타일 목록(phoneCases)에 없어 여기 오지 않는다 — 빠짐없는 when 을 지키는 빈 그림.
            MiniGameKind.crossy -> Unit
        }
    }
}

private fun DrawScope.starDots(count: Int) {
    for ((x, y) in tileStars.take(count)) {
        drawCircle(Color.White.copy(alpha = 0.7f), radius = 1.dp.toPx(), center = Offset(size.width * x + 1.dp.toPx(), y.dp.toPx() + 1.dp.toPx()))
    }
}

private val zone = Color(1f, 210 / 255f, 120 / 255f)

private fun drawTimingTile(scope: DrawScope) = with(scope) {
    drawRect(
        Brush.radialGradient(
            0f to gamesHex(0x7A4A6B), 0.45f to gamesHex(0x3A2856), 1f to gamesHex(0x1D1733),
            center = Offset(size.width * 0.5f, size.height * 1.1f), radius = maxOf(size.width, size.height) * 0.95f,
        ),
    )
    starDots(tileStars.size)
    val trackWidth = maxOf(0f, size.width - 28.dp.toPx())
    val left = 14.dp.toPx()
    val top = 52.dp.toPx()
    val h = 14.dp.toPx()
    val radius = CornerRadius(7.dp.toPx())
    drawRoundRect(gamesHex(0x120E1E), Offset(left, top), Size(trackWidth, h), radius)
    drawRoundRect(Color.White.copy(alpha = 0.12f), Offset(left, top), Size(trackWidth, h), radius, style = Stroke(1.dp.toPx()))
    val zoneLeft = left + trackWidth * 0.58f
    drawRoundRect(
        Brush.horizontalGradient(listOf(zone.copy(alpha = 0.2f), zone.copy(alpha = 0.85f), zone.copy(alpha = 0.2f)), startX = zoneLeft, endX = zoneLeft + trackWidth * 0.16f),
        Offset(zoneLeft, top), Size(trackWidth * 0.16f, h), radius,
    )
    val markerX = left + trackWidth * 0.41f
    val markerH = 26.dp.toPx()
    drawCircle(Color.White.copy(alpha = 0.25f), radius = 6.dp.toPx(), center = Offset(markerX + 1.5.dp.toPx(), top + h / 2))
    drawRoundRect(Color.White, Offset(markerX, top + h / 2 - markerH / 2), Size(3.dp.toPx(), markerH), CornerRadius(1.5.dp.toPx()))
}

/** 기둥(시안 px — 타일 폭 182 기준을 폭 비율로): (왼쪽 비율, 위, 높이). */
private val tilePipes: List<Triple<Float, Float, Float>> = listOf(
    Triple(0.615f, -4f, 38f), Triple(0.615f, 84f, 40f), Triple(0.879f, -4f, 18f), Triple(0.879f, 66f, 60f),
)

private fun drawFlappyTile(scope: DrawScope) = with(scope) {
    drawRect(Brush.verticalGradient(0f to gamesHex(0x1F4A63), 0.7f to gamesHex(0x2E6F73), 1f to gamesHex(0x3C8A6C)))
    for ((x, top, height) in tilePipes) {
        val left = size.width * x
        val w = 26.dp.toPx()
        drawRoundRect(
            Brush.horizontalGradient(0f to gamesHex(0x3FA66A), 0.45f to gamesHex(0x6BD58F), 1f to gamesHex(0x3A9660), startX = left, endX = left + w),
            Offset(left, top.dp.toPx()), Size(w, height.dp.toPx()), CornerRadius(3.dp.toPx()),
        )
    }
}

/** 타일 한 장의 판(6×7 칸): 아래 두 줄은 쌓인 조각, 위 한 줄은 **떨어지는 중인 I** — 정지 그림 한 장으로 "움직이는 게임"이라고 말한다. */
private val tetrisTileCells: List<Triple<Int, Int, TetrisGame.Piece>> = listOf(
    Triple(1, 1, TetrisGame.Piece.i), Triple(2, 1, TetrisGame.Piece.i), Triple(3, 1, TetrisGame.Piece.i), Triple(4, 1, TetrisGame.Piece.i),
    Triple(0, 5, TetrisGame.Piece.l), Triple(1, 5, TetrisGame.Piece.l), Triple(2, 5, TetrisGame.Piece.o), Triple(3, 5, TetrisGame.Piece.o), Triple(5, 5, TetrisGame.Piece.t),
    Triple(0, 6, TetrisGame.Piece.l), Triple(1, 6, TetrisGame.Piece.z), Triple(2, 6, TetrisGame.Piece.o), Triple(3, 6, TetrisGame.Piece.o), Triple(4, 6, TetrisGame.Piece.s), Triple(5, 6, TetrisGame.Piece.t),
)

private fun drawTetrisTile(scope: DrawScope) = with(scope) {
    drawRect(Brush.verticalGradient(0f to gamesHex(0x151A3A), 0.55f to gamesHex(0x24204E), 1f to gamesHex(0x3A2A5E)))
    starDots(5)
    val cell = 14.dp.toPx()
    val wellW = cell * 6
    val wellH = cell * 7
    val originX = (size.width - wellW) / 2
    val originY = 7.dp.toPx()
    val corner = CornerRadius(4.dp.toPx())
    drawRoundRect(TetrisPaletteColors.wellColor.copy(alpha = TetrisPalette.wellOpacity.toFloat()), Offset(originX, originY), Size(wellW, wellH), corner)
    drawRoundRect(Color.White.copy(alpha = 0.18f), Offset(originX, originY), Size(wellW, wellH), corner, style = Stroke(1.dp.toPx()))
    val half = 0.5.dp.toPx()
    for ((x, y, piece) in tetrisTileCells) {
        drawRoundRect(
            TetrisPaletteColors.color(piece), Offset(originX + x * cell + half, originY + y * cell + half), Size(cell - 2 * half, cell - 2 * half),
            CornerRadius(2.dp.toPx()),
        )
    }
}

/** "오늘 내 순위" 행 앞 30 둥근 네모 — 타일과 같은 무대 색 · 흰 기호(플래피는 아잉 옆모습). 게임마다 자기 타일 무대 색이다. */
@Composable
fun GamesGameIconSquare(kind: MiniGameKind, art: MiniGameArt, modifier: Modifier = Modifier) {
    val colors = when (kind) {
        MiniGameKind.timingBar -> listOf(gamesHex(0x4B3274), gamesHex(0x8A4F74))
        MiniGameKind.flappy -> listOf(gamesHex(0x1F4A63), gamesHex(0x3C8A6C))
        MiniGameKind.tetris -> listOf(gamesHex(0x24204E), gamesHex(0x3A2A5E))
        MiniGameKind.crossy -> listOf(gamesHex(0x2E5A2A), gamesHex(0x4F8A3C)) // 폰에 없음(phoneCases)
    }
    Box(
        modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(Brush.linearGradient(colors)).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        when (kind) {
            MiniGameKind.timingBar -> AingIcon(AppIcon.Timer, contentDescription = null, size = 16.dp, tint = Color.White)
            MiniGameKind.flappy -> FlappyAingImage(art.flappySide, 24.dp)
            // 타일 그림과 같은 두 색(I 하늘 · O 노랑)으로 작은 조각 하나 — 기호를 쓰면 30 에서 오목 입구(3×3 격자)와 실루엣이 겹친다.
            MiniGameKind.tetris -> Row(horizontalArrangement = Arrangement.spacedBy(1.5.dp), verticalAlignment = Alignment.Top) {
                Box(Modifier.size(5.dp, 14.dp).background(TetrisPaletteColors.color(TetrisGame.Piece.i), RoundedCornerShape(1.5.dp)))
                Box(Modifier.offset(y = 2.dp).size(10.dp).background(TetrisPaletteColors.color(TetrisGame.Piece.o), RoundedCornerShape(1.5.dp)))
            }
            MiniGameKind.crossy -> AingIcon(AppIcon.DirectionsWalk, contentDescription = null, size = 16.dp, tint = Color.White)
        }
    }
}

/** 썸네일 판(60 · 둥글기 20%) — 세 카드가 한 열로 선다. */
@Composable
private fun Thumbnail(side: Dp, modifier: Modifier, draw: DrawScope.() -> Unit) {
    Canvas(modifier.size(side).clearAndSetSemantics { }) {
        val clip = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(0f, 0f, size.width, size.height, CornerRadius(size.width * 0.2f))) }
        clipPath(clip) { draw() }
    }
}

private val woodLight = Color(0.88f, 0.73f, 0.49f)
private val woodDark = Color(0.79f, 0.62f, 0.38f)
private val woodLine = Color(0.30f, 0.21f, 0.12f)

/** 돌 하나(오목 판 그림과 같은 레시피 — 그림자 · 하이라이트 방사형). */
private fun DrawScope.drawStone(center: Offset, radius: Float, black: Boolean) {
    drawCircle(Color.Black.copy(alpha = 0.25f), radius, Offset(center.x + radius * 0.06f, center.y + radius * 0.14f))
    val highlight = Offset(center.x - radius * 0.35f, center.y - radius * 0.4f)
    if (black) {
        drawCircle(Brush.radialGradient(listOf(Color(0.45f, 0.45f, 0.45f), Color(0.05f, 0.05f, 0.05f)), highlight, radius * 1.5f), radius, center)
    } else {
        drawCircle(Brush.radialGradient(listOf(Color.White, Color(0.80f, 0.80f, 0.80f)), highlight, radius * 1.6f), radius, center)
        drawCircle(Color.Black.copy(alpha = 0.2f), radius, center, style = Stroke(0.8f * density))
    }
}

/** 나무판 썸네일(시안 `.b-woodthumb` 60) — 판 그림과 같은 나무·돌. */
@Composable
fun GamesWoodThumbnail(modifier: Modifier = Modifier, side: Dp = 60.dp) = Thumbnail(side, modifier) {
    drawRect(Brush.linearGradient(listOf(woodLight, woodDark), Offset.Zero, Offset(size.width, size.height)))
    val lines = 11
    val inset = size.width * 0.12f
    val cell = (size.width - inset * 2) / (lines - 1)
    for (i in 0 until lines) {
        val o = inset + i * cell
        drawLine(woodLine.copy(alpha = 0.55f), Offset(o, inset), Offset(o, size.width - inset), 0.5f * density)
        drawLine(woodLine.copy(alpha = 0.55f), Offset(inset, o), Offset(size.width - inset, o), 0.5f * density)
    }
    for ((x, y, black) in listOf(Triple(5, 5, true), Triple(6, 4, false), Triple(4, 6, true), Triple(6, 6, false), Triple(5, 3, true))) {
        drawStone(Offset(inset + x * cell, inset + y * cell), cell * 0.48f, black)
    }
}

/** 체스판 썸네일 60 — 나무판 썸네일과 같은 변·같은 둥글기. 흑·백 한 점씩(두 사람이 두는 판). */
@Composable
fun GamesChessTabThumbnail(modifier: Modifier = Modifier, side: Dp = 60.dp) = Thumbnail(side, modifier) {
    val light = Color(0.93f, 0.88f, 0.78f)
    val dark = Color(0.54f, 0.38f, 0.27f)
    drawRect(light)
    val cell = size.width / 8
    for (rank in 0 until 8) for (file in 0 until 8) if ((rank + file) % 2 == 1) {
        drawRect(dark, Offset(file * cell, rank * cell), Size(cell, cell))
    }
    for ((file, rank, white) in listOf(Triple(3, 6, true), Triple(4, 4, true), Triple(4, 1, false), Triple(2, 3, false))) {
        val c = Offset((file + 0.5f) * cell, (rank + 0.5f) * cell)
        drawCircle(if (white) Color.White else Color(0.12f, 0.12f, 0.12f), cell * 0.3f, c)
        drawCircle(Color.Black.copy(alpha = 0.25f), cell * 0.3f, c, style = Stroke(0.5f * density))
    }
}

/**
 * 1:1 테트리스 썸네일 60 — 우물 **둘**(1:1 이라는 사실을 정지 그림 한 장으로). 왼쪽은 떨어지는 I + 쌓인 두 줄, 오른쪽은 **회색 방해 줄**이
 * 올라온 판(공격형 — 판과 같은 토큰 TetrisDuelPalette.garbageColor). 솔로 타일 그림은 건드리지 않았다(설계서 P1).
 */
@Composable
fun GamesTetrisDuelTabThumbnail(modifier: Modifier = Modifier, side: Dp = 60.dp) = Thumbnail(side, modifier) {
    drawRect(Brush.linearGradient(listOf(gamesHex(0x1D2148), gamesHex(0x3A2A5E)), Offset.Zero, Offset(size.width, size.height)))
    val cell = size.width / 11
    val origins = listOf(0.09f to 0.14f, 0.545f to 0.14f)
    val blocks: List<List<Triple<Int, Int, TetrisGame.Piece?>>> = listOf(
        listOf(
            Triple(0, 0, TetrisGame.Piece.i), Triple(1, 0, TetrisGame.Piece.i), Triple(2, 0, TetrisGame.Piece.i), Triple(3, 0, TetrisGame.Piece.i),
            Triple(0, 5, TetrisGame.Piece.l), Triple(1, 5, TetrisGame.Piece.o), Triple(2, 5, TetrisGame.Piece.o), Triple(0, 6, TetrisGame.Piece.l),
            Triple(1, 6, TetrisGame.Piece.o), Triple(2, 6, TetrisGame.Piece.o), Triple(3, 6, TetrisGame.Piece.t),
        ),
        listOf(
            Triple(2, 3, TetrisGame.Piece.s), Triple(3, 3, TetrisGame.Piece.s), Triple(1, 4, TetrisGame.Piece.s), Triple(2, 4, TetrisGame.Piece.s),
            Triple(0, 5, TetrisGame.Piece.z), Triple(1, 5, TetrisGame.Piece.z), Triple(2, 5, TetrisGame.Piece.t), Triple(0, 6, null), Triple(1, 6, null),
            Triple(2, 6, null), Triple(3, 6, null),
        ),
    )
    origins.forEachIndexed { index, (ox, oy) ->
        val left = ox * size.width
        val top = oy * size.height
        val corner = CornerRadius(2 * density)
        drawRoundRect(TetrisPaletteColors.wellColor.copy(alpha = TetrisPalette.wellOpacity.toFloat()), Offset(left, top), Size(cell * 4, cell * 7), corner)
        drawRoundRect(Color.White.copy(alpha = 0.18f), Offset(left, top), Size(cell * 4, cell * 7), corner, style = Stroke(0.5f * density))
        for ((x, y, piece) in blocks[index]) {
            drawRoundRect(
                piece?.let { TetrisPaletteColors.color(it) } ?: TetrisDuelPalette.garbageColor,
                Offset(left + x * cell + 0.5f * density, top + y * cell + 0.5f * density), Size(cell - density, cell - density), CornerRadius(density),
            )
        }
    }
}
