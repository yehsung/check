import Foundation
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

/// 캐릭터 초상 그림(11 캐릭터 × 표정 2 = 22장) — **앱과 위젯 확장이 함께 읽는 번들 리소스**(App Group 이 아니다).
///
/// 원본은 맥 에셋 그대로다: 스프라이트는 `Sources/check/Characters/<id>/portrait-{neutral,negative}.png`, 아잉·황금·무지개·케이크 아잉이는
/// `Sources/check/Resources/<id>-{neutral,negative}.png`(모두 192px — 맥 원본 해상도). 이 패키지 리소스(`Resources/Portraits`)는
/// 그 사본이고, `BaseComponentTests` 가 **픽셀 단위로** 원본과 같은지 잰다(맥 그림이 바뀌면 빨강 — 사본은 재압축돼 바이트가 다르다).
///
/// 표정은 근무 상태다(맥 헤더 문법): 근무 중·연결 끊김 = neutral(웃음), 근무 안 함 = negative(시무룩).
public enum AingCharacterArt {
    /// 기본 캐릭터(서버 착용값이 비었거나 이 빌드가 모르는 id).
    public static let defaultID = "aing"

    /// 이 번들에 초상이 있는 캐릭터 — **코어 `CharacterCatalog.allIDs` 순서 규칙과 같다**: 내장 다섯(아잉 · 황금 · 무지개 · 딸기 케이크 ·
    /// 초코 케이크)이 그 순서로 먼저, 나머지는 이름순. (케이크 둘은 이름순이면 금보다 **앞**이라 — `aing_cake_*` < `aing_gold` —
    /// 내장 순서로 박는다. 고르기·상점 자리표시가 이 순서를 그대로 쓴다.)
    ///
    /// v0.3.54(폰 1.0.8): 황금 아잉이(`aing_gold` — 뽑기·조각 교환으로만 얻는다)의 초상 두 장이 들어와 8 캐릭터가 됐다.
    /// v0.3.59(폰 1.0.10): 무지개 아잉이(`aing_rainbow` — 금과 같은 급의 뽑기 전용)가 들어와 **9 캐릭터**가 됐다.
    /// v0.3.66(폰 1.0.14): 케이크 아잉이 둘(`aing_cake_strawberry` · `aing_cake_choco` — 생일 선물 전용)이 들어와 **11 캐릭터**가 됐고,
    /// 능력 번호가 저절로 **4** 가 된다(`ShopWire.protocolVersion` — 두 케이크를 **다** 그릴 수 있어야 4 다).
    ///
    /// ★ 이 목록이 상점 능력 번호의 재료다(`MeStore.drawableCharacterIDs` → `ShopWire.protocolVersion`), 그리고 번호는
    ///   **누적**이다: `robot` 까지면 1, `aing_gold` 까지면 2, `aing_rainbow` 까지 있어야 **3** 이다. 폰이 3 을 말해야 서버가
    ///   무지개 행(목록 · 확률표 8줄 정수 · 교환표 `shard_costs.aing_rainbow = 20`)을 내려 준다 — 2 를 말하면 서버는 무지개를
    ///   **아예 안 보내고** 남은 7줄을 100 으로 다시 나눈 소수 확률표를 준다. 그래서 여기서 `aing_rainbow` 를 빼는 순간
    ///   폰에서 무지개가 통째로 사라진다(뽑히지도, 교환되지도 않는다).
    /// ★ 초상 파일 없이 이름만 더하면 그 반대로 틀린다 — 아잉 그림의 "황금/무지개 아잉이"를 뽑게 된다.
    ///   파일 ⟺ 목록 ⟺ 번호를 양방향으로 재는 자리는 `MeGoldShopProtocolTests`(2) · `MeRainbowProtocolTests`(3) ·
    ///   `MeCakeGiftTests`(4)다.
    public static let knownIDs: [String] = [
        "aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco",
        "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel",
    ]

    // MARK: 아바타 틀(원 안 얼굴 크기)

    /// 원형 아바타(작은 원 · 순위 · 게임 · 탭 막대 · 위젯 얼굴) 안에서 초상을 **얼마나 키우고 어디로 옮길지**.
    ///
    /// 아바타는 초상을 원 지름의 88% 로 그린다(모든 자리 같은 기하). 아잉 · 황금 · 무지개 초상은 몸이 같은 자리 · 같은 크기라 그대로 두면
    /// 얼굴 크기가 같다. **케이크 초상만 다르다**: 머리 위 장식(초 · 딸기)이 캔버스에 들어가도록 아잉 몸을 0.88 배로 줄여 아래로 내렸다
    /// (`scripts/make-cake-aing.swift` — 네 장 같은 배율 · 자리). 그대로 그리면 케이크 착용자만 원 안 얼굴이 12% 작고 낮다.
    /// 그래서 케이크는 그 줄임을 되돌려(×1/0.88) 몸을 아잉 자리로 올린다 — 장식은 원 위로 조금 잘린다(조정자 결정 — 괜찮다).
    ///
    /// 전신을 보이는 자리(무대 · 상점 타일 · 미리 보기 · 축하 시트)는 이 틀을 쓰지 않는다 — 장식이 케이크의 핵심이다.
    public struct AvatarFraming: Equatable, Sendable {
        /// 초상 그림의 배율(가운데 기준). 1 = 그대로.
        public let scale: Double
        /// 세로 이동 — 초상 한 변에 대한 비율(음수 = 위로). 배율을 건 뒤에 옮긴다.
        public let offsetY: Double

        public static let identity = AvatarFraming(scale: 1, offsetY: 0)

        public init(scale: Double, offsetY: Double) {
            self.scale = scale
            self.offsetY = offsetY
        }
    }

    /// 케이크 초상의 몸 배치 — **아잉 초상 좌표 (x, y) → 케이크 초상 좌표 (96 + (x − 96)·s, top + y·s)**(192px 캔버스, 위가 0).
    /// 생성기 `composePortrait` 의 `k`(0.88)와, 네 장(두 케이크 × 두 표정)을 아잉 초상에 맞춰 잰 세로 자리(28.0px)다.
    /// `MeCakeGiftTests` 가 실제 PNG 를 이 값으로 되돌려 아잉 몸과 겹치는지(아래 끝 · 가장 넓은 폭) 잰다 — 생성기를 다시 돌려 배치가 바뀌면 빨개진다.
    public static let cakePortraitBodyScale = 0.88
    public static let cakePortraitBodyTop = 28.0

    /// 이 캐릭터의 아바타 틀. 케이크 둘만 `identity` 가 아니다(모르는 id 는 아잉으로 접히므로 `identity`).
    public static func avatarFraming(id: String?) -> AvatarFraming {
        let resolved = resolvedID(id)
        guard resolved == "aing_cake_strawberry" || resolved == "aing_cake_choco" else { return .identity }
        let s = cakePortraitBodyScale
        let side = Double(portraitPixelSize)
        // 가운데 기준으로 1/s 배 키우면 케이크 Y 는 side/2 + (Y − side/2)/s 에 선다. 아잉 자리 (Y − top)/s 와의 차가 이동량이다.
        let shift = (side / 2 - cakePortraitBodyTop) / s - side / 2
        return AvatarFraming(scale: 1 / s, offsetY: shift / side)
    }

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
