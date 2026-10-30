// 원본: 없음(조립 — Windows 기기 행). 근거: xplat-design/B-server-expansion.md 계약 1("같은 installation_id 로 client_devices 에
// 'windows' 행을 등록한다") · supabase/migrations 20261101100000(M1: register_device 플랫폼 3값) · 20261101120000(M3:
// ultra_windows_floor_build · windows_device_build 가 client_devices platform='windows' 짝 행을 읽는다).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.registerDevice
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.device.DeviceRegistration
import com.yehsung.aingcheck.core.wire.models.RegisterDeviceResponse

/**
 * Windows 기기 등록: `register_device(p_installation_id, p_platform='windows', p_app_build, p_app_version)` — 푸시 토큰이 없어
 * APNs 칸은 언제나 뺀다. 이 행이 있어야 서버가 Windows 만 쓰는 사람을 새 울트라 경제(밑바닥 1)로 보고
 * (ultra_windows_floor_build), 'win:'||installation_id 기기 행의 빌드 축을 읽는다(windows_device_build — 찌르기·대결 능력).
 *
 * 세션 스토어가 언제 부를지(로그인·포그라운드 1시간 스로틀·로그아웃 정리의 unregister_device)를 정한다. 설치 식별자를 확인하지
 * 못했으면 스토어가 부르지 않는다(기기 신원을 지어내지 않는다). M1 전 서버는 'windows' 를 invalid 로 돌려준다 — 스토어가
 * 스탬프를 찍지 않고 조용히 넘긴다(쓰기 0).
 *
 * core 의 [DeviceRegistration.forPlatform] 기본값(Windows → None)은 그대로 두고 조립(AppWirings)이 이것을 넘긴다.
 */
object WindowsDeviceRegistration : DeviceRegistration {
    const val PLATFORM: String = "windows"

    override val isEnabled: Boolean = true

    /** Windows 는 푸시 토큰이 없다. */
    override fun normalizedToken(raw: String?): String? = null

    override fun signature(userID: String, appInfo: AppInfo, token: String?): String =
        listOf(userID, PLATFORM, appInfo.build.toString(), appInfo.version).joinToString("|")

    override suspend fun register(
        service: SupabaseWorkService,
        accessToken: String,
        installationID: String,
        appInfo: AppInfo,
        token: String?,
    ): RegisterDeviceResponse = service.registerDevice(
        accessToken = accessToken,
        platform = PLATFORM,
        installationID = installationID,
        appBuild = appInfo.build,
        appVersion = appInfo.version,
        apnsToken = null,
        apnsEnvironment = null,
    )
}
