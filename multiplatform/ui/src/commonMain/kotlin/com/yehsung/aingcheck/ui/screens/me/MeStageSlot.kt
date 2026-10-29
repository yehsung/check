// 원본: Sources/CheckMobileKit/Me/MeTab.swift @ 3bd04bd (MeStageCard.stage · artSize 132 · 칸 artSize+6 × artSize+12)
//
// 나 탭 무대 **자리** 계약(W3-b ↔ W5-c). 무대 카드의 왼쪽 칸에 무엇을 세울지는 이 자리 하나로 갈린다:
//  - 기본([MeStageDefaults.Static]) — 정지 초상(W1-e CharacterStage: 발밑 빛 + 그림자 + 그림).
//  - W5-c 살아 있는 미리보기(androidApp …/screens/stage) — 같은 자리에 구운 아잉이 재생기를 세운다(결정 #2 = 10-21 '살아 있는 미리보기 하나').
// 자리의 **크기는 이 파일이 정한다**(그림 132 · 칸 138×144 dp). 무대 카드는 자리에 Modifier.size(칸) 을 먼저 걸고 내용을 부른다 —
// 내용이 무엇이든 카드 배치(이름표 · 루비 칩 · 단추)는 흔들리지 않는다. 조립(K11)은 `stage =` 인자 하나만 바꾼다(assembly.md).
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterStage
import com.yehsung.aingcheck.ui.components.CharacterStageMetrics
import com.yehsung.aingcheck.ui.screens.settingscommon.LocalScreenArt

/**
 * 무대 자리 한 칸의 입력. [characterId] 는 착용 캐릭터(모르면 아잉 — MeStore.equippedCharacterID 가 이미 접는다),
 * [mood] 는 근무 상태(null = 모른다 → 회색 발밑 빛, 표정은 웃음).
 */
@Immutable
data class MeStageSpec(
    val characterId: String,
    val mood: CharacterMood?,
    val artSize: Dp = CharacterStageMetrics.artSize,
) {
    /** 칸 폭 = 그림 + 6(iOS `frame(width: artSize + 6)`). */
    val slotWidth: Dp get() = artSize + 6.dp

    /** 칸 높이 = 그림 + 12(발밑 빛이 그림 아래로 내려앉는 자리). */
    val slotHeight: Dp get() = artSize + 12.dp
}

/** 무대 자리 내용. [modifier] 에는 이미 칸 크기가 걸려 있다 — 내용은 크기를 다시 정하지 않는다. */
typealias MeStageContent = @Composable (spec: MeStageSpec, modifier: Modifier) -> Unit

object MeStageDefaults {
    /** 정지 무대(초상). 그림은 [LocalScreenArt] 창구에서 받는다(시험은 저장소 원본을 동기로 넘긴다). */
    val Static: MeStageContent = { spec, modifier ->
        val art = LocalScreenArt.current.stage(spec.characterId, spec.mood, spec.artSize)
        CharacterStage(art = art, mood = spec.mood, modifier = modifier, artSize = spec.artSize)
    }
}
