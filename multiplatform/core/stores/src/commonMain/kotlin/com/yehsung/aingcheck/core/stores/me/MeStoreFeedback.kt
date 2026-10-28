// 원본: Sources/CheckMobileKit/Me/MeStoreFeedback.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.foundation.platform.GraphemeCounter
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchFeedbackList
import com.yehsung.aingcheck.core.net.fetchFeedbackReplyLatest
import com.yehsung.aingcheck.core.net.submitFeedback
import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.FeedbackComposer
import com.yehsung.aingcheck.core.wire.models.FeedbackReport
import com.yehsung.aingcheck.core.wire.models.FeedbackText

// 제보: 쓰기(`submit_feedback` — 앱 버전 "Android 0.1.0 (1)" · OS 버전, **진단 줄 없음**) · 내 제보 목록과 답장(`feedback_list`) · 답장 배지
// (`feedback_reply_latest` vs 이 계정이 본 시각). 문구는 와이어 `FeedbackText` 그대로(맥과 같은 문장). 초안은 전송 **성공**에서만 비운다.
// INV-MeStoreFeedback-48426bc1 이식: 제보 본문은 사용자가 쓴 글이다 — 로그·print 금지(이 파일엔 로그 호출이 없다).

/** 글자 수 = 플랫폼 그래핌(Swift `String.count`) — rules 의 그래핌 경계(ART=ICU · 데스크톱=JDK, §8-16 ③)를 쓴다. */
internal object MeGraphemes : GraphemeCounter {
    override fun count(text: String): Int = Graphemes.count(text)
}

val MeStore.canSendFeedback: Boolean
    get() = !isSendingFeedback && context.sessionStore.isSignedIn && FeedbackComposer.isSendable(feedbackDraft, MeGraphemes)

val MeStore.feedbackAutoAttachNotice: String
    get() = MeText.feedbackAutoAttach(context.appInfo.feedbackAppVersion, context.appInfo.osVersion)

suspend fun MeStore.sendFeedback() {
    if (!context.sessionStore.isSignedIn || isSendingFeedback) return
    val body = FeedbackComposer.normalized(feedbackDraft)
    if (!FeedbackComposer.isSendable(body, MeGraphemes)) return
    val kind = feedbackKind
    val appVersion = context.appInfo.feedbackAppVersion
    val osVersion = context.appInfo.osVersion
    val generation = context.generation
    isSendingFeedback = true
    feedbackNotice = null
    try {
        val service = context.service
        try {
            context.withSessionRetry { s -> service.submitFeedback(s.accessToken, kind, body, appVersion, osVersion) }
        } catch (e: Throwable) {
            if (generation != context.generation) return
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            feedbackNotice = MeText.feedbackFailure(e, FeedbackText.sendFailed, FeedbackText.sendSchemaMissing)
            return
        }
        if (generation != context.generation) return
        feedbackDraft = ""
        feedbackNotice = FeedbackText.sendSuccess
        loadFeedback()
    } finally {
        if (generation == context.generation) isSendingFeedback = false
    }
}

/** 내 제보 목록. 관리자 계정은 서버가 전부를 주므로 **내 것만** 거른다(이 화면은 "내가 보낸 제보"다). */
suspend fun MeStore.loadFeedback() {
    if (!context.sessionStore.isSignedIn) return
    val me = context.sessionStore.userID ?: return
    val serial = nextSerial("feedback")
    val generation = context.generation
    feedbackState.isLoading = true
    feedbackState.hasFailed = false
    try {
        val service = context.service
        val reports = try {
            context.withSessionRetry { s -> service.fetchFeedbackList(s.accessToken, null, MeStore.FEEDBACK_LIST_LIMIT) }
        } catch (e: Throwable) {
            if (generation != context.generation || !isCurrent("feedback", serial)) return
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) {
                // 표가 아직 없다 — 실패가 아니라 "아직 없음".
                feedbackState.hasLoaded = true
                feedbackState.loadedAt = context.clock.now()
            } else {
                feedbackState.hasFailed = true
            }
            return
        }
        if (generation != context.generation || !isCurrent("feedback", serial)) return
        val mine = MeText.sortedFeedback(reports.filter { it.userID == me })
        if (feedbackList != mine) feedbackList = mine
        feedbackState.hasLoaded = true
        feedbackState.loadedAt = context.clock.now()
        val latest = mine.mapNotNull { it.adminNoteAt }.maxOrNull()
        val held = feedbackReplyLatestAt
        if (latest != null && (held == null || latest > held)) feedbackReplyLatestAt = latest
        if (isFeedbackVisible) markFeedbackRepliesSeen()
    } finally {
        if (isCurrent("feedback", serial)) feedbackState.isLoading = false
    }
}

