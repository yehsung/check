// 원본: Sources/CheckMobileKit/App/MobileRootView.swift:119-127 @ 3bd04bd (생일 선물 축하 시트 — `.sheet(item:)` 의 내용은 클로저가 받은 item 으로 그린다)
//
// 스토어 값이 걷히는 순간에도 **내려가는 판**이 비지 않게 하는 시트 내용 붙잡기(K11 조립이 루트 시트를 띄울 때 쓴다 — 생일 선물 축하 시트 W4-c 등).
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

/**
 * INV-MobileRootView-3f3f1540 이식: 시트 내용은 **띄울 때 받은 item** 으로 그린다. 닫을 때 스토어 값은 곧바로 null 이 되지만 시트는 내려가는
 *   애니메이션 동안 화면에 남는다 — 스토어 값으로 그리면 내려가는 판이 텅 빈다. 그래서 마지막으로 본 null 아닌 item 을 붙잡아 [content] 에 넘기고,
 *   [current] 가 null 이 된 뒤에도 내려가는 동안은 그 값으로 그린다. 떠 있는 동안의 단계 변화(받는 중 → 받은 뒤)는 내용이 같은 item 의 스토어 값을
 *   먼저 보면 된다(id 가 같으면 새 값으로 바꿔 쥔다).
 * 반환값: 그릴 item(처음부터 null 이면 null — 띄운 적이 없다).
 */
@Composable
fun <T : Any> rememberRetainedSheetItem(current: T?): T? {
    var retained by remember { mutableStateOf<T?>(null) }
    if (current != null) retained = current
    return retained
}

/** 같은 규칙의 순수 판(시험용): 지난 붙잡은 값과 지금 값 → 새 붙잡은 값. */
object RetainedSheetItem {
    fun <T : Any> next(retained: T?, current: T?): T? = current ?: retained
}
