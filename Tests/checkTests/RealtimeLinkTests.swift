import Foundation
import SwiftUI
import Testing
@testable import check

// 초인종(Supabase Realtime Broadcast) 테스트.
//
// ── 이 파일이 소켓을 한 개도 열지 않는 이유 ──
// 이 저장소는 스텁 주입을 잊은 테스트가 실네트워크로 새어 나가 188초 걸리는 플레이키를 이미 겪었다
// (drainKeepsUltraPathUntouched). 그 구조적 원인은 **기본값이 라이브**라는 것이었다.
// 여기서는 정반대로 만든다: `WorkTimerStore(realtimeTransport:)` 의 기본값이 nil 이고,
// `LiveRealtimeTransport.init?` 는 테스트 프로세스에서 nil 을 돌려준다. 그래서 이 파일의 모든 테스트는
// ① 순수 상태머신(`RealtimeLink.apply`)을 동기 호출하거나 ② 아래 FakeRealtimeTransport 를 주입한다.
// **벽시계 대기가 한 곳도 없다** — 링이 시각을 인자로 받기 때문이다.

// MARK: - 도구

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// 지터를 상한 그대로 돌려주는 결정적 주입값. 분산 테스트만 실난수를 쓴다.
private let ceilingJitter: @Sendable (Double) -> Double = { $0 }

@discardableResult
private func apply(
    _ link: inout RealtimeLink,
    _ event: RealtimeEvent,
    _ now: Date,
    jitter: (Double) -> Double = ceilingJitter
) -> [RealtimeEffect] {
    link.apply(event, now: now, jitter: jitter)
}

/// 구독까지 올려놓은 링. 테스트마다 같은 4줄을 베끼지 않게 한 곳에 둔다.
private func subscribedLink(token: String = "tok-a", at now: Date = t0) -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    apply(&link, .signedIn(accessToken: token), now)
    apply(&link, .transport(.joined), now)
    return link
}

/// 테스트용 전송자. **스스로 아무 일도 하지 않는다** — 타이머도 큐도 스레드도 없다.
@MainActor
final class FakeRealtimeTransport: RealtimeTransport {
    var onEvent: ((RealtimeTransportEvent) -> Void)?
    private(set) var commands: [String] = []
    private(set) var lastChannel: String?
    private(set) var lastIsPrivate: Bool?

    func connect(url: URL, apiKey: String, accessToken: String, channel: String, isPrivate: Bool) {
        commands.append("connect(\(accessToken))")
        lastChannel = channel
        lastIsPrivate = isPrivate
    }
    func pushAccessToken(_ token: String) { commands.append("push(\(token))") }
    /// 하트비트에 **즉시 응답한다.** 살아 있는 소켓의 모양이다.
    /// 응답하지 않으면 스토어의 5초 티커가 50초 뒤 이 연결을 좀비로 판정해 끊는데, 전체 스위트에서는
    /// 테스트 하나가 수백 초를 살기 때문에 그 판정이 **테스트 도중에** 터져 구독 상태를 전제한 단언들이
    /// 부하 때문에 빨개진다(좀비 판정 자체는 순수 링 테스트가 따로 지킨다).
    func sendHeartbeat() {
        commands.append("heartbeat")
        onEvent?(.heartbeatAck)
    }
    func disconnect() { commands.append("disconnect") }
    func emit(_ event: RealtimeTransportEvent) { onEvent?(event) }
}

// MARK: - 1. 뚜껑 — 재연결중과 실패는 다르다

@Test
func 뚜껑을_두시간_닫았다_열면_오류가_아니라_재연결이다() {
    var link = subscribedLink()

    apply(&link, .willSleep, t0 + 10)
    #expect(link.state == .idle(.suspended))

    // 2시간 뒤 깨어난다. 실패 시계는 **여기서 새로 시작한다** — 그래서 뚜껑을 아무리 오래 닫아도
    // 깨는 순간 빨간 글씨가 뜨는 일은 원리적으로 없다.
    let wake = t0 + 7210
    let effects = apply(&link, .didWake, wake)
    #expect(effects.contains(.connect(accessToken: "tok-a")))

    // Wi-Fi 재결합에 5번 실패한다. 그래도 아직 실패가 아니다.
    var now = wake
    for _ in 0..<5 {
        apply(&link, .transport(.closed(code: 1006)), now)
        now = link.retryAt ?? now
        apply(&link, .tick, now)                    // 백오프 대기 중에도 tick 은 계속 들어온다
        apply(&link, .backoffElapsed, now)
    }
    #expect(link.isFailed == false, "뚜껑을 열 때마다 빨간 글씨가 뜨면 안 된다")
    #expect(now.timeIntervalSince(wake) < RealtimeLinkConstants.failedAfterSeconds)

    // 붙는 순간 캐치업이 정확히 한 번 나간다. **이 배열이 딱 이것이어야 한다** —
    // 여기 다른 effect 가 끼면 캐치업 발사 지점이 하나가 아니게 된 것이다.
    #expect(apply(&link, .transport(.joined), now) == [.catchUp])
    #expect(link.state.isSubscribed)
}

@Test
func 실패는_시도횟수가_아니라_연속실패_시간으로_승격된다() {
    var link = subscribedLink()
    apply(&link, .transport(.closed(code: nil)), t0)
    #expect(link.isFailed == false)

    // 임계 직전: 시도를 몇 번을 했든 아직 실패가 아니다.
    apply(&link, .tick, t0 + RealtimeLinkConstants.failedAfterSeconds - 1)
    #expect(link.isFailed == false)

    apply(&link, .tick, t0 + RealtimeLinkConstants.failedAfterSeconds + 1)
    #expect(link.state == .failed(
        Backoff(attempt: 1, retryAt: t0 + 1, failingSince: t0), .exhausted
    ))

    // failed 는 **스스로 내려오지 않는다**. 내려오는 길은 joined 하나다.
    apply(&link, .tick, t0 + 600)
    #expect(link.isFailed)
    apply(&link, .backoffElapsed, t0 + 601)
    apply(&link, .transport(.joined), t0 + 601)
    #expect(link.state.isSubscribed)
}

@Test
func 실패시계는_뚜껑을_열_때마다_사라진다() {
    var link = subscribedLink()
    apply(&link, .transport(.closed(code: nil)), t0)
    apply(&link, .tick, t0 + 100)
    #expect(link.isFailed)

    apply(&link, .willSleep, t0 + 110)
    #expect(link.failingSince == nil, "suspended 에 실패 시계가 남으면 뚜껑을 열자마자 빨간 글씨다")

    apply(&link, .didWake, t0 + 8000)
    apply(&link, .transport(.closed(code: nil)), t0 + 8000)
    apply(&link, .tick, t0 + 8010)
    #expect(link.isFailed == false, "wake 직후 10초 만에 실패로 떨어지면 실패 시계가 리셋되지 않은 것이다")
}

// MARK: - 2. 좀비 소켓 (blocker 리얼타임 #1)

