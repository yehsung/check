import Foundation

// 초인종(Supabase Realtime Broadcast) 연결의 **상태 타입**.
//
// ── 이 파일의 현재 범위 (W1 seam) ──
// 여기 있는 것은 상태 어휘뿐이다. 링 본체(`RealtimeLink.apply(_:now:jitter:)` 와 effect 목록)와
// 전송자(RealtimeTransport)는 agent-realtime 이 이 파일에 이어 쓴다. 상태 타입을 먼저 심는 이유는
// 스토어가 `realtimeState` 를 **읽어서** 폴링을 재우기 때문이다 — 읽는 쪽이 쓰는 쪽보다 먼저 있어야
// 리얼타임을 통째로 빼도 나머지가 컴파일된다(사장님 확정 2).
//
// ── 채널명 규약 (설계 모순 해소 #1) ──
// 채널명은 접두사 **없는** `poke:<uid>` 다. Phoenix wire 의 topic 필드는 `realtime:poke:<uid>` 이고
// RLS 가 보는 `realtime.topic()` 은 접두사를 뗀 `poke:<uid>` 다 — 둘은 같은 것의 두 표현이다.
// 전송자가 프레임 조립 시점에 `realtime:` 를 붙인다. 서버 `public.poke_topic(uuid)` 의 반환값과
// **문자 그대로 같은 문자열**이어야 한다.

/// 초인종 링의 상태. **`.idle(.disabled)` 이 출시 기본값이다** — 전송자가 nil 이면(fail-closed)
/// 링은 여기서 한 발짝도 움직이지 않고, 그동안 폴링이 예전 그대로 돈다.
enum RealtimeState: Equatable, Sendable {
    case idle(IdleReason)
    case connecting(attempt: Int, since: Date)
    /// 구독 성공. `lastHeardAt` 은 **좀비 소켓 판정의 유일한 근거**다 —
    /// Wi-Fi 이탈·VPN 전환처럼 willSleep 이 안 오는 half-open TCP 에서 URLSessionWebSocketTask 는
    /// `.closed` 를 주지 않아, 이 값이 없으면 링이 영원히 subscribed 로 남고 회복 경로가 0이 된다.
    case subscribed(since: Date, lastHeardAt: Date)
    case reconnecting(Backoff)
    case failed(Backoff, RealtimeFailure)

    enum IdleReason: Equatable, Sendable {
        /// 로그아웃 상태.
        case signedOut
        /// 잠자기 등으로 스스로 내려놨다.
        case suspended
        /// 전송자가 없다(테스트·킬스위치·미배포). **출시 시점의 값이다.**
        case disabled
        /// 이 맥이 **찌르기를 받을 자격이 있는 근무 중이 아니다**(비근무이거나, 근무 중이어도 그 세션의
        /// 주인이 다른 맥이다). 로그아웃도 잠자기도 아니라서 새 사유를 따로 둔다 — 셋 중 아무것에나
        /// 접어 넣으면 `.willSleep`/`.didWake` 가 그 사유를 잘못 해석해 근무하지 않는 맥이 뚜껑을 열 때
        /// 소켓을 다시 올린다.
        ///
        /// **왜 근무 중에만 붙는가**: 서버의 세 함수(poke_user / ultra_poke_user / send_message)가 전부
        /// `target_not_working` 게이트를 갖는다(20260819030000_poke_economy_and_ring.sql:69, :156, :215).
        /// 근무 중이 아닌 사람은 **아무도 찌를 수 없으므로** 그때의 소켓은 받을 것이 원리적으로 없는
        /// 연결이고, 25초 하트비트만 태운다(무료 플랜 동시연결 200 / 메시지 200만·월).
        /// 폴링(`takePokesIfWorking`)이 이미 같은 눈금을 쓰고 있었다 — 리얼타임만 로그인 기준이던 것이
        /// 두 경로가 어긋나 있던 자리다.
        case notWorking
    }

