// 시험 봉인 컨벤션(A§4-1, K12). 모든 모듈의 모든 Test 작업에 같은 조건을 건다.
//
// - ② JVM 트립와이어: testkit 의 tripwire jar(InetAddressResolverProvider)를 **모든** Test 작업의 classpath 에 붙인다.
//   localhost 밖 이름 풀이는 예외로 막히고, 기록은 build/tripwire/<작업>.txt 에 남는다. 기록이 있으면 작업이 실패한다.
// - 홈 격리: user.home·HOME·APPDATA·LOCALAPPDATA·USERPROFILE·CLAUDE_CONFIG_DIR·CODEX_HOME 을 build/test-home/<작업> 로.
// - 창 금지: java.awt.headless=true 가 실행 조건이다(A§4-5).
// - Robolectric 은 실행 중에 Maven 에서 android-all 을 받지 않는다(offline + 미리 받은 jar 폴더).
// - slow 태그는 빠른 게이트에서 뺀다. -Paingcheck.includeSlow=true 면 넣는다(gate-full).

import org.gradle.api.attributes.Usage
import org.gradle.api.tasks.testing.Test
import org.gradle.kotlin.dsl.named

val libsCatalog = aingcheckLibs
val tripwireUsage: Usage = objects.named<Usage>("aingcheck-tripwire")

val aingcheckTripwire = configurations.create("aingcheckTripwire") {
    isCanBeConsumed = false
    isCanBeResolved = true
    attributes { attribute(Usage.USAGE_ATTRIBUTE, tripwireUsage) }
}
if (path != ":testkit") {
    dependencies.add(aingcheckTripwire.name, dependencies.project(mapOf("path" to ":testkit")))
}
// 시험 실행 classpath 에 트립와이어를 붙인다. Test 작업의 classpath 를 직접 고치지 않고 의존 설정에 더한다 —
// KGP·AGP 가 classpath 를 나중에 다시 정해도 빠지지 않게(실측: configureEach 의 classpath += 는 덮였다).
val tripwireRuntimeConfigs = setOf("desktopTestRuntimeOnly", "androidHostTestRuntimeOnly", "testRuntimeOnly")
// testkit 자신은 자기 jar 를 직접 붙인다(testkit/build.gradle.kts).
if (path != ":testkit") {
    configurations.matching { it.name in tripwireRuntimeConfigs }.configureEach {
        dependencies.add(project.dependencies.create(project.files(aingcheckTripwire)))
    }
}

// kotlin-test 의 JUnit 판 고르기: kotlin-test(공용)의 JVM 변형과 명시한 kotlin-test-junit(5) 이 같은 능력
// (kotlin-test-framework-impl)을 내서 부딪힌다(실측). Android 쪽(호스트 시험·기기 계측·testkit androidMain)은
// JUnit4(Robolectric·AndroidJUnitRunner), 데스크톱 쪽은 JUnit5 로 고른다.
val isAndroidAppProject = path == ":androidApp"
configurations.configureEach {
    val wantJUnit4 = isAndroidAppProject || name.contains("android", ignoreCase = true)
    val wanted = if (wantJUnit4) "kotlin-test-junit" else "kotlin-test-junit5"
    resolutionStrategy.capabilitiesResolution.withCapability("org.jetbrains.kotlin", "kotlin-test-framework-impl") {
        val pick = candidates.firstOrNull {
            (it.id as? org.gradle.api.artifacts.component.ModuleComponentIdentifier)?.module == wanted
        }
        if (pick != null) select(pick).because("aingcheck: ${if (wantJUnit4) "Android=JUnit4" else "데스크톱=JUnit5"}")
    }
}

val robolectricAndroidAll = configurations.create("aingcheckRobolectricAndroidAll") {
    isCanBeConsumed = false
    isCanBeResolved = true
    isTransitive = false
}
dependencies.add(robolectricAndroidAll.name, libsCatalog.lib("robolectric-android-all-instrumented"))

val robolectricDepsDir = layout.buildDirectory.dir("robolectric-deps")
val syncRobolectricJars = tasks.register<Sync>("aingcheckSyncRobolectricJars") {
    description = "Robolectric android-all 사전 계측 jar 를 오프라인 폴더로 옮긴다(A-X5)."
    from(robolectricAndroidAll)
    into(robolectricDepsDir)
}

val includeSlow = providers.gradleProperty("aingcheck.includeSlow").map { it.toBoolean() }.orElse(false)
val mpRoot = rootProject.layout.projectDirectory.asFile
val prodUrlForScan = providers.gradleProperty("aingcheck.prod.supabaseUrl").orElse("")

