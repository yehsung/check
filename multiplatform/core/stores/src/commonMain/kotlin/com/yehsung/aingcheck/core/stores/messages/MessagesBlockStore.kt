// 원본: Sources/CheckMobileKit/Messages/MessagesBlockStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.blockUser
import com.yehsung.aingcheck.core.net.fetchBlocks
import com.yehsung.aingcheck.core.net.reportContent
import com.yehsung.aingcheck.core.net.unblockUser
import com.yehsung.aingcheck.core.rules.text.BlockReportAction
import com.yehsung.aingcheck.core.rules.text.BlockReportFailure
import com.yehsung.aingcheck.core.rules.text.BlockReportRules
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.rules.text.ContentReportDetail
import com.yehsung.aingcheck.core.rules.text.ServiceErrorFacts
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.models.ContentReportReason
import kotlinx.coroutines.launch

/*
 * 차단·신고 동작(SPEC-block-report 작업 P). 상태는 [MessagesStore] 본체에, 문구·규칙은 코어 `BlockReportRules`(맥과 한 벌)에 있다.
 *
 * ── 이 확장이 지키는 것 ──
 * ① **차단 직후 화면은 서버를 기다리지 않는다.** 확인 시트를 지나면 그 상대를 곧바로 숨기고 대화·목록·배지·사람 찾기에서 사라진다.
 *    실패하면 숨김을 되돌리고 목록 위에 이유 한 줄을 세운다 — **대화는 그대로 돌아온다.**
 * ② **확인 없이는 차단하지 않는다.** [blockPeer] 를 부르는 곳은 확인 시트 하나다(화면 갈래 W3-a 가 지킨다).
 * ③ **서버가 아직 없는 창**에서는 "고장"이 아니라 "아직"이라고 말한다(`BlockReportText.serverNotReady`).
 * ④ 세대 가드: 로그아웃 뒤 도착한 응답은 다음 계정의 숨김·목록·문구를 건드리지 않는다.
 */
// INV-MessagesBlockStore-ca3a6fda 이식: 신고 본문은 사람이 쓴 문장이다 — 이 파일(과 모듈)에 로그(print · Logger)를 두지 않는다.

/** Swift `BlockReportRules.classify(Error)` 의 앞단 — 전선 오류를 규칙이 읽는 사실로(rules 는 net 을 볼 수 없다). */
fun serviceErrorFacts(error: Throwable): ServiceErrorFacts {
    if (AuthErrorRules.classify(error) == AuthErrorDisposition.cancelled) return ServiceErrorFacts.cancelled
    val serviceError = error as? SupabaseWorkServiceError ?: return ServiceErrorFacts.notServiceError
    return when (serviceError) {
        SupabaseWorkServiceError.DatabaseSchemaMissing -> ServiceErrorFacts.databaseSchemaMissing
        is SupabaseWorkServiceError.InvalidResponse -> ServiceErrorFacts.invalidResponse(serviceError.statusCode)
        is SupabaseWorkServiceError.RateLimited -> ServiceErrorFacts.rateLimited
        else -> ServiceErrorFacts.otherServiceError
    }
}

internal fun blockFailure(error: Throwable): BlockReportFailure = BlockReportRules.classify(serviceErrorFacts(error))

/** 한 사람을 차단한다(확인 시트가 부르는 유일한 문). 낙관적으로 숨기고 왕복을 띄운다 — 화면은 성공을 기다리지 않는다. */
fun MessagesStore.blockPeer(peerID: String) {
    if (!isSignedIn || peerID.isEmpty() || peerID == context.sessionStore.userID) return
    if (blockingPeerID != null) return
    val generation = context.generation
    blockNotice = null
    blockNoticeIsError = false
    blockingPeerID = peerID
    // 숨기는 즉시 묶음·배지·점·사람 찾기에서 사라진다(`visibleHistory` 한 곳이 거른다). 읽음 표시도 더 올라가지 않는다.
    hiddenBlockedPeerIDs = hiddenBlockedPeerIDs + peerID
    val service = context.service
    scope.launch {
        try {
            context.withSessionRetry { session -> service.blockUser(session.accessToken, peerID) }
            if (generation != context.generation) return@launch
            blockingPeerID = null
            // 차단 목록 화면은 다음에 설 때 서버에서 다시 받는다(지어내 넣지 않는다 — 별명·시각을 모른다).
            blocksLoaded = false
        } catch (error: Throwable) {
            if (generation != context.generation) return@launch
            blockingPeerID = null
            val failure = blockFailure(error)
            // 되돌리기: 숨긴 대화가 그대로 돌아온다.
            hiddenBlockedPeerIDs = hiddenBlockedPeerIDs - peerID
            BlockReportRules.notice(failure, BlockReportAction.block)?.let {
                blockNotice = it
                blockNoticeIsError = true
            }
        }
    }
}

