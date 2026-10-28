// 원본: 없음 (W0-f ⑤ FCM 토큰 탐침 — 빌드에 들지 않는 측정기 원문, 저장소 밖 스크래치 사본에서 빌드한다)
// Firebase 는 google-services 플러그인 없이 FirebaseOptions 를 손수 초기화한다(A§6-1 · E§6.6 과 같은 길).
// 개발 Firebase(aingcheck-dev) 클라 설정 JSON(콘솔에서 받는 Android 설정 파일)의 경로는 -Pw0f5.firebaseConfig=<경로> 로 받는다.
// 값은 이 빌드의 BuildConfig 에만 들어간다(스크래치 — 저장소·로그에 적지 않는다).
import groovy.json.JsonSlurper

plugins { id("com.android.application") }

val cfgPath = providers.gradleProperty("w0f5.firebaseConfig").orNull
    ?: error("-Pw0f5.firebaseConfig=<Firebase 클라 설정 JSON 경로> 가 필요하다")
@Suppress("UNCHECKED_CAST")
val cfg = JsonSlurper().parse(file(cfgPath)) as Map<String, Any?>
@Suppress("UNCHECKED_CAST")
val projectInfo = cfg["project_info"] as Map<String, Any?>
@Suppress("UNCHECKED_CAST")
val client = (cfg["client"] as List<Map<String, Any?>>).firstOrNull { c ->
    val ci = c["client_info"] as Map<String, Any?>
    val aci = ci["android_client_info"] as Map<String, Any?>
    aci["package_name"] == "com.yehsung.aingcheck"
} ?: error("Firebase 클라 설정 JSON 에 com.yehsung.aingcheck 클라가 없다")
@Suppress("UNCHECKED_CAST")
val appId = (client["client_info"] as Map<String, Any?>)["mobilesdk_app_id"] as String
@Suppress("UNCHECKED_CAST")
val apiKey = ((client["api_key"] as List<Map<String, Any?>>).first())["current_key"] as String
val projectId = projectInfo["project_id"] as String
val senderId = projectInfo["project_number"] as String
check(projectId == "aingcheck-dev") { "개발 프로젝트(aingcheck-dev)가 아니다 — 운영 설정으로 실험하지 않는다(§8-8)" }

android {
    namespace = "com.yehsung.aingcheck.w0f5"
    compileSdk = 37
    defaultConfig {
        applicationId = "com.yehsung.aingcheck"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "w0f5"
        buildConfigField("String", "FB_APP_ID", "\"$appId\"")
        buildConfigField("String", "FB_API_KEY", "\"$apiKey\"")
        buildConfigField("String", "FB_PROJECT_ID", "\"$projectId\"")
        buildConfigField("String", "FB_SENDER_ID", "\"$senderId\"")
    }
    buildFeatures { buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    lint { checkReleaseBuilds = false; abortOnError = false }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:35.0.2"))
    implementation("com.google.firebase:firebase-messaging")
    // 앱(androidApp)이 실제로 푸는 판으로 올린다(캐시에 있는 판 — 앱의 의존 그래프와 같게)
    implementation("androidx.core:core:1.19.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime:2.11.0")
    implementation("androidx.lifecycle:lifecycle-common:2.11.0")
    implementation("androidx.arch.core:core-common:2.2.0")
    implementation("androidx.datastore:datastore-core:1.2.1")
    implementation("androidx.datastore:datastore-preferences:1.2.1")
}
