import Foundation

// MARK: - 흑우 아잉이 (v0.3.78 — 조각 20개로만 바꾸는 캐릭터)
//
// 대표 결정(2026-11-06): 제보 "뽑기말고 조각으로만 교환할 수 있는 흑우 아잉이" → "흑우 아잉이 좋음" · 조각 "20개 (황금·무지개와 같게)" ·
// 그림 "U9 네온"(짙은 남색 몸 + 왼쪽 하늘색 · 오른쪽 분홍 네온 테). 시안 렌더러 `~/.claude/projects/-Users-yesung-check/aing-hwoo-ruby/r1`
// (`uNeon()`)의 식을 앱 몸 셰이더(`HwooAingFinish`)와 초상 생성기(`scripts/make-hwoo-aing.swift`)가 같은 값으로 쓴다.

/// 흑우 아잉이 그림 파일의 이름 · "그릴 수 있다"의 판정 · 네온 색. **파일 이름 · 색을 적는 곳은 여기 하나다.**
///
/// 파일 자리(확장자 png): 맥 `Sources/check/Resources/`(초상 두 장 — 3D 마감 재료는 무지개 밝기 맵을 **같이 쓴다**, 따로 굽지 않는다).
/// 폰은 다음 판(초상을 폰 번들에 넣는 판이 능력 번호 7 을 말한다).
package nonisolated enum HwooAingArt {
    package static let characterID = CharacterCatalog.hwooAingID
    package static let resourceExtension = GoldAingArt.resourceExtension

    /// 초상(192×192). 이름 규칙은 폰 `AingCharacterArt.portraitName` 의 `<id>-<표정>` 과 같다.
    package static let neutralPortraitResourceName = "\(characterID)-neutral"
    package static let negativePortraitResourceName = "\(characterID)-negative"
    package static var portraitResourceNames: [String] { [neutralPortraitResourceName, negativePortraitResourceName] }

    /// 맥 3D 마감 재료 — 무지개와 같이 쓰는 라벤더 밝기 맵(디퓨즈 합성 · 셰이더 인자 ckShadeMap). 네온 몸 색은 셰이더가 정한다.
    package static var finishResourceNames: [String] { [RainbowAingArt.shadeResourceName] }

    package typealias Platform = GoldAingArt.Platform

    /// 플랫폼별 요구 파일. 폰은 3D 를 그리지 않으므로 초상이 전부다.
    package static func requiredResourceNames(for platform: Platform) -> [String] {
        switch platform {
        case .mac: return portraitResourceNames + finishResourceNames
        case .phone: return portraitResourceNames
        }
    }

    /// 이 빌드가 흑우를 **그릴 수 있는가** — 요구 파일이 전부 실재할 때만 참(상점 능력 번호 7 의 재료).
    package static func isDrawable(on platform: Platform, resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames(for: platform).allSatisfy(resourceExists)
    }

    // MARK: 네온 색(sRGB 16진) — 셰이더 · 초상 생성기가 같은 값을 쓴다

    /// 몸 바탕(짙은 남색).
    package static let bodyColor = 0x1A1830
    /// 네온 테 — 화면 왼쪽(물체 −x) 하늘색 · 오른쪽(+x) 분홍. 가운데는 섞인다.
    package static let neonLeft = 0x2EE6FF
    package static let neonRight = 0xFF3FA8
    /// 테 세기 · 날카로움(셰이더 `pow(1 − N·V, rimPower) × rimStrength`).
    package static let rimPower = 2.4
    package static let rimStrength = 1.1
}
