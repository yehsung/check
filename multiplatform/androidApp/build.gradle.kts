// 원본: 없음 — Android 앱 모듈 빌드 파일(조정자 몫). W2-a 패치 0001: 판돈 대결 BuildConfig 깃발. W6-a 패치 01: 출시 조립(R8 · 업로드 키 · 빌드 도장).
// androidApp — 단일 Activity·탭 셸·화면·FCM·Glance·Keystore(W1-g·W3·W4·W5-c·W6-a).
// feature/desktop 에 의존하지 않는다(C§3.1 — 구조 시험이 이 파일을 읽어 단언한다).
// Firebase 는 google-services 플러그인 없이 FirebaseOptions 를 손수 초기화한다(A§6-1) — 저장소에 google-services.json 이 없다.
// 운영 구성은 release 변형에서만 Gradle 속성으로 들어간다(§8-5, aingcheck.android-app).
plugins {
    id("aingcheck.android-app")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("io.github.takahirom.roborazzi")
}

// ---------- 출시 조립(W6-a · E§11 · A§6-1) — 값은 전부 밖에서 온다. 출시 입구는 multiplatform/scripts/release-android.sh 하나다 ----------
// 판돈 대결 빌드 깃발(G §8-17 #1 · W2-a 앱 구성 계약 `AppConfig.duelsEnabled` 의 Android 원천). **기본 꺼짐.**
// debug·stub 은 언제나 false 다(아래 defaultConfig — DuelsBuildFlagTest 가 잰다). release 만 Gradle 속성 aingcheck.release.duelsEnabled
// (true|false, 없으면 false)를 읽는다 — 출시 스크립트의 `--duels on|off`(기본 off)가 넣고, 산출물 dex 에서 BuildConfig 값을 다시 읽어 대조한다.
// 판돈 e2e 를 통과한 빌드 N 에서만 켜고, 그 N 으로 서버 ⑤ 를 연다(서버 변경 없음 — 로비 me.capable 안 씀). 꺼진 빌드는 내부 트랙에만 오른다.
// **켜는 일은 두 곳이 맞아야 한다(의도된 이중 확인)**: 커밋된 version.properties 의 androidDuelsFromBuild=N(N ≤ androidVersionCode)과
//   출시 인자 --duels on. 한쪽만 있으면 여기(Gradle)와 출시 스크립트 preflight 가 둘 다 멈춘다 — 출시 인자 하나로 켜지지 않고, 켠 사실이 커밋에 남는다.
// 스토어는 BuildConfig 를 직접 읽지 않는다 — AppContainer.appConfig → SessionContext.appConfig.
val releaseDuelsEnabled: Boolean = when (val v = providers.gradleProperty("aingcheck.release.duelsEnabled").orNull?.trim()) {
    null, "", "false" -> false
    "true" -> true
    else -> throw GradleException("aingcheck.release.duelsEnabled 는 true 또는 false 다('$v')")
}
if (releaseDuelsEnabled) {
    val vp = aingcheckVersionProperties()
    val from = vp.getProperty("androidDuelsFromBuild")?.trim()?.toIntOrNull()
    val code = vp.required("androidVersionCode").toInt()
    if (from == null || code < from) {
        throw GradleException(
            "aingcheck.release.duelsEnabled=true 는 커밋된 version.properties 의 androidDuelsFromBuild=N(≤ androidVersionCode)과 함께만 받는다" +
                "(지금 androidDuelsFromBuild=${vp.getProperty("androidDuelsFromBuild") ?: "없음"} · androidVersionCode=$code)",
        )
    }
}
// 빌드 도장(기억 binary-verification-needs-build-time): release 의 BuildConfig.RELEASE_STAMP 에 빌드 시각·커밋·판 번호·판돈 깃발을 싣는다.
// proguard-rules.pro 가 이 필드를 지키므로 산출물 dex 에 글자 그대로 남는다 — 출시 스크립트가 영수증과 대조한다.
// 둘 다 없으면(게이트·CI 의 assembleRelease) 빈 글자다(빌드마다 다시 컴파일되지 않게). 하나만 있으면 멈춘다.
val releaseBuildTime: String? = providers.gradleProperty("aingcheck.release.buildTime").orNull?.trim()?.takeIf { it.isNotEmpty() }
val releaseGitSha: String? = providers.gradleProperty("aingcheck.release.gitSha").orNull?.trim()?.takeIf { it.isNotEmpty() }
if ((releaseBuildTime == null) != (releaseGitSha == null)) {
    throw GradleException("aingcheck.release.buildTime 과 aingcheck.release.gitSha 는 함께 넣는다")
}
if (releaseBuildTime != null && !Regex("^[0-9]{8}T[0-9]{6}Z$").matches(releaseBuildTime)) {
    throw GradleException("aingcheck.release.buildTime 은 UTC yyyyMMdd'T'HHmmss'Z' 다('$releaseBuildTime')")
}
if (releaseGitSha != null && !Regex("^[0-9a-f]{7,40}(-dirty)?$").matches(releaseGitSha)) {
    throw GradleException("aingcheck.release.gitSha 는 소문자 16진 7~40자(+ -dirty)다('$releaseGitSha')")
}
// 업로드 키(A§6-1 · E§11 Play App Signing): 경로·비밀번호는 저장소 밖에서 **환경 변수로만** 들어온다(argv·gradle.properties 금지).
// 출시 스크립트가 키체인 항목(/usr/bin/security) 또는 환경 변수에서 받아 넣는다. 없으면 release 는 서명하지 않는다(게이트·CI).
val uploadStoreFile: String? = System.getenv("AINGCHECK_UPLOAD_STORE_FILE")?.takeIf { it.isNotBlank() }

