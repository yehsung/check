import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - Semver 비교 (접두/자릿수/프리릴리스 규칙)

@Test
func semverComparisonHandlesPrefixDigitsAndPrerelease() {
    // "v" 접두 허용 · 정상 대소.
    #expect(SemverCompare.isNewer("1.2.3", than: "v0.2.1"))
    #expect(SemverCompare.isNewer("v0.3.0", than: "0.2.1"))
    #expect(!SemverCompare.isNewer("v0.2.1", than: "0.2.1")) // 동일 → 아님
    #expect(!SemverCompare.isNewer("0.2.0", than: "0.2.1")) // 더 낮음 → 아님

    // 자릿수 차이는 짧은 쪽을 0 패딩해 비교: "0.3" > "0.2.9", "1.0" == "1.0.0".
    #expect(SemverCompare.isNewer("0.3", than: "0.2.9"))
    #expect(!SemverCompare.isNewer("1.0", than: "1.0.0"))
    #expect(!SemverCompare.isNewer("1.0.0", than: "1.0"))

    // 프리릴리스("-")·빌드메타("+")는 절단하고 수치 코어만 비교한다(프리릴리스 무시 규칙):
    //  - "1.2.3-beta" 는 코어가 "1.2.3" 과 같으므로 업데이트로 보지 않는다(오탐 넛지 방지).
    //  - 코어가 더 높으면("1.2.4-rc.1") 프리릴리스여도 더 높게 본다.
    #expect(!SemverCompare.isNewer("1.2.3-beta.1", than: "1.2.3"))
    #expect(SemverCompare.isNewer("1.2.4-rc.1", than: "1.2.3"))
    #expect(!SemverCompare.isNewer("1.2.3", than: "1.2.3+build.5"))

    // 파싱 실패는 false(오탐 방지 — 형식이 이상하면 조용히 '업데이트 없음').
    #expect(!SemverCompare.isNewer("garbage", than: "1.0.0"))
    #expect(!SemverCompare.isNewer("1.0.0", than: "not-a-version"))
    #expect(SemverCompare.components("nope") == nil)
    #expect(SemverCompare.components("v0.2.1") == [0, 2, 1])
    #expect(SemverCompare.components("1.2.3-beta") == [1, 2, 3])
}

// MARK: - 릴리스 JSON 파싱 (실 API 필드명과 일치)

@Test
func parseTagExtractsTagNameFromReleaseJSON() {
    // 실 GitHub 응답 형태(v0.2.1)와 동일한 필드명(tag_name)에서 태그만 뽑는다.
    let real = Data(#"{"tag_name":"v0.2.1","name":"aing-check 0.2.1","prerelease":false}"#.utf8)
    #expect(UpdateCheckStore.parseTag(real) == "v0.2.1")
    // 형식 오류/누락/빈 값은 nil(조용히).
    #expect(UpdateCheckStore.parseTag(Data("not json".utf8)) == nil)
    #expect(UpdateCheckStore.parseTag(Data(#"{"name":"x"}"#.utf8)) == nil)
    #expect(UpdateCheckStore.parseTag(Data(#"{"tag_name":""}"#.utf8)) == nil)
}

// MARK: - 패치노트 파싱 (불릿만 취함 · 마크다운 제거 · 4줄 상한)

@Test
func parseNotesKeepsOnlyBulletLinesAsPlainText() {
    // GitHub 릴리스 본문 그대로(CRLF + 헤딩 + 설치 안내 산문). 불릿 줄만 항목이 되고 기호는 떨어진다.
    let body = "## 0.2.14\r\n\r\n- 새 버전 안내에 **바뀐 내용**이 보여요\r\n* `brew upgrade` 없이 눌러서 업데이트해요\r\n\r\n설치: brew tap yehsung/check && brew install --cask aing-check\r\n"
    #expect(UpdateCheckStore.parseNotes(body) == [
        "새 버전 안내에 바뀐 내용이 보여요",
        "brew upgrade 없이 눌러서 업데이트해요"
    ])

    // 노트가 없는 경우는 모두 빈 배열(옛 릴리스/필드 누락/산문만 있는 본문) — 배너는 노트 없이 그려진다.
    #expect(UpdateCheckStore.parseNotes(nil).isEmpty)
    #expect(UpdateCheckStore.parseNotes("").isEmpty)
    #expect(UpdateCheckStore.parseNotes("aing-check 0.2.9 배포. 설치: brew tap ...").isEmpty)
    // 불릿만 있고 내용이 비면 버린다(기호를 뗀 뒤 빈 줄).
    #expect(UpdateCheckStore.parseNotes("- \n-  \n").isEmpty)
}

@Test
func parseNotesCapsAtFourLinesWithRemainderCount() {
    let five = (1...5).map { "- 항목\($0)" }.joined(separator: "\n")
    // 4줄을 넘으면 앞 3줄 + 남은 개수(총 4줄) — 팝오버 높이 보호.
    #expect(UpdateCheckStore.parseNotes(five) == ["항목1", "항목2", "항목3", "외 2건"])
    // 정확히 4줄이면 그대로 4줄(대체 없음).
    let four = (1...4).map { "- 항목\($0)" }.joined(separator: "\n")
    #expect(UpdateCheckStore.parseNotes(four) == ["항목1", "항목2", "항목3", "항목4"])
    #expect(UpdateCheckStore.parseNotes(five).count == UpdateCheckStore.maxNotes)
}

@Test
func parseBodyReadsOptionalBodyFieldSafely() {
    #expect(UpdateCheckStore.parseBody(Data(#"{"tag_name":"v0.3.0","body":"- 한 줄"}"#.utf8)) == "- 한 줄")
    // body 누락(옛 릴리스)·형식 오류는 nil — parseTag 는 그대로 동작해야 한다(노트만 없는 상태).
    #expect(UpdateCheckStore.parseBody(Data(#"{"tag_name":"v0.3.0"}"#.utf8)) == nil)
    #expect(UpdateCheckStore.parseBody(Data("not json".utf8)) == nil)
    #expect(UpdateCheckStore.parseTag(Data(#"{"tag_name":"v0.3.0"}"#.utf8)) == "v0.3.0")
}

// MARK: - 노트 영속 (버전과 한 쌍 · 재실행 복원)

