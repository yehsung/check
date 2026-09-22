import Foundation
import Testing
import CheckMobileShared

// ~/Library/Preferences 누수 회귀 게이트 — **모바일 런타임 쪽**(2026-09-22 사고 이후).
//
// **왜 맥 쪽 게이트만으로 부족한가** — `checkTests/PreferencesLeakGateTests` 의 두 단언 중
// 실행 중 측정(①)은 `CheckTestScratch` 만 본다. 그리고 그 파일은 checkTests 타깃에만 있어
// **모바일 타깃을 단독으로 돌리면 아예 없다**(`swift test --filter <모바일 테스트>`). 그러면 모바일의
// 스크래치 축(`MobileTestScratch`)을 지키는 것은 소스 스캔 하나뿐인데, 소스 스캔은 "이름이 어떻게
// 만들어지는가"만 본다 — `MobileTestScratch` 자신이 언젠가 "경로 말고 이름"으로 되돌아가거나
// CFPreferences 가 경로 이름을 다르게 해석하게 되면 소스는 그대로인 채 새기 시작한다. 그 자리를 이 파일이 맡는다.
//
// 성질은 맥 ①과 같다(근거는 그 파일 머리 주석에 길게 적혀 있다 — 여기선 결론만):
//  · 폴더의 **전체 항목 이름 집합**을 찍는다(글롭·접두사 목록 없음 — `com.yehsung.aingcheck.scratch.*`
//    98,609개를 두 번 놓친 이유가 정확히 "접두사로 좁혀 봤다"였다).
//  · **회차를 여러 번 돌고 최솟값**으로 건다(같은 프로세스에서 병렬로 도는 남의 1회성 쓰기를 오탐으로
//    안 삼키려고). 진짜 누수는 회차마다 반복되므로 최솟값에서도 안 사라진다.
//  · 스위트를 **열기 전에** 이름이 스크래치 절대 경로인지 `#require` 로 먼저 막는다 — 던져서 끝내므로
//    Preferences 에 한 줄도 안 남기고 빨개지는 결정적 그물이다(실측: 이 줄을 평범한 이름으로 바꾸면
//    이 테스트가 빨개지고, 막지 않았다면 Preferences 항목이 하나 늘었을 자리다).
//  · 워크로드가 진짜로 plist 를 만들었는지 함께 단언한다 — 아무것도 안 쓰면 누수도 못 만들어 위 단언이 공허해진다.
//
// **모바일만의 갈래** — 여기선 두 문을 다 연다: `MobileTestScratch.defaults`(맨 UserDefaults)와
// `MobileTestScratch.storage`(모바일이 실제로 쓰는 `AingSharedStorage`). 후자는 스위트를 못 열면
// **조용히 `.standard` 로 접는데**, 그러면 쓰기가 이 프로세스의 표준 도메인으로 흘러 Preferences 에
// 새 항목을 만든다. 접혔는지도 여기서 못으로 박는다.

@Suite(.serialized)
struct MobilePreferencesLeakGateTests {

    /// 모바일 스크래치로 저장소를 만들어 써도 ~/Library/Preferences 에 새 항목이 하나도 안 생긴다.
    @Test
    func mobileScratchStoragesAddNothingToLibraryPreferences() throws {
        // 폴더를 잘못 보고 있으면(경로 오타·샌드박스) 빈 목록이 되어 단언이 공허하게 초록이 된다.
        let sanity = try mplgPreferencesEntries()
        #expect(sanity.contains(".GlobalPreferences.plist"),
                "~/Library/Preferences 를 못 읽고 있다(항목 \(sanity.count)개) — 이 단언은 공허하다: \(mplgPreferencesDirectory.path)")

        let rounds = 3
        let pairsPerRound = 4
        let rootPrefix = MobileTestScratch.root.path + "/"
        var added: [Set<String>] = []
        var landed: [Int] = []

