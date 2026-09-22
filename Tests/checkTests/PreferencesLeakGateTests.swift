import Foundation
import Testing

// ~/Library/Preferences 누수 회귀 게이트 (2026-09-22 사고 이후).
//
// **무엇을 막는가** — 테스트가 만든 UserDefaults plist 가 ~/Library/Preferences 에 62만 개까지 쌓여
// cfprefsd 가 **모든 도메인 서빙을 멈췄다.** Finder·Dock·앱이 설정을 못 읽었고, 앱은 기기 ID 를 잃어
// 새 UUID 로 유령 기기를 만들어 같은 달치를 또 올렸다 — 순위표 토큰이 129억 → 258억으로 2배가 됐다.
// 기전은 단순하다: 스위트 이름이 평범한 도메인 이름(`check-tests-<UUID>`)이면 plist 가
// ~/Library/Preferences 로 떨어지고, 이름에 UUID 가 섞이면 **실행마다 새 파일**이라 O(실행 × 테스트)로 는다.
// 정답은 `CheckTestScratch`: 스위트 이름을 **절대 경로**로 줘서 $TMPDIR 로 보내고, 이름을 테스트 신원에서
// 뽑아 개수를 유계로 만든다.
//
// ---------------------------------------------------------------------------------------------
// **설계 근거 — 왜 게이트가 둘인가**
//
// 이 파일은 단언을 두 개 건다. 하나는 실행 중 측정, 하나는 소스 검사다. 둘 다 필요하다.
//
// ① `scratchSuitesAddNothingToLibraryPreferences` — **실행 중** ~/Library/Preferences 의 항목이 느는지 본다.
//    이게 지키는 것은 **헬퍼 자신**이다. `CheckTestScratch` 가 언젠가 "경로 말고 이름"으로 되돌아가면
//    (또는 CFPreferences 가 경로 이름을 다르게 해석하게 되면) 이 단언이 바로 빨개진다.
//    한계가 분명하다: swift-testing 은 **테스트 순서를 보장하지 않는다.** "다른 테스트가 다 끝난 뒤"를
//    가정할 수 없으므로, 이 단언이 실제로 보는 것은 **이 테스트가 자기 손으로 만든 스위트**뿐이다.
//    다른 파일이 옛 관용구를 되살려도 이 단언이 그걸 볼지는 스케줄 운이다.
//
// ② `noTestSourceNamesADefaultsSuiteThatLandsInLibraryPreferences` — **소스 전체**를 훑어 스위트 이름이
//    나오는 자리를 전부 검사한다. 순서와 무관하고, `--filter` 로 그 파일을 안 돌려도 잡는다.
//    **되주입을 실제로 빨갛게 만드는 것은 이쪽이다.** ①만 두면 게이트는 장식이 된다.
//
// ---------------------------------------------------------------------------------------------
// **왜 접두사로 안 좁히는가** — `-name 'check-*'` 로만 세다가 바로 옆 `com.yehsung.aingcheck.scratch.*`
// **98,609개**를 두 번이나 못 봤다. 접두사를 열거하면 다음에 새 접두사가 생길 때 또 못 본다.
// 그래서 ①은 폴더의 **전체 항목**을 찍고(글롭 없음), ②는 이름을 만드는 **자리**를 검사한다(접두사 목록 없음).
//
// **왜 개수 차이가 아니라 "새로 생긴 이름 집합"인가** — 전체 항목 수만 비교하면 같은 창에서 하나가 지워지고
// 하나가 생길 때 0 으로 상쇄되어 **누수가 초록으로 숨는다.** 집합 차이는 그 경우에도 잡고, 빨개질 때
// **어떤 접두사가 샜는지 이름으로 말해 준다** — 위의 98,609개를 두 번 놓친 이유가 정확히 "이름을 안 봤다"였다.
//
// **병렬 오탐을 어떻게 줄이는가** — 이 스위트는 `.serialized` 다(이 파일 안 두 테스트가 서로를 안 흔든다).
// 하지만 `.serialized` 는 **다른 스위트의 병렬 실행까지 막지는 못한다.** 같은 프로세스에서 도는 남의 테스트가
// 마침 이 창 안에서 도메인을 하나 만들면 오탐이다(예: 모바일 쪽 `AingSharedStorage.temporary(name: "demo")` 는
// 이름이 고정이라 프로세스당 한 번만 새 항목이 될 수 있다). 그래서 **회차를 여러 번 돌고 최솟값**으로 건다:
// 한 회차는 수십 밀리초라, 남의 1회성 쓰기가 세 회차에 **모두** 걸릴 일은 사실상 없다. 반대로 진짜 누수는
// 회차마다 반복되므로 최솟값도 0 이 아니다.
//
// **최솟값이 못 보는 것(알고 남긴 구멍)** — "고정 이름 하나가 딱 한 번 새는" 누수는 1회차에만 새 항목으로
// 보이고 2·3회차엔 이미 그 파일이 있어 안 보인다. 최솟값이 0 이 되어 ①은 초록이다. 그 자리를 두 장치가 메운다:
//  · ①이 스위트를 **열기 전에** 이름이 스크래치 절대 경로인지 `#require` 로 먼저 막는다(아래 ★).
//    던져서 끝내므로 **Preferences 에 한 줄도 안 남기고** 빨개진다 — 회차 통계와 무관한 결정적 그물이다.
//  · 고정 이름 리터럴 자체는 ②가 소스에서 잡는다.
// 즉 ①의 회차 통계는 "유계가 아닌 누수"를 잡는 그물이고, 유계 누수는 나머지 둘이 맡는다.
//
// **왜 창을 닫기 전에 CFPreferencesSynchronize 를 부르는가** — cfprefsd 는 쓰기를 미뤘다가 나중에 flush 한다
// (이 사고의 핵심도 그거였다: `removePersistentDomain` 으로 지운 파일이 테스트가 끝난 뒤 값을 품은 채 1,110개
// 되살아났다). 미뤄진 쓰기를 창 안으로 끌어와야 "after" 가 진실이 된다.
//
// **왜 "파일이 실제로 생겼나"까지 보는가** — 아무것도 안 쓰는 워크로드는 영원히 초록이다(기준선이 같은 입력이면
// 그 테스트는 장식이다). 그래서 회차마다 스크래치 폴더에 plist 가 **실제로 떨어졌는지** 함께 단언한다.

