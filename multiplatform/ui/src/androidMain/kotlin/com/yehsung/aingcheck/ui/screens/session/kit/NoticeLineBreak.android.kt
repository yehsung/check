// 안내 한 줄(InlineNotice)의 줄바꿈 — 안드로이드 몫. 말풍선과 같은 한글 어절 단위(BubbleLineBreak — API 33+ 어구 단위)다(검토 F4).
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.ui.text.TextStyle
import com.yehsung.aingcheck.ui.screens.messages.BubbleLineBreak

internal actual fun TextStyle.noticeLineBreak(): TextStyle = copy(lineBreak = BubbleLineBreak)
