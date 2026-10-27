// 원본: Sources/CheckCore/CharacterKit/RainbowAing.swift @ 1b8260d (식별 · 그림 이름 · "그릴 수 있다" 몫)
package com.yehsung.aingcheck.core.rules.character

/**
 * 무지개 아잉이 그림 파일의 이름과 "그릴 수 있다"의 판정(금과 같은 규약). 상점 능력 번호 3 의 재료.
 *
 * 몸 색 공식(OKLCh 정지점 · 셰이더 기준 구현 `bodyColorLinear`)은 옮기지 않는다 — Android·Windows 는 3D 를 런타임에 칠하지 않고
 * 구운 스프라이트를 쓴다(G §8-12 굽기 · F). 그 공식은 굽기 도구(맥 SceneKit) 안에서만 돈다:
 *  - INV-RainbowAing-cb063b85 해당 없음(몸을 띠 색 피부 맵으로 굽지 않고 셰이더가 물체 좌표 높이로 칠하는 이유 — 맥 3D 렌더러 · 굽기 몫).
 *  - INV-RainbowAing-aee950b3 해당 없음(정지점 배열을 아트 스크립트와 글자까지 맞추는 규약 — 맥 아트 스크립트 · 셰이더 몫, Kotlin 은 그 결과 그림만 받는다).
 */
object RainbowAingArt {
    val characterID: String get() = CharacterCatalog.rainbowAingID
    val resourceExtension: String get() = GoldAingArt.resourceExtension

    val neutralPortraitResourceName: String get() = "$characterID-neutral"
    val negativePortraitResourceName: String get() = "$characterID-negative"
    val portraitResourceNames: List<String> get() = listOf(neutralPortraitResourceName, negativePortraitResourceName)

    val shadeResourceName: String get() = "$characterID-shade"
    val haloResourceName: String get() = "$characterID-halo"
    val finishResourceNames: List<String> get() = listOf(shadeResourceName, haloResourceName)

    val haloYawStepDegrees: Int get() = GoldAingArt.haloYawStepDegrees
    val haloCellCount: Int get() = GoldAingArt.haloCellCount

    fun haloResourceName(cell: Int): String =
        if (cell == 0) haloResourceName else "$haloResourceName-${(cell * haloYawStepDegrees).toString().padStart(3, '0')}"

    val haloCellResourceNames: List<String> get() = (0 until haloCellCount).map(::haloResourceName)

    fun requiredResourceNames(platform: GoldAingArt.Platform): List<String> = when (platform) {
        GoldAingArt.Platform.mac -> portraitResourceNames + finishResourceNames
        GoldAingArt.Platform.phone -> portraitResourceNames
    }

    fun isDrawable(platform: GoldAingArt.Platform, resourceExists: (String) -> Boolean): Boolean =
        requiredResourceNames(platform).all(resourceExists)
}
