import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.39 — 맥 미니게임 **제출 인편**의 계약. 재현(수리 전 빨강)은 `V0339MiniGameScoreLossTests` 가 맡고, 이 파일은 수리가
// 더한 장치를 직접 잰다: 인편 대기열의 영속과 수명, "인편이 살아 있는 동안 그 게임의 start_round 는 나가지 않는다"는 불변식,
// status 집합 셋(terminal · retryable · dead)이 **죽은 글자가 아님**, 백오프, 방아쇠 배선, 토큰 없이 끝난 판의 토큰 대기.
//
// 네트워크는 `V0339GateURLProtocol`(재현 파일의 게이트식 스텁 — 토큰 요청·제출을 보류했다가 테스트가 연다)을 그대로 쓴다.
// 시간 단언은 백오프를 `miniGamePendingRetryDelays` 로 줄여서만 한다. UserDefaults 는 전부 `CheckTestScratch` 다.

private let psUserID = "00000000-0000-0000-0000-000000000002"
private let psOtherUserID = "00000000-0000-0000-0000-000000000007"

/// `function` 은 호출한 테스트에서 받아 이어 넘긴다(안 넘기면 스위트 이름이 이 헬퍼로 굳어 전부 한 스위트다).
@MainActor
private func psStore(host: String, defaults: UserDefaults? = nil, function: String = #function) -> WorkTimerStore {
    V0339GateURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: V0339GateURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults ?? CheckTestScratch.defaults(host, function: function)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: psUserID)
    store.miniGameKind = .flappy
    return store
}

@MainActor
private func psArm(_ store: WorkTimerStore, token: String, kind: MiniGameKind = .flappy) {
    store.miniGameRoundToken = token
    store.miniGameRoundTokenKind = kind
    store.miniGameRoundTokenAt = Date()
}

