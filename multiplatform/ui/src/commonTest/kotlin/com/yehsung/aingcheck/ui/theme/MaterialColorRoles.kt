// 원본: 없음 — M3 ColorScheme 의 색 역할을 손 목록 없이 전부 열거한다(시험 도구). 두 JVM 시험 소스셋(데스크톱·Android 호스트)이
// 같은 반사 코드로 actual 을 둔다. 손으로 적은 목록은 M3 판이 역할을 늘려도 영원히 초록이라(W1-e 검증 지적) 반사로 센다.
package com.yehsung.aingcheck.ui.theme

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color

/** 역할 이름(예: "primaryFixedDim")과 그 값을 읽는 함수. */
internal class MaterialColorRole(val name: String, val read: (ColorScheme) -> Color)

/** [ColorScheme] 의 공개 Color 게터 전부(이름순). */
internal expect fun materialColorRoles(): List<MaterialColorRole>
