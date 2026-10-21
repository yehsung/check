// 원본: Sources/CheckMobileKit/Theme/MobileAppearance.swift @ a63fea2
//
// 화면 모드(나 → 설정 → 화면 모드). **기본은 다크**(사용자 결정 2026-09-18 — 그림이 어두운 바탕에서 만들어졌다).
// 저장은 플랫폼 KeyValueStore 몫(W2·W3). 이 파일은 값 ↔ 모드 규칙만 둔다.
package com.yehsung.aingcheck.ui.theme

enum class AingAppearanceMode(val storedValue: String) {
    Dark("dark"),
    Light("light"),
    System("system"),
    ;

    /** 이 모드에서 어둡게 그리는가. [systemIsDark] 는 OS 설정(System 일 때만 쓴다). */
    fun isDark(systemIsDark: Boolean): Boolean = when (this) {
        Dark -> true
        Light -> false
        System -> systemIsDark
    }

    companion object {
        /** iOS 와 같은 저장 키(기기 설정 — 계정·로그아웃과 무관). */
        const val STORAGE_KEY = "aingcheck.appearance.mode"

        /**
         * 저장값 → 모드. 값이 없거나 문자열이 아니거나 모르는 값(다음 버전이 더한 값 · 손상)이면 **다크**.
         * 모르는 값을 라이트로 접지 않는다 — 구버전이 보여 줄 수 있는 가장 안전한 화면은 설계한 화면이다.
         */
        fun fromStored(value: Any?): AingAppearanceMode {
            val raw = value as? String ?: return Dark
            return entries.firstOrNull { it.storedValue == raw } ?: Dark
        }
    }
}
