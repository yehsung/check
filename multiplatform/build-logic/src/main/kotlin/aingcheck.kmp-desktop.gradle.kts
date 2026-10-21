// 데스크톱 전용 KMP 모듈(feature/desktop). 대상은 jvm("desktop") 하나뿐이다.
// android 대상이 없으므로 androidApp 은 이 모듈에 의존할 수 없다 — 폰 금지 호출을 컴파일 단계에서 막는다(C§3.1).

plugins {
    id("org.jetbrains.kotlin.multiplatform")
    id("aingcheck.test-seal")
}

val libsCatalog = aingcheckLibs

kotlin {
    jvmToolchain(21)
    jvm("desktop")
    sourceSets {
        getByName("commonTest").dependencies {
            implementation(libsCatalog.lib("kotlin-test"))
            implementation(libsCatalog.lib("kotlinx-coroutines-test"))
            implementation(project(":testkit"))
        }
        getByName("desktopTest").dependencies {
            implementation(libsCatalog.lib("kotlin-test-junit5"))
            implementation(project.dependencies.platform(libsCatalog.lib("junit-bom")))
            implementation(libsCatalog.lib("junit-jupiter"))
            runtimeOnly(libsCatalog.lib("junit-platform-launcher"))
        }
    }
}
