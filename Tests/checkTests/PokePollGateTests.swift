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
// 폴링 주기(15초)는 static let 이라 테스트에서 줄일 수 없다. 전역 var 로 여는 대신 루프 본문을 localExpiryTick() 으로
// 분리해 직접 호출한다 — 전역 가변값은 병렬 스위트끼리 서로 덮어써 레이스를 무음으로 지운다
// (URLProtocolStub.delayedHosts 주석의 그 사고).

@MainActor
@Test
func localExpiryTickSkipsTakePokesWhenNotWorking() async {
    let testHost = "poke-gate-idle"
    let store = makePokeGateStore(host: testHost)

    // 로그인만 되어 있고 근무는 시작하지 않은 상태 — 예전 게이트(session != nil)라면 여기서 요청이 나갔다.
    #expect(store.startedAt == nil)
    await store.localExpiryTick()

    #expect(takePokesRequestCount(host: testHost) == 0)
}

@MainActor
@Test
func localExpiryTickTakesPokesWhileWorking() async {
    let testHost = "poke-gate-working"
    let store = makePokeGateStore(host: testHost)

    // 게이트 기준은 snapshot.isWorking 이 아니라 startedAt 이다(sendPoke 선게이트·서버 '열린 세션'과 같은 눈금).
    store.startedAt = Date()
    store.currentSessionID = "poke-gate-session"
    await store.localExpiryTick()

    // 근무중이면 tick 당 정확히 1건. 2건이면 withSessionRetry 가 헛돌고 있다는 뜻이다.
    #expect(takePokesRequestCount(host: testHost) == 1)
}

@MainActor
@Test
func localExpiryTickLoadsTokenPrivacyEvenWhenNotWorking() async {
    let testHost = "poke-gate-privacy"
    let store = makePokeGateStore(host: testHost)

    // 근무 이력이 없는 사용자(로그인 직후, 아직 시작을 안 누름).
    #expect(store.startedAt == nil)
    await store.localExpiryTick()

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


// MARK: - 리얼타임 킬스위치 (사장님 확정 2 — 리얼타임이 빠져도 나머지 6개가 온전해야 한다)

/// **폴링은 지워지지 않았다.** 리얼타임이 실제로 구독 중일 때만 쉰다.
/// 출시 시점 realtimeState 는 `.idle(.disabled)` 이므로 이 앱은 v0.2.33 과 **똑같이** 폴링한다 —
/// 그게 리얼타임 e2e 프로브가 실패해도 나머지를 배포할 수 있는 근거의 전부다.
@MainActor
@Test
func pollingKeepsRunningWhileRealtimeIsDisabled() async {
    let testHost = "poke-gate-realtime-off"
    let store = makePokeGateStore(host: testHost)
    store.startedAt = Date()

    #expect(store.realtimeState == .idle(.disabled))
    #expect(store.pollingIsPausedByRealtime == false)
    await store.localExpiryTick()

    #expect(takePokesRequestCount(host: testHost) == 1)
}

/// **v0.2.34 는 구독 중에도 폴링을 멈추지 않는다**(사장님 확정: 리얼타임을 켜되 폴링을 남긴다).
///
/// 이 테스트가 지키는 것은 "억제가 꺼져 있다"가 아니라 **그 이유가 살아 있다**는 것이다:
/// 리얼타임이 조용히 죽어도(좀비 소켓·재연결 실패) 찌르기가 30초 안에 도착한다. 억제를 되살리는
/// 순간 그 안전망이 사라지므로, v0.2.35 에서 뗄 때는 이 단언을 **일부러** 뒤집어야 한다.
/// 중복 소비는 서버의 take_pokes 원자성이 막는다 — 두 경로가 같은 찌름을 집어도 한쪽만 받는다.
@MainActor
@Test
func realtimeSubscribedStillPollsWhilePollingIsKeptAsBackstop() async {
    let testHost = "poke-gate-realtime-on"
    let store = makePokeGateStore(host: testHost)
    store.startedAt = Date()
    let now = Date()
    store.realtimeState = .subscribed(since: now, lastHeardAt: now)

    // 구독 중이지만 억제는 꺼져 있다.
    #expect(WorkTimerStore.pollingKeepsRunningAlongsideRealtime)
    #expect(store.pollingIsPausedByRealtime == false)
    await store.localExpiryTick()

    // take_pokes 가 **그대로 나간다** — 이것이 안전망의 전부다.
    #expect(takePokesRequestCount(host: testHost) == 1)
    #expect(tokenPrivacyRequestCount(host: testHost) == 1)
}

/// 억제 배선 자체는 살아 있다 — v0.2.35 에서 상수를 지우면 곧바로 동작해야 한다.
/// 상수를 통과시키지 않고 `realtimeState.isSubscribed` 를 직접 확인해, 배선이 썩지 않았음을 못 박는다.
@MainActor
@Test
func realtimeSubscribedIsStillTheSignalThatWouldPausePolling() async {
    let store = makePokeGateStore(host: "poke-gate-realtime-signal")
    let now = Date()
    #expect(store.realtimeState.isSubscribed == false)
    store.realtimeState = .subscribed(since: now, lastHeardAt: now)
    #expect(store.realtimeState.isSubscribed)
}

/// **근무 종료 꼬리 회수도 폴링의 일부라 구독 중에도 그대로 돈다**(v0.2.34 — 폴링을 남긴다).
///
/// 예전 이 자리는 "구독 중엔 그 15초 창이 애초에 없다"였다. 그 전제가 참이려면 초인종이 종료 직전까지
/// 살아 있어야 하는데, 좀비 소켓 감지·백오프 재연결은 실환경에서 **한 번도 돌지 않았다**. 링이 조용히
/// 죽어 있었다면 이 한 번의 회수가 그 근무의 마지막 찔림을 건지는 유일한 경로다.
/// 반대로 링이 이미 비웠다면 대가는 빈 배열 한 왕복뿐이다 — take_pokes 는 서버에서 **원자적으로**
/// 소비되므로 두 경로가 같은 행을 집어도 한쪽만 받는다. 그 원자성이 이 중복을 안전하게 만든다.
@MainActor
@Test
func flushPokesOnWorkEndStillDrainsWhileRealtimeIsSubscribed() async throws {
    let testHost = "poke-gate-flush-realtime"
    let store = makePokeGateStore(host: testHost)
    let now = Date()
    store.realtimeState = .subscribed(since: now, lastHeardAt: now)

    // 구독 **신호는 서 있고** 억제 판정만 상수가 가린다. 이 릴리스의 전부가 그 둘이 갈라져 있다는 것이다.
    #expect(store.realtimeState.isSubscribed)
    #expect(store.pollingIsPausedByRealtime == false)

    let task = try #require(
        store.flushPokesOnWorkEnd(),
        "구독을 이유로 꼬리 회수를 접으면 링이 죽어 있던 근무의 마지막 찔림이 조용히 사라진다"
    )
    await task.value

    #expect(takePokesRequestCount(host: testHost) == 1)
}

