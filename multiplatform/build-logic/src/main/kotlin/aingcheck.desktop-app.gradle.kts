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
    outputDir.set(layout.buildDirectory.dir("generated/aingcheck/buildIdentity/main"))
}

sourceSets.named("main") {
    kotlin.srcDir(generateProdConfig.flatMap { it.outputDir })
    kotlin.srcDir(generateBuildIdentity.flatMap { it.outputDir })
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
                // 영구 식별자 후보(A§9-7) — 첫 출시 전에 확정한다. 바꾸면 업그레이드 설치가 깨진다.
                upgradeUuid = versions.required("windowsUpgradeUuid")
                perUserInstall = true
                menu = true
            }
        }
    }
}
