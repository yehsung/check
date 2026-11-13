import Foundation

// MARK: - 루비 아잉이 (v0.3.78 — 상점에서 루비 1000개로 사는 캐릭터)
//
// 대표 결정(2026-11-06): "루비 아잉이는 루비 1000개로 구매 가능하게" · 그림 7차 "Y5 배 띠 · 6:4". 몸 모양(정점 이동) · 몸 셰이더는
// `RubyAingShape` · `RubyAingShader`(같은 폴더) 한 곳이고, 맥 3D 마감(`RubyAingFinish`)과 초상 생성기(`scripts/make-ruby-aing.swift`)가
// 그 둘을 같이 쓴다.

/// 루비 아잉이 그림 파일의 이름 · "그릴 수 있다"의 판정. **파일 이름을 적는 곳은 여기 하나다.**
///
/// 파일 자리(확장자 png): 맥 `Sources/check/Resources/`(초상 두 장 — 3D 마감 재료는 무지개 밝기 맵을 **같이 쓴다**, 몸 모양은 코드가 빚는다).
/// 폰은 다음 판(초상을 폰 번들에 넣는 판이 능력 번호 8 을 말한다).
package nonisolated enum RubyAingArt {
    package static let characterID = CharacterCatalog.rubyAingID
    package static let resourceExtension = GoldAingArt.resourceExtension

    /// 초상(192×192). 이름 규칙은 폰 `AingCharacterArt.portraitName` 의 `<id>-<표정>` 과 같다.
    package static let neutralPortraitResourceName = "\(characterID)-neutral"
    package static let negativePortraitResourceName = "\(characterID)-negative"
    package static var portraitResourceNames: [String] { [neutralPortraitResourceName, negativePortraitResourceName] }

    /// 맥 3D 마감 재료 — 무지개와 같이 쓰는 라벤더 밝기 맵(디퓨즈 합성 · 셰이더 인자 ckShadeMap). 몸 색 · 모양은 코드가 정한다.
    package static var finishResourceNames: [String] { [RainbowAingArt.shadeResourceName] }

    package typealias Platform = GoldAingArt.Platform

    /// 플랫폼별 요구 파일. 폰은 3D 를 그리지 않으므로 초상이 전부다.
    package static func requiredResourceNames(for platform: Platform) -> [String] {
        switch platform {
        case .mac: return portraitResourceNames + finishResourceNames
        case .phone: return portraitResourceNames
        }
    }

    /// 이 빌드가 루비 아잉이를 **그릴 수 있는가** — 요구 파일이 전부 실재할 때만 참(상점 능력 번호 8 의 재료).
    package static func isDrawable(on platform: Platform, resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames(for: platform).allSatisfy(resourceExists)
    }
}
