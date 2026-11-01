// 원본: Sources/check/RummyArt.swift:88 (RummyArt 저장소) · :229-369 (RummyTableSurface · RummyFeltPaint · RummyFeltFallback · RummyRackStand · RummyRackFallback) @ 1a5eeca6
//
// 아잉 큐브 받침대·펠트 그림. 사용자가 **다시 고를 수 있게** 앱에 굽지 않는다(메모리 assets-users-iterate-must-not-be-baked-in):
//   1) 디스크 캐시(운영 Storage `game-art/rummy/{rack,table}.png` 에서 받은 것).
//   2) 번들 사본(`files/art/rummy-{rack,table}.png` — ui Gradle Sync 가 맥 원본을 git 사본 없이 싣는다).
//   3) 둘 다 없으면 Compose 로 그린 폴백(남색 유광 + 분홍 테두리, 남보라 펠트).
// 화면이 처음 뜰 때 한 번 조건부 요청으로 캐시를 덮는다(200 = 바꿈 · 304 = 그대로 · 404 = 캐시 지우고 번들로 · 그 밖 = 그대로 — 판정은 core RummyArtRules).
// ui 는 HTTP 를 만들지 않는다(구조 시험 R3c) — 받기·디스크는 [GamesRummyArtSource] 로 조립이 넣는다. 넣지 않으면(시험·스냅숏) 망·디스크를 타지 않는다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.rummy.RummyArtKind
import com.yehsung.aingcheck.core.rules.rummy.RummyArtOutcome
import com.yehsung.aingcheck.core.rules.rummy.RummyArtRules
import com.yehsung.aingcheck.core.rules.rummy.RummyRackLayout
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.CharacterExpression
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.jetbrains.compose.resources.decodeToImageBitmap
import kotlin.math.min
import kotlin.math.roundToInt

/** 조건부 요청 재료. */
data class GamesRummyArtValidators(val etag: String?, val lastModified: String?)

/** 받기 답. */
class GamesRummyArtResponse(val status: Int, val bytes: ByteArray, val etag: String?, val lastModified: String?)

/** 받기·디스크 문(Android 조립 AndroidRummyArtSource). 실패는 null 이고 던지지 않는다(취소만 다시 던진다). */
interface GamesRummyArtSource {
    suspend fun readCached(kind: RummyArtKind): ByteArray?

    suspend fun readValidators(kind: RummyArtKind): GamesRummyArtValidators?

    suspend fun fetch(kind: RummyArtKind, validators: GamesRummyArtValidators?): GamesRummyArtResponse?

    suspend fun writeCache(kind: RummyArtKind, bytes: ByteArray, validators: GamesRummyArtValidators)

    suspend fun clearCache(kind: RummyArtKind)
}

/** 아잉 큐브 화면 아래 어디서든 그림을 읽는 자리. 없으면 폴백을 그린다. */
val LocalGamesRummyArt = staticCompositionLocalOf<GamesRummyArt?> { null }