@MainActor
private func psWait(upTo seconds: Double = 3, until condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
private func psSettle(_ seconds: Double = 0.3) async {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
}

private func psHeld(_ host: String, _ containing: String) -> Int {
    V0339GateURLProtocol.heldCount(host: host, containing: containing)
}

private func psCount(_ host: String, _ containing: String) -> Int {
    V0339GateURLProtocol.count(host: host, containing: containing)
}

private func psTokens(_ host: String) -> [String] {
    V0339GateURLProtocol.bodies(host: host, containing: "minigame_submit_score").compactMap { $0["p_token"] as? String }
}

private let psOK = #"{"status":"ok","best_score":3,"plays":1,"improved":true}"#
private func psStatus(_ status: String) -> String { #"{"status":"\#(status)"}"# }
private func psToken(_ token: String) -> String { #"{"status":"ok","token":"\#(token)"}"# }

// MARK: - 영속 · 수명

/// 맥 사용자는 앱을 자주 끄고 켠다 — 종료가 점수를 삼키면 안 된다. 인편은 `defaults` 에 계정별로 남고, 새 스토어가
/// 같은 토큰으로 이어서 보낸다(같은 토큰이라 두 번 올라가지 않는다 — 서버가 `token_used`).
@MainActor
@Test("인편은 재시작을 살아남아 같은 토큰으로 다시 나간다")
func pendingSubmitsSurviveARestartAndResendWithTheSameToken() async {
    let defaults = CheckTestScratch.defaults()
    let first = "v0339-ps-restart-1"
    let store = psStore(host: first, defaults: defaults)
    store.miniGamePendingRetryDelays = [60]   // 첫 스토어의 백오프가 이 테스트 안에서 끼어들지 않게
    psArm(store, token: "tok-A")
    store.recordMiniGameScore(kind: .flappy, score: 11)
    #expect(await psWait { psHeld(first, "minigame_submit_score") == 1 }, "전제: 제출이 나갔다")
    V0339GateURLProtocol.fail(host: first, containing: "minigame_submit_score")
    #expect(await psWait { store.miniGameSubmitNotice == MiniGameSubmitCopy.pending }, "네트워크 실패 뒤 문구가 '올리는 중'이 아니다")
    #expect(store.miniGamePendingSubmits.map(\.token) == ["tok-A"], "인편이 토큰과 함께 남지 않았다")
    #expect(defaults.data(forKey: WorkTimerStore.miniGamePendingKey(userID: psUserID)) != nil, "인편이 defaults 에 없다 — 종료가 점수를 삼킨다")

    // 재시작: 같은 defaults · 같은 계정의 새 스토어. 인편은 게으르게 읽는다 — 물어보는 순간 그 계정의 키에서 온다.
    let second = "v0339-ps-restart-2"
    let restarted = psStore(host: second, defaults: defaults)
    #expect(restarted.hasMiniGamePendingSubmit(for: .flappy), "재시작한 스토어가 인편을 못 읽었다")
    restarted.retryMiniGamePendingSubmitIfAny()
    #expect(await psWait { psHeld(second, "minigame_submit_score") == 1 }, "재시작 뒤 인편이 나가지 않았다")
    #expect(psTokens(second) == ["tok-A"], "재시작 뒤 다른 토큰으로 나갔다 — 같은 토큰이어야 멱등이다")
    #expect(psCount(second, "minigame_start_round") == 0, "인편이 살아 있는데 start_round 가 먼저 나갔다 — 서버에서 tok-A 가 죽는다")

    V0339GateURLProtocol.release(host: second, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { restarted.miniGamePendingSubmits.isEmpty }, "성공했는데 인편이 남아 있다")
    #expect(defaults.data(forKey: WorkTimerStore.miniGamePendingKey(userID: psUserID)) == nil, "성공 뒤 defaults 의 인편이 안 지워졌다")
    #expect(restarted.miniGameSubmitNotice == nil)
}

/// 30분(서버 토큰 TTL)을 넘긴 인편은 토큰이 죽었으므로 읽을 때 버린다 — 토큰이 없는 인편도 같은 수명이다
/// (더 늦으면 다른 날 순위표에 올라간다).
@MainActor
@Test("TTL 을 넘긴 인편은 읽을 때 버려지고, 아직 산 인편만 나간다")
func aPendingSubmitOlderThanTheTokenTTLIsDroppedOnLoad() async throws {
    let defaults = CheckTestScratch.defaults()
    let stale = Date().addingTimeInterval(-(WorkTimerStore.miniGamePendingSubmitTTL + 60))
    let entries = [
        MiniGamePendingSubmit(id: UUID(), kind: .flappy, score: 5, token: "tok-old", tokenIssuedAt: stale, recordedAt: stale, attempts: 2),
        // 토큰이 없어도 판이 끝난 지 30분이 지났으면 버린다.
        MiniGamePendingSubmit(id: UUID(), kind: .flappy, score: 6, token: nil, tokenIssuedAt: nil, recordedAt: stale, attempts: 0),
        MiniGamePendingSubmit(id: UUID(), kind: .flappy, score: 7, token: "tok-new", tokenIssuedAt: Date(), recordedAt: Date(), attempts: 0),
    ]
    defaults.set(try JSONEncoder().encode(entries), forKey: WorkTimerStore.miniGamePendingKey(userID: psUserID))

    let host = "v0339-ps-ttl"
    let store = psStore(host: host, defaults: defaults)
    store.retryMiniGamePendingSubmitIfAny()
    #expect(store.miniGamePendingSubmits.map(\.score) == [7], Comment(rawValue: "TTL 을 넘긴 인편이 남았다 — \(store.miniGamePendingSubmits.map(\.score))"))
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 }, "산 인편이 나가지 않았다")
    #expect(psTokens(host) == ["tok-new"], "죽은 토큰으로 제출이 나갔다")
    // 영속본도 정리됐다.
    let saved = try JSONDecoder().decode([MiniGamePendingSubmit].self,
                                         from: try #require(defaults.data(forKey: WorkTimerStore.miniGamePendingKey(userID: psUserID))))
    #expect(saved.map(\.score) == [7])
}

/// 로그아웃은 메모리의 인편만 비운다 — 영속본은 그 계정의 키에 남아 같은 사람이 돌아오면 이어지고, 다른 계정에는 안 보인다.
@MainActor
@Test("로그아웃 뒤 인편은 같은 계정에만 다시 보인다")
func signOutKeepsThePersistedPendingForTheSameAccountOnly() async {
    let host = "v0339-ps-signout"
    let store = psStore(host: host)
    store.miniGamePendingRetryDelays = [60]
    psArm(store, token: "tok-A")
    store.recordMiniGameScore(kind: .flappy, score: 3)
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 })
    V0339GateURLProtocol.fail(host: host, containing: "minigame_submit_score")
    #expect(await psWait { store.miniGamePendingSubmits.count == 1 })

    store.signOut()
    #expect(store.miniGamePendingSubmits.isEmpty, "로그아웃했는데 메모리에 앞 사람의 인편이 남았다")
    #expect(store.defaults.data(forKey: WorkTimerStore.miniGamePendingKey(userID: psUserID)) != nil, "로그아웃이 영속 인편을 지웠다 — 돌아온 사람의 점수가 사라진다")

    store.session = SupabaseSession(accessToken: "t2", refreshToken: nil, userID: psOtherUserID)
    #expect(!store.hasMiniGamePendingSubmit(for: .flappy), "다른 계정에 앞 사람의 인편이 보인다 — 남의 점수를 내 이름으로 올린다")
    store.session = SupabaseSession(accessToken: "t3", refreshToken: nil, userID: psUserID)
    #expect(store.hasMiniGamePendingSubmit(for: .flappy), "같은 계정으로 돌아왔는데 인편이 안 보인다")
}

// MARK: - 불변식: 인편이 살아 있는 동안 그 게임의 start_round 는 나가지 않는다