android {
    buildFeatures {
        buildConfig = true
    }
    defaultConfig {
        // 무대 묶음 예산 — 정의는 한 곳(scripts/bake-aing/config.json bundles.androidDefault.budget). 기기 시험이 설치된 APK 를 이 값으로 잰다.
        buildConfigField(
            "int", "STAGE_BUNDLE_BUDGET",
            (((groovy.json.JsonSlurper().parse(rootDir.resolve("scripts/bake-aing/config.json")) as Map<*, *>)["bundles"] as Map<*, *>)["androidDefault"] as Map<*, *>)["budget"].toString(),
        )
        buildConfigField("boolean", "DUELS_ENABLED", "false")
        buildConfigField("String", "RELEASE_STAMP", "\"\"")
    }
    signingConfigs {
        if (uploadStoreFile != null) {
            create("upload") {
                val storePass = System.getenv("AINGCHECK_UPLOAD_STORE_PASSWORD")?.takeIf { it.isNotEmpty() }
                    ?: throw GradleException("AINGCHECK_UPLOAD_STORE_FILE 가 있는데 AINGCHECK_UPLOAD_STORE_PASSWORD 가 없다")
                val store = file(uploadStoreFile)
                if (!store.isFile) throw GradleException("업로드 키 파일이 없다(AINGCHECK_UPLOAD_STORE_FILE)")
                storeFile = store
                storePassword = storePass
                keyAlias = System.getenv("AINGCHECK_UPLOAD_KEY_ALIAS")?.takeIf { it.isNotBlank() } ?: "upload"
                keyPassword = System.getenv("AINGCHECK_UPLOAD_KEY_PASSWORD")?.takeIf { it.isNotEmpty() } ?: storePass
            }
        }
    }
    buildTypes {
        getByName("release") {
            // R8 전체 모드(AGP 9 기본) + 리소스 줄이기. 규칙은 W6-a proguard-rules.pro(Ktor·kotlinx.serialization·Firebase 메시징·빌드 도장).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("boolean", "DUELS_ENABLED", releaseDuelsEnabled.toString())
            val stamp = if (releaseBuildTime == null) "" else
                "aingcheck-release;build=${defaultConfig.versionCode};version=${defaultConfig.versionName};" +
                    "time=$releaseBuildTime;sha=$releaseGitSha;duels=${if (releaseDuelsEnabled) 1 else 0}"
            buildConfigField("String", "RELEASE_STAMP", "\"$stamp\"")
            signingConfigs.findByName("upload")?.let { signingConfig = it }
        }
    }
}

