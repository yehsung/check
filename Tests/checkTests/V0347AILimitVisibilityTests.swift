import AppKit
import os
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.47 설정에서 AI 리밋을 **원하는 것만** · 아예 안 볼 수도 있게
//
// 사용자 요청(2026-10-07): "설정에서 AI 한도 원하는것만 표시하고, 아예 표시 안할 수도 있게 각자 조정할 수 있게".
//
// ## 이 스위트가 지키는 것 — 전부 "초록인 채로 틀릴 수 있는" 자리다
//  ① **기본값이 전부 켬**이고 끈 값은 다음 실행에도 남는다. 안 남으면 brew 업데이트 한 번에 설정이 풀린다.
//     모르는 제공자 키가 저장돼 있어도 깨지지 않고, 그 키를 **지우지도 않는다**(열거값 확장 함정).
//  ② **꺼진 제공자의 리더가 0번 불린다.** 결과만 비었는지 보는 테스트는 이 결함을 못 잡는다 —
//     리더가 불리고 결과만 버려져도 그런 테스트는 초록이고, 그때는 이미 키체인·auth.json·agy 를 건드린 뒤다.
//     그래서 ㉮ 스토어가 러너에게 **무엇을 요청했는지**와 ㉯ `liveRunner` 가 **실제로 띄운 명령·요청**을 둘 다 센다.
//  ③ 마스터가 꺼져 있으면 **갱신 자체가 없다**(러너 0회 · 시도 스탬프 없음 · 디스크에 쓰기 없음).
//  ④ 끈 제공자의 서버 행은 **그 순간 비워진다**(창 값 전부 null · 키 집합 동일 · 한 번만 · 실패하면 재시도).
//  ⑤ 끄면 팝오버 카드에서 줄이 사라지고 전부 끄면 **섹션 자체가 사라진다**(높이 0).
//  ⑥ 설정 화면이 **연동된 제공자만** 줄을 세우고, 세터 한 쌍으로만 간다(집이 둘이 되지 않는다).
//
// ## 제공자 API 를 **실제로 부르지 않는다**
// Claude 는 5분에 5회가 상한이라 스위트가 그걸 넘기면 사용자 계정이 5분간 잠긴다(실측 2026-10-07).
// 이 파일의 모든 리더 입구(`security` 프로세스 · HTTP · `agy` 탐색)는 주입된 가짜다.

// MARK: - 고정 시각·도우미

/// 고정 기준 시각(AILimitsMacTests 와 같은 값 — 두 파일이 같은 세계를 말한다).
private let vvNow = Date(timeIntervalSince1970: 1_791_300_000)

/// 격리 UserDefaults. 이름은 **반드시** `CheckTestScratch` 에서 받는다(절대 경로 · UUID 없음) —
/// 평범한 도메인 이름은 `~/Library/Preferences` 에 plist 를 쌓고, 62만 개가 `cfprefsd` 를 죽인 전례가 있다.
private func vvDefaults(_ function: String = #function, line: Int = #line) -> UserDefaults {
    let name = CheckTestScratch.uniqueSuitePath(function: function, line: line)
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// 창 둘을 가진 제공자 스냅샷.
private func vvSnapshot(
    _ provider: AILimitProvider,
    fiveHour: Double = 27,
    weekly: Double = 60,
    observedAt: Date = vvNow
) -> AILimitProviderSnapshot {
    AILimitProviderSnapshot(
        provider: provider,
        windows: [
            AILimitWindowSnapshot(window: .fiveHour, usedPercent: fiveHour,
                                  resetsAt: observedAt.addingTimeInterval(3_600),
                                  observedAt: observedAt, source: .local),
            AILimitWindowSnapshot(window: .weekly, usedPercent: weekly,
                                  resetsAt: observedAt.addingTimeInterval(86_400),
                                  observedAt: observedAt, source: .local)
        ],
        planLabel: "max"
    )
}

/// 러너가 **무엇을 요청받았는지** 기록하는 가짜. 이 스위트의 ② 가 서는 자리다.
///
/// ★ 기록하는 것이 "불렸는가"가 아니라 "**누구를** 물었는가" 다. 전자만 세면 러너가 셋 다 읽고 결과에서
///   꺼진 제공자를 지우는 구현도 초록이다 — 그 구현은 키체인을 이미 건드렸다.
private final class VVRunnerSpy: @unchecked Sendable {
    /// 바퀴마다 요청받은 제공자 집합(호출 순서대로).
    private(set) var requested: [Set<AILimitProvider>] = []
    /// 이 제공자들은 읽을 수 있다고 답한다.
    var available: Set<AILimitProvider>

    init(available: Set<AILimitProvider>) {
        self.available = available
    }

    /// 어떤 제공자가 **한 번이라도** 요청됐는가.
    func askedFor(_ provider: AILimitProvider) -> Bool {
        requested.contains { $0.contains(provider) }
    }

    var callCount: Int { requested.count }

    func runner() -> AILimitStore.Runner {
        { [self] now, providers in
            requested.append(providers)
            // **요청받은 제공자만** 답한다. 러너가 요청 밖의 제공자까지 읽어 오는 세계를 흉내내지 않는다 —
            // 그 세계가 바로 결함이고, 그 결함은 위 `requested` 가 잡는다.
            var results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>] = [:]
            for provider in providers {
                results[provider] = available.contains(provider)
                    ? .success(vvSnapshot(provider, observedAt: now))
                    : .failure(AILimitReadError(.notInstalled))
            }
            return AILimitReadOutcome(results: results)
        }
    }
}

/// 리더가 **실제로 건드린 것**을 세는 기록기(프로세스 명령 · HTTP 요청).
/// ②㉯ 가 서는 자리다 — 여기 숫자가 0 이어야 "안 읽었다"가 사실이다.
private struct VVProbeState {
    var commands: [String] = []
    var hosts: [String] = []
}

private final class VVReaderProbe: Sendable {
    /// 두 리더가 서로 다른 작업에서 동시에 적는다(러너가 셋을 나란히 돌린다) — 자물쇠로 직렬화한다.
    /// `NSLock.lock()` 은 비동기 문맥에서 쓸 수 없어(컴파일러가 막는다) 이 저장소가 쓰는 것과 같은
    /// `OSAllocatedUnfairLock` 범위 잠금을 쓴다(`CodexAccountUsageProbe.LocateCache` 와 같은 관용구).
    private let state = OSAllocatedUnfairLock(initialState: VVProbeState())

    var commands: [String] { state.withLock { $0.commands } }
    var fetchedHosts: [String] { state.withLock { $0.hosts } }

    var processRunner: AILimitCommandRunner {
        { [self] command in
            let name = command.executable.lastPathComponent
            state.withLock { $0.commands.append(name) }
            // 빈 stdout = 실패. 파싱까지 가지 않는다(이 스위트가 재는 것은 "불렸나" 하나다).
            return AILimitCommandOutput(status: 1, stdout: Data())
        }
    }

    var fetcher: AILimitHTTPFetcher {
        { [self] request in
            let host = request.url?.host ?? ""
            state.withLock { $0.hosts.append(host) }
            return AILimitHTTPResponse(status: 500, body: Data(), retryAfter: nil, transportFailed: false)
        }
    }

    func ranCommand(_ name: String) -> Bool { commands.contains(name) }
    func fetched(host: String) -> Bool { fetchedHosts.contains(host) }
}

/// 움직이는 시계. 트레일링 업로드가 **그 시점의 now** 로 도는지 가르려면 두 바퀴의 시각이 달라야 한다 —
/// 고정 시계(`{ vvNow }`)로는 옛 now 를 재사용해도 같은 값이라 그 결함이 보이지 않는다
/// (기준선이 같은 입력이면 그 테스트는 영원히 초록이다).
private final class VVClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// 관찰 알림이 왔는가. `withObservationTracking` 의 onChange 는 `@Sendable` 이라 지역 변수를 못 잡는다.
private final class VVObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func hit() { lock.lock(); value = true; lock.unlock() }
    var wasHit: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - ① 설정 모델: 기본 전부 켬 · 영속 · 모르는 키 보존

@Suite("v0.3.47 — 표시 설정 모델")
@MainActor
struct V0347AILimitVisibilityModelTests {
    /// 기본값은 **전부 켬**이고, 끈 값은 다음 실행에도 남는다.
    ///
    /// 없으면: 기본값을 꺼짐으로 바꿔도 초록이고, 그러면 업데이트하는 순간 **모든 사람의** 리밋이 사라진다
    /// (요건은 "기존 사용자에게 변화가 없어야 한다").
    @Test
    func defaultsToEverythingOnAndSurvivesRelaunch() {
        let defaults = vvDefaults()
        let first = AILimitStore(defaults: defaults, clock: { vvNow }, runner: { _, _ in AILimitReadOutcome() })
        #expect(first.visibility == .allEnabled)
        #expect(first.visibility.masterEnabled)
        #expect(first.visibility.enabledProviders == Set(AILimitProvider.allCases))
        for provider in AILimitProvider.allCases {
            #expect(first.visibility.isEnabled(provider), "\(provider) 가 기본으로 꺼져 있다")
        }

        first.setProviderEnabled(.codex, false)
        #expect(first.visibility.isProviderOn(.codex) == false)
        #expect(first.visibility.isProviderOn(.claude), "한 제공자를 끄자 다른 제공자도 꺼졌다")

        let relaunched = AILimitStore(defaults: defaults, clock: { vvNow }, runner: { _, _ in AILimitReadOutcome() })
        #expect(relaunched.visibility.isProviderOn(.codex) == false, "끈 값이 재실행에 되살아났다")
        #expect(relaunched.visibility.masterEnabled)
        #expect(relaunched.visibility.enabledProviders == [.claude, .antigravity])

        relaunched.setMasterEnabled(false)
        let again = AILimitStore(defaults: defaults, clock: { vvNow }, runner: { _, _ in AILimitReadOutcome() })
        #expect(again.visibility.masterEnabled == false, "끈 마스터가 재실행에 되살아났다")
        // ★ 마스터를 껐어도 제공자 스위치는 **그대로** 기억된다 — 다시 켤 때 내 선택이 돌아와야 한다.
        #expect(again.visibility.isProviderOn(.codex) == false)
        #expect(again.visibility.isProviderOn(.claude))

        // 키 이름을 못 박는다. 바꾸면 이미 끈 사람의 설정이 아무 말 없이 켜짐으로 돌아간다.
        #expect(AILimitStore.visibilityKey == "check.aiLimits.show")
        #expect(AILimitStore.disabledProvidersKey == "check.aiLimits.disabledProviders")
        #expect(AILimitStore.pendingClearKey == "check.aiLimits.pendingClear")
    }

    /// 모르는 제공자 키가 저장돼 있어도 **깨지지 않고, 지워지지도 않는다**.
    ///
    /// 왜 보존이 요건인가: 신버전에서 끈 네 번째 제공자를 구버전이 저장하며 지워 버리면, 다시 신버전으로
    /// 올라갈 때 그 제공자가 **아무 말 없이 켜진다**(열거값 확장 함정의 쌍둥이).
    /// 그리고 모르는 키가 아는 제공자의 판정을 흔들어서도 안 된다.
    @Test
    func unknownProviderKeysSurviveAndChangeNothing() {
        let defaults = vvDefaults()
        defaults.set(["codex", "gemini", "future-tool"], forKey: AILimitStore.disabledProvidersKey)

        let store = AILimitStore(defaults: defaults, clock: { vvNow }, runner: { _, _ in AILimitReadOutcome() })
        #expect(store.visibility.isProviderOn(.codex) == false)
        #expect(store.visibility.isProviderOn(.claude), "모르는 키가 아는 제공자를 껐다")
        #expect(store.visibility.enabledProviders == [.claude, .antigravity])

        // 저장을 한 번 더 거쳐도 모르는 키가 **살아 있다**.
        store.setProviderEnabled(.antigravity, false)
        let saved = Set(defaults.stringArray(forKey: AILimitStore.disabledProvidersKey) ?? [])
        #expect(saved.contains("gemini"), "모르는 제공자 키를 저장하면서 지웠다")
        #expect(saved.contains("future-tool"))
        #expect(saved == ["codex", "gemini", "future-tool", "antigravity"])

        // 모르는 키만으로는 비우기 대기열에 아무것도 들어가지 않는다(올릴 행을 만들 수 없는 이름이다).
        #expect(store.pendingClear == [])
    }

