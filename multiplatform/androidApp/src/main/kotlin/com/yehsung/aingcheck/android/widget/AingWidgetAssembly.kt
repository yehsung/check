// 원본: Sources/CheckMobileShared/WidgetSnapshot.swift @ 3bd04bd (위젯이 읽는 스냅숏 — 앱이 쓰고 위젯이 읽는 같은 값)
// 원본: Sources/CheckMobileKit/Rankings/RankingsTab.swift:105-119 @ 3bd04bd (myCharacterID · myCharacterMood — 위젯 스냅숏으로 접는 자리)
//
// 7차 조립(K11) 배선: W2-f 스냅숏(feature/phone …/widget WidgetSnapshot)을 위젯 갈래의 읽기 모양 [AingWidgetInput] 으로 옮긴다(필드 1:1 —
// 두 타입 모두 Swift WidgetSnapshot 을 옮긴 것). Swift 는 한 타입을 앱·위젯이 같이 썼고, Android 는 모듈 경계 때문에 둘로 갈라져 여기서 잇는다.
// 순위 '나' 행의 스냅숏 표정([rankingsMood])도 같은 상태 세 갈래를 읽는다(Swift `CharacterMood(status)` — 근무 중 · 연결 끊김 → 길 잃음 · 근무 안 함).
package com.yehsung.aingcheck.android.widget

import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshot
import com.yehsung.aingcheck.ui.components.CharacterMood

/** W2-f 스냅숏 → 위젯 읽기 모양(필드 1:1). */
fun WidgetSnapshot.toAingWidgetInput(): AingWidgetInput = AingWidgetInput(
    generatedAt = generatedAt,
    me = me?.let { m ->
        AingWidgetInput.Me(
            working = m.working,
            sessionStartedAt = m.sessionStartedAt,
            todaySeconds = m.todaySeconds,
            weekSeconds = m.weekSeconds,
            goalHours = m.goalHours,
            status = m.status?.let { s -> AingWidgetInput.WorkState.valueOf(s.name) },
        )
    },
    working = working.map { AingWidgetInput.Person(it.name, it.center, it.teammate, it.startedAt, it.characterID) },
    todosPreview = todosPreview.map { AingWidgetInput.Todo(it.id, it.title, it.isCompleted, it.carryOverDays) },
    characterID = characterID,
    aiLimits = aiLimits,
)

/** 순위 '나' 행의 스냅숏 표정(Swift `myCharacterMood` 의 둘째 갈래). 스냅숏에 me 가 없으면 null(규칙이 근무 안 함으로 접는다). */
fun WidgetSnapshot.rankingsMood(): CharacterMood? = when (me?.resolvedStatus) {
    WidgetSnapshot.WorkState.working -> CharacterMood.Working
    WidgetSnapshot.WorkState.disconnected -> CharacterMood.Lost
    WidgetSnapshot.WorkState.off -> CharacterMood.Off
    null -> null
}
