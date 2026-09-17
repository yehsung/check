import Foundation
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

/// 캐릭터 초상 그림(6 캐릭터 × 표정 2) — **앱과 위젯 확장이 함께 읽는 번들 리소스**(App Group 이 아니다).
///
/// 원본은 맥 에셋 그대로다: 스프라이트는 `Sources/check/Characters/<id>/portrait-{neutral,negative}.png`, 아잉은
/// `Sources/check/Resources/aing-{neutral,negative}.png`(모두 192px — 맥 원본 해상도). 이 패키지 리소스(`Resources/Portraits`)는
/// 그 사본이고, `BaseComponentTests` 가 바이트 단위로 원본과 같은지 잰다(맥 그림이 바뀌면 빨강).
///
/// 표정은 근무 상태다(맥 헤더 문법): 근무 중·연결 끊김 = neutral(웃음), 근무 안 함 = negative(시무룩).
public enum AingCharacterArt {
    /// 기본 캐릭터(서버 착용값이 비었거나 이 빌드가 모르는 id).
    public static let defaultID = "aing"

    /// 이 번들에 초상이 있는 캐릭터(아잉 먼저, 나머지 이름순 — 코어 `CharacterCatalog` 순서 규칙과 같다).
    public static let knownIDs: [String] = ["aing", "fox", "ghost", "jellyfish", "shiba", "squirrel"]

    public enum Expression: String, CaseIterable, Sendable {
        /// 웃는 얼굴(근무 중 · 연결 끊김 · 상태 없음).
        case neutral
        /// 시무룩(근무 안 함).
        case negative
    }

    /// 착용값 → 세울 id. 공백·nil·모르는 id 는 아잉(앱 `MeCharacterCards.equippedID(fromServer:)` 와 같은 접기 — 테스트가 대조).
    public static func resolvedID(_ raw: String?) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), knownIDs.contains(trimmed) else {
            return defaultID
        }
        return trimmed
    }

    /// 초상 파일 이름(확장자 뺀 것) — `<id>-<표정>`.
    public static func portraitName(id: String, expression: Expression) -> String {
        "\(resolvedID(id))-\(expression.rawValue)"
    }

    /// 초상 파일 위치(번들 안). 없으면 nil — 이 빌드의 리소스가 빠졌다는 뜻이다(테스트가 12장 모두 있는지 잰다).
    public static func portraitURL(id: String, expression: Expression, bundle: Bundle? = nil) -> URL? {
        (bundle ?? .module).url(forResource: portraitName(id: id, expression: expression), withExtension: "png", subdirectory: "Portraits")
    }

    /// 원본 픽셀 한 변(정사각).
    public static let portraitPixelSize = 192

    #if canImport(ImageIO)
    private static let cache = PortraitCache()

    /// 초상 CGImage(디코드 1회 캐시 · 스레드 안전). 위젯은 이걸 `Image(decorative:scale:)` 로 그린다.
    public static func portraitImage(id: String, expression: Expression) -> CGImage? {
        let key = portraitName(id: id, expression: expression)
        if let hit = cache.get(key) { return hit }
        guard let url = portraitURL(id: id, expression: expression),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        cache.set(key, image)
        return image
    }
    #endif
}

#if canImport(ImageIO)
private final class PortraitCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: CGImage] = [:]

    func get(_ key: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        return images[key]
    }

    func set(_ key: String, _ image: CGImage) {
        lock.lock(); defer { lock.unlock() }
        images[key] = image
    }
}
#endif
