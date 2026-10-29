// 원본: 없음 — Android 조립 지점(K11). W2-a 패치 0001: 앱 구성 계약 appConfig.
// Android 조립 지점(K11 — 셸 몫). 플랫폼 서비스를 프로세스에 하나씩 만든다. 위젯 콜백이 콜드 스타트한 프로세스도
// 같은 Application 을 지나므로 같은 싱글턴을 쓴다(E§5.2 "프로세스 안 조정자 하나만 갱신").
// 세션·스토어(W2)는 이 그릇에 조정자가 이어 붙인다. 벽시계는 조립 지점에서만 만든다(구조 시험 R2).
package com.yehsung.aingcheck.android.app

import android.app.Application
import android.graphics.BitmapFactory
import android.os.Build
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import com.yehsung.aingcheck.android.generated.ProdConfig
import com.yehsung.aingcheck.android.http.HttpEngineFactory
import com.yehsung.aingcheck.android.nav.AppScreens
import com.yehsung.aingcheck.android.push.AndroidPushSystem
import com.yehsung.aingcheck.android.screens.account.DefaultAndroidAccountCleanup
import com.yehsung.aingcheck.android.shell.ShellPhases
import com.yehsung.aingcheck.android.widget.AingWidgetRuntime
import com.yehsung.aingcheck.android.widget.AingWidgetSnapshotFaces
import com.yehsung.aingcheck.android.widget.AingWidgetUpdater
import com.yehsung.aingcheck.android.widget.AndroidWidgetSharedData
import com.yehsung.aingcheck.android.widget.WidgetSnapshotTodoPatcher
import com.yehsung.aingcheck.android.widget.WidgetTodoToggle
import com.yehsung.aingcheck.android.widget.toAingWidgetInput
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.KtorRealtimeTransport
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.todo.JvmTodoFileSystem
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.phone.app.PhoneAppModel
import com.yehsung.aingcheck.feature.phone.app.PhoneEnvironment
import com.yehsung.aingcheck.feature.phone.widget.FileWidgetSnapshotFile
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshotCodec
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshotWriter
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.screens.session.kit.AvatarPhotoLoader
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.statement.readRawBytes
import io.ktor.http.isSuccess
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
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
import com.yehsung.aingcheck.ui.screens.settingscommon.AppearanceStore
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

    /**
     * 화면 모드(나 → 설정 → 화면 모드 — W3-b 조정자 패치 0002). 이 기기의 설정이라 세션·로그아웃과 무관하고 서버에 올리지 않는다.
     * 셸(MainActivity)이 AingTheme(mode = appearance.mode) 로 감싼다 — 고르는 즉시 재실행 없이 바뀐다.
     */
    val appearance: AppearanceStore by lazy { AppearanceStore(keyValueStore) }

    val lifecycle = AppLifecycle()
    val visibleRoute = VisibleRoute()
    val pushInbox = PushInbox()
    val routeProof = RouteProof(keyValueStore)
    val notificationPoster = NotificationPoster(app) { routeProof.value() }

    /** 알림 [수락]으로 연 신청(증표 확인됨). 오목·체스 스토어(W2-d)가 읽어 respond 를 부르고 비운다 — 한 번만. */
    val pendingInviteAccept = MutableStateFlow<AingRoute?>(null)

    // ---------- 7차 조립(K11): 폰 앱 모델 한 벌(W2-f §1) — 세션 · 탭 스토어 다섯 · 게임 · 루비 칸 · 푸시 · 위젯 ----------

    /** 스토어 · 세션이 도는 자리(메인 한 줄기). */
    val mainScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    /** 벽시계는 조립 지점에서만 만든다(구조 시험 R2). */
    val wallClock: SessionClock = SessionClock { SwiftDate(System.currentTimeMillis() / 1000.0) }

    /** 서버 문(단일 HTTP 팩토리 — G §8-12). 주소는 생성 구성(release 만 Gradle 속성, 그 밖은 .invalid). */
    val service: SupabaseWorkService by lazy {
        SupabaseWorkService(
            projectURL = ProdConfig.SUPABASE_URL,
            anonKey = ProdConfig.SUPABASE_ANON_KEY.takeIf { it.isNotBlank() },
            client = HttpEngineFactory.ktorClient(SupabaseWorkService.clientConfig),
            clock = { wallClock.now() },
            text = RulesWireTextRules,
            newUUIDString = { UUID.randomUUID().toString().uppercase() },
        )
    }

    /** 푸시 시스템(W2-f 패치 0001 — 권한 · FCM 토큰 · 설명 시트 표시 상태). */
    val pushSystem: AndroidPushSystem by lazy { AndroidPushSystem(app, keyValueStore) }

    /** 할 일 파일(지금 탭과 위젯 체크가 같은 파일 · 같은 잠금 — int-h K11 "NowStore 에 todoStorage"). */
    val todoStorage: NowTodoStorage by lazy { NowTodoStorage(File(app.filesDir, TODO_DIR).path, JvmTodoFileSystem()) }

    /**
     * 폰 앱 모델(W2-f). 루비 칸은 하나다 — 오목 · 체스(SessionGomokuHost) · 테트리스 · 확성기 · 나 탭(MeContext)이 같이 쓴다(§8-18 4).
     * 로그아웃 리셋 사슬(me.reset() 포함)은 앱 모델 안 sessionDidSignOut 이 Swift 순서대로 돈다 — 그릇이 따로 잇지 않는다.
     */
    val phone: PhoneAppModel by lazy {
        PhoneAppModel(
            PhoneEnvironment(
                service = service,
                vault = tokenVault,
                prefs = keyValueStore,
                appInfo = AppInfo(clientIdentity, osVersion = "Android ${Build.VERSION.RELEASE}"),
                installationIdentity = installationIdentity,
                clock = wallClock,
                instanceGuard = singleInstanceGuard,
                appConfig = appConfig,
                scope = mainScope,
                realtimeTransport = KtorRealtimeTransport.create(
                    HttpEngineFactory.ktorClient(KtorRealtimeTransport.clientConfig), mainScope, runningTests, System.getenv(),
                ),
                runsTimers = !runningTests.isRunningTests,
                widgetFile = widgetFile,
                reloadWidgetTimelines = { mainScope.launch { AingWidgetUpdater.updateAll(app) } },
                todoStorage = todoStorage,
                collation = NaturalKoNameCollation,
                drawableCharacters = CharacterArt.drawableCharacterSource,
                knownCharacterIDs = CharacterArt.portraitIds,
                logger = logger,
            ),
        )
    }

    /** 위젯 스냅숏 파일 하나(W2-f 쓰기 창구가 쓰고 위젯 얼굴이 읽는다 — 같은 프로세스 · 같은 파일). */
    val widgetFile: FileWidgetSnapshotFile by lazy { FileWidgetSnapshotFile(File(app.filesDir, WidgetSnapshotWriter.FILE_NAME)) }

    /**
     * 위젯 런타임 배선(K11 — AingWidgetFaces.kt 머리말). 얼굴 = 그릴 때마다 스냅숏 파일을 읽어 [toAingWidgetInput](없거나 못 읽으면 로그아웃 얼굴 —
     * 로그아웃은 쓰기 창구가 파일을 지운다). 체크 = WidgetTodoToggle(앱과 같은 설정 · 금고 · 할 일 폴더 · 서버 문, 토큰 갱신 없음).
     * 체크 본문은 메인에서 돈다 — 스냅숏 줄 고치기([NowWidgetSnapshotSink.patchTodo])와 할 일 파일 편집이 앱 스토어와 같은 줄기를 탄다
     * (서버 요청은 멈춤 지점이라 메인을 막지 않는다). 앱 프로세스 시작 때 한 번(AingApplication.startPhone — 시험 프로세스는 안 부른다).
     */
    fun installWidgetRuntime() {
        AingWidgetRuntime.faces = AingWidgetSnapshotFaces { widgetFile.read()?.let(WidgetSnapshotCodec::decode)?.toAingWidgetInput() }
        AingWidgetRuntime.toggleTodo = { id ->
            withContext(Dispatchers.Main) {
                WidgetTodoToggle.run(id, widgetShared, { wallClock.now().timeIntervalSince1970 }, WidgetTodoToggle.serviceSync(service))
            }
        }
    }

    /** 위젯 체크가 앱과 나눠 보는 창구(첫 체크 때 만든다 — 금고 · 서버 문을 앱 시작에 미리 열지 않는다). */
    private val widgetShared: AndroidWidgetSharedData by lazy {
        AndroidWidgetSharedData(
            prefs = keyValueStore,
            vault = tokenVault,
            storage = todoStorage,
            snapshot = WidgetSnapshotTodoPatcher { id, done -> phone.widgetSink.patchTodo(id, done) },
        )
    }

    /** 화면 갈래 진입 함수의 의존 한 벌(NavGraph · AingShell). */
    val screens: AppScreens by lazy {
        AppScreens(
            phone = phone,
            appearance = appearance,
            prefs = keyValueStore,
            lifecycle = lifecycle,
            currentBuild = clientIdentity.build.toLong(),
            accountCleanup = DefaultAndroidAccountCleanup(app, pushTokenDeleter = { pushSystem.unregisterForRemoteNotifications() }),
            screenArt = ScreenArt(AvatarPhotoLoader { url -> photoLoader.load(url) }),
            primerVisible = pushSystem.isPrimerVisible,
        )
    }

    /** 원격 프로필 사진 읽개(앱의 단일 HTTP 엔진 — 구조 시험 R3c: ui 는 HTTP 를 만들지 않는다). 실패는 null → 캐릭터 · 이니셜. */
    private val photoLoader by lazy { AvatarPhotoHttp(HttpEngineFactory.ktorClient()) }

    private var placeholderShell = false

    /**
     * 셸 시험(ShellNavigationTest · ShellTabColorsTest · 기기 HistoryRelaunchDeviceTest)이 화면 없이 탭 · 딥링크 · 수락 증표만 재려고 고르는
     * 자리표시 셸. Activity 를 띄우기 **전에** 부른다. 단계는 탭으로 고정되고, 수락은 [pendingInviteAccept] 에 적힌다.
     * [on] = false 는 되돌리기다 — 기기 시험은 한 프로세스에서 이어 돌아 다음 시험(AppLaunchDeviceTest — 조립 셸을 잰다)이 이 값을 물려받는다.
     */
    fun usePlaceholderShell(on: Boolean = true) {
        placeholderShell = on
    }

    /** 셸이 그릴 화면 한 벌. 자리표시 셸이면 null. */
    val shellScreens: AppScreens? get() = if (placeholderShell) null else screens

    private val placeholderPhase = MutableStateFlow(ShellPhase.SIGNED_IN)
    private val assembledPhase: StateFlow<ShellPhase> by lazy {
        phone.session.phaseFlow.map(ShellPhases::of).stateIn(mainScope, SharingStarted.Eagerly, ShellPhases.of(phone.session.phase))
    }

    /** 셸 단계(실행 중 → 업데이트 필요 → 로그인 → 탭). 원천은 세션 스토어(W2-a SessionStore.phaseFlow). */
    val shellPhase: StateFlow<ShellPhase> get() = if (placeholderShell) placeholderPhase else assembledPhase

    private companion object {
        const val VAULT_DIR = "vault"
        const val TODO_DIR = "todos"
    }
}

/** 프로필 사진 GET → 비트맵(디코드는 기본 디스패처). 실패 · 비정상 응답은 null(iOS "사진을 못 읽으면 캐릭터"). */
internal class AvatarPhotoHttp(private val client: HttpClient) {
    suspend fun load(url: String): ImageBitmap? = try {
        val response = client.get(url)
        if (!response.status.isSuccess()) null
        else {
            val bytes = response.readRawBytes()
            withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }
        }
    } catch (error: Throwable) {
        if (error is kotlinx.coroutines.CancellationException) throw error
        null
    }
}