/// 서버 `minigame_start_round` 는 `(user_id, game)` 의 미사용 행을 갈아 끼운다 — 새 토큰을 받으면 인편이 든 토큰이 죽는다.
/// 그래서 선발급·판 시작·인편 밀기 어느 방아쇠도 인편이 살아 있는 동안은 그 게임의 토큰을 청하지 않는다. 다른 게임은 무관하다.
@MainActor
@Test("인편이 든 게임의 start_round 는 어떤 방아쇠에서도 먼저 나가지 않는다")
func noStartRoundLeavesForAGameWhoseSubmitIsStillPending() async {
    let host = "v0339-ps-invariant"
    let store = psStore(host: host)
    store.miniGamePendingRetryDelays = [0.05]
    psArm(store, token: "tok-A")
    store.recordMiniGameScore(kind: .flappy, score: 13)
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 })
    V0339GateURLProtocol.fail(host: host, containing: "minigame_submit_score")
    // 백오프(0.05s) 재시도가 나가 있는 상태에서 방아쇠를 전부 당긴다.
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 && psCount(host, "minigame_submit_score") == 2 },
            "백오프 재시도가 안 나갔다")
    store.prefetchMiniGameRoundToken(kind: .flappy)
    store.beginMiniGameRound(kind: .flappy)
    store.retryMiniGamePendingSubmitIfAny()
    store.handleWake()
    await psSettle()
    #expect(psCount(host, "minigame_start_round") == 0,
            Comment(rawValue: "인편이 살아 있는데 start_round 가 \(psCount(host, "minigame_start_round"))건 나갔다 — 서버가 tok-A 를 갈아 끼운다"))
    #expect(Set(psTokens(host)) == ["tok-A"], "재시도가 다른 토큰으로 나갔다")

    // 다른 게임은 막히지 않는다(서버 행이 게임별이다).
    store.prefetchMiniGameRoundToken(kind: .timingBar)
    #expect(await psWait { psCount(host, "minigame_start_round") == 1 }, "다른 게임의 선발급까지 막혔다")
    let games = V0339GateURLProtocol.bodies(host: host, containing: "minigame_start_round").compactMap { $0["p_game"] as? String }
    #expect(games == ["timing_bar"], Comment(rawValue: "\(games)"))

    // 인편이 비워지면 그제야 그 게임의 선발급이 나간다.
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { store.miniGamePendingSubmits.isEmpty })
    let flappyStarts = await psWait {
        V0339GateURLProtocol.bodies(host: host, containing: "minigame_start_round").contains { ($0["p_game"] as? String) == "flappy" }
    }
    #expect(flappyStarts, "인편이 비었는데 다음 판 토큰을 미리 받지 않는다")
}

/// 토큰을 기다리는 인편이 둘이면 **순서대로** 토큰을 받는다 — 앞 것이 성공하기 전에는 뒤 것의 토큰을 청하지 않는다
/// (청하면 앞 것의 토큰이 죽는다). 도착한 토큰은 살아 있는 판이 아니라 기다리던 점수가 먼저 가져간다.
@MainActor
@Test("토큰을 기다리는 인편들은 순서대로 토큰을 받아 나간다")
func waitingScoresTakeArrivingTokensInOrder() async {
    let host = "v0339-ps-fifo"
    let store = psStore(host: host)
    store.beginMiniGameRound(kind: .flappy)
    #expect(await psWait { psHeld(host, "minigame_start_round") == 1 }, "전제: 판 시작이 토큰을 청했다")
    // 즉사 둘 — 둘 다 토큰 없이 끝난다.
    store.recordMiniGameScore(kind: .flappy, score: 4)
    store.recordMiniGameScore(kind: .flappy, score: 6)
    await psSettle(0.1)
    #expect(store.miniGamePendingSubmits.map(\.score) == [4, 6])
    #expect(psCount(host, "minigame_start_round") == 1, "기다리는 인편마다 토큰을 청했다 — 서로의 토큰을 죽인다")

    V0339GateURLProtocol.release(host: host, containing: "minigame_start_round", json: psToken("tok-1"))
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 }, "도착한 토큰으로 앞 인편이 나가지 않았다")
    #expect(V0339GateURLProtocol.bodies(host: host, containing: "minigame_submit_score").first?["p_score"] as? Int == 4)
    #expect(store.miniGameRoundToken == nil, "기다리는 점수가 있는데 토큰이 살아 있는 판 슬롯으로 갔다")
    await psSettle(0.1)
    #expect(psCount(host, "minigame_start_round") == 1, "앞 인편이 끝나기 전에 뒤 인편의 토큰을 청했다")

    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { psHeld(host, "minigame_start_round") == 1 }, "앞 인편이 끝났는데 뒤 인편의 토큰을 청하지 않는다")
    V0339GateURLProtocol.release(host: host, containing: "minigame_start_round", json: psToken("tok-2"))
    #expect(await psWait { psTokens(host) == ["tok-1", "tok-2"] }, Comment(rawValue: "\(psTokens(host))"))
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { store.miniGamePendingSubmits.isEmpty })
}

