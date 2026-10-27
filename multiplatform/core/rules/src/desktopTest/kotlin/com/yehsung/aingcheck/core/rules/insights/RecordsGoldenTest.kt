// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesRecords.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.insights

import com.yehsung.aingcheck.testkit.golden.Golden
import kotlin.test.Test

/** 기록 · 주간 · 날짜 · 숫자 · 토큰 · 리밋 골든의 JVM 대조 — 판정은 [RecordsGoldenChecks](commonTest)에 있고 Android 계측이 같은 판정을 ART 에서 다시 돈다. */
class RecordsGoldenTest {
    @Test
    fun weeklyStatusMatchesSwift() = RecordsGoldenChecks.weeklyStatusMatchesSwift(Golden.load("weekly/status"))

    @Test
    fun datesParseMatchesSwift() = RecordsGoldenChecks.datesParseMatchesSwift(Golden.load("dates/parse"))

    @Test
    fun datesDurationsMatchSwift() = RecordsGoldenChecks.datesDurationsMatchSwift(Golden.load("dates/durations"))

    @Test
    fun insightsComputationMatchesSwift() = RecordsGoldenChecks.insightsComputationMatchesSwift(Golden.load("insights/computation"))

    @Test
    fun insightsTokenMatchesSwift() = RecordsGoldenChecks.insightsTokenMatchesSwift(Golden.load("insights/token"))

    @Test
    fun numberFormatMatchesSwift() = RecordsGoldenChecks.numberFormatMatchesSwift(Golden.load("text/number-format"))

    @Test
    fun aiLimitMatchesSwift() = RecordsGoldenChecks.aiLimitMatchesSwift(Golden.load("dates/ailimit"))
}
