import Foundation
import Testing

// v0.3.27 오목 테스트가 만드는 UserDefaults 스위트의 자리와 이름을 정한다.
//
// 스토어 테스트는 병렬로 돌아 **자리마다 다른 이름**이 필요하다(이름이 겹치면 한 테스트의 값이 다른 테스트로 샌다).
//
// **2026-09-22 재설계 — 이 헬퍼는 이제 `CheckTestScratch` 위에 선다.**
// 앞 판도 이름을 절대 경로(`$TMPDIR/check-v0327-defaults/...`)로 줘서 ~/Library/Preferences 로는 안 샜다.
// 그건 맞았다. 틀린 것은 두 가지였다.
//  ① **이름에 UUID 를 썼다** — 실행마다 새 파일이라 `$TMPDIR/check-v0327-defaults` 에 1,111개가 쌓였다.
//  ② **정리를 끝에 뒀다** — `forget()` 이 removePersistentDomain 과 파일 삭제를 **둘 다** 부르는데도
//     1,110개가 100바이트짜리로 살아남았고 그 안에 값이 그대로 있었다(2026-09-22 실측). cfprefsd 가
//     테스트가 끝난 뒤 자기 메모리 사본을 다시 flush 하기 때문이다 — 끝내기 경쟁은 이길 수 없다.
// 그래서 이름을 `CheckTestScratch.uniqueSuitePath` 에서 받는다: 자리는 프로세스별 스크래치 폴더
// (`CheckTestScratch.root`)이고, 이름은 **호출 지점 + 그 지점을 이번 실행에서 부른 횟수**라 개수가 유계다.
// 청소는 다음 실행이 시작할 때 `CheckTestScratch.root` 가 통째로 한다.
//
// 쓰는 법: 스위트는 `GomokuTestDefaults.make(_:)` 로 만든다. `@Test(.gomokuDefaultsCleanup)` 는 그대로
// 두어도 되지만(값을 일찍 비워 주는 보험일 뿐) 이제 파일 누적을 막는 장치는 아니다.

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

    /// 이 실행에서 유일한 스위트를 비운 채로 만든다.
    ///
    /// `prefix` 는 **이름에 들어가지 않는다.** 호출 지점을 읽는 사람에게 알려 주는 표시로만 남긴다 —
    /// 호출자 중 둘(`V0336AvatarArtTests`)이 `"v0336-bake-\(UUID()...prefix(6))"` 처럼 **난수 꼬리**를 붙여
    /// 부르기 때문에, 그 값을 파일 이름에 넣으면 실행마다 새 파일이 생겨 이 파일이 막으려는 병이 되돌아온다.
    /// 자리를 가르는 일은 `function`·`line`(=호출 지점)과 일련번호가 이미 한다. 같은 줄에서 몇 번을 불러도
    /// 서로 다른 이름이 나오고, 다음 실행은 같은 이름들을 다시 쓴다.
    ///
    /// `function`·`line` 은 **호출 지점**에서 평가되는 컴파일러 기본 인자다. 호출자 서명은 하나도 안 바뀐다.
    static func make(_ prefix: String, function: String = #function, line: Int = #line) -> UserDefaults {
        _ = prefix
        let name = CheckTestScratch.uniqueSuitePath(function: function, line: line)
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        collector?.add(name)
        return defaults
    }

    /// 스위트의 값을 비운다. **파일이 사라지는 것에 기대지 마라** — cfprefsd 가 되살린다(머리 주석 ②).
    /// 실제 누적을 막는 장치는 `CheckTestScratch.root` 의 시작 시점 청소다. 여기는 같은 프로세스 안에서
    /// 값이 새는 것을 줄이는 보험일 뿐이다.
    static func forget(_ names: [String]) {
        for name in names {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
    }
}

/// 테스트 하나를 감싸 그 안에서 만든 스위트의 값을 끝에 비운다.
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
