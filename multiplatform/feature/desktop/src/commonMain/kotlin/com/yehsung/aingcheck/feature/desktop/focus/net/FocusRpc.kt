// 원본: Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 923-935(updateFocusMode) · Sources/CheckCore/SupabaseWorkModels.swift 2609-2613 @ a90d8623
package com.yehsung.aingcheck.feature.desktop.focus.net

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** profiles.focus_mode 자기 행 PATCH 본문. 토큰 공개와 **따로** 보낸다(컬럼당 별도 구조체 — 한 칸이 없는 서버에서 다른 칸까지 죽지 않게). */
@Serializable
data class ProfileFocusModeUpdateRequest(@SerialName("focus_mode") val focusMode: Boolean)

object FocusRpcPaths {
    const val PROFILES: String = "/rest/v1/profiles"
}

/** 집중 모드(찌르기 수신 거부) 갱신 — 컬럼 단위 UPDATE 권한이 있어야 통과한다. 응답 본문은 버린다(return=minimal). */
suspend fun SupabaseWorkService.updateFocusMode(accessToken: String, userID: String, enabled: Boolean) {
    sendNoBody(
        FocusRpcPaths.PROFILES, "PATCH", listOf("id" to "eq.$userID"),
        encode(ProfileFocusModeUpdateRequest.serializer(), ProfileFocusModeUpdateRequest(enabled)), accessToken, "return=minimal",
    )
}
