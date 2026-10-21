// core/rules — 순수 규칙(테트리스·미니게임·렌주·체스·AI·판돈·뽑기·주간·미션·기록·할 일·글자·캐릭터·리밋·토큰·표기).
// foundation·wire 에만 기댄다(G §2-0). 게임 엔진은 시계를 읽지 않는다(A§3-3).
plugins {
    id("aingcheck.kmp-library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    sourceSets {
        commonMain.dependencies {
            api(project(":core:foundation"))
            api(project(":core:wire"))
        }
    }
}
