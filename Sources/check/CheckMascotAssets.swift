import AppKit
import Foundation

/// 번들에 포함된 캐릭터 이미지("아잉") 로딩·캐싱 헬퍼.
///
/// 근무 상태에 따라 두 가지 표정을 노출한다.
/// - 근무중(`snapshot.isWorking == true`): 웃는 얼굴(`aing-neutral`)
/// - 근무중 아님: 시무룩(`aing-negative`)
///
/// 판단 기준은 `snapshot.isWorking` 하나만 사용하며 `pendingSync` 여부와 무관하다.
/// 로드 실패 시 nil을 돌려주어 호출부가 SF Symbol/그려진 얼굴로 폴백하도록 한다.
enum CheckMascotAssets {
    enum Mood: Equatable {
        case neutral
        case negative
    }

    /// 캐릭터 이미지가 담긴 리소스 번들. 테스트에서 접근성 검증에 사용한다.
    static var bundle: Bundle {
        Bundle.module
    }

    static func resourceName(for mood: Mood) -> String {
        switch mood {
        case .neutral:
            return "aing-neutral"
        case .negative:
            return "aing-negative"
        }
    }

    static func mood(for snapshot: WorkStatusSnapshot) -> Mood {
        snapshot.isWorking ? .neutral : .negative
    }

    static func url(for mood: Mood) -> URL? {
        bundle.url(forResource: resourceName(for: mood), withExtension: "png")
    }

    static func image(for snapshot: WorkStatusSnapshot) -> NSImage? {
        image(for: mood(for: snapshot))
    }

    static func image(for mood: Mood) -> NSImage? {
        cache.image(named: resourceName(for: mood))
    }

    /// 메뉴바(높이 ~22pt) 전용 캐릭터 이미지.
    ///
    /// 원본 NSImage의 copy를 만들어 `size`만 18×18pt로 지정한다. 비트맵 rep은
    /// 640px 그대로 유지되므로 레티나에서 선명하다. `MenuBarExtra` 라벨은
    /// NSImage의 intrinsic size를 그대로 쓰는 경로가 있어 SwiftUI `.frame`이
    /// 무시될 수 있으므로, 이미지 자체 크기를 줄여 잘림을 방지한다.
    static let menuBarSize = NSSize(width: 18, height: 18)

    static func menuBarImage(for snapshot: WorkStatusSnapshot) -> NSImage? {
        menuBarImage(for: mood(for: snapshot))
    }

    static func menuBarImage(for mood: Mood) -> NSImage? {
        cache.menuBarImage(named: resourceName(for: mood), size: menuBarSize)
    }

    // MARK: - Caching

    private static let cache = ImageCache()

    /// 내부 상태는 `NSLock`으로 직렬화하므로 `@unchecked Sendable`로 표시한다.
    private final class ImageCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: NSImage] = [:]
        private var menuBarStorage: [String: NSImage] = [:]

        func image(named name: String) -> NSImage? {
            lock.lock()
            defer { lock.unlock() }
            return baseImageLocked(named: name)
        }

        func menuBarImage(named name: String, size: NSSize) -> NSImage? {
            lock.lock()
            defer { lock.unlock() }

            if let cached = menuBarStorage[name] {
                return cached
            }
            guard let base = baseImageLocked(named: name),
                  let sized = base.copy() as? NSImage else {
                return nil
            }
            // rep(640px)은 그대로 두고 논리 크기만 줄인다 → 다운스케일되어 선명.
            sized.size = size
            menuBarStorage[name] = sized
            return sized
        }

        /// `lock`을 이미 획득한 상태에서만 호출해야 한다.
        private func baseImageLocked(named name: String) -> NSImage? {
            if let cached = storage[name] {
                return cached
            }
            guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else {
                return nil
            }
            storage[name] = image
            return image
        }
    }
}