// @MainActor 인 이유: 근무 하트비트 상수(WorkTimerStore.heartbeatIntervalSeconds)와 값이 다른지를
// 여기서 대조하기 때문이다. 그 대조가 "이름·값 모두 분리한다"는 계약의 유일한 기계적 증거다.
@MainActor
@Test
func 하트비트가_끊긴_좀비소켓은_스스로_재연결로_빠져나온다() {
    // 임계를 **리터럴로 못 박는다.** 상수를 그대로 쓰는 단언만 있으면 상수를 늘리는 뮤턴트가
    // 기대값까지 함께 늘려 초록으로 통과한다(조인 타임아웃·캐치업 재시도에서 실제로 겪었다).
    #expect(RealtimeLinkConstants.heartbeatIntervalSeconds == 25)
    #expect(RealtimeLinkConstants.heartbeatMissesBeforeDead == 2)
    // 근무 하트비트(30초)와 **값이 달라야** 한다 — 같으면 한쪽을 고칠 때 다른 쪽이 조용히 따라 바뀐다.
    #expect(RealtimeLinkConstants.heartbeatIntervalSeconds != WorkTimerStore.heartbeatIntervalSeconds)
    // 점검 주기가 하트비트 주기보다 성기면 25초 눈금을 놓쳐 좀비 판정이 통째로 늦는다.
    #expect(WorkTimerStore.realtimeTickIntervalSeconds < RealtimeLinkConstants.heartbeatIntervalSeconds)

    var link = subscribedLink()

    // 25초: 아직 살아 있다고 본다. 대신 하트비트를 보낸다.
    let firstTick = t0 + RealtimeLinkConstants.heartbeatIntervalSeconds
    #expect(apply(&link, .tick, firstTick) == [.sendHeartbeat])
    #expect(link.state.isSubscribed)

    // 50초까지도 아직이다(misses = 2).
    let dead = RealtimeLinkConstants.heartbeatIntervalSeconds
        * Double(RealtimeLinkConstants.heartbeatMissesBeforeDead)
    apply(&link, .tick, t0 + dead)
    #expect(link.state.isSubscribed)

    // 50초를 넘기면 — `.closed` 가 **한 번도 오지 않았는데도** 스스로 빠져나온다.
    // Wi-Fi 이탈·VPN 전환의 half-open TCP 가 정확히 이 모양이고, 폴백이 없으므로 이것이 유일한 회복 경로다.
    let effects = apply(&link, .tick, t0 + dead + 1)
    #expect(effects.contains(.disconnect))
    #expect(link.state.isSubscribed == false)
    if case .reconnecting = link.state {} else { Issue.record("좀비 소켓이 subscribed 로 남았다: \(link.state)") }
}

@Test
func 하트비트_응답과_브로드캐스트는_둘_다_살아있다는_증거다() {
    for evidence: RealtimeTransportEvent in [.heartbeatAck, .broadcast(event: "ring")] {
        var link = subscribedLink()
        let dead = RealtimeLinkConstants.heartbeatIntervalSeconds
            * Double(RealtimeLinkConstants.heartbeatMissesBeforeDead)
        // 죽었다고 판정되기 직전에 증거가 하나 도착한다.
        apply(&link, .transport(evidence), t0 + dead - 1)
        // 그 뒤 50초까지는 여전히 살아 있어야 한다.
        apply(&link, .tick, t0 + dead - 1 + dead)
        #expect(link.state.isSubscribed, "\(evidence) 를 받고도 죽은 소켓으로 판정했다")
    }
}

@Test
func 조인이_응답없이_굳어도_링이_스스로_빠져나온다() {
    // 설계 전이표에 없던 가드다. `connecting` 을 빠져나가는 길이 joined/closed/joinRejected 셋뿐인데
    // half-open TCP 는 그 셋을 **하나도** 주지 않는다 — 없으면 영구 connecting = 영구 침묵이다.
    // 임계를 **리터럴로 적는다.** 상수를 그대로 쓰면 상수를 늘리는 뮤턴트가 테스트까지 함께 늘려
    // 초록으로 통과한다(실제로 겪었다 — 86400 으로 바꿔도 안 빨개졌다).
    #expect(RealtimeLink.joinTimeoutSeconds == 15)
    var link = RealtimeLink(transportAvailable: true)
    apply(&link, .signedIn(accessToken: "tok"), t0)
    apply(&link, .tick, t0 + 15)
    if case .connecting = link.state {} else { Issue.record("타임아웃 전에 나갔다") }

    let effects = apply(&link, .tick, t0 + 16)
    #expect(effects.contains(.disconnect))
    if case .reconnecting = link.state {} else { Issue.record("조인이 굳었는데 안 빠져나왔다: \(link.state)") }
}

// MARK: - 3. 백오프 — 38명이 같은 밀리초에 끊긴다

@Test
func 서른여덟명이_동시에_끊겨도_재시도가_흩어진다() {
    var retries: [Date] = []
    for _ in 0..<38 {
        var link = subscribedLink()
        // 실난수를 쓰는 **유일한** 테스트다(분산 자체가 대상이라 결정적 주입값으로는 잴 수 없다).
        _ = link.apply(.transport(.closed(code: nil)), now: t0, jitter: { $0 <= 0 ? 0 : Double.random(in: 0...$0) })
        retries.append(link.retryAt ?? t0)
    }
    let seconds = retries.map { $0.timeIntervalSince(t0) }
    #expect(Set(seconds).count >= 20, "38개 재조인이 같은 지점에 뭉치면 자기충족적 장애 루프가 된다")
    #expect(seconds.allSatisfy { $0 >= BackoffPolicy.default.floor })

    // 대조군: 지터를 빼면(고정 지수) 38개가 **정확히 한 지점**에 뭉친다. 이 줄이 위 단언의 의미를 만든다.
    var fixed: [Date] = []
    for _ in 0..<38 {
        var link = subscribedLink()
        apply(&link, .transport(.closed(code: nil)), t0)
        fixed.append(link.retryAt ?? t0)
    }
    #expect(Set(fixed).count == 1)
}

@Test
func 백오프_상한과_하한이_지켜진다() {
    let policy = BackoffPolicy.default
    // ceiling 수열 1, 2, 4, 8, 16, 30, 30 …
    #expect(policy.delay(attempt: 1, jitter: ceilingJitter) == 1)
    #expect(policy.delay(attempt: 5, jitter: ceilingJitter) == 16)
    #expect(policy.delay(attempt: 9, jitter: ceilingJitter) == 30)
    // full jitter 는 0 에 가까운 값을 뽑을 수 있다 — floor 가 없으면 소켓 정리 전에 재시도가 나간다.
    #expect(policy.delay(attempt: 5, jitter: { _ in 0 }) == policy.floor)
}

// MARK: - 4. 캐치업 발사 지점은 정확히 하나

@Test
func 캐치업은_구독전이에서만_발사된다() {
    var link = subscribedLink()
    // 이미 subscribed 인 상태에서 어떤 사건이 와도 캐치업은 안 나간다.
    for event: RealtimeEvent in [
        .transport(.broadcast(event: "ring")),
        .transport(.heartbeatAck),
        .tick,
        .tokenRefreshed(accessToken: "tok-b"),
        .transport(.opened)
    ] {
        #expect(apply(&link, event, t0 + 1).contains(.catchUp) == false, "\(event) 가 캐치업을 또 쐈다")
    }
    // 끊겼다 붙을 때만 다시 나간다.
    apply(&link, .transport(.closed(code: nil)), t0 + 2)
    apply(&link, .backoffElapsed, t0 + 3)
    #expect(apply(&link, .transport(.joined), t0 + 4) == [.catchUp])
}

@Test
func 브로드캐스트는_drain_하나만_시킨다() {
    var link = subscribedLink()
    #expect(apply(&link, .transport(.broadcast(event: "ring")), t0 + 1) == [.drain])
}

// MARK: - 5. 인증 — 조인 거절의 두 종류

@Test
func 만료토큰_조인거절은_먼저_갱신을_시도한다() {
    var link = RealtimeLink(transportAvailable: true)
    apply(&link, .signedIn(accessToken: "old"), t0)

    // 1회차: 갱신을 먼저 시도한다. **즉시 실패로 승격하지 않는다** —
    // 뚜껑을 3시간 닫았다 연 사용자는 **항상** 이 경로이고, 그건 정상 경로다.
    let first = apply(&link, .transport(.joinRejected(.expiredToken)), t0 + 1)
    #expect(first == [.refreshToken(force: true)])
    if case .connecting = link.state {} else { Issue.record("갱신 시도 중에 상태가 바뀌었다") }

    // 2회차(같은 시도 안에서): 갱신하고도 거절이면 그때 실패다.
    apply(&link, .transport(.joinRejected(.expiredToken)), t0 + 2)
    #expect(link.state == .failed(
        Backoff(attempt: 2, retryAt: t0 + 3, failingSince: t0 + 2), .unauthorized
    ))
}