/// **억제 배선은 상수 뒤에서 그대로 살아 있다** — v0.2.35 에서 상수만 지우면 곧바로 다시 쉰다.
/// 위 테스트가 지키는 것은 "지금 돈다"뿐이라 가드를 통째로 뜯어내도 초록이다. 그러면 상수를 지우는 날
/// 아무 일도 일어나지 않고 — 그게 정확히 이 앱의 최악 실패 모드인 무음이다 — 아무도 모른다.
/// 그래서 꼬리 회수 쪽 가드와 **상수를 읽는 곳의 수**를 소스로 못 박는다(주석은 걷어내고 코드만 본다).
/// 폴링 tick 쪽 가드와 판정의 단일성은 RealtimeLinkTests 의 `폴링_억제_배선은_상수_뒤에서_그대로_살아_있다` 가 지킨다.
@Test
func flushPokesOnWorkEndKeepsSuppressionWiringBehindTheConstant() throws {
    let code = try pokeStoreCodeWithoutComments()

    // 꼬리 회수는 자기 판정을 따로 들지 않고 **단일 출처**를 보고 접는다.
    // 공백을 접은 문자열을 let 에 담는 이유는 실패 메시지다 — 식을 그대로 쓰면 파일 전체가 진단에 찍힌다.
    let collapsed = collapsingWhitespace(code)
    #expect(
        collapsed.contains("guard !pollingIsPausedByRealtime else { return nil }"),
        "flushPokesOnWorkEnd 의 억제 가드가 사라졌다 — 상수를 지워도 꼬리 회수는 안 쉰다"
    )
    // 상수를 읽는 곳은 선언 1 + 단일 출처 1, 정확히 둘이다. 늘어나면 v0.2.35 의 '상수만 지우기'가
    // 한 줄로 안 끝나고, 지우다 만 자리가 남으면 억제가 반만 되살아난다(그게 반쪽 침묵이다).
    #expect(code.components(separatedBy: "pollingKeepsRunningAlongsideRealtime").count - 1 == 2)
}

// MARK: - requestDrain 직렬화 (blocker 리얼타임 #2 — defer 함정)

/// **요청이 날아가 있는 사이에 도착한 신호는 정확히 한 번 더 돈다.**
/// 원안대로 `defer { drainInFlight = nil }` + 끝에서 requestDrain() 재호출로 쓰면, 재호출 시점에
/// drainInFlight 가 **아직 non-nil**(defer 는 스코프 종료 시점이다)이라 자기 자신의 가드에 막힌다 —
/// pending 만 다시 세우고 아무도 안 돌아 **요청 1건에서 멈춘다**. 초인종이 1초 안에 두 번 울리는
/// 상황이 정확히 이것이고, 폴링을 지운 구성에서는 회복 경로가 0이다.
///
/// 호스트가 `delayed-` 로 시작하는 것이 이 테스트의 핵심이다(URLProtocolStub.alwaysDelayedHostPrefix):
/// 응답이 지연돼야 "drain 이 도는 **중**"이라는 창이 실제로 열린다.
@MainActor
@Test
func requestDrainRunsTrailingSignalExactlyOnce() async {
    let testHost = "delayed-poke-gate-drain-trailing"
    let store = makePokeGateStore(host: testHost)

    store.requestDrain()
    // 첫 요청이 네트워크 대기에 들어갈 때까지만 기다린다(응답 지연 0.15s 보다 짧게).
    await waitUntilTakePokes(host: testHost, expected: 1)
    #expect(takePokesRequestCount(host: testHost) == 1)

    store.requestDrain()   // ← 도는 중에 도착한 신호
    store.requestDrain()   // 트레일링은 몇 번 울려도 한 번이다(합류)
    #expect(store.drainPendingTrailing)

    await store.drainInFlight?.value

    #expect(takePokesRequestCount(host: testHost) == 2)
    #expect(store.drainInFlight == nil)
    #expect(store.drainPendingTrailing == false)
}

/// 반대쪽 경계: **아직 시작도 안 한** drain 앞에 신호가 더 와도 요청은 하나다.
/// 그 신호들은 곧 나갈 그 요청이 어차피 가져오므로, 여기서 한 번 더 쏘면 무료 플랜 왕복만 는다.
@MainActor
@Test
func requestDrainCoalescesSignalsThatArriveBeforeItStarts() async {
    let testHost = "poke-gate-drain-single"
    let store = makePokeGateStore(host: testHost)

    store.requestDrain()
    store.requestDrain()
    store.requestDrain()
    await store.drainInFlight?.value

    #expect(takePokesRequestCount(host: testHost) == 1)
}

/// 결과를 **읽을 수 있다**는 것이 이 릴리스의 변경이다(예전 함수는 Void 라 캐치업이 재시도할 근거가 없었다).
/// 세션이 없으면 성공으로 접지 않는다 — 접으면 따라잡기 실패가 조용히 감춰진다.
@MainActor
@Test
func drainReceivedPokesReportsOutcome() async {
    let testHost = "poke-gate-drain-outcome"
    let store = makePokeGateStore(host: testHost)

    let ok = await store.drainReceivedPokes()
    #expect(ok == .ok(count: 0))
    #expect(ok.isOK)

    store.session = nil
    let failed = await store.drainReceivedPokes()
    #expect(failed.isOK == false)
    #expect(takePokesRequestCount(host: testHost) == 1)   // 두 번째는 요청조차 안 나갔다
}

// MARK: - 두 대 맥 (blocker 리얼타임 #5)

/// **흡수 세션의 주인은 다른 맥이다.** 로컬 startedAt 이 서 있어도 여기서 소비하면 진짜 주인이 못 본다
/// (take_pokes 는 서버 원자 소비라 복구 불가다).
@MainActor
@Test
func takePokesIfWorkingSkipsAdoptedRemoteSession() async {
    let testHost = "poke-gate-adopted"
    let store = makePokeGateStore(host: testHost)
    store.startedAt = Date()
    store.adoptedRemoteSession = true

    await store.takePokesIfWorking()

    #expect(takePokesRequestCount(host: testHost) == 0)
}