/// 토큰도 없고 왕복도 없이 끝난 판(선발급이 실패해 있던 오프라인 판). 점수는 인편으로 남고, 토큰 요청이 실패하면 백오프 뒤
/// 다시 청해서 결국 올라간다.
@MainActor
@Test("토큰도 왕복도 없이 끝난 판은 토큰을 기다렸다가 올라간다")
func aRoundThatEndsWithNoTokenAndNoRequestInFlightStillGetsUploaded() async {
    let host = "v0339-ps-offline"
    let store = psStore(host: host)
    store.miniGamePendingRetryDelays = [0.05]
    store.recordMiniGameScore(kind: .flappy, score: 8)
    #expect(store.miniGameSubmitNotice == MiniGameSubmitCopy.pending, "토큰 없는 판의 문구가 '올리는 중'이 아니다")
    #expect(await psWait { psHeld(host, "minigame_start_round") == 1 }, "기다리는 점수를 위해 토큰을 청하지 않는다")
    V0339GateURLProtocol.fail(host: host, containing: "minigame_start_round")
    #expect(await psWait { psCount(host, "minigame_start_round") == 2 }, "토큰 요청이 실패했는데 다시 청하지 않는다")
    V0339GateURLProtocol.release(host: host, containing: "minigame_start_round", json: psToken("tok-Z"))
    #expect(await psWait { psTokens(host) == ["tok-Z"] }, "도착한 토큰으로 점수가 나가지 않았다")
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { store.miniGamePendingSubmits.isEmpty && store.miniGameSubmitNotice == nil })
}

// MARK: - status 집합은 죽은 글자가 아니다

/// 두 집합은 서로소여야 한다. 코드는 terminal 을 먼저 보므로 `too_fast` 를 terminal 에 되돌려 놓으면 **지워진다** —
/// 그 순간 아래 백오프 테스트가 빨개지고, 이 단언은 그 사고를 이름으로 잡는다(폰에서 실측한 함정: 재시도 갈래를 먼저 보면
/// 등재가 아무것도 안 하는 글자가 되고 다음 사람이 그걸 읽고 틀리게 믿는다).
@Test("재시도 status 와 terminal status 는 서로소이고, 죽은 토큰 status 는 terminal 의 부분집합이다")
func retryableAndTerminalStatusesMustStayDisjoint() {
    let terminal = WorkTimerStore.miniGameTerminalSubmitStatuses
    let retryable = WorkTimerStore.miniGameRetryableSubmitStatuses
    let dead = WorkTimerStore.miniGameDeadTokenStatuses
    #expect(terminal.isDisjoint(with: retryable), Comment(rawValue: "겹친다 — \(terminal.intersection(retryable))"))
    #expect(dead.isSubset(of: terminal), "죽은 토큰인데 terminal 이 아니면 '영영 못 올린다'고 말하면서 계속 다시 보낸다")
    #expect(retryable.contains("too_fast"), "too_fast 가 재시도 대상이 아니다 — 경과는 자라기만 하는데 점수를 버린다")
    #expect(!terminal.contains("too_fast") && !terminal.contains("token_used") && !terminal.contains("ok"))
    #expect(terminal == ["invalid", "no_token", "token_expired", "unauthorized", "no_profile"], Comment(rawValue: "\(terminal.sorted())"))
    #expect(dead == ["no_token", "token_expired"])
}

/// `too_fast` 는 토큰을 소모하기 전에 돌아오고 경과는 단조증가다 — 같은 토큰으로 백오프 뒤 다시 보내면 통과한다.
/// (뮤테이션 검증: `too_fast` 를 terminal 에 넣으면 지워져 재시도가 없고, retryable 에서 빼면 타이머가 안 걸린다 — 둘 다 여기서 빨개진다.)
@MainActor
@Test("too_fast 는 같은 토큰으로 백오프 뒤 다시 나간다")
func tooFastIsResentWithTheSameTokenAfterTheBackoff() async {
    let host = "v0339-ps-too-fast"
    let store = psStore(host: host)
    store.miniGamePendingRetryDelays = [0.05]
    psArm(store, token: "tok-A")
    store.recordMiniGameScore(kind: .flappy, score: 29)
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 })
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score",
                                 json: #"{"status":"too_fast","need_seconds":10,"elapsed_seconds":1.2}"#)
    #expect(await psWait(upTo: 1) { psCount(host, "minigame_submit_score") == 2 }, "백오프 재시도가 안 나갔다 — too_fast 로 점수를 버렸다")
    #expect(psTokens(host) == ["tok-A", "tok-A"], Comment(rawValue: "다른 토큰으로 나갔다 — \(psTokens(host))"))
    #expect(store.miniGameSubmitNotice == MiniGameSubmitCopy.pending, Comment(rawValue: "too_fast 뒤 문구가 '못 올렸어요'다 — \(store.miniGameSubmitNotice ?? "nil")"))
    #expect(psCount(host, "minigame_start_round") == 0, "too_fast 뒤 새 토큰을 청했다 — 살아 있던 토큰이 서버에서 죽는다")
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { store.miniGamePendingSubmits.isEmpty && store.miniGameSubmitNotice == nil })
}

