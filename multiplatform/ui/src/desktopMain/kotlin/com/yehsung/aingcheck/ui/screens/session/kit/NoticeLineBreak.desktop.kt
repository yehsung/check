// 안내 한 줄(InlineNotice)의 줄바꿈 — 데스크톱 몫. 손대지 않는다(Windows v1 동결 — 데스크톱 골든 그대로).
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.ui.text.TextStyle

internal actual fun TextStyle.noticeLineBreak(): TextStyle = this
