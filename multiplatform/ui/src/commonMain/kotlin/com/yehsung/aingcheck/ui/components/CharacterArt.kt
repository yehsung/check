// 원본: Sources/CheckMobileShared/AingCharacterArt.swift @ 1b8260d (초상 이름 `<id>-<표정>` · 192px · 케이크 둘 0.3.66 · knownIDs = 번들에 실린 초상)
// 원본: Sources/CheckMobileKit/Components/MobileArt.swift @ 862be0f (루비·무대 그림 창구)
// 원본: Sources/CheckCore/AingSticker.swift @ 862be0f (이모티콘 그림 이름 `sticker-<rawValue>.png`)
//
// 그림 창구. 그림 파일은 **git 에 사본을 두지 않는다**(A-X18): ui 빌드의 Gradle Sync 작업이 맥 원본을 빌드 폴더로 모아
// Compose 리소스 files/ 아래에 싣는다(조정자 패치 — ui/build.gradle.kts `aingcheckSyncCharacterArt`).
//   Sources/check/Characters/<id>/{manifest.json, portrait-neutral.png, portrait-negative.png} → files/characters/<id>/…
//   Sources/check/Resources/<aing·aing_gold·aing_rainbow·aing_cake_strawberry·aing_cake_choco>-<표정>.png → files/characters/<id>/portrait-<표정>.png
//   Sources/CheckMobileKit/Resources/Art/{ruby,ruby-48,ruby-96,stage-<id>-neutral}.png    → files/art/…
//   Sources/CheckCore/Resources/Stickers/sticker-<이름>.png(0.3.62 아잉이 이모티콘)           → files/stickers/…
// 스프라이트 아틀라스(atlas.png)는 싣지 않는다 — 살아 있는 캐릭터는 구운 자산(W0-d·W5)이 맡는다.
package com.yehsung.aingcheck.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.LocalDensity
import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.stores.me.DrawableCharacterSource
import com.yehsung.aingcheck.ui.resources.Res
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.jetbrains.compose.resources.decodeToImageBitmap

object CharacterArt {
    /**
     * Gradle Sync 가 싣는 초상의 **원천 목록**(아잉 가족 먼저, 나머지 이름순 — Sync 규칙과 시험이 쓴다). 상점 능력 번호(K9)는 이 손 목록이
     * 아니라 **실제로 실린 파일 목록**([PORTRAIT_INDEX_PATH] → [drawableCharacterIDs])에서 파생한다.
     */
    val portraitIds: List<String> = listOf(
        "aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco",
        "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel",
    )

    /** 매니페스트가 있는 스프라이트 캐릭터(Sources/check/Characters/<id>). */
    val spriteIds: List<String> = listOf("fox", "ghost", "jellyfish", "robot", "shiba", "squirrel")

    fun portraitPath(id: String, expression: CharacterExpression): String = "files/characters/$id/portrait-${expression.fileSuffix}.png"

    fun manifestPath(id: String): String = "files/characters/$id/manifest.json"

    fun rubyPath(pointSize: Float, density: Float): String = "files/art/${RubyGlyph.assetName(pointSize, density)}.png"

    fun stagePath(id: String): String = "files/art/stage-$id-neutral.png"

    /** 이모티콘 그림이 있는 맥 원본 폴더(저장소 뿌리 기준). Gradle Sync 가 이 폴더의 sticker-*.png 를 files/stickers 로 싣는다. */
    const val STICKER_SOURCE_DIR = "Sources/CheckCore/Resources/Stickers"

    /** 이모티콘 그림(이름 = Swift `AingSticker.rawValue`, 예: "joy"). 전선 토큰·판정은 W1-c 글자 규칙 몫이다. */
    fun stickerPath(name: String): String = "files/stickers/sticker-$name.png"

    /** Sync 가 실제로 실은 초상 파일 목록(한 줄에 `<id>-<표정>` — ui/build.gradle.kts `aingcheckSyncCharacterArt` 의 doLast 가 쓴다). */
    const val PORTRAIT_INDEX_PATH = "files/characters/portraits.txt"

    /**
     * 이 빌드에 실린 초상 이름들(`<id>-<표정>`). 목록을 못 읽으면 빈 목록 — 그 호출의 번호는 0(옛 모양)으로 내려간다(보수적인 쪽으로 틀린다).
     * 나 탭 스토어(`MeStore.drawableCharacterIDs`)는 빈 집합을 쥐지 않고 다음 호출에서 다시 읽는다 — 한 번의 읽기 실패가 실행 내내 뽑기·케이크
     * 선물을 숨기지 않게(W2-c 6차 검증 지적). 읽어 낸 집합은 스토어가 실행 동안 쥔다(번들은 바뀌지 않는다).
     */
    suspend fun portraitResourceNames(): List<String> =
        readBytesOrNull(PORTRAIT_INDEX_PATH)?.decodeToString()?.lines()?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()

    /** K9: 초상 두 장(neutral · negative)이 **다** 실린 캐릭터 → 상점 능력 번호의 재료(W1-c `ShopWire.drawableCharacterIDs`). */
    suspend fun drawableCharacterIDs(): Set<String> = ShopWire.drawableCharacterIDs(portraitResourceNames())

    /** 나 탭 스토어(W2-c `MeStore`)에 꽂는 재료 — 조립(K11)이 넘긴다. */
    val drawableCharacterSource: DrawableCharacterSource = DrawableCharacterSource { drawableCharacterIDs() }

    /** 리소스 바이트(없으면 null — 이 빌드에 그림이 빠졌다는 뜻이다). */
    @OptIn(ExperimentalResourceApi::class)
    suspend fun readBytesOrNull(path: String): ByteArray? = runCatching { Res.readBytes(path) }.getOrNull()

    @OptIn(ExperimentalResourceApi::class)
    suspend fun decode(path: String): ImageBitmap? = readBytesOrNull(path)?.let { runCatching { it.decodeToImageBitmap() }.getOrNull() }
}

/** 초상 그림(비동기 — 처음 한 번은 null). */
@Composable
fun rememberPortraitArt(id: String, expression: CharacterExpression): ImageBitmap? {
    val path = CharacterArt.portraitPath(id, expression)
    val art by produceState<ImageBitmap?>(null, path) { value = CharacterArt.decode(path) }
    return art
}

/** 무대 그림: 웃는 얼굴이고 무대 고해상이 있으면 420px, 아니면 초상. */
@Composable
fun rememberStageArt(id: String, expression: CharacterExpression, pointSize: Float): ImageBitmap? {
    val density = LocalDensity.current.density
    val path = if (CharacterStageMetrics.prefersStageArt(id, expression, pointSize, density)) CharacterArt.stagePath(id)
    else CharacterArt.portraitPath(id, expression)
    val art by produceState<ImageBitmap?>(null, path) { value = CharacterArt.decode(path) }
    return art
}

/** 크기에 맞는 루비 그림. */
@Composable
fun rememberRubyArt(pointSize: Float): ImageBitmap? {
    val path = CharacterArt.rubyPath(pointSize, LocalDensity.current.density)
    val art by produceState<ImageBitmap?>(null, path) { value = CharacterArt.decode(path) }
    return art
}