@MainActor
@Test
func latestNotesPersistWithVersionAndRestoreOnRelaunch() async {
    let defaults = isolatedUpdateDefaults()
    let base = Date(timeIntervalSince1970: 5_000_000)
    let json = Data(#"{"tag_name":"v0.3.0","body":"- 첫 줄\n- 둘째 줄"}"#.utf8)

    let store = UpdateCheckStore(
        currentVersion: "0.2.1",
        fetcher: FetchRecorder(.success(json)).fetch,
        clock: { base },
        defaults: defaults
    )
    await store.checkIfStale()
    #expect(store.latestVersion == "v0.3.0")
    #expect(store.latestNotes == ["첫 줄", "둘째 줄"])

    // 앱 재실행 재현: 같은 defaults 로 새 스토어 + 24h 스로틀 안(네트워크 미접촉)에서도 배너 재료가 남아 있다.
    let recorder = FetchRecorder(.success(json))
    let relaunched = UpdateCheckStore(
        currentVersion: "0.2.1",
        fetcher: recorder.fetch,
        clock: { base.addingTimeInterval(3_600) },
        defaults: defaults
    )
    #expect(relaunched.latestVersion == "v0.3.0")
    #expect(relaunched.latestNotes == ["첫 줄", "둘째 줄"])
    #expect(relaunched.isUpdateAvailable)
    await relaunched.checkIfStale()
    #expect(recorder.count == 0) // 스로틀 유지 — 복원이 네트워크를 새로 유발하지 않는다.
}

@MainActor
@Test
func latestNotesAreEmptyForReleaseWithoutBody() async {
    // 노트 없이 만든 옛 릴리스: 버전만 채워지고 노트는 빈 배열(배너는 예전 모습 그대로).
    let store = makeUpdateStore(current: "0.2.1", tag: "v0.3.0")
    await store.checkIfStale()
    #expect(store.latestVersion == "v0.3.0")
    #expect(store.latestNotes.isEmpty)
}

// MARK: - 24h 스로틀 (주입 clock)

@MainActor
@Test
func updateCheckThrottlesToOncePerDay() async {
    var now = Date(timeIntervalSince1970: 1_000_000)
    let recorder = FetchRecorder(.success(tagJSON("v9.9.9")))
    let store = UpdateCheckStore(
        currentVersion: "0.2.1",
        fetcher: recorder.fetch,
        clock: { now },
        defaults: isolatedUpdateDefaults()
    )

    // 최초(미기록)는 신선하지 않으므로 1회 조회하고 latestVersion 을 채운다.
    await store.checkIfStale()
    #expect(recorder.count == 1)
    #expect(store.latestVersion == "v9.9.9")
    #expect(store.isUpdateAvailable)

    // 같은 날(24h 이내) 재호출은 스로틀로 조회하지 않는다(도배 오픈에도 하루 1회).
    now = now.addingTimeInterval(23 * 3_600)
    await store.checkIfStale()
    #expect(recorder.count == 1)

    // 24h 를 넘기면 다시 1회 조회한다.
    now = now.addingTimeInterval(2 * 3_600) // 누적 25h
    await store.checkIfStale()
    #expect(recorder.count == 2)
}

// MARK: - fetch 스텁: 성공 / 실패 / 형식 오류

@MainActor
@Test
func updateCheckReflectsAvailabilityBySemverOnSuccess() async {
    // 최신==현재 → 업데이트 없음.
    let same = makeUpdateStore(current: "0.2.1", tag: "v0.2.1")
    await same.checkIfStale()
    #expect(same.latestVersion == "v0.2.1")
    #expect(!same.isUpdateAvailable)

    // 최신>현재 → 업데이트 있음.
    let newer = makeUpdateStore(current: "0.2.1", tag: "v0.3.0")
    await newer.checkIfStale()
    #expect(newer.isUpdateAvailable)
}

@MainActor
@Test
func updateCheckIgnoresFailureSilentlyAndStampsThrottle() async {
    struct Boom: Error {}
    var now = Date(timeIntervalSince1970: 2_000_000)
    let recorder = FetchRecorder(.failure(Boom()))
    let store = UpdateCheckStore(
        currentVersion: "0.2.1",
        fetcher: recorder.fetch,
        clock: { now },
        defaults: isolatedUpdateDefaults()
    )

    // 실패는 조용히 무시: latestVersion 미변경, 업데이트 없음. 하지만 시도 스탬프는 찍혀 재시도를 스로틀한다.
    await store.checkIfStale()
    #expect(recorder.count == 1)
    #expect(store.latestVersion == nil)
    #expect(!store.isUpdateAvailable)

    now = now.addingTimeInterval(3_600) // 1h 뒤 재호출 → 스로틀로 재조회 안 함.
    await store.checkIfStale()
    #expect(recorder.count == 1)
}

@MainActor
@Test
func updateCheckIgnoresMalformedResponseSilently() async {
    let recorder = FetchRecorder(.success(Data("<<not json>>".utf8)))
    let store = UpdateCheckStore(
        currentVersion: "0.2.1",
        fetcher: recorder.fetch,
        clock: { Date(timeIntervalSince1970: 3_000_000) },
        defaults: isolatedUpdateDefaults()
    )
    await store.checkIfStale()
    #expect(recorder.count == 1)
    #expect(store.latestVersion == nil)
    #expect(!store.isUpdateAvailable)
}

// MARK: - 말풍선 버전당 1회 (영속 기록)

@MainActor
@Test
func bubbleShowsOncePerVersionAndReArmsOnNewerVersion() async {
    let defaults = isolatedUpdateDefaults()
    let base = Date(timeIntervalSince1970: 4_000_000)

    let store = UpdateCheckStore(
        currentVersion: "0.2.1",
        fetcher: FetchRecorder(.success(tagJSON("v0.3.0"))).fetch,
        clock: { base },
        defaults: defaults
    )
    await store.checkIfStale()
    #expect(store.isUpdateAvailable)

    // 첫 요청은 true → 기록 → 이후 같은 버전은 false(도배 금지).
    #expect(store.shouldShowBubble())
    store.markBubbleShown()
    #expect(!store.shouldShowBubble())

    // 더 높은 새 버전이 감지되면 다시 true(영속 기록은 버전별). 같은 defaults 를 공유하는 새 스토어로,
    // 스로틀을 넘긴 시각에서 v0.4.0 을 조회한다.
    let next = UpdateCheckStore(
        currentVersion: "0.2.1",
        fetcher: FetchRecorder(.success(tagJSON("v0.4.0"))).fetch,
        clock: { base.addingTimeInterval(48 * 3_600) },
        defaults: defaults
    )
    await next.checkIfStale()
    #expect(next.latestVersion == "v0.4.0")
    #expect(next.shouldShowBubble())
}

@MainActor
@Test
func bubbleNeverShowsWhenNoUpdateAvailable() async {
    let store = makeUpdateStore(current: "0.3.0", tag: "v0.3.0")
    await store.checkIfStale()
    #expect(!store.isUpdateAvailable)
    #expect(!store.shouldShowBubble())
}

// MARK: - UpdateRunner 출처 탐지 (brew 가 **이 번들을** 관리하는가)

/// brew 로 깔린 상태를 꾸민 러너. 실제 파일시스템을 보지 않는다.
///
/// 꾸미는 것은 세 가지다: `<prefix>/bin/brew` 가 있고, `<prefix>/Caskroom/aing-check` 에 버전 폴더가 있고,
/// 그 안의 staged 앱 심링크가 **지금 돌고 있는 번들**을 가리킨다. 실측된 실물 구조와 같다 —
/// `/opt/homebrew/Caskroom/aing-check/0.3.48/aing-check/aing-check.app → /Applications/aing-check.app`.
@MainActor
private func makeBrewRunner(
    prefix: String = "/opt/homebrew",
    caskroomPrefix: String? = nil,
    bundle: String = "/Applications/aing-check.app",
    version: String = "0.3.48",
    spawn: @escaping (String) -> Bool = { _ in true },
    spawnDMG: @escaping (UpdateRunner.DMGUpdatePlan) -> Bool = { _ in
        Issue.record("brew 경로인데 DMG 스크립트를 스폰했다")
        return false
    },
    watchdogSleep: @escaping @Sendable (Double) async -> Void = { _ in }
) -> UpdateRunner {
    let cr = caskroomPrefix ?? prefix
    let staged = "\(cr)/Caskroom/aing-check/\(version)/aing-check/aing-check.app"
    return UpdateRunner(
        fileExists: { $0 == "\(prefix)/bin/brew" },
        // `.metadata` 를 함께 돌려준다 — 숨김 항목을 건너뛰는지 같이 재기 위해서다.
        directoryContents: { $0 == "\(cr)/Caskroom/aing-check" ? [version, ".metadata"] : [] },
        resolvePath: { $0 == staged ? bundle : $0 },
        isWritable: { _ in true },
        bundlePath: bundle,
        processID: 4242,
        currentBuild: 100,
        readState: { _ in nil },
        clearState: { _ in },
        spawn: spawn,
        spawnDMG: spawnDMG,
        watchdogSleep: watchdogSleep
    )
}

/// 직접(DMG·zip) 깔린 상태를 꾸민 러너. **brew 실행파일은 있다고 꾸민다** — 그게 고치려는 결함의 조건이다
/// (DMG 로 설치하는 사람은 대개 개발자이고 그 맥에는 brew 가 거의 다 있다).
@MainActor
private func makeStandaloneRunner(
    bundle: String = "/Applications/aing-check.app",
    writable: Bool = true,
    currentBuild: Int? = 100,
    state: String? = nil,
    spawnDMG: @escaping (UpdateRunner.DMGUpdatePlan) -> Bool = { _ in true },
    spawn: @escaping (String) -> Bool = { _ in
        Issue.record("직접 설치인데 brew 를 스폰했다")
        return false
    },
    watchdogSleep: @escaping @Sendable (Double) async -> Void = { _ in }
) -> UpdateRunner {
    UpdateRunner(
        fileExists: { _ in true },               // brew 는 있다
        directoryContents: { _ in [] },          // 그런데 이 앱을 깐 기록은 없다
        resolvePath: { $0 },
        isWritable: { _ in writable },
        bundlePath: bundle,
        processID: 4242,
        currentBuild: currentBuild,
        readState: { _ in state },
        clearState: { _ in },
        spawn: spawn,
        spawnDMG: spawnDMG,
        watchdogSleep: watchdogSleep
    )
}

@MainActor
@Test
func installSourceIsBrewOnlyWhenBrewManagesThisBundle() {
    let runner = makeBrewRunner()
    #expect(runner.installSource == .brew)
    #expect(runner.managingBrewPrefix == "/opt/homebrew")
    #expect(runner.brewPath == "/opt/homebrew/bin/brew")
}

// 이것이 고치려는 결함의 핵심이다. brew 는 깔려 있지만 **이 앱을 깐 적이 없다**(Caskroom 기록이 없다).
// 예전 코드는 brew 실행파일만 보고 `brew upgrade --cask aing-check` 를 던졌고, 그 명령은
// "설치되지 않았다"로 끝나 배너가 600초 뒤 실패로 떨어졌다. 이제 DMG 경로를 타야 한다.
@MainActor
@Test
func brewPresentButNeverInstalledThisAppTakesTheDMGPath() {
    var dmgSpawns = 0
    let runner = makeStandaloneRunner(spawnDMG: { _ in dmgSpawns += 1; return true })
    #expect(runner.installSource == .standalone)
    #expect(runner.brewPath == nil)
    runner.runUpgrade()
    #expect(dmgSpawns == 1)
    #expect(runner.status == .running)
}

// Caskroom 이 있는지만 보면 틀리는 경우. brew 로 /Applications 에 깔아 쓰던 사람이 DMG 를 받아
// ~/Applications 에 두고 **그쪽을** 실행하면, brew 는 돌고 있지 않은 사본을 올린다 —
// 돌고 있는 앱은 영원히 안 바뀌는데 배너는 같은 새 버전을 계속 권한다(조용한 영구 실패).
@MainActor
@Test
func brewManagingADifferentCopyIsNotThisBundle() {
    var dmgSpawns = 0
    let runner = UpdateRunner(
        fileExists: { $0 == "/opt/homebrew/bin/brew" },
        directoryContents: { $0 == "/opt/homebrew/Caskroom/aing-check" ? ["0.3.48"] : [] },
        // staged 심링크는 /Applications 를 가리키는데 우리는 ~/Applications 에서 돌고 있다.
        resolvePath: { $0.contains("/Caskroom/") ? "/Applications/aing-check.app" : $0 },
        isWritable: { _ in true },
        bundlePath: "/Users/me/Applications/aing-check.app",
        currentBuild: 100,
        clearState: { _ in },
        spawn: { _ in Issue.record("돌고 있지 않은 사본을 brew 로 올리려 했다"); return false },
        spawnDMG: { _ in dmgSpawns += 1; return true },
        watchdogSleep: { _ in }
    )
    #expect(runner.installSource == .standalone)
    runner.runUpgrade()
    #expect(dmgSpawns == 1)
}

// brew 실행파일과 Caskroom 은 **같은 접두사**에서 나와야 한다 — Caskroom 위치는 HOMEBREW_PREFIX 에 묶여 있다.
// 짝이 어긋나면(ARM 맥에 Rosetta Intel brew 가 함께 깔린 경우) 엉뚱한 brew 에게 엉뚱한 설치를 올리라고 시킨다.
@MainActor
@Test
func brewBinaryAndCaskroomMustSharePrefix() {
    // Intel 쪽에만 둘 다 있으면 그 접두사를 쓴다.
    let intel = makeBrewRunner(prefix: "/usr/local")
    #expect(intel.managingBrewPrefix == "/usr/local")
    #expect(intel.brewPath == "/usr/local/bin/brew")

    // 짝이 어긋나면(brew 는 /opt/homebrew, 기록은 /usr/local) brew 경로를 쓰지 않는다.
    let mismatched = makeBrewRunner(
        prefix: "/opt/homebrew",
        caskroomPrefix: "/usr/local",
        spawnDMG: { _ in true }
    )
    #expect(mismatched.installSource == .standalone)
    #expect(mismatched.brewPath == nil)
}

// 두 후보 목록이 어긋나면 짝 판정이 조용히 무너진다 — 그래서 실행파일 목록은 접두사에서 파생한다.
@Test
func brewCandidatesDeriveFromPrefixCandidates() {
    #expect(UpdateRunner.brewPrefixCandidates == ["/opt/homebrew", "/usr/local"])
    #expect(UpdateRunner.brewCandidates == ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
    for (prefix, brew) in zip(UpdateRunner.brewPrefixCandidates, UpdateRunner.brewCandidates) {
        #expect(brew == "\(prefix)/bin/brew")
    }
}

// cask 스탠자가 `app "aing-check.app"` 로 단순해지면 staged 경로에서 중간 폴더가 사라진다.
// 한 모양만 보면 그때 판정이 조용히 .standalone 으로 기울어 brew 사용자가 DMG 경로를 탄다.
@MainActor
@Test
func stagedBundleIsFoundWithOrWithoutTheExtraFolder() {
    let flat = "/opt/homebrew/Caskroom/aing-check/0.3.48/aing-check.app"
    let runner = UpdateRunner(
        fileExists: { $0 == "/opt/homebrew/bin/brew" },
        directoryContents: { $0 == "/opt/homebrew/Caskroom/aing-check" ? ["0.3.48"] : [] },
        resolvePath: { $0 == flat ? "/Applications/aing-check.app" : $0 },
        isWritable: { _ in true },
        bundlePath: "/Applications/aing-check.app",
        clearState: { _ in },
        spawn: { _ in true },
        spawnDMG: { _ in Issue.record("brew 경로여야 한다"); return false },
        watchdogSleep: { _ in }
    )
    #expect(runner.installSource == .brew)
}

// MARK: - UpdateRunner brew 경로 무회귀 (예전과 **똑같이** 동작해야 한다)

@Test
func copyCommandIsExact() {
    // 폴백 복사 문자열은 **원클릭이 실제로 실행하는 명령과 같아야 한다**.
    // 예전 문자열(`brew upgrade aing-check`)은 탭이 낡았을 때 조용히 "이미 최신"으로 끝나
    // 사용자가 손으로 실행해도 똑같이 실패했다 — 폴백이 폴백 구실을 못 했다.
    #expect(UpdateRunner.copyCommand == "brew update && brew upgrade --cask aing-check")
}

// 원클릭이 실제로 던지는 명령이 (1) brew update 를 **먼저** 하고 (2) --cask 를 명시하는지 문자열로 못박는다.
// (1)이 없으면 HOMEBREW_AUTO_UPDATE_SECS 스로틀 창 안에 있는 사용자는 낡은 탭으로 upgrade 를 돌려
// 새 버전을 못 본 채 끝나고, 앱은 죽지 않아 배너가 "업데이트 중…"으로 굳는다(실사용 신고 증상).
@Test
func upgradeScriptUpdatesTapFirstAndTargetsTheCask() {
    // 프로덕션 스폰이 만드는 **실제 스크립트 문자열**을 본다. 테스트가 문자열을 재조립하면
    // 소스를 되돌려도 초록이라 아무것도 못 잡는다.
    let script = UpdateRunner.upgradeScript(brew: "/opt/homebrew/bin/brew")

    let updateAt = script.range(of: "brew\" update")
    let upgradeAt = script.range(of: "brew\" upgrade")
    #expect(updateAt != nil)
    #expect(upgradeAt != nil)
    // 순서가 뒤집히면 낡은 탭으로 upgrade 가 돌아 새 버전을 못 본다.
    if let u = updateAt, let g = upgradeAt { #expect(u.lowerBound < g.lowerBound) }
    // 이름만 주면 brew 가 포뮬러를 먼저 찾는다 — 동명 포뮬러가 생기면 엉뚱한 것을 올린다.
    #expect(script.contains("upgrade --cask \(UpdateRunner.caskName)"))
    // 실패 원인을 볼 수 있어야 한다 — /dev/null 로 버리면 지원이 불가능하다.
    #expect(!script.contains("/dev/null"))
    #expect(script.contains(UpdateRunner.logPath))
    // 앱 종료에도 살아남아야 한다(cask 의 quit 스탠자가 이 앱을 죽인다).
    #expect(script.hasPrefix("nohup "))
    #expect(script.hasSuffix("&"))
}

// running 은 종착역이 아니다. 업그레이드가 실제로 일어나면 cask 의 quit 스탠자가 앱을 죽이므로
// 감시가 발화할 기회가 없다 — 발화했다는 건 업그레이드가 안 일어났다는 뜻이고, 그때는 failed 로 내려
// 폴백 안내 + 재시도를 열어 줘야 한다. 예전엔 running 을 벗어나는 경로가 하나도 없어 영구히 굳었다.
@MainActor
@Test
func runningFallsBackToFailedWhenUpgradeNeverHappens() async {
    let runner = makeBrewRunner()            // watchdogSleep 이 시한을 즉시 통과시킨다
    let task = runner.runUpgrade()
    #expect(runner.status == .running)
    await task?.value
    #expect(runner.status == .failed)

    // 그리고 다시 누를 수 있어야 한다(재시도 가능 = 이 수리의 핵심).
    var respawned = 0
    let retry = makeBrewRunner(spawn: { _ in respawned += 1; return true })
    await retry.runUpgrade()?.value
    #expect(retry.status == .failed)
    await retry.runUpgrade()?.value      // failed 상태에서 재시도가 실제로 스폰된다
    #expect(respawned == 2)
}

// brew 경로는 폴링하지 않는다 — 표식을 남기지 않으므로 1초마다 깨어나면 600번 헛일이고,
// 그 경로의 동작은 실전에서 잘 돌고 있어 바꿀 이유가 없다. 시한 한 번만 자는지 못박는다.
@MainActor
@Test
func brewPathSleepsTheWatchdogOnceNotPollingEverySecond() async {
    final class Naps: @unchecked Sendable { var values: [Double] = [] }
    let naps = Naps()
    let runner = makeBrewRunner(watchdogSleep: { naps.values.append($0) })
    await runner.runUpgrade()?.value
    #expect(naps.values == [UpdateRunner.watchdogSeconds])
}

// 대조군: 업그레이드가 정상적으로 일어나 앱이 곧 종료될 경우, 감시가 성급하게 failed 로 내리면 안 된다.
@MainActor
@Test
func runningStaysWhileWatchdogHasNotElapsed() async {
    let runner = makeBrewRunner(watchdogSleep: { _ in try? await Task.sleep(for: .seconds(60)) })
    let task = runner.runUpgrade()
    defer { task?.cancel() }
    #expect(runner.status == .running)
    #expect(runner.status == .running)
}

@MainActor
@Test
func updateRunnerRunsWhenBrewPresentAndSpawnSucceeds() {
    var spawnedWith: String?
    let runner = makeBrewRunner(spawn: { spawnedWith = $0; return true })
    runner.runUpgrade()
    #expect(runner.status == .running)
    #expect(spawnedWith == "/opt/homebrew/bin/brew")

    // running 중 재호출은 무시(중복 스폰 금지).
    var secondSpawn = false
    let runner2 = makeBrewRunner(spawn: { _ in secondSpawn = true; return true })
    runner2.runUpgrade()
    secondSpawn = false
    runner2.runUpgrade()
    #expect(!secondSpawn)
    #expect(runner2.status == .running)
}

@MainActor
@Test
func updateRunnerFailsWhenSpawnFails() {
    let runner = makeBrewRunner(spawn: { _ in false })
    runner.runUpgrade()
    #expect(runner.status == .failed)
}

// MARK: - 직접 설치(standalone) 전제 조건 — 못 바꿀 자리면 **받지도 않는다**

// DMG 배포에서 가장 흔한 사용 오류가 '응용 프로그램 폴더로 끌지 않고 바로 두 번 클릭'이다.
// 그러면 번들은 읽기 전용 자리(DMG 볼륨 또는 App Translocation)에 있고, 교체는 임시 사본을
// 갈아치우고 끝난다 — 사용자는 업데이트됐다고 믿지만 다음 실행이면 사라진다.
@MainActor
@Test
func standaloneRefusesToUpdateFromAReadOnlyLocation() {
    for path in [
        "/Volumes/aing-check/aing-check.app",
        "/private/var/folders/x1/abc/d/AppTranslocation/UUID/d/aing-check.app",
        "/private/var/folders/x1/abc/T/aing-check.app",
    ] {
        var spawns = 0
        let runner = makeStandaloneRunner(bundle: path, spawnDMG: { _ in spawns += 1; return true })
        #expect(runner.isRunningFromReadOnlyLocation, "읽기 전용으로 봐야 한다: \(path)")
        runner.runUpgrade()
        #expect(runner.status == .unavailable)
        #expect(spawns == 0, "받아 봐야 버리는 30MB 를 받지 않는다: \(path)")
    }
}

// 일반(비 admin) 사용자는 /Applications 에 쓸 수 없다(실측: root:admin drwxrwxr-x).
// 스크립트에 맡기면 28.5MB 를 **다 받은 뒤** 복사 단계에서야 실패한다(실측) — 미리 보고 즉시 알린다.
@MainActor
@Test
func standaloneRefusesWhenParentFolderIsNotWritable() {
    var spawns = 0
    let runner = makeStandaloneRunner(writable: false, spawnDMG: { _ in spawns += 1; return true })
    #expect(!runner.canReplaceBundle)
    runner.runUpgrade()
    #expect(runner.status == .unavailable)
    #expect(spawns == 0)
}

@MainActor
@Test
func standaloneSpawnsWhenTheBundleCanBeReplaced() {
    var spawns = 0
    let runner = makeStandaloneRunner(spawnDMG: { _ in spawns += 1; return true })
    #expect(runner.canReplaceBundle)
    #expect(!runner.isRunningFromReadOnlyLocation)
    runner.runUpgrade()
    #expect(spawns == 1)
    #expect(runner.status == .running)
}

@MainActor
@Test
func standaloneFailsWhenSpawnFails() {
    let runner = makeStandaloneRunner(spawnDMG: { _ in false })
    runner.runUpgrade()
    #expect(runner.status == .failed)
}

// MARK: - DMG 계획: 값은 **전부** 위치 인자로 간다(셸 주입 불가)

// 번들 경로는 사용자가 정하는 값이다(앱을 어느 폴더에 끌어다 놓았는지). 기존 brew 경로처럼
// `zsh -c '…경로…'` 로 끼워 넣으면 폴더 이름의 작은 인용 하나가 스크립트를 끊고 그 뒤가 명령이 된다 —
// 그리고 이 스크립트에는 `rm -rf` 가 들어 있다. 래퍼에 보간이 없다는 것이 그 방어의 전부다.
@Test
func dmgSpawnWrapperInterpolatesNothing() {
    let wrapper = UpdateRunner.dmgSpawnWrapper
    // 위치 인자만 쓴다. $1 은 스크립트 본문, $8 은 로그 경로.
    #expect(wrapper == #"nohup zsh -c "$1" aing-check-update "$2" "$3" "$4" "$5" "$6" "$7" >>"$8" 2>&1 &"#)
    // 경로·주소·요구사항이 **글자로** 들어 있으면 그게 곧 주입 경로다.
    #expect(!wrapper.contains("/Applications"))
    #expect(!wrapper.contains("https://"))
    #expect(!wrapper.contains("kingcheck"))
    #expect(!wrapper.contains("Library"))
    // 앱이 죽어도 살아남아야 한다(이 스크립트가 바로 그 앱을 종료시킨다).
    #expect(wrapper.hasPrefix("nohup "))
    #expect(wrapper.hasSuffix("&"))
}

// 인자 순서가 스크립트의 $1…$6 과 한 자리씩 어긋나면 경로 자리에 주소가 들어가는 식으로 조용히 틀린다.
@MainActor
@Test
func dmgPlanPassesEachValueInItsOwnSlot() throws {
    // 일부러 악의적인 경로를 쓴다 — 어떤 글자가 와도 **한 토막 그대로** 넘어가야 한다.
    let nasty = "/Users/김예성/It's \"My\" Apps; rm -rf ~/x $(whoami)/aing-check.app"
    let runner = makeStandaloneRunner(bundle: nasty)
    let plan = try #require(runner.dmgUpdatePlan())

    #expect(plan.script == UpdateRunner.dmgUpdateScript)
    #expect(plan.arguments.count == 9)
    #expect(plan.arguments[0] == "aing-check-update")       // argv0 (스크립트 안의 $0)
    #expect(plan.arguments[1] == UpdateRunner.dmgUpdateScript)
    #expect(plan.arguments[2] == nasty)                     // $1 번들 경로 — 손대지 않은 그대로
    #expect(plan.arguments[3] == UpdateRunner.dmgURL)        // $2
    #expect(plan.arguments[4] == "4242")                     // $3 PID
    #expect(plan.arguments[5] == UpdateRunner.codeRequirement) // $4
    #expect(plan.arguments[6] == "100")                      // $5 내 build
    #expect(plan.arguments[7] == UpdateRunner.statePath)      // $6
    #expect(plan.arguments[8] == UpdateRunner.logPath)        // $7(래퍼의 $8)
}

// 하드코딩된 appPath 를 쓰면 앱을 ~/Applications 에 끌어다 놓은 사람의 교체가 엉뚱한 곳을 노린다.
@MainActor
@Test
func dmgPlanTargetsTheResolvedRunningBundleNotTheHardcodedPath() throws {
    let runner = makeStandaloneRunner(bundle: "/Users/me/Applications/aing-check.app")
    let plan = try #require(runner.dmgUpdatePlan())
    #expect(plan.arguments[2] == "/Users/me/Applications/aing-check.app")
    #expect(plan.arguments[2] != UpdateRunner.appPath)
}

// 내 build 를 모르면(개발 빌드) **아무것도 하지 않는다**. 0 으로 때우면 스크립트의 `GOT > MIN` 비교가
// 아무 build 든 통과시켜 다운그레이드 차단이 통째로 꺼진다. 그리고 실측으로 테스트 호스트 번들
// (`checkPackageTests.xctest`)에는 CFBundleVersion 이 **없다** — `?? 0` 을 두면 스폰을 안 박은 테스트가
// 실제 스크립트를 띄워 아무 build 나 받아 테스트 번들을 갈아치울 수 있었다.
@MainActor
@Test
func unknownOwnBuildRefusesToSelfUpdateInsteadOfAcceptingAnyBuild() {
    var spawns = 0
    let runner = makeStandaloneRunner(currentBuild: nil, spawnDMG: { _ in spawns += 1; return true })
    #expect(runner.dmgUpdatePlan() == nil)
    #expect(!runner.hasKnownBuild)
    // 다른 두 사유와 구별돼야 한다 — 배너가 "권한이 없어요"를 기본값으로 쓰면 거짓말이 된다.
    #expect(runner.canReplaceBundle)
    #expect(!runner.isRunningFromReadOnlyLocation)
    runner.runUpgrade()
    #expect(runner.status == .unavailable)
    #expect(spawns == 0)
}

// 지난 시도의 실패 표식이 남아 있으면 누르자마자 거짓 실패 문구가 뜬다 — 스폰 **직전에** 지워야 한다.
@MainActor
@Test
func standaloneClearsTheStaleStateFileBeforeSpawning() {
    var cleared: [String] = []
    var spawnedAfterClearing = false
    let runner = UpdateRunner(
        fileExists: { _ in true },
        directoryContents: { _ in [] },
        resolvePath: { $0 },
        isWritable: { _ in true },
        bundlePath: "/Applications/aing-check.app",
        processID: 4242,
        currentBuild: 100,
        readState: { _ in "error=download code=6\n" },     // 지난주의 실패가 남아 있다
        clearState: { cleared.append($0) },
        spawn: { _ in Issue.record("brew 가 아니다"); return false },
        spawnDMG: { _ in spawnedAfterClearing = !cleared.isEmpty; return true },
        watchdogSleep: { _ in }
    )
    runner.runUpgrade()
    #expect(cleared == [UpdateRunner.statePath])
    #expect(spawnedAfterClearing, "상태 파일을 지우기 **전에** 스폰했다")
}

// MARK: - DMG 스크립트 계약 (프로덕션 상수를 직접 검사한다)

/// 프로덕션 스크립트 상수. 테스트가 문자열을 재조립하면 소스를 되돌려도 초록이라 회귀를 못 잡는다.
private let dmgScript = UpdateRunner.dmgUpdateScript

/// 스크립트 안에서 어떤 글자가 처음 나오는 자리(없으면 nil). 순서 단언에 쓴다.
private func at(_ needle: String) -> String.Index? {
    dmgScript.range(of: needle)?.lowerBound
}

// `contains` 만으로는 약하다 — 실제로 zsh 가 파싱할 수 있는지 봐야 한다.
// 실측 선례: `--proto =https` 는 zsh 가 `=명령어` 확장으로 읽어 "https not found" 로 통째로 죽었고,
// 문자열 단언은 그걸 전혀 잡지 못했다.
@Test
func dmgUpdateScriptParsesUnderZsh() throws {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("aing-dmg-script-\(UUID().uuidString).zsh")
    try dmgScript.write(to: path, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: path) }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
    proc.arguments = ["-n", path.path]        // 파싱만 한다 — 아무것도 실행하지 않는다
    let err = Pipe()
    proc.standardError = err
    try proc.run()
    let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    proc.waitUntilExit()
    #expect(proc.terminationStatus == 0, "zsh 가 스크립트를 파싱하지 못했다: \(message)")
}

// zsh 는 단어 앞의 `=https` 를 `=명령어` 확장으로 읽는다(실측: "https not found" 로 죽었다).
// 작은 인용을 걷어내는 '정리'가 스크립트를 통째로 죽이므로 글자로 못박는다.
@Test
func dmgUpdateScriptQuotesTheProtoArgument() {
    #expect(dmgScript.contains("--proto '=https'"))
}

// 검증을 하나라도 건너뛰면 네트워크에서 받은 것을 그대로 실행 위치에 넣는 셈이다.
@Test
func dmgUpdateScriptVerifiesNotarizationAndIdentityAndVersion() {
    // 공증: 종료코드만 보면 Gatekeeper 가 꺼진 맥에서 무엇이든 통과한다 — 출처 문자열까지 본다.
    // DMG 와 그 안의 앱, 두 번 확인한다.
    #expect(dmgScript.components(separatedBy: "source=Notarized Developer ID").count - 1 == 2)
    // 신원: spctl 은 '남이 공증한 앱'(Xcode·Chrome 실측)도 통과시킨다. 지정 요구사항만이 관문이다.
    // 대상까지 못박는다 — `$SRC`(마운트한 원본)·`$STAGE`(사본)·`$DEST`(교체된 자리) 셋 다 봐야 하고,
    // 하나만 남아도 "문자열이 있다"로 통과해 버린다(뮤테이션으로 확인했다).
    for target in ["$SRC", "$STAGE", "$DEST"] {
        #expect(
            dmgScript.contains(#"codesign --verify --deep --strict -R "=$REQ" "\#(target)""#),
            "\(target) 의 신원 검증이 사라졌다"
        )
    }
    // 버전: 옛 정식 릴리스(0.3.47)도 공증·신원 검증을 전부 통과한다(실측) — 다운그레이드를 막는 건 이 비교뿐이다.
    #expect(dmgScript.contains(#"[ "$GOT_BUILD" -le "$MIN_BUILD" ]"#))
    #expect(dmgScript.contains("fail not-newer"))
    // 받은 이미지 자체도 본다(마운트 전).
    #expect(dmgScript.contains("hdiutil verify"))
    // DMG 안의 앱이 심링크면 거절한다 — 따라가면 검증·복사 대상이 디스크의 다른 앱으로 돌아간다.
    #expect(dmgScript.contains(#"[ ! -L "$SRC" ]"#))
    // spctl 출력이 지역화되면 grep 이 어긋난다(hdiutil 은 이미 한국어로 출력한다 — 실측). 로케일을 묶는다.
    #expect(dmgScript.components(separatedBy: "LC_ALL=C spctl").count - 1 == 2)
}

// 순서가 안전의 핵심이다 — 검증을 다 통과하고 사본까지 만든 뒤에야 기존 번들을 건드린다.
// 그래야 무엇이 실패해도 설치본이 그 자리에 그대로 남는다.
@Test
func dmgUpdateScriptNeverTouchesTheInstalledBundleBeforeVerifying() throws {
    let swap = try #require(at(#"mv "$DEST" "$OLD""#), "교체 지점을 못 찾았다")
    for guardStep in [
        "hdiutil verify",
        "spctl -a -t open",
        "spctl --assess --type execute",
        #"codesign --verify --deep --strict -R "=$REQ" "$SRC""#,
        #"[ "$GOT_BUILD" -le "$MIN_BUILD" ]"#,
        #"codesign --verify --deep --strict -R "=$REQ" "$STAGE""#,
    ] {
        let i = try #require(at(guardStep), "검증 단계가 사라졌다: \(guardStep)")
        #expect(i < swap, "\(guardStep) 가 교체보다 뒤에 있다")
    }
    // DMG 는 **붙이기 전에** 검증한다 — 공격자 바이트를 커널 파일시스템 파서에 먼저 들이지 않는다.
    let attach = try #require(at("hdiutil attach"))
    #expect(try #require(at("hdiutil verify")) < attach)
    #expect(try #require(at("spctl -a -t open")) < attach)
}

// 교체가 어긋나면 앱이 사라진다 — 메뉴바에서 없어지면 사용자에게 알릴 표면조차 없다.
@Test
func dmgUpdateScriptRollsBackAndRelaunchesOnFailure() throws {
    // 되돌리기가 두 곳에 있어야 한다: mv 실패와 교체 후 검증 실패.
    #expect(dmgScript.components(separatedBy: #"mv "$OLD" "$DEST""#).count - 1 == 2)
    // 교체된 자리를 다시 검증한다 — 검증한 것과 실행될 것이 같다는 보장(TOCTOU).
    #expect(dmgScript.contains(#"codesign --verify --deep --strict -R "=$REQ" "$DEST""#))
    // 옛 번들은 **확정된 뒤에만** 지운다 — 마지막 `rm -rf "$OLD"` 가 교체 후 검증보다 뒤에 있어야 한다.
    let verified = try #require(at(#"codesign --verify --deep --strict -R "=$REQ" "$DEST""#))
    let lastRemoveOld = try #require(
        dmgScript.range(of: #"rm -rf "$OLD""#, options: .backwards)?.lowerBound
    )
    #expect(verified < lastRemoveOld)
    // 끝나면 다시 열어야 한다.
    #expect(dmgScript.contains(#"open -a "$DEST""#))
}

// Xcode 명령행 도구가 없는 맥에서 `xcrun stapler` 는 그 자체로 실패한다 —
// 그리고 DMG 로 설치하는 사람이야말로 개발자 도구가 없을 확률이 높다.
@Test
func dmgUpdateScriptDoesNotNeedXcodeTools() {
    #expect(!dmgScript.contains("xcrun"))
    #expect(!dmgScript.contains("stapler"))
}

// Apple Event 로 quit 을 보내면 자동화 권한 프롬프트가 끼어들 수 있고, **응답으로** 돌아와
// 프로세스 소멸을 보장하지 않는다 — 종료 절차(최대 3초 서버 왕복)가 도는 중에 번들을 바꾸면 경합한다.
@Test
func dmgUpdateScriptQuitsBySignalAndWaitsForTheProcessToGo() {
    #expect(!dmgScript.contains("osascript"))
    #expect(dmgScript.contains(#"kill -TERM "$APP_PID""#))
    // 소멸을 **확인**한 뒤에 교체한다.
    #expect(dmgScript.contains(#"kill -0 "$APP_PID""#))
    // 끝까지 안 죽으면 마지막 수단이 있어야 한다(없으면 영구히 멈춘다).
    #expect(dmgScript.contains(#"kill -KILL "$APP_PID""#))
}

// zsh 의 errexit 은 `&&`/`||` 목록의 마지막이 아닌 명령에 적용되지 않는다
// (실측: `set -e; false && echo nope; echo AFTER` → AFTER 가 찍히고 종료코드 0).
// 그 성질을 모르고 `set -e` 에 생명을 걸면 교체 실패인데 exit 0 으로 옛 앱을 다시 띄운다.
@Test
func dmgUpdateScriptDoesNotRelyOnErrexit() {
    #expect(!dmgScript.contains("set -e"))
    #expect(dmgScript.contains("set -u"))
    // 파괴적인 단계마다 명시 분기가 있어야 한다.
    #expect(dmgScript.components(separatedBy: "|| fail ").count - 1 >= 6)
}

// 두 벌이 같은 번들을 동시에 갈아치우면 한쪽이 치워 둔 옛 번들을 다른 쪽이 지운다.
// brew 경로는 brew 자신의 락이 막아 줬다 — DMG 경로는 우리가 걸어야 한다.
@Test
func dmgUpdateScriptLocksAgainstConcurrentRuns() {
    #expect(dmgScript.contains("aing-check-update.lock"))
    // 상태 파일 부모 폴더를 만들어야 한다 — 없으면 표식이 하나도 안 남고 배너가 다시 600초 굳는다.
    #expect(dmgScript.contains(#"mkdir -p "$(dirname "$STATE")""#))
    // 자리는 cask 의 zap 목록 안이어야 한다(제거 시 잔재가 남지 않게).
    #expect(UpdateRunner.statePath.contains("/Library/Caches/kingcheck/"))
    #expect(dmgScript.contains("fail busy"))
    // SIGKILL 로 죽은 시도가 남긴 자물쇠에 영구히 막히면 안 된다.
    #expect(dmgScript.contains("-mmin +60"))
}

// ditto 는 대상이 이미 있으면 **합친다**(실측) — 지난 시도의 잔재를 안 치우면 새 버전에서 지워진 파일이
// 섞인 번들이 되고 코드 서명이 무효가 된다.
@Test
func dmgUpdateScriptClearsLeftoversFromDeadAttempts() throws {
    let clear = try #require(at(".aing-check-update.*"))
    let ditto = try #require(at(#"ditto "$SRC" "$STAGE""#))
    #expect(clear < ditto)
    #expect(dmgScript.contains(#"rm -rf "$OLD""#))
}

// 스크립트가 적는 단계 이름과 사용자 문구는 **일대일**이어야 한다. 어긋나면 사용자가 빈 안내를 받는다.
// 스크립트에서 이름을 직접 긁어 되묻는다 — 목록을 테스트에 다시 적으면 둘이 함께 썩는다.
@Test
func everyFailureStepInTheScriptHasAUserFacingMessage() {
    var steps: Set<String> = []
    for line in dmgScript.split(whereSeparator: \.isNewline) {
        var rest = Substring(line.trimmingCharacters(in: .whitespaces))
        while let r = rest.range(of: "fail ") {
            rest = rest[r.upperBound...]
            let name = rest.prefix { $0.isLetter || $0 == "-" }
            // `fail() {` 선언 자체와 빈 이름은 건너뛴다.
            if !name.isEmpty { steps.insert(String(name)) }
        }
    }
    #expect(steps.count >= 15, "단계 이름을 긁지 못했다(파싱이 깨졌다): \(steps)")
    for step in steps.sorted() {
        #expect(
            UpdateProgress.userMessage(forFailedStep: step) != nil,
            "스크립트의 '\(step)' 단계에 사용자 문구가 없다"
        )
    }
}