        for round in 0..<rounds {
            let before = try mplgPreferencesEntries()
            var expectedFiles: [String] = []

            for index in 0..<pairsPerRound {
                let label = "r\(round)-\(index)"

                // 갈래 ㉮ — 맨 UserDefaults. (`function:` 를 안 넘기고 테스트 본문에서 직접 부른다 —
                // 그래야 #function 이 이 테스트가 되어 다른 파일과 이름이 안 겹친다.)
                let suite = MobileTestScratch.suiteName(label)
                try #require(suite.hasPrefix(rootPrefix),
                             "MobileTestScratch 의 스위트 이름이 스크래치 절대 경로가 아니다: \(suite)")
                let defaults = MobileTestScratch.defaults(label)
                defaults.set("v-\(round)-\(index)", forKey: "mplgValue")
                defaults.synchronize()
                expectedFiles.append(suite + ".plist")

                // 갈래 ㉯ — 모바일이 실제로 쓰는 문(AingSharedStorage).
                let storageLabel = "\(label)-storage"
                let storageSuite = MobileTestScratch.suiteName(storageLabel)
                try #require(storageSuite.hasPrefix(rootPrefix),
                             "MobileTestScratch.storage 의 스위트 이름이 스크래치 절대 경로가 아니다: \(storageSuite)")
                let storage = MobileTestScratch.storage(storageLabel)
                #expect(storage.defaultsSuiteName == storageSuite)
                // 스위트를 못 열면 `.standard` 로 접고, 그때 쓰기는 이 프로세스의 표준 도메인 — 즉 Preferences 로 간다.
                #expect(storage.defaults != UserDefaults.standard,
                        "공유 저장소가 .standard 로 접혔다 — 이 쓰기는 ~/Library/Preferences 로 간다: \(storageSuite)")
                storage.defaults.set(round, forKey: "mplgValue")
                storage.defaults.synchronize()
                expectedFiles.append(storageSuite + ".plist")
            }

            // 미뤄진 쓰기를 창 안으로 끌어온다(cfprefsd 는 flush 를 미룬다). 실패해도 단언을 흔들지 않는다 —
            // 보수적으로 더 많이 보일 뿐이라 누수를 놓치는 쪽으로는 안 기운다.
            _ = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

            let after = try mplgPreferencesEntries()
            added.append(after.subtracting(before))
            landed.append(expectedFiles.filter { FileManager.default.fileExists(atPath: $0) }.count)
        }

        // 최솟값 회차 = 남의 병렬 쓰기가 가장 덜 섞인 회차.
        let quietest = added.min(by: { $0.count < $1.count }) ?? []
        #expect(quietest.isEmpty, """
            모바일 스크래치 저장소가 ~/Library/Preferences 에 새 항목을 남겼다(회차별 \(added.map(\.count)) 개).
            가장 조용한 회차에 생긴 이름 \(quietest.count)개 중 앞 10개: \(quietest.sorted().prefix(10).joined(separator: ", "))
            → 스위트 이름이 절대 경로가 아니게 됐다는 뜻이다. MobileTestScratch 를 보라.
            """)

        // 워크로드가 진짜로 plist 를 만들었는가. 안 만들었다면 위 단언은 아무것도 안 지킨 채 초록이다.
        let expectedPerRound = pairsPerRound * 2
        #expect(landed.allSatisfy { $0 == expectedPerRound }, """
            스크래치 폴더에 plist 가 안 떨어졌다(회차별 \(landed) / 기대 \(expectedPerRound)).
            아무것도 안 쓰는 워크로드는 누수도 못 만들므로 위 단언이 공허해진다.
            스크래치 뿌리: \(MobileTestScratch.root.path)
            """)
    }
}

// MARK: - 도우미

private let mplgPreferencesDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    .appendingPathComponent("Library/Preferences", isDirectory: true)

/// 폴더의 **전체 항목** 이름(글롭 없음). `find ~/Library/Preferences -maxdepth 1` 과 같은 범위다.
private func mplgPreferencesEntries() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: mplgPreferencesDirectory.path))
}
