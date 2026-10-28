// 원본: Sources/CheckCore/SupabaseWorkService.swift:946-964(setStatusMessage) · Sources/CheckCore/Achievements.swift:280-310(achievementsStatus ·
//       achievementClaim) · Sources/CheckCore/DailyMissions.swift:197-213(dailyMissionClaim) · Sources/CheckCore/WeeklyWorkReward.swift:326-360
//       (weeklyWorkStatus · weeklyWorkClaim) · Sources/CheckCore/Megaphone.swift:203-241(sendMegaphone · megaphoneInfo) ·
//       Sources/CheckMobileKit/Me/MeAILimitsService.swift:91-139(fetchMyAILimits) @ 1b8260d
package com.yehsung.aingcheck.core.stores.service

import com.yehsung.aingcheck.core.net.StatusMessageSaveResult
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.achievementClaimRaw
import com.yehsung.aingcheck.core.net.achievementsStatusRaw
import com.yehsung.aingcheck.core.net.dailyMissionClaimRaw
import com.yehsung.aingcheck.core.net.fetchMyAILimitRows
import com.yehsung.aingcheck.core.net.megaphoneInfoRaw
import com.yehsung.aingcheck.core.net.sendMegaphoneRaw
import com.yehsung.aingcheck.core.net.setStatusMessage
import com.yehsung.aingcheck.core.net.weeklyWorkClaimRaw
import com.yehsung.aingcheck.core.net.weeklyWorkStatusRaw
import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.rules.text.MegaphoneBody
import com.yehsung.aingcheck.core.rules.text.MegaphoneInfoResponse
import com.yehsung.aingcheck.core.rules.text.MegaphoneSendResponse
import com.yehsung.aingcheck.core.rules.text.MessageBodyValidation
import com.yehsung.aingcheck.core.rules.text.StatusMessageSaveOutcome
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkStatus
import com.yehsung.aingcheck.core.stores.me.AILimitFetchedRow

/*
 * Swift 서비스 함수 가운데 **반환 타입이 rules 에 있는 것**(G5 골든 spec.resultOtherLanes)의 Kotlin 한 벌.
 *
 * Swift 는 `SupabaseWorkService` 의 메서드 하나가 요청 → 디코드 → 규칙 합성을 다 한다. Kotlin 은 모듈이 갈려(net 은 rules 를 모른다)
 * net 이 요청과 날것 응답(`…Raw` · `StatusMessageSaveResult` · `AILimitServerRow`)까지, 이 파일이 rules 디코드와 합성을 맡는다 —
 * net 과 rules 를 둘 다 보는 가장 낮은 모듈이 core/stores 다. 스토어(W2-b 메시지 · W2-c 나 · 미션 화면)는 이 함수를 부르고 다시 합성하지 않는다.
 * G5 요청 골든 대조(core/stores desktopTest `wiregolden`)도 이 함수를 그대로 부른다 — 시험 안에 따로 합성하면 앱이 다르게 합성해도 초록이다
 * (6차 c-fold 검증 지적).
 *
 * net 의 같은 이름 함수(`setStatusMessage` → `StatusMessageSaveResult`)와 겹치지 않게 상태메시지만 이름이 다르다([setStatusMessageOutcome]).
 */

/**
 * Swift `setStatusMessage(accessToken:text:)` → `StatusMessageSaveOutcome`. 서버에 함수가 없으면(PGRST202 · 404) throw 하지 않고
 * `serverNotReady`(net 이 그 둘을 가른다), 응답이 오면 세 칸(status · status_message · max_length)으로 결과를 정한다.
 */
suspend fun SupabaseWorkService.setStatusMessageOutcome(accessToken: String, text: String?): StatusMessageSaveOutcome =
    when (val result = setStatusMessage(accessToken, text)) {
        is StatusMessageSaveResult.Response ->
            StatusMessageSaveOutcome.from(result.response.status, result.response.statusMessage, result.response.maxLength)
        StatusMessageSaveResult.ServerNotReady -> StatusMessageSaveOutcome.serverNotReady
    }

