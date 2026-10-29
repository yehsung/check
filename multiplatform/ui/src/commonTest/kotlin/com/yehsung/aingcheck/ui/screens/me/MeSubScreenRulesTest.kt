// 원본: Sources/CheckMobileKit/Me/MeCharacterViews.swift:383-684 @ 3bd04bd · Me/MeFeedbackView.swift @ 3bd04bd · Me/MeProfileView.swift @ 3bd04bd
//
// 나 탭 하위 화면(캐릭터 고르기 · 제보 · 프로필)의 순수 판정을 Swift 뷰의 갈래 순서와 같은 값으로 잰다.
// 기준선은 늘 다른 입력이다(같은 입력 둘을 비교하지 않는다): 갈래마다 한 칸씩 바꾼 입력이 다른 결과로 가는지 본다.
package com.yehsung.aingcheck.ui.screens.me

import com.yehsung.aingcheck.core.stores.me.MeCharacterTileStatus
import com.yehsung.aingcheck.core.stores.me.MeLoadState
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.FeedbackKind
import com.yehsung.aingcheck.core.wire.models.FeedbackReport
import com.yehsung.aingcheck.core.wire.models.FeedbackStatus
import com.yehsung.aingcheck.core.wire.models.FeedbackText
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.ui.screens.settingscommon.NoticeKind
import com.yehsung.aingcheck.ui.theme.AingColors
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MeSubScreenRulesTest {
    private fun status(
        saving: Boolean = false, on: Boolean = false, owned: Boolean = false, gift: Boolean = false, gacha: Boolean = false,
        shard: Long? = null, price: Long? = null, balance: Long? = null, unlocked: Boolean = false,
    ) = CharacterPickerRules.status(saving, on, owned, gift, gacha, shard, price, balance, unlocked)

    @Test
    fun pickerStatusFollowsSwiftPrecedence() {
        assertEquals(MeCharacterTileStatus.Busy, status(saving = true, on = true, owned = true), "저장 중이 무엇보다 먼저")
        assertEquals(MeCharacterTileStatus.Equipped, status(on = true, owned = true))
        assertEquals(MeCharacterTileStatus.Owned, status(owned = true, price = 60))
        assertEquals(MeCharacterTileStatus.GiftOnly, status(gift = true, gacha = true, price = 2000), "선물 전용이 뽑기 전용·가격보다 먼저")
        assertEquals(MeCharacterTileStatus.GachaOnly(20), status(gacha = true, shard = 20, price = 1000), "뽑기 전용은 명목가(1000)를 말하지 않는다")
        assertEquals(MeCharacterTileStatus.Price(60, 120), status(price = 60, balance = 120))
        assertEquals(MeCharacterTileStatus.None, status(unlocked = true))
        assertEquals(MeCharacterTileStatus.UnknownPrice, status())
    }

    @Test
    fun pickerOrderColumnsAndTap() {
        val owned = setOf("aing", "fox")
        assertEquals(listOf("aing", "fox", "ghost", "robot"), CharacterPickerRules.ordered(listOf("aing", "ghost", "fox", "robot")) { it in owned }, "가진 것 먼저 · 안정 정렬")
        assertEquals(3, CharacterPickerRules.columns(1f))
        assertEquals(2, CharacterPickerRules.columns(1.3f))
        assertEquals(1, CharacterPickerRules.columns(2f))
        assertEquals(CharacterPickerTap.OpenGachaMachine, CharacterPickerRules.tap(showsGacha = true, owned = false, gachaOnly = true))
        assertEquals(CharacterPickerTap.Choose, CharacterPickerRules.tap(showsGacha = false, owned = false, gachaOnly = true), "뽑기가 닫힌 서버면 고르기가 얻는 길을 말한다")
        assertEquals(CharacterPickerTap.Choose, CharacterPickerRules.tap(showsGacha = true, owned = true, gachaOnly = true), "가진 것은 입는다")
        assertEquals(CharacterPickerTap.Choose, CharacterPickerRules.tap(showsGacha = true, owned = false, gachaOnly = false))
    }

    @Test
    fun pickerAccessibilityAndHero() {
        assertEquals("여우, 착용 중", CharacterPickerRules.accessibilityText("여우", MeCharacterTileStatus.Equipped))
        assertEquals("다람쥐, 루비 60개, 모자라요", CharacterPickerRules.accessibilityText("다람쥐", MeCharacterTileStatus.Price(60, 10)))
        assertEquals("다람쥐, 루비 60개", CharacterPickerRules.accessibilityText("다람쥐", MeCharacterTileStatus.Price(60, null)), "잔량을 모르면 모자라다고 하지 않는다")
        assertTrue(CharacterPickerRules.lockedLabel("유령", giftOnly = false, gachaOnly = false, shardCost = null).endsWith("상점에서 사기"))
        assertTrue(CharacterPickerRules.lockedLabel("딸기", giftOnly = true, gachaOnly = true, shardCost = null).contains("생일 선물"))
        assertEquals("착용 중" to MeWearKind.Value, CharacterPickerRules.heroStatus(loaded = true, failed = true))
        assertEquals(MeWearKind.Failed, CharacterPickerRules.heroStatus(loaded = false, failed = true).second)
        assertEquals(MeWearKind.Loading, CharacterPickerRules.heroStatus(loaded = false, failed = false).second)
    }

    @Test
    fun sparkleIsGoldOrRainbowSolidInLightAndGradientInDark() {
        assertEquals(AingColors.Light.gold, TileSparkle.solid(AingColors.Light, CharacterManifest.Finish.gold))
        assertEquals(AingColors.Light.rainbowStops[5], TileSparkle.solid(AingColors.Light, CharacterManifest.Finish.rainbow), "라이트 무지개는 단색(짧은 기호에 그라데이션이 안 읽힌다)")
        assertNull(TileSparkle.solid(AingColors.Dark, CharacterManifest.Finish.rainbow), "다크 무지개는 그라데이션")
        assertEquals(AingColors.Dark.gold, TileSparkle.solid(AingColors.Dark, CharacterManifest.Finish.gold))
    }

    private fun report(id: String, version: String? = "Android 0.1.0 (1)", reply: String? = null) = FeedbackReport(
        id = id, userID = "u", kind = FeedbackKind.bug, body = "본문", status = FeedbackStatus.Open, adminNote = reply,
        adminNoteAt = null, appVersion = version, osVersion = "Android 16", createdAt = SwiftDate(1_000.0), updatedAt = null,
        authorName = "새벽", authorAvatarURL = null,
    )

    @Test
    fun feedbackRules() {
        val loading = MeLoadState().apply { isLoading = true }
        val failed = MeLoadState().apply { hasFailed = true }
        val loadedEmpty = MeLoadState().apply { hasLoaded = true; hasFailed = true }
        assertEquals(FeedbackEmptyCard.Loading, FeedbackScreenRules.emptyCard(loading))
        assertEquals(FeedbackEmptyCard.Failed, FeedbackScreenRules.emptyCard(failed))
        assertEquals(FeedbackEmptyCard.Empty, FeedbackScreenRules.emptyCard(loadedEmpty), "받은 값이 있으면 실패여도 빈 안내")
        assertEquals(NoticeKind.Info, FeedbackScreenRules.noticeKind(FeedbackText.sendSuccess))
        assertEquals(NoticeKind.Warning, FeedbackScreenRules.noticeKind(FeedbackText.sendFailed))
        assertEquals("버그 · 5분 전", FeedbackScreenRules.headerLine(report("a"), SwiftDate(1_300.0)))
        assertNull(FeedbackScreenRules.versionLine(report("a"), expanded = false), "접힌 줄엔 버전이 없다")
        assertEquals("앱 0.1.0 (1) · Android 16", FeedbackScreenRules.versionLine(report("a"), expanded = true))
        assertNull(FeedbackScreenRules.versionLine(report("a", version = ""), expanded = true))
        val list = listOf(report("a"), report("b"))
        assertEquals(3, FeedbackScreenRules.revealIndex(list, "b"), "쓰기 카드 · 머리 다음 칸")
        assertNull(FeedbackScreenRules.revealIndex(list, "z"), "목록에 없으면 목록이 올 때 다시")
        assertNull(FeedbackScreenRules.revealIndex(list, null))
        assertEquals(listOf("a", "b"), FeedbackScreenRules.toggled(listOf("a"), "b"))
        assertEquals(listOf("a"), FeedbackScreenRules.toggled(listOf("a", "b"), "b"))
    }

    @Test
    fun profileRules() {
        assertEquals("올리는 중…", ProfileScreenRules.pickerTitle(uploading = true))
        assertEquals("사진 바꾸기", ProfileScreenRules.pickerTitle(uploading = false))
        assertTrue(ProfileScreenRules.showsClear("오후엔 리뷰"))
        assertTrue(!ProfileScreenRules.showsClear(null), "저장된 상태가 없으면 [지우기]가 없다")
        assertTrue(ProfileScreenRules.showsCharacterFace(hasPhotoURL = false), "사진이 없으면 착용 캐릭터")
        assertTrue(!ProfileScreenRules.showsCharacterFace(hasPhotoURL = true))
        assertEquals(NoticeKind.Error, ProfileScreenRules.noticeKind(true))
        assertEquals(NoticeKind.Info, ProfileScreenRules.noticeKind(false))
    }
}
