// 원본: Sources/CheckCore/CenterLabel.swift @ 1b8260d
package com.yehsung.aingcheck.core.wire

/** 소속 센터 서버값(`seoul`/`busan`) ↔ 화면 글자. 모르는 값은 nil(배지 없음). 순위에는 영향이 없다. */
object CenterLabel {
    const val seoul = "seoul"
    const val busan = "busan"
    val allServerValues: List<String> = listOf(seoul, busan)

    fun display(serverValue: String?): String? = when (serverValue) {
        seoul -> "서울"
        busan -> "부산"
        else -> null
    }

    fun serverValue(forDisplay: String?): String? = when (forDisplay) {
        "서울" -> seoul
        "부산" -> busan
        else -> null
    }

    fun isKnown(serverValue: String?): Boolean = display(serverValue) != null
}