/** Swift `achievementsStatus(accessToken:)` — 관대한 디코드(최상위가 객체가 아닐 때만 throw). 함수 없는 서버는 net 오류 그대로 던진다. */
suspend fun SupabaseWorkService.achievementsStatus(accessToken: String): AchievementStatus =
    AchievementStatus.decode(achievementsStatusRaw(accessToken))

/** Swift `achievementClaim(accessToken:key:)` — key 가 null 이면 받을 것 전부. 응답은 상태와 같은 모양 + claimed_now. */
suspend fun SupabaseWorkService.achievementClaim(accessToken: String, key: String?): AchievementStatus =
    AchievementStatus.decode(achievementClaimRaw(accessToken, key))

/** Swift `dailyMissionClaim(accessToken:key:)` — 응답은 achievements_status 와 같은 모양 전체 + claimed_now(일일 지급만). */
suspend fun SupabaseWorkService.dailyMissionClaim(accessToken: String, key: String?): AchievementStatus =
    AchievementStatus.decode(dailyMissionClaimRaw(accessToken, key))

/** Swift `weeklyWorkStatus(accessToken:)` — 서버가 먼저 정산하고 돌려준다(읽기 전용이 아니다). */
suspend fun SupabaseWorkService.weeklyWorkStatus(accessToken: String): WeeklyWorkStatus =
    WeeklyWorkStatus.decode(weeklyWorkStatusRaw(accessToken))

/** Swift `weeklyWorkClaim(accessToken:weekStart:hours:)` — 둘 다 null 이면 받을 것 전부(어느 주든). 응답은 상태와 같은 모양 + claimed_now. */
suspend fun SupabaseWorkService.weeklyWorkClaim(accessToken: String, weekStart: String? = null, hours: Long? = null): WeeklyWorkStatus =
    WeeklyWorkStatus.decode(weeklyWorkClaimRaw(accessToken, weekStart, hours))

/**
 * Swift `sendMegaphone(accessToken:body:requestID:)`. **빈 글 · 상한 초과는 요청을 내지 않고** 서버와 같은 status 로 즉답한다
 * (`MegaphoneBody.validate` 의 empty · tooLong). 보내는 글자는 정규화한 값이고, 표식(`📢 `)은 서버가 붙인다.
 * 함수가 없는 서버는 net 오류(databaseSchemaMissing)로 던진다 — 스토어가 "지금은 보낼 수 없어요"로 접는다.
 */
suspend fun SupabaseWorkService.sendMegaphone(accessToken: String, body: String, requestID: String): MegaphoneSendResponse =
    when (val validation = MegaphoneBody.validate(body)) {
        is MessageBodyValidation.empty -> MegaphoneSendResponse(status = "empty", maxLength = MegaphoneBody.maxLength.toLong())
        is MessageBodyValidation.tooLong -> MegaphoneSendResponse(status = "too_long", maxLength = validation.maxLength.toLong())
        is MessageBodyValidation.ok -> MegaphoneSendResponse.decode(sendMegaphoneRaw(accessToken, validation.value, requestID))
    }

/** Swift `megaphoneInfo(accessToken:)` — 작성 화면 정보(인자 없는 RPC, 본문 `{}`). 칸 모양이 틀리면 전체 throw. */
suspend fun SupabaseWorkService.megaphoneInfo(accessToken: String): MegaphoneInfoResponse =
    MegaphoneInfoResponse.decode(megaphoneInfoRaw(accessToken))

/**
 * Swift `fetchMyAILimits(accessToken:userID:)` → `[AILimitFetchedRow]`. 요청 · 행 디코드는 net [fetchMyAILimitRows], 행 거르기 · 값 정규화는
 * [AILimitFetchedRow.fromRows] **한 자리**(Swift `compactMap` 하나와 같다 — 두 자리에서 거르면 한쪽은 영영 돌지 않는다).
 */
suspend fun SupabaseWorkService.fetchMyAILimits(accessToken: String, userID: String): List<AILimitFetchedRow> =
    AILimitFetchedRow.fromRows(fetchMyAILimitRows(accessToken, userID))