// MARK: - 진행 표식 파싱 (스크립트 → 배너)

@Test
func progressTakesTheLastStageWritten() {
    let p = UpdateProgress.parse("stage=start\nstage=download\nstage=verify\n")
    #expect(p.stage == .verify)
    #expect(p.failedStep == nil)
}

// 실패가 적혀 있으면 그게 결론이다 — 600초를 기다릴 이유가 없다(오프라인은 1초에 판정된다).
@Test
func progressErrorOverridesTheStage() {
    let p = UpdateProgress.parse("stage=start\nstage=download\nerror=download code=56\n")
    #expect(p.failedStep == "download")
    #expect(p.stage == nil)
    #expect(UpdateProgress.userMessage(forFailedStep: "download")?.contains("인터넷") == true)
}

// 스크립트가 나중에 단계를 더 적어도 옛 앱이 "모름"으로 되돌아가면 안 된다.
@Test
func progressIgnoresUnknownStagesAndKeepsTheLastKnownOne() {
    let p = UpdateProgress.parse("stage=download\nstage=teleporting\n")
    #expect(p.stage == .download)
    #expect(UpdateProgress.userMessage(forFailedStep: "teleporting") == nil)
}

@Test
func progressIsUnknownWhenThereIsNoStateFile() {
    #expect(UpdateProgress.parse(nil) == .unknown)
    #expect(UpdateProgress.parse("") == .unknown)
    #expect(UpdateProgress.parse("쓰레기\n한 줄") == .unknown)
}

