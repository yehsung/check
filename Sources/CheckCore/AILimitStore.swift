#if os(macOS)
import Foundation
import Observation

// MARK: - 리밋 스토어 (맥 전용 · @MainActor · 10분 간격 · 영속)
//
// 선례는 둘이다.
//  · 간격·영속·상태 관리는 `CodexAccountUsageStore` 를 본떴다(스탬프를 러너 **전에** 찍어 실패도 간격을
//    지키게 하는 관용구, `inert()` 기본값으로 주입을 잊은 테스트가 프로세스를 띄우지 못하게 하는 fail-closed).
//  · 외부 HTTP 의 조용한 실패는 `UpdateCheckStore` 를 본떴다(주입형 fetcher · 실패는 사용자를 방해하지 않는다).
//
// ## 왜 주기가 10분이고 강제 갱신에도 5분 하한이 있는가
// Claude 의 사용량 엔드포인트는 **5분에 5회**가 상한이고 6번째부터 429 `retry-after: 300` 이다(실측 2026-10-07).
// 팝오버는 여닫기가 잦아서, 열 때마다 치면 평범한 사용자가 몇 분 만에 자기 계정을 5분간 잠근다.
// 그래서 `refreshInterval` 10분 · `forcedRefreshFloor` 5분 · 캐시 TTL 5분이다. 429 를 받으면
// `retryAfter` 가 끝날 때까지 **완전히 침묵한다** — 30초마다 다시 노크하는 구현은 300초 금지창에서 틀린 동작이다.
//
// ## 실패해도 직전 값을 버리지 않는다
// 사용률은 한 창 안에서 올라가기만 하므로 마지막 값은 **안전한 하한**이다(`AILimitFreshnessRule` 머리말).
// 그래서 네트워크·429·만료에서는 영속된 값을 그대로 들고 있고, 나이 캡션만 낡는다. 숨기는 것은
// "그 도구를 안 쓴다 / 우리가 볼 수 없다"(`AILimitReadFailure.hidesProvider`) 뿐이다.
//
// ## 자동 감지 — 설정 토글이 없다
// 자격증명이 하나도 없으면 `isAvailable == false` 이고 화면은 섹션을 **통째로 숨긴다**(2026-10-07 사용자 결정).
// 그래서 "AI 리밋 보기" 스위치가 없다 — 쓰는 사람에게만 저절로 생기고, 안 쓰는 사람은 그 줄을 본 적이 없다.

/// 리더 셋을 한 번 돌린 결과. 제공자마다 성공이거나 분류된 실패다.
package struct AILimitReadOutcome: Sendable {
    package var results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>]

    package init(results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>] = [:]) {
        self.results = results
    }

    /// 성공한 제공자 스냅샷(정렬).
    package var snapshots: [AILimitProviderSnapshot] {
        results.values
            .compactMap { try? $0.get() }
            .sorted { $0.provider.sortOrder < $1.provider.sortOrder }
    }

    /// 실패 분류만.
    package var failures: [AILimitProvider: AILimitReadFailure] {
        results.compactMapValues { result in
            switch result {
            case .success: return nil
            case .failure(let error): return error.failure
            }
        }
    }

    /// 이번 바퀴에서 받은 가장 긴 `retry-after`(초). 없으면 nil.
    package var retryAfter: TimeInterval? {
        results.values.compactMap { result -> TimeInterval? in
            switch result {
            case .success: return nil
            case .failure(let error): return error.retryAfter
            }
        }.max()
    }
}

