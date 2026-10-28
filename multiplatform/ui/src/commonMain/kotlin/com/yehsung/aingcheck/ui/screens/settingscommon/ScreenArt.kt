// 원본: Sources/CheckMobileKit/Components/MobileArt.swift @ 3bd04bd (화면이 그림을 받는 창구 — 초상·무대·루비)
//
// W3-b 화면이 그림을 받는 **한 창구**. 앱은 [ScreenArt.Resources](Compose 리소스 — W1-e CharacterArt, 비동기 · 처음 한 장은 빈 칸),
// 스냅숏 시험은 저장소 원본을 **동기로** 읽어 넘긴다(비동기 그림은 세 장 렌더 사이에 늦게 와 '굳은 렌더'를 깨뜨린다 —
// 기억 imagerenderer-first-two-renders-differ). 화면은 그림을 직접 불러오지 않는다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.unit.Dp
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.rememberPortraitArt
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.components.rememberStageArt

/** 그림 창구. 없으면 null — 부품이 받침·링만 그린다(다른 그림으로 대신하지 않는다). */
interface ScreenArt {
    /** 초상(원 안). [mood] null 이면 웃는 얼굴. */
    @Composable
    fun portrait(characterId: String, mood: CharacterMood?): ImageBitmap?

    /** 무대 그림(큰 전신 — 웃는 얼굴이고 고해상이 있으면 420px). */
    @Composable
    fun stage(characterId: String, mood: CharacterMood?, size: Dp): ImageBitmap?

    /** 루비 보석([pointSize] 에 맞는 해상도). */
    @Composable
    fun ruby(pointSize: Float): ImageBitmap?

    /** 앱 기본: Compose 리소스(Gradle Sync 가 맥 원본을 싣는다 — git 사본 0). */
    object Resources : ScreenArt {
        @Composable
        override fun portrait(characterId: String, mood: CharacterMood?): ImageBitmap? =
            rememberPortraitArt(characterId, expressionOf(mood))

        @Composable
        override fun stage(characterId: String, mood: CharacterMood?, size: Dp): ImageBitmap? =
            rememberStageArt(characterId, expressionOf(mood), size.value)

        @Composable
        override fun ruby(pointSize: Float): ImageBitmap? = rememberRubyArt(pointSize)
    }

    companion object {
        /** 근무 안 함이면 시무룩, 그 밖(모름 포함)은 웃음. */
        fun expressionOf(mood: CharacterMood?): CharacterExpression = mood?.expression ?: CharacterExpression.Neutral
    }
}

/** 화면 트리가 받는 그림 창구. 기본은 리소스 — 시험·미리보기가 갈아 끼운다. */
val LocalScreenArt = staticCompositionLocalOf<ScreenArt> { ScreenArt.Resources }