// 단계마다 사용자용 문구가 있어야 한다 — 없으면 배너가 빈 줄을 그린다.
@Test
func everyStageHasUserText() {
    for stage in [UpdateStage.start, .download, .verify, .staging, .quit, .swap, .done] {
        #expect(!stage.userText.isEmpty)
    }
}

// MARK: - 진행 감시 (상태 파일을 읽어 즉시 판정)

// 오프라인은 curl 이 1초에 끝난다. 표식을 읽으면 600초를 기다리지 않고 바로 알릴 수 있다 —
// 이 앱은 이미 "배너가 업데이트 중으로 굳었다"는 실사용 신고를 받은 적이 있다.
@MainActor
@Test
func standaloneFailsAsSoonAsTheScriptReportsAnError() async {
    let runner = makeStandaloneRunner(state: "stage=start\nstage=download\nerror=download code=6\n")
    let task = runner.runUpgrade()
    #expect(runner.status == .running)
    await task?.value
    #expect(runner.status == .failed)
    #expect(runner.progress.failedStep == "download")
}

// 진행 중엔 **어느 단계인지** 배너에 올라가야 한다. 한 문구로 굳어 있으면 사용자가 멈춘 것으로 본다.
@MainActor
@Test
func standaloneSurfacesTheCurrentStageWhileRunning() async {
    let runner = makeStandaloneRunner(state: "stage=start\nstage=staging\n")
    let task = runner.runUpgrade()
    // 한 번 폴링하면 표식이 올라온다(watchdogSleep 이 즉시 반환한다).
    try? await Task.sleep(for: .milliseconds(50))
    task?.cancel()
    #expect(runner.progress.stage == .staging)
    #expect(runner.progress.stage?.userText == "설치를 준비하는 중…")
}

