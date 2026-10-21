// feature/phone — Android 전용 로직(폰 근무·푸시 경로·폰 실시간·위젯 스냅숏). 판정은 commonMain(JVM 시험이 닿게).
// feature/desktop 과 서로 모른다(C§3.1).
plugins {
    id("aingcheck.kmp-library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:stores"))
        }
        commonTest.dependencies {
            implementation(libs.ktor.client.mock)
        }
    }
}
