import Foundation

// 초인종 링을 **스토어에 배선**하는 곳. 링(RealtimeLink)은 순수하고, 소켓(RealtimeTransport)은 무지하며,
// 둘 사이에서 시간을 만들고 네트워크를 부르는 유일한 계층이 여기다.
//
// 이 파일이 지키는 계약 3개:
//  ① 링에게 시각을 주는 것은 `realtimeApply(_:at:)` 하나다(다른 곳에서 Date() 를 읽어 링에 넣지 마라).
//  ② effect 실행은 `run(_:now:)` 하나를 지난다(effect 마다 호출부가 흩어지면 어떤 effect 가 죽었는지 아무도 모른다).
//  ③ take_pokes 로 가는 문은 `realtimeMayConsumePokes` 하나다(blocker 리얼타임 #5).

/// 리얼타임 한 벌의 **수명 소유자**. 스토어에 저장 프로퍼티를 일곱 개 흩뿌리는 대신 하나로 든다 —
/// 로그아웃/잠자기에서 "타이머 하나를 안 껐다"가 이 계층에서 가장 흔한 누수이고, 한 덩어리면 셀 수 있다.
@MainActor
final class RealtimeRuntime {
    /// **기본값이 없다.** nil = 리얼타임 없음(fail-closed). 프로덕션 조립(CheckApp)에서만 값이 들어온다.
    let transport: RealtimeTransport?
    var link: RealtimeLink
    var diagnostics = RealtimeDiagnostics()
    var retryTask: Task<Void, Never>?
    var tokenRefreshTask: Task<Void, Never>?
    var tickTask: Task<Void, Never>?
    var catchUpTask: Task<Void, Never>?
    /// onEvent 배선을 두 번 걸지 않기 위한 도장(startStatusRefreshLoop 는 idempotent 해야 한다).
    var wired = false
    /// 구독은 했는데 **근무중 게이트에 막혀** 따라잡기를 못 돌린 상태인가.
    ///
    /// v0.2.34 의 근무 게이트가 이 창을 크게 줄였지만 **없애지는 못한다**: 조인은 근무 중에 나가는데
    /// 응답이 오기까지의 몇 초 사이에 폴링이 "이 세션의 주인은 다른 맥"(adoptedRemoteSession)이라고
    /// 알려 올 수 있고, 그러면 도착한 `.joined` 의 따라잡기가 게이트에 막힌다. 재구독은 다시 일어나지
    /// 않으므로(그 링은 이미 subscribed 다) 잊으면 그 구간의 밀린 찌르기는 회수 경로가 0이다.
    var catchUpDeferred = false

    init(transport: RealtimeTransport?) {
        self.transport = transport
        // 전송자가 없으면 링은 `.idle(.disabled)` 로 태어나 **한 발짝도 움직이지 않는다**.
        self.link = RealtimeLink(transportAvailable: transport != nil)
    }

    var transportAvailable: Bool { transport != nil }

    /// 로그아웃/종료에서 부른다. 타이머를 하나라도 남기면 다음 계정 세션에 옛 이벤트가 흘러든다.
    func cancelTimers() {
        catchUpDeferred = false
        retryTask?.cancel(); retryTask = nil
        tokenRefreshTask?.cancel(); tokenRefreshTask = nil
        catchUpTask?.cancel(); catchUpTask = nil
    }
}

