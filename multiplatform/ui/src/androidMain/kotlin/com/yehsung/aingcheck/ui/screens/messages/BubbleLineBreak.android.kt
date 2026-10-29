// 원본: Sources/CheckMobileKit/Messages/MessagesBubbleTextLayout.swift @ 3bd04bd (hangulWordPriority → Android LineBreak.WordBreak.Phrase)
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.ui.text.style.LineBreak

internal actual val BubbleLineBreak: LineBreak =
    LineBreak(strategy = LineBreak.Strategy.HighQuality, strictness = LineBreak.Strictness.Strict, wordBreak = LineBreak.WordBreak.Phrase)
