import AppKit
import Foundation
import Testing
@testable import check

// MARK: - v0.3.20 서버가 알리는 새 버전 (app_latest_release → UpdateCheckStore)
//
// 예전엔 새 버전을 팝오버를 열 때만, 하루 1회 GitHub 으로 알았다. 이 스위트는 서버 소스의 네 갈래를 잰다:
//  ① 요청 모양(anon Bearer · POST · 본문 {})과 디코드(전부 / 빈 표 / 모르는 키 / 비2xx),
//  ② 판정(빌드 > 내 빌드일 때만 기록 · v 계약 · 모르는 내 빌드는 침묵 · 서버 경로는 지우지 않는다),
//  ③ 두 경로의 정합(같은 태그면 빌드 유지 · 노트 상한 한 벌 · 새 버전 콜백 버전당 1회),
//  ④ 언제 치는가(60초 스로틀 · 실패 뒤 재시도 · 감시 루프 · 깨어남 · 팝오버 경로가 GitHub 스로틀을 그대로 지킨다).
// 네트워크는 건드리지 않는다 — 서비스는 URLProtocol 스텁, 스토어는 주입 조회기만 쓴다.
// 시간이 걸리는 루프·깨어남은 정확한 수면에 기대지 않고 넉넉한 시한의 폴링으로 기다린다(전체 스위트 부하 대비).

@MainActor
@Suite struct V0320ServerReleaseTests {

    // MARK: ① 서비스 — 요청 모양 · 디코드