/// 근무 시작 직후의 창을 닫는 1회 drain. 이게 없으면 start() 와 다음 폴링 tick 사이(최대 15초)에
/// 도착한 찔림이 붕 뜬다 — takePokesIfWorking 이 startedAt 을 요구하는데 그 값이 방금 섰기 때문이다.
@MainActor
@Test
func startRequestsOneDrain() async {
    let testHost = "poke-gate-start-drain"
    let store = makePokeGateStore(host: testHost)

    store.start()
    await store.drainInFlight?.value

    #expect(takePokesRequestCount(host: testHost) == 1)
}

// MARK: - 울트라 지갑 (계약 타입 · 순수 반영)

/// **status 를 먼저 읽는 디코더다.** `invalid` 응답에는 status 외의 키가 하나도 없어서,
/// balance 를 decode 하려 들면 통째로 throw 된다 — 그러면 스토어가 '서버 오류'로 오진하고
/// 화면이 "못 읽었어요 + 재시도"를 띄운다(재시도해도 같은 답이 온다).
@Test
func ultraWalletResponseDecodesInvalidWithoutThrowing() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let response = try decoder.decode(UltraWalletResponse.self, from: Data(#"{"status":"invalid"}"#.utf8))

    #expect(response.isOK == false)
    #expect(response.balance == 0)
    #expect(response.missions.isEmpty)
}

/// 성공 응답의 **모든 계약 키**를 실제 JSON 으로 통과시킨다. 직접 생성자로는 커스텀 디코더의 누락을
/// 원리적으로 못 잡는다(PokeSendResponse 주석의 그 함정이 이 타입에도 그대로 있다).
///
/// 랩 3형제(`laps_settled`/`laps_granted`/`worked_seconds`)는 **여기 없다** — 일부러다. 이 응답은
/// 그 키들을 모르는 서버(랩 전환 이전)의 모양이고, 그 서버에서도 디코드가 살아야 한다는 것이
/// 이 테스트가 지키는 것이다. 새 키 쪽은 V0239UltraLapTests 가 있음/없음 양쪽으로 덮는다.
@Test
func ultraWalletResponseDecodesEveryContractKey() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let json = """
    {"status":"ok","balance":3,"balance_cap":5,"daily_floor":1,"day":"2026-08-19","floor_applied":true,
     "missions":[{"key":"work3h","kst_day":"2026-08-19","target_seconds":10800,"progress_seconds":14400,
                  "claimed":false,"granted_now":false,"capped":true}],
     "worked_seconds_closed":14400,"worked_seconds_open":600,
     "streak_days":3,"streak_includes_today":true,"measured_at":1787098516}
    """
    let response = try decoder.decode(UltraWalletResponse.self, from: Data(json.utf8))

    #expect(response.isOK)
    #expect(response.balance == 3)
    #expect(response.balanceCap == 5)          // UI 가 리터럴 5 를 박지 않게 하는 값
    #expect(response.dailyFloor == 1)
    #expect(response.day == "2026-08-19")
    #expect(response.floorApplied)
    #expect(response.workedSecondsClosed == 14400)
    #expect(response.workedSecondsOpen == 600)
    #expect(response.workedSecondsToday == 15000)
    #expect(response.streakDays == 3)
    #expect(response.streakIncludesToday)
    #expect(response.measuredAt == 1787098516)
    let mission = try #require(response.missions.first)
    #expect(mission.key == "work3h")
    #expect(mission.kstDay == "2026-08-19")
    #expect(mission.targetSeconds == 10800)
    #expect(mission.progressSeconds == 14400)
    // 상한에서는 **claimed 가 false 로 남고 capped 가 참이다**(서버가 장부를 안 쓴다).
    #expect(mission.claimed == false)
    #expect(mission.grantedNow == false)
    #expect(mission.capped)
}

