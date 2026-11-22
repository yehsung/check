// 원본: 없음 — 계측·스냅숏 시험이 화면 자리를 찾는 표식(Compose testTag). 사용자에게 보이지 않는다.
package com.yehsung.aingcheck.ui.screens.messages

object MessagesTags {
    const val LIST_SCREEN = "messages-list"
    const val MARK_ALL_READ = "messages-mark-all-read"
    const val LIST_SUBTITLE = "messages-list-subtitle"
    const val MEGAPHONE_BUTTON = "messages-megaphone"
    const val NEW_CONVERSATION_BUTTON = "messages-new-conversation"
    const val BLOCK_NOTICE = "messages-block-notice"
    /** 내 집중이면 대화 목록 위 한 줄(판 7 · MessagesFocusRules.listNotice). */
    const val LIST_FOCUS_NOTICE = "messages-list-focus-notice"
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
    /** 지난 확성기(판 9) — 작성 시트의 문 · 페이지 · 줄 · 더 보기. */
    const val MEGAPHONE_FEED_ENTRY = "megaphone-feed-entry"
    /** 대화 맨 위 '이전 대화 더 보기' 줄(판 9). */
    const val OLDER_ROW = "conversation-older-row"
    const val MEGAPHONE_FEED_PAGE = "megaphone-feed-page"
    fun megaphoneFeedRow(id: String) = "megaphone-feed-row-$id"
    const val MEGAPHONE_FEED_MORE = "megaphone-feed-more"
    /** 사람 찾기 거르기 칸(판 9) — 칸마다 꼬리표 `new-conversation-presence-<all|working|away>`. */
    const val NEW_CONVERSATION_PRESENCE = "new-conversation-presence"
    fun presenceSegment(name: String) = "new-conversation-presence-$name"
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
    /** 판 9 — 메시지 사진(입력줄 [사진] · 말풍선 · 미리 보기 · 크게 보기). */
    const val PHOTO_BUTTON = "messages-photo-button"
    const val PHOTO_PREVIEW = "messages-photo-preview"
    const val PHOTO_PREVIEW_SEND = "messages-photo-preview-send"
    const val PHOTO_PREVIEW_CANCEL = "messages-photo-preview-cancel"
    const val PHOTO_VIEWER = "messages-photo-viewer"
    const val PHOTO_VIEWER_CLOSE = "messages-photo-viewer-close"
    fun photoBubble(id: String) = "messages-photo-bubble:$id"
}