/// terminal 다섯은 저마다 인편을 지우고, 문장이 갈린다: 토큰 만료만 이유를 밝히고, 토큰이 죽은 거절은 "다음 판부터"를,
/// 나머지는 이유 없이 "못 올렸어요"를 말한다. 지운 뒤에는 다음 판 토큰을 미리 받는다.
/// (뮤테이션 검증: terminal 에서 하나를 빼면 그 status 는 "모르는 status"가 되어 지워지지 않는다 — 여기서 빨개진다.)
@MainActor
@Test("terminal 거절은 인편을 지우고 status 에 맞는 문장을 말한다")
func everyTerminalStatusDropsThePendingAndSaysSo() async {
    // ⚠️ `no_token` 은 여기 없다 — **첫 번은 되살린다**(2026-09-27 실사용 신고: 잃은 여섯 판이 전부 `no_token` 이었고
    //    원인은 제출과 `start_round` 의 경합이라 점수 자체는 진짜였다). 그래서 "첫 번은 새 토큰으로 되살리고 두 번째는
    //    놓아 준다"는 계약을 전용 테스트 둘이 잰다: `aDeadTokenIsRecoveredOnceWithAFreshToken` ·
    //    `aDeadTokenIsNotRecoveredTwice`. terminal 집합의 **등재**는 그대로다(두 번째에 그 자리로 간다).
    let expectations: [(status: String, notice: String)] = [
        ("invalid", MiniGameSubmitCopy.refused),
        ("token_expired", MiniGameSubmitCopy.tokenExpired),
        ("unauthorized", MiniGameSubmitCopy.refused),
        ("no_profile", MiniGameSubmitCopy.refused),
    ]
    for (status, notice) in expectations {
        let host = "v0339-ps-terminal-\(status.replacingOccurrences(of: "_", with: "-"))"
        let store = psStore(host: host)
        store.miniGamePendingRetryDelays = [0.05]
        psArm(store, token: "tok-A")
        store.recordMiniGameScore(kind: .flappy, score: 21)
        #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 }, Comment(rawValue: "\(status): 전제"))
        V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psStatus(status))
        #expect(await psWait { store.miniGamePendingSubmits.isEmpty }, Comment(rawValue: "\(status): 인편이 안 지워졌다 — 영영 못 올릴 토큰으로 계속 보낸다"))
        #expect(store.miniGameSubmitNotice == notice, Comment(rawValue: "\(status): 문구가 \(store.miniGameSubmitNotice ?? "nil")"))
        #expect(await psWait { psCount(host, "minigame_start_round") == 1 }, Comment(rawValue: "\(status): 인편을 지운 뒤 다음 판 토큰을 안 받는다"))
        await psSettle(0.2)
        #expect(psCount(host, "minigame_submit_score") == 1, Comment(rawValue: "\(status): 지운 인편을 다시 보냈다"))
    }
}

/// 모르는 status(신버전 서버): 점수는 남기되(버리지 않는다) 두드리지는 않는다 — 타이머 없이 방아쇠에서만 다시 보낸다.
@MainActor
@Test("모르는 status 는 인편을 남기되 타이머로 두드리지 않고, 방아쇠에서만 다시 나간다")
func anUnknownStatusKeepsTheScoreButDoesNotHammer() async {
    let host = "v0339-ps-unknown"
    let store = psStore(host: host)
    store.miniGamePendingRetryDelays = [0.05]
    psArm(store, token: "tok-A")
    store.recordMiniGameScore(kind: .flappy, score: 17)
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 })
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psStatus("banana"))
    #expect(await psWait { store.miniGameSubmitNotice == MiniGameSubmitCopy.pending })
    await psSettle(0.4)
    #expect(store.miniGamePendingSubmits.map(\.token) == ["tok-A"], "모르는 status 에 점수를 버렸다")
    #expect(psCount(host, "minigame_submit_score") == 1, "모르는 status 를 타이머로 두드린다")
    #expect(psCount(host, "minigame_start_round") == 0)
    store.retryMiniGamePendingSubmitIfAny()
    #expect(await psWait { psCount(host, "minigame_submit_score") == 2 }, "방아쇠에서도 다시 안 나간다 — TTL 안에 닿을 길이 없다")
    #expect(psTokens(host) == ["tok-A", "tok-A"])
}

