// 원본: Sources/CheckMobileKit/Me/MeStoreFeedbackShots.swift @ 6a6141ce (폰 1.0.19 — 제보 화면 캡처 · 맥 0.3.86 WorkTimerStoreFeedbackShot 의 폰 짝)
//
// 판 9(대표 #d_xygj8oZRFlfH 4번 메시지 묶음). 서버 어휘는 전부 와이어 FeedbackShotWire(계약 v2 §3). 맥 · 아이폰과 같은 다섯 가지:
//  ① **글이 먼저 간다.** submit_feedback 이 돌려준 제보 id 폴더에 캡처를 하나씩 올리고 붙인다. 캡처가 실패해도 제보는 보낸 것이다.
//  ② 새 자동 호출은 하나뿐: feedback_list 가 비어 있지 않을 때 feedback_shots 한 번(칩 "캡처 N장").
//  ③ 404 · PGRST202 는 입구를 숨기되 영구히 기억하지 않는다(제보 화면을 다시 열면 다시 묻는다). 문 닫힘은 붙이기 줄만 숨긴다.
//  ④ 캡처를 얻는 길은 사진 고르기뿐이다(시스템 사진 고르기 — 권한을 묻지 않는다 · 이 앱은 화면을 찍지 않는다).
//  ⑤ 캡처에는 남의 이름 · 대화가 찍혀 있을 수 있다 — 로그 금지 · 디스크에 쓰지 않는다.
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.PrivateStorageError
import com.yehsung.aingcheck.core.net.attachFeedbackShot
import com.yehsung.aingcheck.core.net.fetchFeedbackShots
import com.yehsung.aingcheck.core.net.uploadFeedbackShot
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.models.FeedbackAttachOutcome
import com.yehsung.aingcheck.core.wire.models.FeedbackReport
import com.yehsung.aingcheck.core.wire.models.FeedbackShotRules
import com.yehsung.aingcheck.core.wire.models.FeedbackShotText
import com.yehsung.aingcheck.core.wire.models.FeedbackShotWire
import com.yehsung.aingcheck.core.wire.models.FeedbackText
import kotlinx.coroutines.withContext
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** 붙여 둔 캡처 한 장(보내기 전). 미리 보기는 화면이 [jpeg] 를 그린다. */
class MeFeedbackShotDraft(val id: String, val jpeg: ByteArray, pixelWidth: Int, pixelHeight: Int) {
    val pixelWidth: Int = maxOf(1, pixelWidth)
    val pixelHeight: Int = maxOf(1, pixelHeight)
    override fun equals(other: Any?): Boolean = other is MeFeedbackShotDraft && other.id == id
    override fun hashCode(): Int = id.hashCode()
}

/** 보낸 뒤 캡처 한 장의 결과(올리기 + 붙이기) — 맥 `FeedbackShotStep` 과 같은 갈래. */
sealed interface MeFeedbackShotStep {
    data object attached : MeFeedbackShotStep
    /** 일시 실패 — 다음 캡처는 계속한다. */
    data object failed : MeFeedbackShotStep
    /** 저장소가 정책으로 거절했고 서버도 문 닫힘을 말하지 않았다 — 멈춘다. */
    data object refused : MeFeedbackShotStep
    /** 서버 문이 닫혔다(door_open 거짓). */
    data object doorClosed : MeFeedbackShotStep
    /** 문은 열렸는데 이 앱 판을 받지 않았다(door_open 참). */
    data object outdated : MeFeedbackShotStep
    data class tooMany(val max: Int) : MeFeedbackShotStep
    /** 서버에 함수 · 버킷이 없다. */
    data object missing : MeFeedbackShotStep

    val stops: Boolean get() = this !is attached && this !is failed
    val closesTheDoor: Boolean get() = this == doorClosed || this == outdated
}

/** 보낸 뒤 캡처들의 결과를 세어 안내 한 줄을 고른다(순수 — 맥 `FeedbackShotTally` 와 같은 글). */
class MeFeedbackShotTally(val total: Int) {
    var attached = 0
        private set
    var stop: MeFeedbackShotStep? = null
        private set

    fun record(step: MeFeedbackShotStep) {
        if (step == MeFeedbackShotStep.attached) attached += 1
        if (step.stops && stop == null) stop = step
    }

    val failed: Int get() = maxOf(0, total - attached)

    val notice: String
        get() {
            when (val s = stop) {
                MeFeedbackShotStep.doorClosed, MeFeedbackShotStep.missing -> return FeedbackShotText.sentShotsDoorClosed
                MeFeedbackShotStep.outdated -> return FeedbackShotText.sentShotsAppOutdated
                is MeFeedbackShotStep.tooMany -> return FeedbackShotText.sentShotsTooMany(s.max)
                else -> Unit
            }
            if (failed == 0) return FeedbackText.sendSuccess
            if (attached == 0) return FeedbackShotText.sentShotsFailed
            return FeedbackShotText.sentSomeShotsFailed(failed)
        }
}