@Test
func RLS거절은_즉시_서버설정_실패이고_백오프는_상한으로_계속_돈다() {
    var link = RealtimeLink(transportAvailable: true)
    apply(&link, .signedIn(accessToken: "tok"), t0)
    let effects = apply(&link, .transport(.joinRejected(.unauthorized)), t0 + 1)

    // 재시도로 안 낫는다(서버 정책 미배포). 그래도 포기가 아니다 —
    // cap 간격으로 계속 두드리므로 마이그레이션이 배포되는 순간 사용자 조작 없이 스스로 낫는다.
    #expect(link.state == .failed(
        Backoff(attempt: 2, retryAt: t0 + 1 + BackoffPolicy.default.cap, failingSince: t0 + 1), .topicDenied
    ))
    #expect(effects == [.scheduleRetry(at: t0 + 1 + BackoffPolicy.default.cap)])
}

@Test
func 토큰갱신은_재연결이_아니라_푸시다() {
    var link = subscribedLink()
    let effects = apply(&link, .tokenRefreshed(accessToken: "tok-b"), t0 + 10)
    #expect(effects.contains(.pushAccessToken("tok-b")))
    #expect(effects.contains(.disconnect) == false, "1시간마다 소켓이 끊기면 진짜 장애와 구분이 안 된다")
    #expect(link.state.isSubscribed)
    // 다음 갱신도 함께 예약된다 — 이게 없으면 두 번째 만료에서 조용히 죽는다.
    #expect(effects.contains { if case .scheduleTokenRefresh = $0 { return true }; return false })
}

@Test
func 선제갱신_시각은_만료_5분_전이고_못_읽으면_50분_고정이다() {
    let exp = t0 + 3600
    let token = fakeJWT(exp: exp)
    #expect(RealtimeLink.tokenRefreshDate(accessToken: token, now: t0) == exp - 300)

    // 이미 만료 임박한 토큰으로 부팅해도 폭주하지 않는다(하한 30초).
    let almost = fakeJWT(exp: t0 + 10)
    #expect(RealtimeLink.tokenRefreshDate(accessToken: almost, now: t0) == t0 + 30)

    // **nil 은 '모른다'이지 '만료'가 아니다.** 즉시 갱신을 걸면 GoTrue 형식이 바뀌는 날
    // 사용자 38명이 한꺼번에 갱신 폭풍을 일으킨다.
    #expect(RealtimeLink.tokenRefreshDate(accessToken: "not-a-jwt", now: t0) == t0 + 3000)
}

@Test
func 치명적_갱신실패만_링을_내린다() {
    var link = subscribedLink()
    apply(&link, .tokenRefreshFailed(fatal: false), t0 + 1)
    #expect(link.state.isSubscribed, "일시 네트워크 실패로 소켓을 내리면 안 된다")

    apply(&link, .tokenRefreshFailed(fatal: true), t0 + 2)
    #expect(link.state == .idle(.signedOut))
}

// MARK: - 6. 킬스위치 / fail-closed

@Test
func 전송자가_없으면_링은_한발짝도_움직이지_않는다() {
    var link = RealtimeLink()      // 기본값 = 전송자 없음
    #expect(link.state == .idle(.disabled))
    for event: RealtimeEvent in [
        .signedIn(accessToken: "tok"), .didWake, .backoffElapsed, .tick,
        .transport(.joined), .transport(.broadcast(event: "ring"))
    ] {
        #expect(apply(&link, event, t0) == [], "\(event) 가 disabled 링을 움직였다")
        #expect(link.state == .idle(.disabled))
    }
    // 그리고 이 상태에서 isSubscribed 는 거짓이다 = 폴링이 예전 그대로 돈다.
    #expect(link.state.isSubscribed == false)
}

/// v0.2.34 부터 기본값이 **켜짐**이다(e2e 배달 실측 통과). 이 테스트가 지키는 핵심은 기본값 자체가 아니라
/// **끈 사람의 의사가 기본값에 덮이지 않는 것**이다 — bool(forKey:) 로 읽으면 "키 없음"과 "false" 가
/// 같아져서, 기본값이 켜짐인 순간 사용자가 끈 사실이 조용히 사라진다.
@Test
func 킬스위치_기본값은_켜짐이고_끈_의사는_보존된다() {
    let empty = UserDefaults(suiteName: "realtime-flag-\(UUID().uuidString)")!
    // 키가 없으면 켜짐.
    #expect(RealtimeFeature.isEnabled(defaults: empty, environment: [:]))
    // 명시적으로 켬.
    empty.set(true, forKey: RealtimeFeature.defaultsKey)
    #expect(RealtimeFeature.isEnabled(defaults: empty, environment: [:]))
    // **명시적으로 끈 사실이 기본값(켜짐)을 이긴다.** 이 줄이 이 테스트의 존재 이유다.
    empty.set(false, forKey: RealtimeFeature.defaultsKey)
    #expect(RealtimeFeature.isEnabled(defaults: empty, environment: [:]) == false)
    // 환경변수는 설정을 이긴다(프로브·개발용 탈출구).
    #expect(RealtimeFeature.isEnabled(defaults: empty, environment: ["CHECK_REALTIME": "1"]))
    // 그리고 끄는 쪽으로도 이긴다 — 프로브가 켜진 앱에서 리얼타임 없이 돌 수 있어야 한다.
    #expect(RealtimeFeature.isEnabled(defaults: empty, environment: ["CHECK_REALTIME": "0"]) == false)
}

@Test
func 로그아웃_상태에서_뚜껑을_닫아도_suspended가_되지_않는다() {
    var link = RealtimeLink(transportAvailable: true)
    #expect(link.state == .idle(.signedOut))
    apply(&link, .willSleep, t0)
    #expect(link.state == .idle(.signedOut), "signedOut 이 suspended 가 되면 wake 가 로그인 없이 연결을 시도한다")
    #expect(apply(&link, .didWake, t0 + 1) == [])
}

// MARK: - 6-b. 근무 게이트 (v0.2.34 — 소켓은 근무 중에만 뜬다)

@Test
func 근무_종료는_로그아웃이_아니라_토큰을_남긴다() {
    var link = subscribedLink(token: "tok-a")

    #expect(apply(&link, .workEnded, t0) == [.disconnect, .cancelRetry])
    #expect(link.state == .idle(.notWorking))
    // **이 한 줄이 `.signedOut` 과의 차이 전부다.** 지우면 근무를 다시 시작할 때 링이 붙을 근거를 잃고
    // `.idle(.signedOut)` 으로 떨어져, 로그인해 둔 사용자가 로그아웃된 것처럼 보인다.
    #expect(link.accessToken == "tok-a")

    // 그래서 근무를 다시 시작하면 **다시 로그인하지 않고** 그 토큰으로 곧바로 붙는다.
    #expect(apply(&link, .signedIn(accessToken: "tok-a"), t0 + 10)
        .contains(.connect(accessToken: "tok-a")))
    apply(&link, .transport(.joined), t0 + 11)
    #expect(link.state.isSubscribed)

    // 두 번째 `.workEnded` 는 no-op 이다 — 되맞춤이 주기적으로 넣으므로, 여기서 매번 disconnect 를
    // 돌려주면 비근무 구간 내내 죽은 소켓에 대고 끊기를 되풀이한다.
    apply(&link, .workEnded, t0 + 12)
    #expect(apply(&link, .workEnded, t0 + 13) == [])
    #expect(link.state == .idle(.notWorking))
}