    /// **폴링을 재우는 유일한 스위치.** 여기가 참일 때만 take_pokes 폴링이 쉰다.
    /// 다른 곳에 두 번째 판정을 만들지 마라 — 리얼타임이 반쯤 죽은 상태에서 폴링도 안 도는
    /// 완전한 침묵이 만들어지는 조합이 정확히 그거다.
    var isSubscribed: Bool {
        if case .subscribed = self { return true }
        return false
    }
}

/// 링이 스스로 회복하지 못하는 사유. 문구가 서로 **달라야** 한다 — 사용자가 할 수 있는 일이 다르다.
enum RealtimeFailure: Equatable, Sendable {
    /// 토큰이 거절됐다(강제 갱신 1회 뒤에도).
    case unauthorized
    /// 조인은 됐는데 RLS 가 채널을 거절했다 = **서버 설정 문제**(정책 미배포). 사용자가 할 수 있는 일이 없다.
    case topicDenied
    /// 재시도 예산을 다 썼다.
    case exhausted
}

/// 재연결 백오프. full jitter / base 1 / factor 2 / cap 30 / floor 0.25, 첫 시도는 지연 0.
struct Backoff: Equatable, Sendable {
    var attempt: Int
    var retryAt: Date
    /// 연속 실패가 **시작된** 시각. 실패 문구를 띄울지 판정하는 근거이고, 재시도마다 갱신되지 않는다.
    var failingSince: Date

    init(attempt: Int, retryAt: Date, failingSince: Date) {
        self.attempt = attempt
        self.retryAt = retryAt
        self.failingSince = failingSince
    }
}

enum RealtimeLinkConstants {
    /// 이 초를 넘겨 실패가 이어지면 화면이 경고를 띄운다. **자기 값이다 — 파생하지 마라.**
    /// ultraDisplayFreshnessSeconds(120)에서 파생하면 울트라 규칙이 바뀔 때마다 이 임계가 따라 흔들린다.
    static let failedAfterSeconds: TimeInterval = 45
    /// 소켓 하트비트 주기. **근무 하트비트(WorkTimerStore.heartbeatIntervalSeconds = 30)와 이름도 값도 다르다** —
    /// 같으면 반드시 혼동하고, 한쪽을 고칠 때 다른 쪽이 조용히 따라 바뀐다.
    static let heartbeatIntervalSeconds: TimeInterval = 25
    /// 이 횟수만큼 응답이 없으면 죽은 소켓으로 본다(25 × 2 = 50초 무응답).
    static let heartbeatMissesBeforeDead = 2

    /// 서버 `public.poke_topic(uuid)` 와 문자 그대로 같은 채널명을 만든다.
    static func pokeChannel(userID: String) -> String { "poke:\(userID)" }
}

// ─────────────────────────────────────────────────────────────────────────────
// 여기서부터가 agent-realtime(W2) 이 이어 쓴 **링 본체**다. 위쪽(상태 어휘)은 W1 이 심었다.
//
// 이 아래 코드의 규칙은 하나다: **I/O 0, Date() 0, Task 0, 난수 0.**
// 시각은 전부 `now:` 인자로 들어오고 지터는 주입된다. 그래서 "뚜껑을 두 시간 닫았다 열었다"가
// 벽시계 없이 함수 호출의 나열로 재현된다. 이 성질이 깨지면 좀비 소켓 판정은 영영 검증 불가능해진다
// (판정을 전송자 안에 숨기면 50초를 실제로 기다리는 테스트가 되고, 그런 테스트는 곧 지워진다).
// ─────────────────────────────────────────────────────────────────────────────

/// 전송자(소켓)가 링에게 알리는 사실. **명령이 아니라 관측이다.**
enum RealtimeTransportEvent: Equatable, Sendable {
    /// TCP/WS 연결이 열렸다. 조인은 아직이다 — 상태는 안 바뀌고 진단에만 남는다.
    case opened
    /// phx_join 이 status:"ok" 를 받았다. **캐치업이 발사되는 유일한 사실.**
    case joined
    case joinRejected(RealtimeJoinRejection)
    /// 브로드캐스트 1건. 페이로드는 신호뿐이라 이벤트 이름 하나면 충분하다(내용은 take_pokes 가 가져온다).
    case broadcast(event: String)
    /// 하트비트 응답. **좀비 소켓 판정의 유일한 양성 증거다.**
    case heartbeatAck
    /// 전송자가 스스로 감지한 하트비트 무응답. 링은 `.closed` 와 같게 다룬다 —
    /// 이 이벤트가 없어도(전송자가 감지를 못 해도) `.tick` 이 같은 결론에 도달해야 한다(이중 안전망).
    case heartbeatTimedOut
    case closed(code: Int?)
}

