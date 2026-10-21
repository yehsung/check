// W0-a 뼈대: 빌드·스냅숏 하네스가 도는지만 재는 빈 Composable(A-X2·X5·X6). 디자인 시스템(W1-e)과 무관하다.
// 글자를 그리지 않는다 — 글꼴은 OS 마다 달라 러너 간 바이트 비교를 흐린다(번들 글꼴은 W1-e).
package com.yehsung.aingcheck.ui.scaffold

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** [accent] 는 렌더 비교의 기준선용이다 — 같은 크기에 색 하나만 다른 장면(A-X6, 기억 comparison-baseline-must-differ). */
@Composable
fun ScaffoldProbe(modifier: Modifier = Modifier, accent: Color = Color(0xFF6B4EFF)) {
    Box(modifier.size(64.dp).background(accent, RoundedCornerShape(12.dp)).padding(8.dp)) {
        Canvas(Modifier.size(48.dp)) {
            drawCircle(Color(0xFFFFD54F), radius = size.minDimension / 3f, center = Offset(size.width / 2f, size.height / 2f))
            drawLine(Color.White, Offset(0f, size.height), Offset(size.width, 0f), strokeWidth = 3f)
        }
    }
}
