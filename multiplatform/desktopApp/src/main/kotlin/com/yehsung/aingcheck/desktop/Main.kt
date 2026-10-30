// 원본: Sources/check/CheckApp.swift:133-137·242-250·458-477 @ a63fea2 (SIGTERM → 평소 종료 절차, --autostart 면 창을 열지 않음,
// 종료 때 최대 3초 근무 마무리) · 설계 D§2-3·§2-4·§2-5 · G K11(조립 지점 — W1-f 뼈대, 이후 조정자)
//
// 에이전트·시험은 이 진입점을 실행하지 않는다(:desktopApp:run 금지 — 창). 순서가 계약이다:
//   ① JNA 속성(첫 JNA 클래스 로드 전) → ② Windows 확인 → ③ --selfcheck 면 진단만 찍고 끝 → ④ 단일 실행 가드(세션 시작 전 필수)
//   → 못 잡으면 첫 실행에 "열어 달라" 신호만 보내고 끝 → ⑤ 플랫폼·그래프 → ⑥ EDT 에서 조립(AppGraph.assemble — 배선 여섯)
//   → ⑦ shutdown hook(로그오프·종료 = SIGTERM, D§2-3 — W-6 #6 순서를 ShutdownSequence 가 상한 안에서) → ⑧ 시작(AppWirings.start:
//   트레이 발표자·InstanceActivation·트레이 클릭·업데이트 감시는 shell.start 하나가 한다 — 고정 Off 아이콘·빈 신호 듣기는 두지 않는다).
package com.yehsung.aingcheck.desktop

import com.sun.jna.platform.win32.User32
import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfaces
import com.yehsung.aingcheck.desktop.overlay.bubble.PretendardBubbleMeasure
import com.yehsung.aingcheck.desktop.platform.windows.network.NetworkReadiness
import com.yehsung.aingcheck.desktop.platform.windows.store.FileDesktopKeyValueStore
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.platform.windows.flyout.TaskbarProbe
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutIconLocator
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutScreen
import com.yehsung.aingcheck.desktop.shell.flyout.native.NativeTrayMenu
import com.yehsung.aingcheck.desktop.wiring.SwingFlyoutWindowPort
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitHTTPKtor
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitWindowsRunner
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountProbe
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAppServerSession
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexToolchain
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexToolchainCandidates
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnosticsScanner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.swing.Swing
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.awt.Desktop
import java.awt.Toolkit
import java.awt.datatransfer.StringSelection
import java.io.File
import com.yehsung.aingcheck.desktop.generated.BuildIdentity
import com.yehsung.aingcheck.desktop.generated.ProdConfig
import com.yehsung.aingcheck.desktop.platform.windows.HostOs
import com.yehsung.aingcheck.desktop.platform.windows.WindowsPlatform
import com.yehsung.aingcheck.desktop.platform.windows.env.WindowsEnvironment
import com.yehsung.aingcheck.desktop.platform.windows.identity.RegistryMachineIdentitySource
import com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsInstallationIdentity
import com.yehsung.aingcheck.desktop.platform.windows.instance.InstanceSignal
import com.yehsung.aingcheck.desktop.platform.windows.instance.WindowsSingleInstanceGuard
import com.yehsung.aingcheck.desktop.platform.windows.jna.JnaBootstrap
import com.yehsung.aingcheck.desktop.platform.windows.paths.PackageIdentity
import com.yehsung.aingcheck.desktop.platform.windows.paths.WindowsAppPaths
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.net.URI
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import javax.swing.SwingUtilities
import kotlin.system.exitProcess
import kotlin.time.Clock

data class LaunchOptions(val autostart: Boolean, val selfcheck: Boolean, val selfcheckOut: String? = null, val unknown: List<String>) {
    companion object {
        const val AUTOSTART = "--autostart"
        const val SELFCHECK = "--selfcheck"
        /** `--selfcheck=<path>`: 같은 한 줄을 그 파일에 UTF-8 로도 쓴다(GUI 서브시스템 런처는 stdout 이 없다 — package.md §4-4). */
        const val SELFCHECK_TO = "$SELFCHECK="

        fun parse(args: Array<String>): LaunchOptions {
            var autostart = false
            var selfcheck = false
            var out: String? = null
            val unknown = mutableListOf<String>()
            for (arg in args) {
                when {
                    arg == AUTOSTART -> autostart = true
                    arg == SELFCHECK -> selfcheck = true
                    arg.startsWith(SELFCHECK_TO) && arg.length > SELFCHECK_TO.length -> {
                        selfcheck = true
                        out = arg.substring(SELFCHECK_TO.length)
                    }
                    else -> unknown += arg
                }
            }
            return LaunchOptions(autostart = autostart, selfcheck = selfcheck, selfcheckOut = out, unknown = unknown)
        }
    }
}

