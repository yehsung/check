// 원본: Tests/checkTests/CheckTodoBoardViewTests.swift:10-112(문구·초안 길이·카운터) @ ef9fab11
package com.yehsung.aingcheck.desktop.overlay.todoboard

import com.yehsung.aingcheck.core.rules.todo.TodoRules
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

class TodoDraftInputTest {
    @Test
    fun stringsAreTheConfirmedProductCopy() {
        assertEquals("오늘 할 일", TodoBoardStrings.TITLE)
        assertEquals("할 일 추가", TodoBoardStrings.PLACEHOLDER)
        assertEquals("삭제됨", TodoBoardStrings.DELETED)
        assertEquals("되돌리기", TodoBoardStrings.UNDO)
        // v0.3.30: 내 계정에 저장(이 맥에만 저장된다는 옛 문구는 사실과 반대).
        assertEquals("내 계정에 저장돼 다른 기기와 맞춰져요", TodoBoardStrings.FOOTER)
    }

    @Test
    fun emptyStateKeepsFactAndNextActionOnSeparateLines() {
        assertEquals("오늘 할 일이 비어 있어요", TodoBoardStrings.EMPTY_TITLE)
        assertEquals("위에 적고 Enter를 누르세요", TodoBoardStrings.EMPTY_HINT)
        assertNotEquals(TodoBoardStrings.EMPTY_TITLE, TodoBoardStrings.EMPTY_HINT)
    }

    @Test
    fun oldSectionHeaderCarriesTheCount() {
        assertEquals("오래된 항목 (3)", TodoBoardStrings.oldSection(3))
    }

    @Test
    fun counterDenominatorComesFromTheRuleNotALiteral() {
        assertEquals("95/${TodoRules.maxTitleLength}", TodoBoardStrings.counter(95))
    }

    @Test
    fun draftAcceptsExactlyTheMaximumLength() {
        val full = "a".repeat(TodoRules.maxTitleLength)
        assertEquals(full, TodoDraftInput.accepted(full.dropLast(1), full))
    }

    @Test
    fun draftBlocksTheCharacterPastTheLimitInsteadOfTruncating() {
        val full = "a".repeat(TodoRules.maxTitleLength)
        assertEquals(full, TodoDraftInput.accepted(full, full + "b"))
    }

    @Test
    fun draftRejectsAnOverlongPasteWholeRatherThanKeepingItsPrefix() {
        val paste = "가".repeat(150)
        assertEquals("메모", TodoDraftInput.accepted("메모", "메모$paste"), "접두만 남기지 않고 통째로 되돌린다")
    }

    @Test
    fun draftAlwaysAllowsShorteningEvenFromAnOverlongValue() {
        val over = "a".repeat(130)
        assertEquals(over.dropLast(1), TodoDraftInput.accepted(over, over.dropLast(1)))
    }

    @Test
    fun draftCountsKoreanSyllablesAsOneCharacterEach() {
        val full = "가".repeat(TodoRules.maxTitleLength)
        assertEquals(full, TodoDraftInput.accepted("", full))
        assertEquals(full, TodoDraftInput.accepted(full, full + "나"))
    }

    @Test
    fun draftRejectsCodePointGrowthHiddenInsideOneCharacter() {
        // 글자 수는 그대로인데 코드 포인트만 1000 을 넘기는 바꿔치기(서버 상한) — 두 잣대로 잰다.
        val proposed = "a" + "́".repeat(TodoRules.maxTitleCodePoints)
        assertEquals("a", TodoDraftInput.accepted("a", proposed))
    }

    @Test
    fun counterStaysHiddenBelowTheVisibleThreshold() {
        assertNull(TodoDraftInput.counterText("a".repeat(TodoRules.counterVisibleFrom - 1)))
    }

    @Test
    fun counterAppearsFromTheThresholdThroughTheLimit() {
        assertEquals("90/100", TodoDraftInput.counterText("a".repeat(90)))
        assertEquals("100/100", TodoDraftInput.counterText("가".repeat(100)))
    }
}