/// 설정 창 진단. "찌르기가 안 와요" 신고에서 **소켓/캐치업/토큰 중 어디인지**를 사용자 화면에서 즉시 가른다.
struct RealtimeDiagnostics: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let at: Date
        let from: String
        let to: String
        let cause: String
    }
    /// 최근 전이 10건(링 버퍼).
    var recent: [Entry] = []
    var totalReconnects = 0
    var lastCatchUpAt: Date?
    var lastCatchUpCount = 0
    /// 마지막 따라잡기가 **몇 번 시도했는가**. 재시도를 지워도 요청 수만 보면 스텁 호스트를 공유하는
    /// 다른 스위트와 섞여 흔들린다 — 시도 횟수는 링 밖에서 셀 수 없으므로 여기 남긴다.
    var lastCatchUpAttempts = 0
    var lastCatchUpFailure: String?
    /// 전송자가 아예 없는가. **`.idle(.disabled)` 이 가장 조용한 결말이라 따로 남긴다** —
    /// 조립 실패와 킬스위치 off 는 화면에서 똑같이 "아무 일도 안 일어남"으로 보인다.
    var transportAvailable = false

    static let recentLimit = 10

    mutating func record(from: RealtimeState, to: RealtimeState, cause: String, at: Date) {
        guard from != to else { return }
        append(Entry(at: at, from: Self.label(from), to: Self.label(to), cause: cause))
        if case .reconnecting = to { totalReconnects += 1 }
    }

    /// 상태 전이가 **아닌** 사실을 남긴다(토큰 추월 등). record 는 from == to 를 버리므로 그쪽으로는 못 남긴다 —
    /// 그 구분이 없으면 "왜 옛 토큰으로 붙었나" 같은 질문에 답할 근거가 통째로 사라진다.
    mutating func note(_ cause: String, state: RealtimeState, at: Date) {
        let label = Self.label(state)
        append(Entry(at: at, from: label, to: label, cause: cause))
    }

    private mutating func append(_ entry: Entry) {
        recent.append(entry)
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
    }

    static func label(_ state: RealtimeState) -> String {
        switch state {
        case .idle(.signedOut): return "idle(signedOut)"
        case .idle(.suspended): return "idle(suspended)"
        case .idle(.disabled): return "idle(disabled)"
        case .idle(.notWorking): return "idle(notWorking)"
        case .connecting(let attempt, _): return "connecting(\(attempt))"
        case .subscribed: return "subscribed"
        case .reconnecting(let b): return "reconnecting(\(b.attempt))"
        case .failed(_, let reason): return "failed(\(reason))"
        }
    }
}

@MainActor
extension WorkTimerStore {
    /// 캐치업 재시도 사이 간격. **시도는 3회다.**
    ///
    /// 예산 근거: takePokes 는 PGRST202 폴백 때문에 1회가 최대 2요청이고 요청 타임아웃이 15초다
    /// (SupabaseWorkService.swift:23). 최악 90초가 wake 직후에 몰리므로 여기서 끊는다.
    /// (설계 원안은 `[1,2,4]` 를 실패마다 잔다고 적었는데, 마지막 실패 뒤의 4초는 아무도 기다리지 않는
    ///  순수 지연이라 **사이 간격만** 남겼다 — 시도 횟수 3은 그대로다.)
    nonisolated static var catchUpRetryDelays: [TimeInterval] { [1, 2] }
    nonisolated static var catchUpAttempts: Int { 3 }
    /// 링에게 `.tick` 을 넣는 주기. 하트비트 주기(25초)보다 촘촘해야 25초 눈금을 놓치지 않는다.
    nonisolated static var realtimeTickIntervalSeconds: TimeInterval { 5 }

    // MARK: - 진입점

    /// 로그인/활성화 지점과 **근무 시작 지점**에서 부른다(idempotent).
    /// 전송자가 없으면(킬스위치 off·테스트) **아무 일도 하지 않는다** — 그동안 폴링이 예전 그대로 돈다.
    func startRealtimeIfPossible() {
        guard let activeSession = session else { return }
        realtime.diagnostics.transportAvailable = realtime.transportAvailable
        // anon 키가 없으면 소켓 URL 자체를 만들 수 없다. 링을 출발시키면 조인 타임아웃 → 재연결을
        // 영원히 반복하는 빈 루프가 된다(그 사이 폴링은 정상적으로 돈다 — isSubscribed 가 거짓이므로).
        guard let transport = realtime.transport, service.anonKey != nil else { return }
        // ★ 근무 게이트(v0.2.34). 판정은 폴링과 **같은 것 하나**(realtimeMayConsumePokes = startedAt != nil
        //   && !adoptedRemoteSession)를 쓴다 — takePokesIfWorking 이 이미 그 조건인데 리얼타임만 로그인
        //   기준으로 붙어 있던 것이 두 경로가 어긋나 있던 자리다.
        //
        //   왜 근무 중에만인가: 서버의 poke_user / ultra_poke_user / send_message 가 전부
        //   `target_not_working` 게이트를 갖는다 — 근무 중이 아닌 사람은 아무도 찌를 수 없으므로,
        //   비근무 소켓은 받을 것이 원리적으로 없는 연결이고 25초 하트비트만 태운다.
        //   흡수 세션(다른 맥이 주인)에서 붙지 않는 것은 blocker(리얼타임 #5)의 **더 강한 형태**다:
        //   소비를 게이트로 막는 대신 아예 신호를 받지 않는다.
        guard realtimeMayConsumePokes else {
            // 막혔다는 **사실을 남긴다.** 조용히 반환하면 realtimeState 가 초기값 `.idle(.disabled)` 에
            // 머물러, 설정 창 진단이 로그인해 둔 사용자에게 "전송자 없음"과 같은 라벨을 보여 준다 —
            // 이 저장소가 가장 경계하는 '조용한 결말'의 표시가 정확히 그것이다.
            realtimeApply(.workEnded)
            return
        }
        if !realtime.wired {
            realtime.wired = true
            transport.onEvent = { [weak self] event in
                self?.realtimeApply(.transport(event))
            }
            startRealtimeTicker()
        }
        realtimeApply(.signedIn(accessToken: activeSession.accessToken))
    }

