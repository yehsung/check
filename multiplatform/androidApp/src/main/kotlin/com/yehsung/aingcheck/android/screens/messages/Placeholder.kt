// 자리표시 — 메시지 탭(E§3.2). 주인: W3-a. 셸(W1-g)이 둔다.
package com.yehsung.aingcheck.android.screens.messages

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.android.nav.Dest
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.shell.PlaceholderLink
import com.yehsung.aingcheck.android.shell.PlaceholderScreen

private const val OWNER = "W3-a 메시지"

@Composable
fun MessagesListPlaceholder(open: (Any) -> Unit) = PlaceholderScreen(
    "메시지", OWNER, detail = AingRoute.Messages.url,
    links = listOf(
        PlaceholderLink("대화 열기(예시)") { open(Dest.Conversation("demo-peer")) },
        PlaceholderLink("새 대화") { open(Dest.NewConversationSheet) },
        PlaceholderLink("확성기") { open(Dest.MegaphoneSheet) },
    ),
)

@Composable
fun ConversationPlaceholder(peerId: String, open: (Any) -> Unit) = PlaceholderScreen(
    "대화", OWNER, detail = AingRoute.safeId(peerId)?.let { AingRoute.Message(it).url } ?: "peer=$peerId",
    links = listOf(PlaceholderLink("신고") { open(Dest.ReportSheet(peerId)) }, PlaceholderLink("차단") { open(Dest.BlockConfirm(peerId)) }),
)

@Composable
fun NewConversationSheetPlaceholder() = PlaceholderScreen("새 대화 시트", OWNER)

@Composable
fun MegaphoneSheetPlaceholder() = PlaceholderScreen("확성기 시트", OWNER, detail = "2단 확인 · 10분 1회 · 가격은 서버값")

@Composable
fun ReportSheetPlaceholder(subjectId: String) = PlaceholderScreen("신고 시트", OWNER, detail = "subject=$subjectId")

@Composable
fun BlockConfirmPlaceholder(peerId: String) = PlaceholderScreen("차단 확인", OWNER, detail = "peer=$peerId")
