import Foundation
import os

/// 이 빌드가 세울 수 있는 캐릭터 전부. 번들 `Characters/<id>/manifest.json` 들을 읽어 담는다.
///
/// **안전망이 이 타입의 존재 이유다.** 번들에 캐릭터 폴더가 하나도 없어도(또는 전부 깨져도) 카탈로그에는 늘
/// 아잉이 있고, 앱은 지금과 똑같이 돈다. 그래서 아잉은 매니페스트 파일 없이 코드에 박아 넣고(`builtInAing`),
/// 파일에서 읽은 캐릭터가 하나 깨져도 **그 하나만 건너뛴다**(전체 로드를 실패시키지 않는다).
package struct CharacterCatalog: Sendable {
    /// 아잉의 고정 id. "모르는 캐릭터 → 아잉" 폴백이 전부 이 값을 쓴다.
    package static let builtInAingID = "aing"

    /// 번들 안 캐릭터 폴더 이름. `Package.swift` 의 `.copy("Characters")` 가 구조를 그대로 보존한다
    /// (`.process` 는 하위 폴더를 평탄화해 동명 `atlas.png` 끼리 빌드를 죽인다 — 실측).
    package static let charactersSubdirectory = "Characters"

    /// 코드에 박힌 아잉. 파일이 없어도, 번들이 비어도 이 항목은 사라지지 않는다.
    package static let builtInAing = CharacterManifest(
        id: builtInAingID,
        displayName: "아잉",
        kind: .scene3D
    )

    /// 황금 아잉이(v0.3.54)의 고정 id. 서버 CHECK·가격표·`gacha_pool` 의 id 와 같다.
    ///
    /// ★ **매니페스트 파일로는 못 싣는다**: 파일 매니페스트의 id 문법은 `[a-z0-9-]{1,32}`(밑줄 금지,
    ///   `CharacterManifest.isValidID`)이고 서버 `shop_state` 는 CHECK 를 `[a-z_]+` 로 읽는다 — 두 문법이 다르다.
    ///   그리고 scene3D 매니페스트는 초상을 가질 수 없다. 그래서 아잉처럼 **코드에 박는다**(검증을 안 탄다).
    package static let goldAingID = "aing_gold"

    /// 코드에 박힌 황금 아잉이 — 아잉과 **같은 3D 메시**(aing.scn)에 금빛 마감을 입힌 변형이다.
    /// 렌더러가 "이건 금 아잉이다"를 아는 길은 `CharacterManifest.finish`(또는 `isGoldAing(_:)`) 하나다 —
    /// `kind` 는 아잉과 같은 `.scene3D` 라 kind 로 가르면 금 착용자 화면에 보라 아잉이 선다.
    /// 상점에서는 살 수 없고 뽑기로만 얻는다(서버 `character_prices.gacha_only = true`).
    package static let builtInGoldAing = CharacterManifest(
        id: goldAingID,
        displayName: "황금 아잉이",
        kind: .scene3D
    )

    /// 무지개 아잉이(v0.3.59)의 고정 id. 서버 CHECK·가격표·`gacha_pool` 의 id 와 같다.
    /// 매니페스트 파일로 못 싣는 이유는 금과 같다(밑줄 id · scene3D 는 초상을 못 가진다) — 그래서 코드에 박는다.
    package static let rainbowAingID = "aing_rainbow"

    /// 코드에 박힌 무지개 아잉이 — 아잉과 **같은 3D 메시**에 무지개 마감(`CharacterManifest.Finish.rainbow`)을 입힌 변형이다.
    /// 금처럼 상점에서 살 수 없고 뽑기 · 조각 교환으로만 얻는다(서버 `character_prices.gacha_only = true` · `min_protocol = 3`).
    package static let builtInRainbowAing = CharacterManifest(
        id: rainbowAingID,
        displayName: "무지개 아잉이",
        kind: .scene3D
    )

    /// 코드에 박힌 항목 전부 — **표시 순서 그대로**(아잉, 황금 아잉이, 무지개 아잉이). 번들이 비어도 이 셋은 늘 있다.
    package static let builtIns: [CharacterManifest] = [builtInAing, builtInGoldAing, builtInRainbowAing]

    /// 이 id 가 황금 아잉이인가. 앞뒤 공백·대소문자를 봐주지 않는다(서버 값은 정확히 `aing_gold` 다).
    package static func isGoldAing(_ id: String?) -> Bool {
        id == goldAingID
    }

    /// 이 id 가 무지개 아잉이인가. 금과 같은 규칙(정확히 `aing_rainbow` 만).
    package static func isRainbowAing(_ id: String?) -> Bool {
        id == rainbowAingID
    }

    /// 카탈로그 한 칸 — 매니페스트와 그 에셋이 있는 폴더. 내장 아잉은 폴더가 없다(씬 파일은 종전 경로).
    package struct Entry: Sendable, Equatable {
        package let manifest: CharacterManifest
        package let directory: URL?
    }

    private let entries: [String: Entry]

    /// 주어진 항목들로 카탈로그를 만든다. **아잉은 항상 들어가고 항상 이긴다** —
    /// 번들이 `aing` 매니페스트를 실어 보내도 3D 아잉을 덮어쓰지 못하게 한다(폴백 대상이 스프라이트가 되면
    /// "모르는 값 → 아잉" 안전망 자체가 스프라이트 파이프라인에 의존하게 된다).
    /// 황금 아잉이(v0.3.54)·무지개 아잉이(v0.3.59)도 같은 규칙이다 — 내장 항목이 늘 이긴다.
    package init(entries: [Entry]) {
        var map: [String: Entry] = [:]
        let builtInIDs = Set(Self.builtIns.map(\.id))
        for entry in entries where !builtInIDs.contains(entry.manifest.id) {
            map[entry.manifest.id] = entry
        }
        for builtIn in Self.builtIns {
            map[builtIn.id] = Entry(manifest: builtIn, directory: nil)
        }
        self.entries = map
    }

    /// 폴더 없는 매니페스트만으로 만드는 편의 생성자(테스트·메모리 카탈로그).
    package init(manifests: [CharacterManifest]) {
        self.init(entries: manifests.map { Entry(manifest: $0, directory: nil) })
    }

    package func manifest(id: String) -> CharacterManifest? {
        entries[id]?.manifest
    }

    package func entry(id: String) -> Entry? {
        entries[id]
    }

    /// 표시 순서: **아잉 먼저, 황금 아잉이 둘째, 무지개 아잉이 셋째, 나머지는 id 정렬**. 목록이 실행마다 흔들리지 않게 정렬을 여기 한 곳에 둔다.
    /// (`aing_gold`·`aing_rainbow` 는 정렬로도 그 자리지만 — `_` 는 소문자보다 앞이다 — 그 우연에 기대지 않고 내장 순서로 박는다.)
    package var allIDs: [String] {
        let builtInIDs = Self.builtIns.map(\.id)
        return builtInIDs + entries.keys.filter { !builtInIDs.contains($0) }.sorted()
    }

    /// 아틀라스 PNG 의 절대 URL. 내장 아잉·3D 캐릭터는 nil.
    package func atlasURL(for id: String) -> URL? {
        guard let entry = entries[id], let directory = entry.directory,
              let file = entry.manifest.atlas?.file else { return nil }
        return directory.appendingPathComponent(file)
    }


    // MARK: - 로드

    private static let logger = Logger(subsystem: "kingcheck", category: "character")


    /// 디렉터리 하나를 훑어 카탈로그를 만든다(테스트가 임시 폴더를 그대로 넣는다).
    ///
    /// 규칙: 하위 폴더 이름 = 캐릭터 id. 폴더 이름과 매니페스트의 `id` 가 다르면 **건너뛴다** —
    /// 에셋은 폴더 이름으로 찾고 선택 값은 `id` 로 저장되므로, 둘이 갈리면 "목록엔 있는데 그림이 없는" 캐릭터가 된다.
    package static func load(charactersDirectory: URL?, fileManager: FileManager = .default) -> CharacterCatalog {
        guard let root = charactersDirectory else { return CharacterCatalog(entries: []) }
        let decoder = JSONDecoder()
        var loaded: [Entry] = []
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path))?.sorted() ?? []
        for name in names {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            guard isDirectory(directory, fileManager: fileManager) else { continue }
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let manifest = try decoder.decode(CharacterManifest.self, from: Data(contentsOf: manifestURL))
                guard manifest.id == name else {
                    logger.error("character manifest id mismatch folder=\(name, privacy: .public) id=\(manifest.id, privacy: .public)")
                    continue
                }
                loaded.append(Entry(manifest: manifest, directory: directory))
            } catch {
                // 한 캐릭터가 깨져도 나머지는 산다. 사용자에게는 "그 캐릭터만 목록에 없다"로 보인다.
                logger.error("character manifest unreadable folder=\(name, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
        return CharacterCatalog(entries: loaded)
    }

    /// 번들 안 캐릭터 폴더 URL. `.copy` 리소스라 `url(forResource:)` 로 잡히지만, 못 잡으면 리소스 루트에서 직접 찾는다.
    package static func directoryURL(
        in bundle: Bundle,
        named subdirectory: String = charactersSubdirectory,
        fileManager: FileManager = .default
    ) -> URL? {
        if let url = bundle.url(forResource: subdirectory, withExtension: nil),
           isDirectory(url, fileManager: fileManager) {
            return url
        }
        if let url = bundle.resourceURL?.appendingPathComponent(subdirectory, isDirectory: true),
           isDirectory(url, fileManager: fileManager) {
            return url
        }
        return nil
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