/** 차단 목록의 [차단 해제]. 성공하면 목록에서 그 줄을 빼고 숨김도 푼다. */
fun MessagesStore.unblock(userID: String) {
    if (!isSignedIn || userID.isEmpty() || userID in unblockingUserIDs) return
    val generation = context.generation
    blockedListNotice = null
    unblockingUserIDs = unblockingUserIDs + userID
    val service = context.service
    scope.launch {
        try {
            context.withSessionRetry { session -> service.unblockUser(session.accessToken, userID) }
            if (generation != context.generation) return@launch
            unblockingUserIDs = unblockingUserIDs - userID
            blockedPeople = blockedPeople.filter { it.userID != userID }
            // 숨김을 푼다 — 서버가 다시 내려 주는 이력에 그 사람의 대화가 있으면 목록에 돌아온다.
            hiddenBlockedPeerIDs = hiddenBlockedPeerIDs - userID
            requestActivityRefresh(includeHistory = true)
            loadDirectory(force = true)
        } catch (error: Throwable) {
            if (generation != context.generation) return@launch
            unblockingUserIDs = unblockingUserIDs - userID
            BlockReportRules.notice(blockFailure(error), BlockReportAction.unblock)?.let { blockedListNotice = it }
        }
    }
}

/** 차단 목록 조회(`list_blocks`). 서버가 함수를 모르면 **빈 목록 + "아직 준비되지 않았어요"** 다. */
fun MessagesStore.loadBlocks(force: Boolean = false) {
    if (!isSignedIn || blocksLoading) return
    if (!force && blocksLoaded) return
    val generation = context.generation
    blocksLoading = true
    blocksFailed = false
    val service = context.service
    scope.launch {
        try {
            val rows = context.withSessionRetry { session -> service.fetchBlocks(session.accessToken) }
            if (generation != context.generation) return@launch
            blocksLoading = false
            blockedPeople = rows
            blocksLoaded = true
            blocksFailed = false
            blocksServerNotReady = false
        } catch (error: Throwable) {
            if (generation != context.generation) return@launch
            blocksLoading = false
            when (blockFailure(error)) {
                BlockReportFailure.cancelled -> return@launch
                BlockReportFailure.serverNotReady -> {
                    blockedPeople = emptyList()
                    blocksLoaded = true
                    blocksServerNotReady = true
                }
                BlockReportFailure.network, BlockReportFailure.rejected -> blocksFailed = true
            }
        }
    }
}

/** 차단 목록 화면이 섰다(스로틀 없음). */
fun MessagesStore.blockedListDidAppear() {
    blockedListNotice = null
    loadBlocks(force = true)
}

/**
 * 신고 한 건(+ `alsoBlock` 이면 서버가 같은 트랜잭션에서 차단까지). 보냈으면 true — 화면은 그때만 시트를 닫는다.
 * 실패하면 시트를 **열어 둔 채** 이유 한 줄을 세운다(사용자가 쓴 글이 사라지지 않게).
 */
suspend fun MessagesStore.submitReport(
    peerID: String,
    reason: ContentReportReason?,
    detail: String,
    messageID: String?,
    alsoBlock: Boolean,
): Boolean {
    if (!isSignedIn || peerID.isEmpty() || isSendingReport) return false
    if (reason == null) {
        reportNotice = BlockReportText.reportReasonRequired
        return false
    }
    if (!ContentReportDetail.isWithinLimit(detail)) {
        reportNotice = BlockReportText.reportDetailOverflow(ContentReportDetail.maxLength)
        return false
    }
    val generation = context.generation
    isSendingReport = true
    reportNotice = null
    val service = context.service
    return try {
        context.withSessionRetry { session ->
            service.reportContent(session.accessToken, peerID, reason, ContentReportDetail.payload(detail), messageID, alsoBlock)
        }
        if (generation != context.generation) return false
        isSendingReport = false
        if (alsoBlock) {
            // 서버가 이미 차단했다 — 화면도 같은 순간에 걷어낸다(되돌릴 실패가 없다).
            hiddenBlockedPeerIDs = hiddenBlockedPeerIDs + peerID
            blocksLoaded = false
        }
        blockNotice = BlockReportText.reportSentNotice
        blockNoticeIsError = false
        true
    } catch (error: Throwable) {
        if (generation != context.generation) return false
        isSendingReport = false
        BlockReportRules.notice(blockFailure(error), BlockReportAction.report)?.let { reportNotice = it }
        false
    }
}

/** 신고 시트가 닫혔다 — 실패 문구를 비운다. */
fun MessagesStore.reportSheetDidDisappear() {
    reportNotice = null
}