    /// 링을 **지금의 근무 상태에 되맞춘다.** 주기 새로고침 루프가 팀 상태를 반영한 직후에 부른다.
    ///
    /// 근무 상태를 바꾸는 경로는 start()/stop() 만이 아니다: 앱 재시작 복구·다른 맥이 연 세션 흡수·
    /// 서버가 세션을 닫음(applyRemoteOwnStatus)·자동 마감이 전부 startedAt / adoptedRemoteSession 을
    /// 뒤집는다. 그 경로마다 링 이벤트를 흩뿌리면 **앞으로 생길 경로가 조용히 빠진다** — 이 저장소가
    /// 자동 마감 가드에서 이미 겪은 모양이라(autoStop 의 흡수 세션 가드 주석) 되맞춤을 한 곳에 둔다.
    func reconcileRealtimeWithWorkState() {
        guard realtimeMayConsumePokes else {
            // 이미 내려가 있으면 링이 스스로 no-op 이다(`.workEnded` 의 idle 가지). 그래서 여기에
            // 두 번째 판정을 두지 않는다 — 두 곳이 어긋나는 순간 한쪽이 조용히 거짓말한다.
            realtimeApply(.workEnded)
            return
        }
        // 근무 게이트가 열렸다. **`.idle(.notWorking)` 에서만** 다시 올린다 — 다른 사유는 각자 주인이
        // 따로 있고(signedOut ← 로그아웃, suspended ← 뚜껑, disabled ← 전송자 없음), 여기서 함께
        // 되살리면 뚜껑을 닫아 둔 맥이 근무 중이라는 이유로 소켓을 다시 연다.
        guard realtime.link.state == .idle(.notWorking) else { return }
        startRealtimeIfPossible()
    }

    /// 링에 사건을 넣고 나온 effect 를 실행한다. **스토어가 링에 시각을 주는 유일한 문.**
    func realtimeApply(_ event: RealtimeEvent, at now: Date = Date()) {
        let before = realtime.link.state
        let effects = realtime.link.apply(event, now: now, jitter: Self.realtimeJitter)
        let after = realtime.link.state
        realtime.diagnostics.record(from: before, to: after, cause: Self.cause(of: event), at: now)
        // **화면이 읽는 값은 여기서만 쓴다.** 다른 곳에서 realtimeState 를 직접 대입하면
        // 링의 상태와 화면의 상태가 갈리고, 갈린 순간 폴링 억제 판정이 거짓말한다.
        // `!=` 가드인 이유는 @Observable 이다: 같은 값 대입도 관찰자를 발화시키는데, 이 문은 5초 티커의
        // `.tick` 과 주기 되맞춤의 `.workEnded` 로 **상태가 안 바뀌는 호출**을 훨씬 자주 받는다.
        if realtimeState != after { realtimeState = after }
        run(effects, now: now)
    }

    /// full jitter 의 난수원. 링은 순수해야 하므로 난수는 **주입**이다.
    nonisolated static let realtimeJitter: @Sendable (Double) -> Double = { ceiling in
        ceiling <= 0 ? 0 : Double.random(in: 0...ceiling)
    }

    /// 초인종/캐치업이 take_pokes 로 갈 수 있는가. **게이트는 여기 하나다.**
    ///
    /// ★ blocker(리얼타임 #5): 초인종은 두 맥 모두에 도착하는데 work_sessions_one_open_per_user 때문에
    ///   회사 맥이 근무중이면 집 맥은 확정적으로 비근무다. 집 맥이 take_pokes 를 쏘면 단일
    ///   UPDATE…RETURNING 이 한쪽만 이기게 하므로 **회사 맥에는 아무것도 안 오고**, 집 맥은
    ///   CheckOverlayWindow 의 peek 경로가 shouldBeVisible 게이트를 안 보므로 8초짜리 팝업을 띄운다.
    ///   흡수 세션도 같은 이유로 막는다 — 그 세션의 주인은 다른 맥이다.
    var realtimeMayConsumePokes: Bool {
        startedAt != nil && !adoptedRemoteSession
    }