    @Test func fetchLatestReleasePostsTheRPCWithAnonBearerAndAnEmptyObjectBody() async throws {
        let host = "v0320-release-shape"
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
        // 공용 스텁은 이 RPC 의 응답 모양을 모른다 — 여기선 **나간 요청**만 잰다(디코드는 아래 전용 스텁이 잰다).
        _ = try? await service.fetchLatestRelease()

        let requests = URLProtocolStub.requests(forHost: host)
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.path == "/rest/v1/rpc/app_latest_release")
        #expect(request.httpMethod == "POST")
        // 로그인 전에도 알아야 하므로 로그인 토큰이 아니라 anon 키를 Bearer 로 싣는다.
        #expect(request.value(forHTTPHeaderField: "apikey") == "anon-test-key")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer anon-test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(URLProtocolStub.bodyText(forHost: host) == "{}")
    }

    @Test func fetchLatestReleaseDecodesFullEmptyAndUnknownKeyPayloads() async throws {
        let full = try await srService("v0320-decode-full").fetchLatestRelease()
        #expect(full == AppLatestRelease(
            v: 1, version: "0.3.20", build: 72, notes: ["첫 줄", "둘째 줄"],
            publishedAt: "2026-09-14T05:00:00.123456+00:00"
        ))
        // 표가 빈 서버의 정상 응답 — 디코드는 성공하고, 판정(applyServerRelease)이 조용히 버린다.
        let empty = try await srService("v0320-decode-empty").fetchLatestRelease()
        #expect(empty == AppLatestRelease(v: 1, version: nil, build: nil, notes: [], publishedAt: nil))
        // 뒤에 필드가 늘어도 옛 앱이 디코드에서 죽으면 안 된다.
        let extra = try await srService("v0320-decode-extra").fetchLatestRelease()
        #expect(extra == AppLatestRelease(v: 1, version: "0.3.20", build: 72, notes: [], publishedAt: nil))
        // 키가 통째로 빠져도 전부 nil 로 읽힌다.
        let bare = try await srService("v0320-decode-bare").fetchLatestRelease()
        #expect(bare == AppLatestRelease(v: nil, version: nil, build: nil, notes: nil, publishedAt: nil))
    }

    @Test func fetchLatestReleaseThrowsOnNon2xxLikeItsSiblings() async {
        // 함수가 없는 옛 서버(404 PGRST202)·일시 장애(500)는 throw — 스토어가 조용히 삼키고 GitHub 폴백이 남는다.
        await #expect(throws: SupabaseWorkServiceError.self) {
            _ = try await srService("v0320-status-404").fetchLatestRelease()
        }
        await #expect(throws: SupabaseWorkServiceError.invalidResponse(500)) {
            _ = try await srService("v0320-status-500").fetchLatestRelease()
        }
    }

    // MARK: ② 판정 — applyServerRelease

    @Test func aNewerServerBuildIsRecordedInTheGitHubTagShapeAndPersisted() {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let store = srStore(defaults: defaults)

        store.applyServerRelease(srRelease("0.3.20", build: 72, notes: ["**새** 기능", "`brew` 없이", "  "]))

        #expect(store.latestVersion == "v0.3.20", "GitHub tag_name 과 같은 모양이 아니다 — 같은 릴리스에 말풍선이 두 번 뜬다")
        #expect(store.latestBuild == 72)
        #expect(store.latestNotes == ["새 기능", "brew 없이"])
        #expect(store.isUpdateAvailable)
        #expect(defaults.string(forKey: UpdateCheckStore.latestVersionKey) == "v0.3.20")
        #expect(defaults.stringArray(forKey: UpdateCheckStore.latestNotesKey) == ["새 기능", "brew 없이"])
        #expect(defaults.object(forKey: UpdateCheckStore.latestBuildKey) as? Int == 72)
    }

    @Test func anEqualOrOlderServerBuildChangesNothingAndNeverClears() {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let store = srStore(defaults: defaults, currentVersion: "0.3.19", currentBuild: 71)

        // 지금 돌고 있는 바로 이 빌드 — 업데이트가 아니다.
        store.applyServerRelease(srRelease("0.3.19", build: 71))
        #expect(store.latestVersion == nil, "같은 빌드를 새 버전으로 기록했다")
        #expect(store.latestBuild == nil)
        store.applyServerRelease(srRelease("0.3.18", build: 70))
        #expect(store.latestVersion == nil)
        #expect(defaults.object(forKey: UpdateCheckStore.latestVersionKey) == nil)

        // 새 버전을 한 번 기록한 뒤 같거나 낮은 응답이 와도 지우지 않는다(서버 경로는 절대 지우지 않는다).
        store.applyServerRelease(srRelease("0.3.20", build: 72, notes: ["한 줄"]))
        store.applyServerRelease(srRelease("0.3.19", build: 71, notes: []))
        store.applyServerRelease(srRelease("0.3.18", build: 70, notes: []))
        #expect(store.latestVersion == "v0.3.20")
        #expect(store.latestBuild == 72)
        #expect(store.latestNotes == ["한 줄"])
    }

    @Test func anUnknownOwnBuildKeepsTheServerPathSilent() {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        // 개발 빌드(CFBundleVersion 없음) — 폴백 숫자를 쓰면 서버가 아는 모든 릴리스가 "업데이트"가 된다.
        let store = srStore(defaults: defaults, currentBuild: nil)
        store.applyServerRelease(srRelease("9.9.9", build: 999))
        #expect(store.latestVersion == nil)
        #expect(store.latestBuild == nil)
        #expect(!store.isUpdateAvailable)
    }

    @Test func onlyContractV1WithAUsableBuildAndVersionIsRead() {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let store = srStore(defaults: defaults, currentBuild: 71)

        store.applyServerRelease(srRelease("0.3.20", build: 72, v: 2))
        #expect(store.latestVersion == nil, "모르는 계약(v=2)을 추측해 읽었다")

        let unusable = [
            srRelease(nil, build: 72),
            srRelease("0.3.20", build: nil),
            srRelease("다음 버전", build: 72),
            srRelease("", build: 72),
            AppLatestRelease(v: 1, version: nil, build: nil, notes: [], publishedAt: nil)
        ]
        for release in unusable {
            store.applyServerRelease(release)
            #expect(store.latestVersion == nil, "쓸 수 없는 응답을 기록했다: \(release)")
        }

        // v 누락은 1 로 읽는다.
        store.applyServerRelease(srRelease("0.3.20", build: 72, v: nil))
        #expect(store.latestVersion == "v0.3.20")
        #expect(store.latestBuild == 72)
    }

    @Test func buildsAtOrBelowZeroAreNeverTreatedAsKnown() {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        // 내 빌드가 음수로 들어와도(이론상) 0·음수 서버 빌드는 '모름'이다 — 크기 비교를 통과시키지 않는다.
        let store = srStore(defaults: defaults, currentBuild: -10)
        store.applyServerRelease(srRelease("0.3.20", build: 0))
        store.applyServerRelease(srRelease("0.3.20", build: -1))
        #expect(store.latestVersion == nil)
    }

    @Test func theServerRecordSurvivesRelaunchAndLegacyRecordsRestoreWithoutABuild() {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let store = srStore(defaults: defaults)
        store.applyServerRelease(srRelease("0.3.20", build: 72, notes: ["첫 줄"]))

        // 재실행: 같은 defaults 로 새 스토어 — 네트워크 없이도 배너 재료와 빌드가 그대로다.
        let relaunched = srStore(defaults: defaults)
        #expect(relaunched.latestVersion == "v0.3.20")
        #expect(relaunched.latestBuild == 72)
        #expect(relaunched.latestNotes == ["첫 줄"])
        #expect(relaunched.isUpdateAvailable)

        // 업데이트를 마치고(내 빌드 72) 같은 기록을 복원하면 더는 업데이트가 아니다.
        let upgraded = srStore(defaults: defaults, currentVersion: "0.3.20", currentBuild: 72)
        #expect(upgraded.latestBuild == 72)
        #expect(!upgraded.isUpdateAvailable)

        // 빌드 ≤71 이 남긴 옛 기록(버전+노트만): 빌드는 nil, 판정은 예전 semver 그대로.
        let (legacy, cleanLegacy) = srIsolatedDefaults()
        defer { cleanLegacy() }
        legacy.set("v0.3.20", forKey: UpdateCheckStore.latestVersionKey)
        legacy.set(["옛 노트"], forKey: UpdateCheckStore.latestNotesKey)
        let old = srStore(defaults: legacy, currentVersion: "0.3.19", currentBuild: 71)
        #expect(old.latestBuild == nil)
        #expect(old.latestNotes == ["옛 노트"])
        #expect(old.isUpdateAvailable)
    }

    // MARK: ③ 두 경로의 정합

    @Test func availabilityComparesBuildsWhenBothAreKnownEvenIfVersionStringsSayOtherwise() {
        // "0.3.01" 과 "0.3.1" 은 semver 로 같다 — 문자열 축으로는 이 업데이트가 영영 안 보인다.
        #expect(!SemverCompare.isNewer("v0.3.01", than: "0.3.1"))
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let store = srStore(defaults: defaults, currentVersion: "0.3.1", currentBuild: 62)
        store.applyServerRelease(srRelease("0.3.01", build: 63))
        #expect(store.isUpdateAvailable, "빌드 63 > 62 인데 버전 문자열 축에 막혔다")

        // 반대 방향: semver 로는 더 높아 보여도 빌드가 같으면 업데이트가 아니다.
        let (sameBuild, cleanSame) = srIsolatedDefaults()
        defer { cleanSame() }
        sameBuild.set("v0.3.10", forKey: UpdateCheckStore.latestVersionKey)
        sameBuild.set(62, forKey: UpdateCheckStore.latestBuildKey)
        #expect(SemverCompare.isNewer("v0.3.10", than: "0.3.9"))
        let same = srStore(defaults: sameBuild, currentVersion: "0.3.9", currentBuild: 62)
        #expect(!same.isUpdateAvailable, "빌드가 같은데 버전 문자열로 업데이트라고 했다")

        // 내 빌드를 모르면 예전 semver 규칙으로 돌아간다.
        let unknown = srStore(defaults: sameBuild, currentVersion: "0.3.9", currentBuild: nil)
        #expect(unknown.isUpdateAvailable)
    }

    @Test func theGitHubPathKeepsTheServerBuildForTheSameTagAndDropsItForAnother() async {
        // 같은 릴리스: 서버가 먼저 알려 주고, 하루 1회 GitHub 도 같은 태그를 말한다 → 빌드 유지.
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let same = srStore(defaults: defaults, github: srTagJSON("v0.3.20", body: "- 깃허브 노트"))
        same.applyServerRelease(srRelease("0.3.20", build: 72, notes: ["서버 노트"]))
        await same.checkIfStale()
        #expect(same.latestVersion == "v0.3.20")
        #expect(same.latestBuild == 72, "같은 태그인데 서버가 준 빌드를 버렸다")
        #expect(same.latestNotes == ["깃허브 노트"])
        #expect(defaults.object(forKey: UpdateCheckStore.latestBuildKey) as? Int == 72)

        // 다른 릴리스: 빌드를 남기면 v0.3.21 태그에 v0.3.20 의 빌드가 붙는다 → 버린다(영속 키까지).
        let (otherDefaults, cleanOther) = srIsolatedDefaults()
        defer { cleanOther() }
        let other = srStore(defaults: otherDefaults, github: srTagJSON("v0.3.21"))
        other.applyServerRelease(srRelease("0.3.20", build: 72))
        await other.checkIfStale()
        #expect(other.latestVersion == "v0.3.21")
        #expect(other.latestBuild == nil, "다른 태그에 옛 릴리스의 빌드가 남았다")
        #expect(otherDefaults.object(forKey: UpdateCheckStore.latestBuildKey) == nil)
        #expect(other.isUpdateAvailable) // 빌드를 모르므로 semver(0.3.21 > 0.3.19)
        #expect(srStore(defaults: otherDefaults).latestBuild == nil) // 재실행도 빌드 없이 복원된다

        // 태그 동일성은 앞의 v 하나만 무시한다 — 숫자 정규화는 하지 않는다.
        #expect(UpdateCheckStore.isSameTag("0.3.20", "v0.3.20"))
        #expect(UpdateCheckStore.isSameTag("V0.3.20", "v0.3.20"))
        #expect(!UpdateCheckStore.isSameTag("v0.3.01", "v0.3.1"))
        #expect(!UpdateCheckStore.isSameTag("v0.3.20", nil))
    }

    @Test func serverNotesUseTheSameCleanupAndCapAsReleaseBodies() {
        // 같은 항목을 두 경로로 넣으면 **같은 줄**이 나와야 한다(0~7개 — 상한 경계 4 앞뒤 전부).
        for count in 0...7 {
            let items = (0..<count).map { i in i.isMultiple(of: 2) ? "**항목\(i)**" : "`항목\(i)` 고침" }
            let body = items.map { "- \($0)" }.joined(separator: "\r\n")
            #expect(
                UpdateCheckStore.serverNotes(items) == UpdateCheckStore.parseNotes(body),
                "항목 \(count)개에서 두 경로가 갈렸다"
            )
        }
        // 빈 항목·기호뿐인 항목은 버리고, 개수에도 세지 않는다.
        #expect(UpdateCheckStore.serverNotes(["  ", "", "**", "진짜"]) == ["진짜"])
        #expect(UpdateCheckStore.capNotes((1...5).map { "n\($0)" }) == ["n1", "n2", "n3", "외 2건"])

        // 스토어 경로도 같은 함수를 탄다.
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let store = srStore(defaults: defaults)
        let six = (1...6).map { "항목\($0)" }
        store.applyServerRelease(srRelease("0.3.20", build: 72, notes: six))
        #expect(store.latestNotes == UpdateCheckStore.parseNotes(six.map { "- \($0)" }.joined(separator: "\n")))
        #expect(store.latestNotes == ["항목1", "항목2", "항목3", "외 3건"])
    }

    @Test func theNewVersionCallbackFiresOncePerVersionFromEitherPath() async {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let store = srStore(defaults: defaults, github: srTagJSON("v0.3.22"))
        let fired = SRLog()
        store.onNewVersionAvailable = { fired.entries.append($0) }

        store.applyServerRelease(srRelease("0.3.20", build: 72))
        #expect(fired.entries == ["v0.3.20"])
        // 5분 뒤 같은 응답 · 노트만 고친 응답(refreshed) — 같은 버전이라 다시 부르지 않는다.
        store.applyServerRelease(srRelease("0.3.20", build: 72))
        store.applyServerRelease(srRelease("0.3.20", build: 72, notes: ["노트만 고침"]))
        #expect(fired.entries == ["v0.3.20"], "같은 버전 재확인에 콜백이 또 불렸다")
        // 더 새 버전은 다시 부른다.
        store.applyServerRelease(srRelease("0.3.21", build: 73))
        #expect(fired.entries == ["v0.3.20", "v0.3.21"])
        // GitHub 경로도 같은 문을 지난다(빌드를 모르므로 semver 로 업데이트).
        await store.checkIfStale()
        #expect(store.latestVersion == "v0.3.22")
        #expect(fired.entries == ["v0.3.20", "v0.3.21", "v0.3.22"])

        // 업데이트가 아닌 새 값에는 부르지 않는다.
        let (quietDefaults, cleanQuiet) = srIsolatedDefaults()
        defer { cleanQuiet() }
        let quiet = srStore(defaults: quietDefaults, currentVersion: "0.3.19", github: srTagJSON("v0.3.19"))
        let quietFired = SRLog()
        quiet.onNewVersionAvailable = { quietFired.entries.append($0) }
        await quiet.checkIfStale()
        #expect(quiet.latestVersion == "v0.3.19")
        #expect(quietFired.entries.isEmpty)

        // 재실행 복원 뒤 같은 버전을 서버가 다시 확인해도 반복이다.
        let relaunched = srStore(defaults: defaults, currentBuild: 71)
        let relaunchedFired = SRLog()
        relaunched.onNewVersionAvailable = { relaunchedFired.entries.append($0) }
        relaunched.applyServerRelease(srRelease("0.3.22", build: 74))
        #expect(relaunched.latestBuild == 74)
        #expect(relaunchedFired.entries.isEmpty)
    }

    // MARK: ④ 언제 치는가

    @Test func thePopoverThrottleIsSixtySecondsAndAFailureNeverBlocksTheNextUnthrottledTry() async {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        var now = Date(timeIntervalSince1970: 2_000_000)
        let store = srStore(defaults: defaults, clock: { now })
        let server = SRServerStub(.success(srRelease("0.3.20", build: 72)))
        store.serverFetcher = { try await server.fetch() }

        await store.checkServerNow(minimumInterval: 60)
        #expect(server.count == 1)
        #expect(store.latestVersion == "v0.3.20")

        now = now.addingTimeInterval(59)
        await store.checkServerNow(minimumInterval: 60)
        #expect(server.count == 1, "60초 안에 팝오버 경로가 서버를 다시 쳤다")

        // 감시 루프·깨어남(0)은 스로틀을 받지 않는다 — 그리고 그 시도가 새 스탬프다.
        await store.checkServerNow()
        #expect(server.count == 2)
        now = now.addingTimeInterval(30)
        await store.checkServerNow(minimumInterval: 60)
        #expect(server.count == 2)
        now = now.addingTimeInterval(31)
        await store.checkServerNow(minimumInterval: 60)
        #expect(server.count == 3)

        // 실패는 조용히(기록 불변), 그리고 다음 무스로틀 시도를 막지 않는다.
        server.result = .failure(SRBoom())
        now = now.addingTimeInterval(120)
        await store.checkServerNow()
        #expect(server.count == 4)
        #expect(store.latestVersion == "v0.3.20")
        #expect(store.latestBuild == 72)
        await store.checkServerNow()
        #expect(server.count == 5, "실패 한 번이 다음 조회를 막았다")
        server.result = .success(srRelease("0.3.21", build: 73))
        await store.checkServerNow()
        #expect(server.count == 6)
        #expect(store.latestVersion == "v0.3.21")
    }

    /// 60초 스로틀 도장은 **이번 실행의 메모리에만** 산다. 영속되면 앱을 다시 켠 직후 연 팝오버가 지난 실행의
    /// 도장에 막혀 서버를 안 본다 — 그리고 그 사실은 어떤 화면에도 드러나지 않는다.
    @Test func thePopoverThrottleStampDiesWithTheProcess() async {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let now = Date(timeIntervalSince1970: 3_000_000)
        let keysBefore = Set(defaults.dictionaryRepresentation().keys)

        let first = srStore(defaults: defaults, clock: { now })
        let firstServer = SRServerStub(.success(srRelease("0.3.19", build: 71)))
        first.serverFetcher = { try await firstServer.fetch() }
        await first.checkServerNow(minimumInterval: 60)
        #expect(firstServer.count == 1)

        // 같은 defaults 로 1초 뒤 다시 켠 앱 — 첫 팝오버 조회는 반드시 나가야 한다.
        let relaunched = srStore(defaults: defaults, clock: { now.addingTimeInterval(1) })
        let relaunchedServer = SRServerStub(.success(srRelease("0.3.19", build: 71)))
        relaunched.serverFetcher = { try await relaunchedServer.fetch() }
        await relaunched.checkServerNow(minimumInterval: 60)
        #expect(relaunchedServer.count == 1, "지난 실행의 스로틀 도장이 새 실행의 첫 조회를 막았다 — 도장이 영속됐다")

        // 서버 경로가 defaults 에 남길 수 있는 키는 기록 셋(+ GitHub 스로틀)뿐이다. 새 키가 생기면 무언가 영속된 것이다.
        let added = Set(defaults.dictionaryRepresentation().keys).subtracting(keysBefore)
        let allowed: Set<String> = [
            UpdateCheckStore.latestVersionKey, UpdateCheckStore.latestNotesKey,
            "check.update.latestBuild", UpdateCheckStore.lastCheckedKey,
        ]
        #expect(added.isSubset(of: allowed), "서버 조회가 예상 밖의 키를 남겼다: \(added.subtracting(allowed))")
    }

    @Test func concurrentChecksShareOneRequestAndNoFetcherMeansNoRequest() async {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        let store = srStore(defaults: defaults)
        // 조회기가 없으면(테스트·프리뷰 기본값) 어떤 서버 메서드도 아무것도 하지 않는다.
        await store.checkServerNow()
        await store.checkServerNow(minimumInterval: 60)
        #expect(store.latestVersion == nil)

        // 루프와 팝오버가 같은 순간 겹쳐도 요청은 1회다(두 번째는 떠 있는 조회를 기다린다).
        let server = SRServerStub(.success(srRelease("0.3.20", build: 72)), delay: .milliseconds(80))
        store.serverFetcher = { try await server.fetch() }
        let first = Task { await store.checkServerNow() }
        let second = Task { await store.checkServerNow() }
        await first.value
        await second.value
        #expect(server.count == 1, "겹친 조회가 요청을 두 번 보냈다")
        #expect(store.latestVersion == "v0.3.20")
    }

    // ★ 아래 세 테스트의 "안 쳤다" 단언은 **벽시계로 기다리지 않는다.** 전체 필터 실행에서 메인 액터가 한 번에 76초 동안
    //   막힌 것을 실측했다(오버레이 쪽 동기 작업 — 순수 계산 테스트까지 전부 ~79초에 끝났다). 그 상태에서 "300ms 뒤 0회"는
    //   루프에 기회를 한 번도 주지 않은 채 초록이 되고, "5초 안에 2회"는 루프가 돌 틈도 없이 빨갛게 된다.
    //   그래서 부정 단언은 **같은 모양으로 계속 도는 대조군**이 몇 바퀴 돌 때까지 기다린 뒤 잰다 — 대조군이 돌 기회가 있었으면
    //   멈춘(또는 늦춘) 쪽에도 같은 기회가 있었다는 뜻이다.

    @Test func theWatchLoopFetchesRepeatedlyAndStopsWhenStopped() async {
        let watched = srWatched(interval: 0.02, initialDelay: 0)
        defer { watched.cleanUp() }
        watched.store.startServerWatch()
        watched.store.startServerWatch() // 멱등 — 두 번 불러도 루프는 하나다.
        let ticked = await srWait { watched.server.count >= 2 }
        #expect(ticked, "감시 루프가 두 번 이상 조회하지 않았다: \(watched.server.count)")

        watched.store.stopServerWatch()
        let atStop = watched.server.count
        // 대조군: 똑같은 주기로 계속 도는 루프. 그게 네 번 치는 동안 멈춘 쪽은 멈춘 순간 떠 있던 1건 말고는 못 친다.
        let control = srWatched(interval: 0.02, initialDelay: 0)
        defer { control.cleanUp() }
        control.store.startServerWatch()
        let controlRan = await srWait { control.server.count >= 4 }
        await srSettle()
        control.store.stopServerWatch()
        #expect(controlRan, "대조군 루프가 돌지 않았다 — 아래 단언이 아무것도 재지 않는다")
        #expect(watched.server.count <= atStop + 1, "멈춘 뒤에도 루프가 돌았다: \(atStop) → \(watched.server.count)")
    }

    @Test func theWatchWaitsForItsInitialDelayBeforeTheFirstFetch() async {
        let delayed = srWatched(interval: 3_600, initialDelay: 3_600)
        defer { delayed.cleanUp() }
        delayed.store.startServerWatch()
        // 대조군은 **나중에** 지연 0 으로 켠다. 지연을 무시했다면 먼저 켠 쪽이 대조군보다 먼저 쳤다.
        let control = srWatched(interval: 3_600, initialDelay: 0)
        defer { control.cleanUp() }
        control.store.startServerWatch()
        let controlRan = await srWait { control.server.count >= 1 }
        await srSettle()
        delayed.store.stopServerWatch()
        control.store.stopServerWatch()
        #expect(controlRan, "대조군 루프가 첫 조회를 하지 않았다")
        #expect(delayed.server.count == 0, "실행 직후 지연 없이 조회했다")
    }

    @Test func wakingUpChecksTheServerAfterTheSettleDelayThroughTheWorkspaceNotification() async {
        let center = NotificationCenter()
        // 루프 첫 조회는 한 시간 뒤라, 이 테스트 동안의 조회는 전부 깨어남에서 온 것이다.
        let watched = srWatched(wakeSettle: 0.01, notifications: center)
        defer { watched.cleanUp() }

        watched.store.handleWake()
        let directWake = await srWait { watched.server.count == 1 }
        #expect(directWake, "handleWake 가 서버를 치지 않았다")

        // 감시를 켜면 didWake 노티가 handleWake 로 이어진다.
        watched.store.startServerWatch()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        let notifiedWake = await srWait { watched.server.count == 2 }
        #expect(notifiedWake, "didWake 노티가 조회로 이어지지 않았다: \(watched.server.count)")

        // 끄면 구독도 풀린다. 같은 센터를 **뒤에** 구독한 대조군이 같은 노티로 조회를 마칠 때까지 기다린 뒤 잰다.
        watched.store.stopServerWatch()
        let control = srWatched(wakeSettle: 0.01, notifications: center)
        defer { control.cleanUp() }
        control.store.startServerWatch()
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        let controlWoke = await srWait { control.server.count == 1 }
        await srSettle()
        control.store.stopServerWatch()
        #expect(controlWoke, "대조군이 깨어남으로 조회하지 않았다")
        #expect(watched.server.count == 2, "감시를 끈 뒤에도 깨어남이 조회를 일으켰다")

        // 대기가 길면 그 전엔 치지 않는다(깨어난 순간엔 네트워크가 없다). 대조군(짧은 대기)을 **나중에** 깨운다.
        let slow = srWatched(wakeSettle: 3_600)
        defer { slow.cleanUp() }
        let quick = srWatched(wakeSettle: 0.01)
        defer { quick.cleanUp() }
        slow.store.handleWake()
        quick.store.handleWake()
        let quickWoke = await srWait { quick.server.count == 1 }
        await srSettle()
        slow.store.stopServerWatch()
        #expect(quickWoke, "대조군이 깨어남으로 조회하지 않았다")
        #expect(slow.server.count == 0, "대기 없이 곧장 쳤다 — 네트워크가 붙기 전이다")
    }

    @Test func thePopoverPathAsksTheServerFirstAndStillKeepsTheGitHubDailyThrottle() async {
        let (defaults, cleanUp) = srIsolatedDefaults()
        defer { cleanUp() }
        var now = Date(timeIntervalSince1970: 3_000_000)
        let order = SRLog()
        let github = SRGitHubStub(data: srTagJSON("v0.3.20"), log: order)
        let server = SRServerStub(.success(srRelease("0.3.20", build: 72)), log: order)
        let store = UpdateCheckStore(
            currentVersion: "0.3.19",
            fetcher: { url in try await github.fetch(url) },
            clock: { now },
            defaults: defaults,
            currentBuild: 71,
            workspaceNotifications: nil
        )
        store.serverFetcher = { try await server.fetch() }

        await store.checkIfStale()
        #expect(order.entries == ["server", "github"], "팝오버 경로가 서버를 먼저 보지 않았다")
        #expect(store.latestVersion == "v0.3.20")
        #expect(store.latestBuild == 72)

        // 30초 뒤: 서버는 60초 스로틀, GitHub 은 24h 스로틀 — 둘 다 안 친다.
        now = now.addingTimeInterval(30)
        await store.checkIfStale()
        #expect(server.count == 1)
        #expect(github.count == 1)

        // 61초 뒤: 서버만 다시 친다(GitHub 은 여전히 하루 1회).
        now = now.addingTimeInterval(31)
        await store.checkIfStale()
        #expect(server.count == 2)
        #expect(github.count == 1, "서버 조회가 GitHub 하루 1회 스로틀을 무너뜨렸다")

        // 25시간 뒤: 둘 다 친다.
        now = now.addingTimeInterval(25 * 3_600)
        await store.checkIfStale()
        #expect(server.count == 3)
        #expect(github.count == 2)
    }

    // MARK: ⑤ 배선

    /// AppDelegate 배선 세 줄을 소스로 못 박는다(주석은 걷어내고 본다). 조회기가 nil 이면 서버 메서드가 전부 no-op 이라
    /// 이 세 줄을 지워도 컴파일도 단위 테스트도 **조용히 초록**이다 — 그 순간 모든 앱이 서버 알림을 잃고 하루 1회 GitHub 로 돌아간다.
    @Test func theAppDelegateWiresTheServerWatchOnceAfterTheOverlayExists() throws {
        let app = srStrippingComments(try String(contentsOf: srSourceURL("CheckApp.swift"), encoding: .utf8))
        let wiringInOrder = [
            "overlayController = CheckOverlayController(",
            "updateCheck.serverFetcher =",
            "updateCheck.onNewVersionAvailable =",
            "updateCheck.startServerWatch()",
        ]
        var previousEnd = app.startIndex
        for needle in wiringInOrder {
            #expect(app.components(separatedBy: needle).count - 1 == 1, "\(needle) 가 정확히 한 번이 아니다")
            let found = try #require(app.range(of: needle), "\(needle) 배선이 사라졌다")
            #expect(previousEnd <= found.lowerBound,
                    "\(needle) 가 앞 배선보다 먼저 온다 — 말풍선 자리가 없을 때 첫 조회가 새 버전을 들고 올 수 있다")
            previousEnd = found.upperBound
        }
        let fetcher = try #require(app.range(of: "updateCheck.serverFetcher ="))
        #expect(app[fetcher.upperBound...].prefix(80).contains("fetchLatestRelease()"), "조회기가 app_latest_release 를 안 부른다")
        let callback = try #require(app.range(of: "updateCheck.onNewVersionAvailable ="))
        #expect(app[callback.upperBound...].prefix(120).contains("showUpdateBubbleIfNeeded()"), "새 버전 콜백이 말풍선을 안 띄운다")
    }
}