@Test
func 비근무_상태에서_뚜껑을_닫아도_suspended가_되지_않는다() {
    // `.suspended` 로 접히면 `.didWake` 가 근무하지도 않는 맥의 소켓을 다시 올린다
    // (로그아웃에서 같은 결함을 막는 가지가 바로 위에 있다).
    var link = subscribedLink()
    apply(&link, .workEnded, t0)
    #expect(link.state == .idle(.notWorking))

    apply(&link, .willSleep, t0 + 10)
    #expect(link.state == .idle(.notWorking),
            "notWorking 이 suspended 가 되면 뚜껑을 여는 순간 근무 없이 다시 붙는다")
    #expect(apply(&link, .didWake, t0 + 7200) == [])
    #expect(link.state == .idle(.notWorking))
}

@Test
func 뚜껑을_닫은_채_근무가_끝나면_사유가_정정된다() {
    // 뚜껑을 닫은 사이에 근무가 끝날 수 있다(잠자기 자동 마감·서버 마감). 사유를 정정하지 않으면
    // 뚜껑을 여는 순간 `.didWake` 가 `.idle(.suspended)` 를 보고 근무 없이 다시 붙는다.
    var link = subscribedLink()
    apply(&link, .willSleep, t0)
    #expect(link.state == .idle(.suspended))

    #expect(apply(&link, .workEnded, t0 + 5) == [], "이미 내려간 소켓에 disconnect 를 또 쏘면 안 된다")
    #expect(link.state == .idle(.notWorking))
    #expect(apply(&link, .didWake, t0 + 10) == [])
    #expect(link.state == .idle(.notWorking))
}

@Test
func 전송자가_없으면_근무_종료도_링을_움직이지_못한다() {
    // `.idle(.disabled)` 은 **어떤 이벤트로도** 벗어나지 않는다(fail-closed). `.workEnded` 가 이
    // 잠금을 뚫으면 킬스위치를 끈 빌드가 조용히 링을 갖게 된다.
    var link = RealtimeLink(transportAvailable: false)
    apply(&link, .signedIn(accessToken: "tok"), t0)
    #expect(apply(&link, .workEnded, t0 + 1) == [])
    #expect(link.state == .idle(.disabled))
}

// MARK: - 7. Phoenix 프레임 (순수 — 소켓 없음)

@Test
func 조인_페이로드에_private가_들어간다() throws {
    let text = RealtimeFrame.join(channel: "poke:abc", accessToken: "tok", isPrivate: true, ref: "1")
    let data = try #require(text.data(using: .utf8))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    // wire topic 에만 `realtime:` 접두사가 붙는다. RLS 가 보는 realtime.topic() 은 접두사 없는 쪽이고,
    // 그게 서버 public.poke_topic(uuid) 의 반환값과 문자 그대로 같아야 한다.
    #expect(object["topic"] as? String == "realtime:poke:abc")
    #expect(RealtimeFrame.wireTopic(channel: "poke:abc") == "realtime:poke:abc")

    let payload = try #require(object["payload"] as? [String: Any])
    #expect(payload["access_token"] as? String == "tok")
    let config = try #require(payload["config"] as? [String: Any])
    // **이 한 줄이 이 프레임의 존재 이유다.** private 이 빠지면 조인이 그냥 성공하고
    // realtime.messages RLS 가 아예 상담되지 않아 `.topicDenied` 브랜치가 죽은 코드가 된다.
    #expect(config["private"] as? Bool == true)
}

@Test
func 소켓_URL은_wss_이고_apikey를_싣는다() throws {
    let url = try #require(RealtimeFrame.socketURL(
        projectURL: URL(string: "https://example.supabase.co")!, apiKey: "anon"
    ))
    #expect(url.scheme == "wss")
    #expect(url.path == "/realtime/v1/websocket")
    #expect(url.query?.contains("apikey=anon") == true)
    #expect(url.query?.contains("vsn=1.0.0") == true)
}

@Test
func 조인거절_분류는_만료를_먼저_본다() {
    // 만료는 강제 갱신 1회로 낫고, RLS 거절은 재시도로 절대 안 낫는다 —
    // 뒤집히면 만료된 사용자가 "서버 설정 문제" 문구를 보고 할 수 있는 일이 없다고 믿는다.
    #expect(RealtimeFrame.classifyJoinError(reason: "Token has expired") == .expiredToken)
    #expect(RealtimeFrame.classifyJoinError(reason: "InvalidJWTToken: expired") == .expiredToken)
    #expect(RealtimeFrame.classifyJoinError(
        reason: "You do not have permissions to read from this Channel topic"
    ) == .unauthorized)
    #expect(RealtimeFrame.classifyJoinError(reason: "unauthorized") == .unauthorized)
    // **순서가 걸리는 유일한 입력**: 두 어휘가 함께 오는 실제 서버 문구다. 만료를 먼저 보지 않으면
    // 뚜껑 3시간 닫았다 연 사용자가 "서버 설정 문제"를 보고 할 수 있는 일이 없다고 믿는다.
    #expect(RealtimeFrame.classifyJoinError(reason: "Unauthorized: Token has expired") == .expiredToken)
    #expect(RealtimeFrame.classifyJoinError(reason: "boom") == .unknown("boom"))
}

@Test
func 프레임_해석이_남의_토픽을_우리_것으로_오인하지_않는다() {
    let channel = "poke:me"
    #expect(RealtimeFrame.decode(
        text: #"{"topic":"realtime:poke:someone-else","event":"broadcast","payload":{"event":"ring"}}"#,
        channel: channel, joinRef: "1"
    ) == nil)
    #expect(RealtimeFrame.decode(
        text: #"{"topic":"realtime:poke:me","event":"broadcast","payload":{"event":"ring"}}"#,
        channel: channel, joinRef: "1"
    ) == .broadcast(event: "ring"))
    #expect(RealtimeFrame.decode(
        text: #"{"topic":"realtime:poke:me","event":"phx_reply","ref":"1","payload":{"status":"ok"}}"#,
        channel: channel, joinRef: "1"
    ) == .joined)
    #expect(RealtimeFrame.decode(
        text: #"{"topic":"realtime:poke:me","event":"phx_reply","ref":"1","payload":{"status":"error","response":{"reason":"Token has expired"}}}"#,
        channel: channel, joinRef: "1"
    ) == .joinRejected(.expiredToken))
    // 하트비트 응답은 topic "phoenix" 로 온다 — 이걸 놓치면 살아 있는 소켓을 좀비로 판정해 끊는다.
    #expect(RealtimeFrame.decode(
        text: #"{"topic":"phoenix","event":"phx_reply","ref":"7","payload":{"status":"ok"}}"#,
        channel: channel, joinRef: "1"
    ) == .heartbeatAck)
    #expect(RealtimeFrame.decode(
        text: #"{"topic":"realtime:poke:me","event":"phx_error","payload":{}}"#,
        channel: channel, joinRef: "1"
    ) == .closed(code: nil))
}

// MARK: - 8. 스토어 배선 (Fake 전송자 — 소켓 0개)

