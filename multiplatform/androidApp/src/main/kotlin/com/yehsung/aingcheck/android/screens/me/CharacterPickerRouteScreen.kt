// 원본: Sources/CheckMobileKit/Me/MeCharacterViews.swift:383-480 @ 3bd04bd (MeCharacterPickerView — [상점 가기] · 뽑기 기계 덮개)
//
// 캐릭터 고르기 껍데기(Android). [상점 가기] → Dest.Shop, 안 가진 뽑기 전용 타일 → 뽑기 기계(W4-c 전체 화면 — 조립이 잇는다, assembly.md).
package com.yehsung.aingcheck.android.screens.me

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.ui.screens.me.CharacterPickerHero
import com.yehsung.aingcheck.ui.screens.me.CharacterPickerScreen
import com.yehsung.aingcheck.ui.screens.me.MeStageContent

@Composable
fun CharacterPickerRouteScreen(
    store: MeStore,
    openShop: () -> Unit,
    openGachaMachine: () -> Unit,
    modifier: Modifier = Modifier,
    hero: MeStageContent = CharacterPickerHero.Static,
) {
    // 머리 그림 자리(칸 100×104 · 그림 92)는 W5-c 살아 있는 미리보기가 채운다 — 조립: hero = { spec, m -> AingStage(spec.characterId, null, m, artSize = spec.artSize) }.
    CharacterPickerScreen(store, openShop, openGachaMachine, modifier, hero = hero)
}