    /// 비우기 대기열도 **영속된다** — 끄고 바로 앱이 죽으면 그 행이 서버에 영원히 남는다.
    @Test
    func pendingClearSurvivesRelaunch() async {
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude, .codex])
        let store = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        await store.refreshIfDue(now: vvNow)
        #expect(store.visibleProviders.count == 2)

        store.setProviderEnabled(.codex, false)
        #expect(store.pendingClear == [.codex])

        let reborn = AILimitStore(defaults: defaults, clock: { vvNow }, runner: { _, _ in AILimitReadOutcome() })
        #expect(reborn.pendingClear == [.codex], "비우기 대기열이 재실행에 사라졌다 — 그 행은 서버에 영원히 남는다")
        // 재실행에서도 **집어서** 비운다(세대는 복원 순서로 다시 매겨진다 — `AILimitClearClaim` 머리말).
        reborn.markCleared(reborn.claimPendingClear())
        #expect(reborn.pendingClear.isEmpty)

        let third = AILimitStore(defaults: defaults, clock: { vvNow }, runner: { _, _ in AILimitReadOutcome() })
        #expect(third.pendingClear.isEmpty, "비운 사실이 재실행에 되살아났다 — 같은 빈 행을 매번 다시 올린다")
    }

    /// ★ 비우기 대기열은 **관찰 대상이 아니다**(`@ObservationIgnored`).
    ///
    /// 같은 커밋이 더한 다른 업로드 상태들(`uploadInFlight`·`uploadPendingTrailing`·계측값)엔 붙어 있는데
    /// 이 둘(`pendingClearGenerations`·`clearSequence`)만 빠져 있었다. 관찰 대상이면 30초 틱마다 도는
    /// 업로드가 대기열을 만질 때 그 값을 읽은 뷰가 전부 무효화돼, 아무 숫자도 안 바뀐 틱에 설정 창·팝오버가
    /// 다시 그려진다. **모양(글자)이 아니라 관찰이 실제로 트이는지**를 잰다.
    @Test
    func theClearQueueIsNotObservable() async {
        let limits = AILimitStore(defaults: vvDefaults(), clock: { vvNow },
                                  runner: VVRunnerSpy(available: [.claude]).runner())
        await limits.refreshIfDue(now: vvNow)
        #expect(limits.pendingClear.isEmpty, "전제: 대기열이 비어 있다")

        let queueFlag = VVObservationFlag()
        withObservationTracking { _ = limits.pendingClear } onChange: { queueFlag.hit() }
        limits.setProviderEnabled(.claude, false)
        #expect(limits.pendingClear == [.claude], "전제: 대기열이 실제로 바뀌었다")
        #expect(queueFlag.wasHit == false,
                "비우기 대기열이 관찰 대상이다 — 틱마다 아무 숫자도 안 바뀐 화면이 다시 그려진다")

        // ★ 대조군: 같은 세터가 바꾼 **표시 설정은 관찰 대상이어야 한다**. 이게 없으면 위 단언은
        //   `withObservationTracking` 을 잘못 쓴 날에도 초록이다(아무것도 추적하지 않으면 늘 안 온다).
        let visibilityFlag = VVObservationFlag()
        withObservationTracking { _ = limits.visibility } onChange: { visibilityFlag.hit() }
        limits.setProviderEnabled(.claude, true)
        #expect(visibilityFlag.wasHit, "표시 설정이 관찰 대상이 아니다 — 스위치를 눌러도 설정 창이 안 바뀐다")
    }
}

// MARK: - ② 읽기 게이트: 꺼진 제공자의 리더는 0번 불린다

@Suite("v0.3.47 — 읽기 게이트(꺼진 리더 0회)")
@MainActor
struct V0347AILimitReadGateTests {
    /// ★ **꺼진 제공자를 러너에게 요청하지 않는다.**
    ///
    /// 결과가 비었는지만 보는 단언은 이 결함을 못 잡는다 — 리더가 불리고 결과만 버려져도 초록이다.
    /// 그래서 가짜 러너가 "누구를 물었는지"를 기록하고, 꺼진 제공자가 그 기록에 **한 번도** 없어야 한다.
    @Test
    func disabledProviderIsNeverRequestedFromTheRunner() async {
        let spy = VVRunnerSpy(available: Set(AILimitProvider.allCases))
        let store = AILimitStore(defaults: vvDefaults(), clock: { vvNow }, runner: spy.runner())

        // 대조군 먼저: 전부 켜면 셋 다 요청된다(기준선이 갈려야 아래 단언이 뜻을 갖는다).
        await store.refreshIfDue(now: vvNow)
        #expect(spy.requested == [Set(AILimitProvider.allCases)])

        store.setProviderEnabled(.codex, false)
        await store.refreshIfDue(now: vvNow.addingTimeInterval(601))
        #expect(spy.callCount == 2)
        #expect(spy.requested.last == [.claude, .antigravity])

        store.setProviderEnabled(.antigravity, false)
        await store.refreshIfDue(now: vvNow.addingTimeInterval(1_202))
        #expect(spy.requested.last == [.claude])

        // 끈 뒤 **단 한 번도** 다시 요청되지 않았는지 — 바퀴 전체를 통틀어 센다.
        let codexAsks = spy.requested.filter { $0.contains(.codex) }.count
        #expect(codexAsks == 1, "끈 뒤에도 Codex 를 \(codexAsks - 1)번 더 물었다 — 그만큼 auth.json 을 읽었다")
        // 그리고 화면에서도 사라졌다(읽지 않으니 값이 낡지도 않는다 — 들고 있던 값은 남지만 안 보인다).
        #expect(store.listedProviders == [.claude])
        #expect(store.visibleProviders.map(\.provider) == [.claude])
    }

    /// ★ 마스터를 끄면 **갱신 타이머 자체가 돌지 않는다**: 러너 0회 · 시도 스탬프 없음 · 디스크에 쓰기 없음.
    ///
    /// `isDue` 가 거짓인 것으로 끝이 아니라 `refreshIfDue` 가 **아무 부작용도 남기지 않아야** 한다 —
    /// 스탬프를 찍는 구현은 "끈 동안에도 10분마다 뭔가를 한다"는 뜻이고, 그건 약속과 다르다.
    @Test
    func masterOffStopsTheRefreshTimerEntirely() async {
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: Set(AILimitProvider.allCases))
        let store = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        store.setMasterEnabled(false)

        #expect(store.isDue(now: vvNow) == false)
        #expect(store.isDue(now: vvNow, force: true) == false, "강제 갱신이 마스터를 뚫었다")
        await store.refreshIfDue(now: vvNow, force: true)
        await store.refreshIfDue(now: vvNow.addingTimeInterval(86_400), force: true)
        #expect(spy.callCount == 0, "마스터가 꺼진 채로 리더를 \(spy.callCount)번 돌렸다")
        #expect(store.runnerCallCount == 0)
        #expect(store.lastAttemptAt == nil, "끈 축이 시도 스탬프를 찍었다 — 아무 일도 안 해야 한다")
        #expect(defaults.object(forKey: AILimitStore.lastAttemptKey) == nil, "끈 축이 디스크에 썼다")

