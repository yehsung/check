// character — 구운 아잉이·스프라이트 재생기(W5-a, F§5). 매니페스트·프레임 시계는 core/rules/character(W1-c)를 import 한다(§8-1).
// 출력은 Skia 래스터 표면(K10). Windows 는 그 표면을 UpdateLayeredWindow 로 올린다(desktopApp/overlay).
plugins {
    id("aingcheck.kmp-library")
    id("aingcheck.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:rules"))
            api(libs.compose.runtime)
            api(libs.compose.ui)
            api(libs.compose.foundation)
            api(libs.compose.components.resources)
        }
        getByName("desktopTest").dependencies {
            implementation(compose.desktop.currentOs)
            implementation(libs.compose.ui.test)
        }
        getByName("androidHostTest").dependencies {
            implementation(libs.androidx.compose.ui.test.junit4)
            implementation(libs.androidx.compose.ui.test.manifest)
            implementation(libs.androidx.test.core)
        }
    }
}

compose.resources {
    packageOfResClass = "com.yehsung.aingcheck.character.resources"
}
