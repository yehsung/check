// 원본: 없음 — Android 판 7 이 맥 0.3.74 이슬 아잉이(술 한잔 선물)를 받고, Windows v1 은 기능 동결로 받지 않는다(플랫폼 문 하나).
package com.yehsung.aingcheck.ui.components

/**
 * 이 플랫폼이 술 한잔 선물(이슬 아잉이)을 받는가 — [CharacterArt.takesDrinkGift] 가 읽는 단 한 곳. Android 참 · 데스크톱(Windows v1) 거짓.
 * 거짓이면 상점 능력 번호가 4 에 머문다(서버가 이슬 행 · 술 선물을 안 싣는다).
 */
internal expect val PlatformTakesDrinkGift: Boolean