    // MARK: - effect 실행

    private func run(_ effects: [RealtimeEffect], now: Date) {
        for effect in effects {
            switch effect {
            case .connect(let linkToken):
                performRealtimeConnect(linkToken: linkToken)
            case .disconnect:
                realtime.transport?.disconnect()
            case .scheduleRetry(let at):
                scheduleRealtimeRetry(at: at, now: now)
            case .cancelRetry:
                realtime.retryTask?.cancel()
                realtime.retryTask = nil
            case .catchUp:
                startCatchUp()
            case .drain:
                // 근무중 게이트를 지난 뒤에만 소비한다. 여기서 requestDrain 을 무조건 부르면
                // 집 맥이 회사 맥의 찌르기를 훔친다(위 realtimeMayConsumePokes 주석).
                guard realtimeMayConsumePokes else { continue }
                requestDrain()
            case .pushAccessToken(let token):
                realtime.transport?.pushAccessToken(token)
            case .scheduleTokenRefresh(let at):
                scheduleRealtimeTokenRefresh(at: at, now: now)
            case .refreshToken:
                startRealtimeTokenRefresh()
            case .sendHeartbeat:
                realtime.transport?.sendHeartbeat()
            }
        }
    }

    private func performRealtimeConnect(linkToken: String) {
        // 프로젝트 URL·anon 키는 **이 스토어의 서비스**에서 읽는다. SupabaseConfig 를 직접 부르면
        // 조립된 서비스와 소켓이 서로 다른 프로젝트를 볼 수 있고(테스트·스테이징), 그 어긋남은
        // "REST 는 되는데 소켓만 안 붙는다"라는 가장 진단하기 어려운 모양으로 나타난다.
        guard let transport = realtime.transport,
              let activeSession = session,
              let apiKey = service.anonKey
        else { return }
        // ★ 경합 2(토큰 갱신 ↔ 재연결) 차단: 백오프 타이머가 만료된 토큰을 들고 있는 동안 갱신이 끝났을 수
        //   있다. 링이 실어 보낸 토큰이 아니라 **지금 스토어에 있는 것**을 쓴다. 둘이 다르면 진단에 남긴다 —
        //   이 로그가 없으면 "왜 옛 토큰으로 붙었나"를 사후에 잴 방법이 없다.
        let token = activeSession.accessToken
        if token != linkToken {
            realtime.diagnostics.note("token-superseded", state: realtime.link.state, at: Date())
        }
        transport.connect(
            url: service.projectURL,
            apiKey: apiKey,
            accessToken: token,
            channel: RealtimeLinkConstants.pokeChannel(userID: activeSession.userID),
            // private = true 가 없으면 realtime.messages RLS 가 아예 상담되지 않는다.
            isPrivate: true
        )
    }

