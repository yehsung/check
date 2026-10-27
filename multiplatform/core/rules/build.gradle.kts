// core/rules — 순수 규칙(테트리스·미니게임·렌주·체스·AI·판돈·뽑기·주간·미션·기록·할 일·글자·캐릭터·리밋·토큰·표기).
// foundation·wire 에만 기댄다(G §2-0). 게임 엔진은 시계를 읽지 않는다(A§3-3).
plugins {
    id("aingcheck.kmp-library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

kotlin {
    android {
        // W1-c 완료 ②(G §8-16): platformSensitive 골든(글자 · 정렬 · 날짜 · 할 일 · 메시지)을 ART 에서 다시 돈다.
        // emu.sh instrumented --task :core:rules:connectedAndroidDeviceTest 로만 돌린다(창 없음 · 봉인).
        withDeviceTest {
            instrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        }
    }
    sourceSets {
        commonMain.dependencies {
            api(project(":core:foundation"))
            api(project(":core:wire"))
        }
        getByName("androidDeviceTest") {
            // commonTest 에 dependsOn 하지 않는다 — 다른 갈래(W1-a · W1-b …)의 commonTest @Test 는 Golden.load 로 저장소 파일을 읽어 기기에서
            // 못 돈다(세 갈래 병합 사본 실측: 55 중 28 빨강). 소스셋 나무가 다른 dependsOn 은 기본 계층 틀도 끈다(KGP 경고 둘).
            // 대신 W1-c 판정 묶음(…GoldenChecks — @Test 없는 object)만 W1-c 패키지 폴더에서 소스로 싣는다. lanes.yml 이 이 열 패키지를
            // 모든 소스셋에서 W1-c 혼자 갖게 하므로 남의 시험이 섞여 들지 않는다. 기기 시험 본체는 androidDeviceTest 의 RulesGoldenDeviceTest.
            val w1cPackages = listOf("gacha", "weekly", "achievements", "insights", "todo", "text", "character", "ailimit", "token", "format")
            kotlin.srcDirs(w1cPackages.map { "src/commonTest/kotlin/com/yehsung/aingcheck/core/rules/$it" })
            // 골든은 기기가 저장소를 못 읽으므로 시험 APK 의 Java 자원으로 싣는다.
            resources.srcDir(rootProject.layout.projectDirectory.dir("../contract/golden"))
            dependencies {
                implementation(project(":testkit"))
                implementation(libs.kotlin.test.junit)
                implementation(libs.androidx.test.runner)
            }
        }
    }
}