/// 세대가 밀린 응답은 상태를 안 건드리지만 인편은 남는다. 세션이 그대로면(테스트에서만 가능한 조합) 즉시 한 번 다시 밀고,
/// 실사용(세션 nil)에서는 그 밀기가 no-op 이라 디스크의 인편이 다음 로그인을 기다린다.
@MainActor
@Test("세대가 밀린 응답은 최고를 안 건드리고 인편을 남긴다")
func aSkewedGenerationResponseLeavesThePendingAndTheBestAlone() async {
    let host = "v0339-ps-skew"
    let store = psStore(host: host)
    store.miniGamePendingRetryDelays = [60]
    psArm(store, token: "tok-A")
    store.recordMiniGameScore(kind: .flappy, score: 9)
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 })
    store.sessionGeneration += 1
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: #"{"status":"ok","best_score":99}"#)
    #expect(await psWait { psCount(host, "minigame_submit_score") == 2 }, "세션이 그대로인데 인편을 다시 밀지 않았다")
    #expect(store.miniGameBest(.flappy) == 9, "세대가 밀린 응답의 best_score 를 로컬에 썼다")
    #expect(store.miniGamePendingSubmits.map(\.token) == ["tok-A"])

    // 세션이 nil 이면(실사용의 세대 밀림 = 로그아웃) 밀기는 no-op 이다.
    store.sessionGeneration += 1
    store.session = nil
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    await psSettle(0.2)
    #expect(psCount(host, "minigame_submit_score") == 2, "세션이 없는데 제출이 나갔다")
}

// MARK: - 방아쇠 배선(소스 계약)

/// 다섯 방아쇠 가운데 소스로만 확인할 수 있는 셋 — 깨어남(`handleWake`) · 앱 재활성화(`AppDelegate`) · 창 열기 — 과,
/// 선발급·판 시작이 요청 **앞에서** 인편을 미는지(불변식의 배선). 행동 테스트는 방아쇠를 직접 당기므로 배선 누락을 못 잡는다.
@Test("인편 재시도 방아쇠가 깨어남·재활성화·창 열기에 배선돼 있고, 선발급·판 시작은 요청보다 먼저 인편을 민다")
func pendingRetryTriggersAreWired() throws {
    let store = psStripped(try psSource("Sources/check/WorkTimerStore.swift"))
    let wake = try #require(psFunctionBody(store, name: "handleWake"))
    #expect(wake.contains("retryMiniGamePendingSubmitIfAny()"), "깨어날 때 인편을 안 민다")

    let app = psStripped(try psSource("Sources/check/CheckApp.swift"))
    let active = try #require(psFunctionBody(app, name: "applicationDidBecomeActive"), "AppDelegate 에 applicationDidBecomeActive 가 없다")
    #expect(active.contains("store.retryMiniGamePendingSubmitIfAny()"), "앱이 다시 활성화될 때 인편을 안 민다")

    let game = psStripped(try psSource("Sources/check/WorkTimerStoreMiniGame.swift"))
    let open = try #require(psFunctionBody(game, name: "openMiniGameWindow"))
    #expect(open.contains("retryMiniGamePendingSubmitIfAny()"), "창을 열 때 인편을 안 민다")
    for name in ["prefetchMiniGameRoundToken", "beginMiniGameRound"] {
        let body = try #require(psFunctionBody(game, name: name))
        let push = try #require(body.range(of: "retryMiniGamePendingSubmitIfAny()"), Comment(rawValue: "\(name) 이 인편을 안 민다"))
        let request = try #require(body.range(of: "requestMiniGameRoundToken(kind: kind)"), Comment(rawValue: "\(name) 이 토큰을 안 청한다"))
        #expect(push.lowerBound < request.lowerBound, Comment(rawValue: "\(name) 이 인편보다 토큰 요청을 먼저 한다 — 인편의 토큰이 서버에서 죽는다"))
    }
    // 세대 밀림 가드는 **지우지 않는다**(계정 전환 방어). 두 가드(do · catch) 모두 남아 있어야 한다.
    let submit = try #require(psFunctionBody(game, name: "performSubmitMiniGameScore"))
    #expect(submit.components(separatedBy: "guard generation == sessionGeneration else {").count - 1 == 2,
            "제출의 세대 가드가 둘이 아니다 — 계정 전환 뒤 앞 사람의 응답이 새 사람의 상태를 만진다")
}

// MARK: - 소스 읽기 헬퍼(다른 파일의 것은 private)

private func psSource(_ relative: String) throws -> String {
    try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent(relative), encoding: .utf8)
}

