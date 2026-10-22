import Foundation
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

/// 캐릭터 초상 그림(9 캐릭터 × 표정 2 = 18장) — **앱과 위젯 확장이 함께 읽는 번들 리소스**(App Group 이 아니다).
///
/// 원본은 맥 에셋 그대로다: 스프라이트는 `Sources/check/Characters/<id>/portrait-{neutral,negative}.png`, 아잉·황금·무지개 아잉이는
/// `Sources/check/Resources/<id>-{neutral,negative}.png`(모두 192px — 맥 원본 해상도). 이 패키지 리소스(`Resources/Portraits`)는
/// 그 사본이고, `BaseComponentTests` 가 **픽셀 단위로** 원본과 같은지 잰다(맥 그림이 바뀌면 빨강 — 사본은 재압축돼 바이트가 다르다).
///
/// 표정은 근무 상태다(맥 헤더 문법): 근무 중·연결 끊김 = neutral(웃음), 근무 안 함 = negative(시무룩).
public enum AingCharacterArt {
    /// 기본 캐릭터(서버 착용값이 비었거나 이 빌드가 모르는 id).
    public static let defaultID = "aing"

    /// 이 번들에 초상이 있는 캐릭터(아잉 먼저, 나머지 이름순 — 코어 `CharacterCatalog` 순서 규칙과 같다).
    ///
    /// v0.3.54(폰 1.0.8): 황금 아잉이(`aing_gold` — 뽑기·조각 교환으로만 얻는다)의 초상 두 장이 들어와 8 캐릭터가 됐다.
    /// v0.3.59(폰 1.0.10): 무지개 아잉이(`aing_rainbow` — 금과 같은 급의 뽑기 전용)가 들어와 **9 캐릭터**가 됐다.
    ///
    /// ★ 이 목록이 상점 능력 번호의 재료다(`MeStore.drawableCharacterIDs` → `ShopWire.protocolVersion`), 그리고 번호는
    ///   **누적**이다: `robot` 까지면 1, `aing_gold` 까지면 2, `aing_rainbow` 까지 있어야 **3** 이다. 폰이 3 을 말해야 서버가
    ///   무지개 행(목록 · 확률표 8줄 정수 · 교환표 `shard_costs.aing_rainbow = 20`)을 내려 준다 — 2 를 말하면 서버는 무지개를
    ///   **아예 안 보내고** 남은 7줄을 100 으로 다시 나눈 소수 확률표를 준다. 그래서 여기서 `aing_rainbow` 를 빼는 순간
    ///   폰에서 무지개가 통째로 사라진다(뽑히지도, 교환되지도 않는다).
    /// ★ 초상 파일 없이 이름만 더하면 그 반대로 틀린다 — 아잉 그림의 "황금/무지개 아잉이"를 뽑게 된다.
    ///   파일 ⟺ 목록 ⟺ 번호를 양방향으로 재는 자리는 `MeGoldShopProtocolTests`(2)와 `MeRainbowProtocolTests`(3)다.
    public static let knownIDs: [String] = ["aing", "aing_gold", "aing_rainbow", "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel"]

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

    /// 초상 파일 위치(번들 안). 없으면 nil — 이 빌드의 리소스가 빠졌다는 뜻이다(테스트가 16장 모두 있는지 잰다).
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