@Observable
@MainActor
package final class AILimitStore {
    /// 리더 셋을 한 번 돌리는 일. 프로덕션은 `live()` 가 만들고, 테스트는 고정 결과를 돌려주는 클로저를 넣는다.
    package typealias Runner = @Sendable (_ now: Date) async -> AILimitReadOutcome

    // MARK: 상수

    package nonisolated static let snapshotKey = "check.aiLimits.snapshot"
    package nonisolated static let failuresKey = "check.aiLimits.failures"
    /// 평상시 갱신 주기(초). 10분 — Claude 의 5분/5회 상한에 여유를 두고도 5시간 창의 변화를 놓치지 않는 값이다.
    package nonisolated static let refreshInterval: TimeInterval = 600
    /// 팝오버·창을 열었을 때의 하한(초). 5분 — 이 아래로 내려가면 여닫기만으로 429 를 맞는다.
    package nonisolated static let forcedRefreshFloor: TimeInterval = 300
    /// 들고 있는 값을 '지금 값'으로 쓰는 수명(초). 이 안이면 창을 열어도 네트워크를 안 쓴다.
    package nonisolated static let cacheTTL: TimeInterval = 300
    /// 429 의 `retry-after` 를 못 읽었을 때의 침묵 길이(초). 실측 헤더 값과 같은 300.
    package nonisolated static let defaultBackoff: TimeInterval = 300

    // MARK: 상태

    /// 마지막으로 받은 묶음(실패해도 유지 — 머리말). nil = 한 번도 못 읽었다.
    package private(set) var bundle: AILimitSnapshotBundle?
    /// 제공자별 마지막 실패 분류. 성공한 제공자는 여기서 사라진다.
    package private(set) var failures: [AILimitProvider: AILimitReadFailure] = [:]
    /// 마지막 **시도** 시각(주입 시계). 간격 판정의 기준.
    package private(set) var lastAttemptAt: Date?
    /// 이 시각 전에는 아무것도 하지 않는다(429 백오프). nil = 제한 없음.
    package private(set) var silentUntil: Date?
    /// 러너가 불린 횟수(테스트 계측 — 간격·백오프·재진입 가드가 실제로 막는지).
    @ObservationIgnored package private(set) var runnerCallCount = 0
    @ObservationIgnored private var inFlight = false

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let runner: Runner

    package init(defaults: UserDefaults, clock: @escaping () -> Date = { Date() }, runner: @escaping Runner) {
        self.defaults = defaults
        self.clock = clock
        self.runner = runner
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(AILimitSnapshotBundle.self, from: data),
           restored.schemaVersion <= AILimitSnapshotBundle.currentSchemaVersion {
            bundle = restored
        }
        if let data = defaults.data(forKey: Self.failuresKey),
           let restored = try? JSONDecoder().decode([String: AILimitReadFailure].self, from: data) {
            // 모르는 제공자 키는 버린다(열거값 확장 함정 — 접어서 남의 실패를 내 카드에 붙이지 않는다).
            failures = restored.reduce(into: [:]) { out, pair in
                guard let provider = AILimitProvider(rawValue: pair.key) else { return }
                out[provider] = pair.value
            }
        }
    }

    /// 무해 인스턴스: 격리 defaults + 아무것도 안 읽는 러너. `WorkTimerStore` 의 기본값이라, 주입을 잊은
    /// 테스트가 실제 키체인·`agy`·네트워크를 건드리는 일이 **구조적으로** 없다(fail-closed).
    ///
    /// ★★ 스위트 이름이 **절대 경로**이고 **UUID 가 없다.** 둘 다 실측으로 못 박힌 값이다.
    ///   · 평범한 도메인 이름(`"check.aiLimits.inert.…"`)을 주면 `cfprefsd` 가 `~/Library/Preferences` 에
    ///     plist 를 만든다. 선례인 `CodexAccountUsageStore.inert()` 는 같은 꼴인데도 파일이 안 생기는데,
    ///     그 스토어는 무해 경로에서 defaults 에 **아무것도 쓰지 않기** 때문이다. 이 스토어는 `refresh` 끝에
    ///     `persist()` 가 실패 표를 **빈 사전이라도** 쓴다 → 바퀴를 한 번 돈 inert 마다 파일 하나가 생긴다.
    ///   · UUID 를 붙이면 그 파일이 **인스턴스마다 다른 이름**이 된다. 2026-10-07 실측: 전체 스위트 한 바퀴가
    ///     `~/Library/Preferences` 에 1,454개를 남겼다. 62만 개가 `cfprefsd` 를 통째로 죽여 로그아웃·유령
    ///     기기·토큰 2배를 한 뿌리에서 만든 그 사고와 같은 가족이다.
    ///   그래서 이름은 `$TMPDIR` 아래 **고정** 경로다. inert 가 쓰는 내용은 어떤 인스턴스에서나 같으므로
    ///   (묶음 없음 + 빈 실패 표) 도메인을 나눠 써도 서로의 관측을 바꾸지 못한다 — 나눠 쓰는 대가가 없다.
    package static func inert() -> AILimitStore {
        let name = FileManager.default.temporaryDirectory
            .appendingPathComponent("check-ai-limits-inert").path
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return AILimitStore(defaults: defaults, runner: { _ in AILimitReadOutcome() })
    }

    // MARK: 표시 재료

    /// 화면에 그릴 제공자 카드(정렬 · 미연동 제거).
    package var visibleProviders: [AILimitProviderSnapshot] {
        bundle?.visibleProviders ?? []
    }

    /// 이 맥에 리밋 축을 보여 줄 근거가 있는가. **없으면 화면이 섹션을 통째로 숨긴다**(설정 토글 없음).
    ///
    /// 근거는 둘이다: ① 읽은 창이 하나라도 있다, ② 숨기지 않는 실패가 하나라도 있다(만료·429·네트워크 —
    /// 그 사람은 그 도구를 쓰고 있고 우리가 지금만 못 읽는 것이다).
    package var isAvailable: Bool {
        if !visibleProviders.isEmpty { return true }
        return failures.values.contains { !$0.hidesProvider }
    }

    /// 목록에 세울 제공자 순서(읽은 것 + 숨기지 않는 실패). 실패만 있는 제공자도 카드를 세워 문구를 말한다.
    package var listedProviders: [AILimitProvider] {
        var seen = Set<AILimitProvider>()
        var out: [AILimitProvider] = []
        for snapshot in visibleProviders where seen.insert(snapshot.provider).inserted {
            out.append(snapshot.provider)
        }
        for (provider, failure) in failures where !failure.hidesProvider && seen.insert(provider).inserted {
            out.append(provider)
        }
        return out.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 한 줄 요약(메뉴바·팝오버)이 그릴 값. 모든 제공자의 모든 창을 합친다 — 가장 많이 쓴 쪽이 하한이고,
    /// 캡션은 가장 낡은 기여자가 정한다(규칙은 `AILimitFreshnessRule.combine` 한 곳).
    package func summary(now: Date) -> AILimitDisplay {
        AILimitFreshnessRule.combine(visibleProviders.flatMap {
            AILimitFreshnessRule.displays(provider: $0, now: now)
        })
    }

    /// 창 하나의 표시(카드가 쓴다). 뷰가 직접 계산하지 않는다.
    package func display(provider: AILimitProvider, window: AILimitWindow, now: Date) -> AILimitDisplay {
        AILimitFreshnessRule.display(provider: bundle?.provider(provider), window: window, now: now)
    }

    /// 제공자 카드에 덧붙일 한 줄(없으면 nil).
    package func noticeText(provider: AILimitProvider) -> String? {
        failures[provider]?.noticeText(for: provider)
    }

    // MARK: 갱신

    /// 간격이 찼는가. 진행 중이거나 백오프 중이면 거짓.
    package func isDue(now: Date, force: Bool = false) -> Bool {
        if inFlight { return false }
        if let silentUntil, now < silentUntil { return false }
        guard let last = lastAttemptAt else { return true }
        let elapsed = now.timeIntervalSince(last)
        return force ? elapsed >= Self.forcedRefreshFloor : elapsed >= Self.refreshInterval
    }

    /// 들고 있는 값이 아직 '지금 값'인가(캐시 TTL). 창을 열 때 네트워크를 쓸지 가르는 데 쓴다.
    package func isFresh(now: Date) -> Bool {
        guard let observed = bundle?.providers.compactMap(\.latestObservedAt).max() else { return false }
        return now.timeIntervalSince(observed) < Self.cacheTTL
    }

    /// 간격이 찼을 때만 리더를 돈다. `force` 는 "사용자가 방금 팝오버·창을 열었다"일 때 쓴다(5분 하한 유지).
    package func refreshIfDue(now: Date, force: Bool = false) async {
        guard isDue(now: now, force: force) else { return }
        // 스탬프를 러너 **전에** 찍는다 — 실패도 간격을 지켜야 난사가 안 된다(CodexAccountUsageStore 와 같은 관용구).
        lastAttemptAt = now
        inFlight = true
        defer { inFlight = false }
        runnerCallCount += 1
        let outcome = await runner(now)
        apply(outcome, now: now)
    }

    /// 결과를 상태에 반영한다(순수에 가까운 지점 — 테스트가 직접 부른다).
    ///
    /// **새로 읽은 제공자는 통째로 교체한다**(옛 값과 max 를 취하지 않는다). 리셋을 지난 창은 값이 **내려가는 것이
    /// 정답**이고, '높은 쪽을 믿는다'는 규칙은 *같은 순간의 두 출처*(로컬 vs 서버)를 견줄 때의 것이다
    /// (`AILimitFreshnessRule` 머리말 — 폐기된 `max(로컬, 계정)` 증폭기와 같은 사고를 여기서 만들지 않는다).
    /// 읽지 **못한** 제공자는 들고 있던 값을 그대로 남긴다 — 그게 하한이다.
    package func apply(_ outcome: AILimitReadOutcome, now: Date) {
        var merged: [AILimitProvider: AILimitProviderSnapshot] = [:]
        for snapshot in bundle?.providers ?? [] { merged[snapshot.provider] = snapshot }
        for snapshot in outcome.snapshots { merged[snapshot.provider] = snapshot }
        // 숨기는 실패(미설치·미로그인·차단)는 들고 있던 값까지 **지운다** — 로그아웃한 사람의 옛 숫자를
        // 계속 보여 주면 그건 남의 계정 값일 수도 있다(기기를 넘겨준 경우).
        for (provider, failure) in outcome.failures where failure.hidesProvider {
            merged.removeValue(forKey: provider)
        }
        let next = AILimitSnapshotBundle(providers: merged.values.sorted { $0.provider.sortOrder < $1.provider.sortOrder })
        bundle = next
        var nextFailures = failures
        for provider in outcome.results.keys { nextFailures.removeValue(forKey: provider) }
        for (provider, failure) in outcome.failures { nextFailures[provider] = failure }
        failures = nextFailures
        silentUntil = outcome.failures.values.contains(.rateLimited)
            ? now.addingTimeInterval(outcome.retryAfter ?? Self.defaultBackoff)
            : nil
        persist()
    }

    private func persist() {
        if let bundle, let data = try? JSONEncoder().encode(bundle) {
            defaults.set(data, forKey: Self.snapshotKey)
        } else if bundle == nil {
            defaults.removeObject(forKey: Self.snapshotKey)
        }
        let raw = failures.reduce(into: [String: AILimitReadFailure]()) { out, pair in
            out[pair.key.rawValue] = pair.value
        }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.failuresKey)
        }
    }
}

