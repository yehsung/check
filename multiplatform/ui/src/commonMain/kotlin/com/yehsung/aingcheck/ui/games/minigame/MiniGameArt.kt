// 원본: Sources/CheckMobileKit/Games/GamesMascotArt.swift @ 3bd04bd (플래피 아잉 두 장 — 옆모습 · 게임오버 시무룩 정면)
// 원본: Sources/CheckMobileKit/Components/MobileArt.swift @ 3bd04bd (MobileArt.flappyAing = Resources/Art/aing-side.png)
//
// 미니게임 그림 창구. 미니게임 캐릭터는 **아잉 고정**이다(사용자 결정 2026-09-13 — 착용 캐릭터를 따르지 않는다).
//  · 옆모습: 맥 원본 `Sources/CheckMobileKit/Resources/Art/aing-side.png` 를 ui Gradle Sync 가 files/art/ 로 싣는다(git 사본 0, A-X18 —
//    Sync 목록에 이 이름을 더하는 줄은 조정자 패치 01). 이 빌드에 없으면 null → 캔버스가 근무 초록 원으로 대신 그린다(Swift 와 같은 폴백).
//  · 시무룩 정면: 이미 실린 아잉 초상 negative(files/characters/aing/portrait-negative.png — 맥 aing-negative.png 192px 그대로).
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.ImageBitmap
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.CharacterExpression

/** 플래피 그림 한 쌍. 시험·스냅숏은 맥 원본 파일을 직접 읽어 넘긴다(리소스 Sync 유무와 무관하게 같은 픽셀). */
@Immutable
data class MiniGameArt(val flappySide: ImageBitmap?, val flappyNegative: ImageBitmap?) {
    companion object {
        /** Compose 리소스 자리(ui Sync — 조정자 패치 01 이 Sources/CheckMobileKit/Resources/Art/aing-side.png 를 싣는다). */
        const val FLAPPY_SIDE_PATH: String = "files/art/aing-side.png"

        /** 맥 원본(저장소 뿌리 기준) — 시험이 이 파일을 직접 읽는다. */
        const val FLAPPY_SIDE_SOURCE: String = "Sources/CheckMobileKit/Resources/Art/aing-side.png"

        val FLAPPY_NEGATIVE_PATH: String = CharacterArt.portraitPath("aing", CharacterExpression.Negative)

        /** 맥 원본(저장소 뿌리 기준) — 시무룩 정면. */
        const val FLAPPY_NEGATIVE_SOURCE: String = "Sources/check/Resources/aing-negative.png"

        val empty: MiniGameArt = MiniGameArt(null, null)
    }
}

/** 미니게임 그림(비동기 — 처음 한 번은 빈 그림). */
@Composable
fun rememberMiniGameArt(): MiniGameArt {
    val side by produceState<ImageBitmap?>(null) { value = CharacterArt.decode(MiniGameArt.FLAPPY_SIDE_PATH) }
    val negative by produceState<ImageBitmap?>(null) { value = CharacterArt.decode(MiniGameArt.FLAPPY_NEGATIVE_PATH) }
    return MiniGameArt(side, negative)
}
