// Android 앱 모듈. AGP 9 는 Kotlin 컴파일을 내장하므로 kotlin-android 플러그인을 걸지 않는다(A§2-1).
//
// 운영 구성(§8-5)은 release 조립 지점에서만 들어간다: release 변형만 Gradle 속성을 읽고,
// debug 변형은 속성이 있어도 언제나 `.invalid` 다. 생성 파일은 변형마다 하나(ProdConfig.kt).

import com.android.build.api.variant.ApplicationAndroidComponentsExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("aingcheck.test-seal")
}

val libsCatalog = aingcheckLibs
val versions = aingcheckVersionProperties()
val appPackage = aingcheckPackage()

android {
    namespace = appPackage
    compileSdk = AINGCHECK_COMPILE_SDK
    defaultConfig {
        // 영구 식별자: Play 에 한 번 올리면 바꿀 수 없다(A§2-2, §5-4).
        applicationId = "com.yehsung.aingcheck"
        minSdk = AINGCHECK_MIN_SDK
        targetSdk = AINGCHECK_TARGET_SDK
        versionCode = versions.required("androidVersionCode").toInt()
        versionName = versions.required("androidVersionName")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    buildFeatures {
        compose = true
    }
    buildTypes {
        // stub(E§4.6): 데모 픽스처로 도는 시험·스크린샷 변형. debug 설정을 물려받고 운영 구성·Firebase 는 언제나 빈 값이다
        // (isRelease 가 거짓). 소스셋 src/stub(W1-g)이 CurrentVariant = STUB 을 준다.
        create("stub") {
            initWith(getByName("debug"))
            matchingFallbacks += listOf("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
    packaging {
        resources {
            excludes += setOf("META-INF/LICENSE*.md", "META-INF/AL2.0", "META-INF/LGPL2.1")
        }
    }
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

extensions.configure<ApplicationAndroidComponentsExtension>("androidComponents") {
    onVariants { variant ->
        val isRelease = variant.buildType == "release"
        val values = project.aingcheckProdConfig(releaseAssembly = isRelease)
        val cap = variant.name.replaceFirstChar { it.uppercase() }
        val prodTask = project.tasks.register<GenerateKotlinConstants>("generate${cap}ProdConfig") {
            packageName.set("$appPackage.generated")
            objectName.set(PROD_CONFIG_OBJECT)
            header.set("운영 구성(§8-5). release 변형만 Gradle 속성 aingcheck.prod.* 를 읽는다. 기본 .invalid")
            constants.put("SUPABASE_URL", values.supabaseUrl)
            constants.put("SUPABASE_ANON_KEY", values.supabaseAnonKey)
            // Firebase(E§6.6): release 만 속성을 읽는다. debug·stub 은 빈 값 — 앱의 FirebaseSettings.parse 가 null 로 읽어 초기화하지 않는다.
            constants.put("FIREBASE_APP_ID", values.firebaseAppId)
            constants.put("FIREBASE_PROJECT_ID", values.firebaseProjectId)
            constants.put("FIREBASE_SENDER_ID", values.firebaseSenderId)
            constants.put("FIREBASE_API_KEY", values.firebaseApiKey)
            outputDir.set(project.layout.buildDirectory.dir("generated/aingcheck/prodConfig/${variant.name}"))
        }
        val identityTask = project.tasks.register<GenerateKotlinConstants>("generate${cap}BuildIdentity") {
            packageName.set("$appPackage.generated")
            objectName.set(BUILD_IDENTITY_OBJECT)
            header.set("K4 ClientIdentity 의 원천(version.properties). 플랫폼 android")
            constants.put("PLATFORM", "android")
            constants.put("BUILD", versions.required("androidVersionCode"))
            constants.put("VERSION", versions.required("androidVersionName"))
            outputDir.set(project.layout.buildDirectory.dir("generated/aingcheck/buildIdentity/${variant.name}"))
        }
        variant.sources.kotlin?.addGeneratedSourceDirectory(prodTask, GenerateKotlinConstants::outputDir)
        variant.sources.kotlin?.addGeneratedSourceDirectory(identityTask, GenerateKotlinConstants::outputDir)
    }
}

dependencies {
    "testImplementation"(project(":testkit"))
    "testImplementation"(libsCatalog.lib("kotlin-test-junit"))
    "testImplementation"(libsCatalog.lib("junit4"))
    "testImplementation"(libsCatalog.lib("robolectric"))
    "testImplementation"(platform(libsCatalog.lib("junit-bom")))
    "testRuntimeOnly"(libsCatalog.lib("junit-vintage-engine"))
    "testRuntimeOnly"(libsCatalog.lib("junit-platform-launcher"))
    "testImplementation"(libsCatalog.lib("kotlinx-coroutines-test"))
}