@MainActor
@Test
func 비근무_맥은_소켓을_아예_붙이지_않는다() async {
    // ★ blocker(리얼타임 #5)의 **더 강한 형태**(v0.2.34). 예전엔 소켓이 로그인만으로 떠 있고,
    //   두 맥 모두에 도착한 초인종을 take_pokes 게이트가 집 맥에서 막았다. 이제는 애초에 붙지 않는다 —
    //   서버의 poke_user / ultra_poke_user / send_message 가 전부 target_not_working 게이트를 갖기 때문에
    //   (20260819030000_poke_economy_and_ring.sql:69, :156, :215) 비근무 맥에게 올 신호가 원리적으로 없고,
    //   그 소켓은 25초 하트비트만 태운다.
    let host = "realtime-idle-mac"
    let (store, transport) = makeRealtimeStore(host: host)

    #expect(store.startedAt == nil)
    store.startRealtimeIfPossible()

    #expect(transport.commands.contains { $0.hasPrefix("connect(") } == false, "비근무인데 소켓을 열었다")
    #expect(store.realtimeState == .idle(.notWorking))
    // 막혔다는 **사실이 화면까지 온다.** 조용히 반환하면 초기값 `.idle(.disabled)` 이 남아
    // 설정 창 진단이 로그인해 둔 사용자에게 '전송자 없음'과 같은 얼굴을 보여 준다.
    #expect(store.realtimeDiagnosticsLine.contains("idle(notWorking)"))

    // 근무를 시작하면 같은 호출이 이번엔 실제로 붙고, 초인종이 소비로 이어진다
    // (게이트가 '언제나 막는' 것이 아님을 증명한다).
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await waitUntil { takePokesCount(host: host) >= 1 }
    await waitUntil { realtimeIdle(store) }
    #expect(store.realtimeState.isSubscribed)
    #expect(takePokesCount(host: host) == 1)
}

@MainActor
@Test
func 흡수세션인_맥은_붙지도_소비하지도_않는다() async {
    let host = "realtime-adopted-mac"
    let (store, transport) = makeRealtimeStore(host: host)
    store.startedAt = Date()
    store.adoptedRemoteSession = true      // 이 근무의 주인은 다른 맥이다

    store.startRealtimeIfPossible()
    #expect(transport.commands.contains { $0.hasPrefix("connect(") } == false,
            "흡수 세션의 주인은 다른 맥이다 — 그 초인종을 받아 가면 진짜 주인에게 아무것도 안 간다")
    #expect(store.realtimeState == .idle(.notWorking))

    // 표식을 내리면 붙는다(게이트가 '언제나 막는' 것이 아님).
    store.adoptedRemoteSession = false
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await waitUntil { takePokesCount(host: host) >= 1 }
    await waitUntil { realtimeIdle(store) }
    let afterCatchUp = takePokesCount(host: host)
    #expect(afterCatchUp == 1)

    // **소비 게이트는 따로 살아 있어야 한다.** 붙어 있는 동안 폴링이 "이 세션의 주인은 다른 맥"이라고
    // 알려 오면(재흡수), 소켓이 아직 살아 있어도 소비는 즉시 멈춘다 — `run(_:now:)` 의 `.drain` 가지다.
    // 붙는 것을 막는 게이트만 있고 이게 없으면, 흡수로 뒤집힌 그 창에서 집 맥이 남의 찌르기를 훔친다.
    store.adoptedRemoteSession = true
    transport.emit(.broadcast(event: "ring"))
    await waitUntil { realtimeIdle(store) }
    #expect(takePokesCount(host: host) == afterCatchUp, "흡수 표식이 선 뒤에도 남의 찌르기를 훔쳤다")
}

@MainActor
@Test
func 조인을_기다리는_사이_흡수로_뒤집히면_되찾은_뒤에_따라잡는다() async {
    // 근무 게이트(v0.2.34)가 "붙기 전"의 창을 없앴지만 **조인 응답을 기다리는 창**은 남는다:
    // 조인은 근무 중에 나갔는데 그 사이 폴링이 "이 세션의 주인은 다른 맥"이라고 알려 오면,
    // 뒤늦게 도착한 `.joined` 의 따라잡기가 게이트에 막힌다. 재구독은 다시 일어나지 않으므로
    // (그 링은 이미 subscribed 다) 잊으면 그 구간의 밀린 찌르기는 회수 경로가 0이다.
    let host = "realtime-deferred-catchup"
    let (store, transport) = makeRealtimeStore(host: host)
    store.startedAt = Date()

    store.startRealtimeIfPossible()
    store.adoptedRemoteSession = true       // 조인 응답을 기다리는 사이에 폴링이 알려 왔다
    transport.emit(.joined)
    await waitUntil { realtimeIdle(store) }
    #expect(takePokesCount(host: host) == 0)
    #expect(store.realtime.catchUpDeferred, "건너뛴 사실을 아무도 기억하지 않으면 회수할 방법이 없다")

    // 다른 맥이 근무를 놓아 이 맥이 세션을 되찾는다. 구독 전이는 이미 지나갔으므로 회수는 주기 점검이 한다.
    // 시각을 **명시**한다 — 기본 인자(Date())를 쓰면 부하로 구독이 오래되었을 때 같은 tick 이
    // 좀비 판정을 먼저 내려 구독을 끊고, 그러면 회수 분기까지 오지도 못한다.
    store.adoptedRemoteSession = false
    store.realtimeTick(at: store.realtime.diagnostics.recent.last.map { $0.at + 1 } ?? Date())
    await waitUntil { takePokesCount(host: host) >= 1 }
    await waitUntil { realtimeIdle(store) }
    #expect(takePokesCount(host: host) == 1)
    #expect(store.realtime.catchUpDeferred == false)
}

@MainActor
@Test
func 구독하면_따라잡기가_정확히_한번_돌고_경고가_내려간다() async {
    let host = "realtime-catchup"
    let (store, transport) = makeRealtimeStore(host: host)
    store.startedAt = Date()
    store.realtimeCatchUpFailedAt = Date()   // 지난 실패의 잔재

    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await waitUntil { takePokesCount(host: host) >= 1 }
    await waitUntil { realtimeIdle(store) }

    #expect(takePokesCount(host: host) == 1, "구독 전이에서 따라잡기가 정확히 1회여야 한다")
    #expect(store.realtimeCatchUpFailedAt == nil, "성공했는데 낡은 경고가 눌러앉았다")
    #expect(store.realtime.diagnostics.lastCatchUpAt != nil)
}

@MainActor
@Test
func 따라잡기는_실패하면_세번까지_재시도하고_그_사실을_남긴다() async {
    // 캐치업은 실패를 삼키면 안 된다 — 폴링이 없어졌으므로 삼킨 그 구간의 찌르기는 영영 안 온다.
    // `schema-missing` 은 /rest/v1/* 를 전부 404 로 돌려주는 픽스처 호스트다(take_pokes 도 실패한다).
    let (store, transport) = makeRealtimeStore(host: "schema-missing")
    store.startedAt = Date()

    store.startRealtimeIfPossible()
    transport.emit(.joined)
    // 예산이 유독 큰 이유: 이 시나리오만 **왕복 3회 + 사이 대기 3초**를 순서대로 지나야 한다.
    // 전체 스위트에서 메인 액터를 수십 초씩 잡는 테스트들과 겹치면 60초로는 모자란다(실측).
    await waitUntil(240) { store.realtimeCatchUpFailedAt != nil }

    // 시도 횟수로 센다 — 요청 수로 세면 이 픽스처 호스트를 공유하는 다른 스위트와 섞여 흔들린다.
    // **리터럴 3 이다.** `WorkTimerStore.catchUpAttempts` 를 그대로 쓰면 예산을 1회로 줄이는 뮤턴트가
    // 기대값까지 함께 줄여 초록으로 통과한다(실제로 겪었다). 상수 자체도 따로 못 박는다.
    #expect(WorkTimerStore.catchUpAttempts == 3)
    #expect(store.realtime.diagnostics.lastCatchUpAttempts == 3)
    #expect(store.realtimeCatchUpFailedAt != nil, "세 번 다 실패했는데 아무 흔적도 안 남았다")
    #expect(store.realtime.diagnostics.lastCatchUpFailure != nil)
}

