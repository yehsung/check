// 원본: Sources/check/CheckApp.swift:133-137·242-250·458-477 @ a63fea2 (SIGTERM → 평소 종료 절차, --autostart 면 창을 열지 않음,
// 종료 때 최대 3초 근무 마무리) · 설계 D§2-3·§2-4·§2-5 · G K11(조립 지점 — W1-f 뼈대, 이후 조정자)
//
// 에이전트·시험은 이 진입점을 실행하지 않는다(:desktopApp:run 금지 — 창). 순서가 계약이다:
//   ① JNA 속성(첫 JNA 클래스 로드 전) → ② Windows 확인 → ③ --selfcheck 면 진단만 찍고 끝 → ④ 단일 실행 가드(세션 시작 전 필수)
//   → 못 잡으면 첫 실행에 "열어 달라" 신호만 보내고 끝 → ⑤ 플랫폼·그래프 → ⑥ shutdown hook(로그오프·종료 = SIGTERM, D§2-3)
//   → ⑦ 트레이 아이콘. 플라이아웃·메뉴·근무 마무리(finishWorkBeforeQuit 3초)는 껍데기·스토어 갈래(W3-c1·W2-g)가 여기 잇는다.
package com.yehsung.aingcheck.desktop

import com.sun.jna.platform.win32.User32
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
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarThemeProbe
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconRenderer
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconSpec
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconStatus
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayTooltip
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
    // 조정자가 웨이브 병합 때 세션·스토어·껍데기를 이 그래프에 잇는다(K11).
    @Suppress("UNUSED_VARIABLE")
    val graph = AppGraph(platform)
    val done = CountDownLatch(1)
    Runtime.getRuntime().addShutdownHook(
        Thread({
            // 로그오프·시스템 종료도 여기로 온다(WM_QUERYENDSESSION → SIGTERM, D§2-3). 근무 마무리(3초)는 W2-g 가 여기 잇는다.
            platform.desktopEvents.onShutdown()
            platform.close()
            done.countDown()
        }, "aingcheck-shutdown"),
    )
    InstanceSignal.listen(platform.messageThread, events) {
        // 두 번째 실행·시작 메뉴 재실행 → 플라이아웃 열기(W3-c1 이 잇는다).
    }
    val size = User32.INSTANCE.GetSystemMetrics(SM_CXSMICON).takeIf { it in 8..256 } ?: 16
    val status = TrayIconStatus.Off
    platform.tray.show(
        TrayIconRenderer.render(TrayIconSpec(status, redDot = false, theme = TaskbarThemeProbe.current(), sizePx = size)),
        TrayTooltip.text(status),
    )
    done.await()
}

private const val SM_CXSMICON = 49