@Suite(.serialized)
struct PreferencesLeakGateTests {

    /// ① 스크래치 헬퍼로 스위트를 잔뜩 만들어 써도 ~/Library/Preferences 에 새 항목이 하나도 안 생긴다.
    @Test
    func scratchSuitesAddNothingToLibraryPreferences() throws {
        // 폴더를 잘못 보고 있으면(경로 오타·샌드박스) 빈 목록이 되어 단언이 공허하게 초록이 된다.
        let sanity = try plgPreferencesEntries()
        #expect(sanity.contains(".GlobalPreferences.plist"),
                "~/Library/Preferences 를 못 읽고 있다(항목 \(sanity.count)개) — 이 단언은 공허하다: \(plgPreferencesDirectory.path)")

        let rounds = 3
        let suitesPerRound = 8
        let rootPrefix = CheckTestScratch.root.path + "/"
        var added: [Set<String>] = []
        var landed: [Int] = []

        for round in 0..<rounds {
            let before = try plgPreferencesEntries()
            var expectedFiles: [String] = []

            for index in 0..<suitesPerRound {
                let label = "r\(round)-\(index)"

                // 갈래 ㉮ — 테스트 신원에서 이름을 뽑는 기본 경로. (`function:` 를 안 넘기고 테스트 본문에서
                // 직접 부른다 — 그래야 #function 이 이 테스트가 되어 다른 파일과 이름이 안 겹친다.)
                //
                // ★ 스위트를 **열기 전에** 이름 모양을 먼저 막는다. `#require` 는 던져서 테스트를 그 자리에서
                //   끝내므로, 헬퍼가 평범한 이름으로 되돌아가도 **~/Library/Preferences 에 한 줄도 안 남기고**
                //   빨개진다. 아래 경험적 단언(집합 차이)은 이걸 통과한 뒤의 두 번째 그물이다 —
                //   이름이 경로여도 CFPreferences 쪽에서 새기 시작하면 그건 저 그물만 잡는다.
                let byFunctionPath = CheckTestScratch.suitePath(label)
                try #require(byFunctionPath.hasPrefix(rootPrefix),
                             "CheckTestScratch.defaults 의 스위트 이름이 스크래치 절대 경로가 아니다: \(byFunctionPath)")
                let byFunction = CheckTestScratch.defaults(label)
                byFunction.set("v-\(round)-\(index)", forKey: "plgValue")
                byFunction.synchronize()
                expectedFiles.append(byFunctionPath + ".plist")

                // 갈래 ㉯ — 옛 고정 이름("check-…")의 1:1 교체 문. 이름이 유계여도 Preferences 로 새면 안 된다.
                let fixed = CheckTestScratch.suitePath(named: "check-preferences-leak-gate-\(index)")
                try #require(fixed.hasPrefix(rootPrefix),
                             "CheckTestScratch.suitePath(named:) 가 스크래치 절대 경로를 안 준다: \(fixed)")
                let byFixedName = try #require(UserDefaults(suiteName: fixed))
                byFixedName.set(round, forKey: "plgValue")
                byFixedName.synchronize()
                expectedFiles.append(fixed + ".plist")