@MainActor
@Test
func drain_중_신호가_두건이면_take_pokes는_정확히_두번_나간다() async {
    // ★ blocker(리얼타임 #2) 회귀 가드. defer 로 drainInFlight 를 비우면 트레일링 재진입이
    //   **자기 자신에게 막혀** 두 번째 찌르기가 영영 유실된다(폴링이 없으니 회복 경로 0).
    // `delayed-` 접두사는 스텁의 상시 지연 규약이다(전역 delayedHosts 를 건드리면 병렬 스위트가 서로를 덮는다).
    let host = "delayed-realtime-drain-merge"
    let (store, _) = makeRealtimeStore(host: host)
    store.startedAt = Date()

    store.requestDrain()
    // 첫 drain 이 **실제로 인플라이트가 될 때까지** 양보한다. 그 전에 도착한 신호는 아직 나가지도 않은
    // 첫 요청이 어차피 함께 가져오므로 유실이 아니다 — 위험한 것은 '이미 지나간 스냅샷 이후'의 신호다.
    await Task.yield()
    store.requestDrain()      // 인플라이트 중 도착한 두 번째 신호
    store.requestDrain()      // 세 번째는 두 번째와 합쳐진다(트레일링은 1건)
    await waitUntil { takePokesCount(host: host) >= 2 }
    await waitUntil { realtimeIdle(store) }

    #expect(takePokesCount(host: host) == 2)
}

@MainActor
@Test
func 구독중_근무종료도_꼬리를_한번_더_회수한다() async throws {
    let host = "realtime-flush"
    let (store, transport) = makeRealtimeStore(host: host)
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await waitUntil { takePokesCount(host: host) >= 1 }
    await waitUntil { realtimeIdle(store) }
    let afterCatchUp = takePokesCount(host: host)

    // 구독 신호는 서 있다. 그런데도 꼬리 회수는 돈다 — v0.2.34 는 폴링을 남긴다.
    #expect(store.realtimeState.isSubscribed)
    #expect(store.pollingIsPausedByRealtime == false)

    // 링이 살아 있었다면 이 왕복의 대가는 빈 배열 하나뿐이다(take_pokes 는 서버 원자 소비라
    // 두 경로가 같은 행을 집어도 한쪽만 받는다). 링이 조용히 죽어 있었다면 이게 그 근무의
    // 마지막 찔림을 건지는 유일한 경로다 — 그 비대칭이 안전망을 남긴 이유 전부다.
    let task = try #require(
        store.flushPokesOnWorkEnd(),
        "구독을 이유로 꼬리 회수를 접으면 좀비 소켓 근무의 마지막 찔림이 조용히 사라진다"
    )
    await task.value
    await waitUntil { realtimeIdle(store) }
    #expect(takePokesCount(host: host) == afterCatchUp + 1)
}

@MainActor
@Test
func 근무를_시작하면_그때_소켓이_붙는다() async {
    // 링이 출발하는 자리는 로그인 지점(startStatusRefreshLoop)이 아니라 **start()** 다.
    let host = "realtime-work-start"
    let (store, transport) = makeRealtimeStore(host: host)

    store.startRealtimeIfPossible()          // 로그인만으로는 붙지 않는다
    #expect(store.realtimeState == .idle(.notWorking))

    store.start()

    if case .connecting = store.realtimeState {} else {
        Issue.record("근무를 시작했는데 소켓이 안 붙는다: \(store.realtimeState)")
    }
    #expect(transport.commands.contains { $0.hasPrefix("connect(") })
    await waitUntil { realtimeIdle(store) }
}

@MainActor
@Test
func 근무를_끝내면_소켓이_내려가고_꼬리_회수는_그대로_돈다() async {
    let host = "realtime-work-end"
    let (store, transport) = makeRealtimeStore(host: host)
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await waitUntil { takePokesCount(host: host) >= 1 }   // 구독 직후 따라잡기
    await waitUntil { realtimeIdle(store) }
    let afterCatchUp = takePokesCount(host: host)
    #expect(store.realtimeState.isSubscribed)

    store.stop()

    // ① 링이 내려간다. 사유는 `.signedOut` 이 아니라 `.notWorking` 이다 — 로그아웃이 아니므로.
    #expect(store.realtimeState == .idle(.notWorking))
    #expect(transport.commands.contains("disconnect"))
    // ② **순서 계약**: 링을 내렸어도 꼬리 회수는 그대로 돈다. 회수는 폴링 경로라 리얼타임과 무관해야
    //    하는데, stop() 안에서 링을 내리는 위치를 잘못 잡으면 그 회수가 조용히 죽는다
    //    (그러면 마지막 폴링 이후 도착한 찔림이 신선도 1시간을 넘겨 영구 소실된다).
    await waitUntil { takePokesCount(host: host) >= afterCatchUp + 1 }
    await waitUntil { realtimeIdle(store) }
    #expect(takePokesCount(host: host) == afterCatchUp + 1,
            "근무 종료 꼬리 회수가 링을 내리는 순서에 걸려 죽었다")
}

@MainActor
@Test
func 서버가_근무를_복원하면_되맞춤이_소켓을_올린다() async {
    // 근무 중에 앱을 재시작하면 start() 를 타지 않는다 — 서버에 열려 있던 내 세션을
    // refreshTeamStatus(adoptRemoteSession)가 로컬 startedAt 으로 되살린다. 되맞춤이 없으면
    // 그 맥의 초인종은 영영 안 붙고 15초 폴링만 남는다(열화이지 침묵은 아니라 아무도 신고하지 않는다).
    let host = "realtime-reconcile-up"
    let (store, transport) = makeRealtimeStore(host: host)
    store.startRealtimeIfPossible()
    #expect(store.realtimeState == .idle(.notWorking))

    store.startedAt = Date()                 // 서버 세션 복원
    store.reconcileRealtimeWithWorkState()

    if case .connecting = store.realtimeState {} else {
        Issue.record("서버가 근무를 복원했는데 소켓이 안 붙는다: \(store.realtimeState)")
    }
    #expect(transport.commands.contains { $0.hasPrefix("connect(") })
    await waitUntil { realtimeIdle(store) }
}

@MainActor
@Test
func 서버가_근무를_닫으면_되맞춤이_소켓을_내린다() async {
    // applyRemoteOwnStatus 의 (.offWork, .some) 가지 — 서버가 내 세션을 닫았다. stop() 을 타지 않으므로
    // 되맞춤이 없으면 비근무인 채로 소켓이 하루 종일 떠서 25초 하트비트만 태운다.
    let host = "realtime-reconcile-down"
    let (store, transport) = makeRealtimeStore(host: host)
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await waitUntil { realtimeIdle(store) }
    #expect(store.realtimeState.isSubscribed)

    store.startedAt = nil
    store.reconcileRealtimeWithWorkState()
    #expect(store.realtimeState == .idle(.notWorking))
    #expect(transport.commands.contains("disconnect"))

    // 그리고 되맞춤은 **뚜껑을 닫아 둔 맥을 깨우지 않는다** — `.suspended` 의 주인은 잠자기이지
    // 근무가 아니다. 여기서 함께 되살리면 근무 중인 채로 잠든 맥이 매 주기마다 소켓을 다시 연다.
    store.startedAt = Date()
    store.reconcileRealtimeWithWorkState()
    transport.emit(.joined)
    #expect(store.realtimeState.isSubscribed)
    store.handleSleep(at: Date())
    #expect(store.realtimeState == .idle(.suspended))

    let before = transport.commands.count
    store.reconcileRealtimeWithWorkState()
    #expect(store.realtimeState == .idle(.suspended))
    #expect(transport.commands.count == before)
    await waitUntil { realtimeIdle(store) }
}

@MainActor
@Test
func 근무중_잠자기는_소켓을_내리고_사유는_suspended다() {
    // 소켓이 뜨는 조건이 '근무 중'으로 좁혀졌으므로(v0.2.34) 잠자기 테스트의 전제도 근무 중이다.
    // handleSleep 의 리얼타임 한 줄이 `guard startedAt != nil` 뒤로 내려가도 여기는 초록이다 —
    // 그 배치가 왜 틀렸는지는 아래 `비근무로_뚜껑을_닫아도...` 가 지킨다.
    let (store, transport) = makeRealtimeStore(host: "realtime-sleep")
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    #expect(store.realtimeState.isSubscribed)

    store.handleSleep(at: Date())
    #expect(store.realtimeState == .idle(.suspended))
    #expect(transport.commands.contains("disconnect"))
}

