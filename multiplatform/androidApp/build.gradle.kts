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
