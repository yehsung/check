// core/wire — 요청·응답 타입, lossy 직렬화기(W1-d). G6 디코드 덤프는 kotlin-reflect 로 정규 덤프를 만든다(C§5.2).
plugins {
    id("aingcheck.kmp-library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:foundation"))
            api(libs.kotlinx.serialization.json)
        }
        getByName("desktopTest").dependencies {
            implementation(libs.kotlin.reflect)
        }
    }
}
