import Foundation
import Testing

// v0.3.27 오목 테스트가 만든 UserDefaults 스위트를 **테스트가 끝나면** 지운다.
//
// 스토어 테스트는 병렬로 돌아 테스트마다 고유 이름 스위트가 필요하다(이름이 겹치면 한 테스트의 값이 다른 테스트로 샌다).
// 그런데 지우지 않으면 실행마다 ~/Library/Preferences 에 plist 가 영구히 쌓인다(2026-09-16 실측: v0327-* 903개).
// 이름을 모으는 곳은 태스크 로컬이라 병렬 테스트끼리 서로의 목록을 건드리지 않는다.
//
// 쓰는 법: 스위트는 `GomokuTestDefaults.make(_:)` 로 만들고, 그 테스트에 `@Test(.gomokuDefaultsCleanup)` 를 단다.

enum GomokuTestDefaults {
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var names: [String] = []

        func add(_ name: String) {
            lock.lock()
            names.append(name)
            lock.unlock()
        }

        func drain() -> [String] {
            lock.lock()
            let taken = names
            names = []
            lock.unlock()
            return taken
        }
    }

    @TaskLocal static var collector: Collector?

    /// 스위트 파일을 두는 곳 — **~/Library/Preferences 가 아니다.** 스위트 이름을 절대 경로로 주면 CFPreferences 가
    /// 그 경로에 plist 를 쓴다(2026-09-16 프로브 실측: 경로 파일 생성·재읽기 성공, Preferences 로 샌 파일 0). 테스트가 끝난 뒤
    /// 붙잡혀 있는 스토어가 늦게 한 번 더 써도 사용자 설정 폴더에는 아무것도 안 남는다(그 실행에서 v0327-* 76개가 새로 샌 원인).
    static let directory: String = {
        let path = NSTemporaryDirectory() + "check-v0327-defaults"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }()

    /// 고유 이름 스위트를 비운 채로 만들고, 지금 테스트가 끝나면 지우도록 적어 둔다.
    static func make(_ prefix: String) -> UserDefaults {
        let name = "\(directory)/\(prefix)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        collector?.add(name)
        return defaults
    }

    /// 스위트를 지운다. 값을 비우고(removePersistentDomain), 디스크의 plist 도 지운다.
    static func forget(_ names: [String]) {
        for name in names {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(atPath: "\(name).plist")
        }
    }
}

/// 테스트 하나를 감싸 그 안에서 만든 스위트를 끝에 지운다.
struct GomokuDefaultsCleanup: TestTrait, TestScoping {
    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        let collector = GomokuTestDefaults.Collector()
        defer { GomokuTestDefaults.forget(collector.drain()) }
        try await GomokuTestDefaults.$collector.withValue(collector) {
            try await function()
        }
    }
}

extension Trait where Self == GomokuDefaultsCleanup {
    static var gomokuDefaultsCleanup: Self { Self() }
}
