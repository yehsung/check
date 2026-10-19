import Foundation

// MARK: - 황금 아잉이 (v0.3.54) — 식별과 "그릴 수 있다"의 정의
//
// 황금 아잉이는 아잉과 **같은 메시**(aing.scn)에 금빛 마감(굽힌 피부 텍스처 + 후광)을 입힌 변형이다. 상점에서 살 수 없고
// 뽑기로만 얻는다. 이 파일은 두 가지를 한 곳에 둔다:
//  ① 렌더러가 금 변형을 알아보는 길(`CharacterManifest.finish`) — kind 는 아잉과 같은 `.scene3D` 라 kind 로 가를 수 없다.
//  ② "이 빌드가 황금 아잉이를 그릴 수 있다"의 정의(`GoldAingArt`) — 상점 능력 번호 2(`ShopWire.goldProtocol`)의 재료다.
//     그림 없는 빌드가 2 를 보내면 서버가 금 카드·뽑기를 내려 주고, 사용자는 **아잉 그림**의 "황금 아잉이"를 뽑는다.

extension CharacterManifest {
    /// 3D 캐릭터의 표면 마감. 스프라이트는 언제나 `.standard` 다.
    package enum Finish: Sendable, Equatable {
        /// 메시·텍스처 그대로(아잉 · 스프라이트).
        case standard
        /// 황금 아잉이 — 아잉 메시 + 금빛 피부(`GoldAingArt.skinResourceName`) + 후광(`GoldAingArt.haloResourceName`).
        case gold
        /// 무지개 아잉이(v0.3.59) — 아잉 메시 + 다듬은 라벤더 밝기 맵(`RainbowAingArt.shadeResourceName`) + 몸 셰이더(높이로 무지개 색상) +
        /// 무지개 후광(`RainbowAingArt.haloResourceName`). 렌더러는 kind 가 아니라 이 값으로 가른다(금과 같은 이유).
        case rainbow
    }

    /// 이 캐릭터의 마감. **id 에서 파생한다**(매니페스트 파일에 칸을 더하지 않는다 — 금·무지개는 코드에 박힌 내장 항목뿐이다).
    package var finish: Finish { Finish(characterID: id) }
}

extension CharacterManifest.Finish {
    /// id → 마감. 매니페스트가 없는 자리(뽑기 결과 · 확률표 줄 · 교환 칸 · 남의 착용 id)도 같은 판정을 쓴다 — 화면의 희귀 강조
    /// (금빛 · 무지개빛)가 3D 마감과 **한 곳**에서 갈린다(v0.3.59).
    package init(characterID: String?) {
        if CharacterCatalog.isGoldAing(characterID) {
            self = .gold
        } else if CharacterCatalog.isRainbowAing(characterID) {
            self = .rainbow
        } else {
            self = .standard
        }
    }

    /// 희귀(뽑기 전용 내장 — 황금 · 무지개)인가. 확률표 강조 · 결과 연출 · 교환 목록 맨 위가 이 값으로 갈린다.
    package var isRare: Bool { self != .standard }
}

/// 황금 아잉이 그림 파일의 이름과 "그릴 수 있다"의 판정. **파일 이름을 적는 곳은 여기 하나다** — 맥 번들 조회·폰 초상·
/// 아트 스크립트(`scripts/make-gold-aing.swift`)·테스트가 이 이름을 같이 쓴다.
///
/// 파일 자리(확장자는 모두 `png`):
/// - 맥: `Sources/check/Resources/` — `.process` 리소스라 번들 루트에 평탄화된다(아잉 `aing-neutral.png` 와 같은 자리).
/// - 폰·위젯: `Sources/CheckMobileShared/Resources/Portraits/` — 초상 두 장만(3D 가 없다). 맥 원본과 픽셀이 같아야 한다.
package nonisolated enum GoldAingArt {
    package static let characterID = CharacterCatalog.goldAingID
    package static let resourceExtension = "png"

    /// 초상(192×192). 메뉴바·헤더·카드·남의 아바타가 쓴다. 이름 규칙은 폰 `AingCharacterArt.portraitName` 의 `<id>-<표정>` 과 같다.
    package static let neutralPortraitResourceName = "\(characterID)-neutral"
    package static let negativePortraitResourceName = "\(characterID)-negative"
    package static var portraitResourceNames: [String] { [neutralPortraitResourceName, negativePortraitResourceName] }

    /// 맥 3D 마감 — UV 공간에 구운 금빛 피부(512²)와, 몸 뒤에 세우는 후광 판.
    package static let skinResourceName = "\(characterID)-skin"
    package static let haloResourceName = "\(characterID)-halo"
    package static var finishResourceNames: [String] { [skinResourceName, haloResourceName] }

    /// 후광 각도 칸(v0.3.55) — 몸이 카메라에 대해 돈 각(요)마다 그 자세의 실루엣으로 구운 후광. 칸 k 는 몸 요 k × 10°
    /// (위에서 볼 때 반시계 = `rotateBy(y: +)` 방향, +90° 면 얼굴이 화면 오른쪽). 0 칸은 정면 후광(`haloResourceName`, 512²) 그대로이고,
    /// 나머지 35칸은 `<id>-halo-010` … `<id>-halo-350`(160²)이다. 아트 스크립트가 같은 이름으로 쓴다.
    ///
    /// "그릴 수 있다"(`requiredResourceNames`)에는 넣지 않는다 — 칸이 빠진 빌드도 황금 아잉이는 서고(빠진 칸은 정면 후광으로 접는다),
    /// 상점 능력 번호 2 의 뜻은 "금 아잉을 그린다"이다. 대신 맥 패키징 대본 둘이 조립한 앱 안에서 칸 수를 세어 빠지면 멈춘다.
    package static let haloYawStepDegrees = 10
    package static var haloCellCount: Int { 360 / haloYawStepDegrees }

    /// 칸 k(0…35)의 그림 이름.
    package static func haloResourceName(cell: Int) -> String {
        cell == 0 ? haloResourceName : "\(haloResourceName)-\(String(format: "%03d", cell * haloYawStepDegrees))"
    }

    /// 후광 그림 전부(0 칸 = 정면부터 순서대로 36장).
    package static var haloCellResourceNames: [String] { (0..<haloCellCount).map(haloResourceName(cell:)) }

    /// 플랫폼별 요구 파일. 폰은 3D 를 그리지 않으므로 초상이 전부다.
    package enum Platform: Sendable, Equatable {
        case mac
        case phone
    }

    package static func requiredResourceNames(for platform: Platform) -> [String] {
        switch platform {
        case .mac: return portraitResourceNames + finishResourceNames
        case .phone: return portraitResourceNames
        }
    }

    /// 이 빌드가 황금 아잉이를 **그릴 수 있는가** — 요구 파일이 전부 실재할 때만 참이다.
    ///
    /// `resourceExists` 는 주입한다(파일 이름 → 실재 여부). 맥은 번들 조회
    /// (`{ CheckResources.bundle.url(forResource: $0, withExtension: GoldAingArt.resourceExtension) != nil }`),
    /// 테스트는 임시 폴더나 가짜 집합을 넣는다. 한 장이라도 없으면 거짓이다 — 초상만 있고 마감이 없는 맥은 금 착용자의
    /// 오버레이에 보라 아잉을 세우고, 마감만 있고 초상이 없으면 메뉴바·카드가 아잉으로 접힌다.
    package static func isDrawable(on platform: Platform, resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames(for: platform).allSatisfy(resourceExists)
    }
}
