// 원본: 없음 — 오목·체스 화면 시험의 그림 출처(Android 호스트 — 저장소 원본을 BitmapFactory 로 동기 디코드)와 시험 테마 감싸개.
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.ImageBitmap
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.components.RubyGlyph
import com.yehsung.aingcheck.ui.theme.AingTheme
import java.io.File

/** 스냅숏 그림 출처 — 저장소 원본을 동기로(세 번 그려도 같은 픽셀). 초상 경로는 ui 빌드의 Sync 표와 같은 규칙이다. */
object TestBoardArt {
    private val aingFamily = setOf("aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco")
    private val cache = HashMap<String, ImageBitmap?>()

    fun portraitPath(id: String, expression: CharacterExpression): String =
        if (id in aingFamily) "Sources/check/Resources/$id-${expression.fileSuffix}.png" else "Sources/check/Characters/$id/portrait-${expression.fileSuffix}.png"

    private fun load(path: String): ImageBitmap? = cache.getOrPut(path) {
        if (File(AndroidSnapshots.repoRoot, path).isFile) AndroidSnapshots.repoImage(path) else null
    }

    val art: BoardGameArt = BoardGameArt(
        portrait = { id, expression -> load(portraitPath(id, expression)) ?: load(portraitPath(FALLBACK_CHARACTER_ID, expression)) },
        ruby = { size -> load("Sources/CheckMobileKit/Resources/Art/${RubyGlyph.assetName(size, AndroidSnapshots.DENSITY)}.png") },
    )
}

/** 시험 화면 감싸개 — 테마 + 동기 그림. */
@Composable
fun BoardTestTheme(dark: Boolean = false, content: @Composable () -> Unit) {
    AingTheme(dark = dark) {
        CompositionLocalProvider(LocalBoardGameArt provides TestBoardArt.art, content = content)
    }
}