// MARK: - 헬퍼

/// 소스 파일 URL(이 테스트 파일에서 저장소 루트로 올라간다).
private func srSourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)   // Tests/checkTests/V0320ServerReleaseTests.swift
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // (repo root)
        .appendingPathComponent("Sources/check/\(name)")
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸 코드. V0320MenuBarUpdateDotTests 의 v0320StrippingComments 와 같은 규칙이다
/// (이 저장소의 소스 계약 도구는 파일마다 private 사본을 둔다). 걷어내지 않으면 설명문의 낱말이 단언에 걸린다.
private func srStrippingComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") {
                    rest = rest[close.upperBound...]
                    inBlock = false
                } else {
                    rest = ""
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]
                rest = rest[block.upperBound...]
                inBlock = true
                continue
            }
            if let comment = lineComment {
                kept += rest[..<comment.lowerBound]
                rest = ""
                continue
            }
            kept += rest
            rest = ""
        }
        output += kept + "\n"
    }
    return output
}

private struct SRBoom: Error {}

private func srRelease(_ version: String?, build: Int?, notes: [String]? = [], v: Int? = 1) -> AppLatestRelease {
    AppLatestRelease(v: v, version: version, build: build, notes: notes, publishedAt: nil)
}

/// GitHub 릴리스 JSON 스텁(tag_name + 선택 body).
private func srTagJSON(_ tag: String, body: String? = nil) -> Data {
    var object: [String: String] = ["tag_name": tag]
    if let body { object["body"] = body }
    return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

/// 격리 defaults(테스트마다 고유 스위트). 끝나면 도메인을 지운다 — 남기면 테스트 실행마다 스위트 파일이 쌓인다.
private func srIsolatedDefaults() -> (defaults: UserDefaults, cleanUp: () -> Void) {
    let suite = "v0320-server-release-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (defaults, { defaults.removePersistentDomain(forName: suite) })
}

/// 서버 경로 테스트용 스토어. 내 버전 0.3.19 / 빌드 71 이 기본이고, 워크스페이스 노티는 기본으로 끊는다(실제 센터 미접촉).
@MainActor
private func srStore(
    defaults: UserDefaults,
    currentVersion: String = "0.3.19",
    currentBuild: Int? = 71,
    github: Data = srTagJSON("v0.3.19"),
    clock: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000_000) },
    interval: TimeInterval = 300,
    initialDelay: TimeInterval = 5,
    wakeSettle: TimeInterval = 10,
    notifications: NotificationCenter? = nil
) -> UpdateCheckStore {
    UpdateCheckStore(
        currentVersion: currentVersion,
        fetcher: { _ in github },
        clock: clock,
        defaults: defaults,
        currentBuild: currentBuild,
        serverWatchInterval: interval,
        serverWatchInitialDelay: initialDelay,
        wakeSettleDelay: wakeSettle,
        workspaceNotifications: notifications
    )
}