/// 조인 거절의 두 종류. **이 구분이 사라지면 서버 미배포(topicDenied)가 "네트워크 문제"로 보인다.**
enum RealtimeJoinRejection: Equatable, Sendable {
    /// "Token has expired" / InvalidJWTToken. 강제 갱신 1회로 나을 수 있다.
    case expiredToken
    /// realtime.messages RLS 가 토픽을 거절했다. 재시도로는 **절대** 안 낫는다(서버 정책 미배포).
    case unauthorized
    case unknown(String)
}

/// 링을 움직이는 사건. 전송자 이벤트는 `.transport` 로 감싸 들어온다.
enum RealtimeEvent: Equatable, Sendable {
    case signedIn(accessToken: String)
    case signedOut
    case willSleep
    case didWake
    case transport(RealtimeTransportEvent)
    /// 백오프 타이머가 만료됐다.
    case backoffElapsed
    /// 주기 점검. **`now` 를 싣지 않는다** — 시각은 `apply(_:now:jitter:)` 의 인자 하나가 유일한 출처다.
    /// 두 곳에서 오면 반드시 어긋나고, 어긋난 쪽이 좀비 판정을 조용히 무력화한다.
    case tick
    case tokenRefreshed(accessToken: String)
    /// fatal = 이 세션은 끝났다(refresh token 이 무효). false = 일시 실패(네트워크).
    case tokenRefreshFailed(fatal: Bool)
    /// 이 맥의 근무가 끝났다(종료·자동 마감·서버가 세션을 닫음·다른 맥에 세션을 넘겨줌).
    ///
    /// **`.signedOut` 과 다른 점은 accessToken 을 지우지 않는다는 것 하나다.** 로그아웃이 아니므로
    /// 토큰은 여전히 유효하고, 근무를 다시 시작하면 `startRealtimeIfPossible()` 이 그 토큰으로 곧바로
    /// 붙는다. 여기서 지우면 근무를 껐다 켤 때마다 세션을 다시 읽어야 하고, 그 사이 `beginConnecting`
    /// 이 토큰 없음을 보고 `.idle(.signedOut)` 으로 떨어뜨려 로그인하지 않은 것처럼 보인다.
    case workEnded
}

/// 링이 스토어에게 **시키는 일**. 링은 스스로 아무것도 하지 않는다.
enum RealtimeEffect: Equatable, Sendable {
    case connect(accessToken: String)
    case disconnect
    case scheduleRetry(at: Date)
    case cancelRetry
    /// 구독 직후 1회 따라잡기. **폴백이 아니라 정확성이다** — 근거는 `catchUpAfterSubscribe` 주석.
    case catchUp
    /// 브로드캐스트를 받았다 → take_pokes 1회(직렬화는 requestDrain 이 한다).
    case drain
    case pushAccessToken(String)
    case scheduleTokenRefresh(at: Date)
    /// 강제 갱신(만료 토큰 조인 거절 직후). force=true 는 "예정보다 앞당겨서라도 지금".
    case refreshToken(force: Bool)
    case sendHeartbeat
}

/// 재연결 지연 정책. **full jitter**(AWS 권장형): delay = max(floor, jitter(0...ceiling)).
///
/// 왜 full jitter 인가: 38명이 같은 AP 를 쓰거나 Supabase Realtime 이 재배포되면 전원이 같은 밀리초에
/// 끊긴다. 고정 지수면 38개 재조인이 1초 지점에 뭉치고, 서버가 그 뭉치를 밀어내면 다음 뭉치가 2초 지점에
/// **더 크게** 뭉친다(자기충족적 장애 루프). full jitter 는 attempt 가 오를수록 분포 폭이 넓어져
/// 서버가 보는 초당 조인율이 내려간다.
struct BackoffPolicy: Equatable, Sendable {
    var base: TimeInterval = 1.0
    var factor: Double = 2.0
    /// 옛 팀 상태 폴링 주기와 **같은 눈금**이다. 최악 지연이 옛 폴링보다 나쁘면
    /// "리얼타임으로 바꿨더니 더 느려졌다"가 된다.
    var cap: TimeInterval = 30.0
    /// full jitter 는 0 에 가까운 값을 뽑을 수 있어, 소켓이 정리되기 전에 재시도가 나간다.
    var floor: TimeInterval = 0.25

