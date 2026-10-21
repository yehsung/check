// 아이콘 한 개(Material Symbols 벡터). 색은 지금 글자 색(LocalContentColor)을 따른다 — 기호는 늘 단색이다
// (그라데이션을 기호에 깔면 가운데 색만 걸려 탁해진다 — 기억 short-text-kills-gradients).
package com.yehsung.aingcheck.ui.icons

import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.resources.painterResource

/** 기본 크기 24dp(Material Symbols opsz 24). iOS 기호 크기는 글자 크기를 따랐다 — 행 안 기호는 20, 도구 막대 22~24. */
@Composable
fun AingIcon(
    icon: AppIcon,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    size: Dp = 24.dp,
    tint: Color = LocalContentColor.current,
) {
    Icon(
        painter = painterResource(icon.drawable),
        contentDescription = contentDescription,
        modifier = modifier.size(size),
        tint = tint,
    )
}