/// PokeSendResponse 의 **커스텀 init(from:) 함정**. CodingKey 만 더하고 decodeIfPresent 를 빠뜨리면
/// 값이 영원히 nil 이라, 잔량 배지가 발사 직후에도 갱신되지 않는다.
/// 그리고 새 필드는 반드시 Optional 이다 — 비옵셔널이면 이 키를 안 보내는 서버에서 디코드가 통째로 throw 되어
/// 콕찌르기 목록이 전원 사라진다.
@Test
func pokeSendResponseDecodesUltraBalanceAndRing() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let full = try decoder.decode(
        PokeSendResponse.self,
        from: Data(#"{"status":"ok","ultra_remaining":2,"ultra_balance":2,"ring":"sent"}"#.utf8)
    )
    #expect(full.ultraBalance == 2)
    #expect(full.ring == "sent")
    #expect(full.ultraBalanceForDisplay == 2)

    // 구버전 서버(키 없음)에서도 디코드는 살아 있고, 잔량은 옛 키로 폴백한다.
    let legacy = try decoder.decode(
        PokeSendResponse.self,
        from: Data(#"{"status":"ok","ultra_remaining":1}"#.utf8)
    )
    #expect(legacy.ultraBalance == nil)
    #expect(legacy.ring == nil)
    #expect(legacy.ultraBalanceForDisplay == 1)

    // 둘 다 없으면 **모름**이다(0 이 아니다 — 0 이라고 말하면 거짓말이 될 수 있다).
    let bare = try decoder.decode(PokeSendResponse.self, from: Data(#"{"status":"ok"}"#.utf8))
    #expect(bare.ultraBalanceForDisplay == nil)

    // 음수는 0 으로 접는다(숫자로 말할 수 없는 값).
    let negative = try decoder.decode(
        PokeSendResponse.self,
        from: Data(#"{"status":"ok","ultra_balance":-3}"#.utf8)
    )
    #expect(negative.ultraBalanceForDisplay == 0)
}

/// 미션 목록은 **오늘 행만** 본다. 어제 행(p_days_back=1 이 함께 주는 소급분)은 적립을 위한 것이지
/// 화면의 '오늘 미션'이 아니다 — 섞으면 어제 이미 받은 몫 때문에 오늘 줄이 완료로 보인다.
/// 그리고 상한 행은 claimedToday=false + cappedToday=true 로 나온다(그 조합이 "가득 차서 못 받아요"다).
@Test
func missionRowsUseTodayOnlyAndSurfaceCapped() {
    let response = UltraWalletResponse(
        status: "ok",
        balance: 5,
        balanceCap: 5,
        dailyFloor: 1,
        day: "2026-08-19",
        floorApplied: false,
        missions: [
            .init(key: "work3h", kstDay: "2026-08-19", targetSeconds: 10800,
                  progressSeconds: 10800, claimed: false, grantedNow: false, capped: true),
            .init(key: "work3h", kstDay: "2026-08-18", targetSeconds: 10800,
                  progressSeconds: 14400, claimed: true, grantedNow: false, capped: false),
            // 모르는 key 는 무시한다(서버가 미션을 늘려도 옛 앱이 빈 줄을 그리지 않는다).
            .init(key: "future_mission", kstDay: "2026-08-19", targetSeconds: 60,
                  progressSeconds: 60, claimed: true, grantedNow: true, capped: false)
        ],
        workedSecondsClosed: 10800,
        workedSecondsOpen: 0,
        streakDays: 4,
        streakIncludesToday: true,
        measuredAt: 1
    )

    let rows = MissionProgress.rows(from: response)
    #expect(rows.map(\.kind) == [.todayThreeHours, .dailyFloor, .arrivalStreak])

    let today = rows[0]
    #expect(today.progress == 1)
    #expect(today.claimedToday == false)   // 상한이라 서버가 장부를 안 썼다
    #expect(today.cappedToday)
    // 어제 행의 claimed=true 가 오늘 줄로 새면 이 단언이 깨진다.

    #expect(rows[1].progress == nil)       // 밑바닥 줄엔 진행 개념이 없다
    #expect(rows[1].claimedToday == false) // floor_applied=false = 오늘 보정이 안 걸렸다
    #expect(rows[1].detail == "잔량 0이면 1개로")
    #expect(rows[2].detail == "4일 연속")

    // ★ 진짜 갈림길: **오늘 행이 아예 없을 때**. `kstDay == day` 대조를 빼면 어제 행이 오늘 줄로 올라와
    //   "오늘 몫 이미 받음"이라고 거짓말한다(어제 받았을 뿐이다). 위 목록은 오늘 행이 앞에 있어
    //   대조를 지워도 우연히 같은 답이 나오므로, 그것만으로는 이 결함을 못 잡는다(실측: 초록으로 살아남았다).
    let yesterdayOnly = UltraWalletResponse(
        status: "ok", balance: 1, balanceCap: 5, dailyFloor: 1, day: "2026-08-19",
        floorApplied: false,
        missions: [
            .init(key: "work3h", kstDay: "2026-08-18", targetSeconds: 10800,
                  progressSeconds: 14400, claimed: true, grantedNow: false, capped: false)
        ],
        workedSecondsClosed: 1800, workedSecondsOpen: 0,
        streakDays: 1, streakIncludesToday: true, measuredAt: 1
    )
    let todayRow = MissionProgress.rows(from: yesterdayOnly)[0]
    #expect(todayRow.claimedToday == false, "어제 받은 몫이 오늘 줄로 새면 사용자는 오늘 몫을 포기한다")
    #expect(todayRow.progress == 1800.0 / 10800.0)

    // invalid 응답은 줄을 만들지 않는다(빈 화면이 거짓 진행 바보다 낫다).
    #expect(MissionProgress.rows(from: UltraWalletResponse(status: "invalid")).isEmpty)
}

/// **granted_now 가 유일한 연출 트리거다.** claimed 로 트리거하면 5분마다 참이라 근무 내내 2초 연출이 반복된다.
/// 그리고 연출과 함께 **지속 증거**(missionNotice)를 같은 지점에서 남긴다 — 연출은 2초면 사라지고,
/// 자리를 비운 사용자에게는 그것만으로 아무 증거도 남지 않는다.
@MainActor
@Test
func applyUltraWalletFiresRewardOnlyOnGrantedNow() {
    let store = makePokeGateStore(host: "poke-gate-wallet-granted")
    var fired: [ReactionKind] = []
    store.onRewardTrigger = { fired.append($0) }

    func row(grantedNow: Bool, claimed: Bool) -> UltraWalletResponse {
        UltraWalletResponse(
            status: "ok", balance: 2, balanceCap: 5, dailyFloor: 1, day: "2026-08-19",
            floorApplied: true,
            missions: [.init(key: "work3h", kstDay: "2026-08-19", targetSeconds: 10800,
                             progressSeconds: 14400, claimed: claimed, grantedNow: grantedNow)],
            workedSecondsClosed: 14400, workedSecondsOpen: 0,
            streakDays: 2, streakIncludesToday: true, measuredAt: 1
        )
    }

    // ① 이미 받은 날: 연출도 안내도 없다.
    store.applyUltraWallet(row(grantedNow: false, claimed: true))
    #expect(fired.isEmpty)
    #expect(store.missionNotice == nil)
    #expect(store.ultraBalance == 2)
    #expect(store.ultraBalanceCap == 5)
    #expect(store.missionsLoaded)
    #expect(store.streakDays == 2)

    // ② 방금 받았다: 연출 1회 + 지속 증거.
    // 문장이 "오늘 3시간"이 아니라 "3시간 채웠어요"인 이유는 랩 반복 지급이다 — 하루에 여러 번 오는
    // 안내라 '오늘'을 주어로 쓰면 두 번째부터는 이미 지난 일을 다시 말하는 것처럼 읽힌다.
    // 이 응답에는 laps_granted 가 없으므로(랩 이전 서버와 같은 모양) 개수 없는 쪽으로 접힌다.
    store.applyUltraWallet(row(grantedNow: true, claimed: true))
    #expect(fired == [.ultraCharged])
    #expect(store.missionNotice == "3시간 채웠어요 — 울트라 +1")
}

/// invalid 응답은 **서버 오류가 아니다**(비로그인/프로필 없음). 실패 플래그를 세우면 화면이
/// "못 읽었어요 + 재시도"를 띄우는데, 재시도해도 같은 답이 온다.
@MainActor
@Test
func applyUltraWalletTreatsInvalidAsNotAFailure() {
    let store = makePokeGateStore(host: "poke-gate-wallet-invalid")
    store.ultraBalanceFailed = true
    store.applyUltraBalance(4)

    store.applyUltraWallet(UltraWalletResponse(status: "invalid"))

    #expect(store.ultraBalanceFailed == false)
    #expect(store.ultraBalance == 4)      // 알던 잔량을 지우지 않는다
    #expect(store.missionsLoaded == false)
}

/// 5분 스로틀 + 근무중 게이트. 이 자리는 blocker(서버 #3)의 **마지막 그물**이라 완전히 꺼지면 안 되고,
/// 15초마다 나가서도 안 된다(무료 플랜).
@MainActor
@Test
func periodicWalletSyncIsThrottledAndRequiresWorking() async {
    let testHost = "poke-gate-wallet-throttle"
    let store = makePokeGateStore(host: testHost)

    // ① 비근무면 요청 0건이다(근무 없는 날엔 미션이 존재할 수 없다).
    store.startedAt = nil
    store.syncUltraWalletIfDue(now: Date())
    try? await Task.sleep(for: .milliseconds(60))
    #expect(walletSyncRequestCount(host: testHost) == 0)

    // ② 근무중 + 첫 호출 → 1건.
    let base = Date()
    store.startedAt = base
    store.syncUltraWalletIfDue(now: base)
    await waitUntilCount(host: testHost, expected: 1)
    #expect(walletSyncRequestCount(host: testHost) == 1)

    // ③ 4분 뒤 → 여전히 1건(스로틀이 막는다).
    store.syncUltraWalletIfDue(now: base.addingTimeInterval(240))
    try? await Task.sleep(for: .milliseconds(60))
    #expect(walletSyncRequestCount(host: testHost) == 1)

    // ④ 5분을 넘기면 다시 나간다.
    store.lastUltraWalletSyncAt = base.addingTimeInterval(-1)
    store.syncUltraWalletIfDue(now: base.addingTimeInterval(400))
    await waitUntilCount(host: testHost, expected: 2)
    #expect(walletSyncRequestCount(host: testHost) == 2)
}

/// 폴링 tick 이 실제로 그 스로틀을 **부른다**. syncUltraWalletIfDue 를 아무리 잘 만들어도
/// tick 에서 호출을 빠뜨리면 blocker(서버 #3)의 마지막 그물이 통째로 없어진다
/// (근무만 하고 패널을 안 연 사용자의 코인이 영구 소실된다).
@MainActor
@Test
func localExpiryTickSyncsWalletWhileWorking() async {
    let testHost = "poke-gate-wallet-tick"
    let store = makePokeGateStore(host: testHost)
    store.startedAt = Date()

    await store.localExpiryTick()
    await waitUntilCount(host: testHost, expected: 1)

    #expect(walletSyncRequestCount(host: testHost) == 1)
}

/// **3시간 마일스톤이 지갑 sync 를 쏜다.** 이 호출 지점이 없으면 근무만 하고 패널을 안 연 사용자는
/// 그날 sync 가 0회라 서버가 미션을 평가할 기회 자체가 없다(코인 영구 소실).
/// 하루 1회 스로틀이라 두 번째 평가에서는 요청이 늘지 않는다.
@MainActor
@Test
func threeHourMilestoneFiresWalletSyncOnceADay() async {
    let testHost = "poke-gate-wallet-milestone"
    let store = makePokeGateStore(host: testHost)
    // ⚠️ Date() 를 쓰면 **KST 00:00~03:00 사이에만 빨개진다**: todayDuration 은 진행 세션을 KST 자정으로
    //    클리핑하므로 새벽에 돌리면 3시간이 채워지지 않아 마일스톤이 발화하지 않는다(실측으로 잡았다).
    //    시각을 고정해 하루 중 언제 돌려도 같은 결과가 나오게 한다 — displayNow 까지 함께 세우는 것이 핵심이다
    //    (todayDuration 이 보는 '지금'은 인자 now 가 아니라 displayNow 다).
    let now = milestoneFixtureNow
    store.startedAt = now.addingTimeInterval(-3 * 3600 - 60)
    store.displayNow = now
    store.accumulatedSeconds = 0
    store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: now)

    store.evaluateTimeMilestones(now: now)
    await waitUntilCount(host: testHost, expected: 1)
    #expect(walletSyncRequestCount(host: testHost) == 1)

    store.evaluateTimeMilestones(now: now)
    try? await Task.sleep(for: .milliseconds(60))
    #expect(walletSyncRequestCount(host: testHost) == 1)
}

/// **아직 3시간이 아니면 안 쏜다**(위 테스트의 짝 — 임계를 0으로 만드는 뮤턴트를 잡는다).
@MainActor
@Test
func milestoneDoesNotFireWalletSyncBeforeThreeHours() async {
    let testHost = "poke-gate-wallet-early"
    let store = makePokeGateStore(host: testHost)
    let now = milestoneFixtureNow
    store.startedAt = now.addingTimeInterval(-2 * 3600)
    store.displayNow = now
    store.accumulatedSeconds = 0
    store.accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: now)

    store.evaluateTimeMilestones(now: now)
    try? await Task.sleep(for: .milliseconds(60))

    #expect(walletSyncRequestCount(host: testHost) == 0)
}

/// 서버에 RPC 가 아직 없으면(PGRST202) 전용 오류로 접는다. 재던지면 "네트워크 실패"와 구별이 사라져
/// 진단이 성립하지 않는다. 그리고 **잔량을 지우지 않는다** — 재화는 이월되므로 직전 값이 지금도 맞다.
@MainActor
@Test
func walletSyncFoldsMissingRPCIntoDedicatedErrorAndKeepsBalance() async {
    let testHost = "wallet-missing-host"
    let store = makePokeGateStore(host: testHost)
    store.applyUltraBalance(2)

    await store.performSyncUltraWallet(reason: .panelOpen)

    #expect(store.ultraBalanceFailed)
    #expect(store.ultraBalance == 2)

    // 서비스 계층이 실제로 접었는지도 직접 확인한다(스토어가 삼켜 버리면 위 단언만으로는 못 가른다).
    do {
        _ = try await store.service.syncUltraWallet(accessToken: "access-token")
        Issue.record("PGRST202 인데 오류가 안 났다")
    } catch let error as SupabaseWorkServiceError {
        #expect(error == .ultraWalletUnavailable)
    } catch {
        Issue.record("예상치 못한 오류: \(error)")
    }
}

// MARK: - 하위 패널 상호배타 (blocker UI-1 / UI-2)

/// ★ blocker UI-2 — **배지 탭은 '봤다'가 아니다.** openUltraPanel(from:.poke) 이 closePokePanel() 을 타면
/// 아직 한 번도 안 본 3글자 메시지가 그 자리에서 사라진다(take_pokes 는 서버 원자 소비라 복구 불가).
@MainActor
@Test
func openUltraPanelFromPokeDoesNotConsumeUnseenMessage() {
    let store = makePokeGateStore(host: "poke-gate-ultra-panel-open")
    store.isPokePanelVisible = true
    store.lastShownMessage = ReceivedMessage(id: "m1", fromName: "영식", body: "밥?", createdAt: Date())
    store.pokeNotice = "안내"
    store.messageNotice = "메시지 안내"

    store.openUltraPanel(from: .poke)

    #expect(store.isUltraPanelVisible)
    #expect(store.isPokePanelVisible == false)
    // closePokePanel() 이 죽이는 세 값이 **살아 있어야** 한다.
    #expect(store.lastShownMessage != nil)
    #expect(store.pokeNotice == "안내")
    #expect(store.messageNotice == "메시지 안내")
}

/// [뒤로]는 진입한 곳으로 돌아간다. 그리고 돌아갈 때도 closePokePanel 부작용을 **두 번째로** 타지 않는다.
@MainActor
@Test
func closeUltraPanelReturnsToOriginWithoutSideEffects() {
    let store = makePokeGateStore(host: "poke-gate-ultra-panel-back")
    store.isPokePanelVisible = true
    store.lastShownMessage = ReceivedMessage(id: "m1", fromName: "영식", body: "밥?", createdAt: Date())
    store.openUltraPanel(from: .poke)
    store.missionNotice = "3시간 채웠어요 — 울트라 +1"

    store.closeUltraPanel()

    #expect(store.isUltraPanelVisible == false)
    #expect(store.isPokePanelVisible)               // 콕찌르기로 돌아왔다
    #expect(store.lastShownMessage != nil)          // 여전히 안 지웠다
    #expect(store.missionNotice == nil)             // 패널을 떠나면 안내는 접는다

    // 홈에서 들어왔으면 홈으로 돌아간다(콕찌르기를 멋대로 열지 않는다).
    store.openUltraPanel(from: .home)
    store.isPokePanelVisible = false
    store.closeUltraPanel()
    #expect(store.isPokePanelVisible == false)

    // ★ 불변식: **콕찌르기 패널의 현재 상태와 무관하게** closeUltraPanel 은 영수증을 죽이지 않는다.
    //   여기서 togglePokePanel() 을 쓰면(원안의 유혹) 이미 열려 있는 경우 그 토글이 closePokePanel() 로
    //   갈라져 안 본 3글자를 소비한다. 지금은 도달하기 어려운 조합이지만, 이 불변식이 없으면
    //   다음 사람이 "토글이 더 깔끔하다"고 바꾸는 순간 무음으로 되살아난다.
    store.openUltraPanel(from: .poke)
    store.isPokePanelVisible = true          // 다른 경로가 패널을 다시 연 상태를 흉내 낸다
    store.lastShownMessage = ReceivedMessage(id: "m2", fromName: "민수", body: "고?", createdAt: Date())
    store.pokeNotice = "안내2"
    store.closeUltraPanel()
    #expect(store.lastShownMessage?.id == "m2", "closeUltraPanel 이 안 본 메시지를 소비했다")
    #expect(store.pokeNotice == "안내2")
}

/// ★ blocker UI-1 — 상호배타는 **양방향**이다. 한쪽만 걸면 울트라 화면이 다른 패널 위에 남아 굳고,
/// 로그아웃 후 재로그인 시 남의 잔량 화면이 그대로 떠 있다.
@MainActor
@Test
func everyOtherPanelTogglesCloseTheUltraPanel() {
    let store = makePokeGateStore(host: "poke-gate-ultra-exclusive")

    func openUltra() {
        store.isLeaderboardVisible = false
        store.isTokenBoardVisible = false
        store.isPokePanelVisible = false
        store.isInsightsPanelVisible = false
        store.openUltraPanel(from: .home)
        #expect(store.isUltraPanelVisible)
    }

    openUltra(); store.toggleLeaderboard()
    #expect(store.isUltraPanelVisible == false, "리그를 열면 울트라 패널이 닫혀야 한다")

    openUltra(); store.toggleTokenBoard()
    #expect(store.isUltraPanelVisible == false, "토큰 보드를 열면 울트라 패널이 닫혀야 한다")

    openUltra(); store.togglePokePanel()
    #expect(store.isUltraPanelVisible == false, "콕찌르기를 열면 울트라 패널이 닫혀야 한다")

    openUltra(); store.toggleInsightsPanel()
    #expect(store.isUltraPanelVisible == false, "개인 기록을 열면 울트라 패널이 닫혀야 한다")
}

// MARK: - JWT / 세션 갱신 조정자

/// **base64url 이다.** 표준 base64 디코더로 그냥 읽으면 `-`/`_` 와 패딩 부재 때문에 언제나 nil 이 되고,
/// 그러면 선제 갱신이 영원히 50분 폴백으로만 돌아 조용히 열화된다.
/// 그리고 nil 은 '만료'가 아니라 **'모른다'** 다 — 만료로 읽으면 파싱 한 번 실패에 갱신 폭풍이 난다.
@Test
func jwtClaimsReadsExpiryFromBase64URLPayload() {
    // 페이로드 {"exp":1787098516,"sub":"ÿÿ~"} 의 base64 는
    //   eyJleHAiOjE3ODcwOTg1MTYsInN1YiI6IsO/w79+In0=
    // 로 **'+' 와 '/' 를 둘 다 포함하고**, url-safe 로 바꾸면 '_' 와 '-' 가 되고 패딩이 사라진다.
    // 이 페이로드를 고르는 것이 이 테스트의 전부다 — 아무 JSON 이나 쓰면 base64 에 '+/' 가 안 나와
    // **url-safe 치환을 지워도 초록**이 된다(실측: 첫 판이 그렇게 통과했다).
    let token = "header.eyJleHAiOjE3ODcwOTg1MTYsInN1YiI6IsO_w79-In0.signature"

    #expect(JWTClaims.expiry(accessToken: token) == Date(timeIntervalSince1970: 1787098516))
    // 모르는 것은 모른다고 답한다.
    #expect(JWTClaims.expiry(accessToken: "not-a-jwt") == nil)
    #expect(JWTClaims.expiry(accessToken: "header.@@@@.sig") == nil)
    #expect(JWTClaims.expiry(accessToken: "header.eyJleHAiOjE3ODcwOTg1MTYsInN1YiI6IsO_w79-In0") != nil)   // 조각 2개면 충분하다
    // exp 가 없는 토큰도 nil 이다("모른다" — 만료가 아니다).
    #expect(JWTClaims.expiry(accessToken: "header.eyJzdWIiOiJtZSJ9.sig") == nil)
}

/// 갱신 주체는 **하나**다. 동시에 둘이 부르면 refresh token 회전이 겹쳐 GoTrue reuse-detection 이
/// 한쪽을 무효로 만들고, 그 결과가 근무 중 강제 로그아웃이다.
@MainActor
@Test
func sessionRefreshCoordinatorCollapsesConcurrentRefreshes() async throws {
    let coordinator = SessionRefreshCoordinator()
    var calls = 0
    var applied = 0
    let refreshed = SupabaseSession(accessToken: "new", refreshToken: "next", userID: "me")

    func run() async throws -> SupabaseSession {
        try await coordinator.refresh(
            generation: 1,
            tokenProvider: { "refresh-token" },
            refresh: { _ in
                calls += 1
                try? await Task.sleep(for: .milliseconds(30))
                return refreshed
            },
            apply: { _ in applied += 1 }
        )
    }

    // `async let` 두 개 대신 Task 두 개를 쓴다 — 둘 다 @MainActor 라 실행은 직렬이지만,
    // 첫 갱신이 sleep 으로 await 지점에 들어간 사이 두 번째가 들어오는 **정확히 그 창**이 재현된다.
    let first = Task { @MainActor in try await run() }
    let second = Task { @MainActor in try await run() }
    let results = try await [first.value, second.value]

    #expect(results.allSatisfy { $0 == refreshed })
    #expect(calls == 1, "동시 호출이 갱신을 두 번 냈다 = refresh token 회전 경합")
    #expect(applied == 1, "스토어에 쓰는 주체도 하나여야 한다(늦은 쪽이 낡은 토큰으로 되돌린다)")

    // 합류가 끝나면 슬롯이 비어 다음 갱신이 정상적으로 나간다(defer 를 안 쓴 것의 증거).
    _ = try await run()
    #expect(calls == 2)
}

/// **withSessionRetry 가 조정자를 통과하는지**를 값으로 못 박는다.
/// 이게 없으면 "조정자를 우회해 service.refreshSession 을 직접 부르는" 변경이 **오늘은 증상이 없다** —
/// 갱신 주체가 하나뿐이라 동작이 똑같기 때문이다. 그리고 리얼타임 선제 갱신이 붙는 순간(W2)
/// 주체가 둘이 되어 근무 중 강제 로그아웃으로 나타난다. 증상이 없는 동안 고정해 두는 것이 요점이다.
@MainActor
@Test
func withSessionRetryRefreshesThroughTheCoordinator() async {
    // 스텁 규약: 호스트가 "expired-token" 으로 끝나고 Authorization 이 옛 토큰이면 401(PGRST301)을 돌려준다.
    let testHost = "poke-gate-coordinator-expired-token"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(testHost)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: pokeGateDefaults()
    )
    defer { store.tickerTask?.cancel() }
    store.session = SupabaseSession(
        accessToken: "old-access-token",
        refreshToken: "refresh-token",
        userID: "00000000-0000-0000-0000-000000000002"
    )

    let outcome = await store.drainReceivedPokes()

    #expect(outcome.isOK, "401 재시도 뒤 성공했어야 한다")
    #expect(store.sessionRefreshCoordinator.completedRefreshCount == 1,
            "갱신이 조정자를 통과하지 않았다 = service.refreshSession 을 직접 부르는 두 번째 주체가 생겼다")
    #expect(store.session?.accessToken == "refreshed-token")
}

