// 아잉체크 Android·Windows (KMP + Compose Multiplatform). 배치는 G §2-0 + §8-4.
// multiplatform/spikes/** 는 여기 넣지 않는다 — W0-e 가 자기 완결 빌드로 쓴다(출시 빌드 제외).

pluginManagement {
    includeBuild("build-logic")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "aingcheck-multiplatform"

// 의존 방향: foundation ← wire ← net ← session ← stores ← feature.* ← 앱. rules 는 foundation·wire 에만.
include(
    ":core:foundation",
    ":core:wire",
    ":core:net",
    ":core:rules",
    ":core:session",
    ":core:stores",
    ":feature:phone",
    ":feature:desktop",
    ":ui",
    ":character",
    ":testkit",
    ":androidApp",
    ":desktopApp",
)
