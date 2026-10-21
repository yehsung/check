// desktopApp — 트레이·플라이아웃·창·platform/windows(JNA)·overlay·packaging(W1-f·W3-c·W3-d·W4·W5-b·W6-b).
// 에이전트는 :desktopApp:run 을 하지 않는다(창). 시험은 java.awt.headless=true 아래에서만 돈다.
// 운영 구성은 Gradle 속성 → 생성 소스 한 파일(ProdConfig.kt), 기본 .invalid(§8-5, aingcheck.desktop-app).
plugins {
    id("aingcheck.desktop-app")
    id("org.jetbrains.kotlin.plugin.serialization")
}

dependencies {
    implementation(project(":feature:desktop"))
    implementation(project(":ui"))
    implementation(project(":character"))
    implementation(compose.desktop.currentOs)
    implementation(libs.kotlinx.coroutines.swing)

    // 실서버 엔진은 앱 조립 지점에서만(A§4-1 ①). retryOnConnectionFailure(false) 로 만든다(C-X6).
    implementation(libs.ktor.client.okhttp)
    implementation(libs.okhttp)

    // Windows OS 층(D§2-4): jna + jna-platform. DLL 은 패키지에 넣고 jna.nounpack=true(W1-f).
    implementation(libs.jna)
    implementation(libs.jna.platform)
    // 비밀 아닌 설정(A§3-4): DataStore Preferences(파일 경로 주입). java.util.prefs 금지(구조 시험).
    implementation(libs.androidx.datastore.preferences.core)

    testImplementation(libs.compose.ui.test)
    testImplementation(libs.roborazzi.compose.desktop)
    // HttpEngineFactoryTest: 끊긴 재사용 연결을 localhost 에서 재현해 POST 재전송 0 을 잰다(C-X6, G §8-12).
    testImplementation(libs.okhttp.mockwebserver3)
}

// W1-f(D§2-4, W0-e 관측): jnidispatch.dll 을 앱 자원 폴더에 실어 %TEMP%\jna--* 에 풀지 않게 한다.
// Main 의 JnaBootstrap 이 compose.application.resources.dir 에서 이 파일을 찾을 때만 jna.boot.library.path·jna.nounpack·jna.nosys 를 켠다
// (파일이 없으면 아무것도 바꾸지 않는다 — 개발 실행·시험). Compose 는 appResourcesRootDir 의 <os>-<arch> 몫을 그 폴더로 싣는다.
val aingcheckJnaJar = configurations.create("aingcheckJnaJar") {
    isCanBeConsumed = false
    isCanBeResolved = true
    isTransitive = false
}
dependencies { add(aingcheckJnaJar.name, libs.jna) }
val aingcheckJnaAppResources = tasks.register<Sync>("aingcheckJnaAppResources") {
    description = "jna jar 의 Windows jnidispatch.dll 을 앱 자원 폴더(windows-x64·windows-arm64)로 꺼낸다."
    val jar = aingcheckJnaJar
    into(layout.buildDirectory.dir("aingcheck/app-resources"))
    from({ zipTree(jar.singleFile) }) {
        include("com/sun/jna/win32-x86-64/jnidispatch.dll")
        eachFile { path = "windows-x64/$name" }
    }
    from({ zipTree(jar.singleFile) }) {
        include("com/sun/jna/win32-aarch64/jnidispatch.dll")
        eachFile { path = "windows-arm64/$name" }
    }
    includeEmptyDirs = false
}
compose.desktop.application.nativeDistributions.appResourcesRootDir.set(
    aingcheckJnaAppResources.map { layout.buildDirectory.dir("aingcheck/app-resources").get() },
)
