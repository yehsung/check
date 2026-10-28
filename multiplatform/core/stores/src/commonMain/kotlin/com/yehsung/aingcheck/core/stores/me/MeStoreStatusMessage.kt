// 원본: Sources/CheckMobileKit/Me/MeStoreStatusMessage.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.StatusMessageSaveResult
import com.yehsung.aingcheck.core.net.fetchMyStatusMessage
import com.yehsung.aingcheck.core.net.setStatusMessage
import com.yehsung.aingcheck.core.rules.text.StatusMessage
import com.yehsung.aingcheck.core.rules.text.StatusMessageSaveOutcome
import com.yehsung.aingcheck.core.rules.text.StatusMessageText
import com.yehsung.aingcheck.core.rules.text.StatusMessageValidation

// 상태메시지(v0.3.51 · 폰 나 > 프로필). 사장님 결정: 40자(코드포인트) · 한 줄 · 만료 없음 · 비우면 지움 · 쿨타임 없음. 맥과 같은 규칙(rules text 한 벌):
//  ① 쓰기는 `set_status_message` 하나 · 내 값 읽기는 **따로 GET**(머리 GET 에 끼우면 칸이 없는 옛 서버에서 머리 전체가 죽는다).
//  ② 연타 가드 + 세대 가드 + **쓰기 표**(statusMessageWriteKey): 저장 성공 뒤 도착한 옛 GET 은 방금 쓴 값을 되돌리지 않는다.
//  ③ 상태는 사람이 쓴 문장이다 — 로그로 흘리지 마라.

val MeStore.Companion.statusMessageMaxLength: Int get() = StatusMessage.maxLength

/** 입력칸 카운터(서버와 같은 눈금 — 정규화 후 코드포인트). */
val MeStore.statusMessageDraftLength: Int get() = StatusMessage.length(statusMessageDraft)

/** [저장]을 살릴 조건: 왕복 중이 아니고 · 길이 안이고 · 지금 서버값과 다르다(비운 입력은 '지우기'라 값이 있을 때만 다르다). */
val MeStore.canSaveStatusMessage: Boolean
    get() {
        if (isUpdatingStatusMessage || statusMessageDraftLength > MeStore.statusMessageMaxLength) return false
        return MeStatusMessage.value(statusMessageDraft) != statusMessage
    }

/** [지우기]를 보일 조건: 저장된 상태가 있다. */
val MeStore.canClearStatusMessage: Boolean get() = statusMessage != null && !isUpdatingStatusMessage

internal object MeStatusMessage {
    /** 입력 → 보낼 값(null = 지우기). 보이는 글자가 없으면 지우기로 읽는다. */
    fun value(raw: String): String? = (StatusMessage.validate(raw) as? StatusMessageValidation.ok)?.value

    fun outcome(result: StatusMessageSaveResult): StatusMessageSaveOutcome = when (result) {
        is StatusMessageSaveResult.Response ->
            StatusMessageSaveOutcome.from(result.response.status, result.response.statusMessage, result.response.maxLength)
        StatusMessageSaveResult.ServerNotReady -> StatusMessageSaveOutcome.serverNotReady
    }
}

/** 내 상태메시지 GET. 실패(칸 없는 옛 서버 포함)는 조용히 — 지난 값을 둔다. */
suspend fun MeStore.loadStatusMessage() {
    if (!context.sessionStore.isSignedIn) return
    val serial = nextSerial("statusMessage")
    val generation = context.generation
    val stamp = writeStamp(MeStore.STATUS_MESSAGE_WRITE_KEY)
    val service = context.service
    val value = attempt { s -> service.fetchMyStatusMessage(s.accessToken, s.userID) }.getOrElse { return }
    // 이 GET 이 떠 있는 사이 저장이 성공했거나 지금 저장 중이면 이 응답은 옛 값이다 — 버린다.
    if (generation != context.generation || !isCurrent("statusMessage", serial) || isUpdatingStatusMessage ||
        writeStamp(MeStore.STATUS_MESSAGE_WRITE_KEY) != stamp
    ) return
    val previous = statusMessage
    statusMessage = value
    statusMessageLoaded = true
    // 편집 화면이 떠 있고 사용자가 아직 손대지 않았으면(비었거나 옛 값 그대로) 입력을 새 값으로 맞춘다.
    if (isProfileVisible && (statusMessageDraft.isEmpty() || statusMessageDraft == (previous ?: ""))) {
        statusMessageDraft = value ?: ""
    }
}

/** 저장(입력이 비면 지우기). 성공이면 true. */
suspend fun MeStore.saveStatusMessage(): Boolean {
    if (!context.sessionStore.isSignedIn || isUpdatingStatusMessage) return false
    val text: String? = when (val v = StatusMessage.validate(statusMessageDraft)) {
        is StatusMessageValidation.ok -> v.value
        StatusMessageValidation.empty -> null
        is StatusMessageValidation.tooLong -> {
            statusMessageNotice = StatusMessageText.tooLong(v.maxLength)
            isStatusMessageNoticeError = true
            return false
        }
    }
    isUpdatingStatusMessage = true
    val generation = context.generation
    try {
        val service = context.service
        val result = try {
            context.withSessionRetry { s -> service.setStatusMessage(s.accessToken, text) }
        } catch (e: Throwable) {
            if (generation != context.generation) return false
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return false
            statusMessageNotice = StatusMessageText.network
            isStatusMessageNoticeError = true
            return false
        }
        if (generation != context.generation) return false
        val outcome = MeStatusMessage.outcome(result)
        val notice = StatusMessageText.notice(outcome)
        statusMessageNotice = notice.first
        isStatusMessageNoticeError = notice.second
        return when (outcome) {
            is StatusMessageSaveOutcome.saved -> {
                noteLocalWrite(MeStore.STATUS_MESSAGE_WRITE_KEY)
                statusMessage = outcome.value
                statusMessageLoaded = true
                statusMessageDraft = outcome.value
                true
            }
            StatusMessageSaveOutcome.cleared -> {
                noteLocalWrite(MeStore.STATUS_MESSAGE_WRITE_KEY)
                statusMessage = null
                statusMessageLoaded = true
                statusMessageDraft = ""
                true
            }
            is StatusMessageSaveOutcome.tooLong, StatusMessageSaveOutcome.notText,
            StatusMessageSaveOutcome.serverNotReady, StatusMessageSaveOutcome.invalid -> false
        }
    } finally {
        if (generation == context.generation) isUpdatingStatusMessage = false
    }
}

/** [지우기]: 입력을 비우고 곧바로 지운다. */
suspend fun MeStore.clearStatusMessage(): Boolean {
    if (isUpdatingStatusMessage) return false
    statusMessageDraft = ""
    return saveStatusMessage()
}