/// 주석을 걷어내고 공백을 접는다(주석에 든 이름 때문에 설명을 지워야만 초록이 되는 테스트를 만들지 않게).
private func psStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func psFunctionBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "func \(name)("),
          let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex) else { return nil }
    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[open.upperBound..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

// MARK: 죽은 토큰 한 번 되살리기 · 닫힌 창 손실 통지 (2026-09-27 실사용 신고 뒤 더한 둘)
//
// 실사용에서 잃은 여섯 판은 전부 `no_token` 이었다(플래피 · 90분 · 네트워크 실패 0 · too_fast 0). 서버 행이 원인을 말했다:
// `used_at` 이 다음 행의 `started_at` 과 같은 정상 흐름 사이에, **제출과 `start_round` 가 같은 초에 날아가 `start_round` 가
// 먼저 닿은 순간**에만 `no_token` 이 찍혔다. 불변식이 그 경합을 막지만, 뚫렸을 때도 점수를 버리지 않는 것이 이 둘이다.

@MainActor
@Test("no_token 을 받아도 점수를 버리지 않고 새 토큰으로 한 번 다시 올린다")
func aDeadTokenIsRecoveredOnceWithAFreshToken() async {
    let host = "v0339-dead-token-recovered"
    let store = psStore(host: host)
    psArm(store, token: "tok-dead")

    store.recordMiniGameScore(kind: .flappy, score: 13)
    #expect(await psWait { psHeld(host, "minigame_submit_score") > 0 }, "제출이 안 나갔다")
    // 서버가 "그 토큰 모른다"고 한다 — 그 사이 start_round 가 행의 id 를 갈아 끼운 경우다.
    _ = V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score",
                                     json: #"{"status":"no_token"}"#)

    // 점수는 남고, 토큰을 기다리는 인편이 되어 **새 토큰을 청한다**.
    #expect(await psWait { psHeld(host, "minigame_start_round") > 0 },
            "죽은 토큰을 받고도 새 토큰을 청하지 않았다 — 점수를 버렸다")
    #expect(store.miniGamePendingSubmits.contains { $0.score == 13 }, "인편이 사라졌다")
    #expect(store.miniGameSubmitNotice == MiniGameSubmitCopy.pending,
            "아직 올릴 수 있는데 못 올렸다고 말했다 — \(store.miniGameSubmitNotice ?? "nil")")

    _ = V0339GateURLProtocol.release(host: host, containing: "minigame_start_round", json: psToken("tok-fresh"))
    #expect(await psWait { psTokens(host).contains("tok-fresh") },
            "새 토큰으로 다시 보내지 않았다 — 보낸 토큰 \(psTokens(host))")
    _ = V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { store.miniGamePendingSubmits.isEmpty }, "성공했는데 인편이 남았다")
    #expect(store.miniGameSubmitNotice == nil, "올라갔는데 문구가 남았다")
}

@MainActor
@Test("죽은 토큰 되살리기는 한 번뿐이다 — 두 번째 no_token 은 인편을 놓아 준다")
func aDeadTokenIsNotRecoveredTwice() async {
    let host = "v0339-dead-token-once"
    let store = psStore(host: host)
    psArm(store, token: "tok-dead-1")

    store.recordMiniGameScore(kind: .flappy, score: 9)
    #expect(await psWait { psHeld(host, "minigame_submit_score") > 0 })
    _ = V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score",
                                     json: #"{"status":"no_token"}"#)
    #expect(await psWait { psHeld(host, "minigame_start_round") > 0 }, "첫 되살리기가 안 일어났다")
    _ = V0339GateURLProtocol.release(host: host, containing: "minigame_start_round", json: psToken("tok-dead-2"))
    #expect(await psWait { psHeld(host, "minigame_submit_score") > 0 }, "새 토큰으로 안 보냈다")

    // 두 번째도 no_token — 원인이 경합이 아니므로 두드려도 같은 답이다. 무한 왕복이 되지 않게 놓아 준다.
    _ = V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score",
                                     json: #"{"status":"no_token"}"#)
    #expect(await psWait { store.miniGamePendingSubmits.isEmpty },
            "두 번째 no_token 에도 인편을 붙들었다 — 그 게임의 선발급이 영영 막힌다")
    #expect(store.miniGameSubmitNotice == MiniGameSubmitCopy.tokenDead,
            "못 올렸다고 말하지 않았다 — \(store.miniGameSubmitNotice ?? "nil")")
}

@MainActor
@Test("창을 닫아 둔 사이에 죽은 점수는 다음에 창을 열 때 말한다")
func aScoreLostWhileTheWindowWasClosedIsToldOnTheNextOpen() async throws {
    let host = "v0339-lost-while-closed"
    let shared = CheckTestScratch.defaults(host)

    // TTL 을 넘긴 인편을 **디스크에 심어** 둔다(시간을 기다리지 않고, 영속 경로를 실제로 지나간다).
    let stale = MiniGamePendingSubmit(
        id: UUID(), kind: .flappy, score: 21, token: "tok-long-dead",
        tokenIssuedAt: Date().addingTimeInterval(-(WorkTimerStore.miniGamePendingSubmitTTL + 60)),
        recordedAt: Date().addingTimeInterval(-(WorkTimerStore.miniGamePendingSubmitTTL + 60)),
        attempts: 3)
    shared.set(try JSONEncoder().encode([stale]),
               forKey: WorkTimerStore.miniGamePendingKey(userID: psUserID))

    // 창이 닫힌 채로 앱이 켜진다 — 읽는 순간 버려진다.
    let store = psStore(host: host, defaults: shared)
    store.isMiniGamePanelVisible = false
    store.loadMiniGamePendingSubmitsIfNeeded()
    #expect(store.miniGamePendingSubmits.isEmpty, "TTL 을 넘긴 인편이 안 버려졌다")
    // 창이 닫혀 있었으니 **그 자리에서는 말하지 않는다** — 볼 화면이 없다.
    #expect(store.miniGameSubmitNotice != MiniGameSubmitCopy.expired, "닫힌 창에 문구를 세웠다")
    #expect(shared.bool(forKey: WorkTimerStore.miniGameLostNoticeKey(userID: psUserID)),
            "표식을 안 남겼다 — 사용자는 점수가 사라진 것을 영영 모른다")

    // 다음에 창을 열면 한 번 말하고, 표식이 지워져 두 번 말하지 않는다.
    store.showMiniGameLostNoticeIfAny()
    #expect(store.miniGameSubmitNotice == MiniGameSubmitCopy.expired,
            "창을 열어도 사라진 점수를 말하지 않았다")
    store.miniGameSubmitNotice = nil
    store.showMiniGameLostNoticeIfAny()
    #expect(store.miniGameSubmitNotice == nil, "같은 손실을 두 번 말했다")
}