    static let `default` = BackoffPolicy()

    /// ceiling 수열: 1, 2, 4, 8, 16, 30, 30, …
    func delay(attempt: Int, jitter: (Double) -> Double) -> TimeInterval {
        let ceiling = min(cap, base * pow(factor, Double(max(0, attempt - 1))))
        return max(floor, jitter(ceiling))
    }
}

/// 초인종 링. **값 타입이고 동기이며 순수하다.**
struct RealtimeLink: Equatable, Sendable {
    private(set) var state: RealtimeState
    var policy: BackoffPolicy = .default

    /// 마지막으로 알려진 access token. 뚜껑을 열었을 때 다시 붙으려면 링이 이걸 기억해야 한다
    /// (didWake 는 토큰을 실어 오지 않는다). nil 이면 붙을 수 없다 = 로그아웃과 같다.
    private(set) var accessToken: String?

    /// **연속 실패 구간의 시작.** `connecting` 케이스에는 이 값을 담을 자리가 없어서(그 타입은 W1 이
    /// 심었고 UI 가 이미 패턴 매칭한다) 링이 따로 든다. 이 값이 뚜껑을 열 때마다 사라지는 것이
    /// "재연결중 ≠ 실패"의 실체다 — 없으면 맥북 사용자는 하루 수십 번 빨간 글씨를 본다.
    private(set) var failingSince: Date?

    /// 이번 연결 시도에서 만료토큰 강제 갱신을 이미 한 번 썼는가. **시도당 1회**다.
    /// 무제한이면 만료가 아닌 원인으로 거절될 때 갱신 폭풍이 되고, 0회면 뚜껑 3시간 닫고 연 사용자가
    /// **항상** 즉시 `.unauthorized` 로 떨어진다(그 경로가 정상 경로다).
    private(set) var forcedRefreshUsedThisAttempt = false

    /// 마지막으로 하트비트를 **보낸** 시각. 보낸 적 없으면 nil.
    private(set) var lastHeartbeatSentAt: Date?

    /// 전송자가 없는 프로세스(테스트·킬스위치 off·미배포)는 `.idle(.disabled)` 로 태어나고
    /// **그 상태를 절대 벗어나지 않는다.** `.disabled` 에서 connecting 으로 가면 `.closed` 가 영영 안 와
    /// 영구 connecting = 영구 침묵이 된다(그동안 폴링은 `isSubscribed == false` 라 정상적으로 돈다).
    init(transportAvailable: Bool = false) {
        state = transportAvailable ? .idle(.signedOut) : .idle(.disabled)
    }

    /// 지금 예약된 재시도 시각(있으면).
    var retryAt: Date? {
        switch state {
        case .reconnecting(let b), .failed(let b, _): return b.retryAt
        default: return nil
        }
    }

    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    /// 전송자가 아예 없는 프로세스인가. 진단에서 "조립 실패(가장 조용한 결말)"를 가르는 값이다.
    var isDisabled: Bool { state == .idle(.disabled) }

