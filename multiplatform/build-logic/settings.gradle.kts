// 컨벤션 플러그인 빌드(A§2-1). 버전은 ../gradle/libs.versions.toml 한 곳에서 읽는다.
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "build-logic"
