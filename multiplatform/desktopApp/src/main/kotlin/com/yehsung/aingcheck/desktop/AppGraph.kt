// 원본: 없음(새 코드) — G K11(조립 지점: W1-f 가 뼈대, 이후 조정자만) · A§2(의존 주입은 손으로 — 생성자 주입 + 플랫폼별 AppGraph,
// Koin·Hilt 를 쓰지 않는다) · D§2-1(각 OS 기능은 인터페이스 뒤)
//
// 뼈대만 둔다: 플랫폼 묶음 + 시계 + 빌드 신원 + HTTP 엔진 팩토리 한 자리. 세션·스토어·화면(W2·W3)은 조정자가 웨이브 병합 때
// 여기 생성자 주입으로 잇는다. 다른 갈래는 자기 팩토리만 낸다(K11).
package com.yehsung.aingcheck.desktop

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.foundation.platform.desktop.AppPaths
import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.IdleSource
import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.SessionEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.desktop.generated.BuildIdentity
import com.yehsung.aingcheck.desktop.generated.DesktopFlags
import com.yehsung.aingcheck.desktop.http.HttpEngineFactory
import com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsDeviceIdentity
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import io.ktor.client.HttpClient
import io.ktor.client.HttpClientConfig
import kotlin.time.Clock

/** K3 데스크톱 인터페이스 묶음. Windows 는 WindowsPlatform 이 채우고, 시험은 가짜로 채운다. */
interface DesktopPlatform {
    val paths: AppPaths
    val env: EnvReader
    val tokenVault: TokenVault
    val installationIdentity: InstallationIdentity
    val singleInstance: SingleInstanceGuard
    val tray: TrayHost
    val hotkeys: HotkeyService
    val idle: IdleSource
    val power: PowerEvents
    val session: SessionEvents
    /** MSI 판 Run 키. MSIX 는 StartupTask 라 null(D§5-5). */
    val loginItem: LoginItem?
}

class AppGraph(
    val platform: DesktopPlatform,
    /** 벽시계는 여기(앱 조립 지점)에서만 System 을 쓴다(구조 시험 R2). 아래 층은 주입받는다. */
    val clock: Clock = Clock.System,
    val monotonic: MonotonicClock = SystemMonotonicClock,
    val clientIdentity: ClientIdentity = ClientIdentity.fromGenerated(BuildIdentity.PLATFORM, BuildIdentity.BUILD, BuildIdentity.VERSION),
    /** Windows 기능 깃발(W-3 #17). 앱은 생성 상수에서, 시험은 값을 넣는다. */
    val desktopConfig: DesktopAppConfig = DesktopAppConfig.fromBuild(),
) {
    /** 세션 문맥의 AppConfig(duelsEnabled 등)는 desktopConfig 에서만 만든다(W-3 #17 — 다른 곳에서 깃발을 다시 적지 않는다). */
    val appConfig: AppConfig get() = desktopConfig.toAppConfig()

    /**
     * 서버 `device_id`(K6) = `'win:'` + 소문자 installation_id. 신원을 확인하지 못했으면 null — 이때 기기 단위 쓰기(토큰 업로드 등)는
     * 하지 않는다(G §5-1 #6, 기억 device-identity-must-not-be-invented). 부르는 쪽(W2-g·h)은 null 을 '건너뜀'으로 다룬다.
     */
    val deviceId: String? get() = WindowsDeviceIdentity.deviceId(platform.installationIdentity.installationId())

    /** 서버 `client_devices.installation_id`(uuid). */
    val installationId: String? get() = platform.installationIdentity.installationId()

    /** HTTP 클라이언트는 단일 팩토리에서만(G §8-12 · 구조 시험 R3c). */
    fun httpClient(configure: HttpClientConfig<*>.() -> Unit = {}): HttpClient = HttpEngineFactory.ktorClient(configure)
}

/** JVM 단조 시계(System.nanoTime). 앱 조립 지점에서만 만든다. */
object SystemMonotonicClock : MonotonicClock {
    override fun elapsedNanos(): Long = System.nanoTime()
}

/**
 * W-3 #17 — [DesktopAppConfig] 를 생성 상수 DesktopFlags(`-Paingcheck.windows.<이름>=true|false`, build-logic aingcheckWindowsFlags)에서
 * 만드는 **한 자리**. DesktopFlags 를 다른 곳에서 읽지 않는다(selfcheck 도 이 함수를 거친다).
 */
fun DesktopAppConfig.Companion.fromBuild(): DesktopAppConfig = DesktopAppConfig(
    duels = DesktopFlags.DUELS,
    poke = DesktopFlags.POKE,
    ultra = DesktopFlags.ULTRA,
    chatToast = DesktopFlags.CHAT_TOAST,
    forkSafe = DesktopFlags.FORK_SAFE,
    tokenUpload = DesktopFlags.TOKEN_UPLOAD,
    adoptedPokeConsume = DesktopFlags.ADOPTED_POKE_CONSUME,
    spectator = DesktopFlags.SPECTATOR,
)
