#if os(iOS)
import CheckMobileShared
import SwiftUI
import UIKit

/// 앱 번들 그림(루비 · 무대용 고해상 초상 · 플래피 아잉 옆모습)과 공용 초상(`AingCharacterArt` — 위젯도 읽는다)을 한 창구로 연다.
/// 디코드는 한 번(캐시). 그림은 **SF 기호로 대신하지 않는다** — 파일이 없으면 빈 자리(테스트가 파일 12+9장을 잰다).
package enum MobileArt {
    private static let cache = MobileArtCache()

    /// `Resources/Art/<name>.png`.
    package static func appImage(_ name: String) -> UIImage? {
        if let hit = cache.get(name) { return hit }
        guard let url = MobileArtNames.url(name),
              let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        cache.set(name, image)
        return image
    }

    /// 크기에 맞는 루비 그림.
    package static func ruby(pointSize: CGFloat, displayScale: CGFloat) -> UIImage? {
        appImage(RubyGlyph.assetName(pointSize: pointSize, displayScale: displayScale))
    }

    /// 캐릭터 그림(초상 192px 또는 무대 420px — `CharacterArtChoice`).
    package static func character(id: String, expression: AingCharacterArt.Expression, pointSize: CGFloat, displayScale: CGFloat) -> UIImage? {
        let resolved = AingCharacterArt.resolvedID(id)
        switch CharacterArtChoice.choose(id: resolved, expression: expression, pointSize: pointSize, displayScale: displayScale) {
        case .stage:
            if let stage = appImage(MobileArtNames.stage(id: resolved)) { return stage }
            fallthrough
        case .portrait:
            let key = "portrait:\(resolved)-\(expression.rawValue)"
            if let hit = cache.get(key) { return hit }
            guard let cg = AingCharacterArt.portraitImage(id: resolved, expression: expression) else { return nil }
            let image = UIImage(cgImage: cg)
            cache.set(key, image)
            return image
        }
    }

    /// 플래피 아잉 옆모습(게임 타일 · 미니게임).
    package static var flappyAing: UIImage? { appImage(MobileArtNames.flappyAing) }
}

private final class MobileArtCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: UIImage] = [:]

    func get(_ key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return images[key]
    }

    func set(_ key: String, _ image: UIImage) {
        lock.lock(); defer { lock.unlock() }
        images[key] = image
    }
}

/// 번들 그림 한 장을 크기에 맞춰 부드럽게(`.interpolation(.high)`) 그린다. 없으면 같은 크기의 빈 자리.
package struct ArtImage: View {
    private let image: UIImage?
    private let size: CGSize

    package init(_ image: UIImage?, size: CGSize) {
        self.image = image
        self.size = size
    }

    package var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// 플래피 아잉 옆모습(게임 탭 타일 · 플래피 캔버스). 벌새 기호 대신.
package struct FlappyAingArt: View {
    private let size: CGFloat

    package init(size: CGFloat = 52) {
        self.size = size
    }

    package var body: some View {
        ArtImage(MobileArt.flappyAing, size: CGSize(width: size, height: size))
    }
}
#endif