                // 갈래 ㉰ — 옛 UUID 자리의 1:1 교체 문. 사고를 일으킨 바로 그 자리다.
                let unique = CheckTestScratch.uniqueSuitePath(label)
                try #require(unique.hasPrefix(rootPrefix),
                             "CheckTestScratch.uniqueSuitePath 가 스크래치 절대 경로를 안 준다: \(unique)")
                let byUniqueName = try #require(UserDefaults(suiteName: unique))
                byUniqueName.set(round, forKey: "plgValue")
                byUniqueName.synchronize()
                expectedFiles.append(unique + ".plist")
            }

            // 미뤄진 쓰기를 창 안으로 끌어온다(머리 주석 참고). 실패해도 단언을 흔들지 않는다 — 보수적으로
            // 더 많이 보일 뿐이라 누수를 놓치는 쪽으로는 안 기운다.
            _ = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

            let after = try plgPreferencesEntries()
            added.append(after.subtracting(before))
            landed.append(expectedFiles.filter { FileManager.default.fileExists(atPath: $0) }.count)
        }

        // 최솟값 회차 = 남의 병렬 쓰기가 가장 덜 섞인 회차. 진짜 누수는 회차마다 반복되므로 여기서도 안 사라진다.
        let quietest = added.min(by: { $0.count < $1.count }) ?? []
        #expect(quietest.isEmpty, """
            스크래치 스위트가 ~/Library/Preferences 에 새 항목을 남겼다(회차별 \(added.map(\.count)) 개).
            가장 조용한 회차에 생긴 이름 \(quietest.count)개 중 앞 10개: \(quietest.sorted().prefix(10).joined(separator: ", "))
            → 스위트 이름이 절대 경로가 아니게 됐다는 뜻이다. CheckTestScratch 를 보라.
            """)

        // 워크로드가 진짜로 plist 를 만들었는가. 안 만들었다면 위 단언은 아무것도 안 지킨 채 초록이다.
        let expectedPerRound = suitesPerRound * 3
        #expect(landed.allSatisfy { $0 == expectedPerRound }, """
            스크래치 폴더에 plist 가 안 떨어졌다(회차별 \(landed) / 기대 \(expectedPerRound)).
            아무것도 안 쓰는 워크로드는 누수도 못 만들므로 위 단언이 공허해진다.
            스크래치 뿌리: \(CheckTestScratch.root.path)
            """)
    }

    /// ② 테스트 소스 어디에도 "평범한 이름의 스위트"를 만드는 자리가 없다. 순서와 무관한 진짜 게이트다.
    @Test
    func noTestSourceNamesADefaultsSuiteThatLandsInLibraryPreferences() throws {
        // 맥 타깃만 훑으면 안 된다 — 두 타깃이 한 프로세스에서 돌고, 새는 폴더는 어차피 하나다.
        let testsRoot = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Tests", isDirectory: true)
        let files = try plgSwiftSources(under: testsRoot)
        #expect(files.count > 50, "테스트 소스를 못 찾았다(\(files.count)개) — 이 단언은 공허하다: \(testsRoot.path)")

        // 주석을 반드시 걷어낸다. 이 저장소의 주석에는 옛 관용구가 **설명으로** 적혀 있다
        // (CheckTestScratch.swift 머리말의 `UserDefaults(suiteName: "check-…")`). 안 걷으면 설명을
        // 지워야만 초록이 되는 테스트가 된다.
        let sources: [(name: String, code: String)] = try files.map {
            (name: $0.path.replacingOccurrences(of: CheckCoreSourceLayout.repoRoot.path + "/", with: ""),
             code: plgStripComments(try String(contentsOf: $0, encoding: .utf8)))
        }

        // **두 번 훑는 이유** — 스위트를 여는 문은 `UserDefaults(suiteName:` 하나가 아니다. `UserDefaults` 를
        // 상속한 대역도 같은 생성자를 물려받고, 그 이름으로 부르면 통짜 마커에 안 걸린다. 2026-09-22 프로브로
        // 실측했다: 어느 타깃에도 안 속하는 파일에 `final class ProbeDefaults: UserDefaults {}` 와
        // `ProbeDefaults(suiteName: "check-leakprobe-…")` 를 놓자 이 단언이 **초록**이었다. 저장소에도 그 꼴이
        // 산다(`V0336DeviceIdentityVaultTests` 의 Id*Defaults 셋). 그래서 먼저 상속 이름을 모으고, 그 이름들로
        // 문을 만든다. (여기서 모은 이름은 파일 전체에서 모은다 — 대역이 선언된 파일과 쓰는 파일이 다를 수 있다.)
        let suiteTypes = plgUserDefaultsSubclasses(in: sources.map(\.code))
        // 수집기가 상속을 실제로 보는지 **합성 조각**으로 못 박는다. 저장소에서 대역이 다 사라져도 이 단언은 산다
        // (기준선이 같은 입력이면 그 테스트는 영원히 초록이다). 아래 두 이름은 이 리터럴 안에만 있으므로
        // 마커가 하나 더 생겨도 걸릴 자리가 없다.
        let synthetic = "private final class PlgSampleDefaults: UserDefaults {}\nfinal class PlgDeepDefaults: PlgSampleDefaults {}"
        let sampled = plgUserDefaultsSubclasses(in: [synthetic])
        #expect(sampled.isSuperset(of: ["PlgSampleDefaults", "PlgDeepDefaults"]), """
            상속 수집기가 멎었다(합성 조각에서 \(sampled.sorted())) — 대역 생성자를 못 보면 이 게이트는 장식이다.
            """)
        var violations: [String] = []
        var checkedSuiteSites = 0

        for (name, code) in sources {
            // (가) UserDefaults(와 그 대역) 스위트를 여는 자리.
            for site in plgSuiteCallSites(in: code, types: suiteTypes) {
                checkedSuiteSites += 1
                let arg = String(site.argument.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                let at = "\(name):\(site.line)"

                if arg.contains("\"") && !arg.hasPrefix("\"/") {
                    violations.append("\(at) 스위트 이름에 문자열 리터럴 `\(arg)` — 절대 경로가 아니면 ~/Library/Preferences 로 떨어진다. CheckTestScratch 를 거쳐라.")
                    continue
                }
                if arg.contains("UUID") {
                    violations.append("\(at) 스위트 이름에 UUID `\(arg)` — 실행마다 새 파일이라 무한히 쌓인다. CheckTestScratch.uniqueSuitePath 를 써라.")
                    continue
                }
                guard plgIsIdentifier(arg) else {
                    violations.append("\(at) 스위트 이름이 추적 불가능한 식 `\(arg)` — CheckTestScratch 가 만든 경로를 변수에 담아 넘겨라.")
                    continue
                }
                // 식별자는 한 칸만 되짚는다: 같은 파일 안에서 스크래치 헬퍼로부터 묶였거나, 호출자에게서
                // 경로를 받는 `String` 파라미터여야 한다. 파라미터는 여기서 더 못 쫓는다 — 대신 그 호출자의
                // 리터럴이 (가)의 첫 규칙에 걸린다.
                let bindings = plgBindings(of: arg, in: code)
                if bindings.contains(where: { rhs in plgScratchProducers.contains(where: rhs.contains) }) { continue }
                if bindings.isEmpty && plgLooksLikeStringParameter(arg, in: code) { continue }
                violations.append("\(at) `\(arg)` 가 어디서 왔는지 추적이 안 된다 — CheckTestScratch 가 만든 절대 경로여야 한다.")
            }

            // (나) 모바일의 다른 갈래. `AingSharedStorage.temporary(name:)` 는 이름에서 `/` 를 걸러내
            // 스위트를 ~/Library/Preferences 로 돌려보낸다(`com.yehsung.aingcheck.scratch.*` — 우리가 두 번
            // 못 본 98,609개가 이 가족이다). 지금 남은 자리는 이름이 고정이라 유계다. 그 유계를 못으로 박는다:
            // 이름이 리터럴이고 아래 목록에 있어야 한다. 새 이름이나 보간(`"\(...)"`)은 곧 무계라는 뜻이다.
            for site in plgCallSites(of: plgTemporaryMarker, in: code) {
                let arg = String(site.argument.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                if plgBoundedTemporaryNames.contains(arg) { continue }
                violations.append("\(name):\(site.line) 공유 저장소 임시 이름 `\(arg)` — 이 문은 스위트를 ~/Library/Preferences 로 돌려보낸다. MobileTestScratch.storage 를 써라.")
            }
        }

        #expect(checkedSuiteSites > 20, "스위트를 여는 자리를 \(checkedSuiteSites)개밖에 못 찾았다 — 스캐너가 소스를 제대로 못 읽고 있다.")
        #expect(violations.isEmpty, """
            테스트 소스가 ~/Library/Preferences 에 떨어지는 스위트를 만든다(\(violations.count)곳):
            \(violations.joined(separator: "\n"))
            """)
    }
}

// MARK: - 도우미

private let plgPreferencesDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    .appendingPathComponent("Library/Preferences", isDirectory: true)

/// 폴더의 **전체 항목** 이름(글롭 없음 — 머리 주석의 "접두사로 안 좁힌다" 참고). `find -maxdepth 1` 과 같은 범위다.
private func plgPreferencesEntries() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: plgPreferencesDirectory.path))
}

/// 스위트 이름이 스크래치에서 왔다고 볼 수 있는 표식. 파일 안에서 `suitePath(`/`uniqueSuitePath(` 를 한정 없이
/// 부르는 자리는 `CheckTestScratch`·`MobileTestScratch` 본문뿐이라 함께 둔다.
private let plgScratchProducers = ["CheckTestScratch.", "MobileTestScratch.", "suitePath(", "uniqueSuitePath("]

/// 찾는 문(門)들. **이 파일도 스캔 대상이라** 조각을 이어 붙여 만든다 — 통짜 리터럴로 적으면 스캐너가
/// 자기 마커 정의를 호출 자리로 착각해 스스로를 고발한다(첫 실행에서 실제로 그랬다). 스위트 쪽 마커는
/// `plgUserDefaultsSubclasses` 가 모은 타입 이름마다 하나씩 만들어진다(`<타입>(suiteName:`).
/// 이 파일 안의 **진짜** 호출 자리(①이 여는 스위트 둘)는 그대로 검사를 받는다 — 게이트가 자기만 면제받으면
/// 그게 다음 구멍이다.
private let plgTemporaryMarker = ".temporary(name" + ":"

/// 테스트 소스에서 `UserDefaults` 를 상속한 타입 이름을 모은다(고정점 — 손자 대역까지).
///
/// **왜 이름을 모으는가** — 마커를 `(suiteName:` 통짜로 넓히면 애먼 자리가 걸린다: 선언
/// (`func inertTokenStore(suiteName: String)`)·튜플 라벨(`-> (suiteName: String, …)`)·**이름을 본문에서 접는**
/// 헬퍼 호출(`inertTokenStore(suiteName: suiteName)` — `fixedDefaults` 가 접는다)까지 위반이 된다.
/// 타입 이름으로 문을 좁히면 그 오탐 없이 대역 생성자만 더 본다.
///
/// **알고 남긴 구멍** — 적용되지 않은 참조(`IdBlindDefaults.init(suiteName:)` 를 `idDouble` 에 넘기는 꼴)는
/// 이름이 여기 안 나타나므로 못 본다. 지금 그 자리(5곳)는 `idDouble` 본문이 `CheckTestScratch.suitePath` 로
/// 접어서 안전하고, 그 접힘이 풀리면 이 스캐너가 아니라 ①의 회차 통계가 잡아야 한다.
private func plgUserDefaultsSubclasses(in sources: [String]) -> Set<String> {
    guard let pattern = try? NSRegularExpression(pattern: "class\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*([^{\\n]+)") else {
        return ["UserDefaults"]
    }
    var edges: [(child: String, parents: [String])] = []
    for code in sources {
        let text = code as NSString
        for match in pattern.matches(in: code, range: NSRange(location: 0, length: text.length)) {
            let child = text.substring(with: match.range(at: 1))
            let parents = text.substring(with: match.range(at: 2))
                .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
                .map(String.init)
            edges.append((child, parents))
        }
    }
    var known: Set<String> = ["UserDefaults"]
    var changed = true
    while changed {                       // 고정점: `B: A` 가 `A: UserDefaults` 보다 먼저 나와도 다음 바퀴에 잡힌다.
        changed = false
        for edge in edges where !known.contains(edge.child) && edge.parents.contains(where: known.contains) {
            known.insert(edge.child)
            changed = true
        }
    }
    return known
}

/// `AingSharedStorage.temporary(name:)` 에 아직 남아 있는 **유계 이름**. 늘리지 마라 — 늘리는 순간
/// ~/Library/Preferences 항목이 그만큼 는다. (2026-09-22 실측: 살아 있는 자리는 `"demo"` 둘뿐.)
private let plgBoundedTemporaryNames: Set<String> = ["\"demo\""]

private struct PLGCallSite {
    let line: Int
    let argument: String
}

/// `<타입>(suiteName:` 자리를 **한 번의 훑기로** 모은다.
///
/// 타입마다 파일을 다시 읽으면 타입 수만큼 느려진다(실측 2026-09-22: 마커를 7개로 늘리자 2.6초 → 10.2초).
/// 그리고 여는 괄호 **앞의 식별자**를 보는 편이 마커를 이어 붙이는 것보다 정확하다: `(suiteName:` 통짜로
/// 넓혔을 때 걸리던 선언(`func inertTokenStore(suiteName: String)`)과 튜플 라벨
/// (`-> (suiteName: String, …)`)은 앞 식별자가 타입 이름이 아니라서 여기서 저절로 빠진다.
private func plgSuiteCallSites(in code: String, types: Set<String>) -> [PLGCallSite] {
    let chars = Array(code)
    let needle = Array("(suiteName" + ":")
    var sites: [PLGCallSite] = []
    var line = 1
    var i = 0
    while i < chars.count {
        if chars[i] == "\n" { line += 1 }
        if i + needle.count <= chars.count, Array(chars[i..<(i + needle.count)]) == needle {
            var head = i
            while head > 0, chars[head - 1].isLetter || chars[head - 1].isNumber || chars[head - 1] == "_" {
                head -= 1
            }
            if types.contains(String(chars[head..<i])) {
                sites.append(PLGCallSite(line: line, argument: plgFirstArgument(chars, from: i + needle.count)))
            }
            i += needle.count   // 이 조각엔 줄 바꿈이 없다 — 건너뛰어도 줄 번호가 안 어긋난다.
            continue
        }
        i += 1
    }
    return sites
}

/// `marker` 로 시작하는 호출의 **첫 인자**를 괄호 균형을 맞춰 떼어 온다. 줄 번호는 1부터.
private func plgCallSites(of marker: String, in code: String) -> [PLGCallSite] {
    let chars = Array(code)
    let needle = Array(marker)
    var sites: [PLGCallSite] = []
    var line = 1
    var i = 0
    while i < chars.count {
        if chars[i] == "\n" { line += 1 }
        if i + needle.count <= chars.count, Array(chars[i..<(i + needle.count)]) == needle {
            sites.append(PLGCallSite(line: line, argument: plgFirstArgument(chars, from: i + needle.count)))
            i += needle.count
            continue
        }
        i += 1
    }
    return sites
}

/// 여는 괄호 안쪽에서 시작해 같은 깊이의 `,` 또는 닫는 `)` 까지.
private func plgFirstArgument(_ chars: [Character], from start: Int) -> String {
    var depth = 1
    var inString = false
    var escaped = false
    var out = ""
    var i = start
    while i < chars.count {
        let c = chars[i]
        if inString {
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            out.append(c)
        } else {
            if c == "\"" { inString = true; out.append(c) }
            else if c == "(" || c == "[" || c == "{" { depth += 1; out.append(c) }
            else if c == ")" || c == "]" || c == "}" {
                depth -= 1
                if depth == 0 { return out }
                out.append(c)
            } else if c == "," && depth == 1 { return out }
            else { out.append(c) }
        }
        i += 1
    }
    return out
}

private func plgIsIdentifier(_ text: String) -> Bool {
    guard let first = text.unicodeScalars.first else { return false }
    guard CharacterSet.letters.contains(first) || first == "_" else { return false }
    return text.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
}

/// 같은 파일에서 `name` 에 무엇을 대입하는지(`let x = …` · `var x: T = …` · `x = …` · `self.x = …) 모은다.
/// 오른쪽은 줄 끝까지만 본다 — 스크래치 호출은 `CheckTestScratch.suitePath(` 까지가 같은 줄에 있다.
private func plgBindings(of name: String, in code: String) -> [String] {
    var out: [String] = []
    for rawLine in code.split(separator: "\n", omittingEmptySubsequences: false) {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("let ") { line = String(line.dropFirst(4)) }
        else if line.hasPrefix("var ") { line = String(line.dropFirst(4)) }
        line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("self.") { line = String(line.dropFirst(5)) }
        guard line.hasPrefix(name) else { continue }
        var rest = String(line.dropFirst(name.count))
        // 뒤에 식별자 글자가 이어지면 이름이 다른 것이다(`suite` 를 찾는데 `suiteName` 줄이 걸리는 일 방지).
        if let head = rest.unicodeScalars.first, CharacterSet.alphanumerics.contains(head) || head == "_" { continue }
        rest = rest.trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix(":") {                       // `x: String = …` — 타입 표기를 건너뛴다
            guard let equals = rest.firstIndex(of: "=") else { continue }   // `let x: String` (선언만) 은 대입이 아니다
            rest = String(rest[rest.index(after: equals)...])
        } else if rest.hasPrefix("=") && !rest.hasPrefix("==") {
            rest = String(rest.dropFirst())
        } else {
            continue
        }
        out.append(rest)
    }
    return out
}

/// `(_ name: String` · `, name: String` 꼴의 파라미터인가. 묶인 자리가 하나도 없을 때만 묻는다.
/// (여기서 더는 못 쫓는다 — 대신 그 호출자가 리터럴을 주면 (가)의 첫 규칙이 잡는다.)
private func plgLooksLikeStringParameter(_ name: String, in code: String) -> Bool {
    let chars = Array(code)
    let needle = Array("\(name): String")
    var i = 0
    while i + needle.count <= chars.count {
        if Array(chars[i..<(i + needle.count)]) == needle {
            let before = i > 0 ? chars[i - 1] : " "
            if !(before.isLetter || before.isNumber || before == "_") { return true }
        }
        i += 1
    }
    return false
}

private func plgSwiftSources(under root: URL) throws -> [URL] {
    guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
    var out: [URL] = []
    for case let url as URL in walker where url.pathExtension == "swift" { out.append(url) }
    return out.sorted { $0.path < $1.path }
}

/// `//` · `/* */` 주석을 걷어낸다. 문자열 리터럴 안의 `//` 는 남기고, **줄 바꿈은 전부 보존한다**
/// (줄 번호가 원본과 같아야 위반을 file:line 으로 가리킬 수 있다).
private func plgStripComments(_ source: String) -> String {
    var out = ""
    var inString = false, inLine = false, inBlock = false, escaped = false
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "\n" { out.append(c) }
            if c == "*", next == "/" { inBlock = false; i += 1 }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; i += 1
        } else if c == "/", next == "*" {
            inBlock = true; i += 1
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        i += 1
    }
    return out
}
