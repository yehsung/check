import Foundation

// B3 — 소스 계약 테스트의 길잡이(테스트 전용).
//
// CheckCore 를 떼어내면서 앱 소스가 두 자리(Sources/check · Sources/CheckCore)로 나뉘었다. 이 저장소의 소스 계약 테스트는
// "Sources/check/<파일>" 을 직접 읽거나 그 폴더를 훑는데, 그대로 두면 코어로 간 파일이 **없는 파일**(빨강)이 되거나
// 폴더 훑기에서 **조용히 빠진다**(부정 단언이 공허하게 초록). 그래서 읽는 자리를 한 곳에서 바로잡는다:
//   · 파일 이름으로 읽기 → 맥 자리에 없고 코어 자리에 있으면 코어에서 읽는다(판정은 실제 파일 존재로 — 목록을 적어 두지 않는다).
//   · 폴더 훑기 → Sources/check 를 물으면 Sources/CheckCore 도 합친다.
//   · 반쪽만 옮긴 파일(쪼갠 파일) → 두 조각을 이어 읽는다(떼기 전 한 파일이던 내용 그대로).
//
// ⚠️ 쪼갠 파일은 **이름 하나로 읽지 마라** — `joinedSplitSource(_:)` 로만 읽는다. `directory(for:)` · `appendingCheckSourcePath` ·
// 글자 그대로의 경로("Sources/check/MiniGameFlappy.swift")는 조각 하나만 준다. 그러면 떼기 전 한 파일이던 내용의 반쪽만
// 검사해서 "이 파일에 X 가 없다" 같은 부정 단언이 다른 반쪽의 위반을 **조용히 통과**시킨다(B3 검증에서 실측 — V0312 의
// `#if DEBUG` 금지가 CheckTokenUsageRow.swift 쪽을 못 봤다). 이 두 도우미에 실행 중 가드를 두지 않은 까닭: 폴더 훑기 루프
// (AwayCloseTests · V0241 · V0251 · V0317 · V0322)도 같은 도우미로 조각 이름을 하나씩 읽는데, 거기서는 두 조각이 모두 목록에
// 있어 빠짐이 없다 — 실행 중에는 "훑기의 한 칸"과 "이름 하나 읽기"를 가를 수 없다. 대신 CheckCoreSourceLayoutTests 가
// 테스트 소스를 훑어, 쪼갠 파일 이름이 든 문자열 리터럴이 `joinedSplitSource(` 의 인자 말고 다른 자리에 있으면 빨개진다.
enum CheckCoreSourceLayout {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // 저장소 루트

    static var macDirectory: URL { repoRoot.appendingPathComponent("Sources/check", isDirectory: true) }
    static var coreDirectory: URL { repoRoot.appendingPathComponent("Sources/CheckCore", isDirectory: true) }

    /// 쪼갠 파일: 맥에 남은 파일 이름 → 코어로 간 조각(또는 반대로 코어 파일 → 맥에 남긴 화면 조각).
    static let splitParts: [String: [String]] = [
        "MiniGame.swift": ["Sources/check/MiniGame.swift", "Sources/CheckCore/MiniGameEngine.swift"],
        "MiniGameTimingBar.swift": ["Sources/check/MiniGameTimingBar.swift", "Sources/CheckCore/TimingBarGame.swift"],
        "MiniGameFlappy.swift": ["Sources/check/MiniGameFlappy.swift", "Sources/CheckCore/FlappyGame.swift"],
        "CheckTokenUsage.swift": ["Sources/CheckCore/CheckTokenUsage.swift", "Sources/check/CheckTokenUsageRow.swift"],
        "CheckOverlayWindow.swift": ["Sources/check/CheckOverlayWindow.swift", "Sources/CheckCore/CheckPanelVisibility.swift"],
        "CheckOverlayReactions.swift": ["Sources/check/CheckOverlayReactions.swift", "Sources/CheckCore/MilestoneTracker.swift"],
        "TodoSync.swift": ["Sources/CheckCore/TodoSync.swift", "Sources/check/TodoSyncCoordinator.swift"],
    ]

    /// 쪼갠 파일에 속하는 파일 이름 전부(떼기 전 이름 + 각 조각의 파일 이름). 이 이름들은 `joinedSplitSource(_:)` 로만 읽는다.
    static var splitFileNames: Set<String> {
        Set(splitParts.keys).union(splitParts.values.flatMap { $0.map { ($0 as NSString).lastPathComponent } })
    }

