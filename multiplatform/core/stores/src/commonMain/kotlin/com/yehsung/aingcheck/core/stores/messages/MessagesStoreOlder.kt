// 원본: Sources/CheckMobileKit/Messages/MessagesStoreOlder.swift @ 7142916e (폰 1.0.19 — 이전 대화 더 보기 · 맥 0.3.86 WorkTimerStoreMessageOlder 의 폰 짝)
//
// 판 9(대표 #d_xygj8oZRFlfH 4번 메시지 묶음 · 맥 #d_IKem7qxZXc5b "메시지 30일로 늘리기"). 전선은 코어 RpcMessagePage · MessagePageWire 한 곳,
// 규칙(머리가 이긴다 · 앞에 붙이기 · 머리 미끄러짐 · 읽음 따라가기)은 코어 MessageOlderHistoryRules 한 곳이다. 지키는 다섯:
//  ① 24시간 머리(history)는 그대로 — 지난 쪽은 olderPages 에 따로 든다(점 · 읽음 처리 · 모두 읽음에 안 들어간다).
//  ② 서버를 부르는 자리는 버튼 하나(loadOlderMessages) — 대화 열기 · 폴링 · 전송 · 도착에서 부르지 않는다.
//  ③ 쓸 수 있는가는 세 갈래(null · false · true). 404/PGRST202 면 숨기고, 다음 대화 열기에서 모름으로 되돌린다.
//  ④ 세대 · 순번 · 상대 가드 — 로그아웃 · 닫기 · 상대 바꾸기 뒤 응답은 버린다.
//  ⑤ 본문은 사람이 쓴 문장 — 로그 금지.
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchMessagePage
import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import com.yehsung.aingcheck.core.rules.text.MessageOlderHistoryRules
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import kotlinx.coroutines.launch

/** 지난 쪽을 붙인 직후 대화가 제자리를 지키게 하는 표(맥 `MessageOlderScrollAnchor` · 아이폰과 같다). */
data class MessagesOlderScrollAnchor(val serial: Int, val messageID: String)

/** 대화 맨 위 줄의 모양(순수). null = 줄이 없다(함수 없는 서버 · 로그인 전). */
enum class MessagesOlderRowState {
    button, loading, failed, end;

    val title: String
        get() = when (this) {
            button -> MessageNoticeText.olderButtonTitle
            loading -> MessageNoticeText.olderLoading
            failed -> MessageNoticeText.olderFailed
            end -> MessageNoticeText.olderEnd
        }

    val isTappable: Boolean get() = this == button || this == failed
}

/** 대화에 그릴 메시지 — 지난 쪽 + 24시간 머리(다시 정렬하지 않고 잇는다 · 머리에 있는 id 는 지난 쪽에서 뺀다 · 내 말 읽음은 머리를 따른다). */
fun MessagesStore.conversationMessages(peerID: String): List<MessageEntry> {
    val head = thread(peerID)?.messages ?: emptyList()
    val older = olderPages[peerID]
    if (peerID in hiddenBlockedPeerIDs || older.isNullOrEmpty()) return head
    return MessageOlderHistoryRules.merged(older, head.map { it.wire }).map(::MessageEntry)
}

/** 대화 맨 위 줄. 함수가 없는 서버면 null — 화면은 이것 하나만 본다(게이트 짝: loadOlderMessages 가드와 같은 조건). */
fun MessagesStore.olderRowState(peerID: String): MessagesOlderRowState? {
    if (!isSignedIn || peerID.isEmpty() || olderAvailable == false) return null
    if (olderLoading) return MessagesOlderRowState.loading
    if (olderFailed) return MessagesOlderRowState.failed
    if (olderHasMore[peerID] == false) return MessagesOlderRowState.end
    return MessagesOlderRowState.button
}

/** 대화 위 보관 안내 — message_page 가 한 번이라도 성공한 뒤에만 30일 문장(모르거나 없는 서버는 예전 24시간 문장). */
val MessagesStore.expiryNotice: String
    get() = if (olderAvailable == true) MessageNoticeText.storeExpiry else MessageNoticeText.expiry

/** [이전 대화 더 보기]. 함수가 없거나 · 받는 중이거나 · 서버가 "더 없다"고 했으면 아무것도 안 한다. */
fun MessagesStore.loadOlderMessages(peerID: String) {
    if (!canLoadOlderMessages(peerID)) return
    scope.launch { performLoadOlderMessages(peerID) }
}

private fun MessagesStore.canLoadOlderMessages(peerID: String): Boolean {
    if (!isSignedIn || peerID.isEmpty()) return false
    return !olderLoading && olderAvailable != false && olderHasMore[peerID] != false
}

