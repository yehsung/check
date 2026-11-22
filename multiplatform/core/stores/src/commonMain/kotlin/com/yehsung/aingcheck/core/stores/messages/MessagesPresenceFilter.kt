// 원본: Sources/CheckMobileKit/Messages/MessagesPresenceFilter.swift @ 777a0e31 (폰 1.0.19 — 맥 0.3.87 `PokePresenceFilter` 의 폰 짝)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry

// 사람 찾기 거르기 칸 '전체 · 근무중 · 자리비움'(판 9 · 아이폰 1.0.19 · 맥 0.3.87).
// 제보(부산, 11-10): "콕 찌르기에서 '전체', '활동중', '활동안함' 이렇게 카테고리 되어있어서 사람들 구분할수 있는? 거 있으면 좋겠어요."
// → 대표 #d_xygj8oZRFlfH "추천안대로 한 판(1.0.19)에 전부"(9번 거르기 칸 · 안드로이드는 판 9 로 뒤따라).
//
// 폰 자리는 메시지 탭 '새 대화'의 사람 찾기다(폰의 찌르기 · 메시지 상대 고르기가 이 시트 하나다). 맥 · 아이폰과 같은 규칙 넷:
//  · 빼기만 한다 — 순서(안 읽음 → 근무 중 → 이름 — MessagesDirectoryRules.filter)는 그대로, 칸은 그 결과에서 사람을 덜어 낼 뿐이다.
//  · 이름 찾기와 함께 건다(AND).
//  · 근무 여부만 본다(서버 명부의 is_working — 줄의 초록 점 · '근무 중' 묶음과 같은 값). 센터 칸은 만들지 않는다.
//  · 집중은 칸을 바꾸지 않는다 — 근무 중 집중은 근무중 칸, 집중 켠 채 퇴근은 자리비움 칸.
// 맥과 다른 것 하나(아이폰과 같다): 가려진 안 읽음 점은 없다 — 시트는 대화를 새로 여는 자리이고 안 읽은 대화는 메시지 목록이 보여 준다.
// 고른 칸은 앱이 켜져 있는 동안 스토어가 들고 있고(MessagesStore.directoryPresenceFilter), 로그아웃(reset)하면 전체로 돌아간다.

/** 근무 칸 셋(맥 `PokePresenceFilter` · 아이폰 `MessagesPresenceFilter` 와 같은 값 · 같은 글자). */
enum class MessagesPresenceFilter {
    all,
    working,
    away,
    ;

    /** 칸 글자 — 맥 · 아이폰과 같다. */
    val label: String
        get() = when (this) {
            all -> MessagesPresenceFilterText.allLabel
            working -> MessagesPresenceFilterText.workingLabel
            away -> MessagesPresenceFilterText.awayLabel
        }

    /** 이 칸에 드는 사람인가. 근무 여부 하나만 본다. */
    fun admits(entry: PokeDirectoryEntry): Boolean = when (this) {
        all -> true
        working -> entry.isWorking
        away -> !entry.isWorking
    }
}

/** 칸 글자 · 빈 문구(맥 `PokePresenceFilterText` · 아이폰과 한 글자도 다르지 않다). */
object MessagesPresenceFilterText {
    const val allLabel = "전체"
    const val workingLabel = "근무중"
    const val awayLabel = "자리비움"
    /** 칸 묶음의 보이스오버 이름. */
    const val groupLabel = "목록 거르기"

    const val noneWorking = "지금 근무 중인 사람이 없어요"
    const val noneAway = "자리를 비운 사람이 없어요"
    const val noMatchWorking = "근무 중인 사람 중엔 맞는 이름이 없어요"
    const val noMatchAway = "자리를 비운 사람 중엔 맞는 이름이 없어요"

    /** 걸러서 아무도 안 남았을 때의 제목. 전체 칸이면 null — 원래 빈 문구(이름 찾기 · 빈 명부)가 말한다. */
    fun empty(presence: MessagesPresenceFilter, isSearching: Boolean): String? = when (presence) {
        MessagesPresenceFilter.all -> null
        MessagesPresenceFilter.working -> if (isSearching) noMatchWorking else noneWorking
        MessagesPresenceFilter.away -> if (isSearching) noMatchAway else noneAway
    }
}