/// 세대가 다르면 합류하지 않는다 — 앞 계정의 갱신 결과를 새 계정 세션에 쓰면 남의 토큰으로 근무를 기록한다.
@MainActor
@Test
func sessionRefreshCoordinatorDoesNotJoinAcrossGenerations() async throws {
    let coordinator = SessionRefreshCoordinator()
    var calls = 0
    let session = SupabaseSession(accessToken: "new", refreshToken: "next", userID: "me")

    _ = try await coordinator.refresh(
        generation: 1, tokenProvider: { "t" },
        refresh: { _ in calls += 1; return session }, apply: { _ in }
    )
    _ = try await coordinator.refresh(
        generation: 2, tokenProvider: { "t" },
        refresh: { _ in calls += 1; return session }, apply: { _ in }
    )
    #expect(calls == 2)
}

// MARK: - 소스 계약: 하루 한도 어휘가 되살아나지 않는다 (blocker UI-5)

/// 서버가 `ultra_poke_daily_limit` 을 지웠으므로, 클라에 하루 한도 어휘가 남으면 **계약 상대가 없는
/// 문장**이 된다. 0잔량 사용자가 실제로 읽는 줄이 그것이라 특히 위험하다.
/// 주석은 걷어내고 **코드만** 본다 — 이 결정을 설명하는 주석이 그 단어들을 정당하게 포함한다
/// (안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
@Test
func pokeStoreSourceCarriesNoDailyLimitVocabulary() throws {
    let source = try pokeStoreSource()
    let code = source
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            guard let range = line.range(of: "//") else { return String(line) }
            return String(line[line.startIndex..<range.lowerBound])
        }
        .joined(separator: "\n")

    for banned in ["하루에", "오늘 다 썼", "소진", "남음", "오늘 몫"] {
        #expect(
            code.contains(banned) == false,
            "WorkTimerStorePoke.swift 코드에 '\(banned)' 가 남아 있다 — 하루 한도는 서버에서 사라진 개념이다."
        )
    }
    // 살아 있어야 하는 쪽도 함께 못 박는다(삭제로 초록을 만들 수 없게).
    #expect(code.contains("ultraEmptyNotice"))
    #expect(code.contains("미션으로 충전하세요"))
}

