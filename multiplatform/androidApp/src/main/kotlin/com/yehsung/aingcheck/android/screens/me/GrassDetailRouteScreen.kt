// 원본: Sources/CheckMobileKit/Me/MeGrassDetailView.swift @ 3bd04bd (잔디 상세 — 목적지 인자 axis 로 연다)
//
// 잔디 상세 껍데기(Android). 목적지 인자(Dest.GrassDetail.axis — "work"·"token")를 MeGrassAxis 로 풀어 공용 화면(ui …/screens/me GrassDetailScreen)에 넘긴다.
// 모르는 축 글자는 근무로 연다(딥링크가 옛 값이어도 화면이 선다). 조립(K11)은 NavGraph 의 GrassDetailPlaceholder 줄을 이 화면으로 바꾼다(assembly.md).
package com.yehsung.aingcheck.android.screens.me

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.ui.screens.me.GrassDetailScreen

@Composable
fun GrassDetailRouteScreen(store: MeStore, axisArg: String, modifier: Modifier = Modifier) {
    val scope = rememberCoroutineScope()
    GrassDetailScreen(store, GrassAxisArg.parse(axisArg), scope, modifier)
}

/** 목적지 인자 → 축(모르면 근무 — 지어내지 않고 기본 축으로 연다). */
object GrassAxisArg {
    fun parse(raw: String): MeGrassAxis = MeGrassAxis.entries.firstOrNull { it.name == raw } ?: MeGrassAxis.work
}
