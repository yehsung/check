// 원본: Sources/check/WorkTimerStorePoke.swift 978-980(focusStageRecordKey — ★F3 사용자별 · 소문자) @ a90d8623
package com.yehsung.aingcheck.feature.desktop.focus

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** ★F3 기록 키는 로캘과 무관하게 소문자(Locale.ROOT). tr-TR 에서 "I".lowercase(로캘) = "ı" 가 되는 함정을 잰다. */
class FocusRecordKeyTest {
    private fun <T> withLocale(locale: Locale, body: () -> T): T {
        val saved = Locale.getDefault()
        Locale.setDefault(locale)
        try {
            return body()
        } finally {
            Locale.setDefault(saved)
        }
    }

    @Test
    fun keyIsRootLowercaseEvenInTurkishLocale() {
        val tr = Locale.forLanguageTag("tr-TR")
        // 대조: 이 JVM 에서 로캘 소문자화는 정말로 다르다(이 시험이 헛돌지 않는다는 증거).
        assertEquals("ı", "I".lowercase(tr))
        val keys = withLocale(tr) {
            listOf("00000000-0000-0000-0000-0000000000AB", "TITLE-I", "İSTANBUL").map(FocusStageRecords::key)
        }
        assertEquals(
            listOf("focusStageRecord.00000000-0000-0000-0000-0000000000ab", "focusStageRecord.title-i", "focusStageRecord.i̇stanbul"),
            keys,
        )
    }

    @Test
    fun sameUserDifferentCaseSharesOneRecord() {
        val kv = InMemoryDesktopKeyValueStore()
        val records = FocusStageRecords(kv)
        val record = FocusStageRecord(FocusStage.TIMED, SwiftDate(1_793_010_800.0))
        withLocale(Locale.forLanguageTag("tr-TR")) {
            records.write(record, "ABCDEF-I")
        }
        assertEquals(record, records.read("abcdef-i"))
        assertEquals(listOf("focusStageRecord.abcdef-i"), kv.keys(FocusStageRecords.KEY_PREFIX))
        assertNull(records.read("someone-else"), "사용자별 칸")
    }

    @Test
    fun recordRoundTripsAndBrokenRecordIsNull() {
        val kv = InMemoryDesktopKeyValueStore()
        val records = FocusStageRecords(kv)
        for (r in listOf(
            FocusStageRecord(FocusStage.TIMED, SwiftDate(1_793_010_800.25)),
            FocusStageRecord(FocusStage.ALWAYS, null),
            FocusStageRecord(FocusStage.TIMED, null),
        )) {
            records.write(r, "u")
            assertEquals(r, records.read("u"))
        }
        for (broken in listOf("", "{", """{"stage":"nope"}""", """{"stage":1}""", """{"stage":"timed","until":"x"}""")) {
            kv.putString(FocusStageRecords.key("u"), broken)
            assertNull(records.read("u"), "깨진 기록 '$broken' = null")
        }
    }
}
