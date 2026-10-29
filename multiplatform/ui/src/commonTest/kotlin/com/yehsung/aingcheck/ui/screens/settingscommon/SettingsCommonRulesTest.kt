// 원본: Tests/CheckMobileKitTests/MeAppearanceTests.swift @ 3bd04bd (저장 · 복원 · 모르는 값 → 다크 · 같은 값 다시 고르기)
// 원본: Sources/CheckMobileKit/Me/MeSettingsView.swift @ 3bd04bd (pushSection 판정 · 팀 코드 칸 · 계정 삭제 행 잠금) — 두 겹 스위치(⑤)는 원본 없음(E§6.5)
package com.yehsung.aingcheck.ui.screens.settingscommon

import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.ui.theme.AingAppearanceMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SettingsCommonRulesTest {
    // ---------------------------------------------------------------- 화면 모드(6차 int-h '[착수 W3-b] 화면 모드 → ui')

    @Test
    fun appearanceDefaultsToDarkAndRestoresStoredValue() {
        val prefs = ScreenMemoryPrefs()
        assertEquals(AingAppearanceMode.Dark, AppearanceStore(prefs).mode, "고른 적 없으면 다크(사용자 결정 2026-09-18)")
        prefs.putString("aingcheck.appearance.mode", "light")
        assertEquals(AingAppearanceMode.Light, AppearanceStore(prefs).mode, "저장값 복원")
        prefs.putString("aingcheck.appearance.mode", "sepia")
        assertEquals(AingAppearanceMode.Dark, AppearanceStore(prefs).mode, "모르는 값은 라이트가 아니라 다크로 접는다")
        assertEquals("sepia", prefs.getString("aingcheck.appearance.mode"), "고르기 전에는 모르는 저장값을 지우지 않는다")
    }

    @Test
    fun appearanceSelectWritesImmediatelyAndNotifiesOnlyOnChange() {
        val prefs = ScreenMemoryPrefs()
        val store = AppearanceStore(prefs)
        val changes = mutableListOf<AingAppearanceMode>()
        store.onChange = { changes += it }
        store.select(AingAppearanceMode.Light)
        assertEquals("light", prefs.getString("aingcheck.appearance.mode"))
        assertEquals(AingAppearanceMode.Light, store.mode)
        store.select(AingAppearanceMode.Light)
        assertEquals(listOf(AingAppearanceMode.Light), changes, "같은 값을 다시 골라도 알리지 않는다")
        store.select(AingAppearanceMode.System)
        assertEquals("system", prefs.getString("aingcheck.appearance.mode"))
        assertEquals(listOf(AingAppearanceMode.Light, AingAppearanceMode.System), changes)
    }

    /** 저장 키·기본 순서·문구가 Swift 원문과 같다(소스 계약 — 원문을 제자리에서 읽는다). */
    @Test
    fun appearanceTextMatchesSwift() {
        val store = RepoFiles.readText("Sources/CheckMobileKit/Theme/MobileAppearance.swift")
        assertTrue(store.contains("defaultsKey = \"${AingAppearanceMode.STORAGE_KEY}\""), "저장 키가 Swift 와 다르다")
        val order = Regex("""case (dark|light|system)\b""").findAll(store).map { it.groupValues[1] }.toList()
        assertEquals(order, AppearanceText.modes.map { it.storedValue }, "목록 순서(기본이 맨 위)가 Swift allCases 와 다르다")
        val text = RepoFiles.readText("Sources/CheckMobileKit/Me/MeText.swift")
        for (mode in AingAppearanceMode.entries) {
            assertTrue(text.contains("return \"${AppearanceText.title(mode)}\""), "${mode.storedValue} 제목이 Swift 와 다르다")
        }
        assertTrue(text.contains("appearanceSection = \"${AppearanceText.section}\""))
        // iOS 는 "아이폰 설정"이다 — Android 는 글자만 바꾼다(뜻은 같다: 위젯은 기기 설정을 따른다).
        assertTrue(text.contains("위젯은 이 설정과 상관없이 아이폰 설정을 따라요."))
        assertEquals("위젯은 이 설정과 상관없이 휴대폰 설정을 따라요.", AppearanceText.widgetNote)
    }

    // ---------------------------------------------------------------- 알림 두 겹 스위치(⑤)

    private val prefsAllOn = PushPrefs(message = true, gomokuInvite = true, feedbackReply = true)
    private fun row(rows: List<NotificationRowState>, raw: String) = rows.single { it.kind.raw == raw }

    @Test
    fun twoLayersAreIndependent() {
        // 서버 켜짐 + 채널 꺼짐 → 토글은 켜진 그대로, 그 행에만 "시스템에서 꺼짐".
        val serverOnChannelOff = NotificationTwoLayer.rows(NotificationTwoLayer.androidKinds, NotificationPermission.Granted, prefsAllOn, setOf("message"))
        assertTrue(row(serverOnChannelOff, "message").appOn, "채널이 꺼졌다고 서버 토글을 끈 모양으로 바꾸지 않는다")
        assertTrue(row(serverOnChannelOff, "message").systemBlocked)
        assertFalse(row(serverOnChannelOff, "gomoku_invite").systemBlocked, "다른 채널은 그대로")
        // 서버 꺼짐 + 채널 켜짐 → 토글만 꺼짐, 시스템 안내 없음.
        val serverOffChannelOn = NotificationTwoLayer.rows(NotificationTwoLayer.androidKinds, NotificationPermission.Granted, prefsAllOn.copy(message = false), emptySet())
        assertFalse(row(serverOffChannelOn, "message").appOn)
        assertTrue(row(serverOffChannelOn, "message").appEnabled, "꺼진 토글도 다시 켤 수 있다")
        assertFalse(row(serverOffChannelOn, "message").systemBlocked)
        // 둘 다 꺼짐 → 토글 꺼짐 + 시스템 안내.
        val bothOff = NotificationTwoLayer.rows(NotificationTwoLayer.androidKinds, NotificationPermission.Granted, prefsAllOn.copy(feedbackReply = false), setOf("feedback_reply"))
        assertFalse(row(bothOff, "feedback_reply").appOn)
        assertTrue(row(bothOff, "feedback_reply").systemBlocked)
    }

    @Test
    fun withoutPermissionTogglesLookOffAndDisabledButServerValueUntouched() {
        for (permission in listOf(NotificationPermission.NotDetermined, NotificationPermission.Denied, NotificationPermission.Unknown)) {
            val rows = NotificationTwoLayer.rows(NotificationTwoLayer.androidKinds, permission, prefsAllOn, setOf("message"))
            assertTrue(rows.none { it.appOn }, "$permission: 권한이 없으면 꺼진 모양")
            assertTrue(rows.none { it.appEnabled }, "$permission: 누를 수 없다")
            assertTrue(rows.none { it.systemBlocked }, "$permission: 권한이 없을 때는 머리 줄이 말한다 — 행마다 달지 않는다")
        }
        assertEquals(NotificationHeaderAction.RequestPermission, NotificationTwoLayer.headerAction(NotificationPermission.NotDetermined))
        assertEquals(NotificationHeaderAction.OpenSystemSettings, NotificationTwoLayer.headerAction(NotificationPermission.Denied))
        assertNull(NotificationTwoLayer.headerAction(NotificationPermission.Granted))
    }

    @Test
    fun unknownServerPrefsDisableTogglesAndSayItOnce() {
        val rows = NotificationTwoLayer.rows(NotificationTwoLayer.androidKinds, NotificationPermission.Granted, null, emptySet())
        assertTrue(rows.filter { it.hasAppToggle }.none { it.appEnabled || it.appOn }, "서버값을 모르면 흐린 꺼짐(지어내지 않는다)")
        assertTrue(NotificationTwoLayer.showsPrefsUnknown(NotificationPermission.Granted, null))
        assertFalse(NotificationTwoLayer.showsPrefsUnknown(NotificationPermission.Denied, null), "권한이 없으면 모름 안내 대신 권한 머리 줄")
    }

    @Test
    fun workCheckAndChessHaveOnlyTheSystemLayer() {
        val rows = NotificationTwoLayer.rows(NotificationTwoLayer.androidKinds, NotificationPermission.Granted, prefsAllOn, setOf("work_check", "chess_invite"))
        assertEquals(listOf("message", "gomoku_invite", "chess_invite", "feedback_reply", "work_check"), rows.map { it.kind.raw }, "E§6.5 채널 표 순서")
        for (raw in listOf("work_check", "chess_invite")) {
            assertFalse(row(rows, raw).hasAppToggle, "$raw: 앱 토글 없음(서버 선호값 전선에 칸이 없다)")
            assertTrue(row(rows, raw).systemBlocked, "$raw: 시스템 겹은 있다")
        }
        // 서버 선호값 전선은 세 칸뿐이다(core/wire PushPrefs) — 체스 칸이 생기면 이 시험이 먼저 빨개져 prefsKey 를 채우게 한다.
        assertNull(NotificationTwoLayer.serverValue(prefsAllOn, "chess_invite"))
        assertNull(NotificationTwoLayer.withValue(prefsAllOn, "work_check", false))
    }

    @Test
    fun savingChangesExactlyOneServerKey() {
        val next = NotificationTwoLayer.withValue(prefsAllOn, "gomoku_invite", false)
        assertEquals(PushPrefs(message = true, gomokuInvite = false, feedbackReply = true), next)
        assertEquals(PushPrefs(message = false, gomokuInvite = true, feedbackReply = true), NotificationTwoLayer.withValue(prefsAllOn, "message", false))
    }

    // ---------------------------------------------------------------- 팀 · 계정 · 시트 붙잡기

    @Test
    fun inviteCodeCellAndAccountRows() {
        assertEquals("AB12CD", SettingsRules.inviteCodeText("AB12CD", loaded = true, failed = false, isLoading = false))
        assertEquals("—", SettingsRules.inviteCodeText(null, loaded = true, failed = false, isLoading = false), "받았는데 코드가 없다")
        assertEquals("—", SettingsRules.inviteCodeText(null, loaded = false, failed = true, isLoading = false), "실패가 끝났다")
        assertEquals("불러오는 중…", SettingsRules.inviteCodeText(null, loaded = false, failed = true, isLoading = true), "다시 시도 중")
        assertEquals("a@b.co", SettingsRules.email("a@b.co", "old@b.co"))
        assertEquals("old@b.co", SettingsRules.email(null, "old@b.co"))
        assertNull(SettingsRules.email(null, null))
        assertTrue(SettingsRules.accountDeletionEnabled(isSigningOut = false, isDeletingAccount = false))
        assertFalse(SettingsRules.accountDeletionEnabled(isSigningOut = true, isDeletingAccount = false))
        assertFalse(SettingsRules.accountDeletionEnabled(isSigningOut = false, isDeletingAccount = true))
    }

    /** INV-MobileRootView-3f3f1540: 스토어 값이 null 로 걷혀도 내려가는 판은 마지막 item 으로 그린다. */
    @Test
    fun retainedSheetItemKeepsLastItemWhileDismissing() {
        var retained: String? = null
        retained = RetainedSheetItem.next(retained, null)
        assertNull(retained, "띄운 적이 없으면 없다")
        retained = RetainedSheetItem.next(retained, "gift-1")
        retained = RetainedSheetItem.next(retained, null)
        assertEquals("gift-1", retained, "닫히는 동안 마지막 item")
        retained = RetainedSheetItem.next(retained, "gift-2")
        assertEquals("gift-2", retained, "새 item 이 오면 바꿔 쥔다")
    }
}
