// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesTodo.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.todo

import com.yehsung.aingcheck.testkit.golden.Golden
import kotlin.test.Test

/** 할 일 골든(E12)의 JVM 대조 — 판정은 [TodoGoldenChecks](commonTest)에 있고 Android 계측이 같은 판정을 ART 에서 다시 돈다. */
class TodoGoldenTest {
    @Test
    fun todoRulesMatchSwift() = TodoGoldenChecks.todoRulesMatchSwift(Golden.load("todo/rules"))

    @Test
    fun todoWireMatchesSwift() = TodoGoldenChecks.todoWireMatchesSwift(Golden.load("todo/wire"))
}
