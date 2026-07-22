import Foundation
import Testing
@testable import check

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

// MARK: - UpdateRunner 폴백 (brew 탐지 · 분리 스폰 · 상태 전이)

@Test
func copyCommandIsExact() {
    // 폴백 복사 문자열은 정확히 이 문자열이어야 한다.
    #expect(UpdateRunner.copyCommand == "brew upgrade aing-check")
}

@MainActor
@Test
func updateRunnerUnavailableWhenBrewMissing() {
    var spawnCalls = 0
    let runner = UpdateRunner(fileExists: { _ in false }, spawn: { _ in spawnCalls += 1; return true })
    #expect(runner.brewPath == nil)
    runner.runUpgrade()
    #expect(runner.status == .unavailable)
    #expect(spawnCalls == 0) // brew 없으면 스폰조차 하지 않는다.
}

@MainActor
@Test
func updateRunnerRunsWhenBrewPresentAndSpawnSucceeds() {
    var spawnedWith: String?
    // 둘 다 존재하면 Apple Silicon(/opt/homebrew) 경로를 우선한다.
    let runner = UpdateRunner(fileExists: { _ in true }, spawn: { spawnedWith = $0; return true })
    #expect(runner.brewPath == "/opt/homebrew/bin/brew")
    runner.runUpgrade()
    #expect(runner.status == .running)
    #expect(spawnedWith == "/opt/homebrew/bin/brew")

    // running 중 재호출은 무시(중복 스폰 금지).
    var secondSpawn = false
    let runner2 = UpdateRunner(fileExists: { _ in true }, spawn: { _ in secondSpawn = true; return true })
    runner2.runUpgrade()
    secondSpawn = false
    runner2.runUpgrade()
    #expect(!secondSpawn)
    #expect(runner2.status == .running)
}

@MainActor
@Test
func updateRunnerFallsBackToIntelPathWhenOnlyThatExists() {
    let runner = UpdateRunner(fileExists: { $0 == "/usr/local/bin/brew" }, spawn: { _ in true })
    #expect(runner.brewPath == "/usr/local/bin/brew")
}

@MainActor
@Test
func updateRunnerFailsWhenSpawnFails() {
    let runner = UpdateRunner(fileExists: { _ in true }, spawn: { _ in false })
    runner.runUpgrade()
    #expect(runner.status == .failed)
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
private func makeUpdateStore(
    current: String,
    tag: String,
    now: Date = Date(timeIntervalSince1970: 1_000_000)
) -> UpdateCheckStore {
    UpdateCheckStore(
        currentVersion: current,
        fetcher: FetchRecorder(.success(tagJSON(tag))).fetch,
        clock: { now },
        defaults: isolatedUpdateDefaults()
    )
}

private func isolatedUpdateDefaults() -> UserDefaults {
    let suite = "check-update-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
