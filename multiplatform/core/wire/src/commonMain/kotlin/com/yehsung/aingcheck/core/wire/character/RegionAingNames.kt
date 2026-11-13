// 원본: Sources/CheckCore/CharacterKit/RegionAing.swift:18-55(id · 표시 이름 · 센터 이름) @ e4995a3a
package com.yehsung.aingcheck.core.wire.character

/**
 * 지역 아잉이(부산 갈매기 · 서울의 밤 — 우리 센터 선물, 상점 번호 10)의 이름 글자만. 그림 · 3D 마감 수치는 옮기지 않는다 —
 * Android 판 8 은 지역 아잉이 그림을 싣지 않아 번호 10 을 말하지 않고(서버가 그 행 · 선물을 안 보낸다), 카탈로그 이름 · 선물 문구만 맥과 같게 둔다.
 */
object RegionAingNames {
    const val busanID = "aing_busan"
    const val seoulID = "aing_seoul"
    const val busanDisplayName = "부산 갈매기 아잉이"
    const val seoulDisplayName = "서울의 밤 아잉이"
    const val busanCenter = "busan"
    const val seoulCenter = "seoul"

    /** 센터 원문(`profiles.center`) → 그 센터의 아잉이 id. 모르는 센터는 null. */
    fun characterID(center: String?): String? = when (center) {
        busanCenter -> busanID
        seoulCenter -> seoulID
        else -> null
    }

    /** 아잉이 id → 센터 원문. 지역 아잉이가 아니면 null. */
    fun center(characterID: String?): String? = when (characterID) {
        busanID -> busanCenter
        seoulID -> seoulCenter
        else -> null
    }

    /** 아잉이 id → 화면에 쓰는 센터 이름("부산" · "서울"). 지역 아잉이가 아니면 null. */
    fun centerName(characterID: String?): String? = when (characterID) {
        busanID -> "부산"
        seoulID -> "서울"
        else -> null
    }
}