    /// 선제 토큰 갱신 시각. **exp - 300초**, 단 하한 now+30초(이미 만료 임박한 토큰으로 부팅한 경우의 폭주 방지).
    /// exp 를 못 읽으면 **50분 고정**이다 — nil 은 '모른다'이지 '만료'가 아니므로(JWTClaims 주석)
    /// 여기서 즉시 갱신을 걸면 GoTrue 형식이 바뀌는 날 38명이 한꺼번에 갱신 폭풍을 일으킨다.
    static let tokenRefreshLeadSeconds: TimeInterval = 300
    static let tokenRefreshMinDelaySeconds: TimeInterval = 30
    static let tokenRefreshFallbackSeconds: TimeInterval = 3000
    /// phx_join 응답이 이 초를 넘게 안 오면 죽은 시도로 본다.
    /// **설계에 없던 가드다**(추가 근거는 파일 하단 주석). half-open TCP 는 `.closed` 를 주지 않으므로
    /// 이것이 없으면 `connecting` 이 영원히 유지되고, `.tick` 의 좀비 판정은 `.subscribed` 만 보므로
    /// 회복 경로가 0이 된다 — blocker(리얼타임 #1)와 정확히 같은 고장을 한 상태 앞에서 다시 만든다.
    static let joinTimeoutSeconds: TimeInterval = 15

    static func tokenRefreshDate(accessToken: String, now: Date) -> Date {
        guard let expiry = JWTClaims.expiry(accessToken: accessToken) else {
            return now.addingTimeInterval(tokenRefreshFallbackSeconds)
        }
        return max(now.addingTimeInterval(tokenRefreshMinDelaySeconds),
                   expiry.addingTimeInterval(-tokenRefreshLeadSeconds))
    }

    // MARK: - 전이

