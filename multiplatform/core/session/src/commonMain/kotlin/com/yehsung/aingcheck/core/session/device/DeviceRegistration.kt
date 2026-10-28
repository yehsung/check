// 원본: Sources/CheckMobileKit/Session/MobileDeviceService.swift:63-140(RegisterDeviceRequest · MobileDeviceRPC · registerDevice) @ 1b8260d
package com.yehsung.aingcheck.core.session.device

import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.wire.models.RegisterDeviceResponse
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 기기 등록 한 벌(플랫폼마다 다르다 — 세션 스토어는 언제 부를지만 정한다, C§4 #33).
 *
 * - Android: K5 `register_device_fcm(p_installation_id, p_app_build, p_app_version, p_fcm_token)` **하나**(§8-1 대체 표 —
 *   `register_device` 뒤 두 번 부르지 않는다). 토큰이 null 이면 키를 빼고 서버가 기존 토큰을 유지한다.
 * - Windows(보류 §8-16): 푸시 기기 행이 없다 → [None].
 */
interface DeviceRegistration {
    /** 이 플랫폼이 서버에 기기 행을 올리는가. 거짓이면 세션 스토어는 등록·해제를 부르지 않는다. */
    val isEnabled: Boolean

    /**
     * 푸시 토큰을 이 플랫폼의 규칙으로 거른다. 모양이 아니면 null(토큰 없음으로 본다).
     * FCM: `^[!-~]{32,4096}$`(B-9.1 — 공백 없는 인쇄 가능 ASCII). **대소문자를 바꾸지 않는다**(서버도 `btrim` 만, `lower()` 금지 — B M1).
     */
    fun normalizedToken(raw: String?): String?

    /** 스로틀 서명의 재료(값이 바뀌면 1시간 스로틀을 무시하고 다시 보낸다). */
    fun signature(userID: String, appInfo: AppInfo, token: String?): String

    /** 등록 한 번. 응답 칸은 전부 옵셔널(앱이 먼저 나가고 db push 가 늦은 창 · 옛 서버). */
    suspend fun register(
        service: SupabaseWorkService,
        accessToken: String,
        installationID: String,
        appInfo: AppInfo,
        token: String?,
    ): RegisterDeviceResponse

    /** Android FCM(K5). */
    object Fcm : DeviceRegistration {
        const val PATH: String = "/rest/v1/rpc/register_device_fcm"
        private val TOKEN_SHAPE = Regex("^[!-~]{32,4096}$")

        override val isEnabled: Boolean = true

        override fun normalizedToken(raw: String?): String? {
            // 서버와 같은 자르기(btrim — 공백·탭·개행)만 한다. 대소문자는 그대로.
            val trimmed = raw?.trim(' ', '\t', '\r', '\n') ?: return null
            return trimmed.takeIf { TOKEN_SHAPE.matches(it) }
        }

        override fun signature(userID: String, appInfo: AppInfo, token: String?): String =
            listOf(userID, appInfo.build.toString(), appInfo.version, token ?: "-").joinToString("|")

        override suspend fun register(
            service: SupabaseWorkService,
            accessToken: String,
            installationID: String,
            appInfo: AppInfo,
            token: String?,
        ): RegisterDeviceResponse {
            val body = RegisterDeviceFcmRequest(
                pInstallationId = installationID,
                pAppBuild = appInfo.build,
                pAppVersion = appInfo.version,
                pFcmToken = token,
            )
            val data = service.send(PATH, "POST", emptyList(), service.encode(RegisterDeviceFcmRequest.serializer(), body), accessToken, null)
            return service.decode(RegisterDeviceResponse.serializer(), data)
        }
    }

    /** 기기 행을 올리지 않는 플랫폼(Windows — 보류). */
    object None : DeviceRegistration {
        override val isEnabled: Boolean = false
        override fun normalizedToken(raw: String?): String? = null
        override fun signature(userID: String, appInfo: AppInfo, token: String?): String = userID
        override suspend fun register(
            service: SupabaseWorkService,
            accessToken: String,
            installationID: String,
            appInfo: AppInfo,
            token: String?,
        ): RegisterDeviceResponse = RegisterDeviceResponse(status = null)
    }

    companion object {
        fun forPlatform(platform: ClientPlatform): DeviceRegistration = when (platform) {
            ClientPlatform.ANDROID -> Fcm
            ClientPlatform.WINDOWS -> None
        }
    }
}

/**
 * `register_device_fcm` 본문(K5). null 칸은 키가 빠진다(Swift 합성 Encodable 과 같은 규칙 — SwiftJson 이 nil Optional 을 뺀다) →
 * 서버 기본값 null → **토큰이 null 이면 서버가 기존 토큰을 유지한다**. 토큰을 지울 때는 `unregister_device` 뒤 토큰 없이 다시 부른다.
 * `p_platform` 은 없다 — 서버가 'android' 로 고정한다(B M1).
 */
@Serializable
data class RegisterDeviceFcmRequest(
    @SerialName("p_installation_id") val pInstallationId: String,
    @SerialName("p_app_build") val pAppBuild: Long,
    @SerialName("p_app_version") val pAppVersion: String? = null,
    @SerialName("p_fcm_token") val pFcmToken: String? = null,
)
