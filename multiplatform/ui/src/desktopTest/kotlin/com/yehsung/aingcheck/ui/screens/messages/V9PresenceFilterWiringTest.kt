// 원본: Tests/CheckMobileKitTests/V1019PresenceFilterTests.swift(wiring) @ 777a0e31
package com.yehsung.aingcheck.ui.screens.messages

import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** 판 9 — 사람 찾기 시트가 보일 사람(이름 찾기 + 칸)을 그리고 · 칸 줄은 스토어 고르기로 · 빈 문구는 칸의 말 먼저. 주석을 걷고 본다. */
class V9PresenceFilterWiringTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))

    @Test
    fun sheetDrawsTheFilteredDirectoryAndTheSegmentRow() {
        val sheet = SwiftStyleComments.strip(File(mpRoot, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/MessagesSheets.kt").readText())
            .filter { !it.isWhitespace() }
        assertTrue(sheet.contains("valpeople=store.visibleDirectory(q)"), "시트가 칸을 거친 목록을 그리지 않는다")
        assertFalse(sheet.contains("store.filteredDirectory(q)"), "시트가 칸을 안 거친 목록을 그린다")
        assertTrue(sheet.contains("PresenceFilterRow(presence){store.selectDirectoryPresenceFilter(it)}"))
        assertTrue(sheet.contains("SingleChoiceSegmentedButtonRow("), "칸 줄이 분할 버튼이 아니다")
        assertTrue(sheet.contains("MessagesPresenceFilterText.empty(presence,isSearching=q.isNotBlank())"), "빈 문구가 칸의 말을 먼저 보지 않는다")
    }
}