    /// 파일 이름(Sources/check 기준 상대경로)이 실제로 있는 폴더("Sources/check" 또는 "Sources/CheckCore").
    static func directory(for name: String) -> String {
        let fm = FileManager.default
        if !fm.fileExists(atPath: macDirectory.appendingPathComponent(name).path),
           fm.fileExists(atPath: coreDirectory.appendingPathComponent(name).path) {
            return "Sources/CheckCore"
        }
        return "Sources/check"
    }

    /// 쪼갠 파일의 조각들을 이어 읽는다. 쪼개지 않은 이름이면 그 파일 하나.
    static func joinedSplitSource(_ name: String) throws -> String {
        let parts = splitParts[name] ?? ["\(directory(for: name))/\(name)"]
        return try parts
            .map { try String(contentsOf: repoRoot.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }

    static func isMacDirectory(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path
            == macDirectory.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

extension URL {
    /// `appendingPathComponent(name)` 와 같다. 단 받는 쪽이 Sources/check 이고 그 파일이 코어로 갔으면 Sources/CheckCore 쪽을 준다.
    func appendingCheckSourcePath(_ name: String) -> URL {
        guard CheckCoreSourceLayout.isMacDirectory(self),
              CheckCoreSourceLayout.directory(for: name) == "Sources/CheckCore" else {
            return appendingPathComponent(name)
        }
        return CheckCoreSourceLayout.coreDirectory.appendingPathComponent(name)
    }
}

extension FileManager {
    /// `contentsOfDirectory(atPath:)` 와 같다. Sources/check 를 물으면 Sources/CheckCore 의 이름도 합친다.
    func checkSourcesContentsOfDirectory(atPath path: String) throws -> [String] {
        let names = try contentsOfDirectory(atPath: path)
        guard CheckCoreSourceLayout.isMacDirectory(URL(fileURLWithPath: path, isDirectory: true)) else { return names }
        let core = (try? contentsOfDirectory(atPath: CheckCoreSourceLayout.coreDirectory.path)) ?? []
        return names + core.filter { !names.contains($0) }
    }

    /// `contentsOfDirectory(at:includingPropertiesForKeys:options:)` 와 같다. Sources/check 를 물으면 Sources/CheckCore 도 합친다.
    func checkSourcesContentsOfDirectory(
        at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        let urls = try contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
        guard CheckCoreSourceLayout.isMacDirectory(url) else { return urls }
        let core = (try? contentsOfDirectory(at: CheckCoreSourceLayout.coreDirectory, includingPropertiesForKeys: keys, options: options)) ?? []
        return urls + core
    }

    /// `enumerator(at:includingPropertiesForKeys:options:)` 와 같다(하위 폴더까지 URL 을 낸다). Sources/check 를 물으면
    /// Sources/CheckCore 아래 URL 도 이어 낸다 — 코어 파일은 맥 폴더 밖이라 "맥 폴더 기준 상대경로"를 셈하는 쪽은 파일 이름으로 받는다.
    func checkSourcesEnumerator(
        at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: FileManager.DirectoryEnumerationOptions = []
    ) -> NSEnumerator? {
        guard let mac = enumerator(at: url, includingPropertiesForKeys: keys, options: options) else { return nil }
        guard CheckCoreSourceLayout.isMacDirectory(url) else { return mac }
        var all = mac.allObjects
        if let core = enumerator(at: CheckCoreSourceLayout.coreDirectory, includingPropertiesForKeys: keys, options: options) {
            all += core.allObjects
        }
        return (all as NSArray).objectEnumerator()
    }

    /// `enumerator(atPath:)` 와 같다(상대경로를 낸다). Sources/check 를 물으면 Sources/CheckCore 의 상대경로도 이어 낸다.
    func checkSourcesEnumerator(atPath path: String) -> NSEnumerator? {
        guard let mac = enumerator(atPath: path) else { return nil }
        guard CheckCoreSourceLayout.isMacDirectory(URL(fileURLWithPath: path, isDirectory: true)) else { return mac }
        var all = mac.allObjects.compactMap { $0 as? String }
        if let core = enumerator(atPath: CheckCoreSourceLayout.coreDirectory.path) {
            let seen = Set(all)
            all += core.allObjects.compactMap { $0 as? String }.filter { !seen.contains($0) }
        }
        return (all as NSArray).objectEnumerator()
    }
}
