// 원본: Sources/check/CheckTodoBoardView.swift:14-90(TodoBoardStrings · TodoDraftInput) @ ef9fab11
package com.yehsung.aingcheck.desktop.overlay.todoboard

import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.rules.todo.TodoRules

/**
 * 보드 문구(맥 TodoBoardStrings — 사용자가 확정한 제품 문구). 외양 조절 문구(진하기·⌥+스크롤)는 외양 갈래(다음 웨이브, W-3 #9)가 가져온다.
 */
object TodoBoardStrings {
    const val TITLE = "오늘 할 일"
    const val CLOSE = "닫기"
    const val PLACEHOLDER = "할 일 추가"

    /** 빈 상태 2줄: 첫 줄은 사실(비었다), 둘째 줄은 다음 행동(적고 Enter). */
    const val EMPTY_TITLE = "오늘 할 일이 비어 있어요"
    const val EMPTY_HINT = "위에 적고 Enter를 누르세요"
    const val DELETED = "삭제됨"
    const val UNDO = "되돌리기"

    /** 이 목록이 어디에 저장되는지(v0.3.30 — 내 계정에 저장돼 다른 기기와 맞춰진다). */
    const val FOOTER = "내 계정에 저장돼 다른 기기와 맞춰져요"
    const val MARK_DONE = "완료로 표시"
    const val MARK_UNDONE = "완료 취소"
    const val DELETE_ITEM = "삭제"
    const val EDIT_TITLE = "할 일 수정"

    fun oldSection(count: Int): String = "오래된 항목 ($count)"

    /** 입력 카운터. 분모는 규칙([TodoRules.maxTitleLength])에서 읽는다 — 문구와 실제 제한이 갈라지지 않게. */
    fun counter(current: Int): String = "$current/${TodoRules.maxTitleLength}"

    fun carriedFrom(badge: String): String = "${badge}부터 이월됨"
}

/**
 * 제목 입력 길이 판정(맥 TodoDraftInput) — '막는다 vs 자른다'는 사용자가 확정한 제품 결정이라 값으로 지킨다.
 * 길이는 두 잣대: 글자(그래핌, Swift `count`)와 코드 포인트(Swift `unicodeScalars.count`).
 */
object TodoDraftInput {
    /**
     * 새 입력(proposed)을 반영할지 고른다. 반영하지 않으면 이전 값(current)을 그대로 돌려준다.
     * - 줄어드는 방향(글자·코드 포인트 둘 다 늘지 않음)은 무조건 통과 — 100자를 넘긴 값에 갇히지 않게.
     * - 늘어나는 방향은 [TodoRules.titleFitsLimits](글자 100 · 코드 포인트 1000)까지. **넘치면 자르지 않고 통째로 거부**.
     */
    fun accepted(current: String, proposed: String): String {
        if (graphemes(proposed) <= graphemes(current) && codePoints(proposed) <= codePoints(current)) return proposed
        return if (TodoRules.titleFitsLimits(proposed)) proposed else current
    }

    /** 카운터 문구. 90자([TodoRules.counterVisibleFrom]) 미만이면 null — 평소엔 숫자를 안 띄운다. */
    fun counterText(text: String): String? {
        val count = graphemes(text)
        if (count < TodoRules.counterVisibleFrom) return null
        return TodoBoardStrings.counter(count)
    }

    internal fun graphemes(text: String): Int = Graphemes.count(text)
    internal fun codePoints(text: String): Int = text.codePointCount(0, text.length)
}