        // 대조군: 다시 켜면 같은 입력으로 바로 돈다(위 단언이 "애초에 못 도는 세계"에서 초록이 아니다).
        store.setMasterEnabled(true)
        #expect(store.isDue(now: vvNow))
        await store.refreshIfDue(now: vvNow)
        #expect(spy.callCount == 1)
        #expect(store.visibleProviders.count == AILimitProvider.allCases.count)
    }

    /// 제공자를 **하나씩** 다 끈 것도 마스터를 끈 것과 같다 — 읽을 리더가 없는데 바퀴를 돌리면
    /// 빈 결과를 받아 와 `apply` 가 디스크를 쓴다.
    @Test
    func turningEveryProviderOffAlsoStopsTheTimer() async {
        let spy = VVRunnerSpy(available: Set(AILimitProvider.allCases))
        let store = AILimitStore(defaults: vvDefaults(), clock: { vvNow }, runner: spy.runner())
        for provider in AILimitProvider.allCases { store.setProviderEnabled(provider, false) }
        #expect(store.visibility.masterEnabled, "전제: 마스터는 켜져 있다 — 가르는 것이 제공자 셋뿐이어야 한다")
        #expect(store.visibility.enabledProviders.isEmpty)
        #expect(store.isDue(now: vvNow, force: true) == false)
        await store.refreshIfDue(now: vvNow, force: true)
        #expect(spy.callCount == 0)
        #expect(store.isAvailable == false)
    }

    /// ★★ **`liveRunner` 가 꺼진 제공자의 자격증명에 손을 대지 않는다** — 리더 입구에서 센다.
    ///
    /// 위 테스트들은 "스토어가 무엇을 요청했나"를 재고, 이 테스트는 그 요청이 **실제 프로세스·네트워크로
    /// 번역되는 자리**를 잰다. 둘이 다 필요한 이유: 러너 안쪽에서 `providers` 를 무시하고 셋 다 읽으면
    /// 위 테스트는 전부 초록인데 키체인은 열린다.
    ///
    /// 세는 입구 셋(제공자별로 다른 입구라 서로를 가린다):
    ///   · Claude      → `/usr/bin/security`(키체인) + `api.anthropic.com`
    ///   · Codex       → `chatgpt.com`
    ///   · 안티그래비티 → `agy` 프로세스
    ///
    /// ## ★★ Codex 대조군은 `auth.json` 이 **실재해야** 선다 (2026-10-08 실증한 P2)
    /// 초안은 **빈 임시 홈**에서 돌면서 `#expect(!claudeOnly.fetched(host: "chatgpt.com"))` 를 단언했다.
    /// `.codex/auth.json` 이 없으면 러너가 Codex 를 **읽어도** `notInstalled` 로 끝나 네트워크가 0 이라,
    /// '꺼진 Codex 를 읽는' 퇴행이 들어와도 그 단언은 **영원히 초록**이다(관례: 기준선이 같은 입력이면
    /// 그 테스트는 영원히 초록). 그래서 자격증명을 실제로 두고, 켜면 요청이 있고 끄면 없다를 **양쪽에서** 잰다.
    ///
    /// ★ `codexHome` 도 **주입한다**: 기본 해결은 이 맥의 셸 캐시(`CODEX_HOME` — Orca 가 바꿔 놓는 그 값)를
    ///   읽으므로, 주입이 없으면 기계에 따라 임시 홈이 무시되고 대조군이 다시 공허해진다(그리고 그때는
    ///   **진짜** auth.json 을 읽는다).
    @Test
    func liveRunnerTouchesNothingForDisabledProviders() async throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("v0347-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        // `agy` 탐색은 **주입한다** — 기본 탐색은 이 맥의 PATH 를 읽어 기계마다 결과가 갈리고, 그러면
        // "켠 제공자는 실제로 불린다"는 대조군이 어떤 기계에서는 공허해진다.
        let fakeAgy = home.appendingPathComponent("agy")
        FileManager.default.createFile(atPath: fakeAgy.path, contents: Data())
        // Codex 자격증명을 **실제로** 둔다. JWT 가 아니므로 `exp` 클레임이 없고(= 만료를 모른다),
        // 그래서 리더는 바로 사용량 엔드포인트로 간다 — 그게 이 대조군이 재려는 바로 그 손길이다.
        let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data(#"{"tokens":{"access_token":"v0347-codex-token","account_id":"acct-v0347"}}"#.utf8)
            .write(to: codexHome.appendingPathComponent("auth.json"))

        func runner(_ probe: VVReaderProbe) -> AILimitStore.Runner {
            AILimitStore.liveRunner(
                home: home, appVersion: "t", session: .shared,
                processRunner: probe.processRunner, fetcher: probe.fetcher,
                locateAntigravity: { fakeAgy }, codexHome: codexHome)
        }

        // ① 아무도 안 켰다(마스터 끔과 같은 상태) → 명령 0 · 요청 0. **auth.json 이 있어도** 그렇다.
        let silent = VVReaderProbe()
        _ = await runner(silent)(vvNow, [])
        #expect(silent.commands.isEmpty, "빈 요청에 프로세스를 띄웠다: \(silent.commands)")
        #expect(silent.fetchedHosts.isEmpty, "빈 요청에 네트워크를 썼다: \(silent.fetchedHosts)")

        // ② Claude 만 켰다 → 키체인은 열리고, `agy` 와 chatgpt.com 에는 **손도 안 댄다**.
        let claudeOnly = VVReaderProbe()
        _ = await runner(claudeOnly)(vvNow, [.claude])
        #expect(claudeOnly.ranCommand("security"), "전제: 켠 Claude 는 키체인을 읽는다(대조군이 비면 아래가 공허하다)")
        #expect(!claudeOnly.ranCommand("agy"), "끈 안티그래비티의 `agy` 를 띄웠다")
        #expect(!claudeOnly.fetched(host: "chatgpt.com"), "끈 Codex 의 사용량 엔드포인트를 쳤다")

        // ③ 안티그래비티만 켰다 → `agy` 는 돌고, 키체인(`security`)과 네트워크는 **건드리지 않는다**.
        let agyOnly = VVReaderProbe()
        _ = await runner(agyOnly)(vvNow, [.antigravity])
        #expect(agyOnly.ranCommand("agy"), "전제: 켠 안티그래비티는 agy 를 띄운다")
        #expect(!agyOnly.ranCommand("security"), "끈 Claude 의 키체인을 열었다 — 승인 대화상자가 뜰 수도 있다")
        #expect(agyOnly.fetchedHosts.isEmpty, "안티그래비티만 켰는데 네트워크를 썼다: \(agyOnly.fetchedHosts)")

        // ④ ★ Codex 만 켰다 → **켜면 chatgpt.com 을 친다**. ②의 "안 쳤다"가 이 한 줄 때문에 뜻을 갖는다.
        let codexOnly = VVReaderProbe()
        _ = await runner(codexOnly)(vvNow, [.codex])
        #expect(codexOnly.fetched(host: "chatgpt.com"),
                "전제: 켠 Codex 는 auth.json 을 읽고 사용량 엔드포인트를 친다 — 이 줄이 빨간 날 ②는 공허하다")
        #expect(codexOnly.commands.isEmpty, "Codex 만 켰는데 프로세스를 띄웠다: \(codexOnly.commands)")
        #expect(!codexOnly.fetched(host: "api.anthropic.com"), "끈 Claude 의 사용량 엔드포인트를 쳤다")
    }

    /// ★ 게이트는 **사용자가 끌 수 있는 집합**으로 잰다 (2026-10-08 실증한 P2).
    ///
    /// 연동 안 된 제공자는 설정에 줄이 없고(섹션은 연동된 것만 세운다) 기본이 '켬'이라, **연동된 유일한
    /// 제공자를 끈 사람도** `enabledProviders` 가 안 비어 바퀴가 계속 돌았다 — 그때 `~/.codex/auth.json` 을
    /// 읽고 `agy`(5초짜리)를 띄운다. 그 사람 화면에는 끌 수 있는 줄이 그 하나뿐이라 멈출 길이 마스터밖에 없었다.
    @Test
    func turningOffTheOnlyLinkedProviderStopsTheWheel() async {
        let spy = VVRunnerSpy(available: [.claude])   // Claude 만 연동됐다
        let store = AILimitStore(defaults: vvDefaults(), clock: { vvNow }, runner: spy.runner())
        await store.refreshIfDue(now: vvNow)
        #expect(store.configurableProviders == [.claude], "전제: 설정에 줄이 서는 제공자는 Claude 하나다")
        #expect(spy.callCount == 1)

        store.setProviderEnabled(.claude, false)
        // 끌 수 있는 줄(Claude)은 다 껐다. 남은 둘은 **화면에 줄이 없는** 제공자다.
        #expect(store.visibility.enabledProviders == [.codex, .antigravity], "전제: 그 둘은 여전히 '켜짐'으로 센다")
        #expect(store.isDue(now: vvNow.addingTimeInterval(601)) == false,
                "줄이 없는 제공자가 바퀴를 살려 뒀다 — 10분마다 auth.json 을 읽고 agy 를 띄운다")
        #expect(store.isDue(now: vvNow.addingTimeInterval(601), force: true) == false, "강제 갱신이 그 게이트를 뚫었다")
        await store.refreshIfDue(now: vvNow.addingTimeInterval(601), force: true)
        #expect(spy.callCount == 1, "끈 뒤에 리더를 \(spy.callCount - 1)번 더 돌렸다")

        // 대조군 ①: 다시 켜면 같은 입력으로 바로 돈다(위 단언이 "애초에 못 도는 세계"에서 초록이 아니다).
        store.setProviderEnabled(.claude, true)
        #expect(store.isDue(now: vvNow.addingTimeInterval(601)))
        await store.refreshIfDue(now: vvNow.addingTimeInterval(601))
        #expect(spy.callCount == 2)

        // 대조군 ②: **줄이 하나도 없는 동안은 거꾸로 돈다** — 그때 닫으면 내일 Claude Code 를 깐 사람에게
        // 이 축이 영영 켜지지 않는다(실패 표도 디스크에 남아 재실행이 구해 주지 못한다).
        let blankSpy = VVRunnerSpy(available: [])
        let blank = AILimitStore(defaults: vvDefaults(), clock: { vvNow }, runner: blankSpy.runner())
        await blank.refreshIfDue(now: vvNow)
        #expect(blank.configurableProviders.isEmpty, "전제: 연동 0 — 설정에 줄이 하나도 없다")
        #expect(blank.isDue(now: vvNow.addingTimeInterval(601)), "연동을 발견할 길이 막혔다")
    }
}

// MARK: - ③ 표시: 카드에서 줄이 사라지고, 전부 끄면 섹션이 사라진다

@Suite("v0.3.47 — 팝오버 카드 표시")
@MainActor
struct V0347AILimitCardVisibilityTests {
    private func seeded(_ providers: [AILimitProvider], defaults: UserDefaults) async -> AILimitStore {
        let spy = VVRunnerSpy(available: Set(providers))
        let store = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        for provider in AILimitProvider.allCases where !providers.contains(provider) {
            // 안 쓰는 제공자는 '미설치' = 숨기는 실패다(연동 안 된 상태의 실제 모양).
            spy.available.remove(provider)
        }
        await store.refreshIfDue(now: vvNow)
        return store
    }

    /// 끈 제공자는 줄이 사라지고, **전부 끄면 섹션 자체가 사라진다**(높이 0).
    ///
    /// 높이 산식(`AILimitRowWidthBudget.cardHeight(providers:)`)은 이미 0·1·2·3 을 받으므로 개수만 맞으면 된다 —
    /// 그래서 이 테스트는 **개수와 높이를 함께** 되묻는다(개수만 보면 카드가 빈 상자로 남아도 초록이다).
    @Test
    func turningProvidersOffShrinksTheCardAndFinallyRemovesIt() async {
        let store = await seeded([.claude, .codex, .antigravity], defaults: vvDefaults())
        #expect(store.listedProviders.count == 3)
        let full = AILimitRowWidthBudget.cardHeight(providers: store.listedProviders.count)
        #expect(full > 0)

        store.setProviderEnabled(.codex, false)
        #expect(store.listedProviders == [.claude, .antigravity])
        let twoRows = AILimitRowWidthBudget.cardHeight(providers: store.listedProviders.count)
        #expect(twoRows < full, "줄을 하나 껐는데 카드 높이가 그대로다")
        #expect(store.isAvailable)

        store.setMasterEnabled(false)
        #expect(store.isAvailable == false, "마스터를 껐는데 섹션이 남아 있다")
        #expect(store.listedProviders.isEmpty)
        #expect(store.visibleProviders.isEmpty)
        #expect(AILimitRowWidthBudget.cardHeight(providers: store.listedProviders.count) == 0)
        #expect(AILimitRowWidthBudget.budgetHeight(providers: store.listedProviders.count) == 0,
                "섹션이 사라졌는데 팝오버 예산이 VStack 간격을 먹는다")
        // 조합값(메뉴바 한 줄)도 같이 비어야 한다 — 여기만 안 걸러면 "다 껐는데 한 줄 요약에는 남아 있다"가 된다.
        #expect(store.summary(now: vvNow).percent == nil)
        #expect(CheckAILimitsCard.combinedWindows(store: store, now: vvNow).isEmpty)

        // 대조군: 다시 켜면 세 줄이 돌아온다(기준선이 달라야 위 단언들이 뜻을 갖는다).
        store.setMasterEnabled(true)
        #expect(store.listedProviders == [.claude, .antigravity], "마스터를 다시 켰을 때 내 제공자 선택이 사라졌다")
        store.setProviderEnabled(.codex, true)
        #expect(store.listedProviders.count == 3)
    }

    /// **꺼진 제공자의 실패 문구로 섹션을 살려 두지 않는다.** 만료·429 는 "숨기지 않는 실패"라
    /// `isAvailable` 을 참으로 만드는데, 안 읽는 제공자의 그 문구가 남으면 "다 껐는데 카드가 있다"가 된다.
    @Test
    func disabledProviderFailuresDoNotKeepTheSectionAlive() async {
        let store = AILimitStore(defaults: vvDefaults(), clock: { vvNow }, runner: { _, providers in
            var results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>] = [:]
            for provider in providers { results[provider] = .failure(AILimitReadError(.expired)) }
            return AILimitReadOutcome(results: results)
        })
        await store.refreshIfDue(now: vvNow)
        #expect(store.isAvailable, "전제: 만료만 있어도 섹션은 보인다")
        #expect(store.listedProviders.count == AILimitProvider.allCases.count)

        for provider in AILimitProvider.allCases { store.setProviderEnabled(provider, false) }
        #expect(store.isAvailable == false, "꺼진 제공자의 만료 문구가 섹션을 살려 뒀다")
        #expect(store.listedProviders.isEmpty)
        // 하지만 설정 화면에는 **그대로 줄이 선다** — 안 그러면 되켤 스위치가 사라진다.
        #expect(store.configurableProviders.count == AILimitProvider.allCases.count)
    }

    /// ★ 설정 화면의 목록은 **표시 설정을 보지 않는다** — 들어가면 못 나오는 방을 만들지 않는다.
    ///
    /// 없으면: `configurableProviders` 를 `listedProviders` 로 바꿔도 다른 테스트는 다 초록인데,
    /// 마스터를 끈 사람의 설정 화면에서 절이 통째로 사라져 **다시 켤 방법이 없어진다**.
    @Test
    func settingsListIgnoresTheVisibilitySettingItself() async {
        let store = await seeded([.claude, .codex], defaults: vvDefaults())
        #expect(store.configurableProviders == [.claude, .codex])

        store.setMasterEnabled(false)
        #expect(store.configurableProviders == [.claude, .codex],
                "마스터를 끄자 설정 목록이 비었다 — 그 사람은 리밋을 다시 켤 수 없다")
        store.setProviderEnabled(.claude, false)
        #expect(store.configurableProviders == [.claude, .codex],
                "제공자를 끄자 그 줄이 설정에서 사라졌다 — 되켤 스위치가 없어진다")

        // 그리고 그 줄들이 그리는 값은 `isProviderOn`(제공자 스위치 하나)이다 — 마스터를 끈 순간
        // 셋이 전부 꺼진 것처럼 보이면 다시 켤 때 내 선택이 사라진 것처럼 보인다.
        #expect(store.visibility.isProviderOn(.codex))
        #expect(store.visibility.isEnabled(.codex) == false)
    }
}