    /// **동기 순수 함수.** async 아님, Task 안 만듦, Date() 안 읽음.
    mutating func apply(_ event: RealtimeEvent, now: Date, jitter: (Double) -> Double) -> [RealtimeEffect] {
        // 전송자가 없는 프로세스는 무엇을 넣어도 움직이지 않는다. 토큰만 기억해 둔다(킬스위치를 켜고
        // 재실행하면 정상 경로를 타므로 상태를 오염시키지 않는 편이 낫다).
        if case .idle(.disabled) = state {
            if case .signedIn(let token) = event { accessToken = token }
            if case .signedOut = event { accessToken = nil }
            return []
        }

        switch event {
        case .signedIn(let token):
            accessToken = token
            return beginConnecting(attempt: 1, now: now, resetFailure: true)

        case .signedOut:
            accessToken = nil
            failingSince = nil
            state = .idle(.signedOut)
            return [.disconnect, .cancelRetry]

        case .willSleep:
            // 로그아웃/비근무 상태에서 뚜껑을 닫아도 `.suspended` 가 되면 안 된다 — 그러면 wake 가
            // 로그인 없이(또는 근무하지 않는 채로) 연결을 시도한다. `.disabled` 는 위에서 이미 걸렀다.
            // `if case` 두 줄이 아니라 망라 switch 인 이유: IdleReason 이 또 넓어지는 날 컴파일러가
            // **이 자리**를 짚어 줘야 한다(사유를 하나 빠뜨린 채 suspended 로 접히는 것이 이 파일에서
            // 가장 조용한 결함이다).
            switch state {
            case .idle(.signedOut), .idle(.notWorking):
                return []
            case .idle(.suspended), .idle(.disabled), .connecting, .subscribed, .reconnecting, .failed:
                break
            }
            failingSince = nil
            state = .idle(.suspended)
            return [.disconnect, .cancelRetry]

        case .didWake:
            switch state {
            case .idle(.suspended):
                guard accessToken != nil else {
                    state = .idle(.signedOut)
                    return [.disconnect, .cancelRetry]
                }
                // 뚜껑을 몇 시간 닫았든 실패 시계는 **여기서 새로 시작한다**. 그래서 "뚜껑 열 때마다
                // 빨간 오류"가 표현 불가능하다.
                return beginConnecting(attempt: 1, now: now, resetFailure: true)
            case .reconnecting(var b):
                // 네트워크가 방금 돌아왔을 가능성이 가장 높은 순간이다. 백오프를 당긴다(초기화는 아니다 —
                // 실패 시계는 유지해야 진짜 장애가 계속 승격된다).
                b.retryAt = now
                state = .reconnecting(b)
                return [.scheduleRetry(at: now)]
            case .failed(var b, let reason):
                b.retryAt = now
                state = .failed(b, reason)
                return [.scheduleRetry(at: now)]
            default:
                return []
            }

        case .transport(let transportEvent):
            return applyTransport(transportEvent, now: now, jitter: jitter)

        case .backoffElapsed:
            switch state {
            case .reconnecting(let b), .failed(let b, _):
                guard accessToken != nil else {
                    state = .idle(.signedOut)
                    return [.disconnect, .cancelRetry]
                }
                return beginConnecting(attempt: b.attempt, now: now, resetFailure: false)
            default:
                return []
            }

        case .tick:
            return applyTick(now: now, jitter: jitter)

        case .tokenRefreshed(let token):
            accessToken = token
            let refreshAt = Self.tokenRefreshDate(accessToken: token, now: now)
            switch state {
            case .subscribed:
                // **재연결하지 않는다.** 재연결하면 1시간마다 소켓이 끊기는 것이 정상이 되어
                // 진짜 장애와 구분이 안 된다(그리고 캐치업이 헛돈다).
                return [.pushAccessToken(token), .scheduleTokenRefresh(at: refreshAt)]
            case .connecting(let attempt, _):
                // 옛 토큰으로 나간 조인을 기다리지 않는다 — 그건 확정적으로 거절된다.
                state = .connecting(attempt: attempt, since: now)
                forcedRefreshUsedThisAttempt = false
                return [.disconnect, .connect(accessToken: token), .scheduleTokenRefresh(at: refreshAt)]
            case .reconnecting(var b):
                b.retryAt = now
                state = .reconnecting(b)
                return [.scheduleRetry(at: now), .scheduleTokenRefresh(at: refreshAt)]
            case .failed(var b, let reason):
                // 만료가 원인이었다면 즉시 낫는다. topicDenied 라면 어차피 또 거절되지만,
                // 그 재시도는 cap 간격이라 비용이 없다.
                b.retryAt = now
                state = .failed(b, reason)
                return [.scheduleRetry(at: now), .scheduleTokenRefresh(at: refreshAt)]
            case .idle:
                return []
            }

        case .tokenRefreshFailed(let fatal):
            guard fatal else { return [] }
            accessToken = nil
            failingSince = nil
            state = .idle(.signedOut)
            return [.disconnect, .cancelRetry]

        case .workEnded:
            switch state {
            case .idle(.notWorking), .idle(.disabled):
                // 이미 그 자리다. `.disabled` 는 위에서 이미 걸러 여기 오지 않지만, 사유가 늘어나는 날
                // 컴파일러가 짚어 주려면 자리를 비워 둘 수 없다.
                return []
            case .idle(.signedOut), .idle(.suspended):
                // 소켓은 이미 내려가 있다 — **사유만** 정정한다(effect 는 비운다). 죽은 소켓에 대고
                // disconnect 를 되풀이하면 진단 로그가 그 반복으로 덮인다.
                // 이 정정이 필요한 이유: 근무 게이트에 막혀 한 번도 출발하지 못한 링은 `.idle(.signedOut)`
                // 인 채로 남는데, 그러면 로그인해 둔 사용자의 설정 창이 "로그아웃"이라고 말한다.
                // `.suspended` 에서 오는 경우는 더 중요하다 — 정정하지 않으면 `.didWake` 가 근무하지도
                // 않는 맥의 소켓을 다시 올린다.
                state = .idle(.notWorking)
                return []
            case .connecting, .subscribed, .reconnecting, .failed:
                break
            }
            // **accessToken 은 남긴다**(위 `.workEnded` 주석). 실패 시계만 접는다 — 근무를 다시 시작하면
            // 그것은 새 연결 구간이고, 옛 실패를 물려받으면 시작하자마자 빨간 글씨가 뜬다.
            failingSince = nil
            state = .idle(.notWorking)
            return [.disconnect, .cancelRetry]
        }
    }

    // MARK: - 내부

