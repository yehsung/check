// testkit — 시험 전용(K2): MockEngine 라우터·FakeClock·망 봉인 트립와이어·카나리아·금고 계약 추상 시험·구조 시험.
// 골든 로더(testkit/golden)는 W0-b 소유다(§8-3). 앱 산출물에는 들어가지 않는다(시험 classpath 에서만 쓴다).
//
// 트립와이어(A§4-1 ②)는 KMP 소스셋이 아니라 따로 컴파일하는 Java 한 줌이다:
//   Android 호스트 시험(Robolectric)도 JDK 위에서 돌지만 androidMain 은 android.jar 로 컴파일돼
//   java.net.spi 가 없다. 그래서 JDK 로만 컴파일한 jar 하나를 모든 Test 작업 classpath 에 붙인다(aingcheck.test-seal).

import org.gradle.api.attributes.Usage

plugins {
    id("aingcheck.kmp-library")
    id("aingcheck.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("io.github.takahirom.roborazzi")
}

// --- 트립와이어 jar ---
val tripwireClasses = layout.buildDirectory.dir("tripwire/classes")
val compileTripwire = tasks.register<JavaCompile>("compileTripwire") {
    description = "망 트립와이어(InetAddressResolverProvider, JEP 418)를 JDK 로만 컴파일한다."
    source = fileTree("src/tripwire/java")
    classpath = files()
    destinationDirectory.set(tripwireClasses)
    options.release.set(21)
    options.encoding = "UTF-8"
    javaCompiler.set(javaToolchains.compilerFor { languageVersion.set(JavaLanguageVersion.of(21)) })
}
val tripwireJar = tasks.register<Jar>("tripwireJar") {
    description = "트립와이어 jar(META-INF/services 포함)."
    archiveFileName.set("aingcheck-tripwire.jar")
    destinationDirectory.set(layout.buildDirectory.dir("tripwire/libs"))
    from(compileTripwire)
    from("src/tripwire/resources")
}
configurations.create("tripwireElements") {
    isCanBeConsumed = true
    isCanBeResolved = false
    attributes { attribute(Usage.USAGE_ATTRIBUTE, objects.named(Usage::class.java, "aingcheck-tripwire")) }
    outgoing.artifact(tripwireJar)
}
dependencies {
    // 자기 시험에는 jar 를 직접 붙인다(다른 모듈은 aingcheck.test-seal 이 tripwireElements 로 받는다).
    add("desktopTestRuntimeOnly", files(tripwireJar))
    add("androidHostTestRuntimeOnly", files(tripwireJar))
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:foundation"))
            api(libs.kotlin.test)
            api(libs.kotlinx.coroutines.test)
            api(libs.ktor.client.core)
            api(libs.ktor.client.mock)
            // Compose 컴파일러 플러그인은 main 컴파일에도 런타임을 요구한다(스냅숏 도우미 자리).
            implementation(libs.compose.runtime)
            // 공용 패치 13: ui·desktopApp 화면 시험 조립(ScreenHarness·MeScreenHarness·UiGamesHarness·보드 게임 스텁 — FQN 그대로)과
            // G5 녹음기(GoldenRecorder)가 진짜 스토어·서비스를 짓는다. compileOnly(공용 패치 7 관례): 실행 때 core 는 쓰는 쪽 시험 classpath 가
            // 준다 — implementation 이면 core 시험마다 자기 main 을 testkit 너머로 한 벌 더 받는다. testkit → ui main 의존은 두지 않는다.
            compileOnly(project(":core:stores"))
        }
        getByName("desktopMain").dependencies {
            api(libs.kotlin.test.junit5)
            api(project.dependencies.platform(libs.junit.bom))
            api(libs.junit.jupiter)
            compileOnly(files(tripwireJar))
            // W1-d G6 디코드 덤프기(C§5.2 · G §8-14): 칸을 **선언 타입**으로 읽는다 — JDK 리플렉션은 무부호·널 표기를 못 본다
            // (MirrorDumpProbeTest). 판은 version.ref = "kotlin"(2.4.21)으로 컴파일러와 한 벌. 시험 classpath 전용(앱 산출물 0).
            api(libs.kotlin.reflect)
            // 공용 패치 7: 데스크톱 스냅숏 하네스(…/ui/components/DesktopSnapshots — ImageComposeScene·Skia)를 ui·desktopApp 시험이 같이 쓴다.
            // compileOnly: 실행 때 compose.ui 는 쓰는 쪽(ui·desktopApp) 시험 classpath 가 준다. implementation 이면 testkit 을 쓰는
            // 모든 core·feature 모듈 desktopTest 에 compose.ui(→ jbr-api 1.5.0)가 번져 봉인·오프라인 게이트가 해석에서 빨개진다(int-w1 실측).
            compileOnly(libs.compose.ui)
        }
        getByName("androidMain").dependencies {
            api(libs.kotlin.test.junit)
            api(libs.junit4)
            api(libs.kotlin.reflect) // 같은 덤프기를 Android 호스트 시험(Robolectric)에서도 쓸 수 있게.
        }
        getByName("desktopTest").dependencies {
            compileOnly(files(tripwireJar))
            // 봉인 실험(C-X6 POST 재전송 · C-X8 OkHttp 경로 트립와이어): 시험 쪽에만, localhost 만 쓴다.
            implementation(libs.okhttp)
            implementation(libs.okhttp.mockwebserver3)
            implementation(libs.ktor.client.okhttp)
            // C-X7 mutableStateOf 스토어 견본 · A-X6 데스크톱 오프스크린 렌더
            implementation(libs.compose.runtime)
            implementation(libs.compose.foundation)
            implementation(libs.compose.ui)
            implementation(compose.desktop.currentOs)
            implementation(libs.compose.ui.test)
            implementation(libs.roborazzi.compose.desktop)
        }
        getByName("androidHostTest").dependencies {
            // A-X5 Robolectric + Roborazzi 오프라인 기록→대조
            implementation(libs.compose.runtime)
            implementation(libs.compose.foundation)
            implementation(libs.compose.ui)
            implementation(libs.roborazzi)
            implementation(libs.roborazzi.compose)
            implementation(libs.roborazzi.junit.rule)
            implementation(libs.androidx.compose.ui.test.junit4)
            implementation(libs.androidx.compose.ui.test.manifest)
            implementation(libs.androidx.test.core)
        }
    }
}
