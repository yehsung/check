// core/stores — 공용 스토어(메시지·지금·순위·캐릭터·나·오목·체스·테트리스·미니게임·게임).
// Swift @Observable 의 var → Compose runtime mutableStateOf(C§2.4). 컴파일러 플러그인 없이 런타임만 쓴다.
plugins {
    id("aingcheck.kmp-library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:session"))
            api(project(":core:rules"))
            api(libs.compose.runtime)
        }
        commonTest.dependencies {
            implementation(libs.ktor.client.mock)
        }
        getByName("desktopTest").dependencies {
            implementation(libs.kotlin.reflect)
        }
    }
}