@MainActor
@Test
func 비근무로_뚜껑을_닫아도_사유는_notWorking_그대로다() {
    // `.suspended` 로 접히면 뚜껑을 여는 순간 `.didWake` 가 **근무하지도 않는 맥의** 소켓을 다시 올린다 —
    // 로그아웃 상태에서 닫아도 `.suspended` 가 되면 안 되는 것과 정확히 같은 이유다
    // (RealtimeLink.swift 의 `.willSleep` 가지).
    let (store, transport) = makeRealtimeStore(host: "realtime-sleep-idle")
    store.startRealtimeIfPossible()
    #expect(store.realtimeState == .idle(.notWorking))

    store.handleSleep(at: t0)
    #expect(store.realtimeState == .idle(.notWorking))

    store.handleWake(at: t0 + 7200)
    #expect(store.realtimeState == .idle(.notWorking), "근무하지 않는 맥이 뚜껑을 열었다고 붙으면 안 된다")
    #expect(transport.commands.contains { $0.hasPrefix("connect(") } == false)
}

@MainActor
@Test
func 깨어나면_맨_먼저_다시_붙는다() {
    // handleWake 의 리얼타임 한 줄이 맨 앞이 아니면(아래 조기 리턴 가지가 셋이다) 이 테스트가 빨개진다.
    let (store, transport) = makeRealtimeStore(host: "realtime-wake")
    store.startedAt = Date()
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    store.handleSleep(at: t0)
    #expect(store.realtimeState == .idle(.suspended))

    // 유예(5분) 이내라 자동 마감 없이 되돌아 나가는, 조기 리턴 가지 중 하나다.
    store.handleWake(at: t0 + 60)
    if case .connecting = store.realtimeState {} else {
        Issue.record("깨어났는데 재연결이 시작되지 않았다: \(store.realtimeState)")
    }
}

@MainActor
@Test
func 연결은_private_채널로_나가고_채널명은_서버_규약과_같다() {
    let (store, transport) = makeRealtimeStore(host: "realtime-channel")
    store.startedAt = Date()          // 소켓은 근무 중에만 뜬다(v0.2.34)
    store.startRealtimeIfPossible()
    #expect(transport.lastIsPrivate == true, "private 이 빠지면 RLS 가 아예 상담되지 않는다")
    #expect(transport.lastChannel == "poke:\(store.session!.userID)")
    #expect(transport.lastChannel == RealtimeLinkConstants.pokeChannel(userID: store.session!.userID))
}

@MainActor
@Test
func 로그아웃은_소켓과_예약을_함께_내린다() {
    let (store, transport) = makeRealtimeStore(host: "realtime-signout")
    store.startedAt = Date()          // 소켓은 근무 중에만 뜬다(v0.2.34)
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    #expect(store.realtimeState.isSubscribed)

    // 끊어서 **재시도 예약이 실제로 서 있는** 상태로 만든다. 구독 중에 바로 로그아웃하면
    // 타이머가 애초에 없어서 "취소했다"를 증명하지 못한다(그 단언은 뮤턴트를 못 잡는다).
    transport.emit(.closed(code: 1006))
    #expect(store.realtime.retryTask != nil)

    store.clearPersistedSession()
    #expect(store.realtimeState == .idle(.signedOut))
    #expect(transport.commands.contains("disconnect"))
    #expect(store.realtime.retryTask == nil)
    #expect(store.realtime.tokenRefreshTask == nil)
}

/// **폴링은 구독 중에도 돈다**(v0.2.34 — 리얼타임을 켜되 폴링을 안전망으로 남긴다).
///
/// 억제 판정은 여전히 `pollingIsPausedByRealtime` **하나뿐**이고(두 번째 판정이 생기면 "리얼타임은
/// 반쯤 죽었는데 폴링도 안 도는" 완전한 침묵이 만들어진다), 지금은 그 하나가 상수에 가려 언제나 거짓이다.
/// 그래서 링이 좀비가 되어도 찌르기는 **최대 15초 지연으로 도착한다** — 열화이지 침묵이 아니다.
/// 중복 소비는 서버 take_pokes 의 원자성이 막는다.
@MainActor
@Test
func 폴링은_구독중에도_안전망으로_계속_돈다() async {
    let host = "realtime-polling-pause"
    let (store, transport) = makeRealtimeStore(host: host)
    store.startedAt = Date()

    await store.localExpiryTick()
    #expect(takePokesCount(host: host) == 1, "리얼타임이 없으면 폴링은 예전 그대로다")

    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await waitUntil { takePokesCount(host: host) >= 2 }   // 폴링 1 + 캐치업 1
    await waitUntil { realtimeIdle(store) }
    let afterSubscribe = takePokesCount(host: host)
    // 신호는 섰다(초인종 경로는 살아 있다). 억제 판정만 상수가 가린다.
    #expect(store.realtimeState.isSubscribed)
    #expect(store.pollingIsPausedByRealtime == false)

    // ★ 이 한 줄이 v0.2.34 의 전부다: 구독 중에도 tick 이 take_pokes 를 그대로 쏜다.
    await store.localExpiryTick()
    #expect(takePokesCount(host: host) == afterSubscribe + 1,
            "구독을 이유로 폴링을 쉬면 링이 조용히 죽는 순간 찌르기가 아예 안 온다 — 그건 아무도 신고하지 않는다")

    // 끊긴 뒤에도 당연히 돈다. 억제를 되살릴 v0.2.35 에서도 **이 줄만은 변하지 않는다** —
    // 그래서 여기가 억제 스위치와 무관하게 폴링 경로가 살아 있음을 보는 자리다.
    transport.emit(.closed(code: 1006))
    #expect(store.realtimeState.isSubscribed == false)
    await store.localExpiryTick()
    #expect(takePokesCount(host: host) == afterSubscribe + 2, "끊겼는데 폴링이 안 돌면 완전한 침묵이다")
}

/// **억제 배선은 상수 뒤에서 그대로 살아 있다.** 위 테스트가 지키는 것은 "지금 돈다"뿐이라,
/// 가드를 통째로 지워도 초록이다 — 그러면 v0.2.35 에서 상수를 지우는 날 아무 일도 일어나지 않고
/// 아무도 모른다. 그래서 폴링 tick 의 가드와 **판정이 하나뿐**임을 소스로 못 박는다.
/// 꼬리 회수 쪽 가드는 PokePollGateTests 의 `flushPokesOnWorkEndKeepsSuppressionWiringBehindTheConstant` 가 지킨다.
@Test
func 폴링_억제_배선은_상수_뒤에서_그대로_살아_있다() throws {
    // 주석을 걷어낸 뒤 검사한다(하우스 규칙) — 안 걷어내면 이 결정을 설명하는 주석이 검사 대상 어휘를
    // 정당하게 포함해, 설명을 지워야만 초록이 되는 테스트가 된다.
    let code = strippingComments(
        try String(contentsOf: sourceURL("WorkTimerStorePoke.swift"), encoding: .utf8)
    )
    // take_pokes 호출이 여전히 그 가드 **안에** 있다. 조각을 따로 contains 하면 본문을 가드 밖으로
    // 꺼낸 뮤턴트를 놓치므로, 공백을 접어 중첩까지 함께 본다.
    let collapsed = code.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    #expect(
        collapsed.contains("if !pollingIsPausedByRealtime { await takePokesIfWorking() }"),
        "폴링 tick 의 억제 가드가 사라졌다 — 상수를 지워도 폴링은 안 쉰다"
    )
    // 그리고 판정은 하나다: 이 파일에서 `realtimeState.isSubscribed` 를 읽는 곳은 단일 출처
    // 프로퍼티 한 군데뿐이다(두 번째 판정이 곧 반쪽 침묵이다).
    #expect(code.components(separatedBy: "realtimeState.isSubscribed").count - 1 == 1)
}