/** --selfcheck 진단(비밀 없음 — 토큰·금고 내용은 싣지 않는다). VM·출시 확인(W6-b)이 빌드 신원·경로·신원 출처를 대조한다. */
object SelfCheck {
    fun report(jnaApplied: Map<String, String>): JsonObject {
        val (pfn, pfnCode) = PackageIdentity.currentFamilyName()
        val env = WindowsEnvironment.system()
        val paths = WindowsAppPaths.fromEnvironment(env, pfn)
        val identity = WindowsInstallationIdentity(RegistryMachineIdentitySource(), Path.of(paths.installationIdFile)).resolve()
        return buildJsonObject {
            put("platform", BuildIdentity.PLATFORM)
            put("build", BuildIdentity.BUILD)
            put("version", BuildIdentity.VERSION)
            put("osName", System.getProperty("os.name"))
            put("osArch", System.getProperty("os.arch"))
            put("javaVersion", System.getProperty("java.version"))
            put("packageFamilyName", pfn)
            put("packageQueryCode", pfnCode)
            put("dataDir", paths.dataDir)
            put("installationIdOrigin", identity.origin.name)
            put("installationId", identity.installationId)
            put("codexHomeSource", env.codexHome().source.name)
            put("jnaBootLibraryPath", jnaApplied["jna.boot.library.path"])
            put("jnaNoUnpack", System.getProperty("jna.nounpack"))
            for ((key, value) in buildFields()) put(key, value)
        }
    }

    /**
     * OS 를 읽지 않는 몫(package.md P2 — 맥 JVM 시험이 잰다): buildTime·gitSha(영수증 대조) · prodHost·prodKeySha8(운영 지문 —
     * 키 자체는 싣지 않고 sha256 앞 8자만, 키가 비면 "") · flags(DesktopAppConfig.fromBuild() 그대로).
     */
    fun buildFields(): JsonObject = buildJsonObject {
        put("buildTime", BuildIdentity.BUILD_TIME)
        put("gitSha", BuildIdentity.GIT_SHA)
        put("prodHost", prodHost(ProdConfig.SUPABASE_URL))
        put("prodKeySha8", keySha8(ProdConfig.SUPABASE_ANON_KEY))
        val flags = DesktopAppConfig.fromBuild()
        put(
            "flags",
            buildJsonObject {
                put("duels", flags.duels)
                put("poke", flags.poke)
                put("ultra", flags.ultra)
                put("chatToast", flags.chatToast)
                put("forkSafe", flags.forkSafe)
                put("tokenUpload", flags.tokenUpload)
                put("adoptedPokeConsume", flags.adoptedPokeConsume)
                put("spectator", flags.spectator)
            },
        )
    }

    fun prodHost(url: String): String = runCatching { URI(url).host }.getOrNull().orEmpty()

    fun keySha8(key: String): String {
        if (key.isEmpty()) return ""
        val digest = MessageDigest.getInstance("SHA-256").digest(key.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }.take(8)
    }

    /** stdout 과 같은 한 줄 + 줄바꿈을 UTF-8 로(부모 폴더가 없으면 만든다). */
    fun write(report: JsonObject, out: String) {
        val path = Path.of(out)
        path.toAbsolutePath().parent?.let { Files.createDirectories(it) }
        Files.writeString(path, report.toString() + "\n", Charsets.UTF_8)
    }
}

fun main(args: Array<String>) {
    val jnaApplied = JnaBootstrap.apply()
    val options = LaunchOptions.parse(args)
    if (!HostOs.isWindows()) {
        System.err.println("아잉체크 데스크톱은 Windows 전용이다(os.name=${System.getProperty("os.name")})")
        exitProcess(2)
    }
    if (options.selfcheck) {
        val report = SelfCheck.report(jnaApplied)
        println(report)
        options.selfcheckOut?.let { SelfCheck.write(report, it) }
        exitProcess(0)
    }
    val guard = WindowsSingleInstanceGuard()
    if (!guard.tryAcquire()) {
        InstanceSignal.activateExisting()
        exitProcess(0)
    }
    val events = Executor { SwingUtilities.invokeLater(it) }
    val platform = WindowsPlatform.create(
        guard = guard,
        clock = Clock.System,
        events = events,
        executable = ProcessHandle.current().info().command().orElse(null),
    )
    val graph = AppGraph(platform)
    // UI 한 줄기(Swing EDT): 스토어·근무 상태·창이 모두 여기서 돈다. 조립도 EDT 에서(FlyoutWindow·게임 창 생성자가 EDT 요구).
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Swing)
    var wirings: AppWirings? = null
    SwingUtilities.invokeAndWait { wirings = graph.assemble(windowsSeams(platform, graph, events), appScope) }
    val app = checkNotNull(wirings)
    val done = CountDownLatch(1)
    Runtime.getRuntime().addShutdownHook(
        Thread({
            // 로그오프·시스템 종료·트레이 '종료'가 모두 여기로 온다(WM_QUERYENDSESSION → SIGTERM, D§2-3). W-6 #6 순서 그대로, 전체 상한 안.
            val startNanos = System.nanoTime()
            runCatching {
                runBlocking {
                    withTimeoutOrNull(ShutdownSequence.TOTAL_BUDGET_MILLIS + SHUTDOWN_GRACE_MILLIS) {
                        withContext(Dispatchers.Swing) {
                            ShutdownSequence.run(app.shutdownSteps(), elapsedMillis = { (System.nanoTime() - startNanos) / 1_000_000 })
                        }
                    }
                }
            }
            platform.desktopEvents.onShutdown()
            platform.close()
            done.countDown()
        }, "aingcheck-shutdown"),
    )
    SwingUtilities.invokeLater { app.start() }
    done.await()
}

