// 원본: 없음 — 계측·스냅숏 시험이 화면 자리를 찾는 표식(Compose testTag). 사용자에게 보이지 않는다.
package com.yehsung.aingcheck.ui.screens.messages

object MessagesTags {
    const val LIST_SCREEN = "messages-list"
    const val LIST_SUBTITLE = "messages-list-subtitle"
    const val MEGAPHONE_BUTTON = "messages-megaphone"
    const val NEW_CONVERSATION_BUTTON = "messages-new-conversation"
    const val BLOCK_NOTICE = "messages-block-notice"
    fun threadRow(peerID: String): String = "messages-thread-$peerID"

    const val CONVERSATION_SCREEN = "conversation"
    const val BACK = "conversation-back"
    const val MORE_MENU = "conversation-more"
    const val MENU_REPORT = "conversation-menu-report"
    const val MENU_BLOCK = "conversation-menu-block"
    const val MENU_COPY = "bubble-menu-copy"
    const val MENU_REPORT_MESSAGE = "bubble-menu-report"
    fun bubble(messageID: String): String = "bubble-$messageID"
    fun pending(localID: String): String = "pending-$localID"
    const val NEW_MESSAGE_BUTTON = "conversation-new-message"

    const val COMPOSER_FIELD = "composer-field"
    const val SEND = "composer-send"
    const val COUNTER = "composer-counter"
    const val SEND_NOTICE = "composer-send-notice"
    const val STICKER_BUTTON = "composer-sticker"
    fun stickerCell(raw: String): String = "sticker-cell-$raw"
    const val STICKER_SHEET = "sticker-sheet"

    const val NEW_CONVERSATION_SHEET = "new-conversation-sheet"
    const val NEW_CONVERSATION_SEARCH = "new-conversation-search"
    fun person(userID: String): String = "person-$userID"

    const val MEGAPHONE_SHEET = "megaphone-sheet"
    const val MEGAPHONE_FIELD = "megaphone-field"
    const val MEGAPHONE_SEND = "megaphone-send"
    const val MEGAPHONE_CONFIRM = "megaphone-confirm"

    const val BLOCK_SHEET = "block-sheet"
    const val BLOCK_CONFIRM = "block-confirm"
    const val REPORT_SHEET = "report-sheet"
    fun reportReason(raw: String): String = "report-reason-$raw"
    const val REPORT_DETAIL = "report-detail"
    const val REPORT_ALSO_BLOCK = "report-also-block"
    const val REPORT_SUBMIT = "report-submit"
}
