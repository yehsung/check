// 원본: 없음 — 폰 1.0.16 문구(main 6ed85edf)는 폰에서 맥·PC 를 가리키는 말이라 Windows 자기 화면에서는 어색하다(사용자 답 "Windows 전용 문구 두기").
//
// 로그인 머리말 · 프로필 캐릭터 안내 · 캐릭터 고르기 안내 세 줄의 갈래. 기본값은 폰 문구: Android 는 아무것도 제공하지 않아 글자가 그대로다.
// Windows(desktopApp)는 이 화면 셋을 그리는 플라이아웃 뿌리에서 true 를 준다 — LocalBlockReportPlatform 과 같은 자리.
package com.yehsung.aingcheck.ui.screens.session

import androidx.compose.runtime.staticCompositionLocalOf

/** Windows 전용 기기 문구를 쓸지. 앱이 사는 동안 바뀌지 않는 값이라 static 이다. */
val LocalDesktopWording = staticCompositionLocalOf { false }
