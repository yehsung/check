// core/session — 금고 계약, 갱신 조정자, 세션·가입·재설정·삭제, 기기 등록(W2-a).
plugins {
    id("aingcheck.kmp-library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:net"))
        }
        commonTest.dependencies {
            implementation(libs.ktor.client.mock)
        }
    }
}