// MARK: - ④ 비우는 업로드

@Suite("v0.3.47 — 비우는 업로드(끈 제공자의 행)")
@MainActor
struct V0347AILimitClearingUploadTests {
    private func service(host: String) -> SupabaseWorkService {
        SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
    }

    private func store(host: String, defaults: UserDefaults, aiLimits: AILimitStore) -> WorkTimerStore {
        let store = WorkTimerStore(
            service: service(host: host),
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: defaults,
            workspaceNotifications: nil,
            aiLimits: aiLimits
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        // 기기 신원은 **지어내지 않고** 있는 것을 쓴다(관례: '기기 신원을 지어내지 마라').
        store.deviceID = "MAC-V0347"
        return store
    }

    private func aiLimitBodies(host: String) -> [[[String: Any]]] {
        URLProtocolStub.bodies(forHost: host).compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [[String: Any]]
        }
    }

    /// 본문들을 **나간 순서대로** 접어 서버에 남는 행을 만든다(PK 당 마지막 승 — upsert 의 뜻이 그것이다).
    ///
    /// ★ 이 접기가 정당한 까닭은 업로드가 **겹치지 않기** 때문이다(`uploadPeakConcurrency == 1`). 겹치면
    ///   나간 순서와 닿은 순서가 달라져 서버의 마지막 말이 사용자의 마지막 뜻과 어긋난다 — 그게 P1 이었다.
    private func aiLimitFinalRows(host: String) -> [String: [String: Any]] {
        var out: [String: [String: Any]] = [:]
        for body in aiLimitBodies(host: host) {
            for row in body {
                guard let provider = row["provider"] as? String else { continue }
                out[provider] = row
            }
        }
        return out
    }

    /// 세터가 띄운 Task 가 MainActor 에서 한 걸음 더 가게 둔다(가드에 막혀 트레일링을 세우는 자리까지).
    private func vvHandOff() async {
        for _ in 0..<8 { await Task.yield() }
    }

    /// 조건이 참이 될 때까지 **양보만** 한다(잠들지 않는다). 벽시계에 기대면 병렬 스위트의 MainActor 혼잡에서
    /// "비행 중"이라는 창(응답 지연 0.15초)을 놓쳐 테스트가 제 발에 걸린다 — 세터의 Task 도, 업로드가
    /// 본문을 굳히고 첫 `await` 로 떠나는 자리도 전부 MainActor 위라 양보만으로 충분하다.
    private func vvYieldUntil(_ condition: () -> Bool, limit: Int = 200) async {
        for _ in 0..<limit where !condition() { await Task.yield() }
    }