// ---------------------------------------------------------------- 파생값

/** 캡처 입구(붙이기 줄 · 칩)를 보이는가 — 이 빌드가 사진을 줄일 수 있고 서버에 기능이 있는가(③). */
val MeStore.feedbackShotsShown: Boolean get() = photoEncoder != null && !feedbackShotServerMissing

/** 붙이기 줄을 보이는가(붙이기 줄 · 전송 · 경고 한 줄이 같은 값을 읽는다). */
val MeStore.feedbackShotAttachShown: Boolean get() = feedbackShotsShown && !feedbackShotDoorClosed

/** 지금 캡처를 붙이거나 뺄 수 있는가. */
val MeStore.canEditFeedbackShots: Boolean get() = feedbackShotAttachShown && !isSendingFeedback && !feedbackShotPreparing

/** 더 붙일 수 있는 장수. */
val MeStore.feedbackShotRoom: Int get() = maxOf(0, FeedbackShotRules.maxDraft - feedbackShots.size)

/** 이번 전송에 실을 캡처(붙이기 줄이 숨었으면 없다). */
val MeStore.feedbackShotsForSend: List<MeFeedbackShotDraft> get() = if (feedbackShotAttachShown) feedbackShots else emptyList()

/** 내 제보 하나에 붙은 캡처 수(칩). 입구가 숨었으면 0. */
fun MeStore.feedbackShotCount(reportID: String): Int = if (!feedbackShotsShown) 0 else feedbackShotsByReport[reportID.lowercase()]?.size ?: 0

// ---------------------------------------------------------------- 입구

/** 제보 화면을 열 때 — 앞서 숨긴 입구를 다시 연다(③). */
fun MeStore.rearmFeedbackShots() {
    if (feedbackShotServerMissing) feedbackShotServerMissing = false
    if (feedbackShotDoorClosed) feedbackShotDoorClosed = false
}

private fun MeStore.markFeedbackShotsMissing() {
    feedbackShotServerMissing = true
    if (feedbackShotsByReport.isNotEmpty()) feedbackShotsByReport = emptyMap()
}

// ---------------------------------------------------------------- 붙이기 · 빼기

/** 사진 고르기로 받은 원본들을 붙인다(남은 자리만큼 · 줄이기는 메인 밖). 자리보다 많으면 앞에서부터 자리만큼 붙이고 "3장까지"를 말한다. */
@OptIn(ExperimentalUuidApi::class)
fun MeStore.attachFeedbackShots(datas: List<ByteArray>) {
    if (!canEditFeedbackShots) return
    val encoder = photoEncoder ?: return
    // 골랐는데 하나도 못 읽었다 — 조용히 끝내지 않고 말한다.
    if (datas.isEmpty()) {
        feedbackNotice = FeedbackShotText.unreadable
        return
    }
    if (feedbackShotRoom <= 0) {
        feedbackNotice = FeedbackShotText.full
        return
    }
    val room = feedbackShotRoom
    val taken = datas.take(room)
    val overflowed = datas.size > room
    feedbackShotPrepareSerial += 1
    val serial = feedbackShotPrepareSerial
    val generation = context.generation
    feedbackShotPreparing = true
    launch {
        val drafts = ArrayList<MeFeedbackShotDraft>()
        var unreadable = false
        for (data in taken) {
            val encoded = withContext(computeContext) { runCatching { encoder.encode(data) }.getOrNull() }
            if (encoded != null) drafts += MeFeedbackShotDraft(Uuid.random().toString().lowercase(), encoded.jpeg, encoded.pixelWidth, encoded.pixelHeight)
            else unreadable = true
        }
        if (generation != context.generation || serial != feedbackShotPrepareSerial) return@launch
        feedbackShotPreparing = false
        val space = maxOf(0, FeedbackShotRules.maxDraft - feedbackShots.size)
        feedbackShots = feedbackShots + drafts.take(space)
        val current = feedbackNotice
        feedbackNotice = when {
            overflowed || drafts.size > space -> FeedbackShotText.full
            unreadable -> FeedbackShotText.unreadable
            current != null && current in setOf(FeedbackShotText.unreadable, FeedbackShotText.tooLarge, FeedbackShotText.full) -> null
            else -> current
        }
    }
}

/** [빼기] 한 장. */
fun MeStore.removeFeedbackShot(id: String) {
    if (isSendingFeedback) return
    feedbackShots = feedbackShots.filter { it.id != id }
}

/** 글만 나간 제보 뒤 — 실리지 않은 캡처를 내린다(다음 제보에 따라 나가지 않게 — 남의 대화가 찍혔을 수 있는 그림이다). */
internal fun MeStore.discardUnsentFeedbackShots() {
    if (feedbackShots.isNotEmpty()) feedbackShots = emptyList()
}