/** 그림 저장소(앱에 하나 — 조립이 만들어 화면에 넘긴다). 값은 Compose 상태라 받기가 끝나면 그림이 저절로 바뀐다. */
@Stable
class GamesRummyArt(
    private val source: GamesRummyArtSource? = null,
    private val decode: suspend (ByteArray) -> ImageBitmap? = { decodeRummyArt(it) },
    private val bundled: suspend (RummyArtKind) -> ImageBitmap? = { CharacterArt.decode(bundlePath(it)) },
    private val jokerFace: suspend () -> ImageBitmap? = { CharacterArt.decode(CharacterArt.portraitPath("aing", CharacterExpression.Neutral)) },
) {
    var rack: ImageBitmap? by mutableStateOf(null)
        private set
    var table: ImageBitmap? by mutableStateOf(null)
        private set

    /** 조커 얼굴(마스코트 아잉이 — 상표 게임 조커 그림 금지). 못 읽으면 타일이 글자로 그린다. */
    var joker: ImageBitmap? by mutableStateOf(null)
        private set

    private var prepared = false
    private var refreshStarted = false

    /** 캐시 → 번들 순으로 올린다(한 번만). 화면이 처음 뜰 때 부른다. */
    suspend fun prepare() {
        if (prepared) return
        prepared = true
        joker = jokerFace()
        for (kind in RummyArtKind.entries) install(kind, cached(kind) ?: bundled(kind))
    }

    /** 조건부 요청으로 캐시를 덮는다(앱 실행에 한 번). 중간에 취소되면 다음 화면이 다시 한다. */
    suspend fun refreshIfNeeded() {
        val source = source ?: return
        if (refreshStarted) return
        refreshStarted = true
        try {
            for (kind in RummyArtKind.entries) refresh(source, kind)
        } catch (error: CancellationException) {
            refreshStarted = false
            throw error
        }
    }

    private suspend fun cached(kind: RummyArtKind): ImageBitmap? {
        val bytes = source?.readCached(kind) ?: return null
        val image = decode(bytes) ?: return null
        return if (RummyArtRules.isAcceptable(kind, image.width, image.height)) image else null
    }

    private suspend fun refresh(source: GamesRummyArtSource, kind: RummyArtKind) {
        val hasCache = source.readCached(kind) != null
        val validators = if (hasCache) source.readValidators(kind) else null
        val response = source.fetch(kind, validators) ?: return
        val image = if (response.status == 200 && response.bytes.size <= RummyArtRules.maxBytes) decode(response.bytes) else null
        when (RummyArtRules.outcome(response.status, response.bytes.size, image?.let { it.width to it.height }, kind)) {
            RummyArtOutcome.keep -> Unit
            RummyArtOutcome.revert -> {
                source.clearCache(kind)
                if (hasCache) install(kind, bundled(kind))
            }
            RummyArtOutcome.replace -> {
                source.writeCache(kind, response.bytes, GamesRummyArtValidators(response.etag, response.lastModified))
                install(kind, image)
            }
        }
    }

    private fun install(kind: RummyArtKind, image: ImageBitmap?) {
        when (kind) {
            RummyArtKind.rack -> rack = image
            RummyArtKind.table -> table = image
        }
    }

    companion object {
        /** 번들 사본 자리(ui Gradle Sync). */
        fun bundlePath(kind: RummyArtKind): String = "files/art/${kind.bundleName}.png"
    }
}

@OptIn(ExperimentalResourceApi::class)
private suspend fun decodeRummyArt(bytes: ByteArray): ImageBitmap? =
    withContext(Dispatchers.Default) { runCatching { bytes.decodeToImageBitmap() }.getOrNull() }

// MARK: - 펠트

private val feltTop = Color(0.20f, 0.17f, 0.38f)
private val feltBottom = Color(0.13f, 0.11f, 0.27f)
private val feltGlow = Color(0.33f, 0.27f, 0.56f)
private val rimPink = Color(1.0f, 0.50f, 0.80f)
private val rimViolet = Color(0.62f, 0.42f, 1.0f)

/** 펠트 천만(테두리·아잉이 없이) — 로비 탁자 · 결과 최종 판이 판 화면과 **같은 천**을 쓴다(그림 → 그린 폴백 순서도 같다). */
@Composable
fun GamesRummyFeltPaint(modifier: Modifier = Modifier) {
    val felt = LocalGamesRummyArt.current?.table
    Canvas(modifier.clearAndSetSemantics { }) {
        if (felt != null) drawFeltTiles(felt) else drawFeltFallback()
    }
}

/** 받은 그림이 1024px 이어도 같은 결로 — 512dp 한 칸으로 반복한다. */
private fun DrawScope.drawFeltTiles(felt: ImageBitmap) {
    val cell = (RummyArtRules.feltTile.toFloat() * density).roundToInt().coerceAtLeast(1)
    var y = 0
    while (y < size.height) {
        var x = 0
        while (x < size.width) {
            drawImage(felt, dstOffset = IntOffset(x, y), dstSize = IntSize(cell, cell), filterQuality = FilterQuality.Medium)
            x += cell
        }
        y += cell
    }
}

private fun DrawScope.drawFeltFallback() {
    drawRect(Brush.verticalGradient(listOf(feltTop, feltBottom)))
    drawRect(Brush.radialGradient(listOf(feltGlow.copy(alpha = 0.55f), Color.Transparent), center, 420f * density))
}

