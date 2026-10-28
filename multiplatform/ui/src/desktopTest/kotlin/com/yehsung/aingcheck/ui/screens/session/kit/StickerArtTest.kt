// 원본: Sources/CheckCore/AingSticker.swift @ 3bd04bd (AingStickerArt.drawable — 판정하는 자리는 하나 · 그림이 없으면 "아잉이 기쁨" 글자)
// Swift 짝 시험: Tests/checkTests/V0362AingStickerTests.swift(통째 일치 · NFD · 그림 폴백).
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.ui.graphics.ImageBitmap
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.rules.text.AingStickerText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class StickerArtTest {
    private val joy = ImageBitmap(2, 2)
    private val heart = ImageBitmap(3, 3)
    private val ready = StickerArtState.Ready(mapOf(AingSticker.joy to joy, AingSticker.heart to heart))

    @Test
    fun wholeTokenWithArtIsDrawn() {
        val drawn = StickerArt.drawable("[아잉:기쁨]", ready)
        assertEquals(AingSticker.joy, drawn?.first)
        assertSame(joy, drawn?.second)
        // 앞뒤 공백은 정규화가 지운다 — 그래도 그림이다.
        assertEquals(AingSticker.heart, StickerArt.drawable("  [아잉:하트]\n", ready)?.first)
        // 자모 분해(NFD)로 들어온 토큰도 같은 이모티콘이다(맥 입력기 실측).
        val nfd = java.text.Normalizer.normalize("[아잉:기쁨]", java.text.Normalizer.Form.NFD)
        assertEquals(AingSticker.joy, StickerArt.drawable(nfd, ready)?.first)
    }

    @Test
    fun partialOrUnknownTokenIsText() {
        assertNull(StickerArt.drawable("[아잉:기쁨] ㅋㅋ", ready), "부분 치환 금지 — 글 속 작은 아이콘이 아니다")
        assertNull(StickerArt.drawable("[아잉:없는것]", ready))
        assertNull(StickerArt.drawable("안녕", ready))
    }

    @Test
    fun missingArtFallsBackToNameNotRawToken() {
        // 그림 지도에 슬픔이 없다(번들이 깨진 배포본) → 그림이 아니라 글자 말풍선, 그 글자는 날것 토큰이 아니라 이름.
        assertNull(StickerArt.drawable("[아잉:슬픔]", ready))
        assertEquals("아잉이 슬픔", AingStickerText.preview("[아잉:슬픔]"))
        // 평범한 본문은 한 글자도 바꾸지 않는다.
        assertEquals("[아잉] 그냥 글", AingStickerText.preview("[아잉] 그냥 글"))
    }

    @Test
    fun loadingHoldsPlaceOnlyForTokens() {
        assertNull(StickerArt.drawable("[아잉:기쁨]", StickerArtState.Loading))
        assertTrue(StickerArt.isPendingArt("[아잉:기쁨]", StickerArtState.Loading), "그림을 읽는 중엔 같은 크기의 자리를 잡는다(높이가 튀지 않게)")
        assertFalse(StickerArt.isPendingArt("안녕", StickerArtState.Loading))
        assertFalse(StickerArt.isPendingArt("[아잉:기쁨]", ready))
    }

    @Test
    fun stickerPathsFollowResourceNames() {
        assertEquals("files/stickers/sticker-joy.png", StickerArt.path(AingSticker.joy))
        assertEquals(AingSticker.entries.map { "files/stickers/sticker-${it.rawValue}.png" }, AingSticker.entries.map(StickerArt::path))
    }
}