/** Windows 실물 이음(AppSeams). EDT 에서 부른다 — SwingFlyoutWindowPort 가 창을 만든다. */
internal fun windowsSeams(platform: WindowsPlatform, graph: AppGraph, events: Executor): AppSeams {
    val homes = DesktopAiHomes(Path.of(platform.paths.userHome)) { Path.of(platform.environment.codexHome().path) }
    val pathDirs = System.getenv("PATH").orEmpty().split(File.pathSeparatorChar).filter { it.isNotBlank() }
        .mapNotNull { runCatching { Path.of(it) }.getOrNull() }
    val codexProbe = CodexAccountProbe(
        candidates = { CodexToolchainCandidates.nativeCandidates(pathDirs).map { CodexToolchain(listOf(it.toString())) } },
        run = { t, now -> CodexAppServerSession.run(t, BuildIdentity.VERSION, now) },
    )
    return AppSeams(
        events = events,
        mainDispatcher = Dispatchers.Swing,
        window = SwingFlyoutWindowPort(),
        screen = FlyoutScreen { TaskbarProbe.probe(it) },
        iconLocator = FlyoutIconLocator { platform.tray.iconRect()?.let { PxRect(it.left, it.top, it.right, it.bottom) } },
        menu = NativeTrayMenu(platform.messageThread),
        instanceListen = { onActivate -> InstanceSignal.listen(platform.messageThread, events, onActivate) },
        trayIconSizePx = { User32.INSTANCE.GetSystemMetrics(SM_CXSMICON).takeIf { it in 8..256 } ?: 16 },
        characterSink = SilentCharacterSink(),
        bubbleMeasure = PretendardBubbleMeasure.bundled,
        homes = homes,
        tokenCacheFile = Path.of(platform.paths.dataDir, "token-usage-cache.json"),
        aiLimitRunner = AILimitWindowsRunner.live(homes, AILimitHTTPKtor.fetcher(graph.httpClient()), BuildIdentity.VERSION),
        codexAccountRunner = { now -> withContext(Dispatchers.IO) { codexProbe.fetch(now) } },
        computeDiagnostics = { m, b -> withContext(Dispatchers.IO) { CodexUsageDiagnosticsScanner.compute(homes.codexHome(), m, b) } },
        deviceLabel = { System.getenv("COMPUTERNAME") },
        runningTests = object : RunningTests {
            override val isRunningTests: Boolean = false
        },
        environment = System.getenv(),
        openUrl = { url -> runCatching { Desktop.getDesktop().browse(URI(url)) } },
        share = { text -> runCatching { Toolkit.getDefaultToolkit().systemClipboard.setContents(StringSelection(text), null) } },
        // EDT 밖에서 끝낸다 — 종료 훅이 근무 마무리를 EDT 로 돌려 보내므로 EDT 가 exitProcess 에 묶여 있으면 상한까지 멈춘다.
        quit = { Thread({ exitProcess(0) }, "aingcheck-quit").start() },
        // W3-d 파일 영속 kv(즉시 쓰기 키 = 근무 큐, 나머지 250ms 묶음 — W-13 #2). 생성자는 읽기만 한다.
        keyValueStore = FileDesktopKeyValueStore.inDataDir(platform.paths.dataDir),
        networkReadiness = NetworkReadiness.forHost(HostOs.isWindows()),
        consoleSessionUsable = platform::consoleSessionUsable,
        overlaySurfaces = { config -> OverlaySurfaces.create(platform, config) },
        beep = { runCatching { Toolkit.getDefaultToolkit().beep() } },
    )
}

/** 종료 훅 바깥 여유(EDT 왕복·플랫폼 닫기). */
private const val SHUTDOWN_GRACE_MILLIS = 1_000L
private const val SM_CXSMICON = 49