tasks.withType<Test>().configureEach {
    val taskName = name
    val homeDir = layout.buildDirectory.dir("test-home/$taskName").get().asFile
    val tripwireReport = layout.buildDirectory.file("tripwire/$taskName.txt").get().asFile
    val robolectricDir = robolectricDepsDir.get().asFile
    val slow = includeSlow.get()
    val securityOverride = layout.buildDirectory.file("aingcheck-seal/java.security.override").get().asFile

    useJUnitPlatform {
        if (!slow) excludeTags("slow")
    }
    dependsOn(syncRobolectricJars)

    systemProperty("java.awt.headless", "true")
    // 이름 풀이 캐시를 끈다(실측 두 건): ① 카나리아가 통로로 푼 이름이 캐시에 남으면 뒤 시험의 같은 이름이 트립와이어를
    // 건너뛴다 ② java.security 기본 negative.ttl=10 이 막힌 풀이를 캐시해 뒤 호출은 우리 제공자 대신 JDK 가 실패시킨다.
    // 보안 속성은 시스템 속성보다 먼저 읽히므로 -Djava.security.properties 덮어쓰기 파일로 준다.
    systemProperty("java.security.properties", securityOverride.absolutePath)
    systemProperty("sun.net.inetaddr.ttl", "0")
    systemProperty("sun.net.inetaddr.negative.ttl", "0")
    if (taskName.contains("UnitTest") || taskName.contains("AndroidHostTest")) {
        // Robolectric(SDK 36)의 FileDescriptor 가로채기는 jdk.internal.access.SharedSecrets 를 반사로 부른다
        // (JDK 21 실측: "module java.base does not export jdk.internal.access").
        jvmArgs(
            "--add-exports=java.base/jdk.internal.access=ALL-UNNAMED",
            "--add-opens=java.base/java.io=ALL-UNNAMED",
            "--add-opens=java.base/java.lang=ALL-UNNAMED",
            "--add-opens=java.base/java.util=ALL-UNNAMED",
            "--add-opens=java.base/java.net=ALL-UNNAMED",
            "--add-opens=java.base/java.nio=ALL-UNNAMED",
            "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
        )
    }
    systemProperty("user.home", homeDir.absolutePath)
    systemProperty("aingcheck.mpRoot", mpRoot.absolutePath)
    systemProperty("aingcheck.repoRoot", mpRoot.parentFile.absolutePath)
    systemProperty("aingcheck.tripwire.report", tripwireReport.absolutePath)
    systemProperty("aingcheck.prodUrlForScan", prodUrlForScan.get())
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", robolectricDir.absolutePath)
    environment(
        mapOf(
            "HOME" to homeDir.absolutePath,
            "APPDATA" to homeDir.resolve("AppData/Roaming").absolutePath,
            "LOCALAPPDATA" to homeDir.resolve("AppData/Local").absolutePath,
            "USERPROFILE" to homeDir.absolutePath,
            "CLAUDE_CONFIG_DIR" to homeDir.resolve(".claude").absolutePath,
            "CODEX_HOME" to homeDir.resolve(".codex").absolutePath,
        ),
    )
    // 시험 결과에 영향을 주는 바깥 변수(봉인 표식)는 입력으로 잡아 캐시가 봉인 여부를 섞지 않게 한다.
    inputs.property("aingcheckNetworkSealed", System.getenv("AINGCHECK_NETWORK_SEALED") ?: "")
    outputs.upToDateWhen { false }

    doFirst {
        // 트립와이어가 빠진 시험 작업은 ②층 없이 돈다 — 조용히 빠지지 않게 실행 직전에 확인한다.
        if (classpath.none { it.name == "aingcheck-tripwire.jar" }) {
            throw GradleException("$taskName: 시험 classpath 에 aingcheck-tripwire.jar 가 없다(②층 트립와이어 누락)")
        }
        securityOverride.parentFile.mkdirs()
        securityOverride.writeText("networkaddress.cache.ttl=0\nnetworkaddress.cache.negative.ttl=0\n")
        tripwireReport.delete()
        tripwireReport.parentFile.mkdirs()
        homeDir.mkdirs()
    }
    doLast {
        if (tripwireReport.isFile && tripwireReport.length() > 0) {
            throw GradleException(
                "망 트립와이어: 시험이 바깥 이름을 풀려고 했다($taskName) — ${tripwireReport.absolutePath}\n" +
                    tripwireReport.readLines().take(20).joinToString("\n"),
            )
        }
    }
}

// --- 게이트 묶음(scripts/gate-*.sh 가 루트 집계 작업으로 부른다) ---
// 빠른 게이트: 이 모듈의 JVM 시험 전부(Release 단위 시험은 Debug 와 겹치므로 뺀다).
tasks.register("aingcheckGateTests") {
    group = "verification"
    description = "게이트가 도는 이 모듈의 JVM 시험(데스크톱 + Android 호스트)."
    dependsOn(tasks.withType<Test>().matching { !it.name.contains("Release") })
}
// Windows 러너: Android 없이 데스크톱 JVM 시험만.
tasks.register("aingcheckGateDesktopTests") {
    group = "verification"
    description = "데스크톱 JVM 시험만(Windows 러너용)."
    dependsOn(tasks.withType<Test>().matching { it.name == "desktopTest" || (it.name == "test" && it.project.path == ":desktopApp") })
}

// --- 의존 예열(봉인 밖에서 한 번) ---
// 봉인 안에서는 --offline 이다. 시험 실행 classpath 의 바깥 모듈까지 미리 받아 둔다.
tasks.register("aingcheckPrefetch") {
    group = "build setup"
    description = "모든 classpath 의 바깥 모듈을 받아 둔다(봉인 전 예열, A§4-1)."
    dependsOn(syncRobolectricJars)
    // 설정 단계에서 파일 묶음을 잡아 둔다(실행 중 Task.project 접근은 Gradle 10 에서 오류 — 실측 경고).
    val targets = configurations.names.filter { name ->
        val cfg = configurations.getByName(name)
        cfg.isCanBeResolved && (name.endsWith("CompileClasspath") || name.endsWith("RuntimeClasspath") ||
            name == "compileClasspath" || name == "runtimeClasspath")
    }
    val collections = targets.map { name ->
        configurations.getByName(name).incoming.artifactView {
            isLenient = false
            componentFilter { it is org.gradle.api.artifacts.component.ModuleComponentIdentifier }
        }.files
    }
    val label = project.path
    doLast {
        val count = collections.sumOf { it.files.size }
        logger.lifecycle("aingcheckPrefetch $label: 설정 ${collections.size}개 · 파일 ${count}개")
    }
}