/** 판 바닥 — 펠트 + 가장자리 어둡게 + 옅은 아잉이 + 분홍-보라 테두리. 크기는 부르는 쪽이 정한다. */
@Composable
fun GamesRummyTableSurface(modifier: Modifier = Modifier, cornerRadius: Dp = 18.dp) {
    val shape = RoundedCornerShape(cornerRadius)
    val face = LocalGamesRummyArt.current?.joker
    Box(
        modifier.clip(shape).border(1.5.dp, Brush.linearGradient(listOf(rimPink.copy(alpha = 0.55f), rimViolet.copy(alpha = 0.35f))), shape),
        contentAlignment = Alignment.Center,
    ) {
        GamesRummyFeltPaint(Modifier.fillMaxSize())
        // 가장자리를 눌러 가운데에 눈이 가게.
        Canvas(Modifier.fillMaxSize().clearAndSetSemantics { }) {
            val radius = 620f * density
            drawRect(
                Brush.radialGradient(
                    0f to Color.Transparent,
                    (120f / 620f) to Color.Transparent,
                    1f to Color.Black.copy(alpha = 0.38f),
                    center = center,
                    radius = radius,
                ),
            )
        }
        if (face != null) {
            Image(face, contentDescription = null, modifier = Modifier.size(120.dp).alpha(0.05f), filterQuality = FilterQuality.High)
        }
    }
}

// MARK: - 받침대

/**
 * 받침대 — 그림(3-슬라이스, 세로로 안 늘림) 또는 그린 폴백. 크기는 부르는 쪽이 정한다(폰은 [GamesRummyRackGeometry] 의 폭 · 높이).
 * 그림의 선반은 두 단이다 — 줄이 셋 이상 열리면 그림 대신 줄 수만큼 선반을 그린다.
 */
@Composable
fun GamesRummyRackStand(geometry: GamesRummyRackGeometry, modifier: Modifier = Modifier) {
    val art = LocalGamesRummyArt.current?.rack
    Canvas(modifier.clearAndSetSemantics { }) {
        val capPixels = if (art != null && geometry.rowCount <= RummyRackLayout.baseRows) RummyArtRules.rackCapPixels(art.width, art.height) else null
        if (art != null && capPixels != null) drawRackSlices(art, capPixels) else drawRackFallback(geometry)
    }
}

private fun DrawScope.drawRackSlices(art: ImageBitmap, capPixels: Int) {
    val height = size.height.roundToInt()
    val width = size.width.roundToInt()
    val cap = min(width / 2f, capPixels.toFloat() / art.height * height).roundToInt()
    val quality = FilterQuality.High
    // 가운데를 끝캡 밑으로 2dp 씩 더 깔아 이음매(가장자리 보간의 반투명 줄)가 안 보이게.
    val overlap = (2 * density).roundToInt()
    drawImage(
        art, IntOffset(capPixels, 0), IntSize(art.width - capPixels * 2, art.height),
        IntOffset(cap - overlap, 0), IntSize((width - cap * 2 + overlap * 2).coerceAtLeast(1), height), filterQuality = quality,
    )
    drawImage(art, IntOffset(0, 0), IntSize(capPixels, art.height), IntOffset(0, 0), IntSize(cap, height), filterQuality = quality)
    drawImage(art, IntOffset(art.width - capPixels, 0), IntSize(capPixels, art.height), IntOffset(width - cap, 0), IntSize(cap, height), filterQuality = quality)
}

/** 그림이 없을 때의 받침대 — 짙은 남색 유광 · 줄마다 선반 · 분홍 테두리(그림과 같은 색). */
private fun DrawScope.drawRackFallback(geometry: GamesRummyRackGeometry) {
    val corner = CornerRadius(14f * density)
    drawRoundRect(Brush.verticalGradient(listOf(Color(0.20f, 0.22f, 0.52f), Color(0.10f, 0.11f, 0.32f))), cornerRadius = corner)
    // 유광 — 위쪽 빛.
    drawRoundRect(
        Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.14f), Color.Transparent), endY = size.height * 0.35f),
        size = Size(size.width, size.height * 0.35f),
        cornerRadius = corner,
    )
    val shelfHeight = 5f * density
    val inset = 6f * density
    for (row in 0 until geometry.rowCount) {
        val y = (((geometry.rowTop(row) + geometry.tileSize.height).toFloat()) * density).coerceAtMost(size.height - shelfHeight)
        val topLeft = Offset(inset, y)
        val shelf = Size(size.width - inset * 2, shelfHeight)
        val round = CornerRadius(shelfHeight / 2)
        drawRoundRect(Brush.verticalGradient(listOf(Color(0.46f, 0.48f, 0.92f), Color(0.20f, 0.21f, 0.52f)), startY = y, endY = y + shelfHeight), topLeft, shelf, round)
        drawRoundRect(Brush.horizontalGradient(listOf(rimPink, rimViolet)), topLeft, shelf, round, alpha = 0.8f, style = Stroke(1f * density))
    }
    drawRoundRect(Brush.horizontalGradient(listOf(rimPink, rimViolet)), cornerRadius = corner, style = Stroke(2f * density))
}
