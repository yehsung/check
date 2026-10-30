// W3-c5(shell/update) — 업데이트·공지 서버 조회 두 가지. 원본: CheckApp.swift 202-215 · CheckUpdateCheck.swift 311-345 ·
// SupabaseWorkService.swift 1247-1265(appCurrentNotice 의 null 규칙). Windows 는 맥 판의 app_latest_release(GitHub·DMG 경로)와
// 플랫폼 없는 공지를 **부르지 않는다** — 공용 함수 `fetchClientRelease(platform)`(core/net · 공용 패치 2 의 세 칸 포함)과
// `appCurrentNoticeFor(platform)`(공용 패치 1)만 부른다(구조 시험 ⑦). 이 앱은 RPC 경로를 직접 치지 않는다.
package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.appCurrentNoticeFor
import com.yehsung.aingcheck.core.net.fetchClientRelease
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse

/** 업데이트 조회기가 부르는 서버 두 가지. 앱은 [ServiceUpdateRpc], 시험은 가짜를 넘긴다. */
interface UpdateRpc {
    /** `client_release(p_platform)`(모르는 플랫폼이면 `{"status":"unknown_platform"}` 하나 — 나머지 null). 던지면 "모름" — 받는 쪽이 상태를 바꾸지 않는다. */
    suspend fun clientRelease(): ClientReleaseResponse

    /**
     * `app_current_notice_for(p_platform)`. 맥 `appCurrentNotice` 와 같은 null 규칙(공용 함수가 진다): 비2xx 와 `{}`(공지 없음)·디코드
     * 실패는 null. **전송 실패(오프라인)는 던진다** — 받는 쪽이 떠 있던 카드를 내리지 않게(CheckUpdateCheck.swift 335-341).
     */
    suspend fun currentNotice(): AppNotice?
}

/** 앱 조립(AppGraph)이 스토어와 같은 [SupabaseWorkService] 를 넘긴다 — 서비스를 하나 더 만들지 않는다(CheckApp.swift 204 ①). */
class ServiceUpdateRpc(
    private val service: SupabaseWorkService,
    /** `ClientIdentity.platform.wire` — Windows 빌드는 "windows". */
    private val platform: String,
) : UpdateRpc {
    override suspend fun clientRelease(): ClientReleaseResponse = service.fetchClientRelease(platform)

    override suspend fun currentNotice(): AppNotice? = service.appCurrentNoticeFor(platform)
}
