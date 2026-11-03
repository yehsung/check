// 원본: wt-phone-1017 2ad01732 Sources/CheckMobileKit/Messages/MessagesRules.swift(MessagesListRules.preview = plainPreview → 공백 접기) ·
//       Tests/CheckMobileKitTests/V1017ChatMarkdownMobileTests.swift(날것 네 자리 — 대화 목록 미리보기).
// 판 7 Android: 대화 목록 미리보기가 서식 기호를 벗기는가(폰만 — MessagesStore.chatMarkdown) · 꺼진 조립(Windows)은 글자 그대로인가.
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MessageThreadBuilder
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import kotlin.test.Test
import kotlin.test.assertEquals

class MessagesChatMarkdownListTest {
    @Test
    fun previewStripsFormattingOnlyWhenTheAssemblyAsks() {
        val body = "## 공지\n**오늘**  [회의록](https://docs.example/a)\t확인 `코드`"
        assertEquals("공지 오늘 회의록 확인 `코드`", MessagesListRules.preview(body, chatMarkdown = true))
        // 기준선: 꺼진 조립(Windows · 기본값)은 예전 글자 그대로(공백 접기만).
        assertEquals("## 공지 **오늘** [회의록](https://docs.example/a) 확인 `코드`", MessagesListRules.preview(body))
        // 이모티콘 규칙이 먼저다 · 평범한 본문은 같다.
        assertEquals("아잉이 기쁨", MessagesListRules.preview("[아잉:기쁨]", chatMarkdown = true))
        for (plain in listOf("오늘 점심 같이 드실래요?", "-_- 아 진짜", "https://a.example/x")) {
            assertEquals(MessagesListRules.preview(plain), MessagesListRules.preview(plain, chatMarkdown = true))
        }
    }

    @Test
    fun threadRowsCarryTheFlag() {
        val entry = MessageEntry(
            MessageHistoryEntry(
                id = "m1", peerUserID = "p1", peerName = "민수", peerAvatarURL = null, body = "**굵게** [링크](https://a.example)",
                createdAt = SwiftDate(1_789_550_400.0), isMine = true,
            ),
        )
        fun preview(flag: Boolean) = MessagesThreadListRules.rows(
            threads = MessageThreadBuilder.threads(listOf(entry), null),
            pokes = emptyList(), chronology = emptyMap(), messageUnreadPeerIDs = emptySet(), pokeUnreadPeerIDs = emptySet(),
            unreadCounts = emptyMap(), workingPeerIDs = emptySet(), workKnown = false, now = SwiftDate(1_789_550_500.0), chatMarkdown = flag,
        ).single().previewText
        assertEquals("굵게 링크", preview(true))
        assertEquals("**굵게** [링크](https://a.example)", preview(false))
    }
}
