// 원본: Tests/checkTests/GoldenExport/app-rules/GoldenExportAppRulesMessages.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.testkit.golden.Golden
import kotlin.test.Test

/** 메시지 글자 규칙 골든의 JVM 대조. 같은 판정을 Android 계측이 ART 에서 다시 돈다(완료 ②). */
class MessageGoldenTest {
    @Test
    fun messageRulesMatchSwift() {
        val scenarios = MessageGoldenChecks.messageRules(Golden.load("text/message-rules"))
        println("AINGCHECK-W1C message-rules scenarios=$scenarios")
    }

    @Test
    fun blockReportMatchesSwift() = MessageGoldenChecks.blockReport(Golden.load("text/block-report"))

    @Test
    fun megaphoneMatchesSwift() = MessageGoldenChecks.megaphone(Golden.load("text/megaphone"))
}