/** 내 제보에 달린 가장 최근 답장 시각. 실패는 조용히(서 있던 배지는 내리지 않는다 — 못 물어봤다는 것이 "답장 없음"은 아니다). */
suspend fun MeStore.loadFeedbackReplyLatest() {
    if (!context.sessionStore.isSignedIn) return
    val serial = nextSerial("replyLatest")
    val generation = context.generation
    val service = context.service
    val latest = attempt { s -> service.fetchFeedbackReplyLatest(s.accessToken) }.getOrElse { return }
    if (generation != context.generation || !isCurrent("replyLatest", serial)) return
    feedbackReplyLatestAt = latest
    loadFeedbackReplySeenStamp()
    if (isFeedbackVisible) markFeedbackRepliesSeen()
}

/** 안 본 답장이 있는가: 서버의 마지막 답장 시각 > 이 계정이 본 시각. */
val MeStore.hasUnseenFeedbackReply: Boolean
    get() {
        val latest = feedbackReplyLatestAt ?: return false
        val seen = feedbackReplySeenAt ?: return true
        return latest > seen
    }

/** 이 답장이 새 것인가(행의 "새 답장" 점). 새 설치면 가장 최근 답장만 새 것으로 친다. */
fun MeStore.isUnseenReply(report: FeedbackReport): Boolean {
    if (report.reply == null) return false
    val at = report.adminNoteAt ?: return false
    val seen = feedbackReplySeenAt ?: return at >= (feedbackReplyLatestAt ?: at)
    return at > seen
}

/** 제보 답장 푸시가 왔다(푸시 코디네이터 — W2-f). 답장 시각을 다시 읽고, 목록을 이미 읽었거나 보고 있으면 목록도 다시 읽는다. */
fun MeStore.didReceiveFeedbackReplyPush(@Suppress("UNUSED_PARAMETER") reportID: String?) {
    if (!context.sessionStore.isSignedIn) return
    launch { loadFeedbackReplyLatest() }
    if (isFeedbackVisible || feedbackState.hasLoaded) launch { loadFeedback() }
}

fun MeStore.feedbackDidAppear() {
    isFeedbackVisible = true
    if (!context.sessionStore.isSignedIn) return
    launch { loadFeedback() }
    launch { loadFeedbackReplyLatest() }
}

fun MeStore.feedbackDidDisappear() {
    isFeedbackVisible = false
    focusedReportID = null
    if (feedbackNotice == FeedbackText.sendSuccess) feedbackNotice = null
    // 떠나는 순간 본 것으로 적는다(행의 "새 답장" 점은 화면에 머무는 동안 남아 있어야 읽고 나서 사라진다).
    markFeedbackRepliesSeen(updatesDisplayedStamp = true)
}

/** 본 것으로 적는다. **적는 값은 서버가 준 마지막 답장 시각**이다(기기 시계를 적으면 시계가 앞선 만큼 새 답장을 못 본다). */
internal fun MeStore.markFeedbackRepliesSeen(updatesDisplayedStamp: Boolean = false) {
    val latest = feedbackReplyLatestAt ?: return
    val key = feedbackReplySeenKey ?: return
    val stored = context.keyValueStore.getString(key)?.toDoubleOrNull()
    if (stored == null || latest.timeIntervalSince1970 > stored) {
        context.keyValueStore.putString(key, latest.timeIntervalSince1970.toString())
    }
    if (updatesDisplayedStamp) feedbackReplySeenAt = latest
}

internal fun MeStore.loadFeedbackReplySeenStamp() {
    val key = feedbackReplySeenKey ?: return
    if (isFeedbackVisible) return
    feedbackReplySeenAt = context.keyValueStore.getString(key)?.toDoubleOrNull()?.let { SwiftDate(it) }
}

/** 계정별 키(같은 폰에서 계정을 바꿔도 앞 계정의 '봤음'을 물려받지 않게). */
internal val MeStore.feedbackReplySeenKey: String? get() = context.sessionStore.userID?.let { "aing.me.feedbackReplySeenAt.$it" }

/** 목록이 가리킬 제보(딥링크) — 목록에 없으면 null. */
val MeStore.focusedReport: FeedbackReport? get() = focusedReportID?.let { id -> feedbackList.firstOrNull { it.id == id } }
