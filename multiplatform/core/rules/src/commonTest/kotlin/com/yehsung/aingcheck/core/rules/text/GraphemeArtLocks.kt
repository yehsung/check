// 원본: 없음(6차 c-fold — G §8-17 2 (a): API 별 그래핌 knownDivergence 잠금. 실측: emu.sh 포트 5566 · aingcheck-api26 · aingcheck-api36)
package com.yehsung.aingcheck.core.rules.text

/**
 * ART 그래핌(플랫폼 BreakIterator = 기기 ICU 판)이 Swift 와 갈리는 줄을 **API 수준별로** 잠근다(G §8-17 2 (a) — minSdk 26 유지).
 * 판정은 [TextGoldenChecks.graphemes] 가 한다. 재지 않은 API 는 목록이 없어 빨강이다(조용히 넘어가지 않는다 — 재서 더한다).
 *
 * 영향(§8-17 2): 낡은 기기(ICU 58 · 유니코드 9)에서는 피부색 수식자가 붙은 이모지 등이 앱 쪽 글자 수 제한에서 2자로 셀 수 있다
 * (서버 제한은 스칼라 눈금이라 따로다). 화면이 Swift 와 다른 경계를 그리는 줄이 정확히 아래 목록이다.
 */
object GraphemeArtLocks {
    sealed interface Lock

    /**
     * 골든 knownDivergence(InCB 2줄)만 허용 폭(Swift 값 또는 legacyClusters) — 나머지 줄은 Swift 값이어야 한다. 잰 API 는 모두 [Exact] 라
     * 지금 이 잠금을 쓰는 API 는 없다(재지 않은 기기를 임시로 받을 때의 꼴로 남긴다 — 쓰면 늘어남 하나를 놓친다).
     */
    data object GoldenListOnly : Lock

    /** 이 API 에서 Swift 와 다른 줄 **전부**(id → 그 기기가 내는 그래핌마다 스칼라 수). 목록 밖은 Swift 값, 목록 안은 정확히 이 값. */
    data class Exact(val api: Int, val runtime: String, val lines: Map<String, List<Int>>) : Lock

    /**
     * API 26(Android 8.0 · ICU 58.2 · 유니코드 9.0 — `system-images/android-26/google_apis/arm64-v8a` r1, OSR1.180418.028.A3).
     * 실측(2026-10-28 · 포트 5566, 봉인 · 읽기 전용 — W0-f ③ 측정기와 같은 26줄): Swift 와 갈리는 줄 **26** = InCB 2(g-018 · g-019 — JDK 21 과 같은
     * 옛 규칙 값) + 피부색 수식자 U+1F3FB…1F3FF 가 든 줄 23 + ZWJ 뒤 그림 문자 1(g-023). 할 일 제목 · 기기 이름 꼴(app-*) 8줄은 Swift 와 같다. ICU 58 은 GB10(E_Base × E_Modifier)의 E_Base 표가 유니코드 9 이라 새 이모지 바탕에 수식자를 붙이지 않고,
     * GB11 이 ZWJ 뒤 Glue_After_Zwj 만 잇는다(유니코드 11 의 Extended_Pictographic 규칙 전).
     */
    private val API_26 = Exact(
        api = 26,
        runtime = "Android 8.0 · ICU 58.2 · Unicode 9.0",
        lines = linkedMapOf(
            "g-018" to listOf(2, 1),   // InCB
            "g-019" to listOf(3, 1),   // InCB
            "g-023" to listOf(2, 1),   // ZWJ 뒤 그림 문자
            "g-038" to listOf(1, 1, 1, 1, 2),   // 피부색 수식자
            "g-044" to listOf(1, 1, 1, 2, 3),   // 피부색 수식자
            "g-055" to listOf(1, 1, 2),   // 피부색 수식자
            "g-057" to listOf(1, 1, 1, 1, 1),   // 피부색 수식자
            "g-059" to listOf(1, 1, 1, 2, 1, 1, 1),   // 피부색 수식자
            "g-077" to listOf(1, 1, 1, 1),   // 피부색 수식자
            "g-099" to listOf(1, 2, 2),   // 피부색 수식자
            "g-115" to listOf(1, 1, 3, 2),   // 피부색 수식자
            "g-116" to listOf(1, 1, 2, 2, 1, 1),   // 피부색 수식자
            "g-139" to listOf(1, 1, 1, 1),   // 피부색 수식자
            "g-147" to listOf(1, 1, 1, 1, 1, 1, 1),   // 피부색 수식자
            "g-161" to listOf(2, 1, 1, 1),   // 피부색 수식자
            "g-169" to listOf(1, 1, 2, 1, 1),   // 피부색 수식자
            "g-200" to listOf(1, 1),   // 피부색 수식자
            "g-202" to listOf(1, 1, 1),   // 피부색 수식자
            "g-208" to listOf(1, 1, 3),   // 피부색 수식자
            "g-217" to listOf(1, 1, 1, 1, 1, 1),   // 피부색 수식자
            "g-218" to listOf(1, 2),   // 피부색 수식자
            "g-245" to listOf(1, 1, 2, 1, 2, 1),   // 피부색 수식자
            "g-252" to listOf(2, 2, 2, 2),   // 피부색 수식자
            "g-275" to listOf(2, 1, 1, 1, 1, 1),   // 피부색 수식자
            "g-276" to listOf(1, 1, 2, 1, 1),   // 피부색 수식자
            "g-296" to listOf(2, 3, 2),   // 피부색 수식자
        ),
    )

    /**
     * API 36(Android 16 · ICU 76.1 · 유니코드 16.0 — `system-images/android-36/google_apis_playstore/arm64-v8a` r7, BE2A.250530.026.D1).
     * 실측(2026-10-28 · 포트 5566 — W0-f ③ 측정기와 같은 0줄): Swift 와 갈리는 줄 **0**(InCB 2줄도 Swift 값). 그래서 빈 목록으로 **정확히** 잠근다 —
     * 한 줄이라도 갈리면(기기 ICU 가 메인라인 갱신으로 바뀌는 등) 빨강이고, 그 기기에서 잰 값을 여기 더한다(G §8-17 2 '늘거나 줄면 빨강').
     * 예전 [GoldenListOnly](InCB 2줄을 옛 값으로도 허용)는 0→2줄로 늘어도 초록이었다(6차 c-fold 검증 지적).
     */
    private val API_36 = Exact(api = 36, runtime = "Android 16 · ICU 76.1 · Unicode 16.0", lines = emptyMap())

    /** API 수준 → 잠금. 재지 않은 API(27~35 · 실기기)는 목록이 없어 빨강이다. */
    val byApi: Map<Int, Lock> = linkedMapOf(26 to API_26, 36 to API_36)

    val measuredApis: Set<Int> get() = byApi.keys

    fun forApi(api: Int): Lock? = byApi[api]
}