/// 조건이 설 때까지 짧게 양보하며 기다린다(성공은 조건이 서는 즉시 돌아온다).
///
/// **벽시계 시한만으로 포기하지 않는다.** 전체 필터 실행에서 메인 액터가 한 번에 76초 막히는 것을 실측했다 —
/// 그동안은 이 폴링도, 기다리는 루프도 못 돈다. 막힘이 풀린 순간 시한만 보면 루프가 한 번도 못 돈 채 "실패"로 끝난다.
/// 그래서 시한과 **최소 폴링 횟수**(= 메인 액터 차례를 실제로 받은 횟수)를 둘 다 넘긴 뒤에만 실패로 본다.
@MainActor
private func srWait(
    timeout: TimeInterval = 30,
    minimumPolls: Int = 100,
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    var polls = 0
    while !condition() {
        if polls >= minimumPolls, Date() > deadline { return false }
        polls += 1
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// 대조군이 끝난 뒤 메인 액터 차례를 몇 번 더 넘긴다 — 대조군 바로 뒤에 줄 선 뮤턴트의 조회가 한 박자 늦게 올 수 있다.
@MainActor
private func srSettle(turns: Int = 5) async {
    for _ in 0..<turns { try? await Task.sleep(for: .milliseconds(10)) }
}

/// 서버 조회기 스텁을 물린 스토어 한 벌(감시·깨어남 테스트용). 기본은 루프 첫 조회·주기가 한 시간이라 루프가 끼어들지 않는다.
@MainActor
private func srWatched(
    interval: TimeInterval = 3_600,
    initialDelay: TimeInterval = 3_600,
    wakeSettle: TimeInterval = 10,
    notifications: NotificationCenter? = nil
) -> (store: UpdateCheckStore, server: SRServerStub, cleanUp: () -> Void) {
    let (defaults, cleanUp) = srIsolatedDefaults()
    let store = srStore(
        defaults: defaults,
        interval: interval,
        initialDelay: initialDelay,
        wakeSettle: wakeSettle,
        notifications: notifications
    )
    let server = SRServerStub(.success(srRelease("0.3.19", build: 71)))
    store.serverFetcher = { try await server.fetch() }
    // 정리 때 루프·구독도 함께 끈다 — 단언이 실패해 중간에 빠져나가도 한 시간짜리 루프가 프로세스에 남지 않게.
    return (store, server, { store.stopServerWatch(); cleanUp() })
}

/// 호출 순서/콜백 값을 모으는 상자(메인 액터 전용).
@MainActor
private final class SRLog {
    var entries: [String] = []
}

/// 서버 조회기 스텁: 호출 횟수를 세고 정해 둔 결과를 돌려준다(지연 선택). 메인 액터 전용.
@MainActor
private final class SRServerStub {
    private(set) var count = 0
    var result: Result<AppLatestRelease, any Error>
    private let delay: Duration?
    private let log: SRLog?

    init(_ result: Result<AppLatestRelease, any Error>, delay: Duration? = nil, log: SRLog? = nil) {
        self.result = result
        self.delay = delay
        self.log = log
    }

    func fetch() async throws -> AppLatestRelease {
        count += 1
        log?.entries.append("server")
        if let delay { try? await Task.sleep(for: delay) }
        return try result.get()
    }
}

/// GitHub 페처 스텁: 호출 횟수를 세고 순서 로그에 남긴다. 메인 액터 전용.
@MainActor
private final class SRGitHubStub {
    private(set) var count = 0
    private let data: Data
    private let log: SRLog?

    init(data: Data, log: SRLog? = nil) {
        self.data = data
        self.log = log
    }

    func fetch(_ url: URL) async throws -> Data {
        count += 1
        log?.entries.append("github")
        return data
    }
}

private func srService(_ host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: SRReleaseURLProtocol.session()
    )
}

/// app_latest_release 응답 전용 스텁. 공용 URLProtocolStub 은 이 경로를 모르므로(단일 객체 jsonb) 호스트로만 갈라
/// 정해 둔 본문을 돌려준다 — 프로세스 전역 가변 상태 없이(병렬 스위트가 서로의 설정을 지우지 않게).
private final class SRReleaseURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.response(host: request.url?.host ?? "")
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SRReleaseURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(host: String) -> (Int, String) {
        switch host {
        case "v0320-decode-full":
            return (200, #"{"v":1,"version":"0.3.20","build":72,"notes":["첫 줄","둘째 줄"],"published_at":"2026-09-14T05:00:00.123456+00:00"}"#)
        case "v0320-decode-empty":
            return (200, #"{"v":1,"version":null,"build":null,"notes":[],"published_at":null}"#)
        case "v0320-decode-extra":
            return (200, #"{"v":1,"version":"0.3.20","build":72,"notes":[],"published_at":null,"channel":"stable","min_build":60}"#)
        case "v0320-decode-bare":
            return (200, "{}")
        case "v0320-status-404":
            return (404, #"{"code":"PGRST202","message":"Could not find the function public.app_latest_release without parameters in the schema cache"}"#)
        default:
            return (500, "")
        }
    }
}
