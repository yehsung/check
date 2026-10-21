// 원본: Sources/CheckMobileKit/Theme/MobileTheme.swift @ a63fea2 (치수 — 4pt 계단)
// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift @ a63fea2 (AingButtonMetrics.minimumTarget)
//
// iOS pt = Compose dp. 모서리는 iOS `.continuous`(스쿼클)이지만 M3·Compose 는 원호 모서리다 — 같은 반지름 숫자를 쓴다(판단: 차이는 2px 안팎).
package com.yehsung.aingcheck.ui.theme

import androidx.compose.ui.unit.dp

object AingDimens {
    /** 인셋 그룹·카드 모서리. */
    val groupRadius = 22.dp
    /** 캐릭터 타일 모서리. */
    val tileRadius = 16.dp
    /** 카드 안 2차 상자 · 입력칸 모서리. */
    val innerRadius = 12.dp
    /** 위젯 모서리. */
    val widgetRadius = 22.dp
    /** 카드 좌우 바깥 여백. */
    val sideMargin = 16.dp
    /** 큰 제목·섹션 머리 좌우 여백. */
    val titleMargin = 20.dp
    /** 카드 안쪽 여백. */
    val cardPadding = 16.dp
    /** 카드 사이 · 카드 안 줄 사이. */
    val rowSpacing = 12.dp
    val space1 = 4.dp
    val space2 = 8.dp
    val space3 = 12.dp
    val space4 = 16.dp
    val space5 = 20.dp
    val space6 = 24.dp
    val space8 = 32.dp
    /** 행 높이: 한 줄 44 · 두 줄 56. */
    val rowHeight = 44.dp
    val rowHeightTwoLine = 56.dp
    /** 구분선 두께(0.5pt). */
    val hairline = 0.5.dp
    /** 누름 영역 최소(작은 단추는 투명 여백으로 채운다). Android 권장 48 보다 작다 — iOS 값 그대로(판단: 같은 화면 밀도 유지). */
    val minimumTarget = 44.dp
}
