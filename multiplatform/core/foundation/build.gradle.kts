// core/foundation — 시계·저장소·금고·기기 신원 인터페이스(K3), Json, KST 달력, 유니코드, SplitMix64(rng/ 는 W0-b).
// 모든 모듈이 기대는 바닥이라 바깥 의존은 kotlinx 셋뿐이다.
plugins {
    id("aingcheck.kmp-library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(libs.kotlinx.coroutines.core)
            api(libs.kotlinx.serialization.json)
            api(libs.kotlinx.datetime)
        }
    }
}
