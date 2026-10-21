// ui — Compose 공용: theme·components·icons·fonts(W1-e) · screens/*(W3-a·b, §8-4) · games/*(W4) · shop·gacha·missions·weekly(W4-c).
// 스냅숏: Android 는 Robolectric + Roborazzi(호스트 시험), 데스크톱은 오프스크린 렌더(창 없음, java.awt.headless=true).
plugins {
    id("aingcheck.kmp-library")
    id("aingcheck.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("io.github.takahirom.roborazzi")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:stores"))
            api(libs.compose.runtime)
            api(libs.compose.foundation)
            api(libs.compose.ui)
            api(libs.compose.material3)
            api(libs.compose.components.resources)
            api(libs.jetbrains.lifecycle.runtime.compose)
        }
        getByName("desktopTest").dependencies {
            implementation(compose.desktop.currentOs)
            implementation(libs.compose.ui.test)
            implementation(libs.roborazzi.compose.desktop)
        }
        getByName("androidHostTest").dependencies {
            implementation(libs.roborazzi)
            implementation(libs.roborazzi.compose)
            implementation(libs.roborazzi.junit.rule)
            implementation(libs.androidx.compose.ui.test.junit4)
            implementation(libs.androidx.compose.ui.test.manifest)
            implementation(libs.androidx.test.core)
        }
    }
}

compose.resources {
    packageOfResClass = "com.yehsung.aingcheck.ui.resources"
    publicResClass = true
}