    /// ★ 끈 **그 순간** 그 제공자의 행이 창 값 전부 null 로 한 번 올라간다 — 그리고 **다시는** 올라가지 않는다.
    ///
    /// 세 가지를 한 테스트에서 재는 까닭: 셋이 같은 한 번의 사건("켬 → 끔")에 달려 있고,
    /// 따로 재면 "올라갔지만 키가 다르다" 같은 조합을 못 본다.
    @Test
    func disablingAProviderClearsItsRowOnceWithTheSameKeySet() async {
        let host = "v0347-clear-once"
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude, .codex])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: vvNow)
        await store.uploadAILimitsIfNeeded(now: vvNow)
        #expect(aiLimitBodies(host: host).count == 1, "전제: 값 업로드가 한 번 나갔다")
        #expect(aiLimitBodies(host: host)[0].count == 2)

        // 끈다. 업로드는 설정 세터가 띄우는 Task 가 아니라 여기서 **동기적으로** 태워 결정적으로 본다.
        limits.setProviderEnabled(.codex, false)
        store.lastUploadedAILimits = nil
        #expect(limits.pendingClear == [.codex])
        await store.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(60))

        let second = try! #require(aiLimitBodies(host: host).last)
        #expect(aiLimitBodies(host: host).count == 2)
        let codexRow = try! #require(second.first { $0["provider"] as? String == "codex" })
        for key in ["five_hour_percent", "five_hour_resets_at", "weekly_percent", "weekly_resets_at", "plan_label"] {
            #expect(codexRow[key] is NSNull, "비우는 행의 \(key) 가 null 이 아니다 — 폰이 그 제공자를 계속 보여 준다")
        }
        #expect(codexRow["observed_at"] as? String != nil, "observed_at 은 NOT NULL 이다(안 보내면 23502 로 조용히 거절된다)")
        #expect(codexRow["user_id"] as? String == "me")
        #expect(codexRow["device_id"] as? String == "MAC-V0347")
        // ★ 키 집합이 값 행과 **똑같다** — 다르면 PostgREST 가 400 PGRST102 로 본문 전체를 거절하고,
        //   그 거절은 조용해서 값도 비우기도 영원히 안 올라간다.
        let expected = Set(AILimitUpsertRow.CodingKeys.allCases.map(\.rawValue))
        for row in second { #expect(Set(row.keys) == expected) }
        #expect(URLProtocolStub.hasMismatchedObjectKeys(URLProtocolStub.bodies(forHost: host).last!) == false)
        // 켜 둔 제공자의 값 행은 **같은 본문에** 그대로 있다(비우기 때문에 값이 멈추지 않는다).
        let claudeRow = try! #require(second.first { $0["provider"] as? String == "claude" })
        #expect(claudeRow["five_hour_percent"] as? Double == 27)

        // ★ 한 번이면 된다 — 다음 주기는 같은 빈 행을 다시 올리지 않는다.
        #expect(limits.pendingClear.isEmpty, "비우기 성공이 대기열에서 빠지지 않았다")
        await store.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(120))
        #expect(aiLimitBodies(host: host).count == 2, "같은 빈 행을 매 주기 다시 올린다")
    }

    /// 마스터를 끄면 **연동된 모든 제공자**가 한 본문에서 비워진다. 올릴 값이 0 건인 바로 그 상태다 —
    /// "묶음이 비었으면 반환"이 비우기보다 앞에 있으면 전체 끄기가 서버에 영원히 닿지 못한다.
    @Test
    func masterOffClearsEveryLinkedProvider() async {
        let host = "v0347-clear-all"
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude, .codex, .antigravity])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: vvNow)
        await store.uploadAILimitsIfNeeded(now: vvNow)
        #expect(aiLimitBodies(host: host).count == 1)

        limits.setMasterEnabled(false)
        #expect(limits.pendingClear == Set(AILimitProvider.allCases))
        #expect(limits.enabledBundle.visibleProviders.isEmpty, "전제: 올릴 값이 하나도 없는 상태다")
        await store.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(60))

        let body = try! #require(aiLimitBodies(host: host).last)
        #expect(body.count == 3, "마스터를 껐는데 비운 행이 \(body.count)개다")
        #expect(Set(body.compactMap { $0["provider"] as? String }) == ["claude", "codex", "antigravity"])
        for row in body {
            #expect(row["five_hour_percent"] is NSNull)
            #expect(row["weekly_percent"] is NSNull)
        }
        #expect(limits.pendingClear.isEmpty)
    }

    /// 비우기 업로드가 **실패하면 다음 기회에 다시 시도한다** — 영구히 안 지워지는 조합이 있으면
    /// 그 사람의 폰은 끈 제공자를 계속 보여 준다.
    @Test
    func failedClearingIsRetriedLater() async {
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        // `schema-missing` 은 모든 /rest/v1 요청을 404 로 떨어뜨린다(앱이 db push 보다 먼저 나간 서버의 모양).
        let failing = store(host: "schema-missing", defaults: defaults, aiLimits: limits)
        defer { failing.session = nil }

        await limits.refreshIfDue(now: vvNow)
        limits.setProviderEnabled(.claude, false)
        #expect(limits.pendingClear == [.claude])
        await failing.uploadAILimitsIfNeeded(now: vvNow)
        #expect(limits.pendingClear == [.claude], "업로드가 실패했는데 비운 것으로 쳤다 — 그 행은 영원히 안 지워진다")

        // 서버가 돌아오면 같은 대기열이 그대로 올라간다.
        let host = "v0347-clear-retry"
        let healthy = store(host: host, defaults: defaults, aiLimits: limits)
        defer { healthy.session = nil }
        await healthy.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(60))
        let body = try! #require(aiLimitBodies(host: host).last)
        #expect(body.count == 1)
        #expect(body[0]["provider"] as? String == "claude")
        #expect(body[0]["weekly_percent"] is NSNull)
        #expect(limits.pendingClear.isEmpty)
    }

    /// ★ **같은 PK 를 한 본문에 두 번 담지 않는다.** 값 행과 비우는 행이 같은 제공자면 Postgres 가
    /// 21000("cannot affect row a second time")으로 **본문 전체**를 거절한다 — 값도 비우기도 못 올라간다.
    ///
    /// 두 겹으로 막는다: 설정이 다시 켜지는 순간 대기열에서 빠지고(아래 첫 단언), 혹시 섞여 들어와도
    /// 서비스가 접는다(둘째 단언 — 서비스를 직접 불러 섞인 입력을 준다).
    @Test
    func aProviderIsNeverBothClearedAndUploadedInOneBody() async {
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude, .codex])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        await limits.refreshIfDue(now: vvNow)

        limits.setProviderEnabled(.codex, false)
        #expect(limits.pendingClear == [.codex])
        limits.setProviderEnabled(.codex, true)
        #expect(limits.pendingClear.isEmpty, "다시 켠 제공자가 비우기 대기열에 남았다 — 켜 둔 제공자의 행이 비워진다")

        // 서비스 쪽 안전망: 값 행이 있는 제공자를 비우라고 해도 그 비우는 행은 **버려진다**.
        let host = "v0347-no-double-pk"
        let service = self.service(host: host)
        try! await service.upsertAILimits(
            accessToken: "t", userID: "me", deviceID: "MAC-V0347",
            bundle: AILimitSnapshotBundle(providers: [vvSnapshot(.claude), vvSnapshot(.codex)]),
            clearedProviders: [.codex, .codex, .antigravity],
            clearedAt: vvNow
        )
        let body = try! #require(aiLimitBodies(host: host).last)
        let providers = body.compactMap { $0["provider"] as? String }
        #expect(providers.count == Set(providers).count, "같은 제공자가 한 본문에 두 번 들어갔다: \(providers)")
        #expect(Set(providers) == ["claude", "codex", "antigravity"])
        // 값이 있는 codex 는 **값 행**으로 남았다(비우는 행이 값을 덮지 않았다).
        let codexRow = try! #require(body.first { $0["provider"] as? String == "codex" })
        #expect(codexRow["five_hour_percent"] as? Double == 27, "비우는 행이 값 행을 밀어냈다")
    }

    /// 설정이 바뀌면 **장부를 버린다.** 장부는 "값이 바뀌었나"만 재므로, 끈 뒤 같은 값으로 다시 켠 사람의
    /// 지문이 장부와 똑같을 수 있다(퍼센트·리셋·플랜 그대로 + 관측 칸도 같은 15분 안). 그러면 비우기만
    /// 올라간 채 값이 다시 안 올라가, 맥에는 숫자가 있는데 폰은 빈 채로 남는다.
    @Test
    func togglingInvalidatesTheUploadLedger() async {
        let host = "v0347-ledger-reset"
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: vvNow)
        await store.uploadAILimitsIfNeeded(now: vvNow)
        let ledger = store.lastUploadedAILimits
        #expect(ledger != nil)

        // ① 끈다 — **진짜 세터**로. 세터가 띄우는 업로드까지 이 경로의 일부다(30초 틱을 기다리지 않는다).
        store.setAILimitProviderEnabled(.claude, false)
        #expect(store.lastUploadedAILimits == nil, "설정을 바꿨는데 장부가 남았다 — 같은 값이면 다시 안 올라간다")
        await vvSettle(host: host, until: 2)
        let cleared = try! #require(aiLimitBodies(host: host).last)
        #expect(cleared.first { $0["provider"] as? String == "claude" }?["five_hour_percent"] is NSNull,
                "끈 그 순간 비우는 행이 올라가지 않았다")

        // ② 다시 켠다 — 값은 한 글자도 안 바뀌었다(러너를 다시 돌리지 않았다). 그래도 올라가야 한다.
        store.setAILimitProviderEnabled(.claude, true)
        #expect(limits.pendingClear.isEmpty)
        #expect(AILimitUploadLedger.fingerprint(limits.enabledBundle) == ledger,
                "전제: 지문이 그대로다 — 장부를 안 버리면 이 업로드가 걸러지고, 그게 이 테스트의 요점이다")
        await vvSettle(host: host, until: 3)
        let last = try! #require(aiLimitBodies(host: host).last)
        let claudeRow = try! #require(last.first { $0["provider"] as? String == "claude" })
        #expect(claudeRow["five_hour_percent"] as? Double == 27,
                "되켠 제공자의 값이 서버에 다시 올라가지 않았다 — 맥에는 숫자가 있는데 폰은 빈 채로 남는다")
        #expect(store.lastUploadedAILimits == ledger)
    }

    /// ★★ 업로드는 **한 번에 하나만** 난다 (2026-10-08 실증한 P1).
    ///
    /// 설정 세터는 토글마다 Task 를 띄우고, `WorkTimerStore` 가 MainActor 라도 `await service.upsertAILimits`
    /// 에서 액터가 풀려 가드가 없으면 **두 업로드가 동시에** 난다. 실측된 모습(스위치 둘을 연달아 끄는
    /// 평범한 사용):
    ///   `in-flight after A = 1  after B = 2` · 본문 A `antigravity=값` · 본문 B `antigravity=null`
    /// 같은 PK 가 두 본문에 **다른 뜻으로** 들어가고 도착 순서는 아무도 보장하지 않는다 — 값 본문이 나중에
    /// 닿으면 끈 제공자가 되살아나고, 그 사이 `markCleared` 둘이 대기열을 비워 **다시는 안 비운다.**
    ///
    /// 재는 것은 본문의 글자가 아니라 **겹침**이다: 직렬화해도 두 본문의 내용은 그대로일 수 있고(A 는 토글
    /// 전에 이미 굳었다), 달라지는 것은 그 둘의 **순서가 보장된다**는 사실뿐이다. 그래서 호스트 접두어
    /// `delayed-` 로 "비행 중"이라는 창을 실제로 열고, 그 창 안에서 두 번째 토글을 누른다.
    @Test
    func concurrentSettingTogglesNeverOverlapInFlight() async {
        let host = "delayed-v0347-serialize"
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude, .codex, .antigravity])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: vvNow)
        await store.uploadAILimitsIfNeeded(now: vvNow)
        #expect(aiLimitBodies(host: host).count == 1, "전제: 씨앗 값 업로드가 한 번 나갔다")
        #expect(limits.uploadInFlight == nil, "전제: 씨앗 업로드는 끝났다(핸들이 비워진다)")

        // ① 첫 토글 — **진짜 세터**로(Task 를 띄우는 그 경로가 결함의 자리다).
        store.setAILimitProviderEnabled(.codex, false)
        await vvYieldUntil { limits.uploadRoundTripCount == 2 }
        #expect(limits.uploadRoundTripCount == 2, "전제: 첫 토글의 업로드가 본문을 굳히고 왕복에 들어갔다")
        #expect(limits.uploadInFlight != nil, "전제: 첫 업로드가 아직 비행 중이다 — 아니면 아래 단언이 공허하다")

        // ② 비행 중에 둘째 토글. 여기가 실측된 레이스다.
        store.setAILimitProviderEnabled(.antigravity, false)
        await vvHandOff()
        #expect(limits.uploadPendingTrailing,
                "전제: 둘째 업로드가 비행 중인 첫 업로드와 만나 합쳐졌다 — 거짓이면 이 테스트는 레이스를 재현하지 못했다")

        await limits.uploadInFlight?.value
        #expect(limits.uploadPeakConcurrency == 1,
                "업로드가 동시에 \(limits.uploadPeakConcurrency)개 떴다 — 두 본문의 도착 순서는 아무도 보장하지 않는다")
        #expect(limits.uploadPendingTrailing == false, "트레일링이 소비되지 않았다")
        #expect(limits.uploadInFlight == nil, "핸들이 남았다 — 다음 업로드가 영원히 자기 가드에 막힌다")

        // 토글 둘이 본문 **둘**로 끝난다(씨앗 + 첫 업로드 + 합쳐진 트레일링). 합치지 않으면 여기가 늘어난다.
        #expect(aiLimitBodies(host: host).count == 3,
                "본문이 \(aiLimitBodies(host: host).count)개다 — 합치기가 요청을 하나로 접지 않았다")

        // 서버에 남는 것은 사용자의 **마지막 뜻**과 같다: 켠 것은 값, 끈 둘은 비워진 행.
        let final = aiLimitFinalRows(host: host)
        #expect(final["claude"]?["five_hour_percent"] as? Double == 27, "켜 둔 제공자의 값이 사라졌다")
        #expect(final["codex"]?["five_hour_percent"] is NSNull, "끈 codex 가 값 행으로 남았다")
        #expect(final["antigravity"]?["five_hour_percent"] is NSNull,
                "끈 antigravity 가 값 행으로 남았다 — 되살아났다")
        #expect(limits.pendingClear.isEmpty, "비우기가 대기열에 남았다")
    }

    /// ★ `markCleared` 는 **자기가 실제로 보낸 것만** 비운다 (P1 둘째 절반).
    ///
    /// 업로드는 `await` 를 건너므로 돌아왔을 때의 대기열은 떠날 때의 대기열이 아니다. 그 사이 사용자가
    /// 다시 켜고 **또 끈** 제공자의 끄기는 아직 아무도 보낸 적이 없다 — 그걸 비웠다고 표시하면 대기열이
    /// 비어 다음 주기도 재시도하지 않고, 그 제공자는 서버에서 영원히 안 비워진다.
    @Test
    func markClearedRetiresOnlyTheClearItActuallySent() async {
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude, .codex])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        await limits.refreshIfDue(now: vvNow)

        limits.setProviderEnabled(.codex, false)
        let claim = limits.claimPendingClear()
        #expect(claim.providers == [.codex], "전제: 보낸 것은 codex 하나다")

        // 보내는 사이에 사용자가 **다시 켜고 또 껐다**.
        limits.setProviderEnabled(.codex, true)
        limits.setProviderEnabled(.codex, false)
        limits.markCleared(claim)
        #expect(limits.pendingClear == [.codex],
                "보낸 적 없는 끄기를 비웠다고 표시했다 — 그 제공자는 서버에서 영원히 안 비워진다")

        // 대조군: 그 사이 아무 일도 없었으면 **비운다**(가드가 '아무것도 안 비운다'로 굳지 않았다).
        limits.markCleared(limits.claimPendingClear())
        #expect(limits.pendingClear.isEmpty, "같은 세대를 비우지 못했다 — 같은 빈 행을 매 주기 다시 올린다")
    }

    /// 비행 중에 되켰다 **다시 끈** 제공자도 서버에 닿는다 — 트레일링 업로드가 그 끄기를 가져간다.
    ///
    /// ★ 이 테스트가 무는 것은 **합치기(트레일링)** 다. `markCleared` 의 세대 규칙은 위 단위 테스트가 문다:
    ///   여기서는 첫 본문이 codex 를 이미 비운 상태라 세대를 무시해도 서버의 **마지막 말**은 같아지고,
    ///   그래서 이 e2e 하나만으로는 그 규칙을 지킬 수 없다(기준선이 갈리지 않는다).
    @Test
    func reTogglingDuringAnUploadStillReachesTheServer() async {
        let host = "delayed-v0347-regen"
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude, .codex])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: vvNow)
        await store.uploadAILimitsIfNeeded(now: vvNow)
        #expect(aiLimitBodies(host: host).count == 1)

        store.setAILimitProviderEnabled(.codex, false)
        await vvYieldUntil { limits.uploadRoundTripCount == 2 }
        #expect(limits.uploadInFlight != nil, "전제: 첫 업로드가 비행 중이다")
        // 비행 중에 되켜고 또 끈다 — 둘째 끄기는 첫 본문에 실리지 못했다.
        store.setAILimitProviderEnabled(.codex, true)
        store.setAILimitProviderEnabled(.codex, false)
        await vvHandOff()
        await limits.uploadInFlight?.value

        let last = try! #require(aiLimitBodies(host: host).last)
        let codexRow = try! #require(last.first { $0["provider"] as? String == "codex" },
                                     "비행 중에 다시 끈 제공자가 마지막 본문에 없다 — 그 끄기는 흔적도 없이 사라졌다")
        #expect(codexRow["five_hour_percent"] is NSNull)
        #expect(aiLimitFinalRows(host: host)["codex"]?["weekly_percent"] is NSNull)
        #expect(limits.pendingClear.isEmpty, "비우기가 대기열에 남았다")
    }

    /// ★★ 비우기가 **항구적으로** 실패하면 간격을 벌린다 — 30초마다 영원히 POST 하지 않는다 (P2).
    ///
    /// 그 상태의 사용자는 **마스터를 끈 사람**이고, 커밋·주석이 그에게 단정한 것은 "리밋 축이 통째로
    /// 잠든다 … 네트워크 0"이었다. 실패 조건은 주석이 스스로 예상한 경우다(스키마가 없는 서버 — 앱이
    /// `db push` 보다 먼저 나간 경우). 실측: 가드가 없으면 10틱에 POST 10건이고 대기열은 그대로다.
    ///
    /// **포기는 하지 않는다**: 대기열이 사라지면 그 행은 영영 안 지워져 폰·위젯이 끈 제공자를 계속 보여 준다.
    /// 느려지되 멈추지 않는다 — 그래서 하루 뒤에는 다시 노크한다.
    @Test
    func permanentlyFailingClearSlowsDownButNeverGivesUp() async {
        // `schema-missing` 접두어는 모든 `/rest/v1/*` 를 404 로 떨어뜨린다. 접두어로 **내 호스트**를 쓰는
        // 까닭은 요청 수를 세기 때문이다 — 공용 이름을 쓰면 병렬로 도는 다른 스위트의 POST 가 섞인다.
        let host = "schema-missing-v0347-backoff"
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: Set(AILimitProvider.allCases))
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: vvNow)
        limits.setMasterEnabled(false)
        #expect(limits.pendingClear == Set(AILimitProvider.allCases), "전제: 비울 행이 셋이다")
        #expect(limits.enabledBundle.visibleProviders.isEmpty, "전제: 올릴 값은 하나도 없다(마스터 끔)")

        // 30초 틱 열 번(= 5분). 가드가 없으면 열 번 다 POST 한다.
        for tick in 0..<10 {
            await store.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(Double(tick) * 30))
        }
        let posts = URLProtocolStub.requests(forHost: host).count
        #expect(posts == 3, "열 틱(5분)에 POST 가 \(posts)건이다 — 60초→두 배씩이면 0·60·180초에 세 번이다")
        #expect(limits.pendingClear == Set(AILimitProvider.allCases), "실패했는데 대기열을 비웠다")
        #expect(limits.uploadFailureStreak == 3)

        // ★ 영구 포기는 없다. 하루 뒤에는 다시 노크한다.
        await store.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(86_400))
        #expect(URLProtocolStub.requests(forHost: host).count == posts + 1,
                "하루가 지나도 다시 시도하지 않았다 — 그 행은 영영 안 지워진다")

        // 대조군: 서버가 돌아오면 **한 번에** 비워지고 그 뒤로는 조용하다(기능 자체는 옳다).
        let healthyHost = "v0347-backoff-recovered"
        let healthy = self.store(host: healthyHost, defaults: defaults, aiLimits: limits)
        defer { healthy.session = nil }
        await healthy.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(90_000))
        #expect(limits.pendingClear.isEmpty, "서버가 돌아왔는데 비우기가 안 올라갔다")
        #expect(limits.uploadFailureStreak == 0, "성공이 백오프를 풀지 않았다")
        for tick in 0..<11 {
            await healthy.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(90_030 + Double(tick) * 30))
        }
        #expect(URLProtocolStub.requests(forHost: healthyHost).count == 1,
                "비우기 성공 뒤에도 POST 가 이어졌다")
    }

    /// 백오프 산식 하나하나: 60초에서 두 배씩 · 상한 1시간 · 성공하면 즉시 풀린다.
    @Test
    func clearBackoffDoublesAndCapsAndResetsOnSuccess() {
        let limits = AILimitStore(defaults: vvDefaults(), clock: { vvNow }, runner: { _, _ in AILimitReadOutcome() })
        #expect(limits.uploadRetryAllowed(now: vvNow), "실패가 하나도 없는데 막았다")

        limits.noteUploadFailed(now: vvNow)
        #expect(limits.uploadRetryAllowed(now: vvNow.addingTimeInterval(59)) == false, "실패에 간격이 없다")
        #expect(limits.uploadRetryAllowed(now: vvNow.addingTimeInterval(60)))

        limits.noteUploadFailed(now: vvNow.addingTimeInterval(60))
        #expect(limits.uploadRetryAllowed(now: vvNow.addingTimeInterval(179)) == false, "둘째 실패에 간격이 안 벌어졌다")
        #expect(limits.uploadRetryAllowed(now: vvNow.addingTimeInterval(180)))

        // 상한. 서른 번 더 실패해도 한 시간을 넘지 않는다 — 상한이 없으면 60초 × 2^31 이고, 그건 영구 포기다.
        for _ in 0..<30 { limits.noteUploadFailed(now: vvNow) }
        #expect(limits.uploadFailureStreak == 32)
        #expect(limits.uploadRetryAllowed(now: vvNow.addingTimeInterval(3_599)) == false)
        #expect(limits.uploadRetryAllowed(now: vvNow.addingTimeInterval(3_600)),
                "간격이 상한을 넘었다 — 그만큼은 영구 포기와 구별되지 않는다")

        limits.noteUploadSucceeded()
        #expect(limits.uploadFailureStreak == 0)
        #expect(limits.uploadRetryAllowed(now: vvNow), "성공이 백오프를 풀지 않았다 — 다음 실패가 한 시간부터 시작한다")
        #expect(AILimitStore.uploadRetryBaseBackoff == 60)
        #expect(AILimitStore.uploadRetryMaxBackoff == 3_600)
    }

    /// ★★ **값** 업로드도 항구적 실패에서 간격을 벌린다 (2026-10-08 재검 — 같은 결함의 더 넓은 쪽).
    ///
    /// 초안의 게이트는 `if !valuesChanged, !uploadRetryAllowed` 라 **값이 바뀐 업로드를 비껴갔다.** 그 비껴감은
    /// "새 소식은 늘 나간다"는 뜻이었는데, 스키마 없는 서버에서는 장부(`lastUploadedAILimits`)가 **성공에만**
    /// 갱신되므로 `valuesChanged` 가 **영원히 참**이다. 그래서 마스터를 켜 둔 평범한 사용자 — 비울 것이 하나도
    /// 없어서 비우기 가드를 한 번도 만나지 않는 사람 — 는 **30초마다 영원히 POST** 했다.
    /// 실측: 가드가 값 쪽을 안 태우면 10틱에 POST 10건이고 장부는 끝까지 nil 이다.
    @Test
    func permanentlyFailingValueUploadAlsoSlowsDown() async {
        // 접두어로 **내 호스트**를 쓰는 까닭은 요청 수를 세기 때문이다 — 공용 이름을 쓰면 병렬로 도는 다른
        // 스위트의 POST 가 그 집계에 섞인다.
        let host = "schema-missing-v0347-value-backoff"
        let defaults = vvDefaults()
        let spy = VVRunnerSpy(available: [.claude])
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: spy.runner())
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: vvNow)
        #expect(limits.pendingClear.isEmpty, "전제: 비울 것이 하나도 없다 — 이 테스트는 값 쪽만 잰다")
        #expect(limits.enabledBundle.visibleProviders.count == 1, "전제: 올릴 값이 있다")

        // 30초 틱 열 번(= 5분). 가드가 값 쪽을 안 태우면 열 번 다 POST 한다.
        for tick in 0..<10 {
            await store.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(Double(tick) * 30))
        }
        let posts = URLProtocolStub.requests(forHost: host).count
        #expect(posts == 3, "열 틱(5분)에 POST 가 세 번이 아니다 — 60초→두 배씩이면 0·60·180초다")
        #expect(store.lastUploadedAILimits == nil,
                "실패했는데 장부를 갱신했다 — 그게 valuesChanged 를 영원히 참으로 만든 뿌리다")
        #expect(limits.uploadFailureStreak == 3)

        // ★ 영구 포기는 없다. 하루 뒤에는 다시 노크한다.
        await store.uploadAILimitsIfNeeded(now: vvNow.addingTimeInterval(86_400))
        #expect(URLProtocolStub.requests(forHost: host).count == posts + 1,
                "하루가 지나도 다시 시도하지 않았다 — 그 맥의 숫자는 영영 서버에 안 올라간다")

        // 대조군: 멀쩡한 서버에서는 **즉시** 나간다(게이트가 '늘 막는다'로 굳지 않았다).
        let okHost = "v0347-value-backoff-ok"
        let okDefaults = vvDefaults()
        let okLimits = AILimitStore(defaults: okDefaults, clock: { vvNow },
                                    runner: VVRunnerSpy(available: [.claude]).runner())
        let okStore = self.store(host: okHost, defaults: okDefaults, aiLimits: okLimits)
        defer { okStore.session = nil }
        await okLimits.refreshIfDue(now: vvNow)
        await okStore.uploadAILimitsIfNeeded(now: vvNow)
        #expect(URLProtocolStub.requests(forHost: okHost).count == 1, "멀쩡한 서버인데 값이 안 나갔다")
        #expect(okStore.lastUploadedAILimits != nil, "성공했는데 장부를 갱신하지 않았다")
    }

    /// ★ 본문을 만드는 함수를 부르는 자리는 **진입점 하나**다.
    ///
    /// 주석은 "직렬화를 건너뛰면 P1 이 그대로 돌아온다"고 단정하는데 그 불변식을 재는 계약이 없었다
    /// (단정만 있고 그물이 없는 자리다). `sendAILimitsUpload` 를 직접 부르는 둘째 집이 생기면 같은 PK 가
    /// 두 본문에 다른 뜻으로 들어가고 도착 순서는 아무도 보장하지 않는다 — 끈 제공자가 되살아나고,
    /// 그때 `markCleared` 가 대기열을 비워 **다시는 안 비운다.**
    @Test
    func theUploadBodyBuilderHasExactlyOneCaller() throws {
        let calls = try v0347CountInSources("sendAILimitsUpload(")
            - (try v0347CountInSources("func sendAILimitsUpload("))
        #expect(calls == 1, "sendAILimitsUpload 를 부르는 곳이 한 군데가 아니다 — 직렬화를 건너뛰는 집이 생겼다")
        // 직렬화 가드가 그 진입점에 **실제로** 있다(부르는 곳을 세는 것만으로는 가드가 지워진 것을 못 본다).
        let source = v0347Stripped(try CheckCoreSourceLayout.joinedSplitSource("WorkTimerStoreAILimits.swift"))
        #expect(source.contains("guard aiLimits.uploadInFlight == nil else"),
                "비행 중 가드가 사라졌다 — 토글 둘이 업로드 둘을 동시에 띄운다")
        #expect(source.contains("aiLimits.uploadPendingTrailing = true"),
                "합치기가 사라졌다 — 줄 세우지 않으면 요청이 토글 수만큼 난다")
    }

    /// ★★ 트레일링 업로드는 **그 시점의 `now`** 로 돈다 (2026-10-08 재검).
    ///
    /// 초안의 루프는 첫 호출의 `now` 를 둘째 바퀴에도 넘겼다. 그 값은 이미 과거다 — 첫 바퀴가 왕복을 돌고 온
    /// 뒤니까. 백오프 창이 그 사이에 끝났는데도 트레일링이 옛 시각으로 판정하면 게이트가 닫혀 **소비된 채
    /// 아무것도 보내지 않는다.** 다음 30초 틱이 구해 주지만 "끈 즉시 폰에서 사라진다"가 그만큼 늦는다.
    ///
    /// 재현에 쓰는 호스트가 `delayed-…-expired-token` 인 까닭: 지연(비행 창)은 **접두어**로, 실패(401)는
    /// **접미어 + 낡은 토큰**으로 붙는다 — 둘을 겹칠 수 있는 유일한 조합이다(URLProtocolStub 주석).
    /// `schema-missing` 은 접두어라 `delayed-` 와 겹칠 수 없다.
    @Test
    func theTrailingUploadRunsWithAFreshNow() async {
        let host = "delayed-v0347-trailing-expired-token"
        let defaults = vvDefaults()
        let clock = VVClock(vvNow)
        let spy = VVRunnerSpy(available: [.claude])
        let limits = AILimitStore(defaults: defaults, clock: { clock.now }, runner: spy.runner())
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        // 이 토큰이어야 스텁이 401 을 준다(만료 재현 규약).
        store.session = SupabaseSession(accessToken: "old-access-token", refreshToken: nil, userID: "me")
        defer { store.session = nil }

        await limits.refreshIfDue(now: vvNow)
        // 껐다 → 비우기 대기열에 claude 하나, 올릴 값은 0 건. 그래서 둘째 바퀴는 백오프 게이트를 지난다.
        limits.setProviderEnabled(.claude, false)
        #expect(limits.pendingClear == [.claude], "전제: 비울 것이 하나 있다")
        #expect(limits.enabledBundle.visibleProviders.isEmpty, "전제: 올릴 값은 없다(값은 게이트를 비껴가지 않는다)")

        // ① 첫 바퀴는 실제로 POST 하고(백오프 없음) 401 로 실패해 60초 창을 세운다.
        let first = Task { @MainActor in await store.uploadAILimitsIfNeeded(now: vvNow) }
        await vvYieldUntil { limits.uploadRoundTripCount == 1 }
        #expect(limits.uploadRoundTripCount == 1, "전제: 첫 업로드가 본문을 굳히고 왕복에 들어갔다")
        #expect(limits.uploadInFlight != nil, "전제: 첫 업로드가 아직 비행 중이다 — 아니면 트레일링이 안 선다")

        // ② 비행 중에 둘째 요청 → 트레일링 한 번으로 합쳐진다.
        await store.uploadAILimitsIfNeeded(now: vvNow)
        #expect(limits.uploadPendingTrailing, "전제: 트레일링이 섰다 — 거짓이면 이 테스트는 아무것도 재지 못한다")

        // ③ 그 사이에 시계가 백오프 창(60초)을 지나간다. 트레일링이 **옛 now** 로 돌면 여기서 막힌다.
        clock.advance(120)
        await first.value

        #expect(URLProtocolStub.requests(forHost: host).count == 2,
                "트레일링이 소비된 채 아무것도 안 보냈다 — 끈 제공자가 폰에서 사라지는 일이 30초 늦는다")
        #expect(limits.pendingClear == [.claude], "실패했으니 대기열은 그대로다(다음 기회에 재시도한다)")
        #expect(limits.uploadPendingTrailing == false, "트레일링이 소비되지 않았다")
        #expect(limits.uploadInFlight == nil, "핸들이 남았다 — 다음 업로드가 영원히 자기 가드에 막힌다")
    }

    /// 세터가 띄운 업로드가 끝날 때까지 기다린다.
    ///
    /// `Task.yield()` 로는 모자란다(실측: 여덟 번 양보해도 0건) — 세터는 `Task` 로 띄우고 그 안에서
    /// URLSession 왕복을 하므로 결과를 **폴링**한다(`inertStoreLeavesNoPlistInLibraryPreferences` 가
    /// cfprefsd flush 를 기다리는 것과 같은 관용구). 못 오면 다음 단언이 그 사실을 말한다.
    private func vvSettle(host: String, until count: Int) async {
        for _ in 0..<100 where aiLimitBodies(host: host).count < count {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// 올릴 값도 없고 비울 것도 없으면 **요청을 아예 보내지 않는다**(끈 사람의 맥은 조용하다).
    @Test
    func nothingToSayMeansNoRequest() async {
        let host = "v0347-silent"
        let defaults = vvDefaults()
        let limits = AILimitStore(defaults: defaults, clock: { vvNow }, runner: { _, _ in AILimitReadOutcome() })
        limits.setMasterEnabled(false)
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }
        #expect(limits.pendingClear.isEmpty, "전제: 연동된 적이 없으니 비울 것도 없다")
        await store.uploadAILimitsIfNeeded(now: vvNow)
        #expect(URLProtocolStub.requests(forHost: host).isEmpty, "할 말이 없는데 요청을 보냈다")
    }
}