// MARK: - 프로덕션 조립

extension AILimitStore {
    /// 라이브 스토어. **저장소에서 이 함수를 부르는 프로덕션 지점은 `CheckApp.swift` 한 줄뿐이다**
    /// (`CodexAccountUsageStore.live()` 와 같은 규약 — 기본값은 무해 인스턴스라 테스트가 실제 자격증명을
    /// 건드리지 않는다).
    package static func live(
        defaults: UserDefaults = .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appVersion: String,
        session: URLSession = .shared
    ) -> AILimitStore {
        let runner = liveRunner(home: home, appVersion: appVersion, session: session)
        return AILimitStore(defaults: defaults, runner: runner)
    }

    /// 리더 셋을 **동시에** 돌리는 러너. 셋이 서로를 기다리지 않아야 한다 — `agy` 는 5초짜리라
    /// 직렬로 묶으면 팝오버를 연 사람이 그만큼 더 기다린다.
    /// `nonisolated` 인 이유: 클로저 셋을 **조립만** 하므로 메인 액터일 필요가 없고, 그래야 실증 하네스나
    /// 배경 작업이 메인을 잡지 않고 한 바퀴를 돌려 볼 수 있다(`live()` 는 스토어를 만들어야 해서 메인이다).
    package nonisolated static func liveRunner(
        home: URL,
        appVersion: String,
        session: URLSession,
        processRunner: AILimitCommandRunner? = nil,
        fetcher: AILimitHTTPFetcher? = nil
    ) -> Runner {
        let process = processRunner ?? AILimitProcess.live()
        let fetch = fetcher ?? AILimitHTTP.fetcher(session: session)
        let claude = AILimitClaudeReader(runner: process, fetch: fetch, appVersion: appVersion)
        let codex = AILimitCodexReader(
            fetch: fetch,
            codexHome: CodexAccountUsageProbe.cachedCodexHome()
                ?? home.appendingPathComponent(".codex", isDirectory: true),
            appVersion: appVersion
        )
        let antigravity = AILimitAntigravityReader(
            runner: process,
            locate: { AILimitAntigravityReader.liveLocate(home: home) }
        )
        return { now in
            async let claudeResult = claude.read(now: now)
            async let codexResult = codex.read(now: now)
            async let antigravityResult = antigravity.read(now: now)
            return AILimitReadOutcome(results: [
                .claude: await claudeResult,
                .codex: await codexResult,
                .antigravity: await antigravityResult
            ])
        }
    }
}
#endif