// MARK: 실사용에서 잃은 순서 그대로 (2026-09-27 신고 · 플래피 13점)
//
// 서버 행과 앱 로그를 맞춰 얻은 순서다. `used_at` 이 다음 행의 `started_at` 과 같은 정상 흐름 사이에, **`no_token` 이 찍힌
// 초에는 같은 초에 `start_round` 도 돌았다.** 0.3.38 에서 그 자리는 하나뿐이다: `recordMiniGameScore` 가 토큰을 비우고
// 제출을 띄운 직후 사용자가 결과 카드를 눌러 `beginMiniGameRound` 가 토큰을 새로 청하고, 그 `start_round` 가 제출보다
// 먼저 DB 에 닿아 제출이 든 토큰을 갈아 끼운다. 여섯 판이 전부 이것이었다(네트워크 실패 0 · too_fast 0).
//
// 이 테스트가 재는 것은 **근본 수리 하나**다: 제출이 왕복 중인 동안 그 게임의 start_round 는 한 건도 나가지 않는다.
// 되살리기(no_token 한 번)는 이 순서를 못 막는 경우(다른 기기가 같은 계정으로 토큰을 청하는 경우)의 보험일 뿐이고,
// 이 테스트가 빨개지면 보험이 매번 동작하는 상태 = 사용자가 매 판 수십 초를 기다리는 상태다.

@MainActor
@Test("죽자마자 다시 시작해도 앞 판의 토큰이 죽지 않는다 — 실사용에서 13점을 잃은 순서")
func clickingReplayTheInstantYouDieNeverKillsThePreviousRoundsToken() async {
    let host = "v0339-replay-instant"
    let store = psStore(host: host)
    psArm(store, token: "tok-round-A")

    // 판 A 가 끝난다(플래피 13점) — 제출이 왕복에 들어간다.
    store.recordMiniGameScore(kind: .flappy, score: 13)
    #expect(await psWait { psHeld(host, "minigame_submit_score") == 1 }, "제출이 안 나갔다")

    // ★ 결과 카드를 **곧바로** 누른다(판 B 시작). 0.3.38 은 여기서 start_round 를 내 tok-round-A 를 죽였다.
    store.beginMiniGameRound(kind: .flappy)
    await psSettle()
    #expect(psCount(host, "minigame_start_round") == 0,
            Comment(rawValue: "제출이 왕복 중인데 start_round 가 \(psCount(host, "minigame_start_round"))건 나갔다 — 서버가 tok-round-A 를 갈아 끼워 13점이 no_token 으로 죽는다"))
    #expect(psTokens(host) == ["tok-round-A"], Comment(rawValue: "제출이 든 토큰이 바뀌었다 — \(psTokens(host))"))

    // 판 A 의 제출이 그제야 서버에 닿는다. 살아 있는 토큰이라 ok 다.
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { store.miniGamePendingSubmits.isEmpty }, "13점이 안 올라갔다")
    #expect(store.miniGameSubmitNotice == nil, Comment(rawValue: "올라갔는데 문구가 남았다 — \(store.miniGameSubmitNotice ?? "nil")"))

    // 판 B 는 토큰 없이 시작됐다 — 그 점수도 버려지지 않는다(인편이 토큰을 기다렸다 올린다).
    #expect(await psWait { psHeld(host, "minigame_start_round") == 1 }, "판 A 가 끝났는데 다음 토큰을 안 받는다")
    store.recordMiniGameScore(kind: .flappy, score: 20)
    V0339GateURLProtocol.release(host: host, containing: "minigame_start_round", json: psToken("tok-round-B"))
    #expect(await psWait { psTokens(host).contains("tok-round-B") },
            Comment(rawValue: "토큰 없이 끝난 판 B 의 20점이 안 나갔다 — 보낸 토큰 \(psTokens(host))"))
    V0339GateURLProtocol.release(host: host, containing: "minigame_submit_score", json: psOK)
    #expect(await psWait { store.miniGamePendingSubmits.isEmpty }, "판 B 점수가 인편에 남았다")
}
