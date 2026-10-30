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
    // W5-b4 P2: 오버레이 구운 아잉이(OverlaySurfaces → BakedCharacter.defaultRoot = <app-resources>/aing-bake). 골든은 빼고(시험 몫),
    // 후광 원본 PNG 는 aing-bake/halo/ 에(Android 자산과 같은 배치 — git 사본 0).
    from(rootDir.resolve("assets/aing-bake")) {
        include("*.json", "*.webp", "tracks/**", "*/manifest.json", "*/cells-*.json", "*/*.webp")
        exclude("golden/**")
        into("common/aing-bake")
    }
    from(rootDir.parentFile.resolve("Sources/check/Resources")) {
        include("aing_gold-halo*.png", "aing_rainbow-halo*.png")
        into("common/aing-bake/halo")
    }
    includeEmptyDirs = false
}
compose.desktop.application.nativeDistributions.appResourcesRootDir.set(
    aingcheckJnaAppResources.map { layout.buildDirectory.dir("aingcheck/app-resources").get() },
)

// W-13 #7 · W-12(Store 업데이트 목적지): 생성 상수 STORE_PRODUCT_ID — packaging/identity/store.properties 의 productId 가 원천(공개 값).
// 자리표시(__U7_…)이거나 비면 "" → 최소 빌드 미달 화면의 [업데이트] 단추를 숨긴다(AppLinks.updateDestination(WINDOWS)=null 과 같음).
// 값이 있으면 Store 제품 ID 꼴(영숫자 12자, 대문자)만 받는다 — 틀린 값으로 빌드되면 사용자를 엉뚱한 Store 페이지로 보낸다.
val aingcheckStoreProductId: String = run {
    val file = project.file("packaging/identity/store.properties")
    // java.util.Properties 대신 줄 읽기(스크립트 안 `java` 는 JavaPluginExtension 을 가리킨다). 키=값 한 줄, # 주석.
    val raw = if (!file.isFile) "" else file.readLines()
        .map { it.trim() }
        .firstOrNull { !it.startsWith("#") && it.substringBefore('=').trim() == "productId" }
        ?.substringAfter('=')?.trim().orEmpty()
    when {
        raw.isEmpty() || raw.startsWith("__U7_") -> ""
        Regex("^[0-9A-Z]{12}$").matches(raw) -> raw
        else -> throw GradleException("store.properties productId 는 Store 제품 ID(영숫자 대문자 12자)여야 한다: '$raw'")
    }
}
val generateStoreIdentity = tasks.register<GenerateKotlinConstants>("generateStoreIdentity") {
    packageName.set("com.yehsung.aingcheck.desktop.generated")
    objectName.set("StoreIdentity")
    header.set("Store 신원(W-13 #7). packaging/identity/store.properties 의 productId — 자리표시면 빈 값")
    constants.put("STORE_PRODUCT_ID", aingcheckStoreProductId)
    outputDir.set(layout.buildDirectory.dir("generated/aingcheck/storeIdentity/main"))
}
sourceSets.named("main") { kotlin.srcDir(generateStoreIdentity.flatMap { it.outputDir }) }