// W5-c 살아 있는 미리보기(결정 #2 · G §8-12 · F §8 B): 구운 아잉이 **Android 기본 묶음**을 앱 자산으로 싣는다(git 사본 0).
// 고르는 규칙은 굽기 설정 한 곳 — scripts/bake-aing/config.json `bundles.androidDefault`(assets = 굽기 뿌리 기준 글롭, repo = 저장소 뿌리 기준 글롭) —
// 을 그대로 읽는다: 굽기 파일은 assets/aing-bake/<굽기 상대 경로>, 후광 원본 PNG 는 assets/aing-bake/halo/<이름>.
// 예산(L 단 ≤ 4MB · 묶음 ≤ config.json budget — 8차 spin: S 스핀 행을 더해 6.9MB)은 시험이 잰다(screens/stage StageBundleTest · 기기 StageDeviceTest 가 설치된 APK 를 읽는다).
// 기기 시험(T7 부분집합 · 맥 렌더 비교 PNG): 맥 골든(golden.json + 무대 리액션 넷)을 시험 APK Java 자원으로, 판정 규칙은 character 의 parity/ 한 벌을 소스로.
abstract class AingcheckStageBakeFiles : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val bakeFiles: ConfigurableFileCollection

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NAME_ONLY)
    abstract val haloFiles: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val root = outputDir.get().asFile.resolve("aing-bake")
        outputDir.get().asFile.deleteRecursively()
        bakeFiles.asFileTree.visit { if (!isDirectory) copyTo(relativePath.getFile(root)) }
        for (f in haloFiles.files) f.copyTo(root.resolve("halo/${f.name}"), overwrite = true)
    }
}

val stageBakeRoot = rootDir.resolve("assets/aing-bake")
@Suppress("UNCHECKED_CAST")
val stageBundle = ((groovy.json.JsonSlurper().parse(rootDir.resolve("scripts/bake-aing/config.json")) as Map<String, Any?>)["bundles"] as Map<String, Any?>)["androidDefault"] as Map<String, Any?>
val stageBakeAssets = tasks.register<AingcheckStageBakeFiles>("aingcheckStageBakeAssets") {
    description = "구운 아잉이 Android 기본 묶음(config.json bundles.androidDefault)과 후광 원본 PNG 를 앱 자산 폴더로 모은다(W5-c)."
    bakeFiles.from(fileTree(stageBakeRoot) { include(stageBundle["assets"] as List<String>) })
    for (glob in stageBundle["repo"] as List<String>) {
        val f = rootDir.parentFile.resolve(glob)
        haloFiles.from(fileTree(f.parentFile) { include(f.name) })
    }
    outputDir.set(layout.buildDirectory.dir("generated/aingcheck/stageBake/assets"))
}
val stageDeviceTestGoldens = tasks.register<AingcheckStageBakeFiles>("aingcheckStageDeviceTestGoldens") {
    description = "기기 시험이 맞댈 맥 골든(무대 리액션 idle · blink · hit · 공개 한 바퀴 commuteStart)과 판정 무리를 가르는 S 칸 표를 시험 APK 자원 폴더로 모은다(W5-c)."
    bakeFiles.from(
        fileTree(stageBakeRoot) {
            include("golden/golden.json", "golden/*-idle-*.webp", "golden/*-blink-*.webp", "golden/*-hit-*.webp", "golden/*-commuteStart-*.webp", "*/cells-S.json")
        },
    )
    outputDir.set(layout.buildDirectory.dir("generated/aingcheck/stageBake/androidTestResources"))
}
androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(stageBakeAssets, AingcheckStageBakeFiles::outputDir)
        variant.androidTest?.sources?.resources?.addGeneratedSourceDirectory(stageDeviceTestGoldens, AingcheckStageBakeFiles::outputDir)
        variant.androidTest?.sources?.kotlin?.addStaticSourceDirectory(
            rootDir.resolve("character/src/desktopTest/kotlin/com/yehsung/aingcheck/character/parity").path,
        )
    }
}

dependencies {
    implementation(project(":feature:phone"))
    implementation(project(":ui"))
    implementation(project(":character"))

    // 실서버 엔진은 앱 조립 지점에서만(A§4-1 ①). retryOnConnectionFailure(false) 로 만든다(C-X6).
    implementation(libs.ktor.client.okhttp)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.coroutines.android)

    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.glance.material3)
    // WorkManager 고정(G §8-12, W0-f A-X17 실측): Glance 1.2.0 → work-runtime 2.7.1 → room-runtime 2.2.5 의 consumer keep 규칙
    // `-keep class * extends androidx.room.RoomDatabase` 에 <init>() 가 없어, R8 전체 모드가 WorkDatabase 생성자를 지운다 →
    // 릴리스 판이 시작하자마자 "Failed to create an instance of androidx.work.impl.WorkDatabase" 로 죽는다. 디버그는 멀쩡하다.
    implementation(libs.androidx.work.runtime)
    implementation(libs.jetbrains.navigation.compose)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi.junit.rule)
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.androidx.test.core)
    // HttpEngineFactoryTest(호스트): 끊긴 재사용 연결 재현으로 POST 재전송 0 을 잰다(C-X6, G §8-12).
    testImplementation(libs.okhttp.mockwebserver3)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    androidTestImplementation(project(":testkit"))
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.kotlin.test.junit)
}