    private func scheduleRealtimeRetry(at date: Date, now: Date) {
        realtime.retryTask?.cancel()
        let delay = max(0, date.timeIntervalSince(now))
        realtime.retryTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.realtime.retryTask = nil
            self.realtimeApply(.backoffElapsed)
        }
    }

    private func scheduleRealtimeTokenRefresh(at date: Date, now: Date) {
        realtime.tokenRefreshTask?.cancel()
        let delay = max(0, date.timeIntervalSince(now))
        realtime.tokenRefreshTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.realtime.tokenRefreshTask = nil
            self.startRealtimeTokenRefresh()
        }
    }

    /// **알려진 한계**: withSessionRetry(REST) 가 먼저 갱신을 끝내면 소켓은 옛 토큰을 쥔 채로 남는다.
    /// 그 경우 서버가 채널을 끊고, 재연결이 `performRealtimeConnect` 에서 **지금 스토어에 있는** 토큰을
    /// 다시 읽으므로 스스로 낫는다(최악 지연 = 백오프 cap 30초). 여기서 REST 갱신에 훅을 거는 것도
    /// 가능하지만, 갱신 주체가 다시 둘로 보이게 되어 SessionRefreshCoordinator 의 계약을 흐린다.
    ///
    /// 선제/강제 토큰 갱신. **반드시 조정자를 지난다** — 여기서 service.refreshSession 을 직접 부르면
    /// withSessionRetry 와 refresh token 회전이 겹쳐 근무 중 강제 로그아웃이 난다.
    private func startRealtimeTokenRefresh() {
        guard let currentSession = session, currentSession.refreshToken != nil else { return }
        let generation = sessionGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let refreshed = try await self.sessionRefreshCoordinator.refresh(
                    generation: generation,
                    tokenProvider: { [weak self] in self?.session?.refreshToken },
                    refresh: { [service = self.service] token in
                        try await service.refreshSession(refreshToken: token)
                    },
                    apply: { [weak self] session in
                        guard let self, generation == self.sessionGeneration else { return }
                        self.session = session
                        self.persistSession(session)
                    }
                )
                guard generation == self.sessionGeneration else { return }
                self.realtimeApply(.tokenRefreshed(accessToken: refreshed.accessToken))
            } catch {
                guard generation == self.sessionGeneration else { return }
                // 취소는 실패가 아니다(뚜껑을 닫았거나 로그아웃 중이다).
                if case .cancelled = self.classifyAuthError(error) { return }
                let fatal = self.classifyAuthError(error) == .fatal
                self.realtimeApply(.tokenRefreshFailed(fatal: fatal))
            }
        }
    }

    private func startRealtimeTicker() {
        // 테스트 프로세스에서는 **벽시계 티커를 띄우지 않는다.** 테스트는 `realtimeTick(at:)` 을 직접 불러
        // 시각을 스스로 정한다. 두 시계가 겹치면 실측한 그대로 무너진다: 전체 스위트에서 테스트 하나가
        // 수백 초를 살고 메인 액터가 굶어, 뒤늦게 깨어난 티커가 "50초 무응답"으로 판정해 **테스트 도중에**
        // 구독을 끊는다 — 결함이 아니라 부하 때문에 빨개진다.
        // 프로덕션 비용은 0이다: 테스트에서는 LiveRealtimeTransport 가 애초에 nil 이라 여기까지 오지 않고,
        // 오는 경우는 Fake 를 주입한 테스트뿐이다. 판정은 이 저장소의 유일한 그 판정을 재사용한다.
        guard !CheckPanelVisibility.isRunningTests else { return }
        realtime.tickTask?.cancel()
        realtime.tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.realtimeTickIntervalSeconds), tolerance: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                self.realtimeTick()
            }
        }
    }

    /// 주기 점검 1회분. 루프와 분리한 이유는 테스트다(벽시계 5초를 기다리지 않고 직접 부른다).
    func realtimeTick(at now: Date = Date()) {
        realtimeApply(.tick, at: now)
        // 안전망: 재시도 타이머가 어떤 이유로든 사라졌는데(취소 경합·태스크 유실) 예약 시각이 지났으면
        // 여기서 한 번 민다. 이게 없으면 타이머 하나가 유실되는 순간 링이 영구 reconnecting 으로 굳는다 —
        // 폴백을 지운 구성에서 그것은 영구 침묵이다.
        if realtime.retryTask == nil, let retryAt = realtime.link.retryAt, now >= retryAt {
            realtimeApply(.backoffElapsed, at: now)
        }
        // 게이트에 막혀 건너뛴 따라잡기를 근무 시작 뒤 회수한다. **구독 전이는 다시 일어나지 않으므로**
        // 이 한 줄이 없으면 그 구간의 찌르기는 영구 소실이다(폴링은 구독 중이라 쉬고 있다).
        if realtimeState.isSubscribed, realtime.catchUpDeferred, realtimeMayConsumePokes,
           realtime.catchUpTask == nil {
            startCatchUp()
        }
    }

    // MARK: - 캐치업

    private func startCatchUp() {
        realtime.catchUpTask?.cancel()
        realtime.catchUpTask = Task { @MainActor [weak self] in
            await self?.catchUpAfterSubscribe()
            self?.realtime.catchUpTask = nil
        }
    }

    /// 구독 직후 1회 따라잡기.
    ///
    /// **이것은 폴백이 아니라 정확성이다.** 폴백이라면 "리얼타임이 실패했을 때 대신 도는 다른 길"이어야
    /// 하는데, 이 호출은 리얼타임이 **성공한 바로 그 순간에만** 발사된다 — 실패해 있는 동안에는 아예
    /// 돌지 않고 주기도 없다. 전이당 정확히 한 번이다.
    ///
    /// 왜 필요한가: 리얼타임 브로드캐스트에는 **재생(replay)이 없다.** 소켓이 닫혀 있던 2시간 동안 도착한
    /// 찌르기는 서버 어디에도 "배달할 것이 남았다"는 형태로 큐잉되지 않고 pokes 행에 consumed_at is null 로
    /// 조용히 앉아 있을 뿐이다. 그 행을 가져오는 수단은 take_pokes 하나뿐이라, 캐치업이 없으면
    /// 뚜껑 닫은 구간의 찌르기는 **영영 안 온다**(폴링을 재웠으므로 다른 길이 없다).
    ///
    /// 조인 성공을 사전조건으로 삼는 것 자체가 안전장치다: take_pokes 는 서버에서 원자 소비라 응답이
    /// 유실되면 그 찌르기는 영구 소실인데, 조인 성공은 "네트워크가 지금 실제로 살아 있다"의 실증이다.
    /// 그래서 didWake 직후가 아니라 subscribed 직후다.
    func catchUpAfterSubscribe() async {
        // 비근무 맥은 따라잡을 것이 원리적으로 없다(서버가 열린 세션을 요구한다). 여기서 경고 플래그를
        // 세우면 로그인만 해 둔 맥 전부가 상시 "놓친 찌르기를 못 받아왔어요"를 띄운다.
        guard realtimeMayConsumePokes else {
            // 지금은 돌릴 수 없다. **잊지 않는다** — 근무중이 되는 순간 tick 이 다시 부른다(위 catchUpDeferred 주석).
            realtime.catchUpDeferred = true
            realtimeCatchUpFailedAt = nil
            realtime.diagnostics.lastCatchUpAttempts = 0
            return
        }
        realtime.catchUpDeferred = false
        for attempt in 0..<Self.catchUpAttempts {
            realtime.diagnostics.lastCatchUpAttempts = attempt + 1
            let outcome = await drainReceivedPokes()
            if case .ok(let count) = outcome {
                realtime.diagnostics.lastCatchUpAt = Date()
                realtime.diagnostics.lastCatchUpCount = count
                realtime.diagnostics.lastCatchUpFailure = nil
                // **명시적으로 nil 로 되돌린다** — 낡은 경고가 눌러앉으면 사용자는 고쳐진 뒤에도 계속 본다.
                realtimeCatchUpFailedAt = nil
                return
            }
            if case .failed(let reason) = outcome {
                realtime.diagnostics.lastCatchUpFailure = reason
            }
            if attempt < Self.catchUpRetryDelays.count {
                try? await Task.sleep(for: .seconds(Self.catchUpRetryDelays[attempt]))
                if Task.isCancelled { return }
            }
        }
        realtime.diagnostics.lastCatchUpAt = Date()
        realtimeCatchUpFailedAt = Date()
    }

    // MARK: - 진단 문구

    /// 설정 창 한 줄. 값 사이 구분자는 ` · ` 하나로 고정한다(로그를 눈으로 자르는 사람이 있다).
    var realtimeDiagnosticsLine: String {
        let d = realtime.diagnostics
        var parts: [String] = [RealtimeDiagnostics.label(realtimeState)]
        if !d.transportAvailable { parts.append("전송자 없음") }
        parts.append("재연결 \(d.totalReconnects)회")
        if let at = d.lastCatchUpAt {
            parts.append("따라잡기 \(Self.realtimeDiagnosticsTime.string(from: at)) \(d.lastCatchUpCount)건")
        } else {
            parts.append("따라잡기 없음")
        }
        if realtimeCatchUpFailedAt != nil { parts.append("따라잡기 실패") }
        return parts.joined(separator: " · ")
    }

    nonisolated static let realtimeDiagnosticsTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func cause(of event: RealtimeEvent) -> String {
        switch event {
        case .signedIn: return "signedIn"
        case .signedOut: return "signedOut"
        case .willSleep: return "willSleep"
        case .didWake: return "didWake"
        case .backoffElapsed: return "backoffElapsed"
        case .tick: return "tick"
        case .tokenRefreshed: return "tokenRefreshed"
        case .tokenRefreshFailed(let fatal): return fatal ? "tokenRefreshFailed(fatal)" : "tokenRefreshFailed"
        case .workEnded: return "workEnded"
        case .transport(let t):
            switch t {
            case .opened: return "opened"
            case .joined: return "joined"
            case .joinRejected(let r): return "joinRejected(\(r))"
            case .broadcast(let e): return "broadcast(\(e))"
            case .heartbeatAck: return "heartbeatAck"
            case .heartbeatTimedOut: return "heartbeatTimedOut"
            case .closed(let code): return "closed(\(code.map(String.init) ?? "-"))"
            }
        }
    }
}
