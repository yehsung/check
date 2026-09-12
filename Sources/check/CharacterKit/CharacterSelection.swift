import Foundation

/// 지금 착용한 캐릭터의 영속 선택.
///
/// **모르는 id 는 언제나 아잉으로 접는다.** 캐릭터를 뺀 빌드로 다운그레이드하거나(브루 롤백), 에셋이 깨져 카탈로그에서
/// 빠진 경우에도 저장값을 그대로 믿으면 캐릭터가 통째로 사라진 빈 오버레이가 남는다. 저장값은 지우지 않는다 —
/// 그 캐릭터가 돌아오는 빌드에서 선택이 되살아나게(사용자가 다시 고르지 않아도 되게) 읽기 시점에만 접는다.
@MainActor
final class CharacterSelection {
    /// UserDefaults 키. 마이그레이션·진단이 이 이름을 그대로 쓴다.
    static let defaultsKey = "check.character.selected"

    private let defaults: UserDefaults
    private let catalog: CharacterCatalog

    init(defaults: UserDefaults, catalog: CharacterCatalog) {
        self.defaults = defaults
        self.catalog = catalog
    }

    /// 현재 선택. 저장값이 없거나 카탈로그에 없으면 아잉.
    var selectedID: String {
        guard let stored = defaults.string(forKey: Self.defaultsKey),
              catalog.manifest(id: stored) != nil else {
            return CharacterCatalog.builtInAingID
        }
        return stored
    }

    /// 현재 선택의 매니페스트. 카탈로그가 아잉을 반드시 갖고 있으므로 nil 이 될 수 없다.
    var selectedManifest: CharacterManifest {
        catalog.manifest(id: selectedID) ?? CharacterCatalog.builtInAing
    }

    /// 선택을 바꾼다. 카탈로그에 없는 id 면 **저장하지 않고** false —
    /// 옛 저장값을 모르는 값으로 덮어써 "되돌아올 선택"을 잃지 않게.
    @discardableResult
    func select(_ id: String) -> Bool {
        guard catalog.manifest(id: id) != nil else { return false }
        defaults.set(id, forKey: Self.defaultsKey)
        return true
    }
}
