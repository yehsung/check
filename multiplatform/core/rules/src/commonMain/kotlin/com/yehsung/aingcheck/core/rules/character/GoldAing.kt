// 원본: Sources/CheckCore/CharacterKit/GoldAing.swift @ 1b8260d (Finish 열거는 CharacterManifest.kt 에 — Kotlin 중첩 타입 규칙)
package com.yehsung.aingcheck.core.rules.character

/**
 * 황금 아잉이 그림 파일의 이름과 "그릴 수 있다"의 판정 — **파일 이름을 적는 곳은 여기 하나다**.
 * 상점 능력 번호 2([com.yehsung.aingcheck.core.rules.gacha.ShopWire.goldProtocol])의 재료다: 그림 없는 빌드가 2 를 보내면 사용자는
 * 아잉 그림의 "황금 아잉이"를 뽑는다.
 */
object GoldAingArt {
    val characterID: String get() = CharacterCatalog.goldAingID
    const val resourceExtension = "png"

    /** 초상(192×192) — 폰 `<id>-<표정>` 규칙. */
    val neutralPortraitResourceName: String get() = "$characterID-neutral"
    val negativePortraitResourceName: String get() = "$characterID-negative"
    val portraitResourceNames: List<String> get() = listOf(neutralPortraitResourceName, negativePortraitResourceName)

    /** 맥 3D 마감 — 굽힌 금빛 피부와 후광 판. */
    val skinResourceName: String get() = "$characterID-skin"
    val haloResourceName: String get() = "$characterID-halo"
    val finishResourceNames: List<String> get() = listOf(skinResourceName, haloResourceName)

    /** 후광 각도 칸(10° 간격 · 36칸 · 0 칸은 정면). "그릴 수 있다"에는 넣지 않는다(빠진 칸은 정면으로 접는다). */
    const val haloYawStepDegrees = 10
    val haloCellCount: Int get() = 360 / haloYawStepDegrees

    fun haloResourceName(cell: Int): String =
        if (cell == 0) haloResourceName else "$haloResourceName-${(cell * haloYawStepDegrees).toString().padStart(3, '0')}"

    val haloCellResourceNames: List<String> get() = (0 until haloCellCount).map(::haloResourceName)

    /** 플랫폼별 요구 파일. 폰(= Android · Windows 첫 판, G §8-7)은 3D 를 그리지 않으므로 초상이 전부다. */
    enum class Platform { mac, phone }

    fun requiredResourceNames(platform: Platform): List<String> = when (platform) {
        Platform.mac -> portraitResourceNames + finishResourceNames
        Platform.phone -> portraitResourceNames
    }

    /** 요구 파일이 전부 실재할 때만 참(`resourceExists` 주입 — 파일 이름 → 실재 여부). */
    fun isDrawable(platform: Platform, resourceExists: (String) -> Boolean): Boolean =
        requiredResourceNames(platform).all(resourceExists)
}
