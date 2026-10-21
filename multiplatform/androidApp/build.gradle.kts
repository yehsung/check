// androidApp — 단일 Activity·탭 셸·화면·FCM·Glance·Keystore(W1-g·W3·W4·W5-c·W6-a).
// feature/desktop 에 의존하지 않는다(C§3.1 — 구조 시험이 이 파일을 읽어 단언한다).
// Firebase 는 google-services 플러그인 없이 FirebaseOptions 를 손수 초기화한다(A§6-1) — 저장소에 google-services.json 이 없다.
// 운영 구성은 release 변형에서만 Gradle 속성으로 들어간다(§8-5, aingcheck.android-app).
plugins {
    id("aingcheck.android-app")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("io.github.takahirom.roborazzi")
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
    implementation(libs.jetbrains.navigation.compose)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(libs.roborazzi.junit.rule)
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.androidx.test.core)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    androidTestImplementation(project(":testkit"))
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    androidTestImplementation(libs.kotlin.test.junit)
}