// MARK: - ⑤ 설정 화면 배선

@Suite("v0.3.47 — 설정 화면")
@MainActor
struct V0347AILimitSettingsViewTests {
    /// 설정 창에 절이 있고, 스위치가 **스토어 세터 한 쌍**으로만 간다.
    ///
    /// 왜 글자로 재는가: 바인딩이 `store.aiLimits` 를 직접 만지면 "끈 순간 서버 행을 비운다"가 설정 화면을
    /// 거친 변경에만 빠지고, 그 누락은 조용하다(화면은 멀쩡하고 폰만 안 바뀐다).
    @Test
    func settingsWindowOffersTheSwitchesAndRoutesThroughTheStore() throws {
        let source = v0347Stripped(try CheckCoreSourceLayout.joinedSplitSource("CheckSettingsView.swift"))
        let title = try #require(source.range(of: "title: \"AI 사용량 리밋 보기\""), "설정 창에 마스터 스위치가 없다")
        let row = source[title.upperBound...].prefix(400)
        #expect(row.contains("isOn: masterBinding"))
        #expect(source.contains("section(\"AI 리밋\")"), "절 제목이 없다")
        #expect(source.contains("get: { store.aiLimits.visibility.masterEnabled }"))
        #expect(source.contains("set: { store.setAILimitsVisible($0) }"))
        #expect(source.contains("get: { store.aiLimits.visibility.isProviderOn(provider) }"),
                "하위 줄이 `isEnabled` 를 그린다 — 마스터를 끈 순간 내 제공자 선택이 사라진 것처럼 보인다")
        #expect(source.contains("set: { store.setAILimitProviderEnabled(provider, $0) }"))