private func pokeStoreSource() throws -> String {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repoRoot.appendingPathComponent("Sources/check/WorkTimerStorePoke.swift")
    guard FileManager.default.fileExists(atPath: url.path) else {
        struct MissingSource: Error { let path: String }
        // 못 찾은 것을 통과로 접으면 경로가 바뀐 날 방어망이 사라진 것을 아무도 모른다.
        throw MissingSource(path: url.path)
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// 주석을 걷어낸 WorkTimerStorePoke.swift 코드. 하우스 규칙이다 — 안 걷어내면 결정을 설명하는 주석이
/// 검사 대상 어휘를 정당하게 포함해, **설명을 지워야만 초록이 되는** 테스트가 된다.
private func pokeStoreCodeWithoutComments() throws -> String {
    try pokeStoreSource()
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            guard let range = line.range(of: "//") else { return String(line) }
            return String(line[line.startIndex..<range.lowerBound])
        }
        .joined(separator: "\n")
}

/// 연속 공백을 한 칸으로 접는다. 들여쓰기·줄바꿈에 흔들리지 않으면서 **가드 안에 무엇이 들어 있는지**를
/// 본다 — 조각을 따로 contains 하면 본문을 가드 밖으로 꺼낸 뮤턴트를 그대로 놓친다.
private func collapsingWhitespace(_ source: String) -> String {
    source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// take_pokes 요청이 지정 건수에 도달할 때까지 짧게 기다린다(지연 응답 호스트 전용).
/// 타임아웃이 넉넉한 이유: 전체 스위트(1000+ 테스트)를 병렬로 돌리면 MainActor 경합으로 Task 시작이
/// 수십 초 밀린다. 짧게 잡으면 **결함이 아니라 부하** 때문에 빨개진다(실측: 2초로는 전체 실행에서 실패).
private func waitUntilTakePokes(host: String, expected: Int, timeout: TimeInterval = 60) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if takePokesRequestCount(host: host) >= expected { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private func walletSyncRequestCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host).filter { $0.url?.path == "/rest/v1/rpc/ultra_wallet_sync" }.count
}

/// 발사형(Task) 경로라 요청이 비동기로 도착한다. 폴링 없이 짧게 기다린다.
/// 마일스톤 픽스처의 고정 '지금'(2026-08-19 15:00 KST — 낮 한복판). 하루 경계에서 멀리 떨어져 있어야
/// 진행 세션의 자정 클리핑이 결과를 바꾸지 않는다.
private let milestoneFixtureNow = Date(timeIntervalSince1970: 1_787_119_200)

private func waitUntilCount(host: String, expected: Int, timeout: TimeInterval = 60) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if walletSyncRequestCount(host: host) >= expected { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: - AF: 자리 비움 정책 폴링 게이트 (v0.2.35 — docs/away-close.md 2절)
//
// away_sync() 는 폴링 본문에 얹혀 있다. 근무 중에는 매 주기 불러야 하고(임계·복원 창·판정 재료가
// 매번 바뀔 수 있다), **비근무에서는 스로틀**해야 한다 — 로그인만 해 둔 맥 38대가 하루 종일
// 30초마다 이 RPC 를 때리면 그건 take_pokes 게이트를 만든 이유(O1)를 그대로 되풀이하는 것이다.

@MainActor
@Test
func awaySyncIsThrottledWhileNotWorking() async {
    let testHost = "afk-sync-idle"
    let store = makePokeGateStore(host: testHost)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(store.startedAt == nil)

    await store.refreshAwayStateIfNeeded(now: start)
    #expect(awaySyncRequestCount(host: testHost) == 1)

    // 스로틀 안(60초 뒤)에는 나가지 않는다.
    await store.refreshAwayStateIfNeeded(now: start.addingTimeInterval(60))
    #expect(awaySyncRequestCount(host: testHost) == 1)

    // 스로틀을 넘기면 다시 나간다 — 영구 침묵이 아니라 지연이다(복원 배너가 비근무에서 뜬다).
    await store.refreshAwayStateIfNeeded(
        now: start.addingTimeInterval(WorkTimerStore.awaySyncIdleThrottleSeconds + 1)
    )
    #expect(awaySyncRequestCount(host: testHost) == 2)
}

@MainActor
@Test
func awaySyncRunsEveryPollWhileWorking() async {
    let testHost = "afk-sync-working"
    let store = makePokeGateStore(host: testHost)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    store.startedAt = start
    store.currentSessionID = "50000000-0000-0000-0000-0000000000a1"

    // 근무 중에는 스로틀이 없다. 정책이 낡으면 마감 시각이 서버와 갈리고, 복원 창 판정도 함께 늙는다.
    await store.refreshAwayStateIfNeeded(now: start)
    await store.refreshAwayStateIfNeeded(now: start.addingTimeInterval(30))
    #expect(awaySyncRequestCount(host: testHost) == 2)
}

/// away_sync 가 없는 서버(마이그레이션 미적용)에서 이 호출이 폴링을 죽이지 않는다.
/// 죽으면 그 뒤 팀 상태·리그·토큰 보드가 통째로 멈춘다 — 실패는 "모른다"로 접히기만 해야 한다.
@MainActor
@Test
func awaySyncFailureLeavesPollingAliveAndStopsClosing() async {
    let testHost = "schema-missing"
    let store = makePokeGateStore(host: testHost)
    store.startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    store.awayServerSupported = true
    store.awayPolicy = AwayPolicy(
        closeThresholdSeconds: 9_000,
        restoreWindowSeconds: nil,
        dailyRestoreLimit: nil,
        restoresLeftToday: nil,
        serverNow: nil
    )

    await store.refreshAwayStateIfNeeded(now: Date(timeIntervalSince1970: 1_800_000_000))

    // 정책이 비워진다 = 마감이 멈춘다. 그리고 새 컬럼 전송도 함께 꺼진다(그 서버에 보내면 하트비트가 400 이다).
    #expect(store.awayPolicy == nil)
    #expect(!store.awayServerSupported)
    // 폴링의 나머지가 계속 돈다는 증거: 같은 스토어로 이어지는 호출이 그대로 요청을 낸다.
    await store.localExpiryTick()
    #expect(takePokesRequestCount(host: testHost) >= 1)
}

private func awaySyncRequestCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host).filter { $0.url?.path == "/rest/v1/rpc/away_sync" }.count
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

/// 이 카운터가 세려는 것은 '내 공개 설정 1회 로드'다. 별명 쿨타임(display_name_changed_at)도 같은
/// 표를 GET 하므로 경로만 보면 2건이 되어, 검증 대상이 아닌 요청이 단언을 흔든다.
private func tokenPrivacyRequestCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host)
        .filter {
            $0.url?.path == "/rest/v1/profiles" && $0.httpMethod == "GET"
                && $0.url?.query?.contains("token_usage_public") == true
        }
        .count
}
