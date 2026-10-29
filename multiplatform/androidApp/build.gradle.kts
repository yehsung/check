// 원본: 없음 — Android 앱 모듈 빌드 파일(조정자 몫). W2-a 패치 0001: 판돈 대결 BuildConfig 깃발.
// androidApp — 단일 Activity·탭 셸·화면·FCM·Glance·Keystore(W1-g·W3·W4·W5-c·W6-a).
// feature/desktop 에 의존하지 않는다(C§3.1 — 구조 시험이 이 파일을 읽어 단언한다).
// Firebase 는 google-services 플러그인 없이 FirebaseOptions 를 손수 초기화한다(A§6-1) — 저장소에 google-services.json 이 없다.
// 운영 구성은 release 변형에서만 Gradle 속성으로 들어간다(§8-5, aingcheck.android-app).
plugins {
    id("aingcheck.android-app")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("io.github.takahirom.roborazzi")
}

// 판돈 대결 빌드 깃발(G §8-17 #1 · W2-a 앱 구성 계약 `AppConfig.duelsEnabled` 의 Android 원천). **기본 꺼짐.**
// 판돈 e2e 를 통과한 빌드 N 에서만 켜고, 그 N 으로 서버 ⑤ 를 연다(서버 변경 없음 — 로비 me.capable 안 씀).
// **켜는 일은 두 곳을 함께 바꾼다**: 아래 "false" → "true" 와 DuelsBuildFlagTest 의 THIS_BUILD_DUELS_ENABLED → true.
//   한쪽만 바뀌면 그 시험이 게이트를 막는다 — 실수로 켠 빌드가 트랙에 오르지 않게 하는 의도된 이중 확인이다.
// 꺼진 빌드는 내부 트랙에만 오른다. 스토어는 BuildConfig 를 직접 읽지 않는다 — AppContainer.appConfig → SessionContext.appConfig.
android {
    buildFeatures {
        buildConfig = true
    }
    defaultConfig {
        buildConfigField("boolean", "DUELS_ENABLED", "false")
    }
}

// W5-c 살아 있는 미리보기(결정 #2 · G §8-12 · F §8 B): 구운 아잉이 **Android 기본 묶음**을 앱 자산으로 싣는다(git 사본 0).
// 고르는 규칙은 굽기 설정 한 곳 — scripts/bake-aing/config.json `bundles.androidDefault`(assets = 굽기 뿌리 기준 글롭, repo = 저장소 뿌리 기준 글롭) —
// 을 그대로 읽는다: 굽기 파일은 assets/aing-bake/<굽기 상대 경로>, 후광 원본 PNG 는 assets/aing-bake/halo/<이름>.
// 예산(L 단 ≤ 4MB · 묶음 ≤ 4.5MB)은 시험이 잰다(screens/stage StageBundleTest · 기기 StageDeviceTest 가 설치된 APK 를 읽는다).
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
    description = "기기 시험이 맞댈 맥 골든(무대 리액션 idle · blink · hit · greeting)과 판정 무리를 가르는 S 칸 표를 시험 APK 자원 폴더로 모은다(W5-c)."
    bakeFiles.from(
        fileTree(stageBakeRoot) {
            include("golden/golden.json", "golden/*-idle-*.webp", "golden/*-blink-*.webp", "golden/*-hit-*.webp", "golden/*-greeting-*.webp", "*/cells-S.json")
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
