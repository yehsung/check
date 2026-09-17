import CheckCore
import CoreGraphics
import Foundation
import ImageIO

/// 캐릭터 카드 한 장(아잉 + 스프라이트 캐릭터). 그림은 `MeCharacterCardData.swift` 에 박힌 HEIC 다(이유는 그 파일 머리말).
package struct MeCharacterCard: Equatable, Sendable {
    package let id: String
    /// 맥 manifest.json 의 displayName 과 같은 글자("여우").
    package let displayName: String
    package let pixelArt: Bool
    /// 알파로 조인 원본 상자 크기(px) — 드리프트 검사가 맥 아틀라스를 다시 잘라 같은지 본다.
    package let sourceCropWidth: Int
    package let sourceCropHeight: Int
    /// 박힌 그림의 픽셀 크기.
    package let pixelWidth: Int
    package let pixelHeight: Int
    package let heicBase64: String
}

/// 나 탭의 캐릭터 카탈로그(이름·그림). **순서·기본값 규칙은 코어 `CharacterCatalog` 와 같다**: 아잉 먼저, 나머지 id 정렬.
/// 서버(`shop_state`)가 이 빌드가 모르는 캐릭터를 주면 이름은 id 그대로, 그림은 없음(뷰가 자리표시를 그린다) — 맥 상점과 같은 관용.
package enum MeCharacterCards {
    package static let aingID = CharacterCatalog.builtInAingID

    package static func card(id: String) -> MeCharacterCard? {
        bundled.first { $0.id == id }
    }

    package static func displayName(for id: String) -> String {
        card(id: id)?.displayName ?? id
    }

    /// 이 빌드가 아는 캐릭터 id(아잉 먼저, 나머지 정렬).
    package static var knownIDs: [String] {
        [aingID] + bundled.map(\.id).filter { $0 != aingID }.sorted()
    }

    package static func isKnown(_ id: String) -> Bool {
        card(id: id) != nil
    }

    /// 서버 착용값(`profiles.character`) → 화면에 세울 id. 비었거나(기본) 이 빌드가 모르는 id 면 아잉.
    /// (맥 `CharacterSyncDecision.normalized` 와 같은 접기 — 모르는 캐릭터는 아잉으로 서되, 서버 값은 건드리지 않는다.)
    package static func equippedID(fromServer serverID: String?) -> String {
        guard let id = CharacterSyncDecision.normalized(serverID), isKnown(id) else { return aingID }
        return id
    }

    private static let imageCache = MeCharacterImageCache()

    /// 카드 그림(디코드 1회 캐시). 모르는 id·디코드 실패는 nil.
    package static func image(id: String) -> CGImage? {
        if let hit = imageCache.get(id) { return hit }
        guard let card = card(id: id),
              let data = Data(base64Encoded: card.heicBase64),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        imageCache.set(id, image)
        return image
    }
}

/// 디코드한 카드 그림 캐시(잠금 — 뷰가 어느 스레드에서 불러도 안전).
private final class MeCharacterImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: CGImage] = [:]

    func get(_ id: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        return images[id]
    }

    func set(_ id: String, _ image: CGImage) {
        lock.lock(); defer { lock.unlock() }
        images[id] = image
    }
}