// 교체가 끝났으면 곧 이 앱이 죽고 새 앱이 뜬다 — 감시가 더 돌며 failed 로 내리면 거짓 실패가 된다.
@MainActor
@Test
func standaloneStopsWatchingOnceTheSwapIsDone() async {
    let runner = makeStandaloneRunner(state: "stage=swap\nstage=done\n")
    let task = runner.runUpgrade()
    await task?.value
    #expect(runner.status == .running, "done 뒤에 failed 로 내리면 성공이 실패로 보인다")
    #expect(runner.progress.stage == .done)
}

// 표식이 하나도 안 올라오면(스크립트가 말없이 사라졌다) 마지막 그물이 작동해야 한다.
@MainActor
@Test
func standaloneStillFailsWhenTheScriptLeavesNoTrace() async {
    let runner = makeStandaloneRunner(state: nil)
    await runner.runUpgrade()?.value
    #expect(runner.status == .failed)
    #expect(runner.progress == .unknown)
}

// MARK: - SIGTERM → 평소 종료 절차

// 기본 처분으로 SIGTERM 이 오면 프로세스가 즉사해 applicationShouldTerminate 가 돌지 않는다 —
// 근무 중이었다면 열린 세션이 서버에 남고 하트비트만 끊긴다(이 저장소가 이미 크게 겪은 사고의 부류).
// 실제로 신호를 보내 받는지 확인한다. install 이 먼저 SIG_IGN 을 걸므로, 배선이 깨져 있어도
// 테스트 프로세스가 죽지 않고 타임아웃으로 빨개진다.
@MainActor
@Test
func sigtermRunsTheGracefulTerminationPathInsteadOfKillingUsOutright() async {
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func raise() { lock.lock(); value = true; lock.unlock() }
        var raised: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
    let flag = Flag()
    GracefulTerminationSignal.install { flag.raise() }
    defer { GracefulTerminationSignal.uninstallForTesting() }

    kill(getpid(), SIGTERM)

    // 신호 전달은 비동기다 — 짧게 기다린다(실측: 실제 앱에서 600ms 안에 종료까지 끝났다).
    for _ in 0..<100 where !flag.raised {
        try? await Task.sleep(for: .milliseconds(20))
    }
    #expect(flag.raised, "SIGTERM 이 평소 종료 절차로 이어지지 않았다")
}

