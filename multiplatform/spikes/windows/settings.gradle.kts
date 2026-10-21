// W0-e Windows 탐침 — 자기 완결 빌드. multiplatform/settings.gradle.kts 에 넣지 않는다(출시 빌드 제외, G §8-3).
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
        google()
    }
}

rootProject.name = "aingcheck-windows-spike"