// MARK: - 9. 소스 계약

@Test
func 라이브_전송자는_프로덕션_조립_한_곳에서만_태어난다() throws {
    // 주석을 **걷어낸 뒤** 검사한다(하우스 규칙) — 안 그러면 설명을 지워야 초록이 된다.
    var hits: [String: Int] = [:]
    for url in try sourceFiles() {
        let code = strippingComments(try String(contentsOf: url, encoding: .utf8))
        let count = code.components(separatedBy: "LiveRealtimeTransport(").count - 1
        if count > 0 { hits[url.lastPathComponent] = count }
    }
    #expect(hits == ["CheckApp.swift": 1], "라이브 전송자를 만드는 곳이 늘었다: \(hits)")
}

@Test
func 테스트_판정은_기존_한_곳을_재사용한다() throws {
    // ★ blocker(리얼타임 #4): XCTestConfigurationFilePath / SWIFT_TESTING 판정은 이 저장소에서
    //   실측으로 탈락했다(둘 다 비어 있다). 그걸 다시 심으면 3겹 잠금 중 2겹이 no-op 이 된다.
    let code = strippingComments(
        try String(contentsOf: sourceURL("RealtimeTransport.swift"), encoding: .utf8)
    )
    #expect(code.contains("CheckPanelVisibility.isRunningTests"))
    #expect(code.contains("XCTestConfigurationFilePath") == false)
    #expect(code.contains("SWIFT_TESTING") == false)
    // 그리고 실제로 이 프로세스에서 nil 이다 = 테스트가 소켓을 열 수 없다.
    #expect(CheckPanelVisibility.isRunningTests)
}

@Test
func 주기_되맞춤이_새로고침_루프에_붙어_있다() throws {
    // 되맞춤은 테스트에서 직접 부를 수 있지만(위 두 테스트), 루프에 걸려 있지 않으면 프로덕션에서는
    // **아무도 부르지 않는다**: 근무 중 앱을 재시작한 맥의 초인종이 영영 안 붙고, 서버가 닫아 준
    // 세션의 소켓이 하루 종일 떠 있는다. 둘 다 조용한 결말이라 소스로 못 박는다.
    // 주석을 걷어낸 뒤 검사한다(하우스 규칙) — 안 그러면 설명을 지워야 초록이 된다.
    let code = strippingComments(
        try String(contentsOf: sourceURL("WorkTimerStore.swift"), encoding: .utf8)
    )
    #expect(code.contains("self?.reconcileRealtimeWithWorkState()"))
}

@Test
func 주기_점검_티커가_프로덕션_조립에_붙어_있다() throws {
    // 티커는 테스트 프로세스에서 뜨지 않으므로(위 startRealtimeTicker 주석) 존재를 소스로 못 박는다.
    // 지우면 좀비 소켓 판정이 **영영 호출되지 않는다** — 링은 옳게 판정하는데 아무도 안 물어보는 상태다.
    let code = strippingComments(
        try String(contentsOf: sourceURL("WorkTimerStoreRealtime.swift"), encoding: .utf8)
    )
    // **개수로 센다.** `contains` 한 번은 선언(`private func startRealtimeTicker()`)에도 걸리므로
    // 호출부를 지운 뮤턴트를 놓친다(실제로 놓쳤다). 선언 1 + 호출 1 = 최소 2다.
    #expect(code.components(separatedBy: "startRealtimeTicker()").count - 1 >= 2)
    #expect(code.contains("self.realtimeTick()"))
}

@Test
func e2e_프로브는_private_채널을_구독한다() throws {
    // 프로브가 private 없이 조인하면 RLS 가 아예 상담되지 않아, 통과해도 "정책이 산다"를
    // 증명하지 못한 채 초록이 된다 — 가장 나쁜 종류의 거짓 확신이다.
    let probe = try String(
        contentsOf: sourceURL("realtime-e2e-probe.swift", in: "scripts"), encoding: .utf8
    )
    #expect(probe.contains("\"private\": true"))
    #expect(probe.contains("realtime:\\(channel)"))
    #expect(probe.contains("poke_ring"))
}

@MainActor
@Test
func 설정창_콘텐츠가_창_높이_안에_들어온다() throws {
    // 초인종 진단 줄을 더했으므로 높이 예산을 확인한다. 팝오버의 700pt 와 같은 종류의 계약이다 —
    // 넘치면 아래 내용이 잘리는데, 잘리는 것이 바로 이 진단 줄이다(맨 아래에 있다).
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: UserDefaults(suiteName: "settings-height-\(UUID().uuidString)")!
    )
    let renderer = ImageRenderer(
        content: CheckSettingsView(store: store, launchAtLoginSeed: false)
            .frame(width: CheckSettingsView.preferredWidth)
    )
    let size = try #require(renderer.nsImage?.size)
    #expect(size.height <= CheckSettingsWindowController.defaultContentSize.height,
            "설정 콘텐츠 \(size.height)pt 가 창 \(CheckSettingsWindowController.defaultContentSize.height)pt 를 넘었다")
}

// MARK: - 헬퍼

private func fakeJWT(exp: Date) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: ["exp": Int(exp.timeIntervalSince1970)])
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}

@MainActor
private func makeRealtimeStore(host: String) -> (WorkTimerStore, FakeRealtimeTransport) {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let transport = FakeRealtimeTransport()
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: UserDefaults(suiteName: "realtime-\(host)-\(UUID().uuidString)")!,
        workspaceNotifications: nil,
        realtimeTransport: transport
    )
    store.session = SupabaseSession(
        accessToken: "access-token",
        refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.currentTeamID = URLProtocolStub.stubTeamID
    return (store, transport)
}

private func takePokesCount(host: String) -> Int {
    URLProtocolStub.requests(forHost: host).filter { $0.url?.path == "/rest/v1/rpc/take_pokes" }.count
}

/// 조건이 참이 될 때까지 기다린다. **타임아웃이 60초로 넉넉한 이유**는 이 저장소가 이미 실측한 사실이다:
/// 전체 스위트(1100+ 테스트)를 돌리면 @MainActor 테스트들이 메인 액터를 공유해 Task 시작이 수십 초 밀린다.
/// 짧게 잡으면 **결함이 아니라 부하** 때문에 빨개진다(내가 실제로 겪었다 — 1초 예산이 단독 실행에선
/// 통과하고 전체 실행에선 네 개가 빨개졌다). 조건이 참이면 즉시 반환하므로 빠른 경우의 비용은 0이다.
@MainActor
private func waitUntil(_ timeout: TimeInterval = 120, _ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 스토어가 띄운 비동기 작업이 **전부 끝났는가**. 부정형 단언("요청이 0건이다") 앞에 쓴다.
@MainActor
private func realtimeIdle(_ store: WorkTimerStore) -> Bool {
    store.drainInFlight == nil && store.realtime.catchUpTask == nil
}

private func sourceURL(_ name: String, in directory: String = "Sources/check") -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("\(directory)/\(name)")
}

private func sourceFiles() throws -> [URL] {
    let root = sourceURL("CheckApp.swift").deletingLastPathComponent()
    return try FileManager.default
        .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다. 문자열 리터럴 안의 `//` 는 남긴다.
private func strippingComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let iterator = Array(source)
    var index = 0
    while index < iterator.count {
        let c = iterator[index]
        let next: Character? = index + 1 < iterator.count ? iterator[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; index += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}