    private mutating func applyTransport(
        _ event: RealtimeTransportEvent,
        now: Date,
        jitter: (Double) -> Double
    ) -> [RealtimeEffect] {
        switch event {
        case .opened:
            return []

        case .joined:
            guard case .connecting = state else { return [] }
            failingSince = nil
            forcedRefreshUsedThisAttempt = false
            lastHeartbeatSentAt = nil
            state = .subscribed(since: now, lastHeardAt: now)
            // **정확히 이 한 줄이 캐치업 발사 지점의 전부다.** 다른 어떤 전이에서도 쏘지 않는다.
            return [.catchUp]

        case .joinRejected(let rejection):
            guard case .connecting(let attempt, _) = state else { return [] }
            switch rejection {
            case .expiredToken:
                if !forcedRefreshUsedThisAttempt {
                    forcedRefreshUsedThisAttempt = true
                    // 상태를 유지한다 — 갱신이 오면 `.tokenRefreshed` 가 조인을 다시 건다.
                    return [.refreshToken(force: true)]
                }
                return promote(.unauthorized, failedAttempt: attempt, now: now, jitter: jitter)
            case .unauthorized:
                // **재시도로 안 풀린다.** 그래도 백오프는 cap 간격으로 계속 돈다 —
                // 서버 마이그레이션이 배포되는 순간 사용자 조작 없이 스스로 낫는다.
                return promote(.topicDenied, failedAttempt: attempt, now: now, jitter: jitter, forcedDelay: policy.cap)
            case .unknown:
                return dropToReconnecting(failedAttempt: attempt, now: now, jitter: jitter)
            }

        case .broadcast:
            guard case .subscribed(let since, _) = state else { return [] }
            // 어떤 트래픽이든 소켓이 살아 있다는 증거다(하트비트 응답만 증거로 삼으면 바쁜 소켓이
            // 하트비트 창을 놓쳤을 때 멀쩡한 연결을 끊는다).
            state = .subscribed(since: since, lastHeardAt: now)
            return [.drain]

        case .heartbeatAck:
            guard case .subscribed(let since, _) = state else { return [] }
            state = .subscribed(since: since, lastHeardAt: now)
            return []

        case .heartbeatTimedOut, .closed:
            switch state {
            case .connecting(let attempt, _):
                return dropToReconnecting(failedAttempt: attempt, now: now, jitter: jitter)
            case .subscribed:
                return dropToReconnecting(failedAttempt: 0, now: now, jitter: jitter)
            case .reconnecting, .failed, .idle:
                return []
            }
        }
    }

    private mutating func applyTick(now: Date, jitter: (Double) -> Double) -> [RealtimeEffect] {
        switch state {
        case .subscribed(let since, let lastHeardAt):
            let silence = now.timeIntervalSince(lastHeardAt)
            // ★ blocker(리얼타임 #1) — 좀비 소켓. Wi-Fi 이탈·VPN 전환의 half-open TCP 는
            //   `.closed` 를 **주지 않는다**. 폴백을 지운 구성에서 이 판정이 없으면 링은 영원히
            //   subscribed 로 남고(그래서 폴링도 안 돈다) 회복 경로가 0이 된다.
            if silence > RealtimeLinkConstants.heartbeatIntervalSeconds
                * Double(RealtimeLinkConstants.heartbeatMissesBeforeDead) {
                var effects: [RealtimeEffect] = [.disconnect]
                effects.append(contentsOf: dropToReconnecting(failedAttempt: 0, now: now, jitter: jitter))
                return effects
            }
            let sentAgo = lastHeartbeatSentAt.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
            if sentAgo >= RealtimeLinkConstants.heartbeatIntervalSeconds {
                lastHeartbeatSentAt = now
                state = .subscribed(since: since, lastHeardAt: lastHeardAt)
                return [.sendHeartbeat]
            }
            return []

        case .connecting(let attempt, let since):
            guard now.timeIntervalSince(since) > Self.joinTimeoutSeconds else { return [] }
            var effects: [RealtimeEffect] = [.disconnect]
            effects.append(contentsOf: dropToReconnecting(failedAttempt: attempt, now: now, jitter: jitter))
            return effects

        case .reconnecting(let b):
            // 실패 승격 기준은 **시도 횟수가 아니라 연속 실패 지속 시간**이다. Wi-Fi 재결합은 보통
            // 2~15초 걸리고 그 사이 시도는 몇 번이고 실패한다 — 횟수로 잡으면 뚜껑을 열 때마다 빨간 글씨다.
            guard now.timeIntervalSince(b.failingSince) > RealtimeLinkConstants.failedAfterSeconds else { return [] }
            state = .failed(b, .exhausted)
            return []

        case .failed, .idle:
            // `.failed` 는 스스로 내려오지 않는다. 내려오는 길은 `.joined` 하나다.
            return []
        }
    }

