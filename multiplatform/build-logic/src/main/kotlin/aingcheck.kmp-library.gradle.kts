// KMP 라이브러리(대상 둘: android + jvm("desktop")). JVM+Android 중간 소스셋은 두지 않는다(G §2-0, 공식 미지원).
// AGP 9: KMP 모듈에는 com.android.kotlin.multiplatform.library 를 쓰고, 앱은 별도 모듈이다(A§2-1).

import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("com.android.kotlin.multiplatform.library")
    id("aingcheck.test-seal")
}

val libsCatalog = aingcheckLibs
val isTestkit = path == ":testkit"

kotlin {
    jvmToolchain(21)
    jvm("desktop")
    android {
        namespace = aingcheckPackage()
        compileSdk = AINGCHECK_COMPILE_SDK
        minSdk = AINGCHECK_MIN_SDK
        compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
        withHostTest { isIncludeAndroidResources = true }
    }
    sourceSets {
        getByName("commonTest").dependencies {
            implementation(libsCatalog.lib("kotlin-test"))
            implementation(libsCatalog.lib("kotlinx-coroutines-test"))
            if (!isTestkit) implementation(project(":testkit"))
        }
        getByName("desktopTest").dependencies {
            implementation(libsCatalog.lib("kotlin-test-junit5"))
            implementation(project.dependencies.platform(libsCatalog.lib("junit-bom")))
            implementation(libsCatalog.lib("junit-jupiter"))
            runtimeOnly(libsCatalog.lib("junit-platform-launcher"))
        }
        getByName("androidHostTest").dependencies {
            // Robolectric 은 JUnit4 러너다 → kotlin.test 도 JUnit4 판, 플랫폼 위에서는 vintage 엔진이 돌린다.
            implementation(libsCatalog.lib("kotlin-test-junit"))
            implementation(libsCatalog.lib("junit4"))
            implementation(libsCatalog.lib("robolectric"))
            implementation(project.dependencies.platform(libsCatalog.lib("junit-bom")))
            runtimeOnly(libsCatalog.lib("junit-vintage-engine"))
            runtimeOnly(libsCatalog.lib("junit-platform-launcher"))
        }
    }
}
