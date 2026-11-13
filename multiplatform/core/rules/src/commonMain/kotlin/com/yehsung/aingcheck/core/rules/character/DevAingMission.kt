// 원본: Sources/CheckCore/CharacterKit/DevAing.swift:272-285(DevAingMission — 글자 · 키) @ e4995a3a
package com.yehsung.aingcheck.core.rules.character

/**
 * 개발에 찌든 아잉이의 얻는 길 — 도전 미션 '누적 근무 100시간'(맥 0.3.81 · 대표 #d_OwYy6Avg5alV "미션보상으로 가자. 총 누적근무시간 100시간
 * 이상달성"). 목표 · 진행 · 제목은 서버 응답(`character_missions`)이 말하고, 여기는 화면 글자와 받기 키만 둔다(맥 · 폰과 한 글자도 다르지 않다).
 */
object DevAingMission {
    /** 서버 정의표의 키 — 받기 요청이 싣는다. */
    const val key = "work100"

    /** 상점 · 고르기 잠긴 칸의 아래 줄(자물쇠 옆). */
    const val lockedCaption = "미션 보상"

    /** 잠긴 칸을 눌렀을 때 · 말풍선 — 얻는 길. */
    const val lockedHint = "누적 미션 '누적 근무 100시간'을 채우면 받아요"

    /** 미션 줄의 진행 숫자("37/100시간"). */
    fun count(progress: Long, target: Long): String = "${maxOf(0L, progress)}/${maxOf(1L, target)}시간"

    /** 받기 성공 한 줄(미션 화면 안내줄 — 캐릭터는 [캐릭터]에서 입는다). */
    fun received(name: String): String = "${name}를 받았어요! [캐릭터]에서 입어 보세요"

    /** 받기 단추 톡백("받기, 개발에 찌든 아잉이"). */
    fun claimAccessibility(name: String): String = "받기, $name"
}
