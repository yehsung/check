// 원본: Sources/CheckMobileKit/Messages/MessagesBubbleTextLayout.swift @ 3bd04bd (한글 어절 단위 줄바꿈 — 기본값은 음절 사이에서 끊겨 "두/었어요"가 됐다)
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.ui.text.style.LineBreak

/**
 * 말풍선 본문 줄바꿈. Android 는 어구(Phrase) 단위 — 한국어 어절을 쪼개지 않는다(API 33+ 의 LineBreaker 어구 단위, 그 아래는 문단 기본값).
 * 데스크톱(Windows 보류)은 문단 기본값.
 */
internal expect val BubbleLineBreak: LineBreak