    private mutating func beginConnecting(attempt: Int, now: Date, resetFailure: Bool) -> [RealtimeEffect] {
        guard let token = accessToken else {
            state = .idle(.signedOut)
            return [.disconnect, .cancelRetry]
        }
        if resetFailure { failingSince = nil }
        forcedRefreshUsedThisAttempt = false
        lastHeartbeatSentAt = nil
        state = .connecting(attempt: max(1, attempt), since: now)
        return [.connect(accessToken: token),
                .scheduleTokenRefresh(at: Self.tokenRefreshDate(accessToken: token, now: now))]
    }

    /// 실패한 시도를 백오프로 내린다.
    ///
    /// `failedAttempt` 는 **방금 실패한 시도 번호**다(구독 중 끊김은 0 — 시도가 실패한 게 아니라
    /// 성공해 있던 연결이 죽은 것이라 다음 재시도를 가장 짧게 잡는다). 지연은 그 번호로 계산하고
    /// 다음 시도 번호는 +1 이다 — 둘을 같은 수로 쓰면 첫 실패의 지연이 2초가 되어 수열이 통째로 밀린다.
    private mutating func dropToReconnecting(
        failedAttempt: Int,
        now: Date,
        jitter: (Double) -> Double
    ) -> [RealtimeEffect] {
        let start = failingSince ?? now
        failingSince = start
        let delay = policy.delay(attempt: max(1, failedAttempt), jitter: jitter)
        let retryAt = now.addingTimeInterval(delay)
        state = .reconnecting(Backoff(attempt: max(1, failedAttempt + 1), retryAt: retryAt, failingSince: start))
        return [.scheduleRetry(at: retryAt)]
    }

    private mutating func promote(
        _ reason: RealtimeFailure,
        failedAttempt: Int,
        now: Date,
        jitter: (Double) -> Double,
        forcedDelay: TimeInterval? = nil
    ) -> [RealtimeEffect] {
        let start = failingSince ?? now
        failingSince = start
        let delay = forcedDelay ?? policy.delay(attempt: max(1, failedAttempt), jitter: jitter)
        let retryAt = now.addingTimeInterval(delay)
        state = .failed(Backoff(attempt: max(1, failedAttempt + 1), retryAt: retryAt, failingSince: start), reason)
        return [.scheduleRetry(at: retryAt)]
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 설계와 다르게 만든 것 3가지 (전부 의도적이고, 각각 이유가 있다)
//
// ① `.tick(now)` 이 아니라 `.tick`.
//    `apply(_:now:jitter:)` 가 이미 시각을 받는다. 이벤트에도 실으면 같은 사실의 출처가 둘이 되고,
//    둘이 어긋나는 날 좀비 판정이 조용히 무력화된다(어긋남을 알려 줄 테스트가 없다).
//
// ② `connecting` 에 조인 타임아웃(15초)을 넣었다.
//    설계 전이표에는 `connecting` 을 빠져나오는 길이 joined / closed / joinRejected 셋뿐인데,
//    half-open TCP 는 그 셋을 **하나도** 주지 않는다. blocker(리얼타임 #1)가 `.subscribed` 에서 찾아낸
//    바로 그 고장이 `.connecting` 에도 있다. 없으면 "뚜껑 열고 Wi-Fi 가 아직 안 붙은" 흔한 상황에서
//    링이 영구 connecting 으로 굳는다.
//
// ③ `failingSince` 를 링이 따로 든다.
//    설계는 Backoff 안에만 뒀는데, `connecting` 케이스에는 Backoff 가 없다(그 타입은 W1 이 심었고
//    UI 가 이미 패턴 매칭한다). reconnecting → connecting → closed 로 도는 동안 실패 시계가 매번
//    리셋되면 `.exhausted` 승격이 영영 일어나지 않는다.
// ─────────────────────────────────────────────────────────────────────────────
