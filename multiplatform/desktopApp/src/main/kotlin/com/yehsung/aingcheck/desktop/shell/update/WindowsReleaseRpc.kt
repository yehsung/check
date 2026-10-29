// W3-c5(shell/update) — 업데이트·공지 서버 조회 두 가지. 원본: CheckApp.swift 202-215 · CheckUpdateCheck.swift 311-345 ·
// SupabaseWorkService.swift 1247-1265(appCurrentNotice 의 null 규칙). Windows 는 맥 판의 app_latest_release(GitHub·DMG 경로)와
// 플랫폼 없는 app_current_notice 를 **부르지 않는다** — client_release('windows') · app_current_notice_for('windows') 만(구조 시험 ⑦).
//
// 공용 패치 1·2 전 임시: core/net 에 `appCurrentNoticeFor(platform)` 이 없고(패치 1), core/wire `ClientReleaseResponse` 에
// latest_version·download_url·updated_at 칸이 없다(패치 2). 그래서 이 파일 **한 곳에서만** `service.send` 로 두 RPC 를 직접 친다.
// 패치가 들어오면 [ServiceUpdateRpc] 몸을 공용 함수 호출로 바꾸고 [WindowsClientRelease]·[NoticeForRequest] 를 지운다.
package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.json.swiftTry
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.core.wire.models.ClientReleaseRequest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 서버 `client_release(p_platform)` 응답(20261101100000 마이그레이션의 jsonb 모양). 공용 패치 2 전 임시 — 공용
 * `ClientReleaseResponse` 의 다섯 칸에 서버가 이미 주는 셋(latest_version·download_url·updated_at)을 더했다. 모르는 플랫폼이면
 * `{"status":"unknown_platform"}` 하나만 온다(나머지는 null).
 */
@Serializable
data class WindowsClientRelease(
    @SerialName("status") val status: String? = null,
    @SerialName("platform") val platform: String? = null,
    @SerialName("min_build") val minBuild: Long? = null,
    @SerialName("latest_build") val latestBuild: Long? = null,
    @SerialName("notes") val notes: String? = null,
    @SerialName("latest_version") val latestVersion: String? = null,
    @SerialName("download_url") val downloadUrl: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)

/** 공용 패치 1 전 임시 — `app_current_notice_for(p_platform text)` 의 본문. */
@Serializable
internal data class NoticeForRequest(@SerialName("p_platform") val pPlatform: String)

/** 업데이트 조회기가 부르는 서버 두 가지. 앱은 [ServiceUpdateRpc], 시험은 가짜를 넘긴다. */
interface UpdateRpc {
    /** `client_release(p_platform)`. 던지면 "모름" — 받는 쪽이 상태를 바꾸지 않는다. */
    suspend fun clientRelease(): WindowsClientRelease

    /**
     * `app_current_notice_for(p_platform)`. 맥 `appCurrentNotice` 와 같은 null 규칙: 비2xx(옛 서버 404·5xx·429·anon 키 없음 —
     * [SupabaseWorkServiceError])와 `{}`(공지 없음)·디코드 실패는 null. **전송 실패(오프라인)는 던진다** — 받는 쪽이 떠 있던
     * 카드를 내리지 않게(CheckUpdateCheck.swift 335-341 "던졌다"와 "공지 없음"을 한 값으로 접지 않는다).
     */
    suspend fun currentNotice(): AppNotice?
}

/** 앱 조립(AppGraph)이 스토어와 같은 [SupabaseWorkService] 를 넘긴다 — 서비스를 하나 더 만들지 않는다(CheckApp.swift 204 ①). */
class ServiceUpdateRpc(
    private val service: SupabaseWorkService,
    /** `ClientIdentity.platform.wire` — Windows 빌드는 "windows". */
    private val platform: String,
) : UpdateRpc {
    override suspend fun clientRelease(): WindowsClientRelease {
        // 공용 패치 1·2 전 임시: 공용 fetchClientRelease 는 latest_version·download_url 을 버린다.
        val body = service.encode(ClientReleaseRequest.serializer(), ClientReleaseRequest(platform))
        val data = service.send(CLIENT_RELEASE_PATH, "POST", emptyList(), body, null, null)
        return service.decode(WindowsClientRelease.serializer(), data)
    }

    override suspend fun currentNotice(): AppNotice? {
        // 공용 패치 1·2 전 임시: core/net appCurrentNoticeFor 가 들어오면 그 호출로 바꾼다.
        val body = service.encode(NoticeForRequest.serializer(), NoticeForRequest(platform))
        val data = try {
            service.send(NOTICE_FOR_PATH, "POST", emptyList(), body, null, null)
        } catch (e: SupabaseWorkServiceError) {
            return null
        }
        return swiftTry { service.decode(AppNotice.serializer(), data) }
    }

    companion object {
        const val CLIENT_RELEASE_PATH: String = "/rest/v1/rpc/client_release"
        const val NOTICE_FOR_PATH: String = "/rest/v1/rpc/app_current_notice_for"
    }
}
