import Foundation
import Testing
@testable import check

// MARK: - O1: 콕찌르기 폴링을 근무 중으로 제한
//
// 서버가 poke 생성 시점에 대상의 열린 세션을 요구하므로(20260724030000_poke_target_working.sql — target_not_working)
// 비근무 구간의 take_pokes 응답은 원리상 확정적으로 빈 배열이다. 그런데 게이트가 `session != nil` 하나뿐이던 시절엔
// 로그인만 해 둔 맥이 24시간 15초마다(하루 3,840~5,760회) 그 빈 배열을 받으러 나갔다.
// 여기 테스트들이 고정하는 것은 두 가지다: ① 비근무면 take_pokes 가 나가지 않는다 ② 그럼에도 공개 설정 로드는
// 게이트 **앞**이라 근무 이력이 없는 사용자도 서버값을 읽는다. ②가 깨지면 가드를 한 줄 위로 잘못 옮긴 것이다.
//
// 폴링 주기(15초)는 static let 이라 테스트에서 줄일 수 없다. 전역 var 로 여는 대신 루프 본문을 pokePollTick() 으로
// 분리해 직접 호출한다 — 전역 가변값은 병렬 스위트끼리 서로 덮어써 레이스를 무음으로 지운다
// (URLProtocolStub.delayedHosts 주석의 그 사고).

@MainActor
@Test
func pokePollTickSkipsTakePokesWhenNotWorking() async {
    let testHost = "poke-gate-idle"
    let store = makePokeGateStore(host: testHost)

    // 로그인만 되어 있고 근무는 시작하지 않은 상태 — 예전 게이트(session != nil)라면 여기서 요청이 나갔다.
    #expect(store.startedAt == nil)
    await store.pokePollTick()

    #expect(takePokesRequestCount(host: testHost) == 0)
}

@MainActor
@Test
func pokePollTickTakesPokesWhileWorking() async {
    let testHost = "poke-gate-working"
    let store = makePokeGateStore(host: testHost)

    // 게이트 기준은 snapshot.isWorking 이 아니라 startedAt 이다(sendPoke 선게이트·서버 '열린 세션'과 같은 눈금).
    store.startedAt = Date()
    store.currentSessionID = "poke-gate-session"
    await store.pokePollTick()

    // 근무중이면 tick 당 정확히 1건. 2건이면 withSessionRetry 가 헛돌고 있다는 뜻이다.
    #expect(takePokesRequestCount(host: testHost) == 1)
}

@MainActor
@Test
func pokePollTickLoadsTokenPrivacyEvenWhenNotWorking() async {
    let testHost = "poke-gate-privacy"
    let store = makePokeGateStore(host: testHost)

    // 근무 이력이 없는 사용자(로그인 직후, 아직 시작을 안 누름).
    #expect(store.startedAt == nil)
    await store.pokePollTick()

    // 가드 배치의 증거: 근무중 가드를 loadTokenUsagePrivacyIfNeeded **앞**으로 옮기면 이 단언이 0이 되어 깨진다.
    // 그 배치에선 이 사용자가 자기 token_usage_public 서버값을 영영 못 읽어, 비공개로 꺼 둔 설정이
    // 실행할 때마다 낙관 기본값 true 로 되살아난다.
    #expect(tokenPrivacyRequestCount(host: testHost) == 1)
    #expect(takePokesRequestCount(host: testHost) == 0)
}

@MainActor
@Test
func flushPokesOnWorkEndDrainsOnceAfterStop() async {
    let testHost = "poke-gate-flush"
    let store = makePokeGateStore(host: testHost)

    // stop() 직후 상태를 그대로 재현한다 — startedAt 은 이미 nil 이다. 그래서 이 진입점은
    // takePokesIfWorking 을 거치지 않고 drainReceivedPokes 를 직접 불러야 한다(거치면 가드에 막혀 0건이 된다).
    #expect(store.startedAt == nil)
    await store.flushPokesOnWorkEnd()?.value

    // 마지막 tick 이후 종료까지 최대 15초 창에 도착한 찔림의 꼬리 회수 — 정확히 1회.
    #expect(takePokesRequestCount(host: testHost) == 1)
}

@MainActor
@Test
func flushPokesOnWorkEndDoesNothingWhenSignedOut() async {
    let testHost = "poke-gate-flush-signed-out"
    let store = makePokeGateStore(host: testHost)
    // 강제 로그아웃 직후에도 stop() 은 불릴 수 있다(큐/진행 근무는 남는다). 그때 헛 Task 를 만들지 않는다.
    store.session = nil

    #expect(store.flushPokesOnWorkEnd() == nil)
    #expect(takePokesRequestCount(host: testHost) == 0)
}

@MainActor
@Test
func pokePollingStaysSleepFirstAndIdempotent() async {
    let testHost = "poke-gate-sleep-first"
    let store = makePokeGateStore(host: testHost)
    defer {
        store.pokePollTask?.cancel()
        store.pokePollTask = nil
    }
    // 근무중이라 게이트는 열려 있다 — 그런데도 시작 직후엔 요청이 없어야 한다(루프는 sleep 먼저·폴링 나중).
    store.startedAt = Date()

    store.startPokePolling()
    let firstTask = store.pokePollTask
    store.startPokePolling()

    // idempotent: 두 번 켜도 루프는 하나다(중복 기동은 요청을 그대로 배로 만든다).
    #expect(store.pokePollTask == firstTask)

    try? await Task.sleep(for: .milliseconds(50))
    // sleep 먼저 계약: 첫 15초가 지나기 전엔 이 호스트로 아무 요청도 나가지 않는다.
    // 이게 깨지면 스토어를 만들자마자 요청 목록을 단언하는 기존 테스트들이 폴링 요청에 오염된다.
    #expect(URLProtocolStub.requests(forHost: testHost).isEmpty)
}

// MARK: - 헬퍼

@MainActor
private func makePokeGateStore(host: String) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: pokeGateDefaults()
    )
    // 세션을 직접 주입해 로그인 흐름을 건너뛴다(팀 확정도 함께 — 찌르기 경로는 팀을 안 타지만 상태를 실제와 맞춘다).
    store.session = SupabaseSession(
        accessToken: "access-token",
        refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

/// 테스트마다 새 suite 를 쓴다 — .standard 를 공유하면 병렬 테스트가 서로의 저장 세션/설정을 덮어쓴다.
private func pokeGateDefaults() -> UserDefaults {
    let suiteName = "check-poke-gate-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// 요청 기록은 프로세스 전역 버퍼라 테스트마다 고유 호스트로 격리하고, 여기서 경로로 한 번 더 좁힌다.
private func takePokesRequestCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host).filter { $0.url?.path == "/rest/v1/rpc/take_pokes" }.count
}

private func tokenPrivacyRequestCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host)
        .filter { $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "GET" }
        .count
}