        // 연동 안 된 제공자는 줄을 세우지 않는다(자동 감지 규약) — 그리고 절 자체가 그 목록에 달려 있다.
        #expect(source.contains("store.aiLimits.configurableProviders"), "연동 목록이 아니라 다른 목록으로 줄을 세운다")
        #expect(source.contains("if !store.aiLimits.configurableProviders.isEmpty"),
                "연동된 도구가 없는 사람에게도 절이 보인다 — 끌 것이 없는 스위치다")

        // 마스터 off 일 때 하위 줄은 **흐려진다**(사라지지 않는다 — 근거는 뷰 주석).
        #expect(source.contains(".disabled(!store.aiLimits.visibility.masterEnabled)"))
        #expect(source.contains(".opacity(store.aiLimits.visibility.masterEnabled ? 1 : 0.4)"))

        // 세터를 부르는 곳은 설정 화면 하나뿐이다. 두 번째 집이 생기면 두 스위치가 서로 다른 값을 그린다.
        for setter in ["setAILimitsVisible(", "setAILimitProviderEnabled("] {
            let calls = try v0347CountInSources(setter) - (try v0347CountInSources("func \(setter)"))
            #expect(calls == 1, "\(setter) 를 부르는 곳이 \(calls)군데다")
        }
    }

    /// ★ '폰·위젯에 보여줄 맥' 고르개가 설정 창에 있고, **스토어 함수 하나로만** 간다.
    ///
    /// 글자로 재는 까닭은 위 스위치들과 같다: 여기서 `aiLimits` 를 직접 만지면 서버에 쓰는 일이 빠지고
    /// 그 누락은 조용하다(설정 창만 바뀌고 폰·위젯은 옛 맥을 계속 그린다).
    @Test
    func settingsWindowOffersTheMainMacPickerAndRoutesThroughTheStore() throws {
        let source = v0347Stripped(try CheckCoreSourceLayout.joinedSplitSource("CheckSettingsView.swift"))
        #expect(source.contains("Text(\"폰·위젯에 보여줄 맥\")"), "고르개 줄의 제목이 없다")
        #expect(source.contains("if store.aiLimits.showsMainDevicePicker {"),
                "맥이 한 대인 사람에게도 고르개가 보인다 — 고를 것이 없는 고르개는 권한에 대한 거짓말이다")
        #expect(source.contains("await store.loadAILimitDevicesIfNeeded()"),
                "기기 목록을 받아 오는 자리가 없다 — 고르개가 영영 안 나타난다")
        #expect(source.contains("await store.setAILimitMainDevice(device.deviceID)"),
                "줄이 스토어 함수로 가지 않는다 — 서버에 안 써서 폰이 안 바뀐다")
        // ★ 이름은 **조각으로** 받는다(v0.3.47 P2). 합친 글자 하나를 받아 그리면 좁은 줄에서 말줄임이
        //   **꼬리부터** 먹어 같은 이름 두 맥이 글자 그대로 똑같아진다 — 고르개가 가를 수 없는 화면이 된다.
        #expect(source.contains("AILimitDeviceRoster.displayNameParts(store.aiLimits.devices)"),
                "이름을 뷰가 직접 만들거나 합친 글자로 받는다 — 겹치는 이름을 가르는 꼬리가 잘릴 자리에 놓인다")

        // 세터를 부르는 곳은 설정 화면 하나뿐이다(위 두 스위치와 같은 규약).
        let calls = try v0347CountInSources("setAILimitMainDevice(")
            - (try v0347CountInSources("func setAILimitMainDevice("))
        #expect(calls == 1, "setAILimitMainDevice 를 부르는 곳이 한 군데가 아니다")

        // ★ 그 줄은 `Menu`·`Picker`·`TextField` 가 아니다. 이 저장소의 렌더 검증(`ImageRenderer`)은 그 셋을
        //   **노란 상자**로 그려 그 자리의 픽셀 커버리지가 0 이 된다 — 잘림·겹침·색 결함을 스냅샷이 영영 못 본다.
        let start = try #require(source.range(of: "struct AILimitMainDeviceSettingsRow"))
        let row = source[start.lowerBound...].prefix(3_200)
        for banned in ["Menu {", "Picker(", "TextField("] {
            #expect(row.contains(banned) == false, "고르개가 렌더 검증에서 노란 상자로 그려지는 조각을 쓴다")
        }
        #expect(row.contains("RoundedRectangle(cornerRadius: 8, style: .continuous)"),
                "줄 배경이 순수 도형이 아니다 — 렌더 검증이 그 자리를 못 본다")
        #expect(row.contains("CheckTheme.gaugeGradient") && row.contains("CheckTheme.trackFill"),
                "고른 줄/나머지 줄의 색 문법이 캐릭터 행과 갈렸다")

        // ★★ 칩 한 줄이 아니라 **목록**이다(v0.3.47 P2). 칩을 한 `HStack` 에 밀어 넣으면 기기 수가 늘수록
        //   칩마다의 폭이 줄어, 4대에서 같은 이름 두 맥이 둘 다 `Mac min…` 으로 떠 **고를 수가 없다**.
        #expect(row.contains("VStack(alignment: .leading, spacing: AILimitDevicePickerBudget.rowGap)"),
                "고르개가 세로 목록이 아니다 — 기기 수에 따라 이름 자리가 줄어드는 배치로 돌아갔다")
        #expect(!row.contains("frame(maxWidth: 160)"),
                "칩 폭 상한이 남았다 — 한 줄에 여럿을 밀어 넣던 그 배치다")
        // 꼬리는 **자르지 않는 자리**에 있다(이름만 잘린다).
        #expect(row.contains("Text(AILimitDeviceNameParts.tailText(tail))"), "꼬리를 따로 세우지 않는다")
        let tail = try #require(row.range(of: "Text(AILimitDeviceNameParts.tailText(tail))"))
        let tailBlock = row[tail.upperBound...].prefix(200)
        #expect(tailBlock.contains(".fixedSize()") && tailBlock.contains(".layoutPriority(1)"),
                "꼬리가 줄어들거나 나중에 자리를 받는다 — 긴 이름 앞에서 `…` 가 되어 두 줄이 똑같아진다")
    }

    /// ★★ 맥이 **두 대일 때만** 그 줄이 실제로 **그려진다**(높이와 잉크가 같이 늘어난다).
    ///
    /// 짝이 필요한 까닭: "두 대면 보인다"만 재면 줄을 통째로 지워도 "한 대면 안 보인다"는 영원히 초록이다
    /// (기준선이 같은 입력이면 그 테스트는 영원히 초록이다). 그리고 높이만 보면 `ScrollView` 안이 비었을 때처럼
    /// **자리는 생겼는데 아무것도 안 그려진** 상태를 통과시킨다(2026-10-07 실증) — 그래서 잉크도 같이 센다.
    @Test
    func theMainMacPickerDrawsOnlyWithTwoMacs() async throws {
        let suite = CheckTestScratch.defaults("v0347-main-mac-render")
        let devices = [
            AILimitDevice(deviceID: "MAC-A", label: "Mac mini", lastObservedAt: vvNow.addingTimeInterval(-600)),
            AILimitDevice(deviceID: "MAC-B", label: "사무실 iMac", lastObservedAt: vvNow)
        ]

        let one = AILimitStore(defaults: vvDefaults(), clock: { vvNow },
                              runner: VVRunnerSpy(available: [.claude]).runner())
        await one.refreshIfDue(now: vvNow)
        one.applyDevices([devices[0]], mainDeviceID: nil, now: vvNow)
        #expect(one.showsMainDevicePicker == false, "전제: 맥 한 대면 고르개가 숨는다")
        let oneHeight = try v0347SettingsHeight(aiLimits: one, characterDefaults: suite)
        let oneInk = try v0347SettingsInk(aiLimits: one, characterDefaults: suite)

        let two = AILimitStore(defaults: vvDefaults(), clock: { vvNow },
                              runner: VVRunnerSpy(available: [.claude]).runner())
        await two.refreshIfDue(now: vvNow)
        two.applyDevices(devices, mainDeviceID: "MAC-B", now: vvNow)
        #expect(two.showsMainDevicePicker, "전제: 맥 두 대면 고르개가 선다")
        let twoHeight = try v0347SettingsHeight(aiLimits: two, characterDefaults: suite)
        let twoInk = try v0347SettingsInk(aiLimits: two, characterDefaults: suite)

        #expect(twoHeight > oneHeight, "맥이 두 대인데 고르개 줄이 그려지지 않았다")
        #expect(twoInk > oneInk, "높이는 늘었는데 잉크가 안 늘었다 — 자리만 생기고 아무것도 안 그려졌다")
    }

    /// ★ **연동된 도구가 없는 사람의 설정 창은 한 픽셀도 안 달라진다.**
    ///
    /// 이 창은 스크롤이 없고 높이 계약이 폭 하한에서 잰 **한 값**으로 서 있다
    /// (`CheckSettingsWindowController.defaultContentSize` · 여유 5pt 규약). 자동 감지로 절을 숨기는 덕분에
    /// 리밋을 안 쓰는 사람에게는 그 계약이 그대로다 — 그 사실을 여기서 못 박는다(다른 스위트의 높이
    /// 단언들이 이 전제 위에 서 있다).
    @Test
    func unlinkedMacKeepsTheSettingsWindowHeightUnchanged() throws {
        let suite = CheckTestScratch.defaults("v0347-height")
        let plain = try v0347SettingsHeight(aiLimits: nil, characterDefaults: suite)
        #expect(plain + AvatarRemovalSettingsRow.maxExtraHeight
                <= CheckSettingsWindowController.defaultContentSize.height,
                "연동 없는 설정 \(plain)pt + 여유 13 이 창 \(CheckSettingsWindowController.defaultContentSize.height)pt 를 넘는다")
        #expect(CheckSettingsWindowController.defaultContentSize.height
                - (plain + AvatarRemovalSettingsRow.maxExtraHeight) == 5,
                "창 여유가 5pt 가 아니다 — AI 리밋 절이 연동 없는 맥에도 그려졌다는 뜻이다")
    }

    /// 연동된 제공자가 있으면 절이 **실제로 그려진다**(그리고 제공자 수만큼 자란다).
    ///
    /// 위 테스트와 짝이다: 이 단언이 없으면 절을 통째로 지워도 위 테스트는 초록이다
    /// (기준선이 같은 입력이면 그 테스트는 영원히 초록이다).
    ///
    /// ★ 그리고 여기서 **스크롤이 필요한 이유가 숫자로** 선다: 연동된 맥의 본문은 창(884pt)보다 높다.
    ///   예전의 이 창은 넘치는 만큼을 **잘랐고**(스크롤이 없었다), 그 잘림은 조용하다 — 사용자는 그 행이
    ///   있는 줄도 모른다. 창 상수를 올려서 풀 수도 없다: 13" 맥북에어의 콘텐츠 상한이 ~903pt 다.
    @Test
    func linkedMacNeedsAScrollingBody() async throws {
        let suite = CheckTestScratch.defaults("v0347-height-linked")
        let plain = try v0347SettingsHeight(aiLimits: nil, characterDefaults: suite)

        let spy = VVRunnerSpy(available: [.claude])
        let one = AILimitStore(defaults: vvDefaults(), clock: { vvNow }, runner: spy.runner())
        await one.refreshIfDue(now: vvNow)
        #expect(one.configurableProviders == [.claude])
        let withOne = try v0347SettingsHeight(aiLimits: one, characterDefaults: suite)
        #expect(withOne > plain, "연동이 있는데 절이 안 그려졌다(\(withOne)pt = \(plain)pt)")

        let spyThree = VVRunnerSpy(available: Set(AILimitProvider.allCases))
        let three = AILimitStore(defaults: vvDefaults(), clock: { vvNow }, runner: spyThree.runner())
        await three.refreshIfDue(now: vvNow)
        let withThree = try v0347SettingsHeight(aiLimits: three, characterDefaults: suite)
        #expect(withThree > withOne, "제공자가 셋인데 줄이 하나일 때와 높이가 같다")

        // 전제: 넘친다. 이 숫자가 창 안으로 들어오는 날이 오면 아래 ScrollView 요구는 과잉이 되므로
        // 그때 이 단언이 먼저 빨개져 알려 준다(근거가 사라진 장치를 남겨 두지 않는다).
        let window = CheckSettingsWindowController.defaultContentSize.height
        #expect(withOne > window,
                "연동 하나짜리 본문(\(withOne)pt)이 창(\(window)pt) 안에 든다 — 스크롤 근거를 다시 재라")

        // 그래서 본문은 **들어가면 맨몸, 넘치면 ScrollView** 다(`ViewThatFits`). 지우면 그 넘치는 만큼이
        // 조용히 잘린다 — 사용자는 그 행이 있는 줄도 모른다.
        let source = v0347Stripped(try CheckCoreSourceLayout.joinedSplitSource("CheckSettingsView.swift"))
        let fits = try #require(source.range(of: "ViewThatFits(in: .vertical)"),
                                "설정 본문의 ViewThatFits 가 사라졌다 — 넘치는 \(Int(withThree - window))pt 가 잘린다")
        let branches = source[fits.upperBound...].prefix(240)
        // 첫 가지가 **맨몸 본문**이어야 한다. 순서가 뒤집히면 ScrollView 가 늘 뽑혀,
        // `ImageRenderer` 가 그 안을 안 그리는 탓에 이 창의 그림 검증 셋이 통째로 무음으로 깨진다(실측 3건).
        let plainBranch = try #require(branches.range(of: "settingsSections"))
        let scrollBranch = try #require(branches.range(of: "ScrollView(.vertical)"),
                                        "넘칠 때의 대안(ScrollView)이 없다 — ViewThatFits 가 고를 것이 하나뿐이다")
        #expect(plainBranch.lowerBound < scrollBranch.lowerBound,
                "ScrollView 가 첫 가지다 — 들어가는 사람에게도 스크롤이 붙고 렌더 검증이 빈 그림을 본다")
        // 콘텐츠가 들어가는 창에서는 튕김조차 없어야 한다.
        #expect(branches.contains(".scrollBounceBehavior(.basedOnSize)"))
        // [차단한 사람] 쪽은 자기 목록을 스스로 스크롤한다 — 중첩 금지.
        #expect(source.components(separatedBy: "ScrollView(.vertical)").count - 1 == 1,
                "설정 뷰에 ScrollView 가 둘이다 — 중첩 스크롤은 휠이 어느 쪽을 움직일지 사용자가 못 고른다")

        // ★ 그리고 **들어가는 경우의 그림이 변하지 않았다**: 제약 없이 그리면 맨몸 가지가 뽑혀 예전과 같은
        //   높이가 나온다(위 `plain == 866` 과 아래 창 여유 5pt 규약이 그 사실이다). ScrollView 를 그냥 감쌌을 때
        //   이 숫자는 맞는데 픽셀이 비었다 — 그래서 높이만으로는 부족하고, 잉크가 있는지도 본다.
        let ink = try v0347SettingsInk(aiLimits: nil, characterDefaults: suite)
        #expect(ink > 10_000, "맨몸 가지가 안 뽑혔다 — 설정 창이 \(ink) 픽셀만 칠하고 비었다")

        // ★ **창 높이에서 어느 가지가 뽑혔는지는 그림으로 가를 수 없다**(2026-10-07 실증).
        //   `ImageRenderer` 는 높이가 **확정**되면 ScrollView 안을 그린다 — 그러면 스크롤된 화면(맨 위부터)과
        //   잘린 화면(맨 위부터)이 픽셀로 같다(실측: 잉크 1,342,217 대 1,315,139). 그래서 그 자리는 위의
        //   소스 계약(가지 둘 · 순서)으로 지키고, 여기서는 **들어가는 경우**만 그림으로 지킨다.
        //   ScrollView 를 `fixedSize` 아래에 두면(= 가지 순서를 뒤집으면) 바로 위 단언이 빈 그림을 보고 빨개진다.
    }
}