// MARK: - 헬퍼

/// 태그를 릴리스 JSON(tag_name 만) 으로 감싼 스텁 응답.
private func tagJSON(_ tag: String) -> Data {
    Data(#"{"tag_name":"\#(tag)"}"#.utf8)
}

/// 성공 데이터/실패 에러를 담고 호출 횟수를 세는 fetch 스텁(네트워크 미접촉). 테스트 전용이라 @unchecked Sendable.
private final class FetchRecorder: @unchecked Sendable {
    private(set) var count = 0
    private let payload: Result<Data, Error>
    init(_ payload: Result<Data, Error>) { self.payload = payload }
    func fetch(_ url: URL) async throws -> Data {
        count += 1
        switch payload {
        case .success(let data): return data
        case .failure(let error): throw error
        }
    }
}

/// 성공 태그를 돌려주는 격리 스토어(신선하지 않은 상태 — 최초 checkIfStale 이 1회 조회).
@MainActor
/// `function` 을 받아서 그대로 내려보낸다 — 여기서 기본 인자를 다시 쓰면 `#function` 이
/// `makeUpdateStore` 로 굳어 이 파일의 모든 테스트가 한 스위트를 나눠 쓴다(CheckTestScratch 주석).
private func makeUpdateStore(
    current: String,
    tag: String,
    now: Date = Date(timeIntervalSince1970: 1_000_000),
    function: String = #function
) -> UpdateCheckStore {
    UpdateCheckStore(
        currentVersion: current,
        fetcher: FetchRecorder(.success(tagJSON(tag))).fetch,
        clock: { now },
        defaults: isolatedUpdateDefaults(function: function)
    )
}

/// 격리 defaults. 이름을 UUID 가 아니라 테스트 신원에서 뽑고 자리도 $TMPDIR 로 옮긴다 —
/// 이유는 `CheckTestScratch` 머리 주석에 있다. 한 테스트가 둘 이상 쓰면 `label` 로 갈라라.
private func isolatedUpdateDefaults(_ label: String = "", function: String = #function) -> UserDefaults {
    CheckTestScratch.defaults(label, function: function)
}
