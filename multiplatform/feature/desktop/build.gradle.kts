// feature/desktop — Windows 전용 로직 desktop/{work,poke,ultra,realtime,tokens,ailimits}(W2-g·W2-h).
// 대상은 jvm("desktop") 하나 — androidApp 은 이 모듈을 볼 수 없다(폰 금지 호출을 컴파일 단계에서 막는다, C§3.1).
// sqlite-jdbc: 안티그래비티 토큰 집계(W2-h, D-E27 통과 시). 임시 폴더에 DLL 을 풀지 않는 설정은 W2-h 가 확인한다(§8-7).
plugins {
    id("aingcheck.kmp-desktop")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            // 2차(int-w0): 갈래가 보는 공용 층을 드러내 적는다(stores 가 이미 api 로 싣지만, 한 층이 빠져도 여기서 보이게).
            api(project(":core:stores"))
            api(project(":core:session"))
            api(project(":core:net"))
            api(project(":core:wire"))
            api(project(":core:rules"))
        }
        getByName("desktopMain").dependencies {
            implementation(libs.sqlite.jdbc)
        }
        commonTest.dependencies {
            implementation(libs.ktor.client.mock)
        }
        getByName("desktopTest").dependencies {
            implementation(libs.kotlin.reflect)
            // 2차(int-w0): 근무·찌르기·토큰 갈래 시험(가짜 시계·runTest·testkit 골든/봉인). commonTest 에도 있지만 desktopTest 에 박는다.
            implementation(project(":testkit"))
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}
