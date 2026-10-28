// character — 구운 아잉이·스프라이트 재생기(W5-a, F§5). 매니페스트·프레임 시계는 core/rules/character(W1-c)를 import 한다(§8-1).
// 출력은 Skia 래스터 표면(K10). Windows 는 그 표면을 UpdateLayeredWindow 로 올린다(desktopApp/overlay).
plugins {
    id("aingcheck.kmp-library")
    id("aingcheck.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// W5-a T7 자원: 시험 APK 에 실을 구운 자산 부분집합(S 단 · Android 기본 묶음의 L 단 · 메타 · 트랙 · 골든) + 후광 PNG.
val syncDeviceTestBake = tasks.register<Sync>("aingcheckSyncDeviceTestBake") {
    description = "기기 시험(T7 · F-1)이 읽을 구운 자산과 후광 원본 PNG 를 빌드 폴더 하나로 모은다(git 사본 0)."
    into(layout.buildDirectory.dir("generated/aingcheck/deviceTestBake"))
    from(rootDir.resolve("assets/aing-bake")) {
        include("*.json", "tracks/*.f32", "*/manifest.json", "*/cells-S.json", "*/S-*.webp", "*/cells-L.json", "*/L-*.webp", "golden/*")
        into("aing-bake")
    }
    from(rootDir.parentFile.resolve("Sources/check/Resources")) {
        include("aing_gold-halo*.png", "aing_rainbow-halo*.png")
    }
}

kotlin {
    android {
        // W5-a 완료 ②(G §2-3 T7 · §2-6 F-1): 구운 아잉이 골든 20장과 원근 그리기를 에뮬레이터 ART 에서 소프트웨어 Canvas · HWUI 두 길로 잰다.
        // emu.sh instrumented --task :character:connectedAndroidDeviceTest 로만 돌린다(창 없음 · 봉인).
        withDeviceTest {
            instrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        }
        // Compose 리소스 플러그인이 기기 시험 변형의 자산 복사 작업에 출력 자리를 달려면 Android 자원이 켜져 있어야 한다(ui 와 같은 설정 —
        // 끄면 copyAndroidDeviceTestComposeResourcesToAndroidAssets 가 'outputDirectory 값 없음'으로 멈춘다, 실측).
        androidResources { enable = true }
    }
    sourceSets {
        commonMain.dependencies {
            api(project(":core:rules"))
            api(libs.compose.runtime)
            api(libs.compose.ui)
            api(libs.compose.foundation)
            api(libs.compose.components.resources)
        }
        getByName("desktopTest").dependencies {
            implementation(compose.desktop.currentOs)
            implementation(libs.compose.ui.test)
        }
        getByName("androidHostTest").dependencies {
            implementation(libs.androidx.compose.ui.test.junit4)
            implementation(libs.androidx.compose.ui.test.manifest)
            implementation(libs.androidx.test.core)
        }
        getByName("androidDeviceTest") {
            // 판정 규칙은 데스크톱 T3 와 한 벌 — 순수 Kotlin parity/ 폴더(java.io 없음)를 소스로 싣는다.
            kotlin.srcDir("src/desktopTest/kotlin/com/yehsung/aingcheck/character/parity")
            // 기기는 저장소를 못 읽는다: 구운 자산(S · L 단 · 메타 · 트랙 · 골든)과 후광 원본 PNG 를 시험 APK 의 Java 자원으로 싣는다
            // (빌드 폴더로 모으기만 — git 사본 0). 저장소의 `assets` 폴더를 자원 뿌리로 바로 주면 Android 자산으로도 한 벌 더 실린다(실측).
            resources.srcDir(syncDeviceTestBake)
            dependencies {
                implementation(libs.kotlin.test.junit)
                implementation(libs.androidx.test.runner)
            }
        }
    }
}

compose.resources {
    packageOfResClass = "com.yehsung.aingcheck.character.resources"
}