// MARK: - 도우미

private enum V0347Error: Error { case renderFailed }

/// 설정 화면을 창 폭 하한에서 **가장 높은 상태**(단축키 안내 한 줄 켬)로 그려 높이를 잰다 —
/// V0316·V0336·V0340 과 같은 규약이다.
@MainActor
private func v0347SettingsHeight(
    aiLimits: AILimitStore?,
    characterDefaults: UserDefaults,
    function: String = #function,
    line: Int = #line
) throws -> CGFloat {
    CGFloat(try v0347SettingsBitmap(
        aiLimits: aiLimits, characterDefaults: characterDefaults,
        function: function, line: line).pixelsHigh) / 2
}

@MainActor
private func v0347SettingsBitmap(
    aiLimits: AILimitStore?,
    characterDefaults: UserDefaults,
    function: String = #function,
    line: Int = #line
) throws -> NSBitmapImageRep {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: CheckTestScratch.defaults("v0347-settings-L\(line)", function: function),
        workspaceNotifications: nil,
        aiLimits: aiLimits
    )
    store.myCenterLoaded = true
    store.myCenter = CenterLabel.seoul
    store.workShortcutStatus = .conflict
    let renderer = ImageRenderer(
        content: CheckSettingsView(store: store, launchAtLoginSeed: false, characterDefaults: characterDefaults)
            .frame(width: CheckSettingsView.preferredWidth)
            .fixedSize(horizontal: false, vertical: true)
    )
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw V0347Error.renderFailed }
    return bitmap
}

/// 설정 화면을 그려 **배경색이 아닌 픽셀 수**를 센다(= 실제로 그려진 잉크).
///
/// 왜 높이만으로는 부족한가(2026-10-07 실증): 본문을 `ScrollView` 로 그냥 감쌌을 때 높이는 예전과
/// 똑같이 866pt 로 나왔는데 **안이 비어 있었다** — `ImageRenderer` 가 ScrollView 내용을 그리지 않는다.
/// 높이만 보는 단언은 그 상태를 통과시킨다.
@MainActor
private func v0347SettingsInk(
    aiLimits: AILimitStore?,
    characterDefaults: UserDefaults,
    function: String = #function,
    line: Int = #line
) throws -> Int {
    let bitmap = try v0347SettingsBitmap(
        aiLimits: aiLimits, characterDefaults: characterDefaults, function: function, line: line)
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    // 기준점은 왼쪽 위 한 픽셀(= 창 배경). 그 색과 다른 픽셀을 전부 센다 — 특정 색을 적어 두면
    // 테마가 바뀌는 날 단언이 조용히 공허해진다.
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let background = (data[0], data[1], data[2])
    var ink = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let offset = y * bpr + x * spp
            if (data[offset], data[offset + 1], data[offset + 2]) != background { ink += 1 }
        }
    }
    return ink
}

/// Sources/check(+CheckCore) 의 모든 .swift 에서 주석을 걷어낸 뒤 needle 이 나오는 횟수.
private func v0347CountInSources(_ needle: String) throws -> Int {
    let directory = CheckCoreSourceLayout.macDirectory
    let names = try FileManager.default
        .checkSourcesContentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".swift") }
    return try names.reduce(0) { total, name in
        let code = v0347Stripped(try String(contentsOf: directory.appendingCheckSourcePath(name), encoding: .utf8))
        return total + code.components(separatedBy: needle).count - 1
    }
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸 코드. 걷어내지 않으면 **설명문의 낱말이 단언에 걸린다** —
/// 그러면 주석을 지워야만 초록이 되는 테스트가 된다(이 저장소가 겪은 그 함정).
private func v0347Stripped(_ source: String) -> String {
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
                    rest = rest[rest.endIndex...]
                }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockOpen = rest.range(of: "/*")
            if let lineComment, blockOpen == nil || lineComment.lowerBound < blockOpen!.lowerBound {
                kept += rest[..<lineComment.lowerBound]
                rest = rest[rest.endIndex...]
            } else if let blockOpen {
                kept += rest[..<blockOpen.lowerBound]
                rest = rest[blockOpen.upperBound...]
                inBlock = true
            } else {
                kept += rest
                rest = rest[rest.endIndex...]
            }
        }
        output += kept + "\n"
    }
    return output
}
