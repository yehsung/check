// ui — Compose 공용: theme·components·icons·fonts(W1-e) · screens/*(W3-a·b, §8-4) · games/*(W4) · shop·gacha·missions·weekly(W4-c).
// 스냅숏: Android 는 Robolectric + Roborazzi(호스트 시험), 데스크톱은 오프스크린 렌더(창 없음, java.awt.headless=true).
plugins {
    id("aingcheck.kmp-library")
    id("aingcheck.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("io.github.takahirom.roborazzi")
}

kotlin {
    android {
        // Compose 리소스(글꼴·아이콘·캐릭터 그림)를 Android 자산으로 싣는다(W1-e). KMP 라이브러리는 기본이 꺼짐이라
        // 끄면 앱·호스트 시험에 composeResources 가 빠져 "Missing resource … Android context is not initialized" 로 죽는다(실측).
        androidResources { enable = true }
    }
    sourceSets {
        commonMain.dependencies {
            api(project(":core:stores"))
            api(libs.compose.runtime)
            api(libs.compose.foundation)
            api(libs.compose.ui)
            api(libs.compose.material3)
            api(libs.compose.components.resources)
            api(libs.jetbrains.lifecycle.runtime.compose)
        }
        getByName("desktopTest").dependencies {
            implementation(compose.desktop.currentOs)
            implementation(libs.compose.ui.test)
            implementation(libs.roborazzi.compose.desktop)
        }
        getByName("androidHostTest").dependencies {
            implementation(libs.roborazzi)
            implementation(libs.roborazzi.compose)
            implementation(libs.roborazzi.junit.rule)
            implementation(libs.androidx.compose.ui.test.junit4)
            implementation(libs.androidx.compose.ui.test.manifest)
            implementation(libs.androidx.test.core)
        }
    }
}

// --- 캐릭터·루비 그림: 맥 원본을 git 사본 없이 Compose 리소스로(A-X18, W1-e) ---
// src/commonMain/composeResources(글꼴·아이콘·라이선스) + 맥 원본 그림을 빌드 폴더 하나로 모으고 그 폴더를 commonMain 리소스 자리로 쓴다.
//   Sources/check/Characters/<id>/{manifest.json, portrait-*.png}           → files/characters/<id>/…
//   Sources/check/Resources/<aing·aing_gold·aing_rainbow·aing_cake_strawberry·aing_cake_choco>-<표정>.png → files/characters/<id>/portrait-<표정>.png
//     (케이크 둘은 0.3.66 생일 선물 전용 — 상점 번호 4(K9 · ShopProtocol.cakeProtocol)는 두 장이 그림 집합에 다 있어야 선다. 5차 int-d)
//   Sources/CheckMobileKit/Resources/Art/{ruby,ruby-48,ruby-96,stage-*-neutral}.png → files/art/…
//   Sources/CheckCore/Resources/Stickers/sticker-*.png(0.3.62 아잉이 이모티콘, G §8-2) → files/stickers/…
// 아틀라스(atlas.png)는 싣지 않는다(살아 있는 캐릭터는 구운 자산 — W0-d·W5).
val repoDir = rootDir.parentFile
val aingFamily = listOf("aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco")
val composeResourcesSynced = layout.buildDirectory.dir("generated/aingcheck/composeResources/commonMain")
val syncCharacterArt = tasks.register<Sync>("aingcheckSyncCharacterArt") {
    description = "맥 원본 캐릭터·루비·이모티콘 그림과 ui 리소스를 Compose 리소스 폴더 하나로 모은다(git 사본 0, A-X18)."
    into(composeResourcesSynced)
    from("src/commonMain/composeResources")
    from(repoDir.resolve("Sources/check/Characters")) {
        include("*/manifest.json", "*/portrait-neutral.png", "*/portrait-negative.png")
        into("files/characters")
    }
    for (id in aingFamily) {
        from(repoDir.resolve("Sources/check/Resources")) {
            include("$id-neutral.png", "$id-negative.png")
            rename("^$id-(neutral|negative)\\.png$", "portrait-$1.png")
            into("files/characters/$id")
        }
    }
    from(repoDir.resolve("Sources/CheckMobileKit/Resources/Art")) {
        include("ruby.png", "ruby-48.png", "ruby-96.png", "stage-*-neutral.png")
        into("files/art")
    }
    from(repoDir.resolve("Sources/CheckCore/Resources/Stickers")) {
        include("sticker-*.png")
        into("files/stickers")
    }
}

compose.resources {
    packageOfResClass = "com.yehsung.aingcheck.ui.resources"
    publicResClass = true
    customDirectory(sourceSetName = "commonMain", directoryProvider = layout.dir(syncCharacterArt.map { it.destinationDir }))
}
