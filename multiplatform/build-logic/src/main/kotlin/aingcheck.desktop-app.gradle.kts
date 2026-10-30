// Windows 트레이 앱 모듈(kotlin jvm + Compose Desktop). 에이전트는 :desktopApp:run 을 하지 않는다(창).
//
// 운영 구성(§8-5): Gradle 속성 → 생성 소스 한 파일(ProdConfig.kt), 기본 `.invalid`.
// CI 산출물은 속성 없이 만든다 → `.invalid` 주소로만 빌드된다(A§5). 출시 산출물은 이 맥·VM 에서 속성을 넣어 만든다.

import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
    id("aingcheck.test-seal")
}

val libsCatalog = aingcheckLibs
val versions = aingcheckVersionProperties()
val appPackage = aingcheckPackage()
val releaseAssembly = providers.gradleProperty("aingcheck.desktop.releaseAssembly").map { it.toBoolean() }.orElse(false).get()
val prodValues = aingcheckProdConfig(releaseAssembly = releaseAssembly)
val buildStamp = aingcheckBuildStamp(releaseAssembly = releaseAssembly)
val windowsFlags = aingcheckWindowsFlags()

run {
    val build = versions.required("windowsBuild").toInt()
    val parts = versions.required("windowsVersion").split('.').map { it.toInt() }
    if (parts.size != 3 || parts[0] !in 0..255 || parts[1] !in 0..255 || parts[2] !in 0..65535 || parts[2] != build) {
        throw GradleException("version.properties: windowsVersion 은 MAJOR.MINOR.BUILD(≤255.≤255.≤65535)이고 BUILD == windowsBuild 여야 한다")
    }
}

kotlin {
    jvmToolchain(21)
}

val generateProdConfig = tasks.register<GenerateKotlinConstants>("generateProdConfig") {
    packageName.set("$appPackage.generated")
    objectName.set(PROD_CONFIG_OBJECT)
    header.set("운영 구성(§8-5). -Paingcheck.desktop.releaseAssembly=true 일 때만 Gradle 속성 aingcheck.prod.* 를 읽는다. 기본 .invalid")
    constants.put("SUPABASE_URL", prodValues.supabaseUrl)
    constants.put("SUPABASE_ANON_KEY", prodValues.supabaseAnonKey)
    outputDir.set(layout.buildDirectory.dir("generated/aingcheck/prodConfig/main"))
}
val generateBuildIdentity = tasks.register<GenerateKotlinConstants>("generateBuildIdentity") {
    packageName.set("$appPackage.generated")
    objectName.set(BUILD_IDENTITY_OBJECT)
    header.set("K4 ClientIdentity 의 원천(version.properties). 플랫폼 windows")
    constants.put("PLATFORM", "windows")
    constants.put("BUILD", versions.required("windowsBuild"))
    constants.put("VERSION", versions.required("windowsVersion"))
    // package.md P1: 출시 영수증·selfcheck 대조용. 기본 "dev"·"unknown" — releaseAssembly=true 면 기본값 거부(aingcheckBuildStamp).
    constants.put("BUILD_TIME", buildStamp.buildTime)
    constants.put("GIT_SHA", buildStamp.gitSha)
    outputDir.set(layout.buildDirectory.dir("generated/aingcheck/buildIdentity/main"))
}
// W-3 #17: Windows 기능 깃발의 유일한 원천(generated 패키지 — 맥 jar 교체 허용 목록이 이 패키지 하나로 닫힌다).
// AppGraph 의 DesktopAppConfig.fromBuild() 한 곳에서만 읽는다.
val generateDesktopFlags = tasks.register<GenerateKotlinConstants>("generateDesktopFlags") {
    packageName.set("$appPackage.generated")
    objectName.set(DESKTOP_FLAGS_OBJECT)
    header.set("Windows 기능 깃발(W-3 #17). -Paingcheck.windows.<이름>=true|false 로만 바꾼다. 기본 전부 false, SPECTATOR 만 true")
    booleanConstants.putAll(windowsFlags)
    outputDir.set(layout.buildDirectory.dir("generated/aingcheck/desktopFlags/main"))
}

sourceSets.named("main") {
    kotlin.srcDir(generateProdConfig.flatMap { it.outputDir })
    kotlin.srcDir(generateBuildIdentity.flatMap { it.outputDir })
    kotlin.srcDir(generateDesktopFlags.flatMap { it.outputDir })
}

dependencies {
    "testImplementation"(project(":testkit"))
    "testImplementation"(libsCatalog.lib("kotlin-test-junit5"))
    "testImplementation"(platform(libsCatalog.lib("junit-bom")))
    "testImplementation"(libsCatalog.lib("junit-jupiter"))
    "testImplementation"(libsCatalog.lib("kotlinx-coroutines-test"))
    "testRuntimeOnly"(libsCatalog.lib("junit-platform-launcher"))
}

compose.desktop {
    application {
        // Main.kt·AppGraph.kt 는 조립 지점(K11) — W1-f 가 뼈대를 쓴다.
        mainClass = "$appPackage.MainKt"
        nativeDistributions {
            targetFormats(TargetFormat.Msi, TargetFormat.Exe)
            packageName = "AingCheck"
            // MSI 버전 칸: MAJOR.MINOR.BUILD, BUILD ≤ 65535(A§6-2).
            packageVersion = versions.required("windowsVersion")
            windows {
                // 영구 식별자(A§9-7) — G §8-13 에서 잠갔다. 바꾸면 새 판이 옛 판을 업그레이드로 못 알아봐 둘이 나란히 깔린다.
                upgradeUuid = versions.required("windowsUpgradeUuid")
                perUserInstall = true
                menu = true
                // W-6 #5(W6-b1 P3): 설치본·바로가기 아이콘. ico 항목 16/24/32/48/256(PNG) — W6-b1 이 커밋한 파일.
                iconFile.set(project.file("packaging/AingCheck.ico"))
            }
        }
    }
}

// 영구 식별자 값 고정(G §8-13): 패키징이 **실제로 쓰는** upgradeUuid 를 시험 JVM 에 넘긴다. PermanentIdentifierPinTest 가 손으로 적은
// 값과 대조한다 — version.properties 의 글자만 재면 이 파일이 다른 값·다른 키를 넣어도 초록이다(기억 tests-measure-shape-not-result).
// 모듈 빌드 파일이 나중에 덮어쓴 값까지 보도록 평가가 끝난 뒤에 읽는다.
afterEvaluate {
    val effectiveUpgradeUuid = compose.desktop.application.nativeDistributions.windows.upgradeUuid.orEmpty()
    val effectiveIcon = compose.desktop.application.nativeDistributions.windows.iconFile.orNull?.asFile?.absolutePath.orEmpty()
    tasks.withType<Test>().configureEach {
        systemProperty("aingcheck.msiUpgradeUuid", effectiveUpgradeUuid)
        systemProperty("aingcheck.msiIconFile", effectiveIcon)
    }
}
