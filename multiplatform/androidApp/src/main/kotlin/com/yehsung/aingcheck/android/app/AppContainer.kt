// 원본: 없음 — Android 조립 지점(K11). W2-a 패치 0001: 앱 구성 계약 appConfig.
// Android 조립 지점(K11 — 셸 몫). 플랫폼 서비스를 프로세스에 하나씩 만든다. 위젯 콜백이 콜드 스타트한 프로세스도
// 같은 Application 을 지나므로 같은 싱글턴을 쓴다(E§5.2 "프로세스 안 조정자 하나만 갱신").
// 세션·스토어(W2)는 이 그릇에 조정자가 이어 붙인다. 벽시계는 조립 지점에서만 만든다(구조 시험 R2).
package com.yehsung.aingcheck.android.app

import android.app.Application
import com.yehsung.aingcheck.android.generated.BuildIdentity
import com.yehsung.aingcheck.android.identity.AndroidInstallationIdentity
import com.yehsung.aingcheck.android.lifecycle.AppLifecycle
import com.yehsung.aingcheck.android.push.NotificationPoster
import com.yehsung.aingcheck.android.push.PushInbox
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteProof
import com.yehsung.aingcheck.android.routing.VisibleRoute
import com.yehsung.aingcheck.android.shell.ShellPhase
import com.yehsung.aingcheck.android.vault.AndroidKeystoreCipher
import com.yehsung.aingcheck.android.vault.KeystoreTokenVault
import com.yehsung.aingcheck.android.vault.VaultCipher
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.session.app.AppConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File

class AppContainer(
    private val app: Application,
    /**
     * 금고 봉투. 운영은 언제나 Android Keystore 다. Robolectric 에는 AndroidKeyStore 제공자가 없어서, 호스트 시험만 소프트웨어 봉투를
     * 넘겨 **이 그릇이 고른 자리**에 금고가 실제로 쓰는지 잰다(AppContainerVaultTest).
     */
    private val vaultCipher: () -> VaultCipher = { AndroidKeystoreCipher() },
) {
    /** K4: (android, versionCode, versionName) — version.properties 한 곳에서 온다. */
    val clientIdentity: ClientIdentity = ClientIdentity.fromGenerated(BuildIdentity.PLATFORM, BuildIdentity.BUILD, BuildIdentity.VERSION)

    /**
     * 앱 구성 계약(W2-a `AppConfig` · G §8-17 #1). 판돈 대결 진입 깃발의 원천은 BuildConfig 하나다 — 조정자가 세션 문맥을 조립할 때
     * `SessionContext(sessionStore, appConfig)` 로 넘기고, 스토어(W2-d·W2-e)는 그 문맥으로만 읽는다.
     */
    val appConfig: AppConfig = AndroidAppConfig.fromBuildConfig()

    val logger: Logger = LogcatLogger()
    val keyValueStore: KeyValueStore = SharedPreferencesKeyValueStore(app)
    val runningTests: RunningTests = AndroidRunningTests
    val singleInstanceGuard: SingleInstanceGuard = ProcessSingleInstanceGuard
    val monotonicClock: MonotonicClock = ElapsedRealtimeClock

    /** 금고·설치 UUID 는 noBackupFilesDir 아래(백업·기기 이전에서 빠진다, E§5.2). */
    val tokenVault: TokenVault by lazy { KeystoreTokenVault(File(app.noBackupFilesDir, VAULT_DIR), vaultCipher()) }
    val installationIdentity: InstallationIdentity by lazy { AndroidInstallationIdentity(app.noBackupFilesDir) }

    val lifecycle = AppLifecycle()
    val visibleRoute = VisibleRoute()
    val pushInbox = PushInbox()
    val routeProof = RouteProof(keyValueStore)
    val notificationPoster = NotificationPoster(app) { routeProof.value() }

    /** 알림 [수락]으로 연 신청(증표 확인됨). 오목·체스 스토어(W2-d)가 읽어 respond 를 부르고 비운다 — 한 번만. */
    val pendingInviteAccept = MutableStateFlow<AingRoute?>(null)

    /**
     * 셸 단계(실행 중 → 업데이트 필요 → 로그인 → 탭). 원천은 세션 스토어(W2-a SessionStore.phase)이고, 조정자가 W2 병합 때
     * 이 자리를 그것으로 바꾼다. 그 전까지는 셸·딥링크·탭을 잴 수 있게 탭 단계로 둔다(화면은 전부 자리표시다).
     */
    private val phaseSource = MutableStateFlow(ShellPhase.SIGNED_IN)
    val shellPhase: StateFlow<ShellPhase> = phaseSource

    private companion object {
        const val VAULT_DIR = "vault"
    }
}
