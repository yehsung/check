// core/net — SupabaseWorkService(Ktor), 오류 분류, Auth, RPC 래퍼, 실시간 프레임·링·전송자(W1-d).
// 실서버 엔진(OkHttp)은 main 에 두지 않는다 — 앱 모듈이 주입한다(A§4-1 ①, 구조 시험).
// 시험 쪽에만 OkHttp + mockwebserver3: localhost Phoenix 흉내 WebSocket 왕복(A-X10, 봉인 아래).
plugins {
    id("aingcheck.kmp-library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:wire"))
            api(libs.ktor.client.core)
            api(libs.ktor.client.websockets)
        }
        commonTest.dependencies {
            implementation(libs.ktor.client.mock)
        }
        getByName("desktopTest").dependencies {
            implementation(libs.ktor.client.okhttp)
            implementation(libs.okhttp)
            implementation(libs.okhttp.mockwebserver3)
            implementation(libs.kotlin.reflect)
        }
    }
}
