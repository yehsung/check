// 원본: Sources/CheckMobileKit/Theme/MobileAppearance.swift @ 3bd04bd (MobileAppearanceStore — 저장 · 복원 · 고르기)
// 원본: Sources/CheckMobileKit/Me/MeText.swift:846-866 @ 3bd04bd (appearanceSection · appearanceWidgetNote · appearanceTitle · appearanceSymbol)
// 원본: Sources/CheckMobileKit/Me/MeStoreSettings.swift:164-172 @ 3bd04bd (appearanceMode · selectAppearance — 6차 int-h unresolved '[착수 W3-b] 화면 모드 → ui')
//
// 화면 모드(나 → 설정 → 화면 모드). **기본은 다크**(사용자 결정 2026-09-18 — 그림이 어두운 바탕에서 만들어졌다). 계정과 무관한 **이 기기의 설정**이다:
// 로그아웃 · 세션 만료 · 세대 변경과 무관하고(스토어 reset 사슬에 들어가지 않는다) 서버에 올리지 않는다. 값 ↔ 모드 규칙은 W1-e AingAppearanceMode.
// 적용: Android 는 셸(MainActivity — 조정자 K11)이 `AingTheme(mode = store.mode)` 로 감싼다(assembly.md). 재실행 없이 바로 바뀐다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingAppearanceMode

/**
 * 화면 모드 저장소. 저장 자리는 앱의 비밀 아닌 설정 저장소(KeyValueStore — Android SharedPreferences)이고 키는 iOS 와 같은 글자다.
 * 위젯은 이 값을 따르지 않는다(위젯은 기기 설정 — Glance ColorProvider 의 낮·밤 짝).
 */
class AppearanceStore(private val store: KeyValueStore) {
    var mode: AingAppearanceMode by mutableStateOf(AingAppearanceMode.fromStored(store.getString(AingAppearanceMode.STORAGE_KEY)))
        private set

    /** 모드가 바뀔 때마다(같은 값을 다시 골라도 부르지 않는다). 셸의 상태 막대 글자색 적용기가 건다. */
    var onChange: ((AingAppearanceMode) -> Unit)? = null

    /** 고른 모드를 곧바로 저장하고 알린다. 모르는 저장값이 있어도 사용자가 고르면 덮어쓴다(고르기 전에는 지우지 않는다). */
    fun select(newMode: AingAppearanceMode) {
        store.putString(AingAppearanceMode.STORAGE_KEY, newMode.storedValue)
        if (newMode == mode) return
        mode = newMode
        onChange?.invoke(newMode)
    }
}

/** 화면 모드 절 글자(폰만의 문장 — 기기 설정, 서버에 올리지 않는다). */
object AppearanceText {
    const val section = "화면 모드"

    /** 위젯은 앱 설정을 따르지 않는다는 것을 칸 아래 한 줄로 밝힌다(iOS 의 "아이폰 설정" 을 Android 글자로). */
    const val widgetNote = "위젯은 이 설정과 상관없이 휴대폰 설정을 따라요."

    /** 목록 순서 = 열거 순서(기본 다크가 맨 위 — 고른 적 없는 사람이 지금 보고 있는 것이 먼저 읽히게). */
    val modes: List<AingAppearanceMode> = AingAppearanceMode.entries

    fun title(mode: AingAppearanceMode): String = when (mode) {
        AingAppearanceMode.System -> "시스템 설정 따르기"
        AingAppearanceMode.Light -> "라이트"
        AingAppearanceMode.Dark -> "다크"
    }

    /** SF `circle.lefthalf.filled` · `sun.max` · `moon` 의 Material Symbols 짝. */
    fun icon(mode: AingAppearanceMode): AppIcon = when (mode) {
        AingAppearanceMode.System -> AppIcon.Contrast
        AingAppearanceMode.Light -> AppIcon.LightMode
        AingAppearanceMode.Dark -> AppIcon.DarkMode
    }
}