// ---------------------------------------------------------------- 보낸 뒤(글은 이미 갔다)

/** 캡처를 화면에서 내리고 하나씩 올리고 붙인 뒤 안내 한 줄을 정한다. 제보 id 를 못 읽었으면 캡처만 못 붙인 것으로 말한다. */
internal suspend fun MeStore.finishFeedbackShotsAfterSubmit(shots: List<MeFeedbackShotDraft>, returnedID: String?, generation: Int) {
    val sentIDs = shots.map { it.id }.toSet()
    feedbackShots = feedbackShots.filter { it.id !in sentIDs }
    val reportID = FeedbackShotWire.reportID(returnedID)
    val userID = context.sessionStore.userID
    if (reportID == null || userID == null) {
        feedbackNotice = FeedbackShotText.sentShotsFailed
        return
    }
    feedbackNotice = FeedbackShotText.uploading
    val tally = MeFeedbackShotTally(shots.size)
    for (shot in shots) {
        val step = uploadAndAttachFeedbackShot(shot, userID, reportID)
        if (generation != context.generation) return
        tally.record(step)
        if (step == MeFeedbackShotStep.missing) markFeedbackShotsMissing()
        if (step.closesTheDoor) feedbackShotDoorClosed = true
        if (step.stops) break
    }
    feedbackNotice = tally.notice
}

/** 캡처 한 장: 올리기 → 붙이기(맥과 같은 갈래 — 저장소 거절이면 붙이기에 까닭을 묻는다). */
@OptIn(ExperimentalUuidApi::class)
private suspend fun MeStore.uploadAndAttachFeedbackShot(shot: MeFeedbackShotDraft, userID: String, reportID: String): MeFeedbackShotStep {
    val path = FeedbackShotWire.objectPath(userID, reportID, Uuid.random().toString().lowercase())
    val service = context.service
    var uploadRefused = false
    try {
        context.withSessionRetry { s -> service.uploadFeedbackShot(s.accessToken, path, shot.jpeg) }
    } catch (e: PrivateStorageError.alreadyExists) {
        // 앞선 시도가 실제로는 올라갔다 — 붙이기로 넘어간다.
    } catch (e: PrivateStorageError.forbidden) {
        uploadRefused = true
    } catch (e: Throwable) {
        if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) throw e
        return if (isMissingShots(e)) MeFeedbackShotStep.missing else MeFeedbackShotStep.failed
    }
    return try {
        val outcome = context.withSessionRetry { s ->
            service.attachFeedbackShot(s.accessToken, reportID, path, shot.pixelWidth.toLong(), shot.pixelHeight.toLong())
        }
        when (outcome) {
            is FeedbackAttachOutcome.attached -> MeFeedbackShotStep.attached
            is FeedbackAttachOutcome.doorClosed -> if (outcome.doorOpen == true) MeFeedbackShotStep.outdated else MeFeedbackShotStep.doorClosed
            is FeedbackAttachOutcome.tooMany -> MeFeedbackShotStep.tooMany(outcome.max)
            else -> if (uploadRefused) MeFeedbackShotStep.refused else MeFeedbackShotStep.failed
        }
    } catch (e: Throwable) {
        if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) throw e
        if (isMissingShots(e)) MeFeedbackShotStep.missing else if (uploadRefused) MeFeedbackShotStep.refused else MeFeedbackShotStep.failed
    }
}

/** "이 서버에는 그 함수(또는 버킷)가 없다" — 404 · PGRST202 · 버킷 없음. 입구를 숨기되 영구히 기억하지 않는다. */
private fun isMissingShots(e: Throwable): Boolean = when (e) {
    SupabaseWorkServiceError.DatabaseSchemaMissing -> true
    is SupabaseWorkServiceError.InvalidResponse -> e.statusCode == 404
    else -> false
}

// ---------------------------------------------------------------- 목록 옆 칩

/** 목록이 비어 있지 않으면 **한 번에** 캡처 행을 받는다(②). 404 는 입구를 숨긴다(③). 다른 실패는 조용히 — 칩만 안 보인다. */
internal suspend fun MeStore.loadFeedbackShots(reports: List<FeedbackReport>, generation: Int) {
    if (!context.sessionStore.isSignedIn || reports.isEmpty() || !feedbackShotsShown) return
    val ids = reports.map { it.id.lowercase() }
    val service = context.service
    try {
        val grouped = context.withSessionRetry { s -> service.fetchFeedbackShots(s.accessToken, ids) }
        if (generation != context.generation) return
        if (feedbackShotsByReport != grouped) feedbackShotsByReport = grouped
    } catch (e: Throwable) {
        if (generation != context.generation) return
        if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
        if (isMissingShots(e)) markFeedbackShotsMissing()
    }
}