/** 누름 한 번. 옛 줄 하나라도 붙거나, 서버가 끝이라고 하거나, 이어 묻기 상한에 닿을 때까지 쪽을 받는다(맥 · 아이폰과 같은 고리). */
suspend fun MessagesStore.performLoadOlderMessages(peer: String) {
    if (!canLoadOlderMessages(peer)) return
    val me = context.sessionStore.userID ?: return
    val generation = context.generation
    val token = olderRequestToken
    val name = peerName(peer)
    val avatar = peerAvatarURL(peer)?.let(SwiftURL::parse)
    val service = context.service
    olderLoading = true
    if (olderFailed) olderFailed = false
    fun isCurrent(): Boolean = generation == context.generation && token == olderRequestToken
    try {
        repeat(MessageNoticeText.olderCatchUpRequests) {
            val cursor = olderCursors[peer]
            val page = context.withSessionRetry { s ->
                service.fetchMessagePage(s.accessToken, peer, me, cursor, MessageNoticeText.olderPageLimit, name, avatar)
            }
            if (!isCurrent()) return
            if (olderAvailable != true) olderAvailable = true
            // 붙인 뒤 위에 맞출 줄 — 붙이기 **직전** 화면 맨 위의 메시지.
            val anchorID = conversationMessages(peer).firstOrNull()?.id
            val older = olderPages[peer] ?: emptyList()
            val head: List<MessageHistoryEntry> = history.filter { it.peerUserID == peer }.map { it.wire }
            val next = MessageOlderHistoryRules.prepending(page.entries, older, head)
            val added = next.size - older.size
            if (added > 0) olderPages = olderPages + (peer to next)
            // 커서는 뒤로만 간다 — 서버가 커서를 무시해 같은 쪽을 다시 줘도 끝없이 묻지 않는다.
            var advanced = false
            val oldest = page.oldestCursor
            if (oldest != null && (cursor == null || oldest.isOlder(cursor))) {
                olderCursors = olderCursors + (peer to oldest)
                advanced = true
            }
            val more = page.hasMore && advanced
            olderHasMore = olderHasMore + (peer to more)
            if (added > 0) {
                if (anchorID != null) olderScrollAnchor = MessagesOlderScrollAnchor((olderScrollAnchor?.serial ?: 0) + 1, anchorID)
                return
            }
            if (!more) return
        }
    } catch (error: Throwable) {
        if (!isCurrent()) return
        if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return
        if (error is SupabaseWorkServiceError && MessagesStore.isMissingFunction(error)) {
            // 함수가 없는 서버 — 줄을 내린다(다음 대화 열기에서 다시 세운다). 실패([다시 시도])로 그리지 않는다.
            olderAvailable = false
        } else {
            olderFailed = true
        }
    } finally {
        if (isCurrent() && olderLoading) olderLoading = false
    }
}

/** 지난 쪽을 비운다(대화 닫기 · 상대 바꾸기 · 로그아웃). 날아가던 응답은 순번으로 버린다. 쓸 수 있는가는 건드리지 않는다. */
fun MessagesStore.clearOlderMessages() {
    olderRequestToken += 1
    if (olderPages.isNotEmpty()) olderPages = emptyMap()
    if (olderCursors.isNotEmpty()) olderCursors = emptyMap()
    if (olderHasMore.isNotEmpty()) olderHasMore = emptyMap()
    if (olderLoading) olderLoading = false
    if (olderFailed) olderFailed = false
    if (olderScrollAnchor != null) olderScrollAnchor = null
}

/** 대화를 열 때 숨김(함수 없음)을 모름으로 되돌린다. 서버는 안 부른다. */
fun MessagesStore.rearmOlderMessagesAvailability() {
    if (olderAvailable == false) olderAvailable = null
}

/** 24시간 머리가 미끄러졌다(이력을 새로 세우기 직전). 쪽을 한 번이라도 받은 상대만 빠진 옛 줄을 지난 쪽 끝으로 옮긴다(코어 규칙 한 곳). */
internal fun MessagesStore.carryOlderMessagesAcrossHeadSlide(previousHead: List<MessageHistoryEntry>, nextHead: List<MessageHistoryEntry>) {
    val paged = olderPages.keys + olderCursors.keys
    if (paged.isEmpty()) return
    val now = context.clock.now()
    var pages = olderPages
    for (peer in paged) {
        val older = pages[peer] ?: emptyList()
        val carried = MessageOlderHistoryRules.carriedAcrossHeadSlide(peer, previousHead, nextHead, older, now)
        if (carried != older) pages = pages + (peer to carried)
    }
    if (pages != olderPages) olderPages = pages
}
